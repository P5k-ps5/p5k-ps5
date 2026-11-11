// Los mismos ajustes en la placa y en esta app. La placa guarda los «buenos» (se pueden cambiar desde el móvil
// en cualquier sitio); al conectarla por el cable, la app los recoge, y lo que se cambie aquí se le manda.
// Va por el mismo puerto serie que las tramas del mando, en líneas de texto cortas (protocolo en main/sincro.c
// del firmware). Lo mismo hace la app de Mac (app/Sincro.swift).
//
// Cuándo gana cada uno:
// - La primera vez: si esta app tiene los ajustes de fábrica, se quedan los de la placa; si no, se suben los
//   de la app (los de la placa se guardan antes en una copia).
// - Después: si solo ha cambiado uno, se copia al otro. Si han cambiado los dos, gana la placa y los de esta
//   app se guardan en una copia (perfiles.copia-conflicto-FECHA.json).
use std::path::{Path, PathBuf};
use std::sync::Mutex;

use base64::Engine;
use serde::{Deserialize, Serialize};

use crate::dualsense_informe::crc32;
use crate::modelo::{Almacen, Perfil};

/// Lo que hace falta para hablar con la placa (la placa de verdad es esp32::Esp32; en las pruebas, una falsa)
pub trait Canal {
    fn conectado(&self) -> bool;
    fn linea(&mut self, l: &str) -> bool;
    fn respuestas(&mut self) -> Vec<String>;
}

impl Canal for crate::esp32::Esp32 {
    fn conectado(&self) -> bool {
        crate::esp32::Esp32::conectado(self)
    }
    fn linea(&mut self, l: &str) -> bool {
        self.escribir_linea(l)
    }
    fn respuestas(&mut self) -> Vec<String> {
        crate::esp32::Esp32::respuestas(self)
    }
}

const TROZO: usize = 150;
const CALMA_PARA_SUBIR: f64 = 1.0;     // los cambios se suben cuando llevan 1 s quietos
const COMPROBAR_CADA: f64 = 3.0;       // cada cuánto se mira si han cambiado en la placa (desde el móvil)
const ESPERA_RESPUESTA: f64 = 0.5;

/// Lo que se guarda entre arranques (sincro.json, al lado de perfiles.json)
#[derive(Serialize, Deserialize, Default, Clone)]
#[serde(default, rename_all = "camelCase")]
struct Guardado {
    /// La revisión de la placa la última vez que quedaron iguales ("" = nunca)
    ultima_rev: String,
    /// Hay cambios en esta app que la placa todavía no tiene
    cambios_locales: bool,
}

enum Destino {
    Aplicar,
    /// Primera vez: según quién tenga los ajustes de fábrica
    PrimeraVez,
}

enum Fase {
    Desconectada,
    Preguntando { enviado: f64, intentos: u32 },
    Bajando { rev: String, largo: usize, crc: u32, datos: Vec<u8>, pedido: f64, destino: Destino },
    Subiendo { datos: Vec<u8>, version: u64, paso: u8, enviado: usize, pedido: f64 },
    AlDia { comprobado: f64 },
    /// La placa no contesta a «ajustes rev»: firmware antiguo
    SinSoporte,
}

pub struct Sincro {
    fase: Fase,
    g: Guardado,
    archivo: PathBuf,
    perfiles: PathBuf,
    /// La versión del almacén que ya tiene la placa (o que vino de ella)
    version_vista: u64,
    ultimo_cambio: f64,
}

impl Sincro {
    pub fn new(archivo_perfiles: &Path, version_inicial: u64) -> Sincro {
        let archivo = archivo_perfiles.with_file_name("sincro.json");
        let g = std::fs::read(&archivo).ok().and_then(|d| serde_json::from_slice(&d).ok()).unwrap_or_default();
        Sincro {
            fase: Fase::Desconectada,
            g,
            archivo,
            perfiles: archivo_perfiles.to_path_buf(),
            version_vista: version_inicial,
            ultimo_cambio: 0.0,
        }
    }

