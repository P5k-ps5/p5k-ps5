// Perfiles, ajustes y todo lo que se guarda en perfiles.json. Es el mismo formato que la app de Mac
// (app/Modelo.swift): mismos nombres de campo, mismos valores por defecto, identificadores en mayúsculas.
// Lo que falte en un archivo antiguo se lee con su valor por defecto (#[serde(default)]).
#![allow(dead_code)]

use std::collections::BTreeMap;
use std::path::PathBuf;

use serde::{Deserialize, Serialize};
use serde_json::Value;

// MARK: - Botones y estado del mando

/// Los 14 primeros van en el orden de los bits del mando de PS4; la cruceta va como 4 botones más
/// para poder reasignarla. El de silenciar solo existe en el DualSense y no llega nunca a la consola.
#[derive(Serialize, Deserialize, Clone, Copy, Debug, PartialEq, Eq, Hash, PartialOrd, Ord)]
#[serde(rename_all = "lowercase")]
pub enum Boton {
    Cuadrado, X, Circulo, Triangulo, L1, R1, L2, R2,
    Share, Options, L3, R3, Ps, Tactil,
    Arriba, Derecha, Abajo, Izquierda,
    Silenciar,
}

impl Boton {
    pub const TODOS: [Boton; 19] = [
        Boton::Cuadrado, Boton::X, Boton::Circulo, Boton::Triangulo, Boton::L1, Boton::R1, Boton::L2, Boton::R2,
        Boton::Share, Boton::Options, Boton::L3, Boton::R3, Boton::Ps, Boton::Tactil,
        Boton::Arriba, Boton::Derecha, Boton::Abajo, Boton::Izquierda, Boton::Silenciar,
    ];

    pub fn indice(self) -> u32 {
        Boton::TODOS.iter().position(|b| *b == self).unwrap() as u32
    }
    pub fn bit(self) -> u32 {
        1 << self.indice()
    }
    pub fn llega_a_la_consola(self) -> bool {
        self != Boton::Silenciar
    }
    pub fn clave(self) -> &'static str {
        match self {
            Boton::Cuadrado => "cuadrado", Boton::X => "x", Boton::Circulo => "circulo", Boton::Triangulo => "triangulo",
            Boton::L1 => "l1", Boton::R1 => "r1", Boton::L2 => "l2", Boton::R2 => "r2",
            Boton::Share => "share", Boton::Options => "options", Boton::L3 => "l3", Boton::R3 => "r3",
            Boton::Ps => "ps", Boton::Tactil => "tactil", Boton::Arriba => "arriba", Boton::Derecha => "derecha",
            Boton::Abajo => "abajo", Boton::Izquierda => "izquierda", Boton::Silenciar => "silenciar",
        }
    }
    pub fn de_clave(c: &str) -> Option<Boton> {
        Boton::TODOS.iter().copied().find(|b| b.clave() == c)
    }
    pub fn corto(self) -> &'static str {
        match self {
            Boton::Cuadrado => "□", Boton::X => "✕", Boton::Circulo => "○", Boton::Triangulo => "△",
            Boton::L1 => "L1", Boton::R1 => "R1", Boton::L2 => "L2", Boton::R2 => "R2",
            Boton::Share => "Create", Boton::Options => "Opt", Boton::L3 => "L3", Boton::R3 => "R3",
            Boton::Ps => "PS", Boton::Tactil => "Táctil", Boton::Arriba => "↑", Boton::Derecha => "→",
            Boton::Abajo => "↓", Boton::Izquierda => "←", Boton::Silenciar => "Mic",
        }
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize)]
pub struct Estado {
    pub botones: u32,
    pub lx: u8, pub ly: u8,          // Y pequeña = arriba, como en el mando
    pub rx: u8, pub ry: u8,
    pub l2: u8, pub r2: u8,
}

impl Default for Estado {
    fn default() -> Self {
        Estado { botones: 0, lx: 128, ly: 128, rx: 128, ry: 128, l2: 0, r2: 0 }
    }
}

impl Estado {
    pub fn pulsado(&self, b: Boton) -> bool {
        self.botones & b.bit() != 0
    }
}

/// Identificador nuevo, en mayúsculas como los de Swift
pub fn nuevo_id() -> String {
    uuid::Uuid::new_v4().to_string().to_uppercase()
}

// MARK: - Perfil

#[derive(Serialize, Deserialize, Clone, Debug, PartialEq)]
#[serde(default, rename_all = "camelCase")]
pub struct AjusteStick {
    pub zona_muerta: f64,
    pub forma_cruz: bool,
    pub zona_externa: f64,
    pub anti_zona_muerta: f64,
    pub curva: f64,
    pub sens_x: f64,
    pub sens_y: f64,
    pub limite: f64,
    pub suavizado: f64,
    pub aceleracion: f64,
    pub tiempo_aceleracion: f64,
    pub invertir_x: bool,
    pub invertir_y: bool,
}

impl Default for AjusteStick {
    fn default() -> Self {
        AjusteStick {
            zona_muerta: 5.0, forma_cruz: false, zona_externa: 100.0, anti_zona_muerta: 0.0, curva: 1.0,
            sens_x: 100.0, sens_y: 100.0, limite: 100.0, suavizado: 0.0, aceleracion: 0.0,
            tiempo_aceleracion: 300.0, invertir_x: false, invertir_y: false,
        }
    }
}

#[derive(Serialize, Deserialize, Clone, Debug, PartialEq)]
#[serde(default, rename_all = "camelCase")]
pub struct AjusteGatillo {
    pub zona_muerta: f64,
    pub zona_externa: f64,
    pub curva: f64,
    pub disparo_rapido: bool,
}

impl Default for AjusteGatillo {
    fn default() -> Self {
        AjusteGatillo { zona_muerta: 0.0, zona_externa: 100.0, curva: 1.0, disparo_rapido: false }
    }
}

#[derive(Serialize, Deserialize, Clone, Debug, PartialEq)]
#[serde(default, rename_all = "camelCase")]
pub struct Turbo {
    pub id: String,
    pub boton: Boton,
    pub hz: f64,
    pub ciclo: f64,
    pub activo: bool,
}

impl Default for Turbo {
    fn default() -> Self {
        Turbo { id: nuevo_id(), boton: Boton::X, hz: 10.0, ciclo: 50.0, activo: true }
    }
}

#[derive(Serialize, Deserialize, Clone, Debug, PartialEq)]
#[serde(default, rename_all = "camelCase")]
pub struct PasoMacro {
    pub id: String,
    pub botones: Vec<Boton>,
    pub ms: i64,
}

impl Default for PasoMacro {
    fn default() -> Self {
        PasoMacro { id: nuevo_id(), botones: vec![], ms: 100 }
    }
}

#[derive(Serialize, Deserialize, Clone, Debug, PartialEq)]
#[serde(default, rename_all = "camelCase")]
pub struct Macro {
    pub id: String,
    pub nombre: String,
    pub activa: bool,
    pub disparador: Boton,
    pub repetir: bool,
    pub bloquear_disparador: bool,
    pub pasos: Vec<PasoMacro>,
    pub atajo: bool,
    pub atajo_mantener: Boton,
    pub atajo_pulsar: Boton,
}

impl Default for Macro {
    fn default() -> Self {
        Macro {
            id: nuevo_id(), nombre: "Macro nueva".into(), activa: true, disparador: Boton::R3, repetir: false,
            bloquear_disparador: true,
            pasos: vec![PasoMacro { botones: vec![Boton::X], ms: 100, ..Default::default() }, PasoMacro::default()],
            atajo: false, atajo_mantener: Boton::L1, atajo_pulsar: Boton::Derecha,
        }
    }
}

