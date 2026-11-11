// Qué modo tiene la placa: «PC» (mando + puerto serie por el USB nativo) o «consola» (solo mando, para el P5Mate).
use std::io::{Read, Write};
use std::thread::sleep;
use std::time::{Duration, Instant};

use serde::Serialize;

use crate::placa;

/// MAC inventada que el firmware contesta en el informe 0x12 (main/usb_ps4.c). En modo consola la placa
/// tiene los mismos datos USB que un DualShock 4 de verdad; esta MAC es lo único que la distingue.
#[cfg_attr(not(any(target_os = "macos", windows)), allow(dead_code))]
const MAC_FIRMWARE: [u8; 6] = [0x5e, 0xe5, 0x32, 0xa0, 0x04, 0xe5];

#[derive(Serialize)]
pub struct Modo {
    /// "pc", "consola", "grabacion" (sin firmware o esperando a grabar), "com" (solo se ve el puerto COM:
    /// hay que preguntarle) o "ninguna".
    pub modo: String,
    /// Puerto serie por el que se puede hablar con la placa (el del modo PC o el COM).
    pub puerto: Option<String>,
    /// En modo consola, false si se ve un mando de PS4 pero no se ha podido confirmar que sea la placa.
    pub confirmado: bool,
}

fn modo(modo: &str, puerto: Option<String>, confirmado: bool) -> Modo {
    Modo { modo: modo.into(), puerto, confirmado }
}

pub fn detectar() -> Modo {
    let puertos = placa::listar();
    let com = puertos.iter().find(|p| p.tipo == "puente-serie").map(|p| p.nombre.clone());

    // Modo PC: el mando viene con su puerto serie (CDC), así que se ve como puerto.
    if let Some(p) = puertos.iter().find(|p| p.tipo == "firmware") {
        return modo("pc", Some(p.nombre.clone()), true);
    }
    // Modo consola: solo el mando HID, sin puerto serie.
    if let Some(confirmado) = mando_hid() {
        return modo("consola", com, confirmado);
    }
    if puertos.iter().any(|p| p.tipo == "esp32s3") {
        return modo("grabacion", None, true);
    }
    match com {
        Some(c) => modo("com", Some(c), false),
        None => modo("ninguna", None, false),
    }
}

/// Busca un mando de PS4 por HID. Some(true) si es la placa (contesta con la MAC del firmware),
/// Some(false) si hay un mando de PS4 que no se ha podido confirmar, None si no hay ninguno.
#[cfg(any(target_os = "macos", windows))]
fn mando_hid() -> Option<bool> {
    let api = hidapi::HidApi::new().ok()?;
    let mut visto = false;
    for d in api
        .device_list()
        .filter(|d| d.vendor_id() == placa::VID_SONY && d.product_id() == placa::PID_DS4)
    {
        visto = true;
        let Ok(mando) = d.open_device(&api) else { continue };
        let mut informe = [0u8; 64];
        informe[0] = 0x12;
        if let Ok(n) = mando.get_feature_report(&mut informe) {
            // Según el sistema el ID del informe va delante o no: se busca la MAC en todo lo recibido.
            if informe[..n.min(informe.len())].windows(6).any(|w| w == MAC_FIRMWARE) {
                return Some(true);
            }
        }
    }
    visto.then_some(false)
}

#[cfg(not(any(target_os = "macos", windows)))]
fn mando_hid() -> Option<bool> {
    None
}

/// Pregunta el modo con la orden `estado` por un puerto serie (el COM de la placa o el del modo PC).
/// Abrir el COM puede reiniciar algunas placas, por eso se reintenta durante unos segundos.
pub fn preguntar(nombre: &str) -> Result<String, String> {
    let mut serie = serialport::new(nombre, 921_600)
        .timeout(Duration::from_millis(100))
        .open()
        .map_err(|e| format!("No he podido abrir {nombre}: {e}. ¿Lo está usando otro programa?"))?;
    let mut texto = String::new();
    for _ in 0..4 {
        serie
            .write_all(b"estado\n")
            .map_err(|e| format!("No he podido hablar con la placa: {e}"))?;
        let limite = Instant::now() + Duration::from_millis(900);
        let mut trozo = [0u8; 256];
        while Instant::now() < limite {
            if let Ok(n) = serie.read(&mut trozo) {
                texto.push_str(&String::from_utf8_lossy(&trozo[..n]));
            }
            if texto.contains("Modo: mac") {
                return Ok("pc".into());
            }
            if texto.contains("Modo: consola") {
                return Ok("consola".into());
            }
        }
        sleep(Duration::from_millis(400));
    }
    Err("La placa no contesta por este puerto. Comprueba que lleva el firmware del puente de mando.".into())
}
