import Foundation

/// Aplica el perfil al mando: botones (alternar, pulsación larga, reasignar), sticks,
/// gatillos, macros, turbo y anti-recoil. Se llama unas 1000 veces por segundo desde el
/// motor y guarda lo que necesita recordar entre una llamada y la siguiente.
final class Procesador {
    private(set) var antiRecoilEncendido = false
    var alCambiarAntiRecoil: ((Bool) -> Void)?
    private(set) var ayudaEncendida = false
    var alCambiarAyuda: ((Bool) -> Void)?
    private var ayudaEnAjustes: Bool?
    private var ayudaDesde: Double?
    // Continuidad ante cambios hechos a mano mientras la ayuda está en marcha (variante, patrón,
    // deslizador, límites): se enlaza con lo anterior en vez de dar un salto. Sin cambios, todo vale 0.
    private var efAnterior: (tamano: Double, hz: Double, entradaMs: Double, ceder: Double, forma: AyudaApuntado.Forma)?
    private var faseDesfase = 0.0
    private var rUltimo = 0.0
    private var correccionR = 0.0, correccionDesde = 0.0
    private var formaAnterior: AyudaApuntado.Forma?, formaCambioDesde = 0.0
    private static let duracionEnlace = 0.15          // s que tarda en enlazarse un cambio manual
    /// Lo que está haciendo la ayuda ahora mismo (la vista de diagnóstico lo lee)
    private(set) var diagnostico = DiagnosticoAyuda()

    private var perfilID: UUID?
    private var activoEnAjustes: Bool?
    private var entradaAntes: UInt32 = 0
    private var tAntes: Double?
    private var turboDesde: [Boton: Double] = [:]
    private var macroDesde: [UUID: Double] = [:]
    private var disparandoDesde: Double?
    private var alternados: UInt32 = 0              // botones en modo alternar que están "pulsados"
    private var pulsadoDesde: [Boton: Double] = [:] // para la pulsación larga
    private var toqueHasta: [Boton: Double] = [:]   // pulsación corta que se está enviando
    private var izq = EstadoStick(), der = EstadoStick()

    private struct EstadoStick {
        var x = 0.0, y = 0.0          // salida suavizada
        var topeDesde: Double?        // desde cuándo está casi a tope (aceleración)
    }

    /// Como la combinación del mando, pero pedido desde «En vivo» (un widget). Desde el hilo del motor.
    func alternarAntiRecoil() {
        antiRecoilEncendido.toggle()
        alCambiarAntiRecoil?(antiRecoilEncendido)
    }

    func alternarAyuda() {
        ayudaEncendida.toggle()
        alCambiarAyuda?(ayudaEncendida)
    }

