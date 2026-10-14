import AppKit
import ApplicationServices
import EventKit
import IOKit.ps
import Observation
import os
import SwiftUI

// Isla del notch: reemplazo liviano de Atoll. En reposo no se anima ni consulta nada en bucle;
// todo llega por avisos del sistema (Spotify, Calendario, corriente, audio, cámara). Las notificaciones
// no pasan por aquí: macOS ya las muestra arriba a la derecha.

// MARK: - Música (Spotify)

/// Lo que suena en Spotify, por la notificación que Spotify publica en cada cambio. Los controles son las
/// teclas multimedia (⏯ ⏭ ⏮), que solo necesitan Accesibilidad. La carátula sale del oEmbed público de Spotify.
@MainActor @Observable
final class Musica {
    var sonando = false
    var titulo = ""
    var artista = ""
    var duracion = 0.0       // segundos
    var posicion = 0.0       // segundos, medida en `actualizada`
    var actualizada = Date()
    var caratula: NSImage?
    var acento = Color.white  // color medio de la carátula

    @ObservationIgnored var alCambiarCancion: (() -> Void)?
    @ObservationIgnored private var pista = ""

    var hayPista: Bool { !titulo.isEmpty }

    func posicion(en ahora: Date) -> Double {
        sonando ? min(duracion, posicion + ahora.timeIntervalSince(actualizada)) : posicion
    }

    init(vivo: Bool = true) {
        guard vivo else { return }
        DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("com.spotify.client.PlaybackStateChanged"), object: nil, queue: .main
        ) { [weak self] nota in
            nonisolated(unsafe) let info = nota.userInfo ?? [:]
            MainActor.assumeIsolated { self?.aplicar(info) }
        }
    }

    private func aplicar(_ info: [AnyHashable: Any]) {
        let estado = info["Player State"] as? String ?? ""
        if estado == "Stopped" {
            sonando = false
            titulo = ""
            artista = ""
            caratula = nil
            pista = ""
            return
        }
        sonando = estado == "Playing"
        titulo = info["Name"] as? String ?? titulo
        artista = info["Artist"] as? String ?? artista
        if let ms = (info["Duration"] as? NSNumber)?.doubleValue { duracion = ms / 1000 }
        if let p = (info["Playback Position"] as? NSNumber)?.doubleValue { posicion = p }
        actualizada = Date()
        if let id = info["Track ID"] as? String, id != pista {
            pista = id
            cargarCaratula(id)
            if sonando { alCambiarCancion?() }
        }
    }

    func alternar() {
        sonando.toggle()  // respuesta inmediata; la notificación de Spotify confirma
        Self.teclaMedia(16)
    }

    func siguiente() { Self.teclaMedia(17) }
    func anterior() { Self.teclaMedia(18) }

    func abrirSpotify() {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.spotify.client") {
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
        }
    }

    /// Tecla multimedia del teclado (16 ⏯, 17 ⏭, 18 ⏮). La recibe la app que está sonando.
    static func teclaMedia(_ tecla: Int) {
        for abajo in [true, false] {
            let datos = (tecla << 16) | ((abajo ? 0xA : 0xB) << 8)
            let evento = NSEvent.otherEvent(with: .systemDefined, location: .zero,
                                            modifierFlags: NSEvent.ModifierFlags(rawValue: abajo ? 0xA00 : 0xB00),
                                            timestamp: 0, windowNumber: 0, context: nil, subtype: 8, data1: datos, data2: -1)
            evento?.cgEvent?.post(tap: .cghidEventTap)
        }
    }

    private func cargarCaratula(_ id: String) {
        caratula = nil
        let partes = id.split(separator: ":")  // spotify:track:XXXX
        guard partes.count == 3,
              let oembed = URL(string: "https://open.spotify.com/oembed?url=https://open.spotify.com/\(partes[1])/\(partes[2])")
        else { return }
        Task {
            guard let (datos, _) = try? await URLSession.shared.data(from: oembed),
                  let json = try? JSONSerialization.jsonObject(with: datos) as? [String: Any],
                  let miniatura = (json["thumbnail_url"] as? String).flatMap(URL.init(string:)),
                  let (img, _) = try? await URLSession.shared.data(from: miniatura),
                  let imagen = NSImage(data: img), pista == id else { return }
            caratula = imagen
            acento = Self.colorMedio(imagen)
        }
    }

    static func colorMedio(_ imagen: NSImage) -> Color {
        guard let punto = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1, pixelsHigh: 1, bitsPerSample: 8,
                                           samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                           colorSpaceName: .deviceRGB, bytesPerRow: 4, bitsPerPixel: 32) else { return .white }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: punto)
        imagen.draw(in: NSRect(x: 0, y: 0, width: 1, height: 1))
        NSGraphicsContext.restoreGraphicsState()
        guard let c = punto.colorAt(x: 0, y: 0)?.usingColorSpace(.sRGB) else { return .white }
        return Color(red: 0.45 + c.redComponent * 0.55, green: 0.45 + c.greenComponent * 0.55, blue: 0.45 + c.blueComponent * 0.55)
    }
}

