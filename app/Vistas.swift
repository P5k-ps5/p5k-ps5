import SwiftUI
import IOKit.pwr_mgt

// MARK: - Tema

/// La misma estética que NeuroClaude: negro, blanco con opacidades y un solo acento, el lima. Líneas finas, sin
/// sombras ni degradados; Inter Tight para leer y Geist Mono para etiquetas y datos. Colores en sRGB exacto.
enum Tema {
    static let fondo = Color.black
    static let tinta = Color(.sRGB, red: 0x0A / 255.0, green: 0x0A / 255.0, blue: 0x0A / 255.0)
    static let vivo = Color(.sRGB, red: 0xC8 / 255.0, green: 0xF0 / 255.0, blue: 0x4D / 255.0)   // el lima de NeuroClaude, Lens y Rankeo
    static let fallo = Color(.sRGB, red: 1, green: 0x5D / 255.0, blue: 0x5D / 255.0)
    static let suave = Color.white.opacity(0.68)
    static let tenue = Color.white.opacity(0.46)
    static let lineaFina = Color.white.opacity(0.1)
    static let linea = Color.white.opacity(0.16)
    static let lineaFuerte = Color.white.opacity(0.36)
    static let salida = Animation.timingCurve(0.16, 1, 0.3, 1, duration: 0.32)
    static let titular = sans(34, .medium)

    // Las fuentes van en Resources/fuentes (ATSApplicationFontsPath); si faltaran, SwiftUI usa la del sistema
    static func sans(_ tam: CGFloat, _ peso: Font.Weight = .regular) -> Font {
        .custom(peso == .semibold ? "InterTight-SemiBold" : (peso == .medium ? "InterTight-Medium" : "InterTight-Regular"), size: tam)
    }
    static func mono(_ tam: CGFloat, _ peso: Font.Weight = .light) -> Font {
        .custom(peso == .medium ? "GeistMono-Medium" : (peso == .regular ? "GeistMono-Regular" : "GeistMono-Light"), size: tam)
    }
}

extension View {
    /// Etiqueta pequeña en mono y mayúsculas
    func etiqueta(_ color: Color = Tema.tenue) -> some View {
        textCase(.uppercase).font(Tema.mono(11, .regular)).tracking(0.7).foregroundStyle(color)
    }
    /// Campo de texto en su caja de línea fina
    func campo() -> some View {
        textFieldStyle(.plain).font(Tema.mono(13)).padding(.horizontal, 8).padding(.vertical, 6)
            .background(Color.white.opacity(0.035)).overlay(Rectangle().strokeBorder(Tema.linea))
    }
}

/// Botón de línea fina en mono. «fuerte» es la acción principal: la píldora blanca de NeuroClaude.
struct BotonCaja: ButtonStyle {
    var fuerte = false
    var elegido = false
    var alarma = false
    @Environment(\.isEnabled) private var activo

    func makeBody(configuration c: Configuration) -> some View {
        let rojo = alarma || c.role == .destructive
        return c.label
            .lineLimit(1).fixedSize()
            .font(fuerte ? Tema.sans(13, .medium) : Tema.mono(12, .regular))
            .foregroundStyle(fuerte || elegido ? Color.black : (rojo ? Tema.fallo : Color.white))
            .padding(.horizontal, fuerte ? 15 : 10).padding(.vertical, fuerte ? 7 : 6)
            .background(fuerte || elegido ? Color.white.opacity(c.isPressed ? 0.8 : 1) : Color.white.opacity(c.isPressed ? 0.14 : 0.08),
                        in: fuerte ? AnyShape(Capsule()) : AnyShape(Rectangle()))
            .overlay { if !fuerte { Rectangle().strokeBorder(rojo ? Tema.fallo.opacity(0.4) : Tema.linea) } }
            .scaleEffect(c.isPressed ? 0.97 : 1)
            .opacity(activo ? 1 : 0.45)
            .animation(Tema.salida, value: c.isPressed)
    }
}

