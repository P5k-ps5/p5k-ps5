import Foundation

/// Medidor de tu propio control: graba lo que hace tu mano con el stick derecho mientras
/// disparas (la entrada del DualSense, antes de que la app aplique nada) y te enseña cómo lo
/// haces ráfaga a ráfaga, para practicar y ver si mejoras. Solo mide: no genera ninguna
/// configuración ni compensa nada, y no toca lo que se manda a la consola.

/// Qué cuenta como ráfaga (ajustes generales: es tu mano, no un perfil)
struct ConfigMedidor: Codable, Equatable {
    var activo = false
    var disparar: Boton = .r2        // botón de tu mando con el que disparas
    var apuntar: Boton = .l2         // y con el que apuntas
    var soloApuntando = false        // contar solo las ráfagas en las que también apuntas
}

/// Lo que hiciste en una ráfaga. Valores en % del recorrido del stick.
struct ResumenRafaga: Codable, Equatable, Identifiable {
    var id = UUID()
    var fecha = Date()
    var perfil = ""
    var duracionMs = 0.0
    var reaccionMs: Double?          // cuánto tardaste en empezar a bajar el stick (nil = no bajaste)
    var bajadaMedia = 0.0            // cuánto bajaste de media (positivo = hacia abajo)
    var constancia = 0.0             // cuánto varió esa bajada (desviación típica; menos = más constante)
    var lateralMedio = 0.0           // desvío lateral medio (positivo = derecha)
    var lateralMax = 0.0             // mayor desvío lateral (valor absoluto)
    var temblor = 0.0                // movimiento brusco de muestra a muestra (menos = más suave)
    var tirones = 0                  // cambios de más de un 15 % en 10 ms
    var muestras = 0
}

enum AnalisisRafaga {
    static let dt = 0.01                 // una muestra cada 10 ms
    static let umbralReaccion = 0.10     // a partir de un 10 % de bajada cuenta como «empezar a corregir»
    static let umbralTiron = 0.15

    /// x: lateral (-1 izquierda ... 1 derecha); abajo: vertical (-1 arriba ... 1 abajo)
    static func analizar(x: [Float], abajo: [Float], perfil: String = "", fecha: Date = Date()) -> ResumenRafaga {
        var r = ResumenRafaga()
        r.fecha = fecha
        r.perfil = perfil
        let n = min(x.count, abajo.count)
        r.muestras = n
        r.duracionMs = Double(n) * dt * 1000
        guard n > 0 else { return r }

        let inicio = (0..<n).first { Double(abajo[$0]) > umbralReaccion }
        r.reaccionMs = inicio.map { Double($0) * dt * 1000 }
        let desde = inicio ?? 0

        var suma = 0.0, suma2 = 0.0, lat = 0.0
        for i in desde..<n {
            let v = Double(abajo[i]); suma += v; suma2 += v * v
            lat += Double(x[i])
        }
        let m = Double(n - desde)
        let media = suma / m
        r.bajadaMedia = media * 100
        r.constancia = (max(suma2 / m - media * media, 0)).squareRoot() * 100
        r.lateralMedio = lat / m * 100
        r.lateralMax = (0..<n).map { abs(Double(x[$0])) }.max()! * 100

        var temblor = 0.0, cuenta = 0
        for i in 1..<max(n, 1) {
            let dx = Double(x[i] - x[i - 1]), dy = Double(abajo[i] - abajo[i - 1])
            if max(abs(dx), abs(dy)) > umbralTiron { r.tirones += 1 }
            if i >= 2 {
                temblor += abs(Double(x[i] - 2 * x[i - 1] + x[i - 2])) + abs(Double(abajo[i] - 2 * abajo[i - 1] + abajo[i - 2]))
                cuenta += 1
            }
        }
        r.temblor = cuenta > 0 ? temblor / Double(cuenta) * 100 : 0
        return r
    }

