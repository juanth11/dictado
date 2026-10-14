import AppKit
import ApplicationServices
import Carbon.HIToolbox

// Ventanas por teclado: solo lo que macOS 26 no trae de serie (su mosaico ya hace mitades y cuartos con fn⌃).
//   Hyper + ←/→   mitad → tercio → dos tercios del lado, en ciclo al repetir
//   Hyper + ↑     casi maximizar (margen pequeño); otra vez, vuelve al tamaño previo
//   Hyper + ↓     restaurar el tamaño previo
//   Hyper + N     a la siguiente pantalla, con las mismas proporciones (girada si cambia de orientación)
//   Hyper + ↩     centrar
// En una pantalla vertical (un monitor girado) las mitades van arriba y abajo, y una mitad de lado quedaría angosta:
//   Hyper + ↑/↓   mitad → tercio → dos tercios, arriba o abajo y a todo el ancho
//   Hyper + ←/→   a la pantalla de ese lado (a la mitad que da hacia la vertical, si es horizontal)
//   Hyper + ↩     casi maximizar; otra vez, vuelve al tamaño previo
// Y en cualquier pantalla:
//   Hyper + D     la ventana al frente y la que usaste antes, juntas en la pantalla de la del frente: arriba y abajo
//                 en una vertical, lado a lado en una horizontal. Al repetir, el reparto pasa de ⅔ + ⅓ a ½ + ½ y a ⅓ + ⅔
// La geometría vive en `GeometriaVentanas` (funciones puras, se prueban con --probar-ventanas); aquí solo se lee
// y se escribe la ventana por Accesibilidad.

enum AccionVentana: Equatable {
    case izquierda, derecha, casiMaximizar, restaurar, otraPantalla, centrar
    /// Hyper + D (dos ventanas a la vez): no pasa por `plan`; se registra para que ↓ / ↩ puedan volver al previo.
    case disponer
}

/// Interruptor del módulo: registra los atajos según `Funcion.ventanas` y mueve la ventana enfocada.
@MainActor
final class VentanasTeclado {
    /// Lo que se recuerda de una ventana: su marco antes de que Dictado la tocara y lo último que le hizo.
    private struct Recuerdo {
        let ventana: AXUIElement
        var memoria: MemoriaVentana
    }

    /// La última disposición (Hyper + D): si al repetir siguen igual, se pasa al siguiente reparto.
    private struct Disposicion {
        let frente: AXUIElement
        let otra: AXUIElement
        var marco: CGRect
        var paso: Int
    }

    private let contexto: ContextoModulos
    private var recuerdos: [Recuerdo] = []
    private var disposicion: Disposicion?
    private var registrados = false
    /// Ids de Carbon reservados para este módulo: 30-39.
    private static let atajos: [(id: UInt32, tecla: Int, accion: AccionVentana)] = [
        (30, kVK_LeftArrow, .izquierda), (31, kVK_RightArrow, .derecha), (32, kVK_UpArrow, .casiMaximizar),
        (33, kVK_DownArrow, .restaurar), (34, kVK_ANSI_N, .otraPantalla), (35, kVK_Return, .centrar),
        (36, kVK_ANSI_D, .disponer),
    ]

    init(_ contexto: ContextoModulos) {
        self.contexto = contexto
        NotificationCenter.default.addObserver(forName: .funcionesCambiaron, object: nil, queue: .main) { [weak self] nota in
            guard (nota.userInfo?["funcion"] as? String) == Funcion.ventanas.rawValue else { return }
            MainActor.assumeIsolated { self?.sincronizar() }
        }
        sincronizar()
    }

    private func sincronizar() {
        if Funcion.ventanas.activa {
            guard !registrados else { return }
            registrados = true
            let hyper = cmdKey | optionKey | controlKey | shiftKey
            let ocupados = Self.atajos.filter { a in
                !Atajos.shared.registrar(id: a.id, tecla: a.tecla, modificadores: hyper,
                                         alPresionar: { [weak self] in a.accion == .disponer ? self?.disponer() : self?.ejecutar(a.accion) })
            }
            if !ocupados.isEmpty {
                contexto.avisar("Algunos atajos de ventanas los usa otra app", "keyboard.badge.exclamationmark", nil)
            }
        } else {
            guard registrados else { return }
            registrados = false
            Self.atajos.forEach { Atajos.shared.quitar(id: $0.id) }
            recuerdos = []
            disposicion = nil
        }
    }

