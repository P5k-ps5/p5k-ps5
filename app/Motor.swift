import AppKit
import AVFoundation
import GameController
import IOKit.hid

// MARK: - DualSense (con el sistema de mandos de macOS)

/// Lee el DualSense. Solo coge mandos DualSense: el ESP32 en modo mac también se ve como
/// mando (de PS4) y no queremos leernos a nosotros mismos.
final class DualSense {
    private let cola = DispatchQueue(label: "dualsense", qos: .userInteractive)
    private let cerrojo = NSLock()
    private var ultimo = Estado()
    private(set) var mando: GCController?
    var alCambiarConexion: ((String?) -> Void)?

    var estado: Estado {
        cerrojo.lock(); defer { cerrojo.unlock() }
        var e = ultimo
        if silencio { e.botones |= Boton.silenciar.bit }
        return e
    }

    /// El botón de silenciar el micro no lo da el sistema de mandos de macOS: se lee del
    /// informe en bruto del DualSense, a la vez que el sistema (sin quitárselo).
    private var hid: IOHIDManager?
    private var silencio = false
    /// Con los mismos informes en bruto se mide el ritmo real del mando
    private var ritmo = RitmoMando()
    private var transporte: String?

    /// Informes por segundo, mayor hueco (ms) y si va por Bluetooth o por USB
    func ritmoActual() -> (hz: Int, huecoMs: Double, conexion: String?) {
        let t = ProcessInfo.processInfo.systemUptime
        cerrojo.lock(); defer { cerrojo.unlock() }
        let r = ritmo.actual(t: t)
        return (r.hz, r.huecoMs, r.hz > 0 ? transporte : nil)
    }

    /// Batería según el sistema (desde el hilo principal)
    var bateria: BateriaMando {
        guard let b = mando?.battery else { return BateriaMando() }
        return BateriaMando(nivel: b.batteryLevel, estado: b.batteryState.rawValue)
    }

    func arrancar() {
        GCController.shouldMonitorBackgroundEvents = true   // seguir leyendo con la ventana en segundo plano
        let centro = NotificationCenter.default
        centro.addObserver(forName: .GCControllerDidConnect, object: nil, queue: .main) { [weak self] _ in self?.buscar() }
        centro.addObserver(forName: .GCControllerDidDisconnect, object: nil, queue: .main) { [weak self] _ in self?.buscar() }
        GCController.startWirelessControllerDiscovery {}
        buscar()
        leerSilencio()
    }

    private func leerSilencio() {
        let m = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        IOHIDManagerSetDeviceMatchingMultiple(m, [
            [kIOHIDVendorIDKey: 0x054C, kIOHIDProductIDKey: 0x0CE6],   // DualSense
            [kIOHIDVendorIDKey: 0x054C, kIOHIDProductIDKey: 0x0DF2],   // DualSense Edge
        ] as CFArray)
        let yo = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterInputReportCallback(m, { contexto, _, _, _, id, informe, largo in
            guard let contexto else { return }
            Unmanaged<DualSense>.fromOpaque(contexto).takeUnretainedValue()
                .anotarInforme(silencio: InformeDualSense.silencio(id: id, informe, largo))
        }, yo)
        // Bluetooth o USB: se mira al conectarse el mando
        IOHIDManagerRegisterDeviceMatchingCallback(m, { contexto, _, _, dispositivo in
            guard let contexto else { return }
            let t = IOHIDDeviceGetProperty(dispositivo, kIOHIDTransportKey as CFString) as? String
            Unmanaged<DualSense>.fromOpaque(contexto).takeUnretainedValue().ponerTransporte(t)
        }, yo)
        IOHIDManagerSetDispatchQueue(m, cola)
        IOHIDManagerOpen(m, IOOptionBits(kIOHIDOptionsTypeNone))   // abrir antes de activar
        IOHIDManagerActivate(m)
        hid = m
    }

    private func anotarInforme(silencio pulsado: Bool?) {
        let ahora = ProcessInfo.processInfo.systemUptime
        cerrojo.lock()
        ritmo.informe(t: ahora)
        if let pulsado { silencio = pulsado }
        cerrojo.unlock()
    }

    private func ponerTransporte(_ t: String?) {
        cerrojo.lock(); transporte = t.map { $0.lowercased().contains("bluetooth") ? "Bluetooth" : "USB" }; cerrojo.unlock()
    }

