// Aplica el perfil al mando: botones (alternar, pulsación larga, reasignar), sticks, gatillos, macros,
// turbo, anti-recoil y ayuda al apuntado. Es un port línea a línea de app/Procesador.swift, con las mismas
// operaciones de coma flotante en el mismo orden: para las mismas entradas da exactamente la misma salida
// (lo comprueba pruebas/procesador.json, generado con la versión de Swift).
#![allow(dead_code)]

use std::collections::HashMap;

use crate::modelo::{AjusteGatillo, AjusteStick, Boton, Estado, Forma, Perfil};

/// Foto de lo que hace la ayuda al apuntado en este instante (solo para mirar; no cambia nada)
#[derive(Clone, Debug, PartialEq)]
pub struct DiagnosticoAyuda {
    pub encendida: bool,
    pub aplicando: bool,
    pub forma: Forma,
    pub tamano: f64,
    pub hz: f64,
    pub entrada_ms: f64,
    pub ceder: f64,
    pub limitada: bool,
    pub rampa: f64,
    pub cesion: f64,
    pub amplitud: f64,
    pub fase: f64,
    pub off_x: f64,
    pub off_y: f64,
    pub en_transicion: bool,
}

impl Default for DiagnosticoAyuda {
    fn default() -> Self {
        DiagnosticoAyuda {
            encendida: false, aplicando: false, forma: Forma::Circulo, tamano: 0.0, hz: 0.0, entrada_ms: 0.0,
            ceder: 0.0, limitada: false, rampa: 0.0, cesion: 1.0, amplitud: 0.0, fase: 0.0, off_x: 0.0,
            off_y: 0.0, en_transicion: false,
        }
    }
}

#[derive(Default)]
struct EstadoStick {
    x: f64,
    y: f64,                    // salida suavizada
    tope_desde: Option<f64>,   // desde cuándo está casi a tope (aceleración)
}

/// Valores efectivos de la ayuda en el tick anterior (para enlazar un cambio hecho a mano)
#[derive(Clone, Copy, PartialEq)]
struct EfAnterior {
    tamano: f64,
    hz: f64,
    entrada_ms: f64,
    ceder: f64,
    forma: Forma,
}

const DURACION_ENLACE: f64 = 0.15; // s que tarda en enlazarse un cambio manual

pub struct Procesador {
    pub anti_recoil_encendido: bool,
    pub ayuda_encendida: bool,
    /// Lo que está haciendo la ayuda ahora mismo
    pub diagnostico: DiagnosticoAyuda,

    ayuda_en_ajustes: Option<bool>,
    ayuda_desde: Option<f64>,
    ef_anterior: Option<EfAnterior>,
    fase_desfase: f64,
    r_ultimo: f64,
    correccion_r: f64,
    correccion_desde: f64,
    forma_anterior: Option<Forma>,
    forma_cambio_desde: f64,

    perfil_id: Option<String>,
    activo_en_ajustes: Option<bool>,
    entrada_antes: u32,
    t_antes: Option<f64>,
    turbo_desde: HashMap<Boton, f64>,
    macro_desde: HashMap<String, f64>,
    disparando_desde: Option<f64>,
    alternados: u32,                      // botones en modo alternar que están «pulsados»
    pulsado_desde: HashMap<Boton, f64>,   // para la pulsación larga
    toque_hasta: HashMap<Boton, f64>,     // pulsación corta que se está enviando
    izq: EstadoStick,
    der: EstadoStick,
}

impl Default for Procesador {
    fn default() -> Self {
        Procesador::new()
    }
}

impl Procesador {
    pub fn new() -> Self {
        Procesador {
            anti_recoil_encendido: false,
            ayuda_encendida: false,
            diagnostico: DiagnosticoAyuda::default(),
            ayuda_en_ajustes: None,
            ayuda_desde: None,
            ef_anterior: None,
            fase_desfase: 0.0,
            r_ultimo: 0.0,
            correccion_r: 0.0,
            correccion_desde: 0.0,
            forma_anterior: None,
            forma_cambio_desde: 0.0,
            perfil_id: None,
            activo_en_ajustes: None,
            entrada_antes: 0,
            t_antes: None,
            turbo_desde: HashMap::new(),
            macro_desde: HashMap::new(),
            disparando_desde: None,
            alternados: 0,
            pulsado_desde: HashMap::new(),
            toque_hasta: HashMap::new(),
            izq: EstadoStick::default(),
            der: EstadoStick::default(),
        }
    }