#[derive(Serialize, Deserialize, Clone, Copy, Debug, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub enum TipoWidget {
    AntiRecoil, Ayuda, Pausa, Turbos, Turbo, Macros, Macro,
}

impl TipoWidget {
    pub fn clave(self) -> &'static str {
        match self {
            TipoWidget::AntiRecoil => "antiRecoil", TipoWidget::Ayuda => "ayuda", TipoWidget::Pausa => "pausa",
            TipoWidget::Turbos => "turbos", TipoWidget::Turbo => "turbo", TipoWidget::Macros => "macros",
            TipoWidget::Macro => "macro",
        }
    }
    pub fn de_clave(c: &str) -> Option<TipoWidget> {
        serde_json::from_value(Value::String(c.into())).ok()
    }
}

/// Un botón de «En vivo» para encender o apagar algo sin usar el mando
#[derive(Serialize, Deserialize, Clone, Debug, PartialEq)]
#[serde(default, rename_all = "camelCase")]
pub struct Widget {
    pub id: String,
    pub tipo: TipoWidget,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub objetivo: Option<String>,
}

impl Default for Widget {
    fn default() -> Self {
        Widget { id: nuevo_id(), tipo: TipoWidget::AntiRecoil, objetivo: None }
    }
}

impl Widget {
    pub fn de(tipo: TipoWidget, objetivo: Option<String>) -> Widget {
        Widget { id: nuevo_id(), tipo, objetivo }
    }
}

#[derive(Serialize, Deserialize, Clone, Debug, PartialEq)]
#[serde(default, rename_all = "camelCase")]
pub struct AntiRecoil {
    pub activo: bool,
    pub vertical: f64,
    pub progresivo: bool,
    pub vertical_final: f64,
    pub transicion_ms: f64,
    pub horizontal: f64,
    pub retardo_ms: f64,
    pub disparar: Boton,
    pub apuntar: Boton,
    pub solo_apuntando: bool,
    pub atajo: bool,
    pub atajo_mantener: Boton,
    pub atajo_pulsar: Boton,
}

impl Default for AntiRecoil {
    fn default() -> Self {
        AntiRecoil {
            activo: false, vertical: 20.0, progresivo: false, vertical_final: 10.0, transicion_ms: 1000.0,
            horizontal: 0.0, retardo_ms: 0.0, disparar: Boton::R2, apuntar: Boton::L2, solo_apuntando: true,
            atajo: true, atajo_mantener: Boton::L2, atajo_pulsar: Boton::Abajo,
        }
    }
}

#[derive(Serialize, Deserialize, Clone, Copy, Debug, PartialEq, Eq)]
#[serde(rename_all = "lowercase")]
pub enum Forma {
    Circulo,
    Temblor,
}

#[derive(Serialize, Deserialize, Clone, Debug, PartialEq)]
#[serde(default, rename_all = "camelCase")]
pub struct LimitesAyuda {
    pub activos: bool,
    pub tamano_min: f64, pub tamano_max: f64,
    pub hz_min: f64, pub hz_max: f64,
    pub entrada_min: f64, pub entrada_max: f64,
}

impl Default for LimitesAyuda {
    fn default() -> Self {
        LimitesAyuda {
            activos: false, tamano_min: 1.0, tamano_max: 30.0, hz_min: 2.0, hz_max: 40.0,
            entrada_min: 0.0, entrada_max: 600.0,
        }
    }
}

#[derive(Serialize, Deserialize, Clone, Debug, PartialEq)]
#[serde(default, rename_all = "camelCase")]
pub struct VarianteAyuda {
    pub id: String,
    pub nombre: String,
    pub base: i64,
    pub forma: Forma,
    pub tamano: f64, pub hz: f64, pub entrada_ms: f64, pub ceder: f64,
}

impl Default for VarianteAyuda {
    fn default() -> Self {
        VarianteAyuda {
            id: nuevo_id(), nombre: "Variante".into(), base: -1, forma: Forma::Circulo,
            tamano: 8.0, hz: 12.0, entrada_ms: 150.0, ceder: 70.0,
        }
    }
}

/// Mueve el stick derecho en círculos o temblores diminutos mientras apuntas
#[derive(Serialize, Deserialize, Clone, Debug, PartialEq)]
#[serde(default, rename_all = "camelCase")]
pub struct AyudaApuntado {
    pub activo: bool,
    pub forma: Forma,
    pub tamano: f64,
    pub hz: f64,
    pub entrada_ms: f64,
    pub ceder: f64,
    pub boton: Boton,
    pub tambien_disparando: bool,
    pub atajo: bool,
    pub atajo_mantener: Boton,
    pub atajo_pulsar: Boton,
    pub cambio_activo: bool,
    pub cambio_mantener: Boton,
    pub cambio_siguiente: Boton,
    pub cambio_anterior: Boton,
    pub limites: LimitesAyuda,
    pub variantes: Vec<VarianteAyuda>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub variante_activa: Option<String>,
}

impl Default for AyudaApuntado {
    fn default() -> Self {
        AyudaApuntado {
            activo: false, forma: Forma::Circulo, tamano: 8.0, hz: 12.0, entrada_ms: 150.0, ceder: 70.0,
            boton: Boton::L2, tambien_disparando: false, atajo: true, atajo_mantener: Boton::L2,
            atajo_pulsar: Boton::Arriba, cambio_activo: true, cambio_mantener: Boton::L1,
            cambio_siguiente: Boton::Derecha, cambio_anterior: Boton::Izquierda,
            limites: LimitesAyuda::default(), variantes: vec![], variante_activa: None,
        }
    }
}

pub struct PatronAyuda {
    pub nombre: &'static str,
    pub forma: Forma,
    pub tamano: f64, pub hz: f64, pub entrada_ms: f64, pub ceder: f64,
}

/// Patrones listos: dos movimientos en tres intensidades
pub const PATRONES: [PatronAyuda; 6] = [
    PatronAyuda { nombre: "Círculos discretos", forma: Forma::Circulo, tamano: 4.0, hz: 8.0, entrada_ms: 300.0, ceder: 85.0 },
    PatronAyuda { nombre: "Círculos medios", forma: Forma::Circulo, tamano: 8.0, hz: 12.0, entrada_ms: 150.0, ceder: 70.0 },
    PatronAyuda { nombre: "Círculos fuertes", forma: Forma::Circulo, tamano: 14.0, hz: 16.0, entrada_ms: 80.0, ceder: 50.0 },
    PatronAyuda { nombre: "Temblor discreto", forma: Forma::Temblor, tamano: 4.0, hz: 8.0, entrada_ms: 300.0, ceder: 85.0 },
    PatronAyuda { nombre: "Temblor medio", forma: Forma::Temblor, tamano: 8.0, hz: 12.0, entrada_ms: 150.0, ceder: 70.0 },
    PatronAyuda { nombre: "Temblor fuerte", forma: Forma::Temblor, tamano: 14.0, hz: 16.0, entrada_ms: 80.0, ceder: 50.0 },
];

pub enum OpcionAyuda {
    Patron(usize),
    Variante(String),
}

impl AyudaApuntado {
    pub fn recortar(v: f64, a: f64, b: f64) -> f64 {
        v.max(a.min(b)).min(a.max(b))
    }

