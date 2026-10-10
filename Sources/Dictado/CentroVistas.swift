import AppKit
import SwiftUI

// Las secciones del centro de mando (Hoy, Metas, Orquesta, Inbox), cada una como ventanas en el espacio
// (CentroEspacio.swift). Las usan la ventana real (CentroVentana.swift) y el render de maquetas (`--vista-centro2`,
// `--vista-centro-real`). Solo pintan el estado: no calculan ni guardan nada. Las acciones abren cosas (el tablero de
// finanzas, una noticia, el archivo de metas, una sesión de Claude), piden una lectura fresca o aprueban el inbox.

enum SeccionCentro: String, CaseIterable {
    case hoy, metas, orquesta, inbox

    var titulo: String {
        switch self {
        case .hoy: return "Hoy"
        case .metas: return "Metas"
        case .orquesta: return "Orquesta"
        case .inbox: return "Inbox"
        }
    }

    var simbolo: String {
        switch self {
        case .hoy: return "sun.horizon"
        case .metas: return "scope"
        case .orquesta: return "square.stack.3d.up"
        case .inbox: return "tray"
        }
    }
}

/// Lo que la vista necesita además del estado. Con valores por defecto para poder renderizar sin la app viva.
struct ContextoCentro {
    var sesiones: [SesionesClaude.Sesion] = []
    var leido: Date?
    var cargando = false
    var error: String?
    var configurado = true
    var enVentana = false
    var actualizar: () -> Void = {}
    /// Ruta relativa al cerebro o URL.
    var abrir: (String) -> Void = { _ in }
    var abrirSesion: (SesionesClaude.Sesion) -> Void = { _ in }
    /// El inbox con un clic: qué se está aplicando, qué falló, y cómo aprobar (id, acción, destino).
    var aplicando: Set<String> = []
    var fallos: [String: String] = [:]
    var puedeActuar = false
    var aplicarInbox: (String, String, String?) -> Void = { _, _, _ in }
    var copiar: (String) -> Void = { _ in }
    var cerrar: () -> Void = {}
    var tokensHoy = 0
    var respuestasHoy = 0

    var esperando: [SesionesClaude.Sesion] { sesiones.filter { $0.estado == .esperando } }
    var trabajando: [SesionesClaude.Sesion] { sesiones.filter { $0.estado == .trabajando } }
}

// MARK: - Formatos

/// Un color estable por vertical, sacado del nombre (ningún nombre va escrito en el código).
func colorVertical(_ v: String) -> Color {
    let paleta = [Tono.azul.base, Tono.violeta.base, Tono.verde.base, Tono.ambar.base, Tono.claude.base,
                  Tono.brillo.claro, Tono.volumen.claro]
    var h = 5381
    for u in v.lowercased().unicodeScalars { h = (h &* 33 &+ Int(u.value)) & 0x7fff_ffff }
    return v.isEmpty ? Color(white: 0.7) : paleta[h % paleta.count]
}

/// "$119,1 M"
func millonesCOP(_ v: Double, signo: Bool = false) -> String {
    let f = NumberFormatter()
    f.locale = Locale(identifier: "es_CO")
    f.numberStyle = .decimal
    f.minimumFractionDigits = 1
    f.maximumFractionDigits = abs(v) < 10_000_000 ? 2 : 1
    let t = f.string(from: NSNumber(value: abs(v) / 1_000_000)) ?? ""
    return (signo ? (v < 0 ? "−" : "+") : (v < 0 ? "−" : "")) + "$" + t + " M"
}

/// "5:30 a. m."
func horaCorta(_ iso: String?) -> String? {
    guard let d = EstadoCentro.fecha(iso) else { return nil }
    let f = DateFormatter()
    f.locale = Locale(identifier: "es_CO")
    f.dateFormat = "h:mm a"
    return f.string(from: d)
}

func esHoy(_ isoDia: String?) -> Bool {
    let f = DateFormatter()
    f.dateFormat = "yyyy-MM-dd"
    return isoDia == f.string(from: Date())
}

private func enlace(_ t: String, accion: @escaping () -> Void) -> some View {
    BotonCentro(titulo: t, tipo: .enlace, accion: accion)
}

// MARK: - Escenas en el espacio

/// La sección en el espacio: cada una pone sus ventanas (y lo de debajo) en EspacioCentro.
struct EscenaCentro: View {
    let estado: EstadoCentro?
    let ctx: ContextoCentro
    @Binding var seccion: SeccionCentro

    var body: some View {
        if !ctx.configurado {
            soloCentro { SinConfigurar() }
        } else if let estado {
            switch seccion {
            case .hoy: EscenaHoyCentro(e: estado, ctx: ctx) { seccion = $0 }
            case .metas:
                if let m = estado.metas { EscenaMetasCentro(metas: m, ctx: ctx) } else { soloCentro { Vacio(texto: "Aún no hay metas publicadas.") } }
            case .orquesta: EscenaOrquestaCentro(e: estado, ctx: ctx)
            case .inbox: EscenaInboxCentro(e: estado, ctx: ctx)
            }
        } else {
            soloCentro { Vacio(texto: ctx.cargando ? "Leyendo el estado del día…" : (ctx.error ?? "Sin datos todavía.")) }
        }
    }

    private func soloCentro<C: View>(@ViewBuilder _ c: @escaping () -> C) -> some View {
        EspacioCentro { EmptyView() } centro: { VentanaEspacio { c() } } derecha: { EmptyView() }
    }
}

private func usd(_ v: Double) -> String { String(format: "%.2f", v).replacingOccurrences(of: ".", with: ",") }

private func tokensCortos(_ n: Int) -> String {
    if n >= 1_000_000 { return String(format: "%.1f M", Double(n) / 1_000_000).replacingOccurrences(of: ".", with: ",") }
    if n >= 1_000 { return "\(n / 1_000) k" }
    return "\(n)"
}

// MARK: - Hoy

/// Hoy: tus agentes a la izquierda, el brief al frente, finanzas y radar a la derecha y las metas debajo.
private struct EscenaHoyCentro: View {
    let e: EstadoCentro
    let ctx: ContextoCentro
    let ir: (SeccionCentro) -> Void

    var body: some View {
        EspacioCentro {
            VentanaEspacio { AgentesHoyCentro(e: e, ctx: ctx) { ir(.inbox) } }
        } centro: {
            if let b = e.brief {
                VentanaEspacio(relleno: 28) { BriefCentro(b: b) }
            } else {
                VentanaEspacio { Vacio(texto: "El brief de hoy todavía no se ha generado: sale a las 5:30 en tu VPS.") }
            }
        } derecha: {
            VStack(spacing: 16) {
                if let f = e.finanzas {
                    VentanaEspacio { FinanzasCentro(f: f, ctx: ctx) }.fixedSize(horizontal: false, vertical: true)
                }
                if let n = e.noticias, !n.items.isEmpty {
                    VentanaEspacio { RadarCentro(items: Array(n.items.prefix(3)), ctx: ctx) }
                }
            }
            .frame(maxHeight: .infinity, alignment: .top)
        } debajo: {
            if let m = e.metas { MetasDebajoCentro(m: m) { ir(.metas) } }
        }
    }
}

private struct AgentesHoyCentro: View {
    let e: EstadoCentro
    let ctx: ContextoCentro
    let irAlInbox: () -> Void

    /// Primero lo que te espera, luego lo que trabaja, luego lo listo (lo más reciente arriba).
    private var sesiones: [SesionesClaude.Sesion] {
        func orden(_ s: SesionesClaude.Sesion) -> Int { s.estado == .esperando ? 0 : (s.estado == .trabajando ? 1 : 2) }
        return ctx.sesiones.sorted { orden($0) != orden($1) ? orden($0) < orden($1) : $0.desde > $1.desde }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            CabeceraVentana(titulo: "Agentes", detalle: detalle)
            if sesiones.isEmpty {
                Text("Ninguna sesión de Claude abierta en el Mac.").font(.system(size: 12)).foregroundStyle(TextoCentro.terciario)
            } else {
                VStack(spacing: 2) {
                    ForEach(sesiones.prefix(5)) { s in FilaSesionCentro(s: s) { ctx.abrirSesion(s) } }
                }
                .padding(.horizontal, -10)
            }
            FiloCentro()
            HermesCentro(e: e)
            if let ib = e.inbox, !ib.items.isEmpty {
                FiloCentro()
                LlegoCentro(items: ib.items, accion: irAlInbox)
            }
            Spacer(minLength: 0)
            VStack(alignment: .leading, spacing: 5) {
                if ctx.tokensHoy > 0 {
                    HStack(alignment: .firstTextBaseline, spacing: 7) {
                        Cifra(numero: tokensCortos(ctx.tokensHoy), tamano: 26)
                        Text("tokens de Claude hoy · \(ctx.respuestasHoy) respuestas").font(.system(size: 12)).foregroundStyle(TextoCentro.terciario)
                    }
                }
                if let o = e.orquesta, o.costoDisponible != false {
                    Text("Hermes: \(usd(o.costoHoy)) USD hoy · el mes va en \(usd(o.costoMes)) de \(Int(o.presupuestoMes))")
                        .font(.system(size: 11.5)).monospacedDigit().foregroundStyle(TextoCentro.terciario)
                }
            }
        }
    }

    private var detalle: String {
        let n = ctx.sesiones.count
        var t = n == 1 ? "1 sesión de Claude" : "\(n) sesiones de Claude"
        if !ctx.trabajando.isEmpty { t += " · \(ctx.trabajando.count) trabajando" }
        if !ctx.esperando.isEmpty { t += ctx.esperando.count == 1 ? " · 1 te espera" : " · \(ctx.esperando.count) te esperan" }
        return t
    }
}

