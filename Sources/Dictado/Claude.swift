import AppKit
import CoreServices
import Observation

/// Sesiones de Claude Code abiertas (app de escritorio y terminal), para la isla.
///
/// Fuente: ~/.claude/sessions/<pid>.json, que cada sesión mantiene al día con su nombre, carpeta y estado
/// (busy = trabajando, waiting = te necesita: permiso o pregunta, idle = lista). Los tokens salen de los
/// JSONL de ~/.claude/projects. Todo es SOLO LECTURA (contrato de observabilidad de CLAUDE.md: jamás se
/// escribe en ~/.claude). FSEvents avisa cada cambio; no se consulta en bucle.
@MainActor @Observable
final class SesionesClaude {
    enum Estado { case trabajando, esperando, lista }

    struct Sesion: Identifiable, Equatable {
        let id: String
        let pid: Int32
        let nombre: String
        let carpeta: String
        let estado: Estado
        let espera: String      // qué necesita, en español ("" si nada)
        let desde: Date         // desde cuándo está en ese estado
        var contexto = 0        // tokens en el contexto de la última respuesta
        var host: String?       // id de la app de escritorio (local_…), para abrir justo esa sesión
        var actividad = ""      // qué hace ahora o qué te pide ("Editando Isla.swift", "Bash · swift build")
        var resumen = ""        // primera línea de su última respuesta
    }

    var sesiones: [Sesion] = []
    var tokensHoy = 0           // tokens generados hoy (salida), todas las sesiones
    var respuestasHoy = 0
    var porHora = [Int](repeating: 0, count: 24)

    var trabajando: Int { sesiones.filter { $0.estado == .trabajando }.count }
    var esperando: [Sesion] { sesiones.filter { $0.estado == .esperando } }
    var hayActividad: Bool { sesiones.contains { $0.estado != .lista } }

    @ObservationIgnored var alTerminar: ((Sesion, TimeInterval) -> Void)?
    @ObservationIgnored var alNecesitar: ((Sesion) -> Void)?
    @ObservationIgnored private var flujo: FSEventStreamRef?
    @ObservationIgnored private var previos: [String: (estado: Estado, desde: Date)] = [:]
    @ObservationIgnored private var pendiente = false
    @ObservationIgnored private let uso = UsoClaude()
    @ObservationIgnored private var relojActividad: Timer?

    static let carpeta = URL(fileURLWithPath: NSHomeDirectory() + "/.claude/sessions")
    static let app = "com.anthropic.claudefordesktop"

    init(vivo: Bool = true) {
        guard vivo else { return }
        vigilar()
        leer(avisar: false)
    }

