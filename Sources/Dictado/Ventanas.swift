import AppKit
import ApplicationServices
import Carbon.HIToolbox

// Ventanas por teclado: solo lo que macOS 26 no trae de serie (su mosaico ya hace mitades y cuartos con fn⌃).
//   Hyper + ←/→   mitad → tercio → dos tercios del lado, en ciclo al repetir
//   Hyper + ↑     casi maximizar (margen pequeño); otra vez, vuelve al tamaño previo
//   Hyper + ↓     restaurar el tamaño previo
//   Hyper + N     a la siguiente pantalla, con las mismas proporciones
//   Hyper + ↩     centrar
// La geometría vive en `GeometriaVentanas` (funciones puras, se prueban con --probar-ventanas); aquí solo se lee
// y se escribe la ventana por Accesibilidad.

enum AccionVentana: Equatable {
    case izquierda, derecha, casiMaximizar, restaurar, otraPantalla, centrar
}

/// Interruptor del módulo: registra los atajos según `Funcion.ventanas` y mueve la ventana enfocada.
@MainActor
final class VentanasTeclado {
    /// Lo que se recuerda de una ventana: su marco antes de que Dictado la tocara y lo último que le hizo.
    private struct Recuerdo {
        let ventana: AXUIElement
        var memoria: MemoriaVentana
    }

    private let contexto: ContextoModulos
    private var recuerdos: [Recuerdo] = []
    private var registrados = false
    /// Ids de Carbon reservados para este módulo: 30-39.
    private static let atajos: [(id: UInt32, tecla: Int, accion: AccionVentana)] = [
        (30, kVK_LeftArrow, .izquierda), (31, kVK_RightArrow, .derecha), (32, kVK_UpArrow, .casiMaximizar),
        (33, kVK_DownArrow, .restaurar), (34, kVK_ANSI_N, .otraPantalla), (35, kVK_Return, .centrar),
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
                                         alPresionar: { [weak self] in self?.ejecutar(a.accion) })
            }
            if !ocupados.isEmpty {
                contexto.avisar("Algunos atajos de ventanas los usa otra app", "keyboard.badge.exclamationmark", nil)
            }
        } else {
            guard registrados else { return }
            registrados = false
            Self.atajos.forEach { Atajos.shared.quitar(id: $0.id) }
            recuerdos = []
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
        let indice = recuerdos.firstIndex { CFEqual($0.ventana, ventana) }
        let memoria = indice.map { recuerdos[$0].memoria }
        let pantallas = GeometriaVentanas.pantallas(NSScreen.screens.map { ($0.frame, $0.visibleFrame) })
        guard let plan = GeometriaVentanas.plan(accion, actual: actual, pantallas: pantallas, memoria: memoria) else {
            // Con memoria y sin plan, la ventana ya está en su tamaño previo: no hace falta avisar.
            if accion == .restaurar, memoria == nil {
                contexto.avisar("No hay un tamaño previo que restaurar", "arrow.uturn.backward", nil)
            }
            return
        }
        AX.mover(ventana, a: plan.marco, app: appAX)
        let leido = AX.marco(ventana) ?? plan.marco  // la app puede ajustar el tamaño (mínimos, celdas de texto)
        let nueva = GeometriaVentanas.recordar(memoria, accion: accion, antes: actual, leido: leido, paso: plan.paso)
        if let indice { recuerdos.remove(at: indice) }
        recuerdos.insert(Recuerdo(ventana: ventana, memoria: nueva), at: 0)
        if recuerdos.count > 40 { recuerdos.removeLast() }  // las ventanas cerradas se olvidan solas
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

    /// Qué tamaño toca: si lo último fue este mismo lado y la ventana no se movió desde entonces, el siguiente
    /// del ciclo; si ya coincide con un paso del ciclo, el que sigue; si no, la mitad.
    static func pasoLado(izquierda: Bool, actual: CGRect, en v: CGRect, memoria: MemoriaVentana?) -> Int {
        if let m = memoria, parecidos(actual, m.ultimo), m.accion == (izquierda ? .izquierda : .derecha) {
            return (m.paso + 1) % fracciones.count
        }
        for k in fracciones.indices where parecidos(actual, lado(izquierda: izquierda, paso: k, en: v)) {
            return (k + 1) % fracciones.count
        }
        return 0
    }

    static func casiMaximizada(_ v: CGRect) -> CGRect {
        v.insetBy(dx: margenCasi, dy: margenCasi)
    }

    /// Mismo tamaño (recortado si no cabe), centrada en el área visible.
    static func centrada(_ m: CGRect, en v: CGRect) -> CGRect {
        let w = min(m.width, v.width), h = min(m.height, v.height)
        return redondear(CGRect(x: v.midX - w / 2, y: v.midY - h / 2, width: w, height: h))
    }

    /// La misma posición y tamaño relativos en otra pantalla (una mitad izquierda sigue siendo mitad izquierda).
    static func trasladada(_ m: CGRect, de o: CGRect, a d: CGRect) -> CGRect {
        let r = CGRect(x: d.minX + (m.minX - o.minX) / o.width * d.width,
                       y: d.minY + (m.minY - o.minY) / o.height * d.height,
                       width: m.width / o.width * d.width,
                       height: m.height / o.height * d.height)
        return redondear(ajustada(r, a: d))
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

    /// El marco nuevo para la acción, o nil si no hay nada que hacer (sin previo que restaurar, una sola pantalla).
    static func plan(_ accion: AccionVentana, actual: CGRect, pantallas: [PantallaAX],
                     memoria: MemoriaVentana?) -> (marco: CGRect, paso: Int)? {
        guard let i = indice(de: actual, en: pantallas) else { return nil }
        let v = pantallas[i].visible
        // ¿La ventana sigue como la dejó Dictado? Si la moviste a mano, su marco actual pasa a ser el "previo".
        let acomodada = memoria.map { parecidos(actual, $0.ultimo) } ?? false
        switch accion {
        case .izquierda, .derecha:
            let izquierda = accion == .izquierda
            let paso = pasoLado(izquierda: izquierda, actual: actual, en: v, memoria: acomodada ? memoria : nil)
            return (lado(izquierda: izquierda, paso: paso, en: v), paso)
        case .casiMaximizar:
            if let m = memoria, acomodada, m.accion == .casiMaximizar { return (m.previo, 0) }
            return (casiMaximizada(v), 0)
        case .restaurar:
            guard let m = memoria, !parecidos(actual, m.previo) else { return nil }
            return (m.previo, 0)
        case .otraPantalla:
            guard pantallas.count > 1 else { return nil }
            return (trasladada(actual, de: v, a: pantallas[siguiente(i, en: pantallas)].visible), 0)
        case .centrar:
            return (centrada(actual, en: v), 0)
        }
    }

    /// Lo que queda en memoria tras aplicar la acción. El previo solo se renueva si la ventana estaba "libre"
    /// (nunca la tocó Dictado o la moviste a mano): así ↓ vuelve al tamaño de antes de toda la serie de atajos.
    static func recordar(_ memoria: MemoriaVentana?, accion: AccionVentana, antes: CGRect, leido: CGRect, paso: Int) -> MemoriaVentana {
        let acomodada = memoria.map { parecidos(antes, $0.ultimo) } ?? false
        let previo = acomodada ? memoria!.previo : antes
        // Volver al previo con ↑ deja la acción como "restaurar" para que el siguiente ↑ vuelva a casi maximizar.
        let volvio = accion == .casiMaximizar && memoria?.accion == .casiMaximizar && acomodada
        return MemoriaVentana(previo: previo, ultimo: leido, accion: volvio ? .restaurar : accion, paso: paso)
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