/// Una sesión de Claude Code: al tocarla se abre justo esa sesión.
private struct FilaSesionCentro: View {
    let s: SesionesClaude.Sesion
    let accion: () -> Void

    var body: some View {
        Button(action: accion) {
            HStack(alignment: .top, spacing: 12) {
                Group {
                    switch s.estado {
                    case .trabajando: EstrellaClaude().fill(Tono.claude.base).frame(width: 14, height: 14)
                    case .esperando: PuntoBrillante(color: Tono.claude.base, lado: 8)
                    case .lista: Image(systemName: "checkmark").font(.system(size: 11, weight: .bold)).foregroundStyle(TextoCentro.terciario)
                    }
                }
                .frame(width: 18, height: 18)
                VStack(alignment: .leading, spacing: 2) {
                    Text(s.nombre).font(.system(size: 14, weight: .semibold)).foregroundStyle(Halo.texto).lineLimit(1)
                    Text(linea).font(.system(size: 11.5))
                        .foregroundStyle(s.estado == .esperando ? Tono.claude.claro : TextoCentro.terciario).lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10).padding(.vertical, 8)
            .contentShape(Rectangle())
            .modifier(EncimaCentro(radio: 12))
        }
        .buttonStyle(.plain)
        .help("Abrir la sesión")
    }

    private var linea: String {
        switch s.estado {
        case .esperando: return s.espera.isEmpty ? "Espera tu respuesta" : s.espera
        case .trabajando: return s.actividad.isEmpty ? "Trabajando · \(hace(s.desde))" : s.actividad
        case .lista: return "Lista · \(hace(s.desde))" + (s.resumen.isEmpty ? "" : " · \(s.resumen)")
        }
    }
}

/// Tu agente del VPS: si está vivo, cuánto corrió hoy y qué sigue.
private struct HermesCentro: View {
    let e: EstadoCentro

    var body: some View {
        let rotas = (e.salud?.capacidades ?? []).filter { $0.estado == "rota" || $0.estado == "alerta" }
        let tono: Tono = !e.vps ? .rojo : (rotas.isEmpty ? .verde : .ambar)
        let estado = !e.vps ? "Sin conexión" : (rotas.isEmpty ? "En línea" : "Con alertas")
        HStack(alignment: .top, spacing: 12) {
            Insignia(icono: .simbolo("server.rack"), tono: tono, lado: 34)
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text("Hermes · VPS").font(.system(size: 14, weight: .semibold)).foregroundStyle(Halo.texto)
                    Spacer()
                    HStack(spacing: 5) {
                        PuntoBrillante(color: tono.base, lado: 5)
                        Text(estado).font(.system(size: 11.5, weight: .semibold)).foregroundStyle(tono.claro)
                    }
                }
                Text(linea(rotas)).font(.system(size: 11.5)).foregroundStyle(TextoCentro.secundario).lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func linea(_ rotas: [EstadoCentro.Capacidad]) -> String {
        if let r = rotas.first { return "\(r.nombre): \(r.detalle ?? r.estado)" }
        guard let o = e.orquesta else { return "Sin datos de la orquesta." }
        var p = [o.hecho.count == 1 ? "1 corrida hoy" : "\(o.hecho.count) corridas hoy"]
        if let s = o.programado.first { p.append("sigue \(s.titulo)" + (s.cuando.map { " \($0)" } ?? "")) }
        return p.joined(separator: " · ")
    }
}

/// Lo último que capturaste, para verlo sin salir de Hoy; clasificarlo es en Inbox.
private struct LlegoCentro: View {
    let items: [EstadoCentro.Propuesta]
    let accion: () -> Void

    var body: some View {
        let recientes = items.sorted { ($0.fecha ?? "") > ($1.fecha ?? "") }.prefix(3)
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Rotulo("En tu inbox · \(items.count)", color: TextoCentro.terciario)
                Spacer()
                BotonCentro(titulo: "Clasificar", tipo: .enlace, accion: accion)
            }
            ForEach(Array(recientes), id: \.id) { p in
                HStack(spacing: 10) {
                    Image(systemName: iconoCaptura(p)).font(.system(size: 11)).foregroundStyle(TextoCentro.terciario).frame(width: 16)
                    Text(p.titulo).font(.system(size: 12.5)).foregroundStyle(Halo.texto).lineLimit(1)
                    Spacer(minLength: 6)
                    if let f = p.fecha, let d = EscenaMetasCentroFecha.dia(f) {
                        Text(hace(d)).font(.system(size: 11)).foregroundStyle(TextoCentro.terciario).fixedSize()
                    }
                }
            }
        }
    }
}

/// El brief del día al frente: saludo y clima, el foco levantado (lo único que pide tu atención), las prioridades
/// y lo bueno de saber.
private struct BriefCentro: View {
    let b: EstadoCentro.Brief

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 5) {
                    Rotulo("\(b.fecha) · semana \(b.semana)", color: TextoCentro.terciario)
                    Text(saludo).font(.system(size: 32, weight: .thin)).foregroundStyle(Halo.texto)
                    HStack(spacing: 6) {
                        EstrellaClaude().fill(Tono.claude.claro).frame(width: 10, height: 10)
                        Text(generado).font(.system(size: 11.5)).foregroundStyle(TextoCentro.terciario).lineLimit(1)
                    }
                }
                Spacer(minLength: 8)
                if let c = b.clima { clima(c) }
            }
            if !esHoy(b.fechaIso) {
                Text("Es de otro día: el brief de hoy aún no sale").font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Tono.ambar.claro).padding(.horizontal, 9).frame(height: 22)
                    .background(Capsule().fill(Tono.ambar.base.opacity(0.14))).padding(.top, 10)
            }
            VStack(alignment: .leading, spacing: 8) {
                Rotulo("El foco", color: Tono.ambar.claro)
                Text(b.foco.titulo).font(.system(size: 18)).foregroundStyle(Halo.texto)
                    .lineSpacing(2).fixedSize(horizontal: false, vertical: true)
                Text(b.foco.porque).font(.system(size: 12.5)).foregroundStyle(TextoCentro.secundario)
                    .lineSpacing(3).lineLimit(5).fixedSize(horizontal: false, vertical: true)
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .levantado(radio: 20, tono: .ambar)
            .padding(.top, 20)
            HStack(alignment: .firstTextBaseline) {
                Text("Prioridades").font(.system(size: 15, weight: .semibold)).foregroundStyle(Halo.texto)
                Spacer()
                Text("\(b.prioridades.filter(\.hecha).count) de \(b.prioridades.count) hechas").font(.system(size: 11)).foregroundStyle(TextoCentro.terciario)
            }
            .padding(.top, 22)
            VStack(spacing: 0) {
                ForEach(Array(b.prioridades.prefix(3).enumerated()), id: \.offset) { i, p in
                    FiloCentro()
                    FilaPrioridadCentro(numero: i + 1, p: p)
                }
                FiloCentro()
            }
            .padding(.top, 8)
            if !b.buenoSaber.isEmpty {
                Rotulo("Bueno saber", color: TextoCentro.terciario).padding(.top, 18)
                VStack(alignment: .leading, spacing: 7) {
                    ForEach(Array(b.buenoSaber.prefix(3).enumerated()), id: \.offset) { _, t in
                        HStack(alignment: .top, spacing: 9) {
                            Circle().fill(.white.opacity(0.4)).frame(width: 3, height: 3).padding(.top, 7)
                            // Sin fixedSize: si falta alto, esto es lo que se acorta (lo demás no).
                            Text(t).font(.system(size: 12)).foregroundStyle(TextoCentro.secundario).lineLimit(2)
                        }
                    }
                }
                .padding(.top, 9)
            }
            Spacer(minLength: 0)
        }
    }

    /// El nombre sale de la cuenta del Mac (nada personal escrito en el código).
    private var saludo: String {
        let nombre = NSFullUserName().split(separator: " ").first.map(String.init) ?? ""
        return nombre.isEmpty ? "Tu día" : "Hola, \(nombre)"
    }

    private var generado: String {
        var partes = ["Brief de \(b.modelo)"]
        if let h = horaCorta(b.generado) { partes.append(h) }
        if let f = b.fuentes { partes.append("\(f) fuentes") }
        return partes.joined(separator: " · ")
    }

    private func clima(_ c: EstadoCentro.Brief.Clima) -> some View {
        VStack(alignment: .trailing, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: c.simbolo).font(.system(size: 18, weight: .light)).foregroundStyle(TextoCentro.secundario)
                Text("\(c.temp)°").font(.system(size: 30, weight: .thin)).foregroundStyle(Halo.texto)
            }
            Text("\(c.cielo) · \(c.ciudad)").font(.system(size: 11.5)).foregroundStyle(TextoCentro.secundario).lineLimit(1)
            Text(detalleClima(c)).font(.system(size: 11)).foregroundStyle(TextoCentro.terciario).lineLimit(1)
        }
    }

    private func detalleClima(_ c: EstadoCentro.Brief.Clima) -> String {
        var t = "Máx \(c.max)° · mín \(c.min)°"
        if b.agendaLeida == true { t += (b.agenda ?? []).isEmpty ? " · sin reuniones" : " · \((b.agenda ?? []).count) en agenda" }
        return t
    }
}

