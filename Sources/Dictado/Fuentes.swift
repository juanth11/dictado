import AppKit
import ApplicationServices
import CoreAudio
import Observation

/// Qué suena en el Mac y por dónde, para el reproductor de la isla. No pide permisos nuevos:
/// - las apps que mandan sonido a la salida salen de CoreAudio (macOS 14.2+);
/// - qué suena en cada una sale del título de sus ventanas (Accesibilidad, que Dictado ya tiene): en un navegador,
///   la pestaña (por ejemplo, el video de YouTube);
/// - las salidas de sonido (altavoces, AirPods, pantalla, AirPlay) y cuál es la actual, también de CoreAudio.
/// Solo se consulta con la isla abierta (cada 2 s) y al tocar algo: en reposo no cuesta nada.
@MainActor @Observable
final class Fuentes {
    struct Fuente: Identifiable, Equatable {
        let id: String          // identificador de la app
        let pid: pid_t
        let nombre: String      // "Spotify", "Arc"
        let icono: NSImage?
        var titulo = ""         // lo que suena, del título de la ventana ("Lo-fi para trabajar")
        var servicio: String?   // "YouTube" si el título lo dice

        var esSpotify: Bool { id == "com.spotify.client" }
        /// "YouTube · Arc", o solo "Arc".
        var detalle: String { servicio.map { "\($0) · \(nombre)" } ?? nombre }
    }

    struct Salida: Identifiable, Equatable {
        let id: AudioDeviceID
        let nombre: String
        let simbolo: String
    }

    var sonando: [Fuente] = []
    var salidas: [Salida] = []
    var salidaActual: AudioDeviceID?
    /// La fuente que muestra el reproductor (nil: Spotify si tiene canción; si no, la primera que suena).
    var elegida: String?
    var mostrandoSalidas = false

    private let vivo: Bool

    init(vivo: Bool = true) {
        self.vivo = vivo
    }

    func refrescar() {
        guard vivo else { return }
        var vistas = Set<String>()
        var nuevas: [Fuente] = []
        for (pid, _) in Audio.procesosSonando() {
            let dueno = Self.responsable?(pid) ?? pid
            guard let app = NSRunningApplication(processIdentifier: dueno > 0 ? dueno : pid) ?? NSRunningApplication(processIdentifier: pid),
                  app.activationPolicy == .regular, let id = app.bundleIdentifier, id != Bundle.main.bundleIdentifier,
                  !vistas.contains(id) else { continue }
            vistas.insert(id)
            var f = Fuente(id: id, pid: app.processIdentifier, nombre: app.localizedName ?? id,
                           icono: app.icon.map { Privacidad.mapaDeBits($0, lado: 50) })
            let (titulo, servicio) = Self.queSuena(app.processIdentifier)
            f.titulo = titulo
            f.servicio = servicio
            nuevas.append(f)
        }
        if nuevas != sonando { sonando = nuevas }
        let lista = Audio.salidas().compactMap { id -> Salida? in
            guard let nombre = Audio.nombre(id), !nombre.isEmpty else { return nil }
            return Salida(id: id, nombre: nombre, simbolo: SalidaAudio(nombre: nombre, integrado: Audio.integrado(id)).simbolo)
        }
        if lista != salidas { salidas = lista }
        let actual = Audio.salida()
        if actual != salidaActual { salidaActual = actual }
    }

    /// Cambia por dónde suena el Mac (las apps y los sonidos del sistema).
    func ponerSalida(_ s: Salida) {
        _ = Audio.ponerSalida(s.id)
        refrescar()
    }

    /// Trae al frente la app de esa fuente (para ver el video o la pestaña).
    func irA(_ f: Fuente) {
        NSRunningApplication(processIdentifier: f.pid)?.activate()
    }

    // MARK: Qué suena

    private typealias Responsable = @convention(c) (pid_t) -> pid_t
    private static let responsable: Responsable? = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "responsibility_get_pid_responsible_for_pid")
        .map { unsafeBitCast($0, to: Responsable.self) }

    private static let servicios = [("youtube", "YouTube"), ("youtube music", "YouTube Music"), ("soundcloud", "SoundCloud"),
                                    ("twitch", "Twitch"), ("netflix", "Netflix"), ("spotify", "Spotify"), ("apple music", "Apple Music"),
                                    ("vimeo", "Vimeo"), ("disney+", "Disney+"), ("prime video", "Prime Video")]

    /// El título que mejor dice qué suena: entre las ventanas de la app, la que nombra un servicio conocido
    /// (YouTube, SoundCloud…); si ninguna, la ventana principal. Le quita el " - YouTube" y el "(3) " de avisos.
    private static func queSuena(_ pid: pid_t) -> (String, String?) {
        let app = AXUIElementCreateApplication(pid)
        var valor: CFTypeRef?
        var titulos: [String] = []
        if AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &valor) == .success,
           let ventanas = valor as? [AXUIElement] {
            for v in ventanas.prefix(12) {
                var t: CFTypeRef?
                if AXUIElementCopyAttributeValue(v, kAXTitleAttribute as CFString, &t) == .success, let s = t as? String, !s.isEmpty {
                    titulos.append(s)
                }
            }
        }
        for t in titulos {
            let bajo = t.lowercased()
            if let (clave, nombre) = servicios.last(where: { bajo.contains($0.0) }) {
                return (limpiar(t, quitando: clave), nombre)
            }
        }
        return (titulos.first.map { limpiar($0, quitando: nil) } ?? "", nil)
    }

    private static func limpiar(_ titulo: String, quitando servicio: String?) -> String {
        var t = titulo
        if let r = t.range(of: #"^\(\d+\)\s*"#, options: .regularExpression) { t.removeSubrange(r) }  // "(3) " de avisos
        if let servicio, let r = t.range(of: #"\s*[-–—|]\s*"# + NSRegularExpression.escapedPattern(for: servicio) + ".*$",
                                         options: [.regularExpression, .caseInsensitive]) {
            t.removeSubrange(r)
        }
        return t.trimmingCharacters(in: .whitespaces)
    }
}