// MARK: - Agenda (Calendario de macOS)

@MainActor @Observable
final class Agenda {
    struct Evento: Identifiable {
        let id: String
        let titulo: String
        let inicio: Date
        let fin: Date
        let color: Color
        var enlace: URL? = nil  // Meet, Zoom, Teams…

        /// "Unirse" aparece desde 10 minutos antes y mientras dura la reunión.
        var sePuedeUnir: Bool {
            guard enlace != nil else { return false }
            let ahora = Date()
            return inicio.timeIntervalSince(ahora) <= 10 * 60 && fin > ahora
        }
    }

    var eventos: [Evento] = []
    var permitido = false

    @ObservationIgnored var alAvisar: ((Evento) -> Void)?
    @ObservationIgnored private let almacen = EKEventStore()
    @ObservationIgnored private var relojes: [Timer] = []
    @ObservationIgnored private var avisados = Set<String>()

    init(vivo: Bool = true) {
        guard vivo else { return }
        NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: almacen, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refrescar() }
        }
        relojes = [
            Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.refrescar() }
            },
            Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in  // sin consultar el calendario
                MainActor.assumeIsolated { self?.recordar() }
            },
        ]
        Task {
            permitido = (try? await almacen.requestFullAccessToEvents()) ?? false
            refrescar()
        }
    }

    func refrescar() {
        guard permitido else { return }
        let ahora = Date()
        let hasta = Calendar.current.date(byAdding: .hour, value: 36, to: ahora) ?? ahora
        let consulta = almacen.predicateForEvents(withStart: ahora.addingTimeInterval(-6 * 3600), end: hasta, calendars: nil)
        eventos = almacen.events(matching: consulta)
            .filter { !$0.isAllDay && $0.endDate > ahora }
            .sorted { $0.startDate < $1.startDate }
            .prefix(5)
            .map { Evento(id: $0.eventIdentifier ?? UUID().uuidString, titulo: $0.title ?? "Sin título",
                          inicio: $0.startDate, fin: $0.endDate, color: Color(nsColor: $0.calendar.color),
                          enlace: Reunion.enlace(en: [$0.url?.absoluteString, $0.location, $0.notes])) }
    }

    /// Aviso único 5 minutos antes de cada evento.
    private func recordar() {
        let ahora = Date()
        for e in eventos where !avisados.contains(e.id) {
            let faltan = e.inicio.timeIntervalSince(ahora)
            if faltan > 0 && faltan <= 5 * 60 {
                avisados.insert(e.id)
                alAvisar?(e)
            }
        }
    }

    /// El evento en curso o el que empieza en menos de 30 minutos (para la isla compacta).
    var inminente: Evento? {
        let ahora = Date()
        return eventos.first { $0.inicio <= ahora.addingTimeInterval(30 * 60) && $0.fin > ahora }
    }
}

