import Foundation

// Los mismos ajustes en la placa y en esta app. La placa guarda los «buenos» (se pueden cambiar desde el móvil
// en cualquier sitio); al conectarla por el cable, la app los recoge, y lo que se cambie aquí se le manda.
// Va por el mismo puerto serie que las tramas del mando, en líneas de texto cortas (protocolo en main/sincro.c
// del firmware). Es lo mismo que hace la app de escritorio (escritorio/src-tauri/src/sincro.rs).
//
// Cuándo gana cada uno:
// - La primera vez: si esta app tiene los ajustes de fábrica, se quedan los de la placa; si no, se suben los
//   de la app (los de la placa se guardan antes en una copia).
// - Después: si solo ha cambiado uno, se copia al otro. Si han cambiado los dos, gana la placa y los de esta
//   app se guardan en una copia (perfiles.copia-conflicto-FECHA.json).

/// Lo que hace falta para hablar con la placa (la de verdad está en Motor.swift; en las pruebas, una falsa)
protocol Canal: AnyObject {
    var conectado: Bool { get }
    @discardableResult func linea(_ l: String) -> Bool
    func respuestas() -> [String]
}

final class Sincro {
    enum Fase { case desconectada, preguntando, bajando, subiendo, alDia, sinSoporte }

    static let trozo = 150
    static let calmaParaSubir = 1.0     // los cambios se suben cuando llevan 1 s quietos
    static let comprobarCada = 3.0      // cada cuánto se mira si han cambiado en la placa (desde el móvil)
    static let esperaRespuesta = 0.5

    /// Lo que se guarda entre arranques (sincro.json, al lado de perfiles.json; el mismo que la app de escritorio)
    struct Guardado: Codable {
        /// La revisión de la placa la última vez que quedaron iguales ("" = nunca)
        var ultimaRev = ""
        /// Hay cambios en esta app que la placa todavía no tiene
        var cambiosLocales = false

        init() {}
        init(from d: Decoder) throws {
            let c = try d.container(keyedBy: CodingKeys.self)
            ultimaRev = try c.decodeIfPresent(String.self, forKey: .ultimaRev) ?? ""
            cambiosLocales = try c.decodeIfPresent(Bool.self, forKey: .cambiosLocales) ?? false
        }
    }

    private(set) var fase: Fase = .desconectada
    private(set) var g = Guardado()
    private let archivo: URL
    private let perfiles: URL
    /// La versión del almacén que ya tiene la placa (o que vino de ella)
    var versionVista: Int
    private var ultimoCambio = 0.0

    // Preguntando
    private var enviado = -Double.infinity
    private var intentos = 0
    // Bajando
    private var revBajada = ""
    private var largo = 0
    private var crc: UInt32 = 0
    private var datos = Data()
    private var pedido = -Double.infinity
    private var primeraVez = false
    // Subiendo (paso 0: «poner», 1: trozos, 2: «fin»)
    private var subida = Data()
    private var versionSubida = 0
    private var paso = 0
    private var enviadoBytes = 0
    // Al día
    private var comprobado = 0.0

    init(archivoPerfiles: URL, versionInicial: Int) {
        archivo = archivoPerfiles.deletingLastPathComponent().appendingPathComponent("sincro.json")
        perfiles = archivoPerfiles
        versionVista = versionInicial
        if let d = try? Data(contentsOf: archivo), let leido = try? JSONDecoder().decode(Guardado.self, from: d) {
            g = leido
        }
    }

    /// Para enseñarlo en la app
    var estado: String {
        switch fase {
        case .desconectada: return "sin placa"
        case .preguntando, .alDia: return g.cambiosLocales ? "pendiente" : "al día"
        case .bajando: return "recibiendo"
        case .subiendo: return "enviando"
        case .sinSoporte: return "firmware antiguo"
        }
    }

    private func guardar() {
        let cod = JSONEncoder()
        cod.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let d = try? cod.encode(g) { try? d.write(to: archivo, options: .atomic) }
    }

