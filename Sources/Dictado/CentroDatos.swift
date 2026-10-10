import Foundation
import Observation

/// El estado del centro de mando: lo que publica el núcleo del centro (contrato v1: brief, metas, noticias, orquesta,
/// salud) más lo que solo existe en el Mac (finanzas, inbox, módulos). Dictado no calcula nada: ejecuta un comando que
/// tú configuras e imprime UN objeto JSON con esos archivos, y lo decodifica. Igual que los agentes remotos.
///
///   defaults write app.dictado centro -dict comando '"/ruta/a/estado.sh"'
///
/// El objeto: { "brief.json": {…}, "metas.json": {…}, "noticias.json": {…}, "orquesta.json": {…}, "salud.json": {…},
///              "finanzas.json": {…}, "modulos.json": [{nombre, valor, abrir}], "local": {cerebro, inbox}, "vps": true }
/// Falta un archivo o no se entiende: esa parte se oculta y el resto sigue.
struct EstadoCentro {
    struct Brief: Decodable {
        struct Clima: Decodable { var ciudad: String; var temp: Int; var cielo: String; var max: Int; var min: Int; var simbolo: String }
        struct Foco: Decodable { var titulo: String; var porque: String }
        struct Evento: Decodable { var hora: String; var titulo: String }
        struct Prioridad: Decodable { var texto: String; var vertical: String; var meta: String?; var minutos: Int?; var delegable: String?; var hecha: Bool }
        var generado: String?
        var modelo: String
        var fecha: String
        var fechaIso: String?
        var semana: Int
        var clima: Clima?
        var agenda: [Evento]?
        var agendaLeida: Bool?
        var foco: Foco
        var prioridades: [Prioridad]
        var buenoSaber: [String]
        var fuentes: Int?
    }

    struct Meta: Decodable { var texto: String; var vertical: String; var estado: String; var avance: Double; var medida: String }
    struct Horizonte: Decodable {
        var nombre: String; var rango: String; var subtitulo: String; var tiempo: Double; var metas: [Meta]
        var vigente: Bool?; var semana: Int?; var semanas: Int?; var dia: Int?; var dias: Int?; var desde: String?
    }
    struct Hito: Decodable { var fecha: String?; var dia: Int; var texto: String; var alerta: Bool; var diasRestantes: Int? }
    struct Metas: Decodable {
        var archivo: String?; var borrador: Bool?
        var semana: Horizonte; var mes: Horizonte; var trimestre: Horizonte
        var hitos: [Hito]?
    }

    struct Noticia: Decodable { var id: String?; var vertical: String; var titulo: String; var fuente: String; var fecha: String; var porQue: String; var url: String? }
    struct Noticias: Decodable { var generado: String?; var items: [Noticia] }

    struct Pago: Decodable { var concepto: String; var monto: Double; var fecha: String; var dias: Int? }
    struct Finanzas: Decodable {
        var actualizado: String; var diasSinActualizar: Int?
        var patrimonio: Double; var delta: Double; var liquidez: Double; var netoMes: Double
        var colchon: Double; var colchonPiso: Double
        var proximos: [Pago]
        var alerta: String?
        var enlace: String?
    }

    struct Tarea: Decodable { var titulo: String; var agente: String; var tipo: String; var detalle: String; var vertical: String?; var cuando: String?; var avance: Double? }
    struct Calendario: Decodable {
        struct Fila: Decodable { var nombre: String; var tipo: String; var continuo: Bool; var corridas: [[Double]] }
        var dias: [String]; var ahora: Double; var filas: [Fila]; var avisos: [[Double]]?
    }
    struct Orquesta: Decodable {
        var generado: String?
        var costoHoy: Double; var costoMes: Double; var costoDisponible: Bool?
        var presupuestoDia: Double; var presupuestoMes: Double
        var aprobaciones: [Tarea]; var trabajando: [Tarea]; var programado: [Tarea]; var hecho: [Tarea]
        var calendario: Calendario?
        var hermesConectado: Bool?
    }

    struct Capacidad: Decodable { var nombre: String; var estado: String; var detalle: String?; var desde: String? }
    struct Salud: Decodable { var generado: String?; var capacidades: [Capacidad] }

    struct Modulo: Decodable { var nombre: String; var valor: String; var abrir: String? }
    struct Local: Decodable { var cerebro: String; var inbox: Int; var inboxHermes: Int? }

    var brief: Brief?
    var metas: Metas?
    var noticias: Noticias?
    var finanzas: Finanzas?
    var orquesta: Orquesta?
    var salud: Salud?
    var modulos: [Modulo] = []
    var local: Local?
    var vps = false