    private func buscar() {
        let encontrado = GCController.controllers().first { $0.extendedGamepad is GCDualSenseGamepad }
        guard encontrado !== mando else { return }
        mando = encontrado
        cerrojo.lock(); ultimo = Estado(); silencio = false; cerrojo.unlock()
        guard let c = encontrado, let pad = c.extendedGamepad as? GCDualSenseGamepad else {
            alCambiarConexion?(nil)
            return
        }
        c.handlerQueue = cola
        // Que el botón PS y Create no abran cosas del sistema mientras juegas
        for el in pad.allElements where el.isBoundToSystemGesture {
            el.preferredSystemGestureState = .disabled
        }
        pad.valueChangedHandler = { [weak self] pad, _ in self?.leer(pad) }
        leer(pad)
        refrescarLuz()
        alCambiarConexion?(c.vendorName ?? "DualSense")
    }

    private func leer(_ g: GCExtendedGamepad) {
        var e = Estado()
        func b(_ boton: Boton, _ el: GCControllerButtonInput?) {
            if el?.isPressed == true { e.botones |= boton.bit }
        }
        b(.cuadrado, g.buttonX); b(.x, g.buttonA); b(.circulo, g.buttonB); b(.triangulo, g.buttonY)
        b(.l1, g.leftShoulder); b(.r1, g.rightShoulder)
        b(.share, g.buttonOptions); b(.options, g.buttonMenu); b(.ps, g.buttonHome)
        b(.l3, g.leftThumbstickButton); b(.r3, g.rightThumbstickButton)
        b(.arriba, g.dpad.up); b(.derecha, g.dpad.right); b(.abajo, g.dpad.down); b(.izquierda, g.dpad.left)
        if let ds = g as? GCDualSenseGamepad { b(.tactil, ds.touchpadButton) }
        e.lx = byte(g.leftThumbstick.xAxis.value);  e.ly = byte(-g.leftThumbstick.yAxis.value)
        e.rx = byte(g.rightThumbstick.xAxis.value); e.ry = byte(-g.rightThumbstick.yAxis.value)
        e.l2 = UInt8((g.leftTrigger.value * 255).rounded())
        e.r2 = UInt8((g.rightTrigger.value * 255).rounded())
        if e.l2 > 0 { e.botones |= Boton.l2.bit }
        if e.r2 > 0 { e.botones |= Boton.r2.bit }
        cerrojo.lock(); ultimo = e; cerrojo.unlock()
    }

    /// Barra de luz: el color del perfil. Al encender o apagar el anti-recoil destella un
    /// momento en verde (encendido) o rojo (apagado) y vuelve al color del perfil.
    /// Ojo: macOS solo deja cambiarla a la app que está delante; si no, pone su color.
    private var colorPerfil = (r: Float(0), g: Float(0.31), b: Float(1))
    private var destello: (r: Float, g: Float, b: Float)?
    private var destelloID = 0
    private var alterna = false

    func ponerColor(hex: String) {
        guard let c = DualSense.leerHex(hex) else { return }
        if c != colorPerfil { colorPerfil = c; refrescarLuz() }
    }

    func destellar(encendido: Bool) { destellar(encendido ? (0, 1, 0) : (1, 0, 0)) }

    func destellar(_ color: (r: Float, g: Float, b: Float)) {
        destelloID += 1
        let id = destelloID
        destello = color
        refrescarLuz()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { [weak self] in
            guard let self, self.destelloID == id else { return }
            self.destello = nil
            self.refrescarLuz()
        }
    }

    /// macOS vuelve a poner su color cada pocos segundos, así que se reenvía cada segundo
    /// (cambiando un pelo el tono para que no lo descarte por repetido).
    func refrescarLuz() {
        guard let luz = mando?.light else { return }
        let c = destello ?? colorPerfil
        alterna.toggle()
        let k: Float = alterna ? 1 : 0.97
        luz.color = GCColor(red: c.r * k, green: c.g * k, blue: c.b * k)
    }

    static func leerHex(_ hex: String) -> (r: Float, g: Float, b: Float)? {
        let s = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard s.count == 6, let v = UInt32(s, radix: 16) else { return nil }
        return (Float((v >> 16) & 0xFF) / 255, Float((v >> 8) & 0xFF) / 255, Float(v & 0xFF) / 255)
    }

