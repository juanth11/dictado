import AppKit
import SwiftUI

/// Pruebas del portapapeles sin tocar el tuyo: usa un portapapeles con nombre propio y una carpeta temporal.
/// `Dictado --probar-portapapeles`
@MainActor
func probarPortapapeles() -> Bool {
    let carpeta = FileManager.default.temporaryDirectory.appendingPathComponent("dictado-prueba-\(UUID().uuidString)")
    let pb = NSPasteboard(name: NSPasteboard.Name("app.dictado.prueba.\(UUID().uuidString)"))
    let h = Historial(carpeta: carpeta, pasteboard: pb)
    var fallas = 0
    func revisar(_ nombre: String, _ condicion: Bool) {
        print(condicion ? "  ✓" : "  ✗", nombre)
        if !condicion { fallas += 1 }
    }
    func copiar(_ escribir: () -> Void) {
        pb.clearContents()
        escribir()
        h.revisar(app: nil)
    }

    copiar { pb.setString("Revisar la propuesta antes del viernes", forType: .string) }
    revisar("captura texto", h.recortes.first?.tipo == .texto && h.recortes.count == 1)

    copiar { pb.setString("https://www.example.com/informe?id=12345", forType: .string) }
    revisar("detecta enlace", h.recortes.first?.tipo == .enlace)

    copiar { pb.setString("Revisar la propuesta antes del viernes", forType: .string) }
    revisar("repetido sube arriba sin duplicar", h.recortes.count == 2 && h.recortes.first?.tipo == .texto)

    copiar {
        let item = NSPasteboardItem()
        item.setString("clave-secreta-123", forType: .string)
        item.setString("", forType: NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType"))
        pb.writeObjects([item])
    }
    revisar("ignora contraseñas (ConcealedType)", h.recortes.count == 2)

    copiar {
        let item = NSPasteboardItem()
        item.setString("<b>Cláusula</b> tercera", forType: .html)
        item.setString("Cláusula tercera", forType: .string)
        pb.writeObjects([item])
    }
    revisar("guarda formato (HTML)", h.recortes.first?.conFormato == true)

    copiar { pb.writeObjects([NSURL(fileURLWithPath: "/tmp/Notas.md")]) }
    revisar("captura archivo", h.recortes.first?.tipo == .archivo && h.recortes.first?.titulo == "Notas.md")

    copiar {
        let img = NSImage(size: NSSize(width: 40, height: 20))
        img.lockFocus()
        NSColor.systemPink.setFill()
        NSRect(x: 0, y: 0, width: 40, height: 20).fill()
        img.unlockFocus()
        pb.writeObjects([img])
    }
    revisar("captura imagen", h.recortes.first?.tipo == .imagen && h.imagen(de: h.recortes[0]) != nil)

    let texto = h.recortes.first { $0.tipo == .texto && !$0.conFormato }!
    h.escribir(texto)
    h.revisar(app: nil)
    revisar("lo que escribe Dictado no se recaptura", h.recortes.count == 5 && h.recortes.first?.id == texto.id)
    revisar("al pegar queda en el portapapeles", pb.string(forType: .string) == texto.texto)

    h.alternarFijado(texto.id)
    let recargado = Historial(carpeta: carpeta, pasteboard: pb)
    revisar("persiste en disco (5 recortes, fijado)", recargado.recortes.count == 5 && recargado.recortes.contains { $0.fijado })
    let permisos = (try? FileManager.default.attributesOfItem(atPath: carpeta.appendingPathComponent("historial.json").path))?[.posixPermissions] as? Int
    revisar("archivo solo legible por ti (600)", permisos == 0o600)

    let estado = EstadoPanel()
    estado.busqueda = "propuesta"
    revisar("búsqueda sin tildes ni mayúsculas", Portapapeles.filtrar(h.recortes, estado).count == 1)
    estado.busqueda = ""
    estado.filtro = .fijados
    revisar("filtro fijados", Portapapeles.filtrar(h.recortes, estado).count == 1)

    // — Versión 2: varios a la vez, pegado limpio, arrastre y selección —
    copiar {
        let img = NSImage(size: NSSize(width: 30, height: 30))
        img.lockFocus(); NSColor.systemBlue.setFill(); NSRect(x: 0, y: 0, width: 30, height: 30).fill(); img.unlockFocus()
        pb.writeObjects([img])
    }
    let imagenes = h.recortes.filter { $0.tipo == .imagen }
    h.escribir(varios: imagenes)
    revisar("pegar 2 imágenes deja 2 imágenes en el portapapeles",
            (pb.pasteboardItems ?? []).filter { $0.types.contains(.png) }.count == 2)
    let textos = h.recortes.filter { $0.tipo == .texto }.prefix(2)
    h.escribir(varios: Array(textos))
    revisar("pegar 2 textos los une en uno", pb.pasteboardItems?.count == 1 && (pb.string(forType: .string) ?? "").contains("\n\n"))
    let pdf = "El contribu-\nyente deberá\npresentar la  declaración\n\nantes del plazo."
    revisar("pegado limpio une líneas de PDF y respeta párrafos",
            Limpieza.aplicar(pdf) == "El contribuyente deberá presentar la declaración\n\nantes del plazo.")
    let arrastre = h.objetosArrastre(imagenes)
    revisar("arrastrar imágenes entrega archivos reales",
            arrastre.count == 2 && arrastre.allSatisfy { ($0 as? URL).map { FileManager.default.fileExists(atPath: $0.path) } ?? false })

    _ = NSApplication.shared
    let control = Portapapeles(historial: h)
    control.abrir()
    control.cerrar()
    let ids = control.visibles().map(\.id)
    control.clic(ids[0], modificadores: [], clics: 1)
    control.clic(ids[2], modificadores: .command, clics: 1)
    revisar("⌘clic marca dos", control.seleccionados().count == 2)
    control.clic(ids[0], modificadores: [], clics: 1)
    control.clic(ids[3], modificadores: .shift, clics: 1)
    revisar("⇧clic marca el rango (4)", control.seleccionados().count == 4)
    control.seleccionarTodo()
    revisar("⌘A marca todo", control.seleccionados().count == ids.count)

    try? FileManager.default.removeItem(at: carpeta)
    pb.releaseGlobally()
    print(fallas == 0 ? "todo bien" : "\(fallas) fallas")
    return fallas == 0
}

/// Prueba de "Liberar ya" con una Papelera y una bitácora falsas en /tmp: nunca toca la Papelera real ni la
/// bitácora de la app. `Dictado --probar-papelera`
func probarPapelera() -> Bool {
    let fm = FileManager.default
    let base = URL(fileURLWithPath: "/tmp/dictado-prueba-papelera-\(UUID().uuidString)")
    let papelera = base.appendingPathComponent(".Trash")
    let origen = base.appendingPathComponent("origen")
    let fuera = base.appendingPathComponent("fuera")
    let bitacora = base.appendingPathComponent("limpiezas.json")
    for c in [papelera, origen, fuera] { try? fm.createDirectory(at: c, withIntermediateDirectories: true) }
    defer { try? fm.removeItem(at: base) }
    var fallas = 0
    func revisar(_ nombre: String, _ condicion: Bool) {
        print(condicion ? "  ✓" : "  ✗", nombre)
        if !condicion { fallas += 1 }
    }
    func crear(_ carpeta: URL, _ nombre: String) -> URL {
        let u = carpeta.appendingPathComponent(nombre)
        try? Data(repeating: 7, count: 64 * 1024).write(to: u)
        return u
    }
    func identificador(_ u: URL) -> UInt64? { (try? u.resourceValues(forKeys: [.fileIdentifierKey]))?.fileIdentifier }
    func existe(_ u: URL) -> Bool { fm.fileExists(atPath: u.path) }
    /// Como Bitacora.mover, pero a la Papelera falsa.
    func mandar(_ nombre: String) -> (URL, RegistroLimpieza.Movimiento) {
        let u = crear(origen, nombre)
        let d = papelera.appendingPathComponent(nombre)
        try? fm.moveItem(at: u, to: d)
        return (d, .init(original: u.path, papelera: d.path, bytes: 65_536, identificador: identificador(d)))
    }
    let hace10 = Date().addingTimeInterval(-10 * 86_400)
    let (viejo, movViejo) = mandar("cache-vieja")
    let (reciente, movReciente) = mandar("cache-reciente")
    let delUsuario = crear(papelera, "foto-del-usuario.jpg")      // lo botaste tú: no está en la bitácora
    let afuera = crear(fuera, "documento.txt")                     // la bitácora apunta fuera de la Papelera
    let movAfuera = RegistroLimpieza.Movimiento(original: "/tmp/x", papelera: afuera.path, bytes: 65_536)
    let movEscape = RegistroLimpieza.Movimiento(original: "/tmp/x", papelera: papelera.path + "/../fuera/documento.txt", bytes: 65_536)
    let suplantado = crear(papelera, "cache-suplantada")           // mismo nombre, otro archivo
    let movSuplantado = RegistroLimpieza.Movimiento(original: "/tmp/x", papelera: suplantado.path, bytes: 65_536,
                                                    identificador: (identificador(suplantado) ?? 0) &+ 1)
    let legado = crear(papelera, "cache-legado")                   // bitácora vieja sin identificador: llegó hoy, no hace 10 días
    let movLegado = RegistroLimpieza.Movimiento(original: "/tmp/x", papelera: legado.path, bytes: 65_536)
    let (legadoHoy, conId) = mandar("cache-legado-hoy")           // bitácora vieja sin identificador, de hoy: sí cuenta
    let movLegadoHoy = RegistroLimpieza.Movimiento(original: conId.original, papelera: conId.papelera, bytes: conId.bytes)
    Bitacora.escribir([
        RegistroLimpieza(fecha: hace10, titulo: "Cachés", movimientos: [movViejo, movAfuera, movEscape, movSuplantado]),
        RegistroLimpieza(fecha: hace10.addingTimeInterval(60), titulo: "Registros", movimientos: [movLegado]),
        RegistroLimpieza(fecha: Date(), titulo: "Cachés de programación", movimientos: [movReciente, movLegadoHoy]),
    ], en: bitacora)

    let pendientes = Bitacora.pendientes(papelera: papelera, en: bitacora, medir: true)
    revisar("solo cuenta lo que Dictado mandó y sigue en la Papelera (3)", pendientes.count == 3)
    let viejos = pendientes.filter { !$0.reciente }
    let recientes = pendientes.filter(\.reciente)
    revisar("separa lo de más de 7 días de lo reciente", viejos.map(\.movimiento.papelera) == [viejo.path]
            && recientes.map(\.movimiento.papelera) == [reciente.path, legadoHoy.path])
    revisar("mide el tamaño antes de borrar", pendientes.allSatisfy { $0.bytes >= 65_536 })

    var r = Bitacora.liberar(viejos, papelera: papelera, en: bitacora)
    revisar("por defecto borra solo lo de más de 7 días", r.cuantos == 1 && !existe(viejo) && existe(reciente))
    revisar("no toca lo que botaste tú", existe(delUsuario))
    revisar("no toca rutas fuera de la Papelera (ni con ..)", existe(afuera))
    revisar("no toca otro archivo con el mismo nombre", existe(suplantado))
    revisar("bitácora vieja: no borra lo que llegó en otro momento", existe(legado))
    let forjado = Bitacora.Pendiente(fecha: hace10, movimiento: movAfuera, bytes: 65_536)
    r = Bitacora.liberar([forjado], papelera: papelera, en: bitacora)
    revisar("vuelve a comprobar justo antes de borrar", r.cuantos == 0 && existe(afuera))
    let tras = Bitacora.todas(bitacora)
    revisar("la bitácora ya no anota lo borrado", !tras.flatMap(\.movimientos).contains { $0.papelera == viejo.path }
            && tras.count == 3)
    revisar("Deshacer sigue ofreciendo lo reciente", Bitacora.ultimaDeshacible(bitacora)?.movimientos.first?.papelera == reciente.path)

    r = Bitacora.liberar(recientes, papelera: papelera, en: bitacora)
    revisar("lo reciente se borra cuando lo confirmas (también lo de bitácoras viejas)", r.cuantos == 2 && !existe(reciente) && !existe(legadoHoy))
    revisar("sin nada que deshacer, Deshacer desaparece", Bitacora.ultimaDeshacible(bitacora) == nil)
    revisar("Liberar ya se oculta: no queda nada pendiente", Bitacora.pendientes(papelera: papelera, en: bitacora).isEmpty)
    revisar("lo tuyo sigue intacto al final", existe(delUsuario) && existe(afuera) && existe(suplantado) && existe(legado))

    let snapshots = "Snapshots for volume group containing disk /:\ncom.apple.os.update-ABC123\n"
    revisar("el sistema en uso solo no cuenta como actualización", !EspacioOculto.actualizacionPreparada(snapshots))
    revisar("detecta una actualización preparada", EspacioOculto.actualizacionPreparada(snapshots + "com.apple.os.update-MSUPrepareUpdate\n"))
    revisar("Time Machine no cuenta", !EspacioOculto.actualizacionPreparada("com.apple.TimeMachine.2026-10-09-101010.local\n"))
    print(fallas == 0 ? "todo bien" : "\(fallas) fallas")
    return fallas == 0
}

/// Render del panel con capturas de ejemplo (recortes del fondo de pantalla) en la cuadrícula de imágenes,
/// tres seleccionadas. `Dictado --vista-portapapeles salida.png`
@MainActor
func hojaPortapapeles(_ destino: URL, modoLista: Bool = false) -> Bool {
    let carpeta = FileManager.default.temporaryDirectory.appendingPathComponent("dictado-vista-\(UUID().uuidString)")
    let pb = NSPasteboard(name: NSPasteboard.Name("app.dictado.vista.\(UUID().uuidString)"))
    let historial = Historial(carpeta: carpeta, pasteboard: pb)
    let fondo = fondoDeMuestra()
    // Variantes para revisar cada tipo: lista (texto), enlace, imagen, largo, archivo, codigo, color; y los estados
    // vacíos: vacio (historial sin nada) y busqueda (sin coincidencias).
    let variante = CommandLine.arguments.count > 3 ? CommandLine.arguments[3] : (modoLista ? "lista" : "")
    // Dos archivos de ejemplo en la carpeta temporal (lo más antiguo del historial).
    let documentos = carpeta.appendingPathComponent("Documentos")
    try? FileManager.default.createDirectory(at: documentos, withIntermediateDirectories: true)
    let archivos = ["Propuesta comercial.pdf", "Informe trimestral.pdf"].map { documentos.appendingPathComponent($0) }
    for (i, url) in archivos.enumerated() { try? Data(count: 180_000 + i * 95_000).write(to: url) }
    pb.clearContents()
    pb.writeObjects(archivos as [NSURL])
    historial.revisar(app: NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.finder").first)
    let recortes: [NSRect] = [
        NSRect(x: 0, y: 900, width: 1400, height: 900), NSRect(x: 1400, y: 300, width: 1200, height: 800),
        NSRect(x: 600, y: 0, width: 1600, height: 1000), NSRect(x: 200, y: 400, width: 900, height: 900),
        NSRect(x: 1800, y: 900, width: 1000, height: 700), NSRect(x: 900, y: 700, width: 1300, height: 800),
    ]
    let apps = [("Arc", "company.thebrowser.Browser"), ("Finder", "com.apple.finder"), ("Mail", "com.apple.mail")]
    for (i, r) in recortes.enumerated() {
        let img = NSImage(size: NSSize(width: r.width / 4, height: r.height / 4))
        img.lockFocus()
        fondo.draw(in: NSRect(origin: .zero, size: img.size), from: r, operation: .copy, fraction: 1)
        img.unlockFocus()
        pb.clearContents()
        pb.writeObjects([img])
        let app = apps[i % apps.count]
        historial.revisar(app: NSRunningApplication.runningApplications(withBundleIdentifier: app.1).first)
    }
    var textos: [(String, String, String?)] = [
        ("Recordar revisar la propuesta comercial antes del viernes y cruzar las cifras con el informe trimestral.", "company.thebrowser.Browser", "https://www.example.com/informes"),
        ("https://www.example.com/informes/2026/trimestral?id=12345&vista=resumen", "company.thebrowser.Browser", nil),
        ("Cordial saludo,\n\nAdjunto el análisis que pidieron para la reunión del jueves.\n\nQuedo atento.", "com.apple.mail", nil),
    ]
    if variante == "largo" {
        let parrafo = "Este es un texto de ejemplo bastante largo para revisar cómo se ve la vista previa cuando el contenido no cabe: "
            + "debe cortarse con limpieza, sin empujar los datos ni los botones fuera de la tarjeta, y la lista debe truncar el título en una sola línea. "
        textos.append((String(repeating: parrafo, count: 6), "com.apple.Notes", nil))
    }
    if variante == "color" {
        textos.append(("#7A5CFF", "com.figma.Desktop", nil))
    }
    if variante == "codigo" {
        textos.append(("func sumar(_ a: Int, _ b: Int) -> Int {\n    let total = a + b\n    return total\n}", "com.apple.dt.Xcode", nil))
    }
    for (texto, app, origen) in textos {
        pb.clearContents()
        let item = NSPasteboardItem()
        item.setString(texto, forType: .string)
        if let origen { item.setString(origen, forType: NSPasteboard.PasteboardType("org.chromium.source-url")) }
        pb.writeObjects([item])
        historial.revisar(app: NSRunningApplication.runningApplications(withBundleIdentifier: app).first)
    }
    let estado = EstadoPanel()
    estado.appDestino = "Mail"
    // vacio: el historial sin nada; busqueda: una búsqueda sin coincidencias (lista y vista previa vacías).
    let mostrado = variante == "vacio" ? Historial(muestra: []) : historial
    if variante == "busqueda" {
        estado.busqueda = "factura"
    } else if variante == "vacio" {
        estado.seleccion = nil
    } else if !variante.isEmpty {
        let lista = Portapapeles.filtrar(historial.recortes, estado)
        estado.seleccion = switch variante {
        case "enlace": lista.first { $0.tipo == .enlace }?.id
        case "archivo": lista.first { $0.tipo == .archivo }?.id
        case "imagen": lista.first { $0.tipo == .imagen }?.id
        case "largo", "codigo", "color": lista.first?.id
        default: lista.first { $0.texto.hasPrefix("Recordar") }?.id
        }
    } else {
        estado.filtro = .imagenes
        let lista = Portapapeles.filtrar(historial.recortes, estado)
        estado.seleccion = lista[1].id
        estado.marcados = Set([lista[0].id, lista[1].id, lista[3].id])
    }
    let vista = lienzoHalo(fondo, lienzo: CGSize(width: 1000, height: 660),
                           panel: CGSize(width: VistaPortapapeles.ancho, height: VistaPortapapeles.alto), radio: 30) {
        VistaPortapapeles(historial: mostrado, estado: estado, control: nil, simulado: true)
    }
    let renderer = ImageRenderer(content: vista)
    renderer.scale = 2
    defer {
        try? FileManager.default.removeItem(at: carpeta)
        pb.releaseGlobally()
    }
    guard let cg = renderer.cgImage,
          let png = NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:]) else { return false }
    return (try? png.write(to: destino)) != nil
}

