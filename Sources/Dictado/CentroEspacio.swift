import AppKit
import ImageIO
import SwiftUI

// El centro de mando como un espacio, al estilo visionOS. Al abrirlo, tu fondo de pantalla ocupa la pantalla (las
// demás ventanas quedan detrás) y encima flotan tres ventanas de vidrio en curva que miran hacia ti, la del centro
// de frente. Alrededor van los ornamentos: las pestañas a la izquierda, el estado arriba y, bajo la ventana del
// centro, lo que acompaña a cada sección. La ventana lateral que apuntas se pone de frente para leerla y tocarla; con
// "Reducir movimiento" todas quedan de frente desde el principio.

// (Claves a mano: sin Xcode no está el plugin de la macro @Entry.)
private struct ClaveVidrioSimulado: EnvironmentKey { static let defaultValue = false }
private struct ClaveMedidasEspacio: EnvironmentKey { static let defaultValue = MedidasEspacio() }
private struct ClavePestanasEspacio: EnvironmentKey { static let defaultValue: AnyView? = nil }

extension EnvironmentValues {
    /// Los renders no componen el vidrio real (lo pone el sistema): se simula.
    var vidrioSimulado: Bool {
        get { self[ClaveVidrioSimulado.self] }
        set { self[ClaveVidrioSimulado.self] = newValue }
    }
    var medidasEspacio: MedidasEspacio {
        get { self[ClaveMedidasEspacio.self] }
        set { self[ClaveMedidasEspacio.self] = newValue }
    }
    /// Las pestañas viven en el hueco izquierdo de cada escena (así se alinean con sus ventanas).
    var pestanasEspacio: AnyView? {
        get { self[ClavePestanasEspacio.self] }
        set { self[ClavePestanasEspacio.self] = newValue }
    }
}

// MARK: - Medidas

/// Cuánto mide cada pieza según la pantalla: las ventanas crecen con el ancho hasta un tope y, si la pantalla es más
/// chica que el mínimo, se escala todo el espacio.
struct MedidasEspacio {
    static let margen: CGFloat = 30
    static let pestanas: CGFloat = 60
    static let separacion: CGFloat = 22
    static let barra: CGFloat = 44
    static let ornamento: CGFloat = 74
    static let aire: CGFloat = 18
    static let minimo = CGSize(width: 1370, height: 780)

    var escala: CGFloat = 1
    var lienzo = CGSize(width: 1600, height: 1000)
    var lateral: CGFloat = 400
    var central: CGFloat = 600
    var alto: CGFloat = 680

    init() {}

    init(_ disponible: CGSize) {
        escala = max(0.5, min(1, disponible.width / Self.minimo.width, disponible.height / Self.minimo.height))
        lienzo = CGSize(width: max(Self.minimo.width, disponible.width / escala), height: max(Self.minimo.height, disponible.height / escala))
        let util = lienzo.width - 2 * Self.margen - Self.pestanas - 3 * Self.separacion
        central = min(760, max(500, util * 0.42))
        lateral = min(440, max(340, (util - central) / 2))
        alto = min(650, max(560, lienzo.height - 2 * Self.margen - Self.barra - Self.ornamento - 2 * Self.aire))
    }
}

// MARK: - Raíz

/// El espacio completo: la barra de estado arriba y la escena de la sección (con las pestañas a su izquierda).
struct VistaCentro: View {
    let estado: EstadoCentro?
    let ctx: ContextoCentro
    @Binding var seccion: SeccionCentro

    var body: some View {
        GeometryReader { g in
            let m = MedidasEspacio(g.size)
            VStack(spacing: MedidasEspacio.aire) {
                BarraEspacio(estado: estado, ctx: ctx).frame(height: MedidasEspacio.barra)
                EscenaCentro(estado: estado, ctx: ctx, seccion: $seccion)
            }
            .padding(MedidasEspacio.margen)
            .frame(width: m.lienzo.width, height: m.lienzo.height)
            .environment(\.medidasEspacio, m)
            .environment(\.pestanasEspacio, AnyView(PestanasEspacio(estado: estado, ctx: ctx, seccion: $seccion)))
            .scaleEffect(m.escala)
            .frame(width: g.size.width, height: g.size.height)
        }
    }
}

