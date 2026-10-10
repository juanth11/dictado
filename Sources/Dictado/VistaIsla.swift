import AppKit
import SwiftUI

/// Forma del notch: arriba plana con hombros cóncavos que se funden con la barra de menú, abajo redondeada.
struct FormaIsla: Shape {
    static let hombro: CGFloat = 8
    var radio: CGFloat

    var animatableData: CGFloat {
        get { radio }
        set { radio = newValue }
    }

    func path(in r: CGRect) -> Path {
        let h = Self.hombro
        let ri = min(radio, (r.height - h) / 2, (r.width - 2 * h) / 2)
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.minY))
        p.addQuadCurve(to: CGPoint(x: r.minX + h, y: r.minY + h), control: CGPoint(x: r.minX + h, y: r.minY))
        p.addLine(to: CGPoint(x: r.minX + h, y: r.maxY - ri))
        p.addQuadCurve(to: CGPoint(x: r.minX + h + ri, y: r.maxY), control: CGPoint(x: r.minX + h, y: r.maxY))
        p.addLine(to: CGPoint(x: r.maxX - h - ri, y: r.maxY))
        p.addQuadCurve(to: CGPoint(x: r.maxX - h, y: r.maxY - ri), control: CGPoint(x: r.maxX - h, y: r.maxY))
        p.addLine(to: CGPoint(x: r.maxX - h, y: r.minY + h))
        p.addQuadCurve(to: CGPoint(x: r.maxX, y: r.minY), control: CGPoint(x: r.maxX - h, y: r.minY))
        p.closeSubpath()
        return p
    }
}

struct VistaIsla: View {
    let estado: EstadoIsla
    let musica: Musica
    let agenda: Agenda
    let hud: EstadoHUD
    let privacidad: Privacidad
    let claude: SesionesClaude
    let agentes: AgentesRemotos
    let salud: EstadoSalud
    let control: Isla?

    private var alas: Bool { musica.hayPista || agenda.inminente != nil || privacidad.activo || claude.hayActividad }

    var body: some View {
        let tam = estado.tamano(alas: alas, punto: privacidad.activo)
        let radio: CGFloat = estado.expandida ? 34 : (estado.actividad != nil ? 24 : 10)
        ZStack(alignment: .top) {
            FormaIsla(radio: radio)
                .fill(.black)
                .shadow(color: .black.opacity(estado.expandida || estado.actividad != nil ? 0.35 : 0), radius: 18, y: 8)
            ZStack(alignment: .top) {
                contenido
                    .id(estado.expandida ? UUID(uuidString: "00000000-0000-0000-0000-000000000001")! : estado.idActividad)
                    .transition(.asymmetric(  // crece desde el notch y se enfoca
                        insertion: .modifier(active: Enfoque(activo: true), identity: Enfoque(activo: false)),
                        removal: .opacity))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .clipShape(FormaIsla(radio: radio))  // los resplandores no se salen de la isla
        }
        .frame(width: tam.width, height: tam.height)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(Halo.morfosis, value: estado.expandida)
        .animation(Halo.entrada, value: estado.idActividad)
        .animation(Halo.cambio, value: alas)
        .animation(Halo.cambio, value: privacidad.activo)
        .environment(\.colorScheme, .dark)
        .onChange(of: alas) { control?.refrescarCompacta() }
        .onChange(of: privacidad.activo) { control?.refrescarCompacta() }
    }

    @ViewBuilder private var contenido: some View {
        if estado.expandida {
            Expandida(estado: estado, musica: musica, agenda: agenda, privacidad: privacidad, claude: claude, agentes: agentes,
                      salud: salud, simulado: control == nil,
                      unirse: { control?.unirse($0) }, abrirSalud: { control?.abrirSalud() }, medirSalud: { control?.medirSalud() })
        } else if let actividad = estado.actividad {
            switch actividad {
            case .dictado:
                DictadoIsla(estado: estado, hud: hud)
            case .aviso(let icono, let texto):
                let tono: Tono = icono == "exclamationmark.triangle" ? .ambar : .verde
                Fila(notch: estado.notch, tono: tono) {
                    IconoSaltarin(simbolo: icono, color: tono.claro)
                    Text(texto).font(Halo.titulo).foregroundStyle(Halo.texto).lineLimit(1)
                }
            case .cancion:
                AhoraSuena(estado: estado, musica: musica)
            case .evento(let titulo, let inicio, let color, let enlace):
                EventoIsla(estado: estado, titulo: titulo, inicio: inicio, color: color, enlace: enlace) { control?.unirse($0) }
            case .carga(let porcentaje):
                CargaIsla(estado: estado, porcentaje: porcentaje)
            case .nivel(let tipo, let valor, let silencio, let salida):
                BarraNivel(estado: estado, tipo: tipo, valor: valor, silencio: silencio, salida: salida)
            case .salud(let titulo, let detalle, let grave):
                SaludIsla(estado: estado, titulo: titulo, detalle: detalle, grave: grave) { control?.abrirSalud() }
            case .claude(let sesion, let necesita, let duracion):
                ClaudeIsla(estado: estado, sesion: sesion, necesita: necesita, duracion: duracion) { control?.abrirClaude(sesion) }
            case .agente(let nombre, let alerta, let caido):
                AgenteIsla(estado: estado, nombre: nombre, alerta: alerta, caido: caido) { control?.verAgente(nombre) }
            }
        } else if alas {
            Compacta(estado: estado, musica: musica, agenda: agenda, privacidad: privacidad, claude: claude)
        }
    }
}

/// Una fila de contenido debajo del notch (para los avisos cortos), con la luz de su tono subiendo desde el borde.
private struct Fila<Contenido: View>: View {
    let notch: CGSize
    var tono: Tono?
    @ViewBuilder let contenido: () -> Contenido

    var body: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: notch.height)
            HStack(spacing: 11) { contenido() }
                .padding(.horizontal, 26)
                .frame(maxHeight: .infinity)
        }
        .background { if let tono { LuzBorde(tono: tono, fuerza: 0.4, alto: 0.95) } }
    }
}

/// Entrada de la isla: crece desde el notch, se enfoca y aparece (con `Halo.entrada`).
private struct Enfoque: ViewModifier {
    let activo: Bool

    func body(content: Content) -> some View {
        content
            .scaleEffect(activo ? 0.88 : 1, anchor: .top)
            .blur(radius: activo ? 10 : 0)
            .opacity(activo ? 0 : 1)
    }
}

/// Ícono que entra con un salto.
private struct IconoSaltarin: View {
    let simbolo: String
    let color: Color
    @State private var salto = false

    var body: some View {
        Image(systemName: simbolo)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(color)
            .symbolEffect(.bounce, options: .nonRepeating, value: salto)
            .onAppear { salto = true }
    }
}

/// Entrada con rebote para imágenes (carátula, ícono de app).
private struct Entrada: ViewModifier {
    @State private var visible = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(visible ? 1 : 0.4)
            .rotationEffect(.degrees(visible ? 0 : -12))
            .onAppear {
                withAnimation(.spring(response: 0.45, dampingFraction: 0.55).delay(0.06)) { visible = true }
            }
    }
}

/// Dictando: punto rojo que late, cronómetro, el Prisma en miniatura y el texto en vivo.
private struct DictadoIsla: View {
    let estado: EstadoIsla
    let hud: EstadoHUD

    var body: some View {
        let escuchando = hud.fase == .escuchando
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                HStack(spacing: 6) {
                    Image(systemName: escuchando ? "circle.fill" : "waveform")
                        .font(.system(size: escuchando ? 8 : 11, weight: .bold))
                        .foregroundStyle(escuchando ? .red : .white)
                        .symbolEffect(.pulse, isActive: true)
                    TimelineView(.periodic(from: .now, by: 1)) { ctx in
                        Text(Tiempo.reloj(ctx.date.timeIntervalSince(estado.inicioActividad)))
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.8))
                    }
                }
                .frame(width: 120, alignment: .leading)
                Spacer(minLength: estado.notch.width)
                Text(escuchando ? (hud.nota == nil ? "Escuchando" : "→ _inbox") : "Transcribiendo")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.6))
                    .frame(width: 120, alignment: .trailing)
            }
            .padding(.horizontal, 22)
            .frame(height: estado.notch.height)
            TimelineView(.animation) { ctx in
                Visual(estado: hud, t: ctx.date.timeIntervalSinceReferenceDate)
                    .frame(width: 380, height: 118)
                    .scaleEffect(0.42)
                    .frame(width: 170, height: 48)
            }
            Text(hud.texto.isEmpty ? " " : hud.texto)
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.85))
                .lineLimit(1)
                .truncationMode(.head)
                .padding(.horizontal, 28)
                .padding(.bottom, 6)
        }
    }
}

/// Verde: cámara (y casi siempre micrófono). Naranja: solo micrófono.
private struct PuntoPrivacidad: View {
    let camara: Bool

    static func color(camara: Bool) -> Color {
        camara ? Color(red: 0.20, green: 0.84, blue: 0.35) : Color(red: 1.0, green: 0.58, blue: 0.0)
    }

    var body: some View {
        Circle()
            .fill(Self.color(camara: camara))
            .frame(width: 6, height: 6)
            .shadow(color: Self.color(camara: camara).opacity(0.8), radius: 3)
    }
}

/// Volumen o brillo (reemplaza el cuadro de macOS): a la izquierda la cifra en su tono, en el centro la cuña de nivel
/// (rayitas que suben de izquierda a derecha sobre una cuadrícula tenue, encendidas hasta el nivel, con la luz naciendo
/// debajo y un marcador blanco) y a la derecha a dónde va el sonido. En silencio la cuña se apaga y queda marcado tenue
/// el volumen guardado. Mientras mantienes la tecla, `Isla` reemplaza la actividad sin cambiar su id: la cuña se
/// enciende o apaga sin volver a entrar.
private struct BarraNivel: View {
    let estado: EstadoIsla
    let tipo: Niveles.Tipo
    let valor: Double
    let silencio: Bool
    var salida: SalidaAudio?

    private var simbolo: String {
        switch tipo {
        case .brillo: return valor < 0.35 ? "sun.min.fill" : "sun.max.fill"
        case .volumen: return silencio ? "speaker.slash.fill" : "speaker.wave.3.fill"
        }
    }

    private var tono: Tono { tipo == .brillo ? .brillo : .volumen }
    private static let rojoMudo = Color(red: 1.0, green: 0.46, blue: 0.44)

    var body: some View {
        if tipo == .volumen {
            switch EstiloVolumen.actual {
            case .niebla: VolumenNiebla(estado: estado, valor: valor, silencio: silencio, salida: salida)
            case .calor: VolumenCalor(estado: estado, valor: valor, silencio: silencio, salida: salida)
            case .espectro: VolumenEspectro(estado: estado, valor: valor, silencio: silencio, salida: salida)
            case .termostato: VolumenIsla(estado: estado, valor: valor, silencio: silencio, salida: salida)
            }
        } else {
            cuna
        }
    }