    /// Tamaño, velocidad y entrada tal como los usa el motor: recortados si hay límites activos
    pub fn recortados(&self, tamano: f64, hz: f64, entrada_ms: f64) -> (f64, f64, f64) {
        if !self.limites.activos {
            return (tamano, hz, entrada_ms);
        }
        let l = &self.limites;
        (
            AyudaApuntado::recortar(tamano, l.tamano_min, l.tamano_max),
            AyudaApuntado::recortar(hz, l.hz_min, l.hz_max),
            AyudaApuntado::recortar(entrada_ms, l.entrada_min, l.entrada_max),
        )
    }

    /// (tamaño, hz, entrada, ceder) efectivos
    pub fn efectivos(&self) -> (f64, f64, f64, f64) {
        let r = self.recortados(self.tamano, self.hz, self.entrada_ms);
        (r.0, r.1, r.2, self.ceder)
    }

    pub fn limitado(&self) -> bool {
        let e = self.efectivos();
        e.0 != self.tamano || e.1 != self.hz || e.2 != self.entrada_ms
    }

    pub fn normalizar(&mut self) {
        let e = self.efectivos();
        self.tamano = e.0;
        self.hz = e.1;
        self.entrada_ms = e.2;
    }

    pub fn variante_seleccionada(&self) -> Option<&VarianteAyuda> {
        let id = self.variante_activa.as_ref()?;
        self.variantes.iter().find(|v| &v.id == id)
    }

    pub fn variante_modificada(&self) -> bool {
        let Some(v) = self.variante_seleccionada() else { return false };
        let r = self.recortados(v.tamano, v.hz, v.entrada_ms);
        !(v.forma == self.forma && r.0 == self.tamano && r.1 == self.hz && r.2 == self.entrada_ms && v.ceder == self.ceder)
    }

    pub fn aplicar(&mut self, v: &VarianteAyuda) {
        self.forma = v.forma;
        self.tamano = v.tamano;
        self.hz = v.hz;
        self.entrada_ms = v.entrada_ms;
        self.ceder = v.ceder;
        self.variante_activa = Some(v.id.clone());
        self.normalizar();
    }

    pub fn guardar_como_variante(&mut self, nombre: &str) {
        let limpio = nombre.trim();
        let v = VarianteAyuda {
            nombre: if limpio.is_empty() { format!("Variante {}", self.variantes.len() + 1) } else { limpio.to_string() },
            base: self.indice_patron().map(|i| i as i64).unwrap_or(-1),
            forma: self.forma, tamano: self.tamano, hz: self.hz, entrada_ms: self.entrada_ms, ceder: self.ceder,
            ..Default::default()
        };
        self.variante_activa = Some(v.id.clone());
        self.variantes.push(v);
    }

    pub fn actualizar_variante_activa(&mut self) {
        let Some(id) = self.variante_activa.clone() else { return };
        let (forma, tamano, hz, entrada, ceder) = (self.forma, self.tamano, self.hz, self.entrada_ms, self.ceder);
        if let Some(v) = self.variantes.iter_mut().find(|v| v.id == id) {
            v.forma = forma;
            v.tamano = tamano;
            v.hz = hz;
            v.entrada_ms = entrada;
            v.ceder = ceder;
        }
    }

    pub fn borrar_variante(&mut self, id: &str) {
        self.variantes.retain(|v| v.id != id);
        if self.variante_activa.as_deref() == Some(id) {
            self.variante_activa = None;
        }
    }

    pub fn opciones(&self) -> Vec<OpcionAyuda> {
        (0..PATRONES.len()).map(OpcionAyuda::Patron)
            .chain(self.variantes.iter().map(|v| OpcionAyuda::Variante(v.id.clone())))
            .collect()
    }

    pub fn opcion_actual(&self) -> Option<usize> {
        if let Some(v) = self.variante_seleccionada() {
            if !self.variante_modificada() {
                if let Some(i) = self.variantes.iter().position(|x| x.id == v.id) {
                    return Some(PATRONES.len() + i);
                }
            }
        }
        self.indice_patron()
    }

    pub fn aplicar_opcion(&mut self, i: usize) -> String {
        match self.opciones().into_iter().nth(i) {
            Some(OpcionAyuda::Patron(p)) => {
                self.aplicar_patron(p);
                PATRONES[p].nombre.to_string()
            }
            Some(OpcionAyuda::Variante(id)) => {
                let Some(v) = self.variantes.iter().find(|v| v.id == id).cloned() else { return String::new() };
                self.aplicar(&v);
                v.nombre
            }
            None => String::new(),
        }
    }

    pub fn indice_patron(&self) -> Option<usize> {
        PATRONES.iter().position(|p| {
            let r = self.recortados(p.tamano, p.hz, p.entrada_ms);
            p.forma == self.forma && r.0 == self.tamano && r.1 == self.hz && r.2 == self.entrada_ms && p.ceder == self.ceder
        })
    }

    pub fn aplicar_patron(&mut self, i: usize) {
        let p = &PATRONES[i];
        self.forma = p.forma;
        self.tamano = p.tamano;
        self.hz = p.hz;
        self.entrada_ms = p.entrada_ms;
        self.ceder = p.ceder;
        self.variante_activa = None;
        self.normalizar();
    }
}

#[derive(Serialize, Deserialize, Clone, Debug, PartialEq)]
#[serde(default, rename_all = "camelCase")]
pub struct Perfil {
    pub id: String,
    pub nombre: String,
    pub intercambiar_sticks: bool,
    pub izq: AjusteStick,
    pub der: AjusteStick,
    pub l2: AjusteGatillo,
    pub r2: AjusteGatillo,
    pub reasignar: BTreeMap<String, String>,
    pub alternar: Vec<Boton>,
    pub pulsacion_larga: BTreeMap<String, String>,
    pub ms_larga: f64,
    pub turbos: Vec<Turbo>,
    pub macros: Vec<Macro>,
    pub anti_recoil: AntiRecoil,
    pub ayuda: AyudaApuntado,
    pub widgets: Vec<Widget>,
    pub color: String,
    pub en_ciclo: bool,
}

impl Default for Perfil {
    fn default() -> Self {
        Perfil {
            id: nuevo_id(), nombre: "Perfil".into(), intercambiar_sticks: false,
            izq: AjusteStick::default(), der: AjusteStick::default(),
            l2: AjusteGatillo::default(), r2: AjusteGatillo::default(),
            reasignar: BTreeMap::new(), alternar: vec![], pulsacion_larga: BTreeMap::new(), ms_larga: 300.0,
            turbos: vec![], macros: vec![], anti_recoil: AntiRecoil::default(), ayuda: AyudaApuntado::default(),
            widgets: vec![], color: "#0050FF".into(), en_ciclo: true,
        }
    }
}

pub const COLORES: [&str; 8] = ["#0050FF", "#FF2D2D", "#00C853", "#FFB300", "#B000FF", "#00E5FF", "#FF4FA3", "#FFFFFF"];

impl Perfil {
    pub fn con_nombre(nombre: &str) -> Perfil {
        Perfil { nombre: nombre.into(), ..Default::default() }
    }

    /// Qué botón recibe la consola por `b` (None = anulado)
    pub fn destino(&self, b: Boton) -> Option<Boton> {
        match self.reasignar.get(b.clave()) {
            None => if b.llega_a_la_consola() { Some(b) } else { None },
            Some(d) => Boton::de_clave(d),
        }
    }
}

#[derive(Serialize, Deserialize, Clone, Debug, PartialEq)]
#[serde(default, rename_all = "camelCase")]
pub struct LimitesMonitor {
    pub activo: bool,
    pub max_abs: f64,
    pub max_salto: f64,
    pub max_velocidad: f64,
    pub max_aceleracion: f64,
    pub max_cambios_signo: f64,
}