    private func byte(_ v: Float) -> UInt8 { UInt8(min(max(127.5 + Double(v) * 127.5, 0), 255).rounded()) }
}

// MARK: - ESP32 por el puerto serie

final class Esp32 {
    static let comCH343 = "5CE52173911"   // el USB-C "COM" de esta placa
    private(set) var ruta: String?
    private var fd: Int32 = -1
    var conectado: Bool { fd >= 0 }

    // Sincronización de ajustes (Sincro.swift): líneas de texto que se mandan desde el hilo del motor, entre
    // trama y trama, y las respuestas «@AJ …» de la placa (el resto de lo que manda es su log)
    private let cerrojoLineas = NSLock()
    private var lineasPorEnviar: [String] = []
    private var respuestasRecibidas: [String] = []
    private var abierto = false
    private var porEscribir = Data()     // lo que no cupo de una línea (sale en la vuelta siguiente)
    private var leido = Data()

    /// ¿Conectada? (desde cualquier hilo)
    var conectadoSeguro: Bool { cerrojoLineas.lock(); defer { cerrojoLineas.unlock() }; return abierto }

    /// Deja una línea para mandarla en la próxima vuelta del motor (desde cualquier hilo)
    func encolarLinea(_ l: String) {
        cerrojoLineas.lock(); lineasPorEnviar.append(l); cerrojoLineas.unlock()
    }

    /// Las respuestas que han llegado desde la última vez (desde cualquier hilo)
    func tomarRespuestas() -> [String] {
        cerrojoLineas.lock(); defer { cerrojoLineas.unlock() }
        let r = respuestasRecibidas
        respuestasRecibidas = []
        return r
    }