    func ejecutar(_ accion: AccionVentana) {
        guard AXIsProcessTrusted() else {
            contexto.avisar("Activa Accesibilidad para mover ventanas", "lock", nil)
            return
        }
        guard let app = NSWorkspace.shared.frontmostApplication, app.processIdentifier != getpid() else { return }
        let appAX = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(appAX, 0.3)  // una app colgada no traba el atajo
        guard let ventana = AX.elemento(appAX, kAXFocusedWindowAttribute) ?? AX.elemento(appAX, kAXMainWindowAttribute) else {
            contexto.avisar("No hay una ventana que mover", "macwindow", nil)
            return
        }
        AXUIElementSetMessagingTimeout(ventana, 0.3)
        if AX.bool(ventana, "AXFullScreen") == true {
            contexto.avisar("La ventana está en pantalla completa", "arrow.down.right.and.arrow.up.left", nil)
            return
        }
        guard let actual = AX.marco(ventana) else { return }
        let memoria = recuerdos.first { CFEqual($0.ventana, ventana) }?.memoria
        let pantallas = GeometriaVentanas.pantallas(NSScreen.screens.map { ($0.frame, $0.visibleFrame) })
        guard let plan = GeometriaVentanas.plan(accion, actual: actual, pantallas: pantallas, memoria: memoria) else {
            if GeometriaVentanas.enVertical(actual, pantallas: pantallas), accion == .izquierda || accion == .derecha {
                contexto.avisar("No hay otra pantalla a ese lado", "rectangle.portrait.arrowtriangle.2.outward", nil)
            } else if accion == .restaurar, memoria == nil {
                // Con memoria y sin plan, la ventana ya está en su tamaño previo: no hace falta avisar.
                contexto.avisar("No hay un tamaño previo que restaurar", "arrow.uturn.backward", nil)
            }
            return
        }
        acomodar(ventana, de: appAX, a: plan.marco, antes: actual, registro: plan.registro, paso: plan.paso)
    }

    /// Mueve la ventana y recuerda lo que le hizo (el previo para volver, y el paso del ciclo).
    @discardableResult
    private func acomodar(_ ventana: AXUIElement, de app: AXUIElement, a marco: CGRect, antes: CGRect,
                          registro: AccionVentana, paso: Int) -> CGRect {
        let indice = recuerdos.firstIndex { CFEqual($0.ventana, ventana) }
        let memoria = indice.map { recuerdos[$0].memoria }
        AX.mover(ventana, a: marco, app: app)
        let leido = AX.marco(ventana) ?? marco  // la app puede ajustar el tamaño (mínimos, celdas de texto)
        let nueva = GeometriaVentanas.recordar(memoria, accion: registro, antes: antes, leido: leido, paso: paso)
        if let indice { recuerdos.remove(at: indice) }
        recuerdos.insert(Recuerdo(ventana: ventana, memoria: nueva), at: 0)
        if recuerdos.count > 40 { recuerdos.removeLast() }  // las ventanas cerradas se olvidan solas
        return leido
    }