impl Default for LimitesMonitor {
    fn default() -> Self {
        LimitesMonitor { activo: false, max_abs: 1.0, max_salto: 0.30, max_velocidad: 25.0, max_aceleracion: 4000.0, max_cambios_signo: 0.6 }
    }
}

#[derive(Serialize, Deserialize, Clone, Debug, PartialEq)]
#[serde(default, rename_all = "camelCase")]
pub struct ConfigMedidor {
    pub activo: bool,
    pub disparar: Boton,
    pub apuntar: Boton,
    pub solo_apuntando: bool,
}

impl Default for ConfigMedidor {
    fn default() -> Self {
        ConfigMedidor { activo: false, disparar: Boton::R2, apuntar: Boton::L2, solo_apuntando: false }
    }
}

/// Ajustes que no dependen del perfil
#[derive(Serialize, Deserialize, Clone, Debug, PartialEq)]
#[serde(default, rename_all = "camelCase")]
pub struct AjustesGenerales {
    pub cambio_perfil: bool,
    pub cambio_mantener: Boton,
    pub cambio_siguiente: Boton,
    pub cambio_anterior: Boton,
    pub decir_nombre: bool,
    pub avisos_voz: bool,
    pub servidor_movil: bool,
    pub clave: String,
    pub ajuste_mando: bool,
    pub ajuste_mantener: Boton,
    pub fuerza_mando: bool,
    pub fuerza_mantener: Boton,
    pub monitor: LimitesMonitor,
    pub medidor: ConfigMedidor,
}

impl Default for AjustesGenerales {
    fn default() -> Self {
        AjustesGenerales {
            cambio_perfil: true, cambio_mantener: Boton::Tactil, cambio_siguiente: Boton::Derecha,
            cambio_anterior: Boton::Izquierda, decir_nombre: true, avisos_voz: true, servidor_movil: true,
            clave: nueva_clave(), ajuste_mando: true, ajuste_mantener: Boton::Share, fuerza_mando: true,
            fuerza_mantener: Boton::Silenciar, monitor: LimitesMonitor::default(),
            medidor: ConfigMedidor::default(),
        }
    }
}

/// 10 caracteres sin letras que se confundan (sin 0/O, 1/I/L)
pub fn nueva_clave() -> String {
    let letras: Vec<char> = "ABCDEFGHJKMNPQRSTUVWXYZ23456789".chars().collect();
    let azar = uuid::Uuid::new_v4();
    azar.as_bytes().iter().take(10).map(|b| letras[*b as usize % letras.len()]).collect()
}

// MARK: - Combinaciones del mando

/// Mantener un botón (Mic por defecto) y pulsar ↑/↓ sube o baja la fuerza del anti-recoil, y ←/→ mueve su
/// corrección lateral. Mientras se mantiene, la cruceta se quita de la entrada para que no llegue a la consola.
/// Devuelve (mantenido, paso de la fuerza, paso lateral).
pub fn combo_fuerza(e: &mut Estado, flanco: u32, g: &AjustesGenerales) -> (bool, i32, i32) {
    if !(g.fuerza_mando && e.pulsado(g.fuerza_mantener)) {
        return (false, 0, 0);
    }
    let paso = if flanco & Boton::Arriba.bit() != 0 { 1 } else if flanco & Boton::Abajo.bit() != 0 { -1 } else { 0 };
    let lateral = if flanco & Boton::Derecha.bit() != 0 { 1 } else if flanco & Boton::Izquierda.bit() != 0 { -1 } else { 0 };
    e.botones &= !(Boton::Arriba.bit() | Boton::Abajo.bit() | Boton::Derecha.bit() | Boton::Izquierda.bit());
    (true, paso, lateral)
}

/// Las macros cuya combinación se acaba de completar
pub fn combo_macros(e: &Estado, flanco: u32, p: &Perfil) -> Vec<String> {
    p.macros.iter()
        .filter(|m| m.atajo && flanco & m.atajo_pulsar.bit() != 0 && (m.atajo_mantener == m.atajo_pulsar || e.pulsado(m.atajo_mantener)))
        .map(|m| m.id.clone())
        .collect()
}

pub struct AjusteRapido {
    pub nombre: &'static str,
    pub min: f64,
    pub max: f64,
    pub paso: f64,
    pub leer: fn(&Perfil) -> f64,
    pub escribir: fn(&mut Perfil, f64),
}

pub const AJUSTES_RAPIDOS: [AjusteRapido; 6] = [
    AjusteRapido { nombre: "Anti-recoil fuerza", min: 0.0, max: 100.0, paso: 2.0, leer: |p| p.anti_recoil.vertical, escribir: |p, v| p.anti_recoil.vertical = v },
    AjusteRapido { nombre: "Anti-recoil lateral", min: -50.0, max: 50.0, paso: 2.0, leer: |p| p.anti_recoil.horizontal, escribir: |p, v| p.anti_recoil.horizontal = v },
    AjusteRapido { nombre: "Ayuda tamaño", min: 1.0, max: 30.0, paso: 1.0, leer: |p| p.ayuda.tamano, escribir: |p, v| p.ayuda.tamano = v },
    AjusteRapido { nombre: "Ayuda velocidad", min: 2.0, max: 40.0, paso: 1.0, leer: |p| p.ayuda.hz, escribir: |p, v| p.ayuda.hz = v },
    AjusteRapido { nombre: "Sensibilidad horizontal", min: 20.0, max: 200.0, paso: 5.0, leer: |p| p.der.sens_x, escribir: |p, v| p.der.sens_x = v },
    AjusteRapido { nombre: "Sensibilidad vertical", min: 20.0, max: 200.0, paso: 5.0, leer: |p| p.der.sens_y, escribir: |p, v| p.der.sens_y = v },
];

/// Número como lo escribe Swift con Int(x.rounded())
pub fn entero(v: f64) -> i64 {
    v.round() as i64
}

// MARK: - Perfiles guardados

#[derive(Serialize, Deserialize, Default)]
#[serde(default)]
struct Fichero {
    perfiles: Vec<Perfil>,
    #[serde(skip_serializing_if = "Option::is_none")]
    activo: Option<String>,
    generales: AjustesGenerales,
}

/// La misma carpeta que la app de Mac; en Windows, %APPDATA%\Puente de mando
/// (la placa no tiene carpetas de usuario: su motor le pasa la ruta del archivo)
#[cfg(not(target_os = "espidf"))]
pub fn archivo_por_defecto() -> PathBuf {
    let base = dirs::data_dir().unwrap_or_else(|| PathBuf::from("."));
    let carpeta = base.join("Puente de mando");
    let _ = std::fs::create_dir_all(&carpeta);
    carpeta.join("perfiles.json")
}

pub struct Almacen {
    pub perfiles: Vec<Perfil>,
    pub activo_id: String,
    pub generales: AjustesGenerales,
    pub ajuste_indice: usize,
    archivo: PathBuf,
    /// Hay cambios sin guardar (se guardan desde fuera, con un poco de retraso)
    pub sucio: bool,
    /// Sube con cada cambio: el motor recoge el perfil nuevo cuando cambia
    pub version: u64,
}