/// Finanzas en resumen, sin cifra de vitrina: lo que importa en una lista corta y el colchón como regla de marcas.
/// El detalle vive en el tablero real (el enlace).
private struct FinanzasCentro: View {
    let f: EstadoCentro.Finanzas
    let ctx: ContextoCentro

    var body: some View {
        let piso = f.colchonPiso > 0 ? min(1, f.colchon / f.colchonPiso) : 0
        VStack(alignment: .leading, spacing: 11) {
            HStack(alignment: .top) {
                CabeceraVentana(titulo: "Finanzas", detalle: actualizado)
                Spacer()
                if let e = f.enlace { enlace("Abrir el tablero") { ctx.abrir(e) }.padding(.top, 5) }
            }
            .padding(.bottom, 4)
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("Patrimonio neto").font(.system(size: 12.5)).foregroundStyle(TextoCentro.secundario)
                Spacer()
                Text(millonesCOP(f.patrimonio)).font(.system(size: 20, weight: .light)).monospacedDigit().foregroundStyle(Halo.texto)
                Text(millonesCOP(f.delta, signo: true)).font(.system(size: 11, weight: .semibold)).monospacedDigit()
                    .foregroundStyle(f.delta >= 0 ? Tono.verde.claro : Tono.rojo.claro)
            }
            fila("Liquidez", millonesCOP(f.liquidez))
            fila("Neto del mes", millonesCOP(f.netoMes, signo: true))
            HStack(spacing: 10) {
                Text("Colchón").font(.system(size: 12.5)).foregroundStyle(TextoCentro.secundario)
                Regla(valor: piso, tono: .neutro, cuantas: 26, alto: 9, grosor: 1)
                Text("\(Int((piso * 100).rounded())) % del piso").font(.system(size: 11.5, weight: .medium)).monospacedDigit()
                    .foregroundStyle(Halo.texto).fixedSize()
            }
            if f.alerta != nil || !f.proximos.isEmpty { FiloCentro().padding(.vertical, 2) }
            if let alerta = f.alerta {
                Label(alerta, systemImage: "exclamationmark.circle").font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(Tono.ambar.claro).lineLimit(2)
            }
            ForEach(Array(f.proximos.prefix(2).enumerated()), id: \.offset) { _, p in
                HStack(spacing: 8) {
                    Text(p.concepto).font(.system(size: 12)).foregroundStyle(TextoCentro.secundario).lineLimit(1)
                    Spacer()
                    Text(p.fecha).font(.system(size: 11)).foregroundStyle(TextoCentro.terciario)
                    Text("$" + miles(Int(p.monto))).font(.system(size: 12, weight: .medium)).monospacedDigit()
                        .foregroundStyle(Halo.texto).frame(width: 74, alignment: .trailing)
                }
            }
        }
    }

    private var actualizado: String {
        guard let d = f.diasSinActualizar else { return "Al \(f.actualizado)" }
        return d == 0 ? "Actualizado hoy" : (d == 1 ? "Actualizado ayer" : "Actualizado hace \(d) días")
    }

    private func fila(_ r: String, _ v: String) -> some View {
        HStack {
            Text(r).font(.system(size: 12.5)).foregroundStyle(TextoCentro.secundario)
            Spacer()
            Text(v).font(.system(size: 13, weight: .medium)).monospacedDigit().foregroundStyle(Halo.texto)
        }
    }
}

private struct RadarCentro: View {
    let items: [EstadoCentro.Noticia]
    let ctx: ContextoCentro

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            CabeceraVentana(titulo: "En tu radar", detalle: "Lo que se movió en tus frentes")
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, x in
                    Button { if let u = x.url { ctx.abrir(u) } } label: {
                        fila(x).padding(.vertical, 6).padding(.horizontal, 8).modifier(EncimaCentro(radio: 12))
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, -8)
                    .help(x.url == nil ? "" : "Abrir la noticia")
                }
            }
        }
    }

    private func fila(_ x: EstadoCentro.Noticia) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Circle().fill(colorVertical(x.vertical)).frame(width: 6, height: 6).padding(.top, 6)
            VStack(alignment: .leading, spacing: 3) {
                Text(x.titulo).font(.system(size: 12.5, weight: .semibold)).foregroundStyle(Halo.texto).lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                if !x.porQue.isEmpty {
                    Text(x.porQue).font(.system(size: 11.5)).foregroundStyle(TextoCentro.secundario).lineLimit(1)
                }
                Text("\(x.vertical) · \(x.fuente) · \(x.fecha)").font(.system(size: 11)).foregroundStyle(TextoCentro.terciario).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
    }
}

/// Debajo de Hoy: las tres metas que mandan (semana, mes, trimestre). Al tocarlo se va a Metas.
private struct MetasDebajoCentro: View {
    let m: EstadoCentro.Metas
    let accion: () -> Void
    @State private var encima = false

