import Foundation

// MARK: - Botones y estado del mando

/// Botones lógicos. Los 14 primeros van en el mismo orden que los bits del mando de PS4;
/// la cruceta va como 4 botones más para poder reasignarla. El de silenciar el micro solo
/// existe en el DualSense: se puede usar como entrada, pero la consola no lo recibe nunca
/// (el mando de PS4 no lo tiene y la trama solo lleva los 14 primeros bits).
enum Boton: String, CaseIterable, Codable, Identifiable {
    case cuadrado, x, circulo, triangulo, l1, r1, l2, r2
    case share, options, l3, r3, ps, tactil
    case arriba, derecha, abajo, izquierda
    case silenciar

    var id: String { rawValue }
    var indice: Int { Boton.allCases.firstIndex(of: self)! }
    var bit: UInt32 { 1 << UInt32(indice) }

    /// Si la consola puede recibirlo (para elegir qué recibe la consola: reasignar, macros, turbo)
    var llegaALaConsola: Bool { self != .silenciar }
    static let salidas = allCases.filter(\.llegaALaConsola)

    var nombre: String {
        switch self {
        case .cuadrado: return "□ Cuadrado"
        case .x: return "✕ X"
        case .circulo: return "○ Círculo"
        case .triangulo: return "△ Triángulo"
        case .l1: return "L1"
        case .r1: return "R1"
        case .l2: return "L2"
        case .r2: return "R2"
        case .share: return "Create / Share"
        case .options: return "Options"
        case .l3: return "L3 (stick izq.)"
        case .r3: return "R3 (stick der.)"
        case .ps: return "PS"
        case .tactil: return "Panel táctil"
        case .arriba: return "↑ Arriba"
        case .derecha: return "→ Derecha"
        case .abajo: return "↓ Abajo"
        case .izquierda: return "← Izquierda"
        case .silenciar: return "🎙 Silenciar micro"
        }
    }

    var corto: String {
        switch self {
        case .cuadrado: return "□"
        case .x: return "✕"
        case .circulo: return "○"
        case .triangulo: return "△"
        case .share: return "Create"
        case .options: return "Opt"
        case .tactil: return "Táctil"
        case .arriba: return "↑"
        case .derecha: return "→"
        case .abajo: return "↓"
        case .izquierda: return "←"
        case .silenciar: return "Mic"
        default: return rawValue.uppercased()
        }
    }
}

/// Informe en bruto del DualSense, para lo que el sistema de mandos de macOS no da
enum InformeDualSense {
    /// Bit del botón de silenciar en el informe completo (el tercer byte de botones, bit 2):
    /// 0x31 por Bluetooth, 0x01 de 64 bytes por USB. El 0x01 corto de Bluetooth (antes de que
    /// el sistema pida el completo) no lo lleva. El informe empieza por su número.
    static func silencio(id: UInt32, _ informe: UnsafePointer<UInt8>, _ largo: Int) -> Bool? {
        if id == 0x31 && largo >= 12 { return informe[11] & 0x04 != 0 }
        if id == 0x01 && largo >= 64 { return informe[10] & 0x04 != 0 }
        return nil
    }
}

/// Ritmo real del mando: cuántos informes manda por segundo y el mayor hueco entre dos
/// seguidos. Por Bluetooth el DualSense puede ir lento (en este Mac, unos 66 por segundo).
struct RitmoMando: Equatable {
    private(set) var hz = 0              // informes en el último segundo medido
    private(set) var huecoMs = 0.0       // mayor hueco en ese segundo
    private var cuenta = 0, desde = -1.0, anterior = -1.0, hueco = 0.0

    mutating func informe(t: Double) {
        if desde < 0 { desde = t }
        if anterior >= 0 { hueco = max(hueco, t - anterior) }
        anterior = t
        cuenta += 1
        if t - desde >= 1 {
            hz = Int((Double(cuenta - 1) / (t - desde)).rounded())
            huecoMs = hueco * 1000
            cuenta = 1; hueco = 0; desde = t
        }
    }

    /// Lo que se enseña: si lleva más de un segundo sin informes, el mando no está mandando nada
    func actual(t: Double) -> (hz: Int, huecoMs: Double) {
        anterior < 0 || t - anterior > 1 ? (0, 0) : (hz, huecoMs)
    }
}

/// Batería del mando tal como la da el sistema (nivel de 0 a 1 y estado: -1 desconocido,
/// 0 descargando, 1 cargando, 2 llena)
struct BateriaMando: Equatable {
    var porcentaje: Int?
    var estado = "descargando"           // "descargando", "cargando", "llena" o "desconocido"

    init(porcentaje: Int? = nil, estado: String = "desconocido") { self.porcentaje = porcentaje; self.estado = estado }

    init(nivel: Float, estado e: Int) {
        porcentaje = nivel.isFinite && nivel >= 0 ? Int((min(nivel, 1) * 100).rounded()) : nil
        estado = [0: "descargando", 1: "cargando", 2: "llena"][e] ?? "desconocido"
        if estado == "llena" { porcentaje = 100 }
    }

    var texto: String {
        guard let porcentaje else { return "Batería desconocida" }
        switch estado {
        case "cargando": return "Batería \(porcentaje) % (cargando)"
        case "llena": return "Batería llena"
        default: return "Batería \(porcentaje) %"
        }
    }

    var baja: Bool { (porcentaje ?? 100) <= 20 && estado != "cargando" }
}

struct Estado: Equatable {
    var botones: UInt32 = 0     // bits de Boton
    var lx: UInt8 = 128, ly: UInt8 = 128   // Y pequeña = arriba, como en el mando
    var rx: UInt8 = 128, ry: UInt8 = 128
    var l2: UInt8 = 0, r2: UInt8 = 0

    func pulsado(_ b: Boton) -> Bool { botones & b.bit != 0 }
}

// MARK: - Perfil


struct AjusteStick: Codable, Equatable {
    var zonaMuerta = 5.0        // % del recorrido que no hace nada
    var formaCruz = false       // zona muerta por ejes (en cruz) en vez de redonda
    var zonaExterna = 100.0     // % a partir del cual ya cuenta como tope
    var antiZonaMuerta = 0.0    // % que se suma al empezar a mover (contra la zona muerta del juego)
    var curva = 1.0             // 1 = lineal; >1 = más fino en el centro; <1 = más brusco
    var sensX = 100.0           // %
    var sensY = 100.0           // %
    var limite = 100.0          // % máximo que llega a la consola
    var suavizado = 0.0         // % (0 = nada; 100 = muy suave, ~150 ms)
    var aceleracion = 0.0       // % extra cuando mantienes el stick casi a tope...
    var tiempoAceleracion = 300.0  // ...que se alcanza en estos ms
    var invertirX = false
    var invertirY = false
}