    /// Como la combinación del mando, pero pedido desde «En vivo» (un widget). Desde el hilo del motor.
    pub fn alternar_anti_recoil(&mut self) {
        self.anti_recoil_encendido = !self.anti_recoil_encendido;
    }

    pub fn alternar_ayuda(&mut self) {
        self.ayuda_encendida = !self.ayuda_encendida;
    }

    pub fn procesar(&mut self, e: &Estado, p: &Perfil, t: f64) -> Estado {
        if self.perfil_id.as_deref() != Some(p.id.as_str()) {   // perfil nuevo: empezar de cero
            self.perfil_id = Some(p.id.clone());
            self.turbo_desde.clear();
            self.macro_desde.clear();
            self.alternados = 0;
            self.pulsado_desde.clear();
            self.toque_hasta.clear();
            self.ef_anterior = None;
            self.fase_desfase = 0.0;
            self.correccion_r = 0.0;
            self.forma_anterior = None;
            self.activo_en_ajustes = None;
            self.ayuda_en_ajustes = None;
        }
        if Some(p.ayuda.activo) != self.ayuda_en_ajustes {
            self.ayuda_en_ajustes = Some(p.ayuda.activo);
            self.ayuda_encendida = p.ayuda.activo;
        }
        if Some(p.anti_recoil.activo) != self.activo_en_ajustes {   // lo han cambiado en la ventana
            self.activo_en_ajustes = Some(p.anti_recoil.activo);
            self.anti_recoil_encendido = p.anti_recoil.activo;
        }
        let dt = swift_min(swift_max(t - self.t_antes.unwrap_or(t), 0.0), 0.05);
        self.t_antes = Some(t);
        let flanco = e.botones & !self.entrada_antes;     // botones que se acaban de pulsar
        let soltados = self.entrada_antes & !e.botones;
        self.entrada_antes = e.botones;

        // 1. Sticks en coma flotante, Y positiva = arriba
        let (mut ix, mut iy) = (eje(e.lx), -eje(e.ly));
        let (mut dx, mut dy) = (eje(e.rx), -eje(e.ry));
        if p.intercambiar_sticks {
            std::mem::swap(&mut ix, &mut dx);
            std::mem::swap(&mut iy, &mut dy);
        }
        (ix, iy) = stick(ix, iy, &p.izq, &mut self.izq, t, dt);
        (dx, dy) = stick(dx, dy, &p.der, &mut self.der, t, dt);

        // 2. Gatillos
        let mut l2 = gatillo(e.l2, &p.l2);
        let mut r2 = gatillo(e.r2, &p.r2);
        let mut entrada = e.botones & !(Boton::L2.bit() | Boton::R2.bit());
        if l2 > 0.0 {
            entrada |= Boton::L2.bit();
        }
        if r2 > 0.0 {
            entrada |= Boton::R2.bit();
        }

        // 3. Alternar: pulsar una vez = mantener, otra vez = soltar
        for &b in &p.alternar {
            if flanco & b.bit() != 0 {
                self.alternados ^= b.bit();
            }
            if self.alternados & b.bit() != 0 {
                entrada |= b.bit();
            } else {
                entrada &= !b.bit();
            }
            if b == Boton::L2 {
                l2 = if self.alternados & b.bit() != 0 { 1.0 } else { 0.0 };
            }
            if b == Boton::R2 {
                r2 = if self.alternados & b.bit() != 0 { 1.0 } else { 0.0 };
            }
        }

        // 4. Pulsación larga: corta = su función normal; larga = otra
        let mut por_larga: u32 = 0;
        for (origen, destino_largo) in &p.pulsacion_larga {
            let Some(b) = Boton::de_clave(origen) else { continue };
            let larga = Boton::de_clave(destino_largo);   // None = «nada»
            if e.botones & b.bit() != 0 {
                let desde = *self.pulsado_desde.get(&b).unwrap_or(&t);
                self.pulsado_desde.insert(b, desde);
                if (t - desde) * 1000.0 >= p.ms_larga {
                    if let Some(larga) = larga {
                        por_larga |= larga.bit();
                    }
                }
            } else if soltados & b.bit() != 0 {
                if let Some(&desde) = self.pulsado_desde.get(&b) {
                    if (t - desde) * 1000.0 < p.ms_larga {
                        self.toque_hasta.insert(b, t + 0.08);   // fue corta: se envía ahora
                    }
                    self.pulsado_desde.remove(&b);
                }
            }
            // Mientras se decide, y durante la larga, la función normal no llega
            match self.toque_hasta.get(&b) {
                Some(&hasta) if t < hasta => {
                    entrada |= b.bit();
                    if b == Boton::L2 {
                        l2 = 1.0;
                    }
                    if b == Boton::R2 {
                        r2 = 1.0;
                    }
                }
                _ => {
                    self.toque_hasta.remove(&b);
                    entrada &= !b.bit();
                    if b == Boton::L2 {
                        l2 = 0.0;
                    }
                    if b == Boton::R2 {
                        r2 = 0.0;
                    }
                }
            }
        }

        // 5. Reasignación
        let mut salida: u32 = 0;
        let (mut l2_sal, mut r2_sal) = (0.0f64, 0.0f64);
        for b in Boton::TODOS {
            if entrada & b.bit() == 0 {
                continue;
            }
            let Some(d) = p.destino(b) else { continue };
            salida |= d.bit();
            let valor = if b == Boton::L2 { l2 } else if b == Boton::R2 { r2 } else { 1.0 };
            if d == Boton::L2 {
                l2_sal = swift_max(l2_sal, valor);
            }
            if d == Boton::R2 {
                r2_sal = swift_max(r2_sal, valor);
            }
        }
        salida |= por_larga;
        if por_larga & Boton::L2.bit() != 0 {
            l2_sal = 1.0;
        }
        if por_larga & Boton::R2.bit() != 0 {
            r2_sal = 1.0;
        }

        // 6. Macros (se disparan con el botón físico)
        let mut de_macros: u32 = 0;
        for m in p.macros.iter().filter(|m| m.activa && !m.pasos.is_empty()) {
            let pulsado = e.botones & m.disparador.bit() != 0;
            if flanco & m.disparador.bit() != 0 && !self.macro_desde.contains_key(&m.id) {
                self.macro_desde.insert(m.id.clone(), t);
            }
            let Some(&desde) = self.macro_desde.get(&m.id) else { continue };
            let total = m.pasos.iter().fold(0i64, |a, x| a + x.ms.max(1)) as f64 / 1000.0;
            let mut pasado = t - desde;
            if pasado >= total {
                if m.repetir && pulsado {
                    pasado %= total;
                } else {
                    self.macro_desde.remove(&m.id);
                    continue;
                }
            }
            let mut acumulado = 0.0;
            for paso in &m.pasos {
                acumulado += paso.ms.max(1) as f64 / 1000.0;
                if pasado < acumulado {
                    for b in &paso.botones {
                        de_macros |= b.bit();
                    }
                    break;
                }
            }
        }
        // El disparador no llega a la consola mientras lo mantienes (salvo que la macro lo pulse)
        for m in p.macros.iter().filter(|m| m.activa && m.bloquear_disparador && e.botones & m.disparador.bit() != 0) {
            let Some(d) = p.destino(m.disparador) else { continue };
            if de_macros & d.bit() != 0 {
                continue;
            }
            salida &= !d.bit();
            if d == Boton::L2 {
                l2_sal = 0.0;
            }
            if d == Boton::R2 {
                r2_sal = 0.0;
            }
        }
        salida |= de_macros;
        if de_macros & Boton::L2.bit() != 0 {
            l2_sal = 1.0;
        }
        if de_macros & Boton::R2.bit() != 0 {
            r2_sal = 1.0;
        }

        // 7. Turbo
        for tb in p.turbos.iter().filter(|tb| tb.hz > 0.0 && tb.activo) {
            if salida & tb.boton.bit() == 0 {
                self.turbo_desde.remove(&tb.boton);
                continue;
            }
            let desde = *self.turbo_desde.get(&tb.boton).unwrap_or(&t);
            self.turbo_desde.insert(tb.boton, desde);
            let fase = ((t - desde) * tb.hz) % 1.0;
            if fase >= tb.ciclo / 100.0 {
                salida &= !tb.boton.bit();
                if tb.boton == Boton::L2 {
                    l2_sal = 0.0;
                }
                if tb.boton == Boton::R2 {
                    r2_sal = 0.0;
                }
            }
        }

        // 8. Anti-recoil
        let ar = &p.anti_recoil;
        let combinacion = if ar.atajo_mantener == ar.atajo_pulsar {
            flanco & ar.atajo_pulsar.bit() != 0
        } else {
            e.pulsado(ar.atajo_mantener) && flanco & ar.atajo_pulsar.bit() != 0
        };
        if ar.atajo && combinacion {
            self.anti_recoil_encendido = !self.anti_recoil_encendido;
        }
        let pulsado_en_salida = |b: Boton| -> bool {
            match b {
                Boton::L2 => l2_sal > 0.1,
                Boton::R2 => r2_sal > 0.1,
                _ => salida & b.bit() != 0,
            }
        };
        let disparando = pulsado_en_salida(ar.disparar) && (!ar.solo_apuntando || pulsado_en_salida(ar.apuntar));
        if self.anti_recoil_encendido && disparando {
            let desde = self.disparando_desde.unwrap_or(t);
            self.disparando_desde = Some(desde);
            let pasado_ms = (t - desde) * 1000.0 - ar.retardo_ms;
            if pasado_ms >= 0.0 {
                let mut fuerza = ar.vertical;
                if ar.progresivo {
                    let k = if ar.transicion_ms > 0.0 { swift_min(pasado_ms / ar.transicion_ms, 1.0) } else { 1.0 };
                    fuerza = ar.vertical + (ar.vertical_final - ar.vertical) * k;
                }
                dy -= fuerza / 100.0;
                dx += ar.horizontal / 100.0;
            }
        } else {
            self.disparando_desde = None;
        }

        // 9. Ayuda al apuntado: círculos o temblores diminutos en el stick derecho
        let ay = &p.ayuda;
        let combo_ayuda = if ay.atajo_mantener == ay.atajo_pulsar {
            flanco & ay.atajo_pulsar.bit() != 0
        } else {
            e.pulsado(ay.atajo_mantener) && flanco & ay.atajo_pulsar.bit() != 0
        };
        if ay.atajo && combo_ayuda {
            self.ayuda_encendida = !self.ayuda_encendida;
        }
        // Valores que usa el motor: los del perfil, recortados a los límites si el usuario los activó
        let (ef_tamano, ef_hz, ef_entrada, ef_ceder) = ay.efectivos();
        let mut diag = DiagnosticoAyuda {
            encendida: self.ayuda_encendida,
            forma: ay.forma,
            tamano: ef_tamano,
            hz: ef_hz,
            entrada_ms: ef_entrada,
            ceder: ef_ceder,
            limitada: ay.limitado(),
            ..Default::default()
        };
        if self.ayuda_encendida && pulsado_en_salida(ay.boton) && (!ay.tambien_disparando || pulsado_en_salida(ar.disparar)) {
            let desde = self.ayuda_desde.unwrap_or(t);
            self.ayuda_desde = Some(desde);
            // Un cambio hecho a mano con la ayuda en marcha: la fase y la amplitud se enlazan
            let mut cambio_manual = false;
            if let Some(a) = self.ef_anterior {
                if a.tamano != ef_tamano || a.hz != ef_hz || a.entrada_ms != ef_entrada || a.ceder != ef_ceder || a.forma != ay.forma {
                    cambio_manual = true;
                    if a.hz != ef_hz {
                        let fase_antes = (t - desde) * a.hz + self.fase_desfase;
                        self.fase_desfase = fase_antes - (t - desde) * ef_hz;
                    }
                    if a.forma != ay.forma {
                        self.forma_anterior = Some(a.forma);
                        self.forma_cambio_desde = t;
                    }
                }
            }
            self.ef_anterior = Some(EfAnterior { tamano: ef_tamano, hz: ef_hz, entrada_ms: ef_entrada, ceder: ef_ceder, forma: ay.forma });
            let fase = ((t - desde) * ef_hz + self.fase_desfase) % 1.0;
            // Entra poco a poco y cede cuando apuntas tú, para que no dé tirones ni pelee con tu mano
            let entrada_suave = if ef_entrada > 0.0 { swift_min((t - desde) * 1000.0 / ef_entrada, 1.0) } else { 1.0 };
            let tuyo = swift_min(dx.hypot(dy), 1.0);
            let r0 = ef_tamano / 100.0 * entrada_suave * (1.0 - ef_ceder / 100.0 * tuyo);
            if cambio_manual {
                self.correccion_r = self.r_ultimo - r0;
                self.correccion_desde = t;
            }
            let mut correccion = 0.0;
            if self.correccion_r != 0.0 {
                let k = 1.0 - (t - self.correccion_desde) / DURACION_ENLACE;
                if k > 0.0 {
                    correccion = self.correccion_r * k;
                } else {
                    self.correccion_r = 0.0;
                }
            }
            let r = r0 + correccion;
            self.r_ultimo = r;
            let (mut vx, mut vy) = vector(ay.forma, r, fase);
            if let Some(anterior) = self.forma_anterior {
                let k = (t - self.forma_cambio_desde) / DURACION_ENLACE;
                if k < 1.0 {
                    let (ox, oy) = vector(anterior, r, fase);
                    vx = ox + (vx - ox) * k;
                    vy = oy + (vy - oy) * k;
                } else {
                    self.forma_anterior = None;
                }
            }
            dx += vx;
            dy += vy;
            diag.aplicando = true;
            diag.rampa = entrada_suave;
            diag.cesion = 1.0 - ef_ceder / 100.0 * tuyo;
            diag.amplitud = r;
            diag.fase = fase - fase.floor();
            diag.off_x = vx;
            diag.off_y = vy;
            diag.en_transicion = correccion != 0.0 || self.forma_anterior.is_some();
        } else {
            self.ayuda_desde = None;
            self.ef_anterior = None;
            self.fase_desfase = 0.0;
            self.correccion_r = 0.0;
            self.forma_anterior = None;
            self.r_ultimo = 0.0;
        }
        self.diagnostico = diag;

        Estado {
            botones: salida,
            lx: byte(ix), ly: byte(-iy), rx: byte(dx), ry: byte(-dy),
            l2: (swift_min(swift_max(l2_sal, 0.0), 1.0) * 255.0).round() as u8,
            r2: (swift_min(swift_max(r2_sal, 0.0), 1.0) * 255.0).round() as u8,
        }
    }
}