    /// Para enseñarlo en la app
    pub fn estado(&self) -> &'static str {
        match self.fase {
            Fase::Desconectada => "sin placa",
            Fase::Preguntando { .. } | Fase::AlDia { .. } if self.g.cambios_locales => "pendiente",
            Fase::Preguntando { .. } | Fase::AlDia { .. } => "al día",
            Fase::Bajando { .. } => "recibiendo",
            Fase::Subiendo { .. } => "enviando",
            Fase::SinSoporte => "firmware antiguo",
        }
    }

    fn guardar(&self) {
        if let Ok(d) = serde_json::to_vec_pretty(&self.g) {
            let _ = std::fs::write(&self.archivo, d);
        }
    }

    fn copia(&self, motivo: &str, datos: &[u8]) -> String {
        let nombre = format!("perfiles.copia-{motivo}-{}.json", fecha_hoy());
        let _ = std::fs::write(self.perfiles.with_file_name(&nombre), datos);
        nombre
    }

    /// Una vuelta (el motor la llama en cada una de las suyas). Devuelve un aviso para el usuario, si hay.
    pub fn vuelta(&mut self, c: &mut impl Canal, almacen: &Mutex<Almacen>, t: f64) -> Option<String> {
        if !c.conectado() {
            self.fase = Fase::Desconectada;
            return None;
        }
        if matches!(self.fase, Fase::Desconectada) {
            self.fase = Fase::Preguntando { enviado: f64::MIN, intentos: 0 };
        }
        if matches!(self.fase, Fase::SinSoporte) {
            return None;
        }

        // Cambios hechos en esta app (no los que vienen de la placa: esos ponen version_vista al aplicarse)
        if !matches!(self.fase, Fase::Bajando { .. }) {
            if let Ok(a) = almacen.try_lock() {
                if a.version != self.version_vista {
                    self.version_vista = a.version;
                    self.ultimo_cambio = t;
                    if !self.g.cambios_locales {
                        self.g.cambios_locales = true;
                        self.guardar();
                    }
                }
            }
        }

        let mut aviso = None;
        for r in c.respuestas() {
            if let Some(a) = self.respuesta(&r, almacen, t) {
                aviso = Some(a);
            }
        }

        // Lo que toca mandar ahora en cada fase
        match &mut self.fase {
            Fase::Preguntando { enviado, intentos } => {
                if t - *enviado > 1.0 {
                    if *intentos >= 5 {
                        self.fase = Fase::SinSoporte;
                    } else {
                        *enviado = t;
                        *intentos += 1;
                        c.linea("ajustes rev");
                    }
                }
            }
            Fase::Bajando { datos, largo, pedido, .. } => {
                if datos.len() < *largo && t - *pedido > ESPERA_RESPUESTA {
                    *pedido = t;
                    c.linea(&format!("ajustes leer {}", datos.len()));
                }
            }
            Fase::Subiendo { datos, paso, enviado, pedido, .. } => {
                let espera = if *paso == 2 { 3.0 } else { ESPERA_RESPUESTA };
                if t - *pedido > espera {
                    match *paso {
                        0 => {
                            *pedido = t;
                            c.linea(&format!("ajustes poner {} {:08x}", datos.len(), crc32(datos)));
                        }
                        1 => {
                            *pedido = t;
                            let fin = (*enviado + TROZO).min(datos.len());
                            let b64 = base64::engine::general_purpose::STANDARD.encode(&datos[*enviado..fin]);
                            c.linea(&format!("ajustes trozo {} {b64}", *enviado));
                        }
                        _ => {
                            // «fin» se manda una sola vez: si no contesta, se vuelve a preguntar la revisión
                            if *pedido == f64::MIN {
                                *pedido = t;
                                c.linea("ajustes fin");
                            } else {
                                self.fase = Fase::Preguntando { enviado: f64::MIN, intentos: 0 };
                            }
                        }
                    }
                }
            }
            Fase::AlDia { comprobado } => {
                if self.g.cambios_locales && t - self.ultimo_cambio > CALMA_PARA_SUBIR {
                    self.subir(almacen);
                } else if t - *comprobado > COMPROBAR_CADA {
                    self.fase = Fase::Preguntando { enviado: f64::MIN, intentos: 0 };
                }
            }
            _ => {}
        }
        aviso
    }

    fn subir(&mut self, almacen: &Mutex<Almacen>) {
        let (datos, version) = {
            let a = almacen.lock().unwrap();
            (a.ajustes_sincronizados().into_bytes(), a.version)
        };
        self.fase = Fase::Subiendo { datos, version, paso: 0, enviado: 0, pedido: f64::MIN };
    }

    fn al_dia(&mut self, t: f64) {
        self.fase = Fase::AlDia { comprobado: t };
    }

    fn respuesta(&mut self, r: &str, almacen: &Mutex<Almacen>, t: f64) -> Option<String> {
        let p: Vec<&str> = r.split_whitespace().collect();
        match (&mut self.fase, p.get(1).copied()) {
            (Fase::Preguntando { .. }, Some("REV")) if p.len() >= 5 => {
                let rev = p[2].to_string();
                let largo: usize = p[3].parse().unwrap_or(0);
                let crc = u32::from_str_radix(p[4], 16).unwrap_or(0);
                let bajar = |destino| Fase::Bajando { rev: rev.clone(), largo, crc, datos: vec![], pedido: f64::MIN, destino };
                if self.g.ultima_rev.is_empty() {
                    self.fase = bajar(Destino::PrimeraVez);
                } else if rev == self.g.ultima_rev {
                    if self.g.cambios_locales {
                        self.subir(almacen);
                    } else {
                        self.al_dia(t);
                    }
                } else if !self.g.cambios_locales {
                    self.fase = bajar(Destino::Aplicar);
                } else {
                    // Cambiados en los dos sitios: gana la placa; los de aquí, a una copia
                    let local = almacen.lock().unwrap().ajustes_sincronizados();
                    let nombre = self.copia("conflicto", local.as_bytes());
                    self.fase = bajar(Destino::Aplicar);
                    return Some(format!("Habías cambiado ajustes aquí y en la placa: me quedo con los de la placa (los de aquí, en {nombre})"));
                }
                None
            }
            (Fase::Bajando { datos, pedido, .. }, Some("T")) if p.len() >= 4 => {
                if p[2].parse::<usize>().ok() == Some(datos.len()) {
                    if let Ok(d) = base64::engine::general_purpose::STANDARD.decode(p[3]) {
                        datos.extend_from_slice(&d);
                        *pedido = f64::MIN;              // el siguiente trozo, ya
                    }
                }
                self.quiza_terminar_bajada(almacen, t)
            }
            (Fase::Subiendo { paso, pedido, .. }, Some("LISTO")) if *paso == 0 => {
                *paso = 1;
                *pedido = f64::MIN;
                None
            }
            (Fase::Subiendo { paso, enviado, pedido, datos, .. }, Some("ACK")) if *paso == 1 && p.len() >= 3 => {
                if let Ok(n) = p[2].parse::<usize>() {
                    *enviado = n;
                    *pedido = f64::MIN;
                    if n >= datos.len() {
                        *paso = 2;
                    }
                }
                None
            }
            (Fase::Subiendo { version, .. }, Some("OK")) if p.len() >= 3 => {
                let version = *version;
                self.g.ultima_rev = p[2].to_string();
                if almacen.lock().unwrap().version == version {
                    self.g.cambios_locales = false;
                }
                self.guardar();
                self.al_dia(t);
                None
            }
            (Fase::Subiendo { .. }, Some("ERROR")) => {
                self.fase = Fase::Preguntando { enviado: t + 1.0, intentos: 0 };
                None
            }
            _ => None,
        }
    }

    fn quiza_terminar_bajada(&mut self, almacen: &Mutex<Almacen>, t: f64) -> Option<String> {
        let Fase::Bajando { rev, largo, crc, datos, destino, .. } = &self.fase else { return None };
        if datos.len() < *largo {
            return None;
        }
        if datos.len() != *largo || crc32(datos) != *crc {
            self.fase = Fase::Preguntando { enviado: f64::MIN, intentos: 0 };   // ha llegado mal: otra vez
            return None;
        }
        let (rev, datos) = (rev.clone(), datos.clone());
        let primera = matches!(destino, Destino::PrimeraVez);
        let json = String::from_utf8_lossy(&datos).to_string();
        if primera && !de_fabrica(&almacen.lock().unwrap().perfiles) {
            // Primera vez y esta app ya tiene ajustes: se suben (los de la placa, a una copia)
            let nombre = self.copia("de-la-placa", &datos);
            self.subir(almacen);
            return Some(format!("Primera vez con esta placa: le paso los ajustes de aquí (los que tenía, en {nombre})"));
        }
        let resultado = {
            let mut a = almacen.lock().unwrap();
            let r = a.poner_ajustes_sincronizados(&json);
            self.version_vista = a.version;
            r
        };
        match resultado {
            Ok(()) => {
                self.g.ultima_rev = rev;
                self.g.cambios_locales = false;
                self.guardar();
                self.al_dia(t);
                Some("Ajustes recogidos de la placa".into())
            }
            Err(e) => {
                self.fase = Fase::SinSoporte;
                Some(format!("Los ajustes de la placa no se pueden leer: {e}"))
            }
        }
    }
}