    /// Hyper + D: la ventana al frente y la anterior, juntas en la pantalla de la del frente.
    func disponer() {
        guard AXIsProcessTrusted() else {
            contexto.avisar("Activa Accesibilidad para mover ventanas", "lock", nil)
            return
        }
        guard let app = NSWorkspace.shared.frontmostApplication, app.processIdentifier != getpid() else { return }
        let appAX = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(appAX, 0.3)
        guard let frente = AX.elemento(appAX, kAXFocusedWindowAttribute) ?? AX.elemento(appAX, kAXMainWindowAttribute),
              let marcoFrente = AX.marco(frente) else {
            contexto.avisar("No hay una ventana que acomodar", "macwindow", nil)
            return
        }
        // ¿Repites sobre la misma pareja tal como quedó? Siguiente reparto. Si no, la ventana que usaste antes.
        var paso = 0
        var otra: (ventana: AXUIElement, app: AXUIElement, marco: CGRect)?
        if let d = disposicion, CFEqual(d.frente, frente), GeometriaVentanas.parecidos(marcoFrente, d.marco),
           let marcoOtra = AX.marco(d.otra) {
            var pid: pid_t = 0
            AXUIElementGetPid(d.otra, &pid)
            otra = (d.otra, AXUIElementCreateApplication(pid), marcoOtra)
            paso = d.paso + 1
        } else {
            otra = Self.anterior(a: marcoFrente, pidFrente: app.processIdentifier)
        }
        guard let otra else {
            contexto.avisar("No hay otra ventana para acomodar al lado", "rectangle.split.1x2", nil)
            return
        }
        let pantallas = GeometriaVentanas.pantallas(NSScreen.screens.map { ($0.frame, $0.visibleFrame) })
        guard let i = GeometriaVentanas.indice(de: marcoFrente, en: pantallas) else { return }
        let reparto = GeometriaVentanas.disposicion(paso: paso, en: pantallas[i].visible)
        let quedo = acomodar(frente, de: appAX, a: reparto.frente, antes: marcoFrente, registro: .disponer, paso: paso)
        AXUIElementSetMessagingTimeout(otra.ventana, 0.3)
        acomodar(otra.ventana, de: otra.app, a: reparto.otra, antes: otra.marco, registro: .disponer, paso: paso)
        disposicion = Disposicion(frente: frente, otra: otra.ventana, marco: quedo, paso: paso)
    }

    /// La ventana que usaste antes de la del frente: la siguiente en el orden de pantalla (de adelante hacia atrás),
    /// de una app normal y de tamaño de ventana (no menús, avisos ni la isla).
    private static func anterior(a marcoFrente: CGRect, pidFrente: pid_t) -> (ventana: AXUIElement, app: AXUIElement, marco: CGRect)? {
        let lista = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        for w in lista {
            guard (w[kCGWindowLayer as String] as? Int) == 0, (w[kCGWindowAlpha as String] as? Double ?? 1) > 0,
                  let pid = w[kCGWindowOwnerPID as String] as? pid_t, pid != getpid(),
                  let b = w[kCGWindowBounds as String] as? [String: CGFloat] else { continue }
            let marco = CGRect(x: b["X"] ?? 0, y: b["Y"] ?? 0, width: b["Width"] ?? 0, height: b["Height"] ?? 0)
            guard marco.width >= 200, marco.height >= 120 else { continue }
            if pid == pidFrente && GeometriaVentanas.parecidos(marco, marcoFrente) { continue }   // la del frente
            guard NSRunningApplication(processIdentifier: pid)?.activationPolicy == .regular else { continue }
            let appAX = AXUIElementCreateApplication(pid)
            AXUIElementSetMessagingTimeout(appAX, 0.3)
            let ventanas = AX.valor(appAX, kAXWindowsAttribute) as? [AXUIElement] ?? []
            if let v = ventanas.first(where: { AX.marco($0).map { GeometriaVentanas.parecidos($0, marco) } ?? false }) {
                return (v, appAX, marco)
            }
        }
        return nil
    }
}

// MARK: - Geometría (pura)

/// Una pantalla en coordenadas de Accesibilidad: origen arriba a la izquierda de la pantalla principal, y hacia
/// abajo. `visible` descuenta la barra de menús y el Dock.
struct PantallaAX: Equatable {
    var marco: CGRect
    var visible: CGRect
}

/// Lo que se recuerda de una ventana para poder restaurar y para seguir el ciclo de tamaños.
struct MemoriaVentana: Equatable {
    /// El marco antes de que Dictado la acomodara (lo que restaura Hyper + ↓).
    var previo: CGRect
    /// El marco que quedó tras la última acción, leído de la ventana (no el pedido: la app pudo ajustarlo).
    var ultimo: CGRect
    /// Lo que quedó registrado (no siempre la tecla: volver al previo con ↑ queda como "restaurar").
    var accion: AccionVentana
    var paso: Int
}

