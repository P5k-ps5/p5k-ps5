// Dibuja el icono de la app: baldosa negra y el símbolo en lima, como las demás apps del usuario. El símbolo es el
// mando visto de frente, con un arco abajo que es también el puente. Con «movil» sale a sangre y sin canal alfa,
// porque iOS redondea por su cuenta y no admite transparencia.
import Cocoa

// El mismo trazado que el logo de la web (app/Pagina.swift) y del instalador, en su rejilla de 24
enum Paso { case m(Double, Double), l(Double, Double), c(Double, Double, Double, Double, Double, Double) }
let silueta: [Paso] = [
    .m(7.2, 5), .l(16.8, 5), .c(19.6, 5, 21.6, 7, 22, 9.8), .l(22.9, 15.6), .c(23.3, 18.2, 21.6, 20, 19.6, 20),
    .c(18.2, 20, 17.2, 19.2, 16.4, 18), .c(15.4, 16.4, 14, 15.4, 12, 15.4), .c(10, 15.4, 8.6, 16.4, 7.6, 18),
    .c(6.8, 19.2, 5.8, 20, 4.4, 20), .c(2.4, 20, 0.7, 18.2, 1.1, 15.6), .l(2, 9.8), .c(2.4, 7, 4.4, 5, 7.2, 5),
]
let cruz: [(Double, Double)] = [(6.7, 7.8), (8.6, 7.8), (8.6, 9.8), (10.6, 9.8), (10.6, 11.7), (8.6, 11.7), (8.6, 13.7),
                                (6.7, 13.7), (6.7, 11.7), (4.7, 11.7), (4.7, 9.8), (6.7, 9.8)]
let botones: [(Double, Double)] = [(15.8, 12.2), (18.4, 9.2)]
let radioBoton = 1.5

let movil = CommandLine.arguments.count > 2 && CommandLine.arguments[2] == "movil"
let lado = movil ? 512.0 : 1024.0
// en sRGB: con el perfil de la pantalla, el lima se desviaría del de los demás proyectos
let mapa = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(lado), pixelsHigh: Int(lado), bitsPerSample: 8, samplesPerPixel: movil ? 3 : 4, hasAlpha: !movil,
                            isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 32)!.retagging(with: .sRGB)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: mapa)
NSColor.black.setFill()
if movil {
    NSBezierPath(rect: NSRect(x: 0, y: 0, width: lado, height: lado)).fill()
} else {
    NSBezierPath(roundedRect: NSRect(x: 100, y: 100, width: 824, height: 824), xRadius: 186, yRadius: 186).fill()
}
// El símbolo ocupa 22 de ancho en su rejilla de 24 y es casi el doble de ancho que de alto: la rejilla se escala
// para que quede centrado y grande, porque a 16 px tiene que seguir leyéndose
let escala = lado * (movil ? 0.72 : 0.62) / 22
func punto(_ x: Double, _ y: Double) -> NSPoint { NSPoint(x: lado / 2 + (x - 12) * escala, y: lado / 2 - (y - 12.5) * escala) }

let marca = NSBezierPath()
marca.windingRule = .evenOdd
for p in silueta {
    switch p {
    case let .m(x, y): marca.move(to: punto(x, y))
    case let .l(x, y): marca.line(to: punto(x, y))
    case let .c(a, b, c, d, x, y): marca.curve(to: punto(x, y), controlPoint1: punto(a, b), controlPoint2: punto(c, d))
    }
}
marca.close()
for (i, p) in cruz.enumerated() {
    if i == 0 { marca.move(to: punto(p.0, p.1)) } else { marca.line(to: punto(p.0, p.1)) }
}
marca.close()
for b in botones {
    let r = radioBoton * escala, c = punto(b.0, b.1)
    marca.appendOval(in: NSRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
}
NSColor(srgbRed: 0xC8 / 255.0, green: 0xF0 / 255.0, blue: 0x4D / 255.0, alpha: 1).setFill() // el lima de NeuroClaude, Lens, Rankeo y EcomCreative
marca.fill()
NSGraphicsContext.restoreGraphicsState()
if let png = mapa.representation(using: .png, properties: [:]) {
    try? png.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
}