struct AjusteGatillo: Codable, Equatable {
    var zonaMuerta = 0.0        // %
    var zonaExterna = 100.0     // % a partir del cual cuenta como pulsado a fondo
    var curva = 1.0
    var disparoRapido = false   // en cuanto lo rozas, cuenta como pulsado a fondo
}

struct Turbo: Codable, Equatable, Identifiable {
    var id = UUID()
    var boton: Boton = .x
    var hz = 10.0               // pulsaciones por segundo
    var ciclo = 50.0            // % de cada pulsación que está apretado
    var activo = true           // se enciende y se apaga desde «En vivo» (los perfiles antiguos lo leen encendido)
}

struct PasoMacro: Codable, Equatable, Identifiable {
    var id = UUID()
    var botones: [Boton] = []
    var ms = 100
}

struct Macro: Codable, Equatable, Identifiable {
    var id = UUID()
    var nombre = "Macro nueva"
    var activa = true
    var disparador: Boton = .r3
    var repetir = false              // repetir mientras se mantenga el disparador
    var bloquearDisparador = true    // el disparador no llega a la consola
    var pasos: [PasoMacro] = [PasoMacro(botones: [.x], ms: 100), PasoMacro(botones: [], ms: 100)]
    var atajo = false                // una combinación del mando la activa y la desactiva
    var atajoMantener: Boton = .l1   // se mantiene este...
    var atajoPulsar: Boton = .derecha    // ...y se pulsa este (botones de tu mando)
}

/// Un botón de «En vivo» (en el Mac y en el móvil) para encender o apagar algo sin usar el mando
struct Widget: Codable, Equatable, Identifiable {
    enum Tipo: String, Codable, CaseIterable {
        case antiRecoil, ayuda, pausa, turbos, turbo, macros, macro
    }
    var id = UUID()
    var tipo = Tipo.antiRecoil
    var objetivo: UUID?              // el turbo o la macro concretos (solo `turbo` y `macro`)
}

/// Combinaciones del mando que activan o desactivan cada macro
enum ComboMacros {
    /// Las macros cuya combinación se acaba de completar (se mira el botón recién pulsado)
    static func pedidas(_ e: Estado, flanco: UInt32, _ p: Perfil) -> [UUID] {
        p.macros.filter { m in
            guard m.atajo, flanco & m.atajoPulsar.bit != 0 else { return false }
            return m.atajoMantener == m.atajoPulsar || e.pulsado(m.atajoMantener)
        }.map(\.id)
    }
}

struct AntiRecoil: Codable, Equatable {
    var activo = false
    var vertical = 20.0         // % del stick derecho hacia abajo mientras disparas
    var progresivo = false      // la fuerza cambia con el tiempo...
    var verticalFinal = 10.0    // ...hasta este %...
    var transicionMs = 1000.0   // ...en este tiempo (el retroceso real suele bajar)
    var horizontal = 0.0        // % hacia la derecha (negativo = izquierda)
    var retardoMs = 0.0         // espera desde que empiezas a disparar
    var disparar: Boton = .r2   // botón de disparar, tal como lo recibe la consola
    var apuntar: Boton = .l2    // botón de apuntar, tal como lo recibe la consola
    var soloApuntando = true    // solo con el botón de apuntar pulsado
    var atajo = true            // la combinación lo enciende y lo apaga
    var atajoMantener: Boton = .l2   // se mantiene este...
    var atajoPulsar: Boton = .abajo  // ...y se pulsa este (botones de tu mando)
}

/// Mueve el stick derecho en círculos o temblores diminutos mientras apuntas, para que la
/// ayuda al apuntado del propio juego esté siempre enganchada (como los scripts del Cronus).
struct AyudaApuntado: Codable, Equatable {
    enum Forma: String, Codable, CaseIterable { case circulo, temblor }
    var activo = false
    var forma = Forma.circulo
    var tamano = 8.0            // % del recorrido del stick
    var hz = 12.0               // vueltas o temblores por segundo
    var entradaMs = 150.0       // tarda esto en llegar a toda la fuerza al empezar a apuntar
    var ceder = 70.0            // % que se reduce cuando mueves tú el stick derecho a tope
    var boton: Boton = .l2      // se activa al apuntar con este botón (tal como lo recibe la consola)
    var tambienDisparando = false    // y además solo mientras disparas (botón de disparar del anti-recoil)
    var atajo = true
    var atajoMantener: Boton = .l2
    var atajoPulsar: Boton = .arriba
    var cambioActivo = true             // cambiar de patrón desde el mando
    var cambioMantener: Boton = .l1     // se mantiene este...
    var cambioSiguiente: Boton = .derecha   // ...y se pulsa este para el patrón siguiente
    var cambioAnterior: Boton = .izquierda  // ...o este para el anterior
    var limites = LimitesAyuda()            // rangos permitidos (solo si el usuario los activa)
    var variantes: [VarianteAyuda] = []     // variantes propias de los patrones, con nombre
    var varianteActiva: UUID? = nil         // la que el usuario eligió a mano en este perfil
}

/// Rangos que el usuario permite para el tamaño, la velocidad y la entrada suave. Mientras
/// no se activen, no se recorta nada. Son límites fijos: no producen ninguna variación.
struct LimitesAyuda: Codable, Equatable {
    var activos = false
    var tamanoMin = 1.0, tamanoMax = 30.0       // %
    var hzMin = 2.0, hzMax = 40.0               // por segundo
    var entradaMin = 0.0, entradaMax = 600.0    // ms
}

/// Ajustes de un patrón guardados con un nombre. Se eligen a mano; nunca cambian solos.
struct VarianteAyuda: Codable, Equatable, Identifiable {
    var id = UUID()
    var nombre = "Variante"
    var base = -1                               // patrón de origen (índice), -1 = ninguno
    var forma = AyudaApuntado.Forma.circulo
    var tamano = 8.0, hz = 12.0, entradaMs = 150.0, ceder = 70.0
}

extension AyudaApuntado {
    /// Lo que se puede elegir con la combinación del mando: los seis patrones y luego las variantes
    enum Opcion: Equatable { case patron(Int), variante(UUID) }

    static func recortar(_ v: Double, _ a: Double, _ b: Double) -> Double {
        Swift.min(Swift.max(v, Swift.min(a, b)), Swift.max(a, b))
    }