/// El mismo conmutador de línea fina que la página del móvil
struct Interruptor: ToggleStyle {
    func makeBody(configuration c: Configuration) -> some View {
        Button { c.isOn.toggle() } label: {
            HStack(spacing: 9) {
                ZStack(alignment: c.isOn ? .trailing : .leading) {
                    Rectangle().fill(c.isOn ? Tema.vivo.opacity(0.1) : Color.clear)
                    Rectangle().fill(c.isOn ? Tema.vivo : Color.white.opacity(0.6)).frame(width: 10, height: 10).padding(.horizontal, 3)
                }
                .frame(width: 30, height: 16)
                .overlay(Rectangle().strokeBorder(c.isOn ? Tema.vivo : Tema.lineaFuerte))
                c.label.fixedSize(horizontal: false, vertical: true)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(Tema.salida, value: c.isOn)
        .accessibilityValue(c.isOn ? "encendido" : "apagado")
    }
}

// MARK: - App

@main
struct PuenteApp: App {
    @NSApplicationDelegateAdaptor(Delegado.self) var delegado

    var body: some Scene {
        WindowGroup("p5k-ps5") {
            Contenido()
                .environmentObject(delegado.almacen)
                .environmentObject(delegado.motor)
                .environmentObject(delegado.servidor)
                .environmentObject(delegado.medidor)
                .frame(minWidth: 960, minHeight: 640)
                .onAppear { delegado.configurar() }
        }
        .windowResizability(.contentMinSize)
    }
}

final class Delegado: NSObject, NSApplicationDelegate {
    let motor = Motor()
    let servidor = Servidor()
    let medidor = MedidorControl()

    let almacen = Almacen()
    private var configurado = false

    /// Arranca el puente: motor, perfiles y servidor del móvil. Se llama al terminar de abrir la app
    /// (aunque no llegue a verse ninguna ventana, por ejemplo con la sesión bloqueada) y otra vez
    /// cuando aparece la ventana; solo hace algo la primera.
    func applicationDidFinishLaunching(_ notification: Notification) { configurar() }

    func configurar() {
        guard !configurado else { return }
        configurado = true
        let almacen = self.almacen
        let motor = self.motor
        almacen.alCambiar = { motor.ponerPerfil($0, $1) }
        motor.ponerPerfil(almacen.activo, almacen.generales)
        motor.alPedirPerfil = { [weak almacen] paso in
            guard let almacen, almacen.perfiles.count > 1 else { return }
            almacen.cambiarPerfil(paso)
            NSSound(named: "Pop")?.play()
            if almacen.generales.decirNombre { motor.anunciar(almacen.activo.nombre) }
        }
        motor.alPedirLateral = { [weak almacen] d in
            guard let almacen else { return }
            let frase = almacen.ajustarLateral(d)
            NSSound(named: "Tink")?.play()
            motor.anunciar(frase)
        }
        motor.alPedirFuerza = { [weak almacen] d in
            guard let almacen else { return }
            let frase = almacen.ajustarFuerza(d)
            NSSound(named: "Tink")?.play()
            motor.anunciar(frase)
        }
        motor.alPedirMacro = { [weak almacen] id in
            guard let almacen, let frase = almacen.alternarMacro(id) else { return }
            NSSound(named: almacen.activo.macros.first { $0.id == id }?.activa == true ? "Glass" : "Bottle")?.play()
            motor.anunciar(frase)
        }
        motor.alPedirPatron = { [weak almacen] paso in
            guard let almacen else { return }
            let nombre = almacen.cambiarPatronAyuda(paso)
            NSSound(named: "Morse")?.play()
            motor.anunciar(nombre)
        }
        motor.alPedirAjuste = { [weak almacen] dp, dv in
            guard let almacen else { return }
            let frase = almacen.ajusteRapido(dParam: dp, dValor: dv)
            NSSound(named: "Tink")?.play()
            motor.anunciar(frase)
        }
        let servidor = self.servidor
        servidor.clave = almacen.generales.clave
        almacen.alCambiar = { motor.ponerPerfil($0, $1); servidor.clave = $1.clave }
        servidor.datosPerfil = { Delegado.perfilJSON(motor, almacen) }
        servidor.aplicar = { [medidor = self.medidor] in Delegado.aplicar($0, motor, almacen, medidor: medidor) }
        let medidor = self.medidor
        servidor.datosMedidor = { Delegado.medidorJSON(medidor) }
        if almacen.generales.servidorMovil { servidor.arrancar() }
        self.iniciarPublicacion(motor: motor, almacen: almacen)
        motor.arrancarSincro(almacen: almacen)   // los mismos ajustes en la placa y aquí
        arrancar()
    }


    /// Historial del medidor para el móvil: últimas 20 ráfagas, su media, observaciones y días
    static func medidorJSON(_ m: MedidorControl) -> Data {
        func r1(_ v: Double) -> Double { (v * 10).rounded() / 10 }
        func media(_ x: AnalisisRafaga.Media) -> [String: Any] {
            ["rafagas": x.rafagas, "reaccion": x.reaccionMs.map(r1) ?? NSNull(), "sinCorregir": r1(x.sinCorregir * 100),
             "bajada": r1(x.bajada), "constancia": r1(x.constancia), "lateral": r1(x.lateralMedio),
             "temblor": r1(x.temblor), "tirones": r1(x.tirones)]
        }
        let ultimas = Array(m.rafagas.suffix(20))
        let lista: [[String: Any]] = ultimas.reversed().map {
            ["fecha": Int($0.fecha.timeIntervalSince1970 * 1000), "perfil": $0.perfil, "duracion": Int($0.duracionMs),
             "reaccion": $0.reaccionMs.map(r1) ?? NSNull(), "bajada": r1($0.bajadaMedia), "constancia": r1($0.constancia),
             "lateral": r1($0.lateralMedio), "lateralMax": r1($0.lateralMax), "temblor": r1($0.temblor), "tirones": $0.tirones]
        }
        let d: [String: Any] = [
            "total": m.rafagas.count, "rafagas": lista, "media": media(AnalisisRafaga.media(ultimas)),
            "observaciones": AnalisisRafaga.observaciones(ultimas),
            "dias": m.porDia.prefix(14).map { ["dia": Int($0.dia.timeIntervalSince1970 * 1000), "media": media($0.media)] as [String: Any] },
        ]
        return (try? JSONSerialization.data(withJSONObject: d)) ?? Data("{}".utf8)
    }
    private var publicando: Timer?

    /// Cada 50 ms, si hay algún móvil mirando, se prepara el estado y se le manda
    func iniciarPublicacion(motor: Motor, almacen: Almacen) {
        guard publicando == nil else { return }
        publicando = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            guard let self, self.servidor.clientes > 0 else { return }
            self.servidor.publicar(Delegado.instantanea(motor, almacen))
        }
    }

    // MARK: Lo que ve y cambia el móvil

    private struct DatosRevision: Codable {
        var perfiles: [Perfil]
        var activo: UUID?
        var generales: AjustesGenerales
    }

    /// Cambia cuando cambia cualquier ajuste, sea desde la app, el mando o el móvil
    static func revision(_ m: Motor, _ a: Almacen) -> String {
        let c = JSONEncoder()
        c.outputFormatting = [.sortedKeys]
        let datos = (try? c.encode(DatosRevision(perfiles: a.perfiles, activo: a.activoID, generales: a.generales))) ?? Data()
        return String(datos.hashValue) + (m.pausado ? "p" : "")
    }

    /// Estado en directo (cada 50 ms)
    static func instantanea(_ m: Motor, _ a: Almacen) -> String {
        func estado(_ e: Estado) -> [String: Any] {
            ["b": e.botones, "lx": e.lx, "ly": e.ly, "rx": e.rx, "ry": e.ry, "l2": e.l2, "r2": e.r2]
        }
        let p = a.activo
        // Diagnóstico de la ayuda al apuntado: valores efectivos; el gráfico usa las últimas 150 muestras (1,5 s)
        // y el monitor analiza las últimas 200 (2 s), igual que la tarjeta de la app
        let (dg, hx2, hy2, ha2) = m.instantaneaAyuda(muestras: 200)
        let hx = Array(hx2.suffix(150)), hy = Array(hy2.suffix(150)), ha = Array(ha2.suffix(150))
        func milesimas(_ v: [Float]) -> [Int] { v.map { Int(($0 * 1000).rounded()) } }
        func r3(_ v: Double) -> Double { (v * 1000).rounded() / 1000 }
        let diag: [String: Any] = [
            "on": dg.encendida, "ap": dg.aplicando, "forma": dg.forma.rawValue, "t": r3(dg.tamano), "hz": r3(dg.hz),
            "e": r3(dg.entradaMs), "c": r3(dg.ceder), "lim": dg.limitada, "ramp": r3(dg.rampa), "ces": r3(dg.cesion),
            "amp": r3(dg.amplitud), "fase": r3(dg.fase), "tr": dg.enTransicion,
            "hx": milesimas(hx), "hy": milesimas(hy), "ha": milesimas(ha),
        ]
        var monitor: [String: Any] = ["activo": a.generales.monitor.activo]
        if a.generales.monitor.activo {
            let inf = MonitorSenales.analizar(x: hx2, y: hy2, dt: 0.01, limites: a.generales.monitor)
            let me = inf.metricas
            monitor["estado"] = inf.estado.nombre
            monitor["gravedad"] = inf.estado.rawValue
            monitor["metricas"] = ["muestras": me.muestras, "maxAbs": r3(me.maxAbs), "maxSalto": r3(me.maxSalto),
                                   "maxVelocidad": r3(me.maxVelocidad), "maxAceleracion": r3(me.maxAceleracion),
                                   "cambiosSigno": r3(me.cambiosSigno), "noNumericos": me.noNumericos]
            monitor["eventos"] = inf.eventos.prefix(8).map {
                ["g": $0.gravedad.nombre, "a": $0.gravedad == .anomalia, "i": $0.indice, "eje": $0.eje,
                 "motivo": $0.motivo, "v": $0.valor.isFinite ? r3($0.valor) : NSNull(), "lim": r3($0.limite)] as [String: Any]
            }
            monitor["mas"] = max(0, inf.eventos.count - 8) + inf.eventosOmitidos
        }
        let d: [String: Any] = [
            "diag": diag, "monitor": monitor,
            "entrada": estado(m.entrada), "salida": estado(m.salida),
            "mando": m.nombreMando ?? NSNull(), "esp": m.puertoEsp != nil, "envios": m.enviosPorSegundo, "sincro": m.estadoSincro,
            "mandoRitmo": ["hz": m.hzMando, "huecoMs": Int(m.huecoMandoMs.rounded()), "conexion": m.conexionMando ?? NSNull()] as [String: Any],
            "bateria": ["porcentaje": m.bateria.porcentaje ?? NSNull(), "estado": m.bateria.estado] as [String: Any],
            "funciones": ResumenFunciones.de(p, a.generales, antiRecoil: m.antiRecoilEncendido, ayuda: m.ayudaEncendida)
                .map { ["nombre": $0.nombre, "detalle": $0.detalle, "on": $0.encendida] as [String: Any] },
            "bucle": ["vueltas": m.vueltasPorSegundo, "peorMs": (m.peorVueltaMs * 10).rounded() / 10] as [String: Any],
            "pausado": m.pausado, "antiRecoil": m.antiRecoilEncendido, "ayuda": m.ayudaEncendida,
            "aviso": m.aviso.map { ["id": $0.id, "texto": $0.texto] as [String: Any] } ?? NSNull(),
            "widgets": estadoWidgets(m, a).map {
                ["id": $0.id.uuidString, "nombre": $0.nombre, "detalle": $0.detalle, "on": $0.encendido,
                 "tipo": $0.tipo.rawValue] as [String: Any]
            },
            "rev": revision(m, a),
            "perfil": ["nombre": p.nombre, "color": p.color] as [String: Any],
        ]
        guard let datos = try? JSONSerialization.data(withJSONObject: d),
              let texto = String(data: datos, encoding: .utf8) else { return "{}" }
        return texto
    }

    /// El perfil activo entero, la lista de perfiles y los ajustes generales (sin la clave)
    static func perfilJSON(_ m: Motor, _ a: Almacen) -> Data {
        func objeto<T: Encodable>(_ v: T) -> Any {
            (try? JSONSerialization.jsonObject(with: JSONEncoder().encode(v))) ?? [:]
        }
        var generales = objeto(a.generales) as? [String: Any] ?? [:]
        generales["clave"] = nil
        generales["servidorMovil"] = nil
        let d: [String: Any] = [
            "perfiles": a.perfiles.map { ["id": $0.id.uuidString, "nombre": $0.nombre, "color": $0.color] },
            "activo": a.activoID?.uuidString ?? "",
            "perfil": objeto(a.activo),
            "generales": generales,
            "pausado": m.pausado,
            "catalogo": Widgets.catalogo(a.activo).map {
                ["tipo": $0.tipo.rawValue, "objetivo": $0.objetivo?.uuidString ?? "", "nombre": Widgets.nombre($0, a.activo)]
            },
            "rev": revision(m, a),
        ]
        return (try? JSONSerialization.data(withJSONObject: d)) ?? Data("{}".utf8)
    }

    /// Tocar un widget (en la ventana o en el móvil). false si ya no existe.
    @discardableResult
    static func alternarWidget(_ id: UUID, _ m: Motor, _ a: Almacen) -> Bool {
        guard let w = a.activo.widgets.first(where: { $0.id == id }) else { return false }
        switch w.tipo {
        case .antiRecoil: m.alternar(.antiRecoil)
        case .ayuda: m.alternar(.ayuda)
        case .pausa: m.pausado.toggle()
        case .turbos: a.alternarTurbos()
        case .macros: a.alternarMacros()
        case .turbo: return w.objetivo.flatMap { a.alternarTurbo($0) } != nil
        case .macro: return w.objetivo.flatMap { a.alternarMacro($0) } != nil
        }
        return true
    }

    /// Los widgets del perfil activo tal como se ven ahora (para la ventana y el móvil)
    static func estadoWidgets(_ m: Motor, _ a: Almacen) -> [EstadoWidget] {
        let p = a.activo
        return p.widgets.compactMap {
            Widgets.estado($0, p, antiRecoil: m.antiRecoilEncendido, ayuda: m.ayudaEncendida, pausado: m.pausado)
        }
    }

    /// Un cambio que llega del móvil
    static func aplicar(_ accion: [String: Any], _ m: Motor, _ a: Almacen, medidor: MedidorControl? = nil) -> [String: Any] {
        func respuesta(_ error: String?) -> [String: Any] {
            error == nil ? ["ok": true, "rev": revision(m, a)] : ["ok": false, "error": error!, "rev": revision(m, a)]
        }
        switch accion["accion"] as? String {
        case "poner":
            guard let ruta = accion["ruta"] as? String, let valor = accion["valor"] else { return respuesta("falta la ruta o el valor") }
            return respuesta(a.ponerRuta(ruta, valor))
        case "perfil":
            guard let id = (accion["id"] as? String).flatMap(UUID.init(uuidString:)) else { return respuesta("perfil no válido") }
            a.seleccionar(id)
            return respuesta(nil)
        case "situaciones":
            let n = a.crearPerfilesPorSituacion()
            var r = respuesta(nil)
            r["info"] = n == 0 ? "Ya existen «Corto alcance» y «Largo alcance»" : "Añadidos \(n) perfil\(n == 1 ? "" : "es")"
            return r
        case "medidorBorrar":
            medidor?.borrarTodo()
            return respuesta(nil)
        case "patron":
            guard let i = accion["indice"] as? Int else { return respuesta("patrón no válido") }
            a.usarPatronAyuda(i)
            return respuesta(nil)
        case "variante":
            // Variantes de la ayuda al apuntado: usar, guardar la actual, actualizar la elegida o borrar
            switch accion["modo"] as? String {
            case "usar":
                guard let id = (accion["id"] as? String).flatMap(UUID.init(uuidString:)) else { return respuesta("variante no válida") }
                a.usarVarianteAyuda(id)
            case "guardar": a.guardarVarianteAyuda((accion["nombre"] as? String) ?? "")
            case "actualizar": a.actualizarVarianteAyuda()
            case "borrar":
                guard let id = (accion["id"] as? String).flatMap(UUID.init(uuidString:)) else { return respuesta("variante no válida") }
                a.borrarVarianteAyuda(id)
            default: return respuesta("modo desconocido")
            }
            return respuesta(nil)
        case "nuevo": a.nuevo(); return respuesta(nil)
        case "duplicar": a.duplicar(); return respuesta(nil)
        case "borrar": a.borrarActivo(); return respuesta(nil)
        case "pausa":
            m.pausado = (accion["valor"] as? Bool) ?? false
            return respuesta(nil)
        case "widget":
            // Tocar un widget de «En vivo»: encender o apagar lo que controla
            guard let id = (accion["id"] as? String).flatMap(UUID.init(uuidString:)) else { return respuesta("widget no válido") }
            return respuesta(alternarWidget(id, m, a) ? nil : "Ese widget ya no existe")
        case "widgetAnadir":
            // «basicos» añade de golpe los de siempre
            if accion["tipo"] as? String == "basicos" {
                Widgets.basicos(a.activo).forEach(a.anadirWidget)
                return respuesta(nil)
            }
            guard let tipo = (accion["tipo"] as? String).flatMap(Widget.Tipo.init(rawValue:)) else { return respuesta("widget no válido") }
            a.anadirWidget(Widget(tipo: tipo, objetivo: (accion["objetivo"] as? String).flatMap(UUID.init(uuidString:))))
            return respuesta(nil)
        case "widgetQuitar":
            guard let id = (accion["id"] as? String).flatMap(UUID.init(uuidString:)) else { return respuesta("widget no válido") }
            a.quitarWidget(id)
            return respuesta(nil)
        case "widgetMover":
            guard let id = (accion["id"] as? String).flatMap(UUID.init(uuidString:)), let paso = accion["paso"] as? Int else {
                return respuesta("widget no válido")
            }
            a.moverWidget(id, paso)
            return respuesta(nil)
        default:
            return respuesta("acción desconocida")
        }
    }

    private var arrancado = false

    private var sinDormir: IOPMAssertionID = 0
    private var sinDormirSinPantalla: IOPMAssertionID = 0

    func arrancar() {
        guard !arrancado else { return }
        arrancado = true
        let medidor = self.medidor
        motor.grabador.alTerminar = { x, abajo, perfil in medidor.registrar(x: x, abajo: abajo, perfil: perfil) }
        motor.arrancar()
        // El Mac no se duerme mientras la app está abierta: mover el mando no cuenta como
        // usar el Mac y, si se durmiera, la consola dejaría de recibir el mando.
        // Tampoco deja que se apague la pantalla: al apagarse, macOS bloquea la sesión.
        IOPMAssertionCreateWithName(kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
                                    IOPMAssertionLevel(kIOPMAssertionLevelOn),
                                    "p5k-ps5: pasando el mando a la consola" as CFString, &sinDormir)
        // Con el portátil cerrado, cuando la pantalla cambia a la PS5 macOS se queda sin pantalla
        // y querría dormirse. Enchufado a la corriente, esto lo impide.
        IOPMAssertionCreateWithName(kIOPMAssertionTypePreventSystemSleep as CFString,
                                    IOPMAssertionLevel(kIOPMAssertionLevelOn),
                                    "p5k-ps5: sin dormir aunque la pantalla esté en la PS5" as CFString,
                                    &sinDormirSinPantalla)
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    func applicationWillTerminate(_ notification: Notification) {
        servidor.parar()
        medidor.guardarAhora()
        motor.cerrar()
        if sinDormir != 0 { IOPMAssertionRelease(sinDormir) }
        if sinDormirSinPantalla != 0 { IOPMAssertionRelease(sinDormirSinPantalla) }
    }
}

// MARK: - Ventana principal

enum Seccion: String, CaseIterable, Identifiable {
    case vivo = "En vivo", sticks = "Sticks", gatillos = "Gatillos", botones = "Botones"
    case turbo = "Turbo", macros = "Macros", antiRecoil = "Anti-recoil", apuntado = "Ayuda al apuntado"
    case control = "Mi control", perfiles = "Perfiles", movil = "Móvil", ayuda = "Ayuda"
    var id: String { rawValue }

    /// La barra lateral, agrupada: lo que se mira jugando, el mando, las asistencias y la app
    static let grupos: [(titulo: String, secciones: [Seccion])] = [
        ("En directo", [.vivo, .control]),
        ("Mando", [.sticks, .gatillos, .botones, .turbo, .macros]),
        ("Asistencias", [.antiRecoil, .apuntado]),
        ("App", [.perfiles, .movil, .ayuda]),
    ]

    var icono: String {
        switch self {
        case .vivo: return "dot.radiowaves.left.and.right"
        case .sticks: return "smallcircle.filled.circle"
        case .gatillos: return "slider.horizontal.below.rectangle"
        case .botones: return "arrow.left.arrow.right"
        case .turbo: return "bolt"
        case .macros: return "list.bullet.rectangle"
        case .antiRecoil: return "scope"
        case .apuntado: return "target"
        case .control: return "chart.line.uptrend.xyaxis"
        case .perfiles: return "person.crop.rectangle.stack"
        case .movil: return "iphone"
        case .ayuda: return "questionmark.circle"
        }
    }
}

struct Contenido: View {
    @EnvironmentObject var almacen: Almacen
    @EnvironmentObject var motor: Motor
    @State private var seccion: Seccion? = .vivo

    var body: some View {
        HStack(spacing: 0) {
            Indice(seccion: $seccion)
                .safeAreaInset(edge: .bottom) { Conexiones().padding(10) }
                .frame(width: 220)
            Rectangle().fill(Tema.lineaFina).frame(width: 1)
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if let s = seccion, s != .vivo { Text(s.rawValue).font(Tema.titular).tracking(-1).padding(.bottom, 2) }
                    switch seccion ?? .vivo {
                    case .vivo: EnVivo()
                    case .sticks: Sticks()
                    case .gatillos: Gatillos()
                    case .botones: Reasignar()
                    case .turbo: Turbos()
                    case .macros: Macros()
                    case .antiRecoil: AntiRecoilVista()
                    case .apuntado: AyudaApuntadoVista()
                    case .perfiles: Perfiles()
                    case .movil: MovilVista()
                    case .control: MiControlVista()
                    case .ayuda: Ayuda()
                    }
                }
                .padding(.horizontal, 24).padding(.vertical, 18)
                .frame(maxWidth: 980, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
        }
        .background(Tema.fondo)
        .navigationTitle("p5k-ps5")
        .overlay(alignment: .bottom) { ToastAviso() }
        .toolbar {
            ToolbarItemGroup {
                Menu {
                    ForEach(almacen.perfiles) { p in
                        Button { almacen.activoID = p.id } label: {
                            if p.id == almacen.activoID { Label(p.nombre, systemImage: "checkmark") } else { Text(p.nombre) }
                        }
                    }
                } label: {
                    Label { Text(almacen.activo.nombre).lineLimit(1) } icon: { Image(nsImage: puntoDeColor(almacen.activo.color)) }
                        .labelStyle(.titleAndIcon)
                }
                .menuStyle(.borderedButton)
                .frame(maxWidth: 220)
                .help("Perfil activo")
                Toggle(isOn: $motor.pausado) {
                    Label(motor.pausado ? "En pausa" : "Pausar", systemImage: motor.pausado ? "pause.circle.fill" : "pause.circle")
                }
                .toggleStyle(.button)
                .labelStyle(.titleAndIcon)
                .buttonStyle(BotonCaja(alarma: motor.pausado))
                .help("En pausa, la consola recibe el mando quieto")
            }
        }
        .toolbarBackground(Tema.fondo, for: .windowToolbar)
        .toolbarBackground(.visible, for: .windowToolbar)
        .preferredColorScheme(.dark)
        .tint(Tema.vivo)
        .font(Tema.sans(14))
        .buttonStyle(BotonCaja())
        .toggleStyle(Interruptor())
    }
}

/// El índice de la izquierda: texto en líneas, en lima lo que está abierto, como el de NeuroClaude
struct Indice: View {
    @Binding var seccion: Seccion?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ForEach(Seccion.grupos, id: \.titulo) { grupo in
                    VStack(alignment: .leading, spacing: 1) {
                        Text(grupo.titulo).etiqueta().padding(.bottom, 5)
                        ForEach(grupo.secciones) { FilaIndice(seccion: $0, elegida: $seccion) }
                    }
                }
            }
            .padding(.horizontal, 14).padding(.top, 8).padding(.bottom, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct FilaIndice: View {
    let seccion: Seccion
    @Binding var elegida: Seccion?
    @State private var encima = false

    var body: some View {
        let activa = (elegida ?? .vivo) == seccion
        Button { elegida = seccion } label: {
            HStack(spacing: 9) {
                Image(systemName: seccion.icono).font(.system(size: 12)).frame(width: 16)
                    .offset(x: encima ? 3 : 0)
                Text(seccion.rawValue).font(Tema.sans(14))
                Spacer(minLength: 0)
            }
            .foregroundStyle(activa || encima ? Tema.vivo : Color.white.opacity(0.78))
            .frame(height: 26)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { encima = $0 }
        .animation(Tema.salida, value: encima)
        .accessibilityAddTraits(activa ? .isSelected : [])
    }
}

struct Conexiones: View {
    @EnvironmentObject var motor: Motor
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Punto(ok: motor.nombreMando != nil, texto: motor.nombreMando == nil ? "DualSense apagado" : "DualSense")
            if motor.nombreMando != nil {
                RitmoYBateria()
            }
            Punto(ok: motor.puertoEsp != nil, texto: motor.puertoEsp.map { $0.contains(Esp32.comCH343) ? "ESP32 (COM)" : "ESP32 (USB)" } ?? "ESP32 sin conectar")
            if motor.puertoEsp != nil {
                Text("\(motor.enviosPorSegundo) envíos/s").font(Tema.mono(11)).foregroundStyle(Tema.tenue)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(Rectangle().strokeBorder(Tema.linea))
    }
}

/// Ritmo real del mando y su batería, con avisos si el ritmo es bajo o la batería va a acabarse
struct RitmoYBateria: View {
    @EnvironmentObject var motor: Motor
    static let hzBajo = 100
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(motor.hzMando > 0
                 ? "\(motor.hzMando) Hz\(motor.conexionMando.map { " por \($0)" } ?? "") · peor hueco \(Int(motor.huecoMandoMs.rounded())) ms"
                 : "Sin informes del mando")
                .font(Tema.mono(11)).foregroundStyle(Tema.suave)
            if motor.hzMando > 0 && motor.hzMando < RitmoYBateria.hzBajo {
                Text("Ritmo bajo").font(Tema.mono(11, .regular)).foregroundStyle(.white).lineLimit(1)
                    .help("Por cable USB (directo o con un hub) el mando suele mandar más rápido")
            }
            Text(motor.bateria.texto)
                .font(Tema.mono(11)).foregroundStyle(motor.bateria.baja ? Tema.fallo : Color.secondary)
        }
        .padding(.leading, 14)
        .help("Informes por segundo que manda el DualSense al Mac y el mayor hueco entre dos seguidos en el último segundo")
    }
}

struct Punto: View {
    let ok: Bool, texto: String
    var body: some View {
        HStack(spacing: 7) {
            PuntoVivo(color: ok ? Tema.vivo : Tema.fallo, late: ok)
            Text(texto).font(Tema.mono(12)).lineLimit(1)
        }
    }
}

/// Punto de estado; lo que está vivo late (salvo con «Reducir movimiento»)
struct PuntoVivo: View {
    let color: Color
    var late = true
    @Environment(\.accessibilityReduceMotion) private var sinMovimiento
    @State private var latido = false

    var body: some View {
        Circle().fill(color).frame(width: 6, height: 6)
            .background {
                if late && !sinMovimiento {
                    Circle().stroke(color.opacity(latido ? 0 : 0.6), lineWidth: 1)
                        .scaleEffect(latido ? 3 : 1)
                        .animation(.timingCurve(0.16, 1, 0.3, 1, duration: 1.6).repeatForever(autoreverses: false), value: latido)
                        .onAppear { latido = true }
                }
            }
    }
}

// MARK: - Piezas reutilizables

/// Fila con un deslizador, su valor y una explicación
struct Deslizador: View {
    let titulo: String
    @Binding var valor: Double
    let rango: ClosedRange<Double>
    var paso: Double = 1
    var unidad = "%"
    var decimales = 0
    var ayuda: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(titulo)
                Spacer()
                Text(String(format: "%.\(decimales)f", valor) + (unidad.isEmpty ? "" : " " + unidad))
                    .font(Tema.mono(12, .regular)).foregroundStyle(Tema.vivo)
            }
            Raya(valor: $valor, rango: rango, paso: paso)
            if let ayuda { Text(ayuda).font(Tema.sans(12)).foregroundStyle(Tema.suave) }
        }
    }
}

