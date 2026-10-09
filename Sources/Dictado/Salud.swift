import AppKit
import Carbon.HIToolbox
import Darwin
import IOKit
import Observation
import SwiftUI

// Salud del Mac (pestaña "Mac" de la isla y panel completo): qué se está saturando, en palabras simples, y una limpieza honesta (todo a la Papelera,
// lo personal solo guiado). Mide en detalle solo con el panel abierto; en segundo plano, un vistazo cada
// 60 s para avisar en la isla (disco casi lleno, memoria al límite, Mac caliente, una app al máximo).
// Sin permisos de administrador, sin procesos extra, sin "liberar RAM" (empeora el rendimiento).

enum Gravedad: Int, Comparable {
    case bien, atento, mal
    static func < (a: Gravedad, b: Gravedad) -> Bool { a.rawValue < b.rawValue }
}

/// Una app (con todos sus procesos sumados) o un servicio del sistema, y cuánto consume.
struct Consumidor: Identifiable, Equatable {
    let id: String
    let nombre: String
    let explicacion: String
    let icono: NSImage?
    let simbolo: String      // si no hay ícono (servicios del sistema)
    let cpu: Double          // fracción de todo el procesador (0–1)
    let memoria: Double      // bytes
    let pid: pid_t
    let esApp: Bool
}

/// Un elemento concreto (carpeta o archivo) que puedes marcar o desmarcar antes de limpiar.
struct ItemLimpieza: Identifiable, Equatable {
    var id: String { url.path }
    let url: URL
    let nombre: String
    let detalle: String
    let bytes: Int64
    var marcado = true
}

/// Algo que ocupa disco y qué hacer con ello.
struct Limpiable: Identifiable {
    enum Accion { case papelera, cerrarYLimpiar(String), abrirApp(String), mostrar }
    let id: String
    let titulo: String
    var detalle: String
    let simbolo: String
    var items: [ItemLimpieza]
    var accion: Accion
    var boton: String

    /// Seguras: se regeneran solas y van a la Papelera. Las demás son tuyas: solo se muestran.
    var segura: Bool {
        switch accion {
        case .papelera, .cerrarYLimpiar: return true
        default: return false
        }
    }

    var total: Int64 { items.reduce(0) { $0 + $1.bytes } }
    var marcados: [ItemLimpieza] { items.filter(\.marcado) }
    /// Lo que se liberaría con lo marcado (en las seguras) o lo que ocupa (en las tuyas).
    var bytes: Int64 { segura ? marcados.reduce(0) { $0 + $1.bytes } : total }
}

@MainActor @Observable
final class EstadoSalud {
    var cpu = 0.0
    var gpu = 0.0
    var memoriaUsada = 0.0
    var swap = 0.0
    var memoriaTotal = Double(ProcessInfo.processInfo.physicalMemory)
    var presion = 1                 // 1 normal, 2 apretada, 4 al límite (lo que usa macOS)
    var discoLibre = 0.0
    var discoTotal = 1.0
    var termico = ProcessInfo.ThermalState.nominal
    var consumidores: [Consumidor] = []
    var limpiables: [Limpiable] = []
    var analizando = false
    var mensaje = ""                // resultado de la última limpieza
    var ultima: RegistroLimpieza? = Bitacora.todas().last.flatMap { Date().timeIntervalSince($0.fecha) < 7 * 86_400 ? $0 : nil }
    var abiertos: Set<String> = []  // categorías desplegadas
    var pestana = 0                 // 0 ahora · 1 limpieza

    var gravedadCPU: Gravedad { cpu > 0.9 ? .mal : (cpu > 0.7 ? .atento : .bien) }
    var gravedadGPU: Gravedad { gpu > 0.9 ? .mal : (gpu > 0.75 ? .atento : .bien) }
    var gravedadMemoria: Gravedad { presion >= 4 ? .mal : (presion == 2 || swap > 3e9 ? .atento : .bien) }
    var gravedadDisco: Gravedad { discoLibre < 10e9 ? .mal : (discoLibre < 20e9 ? .atento : .bien) }
    var gravedadTermica: Gravedad {
        switch termico {
        case .serious, .critical: return .mal
        case .fair: return .atento
        default: return .bien
        }
    }

    var recuperable: Int64 { limpiables.filter(\.segura).reduce(0) { $0 + $1.bytes } }
    var revisable: Int64 { limpiables.filter { !$0.segura }.reduce(0) { $0 + $1.bytes } }

    /// Lo más grave, en una frase que entienda cualquiera.
    var diagnostico: (gravedad: Gravedad, titulo: String, frase: String) {
        let porMemoria = consumidores.sorted { $0.memoria > $1.memoria }
        let porCPU = consumidores.sorted { $0.cpu > $1.cpu }
        let memoria = porMemoria.prefix(2).map { "\($0.nombre) (\(Medida.bytes($0.memoria)))" }.joined(separator: " y ")
        let cpuTop = porCPU.first.map { "\($0.nombre) (\(Medida.porcentaje($0.cpu)) del procesador)" } ?? "una app"
        if gravedadDisco == .mal {
            return (.mal, "El disco está casi lleno",
                    "Quedan \(Medida.bytes(discoLibre)) libres. macOS usa ese espacio como memoria de reserva: con menos de 20 GB todo se traba. En Limpieza puedes recuperar espacio.")
        }
        if gravedadMemoria == .mal {
            return (.mal, "La memoria está al límite", "Lo que más ocupa: \(memoria). Cierra lo que no estés usando.")
        }
        if gravedadTermica == .mal {
            return (.mal, "Tu Mac está caliente", "macOS bajó la velocidad para enfriarse. Lo que más trabaja: \(cpuTop).")
        }
        if gravedadCPU == .mal {
            return (.mal, "El procesador está al máximo", "Lo está usando \(cpuTop).")
        }
        if gravedadMemoria == .atento {
            return swap > 3e9
                ? (.atento, "Está usando el disco como memoria",
                   "Hay \(Medida.bytes(swap)) de memoria de reserva en el disco, por eso va lento. Cerrar apps o reiniciar lo libera. Lo que más ocupa: \(memoria).")
                : (.atento, "La memoria está apretada", "Lo que más ocupa: \(memoria).")
        }
        if gravedadDisco == .atento {
            return (.atento, "Queda poco disco", "Quedan \(Medida.bytes(discoLibre)) libres; lo ideal es tener más de 20 GB. Revisa Limpieza.")
        }
        if max(gravedadCPU, gravedadGPU, gravedadTermica) == .atento {
            return (.atento, "Tu Mac está trabajando duro", "Lo que más usa el procesador: \(cpuTop).")
        }
        return (.bien, "Tu Mac está bien", "Nada se está saturando." + (porMemoria.first.map { " Lo que más memoria usa: \($0.nombre) (\(Medida.bytes($0.memoria)))." } ?? ""))
    }
}

