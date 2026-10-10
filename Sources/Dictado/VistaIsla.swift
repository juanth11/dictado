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
            contenido
                .id(estado.expandida ? UUID(uuidString: "00000000-0000-0000-0000-000000000001")! : estado.idActividad)
                .transition(.asymmetric(
                    insertion: .scale(scale: 0.7, anchor: .top).combined(with: .opacity),
                    removal: .opacity))
        }
        .frame(width: tam.width, height: tam.height)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(.spring(response: 0.46, dampingFraction: 0.74), value: estado.expandida)
        .animation(.spring(response: 0.5, dampingFraction: 0.66), value: estado.idActividad)
        .animation(.spring(response: 0.38, dampingFraction: 0.85), value: alas)
        .animation(.spring(response: 0.38, dampingFraction: 0.85), value: privacidad.activo)
        .environment(\.colorScheme, .dark)
        .onChange(of: alas) { control?.refrescarCompacta() }
        .onChange(of: privacidad.activo) { control?.refrescarCompacta() }
    }

    @ViewBuilder private var contenido: some View {
        if estado.expandida {
            Expandida(estado: estado, musica: musica, agenda: agenda, privacidad: privacidad, claude: claude, salud: salud,
                      unirse: { control?.unirse($0) }, abrirSalud: { control?.abrirSalud() }, medirSalud: { control?.medirSalud() })
        } else if let actividad = estado.actividad {
            switch actividad {
            case .dictado:
                DictadoIsla(estado: estado, hud: hud)
            case .aviso(let icono, let texto):
                Fila(notch: estado.notch) {
                    IconoSaltarin(simbolo: icono, color: icono == "exclamationmark.triangle" ? .orange : .green)
                    Text(texto).font(.system(size: 13, weight: .semibold)).foregroundStyle(.white).lineLimit(1)
                }
            case .cancion:
                AhoraSuena(estado: estado, musica: musica)
            case .evento(let titulo, let inicio, let color, let enlace):
                EventoIsla(estado: estado, titulo: titulo, inicio: inicio, color: color, enlace: enlace) { control?.unirse($0) }
            case .carga(let porcentaje):
                CargaIsla(estado: estado, porcentaje: porcentaje)
            case .nivel(let tipo, let valor, let silencio):
                BarraNivel(estado: estado, tipo: tipo, valor: valor, silencio: silencio)
            case .salud(let titulo, let detalle, let grave):
                SaludIsla(estado: estado, titulo: titulo, detalle: detalle, grave: grave) { control?.abrirSalud() }
            case .claude(let sesion, let necesita, let duracion):
                ClaudeIsla(estado: estado, sesion: sesion, necesita: necesita, duracion: duracion) { control?.abrirClaude(sesion) }
            }
        } else if alas {
            Compacta(estado: estado, musica: musica, agenda: agenda, privacidad: privacidad, claude: claude)
        }
    }
}

/// Una fila de contenido debajo del notch (para los avisos cortos).
private struct Fila<Contenido: View>: View {
    let notch: CGSize
    @ViewBuilder let contenido: () -> Contenido

    var body: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: notch.height)
            HStack(spacing: 10) { contenido() }
                .padding(.horizontal, 26)
                .frame(maxHeight: .infinity)
        }
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

/// Volumen o brillo (reemplaza el cuadro de macOS): barra ancha bajo el notch con ícono y porcentaje.
/// El brillo va en tono cálido; el silencio, apagado.
private struct BarraNivel: View {
    let estado: EstadoIsla
    let tipo: Niveles.Tipo
    let valor: Double
    let silencio: Bool

    private var simbolo: String {
        switch tipo {
        case .brillo: return valor < 0.35 ? "sun.min.fill" : "sun.max.fill"
        case .volumen: return silencio ? "speaker.slash.fill" : "speaker.wave.3.fill"
        }
    }

    private var color: Color {
        tipo == .brillo ? Color(red: 1.0, green: 0.82, blue: 0.36) : .white
    }