enum GeometriaVentanas {
    /// Ciclo de Hyper + ←/→: mitad, tercio, dos tercios.
    static let fracciones: [CGFloat] = [1.0 / 2, 1.0 / 3, 2.0 / 3]
    static let margenCasi: CGFloat = 12
    /// Tolerancia al comparar marcos: las apps redondean el tamaño a su manera.
    static let tolerancia: CGFloat = 4

    /// NSScreen mide desde abajo a la izquierda de la pantalla principal; Accesibilidad, desde arriba.
    static func aAX(_ r: CGRect, alturaPrincipal: CGFloat) -> CGRect {
        CGRect(x: r.minX, y: alturaPrincipal - r.maxY, width: r.width, height: r.height)
    }

    /// Pantallas en coordenadas AX a partir de (frame, visibleFrame) de NSScreen. La principal es la de origen (0, 0).
    static func pantallas(_ cocoa: [(marco: CGRect, visible: CGRect)]) -> [PantallaAX] {
        guard let principal = cocoa.first(where: { $0.marco.origin == .zero }) ?? cocoa.first else { return [] }
        let h = principal.marco.height
        return cocoa.map { PantallaAX(marco: aAX($0.marco, alturaPrincipal: h), visible: aAX($0.visible, alturaPrincipal: h)) }
    }

    /// La pantalla donde está la mayor parte de la ventana; si no toca ninguna, la más cercana a su centro.
    static func indice(de ventana: CGRect, en pantallas: [PantallaAX]) -> Int? {
        guard !pantallas.isEmpty else { return nil }
        let areas = pantallas.map { p -> CGFloat in
            let i = p.marco.intersection(ventana)
            return i.isNull ? 0 : i.width * i.height
        }
        if let mayor = areas.max(), mayor > 0 { return areas.firstIndex(of: mayor) }
        let centro = CGPoint(x: ventana.midX, y: ventana.midY)
        return pantallas.indices.min { a, b in
            distancia(centro, pantallas[a].marco) < distancia(centro, pantallas[b].marco)
        }
    }

    private static func distancia(_ p: CGPoint, _ r: CGRect) -> CGFloat {
        hypot(p.x - r.midX, p.y - r.midY)
    }

    static func lado(izquierda: Bool, paso: Int, en v: CGRect) -> CGRect {
        let ancho = (v.width * fracciones[paso % fracciones.count]).rounded()
        return CGRect(x: izquierda ? v.minX : v.maxX - ancho, y: v.minY, width: ancho, height: v.height)
    }

    /// Lo mismo que `lado` pero arriba o abajo y a todo el ancho (pantallas verticales).
    static func franja(arriba: Bool, paso: Int, en v: CGRect) -> CGRect {
        let alto = (v.height * fracciones[paso % fracciones.count]).rounded()
        return CGRect(x: v.minX, y: arriba ? v.minY : v.maxY - alto, width: v.width, height: alto)
    }

    /// Hyper + D: cuánto le toca a la ventana del frente, en ciclo.
    static let repartos: [CGFloat] = [2.0 / 3, 1.0 / 2, 1.0 / 3]

    /// La del frente arriba y la otra abajo en una pantalla vertical; lado a lado (la del frente a la izquierda) en una
    /// horizontal.
    static func disposicion(paso: Int, en v: CGRect) -> (frente: CGRect, otra: CGRect) {
        let f = repartos[paso % repartos.count]
        if vertical(v) {
            let alto = (v.height * f).rounded()
            return (CGRect(x: v.minX, y: v.minY, width: v.width, height: alto),
                    CGRect(x: v.minX, y: v.minY + alto, width: v.width, height: v.height - alto))
        }
        let ancho = (v.width * f).rounded()
        return (CGRect(x: v.minX, y: v.minY, width: ancho, height: v.height),
                CGRect(x: v.minX + ancho, y: v.minY, width: v.width - ancho, height: v.height))
    }

    /// Más alta que ancha: un monitor girado.
    static func vertical(_ v: CGRect) -> Bool { v.height > v.width }