    private var cuna: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: estado.notch.height)
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 4) {
                        Image(systemName: simbolo, variableValue: tipo == .volumen ? max(valor, 0.01) : 1)
                            .font(.system(size: 8.5, weight: .semibold))
                            .contentTransition(.symbolEffect(.replace))
                        Rotulo(tipo == .brillo ? "Brillo" : (silencio ? "Silencio" : "Volumen"), color: silencio ? Self.rojoMudo : tono.claro)
                    }
                    .foregroundStyle(silencio ? Self.rojoMudo : tono.claro)
                    if silencio {
                        Text("Mudo").font(.system(size: 22, weight: .light)).foregroundStyle(Halo.texto2).fixedSize()
                    } else {
                        NumeroFino(texto: "\(Int((valor * 100).rounded()))", unidad: "%", tamano: 26, peso: .light,
                                   color: tono.claro, valor: valor)
                            .shadow(color: tono.base.opacity(0.6), radius: 6)
                    }
                }
                .frame(width: 82, alignment: .leading)
                Cuna(valor: valor, tono: tono, apagada: silencio)
                    .frame(height: 34)
                Group {
                    if tipo == .volumen, let salida {
                        Label { Text(salida.nombre) } icon: { Image(systemName: salida.simbolo) }
                    } else if tipo == .brillo {
                        Label { Text("Pantalla") } icon: { Image(systemName: "display") }
                    }
                }
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(silencio ? Halo.texto3 : Halo.texto)
                .labelStyle(EtiquetaJunta())
                .lineLimit(1)
                .frame(maxWidth: 104, alignment: .trailing)
            }
            .padding(.leading, 24)
            .padding(.trailing, 24)
            .frame(maxHeight: .infinity)
        }
        .background {  // la isla toma el tono del nivel desde el borde; más fuerte cuanto más alto
            if !silencio { LuzBorde(tono: tono, fuerza: 0.1 + 0.2 * valor, alto: 0.9, centro: 0.5, ancho: 0.8) }
        }
        .animation(Halo.cambio, value: valor)
        .animation(Halo.cambio, value: silencio)
    }
}

/// Cuña de nivel: rayitas verticales finas cuya altura sube de izquierda a derecha (la forma del volumen) sobre una
/// cuadrícula tenue. Las rayitas hasta el nivel se encienden del tono base al claro y brillan; la última es blanca;
/// la luz nace debajo de lo encendido y un marcador blanco señala el nivel. Apagada (silencio), las rayitas hasta el
/// nivel guardado quedan apenas más claras.
private struct Cuna: View {
    let valor: Double
    let tono: Tono
    var apagada = false
    var cuantas = 44

    var body: some View {
        let v = max(0, min(1, valor))
        let encendidas = Int((v * Double(cuantas)).rounded())
        GeometryReader { g in
            let w = g.size.width
            let h = g.size.height - 7  // abajo queda el marcador
            let paso = w / CGFloat(cuantas)
            ZStack(alignment: .topLeading) {
                Path { p in  // cuadrícula: una vertical cada 4 rayitas, cuatro horizontales
                    for i in stride(from: 0, through: cuantas, by: 4) {
                        let x = paso * CGFloat(i)
                        p.move(to: CGPoint(x: x, y: 0)); p.addLine(to: CGPoint(x: x, y: h))
                    }
                    for k in 0...3 {
                        let y = h * CGFloat(k) / 3
                        p.move(to: CGPoint(x: 0, y: y)); p.addLine(to: CGPoint(x: w, y: y))
                    }
                }
                .stroke(.white.opacity(0.05), lineWidth: 0.5)
                Path { p in  // la forma completa de la cuña, tenue
                    p.move(to: CGPoint(x: 0, y: h)); p.addLine(to: CGPoint(x: w, y: h * 0.06)); p.addLine(to: CGPoint(x: w, y: h))
                }
                .stroke(.white.opacity(0.12), lineWidth: 0.6)
                if !apagada && v > 0 {  // la luz nace debajo de lo encendido
                    Ellipse().fill(tono.base)
                        .frame(width: max(24, w * v * 1.15), height: h * 0.9)
                        .position(x: w * v * 0.55, y: h + 3)
                        .blur(radius: 11)
                        .opacity(0.3 + 0.35 * v)
                }
                ForEach(0..<cuantas, id: \.self) { i in
                    let t = Double(i) / Double(cuantas - 1)
                    let alto = max(2.5, h * CGFloat(0.1 + 0.84 * t))
                    let prendida = i < encendidas && !apagada
                    let punta = prendida && i == encendidas - 1
                    let c = tono.base.mix(with: tono.claro, by: t)
                    Capsule()
                        .fill(prendida ? (punta ? Color.white : c) : Color.white.opacity(apagada && i < encendidas ? 0.3 : 0.11))
                        .frame(width: 1.3, height: alto)
                        .shadow(color: prendida ? c.opacity(0.85) : .clear, radius: punta ? 3.5 : 1.8)
                        .position(x: paso * (CGFloat(i) + 0.5), y: h - alto / 2)
                }
                if encendidas > 0 {
                    Triangulo()
                        .fill(apagada ? Color.white.opacity(0.4) : .white)
                        .frame(width: 6, height: 4.5)
                        .shadow(color: apagada ? .clear : tono.claro, radius: 3)
                        .position(x: paso * (CGFloat(encendidas) - 0.5), y: h + 4.5)
                }
            }
        }
        .animation(Halo.cambio, value: encendidas)
    }
}

/// Volumen como un termostato: un arco de tubo con volumen que va de azul (bajo) a naranja y rojo (alto), encendido
/// hasta el nivel y tenue después, con una perilla blanca que brilla en el nivel y la cifra grande con relieve en el
/// centro. A la izquierda, un botón de vidrio con el parlante (rojo en silencio, como el de encendido); a la derecha,
/// a dónde va el sonido. En silencio el arco se apaga y la perilla queda gris en el volumen guardado.
private struct VolumenIsla: View {
    let estado: EstadoIsla
    let valor: Double
    let silencio: Bool
    var salida: SalidaAudio?

    private static let rojo = Color(red: 1.0, green: 0.33, blue: 0.27)

    var body: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: estado.notch.height)
            HStack(spacing: 0) {
                BotonVidrio(simbolo: silencio ? "speaker.slash.fill" : "speaker.wave.3.fill", valor: valor,
                            tinte: silencio ? Self.rojo : nil)
                Spacer(minLength: 8)
                ZStack(alignment: .bottom) {
                    ArcoTubo(valor: valor, apagada: silencio)
                        .frame(width: 140, height: 58)
                    Text("\(Int((valor * 100).rounded()))")
                        .font(.system(size: 21, weight: .semibold, design: .rounded)).monospacedDigit()
                        .foregroundStyle(LinearGradient(colors: silencio ? [Color(white: 0.55), Color(white: 0.35)]
                                                                 : [.white, Color(white: 0.7)],
                                                        startPoint: .top, endPoint: .bottom))
                        .shadow(color: .black.opacity(0.7), radius: 1.5, y: 1.5)
                        .contentTransition(.numericText(value: valor))
                        .offset(y: 1)
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 2) {
                    Rotulo(silencio ? "Silencio" : "Volumen", color: silencio ? Self.rojo : Halo.texto3)
                    if let salida {
                        Label { Text(salida.nombre) } icon: { Image(systemName: salida.simbolo) }
                            .font(.system(size: 11.5, weight: .semibold)).foregroundStyle(silencio ? Halo.texto3 : Halo.texto)
                            .labelStyle(EtiquetaJunta()).lineLimit(1)
                    }
                }
                .frame(width: 112, alignment: .trailing)
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 5)  // el arco y la cifra no tocan el borde; la perilla nunca queda bajo el notch
            .frame(maxHeight: .infinity, alignment: .bottom)
        }
        .animation(Halo.cambio, value: valor)
        .animation(Halo.cambio, value: silencio)
    }
}

/// Cómo se ve el volumen en la isla. Se elige con `defaults write app.dictado estiloVolumen niebla` (termostato,
/// niebla, calor o espectro); en los renders, con la variable DICTADO_VOLUMEN.
enum EstiloVolumen: String {
    case termostato, niebla, calor, espectro

    static var actual: EstiloVolumen {
        let valor = ProcessInfo.processInfo.environment["DICTADO_VOLUMEN"]
            ?? UserDefaults(suiteName: "app.dictado")?.string(forKey: "estiloVolumen")
        return valor.flatMap(EstiloVolumen.init(rawValue:)) ?? .termostato
    }
}

/// Alturas fijas de una onda de sonido (siempre las mismas: nada se anima solo), entre 0,25 y 1.
private let ondaVolumen: [Double] = (0..<48).map { i in
    let x = Double(i)
    return 0.25 + 0.75 * abs(sin(x * 0.61) * 0.55 + sin(x * 1.37 + 1.1) * 0.3 + sin(x * 0.23 + 0.4) * 0.15)
}

/// Volumen como niebla de luz: hasta el nivel, la onda del sonido es una masa difuminada de azul a violeta y rosa;
/// una línea punteada con un punto marca el nivel y encima va la cifra; después, rayitas finas y tenues con la misma
/// onda (lo que falta). A la izquierda, qué es y a dónde va el sonido.
private struct VolumenNiebla: View {
    let estado: EstadoIsla
    let valor: Double
    let silencio: Bool
    var salida: SalidaAudio?

    private static let colores = [Color(red: 0.35, green: 0.62, blue: 1.0), Color(red: 0.62, green: 0.48, blue: 1.0),
                                  Color(red: 1.0, green: 0.45, blue: 0.62)]
    private static let marca = Color(red: 1.0, green: 0.62, blue: 0.45)

    var body: some View {
        let v = max(0, min(1, valor))
        VStack(spacing: 0) {
            Color.clear.frame(height: estado.notch.height)
            HStack(spacing: 18) {
                VStack(alignment: .leading, spacing: 2) {
                    Rotulo(silencio ? "Silencio" : "Volumen", color: silencio ? Color(red: 1, green: 0.46, blue: 0.44) : Halo.texto3)
                    if let salida {
                        Label { Text(salida.nombre) } icon: { Image(systemName: salida.simbolo) }
                            .font(.system(size: 11.5, weight: .semibold)).foregroundStyle(silencio ? Halo.texto3 : Halo.texto)
                            .labelStyle(EtiquetaJunta()).lineLimit(1)
                    }
                }
                .frame(width: 104, alignment: .leading)
                GeometryReader { g in
                    let w = g.size.width, h = g.size.height
                    let base = h - 2, techo: CGFloat = 20  // arriba queda la cifra
                    let n = ondaVolumen.count
                    let paso = w / CGFloat(n - 1)
                    let x = w * v
                    ZStack(alignment: .topLeading) {
                        if !silencio && v > 0 {
                            Path { p in  // la masa de la onda hasta el nivel: colinas suaves (una cada 4 muestras)
                                let puntos = stride(from: 0, to: n, by: 4).map { i in
                                    CGPoint(x: CGFloat(i) * paso, y: base - (base - techo) * CGFloat(0.3 + 0.7 * ondaVolumen[i]))
                                } + [CGPoint(x: w, y: base - (base - techo) * 0.5)]
                                p.move(to: CGPoint(x: 0, y: base))
                                p.addLine(to: puntos[0])
                                for k in 1..<puntos.count {
                                    let a = puntos[k - 1], b = puntos[k]
                                    let medio = CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
                                    p.addQuadCurve(to: medio, control: a)
                                    if k == puntos.count - 1 { p.addQuadCurve(to: b, control: medio) }
                                }
                                p.addLine(to: CGPoint(x: w, y: base))
                                p.closeSubpath()
                            }
                            .fill(LinearGradient(colors: Self.colores, startPoint: .leading, endPoint: .trailing))
                            .mask(alignment: .leading) { Rectangle().frame(width: x) }
                            .mask(LinearGradient(stops: [.init(color: .black, location: 0), .init(color: .black, location: 0.55),
                                                         .init(color: .black.opacity(0.25), location: 1)], startPoint: .top, endPoint: .bottom))
                            .blur(radius: 5)
                        }
                        ForEach(0..<n, id: \.self) { i in  // lo que falta: rayitas finas
                            let xi = CGFloat(i) * paso
                            if xi > x + 3 || silencio {
                                let alto = (base - techo) * CGFloat(ondaVolumen[i])
                                Rectangle().fill((silencio ? Color.white : Self.colores[2]).opacity(silencio ? 0.18 : 0.45))
                                    .frame(width: 0.8, height: alto)
                                    .position(x: xi, y: base - alto / 2)
                            }
                        }
                        Path { p in p.move(to: CGPoint(x: x, y: techo - 4)); p.addLine(to: CGPoint(x: x, y: base)) }
                            .stroke(silencio ? Color.white.opacity(0.35) : Self.marca, style: StrokeStyle(lineWidth: 1, dash: [1.5, 2]))
                        Circle().fill(silencio ? Color.white.opacity(0.4) : Self.marca).frame(width: 5, height: 5)
                            .shadow(color: silencio ? .clear : Self.marca, radius: 3)
                            .position(x: x, y: techo - 4)
                        Text(silencio ? "Mudo" : "\(Int((v * 100).rounded()))%")
                            .font(.system(size: 14, weight: .light)).monospacedDigit()
                            .foregroundStyle(silencio ? Halo.texto3 : Halo.texto)
                            .contentTransition(.numericText(value: v))
                            .fixedSize()
                            .position(x: min(max(x, 18), w - 18), y: 6)
                    }
                }
                .frame(height: 50)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 4)
            .frame(maxHeight: .infinity, alignment: .bottom)
        }
        .animation(Halo.cambio, value: valor)
        .animation(Halo.cambio, value: silencio)
    }
}