/// ¿Son los ajustes con los que arranca la app la primera vez? (un perfil «Normal» sin tocar)
fn de_fabrica(perfiles: &[Perfil]) -> bool {
    let [p] = perfiles else { return false };
    let mut nuevo = Perfil::con_nombre("Normal");
    nuevo.id = p.id.clone();
    serde_json::to_value(&nuevo).ok() == serde_json::to_value(p).ok()
}

/// AAAA-MM-DD de hoy (UTC), para el nombre de las copias
fn fecha_hoy() -> String {
    let s = std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).map(|d| d.as_secs()).unwrap_or(0);
    let dias = (s / 86400) as i64;
    // de días desde 1970 a fecha civil (Howard Hinnant)
    let z = dias + 719_468;
    let era = z.div_euclid(146_097);
    let doe = z - era * 146_097;
    let yoe = (doe - doe / 1460 + doe / 36_524 - doe / 146_096) / 365;
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
    let mp = (5 * doy + 2) / 153;
    let d = doy - (153 * mp + 2) / 5 + 1;
    let m = if mp < 10 { mp + 3 } else { mp - 9 };
    let y = yoe + era * 400 + if m <= 2 { 1 } else { 0 };
    format!("{y:04}-{m:02}-{d:02}")
}

#[cfg(test)]
mod pruebas {
    use super::*;
    use crate::modelo::nuevo_id;
    use serde_json::json;