/// Render del panel de captura (sin vidrio real), con dos opciones elegidas para ver cómo la luz cambia de tono y
/// de sitio: Texto (violeta) y Grabar (rojo). `Dictado --vista-captura salida.png`
@MainActor
func hojaCaptura(_ destino: URL) -> Bool {
    let fondo = fondoDeMuestra()
    func panel(_ seleccion: Int) -> some View {
        let estado = EstadoCaptura()
        estado.seleccion = seleccion
        return lienzoConVidrio(fondo, lienzo: CGSize(width: 760, height: 330),
                               panel: CGSize(width: VistaCaptura.ancho, height: VistaCaptura.alto), radio: 30) {
            VistaCaptura(estado: estado, control: nil, simulado: true)
        }
    }
    let vista = VStack(spacing: 0) { panel(3); panel(4) }
    let renderer = ImageRenderer(content: vista)
    renderer.scale = 2
    guard let cg = renderer.cgImage,
          let png = NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:]) else { return false }
    return (try? png.write(to: destino)) != nil
}

/// Render de la isla: reposo, abierta y sus actividades. `Dictado --vista-isla salida.png`
/// `DICTADO_ESCENA=abierta` dibuja una sola escena (la imagen de portada del README); `DICTADO_ESTRES=1` agrega
/// escenas con textos largos y mucho contenido para revisar que nada se corte. `DICTADO_NOTCH=180x24` dibuja la isla
/// con otro notch (la de un monitor externo, sin notch, usa el alto de su barra de menús).
@MainActor
func hojaIsla(_ destino: URL, soloAgentes: Bool = false) -> Bool {
    let fondo = fondoDeMuestra()
    let entorno = ProcessInfo.processInfo.environment
    let medidas = (entorno["DICTADO_NOTCH"] ?? "").split(separator: "x").compactMap { Double($0) }
    let notch = medidas.count == 2 ? CGSize(width: medidas[0], height: medidas[1]) : CGSize(width: 186, height: 32)
    let caratula = NSImage(size: NSSize(width: 300, height: 300))
    caratula.lockFocus()
    fondo.draw(in: NSRect(x: 0, y: 0, width: 300, height: 300), from: NSRect(x: 1500, y: 600, width: 900, height: 900),
               operation: .copy, fraction: 1)
    caratula.unlockFocus()
    let chrome = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.google.Chrome").map { Privacidad.mapaDeBits(NSWorkspace.shared.icon(forFile: $0.path)) }
    enum Escena: String {
        case compacta, abierta, abiertaAgentes, abiertaAgenteAlerta, abiertaAgenda, abiertaMac, dictado, privacidad, cancion, evento,
             volumen, brillo, silencio, carga, claudeNecesita, claudeTermino, llamada, saludAviso, agenteAviso, agenteCaido,
             agenteDetalle, agenteDetalleAlerta, abiertaFuentes, abiertaVideo, abiertaSalidas, youtube, abiertaYoutube,
             foco, abiertaFoco, focoTermino, notasOferta, eventoPrep
        case estresAgentes, estresAgenda, estresMac, estresVacia, estresNivel, estresAgente, estresBrillo
        var abierta: Bool {
            [.abierta, .abiertaAgentes, .abiertaAgenteAlerta, .abiertaAgenda, .abiertaMac, .agenteDetalle, .agenteDetalleAlerta,
             .abiertaFuentes, .abiertaVideo, .abiertaSalidas, .abiertaYoutube, .abiertaFoco,
             .estresAgentes, .estresAgenda, .estresMac, .estresVacia].contains(self)
        }
    }
    func escena(_ tipo: Escena) -> some View {
        let estado = EstadoIsla()
        estado.notch = notch
        estado.inicioActividad = Date().addingTimeInterval(-7)
        let musica = Musica(vivo: false)
        let privacidad = Privacidad(vivo: false)
        let claude = SesionesClaude(vivo: false)
        let salud = ejemploSalud()
        let agentes = ejemploAgentes()
        claude.sesiones = [
            .init(id: "a", pid: 1, nombre: "Rediseño del sitio web", carpeta: "proyectos", estado: .esperando,
                  espera: "Necesita tu permiso", desde: Date().addingTimeInterval(-40), contexto: 318_000,
                  actividad: "Terminal · swift build -c release"),
            .init(id: "b", pid: 2, nombre: "Informe trimestral", carpeta: "proyectos", estado: .trabajando,
                  espera: "", desde: Date().addingTimeInterval(-260), contexto: 768_000, actividad: "Editando HeroSection.tsx"),
            .init(id: "c", pid: 3, nombre: "Correos pendientes", carpeta: "notas", estado: .lista,
                  espera: "", desde: Date().addingTimeInterval(-1500), contexto: 31_000,
                  resumen: "Clasifiqué los 14 correos pendientes"),
        ]
        claude.respuestasHoy = 214
        claude.tokensHoy = 727_000
        claude.porHora = [0, 0, 0, 0, 0, 0, 0, 0, 12, 40, 31, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 3, 8, 0].map { $0 * 1000 }
        musica.titulo = "Weightless"
        musica.artista = "Marconi Union"
        musica.duracion = 480
        musica.posicion = 151
        musica.sonando = true
        musica.caratula = caratula
        musica.acento = Musica.colorMedio(caratula)
        musica.origen = Musica.spotify
        musica.nombreOrigen = "Spotify"
        musica.puedeSaltar = true
        let agenda = Agenda(vivo: false)
        agenda.permitido = true
        let ahora = Date()
        agenda.eventos = [
            .init(id: "1", titulo: "Revisión de contrato", inicio: ahora.addingTimeInterval(4 * 60 + 12),
                  fin: ahora.addingTimeInterval(49 * 60), color: Color(red: 0.35, green: 0.6, blue: 1.0),
                  enlace: URL(string: "https://meet.google.com/abc-defg-hij")),
            .init(id: "2", titulo: "Llamada con el equipo", inicio: ahora.addingTimeInterval(3 * 3600),
                  fin: ahora.addingTimeInterval(3.75 * 3600), color: Color(red: 1.0, green: 0.55, blue: 0.3)),
            .init(id: "3", titulo: "Gimnasio", inicio: ahora.addingTimeInterval(5.5 * 3600),
                  fin: ahora.addingTimeInterval(6.5 * 3600), color: Color(red: 0.45, green: 0.85, blue: 0.5)),
        ]
        let hud = EstadoHUD()
        hud.estilo = .prisma
        hud.fase = .escuchando
        hud.nivel = 0.75
        hud.texto = "Recordar enviar la propuesta al cliente"
        let airpods = SalidaAudio(nombre: "AirPods Pro")
        let fuentes = Fuentes(vivo: false)
        let foco = Foco(vivo: false)
        fuentes.salidas = [.init(id: 1, nombre: "Altavoces del MacBook", simbolo: "laptopcomputer"),
                           .init(id: 2, nombre: "AirPods Pro", simbolo: "airpods.pro"),
                           .init(id: 3, nombre: "Pantalla del estudio", simbolo: "display")]
        fuentes.salidaActual = 2
        switch tipo {
        case .compacta: break
        case .llamada:
            privacidad.camara = true
            privacidad.icono = chrome
            privacidad.nombre = "Google Chrome"
            privacidad.desde = Date().addingTimeInterval(-754)
        case .saludAviso:
            estado.actividad = .salud(titulo: "Disco casi lleno", detalle: "Quedan 7,9 GB libres · Limpieza puede recuperar 5,7 GB", grave: true)
        case .agenteAviso:
            estado.actividad = .agente(nombre: "Agente del servidor", alerta: "resumen-finanzas falló: el banco no respondió", caido: false)
        case .claudeNecesita:
            estado.actividad = .claude(sesion: claude.sesiones[0], necesita: true, duracion: 0)
        case .claudeTermino:
            var lista = claude.sesiones[1]
            lista.resumen = "Terminé el borrador del informe"
            estado.actividad = .claude(sesion: lista, necesita: false, duracion: 252)
        case .abiertaFuentes, .abiertaVideo, .abiertaSalidas:  // Spotify y un video de YouTube a la vez; las salidas
            estado.expandida = true
            estado.pestana = .agentes
            let navegador = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "company.thebrowser.Browser")
                ?? NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Safari")
            fuentes.sonando = [.init(id: "navegador", pid: 0, nombre: navegador.map { $0.deletingPathExtension().lastPathComponent } ?? "Safari",
                                     icono: navegador.map { Privacidad.mapaDeBits(NSWorkspace.shared.icon(forFile: $0.path), lado: 50) },
                                     titulo: "Lo-fi para concentrarse · 3 horas", servicio: "YouTube")]
            if tipo == .abiertaVideo { fuentes.elegida = "navegador" }
            if tipo == .abiertaSalidas { fuentes.mostrandoSalidas = true }
        case .foco, .abiertaFoco:  // un bloque de 30 min que va por la mitad
            foco.empezar("Avanzar FONTUR T3: reunir los datos y el borrador", minutos: 30, inicio: Date().addingTimeInterval(-14 * 60))
            agenda.eventos = []
            if tipo == .abiertaFoco {
                estado.expandida = true
                estado.pestana = .agentes
            }
        case .focoTermino:
            estado.actividad = .foco(titulo: "Avanzar FONTUR T3: reunir los datos y el borrador")
        case .notasOferta:
            estado.actividad = .notas(titulo: "Revisión de contrato")
        case .eventoPrep:
            estado.actividad = .evento(titulo: "Revisión de contrato", inicio: Date().addingTimeInterval(252),
                                       color: Color(red: 0.35, green: 0.6, blue: 1.0), enlace: URL(string: "https://meet.google.com/abc-defg-hij"))
        case .youtube, .abiertaYoutube:  // un video de YouTube en el navegador, por "Ahora suena" (sin siguiente: ±10 s)
            let arc = "company.thebrowser.Browser"
            let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: arc)
            let icono = url.map { Privacidad.mapaDeBits(NSWorkspace.shared.icon(forFile: $0.path), lado: 96) }
            musica.origen = arc
            musica.nombreOrigen = "Arc"
            musica.titulo = "Lo-fi para concentrarse · 3 horas"
            musica.artista = "Lofi Girl"
            musica.duracion = 10_800
            musica.posicion = 1_262
            musica.caratula = icono
            musica.acento = icono.map(Musica.colorMedio) ?? .white
            musica.puedeSaltar = true
            musica.tieneSiguiente = false
            fuentes.sonando = [.init(id: arc, pid: 0, nombre: "Arc", icono: icono, titulo: musica.titulo, servicio: "YouTube")]
            agenda.eventos = []
            if tipo == .abiertaYoutube {
                estado.expandida = true
                estado.pestana = .agentes
            }
        case .abiertaAgentes:
            estado.expandida = true
            estado.pestana = .agentes
        case .abiertaAgenteAlerta:
            estado.expandida = true
            estado.pestana = .agentes
            agentes.agentes = ejemploAgentes(alerta: true).agentes
            claude.sesiones.removeFirst()
        case .abiertaAgenda:
            estado.expandida = true
            estado.pestana = .agenda
            salud.discoLibre = 60e9
        case .abiertaMac:
            estado.expandida = true
            estado.pestana = .mac
        case .agenteDetalle:
            estado.expandida = true
            estado.agenteAbierto = agentes.agentes[0].nombre
        case .agenteDetalleAlerta:
            estado.expandida = true
            agentes.agentes = ejemploAgentes(alerta: true).agentes
            estado.agenteAbierto = agentes.agentes[0].nombre
        case .agenteCaido:
            estado.actividad = .agente(nombre: "Agente del servidor", alerta: "El servidor no responde por SSH", caido: true)
        case .abierta:  // portada del README: la llamada, Claude esperándote, el agente del servidor y la música
            estado.expandida = true
            privacidad.camara = true
            privacidad.nombre = "Google Chrome"
            claude.sesiones[0] = .init(id: "a", pid: 1, nombre: "Rediseño del sitio web", carpeta: "proyectos", estado: .esperando,
                                       espera: "Necesita tu permiso", desde: Date().addingTimeInterval(-40), contexto: 318_000,
                                       actividad: "Terminal · npm run build")
            claude.sesiones.remove(at: 1)
        case .dictado: estado.actividad = .dictado
        case .privacidad:
            musica.titulo = ""
            agenda.eventos = []
            privacidad.microfono = true
            privacidad.icono = chrome
            privacidad.nombre = "Google Chrome"
        case .cancion: estado.actividad = .cancion
        case .evento: estado.actividad = .evento(titulo: "Revisión de contrato", inicio: Date().addingTimeInterval(252),
                                                  color: Color(red: 0.35, green: 0.6, blue: 1.0),
                                                  enlace: URL(string: "https://meet.google.com/abc-defg-hij"))
        case .volumen:  // DICTADO_VALOR=0.9 para ver otro nivel
            let v = entorno["DICTADO_VALOR"].flatMap(Double.init) ?? 0.62
            estado.actividad = .nivel(tipo: .volumen, valor: v, silencio: false, salida: airpods)
        case .brillo: estado.actividad = .nivel(tipo: .brillo, valor: 0.81, silencio: false)
        case .silencio: estado.actividad = .nivel(tipo: .volumen, valor: 0.62, silencio: true, salida: airpods)
        case .carga: estado.actividad = .carga(porcentaje: 87)
        // Escenas de estrés: textos largos y mucho contenido.
        case .estresAgentes:
            estado.expandida = true
            estado.pestana = .agentes
            musica.titulo = "Una canción con un título larguísimo que no cabe en el reproductor"
            musica.artista = "Un artista con un nombre igual de largo y varios invitados"
            claude.sesiones[0] = .init(id: "a", pid: 1, nombre: "Migración de la base de datos de clientes y facturación del año pasado",
                                       carpeta: "x", estado: .esperando, espera: "Tiene una pregunta",
                                       desde: Date().addingTimeInterval(-90), contexto: 912_000,
                                       actividad: "¿Borro las tablas temporales antes de migrar o prefieres revisarlas primero una por una?")
            claude.sesiones.append(.init(id: "d", pid: 4, nombre: "Otra sesión que trabaja", carpeta: "x", estado: .trabajando, espera: "",
                                         desde: Date().addingTimeInterval(-60), actividad: "Leyendo un archivo con un nombre muy largo.swift"))
            var conAlertas = ejemploAgentes(alerta: true).agentes[0]
            conAlertas.alertas += ["El disco del servidor está al 94 % y la copia de seguridad puede fallar esta noche si no se libera espacio",
                                   "Certificado vence en 5 días"]
            conAlertas.tareas += (1...3).map { .init(nombre: "tarea-programada-con-nombre-largo-\($0)", estado: "ok", ultima: nil,
                                                     proxima: Date().addingTimeInterval(Double($0) * 86_400), detalle: "") }
            agentes.agentes = [conAlertas, AgentesRemotos.Agente(
                nombre: "Agente de respaldo", estado: .desconocido, actualizado: Date().addingTimeInterval(-300),
                error: "No respondió en 20 s")]
        case .estresAgenda:
            estado.expandida = true
            estado.pestana = .agenda
            agenda.eventos = [
                .init(id: "1", titulo: "Reunión de seguimiento trimestral con todo el equipo de producto y diseño", inicio: ahora.addingTimeInterval(-20 * 60),
                      fin: ahora.addingTimeInterval(25 * 60), color: Color(red: 0.75, green: 0.45, blue: 1.0),
                      enlace: URL(string: "https://zoom.us/j/123456789")),
                .init(id: "2", titulo: "Encimada", inicio: ahora.addingTimeInterval(10 * 60),
                      fin: ahora.addingTimeInterval(70 * 60), color: Color(red: 1.0, green: 0.55, blue: 0.3)),
                .init(id: "3", titulo: "Almuerzo", inicio: ahora.addingTimeInterval(2 * 3600),
                      fin: ahora.addingTimeInterval(3 * 3600), color: Color(red: 0.45, green: 0.85, blue: 0.5)),
                .init(id: "4", titulo: "Mañana temprano", inicio: ahora.addingTimeInterval(20 * 3600),
                      fin: ahora.addingTimeInterval(21 * 3600), color: Color(red: 0.35, green: 0.6, blue: 1.0)),
            ]
        case .estresMac:
            estado.expandida = true
            estado.pestana = .mac
            salud.cpu = 0.99
            salud.gpu = 0.93
            salud.presion = 4
            salud.discoLibre = 120e9
        case .estresVacia:
            estado.expandida = true
            estado.pestana = .agentes
            claude.sesiones = []
            agentes.agentes = []
            musica.titulo = ""
        case .estresNivel:
            estado.actividad = .nivel(tipo: .volumen, valor: 1, silencio: false,
                                      salida: SalidaAudio(nombre: "Altavoces externos de la sala de reuniones del tercer piso"))
        case .estresBrillo: estado.actividad = .nivel(tipo: .brillo, valor: 0.06, silencio: false)
        case .estresAgente:
            estado.actividad = .agente(nombre: "Un agente con un nombre bastante largo para la isla",
                                       alerta: "El proceso nocturno falló tres veces seguidas: el disco del servidor está lleno y no pudo guardar el informe",
                                       caido: true)
        }
        let alto: CGFloat = tipo.abierta ? 280 : 168
        let ancho: CGFloat = tipo.abierta ? 720 : 700
        return ZStack(alignment: .top) {
            Image(nsImage: fondo).resizable().scaledToFill().frame(width: ancho, height: alto, alignment: .top).clipped()
            Rectangle().fill(.white.opacity(0.18)).frame(height: 32)  // barra de menú
            UnevenRoundedRectangle(bottomLeadingRadius: 10, bottomTrailingRadius: 10).fill(.black).frame(width: 186, height: 32)
            VistaIsla(estado: estado, musica: musica, agenda: agenda, hud: hud, privacidad: privacidad, claude: claude,
                      agentes: agentes, salud: salud, control: nil, fuentes: fuentes, foco: foco,
                      notas: NotasReunion(agenda: agenda, privacidad: privacidad, vivo: false))
                .frame(width: Isla.expandida.width, height: Isla.expandida.height)
                .frame(height: alto, alignment: .top)
        }
        .frame(width: ancho, height: alto)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
    let hoja: AnyView
    if soloAgentes {  // `Dictado --vista-agentes`: avisos, la pestaña Agentes y el detalle de un agente
        hoja = AnyView(VStack(spacing: 14) {
            HStack(spacing: 14) { escena(.agenteAviso); escena(.agenteCaido) }
            HStack(spacing: 14) { escena(.abiertaAgentes); escena(.abiertaAgenteAlerta) }
            HStack(spacing: 14) { escena(.agenteDetalle); escena(.agenteDetalleAlerta) }
        }
        .padding(14)
        .background(Color(white: 0.08)))
    } else if let sola = entorno["DICTADO_ESCENA"].flatMap(Escena.init(rawValue:)) {
        hoja = AnyView(escena(sola))
    } else {
        hoja = AnyView(VStack(spacing: 14) {
            HStack(spacing: 14) { escena(.compacta); escena(.dictado) }
            HStack(spacing: 14) { escena(.volumen); escena(.brillo) }
            HStack(spacing: 14) { escena(.silencio); escena(.carga) }
            HStack(spacing: 14) { escena(.evento); escena(.cancion) }
            HStack(spacing: 14) { escena(.claudeNecesita); escena(.claudeTermino) }
            HStack(spacing: 14) { escena(.agenteAviso); escena(.agenteCaido) }
            HStack(spacing: 14) { escena(.saludAviso); escena(.llamada) }
            escena(.abierta)
            escena(.abiertaAgenteAlerta)
            escena(.agenteDetalle)
            escena(.abiertaAgenda)
            escena(.abiertaMac)
            if entorno["DICTADO_ESTRES"] != nil {
                HStack(spacing: 14) { escena(.estresNivel); escena(.estresAgente) }
                HStack(spacing: 14) { escena(.estresBrillo); escena(.privacidad) }
                escena(.estresAgentes)
                escena(.estresAgenda)
                escena(.estresMac)
                escena(.estresVacia)
            }
        }
        .padding(14)
        .background(Color(white: 0.08)))
    }
    let renderer = ImageRenderer(content: hoja)
    renderer.scale = 2
    guard let cg = renderer.cgImage,
          let png = NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:]) else { return false }
    return (try? png.write(to: destino)) != nil
}

