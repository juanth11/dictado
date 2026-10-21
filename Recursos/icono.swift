// Dibuja el ícono de Dictado en Halo y arma Recursos/Dictado.icns.
// Uso: swift Recursos/icono.swift   (desde la carpeta de la app)
// Negro con filo de luz, un dial de marcas finas encendido en el tono del volumen y la onda de la voz al centro.
import AppKit

func dibujar(_ lado: Int) -> Data {
    let s = CGFloat(lado), u = s / 1024
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: lado, pixelsHigh: lado, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let c = NSGraphicsContext.current!.cgContext
    let rgb = CGColorSpaceCreateDeviceRGB()
    func color(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
        CGColor(red: CGFloat(hex >> 16 & 255) / 255, green: CGFloat(hex >> 8 & 255) / 255, blue: CGFloat(hex & 255) / 255, alpha: a)
    }

    // Placa de macOS: 824 de lado dentro de 1024, con sombra.
    let placa = CGRect(x: 100 * u, y: 100 * u, width: 824 * u, height: 824 * u)
    let forma = CGPath(roundedRect: placa, cornerWidth: 185 * u, cornerHeight: 185 * u, transform: nil)
    c.saveGState()
    c.setShadow(offset: CGSize(width: 0, height: -10 * u), blur: 24 * u, color: color(0x000000, 0.45))
    c.addPath(forma); c.setFillColor(color(0x000000)); c.fillPath()
    c.restoreGState()

    c.saveGState()
    c.addPath(forma); c.clip()
    // Fondo: negro con un leve vidrio arriba.
    let fondo = CGGradient(colorsSpace: rgb, colors: [color(0x1A1B22), color(0x050507)] as CFArray, locations: [0, 1])!
    c.drawLinearGradient(fondo, start: CGPoint(x: 0, y: placa.maxY), end: CGPoint(x: 0, y: placa.minY), options: [])
    // Luz que nace del borde de abajo, en el tono del volumen.
    let luz = CGGradient(colorsSpace: rgb, colors: [color(0x5280FF, 0.55), color(0x7A66FF, 0.18), color(0x7A66FF, 0)] as CFArray,
                         locations: [0, 0.45, 1])!
    c.drawRadialGradient(luz, startCenter: CGPoint(x: s / 2, y: placa.minY - 60 * u), startRadius: 0,
                         endCenter: CGPoint(x: s / 2, y: placa.minY - 60 * u), endRadius: 520 * u, options: [])
    c.restoreGState()

    // Filo de luz arriba.
    c.saveGState()
    c.addPath(forma); c.setLineWidth(3 * u)
    c.replacePathWithStrokedPath(); c.clip()
    let filo = CGGradient(colorsSpace: rgb, colors: [color(0xFFFFFF, 0.32), color(0xFFFFFF, 0.04), color(0xFFFFFF, 0)] as CFArray,
                          locations: [0, 0.35, 1])!
    c.drawLinearGradient(filo, start: CGPoint(x: 0, y: placa.maxY), end: CGPoint(x: 0, y: placa.minY), options: [])
    c.restoreGState()

    // Dial: 60 marcas finas; se encienden las de 7 a 5 en punto (por abajo, como el nivel de la voz).
    let centro = CGPoint(x: s / 2, y: s / 2 + 8 * u)
    let total = 60, encendidas = 44
    for i in 0..<total {
        // Empieza abajo a la izquierda y gira en sentido horario.
        let t = CGFloat(i) / CGFloat(total)
        let angulo = -.pi / 2 - .pi / 6 - t * 2 * .pi
        let encendida = i < encendidas
        let largo: CGFloat = (i % 5 == 0 ? 46 : 34) * u
        let r1: CGFloat = 300 * u, r0 = r1 - largo
        let a = CGPoint(x: centro.x + cos(angulo) * r0, y: centro.y + sin(angulo) * r0)
        let b = CGPoint(x: centro.x + cos(angulo) * r1, y: centro.y + sin(angulo) * r1)
        c.setLineCap(.round)
        c.setLineWidth((encendida ? 9 : 7) * u)
        if encendida {
            // Del azul al violeta; la última marca, más clara.
            let f = CGFloat(i) / CGFloat(encendidas - 1)
            let tono = i == encendidas - 1 ? color(0xE6DCFF) : mezcla(0x6E98FF, 0xBD94FF, f)
            c.saveGState()
            c.setShadow(offset: .zero, blur: 22 * u, color: tono.copy(alpha: 0.9))
            c.setStrokeColor(tono)
            c.move(to: a); c.addLine(to: b); c.strokePath()
            c.restoreGState()
        } else {
            c.setStrokeColor(color(0xFFFFFF, 0.16))
            c.move(to: a); c.addLine(to: b); c.strokePath()
        }
    }

    // La onda de la voz: siete cápsulas blancas.
    let alturas: [CGFloat] = [70, 140, 230, 300, 210, 130, 80]
    let ancho: CGFloat = 30 * u, paso: CGFloat = 56 * u
    let x0 = centro.x - paso * CGFloat(alturas.count - 1) / 2
    c.saveGState()
    c.setShadow(offset: .zero, blur: 30 * u, color: color(0xA3CCFF, 0.55))
    for (i, h) in alturas.enumerated() {
        let r = CGRect(x: x0 + paso * CGFloat(i) - ancho / 2, y: centro.y - h * u / 2, width: ancho, height: h * u)
        c.addPath(CGPath(roundedRect: r, cornerWidth: ancho / 2, cornerHeight: ancho / 2, transform: nil))
    }
    c.setFillColor(color(0xFFFFFF, 0.96)); c.fillPath()
    c.restoreGState()

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!

    func mezcla(_ x: UInt32, _ y: UInt32, _ f: CGFloat) -> CGColor {
        func canal(_ v: UInt32, _ d: UInt32) -> CGFloat { CGFloat(v >> d & 255) / 255 }
        return CGColor(red: canal(x, 16) + (canal(y, 16) - canal(x, 16)) * f,
                       green: canal(x, 8) + (canal(y, 8) - canal(x, 8)) * f,
                       blue: canal(x, 0) + (canal(y, 0) - canal(x, 0)) * f, alpha: 1)
    }
}

let fm = FileManager.default
let set = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("Dictado.iconset")
try? fm.removeItem(at: set)
try! fm.createDirectory(at: set, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    try! dibujar(base).write(to: set.appendingPathComponent("icon_\(base)x\(base).png"))
    try! dibujar(base * 2).write(to: set.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}
try! dibujar(1024).write(to: URL(fileURLWithPath: "docs/icono.png"))
let p = Process()
p.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
p.arguments = ["-c", "icns", set.path, "-o", "Recursos/Dictado.icns"]
try! p.run(); p.waitUntilExit()
print(p.terminationStatus == 0 ? "Recursos/Dictado.icns y docs/icono.png listos" : "iconutil falló")