    /// En cada vuelta del motor: manda las líneas pendientes y lee lo que haya llegado (sin esperar). Si una
    /// trama se cuela en medio de una línea no pasa nada: la placa las separa (las tramas empiezan por A5 5A).
    func servirLineas() {
        guard fd >= 0 else { return }
        cerrojoLineas.lock()
        for l in lineasPorEnviar { porEscribir.append(contentsOf: Array((l + "\n").utf8)) }
        lineasPorEnviar = []
        cerrojoLineas.unlock()
        if !porEscribir.isEmpty {
            let n = porEscribir.withUnsafeBytes { write(fd, $0.baseAddress, $0.count) }
            if n > 0 { porEscribir.removeFirst(n) } else if n < 0 && errno != EAGAIN { cerrar(); return }
        }
        var buf = [UInt8](repeating: 0, count: 1024)
        while true {
            let n = read(fd, &buf, buf.count)
            if n <= 0 { break }
            leido.append(contentsOf: buf[0..<n])
        }
        var nuevas: [String] = []
        while let i = leido.firstIndex(of: UInt8(ascii: "\n")) {
            let linea = String(decoding: leido[leido.startIndex..<i], as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            leido.removeSubrange(leido.startIndex...i)
            if linea.hasPrefix("@AJ ") { nuevas.append(linea) }
        }
        if leido.count > 8192 { leido.removeAll() }   // basura sin saltos de línea
        if !nuevas.isEmpty {
            cerrojoLineas.lock(); respuestasRecibidas.append(contentsOf: nuevas); cerrojoLineas.unlock()
        }
    }

    /// Prefiere el puerto serie del USB nativo (modo mac); si no, el COM.
    func conectar() -> Bool {
        let puertos = ((try? FileManager.default.contentsOfDirectory(atPath: "/dev")) ?? [])
            .filter { $0.hasPrefix("cu.usbmodem") }.sorted().map { "/dev/" + $0 }
        guard let ruta = puertos.first(where: { !$0.contains(Esp32.comCH343) }) ?? puertos.first else { return false }
        let f = open(ruta, O_RDWR | O_NOCTTY | O_NONBLOCK)
        guard f >= 0 else { return false }
        var t = termios()
        tcgetattr(f, &t)
        cfmakeraw(&t)
        t.c_cflag |= tcflag_t(CLOCAL | CREAD)
        t.c_cflag &= ~tcflag_t(HUPCL)          // no reiniciar la placa al cerrar
        tcsetattr(f, TCSANOW, &t)
        var baudios: speed_t = 921600
        _ = ioctl(f, UInt(0x80085402), &baudios)   // IOSSIOSPEED: velocidades no estándar
        fd = f
        self.ruta = ruta
        cerrojoLineas.lock(); abierto = true; cerrojoLineas.unlock()
        return true
    }

    /// Trama: A5 5A | botones(2) cruceta lx ly rx ry l2 r2 | xor de los 9 bytes
    func enviar(_ e: Estado) {
        guard fd >= 0 else { return }
        let fisicos = e.botones & 0x3FFF
        var datos: [UInt8] = [UInt8(fisicos & 0xFF), UInt8(fisicos >> 8), cruceta(e),
                              e.lx, e.ly, e.rx, e.ry, e.l2, e.r2]
        datos.append(datos.reduce(0, ^))
        let trama: [UInt8] = [0xA5, 0x5A] + datos
        let n = trama.withUnsafeBytes { write(fd, $0.baseAddress, $0.count) }
        if n < 0 && errno != EAGAIN { cerrar() }   // se ha desenchufado
    }

    func cerrar() {
        if fd >= 0 { close(fd) }
        fd = -1
        ruta = nil
        porEscribir.removeAll()
        leido.removeAll()
        cerrojoLineas.lock(); abierto = false; lineasPorEnviar = []; respuestasRecibidas = []; cerrojoLineas.unlock()
    }

    private func cruceta(_ e: Estado) -> UInt8 {
        let (ar, de, ab, iz) = (e.pulsado(.arriba), e.pulsado(.derecha), e.pulsado(.abajo), e.pulsado(.izquierda))
        switch (ar, de, ab, iz) {
        case (true, false, false, false): return 0
        case (true, true, false, false):  return 1
        case (false, true, false, false): return 2
        case (false, true, true, false):  return 3
        case (false, false, true, false): return 4
        case (false, false, true, true):  return 5
        case (false, false, false, true): return 6
        case (true, false, false, true):  return 7
        default: return 8
        }
    }
}

/// La placa de verdad para la sincronización de ajustes (Sincro.swift)
final class CanalEsp32: Canal {
    private let esp: Esp32
    init(_ esp: Esp32) { self.esp = esp }
    var conectado: Bool { esp.conectadoSeguro }
    @discardableResult func linea(_ l: String) -> Bool { esp.encolarLinea(l); return true }
    func respuestas() -> [String] { esp.tomarRespuestas() }
}

// MARK: - Motor: DualSense -> perfil -> ESP32, 1000 veces por segundo

final class Motor: ObservableObject {
    @Published private(set) var entrada = Estado()
    @Published private(set) var salida = Estado()
    @Published private(set) var nombreMando: String?
    @Published private(set) var puertoEsp: String?
    @Published private(set) var enviosPorSegundo = 0
    /// Vueltas del bucle en el último segundo (deberían ser unas 900) y la más lenta, en ms
    @Published private(set) var vueltasPorSegundo = 0
    @Published private(set) var peorVueltaMs = 0.0
    /// Ritmo real del DualSense (informes/s y mayor hueco), por dónde va y su batería
    @Published private(set) var hzMando = 0
    @Published private(set) var huecoMandoMs = 0.0
    @Published private(set) var conexionMando: String?
    @Published private(set) var bateria = BateriaMando()
    @Published private(set) var antiRecoilEncendido = false
    @Published private(set) var ayudaEncendida = false
    @Published var pausado = false { didSet { cerrojo.lock(); pausaInterna = pausado; cerrojo.unlock() } }
    /// Sincronización de los ajustes con la placa («al día», «enviando», «sin placa»…)
    @Published private(set) var estadoSincro = "sin placa"
    private var sincro: Sincro?

    let dualsense = DualSense()
    private let esp = Esp32()
    private let procesador = Procesador()
    private let historial = HistorialAyuda()
    /// Medidor de tu control: lee la entrada del DualSense; no cambia nada de lo que se manda
    let grabador = GrabadorRafagas()
    private let cerrojo = NSLock()
    private var perfil = Perfil()
    private var generales = AjustesGenerales()
    private var pausaInterna = false
    private let voz = AVSpeechSynthesizer()

