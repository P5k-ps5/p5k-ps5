// Lee el DualSense por HID (USB o Bluetooth), en su propio hilo, y se reconecta solo.
// Hace lo mismo que la clase DualSense de app/Motor.swift, pero sin el sistema de mandos de macOS:
// botones, cruceta, sticks, gatillos, el botón de silenciar, la batería, el ritmo real y la barra de luz.
#![allow(dead_code)]

use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Mutex};
use std::thread;
use std::time::{Duration, Instant};

use crate::modelo::Estado;

const VID_SONY: u16 = 0x054C;
const PID_DUALSENSE: u16 = 0x0CE6;
const PID_DUALSENSE_EDGE: u16 = 0x0DF2;

/// Si deja de mandar informes este tiempo, se da por apagado (encendido manda sin parar, aunque esté quieto)
const SIN_INFORMES: Duration = Duration::from_secs(1);
const DURACION_DESTELLO: Duration = Duration::from_millis(700);
const REFRESCO_LUZ: Duration = Duration::from_secs(1);

pub struct InfoMando {
    pub nombre: Option<String>,
    pub conexion: Option<String>, // "USB" | "Bluetooth"
    pub hz: i32,
    pub hueco_ms: f64,
    pub bateria: Option<i32>,
    pub bateria_estado: String, // "descargando" | "cargando" | "llena" | "desconocido"
}

/// Ritmo real del mando: informes por segundo y el mayor hueco entre dos seguidos (como RitmoMando en Swift)
#[derive(Clone, Copy, Default)]
struct Ritmo {
    hz: i32,
    hueco_ms: f64,
    cuenta: i32,
    desde: Option<f64>,
    anterior: Option<f64>,
    hueco: f64,
}

impl Ritmo {
    fn informe(&mut self, t: f64) {
        let desde = *self.desde.get_or_insert(t);
        if let Some(a) = self.anterior {
            self.hueco = self.hueco.max(t - a);
        }
        self.anterior = Some(t);
        self.cuenta += 1;
        if t - desde >= 1.0 {
            self.hz = ((self.cuenta - 1) as f64 / (t - desde)).round() as i32;
            self.hueco_ms = self.hueco * 1000.0;
            self.cuenta = 1;
            self.hueco = 0.0;
            self.desde = Some(t);
        }
    }

    /// Si lleva más de un segundo sin informes, el mando no está mandando nada
    fn actual(&self, t: f64) -> (i32, f64) {
        match self.anterior {
            Some(a) if t - a <= 1.0 => (self.hz, self.hueco_ms),
            _ => (0, 0.0),
        }
    }
}

#[derive(Default)]
struct Compartido {
    estado: Option<Estado>,
    nombre: Option<String>,
    conexion: Option<String>,
    ritmo: Ritmo,
    bateria: Option<i32>,
    bateria_estado: String,
    /// Color del perfil y destello en curso (con su fin); `luz_cambiada` pide mandarla ya
    color: Option<(u8, u8, u8)>,
    destello: Option<((u8, u8, u8), Instant)>,
    luz_cambiada: bool,
}

pub struct Mando {
    compartido: Arc<Mutex<Compartido>>,
    parar: Arc<AtomicBool>,
    origen: Instant,
}

impl Mando {
    pub fn arrancar() -> Mando {
        let compartido = Arc::new(Mutex::new(Compartido { bateria_estado: "desconocido".into(), ..Default::default() }));
        let parar = Arc::new(AtomicBool::new(false));
        let origen = Instant::now();
        let (c, p) = (compartido.clone(), parar.clone());
        thread::Builder::new()
            .name("dualsense".into())
            .spawn(move || bucle(c, p, origen))
            .expect("no se pudo arrancar el hilo del DualSense");
        Mando { compartido, parar, origen }
    }

    /// El último estado leído (None si no hay mando). Se puede llamar a 1000 Hz: cerrojo cortísimo.
    pub fn estado(&self) -> Option<Estado> {
        self.compartido.lock().map(|c| c.estado).unwrap_or(None)
    }

