import AppKit
import Carbon.HIToolbox
import SwiftUI

// Pruebas y renders de la tecla hyper, las ventanas por teclado y el buscador. Ninguna publica eventos de
// teclado, mueve ventanas reales ni cambia el mapeo del sistema (salvo --quitar-hyper, que es para recuperar
// Bloq Mayús a mano).
//   Dictado --probar-hyper           máquina de estados con eventos construidos y mezcla del mapeo
//   Dictado --probar-ventanas        geometría sobre pantallas de ejemplo, imprimiendo los marcos
//   Dictado --probar-buscador        filtro y orden; si hay Accesibilidad, cuánto tarda leer las ventanas
//   Dictado --vista-buscador s.png   render del panel con datos de ejemplo
//   Dictado --estado-hyper           mapeo actual, Entrada Segura y permiso (solo lectura)
//   Dictado --quitar-hyper           quita Bloq Mayús → F18 si quedó puesto tras un cierre brusco

/// Banderas de estos módulos; nil si la bandera no es de aquí.
@MainActor
func cliTeclado(_ args: [String]) -> Int32? {
    guard args.count > 1 else { return nil }
    switch args[1] {
    case "--probar-hyper": return probarHyper() ? 0 : 1
    case "--probar-ventanas": return probarVentanas() ? 0 : 1
    case "--probar-buscador": return probarBuscador() ? 0 : 1
    case "--vista-buscador" where args.count > 2: return hojaBuscador(URL(fileURLWithPath: args[2])) ? 0 : 1
    case "--estado-hyper":
        estadoHyper()
        return 0
    case "--quitar-hyper":
        MapeoHyper.cola.sync { MapeoHyper.quitar(forzar: true) }
        print(MapeoHyper.leer().contains(MapeoHyper.propio) ? "no se pudo quitar el mapeo" : "Bloq Mayús vuelve a ser Bloq Mayús")
        return 0
    default: return nil
    }
}

/// Contador de pruebas con la misma salida que --probar-portapapeles.
private final class Revision {
    var fallas = 0
    func revisar(_ nombre: String, _ condicion: Bool) {
        print(condicion ? "  ✓" : "  ✗", nombre)
        if !condicion { fallas += 1 }
    }
    func final() -> Bool {
        print(fallas == 0 ? "todo bien" : "\(fallas) fallas")
        return fallas == 0
    }
}

// MARK: - Hyper