/// Lo que se ve detrás: tu fondo de pantalla (un poco oscurecido para leer encima) o, si no se puede leer, el
/// escritorio desenfocado. Con "Reducir transparencia", un fondo sólido.
struct FondoEspacio: View {
    let imagen: NSImage?
    @Environment(\.accessibilityReduceTransparency) private var sinTransparencia

    var body: some View {
        ZStack {
            if sinTransparencia {
                Color(white: 0.09)
            } else if let imagen {
                Image(nsImage: imagen).resizable().scaledToFill()
                    .frame(maxWidth: .infinity, maxHeight: .infinity).clipped()
                Color.black.opacity(0.14)
            } else {
                DesenfoqueEscritorio()
                Color.black.opacity(0.2)
            }
        }
        .ignoresSafeArea()
    }

    /// El fondo de pantalla de esa pantalla, reducido a su tamaño (un JPEG de 6K pesa cientos de MB sin reducir).
    static func deEscritorio(_ pantalla: NSScreen) -> NSImage? {
        guard let url = NSWorkspace.shared.desktopImageURL(for: pantalla),
              let fuente = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let lado = max(pantalla.frame.width, pantalla.frame.height) * pantalla.backingScaleFactor
        let opciones: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                         kCGImageSourceThumbnailMaxPixelSize: lado,
                                         kCGImageSourceCreateThumbnailWithTransform: true]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(fuente, 0, opciones as CFDictionary) else { return nil }
        return NSImage(cgImage: cg, size: .zero)
    }
}

private struct DesenfoqueEscritorio: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = .fullScreenUI
        v.blendingMode = .behindWindow
        v.state = .active
        return v
    }

    func updateNSView(_ v: NSVisualEffectView, context: Context) {}
}

// MARK: - Escena: tres ventanas en curva

enum LadoEspacio { case izquierda, derecha }

/// Pone las ventanas de una sección en el espacio: izquierda y derecha giradas hacia ti, la del centro de frente y,
/// debajo de ella, un ornamento opcional. Cada sección trae sus ventanas ya armadas (con `VentanaEspacio`).
struct EspacioCentro<I: View, C: View, D: View, B: View>: View {
    @ViewBuilder var izquierda: () -> I
    @ViewBuilder var centro: () -> C
    @ViewBuilder var derecha: () -> D
    @ViewBuilder var debajo: () -> B
    @Environment(\.medidasEspacio) private var m
    @Environment(\.pestanasEspacio) private var pestanas

