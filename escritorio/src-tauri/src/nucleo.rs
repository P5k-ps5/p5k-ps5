// El puente en marcha: el bucle del motor (DualSense → perfil → ESP32, unas 1000 veces por segundo),
// lo que comparten el motor, el servidor del móvil y la ventana, y las acciones del móvil y de los widgets.
// Es el mismo comportamiento que la app de Mac (app/Motor.swift y Delegado en app/Vistas.swift).
use std::collections::VecDeque;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Mutex};
use std::thread;
use std::time::{Duration, Instant};

use serde_json::{json, Value};

use crate::dualsense::Mando;
use crate::esp32::Esp32;
use crate::medidor::{GrabadorRafagas, Medidor};
use crate::modelo::*;
use crate::procesador::{DiagnosticoAyuda, Procesador};
use crate::sincro::Sincro;
use crate::sistema::{sonar, Sonido};

/// Lo que se puede encender y apagar desde «En vivo» y vive en el motor (no en el perfil)
#[derive(Clone, Copy)]
pub enum Interruptor {
    AntiRecoil,
    Ayuda,
}

/// Lo que el motor deja para los demás 30 veces por segundo
#[derive(Default, Clone)]
pub struct Directo {
    pub entrada: Estado,
    pub salida: Estado,
    pub esp_ruta: Option<String>,
    /// Sincronización de los ajustes con la placa («al día», «enviando», «sin placa»…)
    pub sincro: &'static str,
    pub envios_por_segundo: i32,
    pub vueltas_por_segundo: i32,
    pub peor_vuelta_ms: f64,
    pub anti_recoil: bool,
    pub ayuda: bool,
    pub diag: DiagnosticoAyuda,
    /// Últimas muestras de la ayuda (100 por segundo): desplazamiento x, y y amplitud
    pub hx: VecDeque<f32>,
    pub hy: VecDeque<f32>,
    pub ha: VecDeque<f32>,
}

pub struct Nucleo {
    pub almacen: Mutex<Almacen>,
    pub pausado: AtomicBool,
    pub mando: Mando,
    pub directo: Mutex<Directo>,
    pedidos: Mutex<Vec<Interruptor>>,
    aviso: Mutex<Option<(u64, String)>>,
    /// Mientras se graba el firmware o se pregunta el modo por el COM, el motor suelta la placa
    pub soltar_placa: AtomicBool,
    /// «Mi control»: el historial de ráfagas (medidor.json)
    pub medidor: Arc<Mutex<Medidor>>,
}

/// Lo que esta app ofrece además de lo que tiene la página de siempre: la página enseña esas secciones
/// solo si están aquí (la app de Mac no manda la lista y sigue funcionando igual)
pub const CAPACIDADES: [&str; 2] = ["movil", "manual"];

impl Nucleo {
    pub fn arrancar() -> Arc<Nucleo> {
        // Para probar junto a la app de Mac sin tocar nada suyo: PUENTE_ARCHIVO (otra copia de los perfiles)
        // y PUENTE_SIN_PLACA (no abrir la placa). PUENTE_PUERTO está en el servidor.
        let archivo = std::env::var_os("PUENTE_ARCHIVO").map(std::path::PathBuf::from).unwrap_or_else(archivo_por_defecto);
        // El historial de «Mi control» va al lado de los perfiles (con PUENTE_ARCHIVO, al lado de esa copia)
        let archivo_medidor = archivo.with_file_name("medidor.json");
        let almacen = Almacen::cargar(archivo);
        crate::sistema::no_dormir();
        let n = Arc::new(Nucleo {
            almacen: Mutex::new(almacen),
            pausado: AtomicBool::new(false),
            mando: Mando::arrancar(),
            directo: Mutex::new(Directo::default()),
            pedidos: Mutex::new(vec![]),
            aviso: Mutex::new(None),
            soltar_placa: AtomicBool::new(std::env::var_os("PUENTE_SIN_PLACA").is_some()),
            medidor: Arc::new(Mutex::new(Medidor::cargar(archivo_medidor))),
        });
        let motor = n.clone();
        thread::Builder::new().name("motor".into()).spawn(move || motor.bucle()).unwrap();
        // Los cambios se guardan medio segundo después del último (como en Mac)
        let guardar = n.clone();
        thread::spawn(move || loop {
            thread::sleep(Duration::from_millis(500));
            let mut a = guardar.almacen.lock().unwrap();
            if a.sucio {
                a.guardar_ahora();
            }
        });
        n
    }

    pub fn servidor_movil(&self) -> bool {
        self.almacen.lock().unwrap().generales.servidor_movil
    }

