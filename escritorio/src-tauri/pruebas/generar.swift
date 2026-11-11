// Genera pruebas/procesador.json con el procesador de Swift (app/Procesador.swift): varios escenarios
// deterministas, con sus perfiles (en el formato de perfiles.json), las entradas de cada tick y la salida
// que da Swift. La prueba de Rust (src/procesador.rs) pasa las mismas entradas y exige la misma salida.
// Se regenera con ./pruebas/generar.sh
import Foundation

/// Entrada de un tick: el estado del mando y, si toca, encender/apagar algo como lo haría un widget
struct Tick {
    var e = Estado()
    var alternarAntiRecoil = false
    var alternarAyuda = false
}

struct Escenario {
    let nombre: String
    let ticks: Int
    var perfil: Perfil
    /// Cambios del perfil a mitad (como si se tocara un ajuste en la ventana o el móvil)
    var cambios: [(tick: Int, cambio: (inout Perfil) -> Void)] = []
    let entrada: (Int, Double) -> Tick
}

/// Generador congruencial fijo: mismas «entradas al azar» en cada ejecución
struct Azar {
    var s: UInt64
    mutating func siguiente() -> UInt64 { s = s &* 6364136223846793005 &+ 1442695040888963407; return s >> 33 }
    mutating func byte() -> UInt8 { UInt8(siguiente() % 256) }
}

func onda(_ t: Double, _ f: Double, _ amp: Double, _ fase: Double = 0) -> UInt8 {
    UInt8(min(max(127.5 + amp * 127.5 * sin(2 * .pi * f * t + fase), 0), 255).rounded())
}

func id(_ n: Int) -> UUID { UUID(uuidString: String(format: "00000000-0000-4000-8000-%012d", n))! }

/// Tiempo con algo de irregularidad (los informes del mando no llegan exactos) para probar dt y los recortes
func tiempo(_ i: Int) -> Double {
    Double(i) / 1000 + (i % 7 == 3 ? 0.0004 : 0) + (i % 97 == 50 ? 0.06 : 0)
}