    /// Una placa falsa que habla el mismo protocolo que main/sincro.c (con su propio almacén)
    struct PlacaFalsa {
        almacen: Almacen,
        copia: String,
        entrada: Vec<u8>,
        esperado: usize,
        crc: u32,
        salida: Vec<String>,
        conectada: bool,
        contesta: bool,
    }

    fn rev(json: &str) -> String {
        let mut h: u64 = 0xcbf29ce484222325;
        for b in json.as_bytes() {
            h ^= *b as u64;
            h = h.wrapping_mul(0x100000001b3);
        }
        format!("{h:016x}")
    }

    impl Canal for PlacaFalsa {
        fn conectado(&self) -> bool {
            self.conectada
        }
        fn linea(&mut self, l: &str) -> bool {
            if !self.contesta {
                return true;
            }
            let p: Vec<&str> = l.split_whitespace().collect();
            match p.get(1).copied() {
                Some("rev") => {
                    self.copia = self.almacen.ajustes_sincronizados();
                    self.salida.push(format!("@AJ REV {} {} {:08x}", rev(&self.copia), self.copia.len(), crc32(self.copia.as_bytes())));
                }
                Some("leer") => {
                    let d: usize = p[2].parse().unwrap();
                    let fin = (d + TROZO).min(self.copia.len());
                    let b = base64::engine::general_purpose::STANDARD.encode(&self.copia.as_bytes()[d..fin]);
                    self.salida.push(format!("@AJ T {d} {b}"));
                }
                Some("poner") => {
                    self.esperado = p[2].parse().unwrap();
                    self.crc = u32::from_str_radix(p[3], 16).unwrap();
                    self.entrada.clear();
                    self.salida.push("@AJ LISTO".into());
                }
                Some("trozo") => {
                    if p[2].parse::<usize>().unwrap() == self.entrada.len() {
                        self.entrada.extend(base64::engine::general_purpose::STANDARD.decode(p[3]).unwrap());
                    }
                    self.salida.push(format!("@AJ ACK {}", self.entrada.len()));
                }
                Some("fin") => {
                    assert_eq!(crc32(&self.entrada), self.crc);
                    self.almacen.poner_ajustes_sincronizados(std::str::from_utf8(&self.entrada).unwrap()).unwrap();
                    self.salida.push(format!("@AJ OK {}", rev(&self.almacen.ajustes_sincronizados())));
                }
                _ => {}
            }
            true
        }
        fn respuestas(&mut self) -> Vec<String> {
            std::mem::take(&mut self.salida)
        }
    }

    fn carpeta() -> PathBuf {
        let d = std::env::temp_dir().join(format!("sincro-{}", nuevo_id()));
        std::fs::create_dir_all(&d).unwrap();
        d
    }

    fn placa() -> PlacaFalsa {
        PlacaFalsa { almacen: Almacen::cargar(carpeta().join("perfiles.json")), copia: String::new(), entrada: vec![],
                     esperado: 0, crc: 0, salida: vec![], conectada: true, contesta: true }
    }

