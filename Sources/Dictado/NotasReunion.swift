import AppKit
import Observation

/// Notas de reunión. Pregunta si grabas cuando empieza una reunión del calendario (con invitados o enlace) y cuando el
/// micrófono entra en una llamada; la pregunta se queda en la isla hasta que respondes (Grabar, En 3 min, No). Nunca
/// graba sola, porque es tu decisión y la de avisar a los demás. También se graba a mano: Hyper + R, el botón Grabar de
/// la isla abierta o el menú de Dictado (sirve en una reunión o clase presencial: solo tu micrófono).
///
/// Graba tu micrófono y el audio del Mac en dos pistas, en trozos de 2 minutos (GrabacionReunion.swift), con una ficha
/// `<base>.json` al lado: si Dictado se cierra a mitad, al volver a abrirla transcribe lo que quedó. Al terminar,
/// transcribe todo en el Mac (sin red), arma la transcripción con "Tú:" y "Otros:", la guarda en la carpeta de Dictado y
/// borra el audio. Luego le pide al cerebro las notas (`accion.sh reunion`): un resumen con decisiones y pendientes que
/// queda en tu inbox, con su commit. La transcripción completa no entra al cerebro.
@MainActor @Observable
final class NotasReunion {
    enum Fase: Equatable { case libre, grabando }
    enum Respuesta { case grabar, luego, no }

    private(set) var fase = Fase.libre
    private(set) var desde: Date?
    private(set) var titulo = ""
    /// La pregunta "¿grabo?" sin responder (su título). La isla la vuelve a mostrar si otro aviso la tapa.
    private(set) var pendiente: String?
    /// Grabaciones que se están transcribiendo (no impiden grabar la siguiente).
    private(set) var procesando = 0
    /// Copiaste el aviso de grabación para pegarlo en el chat.
    private(set) var avisaste = false

    /// Para mostrar un aviso en la isla (actividad, segundos).
    @ObservationIgnored var avisar: ((EstadoIsla.Actividad, Double) -> Void)?
    /// Llegaron notas nuevas al inbox (para refrescar los pendientes).
    @ObservationIgnored var alListo: (() -> Void)?

    @ObservationIgnored private let agenda: Agenda
    @ObservationIgnored private let privacidad: Privacidad
    @ObservationIgnored private var personas: [String] = []
    @ObservationIgnored private var inicioReunion: Date?
    @ObservationIgnored private var microfono: GrabadorMicrofono?
    @ObservationIgnored private var sistema: GrabadorSistema?
    @ObservationIgnored private var base: String?
    @ObservationIgnored private var ofrecida = false
    /// La grabación empezó con otra app usando el micrófono (una llamada): al colgar, se cierra sola.
    @ObservationIgnored private var porLlamada = false
    @ObservationIgnored private var oferta: DispatchWorkItem?
    @ObservationIgnored private var silencio: DispatchWorkItem?
    @ObservationIgnored private var vencimiento: DispatchWorkItem?
    @ObservationIgnored private var repregunta: DispatchWorkItem?
    @ObservationIgnored private var revision: DispatchWorkItem?
    @ObservationIgnored private var tope: DispatchWorkItem?
    /// El evento de la pregunta abierta, los que ya se volvieron a preguntar y los que dijiste que no son reunión.
    @ObservationIgnored private var eventoPendiente: String?
    @ObservationIgnored private var repreguntados = Set<String>()
    @ObservationIgnored private var ignorados = Set<String>()

    static let carpeta = URL(fileURLWithPath: NSHomeDirectory() + "/Library/Application Support/app.dictado/reuniones")
    /// Apps de llamadas; los navegadores cuentan porque Meet y Teams suelen ir ahí (Arc, Chrome, Safari…).
    private static let appsDeLlamada = ["zoom", "teams", "meet", "facetime", "slack", "whatsapp", "discord", "webex", "skype",
                                        "arc", "chrome", "safari", "brave", "edge", "firefox", "comet", "dia"]
    /// Una grabación olvidada se cierra sola a las 5 horas.
    private static let maximo: Double = 5 * 3600
    static let textoAviso = "Hola a todos: voy a tomar notas de esta reunión con una transcripción en mi computador, "
        + "para no perder los acuerdos. Si alguien prefiere que no, me avisa y la detengo."