fn stick(x: f64, y: f64, a: &AjusteStick, s: &mut EstadoStick, t: f64, dt: f64) -> (f64, f64) {
    let (mut ox, mut oy) = forma(x, y, a);
    // Aceleración: con el stick casi a tope, la sensibilidad sube poco a poco
    if a.aceleracion > 0.0 && x.hypot(y) > 0.85 {
        let desde = s.tope_desde.unwrap_or(t);
        s.tope_desde = Some(desde);
        let k = if a.tiempo_aceleracion > 0.0 { swift_min((t - desde) * 1000.0 / a.tiempo_aceleracion, 1.0) } else { 1.0 };
        let factor = 1.0 + a.aceleracion / 100.0 * k;
        ox *= factor;
        oy *= factor;
    } else {
        s.tope_desde = None;
    }
    // Límite: lo más lejos que llega el stick a la consola
    let lim = a.limite / 100.0;
    let m = ox.hypot(oy);
    if m > lim && m > 0.0 {
        ox *= lim / m;
        oy *= lim / m;
    }
    // Suavizado: filtro que quita los tirones (hasta ~150 ms)
    if a.suavizado > 0.0 {
        let tau = a.suavizado / 100.0 * 0.15;
        let alfa = dt / (tau + dt);
        s.x += (ox - s.x) * alfa;
        s.y += (oy - s.y) * alfa;
        (ox, oy) = (s.x, s.y);
    } else {
        (s.x, s.y) = (ox, oy);
    }
    (swift_min(swift_max(ox, -1.0), 1.0), swift_min(swift_max(oy, -1.0), 1.0))
}