    pub fn poner_servidor_movil(&self, activo: bool) {
        let mut a = self.almacen.lock().unwrap();
        let mut g = a.generales.clone();
        g.servidor_movil = activo;
        a.poner_generales(g);
    }

    pub fn revision(&self) -> String {
        self.almacen.lock().unwrap().revision(self.pausado())
    }

    pub fn clave(&self) -> String {
        self.almacen.lock().unwrap().generales.clave.clone()
    }

    /// Un widget pide encender o apagar algo del motor: lo hace el hilo del motor en la siguiente vuelta
    pub fn alternar(&self, i: Interruptor) {
        self.pedidos.lock().unwrap().push(i);
    }

    pub fn pausado(&self) -> bool {
        self.pausado.load(Ordering::Relaxed)
    }

    pub fn poner_pausa(&self, p: bool) {
        self.pausado.store(p, Ordering::Relaxed);
    }

    /// En voz alta (voz del sistema) o, con los avisos de voz apagados, como un aviso en pantalla
    pub fn anunciar(&self, texto: &str) {
        let con_voz = self.almacen.lock().unwrap().generales.avisos_voz;
        if con_voz {
            hablar(texto);
        } else {
            let mut a = self.aviso.lock().unwrap();
            let id = a.as_ref().map(|x| x.0).unwrap_or(0) + 1;
            *a = Some((id, texto.to_string()));
        }
    }

    // MARK: - El motor