func escenarios() -> [Escenario] {
    var lista: [Escenario] = []

    // 1. Sticks: zonas muertas, curva, anti zona muerta, sensibilidad, inversión, límite, forma en cruz
    var p1 = Perfil(nombre: "Sticks"); p1.id = id(1)
    p1.izq.zonaMuerta = 12; p1.izq.curva = 1.8; p1.izq.antiZonaMuerta = 9; p1.izq.sensX = 130; p1.izq.limite = 85
    p1.izq.invertirY = true
    p1.der.formaCruz = true; p1.der.zonaMuerta = 8; p1.der.zonaExterna = 90; p1.der.curva = 0.7; p1.der.sensY = 70
    p1.der.invertirX = true
    lista.append(Escenario(nombre: "sticks", ticks: 4000, perfil: p1) { i, t in
        var k = Tick()
        k.e.lx = onda(t, 0.7, 1.1); k.e.ly = onda(t, 0.45, 0.9, 1)
        k.e.rx = onda(t, 1.3, 0.6); k.e.ry = onda(t, 0.9, 1.0, 2)
        return k
    })

    // 2. Suavizado y aceleración (con el stick a tope y soltándolo), sticks intercambiados
    var p2 = Perfil(nombre: "Suave"); p2.id = id(2)
    p2.intercambiarSticks = true
    p2.der.suavizado = 40; p2.der.aceleracion = 60; p2.der.tiempoAceleracion = 400
    p2.izq.suavizado = 100; p2.izq.aceleracion = 30; p2.izq.tiempoAceleracion = 0
    lista.append(Escenario(nombre: "suavizado-aceleracion", ticks: 4000, perfil: p2) { i, t in
        var k = Tick()
        let tope = (i / 600) % 2 == 0
        k.e.lx = tope ? 255 : onda(t, 2, 0.3); k.e.ly = tope ? 0 : 128
        k.e.rx = (i / 450) % 3 == 0 ? 0 : onda(t, 1.1, 1.0)
        k.e.ry = (i / 450) % 3 == 1 ? 255 : 128
        return k
    })

    // 3. Gatillos: zonas muertas, curva, disparo rápido
    var p3 = Perfil(nombre: "Gatillos"); p3.id = id(3)
    p3.l2.zonaMuerta = 20; p3.l2.zonaExterna = 80; p3.l2.curva = 2.2
    p3.r2.disparoRapido = true; p3.r2.zonaMuerta = 5
    lista.append(Escenario(nombre: "gatillos", ticks: 3000, perfil: p3) { i, t in
        var k = Tick()
        k.e.l2 = onda(t, 0.8, 1.0); k.e.r2 = onda(t, 1.7, 1.0, 3)
        return k
    })

    // 4. Botones: reasignar (también anular y la cruceta), alternar, pulsación larga (corta, larga y a «nada»)
    var p4 = Perfil(nombre: "Botones"); p4.id = id(4)
    p4.reasignar = ["x": "circulo", "circulo": "x", "l1": "nada", "arriba": "triangulo", "silenciar": "r3", "r2": "l2"]
    p4.alternar = [.l2, .cuadrado]
    p4.pulsacionLarga = ["triangulo": "options", "r1": "nada", "l2": "r1"]
    p4.msLarga = 250
    lista.append(Escenario(nombre: "botones", ticks: 5000, perfil: p4) { i, t in
        var k = Tick()
        let bloque = i / 37
        var r = Azar(s: UInt64(bloque) &* 2654435761 &+ 7)
        // en cada bloque se mantiene un grupo de botones; los bloques largos permiten pulsaciones largas
        let mascara: UInt32 = UInt32(r.siguiente() % (1 << 19))
        let largo = (i / 400) % 3 == 1
        k.e.botones = largo ? (Boton.triangulo.bit | Boton.r1.bit) : mascara & ~((i % 2 == 0) ? 0 : Boton.silenciar.bit)
        k.e.l2 = mascara & Boton.l2.bit != 0 ? 255 : 0
        k.e.r2 = mascara & Boton.r2.bit != 0 ? 200 : 0
        if mascara & Boton.l2.bit != 0 { k.e.botones |= Boton.l2.bit }
        return k
    })

    // 5. Macros: repetir, bloquear el disparador, macro que pulsa su propio disparador, inactiva, pasos de 0 ms
    var p5 = Perfil(nombre: "Macros"); p5.id = id(5)
    var m1 = Macro(); m1.id = id(51); m1.nombre = "Repetir"; m1.disparador = .r3; m1.repetir = true
    m1.pasos = [PasoMacro(id: id(511), botones: [.x], ms: 40), PasoMacro(id: id(512), botones: [], ms: 25), PasoMacro(id: id(513), botones: [.cuadrado, .l2], ms: 0)]
    var m2 = Macro(); m2.id = id(52); m2.nombre = "Una vez"; m2.disparador = .l1; m2.bloquearDisparador = true
    m2.pasos = [PasoMacro(id: id(521), botones: [.l1, .r2], ms: 120), PasoMacro(id: id(522), botones: [.circulo], ms: 60)]
    var m3 = Macro(); m3.id = id(53); m3.nombre = "Apagada"; m3.activa = false; m3.disparador = .triangulo
    var m4 = Macro(); m4.id = id(54); m4.nombre = "Sin bloquear"; m4.disparador = .derecha; m4.bloquearDisparador = false
    m4.pasos = [PasoMacro(id: id(541), botones: [.r1], ms: 90)]
    p5.macros = [m1, m2, m3, m4]
    lista.append(Escenario(nombre: "macros", ticks: 5000, perfil: p5) { i, t in
        var k = Tick()
        if (i / 700) % 2 == 0 && i % 700 > 50 { k.e.botones |= Boton.r3.bit }
        if i % 500 < 240 && i > 100 { k.e.botones |= Boton.l1.bit }
        if i % 333 < 30 { k.e.botones |= Boton.triangulo.bit | Boton.derecha.bit }
        return k
    })

    // 6. Turbo: varios, uno apagado, en un gatillo y en un botón reasignado; se apaga y se enciende a mitad
    var p6 = Perfil(nombre: "Turbo"); p6.id = id(6)
    p6.turbos = [Turbo(id: id(61), boton: .x, hz: 13, ciclo: 35), Turbo(id: id(62), boton: .r2, hz: 7.5, ciclo: 60),
                 Turbo(id: id(63), boton: .r1, hz: 20, ciclo: 50, activo: false), Turbo(id: id(64), boton: .circulo, hz: 0, ciclo: 50)]
    p6.reasignar = ["cuadrado": "x"]
    var c6: [(tick: Int, cambio: (inout Perfil) -> Void)] = []
    c6.append((1500, { $0.turbos[0].activo = false; $0.turbos[2].activo = true }))
    c6.append((3000, { $0.turbos[0].activo = true; $0.turbos[1].hz = 11 }))
    lista.append(Escenario(nombre: "turbo", ticks: 4500, perfil: p6, cambios: c6) { i, t in
        var k = Tick()
        if i % 900 < 600 { k.e.botones |= Boton.x.bit | Boton.r1.bit }
        if i % 1100 > 300 { k.e.botones |= Boton.cuadrado.bit | Boton.circulo.bit; k.e.r2 = 230 }
        return k
    })

    // 7. Anti-recoil fijo: solo apuntando, retardo, lateral, atajo del mando y desde un widget
    var p7 = Perfil(nombre: "Recoil fijo"); p7.id = id(7)
    p7.antiRecoil.activo = true; p7.antiRecoil.vertical = 27; p7.antiRecoil.horizontal = -6; p7.antiRecoil.retardoMs = 80
    p7.antiRecoil.disparar = .r2; p7.antiRecoil.apuntar = .l2; p7.antiRecoil.soloApuntando = true
    p7.antiRecoil.atajoMantener = .l2; p7.antiRecoil.atajoPulsar = .abajo
    lista.append(Escenario(nombre: "antirecoil-fijo", ticks: 6000, perfil: p7) { i, t in
        var k = Tick()
        k.e.rx = onda(t, 0.3, 0.4); k.e.ry = onda(t, 0.5, 0.3)
        if i % 1000 > 200 { k.e.l2 = 255; k.e.botones |= Boton.l2.bit }
        if i % 1000 > 350 && i % 1000 < 900 { k.e.r2 = 255; k.e.botones |= Boton.r2.bit }
        if i == 2600 || i == 3700 { k.e.botones |= Boton.abajo.bit }      // la combinación L2 + ↓
        k.alternarAntiRecoil = i == 4400 || i == 5100                       // como el widget
        return k
    })

    // 8. Anti-recoil progresivo sin apuntar, y luego atajo con el mismo botón para mantener y pulsar
    var p8 = Perfil(nombre: "Recoil progresivo"); p8.id = id(8)
    p8.antiRecoil.activo = true; p8.antiRecoil.vertical = 35; p8.antiRecoil.progresivo = true
    p8.antiRecoil.verticalFinal = 12; p8.antiRecoil.transicionMs = 700; p8.antiRecoil.soloApuntando = false
    p8.antiRecoil.atajoMantener = .options; p8.antiRecoil.atajoPulsar = .options
    var c8: [(tick: Int, cambio: (inout Perfil) -> Void)] = []
    c8.append((2500, { $0.antiRecoil.transicionMs = 0; $0.antiRecoil.disparar = .x }))
    c8.append((4000, { $0.antiRecoil.activo = false }))
    lista.append(Escenario(nombre: "antirecoil-progresivo", ticks: 5000, perfil: p8, cambios: c8) { i, t in
        var k = Tick()
        if i % 1200 > 100 { k.e.r2 = 255; k.e.botones |= Boton.r2.bit | Boton.x.bit }
        if i == 1900 || i == 3300 { k.e.botones |= Boton.options.bit }
        return k
    })

    // 10. Ayuda en círculos: entrada suave, ceder con el stick, cambios a mitad (patrones, hz, forma)
    var p10 = Perfil(nombre: "Ayuda círculos"); p10.id = id(10)
    p10.ayuda.activo = true; p10.ayuda.boton = .l2; p10.ayuda.aplicarPatron(1)
    var c10: [(tick: Int, cambio: (inout Perfil) -> Void)] = []
    c10.append((1200, { $0.ayuda.aplicarPatron(2) }))
    c10.append((1900, { $0.ayuda.hz = 23 }))
    c10.append((2600, { $0.ayuda.forma = .temblor }))
    c10.append((2700, { $0.ayuda.tamano = 3; $0.ayuda.ceder = 20 }))
    c10.append((3400, { $0.ayuda.aplicarPatron(0); $0.ayuda.entradaMs = 0 }))
    lista.append(Escenario(nombre: "ayuda-circulos", ticks: 5000, perfil: p10, cambios: c10) { i, t in
        var k = Tick()
        if i > 150 && i % 2300 < 2200 { k.e.l2 = 255; k.e.botones |= Boton.l2.bit }
        if i > 800 && i < 1100 { k.e.rx = 255 }
        if i > 1500 && i < 2000 { k.e.ry = onda(t, 0.7, 0.5) }
        if i == 4200 { k.e.botones |= Boton.l2.bit | Boton.arriba.bit }   // la combinación L2 + ↑ la apaga
        k.alternarAyuda = i == 4600
        return k
    })

    // 11. Ayuda en temblor con límites, solo disparando, y con anti-recoil a la vez
    var p11 = Perfil(nombre: "Ayuda temblor"); p11.id = id(11)
    p11.ayuda.activo = true; p11.ayuda.boton = .l2; p11.ayuda.forma = .temblor
    p11.ayuda.tamano = 40; p11.ayuda.hz = 1; p11.ayuda.entradaMs = 900; p11.ayuda.ceder = 100
    p11.ayuda.limites.activos = true; p11.ayuda.limites.tamanoMax = 12; p11.ayuda.limites.hzMin = 6; p11.ayuda.limites.entradaMax = 200
    p11.ayuda.tambienDisparando = true
    p11.antiRecoil.activo = true; p11.antiRecoil.vertical = 18
    var c11: [(tick: Int, cambio: (inout Perfil) -> Void)] = []
    c11.append((2000, { $0.ayuda.limites.tamanoMax = 5 }))
    c11.append((3000, { $0.ayuda.limites.activos = false }))
    lista.append(Escenario(nombre: "ayuda-temblor-limites", ticks: 4500, perfil: p11, cambios: c11) { i, t in
        var k = Tick()
        if i % 1500 > 100 { k.e.l2 = 255; k.e.botones |= Boton.l2.bit }
        if i % 700 > 200 { k.e.r2 = 255; k.e.botones |= Boton.r2.bit }
        k.e.rx = onda(t, 0.25, 0.8)
        return k
    })

    // 12. Todo junto con entradas al azar y cambio de perfil a mitad (empieza de cero)
    var p12 = Perfil(nombre: "Todo"); p12.id = id(12)
    p12.izq.suavizado = 20; p12.der.aceleracion = 25; p12.der.curva = 1.4
    p12.reasignar = ["cuadrado": "triangulo"]; p12.alternar = [.r3]; p12.pulsacionLarga = ["circulo": "share"]
    p12.turbos = [Turbo(id: id(121), boton: .x, hz: 9, ciclo: 50)]
    var m12 = Macro(); m12.id = id(122); m12.disparador = .l3; m12.repetir = true
    p12.macros = [m12]
    p12.antiRecoil.activo = true; p12.antiRecoil.soloApuntando = false
    p12.ayuda.activo = true; p12.ayuda.boton = .r2
    var c12: [(tick: Int, cambio: (inout Perfil) -> Void)] = []
    c12.append((3000, { p in p.id = id(13); p.nombre = "Otro"; p.ayuda.forma = .temblor }))
    var azar = Azar(s: 12)
    var botones: UInt32 = 0
    var lx: UInt8 = 128, ly: UInt8 = 128, rx: UInt8 = 128, ry: UInt8 = 128, l2: UInt8 = 0, r2: UInt8 = 0
    var entradas: [Tick] = []
    for i in 0..<6000 {
        if i % 23 == 0 { botones = UInt32(azar.siguiente() % (1 << 19)) }
        if i % 11 == 0 { lx = azar.byte(); ly = azar.byte() }
        if i % 17 == 0 { rx = azar.byte(); ry = azar.byte() }
        if i % 29 == 0 { l2 = azar.byte(); r2 = azar.byte() }
        var k = Tick()
        k.e = Estado(botones: botones, lx: lx, ly: ly, rx: rx, ry: ry, l2: l2, r2: r2)
        k.alternarAntiRecoil = i % 1700 == 900
        k.alternarAyuda = i % 2100 == 1000
        entradas.append(k)
    }
    lista.append(Escenario(nombre: "todo-al-azar", ticks: 6000, perfil: p12, cambios: c12) { i, _ in entradas[i] })

    return lista
}

