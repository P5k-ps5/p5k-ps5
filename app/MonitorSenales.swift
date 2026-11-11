import Foundation

/// Monitor de solo lectura: analiza una secuencia de muestras de un stick (x, y en -1...1,
/// tomadas cada `dt` segundos) y devuelve métricas y anomalías. No modifica nada: recibe
/// copias y no tiene ningún efecto sobre la salida del mando.
///
/// Se usa con el historial real de la ayuda al apuntado (lo que suma al stick derecho,
/// una muestra cada 10 ms) y con secuencias preparadas en las pruebas.

/// Umbrales del monitor (ajustes generales, no de cada perfil)
struct LimitesMonitor: Codable, Equatable {
    var activo = false
    var maxAbs = 1.0            // valor máximo permitido en cada eje (el stick va de -1 a 1)
    var maxSalto = 0.30         // cambio máximo entre dos muestras seguidas (fracción del recorrido)
    var maxVelocidad = 25.0     // recorrido por segundo
    var maxAceleracion = 4000.0 // recorrido por segundo²
    var maxCambiosSigno = 0.6   // fracción de muestras en las que la pendiente cambia de signo (oscilación)
}

struct MonitorSenales {
    enum Gravedad: Int, Comparable, Codable {
        case ok = 0, advertencia = 1, anomalia = 2
        static func < (a: Gravedad, b: Gravedad) -> Bool { a.rawValue < b.rawValue }
        var nombre: String {
            switch self { case .ok: return "Correcta"; case .advertencia: return "Advertencia"; case .anomalia: return "Anomalía" }
        }
    }

    enum Tipo: String, Codable {
        case noNumerico, fueraDeRango, salto, velocidad, aceleracion, oscilacion
    }

    struct Evento: Equatable {
        let indice: Int          // muestra donde ocurre
        let eje: String          // "x" o "y"
        let tipo: Tipo
        let gravedad: Gravedad
        let valor: Double
        let limite: Double
        let motivo: String
    }

    struct Metricas: Equatable {
        var muestras = 0
        var maxAbs = 0.0
        var maxSalto = 0.0
        var maxVelocidad = 0.0
        var maxAceleracion = 0.0
        var cambiosSigno = 0.0   // fracción
        var noNumericos = 0
    }

    struct Informe: Equatable {
        var estado: Gravedad = .ok
        var metricas = Metricas()
        var eventos: [Evento] = []        // como mucho `maxEventos` por muestra, más los avisos de resumen
        var eventosOmitidos = 0
    }

    /// Para no crecer sin límite si la señal está muy mal
    static let maxEventos = 50

    /// Analiza las dos componentes de la señal. Gravedad:
    /// - anomalía: valor no numérico, fuera de rango o salto mayor que el permitido (la señal no es válida)
    /// - advertencia: velocidad, aceleración u oscilación por encima de lo configurado (válida, pero llamativa)
    static func analizar(x: [Float], y: [Float], dt: Double, limites l: LimitesMonitor) -> Informe {
        var inf = Informe()
        let n = min(x.count, y.count)
        inf.metricas.muestras = n
        guard n > 0, dt > 0 else { return inf }

        func anotar(_ i: Int, _ eje: String, _ tipo: Tipo, _ g: Gravedad, _ v: Double, _ lim: Double, _ motivo: String) {
            if g > inf.estado { inf.estado = g }
            if inf.eventos.count < maxEventos {
                inf.eventos.append(Evento(indice: i, eje: eje, tipo: tipo, gravedad: g, valor: v, limite: lim, motivo: motivo))
            } else {
                inf.eventosOmitidos += 1
            }
        }

        var cambiosSigno = 0, pendientes = 0
        for (eje, s) in [("x", x), ("y", y)] {
            var anterior: Double?, velAnterior: Double?, signoAnterior = 0
            for i in 0..<n {
                let v = Double(s[i])
                guard v.isFinite else {
                    inf.metricas.noNumericos += 1
                    anotar(i, eje, .noNumerico, .anomalia, v, l.maxAbs, "valor no numérico")
                    anterior = nil; velAnterior = nil
                    continue
                }
                inf.metricas.maxAbs = max(inf.metricas.maxAbs, abs(v))
                if abs(v) > l.maxAbs {
                    anotar(i, eje, .fueraDeRango, .anomalia, v, l.maxAbs, "fuera del rango del stick")
                }
                if let a = anterior {
                    let salto = abs(v - a)
                    inf.metricas.maxSalto = max(inf.metricas.maxSalto, salto)
                    if salto > l.maxSalto {
                        anotar(i, eje, .salto, .anomalia, salto, l.maxSalto, "salto entre dos muestras seguidas")
                    }
                    let vel = (v - a) / dt
                    inf.metricas.maxVelocidad = max(inf.metricas.maxVelocidad, abs(vel))
                    if abs(vel) > l.maxVelocidad {
                        anotar(i, eje, .velocidad, .advertencia, abs(vel), l.maxVelocidad, "velocidad por encima de la configurada")
                    }
                    if let va = velAnterior {
                        let acel = abs(vel - va) / dt
                        inf.metricas.maxAceleracion = max(inf.metricas.maxAceleracion, acel)
                        if acel > l.maxAceleracion {
                            anotar(i, eje, .aceleracion, .advertencia, acel, l.maxAceleracion, "aceleración por encima de la configurada")
                        }
                    }
                    // Oscilación: cuántas veces cambia de sentido (se ignoran cambios diminutos)
                    let signo = abs(v - a) < 1e-4 ? 0 : (v > a ? 1 : -1)
                    if signo != 0 {
                        pendientes += 1
                        if signoAnterior != 0 && signo != signoAnterior { cambiosSigno += 1 }
                        signoAnterior = signo
                    }
                    velAnterior = vel
                }
                anterior = v
            }
        }
        if pendientes > 10 {
            let f = Double(cambiosSigno) / Double(pendientes)
            inf.metricas.cambiosSigno = f
            if f > l.maxCambiosSigno {
                // Es un resumen de toda la secuencia: se guarda siempre, aunque ya haya 50 eventos
                if .advertencia > inf.estado { inf.estado = .advertencia }
                inf.eventos.append(Evento(indice: n - 1, eje: "x+y", tipo: .oscilacion, gravedad: .advertencia,
                                          valor: f, limite: l.maxCambiosSigno, motivo: "cambia de sentido casi en cada muestra"))
            }
        }
        return inf
    }
}