    fn app() -> (Mutex<Almacen>, Sincro, PathBuf) {
        let dir = carpeta();
        let a = Almacen::cargar(dir.join("perfiles.json"));
        let s = Sincro::new(&dir.join("perfiles.json"), a.version);
        (Mutex::new(a), s, dir)
    }

    /// Da vueltas hasta que esté al día (o 20 s simulados)
    fn hasta_al_dia(s: &mut Sincro, c: &mut PlacaFalsa, a: &Mutex<Almacen>, t: &mut f64) -> Vec<String> {
        let mut avisos = vec![];
        for _ in 0..20_000 {
            *t += 0.001;
            if let Some(x) = s.vuelta(c, a, *t) {
                avisos.push(x);
            }
            if s.estado() == "al día" && !matches!(s.fase, Fase::Preguntando { .. }) {
                break;
            }
        }
        avisos
    }

    fn cambiar(a: &mut Almacen, ruta: &str, valor: serde_json::Value) {
        assert!(a.poner_ruta(ruta, valor).is_none());
    }

    #[test]
    fn primera_vez_con_ajustes_aqui_los_sube_y_guarda_copia_de_los_de_la_placa() {
        let (a, mut s, dir) = app();
        cambiar(&mut a.lock().unwrap(), "antiRecoil.vertical", json!(37));
        s.version_vista = a.lock().unwrap().version;      // como si viniera ya así del disco
        let mut c = placa();
        let mut t = 0.0;
        let avisos = hasta_al_dia(&mut s, &mut c, &a, &mut t);
        assert_eq!(c.almacen.activo().anti_recoil.vertical, 37.0, "la placa tiene los ajustes de la app");
        assert!(avisos.iter().any(|x| x.contains("Primera vez")), "{avisos:?}");
        assert!(std::fs::read_dir(&dir).unwrap().any(|e| e.unwrap().file_name().to_string_lossy().contains("copia-de-la-placa")));
        assert_eq!(c.almacen.ajustes_sincronizados(), a.lock().unwrap().ajustes_sincronizados());
    }

    #[test]
    fn primera_vez_de_fabrica_se_queda_los_de_la_placa() {
        let (a, mut s, _) = app();
        let mut c = placa();
        cambiar(&mut c.almacen, "antiRecoil.vertical", json!(55));
        let mut t = 0.0;
        hasta_al_dia(&mut s, &mut c, &a, &mut t);
        assert_eq!(a.lock().unwrap().activo().anti_recoil.vertical, 55.0);
        let clave_app = a.lock().unwrap().generales.clave.clone();
        assert_ne!(clave_app, c.almacen.generales.clave, "cada uno con su clave");
    }

    #[test]
    fn despues_los_cambios_van_y_vienen() {
        let (a, mut s, _) = app();
        let mut c = placa();
        let mut t = 0.0;
        hasta_al_dia(&mut s, &mut c, &a, &mut t);
        // Cambio aquí: se sube cuando lleva 1 s quieto
        cambiar(&mut a.lock().unwrap(), "antiRecoil.vertical", json!(12));
        for _ in 0..3000 {
            t += 0.001;
            s.vuelta(&mut c, &a, t);
        }
        assert_eq!(c.almacen.activo().anti_recoil.vertical, 12.0, "subido");
        assert_eq!(s.estado(), "al día");
        // Cambio en la placa (desde el móvil): se recoge en la siguiente comprobación (3 s)
        cambiar(&mut c.almacen, "antiRecoil.vertical", json!(19));
        let mut avisos = vec![];
        for _ in 0..5000 {
            t += 0.001;
            avisos.extend(s.vuelta(&mut c, &a, t));
        }
        assert_eq!(a.lock().unwrap().activo().anti_recoil.vertical, 19.0, "recogido");
        assert!(avisos.iter().any(|x| x.contains("recogidos")));
        // y recoger no cuenta como cambio de aquí (no se vuelve a subir)
        assert!(!s.g.cambios_locales);
    }