    var body: some View {
        Button(action: accion) {
            HStack(spacing: 0) {
                ForEach(Array([m.semana, m.mes, m.trimestre].enumerated()), id: \.offset) { i, h in
                    if i > 0 { Rectangle().fill(Halo.linea).frame(width: 0.75).padding(.vertical, 16) }
                    columna(h)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(RoundedRectangle(cornerRadius: 26, style: .continuous).fill(.white.opacity(encima ? 0.05 : 0)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Ver tus metas (⌘2)")
        .onHover { encima = $0 }
        .ornamento(radio: 26)
    }

    private func columna(_ h: EstadoCentro.Horizonte) -> some View {
        let hechas = h.metas.filter { $0.estado == "hecha" }.count
        let principal = h.metas.first { $0.estado != "hecha" } ?? h.metas.first
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Rotulo(h.nombre, color: TextoCentro.terciario)
                Spacer()
                Text("\(hechas) de \(h.metas.count)").font(.system(size: 11)).monospacedDigit().foregroundStyle(TextoCentro.terciario)
            }
            Text(principal?.texto ?? (h.vigente == false ? "Define las metas de esta semana" : "—"))
                .font(.system(size: 13, weight: .semibold)).foregroundStyle(Halo.texto).lineLimit(1)
            HStack(spacing: 8) {
                Regla(valor: h.tiempo, tono: .neutro, cuantas: 26, alto: 8, grosor: 1)
                Text("\(Int((h.tiempo * 100).rounded())) % del tiempo").font(.system(size: 11)).monospacedDigit()
                    .foregroundStyle(TextoCentro.terciario).fixedSize()
            }
        }
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct Vacio: View {
    let texto: String
    var body: some View {
        Text(texto).font(.system(size: 13)).foregroundStyle(TextoCentro.secundario)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct SinConfigurar: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Rotulo("Centro de mando", color: TextoCentro.terciario)
            Text("Conecta tu centro").font(.system(size: 30, weight: .thin)).foregroundStyle(Halo.texto)
            Text("La ventana lee un comando que imprime el estado del día en JSON (el contrato del centro). Configúralo así:")
                .font(.system(size: 13)).foregroundStyle(TextoCentro.secundario)
            Text("defaults write app.dictado centro -dict comando '\"/ruta/a/estado.sh\"'")
                .font(.system(size: 12, design: .monospaced)).foregroundStyle(Halo.texto)
                .padding(12).background(RoundedRectangle(cornerRadius: 10).fill(.white.opacity(0.06)))
                .textSelection(.enabled)
        }
        .padding(40)
        .frame(maxWidth: 640, maxHeight: .infinity, alignment: .leading)
    }
}

private struct FilaPrioridadCentro: View {
    let numero: Int
    let p: EstadoCentro.Brief.Prioridad

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Text(String(format: "%02d", numero)).font(.system(size: 12, weight: .light)).monospacedDigit()
                .foregroundStyle(TextoCentro.terciario).padding(.top, 1)
            VStack(alignment: .leading, spacing: 4) {
                Text(p.texto).font(.system(size: 13.5)).foregroundStyle(Halo.texto).lineLimit(2)
                HStack(spacing: 6) {
                    Circle().fill(colorVertical(p.vertical)).frame(width: 5, height: 5)
                    Text(detalle).font(.system(size: 11)).foregroundStyle(TextoCentro.terciario).lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            Circle().strokeBorder(.white.opacity(p.hecha ? 0 : 0.32), lineWidth: 1)
                .background { if p.hecha { Circle().fill(.white.opacity(0.9)) } }
                .frame(width: 17, height: 17)
                .padding(.top, 1)
        }
        .padding(.vertical, 11)
    }

    private var detalle: String {
        var partes = [p.vertical].filter { !$0.isEmpty }
        if let m = p.meta { partes.append("Meta: \(m)") }
        if let n = p.minutos { partes.append("\(n) min") }
        if let d = p.delegable { partes.append("se puede delegar a \(d)") }
        return partes.joined(separator: " · ")
    }
}

// MARK: - Metas

/// Metas: la semana, el mes y el trimestre, cada uno en su ventana; debajo, el trimestre como regla con sus hitos.
private struct EscenaMetasCentro: View {
    let metas: EstadoCentro.Metas
    let ctx: ContextoCentro

    private var hito: Date? {
        metas.hitos?.first { $0.alerta && ($0.diasRestantes ?? 0) >= 0 }.flatMap { $0.fecha }.flatMap(Self.dia)
    }

    static func dia(_ iso: String) -> Date? {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.date(from: iso)
    }

    var body: some View {
        EspacioCentro {
            VentanaEspacio(relleno: 0) { TarjetaHorizonteCentro(h: metas.semana, dibujo: .semana, hito: hito) }
        } centro: {
            VentanaEspacio(relleno: 0) { TarjetaHorizonteCentro(h: metas.mes, dibujo: .mes, hito: hito) }
        } derecha: {
            VentanaEspacio(relleno: 0) { TarjetaHorizonteCentro(h: metas.trimestre, dibujo: .trimestre, hito: hito) }
        } debajo: {
            HStack(spacing: 22) {
                ReglaTrimestreCentro(t: metas.trimestre, hitos: metas.hitos ?? []).frame(height: 46)
                if let a = metas.archivo {
                    VStack(alignment: .trailing, spacing: 5) {
                        BotonCentro(titulo: "Editar metas", icono: "square.and.pencil", tipo: .principal) { ctx.abrir(a) }
                        if metas.borrador == true {
                            Text("Borrador para que decidas").font(.system(size: 11)).foregroundStyle(TextoCentro.terciario)
                        }
                    }
                    .fixedSize()
                }
            }
            .padding(.horizontal, 24)
            .frame(maxHeight: .infinity)
            .ornamento(radio: 26)
        }
    }
}

/// Los días del trimestre como marcas finas: los lunes más altos, lo vivido encendido y hoy con brillo.
private struct ReglaTrimestreCentro: View {
    let t: EstadoCentro.Horizonte
    let hitos: [EstadoCentro.Hito]

    private var dias: Int { t.dias ?? 92 }
    private var hoy: Int { (t.dia ?? Int((t.tiempo * Double(dias)).rounded())) - 1 }
    /// Cuántos días faltan para el primer lunes desde el inicio del trimestre.
    private var primerLunes: Int {
        guard let d = t.desde.flatMap(EscenaMetasCentro.dia) else { return 0 }
        let w = Calendar(identifier: .gregorian).component(.weekday, from: d)   // 1 = domingo
        return (9 - w) % 7
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(t.nombre).font(.system(size: 12, weight: .semibold)).foregroundStyle(Halo.texto)
                Text(t.rango).font(.system(size: 11)).foregroundStyle(TextoCentro.terciario)
                Spacer()
                Text(resumen).font(.system(size: 11)).monospacedDigit().foregroundStyle(TextoCentro.terciario)
            }
            GeometryReader { g in
                let paso = g.size.width / CGFloat(max(1, dias - 1))
                ZStack(alignment: .topLeading) {
                    Canvas { ctx, _ in
                        for d in 0..<dias {
                            let alto: CGFloat = (d - primerLunes) % 7 == 0 ? 14 : 8
                            let op = d == hoy ? 1.0 : (d < hoy ? 0.55 : 0.16)
                            ctx.fill(Path(CGRect(x: CGFloat(d) * paso - 0.5, y: 16 - alto, width: 1, height: alto)),
                                     with: .color(.white.opacity(op)))
                        }
                    }
                    .frame(height: 16)
                    Circle().fill(.white).frame(width: 5, height: 5).shadow(color: .white, radius: 4)
                        .offset(x: CGFloat(max(0, hoy)) * paso - 2.5, y: 19)
                    // Todos los hitos llevan su punto; solo los de alerta llevan texto (así no se enciman). Cerca del
                    // final del trimestre el texto va a la izquierda del punto para no salirse.
                    ForEach(Array(hitos.filter { $0.dia >= 1 && $0.dia <= dias }.enumerated()), id: \.offset) { _, h in
                        let x = CGFloat(h.dia - 1) * paso
                        let alFinal = h.dia > dias * 7 / 10
                        HStack(spacing: 5) {
                            if alFinal && h.alerta { Text(etiqueta(h)).font(.system(size: 10.5)).foregroundStyle(TextoCentro.terciario).fixedSize() }
                            Circle().fill(h.alerta ? Tono.ambar.base : Color.white.opacity(0.5)).frame(width: 4, height: 4)
                            if !alFinal && h.alerta { Text(etiqueta(h)).font(.system(size: 10.5)).foregroundStyle(TextoCentro.terciario).fixedSize() }
                        }
                        .frame(width: 360, alignment: alFinal ? .trailing : .leading)
                        .offset(x: alFinal ? x - 358 : x - 2, y: 20)
                    }
                }
            }
        }
    }

    private var resumen: String {
        var p = [String]()
        if let s = t.semana, let n = t.semanas { p.append("Semana \(s) de \(n)") }
        p.append("\(Int((t.tiempo * 100).rounded())) % del trimestre")
        return p.joined(separator: " · ")
    }

    private func etiqueta(_ h: EstadoCentro.Hito) -> String {
        guard let iso = h.fecha, let d = EscenaMetasCentro.dia(iso) else { return h.texto }
        let f = DateFormatter()
        f.locale = Locale(identifier: "es_CO")
        f.dateFormat = "d MMM"
        return "\(h.texto) · \(f.string(from: d).replacingOccurrences(of: ".", with: ""))"
    }
}

private enum DibujoCentro { case semana, mes, trimestre }

private struct TarjetaHorizonteCentro: View {
    let h: EstadoCentro.Horizonte
    let dibujo: DibujoCentro
    let hito: Date?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack {
                LinearGradient(colors: [.white.opacity(0.05), .clear], startPoint: .top, endPoint: .bottom)
                switch dibujo {
                case .semana: SemanaDibujo()
                case .mes: MesDibujo(mes: Date(), conHoy: true, hito: hito, lado: 16).frame(width: 236)
                case .trimestre: TrimestreDibujo(hito: hito)
                }
            }
            .frame(height: 196)
            .frame(maxWidth: .infinity)
            VStack(alignment: .leading, spacing: 4) {
                Text(h.nombre).font(.system(size: 26, weight: .thin)).foregroundStyle(Halo.texto)
                Text("\(h.subtitulo) · \(h.rango)").font(.system(size: 11)).foregroundStyle(TextoCentro.terciario).lineLimit(1)
            }
            .padding(.horizontal, 22).padding(.top, 6)
            HStack(spacing: 10) {
                Regla(valor: h.tiempo, tono: .neutro, cuantas: 40, alto: 9, grosor: 1)
                let hechas = h.metas.filter { $0.estado == "hecha" }.count
                Text("\(Int((h.tiempo * 100).rounded())) % del tiempo · \(hechas) de \(h.metas.count) hechas")
                    .font(.system(size: 11)).monospacedDigit().foregroundStyle(TextoCentro.terciario).fixedSize()
            }
            .padding(.horizontal, 22).padding(.top, 14)
            Rectangle().fill(Halo.linea).frame(height: 1).padding(.vertical, 16)
            VStack(spacing: 18) {
                if h.metas.isEmpty {
                    Text(h.vigente == false ? "Las metas escritas son de otra semana: defínelas en la revisión."
                                            : "Sin metas todavía.")
                        .font(.system(size: 12)).foregroundStyle(TextoCentro.terciario).frame(maxWidth: .infinity, alignment: .leading)
                }
                ForEach(Array(h.metas.enumerated()), id: \.offset) { _, m in FilaMetaCentro(m: m) }
            }
            .padding(.horizontal, 18)
            Spacer(minLength: 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private struct FilaMetaCentro: View {
    let m: EstadoCentro.Meta

    var body: some View {
        let hecha = m.estado == "hecha"
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                ZStack {
                    Circle().strokeBorder(.white.opacity(hecha ? 0 : 0.32), lineWidth: 1)
                    if hecha {
                        Circle().fill(.white.opacity(0.9))
                        Image(systemName: "checkmark").font(.system(size: 8, weight: .heavy)).foregroundStyle(.black)
                    }
                }
                .frame(width: 17, height: 17)
                Text(m.texto).font(.system(size: 13)).foregroundStyle(hecha ? TextoCentro.secundario : Halo.texto).lineLimit(1)
                Spacer(minLength: 6)
                PildoraEstadoCentro(estado: m.estado)
            }
            HStack(spacing: 10) {
                Liquido(valor: max(0.02, m.avance), tono: .neutro, alto: 4).frame(width: 110)
                Text(m.medida).font(.system(size: 11)).foregroundStyle(TextoCentro.terciario).lineLimit(1)
                Spacer()
                Circle().fill(colorVertical(m.vertical)).frame(width: 5, height: 5)
                Text(m.vertical).font(.system(size: 11)).foregroundStyle(TextoCentro.terciario).lineLimit(1)
            }
            .padding(.leading, 27)
        }
    }
}

private struct PildoraEstadoCentro: View {
    let estado: String

    var body: some View {
        let t = estado == "hecha" ? "Hecha" : (estado == "en_curso" ? "En curso" : "Planeada")
        HStack(spacing: 5) {
            if estado == "en_curso" { PuntoBrillante(color: .white, lado: 4) }
            Text(t).font(.system(size: 11, weight: .medium))
        }
        .foregroundStyle(estado == "planeada" ? TextoCentro.terciario : TextoCentro.secundario)
        .padding(.horizontal, 9).frame(height: 22)
        .background(Capsule().fill(.white.opacity(estado == "en_curso" ? 0.09 : 0.04)))
        .overlay(Capsule().strokeBorder(.white.opacity(0.08), lineWidth: 0.75))
    }
}

// MARK: - Calendaritos (semana, mes y trimestre de la fecha real)

private struct VentanitaCentro<C: View>: View {
    var titulo: String
    @ViewBuilder let contenido: () -> C

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(titulo).font(.system(size: 9, weight: .semibold)).tracking(0.8).foregroundStyle(TextoCentro.secundario)
                Spacer()
                Circle().fill(.white.opacity(0.6)).frame(width: 4, height: 4)
            }
            contenido()
        }
        .padding(12)
        .background {   // opaco a propósito: en el trimestre se apilan y no deben verse unos a través de otros
            RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color(white: 0.29))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(LinearGradient(colors: [.white.opacity(0.07), .clear], startPoint: .top, endPoint: .center)))
        }
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .strokeBorder(LinearGradient(colors: [.white.opacity(0.26), .white.opacity(0.08)], startPoint: .top, endPoint: .bottom), lineWidth: 0.75))
        .shadow(color: .black.opacity(0.28), radius: 14, y: 8)
    }
}