    private func copia(_ motivo: String, _ d: Data) -> String {
        let nombre = "perfiles.copia-\(motivo)-\(Sincro.fechaHoy()).json"
        try? d.write(to: perfiles.deletingLastPathComponent().appendingPathComponent(nombre), options: .atomic)
        return nombre
    }

    private func preguntar(enviado e: Double = -.infinity) {
        fase = .preguntando
        enviado = e
        intentos = 0
    }

    /// Una vuelta (se llama a menudo, desde el hilo principal). Devuelve un aviso para el usuario, si hay.
    func vuelta(_ c: Canal, _ almacen: Almacen, t: Double) -> String? {
        guard c.conectado else {
            fase = .desconectada
            return nil
        }
        if fase == .desconectada { preguntar() }
        if fase == .sinSoporte { return nil }

        // Cambios hechos en esta app (no los que vienen de la placa: esos ponen versionVista al aplicarse)
        if fase != .bajando, almacen.version != versionVista {
            versionVista = almacen.version
            ultimoCambio = t
            if !g.cambiosLocales {
                g.cambiosLocales = true
                guardar()
            }
        }

        var aviso: String?
        for r in c.respuestas() {
            if let a = respuesta(r, almacen, t: t) { aviso = a }
        }

        // Lo que toca mandar ahora en cada fase
        switch fase {
        case .preguntando:
            if t - enviado > 1 {
                if intentos >= 5 {
                    fase = .sinSoporte
                } else {
                    enviado = t
                    intentos += 1
                    c.linea("ajustes rev")
                }
            }
        case .bajando:
            if datos.count < largo && t - pedido > Sincro.esperaRespuesta {
                pedido = t
                c.linea("ajustes leer \(datos.count)")
            }
        case .subiendo:
            let espera = paso == 2 ? 3.0 : Sincro.esperaRespuesta
            if t - pedido > espera {
                switch paso {
                case 0:
                    pedido = t
                    c.linea("ajustes poner \(subida.count) \(Sincro.hex8(Sincro.crc32(subida)))")
                case 1:
                    pedido = t
                    let fin = min(enviadoBytes + Sincro.trozo, subida.count)
                    let b64 = subida.subdata(in: enviadoBytes..<fin).base64EncodedString()
                    c.linea("ajustes trozo \(enviadoBytes) \(b64)")
                default:
                    // «fin» se manda una sola vez: si no contesta, se vuelve a preguntar la revisión
                    if pedido == -.infinity {
                        pedido = t
                        c.linea("ajustes fin")
                    } else {
                        preguntar()
                    }
                }
            }
        case .alDia:
            if g.cambiosLocales && t - ultimoCambio > Sincro.calmaParaSubir {
                subir(almacen)
            } else if t - comprobado > Sincro.comprobarCada {
                preguntar()
            }
        default:
            break
        }
        return aviso
    }

    private func subir(_ almacen: Almacen) {
        subida = almacen.ajustesSincronizados()
        versionSubida = almacen.version
        paso = 0
        enviadoBytes = 0
        pedido = -.infinity
        fase = .subiendo
    }

    private func alDia(_ t: Double) {
        fase = .alDia
        comprobado = t
    }

    private func bajar(rev: String, largo l: Int, crc c: UInt32, primeraVez p: Bool) {
        revBajada = rev
        largo = l
        crc = c
        datos = Data()
        pedido = -.infinity
        primeraVez = p
        fase = .bajando
    }

