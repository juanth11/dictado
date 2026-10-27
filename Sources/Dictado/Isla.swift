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

// MARK: - Música (lo que suena en el Mac)

/// Lo que suena en el Mac, venga de donde venga: Spotify, un video de YouTube en el navegador, Música, un podcast.
/// Dos fuentes: el "Ahora suena" del sistema (AhoraSuenaSistema.swift: título, posición y qué controles acepta la app) y,
/// para Spotify, su propia notificación, que trae la carátula (del oEmbed público de Spotify). Los controles son las
/// teclas multimedia (⏯ ⏭ ⏮, las recibe la app que suena) y, para saltar a un punto, MediaRemote.
@MainActor @Observable
final class Musica {
    static let spotify = "com.spotify.client"

    var sonando = false
    var titulo = ""
    var artista = ""
    var duracion = 0.0       // segundos
    var posicion = 0.0       // segundos, medida en `actualizada`
    var actualizada = Date()
    var caratula: NSImage?
    var acento = Color.white  // color medio de la carátula
    /// La app que suena ("com.spotify.client", "company.thebrowser.Browser") y su nombre ("Spotify", "Arc").
    var origen = ""
    var nombreOrigen = ""
    /// Lo que deja hacer esa app: saltar a un punto (YouTube, Música, Spotify) y pasar a la siguiente o la anterior
    /// (un video suelto de YouTube no tiene siguiente: ahí van ±10 s).
    var puedeSaltar = false
    var tieneSiguiente = true

    @ObservationIgnored var alCambiarCancion: (() -> Void)?
    @ObservationIgnored private var pista = ""
    @ObservationIgnored private var sistema: AhoraSuenaSistema?

