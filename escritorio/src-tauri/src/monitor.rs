// Monitor de solo lectura (port de app/MonitorSenales.swift): analiza una secuencia de muestras de un stick
// (x, y en -1...1, tomadas cada `dt` segundos) y devuelve métricas y anomalías. No modifica nada: recibe
// copias y no tiene ningún efecto sobre la salida del mando. Se usa con el historial real de la ayuda al
// apuntado (lo que suma al stick derecho, una muestra cada 10 ms).
use crate::modelo::LimitesMonitor;

#[derive(Clone, Copy, Debug, PartialEq, Eq, PartialOrd, Ord)]
pub enum Gravedad {
    Ok = 0,
    Advertencia = 1,
    Anomalia = 2,
}

impl Gravedad {
    pub fn nombre(self) -> &'static str {
        match self {
            Gravedad::Ok => "Correcta",
            Gravedad::Advertencia => "Advertencia",
            Gravedad::Anomalia => "Anomalía",
        }
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Tipo {
    NoNumerico,
    FueraDeRango,
    Salto,
    Velocidad,
    Aceleracion,
    Oscilacion,
}

#[derive(Clone, Debug, PartialEq)]
pub struct Evento {
    pub indice: usize,
    pub eje: &'static str,
    pub tipo: Tipo,
    pub gravedad: Gravedad,
    pub valor: f64,
    pub limite: f64,
    pub motivo: &'static str,
}

#[derive(Clone, Debug, Default, PartialEq)]
pub struct Metricas {
    pub muestras: usize,
    pub max_abs: f64,
    pub max_salto: f64,
    pub max_velocidad: f64,
    pub max_aceleracion: f64,
    pub cambios_signo: f64,
    pub no_numericos: usize,
}

#[derive(Clone, Debug, PartialEq)]
pub struct Informe {
    pub estado: Gravedad,
    pub metricas: Metricas,
    pub eventos: Vec<Evento>,
    pub eventos_omitidos: usize,
}

/// Para no crecer sin límite si la señal está muy mal
pub const MAX_EVENTOS: usize = 50;

/// Gravedad: anomalía (no numérico, fuera de rango o salto mayor que el permitido) o advertencia
/// (velocidad, aceleración u oscilación por encima de lo configurado)
pub fn analizar(x: &[f32], y: &[f32], dt: f64, l: &LimitesMonitor) -> Informe {
    let mut inf = Informe { estado: Gravedad::Ok, metricas: Metricas::default(), eventos: vec![], eventos_omitidos: 0 };
    let n = x.len().min(y.len());
    inf.metricas.muestras = n;
    if n == 0 || dt <= 0.0 {
        return inf;
    }
    let anotar = |inf: &mut Informe, i: usize, eje: &'static str, tipo: Tipo, g: Gravedad, v: f64, lim: f64, motivo: &'static str| {
        if g > inf.estado {
            inf.estado = g;
        }
        if inf.eventos.len() < MAX_EVENTOS {
            inf.eventos.push(Evento { indice: i, eje, tipo, gravedad: g, valor: v, limite: lim, motivo });
        } else {
            inf.eventos_omitidos += 1;
        }
    };

    let (mut cambios_signo, mut pendientes) = (0usize, 0usize);
    for (eje, s) in [("x", x), ("y", y)] {
        let (mut anterior, mut vel_anterior): (Option<f64>, Option<f64>) = (None, None);
        let mut signo_anterior = 0i32;
        for i in 0..n {
            let v = s[i] as f64;
            if !v.is_finite() {
                inf.metricas.no_numericos += 1;
                anotar(&mut inf, i, eje, Tipo::NoNumerico, Gravedad::Anomalia, v, l.max_abs, "valor no numérico");
                anterior = None;
                vel_anterior = None;
                continue;
            }
            inf.metricas.max_abs = swift_max(inf.metricas.max_abs, v.abs());
            if v.abs() > l.max_abs {
                anotar(&mut inf, i, eje, Tipo::FueraDeRango, Gravedad::Anomalia, v, l.max_abs, "fuera del rango del stick");
            }
            if let Some(a) = anterior {
                let salto = (v - a).abs();
                inf.metricas.max_salto = swift_max(inf.metricas.max_salto, salto);
                if salto > l.max_salto {
                    anotar(&mut inf, i, eje, Tipo::Salto, Gravedad::Anomalia, salto, l.max_salto, "salto entre dos muestras seguidas");
                }
                let vel = (v - a) / dt;
                inf.metricas.max_velocidad = swift_max(inf.metricas.max_velocidad, vel.abs());
                if vel.abs() > l.max_velocidad {
                    anotar(&mut inf, i, eje, Tipo::Velocidad, Gravedad::Advertencia, vel.abs(), l.max_velocidad,
                           "velocidad por encima de la configurada");
                }
                if let Some(va) = vel_anterior {
                    let acel = (vel - va).abs() / dt;
                    inf.metricas.max_aceleracion = swift_max(inf.metricas.max_aceleracion, acel);
                    if acel > l.max_aceleracion {
                        anotar(&mut inf, i, eje, Tipo::Aceleracion, Gravedad::Advertencia, acel, l.max_aceleracion,
                               "aceleración por encima de la configurada");
                    }
                }
                // Oscilación: cuántas veces cambia de sentido (se ignoran cambios diminutos)
                let signo = if (v - a).abs() < 1e-4 { 0 } else if v > a { 1 } else { -1 };
                if signo != 0 {
                    pendientes += 1;
                    if signo_anterior != 0 && signo != signo_anterior {
                        cambios_signo += 1;
                    }
                    signo_anterior = signo;
                }
                vel_anterior = Some(vel);
            }
            anterior = Some(v);
        }
    }
    if pendientes > 10 {
        let f = cambios_signo as f64 / pendientes as f64;
        inf.metricas.cambios_signo = f;
        if f > l.max_cambios_signo {
            // Es un resumen de toda la secuencia: se guarda siempre, aunque ya haya 50 eventos
            if Gravedad::Advertencia > inf.estado {
                inf.estado = Gravedad::Advertencia;
            }
            inf.eventos.push(Evento {
                indice: n - 1, eje: "x+y", tipo: Tipo::Oscilacion, gravedad: Gravedad::Advertencia, valor: f,
                limite: l.max_cambios_signo, motivo: "cambia de sentido casi en cada muestra",
            });
        }
    }
    inf
}

/// max de Swift: si el segundo no es comparable (NaN) se queda el primero; igual que el `max` de la app de Mac
fn swift_max(a: f64, b: f64) -> f64 {
    if b > a { b } else { a }
}

#[cfg(test)]
mod pruebas {
    use super::*;
    use crate::modelo::{Boton, Estado, Perfil, PATRONES};
    use crate::procesador::Procesador;

