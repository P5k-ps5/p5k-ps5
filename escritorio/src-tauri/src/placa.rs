// Todo lo que toca la placa: listar los puertos, reconocer un ESP32-S3 y grabarle el firmware.
use std::thread::sleep;
use std::time::{Duration, Instant};

use espflash::connection::{Connection, ResetAfterOperation, ResetBeforeOperation};
use espflash::flasher::Flasher;
use espflash::target::{Chip, ProgressCallbacks};
use serde::Serialize;
use serialport::{SerialPortType, UsbPortInfo};
use tauri::{AppHandle, Emitter};

const VID_ESPRESSIF: u16 = 0x303A;
pub const VID_SONY: u16 = 0x054C; // el firmware del puente se presenta como un mando de PS4
pub const PID_DS4: u16 = 0x09CC;

// Firmware compilado de `main/` (ver actualizar_firmware.sh). Direcciones de build/flasher_args.json.
const BOOTLOADER: &[u8] = include_bytes!("../firmware/bootloader.bin");
const PARTICIONES: &[u8] = include_bytes!("../firmware/particiones.bin");
const APLICACION: &[u8] = include_bytes!("../firmware/puente_mando.bin");
const VERSION: &str = env!("CARGO_PKG_VERSION");

fn piezas() -> [(u32, &'static str, &'static [u8]); 3] {
    [
        (0x0, "gestor de arranque", BOOTLOADER),
        (0x8000, "tabla de particiones", PARTICIONES),
        (0x10000, "firmware del puente", APLICACION),
    ]
}

#[derive(Serialize, Clone)]
pub struct Puerto {
    pub nombre: String,
    pub vid: u16,
    pub pid: u16,
    pub producto: String,
    /// "esp32s3" (USB nativo), "puente-serie" (chip USB-serie del COM), "firmware" (ya instalado) u "otro".
    pub tipo: String,
    pub descripcion: String,
}

#[derive(Serialize)]
pub struct InfoFirmware {
    pub version: String,
    pub bytes: usize,
}

#[derive(Serialize)]
pub struct Resultado {
    pub chip: String,
    pub bytes: usize,
    /// true si después de grabar la placa ha vuelto a aparecer como el mando del puente.
    pub verificado: bool,
}

#[derive(Serialize, Clone)]
struct Avance {
    etapa: String,
    mensaje: String,
    porcentaje: f32,
}

pub fn info_firmware() -> InfoFirmware {
    InfoFirmware {
        version: VERSION.to_string(),
        bytes: piezas().iter().map(|p| p.2.len()).sum(),
    }
}

fn clasificar(vid: u16, pid: u16) -> (&'static str, &'static str) {
    match (vid, pid) {
        (VID_SONY, PID_DS4) => ("firmware", "p5k-ps5 ya instalado"),
        (VID_ESPRESSIF, _) => ("esp32s3", "ESP32-S3 (USB nativo)"),
        (0x10C4, _) => ("puente-serie", "Puerto COM de la placa (CP210x)"),
        (0x1A86, _) => ("puente-serie", "Puerto COM de la placa (CH340/CH343)"),
        (0x0403, _) => ("puente-serie", "Puerto COM de la placa (FTDI)"),
        _ => ("otro", "Dispositivo USB"),
    }
}

fn orden(tipo: &str) -> u8 {
    match tipo {
        "esp32s3" => 0,
        "firmware" => 1,
        "puente-serie" => 2,
        _ => 3,
    }
}

pub fn listar() -> Vec<Puerto> {
    let mut lista: Vec<Puerto> = serialport::available_ports()
        .unwrap_or_default()
        .into_iter()
        // En macOS cada puerto sale como tty.* y cu.*; para abrir hay que usar cu.*
        .filter(|p| !p.port_name.contains("/dev/tty."))
        .filter_map(|p| match p.port_type {
            SerialPortType::UsbPort(u) => {
                let (tipo, descripcion) = clasificar(u.vid, u.pid);
                Some(Puerto {
                    nombre: p.port_name,
                    vid: u.vid,
                    pid: u.pid,
                    producto: u.product.unwrap_or_default(),
                    tipo: tipo.to_string(),
                    descripcion: descripcion.to_string(),
                })
            }
            _ => None,
        })
        .collect();
    lista.sort_by_key(|p| orden(&p.tipo));
    lista
}

fn info_usb(nombre: &str) -> Option<UsbPortInfo> {
    serialport::available_ports()
        .ok()?
        .into_iter()
        .find(|p| p.port_name == nombre)
        .and_then(|p| match p.port_type {
            SerialPortType::UsbPort(u) => Some(u),
            _ => None,
        })
}

fn avisar(app: &AppHandle, etapa: &str, mensaje: &str, porcentaje: f32) {
    let _ = app.emit(
        "instalacion",
        Avance { etapa: etapa.into(), mensaje: mensaje.into(), porcentaje },
    );
}

/// Espera a que aparezca un puerto que cumpla la condición.
fn esperar_puerto(segundos: u64, vale: impl Fn(&Puerto) -> bool) -> Option<Puerto> {
    let limite = Instant::now() + Duration::from_secs(segundos);
    while Instant::now() < limite {
        if let Some(p) = listar().into_iter().find(|p| vale(p)) {
            return Some(p);
        }
        sleep(Duration::from_millis(250));
    }
    None
}