impl Almacen {
    pub fn cargar(archivo: PathBuf) -> Almacen {
        let leido: Option<Fichero> = std::fs::read(&archivo).ok().and_then(|d| serde_json::from_slice(&d).ok());
        let mut a = match leido {
            Some(f) if !f.perfiles.is_empty() => {
                let activo = f.activo.filter(|id| f.perfiles.iter().any(|p| &p.id == id)).unwrap_or_else(|| f.perfiles[0].id.clone());
                Almacen { perfiles: f.perfiles, activo_id: activo, generales: f.generales, ajuste_indice: 0, archivo, sucio: false, version: 0 }
            }
            _ => {
                let p = Perfil::con_nombre("Normal");
                Almacen { activo_id: p.id.clone(), perfiles: vec![p], generales: AjustesGenerales::default(), ajuste_indice: 0, archivo, sucio: false, version: 0 }
            }
        };
        a.cambiado();
        a.guardar_ahora(); // guarda ya la clave, si es nueva
        a
    }

    fn cambiado(&mut self) {
        self.sucio = true;
        self.version += 1;
    }

    pub fn guardar_ahora(&mut self) {
        let f = Fichero { perfiles: self.perfiles.clone(), activo: Some(self.activo_id.clone()), generales: self.generales.clone() };
        if let Ok(datos) = serde_json::to_vec_pretty(&f) {
            let tmp = self.archivo.with_extension("json.tmp");
            if std::fs::write(&tmp, datos).is_ok() {
                let _ = std::fs::rename(&tmp, &self.archivo);
            }
        }
        self.sucio = false;
    }

    pub fn archivo(&self) -> &std::path::Path {
        &self.archivo
    }

    // MARK: - Sincronización con la placa (los mismos ajustes en la placa y en las apps)

    /// Lo que se sincroniza: los perfiles, el activo y los ajustes generales, sin lo que es de cada aparato
    /// (la clave del acceso por la red y si ese acceso está encendido). JSON compacto con las claves en orden
    /// fijo: el mismo contenido da siempre el mismo texto.
    pub fn ajustes_sincronizados(&self) -> String {
        let mut generales = serde_json::to_value(&self.generales).unwrap_or(Value::Null);
        if let Some(o) = generales.as_object_mut() {
            o.remove("clave");
            o.remove("servidorMovil");
        }
        serde_json::json!({"perfiles": self.perfiles, "activo": self.activo_id, "generales": generales}).to_string()
    }

    /// Pone unos ajustes sincronizados (de la placa o de una app). Se queda con su clave y su acceso por la red.
    pub fn poner_ajustes_sincronizados(&mut self, json: &str) -> Result<(), String> {
        let v: Value = serde_json::from_str(json).map_err(|e| format!("JSON no válido: {e}"))?;
        let perfiles: Vec<Perfil> = serde_json::from_value(v.get("perfiles").cloned().unwrap_or(Value::Null))
            .map_err(|e| format!("perfiles no válidos: {e}"))?;
        if perfiles.is_empty() {
            return Err("no hay ningún perfil".into());
        }
        let mut g: AjustesGenerales = serde_json::from_value(v.get("generales").cloned().unwrap_or(serde_json::json!({})))
            .map_err(|e| format!("ajustes generales no válidos: {e}"))?;
        g.clave = self.generales.clave.clone();
        g.servidor_movil = self.generales.servidor_movil;
        let activo = v.get("activo").and_then(|x| x.as_str()).unwrap_or("");
        self.activo_id = if perfiles.iter().any(|p| p.id == activo) { activo.to_string() } else { perfiles[0].id.clone() };
        self.perfiles = perfiles;
        self.poner_generales(g);
        Ok(())
    }

    pub fn activo(&self) -> &Perfil {
        self.perfiles.iter().find(|p| p.id == self.activo_id).unwrap_or(&self.perfiles[0])
    }

    /// Cambia el perfil activo entero (los valores de la ayuda se dejan dentro de sus límites)
    pub fn poner_activo(&mut self, mut p: Perfil) {
        if let Some(i) = self.perfiles.iter().position(|x| x.id == p.id) {
            p.ayuda.normalizar();
            self.perfiles[i] = p;
            self.cambiado();
        }
    }

    fn con_activo<R>(&mut self, f: impl FnOnce(&mut Perfil) -> R) -> R {
        let mut p = self.activo().clone();
        let r = f(&mut p);
        self.poner_activo(p);
        r
    }

    pub fn poner_generales(&mut self, g: AjustesGenerales) {
        self.generales = g;
        self.cambiado();
    }

    pub fn seleccionar(&mut self, id: &str) {
        if self.perfiles.iter().any(|p| p.id == id) {
            self.activo_id = id.to_string();
            self.cambiado();
        }
    }

    pub fn nuevo(&mut self) {
        let mut p = Perfil::con_nombre(&format!("Perfil {}", self.perfiles.len() + 1));
        p.color = COLORES[self.perfiles.len() % COLORES.len()].into();
        self.activo_id = p.id.clone();
        self.perfiles.push(p);
        self.cambiado();
    }

    pub fn duplicar(&mut self) {
        let mut p = self.activo().clone();
        p.id = nuevo_id();
        p.nombre = format!("{} (copia)", self.activo().nombre);
        p.color = COLORES[self.perfiles.len() % COLORES.len()].into();
        self.activo_id = p.id.clone();
        self.perfiles.push(p);
        self.cambiado();
    }

    pub fn borrar_activo(&mut self) {
        if self.perfiles.len() < 2 {
            return;
        }
        let Some(i) = self.perfiles.iter().position(|p| p.id == self.activo_id) else { return };
        self.perfiles.remove(i);
        self.activo_id = self.perfiles[i.saturating_sub(1)].id.clone();
        self.cambiado();
    }

    /// +1 = siguiente, -1 = anterior (da la vuelta). Se salta los que no entran en el ciclo.
    pub fn cambiar_perfil(&mut self, paso: i32) {
        let Some(i) = self.perfiles.iter().position(|p| p.id == self.activo_id) else { return };
        let n = self.perfiles.len() as i64;
        for k in 1..=n {
            let j = (((i as i64 + paso as i64 * k) % n) + n) % n;
            let c = &self.perfiles[j as usize];
            if c.en_ciclo && c.id != self.activo_id {
                self.activo_id = c.id.clone();
                self.cambiado();
                return;
            }
        }
    }

    /// Desde el mando: dParam cambia el ajuste elegido y dValor sube o baja su valor
    pub fn ajuste_rapido(&mut self, d_param: i32, d_valor: i32) -> String {
        let n = AJUSTES_RAPIDOS.len();
        if d_param != 0 {
            self.ajuste_indice = ((self.ajuste_indice as i64 + d_param as i64 + n as i64) % n as i64) as usize;
            let a = &AJUSTES_RAPIDOS[self.ajuste_indice];
            return format!("{} {}", a.nombre, entero((a.leer)(self.activo())));
        }
        let a = &AJUSTES_RAPIDOS[self.ajuste_indice];
        let v = ((a.leer)(self.activo()) + d_valor as f64 * a.paso).max(a.min).min(a.max);
        self.con_activo(|p| (a.escribir)(p, v));
        format!("{}", entero(v))
    }

    pub const PASO_FUERZA: f64 = 2.0;

    pub fn ajustar_fuerza(&mut self, d: i32) -> String {
        let delta = d as f64 * Almacen::PASO_FUERZA;
        self.con_activo(|p| {
            p.anti_recoil.vertical = (p.anti_recoil.vertical + delta).clamp(0.0, 100.0);
            if p.anti_recoil.progresivo {
                p.anti_recoil.vertical_final = (p.anti_recoil.vertical_final + delta).clamp(0.0, 100.0);
            }
            let mut frase = format!("Anti-recoil {}", entero(p.anti_recoil.vertical));
            if p.anti_recoil.progresivo {
                frase += &format!(", final {}", entero(p.anti_recoil.vertical_final));
            }
            if !p.anti_recoil.activo {
                frase += ", apagado";
            }
            frase
        })
    }

