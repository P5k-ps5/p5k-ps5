// Medidor de tu propio control (port de app/MedidorControl.swift): graba lo que hace tu mano con el stick
// derecho mientras disparas (la entrada del DualSense, antes de que la app aplique nada) y te enseña cómo lo
// haces ráfaga a ráfaga. Solo mide: no cambia nada de lo que llega a la consola. El historial va en
// medidor.json, en la misma carpeta y con el mismo formato que la app de Mac (fechas en segundos desde 2001).
use std::path::PathBuf;

use serde::{Deserialize, Serialize};
use serde_json::{json, Value};

use crate::modelo::{nuevo_id, Boton, ConfigMedidor, Estado};

/// Segundos entre 1970 y 2001 (las fechas de Swift cuentan desde 2001)
const DESDE_2001: f64 = 978_307_200.0;

/// Lo que hiciste en una ráfaga. Valores en % del recorrido del stick. Campos en orden alfabético,
/// como los escribe la app de Mac (`sortedKeys`).
#[derive(Serialize, Deserialize, Clone, Debug, PartialEq)]
#[serde(default, rename_all = "camelCase")]
pub struct ResumenRafaga {
    pub bajada_media: f64,
    pub constancia: f64,
    pub duracion_ms: f64,
    /// Segundos desde el 1 de enero de 2001 (como Date en Swift)
    pub fecha: f64,
    pub id: String,
    pub lateral_max: f64,
    pub lateral_medio: f64,
    pub muestras: i64,
    pub perfil: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub reaccion_ms: Option<f64>,
    pub temblor: f64,
    pub tirones: i64,
}

impl Default for ResumenRafaga {
    fn default() -> Self {
        ResumenRafaga {
            bajada_media: 0.0, constancia: 0.0, duracion_ms: 0.0, fecha: ahora_2001(), id: nuevo_id(),
            lateral_max: 0.0, lateral_medio: 0.0, muestras: 0, perfil: String::new(), reaccion_ms: None,
            temblor: 0.0, tirones: 0,
        }
    }
}

pub fn ahora_2001() -> f64 {
    std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).map(|d| d.as_secs_f64()).unwrap_or(0.0) - DESDE_2001
}

pub const DT: f64 = 0.01; // una muestra cada 10 ms
pub const UMBRAL_REACCION: f64 = 0.10; // a partir de un 10 % de bajada cuenta como «empezar a corregir»
pub const UMBRAL_TIRON: f64 = 0.15;

/// x: lateral (-1 izquierda ... 1 derecha); abajo: vertical (-1 arriba ... 1 abajo)
pub fn analizar(x: &[f32], abajo: &[f32], perfil: &str, fecha: f64) -> ResumenRafaga {
    let mut r = ResumenRafaga { fecha, perfil: perfil.to_string(), ..Default::default() };
    let n = x.len().min(abajo.len());
    r.muestras = n as i64;
    r.duracion_ms = n as f64 * DT * 1000.0;
    if n == 0 {
        return r;
    }
    let inicio = (0..n).find(|&i| abajo[i] as f64 > UMBRAL_REACCION);
    r.reaccion_ms = inicio.map(|i| i as f64 * DT * 1000.0);
    let desde = inicio.unwrap_or(0);

    let (mut suma, mut suma2, mut lat) = (0.0f64, 0.0f64, 0.0f64);
    for i in desde..n {
        let v = abajo[i] as f64;
        suma += v;
        suma2 += v * v;
        lat += x[i] as f64;
    }
    let m = (n - desde) as f64;
    let media = suma / m;
    r.bajada_media = media * 100.0;
    r.constancia = (suma2 / m - media * media).max(0.0).sqrt() * 100.0;
    r.lateral_medio = lat / m * 100.0;
    r.lateral_max = (0..n).map(|i| (x[i] as f64).abs()).fold(f64::NEG_INFINITY, |a, b| if b > a { b } else { a }) * 100.0;

    let (mut temblor, mut cuenta) = (0.0f64, 0usize);
    for i in 1..n.max(1) {
        let dx = (x[i] - x[i - 1]) as f64;
        let dy = (abajo[i] - abajo[i - 1]) as f64;
        if dx.abs().max(dy.abs()) > UMBRAL_TIRON {
            r.tirones += 1;
        }
        if i >= 2 {
            temblor += ((x[i] - 2.0 * x[i - 1] + x[i - 2]) as f64).abs() + ((abajo[i] - 2.0 * abajo[i - 1] + abajo[i - 2]) as f64).abs();
            cuenta += 1;
        }
    }
    r.temblor = if cuenta > 0 { temblor / cuenta as f64 * 100.0 } else { 0.0 };
    r
}