@MainActor
func probarHyper() -> Bool {
    let r = Revision()
    var m = MaquinaHyper()
    let hyper = MaquinaHyper.modificadores
    let f18 = MaquinaHyper.teclaF18
    let v: Int64 = Int64(kVK_ANSI_V), a: Int64 = Int64(kVK_ANSI_A)
    func ev(_ tipo: CGEventType, _ tecla: Int64, _ t: TimeInterval, repite: Bool = false, abajo: Bool = true,
            flags: CGEventFlags = []) -> MaquinaHyper.Resultado {
        m.procesar(tipo: tipo, tecla: tecla, flags: flags, repeticion: repite, momento: t, f18Abajo: { abajo })
    }

    print("Máquina de estados")
    r.revisar("F18 abajo se consume (activa hyper)", ev(.keyDown, f18, 0) == .consumir && m.activa)
    r.revisar("F18 arriba sola alterna las mayúsculas", ev(.keyUp, f18, 0.15) == .consumirYAlternarMayusculas)
    _ = ev(.keyDown, f18, 1)
    r.revisar("V con hyper lleva ⌃⌥⌘⇧", ev(.keyDown, v, 1.1) == .pasarCon(hyper))
    r.revisar("soltar V también lleva ⌃⌥⌘⇧", ev(.keyUp, v, 1.2) == .pasarCon(hyper))
    r.revisar("soltar hyper tras usarla no alterna las mayúsculas", ev(.keyUp, f18, 1.3) == .consumir)
    r.revisar("después, V va limpia", ev(.keyDown, v, 1.4) == .pasar && ev(.keyUp, v, 1.45) == .pasar)
    _ = ev(.keyDown, f18, 2)
    _ = ev(.keyDown, f18, 2.5, repite: true)
    r.revisar("mantenida 1,5 s sin tocar nada no alterna las mayúsculas", ev(.keyUp, f18, 3.5) == .consumir)
    _ = ev(.keyDown, f18, 4)
    r.revisar("la repetición automática de F18 se consume", ev(.keyDown, f18, 4.3, repite: true) == .consumir)
    r.revisar("y no cuenta como otra tecla (sí alterna las mayúsculas)", ev(.keyUp, f18, 4.4) == .consumirYAlternarMayusculas)
    _ = ev(.keyDown, f18, 5)
    r.revisar("con ⇧ ya presionado, sola también alterna las mayúsculas",
              ev(.keyUp, f18, 5.1, flags: [.maskShift, .maskSecondaryFn]) == .consumirYAlternarMayusculas)
    _ = ev(.keyDown, f18, 6)
    _ = ev(.keyDown, a, 6.1)
    _ = ev(.keyUp, f18, 6.2)
    r.revisar("la tecla que bajó con hyper sube con hyper aunque F18 ya subió", ev(.keyUp, a, 6.3) == .pasarCon(hyper))
    _ = ev(.keyDown, f18, 7, abajo: true)
    r.revisar("Hyper+tecla soltada muy rápido (estado HID adelantado) sigue con hyper",
              ev(.keyDown, v, 7.2, abajo: false) == .pasarCon(hyper))
    _ = ev(.keyUp, v, 7.25)
    r.revisar("soltar de F18 perdido (Entrada Segura): pasado medio segundo, la siguiente tecla va limpia",
              ev(.keyDown, v, 7.8, abajo: false) == .pasar)
    _ = ev(.keyUp, v, 7.85)
    _ = ev(.keyDown, f18, 8, abajo: false)
    r.revisar("si el estado HID no es fiable, hyper sigue funcionando", ev(.keyDown, v, 8.1, abajo: false) == .pasarCon(hyper))
    _ = ev(.keyUp, v, 8.2)
    _ = ev(.keyUp, f18, 8.3)
    _ = ev(.keyDown, f18, 9)
    m.reiniciar()
    r.revisar("tras reiniciar (tap apagado por demora), nada queda pegado", ev(.keyDown, v, 9.1) == .pasar)
    _ = ev(.keyUp, v, 9.2)
    _ = ev(.keyDown, f18, 10)
    _ = ev(.leftMouseDown, 0, 10.1)
    r.revisar("hyper + clic no alterna las mayúsculas", ev(.keyUp, f18, 10.2) == .consumir)
    _ = ev(.keyDown, f18, 11)
    _ = ev(.flagsChanged, Int64(kVK_Shift), 11.1)
    r.revisar("hyper + ⇧ no alterna las mayúsculas", ev(.keyUp, f18, 11.2) == .consumir)
    r.revisar("sin hyper, las teclas pasan intactas", ev(.keyDown, a, 12) == .pasar && ev(.keyUp, a, 12.1) == .pasar)
    r.revisar("un F18 arriba suelto (sin abajo) se consume sin Esc", ev(.keyUp, f18, 13) == .consumir)

    print("Eventos construidos (no se publican)")
    var maquina = MaquinaHyper()
    func evento(_ tecla: Int, _ abajo: Bool, repite: Bool = false) -> CGEvent? {
        let e = CGEvent(keyboardEventSource: CGEventSource(stateID: .privateState), virtualKey: CGKeyCode(tecla), keyDown: abajo)
        e?.flags = []
        if repite { e?.setIntegerValueField(.keyboardEventAutorepeat, value: 1) }
        return e
    }
    if let f18Abajo = evento(kVK_F18, true), let vAbajo = evento(kVK_ANSI_V, true), let f18Arriba = evento(kVK_F18, false),
       let solo = evento(kVK_F18, true), let soloArriba = evento(kVK_F18, false) {
        let x1 = TapHyper.transformar(f18Abajo, tipo: .keyDown, maquina: &maquina, momento: 0, f18Abajo: { true })
        let x2 = TapHyper.transformar(vAbajo, tipo: .keyDown, maquina: &maquina, momento: 0.1, f18Abajo: { true })
        r.revisar("F18 real abajo: no sigue", !x1.sigue && !x1.mayusculas)
        r.revisar("V real: sigue con ⌃⌥⌘⇧ en sus flags", x2.sigue && vAbajo.flags.contains(hyper))
        let x3 = TapHyper.transformar(f18Arriba, tipo: .keyUp, maquina: &maquina, momento: 0.2, f18Abajo: { false })
        r.revisar("F18 real arriba tras V: no sigue y no alterna mayúsculas", !x3.sigue && !x3.mayusculas)
        _ = TapHyper.transformar(solo, tipo: .keyDown, maquina: &maquina, momento: 1, f18Abajo: { true })
        let x4 = TapHyper.transformar(soloArriba, tipo: .keyUp, maquina: &maquina, momento: 1.1, f18Abajo: { false })
        r.revisar("F18 real sola: pide alternar las mayúsculas", !x4.sigue && x4.mayusculas)
    } else {
        r.revisar("construir eventos de teclado", false)
    }

    print("Mezcla del mapeo (no se escribe en el sistema)")
    typealias Par = MapeoHyper.Par
    let propio = MapeoHyper.propio
    let otro = Par(origen: 0x7_0000_0004, destino: 0x7_0000_0005)          // A → B
    let bloqAControl = Par(origen: MapeoHyper.bloqMayus, destino: 0x7_0000_00E0)  // Bloq Mayús → Control
    let vacio = MapeoHyper.conHyper([], guardado: nil, yaAplicado: false)
    r.revisar("sin mapeos: solo Bloq Mayús → F18", vacio.mapeo == [propio] && vacio.previo == nil)
    let conOtro = MapeoHyper.conHyper([otro], guardado: nil, yaAplicado: false)
    r.revisar("respeta tus otros mapeos", conOtro.mapeo == [otro, propio])
    r.revisar("al quitar, quedan tus mapeos", MapeoHyper.sinHyper(conOtro.mapeo, previo: conOtro.previo) == [otro])
    let conBloq = MapeoHyper.conHyper([bloqAControl, otro], guardado: nil, yaAplicado: false)
    r.revisar("si Bloq Mayús ya tenía un mapeo tuyo, se guarda", conBloq.mapeo == [otro, propio] && conBloq.previo == bloqAControl)
    r.revisar("y vuelve al quitar hyper", MapeoHyper.sinHyper(conBloq.mapeo, previo: conBloq.previo) == [otro, bloqAControl])
    let otraVez = MapeoHyper.conHyper(conBloq.mapeo, guardado: bloqAControl, yaAplicado: true)
    r.revisar("reaplicar (despertar, teclado nuevo) no duplica ni pierde lo guardado",
              otraVez.mapeo == [otro, propio] && otraVez.previo == bloqAControl)
    let json = MapeoHyper.json([propio])
    print("    hidutil property --set '\(json)'")
    r.revisar("JSON para hidutil", json == "{\"UserKeyMapping\":[{\"HIDKeyboardModifierMappingSrc\":30064771129,\"HIDKeyboardModifierMappingDst\":30064771181}]}")
    r.revisar("JSON vacío limpia", MapeoHyper.json([]) == "{\"UserKeyMapping\":[]}")
    let leido = MapeoHyper.pares([["HIDKeyboardModifierMappingSrc": NSNumber(value: otro.origen),
                                   "HIDKeyboardModifierMappingDst": NSNumber(value: otro.destino)]] as NSArray)
    r.revisar("lee el formato de IOKit", leido == [otro])
    return r.final()
}