    /// ¿La ventana está en una pantalla vertical?
    static func enVertical(_ ventana: CGRect, pantallas: [PantallaAX]) -> Bool {
        indice(de: ventana, en: pantallas).map { vertical(pantallas[$0].visible) } ?? false
    }

    /// Qué tamaño del ciclo toca: si lo último fue esta misma acción y la ventana no se movió desde entonces, el
    /// siguiente; si ya coincide con un paso del ciclo, el que sigue; si no, la mitad.
    static func pasoCiclo(_ accion: AccionVentana, actual: CGRect, memoria: MemoriaVentana?, marco: (Int) -> CGRect) -> Int {
        if let m = memoria, parecidos(actual, m.ultimo), m.accion == accion {
            return (m.paso + 1) % fracciones.count
        }
        for k in fracciones.indices where parecidos(actual, marco(k)) {
            return (k + 1) % fracciones.count
        }
        return 0
    }

    static func pasoLado(izquierda: Bool, actual: CGRect, en v: CGRect, memoria: MemoriaVentana?) -> Int {
        pasoCiclo(izquierda ? .izquierda : .derecha, actual: actual, memoria: memoria) { lado(izquierda: izquierda, paso: $0, en: v) }
    }

    static func casiMaximizada(_ v: CGRect) -> CGRect {
        v.insetBy(dx: margenCasi, dy: margenCasi)
    }

    /// Mismo tamaño (recortado si no cabe), centrada en el área visible.
    static func centrada(_ m: CGRect, en v: CGRect) -> CGRect {
        let w = min(m.width, v.width), h = min(m.height, v.height)
        return redondear(CGRect(x: v.midX - w / 2, y: v.midY - h / 2, width: w, height: h))
    }

    /// La misma posición y tamaño relativos en otra pantalla (una mitad izquierda sigue siendo mitad izquierda). Entre
    /// una pantalla horizontal y una vertical se giran los ejes: la mitad izquierda pasa a ser la de arriba y la derecha,
    /// la de abajo (y al revés), para que nada quede como una tira angosta.
    static func trasladada(_ m: CGRect, de o: CGRect, a d: CGRect) -> CGRect {
        var rel = CGRect(x: (m.minX - o.minX) / o.width, y: (m.minY - o.minY) / o.height,
                         width: m.width / o.width, height: m.height / o.height)
        if vertical(o) != vertical(d) { rel = CGRect(x: rel.minY, y: rel.minX, width: rel.height, height: rel.width) }
        let r = CGRect(x: d.minX + rel.minX * d.width, y: d.minY + rel.minY * d.height,
                       width: rel.width * d.width, height: rel.height * d.height)
        return redondear(ajustada(r, a: d))
    }

    /// La pantalla pegada a ese lado (la más cercana hacia la izquierda o la derecha), si hay.
    static func vecina(_ i: Int, izquierda: Bool, en pantallas: [PantallaAX]) -> Int? {
        let m = pantallas[i].marco
        let candidatas = pantallas.indices.filter { j in
            j != i && (izquierda ? pantallas[j].marco.midX < m.minX : pantallas[j].marco.midX > m.maxX)
        }
        func hueco(_ j: Int) -> CGFloat {
            izquierda ? m.minX - pantallas[j].marco.maxX : pantallas[j].marco.minX - m.maxX
        }
        return candidatas.min { hueco($0) < hueco($1) }
    }

    /// Recorta el tamaño a lo que cabe y mete la ventana dentro del área visible.
    static func ajustada(_ m: CGRect, a v: CGRect) -> CGRect {
        let w = min(m.width, v.width), h = min(m.height, v.height)
        return CGRect(x: min(max(m.minX, v.minX), v.maxX - w), y: min(max(m.minY, v.minY), v.maxY - h), width: w, height: h)
    }

    /// La pantalla que sigue de izquierda a derecha (y de arriba abajo si están apiladas), en ciclo.
    static func siguiente(_ i: Int, en pantallas: [PantallaAX]) -> Int {
        let orden = pantallas.indices.sorted { a, b in
            let pa = pantallas[a].marco, pb = pantallas[b].marco
            return pa.minX != pb.minX ? pa.minX < pb.minX : pa.minY < pb.minY
        }
        guard let pos = orden.firstIndex(of: i) else { return i }
        return orden[(pos + 1) % orden.count]
    }