#[derive(Clone, Debug, Default, PartialEq)]
pub struct Media {
    pub rafagas: usize,
    pub reaccion_ms: Option<f64>,
    pub sin_corregir: f64,
    pub bajada: f64,
    pub constancia: f64,
    pub lateral_medio: f64,
    pub lateral_abs: f64,
    pub temblor: f64,
    pub tirones: f64,
}

pub fn media(rs: &[ResumenRafaga]) -> Media {
    let mut m = Media { rafagas: rs.len(), ..Default::default() };
    if rs.is_empty() {
        return m;
    }
    let n = rs.len() as f64;
    let con: Vec<f64> = rs.iter().filter_map(|r| r.reaccion_ms).collect();
    m.reaccion_ms = if con.is_empty() { None } else { Some(con.iter().sum::<f64>() / con.len() as f64) };
    m.sin_corregir = (rs.len() - con.len()) as f64 / n;
    m.bajada = rs.iter().map(|r| r.bajada_media).sum::<f64>() / n;
    m.constancia = rs.iter().map(|r| r.constancia).sum::<f64>() / n;
    m.lateral_medio = rs.iter().map(|r| r.lateral_medio).sum::<f64>() / n;
    m.lateral_abs = rs.iter().map(|r| r.lateral_medio.abs()).sum::<f64>() / n;
    m.temblor = rs.iter().map(|r| r.temblor).sum::<f64>() / n;
    m.tirones = rs.iter().map(|r| r.tirones).sum::<i64>() as f64 / n;
    m
}

/// Observaciones orientativas sobre un grupo de ráfagas (los umbrales son aproximados, no una norma)
pub fn observaciones(rs: &[ResumenRafaga]) -> Vec<String> {
    if rs.is_empty() {
        return vec![];
    }
    let m = media(rs);
    let mut o = vec![];
    if let Some(rea) = m.reaccion_ms {
        if rea > 200.0 {
            o.push(format!("Tardas de media {} ms en empezar a bajar el stick.", rea as i64));
        }
    }
    if m.sin_corregir > 0.3 {
        o.push(format!("En {} % de las ráfagas no llegaste a bajar el stick.", (m.sin_corregir * 100.0) as i64));
    }
    if m.lateral_medio.abs() > 3.0 {
        o.push(format!("Tiendes a irte hacia la {} ({:.1} % de media).",
                       if m.lateral_medio > 0.0 { "derecha" } else { "izquierda" }, m.lateral_medio.abs()));
    }
    if m.constancia > 8.0 {
        o.push(format!("Tu bajada varía bastante dentro de cada ráfaga ({:.1} %).", m.constancia));
    }
    if m.tirones > 1.0 {
        o.push(format!("Haces correcciones a tirones ({:.1} por ráfaga).", m.tirones));
    }
    if o.is_empty() {
        o.push("Sin nada llamativo en estas ráfagas.".into());
    }
    o
}

/// Una ráfaga terminada: lateral, vertical y el perfil con el que se jugó
pub type Rafaga = (Vec<f32>, Vec<f32>, String);

