// Manda el estado del mando a la ESP32 por el puerto serie, como la clase Esp32 de app/Motor.swift.
// Prefiere el puerto serie del propio firmware (modo PC, por el USB nativo); si no, el COM de la placa.
#![allow(dead_code)]

use std::io::{ErrorKind, Read, Write};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::mpsc::{channel, Receiver};
use std::sync::Arc;
use std::time::Duration;

use serialport::{SerialPort, SerialPortType};

use crate::modelo::{Boton, Estado};

const VID_SONY: u16 = 0x054C; // el firmware en modo PC: mando de PS4 + puerto serie
const PID_DS4: u16 = 0x09CC;
/// Chips USB-serie del «COM» de las placas: CH340/CH343, CP210x y FTDI
const VID_PUENTES: [u16; 3] = [0x1A86, 0x10C4, 0x0403];
const BAUDIOS: u32 = 921_600;

pub struct Esp32 {
    puerto: Option<Box<dyn SerialPort>>,
    ruta: Option<String>,
    /// Respuestas de la sincronización de ajustes («@AJ …»), leídas por un hilo aparte
    respuestas: Option<Receiver<String>>,
    parar_lector: Arc<AtomicBool>,
}

impl Default for Esp32 {
    fn default() -> Self {
        Esp32::new()
    }
}

impl Esp32 {
    pub fn new() -> Self {
        Esp32 { puerto: None, ruta: None, respuestas: None, parar_lector: Arc::new(AtomicBool::new(false)) }
    }

    pub fn conectado(&self) -> bool {
        self.puerto.is_some()
    }

    pub fn ruta(&self) -> Option<String> {
        self.ruta.clone()
    }

    /// Busca la placa y abre su puerto. true si queda conectada.
    pub fn conectar(&mut self) -> bool {
        if self.puerto.is_some() {
            return true;
        }
        for ruta in candidatos() {
            // Sin tocar DTR/RTS: en Windows serialport los deja apagados y en macOS se quedan como los pone
            // el sistema (los dos a la vez), así el circuito de reinicio automático de la placa no salta.
            // No exclusivo, como en la app de Mac, para poder preguntarle el modo con el puerto abierto.
            let constructor = serialport::new(&ruta, BAUDIOS)
                .timeout(Duration::from_millis(5))
                .preserve_dtr_on_open();
            // En Windows un COM siempre es exclusivo: para grabar o preguntar el modo, el motor suelta la placa
            #[cfg(unix)]
            let abierto = constructor.open_native().map(|mut p| {
                let _ = p.set_exclusive(false);
                sin_hupcl(&p);
                Box::new(p) as Box<dyn serialport::SerialPort>
            });
            #[cfg(not(unix))]
            let abierto = constructor.open();
            if let Ok(p) = abierto {
                self.arrancar_lector(&p);
                self.puerto = Some(p);
                self.ruta = Some(ruta);
                return true;
            }
        }
        false
    }

    /// Manda una trama. false si la placa se ha perdido (se cierra el puerto; el motor reintenta conectar).
    pub fn enviar(&mut self, e: &Estado) -> bool {
        let Some(p) = self.puerto.as_mut() else { return false };
        match p.write_all(&trama(e)) {
            Ok(()) => true,
            // Buffer lleno: se pierde esta trama, pero el puerto sigue (como el EAGAIN de la versión de Swift)
            Err(err) if err.kind() == ErrorKind::TimedOut || err.kind() == ErrorKind::WouldBlock => true,
            Err(_) => {
                self.cerrar();
                false
            }
        }
    }

    pub fn cerrar(&mut self) {
        // (en macOS, sin HUPCL: cerrar el puerto no reinicia la placa ni la desconecta de la consola)
        self.parar_lector.store(true, Ordering::Relaxed);   // suelta su copia del puerto (para grabar, etc.)
        self.puerto = None;
        self.ruta = None;
        self.respuestas = None;
    }

    /// Manda una línea de texto (una orden para la placa). false si la placa se ha perdido.
    pub fn escribir_linea(&mut self, linea: &str) -> bool {
        let Some(p) = self.puerto.as_mut() else { return false };
        let mut datos = linea.as_bytes().to_vec();
        datos.push(b'\n');
        match p.write_all(&datos) {
            Ok(()) => true,
            Err(err) if err.kind() == ErrorKind::TimedOut || err.kind() == ErrorKind::WouldBlock => true,
            Err(_) => {
                self.cerrar();
                false
            }
        }
    }

    /// Las respuestas de la sincronización que hayan llegado desde la última vez
    pub fn respuestas(&mut self) -> Vec<String> {
        self.respuestas.as_ref().map(|r| r.try_iter().collect()).unwrap_or_default()
    }

    /// Un hilo que lee lo que manda la placa y se queda con las líneas «@AJ …» (el resto es su log)
    fn arrancar_lector(&mut self, p: &Box<dyn SerialPort>) {
        let Ok(mut copia) = p.try_clone() else { return };
        let _ = copia.set_timeout(Duration::from_millis(50));
        let parar = Arc::new(AtomicBool::new(false));
        self.parar_lector = parar.clone();
        let (tx, rx) = channel();
        self.respuestas = Some(rx);
        std::thread::Builder::new().name("placa-lector".into()).spawn(move || {
            let mut pendiente: Vec<u8> = vec![];
            let mut buf = [0u8; 1024];
            while !parar.load(Ordering::Relaxed) {
                match copia.read(&mut buf) {
                    Ok(0) => {}
                    Ok(n) => {
                        pendiente.extend_from_slice(&buf[..n]);
                        while let Some(i) = pendiente.iter().position(|b| *b == b'\n') {
                            let linea: Vec<u8> = pendiente.drain(..=i).collect();
                            let texto = String::from_utf8_lossy(&linea).trim().to_string();
                            if texto.starts_with("@AJ ") && tx.send(texto).is_err() {
                                return;
                            }
                        }
                        if pendiente.len() > 8192 {
                            pendiente.clear();          // basura sin saltos de línea
                        }
                    }
                    Err(e) if e.kind() == ErrorKind::TimedOut || e.kind() == ErrorKind::WouldBlock => {}
                    Err(_) => return,                   // la placa se ha ido
                }
            }
        }).ok();
    }
}

