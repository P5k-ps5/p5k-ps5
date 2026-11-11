// El motor en la placa. Hace lo mismo que el bucle de la app de escritorio (escritorio/src-tauri/src/nucleo.rs)
// pero sin hilo propio: el firmware en C llama a `vuelta` cada milisegundo con lo que lee del mando real y
// usa lo que devuelve para la consola, y llama a `lento` cada poco para guardar y analizar ráfagas.
// Sin voz ni sonidos: los avisos salen en la página (como en el escritorio con los avisos de voz apagados).
// Lo que ve y cambia la página (instantánea, perfil, acciones) es el mismo JSON que en el escritorio.
use std::collections::VecDeque;
use std::path::Path;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Mutex;
use std::time::{Duration, Instant};

use serde_json::{json, Value};

use crate::medidor::{GrabadorRafagas, Medidor, Rafaga};
use crate::modelo::*;
use crate::procesador::{DiagnosticoAyuda, Procesador};

/// Lo que la página enseña además de lo de siempre (la pestaña Placa y el manual)
pub const CAPACIDADES: [&str; 2] = ["manual", "placa"];

/// Lo que se puede encender y apagar desde «En vivo» y vive en el motor (no en el perfil)
#[derive(Clone, Copy)]
pub enum Interruptor {
    AntiRecoil,
    Ayuda,
}

/// Lo que sabe el firmware del mando real (para «En vivo»)
#[derive(Default, Clone)]
pub struct InfoMando {
    pub conectado: bool,
    pub hz: i32,
    pub hueco_ms: f64,
    pub bateria: Option<i32>,
    pub bateria_estado: String,
    /// Informes por segundo que llegan a la consola
    pub envios: i32,
}

/// Lo que el motor deja para la página 30 veces por segundo
#[derive(Default, Clone)]
struct Directo {
    entrada: Estado,
    salida: Estado,
    vueltas_por_segundo: i32,
    peor_vuelta_ms: f64,
    anti_recoil: bool,
    ayuda: bool,
    diag: DiagnosticoAyuda,
    hx: VecDeque<f32>,
    hy: VecDeque<f32>,
    ha: VecDeque<f32>,
}

/// El estado del bucle: solo lo toca `vuelta`
struct Bucle {
    procesador: Procesador,
    version: u64,
    perfil: Perfil,
    generales: AjustesGenerales,
    botones_antes: u32,
    ar_antes: bool,
    ayuda_antes: bool,
    hist: (VecDeque<f32>, VecDeque<f32>, VecDeque<f32>),
    grabador: GrabadorRafagas,
    muestreado_en: f64,
    pintado_en: f64,
    contado_en: f64,
    anterior: f64,
    peor: f64,
    vueltas: i32,
    vueltas_seg: i32,
    peor_seg: f64,
}

pub struct Nucleo {
    pub almacen: Mutex<Almacen>,
    pub pausado: AtomicBool,
    directo: Mutex<Directo>,
    pedidos: Mutex<Vec<Interruptor>>,
    aviso: Mutex<Option<(u64, String)>>,
    pub medidor: Mutex<Medidor>,
    bucle: Mutex<Bucle>,
    /// Ráfagas de «Mi control» terminadas: se analizan y guardan en `lento`, fuera del bucle
    rafagas: Mutex<Vec<Rafaga>>,
    mando: Mutex<InfoMando>,
    /// Color con el que destellar la luz del mando (al encender o apagar el anti-recoil o la ayuda)
    destello: Mutex<Option<(u8, u8, u8)>>,
    /// (versión, pausa, revisión): ver `rev`
    rev_cache: Mutex<(u64, bool, String)>,
    /// (última versión vista, desde cuándo): para guardar cuando los cambios se calman
    guardado: Mutex<(u64, Instant)>,
}

/// Guardar en la flash para la caché y con ella el núcleo del mando: se espera a que dejen de llegar cambios
/// (p. ej. varios toques del atajo de fuerza seguidos) para grabar una sola vez
const CALMA_PARA_GUARDAR: Duration = Duration::from_secs(5);