/// Graba las ráfagas desde el hilo del motor. Sin reservar memoria en cada tick: dos búferes fijos
/// y solo se copia la ráfaga una vez, cuando termina.
pub struct GrabadorRafagas {
    x: Vec<f32>,
    abajo: Vec<f32>,
    n: usize,
    en_rafaga: bool,
    inicio: f64,
    muestreado_en: f64,
}

pub const CAPACIDAD: usize = 3000; // 30 s a una muestra cada 10 ms
pub const DURACION_MINIMA: f64 = 0.15; // ráfagas más cortas no se cuentan

impl GrabadorRafagas {
    pub fn new() -> Self {
        GrabadorRafagas { x: vec![0.0; CAPACIDAD], abajo: vec![0.0; CAPACIDAD], n: 0, en_rafaga: false, inicio: 0.0, muestreado_en: 0.0 }
    }

    /// Devuelve la ráfaga cuando termina
    pub fn tick(&mut self, e: &Estado, t: f64, c: &ConfigMedidor, perfil: &str) -> Option<Rafaga> {
        let dispara = pulsado(e, c.disparar);
        let p = dispara && (!c.solo_apuntando || pulsado(e, c.apuntar));
        if p {
            if !self.en_rafaga {
                self.en_rafaga = true;
                self.n = 0;
                self.inicio = t;
                self.muestreado_en = t - 1.0;
            }
            if t - self.muestreado_en >= DT - 1e-9 && self.n < CAPACIDAD {
                self.muestreado_en = t;
                self.x[self.n] = ((e.rx as f64 - 127.5) / 127.5) as f32;
                self.abajo[self.n] = ((e.ry as f64 - 127.5) / 127.5) as f32;
                self.n += 1;
            }
        } else if self.en_rafaga {
            self.en_rafaga = false;
            if t - self.inicio >= DURACION_MINIMA && self.n >= 10 {
                return Some((self.x[..self.n].to_vec(), self.abajo[..self.n].to_vec(), perfil.to_string()));
            }
        }
        None
    }

    /// Descarta la ráfaga en curso (al apagar el medidor o perder el mando)
    pub fn cortar(&mut self) {
        self.en_rafaga = false;
        self.n = 0;
    }
}

/// R2 y L2 cuentan por el gatillo analógico (a partir de un 10 %); el resto, por el botón
pub fn pulsado(e: &Estado, b: Boton) -> bool {
    match b {
        Boton::L2 => e.l2 > 25,
        Boton::R2 => e.r2 > 25,
        _ => e.pulsado(b),
    }
}

/// Historial de ráfagas (medidor.json)
pub struct Medidor {
    pub rafagas: Vec<ResumenRafaga>,
    /// La última ráfaga entera, para dibujarla (no se guarda en disco)
    pub ultima_x: Vec<f32>,
    pub ultima_abajo: Vec<f32>,
    archivo: PathBuf,
}

pub const MAX_GUARDADAS: usize = 1000;

impl Medidor {
    pub fn cargar(archivo: PathBuf) -> Medidor {
        let rafagas = std::fs::read(&archivo).ok().and_then(|d| serde_json::from_slice(&d).ok()).unwrap_or_default();
        Medidor { rafagas, ultima_x: vec![], ultima_abajo: vec![], archivo }
    }

    pub fn anadir(&mut self, r: ResumenRafaga, x: Vec<f32>, abajo: Vec<f32>) {
        self.rafagas.push(r);
        if self.rafagas.len() > MAX_GUARDADAS {
            let sobran = self.rafagas.len() - MAX_GUARDADAS;
            self.rafagas.drain(..sobran);
        }
        if !x.is_empty() {
            self.ultima_x = x;
            self.ultima_abajo = abajo;
        }
        self.guardar_ahora();
    }

    pub fn borrar_todo(&mut self) {
        self.rafagas.clear();
        self.ultima_x.clear();
        self.ultima_abajo.clear();
        self.guardar_ahora();
    }