    #[test]
    fn si_cambian_los_dos_gana_la_placa_y_se_guarda_copia() {
        let (a, mut s, dir) = app();
        let mut c = placa();
        let mut t = 0.0;
        hasta_al_dia(&mut s, &mut c, &a, &mut t);
        // La app se queda sin placa, cambia algo; mientras, en la placa también
        c.conectada = false;
        s.vuelta(&mut c, &a, t);
        cambiar(&mut a.lock().unwrap(), "antiRecoil.vertical", json!(70));
        t += 0.01;
        s.vuelta(&mut c, &a, t);
        cambiar(&mut c.almacen, "antiRecoil.vertical", json!(30));
        c.conectada = true;
        let avisos = hasta_al_dia(&mut s, &mut c, &a, &mut t);
        assert_eq!(a.lock().unwrap().activo().anti_recoil.vertical, 30.0, "gana la placa");
        assert!(avisos.iter().any(|x| x.contains("me quedo con los de la placa")), "{avisos:?}");
        let copia = std::fs::read_dir(&dir).unwrap().map(|e| e.unwrap().path())
            .find(|p| p.to_string_lossy().contains("copia-conflicto")).expect("copia de los de aquí");
        assert!(std::fs::read_to_string(copia).unwrap().contains("\"vertical\":70"));
    }

    #[test]
    fn el_estado_se_guarda_entre_arranques() {
        let (a, mut s, dir) = app();
        let mut c = placa();
        let mut t = 0.0;
        hasta_al_dia(&mut s, &mut c, &a, &mut t);
        let otra = Sincro::new(&dir.join("perfiles.json"), 0);
        assert_eq!(otra.g.ultima_rev, s.g.ultima_rev);
        assert!(!otra.g.cambios_locales);
    }

    #[test]
    fn firmware_antiguo_no_contesta_y_se_deja_en_paz() {
        let (a, mut s, _) = app();
        let mut c = placa();
        c.contesta = false;
        let mut t = 0.0;
        for _ in 0..8000 {
            t += 0.001;
            s.vuelta(&mut c, &a, t);
        }
        assert_eq!(s.estado(), "firmware antiguo");
    }
}

#[cfg(test)]
mod con_la_placa {
    use super::*;
    use crate::modelo::nuevo_id;

    /// Con la placa de verdad conectada por el cable: cargo test -- --ignored con_la_placa --nocapture
    #[test]
    #[ignore]
    fn sincroniza_con_la_placa_de_verdad() {
        let dir = std::env::temp_dir().join(format!("sincro-real-{}", nuevo_id()));
        std::fs::create_dir_all(&dir).unwrap();
        let a = Mutex::new(Almacen::cargar(dir.join("perfiles.json")));
        let mut s = Sincro::new(&dir.join("perfiles.json"), a.lock().unwrap().version);
        let mut esp = crate::esp32::Esp32::new();
        assert!(esp.conectar(), "no encuentro la placa");
        let inicio = std::time::Instant::now();
        let ahora = || inicio.elapsed().as_secs_f64();
        let mut paso = |s: &mut Sincro, esp: &mut crate::esp32::Esp32, hasta: f64| {
            while ahora() < hasta {
                if let Some(x) = s.vuelta(esp, &a, ahora()) {
                    println!("aviso: {x}");
                }
                std::thread::sleep(std::time::Duration::from_millis(1));
            }
        };
        paso(&mut s, &mut esp, 6.0);
        println!("tras conectar: {} ({} perfiles)", s.estado(), a.lock().unwrap().perfiles.len());
        assert_eq!(s.estado(), "al día");
        let original = a.lock().unwrap().activo().anti_recoil.vertical;
        a.lock().unwrap().poner_ruta("antiRecoil.vertical", serde_json::json!(original + 1.0));
        let t0 = ahora();
        paso(&mut s, &mut esp, t0 + 4.0);
        println!("tras cambiar aquí: {}", s.estado());
        // Otra «app» nueva lee la placa y tiene que ver el cambio
        let dir2 = std::env::temp_dir().join(format!("sincro-real-{}", nuevo_id()));
        std::fs::create_dir_all(&dir2).unwrap();
        let b = Mutex::new(Almacen::cargar(dir2.join("perfiles.json")));
        let mut s2 = Sincro::new(&dir2.join("perfiles.json"), b.lock().unwrap().version);
        let t1 = ahora();
        while ahora() < t1 + 6.0 {
            s2.vuelta(&mut esp, &b, ahora());
            std::thread::sleep(std::time::Duration::from_millis(1));
        }
        let leido = b.lock().unwrap().activo().anti_recoil.vertical;
        println!("otra app lee de la placa: vertical = {leido} (esperado {})", original + 1.0);
        assert_eq!(leido, original + 1.0);
        // Dejarlo como estaba
        a.lock().unwrap().poner_ruta("antiRecoil.vertical", serde_json::json!(original));
        let t2 = ahora();
        paso(&mut s, &mut esp, t2 + 4.0);
        println!("restaurado: {}", s.estado());
    }
}