    /// Lo pide el mando con la combinación de cambiar de perfil: +1 siguiente, -1 anterior
    var alPedirPerfil: ((Int) -> Void)?
    /// Lo pide el mando con la combinación de ajustar: (cambio de ajuste, cambio de valor)
    var alPedirAjuste: ((Int, Int) -> Void)?
    /// Lo pide el mando con la combinación de la fuerza del anti-recoil: +1 sube, -1 baja
    var alPedirFuerza: ((Int) -> Void)?
    /// Lo mismo con ←/→: mover la corrección lateral del anti-recoil (+1 derecha, -1 izquierda)
    var alPedirLateral: ((Int) -> Void)?
    /// Lo pide el mando con la combinación de una macro: activarla o desactivarla
    var alPedirMacro: ((UUID) -> Void)?

    /// Lo que se puede encender y apagar desde «En vivo» y vive en el motor (no en el perfil)
    enum Interruptor { case antiRecoil, ayuda }
    private var pedidos: [Interruptor] = []

    /// Un widget de «En vivo» pide encender o apagar algo: lo hace el hilo del motor en la siguiente vuelta
    func alternar(_ i: Interruptor) {
        cerrojo.lock(); pedidos.append(i); cerrojo.unlock()
    }
    /// Lo pide el mando con la combinación de cambiar el patrón de la ayuda al apuntado: +1 o -1
    var alPedirPatron: ((Int) -> Void)?

    /// Se llama desde el hilo principal cada vez que cambia algo en la ventana
    func ponerPerfil(_ p: Perfil, _ g: AjustesGenerales) {
        cerrojo.lock(); perfil = p; generales = g; cerrojo.unlock()
        dualsense.ponerColor(hex: p.color)
    }

    /// El Mac dice el perfil en voz alta (la pantalla suele estar en la PS5)
    /// Con los avisos de voz apagados, el aviso sale en pantalla (en la ventana y en el móvil)
    func anunciar(_ texto: String) {
        cerrojo.lock(); let conVoz = generales.avisosVoz; cerrojo.unlock()
        voz.stopSpeaking(at: .immediate)
        guard conVoz else {
            aviso = AvisoPantalla(id: (aviso?.id ?? 0) + 1, texto: texto)
            return
        }
        let frase = AVSpeechUtterance(string: texto)
        frase.voice = AVSpeechSynthesisVoice(language: "es-ES")
        voz.speak(frase)
    }

    /// Los mismos ajustes en la placa y aquí (Sincro.swift). Va en el hilo principal, como el almacén; las
    /// líneas las manda y las lee el hilo del motor (Esp32.servirLineas).
    func arrancarSincro(almacen: Almacen) {
        let s = Sincro(archivoPerfiles: almacen.archivoURL, versionInicial: almacen.version)
        sincro = s
        let canal = CanalEsp32(esp)
        let reloj = Timer(timeInterval: 0.005, repeats: true) { [weak self] _ in
            guard let self else { return }
            if let aviso = s.vuelta(canal, almacen, t: ProcessInfo.processInfo.systemUptime) { self.anunciar(aviso) }
            if self.estadoSincro != s.estado { self.estadoSincro = s.estado }
        }
        RunLoop.main.add(reloj, forMode: .common)
    }

    /// El último aviso que no se ha dicho en voz alta (el id cambia con cada aviso, aunque el texto se repita)
    struct AvisoPantalla: Equatable { let id: Int; let texto: String }
    @Published private(set) var aviso: AvisoPantalla?

    func arrancar() {
        dualsense.alCambiarConexion = { [weak self] nombre in
            DispatchQueue.main.async { self?.nombreMando = nombre }
        }
        procesador.alCambiarAntiRecoil = { [weak self] encendido in
            DispatchQueue.main.async {
                guard let self else { return }
                // Un sonido en el Mac al cambiar: la luz solo la controla la app que está delante
                if self.antiRecoilEncendido != encendido {
                    NSSound(named: encendido ? "Glass" : "Bottle")?.play()
                }
                if self.antiRecoilEncendido != encendido { self.dualsense.destellar(encendido: encendido) }
                self.antiRecoilEncendido = encendido
            }
        }
        procesador.alCambiarAyuda = { [weak self] encendida in
            DispatchQueue.main.async {
                guard let self, self.ayudaEncendida != encendida else { return }
                // Aviso distinto al del anti-recoil: otro sonido y destello cian / naranja
                NSSound(named: encendida ? "Ping" : "Funk")?.play()
                self.dualsense.destellar(encendida ? (0, 1, 1) : (1, 0.5, 0))
                self.ayudaEncendida = encendida
            }
        }
        dualsense.arrancar()
        Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.dualsense.refrescarLuz()
            let r = self.dualsense.ritmoActual(), b = self.dualsense.bateria
            if self.hzMando != r.hz { self.hzMando = r.hz }
            if self.huecoMandoMs != r.huecoMs { self.huecoMandoMs = r.huecoMs }
            if self.conexionMando != r.conexion { self.conexionMando = r.conexion }
            if self.bateria != b { self.bateria = b }
        }
        let hilo = Thread { [weak self] in self?.bucle() }
        hilo.qualityOfService = .userInteractive
        hilo.name = "motor"
        hilo.start()
    }