    pub fn info(&self) -> InfoMando {
        let t = self.origen.elapsed().as_secs_f64();
        let c = self.compartido.lock().unwrap();
        let (hz, hueco_ms) = c.ritmo.actual(t);
        InfoMando {
            nombre: c.nombre.clone(),
            conexion: if hz > 0 { c.conexion.clone() } else { None },
            hz,
            hueco_ms,
            bateria: c.bateria,
            bateria_estado: c.bateria_estado.clone(),
        }
    }

    /// Barra de luz con el color del perfil ("#RRGGBB")
    pub fn poner_color(&self, hex: &str) {
        let Some(rgb) = leer_hex(hex) else { return };
        let mut c = self.compartido.lock().unwrap();
        if c.color != Some(rgb) {
            c.color = Some(rgb);
            c.luz_cambiada = true;
        }
    }

    /// Destello corto (0,7 s) de este color y vuelta al del perfil (componentes de 0 a 1)
    pub fn destellar(&self, rgb: (f32, f32, f32)) {
        let a = |v: f32| (v.clamp(0.0, 1.0) * 255.0).round() as u8;
        let mut c = self.compartido.lock().unwrap();
        c.destello = Some(((a(rgb.0), a(rgb.1), a(rgb.2)), Instant::now() + DURACION_DESTELLO));
        c.luz_cambiada = true;
    }
}

impl Drop for Mando {
    fn drop(&mut self) {
        self.parar.store(true, Ordering::Relaxed);
    }
}

pub fn leer_hex(hex: &str) -> Option<(u8, u8, u8)> {
    let s = hex.trim().trim_start_matches('#');
    if s.len() != 6 {
        return None;
    }
    let v = u32::from_str_radix(s, 16).ok()?;
    Some(((v >> 16) as u8, (v >> 8) as u8, v as u8))
}

// MARK: - Hilo de lectura

fn bucle(c: Arc<Mutex<Compartido>>, parar: Arc<AtomicBool>, origen: Instant) {
    let mut api = None;
    while !parar.load(Ordering::Relaxed) {
        if api.is_none() {
            api = hidapi::HidApi::new().ok();
        }
        if let Some(api) = api.as_mut() {
            let _ = api.refresh_devices();
            if let Some((dispositivo, nombre, bluetooth)) = abrir(api) {
                {
                    let mut g = c.lock().unwrap();
                    g.nombre = Some(nombre);
                    g.conexion = bluetooth.map(|b| if b { "Bluetooth" } else { "USB" }.to_string());
                    g.luz_cambiada = true; // al reconectar se vuelve a poner el color del perfil
                }
                leer(&dispositivo, bluetooth, &c, &parar, origen);
                let mut g = c.lock().unwrap();
                g.estado = None;
                g.nombre = None;
                g.conexion = None;
                g.bateria = None;
                g.bateria_estado = "desconocido".into();
            }
        }
        thread::sleep(Duration::from_millis(1000));
    }
}

/// Busca un DualSense (no el ESP32, que también se presenta como mando de Sony) y lo abre.
/// Devuelve el dispositivo, su nombre y si va por Bluetooth (None si el sistema no lo dice).
fn abrir(api: &hidapi::HidApi) -> Option<(hidapi::HidDevice, String, Option<bool>)> {
    let mut candidatos: Vec<&hidapi::DeviceInfo> = api
        .device_list()
        .filter(|d| d.vendor_id() == VID_SONY && (d.product_id() == PID_DUALSENSE || d.product_id() == PID_DUALSENSE_EDGE))
        .collect();
    // Primero la interfaz de mando (página 1, uso 5), si el sistema la distingue
    candidatos.sort_by_key(|d| !(d.usage_page() == 1 && d.usage() == 5));
    for d in candidatos {
        let Ok(dispositivo) = d.open_device(api) else { continue };
        let bluetooth = match d.bus_type() {
            hidapi::BusType::Bluetooth => Some(true),
            hidapi::BusType::Usb => Some(false),
            _ => None,
        };
        // Por Bluetooth el mando manda un informe corto hasta que alguien lee la calibración (característica 0x05):
        // entonces pasa al completo (0x31), con el botón de silenciar y la batería. Por USB no hace falta.
        if bluetooth != Some(false) {
            let mut calibracion = [0u8; 41];
            calibracion[0] = 0x05;
            let _ = dispositivo.get_feature_report(&mut calibracion);
        }
        let nombre = d.product_string().filter(|s| !s.is_empty()).unwrap_or("DualSense").to_string();
        return Some((dispositivo, nombre, bluetooth));
    }
    None
}