    func procesar(_ e: Estado, _ p: Perfil, t: Double) -> Estado {
        if p.id != perfilID {            // perfil nuevo: empezar de cero
            perfilID = p.id
            turboDesde = [:]; macroDesde = [:]; alternados = 0
            pulsadoDesde = [:]; toqueHasta = [:]
            efAnterior = nil; faseDesfase = 0; correccionR = 0; formaAnterior = nil
            activoEnAjustes = nil
            ayudaEnAjustes = nil
        }
        if p.ayuda.activo != ayudaEnAjustes {
            ayudaEnAjustes = p.ayuda.activo
            ayudaEncendida = p.ayuda.activo
            alCambiarAyuda?(ayudaEncendida)
        }
        if p.antiRecoil.activo != activoEnAjustes {   // lo han cambiado en la ventana
            activoEnAjustes = p.antiRecoil.activo
            antiRecoilEncendido = p.antiRecoil.activo
            alCambiarAntiRecoil?(antiRecoilEncendido)
        }
        let dt = min(max(t - (tAntes ?? t), 0), 0.05)
        tAntes = t
        let flanco = e.botones & ~entradaAntes       // botones que se acaban de pulsar
        let soltados = entradaAntes & ~e.botones
        defer { entradaAntes = e.botones }

        // 1. Sticks en coma flotante, Y positiva = arriba
        var (ix, iy) = (eje(e.lx), -eje(e.ly))
        var (dx, dy) = (eje(e.rx), -eje(e.ry))
        if p.intercambiarSticks { swap(&ix, &dx); swap(&iy, &dy) }
        (ix, iy) = stick(ix, iy, p.izq, &izq, t: t, dt: dt)
        (dx, dy) = stick(dx, dy, p.der, &der, t: t, dt: dt)

        // 2. Gatillos
        var l2 = Procesador.gatillo(e.l2, p.l2)
        var r2 = Procesador.gatillo(e.r2, p.r2)
        var entrada = e.botones & ~(Boton.l2.bit | Boton.r2.bit)
        if l2 > 0 { entrada |= Boton.l2.bit }
        if r2 > 0 { entrada |= Boton.r2.bit }

        // 3. Alternar: pulsar una vez = mantener, otra vez = soltar
        for b in p.alternar {
            if flanco & b.bit != 0 { alternados ^= b.bit }
            if alternados & b.bit != 0 { entrada |= b.bit } else { entrada &= ~b.bit }
            if b == .l2 { l2 = alternados & b.bit != 0 ? 1 : 0 }
            if b == .r2 { r2 = alternados & b.bit != 0 ? 1 : 0 }
        }

        // 4. Pulsación larga: corta = su función normal; larga = otra
        var porLarga: UInt32 = 0
        for (origen, destinoLargo) in p.pulsacionLarga {
            guard let b = Boton(rawValue: origen) else { continue }
            let larga = Boton(rawValue: destinoLargo)          // nil = "nada"
            if e.botones & b.bit != 0 {
                let desde = pulsadoDesde[b] ?? t
                pulsadoDesde[b] = desde
                if (t - desde) * 1000 >= p.msLarga, let larga { porLarga |= larga.bit }
            } else if soltados & b.bit != 0, let desde = pulsadoDesde[b] {
                if (t - desde) * 1000 < p.msLarga { toqueHasta[b] = t + 0.08 }   // fue corta: se envía ahora
                pulsadoDesde[b] = nil
            }
            // Mientras se decide, y durante la larga, la función normal no llega
            if let hasta = toqueHasta[b], t < hasta {
                entrada |= b.bit
                if b == .l2 { l2 = 1 }
                if b == .r2 { r2 = 1 }
            } else {
                toqueHasta[b] = nil
                entrada &= ~b.bit
                if b == .l2 { l2 = 0 }
                if b == .r2 { r2 = 0 }
            }
        }

        // 5. Reasignación
        var salida: UInt32 = 0
        var l2Sal = 0.0, r2Sal = 0.0
        for b in Boton.allCases where entrada & b.bit != 0 {
            guard let d = p.destino(de: b) else { continue }
            salida |= d.bit
            let valor = b == .l2 ? l2 : (b == .r2 ? r2 : 1.0)
            if d == .l2 { l2Sal = max(l2Sal, valor) }
            if d == .r2 { r2Sal = max(r2Sal, valor) }
        }
        salida |= porLarga
        if porLarga & Boton.l2.bit != 0 { l2Sal = 1 }
        if porLarga & Boton.r2.bit != 0 { r2Sal = 1 }

        // 6. Macros (se disparan con el botón físico)
        var deMacros: UInt32 = 0
        for m in p.macros where m.activa && !m.pasos.isEmpty {
            let pulsado = e.botones & m.disparador.bit != 0
            if flanco & m.disparador.bit != 0 && macroDesde[m.id] == nil { macroDesde[m.id] = t }
            guard let desde = macroDesde[m.id] else { continue }
            let total = Double(m.pasos.reduce(0) { $0 + max($1.ms, 1) }) / 1000
            var pasado = t - desde
            if pasado >= total {
                if m.repetir && pulsado {
                    pasado = pasado.truncatingRemainder(dividingBy: total)
                } else {
                    macroDesde[m.id] = nil
                    continue
                }
            }
            var acumulado = 0.0
            for paso in m.pasos {
                acumulado += Double(max(paso.ms, 1)) / 1000
                if pasado < acumulado {
                    for b in paso.botones { deMacros |= b.bit }
                    break
                }
            }
        }
        // El disparador no llega a la consola mientras lo mantienes (salvo que la macro lo pulse)
        for m in p.macros where m.activa && m.bloquearDisparador && e.botones & m.disparador.bit != 0 {
            guard let d = p.destino(de: m.disparador), deMacros & d.bit == 0 else { continue }
            salida &= ~d.bit
            if d == .l2 { l2Sal = 0 }
            if d == .r2 { r2Sal = 0 }
        }
        salida |= deMacros
        if deMacros & Boton.l2.bit != 0 { l2Sal = 1 }
        if deMacros & Boton.r2.bit != 0 { r2Sal = 1 }

        // 7. Turbo
        for tb in p.turbos where tb.hz > 0 && tb.activo {
            guard salida & tb.boton.bit != 0 else { turboDesde[tb.boton] = nil; continue }
            let desde = turboDesde[tb.boton] ?? t
            turboDesde[tb.boton] = desde
            let fase = ((t - desde) * tb.hz).truncatingRemainder(dividingBy: 1)
            if fase >= tb.ciclo / 100 {
                salida &= ~tb.boton.bit
                if tb.boton == .l2 { l2Sal = 0 }
                if tb.boton == .r2 { r2Sal = 0 }
            }
        }

        // 8. Anti-recoil
        let ar = p.antiRecoil
        let combinacion = ar.atajoMantener == ar.atajoPulsar
            ? flanco & ar.atajoPulsar.bit != 0
            : e.pulsado(ar.atajoMantener) && flanco & ar.atajoPulsar.bit != 0
        if ar.atajo && combinacion {
            antiRecoilEncendido.toggle()
            alCambiarAntiRecoil?(antiRecoilEncendido)
        }
        func pulsadoEnSalida(_ b: Boton) -> Bool {
            switch b {
            case .l2: return l2Sal > 0.1
            case .r2: return r2Sal > 0.1
            default: return salida & b.bit != 0
            }
        }
        let disparando = pulsadoEnSalida(ar.disparar) && (!ar.soloApuntando || pulsadoEnSalida(ar.apuntar))
        if antiRecoilEncendido && disparando {
            let desde = disparandoDesde ?? t
            disparandoDesde = desde
            let pasadoMs = (t - desde) * 1000 - ar.retardoMs
            if pasadoMs >= 0 {
                var fuerza = ar.vertical
                if ar.progresivo {
                    let k = ar.transicionMs > 0 ? min(pasadoMs / ar.transicionMs, 1) : 1
                    fuerza = ar.vertical + (ar.verticalFinal - ar.vertical) * k
                }
                dy -= fuerza / 100
                dx += ar.horizontal / 100
            }
        } else {
            disparandoDesde = nil
        }

        // 9. Ayuda al apuntado: círculos o temblores diminutos en el stick derecho
        let ay = p.ayuda
        let comboAyuda = ay.atajoMantener == ay.atajoPulsar
            ? flanco & ay.atajoPulsar.bit != 0
            : e.pulsado(ay.atajoMantener) && flanco & ay.atajoPulsar.bit != 0
        if ay.atajo && comboAyuda {
            ayudaEncendida.toggle()
            alCambiarAyuda?(ayudaEncendida)
        }
        // Valores que usa el motor: los del perfil, recortados a los límites si el usuario los activó
        let ef = ay.efectivos
        var diag = DiagnosticoAyuda()
        diag.encendida = ayudaEncendida
        diag.forma = ay.forma
        diag.tamano = ef.tamano; diag.hz = ef.hz; diag.entradaMs = ef.entradaMs; diag.ceder = ef.ceder
        diag.limitada = ay.limitado
        if ayudaEncendida && pulsadoEnSalida(ay.boton) && (!ay.tambienDisparando || pulsadoEnSalida(ar.disparar)) {
            let desde = ayudaDesde ?? t
            ayudaDesde = desde
            // Un cambio hecho a mano con la ayuda en marcha: la fase y la amplitud se enlazan
            var cambioManual = false
            if let a = efAnterior, a.tamano != ef.tamano || a.hz != ef.hz || a.entradaMs != ef.entradaMs
                || a.ceder != ef.ceder || a.forma != ay.forma {
                cambioManual = true
                if a.hz != ef.hz {
                    let faseAntes = (t - desde) * a.hz + faseDesfase
                    faseDesfase = faseAntes - (t - desde) * ef.hz
                }
                if a.forma != ay.forma { formaAnterior = a.forma; formaCambioDesde = t }
            }
            efAnterior = (ef.tamano, ef.hz, ef.entradaMs, ef.ceder, ay.forma)
            let fase = ((t - desde) * ef.hz + faseDesfase).truncatingRemainder(dividingBy: 1)
            // Entra poco a poco y cede cuando apuntas tú, para que no dé tirones ni pelee con tu mano
            let entrada = ef.entradaMs > 0 ? min((t - desde) * 1000 / ef.entradaMs, 1) : 1
            let tuyo = min(hypot(dx, dy), 1)
            let r0 = ef.tamano / 100 * entrada * (1 - ef.ceder / 100 * tuyo)
            if cambioManual { correccionR = rUltimo - r0; correccionDesde = t }
            var correccion = 0.0
            if correccionR != 0 {
                let k = 1 - (t - correccionDesde) / Procesador.duracionEnlace
                if k > 0 { correccion = correccionR * k } else { correccionR = 0 }
            }
            let r = r0 + correccion
            rUltimo = r
            var (vx, vy) = Procesador.vector(ay.forma, r, fase)
            if let anterior = formaAnterior {
                let k = (t - formaCambioDesde) / Procesador.duracionEnlace
                if k < 1 {
                    let (ox, oy) = Procesador.vector(anterior, r, fase)
                    vx = ox + (vx - ox) * k; vy = oy + (vy - oy) * k
                } else {
                    formaAnterior = nil
                }
            }
            dx += vx
            dy += vy
            diag.aplicando = true
            diag.rampa = entrada; diag.cesion = 1 - ef.ceder / 100 * tuyo
            diag.amplitud = r; diag.fase = fase - fase.rounded(.down)
            diag.offX = vx; diag.offY = vy
            diag.enTransicion = correccion != 0 || formaAnterior != nil
        } else {
            ayudaDesde = nil
            efAnterior = nil; faseDesfase = 0; correccionR = 0; formaAnterior = nil; rUltimo = 0
        }
        diagnostico = diag

        return Estado(botones: salida,
                      lx: byte(ix), ly: byte(-iy), rx: byte(dx), ry: byte(-dy),
                      l2: UInt8((min(max(l2Sal, 0), 1) * 255).rounded()),
                      r2: UInt8((min(max(r2Sal, 0), 1) * 255).rounded()))
    }

