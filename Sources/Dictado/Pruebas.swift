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
    let textos: [(String, String, String?)] = [
        ("Recordar revisar la propuesta comercial antes del viernes y cruzar las cifras con el informe trimestral.", "company.thebrowser.Browser", "https://www.example.com/informes"),
        ("https://www.example.com/informe?id=12345", "company.thebrowser.Browser", nil),
        ("Cordial saludo,\n\nAdjunto el análisis que pidieron para la reunión del jueves.\n\nQuedo atento.", "com.apple.mail", nil),
    ]
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
    if modoLista {
        let lista = Portapapeles.filtrar(historial.recortes, estado)
        estado.seleccion = lista.first { $0.texto.hasPrefix("Recordar") }?.id
    } else {
        estado.filtro = .imagenes
        let lista = Portapapeles.filtrar(historial.recortes, estado)
        estado.seleccion = lista[1].id
        estado.marcados = Set([lista[0].id, lista[1].id, lista[3].id])
    }
    let vista = lienzoConVidrio(fondo, lienzo: CGSize(width: 1000, height: 660),
                                panel: CGSize(width: VistaPortapapeles.ancho, height: VistaPortapapeles.alto), radio: 30) {
        VistaPortapapeles(historial: historial, estado: estado, control: nil, simulado: true)
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

/// Render del panel de captura (sin vidrio real). `Dictado --vista-captura salida.png`
@MainActor
func hojaCaptura(_ destino: URL) -> Bool {
    let estado = EstadoCaptura()
    estado.seleccion = 3
    let fondo = fondoDeMuestra()
    let vista = lienzoConVidrio(fondo, lienzo: CGSize(width: 760, height: 400),
                                panel: CGSize(width: VistaCaptura.ancho, height: VistaCaptura.alto), radio: 30) {
        VistaCaptura(estado: estado, control: nil, simulado: true)
    }
    let renderer = ImageRenderer(content: vista)
    renderer.scale = 2
    guard let cg = renderer.cgImage,
          let png = NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:]) else { return false }
    return (try? png.write(to: destino)) != nil
}