    /// Tamaño, velocidad y entrada tal como los usa el motor: los guardados, recortados a los
    /// límites si el usuario los ha activado (si no, exactamente los guardados).
    func recortados(_ tamano: Double, _ hz: Double, _ entradaMs: Double) -> (tamano: Double, hz: Double, entradaMs: Double) {
        guard limites.activos else { return (tamano, hz, entradaMs) }
        let l = limites
        return (AyudaApuntado.recortar(tamano, l.tamanoMin, l.tamanoMax),
                AyudaApuntado.recortar(hz, l.hzMin, l.hzMax),
                AyudaApuntado.recortar(entradaMs, l.entradaMin, l.entradaMax))
    }

    var efectivos: (tamano: Double, hz: Double, entradaMs: Double, ceder: Double) {
        let r = recortados(tamano, hz, entradaMs)
        return (r.tamano, r.hz, r.entradaMs, ceder)
    }

    /// ¿Algún valor guardado queda fuera de los límites?
    var limitado: Bool {
        let e = efectivos
        return e.tamano != tamano || e.hz != hz || e.entradaMs != entradaMs
    }

    /// Deja los valores guardados dentro de los límites (si no hay límites, no toca nada)
    mutating func normalizar() {
        let e = efectivos
        tamano = e.tamano; hz = e.hz; entradaMs = e.entradaMs
    }

    // MARK: Variantes

    var varianteSeleccionada: VarianteAyuda? {
        guard let id = varianteActiva else { return nil }
        return variantes.first { $0.id == id }
    }

    /// ¿Se han tocado los valores desde que se eligió la variante?
    var varianteModificada: Bool {
        guard let v = varianteSeleccionada else { return false }
        let r = recortados(v.tamano, v.hz, v.entradaMs)
        return !(v.forma == forma && r.tamano == tamano && r.hz == hz && r.entradaMs == entradaMs && v.ceder == ceder)
    }

    mutating func aplicar(_ v: VarianteAyuda) {
        forma = v.forma; tamano = v.tamano; hz = v.hz; entradaMs = v.entradaMs; ceder = v.ceder
        varianteActiva = v.id
        normalizar()
    }

    /// Guarda los valores actuales como variante nueva y la deja elegida
    @discardableResult
    mutating func guardarComoVariante(nombre: String) -> VarianteAyuda {
        var v = VarianteAyuda()
        let limpio = nombre.trimmingCharacters(in: .whitespacesAndNewlines)
        v.nombre = limpio.isEmpty ? "Variante \(variantes.count + 1)" : limpio
        v.base = indicePatron ?? -1
        v.forma = forma; v.tamano = tamano; v.hz = hz; v.entradaMs = entradaMs; v.ceder = ceder
        variantes.append(v)
        varianteActiva = v.id
        return v
    }

    /// Pone en la variante elegida los valores actuales
    mutating func actualizarVarianteActiva() {
        guard let id = varianteActiva, let i = variantes.firstIndex(where: { $0.id == id }) else { return }
        variantes[i].forma = forma; variantes[i].tamano = tamano; variantes[i].hz = hz
        variantes[i].entradaMs = entradaMs; variantes[i].ceder = ceder
    }

    mutating func borrarVariante(_ id: UUID) {
        variantes.removeAll { $0.id == id }
        if varianteActiva == id { varianteActiva = nil }
    }

    // MARK: Elegir con el mando

    var opciones: [Opcion] {
        AyudaApuntado.patrones.indices.map { Opcion.patron($0) } + variantes.map { Opcion.variante($0.id) }
    }

    /// Posición de lo que está elegido ahora en `opciones` (nil si los valores están tocados a mano)
    var opcionActual: Int? {
        if let v = varianteSeleccionada, !varianteModificada, let i = variantes.firstIndex(where: { $0.id == v.id }) {
            return AyudaApuntado.patrones.count + i
        }
        return indicePatron
    }

    /// Elige la opción `i` y devuelve su nombre
    mutating func aplicarOpcion(_ i: Int) -> String {
        switch opciones[i] {
        case .patron(let p):
            aplicarPatron(p)
            return AyudaApuntado.patrones[p].nombre
        case .variante(let id):
            guard let v = variantes.first(where: { $0.id == id }) else { return "" }
            aplicar(v)
            return v.nombre
        }
    }
}

extension AyudaApuntado {
    struct Patron {
        let nombre: String
        let forma: Forma
        let tamano: Double, hz: Double, entradaMs: Double, ceder: Double
    }

    /// Patrones listos: dos movimientos en tres intensidades. Se cambia entre ellos a mano,
    /// con la combinación del mando o desde las ventanas; nunca solo.
    static let patrones: [Patron] = [
        Patron(nombre: "Círculos discretos", forma: .circulo, tamano: 4, hz: 8, entradaMs: 300, ceder: 85),
        Patron(nombre: "Círculos medios", forma: .circulo, tamano: 8, hz: 12, entradaMs: 150, ceder: 70),
        Patron(nombre: "Círculos fuertes", forma: .circulo, tamano: 14, hz: 16, entradaMs: 80, ceder: 50),
        Patron(nombre: "Temblor discreto", forma: .temblor, tamano: 4, hz: 8, entradaMs: 300, ceder: 85),
        Patron(nombre: "Temblor medio", forma: .temblor, tamano: 8, hz: 12, entradaMs: 150, ceder: 70),
        Patron(nombre: "Temblor fuerte", forma: .temblor, tamano: 14, hz: 16, entradaMs: 80, ceder: 50),
    ]

    /// Cuál de los patrones listos es el actual (nil si los valores están tocados a mano)
    var indicePatron: Int? {
        AyudaApuntado.patrones.firstIndex {
            let r = recortados($0.tamano, $0.hz, $0.entradaMs)
            return $0.forma == forma && r.tamano == tamano && r.hz == hz && r.entradaMs == entradaMs && $0.ceder == ceder
        }
    }

    mutating func aplicarPatron(_ i: Int) {
        let p = AyudaApuntado.patrones[i]
        forma = p.forma; tamano = p.tamano; hz = p.hz; entradaMs = p.entradaMs; ceder = p.ceder
        varianteActiva = nil
        normalizar()
    }
}

