import AppKit
import SwiftUI
import Translation

/// Panel de acciones sobre el texto seleccionado (Hyper+T) en Halo: extracto del texto, seis acciones (la elegida
/// en blanco sólido) y, debajo, el resultado en una tarjeta con la luz del tono de la acción, Reemplazar (el botón
/// principal) y Copiar. Crece hacia abajo según lo que muestre.
struct VistaAcciones: View {
    static let ancho: CGFloat = 460

    let estado: EstadoAcciones
    let control: AccionesTexto?
    var simulado = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            cabecera
            Text(estado.texto)
                .font(.system(size: 13))
                .foregroundStyle(Halo.texto2)
                .lineSpacing(1.5)
                .lineLimit(3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .tarjetaHalo(radio: Halo.radioTarjeta)
            Grid(horizontalSpacing: 8, verticalSpacing: 8) {
                ForEach([Array(AccionTexto.allCases.prefix(3)), Array(AccionTexto.allCases.suffix(3))], id: \.first) { fila in
                    GridRow {
                        ForEach(fila) { accion in
                            BotonAccion(accion: accion, activa: estado.accion == accion) { control?.ejecutar(accion) }
                        }
                    }
                }
            }
            .animation(Halo.cambio, value: estado.accion)
            resultado
            Rotulo(estado.resultado == nil ? "1–6 elige · esc cierra" : "1–6 elige · ↩ reemplaza · ⌘C copia · esc cierra",
                   color: Halo.texto3)
                .frame(maxWidth: .infinity)
        }
        .padding(16)
        .frame(width: Self.ancho)
        .modifier(PanelVidrio(radio: Halo.radioPanel, simulado: simulado))
        .fixedSize(horizontal: false, vertical: true)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { control?.ajustarAlto($0) }
        .modifier(TareaTraduccion(estado: estado, control: control, activa: !simulado))
    }

    private var cabecera: some View {
        HStack(spacing: 8) {
            EtiquetaSeccion(titulo: "Texto seleccionado")
            Spacer(minLength: 8)
            if !estado.app.isEmpty { Chip(texto: estado.app, icono: estado.icono) }
            BotonCirculo(simbolo: "xmark", lado: 28, ayuda: "Cerrar (Esc)") { control?.cerrar() }
        }
    }

    @ViewBuilder private var resultado: some View {
        let tono = estado.accion?.tono ?? .violeta
        if estado.cargando {
            HStack(spacing: 8) {
                if !simulado { ProgressView().controlSize(.small) }  // ImageRenderer no dibuja vistas de AppKit
                Text(estado.accion == .traducir ? "Traduciendo en el Mac…" : "Pensando en el Mac…")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Halo.texto2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .tarjetaHalo(radio: 20)
            .modifier(Aparece())
        } else if let aviso = estado.aviso {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 12) {
                    Insignia(icono: .simbolo(estado.faltanIdiomas ? "arrow.down" : "exclamationmark"), tono: .ambar, lado: 24)
                    Text(aviso).font(.system(size: 13)).foregroundStyle(Halo.texto)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 4)
                }
                if estado.faltanIdiomas {
                    HStack(spacing: 8) {
                        BotonHalo(titulo: "Descargar", icono: "arrow.down", alto: 32) { control?.descargarIdiomas() }
                        BotonHalo(titulo: "Abrir Ajustes", icono: "gearshape", secundario: true, alto: 32) { control?.abrirAjustesIdiomas() }
                    }
                    .padding(.leading, 36)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(LuzBorde(tono: .ambar, fuerza: 0.18, alto: 0.8, centro: 0.15, ancho: 0.6))
            .tarjetaHalo(radio: 20)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .modifier(Aparece())
        } else if let r = estado.resultado {
            VStack(alignment: .leading, spacing: 12) {
                Rotulo(estado.detalle, color: tono.claro)
                textoResultado(r)
                HStack(spacing: 8) {
                    BotonHalo(titulo: "Reemplazar", icono: "arrow.uturn.backward", teclas: "↩", alto: 32) { control?.reemplazar() }
                    BotonHalo(titulo: "Copiar", icono: "doc.on.doc", secundario: true, teclas: "⌘C", alto: 32) { control?.copiar() }
                }
                .padding(.top, 4)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            // la luz del tono de la acción sube por la derecha, frente a los botones
            .background(LuzBorde(tono: tono, fuerza: 0.22, alto: 0.9, centro: 0.8, ancho: 0.6))
            .tarjetaHalo(radio: 20, activa: true)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .modifier(Aparece())
        }
    }

    /// Los resultados largos se desplazan; los cortos (casi todos) se muestran enteros.
    @ViewBuilder private func textoResultado(_ r: String) -> some View {
        let texto = Text(r)
            .font(.system(size: 14))
            .foregroundStyle(Halo.texto)
            .lineSpacing(2)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
        if simulado || r.count < 500 {
            texto.fixedSize(horizontal: false, vertical: true)
        } else {
            ScrollView { texto }.frame(height: 220)
        }
    }
}

