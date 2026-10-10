import AppKit
import SwiftUI

/// Maqueta (solo render, no está en la app): variante «Mosaicos» de la isla para comparar con la de diales.
/// Sin pestañas: al abrirla se ve todo a la vez en mosaicos de color (música, reunión, Mac, agentes); números
/// gruesos redondeados en vez de finos; barras por bloques en vez de anillos; avisos con ícono en cuadro de color.
/// `Dictado --vista-mosaicos salida.png`
@MainActor
func hojaMosaicos(_ destino: URL) -> Bool {
    let fondo = fondoDeMuestra()
    let caratula = NSImage(size: NSSize(width: 300, height: 300))
    caratula.lockFocus()
    fondo.draw(in: NSRect(x: 0, y: 0, width: 300, height: 300), from: NSRect(x: 1500, y: 600, width: 900, height: 900),
               operation: .copy, fraction: 1)
    caratula.unlockFocus()

    func escena<C: View>(alto: CGFloat, ancho: CGFloat = 760, isla: CGSize, radio: CGFloat, @ViewBuilder _ contenido: () -> C) -> some View {
        ZStack(alignment: .top) {
            Image(nsImage: fondo).resizable().scaledToFill().frame(width: ancho, height: alto, alignment: .top).clipped()
            Rectangle().fill(.white.opacity(0.18)).frame(height: 32)
            ZStack(alignment: .top) {
                FormaIsla(radio: radio).fill(.black).shadow(color: .black.opacity(0.35), radius: 18, y: 8)
                contenido()
            }
            .frame(width: isla.width, height: isla.height)
        }
        .frame(width: ancho, height: alto)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
    let notch: CGFloat = 32
    let w = 186 + 2 * FormaIsla.hombro
    func aviso(_ ancho: CGFloat, _ alto: CGFloat) -> CGSize { CGSize(width: w + 2 * ancho, height: notch + alto) }

    let hoja = VStack(spacing: 14) {
        HStack(spacing: 14) {
            escena(alto: 150, isla: aviso(130, 58), radio: 24) {
                AvisoMosaico(color: M.ambar, simbolo: "server.rack", rotulo: "Alerta · Agente del servidor",
                             titulo: "resumen-finanzas falló", detalle: "el banco no respondió", boton: "Ver")
            }
            escena(alto: 150, isla: aviso(140, 58), radio: 24) {
                AvisoMosaico(color: .claude, estrella: true, rotulo: "Necesita tu permiso",
                             titulo: "Rediseño del sitio web", detalle: "Terminal · swift build -c release", boton: "Responder")
            }
        }
        HStack(spacing: 14) {
            escena(alto: 150, isla: aviso(135, 46), radio: 24) {
                NivelMosaico(color: M.azul, simbolo: "speaker.wave.3.fill", rotulo: "Volumen · AirPods Pro", valor: 0.62)
            }
            escena(alto: 150, isla: aviso(135, 46), radio: 24) {
                NivelMosaico(color: M.ambar, simbolo: "sun.max.fill", rotulo: "Brillo · Pantalla", valor: 0.81)
            }
        }
        HStack(spacing: 14) {
            escena(alto: 150, isla: aviso(135, 46), radio: 24) {
                NivelMosaico(color: M.rojo, simbolo: "speaker.slash.fill", rotulo: "Silencio · AirPods Pro", valor: 0.62, mudo: true)
            }
            escena(alto: 150, isla: aviso(150, 58), radio: 24) {
                ReunionMosaico()
            }
        }
        escena(alto: 300, isla: CGSize(width: 680, height: 250), radio: 34) {
            AbiertaMosaicos(caratula: caratula, calma: false)
        }
        escena(alto: 300, isla: CGSize(width: 680, height: 250), radio: 34) {
            AbiertaMosaicos(caratula: caratula, calma: true)
        }
    }
    .padding(14)
    .background(Color(white: 0.08))
    .environment(\.colorScheme, .dark)

    let renderer = ImageRenderer(content: hoja)
    renderer.scale = 2
    guard let cg = renderer.cgImage,
          let png = NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:]) else { return false }
    return (try? png.write(to: destino)) != nil
}