impl Nucleo {
    /// Carga perfiles.json y medidor.json de la carpeta (en la placa, la partición de datos)
    pub fn arrancar(carpeta: &Path) -> Nucleo {
        let almacen = Almacen::cargar(carpeta.join("perfiles.json"));
        let generales = almacen.generales.clone();
        Nucleo {
            almacen: Mutex::new(almacen),
            pausado: AtomicBool::new(false),
            directo: Mutex::new(Directo::default()),
            pedidos: Mutex::new(vec![]),
            aviso: Mutex::new(None),
            medidor: Mutex::new(Medidor::cargar(carpeta.join("medidor.json"))),
            bucle: Mutex::new(Bucle {
                procesador: Procesador::new(),
                version: u64::MAX,
                perfil: Perfil::default(),
                generales,
                botones_antes: 0,
                ar_antes: false,
                ayuda_antes: false,
                hist: (VecDeque::new(), VecDeque::new(), VecDeque::new()),
                grabador: GrabadorRafagas::new(),
                muestreado_en: 0.0,
                pintado_en: 0.0,
                contado_en: 0.0,
                anterior: 0.0,
                peor: 0.0,
                vueltas: 0,
                vueltas_seg: 0,
                peor_seg: 0.0,
            }),
            rafagas: Mutex::new(vec![]),
            mando: Mutex::new(InfoMando::default()),
            destello: Mutex::new(None),
            rev_cache: Mutex::new((u64::MAX, false, String::new())),
            guardado: Mutex::new((u64::MAX, Instant::now())),
        }
    }

    pub fn revision(&self) -> String {
        let a = self.almacen.lock().unwrap();
        self.rev(&a)
    }

    /// La revisión de la página (cambia con cada cambio): recalcularla pasa todos los perfiles a JSON, así
    /// que se guarda hasta que cambie la versión del almacén o la pausa
    fn rev(&self, a: &Almacen) -> String {
        let pausado = self.pausado();
        let mut c = self.rev_cache.lock().unwrap();
        if c.0 != a.version || c.1 != pausado || c.2.is_empty() {
            *c = (a.version, pausado, a.revision(pausado));
        }
        c.2.clone()
    }

    /// Color del perfil activo («#RRGGBB»), para la luz del mando
    pub fn color(&self) -> String {
        self.almacen.lock().unwrap().activo().color.clone()
    }

    pub fn clave(&self) -> String {
        self.almacen.lock().unwrap().generales.clave.clone()
    }

    pub fn alternar(&self, i: Interruptor) {
        self.pedidos.lock().unwrap().push(i);
    }

    pub fn pausado(&self) -> bool {
        self.pausado.load(Ordering::Relaxed)
    }

    pub fn poner_pausa(&self, p: bool) {
        self.pausado.store(p, Ordering::Relaxed);
    }

    pub fn poner_mando(&self, info: InfoMando) {
        *self.mando.lock().unwrap() = info;
    }

    pub fn tomar_destello(&self) -> Option<(u8, u8, u8)> {
        self.destello.lock().unwrap().take()
    }

    /// Un aviso en la página (la placa no habla)
    pub fn anunciar(&self, texto: &str) {
        let mut a = self.aviso.lock().unwrap();
        let id = a.as_ref().map(|x| x.0).unwrap_or(0) + 1;
        *a = Some((id, texto.to_string()));
    }

    // MARK: - El motor: una vuelta cada milisegundo

