import Foundation

// Pruebas del motor de la «Ayuda al apuntado». Se ejecutan con ./ejecutar_pruebas.sh
// (no hace falta Xcode). Comprueban que el comportamiento de los seis patrones no ha cambiado,
// los límites, las variantes, la persistencia, la ausencia de saltos y que nada cambia solo.

var total = 0, fallos = 0
func comprobar(_ ok: Bool, _ texto: String, _ detalle: @autoclosure () -> String = "") {
    total += 1
    if ok { print("  ✓ \(texto)") } else { fallos += 1; print("  ✗ \(texto)  \(detalle())") }
}
func seccion(_ t: String) { print("\n\(t)") }

/// Perfil con una variante concreta elegida a mano
func perfil(con valores: (AyudaApuntado.Forma, Double, Double, Double, Double)) -> Perfil {
    var p = perfilBaseAyuda(patron: 1)
    p.ayuda.forma = valores.0; p.ayuda.tamano = valores.1; p.ayuda.hz = valores.2
    p.ayuda.entradaMs = valores.3; p.ayuda.ceder = valores.4
    return p
}

/// Mayor salto entre dos ticks seguidos del stick derecho, sin movimiento del jugador:
/// lo que se mueve es solo lo que añade la ayuda.
func mayorSalto(_ perfil: Perfil, ticks: Int = 3000,
                cambios: [(tick: Int, cambio: (inout Perfil) -> Void)] = []) -> (maximo: Int, enTick: Int) {
    var p = perfil
    let pr = Procesador()
    var anterior: (Int, Int)?
    var mejor = (0, 0)
    for i in 0..<ticks {
        for c in cambios where c.tick == i { c.cambio(&p) }
        var e = Estado()
        if i >= 200 { e.botones = Boton.l1.bit }
        let s = pr.procesar(e, p, t: Double(i) / 1000)
        let ahora = (Int(s.rx), Int(s.ry))
        if let a = anterior {
            let d = max(abs(ahora.0 - a.0), abs(ahora.1 - a.1))
            if d > mejor.0 { mejor = (d, i) }
        }
        anterior = ahora
    }
    return mejor
}

/// Una placa falsa que habla el mismo protocolo que main/sincro.c (con su propio almacén)
final class PlacaFalsa: Canal {
    let almacen: Almacen
    var copia = Data(), entrada = Data(), esperado = 0, crc: UInt32 = 0
    var salida: [String] = []
    var conectada = true, contesta = true
    init(_ a: Almacen) { almacen = a }
    var conectado: Bool { conectada }
    static func rev(_ d: Data) -> String {
        var h: UInt64 = 0xcbf29ce484222325
        for b in d { h ^= UInt64(b); h = h &* 0x100000001b3 }
        let t = String(h, radix: 16)
        return String(repeating: "0", count: 16 - t.count) + t
    }
    @discardableResult func linea(_ l: String) -> Bool {
        guard contesta else { return true }
        let p = l.split(separator: " ").map(String.init)
        guard p.count >= 2 else { return true }
        switch p[1] {
        case "rev":
            copia = almacen.ajustesSincronizados()
            salida.append("@AJ REV \(PlacaFalsa.rev(copia)) \(copia.count) \(Sincro.hex8(Sincro.crc32(copia)))")
        case "leer":
            let d = Int(p[2])!, fin = min(d + Sincro.trozo, copia.count)
            salida.append("@AJ T \(d) \(copia.subdata(in: d..<fin).base64EncodedString())")
        case "poner":
            esperado = Int(p[2])!; crc = UInt32(p[3], radix: 16)!; entrada = Data()
            salida.append("@AJ LISTO")
        case "trozo":
            if Int(p[2])! == entrada.count { entrada.append(Data(base64Encoded: p[3])!) }
            salida.append("@AJ ACK \(entrada.count)")
        case "fin":
            guard Sincro.crc32(entrada) == crc, almacen.ponerAjustesSincronizados(entrada) == nil else {
                salida.append("@AJ ERROR"); return true
            }
            salida.append("@AJ OK \(PlacaFalsa.rev(almacen.ajustesSincronizados()))")
        default: break
        }
        return true
    }
    func respuestas() -> [String] { let r = salida; salida = []; return r }
}

func carpetaTemporal() -> URL {
    let d = FileManager.default.temporaryDirectory.appendingPathComponent("sincro-\(UUID().uuidString)")
    try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
    return d
}

/// Da vueltas hasta que esté al día (o 20 s simulados). Devuelve los avisos.
@discardableResult
func hastaAlDia(_ s: Sincro, _ c: PlacaFalsa, _ a: Almacen, _ t: inout Double) -> [String] {
    var avisos: [String] = []
    for _ in 0..<20_000 {
        t += 0.001
        if let x = s.vuelta(c, a, t: t) { avisos.append(x) }
        if s.estado == "al día" && s.fase != .preguntando { break }
    }
    return avisos
}