/// Tokens de la variante: colores planos y vivos, números gruesos redondeados, rótulos en versalitas.
private enum M {
    static let azul = Color(red: 0.25, green: 0.52, blue: 1.0)
    static let verde = Color(red: 0.22, green: 0.80, blue: 0.45)
    static let ambar = Color(red: 1.0, green: 0.66, blue: 0.16)
    static let rojo = Color(red: 1.0, green: 0.33, blue: 0.30)
    static let violeta = Color(red: 0.58, green: 0.44, blue: 1.0)

    static func numero(_ tam: CGFloat) -> Font { .system(size: tam, weight: .bold, design: .rounded) }
}

private struct RotuloM: View {
    let texto: String
    var color: Color = .white.opacity(0.6)

    var body: some View {
        Text(texto.uppercased()).font(.system(size: 9, weight: .heavy, design: .rounded)).tracking(0.8)
            .foregroundStyle(color).lineLimit(1)
    }
}

/// Ícono en un cuadro redondeado de color, como el de una app.
private struct Cuadro: View {
    let color: Color
    var simbolo = ""
    var estrella = false
    var lado: CGFloat = 34

    var body: some View {
        RoundedRectangle(cornerRadius: lado * 0.3, style: .continuous)
            .fill(LinearGradient(colors: [color, color.opacity(0.72)], startPoint: .top, endPoint: .bottom))
            .overlay {
                if estrella {
                    EstrellaClaude().fill(.white).frame(width: lado * 0.5, height: lado * 0.5)
                } else {
                    Image(systemName: simbolo).font(.system(size: lado * 0.42, weight: .bold)).foregroundStyle(.white)
                }
            }
            .frame(width: lado, height: lado)
    }
}

/// Un mosaico: fondo oscuro con su color en degradado y un filo de luz arriba.
private struct Mosaico<C: View>: View {
    let color: Color
    var fuerza = 0.34
    @ViewBuilder let contenido: () -> C

    var body: some View {
        contenido()
            .padding(12)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background {
                let forma = RoundedRectangle(cornerRadius: 18, style: .continuous)
                ZStack {
                    forma.fill(Color(white: 0.10))
                    forma.fill(LinearGradient(colors: [color.opacity(fuerza), color.opacity(fuerza * 0.35)],
                                              startPoint: .topLeading, endPoint: .bottomTrailing))
                    forma.strokeBorder(LinearGradient(colors: [.white.opacity(0.16), .white.opacity(0.02)],
                                                      startPoint: .top, endPoint: .bottom), lineWidth: 1)
                }
            }
    }
}

/// Barra por bloques: 20 bloques; los encendidos en el color, el último más claro.
private struct Bloques: View {
    let valor: Double
    let color: Color
    var cuantos = 20
    var apagado = false

    var body: some View {
        let encendidos = Int((valor * Double(cuantos)).rounded())
        HStack(spacing: 3) {
            ForEach(0..<cuantos, id: \.self) { i in
                RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                    .fill(i < encendidos ? (apagado ? Color.white.opacity(0.22) : color.opacity(0.55 + 0.45 * Double(i) / Double(cuantos)))
                                         : Color.white.opacity(0.09))
                    .frame(width: 7, height: 16)
            }
        }
    }
}

// MARK: Avisos

private struct AvisoMosaico: View {
    let color: Color
    var simbolo = ""
    var estrella = false
    let rotulo: String
    let titulo: String
    let detalle: String
    let boton: String

    var body: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: 32)
            HStack(spacing: 12) {
                Cuadro(color: color, simbolo: simbolo, estrella: estrella, lado: 38)
                VStack(alignment: .leading, spacing: 2) {
                    RotuloM(texto: rotulo, color: color)
                    Text(titulo).font(.system(size: 14, weight: .bold, design: .rounded)).foregroundStyle(.white).lineLimit(1)
                    Text(detalle).font(.system(size: 11, weight: .medium)).foregroundStyle(.white.opacity(0.55)).lineLimit(1)
                }
                Spacer(minLength: 6)
                Text(boton).font(.system(size: 12.5, weight: .bold, design: .rounded)).foregroundStyle(.black)
                    .padding(.horizontal, 14).frame(height: 30)
                    .background(Capsule().fill(color))
            }
            .padding(.horizontal, 24)
            .frame(maxHeight: .infinity)
        }
    }
}