    /// Media de cada día (el más reciente primero); el día, en segundos desde 1970 a las 0:00 de la hora local
    pub fn por_dia(&self) -> Vec<(f64, Media)> {
        let mut grupos: Vec<(f64, Vec<ResumenRafaga>)> = vec![];
        for r in &self.rafagas {
            let unix = r.fecha + DESDE_2001;
            let dia = (unix - crate::sistema::segundos_del_dia_local(unix)).round();
            match grupos.iter_mut().find(|g| g.0 == dia) {
                Some(g) => g.1.push(r.clone()),
                None => grupos.push((dia, vec![r.clone()])),
            }
        }
        grupos.sort_by(|a, b| b.0.partial_cmp(&a.0).unwrap());
        grupos.into_iter().map(|(d, rs)| (d, media(&rs))).collect()
    }

    pub fn guardar_ahora(&self) {
        if let Ok(datos) = serde_json::to_vec(&self.rafagas) {
            let tmp = self.archivo.with_extension("json.tmp");
            if std::fs::write(&tmp, datos).is_ok() {
                let _ = std::fs::rename(&tmp, &self.archivo);
            }
        }
    }

    /// Lo que pide el móvil en /medidor: las 20 últimas, su media, observaciones y días (como Delegado.medidorJSON).
    /// Además la última ráfaga entera, para dibujarla como en la ventana del Mac.
    pub fn json(&self) -> Value {
        let r1 = |v: f64| (v * 10.0).round() / 10.0;
        let media_json = |m: &Media| json!({
            "rafagas": m.rafagas, "reaccion": m.reaccion_ms.map(r1), "sinCorregir": r1(m.sin_corregir * 100.0),
            "bajada": r1(m.bajada), "constancia": r1(m.constancia), "lateral": r1(m.lateral_medio),
            "temblor": r1(m.temblor), "tirones": r1(m.tirones),
        });
        let desde = self.rafagas.len().saturating_sub(20);
        let ultimas = &self.rafagas[desde..];
        let lista: Vec<Value> = ultimas.iter().rev().map(|r| json!({
            "fecha": ((r.fecha + DESDE_2001) * 1000.0) as i64, "perfil": r.perfil, "duracion": r.duracion_ms as i64,
            "reaccion": r.reaccion_ms.map(r1), "bajada": r1(r.bajada_media), "constancia": r1(r.constancia),
            "lateral": r1(r.lateral_medio), "lateralMax": r1(r.lateral_max), "temblor": r1(r.temblor), "tirones": r.tirones,
        })).collect();
        let dias: Vec<Value> = self.por_dia().into_iter().take(14)
            .map(|(d, m)| json!({"dia": (d * 1000.0) as i64, "media": media_json(&m)}))
            .collect();
        let milesimas = |v: &[f32]| v.iter().map(|x| (*x as f64 * 1000.0).round() as i64).collect::<Vec<_>>();
        json!({
            "total": self.rafagas.len(), "rafagas": lista, "media": media_json(&media(ultimas)),
            "observaciones": observaciones(ultimas), "dias": dias,
            "ultima": {"x": milesimas(&self.ultima_x), "abajo": milesimas(&self.ultima_abajo)},
        })
    }
}

#[cfg(test)]
mod pruebas {
    use super::*;

    fn temporal(nombre: &str) -> PathBuf {
        let d = std::env::temp_dir().join(format!("puente-med-{}", nuevo_id()));
        std::fs::create_dir_all(&d).unwrap();
        d.join(nombre)
    }