/// Lo que la ayuda suma al stick derecho según la forma, la amplitud y la fase (0...1)
pub fn vector(forma: Forma, r: f64, fase: f64) -> (f64, f64) {
    match forma {
        Forma::Circulo => (r * (2.0 * std::f64::consts::PI * fase).cos(), r * (2.0 * std::f64::consts::PI * fase).sin()),
        Forma::Temblor => (r * (2.0 * std::f64::consts::PI * fase).sin(), 0.0),   // vaivén suave, sin saltos
    }
}

/// Zona muerta, curva, sensibilidad e inversión (sin aceleración, límite ni suavizado)
pub fn forma(x: f64, y: f64, a: &AjusteStick) -> (f64, f64) {
    let (mut sx, mut sy);
    if a.forma_cruz {
        sx = (if x < 0.0 { -1.0 } else { 1.0 }) * curva(swift_min(x.abs(), 1.0), a);
        sy = (if y < 0.0 { -1.0 } else { 1.0 }) * curva(swift_min(y.abs(), 1.0), a);
    } else {
        let modulo = swift_min(x.hypot(y), 1.0);
        if !(modulo > 0.0) {
            return (0.0, 0.0);
        }
        let salida = curva(modulo, a);
        sx = x / x.hypot(y) * salida;
        sy = y / x.hypot(y) * salida;
    }
    sx *= a.sens_x / 100.0;
    sy *= a.sens_y / 100.0;
    if a.invertir_x {
        sx = -sx;
    }
    if a.invertir_y {
        sy = -sy;
    }
    (sx, sy)
}

