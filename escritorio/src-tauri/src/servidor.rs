// Servidor web pequeño, solo para la red de casa: la misma página que sirve la app de Mac (app/Pagina.swift),
// con las mismas rutas. Todo lleva la clave: sin ella no se mira ni se cambia nada.
use std::io::{Read, Write};
use std::net::{TcpListener, TcpStream};
use std::sync::{Arc, Mutex};
use std::thread;
use std::time::{Duration, Instant};

use serde_json::Value;

use crate::nucleo::Nucleo;

/// La página del móvil, sacada de app/Pagina.swift al compilar (build.rs): una sola fuente para Mac y Windows
const PAGINA: &str = include_str!(concat!(env!("OUT_DIR"), "/pagina.html"));
const ICONO: &[u8] = include_bytes!("../icons/128x128@2x.png");

/// El de siempre: el acceso directo del móvil apunta a él. Si está ocupado, se insiste medio minuto
pub const PUERTO: u16 = 8787;

struct Intentos {
    fallos: Vec<Instant>,
    bloqueado_hasta: Option<Instant>,
}

pub struct Servidor {
    nucleo: Arc<Nucleo>,
    /// Los móviles mirando en directo, con la clave con la que entraron (si cambia, se les cierra)
    directo: Mutex<Vec<(TcpStream, String)>>,
    intentos: Mutex<Intentos>,
    pub puerto: Mutex<Option<u16>>,
    ultimo: Mutex<(String, Instant)>,
}

const MAXIMO: usize = 300_000;

impl Servidor {
    pub fn arrancar(nucleo: Arc<Nucleo>) -> Arc<Servidor> {
        let s = Arc::new(Servidor {
            nucleo,
            directo: Mutex::new(vec![]),
            intentos: Mutex::new(Intentos { fallos: vec![], bloqueado_hasta: None }),
            puerto: Mutex::new(None),
            ultimo: Mutex::new((String::new(), Instant::now())),
        });
        let s2 = s.clone();
        thread::spawn(move || s2.escuchar());
        let s3 = s.clone();
        thread::spawn(move || s3.publicar());
        s
    }

    pub fn clientes(&self) -> usize {
        self.directo.lock().unwrap().len()
    }

    fn escuchar(self: Arc<Self>) {
        let mut intento = 0;
        let fijo: u16 = std::env::var("PUENTE_PUERTO").ok().and_then(|p| p.parse().ok()).unwrap_or(PUERTO);
        let listener = loop {
            // Primero el 8787 durante medio minuto; luego el primero libre hasta el 8797
            let candidatos: Vec<u16> = if intento < 30 { vec![fijo] } else { (fijo..=fijo + 10).collect() };
            if let Some(l) = candidatos.iter().find_map(|p| TcpListener::bind(("0.0.0.0", *p)).ok()) {
                break l;
            }
            intento += 1;
            thread::sleep(Duration::from_secs(1));
        };
        *self.puerto.lock().unwrap() = listener.local_addr().ok().map(|a| a.port());
        for c in listener.incoming().flatten() {
            let s = self.clone();
            thread::spawn(move || s.atender(c));
        }
    }