private struct NivelMosaico: View {
    let color: Color
    let simbolo: String
    let rotulo: String
    let valor: Double
    var mudo = false

    var body: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: 32)
            HStack(spacing: 12) {
                Cuadro(color: mudo ? Color(white: 0.25) : color, simbolo: simbolo, lado: 30)
                    .overlay(alignment: .topTrailing) {
                        if mudo { Circle().fill(M.rojo).frame(width: 9, height: 9).offset(x: 3, y: -3) }
                    }
                VStack(alignment: .leading, spacing: 5) {
                    RotuloM(texto: rotulo, color: mudo ? M.rojo : .white.opacity(0.55))
                    Bloques(valor: valor, color: color, apagado: mudo)
                }
                Spacer(minLength: 4)
                if mudo {
                    Text("Mudo").font(M.numero(20)).foregroundStyle(.white.opacity(0.85))
                } else {
                    HStack(alignment: .firstTextBaseline, spacing: 1) {
                        Text("\(Int(valor * 100))").font(M.numero(26)).monospacedDigit().foregroundStyle(.white)
                        Text("%").font(M.numero(12)).foregroundStyle(.white.opacity(0.5))
                    }
                }
            }
            .padding(.horizontal, 24)
            .frame(maxHeight: .infinity)
        }
    }
}

private struct ReunionMosaico: View {
    var body: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: 32)
            HStack(spacing: 12) {
                Cuadro(color: M.azul, simbolo: "video.fill", lado: 38)
                VStack(alignment: .leading, spacing: 2) {
                    RotuloM(texto: "Empieza en · Meet", color: M.azul)
                    Text("Revisión de contrato").font(.system(size: 14, weight: .bold, design: .rounded)).foregroundStyle(.white).lineLimit(1)
                    Text("8:53 – 9:38 p. m.").font(.system(size: 11, weight: .medium)).foregroundStyle(.white.opacity(0.55))
                }
                Spacer(minLength: 6)
                Text("4:12").font(M.numero(30)).monospacedDigit().foregroundStyle(.white)
                Label("Unirse", systemImage: "video.fill").font(.system(size: 12.5, weight: .bold, design: .rounded))
                    .foregroundStyle(.black).padding(.horizontal, 13).frame(height: 30)
                    .background(Capsule().fill(M.verde))
            }
            .padding(.horizontal, 24)
            .frame(maxHeight: .infinity)
        }
    }
}

// MARK: Isla abierta

/// Todo a la vez: música a la izquierda; reunión y Mac en el centro; agentes a la derecha.
/// `calma`: nadie te espera, el Mac está bien y el agente del servidor tiene una alerta.
private struct AbiertaMosaicos: View {
    let caratula: NSImage
    let calma: Bool

    var body: some View {
        HStack(spacing: 8) {
            MusicaMosaico(caratula: caratula).frame(width: 206)
            VStack(spacing: 8) {
                if calma { AgendaVaciaMosaico() } else { ProximaMosaico() }
                MacMosaico(lleno: !calma)
            }
            .frame(width: 196)
            AgentesMosaico(calma: calma)
        }
        .padding(.horizontal, 22)
        .padding(.top, 38)
        .padding(.bottom, 14)
    }
}

private struct MusicaMosaico: View {
    let caratula: NSImage

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                Image(nsImage: caratula).resizable().scaledToFill().frame(width: 62, height: 62)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .shadow(color: .black.opacity(0.4), radius: 8, y: 4)
                Spacer()
                Image(systemName: "waveform").font(.system(size: 15, weight: .bold)).foregroundStyle(.white.opacity(0.85))
            }
            Spacer(minLength: 8)
            Text("Weightless").font(.system(size: 16, weight: .bold, design: .rounded)).foregroundStyle(.white).lineLimit(1)
            Text("Marconi Union").font(.system(size: 12, weight: .medium)).foregroundStyle(.white.opacity(0.65)).lineLimit(1)
            Spacer(minLength: 8)
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.22))
                    Capsule().fill(.white).frame(width: g.size.width * 0.31)
                }
            }
            .frame(height: 5)
            HStack {
                Text("2:31"); Spacer(); Text("-5:29")
            }
            .font(.system(size: 9.5, weight: .semibold, design: .rounded)).monospacedDigit().foregroundStyle(.white.opacity(0.55))
            .padding(.top, 4)
            HStack {
                Image(systemName: "backward.fill")
                Spacer()
                Image(systemName: "pause.fill").font(.system(size: 15, weight: .bold)).foregroundStyle(.black)
                    .frame(width: 36, height: 36).background(Circle().fill(.white))
                Spacer()
                Image(systemName: "forward.fill")
            }
            .font(.system(size: 15, weight: .bold)).foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.top, 6)
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background {
            let forma = RoundedRectangle(cornerRadius: 18, style: .continuous)
            ZStack {
                Image(nsImage: caratula).resizable().scaledToFill().blur(radius: 26).scaleEffect(1.4)
                Color.black.opacity(0.38)
                LinearGradient(colors: [.clear, .black.opacity(0.35)], startPoint: .top, endPoint: .bottom)
            }
            .clipShape(forma)
            .overlay(forma.strokeBorder(.white.opacity(0.12), lineWidth: 1))
        }
    }
}