/// La raya del deslizador: fina, con el tramo en lima y un pomo blanco. Con mínimo negativo se rellena desde el
/// cero, para no aparentar un valor que no hay. Se maneja también con las flechas, y VoiceOver ve un Slider normal.
struct Raya: View {
    @Binding var valor: Double
    let rango: ClosedRange<Double>
    let paso: Double
    private let pomo: CGFloat = 10

    private func ajustar(_ v: Double) -> Double {
        min(rango.upperBound, max(rango.lowerBound, rango.lowerBound + ((v - rango.lowerBound) / paso).rounded() * paso))
    }

    var body: some View {
        GeometryReader { g in
            let ancho = max(g.size.width - pomo, 1)
            let total = rango.upperBound - rango.lowerBound
            let x = ancho * CGFloat((valor - rango.lowerBound) / total)
            let cero = ancho * CGFloat((min(max(0, rango.lowerBound), rango.upperBound) - rango.lowerBound) / total)
            ZStack(alignment: .leading) {
                Rectangle().fill(Tema.linea).frame(height: 2)
                Rectangle().fill(Tema.vivo).frame(width: abs(x - cero), height: 2).offset(x: min(x, cero) + pomo / 2)
                Rectangle().fill(.white).frame(width: pomo, height: 20).offset(x: x)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged {
                valor = ajustar(rango.lowerBound + Double(($0.location.x - pomo / 2) / ancho) * total)
            })
        }
        .frame(height: 26)
        .focusable()
        .onMoveCommand { d in
            if d == .left || d == .down { valor = ajustar(valor - paso) }
            if d == .right || d == .up { valor = ajustar(valor + paso) }
        }
        .accessibilityRepresentation { Slider(value: $valor, in: rango, step: paso) }
    }
}

struct Tarjeta<C: View>: View {
    let titulo: String
    @ViewBuilder var contenido: C
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(titulo).etiqueta(Tema.suave)
                .padding(.horizontal, 14).frame(maxWidth: .infinity, minHeight: 34, alignment: .leading)
                .overlay(alignment: .bottom) { Rectangle().fill(Tema.lineaFina).frame(height: 1) }
            VStack(alignment: .leading, spacing: 12) { contenido }.padding(14)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(Rectangle().strokeBorder(Tema.linea))
    }
}

struct StickDibujo: View {
    let x: UInt8, y: UInt8
    var tam: CGFloat = 90
    var body: some View {
        ZStack {
            Circle().stroke(Tema.lineaFuerte, lineWidth: 1)
            Path { p in
                p.move(to: CGPoint(x: tam / 2, y: 0)); p.addLine(to: CGPoint(x: tam / 2, y: tam))
                p.move(to: CGPoint(x: 0, y: tam / 2)); p.addLine(to: CGPoint(x: tam, y: tam / 2))
            }.stroke(Tema.lineaFina)
            Circle().fill(Tema.vivo).frame(width: 13, height: 13)
                .position(x: CGFloat(x) / 255 * tam, y: CGFloat(y) / 255 * tam)
        }
        .frame(width: tam, height: tam)
    }
}

struct Barra: View {
    let titulo: String, valor: UInt8
    var body: some View {
        VStack(spacing: 4) {
            ZStack(alignment: .bottom) {
                Rectangle().fill(Tema.vivo)
                    .frame(height: CGFloat(valor) / 255 * 90)
            }
            .frame(width: 16, height: 90, alignment: .bottom)
            .overlay(Rectangle().strokeBorder(Tema.lineaFuerte))
            Text(titulo).font(Tema.sans(12))
        }
    }
}

struct MandoDibujo: View {
    let titulo: String, estado: Estado
    var botones = Boton.allCases
    var body: some View {
        Tarjeta(titulo: titulo) {
            HStack(alignment: .top, spacing: 18) {
                Barra(titulo: "L2", valor: estado.l2)
                VStack { StickDibujo(x: estado.lx, y: estado.ly); Text("Izquierdo").font(Tema.sans(12)) }
                VStack { StickDibujo(x: estado.rx, y: estado.ry); Text("Derecho").font(Tema.sans(12)) }
                Barra(titulo: "R2", valor: estado.r2)
            }
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(58), spacing: 6), count: 6), spacing: 6) {
                ForEach(botones) { b in
                    Text(b.corto)
                        .font(Tema.mono(11, .regular))
                        .frame(width: 58, height: 26)
                        .background(estado.pulsado(b) ? Tema.vivo : Color.clear)
                        .overlay(Rectangle().strokeBorder(estado.pulsado(b) ? Tema.vivo : Tema.lineaFina))
                        .foregroundStyle(estado.pulsado(b) ? Color.black : Tema.tenue)
                }
            }
        }
    }
}

// MARK: - Avisos en pantalla

/// Con los avisos de voz apagados, lo que se diría sale aquí abajo unos segundos
struct ToastAviso: View {
    @EnvironmentObject var motor: Motor
    @State private var visible: Motor.AvisoPantalla?

    var body: some View {
        ZStack {
            if let a = visible {
                Label(a.texto, systemImage: "bell.fill")
                    .font(Tema.mono(12, .regular))
                    .padding(.horizontal, 14).padding(.vertical, 9)
                    .background(Tema.fondo)
                    .overlay(Rectangle().strokeBorder(Tema.lineaFuerte))
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .id(a.id)
            }
        }
        .padding(.bottom, 20)
        .animation(Tema.salida, value: visible)
        .onChange(of: motor.aviso) { nuevo in
            visible = nuevo
            guard let id = nuevo?.id else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.8) { if visible?.id == id { visible = nil } }
        }
        .allowsHitTesting(false)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - En vivo

struct EnVivo: View {
    @EnvironmentObject var motor: Motor
    @EnvironmentObject var almacen: Almacen
    var body: some View {
        if motor.nombreMando == nil {
            Aviso(icono: "gamecontroller", texto: "Enciende el DualSense con el botón PS. Si nunca lo has conectado a este Mac: mantén PS + Create hasta que parpadee y emparéjalo en Ajustes del Sistema → Bluetooth.")
        }
        if motor.puertoEsp == nil {
            Aviso(icono: "cable.connector", texto: "Conecta la placa: por el USB-C «USB» si estás probando con el Mac, o por el «COM» si el USB va al P5Mate.")
        }
        if motor.pausado {
            Aviso(icono: "pause.circle.fill", texto: "En pausa: la consola recibe el mando quieto. Reanuda con el botón de arriba o con el widget de pausa.")
        }
        // Lo que se toca jugando va primero; los mandos en directo, debajo
        PanelWidgets()
        HStack(alignment: .top, spacing: 16) {
            MandoDibujo(titulo: "Tu DualSense", estado: motor.entrada)
            MandoDibujo(titulo: "Lo que recibe la consola", estado: motor.salida, botones: Boton.salidas)
        }
        let funciones = ResumenFunciones.de(almacen.activo, almacen.generales,
                                            antiRecoil: motor.antiRecoilEncendido, ayuda: motor.ayudaEncendida)
        Tarjeta(titulo: "Activo en este perfil") {
            if funciones.isEmpty {
                Text("Nada activado: el mando pasa tal cual.").font(Tema.sans(13)).foregroundStyle(Tema.suave)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 8, alignment: .leading)],
                          alignment: .leading, spacing: 8) {
                    ForEach(funciones, id: \.nombre) { InsigniaFuncion(funcion: $0) }
                }
            }
        }
    }
}

