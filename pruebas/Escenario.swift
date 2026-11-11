import Foundation

/// Escenario fijo para comparar el comportamiento de la ayuda al apuntado: 3 s a 1000 Hz con
/// el botón de apuntar pulsado de 0,2 s a 2,6 s y el stick derecho movido por el jugador
/// (a tope de 1,2 a 1,5 s y un vaivén lento de 1,8 a 2,4 s). Devuelve rx, ry de cada tick.
func escenarioAyuda(_ perfil: Perfil, cambios: [(tick: Int, cambio: (inout Perfil) -> Void)] = []) -> [UInt8] {
    var p = perfil
    let pr = Procesador()
    var salida: [UInt8] = []
    salida.reserveCapacity(6000)
    for i in 0..<3000 {
        for c in cambios where c.tick == i { c.cambio(&p) }
        let t = Double(i) / 1000
        var e = Estado()
        if t >= 0.2 && t < 2.6 { e.botones = Boton.l1.bit }
        if t >= 1.2 && t < 1.5 { e.rx = 255 }
        if t >= 1.8 && t < 2.4 { e.ry = UInt8((128 + 40 * sin(2 * .pi * 0.5 * (t - 1.8))).rounded()) }
        let s = pr.procesar(e, p, t: t)
        salida.append(s.rx); salida.append(s.ry)
    }
    return salida
}

/// Perfil base de las comparaciones: ayuda encendida, apuntando con L1, sin anti-recoil
func perfilBaseAyuda(patron i: Int) -> Perfil {
    var p = Perfil()
    p.antiRecoil.activo = false
    p.ayuda.activo = true
    p.ayuda.boton = .l1
    p.ayuda.aplicarPatron(i)
    return p
}