    #[test]
    fn analisis_como_en_mac() {
        let n = 100;
        let bx = vec![0.05f32; n];
        let mut ba = vec![0f32; n];
        for v in ba.iter_mut().skip(15) {
            *v = 0.30;
        }
        let r = analizar(&bx, &ba, "", 0.0);
        assert!(r.muestras == 100 && r.duracion_ms == 1000.0);
        assert_eq!(r.reaccion_ms, Some(150.0));
        assert!((r.bajada_media - 30.0).abs() < 1e-4 && r.constancia < 1e-3);
        assert!((r.lateral_medio - 5.0).abs() < 1e-4 && (r.lateral_max - 5.0).abs() < 1e-4);
        assert_eq!(r.tirones, 1);
        let r = analizar(&[0.0; 50], &[0.0; 50], "", 0.0);
        assert!(r.reaccion_ms.is_none() && r.bajada_media == 0.0 && r.tirones == 0);
        let ba: Vec<f32> = (0..n).map(|i| if i % 2 == 0 { 0.10 } else { 0.40 }).collect();
        let bx = vec![0f32; n];
        let irregular = analizar(&bx, &ba, "", 0.0);
        let suave = analizar(&bx, &vec![0.25f32; n], "", 0.0);
        assert!((irregular.bajada_media - 25.0).abs() < 0.2 && irregular.constancia > 14.0 && suave.constancia < 1e-3);
        assert!(irregular.temblor > 50.0 && irregular.tirones > 90 && suave.temblor == 0.0);
        assert_eq!(analizar(&[], &[], "", 0.0).muestras, 0);
    }

    #[test]
    fn grabacion_como_en_mac() {
        let mut grab = GrabadorRafagas::new();
        let mut terminadas: Vec<Rafaga> = vec![];
        let mut cfg = ConfigMedidor { activo: true, disparar: Boton::R1, apuntar: Boton::L1, solo_apuntando: false };
        let jugar = |grab: &mut GrabadorRafagas, cfg: &ConfigMedidor, terminadas: &mut Vec<Rafaga>, desde: usize, hasta: usize, apuntando: bool| {
            for k in desde..hasta {
                let e = Estado { botones: Boton::R1.bit() | if apuntando { Boton::L1.bit() } else { 0 }, ry: 166, ..Default::default() };
                if let Some(r) = grab.tick(&e, k as f64 / 1000.0, cfg, "P") {
                    terminadas.push(r);
                }
            }
            if let Some(r) = grab.tick(&Estado::default(), hasta as f64 / 1000.0, cfg, "P") {
                terminadas.push(r);
            }
        };
        jugar(&mut grab, &cfg, &mut terminadas, 0, 600, true);
        assert!(terminadas.len() == 1 && terminadas[0].0.len() == 60 && (terminadas[0].1[0] - ((166.0 - 127.5) / 127.5) as f32).abs() < 1e-6 && terminadas[0].2 == "P");
        jugar(&mut grab, &cfg, &mut terminadas, 1000, 1100, true);
        assert_eq!(terminadas.len(), 1, "una ráfaga de 100 ms no cuenta");
        cfg.solo_apuntando = true;
        jugar(&mut grab, &cfg, &mut terminadas, 2000, 2500, false);
        assert_eq!(terminadas.len(), 1, "con «solo apuntando», sin apuntar no cuenta");
        jugar(&mut grab, &cfg, &mut terminadas, 3000, 3500, true);
        assert_eq!(terminadas.len(), 2);
        let e_gat = Estado { r2: 200, ..Default::default() };
        assert!(pulsado(&e_gat, Boton::R2) && !pulsado(&Estado::default(), Boton::R2));
        // Una ráfaga de 1000 s se corta en 3000 muestras, sin reservar memoria por tick
        let mut grab2 = GrabadorRafagas::new();
        let mut cuenta = 0;
        let mut e = Estado { botones: Boton::R2.bit(), r2: 255, ..Default::default() };
        let inicio = std::time::Instant::now();
        for k in 0..1_000_000u64 {
            e.ry = (128 + k % 60) as u8;
            if let Some(r) = grab2.tick(&e, k as f64 / 1000.0, &ConfigMedidor::default(), "") {
                cuenta += r.0.len();
            }
        }
        if let Some(r) = grab2.tick(&Estado::default(), 1000.0, &ConfigMedidor::default(), "") {
            cuenta += r.0.len();
        }
        assert!(cuenta == CAPACIDAD && inicio.elapsed().as_millis() < 2000);
    }