/// Puertos de la placa en orden de preferencia: primero el del firmware en modo PC; después el COM
fn candidatos() -> Vec<String> {
    let mut firmware = vec![];
    let mut com = vec![];
    for p in serialport::available_ports().unwrap_or_default() {
        // En macOS cada puerto sale como tty.* y cu.*; para abrir sin esperar a la portadora, cu.*
        if p.port_name.contains("/dev/tty.") {
            continue;
        }
        if let SerialPortType::UsbPort(u) = p.port_type {
            if u.vid == VID_SONY && u.pid == PID_DS4 {
                firmware.push(p.port_name);
            } else if VID_PUENTES.contains(&u.vid) {
                com.push(p.port_name);
            }
        }
    }
    firmware.sort();
    com.sort();
    firmware.extend(com);
    firmware
}

/// Trama: A5 5A | botones (2 bytes, bajo primero, los 14 bits) | cruceta | lx ly rx ry l2 r2 | XOR de esos 9 bytes
pub fn trama(e: &Estado) -> [u8; 12] {
    let fisicos = e.botones & 0x3FFF;
    let datos = [fisicos as u8, (fisicos >> 8) as u8, cruceta(e), e.lx, e.ly, e.rx, e.ry, e.l2, e.r2];
    let mut t = [0u8; 12];
    t[0] = 0xA5;
    t[1] = 0x5A;
    t[2..11].copy_from_slice(&datos);
    t[11] = datos.iter().fold(0, |a, b| a ^ b);
    t
}

/// Cruceta: 0 = arriba y en sentido horario hasta 7; 8 = suelta (o una combinación imposible)
pub fn cruceta(e: &Estado) -> u8 {
    match (e.pulsado(Boton::Arriba), e.pulsado(Boton::Derecha), e.pulsado(Boton::Abajo), e.pulsado(Boton::Izquierda)) {
        (true, false, false, false) => 0,
        (true, true, false, false) => 1,
        (false, true, false, false) => 2,
        (false, true, true, false) => 3,
        (false, false, true, false) => 4,
        (false, false, true, true) => 5,
        (false, false, false, true) => 6,
        (true, false, false, true) => 7,
        _ => 8,
    }
}

#[cfg(test)]
mod pruebas {
    use super::*;

    #[test]
    fn trama_en_reposo() {
        // Lo mismo que construye Esp32.enviar en Swift con Estado(): sticks al centro y nada pulsado
        let t = trama(&Estado::default());
        assert_eq!(t, [0xA5, 0x5A, 0x00, 0x00, 0x08, 128, 128, 128, 128, 0, 0, 0x08]);
    }

    #[test]
    fn botones_cruceta_y_xor() {
        let e = Estado {
            botones: Boton::X.bit() | Boton::R2.bit() | Boton::Tactil.bit() | Boton::Arriba.bit() | Boton::Derecha.bit()
                | Boton::Silenciar.bit(),
            lx: 0, ly: 255, rx: 100, ry: 30, l2: 0, r2: 255,
        };
        let t = trama(&e);
        // X = bit 1, R2 = bit 7, Táctil = bit 13: 0x2082. La cruceta y el silenciar no van en los 14 bits.
        assert_eq!(&t[..11], &[0xA5, 0x5A, 0x82, 0x20, 1, 0, 255, 100, 30, 0, 255]);
        let xor = t[2..11].iter().fold(0u8, |a, b| a ^ b);
        assert_eq!(t[11], xor);
    }

    #[test]
    fn las_ocho_direcciones() {
        use Boton::*;
        let casos: [(&[Boton], u8); 10] = [
            (&[Arriba], 0), (&[Arriba, Derecha], 1), (&[Derecha], 2), (&[Derecha, Abajo], 3), (&[Abajo], 4),
            (&[Abajo, Izquierda], 5), (&[Izquierda], 6), (&[Arriba, Izquierda], 7), (&[], 8), (&[Arriba, Abajo], 8),
        ];
        for (botones, esperado) in casos {
            let e = Estado { botones: botones.iter().fold(0, |a, b| a | b.bit()), ..Default::default() };
            assert_eq!(cruceta(&e), esperado, "{botones:?}");
        }
    }
}

/// Que cerrar el puerto no baje DTR/RTS: con el circuito de reinicio automático la placa se reiniciaría
/// y la consola perdería el mando (la app de Mac hace lo mismo)
#[cfg(unix)]
fn sin_hupcl(p: &serialport::TTYPort) {
    use std::os::unix::io::AsRawFd;
    let fd = p.as_raw_fd();
    unsafe {
        let mut t: libc::termios = std::mem::zeroed();
        if libc::tcgetattr(fd, &mut t) == 0 {
            t.c_cflag &= !libc::HUPCL;
            libc::tcsetattr(fd, libc::TCSANOW, &t);
        }
    }
}
