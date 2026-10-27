import AppKit
import AVFoundation
import Carbon.HIToolbox
import ServiceManagement
import os

enum Modo { case pegar, inbox }

private let log = Logger(subsystem: "app.dictado", category: "app")

/// App de barra de menú. ⌥Espacio (mantener): dicta y pega. ⌥⇧Espacio (mantener): dicta a _inbox/. Esc: cancela.
@MainActor
final class App: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private enum Atajo: UInt32 { case pegar = 1, inbox = 2, portapapeles = 3, captura = 4, cancelar = 9 }

    private var item: NSStatusItem!
    private let hud = HUD()
    private let ajustes = Ajustes()
    private var reconocedor: Reconocedor?
    private var sesion: SesionEnVivo?
    private var modo = Modo.pegar
    private var inicio = Date()
    private var ultimo = ""

    private let itemEstado = NSMenuItem(title: "Preparando el modelo de voz…", action: nil, keyEquivalent: "")
    private let itemUltimo = NSMenuItem(title: "Último dictado: —", action: #selector(copiarUltimo), keyEquivalent: "")
    private let itemPermiso = NSMenuItem(title: "⚠︎ Activa Accesibilidad para pegar…", action: #selector(abrirAccesibilidad), keyEquivalent: "")
    private let itemInicio = NSMenuItem(title: "Abrir al iniciar sesión", action: #selector(alternarInicio), keyEquivalent: "")
    private var menuEstilos: NSMenu?
    private var portapapeles: Portapapeles!
    private var atajoPortapapeles = false
    private var atajoCaptura = false
    private var reintento: Timer?
    private var textoEstado = ""
    private let itemPortapapeles = NSMenuItem(title: "Portapapeles", action: #selector(abrirPortapapeles), keyEquivalent: "")
    private let captura = Captura()
    private var salud: Salud!
    /// Módulos opcionales vivos (ver Funciones.swift y docs/FUNCIONES.md).
    private var modulos: [AnyObject] = []
    /// Transformación del texto dictado antes de pegarlo (la registra el módulo de pulido con IA).
    private var pulidor: (@MainActor (String) async -> String)?
    private let menuFunciones = NSMenu()
    private let itemSalud = NSMenuItem(title: "Salud del Mac…", action: #selector(abrirSalud), keyEquivalent: "")
    private let itemCentro = NSMenuItem(title: "Centro de mando…", action: #selector(abrirCentro), keyEquivalent: "")
    /// La ventana del centro de mando (CentroVentana.swift): se crea al pedirla por primera vez.
    private var centro: Centro?
    /// El bloque de foco: lo comparten la isla (anillo y pregunta final), el Centro (empezar desde una prioridad) y
    /// Hyper + F.
    private let foco = Foco()
    private var isla: Isla?
    private var diagnostico: Timer?
    private var ultimoEstado = ""
    /// Si hay isla en el notch, el dictado y los avisos se muestran ahí; si no, en el indicador de abajo.
    private var usaIsla: Bool { isla?.activa == true }
    private let itemIsla = NSMenuItem(title: "Isla en el notch (Spotify y calendario)", action: #selector(alternarIsla), keyEquivalent: "")
    private let itemNiveles = NSMenuItem(title: "Volumen y brillo en la isla", action: #selector(alternarNiveles), keyEquivalent: "")
    private let itemCaptura = NSMenuItem(title: "Captura  ⌘↩", action: #selector(abrirCaptura), keyEquivalent: "")
    private let itemGrabar = NSMenuItem(title: "Grabar reunión  (Hyper + R)", action: #selector(alternarNotas), keyEquivalent: "")
    private let itemAvisoGrabar = NSMenuItem(title: "Copiar aviso de grabación", action: #selector(copiarAvisoNotas), keyEquivalent: "")
    private let menuCalendarios = NSMenu()

    func applicationDidFinishLaunching(_ notification: Notification) {
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        icono("mic")
        hud.estado.estilo = ajustes.estilo
        let historial = Historial(carpeta: Ajustes.carpetaPortapapeles)
        historial.vigilar()
        portapapeles = Portapapeles(historial: historial)
        portapapeles.alGuardarEnInbox = { [weak self] texto in self?.guardarEnInbox(texto) }
        captura.alTerminar = { [weak self] texto, icono, nota in
            self?.avisar(texto, icono: icono, nota: nota, segundos: texto.isEmpty ? 1.6 : 2.6)
        }
        salud = Salud()
        DistributedNotificationCenter.default().addObserver(forName: .abrirCentro, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.abrirCentro() }
        }
        salud.alAlertar = { [weak self] titulo, detalle, gravedad in
            self?.isla?.mostrar(.salud(titulo: titulo, detalle: detalle, grave: gravedad == .mal), segundos: 8)
        }
        if ajustes.isla { crearIsla() }
        // Cada pasada pregunta a macOS por los permisos: cada 20 s basta (los cambios importantes llaman a estado()).
        diagnostico = Timer.scheduledTimer(withTimeInterval: 20, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.estado(self?.textoEstado ?? "") }
        }
        construirMenu()
        registrarAtajos()
        registrarPortapapeles()
        asegurarInicio()
        instalarModulos()
        Task { await preparar() }
    }

    // MARK: - Módulos opcionales

    /// MÓDULOS: una línea por módulo (ver docs/FUNCIONES.md). Para quitar uno del todo: borra su línea aquí,
    /// su archivo en Sources/Dictado y su caso en `Funcion`.
    private func instalarModulos() {
        let contexto = ContextoModulos(
            avisar: { [weak self] texto, icono, nota in self?.avisar(texto, icono: icono, nota: nota) },
            guardarIdea: { [weak self] texto in self?.guardarEnInbox(texto) },
            abrirPortapapeles: { [weak self] in self?.portapapeles.abrir() },
            abrirCaptura: { [weak self] in self?.captura.abrir() },
            abrirSalud: { [weak self] in self?.salud.abrir() },
            alternarCentro: { [weak self] in self?.alternarCentro() },
            alternarFoco: { [weak self] in self?.alternarFoco() },
            unirseAProxima: { [weak self] in self?.unirseAProxima() },
            alternarNotas: { [weak self] in self?.alternarNotas() },
            registrarPulido: { [weak self] pulir in self?.pulidor = pulir },
            pausarHistorial: { [weak self] si in self?.portapapeles.historial.pausar(si) })
        // ↓ módulos
        modulos.append(PulidoIA(contexto))
        modulos.append(AccionesTexto(contexto))
        modulos.append(TeclaHyper(contexto))
        modulos.append(VentanasTeclado(contexto))
        modulos.append(BuscadorVentanas(contexto))
        // ↑ módulos
    }

    @objc private func alternarNotas() {
        guard let isla else { return avisar("Grabar reuniones necesita la isla encendida", icono: "record.circle") }
        isla.alternarNotas()
    }

    @objc private func copiarAvisoNotas() { isla?.copiarAvisoNotas() }

    @objc private func alternarCalendario(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        isla?.agenda.alternarCalendario(id)
    }

    /// Calendarios de la agenda: los elegidos son los únicos que se ven en la isla y que preguntan si grabas.
    private func llenarCalendarios() {
        menuCalendarios.removeAllItems()
        let lista = isla?.agenda.calendarios() ?? []
        if lista.isEmpty {
            let i = NSMenuItem(title: "Sin acceso a Calendarios", action: nil, keyEquivalent: "")
            i.isEnabled = false
            menuCalendarios.addItem(i)
            return
        }
        var cuenta: String?
        for c in lista {
            if c.cuenta != cuenta {
                if cuenta != nil { menuCalendarios.addItem(.separator()) }
                let t = NSMenuItem(title: c.cuenta, action: nil, keyEquivalent: "")
                t.isEnabled = false
                menuCalendarios.addItem(t)
                cuenta = c.cuenta
            }
            let i = NSMenuItem(title: c.titulo.isEmpty ? "Sin nombre" : c.titulo, action: #selector(alternarCalendario(_:)), keyEquivalent: "")
            i.target = self
            i.representedObject = c.id
            i.state = c.activo ? .on : .off
            i.indentationLevel = 1
            menuCalendarios.addItem(i)
        }
    }

    private func unirseAProxima() {
        if let isla, isla.unirseAProxima() { return }
        avisar("No hay reuniones con enlace en la próxima hora", icono: "calendar.badge.exclamationmark")
    }

    /// Dictado se abre solo al iniciar sesión, salvo que lo apagues en el menú. Si macOS pide aprobarlo
    /// (Ajustes → General → Ítems de inicio), el menú lo avisa y lleva directo ahí.
    private func asegurarInicio() {
        let servicio = SMAppService.mainApp
        if ajustes.abrirAlIniciar && servicio.status != .enabled && servicio.status != .requiresApproval {
            do {
                try servicio.register()
            } catch {
                log.error("inicio de sesión: \(error.localizedDescription, privacy: .public)")
            }
        }
        actualizarItemInicio()
    }

    private func actualizarItemInicio() {
        switch SMAppService.mainApp.status {
        case .enabled:
            itemInicio.title = "Abrir al iniciar sesión"
            itemInicio.state = .on
        case .requiresApproval:
            itemInicio.title = "⚠︎ Aprueba Dictado en Ítems de inicio…"
            itemInicio.state = .off
        default:
            itemInicio.title = "Abrir al iniciar sesión"
            itemInicio.state = .off
        }
    }

    private var textoInicio: String {
        switch SMAppService.mainApp.status {
        case .enabled: return "sí"
        case .requiresApproval: return "falta aprobar"
        default: return "no"
        }
    }

    // MARK: - Preparación

    private func preparar() async {
        // El modelo carga mientras respondes los permisos.
        async let modelo = Reconocedor.preparar(motor: ajustes.motor, idioma: ajustes.idioma,
                                                vocabulario: ajustes.vocabulario())
        if AVCaptureDevice.authorizationStatus(for: .audio) == .notDetermined {
            _ = await AVCaptureDevice.requestAccess(for: .audio)
        }
        if !AXIsProcessTrusted() {
            let opciones = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(opciones)
        }
        do {
            let r = try await modelo
            reconocedor = r
            estado("Listo · \(r.locale.identifier) · motor \(r.motor.rawValue)")
            log.info("listo: \(r.locale.identifier, privacy: .public) \(r.motor.rawValue, privacy: .public)")
        } catch {
            estado("⚠︎ \(error.localizedDescription)")
            icono("exclamationmark.triangle")
            log.error("preparar: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func registrarAtajos() {
        let a = Atajos.shared
        let pegar = a.registrar(id: Atajo.pegar.rawValue, tecla: kVK_Space, modificadores: optionKey,
                                alPresionar: { [weak self] in self?.empezar(.pegar) },
                                alSoltar: { [weak self] in self?.soltar() })
        let inbox = a.registrar(id: Atajo.inbox.rawValue, tecla: kVK_Space, modificadores: optionKey | shiftKey,
                                alPresionar: { [weak self] in self?.empezar(.inbox) },
                                alSoltar: { [weak self] in self?.soltar() })
        atajoCaptura = a.registrar(id: Atajo.captura.rawValue, tecla: kVK_Return, modificadores: cmdKey,
                                   alPresionar: { [weak self] in self?.captura.alternar() })
        if !atajoCaptura { itemCaptura.title = "Captura (⌘↩ ocupado por otra app)" }
        if !(pegar && inbox) {
            estado("⚠︎ ⌥Espacio lo usa otra app (¿Handy abierto?)")
        }
    }

    /// ⌘⌥V. Si otra app lo tiene (Raycast), reintenta cada 5 s hasta que quede libre.
    private func registrarPortapapeles() {
        atajoPortapapeles = Atajos.shared.registrar(
            id: Atajo.portapapeles.rawValue, tecla: kVK_ANSI_V, modificadores: cmdKey | optionKey,
            alPresionar: { [weak self] in self?.portapapeles.alternar() })
        itemPortapapeles.title = atajoPortapapeles ? "Portapapeles  ⌘⌥V" : "Portapapeles (⌘⌥V ocupado: ¿Raycast abierto?)"
        estado(textoEstado)
        if atajoPortapapeles {
            reintento?.invalidate()
            reintento = nil
        } else if reintento == nil {
            reintento = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.registrarPortapapeles() }
            }
        }
    }

    @objc private func abrirPortapapeles() { portapapeles.abrir() }
    @objc private func abrirSalud() { salud.abrir() }
    @objc private func abrirCentro() {
        if centro == nil { centro = Centro(claude: isla?.claude, foco: foco) }
        centro?.abrir()
    }

    /// Hyper + F: sin bloque, empieza uno con la siguiente prioridad del brief (sus minutos); con uno en curso, muestra
    /// cómo va (o la pregunta, si ya terminó).
    private func alternarFoco() {
        if foco.activo != nil {
            isla?.mostrarFoco()
            return
        }
        let estado = (try? Data(contentsOf: CentroStore.cache)).flatMap(EstadoCentro.decodificar)
        let p = Foco.propuesta(estado, hechas: foco.hechas)
        foco.empezar(p.titulo, minutos: p.minutos, vertical: p.vertical)
        isla?.mostrar(.aviso(icono: "timer", texto: "Foco · \(p.minutos) min · \(p.titulo)"), segundos: 3)
    }

    /// Hyper + A: abre el centro de mando o, si ya está abierto, lo cierra.
    private func alternarCentro() {
        if centro?.abierta == true { centro?.cerrar() } else { abrirCentro() }
    }

    private func crearIsla() {
        isla = Isla(hud: hud.estado, niveles: ajustes.niveles, salud: salud, foco: foco)
    }
    @objc private func abrirCaptura() { captura.abrir() }

    @objc private func alternarIsla() {
        let activa = !ajustes.isla
        ajustes.guardar(isla: activa)
        if activa {
            if isla == nil {
                crearIsla()
            } else {
                isla?.montar()
                isla?.usarNiveles(ajustes.niveles)
            }
        } else {
            isla?.apagar()
        }
        itemIsla.state = activa ? .on : .off
        itemNiveles.isEnabled = activa
    }

    /// Las teclas de volumen y brillo muestran la barra en la isla o el cuadro de siempre de macOS.
    @objc private func alternarNiveles() {
        let si = !ajustes.niveles
        ajustes.guardar(niveles: si)
        isla?.usarNiveles(si && ajustes.isla)
        itemNiveles.state = si ? .on : .off
    }

    // MARK: - Push-to-talk

    private func empezar(_ modo: Modo) {
        guard sesion == nil else { return }  // la tecla mantenida repite el evento
        guard let reconocedor else {
            hud.aviso("El modelo de voz aún se está preparando")
            return
        }
        guard AVCaptureDevice.authorizationStatus(for: .audio) == .authorized else {
            hud.aviso("Falta permiso de micrófono", icono: "mic.slash")
            abrirAjustes("Privacy_Microphone")
            return
        }
        reconocedor.vocabulario = ajustes.vocabulario()
        let s = SesionEnVivo(reconocedor)
        let correcciones = ajustes.correcciones()
        s.alNivel = { [weak self] n in DispatchQueue.main.async { self?.hud.nivel(n) } }
        s.alParcial = { [weak self] texto in
            let corregido = Transcripcion.corregir(texto, con: correcciones)
            DispatchQueue.main.async { self?.hud.parcial(corregido) }
        }
        do {
            try s.iniciar()
        } catch {
            fallo(error)
            return
        }
        sesion = s
        self.modo = modo
        inicio = Date()
        icono("mic.fill", color: .systemRed)
        hud.escuchar(inbox: modo == .inbox, mostrar: !usaIsla)
        if usaIsla { isla?.empezarDictado() }
        Atajos.shared.registrar(id: Atajo.cancelar.rawValue, tecla: kVK_Escape, modificadores: 0,
                                alPresionar: { [weak self] in self?.cancelar() })
    }

    private func soltar() {
        guard let s = sesion else { return }
        Atajos.shared.quitar(id: Atajo.cancelar.rawValue)
        if Date().timeIntervalSince(inicio) < 0.3 {  // toque accidental
            cancelar()
            return
        }
        icono("waveform")
        hud.transcribiendo()
        let modo = self.modo
        Task {
            do {
                let texto = Transcripcion.corregir(try await s.terminar(), con: ajustes.correcciones())
                await entregar(texto, modo)
            } catch {
                fallo(error)
            }
            sesion = nil
        }
    }

    private func cancelar() {
        Atajos.shared.quitar(id: Atajo.cancelar.rawValue)
        sesion?.cancelar()
        sesion = nil
        icono("mic")
        hud.ocultar()
        isla?.cancelarDictado()
    }

    private func entregar(_ texto: String, _ modo: Modo) async {
        defer { icono("mic") }
        guard !texto.isEmpty else {
            avisar("No escuché nada", icono: "mic.slash", segundos: 1.2)
            return
        }
        var texto = texto
        if Funcion.pulido.activa, let pulidor {
            texto = await pulidor(texto)
        }
        ultimo = texto
        itemUltimo.title = "Último: " + (texto.count > 50 ? texto.prefix(50) + "…" : texto)
        switch modo {
        case .pegar:
            switch await Salida.entregar(texto) {
            case .pegado:
                if usaIsla { isla?.terminarDictado(icono: "checkmark.circle.fill", texto: "Pegado") } else { hud.resultado(texto, segundos: 0.9) }
            case .copiado:
                avisar(texto, icono: "doc.on.clipboard", nota: "Copiado al portapapeles", segundos: 2.2)
            case .sinPermiso:
                avisar(texto, icono: "doc.on.clipboard", nota: "Copiado · activa Accesibilidad para pegar", segundos: 2.8)
                itemPermiso.isHidden = false
            }
        case .inbox:
            guardarEnInbox(texto)
        }
    }

    /// Guarda una idea en tu carpeta de ideas (dictado con ⌥⇧Espacio o recorte con ⌘I en el portapapeles).
    private func guardarEnInbox(_ texto: String) {
        do {
            let archivo = try Inbox.guardar(texto, en: ajustes.carpetaInbox)
            DispatchQueue.global(qos: .utility).async { Inbox.commitear(archivo) }
            NSSound(named: "Pop")?.play()
            avisar(texto, icono: "tray.and.arrow.down", nota: "Guardado en _inbox", segundos: 1.8)
        } catch {
            fallo(error)
        }
    }

    /// Estado visible en el menú y en ~/Library/Application Support/Dictado/estado.txt (diagnóstico).
    private func estado(_ texto: String) {
        textoEstado = texto
        itemEstado.title = texto
        let url = Ajustes.archivoVocabulario.deletingLastPathComponent().appendingPathComponent("estado.txt")
        let atajo = atajoPortapapeles ? "⌘⌥V listo" : "⌘⌥V ocupado"
        let captura = atajoCaptura ? "⌘↩ listo" : "⌘↩ ocupado"
        let permisos = [
            "accesibilidad: " + (AXIsProcessTrusted() ? "sí" : "no"),
            "micrófono: " + (AVCaptureDevice.authorizationStatus(for: .audio) == .authorized ? "sí" : "no"),
            "isla: " + (isla?.activa == true ? "sí" : "no"),
            "calendario: " + (isla?.agenda.permitido == true ? "sí" : "no"),
            "volumen/brillo: " + (isla?.interceptaNiveles == true ? "sí" : "no"),
            "abre al iniciar: " + textoInicio,
        ].joined(separator: " · ")
        let linea = "\(texto) · portapapeles: \(atajo) · captura: \(captura) · \(permisos)"
        guard linea != ultimoEstado else { return }
        ultimoEstado = linea
        try? "\(Date()) \(linea)\n".write(to: url, atomically: true, encoding: .utf8)
    }

    private func fallo(_ error: Error) {
        log.error("\(error.localizedDescription, privacy: .public)")
        sesion = nil
        icono("mic")
        avisar(error.localizedDescription, icono: "exclamationmark.triangle", segundos: 3)
    }

    /// Aviso corto: en la isla (ícono + nota) si existe; si no, en el indicador de abajo.
    private func avisar(_ texto: String, icono: String, nota: String? = nil, segundos: Double = 2) {
        if usaIsla {
            if isla?.estado.dictando == true || nota != nil || texto.count < 40 {
                isla?.terminarDictado(icono: icono, texto: nota ?? texto)
            } else {
                isla?.mostrar(.aviso(icono: icono, texto: texto), segundos: segundos)
            }
        } else if let nota {
            hud.resultado(texto, icono: icono, nota: nota, segundos: segundos)
        } else {
            hud.aviso(texto, icono: icono, segundos: segundos)
        }
    }

    // MARK: - Menú

    private func construirMenu() {
        let menu = NSMenu()
        itemEstado.isEnabled = false
        menu.addItem(itemEstado)
        let ayuda = NSMenuItem(title: "Mantén ⌥Espacio: dicta y pega (o copia) · ⌥⇧Espacio: idea a _inbox · Esc: cancela",
                               action: nil, keyEquivalent: "")
        ayuda.isEnabled = false
        menu.addItem(ayuda)
        menu.addItem(.separator())
        itemPortapapeles.target = self
        menu.addItem(itemPortapapeles)
        itemCaptura.target = self
        menu.addItem(itemCaptura)
        itemSalud.target = self
        menu.addItem(itemSalud)
        itemCentro.target = self
        menu.addItem(itemCentro)
        itemIsla.target = self
        itemIsla.state = ajustes.isla ? .on : .off
        menu.addItem(itemIsla)
        itemNiveles.target = self
        itemNiveles.state = ajustes.niveles ? .on : .off
        itemNiveles.isEnabled = ajustes.isla
        itemNiveles.indentationLevel = 1
        menu.addItem(itemNiveles)
        itemGrabar.target = self
        menu.addItem(itemGrabar)
        itemAvisoGrabar.target = self
        itemAvisoGrabar.indentationLevel = 1
        menu.addItem(itemAvisoGrabar)
        let itemCalendarios = NSMenuItem(title: "Calendarios de la agenda", action: nil, keyEquivalent: "")
        itemCalendarios.submenu = menuCalendarios
        menu.addItem(itemCalendarios)
        let itemFunciones = NSMenuItem(title: "Funciones", action: nil, keyEquivalent: "")
        itemFunciones.submenu = menuFunciones
        for f in Funcion.allCases {
            let i = NSMenuItem(title: f.titulo, action: #selector(alternarFuncion(_:)), keyEquivalent: "")
            i.target = self
            i.representedObject = f.rawValue
            i.toolTip = f.detalle
            menuFunciones.addItem(i)
        }
        menu.addItem(itemFunciones)
        itemUltimo.target = self
        menu.addItem(itemUltimo)
        itemPermiso.target = self
        itemPermiso.isHidden = AXIsProcessTrusted()
        menu.addItem(itemPermiso)
        menu.addItem(.separator())
        menu.addItem(accion("Abrir _inbox", #selector(abrirInbox)))
        menu.addItem(accion("Editar vocabulario…", #selector(editarVocabulario)))
        let estilos = NSMenu()
        for e in Estilo.allCases {
            let i = NSMenuItem(title: e.nombre, action: #selector(elegirEstilo(_:)), keyEquivalent: "")
            i.target = self
            i.representedObject = e.rawValue
            estilos.addItem(i)
        }
        let itemEstilo = NSMenuItem(title: "Estilo", action: nil, keyEquivalent: "")
        itemEstilo.submenu = estilos
        menu.addItem(itemEstilo)
        self.menuEstilos = estilos
        itemInicio.target = self
        actualizarItemInicio()
        menu.addItem(itemInicio)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Salir de Dictado", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        menu.delegate = self
        item.menu = menu
    }

    /// Prende o apaga una función opcional; el módulo se entera por la notificación funcionesCambiaron.
    @objc private func alternarFuncion(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String, let f = Funcion(rawValue: id) else { return }
        f.poner(!f.activa)
    }

    func menuWillOpen(_ menu: NSMenu) {
        menuFunciones.items.forEach { i in
            i.state = (i.representedObject as? String).flatMap(Funcion.init(rawValue:))?.activa == true ? .on : .off
        }
        menuEstilos?.items.forEach { $0.state = ($0.representedObject as? String) == hud.estado.estilo.rawValue ? .on : .off }
        itemPermiso.isHidden = AXIsProcessTrusted()
        actualizarItemInicio()
        let grabando = isla?.notas.grabando == true
        itemGrabar.title = grabando ? "Terminar la grabación  (Hyper + R)" : "Grabar reunión  (Hyper + R)"
        itemGrabar.isEnabled = isla != nil
        itemAvisoGrabar.isHidden = !grabando
        llenarCalendarios()
    }

    private func accion(_ titulo: String, _ selector: Selector) -> NSMenuItem {
        let i = NSMenuItem(title: titulo, action: selector, keyEquivalent: "")
        i.target = self
        return i
    }

    /// Cambia el estilo y lo muestra un momento para que lo veas.
    @objc private func elegirEstilo(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String, let e = Estilo(rawValue: id) else { return }
        ajustes.guardar(estilo: e)
        hud.estado.estilo = e
        hud.resultado("Así se ve \(e.nombre)", icono: "sparkles", segundos: 2.5)
    }

    @objc private func copiarUltimo() {
        guard !ultimo.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(ultimo, forType: .string)
    }

    @objc private func abrirInbox() { NSWorkspace.shared.open(ajustes.carpetaInbox) }

    @objc private func editarVocabulario() {
        _ = ajustes.vocabulario()  // crea el archivo si no existe
        NSWorkspace.shared.open(Ajustes.archivoVocabulario)
    }

    @objc private func abrirAccesibilidad() { abrirAjustes("Privacy_Accessibility") }

    @objc private func alternarInicio() {
        let servicio = SMAppService.mainApp
        if servicio.status == .requiresApproval {
            SMAppService.openSystemSettingsLoginItems()
            return
        }
        do {
            if servicio.status == .enabled {
                try servicio.unregister()
                ajustes.guardar(abrirAlIniciar: false)
            } else {
                try servicio.register()
                ajustes.guardar(abrirAlIniciar: true)
            }
        } catch {
            hud.aviso(error.localizedDescription, icono: "exclamationmark.triangle", segundos: 3)
        }
        actualizarItemInicio()
        estado(textoEstado)
    }

    private func abrirAjustes(_ panel: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(panel)") {
            NSWorkspace.shared.open(url)
        }
    }

    private func icono(_ simbolo: String, color: NSColor? = nil) {
        var imagen = NSImage(systemSymbolName: simbolo, accessibilityDescription: "Dictado")
        if let color {
            imagen = imagen?.withSymbolConfiguration(.init(paletteColors: [color]))
            imagen?.isTemplate = false
        } else {
            imagen?.isTemplate = true
        }
        item.button?.image = imagen
    }
}