/// Botones para encender y apagar cosas sin usar el mando. Cada perfil tiene los suyos.
struct PanelWidgets: View {
    @EnvironmentObject var motor: Motor
    @EnvironmentObject var almacen: Almacen
    @State private var editando = false

    var body: some View {
        let estados = Delegado.estadoWidgets(motor, almacen)
        let catalogo = Widgets.catalogo(almacen.activo)
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Text("Widgets").etiqueta(Tema.suave)
                Text("tócalos para encender o apagar").font(Tema.sans(13)).foregroundStyle(Tema.tenue)
                Spacer()
                Menu {
                    ForEach(catalogo, id: \.id) { w in
                        Button(Widgets.nombre(w, almacen.activo)) { almacen.anadirWidget(w) }
                    }
                } label: { Label("Añadir", systemImage: "plus") }
                .menuStyle(.borderedButton).fixedSize()
                .disabled(catalogo.isEmpty)
                if !estados.isEmpty {
                    Button(editando ? "Listo" : "Editar") { withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { editando.toggle() } }
                        .keyboardShortcut(editando ? .defaultAction : .init("e", modifiers: .command))
                }
            }
            if estados.isEmpty {
                HStack(spacing: 14) {
                    Image(systemName: "square.grid.2x2").font(.title2).foregroundStyle(Tema.suave)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Sin widgets en este perfil").font(Tema.sans(13, .medium))
                        Text("Añade botones para encender anti-recoil, ayuda, turbo o macros sin tocar el mando. También salen en el móvil.")
                            .font(Tema.sans(13)).foregroundStyle(Tema.suave).fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                    Button("Añadir los básicos") { Widgets.basicos(almacen.activo).forEach(almacen.anadirWidget) }
                        .buttonStyle(BotonCaja(fuerte: true))
                }
                .padding(14)
                .overlay(Rectangle().strokeBorder(Tema.linea))
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 124, maximum: 156), spacing: 12)], alignment: .leading, spacing: 12) {
                    ForEach(Array(estados.enumerated()), id: \.element.id) { i, e in
                        WidgetBoton(estado: e, editando: editando,
                                    primero: i == 0, ultimo: i == estados.count - 1,
                                    tocar: { Delegado.alternarWidget(e.id, motor, almacen) },
                                    mover: { almacen.moverWidget(e.id, $0) },
                                    quitar: { withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { almacen.quitarWidget(e.id) } })
                    }
                }
            }
        }
        .onChange(of: almacen.activoID) { _ in editando = false }
    }
}

extension Widget.Tipo {
    var color: Color {
        switch self {
        // Encendido = lima; solo la pausa, que es un estado de alarma, en rojo. El tipo lo dice el icono.
        case .pausa: return Tema.fallo
        default: return Tema.vivo
        }
    }
}

/// Un widget: grande y fácil de acertar. Encendido, línea y símbolo en su color y el punto latiendo.
struct WidgetBoton: View {
    let estado: EstadoWidget
    let editando: Bool
    let primero: Bool, ultimo: Bool
    let tocar: () -> Void
    let mover: (Int) -> Void
    let quitar: () -> Void
    @State private var encima = false

    var body: some View {
        let color = estado.tipo.color
        let on = estado.encendido
        Button(action: tocar) {
            // Una tecla de línea fina: símbolo arriba, estado en la esquina y el nombre abajo
            VStack(alignment: .leading, spacing: 2) {
                Image(systemName: estado.icono)
                    .font(.system(size: 20, weight: .light))
                    .foregroundStyle(on ? color : Tema.tenue)
                    .frame(height: 26, alignment: .topLeading)
                Spacer(minLength: 8)
                Text(estado.nombre).font(Tema.sans(14, .medium)).multilineTextAlignment(.leading).lineLimit(2)
                Text(estado.detalle.isEmpty ? (on ? "Encendido" : "Apagado") : estado.detalle)
                    .font(Tema.mono(11)).foregroundStyle(on ? Tema.suave : Tema.tenue).multilineTextAlignment(.leading).lineLimit(2)
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 128, alignment: .topLeading)
            .background(on ? color.opacity(0.08) : Color.clear)
            .overlay(Rectangle().strokeBorder(on ? color : (encima ? Tema.lineaFuerte : Tema.linea),
                                              style: StrokeStyle(lineWidth: 1, dash: editando ? [5, 4] : [])))
            .overlay(alignment: .topTrailing) {
                if !editando {
                    HStack(spacing: 6) {
                        if on { PuntoVivo(color: color) }
                        Text(on ? "ON" : "OFF").font(Tema.mono(11, .regular))
                    }
                    .foregroundStyle(on ? color : Tema.tenue)
                    .padding(.top, 12).padding(.trailing, 12)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(editando)
        .animation(Tema.salida, value: on)
        .animation(Tema.salida, value: encima)
        .onHover { encima = $0 }
        .overlay(alignment: .topTrailing) {
            if editando {
                HStack(spacing: 2) {
                    Button { mover(-1) } label: { Image(systemName: "chevron.left") }.disabled(primero)
                    Button { mover(1) } label: { Image(systemName: "chevron.right") }.disabled(ultimo)
                    Button(role: .destructive, action: quitar) { Image(systemName: "xmark") }
                }
                .buttonStyle(.borderless).controlSize(.small)
                .padding(4)
                .background(Tema.fondo)
                .overlay(Rectangle().strokeBorder(Tema.lineaFuerte))
                .padding(5)
                .transition(.scale.combined(with: .opacity))
            }
        }
        .help(editando ? "Muévelo o quítalo" : (on ? "Pulsa para apagar" : "Pulsa para encender"))
        .accessibilityLabel("\(estado.nombre), \(on ? "encendido" : "apagado")")
    }
}

/// Una función activa, en lima si está encendida y en gris si está configurada pero apagada
struct InsigniaFuncion: View {
    let funcion: FuncionActiva
    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: funcion.icono).frame(width: 18).foregroundStyle(Tema.suave)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(funcion.nombre).font(Tema.sans(13, .medium))
                    PuntoVivo(color: funcion.encendida ? Tema.vivo : Color.white.opacity(0.3), late: funcion.encendida)
                    if !funcion.encendida { Text("apagado").font(Tema.sans(12)).foregroundStyle(Tema.suave) }
                }
                if !funcion.detalle.isEmpty {
                    Text(funcion.detalle).font(Tema.sans(12)).foregroundStyle(Tema.suave).lineLimit(2)
                }
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(Rectangle().strokeBorder(Tema.linea))
    }
}

struct Aviso: View {
    let icono: String, texto: String
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icono).font(.system(size: 14)).foregroundStyle(.white)
            Text(texto).fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(Rectangle().strokeBorder(Tema.linea))
        .overlay(alignment: .leading) { Rectangle().fill(.white).frame(width: 2) }
    }
}

// MARK: - Sticks

struct Sticks: View {
    @EnvironmentObject var almacen: Almacen
    @EnvironmentObject var motor: Motor
    var body: some View {
        Toggle("Intercambiar sticks (el izquierdo hace de derecho y al revés)", isOn: $almacen.activo.intercambiarSticks)
        HStack(alignment: .top, spacing: 16) {
            AjusteStickVista(titulo: "Stick izquierdo (moverse)", ajuste: $almacen.activo.izq,
                             entrada: (motor.entrada.lx, motor.entrada.ly), salida: (motor.salida.lx, motor.salida.ly))
            AjusteStickVista(titulo: "Stick derecho (apuntar)", ajuste: $almacen.activo.der,
                             entrada: (motor.entrada.rx, motor.entrada.ry), salida: (motor.salida.rx, motor.salida.ry))
        }
    }
}

struct AjusteStickVista: View {
    let titulo: String
    @Binding var ajuste: AjusteStick
    let entrada: (UInt8, UInt8), salida: (UInt8, UInt8)

    var body: some View {
        Tarjeta(titulo: titulo) {
            HStack(spacing: 16) {
                VStack { StickDibujo(x: entrada.0, y: entrada.1, tam: 70); Text("Tu mando").font(Tema.sans(12)) }
                VStack { StickDibujo(x: salida.0, y: salida.1, tam: 70); Text("Consola").font(Tema.sans(12)) }
                Curva(ajuste: ajuste).frame(width: 110, height: 70)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("Curvas listas").etiqueta()
                HStack(spacing: 6) {
                    Button("Lineal") { ajuste.curva = 1; ajuste.antiZonaMuerta = 0 }
                    Button("Precisión") { ajuste.curva = 1.8; ajuste.antiZonaMuerta = 0 }
                    Button("Rápida") { ajuste.curva = 0.7; ajuste.antiZonaMuerta = 0 }
                    Button("Inmediata") { ajuste.curva = 1.2; ajuste.antiZonaMuerta = 12 }
                }
            }
            Deslizador(titulo: "Zona muerta", valor: $ajuste.zonaMuerta, rango: 0...40,
                       ayuda: "Lo poco que se mueve sin hacer nada. Súbela si el personaje se mueve solo.")
            Picker("Forma de la zona muerta", selection: $ajuste.formaCruz) {
                Text("Redonda (natural)").tag(false)
                Text("En cruz (ejes rectos, más fácil ir recto)").tag(true)
            }
            Deslizador(titulo: "Zona externa", valor: $ajuste.zonaExterna, rango: 50...100,
                       ayuda: "A partir de aquí ya cuenta como stick a tope.")
            Deslizador(titulo: "Anti zona muerta", valor: $ajuste.antiZonaMuerta, rango: 0...40,
                       ayuda: "Salta la zona muerta del propio juego para que responda al primer roce.")
            Deslizador(titulo: "Curva", valor: $ajuste.curva, rango: 0.3...3, paso: 0.05, unidad: "", decimales: 2,
                       ayuda: "1 = lineal. Más de 1: más fino en el centro (apuntar con precisión). Menos de 1: más brusco.")
            Deslizador(titulo: "Sensibilidad horizontal", valor: $ajuste.sensX, rango: 0...200)
            Deslizador(titulo: "Sensibilidad vertical", valor: $ajuste.sensY, rango: 0...200)
            Deslizador(titulo: "Límite", valor: $ajuste.limite, rango: 20...100,
                       ayuda: "Lo más lejos que llega el stick a la consola. Bájalo para no pasarte de largo.")
            Deslizador(titulo: "Suavizado", valor: $ajuste.suavizado, rango: 0...100,
                       ayuda: "Quita tirones y temblores. Mucho suavizado se nota como retraso.")
            Deslizador(titulo: "Aceleración", valor: $ajuste.aceleracion, rango: 0...100,
                       ayuda: "Con el stick casi a tope, la sensibilidad sube poco a poco (para girar rápido).")
            Deslizador(titulo: "Tiempo de aceleración", valor: $ajuste.tiempoAceleracion, rango: 50...1500, paso: 50, unidad: "ms",
                       ayuda: "Lo que tarda en llegar a la aceleración máxima.")
            HStack {
                Toggle("Invertir horizontal", isOn: $ajuste.invertirX)
                Toggle("Invertir vertical", isOn: $ajuste.invertirY)
            }
            Button("Valores de fábrica") { ajuste = AjusteStick() }
        }
    }
}

struct Curva: View {
    let ajuste: AjusteStick
    var body: some View {
        Canvas { ctx, tam in
            var ejes = Path()
            ejes.move(to: CGPoint(x: 0, y: tam.height)); ejes.addLine(to: CGPoint(x: tam.width, y: tam.height))
            ejes.move(to: CGPoint(x: 0, y: 0)); ejes.addLine(to: CGPoint(x: 0, y: tam.height))
            ctx.stroke(ejes, with: .color(.secondary.opacity(0.5)))
            var linea = Path()
            for i in 0...60 {
                let v = Double(i) / 60
                let p = CGPoint(x: v * tam.width, y: tam.height * (1 - Procesador.curva(v, ajuste)))
                i == 0 ? linea.move(to: p) : linea.addLine(to: p)
            }
            ctx.stroke(linea, with: .color(Tema.vivo), lineWidth: 2)
        }
        .overlay(alignment: .topLeading) { Text("respuesta").font(Tema.mono(9)).foregroundStyle(Tema.suave).padding(.leading, 4) }
    }
}

// MARK: - Gatillos

struct Gatillos: View {
    @EnvironmentObject var almacen: Almacen
    @EnvironmentObject var motor: Motor
    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            AjusteGatilloVista(titulo: "L2 (apuntar)", ajuste: $almacen.activo.l2, entrada: motor.entrada.l2, salida: motor.salida.l2)
            AjusteGatilloVista(titulo: "R2 (disparar)", ajuste: $almacen.activo.r2, entrada: motor.entrada.r2, salida: motor.salida.r2)
        }
    }
}