private struct CeldaCentro: View {
    enum Estado { case vivida, hoy, futura, vacia }
    let estado: Estado
    var lado: CGFloat = 14
    var hito = false

    var body: some View {
        RoundedRectangle(cornerRadius: lado * 0.22, style: .continuous)
            .fill(relleno)
            .frame(width: lado, height: lado)
            .overlay {
                if hito {
                    Circle().fill(Tono.ambar.base).frame(width: lado * 0.34, height: lado * 0.34).shadow(color: Tono.ambar.base, radius: 3)
                }
            }
            .shadow(color: estado == .hoy ? .white.opacity(0.8) : .clear, radius: 5)
    }

    private var relleno: Color {
        switch estado {
        case .vivida: return .white.opacity(0.3)
        case .hoy: return .white.opacity(0.95)
        case .futura: return .white.opacity(0.1)
        case .vacia: return .clear
        }
    }
}

private let calendarioISO: Calendar = {
    var c = Calendar(identifier: .iso8601)
    c.timeZone = .current
    return c
}()

private struct SemanaDibujo: View {
    var body: some View {
        let hoy = (calendarioISO.component(.weekday, from: Date()) + 5) % 7   // lunes = 0
        let numero = calendarioISO.component(.weekOfYear, from: Date())
        VentanitaCentro(titulo: "SEMANA \(numero)") {
            HStack(spacing: 7) {
                ForEach(Array(["L", "M", "M", "J", "V", "S", "D"].enumerated()), id: \.offset) { i, d in
                    VStack(spacing: 5) {
                        Text(d).font(.system(size: 8.5, weight: .medium)).foregroundStyle(TextoCentro.terciario)
                        CeldaCentro(estado: i < hoy ? .vivida : (i == hoy ? .hoy : .futura), lado: 20)
                    }
                }
            }
        }
        .frame(width: 228)
    }
}

/// Un mes con sus días en una rejilla que empieza el lunes; hoy encendido y el hito (si cae en el mes) marcado.
private struct MesDibujo: View {
    let mes: Date
    var conHoy: Bool
    var hito: Date?
    var lado: CGFloat

    var body: some View {
        let cal = calendarioISO
        let inicio = cal.date(from: cal.dateComponents([.year, .month], from: mes)) ?? mes
        let desfase = (cal.component(.weekday, from: inicio) + 5) % 7
        let dias = cal.range(of: .day, in: .month, for: inicio)?.count ?? 30
        let mismoMes = cal.isDate(Date(), equalTo: inicio, toGranularity: .month)
        let hoy = conHoy && mismoMes ? cal.component(.day, from: Date()) : (inicio < Date() ? dias + 1 : 0)
        let diaHito = hito.flatMap { cal.isDate($0, equalTo: inicio, toGranularity: .month) ? cal.component(.day, from: $0) : nil }
        let f = DateFormatter()
        f.locale = Locale(identifier: "es_CO")
        f.dateFormat = "MMMM"
        let filas = (desfase + dias + 6) / 7
        return VentanitaCentro(titulo: f.string(from: inicio).uppercased()) {
            VStack(spacing: lado * 0.31) {
                ForEach(0..<filas, id: \.self) { fila in
                    HStack(spacing: lado * 0.31) {
                        ForEach(0..<7, id: \.self) { col in
                            let d = fila * 7 + col - desfase + 1
                            CeldaCentro(estado: d < 1 || d > dias ? .vacia : (d < hoy ? .vivida : (d == hoy ? .hoy : .futura)),
                                        lado: lado, hito: d == diaHito)
                        }
                    }
                }
            }
        }
    }
}

private struct TrimestreDibujo: View {
    let hito: Date?