struct Perfil: Codable, Equatable, Identifiable {
    var id = UUID()
    var nombre = "Perfil"
    var intercambiarSticks = false
    var izq = AjusteStick()
    var der = AjusteStick()
    var l2 = AjusteGatillo()
    var r2 = AjusteGatillo()
    var reasignar: [String: String] = [:]   // botón físico -> botón que recibe la consola ("nada" = anulado)
    var alternar: [Boton] = []              // pulsar una vez = mantener; otra vez = soltar
    var pulsacionLarga: [String: String] = [:]   // botón físico -> qué recibe la consola si lo mantienes
    var msLarga = 300.0                     // a partir de cuánto cuenta como pulsación larga
    var turbos: [Turbo] = []
    var macros: [Macro] = []
    var antiRecoil = AntiRecoil()
    var ayuda = AyudaApuntado()
    var widgets: [Widget] = []              // botones de «En vivo» de este perfil, en orden
    var color = "#0050FF"                   // barra de luz del DualSense con este perfil
    var enCiclo = true                      // entra al cambiar de perfil con el mando

    init(nombre: String = "Perfil") { self.nombre = nombre }

    /// Colores que se van dando a los perfiles nuevos
    static let colores = ["#0050FF", "#FF2D2D", "#00C853", "#FFB300", "#B000FF", "#00E5FF", "#FF4FA3", "#FFFFFF"]

    func destino(de b: Boton) -> Boton? {
        guard let d = reasignar[b.rawValue] else { return b.llegaALaConsola ? b : nil }
        return Boton(rawValue: d)   // "nada" -> nil
    }
}

/// Ajustes que no dependen del perfil
struct AjustesGenerales: Codable, Equatable {
    var cambioPerfil = true          // cambiar de perfil desde el mando
    var cambioMantener: Boton = .tactil
    var cambioSiguiente: Boton = .derecha
    var cambioAnterior: Boton = .izquierda
    var decirNombre = true           // el Mac avisa del perfil nuevo
    var avisosVoz = true             // los avisos se dicen en voz alta; si no, salen en pantalla (Mac y móvil)
    var servidorMovil = true         // servidor local para ver y ajustar el mando desde el móvil
    var clave = AjustesGenerales.nuevaClave()   // sin ella, el móvil no puede ni mirar ni cambiar nada
    var ajusteMando = true           // ajustar valores desde el mando
    var ajusteMantener: Boton = .share   // mantén este; ←/→ elige qué ajustar y ↑/↓ lo sube o baja
    var fuerzaMando = true           // subir y bajar la fuerza del anti-recoil desde el mando
    var fuerzaMantener: Boton = .silenciar   // mantén este y pulsa ↑/↓ (no llegan a la consola)
    var monitor = LimitesMonitor()       // monitor de solo lectura de la señal de la ayuda al apuntado
    var medidor = ConfigMedidor()        // medidor de tu propio control (qué cuenta como ráfaga)
}

extension AjustesGenerales {
    /// 10 caracteres sin letras que se confundan (sin 0/O, 1/I/L)
    static func nuevaClave() -> String {
        let letras = Array("ABCDEFGHJKMNPQRSTUVWXYZ23456789")
        return String((0..<10).map { _ in letras[Int.random(in: 0..<letras.count)] })
    }
}

/// Mantener un botón (por defecto el de silenciar el micro) y pulsar ↑/↓ sube o baja la fuerza del
/// anti-recoil, y ←/→ mueve su corrección lateral. Mientras se mantiene, la cruceta se quita de la entrada
/// para que no llegue a la consola.
enum ComboFuerza {
    /// Devuelve si la combinación está mantenida y los pasos pedidos en esta vuelta (+1, -1 o 0):
    /// `paso` para la fuerza (↑/↓) y `lateral` para la corrección lateral (→ derecha, ← izquierda)
    static func aplicar(_ e: inout Estado, flanco: UInt32, _ g: AjustesGenerales) -> (mantenido: Bool, paso: Int, lateral: Int) {
        guard g.fuerzaMando && e.pulsado(g.fuerzaMantener) else { return (false, 0, 0) }
        let paso = flanco & Boton.arriba.bit != 0 ? 1 : (flanco & Boton.abajo.bit != 0 ? -1 : 0)
        let lateral = flanco & Boton.derecha.bit != 0 ? 1 : (flanco & Boton.izquierda.bit != 0 ? -1 : 0)
        e.botones &= ~(Boton.arriba.bit | Boton.abajo.bit | Boton.derecha.bit | Boton.izquierda.bit)
        return (true, paso, lateral)
    }
}

/// Valores que se pueden subir y bajar desde el mando
struct AjusteRapido {
    let nombre: String
    let rango: ClosedRange<Double>
    let paso: Double
    let leer: (Perfil) -> Double
    let escribir: (inout Perfil, Double) -> Void

    static let lista: [AjusteRapido] = [
        AjusteRapido(nombre: "Anti-recoil fuerza", rango: 0...100, paso: 2,
                     leer: { $0.antiRecoil.vertical }, escribir: { $0.antiRecoil.vertical = $1 }),
        AjusteRapido(nombre: "Anti-recoil lateral", rango: -50...50, paso: 2,
                     leer: { $0.antiRecoil.horizontal }, escribir: { $0.antiRecoil.horizontal = $1 }),
        AjusteRapido(nombre: "Ayuda tamaño", rango: 1...30, paso: 1,
                     leer: { $0.ayuda.tamano }, escribir: { $0.ayuda.tamano = $1 }),
        AjusteRapido(nombre: "Ayuda velocidad", rango: 2...40, paso: 1,
                     leer: { $0.ayuda.hz }, escribir: { $0.ayuda.hz = $1 }),
        AjusteRapido(nombre: "Sensibilidad horizontal", rango: 20...200, paso: 5,
                     leer: { $0.der.sensX }, escribir: { $0.der.sensX = $1 }),
        AjusteRapido(nombre: "Sensibilidad vertical", rango: 20...200, paso: 5,
                     leer: { $0.der.sensY }, escribir: { $0.der.sensY = $1 }),
    ]
}

// MARK: - Cargar sin perder nada

/// Rellena lo que falte en un JSON guardado con los valores por defecto. Así, cuando se
/// añade una opción nueva, los perfiles antiguos siguen cargando (con la opción por defecto).
private enum Rellenar {
    static func json<T: Encodable>(_ v: T) -> Any {
        (try? JSONSerialization.jsonObject(with: JSONEncoder().encode(v))) ?? [:]
    }
    // Plantillas para los elementos de las listas
    static let plantillas: [String: Any] = [
        "perfiles": json(Perfil()), "turbos": json(Turbo()),
        "macros": json(Macro()), "pasos": json(PasoMacro()), "variantes": json(VarianteAyuda()),
        "widgets": json(Widget()),
    ]