fn leer(d: &hidapi::HidDevice, mut bluetooth: Option<bool>, c: &Arc<Mutex<Compartido>>, parar: &AtomicBool, origen: Instant) {
    let mut buf = [0u8; 128];
    let mut ultimo = Instant::now();
    let mut luz_enviada: Option<Instant> = None;
    let mut secuencia: u8 = 0;
    let mut luz_preparada = false;
    while !parar.load(Ordering::Relaxed) {
        match d.read_timeout(&mut buf, 20) {
            Err(_) => return, // desenchufado o apagado
            Ok(0) => {}
            Ok(n) => {
                if let Some(informe) = analizar(&buf[..n]) {
                    ultimo = Instant::now();
                    if bluetooth.is_none() {
                        bluetooth = Some(informe.bluetooth);
                    }
                    let t = origen.elapsed().as_secs_f64();
                    let mut g = c.lock().unwrap();
                    g.ritmo.informe(t);
                    g.estado = Some(informe.estado);
                    if g.conexion.is_none() {
                        g.conexion = bluetooth.map(|b| if b { "Bluetooth" } else { "USB" }.to_string());
                    }
                    if let Some((pct, estado)) = informe.bateria {
                        g.bateria = pct;
                        g.bateria_estado = estado.to_string();
                    }
                }
            }
        }
        if ultimo.elapsed() > SIN_INFORMES {
            return;
        }
        // Barra de luz: al cambiar, al acabar un destello y una vez por segundo (por si otra app la pisa)
        let pendiente = {
            let mut g = c.lock().unwrap();
            let ahora = Instant::now();
            let mut toca = g.luz_cambiada;
            if let Some((_, fin)) = g.destello {
                if ahora >= fin {
                    g.destello = None;
                    toca = true;
                }
            }
            if g.color.is_some() && luz_enviada.is_some_and(|t| t.elapsed() >= REFRESCO_LUZ) {
                toca = true;
            }
            g.luz_cambiada = false;
            if toca { g.destello.map(|(rgb, _)| rgb).or(g.color) } else { None }
        };
        if let Some(rgb) = pendiente {
            let informe = informe_luz(rgb, bluetooth.unwrap_or(false), secuencia, !luz_preparada);
            secuencia = secuencia.wrapping_add(1) & 0x0F;
            if d.write(&informe).is_ok() {
                luz_preparada = true;
            }
            luz_enviada = Some(Instant::now());
        }
    }
}

pub use crate::dualsense_informe::*;

#[cfg(test)]
mod pruebas {
    use super::*;
    use crate::modelo::Boton;

    fn usb(b0: u8, b1: u8, b2: u8, l2: u8, r2: u8, estado: u8) -> Vec<u8> {
        let mut r = vec![0u8; 64];
        r[0] = 0x01;
        r[1] = 10; r[2] = 20; r[3] = 200; r[4] = 250;
        r[5] = l2; r[6] = r2;
        r[8] = b0; r[9] = b1; r[10] = b2;
        r[53] = estado;
        r
    }