func copias(_ dir: URL, _ texto: String) -> [URL] {
    ((try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? [])
        .filter { $0.lastPathComponent.contains(texto) }
}

@main struct Pruebas {
    static func main() {
        let huella = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "pruebas/huella_ayuda.json"

        // 1 ──────────────────────────────────────────────────────────────
        seccion("1. Sin usar las opciones nuevas, los seis patrones se comportan exactamente igual que antes")
        if let datos = try? Data(contentsOf: URL(fileURLWithPath: huella)),
           let d = try? JSONSerialization.jsonObject(with: datos) as? [String: String] {
            for (i, patron) in AyudaApuntado.patrones.enumerated() {
                let esperado = d[patron.nombre].flatMap { Data(base64Encoded: $0) }.map { [UInt8]($0) } ?? []
                let actual = escenarioAyuda(perfilBaseAyuda(patron: i))
                let distintos = zip(esperado, actual).filter { $0 != $1 }.count
                comprobar(esperado.count == actual.count && distintos == 0,
                          "\(patron.nombre): 3000 ticks idénticos (\(actual.count) bytes)",
                          "\(distintos) bytes distintos de \(esperado.count)")
            }
        } else {
            comprobar(false, "no se pudo leer la huella \(huella)")
        }

        // 2 ──────────────────────────────────────────────────────────────
        seccion("2. Límites mínimo y máximo")
        var a = AyudaApuntado()
        a.tamano = 500; a.hz = 999; a.entradaMs = 9999
        comprobar(a.efectivos.tamano == 500 && a.efectivos.hz == 999 && a.efectivos.entradaMs == 9999 && !a.limitado,
                  "sin activar los límites no se recorta nada")
        var sinTocar = a; sinTocar.normalizar()
        comprobar(sinTocar == a, "normalizar sin límites no cambia nada")
        a.limites.activos = true
        a.limites.tamanoMin = 4; a.limites.tamanoMax = 10
        a.limites.hzMin = 6; a.limites.hzMax = 14
        a.limites.entradaMin = 100; a.limites.entradaMax = 300
        comprobar(a.efectivos.tamano == 10 && a.efectivos.hz == 14 && a.efectivos.entradaMs == 300 && a.limitado,
                  "con límites activos recorta por arriba")
        a.tamano = 1; a.hz = 1; a.entradaMs = 0
        comprobar(a.efectivos.tamano == 4 && a.efectivos.hz == 6 && a.efectivos.entradaMs == 100, "y por abajo")
        a.tamano = 7; a.hz = 9; a.entradaMs = 200
        comprobar(!a.limitado && a.efectivos.tamano == 7 && a.efectivos.hz == 9 && a.efectivos.entradaMs == 200,
                  "dentro del rango no cambia")
        a.limites.tamanoMin = 12; a.limites.tamanoMax = 3   // mínimo mayor que máximo: se interpreta al revés
        comprobar(a.efectivos.tamano == 7, "mínimo y máximo intercambiados se tratan igual")
        a.limites.tamanoMin = 4; a.limites.tamanoMax = 10
        a.tamano = 99; a.normalizar()
        comprobar(a.tamano == 10, "normalizar deja el valor guardado dentro del rango")
        var b = AyudaApuntado(); b.limites.activos = true; b.limites.tamanoMin = 5; b.limites.tamanoMax = 6
        b.aplicarPatron(2)      // Círculos fuertes: 14 %
        comprobar(b.tamano == 6, "elegir un patrón con límites activos lo recorta (14 % -> 6 %)", "\(b.tamano)")
        comprobar(b.indicePatron == 2, "y sigue reconociéndose como ese patrón", "\(String(describing: b.indicePatron))")
        // El motor usa lo mismo que el perfil: 20 % con tope de 10 % == 10 % sin límites
        var limitado = perfilBaseAyuda(patron: 1)
        limitado.ayuda.tamano = 20; limitado.ayuda.limites.activos = true; limitado.ayuda.limites.tamanoMax = 10
        var libre = perfilBaseAyuda(patron: 1); libre.ayuda.tamano = 10
        comprobar(escenarioAyuda(limitado) == escenarioAyuda(libre), "el motor aplica los límites (20 % con tope 10 % == 10 %)")

        // 3 ──────────────────────────────────────────────────────────────
        seccion("3. Variantes personalizadas y selección manual")
        var v = AyudaApuntado()
        v.aplicarPatron(4)                      // Temblor medio
        let guardada = v.guardarComoVariante(nombre: "  Mi temblor  ")
        comprobar(guardada.nombre == "Mi temblor" && guardada.base == 4 && guardada.forma == .temblor,
                  "guardar una variante recoge el nombre y el patrón de origen")
        comprobar(v.varianteActiva == guardada.id && !v.varianteModificada, "queda elegida y sin modificar")
        v.tamano = 9
        comprobar(v.varianteModificada, "si se tocan los valores, se ve que está modificada")
        v.actualizarVarianteActiva()
        comprobar(!v.varianteModificada && v.variantes[0].tamano == 9, "«actualizar» pone los valores actuales en la variante")
        v.aplicarPatron(0)
        comprobar(v.varianteActiva == nil && v.forma == .circulo && v.tamano == 4, "elegir un patrón deja sin variante elegida")
        v.aplicar(v.variantes[0])
        comprobar(v.tamano == 9 && v.forma == .temblor && v.varianteActiva == v.variantes[0].id, "elegir la variante pone sus valores")
        var w = AyudaApuntado()
        w.guardarComoVariante(nombre: "")
        comprobar(w.variantes[0].nombre == "Variante 1", "sin nombre se le da uno")
        w.borrarVariante(w.variantes[0].id)
        comprobar(w.variantes.isEmpty && w.varianteActiva == nil, "borrar quita la variante y la elección")
        // El motor con una variante == el motor con esos mismos valores puestos a mano
        var conVariante = perfilBaseAyuda(patron: 0)
        conVariante.ayuda.tamano = 11; conVariante.ayuda.hz = 7; conVariante.ayuda.entradaMs = 220; conVariante.ayuda.ceder = 60
        conVariante.ayuda.forma = .temblor
        conVariante.ayuda.guardarComoVariante(nombre: "X")
        conVariante.ayuda.aplicarPatron(1)
        conVariante.ayuda.aplicar(conVariante.ayuda.variantes[0])
        let aMano = perfil(con: (.temblor, 11, 7, 220, 60))
        comprobar(escenarioAyuda(conVariante) == escenarioAyuda(aMano), "una variante da exactamente el mismo resultado que sus valores a mano")

        // 4 ──────────────────────────────────────────────────────────────
        seccion("4. Elegir con el mando: los seis patrones y luego las variantes, de uno en uno")
        let temporal = FileManager.default.temporaryDirectory.appendingPathComponent("puente-pruebas-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: temporal, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporal) }
        let archivo = temporal.appendingPathComponent("perfiles.json")
        let almacen = Almacen(archivo: archivo)
        var base = almacen.activo
        base.ayuda.aplicarPatron(5)
        base.ayuda.guardarComoVariante(nombre: "Uno"); base.ayuda.aplicarPatron(5)
        base.ayuda.tamano = 6; base.ayuda.guardarComoVariante(nombre: "Dos"); base.ayuda.aplicarPatron(5)
        almacen.activo = base
        var nombres: [String] = []
        for _ in 0..<4 { nombres.append(almacen.cambiarPatronAyuda(1)) }
        comprobar(nombres == ["Uno", "Dos", "Círculos discretos", "Círculos medios"], "→ desde el último patrón: \(nombres)")
        nombres = []
        for _ in 0..<3 { nombres.append(almacen.cambiarPatronAyuda(-1)) }
        comprobar(nombres == ["Círculos discretos", "Dos", "Uno"], "← hacia atrás: \(nombres)")
        almacen.usarPatronAyuda(3)
        comprobar(almacen.activo.ayuda.indicePatron == 3 && almacen.activo.ayuda.varianteActiva == nil,
                  "elegir un patrón desde el móvil lo aplica y deja sin variante elegida")
        almacen.usarPatronAyuda(99)
        comprobar(almacen.activo.ayuda.indicePatron == 3, "un patrón que no existe se ignora")
        let sinVariantes = Almacen(archivo: temporal.appendingPathComponent("otro.json"))
        sinVariantes.activoID = sinVariantes.perfiles[0].id
        var ps: [String] = []
        for _ in 0..<7 { ps.append(sinVariantes.cambiarPatronAyuda(1)) }
        comprobar(ps == ["Círculos fuertes", "Temblor discreto", "Temblor medio", "Temblor fuerte", "Círculos discretos", "Círculos medios", "Círculos fuertes"],
                  "sin variantes recorre solo los seis patrones de siempre")

        // 5 ──────────────────────────────────────────────────────────────
        seccion("5. Persistencia")
        var guardar = almacen.activo
        guardar.ayuda.limites.activos = true
        guardar.ayuda.limites.tamanoMin = 3; guardar.ayuda.limites.tamanoMax = 12
        guardar.ayuda.limites.hzMax = 20; guardar.ayuda.limites.entradaMin = 50
        guardar.ayuda.aplicar(guardar.ayuda.variantes[1])
        almacen.activo = guardar
        almacen.guardarAhora()
        let recargado = Almacen(archivo: archivo)
        comprobar(recargado.perfiles == almacen.perfiles, "al volver a abrir, los perfiles son idénticos")
        comprobar(recargado.activo.ayuda.limites == guardar.ayuda.limites && recargado.activo.ayuda.variantes.count == 2
                  && recargado.activo.ayuda.varianteActiva == almacen.activo.ayuda.varianteActiva,
                  "límites, variantes y la variante elegida se conservan")
        // Un archivo guardado antes de existir estas opciones sigue cargando y se comporta igual
        if var viejo = (try? JSONSerialization.jsonObject(with: Data(contentsOf: archivo))) as? [String: Any],
           var perfiles = viejo["perfiles"] as? [[String: Any]] {
            for i in perfiles.indices {
                var ay = perfiles[i]["ayuda"] as? [String: Any] ?? [:]
                for k in ["limites", "variantes", "varianteActiva"] { ay[k] = nil }
                perfiles[i]["ayuda"] = ay
            }
            viejo["perfiles"] = perfiles
            let archivoViejo = temporal.appendingPathComponent("viejo.json")
            try? JSONSerialization.data(withJSONObject: viejo).write(to: archivoViejo)
            let cargado = Almacen(archivo: archivoViejo)
            let ay = cargado.activo.ayuda
            comprobar(!ay.limites.activos && ay.variantes.isEmpty && ay.varianteActiva == nil,
                      "un archivo antiguo, sin las opciones nuevas, carga con los valores por defecto")
            comprobar(cargado.perfiles.count == almacen.perfiles.count, "y conserva todos los perfiles")
        } else {
            comprobar(false, "no se pudo preparar el archivo antiguo")
        }
        comprobar(almacen.ponerRuta("ayuda.limites.hzMax", 8) == nil && almacen.activo.ayuda.limites.hzMax == 8,
                  "se cambia un límite por ruta (como hace el móvil)")
        comprobar(almacen.ponerRuta("ayuda.limites.hzMax", "mucho") != nil, "un valor de tipo malo se rechaza")
        almacen.guardarAhora()

        // 6 ──────────────────────────────────────────────────────────────
        seccion("6. Sin saltos bruscos en el stick (salto máximo entre dos ticks de 1 ms, en unidades de 0-255)")
        for (i, p) in AyudaApuntado.patrones.enumerated() {
            let s = mayorSalto(perfilBaseAyuda(patron: i))
            comprobar(s.maximo <= 3, "\(p.nombre): salto máximo \(s.maximo) (límite 3)", "en el tick \(s.enTick)")
        }
        // Cambios hechos a mano con la ayuda en marcha: se enlazan sin saltos
        let destinos: [(String, (inout Perfil) -> Void)] = [
            ("de Círculos discretos a Temblor fuerte", { $0.ayuda.aplicarPatron(5) }),
            ("de tamaño 8 % a 14 %", { $0.ayuda.tamano = 14 }),
            ("de 12 a 16 por segundo", { $0.ayuda.hz = 16 }),
            ("de entrada 150 a 600 ms", { $0.ayuda.entradaMs = 600 }),
            ("de ceder 70 % a 0 %", { $0.ayuda.ceder = 0 }),
            ("activar límites que recortan", { $0.ayuda.limites.activos = true; $0.ayuda.limites.tamanoMax = 3; $0.ayuda.limites.hzMax = 5 }),
            ("elegir una variante muy distinta", {
                var v = VarianteAyuda(); v.forma = .temblor; v.tamano = 25; v.hz = 30; v.entradaMs = 50; v.ceder = 10
                $0.ayuda.variantes = [v]; $0.ayuda.aplicar(v) }),
        ]
        /// Pendiente natural de un patrón: lo más rápido que se mueve el stick en régimen (unidades por ms)
        func pendiente(_ p: Perfil) -> Double {
            let e = p.ayuda.efectivos
            return (e.tamano / 100 * 127.5) * 2 * .pi * e.hz / 1000
        }
        for (nombre, cambio) in destinos {
            let antes = perfilBaseAyuda(patron: 0)
            var despues = antes; cambio(&despues)
            let tope = Int(max(pendiente(antes), pendiente(despues)).rounded(.up)) + 1
            let s = mayorSalto(antes, cambios: [(1500, cambio)])
            comprobar(s.maximo <= tope, "cambio a mano \(nombre): salto máximo \(s.maximo) (tope \(tope) = pendiente natural + 1)", "en el tick \(s.enTick)")
        }
        // La prueba detecta el problema: un cambio sin enlace (misma fórmula, otra frecuencia y amplitud) sí salta
        var peor = 0.0
        for k in 0..<1000 {
            let t = 1.3 + Double(k) * 0.0007
            peor = max(peor, abs(25 / 100 * 127.5 * sin(2 * .pi * 30 * t) - 4 / 100 * 127.5 * sin(2 * .pi * 8 * t)))
        }
        comprobar(peor > 10, "sin enlace, ese mismo cambio daría saltos de hasta \(Int(peor)) unidades (la prueba los detectaría)")

        // 7 ──────────────────────────────────────────────────────────────
        seccion("7. Nada cambia solo: los valores efectivos dependen únicamente de la configuración")
        for (i, p) in AyudaApuntado.patrones.enumerated() {
            let pr = Procesador()
            let perf = perfilBaseAyuda(patron: i)
            var primero: DiagnosticoAyuda?
            var iguales = true, activos = 0
            for k in 0..<6000 {
                var e = Estado(); e.botones = Boton.l1.bit
                _ = pr.procesar(e, perf, t: Double(k) / 1000)
                let d = pr.diagnostico
                if d.aplicando { activos += 1 }
                if primero == nil { primero = d }
                if let f = primero, (d.tamano, d.hz, d.entradaMs, d.ceder, d.forma) != (f.tamano, f.hz, f.entradaMs, f.ceder, f.forma) { iguales = false }
            }
            comprobar(iguales && activos == 6000 && primero?.tamano == p.tamano && primero?.hz == p.hz,
                      "\(p.nombre): tamaño, velocidad, entrada y cesión constantes durante 6000 ticks")
        }
        let r1 = escenarioAyuda(perfilBaseAyuda(patron: 3)), r2 = escenarioAyuda(perfilBaseAyuda(patron: 3))
        comprobar(r1 == r2, "dos ejecuciones iguales dan exactamente los mismos bytes (no hay azar)")
        let pr = Procesador()
        var diag: [DiagnosticoAyuda] = []
        for k in 0..<600 {
            var e = Estado(); e.botones = Boton.l1.bit
            _ = pr.procesar(e, perfilBaseAyuda(patron: 1), t: Double(k) / 1000)
            diag.append(pr.diagnostico)
        }
        comprobar(diag[0].amplitud == 0 && diag[0].rampa == 0 && diag[150].rampa > 0.99 && diag.allSatisfy { !$0.enTransicion },
                  "el diagnóstico refleja la entrada suave (0 al empezar, 1 a los 150 ms) y que no hay transición")
        comprobar(diag.allSatisfy { hypot($0.offX, $0.offY) <= $0.amplitud + 1e-12 }, "la amplitud del diagnóstico acota lo que se suma al stick")

        // 8 ──────────────────────────────────────────────────────────────
        seccion("8. Monitor de la señal (solo lectura)")
        let lm = LimitesMonitor()
        /// Lo que la ayuda suma al stick, muestreado cada 10 ms como en la app
        func senalReal(_ perfil: Perfil, segundos: Double = 3) -> ([Float], [Float]) {
            let pr = Procesador()
            var x: [Float] = [], y: [Float] = []
            for k in 0..<Int(segundos * 1000) {
                var e = Estado(); e.botones = Boton.l1.bit
                _ = pr.procesar(e, perfil, t: Double(k) / 1000)
                if k % 10 == 0 { x.append(Float(pr.diagnostico.offX)); y.append(Float(pr.diagnostico.offY)) }
            }
            return (x, y)
        }
        for (i, p) in AyudaApuntado.patrones.enumerated() {
            let (x, y) = senalReal(perfilBaseAyuda(patron: i))
            let inf = MonitorSenales.analizar(x: x, y: y, dt: 0.01, limites: lm)
            comprobar(inf.estado == .ok && inf.eventos.isEmpty,
                      "\(p.nombre): señal real correcta con los umbrales de fábrica (vel. máx \(String(format: "%.1f", inf.metricas.maxVelocidad))/s)",
                      "\(inf.estado) \(inf.eventos.first?.motivo ?? "")")
        }
        // Señal limpia preparada a mano: un seno lento
        let lx = (0..<300).map { Float(0.1 * sin(2 * Double.pi * 2 * Double($0) * 0.01)) }
        let ly = [Float](repeating: 0, count: 300)
        let limpio = MonitorSenales.analizar(x: lx, y: ly, dt: 0.01, limites: lm)
        comprobar(limpio.estado == .ok, "un seno lento y suave da «Correcta»")
        func con(_ cambio: (inout [Float]) -> Void) -> MonitorSenales.Informe {
            var s = lx; cambio(&s)
            return MonitorSenales.analizar(x: s, y: ly, dt: 0.01, limites: lm)
        }
        var inf = con { $0[100] = .nan }
        comprobar(inf.estado == .anomalia && inf.eventos.contains { $0.tipo == .noNumerico && $0.indice == 100 } && inf.metricas.noNumericos == 1,
                  "detecta un valor no numérico en la muestra 100")
        inf = con { $0[50] = 1.5 }
        comprobar(inf.estado == .anomalia && inf.eventos.contains { $0.tipo == .fueraDeRango && $0.indice == 50 }, "detecta un valor fuera de rango (1,5)")
        inf = con { for k in 150..<300 { $0[k] += 0.5 } }
        comprobar(inf.estado == .anomalia && inf.eventos.contains { $0.tipo == .salto && $0.indice == 150 }, "detecta un escalón de 0,5 en la muestra 150")
        var rapido = MonitorSenales.analizar(x: (0..<300).map { Float(0.9 * sin(2 * Double.pi * 8 * Double($0) * 0.01)) }, y: ly, dt: 0.01, limites: lm)
        comprobar(rapido.estado >= .advertencia && rapido.eventos.contains { $0.tipo == .velocidad } && !rapido.eventos.contains { $0.tipo == .fueraDeRango },
                  "un seno grande y rápido da advertencia de velocidad, no anomalía de rango (vel. \(Int(rapido.metricas.maxVelocidad))/s)")
        rapido = MonitorSenales.analizar(x: (0..<300).map { Float($0 % 2 == 0 ? 0.2 : -0.2) }, y: ly, dt: 0.01, limites: lm)
        comprobar(rapido.eventos.contains { $0.tipo == .oscilacion } && rapido.eventos.contains { $0.tipo == .aceleracion },
                  "una señal que cambia de sentido en cada muestra da advertencia de oscilación y aceleración")
        let solo = MonitorSenales.analizar(x: (0..<300).map { Float($0 % 2 == 0 ? 0.2 : -0.2) }, y: ly, dt: 0.01,
                                           limites: { var l = lm; l.maxSalto = 1; return l }())
        comprobar(solo.estado == .advertencia, "esa misma señal, con salto permitido, es advertencia y no anomalía")
        let muchos = MonitorSenales.analizar(x: [Float](repeating: 3, count: 1000), y: [Float](repeating: 3, count: 1000), dt: 0.01, limites: lm)
        comprobar(muchos.eventos.filter { $0.tipo != .oscilacion }.count == MonitorSenales.maxEventos && muchos.eventosOmitidos == 2000 - MonitorSenales.maxEventos,
                  "con una señal muy mala guarda 50 eventos y cuenta el resto (\(muchos.eventosOmitidos) omitidos)")
        let vacio = MonitorSenales.analizar(x: [], y: [], dt: 0.01, limites: lm)
        comprobar(vacio.estado == .ok && vacio.metricas.muestras == 0, "sin muestras no falla")
        // No modifica: mismas entradas, mismo informe, y las entradas siguen igual
        let copia = lx
        let a1 = MonitorSenales.analizar(x: lx, y: ly, dt: 0.01, limites: lm), a2 = MonitorSenales.analizar(x: lx, y: ly, dt: 0.01, limites: lm)
        comprobar(a1 == a2 && lx == copia, "no modifica la señal y da siempre el mismo informe")
        // No toca la salida del mando: el motor da los mismos bytes con el monitor activo
        let alm = Almacen(archivo: temporal.appendingPathComponent("monitor.json"))
        alm.generales.monitor.activo = true
        comprobar(escenarioAyuda(perfilBaseAyuda(patron: 2)) == escenarioAyuda(perfilBaseAyuda(patron: 2)),
                  "la salida del motor no depende del monitor (no está en el bucle del mando)")
        // Persistencia
        alm.generales.monitor.maxSalto = 0.12; alm.generales.monitor.maxVelocidad = 33
        alm.guardarAhora()
        let rel = Almacen(archivo: temporal.appendingPathComponent("monitor.json"))
        comprobar(rel.generales.monitor == alm.generales.monitor, "los umbrales del monitor se guardan y se recuperan")
        comprobar(Almacen(archivo: archivo).generales.monitor == LimitesMonitor(), "un archivo sin monitor carga con los umbrales de fábrica")
        // Cambios por ruta, como los manda el móvil
        comprobar(rel.ponerRuta("generales.monitor.maxVelocidad", 40) == nil && rel.generales.monitor.maxVelocidad == 40,
                  "el móvil cambia un umbral por ruta (velocidad máxima 40)")
        comprobar(rel.ponerRuta("generales.monitor.activo", false) == nil && !rel.generales.monitor.activo, "y el interruptor")
        comprobar(rel.ponerRuta("generales.monitor.maxSalto", 0) != nil && rel.ponerRuta("generales.monitor.maxSalto", -1) != nil
                  && rel.ponerRuta("generales.monitor.maxSalto", "mucho") != nil && rel.generales.monitor.maxSalto == 0.12,
                  "rechaza umbrales 0, negativos o de tipo malo y deja el anterior")
        comprobar(rel.ponerRuta("generales.monitor.inventado", 3) != nil && rel.ponerRuta("generales.clave", "X") != nil,
                  "rechaza campos que no existen y la clave")
        comprobar(rel.ponerRuta("generales.decirNombre", false) == nil && !rel.generales.decirNombre
                  && rel.ponerRuta("generales.cambioMantener", "ps") == nil && rel.generales.cambioMantener == .ps,
                  "los demás ajustes generales se siguen cambiando por ruta como antes")
        rel.guardarAhora()
        comprobar(Almacen(archivo: temporal.appendingPathComponent("monitor.json")).generales.monitor == rel.generales.monitor,
                  "los cambios por ruta también se guardan")
        // Rendimiento: un millón de muestras por eje
        let grande = (0..<1_000_000).map { Float(0.1 * sin(Double($0) * 0.05)) }
        let inicio = Date()
        let infG = MonitorSenales.analizar(x: grande, y: grande, dt: 0.01, limites: lm)
        let ms = Date().timeIntervalSince(inicio) * 1000
        // Se comprueban también las métricas, para que el compilador no pueda saltarse el cálculo
        let esperadaVel = 0.1 * 0.05 / 0.01   // pendiente máxima del seno de prueba (/s)
        comprobar(abs(infG.metricas.maxVelocidad - esperadaVel) < 0.01 && abs(infG.metricas.maxAbs - 0.1) < 1e-4,
                  "las métricas del análisis grande son las esperadas (vel. máx \(String(format: "%.4f", infG.metricas.maxVelocidad))/s)")
        comprobar(infG.metricas.muestras == 1_000_000 && ms < 1000,
                  "analiza 1 000 000 de muestras por eje en \(Int(ms)) ms (la app analiza 200, dos veces por segundo)")

        // 9 ──────────────────────────────────────────────────────────────
        seccion("9. Medidor de tu control")
        // Ráfaga de 1 s: empieza a bajar a los 150 ms, baja un 30 % estable y se desvía un 5 % a la derecha
        let n = 100
        var bx = [Float](repeating: 0.05, count: n), ba = [Float](repeating: 0, count: n)
        for i in 15..<n { ba[i] = 0.30 }
        var r = AnalisisRafaga.analizar(x: bx, abajo: ba)
        comprobar(r.muestras == 100 && r.duracionMs == 1000, "una ráfaga de 100 muestras dura 1000 ms")
        comprobar(r.reaccionMs == 150, "reacción: empieza a bajar a los 150 ms", "\(String(describing: r.reaccionMs))")
        comprobar(abs(r.bajadaMedia - 30) < 1e-4 && r.constancia < 1e-3, "bajada media 30 % y constante (\(String(format: "%.4f", r.constancia)))")
        comprobar(abs(r.lateralMedio - 5) < 1e-4 && abs(r.lateralMax - 5) < 1e-4, "desvío lateral 5 % a la derecha")
        comprobar(r.tirones == 1, "el paso de 0 a 30 % de golpe cuenta como un tirón", "\(r.tirones)")
        // Sin bajar el stick
        r = AnalisisRafaga.analizar(x: [Float](repeating: 0, count: 50), abajo: [Float](repeating: 0, count: 50))
        comprobar(r.reaccionMs == nil && r.bajadaMedia == 0 && r.tirones == 0, "sin bajar el stick: sin reacción y bajada 0")
        // Bajada irregular: alterna 10 % y 40 %
        ba = (0..<n).map { $0 % 2 == 0 ? 0.10 : 0.40 }; bx = [Float](repeating: 0, count: n)
        let irregular = AnalisisRafaga.analizar(x: bx, abajo: ba)
        let suave = AnalisisRafaga.analizar(x: bx, abajo: (0..<n).map { _ in 0.25 })
        comprobar(abs(irregular.bajadaMedia - 25) < 0.2 && irregular.constancia > 14 && suave.constancia < 1e-3,
                  "una bajada irregular tiene la misma media (25 %) pero mucha menos constancia (\(String(format: "%.1f", irregular.constancia)) frente a 0)")
        comprobar(irregular.temblor > 50 && irregular.tirones > 90 && suave.temblor == 0, "y mucho más temblor y tirones")
        comprobar(AnalisisRafaga.analizar(x: [], abajo: []).muestras == 0, "una ráfaga vacía no falla")

        // Grabación: segmenta ráfagas con el botón de disparar, a una muestra cada 10 ms
        let grab = GrabadorRafagas()
        var terminadas: [([Float], [Float], String)] = []
        grab.alTerminar = { terminadas.append(($0, $1, $2)) }
        var cfg = ConfigMedidor(); cfg.activo = true; cfg.disparar = .r1; cfg.apuntar = .l1
        func jugar(_ desde: Int, _ hasta: Int, apuntando: Bool = true, ry: UInt8 = 166) {
            for k in desde..<hasta {
                var e = Estado(); e.botones = Boton.r1.bit | (apuntando ? Boton.l1.bit : 0); e.ry = ry
                grab.tick(e, t: Double(k) / 1000, config: cfg, perfil: "P")
            }
            grab.tick(Estado(), t: Double(hasta) / 1000, config: cfg, perfil: "P")
        }
        jugar(0, 600)
        comprobar(terminadas.count == 1 && terminadas[0].0.count == 60 && abs(terminadas[0].1[0] - Float((166 - 127.5) / 127.5)) < 1e-6
                  && terminadas[0].2 == "P", "600 ms disparando = una ráfaga de 60 muestras con tu stick")
        jugar(1000, 1100)
        comprobar(terminadas.count == 1, "una ráfaga de 100 ms es demasiado corta y no se cuenta")
        cfg.soloApuntando = true
        jugar(2000, 2500, apuntando: false)
        comprobar(terminadas.count == 1, "con «solo apuntando», disparar sin apuntar no cuenta")
        jugar(3000, 3500, apuntando: true)
        comprobar(terminadas.count == 2, "y apuntando sí")
        var eGat = Estado(); eGat.r2 = 200
        comprobar(GrabadorRafagas.pulsado(eGat, .r2) && !GrabadorRafagas.pulsado(Estado(), .r2), "con R2 cuenta el gatillo analógico")
        // El medidor no está en el procesado: la salida del motor no cambia
        comprobar(escenarioAyuda(perfilBaseAyuda(patron: 1)) == escenarioAyuda(perfilBaseAyuda(patron: 1)), "el procesado no depende del medidor")
        // Sin reservar memoria por tick: un millón de ticks de ráfaga larga
        let grab2 = GrabadorRafagas(); var cuenta = 0
        grab2.alTerminar = { x, _, _ in cuenta += x.count }
        let t0 = Date()
        var eL = Estado(); eL.botones = Boton.r2.bit; eL.r2 = 255
        for k in 0..<1_000_000 { eL.ry = UInt8(128 + k % 60); grab2.tick(eL, t: Double(k) / 1000, config: ConfigMedidor(), perfil: "") }
        grab2.tick(Estado(), t: 1000, config: ConfigMedidor(), perfil: "")
        let msGrab = Date().timeIntervalSince(t0) * 1000
        comprobar(cuenta == GrabadorRafagas.capacidad && msGrab < 500,
                  "1 000 000 de ticks en \(Int(msGrab)) ms; una ráfaga de 1000 s se corta en \(GrabadorRafagas.capacidad) muestras (30 s)")

        // Historial y persistencia
        let fMed = temporal.appendingPathComponent("medidor.json")
        let med = MedidorControl(archivo: fMed)
        let ayer = Date().addingTimeInterval(-86400)
        med.anadir(AnalisisRafaga.analizar(x: [Float](repeating: 0.05, count: 100), abajo: (0..<100).map { $0 < 30 ? 0 : 0.3 }, perfil: "A", fecha: ayer))
        med.anadir(AnalisisRafaga.analizar(x: [Float](repeating: -0.02, count: 80), abajo: (0..<80).map { $0 < 10 ? 0 : 0.2 }, perfil: "B"))
        med.guardarAhora()
        let med2 = MedidorControl(archivo: fMed)
        comprobar(med2.rafagas == med.rafagas && med2.rafagas.count == 2, "el historial se guarda y se recupera igual")
        comprobar(med2.porDia.count == 2 && med2.porDia[0].media.rafagas == 1, "agrupa por día (hoy primero)")
        let m = AnalisisRafaga.media(med2.rafagas)
        comprobar(m.reaccionMs == 200 && abs(m.bajada - 25) < 1e-4, "la media de reacción (300 y 100 ms) es 200 ms y la de bajada 25 %")
        let obs = AnalisisRafaga.observaciones([AnalisisRafaga.analizar(x: [Float](repeating: 0.08, count: 60), abajo: [Float](repeating: 0, count: 60))])
        comprobar(obs.contains { $0.contains("derecha") } && obs.contains { $0.contains("no llegaste") }, "las observaciones señalan el desvío a la derecha y que no bajaste")
        med2.borrarTodo(); med2.guardarAhora()
        comprobar(MedidorControl(archivo: fMed).rafagas.isEmpty, "borrar el historial también se guarda")
        for _ in 0..<(MedidorControl.maxGuardadas + 5) { med2.anadir(ResumenRafaga()) }
        comprobar(med2.rafagas.count == MedidorControl.maxGuardadas, "guarda como mucho \(MedidorControl.maxGuardadas) ráfagas")
        // Ajustes del medidor: en los generales, cambiables por ruta (como el móvil)
        let almM = Almacen(archivo: temporal.appendingPathComponent("med-ajustes.json"))
        comprobar(almM.ponerRuta("generales.medidor.activo", true) == nil && almM.ponerRuta("generales.medidor.disparar", "r1") == nil
                  && almM.generales.medidor.activo && almM.generales.medidor.disparar == .r1, "se activan y eligen botones por ruta")
        comprobar(almM.ponerRuta("generales.medidor.disparar", "nada") != nil && almM.ponerRuta("generales.medidor.otro", 1) != nil,
                  "rechaza botones y campos que no existen")
        almM.guardarAhora()
        comprobar(Almacen(archivo: temporal.appendingPathComponent("med-ajustes.json")).generales.medidor == almM.generales.medidor,
                  "los ajustes del medidor se guardan")
        comprobar(Almacen(archivo: archivo).generales.medidor == ConfigMedidor(), "un archivo antiguo carga el medidor apagado")

        // 10 ─────────────────────────────────────────────────────────────
        seccion("10. Anti-recoil: fuerza fija, y los perfiles que tenían un patrón siguen cargando")
        do {
            /// `ms` ticks disparando y apuntando (gatillos a tope); stick derecho de salida (Y arriba) en cada ms
            func rafaga(_ p: Perfil, ms: Int = 1500) -> [(x: Double, y: Double)] {
                let pr = Procesador()
                return (0..<ms).map { i in
                    var e = Estado()
                    e.botones = Boton.l2.bit | Boton.r2.bit; e.l2 = 255; e.r2 = 255
                    let s = pr.procesar(e, p, t: Double(i) / 1000)
                    return ((Double(s.rx) - 127.5) / 127.5, -(Double(s.ry) - 127.5) / 127.5)
                }
            }
            func iguales(_ a: [(x: Double, y: Double)], _ b: [(x: Double, y: Double)]) -> Bool {
                a.count == b.count && zip(a, b).allSatisfy { $0.x == $1.x && $0.y == $1.y }
            }
            let paso = 1 / 127.5 + 1e-9      // un paso del stick (0-255)
            var fijo = Perfil()
            fijo.antiRecoil.activo = true
            fijo.antiRecoil.vertical = 20
            let rf = rafaga(fijo)
            comprobar(abs(rf[1000].y + 0.2) <= paso && abs(rf[1000].x) <= paso, "fuerza fija del 20 %: el stick baja un 20 %")
            var conLateral = fijo
            conLateral.antiRecoil.horizontal = 10
            comprobar(abs(rafaga(conLateral)[705].x - 0.1) <= paso, "la corrección lateral se suma")
            var apagado = fijo
            apagado.antiRecoil.activo = false
            comprobar(rafaga(apagado).allSatisfy { abs($0.x) <= paso && abs($0.y) <= paso }, "con el anti-recoil apagado, no hace nada")
            // un perfiles.json de cuando existía el modo «patrón» (Trayectorias): carga y compensa con la fuerza fija
            let carpeta = FileManager.default.temporaryDirectory.appendingPathComponent("recoil-\(UUID().uuidString)")
            try? FileManager.default.createDirectory(at: carpeta, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: carpeta) }
            let fPerfiles = carpeta.appendingPathComponent("perfiles.json")
            let alm = Almacen(archivo: fPerfiles)
            var p = alm.activo
            p.antiRecoil = fijo.antiRecoil
            alm.activo = p
            alm.guardarAhora()
            if var viejo = (try? JSONSerialization.jsonObject(with: Data(contentsOf: fPerfiles))) as? [String: Any],
               var perfiles = viejo["perfiles"] as? [[String: Any]] {
                for i in perfiles.indices {
                    var ar = perfiles[i]["antiRecoil"] as? [String: Any] ?? [:]
                    ar["usarPatron"] = true
                    ar["patron"] = ["nombre": "prueba", "duracionMs": 2000, "escalaHorizontal": 100,
                                    "stickX": [0.1, -0.1], "stickY": [-0.5, -0.5]] as [String: Any]
                    perfiles[i]["antiRecoil"] = ar
                }
                viejo["perfiles"] = perfiles
                let fViejo = carpeta.appendingPathComponent("viejo.json")
                try? JSONSerialization.data(withJSONObject: viejo).write(to: fViejo)
                let cargado = Almacen(archivo: fViejo).activo
                comprobar(cargado.antiRecoil == fijo.antiRecoil, "un perfiles.json con un patrón guardado carga igual, sin el patrón")
                comprobar(iguales(rafaga(cargado), rf), "y compensa con la fuerza fija, tick a tick")
            } else {
                comprobar(false, "no se pudo preparar el archivo antiguo del anti-recoil")
            }
        }

        // 11 ──────────────────────────────────────────────────────────────
        seccion("11. Botón de silenciar el micro (solo entrada)")
        do {
            comprobar(Boton.izquierda.indice == 17 && Boton.ps.bit == 1 << 12, "los botones de antes conservan su bit")
            comprobar(Boton.silenciar.bit & 0x3FFF == 0, "su bit no cabe en la trama que va al ESP32")
            comprobar(!Boton.salidas.contains(.silenciar) && Boton.salidas.count == 18, "no se ofrece como botón que recibe la consola")

            var p = Perfil()
            var e = Estado(); e.botones = Boton.silenciar.bit
            comprobar(Procesador().procesar(e, p, t: 0).botones == 0, "sin reasignar no llega nada a la consola")

            p.reasignar["silenciar"] = Boton.triangulo.rawValue
            let s = Procesador().procesar(e, p, t: 0)
            comprobar(s.botones == Boton.triangulo.bit, "reasignado a triángulo, la consola recibe triángulo",
                      String(s.botones, radix: 2))
            comprobar(Procesador().procesar(Estado(), p, t: 0).botones == 0, "al soltarlo no queda nada pulsado")

            var bt = [UInt8](repeating: 0, count: 78); bt[0] = 0x31; bt[11] = 0x04
            var usb = [UInt8](repeating: 0, count: 64); usb[0] = 0x01; usb[10] = 0x05
            let corto = [UInt8](repeating: 0xFF, count: 10)
            comprobar(InformeDualSense.silencio(id: 0x31, bt, bt.count) == true, "se lee pulsado del informe Bluetooth (0x31)")
            bt[11] = 0x03   // PS y táctil, sin silenciar
            comprobar(InformeDualSense.silencio(id: 0x31, bt, bt.count) == false, "PS y táctil no cuentan como silenciar")
            comprobar(InformeDualSense.silencio(id: 0x01, usb, usb.count) == true, "se lee pulsado del informe USB (0x01 de 64 bytes)")
            comprobar(InformeDualSense.silencio(id: 0x01, corto, corto.count) == nil, "el informe corto de Bluetooth se ignora")
        }

        // 12 ──────────────────────────────────────────────────────────────
        seccion("12. Ritmo real del mando y batería")
        do {
            var r = RitmoMando()
            comprobar(r.actual(t: 0).hz == 0, "sin informes, 0 Hz")
            for i in 0...140 { r.informe(t: 10 + Double(i) * 0.015) }   // uno cada 15 ms, como por Bluetooth
            let a = r.actual(t: 12.1)
            comprobar(abs(a.hz - 67) <= 1 && abs(a.huecoMs - 15) < 0.5, "uno cada 15 ms: ~67 Hz y hueco de 15 ms",
                      "\(a.hz) Hz, \(a.huecoMs) ms")
            var g = RitmoMando()
            var t = 0.0
            for i in 0..<500 { t += i == 300 ? 0.030 : 0.004; g.informe(t: t) }   // 250 Hz con un hueco de 30 ms en el 2.º segundo
            let b = g.actual(t: t)
            comprobar(b.hz >= 240 && b.hz <= 255, "uno cada 4 ms: ~250 Hz", "\(b.hz) Hz")
            comprobar(abs(b.huecoMs - 30) < 0.5, "un hueco de 30 ms se ve como peor hueco de ese segundo", "\(b.huecoMs) ms")
            comprobar(r.actual(t: 14).hz == 0, "más de un segundo sin informes: 0 Hz (el mando no manda nada)")

            comprobar(BateriaMando(nivel: 0.35, estado: 0) == BateriaMando(porcentaje: 35, estado: "descargando"), "35 % descargando")
            comprobar(BateriaMando(nivel: 0.8, estado: 1).texto == "Batería 80 % (cargando)", "cargando se indica")
            comprobar(BateriaMando(nivel: 0.97, estado: 2).porcentaje == 100, "llena cuenta como 100 %")
            comprobar(BateriaMando(nivel: 0.15, estado: 0).baja && !BateriaMando(nivel: 0.15, estado: 1).baja, "baja solo si no está cargando")
            comprobar(BateriaMando(nivel: -1, estado: -1).porcentaje == nil, "sin dato: desconocida")
        }

        // 13 ──────────────────────────────────────────────────────────────
        seccion("13. Resumen de funciones de «En vivo»")
        do {
            let g = AjustesGenerales()
            comprobar(ResumenFunciones.de(Perfil(), g, antiRecoil: false, ayuda: false).isEmpty, "perfil nuevo: nada activado")
            var p = Perfil()
            p.antiRecoil.activo = true
            p.ayuda.activo = true
            p.turbos = [Turbo(boton: .r1, hz: 12)]
            p.macros = [Macro(nombre: "Dropshot", activa: true, disparador: .silenciar), Macro(nombre: "Vieja", activa: false)]
            p.reasignar = ["circulo": "r3"]
            let f = ResumenFunciones.de(p, g, antiRecoil: true, ayuda: false)
            comprobar(f.map(\.nombre) == ["Anti-recoil", "Ayuda al apuntado", "Turbo", "Macro", "Botones cambiados"],
                      "orden: anti-recoil, ayuda, turbo, macros y lo demás", "\(f.map(\.nombre))")
            comprobar(f[0].encendida && !f[1].encendida, "el encendido del anti-recoil y la ayuda lo da el motor")
            comprobar(f[2].detalle == "R1 12/s", "el turbo dice el botón y la velocidad", f[2].detalle)
            comprobar(f[3].detalle == "Dropshot (Mic)", "solo cuenta las macros activas, con su disparador", f[3].detalle)
            comprobar(f[4].detalle == "○", "los botones cambiados se nombran", f[4].detalle)
            p.macros[0].activa = false
            let sinMacros = ResumenFunciones.de(p, g, antiRecoil: true, ayuda: false).first { $0.nombre.hasPrefix("Macro") }
            comprobar(sinMacros?.encendida == false && sinMacros?.detalle == "ninguna activa", "macros todas apagadas: en gris")
        }

        // 14 ──────────────────────────────────────────────────────────────
        seccion("14. Fuerza del anti-recoil desde el mando (Mic + ↑/↓)")
        do {
            let g = AjustesGenerales()
            comprobar(g.fuerzaMando && g.fuerzaMantener == .silenciar, "viene activado con el botón de silenciar el micro")
            let mic = Boton.silenciar.bit, arriba = Boton.arriba.bit, abajo = Boton.abajo.bit
            var e = Estado(); e.botones = mic | arriba
            var r = ComboFuerza.aplicar(&e, flanco: arriba, g)
            comprobar(r.mantenido && r.paso == 1, "Mic mantenido + ↑ recién pulsada: sube")
            comprobar(e.botones & arriba == 0 && e.pulsado(.silenciar), "la ↑ no llega a la consola mientras mantienes Mic")
            e.botones = mic | arriba
            r = ComboFuerza.aplicar(&e, flanco: 0, g)
            comprobar(r.mantenido && r.paso == 0, "dejar la ↑ pulsada no sigue subiendo (solo cuenta al pulsar)")
            e.botones = mic | abajo | Boton.x.bit
            r = ComboFuerza.aplicar(&e, flanco: abajo, g)
            comprobar(r.paso == -1 && e.botones & abajo == 0 && e.pulsado(.x), "↓ baja; los demás botones siguen llegando")
            e.botones = arriba
            r = ComboFuerza.aplicar(&e, flanco: arriba, g)
            comprobar(!r.mantenido && r.paso == 0 && e.pulsado(.arriba), "sin Mic, la ↑ llega normal a la consola")
            var apagado = g; apagado.fuerzaMando = false
            e.botones = mic | arriba
            r = ComboFuerza.aplicar(&e, flanco: arriba, apagado)
            comprobar(!r.mantenido && e.pulsado(.arriba), "desactivado en ajustes: no hace nada")

            let alm = Almacen(archivo: temporal.appendingPathComponent("fuerza.json"))
            var p = alm.activo
            p.antiRecoil.activo = true; p.antiRecoil.vertical = 20
            alm.activo = p
            comprobar(alm.ajustarFuerza(1) == "Anti-recoil 22" && alm.activo.antiRecoil.vertical == 22, "sube de 2 en 2 y lo dice")
            _ = alm.ajustarFuerza(-1); _ = alm.ajustarFuerza(-1)
            comprobar(alm.activo.antiRecoil.vertical == 18, "baja de 2 en 2", "\(alm.activo.antiRecoil.vertical)")
            p = alm.activo; p.antiRecoil.vertical = 1; alm.activo = p
            _ = alm.ajustarFuerza(-1)
            comprobar(alm.activo.antiRecoil.vertical == 0, "no baja de 0")
            p = alm.activo; p.antiRecoil.vertical = 99; alm.activo = p
            _ = alm.ajustarFuerza(1)
            comprobar(alm.activo.antiRecoil.vertical == 100, "no pasa de 100")
            p = alm.activo; p.antiRecoil.vertical = 30; p.antiRecoil.progresivo = true; p.antiRecoil.verticalFinal = 20; p.antiRecoil.activo = false
            alm.activo = p
            let frase = alm.ajustarFuerza(1)
            comprobar(alm.activo.antiRecoil.verticalFinal == 22 && frase == "Anti-recoil 32, final 22, apagado",
                      "con el progresivo también mueve la fuerza final, y avisa si está apagado", frase)
            alm.guardarAhora()
            comprobar(Almacen(archivo: temporal.appendingPathComponent("fuerza.json")).activo.antiRecoil.vertical == 32, "el cambio se guarda en el perfil")
            comprobar(Almacen(archivo: archivo).generales.fuerzaMantener == .silenciar, "un archivo de antes carga la combinación con Mic")

            // Corrección lateral con Mic + ←/→
            let der = Boton.derecha.bit, izq = Boton.izquierda.bit
            e.botones = mic | der
            let rl = ComboFuerza.aplicar(&e, flanco: der, g)
            comprobar(rl.mantenido && rl.lateral == 1 && rl.paso == 0 && e.botones & der == 0, "Mic + → mueve la corrección a la derecha y la → no llega a la consola")
            e.botones = mic | izq
            comprobar(ComboFuerza.aplicar(&e, flanco: izq, g).lateral == -1 && e.botones & izq == 0, "Mic + ← a la izquierda")
            e.botones = der
            comprobar(ComboFuerza.aplicar(&e, flanco: der, g).lateral == 0 && e.pulsado(.derecha), "sin Mic, la → llega normal")
            let alm2 = Almacen(archivo: temporal.appendingPathComponent("lateral.json"))
            var pl = alm2.activo; pl.antiRecoil.activo = true; pl.antiRecoil.horizontal = 0; alm2.activo = pl
            comprobar(alm2.ajustarLateral(1) == "Lateral derecha 2" && alm2.activo.antiRecoil.horizontal == 2, "sube de 2 en 2 a la derecha y lo dice")
            _ = alm2.ajustarLateral(-1)
            comprobar(alm2.ajustarLateral(-1) == "Lateral izquierda 2", "y a la izquierda", alm2.ajustarLateral(0))
            pl = alm2.activo; pl.antiRecoil.horizontal = 49; alm2.activo = pl
            _ = alm2.ajustarLateral(1)
            comprobar(alm2.activo.antiRecoil.horizontal == 50, "no pasa de 50")
            pl = alm2.activo; pl.antiRecoil.horizontal = -49; alm2.activo = pl
            _ = alm2.ajustarLateral(-1)
            comprobar(alm2.activo.antiRecoil.horizontal == -50, "no baja de −50")
        }

        // 15 ──────────────────────────────────────────────────────────────
        seccion("15. Widgets de «En vivo», turbos que se apagan y macros con su combinación")
        do {
            // Un archivo de antes: turbos y macros sin los campos nuevos, y sin widgets
            let viejoURL = temporal.appendingPathComponent("widgets-viejo.json")
            let viejo: [String: Any] = ["perfiles": [[
                "id": UUID().uuidString, "nombre": "Viejo",
                "turbos": [["id": UUID().uuidString, "boton": "r1", "hz": 12, "ciclo": 50]],
                "macros": [["id": UUID().uuidString, "nombre": "Salto", "activa": true, "disparador": "r3",
                            "repetir": false, "bloquearDisparador": true, "pasos": []]],
            ]]]
            try? JSONSerialization.data(withJSONObject: viejo).write(to: viejoURL)
            let v = Almacen(archivo: viejoURL)
            comprobar(v.activo.nombre == "Viejo" && v.activo.turbos.first?.activo == true && v.activo.widgets.isEmpty
                      && v.activo.macros.first?.atajo == false,
                      "un archivo antiguo carga: turbos encendidos, macros sin combinación y sin widgets")

            let alm = Almacen(archivo: temporal.appendingPathComponent("widgets.json"))
            var p = alm.activo
            p.turbos = [Turbo(boton: .r1, hz: 12), Turbo(boton: .x, hz: 8)]
            var m1 = Macro(); m1.nombre = "Salto"; var m2 = Macro(); m2.nombre = "Agacharse"; m2.activa = false
            p.macros = [m1, m2]
            alm.activo = p

            let cat = Widgets.catalogo(alm.activo)
            comprobar(cat.map(\.tipo) == [.antiRecoil, .ayuda, .turbos, .turbo, .turbo, .macros, .macro, .macro, .pausa],
                      "el catálogo ofrece todo lo del perfil, cada turbo y cada macro", "\(cat.map(\.tipo))")
            Widgets.basicos(alm.activo).forEach(alm.anadirWidget)
            comprobar(alm.activo.widgets.map(\.tipo) == [.antiRecoil, .ayuda, .macros, .turbos, .pausa], "los básicos",
                      "\(alm.activo.widgets.map(\.tipo))")
            alm.anadirWidget(Widget(tipo: .pausa))
            comprobar(alm.activo.widgets.count == 5, "no se repite un widget que ya está")
            comprobar(!Widgets.catalogo(alm.activo).contains { $0.tipo == .pausa }, "y deja de salir en el catálogo")

            // Tocar los widgets de turbo y macros cambia el perfil
            comprobar(alm.alternarMacros() == "Macros desactivadas" && !alm.activo.macros.contains(where: \.activa),
                      "con alguna macro activa, «Macros» las desactiva todas")
            comprobar(alm.alternarMacros() == "Macros activadas" && alm.activo.macros.allSatisfy(\.activa), "y otra vez las activa todas")
            comprobar(alm.alternarMacro(m1.id) == "Salto desactivada" && alm.activo.macros[0].activa == false, "una macro sola")
            let fraseTurbo = alm.alternarTurbo(p.turbos[1].id)
            comprobar(fraseTurbo?.hasSuffix("apagado") == true && alm.activo.turbos[1].activo == false && alm.activo.turbos[0].activo,
                      "un turbo solo se apaga", fraseTurbo ?? "")
            comprobar(alm.alternarTurbos() == "Turbo apagado" && !alm.activo.turbos.contains(where: \.activo), "«Turbo» los apaga todos")

            let id = alm.activo.widgets[0].id
            alm.moverWidget(id, 1)
            comprobar(alm.activo.widgets[1].id == id, "mover un widget un puesto")
            alm.moverWidget(alm.activo.widgets.last!.id, 1)
            comprobar(alm.activo.widgets.count == 5, "moverlo fuera de la lista no hace nada")

            // Un widget de una macro que ya no existe deja de verse
            alm.anadirWidget(Widget(tipo: .macro, objetivo: m2.id))
            var sinM2 = alm.activo; sinM2.macros.removeAll { $0.id == m2.id }; alm.activo = sinM2
            let estados = alm.activo.widgets.compactMap { Widgets.estado($0, alm.activo, antiRecoil: true, ayuda: false, pausado: false) }
            comprobar(estados.count == 5 && estados.first { $0.tipo == .antiRecoil }?.encendido == true,
                      "el de una macro borrada no sale; el resto sí, con su estado")
            var pAyuda = alm.activo; pAyuda.ayuda.forma = .temblor; pAyuda.ayuda.tamano = 8
            let det = Widgets.estado(Widget(tipo: .ayuda), pAyuda, antiRecoil: false, ayuda: true, pausado: false)?.detalle
            comprobar(det == "temblor · 8 %", "el widget de la ayuda dice la forma y la intensidad", det ?? "")
            alm.quitarWidget(alm.activo.widgets.last!.id)
            alm.guardarAhora()
            comprobar(Almacen(archivo: temporal.appendingPathComponent("widgets.json")).activo.widgets.map(\.tipo)
                      == alm.activo.widgets.map(\.tipo), "los widgets se guardan en el perfil")

            // Desde el móvil llega un turbo sin «activo»: se rellena encendido
            let r = alm.ponerRuta("turbos", [["id": UUID().uuidString, "boton": "x", "hz": 10, "ciclo": 50]])
            comprobar(r == nil && alm.activo.turbos.count == 1 && alm.activo.turbos[0].activo, "un turbo nuevo del móvil, sin el campo, llega encendido", r ?? "")

            // Un turbo apagado deja pasar el botón tal cual
            var pt = Perfil(); pt.turbos = [Turbo(boton: .x, hz: 10)]
            let prT = Procesador()
            var e = Estado(); e.botones = Boton.x.bit
            var cortes = 0
            for k in 0..<300 { if prT.procesar(e, pt, t: Double(k) / 1000).botones & Boton.x.bit == 0 { cortes += 1 } }
            comprobar(cortes > 0, "turbo encendido: el botón se corta")
            pt.turbos[0].activo = false
            cortes = 0
            for k in 300..<600 { if prT.procesar(e, pt, t: Double(k) / 1000).botones & Boton.x.bit == 0 { cortes += 1 } }
            comprobar(cortes == 0, "turbo apagado: el botón llega siempre pulsado")

            // El widget del anti-recoil hace lo mismo que la combinación del mando
            let prA = Procesador()
            var avisos: [Bool] = []
            prA.alCambiarAntiRecoil = { avisos.append($0) }
            e = Estado()
            let pa = Perfil()
            _ = prA.procesar(e, pa, t: 0)
            prA.alternarAntiRecoil()
            comprobar(prA.antiRecoilEncendido && avisos.last == true, "alternar el anti-recoil desde un widget lo enciende y avisa")
            _ = prA.procesar(e, pa, t: 0.001)
            comprobar(prA.antiRecoilEncendido, "y sigue encendido en la siguiente vuelta")
            prA.alternarAyuda()
            comprobar(prA.ayudaEncendida, "la ayuda también se enciende desde un widget")

            // Combinación de una macro: mantener uno y pulsar otro
            var pm = Perfil(); var mc = Macro(); mc.atajo = true; mc.atajoMantener = .l1; mc.atajoPulsar = .derecha
            var otra = Macro(); otra.atajo = false; otra.atajoMantener = .l1; otra.atajoPulsar = .derecha
            pm.macros = [mc, otra]
            e = Estado(); e.botones = Boton.l1.bit | Boton.derecha.bit
            comprobar(ComboMacros.pedidas(e, flanco: Boton.derecha.bit, pm) == [mc.id], "L1 + → activa o desactiva solo la que tiene el atajo")
            comprobar(ComboMacros.pedidas(e, flanco: 0, pm).isEmpty, "dejarlo pulsado no la cambia otra vez")
            e.botones = Boton.derecha.bit
            comprobar(ComboMacros.pedidas(e, flanco: Boton.derecha.bit, pm).isEmpty, "sin mantener L1, → no hace nada")
        }


        // 16 ──────────────────────────────────────────────────────────────
        seccion("16. Los mismos ajustes en la placa y en la app (sincronización por el cable)")
        do {
            // Primera vez con ajustes aquí: se suben y los de la placa van a una copia
            var t = 0.0
            let dir = carpetaTemporal()
            let a = Almacen(archivo: dir.appendingPathComponent("perfiles.json"))
            _ = a.ponerRuta("antiRecoil.vertical", 37)
            let s = Sincro(archivoPerfiles: dir.appendingPathComponent("perfiles.json"), versionInicial: a.version)
            let c = PlacaFalsa(Almacen(archivo: carpetaTemporal().appendingPathComponent("perfiles.json")))
            let avisos = hastaAlDia(s, c, a, &t)
            comprobar(c.almacen.activo.antiRecoil.vertical == 37, "primera vez con ajustes aquí: la placa recibe los de la app",
                      "\(c.almacen.activo.antiRecoil.vertical)")
            comprobar(avisos.contains { $0.contains("Primera vez") }, "y avisa", "\(avisos)")
            comprobar(!copias(dir, "copia-de-la-placa").isEmpty, "y guarda una copia de los que tenía la placa")
            comprobar(c.almacen.ajustesSincronizados() == a.ajustesSincronizados(), "quedan iguales")
        }
        do {
            // Primera vez con la app de fábrica: se queda los de la placa (cada uno con su clave)
            var t = 0.0
            let dir = carpetaTemporal()
            let a = Almacen(archivo: dir.appendingPathComponent("perfiles.json"))
            let s = Sincro(archivoPerfiles: dir.appendingPathComponent("perfiles.json"), versionInicial: a.version)
            let c = PlacaFalsa(Almacen(archivo: carpetaTemporal().appendingPathComponent("perfiles.json")))
            _ = c.almacen.ponerRuta("antiRecoil.vertical", 55)
            hastaAlDia(s, c, a, &t)
            comprobar(a.activo.antiRecoil.vertical == 55, "primera vez de fábrica: se queda los de la placa")
            comprobar(a.generales.clave != c.almacen.generales.clave, "cada uno con su clave")
        }
        do {
            // Después: los cambios van y vienen
            var t = 0.0
            let dir = carpetaTemporal()
            let a = Almacen(archivo: dir.appendingPathComponent("perfiles.json"))
            let s = Sincro(archivoPerfiles: dir.appendingPathComponent("perfiles.json"), versionInicial: a.version)
            let c = PlacaFalsa(Almacen(archivo: carpetaTemporal().appendingPathComponent("perfiles.json")))
            hastaAlDia(s, c, a, &t)
            _ = a.ponerRuta("antiRecoil.vertical", 12)
            for _ in 0..<3000 { t += 0.001; _ = s.vuelta(c, a, t: t) }
            comprobar(c.almacen.activo.antiRecoil.vertical == 12, "un cambio aquí llega a la placa (tras 1 s de calma)")
            comprobar(s.estado == "al día", "y queda al día", s.estado)
            _ = c.almacen.ponerRuta("antiRecoil.vertical", 19)
            var avisos: [String] = []
            for _ in 0..<5000 { t += 0.001; if let x = s.vuelta(c, a, t: t) { avisos.append(x) } }
            comprobar(a.activo.antiRecoil.vertical == 19, "un cambio en la placa (desde el móvil) llega aquí en la siguiente comprobación",
                      "\(a.activo.antiRecoil.vertical)")
            comprobar(avisos.contains { $0.contains("recogidos") }, "y avisa", "\(avisos)")
            comprobar(!s.g.cambiosLocales, "lo recibido no cuenta como cambio de aquí (no se vuelve a subir)")
            // El estado se guarda entre arranques
            let otra = Sincro(archivoPerfiles: dir.appendingPathComponent("perfiles.json"), versionInicial: 0)
            comprobar(otra.g.ultimaRev == s.g.ultimaRev && !otra.g.cambiosLocales, "el estado se guarda en sincro.json entre arranques")
            let guardado = (try? JSONSerialization.jsonObject(with: Data(contentsOf: dir.appendingPathComponent("sincro.json")))) as? [String: Any]
            comprobar(guardado?["ultimaRev"] is String && guardado?["cambiosLocales"] is Bool, "con el mismo formato que la app de escritorio")
        }
        do {
            // Cambiados en los dos sitios: gana la placa y los de aquí van a una copia
            var t = 0.0
            let dir = carpetaTemporal()
            let a = Almacen(archivo: dir.appendingPathComponent("perfiles.json"))
            let s = Sincro(archivoPerfiles: dir.appendingPathComponent("perfiles.json"), versionInicial: a.version)
            let c = PlacaFalsa(Almacen(archivo: carpetaTemporal().appendingPathComponent("perfiles.json")))
            hastaAlDia(s, c, a, &t)
            c.conectada = false
            _ = s.vuelta(c, a, t: t)
            _ = a.ponerRuta("antiRecoil.vertical", 70)
            t += 0.01
            _ = s.vuelta(c, a, t: t)
            _ = c.almacen.ponerRuta("antiRecoil.vertical", 30)
            c.conectada = true
            let avisos = hastaAlDia(s, c, a, &t)
            comprobar(a.activo.antiRecoil.vertical == 30, "cambiados en los dos sitios: gana la placa", "\(a.activo.antiRecoil.vertical)")
            comprobar(avisos.contains { $0.contains("me quedo con los de la placa") }, "y avisa", "\(avisos)")
            let copia = copias(dir, "copia-conflicto").first
            let texto = copia.flatMap { try? String(contentsOf: $0, encoding: .utf8) } ?? ""
            comprobar(texto.contains("\"vertical\":70"), "y los de aquí quedan en una copia", copia?.lastPathComponent ?? "sin copia")
        }
        do {
            // Una placa con el firmware antiguo no contesta: se deja en paz
            var t = 0.0
            let dir = carpetaTemporal()
            let a = Almacen(archivo: dir.appendingPathComponent("perfiles.json"))
            let s = Sincro(archivoPerfiles: dir.appendingPathComponent("perfiles.json"), versionInicial: a.version)
            let c = PlacaFalsa(Almacen(archivo: carpetaTemporal().appendingPathComponent("perfiles.json")))
            c.contesta = false
            for _ in 0..<8000 { t += 0.001; _ = s.vuelta(c, a, t: t) }
            comprobar(s.estado == "firmware antiguo", "firmware antiguo (no contesta): se deja en paz", s.estado)
            // Y los ajustes sincronizados no llevan lo que es de cada aparato
            let d = (try? JSONSerialization.jsonObject(with: a.ajustesSincronizados())) as? [String: Any]
            let g = d?["generales"] as? [String: Any]
            comprobar(g != nil && g?["clave"] == nil && g?["servidorMovil"] == nil && d?["perfiles"] is [Any],
                      "lo que se sincroniza no lleva la clave ni el acceso por la red")
            comprobar(a.ponerAjustesSincronizados(Data("{\"perfiles\": []}".utf8)) != nil
                      && a.ponerAjustesSincronizados(Data("no es json".utf8)) != nil, "y unos ajustes sin perfiles o rotos se rechazan")
        }

        print("\n\(total - fallos) de \(total) comprobaciones correctas")
        exit(fallos == 0 ? 0 : 1)
    }
}