/// Volumen como calor y frío: una línea fina con topes en los extremos; desde la izquierda hasta el nivel, un brillo
/// cálido (naranja a amarillo, con el centro blanco en el nivel) y después un brillo frío azul que se apaga. Arriba,
/// "VOLUMEN 62" con la cifra en amarillo y el parlante; abajo, los extremos de la escala.
private struct VolumenCalor: View {
    let estado: EstadoIsla
    let valor: Double
    let silencio: Bool
    var salida: SalidaAudio?

    private static let amarillo = Color(red: 1.0, green: 0.82, blue: 0.25)
    private static let naranja = Color(red: 1.0, green: 0.45, blue: 0.12)
    private static let azul = Color(red: 0.35, green: 0.72, blue: 1.0)
    private static let rojoMudo = Color(red: 1.0, green: 0.46, blue: 0.44)

    var body: some View {
        let v = max(0, min(1, valor))
        VStack(spacing: 0) {
            Color.clear.frame(height: estado.notch.height)
            VStack(spacing: 2) {
                HStack(alignment: .firstTextBaseline) {
                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        Text(silencio ? "SILENCIO" : "VOLUMEN").font(.system(size: 13, weight: .heavy))
                            .foregroundStyle(silencio ? Self.rojoMudo : .white)
                        if !silencio {
                            Text("\(Int((v * 100).rounded()))").font(.system(size: 13, weight: .heavy)).monospacedDigit()
                                .foregroundStyle(Self.amarillo)
                                .contentTransition(.numericText(value: v))
                        }
                    }
                    Spacer()
                    if let salida {
                        Text(salida.nombre).font(.system(size: 10.5, weight: .medium)).foregroundStyle(Halo.texto3).lineLimit(1)
                    }
                    Image(systemName: silencio ? "speaker.slash.fill" : "speaker.wave.3.fill", variableValue: max(v, 0.01))
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(silencio ? Self.rojoMudo : Self.amarillo)
                }
                GeometryReader { g in
                    let w = g.size.width, medio = g.size.height / 2
                    let x = w * v
                    ZStack(alignment: .topLeading) {
                        if !silencio {
                            Ellipse()  // frío: lo que falta
                                .fill(LinearGradient(colors: [Self.azul, Self.azul.opacity(0.0)], startPoint: .leading, endPoint: .trailing))
                                .frame(width: max(30, (w - x) * 1.1), height: 18)
                                .position(x: x + (w - x) / 2, y: medio)
                                .blur(radius: 7).opacity(0.85)
                            Ellipse()  // calor: hasta el nivel
                                .fill(LinearGradient(colors: [Self.naranja.opacity(0.0), Self.naranja, Self.amarillo],
                                                     startPoint: .leading, endPoint: .trailing))
                                .frame(width: max(30, x * 1.1), height: 20)
                                .position(x: x / 2, y: medio)
                                .blur(radius: 6)
                            Ellipse().fill(.white)  // el centro blanco en el nivel
                                .frame(width: 22, height: 12)
                                .position(x: x, y: medio)
                                .blur(radius: 4.5)
                        }
                        Path { p in  // la línea con sus topes
                            p.move(to: CGPoint(x: 0, y: medio)); p.addLine(to: CGPoint(x: w, y: medio))
                            p.move(to: CGPoint(x: 0, y: medio - 4)); p.addLine(to: CGPoint(x: 0, y: medio + 4))
                            p.move(to: CGPoint(x: w, y: medio - 4)); p.addLine(to: CGPoint(x: w, y: medio + 4))
                        }
                        .stroke(.white.opacity(silencio ? 0.25 : 0.55), lineWidth: 0.8)
                        if silencio {
                            Capsule().fill(.white.opacity(0.35)).frame(width: 1.2, height: 9).position(x: x, y: medio)
                        }
                    }
                }
                .frame(height: 18)
                HStack {
                    Text("0"); Spacer(); Text("100")
                }
                .font(.system(size: 10.5, weight: .semibold)).foregroundStyle(Halo.texto3)
            }
            .padding(.horizontal, 26)
            .padding(.bottom, 5)
            .frame(maxHeight: .infinity, alignment: .bottom)
        }
        .animation(Halo.cambio, value: valor)
        .animation(Halo.cambio, value: silencio)
    }
}

/// Volumen como espectro (como un reproductor con barras): arriba "Volumen" y a dónde va el sonido, la cifra y el
/// parlante en un círculo; una línea fina con su perilla marca el nivel; abajo, rayitas blancas a todo lo ancho,
/// sumergidas en una luz azul y violeta que sube desde el borde, encendidas hasta el nivel y tenues después.
private struct VolumenEspectro: View {
    let estado: EstadoIsla
    let valor: Double
    let silencio: Bool
    var salida: SalidaAudio?

    private static let azul = Color(red: 0.25, green: 0.4, blue: 1.0)
    private static let violeta = Color(red: 0.55, green: 0.45, blue: 1.0)
    private static let rojoMudo = Color(red: 1.0, green: 0.46, blue: 0.44)

    var body: some View {
        let v = max(0, min(1, valor))
        VStack(spacing: 0) {
            Color.clear.frame(height: estado.notch.height)
            VStack(spacing: 5) {
                HStack(alignment: .center, spacing: 10) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(silencio ? "Silencio" : "Volumen").font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(silencio ? Self.rojoMudo : Halo.texto)
                        if let salida { Text(salida.nombre).font(.system(size: 10.5)).foregroundStyle(Halo.texto3).lineLimit(1) }
                    }
                    Spacer()
                    Text(silencio ? "—" : "\(Int((v * 100).rounded()))")
                        .font(.system(size: 20, weight: .light)).monospacedDigit().foregroundStyle(Halo.texto)
                        .contentTransition(.numericText(value: v))
                    Image(systemName: silencio ? "speaker.slash.fill" : "speaker.wave.3.fill", variableValue: max(v, 0.01))
                        .font(.system(size: 9.5, weight: .bold)).foregroundStyle(silencio ? Self.rojoMudo : .white.opacity(0.85))
                        .frame(width: 22, height: 22)
                        .background(Circle().fill(.white.opacity(0.14)))
                }
                .padding(.horizontal, 24)
                GeometryReader { g in  // la línea del nivel con su perilla
                    let w = g.size.width
                    ZStack(alignment: .leading) {
                        Capsule().fill(.white.opacity(0.2)).frame(height: 1.2)
                        Capsule().fill(.white.opacity(silencio ? 0.3 : 0.9)).frame(width: w * v, height: 1.2)
                        Circle().fill(.white.opacity(silencio ? 0.4 : 1)).frame(width: 6, height: 6)
                            .shadow(color: .white.opacity(silencio ? 0 : 0.8), radius: 3)
                            .offset(x: w * v - 3)
                    }
                    .frame(maxHeight: .infinity)
                }
                .frame(height: 6)
                .padding(.horizontal, 24)
                GeometryReader { g in  // el espectro a todo lo ancho, con la luz desde abajo
                    let w = g.size.width, h = g.size.height
                    let n = 72
                    let paso = w / CGFloat(n)
                    let x = w * v
                    ZStack(alignment: .bottomLeading) {
                        if !silencio && v > 0 {
                            Ellipse().fill(Self.azul)  // la luz que se derrama más allá de las barras
                                .frame(width: x * 1.1, height: h * 2.2)
                                .offset(x: -x * 0.03, y: h * 0.45)
                                .blur(radius: 12)
                            Rectangle()  // la luz que sube desde el borde e inunda la base de las barras
                                .fill(LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: Self.azul.opacity(0.9), location: 0.3),
                                                             .init(color: Self.violeta, location: 0.65), .init(color: .white, location: 1)],
                                                     startPoint: .top, endPoint: .bottom))
                                .frame(width: x, height: h + 20)
                                .blur(radius: 5)
                        }
                        ForEach(0..<n, id: \.self) { i in
                            let xi = paso * (CGFloat(i) + 0.5)
                            let alto = h * CGFloat(0.35 + 0.65 * ondaVolumen[i % ondaVolumen.count])
                            let prendida = !silencio && xi <= x
                            Rectangle()
                                .fill(LinearGradient(colors: prendida ? [.white.opacity(0.95), .white.opacity(0.35)] : [.white.opacity(0.14), .white.opacity(0.05)],
                                                     startPoint: .top, endPoint: .bottom))
                                .frame(width: 1.6, height: alto)
                                .position(x: xi, y: h - alto / 2)
                        }
                    }
                }
                .frame(height: 24)
                .padding(.horizontal, FormaIsla.hombro + 6)
            }
            .frame(maxHeight: .infinity, alignment: .bottom)
        }
        .animation(Halo.cambio, value: valor)
        .animation(Halo.cambio, value: silencio)
    }
}

/// Botón redondo de vidrio oscuro con relieve (como los de un termostato); con tinte, el vidrio brilla de ese color.
private struct BotonVidrio: View {
    let simbolo: String
    var valor: Double = 1
    var tinte: Color?

    var body: some View {
        ZStack {
            Circle().fill(RadialGradient(colors: [(tinte ?? Color(white: 0.32)).opacity(tinte == nil ? 0.9 : 0.75),
                                                  (tinte ?? Color(white: 0.12)).opacity(tinte == nil ? 1 : 0.35)],
                                         center: UnitPoint(x: 0.5, y: 0.2), startRadius: 0, endRadius: 22))
            Circle().strokeBorder(LinearGradient(colors: [.white.opacity(0.45), .white.opacity(0.05)], startPoint: .top, endPoint: .bottom),
                                  lineWidth: 0.8)
            Image(systemName: simbolo, variableValue: max(valor, 0.01))
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(.white)
                .contentTransition(.symbolEffect(.replace))
        }
        .frame(width: 32, height: 32)
        .shadow(color: .black.opacity(0.6), radius: 3, y: 2)
        .shadow(color: (tinte ?? .clear).opacity(0.55), radius: 8)
    }
}