    var body: some View {
        let cal = calendarioISO
        let mes = cal.component(.month, from: Date())
        let primero = cal.date(from: DateComponents(year: cal.component(.year, from: Date()), month: ((mes - 1) / 3) * 3 + 1, day: 1)) ?? Date()
        let meses = (0..<3).compactMap { cal.date(byAdding: .month, value: $0, to: primero) }
        ZStack {
            // Escalonadas hacia arriba a la derecha: de cada mes de atrás se ve su rótulo.
            ForEach(Array(meses.enumerated().reversed()), id: \.offset) { i, m in
                MesDibujo(mes: m, conHoy: true, hito: hito, lado: 10)
                    .frame(width: 150)
                    .offset(x: CGFloat(i) * 30 - 16, y: 26 - CGFloat(i) * 28)
                    .opacity(1 - Double(i) * 0.15)
            }
        }
    }
}

// MARK: - Orquesta

/// Orquesta: lo que pide tu sí a la izquierda (se enciende si hay algo), lo que pasa ahora y la semana de tus agentes
/// al frente, lo programado y lo hecho a la derecha; debajo, cuánto va costando.
private struct EscenaOrquestaCentro: View {
    let e: EstadoCentro
    let ctx: ContextoCentro

    var body: some View {
        let o = e.orquesta
        let piden = (o?.aprobaciones.count ?? 0) + ctx.esperando.count
        EspacioCentro {
            VentanaEspacio(tono: piden > 0 ? .claude : nil) {
                VStack(alignment: .leading, spacing: 14) {
                    CabeceraVentana(titulo: "Piden tu sí", detalle: piden == 0 ? "Nada espera una decisión"
                                    : (piden == 1 ? "1 decisión te espera" : "\(piden) decisiones te esperan"))
                    if piden == 0 {
                        VStack(spacing: 12) {
                            Image(systemName: "checkmark.seal").font(.system(size: 30, weight: .ultraLight)).foregroundStyle(TextoCentro.secundario)
                            Text("Cuando una sesión de Claude o un agente necesite tu sí, aparece aquí y se enciende.")
                                .font(.system(size: 12.5)).foregroundStyle(TextoCentro.secundario).multilineTextAlignment(.center)
                        }
                        .padding(.horizontal, 20)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        ForEach(ctx.esperando) { s in TarjetaSesion(s: s, ctx: ctx) }
                        ForEach(Array((o?.aprobaciones ?? []).enumerated()), id: \.offset) { i, t in
                            TarjetaAprobacion(t: t, primera: i == 0 && ctx.esperando.isEmpty)
                        }
                        Spacer(minLength: 0)
                    }
                }
            }
        } centro: {
            VentanaEspacio {
                VStack(alignment: .leading, spacing: 12) {
                    CabeceraVentana(titulo: "Ahora", detalle: ahora(o))
                    let tareas = o?.trabajando ?? []
                    if ctx.trabajando.isEmpty && tareas.isEmpty {
                        Text("Nadie trabajando en este momento.").font(.system(size: 12)).foregroundStyle(TextoCentro.terciario)
                    }
                    VStack(spacing: 0) {
                        ForEach(ctx.trabajando.prefix(3)) { s in TarjetaTrabajoSesion(s: s) }
                        ForEach(Array(tareas.enumerated()), id: \.offset) { _, t in FilaTareaCentro(t: t, hecha: false) }
                    }
                    if let c = o?.calendario, !c.filas.isEmpty {
                        SemanaAgentesCentro(c: c).frame(maxHeight: .infinity).padding(.top, 8)
                    } else {
                        Spacer(minLength: 0)
                    }
                }
            }
        } derecha: {
            VentanaEspacio {
                VStack(alignment: .leading, spacing: 10) {
                    let programado = o?.programado ?? []
                    let hecho = o?.hecho ?? []
                    CabeceraVentana(titulo: "Programado", detalle: programado.isEmpty ? "Nada por correr" : "Lo que corre en los próximos días")
                    VStack(spacing: 0) {
                        ForEach(Array(programado.prefix(4).enumerated()), id: \.offset) { _, t in FilaTareaCentro(t: t, hecha: false) }
                    }
                    Rotulo("Hecho hoy · \(hecho.count)", color: TextoCentro.terciario).padding(.top, 10)
                    if hecho.isEmpty {
                        Text("Nada todavía.").font(.system(size: 12)).foregroundStyle(TextoCentro.terciario)
                    }
                    VStack(spacing: 0) {
                        ForEach(Array(hecho.prefix(4).enumerated()), id: \.offset) { _, t in FilaTareaCentro(t: t, hecha: true) }
                    }
                    Spacer(minLength: 0)
                }
            }
        } debajo: {
            if let o, o.costoDisponible != false { GastoDebajoCentro(o: o) }
        }
    }

    private func ahora(_ o: EstadoCentro.Orquesta?) -> String {
        let n = ctx.trabajando.count + (o?.trabajando.count ?? 0)
        let h = o?.hecho.count ?? 0
        return (n == 1 ? "1 trabajando" : "\(n) trabajando") + " · " + (h == 1 ? "1 hecha hoy" : "\(h) hechas hoy")
    }
}

/// Debajo de Orquesta: lo que va costando Hermes hoy y en el mes, contra el presupuesto.
private struct GastoDebajoCentro: View {
    let o: EstadoCentro.Orquesta

    var body: some View {
        HStack(spacing: 18) {
            Cifra(numero: usd(o.costoHoy), unidad: "USD hoy", tamano: 26)
            Liquido(valor: o.presupuestoDia > 0 ? min(1, o.costoHoy / o.presupuestoDia) : 0, tono: .neutro, alto: 4).frame(width: 150)
            Text("de \(usd(o.presupuestoDia)) al día · el mes va en \(usd(o.costoMes)) de \(Int(o.presupuestoMes))")
                .font(.system(size: 12)).monospacedDigit().foregroundStyle(TextoCentro.secundario)
        }
        .padding(.horizontal, 26)
        .frame(maxHeight: .infinity)
        .fixedSize(horizontal: true, vertical: false)
        .ornamento(radio: 26)
    }
}

private struct InsigniaAgenteCentro: View {
    let tipo: String
    var lado: CGFloat = 22

    var body: some View {
        if tipo == "claude" {
            Insignia(icono: .estrella, tono: .claude, lado: lado)
        } else {
            Insignia(icono: .simbolo("antenna.radiowaves.left.and.right"), tono: .neutro, lado: lado)
        }
    }
}

/// Una sesión de Claude Code que espera tu respuesta: el botón abre justo esa sesión.
private struct TarjetaSesion: View {
    let s: SesionesClaude.Sesion
    let ctx: ContextoCentro

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                InsigniaAgenteCentro(tipo: "claude")
                Text("Claude Code").font(.system(size: 11, weight: .semibold)).foregroundStyle(TextoCentro.secundario)
                Spacer()
                Text(hace(s.desde)).font(.system(size: 11)).foregroundStyle(TextoCentro.terciario)
            }
            Text(s.nombre).font(.system(size: 13, weight: .semibold)).foregroundStyle(Halo.texto).lineLimit(2)
            Text(s.espera.isEmpty ? (s.actividad.isEmpty ? "Espera tu respuesta" : s.actividad) : s.espera)
                .font(.system(size: 11)).foregroundStyle(TextoCentro.terciario).lineLimit(2)
            BotonCentro(titulo: "Abrir la sesión", tipo: .principal) { ctx.abrirSesion(s) }
                .padding(.top, 2)
        }
        .padding(16)
        .levantado(radio: 18, tono: .claude)
    }
}

/// Una aprobación que pide un agente del VPS (en esta fase se responde en Telegram).
private struct TarjetaAprobacion: View {
    let t: EstadoCentro.Tarea
    let primera: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                InsigniaAgenteCentro(tipo: t.tipo)
                Text(t.agente).font(.system(size: 11, weight: .semibold)).foregroundStyle(TextoCentro.secundario)
                Spacer()
                Text(t.cuando ?? "").font(.system(size: 11)).foregroundStyle(TextoCentro.terciario)
            }
            Text(t.titulo).font(.system(size: 13, weight: .semibold)).foregroundStyle(Halo.texto)
                .fixedSize(horizontal: false, vertical: true)
            Text(t.detalle).font(.system(size: 11)).foregroundStyle(TextoCentro.terciario).lineLimit(2)
            Text("Respóndelo en Telegram").font(.system(size: 11, weight: .medium)).foregroundStyle(Tono.claude.claro)
        }
        .padding(16)
        .levantado(radio: 18)
    }
}