    static func mezclar(_ base: Any, _ guardado: Any, clave: String? = nil) -> Any {
        if let b = base as? [String: Any], let g = guardado as? [String: Any] {
            var r = g
            for (k, v) in b {
                r[k] = g[k].map { mezclar(v, $0, clave: k) } ?? v
            }
            return r
        }
        if let g = guardado as? [Any], let k = clave, let plantilla = plantillas[k] {
            return g.map { mezclar(plantilla, $0) }
        }
        return guardado
    }
}

// MARK: - Perfiles guardados

/// Guarda los perfiles en ~/Library/Application Support/Puente de mando/perfiles.json
final class Almacen: ObservableObject {
    @Published var perfiles: [Perfil] = [] { didSet { cambiado() } }
    @Published var activoID: UUID? { didSet { cambiado() } }
    @Published var generales = AjustesGenerales() { didSet { cambiado() } }

    /// Lo llama el motor para tener siempre el perfil activo y los ajustes al día
    var alCambiar: ((Perfil, AjustesGenerales) -> Void)?

    private let archivo: URL
    private var guardado: DispatchWorkItem?
    /// Sube con cada cambio: la sincronización con la placa (Sincro.swift) sabe así si hay cambios hechos aquí
    private(set) var version = 0
    var archivoURL: URL { archivo }

    private struct Fichero: Codable {
        var perfiles: [Perfil]
        var activo: UUID?
        var generales = AjustesGenerales()
    }

    /// `archivo`: dónde se guardan los perfiles (por defecto, la carpeta de la app; las pruebas usan otra)
    init(archivo: URL? = nil) {
        if let archivo {
            self.archivo = archivo
        } else {
            let carpeta = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("Puente de mando", isDirectory: true)
            try? FileManager.default.createDirectory(at: carpeta, withIntermediateDirectories: true)
            self.archivo = carpeta.appendingPathComponent("perfiles.json")
        }
        if let datos = try? Data(contentsOf: self.archivo),
           let guardado = try? JSONSerialization.jsonObject(with: datos),
           let completo = try? JSONSerialization.data(withJSONObject:
                Rellenar.mezclar(Rellenar.json(Fichero(perfiles: [])), guardado)),
           let f = try? JSONDecoder().decode(Fichero.self, from: completo), !f.perfiles.isEmpty {
            perfiles = f.perfiles
            activoID = f.activo ?? f.perfiles[0].id
            generales = f.generales
        } else {
            let p = Perfil(nombre: "Normal")
            perfiles = [p]
            activoID = p.id
        }
        cambiado()   // guarda ya la clave, si es nueva
    }

    var activo: Perfil {
        get { perfiles.first { $0.id == activoID } ?? perfiles[0] }
        set {
            if let i = perfiles.firstIndex(where: { $0.id == newValue.id }) {
                var p = newValue
                p.ayuda.normalizar()      // sin límites activos no cambia nada
                perfiles[i] = p
            }
        }
    }

    func nuevo() {
        var p = Perfil(nombre: "Perfil \(perfiles.count + 1)")
        p.id = UUID()
        p.color = Perfil.colores[perfiles.count % Perfil.colores.count]
        perfiles.append(p)
        activoID = p.id
    }

    func duplicar() {
        var p = activo
        p.id = UUID()
        p.nombre = activo.nombre + " (copia)"
        p.color = Perfil.colores[perfiles.count % Perfil.colores.count]
        perfiles.append(p)
        activoID = p.id
    }

    func borrarActivo() {
        guard perfiles.count > 1, let i = perfiles.firstIndex(where: { $0.id == activoID }) else { return }
        perfiles.remove(at: i)
        activoID = perfiles[max(0, i - 1)].id
    }

    @Published var ajusteIndice = 0

    /// Desde el mando: dParam cambia el ajuste elegido y dValor sube o baja su valor.
    /// Devuelve lo que hay que decir en voz alta.
    func ajusteRapido(dParam: Int, dValor: Int) -> String {
        let lista = AjusteRapido.lista
        if dParam != 0 {
            ajusteIndice = (ajusteIndice + dParam + lista.count) % lista.count
            let a = lista[ajusteIndice]
            return "\(a.nombre) \(Int(a.leer(activo).rounded()))"
        }
        let a = lista[ajusteIndice]
        var p = activo
        let v = min(max(a.leer(p) + Double(dValor) * a.paso, a.rango.lowerBound), a.rango.upperBound)
        a.escribir(&p, v)
        activo = p
        return "\(Int(v.rounded()))"
    }

    static let pasoFuerza = 2.0

    /// Desde el mando: sube (+1) o baja (-1) la fuerza del anti-recoil del perfil activo.
    /// Con el progresivo, la fuerza final se mueve lo mismo. Devuelve lo que hay que decir.
    func ajustarFuerza(_ d: Int) -> String {
        var p = activo
        let delta = Double(d) * Almacen.pasoFuerza
        p.antiRecoil.vertical = min(max(p.antiRecoil.vertical + delta, 0), 100)
        if p.antiRecoil.progresivo { p.antiRecoil.verticalFinal = min(max(p.antiRecoil.verticalFinal + delta, 0), 100) }
        activo = p
        var frase = "Anti-recoil \(Int(p.antiRecoil.vertical.rounded()))"
        if p.antiRecoil.progresivo { frase += ", final \(Int(p.antiRecoil.verticalFinal.rounded()))" }
        if !p.antiRecoil.activo { frase += ", apagado" }
        return frase
    }

    /// Desde el mando: mueve la corrección lateral del anti-recoil (+1 a la derecha, -1 a la izquierda)
    func ajustarLateral(_ d: Int) -> String {
        var p = activo
        p.antiRecoil.horizontal = min(max(p.antiRecoil.horizontal + Double(d) * Almacen.pasoFuerza, -50), 50)
        activo = p
        let v = Int(p.antiRecoil.horizontal.rounded())
        var frase = v > 0 ? "Lateral derecha \(v)" : (v < 0 ? "Lateral izquierda \(-v)" : "Lateral 0")
        if !p.antiRecoil.activo { frase += ", apagado" }
        return frase
    }

    // MARK: Widgets de «En vivo» y lo que encienden y apagan

    /// Activa o desactiva una macro del perfil activo. Devuelve lo que hay que decir (nil si no existe).
    @discardableResult
    func alternarMacro(_ id: UUID) -> String? {
        guard let i = activo.macros.firstIndex(where: { $0.id == id }) else { return nil }
        activo.macros[i].activa.toggle()
        let m = activo.macros[i]
        return "\(m.nombre) \(m.activa ? "activada" : "desactivada")"
    }