/// Enlace de videollamada de un evento. Google Calendar pone el de Meet en la descripción; Zoom y Teams
/// suelen ir en la ubicación o en las notas.
enum Reunion {
    private static let patrones = [
        #"https://meet\.google\.com/[a-z]{3,}-[a-z]{3,}-[a-z]{3,}"#,
        #"https://([\w-]+\.)?zoom\.us/(j|my|s|w)/[^\s<>"')\]]+"#,
        #"https://teams\.microsoft\.com/l/meetup-join/[^\s<>"')\]]+"#,
        #"https://teams\.live\.com/meet/[^\s<>"')\]]+"#,
        #"https://([\w-]+\.)?webex\.com/[^\s<>"')\]]+"#,
        #"https://facetime\.apple\.com/join[^\s<>"')\]]+"#,
    ]

    static func enlace(en textos: [String?]) -> URL? {
        for texto in textos.compactMap({ $0 }) where !texto.isEmpty {
            for patron in patrones {
                if let r = texto.range(of: patron, options: [.regularExpression, .caseInsensitive]) {
                    return URL(string: String(texto[r]))
                }
            }
        }
        return nil
    }

    /// Zoom abre directo en la app si está instalada (sin la página intermedia del navegador).
    static func abrible(_ url: URL) -> URL {
        guard url.host?.hasSuffix("zoom.us") == true,
              let partes = URLComponents(url: url, resolvingAgainstBaseURL: false),
              partes.path.hasPrefix("/j/"), let numero = partes.path.split(separator: "/").last
        else { return url }
        var app = URLComponents()
        app.scheme = "zoommtg"
        app.host = "zoom.us"
        app.path = "/join"
        app.queryItems = [URLQueryItem(name: "confno", value: String(numero))]
            + (partes.queryItems ?? []).filter { $0.name == "pwd" }
        guard let directo = app.url, NSWorkspace.shared.urlForApplication(toOpen: directo) != nil else { return url }
        return directo
    }
}

// MARK: - Corriente

/// Avisa cuando conectas el cargador (aviso de IOKit, sin consultar en bucle).
@MainActor
final class Bateria {
    var alConectar: ((Int) -> Void)?
    private var fuente: CFRunLoopSource?
    private var conectada = Bateria.enCorriente()

    init(vivo: Bool = true) {
        guard vivo else { return }
        let contexto = Unmanaged.passUnretained(self).toOpaque()
        fuente = IOPSNotificationCreateRunLoopSource({ ctx in
            guard let ctx else { return }
            let yo = Unmanaged<Bateria>.fromOpaque(ctx).takeUnretainedValue()
            MainActor.assumeIsolated { yo.cambio() }
        }, contexto)?.takeRetainedValue()
        if let fuente { CFRunLoopAddSource(CFRunLoopGetMain(), fuente, .defaultMode) }
    }

    private func cambio() {
        let ahora = Self.enCorriente()
        if ahora && !conectada { alConectar?(Self.porcentaje()) }
        conectada = ahora
    }

    static func enCorriente() -> Bool {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let tipo = IOPSGetProvidingPowerSourceType(info)?.takeUnretainedValue() else { return false }
        return (tipo as String) == kIOPSACPowerValue
    }

    static func porcentaje() -> Int {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let lista = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return 0 }
        for fuente in lista {
            if let d = IOPSGetPowerSourceDescription(info, fuente)?.takeUnretainedValue() as? [String: Any],
               let actual = d[kIOPSCurrentCapacityKey] as? Int, let maximo = d[kIOPSMaxCapacityKey] as? Int, maximo > 0 {
                return actual * 100 / maximo
            }
        }
        return 0
    }
}

// MARK: - Estado y ventana

@MainActor @Observable
final class EstadoIsla {
    enum Actividad {
        case dictado
        case aviso(icono: String, texto: String)
        case cancion
        case evento(titulo: String, inicio: Date, color: Color, enlace: URL?)
        case carga(porcentaje: Int)
        case nivel(tipo: Niveles.Tipo, valor: Double, silencio: Bool, salida: SalidaAudio? = nil)
        case claude(sesion: SesionesClaude.Sesion, necesita: Bool, duracion: TimeInterval)
        case salud(titulo: String, detalle: String, grave: Bool)
        /// Un agente remoto (servidor) avisa de un problema; "Ver" abre su detalle en la pestaña Agentes.
        case agente(nombre: String, alerta: String, caido: Bool)
    }