    /// Desde el mando: mueve la corrección lateral del anti-recoil (+1 a la derecha, -1 a la izquierda)
    pub fn ajustar_lateral(&mut self, d: i32) -> String {
        let delta = d as f64 * Almacen::PASO_FUERZA;
        self.con_activo(|p| {
            p.anti_recoil.horizontal = (p.anti_recoil.horizontal + delta).clamp(-50.0, 50.0);
            let v = entero(p.anti_recoil.horizontal);
            let mut frase = if v > 0 { format!("Lateral derecha {v}") } else if v < 0 { format!("Lateral izquierda {}", -v) } else { "Lateral 0".to_string() };
            if !p.anti_recoil.activo {
                frase += ", apagado";
            }
            frase
        })
    }

    pub fn alternar_macro(&mut self, id: &str) -> Option<String> {
        if !self.activo().macros.iter().any(|m| m.id == id) {
            return None;
        }
        Some(self.con_activo(|p| {
            let m = p.macros.iter_mut().find(|m| m.id == id).unwrap();
            m.activa = !m.activa;
            format!("{} {}", m.nombre, if m.activa { "activada" } else { "desactivada" })
        }))
    }

    pub fn alternar_macros(&mut self) -> String {
        self.con_activo(|p| {
            let encender = !p.macros.iter().any(|m| m.activa);
            p.macros.iter_mut().for_each(|m| m.activa = encender);
            if encender { "Macros activadas" } else { "Macros desactivadas" }.to_string()
        })
    }

    pub fn alternar_turbo(&mut self, id: &str) -> Option<String> {
        if !self.activo().turbos.iter().any(|t| t.id == id) {
            return None;
        }
        Some(self.con_activo(|p| {
            let t = p.turbos.iter_mut().find(|t| t.id == id).unwrap();
            t.activo = !t.activo;
            format!("Turbo en {} {}", t.boton.corto(), if t.activo { "encendido" } else { "apagado" })
        }))
    }

    pub fn alternar_turbos(&mut self) -> String {
        self.con_activo(|p| {
            let encender = !p.turbos.iter().any(|t| t.activo);
            p.turbos.iter_mut().for_each(|t| t.activo = encender);
            if encender { "Turbo encendido" } else { "Turbo apagado" }.to_string()
        })
    }

    pub fn anadir_widget(&mut self, w: Widget) {
        if self.activo().widgets.iter().any(|x| x.tipo == w.tipo && x.objetivo == w.objetivo) {
            return;
        }
        self.con_activo(|p| p.widgets.push(w));
    }

    pub fn quitar_widget(&mut self, id: &str) {
        self.con_activo(|p| p.widgets.retain(|w| w.id != id));
    }

    pub fn mover_widget(&mut self, id: &str, paso: i32) {
        let Some(i) = self.activo().widgets.iter().position(|w| w.id == id) else { return };
        let j = i as i64 + paso as i64;
        if j < 0 || j >= self.activo().widgets.len() as i64 {
            return;
        }
        self.con_activo(|p| p.widgets.swap(i, j as usize));
    }

    const AJUSTES_PERMITIDOS: [&'static str; 10] = [
        "cambioPerfil", "cambioMantener", "cambioSiguiente", "cambioAnterior",
        "decirNombre", "avisosVoz", "ajusteMando", "ajusteMantener", "fuerzaMando", "fuerzaMantener",
    ];

    /// Cambia un valor del perfil activo («antiRecoil.vertical») o de los generales («generales.decirNombre»).
    /// Devuelve el error o None si fue bien.
    pub fn poner_ruta(&mut self, ruta: &str, valor: Value) -> Option<String> {
        let partes: Vec<&str> = ruta.split('.').filter(|s| !s.is_empty()).collect();
        if partes.is_empty() {
            return Some("ruta vacía".into());
        }
        if partes[0] == "generales" {
            let simple = partes.len() == 2 && Almacen::AJUSTES_PERMITIDOS.contains(&partes[1]);
            let monitor = partes.len() == 3 && partes[1] == "monitor";
            let medidor = partes.len() == 3 && partes[1] == "medidor";
            if !(simple || monitor || medidor) {
                return Some("ajuste no permitido".into());
            }
            if monitor && partes[2] != "activo" {
                match valor.as_f64() {
                    Some(n) if n.is_finite() && n > 0.0 => {}
                    _ => return Some("el umbral tiene que ser un número mayor que 0".into()),
                }
            }
            let mut d = serde_json::to_value(&self.generales).unwrap_or(Value::Null);
            if !poner(&mut d, &partes[1..], valor) {
                return Some(format!("ruta desconocida: {ruta}"));
            }
            match serde_json::from_value::<AjustesGenerales>(d) {
                Ok(g) => self.poner_generales(g),
                Err(_) => return Some(format!("valor no válido para {ruta}")),
            }
        } else {
            if partes[0] == "id" {
                return Some("ajuste no permitido".into());
            }
            let mut d = serde_json::to_value(self.activo()).unwrap_or(Value::Null);
            if !poner(&mut d, &partes, valor) {
                return Some(format!("ruta desconocida: {ruta}"));
            }
            // Lo que falte (un turbo o una macro nuevos del móvil) va con su valor por defecto
            match serde_json::from_value::<Perfil>(d) {
                Ok(mut nuevo) => {
                    nuevo.id = self.activo_id.clone();
                    self.poner_activo(nuevo);
                }
                Err(_) => return Some(format!("valor no válido para {ruta}")),
            }
        }
        None
    }

    pub fn cambiar_patron_ayuda(&mut self, paso: i32) -> String {
        self.con_activo(|p| {
            let n = p.ayuda.opciones().len() as i64;
            let actual = p.ayuda.opcion_actual().map(|i| i as i64).unwrap_or(if paso > 0 { -1 } else { 0 });
            let nuevo = (((actual + paso as i64) % n) + n) % n;
            p.ayuda.aplicar_opcion(nuevo as usize)
        })
    }

    pub fn usar_patron_ayuda(&mut self, i: usize) {
        if i < PATRONES.len() {
            self.con_activo(|p| p.ayuda.aplicar_patron(i));
        }
    }
    pub fn usar_variante_ayuda(&mut self, id: &str) {
        let Some(v) = self.activo().ayuda.variantes.iter().find(|v| v.id == id).cloned() else { return };
        self.con_activo(|p| p.ayuda.aplicar(&v));
    }
    pub fn guardar_variante_ayuda(&mut self, nombre: &str) {
        self.con_activo(|p| p.ayuda.guardar_como_variante(nombre));
    }
    pub fn actualizar_variante_ayuda(&mut self) {
        self.con_activo(|p| p.ayuda.actualizar_variante_activa());
    }
    pub fn borrar_variante_ayuda(&mut self, id: &str) {
        self.con_activo(|p| p.ayuda.borrar_variante(id));
    }