/// Render del panel Salud del Mac (Ahora, Limpieza y el final de Limpieza) con datos de ejemplo. `Dictado --vista-salud salida.png`
@MainActor
func hojaSalud(_ destino: URL) -> Bool {
    let fondo = fondoDeMuestra()
    func icono(_ bundle: String) -> NSImage? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundle).map { Privacidad.mapaDeBits(NSWorkspace.shared.icon(forFile: $0.path), lado: 52) }
    }
    func estado(_ pestana: Int) -> EstadoSalud {
        let e = EstadoSalud()
        e.pestana = pestana
        e.cpu = 0.46
        e.gpu = 0.63
        e.memoriaTotal = 17_179_869_184
        e.memoriaUsada = 12.4e9
        e.swap = 4.96e9
        e.presion = 1
        e.discoLibre = 8.9e9
        e.discoTotal = 245e9
        e.consumidores = [
            .init(id: "c", nombre: "Claude", explicacion: Explicaciones.app("com.anthropic.claudefordesktop"), icono: icono("com.anthropic.claudefordesktop"),
                  simbolo: "app", cpu: 0.19, memoria: 3.6e9, pid: 1, esApp: true),
            .init(id: "a", nombre: "Arc", explicacion: Explicaciones.app("company.thebrowser.Browser"), icono: icono("company.thebrowser.Browser"),
                  simbolo: "app", cpu: 0.05, memoria: 1.7e9, pid: 2, esApp: true),
            .init(id: "s", nombre: "Apple Intelligence", explicacion: "Procesa en segundo plano; se calma solo", icono: nil,
                  simbolo: "apple.intelligence", cpu: 0.08, memoria: 0.4e9, pid: 3, esApp: false),
            .init(id: "w", nombre: "Pantalla", explicacion: "Dibuja todo lo que ves; sube con muchas ventanas y animaciones", icono: nil,
                  simbolo: "display", cpu: 0.05, memoria: 0.88e9, pid: 4, esApp: false),
            .init(id: "wa", nombre: "WhatsApp", explicacion: "Mensajería", icono: icono("net.whatsapp.WhatsApp"),
                  simbolo: "app", cpu: 0.01, memoria: 0.24e9, pid: 5, esApp: true),
        ]
        func item(_ nombre: String, _ detalle: String, _ bytes: Int64, marcado: Bool = true) -> ItemLimpieza {
            ItemLimpieza(url: URL(fileURLWithPath: "/tmp/" + nombre), nombre: nombre, detalle: detalle, bytes: bytes, marcado: marcado)
        }
        e.limpiables = [
            .init(id: "dependencias", titulo: "Dependencias de proyectos dormidos",
                  detalle: "prototipo-ia 1,8 GB · finanzas 698 MB · video-promo 454 MB — se recrean con npm install o uv sync",
                  simbolo: "cube.box", items: [
                      item("prototipo-ia", ".venv · sin tocar desde 2 jul · revisa antes", 1_833_000_000, marcado: false),
                      item("finanzas", "node_modules · sin tocar desde 18 jul", 698_000_000),
                      item("video-promo", "node_modules · sin tocar desde 3 ago", 454_000_000, marcado: false),
                      item("sitio-v3", "node_modules · sin tocar desde 9 jun", 353_000_000),
                  ], accion: .papelera, boton: "A la Papelera"),
            .init(id: "desarrollo", titulo: "Cachés de programación", detalle: "uv 3,7 GB · npx 889 MB · Playwright 553 MB — se vuelven a descargar si hacen falta",
                  simbolo: "hammer", items: [item("uv", "", 3_700_000_000), item("npx", "", 889_000_000), item("Playwright", "", 553_000_000)],
                  accion: .papelera, boton: "A la Papelera"),
            .init(id: "cerrar:arc", titulo: "Caché de Arc", detalle: "Arc está abierto: lo cierro, limpio su caché y lo vuelvo a abrir como estaba",
                  simbolo: "arrow.triangle.2.circlepath", items: [item("Arc", "", 3_300_000_000)], accion: .cerrarYLimpiar("x"), boton: "Cerrar y limpiar"),
            .init(id: "caches", titulo: "Cachés de apps cerradas", detalle: "Spotify 205 MB · Claude (actualizaciones) 680 MB · SiriTTS 247 MB",
                  simbolo: "shippingbox", items: [item("varias", "", 1_400_000_000)], accion: .papelera, boton: "A la Papelera"),
            .init(id: "wa", titulo: "Fotos y videos de WhatsApp", detalle: "En WhatsApp: Ajustes → Almacenamiento → revisa los chats más pesados",
                  simbolo: "message", items: [item("Media", "", 21_200_000_000)], accion: .abrirApp(""), boton: "Abrir WhatsApp"),
            .init(id: "nv", titulo: "Notas de Voz", detalle: "Exporta las viejas a Drive y bórralas en la app",
                  simbolo: "waveform", items: [item("Recordings", "", 15_400_000_000)], accion: .abrirApp(""), boton: "Abrir Notas de Voz"),
            .init(id: "dup", titulo: "Archivos duplicados", detalle: "reel-evento.mp4 113 MB · webinar.mov 110 MB — se conserva la copia más antigua",
                  simbolo: "doc.on.doc", items: [item("reel-evento.mp4", "", 1_090_000_000)], accion: .mostrar, boton: "Ver copias"),
        ]
        e.abiertos = ["dependencias"]
        e.ultima = RegistroLimpieza(fecha: Date(), titulo: "x", movimientos: [])
        e.mensaje = "2,1 GB de cachés de programación a la Papelera (puedes deshacer). El disco todavía no gana espacio: se libera con «Liberar ya» o al vaciar la Papelera."
        // Lo que Dictado dejó en la Papelera: el botón "Liberar ya" aparece con el total.
        func pendiente(_ dias: Double, _ bytes: Int64) -> Bitacora.Pendiente {
            Bitacora.Pendiente(fecha: Date().addingTimeInterval(-dias * 86_400),
                               movimiento: .init(original: "/tmp/x", papelera: "/tmp/x", bytes: bytes), bytes: bytes)
        }
        e.pendientes = [pendiente(12, 2_400_000_000), pendiente(0, 2_100_000_000)]
        e.discoPurgable = 2.8e9
        e.actualizacionLista = true
        return e
    }
    func icloud() -> Limpiable {
        func item(_ nombre: String, _ detalle: String, _ bytes: Int64) -> ItemLimpieza {
            ItemLimpieza(url: URL(fileURLWithPath: "/tmp/" + nombre), nombre: nombre, detalle: detalle, bytes: bytes)
        }
        return Limpiable(id: "icloud", titulo: "Archivos de iCloud descargados",
                         detalle: "grabacion-taller.mov 1,2 GB · fotos-viaje.zip 640 MB · manual.pdf 96 MB — siguen en iCloud y se descargan al abrirlos",
                         simbolo: "icloud.and.arrow.down", items: [
                             item("grabacion-taller.mov", "iCloud Drive › Videos · sin abrir desde 14 ago", 1_200_000_000),
                             item("fotos-viaje.zip", "iCloud Drive › Archivo · sin abrir desde 2 jun", 640_000_000),
                             item("manual.pdf", "Documentos › Referencias · sin abrir desde 21 sept", 96_000_000),
                         ], accion: .quitarDescarga, boton: "Quitar descargas")
    }
    /// En los renders no hay desplazamiento: Limpieza se muestra en dos vistas, el principio de la lista y el final
    /// (iCloud desplegado, tus cosas y el espacio oculto), como si la hubieras bajado.
    func panel(_ pestana: Int, final: Bool = false) -> some View {
        let e = estado(pestana)
        if pestana == 1 && !final { e.limpiables.insert(icloud(), at: 4) }
        if final {
            e.limpiables = [icloud()] + e.limpiables.filter { $0.id == "wa" }
            e.abiertos = ["icloud"]
            // Tras "Liberar ya" con lo de más de 7 días: queda lo reciente, que pide confirmación aparte.
            e.pendientes.removeAll { !$0.reciente }
            e.mensaje = "Borré para siempre 2,4 GB de la Papelera. El disco ganó 2,4 GB."
        }
        return lienzoConVidrio(fondo, lienzo: CGSize(width: 800, height: 720), panel: CGSize(width: Salud.ancho, height: Salud.alto), radio: 30) {
            VistaSalud(estado: e, control: nil, simulado: true, alFinal: final)
        }
    }
    let hoja = HStack(spacing: 0) { panel(0); panel(1); panel(1, final: true) }
    let renderer = ImageRenderer(content: hoja)
    renderer.scale = 2
    guard let cg = renderer.cgImage,
          let png = NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:]) else { return false }
    return (try? png.write(to: destino)) != nil
}