    fn perfil_base_ayuda(patron: usize) -> Perfil {
        // Igual que perfilBaseAyuda de pruebas/Escenario.swift: ayuda con L1 y el patrón elegido
        let mut p = Perfil::default();
        p.anti_recoil.activo = false;
        p.ayuda.activo = true;
        p.ayuda.boton = Boton::L1;
        p.ayuda.aplicar_patron(patron);
        p
    }

    fn senal_real(p: &Perfil, segundos: f64) -> (Vec<f32>, Vec<f32>) {
        let mut pr = Procesador::new();
        let (mut x, mut y) = (vec![], vec![]);
        for k in 0..(segundos * 1000.0) as usize {
            let e = Estado { botones: Boton::L1.bit(), ..Default::default() };
            pr.procesar(&e, p, k as f64 / 1000.0);
            if k % 10 == 0 {
                x.push(pr.diagnostico.off_x as f32);
                y.push(pr.diagnostico.off_y as f32);
            }
        }
        (x, y)
    }

    #[test]
    fn monitor_como_en_mac() {
        let lm = LimitesMonitor::default();
        for i in 0..PATRONES.len() {
            let (x, y) = senal_real(&perfil_base_ayuda(i), 3.0);
            let inf = analizar(&x, &y, 0.01, &lm);
            assert!(inf.estado == Gravedad::Ok && inf.eventos.is_empty(), "{}: señal real correcta", PATRONES[i].nombre);
        }
        let lx: Vec<f32> = (0..300).map(|k| (0.1 * (2.0 * std::f64::consts::PI * 2.0 * k as f64 * 0.01).sin()) as f32).collect();
        let ly = vec![0f32; 300];
        assert_eq!(analizar(&lx, &ly, 0.01, &lm).estado, Gravedad::Ok, "un seno lento y suave da «Correcta»");
        let con = |cambio: &dyn Fn(&mut Vec<f32>)| {
            let mut s = lx.clone();
            cambio(&mut s);
            analizar(&s, &ly, 0.01, &lm)
        };
        let inf = con(&|s| s[100] = f32::NAN);
        assert!(inf.estado == Gravedad::Anomalia && inf.eventos.iter().any(|e| e.tipo == Tipo::NoNumerico && e.indice == 100) && inf.metricas.no_numericos == 1);
        let inf = con(&|s| s[50] = 1.5);
        assert!(inf.estado == Gravedad::Anomalia && inf.eventos.iter().any(|e| e.tipo == Tipo::FueraDeRango && e.indice == 50));
        let inf = con(&|s| for k in 150..300 { s[k] += 0.5 });
        assert!(inf.estado == Gravedad::Anomalia && inf.eventos.iter().any(|e| e.tipo == Tipo::Salto && e.indice == 150));
        let rapido_x: Vec<f32> = (0..300).map(|k| (0.9 * (2.0 * std::f64::consts::PI * 8.0 * k as f64 * 0.01).sin()) as f32).collect();
        let rapido = analizar(&rapido_x, &ly, 0.01, &lm);
        assert!(rapido.estado >= Gravedad::Advertencia && rapido.eventos.iter().any(|e| e.tipo == Tipo::Velocidad)
            && !rapido.eventos.iter().any(|e| e.tipo == Tipo::FueraDeRango));
        let alterna: Vec<f32> = (0..300).map(|k| if k % 2 == 0 { 0.2 } else { -0.2 }).collect();
        let rapido = analizar(&alterna, &ly, 0.01, &lm);
        assert!(rapido.eventos.iter().any(|e| e.tipo == Tipo::Oscilacion) && rapido.eventos.iter().any(|e| e.tipo == Tipo::Aceleracion));
        let mut l2 = lm.clone();
        l2.max_salto = 1.0;
        assert_eq!(analizar(&alterna, &ly, 0.01, &l2).estado, Gravedad::Advertencia, "con salto permitido es advertencia");
        let muchos = analizar(&vec![3f32; 1000], &vec![3f32; 1000], 0.01, &lm);
        assert!(muchos.eventos.iter().filter(|e| e.tipo != Tipo::Oscilacion).count() == MAX_EVENTOS && muchos.eventos_omitidos == 2000 - MAX_EVENTOS);
        let vacio = analizar(&[], &[], 0.01, &lm);
        assert!(vacio.estado == Gravedad::Ok && vacio.metricas.muestras == 0);
        assert_eq!(analizar(&lx, &ly, 0.01, &lm), analizar(&lx, &ly, 0.01, &lm), "siempre el mismo informe");
        // Un millón de muestras por eje, con las métricas esperadas
        let grande: Vec<f32> = (0..1_000_000).map(|k| (0.1 * (k as f64 * 0.05).sin()) as f32).collect();
        let inicio = std::time::Instant::now();
        let g = analizar(&grande, &grande, 0.01, &lm);
        let esperada = 0.1 * 0.05 / 0.01;
        assert!((g.metricas.max_velocidad - esperada).abs() < 0.01 && (g.metricas.max_abs - 0.1).abs() < 1e-4);
        assert!(g.metricas.muestras == 1_000_000 && inicio.elapsed().as_millis() < 3000, "rápido");
    }
}