    /// Crea «Corto alcance» y «Largo alcance» a partir del activo. Devuelve cuántos ha añadido.
    pub fn crear_perfiles_por_situacion(&mut self) -> usize {
        let base = self.activo().clone();
        let mut anadidos = 0;
        let mut nuevo = |a: &mut Almacen, nombre: &str, color: &str, ajustar: &dyn Fn(&mut Perfil)| {
            if a.perfiles.iter().any(|p| p.nombre == nombre) {
                return;
            }
            let mut p = base.clone();
            p.id = nuevo_id();
            p.nombre = nombre.into();
            p.color = color.into();
            p.en_ciclo = true;
            ajustar(&mut p);
            a.perfiles.push(p);
            anadidos += 1;
        };
        nuevo(self, "Corto alcance", "#FF6A00", &|p| {
            p.der.sens_x = 120.0; p.der.sens_y = 120.0; p.der.curva = 1.0; p.der.suavizado = 0.0;
            p.anti_recoil.vertical = 15.0; p.anti_recoil.progresivo = false;
            p.ayuda.aplicar_patron(2);
        });
        nuevo(self, "Largo alcance", "#00B0FF", &|p| {
            p.der.sens_x = 80.0; p.der.sens_y = 80.0; p.der.curva = 1.6; p.der.suavizado = 15.0;
            p.anti_recoil.vertical = 30.0; p.anti_recoil.progresivo = true;
            p.anti_recoil.vertical_final = 15.0; p.anti_recoil.transicion_ms = 1200.0;
            p.ayuda.aplicar_patron(0);
        });
        if anadidos > 0 {
            self.cambiado();
        }
        anadidos
    }

    /// Cambia cuando cambia cualquier ajuste (el móvil lo usa para saber si recargar)
    pub fn revision(&self, pausado: bool) -> String {
        use std::hash::{Hash, Hasher};
        let mut h = std::collections::hash_map::DefaultHasher::new();
        serde_json::to_string(&(&self.perfiles, &self.activo_id, &self.generales)).unwrap_or_default().hash(&mut h);
        format!("{}{}", h.finish(), if pausado { "p" } else { "" })
    }
}

fn poner(d: &mut Value, ruta: &[&str], valor: Value) -> bool {
    let Some((clave, resto)) = ruta.split_first() else { return false };
    let Some(obj) = d.as_object_mut() else { return false };
    if !obj.contains_key(*clave) {
        // Los opcionales vacíos no se escriben en el JSON; se pueden poner igual si son del modelo
        if !resto.is_empty() || !matches!(*clave, "varianteActiva" | "objetivo") {
            return false;
        }
    }
    if resto.is_empty() {
        obj.insert(clave.to_string(), valor);
        return true;
    }
    match obj.get_mut(*clave) {
        Some(hijo) => poner(hijo, resto, valor),
        None => false,
    }
}

// MARK: - Resumen de lo que está activo (para «En vivo»)

pub struct FuncionActiva {
    pub nombre: String,
    pub detalle: String,
    pub encendida: bool,
}

pub fn resumen_funciones(p: &Perfil, g: &AjustesGenerales, anti_recoil: bool, ayuda: bool) -> Vec<FuncionActiva> {
    let mut f = vec![];
    let mut anadir = |n: &str, d: String, on: bool| f.push(FuncionActiva { nombre: n.into(), detalle: d, encendida: on });
    let lista = |b: &[Boton]| b.iter().map(|x| x.corto()).collect::<Vec<_>>().join(", ");
    if p.anti_recoil.activo || anti_recoil {
        let modo = if p.anti_recoil.progresivo { "progresivo" } else { "fuerza fija" };
        anadir("Anti-recoil", modo.into(), anti_recoil);
    }
    if p.ayuda.activo || ayuda {
        let forma = if p.ayuda.forma == Forma::Circulo { "círculos" } else { "temblor" };
        anadir("Ayuda al apuntado", format!("{forma}, con {}", p.ayuda.boton.corto()), ayuda);
    }
    if !p.turbos.is_empty() {
        let d = p.turbos.iter().map(|t| format!("{} {}/s", t.boton.corto(), entero(t.hz))).collect::<Vec<_>>().join(", ");
        anadir("Turbo", d, true);
    }
    let activas: Vec<&Macro> = p.macros.iter().filter(|m| m.activa).collect();
    if !p.macros.is_empty() {
        let d = if activas.is_empty() { "ninguna activa".to_string() }
            else { activas.iter().map(|m| format!("{} ({})", m.nombre, m.disparador.corto())).collect::<Vec<_>>().join(", ") };
        anadir(if activas.len() == 1 { "Macro" } else { "Macros" }, d, !activas.is_empty());
    }
    let cambiados: Vec<Boton> = Boton::TODOS.iter().copied().filter(|b| p.reasignar.contains_key(b.clave())).collect();
    if !cambiados.is_empty() {
        anadir("Botones cambiados", lista(&cambiados), true);
    }
    if !p.alternar.is_empty() {
        anadir("Alternar", lista(&p.alternar), true);
    }
    let largas: Vec<Boton> = Boton::TODOS.iter().copied().filter(|b| p.pulsacion_larga.contains_key(b.clave())).collect();
    if !largas.is_empty() {
        anadir("Pulsación larga", lista(&largas), true);
    }
    if p.intercambiar_sticks {
        anadir("Sticks intercambiados", String::new(), true);
    }
    if g.medidor.activo {
        anadir("Mi control", "midiendo".into(), true);
    }
    if g.monitor.activo {
        anadir("Monitor de señal", String::new(), true);
    }
    f
}

// MARK: - Widgets de «En vivo»

pub struct EstadoWidget {
    pub id: String,
    pub tipo: TipoWidget,
    pub nombre: String,
    pub detalle: String,
    pub encendido: bool,
}

pub fn catalogo_widgets(p: &Perfil) -> Vec<Widget> {
    let mut c = vec![Widget::de(TipoWidget::AntiRecoil, None), Widget::de(TipoWidget::Ayuda, None)];
    if p.turbos.len() > 1 {
        c.push(Widget::de(TipoWidget::Turbos, None));
    }
    c.extend(p.turbos.iter().map(|t| Widget::de(TipoWidget::Turbo, Some(t.id.clone()))));
    if p.macros.len() > 1 {
        c.push(Widget::de(TipoWidget::Macros, None));
    }
    c.extend(p.macros.iter().map(|m| Widget::de(TipoWidget::Macro, Some(m.id.clone()))));
    c.push(Widget::de(TipoWidget::Pausa, None));
    c.retain(|w| !p.widgets.iter().any(|x| x.tipo == w.tipo && x.objetivo == w.objetivo));
    c
}

pub fn widgets_basicos(p: &Perfil) -> Vec<Widget> {
    let mut b = vec![Widget::de(TipoWidget::AntiRecoil, None), Widget::de(TipoWidget::Ayuda, None)];
    if !p.macros.is_empty() {
        b.push(if p.macros.len() == 1 { Widget::de(TipoWidget::Macro, Some(p.macros[0].id.clone())) } else { Widget::de(TipoWidget::Macros, None) });
    }
    if !p.turbos.is_empty() {
        b.push(if p.turbos.len() == 1 { Widget::de(TipoWidget::Turbo, Some(p.turbos[0].id.clone())) } else { Widget::de(TipoWidget::Turbos, None) });
    }
    b.push(Widget::de(TipoWidget::Pausa, None));
    b
}

pub fn nombre_widget(w: &Widget, p: &Perfil) -> String {
    estado_widget(w, p, false, false, false).map(|e| e.nombre).unwrap_or_else(|| "—".into())
}