/// Solo lectura: qué mapeo hay, si lo puso Dictado, si hay Entrada Segura y si este proceso tiene Accesibilidad.
@MainActor
func estadoHyper() {
    let mapeo = MapeoHyper.leer()
    let texto = mapeo.map { String(format: "0x%llX → 0x%llX", $0.origen, $0.destino) }
    print("mapeo actual:", texto.isEmpty ? "(ninguno)" : texto.joined(separator: ", "))
    print("Bloq Mayús → F18:", mapeo.contains(MapeoHyper.propio) ? "sí" : "no", "· puesto por Dictado:", MapeoHyper.aplicado ? "sí" : "no")
    print("Entrada Segura activa (hyper no ve el teclado):", IsSecureEventInputEnabled() ? "sí" : "no")
    // Quién la tiene: si es loginwindow, quedó prendida tras desbloquear (bloquea y desbloquea la pantalla).
    if IsSecureEventInputEnabled(), let sesion = CGSessionCopyCurrentDictionary() as? [String: Any],
       let pid = sesion["kCGSSessionSecureInputPID"] as? Int {
        print("  la tiene:", NSRunningApplication(processIdentifier: pid_t(pid))?.localizedName ?? "proceso \(pid)")
    }
    print("Accesibilidad de este proceso:", AXIsProcessTrusted() ? "sí" : "no")
}