    /// Observaciones orientativas sobre un grupo de ráfagas (los umbrales son aproximados, no una norma)
    static func observaciones(_ rs: [ResumenRafaga]) -> [String] {
        guard !rs.isEmpty else { return [] }
        let m = media(rs)
        var o: [String] = []
        if let rea = m.reaccionMs, rea > 200 { o.append("Tardas de media \(Int(rea)) ms en empezar a bajar el stick.") }
        if m.sinCorregir > 0.3 { o.append("En \(Int(m.sinCorregir * 100)) % de las ráfagas no llegaste a bajar el stick.") }
        if abs(m.lateralMedio) > 3 { o.append("Tiendes a irte hacia la \(m.lateralMedio > 0 ? "derecha" : "izquierda") (\(String(format: "%.1f", abs(m.lateralMedio))) % de media).") }
        if m.constancia > 8 { o.append("Tu bajada varía bastante dentro de cada ráfaga (\(String(format: "%.1f", m.constancia)) %).") }
        if m.tirones > 1 { o.append("Haces correcciones a tirones (\(String(format: "%.1f", m.tirones)) por ráfaga).") }
        if o.isEmpty { o.append("Sin nada llamativo en estas ráfagas.") }
        return o
    }

    struct Media { var rafagas = 0; var reaccionMs: Double?; var sinCorregir = 0.0; var bajada = 0.0; var constancia = 0.0
                   var lateralMedio = 0.0; var lateralAbs = 0.0; var temblor = 0.0; var tirones = 0.0 }

    static func media(_ rs: [ResumenRafaga]) -> Media {
        var m = Media()
        m.rafagas = rs.count
        guard !rs.isEmpty else { return m }
        let n = Double(rs.count)
        let conReaccion = rs.compactMap(\.reaccionMs)
        m.reaccionMs = conReaccion.isEmpty ? nil : conReaccion.reduce(0, +) / Double(conReaccion.count)
        m.sinCorregir = Double(rs.count - conReaccion.count) / n
        m.bajada = rs.map(\.bajadaMedia).reduce(0, +) / n
        m.constancia = rs.map(\.constancia).reduce(0, +) / n
        m.lateralMedio = rs.map(\.lateralMedio).reduce(0, +) / n
        m.lateralAbs = rs.map { abs($0.lateralMedio) }.reduce(0, +) / n
        m.temblor = rs.map(\.temblor).reduce(0, +) / n
        m.tirones = Double(rs.map(\.tirones).reduce(0, +)) / n
        return m
    }
}

/// Graba las ráfagas desde el hilo del motor. Sin reservar memoria en cada tick: usa dos
/// búferes fijos y solo copia la ráfaga una vez, cuando termina.
final class GrabadorRafagas {
    static let capacidad = 3000                       // 30 s a una muestra cada 10 ms
    static let duracionMinima = 0.15                  // ráfagas más cortas no se cuentan
    private var x = [Float](repeating: 0, count: capacidad)
    private var abajo = [Float](repeating: 0, count: capacidad)
    private var n = 0
    private var enRafaga = false
    private var inicio = 0.0, muestreadoEn = 0.0
    /// Se llama (en el hilo del motor) con la ráfaga terminada
    var alTerminar: (([Float], [Float], String) -> Void)?

    func tick(_ e: Estado, t: Double, config c: ConfigMedidor, perfil: String) {
        let dispara = GrabadorRafagas.pulsado(e, c.disparar)
        let pulsado = dispara && (!c.soloApuntando || GrabadorRafagas.pulsado(e, c.apuntar))
        if pulsado {
            if !enRafaga { enRafaga = true; n = 0; inicio = t; muestreadoEn = t - 1 }
            if t - muestreadoEn >= AnalisisRafaga.dt - 1e-9 && n < GrabadorRafagas.capacidad {
                muestreadoEn = t
                x[n] = Float((Double(e.rx) - 127.5) / 127.5)
                abajo[n] = Float((Double(e.ry) - 127.5) / 127.5)
                n += 1
            }
        } else if enRafaga {
            enRafaga = false
            if t - inicio >= GrabadorRafagas.duracionMinima && n >= 10 {
                alTerminar?(Array(x[0..<n]), Array(abajo[0..<n]), perfil)
            }
        }
    }