private struct ProximaMosaico: View {
    var body: some View {
        Mosaico(color: M.azul, fuerza: 0.42) {
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    RotuloM(texto: "Empieza en · Meet", color: Color(red: 0.6, green: 0.78, blue: 1))
                    Spacer()
                    Image(systemName: "video.fill").font(.system(size: 11, weight: .bold)).foregroundStyle(.black)
                        .frame(width: 26, height: 26).background(Circle().fill(M.verde))
                }
                .frame(height: 16)
                Text("4:12").font(M.numero(30)).monospacedDigit().foregroundStyle(.white)
                Text("Revisión de contrato").font(.system(size: 11.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.85)).lineLimit(1)
            }
        }
    }
}

private struct AgendaVaciaMosaico: View {
    var body: some View {
        Mosaico(color: M.violeta, fuerza: 0.26) {
            VStack(alignment: .leading, spacing: 3) {
                RotuloM(texto: "Agenda")
                Text("Libre").font(M.numero(30)).foregroundStyle(.white)
                Text("Mañana 9:00 a. m. · Comité").font(.system(size: 11.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.65)).lineLimit(1)
            }
        }
    }
}

private struct MacMosaico: View {
    let lleno: Bool

    var body: some View {
        let color = lleno ? M.rojo : M.verde
        Mosaico(color: color, fuerza: lleno ? 0.4 : 0.26) {
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    RotuloM(texto: lleno ? "Mac · disco casi lleno" : "Mac · todo bien", color: lleno ? Color(red: 1, green: 0.62, blue: 0.58) : .white.opacity(0.6))
                    Spacer()
                    Image(systemName: "arrow.up.forward").font(.system(size: 10, weight: .heavy)).foregroundStyle(.white.opacity(0.6))
                }
                .frame(height: 16)
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(lleno ? "7,9" : "46").font(M.numero(30)).foregroundStyle(.white)
                    Text(lleno ? "GB libres" : "% procesador").font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.6))
                }
                HStack(spacing: 8) {
                    Medida(titulo: "CPU", valor: 0.46)
                    Medida(titulo: "RAM", valor: 0.81)
                    Medida(titulo: "GPU", valor: 0.23)
                    Medida(titulo: "Disco", valor: lleno ? 0.97 : 0.6)
                }
            }
        }
    }

    private struct Medida: View {
        let titulo: String
        let valor: Double

        var body: some View {
            let color = valor > 0.9 ? M.rojo : valor > 0.75 ? M.ambar : M.verde
            VStack(alignment: .leading, spacing: 2) {
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.white.opacity(0.14))
                        Capsule().fill(color).frame(width: max(3, g.size.width * valor))
                    }
                }
                .frame(height: 3.5)
                Text(titulo).font(.system(size: 8, weight: .heavy, design: .rounded)).foregroundStyle(.white.opacity(0.45))
            }
        }
    }
}

private struct AgentesMosaico: View {
    let calma: Bool