// MARK: - Ventanas

@MainActor
func probarVentanas() -> Bool {
    let r = Revision()
    typealias G = GeometriaVentanas
    func t(_ m: CGRect?) -> String {
        guard let m else { return "(nada)" }
        return String(format: "x %5.0f  y %5.0f  %5.0f × %-5.0f", m.minX, m.minY, m.width, m.height)
    }
    // Pantallas de ejemplo como las entrega NSScreen (origen abajo a la izquierda de la principal):
    // un portátil de 1512 × 982 con notch (barra de menús de 37 pt, Dock oculto) y, a su derecha y alineado
    // arriba, un monitor de 2560 × 1440 con barra de menús de 25 pt y Dock abajo de 70 pt.
    let cocoa: [(marco: CGRect, visible: CGRect)] = [
        (CGRect(x: 0, y: 0, width: 1512, height: 982), CGRect(x: 0, y: 0, width: 1512, height: 945)),
        (CGRect(x: 1512, y: -458, width: 2560, height: 1440), CGRect(x: 1512, y: -388, width: 2560, height: 1345)),
    ]
    let pantallas = G.pantallas(cocoa)
    print("Pantallas en coordenadas de Accesibilidad (origen arriba a la izquierda)")
    for (i, p) in pantallas.enumerated() { print("  \(i == 0 ? "portátil" : "monitor ")  marco \(t(p.marco))   visible \(t(p.visible))") }
    r.revisar("portátil: visible empieza bajo la barra de menús", pantallas[0].visible == CGRect(x: 0, y: 37, width: 1512, height: 945))
    r.revisar("monitor: marco alineado arriba", pantallas[1].marco == CGRect(x: 1512, y: 0, width: 2560, height: 1440))
    r.revisar("monitor: visible sin barra ni Dock", pantallas[1].visible == CGRect(x: 1512, y: 25, width: 2560, height: 1345))

    /// Una ventana simulada: aplica el plan como lo haría la app (con su tamaño mínimo) y recuerda como el módulo.
    struct Simulada {
        var marco: CGRect
        var memoria: MemoriaVentana?
        var minimo = CGSize.zero
    }
    let nombres: [AccionVentana: String] = [.izquierda: "Hyper+←", .derecha: "Hyper+→", .casiMaximizar: "Hyper+↑",
                                            .restaurar: "Hyper+↓", .otraPantalla: "Hyper+N", .centrar: "Hyper+↩", .disponer: "Hyper+D"]
    @discardableResult
    func aplicar(_ accion: AccionVentana, _ w: inout Simulada, en ps: [PantallaAX] = pantallas) -> CGRect? {
        guard let plan = G.plan(accion, actual: w.marco, pantallas: ps, memoria: w.memoria) else {
            print("    \(nombres[accion]!)  →  (no hace nada)")
            return nil
        }
        var leido = plan.marco
        leido.size.width = max(leido.width, w.minimo.width)
        leido.size.height = max(leido.height, w.minimo.height)
        w.memoria = G.recordar(w.memoria, accion: plan.registro, antes: w.marco, leido: leido, paso: plan.paso)
        w.marco = leido
        print("    \(nombres[accion]!)  →  \(t(leido))")
        return leido
    }

    print("Hyper+← en ciclo y Hyper+↓ (portátil, ventana en x 200 y 150, 900 × 600)")
    let inicial = CGRect(x: 200, y: 150, width: 900, height: 600)
    var w = Simulada(marco: inicial)
    r.revisar("1.ª vez: mitad izquierda", aplicar(.izquierda, &w) == CGRect(x: 0, y: 37, width: 756, height: 945))
    r.revisar("2.ª vez: tercio", aplicar(.izquierda, &w) == CGRect(x: 0, y: 37, width: 504, height: 945))
    r.revisar("3.ª vez: dos tercios", aplicar(.izquierda, &w) == CGRect(x: 0, y: 37, width: 1008, height: 945))
    r.revisar("4.ª vez: vuelve a la mitad", aplicar(.izquierda, &w) == CGRect(x: 0, y: 37, width: 756, height: 945))
    r.revisar("Hyper+↓ restaura el tamaño de antes de la serie", aplicar(.restaurar, &w) == inicial)
    r.revisar("Hyper+↓ otra vez no hace nada", aplicar(.restaurar, &w) == nil)

    print("Hyper+→ en el monitor (ventana en x 2000 y 300, 1200 × 800)")
    w = Simulada(marco: CGRect(x: 2000, y: 300, width: 1200, height: 800))
    r.revisar("mitad derecha", aplicar(.derecha, &w) == CGRect(x: 2792, y: 25, width: 1280, height: 1345))
    r.revisar("tercio derecho", aplicar(.derecha, &w) == CGRect(x: 3219, y: 25, width: 853, height: 1345))
    r.revisar("dos tercios derechos", aplicar(.derecha, &w) == CGRect(x: 2365, y: 25, width: 1707, height: 1345))
    r.revisar("cambiar de lado empieza por la mitad", aplicar(.izquierda, &w) == CGRect(x: 1512, y: 25, width: 1280, height: 1345))

    print("Hyper+↑ alterna entre casi maximizar y el tamaño previo")
    let mediana = CGRect(x: 300, y: 200, width: 800, height: 500)
    w = Simulada(marco: mediana)
    r.revisar("casi maximizada con margen de 12 pt", aplicar(.casiMaximizar, &w) == CGRect(x: 12, y: 49, width: 1488, height: 921))
    r.revisar("otra vez: vuelve al tamaño previo", aplicar(.casiMaximizar, &w) == mediana)
    r.revisar("y otra: casi maximizada de nuevo", aplicar(.casiMaximizar, &w) == CGRect(x: 12, y: 49, width: 1488, height: 921))
    r.revisar("Hyper+↓ también vuelve al previo", aplicar(.restaurar, &w) == mediana)

    print("Hyper+N lleva a la otra pantalla con las mismas proporciones")
    w = Simulada(marco: mediana)
    aplicar(.izquierda, &w)
    r.revisar("mitad izquierda del portátil → mitad izquierda del monitor",
              aplicar(.otraPantalla, &w) == CGRect(x: 1512, y: 25, width: 1280, height: 1345))
    r.revisar("otra vez → de vuelta al portátil", aplicar(.otraPantalla, &w) == CGRect(x: 0, y: 37, width: 756, height: 945))
    w = Simulada(marco: CGRect(x: 1600, y: 100, width: 1280, height: 720))
    let llevada = aplicar(.otraPantalla, &w)
    r.revisar("una ventana del monitor cabe en el portátil", llevada.map { pantallas[0].visible.contains($0) } ?? false)
    w = Simulada(marco: mediana)
    r.revisar("con una sola pantalla no hace nada", aplicar(.otraPantalla, &w, en: [pantallas[0]]) == nil)

    print("Hyper+↩ centra")
    w = Simulada(marco: CGRect(x: 100, y: 100, width: 800, height: 600))
    r.revisar("centrada en el área visible del portátil", aplicar(.centrar, &w) == CGRect(x: 356, y: 210, width: 800, height: 600))
    w = Simulada(marco: CGRect(x: 0, y: 0, width: 2000, height: 1200))
    r.revisar("una ventana más grande que la pantalla se recorta al centrar",
              aplicar(.centrar, &w) == CGRect(x: 0, y: 37, width: 1512, height: 945))

    print("Apps que imponen un ancho mínimo (600 pt)")
    w = Simulada(marco: inicial, minimo: CGSize(width: 600, height: 0))
    aplicar(.izquierda, &w)
    r.revisar("el tercio queda en 600 (lo ajusta la app)", aplicar(.izquierda, &w)?.width == 600)
    r.revisar("y el ciclo sigue a dos tercios", aplicar(.izquierda, &w)?.width == 1008)

    print("Si la mueves a mano entre atajos")
    w = Simulada(marco: inicial)
    aplicar(.izquierda, &w)
    let aMano = CGRect(x: 300, y: 300, width: 700, height: 500)
    w.marco = aMano
    print("    (a mano)  →  \(t(aMano))")
    r.revisar("Hyper+← empieza otra vez por la mitad", aplicar(.izquierda, &w)?.width == 756)
    r.revisar("Hyper+↓ restaura donde la dejaste a mano", aplicar(.restaurar, &w) == aMano)

    print("Pantalla de una ventana repartida entre dos")
    r.revisar("cuenta la que tiene la mayor parte", G.indice(de: CGRect(x: 1300, y: 100, width: 600, height: 400), en: pantallas) == 1)
    r.revisar("fuera de toda pantalla: la más cercana", G.indice(de: CGRect(x: -900, y: 100, width: 400, height: 300), en: pantallas) == 0)
    w = Simulada(marco: mediana)
    r.revisar("sin memoria, Hyper+↓ no hace nada", aplicar(.restaurar, &w) == nil)

    print("Pantalla vertical (1080 × 1920 a la derecha del portátil, alineada arriba, barra de 25 pt)")
    let conVertical = G.pantallas([cocoa[0], (CGRect(x: 1512, y: -938, width: 1080, height: 1920),
                                              CGRect(x: 1512, y: -938, width: 1080, height: 1895))])
    r.revisar("vertical: visible bajo la barra", conVertical[1].visible == CGRect(x: 1512, y: 25, width: 1080, height: 1895))
    let enVertical = CGRect(x: 1600, y: 300, width: 800, height: 700)
    w = Simulada(marco: enVertical)
    r.revisar("Hyper+↓: mitad de abajo, a todo el ancho", aplicar(.restaurar, &w, en: conVertical) == CGRect(x: 1512, y: 972, width: 1080, height: 948))
    r.revisar("otra vez: tercio de abajo", aplicar(.restaurar, &w, en: conVertical) == CGRect(x: 1512, y: 1288, width: 1080, height: 632))
    r.revisar("otra vez: dos tercios de abajo", aplicar(.restaurar, &w, en: conVertical) == CGRect(x: 1512, y: 657, width: 1080, height: 1263))
    r.revisar("Hyper+↑: mitad de arriba", aplicar(.casiMaximizar, &w, en: conVertical) == CGRect(x: 1512, y: 25, width: 1080, height: 948))
    r.revisar("otra vez: tercio de arriba", aplicar(.casiMaximizar, &w, en: conVertical) == CGRect(x: 1512, y: 25, width: 1080, height: 632))
    r.revisar("Hyper+↩: casi maximizada", aplicar(.centrar, &w, en: conVertical) == CGRect(x: 1524, y: 37, width: 1056, height: 1871))
    r.revisar("Hyper+↩ otra vez: el tamaño de antes de la serie", aplicar(.centrar, &w, en: conVertical) == enVertical)
    r.revisar("Hyper+→ sin pantalla a la derecha: no hace nada", aplicar(.derecha, &w, en: conVertical) == nil)
    r.revisar("Hyper+← la lleva a la mitad derecha del portátil", aplicar(.izquierda, &w, en: conVertical) == CGRect(x: 756, y: 37, width: 756, height: 945))
    r.revisar("allí, Hyper+← la pasa a la mitad izquierda", aplicar(.izquierda, &w, en: conVertical) == CGRect(x: 0, y: 37, width: 756, height: 945))
    r.revisar("Hyper+N: la mitad izquierda pasa a ser la de arriba en la vertical",
              aplicar(.otraPantalla, &w, en: conVertical) == CGRect(x: 1512, y: 25, width: 1080, height: 948))
    r.revisar("y de vuelta: la de arriba pasa a ser la mitad izquierda",
              aplicar(.otraPantalla, &w, en: conVertical) == CGRect(x: 0, y: 37, width: 756, height: 945))

    print("Hyper+D: la del frente y la anterior juntas")
    let enVerticalD = G.disposicion(paso: 0, en: conVertical[1].visible)
    print("    vertical  frente \(t(enVerticalD.frente))   otra \(t(enVerticalD.otra))")
    r.revisar("vertical: la del frente en los dos tercios de arriba", enVerticalD.frente == CGRect(x: 1512, y: 25, width: 1080, height: 1263))
    r.revisar("vertical: la otra en el tercio de abajo, sin hueco", enVerticalD.otra == CGRect(x: 1512, y: 1288, width: 1080, height: 632))
    let mitades = G.disposicion(paso: 1, en: conVertical[1].visible)
    r.revisar("vertical, otra vez: mitad y mitad", mitades.frente.height == 948 && mitades.otra.height == 947)
    let enPortatil = G.disposicion(paso: 0, en: pantallas[0].visible)
    print("    portátil  frente \(t(enPortatil.frente))   otra \(t(enPortatil.otra))")
    r.revisar("horizontal: lado a lado, dos tercios a la izquierda",
              enPortatil.frente == CGRect(x: 0, y: 37, width: 1008, height: 945) && enPortatil.otra == CGRect(x: 1008, y: 37, width: 504, height: 945))
    r.revisar("el tercer reparto deja un tercio a la del frente", G.disposicion(paso: 2, en: pantallas[0].visible).frente.width == 504)

    print("Pantallas de este Mac (solo lectura)")
    for (i, p) in G.pantallas(NSScreen.screens.map { ($0.frame, $0.visibleFrame) }).enumerated() {
        print("  \(i)  marco \(t(p.marco))   visible \(t(p.visible))")
    }
    return r.final()
}