/// Recorrido del stick (0..1) -> recorrido que sale (0..1)
pub fn curva(v: f64, a: &AjusteStick) -> f64 {
    let dz = a.zona_muerta / 100.0;
    let ext = swift_max(a.zona_externa / 100.0, dz + 0.01);
    if !(v > dz) {
        return 0.0;
    }
    let mut n = swift_min((v - dz) / (ext - dz), 1.0);
    n = n.powf(swift_max(a.curva, 0.1));
    let anti = a.anti_zona_muerta / 100.0;
    anti + (1.0 - anti) * n
}

pub fn gatillo(v: u8, a: &AjusteGatillo) -> f64 {
    let x = v as f64 / 255.0;
    let dz = a.zona_muerta / 100.0;
    if !(x > dz && x > 0.01) {
        return 0.0;
    }
    if a.disparo_rapido {
        return 1.0;
    }
    let ext = swift_max(a.zona_externa / 100.0, dz + 0.01);
    swift_min((x - dz) / (ext - dz), 1.0).powf(swift_max(a.curva, 0.1))
}

fn eje(v: u8) -> f64 {
    (v as f64 - 127.5) / 127.5
}

fn byte(v: f64) -> u8 {
    swift_min(swift_max(127.5 + v * 127.5, 0.0), 255.0).round() as u8
}