    var body: some View {
        Mosaico(color: calma ? M.ambar : .claude, fuerza: 0.3) {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    RotuloM(texto: "Agentes · 4")
                    Spacer()
                    BarrasHoy()
                }
                .frame(height: 14)
                Text(calma ? "1 alerta" : "1 te espera").font(M.numero(24))
                    .foregroundStyle(calma ? M.ambar : Color(red: 1, green: 0.62, blue: 0.46))
                    .padding(.top, 2)
                VStack(alignment: .leading, spacing: 7) {
                    if calma {
                        FilaM(icono: AnyView(Cuadro(color: M.ambar, simbolo: "server.rack", lado: 22)),
                              titulo: "Agente del servidor", detalle: "resumen-finanzas falló", detalleColor: M.ambar,
                              derecha: AnyView(TareasBloques(estados: ["ok", "ok", "error", "ok", "corriendo", "ok"])))
                        FilaM(icono: AnyView(Cuadro(color: .claude, estrella: true, lado: 22)),
                              titulo: "Informe trimestral", detalle: "Editando HeroSection.tsx · 4 min",
                              derecha: AnyView(Contexto(texto: "768 k")))
                        FilaM(icono: AnyView(Cuadro(color: Color(white: 0.3), simbolo: "checkmark", lado: 22)),
                              titulo: "Correos pendientes", detalle: "Lista · hace 25 min",
                              derecha: AnyView(EmptyView()))
                    } else {
                        FilaM(icono: AnyView(Cuadro(color: .claude, estrella: true, lado: 22)),
                              titulo: "Rediseño del sitio web", detalle: "Necesita tu permiso",
                              detalleColor: Color(red: 1, green: 0.62, blue: 0.46), derecha: AnyView(EmptyView()))
                        FilaM(icono: AnyView(Cuadro(color: .claude.opacity(0.55), estrella: true, lado: 22)),
                              titulo: "Informe trimestral", detalle: "Editando HeroSection.tsx · 4 min",
                              derecha: AnyView(Contexto(texto: "768 k")))
                        FilaM(icono: AnyView(Cuadro(color: M.verde, simbolo: "server.rack", lado: 22)),
                              titulo: "Agente del servidor", detalle: "6 tareas · todo bien",
                              derecha: AnyView(TareasBloques(estados: ["ok", "ok", "ok", "ok", "corriendo", "ok"])))
                    }
                }
                .padding(.top, 8)
            }
        }
    }

    private struct FilaM: View {
        let icono: AnyView
        let titulo: String
        let detalle: String
        var detalleColor: Color = .white.opacity(0.5)
        let derecha: AnyView

        var body: some View {
            HStack(spacing: 8) {
                icono
                VStack(alignment: .leading, spacing: 0) {
                    Text(titulo).font(.system(size: 11.5, weight: .bold, design: .rounded)).foregroundStyle(.white).lineLimit(1)
                    Text(detalle).font(.system(size: 9.5, weight: .medium)).foregroundStyle(detalleColor).lineLimit(1)
                }
                Spacer(minLength: 2)
                derecha
            }
        }
    }

    private struct Contexto: View {
        let texto: String

        var body: some View {
            Text(texto).font(.system(size: 9, weight: .bold, design: .rounded)).monospacedDigit()
                .foregroundStyle(M.ambar)
                .padding(.horizontal, 6).frame(height: 16)
                .background(Capsule().fill(M.ambar.opacity(0.14)))
                .help("Contexto de esta conversación: pasa de ~600 k, conviene abrir una nueva")
        }
    }

    /// Un bloque por tarea: verde bien, rojo falló, blanco corriendo.
    private struct TareasBloques: View {
        let estados: [String]

        var body: some View {
            HStack(spacing: 2) {
                ForEach(Array(estados.enumerated()), id: \.offset) { _, e in
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(e == "error" ? M.rojo : e == "corriendo" ? .white : M.verde)
                        .frame(width: 4, height: 11)
                }
            }
        }
    }

    /// Tokens de Claude por hora (últimas 8): bloques en vez de rayitas.
    private struct BarrasHoy: View {
        var body: some View {
            let valores: [Double] = [0.1, 0.3, 1, 0.8, 0.2, 0, 0.4, 0.6]
            HStack(alignment: .bottom, spacing: 2) {
                ForEach(Array(valores.enumerated()), id: \.offset) { i, v in
                    RoundedRectangle(cornerRadius: 1.2)
                        .fill(i == valores.count - 1 ? Color.claude : .white.opacity(0.35))
                        .frame(width: 4, height: max(2, 12 * v))
                }
            }
            .frame(height: 12, alignment: .bottom)
        }
    }
}