private struct TarjetaTrabajoSesion: View {
    let s: SesionesClaude.Sesion

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                InsigniaAgenteCentro(tipo: "claude", lado: 20)
                Text("Claude Code").font(.system(size: 11, weight: .semibold)).foregroundStyle(TextoCentro.secundario)
                Spacer()
                Text(hace(s.desde)).font(.system(size: 11)).foregroundStyle(TextoCentro.terciario)
            }
            Text(s.nombre).font(.system(size: 12.5, weight: .semibold)).foregroundStyle(Halo.texto).lineLimit(2)
            if !s.actividad.isEmpty {
                Text(s.actividad).font(.system(size: 11)).foregroundStyle(TextoCentro.terciario).lineLimit(1)
            }
        }
        .padding(.vertical, 11)
        .overlay(alignment: .bottom) { FiloCentro() }
    }
}

private struct FilaTareaCentro: View {
    let t: EstadoCentro.Tarea
    let hecha: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            if hecha {
                Image(systemName: t.detalle.hasPrefix("falló") ? "exclamationmark.triangle" : "checkmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(t.detalle.hasPrefix("falló") ? Tono.ambar.claro : TextoCentro.terciario)
                    .frame(width: 20, height: 20)
            } else {
                InsigniaAgenteCentro(tipo: t.tipo, lado: 20)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(t.titulo).font(.system(size: 12, weight: .semibold)).foregroundStyle(hecha ? TextoCentro.secundario : Halo.texto).lineLimit(1)
                Text(hecha || t.agente == "default" ? t.detalle : "\(t.agente) · \(t.detalle)")
                    .font(.system(size: 11)).foregroundStyle(TextoCentro.terciario).lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 4)
            if let c = t.cuando, !hecha {
                Text(c).font(.system(size: 11)).monospacedDigit().foregroundStyle(TextoCentro.terciario).fixedSize()
            }
        }
        .padding(.vertical, 10)
        .overlay(alignment: .bottom) { FiloCentro() }
    }
}

/// La semana de tus agentes: una fila por agente, un punto por corrida. Lo que ya corrió, encendido; lo que viene,
/// hueco; un aviso, en ámbar.
private struct SemanaAgentesCentro: View {
    let c: EstadoCentro.Calendario
    private let etiqueta: CGFloat = 132

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Rotulo("La semana de tus agentes", color: TextoCentro.terciario)
            GeometryReader { g in
                let ancho = (g.size.width - etiqueta) / CGFloat(max(1, c.dias.count))
                let alto = (g.size.height - 22) / CGFloat(max(1, c.filas.count))
                ZStack(alignment: .topLeading) {
                    ForEach(Array(c.dias.enumerated()), id: \.offset) { i, d in
                        Text(d).font(.system(size: 11, weight: i == 0 ? .semibold : .regular))
                            .foregroundStyle(i == 0 ? Halo.texto : TextoCentro.terciario)
                            .offset(x: etiqueta + CGFloat(i) * ancho + 4, y: 0)
                        Rectangle().fill(Halo.linea).frame(width: 0.5, height: max(0, g.size.height - 18))
                            .offset(x: etiqueta + CGFloat(i) * ancho, y: 18)
                    }
                    ForEach(Array(c.filas.enumerated()), id: \.offset) { f, fila in
                        filaVista(fila, y: 22 + CGFloat(f) * alto + alto / 2, ancho: ancho, total: g.size.width)
                    }
                    Rectangle().fill(.white.opacity(0.7)).frame(width: 1, height: max(0, g.size.height - 18))
                        .offset(x: etiqueta + CGFloat(c.ahora / 24) * ancho, y: 18)
                        .shadow(color: .white, radius: 2)
                }
            }
        }
    }

    @ViewBuilder private func filaVista(_ fila: EstadoCentro.Calendario.Fila, y: CGFloat, ancho: CGFloat, total: CGFloat) -> some View {
        HStack(spacing: 7) {
            InsigniaAgenteCentro(tipo: fila.tipo, lado: 14)
            Text(fila.nombre).font(.system(size: 11)).foregroundStyle(TextoCentro.secundario).lineLimit(1)
        }
        .frame(width: etiqueta - 8, alignment: .leading)
        .offset(y: y - 8)
        if fila.continuo {
            Capsule().fill(.white.opacity(0.08)).frame(width: max(0, total - etiqueta), height: 2)
                .offset(x: etiqueta, y: y - 1)
        }
        ForEach(Array(fila.corridas.enumerated()), id: \.offset) { _, r in
            if r.count == 2 {
                punto(r, fila: fila).frame(width: 6, height: 6)
                    .offset(x: etiqueta + CGFloat(r[0]) * ancho + CGFloat(r[1] / 24) * ancho - 3, y: y - 3)
            }
        }
    }

    @ViewBuilder private func punto(_ r: [Double], fila: EstadoCentro.Calendario.Fila) -> some View {
        let aviso = (c.avisos ?? []).contains { $0.count == 2 && $0[0] == r[0] && $0[1] == r[1] }
        let paso = r[0] == 0 && r[1] <= c.ahora
        if aviso {
            Circle().fill(Tono.ambar.base).shadow(color: Tono.ambar.base, radius: 3)
        } else if paso {
            Circle().fill(.white.opacity(0.9)).shadow(color: .white.opacity(0.6), radius: 2)
        } else {
            Circle().strokeBorder(.white.opacity(0.35), lineWidth: 0.75)
        }
    }
}

// MARK: - Inbox

/// Inbox: el resumen y la acción en bloque a la izquierda, tus capturas al frente y, a la derecha, la que elegiste
/// con lo que propone Claude (es la decisión: su borde se enciende).
private struct EscenaInboxCentro: View {
    let e: EstadoCentro
    let ctx: ContextoCentro
    @State private var elegida: String?
    @State private var confirmar = false

    private var items: [EstadoCentro.Propuesta] { e.inbox?.items ?? [] }
    private var actual: EstadoCentro.Propuesta? { items.first { $0.id == elegida } ?? items.first }
    private var archivables: [EstadoCentro.Propuesta] { items.filter { $0.accion == "archivar" && !ctx.aplicando.contains($0.id) } }

    var body: some View {
        EspacioCentro {
            VentanaEspacio { resumen }
        } centro: {
            VentanaEspacio(relleno: 0) { lista }
        } derecha: {
            if let p = actual {
                VentanaEspacio(tono: .claude) { DetalleCaptura(p: p, destinos: e.inbox?.destinos ?? [], ctx: ctx) }
            } else {
                VentanaEspacio { Vacio(texto: "Nada que decidir.") }
            }
        }
    }

    private var resumen: some View {
        VStack(alignment: .leading, spacing: 14) {
            CabeceraVentana(titulo: "Inbox", detalle: items.isEmpty ? "Al día" : "\(items.count) capturas por clasificar")
            VStack(spacing: 0) {
                ForEach(Array(Self.acciones.enumerated()), id: \.offset) { _, a in
                    let n = items.filter { $0.accion == a.clave }.count
                    if n > 0 {
                        HStack(spacing: 12) {
                            Image(systemName: a.icono).font(.system(size: 13)).foregroundStyle(TextoCentro.secundario).frame(width: 20)
                            Text(a.titulo).font(.system(size: 13.5)).foregroundStyle(Halo.texto)
                            Spacer()
                            Text("\(n)").font(.system(size: 13.5, weight: .medium)).monospacedDigit().foregroundStyle(Halo.texto)
                        }
                        .padding(.vertical, 11)
                        .overlay(alignment: .bottom) { FiloCentro() }
                    }
                }
            }
            Text("Claude propone un destino para cada captura. Nada se mueve sin tu sí: cada sí queda en el log y todo se recupera con git.")
                .font(.system(size: 12)).foregroundStyle(TextoCentro.secundario).lineSpacing(2).fixedSize(horizontal: false, vertical: true)
            if ctx.puedeActuar && archivables.count > 1 {
                if confirmar {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("¿Archivar \(archivables.count) capturas? Van a Archivo/inbox/ con git; nada se borra.")
                            .font(.system(size: 12.5)).foregroundStyle(Halo.texto).fixedSize(horizontal: false, vertical: true)
                        HStack(spacing: 8) {
                            BotonCentro(titulo: "Sí, archivar \(archivables.count)", tipo: .principal) {
                                for p in archivables { ctx.aplicarInbox(p.id, "archivar", nil) }
                                confirmar = false
                            }
                            BotonCentro(titulo: "Cancelar") { confirmar = false }
                        }
                    }
                    .padding(14)
                    .levantado(radio: 16, tono: .claude)
                } else {
                    BotonCentro(titulo: "Archivar las \(archivables.count) viejas", icono: "archivebox") { confirmar = true }
                }
            }
            if !ctx.puedeActuar {
                Text("Para aprobar desde aquí: defaults write app.dictado centro -dict-add acciones /ruta/a/accion.sh")
                    .font(.system(size: 11)).foregroundStyle(TextoCentro.terciario).textSelection(.enabled)
            }
            Spacer(minLength: 0)
        }
    }

    private var lista: some View {
        // En la ventana van todas (con scroll); en el render de maquetas, las primeras siete.
        let visibles = ctx.enVentana ? items : Array(items.prefix(7))
        let filas = VStack(spacing: 2) {
            ForEach(visibles, id: \.id) { p in
                FilaCapturaLista(p: p, elegida: p.id == actual?.id, ocupada: ctx.aplicando.contains(p.id)) { elegida = p.id }
            }
        }
        .padding(.horizontal, 12)
        return VStack(alignment: .leading, spacing: 10) {
            CabeceraVentana(titulo: "Lo que capturaste", detalle: items.isEmpty ? nil : "Elige una para ver qué propone Claude")
                .padding(.horizontal, 24).padding(.top, 24)
            if items.isEmpty {
                Vacio(texto: "Inbox al día. Lo que captures con ⌥⇧Espacio o por Telegram aparece aquí con su destino propuesto.")
                    .padding(24)
            } else if ctx.enVentana {
                ScrollView { filas.padding(.bottom, 12) }
            } else {
                filas   // el render de maquetas no dibuja el contenido de un ScrollView
                Spacer(minLength: 0)
            }
        }
    }

    private static let acciones: [(clave: String, titulo: String, icono: String)] = [
        ("archivar", "Archivar", "archivebox"), ("mover", "Mover a una carpeta", "folder"),
        ("tarea", "Volver tarea", "checklist"), ("destilar", "Destilar con Claude", "text.book.closed"),
    ]
}