    #[test]
    fn informe_usb() {
        let i = analizar(&usb(0x20 | 0x02, 0x01 | 0x80, 0x01 | 0x04, 0, 0, 0x16)).unwrap();
        let e = i.estado;
        assert!(!i.bluetooth);
        assert_eq!((e.lx, e.ly, e.rx, e.ry), (10, 20, 200, 250));
        for b in [Boton::X, Boton::Derecha, Boton::L1, Boton::R3, Boton::Ps, Boton::Silenciar] {
            assert!(e.pulsado(b), "{b:?} debería estar pulsado");
        }
        assert!(!e.pulsado(Boton::Arriba) && !e.pulsado(Boton::L2) && !e.pulsado(Boton::Tactil));
        assert_eq!(i.bateria, Some((Some(65), "cargando")));
    }

    #[test]
    fn cruceta_suelta_y_gatillos_analogicos() {
        let e = analizar(&usb(0x08, 0, 0, 3, 0, 0x2A)).unwrap().estado;
        assert!(!e.pulsado(Boton::Arriba) && !e.pulsado(Boton::Abajo));
        assert!(e.pulsado(Boton::L2) && !e.pulsado(Boton::R2), "L2 cuenta en cuanto se mueve el gatillo");
        assert_eq!(e.l2, 3);
        let e = analizar(&usb(0x07, 0, 0, 0, 0, 0)).unwrap().estado;
        assert!(e.pulsado(Boton::Arriba) && e.pulsado(Boton::Izquierda));
    }

    #[test]
    fn informe_bluetooth_completo_y_corto() {
        let mut r = vec![0u8; 78];
        r[0] = 0x31;
        r[2] = 1; r[3] = 2; r[4] = 3; r[5] = 4; r[6] = 50; r[7] = 60;
        r[9] = 0x10; r[11] = 0x06; r[54] = 0x23;
        let i = analizar(&r).unwrap();
        assert!(i.bluetooth);
        assert_eq!((i.estado.lx, i.estado.l2, i.estado.r2), (1, 50, 60));
        assert!(i.estado.pulsado(Boton::Cuadrado) && i.estado.pulsado(Boton::Tactil) && i.estado.pulsado(Boton::Silenciar));
        assert_eq!(i.bateria, Some((Some(100), "llena")));
        let c = [0x01, 128, 128, 0, 255, 0x40, 0x02, 0x00, 0, 200];
        let i = analizar(&c).unwrap();
        assert!(i.bluetooth && i.estado.pulsado(Boton::Circulo) && i.estado.pulsado(Boton::R1) && i.estado.pulsado(Boton::R2));
        assert_eq!(i.bateria, None);
    }

    #[test]
    fn luz_usb_y_bluetooth_con_crc() {
        let u = informe_luz((1, 2, 3), false, 0, false);
        assert_eq!((u.len(), u[0], u[2], u[45], u[46], u[47]), (48, 0x02, 0x04, 1, 2, 3));
        let b = informe_luz((1, 2, 3), true, 5, true);
        assert_eq!((b.len(), b[0], b[1], b[2], b[47], b[48], b[49]), (78, 0x31, 0x50, 0x10, 1, 2, 3));
        // CRC32 conocido: «123456789» da 0xCBF43926
        assert_eq!(crc32(b"123456789"), 0xCBF4_3926);
        let mut datos = vec![0xA2];
        datos.extend_from_slice(&b[..74]);
        assert_eq!(u32::from_le_bytes([b[74], b[75], b[76], b[77]]), crc32(&datos));
    }

    #[test]
    fn hex() {
        assert_eq!(leer_hex("#0050FF"), Some((0, 0x50, 0xFF)));
        assert_eq!(leer_hex("nope"), None);
    }

    /// Con un DualSense de verdad conectado: `cargo test --lib mando_real -- --ignored --nocapture`.
    /// Solo lee (no cambia la luz).
    #[test]
    #[ignore]
    fn mando_real() {
        let m = Mando::arrancar();
        for _ in 0..12 {
            thread::sleep(Duration::from_millis(500));
            let i = m.info();
            println!("{:?} {:?} {} Hz hueco {:.0} ms batería {:?} {} -> {:?}",
                     i.nombre, i.conexion, i.hz, i.hueco_ms, i.bateria, i.bateria_estado, m.estado());
        }
    }
}