/// None si apunta a un turbo o una macro que ya no existe
pub fn estado_widget(w: &Widget, p: &Perfil, anti_recoil: bool, ayuda: bool, pausado: bool) -> Option<EstadoWidget> {
    let e = |n: String, d: String, on: bool| EstadoWidget { id: w.id.clone(), tipo: w.tipo, nombre: n, detalle: d, encendido: on };
    Some(match w.tipo {
        TipoWidget::AntiRecoil => {
            let ar = &p.anti_recoil;
            let modo = if ar.progresivo { "progresivo".to_string() } else { format!("fuerza {}", entero(ar.vertical)) };
            e("Anti-recoil".into(), modo, anti_recoil)
        }
        TipoWidget::Ayuda => {
            let tam = p.ayuda.efectivos().0;
            let t = if tam.round() == tam { format!("{}", tam as i64) } else { format!("{tam:.1}") };
            let forma = if p.ayuda.forma == Forma::Circulo { "círculos" } else { "temblor" };
            e("Ayuda al apuntado".into(), format!("{forma} · {t} %"), ayuda)
        }
        TipoWidget::Pausa => e(
            "Pausa".into(),
            if pausado { "la consola recibe el mando quieto" } else { "el mando pasa a la consola" }.into(),
            pausado,
        ),
        TipoWidget::Turbos => {
            let n = p.turbos.iter().filter(|t| t.activo).count();
            let d = if p.turbos.is_empty() { "sin turbos".to_string() } else { format!("{n} de {} encendidos", p.turbos.len()) };
            e("Turbo".into(), d, n > 0)
        }
        TipoWidget::Turbo => {
            let t = p.turbos.iter().find(|t| Some(&t.id) == w.objetivo.as_ref())?;
            e(format!("Turbo {}", t.boton.corto()), format!("{} pulsaciones/s", entero(t.hz)), t.activo)
        }
        TipoWidget::Macros => {
            let n = p.macros.iter().filter(|m| m.activa).count();
            let d = if p.macros.is_empty() { "sin macros".to_string() } else { format!("{n} de {} activas", p.macros.len()) };
            e("Macros".into(), d, n > 0)
        }
        TipoWidget::Macro => {
            let m = p.macros.iter().find(|m| Some(&m.id) == w.objetivo.as_ref())?;
            let mut d = format!("con {}", m.disparador.corto());
            if m.atajo {
                d += &format!(" · atajo {}+{}", m.atajo_mantener.corto(), m.atajo_pulsar.corto());
            }
            e(m.nombre.clone(), d, m.activa)
        }
    })
}

#[cfg(test)]
mod pruebas {
    use super::*;

    #[test]
    fn lee_un_archivo_de_la_app_de_mac_y_rellena_lo_que_falta() {
        let viejo = r##"{"perfiles":[{"id":"9A7C5F3E-1111-4222-8333-944455556666","nombre":"Viejo",
            "turbos":[{"id":"AAAAAAAA-1111-4222-8333-944455556666","boton":"r1","hz":12,"ciclo":50}],
            "macros":[{"id":"BBBBBBBB-1111-4222-8333-944455556666","nombre":"Salto","activa":true,"disparador":"r3",
                       "repetir":false,"bloquearDisparador":true,"pasos":[]}]}],
            "generales":{"clave":"ABCDEFGHJK"}}"##;
        let dir = std::env::temp_dir().join(format!("puente-{}", nuevo_id()));
        std::fs::create_dir_all(&dir).unwrap();
        let ruta = dir.join("perfiles.json");
        std::fs::write(&ruta, viejo).unwrap();
        let a = Almacen::cargar(ruta.clone());
        let p = a.activo();
        assert_eq!(p.nombre, "Viejo");
        assert!(p.turbos[0].activo, "turbo de un archivo antiguo: encendido");
        assert!(!p.macros[0].atajo && p.widgets.is_empty());
        assert_eq!(p.der.zona_muerta, 5.0);
        assert_eq!(a.generales.clave, "ABCDEFGHJK");
        // Se guarda con los mismos nombres de campo que lee Swift
        let guardado = std::fs::read_to_string(&ruta).unwrap();
        assert!(guardado.contains("\"antiRecoil\"") && guardado.contains("\"zonaMuerta\"") && guardado.contains("\"bloquearDisparador\""));
        assert!(guardado.contains("9A7C5F3E-1111-4222-8333-944455556666"), "los ids se quedan en mayúsculas");
    }

    #[test]
    fn poner_ruta_como_el_movil() {
        let dir = std::env::temp_dir().join(format!("puente-{}", nuevo_id()));
        std::fs::create_dir_all(&dir).unwrap();
        let mut a = Almacen::cargar(dir.join("perfiles.json"));
        assert_eq!(a.poner_ruta("antiRecoil.vertical", serde_json::json!(33)), None);
        assert_eq!(a.activo().anti_recoil.vertical, 33.0);
        assert!(a.poner_ruta("antiRecoil.vertical", serde_json::json!("mucho")).is_some());
        assert!(a.poner_ruta("generales.clave", serde_json::json!("X")).is_some(), "la clave no se cambia desde el móvil");
        let r = a.poner_ruta("turbos", serde_json::json!([{"id": nuevo_id(), "boton": "x", "hz": 10, "ciclo": 50}]));
        assert_eq!(r, None);
        assert!(a.activo().turbos[0].activo, "un turbo nuevo sin el campo llega encendido");
    }

    #[test]
    fn mic_y_cruceta_fuerza_y_lateral() {
        let g = AjustesGenerales::default();
        let (mic, der, izq) = (Boton::Silenciar.bit(), Boton::Derecha.bit(), Boton::Izquierda.bit());
        let mut e = Estado { botones: mic | der, ..Default::default() };
        assert_eq!(combo_fuerza(&mut e, der, &g), (true, 0, 1));
        assert_eq!(e.botones & der, 0, "la → no llega a la consola");
        let mut e = Estado { botones: mic | izq, ..Default::default() };
        assert_eq!(combo_fuerza(&mut e, izq, &g), (true, 0, -1));
        let mut e = Estado { botones: der, ..Default::default() };
        assert_eq!(combo_fuerza(&mut e, der, &g), (false, 0, 0));
        assert!(e.pulsado(Boton::Derecha), "sin Mic, la → llega normal");

        let dir = std::env::temp_dir().join(format!("puente-{}", nuevo_id()));
        std::fs::create_dir_all(&dir).unwrap();
        let mut a = Almacen::cargar(dir.join("perfiles.json"));
        let mut p = a.activo().clone();
        p.anti_recoil.activo = true;
        a.poner_activo(p);
        assert_eq!(a.ajustar_lateral(1), "Lateral derecha 2");
        a.ajustar_lateral(-1);
        assert_eq!(a.ajustar_lateral(-1), "Lateral izquierda 2");
        let mut p = a.activo().clone();
        p.anti_recoil.horizontal = 49.0;
        a.poner_activo(p);
        a.ajustar_lateral(1);
        assert_eq!(a.activo().anti_recoil.horizontal, 50.0, "no pasa de 50");
    }

    #[test]
    fn widgets_y_textos_iguales_que_en_mac() {
        let mut p = Perfil::default();
        p.ayuda.forma = Forma::Temblor;
        p.ayuda.tamano = 8.0;
        let w = Widget::de(TipoWidget::Ayuda, None);
        assert_eq!(estado_widget(&w, &p, false, true, false).unwrap().detalle, "temblor · 8 %");
        p.turbos = vec![Turbo { boton: Boton::R1, hz: 12.0, ..Default::default() }, Turbo::default()];
        let cat: Vec<TipoWidget> = catalogo_widgets(&p).iter().map(|w| w.tipo).collect();
        assert_eq!(cat, vec![TipoWidget::AntiRecoil, TipoWidget::Ayuda, TipoWidget::Turbos, TipoWidget::Turbo, TipoWidget::Turbo, TipoWidget::Pausa]);
    }
}