    fn bucle(self: Arc<Self>) {
        prioridad_maxima();
        let mut esp = Esp32::new();
        let mut procesador = Procesador::new();
        let mut ultimo_enviado: Option<Estado> = None;
        let inicio = Instant::now();
        let ahora = || inicio.elapsed().as_secs_f64();
        let (mut enviado_en, mut reintento_en, mut pintado_en, mut contado_en, mut muestreado_en) = (0.0, 0.0, 0.0, 0.0, 0.0);
        let (mut envios, mut por_segundo, mut vueltas, mut vueltas_seg) = (0, 0, 0, 0);
        let (mut anterior, mut peor, mut peor_seg) = (ahora(), 0.0f64, 0.0f64);
        let mut botones_antes: u32 = 0;
        let mut version = u64::MAX;
        let mut perfil = Perfil::default();
        let mut generales = AjustesGenerales::default();
        let mut color = String::new();
        let (mut ar_antes, mut ayuda_antes) = (false, false);
        let mut hist = (VecDeque::new(), VecDeque::new(), VecDeque::new());
        let mut grabador = GrabadorRafagas::new();
        // Los mismos ajustes en la placa y aquí (sincro.rs)
        let mut sincro = {
            let a = self.almacen.lock().unwrap();
            Sincro::new(a.archivo(), a.version)
        };

        loop {
            let t = ahora();
            vueltas += 1;
            peor = peor.max(t - anterior);
            anterior = t;

            // La placa: se suelta si hace falta (grabar el firmware) y se reintenta cada segundo
            if self.soltar_placa.load(Ordering::Relaxed) {
                if esp.conectado() {
                    esp = Esp32::new();
                    ultimo_enviado = None;
                }
            } else if !esp.conectado() && t >= reintento_en {
                reintento_en = t + 1.0;
                if esp.conectar() {
                    ultimo_enviado = None;
                }
            }

            // Ajustes con la placa: recoger los suyos (cambiados desde el móvil) y mandarle los de aquí
            if let Some(aviso) = sincro.vuelta(&mut esp, &self.almacen, t) {
                self.anunciar(&aviso);
            }

            // El perfil y los ajustes, solo si han cambiado
            {
                let a = self.almacen.lock().unwrap();
                if a.version != version {
                    version = a.version;
                    perfil = a.activo().clone();
                    generales = a.generales.clone();
                }
            }
            if perfil.color != color {
                color = perfil.color.clone();
                self.mando.poner_color(&color);
            }
            for pedido in std::mem::take(&mut *self.pedidos.lock().unwrap()) {
                match pedido {
                    Interruptor::AntiRecoil => procesador.alternar_anti_recoil(),
                    Interruptor::Ayuda => procesador.alternar_ayuda(),
                }
            }

            let pausa = self.pausado();
            let mando = self.mando.estado();
            let mut e = mando.unwrap_or_default();

            // Combinaciones del mando: fuerza del anti-recoil, ajustes rápidos, patrón de la ayuda, macros y perfil
            let flanco = e.botones & !botones_antes;
            botones_antes = e.botones;
            let (fuerza, paso_fuerza, paso_lateral) = combo_fuerza(&mut e, flanco, &generales);
            if paso_fuerza != 0 {
                let frase = self.almacen.lock().unwrap().ajustar_fuerza(paso_fuerza);
                sonar(Sonido::Tink);
                self.anunciar(&frase);
            }
            if paso_lateral != 0 {
                let frase = self.almacen.lock().unwrap().ajustar_lateral(paso_lateral);
                sonar(Sonido::Tink);
                self.anunciar(&frase);
            }
            if generales.ajuste_mando && !(fuerza && generales.ajuste_mantener == generales.fuerza_mantener) && e.pulsado(generales.ajuste_mantener) {
                let dv = if flanco & Boton::Arriba.bit() != 0 { 1 } else if flanco & Boton::Abajo.bit() != 0 { -1 } else { 0 };
                let dp = if flanco & Boton::Derecha.bit() != 0 { 1 } else if flanco & Boton::Izquierda.bit() != 0 { -1 } else { 0 };
                if dv != 0 || dp != 0 {
                    let frase = self.almacen.lock().unwrap().ajuste_rapido(dp, dv);
                    sonar(Sonido::Tink);
                    self.anunciar(&frase);
                }
            }
            let ay = &perfil.ayuda;
            if ay.cambio_activo && e.pulsado(ay.cambio_mantener) {
                let paso = if flanco & ay.cambio_siguiente.bit() != 0 { 1 } else if flanco & ay.cambio_anterior.bit() != 0 { -1 } else { 0 };
                if paso != 0 {
                    let nombre = self.almacen.lock().unwrap().cambiar_patron_ayuda(paso);
                    sonar(Sonido::Morse);
                    self.anunciar(&nombre);
                }
            }
            if flanco != 0 {
                for id in combo_macros(&e, flanco, &perfil) {
                    let (frase, activa) = {
                        let mut a = self.almacen.lock().unwrap();
                        let f = a.alternar_macro(&id);
                        (f, a.activo().macros.iter().any(|m| m.id == id && m.activa))
                    };
                    if let Some(f) = frase {
                        sonar(if activa { Sonido::Glass } else { Sonido::Bottle });
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
                        sonar(Sonido::Pop);
                        if decir {
                            self.anunciar(&n);
                        }
                    }
                }
            }

            // «Mi control»: mide tu mano (la entrada), antes de procesar nada
            if generales.medidor.activo && mando.is_some() {
                if let Some((x, abajo, nombre)) = grabador.tick(&e, t, &generales.medidor, &perfil.nombre) {
                    // El análisis y el guardado, fuera del hilo del motor
                    let medidor = self.medidor.clone();
                    thread::spawn(move || {
                        let r = crate::medidor::analizar(&x, &abajo, &nombre, crate::medidor::ahora_2001());
                        medidor.lock().unwrap().anadir(r, x, abajo);
                    });
                }
            } else {
                grabador.cortar();
            }
            let s = if pausa || mando.is_none() { Estado::default() } else { procesador.procesar(&e, &perfil, t) };

            // Avisos al encender o apagar el anti-recoil y la ayuda (luz del mando)
            // (con sonido, como en la app de Mac: Glass/Bottle el anti-recoil, Ping/Funk la ayuda)
            if procesador.anti_recoil_encendido != ar_antes {
                ar_antes = procesador.anti_recoil_encendido;
                sonar(if ar_antes { Sonido::Glass } else { Sonido::Bottle });
                self.mando.destellar(if ar_antes { (0.0, 1.0, 0.0) } else { (1.0, 0.0, 0.0) });
            }
            if procesador.ayuda_encendida != ayuda_antes {
                ayuda_antes = procesador.ayuda_encendida;
                sonar(if ayuda_antes { Sonido::Ping } else { Sonido::Funk });
                self.mando.destellar(if ayuda_antes { (0.0, 1.0, 1.0) } else { (1.0, 0.5, 0.0) });
            }

            // Diagnóstico de la ayuda: 100 muestras por segundo
            if t - muestreado_en >= 0.01 {
                muestreado_en = t;
                let d = &procesador.diagnostico;
                for (cola, v) in [(&mut hist.0, d.off_x), (&mut hist.1, d.off_y), (&mut hist.2, d.amplitud)] {
                    cola.push_back(v as f32);
                    if cola.len() > 400 {
                        cola.pop_front();
                    }
                }
            }

            if esp.conectado() && (Some(s) != ultimo_enviado || t - enviado_en >= 0.05) {
                if esp.enviar(&s) {
                    ultimo_enviado = Some(s);
                    enviado_en = t;
                    envios += 1;
                }
            }
            if t - contado_en >= 1.0 {
                por_segundo = envios;
                envios = 0;
                vueltas_seg = vueltas;
                vueltas = 0;
                peor_seg = peor * 1000.0;
                peor = 0.0;
                contado_en = t;
            }
            if t - pintado_en >= 1.0 / 30.0 {
                pintado_en = t;
                let mut d = self.directo.lock().unwrap();
                d.entrada = e;
                d.salida = s;
                d.esp_ruta = esp.ruta();
                d.sincro = sincro.estado();
                d.envios_por_segundo = por_segundo;
                d.vueltas_por_segundo = vueltas_seg;
                d.peor_vuelta_ms = peor_seg;
                d.anti_recoil = procesador.anti_recoil_encendido;
                d.ayuda = procesador.ayuda_encendida;
                d.diag = procesador.diagnostico.clone();
                d.hx = hist.0.clone();
                d.hy = hist.1.clone();
                d.ha = hist.2.clone();
            }
            // Cada vuelta dura 1 ms contando el trabajo (no 1 ms de espera más el trabajo)
            let resta = 0.001 - (ahora() - t);
            if resta > 0.0 {
                thread::sleep(Duration::from_secs_f64(resta));
            }
        }
    }