struct AjusteGatilloVista: View {
    let titulo: String
    @Binding var ajuste: AjusteGatillo
    let entrada: UInt8, salida: UInt8
    var body: some View {
        Tarjeta(titulo: titulo) {
            HStack(spacing: 20) { Barra(titulo: "Tu mando", valor: entrada); Barra(titulo: "Consola", valor: salida) }
            Deslizador(titulo: "Zona muerta", valor: $ajuste.zonaMuerta, rango: 0...60,
                       ayuda: "Recorrido inicial que no cuenta.")
            Deslizador(titulo: "Zona externa", valor: $ajuste.zonaExterna, rango: 40...100,
                       ayuda: "A partir de aquí cuenta como pulsado a fondo (no hace falta apretar del todo).")
            Deslizador(titulo: "Curva", valor: $ajuste.curva, rango: 0.3...3, paso: 0.05, unidad: "", decimales: 2,
                       ayuda: "1 = lineal. Menos de 1: llega antes a fondo. Más de 1: más control al principio.")
            Button("Valores de fábrica") { ajuste = AjusteGatillo() }
            Toggle("Disparo rápido (al rozarlo cuenta como pulsado a fondo)", isOn: $ajuste.disparoRapido)
        }
    }
}

// MARK: - Reasignar botones

struct Reasignar: View {
    @EnvironmentObject var almacen: Almacen
    @EnvironmentObject var motor: Motor
    var body: some View {
        Text("Elige qué recibe la consola al pulsar cada botón de tu mando.").foregroundStyle(Tema.suave)
        Tarjeta(titulo: "Botones") {
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
                ForEach(Boton.allCases) { b in
                    GridRow {
                        Circle().fill(motor.entrada.pulsado(b) ? Tema.vivo : Color.secondary.opacity(0.2))
                            .frame(width: 10, height: 10)
                        Text(b.nombre).frame(width: 150, alignment: .leading)
                        Image(systemName: "arrow.right").foregroundStyle(Tema.suave)
                        Picker("", selection: destino(b)) {
                            ForEach(Boton.salidas) { Text($0.nombre).tag($0.rawValue) }
                            Divider()
                            Text("Nada (anulado)").tag("nada")
                        }
                        .labelsHidden()
                        .frame(width: 190)
                        Toggle("Alternar", isOn: alternar(b))
                            .help("Pulsar una vez = mantenido; otra vez = suelto (por ejemplo, agacharse)")
                        Picker("", selection: larga(b)) {
                            Text("Sin pulsación larga").tag("")
                            Divider()
                            ForEach(Boton.salidas) { Text("Larga: \($0.nombre)").tag($0.rawValue) }
                            Text("Larga: nada").tag("nada")
                        }
                        .labelsHidden()
                        .frame(width: 200)
                    }
                }
            }
            Deslizador(titulo: "Cuánto hay que mantener para la pulsación larga", valor: $almacen.activo.msLarga,
                       rango: 150...1000, paso: 25, unidad: "ms",
                       ayuda: "Con pulsación larga, la corta se envía al soltar el botón (un pelín más tarde).")
            Button("Dejar todos como vienen") {
                almacen.activo.reasignar = [:]
                almacen.activo.alternar = []
                almacen.activo.pulsacionLarga = [:]
            }
        }
    }

    private func alternar(_ b: Boton) -> Binding<Bool> {
        Binding(
            get: { almacen.activo.alternar.contains(b) },
            set: { on in
                almacen.activo.alternar.removeAll { $0 == b }
                if on { almacen.activo.alternar.append(b) }
            })
    }

    private func larga(_ b: Boton) -> Binding<String> {
        Binding(
            get: { almacen.activo.pulsacionLarga[b.rawValue] ?? "" },
            set: { almacen.activo.pulsacionLarga[b.rawValue] = $0.isEmpty ? nil : $0 })
    }

    private func destino(_ b: Boton) -> Binding<String> {
        Binding(
            get: { almacen.activo.reasignar[b.rawValue] ?? (b.llegaALaConsola ? b.rawValue : "nada") },
            set: { nuevo in
                if nuevo == b.rawValue || (!b.llegaALaConsola && nuevo == "nada") { almacen.activo.reasignar[b.rawValue] = nil }
                else { almacen.activo.reasignar[b.rawValue] = nuevo }
            })
    }
}

// MARK: - Turbo

struct Turbos: View {
    @EnvironmentObject var almacen: Almacen
    var body: some View {
        Text("Mientras mantienes el botón, la consola lo recibe pulsándose y soltándose solo.").foregroundStyle(Tema.suave)
        ForEach($almacen.activo.turbos) { $tb in
            Tarjeta(titulo: "Turbo en \(tb.boton.nombre)") {
                Toggle("Encendido", isOn: $tb.activo)
                Picker("Botón", selection: $tb.boton) {
                    ForEach(Boton.salidas) { Text($0.nombre).tag($0) }
                }
                .frame(width: 260)
                Deslizador(titulo: "Velocidad", valor: $tb.hz, rango: 2...30, unidad: "pulsaciones/s")
                Deslizador(titulo: "Tiempo apretado en cada pulsación", valor: $tb.ciclo, rango: 10...90,
                           ayuda: "Si el juego no pilla alguna pulsación, súbelo o baja la velocidad.")
                Button(role: .destructive) {
                    almacen.activo.turbos.removeAll { $0.id == tb.id }
                } label: { Label("Quitar", systemImage: "trash") }
            }
        }
        Button { almacen.activo.turbos.append(Turbo()) } label: { Label("Añadir turbo", systemImage: "plus") }
    }
}

// MARK: - Macros

struct Macros: View {
    @EnvironmentObject var almacen: Almacen
    var body: some View {
        Text("Una macro pulsa una secuencia de botones al pulsar su disparador. Cada paso dice qué botones se pulsan y durante cuánto tiempo.")
            .foregroundStyle(Tema.suave)
        ForEach($almacen.activo.macros) { $m in
            Tarjeta(titulo: m.nombre) {
                HStack {
                    TextField("Nombre", text: $m.nombre).campo().frame(width: 220)
                    Toggle("Activa", isOn: $m.activa)
                }
                HStack(spacing: 20) {
                    Picker("Se dispara con", selection: $m.disparador) {
                        ForEach(Boton.allCases) { Text($0.nombre).tag($0) }
                    }
                    .frame(width: 260)
                    Toggle("Repetir mientras lo mantengo", isOn: $m.repetir)
                    Toggle("El disparador no llega a la consola", isOn: $m.bloquearDisparador)
                }
                HStack(spacing: 12) {
                    Toggle("Activarla y desactivarla con el mando:", isOn: $m.atajo)
                    Group {
                        Picker("mantén", selection: $m.atajoMantener) {
                            ForEach(Boton.allCases) { Text($0.nombre).tag($0) }
                        }
                        .frame(width: 200)
                        Picker("y pulsa", selection: $m.atajoPulsar) {
                            ForEach(Boton.allCases) { Text($0.nombre).tag($0) }
                        }
                        .frame(width: 200)
                    }
                    .disabled(!m.atajo)
                }
                if m.atajo {
                    Text("Con la voz encendida el Mac dice «\(m.nombre) activada» o «desactivada». Esos botones también llegan a la consola: elige una combinación que no uses en el juego.")
                        .font(Tema.sans(12)).foregroundStyle(Tema.suave)
                }
                ForEach(Array($m.pasos.enumerated()), id: \.element.id) { i, $paso in
                    HStack {
                        Text("Paso \(i + 1)").frame(width: 56, alignment: .leading).foregroundStyle(Tema.suave)
                        Menu(paso.botones.isEmpty ? "Ningún botón (espera)" : paso.botones.map(\.corto).joined(separator: " + ")) {
                            ForEach(Boton.salidas) { b in
                                Toggle(b.nombre, isOn: Binding(
                                    get: { paso.botones.contains(b) },
                                    set: { on in
                                        if on { paso.botones.append(b) } else { paso.botones.removeAll { $0 == b } }
                                    }))
                            }
                        }
                        .frame(width: 220)
                        Stepper("\(paso.ms) ms", value: $paso.ms, in: 10...3000, step: 10).frame(width: 140)
                        Button { m.pasos.removeAll { $0.id == paso.id } } label: { Image(systemName: "minus.circle") }
                            .buttonStyle(.borderless)
                    }
                }
                HStack {
                    Button { m.pasos.append(PasoMacro()) } label: { Label("Añadir paso", systemImage: "plus") }
                    Spacer()
                    Button(role: .destructive) {
                        almacen.activo.macros.removeAll { $0.id == m.id }
                    } label: { Label("Borrar macro", systemImage: "trash") }
                }
            }
        }
        HStack {
            Button { almacen.activo.macros.append(Macro()) } label: { Label("Añadir macro", systemImage: "plus") }
            Button { almacen.activo.macros.append(preparada(dropshot: true)) } label: { Label("Añadir dropshot", systemImage: "arrow.down.to.line") }
                .help("Al disparar, se tumba solo (mantiene ○)")
            Button { almacen.activo.macros.append(preparada(dropshot: false)) } label: { Label("Añadir jumpshot", systemImage: "arrow.up.to.line") }
                .help("Al disparar, salta solo (pulsa ✕)")
        }
        Text("Dropshot y jumpshot se disparan con tu botón de disparar (el de Anti-recoil) y no lo bloquean, así que sigues disparando. En BO2 mantener ○ te tumba y ✕ salta; si los tienes cambiados en el juego, cambia el botón del paso. Solo para modos sin conexión.")
            .font(Tema.sans(12)).foregroundStyle(Tema.suave)
    }

    /// Macro lista para usar. Se dispara con el botón físico que dispara en el juego.
    private func preparada(dropshot: Bool) -> Macro {
        let p = almacen.activo
        let disparo = p.antiRecoil.disparar
        let fisico = Boton.allCases.first { p.destino(de: $0) == disparo } ?? disparo
        var m = Macro()
        m.disparador = fisico
        m.bloquearDisparador = false
        if dropshot {
            m.nombre = "Dropshot"
            m.pasos = [PasoMacro(botones: [.circulo], ms: 600)]   // mantener ○ = tumbarse
        } else {
            m.nombre = "Jumpshot"
            m.pasos = [PasoMacro(botones: [.x], ms: 100)]         // ✕ = saltar
        }
        return m
    }
}

// MARK: - Anti-recoil

struct AntiRecoilVista: View {
    @EnvironmentObject var almacen: Almacen
    @EnvironmentObject var motor: Motor
    var body: some View {
        Aviso(icono: "exclamationmark.triangle",
              texto: "Solo para modos sin conexión (campaña, zombis, partidas contra bots). En partidas online es hacer trampas y el anti-trampas de Call of Duty lo detecta.")
        Tarjeta(titulo: "Compensar el retroceso") {
            HStack {
                Toggle("Activado en este perfil", isOn: $almacen.activo.antiRecoil.activo)
                Spacer()
                Label(motor.antiRecoilEncendido ? "Encendido ahora" : "Apagado ahora", systemImage: "circle.fill")
                    .foregroundStyle(motor.antiRecoilEncendido ? Tema.vivo : Tema.suave)
            }
            Deslizador(titulo: "Fuerza hacia abajo", valor: $almacen.activo.antiRecoil.vertical, rango: 0...100,
                       ayuda: "Cuánto baja el stick derecho mientras disparas. Empieza bajo y súbelo poco a poco.")
            Toggle("La fuerza cambia mientras disparas", isOn: $almacen.activo.antiRecoil.progresivo)
            if almacen.activo.antiRecoil.progresivo {
                Deslizador(titulo: "Fuerza al final", valor: $almacen.activo.antiRecoil.verticalFinal, rango: 0...100,
                           ayuda: "La fuerza pasa de «Fuerza hacia abajo» a esta. Muchas armas suben mucho al principio y luego menos.")
                Deslizador(titulo: "Tiempo del cambio", valor: $almacen.activo.antiRecoil.transicionMs, rango: 100...3000, paso: 50, unidad: "ms")
            }
            Deslizador(titulo: "Corrección lateral", valor: $almacen.activo.antiRecoil.horizontal, rango: -50...50,
                       ayuda: "Negativo = hacia la izquierda, positivo = hacia la derecha.")
            Deslizador(titulo: "Retardo", valor: $almacen.activo.antiRecoil.retardoMs, rango: 0...500, paso: 10, unidad: "ms",
                       ayuda: "Espera desde que empiezas a disparar hasta que empieza a compensar.")
            Text("Botones tal como los recibe la consola (después de reasignar). Si en el juego apuntas con L1 y disparas con R1, elige L1 y R1.")
                .font(Tema.sans(12)).foregroundStyle(Tema.suave)
            HStack(spacing: 20) {
                Picker("Disparar con", selection: $almacen.activo.antiRecoil.disparar) {
                    ForEach(Boton.allCases) { Text($0.nombre).tag($0) }
                }
                .frame(width: 240)
                Picker("Apuntar con", selection: $almacen.activo.antiRecoil.apuntar) {
                    ForEach(Boton.allCases) { Text($0.nombre).tag($0) }
                }
                .frame(width: 240)
            }
            Picker("Compensa cuando", selection: $almacen.activo.antiRecoil.soloApuntando) {
                Text("apunto y disparo a la vez").tag(true)
                Text("disparo, aunque no apunte").tag(false)
            }
            .pickerStyle(.radioGroup)
            Text("Solo apuntar no hace nada: siempre hace falta disparar.")
                .font(Tema.sans(12)).foregroundStyle(Tema.suave)
            Toggle("Encender y apagar con una combinación (suena un aviso y la barra de luz destella verde al encender y roja al apagar)",
                   isOn: $almacen.activo.antiRecoil.atajo)
            HStack(spacing: 12) {
                Picker("Mantén", selection: $almacen.activo.antiRecoil.atajoMantener) {
                    ForEach(Boton.allCases) { Text($0.nombre).tag($0) }
                }
                .frame(width: 220)
                Picker("y pulsa", selection: $almacen.activo.antiRecoil.atajoPulsar) {
                    ForEach(Boton.allCases) { Text($0.nombre).tag($0) }
                }
                .frame(width: 220)
            }
            .disabled(!almacen.activo.antiRecoil.atajo)
            Text("Botones de tu mando. Si eliges el mismo en los dos, basta con pulsarlo.")
                .font(Tema.sans(12)).foregroundStyle(Tema.suave)
        }
    }
}