/// El arco del termostato: medio círculo por arriba, con un tubo de volumen (sombra debajo, brillo arriba) que se
/// enciende hasta el nivel con el degradado azul → violeta → naranja → rojo; después del nivel queda tenue; los
/// extremos se desvanecen; la perilla es una esfera blanca que brilla.
private struct ArcoTubo: View {
    let valor: Double
    var apagada = false

    private static let colores = [Color(red: 0.3, green: 0.6, blue: 1.0), Color(red: 0.55, green: 0.78, blue: 1.0),
                                  Color(red: 0.7, green: 0.55, blue: 1.0), Color(red: 1.0, green: 0.6, blue: 0.3),
                                  Color(red: 1.0, green: 0.3, blue: 0.25)]

    var body: some View {
        let v = max(0, min(1, valor))
        GeometryReader { g in
            let grosor: CGFloat = 8.5
            let radio: CGFloat = 40  // el resto del cuadro es aire para que el brillo se desvanezca sin bordes
            let centro = CGPoint(x: g.size.width / 2, y: g.size.height - 1)
            let arco = { (hasta: Double) -> Path in
                Path { p in
                    p.addArc(center: centro, radius: radio, startAngle: .degrees(180), endAngle: .degrees(180 + 180 * hasta),
                             clockwise: false)
                }
            }
            let degradado = LinearGradient(colors: apagada ? [Color(white: 0.4), Color(white: 0.3)] : Self.colores,
                                           startPoint: .leading, endPoint: .trailing)
            let angulo = (180 + 180 * v) * .pi / 180
            let perilla = CGPoint(x: centro.x + radio * cos(angulo), y: centro.y + radio * sin(angulo))
            ZStack {
                // hendidura: el tubo va encajado (sombra arriba, filo de luz abajo)
                arco(1).stroke(Color.black.opacity(0.8), style: StrokeStyle(lineWidth: grosor + 3, lineCap: .round))
                    .blur(radius: 1.5).offset(y: -0.5)
                arco(1).stroke(Color.white.opacity(0.07), style: StrokeStyle(lineWidth: grosor + 2, lineCap: .round)).offset(y: 0.8)
                // el tubo completo, tenue
                arco(1).stroke(degradado, style: StrokeStyle(lineWidth: grosor, lineCap: .round)).opacity(apagada ? 0.25 : 0.22)
                if !apagada && v > 0.001 {
                    // resplandor del tramo encendido
                    arco(v).stroke(degradado, style: StrokeStyle(lineWidth: grosor + 6, lineCap: .round)).blur(radius: 7).opacity(0.75)
                    // el tubo encendido
                    arco(v).stroke(degradado, style: StrokeStyle(lineWidth: grosor, lineCap: .round))
                    // sombra interior abajo y brillo arriba: volumen de tubo
                    arco(v).stroke(Color.black.opacity(0.35), style: StrokeStyle(lineWidth: grosor * 0.4, lineCap: .round))
                        .blur(radius: 1.2).offset(y: grosor * 0.22)
                    arco(v).stroke(Color.white.opacity(0.55), style: StrokeStyle(lineWidth: grosor * 0.28, lineCap: .round))
                        .blur(radius: 0.8).offset(y: -grosor * 0.2)
                }
                // la perilla: esfera blanca que brilla
                Circle()
                    .fill(RadialGradient(colors: [.white, Color(white: apagada ? 0.55 : 0.88)], center: UnitPoint(x: 0.4, y: 0.35),
                                         startRadius: 0, endRadius: 7))
                    .frame(width: 12, height: 12)
                    .shadow(color: apagada ? .clear : .white.opacity(0.95), radius: 4)
                    .shadow(color: apagada ? .black.opacity(0.5) : Color(red: 1, green: 0.9, blue: 0.75).opacity(0.7), radius: 9)
                    .position(perilla)
            }
            // los extremos se desvanecen hacia la base, como en el termostato
            .mask(LinearGradient(stops: [.init(color: .black, location: 0), .init(color: .black, location: 0.7),
                                         .init(color: .black.opacity(0.12), location: 1)], startPoint: .top, endPoint: .bottom))
        }
    }
}

/// Triángulo con la punta hacia arriba (el marcador de la cuña).
private struct Triangulo: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.midX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX, y: r.maxY))
        p.closeSubpath()
        return p
    }
}

/// Ícono y texto juntos, con el ícono pequeño (para "AirPods Pro", "Pantalla").
private struct EtiquetaJunta: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 5) {
            configuration.icon.font(.system(size: 10.5, weight: .medium)).opacity(0.8)
            configuration.title
        }
    }
}

/// Cuatro barras que bailan con la música (solo mientras el aviso está a la vista).
private struct Ecualizador: View {
    let color: Color
    let activo: Bool

    private func alto(_ i: Int, _ t: Double) -> CGFloat {
        guard activo else { return 4 }
        let n = Double(i)
        let onda: Double = abs(sin(t * (2.6 + n * 0.7) + n * 1.9))
        return CGFloat(5 + 13 * onda)
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !activo)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            HStack(spacing: 2.5) {
                ForEach(0..<4, id: \.self) { i in
                    Capsule().fill(color).frame(width: 3, height: alto(i, t)).shadow(color: color.opacity(0.8), radius: 2.5)
                }
            }
            .frame(width: 22, height: 20)
        }
    }
}

/// Alas a los lados del notch. Izquierda: carátula, evento, Claude o la app que escucha. Derecha: Claude
/// trabajando o esperándote, la onda de la música o los minutos para el evento; y el punto verde/naranja de
/// cámara o micrófono en el borde (como el iPhone).
private struct Compacta: View {
    let estado: EstadoIsla
    let musica: Musica
    let agenda: Agenda
    let privacidad: Privacidad
    let claude: SesionesClaude

    var body: some View {
        let punto = privacidad.activo
        let llamada = privacidad.desde != nil
        HStack(spacing: 0) {
            izquierda
                .frame(width: 46)
                .padding(.leading, punto ? 14 : 0)
            Spacer(minLength: estado.notch.width)
            HStack(spacing: 6) {
                if llamada, let desde = privacidad.desde {
                    Cronometro(desde: desde)  // en llamada manda el cronómetro, como en el iPhone
                } else {
                    if claude.hayActividad { IndicadorClaude(claude: claude) }
                    derecha
                }
            }
            .frame(width: 46)
            if punto {
                PuntoPrivacidad(camara: privacidad.camara).frame(width: 14, alignment: .leading)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .padding(.horizontal, FormaIsla.hombro)
        .frame(height: estado.notch.height)
    }

    @ViewBuilder private var izquierda: some View {
        if privacidad.activo, let icono = privacidad.icono {  // la llamada manda sobre la música
            Image(nsImage: icono).resizable().frame(width: 18, height: 18).modifier(Entrada())
        } else if musica.hayPista {
            Caratula(imagen: musica.caratula, lado: 20, radio: 5)
        } else if let evento = agenda.inminente {
            Circle().fill(evento.color).frame(width: 8, height: 8)
        } else if privacidad.activo {
            if let icono = privacidad.icono {
                Image(nsImage: icono).resizable().frame(width: 18, height: 18).modifier(Entrada())
            } else {
                Image(systemName: privacidad.camara ? "video.fill" : "mic.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(PuntoPrivacidad.color(camara: privacidad.camara))
            }
        } else if claude.hayActividad {
            EstrellaClaude().fill(Color.claude).frame(width: 15, height: 15)
        }
    }

    @ViewBuilder private var derecha: some View {
        if musica.hayPista {
            Image(systemName: "waveform")  // fija: en reposo la isla no anima nada (cero CPU)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(musica.acento)
                .opacity(musica.sonando ? 1 : 0.4)
        } else if let evento = agenda.inminente, !claude.hayActividad {
            Text(Tiempo.faltan(evento.inicio))
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(evento.color)
                .fixedSize()
        }
    }
}

/// Tiempo en llamada (micrófono o cámara en uso), verde como en el iPhone. Se redibuja 1 vez por segundo
/// solo mientras dura la llamada.
private struct Cronometro: View {
    let desde: Date

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { ctx in
            Text(Tiempo.reloj(ctx.date.timeIntervalSince(desde)))
                .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(PuntoPrivacidad.color(camara: true))
                .fixedSize()
        }
    }
}

/// Aviso de Salud del Mac (disco casi lleno, memoria al límite, calor, una app al máximo): el ícono dentro de un
/// dial encendido en rojo o ámbar, con su resplandor.
private struct SaludIsla: View {
    let estado: EstadoIsla
    let titulo: String
    let detalle: String
    let grave: Bool
    let ver: () -> Void

    var body: some View {
        let tono: Tono = grave ? .rojo : .ambar
        Fila(notch: estado.notch, tono: tono) {
            Dial(lado: 38, valor: 1, colores: tono.gradiente, marcas: 28, arco: 360, anillo: 3.5, brillo: 0.6, destello: false) {
                IconoSaltarin(simbolo: grave ? "exclamationmark.triangle.fill" : "gauge.with.dots.needle.67percent", color: tono.claro)
            }
            VStack(alignment: .leading, spacing: 1) {
                Rotulo("Salud del Mac", color: tono.claro)
                Text(titulo).font(Halo.titulo).foregroundStyle(Halo.texto).lineLimit(1)
                Text(detalle).font(Halo.detalle).foregroundStyle(Halo.texto2).lineLimit(1)
            }
            Spacer(minLength: 6)
            BotonHalo(titulo: "Ver", accion: ver)
        }
    }
}

/// Aviso de un agente de fuera del Mac: una tarea falló o el servidor no responde. El ícono va dentro de un dial
/// encendido en ámbar o rojo. "Ver" abre su detalle en la pestaña Agentes.
private struct AgenteIsla: View {
    let estado: EstadoIsla
    let nombre: String
    let alerta: String
    let caido: Bool
    let ver: () -> Void

    var body: some View {
        let tono: Tono = caido ? .rojo : .ambar
        // "informe-diario falló: sin conexión" → título "informe-diario falló", detalle "sin conexión".
        let partes = alerta.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
        Fila(notch: estado.notch, tono: tono) {
            Dial(lado: 38, valor: 1, colores: tono.gradiente, marcas: 28, arco: 360, anillo: 3.5, brillo: 0.6, destello: false) {
                IconoSaltarin(simbolo: "server.rack", color: tono.claro)
            }
            .modifier(Entrada())
            VStack(alignment: .leading, spacing: 1) {
                Rotulo((caido ? "Sin respuesta · " : "Alerta · ") + nombre, color: tono.claro)
                Text(partes.first ?? alerta).font(Halo.titulo).foregroundStyle(Halo.texto).lineLimit(1)
                if partes.count > 1 {
                    Text(partes[1]).font(Halo.detalle).foregroundStyle(Halo.texto2).lineLimit(1)
                }
            }
            Spacer(minLength: 6)
            BotonHalo(titulo: "Ver", accion: ver)
        }
    }
}

/// Botón en píldora de los avisos ("Ver", "Responder").
private struct BotonAviso: View {
    let titulo: String
    var fondo: Color = .white
    var texto: Color = .black
    let accion: () -> Void

    var body: some View {
        Button(action: accion) {
            Text(titulo)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(texto)
                .padding(.horizontal, 14)
                .frame(height: 28)
                .background(Capsule().fill(fondo))
                .contentShape(Capsule())
                .fixedSize()
        }
        .buttonStyle(.plain)
    }
}

/// Claude en el ala, sin animaciones continuas (cero CPU en reposo): estrella naranja con cuántas sesiones
/// trabajan; si alguna te espera, punto naranja con brillo.
private struct IndicadorClaude: View {
    let claude: SesionesClaude

    var body: some View {
        let esperan = claude.esperando.count
        HStack(spacing: 3) {
            if esperan > 0 {
                Circle().fill(Color.claude).frame(width: 7, height: 7).shadow(color: Color.claude, radius: 4)
            } else {
                EstrellaClaude().fill(Color.claude).frame(width: 12, height: 12)
            }
            let n = esperan > 0 ? esperan : claude.trabajando
            if n > 1 {
                Text("\(n)").font(.system(size: 10, weight: .bold, design: .rounded)).foregroundStyle(Color.claude)
            }
        }
        .transition(.scale.combined(with: .opacity))
    }
}

/// Estrella de Claude (doce rayos de largo alterno).
struct EstrellaClaude: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        let radio = min(r.width, r.height) / 2
        let ancho = radio * 0.2
        for i in 0..<12 {
            let largo = radio * (i.isMultiple(of: 2) ? 1.0 : 0.74)
            let rayo = CGRect(x: -ancho / 2, y: radio * 0.1, width: ancho, height: largo - radio * 0.1)
            let giro = CGAffineTransform(translationX: r.midX, y: r.midY).rotated(by: Double(i) / 12 * 2 * .pi)
            p.addPath(Path(roundedRect: rayo, cornerRadius: ancho / 2).applying(giro))
        }
        return p
    }
}