    private func bucle() {
        var ultimoEnviado: Estado?
        var enviadoEn = 0.0, reintentoEn = 0.0, pintadoEn = 0.0, contadoEn = 0.0
        var envios = 0, porSegundo = 0
        var vueltas = 0, vueltasSeg = 0, anterior = ProcessInfo.processInfo.systemUptime, peor = 0.0, peorSeg = 0.0
        var botonesAntes: UInt32 = 0
        var muestreadoEn = 0.0
        while true {
            let t = ProcessInfo.processInfo.systemUptime
            vueltas += 1; peor = max(peor, t - anterior); anterior = t
            if !esp.conectado && t >= reintentoEn {
                reintentoEn = t + 1
                if esp.conectar() { ultimoEnviado = nil }
            }
            esp.servirLineas()   // sincronización de ajustes con la placa

            cerrojo.lock(); let p = perfil; let g = generales; let pausa = pausaInterna
            let pedidosAhora = pedidos; pedidos = []; cerrojo.unlock()
            for pedido in pedidosAhora {
                switch pedido {
                case .antiRecoil: procesador.alternarAntiRecoil()
                case .ayuda: procesador.alternarAyuda()
                }
            }
            let hayMando = dualsense.mando != nil
            var e = dualsense.estado

            // Cambiar de perfil desde el mando: mantener un botón y pulsar otro
            let flanco = e.botones & ~botonesAntes
            botonesAntes = e.botones
            // Fuerza del anti-recoil: mientras lo mantienes, ↑ y ↓ son solo para esto (no llegan a la consola)
            let (fuerza, pasoFuerza, pasoLateral) = ComboFuerza.aplicar(&e, flanco: flanco, g)
            if pasoFuerza != 0 { DispatchQueue.main.async { [weak self] in self?.alPedirFuerza?(pasoFuerza) } }
            if pasoLateral != 0 { DispatchQueue.main.async { [weak self] in self?.alPedirLateral?(pasoLateral) } }
            if g.ajusteMando && !(fuerza && g.ajusteMantener == g.fuerzaMantener) && e.pulsado(g.ajusteMantener) {
                let dv = flanco & Boton.arriba.bit != 0 ? 1 : (flanco & Boton.abajo.bit != 0 ? -1 : 0)
                let dp = flanco & Boton.derecha.bit != 0 ? 1 : (flanco & Boton.izquierda.bit != 0 ? -1 : 0)
                if dv != 0 || dp != 0 { DispatchQueue.main.async { [weak self] in self?.alPedirAjuste?(dp, dv) } }
            }
            let ayuda = p.ayuda
            if ayuda.cambioActivo && e.pulsado(ayuda.cambioMantener) {
                let paso = flanco & ayuda.cambioSiguiente.bit != 0 ? 1 : (flanco & ayuda.cambioAnterior.bit != 0 ? -1 : 0)
                if paso != 0 { DispatchQueue.main.async { [weak self] in self?.alPedirPatron?(paso) } }
            }
            // Activar o desactivar una macro con su combinación (se guarda en el perfil, en el hilo principal)
            if flanco != 0 {
                for id in ComboMacros.pedidas(e, flanco: flanco, p) {
                    DispatchQueue.main.async { [weak self] in self?.alPedirMacro?(id) }
                }
            }
            if g.cambioPerfil && e.pulsado(g.cambioMantener) {
                let paso = flanco & g.cambioSiguiente.bit != 0 ? 1 : (flanco & g.cambioAnterior.bit != 0 ? -1 : 0)
                if paso != 0 { DispatchQueue.main.async { [weak self] in self?.alPedirPerfil?(paso) } }
            }
            // Medidor de tu control: graba tu mano (la entrada), antes de procesar nada
            if g.medidor.activo && hayMando { grabador.tick(e, t: t, config: g.medidor, perfil: p.nombre) } else { grabador.cortar() }
            let s = (pausa || !hayMando) ? Estado() : procesador.procesar(e, p, t: t)
            // Diagnóstico de la ayuda: se guarda en un anillo (100 muestras por segundo) sin salir de este hilo
            var d = procesador.diagnostico
            if pausa || !hayMando {
                // Sin mando (o en pausa) no se procesa nada, pero se siguen mostrando los valores efectivos del perfil
                let ef = p.ayuda.efectivos
                d = DiagnosticoAyuda()
                d.encendida = procesador.ayudaEncendida
                d.forma = p.ayuda.forma
                d.tamano = ef.tamano; d.hz = ef.hz; d.entradaMs = ef.entradaMs; d.ceder = ef.ceder
                d.limitada = p.ayuda.limitado
            }
            if t - muestreadoEn >= 0.01 { muestreadoEn = t; historial.anadir(d) } else { historial.actualizar(d) }

            if esp.conectado && (s != ultimoEnviado || t - enviadoEn >= 0.05) {
                esp.enviar(s)
                ultimoEnviado = s
                enviadoEn = t
                envios += 1
            }
            if t - contadoEn >= 1 {
                porSegundo = envios; envios = 0
                vueltasSeg = vueltas; vueltas = 0; peorSeg = peor * 1000; peor = 0
                contadoEn = t
            }
            if t - pintadoEn >= 1.0 / 30 {     // la ventana se refresca a 30 fps
                pintadoEn = t
                let ruta = esp.ruta
                let ps = porSegundo, vs = vueltasSeg, pv = peorSeg
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    if self.entrada != e { self.entrada = e }
                    if self.salida != s { self.salida = s }
                    if self.puertoEsp != ruta { self.puertoEsp = ruta }
                    if self.enviosPorSegundo != ps { self.enviosPorSegundo = ps }
                    if self.vueltasPorSegundo != vs { self.vueltasPorSegundo = vs }
                    if self.peorVueltaMs != pv { self.peorVueltaMs = pv }
                }
            }
            usleep(1000)
        }
    }

    /// Para la vista de diagnóstico (la de la app y la del móvil): el estado actual de la ayuda y
    /// las últimas `muestras` muestras (una cada 10 ms) de lo que suma al stick derecho
    func instantaneaAyuda(muestras: Int) -> (DiagnosticoAyuda, [Float], [Float], [Float]) {
        historial.ultimas(muestras)
    }

    func cerrar() {
        esp.enviar(Estado())   // que no se quede nada pulsado
    }
}