/// Datos de ejemplo de Salud del Mac (parecidos a los reales del 9 oct 2026) para los renders.
@MainActor
func ejemploSalud() -> EstadoSalud {
    func icono(_ bundle: String) -> NSImage? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundle).map { Privacidad.mapaDeBits(NSWorkspace.shared.icon(forFile: $0.path), lado: 52) }
    }
    let e = EstadoSalud()
    e.cpu = 0.46
    e.gpu = 0.23
    e.memoriaTotal = 17_179_869_184
    e.memoriaUsada = 13.0e9
    e.swap = 6.8e9
    e.presion = 2
    e.discoLibre = 7.9e9
    e.discoTotal = 245e9
    e.consumidores = [
        .init(id: "c", nombre: "Claude", explicacion: "", icono: icono("com.anthropic.claudefordesktop"), simbolo: "app",
              cpu: 0.19, memoria: 3.6e9, pid: 1, esApp: true),
        .init(id: "a", nombre: "Arc", explicacion: "", icono: icono("company.thebrowser.Browser"), simbolo: "app",
              cpu: 0.05, memoria: 1.7e9, pid: 2, esApp: true),
    ]
    return e
}

/// Fondo de los renders: la imagen de la variable DICTADO_FONDO si existe; si no, un degradado.
@MainActor
func fondoDeMuestra() -> NSImage {
    if let ruta = ProcessInfo.processInfo.environment["DICTADO_FONDO"],
       let imagen = NSImage(contentsOfFile: (ruta as NSString).expandingTildeInPath) { return imagen }
    let imagen = NSImage(size: NSSize(width: 3000, height: 2000))
    imagen.lockFocus()
    NSGradient(colors: [NSColor(calibratedRed: 0.42, green: 0.50, blue: 0.74, alpha: 1),
                        NSColor(calibratedRed: 0.84, green: 0.78, blue: 0.86, alpha: 1),
                        NSColor(calibratedRed: 0.30, green: 0.38, blue: 0.62, alpha: 1)])?
        .draw(in: NSRect(x: 0, y: 0, width: 3000, height: 2000), angle: -65)
    imagen.unlockFocus()
    return imagen
}