extension Color {
    static let claude = Color(red: 0.85, green: 0.47, blue: 0.34)
}

/// Una sesión de Claude te necesita (qué permiso o qué pregunta) o terminó (con qué frase). El botón abre
/// justo esa sesión.
private struct ClaudeIsla: View {
    let estado: EstadoIsla
    let sesion: SesionesClaude.Sesion
    let necesita: Bool
    let duracion: TimeInterval
    let abrir: () -> Void
    @State private var giro = false

    var body: some View {
        let detalle = necesita ? sesion.actividad : sesion.resumen
        Fila(notch: estado.notch, tono: necesita ? .claude : .verde) {
            ZStack(alignment: .bottomTrailing) {
                EstrellaClaude().fill(Tono.claude.base).frame(width: 26, height: 26)
                    .rotationEffect(.degrees(giro ? 45 : 0))
                    .background { Resplandor(colores: Tono.claude.gradiente, difuso: 8).frame(width: 54, height: 54).opacity(0.5) }
                Image(systemName: necesita ? "exclamationmark.circle.fill" : "checkmark.circle.fill")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white, necesita ? Tono.claude.base : Tono.verde.base)
                    .background(Circle().fill(.black).padding(-1.5))
                    .offset(x: 4, y: 4)
            }
            .frame(width: 32, height: 32)
            .modifier(Entrada())
            .onAppear { withAnimation(.spring(response: 1.1, dampingFraction: 0.45)) { giro = true } }
            VStack(alignment: .leading, spacing: 1) {
                Rotulo(necesita ? sesion.espera : "Terminó · \(Tiempo.reloj(duracion))",
                       color: necesita ? Tono.claude.claro : Tono.verde.claro)
                Text(sesion.nombre).font(Halo.titulo).foregroundStyle(Halo.texto).lineLimit(1)
                if !detalle.isEmpty {
                    Text(detalle).font(Halo.detalle).foregroundStyle(Halo.texto2).lineLimit(1)
                }
            }
            Spacer(minLength: 6)
            BotonHalo(titulo: necesita ? "Responder" : "Ver", tono: necesita ? .claude : nil, accion: abrir)
        }
    }
}

/// Reunión en 5 minutos: cuenta regresiva en números de puntos y el botón verde para unirse dentro de un anillo de
/// marcas que se va apagando hasta la hora (se redibuja 1 vez por segundo solo mientras el aviso está a la vista).
private struct EventoIsla: View {
    let estado: EstadoIsla
    let titulo: String
    let inicio: Date
    let color: Color
    let enlace: URL?
    let unirse: (URL) -> Void

    var body: some View {
        Fila(notch: estado.notch, tono: Tono.de(color)) {
            VStack(alignment: .leading, spacing: 2) {
                Rotulo(enlace == nil ? "Reunión" : "Videollamada", color: Tono.de(color).claro)
                Text(titulo).font(Halo.titulo).foregroundStyle(Halo.texto).lineLimit(1)
            }
            .layoutPriority(1)
            Spacer(minLength: 6)
            TimelineView(.periodic(from: .now, by: 1)) { ctx in
                let falta = inicio.timeIntervalSince(ctx.date)
                HStack(spacing: 14) {
                    if falta > 0 {
                        NumeroPuntos(texto: Tiempo.cuentaRegresiva(hasta: inicio, desde: ctx.date), color: Tono.de(color).claro)
                    } else {
                        Text("Ahora").font(.system(size: 24, weight: .thin)).foregroundStyle(color)
                    }
                    if let enlace {
                        ZStack {
                            Resplandor(colores: Tono.verde.gradiente, difuso: 8).frame(width: 66, height: 66).opacity(0.55)
                            Marcas(cuenta: 36, arco: 360, desde: max(0, min(1, falta / 300)), hasta: 1, largo: 3.5)
                                .stroke(.white.opacity(0.16), style: StrokeStyle(lineWidth: 1, lineCap: .round))
                            Marcas(cuenta: 36, arco: 360, desde: 0, hasta: max(0, min(1, falta / 300)), largo: 3.5)
                                .stroke(Tono.verde.claro, style: StrokeStyle(lineWidth: 1.3, lineCap: .round))
                                .shadow(color: Tono.verde.base, radius: 2)
                            BotonUnirse(redondo: true) { unirse(enlace) }
                        }
                        .frame(width: 44, height: 44)
                        .modifier(Entrada())
                    }
                }
            }
        }
    }
}

/// Cargador conectado: rayo a la izquierda; a la derecha porcentaje y una pila que se llena.
private struct CargaIsla: View {
    let estado: EstadoIsla
    let porcentaje: Int
    @State private var lleno = 0.0

    var body: some View {
        HStack(spacing: 0) {
            IconoSaltarin(simbolo: "bolt.fill", color: Tono.verde.claro).shadow(color: Tono.verde.base, radius: 5).frame(width: 70)
            Spacer(minLength: estado.notch.width)
            HStack(spacing: 6) {
                Text("\(porcentaje) %").font(.system(size: 12, weight: .semibold)).monospacedDigit().foregroundStyle(Tono.verde.claro)
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3.5).strokeBorder(.white.opacity(0.35), lineWidth: 1)
                    RoundedRectangle(cornerRadius: 2).fill(Tono.verde.base).frame(width: 19 * lleno).padding(2)
                        .shadow(color: Tono.verde.base, radius: 3)
                }
                .frame(width: 25, height: 12)
                .overlay(alignment: .trailing) { Capsule().fill(.white.opacity(0.35)).frame(width: 1.5, height: 4).offset(x: 2.5) }
            }
            .frame(width: 70)
        }
        .padding(.horizontal, FormaIsla.hombro)
        .frame(height: estado.notch.height)
        .onAppear { withAnimation(.easeOut(duration: 0.9).delay(0.15)) { lleno = Double(porcentaje) / 100 } }
    }
}

/// Unirse a la videollamada: círculo verde (como contestar una llamada) o píldora con el texto "Unirse".
private struct BotonUnirse: View {
    var redondo = false
    var conTexto = false
    let accion: () -> Void

    var body: some View {
        Button(action: accion) {
            Group {
                if conTexto {
                    Label("Unirse", systemImage: "video.fill")
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 14)
                        .frame(height: 30)
                        .background(Capsule().fill(LinearGradient(colors: Tono.verde.gradiente.reversed(), startPoint: .top, endPoint: .bottom)))
                        .shadow(color: Tono.verde.base.opacity(0.45), radius: 6)
                        .fixedSize()
                } else {
                    Image(systemName: "video.fill")
                        .font(.system(size: redondo ? 13 : 11, weight: .semibold))
                        .frame(width: redondo ? 34 : 28, height: redondo ? 34 : 28)
                        .background(Circle().fill(LinearGradient(colors: Tono.verde.gradiente.reversed(), startPoint: .top, endPoint: .bottom)))
                        .shadow(color: Tono.verde.base.opacity(0.45), radius: 6)
                }
            }
            .foregroundStyle(conTexto ? .black : .white)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help("Unirse a la reunión")
    }
}

/// Nueva canción: carátula grande, título y artista, ecualizador; de fondo, los colores de la carátula.
private struct AhoraSuena: View {
    let estado: EstadoIsla
    let musica: Musica

    var body: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: estado.notch.height)
            HStack(spacing: 13) {
                Caratula(imagen: musica.caratula, lado: 46, radio: 11, resplandor: true)
                    .modifier(Entrada())
                VStack(alignment: .leading, spacing: 2) {
                    Rotulo(musica.sonando ? "Ahora suena" : "En pausa", color: Tono.de(musica.acento).claro)
                    Text(musica.titulo).font(.system(size: 14, weight: .semibold)).foregroundStyle(Halo.texto).lineLimit(1)
                    Text(musica.artista).font(.system(size: 12)).foregroundStyle(Halo.texto2).lineLimit(1)
                }
                Spacer(minLength: 8)
                Ecualizador(color: Tono.de(musica.acento).claro, activo: musica.sonando)
            }
            .padding(.horizontal, 22)
            .frame(maxHeight: .infinity)
        }
        .background { LuzBorde(tono: Tono.de(musica.acento), fuerza: 0.5, alto: 0.95, centro: 0.3, ancho: 0.9) }
    }
}

/// Fondo con los colores de la carátula: la imagen muy desenfocada, más fuerte a la izquierda y que se
/// funde en negro hacia la derecha (como las tarjetas de Live Activities).
private struct FondoArte<Forma: Shape>: View {
    let imagen: NSImage?
    let forma: Forma
    var alcance: CGFloat = 0.75

    var body: some View {
        if let imagen {
            GeometryReader { geo in
                Image(nsImage: imagen).resizable().scaledToFill()
                    .frame(width: geo.size.width * 0.7, height: geo.size.height * 1.4)
                    .blur(radius: 34)
                    .saturation(1.5)
                    .opacity(0.7)
                    .frame(width: geo.size.width, height: geo.size.height, alignment: .leading)
                    .mask(LinearGradient(stops: [.init(color: .black, location: 0), .init(color: .clear, location: alcance)],
                                         startPoint: .leading, endPoint: .trailing))
                    .overlay(LinearGradient(colors: [.black.opacity(0.0), .black.opacity(0.35)], startPoint: .top, endPoint: .bottom))
            }
            .clipShape(forma)
            .allowsHitTesting(false)
        }
    }
}

private struct Expandida: View {
    let estado: EstadoIsla
    let musica: Musica
    let agenda: Agenda
    let privacidad: Privacidad
    let claude: SesionesClaude
    let agentes: AgentesRemotos
    let salud: EstadoSalud
    /// Render sin app (ImageRenderer no dibuja ScrollView): las listas se cortan abajo en vez de desplazarse.
    var simulado = false
    let unirse: (URL) -> Void
    let abrirSalud: () -> Void
    let medirSalud: () -> Void