    /// `entrada`: lo que llega del mando real (None si no hay mando). Devuelve lo que va a la consola.
    pub fn vuelta(&self, entrada: Option<Estado>, t: f64) -> Estado {
        let mut b = self.bucle.lock().unwrap();
        let b = &mut *b;
        b.vueltas += 1;
        if b.anterior > 0.0 {
            b.peor = b.peor.max(t - b.anterior);
        }
        b.anterior = t;

        // El perfil y los ajustes, solo si han cambiado. Sin esperar: si la página o el guardado tienen el
        // almacén en ese momento, se sigue con el perfil que ya hay y se recoge el nuevo en la vuelta siguiente
        // (en el escritorio el motor espera; aquí el bucle de 1 ms no puede).
        if let Ok(a) = self.almacen.try_lock() {
            if a.version != b.version {
                b.version = a.version;
                b.perfil = a.activo().clone();
                b.generales = a.generales.clone();
            }
        }
        for pedido in std::mem::take(&mut *self.pedidos.lock().unwrap()) {
            match pedido {
                Interruptor::AntiRecoil => b.procesador.alternar_anti_recoil(),
                Interruptor::Ayuda => b.procesador.alternar_ayuda(),
            }
        }

        let pausa = self.pausado();
        let mut e = entrada.unwrap_or_default();
        let generales = &b.generales;
        let perfil = &b.perfil;

        // Combinaciones del mando: fuerza del anti-recoil, ajustes rápidos, patrón de la ayuda, macros y perfil
        let flanco = e.botones & !b.botones_antes;
        b.botones_antes = e.botones;
        let (fuerza, paso_fuerza, paso_lateral) = combo_fuerza(&mut e, flanco, generales);
        if paso_fuerza != 0 {
            let frase = self.almacen.lock().unwrap().ajustar_fuerza(paso_fuerza);
            self.anunciar(&frase);
        }
        if paso_lateral != 0 {
            let frase = self.almacen.lock().unwrap().ajustar_lateral(paso_lateral);
            self.anunciar(&frase);
        }
        if generales.ajuste_mando && !(fuerza && generales.ajuste_mantener == generales.fuerza_mantener) && e.pulsado(generales.ajuste_mantener) {
            let dv = if flanco & Boton::Arriba.bit() != 0 { 1 } else if flanco & Boton::Abajo.bit() != 0 { -1 } else { 0 };
            let dp = if flanco & Boton::Derecha.bit() != 0 { 1 } else if flanco & Boton::Izquierda.bit() != 0 { -1 } else { 0 };
            if dv != 0 || dp != 0 {
                let frase = self.almacen.lock().unwrap().ajuste_rapido(dp, dv);
                self.anunciar(&frase);
            }
        }
        let ay = &perfil.ayuda;
        if ay.cambio_activo && e.pulsado(ay.cambio_mantener) {
            let paso = if flanco & ay.cambio_siguiente.bit() != 0 { 1 } else if flanco & ay.cambio_anterior.bit() != 0 { -1 } else { 0 };
            if paso != 0 {
                let nombre = self.almacen.lock().unwrap().cambiar_patron_ayuda(paso);
                self.anunciar(&nombre);
            }
        }
        if flanco != 0 {
            for id in combo_macros(&e, flanco, perfil) {
                if let Some(f) = self.almacen.lock().unwrap().alternar_macro(&id) {
                    self.anunciar(&f);
                }
            }
        }
        if generales.cambio_perfil && e.pulsado(generales.cambio_mantener) {
            let paso = if flanco & generales.cambio_siguiente.bit() != 0 { 1 } else if flanco & generales.cambio_anterior.bit() != 0 { -1 } else { 0 };
            if paso != 0 {
                let nombre = {
                    let mut a = self.almacen.lock().unwrap();
                    if a.perfiles.len() > 1 {
                        a.cambiar_perfil(paso);
                        Some((a.activo().nombre.clone(), a.generales.decir_nombre))
                    } else {
                        None
                    }
                };
                if let Some((n, decir)) = nombre {
                    if decir {
                        self.anunciar(&n);
                    }
                }
            }
        }

        // «Mi control»: mide tu mano (la entrada), antes de procesar nada. El análisis, en `lento`.
        if generales.medidor.activo && entrada.is_some() {
            if let Some(r) = b.grabador.tick(&e, t, &generales.medidor, &perfil.nombre) {
                self.rafagas.lock().unwrap().push(r);
            }
        } else {
            b.grabador.cortar();
        }
        let s = if pausa || entrada.is_none() { Estado::default() } else { b.procesador.procesar(&e, perfil, t) };

        // Avisos al encender o apagar el anti-recoil y la ayuda: destello en la luz del mando
        if b.procesador.anti_recoil_encendido != b.ar_antes {
            b.ar_antes = b.procesador.anti_recoil_encendido;
            *self.destello.lock().unwrap() = Some(if b.ar_antes { (0, 255, 0) } else { (255, 0, 0) });
        }
        if b.procesador.ayuda_encendida != b.ayuda_antes {
            b.ayuda_antes = b.procesador.ayuda_encendida;
            *self.destello.lock().unwrap() = Some(if b.ayuda_antes { (0, 255, 255) } else { (255, 128, 0) });
        }

        // Diagnóstico de la ayuda: 100 muestras por segundo
        if t - b.muestreado_en >= 0.01 {
            b.muestreado_en = t;
            let d = &b.procesador.diagnostico;
            for (cola, v) in [(&mut b.hist.0, d.off_x), (&mut b.hist.1, d.off_y), (&mut b.hist.2, d.amplitud)] {
                cola.push_back(v as f32);
                if cola.len() > 400 {
                    cola.pop_front();
                }
            }
        }
        if t - b.contado_en >= 1.0 {
            b.vueltas_seg = b.vueltas;
            b.vueltas = 0;
            b.peor_seg = b.peor * 1000.0;
            b.peor = 0.0;
            b.contado_en = t;
        }
        if t - b.pintado_en >= 1.0 / 30.0 {
            b.pintado_en = t;
            let mut d = self.directo.lock().unwrap();
            d.entrada = e;
            d.salida = s;
            d.vueltas_por_segundo = b.vueltas_seg;
            d.peor_vuelta_ms = b.peor_seg;
            d.anti_recoil = b.procesador.anti_recoil_encendido;
            d.ayuda = b.procesador.ayuda_encendida;
            d.diag = b.procesador.diagnostico.clone();
            d.hx = b.hist.0.clone();
            d.hy = b.hist.1.clone();
            d.ha = b.hist.2.clone();
        }
        s
    }