// MARK: - Panel y vigilancia

@MainActor
final class Salud {
    let estado = EstadoSalud()
    /// Aviso para la isla: título, detalle, gravedad.
    var alAlertar: ((String, String, Gravedad) -> Void)?

    private let panel: PanelClave
    private var monitor: Any?
    private var relojFondo: Timer?
    private var relojPanel: Timer?
    private let medidor = Medidor()
    private let cola = DispatchQueue(label: "dictado.salud", qos: .utility)
    private var avisados: [String: Date] = [:]
    private var alTope: [String: Int] = [:]       // muestras seguidas de una app al máximo
    private var iconos: [String: NSImage] = [:]

    static let ancho: CGFloat = 720
    static let alto: CGFloat = 680

    init(vivo: Bool = true) {
        panel = PanelClave(contentRect: NSRect(x: 0, y: 0, width: Self.ancho, height: Self.alto),
                           styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView], backing: .buffered, defer: true)
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        guard vivo else { return }
        panel.contentView = NSHostingView(rootView: VistaSalud(estado: estado, control: self))
        NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification, object: panel, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.cerrar() }
        }
        medir(alertar: false)
        relojFondo = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.medir(alertar: true) }
        }
    }

    var abierto: Bool { panel.isVisible }

    func alternar() { abierto ? cerrar() : abrir() }

    func abrir() {
        if let pantalla = NSScreen.main {
            let z = pantalla.visibleFrame
            panel.setFrameOrigin(NSPoint(x: z.midX - Self.ancho / 2, y: z.midY - Self.alto / 2))
        }
        panel.makeKeyAndOrderFront(nil)
        medir(alertar: false)
        relojPanel?.invalidate()
        relojPanel = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] t in
            MainActor.assumeIsolated {
                guard let self, self.abierto else {  // el panel se ocultó por otro camino: deja de medir
                    t.invalidate()
                    return
                }
                self.medir(alertar: false)
            }
        }
        if estado.limpiables.isEmpty && !estado.analizando { analizar() }
        if monitor == nil {
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] evento in
                nonisolated(unsafe) let e = evento
                return MainActor.assumeIsolated {
                    guard let self, self.panel.isKeyWindow, Int(e.keyCode) == kVK_Escape else { return e }
                    self.cerrar()
                    return nil
                }
            }
        }
    }

    func cerrar() {
        guard abierto else { return }
        panel.orderOut(nil)
        relojPanel?.invalidate()
        relojPanel = nil
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }

    // MARK: Medición

    /// Medición fresca (al abrir la pestaña Mac de la isla).
    func medirAhora() { medir(alertar: false) }

    private func medir(alertar: Bool) {
        let medidor = self.medidor
        cola.async { [weak self] in
            let m = medidor.medir()
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.aplicar(m)
                    if alertar { self.revisarAlertas() }
                }
            }
        }
    }

    private func aplicar(_ m: Medidor.Muestra) {
        estado.cpu = m.cpu
        estado.gpu = m.gpu
        estado.memoriaUsada = m.memoriaUsada
        estado.swap = m.swap
        estado.presion = m.presion
        estado.discoLibre = m.discoLibre
        estado.discoTotal = m.discoTotal
        estado.termico = ProcessInfo.processInfo.thermalState
        estado.consumidores = agrupar(m.procesos)
    }

    /// Junta los procesos por la app dueña (Claude con sus ayudantes, Arc con sus pestañas) y nombra los
    /// servicios del sistema en palabras simples.
    private func agrupar(_ procesos: [Medidor.Proceso]) -> [Consumidor] {
        struct Grupo { var nombre: String, explicacion: String, icono: NSImage?, simbolo: String, cpu = 0.0, memoria = 0.0, pid: pid_t, esApp: Bool }
        var grupos: [String: Grupo] = [:]
        for p in procesos {
            let clave: String
            if let app = NSRunningApplication(processIdentifier: p.responsable), app.activationPolicy == .regular,
               let bundle = app.bundleIdentifier {
                clave = bundle
                if grupos[clave] == nil {
                    grupos[clave] = Grupo(nombre: app.localizedName ?? bundle, explicacion: Explicaciones.app(bundle),
                                          icono: icono(bundle, app), simbolo: "app", pid: app.processIdentifier, esApp: true)
                }
            } else {
                let s = Explicaciones.sistema(p.nombre)
                clave = "sistema:" + s.nombre
                if grupos[clave] == nil {
                    grupos[clave] = Grupo(nombre: s.nombre, explicacion: s.explicacion, icono: nil, simbolo: s.simbolo, pid: p.pid, esApp: false)
                }
            }
            grupos[clave]?.cpu += p.cpu
            grupos[clave]?.memoria += p.memoria
        }
        let total = estado.memoriaTotal
        func peso(_ c: Consumidor) -> Double { c.cpu * 2 + c.memoria / total }  // procesador pesa doble
        let lista: [Consumidor] = grupos.map { clave, g in
            Consumidor(id: clave, nombre: g.nombre, explicacion: g.explicacion, icono: g.icono, simbolo: g.simbolo,
                       cpu: g.cpu, memoria: g.memoria, pid: g.pid, esApp: g.esApp)
        }
        return Array(lista.sorted { peso($0) > peso($1) }.prefix(5))
    }

    private func icono(_ bundle: String, _ app: NSRunningApplication) -> NSImage? {
        if let i = iconos[bundle] { return i }
        let i = app.icon.map { Privacidad.mapaDeBits($0, lado: 52) }
        iconos[bundle] = i
        return i
    }

    /// Avisos en la isla, uno por problema y con pausa para no insistir.
    private func revisarAlertas() {
        func avisar(_ clave: String, horas: Double, _ titulo: String, _ detalle: String, _ g: Gravedad) {
            if let antes = avisados[clave], Date().timeIntervalSince(antes) < horas * 3600 { return }
            avisados[clave] = Date()
            alAlertar?(titulo, detalle, g)
        }
        let e = estado
        if e.gravedadDisco == .mal { avisar("disco", horas: 3, "Disco casi lleno", "Quedan \(Medida.bytes(e.discoLibre)) libres", .mal) }
        if e.gravedadMemoria == .mal, let top = e.consumidores.max(by: { $0.memoria < $1.memoria }) {
            avisar("memoria", horas: 1, "Memoria al límite", "\(top.nombre) usa \(Medida.bytes(top.memoria))", .mal)
        }
        if e.gravedadTermica == .mal { avisar("calor", horas: 1, "Tu Mac está caliente", "macOS bajó la velocidad para enfriarse", .mal) }
        // Una app usando un núcleo entero durante 2 minutos seguidos.
        let nucleo = 1.0 / Double(ProcessInfo.processInfo.activeProcessorCount)
        var siguen: [String: Int] = [:]
        for c in e.consumidores where c.esApp && c.cpu >= nucleo * 0.95 && c.nombre != "Dictado" {
            siguen[c.id] = (alTope[c.id] ?? 0) + 1
            if siguen[c.id]! >= 2 {
                avisar("tope:" + c.id, horas: 1, "\(c.nombre) lleva 2 min al máximo", "Usa \(Medida.porcentaje(c.cpu)) del procesador", .atento)
            }
        }
        alTope = siguen
    }

    // MARK: Acciones

    /// Cierra la app como si eligieras Salir (guarda y pregunta lo que tenga que preguntar).
    func cerrarApp(_ c: Consumidor) {
        NSRunningApplication(processIdentifier: c.pid)?.terminate()
    }

    func analizar() {
        estado.analizando = true
        estado.mensaje = ""
        let abiertas = Escaner.appsAbiertas()
        cola.async { [weak self] in
            let lista = Escaner.analizar(abiertas: abiertas)
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    self?.estado.limpiables = lista
                    self?.estado.analizando = false
                }
            }
        }
    }

    func ejecutar(_ l: Limpiable) {
        switch l.accion {
        case .papelera:
            let r = Bitacora.mover(l.marcados, titulo: l.titulo)
            terminarLimpieza(r, titulo: l.titulo)
        case .cerrarYLimpiar(let bundle):
            cerrarYLimpiar(l, bundle: bundle)
        case .abrirApp(let bundle):
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundle) {
                NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
            }
            cerrar()
        case .mostrar:
            let urls = l.items.map(\.url)
            if urls.count == 1 { NSWorkspace.shared.open(urls[0]) } else { NSWorkspace.shared.activateFileViewerSelecting(urls) }
            cerrar()
        }
    }

    private func terminarLimpieza(_ r: RegistroLimpieza, titulo: String) {
        if r.movimientos.isEmpty {
            estado.mensaje = "No se pudo mover nada: puede que una app lo esté usando."
        } else {
            estado.ultima = r
            estado.mensaje = "\(Medida.bytes(Double(r.bytes))) de \(titulo.lowercased()) a la Papelera. Se libera al vaciarla; puedes deshacer."
        }
        analizar()
    }

    /// Cierra la app como ⌘Q (si tiene algo sin guardar, te pregunta y no se toca nada), limpia su caché y la
    /// vuelve a abrir (Arc y los navegadores restauran sus pestañas).
    private func cerrarYLimpiar(_ l: Limpiable, bundle: String) {
        let nombre = Escaner.nombreApp(bundle)
        let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundle).first
        app?.terminate()
        estado.mensaje = "Cerrando \(nombre)…"
        Task { @MainActor in
            for _ in 0..<60 where app?.isTerminated == false { try? await Task.sleep(for: .milliseconds(250)) }
            guard app?.isTerminated != false else {
                estado.mensaje = "\(nombre) no se cerró (quizá tenía algo sin guardar). No toqué nada."
                return
            }
            try? await Task.sleep(for: .milliseconds(600))
            let r = Bitacora.mover(l.marcados, titulo: l.titulo)
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundle) {
                let config = NSWorkspace.OpenConfiguration()
                config.activates = false
                NSWorkspace.shared.openApplication(at: url, configuration: config) { _, _ in }
            }
            terminarLimpieza(r, titulo: l.titulo)
        }
    }

    /// Devuelve a su lugar lo de la última limpieza.
    func deshacer() {
        guard let r = estado.ultima else { return }
        let vueltos = Bitacora.deshacer(r)
        estado.ultima = nil
        estado.mensaje = vueltos > 0 ? "Listo: devolví \(vueltos) elemento\(vueltos == 1 ? "" : "s") a su lugar." : "Ya no estaban en la Papelera."
        analizar()
    }
}