    private func stick(_ x: Double, _ y: Double, _ a: AjusteStick, _ s: inout EstadoStick,
                       t: Double, dt: Double) -> (Double, Double) {
        var (ox, oy) = Procesador.forma(x, y, a)
        // Aceleración: con el stick casi a tope, la sensibilidad sube poco a poco
        if a.aceleracion > 0 && hypot(x, y) > 0.85 {
            let desde = s.topeDesde ?? t
            s.topeDesde = desde
            let k = a.tiempoAceleracion > 0 ? min((t - desde) * 1000 / a.tiempoAceleracion, 1) : 1
            let factor = 1 + a.aceleracion / 100 * k
            ox *= factor; oy *= factor
        } else {
            s.topeDesde = nil
        }
        // Límite: lo más lejos que llega el stick a la consola
        let lim = a.limite / 100
        let m = hypot(ox, oy)
        if m > lim, m > 0 { ox *= lim / m; oy *= lim / m }
        // Suavizado: filtro que quita los tirones (hasta ~150 ms)
        if a.suavizado > 0 {
            let tau = a.suavizado / 100 * 0.15
            let alfa = dt / (tau + dt)
            s.x += (ox - s.x) * alfa
            s.y += (oy - s.y) * alfa
            (ox, oy) = (s.x, s.y)
        } else {
            (s.x, s.y) = (ox, oy)
        }
        return (min(max(ox, -1), 1), min(max(oy, -1), 1))
    }