    /// Lo que no cabe en el bucle de 1 ms: guardar los cambios y analizar las ráfagas de «Mi control»
    pub fn lento(&self) {
        {
            let ahora = Instant::now();
            let mut g = self.guardado.lock().unwrap();
            let mut a = self.almacen.lock().unwrap();
            if a.version != g.0 {
                *g = (a.version, ahora);
            }
            if a.sucio && ahora.duration_since(g.1) >= CALMA_PARA_GUARDAR {
                a.guardar_ahora();
            }
        }
        let pendientes = std::mem::take(&mut *self.rafagas.lock().unwrap());
        for (x, abajo, nombre) in pendientes {
            let r = crate::medidor::analizar(&x, &abajo, &nombre, crate::medidor::ahora_2001());
            self.medidor.lock().unwrap().anadir(r, x, abajo);
        }
    }

    // MARK: - Lo que ve y cambia la página (mismo JSON que la app de escritorio)

    pub fn instantanea(&self) -> String {
        let d = self.directo.lock().unwrap().clone();
        let info = self.mando.lock().unwrap().clone();
        let a = self.almacen.lock().unwrap();
        let p = a.activo();
        let pausado = self.pausado();
        let estado = |e: &Estado| json!({"b": e.botones, "lx": e.lx, "ly": e.ly, "rx": e.rx, "ry": e.ry, "l2": e.l2, "r2": e.r2});
        let r3 = |v: f64| (v * 1000.0).round() / 1000.0;
        let ultimas = |v: &VecDeque<f32>| -> Vec<i64> {
            v.iter().skip(v.len().saturating_sub(150)).map(|x| (*x as f64 * 1000.0).round() as i64).collect()
        };
        let g = &d.diag;
        let diag = json!({
            "on": g.encendida, "ap": g.aplicando, "forma": if g.forma == Forma::Circulo { "circulo" } else { "temblor" },
            "t": r3(g.tamano), "hz": r3(g.hz), "e": r3(g.entrada_ms), "c": r3(g.ceder), "lim": g.limitada,
            "ramp": r3(g.rampa), "ces": r3(g.cesion), "amp": r3(g.amplitud), "fase": r3(g.fase), "tr": g.en_transicion,
            "hx": ultimas(&d.hx), "hy": ultimas(&d.hy), "ha": ultimas(&d.ha),
        });
        let aviso = self.aviso.lock().unwrap().clone();
        let widgets: Vec<Value> = p.widgets.iter()
            .filter_map(|w| estado_widget(w, p, d.anti_recoil, d.ayuda, pausado))
            .map(|e| json!({"id": e.id, "nombre": e.nombre, "detalle": e.detalle, "on": e.encendido, "tipo": e.tipo.clave()}))
            .collect();
        // Monitor de la señal: analiza las últimas 200 muestras (2 s), como el escritorio
        let mut monitor = json!({"activo": a.generales.monitor.activo});
        if a.generales.monitor.activo {
            let ult = |v: &VecDeque<f32>| -> Vec<f32> { v.iter().skip(v.len().saturating_sub(200)).copied().collect() };
            let inf = crate::monitor::analizar(&ult(&d.hx), &ult(&d.hy), 0.01, &a.generales.monitor);
            let me = &inf.metricas;
            monitor["estado"] = json!(inf.estado.nombre());
            monitor["gravedad"] = json!(inf.estado as i32);
            monitor["metricas"] = json!({
                "muestras": me.muestras, "maxAbs": r3(me.max_abs), "maxSalto": r3(me.max_salto),
                "maxVelocidad": r3(me.max_velocidad), "maxAceleracion": r3(me.max_aceleracion),
                "cambiosSigno": r3(me.cambios_signo), "noNumericos": me.no_numericos,
            });
            monitor["eventos"] = json!(inf.eventos.iter().take(8).map(|e| json!({
                "g": e.gravedad.nombre(), "a": e.gravedad == crate::monitor::Gravedad::Anomalia, "i": e.indice, "eje": e.eje,
                "motivo": e.motivo, "v": if e.valor.is_finite() { json!(r3(e.valor)) } else { Value::Null }, "lim": r3(e.limite),
            })).collect::<Vec<_>>());
            monitor["mas"] = json!(inf.eventos.len().saturating_sub(8) + inf.eventos_omitidos);
        }
        let funciones: Vec<Value> = resumen_funciones(p, &a.generales, d.anti_recoil, d.ayuda).into_iter()
            .map(|f| json!({"nombre": f.nombre, "detalle": f.detalle, "on": f.encendida}))
            .collect();
        json!({
            "diag": diag,
            "monitor": monitor,
            "entrada": estado(&d.entrada), "salida": estado(&d.salida),
            "mando": if info.conectado { Some("DualSense") } else { None },
            "esp": true, "envios": info.envios,
            "mandoRitmo": {"hz": info.hz, "huecoMs": info.hueco_ms.round() as i64,
                           "conexion": if info.conectado { Some("USB") } else { None }},
            "bateria": {"porcentaje": info.bateria,
                        "estado": if info.bateria_estado.is_empty() { "desconocido" } else { info.bateria_estado.as_str() }},
            "funciones": funciones,
            "bucle": {"vueltas": d.vueltas_por_segundo, "peorMs": (d.peor_vuelta_ms * 10.0).round() / 10.0},
            "pausado": pausado, "antiRecoil": d.anti_recoil, "ayuda": d.ayuda,
            "aviso": aviso.map(|(id, texto)| json!({"id": id, "texto": texto})),
            "widgets": widgets,
            "rev": self.rev(&a),
            "perfil": {"nombre": p.nombre, "color": p.color},
        }).to_string()
    }