// MARK: - Medidor (fuera del hilo principal)

final class Medidor: @unchecked Sendable {
    struct Proceso: Sendable { let pid: pid_t; let nombre: String; let responsable: pid_t; let cpu: Double; let memoria: Double }
    struct Muestra: Sendable {
        var cpu = 0.0, gpu = 0.0, memoriaUsada = 0.0, swap = 0.0, discoLibre = 0.0, discoTotal = 1.0
        var presion = 1
        var procesos: [Proceso] = []
    }

    private var ticksPrevios: (usado: UInt64, total: UInt64)?
    private let nucleos = Double(ProcessInfo.processInfo.activeProcessorCount)

    private typealias Responsable = @convention(c) (pid_t) -> pid_t
    private static let responsable: Responsable? = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "responsibility_get_pid_responsible_for_pid")
        .map { unsafeBitCast($0, to: Responsable.self) }

    func medir() -> Muestra {
        var m = Muestra()
        m.cpu = procesador()
        m.gpu = Self.graficos()
        (m.memoriaUsada, m.swap, m.presion) = Self.memoria()
        (m.discoLibre, m.discoTotal) = disco()
        m.procesos = procesos()
        return m
    }

    private func procesador() -> Double {
        var cuantos: natural_t = 0
        var info: processor_info_array_t?
        var tam: mach_msg_type_number_t = 0
        guard host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &cuantos, &info, &tam) == KERN_SUCCESS,
              let info else { return 0 }
        defer {
            vm_deallocate(mach_task_self_, vm_address_t(UInt(bitPattern: info)), vm_size_t(Int(tam) * MemoryLayout<integer_t>.stride))
        }
        var usado: UInt64 = 0
        var total: UInt64 = 0
        for i in 0..<Int(cuantos) {
            let base = Int(CPU_STATE_MAX) * i
            let u = UInt64(UInt32(bitPattern: info[base + Int(CPU_STATE_USER)]))
            let s = UInt64(UInt32(bitPattern: info[base + Int(CPU_STATE_SYSTEM)]))
            let n = UInt64(UInt32(bitPattern: info[base + Int(CPU_STATE_NICE)]))
            let o = UInt64(UInt32(bitPattern: info[base + Int(CPU_STATE_IDLE)]))
            usado += u + s + n
            total += u + s + n + o
        }
        defer { ticksPrevios = (usado, total) }
        guard let previo = ticksPrevios, total > previo.total, usado >= previo.usado else { return 0 }
        return Double(usado - previo.usado) / Double(total - previo.total)
    }

    /// Uso de la GPU según el propio driver (IOAccelerator → PerformanceStatistics), sin permisos especiales.
    private static func graficos() -> Double {
        var iterador: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOAccelerator"), &iterador) == KERN_SUCCESS else { return 0 }
        defer { IOObjectRelease(iterador) }
        var maximo = 0.0
        var servicio = IOIteratorNext(iterador)
        while servicio != 0 {
            if let datos = IORegistryEntryCreateCFProperty(servicio, "PerformanceStatistics" as CFString, kCFAllocatorDefault, 0)?
                .takeRetainedValue() as? [String: Any], let uso = datos["Device Utilization %"] as? Int {
                maximo = max(maximo, Double(uso) / 100)
            }
            IOObjectRelease(servicio)
            servicio = IOIteratorNext(iterador)
        }
        return maximo
    }

    /// Memoria usada como la cuenta Monitor de Actividad (apps + fija + comprimida), swap y presión.
    private static func memoria() -> (Double, Double, Int) {
        var datos = vm_statistics64()
        var cuenta = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let r = withUnsafeMutablePointer(to: &datos) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(cuenta)) { host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &cuenta) }
        }
        let pagina = Double(vm_kernel_page_size)
        let usada = r == KERN_SUCCESS
            ? (Double(datos.internal_page_count) - Double(datos.purgeable_count) + Double(datos.wire_count)
               + Double(datos.compressor_page_count)) * pagina
            : 0
        var swap = xsw_usage()
        var tam = MemoryLayout<xsw_usage>.size
        sysctlbyname("vm.swapusage", &swap, &tam, nil, 0)
        var presion: Int32 = 1
        tam = MemoryLayout<Int32>.size
        sysctlbyname("kern.memorystatus_vm_pressure_level", &presion, &tam, nil, 0)
        return (usada, Double(swap.xsu_used), Int(presion))
    }

    /// Espacio que macOS de verdad puede usar (incluye lo que puede liberar solo, como cachés de iCloud).
    /// Esta consulta hace que macOS calcule lo que puede liberar solo (cachés purgables): con el disco casi
    /// lleno le cuesta trabajo, así que se repite como máximo una vez por minuto.
    private var discoPrevio: (libre: Double, total: Double, cuando: Date)?

    private func disco() -> (Double, Double) {
        if let p = discoPrevio, Date().timeIntervalSince(p.cuando) < 60 { return (p.libre, p.total) }
        let v = try? URL(fileURLWithPath: "/").resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey, .volumeTotalCapacityKey])
        let medida = (Double(v?.volumeAvailableCapacityForImportantUsage ?? 0), Double(v?.volumeTotalCapacity ?? 1))
        discoPrevio = (medida.0, medida.1, Date())
        return medida
    }

    /// Procesos que consumen algo, con su app dueña. El procesador sale de /bin/ps (del sistema, puede ver todos
    /// los procesos sin pedir contraseña; promedio del último minuto). La memoria es la real (la que muestra
    /// Monitor de Actividad) para tus procesos y la residente para los del sistema.
    private func procesos() -> [Proceso] {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/ps")
        p.arguments = ["-Ao", "pid=,pcpu=,rss=,comm="]
        let tubo = Pipe()
        p.standardOutput = tubo
        p.standardError = FileHandle.nullDevice
        guard (try? p.run()) != nil else { return [] }
        let datos = tubo.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        var lista: [Proceso] = []
        for linea in (String(data: datos, encoding: .utf8) ?? "").split(separator: "\n") {
            let partes = linea.split(separator: " ", maxSplits: 3, omittingEmptySubsequences: true)
            guard partes.count == 4, let pid = pid_t(partes[0]), let pcpu = Double(partes[1]), let rss = Double(partes[2]) else { continue }
            var memoria = rss * 1024
            var uso = rusage_info_v4()
            let ok = withUnsafeMutablePointer(to: &uso) {
                $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { proc_pid_rusage(pid, RUSAGE_INFO_V4, $0) }
            }
            if ok == 0 { memoria = Double(uso.ri_phys_footprint) }
            let cpu = pcpu / 100 / nucleos
            guard cpu > 0.003 || memoria > 80_000_000 else { continue }
            let ruta = String(partes[3])
            lista.append(Proceso(pid: pid, nombre: (ruta as NSString).lastPathComponent, responsable: Self.responsable?(pid) ?? pid,
                                 cpu: cpu, memoria: memoria))
        }
        return lista
    }
}