private func iconoCaptura(_ p: EstadoCentro.Propuesta) -> String {
    if p.fuente == "hermes" { return "antenna.radiowaves.left.and.right" }
    switch p.tipo {
    case "tarea": return "checklist"
    case "nota": return "note.text"
    default: return "lightbulb"
    }
}

private func metaCaptura(_ p: EstadoCentro.Propuesta) -> String {
    var partes = [p.tipo]
    if !p.fuente.isEmpty && p.fuente != p.tipo { partes.append(p.fuente) }
    if let f = p.fecha, let d = EscenaMetasCentroFecha.dia(f) {
        let x = DateFormatter()
        x.locale = Locale(identifier: "es_CO")
        x.dateFormat = "d MMM yyyy"
        partes.append(x.string(from: d).replacingOccurrences(of: ".", with: ""))
    }
    return partes.joined(separator: " · ")
}

private func propuestaCaptura(_ p: EstadoCentro.Propuesta) -> (simbolo: String, texto: String) {
    switch p.accion {
    case "archivar": return ("archivebox", "Archivar")
    case "mover": return ("folder", "Mover a \(p.destino ?? "")")
    case "tarea": return ("checklist", "Volver tarea")
    default: return ("text.book.closed", "Destilar con Claude")
    }
}

private struct FilaCapturaLista: View {
    let p: EstadoCentro.Propuesta
    let elegida: Bool
    let ocupada: Bool
    let accion: () -> Void
    @State private var encima = false

    var body: some View {
        Button(action: accion) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: iconoCaptura(p)).font(.system(size: 12, weight: .medium)).foregroundStyle(TextoCentro.secundario)
                    .frame(width: 28, height: 28).background(Circle().fill(.white.opacity(0.06)))
                VStack(alignment: .leading, spacing: 3) {
                    Text(p.titulo).font(.system(size: 13.5, weight: .semibold)).foregroundStyle(Halo.texto).lineLimit(2)
                        .multilineTextAlignment(.leading)
                    HStack(spacing: 5) {
                        Text(metaCaptura(p)).foregroundStyle(TextoCentro.terciario)
                        Text("·").foregroundStyle(TextoCentro.terciario)
                        Text(propuestaCaptura(p).texto).fontWeight(.semibold).foregroundStyle(TextoCentro.secundario)
                    }
                    .font(.system(size: 11)).lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12).padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                let forma = RoundedRectangle(cornerRadius: 14, style: .continuous)
                if elegida {
                    forma.fill(.white.opacity(0.12)).overlay(forma.strokeBorder(.white.opacity(0.16), lineWidth: 0.75))
                } else if encima {
                    forma.fill(.white.opacity(0.05))
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { encima = $0 }
        .opacity(ocupada ? 0.5 : 1)
        .accessibilityAddTraits(elegida ? .isSelected : [])
    }
}

/// La captura elegida: qué es, qué propone Claude y por qué, y los botones para decidir.
private struct DetalleCaptura: View {
    let p: EstadoCentro.Propuesta
    let destinos: [String]
    let ctx: ContextoCentro

    var body: some View {
        let ocupado = ctx.aplicando.contains(p.id)
        let (simbolo, texto) = propuestaCaptura(p)
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: iconoCaptura(p)).font(.system(size: 12, weight: .medium)).foregroundStyle(TextoCentro.secundario)
                    .frame(width: 30, height: 30).background(Circle().fill(.white.opacity(0.08)))
                Text(metaCaptura(p)).font(.system(size: 11.5)).foregroundStyle(TextoCentro.terciario).lineLimit(1)
            }
            Text(p.titulo).font(.system(size: 19)).foregroundStyle(Halo.texto).lineSpacing(2).lineLimit(4)
                .fixedSize(horizontal: false, vertical: true)
            if !p.extracto.isEmpty {
                Text(p.extracto).font(.system(size: 12.5)).foregroundStyle(TextoCentro.secundario).lineSpacing(3).lineLimit(8)
            }
            FiloCentro().padding(.top, 6)
            VStack(alignment: .leading, spacing: 7) {
                Rotulo("Claude propone", color: Tono.claude.claro)
                HStack(spacing: 8) {
                    Image(systemName: simbolo).font(.system(size: 14, weight: .semibold))
                    Text(texto).font(.system(size: 16, weight: .semibold)).lineLimit(1)
                }
                .foregroundStyle(Halo.texto)
                if !p.razon.isEmpty {
                    Text(p.razon).font(.system(size: 12)).foregroundStyle(TextoCentro.secundario).fixedSize(horizontal: false, vertical: true)
                }
            }
            HStack(spacing: 8) { botones(ocupado) }.padding(.top, 4)
            if let f = ctx.fallos[p.id] {
                Text(f).font(.system(size: 11.5, weight: .medium)).foregroundStyle(Tono.rojo.claro).lineLimit(2)
            }
            Spacer(minLength: 0)
        }
        .opacity(ocupado ? 0.6 : 1)
    }

    @ViewBuilder private func botones(_ ocupado: Bool) -> some View {
        if p.accion == "destilar" {
            BotonCentro(titulo: "Copiar el pedido para Claude", icono: "doc.on.doc", tipo: .principal) {
                ctx.copiar("Destila \(p.id) a la wiki (las páginas que toque) y luego archívalo.")
            }
        } else if ctx.puedeActuar {
            BotonCentro(titulo: ocupado ? "Aplicando…" : "Aprobar", icono: "checkmark", tipo: .principal) {
                ctx.aplicarInbox(p.id, p.accion, p.destino)
            }
            .disabled(ocupado)
        }
        if ctx.puedeActuar && !ctx.enVentana {
            chip("Otro destino")   // el render no dibuja menús
        } else if ctx.puedeActuar {
            Menu {
                Button("Archivar") { ctx.aplicarInbox(p.id, "archivar", nil) }
                Menu("Mover a") {
                    ForEach(destinos, id: \.self) { d in Button(d) { ctx.aplicarInbox(p.id, "mover", d) } }
                }
                Button("Volver tarea") { ctx.aplicarInbox(p.id, "tarea", p.titulo) }
            } label: {
                chip("Otro destino")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .disabled(ocupado)
        }
    }

    private func chip(_ t: String) -> some View {
        HStack(spacing: 5) {
            Text(t).font(.system(size: 12.5, weight: .semibold))
            Image(systemName: "chevron.down").font(.system(size: 8, weight: .bold)).opacity(0.7)
        }
        .foregroundStyle(Halo.texto)
        .padding(.horizontal, 13).frame(height: 28)
        .background(Capsule().fill(.white.opacity(0.08)))
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.13), lineWidth: 0.75))
    }
}

/// "2026-03-09" → Date (para las fechas del inbox).
private enum EscenaMetasCentroFecha {
    static func dia(_ iso: String) -> Date? {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.date(from: iso)
    }
}