    /// El perfil activo entero, la lista de perfiles y los ajustes generales (sin la clave)
    pub fn perfil_json(&self) -> String {
        let a = self.almacen.lock().unwrap();
        let mut generales = serde_json::to_value(&a.generales).unwrap_or(Value::Null);
        if let Some(o) = generales.as_object_mut() {
            o.remove("clave");
            o.remove("servidorMovil");
        }
        let p = a.activo();
        let pausado = self.pausado();
        json!({
            "perfiles": a.perfiles.iter().map(|p| json!({"id": p.id, "nombre": p.nombre, "color": p.color})).collect::<Vec<_>>(),
            "activo": a.activo_id,
            "perfil": p,
            "generales": generales,
            "pausado": pausado,
            "capacidades": CAPACIDADES,
            "catalogo": catalogo_widgets(p).iter().map(|w| json!({
                "tipo": w.tipo.clave(), "objetivo": w.objetivo.clone().unwrap_or_default(), "nombre": nombre_widget(w, p)
            })).collect::<Vec<_>>(),
            "rev": self.rev(&a),
        }).to_string()
    }

    // MARK: - Sincronización con las apps (por el cable): los mismos ajustes en la placa y en el ordenador

    /// Lo que se sincroniza con las apps (lo mismo que calculan ellas: modelo::Almacen)
    pub fn ajustes_json(&self) -> String {
        self.almacen.lock().unwrap().ajustes_sincronizados()
    }