    /// Lo que la ayuda suma al stick derecho según la forma, la amplitud y la fase (0...1)
    static func vector(_ forma: AyudaApuntado.Forma, _ r: Double, _ fase: Double) -> (Double, Double) {
        switch forma {
        case .circulo: return (r * cos(2 * .pi * fase), r * sin(2 * .pi * fase))
        case .temblor: return (r * sin(2 * .pi * fase), 0)     // vaivén suave, sin saltos
        }
    }

    // MARK: - Cálculos sueltos (también los usa la ventana para dibujar la curva)

    /// Zona muerta, curva, sensibilidad e inversión (sin aceleración, límite ni suavizado)
    static func forma(_ x: Double, _ y: Double, _ a: AjusteStick) -> (Double, Double) {
        var sx: Double, sy: Double
        if a.formaCruz {
            sx = (x < 0 ? -1 : 1) * curva(min(abs(x), 1), a)
            sy = (y < 0 ? -1 : 1) * curva(min(abs(y), 1), a)
        } else {
            let modulo = min(hypot(x, y), 1)
            guard modulo > 0 else { return (0, 0) }
            let salida = curva(modulo, a)
            (sx, sy) = (x / hypot(x, y) * salida, y / hypot(x, y) * salida)
        }
        sx *= a.sensX / 100
        sy *= a.sensY / 100
        if a.invertirX { sx = -sx }
        if a.invertirY { sy = -sy }
        return (sx, sy)
    }