    init(agenda: Agenda, privacidad: Privacidad, vivo: Bool = true) {
        self.agenda = agenda
        self.privacidad = privacidad
        guard vivo else { return }
        // Lo que quedó de una grabación que no terminó (Dictado se cerró a mitad): se transcribe al abrir.
        DispatchQueue.main.asyncAfter(deadline: .now() + 6) { [weak self] in MainActor.assumeIsolated { self?.recuperar() } }
    }

    var grabando: Bool { fase == .grabando }

    // MARK: Cuándo preguntar

    /// Empezó una reunión del calendario (la avisa la agenda).
    func eventoEmpezo(_ e: Agenda.Evento) {
        guard fase == .libre, !ignorados.contains(e.id) else { return }
        ofrecer(e.titulo, evento: e.id, hasta: e.fin)
    }

    /// Lo avisa la isla cuando otra app empieza o deja de usar el micrófono.
    func microfonoCambio(_ enUso: Bool) {
        if enUso {
            silencio?.cancel()
            silencio = nil
            guard fase == .libre, !ofrecida, pendiente == nil else { return }
            // Unos segundos de margen: una nota de voz o una prueba de micrófono no son una llamada.
            let tarea = DispatchWorkItem { [weak self] in MainActor.assumeIsolated { self?.ofrecerLlamada() } }
            oferta = tarea
            DispatchQueue.main.asyncAfter(deadline: .now() + 8, execute: tarea)
        } else {
            oferta?.cancel()
            oferta = nil
            ofrecida = false
            // Solo si grababas una llamada: en una reunión presencial, otra app que suelta el micrófono no la corta.
            guard fase == .grabando, porLlamada else { return }
            // Colgaste: si en 20 s el micrófono no vuelve, se cierran las notas.
            let tarea = DispatchWorkItem { [weak self] in MainActor.assumeIsolated { self?.terminar() } }
            silencio = tarea
            DispatchQueue.main.asyncAfter(deadline: .now() + 20, execute: tarea)
        }
    }

    /// La reunión en curso (con invitados o enlace) más cercana a ahora; los bloques sin invitados no cuentan, para que
    /// una clase vieja o el almuerzo no le pongan su título a la grabación.
    private var eventoActual: Agenda.Evento? {
        let ahora = Date()
        return agenda.eventos
            .filter { $0.esReunion && $0.inicio.timeIntervalSince(ahora) < 600 && $0.fin > ahora && !ignorados.contains($0.id) }
            .min { abs($0.inicio.timeIntervalSince(ahora)) < abs($1.inicio.timeIntervalSince(ahora)) }
    }

    private var esLlamada: Bool {
        eventoActual != nil || privacidad.camara
            || Self.appsDeLlamada.contains { privacidad.nombre.localizedCaseInsensitiveContains($0) }
    }

    private func ofrecerLlamada() {
        guard fase == .libre, pendiente == nil, privacidad.microfono, esLlamada else { return }
        ofrecida = true
        let e = eventoActual
        ofrecer(e?.titulo ?? "Llamada en \(privacidad.nombre.isEmpty ? "el Mac" : privacidad.nombre)", evento: e?.id,
                hasta: e?.fin ?? Date().addingTimeInterval(30 * 60))
    }

    /// Abre la pregunta y la deja hasta que respondes, hasta que termina la reunión o, como mucho, 30 minutos.
    private func ofrecer(_ t: String, evento: String?, hasta: Date) {
        pendiente = t
        titulo = t
        eventoPendiente = evento
        let segundos = min(30 * 60, max(60, hasta.timeIntervalSinceNow))
        vencimiento?.cancel()
        let tarea = DispatchWorkItem { [weak self] in MainActor.assumeIsolated { self?.cerrarPregunta() } }
        vencimiento = tarea
        DispatchQueue.main.asyncAfter(deadline: .now() + segundos, execute: tarea)
        avisar?(.notas(titulo: t), segundos)
    }