    /// Si hay alguna macro activa las desactiva todas; si no, las activa todas
    @discardableResult
    func alternarMacros() -> String {
        let encender = !activo.macros.contains(where: \.activa)
        for i in activo.macros.indices { activo.macros[i].activa = encender }
        return encender ? "Macros activadas" : "Macros desactivadas"
    }

    @discardableResult
    func alternarTurbo(_ id: UUID) -> String? {
        guard let i = activo.turbos.firstIndex(where: { $0.id == id }) else { return nil }
        activo.turbos[i].activo.toggle()
        let t = activo.turbos[i]
        return "Turbo en \(t.boton.corto) \(t.activo ? "encendido" : "apagado")"
    }

    /// Igual que con las macros: si hay alguno encendido se apagan todos; si no, se encienden todos
    @discardableResult
    func alternarTurbos() -> String {
        let encender = !activo.turbos.contains(where: \.activo)
        for i in activo.turbos.indices { activo.turbos[i].activo = encender }
        return encender ? "Turbo encendido" : "Turbo apagado"
    }

    /// Añade un widget al final (si ya está, no lo repite)
    func anadirWidget(_ w: Widget) {
        guard !activo.widgets.contains(where: { $0.tipo == w.tipo && $0.objetivo == w.objetivo }) else { return }
        activo.widgets.append(w)
    }

    func quitarWidget(_ id: UUID) {
        activo.widgets.removeAll { $0.id == id }
    }

    /// Mueve un widget un puesto (-1 antes, +1 después)
    func moverWidget(_ id: UUID, _ paso: Int) {
        guard let i = activo.widgets.firstIndex(where: { $0.id == id }) else { return }
        let j = i + paso
        guard activo.widgets.indices.contains(j) else { return }
        activo.widgets.swapAt(i, j)
    }

    // MARK: Cambios que llegan del móvil

    private static let ajustesPermitidos: Set<String> = [
        "cambioPerfil", "cambioMantener", "cambioSiguiente", "cambioAnterior",
        "decirNombre", "avisosVoz", "ajusteMando", "ajusteMantener", "fuerzaMando", "fuerzaMantener",
    ]

    /// Cambia un valor del perfil activo (ruta como «antiRecoil.vertical») o de los ajustes
    /// generales (ruta «generales.decirNombre»). Devuelve un texto de error o nil si fue bien.
    func ponerRuta(_ ruta: String, _ valor: Any) -> String? {
        let partes = ruta.split(separator: ".").map(String.init)
        guard !partes.isEmpty else { return "ruta vacía" }
        do {
            if partes[0] == "generales" {
                let simple = partes.count == 2 && Almacen.ajustesPermitidos.contains(partes[1])
                let monitor = partes.count == 3 && partes[1] == "monitor"   // umbrales del monitor de la señal
                let medidor = partes.count == 3 && partes[1] == "medidor"   // medidor de tu control
                guard simple || monitor || medidor else { return "ajuste no permitido" }
                if monitor && partes[2] != "activo" {
                    guard let n = valor as? Double ?? (valor as? Int).map(Double.init), n.isFinite, n > 0 else {
                        return "el umbral tiene que ser un número mayor que 0"
                    }
                }
                var d = try JSONSerialization.jsonObject(with: JSONEncoder().encode(generales)) as? [String: Any] ?? [:]
                guard Almacen.poner(&d, partes.dropFirst(), valor) else { return "ruta desconocida: \(ruta)" }
                generales = try JSONDecoder().decode(AjustesGenerales.self, from: JSONSerialization.data(withJSONObject: d))
            } else {
                guard partes[0] != "id" else { return "ajuste no permitido" }
                var d = try JSONSerialization.jsonObject(with: JSONEncoder().encode(activo)) as? [String: Any] ?? [:]
                guard Almacen.poner(&d, partes[...], valor) else { return "ruta desconocida: \(ruta)" }
                // Lo que falte (un turbo o una macro nuevos sin los campos más recientes) va con su valor por defecto
                let completo = Rellenar.mezclar(Rellenar.json(Perfil()), d)
                var nuevo = try JSONDecoder().decode(Perfil.self, from: JSONSerialization.data(withJSONObject: completo))
                nuevo.id = activo.id
                activo = nuevo
            }
            return nil
        } catch {
            return "valor no válido para \(ruta)"
        }
    }

    private static func poner(_ d: inout [String: Any], _ ruta: ArraySlice<String>, _ valor: Any) -> Bool {
        guard let clave = ruta.first, d[clave] != nil else { return false }
        if ruta.count == 1 { d[clave] = valor; return true }
        guard var hijo = d[clave] as? [String: Any], poner(&hijo, ruta.dropFirst(), valor) else { return false }
        d[clave] = hijo
        return true
    }

    func seleccionar(_ id: UUID) { if perfiles.contains(where: { $0.id == id }) { activoID = id } }

    /// Desde el mando: pasa al patrón siguiente (+1) o anterior (-1) y devuelve su nombre
    func cambiarPatronAyuda(_ paso: Int) -> String {
        var p = activo
        let n = p.ayuda.opciones.count
        let actual = p.ayuda.opcionActual ?? (paso > 0 ? -1 : 0)
        let nuevo = ((actual + paso) % n + n) % n
        let nombre = p.ayuda.aplicarOpcion(nuevo)
        activo = p
        return nombre
    }

    // Variantes de la ayuda al apuntado (las usan la app y el móvil)
    func usarPatronAyuda(_ i: Int) {
        guard AyudaApuntado.patrones.indices.contains(i) else { return }
        var p = activo
        p.ayuda.aplicarPatron(i)
        activo = p
    }
    func usarVarianteAyuda(_ id: UUID) {
        var p = activo
        guard let v = p.ayuda.variantes.first(where: { $0.id == id }) else { return }
        p.ayuda.aplicar(v)
        activo = p
    }
    func guardarVarianteAyuda(_ nombre: String) {
        var p = activo
        p.ayuda.guardarComoVariante(nombre: nombre)
        activo = p
    }
    func actualizarVarianteAyuda() {
        var p = activo
        p.ayuda.actualizarVarianteActiva()
        activo = p
    }
    func borrarVarianteAyuda(_ id: UUID) {
        var p = activo
        p.ayuda.borrarVariante(id)
        activo = p
    }

