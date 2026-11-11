import Foundation
@main struct Generar { static func main() {
    var d: [String: String] = [:]
    for i in 0..<AyudaApuntado.patrones.count {
        let bytes = escenarioAyuda(perfilBaseAyuda(patron: i))
        d[AyudaApuntado.patrones[i].nombre] = Data(bytes).base64EncodedString()
    }
    let datos = try! JSONSerialization.data(withJSONObject: d, options: [.prettyPrinted, .sortedKeys])
    try! datos.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
    print("huella guardada:", d.keys.sorted())
}}