    private func cerrarPregunta() {
        pendiente = nil
        eventoPendiente = nil
        vencimiento?.cancel()
        vencimiento = nil
    }

    /// La respuesta a "¿grabo?". "En 3 min" vuelve a preguntar una sola vez; "No" no vuelve a preguntar por ese evento.
    func responder(_ r: Respuesta) {
        let evento = eventoPendiente
        let t = pendiente ?? titulo
        cerrarPregunta()
        switch r {
        case .grabar:
            empezar(titulo: t)
        case .no:
            if let evento { ignorados.insert(evento) }
        case .luego:
            let clave = evento ?? t
            guard !repreguntados.contains(clave) else { return }
            repreguntados.insert(clave)
            repregunta?.cancel()
            let tarea = DispatchWorkItem { [weak self] in
                MainActor.assumeIsolated {
                    guard let self, self.fase == .libre, self.pendiente == nil else { return }
                    let e = evento.flatMap { id in self.agenda.eventos.first { $0.id == id } }
                    if evento != nil && (e == nil || e!.fin < Date()) { return }
                    self.ofrecer(t, evento: evento, hasta: e?.fin ?? Date().addingTimeInterval(20 * 60))
                }
            }
            repregunta = tarea
            DispatchQueue.main.asyncAfter(deadline: .now() + 180, execute: tarea)
        }
    }

    // MARK: Grabar

    /// Hyper + R, el botón de la isla y el menú: graba si no estás grabando; si estás grabando, termina.
    func alternar() {
        if grabando { terminar() } else { empezar(titulo: pendiente) }
    }