    private func respuesta(_ r: String, _ almacen: Almacen, t: Double) -> String? {
        let p = r.split(separator: " ").map(String.init)
        guard p.count >= 2 else { return nil }
        switch (fase, p[1]) {
        case (.preguntando, "REV") where p.count >= 5:
            let rev = p[2], l = Int(p[3]) ?? 0, c = UInt32(p[4], radix: 16) ?? 0
            if g.ultimaRev.isEmpty {
                bajar(rev: rev, largo: l, crc: c, primeraVez: true)
            } else if rev == g.ultimaRev {
                if g.cambiosLocales { subir(almacen) } else { alDia(t) }
            } else if !g.cambiosLocales {
                bajar(rev: rev, largo: l, crc: c, primeraVez: false)
            } else {
                // Cambiados en los dos sitios: gana la placa; los de aquí, a una copia
                let nombre = copia("conflicto", almacen.ajustesSincronizados())
                bajar(rev: rev, largo: l, crc: c, primeraVez: false)
                return "Habías cambiado ajustes aquí y en la placa: me quedo con los de la placa (los de aquí, en \(nombre))"
            }
            return nil
        case (.bajando, "T") where p.count >= 4:
            if Int(p[2]) == datos.count, let d = Data(base64Encoded: p[3]) {
                datos.append(d)
                pedido = -.infinity             // el siguiente trozo, ya
            }
            return quizaTerminarBajada(almacen, t: t)
        case (.subiendo, "LISTO") where paso == 0:
            paso = 1
            pedido = -.infinity
            return nil
        case (.subiendo, "ACK") where paso == 1 && p.count >= 3:
            if let n = Int(p[2]) {
                enviadoBytes = n
                pedido = -.infinity
                if n >= subida.count { paso = 2 }
            }
            return nil
        case (.subiendo, "OK") where p.count >= 3:
            g.ultimaRev = p[2]
            if almacen.version == versionSubida { g.cambiosLocales = false }
            guardar()
            alDia(t)
            return nil
        case (.subiendo, "ERROR"):
            preguntar(enviado: t + 1)
            return nil
        default:
            return nil
        }
    }

    private func quizaTerminarBajada(_ almacen: Almacen, t: Double) -> String? {
        guard fase == .bajando, datos.count >= largo else { return nil }
        if datos.count != largo || Sincro.crc32(datos) != crc {
            preguntar()                         // ha llegado mal: otra vez
            return nil
        }
        if primeraVez && !Sincro.deFabrica(almacen.perfiles) {
            // Primera vez y esta app ya tiene ajustes: se suben (los de la placa, a una copia)
            let nombre = copia("de-la-placa", datos)
            subir(almacen)
            return "Primera vez con esta placa: le paso los ajustes de aquí (los que tenía, en \(nombre))"
        }
        if let e = almacen.ponerAjustesSincronizados(datos) {
            fase = .sinSoporte
            return "Los ajustes de la placa no se pueden leer: \(e)"
        }
        versionVista = almacen.version
        g.ultimaRev = revBajada
        g.cambiosLocales = false
        guardar()
        alDia(t)
        return "Ajustes recogidos de la placa"
    }

    /// ¿Son los ajustes con los que arranca la app la primera vez? (un perfil «Normal» sin tocar)
    static func deFabrica(_ perfiles: [Perfil]) -> Bool {
        guard perfiles.count == 1, let p = perfiles.first else { return false }
        var nuevo = Perfil(nombre: "Normal")
        nuevo.id = p.id
        let cod = JSONEncoder()
        cod.outputFormatting = .sortedKeys
        return (try? cod.encode(nuevo)) == (try? cod.encode(p))
    }

    /// CRC-32 normal (el de zlib), como el firmware y la app de escritorio
    static func crc32(_ d: Data) -> UInt32 {
        var c: UInt32 = 0xFFFF_FFFF
        for b in d {
            c ^= UInt32(b)
            for _ in 0..<8 { c = (c & 1) != 0 ? (c >> 1) ^ 0xEDB8_8320 : c >> 1 }
        }
        return ~c
    }

    static func hex8(_ v: UInt32) -> String {
        let s = String(v, radix: 16)
        return String(repeating: "0", count: max(0, 8 - s.count)) + s
    }

    /// AAAA-MM-DD de hoy (UTC), para el nombre de las copias
    static func fechaHoy() -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: Date())
    }
}