// MARK: - Explicaciones en palabras simples

enum Explicaciones {
    static func app(_ bundle: String) -> String {
        switch bundle {
        case "com.anthropic.claudefordesktop": return "Cada sesión abierta ocupa memoria: archiva las que ya no uses"
        case "company.thebrowser.Browser", "com.google.Chrome", "com.apple.Safari", "org.mozilla.firefox":
            return "Cada pestaña abierta ocupa memoria"
        case "net.whatsapp.WhatsApp": return "Mensajería"
        case "com.spotify.client": return "Música"
        case "com.microsoft.Word", "com.microsoft.Excel", "com.microsoft.Powerpoint": return "Documentos abiertos"
        case "app.dictado": return "Dictado, isla y portapapeles"
        default: return ""
        }
    }

    /// Nombre amable, explicación y símbolo para un proceso del sistema.
    static func sistema(_ proceso: String) -> (nombre: String, explicacion: String, simbolo: String) {
        let p = proceso.lowercased()
        if p == "windowserver" { return ("Pantalla", "Dibuja todo lo que ves; sube con muchas ventanas y animaciones", "display") }
        if p == "kernel_task" { return ("Sistema", "macOS enfría el Mac y ordena la memoria; alto = calor o memoria llena", "cpu") }
        if p.contains("siri") || p.contains("intelligence") || p.contains("generativeexperiences") || p.contains("knowledge") {
            return ("Apple Intelligence", "Procesa en segundo plano; se calma solo", "apple.intelligence")
        }
        if p.hasPrefix("mds") || p.hasPrefix("mdworker") || p.contains("spotlight") || p.contains("corespotlight") || p.contains("quicklook") {
            return ("Spotlight", "Indexa tus archivos para la búsqueda; pasa tras copiar muchos archivos", "magnifyingglass")
        }
        if p.contains("photoanalysis") || p.contains("mediaanalysis") || p.contains("photolibrary") {
            return ("Fotos", "Analiza tus fotos (caras, objetos) cuando el Mac está libre", "photo.on.rectangle")
        }
        if p.hasPrefix("backupd") { return ("Time Machine", "Haciendo copia de seguridad", "clock.arrow.circlepath") }
        if p.contains("softwareupdate") { return ("Actualización de macOS", "Descargando o preparando una actualización", "arrow.down.circle") }
        if p == "deleted" { return ("Liberador de espacio", "macOS borra sus propios cachés porque el disco está casi lleno", "internaldrive") }
        if p == "mobileassetd" { return ("Descargas de macOS", "Baja voces, modelos y recursos de Apple en segundo plano", "arrow.down.circle") }
        if p == "contactsd" || p == "calaccessd" || p.contains("dataaccess") { return ("Contactos y calendarios", "Sincronizando tus cuentas", "person.2") }
        if p == "coreaudiod" { return ("Audio", "Sube cuando una app usa el micrófono o suena algo", "speaker.wave.2") }
        if p == "cloudd" || p == "bird" || p.contains("fileprovider") { return ("iCloud", "Sincronizando archivos", "icloud") }
        if p.contains("perfpower") || p == "powerd" { return ("Energía", "macOS mide el consumo de la batería", "battery.75percent") }
        if p.contains("notificationcenter") { return ("Notificaciones", "Centro de notificaciones y widgets", "bell") }
        if p.contains("wallpaper") { return ("Fondo de pantalla", "Fondo animado o dinámico", "photo") }
        if p.contains("claude") { return ("Claude (sesiones)", "Procesos de las sesiones de Claude Code", "sparkle") }
        if p == "node" || p == "python3" || p == "python" || p == "bun" || p == "deno" {
            return ("Programas de desarrollo", "Servidores o scripts (\(proceso)) corriendo en segundo plano", "terminal")
        }
        return (proceso, "Proceso del sistema", "gearshape")
    }
}