    /// Sin elegir: lo que más importa ahora (un agente abierto desde su aviso, Claude esperándote o un agente con
    /// alerta, el Mac en rojo, Claude trabajando, la agenda).
    private var porDefecto: EstadoIsla.Pestana {
        if estado.agenteAbierto != nil || !claude.esperando.isEmpty || agentes.hayAlertas { return .agentes }
        if salud.diagnostico.gravedad == .mal { return .mac }
        if claude.hayActividad { return .agentes }
        return agenda.eventos.isEmpty ? .mac : .agenda
    }

    /// Punto de la pestaña Agentes: naranja si Claude te espera, rojo o ámbar si un agente remoto avisa.
    private var puntoAgentes: Color? {
        if !claude.esperando.isEmpty { return Tono.claude.base }
        if agentes.agentes.contains(where: { $0.estado == .caido }) { return AgentesRemotos.Estado.caido.color }
        return agentes.hayAlertas ? AgentesRemotos.Estado.alerta.color : nil
    }

    /// La luz de la derecha, solo cuando algo pide atención: Claude te espera, un agente avisa (o su detalle está
    /// abierto), hay una reunión en la próxima hora, el Mac no está bien. Si todo está en calma, no hay luz.
    private func tonoPestana(_ p: EstadoIsla.Pestana) -> Tono? {
        switch p {
        case .agentes:
            if !claude.esperando.isEmpty { return .claude }
            if let a = agentes.agentes.first(where: { $0.estado == .caido || $0.estado == .alerta }) { return Tono.agente(a.estado) }
            if let nombre = estado.agenteAbierto, let a = agentes.agentes.first(where: { $0.nombre == nombre }) { return Tono.agente(a.estado) }
            return nil
        case .agenda:
            return agenda.eventos.first { $0.fin > Date() && $0.inicio.timeIntervalSinceNow < 3600 }.map { Tono.de($0.color) }
        case .mac:
            let g = salud.diagnostico.gravedad
            return g == .bien ? nil : Tono.gravedad(g)
        }
    }

    private func elegir(_ p: EstadoIsla.Pestana) {
        estado.pestana = p
        estado.agenteAbierto = nil
        switch p {
        case .agentes:
            claude.actualizarUso()
            agentes.refrescar()
        case .mac: medirSalud()
        case .agenda: break
        }
    }

    /// "Revisión de contrato · Arc" si coincide con una reunión en curso; si no, la app.
    private var etiquetaLlamada: String {
        let ahora = Date()
        let app = privacidad.nombre.isEmpty ? (privacidad.camara ? "Cámara" : "Micrófono") : privacidad.nombre
        if let reunion = agenda.eventos.first(where: { $0.inicio <= ahora.addingTimeInterval(300) && $0.fin > ahora }) {
            return reunion.titulo + " · " + app
        }
        return "En llamada · " + app
    }

    var body: some View {
        let actual = estado.pestana ?? porDefecto
        VStack(spacing: 0) {
            HStack {  // el notch físico; a la derecha, quién usa la cámara o el micrófono
                Spacer()
                if privacidad.activo {
                    Button { privacidad.irALaApp() } label: {
                        HStack(spacing: 6) {
                            Text(etiquetaLlamada)
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(Halo.texto2)
                                .lineLimit(1)
                            if let desde = privacidad.desde { Cronometro(desde: desde) }
                            PuntoPrivacidad(camara: privacidad.camara)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Volver a la llamada")
                    .padding(.trailing, 32)
                }
            }
            .frame(height: estado.notch.height)
            HStack(alignment: .top, spacing: 22) {
                Reproductor(musica: musica)
                    .frame(width: 212, alignment: .leading)
                    .frame(maxHeight: .infinity, alignment: .center)
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 4) {
                        PildoraHalo(titulo: "Agentes", cuenta: claude.sesiones.count + agentes.agentes.count, punto: puntoAgentes,
                                    activa: actual == .agentes) { elegir(.agentes) }
                        PildoraHalo(titulo: "Agenda", cuenta: agenda.eventos.count, activa: actual == .agenda) { elegir(.agenda) }
                        PildoraHalo(titulo: "Mac", punto: Tono.gravedad(salud.diagnostico.gravedad).base, activa: actual == .mac) {
                            elegir(.mac)
                        }
                        Spacer(minLength: 4)
                        if actual == .agentes && estado.agenteAbierto == nil && claude.tokensHoy > 0 {
                            ActividadDia(porHora: claude.porHora)
                                .help("Hoy: \(claude.respuestasHoy) respuestas y \(Tiempo.tokens(claude.tokensHoy)) tokens escritos entre todas las sesiones")
                        }
                    }
                    switch actual {
                    case .agentes:
                        if let nombre = estado.agenteAbierto, let agente = agentes.agentes.first(where: { $0.nombre == nombre }) {
                            DetalleAgente(agente: agente, consultando: agentes.consultando) { estado.agenteAbierto = nil }
                        } else {
                            ListaAgentes(claude: claude, agentes: agentes, simulado: simulado) { estado.agenteAbierto = $0 }
                        }
                    case .agenda: ListaAgenda(agenda: agenda, unirse: unirse)
                    case .mac: ResumenMac(salud: salud, abrir: abrirSalud)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .padding(.horizontal, 26)
            .padding(.top, 4)
            .padding(.bottom, 14)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background {  // la música tiñe el borde de abajo a la izquierda; la pestaña, a la derecha
            ZStack {
                if musica.hayPista { LuzBorde(tono: Tono.de(musica.acento), fuerza: 0.5, alto: 0.6, centro: 0.2, ancho: 0.48) }
                if let tono = tonoPestana(actual) { LuzBorde(tono: tono, fuerza: 0.26, alto: 0.5, centro: 0.74, ancho: 0.5) }
            }
        }
        .onAppear {
            claude.actualizarUso()
            claude.vigilarActividad(true)
            switch estado.pestana ?? porDefecto {
            case .mac: medirSalud()
            case .agentes: agentes.refrescar()
            case .agenda: break
            }
        }
        .onDisappear { claude.vigilarActividad(false) }
    }
}

/// Tokens escritos por hora en las últimas 8 horas de hoy (como la gráfica de UV de las referencias);
/// la hora actual en naranja.
private struct ActividadDia: View {
    let porHora: [Int]

    var body: some View {
        let ahora = Calendar.current.component(.hour, from: Date())
        let horas = Array(max(0, ahora - 7)...ahora)
        let maximo = max(1, horas.map { porHora[$0] }.max() ?? 1)
        HStack(alignment: .bottom, spacing: 1.5) {
            ForEach(horas, id: \.self) { h in
                Capsule()
                    .fill(h == ahora ? Tono.claude.base : .white.opacity(0.3))
                    .frame(width: 2.5, height: max(2.5, 14 * CGFloat(porHora[h]) / CGFloat(maximo)))
            }
        }
        .frame(height: 14, alignment: .bottom)

    }
}

/// Lo más importante de Salud del Mac en la isla: el titular del diagnóstico y cuatro diales cuyo resplandor sube
/// con la gravedad (verde tranquilo, ámbar, rojo intenso). El titular y el ícono abren el panel completo.
private struct ResumenMac: View {
    let salud: EstadoSalud
    let abrir: () -> Void

    private static func gigas(_ bytes: Double) -> String {
        let g = bytes / 1e9
        return g < 10 ? String(format: "%.1f", g).replacingOccurrences(of: ".", with: ",") : String(format: "%.0f", g)
    }

    var body: some View {
        let d = salud.diagnostico
        VStack(alignment: .leading, spacing: 9) {
            Button(action: abrir) {
                HStack(spacing: 10) {
                    PuntoBrillante(color: Tono.gravedad(d.gravedad).base, lado: 7)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(d.titulo).font(.system(size: 12.5, weight: .semibold)).foregroundStyle(Halo.texto).lineLimit(1)
                        Text(d.frase).font(Halo.detalle).foregroundStyle(Halo.texto2).lineLimit(1)
                    }
                    Spacer(minLength: 4)
                    Image(systemName: "arrow.up.forward.app")
                        .font(.system(size: 15, weight: .regular))
                        .foregroundStyle(.white.opacity(0.7))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Abrir Salud del Mac (detalle y limpieza)")
            HStack(spacing: 0) {
                DialMac(valor: salud.cpu, gravedad: salud.gravedadCPU,
                        numero: String(format: "%.0f", salud.cpu * 100), unidad: "%", titulo: "Procesador")
                DialMac(valor: salud.memoriaUsada / max(1, salud.memoriaTotal), gravedad: salud.gravedadMemoria,
                        numero: String(format: "%.0f", salud.memoriaUsada / 1e9),
                        unidad: String(format: "/%.0f", salud.memoriaTotal / 1.073741824e9), titulo: "Memoria GB")
                DialMac(valor: salud.gpu, gravedad: salud.gravedadGPU,
                        numero: String(format: "%.0f", salud.gpu * 100), unidad: "%", titulo: "Gráficos")
                DialMac(valor: 1 - salud.discoLibre / max(1, salud.discoTotal), gravedad: salud.gravedadDisco,
                        numero: Self.gigas(salud.discoLibre), unidad: "GB", titulo: "Disco libre")
            }
        }
    }
}

/// Un dial de Salud del Mac: anillo encendido hasta el uso, resplandor según la gravedad y el número en el centro.
private struct DialMac: View {
    let valor: Double
    let gravedad: Gravedad
    let numero: String
    let unidad: String
    let titulo: String

    var body: some View {
        VStack(spacing: 6) {
            Dial(lado: 52, valor: valor, colores: Tono.gravedad(gravedad).gradiente, marcas: 32, anillo: 4,
                 brillo: gravedad == .mal ? 0.8 : (gravedad == .atento ? 0.55 : 0.25)) {
                NumeroFino(texto: numero, unidad: unidad, tamano: 14.5, peso: .light)
            }
            Rotulo(titulo, color: Halo.texto3)
        }
        .frame(maxWidth: .infinity)
    }
}

/// Pestaña Agentes: las sesiones de Claude Code y los agentes remotos en una sola lista, primero lo que necesita
/// atención (Claude esperándote, un agente con alerta), luego lo que trabaja y al final lo que está quieto.
/// Tocar un agente remoto abre su detalle con el día (`DetalleAgente`).
private struct ListaAgentes: View {
    let claude: SesionesClaude
    let agentes: AgentesRemotos
    var simulado = false
    let abrir: (String) -> Void

    private enum Elemento: Identifiable {
        case sesion(SesionesClaude.Sesion)
        case agente(AgentesRemotos.Agente)

        var id: String {
            switch self {
            case .sesion(let s): return "s" + s.id
            case .agente(let a): return "a" + a.id
            }
        }

        var prioridad: Int {
            switch self {
            case .sesion(let s): return s.estado == .esperando ? 0 : (s.estado == .trabajando ? 2 : 4)
            case .agente(let a): return a.estado == .alerta || a.estado == .caido || !a.alertas.isEmpty ? 1 : 3
            }
        }
    }

    private var elementos: [Elemento] {
        let todos = claude.sesiones.map(Elemento.sesion) + agentes.agentes.map(Elemento.agente)
        return todos.enumerated()
            .sorted { ($0.element.prioridad, $0.offset) < ($1.element.prioridad, $1.offset) }
            .map(\.element)
    }

    var body: some View {
        if elementos.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text("Sin sesiones abiertas").font(.system(size: 13)).foregroundStyle(Halo.texto2)
                Text("Aquí aparecen tus sesiones de Claude Code y los agentes remotos que configures.")
                    .font(Halo.detalle).foregroundStyle(Halo.texto3)
            }
        } else if simulado {
            Color.clear.overlay(alignment: .top) { lista }.clipped().mask(desvanecido)
        } else {
            ScrollView(.vertical, showsIndicators: false) { lista.padding(.bottom, 10) }
                .mask(desvanecido)
        }
    }

    private var lista: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(elementos) { e in
                switch e {
                case .sesion(let s): FilaSesion(sesion: s)
                case .agente(let a): FilaAgente(agente: a) { abrir(a.nombre) }
                }
            }
        }
    }

    /// Lo que sigue más abajo se desvanece (pista de que se puede desplazar).
    private var desvanecido: some View {
        LinearGradient(stops: [.init(color: .black, location: 0), .init(color: .black, location: 0.86), .init(color: .clear, location: 1)],
                       startPoint: .top, endPoint: .bottom)
    }
}

/// Una sesión de Claude Code: qué hace o qué te pide, y su contexto. El clic abre justo esa sesión. Si te espera,
/// va resaltada en naranja y con el pedido completo.
private struct FilaSesion: View {
    let sesion: SesionesClaude.Sesion