    var body: some View {
        VStack(spacing: MedidasEspacio.aire) {
            HStack(spacing: MedidasEspacio.separacion) {
                // Las pestañas se abren hacia la derecha (encima de la ventana izquierda) sin mover nada.
                Color.clear.frame(width: MedidasEspacio.pestanas)
                    .overlay(alignment: .leading) { pestanas }
                    .zIndex(3)
                izquierda().frame(width: m.lateral, height: m.alto).modifier(Curva(lado: .izquierda))
                centro().frame(width: m.central, height: m.alto).zIndex(1)
                derecha().frame(width: m.lateral, height: m.alto).modifier(Curva(lado: .derecha))
            }
            ZStack {
                Color.clear
                debajo()
            }
            .frame(width: m.central + m.lateral, height: MedidasEspacio.ornamento)
            .offset(x: (MedidasEspacio.pestanas - MedidasEspacio.separacion) / 2)   // centrado bajo la ventana del centro
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

extension EspacioCentro where B == EmptyView {
    init(@ViewBuilder izquierda: @escaping () -> I, @ViewBuilder centro: @escaping () -> C, @ViewBuilder derecha: @escaping () -> D) {
        self.init(izquierda: izquierda, centro: centro, derecha: derecha, debajo: { EmptyView() })
    }
}

/// Una ventana lateral gira hacia ti desde su borde interior; la que apuntas se pone de frente (así se lee y se toca
/// sin perspectiva). Con "Reducir movimiento", de frente siempre.
private struct Curva: ViewModifier {
    let lado: LadoEspacio
    @Environment(\.accessibilityReduceMotion) private var sinMovimiento
    @State private var deFrente = false

    func body(content: Content) -> some View {
        let giro = sinMovimiento || deFrente ? 0.0 : (lado == .izquierda ? 13.0 : -13.0)
        content
            .rotation3DEffect(.degrees(giro), axis: (x: 0, y: 1, z: 0), anchor: lado == .izquierda ? .trailing : .leading,
                              perspective: 0.45)
            .onHover { h in
                withAnimation(sinMovimiento ? nil : .timingCurve(0.16, 1, 0.3, 1, duration: 0.55)) { deFrente = h }
            }
    }
}

/// Una ventana de vidrio del espacio. Si pide atención (`tono`), su borde se enciende de ese tono.
struct VentanaEspacio<C: View>: View {
    var tono: Tono?
    var relleno: CGFloat = 24
    @ViewBuilder let contenido: () -> C
    @Environment(\.vidrioSimulado) private var simulado

    var body: some View {
        let forma = RoundedRectangle(cornerRadius: 30, style: .continuous)
        contenido()
            .padding(relleno)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background {
                if let tono { LuzBorde(tono: tono, fuerza: 0.2, alto: 0.5, centro: 0.25, ancho: 0.9).clipShape(forma) }
            }
            .modifier(VidrioCentro(simulado: simulado, radio: 30))
            .shadow(color: .black.opacity(0.34), radius: 28, y: 16)
    }
}

/// El título de una ventana y, debajo, una línea que dice cómo va.
struct CabeceraVentana: View {
    let titulo: String
    var detalle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(titulo).font(.system(size: 21, weight: .semibold)).foregroundStyle(Halo.texto).lineLimit(1)
            if let detalle {
                Text(detalle).font(.system(size: 12.5)).foregroundStyle(TextoCentro.secundario).lineLimit(1)
            }
        }
    }
}

extension View {
    /// Un ornamento: vidrio flotante pegado a las ventanas (pestañas, barra de estado, lo de debajo).
    func ornamento(radio: CGFloat) -> some View { modifier(Ornamento(radio: radio)) }
}

private struct Ornamento: ViewModifier {
    let radio: CGFloat
    @Environment(\.vidrioSimulado) private var simulado

