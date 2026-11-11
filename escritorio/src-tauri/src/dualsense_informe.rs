// Informes del DualSense: leer el de entrada (botones, sticks, batería) y preparar el de la barra de luz.
// Sin nada del sistema: lo usan la app de escritorio (dualsense.rs) y el motor de la placa (components/motor).
use crate::modelo::{Boton, Estado};

pub struct Informe {
    pub estado: Estado,
    pub bluetooth: bool,
    /// (porcentaje, estado) si el informe la lleva
    pub bateria: Option<(Option<i32>, &'static str)>,
}

/// Informe de entrada del DualSense (empieza por su número). USB: 0x01 de 64 bytes.
/// Bluetooth: 0x31 de 78 bytes (los datos empiezan un byte después), o el 0x01 corto de 10 bytes.
pub fn analizar(r: &[u8]) -> Option<Informe> {
    match (r.first()?, r.len()) {
        (0x01, n) if n >= 64 => Some(completo(&r[1..], false)),
        (0x31, n) if n >= 78 => Some(completo(&r[2..], true)),
        (0x01, n) if n >= 10 => Some(corto(&r[1..])),
        _ => None,
    }
}

/// Datos comunes de USB y Bluetooth (sin el número de informe): x y rx ry z rz seq botones[4] … estado(52)
fn completo(d: &[u8], bluetooth: bool) -> Informe {
    let mut e = Estado { lx: d[0], ly: d[1], rx: d[2], ry: d[3], l2: d[4], r2: d[5], botones: 0 };
    e.botones = botones(d[7], d[8], d[9], e.l2, e.r2);
    if d[9] & 0x04 != 0 {
        e.botones |= Boton::Silenciar.bit();
    }
    Informe { estado: e, bluetooth, bateria: Some(bateria(d[52])) }
}

/// El 0x01 corto de Bluetooth: x y rx ry botones[3] z rz (sin silenciar ni batería)
fn corto(d: &[u8]) -> Informe {
    let mut e = Estado { lx: d[0], ly: d[1], rx: d[2], ry: d[3], l2: d[7], r2: d[8], botones: 0 };
    e.botones = botones(d[4], d[5], d[6], e.l2, e.r2);
    Informe { estado: e, bluetooth: true, bateria: None }
}

fn botones(b0: u8, b1: u8, b2: u8, l2: u8, r2: u8) -> u32 {
    let mut b = 0u32;
    let mut poner = |boton: Boton, si: bool| {
        if si {
            b |= boton.bit();
        }
    };
    poner(Boton::Cuadrado, b0 & 0x10 != 0);
    poner(Boton::X, b0 & 0x20 != 0);
    poner(Boton::Circulo, b0 & 0x40 != 0);
    poner(Boton::Triangulo, b0 & 0x80 != 0);
    poner(Boton::L1, b1 & 0x01 != 0);
    poner(Boton::R1, b1 & 0x02 != 0);
    // Como en la app de Mac: L2 y R2 cuentan como pulsados en cuanto se mueve el gatillo
    poner(Boton::L2, b1 & 0x04 != 0 || l2 > 0);
    poner(Boton::R2, b1 & 0x08 != 0 || r2 > 0);
    poner(Boton::Share, b1 & 0x10 != 0);
    poner(Boton::Options, b1 & 0x20 != 0);
    poner(Boton::L3, b1 & 0x40 != 0);
    poner(Boton::R3, b1 & 0x80 != 0);
    poner(Boton::Ps, b2 & 0x01 != 0);
    poner(Boton::Tactil, b2 & 0x02 != 0);
    // Cruceta: 0 = arriba y en sentido horario hasta 7; 8 = suelta
    let (ar, de, ab, iz) = match b0 & 0x0F {
        0 => (true, false, false, false),
        1 => (true, true, false, false),
        2 => (false, true, false, false),
        3 => (false, true, true, false),
        4 => (false, false, true, false),
        5 => (false, false, true, true),
        6 => (false, false, false, true),
        7 => (true, false, false, true),
        _ => (false, false, false, false),
    };
    poner(Boton::Arriba, ar);
    poner(Boton::Derecha, de);
    poner(Boton::Abajo, ab);
    poner(Boton::Izquierda, iz);
    b
}

/// Byte de estado: nivel en el nibble bajo (0-10) y carga en el alto (0 descargando, 1 cargando, 2 llena)
fn bateria(s: u8) -> (Option<i32>, &'static str) {
    let nivel = ((s & 0x0F) as i32 * 10 + 5).min(100);
    match s >> 4 {
        0 => (Some(nivel), "descargando"),
        1 => (Some(nivel), "cargando"),
        2 => (Some(100), "llena"),
        _ => (None, "desconocido"),
    }
}

/// Informe de salida que solo cambia la barra de luz (no toca la vibración ni los gatillos).
/// USB: 0x02 de 48 bytes. Bluetooth: 0x31 de 78 bytes con la etiqueta 0x10 y su CRC32 al final.
/// `preparar` libera la barra de la animación de encendido (hace falta la primera vez).
pub fn informe_luz(rgb: (u8, u8, u8), bluetooth: bool, secuencia: u8, preparar: bool) -> Vec<u8> {
    let mut comun = [0u8; 47];
    comun[1] = 0x04; // valid_flag1: control de la barra de luz
    if preparar {
        comun[38] = 0x02; // valid_flag2: configuración de la barra
        comun[41] = 0x02; // lightbar_setup: apagar la animación de encendido
    }
    comun[44] = rgb.0;
    comun[45] = rgb.1;
    comun[46] = rgb.2;
    if !bluetooth {
        let mut r = vec![0x02];
        r.extend_from_slice(&comun);
        return r;
    }
    let mut r = vec![0u8; 78];
    r[0] = 0x31;
    r[1] = secuencia << 4;
    r[2] = 0x10;
    r[3..50].copy_from_slice(&comun);
    let mut datos = vec![0xA2];
    datos.extend_from_slice(&r[..74]);
    r[74..78].copy_from_slice(&crc32(&datos).to_le_bytes());
    r
}

pub fn crc32(datos: &[u8]) -> u32 {
    let mut crc = 0xFFFF_FFFFu32;
    for &b in datos {
        crc ^= b as u32;
        for _ in 0..8 {
            crc = if crc & 1 != 0 { (crc >> 1) ^ 0xEDB8_8320 } else { crc >> 1 };
        }
    }
    !crc
}