// MARK: - Mi control (medidor)

struct MiControlVista: View {
    @EnvironmentObject var almacen: Almacen
    @EnvironmentObject var medidor: MedidorControl
    @State private var preguntarBorrar = false

    private func f(_ v: Double) -> String { String(format: "%.1f", v) }

    var body: some View {
        Text("Graba lo que hace tu mano con el stick derecho mientras disparas (la entrada de tu DualSense, antes de que la app aplique nada) y te enseña cómo lo haces, para practicar y ver si mejoras. Solo mide: no cambia nada de lo que llega a la consola ni crea ninguna configuración.")
            .foregroundStyle(Tema.suave)
        Tarjeta(titulo: "Medir") {
            Toggle("Medir mis ráfagas", isOn: $almacen.generales.medidor.activo)
            HStack(spacing: 20) {
                Picker("Disparo con", selection: $almacen.generales.medidor.disparar) {
                    ForEach(Boton.allCases) { Text($0.nombre).tag($0) }
                }
                .frame(width: 240)
                Picker("Apunto con", selection: $almacen.generales.medidor.apuntar) {
                    ForEach(Boton.allCases) { Text($0.nombre).tag($0) }
                }
                .frame(width: 240)
            }
            Toggle("Contar solo las ráfagas en las que también apunto", isOn: $almacen.generales.medidor.soloApuntando)
            Text("Botones de tu mando. Una ráfaga empieza al pulsar el de disparar y acaba al soltarlo; las de menos de 150 ms no cuentan.")
                .font(Tema.sans(12)).foregroundStyle(Tema.suave)
        }
        if let ultima = medidor.rafagas.last {
            Tarjeta(titulo: "Última ráfaga") {
                ResumenRafagaVista(r: ultima)
                if !medidor.ultimaX.isEmpty {
                    GraficoAyuda(x: medidor.ultimaX, y: medidor.ultimaAbajo.map { -$0 }, amplitud: [])
                    Text("Lima: lateral · blanco: vertical (hacia abajo es negativo). Tu stick durante la ráfaga.")
                        .font(Tema.sans(12)).foregroundStyle(Tema.suave)
                }
            }
            let ultimas = Array(medidor.rafagas.suffix(20))
            Tarjeta(titulo: "Últimas \(ultimas.count) ráfagas") {
                MediaRafagasVista(m: AnalisisRafaga.media(ultimas))
                ForEach(AnalisisRafaga.observaciones(ultimas), id: \.self) { Label($0, systemImage: "lightbulb").font(Tema.sans(13)) }
                Text("Las observaciones usan umbrales orientativos, no una norma.").font(Tema.sans(12)).foregroundStyle(Tema.suave)
            }
            Tarjeta(titulo: "Por días") {
                Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 4) {
                    GridRow { Text("Día"); Text("Ráfagas"); Text("Reacción"); Text("Bajada"); Text("Constancia"); Text("Lateral"); Text("Tirones") }
                        .foregroundStyle(Tema.suave)
                    ForEach(medidor.porDia.prefix(14), id: \.dia) { d in
                        GridRow {
                            Text(d.dia.formatted(date: .abbreviated, time: .omitted))
                            Text("\(d.media.rafagas)")
                            Text(d.media.reaccionMs.map { "\(Int($0)) ms" } ?? "—")
                            Text("\(f(d.media.bajada)) %"); Text("\(f(d.media.constancia)) %")
                            Text("\(f(d.media.lateralMedio)) %"); Text(f(d.media.tirones))
                        }
                    }
                }
                .font(Tema.mono(12))
                Button("Borrar el historial…", role: .destructive) { preguntarBorrar = true }
                    .confirmationDialog("¿Borrar las \(medidor.rafagas.count) ráfagas guardadas?", isPresented: $preguntarBorrar) {
                        Button("Borrar", role: .destructive) { medidor.borrarTodo() }
                    }
            }
        } else {
            Text(almacen.generales.medidor.activo ? "Todavía no hay ráfagas. Dispara un rato (en el juego o con la app abierta) y aparecerán aquí."
                                                  : "Activa «Medir mis ráfagas» para empezar.")
                .foregroundStyle(Tema.suave)
        }
    }
}

struct ResumenRafagaVista: View {
    let r: ResumenRafaga
    private func f(_ v: Double) -> String { String(format: "%.1f", v) }
    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 4) {
            GridRow { Text("Duración"); Text("\(Int(r.duracionMs)) ms"); Text("Reacción"); Text(r.reaccionMs.map { "\(Int($0)) ms" } ?? "no bajaste el stick") }
            GridRow { Text("Bajada media"); Text("\(f(r.bajadaMedia)) %"); Text("Constancia"); Text("±\(f(r.constancia)) %") }
            GridRow { Text("Desvío lateral"); Text("\(f(r.lateralMedio)) % (máx. \(f(r.lateralMax)) %)"); Text("Temblor / tirones"); Text("\(f(r.temblor)) · \(r.tirones)") }
            GridRow { Text("Perfil"); Text(r.perfil.isEmpty ? "—" : r.perfil); Text("Cuándo"); Text(r.fecha.formatted(date: .omitted, time: .standard)) }
        }
        .font(Tema.mono(12))
    }
}

struct MediaRafagasVista: View {
    let m: AnalisisRafaga.Media
    private func f(_ v: Double) -> String { String(format: "%.1f", v) }
    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 4) {
            GridRow { Text("Reacción media"); Text(m.reaccionMs.map { "\(Int($0)) ms" } ?? "—"); Text("Sin bajar el stick"); Text("\(Int((m.sinCorregir * 100).rounded())) %") }
            GridRow { Text("Bajada media"); Text("\(f(m.bajada)) %"); Text("Constancia media"); Text("±\(f(m.constancia)) %") }
            GridRow { Text("Desvío lateral medio"); Text("\(f(m.lateralMedio)) %"); Text("Temblor / tirones"); Text("\(f(m.temblor)) · \(f(m.tirones))") }
        }
        .font(Tema.mono(12))
    }
}

// MARK: - Ver desde el móvil

struct MovilVista: View {
    @EnvironmentObject var almacen: Almacen
    @EnvironmentObject var servidor: Servidor

    var body: some View {
        Text("Abre esta dirección en el móvil (con la misma wifi que el Mac) para ver lo mismo que en «En vivo» y cambiar los mismos ajustes que aquí, aunque la pantalla esté en la PS5. No sale a internet.")
            .foregroundStyle(Tema.suave)
        Tarjeta(titulo: "Servidor para el móvil") {
            Toggle("Activado", isOn: $almacen.generales.servidorMovil)
                .onChange(of: almacen.generales.servidorMovil) { activo in
                    if activo { servidor.arrancar() } else { servidor.parar() }
                }
            if let error = servidor.error {
                Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(Tema.fallo)
            }
            if servidor.activo {
                let direcciones = Servidor.direcciones(puerto: servidor.puerto, clave: almacen.generales.clave)
                if let primera = direcciones.first, let qr = Servidor.codigoQR(primera) {
                    HStack(alignment: .top, spacing: 20) {
                        Image(nsImage: qr).interpolation(.none).resizable().frame(width: 170, height: 170)
                            .background(Color.white)
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Escanea el código con la cámara del móvil, o abre:").font(Tema.sans(13))
                            ForEach(direcciones, id: \.self) { d in
                                Text(d).font(Tema.mono(12)).textSelection(.enabled)
                            }
                            Label("\(servidor.clientes) móvil\(servidor.clientes == 1 ? "" : "es") conectado\(servidor.clientes == 1 ? "" : "s") ahora",
                                  systemImage: "iphone")
                                .foregroundStyle(servidor.clientes > 0 ? Tema.vivo : Tema.suave)
                        }
                    }
                } else {
                    Text("No encuentro la dirección del Mac en la red. ¿Está conectado a la wifi?").foregroundStyle(Tema.suave)
                }
            } else if almacen.generales.servidorMovil && servidor.error == nil {
                Text("Arrancando…").foregroundStyle(Tema.suave)
            }
            Divider()
            HStack {
                Text("Clave: ").foregroundStyle(Tema.suave)
                Text(almacen.generales.clave).font(Tema.mono(14, .regular)).textSelection(.enabled)
                Spacer()
                Button("Cambiar clave") {
                    almacen.generales.clave = AjustesGenerales.nuevaClave()
                    servidor.cerrarClientes()
                }
                .help("Desconecta los móviles. Hay que volver a abrir la dirección o escanear el código")
            }
            Text("La clave ya va dentro de la dirección y del código QR: el móvil la guarda la primera vez y no hay que escribirla. Sin ella no se puede ni mirar ni cambiar nada. Si cambias la clave, vuelve a abrir la dirección nueva.")
                .font(Tema.sans(12)).foregroundStyle(Tema.suave)
            Text("La primera vez, macOS puede preguntar si la app acepta conexiones entrantes: di que sí. El móvil y el Mac tienen que estar en la misma wifi.")
                .font(Tema.sans(12)).foregroundStyle(Tema.suave)
        }
    }
}

// MARK: - Ajustar desde el mando

struct AjusteMandoVista: View {
    @EnvironmentObject var almacen: Almacen
    var body: some View {
        Tarjeta(titulo: "Ajustar desde el mando") {
            Toggle("Activado", isOn: $almacen.generales.ajusteMando)
            Picker("Mantén", selection: $almacen.generales.ajusteMantener) {
                ForEach(Boton.allCases) { Text($0.nombre).tag($0) }
            }
            .frame(width: 240)
            .disabled(!almacen.generales.ajusteMando)
            Text("Con ese botón mantenido: ← y → eligen qué ajustar, y ↑ y ↓ lo suben o bajan. El Mac dice el nombre y el valor en voz alta. Los cambios se guardan en el perfil.")
                .font(Tema.sans(12)).foregroundStyle(Tema.suave)
            Text("Se puede ajustar: " + AjusteRapido.lista.map(\.nombre).joined(separator: ", ") + ".")
                .font(Tema.sans(12)).foregroundStyle(Tema.suave)
            Text("Ojo: elige un botón distinto al de cambiar de perfil, y que no uses en el juego (el botón mantenido y la cruceta también llegan a la consola).")
                .font(Tema.sans(12)).foregroundStyle(Tema.suave)
        }
        Tarjeta(titulo: "Anti-recoil desde el mando") {
            Toggle("Activado", isOn: $almacen.generales.fuerzaMando)
            Picker("Mantén", selection: $almacen.generales.fuerzaMantener) {
                ForEach(Boton.allCases) { Text($0.nombre).tag($0) }
            }
            .frame(width: 240)
            .disabled(!almacen.generales.fuerzaMando)
            Text("Con ese botón mantenido: ↑ sube y ↓ baja la fuerza (de 0 a 100), y → y ← mueven la corrección lateral a la derecha o a la izquierda (de −50 a 50), de \(Int(Almacen.pasoFuerza)) en \(Int(Almacen.pasoFuerza)). Se avisa del valor y se guarda en el perfil. Mientras lo mantienes, la cruceta no llega a la consola.")
                .font(Tema.sans(12)).foregroundStyle(Tema.suave)
            Text("El botón de silenciar el micro no llega a la PS5 (salvo que lo hayas cambiado a otro botón), así que no estorba en el juego.")
                .font(Tema.sans(12)).foregroundStyle(Tema.suave)
        }
    }
}

// MARK: - Ayuda al apuntado

struct AyudaApuntadoVista: View {
    @EnvironmentObject var almacen: Almacen
    @EnvironmentObject var motor: Motor

    /// Si el usuario ha activado los límites, los deslizadores solo llegan hasta ellos
    private func rango(_ normal: ClosedRange<Double>, _ mn: Double, _ mx: Double) -> ClosedRange<Double> {
        let l = almacen.activo.ayuda.limites
        guard l.activos else { return normal }
        let a = min(mn, mx), b = max(mn, mx)
        return a...max(b, a + 0.001)
    }