    static func parecidos(_ a: CGRect, _ b: CGRect) -> Bool {
        abs(a.minX - b.minX) <= tolerancia && abs(a.minY - b.minY) <= tolerancia
            && abs(a.width - b.width) <= tolerancia && abs(a.height - b.height) <= tolerancia
    }

    static func redondear(_ r: CGRect) -> CGRect {
        CGRect(x: r.minX.rounded(), y: r.minY.rounded(), width: r.width.rounded(), height: r.height.rounded())
    }

    typealias Plan = (marco: CGRect, paso: Int, registro: AccionVentana)

    /// El marco nuevo para la acción y lo que se registra en memoria, o nil si no hay nada que hacer (sin previo que
    /// restaurar, una sola pantalla, ninguna pantalla hacia ese lado).
    static func plan(_ accion: AccionVentana, actual: CGRect, pantallas: [PantallaAX], memoria: MemoriaVentana?) -> Plan? {
        guard let i = indice(de: actual, en: pantallas) else { return nil }
        let v = pantallas[i].visible
        // ¿La ventana sigue como la dejó Dictado? Si la moviste a mano, su marco actual pasa a ser el "previo".
        let acomodada = memoria.map { parecidos(actual, $0.ultimo) } ?? false
        if vertical(v) { return planVertical(accion, actual: actual, i: i, pantallas: pantallas, memoria: acomodada ? memoria : nil) }
        switch accion {
        case .izquierda, .derecha:
            let izquierda = accion == .izquierda
            let paso = pasoLado(izquierda: izquierda, actual: actual, en: v, memoria: acomodada ? memoria : nil)
            return (lado(izquierda: izquierda, paso: paso, en: v), paso, accion)
        case .casiMaximizar:
            // Volver al previo queda como "restaurar", para que el siguiente ↑ vuelva a casi maximizar.
            if let m = memoria, acomodada, m.accion == .casiMaximizar { return (m.previo, 0, .restaurar) }
            return (casiMaximizada(v), 0, accion)
        case .restaurar:
            guard let m = memoria, !parecidos(actual, m.previo) else { return nil }
            return (m.previo, 0, accion)
        case .otraPantalla:
            guard pantallas.count > 1 else { return nil }
            return (trasladada(actual, de: v, a: pantallas[siguiente(i, en: pantallas)].visible), 0, accion)
        case .centrar:
            return (centrada(actual, en: v), 0, accion)
        case .disponer:
            return nil
        }
    }

    /// Las mismas teclas en una pantalla vertical (ver el encabezado). `memoria` solo llega si la ventana sigue como
    /// la dejó Dictado.
    private static func planVertical(_ accion: AccionVentana, actual: CGRect, i: Int, pantallas: [PantallaAX],
                                     memoria: MemoriaVentana?) -> Plan? {
        let v = pantallas[i].visible
        switch accion {
        case .casiMaximizar, .restaurar:   // ↑ arriba, ↓ abajo
            let arriba = accion == .casiMaximizar
            let paso = pasoCiclo(accion, actual: actual, memoria: memoria) { franja(arriba: arriba, paso: $0, en: v) }
            return (franja(arriba: arriba, paso: paso, en: v), paso, accion)
        case .izquierda, .derecha:
            let izquierda = accion == .izquierda
            guard let j = vecina(i, izquierda: izquierda, en: pantallas) else { return nil }
            let d = pantallas[j].visible
            if vertical(d) { return (trasladada(actual, de: v, a: d), 0, .otraPantalla) }
            // Queda en la mitad de la horizontal que da hacia la vertical; se registra como ese lado, para que
            // allí la tecla contraria la lleve a la otra mitad y la misma siga el ciclo.
            return (lado(izquierda: !izquierda, paso: 0, en: d), 0, izquierda ? .derecha : .izquierda)
        case .centrar:   // ↩ casi maximiza; otra vez, vuelve al previo
            if let m = memoria, m.accion == .centrar { return (m.previo, 0, .restaurar) }
            return (casiMaximizada(v), 0, .centrar)
        case .otraPantalla:
            guard pantallas.count > 1 else { return nil }
            return (trasladada(actual, de: v, a: pantallas[siguiente(i, en: pantallas)].visible), 0, accion)
        case .disponer:
            return nil
        }
    }

