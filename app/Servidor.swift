import AppKit
import CoreImage.CIFilterBuiltins
import Foundation
import Network

/// Servidor web pequeño, solo para la red de casa. Enseña en el móvil lo mismo que la app
/// (mando, perfil, estado) y deja cambiar los mismos ajustes. Todo lleva una clave: sin ella
/// no se mira ni se cambia nada. La página se refresca sola por «eventos del servidor».
final class Servidor: ObservableObject {
    @Published private(set) var activo = false
    @Published private(set) var puerto: UInt16 = 0
    @Published private(set) var clientes = 0
    @Published private(set) var error: String?

    /// Qué devolver en /perfil (se pide desde el hilo principal)
    var datosPerfil: (() -> Data)?
    /// Qué devolver en /medidor: el historial de tu control (hilo principal)
    var datosMedidor: (() -> Data)?
    /// Qué hacer con un cambio que llega por /api (se ejecuta en el hilo principal)
    var aplicar: (([String: Any]) -> [String: Any])?

    private let candado = NSLock()
    private var _clave = ""
    var clave: String {
        get { candado.lock(); defer { candado.unlock() }; return _clave }
        set { candado.lock(); _clave = newValue; candado.unlock() }
    }

    private var listener: NWListener?
    private let cola = DispatchQueue(label: "servidor-movil")
    private var directo: [ObjectIdentifier: NWConnection] = [:]
    private var ultimoJSON = "{}"
    private var ultimoEnvio = Date.distantPast
    private var fallos: [Date] = []
    private var bloqueadoHasta = Date.distantPast

    // MARK: - Arrancar y parar

    /// El puerto de siempre es el 8787: el acceso directo del móvil apunta a él. Si está ocupado
    /// (por ejemplo, otra copia de la app que aún se está cerrando), se insiste medio minuto antes de usar otro.
    private static let reintentos = 30

    func arrancar() {
        guard listener == nil else { return }
        intentar(0)
    }