// MARK: - Escáner de limpieza (fuera del hilo principal)

/// Reglas de seguridad: solo se proponen cosas que se regeneran solas o que tú decides; nunca tus carpetas
/// protegidas (ajuste "protegidas"), iCloud, contenedores de apps, ni nada en uso.
enum Escaner {
    static let casa = FileManager.default.homeDirectoryForCurrentUser

    static func protegido(_ url: URL) -> Bool {
        let p = url.path
        return Ajustes.carpetasProtegidas.contains { p.hasPrefix($0) } || p.contains("/Library/Mobile Documents")
            || p.contains("/Library/Containers/") || p.contains("/.Trash/")
    }

    /// Todo en paralelo: el análisis tarda lo que tarde la carpeta más grande.
    static func analizar(abiertas: [String: String]) -> [Limpiable] {
        let tareas: [@Sendable () -> [Limpiable]] = [
            { cacheApps(abiertas) }, { cachesInternas(abiertas) }, { cachesDesarrollo() }, { dependenciasDormidas() },
            { registros() }, { carpetasPersonales() }, { descargasViejas() }, { archivosGrandes() }, { duplicados() },
            { appsGrandes(abiertas) },
        ]
        let cerrojo = NSLock()
        nonisolated(unsafe) var lista: [Limpiable] = []
        DispatchQueue.concurrentPerform(iterations: tareas.count) { i in
            let parte = tareas[i]()
            cerrojo.lock()
            lista.append(contentsOf: parte)
            cerrojo.unlock()
        }
        return lista.filter { $0.total > 50_000_000 }
            .sorted { ($0.segura ? 0 : 1, -$0.total) < ($1.segura ? 0 : 1, -$1.total) }
    }

    // MARK: Seguras (a la Papelera, se regeneran)

    /// Cachés de ~/Library/Caches. Las de apps abiertas no se tocan; si son grandes, se ofrece cerrar la app,
    /// limpiar y volver a abrirla.
    static func cacheApps(_ abiertas: [String: String]) -> [Limpiable] {
        var cerradas: [ItemLimpieza] = []
        var porApp: [String: [ItemLimpieza]] = [:]
        for c in contenido(casa.appendingPathComponent("Library/Caches")) {
            let id = c.lastPathComponent
            guard !id.hasPrefix("com.apple."), !["ms-playwright", "app.dictado", "CloudKit", "FamilyCircle"].contains(id),
                  let b = bytes(c), b > 5_000_000 else { continue }
            let item = ItemLimpieza(url: c, nombre: nombreApp(id), detalle: id, bytes: b)
            if let bundle = abiertas[id] ?? abiertas[id.lowercased()] {
                porApp[bundle, default: []].append(item)
            } else if !enUsoReciente(c) {
                cerradas.append(item)
            }
        }
        var lista: [Limpiable] = []
        if !cerradas.isEmpty {
            cerradas.sort { $0.bytes > $1.bytes }
            lista.append(Limpiable(id: "caches", titulo: "Cachés de apps cerradas", detalle: resumen(cerradas), simbolo: "shippingbox",
                                   items: cerradas, accion: .papelera, boton: "A la Papelera"))
        }
        let nuncaCerrar: Set = ["com.anthropic.claudefordesktop", "app.dictado", "com.apple.finder"]
        for (bundle, items) in porApp where !nuncaCerrar.contains(bundle) {
            let total = items.reduce(0) { $0 + $1.bytes }
            guard total > 300_000_000 else { continue }
            let nombre = nombreApp(bundle)
            lista.append(Limpiable(id: "cerrar:" + bundle, titulo: "Caché de \(nombre)",
                                   detalle: "\(nombre) está abierto: lo cierro, limpio su caché y lo vuelvo a abrir como estaba",
                                   simbolo: "arrow.triangle.2.circlepath", items: items, accion: .cerrarYLimpiar(bundle), boton: "Cerrar y limpiar"))
        }
        return lista
    }

    /// Cachés internas de apps hechas con Chrome/Electron (Claude, VS Code, Slack…): solo de las que están cerradas.
    static func cachesInternas(_ abiertas: [String: String]) -> [Limpiable] {
        let nombres: Set = ["Cache", "Code Cache", "GPUCache", "DawnGraphiteCache", "DawnWebGPUCache", "ShaderCache", "Crashpad"]
        var items: [ItemLimpieza] = []
        for app in contenido(casa.appendingPathComponent("Library/Application Support")) where esCarpeta(app) {
            let nombre = app.lastPathComponent
            guard !nombre.hasPrefix("com.apple"), abiertas[nombre] == nil, abiertas[nombre.lowercased()] == nil else { continue }
            func buscar(_ dir: URL, _ nivel: Int) {
                guard nivel < 3 else { return }
                for h in contenido(dir) where esCarpeta(h) {
                    if nombres.contains(h.lastPathComponent) {
                        if !enUsoReciente(h), let b = bytes(h), b > 10_000_000 {
                            items.append(ItemLimpieza(url: h, nombre: nombre, detalle: h.lastPathComponent, bytes: b))
                        }
                    } else if !h.lastPathComponent.hasPrefix(".") {
                        buscar(h, nivel + 1)
                    }
                }
            }
            buscar(app, 0)
        }
        guard !items.isEmpty else { return [] }
        items.sort { $0.bytes > $1.bytes }
        return [Limpiable(id: "internas", titulo: "Cachés internas de apps cerradas", detalle: resumen(items) + " — se regeneran al abrirlas",
                          simbolo: "square.stack.3d.up", items: items, accion: .papelera, boton: "A la Papelera")]
    }