    fn atender(self: Arc<Self>, mut c: TcpStream) {
        let _ = c.set_read_timeout(Some(Duration::from_secs(10)));
        // La ventana de la app entra siempre; desde la red, solo con «Servidor para el móvil» encendido
        let local = c.peer_addr().map(|a| a.ip().is_loopback()).unwrap_or(false);
        if !local && !self.nucleo.servidor_movil() {
            responder(&mut c, "403 Forbidden", "text/plain; charset=utf-8",
                      "El servidor para el móvil está apagado en el ordenador".as_bytes(), "no-store");
            return;
        }
        let mut buf = Vec::new();
        let mut trozo = [0u8; 16384];
        let (cabecera, cuerpo) = loop {
            let n = match c.read(&mut trozo) {
                Ok(0) | Err(_) => return,
                Ok(n) => n,
            };
            buf.extend_from_slice(&trozo[..n]);
            let fin = buf.windows(4).position(|w| w == b"\r\n\r\n");
            if buf.len() > MAXIMO {
                responder(&mut c, "413 Payload Too Large", "text/plain; charset=utf-8", "Demasiado grande".as_bytes(), "no-store");
                return;
            }
            if let Some(i) = fin {
                let cabecera = String::from_utf8_lossy(&buf[..i]).to_string();
                let largo = largo_del_cuerpo(&cabecera);
                if largo > MAXIMO {
                    responder(&mut c, "413 Payload Too Large", "text/plain; charset=utf-8", "Demasiado grande".as_bytes(), "no-store");
                    return;
                }
                if buf.len() - (i + 4) >= largo {
                    break (cabecera, buf[i + 4..i + 4 + largo].to_vec());
                }
            }
        };
        let mut lineas = cabecera.split("\r\n");
        let primera: Vec<&str> = lineas.next().unwrap_or("").split(' ').collect();
        if primera.len() < 2 {
            return;
        }
        let metodo = primera[0];
        let (ruta, consulta) = match primera[1].split_once('?') {
            Some((r, q)) => (r, q),
            None => (primera[1], ""),
        };
        let clave = consulta.split('&').find_map(|par| {
            let (k, v) = par.split_once('=')?;
            (k == "k").then(|| decodificar(v))
        });
        let x_puente = lineas.any(|l| l.to_lowercase().starts_with("x-puente:") && l[9..].trim() == "1");

        match (metodo, ruta) {
            ("GET", "/") | ("GET", "/index.html") => responder(&mut c, "200 OK", "text/html; charset=utf-8", PAGINA.as_bytes(), "no-store"),
            ("GET", "/icono.png") => responder(&mut c, "200 OK", "image/png", ICONO, "public, max-age=86400"),
            ("GET", "/estado") => {
                if self.autorizado(&mut c, clave) {
                    let json = self.nucleo.instantanea();
                    responder(&mut c, "200 OK", "application/json; charset=utf-8", json.as_bytes(), "no-store");
                }
            }
            ("GET", "/perfil") => {
                if self.autorizado(&mut c, clave) {
                    let json = self.nucleo.perfil_json();
                    responder(&mut c, "200 OK", "application/json; charset=utf-8", json.as_bytes(), "no-store");
                }
            }
            ("GET", "/medidor") => {
                if self.autorizado(&mut c, clave) {
                    let json = self.nucleo.medidor.lock().unwrap().json().to_string();
                    responder(&mut c, "200 OK", "application/json; charset=utf-8", json.as_bytes(), "no-store");
                }
            }
            // Sección «Móvil»: direcciones con la clave, el código QR de la primera y cuántos móviles miran
            ("GET", "/movil") => {
                if self.autorizado(&mut c, clave) {
                    let puerto = self.puerto.lock().unwrap().unwrap_or(PUERTO);
                    let dirs = direcciones(puerto, &self.nucleo.clave());
                    let qr = dirs.first().and_then(|d| crate::qr::svg(d));
                    let json = serde_json::json!({"direcciones": dirs, "qr": qr, "clientes": self.clientes(), "puerto": puerto,
                                                  "activo": self.nucleo.servidor_movil(), "local": local});
                    responder(&mut c, "200 OK", "application/json; charset=utf-8", json.to_string().as_bytes(), "no-store");
                }
            }
            ("GET", "/eventos") => {
                let k = clave.clone().unwrap_or_default();
                if self.autorizado(&mut c, clave) {
                    self.abrir_directo(c, k);
                }
            }
            ("POST", "/api") => {
                if !self.autorizado(&mut c, clave) {
                    return;
                }
                // Esta cabecera obliga al navegador a pedir permiso antes, y así otra web no puede cambiar nada
                let obj: Option<Value> = serde_json::from_slice(&cuerpo).ok().filter(|v: &Value| v.is_object());
                match (x_puente, obj) {
                    // Encender o apagar el acceso desde la red solo se puede desde el propio ordenador
                    (true, Some(obj)) if obj.get("accion").and_then(|a| a.as_str()) == Some("servidorMovil") => {
                        let r = if local {
                            let activo = obj.get("valor").and_then(|v| v.as_bool()).unwrap_or(true);
                            self.nucleo.poner_servidor_movil(activo);
                            if !activo {
                                self.directo.lock().unwrap().retain(|(s, _)| s.peer_addr().map(|a| a.ip().is_loopback()).unwrap_or(false));
                            }
                            serde_json::json!({"ok": true, "rev": self.nucleo.revision()})
                        } else {
                            serde_json::json!({"ok": false, "error": "Esto solo se cambia desde el ordenador", "rev": self.nucleo.revision()})
                        };
                        responder(&mut c, "200 OK", "application/json; charset=utf-8", r.to_string().as_bytes(), "no-store");
                    }
                    (true, Some(obj)) => {
                        let r = self.nucleo.aplicar(&obj);
                        responder(&mut c, "200 OK", "application/json; charset=utf-8", r.to_string().as_bytes(), "no-store");
                    }
                    _ => responder(&mut c, "400 Bad Request", "application/json; charset=utf-8",
                                   r#"{"ok":false,"error":"petición no válida"}"#.as_bytes(), "no-store"),
                }
            }
            _ => responder(&mut c, "404 Not Found", "text/plain; charset=utf-8", b"No existe", "no-store"),
        }
    }

    /// Comprueba la clave. Tras 8 fallos en un minuto se bloquea un minuto.
    fn autorizado(&self, c: &mut TcpStream, k: Option<String>) -> bool {
        let ahora = Instant::now();
        let mut i = self.intentos.lock().unwrap();
        if i.bloqueado_hasta.is_some_and(|b| ahora < b) {
            responder(c, "429 Too Many Requests", "text/plain; charset=utf-8", b"Demasiados intentos", "no-store");
            return false;
        }
        let clave = self.nucleo.clave();
        if k.as_deref().is_some_and(|k| !clave.is_empty() && k == clave) {
            return true;
        }
        i.fallos.retain(|f| ahora.duration_since(*f) < Duration::from_secs(60));
        i.fallos.push(ahora);
        if i.fallos.len() >= 8 {
            i.bloqueado_hasta = Some(ahora + Duration::from_secs(60));
            i.fallos.clear();
        }
        responder(c, "401 Unauthorized", "text/plain; charset=utf-8", b"Falta la clave", "no-store");
        false
    }

    fn abrir_directo(&self, mut c: TcpStream, clave: String) {
        let primero = self.nucleo.instantanea();
        let cabecera = format!(
            "HTTP/1.1 200 OK\r\nContent-Type: text/event-stream\r\nCache-Control: no-store\r\nConnection: keep-alive\r\nX-Accel-Buffering: no\r\n\r\ndata: {primero}\n\n"
        );
        let _ = c.set_write_timeout(Some(Duration::from_secs(2)));
        if c.write_all(cabecera.as_bytes()).is_ok() {
            self.directo.lock().unwrap().push((c, clave));
        }
    }

    /// 20 veces por segundo, si hay algún móvil mirando, se le manda el estado (y como mínimo cada 5 s)
    fn publicar(self: Arc<Self>) {
        loop {
            thread::sleep(Duration::from_millis(50));
            if self.clientes() == 0 {
                continue;
            }
            let json = self.nucleo.instantanea();
            {
                let mut u = self.ultimo.lock().unwrap();
                if json == u.0 && u.1.elapsed() < Duration::from_secs(5) {
                    continue;
                }
                *u = (json.clone(), Instant::now());
            }
            let dato = format!("data: {json}\n\n");
            let clave = self.nucleo.clave();
            self.directo.lock().unwrap().retain_mut(|(c, k)| {
                // Con la clave cambiada, ese móvil deja de ver nada y la página pide la nueva
                if *k != clave {
                    let _ = c.shutdown(std::net::Shutdown::Both);
                    return false;
                }
                c.write_all(dato.as_bytes()).is_ok()
            });
        }
    }

}

fn responder(c: &mut TcpStream, estado: &str, tipo: &str, cuerpo: &[u8], cache: &str) {
    let cabecera = format!(
        "HTTP/1.1 {estado}\r\nContent-Type: {tipo}\r\nContent-Length: {}\r\nCache-Control: {cache}\r\nConnection: close\r\n\r\n",
        cuerpo.len()
    );
    let _ = c.write_all(cabecera.as_bytes());
    let _ = c.write_all(cuerpo);
    let _ = c.flush();
}

fn largo_del_cuerpo(cabecera: &str) -> usize {
    cabecera.split("\r\n")
        .find_map(|l| l.to_lowercase().strip_prefix("content-length:").map(|v| v.trim().parse().unwrap_or(0)))
        .unwrap_or(0)
}

/// %XX y + de la dirección
fn decodificar(s: &str) -> String {
    let b = s.as_bytes();
    let mut out = Vec::with_capacity(b.len());
    let mut i = 0;
    while i < b.len() {
        if b[i] == b'%' && i + 2 < b.len() {
            if let Ok(v) = u8::from_str_radix(&s[i + 1..i + 3], 16) {
                out.push(v);
                i += 3;
                continue;
            }
        }
        out.push(if b[i] == b'+' { b' ' } else { b[i] });
        i += 1;
    }
    String::from_utf8_lossy(&out).to_string()
}

/// Direcciones con la clave para abrir desde el móvil (redes privadas de casa)
pub fn direcciones(puerto: u16, clave: &str) -> Vec<String> {
    let mut r = vec![];
    // La IP de salida a la red local, sin mandar nada: un socket UDP «conectado» a una dirección privada
    if let Ok(s) = std::net::UdpSocket::bind("0.0.0.0:0") {
        if s.connect("192.168.1.1:9").is_ok() {
            if let Ok(a) = s.local_addr() {
                let ip = a.ip().to_string();
                if !ip.starts_with("0.") && !ip.starts_with("127.") {
                    r.push(format!("http://{ip}:{puerto}/#k={clave}"));
                }
            }
        }
    }
    r
}