/// Datos de ejemplo de agentes remotos para los renders. `alerta`: una tarea falló.
@MainActor
func ejemploAgentes(alerta: Bool = false) -> AgentesRemotos {
    let a = AgentesRemotos(vivo: false)
    let ahora = Date()
    let hoy = Calendar.current.startOfDay(for: ahora)
    func h(_ horas: Double) -> Date { hoy.addingTimeInterval(horas * 3600) }
    let enUnRato = min(ahora.addingTimeInterval(5400), h(23.8))   // algo que falta hoy
    a.agentes = [AgentesRemotos.Agente(
        nombre: "Agente del servidor", estado: alerta ? .alerta : .ok,
        resumen: alerta ? "6 tareas activas · 1 con error" : "6 tareas activas · todo bien",
        alertas: alerta ? ["resumen-finanzas falló: el banco no respondió"] : [],
        tareas: [
            .init(nombre: "copia-nocturna", estado: "ok", ultima: h(2), proxima: h(26), detalle: "todos los días a las 2"),
            .init(nombre: "procesar-ideas", estado: "ok", ultima: h(3.5), proxima: h(27.5), detalle: "todos los días a las 3:30"),
            .init(nombre: "resumen-finanzas", estado: alerta ? "error" : "ok", ultima: h(7), proxima: h(31),
                  detalle: "todos los días a las 7"),
            .init(nombre: "informe-matutino", estado: "ok", ultima: h(8), proxima: h(32), detalle: "todos los días a las 8"),
            .init(nombre: "revisar-correo", estado: "ok", ultima: enUnRato.addingTimeInterval(-86_400), proxima: enUnRato,
                  detalle: "todos los días"),
            .init(nombre: "revision-semanal", estado: "corriendo", ultima: ahora.addingTimeInterval(-120), proxima: nil,
                  detalle: "lunes 10:00"),
            .init(nombre: "radar-contenidos", estado: "pausada", ultima: h(-700), proxima: nil, detalle: ""),
        ],
        actualizado: ahora)]
    return a
}