    /// Descargas de herramientas de programación que se vuelven a bajar solas.
    static func cachesDesarrollo() -> [Limpiable] {
        let candidatos: [(String, String)] = [
            (".cache/uv", "uv"), (".cache/pip", "pip"), (".npm/_cacache", "npm"), (".npm/_npx", "npx"),
            ("Library/Caches/ms-playwright", "Playwright"), ("Library/Developer/Xcode/DerivedData", "Xcode"), (".bun/install/cache", "bun"),
        ]
        var items: [ItemLimpieza] = []
        for (ruta, nombre) in candidatos {
            let url = casa.appendingPathComponent(ruta)
            if let b = bytes(url), b > 10_000_000 { items.append(ItemLimpieza(url: url, nombre: nombre, detalle: "~/" + ruta, bytes: b)) }
        }
        // Versiones viejas de Claude Code instalado en la terminal; la que usa el comando `claude` se conserva.
        let versiones = casa.appendingPathComponent(".local/share/claude/versions")
        let activa = (try? FileManager.default.destinationOfSymbolicLink(atPath: casa.appendingPathComponent(".local/bin/claude").path))
            .map { URL(fileURLWithPath: $0).lastPathComponent }
        for v in contenido(versiones) where v.lastPathComponent != activa {
            if let b = bytes(v), b > 10_000_000 {
                items.append(ItemLimpieza(url: v, nombre: "Claude Code \(v.lastPathComponent)", detalle: "versión vieja de la terminal", bytes: b))
            }
        }
        guard !items.isEmpty else { return [] }
        items.sort { $0.bytes > $1.bytes }
        return [Limpiable(id: "desarrollo", titulo: "Cachés de programación", detalle: resumen(items) + " — se vuelven a descargar si hacen falta",
                          simbolo: "hammer", items: items, accion: .papelera, boton: "A la Papelera")]
    }

    /// node_modules y entornos de Python de proyectos dormidos: sin cambios hace 60+ días y con su receta
    /// (package.json, pyproject…) para recrearlos. Los .venv salen desmarcados: pueden tener paquetes
    /// instalados a mano que la receta no recuerda.
    static func dependenciasDormidas() -> [Limpiable] {
        let estandar: Set = ["Library", "Applications", "Desktop", "Documents", "Downloads", "Movies", "Music", "Pictures", "Public", "Developer"]
        var raices = [casa.appendingPathComponent("Developer"), casa.appendingPathComponent("Documents")]
        raices += contenido(casa).filter { esCarpeta($0) && !$0.lastPathComponent.hasPrefix(".") && !estandar.contains($0.lastPathComponent) }
        var encontrados: [URL] = []
        func buscar(_ dir: URL, _ nivel: Int) {
            guard nivel <= 5, !protegido(dir) else { return }
            for h in contenido(dir) where esCarpeta(h) {
                let n = h.lastPathComponent
                if ["node_modules", ".venv", "venv"].contains(n) { encontrados.append(h); continue }
                if n.hasPrefix(".") || n.hasSuffix(".app") || n.hasSuffix(".photoslibrary") || n == "Library" { continue }
                buscar(h, nivel + 1)
            }
        }
        raices.forEach { buscar($0, 0) }
        let limite = Date().addingTimeInterval(-60 * 86_400)
        let recetas = ["package.json", "pyproject.toml", "requirements.txt", "uv.lock", "Pipfile", "setup.py"]
        var items: [ItemLimpieza] = []
        for dep in encontrados {
            let proyecto = dep.deletingLastPathComponent()
            let archivos = contenido(proyecto).map(\.lastPathComponent)
            guard archivos.contains(where: { recetas.contains($0) || ($0.hasPrefix("requirements") && $0.hasSuffix(".txt")) }),
                  let ultima = ultimaActividad(proyecto), ultima < limite,
                  let b = bytes(dep), b > 20_000_000 else { continue }
            let esPython = dep.lastPathComponent != "node_modules"
            items.append(ItemLimpieza(url: dep, nombre: proyecto.lastPathComponent,
                                      detalle: "\(dep.lastPathComponent) · sin tocar desde \(fechaCorta(ultima))" + (esPython ? " · revisa antes" : ""),
                                      bytes: b, marcado: !esPython))
        }
        guard !items.isEmpty else { return [] }
        items.sort { $0.bytes > $1.bytes }
        return [Limpiable(id: "dependencias", titulo: "Dependencias de proyectos dormidos",
                          detalle: resumen(items) + " — se recrean con npm install o uv sync al volver",
                          simbolo: "cube.box", items: items, accion: .papelera, boton: "A la Papelera")]
    }

    static func registros() -> [Limpiable] {
        var items: [ItemLimpieza] = []
        for h in contenido(casa.appendingPathComponent("Library/Logs")) {
            if let b = bytes(h), b > 1_000_000 { items.append(ItemLimpieza(url: h, nombre: h.lastPathComponent, detalle: "Library/Logs", bytes: b)) }
        }
        guard !items.isEmpty else { return [] }
        items.sort { $0.bytes > $1.bytes }
        return [Limpiable(id: "registros", titulo: "Registros y reportes de fallos", detalle: "Historiales de apps que nadie lee",
                          simbolo: "doc.text", items: items, accion: .papelera, boton: "A la Papelera")]
    }

    // MARK: Guiadas (son tuyas: se muestran y se abre el lugar)

    static func carpetasPersonales() -> [Limpiable] {
        var lista: [Limpiable] = []
        func carpeta(_ id: String, _ rutas: [String], _ titulo: String, _ detalle: String, _ simbolo: String, _ accion: Limpiable.Accion, _ boton: String) {
            let items = rutas.compactMap { r -> ItemLimpieza? in
                let u = casa.appendingPathComponent(r)
                guard let b = bytes(u), b > 0 else { return nil }
                return ItemLimpieza(url: u, nombre: u.lastPathComponent, detalle: "~/" + r, bytes: b)
            }
            if !items.isEmpty {
                lista.append(Limpiable(id: id, titulo: titulo, detalle: detalle, simbolo: simbolo, items: items, accion: accion, boton: boton))
            }
        }
        carpeta("whatsapp", ["Library/Group Containers/group.net.whatsapp.WhatsApp.shared/Message/Media"], "Fotos y videos de WhatsApp",
                "En WhatsApp: Ajustes → Almacenamiento → revisa los chats más pesados", "message", .abrirApp("net.whatsapp.WhatsApp"), "Abrir WhatsApp")
        carpeta("cowork", ["Library/Application Support/Claude/vm_bundles"], "Máquina virtual de Cowork",
                "Si no usas Cowork, se restablece desde la app de Claude", "shippingbox.circle", .mostrar, "Ver en Finder")
        carpeta("notas", ["Library/Group Containers/group.com.apple.VoiceMemos.shared/Recordings"], "Notas de Voz",
                "Exporta las viejas a Drive y bórralas en la app", "waveform", .abrirApp("com.apple.VoiceMemos"), "Abrir Notas de Voz")
        carpeta("modelos", [".cache/huggingface", ".cache/fastembed"], "Modelos de IA descargados",
                "Whisper, voces y modelos de experimentos; se vuelven a bajar si los usas", "cpu", .mostrar, "Ver en Finder")
        carpeta("papelera", [".Trash"], "Papelera", "Sigue ocupando espacio hasta que la vacíes (Finder → Vaciar Papelera)",
                "trash", .mostrar, "Abrir Papelera")
        return lista
    }