extension AccionTexto {
    /// El tono del resultado: azul traducir, verde corregir, violeta lo que reescribe la IA del Mac, el de Claude
    /// para Claude y ámbar para las ideas.
    var tono: Tono {
        switch self {
        case .traducir: return .azul
        case .corregir: return .verde
        case .resumir, .formal: return .violeta
        case .claude: return .claude
        case .idea: return .ambar
        }
    }
}

/// Lo que aparece debajo (resultado, aviso, cargando) entra con un fundido y sin desplazarse: el alto del panel ya
/// cambió (lo ajusta `ajustarAlto`) y solo se anima la opacidad, para no pelear con el marco de la ventana.
private struct Aparece: ViewModifier {
    @State private var visible = false

    func body(content: Content) -> some View {
        content
            .opacity(visible ? 1 : 0)
            .onAppear { withAnimation(Halo.fundido) { visible = true } }
    }
}

/// Píldora de acción que llena su columna; la última elegida queda en blanco sólido con letra negra.
private struct BotonAccion: View {
    let accion: AccionTexto
    let activa: Bool
    let alTocar: () -> Void

    var body: some View {
        Button(action: alTocar) {
            HStack(spacing: 8) {
                Image(systemName: accion.simbolo).font(.system(size: 12, weight: .semibold))
                Text(accion.titulo).font(.system(size: 12.5, weight: activa ? .semibold : .medium)).lineLimit(1)
                Text("\(accion.rawValue)").font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(activa ? Color.black.opacity(0.35) : Halo.texto3)
            }
            .foregroundStyle(activa ? Color.black : Halo.texto)
            .frame(maxWidth: .infinity)
            .frame(height: 36)
            .background {
                if activa {
                    Capsule().fill(LinearGradient(colors: [.white, Color(white: 0.86)], startPoint: .top, endPoint: .bottom))
                        .shadow(color: .white.opacity(0.18), radius: 8)
                } else {
                    Capsule().fill(.white.opacity(0.07)).overlay(Capsule().strokeBorder(.white.opacity(0.1), lineWidth: 1))
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(accion.ayuda)
    }
}

/// Solo `.translationTask` puede pedirle a macOS que descargue idiomas de traducción; se activa con el botón
/// Descargar (estado.traduccion deja de ser nil).
private struct TareaTraduccion: ViewModifier {
    let estado: EstadoAcciones
    let control: AccionesTexto?
    let activa: Bool

    func body(content: Content) -> some View {
        if activa {
            content.translationTask(estado.traduccion) { sesion in await control?.traducir(con: sesion) }
        } else {
            content
        }
    }
}

// MARK: - Render y pruebas sin abrir la app

/// Render del panel con un texto de ejemplo: su traducción y, al lado, el aviso de idiomas sin descargar.
/// `Dictado --vista-acciones salida.png`
@MainActor
func hojaAcciones(_ destino: URL) -> Bool {
    func estado(aviso: Bool) -> EstadoAcciones {
        let estado = EstadoAcciones()
        estado.texto = "Recordar revisar la propuesta comercial antes del viernes y confirmar la reunión con el equipo de diseño para cerrar los últimos detalles."
        estado.app = "Mail"
        estado.icono = Privacidad.mapaDeBits(NSWorkspace.shared.icon(forFile: "/System/Applications/Mail.app"))
        estado.accion = .traducir
        if aviso {
            estado.aviso = "Para traducir sin internet, macOS necesita descargar Español e Inglés (una sola vez)."
            estado.faltanIdiomas = true
        } else {
            estado.detalle = "Traducción · Español → Inglés"
            estado.resultado = "Remember to review the sales proposal before Friday and confirm the meeting with the design team to settle the final details."
        }
        return estado
    }
    let fondo = fondoDeMuestra()
    func lienzo(_ e: EstadoAcciones) -> some View {
        let vista = VistaAcciones(estado: e, control: nil, simulado: true)
        let tam = NSHostingView(rootView: vista).fittingSize
        return lienzoConVidrio(fondo, lienzo: CGSize(width: tam.width + 160, height: 640), panel: tam, radio: Halo.radioPanel) { vista }
    }
    let hoja = HStack(spacing: 0) { lienzo(estado(aviso: false)); lienzo(estado(aviso: true)) }
    let renderer = ImageRenderer(content: hoja)
    renderer.scale = 2
    guard let cg = renderer.cgImage,
          let png = NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:]) else { return false }
    return (try? png.write(to: destino)) != nil
}

/// Comprobaciones de los módulos de IA sin tocar tu portapapeles (usa portapapeles con nombre propio).
/// `Dictado --probar-acciones`
@MainActor
func probarAcciones() async -> Bool {
    var fallas = 0
    func revisar(_ nombre: String, _ condicion: Bool) {
        print(condicion ? "  ✓" : "  ✗", nombre)
        if !condicion { fallas += 1 }
    }

    // Foto del portapapeles: vuelve con todos sus tipos.
    let pb = NSPasteboard(name: NSPasteboard.Name("app.dictado.prueba.\(UUID().uuidString)"))
    pb.clearContents()
    let item = NSPasteboardItem()
    item.setString("Cláusula tercera", forType: .string)
    item.setString("<b>Cláusula</b> tercera", forType: .html)
    pb.writeObjects([item])
    let foto = FotoPortapapeles(pb)
    pb.clearContents()
    pb.setString("copia de paso", forType: .string)
    foto.restaurar(en: pb)
    revisar("el portapapeles vuelve como estaba (texto y HTML)",
            pb.string(forType: .string) == "Cláusula tercera" && pb.string(forType: .html) == "<b>Cláusula</b> tercera")

    // Historial en pausa: la copia de paso y la restauración no se guardan.
    let carpeta = FileManager.default.temporaryDirectory.appendingPathComponent("dictado-prueba-\(UUID().uuidString)")
    let pbh = NSPasteboard(name: NSPasteboard.Name("app.dictado.prueba.\(UUID().uuidString)"))
    let h = Historial(carpeta: carpeta, pasteboard: pbh)
    func copiar(_ s: String) {
        pbh.clearContents()
        pbh.setString(s, forType: .string)
        h.revisar(app: nil)
    }
    copiar("Lo que había antes")
    h.pausar(true)
    copiar("Selección copiada de paso")
    copiar("Lo que había antes")
    h.pausar(false)
    h.revisar(app: nil)
    revisar("en pausa el historial no captura", h.recortes.count == 1)
    copiar("Copia normal después de la pausa")
    revisar("al reanudar vuelve a capturar", h.recortes.count == 2)
    try? FileManager.default.removeItem(at: carpeta)
    pb.releaseGlobally()
    pbh.releaseGlobally()

    // Tabla de modos.
    revisar("Mail → correo", TablaModos.modo(app: "com.apple.mail", titulo: nil) == .correo)
    revisar("WhatsApp → chat", TablaModos.modo(app: "net.whatsapp.WhatsApp", titulo: nil) == .chat)
    revisar("Terminal → prompt", TablaModos.modo(app: "com.apple.Terminal", titulo: nil) == .prompt)
    revisar("JetBrains (prefijo) → prompt", TablaModos.modo(app: "com.jetbrains.intellij", titulo: nil) == .prompt)
    revisar("Pages → documento", TablaModos.modo(app: "com.apple.iWork.Pages", titulo: nil) == .documento)
    revisar("Chrome con Gmail → correo", TablaModos.modo(app: "com.google.Chrome", titulo: "Recibidos (3) - Gmail") == .correo)
    revisar("Arc con Claude → prompt", TablaModos.modo(app: "company.thebrowser.Browser", titulo: "Nuevo chat - Claude") == .prompt)
    revisar("Safari con Google Docs → documento", TablaModos.modo(app: "com.apple.Safari", titulo: "Informe - Google Docs") == .documento)
    revisar("navegador en otra página → neutro", TablaModos.modo(app: "com.google.Chrome", titulo: "Noticias") == .neutro)
    revisar("Finder → neutro", TablaModos.modo(app: "com.apple.finder", titulo: nil) == .neutro)

    // Salvaguardas del pulido.
    revisar("descarta si agrega contenido", PulidoIA.descartar(
        original: "nos vemos mañana a las tres en la oficina",
        pulido: "Nos vemos mañana a las tres en la oficina. Recuerda traer los documentos firmados y el informe del trimestre completo.",
        vocabulario: []) != nil)
    revisar("descarta si pierde un término del vocabulario", PulidoIA.descartar(
        original: "eh mándale el informe a Xavier por slack", pulido: "Mándale el informe por Slack.", vocabulario: ["Xavier"]) != nil)
    revisar("acepta una limpieza normal", PulidoIA.descartar(
        original: "eh bueno o sea mándale el informe a Xavier por slack", pulido: "Mándale el informe a Xavier por Slack.",
        vocabulario: ["Xavier", "Slack"]) == nil)
    revisar("limpia etiquetas y comillas", IALocal.limpiar("<texto>\n«Hola, ¿qué tal?»\n</texto>") == "Hola, ¿qué tal?")

    // Idioma de la traducción.
    let es = AccionesTexto.idiomas(de: "Nos vemos mañana en la oficina para revisar el contrato.")
    revisar("español → inglés", es.origen.languageCode == .spanish && es.destino.languageCode == .english)
    let en = AccionesTexto.idiomas(de: "See you tomorrow at the office to review the contract.")
    revisar("inglés → español", en.origen.languageCode == .english && en.destino.languageCode == .spanish)

    // Enlace a Claude.
    let enlace = AccionesTexto.enlaceClaude("¿Qué opinas? Sí & no")?.absoluteString ?? ""
    revisar("enlace a Claude con el texto codificado",
            enlace == "claude://claude.ai/new?q=%C2%BFQu%C3%A9%20opinas%3F%20S%C3%AD%20%26%20no&surface=chat")
    revisar("texto que empieza por / va copiado", AccionesTexto.enlaceClaude("/compact") == nil)
    revisar("texto larguísimo va copiado", AccionesTexto.enlaceClaude(String(repeating: "a", count: 15_000)) == nil)

    // Tiempo límite: el trabajo lento se abandona sin esperarlo.
    let t0 = Date()
    let lento = try? await IALocal.conLimite(0.2) { () async throws -> String in
        try await Task.sleep(for: .seconds(3))
        return "tarde"
    }
    revisar("el tiempo límite corta a tiempo", lento == nil && Date().timeIntervalSince(t0) < 1)

    print(fallas == 0 ? "todo bien" : "\(fallas) fallas")
    return fallas == 0
}