/// Si la placa ya lleva este firmware, se le pide que reinicie en modo grabación (como BOOT + RST).
fn pedir_modo_grabacion(puerto: &Puerto) -> Result<Puerto, String> {
    let mut serie = serialport::new(&puerto.nombre, 115_200)
        .timeout(Duration::from_millis(500))
        .open()
        .map_err(|e| format!("No he podido abrir {}: {e}", puerto.nombre))?;
    serie
        .write_all(b"grabar\n")
        .map_err(|e| format!("No he podido hablar con la placa: {e}"))?;
    drop(serie);
    sleep(Duration::from_millis(1200));
    esperar_puerto(12, |p| p.vid == VID_ESPRESSIF).ok_or_else(|| {
        "La placa no ha entrado en modo grabación. Mantén pulsado BOOT, pulsa RST una vez, suelta BOOT y vuelve a intentarlo."
            .to_string()
    })
}

fn explicar(error: &espflash::Error) -> String {
    let texto = format!("{error}");
    let bajo = texto.to_lowercase();
    if bajo.contains("connect") || bajo.contains("timeout") || bajo.contains("sync") {
        "No consigo hablar con la placa. Prueba así: mantén pulsado el botón BOOT, pulsa una vez RST, suelta BOOT y pulsa «Instalar» otra vez. Si tu placa tiene dos puertos USB, usa el que pone COM o UART; si no, usa el USB nativo."
            .to_string()
    } else if bajo.contains("permission") || bajo.contains("access") || bajo.contains("busy") {
        "El puerto está ocupado o no tengo permiso. Cierra otros programas que usen la placa (monitor serie, Arduino IDE, otra copia de esta app) y reinténtalo."
            .to_string()
    } else {
        format!("Ha fallado la grabación: {texto}")
    }
}

struct Progreso<'a> {
    app: &'a AppHandle,
    pieza: &'static str,
    ya_escrito: usize,
    total: usize,
    pieza_total: usize,
}

impl Progreso<'_> {
    fn emitir(&self, actual: usize, mensaje: String) {
        let hecho = (self.ya_escrito + actual.min(self.pieza_total)) as f32;
        // 10 % para conectar, 85 % para grabar y el resto para comprobar
        let porcentaje = 10.0 + 85.0 * hecho / self.total as f32;
        avisar(self.app, "grabando", &mensaje, porcentaje);
    }
}

impl ProgressCallbacks for Progreso<'_> {
    fn init(&mut self, _addr: u32, total: usize) {
        self.pieza_total = total;
        self.emitir(0, format!("Grabando {}…", self.pieza));
    }
    fn update(&mut self, actual: usize) {
        self.emitir(actual, format!("Grabando {}…", self.pieza));
    }
    fn verifying(&mut self) {
        self.emitir(self.pieza_total, format!("Comprobando {}…", self.pieza));
    }
    fn finish(&mut self, _saltado: bool) {}
}

pub fn instalar(app: &AppHandle, nombre: &str) -> Result<Resultado, String> {
    avisar(app, "preparando", "Buscando la placa…", 2.0);
    let mut puerto = listar()
        .into_iter()
        .find(|p| p.nombre == nombre)
        .ok_or("La placa ya no está conectada. Revisa el cable y vuelve a intentarlo.")?;

    if puerto.tipo == "firmware" {
        avisar(app, "preparando", "Reiniciando la placa en modo grabación…", 4.0);
        puerto = pedir_modo_grabacion(&puerto)?;
    }
    let usb = info_usb(&puerto.nombre).ok_or("La placa ya no está conectada.")?;

    avisar(app, "conectando", "Conectando con la placa…", 8.0);
    let serie = serialport::new(&puerto.nombre, 115_200)
        .timeout(Duration::from_secs(3))
        .open_native()
        .map_err(|e| format!("No he podido abrir {}: {e}. ¿Lo está usando otro programa?", puerto.nombre))?;
    // Con el USB nativo la velocidad da igual; con un puente USB-serie se sube para ir más rápido.
    let por_usb_nativo = usb.vid == VID_ESPRESSIF;
    let despues = if por_usb_nativo { ResetAfterOperation::WatchdogReset } else { ResetAfterOperation::HardReset };
    let conexion = Connection::new(serie, usb, despues, ResetBeforeOperation::DefaultReset, 115_200);
    let mut flasher = Flasher::connect(conexion, true, true, false, None, Some(460_800))
        .map_err(|e| explicar(&e))?;

    let chip = flasher.chip();
    if chip != Chip::Esp32s3 {
        return Err(format!(
            "Esta placa es un {chip}, pero hace falta un ESP32-S3: solo el S3 puede hacerse pasar por un mando por USB."
        ));
    }

    let total: usize = piezas().iter().map(|p| p.2.len()).sum();
    let mut ya_escrito = 0;
    for (direccion, pieza, datos) in piezas() {
        let mut progreso = Progreso { app, pieza, ya_escrito, total, pieza_total: datos.len() };
        flasher
            .write_bin_to_flash(direccion, datos, &mut progreso)
            .map_err(|e| explicar(&e))?;
        ya_escrito += datos.len();
    }

    avisar(app, "reiniciando", "Reiniciando la placa…", 96.0);
    flasher
        .connection()
        .reset_after(true, chip)
        .map_err(|e| explicar(&e))?;
    drop(flasher);

    avisar(app, "comprobando", "Comprobando que arranca…", 97.0);
    // En modo «mac» la placa vuelve como mando de PS4 con un puerto serie; en modo «consola» no
    // enseña puerto, así que no verlo no es un fallo.
    let verificado = esperar_puerto(12, |p| p.vid == VID_SONY && p.pid == PID_DS4).is_some();
    avisar(app, "listo", "Firmware instalado", 100.0);
    Ok(Resultado { chip: chip.to_string(), bytes: total, verificado })
}