    /// Lo que queda en memoria tras aplicar la acción (`accion` es lo que el plan pidió registrar). El previo solo se
    /// renueva si la ventana estaba "libre" (nunca la tocó Dictado o la moviste a mano): así volver al previo lleva al
    /// tamaño de antes de toda la serie de atajos.
    static func recordar(_ memoria: MemoriaVentana?, accion: AccionVentana, antes: CGRect, leido: CGRect, paso: Int) -> MemoriaVentana {
        let acomodada = memoria.map { parecidos(antes, $0.ultimo) } ?? false
        let previo = acomodada ? memoria!.previo : antes
        return MemoriaVentana(previo: previo, ultimo: leido, accion: accion, paso: paso)
    }
}

// MARK: - Accesibilidad

/// Lectura y escritura de ventanas por Accesibilidad (la usan Ventanas y el Buscador).
enum AX {
    static func valor(_ e: AXUIElement, _ atributo: String) -> CFTypeRef? {
        var v: CFTypeRef?
        return AXUIElementCopyAttributeValue(e, atributo as CFString, &v) == .success ? v : nil
    }

    static func elemento(_ e: AXUIElement, _ atributo: String) -> AXUIElement? {
        guard let v = valor(e, atributo), CFGetTypeID(v) == AXUIElementGetTypeID() else { return nil }
        return (v as! AXUIElement)
    }

    static func bool(_ e: AXUIElement, _ atributo: String) -> Bool? {
        valor(e, atributo) as? Bool
    }

    static func marco(_ e: AXUIElement) -> CGRect? {
        guard let p = valor(e, kAXPositionAttribute), let t = valor(e, kAXSizeAttribute),
              CFGetTypeID(p) == AXValueGetTypeID(), CFGetTypeID(t) == AXValueGetTypeID() else { return nil }
        var origen = CGPoint.zero, tamano = CGSize.zero
        guard AXValueGetValue(p as! AXValue, .cgPoint, &origen), AXValueGetValue(t as! AXValue, .cgSize, &tamano) else { return nil }
        return CGRect(origin: origen, size: tamano)
    }

    static func modificable(_ e: AXUIElement, _ atributo: String) -> Bool {
        var si: DarwinBoolean = false
        return AXUIElementIsAttributeSettable(e, atributo as CFString, &si) == .success && si.boolValue
    }

    /// Tamaño → posición → tamaño: el primer tamaño evita que la app lo recorte al llegar a una pantalla más
    /// chica; el último corrige lo que la app ajustó al moverse. En Chromium/Electron, `AXEnhancedUserInterface`
    /// prendido hace que cada cambio sea lento y animado: se apaga mientras tanto y se deja como estaba.
    static func mover(_ ventana: AXUIElement, a marco: CGRect, app: AXUIElement) {
        let mejorada = bool(app, "AXEnhancedUserInterface") == true
        if mejorada { AXUIElementSetAttributeValue(app, "AXEnhancedUserInterface" as CFString, kCFBooleanFalse) }
        defer { if mejorada { AXUIElementSetAttributeValue(app, "AXEnhancedUserInterface" as CFString, kCFBooleanTrue) } }
        var origen = marco.origin, tamano = marco.size
        guard let posicion = AXValueCreate(.cgPoint, &origen), let medida = AXValueCreate(.cgSize, &tamano) else { return }
        let redimensionable = modificable(ventana, kAXSizeAttribute)
        if redimensionable { AXUIElementSetAttributeValue(ventana, kAXSizeAttribute as CFString, medida) }
        AXUIElementSetAttributeValue(ventana, kAXPositionAttribute as CFString, posicion)
        if redimensionable { AXUIElementSetAttributeValue(ventana, kAXSizeAttribute as CFString, medida) }
    }
}
