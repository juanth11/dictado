import Foundation

/// "Ahora suena" del sistema: lo mismo que macOS muestra en el Centro de control (Spotify, un video de YouTube en el
/// navegador, Música, un podcast…), con título, artista, duración, posición y qué controles acepta la app.
///
/// Desde macOS 15.4 ese dato (el framework privado MediaRemote) solo se lo da macOS a sus propios programas: Dictado
/// recibe nada. Por eso lo lee `osascript`, que es de Apple, con un script de JavaScript que corre mientras Dictado
/// vive: revisa una vez por segundo y escribe una línea JSON solo cuando algo cambia (la posición viene como una marca
/// de tiempo, así que mientras suena no cambia nada). Si Dictado se cierra, el script lo nota (su padre pasa a ser
/// launchd) y termina solo. No pide permisos.
@MainActor
final class AhoraSuenaSistema {
    struct Info: Decodable, Equatable {
        var app: String?
        var nombre: String?
        var titulo: String?
        var artista: String?
        var duracion: Double?
        var transcurrido: Double?
        /// Cuándo se midió `transcurrido` (segundos desde 1970). La posición real es transcurrido + (ahora − marca) × ritmo.
        var marca: Double?
        var ritmo: Double?
        var sonando: Bool?
        /// Comandos que la app acepta (de MediaRemote): 0 reproducir, 1 pausar, 2 alternar, 4 siguiente, 5 anterior,
        /// 24 saltar a un punto.
        var comandos: [Int]?

        func posicion(en ahora: Date) -> Double {
            let t = transcurrido ?? 0
            guard let marca, let ritmo, ritmo > 0 else { return t }
            return t + (ahora.timeIntervalSince1970 - marca) * ritmo
        }
    }

    private var proceso: Process?
    private var resto = Data()
    private var intentos = 0
    private var parado = false
    private let alCambiar: (Info?) -> Void

    init(alCambiar: @escaping (Info?) -> Void) {
        self.alCambiar = alCambiar
        arrancar()
    }

    func detener() {
        parado = true
        proceso?.terminate()
        proceso = nil
    }

    /// Lleva lo que suena a ese segundo (lo hace la app que suena; YouTube, Música y Spotify lo aceptan).
    nonisolated static func saltar(a segundos: Double) {
        let script = Self.cargar + """
        ObjC.bindFunction("MRMediaRemoteSetElapsedTime", ["void", ["double"]]);
        $.MRMediaRemoteSetElapsedTime(\(String(format: "%.3f", max(0, segundos))));
        """
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        p.arguments = ["-l", "JavaScript", "-e", script]
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        try? p.run()
    }

    private func arrancar() {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        p.arguments = ["-l", "JavaScript", "-e", Self.cargar + Self.vigia]
        let tubo = Pipe()
        p.standardOutput = tubo
        p.standardError = FileHandle.nullDevice
        tubo.fileHandleForReading.readabilityHandler = { [weak self] h in
            let datos = h.availableData
            guard !datos.isEmpty else { return }
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.recibir(datos) } }
        }
        p.terminationHandler = { [weak self] _ in
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.termino() } }
        }
        do {
            try p.run()
            proceso = p
        } catch {
            proceso = nil
        }
    }

    private func recibir(_ datos: Data) {
        resto.append(datos)
        while let fin = resto.firstIndex(of: 0x0A) {
            let linea = resto[resto.startIndex..<fin]
            resto.removeSubrange(resto.startIndex...fin)
            guard let info = try? JSONDecoder().decode(Info.self, from: Data(linea)) else { continue }
            intentos = 0
            alCambiar((info.titulo ?? "").isEmpty ? nil : info)
        }
    }

    /// Si el script se cae (no debería), se vuelve a lanzar unas pocas veces, con espera.
    private func termino() {
        proceso = nil
        guard !parado, intentos < 5 else { return }
        intentos += 1
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
            MainActor.assumeIsolated {
                guard let self, !self.parado, self.proceso == nil else { return }
                self.arrancar()
            }
        }
    }

    private static let cargar = """
    ObjC.import("Foundation");
    $.NSBundle.bundleWithPath("/System/Library/PrivateFrameworks/MediaRemote.framework/").load;

    """

    /// Una línea por cambio; `{}` si no suena nada.
    private static let vigia = """
    ObjC.bindFunction("getppid", ["int", []]);
    const R = $.NSClassFromString("MRNowPlayingRequest");
    const salida = $.NSFileHandle.fileHandleWithStandardOutput;
    const K = "kMRMediaRemoteNowPlayingInfo";
    function nada(v) { return v === undefined || v === null || (v.isNil && v.isNil()); }
    function texto(v) { return nada(v) ? "" : String(ObjC.unwrap(v)); }
    function numero(v) { return nada(v) ? 0 : Number(ObjC.unwrap(v)); }
    function leer() {
      const o = {};
      const item = R.localNowPlayingItem;
      if (nada(item)) return o;
      const info = item.nowPlayingInfo;
      if (nada(info)) return o;
      o.titulo = texto(info.objectForKey(K + "Title"));
      o.artista = texto(info.objectForKey(K + "Artist"));
      o.duracion = numero(info.objectForKey(K + "Duration"));
      o.transcurrido = numero(info.objectForKey(K + "ElapsedTime"));
      o.ritmo = numero(info.objectForKey(K + "PlaybackRate"));
      const marca = info.objectForKey(K + "Timestamp");
      o.marca = nada(marca) ? 0 : marca.timeIntervalSince1970;
      const ruta = R.localNowPlayingPlayerPath;
      if (!nada(ruta) && !nada(ruta.client)) { o.app = texto(ruta.client.bundleIdentifier); o.nombre = texto(ruta.client.displayName); }
      o.sonando = R.localIsPlaying === true;
      const cmds = R.localSupportedCommands;
      o.comandos = [];
      if (!nada(cmds)) for (let i = 0; i < cmds.count; i++) o.comandos.push(numero(cmds.objectAtIndex(i).command));
      return o;
    }
    let ultimo = null;
    while ($.getppid() !== 1) {
      let s;
      try { s = JSON.stringify(leer()); } catch (e) { s = "{}"; }
      if (s !== ultimo) { ultimo = s; salida.writeData($(s + "\\n").dataUsingEncoding($.NSUTF8StringEncoding)); }
      delay(1);
    }
    """
}