    /// Lo que está en Descargas sin tocarse hace más de 90 días.
    static func descargasViejas() -> [Limpiable] {
        let limite = Date().addingTimeInterval(-90 * 86_400)
        let items = contenido(casa.appendingPathComponent("Downloads")).compactMap { u -> ItemLimpieza? in
            let v = try? u.resourceValues(forKeys: [.contentModificationDateKey, .contentAccessDateKey])
            let ultima = max(v?.contentModificationDate ?? .distantFuture, v?.contentAccessDate ?? .distantPast)
            guard ultima < limite, let b = bytes(u) else { return nil }
            return ItemLimpieza(url: u, nombre: u.lastPathComponent, detalle: "sin abrir desde \(fechaCorta(ultima))", bytes: b)
        }.sorted { $0.bytes > $1.bytes }
        guard !items.isEmpty else { return [] }
        return [Limpiable(id: "descargas", titulo: "Descargas de hace más de 3 meses", detalle: "\(items.count) archivos y carpetas sin abrir desde entonces",
                          simbolo: "arrow.down.circle", items: items, accion: .mostrar, boton: "Ver en Finder")]
    }

    /// Archivos de más de 1 GB en tu carpeta (Spotlight los encuentra al instante).
    static func archivosGrandes() -> [Limpiable] {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/mdfind")
        p.arguments = ["-onlyin", casa.path, "kMDItemFSSize > 1073741824"]
        let tubo = Pipe()
        p.standardOutput = tubo
        p.standardError = FileHandle.nullDevice
        guard (try? p.run()) != nil else { return [] }
        let salida = String(data: tubo.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        p.waitUntilExit()
        let items = salida.split(separator: "\n").map { URL(fileURLWithPath: String($0)) }
            .filter { !$0.path.contains("/Library/") && !$0.path.contains("/.Trash/") }
            .compactMap { u in bytes(u).map { ItemLimpieza(url: u, nombre: u.lastPathComponent, detalle: u.deletingLastPathComponent().path.replacingOccurrences(of: casa.path, with: "~"), bytes: $0) } }
            .sorted { $0.bytes > $1.bytes }
        guard !items.isEmpty else { return [] }
        return [Limpiable(id: "grandes", titulo: "Archivos de más de 1 GB", detalle: resumen(items), simbolo: "doc.zipper",
                          items: items, accion: .mostrar, boton: "Ver en Finder")]
    }

    /// Copias idénticas (mismo tamaño y mismo contenido) de archivos de 5 MB o más. Se conserva la más antigua;
    /// las demás se muestran en el Finder para que decidas.
    static func duplicados() -> [Limpiable] {
        var porTamano: [Int64: [URL]] = [:]
        func recorrer(_ dir: URL, _ nivel: Int) {
            guard nivel < 8 else { return }
            for h in contenido(dir) {
                let n = h.lastPathComponent
                if n.hasPrefix(".") || n == "node_modules" || n.hasSuffix(".app") || n.hasSuffix(".photoslibrary") { continue }
                if esCarpeta(h) {
                    recorrer(h, nivel + 1)
                } else if let t = (try? h.resourceValues(forKeys: [.fileSizeKey]))?.fileSize, t >= 5_000_000 {
                    porTamano[Int64(t), default: []].append(h)
                }
            }
        }
        for r in ["Downloads", "Desktop", "Documents", "Movies", "Pictures"] { recorrer(casa.appendingPathComponent(r), 0) }
        var items: [ItemLimpieza] = []
        for (tam, urls) in porTamano where urls.count > 1 {
            var porHuella: [String: [URL]] = [:]
            for u in urls { if let h = huella(u) { porHuella[h, default: []].append(u) } }
            for (_, iguales) in porHuella where iguales.count > 1 {
                let ordenados = iguales.sorted { creacion($0) < creacion($1) }
                let original = ordenados[0]
                for copia in ordenados.dropFirst() {
                    items.append(ItemLimpieza(url: copia, nombre: copia.lastPathComponent,
                                              detalle: "igual a la de " + original.deletingLastPathComponent().lastPathComponent, bytes: tam))
                }
            }
        }
        guard !items.isEmpty else { return [] }
        items.sort { $0.bytes > $1.bytes }
        return [Limpiable(id: "duplicados", titulo: "Archivos duplicados", detalle: resumen(items) + " — se conserva la copia más antigua",
                          simbolo: "doc.on.doc", items: items, accion: .mostrar, boton: "Ver copias")]
    }

    /// Apps grandes que no son de Apple y no están abiertas: tú decides si alguna sobra.
    static func appsGrandes(_ abiertas: [String: String]) -> [Limpiable] {
        let enUso = Set(abiertas.values)
        let items = contenido(URL(fileURLWithPath: "/Applications")).compactMap { app -> ItemLimpieza? in
            guard app.pathExtension == "app", let id = Bundle(url: app)?.bundleIdentifier, !id.hasPrefix("com.apple."),
                  !enUso.contains(id), let b = bytes(app), b > 300_000_000 else { return nil }
            return ItemLimpieza(url: app, nombre: app.deletingPathExtension().lastPathComponent, detalle: "/Applications", bytes: b)
        }.sorted { $0.bytes > $1.bytes }
        guard !items.isEmpty else { return [] }
        return [Limpiable(id: "apps", titulo: "Apps grandes", detalle: resumen(items) + " — si alguna no la usas, arrástrala a la Papelera",
                          simbolo: "square.grid.2x2", items: items, accion: .mostrar, boton: "Ver en Finder")]
    }

    // MARK: Utilidades

    static func contenido(_ carpeta: URL) -> [URL] {
        (try? FileManager.default.contentsOfDirectory(at: carpeta, includingPropertiesForKeys: nil)) ?? []
    }

    static func esCarpeta(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])).map { $0.isDirectory == true && $0.isSymbolicLink != true } ?? false
    }

    /// Una carpeta que cambió en los últimos 15 minutos probablemente la está usando una app.
    static func enUsoReciente(_ url: URL) -> Bool {
        let fecha = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
        return Date().timeIntervalSince(fecha) < 15 * 60
    }

    /// Última modificación de un proyecto, sin contar dependencias ni git (máx. 4 niveles y 3 000 archivos).
    static func ultimaActividad(_ proyecto: URL) -> Date? {
        var ultima: Date?
        var vistos = 0
        let saltar: Set = ["node_modules", ".venv", "venv", ".git", "dist", "build", ".next", "__pycache__", ".turbo"]
        func recorrer(_ dir: URL, _ nivel: Int) {
            guard nivel < 4, vistos < 3000 else { return }
            for h in contenido(dir) where !saltar.contains(h.lastPathComponent) {
                vistos += 1
                if let f = (try? h.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate, f > (ultima ?? .distantPast) {
                    ultima = f
                }
                if esCarpeta(h) { recorrer(h, nivel + 1) }
            }
        }
        recorrer(proyecto, 0)
        return ultima
    }

    /// Huella del contenido: primer y último mega (con el tamaño igual, basta para ubicar copias).
    static func huella(_ url: URL) -> String? {
        guard let h = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? h.close() }
        let inicio = (try? h.read(upToCount: 1 << 20)) ?? Data()
        let fin = (try? h.seekToEnd()).flatMap { tam -> Data? in
            try? h.seek(toOffset: tam > (1 << 20) ? tam - (1 << 20) : 0)
            return try? h.read(upToCount: 1 << 20)
        } ?? Data()
        var hasher = Hasher()
        hasher.combine(inicio)
        hasher.combine(fin)
        return String(hasher.finalize())
    }

    static func creacion(_ url: URL) -> Date {
        (try? url.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? .distantFuture
    }

    static func resumen(_ items: [ItemLimpieza]) -> String {
        items.prefix(3).map { "\($0.nombre) \(Medida.bytes(Double($0.bytes)))" }.joined(separator: " · ")
    }

    static func fechaCorta(_ fecha: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "es_CO")
        f.dateFormat = Calendar.current.isDate(fecha, equalTo: Date(), toGranularity: .year) ? "d MMM" : "d MMM yyyy"
        return f.string(from: fecha)
    }

    /// Tamaño real en disco de un archivo o carpeta (nil si no existe o no se puede leer).
    static func bytes(_ url: URL) -> Int64? {
        var esCarpeta: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &esCarpeta) else { return nil }
        let claves: Set<URLResourceKey> = [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey]
        guard esCarpeta.boolValue else {
            let v = try? url.resourceValues(forKeys: claves)
            return Int64(v?.totalFileAllocatedSize ?? v?.fileAllocatedSize ?? 0)
        }
        guard let e = FileManager.default.enumerator(at: url, includingPropertiesForKeys: Array(claves), options: [],
                                                     errorHandler: { _, _ in true }) else { return nil }
        var total: Int64 = 0
        for case let f as URL in e {
            let v = try? f.resourceValues(forKeys: claves)
            total += Int64(v?.totalFileAllocatedSize ?? v?.fileAllocatedSize ?? 0)
        }
        return total
    }

    /// Apps abiertas por id, nombre y ejecutable → su id: hay cachés que se llaman como la app ("Arc").
    /// Los ayudantes internos (p. ej. "Browser Helper" de Arc) cuentan como abiertos, pero el nombre lo pone
    /// la app visible.
    @MainActor static func appsAbiertas() -> [String: String] {
        var mapa: [String: String] = [:]
        let apps = NSWorkspace.shared.runningApplications.sorted { a, _ in a.activationPolicy != .regular }
        for app in apps {
            guard let b = app.bundleIdentifier else { continue }
            mapa[b] = b
            if let n = app.localizedName { mapa[n] = b; mapa[n.lowercased()] = b }
            if let e = app.executableURL?.lastPathComponent { mapa[e] = b }
        }
        return mapa
    }

    /// "company.thebrowser.Browser" → "Arc"; "com.anthropic.claudefordesktop.ShipIt" → "Claude (actualizaciones)".
    static func nombreApp(_ id: String) -> String {
        var partes = id.split(separator: ".").map(String.init)
        var sufijo = ""
        while partes.count >= 3 {
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: partes.joined(separator: ".")) {
                return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "") + sufijo
            }
            sufijo = id.hasSuffix("ShipIt") ? " (actualizaciones)" : ""
            partes.removeLast()
        }
        return id
    }
}