    var hayPista: Bool { !titulo.isEmpty }
    var esSpotify: Bool { origen == Self.spotify }

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
        sistema = AhoraSuenaSistema { [weak self] info in self?.aplicarSistema(info) }
    }

    /// La notificación de Spotify. Si en "Ahora suena" manda otra app (un video que suena), se ignora mientras Spotify
    /// no esté sonando.
    private func aplicar(_ info: [AnyHashable: Any]) {
        let estado = info["Player State"] as? String ?? ""
        guard origen.isEmpty || esSpotify || estado == "Playing" else { return }
        if estado == "Stopped" {
            limpiar()
            return
        }
        if !esSpotify {
            origen = Self.spotify
            nombreOrigen = "Spotify"
            tieneSiguiente = true
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

    /// "Ahora suena" del sistema. Para Spotify solo aporta la posición exacta y los controles (su notificación trae lo
    /// demás, con la carátula); para cualquier otra app es la fuente: título, artista, duración, posición y el ícono
    /// de la app como carátula.
    private func aplicarSistema(_ info: AhoraSuenaSistema.Info?) {
        guard let info, let app = info.app, !app.isEmpty else {
            if !esSpotify { limpiar() }  // nada en "Ahora suena": Spotify avisa lo suyo por su lado
            return
        }
        let comandos = Set(info.comandos ?? [])
        puedeSaltar = comandos.contains(24)
        tieneSiguiente = comandos.isEmpty || comandos.contains(4)
        let ahora = Date()
        if app == Self.spotify {
            origen = app
            nombreOrigen = "Spotify"
            if titulo.isEmpty { titulo = info.titulo ?? ""; artista = info.artista ?? "" }
            if let d = info.duracion, d > 0 { duracion = d }
            posicion = info.posicion(en: ahora)
            actualizada = ahora
            return
        }
        let nueva = app != origen || (info.titulo ?? "") != titulo
        origen = app
        nombreOrigen = info.nombre.flatMap { $0.isEmpty ? nil : $0 } ?? app
        titulo = info.titulo ?? ""
        artista = info.artista ?? ""
        duracion = info.duracion ?? 0
        sonando = info.sonando ?? ((info.ritmo ?? 0) > 0)
        posicion = info.posicion(en: ahora)
        actualizada = ahora
        if nueva {
            pista = ""
            caratula = Self.icono(app)
            acento = caratula.map(Self.colorMedio) ?? .white
            if sonando { alCambiarCancion?() }
        }
    }

    private func limpiar() {
        sonando = false
        titulo = ""
        artista = ""
        caratula = nil
        pista = ""
        origen = ""
        nombreOrigen = ""
        puedeSaltar = false
        tieneSiguiente = true
    }

    /// El ícono de la app (hace de carátula cuando la app no da una, como un navegador).
    private static func icono(_ app: String) -> NSImage? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: app)
            .map { Privacidad.mapaDeBits(NSWorkspace.shared.icon(forFile: $0.path), lado: 96) }
    }

    func alternar() {
        sonando.toggle()  // respuesta inmediata; la notificación o "Ahora suena" confirman
        Self.teclaMedia(16)
    }

    /// Salta a ese segundo (si la app que suena lo acepta). La barra se mueve al instante.
    func saltar(a segundos: Double) {
        guard puedeSaltar else { return }
        let s = max(0, duracion > 0 ? min(duracion, segundos) : segundos)
        posicion = s
        actualizada = Date()
        AhoraSuenaSistema.saltar(a: s)
    }

    func avanzar(_ segundos: Double) { saltar(a: posicion(en: Date()) + segundos) }

    /// Trae al frente la app que suena (el video, la pestaña, Spotify).
    func irAOrigen() {
        if let app = NSRunningApplication.runningApplications(withBundleIdentifier: origen).first {
            app.activate()
        } else if esSpotify || origen.isEmpty {
            abrirSpotify()
        }
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
        /// Los invitados (nombre y correo por separado, sin ti): con eso el cerebro busca al cliente o la organización.
        var personas: [String] = []

        /// Una reunión de verdad: tiene invitados o enlace. Lo demás (Almuerzo, Ejercicio, una clase sin invitados) es
        /// un bloque: se ve en la agenda, pero no pregunta si grabas ni le pone su título a una grabación.
        var esReunion: Bool { enlace != nil || !personas.isEmpty }

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
    /// Empezó una reunión (con invitados o enlace): las notas preguntan si grabas.
    @ObservationIgnored var alEmpezar: ((Evento) -> Void)?
    @ObservationIgnored private var empezados = Set<String>()
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
        let elegidos = calendariosElegidos()
        guard !elegidos.isEmpty else {
            eventos = []
            return
        }
        let consulta = almacen.predicateForEvents(withStart: ahora.addingTimeInterval(-6 * 3600), end: hasta, calendars: elegidos)
        // El mismo evento llega dos veces si una cuenta tiene suscrito el calendario de otra: se queda uno (el que
        // tiene invitados o enlace, si alguno los tiene).
        var vistos: [String: Int] = [:]
        var lista: [EKEvent] = []
        for e in almacen.events(matching: consulta).sorted(by: { $0.startDate < $1.startDate })
        where !e.isAllDay && e.endDate > ahora && e.status != .canceled && !Self.rechazado(e) {
            let clave = (e.title ?? "").lowercased().trimmingCharacters(in: .whitespaces) + "|" + String(Int(e.startDate.timeIntervalSince1970))
            if let i = vistos[clave] {
                if (lista[i].attendees ?? []).isEmpty, !(e.attendees ?? []).isEmpty { lista[i] = e }
                continue
            }
            vistos[clave] = lista.count
            lista.append(e)
        }
        // Los bloques de la mañana no deben dejar fuera a las reuniones: hasta 24 eventos (36 horas).
        eventos = lista
            .prefix(24)
            .map { Evento(id: $0.eventIdentifier ?? UUID().uuidString, titulo: $0.title ?? "Sin título",
                          inicio: $0.startDate, fin: $0.endDate, color: Color(nsColor: $0.calendar.color),
                          enlace: Reunion.enlace(en: [$0.url?.absoluteString, $0.location, $0.notes]),
                          personas: Self.personas($0)) }
    }

    /// Lo rechazaste: no es parte de tu día.
    private static func rechazado(_ e: EKEvent) -> Bool {
        (e.attendees ?? []).contains { $0.isCurrentUser && $0.participantStatus == .declined }
    }

    // MARK: Qué calendarios cuentan

    struct Calendario: Identifiable {
        let id: String
        let titulo: String
        let cuenta: String
        let activo: Bool
    }

    private static let claveCalendarios = "calendarios"
    /// Las cuentas de la agenda (correos, en las preferencias del Mac, nunca en el código). De cada una entra solo su
    /// calendario principal: así una cuenta que agregues después entra sola, y los calendarios viejos de esas cuentas
    /// (clases, familia, las copias de otra cuenta) se quedan fuera.
    private static let claveCuentas = "agenda.cuentas"

    /// Por omisión: los calendarios en los que puedes escribir, sin cumpleaños, festivos ni suscripciones ("Encontrado en
    /// Mail" y los festivos de Google son de solo lectura). Al elegir en el menú se guarda la lista exacta.
    private static func porOmision(_ c: EKCalendar) -> Bool {
        c.type != .birthday && c.type != .subscription && c.allowsContentModifications
    }

    /// El principal de una cuenta: en Google se llama como el correo; en Exchange u Outlook, "Calendario" o "Calendar"
    /// dentro de la cuenta.
    private static func principal(_ c: EKCalendar, de cuentas: Set<String>) -> Bool {
        guard c.type != .birthday, c.type != .subscription else { return false }
        let cuenta = (c.source?.title ?? "").lowercased()
        let titulo = c.title.trimmingCharacters(in: .whitespaces).lowercased()
        // Una cuenta de Google agregada desde Ajustes puede llamarse solo "Google": entonces manda el título.
        if cuentas.contains(titulo) { return true }
        return cuentas.contains(cuenta) && (titulo == "calendario" || titulo == "calendar")
    }

    private func calendariosElegidos() -> [EKCalendar] {
        let todos = almacen.calendars(for: .event)
        guard let ids = UserDefaults.dictado.stringArray(forKey: Self.claveCalendarios) else {
            if let cuentas = UserDefaults.dictado.stringArray(forKey: Self.claveCuentas), !cuentas.isEmpty {
                let set = Set(cuentas.map { $0.lowercased() })
                return todos.filter { Self.principal($0, de: set) }
            }
            return todos.filter(Self.porOmision)
        }
        let set = Set(ids)
        return todos.filter { set.contains($0.calendarIdentifier) }
    }

    /// Todos los calendarios del Mac, con los elegidos marcados (para el menú).
    func calendarios() -> [Calendario] {
        guard permitido else { return [] }
        let activos = Set(calendariosElegidos().map(\.calendarIdentifier))
        return almacen.calendars(for: .event)
            .map { Calendario(id: $0.calendarIdentifier, titulo: $0.title.trimmingCharacters(in: .whitespaces),
                              cuenta: $0.source?.title ?? "", activo: activos.contains($0.calendarIdentifier)) }
            .sorted { ($0.cuenta, $0.titulo) < ($1.cuenta, $1.titulo) }
    }

    /// Hay cuentas guardadas y elegiste a mano en el menú: el menú ofrece volver a "solo el principal de cada cuenta".
    var eligioAMano: Bool {
        UserDefaults.dictado.stringArray(forKey: Self.claveCalendarios) != nil
            && !(UserDefaults.dictado.stringArray(forKey: Self.claveCuentas) ?? []).isEmpty
    }

    func usarCuentas() {
        UserDefaults.dictado.removeObject(forKey: Self.claveCalendarios)
        refrescar()
    }

    func alternarCalendario(_ id: String) {
        var activos = Set(calendariosElegidos().map(\.calendarIdentifier))
        if activos.contains(id) { activos.remove(id) } else { activos.insert(id) }
        UserDefaults.dictado.set(Array(activos), forKey: Self.claveCalendarios)
        refrescar()
    }

    private static func personas(_ e: EKEvent) -> [String] {
        var lista: [String] = []
        for p in e.attendees ?? [] where !p.isCurrentUser {
            if let n = p.name, !n.isEmpty, !n.contains("@") { lista.append(n) }
            let correo = p.url.absoluteString.replacingOccurrences(of: "mailto:", with: "")
            if correo.contains("@") { lista.append(correo) }
        }
        return Array(lista.prefix(12))
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
        // Empezó (hace menos de 10 minutos) una reunión: se pregunta una vez por evento.
        for e in eventos where e.esReunion && !empezados.contains(e.id) {
            let paso = ahora.timeIntervalSince(e.inicio)
            if paso >= 0 && paso < 10 * 60 && e.fin > ahora {
                empezados.insert(e.id)
                alEmpezar?(e)
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
        /// Terminó un bloque de foco: ¿quedó hecha?
        case foco(titulo: String)
        /// Empezó una llamada: ¿tomo notas?
        case notas(titulo: String)
        /// El cierre del día: quedan pendientes (Mañana, Soltar, Ver).
        case cierre(quedan: Int)
    }

    /// Pestañas de la isla abierta. nil = la que más importa ahora (ver `Expandida.porDefecto`).
    enum Pestana { case agentes, agenda, notas, mac }

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
        case .foco: return CGSize(width: w + 2 * 180, height: h + 58)
        case .notas: return CGSize(width: w + 2 * 160, height: h + 62)
        case .cierre: return CGSize(width: w + 2 * 160, height: h + 62)
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
        case .claude, .salud, .agente, .foco, .notas, .cierre: return true
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
    /// El bloque de foco (lo comparte con el Centro y Hyper + F) y las notas de reunión.
    let foco: Foco
    let notas: NotasReunion
    /// Tus pendientes de las reuniones, de a uno (pestaña Notas) y el cierre del día.
    let pendientes: Pendientes
    private var relojCierre: Timer?
    private var archivoCierre: String?
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

    init(hud: EstadoHUD, niveles: Bool, salud: Salud, foco: Foco) {
        self.hud = hud
        self.salud = salud
        self.foco = foco
        musica = Musica()
        agenda = Agenda()
        bateria = Bateria()
        privacidad = Privacidad()
        notas = NotasReunion(agenda: agenda, privacidad: privacidad)
        pendientes = Pendientes(cerebro: Ajustes().carpetaInbox.deletingLastPathComponent().path)
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
        foco.alTerminar = { [weak self] b in self?.mostrar(.foco(titulo: b.titulo), segundos: 30) }
        notas.avisar = { [weak self] actividad, segundos in self?.mostrar(actividad, segundos: segundos) }
        privacidad.alCambiarMicrofono = { [weak self] enUso in self?.notas.microfonoCambio(enUso) }
        agenda.alEmpezar = { [weak self] e in self?.notas.eventoEmpezo(e) }
        notas.alListo = { [weak self] in self?.pendientes.refrescar() }
        programarCierre()
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
                                                        control: self, fuentes: fuentes, foco: foco, notas: notas))
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
        // La pregunta "¿grabo?" sin responder vuelve cuando se va el aviso que la tapó.
        if let t = notas.pendiente {
            if case .notas = estado.actividad {} else {
                mostrar(.notas(titulo: t), segundos: 30 * 60)
                return
            }
        }
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

    // MARK: Foco, preparación y notas

    /// La respuesta al final de un bloque (o al soltarlo antes): hecha, aún no, o cancelado (nil).
    func responderFoco(_ hecha: Bool?) {
        if hecha == true, let t = foco.activo?.titulo { pendientes.focoHecho(t) }
        foco.cerrar(hecha: hecha)
        if case .foco = estado.actividad { quitarActividad() }
        ajustar()
    }

    func extenderFoco(_ minutos: Int) {
        foco.extender(minutos)
        if case .foco = estado.actividad { quitarActividad() }
        ajustar()
    }

    /// Hyper + F con un bloque en curso: muestra cómo va (o la pregunta, si ya terminó).
    func mostrarFoco() {
        guard let b = foco.activo else { return }
        if foco.terminado {
            mostrar(.foco(titulo: b.titulo), segundos: 30)
        } else {
            let falta = Int((foco.restante(en: Date()) / 60).rounded(.up))
            mostrar(.aviso(icono: "timer", texto: "Foco · \(falta) min · \(b.titulo)"), segundos: 3)
        }
    }

    /// "Prepárame" de una reunión (aviso o pestaña Agenda): el panel con lo que sabe el cerebro.
    func preparar(_ evento: Agenda.Evento) {
        cerrarTodas()
        quitarActividad()
        PrepReunion.shared.abrir(evento)
    }

    /// El aviso de la reunión trae solo título e inicio: se busca el evento completo (con sus invitados).
    func preparar(titulo: String, inicio: Date) {
        if let e = agenda.eventos.first(where: { $0.titulo == titulo && abs($0.inicio.timeIntervalSince(inicio)) < 60 }) {
            preparar(e)
        }
    }

    /// La respuesta a "¿grabo la reunión?".
    func responderNotas(_ r: NotasReunion.Respuesta) {
        notas.responder(r)
        if case .notas = estado.actividad { quitarActividad() }
        ajustar()
    }

    /// Hyper + R, el botón de la isla abierta y el menú: grabar o terminar.
    func alternarNotas() {
        if case .notas = estado.actividad, !notas.grabando {
            responderNotas(.grabar)
            return
        }
        notas.alternar()
        ajustar()
    }

    func copiarAvisoNotas() { notas.copiarAviso() }

    // MARK: Cierre del día

    /// Todos los días a la hora del ajuste `cierre` ("18:30" por omisión; "no" lo apaga): un solo temporizador hasta
    /// la próxima, nada en bucle.
    private func programarCierre() {
        relojCierre?.invalidate()
        let ajuste = UserDefaults.dictado.string(forKey: "cierre") ?? "18:30"
        let partes = ajuste.split(separator: ":").compactMap { Int($0) }
        guard partes.count == 2 else { return }
        let cal = Calendar.current
        var cuando = cal.date(bySettingHour: partes[0], minute: partes[1], second: 0, of: Date()) ?? Date()
        if cuando <= Date() { cuando = cal.date(byAdding: .day, value: 1, to: cuando) ?? cuando }
        relojCierre = Timer.scheduledTimer(withTimeInterval: cuando.timeIntervalSinceNow, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.cerrarDia()
                self?.programarCierre()
            }
        }
    }

    /// Le pide al cerebro el cierre (`accion.sh cierre`: junta las reuniones de hoy en `_inbox/cierre-<fecha>.md`) y
    /// pregunta qué hacer con lo que quedó. Sin reuniones ni pendientes, no molesta.
    func cerrarDia(manual: Bool = false) {
        guard let acciones = CentroStore.acciones else {
            if manual { mostrar(.aviso(icono: "moon.stars", texto: "El cierre necesita el Centro configurado"), segundos: 4) }
            return
        }
        Task { [weak self] in
            let (salida, _) = await Task.detached { CentroStore.correr(URL(fileURLWithPath: acciones), ["cierre"], limite: 180) }.value
            struct R: Decodable { var ok: Bool; var captura: String?; var mensaje: String? }
            let r = try? JSONDecoder().decode(R.self, from: salida)
            guard let self else { return }
            self.pendientes.refrescar()
            self.archivoCierre = r?.captura.map { Ajustes().carpetaInbox.deletingLastPathComponent().appendingPathComponent($0).path }
            let quedan = self.pendientes.abiertos
            if quedan > 0 {
                self.mostrar(.cierre(quedan: quedan), segundos: 20 * 60)
            } else if manual {
                self.mostrar(.aviso(icono: "moon.stars", texto: r?.mensaje ?? (r?.ok == true ? "Cierre listo: nada pendiente" : "El cierre falló")), segundos: 4)
            }
        }
    }

    /// Mañana (true): siguen ahí. Soltar (false): dejan de mostrarse. Ver (nil): abre el resumen.
    func responderCierre(_ r: Bool?) {
        if r == false { pendientes.soltarTodos() }
        if r == nil, let a = archivoCierre { NSWorkspace.shared.open(URL(fileURLWithPath: a)) }
        if case .cierre = estado.actividad { quitarActividad() }
        ajustar()
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
                case "reunion":
                    self.notas.eventoEmpezo(Agenda.Evento(id: "prueba-\(UUID())", titulo: "Prueba de reunión", inicio: Date(),
                                                          fin: Date().addingTimeInterval(1800), color: .green,
                                                          personas: ["prueba@ejemplo.com"]))
                case "grabar-prueba":
                    self.notas.empezar(titulo: "Prueba de grabación", prueba: true)
                    self.ajustar()
                case "terminar":
                    self.notas.terminar()
                    self.ajustar()
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
        cara.estado.tamano(alas: musica.hayPista || agenda.inminente != nil || privacidad.activo || claude.hayActividad
                               || foco.activo != nil || notas.grabando || notas.pendiente != nil,
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