    /// Descarta la ráfaga en curso (por ejemplo, al apagar el medidor o perder el mando)
    func cortar() { enRafaga = false; n = 0 }

    static func pulsado(_ e: Estado, _ b: Boton) -> Bool {
        switch b {
        case .l2: return e.l2 > 25
        case .r2: return e.r2 > 25
        default: return e.pulsado(b)
        }
    }
}

/// Historial de ráfagas, guardado en ~/Library/Application Support/Puente de mando/medidor.json
final class MedidorControl: ObservableObject {
    static let maxGuardadas = 1000
    @Published private(set) var rafagas: [ResumenRafaga] = []
    /// La última ráfaga entera, para dibujarla (no se guarda en disco)
    @Published private(set) var ultimaX: [Float] = []
    @Published private(set) var ultimaAbajo: [Float] = []

    private let archivo: URL
    private let cola = DispatchQueue(label: "medidor", qos: .utility)
    private var guardado: DispatchWorkItem?

    init(archivo: URL? = nil) {
        if let archivo { self.archivo = archivo } else {
            let carpeta = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("Puente de mando", isDirectory: true)
            try? FileManager.default.createDirectory(at: carpeta, withIntermediateDirectories: true)
            self.archivo = carpeta.appendingPathComponent("medidor.json")
        }
        let dec = JSONDecoder()   // fechas con toda su precisión (segundos con decimales)
        if let datos = try? Data(contentsOf: self.archivo), let r = try? dec.decode([ResumenRafaga].self, from: datos) {
            rafagas = r
        }
    }

    /// Desde cualquier hilo: analiza fuera del motor y del hilo principal, y luego lo añade
    func registrar(x: [Float], abajo: [Float], perfil: String) {
        cola.async { [weak self] in
            let r = AnalisisRafaga.analizar(x: x, abajo: abajo, perfil: perfil)
            DispatchQueue.main.async { self?.anadir(r, x: x, abajo: abajo) }
        }
    }

    func anadir(_ r: ResumenRafaga, x: [Float] = [], abajo: [Float] = []) {
        rafagas.append(r)
        if rafagas.count > MedidorControl.maxGuardadas { rafagas.removeFirst(rafagas.count - MedidorControl.maxGuardadas) }
        if !x.isEmpty { ultimaX = x; ultimaAbajo = abajo }
        guardar()
    }

    func borrarTodo() {
        rafagas = []; ultimaX = []; ultimaAbajo = []
        guardar()
    }

    /// Media de cada día (el más reciente primero)
    var porDia: [(dia: Date, media: AnalisisRafaga.Media)] {
        let cal = Calendar.current
        let grupos = Dictionary(grouping: rafagas) { cal.startOfDay(for: $0.fecha) }
        return grupos.keys.sorted(by: >).map { ($0, AnalisisRafaga.media(grupos[$0]!)) }
    }

    private func guardar() {
        guardado?.cancel()
        let datos = rafagas, destino = archivo
        let tarea = DispatchWorkItem { MedidorControl.escribir(datos, destino) }
        guardado = tarea
        cola.asyncAfter(deadline: .now() + 0.5, execute: tarea)
    }

    /// Guarda ya (al cerrar la app y en las pruebas)
    func guardarAhora() {
        guardado?.cancel()
        MedidorControl.escribir(rafagas, archivo)
    }

    private static func escribir(_ r: [ResumenRafaga], _ destino: URL) {
        let enc = JSONEncoder(); enc.outputFormatting = [.sortedKeys]
        if let datos = try? enc.encode(r) { try? datos.write(to: destino, options: .atomic) }
    }
}