// MARK: - Buscador

@MainActor
func ventanasDeMuestra() -> [VentanaEncontrada] {
    func icono(_ bundle: String) -> NSImage? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundle)
            .map { BuscadorVentanas.mapaDeBits(NSWorkspace.shared.icon(forFile: $0.path)) }
    }
    let datos: [(String, String, String, Bool, Bool)] = [
        ("com.apple.Safari", "Safari", "Documentación de SwiftUI — Apple Developer", false, false),
        ("com.apple.mail", "Mail", "Bandeja de entrada — 12 mensajes", false, false),
        ("com.apple.Safari", "Safari", "Informe de ventas — Hoja de cálculo", false, false),
        ("com.apple.finder", "Finder", "Descargas", false, false),
        ("com.apple.Preview", "Vista Previa", "Informe trimestral.pdf", false, false),
        ("com.apple.TextEdit", "TextEdit", "Borrador de propuesta.rtf", true, false),
        ("com.apple.iCal", "Calendario", "Calendario", false, true),
    ]
    var pids: [String: pid_t] = [:]
    return datos.enumerated().map { i, d in
        let pid = pids[d.0] ?? pid_t(1000 + pids.count)
        pids[d.0] = pid
        return VentanaEncontrada(id: "muestra-\(i)", pid: pid, app: d.1, bundle: d.0, titulo: d.2, minimizada: d.3,
                                 appOculta: d.4, elemento: nil, icono: icono(d.0))
    }
}