// min y max de Swift: `min(a, b)` es `b < a ? b : a`, `max(a, b)` es `b > a ? b : a`
// (con NaN no coinciden con f64::min/max, que ignoran el NaN)
fn swift_min(a: f64, b: f64) -> f64 {
    if b < a { b } else { a }
}

fn swift_max(a: f64, b: f64) -> f64 {
    if b > a { b } else { a }
}

#[cfg(test)]
mod pruebas {
    use super::*;
    use serde_json::Value;

    /// La misma fórmula que pruebas/generar.swift (informes algo irregulares para probar dt y sus recortes)
    fn tiempo(i: usize) -> f64 {
        i as f64 / 1000.0 + (if i % 7 == 3 { 0.0004 } else { 0.0 }) + (if i % 97 == 50 { 0.06 } else { 0.0 })
    }

    fn estado(v: &[Value]) -> Estado {
        let n = |i: usize| v[i].as_u64().unwrap();
        Estado { botones: n(0) as u32, lx: n(1) as u8, ly: n(2) as u8, rx: n(3) as u8, ry: n(4) as u8, l2: n(5) as u8, r2: n(6) as u8 }
    }

    /// Mismas entradas que el procesador de Swift (pruebas/procesador.json, de ./pruebas/generar.sh):
    /// la salida tiene que ser idéntica en cada tick, byte a byte, y también el estado del anti-recoil,
    /// de la ayuda y la amplitud de la ayuda (en coma flotante, sin tolerancia).
    #[test]
    fn identico_al_de_swift() {
        let ruta = concat!(env!("CARGO_MANIFEST_DIR"), "/pruebas/procesador.json");
        let datos: Value = serde_json::from_slice(&std::fs::read(ruta).expect("falta pruebas/procesador.json")).unwrap();
        let mut total = 0;
        let mut fallos: Vec<String> = vec![];
        for esc in datos["escenarios"].as_array().unwrap() {
            let nombre = esc["nombre"].as_str().unwrap();
            let cambios: Vec<(usize, Perfil)> = esc["perfiles"].as_array().unwrap().iter()
                .map(|c| (c["tick"].as_u64().unwrap() as usize, serde_json::from_value(c["perfil"].clone()).expect("perfil no válido")))
                .collect();
            let mut perfil = cambios[0].1.clone();
            let mut pr = Procesador::new();
            let mut fallos_esc = 0;
            for (i, fila) in esc["ticks"].as_array().unwrap().iter().enumerate() {
                if let Some((_, p)) = cambios.iter().find(|(t, _)| *t == i) {
                    perfil = p.clone();
                }
                let f = fila.as_array().unwrap();
                let entrada = estado(&f[0..7]);
                let marcas = f[7].as_u64().unwrap();
                if marcas & 1 != 0 {
                    pr.alternar_anti_recoil();
                }
                if marcas & 2 != 0 {
                    pr.alternar_ayuda();
                }
                let s = pr.procesar(&entrada, &perfil, tiempo(i));
                let esperado = estado(&f[8..15]);
                let ar = f[15].as_u64().unwrap() == 1;
                let ay = f[16].as_u64().unwrap() == 1;
                let amplitud = f64::from_bits(u64::from_str_radix(f[17].as_str().unwrap(), 16).unwrap());
                total += 1;
                if s != esperado || pr.anti_recoil_encendido != ar || pr.ayuda_encendida != ay || pr.diagnostico.amplitud != amplitud {
                    fallos_esc += 1;
                    if fallos_esc <= 3 {
                        fallos.push(format!("{nombre} tick {i}: Rust {s:?} ar={} ay={} amp={} / Swift {esperado:?} ar={ar} ay={ay} amp={amplitud}",
                                            pr.anti_recoil_encendido, pr.ayuda_encendida, pr.diagnostico.amplitud));
                    }
                }
            }
            if fallos_esc > 0 {
                fallos.push(format!("{nombre}: {fallos_esc} ticks distintos"));
            }
        }
        assert!(total >= 50_000, "pocos ticks: {total}");
        assert!(fallos.is_empty(), "{} diferencias con Swift:\n{}", fallos.len(), fallos.join("\n"));
        println!("{total} ticks idénticos a los de Swift");
    }
}
