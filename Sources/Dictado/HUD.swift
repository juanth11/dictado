import AppKit
import Observation
import SwiftUI

/// Lo que pinta el HUD. App lo actualiza desde el hilo principal.
@MainActor @Observable
final class EstadoHUD {
    enum Fase { case escuchando, transcribiendo, resultado }

    var fase = Fase.escuchando
    var nivel = 0.0          // volumen del micrófono, 0…1
    var texto = ""           // vista previa en vivo o resultado
    var icono: String?       // SF Symbol de la nota: "tray.and.arrow.down", "doc.on.clipboard"…
    var nota: String?        // "Guardado en _inbox", "Copiado al portapapeles"…
    var visible = false
    var desde = 0.0          // cuándo apareció (para la animación de entrada)
    var estilo = Estilo.prisma

    /// Sube rápido y baja suave, para que la animación no tiemble.
    func registrarNivel(_ nuevo: Double) {
        nivel = nuevo > nivel ? nuevo : nivel * 0.85 + nuevo * 0.15
    }
}

/// HUD flotante abajo al centro. No roba el foco ni recibe clics.
@MainActor
final class HUD {
    let estado = EstadoHUD()
    private let panel: NSPanel
    private var generacion = 0

    init() {
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: VistaHUD.ancho, height: VistaHUD.alto),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        let vista = NSHostingView(rootView: VistaHUD(estado: estado))
        vista.frame = NSRect(x: 0, y: 0, width: VistaHUD.ancho, height: VistaHUD.alto)
        panel.contentView = vista
    }

    /// `mostrar: false` prepara el estado (lo usa la isla para su Prisma) sin abrir el indicador de abajo.
    func escuchar(inbox: Bool, mostrar: Bool = true) {
        estado.fase = .escuchando
        estado.nivel = 0
        estado.texto = ""
        estado.icono = inbox ? "tray.and.arrow.down" : nil
        estado.nota = inbox ? "A _inbox" : nil
        if mostrar { presentar() }
    }

    func nivel(_ n: Double) { estado.registrarNivel(n) }
    func parcial(_ texto: String) { estado.texto = texto }
    func transcribiendo() { estado.fase = .transcribiendo }

    func resultado(_ texto: String, icono: String? = nil, nota: String? = nil, segundos: Double = 1.4) {
        estado.fase = .resultado
        estado.texto = texto
        estado.icono = icono
        estado.nota = nota
        presentar()
        ocultar(en: segundos)
    }

    func aviso(_ texto: String, icono: String = "exclamationmark.circle", segundos: Double = 2) {
        resultado(texto, icono: icono, segundos: segundos)
    }

    func ocultar(en segundos: Double = 0) {
        let gen = generacion
        DispatchQueue.main.asyncAfter(deadline: .now() + segundos) { [weak self] in
            MainActor.assumeIsolated {
                guard let self, gen == self.generacion else { return }
                NSAnimationContext.runAnimationGroup({ ctx in
                    ctx.duration = 0.3
                    self.panel.animator().alphaValue = 0
                }, completionHandler: { [weak self] in
                    MainActor.assumeIsolated {
                        guard let self, gen == self.generacion else { return }
                        self.panel.orderOut(nil)
                        self.estado.visible = false
                    }
                })
            }
        }
    }

    private func presentar() {
        generacion += 1
        if !estado.visible { estado.desde = Date.timeIntervalSinceReferenceDate }
        if let pantalla = NSScreen.main {
            let zona = pantalla.visibleFrame
            panel.setFrameOrigin(NSPoint(x: zona.midX - VistaHUD.ancho / 2, y: zona.minY + 6))
        }
        estado.visible = true
        panel.alphaValue = 1
        panel.orderFrontRegardless()
    }
}

// MARK: - Vistas

struct VistaHUD: View {
    static let ancho: CGFloat = 440
    static let alto: CGFloat = 236

    let estado: EstadoHUD
    var tiempoFijo: Double?  // para renders estáticos (modo --vista-hud)

    var body: some View {
        if let tiempoFijo {
            contenido(tiempoFijo, entrada: 1)
        } else {
            TimelineView(.animation(paused: !estado.visible)) { ctx in
                let t = ctx.date.timeIntervalSinceReferenceDate
                contenido(t, entrada: min(max((t - estado.desde) / 0.45, 0), 1))
            }
        }
    }

