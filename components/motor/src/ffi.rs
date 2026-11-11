// Lo que el firmware en C le pide al motor (declarado en include/motor.h). Los textos que devuelve el motor
// son cadenas de C reservadas aquí: el firmware las devuelve con motor_liberar().
use std::ffi::{c_char, CStr, CString};
use std::path::Path;
use std::sync::OnceLock;

use serde_json::Value;

use crate::modelo::Estado;
use crate::nucleo::{InfoMando, Nucleo};

static NUCLEO: OnceLock<Nucleo> = OnceLock::new();

/// Estado del mando para C (mismo orden de botones que modelo::Boton)
#[repr(C)]
#[derive(Clone, Copy)]
pub struct MotorEstado {
    pub botones: u32,
    pub lx: u8,
    pub ly: u8,
    pub rx: u8,
    pub ry: u8,
    pub l2: u8,
    pub r2: u8,
}

impl From<MotorEstado> for Estado {
    fn from(e: MotorEstado) -> Estado {
        Estado { botones: e.botones, lx: e.lx, ly: e.ly, rx: e.rx, ry: e.ry, l2: e.l2, r2: e.r2 }
    }
}

impl From<Estado> for MotorEstado {
    fn from(e: Estado) -> MotorEstado {
        MotorEstado { botones: e.botones, lx: e.lx, ly: e.ly, rx: e.rx, ry: e.ry, l2: e.l2, r2: e.r2 }
    }
}

fn texto(s: String) -> *mut c_char {
    CString::new(s).map(|c| c.into_raw()).unwrap_or(std::ptr::null_mut())
}

fn leer(p: *const c_char) -> Option<String> {
    if p.is_null() {
        return None;
    }
    unsafe { CStr::from_ptr(p) }.to_str().ok().map(|s| s.to_string())
}

#[no_mangle]
pub extern "C" fn motor_iniciar(carpeta: *const c_char) {
    let carpeta = leer(carpeta).unwrap_or_else(|| ".".into());
    let _ = NUCLEO.set(Nucleo::arrancar(Path::new(&carpeta)));
}

/// Una vuelta del motor (cada milisegundo). entrada NULL = no hay mando real. t_us: tiempo en microsegundos.
#[no_mangle]
pub extern "C" fn motor_vuelta(entrada: *const MotorEstado, t_us: i64) -> MotorEstado {
    let Some(n) = NUCLEO.get() else { return Estado::default().into() };
    let e = if entrada.is_null() { None } else { Some(Estado::from(unsafe { *entrada })) };
    n.vuelta(e, t_us as f64 / 1e6).into()
}

#[no_mangle]
pub extern "C" fn motor_lento() {
    if let Some(n) = NUCLEO.get() {
        n.lento();
    }
}

/// bateria < 0: no se sabe. estado_bateria: 0 descargando, 1 cargando, 2 llena, otro desconocido.
#[no_mangle]
pub extern "C" fn motor_poner_mando(conectado: bool, hz: i32, hueco_ms: f32, bateria: i32, estado_bateria: u8, envios: i32) {
    if let Some(n) = NUCLEO.get() {
        n.poner_mando(InfoMando {
            conectado,
            hz,
            hueco_ms: hueco_ms as f64,
            bateria: (bateria >= 0).then_some(bateria),
            bateria_estado: match estado_bateria {
                0 => "descargando", 1 => "cargando", 2 => "llena", _ => "desconocido",
            }.into(),
            envios,
        });
    }
}

/// Lee un informe de entrada del DualSense (con su número delante), como la app de escritorio.
/// Devuelve false si no es un informe de mando. bateria: -1 si no la trae.
#[no_mangle]
pub extern "C" fn motor_leer_dualsense(r: *const u8, largo: usize, salida: *mut MotorEstado,
                                       bateria: *mut i32, estado_bateria: *mut u8) -> bool {
    if r.is_null() || salida.is_null() {
        return false;
    }
    let datos = unsafe { std::slice::from_raw_parts(r, largo) };
    let Some(i) = crate::dualsense_informe::analizar(datos) else { return false };
    unsafe {
        *salida = i.estado.into();
        if !bateria.is_null() && !estado_bateria.is_null() {
            let (nivel, estado) = i.bateria.unwrap_or((None, "desconocido"));
            *bateria = nivel.unwrap_or(-1);
            *estado_bateria = match estado { "descargando" => 0, "cargando" => 1, "llena" => 2, _ => 3 };
        }
    }
    true
}

/// Informe de salida USB del DualSense que solo cambia la barra de luz (0x02, 48 bytes) en `destino`.
/// Devuelve los bytes escritos (0 si no cabe).
#[no_mangle]
pub extern "C" fn motor_informe_luz(r: u8, g: u8, b: u8, preparar: bool, destino: *mut u8, cabe: usize) -> usize {
    let inf = crate::dualsense_informe::informe_luz((r, g, b), false, 0, preparar);
    if destino.is_null() || inf.len() > cabe {
        return 0;
    }
    unsafe { std::ptr::copy_nonoverlapping(inf.as_ptr(), destino, inf.len()) };
    inf.len()
}

/// Si hay que destellar la luz del mando (anti-recoil o ayuda encendidos/apagados), deja el color en rgb[3]
#[no_mangle]
pub extern "C" fn motor_destello(rgb: *mut u8) -> bool {
    let Some(n) = NUCLEO.get() else { return false };
    match n.tomar_destello() {
        Some((r, g, b)) if !rgb.is_null() => {
            unsafe {
                *rgb = r;
                *rgb.add(1) = g;
                *rgb.add(2) = b;
            }
            true
        }
        _ => false,
    }
}