    var body: some View {
        let lleno = silencio ? 0 : valor
        VStack(spacing: 0) {
            Color.clear.frame(height: estado.notch.height)
            HStack(spacing: 12) {
                Image(systemName: simbolo, variableValue: tipo == .volumen ? max(valor, 0.01) : 1)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(silencio ? Color.white.opacity(0.4) : color)
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: 22)
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.white.opacity(0.13))
                        Capsule()
                            .fill(LinearGradient(colors: [color.opacity(0.7), color], startPoint: .leading, endPoint: .trailing))
                            .frame(width: max(8, geo.size.width * lleno))
                            .shadow(color: color.opacity(0.55), radius: 6)
                            .opacity(lleno > 0 ? 1 : 0)
                    }
                }
                .frame(height: 7)
                Text(silencio ? "Mudo" : "\(Int((valor * 100).rounded()))")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(silencio ? 0.45 : 0.85))
                    .contentTransition(.numericText(value: valor))
                    .frame(width: 34, alignment: .trailing)
            }
            .padding(.horizontal, 24)
            .frame(maxHeight: .infinity)
        }
        .animation(.spring(response: 0.28, dampingFraction: 0.9), value: valor)
        .animation(.spring(response: 0.28, dampingFraction: 0.9), value: silencio)
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
                    Capsule().fill(color).frame(width: 3, height: alto(i, t))
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

/// Aviso de Salud del Mac (disco casi lleno, memoria al límite, calor, una app al máximo).
private struct SaludIsla: View {
    let estado: EstadoIsla
    let titulo: String
    let detalle: String
    let grave: Bool
    let ver: () -> Void

    var body: some View {
        Fila(notch: estado.notch) {
            IconoSaltarin(simbolo: grave ? "exclamationmark.triangle.fill" : "gauge.with.dots.needle.67percent",
                          color: grave ? Color(red: 1, green: 0.42, blue: 0.36) : .orange)
                .font(.system(size: 18))
            VStack(alignment: .leading, spacing: 1) {
                Text("SALUD DEL MAC").font(.system(size: 9, weight: .semibold, design: .monospaced)).tracking(1.1)
                    .foregroundStyle(.white.opacity(0.45))
                Text(titulo).font(.system(size: 13, weight: .semibold)).foregroundStyle(.white).lineLimit(1)
                Text(detalle).font(.system(size: 11)).foregroundStyle(.white.opacity(0.55)).lineLimit(1)
            }
            Spacer(minLength: 6)
            Button(action: ver) {
                Text("Ver").font(.system(size: 12, weight: .semibold)).foregroundStyle(.black)
                    .padding(.horizontal, 14).frame(height: 28)
                    .background(Capsule().fill(.white)).contentShape(Capsule())
            }
            .buttonStyle(.plain)
        }
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
        Fila(notch: estado.notch) {
            ZStack(alignment: .bottomTrailing) {
                EstrellaClaude().fill(Color.claude).frame(width: 28, height: 28)
                    .rotationEffect(.degrees(giro ? 45 : 0))
                Image(systemName: necesita ? "exclamationmark.circle.fill" : "checkmark.circle.fill")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white, necesita ? Color.orange : Color.green)
                    .background(Circle().fill(.black).padding(-1.5))
                    .offset(x: 4, y: 4)
            }
            .frame(width: 36, height: 36)
            .modifier(Entrada())
            .onAppear { withAnimation(.spring(response: 1.1, dampingFraction: 0.45)) { giro = true } }
            VStack(alignment: .leading, spacing: 1) {
                Text(necesita ? sesion.espera.uppercased() : "TERMINÓ · \(Tiempo.reloj(duracion))")
                    .font(.system(size: 9, weight: .semibold, design: .monospaced)).tracking(1.1)
                    .foregroundStyle(necesita ? Color.claude : Color.green)
                Text(sesion.nombre).font(.system(size: 13, weight: .semibold)).foregroundStyle(.white).lineLimit(1)
                if !detalle.isEmpty {
                    Text(detalle).font(.system(size: 11)).foregroundStyle(.white.opacity(0.55)).lineLimit(1)
                }
            }
            Spacer(minLength: 6)
            Button(action: abrir) {
                Text(necesita ? "Responder" : "Ver")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(necesita ? .white : .black)
                    .padding(.horizontal, 14)
                    .frame(height: 28)
                    .background(Capsule().fill(necesita ? Color.claude : .white))
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
        }
    }
}