    /// Revisión de unos ajustes: FNV-1a de 64 bits del JSON (estable entre arranques y versiones)
    pub fn revision_ajustes(json: &str) -> String {
        let mut h: u64 = 0xcbf29ce484222325;
        for b in json.as_bytes() {
            h ^= *b as u64;
            h = h.wrapping_mul(0x100000001b3);
        }
        format!("{h:016x}")
    }

    /// Pone los ajustes que manda una app (y los guarda ya). Se queda con la clave y el acceso por la red.
    pub fn poner_ajustes(&self, json: &str) -> Result<String, String> {
        {
            let mut a = self.almacen.lock().unwrap();
            a.poner_ajustes_sincronizados(json)?;
            a.guardar_ahora();
        }
        Ok(Nucleo::revision_ajustes(&self.ajustes_json()))
    }

    pub fn medidor_json(&self) -> String {
        self.medidor.lock().unwrap().json().to_string()
    }

    /// Tocar un widget. false si ya no existe.
    pub fn alternar_widget(&self, id: &str) -> bool {
        let mut a = self.almacen.lock().unwrap();
        let Some(w) = a.activo().widgets.iter().find(|w| w.id == id).cloned() else { return false };
        match w.tipo {
            TipoWidget::AntiRecoil => self.alternar(Interruptor::AntiRecoil),
            TipoWidget::Ayuda => self.alternar(Interruptor::Ayuda),
            TipoWidget::Pausa => self.poner_pausa(!self.pausado()),
            TipoWidget::Turbos => { a.alternar_turbos(); }
            TipoWidget::Macros => { a.alternar_macros(); }
            TipoWidget::Turbo => return w.objetivo.and_then(|o| a.alternar_turbo(&o)).is_some(),
            TipoWidget::Macro => return w.objetivo.and_then(|o| a.alternar_macro(&o)).is_some(),
        }
        true
    }

