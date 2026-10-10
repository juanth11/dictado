import AppKit
import SwiftUI
import Translation

/// Panel de acciones sobre el texto seleccionado (Hyper+T), en vidrio claro: extracto del texto, seis acciones
/// y, debajo, el resultado con Reemplazar y Copiar. Crece hacia abajo según lo que muestre.
struct VistaAcciones: View {
    static let ancho: CGFloat = 460

    let estado: EstadoAcciones
    let control: AccionesTexto?
    var simulado = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            cabecera
            Text(estado.texto)
                .font(.system(size: 13))
                .foregroundStyle(Diseno.tinta.opacity(0.78))
                .lineLimit(3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.white.opacity(0.42)))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.white.opacity(0.6), lineWidth: 0.6))
            Grid(horizontalSpacing: 8, verticalSpacing: 8) {
                ForEach([Array(AccionTexto.allCases.prefix(3)), Array(AccionTexto.allCases.suffix(3))], id: \.first) { fila in
                    GridRow {
                        ForEach(fila) { accion in
                            BotonAccion(accion: accion, activa: estado.accion == accion) { control?.ejecutar(accion) }
                        }
                    }
                }
            }
            resultado
            Text(estado.resultado == nil ? "1–6 elige · Esc cierra" : "1–6 elige · ↩ reemplaza · ⌘C copia · Esc cierra")
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(Diseno.tintaTenue)
                .frame(maxWidth: .infinity)
        }
        .padding(18)
        .frame(width: Self.ancho)
        .modifier(PanelVidrio(radio: 26, simulado: simulado))
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
        if estado.cargando {
            HStack(spacing: 10) {
                if !simulado { ProgressView().controlSize(.small) }  // ImageRenderer no dibuja vistas de AppKit
                Text(estado.accion == .traducir ? "Traduciendo en el Mac…" : "Pensando en el Mac…")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Diseno.tintaSuave)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(tarjeta(0.32))
        } else if let aviso = estado.aviso {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: estado.faltanIdiomas ? "arrow.down.circle" : "exclamationmark.circle")
                        .font(.system(size: 13, weight: .semibold))
                    Text(aviso).font(.system(size: 13)).fixedSize(horizontal: false, vertical: true)
                }
                .foregroundStyle(Diseno.tinta.opacity(0.8))
                if estado.faltanIdiomas {
                    HStack(spacing: 8) {
                        BotonPildora(titulo: "Descargar", simbolo: "arrow.down", primario: true) { control?.descargarIdiomas() }
                        BotonPildora(titulo: "Abrir Ajustes", simbolo: "gearshape") { control?.abrirAjustesIdiomas() }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(tarjeta(0.32))
        } else if let r = estado.resultado {
            VStack(alignment: .leading, spacing: 10) {
                EtiquetaSeccion(titulo: estado.detalle)
                textoResultado(r)
                HStack(spacing: 8) {
                    BotonPildora(titulo: "Reemplazar", teclas: "↩", simbolo: "arrow.uturn.backward", primario: true) { control?.reemplazar() }
                    BotonPildora(titulo: "Copiar", teclas: "⌘C", simbolo: "doc.on.doc") { control?.copiar() }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(tarjeta(0.55))
        }
    }

    /// Los resultados largos se desplazan; los cortos (casi todos) se muestran enteros.
    @ViewBuilder private func textoResultado(_ r: String) -> some View {
        let texto = Text(r)
            .font(.system(size: 14))
            .foregroundStyle(Diseno.tinta)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
        if simulado || r.count < 500 {
            texto.fixedSize(horizontal: false, vertical: true)
        } else {
            ScrollView { texto }.frame(height: 220)
        }
    }

    private func tarjeta(_ opacidad: Double) -> some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(Color.white.opacity(opacidad))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Color.white.opacity(0.65), lineWidth: 0.6))
    }
}

/// Píldora de acción que llena su columna; la última elegida queda en blanco sólido.
private struct BotonAccion: View {
    let accion: AccionTexto
    let activa: Bool
    let alTocar: () -> Void

    var body: some View {
        Button(action: alTocar) {
            HStack(spacing: 7) {
                Image(systemName: accion.simbolo).font(.system(size: 12, weight: .semibold))
                Text(accion.titulo).font(.system(size: 12.5, weight: .medium)).lineLimit(1)
                Text("\(accion.rawValue)").font(.system(size: 10, weight: .medium, design: .rounded)).foregroundStyle(Diseno.tintaTenue)
            }
            .foregroundStyle(Diseno.tinta)
            .frame(maxWidth: .infinity)
            .frame(height: 36)
            .background(Capsule().fill(activa ? Color.white : Diseno.vidrio))
            .overlay(Capsule().strokeBorder(Diseno.borde, lineWidth: 0.8))
            .shadow(color: activa ? Diseno.sombra : .clear, radius: 8, y: 3)
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

/// Render del panel con un texto de ejemplo y su traducción. `Dictado --vista-acciones salida.png`
@MainActor
func hojaAcciones(_ destino: URL) -> Bool {
    let estado = EstadoAcciones()
    estado.texto = "Recordar revisar la propuesta comercial antes del viernes y confirmar la reunión con el equipo de diseño para cerrar los últimos detalles."
    estado.app = "Mail"
    estado.icono = Privacidad.mapaDeBits(NSWorkspace.shared.icon(forFile: "/System/Applications/Mail.app"))
    estado.accion = .traducir
    estado.detalle = "Traducción · Español → Inglés"
    estado.resultado = "Remember to review the sales proposal before Friday and confirm the meeting with the design team to settle the final details."
    let vista = VistaAcciones(estado: estado, control: nil, simulado: true)
    let tam = NSHostingView(rootView: vista).fittingSize
    let lienzo = CGSize(width: tam.width + 260, height: tam.height + 180)
    let hoja = lienzoConVidrio(fondoDeMuestra(), lienzo: lienzo, panel: tam, radio: 26) { vista }
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