    /// Abre justo esa sesión en la app de escritorio con sus enlaces oficiales (claude://code/continue y
    /// claude://code/needs-input, los mismos del menú del Dock). Sin sesión, trae Claude al frente.
    static func abrir(_ sesion: Sesion? = nil) {
        if let sesion, let host = sesion.host {
            var c = URLComponents()
            c.scheme = "claude"
            c.host = "code"
            c.path = sesion.estado == .esperando ? "/needs-input" : "/continue"
            c.queryItems = [URLQueryItem(name: "session", value: host)]
            if let url = c.url, NSWorkspace.shared.open(url) { return }
        }
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: app) {
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
        }
    }

    /// Mientras la isla está abierta, cada 2 s se mira qué hace cada sesión activa (cola de su transcripto).
    func vigilarActividad(_ si: Bool) {
        relojActividad?.invalidate()
        relojActividad = nil
        guard si else { return }
        refrescarActividad()
        relojActividad = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refrescarActividad() }
        }
    }

    private func refrescarActividad() {
        let ids = sesiones.map(\.id)
        guard !ids.isEmpty else { return }
        Task.detached(priority: .utility) {
            var lecturas: [String: Transcripto.Lectura] = [:]
            for id in ids { lecturas[id] = Transcripto.leer(id) }
            await MainActor.run { [weak self] in
                guard let self else { return }
                let nuevas = self.sesiones.map { s -> Sesion in
                    var s = s
                    if let l = lecturas[s.id] { s.aplicar(l) }
                    return s
                }
                if nuevas != self.sesiones { self.sesiones = nuevas }
            }
        }
    }

    /// Tokens del día y contexto de cada sesión. Lee en segundo plano solo lo nuevo de cada JSONL.
    func actualizarUso() {
        let ids = sesiones.map(\.id)
        let uso = self.uso
        Task.detached(priority: .utility) {
            let resultado = uso.calcular(sesiones: ids)
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.tokensHoy = resultado.tokens
                self.respuestasHoy = resultado.respuestas
                self.porHora = resultado.porHora
                self.sesiones = self.sesiones.map { s in
                    var s = s
                    s.contexto = resultado.contexto[s.id] ?? s.contexto
                    return s
                }
            }
        }
    }

    // MARK: Lectura

    private func vigilar() {
        var contexto = FSEventStreamContext(version: 0, info: Unmanaged.passUnretained(self).toOpaque(),
                                            retain: nil, release: nil, copyDescription: nil)
        guard let nuevo = FSEventStreamCreate(nil, { _, info, _, _, _, _ in
            guard let info else { return }
            let yo = Unmanaged<SesionesClaude>.fromOpaque(info).takeUnretainedValue()
            MainActor.assumeIsolated { yo.programarLectura() }
        }, &contexto, [Self.carpeta.path] as CFArray, FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 0.3,
           FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagNoDefer)) else { return }
        FSEventStreamSetDispatchQueue(nuevo, .main)
        FSEventStreamStart(nuevo)
        flujo = nuevo
    }

    private func programarLectura() {
        guard !pendiente else { return }
        pendiente = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            MainActor.assumeIsolated {
                self?.pendiente = false
                self?.leer(avisar: true)
            }
        }
    }

    func leer(avisar: Bool) {
        let archivos = (try? FileManager.default.contentsOfDirectory(at: Self.carpeta, includingPropertiesForKeys: nil)) ?? []
        var nuevas: [Sesion] = []
        for url in archivos where url.pathExtension == "json" {
            guard let datos = try? Data(contentsOf: url),
                  let d = try? JSONSerialization.jsonObject(with: datos) as? [String: Any],
                  let pid = (d["pid"] as? NSNumber)?.int32Value, kill(pid, 0) == 0,  // proceso vivo
                  let id = d["sessionId"] as? String else { continue }
            let estado: Estado
            switch d["status"] as? String {
            case "busy": estado = .trabajando
            case "waiting": estado = .esperando
            default: estado = .lista
            }
            let ms = (d["statusUpdatedAt"] as? NSNumber)?.doubleValue ?? (d["updatedAt"] as? NSNumber)?.doubleValue ?? 0
            let cwd = d["cwd"] as? String ?? ""
            let anterior = sesiones.first { $0.id == id }
            nuevas.append(Sesion(id: id, pid: pid,
                                 nombre: (d["name"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? URL(fileURLWithPath: cwd).lastPathComponent,
                                 carpeta: URL(fileURLWithPath: cwd).lastPathComponent,
                                 estado: estado, espera: estado == .esperando ? Self.espera(d["waitingFor"]) : "",
                                 desde: Date(timeIntervalSince1970: ms / 1000), contexto: anterior?.contexto ?? 0,
                                 host: d["hostSessionId"] as? String,
                                 actividad: anterior?.actividad ?? "", resumen: anterior?.resumen ?? ""))
        }
        // Primero lo que te necesita, luego lo que trabaja, luego lo más reciente.
        nuevas.sort { a, b in
            let pa = a.estado == .esperando ? 0 : (a.estado == .trabajando ? 1 : 2)
            let pb = b.estado == .esperando ? 0 : (b.estado == .trabajando ? 1 : 2)
            return pa != pb ? pa < pb : a.desde > b.desde
        }
        if avisar {
            for s in nuevas {
                guard let antes = previos[s.id], antes.estado != s.estado else { continue }
                let necesita = s.estado == .esperando
                let termino = antes.estado == .trabajando && s.estado == .lista
                guard necesita || termino else { continue }
                let duracion = s.desde.timeIntervalSince(antes.desde)
                // El detalle (qué pide, con qué terminó) sale de la cola del transcripto, fuera del hilo principal.
                Task.detached(priority: .userInitiated) {
                    let lectura = Transcripto.leer(s.id)
                    await MainActor.run { [weak self] in
                        var s = s
                        s.aplicar(lectura)
                        if necesita { self?.alNecesitar?(s) } else { self?.alTerminar?(s, duracion) }
                    }
                }
            }
        }
        previos = Dictionary(uniqueKeysWithValues: nuevas.map { ($0.id, ($0.estado, $0.desde)) })
        if nuevas != sesiones { sesiones = nuevas }
    }

    /// "waitingFor" viene como texto ("dialog open", "input needed", "goal proposal", "sandbox request").
    private static func espera(_ valor: Any?) -> String {
        let texto: String
        if let s = valor as? String {
            texto = s
        } else if let d = valor as? [String: Any] {
            texto = (d["type"] ?? d["kind"] ?? d["tool"] ?? d["name"]).map { "\($0)" } ?? ""
        } else {
            texto = ""
        }
        let t = texto.lowercased()
        if t.contains("dialog") || t.contains("permission") { return "Necesita tu permiso" }
        if t.contains("input") || t.contains("question") { return "Tiene una pregunta" }
        if t.contains("goal") { return "Propone un objetivo" }
        if t.contains("sandbox") { return "Pide salir del sandbox" }
        if t.contains("plan") { return "Plan listo para revisar" }
        return "Te necesita"
    }
}

/// Cuenta tokens leyendo los JSONL de ~/.claude/projects (solo lectura, solo lo agregado desde la última vez).
final class UsoClaude: @unchecked Sendable {
    struct Resultado { var tokens = 0, respuestas = 0, contexto: [String: Int] = [:], porHora = [Int](repeating: 0, count: 24) }

    private let cola = DispatchQueue(label: "dictado.uso-claude")
    private var dia = ""
    private var desplazamientos: [String: UInt64] = [:]
    private var vistos = Set<String>()
    private var acumulado = Resultado()

    func calcular(sesiones: [String]) -> Resultado {
        cola.sync {
            let hoy = Self.dia(Date())
            if hoy != dia {  // día nuevo: empezar de cero
                dia = hoy
                desplazamientos = [:]
                vistos = []
                acumulado = Resultado()
            }
            let raiz = URL(fileURLWithPath: NSHomeDirectory() + "/.claude/projects")
            let inicioDia = Calendar.current.startOfDay(for: Date())
            let proyectos = (try? FileManager.default.contentsOfDirectory(at: raiz, includingPropertiesForKeys: nil)) ?? []
            for proyecto in proyectos {
                let archivos = (try? FileManager.default.contentsOfDirectory(
                    at: proyecto, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
                for archivo in archivos where archivo.pathExtension == "jsonl" {
                    let modificado = (try? archivo.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
                    guard let modificado, modificado >= inicioDia else { continue }
                    leer(archivo, sesion: archivo.deletingPathExtension().lastPathComponent, rastrear: sesiones)
                }
            }
            return acumulado
        }
    }

    private func leer(_ archivo: URL, sesion: String, rastrear: [String]) {
        guard let manija = try? FileHandle(forReadingFrom: archivo) else { return }
        defer { try? manija.close() }
        let desde = desplazamientos[archivo.path] ?? 0
        guard (try? manija.seek(toOffset: desde)) != nil, let datos = try? manija.readToEnd(), !datos.isEmpty else { return }
        // Solo líneas completas; la última puede estar a medio escribir.
        guard let ultimoSalto = datos.lastIndex(of: UInt8(ascii: "\n")) else { return }
        desplazamientos[archivo.path] = desde + UInt64(ultimoSalto + 1)
        let marca = Data("\"usage\"".utf8)
        for linea in datos[..<ultimoSalto].split(separator: UInt8(ascii: "\n")) where linea.range(of: marca) != nil {
            guard let d = try? JSONSerialization.jsonObject(with: Data(linea)) as? [String: Any],
                  d["type"] as? String == "assistant",
                  let mensaje = d["message"] as? [String: Any],
                  let uso = mensaje["usage"] as? [String: Any] else { continue }
            let entrada = (uso["input_tokens"] as? Int ?? 0) + (uso["cache_creation_input_tokens"] as? Int ?? 0)
                + (uso["cache_read_input_tokens"] as? Int ?? 0)
            if rastrear.contains(sesion) { acumulado.contexto[sesion] = entrada }
            guard let cuando = d["timestamp"] as? String else { continue }
            let fecha = Self.fecha(cuando)
            guard Self.dia(fecha) == dia else { continue }
            let id = mensaje["id"] as? String ?? (d["uuid"] as? String ?? UUID().uuidString)
            guard vistos.insert(id).inserted else { continue }  // un mensaje llega en varias líneas
            let escritos = uso["output_tokens"] as? Int ?? 0
            acumulado.tokens += escritos
            acumulado.respuestas += 1
            acumulado.porHora[Calendar.current.component(.hour, from: fecha)] += escritos
        }
    }

    private static func dia(_ fecha: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: fecha)
    }

    private static func fecha(_ iso: String) -> Date {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.date(from: iso) ?? .distantPast
    }
}

extension SesionesClaude.Sesion {
    mutating func aplicar(_ l: Transcripto.Lectura) {
        switch estado {
        case .esperando: actividad = l.pregunta.isEmpty ? l.pendiente : l.pregunta
        case .trabajando: actividad = l.accion
        case .lista: actividad = ""
        }
        if !l.ultimoTexto.isEmpty { resumen = l.ultimoTexto }
    }
}

/// Lee la cola del transcripto de una sesión (~/.claude/projects/*/<id>.jsonl, solo lectura) para saber qué
/// está haciendo, qué herramienta espera tu permiso, qué te pregunta y con qué frase terminó.
enum Transcripto {
    struct Lectura: Sendable { var accion = "", pendiente = "", pregunta = "", ultimoTexto = "" }

    private static let cerrojo = NSLock()
    nonisolated(unsafe) private static var rutas: [String: URL] = [:]

    static func ruta(_ id: String) -> URL? {
        cerrojo.lock()
        defer { cerrojo.unlock() }
        if let r = rutas[id], FileManager.default.fileExists(atPath: r.path) { return r }
        let raiz = URL(fileURLWithPath: NSHomeDirectory() + "/.claude/projects")
        for proyecto in (try? FileManager.default.contentsOfDirectory(at: raiz, includingPropertiesForKeys: nil)) ?? [] {
            let candidato = proyecto.appendingPathComponent(id + ".jsonl")
            if FileManager.default.fileExists(atPath: candidato.path) {
                rutas[id] = candidato
                return candidato
            }
        }
        return nil
    }

    static func leer(_ id: String) -> Lectura {
        guard let url = ruta(id), let h = try? FileHandle(forReadingFrom: url) else { return Lectura() }
        defer { try? h.close() }
        let tam = (try? h.seekToEnd()) ?? 0
        let desde: UInt64 = tam > 600_000 ? tam - 600_000 : 0
        guard (try? h.seek(toOffset: desde)) != nil, let datos = try? h.readToEnd() else { return Lectura() }
        var lineas = datos.split(separator: UInt8(ascii: "\n"))
        if desde > 0, !lineas.isEmpty { lineas.removeFirst() }  // la primera puede estar cortada
        var lectura = Lectura()
        var conResultado = Set<String>()
        for linea in lineas.reversed() {
            guard let d = try? JSONSerialization.jsonObject(with: Data(linea)) as? [String: Any],
                  let bloques = (d["message"] as? [String: Any])?["content"] as? [[String: Any]] else { continue }
            switch d["type"] as? String {
            case "user":
                for b in bloques where b["type"] as? String == "tool_result" {
                    if let id = b["tool_use_id"] as? String { conResultado.insert(id) }
                }
            case "assistant":
                for b in bloques.reversed() {
                    switch b["type"] as? String {
                    case "tool_use":
                        let nombre = b["name"] as? String ?? ""
                        let entrada = b["input"] as? [String: Any] ?? [:]
                        let texto = describir(nombre, entrada)
                        if lectura.accion.isEmpty { lectura.accion = texto }
                        if lectura.pendiente.isEmpty, let id = b["id"] as? String, !conResultado.contains(id) {
                            lectura.pendiente = texto
                            if nombre == "AskUserQuestion" { lectura.pregunta = texto }
                        }
                    case "text":
                        if lectura.ultimoTexto.isEmpty, let t = b["text"] as? String { lectura.ultimoTexto = primeraLinea(t) }
                        if lectura.accion.isEmpty { lectura.accion = "Escribiendo la respuesta" }
                    default: break
                    }
                }
                if !lectura.accion.isEmpty && !lectura.ultimoTexto.isEmpty { return lectura }
            default: break
            }
        }
        return lectura
    }

    /// La herramienta en palabras: "Editando Isla.swift", "Bash · Build and install", "Buscando en la web".
    static func describir(_ nombre: String, _ entrada: [String: Any]) -> String {
        func archivo(_ clave: String) -> String {
            ((entrada[clave] as? String) ?? "").split(separator: "/").last.map(String.init) ?? ""
        }
        switch nombre {
        case "Bash":
            if let d = entrada["description"] as? String, !d.isEmpty { return d }
            return "Terminal · " + primeraLinea(entrada["command"] as? String ?? "")
        case "Edit", "MultiEdit", "NotebookEdit": return "Editando " + archivo("file_path")
        case "Write": return "Escribiendo " + archivo("file_path")
        case "Read": return "Leyendo " + archivo("file_path")
        case "Grep", "Glob": return "Buscando en los archivos"
        case "WebSearch": return "Buscando en la web"
        case "WebFetch": return "Leyendo una página web"
        case "Agent", "Task": return "Agente · " + (entrada["description"] as? String ?? "")
        case "TodoWrite": return "Organizando tareas"
        case "AskUserQuestion":
            let preguntas = entrada["questions"] as? [[String: Any]]
            return (preguntas?.first?["question"] as? String).map(primeraLinea) ?? "Tiene una pregunta"
        default:
            if nombre.hasPrefix("mcp__") {
                let partes = nombre.split(separator: "_").filter { !$0.isEmpty }
                return "Usando " + (partes.count > 1 ? String(partes[1]) : nombre)
            }
            return nombre
        }
    }

    /// Primera línea legible, sin marcas de Markdown, máximo 90 caracteres.
    static func primeraLinea(_ texto: String) -> String {
        let linea = texto.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.first { !$0.isEmpty } ?? ""
        let limpia = linea.trimmingCharacters(in: CharacterSet(charactersIn: "#*`>-_ ")).replacingOccurrences(of: "**", with: "")
        return limpia.count > 90 ? String(limpia.prefix(89)) + "…" : limpia
    }
}