@MainActor
func probarBuscador() -> Bool {
    let r = Revision()
    let muestra = BuscadorVentanas.ordenar(ventanasDeMuestra())
    func titulos(_ consulta: String) -> [String] { BuscadorVentanas.filtrar(muestra, consulta).map(\.tituloVisible) }
    print("Filtro y orden")
    r.revisar("sin búsqueda: todas", titulos("").count == muestra.count)
    let primeraGuardada = muestra.firstIndex(where: \.guardada) ?? muestra.count
    r.revisar("minimizadas y ocultas al final", primeraGuardada > 0 && muestra[primeraGuardada...].allSatisfy(\.guardada))
    r.revisar("por título", titulos("informe").count == 2)
    r.revisar("sin tildes ni mayúsculas (INFÓRME)", titulos("INFÓRME") == titulos("informe"))
    r.revisar("por nombre de la app (vista)", titulos("vista") == ["Informe trimestral.pdf"])
    r.revisar("varias palabras: todas deben estar (safari informe)", titulos("safari informe") == ["Informe de ventas — Hoja de cálculo"])
    r.revisar("tildes en el título sin escribirlas (calculo)", titulos("calculo") == ["Informe de ventas — Hoja de cálculo"])
    let dos = [VentanaEncontrada(id: "1", pid: 1, app: "Notas", bundle: nil, titulo: "Escuela", minimizada: false, appOculta: false),
               VentanaEncontrada(id: "2", pid: 1, app: "Notas", bundle: nil, titulo: "Cuentas por pagar", minimizada: false, appOculta: false)]
    r.revisar("primero lo que empieza como lo escrito (cue: Cuentas antes que Escuela)",
              BuscadorVentanas.filtrar(dos, "cue").map(\.titulo) == ["Cuentas por pagar", "Escuela"])
    r.revisar("nada coincide", titulos("zzz").isEmpty)
    r.revisar("empieza en la segunda si la primera es la ventana donde estás",
              BuscadorVentanas.inicial(muestra, frente: muestra[0].pid) == muestra[1].id)
    r.revisar("empieza en la primera si estás en otra app", BuscadorVentanas.inicial(muestra, frente: 1) == muestra[0].id)

    if AXIsProcessTrusted() {
        // Solo cuenta y mide: no imprime títulos.
        let apps = BuscadorVentanas.appsVisibles()
        let t0 = Date()
        let ventanas = BuscadorVentanas.recolectar(apps)
        let total = Date().timeIntervalSince(t0)
        print(String(format: "Lectura real: %d apps, %d ventanas (%d minimizadas) en %.0f ms", apps.count, ventanas.count,
                     ventanas.filter(\.minimizada).count, total * 1000))
        r.revisar("la lectura termina en menos de medio segundo", total < 0.5)
    } else {
        print("Lectura real: este proceso no tiene Accesibilidad (se omite)")
    }
    return r.final()
}