    /// +1 = siguiente, -1 = anterior (da la vuelta). Se salta los perfiles que no entran en el ciclo.
    func cambiarPerfil(_ paso: Int) {
        guard let i = perfiles.firstIndex(where: { $0.id == activoID }) else { return }
        let n = perfiles.count
        for k in 1...n {
            let candidato = perfiles[((i + paso * k) % n + n) % n]
            if candidato.enCiclo, candidato.id != activoID { activoID = candidato.id; return }
        }
    }

    /// Crea «Corto alcance» y «Largo alcance» a partir del perfil activo (sus botones y combinaciones
    /// se mantienen). Son un punto de partida: se afinan como cualquier otro perfil.
    /// Devuelve cuántos ha añadido (0 si ya existían).
    @discardableResult
    func crearPerfilesPorSituacion() -> Int {
        let base = activo
        var anadidos = 0
        func nuevo(_ nombre: String, _ color: String, _ ajustar: (inout Perfil) -> Void) {
            guard !perfiles.contains(where: { $0.nombre == nombre }) else { return }
            var p = base
            p.id = UUID(); p.nombre = nombre; p.color = color; p.enCiclo = true
            ajustar(&p)
            perfiles.append(p)
            anadidos += 1
        }
        nuevo("Corto alcance", "#FF6A00") { p in   // pasillos: giro rápido, retroceso corto, ayuda fuerte
            p.der.sensX = 120; p.der.sensY = 120; p.der.curva = 1.0; p.der.suavizado = 0
            p.antiRecoil.vertical = 15; p.antiRecoil.progresivo = false
            p.ayuda.aplicarPatron(2)
        }
        nuevo("Largo alcance", "#00B0FF") { p in   // distancia: más fino, ráfagas largas, ayuda discreta
            p.der.sensX = 80; p.der.sensY = 80; p.der.curva = 1.6; p.der.suavizado = 15
            p.antiRecoil.vertical = 30; p.antiRecoil.progresivo = true
            p.antiRecoil.verticalFinal = 15; p.antiRecoil.transicionMs = 1200
            p.ayuda.aplicarPatron(0)
        }
        return anadidos
    }

    // MARK: Sincronización con la placa (los mismos ajustes en la placa y en las apps)

    /// Lo que se sincroniza con la placa: los perfiles, el activo y los ajustes generales, sin lo que es de
    /// cada aparato (la clave del acceso por la red y si ese acceso está encendido). Es lo mismo que en la app
    /// de escritorio (modelo.rs: ajustes_sincronizados); la revisión la calcula la placa.
    func ajustesSincronizados() -> Data {
        var d = Rellenar.json(Fichero(perfiles: perfiles, activo: activoID, generales: generales)) as? [String: Any] ?? [:]
        if var g = d["generales"] as? [String: Any] {
            g.removeValue(forKey: "clave")
            g.removeValue(forKey: "servidorMovil")
            d["generales"] = g
        }
        return (try? JSONSerialization.data(withJSONObject: d, options: [.sortedKeys])) ?? Data()
    }

    /// Pone unos ajustes sincronizados (los de la placa). Se queda con su clave y su acceso por la red.
    /// Devuelve el motivo si no se pueden leer (nil si fue bien).
    func ponerAjustesSincronizados(_ datos: Data) -> String? {
        guard var obj = (try? JSONSerialization.jsonObject(with: datos)) as? [String: Any] else { return "JSON no válido" }
        guard let lista = obj["perfiles"] as? [Any], !lista.isEmpty else { return "no hay ningún perfil" }
        if let a = obj["activo"] as? String, UUID(uuidString: a) == nil { obj.removeValue(forKey: "activo") }
        guard let completo = try? JSONSerialization.data(withJSONObject:
                Rellenar.mezclar(Rellenar.json(Fichero(perfiles: [])), obj)),
              let f = try? JSONDecoder().decode(Fichero.self, from: completo), !f.perfiles.isEmpty else {
            return "perfiles no válidos"
        }
        var g = f.generales
        g.clave = generales.clave
        g.servidorMovil = generales.servidorMovil
        perfiles = f.perfiles
        activoID = f.perfiles.contains { $0.id == f.activo } ? f.activo : f.perfiles[0].id
        generales = g
        return nil
    }

    private func cambiado() {
        guard !perfiles.isEmpty else { return }
        version += 1
        alCambiar?(activo, generales)
        guardado?.cancel()
        let f = Fichero(perfiles: perfiles, activo: activoID, generales: generales)
        let destino = archivo
        let tarea = DispatchWorkItem { Almacen.escribir(f, en: destino) }
        guardado = tarea
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.5, execute: tarea)
    }

    /// Guarda ya, sin esperar (al cerrar la app y en las pruebas)
    func guardarAhora() {
        guardado?.cancel()
        guard !perfiles.isEmpty else { return }
        Almacen.escribir(Fichero(perfiles: perfiles, activo: activoID, generales: generales), en: archivo)
    }

    private static func escribir(_ f: Fichero, en destino: URL) {
        let cod = JSONEncoder()
        cod.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let datos = try? cod.encode(f) { try? datos.write(to: destino, options: .atomic) }
    }
}

// MARK: - Resumen de lo que está activo (para «En vivo»)

/// Una función del perfil o de los ajustes generales, tal como se resume en «En vivo»
struct FuncionActiva: Equatable {
    let nombre: String
    let detalle: String
    let icono: String        // símbolo de SF Symbols (en el móvil no se usa)
    let encendida: Bool
}