func fila(_ e: Estado) -> [Int] { [Int(e.botones), Int(e.lx), Int(e.ly), Int(e.rx), Int(e.ry), Int(e.l2), Int(e.r2)] }

func json<T: Encodable>(_ v: T) -> Any {
    (try? JSONSerialization.jsonObject(with: JSONEncoder().encode(v))) ?? [:]
}

@main struct Generar {
    static func main() {
        let destino = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "procesador.json"
        var salidaTotal: [[String: Any]] = []
        var total = 0
        for esc in escenarios() {
            var p = esc.perfil
            let pr = Procesador()
            var perfiles: [[String: Any]] = [["tick": 0, "perfil": json(p)]]
            var ticks: [[Any]] = []
            for i in 0..<esc.ticks {
                var cambio = false
                for c in esc.cambios where c.tick == i { c.cambio(&p); cambio = true }
                if cambio { perfiles.append(["tick": i, "perfil": json(p)]) }
                let k = esc.entrada(i, tiempo(i))
                if k.alternarAntiRecoil { pr.alternarAntiRecoil() }
                if k.alternarAyuda { pr.alternarAyuda() }
                let t = tiempo(i)
                let s = pr.procesar(k.e, p, t: t)
                let d = pr.diagnostico
                let marcas = (k.alternarAntiRecoil ? 1 : 0) | (k.alternarAyuda ? 2 : 0)
                // [entrada (7), marcas, salida (7), anti-recoil encendido, ayuda encendida, amplitud de la ayuda]
                // (el tiempo no se guarda: la prueba de Rust lo calcula con la misma fórmula, `tiempo(i)`)
                ticks.append(fila(k.e).map { $0 as Any } + [marcas] + fila(s).map { $0 as Any }
                             + [pr.antiRecoilEncendido ? 1 : 0, pr.ayudaEncendida ? 1 : 0,
                                // los bits exactos: JSONSerialization escribe los Double con 16 cifras y no vuelven igual
                                String(d.amplitud.bitPattern, radix: 16)])
            }
            total += esc.ticks
            salidaTotal.append(["nombre": esc.nombre, "perfiles": perfiles, "ticks": ticks])
        }
        let datos = try! JSONSerialization.data(withJSONObject: ["escenarios": salidaTotal])
        try! datos.write(to: URL(fileURLWithPath: destino))
        print("\(salidaTotal.count) escenarios, \(total) ticks → \(destino)")
    }
}