/// Color del perfil activo en rgb[3]. false si no se entiende el color.
#[no_mangle]
pub extern "C" fn motor_color(rgb: *mut u8) -> bool {
    let Some(n) = NUCLEO.get() else { return false };
    let c = n.color();
    let hex = c.trim_start_matches('#');
    if rgb.is_null() || hex.len() != 6 {
        return false;
    }
    let Ok(v) = u32::from_str_radix(hex, 16) else { return false };
    unsafe {
        *rgb = (v >> 16) as u8;
        *rgb.add(1) = (v >> 8) as u8;
        *rgb.add(2) = v as u8;
    }
    true
}

#[no_mangle]
pub extern "C" fn motor_instantanea() -> *mut c_char {
    texto(NUCLEO.get().map(|n| n.instantanea()).unwrap_or_else(|| "{}".into()))
}

#[no_mangle]
pub extern "C" fn motor_perfil() -> *mut c_char {
    texto(NUCLEO.get().map(|n| n.perfil_json()).unwrap_or_else(|| "{}".into()))
}

#[no_mangle]
pub extern "C" fn motor_medidor() -> *mut c_char {
    texto(NUCLEO.get().map(|n| n.medidor_json()).unwrap_or_else(|| "{}".into()))
}

/// Una acción de la página (el cuerpo de POST /api). Devuelve el JSON de respuesta.
#[no_mangle]
pub extern "C" fn motor_aplicar(json: *const c_char) -> *mut c_char {
    let Some(n) = NUCLEO.get() else { return texto(r#"{"ok":false,"error":"el motor no ha arrancado"}"#.into()) };
    let accion: Option<Value> = leer(json).and_then(|s| serde_json::from_str(&s).ok()).filter(|v: &Value| v.is_object());
    match accion {
        Some(a) => texto(n.aplicar(&a).to_string()),
        None => texto(r#"{"ok":false,"error":"petición no válida"}"#.into()),
    }
}

#[no_mangle]
pub extern "C" fn motor_clave() -> *mut c_char {
    texto(NUCLEO.get().map(|n| n.clave()).unwrap_or_default())
}

#[no_mangle]
pub extern "C" fn motor_revision() -> *mut c_char {
    texto(NUCLEO.get().map(|n| n.revision()).unwrap_or_default())
}

/// Código QR (SVG) de un texto, el mismo que pinta el escritorio en «Móvil»
#[no_mangle]
pub extern "C" fn motor_qr_svg(t: *const c_char) -> *mut c_char {
    match leer(t).and_then(|t| crate::qr::svg(&t)) {
        Some(s) => texto(s),
        None => std::ptr::null_mut(),
    }
}

/// Mide cuánto tarda el procesador en esta placa: `vueltas` con el perfil activo, anti-recoil y ayuda
/// encendidos y disparando mientras se mueve el stick. Devuelve el tiempo medio (µs) y deja el peor en `peor_us`.
#[no_mangle]
pub extern "C" fn motor_medir(vueltas: u32, peor_us: *mut f32) -> f32 {
    let Some(n) = NUCLEO.get() else { return -1.0 };
    let perfil = n.almacen.lock().unwrap().activo().clone();
    let mut p = crate::procesador::Procesador::new();
    p.alternar_anti_recoil();
    p.alternar_ayuda();
    let mut e = Estado::default();
    let (mut total, mut peor) = (0.0f64, 0.0f64);
    let inicio = std::time::Instant::now();
    for i in 0..vueltas {
        e.botones = crate::modelo::Boton::R2.bit() | crate::modelo::Boton::L2.bit();
        e.r2 = 255;
        e.l2 = 255;
        e.rx = (128.0 + 60.0 * (i as f64 * 0.01).sin()) as u8;
        e.ry = (128.0 + 60.0 * (i as f64 * 0.013).cos()) as u8;
        let t0 = std::time::Instant::now();
        std::hint::black_box(p.procesar(&e, &perfil, i as f64 * 0.001));
        let d = t0.elapsed().as_secs_f64() * 1e6;
        total += d;
        peor = peor.max(d);
    }
    let _ = inicio;
    if !peor_us.is_null() {
        unsafe { *peor_us = peor as f32 };
    }
    (total / vueltas.max(1) as f64) as f32
}

/// Los ajustes que se sincronizan con las apps (JSON compacto)
#[no_mangle]
pub extern "C" fn motor_ajustes() -> *mut c_char {
    texto(NUCLEO.get().map(|n| n.ajustes_json()).unwrap_or_else(|| "{}".into()))
}

/// Revisión de unos ajustes (la de motor_ajustes, para comparar con la que guardó la app)
#[no_mangle]
pub extern "C" fn motor_revision_ajustes(json: *const c_char) -> *mut c_char {
    texto(Nucleo::revision_ajustes(&leer(json).unwrap_or_default()))
}

/// Pone los ajustes que manda una app. Devuelve «OK <revisión>» o «ERROR <motivo>».
#[no_mangle]
pub extern "C" fn motor_poner_ajustes(json: *const c_char) -> *mut c_char {
    let Some(n) = NUCLEO.get() else { return texto("ERROR el motor no ha arrancado".into()) };
    texto(match n.poner_ajustes(&leer(json).unwrap_or_default()) {
        Ok(rev) => format!("OK {rev}"),
        Err(e) => format!("ERROR {}", e.replace(['\n', '\r'], " ")),
    })
}

#[no_mangle]
pub extern "C" fn motor_liberar(s: *mut c_char) {
    if !s.is_null() {
        unsafe { drop(CString::from_raw(s)) };
    }
}