/// Reunión en 5 minutos: cuenta regresiva grande y botón verde redondo para unirse (como una llamada).
private struct EventoIsla: View {
    let estado: EstadoIsla
    let titulo: String
    let inicio: Date
    let color: Color
    let enlace: URL?
    let unirse: (URL) -> Void

    var body: some View {
        Fila(notch: estado.notch) {
            Capsule().fill(color).frame(width: 4, height: 34)
            VStack(alignment: .leading, spacing: 1) {
                Text(enlace == nil ? "REUNIÓN" : "VIDEOLLAMADA")
                    .font(.system(size: 9, weight: .semibold, design: .monospaced)).tracking(1.2)
                    .foregroundStyle(color)
                Text(titulo).font(.system(size: 13, weight: .semibold)).foregroundStyle(.white).lineLimit(1)
            }
            Spacer(minLength: 6)
            TimelineView(.periodic(from: .now, by: 1)) { ctx in
                Text(Tiempo.cuentaRegresiva(hasta: inicio, desde: ctx.date))
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(color)
                    .contentTransition(.numericText(countsDown: true))
            }
            if let enlace {
                BotonUnirse(redondo: true) { unirse(enlace) }.modifier(Entrada())
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
            IconoSaltarin(simbolo: "bolt.fill", color: .green).frame(width: 70)
            Spacer(minLength: estado.notch.width)
            HStack(spacing: 6) {
                Text("\(porcentaje)%").font(.system(size: 12, weight: .semibold, design: .rounded)).foregroundStyle(.green)
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3.5).strokeBorder(.white.opacity(0.35), lineWidth: 1)
                    RoundedRectangle(cornerRadius: 2).fill(.green).frame(width: 19 * lleno).padding(2)
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

/// Unirse a la videollamada: píldora verde o círculo (como contestar una llamada).
private struct BotonUnirse: View {
    var redondo = false
    let accion: () -> Void

    var body: some View {
        Button(action: accion) {
            Group {
                if redondo {
                    Image(systemName: "video.fill").font(.system(size: 14, weight: .semibold)).frame(width: 38, height: 38)
                } else {
                    Image(systemName: "video.fill").font(.system(size: 11, weight: .semibold)).frame(width: 28, height: 28)
                }
            }
            .foregroundStyle(.white)
            .background(Circle().fill(PuntoPrivacidad.color(camara: true)))
            .contentShape(Circle())
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
                    Text("AHORA SUENA")
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .tracking(1.3)
                        .foregroundStyle(.white.opacity(0.55))
                    Text(musica.titulo).font(.system(size: 14, weight: .semibold)).foregroundStyle(.white).lineLimit(1)
                    Text(musica.artista).font(.system(size: 12)).foregroundStyle(.white.opacity(0.6)).lineLimit(1)
                }
                Spacer(minLength: 8)
                Ecualizador(color: musica.acento, activo: musica.sonando)
            }
            .padding(.horizontal, 22)
            .frame(maxHeight: .infinity)
        }
        .background { FondoArte(imagen: musica.caratula, forma: FormaIsla(radio: 24)) }
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
    enum Pestana { case claude, agenda, mac }

    let estado: EstadoIsla
    let musica: Musica
    let agenda: Agenda
    let privacidad: Privacidad
    let claude: SesionesClaude
    let salud: EstadoSalud
    let unirse: (URL) -> Void
    let abrirSalud: () -> Void
    let medirSalud: () -> Void
    @State private var pestana: Pestana?

    /// Sin elegir: lo que más importa ahora (Claude esperándote, el Mac en rojo, Claude trabajando, la agenda).
    private var porDefecto: Pestana {
        if !claude.esperando.isEmpty { return .claude }
        if salud.diagnostico.gravedad == .mal { return .mac }
        if claude.hayActividad { return .claude }
        return agenda.eventos.isEmpty ? .mac : .agenda
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
        let actual = pestana ?? porDefecto
        VStack(spacing: 0) {
            HStack {  // el notch físico; a la derecha, quién usa la cámara o el micrófono
                Spacer()
                if privacidad.activo {
                    Button { privacidad.irALaApp() } label: {
                        HStack(spacing: 6) {
                            Text(etiquetaLlamada)
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(.white.opacity(0.6))
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
                    .frame(width: 262, alignment: .leading)
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 4) {
                        Pildora(titulo: "Claude", cuenta: claude.sesiones.count, activa: actual == .claude) {
                            pestana = .claude
                            claude.actualizarUso()
                        }
                        Pildora(titulo: "Agenda", cuenta: agenda.eventos.count, activa: actual == .agenda) { pestana = .agenda }
                        Pildora(titulo: "Mac", cuenta: 0, punto: salud.diagnostico.gravedad.color, activa: actual == .mac) {
                            pestana = .mac
                            medirSalud()
                        }
                        Spacer(minLength: 4)
                        if actual == .claude && claude.tokensHoy > 0 {
                            ActividadDia(porHora: claude.porHora)
                                .help("Hoy: \(claude.respuestasHoy) respuestas y \(Tiempo.tokens(claude.tokensHoy)) tokens escritos entre todas las sesiones")
                        }
                    }
                    switch actual {
                    case .claude: ListaClaude(claude: claude)
                    case .agenda: ListaAgenda(agenda: agenda, unirse: unirse)
                    case .mac: ResumenMac(salud: salud, abrir: abrirSalud)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 28)
            .padding(.top, 10)
            .padding(.bottom, 18)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background { FondoArte(imagen: musica.hayPista ? musica.caratula : nil, forma: FormaIsla(radio: 34), alcance: 0.6) }
        .onAppear {
            claude.actualizarUso()
            claude.vigilarActividad(true)
            if (pestana ?? porDefecto) == .mac { medirSalud() }
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
                    .fill(h == ahora ? Color.claude : .white.opacity(0.32))
                    .frame(width: 2.5, height: max(2.5, 14 * CGFloat(porHora[h]) / CGFloat(maximo)))
            }
        }
        .frame(height: 14, alignment: .bottom)

    }
}

/// Lo más importante de Salud del Mac en la isla: semáforo con la causa, cuatro anillos y lo que más consume.
/// El título y el ícono abren el panel completo (limpieza incluida).
private struct ResumenMac: View {
    let salud: EstadoSalud
    let abrir: () -> Void

    var body: some View {
        let d = salud.diagnostico
        VStack(alignment: .leading, spacing: 10) {
            Button(action: abrir) {
                HStack(spacing: 8) {
                    Circle().fill(d.gravedad.color).frame(width: 8, height: 8).shadow(color: d.gravedad.color, radius: 4)
                    Text(d.titulo).font(.system(size: 12.5, weight: .semibold)).foregroundStyle(.white).lineLimit(1)
                    Spacer(minLength: 4)
                    Image(systemName: "arrow.up.forward.app")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.white.opacity(0.65))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Abrir Salud del Mac (detalle y limpieza)")
            HStack(spacing: 0) {
                MiniAnillo(valor: salud.cpu, gravedad: salud.gravedadCPU, texto: Medida.porcentaje(salud.cpu), titulo: "Procesador")
                MiniAnillo(valor: salud.memoriaUsada / salud.memoriaTotal, gravedad: salud.gravedadMemoria,
                           texto: String(format: "%.0f/%.0f", salud.memoriaUsada / 1e9, salud.memoriaTotal / 1.073741824e9), titulo: "Memoria")
                MiniAnillo(valor: salud.gpu, gravedad: salud.gravedadGPU, texto: Medida.porcentaje(salud.gpu), titulo: "Gráficos")
                MiniAnillo(valor: 1 - salud.discoLibre / max(1, salud.discoTotal), gravedad: salud.gravedadDisco,
                           texto: String(format: "%.0f GB", salud.discoLibre / 1e9), titulo: "Disco libre")
            }
            if let top = salud.consumidores.max(by: { $0.memoria < $1.memoria }) {
                Text("Lo que más consume: \(top.nombre) · \(Medida.bytes(top.memoria))")
                    .font(.system(size: 10.5)).foregroundStyle(.white.opacity(0.5)).lineLimit(1)
            }
        }
    }
}

private struct MiniAnillo: View {
    let valor: Double
    let gravedad: Gravedad
    let texto: String
    let titulo: String

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                Circle().stroke(.white.opacity(0.12), lineWidth: 3.5)
                Circle().trim(from: 0, to: max(0.02, min(1, valor)))
                    .stroke(gravedad.color, style: StrokeStyle(lineWidth: 3.5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text(texto).font(.system(size: 8.5, weight: .semibold, design: .rounded)).monospacedDigit()
                    .foregroundStyle(.white).minimumScaleFactor(0.7).lineLimit(1).padding(.horizontal, 4)
            }
            .frame(width: 38, height: 38)
            Text(titulo).font(.system(size: 9)).foregroundStyle(.white.opacity(0.45)).lineLimit(1)
        }
        .frame(maxWidth: .infinity)
    }
}

/// Pestaña en píldora: activa en blanco translúcido, con cuántos elementos tiene.
private struct Pildora: View {
    let titulo: String
    let cuenta: Int
    var punto: Color?
    let activa: Bool
    let accion: () -> Void

    var body: some View {
        Button(action: accion) {
            HStack(spacing: 5) {
                if let punto { Circle().fill(punto).frame(width: 6, height: 6) }
                Text(titulo).font(.system(size: 11, weight: .semibold))
                if cuenta > 0 {
                    Text("\(cuenta)").font(.system(size: 10, weight: .bold, design: .rounded)).foregroundStyle(.white.opacity(0.5))
                }
            }
            .foregroundStyle(.white.opacity(activa ? 1 : 0.5))
            .fixedSize()
            .padding(.horizontal, 10)
            .frame(height: 22)
            .background(Capsule().fill(.white.opacity(activa ? 0.16 : 0)))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

/// Sesiones de Claude: qué hace cada una, cuánto contexto lleva y el total de hoy.
private struct ListaClaude: View {
    let claude: SesionesClaude

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            if claude.sesiones.isEmpty {
                Text("Sin sesiones abiertas").font(.system(size: 13)).foregroundStyle(.white.opacity(0.6))
            }
            ForEach(claude.sesiones.prefix(3)) { s in
                Button { SesionesClaude.abrir(s) } label: {
                    HStack(spacing: 10) {
                        EstadoSesion(estado: s.estado).frame(width: 16, height: 16)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(s.nombre).font(.system(size: 12.5, weight: .medium)).foregroundStyle(.white).lineLimit(1)
                            Text(Tiempo.sesion(s))
                                .font(.system(size: 10.5))
                                .foregroundStyle(s.estado == .esperando ? Color.claude : .white.opacity(0.45))
                                .lineLimit(1)
                        }
                        Spacer(minLength: 4)
                        if s.contexto > 0 {
                            Text(Tiempo.tokens(s.contexto))
                                .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                                .foregroundStyle(.white.opacity(s.contexto > 600_000 ? 0.75 : 0.3))
                                .help("Contexto de esta conversación. Si pasa de ~600 k conviene abrir una nueva.")
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }
}

/// Ícono del estado de una sesión: estrella que gira (trabaja), punto que late (te espera), check (lista).
private struct EstadoSesion: View {
    let estado: SesionesClaude.Estado
    @State private var giro = false

    var body: some View {
        switch estado {
        case .trabajando:
            EstrellaClaude().fill(Color.claude)
                .rotationEffect(.degrees(giro ? 360 : 0))
                .onAppear { withAnimation(.linear(duration: 6).repeatForever(autoreverses: false)) { giro = true } }
        case .esperando:
            Circle().fill(Color.claude).frame(width: 8, height: 8)
                .shadow(color: Color.claude, radius: 5)
                .symbolEffect(.pulse, isActive: true)
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
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 12) {
                    Caratula(imagen: musica.caratula, lado: 58, radio: 13, resplandor: true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(musica.titulo).font(.system(size: 14, weight: .semibold)).foregroundStyle(.white).lineLimit(1)
                        Text(musica.artista).font(.system(size: 12)).foregroundStyle(.white.opacity(0.6)).lineLimit(1)
                    }
                    Spacer(minLength: 4)
                    Ecualizador(color: musica.acento, activo: musica.sonando)
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
                Text("Nada sonando todavía").font(.system(size: 13)).foregroundStyle(.white.opacity(0.7))
                HStack(spacing: 8) {
                    Button { musica.alternar() } label: {
                        Label("Reanudar", systemImage: "play.fill")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.black)
                            .padding(.horizontal, 12)
                            .frame(height: 28)
                            .background(Capsule().fill(.white))
                    }
                    .buttonStyle(.plain)
                    Button { musica.abrirSpotify() } label: {
                        Text("Abrir Spotify")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 12)
                            .frame(height: 28)
                            .background(Capsule().fill(.white.opacity(0.14)))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

/// Barra de progreso; solo se redibuja (1 vez por segundo) mientras la isla está abierta.
private struct Progreso: View {
    let musica: Musica

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { ctx in
            let pos = musica.posicion(en: ctx.date)
            let fraccion = musica.duracion > 0 ? pos / musica.duracion : 0
            HStack(spacing: 8) {
                Text(Tiempo.reloj(pos))
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.white.opacity(0.18))
                        Capsule().fill(.white).frame(width: geo.size.width * fraccion)
                    }
                }
                .frame(height: 4)
                Text("-" + Tiempo.reloj(max(0, musica.duracion - pos)))
            }
            .font(.system(size: 10, weight: .medium, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(.white.opacity(0.5))
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

private struct ListaAgenda: View {
    let agenda: Agenda
    let unirse: (URL) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            if !agenda.permitido {
                Text("Permite el acceso al Calendario en Ajustes → Privacidad y seguridad → Calendarios.")
                    .font(.system(size: 12)).foregroundStyle(.white.opacity(0.6))
            } else if agenda.eventos.isEmpty {
                Text("Sin eventos en las próximas horas").font(.system(size: 13)).foregroundStyle(.white.opacity(0.6))
            } else {
                ForEach(agenda.eventos.prefix(3)) { e in
                    HStack(alignment: .center, spacing: 10) {
                        Capsule().fill(e.color).frame(width: 3, height: 28)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(e.titulo).font(.system(size: 12.5, weight: .medium)).foregroundStyle(.white).lineLimit(1)
                            Text(Tiempo.franja(e)).font(.system(size: 10.5)).foregroundStyle(.white.opacity(0.5)).lineLimit(1)
                        }
                        Spacer(minLength: 6)
                        if e.sePuedeUnir, let enlace = e.enlace {
                            BotonUnirse { unirse(enlace) }
                        }
                    }
                }
            }
        }
    }
}

private struct EtiquetaIsla: View {
    let titulo: String

    var body: some View {
        Text(titulo.uppercased())
            .font(.system(size: 10, weight: .medium, design: .monospaced))
            .tracking(1.3)
            .foregroundStyle(.white.opacity(0.42))
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

    /// "hace 3 min", "hace 2 h".
    static func hace(_ fecha: Date) -> String {
        let s = Int(-fecha.timeIntervalSinceNow)
        if s < 60 { return "ahora" }
        if s < 3600 { return "hace \(s / 60) min" }
        return "hace \(s / 3600) h"
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

    /// "2:04 – 2:49 p. m." (formato colombiano de 12 horas).
    static func franja(_ e: Agenda.Evento) -> String {
        let formato = DateFormatter()
        formato.locale = Locale(identifier: "es_CO")
        formato.dateFormat = "h:mm"
        let inicio = formato.string(from: e.inicio)
        formato.dateFormat = "h:mm a"
        let fin = formato.string(from: e.fin)
        let dia = Calendar.current.isDateInToday(e.inicio) ? "" : "Mañana · "
        let ahora = Date()
        let estado = e.inicio <= ahora ? " · en curso" : (e.inicio.timeIntervalSince(ahora) < 3600 ? " · \(faltan(e.inicio))" : "")
        return dia + inicio + " – " + fin + estado
    }
}