    private func poner(tamano: Double, hz: Double, entrada: Double, ceder: Double) {
        almacen.activo.ayuda.tamano = tamano
        almacen.activo.ayuda.hz = hz
        almacen.activo.ayuda.entradaMs = entrada
        almacen.activo.ayuda.ceder = ceder
    }
    var body: some View {
        Aviso(icono: "exclamationmark.triangle",
              texto: "Solo para modos sin conexión (campaña, zombis, partidas contra bots). En partidas online es hacer trampas y el anti-trampas de Call of Duty lo detecta.")
        Text("No ve la pantalla: mientras apuntas, mueve el stick derecho en círculos o temblores diminutos para que la ayuda al apuntado del propio juego esté siempre enganchada.")
            .foregroundStyle(Tema.suave)
        Tarjeta(titulo: "Ayuda al apuntado") {
            HStack {
                Toggle("Activada en este perfil", isOn: $almacen.activo.ayuda.activo)
                Spacer()
                Label(motor.ayudaEncendida ? "Encendida ahora" : "Apagada ahora", systemImage: "circle.fill")
                    .foregroundStyle(motor.ayudaEncendida ? Tema.vivo : Tema.suave)
            }
            HStack {
                Text("Intensidad lista:").foregroundStyle(Tema.suave)
                Button("Discreta") { poner(tamano: 4, hz: 8, entrada: 300, ceder: 85) }
                Button("Media") { poner(tamano: 8, hz: 12, entrada: 150, ceder: 70) }
                Button("Fuerte") { poner(tamano: 14, hz: 16, entrada: 80, ceder: 50) }
            }
            .controlSize(.small)
            VStack(alignment: .leading, spacing: 6) {
                Text("Patrones listos").etiqueta()
                HStack(spacing: 6) {
                    ForEach(Array(AyudaApuntado.patrones.enumerated()).prefix(3), id: \.offset) { i, p in
                        Button(p.nombre) { almacen.activo.ayuda.aplicarPatron(i) }
                            .buttonStyle(BotonCaja(elegido: almacen.activo.ayuda.indicePatron == i))
                    }
                }
                HStack(spacing: 6) {
                    ForEach(Array(AyudaApuntado.patrones.enumerated()).dropFirst(3), id: \.offset) { i, p in
                        Button(p.nombre) { almacen.activo.ayuda.aplicarPatron(i) }
                            .buttonStyle(BotonCaja(elegido: almacen.activo.ayuda.indicePatron == i))
                    }
                }
            }
            Picker("Movimiento", selection: $almacen.activo.ayuda.forma) {
                Text("Círculos").tag(AyudaApuntado.Forma.circulo)
                Text("Temblor lateral").tag(AyudaApuntado.Forma.temblor)
            }
            .pickerStyle(.segmented)
            .frame(width: 300)
            Deslizador(titulo: "Tamaño", valor: $almacen.activo.ayuda.tamano, rango: rango(1...30, almacen.activo.ayuda.limites.tamanoMin, almacen.activo.ayuda.limites.tamanoMax),
                       ayuda: "Cuánto se mueve la mira. Empieza pequeño: si se nota bailar la mira, bájalo.")
            Deslizador(titulo: "Velocidad", valor: $almacen.activo.ayuda.hz, rango: rango(2...40, almacen.activo.ayuda.limites.hzMin, almacen.activo.ayuda.limites.hzMax), unidad: "por segundo")
            Deslizador(titulo: "Entrada suave", valor: $almacen.activo.ayuda.entradaMs, rango: rango(0...600, almacen.activo.ayuda.limites.entradaMin, almacen.activo.ayuda.limites.entradaMax), paso: 10, unidad: "ms",
                       ayuda: "Al empezar a apuntar, tarda esto en llegar a toda la fuerza. Evita el tirón inicial.")
            Deslizador(titulo: "Ceder cuando apunto yo", valor: $almacen.activo.ayuda.ceder, rango: 0...100,
                       ayuda: "Cuánto se reduce mientras mueves tú el stick derecho, para que no pelee con tu mano.")
            HStack(spacing: 20) {
                Picker("Se activa al apuntar con", selection: $almacen.activo.ayuda.boton) {
                    ForEach(Boton.allCases) { Text($0.nombre).tag($0) }
                }
                .frame(width: 300)
                Toggle("y solo mientras disparo", isOn: $almacen.activo.ayuda.tambienDisparando)
                    .help("Usa el botón de disparar de Anti-recoil")
            }
            Text("Botón tal como lo recibe la consola (después de reasignar).").font(Tema.sans(12)).foregroundStyle(Tema.suave)
            Toggle("Encender y apagar con una combinación (suena un aviso y la luz destella cian al encender y naranja al apagar)",
                   isOn: $almacen.activo.ayuda.atajo)
            HStack(spacing: 12) {
                Picker("Mantén", selection: $almacen.activo.ayuda.atajoMantener) {
                    ForEach(Boton.allCases) { Text($0.nombre).tag($0) }
                }
                .frame(width: 220)
                Picker("y pulsa", selection: $almacen.activo.ayuda.atajoPulsar) {
                    ForEach(Boton.allCases) { Text($0.nombre).tag($0) }
                }
                .frame(width: 220)
            }
            .disabled(!almacen.activo.ayuda.atajo)
            Divider()
            Toggle("Cambiar de patrón con una combinación (el Mac dice el nombre en voz alta)", isOn: $almacen.activo.ayuda.cambioActivo)
            HStack(spacing: 12) {
                Picker("Mantén", selection: $almacen.activo.ayuda.cambioMantener) {
                    ForEach(Boton.allCases) { Text($0.nombre).tag($0) }
                }
                .frame(width: 200)
                Picker("y pulsa (siguiente)", selection: $almacen.activo.ayuda.cambioSiguiente) {
                    ForEach(Boton.allCases) { Text($0.nombre).tag($0) }
                }
                .frame(width: 240)
                Picker("(anterior)", selection: $almacen.activo.ayuda.cambioAnterior) {
                    ForEach(Boton.allCases) { Text($0.nombre).tag($0) }
                }
                .frame(width: 190)
            }
            .disabled(!almacen.activo.ayuda.cambioActivo)
            Text("Pasa por los seis patrones de la lista y luego por tus variantes, de uno en uno, solo cuando pulsas la combinación. Botones de tu mando.")
                .font(Tema.sans(12)).foregroundStyle(Tema.suave)
        }
        LimitesAyudaVista()
        VariantesAyudaVista()
        DiagnosticoAyudaVista()
        MonitorSenalesVista()
    }
}

// MARK: - Límites, variantes y diagnóstico de la ayuda al apuntado

struct ParLimites: View {
    let titulo: String, unidad: String
    @Binding var minimo: Double
    @Binding var maximo: Double
    let rango: ClosedRange<Double>
    var paso = 1.0
    var body: some View {
        HStack(spacing: 20) {
            Deslizador(titulo: titulo + " · mínimo", valor: $minimo, rango: rango, paso: paso, unidad: unidad)
            Deslizador(titulo: titulo + " · máximo", valor: $maximo, rango: rango, paso: paso, unidad: unidad)
        }
    }
}

struct LimitesAyudaVista: View {
    @EnvironmentObject var almacen: Almacen
    var body: some View {
        Tarjeta(titulo: "Límites de los valores") {
            Toggle("Usar límites mínimo y máximo", isOn: $almacen.activo.ayuda.limites.activos)
            Text("Son rangos fijos que pones tú: recortan el tamaño, la velocidad y la entrada suave del patrón, también al elegir un patrón o una variante. No cambian nada por sí solos, y con los límites apagados no se recorta nada.")
                .font(Tema.sans(12)).foregroundStyle(Tema.suave)
            if almacen.activo.ayuda.limites.activos {
                ParLimites(titulo: "Tamaño", unidad: "%", minimo: $almacen.activo.ayuda.limites.tamanoMin,
                           maximo: $almacen.activo.ayuda.limites.tamanoMax, rango: 0...100)
                ParLimites(titulo: "Velocidad", unidad: "por s", minimo: $almacen.activo.ayuda.limites.hzMin,
                           maximo: $almacen.activo.ayuda.limites.hzMax, rango: 0...60)
                ParLimites(titulo: "Entrada suave", unidad: "ms", minimo: $almacen.activo.ayuda.limites.entradaMin,
                           maximo: $almacen.activo.ayuda.limites.entradaMax, rango: 0...1500, paso: 10)
                Button("Valores de fábrica de los límites") {
                    let activos = almacen.activo.ayuda.limites.activos
                    almacen.activo.ayuda.limites = LimitesAyuda()
                    almacen.activo.ayuda.limites.activos = activos
                }
            }
        }
    }
}

struct VariantesAyudaVista: View {
    @EnvironmentObject var almacen: Almacen
    @State private var nombreNuevo = ""

    private func resumen(_ v: VarianteAyuda) -> String {
        "\(v.forma == .circulo ? "Círculos" : "Temblor") · \(Int(v.tamano.rounded())) % · \(Int(v.hz.rounded())) por s · entrada \(Int(v.entradaMs.rounded())) ms · ceder \(Int(v.ceder.rounded())) %"
    }

    var body: some View {
        let ay = almacen.activo.ayuda
        Tarjeta(titulo: "Variantes de los patrones") {
            Text("Guarda tus propios ajustes de un patrón con un nombre y elige a mano cuál usar. La elegida se conserva en este perfil. Nada cambia solo: los valores son siempre los de la variante elegida.")
                .font(Tema.sans(12)).foregroundStyle(Tema.suave)
            if ay.variantes.isEmpty {
                Text("Todavía no tienes variantes.").foregroundStyle(Tema.suave)
            }
            ForEach($almacen.activo.ayuda.variantes) { $v in
                HStack(spacing: 10) {
                    Image(systemName: ay.varianteActiva == v.id ? "largecircle.fill.circle" : "circle")
                        .foregroundStyle(ay.varianteActiva == v.id ? Tema.vivo : Color.secondary)
                    TextField("Nombre", text: $v.nombre).campo().frame(width: 170)
                    Text(resumen(v)).font(Tema.sans(12)).foregroundStyle(Tema.suave)
                    Spacer()
                    Button("Usar") { almacen.usarVarianteAyuda(v.id) }
                    Button { almacen.borrarVarianteAyuda(v.id) } label: { Image(systemName: "trash") }
                        .buttonStyle(.borderless)
                }
            }
            if let v = ay.varianteSeleccionada {
                HStack {
                    if ay.varianteModificada {
                        Label("Has cambiado los valores desde que elegiste «\(v.nombre)»", systemImage: "pencil")
                            .foregroundStyle(.white)
                        Button("Actualizar la variante con los valores actuales") { almacen.actualizarVarianteAyuda() }
                    } else {
                        Label("Usando «\(v.nombre)»", systemImage: "checkmark.circle").foregroundStyle(Tema.vivo)
                    }
                }
            }
            HStack {
                TextField("Nombre de la variante nueva", text: $nombreNuevo).campo().frame(width: 260)
                Button("Guardar los valores actuales como variante") {
                    almacen.guardarVarianteAyuda(nombreNuevo)
                    nombreNuevo = ""
                }
            }
        }
    }
}

struct GraficoAyuda: View {
    let x: [Float], y: [Float], amplitud: [Float]
    var body: some View {
        Canvas { ctx, tam in
            let maximo = max(0.05, (x + y + amplitud).map { abs($0) }.max() ?? 0) * 1.2
            let medio = tam.height / 2
            func punto(_ i: Int, _ v: Float, _ n: Int) -> CGPoint {
                CGPoint(x: tam.width * CGFloat(i) / CGFloat(max(n - 1, 1)), y: medio - CGFloat(v / maximo) * medio)
            }
            var eje = Path()
            eje.move(to: CGPoint(x: 0, y: medio)); eje.addLine(to: CGPoint(x: tam.width, y: medio))
            ctx.stroke(eje, with: .color(.secondary.opacity(0.4)), lineWidth: 1)
            func linea(_ v: [Float], _ color: Color, _ ancho: CGFloat) {
                guard v.count > 1 else { return }
                var p = Path()
                for (i, valor) in v.enumerated() {
                    i == 0 ? p.move(to: punto(i, valor, v.count)) : p.addLine(to: punto(i, valor, v.count))
                }
                ctx.stroke(p, with: .color(color), lineWidth: ancho)
            }
            linea(amplitud, .secondary, 1)
            linea(amplitud.map { -$0 }, .secondary, 1)
            linea(x, Tema.vivo, 1.5)
            linea(y, .white, 1.5)
        }
        .frame(height: 140)
        .background(Color.secondary.opacity(0.08), in: Rectangle())
    }
}

struct MonitorSenalesVista: View {
    @EnvironmentObject var almacen: Almacen
    @EnvironmentObject var motor: Motor