    var body: some View {
        let espera = sesion.estado == .esperando
        Button { SesionesClaude.abrir(sesion) } label: {
            HStack(spacing: 10) {
                Group {
                    if espera { Insignia(icono: .estrella, tono: .claude, lado: 26) } else { EstadoSesion(estado: sesion.estado).frame(width: 15, height: 15) }
                }
                .frame(width: 26, height: 26)
                VStack(alignment: .leading, spacing: 1) {
                    Text(sesion.nombre).font(.system(size: 12.5, weight: .semibold)).foregroundStyle(Halo.texto).lineLimit(1)
                    Text(Tiempo.sesion(sesion))
                        .font(Halo.detalle)
                        .foregroundStyle(espera ? Tono.claude.claro : Halo.texto3)
                        .lineLimit(espera ? 2 : 1)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 4)
                if espera {
                    BotonHalo(titulo: "Responder", tono: .claude, alto: 26) { SesionesClaude.abrir(sesion) }
                } else if sesion.contexto > 0 {
                    Contexto(tokens: sesion.contexto)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, espera ? 7 : 3)
            .background {
                if espera { Color.clear.tarjetaHalo(radio: 14, activa: true, tono: .claude) }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(espera ? "Abrir la sesión para responder" : "Abrir la sesión")
    }
}

/// Contexto de una conversación: anillo pequeño (de 0 a 1 M) y la cifra; ámbar pasados ~600 k.
private struct Contexto: View {
    let tokens: Int

    var body: some View {
        let alto = tokens > 600_000
        let color = alto ? Tono.ambar.base : Color.white.opacity(0.5)
        HStack(spacing: 4) {
            ZStack {
                Circle().stroke(.white.opacity(0.12), lineWidth: 1.6)
                Circle().trim(from: 0, to: min(1, Double(tokens) / 1_000_000))
                    .stroke(color, style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            .frame(width: 10, height: 10)
            Text(Tiempo.tokens(tokens))
                .font(.system(size: 10, weight: .medium)).monospacedDigit()
                .foregroundStyle(alto ? Tono.ambar.claro : Halo.texto3)
        }
        .fixedSize()
        .help("Contexto de esta conversación. Si pasa de ~600 k conviene abrir una nueva.")
    }
}

/// Ícono del estado de una sesión: estrella que gira (trabaja), punto que late (te espera), check (lista).
private struct EstadoSesion: View {
    let estado: SesionesClaude.Estado
    @State private var giro = false

    var body: some View {
        switch estado {
        case .trabajando:
            EstrellaClaude().fill(Tono.claude.base)
                .rotationEffect(.degrees(giro ? 360 : 0))
                .onAppear { withAnimation(.linear(duration: 6).repeatForever(autoreverses: false)) { giro = true } }
        case .esperando:
            PuntoBrillante(color: Tono.claude.base, lado: 8)
        case .lista:
            Image(systemName: "checkmark").font(.system(size: 10, weight: .bold)).foregroundStyle(.white.opacity(0.4))
        }
    }
}

struct Caratula: View {
    let imagen: NSImage?
    let lado: CGFloat
    let radio: CGFloat
    /// Detrás, la misma carátula desenfocada: un brillo con los colores reales del álbum (como Apple Music).
    var resplandor = false

    var body: some View {
        if resplandor, let imagen {
            portada.background {
                Image(nsImage: imagen).resizable().scaledToFill()
                    .frame(width: lado, height: lado)
                    .clipShape(RoundedRectangle(cornerRadius: radio, style: .continuous))
                    .blur(radius: lado * 0.22)
                    .opacity(0.75)
                    .offset(y: lado * 0.06)
            }
        } else {
            portada
        }
    }

    private var portada: some View {
        Group {
            if let imagen {
                Image(nsImage: imagen).resizable().scaledToFill()
            } else {
                LinearGradient(colors: [Color(white: 0.25), Color(white: 0.12)], startPoint: .top, endPoint: .bottom)
                    .overlay(Image(systemName: "music.note").font(.system(size: lado * 0.4)).foregroundStyle(.white.opacity(0.5)))
            }
        }
        .frame(width: lado, height: lado)
        .clipShape(RoundedRectangle(cornerRadius: radio, style: .continuous))
    }
}

/// Reproductor de la vista abierta: carátula, título, onda en el color del álbum, progreso y controles.
private struct Reproductor: View {
    let musica: Musica

    var body: some View {
        if musica.hayPista {
            VStack(alignment: .leading, spacing: 9) {
                HStack(spacing: 11) {
                    Caratula(imagen: musica.caratula, lado: 50, radio: 12, resplandor: true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(musica.titulo).font(.system(size: 14, weight: .semibold)).foregroundStyle(Halo.texto).lineLimit(1)
                        Text(musica.artista).font(.system(size: 11.5)).foregroundStyle(Halo.texto2).lineLimit(1)
                    }
                    Spacer(minLength: 4)
                    Ecualizador(color: Tono.de(musica.acento).claro, activo: musica.sonando)
                }
                Progreso(musica: musica)
                HStack(spacing: 0) {
                    Spacer()
                    BotonIsla(simbolo: "backward.fill") { musica.anterior() }
                    Spacer()
                    BotonIsla(simbolo: musica.sonando ? "pause.fill" : "play.fill", grande: true) { musica.alternar() }
                    Spacer()
                    BotonIsla(simbolo: "forward.fill") { musica.siguiente() }
                    Spacer()
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 8) {
                EtiquetaIsla(titulo: "Música")
                Text("Nada sonando todavía").font(.system(size: 13)).foregroundStyle(Halo.texto2)
                HStack(spacing: 8) {
                    BotonHalo(titulo: "Reanudar", icono: "play.fill", alto: 28) { musica.alternar() }
                    BotonHalo(titulo: "Abrir Spotify", secundario: true, alto: 28) { musica.abrirSpotify() }
                }
            }
        }
    }
}

/// Progreso como un deslizador fino: lo escuchado en línea continua, un punto brillante y lo que falta punteado.
/// Solo se redibuja (1 vez por segundo) mientras la isla está abierta.
private struct Progreso: View {
    let musica: Musica

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { ctx in
            let pos = musica.posicion(en: ctx.date)
            let fraccion = musica.duracion > 0 ? min(1, pos / musica.duracion) : 0
            HStack(spacing: 8) {
                Text(Tiempo.reloj(pos))
                GeometryReader { geo in
                    let w = geo.size.width
                    let x = w * fraccion
                    let medio = geo.size.height / 2
                    ZStack(alignment: .leading) {
                        Path { p in
                            p.move(to: CGPoint(x: x + 6, y: medio))
                            p.addLine(to: CGPoint(x: w, y: medio))
                        }
                        .stroke(.white.opacity(0.3), style: StrokeStyle(lineWidth: 1.4, lineCap: .round, dash: [0.01, 4]))
                        Capsule()
                            .fill(LinearGradient(colors: [Tono.de(musica.acento).base, Tono.de(musica.acento).claro], startPoint: .leading, endPoint: .trailing))
                            .frame(width: x, height: 3)
                            .shadow(color: Tono.de(musica.acento).base.opacity(0.8), radius: 3)
                        Circle().fill(.white).frame(width: 9, height: 9)
                            .shadow(color: Tono.de(musica.acento).base, radius: 5)
                            .offset(x: x - 4.5)
                    }
                    .frame(height: geo.size.height)
                }
                .frame(height: 8)
                Text("-" + Tiempo.reloj(max(0, musica.duracion - pos)))
            }
            .font(.system(size: 10, weight: .medium))
            .monospacedDigit()
            .foregroundStyle(Halo.texto3)
        }
    }
}

/// Controles como los de iOS: glifos blancos sin fondo.
private struct BotonIsla: View {
    let simbolo: String
    var grande = false
    let accion: () -> Void

    var body: some View {
        Button(action: accion) {
            Image(systemName: simbolo)
                .font(.system(size: grande ? 22 : 16, weight: .semibold))
                .foregroundStyle(.white.opacity(grande ? 1 : 0.85))
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 34, height: 30)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Agenda: la próxima reunión como protagonista (cuenta regresiva en números de puntos, título y Unirse) y el
/// resto del día como una línea de tiempo con regla fina y la hora actual marcada. Se redibuja 1 vez por segundo
/// solo mientras la isla está abierta en esta pestaña.
private struct ListaAgenda: View {
    let agenda: Agenda
    let unirse: (URL) -> Void

    var body: some View {
        if !agenda.permitido {
            Text("Permite el acceso al Calendario en Ajustes → Privacidad y seguridad → Calendarios.")
                .font(.system(size: 12)).foregroundStyle(.white.opacity(0.6))
        } else {
            TimelineView(.periodic(from: .now, by: 1)) { ctx in
                let ahora = ctx.date
                let proxima = agenda.eventos.first { $0.fin > ahora }
                VStack(alignment: .leading, spacing: 0) {
                    if let proxima {
                        Protagonista(evento: proxima, ahora: ahora, unirse: unirse)
                    } else {
                        VStack(alignment: .leading, spacing: 3) {
                            Rotulo("Agenda")
                            Text("Nada más en las próximas horas").font(.system(size: 20, weight: .thin))
                                .foregroundStyle(Halo.texto)
                        }
                    }
                    Spacer(minLength: 6)
                    LineaDia(eventos: agenda.eventos, destacado: proxima?.id, ahora: ahora)
                }
            }
        }
    }
}

/// La próxima reunión: cuánto falta (o cuánto queda si ya empezó), qué es y el botón para unirse.
private struct Protagonista: View {
    let evento: Agenda.Evento
    let ahora: Date
    let unirse: (URL) -> Void

    private var cuenta: (rotulo: String, numero: String, unidad: String) {
        let s = evento.inicio.timeIntervalSince(ahora)
        if s <= 0 {
            let queda = max(1, Int((evento.fin.timeIntervalSince(ahora) / 60).rounded(.up)))
            return ("Termina en", "\(queda)", "min")
        }
        if s < 600 { return ("Empieza en", Tiempo.cuentaRegresiva(hasta: evento.inicio, desde: ahora), "") }
        if s < 3600 { return ("Empieza en", "\(Int((s / 60).rounded(.up)))", "min") }
        let manana = !Calendar.current.isDate(evento.inicio, inSameDayAs: ahora)
        return (manana ? "Mañana a las" : "A las", Tiempo.horaDelDia(evento.inicio, conPeriodo: false), Tiempo.periodo(evento.inicio))
    }

    var body: some View {
        let c = cuenta
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 7) {
                Rotulo(c.rotulo, color: Tono.de(evento.color).claro)
                HStack(alignment: .lastTextBaseline, spacing: 5) {
                    NumeroPuntos(texto: c.numero, punto: 2.8, paso: 3.9, color: .white)
                    if !c.unidad.isEmpty {
                        Text(c.unidad).font(.system(size: 11, weight: .medium)).foregroundStyle(.white.opacity(0.5))
                    }
                }
            }
            .fixedSize()
            Rectangle().fill(.white.opacity(0.12)).frame(width: 0.5, height: 36)
            VStack(alignment: .leading, spacing: 3) {
                Text(evento.titulo).font(.system(size: 13.5, weight: .semibold)).foregroundStyle(Halo.texto).lineLimit(1)
                Text(Tiempo.franja(evento, conEstado: false) + (evento.enlace.flatMap { $0.host }.map { " · " + Tiempo.servicio($0) } ?? "")).font(Halo.detalle).foregroundStyle(Halo.texto2).lineLimit(1)
            }
            Spacer(minLength: 4)
            if evento.sePuedeUnir, let enlace = evento.enlace {
                BotonUnirse(redondo: true) { unirse(enlace) }  // círculo, como contestar: el título cabe en una línea
            }
        }
    }
}

/// El día como una regla: marcas finas cada cuarto de hora, las horas numeradas, los eventos como barras de su
/// color (la próxima reunión con brillo) y una línea roja en la hora actual.
private struct LineaDia: View {
    let eventos: [Agenda.Evento]
    let destacado: String?
    let ahora: Date

    private static let horas = 9.0

    var body: some View {
        let hora = Calendar.current.dateInterval(of: .hour, for: ahora)?.start ?? ahora
        let inicio = hora.addingTimeInterval(-3600)
        let fin = inicio.addingTimeInterval(Self.horas * 3600)
        let despues = eventos.filter { $0.inicio >= fin }.count
        GeometryReader { geo in
            let w = geo.size.width
            let x = { (d: Date) -> CGFloat in CGFloat(d.timeIntervalSince(inicio) / fin.timeIntervalSince(inicio)) * w }
            let visibles = carriles(eventos.filter { $0.fin > inicio && $0.inicio < fin })
            let base: CGFloat = 38
            ZStack(alignment: .topLeading) {
                Path { p in  // regla
                    let cuartos = Int(Self.horas * 4)
                    for q in 0...cuartos {
                        let xx = w * CGFloat(q) / CGFloat(cuartos)
                        let largo: CGFloat = q % 4 == 0 ? 7 : 3
                        p.move(to: CGPoint(x: xx, y: base - largo))
                        p.addLine(to: CGPoint(x: xx, y: base))
                    }
                }
                .stroke(.white.opacity(0.22), lineWidth: 0.8)
                ForEach(1..<Int(Self.horas), id: \.self) { i in
                    let h = inicio.addingTimeInterval(Double(i) * 3600)
                    Text(Tiempo.horaCorta(h))
                        .font(.system(size: 8.5, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.35))
                        .fixedSize()
                        .position(x: w * CGFloat(i) / CGFloat(Self.horas), y: base + 8)
                }
                ForEach(visibles, id: \.evento.id) { item in
                    let e = item.evento
                    let x0 = max(0, x(e.inicio)), x1 = min(w, x(e.fin))
                    let principal = e.id == destacado
                    let alto: CGFloat = principal ? 6 : 4
                    let y: CGFloat = item.carril == 0 ? 17 : 24
                    Capsule()
                        .fill(LinearGradient(colors: [Tono.de(e.color).base, Tono.de(e.color).claro], startPoint: .leading, endPoint: .trailing))
                        .opacity(principal ? 1 : 0.6)
                        .frame(width: max(4, x1 - x0), height: alto)
                        .shadow(color: Tono.de(e.color).base.opacity(principal ? 0.9 : 0.3), radius: principal ? 6 : 3)
                        .offset(x: x0, y: y - alto / 2)
                    let espacio = (item.siguiente.map { x($0) } ?? w) - x0 - 6
                    if item.carril == 0 && espacio > 30 {
                        Text(e.titulo)
                            .font(.system(size: 9.5, weight: principal ? .semibold : .medium))
                            .foregroundStyle(.white.opacity(principal ? 0.85 : 0.6))
                            .lineLimit(1)
                            .frame(width: espacio, alignment: .leading)
                            .offset(x: x0, y: 0)
                    }
                }
                let xa = x(ahora)
                Rectangle().fill(LinearGradient(colors: [Paleta.ahora.opacity(0), Paleta.ahora], startPoint: .top, endPoint: .bottom))
                    .frame(width: 1.2, height: base - 10)
                    .shadow(color: Paleta.ahora, radius: 3)
                    .offset(x: xa - 0.6, y: 10)
                PuntoBrillante(color: Paleta.ahora, lado: 6)
                    .offset(x: xa - 3, y: base - 3)
                if despues > 0 {
                    Text("+\(despues) después")
                        .font(.system(size: 9, weight: .medium)).foregroundStyle(.white.opacity(0.4)).fixedSize()
                        .frame(width: w, alignment: .trailing)
                        .offset(y: 0)
                }
            }
        }
        .frame(height: 50)
    }

    /// Reparte los eventos en dos carriles para que dos reuniones encimadas no se tapen; `siguiente` es dónde
    /// empieza la próxima del carril de arriba (hasta ahí cabe el título).
    private func carriles(_ lista: [Agenda.Evento]) -> [(evento: Agenda.Evento, carril: Int, siguiente: Date?)] {
        var finCarril = [Date.distantPast, Date.distantPast]
        let repartidos = lista.sorted { $0.inicio < $1.inicio }.map { e -> (Agenda.Evento, Int) in
            let carril = e.inicio >= finCarril[0] ? 0 : 1
            finCarril[carril] = max(finCarril[carril], e.fin)
            return (e, carril)
        }
        let arriba = repartidos.filter { $0.1 == 0 }.map(\.0)
        return repartidos.map { e, carril in
            (e, carril, carril == 0 ? arriba.first { $0.inicio > e.inicio }?.inicio : nil)
        }
    }
}

private struct EtiquetaIsla: View {
    let titulo: String

    var body: some View {
        Rotulo(titulo, color: Halo.texto3)
    }
}

enum Tiempo {
    static func reloj(_ segundos: Double) -> String {
        let s = max(0, Int(segundos.rounded()))
        return String(format: "%d:%02d", s / 60, s % 60)
    }

    static func faltan(_ fecha: Date) -> String {
        let minutos = Int((fecha.timeIntervalSinceNow / 60).rounded(.up))
        return minutos <= 0 ? "ahora" : "en \(minutos) min"
    }

    /// "4:59" hasta que empieza; "Ahora" cuando ya empezó.
    static func cuentaRegresiva(hasta inicio: Date, desde ahora: Date) -> String {
        let s = Int(inicio.timeIntervalSince(ahora).rounded(.up))
        return s <= 0 ? "Ahora" : reloj(Double(s))
    }

    /// "hace 3 min", "hace 2 h", "hace 4 d".
    static func hace(_ fecha: Date) -> String {
        let s = Int(-fecha.timeIntervalSinceNow)
        if s < 60 { return "ahora" }
        if s < 3600 { return "hace \(s / 60) min" }
        if s < 48 * 3600 { return "hace \(s / 3600) h" }
        return "hace \(s / 86_400) d"
    }

    private static func formato(_ patron: String) -> DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "es_CO")
        f.dateFormat = patron
        return f
    }

    /// "3:00 p. m." (o "3:00" sin el periodo), sin el día.
    static func horaDelDia(_ fecha: Date, conPeriodo: Bool = true) -> String {
        formato(conPeriodo ? "h:mm a" : "h:mm").string(from: fecha)
    }

    /// "a. m." / "p. m.".
    static func periodo(_ fecha: Date) -> String { formato("a").string(from: fecha) }

    /// Número de la hora para la regla de la agenda ("9", "10", "1").
    static func horaCorta(_ fecha: Date) -> String { formato("h").string(from: fecha) }

    /// "Meet", "Zoom", "Teams"… según el enlace de la reunión.
    static func servicio(_ host: String) -> String {
        if host.contains("meet.google") { return "Meet" }
        if host.contains("zoom") { return "Zoom" }
        if host.contains("teams") { return "Teams" }
        if host.contains("webex") { return "Webex" }
        if host.contains("facetime") { return "FaceTime" }
        return "Videollamada"
    }

    /// "Editando Isla.swift · 3 min", "Necesita tu permiso: swift build", "Lista · hace 5 min".
    static func sesion(_ s: SesionesClaude.Sesion) -> String {
        let minutos = max(0, Int(-s.desde.timeIntervalSinceNow) / 60)
        switch s.estado {
        case .trabajando:
            return (s.actividad.isEmpty ? "Trabajando" : s.actividad) + (minutos > 0 ? " · \(minutos) min" : "")
        case .esperando:
            return s.espera + (s.actividad.isEmpty ? "" : ": " + s.actividad)
        case .lista:
            return "Lista · " + hace(s.desde) + (s.resumen.isEmpty ? "" : " · " + s.resumen)
        }
    }

    /// 76 400 → "76 k"; 1 230 000 → "1,2 M".
    static func tokens(_ n: Int) -> String {
        if n >= 1_000_000 { return String(format: "%.1f M", Double(n) / 1_000_000).replacingOccurrences(of: ".", with: ",") }
        if n >= 1_000 { return "\(n / 1_000) k" }
        return "\(n)"
    }

    /// "3:00 a. m." si es hoy; "mañana 3:00 a. m.", "ayer 8:03 a. m." o "lun. 8:00 a. m." si no.
    static func hora(_ fecha: Date) -> String {
        let formato = DateFormatter()
        formato.locale = Locale(identifier: "es_CO")
        let cal = Calendar.current
        formato.dateFormat = cal.isDateInToday(fecha) || cal.isDateInTomorrow(fecha) || cal.isDateInYesterday(fecha) ? "h:mm a" : "EEE h:mm a"
        let dia = cal.isDateInTomorrow(fecha) ? "mañana " : cal.isDateInYesterday(fecha) ? "ayer " : ""
        return dia + formato.string(from: fecha)
    }

    /// "2:04 – 2:49 p. m." (formato colombiano de 12 horas).
    static func franja(_ e: Agenda.Evento, conEstado: Bool = true) -> String {
        let inicio = horaDelDia(e.inicio, conPeriodo: false)
        let fin = horaDelDia(e.fin)
        let dia = Calendar.current.isDateInToday(e.inicio) ? "" : "Mañana · "
        let ahora = Date()
        let estado = !conEstado ? "" : e.inicio <= ahora ? " · en curso"
            : (e.inicio.timeIntervalSince(ahora) < 3600 ? " · \(faltan(e.inicio))" : "")
        return dia + inicio + " – " + fin + estado
    }
}