    /// Un cambio que llega de la página (mismas acciones que el escritorio)
    pub fn aplicar(&self, accion: &Value) -> Value {
        let s = |k: &str| accion.get(k).and_then(|v| v.as_str()).map(|v| v.to_string());
        let mut info: Option<String> = None;
        let mut nueva: Option<String> = None;
        let error: Option<String> = match s("accion").as_deref() {
            Some("poner") => match (s("ruta"), accion.get("valor")) {
                (Some(r), Some(v)) => self.almacen.lock().unwrap().poner_ruta(&r, v.clone()),
                _ => Some("falta la ruta o el valor".into()),
            },
            Some("perfil") => match s("id") {
                Some(id) => { self.almacen.lock().unwrap().seleccionar(&id); None }
                None => Some("perfil no válido".into()),
            },
            Some("situaciones") => {
                let n = self.almacen.lock().unwrap().crear_perfiles_por_situacion();
                info = Some(if n == 0 { "Ya existen «Corto alcance» y «Largo alcance»".into() }
                            else { format!("Añadidos {n} perfil{}", if n == 1 { "" } else { "es" }) });
                None
            }
            Some("medidorBorrar") => { self.medidor.lock().unwrap().borrar_todo(); None }
            Some("cambiarClave") => {
                let mut a = self.almacen.lock().unwrap();
                let mut g = a.generales.clone();
                g.clave = nueva_clave();
                info = Some("Clave cambiada: vuelve a abrir la dirección nueva en los móviles".into());
                nueva = Some(g.clave.clone());
                a.poner_generales(g);
                None
            }
            Some("patron") => match accion.get("indice").and_then(|v| v.as_u64()) {
                Some(i) => { self.almacen.lock().unwrap().usar_patron_ayuda(i as usize); None }
                None => Some("patrón no válido".into()),
            },
            Some("variante") => {
                let mut a = self.almacen.lock().unwrap();
                match s("modo").as_deref() {
                    Some("usar") => match s("id") { Some(id) => { a.usar_variante_ayuda(&id); None } None => Some("variante no válida".into()) },
                    Some("guardar") => { a.guardar_variante_ayuda(&s("nombre").unwrap_or_default()); None }
                    Some("actualizar") => { a.actualizar_variante_ayuda(); None }
                    Some("borrar") => match s("id") { Some(id) => { a.borrar_variante_ayuda(&id); None } None => Some("variante no válida".into()) },
                    _ => Some("modo desconocido".into()),
                }
            }
            Some("nuevo") => { self.almacen.lock().unwrap().nuevo(); None }
            Some("duplicar") => { self.almacen.lock().unwrap().duplicar(); None }
            Some("borrar") => { self.almacen.lock().unwrap().borrar_activo(); None }
            Some("pausa") => { self.poner_pausa(accion.get("valor").and_then(|v| v.as_bool()).unwrap_or(false)); None }
            Some("widget") => match s("id") {
                Some(id) => if self.alternar_widget(&id) { None } else { Some("Ese widget ya no existe".into()) },
                None => Some("widget no válido".into()),
            },
            Some("widgetAnadir") => {
                let mut a = self.almacen.lock().unwrap();
                if s("tipo").as_deref() == Some("basicos") {
                    for w in widgets_basicos(a.activo()) {
                        a.anadir_widget(w);
                    }
                    None
                } else {
                    match s("tipo").as_deref().and_then(TipoWidget::de_clave) {
                        Some(tipo) => {
                            let objetivo = s("objetivo").filter(|o| !o.is_empty());
                            a.anadir_widget(Widget::de(tipo, objetivo));
                            None
                        }
                        None => Some("widget no válido".into()),
                    }
                }
            }
            Some("widgetQuitar") => match s("id") {
                Some(id) => { self.almacen.lock().unwrap().quitar_widget(&id); None }
                None => Some("widget no válido".into()),
            },
            Some("widgetMover") => match (s("id"), accion.get("paso").and_then(|v| v.as_i64())) {
                (Some(id), Some(p)) => { self.almacen.lock().unwrap().mover_widget(&id, p as i32); None }
                _ => Some("widget no válido".into()),
            },
            Some("servidorMovil") => Some("En la placa el acceso por la red está siempre encendido".into()),
            _ => Some("acción desconocida".into()),
        };
        let rev = self.revision();
        let mut r = match error {
            None => json!({"ok": true, "rev": rev}),
            Some(e) => json!({"ok": false, "error": e, "rev": rev}),
        };
        if let Some(i) = info {
            r["info"] = json!(i);
        }
        if let Some(k) = nueva {
            r["clave"] = json!(k);
        }
        r
    }
}

#[cfg(test)]
mod pruebas {
    use super::*;

    fn carpeta() -> std::path::PathBuf {
        let d = std::env::temp_dir().join(format!("motor-placa-{}", nuevo_id()));
        std::fs::create_dir_all(&d).unwrap();
        d
    }

    #[test]
    fn arranca_guarda_y_contesta_como_el_escritorio() {
        let dir = carpeta();
        let n = Nucleo::arrancar(&dir);
        assert!(dir.join("perfiles.json").exists(), "guarda al arrancar (con la clave nueva)");
        let p: Value = serde_json::from_str(&n.perfil_json()).unwrap();
        assert_eq!(p["capacidades"], json!(["manual", "placa"]));
        assert!(p["generales"].get("clave").is_none(), "la clave no sale en /perfil");
        assert_eq!(n.clave().len(), p["generales"].as_object().map(|_| n.clave().len()).unwrap());

        // Un cambio de la página se guarda en `lento`
        let r = n.aplicar(&json!({"accion": "poner", "ruta": "antiRecoil.vertical", "valor": 33}));
        assert_eq!(r["ok"], json!(true), "{r}");
        n.lento();
        let sin_guardar = std::fs::read_to_string(dir.join("perfiles.json")).unwrap();
        assert!(!sin_guardar.contains("\"vertical\" : 33") && !sin_guardar.contains("\"vertical\": 33"), "espera a que se calmen los cambios");
        *n.guardado.lock().unwrap() = (n.almacen.lock().unwrap().version, Instant::now() - CALMA_PARA_GUARDAR);
        n.lento();
        let guardado = std::fs::read_to_string(dir.join("perfiles.json")).unwrap();
        assert!(guardado.contains("\"vertical\" : 33") || guardado.contains("\"vertical\": 33"), "{guardado}");
        let otra = Nucleo::arrancar(&dir);
        assert_eq!(otra.almacen.lock().unwrap().activo().anti_recoil.vertical, 33.0);
    }