// MARK: - Bitácora (para deshacer)

/// Cada limpieza queda anotada (qué se movió y a dónde) en ~/Library/Application Support/Dictado/limpiezas.json,
/// así "Deshacer" devuelve todo a su lugar aunque hayas cerrado el panel o reiniciado.
struct RegistroLimpieza: Codable {
    struct Movimiento: Codable { let original: String; let papelera: String; let bytes: Int64 }
    let fecha: Date
    let titulo: String
    let movimientos: [Movimiento]
    var bytes: Int64 { movimientos.reduce(0) { $0 + $1.bytes } }
}

enum Bitacora {
    static var archivo: URL { Ajustes.archivoVocabulario.deletingLastPathComponent().appendingPathComponent("limpiezas.json") }

    static func todas() -> [RegistroLimpieza] {
        guard let datos = try? Data(contentsOf: archivo) else { return [] }
        return (try? JSONDecoder().decode([RegistroLimpieza].self, from: datos)) ?? []
    }

    private static func escribir(_ lista: [RegistroLimpieza]) {
        if let datos = try? JSONEncoder().encode(Array(lista.suffix(50))) { try? datos.write(to: archivo, options: .atomic) }
    }

    /// Mueve a la Papelera y anota. Devuelve el registro (vacío si nada se pudo mover).
    static func mover(_ items: [ItemLimpieza], titulo: String) -> RegistroLimpieza {
        var hechos: [RegistroLimpieza.Movimiento] = []
        for item in items where !Escaner.protegido(item.url) {
            var destino: NSURL?
            if (try? FileManager.default.trashItem(at: item.url, resultingItemURL: &destino)) != nil, let d = destino?.path {
                hechos.append(.init(original: item.url.path, papelera: d, bytes: item.bytes))
            }
        }
        let registro = RegistroLimpieza(fecha: Date(), titulo: titulo, movimientos: hechos)
        if !hechos.isEmpty { escribir(todas() + [registro]) }
        return registro
    }

    /// Devuelve a su lugar lo de una limpieza (lo que siga en la Papelera). Cuántos volvieron.
    static func deshacer(_ registro: RegistroLimpieza) -> Int {
        var vueltos = 0
        for m in registro.movimientos where FileManager.default.fileExists(atPath: m.papelera) && !FileManager.default.fileExists(atPath: m.original) {
            let original = URL(fileURLWithPath: m.original)
            try? FileManager.default.createDirectory(at: original.deletingLastPathComponent(), withIntermediateDirectories: true)
            if (try? FileManager.default.moveItem(at: URL(fileURLWithPath: m.papelera), to: original)) != nil { vueltos += 1 }
        }
        escribir(todas().filter { $0.fecha != registro.fecha })
        return vueltos
    }
}

// MARK: - Formato

enum Medida {
    /// 8 900 000 000 → "8,9 GB"; 640 000 000 → "640 MB".
    static func bytes(_ b: Double) -> String {
        if b >= 1e9 { return String(format: "%.1f GB", b / 1e9).replacingOccurrences(of: ".", with: ",") }
        if b >= 1e6 { return String(format: "%.0f MB", b / 1e6) }
        return String(format: "%.0f KB", b / 1e3)
    }

    static func porcentaje(_ f: Double) -> String { "\(Int((f * 100).rounded())) %" }
}