    func body(content: Content) -> some View {
        content
            .modifier(VidrioCentro(simulado: simulado, radio: radio))
            .shadow(color: .black.opacity(0.28), radius: 18, y: 10)
    }
}

// MARK: - Ornamentos

/// Arriba: dónde estás, cómo está la conexión, actualizar y cerrar.
private struct BarraEspacio: View {
    let estado: EstadoCentro?
    let ctx: ContextoCentro

    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(RadialGradient(colors: [.white.opacity(0.9), Tono.azul.base.opacity(0.4), .clear], center: .center,
                                                 startRadius: 0, endRadius: 15))
                    Circle().strokeBorder(.white.opacity(0.4), lineWidth: 0.75)
                }
                .frame(width: 28, height: 28)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Centro de mando").font(.system(size: 15, weight: .semibold)).foregroundStyle(Halo.texto)
                    Text(fecha).font(.system(size: 11.5)).foregroundStyle(TextoCentro.secundario)
                }
            }
            .shadow(color: .black.opacity(0.35), radius: 10)
            Spacer(minLength: 20)
            if let error = ctx.error, ctx.configurado {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 11)).foregroundStyle(Tono.ambar.claro)
                    Text(error).font(.system(size: 12)).foregroundStyle(Halo.texto).lineLimit(1)
                    BotonCentro(titulo: "Reintentar", icono: "arrow.clockwise", tipo: .enlace, accion: ctx.actualizar)
                }
                .padding(.horizontal, 16).frame(height: MedidasEspacio.barra)
                .ornamento(radio: MedidasEspacio.barra / 2)
            }
            HStack(spacing: 14) {
                conexion
                if !ctx.sesiones.isEmpty {
                    Rectangle().fill(Halo.linea).frame(width: 0.75, height: 18)
                    HStack(spacing: 7) {
                        PuntoBrillante(color: ctx.esperando.isEmpty ? Tono.claude.base.opacity(0.6) : Tono.claude.base, lado: 6)
                        Text(ctx.sesiones.count == 1 ? "1 sesión de Claude" : "\(ctx.sesiones.count) sesiones de Claude")
                            .font(.system(size: 12, weight: .medium)).foregroundStyle(TextoCentro.secundario)
                    }
                }
                BotonCentro(titulo: ctx.cargando ? "Actualizando…" : "Actualizar", icono: "arrow.clockwise", accion: ctx.actualizar)
                    .disabled(ctx.cargando)
            }
            .padding(.leading, 18).padding(.trailing, 8).frame(height: MedidasEspacio.barra)
            .ornamento(radio: MedidasEspacio.barra / 2)
            BotonRedondoCentro(icono: "xmark", ayuda: "Cerrar (esc)", accion: ctx.cerrar)
        }
    }

    private var fecha: String {
        if let b = estado?.brief, esHoy(b.fechaIso) { return "\(b.fecha) · semana \(b.semana)" }
        let f = DateFormatter()
        f.locale = Locale(identifier: "es_CO")
        f.dateFormat = "EEEE d 'de' MMMM"
        let t = f.string(from: Date())
        return t.prefix(1).uppercased() + t.dropFirst()
    }

    private var conexion: some View {
        let rotas = (estado?.salud?.capacidades ?? []).filter { $0.estado == "rota" || $0.estado == "alerta" }
        let sinVPS = estado?.vps == false || ctx.error != nil
        let color: Color = sinVPS ? Tono.rojo.base : (rotas.isEmpty ? Tono.verde.base : Tono.ambar.base)
        var texto = sinVPS ? "Sin conexión con el VPS" : (rotas.first.map { "\($0.nombre): \($0.estado)" } ?? "VPS bien")
        if let leido = ctx.leido { texto += " · leído \(hace(leido))" }
        return HStack(spacing: 7) {
            PuntoBrillante(color: color, lado: 6)
            Text(texto).font(.system(size: 12, weight: .medium)).foregroundStyle(TextoCentro.secundario).lineLimit(1)
        }
    }
}

/// Un botón redondo de vidrio (cerrar el espacio).
private struct BotonRedondoCentro: View {
    let icono: String
    let ayuda: String
    let accion: () -> Void
    @State private var encima = false