    #[test]
    fn sin_mando_manda_reposo_y_con_mando_procesa() {
        let n = Nucleo::arrancar(&carpeta());
        let reposo = n.vuelta(None, 0.001);
        assert_eq!(reposo, Estado::default());
        let mut e = Estado::default();
        e.botones = Boton::X.bit();
        e.lx = 200;
        let s = n.vuelta(Some(e), 0.002);
        assert!(s.pulsado(Boton::X), "sin ajustes, la X pasa");
        // La instantánea es JSON válido y lleva lo que pinta «En vivo»
        for k in 1..100 {
            n.vuelta(Some(e), 0.002 + k as f64 * 0.001);
        }
        let i: Value = serde_json::from_str(&n.instantanea()).unwrap();
        assert_eq!(i["esp"], json!(true));
        assert!(i["entrada"]["b"].as_u64().unwrap() & Boton::X.bit() as u64 != 0);
    }

    #[test]
    fn ajustes_ida_y_vuelta() {
        let n = Nucleo::arrancar(&carpeta());
        let clave = n.clave();
        let j = n.ajustes_json();
        assert!(!j.contains("\"clave\"") && !j.contains("servidorMovil"), "sin lo que es de cada aparato");
        let rev = Nucleo::revision_ajustes(&j);
        assert_eq!(rev, Nucleo::revision_ajustes(&n.ajustes_json()), "mismo contenido, misma revisión");
        // Otra «app» con dos perfiles y otra clave: la placa se queda sus perfiles pero no su clave
        let otra = Nucleo::arrancar(&carpeta());
        otra.aplicar(&json!({"accion": "nuevo"}));
        otra.aplicar(&json!({"accion": "poner", "ruta": "antiRecoil.vertical", "valor": 41}));
        let nueva = n.poner_ajustes(&otra.ajustes_json()).unwrap();
        assert_ne!(nueva, rev);
        assert_eq!(nueva, Nucleo::revision_ajustes(&n.ajustes_json()));
        assert_eq!(n.almacen.lock().unwrap().perfiles.len(), 2);
        assert_eq!(n.almacen.lock().unwrap().activo().anti_recoil.vertical, 41.0);
        assert_eq!(n.clave(), clave, "la clave de la placa no cambia");
        assert_eq!(n.ajustes_json(), otra.ajustes_json(), "quedan iguales");
        assert!(n.poner_ajustes("{\"perfiles\": []}").is_err());
        assert!(n.poner_ajustes("no es json").is_err());
    }

    #[test]
    fn pausa_manda_reposo() {
        let n = Nucleo::arrancar(&carpeta());
        n.aplicar(&json!({"accion": "pausa", "valor": true}));
        let mut e = Estado::default();
        e.botones = Boton::X.bit();
        assert_eq!(n.vuelta(Some(e), 0.01), Estado::default());
    }

    #[test]
    fn el_informe_usb_del_dualsense_se_lee_igual() {
        // Captura real del mando del usuario (la del autotest del firmware): sticks al centro, sin botones
        let mut r = vec![0u8; 64];
        r[..12].copy_from_slice(&[0x01, 0x82, 0x7b, 0x7e, 0x83, 0x00, 0x00, 0xec, 0x08, 0x00, 0x00, 0x00]);
        let i = crate::dualsense_informe::analizar(&r).unwrap();
        assert_eq!((i.estado.lx, i.estado.ly, i.estado.rx, i.estado.ry), (130, 123, 126, 131));
        assert_eq!(i.estado.botones, 0);
    }
}