/// Render del buscador con datos de ejemplo: sin búsqueda y buscando "informe". `Dictado --vista-buscador salida.png`
@MainActor
func hojaBuscador(_ destino: URL) -> Bool {
    let fondo = fondoDeMuestra()
    let ventanas = BuscadorVentanas.ordenar(ventanasDeMuestra())
    func panel(_ busqueda: String) -> some View {
        let estado = EstadoBuscador()
        estado.ventanas = ventanas
        estado.busqueda = busqueda
        let lista = BuscadorVentanas.filtrar(ventanas, busqueda)
        estado.seleccion = busqueda.isEmpty ? BuscadorVentanas.inicial(lista, frente: ventanas[0].pid) : lista.first?.id
        return lienzoConVidrio(fondo, lienzo: CGSize(width: 760, height: 620),
                               panel: CGSize(width: VistaBuscador.ancho, height: VistaBuscador.alto), radio: 28) {
            VistaBuscador(estado: estado, control: nil, simulado: true)
        }
    }
    let hoja = HStack(spacing: 0) { panel(""); panel("informe") }
    let renderer = ImageRenderer(content: hoja)
    renderer.scale = 2
    guard let cg = renderer.cgImage,
          let png = NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:]) else { return false }
    return (try? png.write(to: destino)) != nil
}