    func copiarAviso() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(Self.textoAviso, forType: .string)
        avisaste = true
        avisar?(.aviso(icono: "doc.on.clipboard", texto: "Aviso copiado: pégalo en el chat de la reunión"), 3)
    }

    /// `prueba`: no le pide las notas al cerebro (para verificar la grabación sin dejar nada en el inbox).
    func empezar(titulo elegido: String? = nil, prueba: Bool = false) {
        guard fase == .libre else { return }
        cerrarPregunta()
        let e = eventoActual
        if let elegido, !elegido.isEmpty {
            titulo = elegido
        } else if let e {
            titulo = e.titulo
        } else {
            let f = DateFormatter()
            f.dateFormat = "HH:mm"
            titulo = "Reunión de las \(f.string(from: Date()))"
        }
        personas = (e?.titulo == titulo ? e?.personas : nil) ?? []
        inicioReunion = e?.titulo == titulo ? e?.inicio : Date()
        avisaste = false
        let ahora = Date()
        let b = Self.carpeta.appendingPathComponent(Self.marca(ahora) + "-" + Self.slug(titulo)).path
        porLlamada = privacidad.microfono
        do {
            try FileManager.default.createDirectory(at: Self.carpeta, withIntermediateDirectories: true)
            try Ficha(titulo: titulo, personas: personas, inicio: inicioReunion ?? ahora, desde: ahora, prueba: prueba).guardar(b)
            let m = GrabadorMicrofono()
            try m.empezar(base: b + "-tu", desde: ahora)
            microfono = m
            let s = GrabadorSistema()
            var conSistema = true
            do {
                try s.empezar(base: b + "-otros", desde: ahora)
                sistema = s
            } catch {
                conSistema = false
                avisar?(.aviso(icono: "exclamationmark.triangle", texto: "Solo tu voz: falta el permiso de audio del sistema"), 5)
            }
            base = b
            desde = ahora
            fase = .grabando
            if conSistema { avisar?(.aviso(icono: "record.circle", texto: "Grabando · Hyper + R para terminar"), 3) }
            vigilarAudio()
        } catch {
            microfono?.detener()
            microfono = nil
            try? FileManager.default.removeItem(atPath: b + ".json")
            avisar?(.aviso(icono: "exclamationmark.triangle", texto: "No se pudo grabar: \(error.localizedDescription)"), 6)
        }
    }

    /// A los 15 s revisa que entre audio del micrófono (el 15-oct quedó un archivo vacío sin que nadie se enterara) y
    /// pone el tope de 5 horas.
    private func vigilarAudio() {
        revision?.cancel()
        let r = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.grabando, let m = self.microfono else { return }
                if m.cuadros == 0 {
                    self.avisar?(.aviso(icono: "mic.slash", texto: "No entra audio del micrófono: revisa la entrada de sonido"), 10)
                } else if m.pico < 0.0005 {
                    self.avisar?(.aviso(icono: "mic.slash", texto: "El micrófono está en silencio: ¿está silenciado?"), 8)
                }
            }
        }
        revision = r
        DispatchQueue.main.asyncAfter(deadline: .now() + 15, execute: r)
        tope?.cancel()
        let t = DispatchWorkItem { [weak self] in MainActor.assumeIsolated { self?.terminar() } }
        tope = t
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.maximo, execute: t)
    }

    func terminar() {
        guard fase == .grabando, let base else { return }
        for t in [silencio, revision, tope] { t?.cancel() }
        silencio = nil
        microfono?.detener()
        sistema?.detener()
        microfono = nil
        sistema = nil
        let duracion = Date().timeIntervalSince(desde ?? Date())
        var ficha = Ficha.leer(base) ?? Ficha(titulo: titulo, personas: personas, inicio: inicioReunion ?? Date(), desde: desde ?? Date())
        ficha.aviso = avisaste
        fase = .libre
        desde = nil
        self.base = nil
        transcribir(base, ficha, duracion: duracion)
    }

    private func transcribir(_ base: String, _ ficha: Ficha, duracion: TimeInterval) {
        procesando += 1
        avisar?(.aviso(icono: "waveform", texto: "Transcribiendo «\(ficha.titulo)» en el Mac… (unos minutos)"), 6)
        let datos = Datos(titulo: ficha.titulo, personas: ficha.personas, inicio: ficha.inicio, duracion: duracion,
                          idioma: UserDefaults.dictado.string(forKey: "idioma") ?? "es-US", vocabulario: Ajustes().vocabulario(),
                          acciones: ficha.prueba ? nil : CentroStore.acciones, aviso: ficha.aviso)
        Task { [weak self] in
            let (texto, bien) = await Self.procesar(base: base, datos)
            guard let self else { return }
            self.procesando -= 1
            if bien { self.alListo?() }
            self.avisar?(.aviso(icono: bien ? "checkmark.circle" : "exclamationmark.triangle", texto: bien ? texto + " · Centro → Notas" : texto), 12)
        }
    }

    /// Fichas sin cerrar en la carpeta de reuniones: grabaciones que Dictado no alcanzó a terminar.
    private func recuperar() {
        let archivos = (try? FileManager.default.contentsOfDirectory(at: Self.carpeta, includingPropertiesForKeys: nil)) ?? []
        for a in archivos where a.pathExtension == "json" {
            let b = a.deletingPathExtension().path
            guard b != base, var ficha = Ficha.leer(b) else { continue }
            // Tres intentos como mucho: si el audio no se deja leer, se deja quieto (y el archivo, para revisarlo a mano).
            guard ficha.intentos < 3 else { continue }
            ficha.intentos += 1
            try? ficha.guardar(b)
            let trozos = Trozos.de(b + "-tu") + Trozos.de(b + "-otros")
            guard let ultimo = trozos.map(\.desde).max() else {
                try? FileManager.default.removeItem(at: a)   // no alcanzó a grabar nada
                continue
            }
            avisar?(.aviso(icono: "arrow.clockwise", texto: "Recuperé la grabación de «\(ficha.titulo)»"), 4)
            transcribir(b, ficha, duracion: ultimo + Trozos.segundos)
        }
    }

    /// Lo que se guarda junto al audio mientras se graba (`<base>.json`).
    struct Ficha: Codable {
        var titulo: String
        var personas: [String]
        var inicio: Date
        var desde: Date
        var aviso = false
        var prueba = false
        var intentos = 0

        init(titulo: String, personas: [String], inicio: Date, desde: Date, aviso: Bool = false, prueba: Bool = false) {
            self.titulo = titulo
            self.personas = personas
            self.inicio = inicio
            self.desde = desde
            self.aviso = aviso
            self.prueba = prueba
        }

        init(from d: Decoder) throws {
            let c = try d.container(keyedBy: CodingKeys.self)
            titulo = try c.decode(String.self, forKey: .titulo)
            personas = try c.decodeIfPresent([String].self, forKey: .personas) ?? []
            inicio = try c.decode(Date.self, forKey: .inicio)
            desde = try c.decode(Date.self, forKey: .desde)
            aviso = try c.decodeIfPresent(Bool.self, forKey: .aviso) ?? false
            prueba = try c.decodeIfPresent(Bool.self, forKey: .prueba) ?? false
            intentos = try c.decodeIfPresent(Int.self, forKey: .intentos) ?? 0
        }

        func guardar(_ base: String) throws {
            let c = JSONEncoder()
            c.dateEncodingStrategy = .iso8601
            try c.encode(self).write(to: URL(fileURLWithPath: base + ".json"), options: .atomic)
        }

        static func leer(_ base: String) -> Ficha? {
            let d = JSONDecoder()
            d.dateDecodingStrategy = .iso8601
            return (try? Data(contentsOf: URL(fileURLWithPath: base + ".json"))).flatMap { try? d.decode(Ficha.self, from: $0) }
        }
    }

    // MARK: Transcribir y mandar al cerebro

    struct Datos: Sendable {
        let titulo: String
        let personas: [String]
        let inicio: Date
        let duracion: TimeInterval
        let idioma: String
        /// Tus palabras del dictado (nombres de clientes, marcas): ayudan a que salgan bien escritas.
        var vocabulario: [String] = []
        let acciones: String?
        /// Copiaste el aviso de grabación (queda anotado en la transcripción).
        var aviso = false
    }

    /// Una grabación por su base: transcribe los trozos de las dos pistas, guarda `<base>.md`, pide las notas y borra la
    /// ficha. Si la transcripción falla, el audio y la ficha se quedan para no perder la reunión.
    nonisolated static func procesar(base: String, _ d: Datos) async -> (String, Bool) {
        let r = await procesar(tu: Trozos.de(base + "-tu"), otros: Trozos.de(base + "-otros"),
                               md: URL(fileURLWithPath: base + ".md"), d)
        if r.1 || (Trozos.de(base + "-tu") + Trozos.de(base + "-otros")).isEmpty {
            try? FileManager.default.removeItem(atPath: base + ".json")
        }
        return r
    }

    /// Transcribe las dos pistas (cada una en trozos, con el segundo en que empieza cada trozo), las mezcla por tiempo
    /// y pide las notas al cerebro. Devuelve el aviso y si salió bien.
    nonisolated static func procesar(tu: [(url: URL, desde: Double)], otros: [(url: URL, desde: Double)], md ruta: URL,
                                     _ d: Datos) async -> (String, Bool) {
        func pista(_ trozos: [(url: URL, desde: Double)]) async -> (lineas: [(inicio: Double, texto: String)], fallos: Int) {
            var lineas: [(inicio: Double, texto: String)] = []
            var fallos = 0
            for t in trozos {
                do {
                    let partes = try await Transcripcion.transcribirConTiempos(t.url, idioma: d.idioma, vocabulario: d.vocabulario)
                    lineas += partes.map { ($0.inicio + t.desde, $0.texto) }
                } catch {
                    fallos += 1
                }
            }
            return (lineas, fallos)
        }
        guard !tu.isEmpty || !otros.isEmpty else { return ("No quedó audio de la reunión", false) }
        let a = await pista(tu)
        let b = await pista(otros)
        if a.fallos + b.fallos == tu.count + otros.count {
            return ("No se pudo transcribir; el audio quedó guardado en la carpeta de Dictado", false)
        }
        let lineas = mezclar(a.lineas, b.lineas)
        (tu + otros).forEach { try? FileManager.default.removeItem(at: $0.url) }
        guard !lineas.isEmpty else { return ("La grabación quedó en silencio: no hay notas", false) }

        do {
            try markdown(lineas, d).write(to: ruta, atomically: true, encoding: .utf8)
        } catch {
            return ("No se pudo guardar la transcripción", false)
        }
        guard let acciones = d.acciones else { return ("Transcripción guardada en el Mac (sin script de acciones para el resumen)", true) }
        var argumentos = ["reunion", "--titulo", d.titulo, "--inicio", ISO8601DateFormatter().string(from: d.inicio),
                          "--transcripcion", ruta.path]
        for p in d.personas { argumentos += ["--persona", p] }
        let (salida, fallo) = CentroStore.correr(URL(fileURLWithPath: acciones), argumentos, limite: 180)
        struct Respuesta: Decodable { var ok: Bool; var captura: String?; var error: String? }
        guard let r = try? JSONDecoder().decode(Respuesta.self, from: salida) else {
            return ("Transcripción guardada; el cerebro no respondió (\(fallo ?? "sin respuesta"))", false)
        }
        return r.ok ? ("Notas listas en tu inbox", true) : ("Transcripción guardada; el resumen falló: \(r.error ?? "")", false)
    }

    /// Las dos pistas en orden de tiempo; los tramos seguidos de la misma persona se juntan.
    nonisolated static func mezclar(_ tu: [(inicio: Double, texto: String)], _ otros: [(inicio: Double, texto: String)])
        -> [(inicio: Double, quien: String, texto: String)] {
        let todas = (tu.map { ($0.inicio, "Tú", $0.texto) } + otros.map { ($0.inicio, "Otros", $0.texto) }).sorted { $0.0 < $1.0 }
        var salida: [(inicio: Double, quien: String, texto: String)] = []
        for (inicio, quien, texto) in todas {
            if let ultima = salida.last, ultima.quien == quien {
                salida[salida.count - 1].texto += " " + texto
            } else {
                salida.append((inicio, quien, texto))
            }
        }
        return salida
    }

    nonisolated static func markdown(_ lineas: [(inicio: Double, quien: String, texto: String)], _ d: Datos) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "es_CO")
        f.dateFormat = "yyyy-MM-dd HH:mm"
        var t = ["# \(d.titulo)", "", "- Inicio: \(f.string(from: d.inicio)) · duración: \(Int((d.duracion / 60).rounded())) min"]
        if !d.personas.isEmpty { t.append("- Personas: \(d.personas.joined(separator: ", "))") }
        t.append("- Aviso de grabación a los demás: " + (d.aviso ? "copiado para el chat" : "no registrado"))
        t += ["- Transcripción automática en el Mac. \"Tú\" es tu micrófono; \"Otros\", el audio del Mac (la llamada).", ""]
        for l in lineas {
            let s = Int(l.inicio)
            t.append(String(format: "[%02d:%02d] ", s / 60, s % 60) + "\(l.quien): \(l.texto)")
            t.append("")
        }
        return t.joined(separator: "\n")
    }

    private static func marca(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMddHHmm"
        return f.string(from: d)
    }

    private static func slug(_ t: String) -> String {
        let plano = t.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current).lowercased()
        let s = plano.replacingOccurrences(of: "[^a-z0-9]+", with: "-", options: .regularExpression).trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return String(s.prefix(40)).isEmpty ? "reunion" : String(s.prefix(40))
    }
}