    var body: some View {
        Tarjeta(titulo: "Monitor de la señal (solo lectura)") {
            Toggle("Analizar la señal de la ayuda al apuntado", isOn: $almacen.generales.monitor.activo)
            Text("Mira los últimos 2 s de lo que la ayuda suma al stick derecho y avisa de valores fuera de rango, saltos, velocidades, aceleraciones y oscilaciones por encima de lo que pongas aquí. No cambia ni corrige nada.")
                .font(Tema.sans(12)).foregroundStyle(Tema.suave)
            if almacen.generales.monitor.activo {
                HStack(spacing: 20) {
                    Deslizador(titulo: "Valor máximo", valor: $almacen.generales.monitor.maxAbs, rango: 0.05...1, paso: 0.01, unidad: "", decimales: 2)
                    Deslizador(titulo: "Salto máximo entre muestras", valor: $almacen.generales.monitor.maxSalto, rango: 0.01...1, paso: 0.01, unidad: "", decimales: 2)
                }
                HStack(spacing: 20) {
                    Deslizador(titulo: "Velocidad máxima", valor: $almacen.generales.monitor.maxVelocidad, rango: 1...100, unidad: "/s")
                    Deslizador(titulo: "Aceleración máxima", valor: $almacen.generales.monitor.maxAceleracion, rango: 100...20000, paso: 100, unidad: "/s²")
                }
                Deslizador(titulo: "Oscilación máxima (cambios de sentido)", valor: $almacen.generales.monitor.maxCambiosSigno,
                           rango: 0.05...1, paso: 0.05, unidad: "", decimales: 2)
                Button("Valores de fábrica") {
                    almacen.generales.monitor = LimitesMonitor()
                    almacen.generales.monitor.activo = true
                }
                // Se analiza dos veces por segundo, fuera del bucle de 1000 Hz
                TimelineView(.periodic(from: .now, by: 0.5)) { _ in
                    let (_, hx, hy, _) = motor.instantaneaAyuda(muestras: 200)
                    let inf = MonitorSenales.analizar(x: hx, y: hy, dt: 0.01, limites: almacen.generales.monitor)
                    InformeMonitorVista(informe: inf)
                }
            }
        }
    }
}

struct InformeMonitorVista: View {
    let informe: MonitorSenales.Informe
    var body: some View {
        let m = informe.metricas
        VStack(alignment: .leading, spacing: 8) {
            Label(informe.estado.nombre, systemImage: informe.estado == .ok ? "checkmark.circle" : "exclamationmark.triangle")
                .foregroundStyle(informe.estado == .ok ? Tema.vivo : (informe.estado == .advertencia ? Color.white : Tema.fallo))
            Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 3) {
                GridRow { Text("Muestras"); Text("\(m.muestras)"); Text("Valor máximo"); Text(String(format: "%.3f", m.maxAbs)) }
                GridRow { Text("Salto máximo"); Text(String(format: "%.3f", m.maxSalto)); Text("Velocidad máx."); Text(String(format: "%.1f /s", m.maxVelocidad)) }
                GridRow { Text("Aceleración máx."); Text(String(format: "%.0f /s²", m.maxAceleracion)); Text("Oscilación"); Text(String(format: "%.2f", m.cambiosSigno)) }
            }
            .font(Tema.mono(12))
            ForEach(Array(informe.eventos.prefix(8).enumerated()), id: \.offset) { _, e in
                Text("\(e.gravedad.nombre) · muestra \(e.indice) · eje \(e.eje) · \(e.motivo): \(String(format: "%.3f", e.valor)) (límite \(String(format: "%.3f", e.limite)))")
                    .font(Tema.sans(12)).foregroundStyle(e.gravedad == .anomalia ? Tema.fallo : Color.white)
            }
            if informe.eventos.count > 8 || informe.eventosOmitidos > 0 {
                Text("… y \(informe.eventos.count - min(8, informe.eventos.count) + informe.eventosOmitidos) más").font(Tema.sans(12)).foregroundStyle(Tema.suave)
            }
        }
    }
}

struct DiagnosticoAyudaVista: View {
    @EnvironmentObject var motor: Motor
    var body: some View {
        Tarjeta(titulo: "Diagnóstico") {
            // Se lee del motor 30 veces por segundo; el cálculo sigue en su propio hilo
            TimelineView(.animation(minimumInterval: 1.0 / 30)) { _ in
                let (d, hx, hy, ha) = motor.instantaneaAyuda(muestras: 200)
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 12) {
                        Label(d.encendida ? "Encendida" : "Apagada", systemImage: "circle.fill")
                            .foregroundStyle(d.encendida ? Tema.vivo : Tema.suave)
                        Label(d.aplicando ? "Moviendo el stick" : "En reposo", systemImage: "scope")
                            .foregroundStyle(d.aplicando ? Tema.vivo : Tema.suave)
                        if d.enTransicion { Label("Enlazando un cambio", systemImage: "arrow.triangle.merge").foregroundStyle(.white) }
                        if d.limitada { Label("Recortada por los límites", systemImage: "arrow.down.right.and.arrow.up.left").foregroundStyle(.white) }
                    }
                    Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 4) {
                        GridRow {
                            Text("Movimiento"); Text(d.forma == .circulo ? "Círculos" : "Temblor lateral").monospacedDigit()
                            Text("Entrada suave"); Text("\(Int(d.entradaMs.rounded())) ms · avance \(Int((d.rampa * 100).rounded())) %").monospacedDigit()
                        }
                        GridRow {
                            Text("Tamaño"); Text(String(format: "%.1f %%", d.tamano)).monospacedDigit()
                            Text("Cesión"); Text("\(Int((d.cesion * 100).rounded())) % (\(Int(d.ceder.rounded())) % configurado)").monospacedDigit()
                        }
                        GridRow {
                            Text("Velocidad"); Text(String(format: "%.1f por s", d.hz)).monospacedDigit()
                            Text("Amplitud ahora"); Text(String(format: "%.2f %% · fase %.2f", d.amplitud * 100, d.fase)).monospacedDigit()
                        }
                    }
                    .font(Tema.sans(13))
                    GraficoAyuda(x: hx, y: hy, amplitud: ha)
                    HStack(spacing: 14) {
                        Label("horizontal", systemImage: "line.diagonal").foregroundStyle(Tema.vivo)
                        Label("vertical", systemImage: "line.diagonal").foregroundStyle(.white)
                        Label("amplitud", systemImage: "line.diagonal").foregroundStyle(Tema.suave)
                        Spacer()
                        Text("últimos 2 s").foregroundStyle(Tema.suave)
                    }
                    .font(Tema.sans(12))
                }
            }
            Text("Son los valores que usa de verdad el motor (ya recortados por los límites) y lo que suma ahora al stick derecho. Solo se mira: no cambia nada. Para verla en movimiento, enciende la ayuda y mantén el botón de apuntar.")
                .font(Tema.sans(12)).foregroundStyle(Tema.suave)
        }
    }
}

// MARK: - Perfiles

struct Perfiles: View {
    @EnvironmentObject var almacen: Almacen
    @State private var mensajeSituaciones: String?
    var body: some View {
        Text("Cada perfil guarda todos los ajustes. El que está marcado es el que se usa ahora.").foregroundStyle(Tema.suave)
        Tarjeta(titulo: "Tus perfiles") {
            ForEach($almacen.perfiles) { $p in
                HStack {
                    Button {
                        almacen.activoID = p.id
                    } label: {
                        Image(systemName: almacen.activoID == p.id ? "largecircle.fill.circle" : "circle")
                    }
                    .buttonStyle(.borderless)
                    TextField("Nombre", text: $p.nombre).campo().frame(width: 260)
                    ColorPicker("Luz", selection: colorBinding($p.color), supportsOpacity: false)
                        .help("Color de la barra de luz del DualSense con este perfil")
                    Toggle("Con el mando", isOn: $p.enCiclo)
                        .help("Si está marcado, este perfil sale al cambiar de perfil con el mando")
                }
            }
            HStack {
                Button { almacen.nuevo() } label: { Label("Nuevo", systemImage: "plus") }
                Button { almacen.duplicar() } label: { Label("Duplicar el activo", systemImage: "plus.square.on.square") }
                Button(role: .destructive) { almacen.borrarActivo() } label: { Label("Borrar el activo", systemImage: "trash") }
                    .disabled(almacen.perfiles.count < 2)
            }
        }
        AjusteMandoVista()
        Tarjeta(titulo: "Avisos") {
            Toggle("Avisos de voz", isOn: $almacen.generales.avisosVoz)
            Text(almacen.generales.avisosVoz
                 ? "El Mac dice en voz alta lo que cambias con el mando o los widgets: perfil, anti-recoil, macros, fuerza…"
                 : "Sin voz: los mismos avisos salen en pantalla, abajo en esta ventana y en el móvil.")
                .font(Tema.sans(12)).foregroundStyle(Tema.suave)
        }
        Tarjeta(titulo: "Perfiles por situación") {
            Text("Crea «Corto alcance» (pasillos: giro rápido, retroceso corto, ayuda fuerte) y «Largo alcance» (distancia: más fino, ráfagas largas, ayuda discreta) a partir del perfil activo, con sus botones y combinaciones. Son un punto de partida: afínalos como quieras. Cámbialos con la combinación de abajo.")
                .font(Tema.sans(13)).foregroundStyle(Tema.suave)
            HStack {
                Button("Crear perfiles por situación") {
                    let n = almacen.crearPerfilesPorSituacion()
                    mensajeSituaciones = n == 0 ? "Ya existen «Corto alcance» y «Largo alcance»." : "Añadidos \(n) perfil\(n == 1 ? "" : "es")."
                }
                if let m = mensajeSituaciones { Text(m).font(Tema.sans(13)).foregroundStyle(Tema.suave) }
            }
            Text("Para que al cambiar con el mando solo pasen los que quieres, desmarca «Con el mando» en los demás.")
                .font(Tema.sans(12)).foregroundStyle(Tema.suave)
        }
        Tarjeta(titulo: "Cambiar de perfil desde el mando") {
            Toggle("Activado", isOn: $almacen.generales.cambioPerfil)
            HStack(spacing: 12) {
                Picker("Mantén", selection: $almacen.generales.cambioMantener) {
                    ForEach(Boton.allCases) { Text($0.nombre).tag($0) }
                }
                .frame(width: 220)
                Picker("y pulsa", selection: $almacen.generales.cambioSiguiente) {
                    ForEach(Boton.allCases) { Text($0.nombre).tag($0) }
                }
                .frame(width: 200)
                Text("para el siguiente,")
                Picker("", selection: $almacen.generales.cambioAnterior) {
                    ForEach(Boton.allCases) { Text($0.nombre).tag($0) }
                }
                .labelsHidden()
                .frame(width: 160)
                Text("para el anterior")
            }
            .disabled(!almacen.generales.cambioPerfil)
            Toggle("Avisar del nombre del perfil al cambiar", isOn: $almacen.generales.decirNombre)
            Text("Son botones de tu mando y también llegan a la consola. Elige uno que no uses en el juego para mantener.")
                .font(Tema.sans(12)).foregroundStyle(Tema.suave)
        }
    }
}

/// Un punto del color del perfil como imagen en color (en los menús de la barra de herramientas una forma no se pinta)
func puntoDeColor(_ hex: String) -> NSImage {
    let c = DualSense.leerHex(hex) ?? (0, 0.31, 1)
    let imagen = NSImage(size: NSSize(width: 10, height: 10), flipped: false) { r in
        NSColor(srgbRed: CGFloat(c.r), green: CGFloat(c.g), blue: CGFloat(c.b), alpha: 1).setFill()
        NSBezierPath(ovalIn: r).fill()
        return true
    }
    imagen.isTemplate = false
    return imagen
}

/// Color de SwiftUI <-> texto "#RRGGBB" guardado en el perfil
func colorBinding(_ hex: Binding<String>) -> Binding<Color> {
    Binding(
        get: {
            let c = DualSense.leerHex(hex.wrappedValue) ?? (0, 0.31, 1)
            return Color(red: Double(c.r), green: Double(c.g), blue: Double(c.b))
        },
        set: { nuevo in
            guard let ns = NSColor(nuevo).usingColorSpace(.sRGB) else { return }
            hex.wrappedValue = String(format: "#%02X%02X%02X", Int(ns.redComponent * 255),
                                      Int(ns.greenComponent * 255), Int(ns.blueComponent * 255))
        })
}

// MARK: - Ayuda

struct Ayuda: View {
    var body: some View {
        Tarjeta(titulo: "Probar en el Mac") {
            Text("1. Placa en modo mac (LED verde al conectarla). Si está en modo consola, mantén BOOT 2 s.")
            Text("2. Conecta el USB-C «USB» de la placa al Mac y enciende el DualSense.")
            Text("3. En «En vivo» verás tu mando y lo que recibiría la consola.")
        }
        Tarjeta(titulo: "Jugar en la PS5") {
            Text("1. Placa en modo consola: mantén BOOT 2 s (el LED pasa a cian al conectarla).")
            Text("2. USB-C «USB» de la placa → puerto USB del P5Mate; P5Mate → PS5.")
            Text("3. USB-C «COM» de la placa → Mac. El DualSense, por Bluetooth al Mac.")
            Text("4. Deja esta app abierta mientras juegas. Si la cierras, el mando se queda quieto.")
            Text("5. Para que la barra de luz tenga el color del perfil, deja la app delante (es la última que tocaste en el Mac). Si no, macOS pone su color, pero el mando funciona igual.")
        }
        Tarjeta(titulo: "Botón BOOT de la placa") {
            Text("Pulsación corta: botón X. Mantener 2 s: cambiar entre modo mac y modo consola.")
        }
    }
}