    /// Decodifica el objeto completo; cada parte por separado, para que una mala no tumbe a las demás.
    static func decodificar(_ datos: Data) -> EstadoCentro? {
        guard let raiz = try? JSONSerialization.jsonObject(with: datos) as? [String: Any] else { return nil }
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        func parte<T: Decodable>(_ clave: String) -> T? {
            guard let valor = raiz[clave], !(valor is NSNull),
                  let crudo = try? JSONSerialization.data(withJSONObject: valor) else { return nil }
            return try? d.decode(T.self, from: crudo)
        }
        var e = EstadoCentro()
        e.brief = parte("brief.json")
        e.metas = parte("metas.json")
        e.noticias = parte("noticias.json")
        e.finanzas = parte("finanzas.json")
        e.orquesta = parte("orquesta.json")
        e.salud = parte("salud.json")
        e.modulos = parte("modulos.json") ?? []
        e.local = parte("local")
        e.vps = raiz["vps"] as? Bool ?? (e.brief != nil)
        return e
    }

    /// Lee una carpeta con los archivos sueltos del contrato (para renderizar maquetas con datos de prueba).
    static func deCarpeta(_ carpeta: URL) -> EstadoCentro? {
        var raiz: [String: Any] = [:]
        for nombre in ["brief.json", "metas.json", "noticias.json", "orquesta.json", "salud.json", "finanzas.json", "modulos.json"] {
            if let datos = try? Data(contentsOf: carpeta.appendingPathComponent(nombre)),
               let valor = try? JSONSerialization.jsonObject(with: datos) { raiz[nombre] = valor }
        }
        guard !raiz.isEmpty, let datos = try? JSONSerialization.data(withJSONObject: raiz) else { return nil }
        return decodificar(datos)
    }

    /// "2026-10-10T05:30:12-05:00" → Date.
    static func fecha(_ iso: String?) -> Date? {
        guard let iso else { return nil }
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        if let d = f.date(from: iso) { return d }
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.date(from: iso)
    }
}

/// Quien trae el estado: el comando configurado, con caché en disco para abrir al instante y seguir mostrando lo
/// último si el VPS no responde. Solo trabaja con la ventana abierta (al abrir y cada 5 min); cerrada, nada corre.
@MainActor @Observable
final class CentroStore {
    var estado: EstadoCentro?
    var cargando = false
    var error: String?
    var leido: Date?

    @ObservationIgnored private var datosCache: Data?

    static let cache = URL(fileURLWithPath: NSHomeDirectory() + "/Library/Caches/app.dictado/centro.json")

    static var comando: String? {
        let c = UserDefaults(suiteName: "app.dictado")?.dictionary(forKey: "centro")?["comando"] as? String
        return (c?.isEmpty ?? true) ? nil : c
    }

    var configurado: Bool { Self.comando != nil }

    init(cargarCache: Bool = true) {
        guard cargarCache, let datos = try? Data(contentsOf: Self.cache), let e = EstadoCentro.decodificar(datos) else { return }
        estado = e
        leido = (try? FileManager.default.attributesOfItem(atPath: Self.cache.path)[.modificationDate]) as? Date
    }

    /// Lectura fresca, como mucho una a la vez.
    func actualizar() {
        guard let comando = Self.comando, !cargando else { return }
        cargando = true
        Task.detached(priority: .userInitiated) {
            let (datos, fallo) = Self.ejecutar(comando)
            let nuevo = datos.flatMap(EstadoCentro.decodificar)
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.cargando = false
                if let nuevo, let datos {
                    self.estado = nuevo
                    self.leido = Date()
                    self.error = nuevo.vps ? nil : "El VPS no respondió: se muestra lo local y lo último guardado."
                    if !nuevo.vps, let viejo = self.estadoDeCache() { self.estado = Self.mezclar(local: nuevo, vps: viejo) }
                    if nuevo.vps {
                        try? FileManager.default.createDirectory(at: Self.cache.deletingLastPathComponent(), withIntermediateDirectories: true)
                        try? datos.write(to: Self.cache, options: .atomic)
                    }
                } else {
                    self.error = fallo ?? "Respuesta inválida del comando del centro."
                }
            }
        }
    }

    private func estadoDeCache() -> EstadoCentro? {
        (try? Data(contentsOf: Self.cache)).flatMap(EstadoCentro.decodificar)
    }

    /// Sin VPS: lo local es fresco (finanzas, inbox, módulos) y lo del VPS sale de la última lectura buena.
    private static func mezclar(local: EstadoCentro, vps: EstadoCentro) -> EstadoCentro {
        var e = vps
        e.finanzas = local.finanzas ?? vps.finanzas
        e.modulos = local.modulos.isEmpty ? vps.modulos : local.modulos
        e.local = local.local ?? vps.local
        e.vps = false
        return e
    }

    /// Ejecuta el comando (máximo 30 s) y devuelve lo que imprimió.
    nonisolated static func ejecutar(_ comando: String) -> (Data?, String?) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/zsh")
        p.arguments = ["-c", comando]
        let tubo = Pipe()
        p.standardOutput = tubo
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return (nil, "No se pudo ejecutar el comando del centro.") }
        let limite = DispatchWorkItem { if p.isRunning { p.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + 30, execute: limite)
        let datos = tubo.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        limite.cancel()
        if p.terminationReason == .uncaughtSignal { return (nil, "El comando del centro no respondió en 30 s.") }
        return (datos.isEmpty ? nil : datos, datos.isEmpty ? "El comando del centro no imprimió nada." : nil)
    }
}