    /// Pestañas de la isla abierta. nil = la que más importa ahora (ver `Expandida.porDefecto`).
    enum Pestana { case agentes, agenda, mac }

    var expandida = false
    var pestana: Pestana?
    var notch = CGSize(width: 200, height: 32)
    var actividad: Actividad?
    var agenteAbierto: String?   // agente de fuera del Mac con su detalle abierto en la pestaña Agentes
    var idActividad = UUID()     // cambia con cada actividad: dispara la animación de entrada
    var inicioActividad = Date()

    /// Tamaño de la isla según lo que muestra. `punto`: cámara o micrófono en uso (ensancha las alas).
    func tamano(alas: Bool, punto: Bool = false) -> CGSize {
        if expandida { return Isla.expandida }
        let w = notch.width + 2 * FormaIsla.hombro
        let h = notch.height
        switch actividad {
        case .dictado: return CGSize(width: w + 2 * 120, height: h + 82)
        case .aviso: return CGSize(width: w + 2 * 100, height: h + 38)
        case .cancion: return CGSize(width: w + 2 * 120, height: h + 66)
        case .evento: return CGSize(width: w + 2 * 150, height: h + 52)
        case .carga: return CGSize(width: w + 2 * 70, height: h)
        case .claude: return CGSize(width: w + 2 * 140, height: h + 58)
        case .salud: return CGSize(width: w + 2 * 136, height: h + 50)
        case .agente: return CGSize(width: w + 2 * 140, height: h + 50)
        case .nivel(let tipo, _, _, _):  // el volumen lleva el arco, un poco más alto
            if tipo == .brillo { return CGSize(width: w + 2 * 92, height: h + 44) }
            let alto: CGFloat = EstiloVolumen.actual == .espectro ? 66 : (EstiloVolumen.actual == .bruma ? 48 : 52)
            return CGSize(width: w + 2 * 124, height: h + alto)
        case nil: return CGSize(width: w + (alas ? 2 * 46 : 0) + (punto ? 2 * 14 : 0), height: h)
        }
    }

    var dictando: Bool {
        if case .dictado = actividad { return true }
        return false
    }

    /// Aviso con botón (Unirse, Responder): no se cambia por la vista abierta al pasar el mouse.
    var reunionConBoton: Bool {
        switch actividad {
        case .evento(_, _, _, let enlace): return enlace != nil
        case .claude, .salud, .agente: return true
        default: return false
        }
    }
}

/// La isla, una por pantalla. En la del notch se pega al notch; en las demás (monitores externos) hace de notch del
/// alto de la barra de menús, centrada arriba. Lo que muestra (dictado, avisos, música…) sale en todas a la vez; abrirla
/// con el mouse es de cada pantalla. Cada ventana crece al instante y se achica cuando termina la animación, para que
/// los clics fuera de la isla no se bloqueen.
@MainActor
final class Isla {
    let musica: Musica
    let agenda: Agenda
    let hud: EstadoHUD
    /// Lo que se muestra ahora, igual en todas las pantallas. Cada pantalla copia esto en su propio estado, que
    /// además lleva lo suyo: su notch, si está abierta y en qué pestaña.
    let estado = EstadoIsla()
    let privacidad: Privacidad
    let claude: SesionesClaude
    /// Agentes fuera del Mac (servidores) configurados en el ajuste `agentes`; ver Agentes.swift.
    let agentes: AgentesRemotos
    /// Qué suena en el Mac y por dónde (el reproductor de la isla abierta).
    let fuentes = Fuentes()
    private let bateria: Bateria
    private var niveles: Niveles?
    private var caras: [CGDirectDisplayID: Cara] = [:]
    private var finActividad: DispatchWorkItem?
    let salud: Salud