/// Render de la isla: reposo, abierta y sus actividades. `Dictado --vista-isla salida.png`
@MainActor
func hojaIsla(_ destino: URL) -> Bool {
    let fondo = fondoDeMuestra()
    let caratula = NSImage(size: NSSize(width: 300, height: 300))
    caratula.lockFocus()
    fondo.draw(in: NSRect(x: 0, y: 0, width: 300, height: 300), from: NSRect(x: 1500, y: 600, width: 900, height: 900),
               operation: .copy, fraction: 1)
    caratula.unlockFocus()
    let chrome = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.google.Chrome").map { Privacidad.mapaDeBits(NSWorkspace.shared.icon(forFile: $0.path)) }
    enum Escena { case compacta, abierta, abiertaAgenda, dictado, privacidad, cancion, evento, volumen, brillo, silencio, carga, claudeNecesita, claudeTermino, llamada, saludAviso, abiertaMac }
    func escena(_ tipo: Escena) -> some View {
        let estado = EstadoIsla()
        estado.notch = CGSize(width: 186, height: 32)
        estado.inicioActividad = Date().addingTimeInterval(-7)
        let musica = Musica(vivo: false)
        let privacidad = Privacidad(vivo: false)
        let claude = SesionesClaude(vivo: false)
        let salud = ejemploSalud()
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
        let agenda = Agenda(vivo: false)
        agenda.permitido = true
        let ahora = Date()
        agenda.eventos = [
            .init(id: "1", titulo: "Revisión de contrato", inicio: ahora.addingTimeInterval(4 * 60),
                  fin: ahora.addingTimeInterval(49 * 60), color: Color(red: 0.35, green: 0.6, blue: 1.0),
                  enlace: URL(string: "https://meet.google.com/abc-defg-hij")),
            .init(id: "2", titulo: "Llamada con el equipo", inicio: ahora.addingTimeInterval(3 * 3600),
                  fin: ahora.addingTimeInterval(3.5 * 3600), color: Color(red: 1.0, green: 0.55, blue: 0.3)),
        ]
        let hud = EstadoHUD()
        hud.estilo = .prisma
        hud.fase = .escuchando
        hud.nivel = 0.75
        hud.texto = "Recordar enviar la propuesta al cliente"
        switch tipo {
        case .compacta: break
        case .llamada:
            privacidad.camara = true
            privacidad.icono = chrome
            privacidad.nombre = "Google Chrome"
            privacidad.desde = Date().addingTimeInterval(-754)
        case .saludAviso:
            estado.actividad = .salud(titulo: "Disco casi lleno", detalle: "Quedan 7,9 GB libres · Limpieza puede recuperar 5,7 GB", grave: true)
        case .claudeNecesita:
            estado.actividad = .claude(sesion: claude.sesiones[0], necesita: true, duracion: 0)
        case .claudeTermino:
            var lista = claude.sesiones[1]
            lista.resumen = "Terminé el borrador del informe"
            estado.actividad = .claude(sesion: lista, necesita: false, duracion: 252)
        case .abiertaAgenda:
            estado.expandida = true
            claude.sesiones = []
            salud.discoLibre = 60e9
        case .abiertaMac:
            estado.expandida = true
            claude.sesiones = []
        case .abierta:
            estado.expandida = true
            privacidad.camara = true
            privacidad.nombre = "Google Chrome"
        case .dictado: estado.actividad = .dictado
        case .privacidad:
            musica.titulo = ""
            agenda.eventos = []
            privacidad.microfono = true
            privacidad.icono = chrome
            privacidad.nombre = "Google Chrome"
        case .cancion: estado.actividad = .cancion
        case .evento: estado.actividad = .evento(titulo: "Revisión de contrato", inicio: Date().addingTimeInterval(299),
                                                  color: Color(red: 0.35, green: 0.6, blue: 1.0),
                                                  enlace: URL(string: "https://meet.google.com/abc-defg-hij"))
        case .volumen: estado.actividad = .nivel(tipo: .volumen, valor: 0.62, silencio: false)
        case .brillo: estado.actividad = .nivel(tipo: .brillo, valor: 0.81, silencio: false)
        case .silencio: estado.actividad = .nivel(tipo: .volumen, valor: 0.62, silencio: true)
        case .carga: estado.actividad = .carga(porcentaje: 87)
        }
        return ZStack(alignment: .top) {
            Image(nsImage: fondo).resizable().scaledToFill().frame(width: 700, height: 210, alignment: .top).clipped()
            Rectangle().fill(.white.opacity(0.18)).frame(height: 32)  // barra de menú
            UnevenRoundedRectangle(bottomLeadingRadius: 10, bottomTrailingRadius: 10).fill(.black).frame(width: 186, height: 32)
            VistaIsla(estado: estado, musica: musica, agenda: agenda, hud: hud, privacidad: privacidad, claude: claude,
                      salud: salud, control: nil)
                .frame(width: Isla.expandida.width, height: Isla.expandida.height)
        }
        .frame(width: 700, height: 210)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
    let hoja = VStack(spacing: 14) {
        HStack(spacing: 14) { escena(.compacta); escena(.dictado) }
        HStack(spacing: 14) { escena(.privacidad); escena(.cancion) }
        HStack(spacing: 14) { escena(.evento); escena(.carga) }
        HStack(spacing: 14) { escena(.volumen); escena(.brillo) }
        HStack(spacing: 14) { escena(.silencio); escena(.compacta) }
        HStack(spacing: 14) { escena(.claudeNecesita); escena(.claudeTermino) }
        HStack(spacing: 14) { escena(.llamada); escena(.saludAviso) }
        escena(.abiertaAgenda)
        escena(.abiertaMac)
        escena(.abierta)
    }
    .padding(14)
    .background(Color(white: 0.08))
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
            VistaSalud(estado: e, control: nil, simulado: true)
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