    private func intentar(_ intento: Int) {
        guard listener == nil else { return }
        let candidatos = intento < Servidor.reintentos ? [UInt16(8787)] : Array(UInt16(8787)...UInt16(8797))
        guard let p = candidatos.first(where: Servidor.puertoLibre) else {
            if intento < Servidor.reintentos {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in self?.intentar(intento + 1) }
            } else {
                error = "No encuentro un puerto libre (8787–8797)."
            }
            return
        }
        do {
            // Reutilizar la dirección: tras reiniciar la app, las conexiones recientes del móvil dejan el puerto
            // «en espera» un rato; sin esto el 8787 falla, se acaba usando otro y el acceso directo deja de valer
            let parametros = NWParameters.tcp
            parametros.allowLocalEndpointReuse = true
            let l = try NWListener(using: parametros, on: NWEndpoint.Port(rawValue: p)!)
            l.newConnectionHandler = { [weak self] c in self?.nueva(c) }
            l.stateUpdateHandler = { [weak self, weak l] estado in
                DispatchQueue.main.async {
                    guard let self, let l, self.listener === l else { return }
                    switch estado {
                    case .ready:
                        self.activo = true; self.error = nil
                    case .failed(let e):
                        l.cancel()
                        self.listener = nil
                        self.activo = false
                        if intento < Servidor.reintentos {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in self?.intentar(intento + 1) }
                        } else {
                            self.error = "No se pudo abrir el servidor: \(e)"
                        }
                    default: break
                    }
                }
            }
            l.start(queue: cola)
            listener = l
            puerto = p
        } catch {
            if intento < Servidor.reintentos {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in self?.intentar(intento + 1) }
            } else {
                self.error = "No se pudo abrir el servidor: \(error.localizedDescription)"
            }
        }
    }

    func parar() {
        listener?.cancel()
        listener = nil
        cerrarClientes()
        activo = false
        clientes = 0
    }

    /// Desconecta a todos los móviles (por ejemplo, al cambiar la clave)
    func cerrarClientes() {
        cola.async {
            self.directo.values.forEach { $0.cancel() }
            self.directo = [:]
            self.contar()
        }
    }

    private static func puertoLibre(_ p: UInt16) -> Bool {
        let s = socket(AF_INET, SOCK_STREAM, 0)
        guard s >= 0 else { return false }
        defer { close(s) }
        var uno: Int32 = 1
        setsockopt(s, SOL_SOCKET, SO_REUSEADDR, &uno, socklen_t(MemoryLayout<Int32>.size))
        var dir = sockaddr_in()
        dir.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        dir.sin_family = sa_family_t(AF_INET)
        dir.sin_port = p.bigEndian
        dir.sin_addr.s_addr = INADDR_ANY
        return withUnsafePointer(to: &dir) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(s, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) } == 0
        }
    }

    // MARK: - Leer la petición

    private func nueva(_ c: NWConnection) {
        c.start(queue: cola)
        leer(c, Data())
    }

    /// Junta lo que llega hasta tener la cabecera y, si hay, todo el cuerpo
    private func leer(_ c: NWConnection, _ acumulado: Data) {
        c.receive(minimumIncompleteLength: 1, maximumLength: 16384) { [weak self] datos, _, fin, error in
            guard let self, error == nil else { c.cancel(); return }
            var buf = acumulado
            if let datos { buf.append(datos) }
            guard buf.count < 300_000 else { c.cancel(); return }
            if let fronteraRango = buf.range(of: Data("\r\n\r\n".utf8)) {
                let cabecera = String(decoding: buf[..<fronteraRango.lowerBound], as: UTF8.self)
                let cuerpo = Data(buf[fronteraRango.upperBound...])
                let largo = Servidor.largoDelCuerpo(cabecera)
                if cuerpo.count >= largo {
                    self.atender(c, cabecera, Data(cuerpo.prefix(largo)))
                    return
                }
            }
            if fin { c.cancel(); return }
            self.leer(c, buf)
        }
    }

    private static func largoDelCuerpo(_ cabecera: String) -> Int {
        for linea in cabecera.components(separatedBy: "\r\n") where linea.lowercased().hasPrefix("content-length:") {
            return Int(linea.dropFirst("content-length:".count).trimmingCharacters(in: .whitespaces)) ?? 0
        }
        return 0
    }

    private func atender(_ c: NWConnection, _ cabecera: String, _ cuerpo: Data) {
        let lineas = cabecera.components(separatedBy: "\r\n")
        let partes = (lineas.first ?? "").split(separator: " ")
        guard partes.count >= 2 else { c.cancel(); return }
        let metodo = String(partes[0])
        let trozos = String(partes[1]).split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false)
        let ruta = String(trozos[0])
        var consulta: [String: String] = [:]
        if trozos.count > 1 {
            for par in trozos[1].split(separator: "&") {
                let kv = par.split(separator: "=", maxSplits: 1)
                if kv.count == 2 { consulta[String(kv[0])] = String(kv[1]).removingPercentEncoding ?? String(kv[1]) }
            }
        }
        var cabezas: [String: String] = [:]
        for l in lineas.dropFirst() {
            if let i = l.firstIndex(of: ":") {
                cabezas[l[..<i].lowercased()] = l[l.index(after: i)...].trimmingCharacters(in: .whitespaces)
            }
        }

        switch (metodo, ruta) {
        case ("GET", "/"), ("GET", "/index.html"):
            responder(c, "200 OK", "text/html; charset=utf-8", Data(Pagina.html.utf8))
        case ("GET", "/icono.png"):
            if let url = Bundle.main.url(forResource: "icono-movil", withExtension: "png"), let datos = try? Data(contentsOf: url) {
                responder(c, "200 OK", "image/png", datos, cache: "public, max-age=86400")
            } else {
                responder(c, "404 Not Found", "text/plain; charset=utf-8", Data("Sin icono".utf8))
            }
        case ("GET", "/estado"):
            guard autorizado(c, consulta) else { return }
            responder(c, "200 OK", "application/json; charset=utf-8", Data(ultimoJSON.utf8))
        case ("GET", "/eventos"):
            guard autorizado(c, consulta) else { return }
            abrirDirecto(c)
        case ("GET", "/perfil"):
            guard autorizado(c, consulta) else { return }
            let datos = DispatchQueue.main.sync { self.datosPerfil?() } ?? Data("{}".utf8)
            responder(c, "200 OK", "application/json; charset=utf-8", datos)
        case ("GET", "/medidor"):
            guard autorizado(c, consulta) else { return }
            let datos = DispatchQueue.main.sync { self.datosMedidor?() } ?? Data("{}".utf8)
            responder(c, "200 OK", "application/json; charset=utf-8", datos)
        case ("POST", "/api"):
            guard autorizado(c, consulta) else { return }
            // Esta cabecera obliga al navegador a pedir permiso antes, y así otra web no puede cambiar nada
            guard cabezas["x-puente"] == "1", let obj = (try? JSONSerialization.jsonObject(with: cuerpo)) as? [String: Any] else {
                responder(c, "400 Bad Request", "application/json; charset=utf-8", Data(#"{"ok":false,"error":"petición no válida"}"#.utf8))
                return
            }
            let respuesta = DispatchQueue.main.sync { self.aplicar?(obj) } ?? ["ok": false]
            let datos = (try? JSONSerialization.data(withJSONObject: respuesta)) ?? Data("{}".utf8)
            responder(c, "200 OK", "application/json; charset=utf-8", datos)
        default:
            responder(c, "404 Not Found", "text/plain; charset=utf-8", Data("No existe".utf8))
        }
    }

    /// Comprueba la clave. Tras muchos fallos seguidos se bloquea un minuto.
    private func autorizado(_ c: NWConnection, _ consulta: [String: String]) -> Bool {
        let ahora = Date()
        if ahora < bloqueadoHasta {
            responder(c, "429 Too Many Requests", "text/plain; charset=utf-8", Data("Demasiados intentos".utf8))
            return false
        }
        if let k = consulta["k"], !clave.isEmpty, k == clave { return true }
        fallos = fallos.filter { ahora.timeIntervalSince($0) < 60 } + [ahora]
        if fallos.count >= 8 { bloqueadoHasta = ahora.addingTimeInterval(60); fallos = [] }
        responder(c, "401 Unauthorized", "text/plain; charset=utf-8", Data("Falta la clave".utf8))
        return false
    }

    private func responder(_ c: NWConnection, _ estado: String, _ tipo: String, _ cuerpo: Data, cache: String = "no-store") {
        let cabecera = "HTTP/1.1 \(estado)\r\nContent-Type: \(tipo)\r\nContent-Length: \(cuerpo.count)\r\n" +
            "Cache-Control: \(cache)\r\nConnection: close\r\n\r\n"
        c.send(content: Data(cabecera.utf8) + cuerpo, completion: .contentProcessed { _ in c.cancel() })
    }

    // MARK: - Directo (eventos del servidor)

    private func abrirDirecto(_ c: NWConnection) {
        let cabecera = "HTTP/1.1 200 OK\r\nContent-Type: text/event-stream\r\nCache-Control: no-store\r\n" +
            "Connection: keep-alive\r\nX-Accel-Buffering: no\r\n\r\n"
        let id = ObjectIdentifier(c)
        c.stateUpdateHandler = { [weak self] estado in
            switch estado {
            case .failed, .cancelled: self?.quitar(id)
            default: break
            }
        }
        directo[id] = c
        contar()
        c.send(content: Data((cabecera + "data: \(ultimoJSON)\n\n").utf8), completion: .contentProcessed { [weak self] e in
            if e != nil { c.cancel(); self?.quitar(id) }
        })
    }

    private func quitar(_ id: ObjectIdentifier) {
        cola.async { self.directo[id] = nil; self.contar() }
    }

    private func contar() {
        let n = directo.count
        DispatchQueue.main.async { if self.clientes != n { self.clientes = n } }
    }

    /// Se llama unas 20 veces por segundo desde la app con el estado en JSON
    func publicar(_ json: String) {
        cola.async {
            let ahora = Date()
            guard json != self.ultimoJSON || ahora.timeIntervalSince(self.ultimoEnvio) > 5 else { return }
            self.ultimoJSON = json
            self.ultimoEnvio = ahora
            let dato = Data("data: \(json)\n\n".utf8)
            for (id, c) in self.directo {
                c.send(content: dato, completion: .contentProcessed { [weak self] e in
                    if e != nil { c.cancel(); self?.quitar(id) }
                })
            }
        }
    }

    // MARK: - Direcciones para abrir desde el móvil

    /// Direcciones con la clave dentro (tras el #, que el navegador no manda por la red)
    static func direcciones(puerto: UInt16, clave: String) -> [String] {
        var resultado: [String] = []
        var lista: UnsafeMutablePointer<ifaddrs>?
        if getifaddrs(&lista) == 0, let primero = lista {
            var actual: UnsafeMutablePointer<ifaddrs>? = primero
            while let i = actual {
                let f = i.pointee
                if f.ifa_addr.pointee.sa_family == UInt8(AF_INET), (f.ifa_flags & UInt32(IFF_UP)) != 0,
                   (f.ifa_flags & UInt32(IFF_LOOPBACK)) == 0 {
                    var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    getnameinfo(f.ifa_addr, socklen_t(f.ifa_addr.pointee.sa_len), &host, socklen_t(host.count),
                                nil, 0, NI_NUMERICHOST)
                    let ip = String(cString: host)
                    let segundo = Int(ip.split(separator: ".").dropFirst().first ?? "") ?? 0
                    let privada = ip.hasPrefix("192.168.") || ip.hasPrefix("10.") || (ip.hasPrefix("172.") && (16...31).contains(segundo))
                    if privada { resultado.append("http://\(ip):\(puerto)/#k=\(clave)") }
                }
                actual = f.ifa_next
            }
            freeifaddrs(lista)
        }
        let nombre = ProcessInfo.processInfo.hostName
        if nombre.hasSuffix(".local") { resultado.append("http://\(nombre):\(puerto)/#k=\(clave)") }
        return resultado
    }

    static func codigoQR(_ texto: String) -> NSImage? {
        let filtro = CIFilter.qrCodeGenerator()
        filtro.message = Data(texto.utf8)
        filtro.correctionLevel = "M"
        guard let salida = filtro.outputImage?.transformed(by: CGAffineTransform(scaleX: 8, y: 8)) else { return nil }
        let rep = NSCIImageRep(ciImage: salida)
        let imagen = NSImage(size: rep.size)
        imagen.addRepresentation(rep)
        return imagen
    }
}