    private func contenido(_ t: Double, entrada: Double) -> some View {
        let e = 1 - pow(1 - entrada, 3)  // ease-out
        return VStack(spacing: 4) {
            Spacer(minLength: 0)
            if !estado.texto.isEmpty || estado.nota != nil {
                Tarjeta(estado: estado, simulado: tiempoFijo != nil)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
            Visual(estado: estado, t: t)
                .frame(width: 380, height: 118)
                .scaleEffect(0.86 + 0.14 * e)
                .opacity(e)
        }
        .frame(width: Self.ancho, height: Self.alto)
        .animation(.spring(duration: 0.35), value: estado.texto.isEmpty)
    }
}

/// Texto minimalista sobre vidrio claro: letra oscura del sistema, sin colores.
struct Tarjeta: View {
    let estado: EstadoHUD
    let simulado: Bool

    var body: some View {
        let forma = RoundedRectangle(cornerRadius: 16, style: .continuous)
        let contenido = VStack(alignment: .leading, spacing: 4) {
            if let nota = estado.nota {
                Label(nota, systemImage: estado.icono ?? "checkmark")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            if !estado.texto.isEmpty {
                Text(estado.texto)
                    .font(.system(size: 13, weight: estado.fase == .resultado ? .medium : .regular))
                    .foregroundStyle(estado.fase == .resultado ? .primary : .secondary)
                    .lineLimit(2)
                    .truncationMode(.head)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: 340, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)

        Group {
            if simulado {  // el render fuera de pantalla no tiene escritorio detrás para el vidrio
                contenido
                    .background(forma.fill(.white.opacity(0.86)))
                    .overlay(forma.stroke(.white.opacity(0.9), lineWidth: 0.6))
            } else {
                contenido.glassEffect(.regular, in: forma)
            }
        }
        .shadow(color: .black.opacity(0.18), radius: 14, y: 6)
        .environment(\.colorScheme, .light)
    }
}

/// Eco de voz: núcleo luminoso orgánico + medialunas que se alejan y se enfrían (rosa → violeta → azul).
/// Escuchando: las ondas salen al ritmo de la voz. Transcribiendo: convergen hacia el núcleo.
struct Eco: View {
    let estado: EstadoHUD
    let t: Double

    var body: some View {
        Canvas { ctx, tam in
            let c = CGPoint(x: tam.width / 2, y: tam.height / 2)
            let nivel: Double
            switch estado.fase {
            case .escuchando: nivel = estado.nivel
            case .transcribiendo: nivel = 0.5 + 0.12 * sin(t * 5)
            case .resultado: nivel = 0.12
            }

            // Halo violeta muy suave: separa el eco del fondo sin dibujar una caja.
            ctx.drawLayer { capa in
                capa.addFilter(.blur(radius: 26))
                let halo = CGRect(x: 60, y: c.y - 22, width: tam.width - 120, height: 44)
                capa.fill(Path(roundedRect: halo, cornerRadius: 22),
                          with: .color(Color(red: 0.16, green: 0.08, blue: 0.30).opacity(0.38)))
            }

            // Capas de onda: medialunas con volumen que nacen del núcleo y se alejan enfriándose.
            let radio = 22 + 10 * nivel
            let ondas = 5
            let velocidad = estado.fase == .transcribiendo ? 0.75 : 0.28 + 0.5 * nivel
            for i in (0..<ondas).reversed() {
                var p = (t * velocidad + Double(i) / Double(ondas)).truncatingRemainder(dividingBy: 1)
                if estado.fase == .transcribiendo { p = 1 - p }
                let alto = (radio * 1.25 + 12 * nivel) * (1 - 0.55 * p)
                let alfa = pow(1 - p, 1.2) * min(1, p * 5) * (0.45 + 0.55 * nivel)
                let color = Self.colorOnda(p)
                for lado in [-1.0, 1.0] {
                    let x = c.x + lado * (radio * 0.9 + p * 150)
                    let capaOnda = Self.capa(x: x, y: c.y, alto: alto, bulto: 9 + 9 * (1 - p), grosor: 4 + 7 * (1 - p), lado: lado)
                    ctx.drawLayer { capa in  // volumen
                        capa.addFilter(.blur(radius: 4 + 3 * p))
                        capa.opacity = alfa * 0.75
                        capa.fill(capaOnda.cuerpo, with: .linearGradient(
                            Gradient(colors: [color.opacity(0.15), color]),
                            startPoint: CGPoint(x: x - lado * 14, y: c.y), endPoint: CGPoint(x: x + lado * 10, y: c.y)))
                    }
                    ctx.drawLayer { capa in  // borde brillante
                        capa.addFilter(.blur(radius: 1.2))
                        capa.opacity = alfa
                        capa.stroke(capaOnda.borde, with: .color(Self.mezclar(color, .white, 0.3)),
                                    style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                    }
                }
            }

            // Núcleo orgánico que respira y se deforma con la voz.
            let nucleo = Self.burbuja(c, radio: radio, t: t, nivel: nivel)
            let relleno = GraphicsContext.Shading.radialGradient(
                Gradient(colors: [Color(red: 1.0, green: 0.68, blue: 0.40), Color(red: 1.0, green: 0.45, blue: 0.48),
                                  Color(red: 0.98, green: 0.33, blue: 0.70), Color(red: 0.72, green: 0.32, blue: 0.98)]),
                center: CGPoint(x: c.x - radio * 0.3, y: c.y), startRadius: 0, endRadius: radio * 1.6)
            ctx.drawLayer { capa in
                capa.addFilter(.blur(radius: 16))
                capa.opacity = 0.55 + 0.35 * nivel
                capa.fill(nucleo, with: relleno)
            }
            ctx.drawLayer { capa in
                capa.addFilter(.blur(radius: 2))
                capa.fill(nucleo, with: relleno)
            }
            ctx.drawLayer { capa in  // borde de luz
                capa.addFilter(.blur(radius: 1))
                capa.opacity = 0.55
                capa.stroke(nucleo, with: .color(.white.opacity(0.7)), lineWidth: 1)
            }
        }
        .hueRotation(.degrees(estado.fase == .transcribiendo ? sin(t * 1.8) * 22 : sin(t * 0.5) * 8))
    }

    /// Medialuna con volumen ")" (o "(" a la izquierda): gruesa al centro, se afina en las puntas.
    static func capa(x: CGFloat, y: CGFloat, alto: CGFloat, bulto: CGFloat, grosor: CGFloat, lado: Double)
        -> (cuerpo: Path, borde: Path) {
        func semielipse(_ ancho: CGFloat) -> [CGPoint] {
            (0...24).map { k in
                let a = -Double.pi / 2 + Double(k) / 24 * .pi
                return CGPoint(x: x + lado * ancho * cos(a), y: y + alto * sin(a))
            }
        }
        let externa = semielipse(bulto)
        let interna = semielipse(max(bulto - grosor, 0)).reversed()
        var cuerpo = Path()
        cuerpo.addLines(externa + interna)
        cuerpo.closeSubpath()
        var borde = Path()
        borde.addLines(externa)
        return (cuerpo, borde)
    }

    /// Contorno polar con armónicos que se mueven: forma viva, más ancha que alta.
    static func burbuja(_ c: CGPoint, radio: CGFloat, t: Double, nivel: Double) -> Path {
        var p = Path()
        let puntos = 72
        for k in 0...puntos {
            let a = Double(k) / Double(puntos) * 2 * .pi
            let deformacion = 1
                + (0.05 + 0.10 * nivel) * sin(3 * a + t * 2.3)
                + 0.05 * sin(5 * a - t * 1.7)
                + 0.03 * sin(2 * a + t * 0.9)
                + 0.025 * sin(t * 1.4)
            let r = radio * deformacion
            let punto = CGPoint(x: c.x + 1.18 * r * cos(a), y: c.y + r * sin(a))
            k == 0 ? p.move(to: punto) : p.addLine(to: punto)
        }
        p.closeSubpath()
        return p
    }

    static func colorOnda(_ p: Double) -> Color {
        let tramos: [(Double, (Double, Double, Double))] = [
            (0.0, (1.00, 0.42, 0.62)), (0.3, (0.86, 0.36, 0.95)),
            (0.6, (0.52, 0.42, 1.00)), (1.0, (0.30, 0.52, 1.00)),
        ]
        for (a, b) in zip(tramos, tramos.dropFirst()) where p <= b.0 {
            let f = (p - a.0) / (b.0 - a.0)
            return Color(red: a.1.0 + (b.1.0 - a.1.0) * f, green: a.1.1 + (b.1.1 - a.1.1) * f,
                         blue: a.1.2 + (b.1.2 - a.1.2) * f)
        }
        return Color(red: 0.30, green: 0.52, blue: 1.00)
    }

    static func mezclar(_ a: Color, _ b: Color, _ f: Double) -> Color {
        let ca = NSColor(a).usingColorSpace(.sRGB) ?? .white
        let cb = NSColor(b).usingColorSpace(.sRGB) ?? .white
        return Color(red: ca.redComponent + (cb.redComponent - ca.redComponent) * f,
                     green: ca.greenComponent + (cb.greenComponent - ca.greenComponent) * f,
                     blue: ca.blueComponent + (cb.blueComponent - ca.blueComponent) * f)
    }
}
