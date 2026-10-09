import AppKit
import SwiftUI

/// Capa de AppKit sobre cada fila: clics con modificadores (⌘/⇧), doble clic y arrastrar uno o varios
/// elementos a otra app. SwiftUI no permite arrastrar varios elementos a la vez; AppKit sí.
struct ZonaInteractiva: NSViewRepresentable {
    let alClic: (NSEvent.ModifierFlags, Int) -> Void
    let alArrastrar: () -> (objetos: [NSPasteboardWriting], imagen: NSImage?)

    func makeNSView(context: Context) -> VistaArrastre {
        let vista = VistaArrastre()
        vista.alClic = alClic
        vista.alArrastrar = alArrastrar
        return vista
    }

    func updateNSView(_ vista: VistaArrastre, context: Context) {
        vista.alClic = alClic
        vista.alArrastrar = alArrastrar
    }
}

final class VistaArrastre: NSView, NSDraggingSource {
    var alClic: ((NSEvent.ModifierFlags, Int) -> Void)?
    var alArrastrar: (() -> (objetos: [NSPasteboardWriting], imagen: NSImage?))?
    private var inicio: NSPoint?

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with evento: NSEvent) {
        inicio = evento.locationInWindow
        alClic?(evento.modifierFlags, evento.clickCount)
    }

    override func mouseDragged(with evento: NSEvent) {
        guard let inicio, hypot(evento.locationInWindow.x - inicio.x, evento.locationInWindow.y - inicio.y) > 4,
              let (objetos, imagen) = alArrastrar?(), !objetos.isEmpty else { return }
        self.inicio = nil
        let punto = convert(evento.locationInWindow, from: nil)
        let icono = imagen ?? NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: nil) ?? NSImage()
        let items = objetos.enumerated().map { i, objeto -> NSDraggingItem in
            let item = NSDraggingItem(pasteboardWriter: objeto)
            let lado: CGFloat = 52
            // varios elementos se ven apilados
            let desfase = CGFloat(min(i, 4)) * 5
            item.setDraggingFrame(NSRect(x: punto.x - lado / 2 + desfase, y: punto.y - lado / 2 - desfase, width: lado, height: lado),
                                  contents: icono)
            return item
        }
        let sesion = beginDraggingSession(with: items, event: evento, source: self)
        sesion.animatesToStartingPositionsOnCancelOrFail = true
        sesion.draggingFormation = .stack
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        context == .outsideApplication ? .copy : []
    }
}