    static let expandida = CGSize(width: 600, height: 200)
    /// Ancho del notch que se dibuja en una pantalla que no lo tiene: parecido al de un MacBook en una horizontal; en una
    /// vertical, angosto, porque su barra de menús es corta y la isla taparía los menús.
    static let notchVirtual: CGFloat = 180
    static let notchVirtualVertical: CGFloat = 64

    /// Una pantalla con su isla: la ventana, su estado de vista y sus esperas.
    @MainActor
    private final class Cara {
        var pantalla: NSScreen
        let estado = EstadoIsla()
        var panel: NSPanel!
        var colapso: DispatchWorkItem?
        var achique: DispatchWorkItem?
        var vigia: Timer?

        init(pantalla: NSScreen) { self.pantalla = pantalla }
    }

    init(hud: EstadoHUD, niveles: Bool, salud: Salud) {
        self.hud = hud
        self.salud = salud
        musica = Musica()
        agenda = Agenda()
        bateria = Bateria()
        privacidad = Privacidad()
        claude = SesionesClaude()
        agentes = AgentesRemotos()
        musica.alCambiarCancion = { [weak self] in self?.mostrar(.cancion, segundos: 3.2) }
        agenda.alAvisar = { [weak self] e in
            self?.mostrar(.evento(titulo: e.titulo, inicio: e.inicio, color: e.color, enlace: e.enlace),
                          segundos: e.enlace == nil ? 7 : 20)
        }
        agentes.alAlertar = { [weak self] agente, alerta in
            guard let self else { return }
            let caido = self.agentes.agentes.first { $0.nombre == agente }?.estado == .caido
            self.mostrar(.agente(nombre: agente, alerta: alerta, caido: caido), segundos: 10)
        }
        claude.alNecesitar = { [weak self] s in
            self?.mostrar(.claude(sesion: s, necesita: true, duracion: 0), segundos: 12)
        }
        claude.alTerminar = { [weak self] s, duracion in
            // Si estás mirando Claude ya lo viste; y los turnos cortos no merecen aviso.
            guard duracion >= 20, NSWorkspace.shared.frontmostApplication?.bundleIdentifier != SesionesClaude.app else { return }
            self?.mostrar(.claude(sesion: s, necesita: false, duracion: duracion), segundos: 6)
        }
        bateria.alConectar = { [weak self] p in self?.mostrar(.carga(porcentaje: p), segundos: 3) }
        usarNiveles(niveles)
        escucharPruebas()
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.montar() }
        }
        montar()
    }

    var activa: Bool { caras.values.contains { $0.panel.isVisible } }
    var interceptaNiveles: Bool { niveles?.conectado == true }

    func apagar() {
        caras.values.forEach { $0.panel.orderOut(nil) }
        usarNiveles(false)
    }

    /// Volumen y brillo en la isla (intercepta esas teclas) o en el cuadro de macOS.
    func usarNiveles(_ si: Bool) {
        if si, niveles == nil {
            let n = Niveles()
            n.puedeMostrar = { [weak self] in self?.activa == true }
            n.alCambiar = { [weak self] tipo, valor, silencio in self?.mostrarNivel(tipo, valor: valor, silencio: silencio) }
            niveles = n
        } else if !si {
            niveles?.apagar()
            niveles = nil
        }
    }

    /// Una isla en cada pantalla conectada. Se vuelve a llamar cuando conectas, desconectas o reacomodas pantallas.
    func montar() {
        var vivas = Set<CGDirectDisplayID>()
        for pantalla in NSScreen.screens {
            guard let id = pantalla.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID else { continue }
            vivas.insert(id)
            let cara = caras[id] ?? crearCara(pantalla)
            caras[id] = cara
            cara.pantalla = pantalla
            cara.estado.notch = Self.notch(de: pantalla)
            sincronizar(cara)
            poner(cara, tamanoObjetivo(cara))
            cara.panel.orderFrontRegardless()
        }
        for (id, cara) in caras where !vivas.contains(id) {   // pantallas que ya no están
            cara.vigia?.invalidate()
            cara.panel.orderOut(nil)
            caras[id] = nil
        }
    }

    /// El notch de la pantalla; si no tiene (un monitor externo), uno del alto de su barra de menús.
    static func notch(de pantalla: NSScreen) -> CGSize {
        if pantalla.safeAreaInsets.top > 0 {
            let izquierda = pantalla.auxiliaryTopLeftArea?.width ?? 0
            let derecha = pantalla.auxiliaryTopRightArea?.width ?? 0
            return CGSize(width: pantalla.frame.width - izquierda - derecha, height: pantalla.safeAreaInsets.top)
        }
        let barra = pantalla.frame.maxY - pantalla.visibleFrame.maxY   // 0 si la barra de menús se oculta sola
        let vertical = pantalla.frame.height > pantalla.frame.width
        return CGSize(width: vertical ? notchVirtualVertical : notchVirtual, height: barra > 0 ? barra : 24)
    }

    private func crearCara(_ pantalla: NSScreen) -> Cara {
        let cara = Cara(pantalla: pantalla)
        let p = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.isFloatingPanel = true
        p.level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)
        p.backgroundColor = .clear
        p.isOpaque = false
        p.hasShadow = false
        p.hidesOnDeactivate = false
        p.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        let sensor = Sensor()
        sensor.alEntrar = { [weak self, weak cara] in if let cara { self?.expandir(cara) } }
        sensor.alSalir = { [weak self, weak cara] in if let cara { self?.colapsar(cara) } }
        let vista = VistaPrimerClic(rootView: VistaIsla(estado: cara.estado, musica: musica, agenda: agenda, hud: hud,
                                                        privacidad: privacidad, claude: claude, agentes: agentes, salud: salud.estado,
                                                        control: self, fuentes: fuentes))
        vista.autoresizingMask = [.width, .height]
        sensor.addSubview(vista)
        p.contentView = sensor
        cara.panel = p
        return cara
    }

    /// Lo que se muestra es lo mismo en todas las pantallas: se copia a cada una.
    private func sincronizar(_ cara: Cara) {
        cara.estado.actividad = estado.actividad
        cara.estado.idActividad = estado.idActividad
        cara.estado.inicioActividad = estado.inicioActividad
    }

    /// Cierra la isla abierta en todas las pantallas (vuelve a la compacta).
    private func cerrarTodas() {
        for cara in caras.values {
            cara.estado.expandida = false
            cara.estado.pestana = nil
            cara.estado.agenteAbierto = nil
        }
    }

    // MARK: Actividades

    func empezarDictado() {
        guard activa else { return }
        finActividad?.cancel()
        cerrarTodas()
        estado.actividad = .dictado
        estado.idActividad = UUID()
        estado.inicioActividad = Date()
        ajustar()
    }

    func terminarDictado(icono: String, texto: String) {
        mostrar(.aviso(icono: icono, texto: texto), segundos: 1.8, forzar: true)
    }

    func cancelarDictado() {
        if estado.dictando { quitarActividad() }
    }

    /// Aviso pasajero. No interrumpe un dictado en curso.
    func mostrar(_ actividad: EstadoIsla.Actividad, segundos: Double, forzar: Bool = false) {
        guard activa, forzar || !estado.dictando else { return }
        finActividad?.cancel()
        estado.actividad = actividad
        estado.idActividad = UUID()
        estado.inicioActividad = Date()
        ajustar()
        programarFin(segundos)
    }

    private func quitarActividad() {
        estado.actividad = nil
        ajustar()
    }

    /// Dial de volumen o brillo. Mientras sigues presionando la tecla, solo se mueve el dial (sin volver a entrar):
    /// la actividad se reemplaza sin cambiar `idActividad`, que es lo que dispara la animación de entrada.
    func mostrarNivel(_ tipo: Niveles.Tipo, valor: Double, silencio: Bool) {
        let nueva = EstadoIsla.Actividad.nivel(tipo: tipo, valor: valor, silencio: silencio,
                                               salida: tipo == .volumen ? Audio.descripcionSalida() : nil)
        if case .nivel(let actual, _, _, _) = estado.actividad, actual == tipo, !caras.values.contains(where: { $0.estado.expandida }) {
            estado.actividad = nueva
            caras.values.forEach(sincronizar)
            programarFin(1.6)
        } else {
            mostrar(nueva, segundos: 1.6)
        }
    }

    private func programarFin(_ segundos: Double) {
        finActividad?.cancel()
        let tarea = DispatchWorkItem { [weak self] in MainActor.assumeIsolated { self?.quitarActividad() } }
        finActividad = tarea
        DispatchQueue.main.asyncAfter(deadline: .now() + segundos, execute: tarea)
    }

    /// Abre el panel completo de Salud del Mac (ícono de la pestaña Mac o "Ver" de un aviso).
    func abrirSalud() {
        cerrarTodas()
        quitarActividad()
        salud.abrir()
    }

    func medirSalud() { salud.medirAhora() }

    /// Desde el aviso de un agente ("Ver"): abre la isla de la pantalla donde está el puntero en la pestaña Agentes,
    /// con su detalle.
    func verAgente(_ nombre: String) {
        finActividad?.cancel()
        quitarActividad()
        let cara = caras.values.first { NSMouseInRect(NSEvent.mouseLocation, $0.pantalla.frame, false) }
            ?? caras.values.first { $0.pantalla.safeAreaInsets.top > 0 } ?? caras.values.first
        guard let cara else { return }
        cara.estado.pestana = .agentes
        cara.estado.agenteAbierto = nombre
        expandir(cara)
    }

    /// Abre esa sesión de Claude desde el aviso ("Responder" / "Ver").
    func abrirClaude(_ sesion: SesionesClaude.Sesion?) {
        if sesion?.id != "prueba" { SesionesClaude.abrir(sesion) }
        cerrarTodas()
        quitarActividad()
    }

    /// La reunión en curso o la que empieza en la próxima hora, si tiene enlace. false si no hay ninguna.
    @discardableResult
    func unirseAProxima() -> Bool {
        let ahora = Date()
        guard let e = agenda.eventos.first(where: { $0.enlace != nil && $0.fin > ahora && $0.inicio.timeIntervalSince(ahora) < 3600 }),
              let enlace = e.enlace else { return false }
        unirse(enlace)
        return true
    }

    /// Abre la videollamada (Zoom directo en su app si está instalada).
    func unirse(_ enlace: URL) {
        let ok = enlace.scheme == "dictado-prueba" ? false : NSWorkspace.shared.open(Reunion.abrible(enlace))
        Logger(subsystem: "app.dictado", category: "isla")
            .notice("unirse: \(enlace.host ?? enlace.scheme ?? "", privacy: .public) abrió=\(ok)")
        cerrarTodas()
        quitarActividad()
    }

    /// Para verificar la isla sin esperar una reunión real:
    ///   DistributedNotificationCenter "app.dictado.prueba" con objeto "evento" o "privacidad".
    private func escucharPruebas() {
        DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("app.dictado.prueba"), object: nil, queue: .main
        ) { [weak self] nota in
            let que = nota.object as? String ?? ""
            MainActor.assumeIsolated {
                guard let self else { return }
                switch que {
                case "evento":
                    self.mostrar(.evento(titulo: "Prueba de reunión", inicio: Date().addingTimeInterval(300), color: .green,
                                         enlace: URL(string: "dictado-prueba://unirse")), segundos: 8)
                case "claude":
                    let prueba = SesionesClaude.Sesion(id: "prueba", pid: 0, nombre: "Prueba de sesión", carpeta: "", estado: .esperando,
                                                       espera: "Necesita tu permiso", desde: Date(), actividad: "Terminal · swift build")
                    self.mostrar(.claude(sesion: prueba, necesita: true, duracion: 0), segundos: 6)
                case "salud":
                    self.mostrar(.salud(titulo: "Disco casi lleno", detalle: "Quedan 7,9 GB libres", grave: true), segundos: 6)
                case "agente":
                    self.mostrar(.agente(nombre: "Prueba de agente", alerta: "informe-diario falló: sin conexión con el correo",
                                         caido: false), segundos: 6)
                case "privacidad":
                    self.privacidad.microfono = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 4) { MainActor.assumeIsolated { self.privacidad.revisar() } }
                default: break
                }
            }
        }
    }

    // MARK: Tamaño y mouse

    private func tamanoObjetivo(_ cara: Cara) -> CGSize {
        cara.estado.tamano(alas: musica.hayPista || agenda.inminente != nil || privacidad.activo || claude.hayActividad,
                           punto: privacidad.activo)
    }

    /// Todas las pantallas: copia lo que se muestra y ajusta cada isla.
    func ajustar() {
        for cara in caras.values {
            sincronizar(cara)
            ajustar(cara)
        }
    }

    /// Crece al instante (la animación ocurre dentro) y se achica cuando termina.
    private func ajustar(_ cara: Cara) {
        let objetivo = tamanoObjetivo(cara)
        let actual = cara.panel.frame.size
        poner(cara, CGSize(width: max(objetivo.width, actual.width), height: max(objetivo.height, actual.height)))
        cara.achique?.cancel()
        let tarea = DispatchWorkItem { [weak self, weak cara] in
            MainActor.assumeIsolated {
                guard let self, let cara else { return }
                self.poner(cara, self.tamanoObjetivo(cara))
            }
        }
        cara.achique = tarea
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: tarea)
    }

    private func poner(_ cara: Cara, _ tam: CGSize) {
        let marco = cara.pantalla.frame
        cara.panel.setFrame(NSRect(x: marco.midX - tam.width / 2, y: marco.maxY - tam.height,
                                   width: tam.width, height: tam.height), display: true)
        cara.panel.contentView?.subviews.first?.frame = NSRect(origin: .zero, size: tam)
    }

    private func expandir(_ cara: Cara) {
        cara.colapso?.cancel()
        if estado.reunionConBoton && !cara.estado.expandida {  // el mouse va hacia "Unirse": el aviso se queda quieto
            finActividad?.cancel()
            return
        }
        guard !cara.estado.expandida, !estado.dictando else { return }
        agenda.refrescar()
        cara.estado.expandida = true
        ajustar(cara)
        vigilarSalida(cara)
    }

    /// Red de seguridad: si macOS no avisa que el mouse salió (pasa cuando la ventana cambia de tamaño bajo el
    /// cursor), la isla abierta se cierra igual.
    private func vigilarSalida(_ cara: Cara) {
        cara.vigia?.invalidate()
        cara.vigia = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self, weak cara] t in
            MainActor.assumeIsolated {
                guard let self, let cara, cara.estado.expandida else {
                    t.invalidate()
                    return
                }
                if !NSMouseInRect(NSEvent.mouseLocation, cara.panel.frame, false) { self.colapsar(cara) }
            }
        }
    }

    private func colapsar(_ cara: Cara) {
        if estado.reunionConBoton && !cara.estado.expandida {
            programarFin(4)
            return
        }
        let tarea = DispatchWorkItem { [weak self, weak cara] in
            MainActor.assumeIsolated {
                guard let self, let cara, cara.estado.expandida else { return }
                cara.estado.expandida = false
                cara.estado.pestana = nil
                cara.estado.agenteAbierto = nil
                self.ajustar(cara)
            }
        }
        cara.colapso = tarea
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: tarea)
    }

    /// Cuando cambia lo que hay que mostrar (música, evento), la isla compacta se ensancha o se encoge.
    func refrescarCompacta() { ajustar() }
}

/// El primer clic en la isla ya pulsa el botón (la isla nunca es la ventana activa).
final class VistaPrimerClic<Contenido: View>: NSHostingView<Contenido> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// Vista base que detecta la entrada y salida del mouse aunque Dictado no sea la app activa.
final class Sensor: NSView {
    var alEntrar: (() -> Void)?
    var alSalir: (() -> Void)?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                       owner: self, userInfo: nil))
    }

    override func mouseEntered(with event: NSEvent) { alEntrar?() }
    override func mouseExited(with event: NSEvent) { alSalir?() }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