    var body: some View {
        Button(action: accion) {
            Image(systemName: icono).font(.system(size: 13, weight: .semibold)).foregroundStyle(Halo.texto)
                .frame(width: MedidasEspacio.barra, height: MedidasEspacio.barra)
                .background(Circle().fill(.white.opacity(encima ? 0.12 : 0)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(ayuda)
        .accessibilityLabel(ayuda)
        .onHover { encima = $0 }
        .ornamento(radio: MedidasEspacio.barra / 2)
    }
}

/// Las pestañas: un ornamento vertical con las secciones y, debajo, los módulos (abren afuera). Al pasar el puntero
/// se abre y muestra los nombres; un punto avisa lo que pide atención.
private struct PestanasEspacio: View {
    let estado: EstadoCentro?
    let ctx: ContextoCentro
    @Binding var seccion: SeccionCentro
    @Environment(\.accessibilityReduceMotion) private var sinMovimiento
    @State private var abiertas = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(SeccionCentro.allCases, id: \.self) { s in
                BotonPestana(icono: s.simbolo, titulo: s.titulo, activa: s == seccion, abiertas: abiertas,
                             cuenta: cuenta(s), aviso: s == .orquesta && cuenta(s) > 0) { seccion = s }
            }
            let modulos = estado?.modulos ?? []
            if !modulos.isEmpty {
                Rectangle().fill(Halo.linea).frame(width: abiertas ? 180 : 28, height: 0.75)
                    .padding(.vertical, 6).padding(.leading, 8)
                ForEach(modulos, id: \.nombre) { m in
                    BotonPestana(icono: m.icono, titulo: m.nombre, valor: m.valor, externo: m.abrir != nil, abiertas: abiertas,
                                 color: colorVertical(m.nombre)) { if let a = m.abrir { ctx.abrir(a) } }
                        .disabled(m.abrir == nil)
                }
            }
        }
        .padding(7)
        .fixedSize()
        .ornamento(radio: 29)
        .onHover { h in
            withAnimation(sinMovimiento ? nil : .timingCurve(0.16, 1, 0.3, 1, duration: 0.4)) { abiertas = h }
        }
    }

    private func cuenta(_ s: SeccionCentro) -> Int {
        switch s {
        case .orquesta: return (estado?.orquesta?.aprobaciones.count ?? 0) + ctx.esperando.count
        case .inbox: return estado?.inbox?.items.count ?? 0
        default: return 0
        }
    }
}

private struct BotonPestana: View {
    let icono: String?
    let titulo: String
    var valor = ""
    var externo = false
    var activa = false
    let abiertas: Bool
    var cuenta = 0
    /// Pide tu sí: punto del tono de Claude. Una cuenta sin urgencia (el inbox) lleva el número al abrirse.
    var aviso = false
    var color: Color?
    let accion: () -> Void
    @State private var encima = false

    var body: some View {
        Button(action: accion) {
            HStack(spacing: 8) {
                ZStack {
                    if let icono {
                        Image(systemName: icono).font(.system(size: 16, weight: .medium))
                    } else {
                        Circle().fill(color ?? .white).frame(width: 7, height: 7)
                    }
                }
                .frame(width: 44, height: 44)
                .overlay(alignment: .topTrailing) {
                    if !abiertas && (aviso || cuenta > 0) {
                        PuntoBrillante(color: aviso ? Tono.claude.base : .white.opacity(0.85), lado: 6).offset(x: -8, y: 9)
                    }
                }
                if abiertas {
                    Text(titulo).font(.system(size: 13.5, weight: activa ? .semibold : .medium)).lineLimit(1).fixedSize()
                    Spacer(minLength: 8)
                    if cuenta > 0 {
                        Text("\(cuenta)").font(.system(size: 11, weight: .semibold)).monospacedDigit()
                            .foregroundStyle(aviso ? Tono.claude.claro : TextoCentro.secundario)
                            .padding(.horizontal, 7).frame(height: 18).background(Capsule().fill(.white.opacity(0.1)))
                    }
                    if !valor.isEmpty {
                        Text(valor).font(.system(size: 11.5)).monospacedDigit().foregroundStyle(TextoCentro.terciario).fixedSize()
                    }
                    if externo { Image(systemName: "arrow.up.right").font(.system(size: 9, weight: .bold)).foregroundStyle(TextoCentro.terciario) }
                }
            }
            .padding(.trailing, abiertas ? 14 : 0)
            .frame(width: abiertas ? 214 : 44, height: 44, alignment: .leading)
            .foregroundStyle(activa || encima ? Halo.texto : TextoCentro.secundario)
            .background {
                if activa {
                    Capsule().fill(.white.opacity(0.17)).overlay(Capsule().strokeBorder(.white.opacity(0.16), lineWidth: 0.75))
                } else if encima {
                    Capsule().fill(.white.opacity(0.07))
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(titulo)
        .accessibilityLabel(cuenta > 0 ? "\(titulo), \(cuenta)" : titulo)
        .onHover { encima = $0 }
    }
}