    #[test]
    fn historial_como_en_mac() {
        let f = temporal("medidor.json");
        let mut med = Medidor::cargar(f.clone());
        let ayer = ahora_2001() - 86400.0;
        let a: Vec<f32> = (0..100).map(|i| if i < 30 { 0.0 } else { 0.3 }).collect();
        med.anadir(analizar(&[0.05; 100], &a, "A", ayer), vec![], vec![]);
        let b: Vec<f32> = (0..80).map(|i| if i < 10 { 0.0 } else { 0.2 }).collect();
        med.anadir(analizar(&[-0.02; 80], &b, "B", ahora_2001()), vec![], vec![]);
        let med2 = Medidor::cargar(f.clone());
        assert!(med2.rafagas == med.rafagas && med2.rafagas.len() == 2, "se guarda y se recupera igual");
        let dias = med2.por_dia();
        assert!(dias.len() == 2 && dias[0].1.rafagas == 1, "agrupa por día (hoy primero)");
        let m = media(&med2.rafagas);
        assert!(m.reaccion_ms == Some(200.0) && (m.bajada - 25.0).abs() < 1e-4);
        let obs = observaciones(&[analizar(&[0.08; 60], &[0.0; 60], "", 0.0)]);
        assert!(obs.iter().any(|o| o.contains("derecha")) && obs.iter().any(|o| o.contains("no llegaste")));
        let mut med2 = med2;
        med2.borrar_todo();
        assert!(Medidor::cargar(f.clone()).rafagas.is_empty());
        for _ in 0..(MAX_GUARDADAS + 5) {
            med2.rafagas.push(ResumenRafaga::default());
        }
        med2.anadir(ResumenRafaga::default(), vec![], vec![]);
        assert_eq!(med2.rafagas.len(), MAX_GUARDADAS);
    }

    #[test]
    fn lee_el_formato_de_la_app_de_mac() {
        // Lo que escribe Swift: claves en orden, fecha desde 2001, sin reaccionMs si no hubo reacción
        let swift = r#"[{"bajadaMedia":30,"constancia":0,"duracionMs":1000,"fecha":783000000.25,"id":"9A7C5F3E-1111-4222-8333-944455556666","lateralMax":5,"lateralMedio":5,"muestras":100,"perfil":"P","reaccionMs":150,"temblor":0,"tirones":1},{"bajadaMedia":0,"constancia":0,"duracionMs":500,"fecha":783000001,"id":"9A7C5F3E-1111-4222-8333-944455556667","lateralMax":0,"lateralMedio":0,"muestras":50,"perfil":"","temblor":0,"tirones":0}]"#;
        let f = temporal("medidor.json");
        std::fs::write(&f, swift).unwrap();
        let med = Medidor::cargar(f.clone());
        assert_eq!(med.rafagas.len(), 2);
        assert_eq!(med.rafagas[0].reaccion_ms, Some(150.0));
        assert!(med.rafagas[1].reaccion_ms.is_none());
        med.guardar_ahora();
        // Se vuelve a escribir con las mismas claves y valores (Swift pone 30 y Rust 30.0: los dos leen ambos)
        let escrito = std::fs::read_to_string(&f).unwrap();
        let a: Vec<ResumenRafaga> = serde_json::from_str(swift).unwrap();
        let b: Vec<ResumenRafaga> = serde_json::from_str(&escrito).unwrap();
        assert_eq!(a, b);
        let claves = |t: &str| -> Vec<String> {
            let v: Value = serde_json::from_str(t).unwrap();
            v[0].as_object().unwrap().keys().cloned().collect()
        };
        assert_eq!(claves(swift), claves(&escrito));
        let j = med.json();
        assert_eq!(j["rafagas"][0]["fecha"], json!(((783000001.0 + DESDE_2001) * 1000.0) as i64), "la más reciente primero, en ms desde 1970");
    }
}