    // MARK: - Lo que ve y cambia el móvil (mismo JSON que la app de Mac)

    pub fn instantanea(&self) -> String {
        let d = self.directo.lock().unwrap().clone();
        let a = self.almacen.lock().unwrap();
        let p = a.activo();
        let pausado = self.pausado();
        let info = self.mando.info();
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
        // Monitor de la señal: analiza las últimas 200 muestras (2 s), como la app de Mac
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
            "mando": info.nombre, "esp": d.esp_ruta.is_some(), "envios": d.envios_por_segundo, "sincro": d.sincro,
            "mandoRitmo": {"hz": info.hz, "huecoMs": info.hueco_ms.round() as i64, "conexion": info.conexion},
            "bateria": {"porcentaje": info.bateria, "estado": info.bateria_estado},
            "funciones": funciones,
            "bucle": {"vueltas": d.vueltas_por_segundo, "peorMs": (d.peor_vuelta_ms * 10.0).round() / 10.0},
            "pausado": pausado, "antiRecoil": d.anti_recoil, "ayuda": d.ayuda,
            "aviso": aviso.map(|(id, texto)| json!({"id": id, "texto": texto})),
            "widgets": widgets,
            "rev": a.revision(pausado),
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
            "rev": a.revision(pausado),
        }).to_string()
    }

    /// Tocar un widget (en la ventana o en el móvil). false si ya no existe.
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

    /// Un cambio que llega del móvil (o de la ventana, que es la misma página)
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
                // Desconecta los móviles (el servidor cierra los directos con la clave vieja); la página que la
                // pide se queda con la nueva
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
            _ => Some("acción desconocida".into()),
        };
        let rev = self.almacen.lock().unwrap().revision(self.pausado());
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

/// La voz del sistema, sin bloquear (Mac: say; Windows: la voz de System.Speech)
fn hablar(texto: &str) {
    let texto = texto.replace(['"', '\'', '`', '$'], "");
    thread::spawn(move || {
        #[cfg(target_os = "macos")]
        {
            let _ = std::process::Command::new("say").args(["-v", "Mónica", &texto]).status()
                .or_else(|_| std::process::Command::new("say").arg(&texto).status());
        }
        #[cfg(windows)]
        {
            use std::os::windows::process::CommandExt;
            const SIN_VENTANA: u32 = 0x0800_0000;
            let orden = format!(
                "Add-Type -AssemblyName System.Speech; $v = New-Object System.Speech.Synthesis.SpeechSynthesizer; \
                 $es = $v.GetInstalledVoices() | Where-Object {{ $_.VoiceInfo.Culture.Name -like 'es*' }} | Select-Object -First 1; \
                 if ($es) {{ $v.SelectVoice($es.VoiceInfo.Name) }}; $v.Speak('{texto}')"
            );
            let _ = std::process::Command::new("powershell").args(["-NoProfile", "-Command", &orden])
                .creation_flags(SIN_VENTANA).status();
        }
    });
}

/// El hilo del motor con la prioridad más alta para el usuario, como en la app de Mac
/// (`qualityOfService = .userInteractive`): sin ella el sistema espacia los despertares y baja de ~860 vueltas/s
fn prioridad_maxima() {
    #[cfg(target_os = "macos")]
    unsafe {
        libc::pthread_set_qos_class_self_np(libc::qos_class_t::QOS_CLASS_USER_INTERACTIVE, 0);
    }
    #[cfg(windows)]
    unsafe {
        use windows_sys::Win32::System::Threading::{GetCurrentThread, SetThreadPriority, THREAD_PRIORITY_TIME_CRITICAL};
        SetThreadPriority(GetCurrentThread(), THREAD_PRIORITY_TIME_CRITICAL);
    }
}