/// Anillo de las últimas muestras de la ayuda al apuntado. Lo escribe el hilo del motor y lo lee
/// quien pinta (app o móvil); el candado dura lo que tarda en copiar unos cientos de números.
final class HistorialAyuda {
    private let capacidad = 400
    private let candado = NSLock()
    private var x: [Float], y: [Float], a: [Float]
    private var cuenta = 0
    private var ultimo = DiagnosticoAyuda()

    init() {
        x = [Float](repeating: 0, count: capacidad)
        y = x; a = x
    }

    func anadir(_ d: DiagnosticoAyuda) {
        candado.lock()
        let i = cuenta % capacidad
        x[i] = Float(d.offX); y[i] = Float(d.offY); a[i] = Float(d.amplitud)
        cuenta += 1
        ultimo = d
        candado.unlock()
    }

    func actualizar(_ d: DiagnosticoAyuda) {
        candado.lock(); ultimo = d; candado.unlock()
    }

    func ultimas(_ n: Int) -> (DiagnosticoAyuda, [Float], [Float], [Float]) {
        candado.lock(); defer { candado.unlock() }
        let k = min(n, capacidad, cuenta)
        var ox = [Float](), oy = [Float](), oa = [Float]()
        ox.reserveCapacity(k); oy.reserveCapacity(k); oa.reserveCapacity(k)
        for j in (cuenta - k)..<cuenta {
            let i = j % capacidad
            ox.append(x[i]); oy.append(y[i]); oa.append(a[i])
        }
        return (ultimo, ox, oy, oa)
    }
}