    /// Recorrido del stick (0..1) -> recorrido que sale (0..1)
    static func curva(_ v: Double, _ a: AjusteStick) -> Double {
        let dz = a.zonaMuerta / 100
        let ext = max(a.zonaExterna / 100, dz + 0.01)
        guard v > dz else { return 0 }
        var n = min((v - dz) / (ext - dz), 1)
        n = pow(n, max(a.curva, 0.1))
        let anti = a.antiZonaMuerta / 100
        return anti + (1 - anti) * n
    }

    static func gatillo(_ v: UInt8, _ a: AjusteGatillo) -> Double {
        let x = Double(v) / 255
        let dz = a.zonaMuerta / 100
        guard x > dz, x > 0.01 else { return 0 }
        if a.disparoRapido { return 1 }
        let ext = max(a.zonaExterna / 100, dz + 0.01)
        return pow(min((x - dz) / (ext - dz), 1), max(a.curva, 0.1))
    }
}

private func eje(_ v: UInt8) -> Double { (Double(v) - 127.5) / 127.5 }
private func byte(_ v: Double) -> UInt8 { UInt8(min(max(127.5 + v * 127.5, 0), 255).rounded()) }

/// Foto de lo que hace la ayuda al apuntado en este instante (solo para mirar; no cambia nada)
struct DiagnosticoAyuda: Equatable {
    var encendida = false          // el interruptor está encendido
    var aplicando = false          // ahora mismo está moviendo el stick
    var forma = AyudaApuntado.Forma.circulo
    var tamano = 0.0, hz = 0.0, entradaMs = 0.0, ceder = 0.0   // valores efectivos (tras los límites)
    var limitada = false           // algún valor del perfil queda fuera de los límites
    var rampa = 0.0                // 0...1: cuánto ha avanzado la entrada suave
    var cesion = 1.0               // 1 = sin ceder; menos = cediendo ante tu stick
    var amplitud = 0.0             // fracción del recorrido del stick
    var fase = 0.0                 // 0...1
    var offX = 0.0, offY = 0.0     // lo que la ayuda suma al stick derecho (-1...1)
    var enTransicion = false       // enlazando un cambio hecho a mano
}