enum ResumenFunciones {
    /// Lo que está configurado ahora mismo, en el orden en que se enseña. El anti-recoil y la
    /// ayuda se pueden encender y apagar desde el mando, así que su estado lo da el motor.
    static func de(_ p: Perfil, _ g: AjustesGenerales, antiRecoil: Bool, ayuda: Bool) -> [FuncionActiva] {
        var f: [FuncionActiva] = []
        func lista(_ b: [Boton]) -> String { b.map(\.corto).joined(separator: ", ") }

        if p.antiRecoil.activo || antiRecoil {
            let modo = p.antiRecoil.progresivo ? "progresivo" : "fuerza fija"
            f.append(FuncionActiva(nombre: "Anti-recoil", detalle: modo, icono: "scope", encendida: antiRecoil))
        }
        if p.ayuda.activo || ayuda {
            let forma = p.ayuda.forma == .circulo ? "círculos" : "temblor"
            f.append(FuncionActiva(nombre: "Ayuda al apuntado", detalle: "\(forma), con \(p.ayuda.boton.corto)",
                                   icono: "target", encendida: ayuda))
        }
        if !p.turbos.isEmpty {
            let d = p.turbos.map { "\($0.boton.corto) \(Int($0.hz.rounded()))/s" }.joined(separator: ", ")
            f.append(FuncionActiva(nombre: "Turbo", detalle: d, icono: "bolt", encendida: true))
        }
        let activas = p.macros.filter(\.activa)
        if !p.macros.isEmpty {
            let d = activas.isEmpty ? "ninguna activa"
                : activas.map { "\($0.nombre) (\($0.disparador.corto))" }.joined(separator: ", ")
            f.append(FuncionActiva(nombre: activas.count == 1 ? "Macro" : "Macros", detalle: d,
                                   icono: "list.bullet.rectangle", encendida: !activas.isEmpty))
        }
        let cambiados = Boton.allCases.filter { p.reasignar[$0.rawValue] != nil }
        if !cambiados.isEmpty {
            f.append(FuncionActiva(nombre: "Botones cambiados", detalle: lista(cambiados),
                                   icono: "arrow.left.arrow.right", encendida: true))
        }
        if !p.alternar.isEmpty {
            f.append(FuncionActiva(nombre: "Alternar", detalle: lista(p.alternar), icono: "switch.2", encendida: true))
        }
        let largas = Boton.allCases.filter { p.pulsacionLarga[$0.rawValue] != nil }
        if !largas.isEmpty {
            f.append(FuncionActiva(nombre: "Pulsación larga", detalle: lista(largas), icono: "hand.tap", encendida: true))
        }
        if p.intercambiarSticks {
            f.append(FuncionActiva(nombre: "Sticks intercambiados", detalle: "", icono: "arrow.triangle.swap", encendida: true))
        }
        if g.medidor.activo {
            f.append(FuncionActiva(nombre: "Mi control", detalle: "midiendo", icono: "chart.xyaxis.line", encendida: true))
        }
        if g.monitor.activo {
            f.append(FuncionActiva(nombre: "Monitor de señal", detalle: "", icono: "waveform.path.ecg", encendida: true))
        }
        return f
    }
}

// MARK: - Widgets de «En vivo»

/// Cómo se enseña un widget ahora mismo
struct EstadoWidget: Equatable, Identifiable {
    let id: UUID
    let tipo: Widget.Tipo
    let nombre: String
    let detalle: String
    let icono: String        // símbolo de SF Symbols (el móvil usa el suyo según el tipo)
    let encendido: Bool
}

enum Widgets {
    /// Lo que se puede añadir en este perfil y aún no está puesto, en orden de catálogo
    static func catalogo(_ p: Perfil) -> [Widget] {
        var c = [Widget(tipo: .antiRecoil), Widget(tipo: .ayuda)]
        if p.turbos.count > 1 { c.append(Widget(tipo: .turbos)) }
        c += p.turbos.map { Widget(tipo: .turbo, objetivo: $0.id) }
        if p.macros.count > 1 { c.append(Widget(tipo: .macros)) }
        c += p.macros.map { Widget(tipo: .macro, objetivo: $0.id) }
        c.append(Widget(tipo: .pausa))
        return c.filter { w in !p.widgets.contains { $0.tipo == w.tipo && $0.objetivo == w.objetivo } }
    }

    /// Los de siempre, para empezar con un toque
    static func basicos(_ p: Perfil) -> [Widget] {
        var b = [Widget(tipo: .antiRecoil), Widget(tipo: .ayuda)]
        if !p.macros.isEmpty { b.append(p.macros.count == 1 ? Widget(tipo: .macro, objetivo: p.macros[0].id) : Widget(tipo: .macros)) }
        if !p.turbos.isEmpty { b.append(p.turbos.count == 1 ? Widget(tipo: .turbo, objetivo: p.turbos[0].id) : Widget(tipo: .turbos)) }
        b.append(Widget(tipo: .pausa))
        return b
    }

    /// Nombre del widget para el catálogo (antes de añadirlo)
    static func nombre(_ w: Widget, _ p: Perfil) -> String {
        estado(w, p, antiRecoil: false, ayuda: false, pausado: false)?.nombre ?? "—"
    }

    /// nil si apunta a un turbo o una macro que ya no existe
    static func estado(_ w: Widget, _ p: Perfil, antiRecoil: Bool, ayuda: Bool, pausado: Bool) -> EstadoWidget? {
        func e(_ n: String, _ d: String, _ i: String, _ on: Bool) -> EstadoWidget {
            EstadoWidget(id: w.id, tipo: w.tipo, nombre: n, detalle: d, icono: i, encendido: on)
        }
        switch w.tipo {
        case .antiRecoil:
            let ar = p.antiRecoil
            let modo = ar.progresivo ? "progresivo" : "fuerza \(Int(ar.vertical.rounded()))"
            return e("Anti-recoil", modo, "scope", antiRecoil)
        case .ayuda:
            // La intensidad es el tamaño efectivo (con los límites aplicados), lo que de verdad mueve el stick
            let ef = p.ayuda.efectivos
            let tam = ef.tamano.rounded() == ef.tamano ? "\(Int(ef.tamano))" : String(format: "%.1f", ef.tamano)
            return e("Ayuda al apuntado", "\(p.ayuda.forma == .circulo ? "círculos" : "temblor") · \(tam) %", "target", ayuda)
        case .pausa:
            return e("Pausa", pausado ? "la consola recibe el mando quieto" : "el mando pasa a la consola",
                     pausado ? "pause.circle.fill" : "pause.circle", pausado)
        case .turbos:
            let n = p.turbos.filter(\.activo).count
            return e("Turbo", p.turbos.isEmpty ? "sin turbos" : "\(n) de \(p.turbos.count) encendidos", "bolt", n > 0)
        case .turbo:
            guard let t = p.turbos.first(where: { $0.id == w.objetivo }) else { return nil }
            return e("Turbo \(t.boton.corto)", "\(Int(t.hz.rounded())) pulsaciones/s", "bolt", t.activo)
        case .macros:
            let n = p.macros.filter(\.activa).count
            return e("Macros", p.macros.isEmpty ? "sin macros" : "\(n) de \(p.macros.count) activas", "list.bullet.rectangle", n > 0)
        case .macro:
            guard let m = p.macros.first(where: { $0.id == w.objetivo }) else { return nil }
            var d = "con \(m.disparador.corto)"
            if m.atajo { d += " · atajo \(m.atajoMantener.corto)+\(m.atajoPulsar.corto)" }
            return e(m.nombre, d, "list.bullet.rectangle", m.activa)
        }
    }
}
