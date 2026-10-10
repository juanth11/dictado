import AppKit
import SwiftUI

// Las vistas del centro de mando (Hoy, Metas, Orquesta). Las usan la ventana real (CentroVentana.swift) y el render
// de maquetas (`--vista-centro2`, `--vista-centro-real`). Solo pintan el estado: no calculan nada ni guardan nada.
// Fase 2 = solo lectura: las acciones que hay abren cosas (el tablero de finanzas, una noticia, el archivo de metas,
// una sesión de Claude) o piden una lectura fresca. Aprobar y delegar llegan después.

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

// MARK: - Raíz

struct VistaCentro: View {
    let estado: EstadoCentro?
    let ctx: ContextoCentro
    @Binding var seccion: SeccionCentro

    var body: some View {
        HStack(spacing: 0) {
            BarraCentro(estado: estado, ctx: ctx, seccion: $seccion)
                .frame(width: 224)
            Rectangle().fill(Halo.linea).frame(width: 1)
            VStack(spacing: 0) {
                BarraSuperiorCentro(estado: estado, ctx: ctx, seccion: seccion)
                    .frame(height: 60)
                Rectangle().fill(Halo.linea).frame(height: 1)
                if let error = ctx.error, ctx.configurado { AvisoCentro(texto: error, accion: ctx.actualizar) }
                contenido
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
    }

    @ViewBuilder private var contenido: some View {
        if !ctx.configurado {
            SinConfigurar()
        } else if let estado {
            switch seccion {
            case .hoy: EscenaHoyCentro(e: estado, ctx: ctx)
            case .metas:
                if let m = estado.metas { EscenaMetasCentro(metas: m, ctx: ctx) } else { Vacio(texto: "Aún no hay metas publicadas.") }
            case .orquesta: EscenaOrquestaCentro(e: estado, ctx: ctx)
            case .inbox: EscenaInboxCentro(e: estado, ctx: ctx)
            }
        } else if ctx.cargando {
            Vacio(texto: "Leyendo el estado del día…")
        } else {
            Vacio(texto: ctx.error ?? "Sin datos todavía.")
        }
    }
}

/// Si el VPS no respondió: una línea, lo último que se supo sigue a la vista y se puede reintentar.
private struct AvisoCentro: View {
    let texto: String
    let accion: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 11)).foregroundStyle(Tono.ambar.claro)
            Text(texto).font(.system(size: 12)).foregroundStyle(Halo.texto).lineLimit(1)
            Spacer()
            BotonCentro(titulo: "Reintentar", icono: "arrow.clockwise", tipo: .enlace, accion: accion)
        }
        .padding(.horizontal, 28).frame(height: 38)
        .background(Tono.ambar.base.opacity(0.12))
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

// MARK: - Barras

private struct BarraCentro: View {
    let estado: EstadoCentro?
    let ctx: ContextoCentro
    @Binding var seccion: SeccionCentro

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                ZStack {
                    Circle().fill(RadialGradient(colors: [.white.opacity(0.9), Tono.azul.base.opacity(0.4), .clear], center: .center,
                                                 startRadius: 0, endRadius: 14))
                    Circle().strokeBorder(.white.opacity(0.4), lineWidth: 0.75)
                }
                .frame(width: 26, height: 26)
                VStack(alignment: .leading, spacing: 0) {
                    Text("Centro de mando").font(.system(size: 13.5, weight: .semibold)).foregroundStyle(Halo.texto)
                    Text(estado?.brief?.fecha ?? "—").font(.system(size: 11)).foregroundStyle(TextoCentro.terciario)
                }
            }
            .padding(.horizontal, 20).padding(.top, ctx.enVentana ? 46 : 22).padding(.bottom, 24)
            Rotulo("Espacio", color: TextoCentro.terciario).padding(.horizontal, 22).padding(.bottom, 6)
            ForEach(SeccionCentro.allCases, id: \.self) { s in
                FilaNavCentro(seccion: s, activa: s == seccion, cuenta: cuenta(s), aviso: s == .orquesta) { seccion = s }
            }
            if let modulos = estado?.modulos, !modulos.isEmpty {
                Rotulo("Módulos", color: TextoCentro.terciario).padding(.horizontal, 22).padding(.top, 18).padding(.bottom, 6)
                ForEach(modulos, id: \.nombre) { m in
                    FilaModuloCentro(m: m) { if let a = m.abrir { ctx.abrir(a) } }
                }
            }
            Spacer()
            EstadoConexion(estado: estado, ctx: ctx)
                .padding(.horizontal, 22).padding(.bottom, 18)
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Color.black.opacity(0.08))
    }

    private func cuenta(_ s: SeccionCentro) -> Int {
        switch s {
        case .orquesta: return (estado?.orquesta?.aprobaciones.count ?? 0) + ctx.esperando.count
        case .inbox: return estado?.inbox?.items.count ?? 0
        default: return 0
        }
    }
}

private struct FilaNavCentro: View {
    let seccion: SeccionCentro
    let activa: Bool
    let cuenta: Int
    let aviso: Bool
    let accion: () -> Void
    @State private var encima = false

    var body: some View {
        Button(action: accion) {
            HStack(spacing: 11) {
                Image(systemName: seccion.simbolo).font(.system(size: 12.5, weight: .medium)).frame(width: 18)
                Text(seccion.titulo).font(.system(size: 13, weight: activa ? .semibold : .regular))
                Spacer()
                if cuenta > 0 {
                    if aviso { PuntoBrillante(color: Tono.claude.base, lado: 5) }
                    Text("\(cuenta)").font(.system(size: 11, weight: .semibold)).monospacedDigit()
                        .padding(.horizontal, 7).frame(height: 18).background(Capsule().fill(.white.opacity(0.1)))
                }
            }
            .foregroundStyle(activa || encima ? Halo.texto : TextoCentro.secundario)
            .padding(.horizontal, 12).frame(height: 34)
            .contentShape(Rectangle())
            .background {
                let forma = RoundedRectangle(cornerRadius: 11, style: .continuous)
                if activa {
                    forma.fill(Color.white.opacity(0.12))
                        .overlay(forma.strokeBorder(Color.white.opacity(0.16), lineWidth: 0.75))
                        .shadow(color: .black.opacity(0.22), radius: 8, y: 4)
                } else if encima {
                    forma.fill(Color.white.opacity(0.05))
                }
            }
        }
        .buttonStyle(.plain)
        .onHover { encima = $0 }
        .padding(.horizontal, 10)
    }
}

private struct FilaModuloCentro: View {
    let m: EstadoCentro.Modulo
    let accion: () -> Void
    @State private var encima = false

    var body: some View {
        Button(action: accion) {
            HStack(spacing: 9) {
                Circle().fill(colorVertical(m.nombre)).frame(width: 6, height: 6).frame(width: 18)
                Text(m.nombre).font(.system(size: 12.5)).foregroundStyle(encima ? Halo.texto : TextoCentro.secundario)
                    .lineLimit(1).fixedSize()
                Spacer(minLength: 6)
                Text(m.valor).font(.system(size: 11)).monospacedDigit().foregroundStyle(TextoCentro.terciario)
                    .lineLimit(1).minimumScaleFactor(0.8)
                if m.abrir != nil {
                    Image(systemName: "arrow.up.right").font(.system(size: 8.5, weight: .semibold))
                        .foregroundStyle(encima ? Halo.texto : TextoCentro.terciario)
                }
            }
            .padding(.horizontal, 12).frame(height: 30)
            .contentShape(Rectangle())
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white.opacity(encima ? 0.05 : 0)))
        }
        .buttonStyle(.plain)
        .disabled(m.abrir == nil)
        .onHover { encima = $0 }
        .padding(.horizontal, 10)
    }
}

private struct EstadoConexion: View {
    let estado: EstadoCentro?
    let ctx: ContextoCentro

    var body: some View {
        let rotas = (estado?.salud?.capacidades ?? []).filter { $0.estado == "rota" || $0.estado == "alerta" }
        let color: Color = (estado?.vps == false || ctx.error != nil) ? Tono.rojo.base
            : (rotas.isEmpty ? Tono.verde.base : Tono.ambar.base)
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                PuntoBrillante(color: color, lado: 6)
                Text(titulo(rotas)).font(.system(size: 11, weight: .medium)).foregroundStyle(TextoCentro.secundario).lineLimit(1)
            }
            if let leido = ctx.leido {
                Text("Leído \(hace(leido))").font(.system(size: 11)).foregroundStyle(TextoCentro.terciario).padding(.leading, 14)
            }
        }
    }

    private func titulo(_ rotas: [EstadoCentro.Capacidad]) -> String {
        if estado?.vps == false || ctx.error != nil { return "Sin conexión con el VPS" }
        if let r = rotas.first { return "\(r.nombre): \(r.estado)" }
        return "VPS bien · todo vivo"
    }
}

private struct BarraSuperiorCentro: View {
    let estado: EstadoCentro?
    let ctx: ContextoCentro
    let seccion: SeccionCentro

    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 6) {
                Text("Centro de mando").foregroundStyle(TextoCentro.terciario)
                Image(systemName: "chevron.right").font(.system(size: 9, weight: .bold)).foregroundStyle(TextoCentro.terciario)
                Text(seccion.titulo).foregroundStyle(Halo.texto)
            }
            .font(.system(size: 14, weight: .semibold))
            Spacer()
            if !ctx.sesiones.isEmpty {
                chip("\(ctx.sesiones.count) sesiones de Claude", ctx.esperando.isEmpty ? Tono.claude.base.opacity(0.6) : Tono.claude.base)
            }
            if let o = estado?.orquesta {
                chip(o.hermesConectado == false ? "Hermes sin datos" : "Hermes · VPS",
                     o.hermesConectado == false ? Tono.ambar.base : Tono.verde.base)
            }
            BotonCentro(titulo: ctx.cargando ? "Actualizando…" : "Actualizar", icono: "arrow.clockwise", accion: ctx.actualizar)
                .disabled(ctx.cargando)
        }
        .padding(.horizontal, 24)
    }

    private func chip(_ t: String, _ c: Color) -> some View {
        HStack(spacing: 6) {
            PuntoBrillante(color: c, lado: 6)
            Text(t).font(.system(size: 11.5, weight: .medium)).foregroundStyle(TextoCentro.secundario)
        }
        .padding(.horizontal, 10).frame(height: 28)
        .background(Capsule().fill(.white.opacity(0.05)))
    }
}

// MARK: - Hoy

private struct EscenaHoyCentro: View {
    let e: EstadoCentro
    let ctx: ContextoCentro

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let b = e.brief {
                CabeceraBriefCentro(b: b).frame(height: 84)
            }
            FichasCentro(e: e, ctx: ctx)
            HStack(alignment: .top, spacing: 16) {
                if let b = e.brief {
                    TarjetaBriefCentro(b: b).fixedSize(horizontal: false, vertical: true)
                } else {
                    Vacio(texto: "El brief de hoy todavía no se ha generado: sale a las 5:30 en tu VPS.").superficie(radio: 20)
                }
                VStack(spacing: 16) {
                    if let f = e.finanzas { TarjetaFinanzasCentro(f: f, ctx: ctx).fixedSize(horizontal: false, vertical: true) }
                    if let n = e.noticias, !n.items.isEmpty { TarjetaRadarCentro(items: Array(n.items.prefix(3)), ctx: ctx) }
                }
                .frame(width: 400)
            }
            .frame(maxHeight: .infinity)
            if let m = e.metas { FranjaMetasCentro(m: m).frame(height: 112) }
        }
        .padding(.horizontal, 28).padding(.vertical, 22)
    }
}

private struct CabeceraBriefCentro: View {
    let b: EstadoCentro.Brief

    var body: some View {
        HStack(alignment: .center, spacing: 28) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 10) {
                    Rotulo("\(b.fecha) · semana \(b.semana)", color: TextoCentro.terciario)
                    if !esHoy(b.fechaIso) {
                        Text("Es de otro día: el brief de hoy aún no sale").font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Tono.ambar.claro).padding(.horizontal, 8).frame(height: 20)
                            .background(Capsule().fill(Tono.ambar.base.opacity(0.14)))
                    }
                }
                Text("Tu brief del día").font(.system(size: 34, weight: .thin)).foregroundStyle(Halo.texto)
                HStack(spacing: 6) {
                    EstrellaClaude().fill(Tono.claude.claro).frame(width: 10, height: 10)
                    Text(generado).font(.system(size: 11.5)).foregroundStyle(TextoCentro.terciario).lineLimit(1)
                }
            }
            Spacer()
            if let c = b.clima {
                Rectangle().fill(Halo.linea).frame(width: 1, height: 64)
                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 2) {
                        Rotulo(c.ciudad, color: TextoCentro.terciario)
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text("\(c.temp)°").font(.system(size: 34, weight: .thin)).foregroundStyle(Halo.texto)
                            Text(c.cielo).font(.system(size: 12, weight: .medium)).foregroundStyle(TextoCentro.secundario)
                        }
                        Text(detalleClima(c)).font(.system(size: 11)).foregroundStyle(TextoCentro.terciario)
                    }
                    Image(systemName: c.simbolo).font(.system(size: 26, weight: .ultraLight)).foregroundStyle(TextoCentro.secundario)
                }
            }
        }
    }

    private var generado: String {
        var partes = ["Generado por \(b.modelo)"]
        if let h = horaCorta(b.generado) { partes.append(h) }
        if let f = b.fuentes { partes.append("\(f) fuentes") }
        return partes.joined(separator: " · ")
    }

    private func detalleClima(_ c: EstadoCentro.Brief.Clima) -> String {
        var t = "Máx \(c.max)° · mín \(c.min)°"
        if b.agendaLeida == true { t += (b.agenda ?? []).isEmpty ? " · sin reuniones" : " · \((b.agenda ?? []).count) en agenda" }
        return t
    }
}

private struct FichasCentro: View {
    let e: EstadoCentro
    let ctx: ContextoCentro

    var body: some View {
        HStack(spacing: 8) {
            let piden = (e.orquesta?.aprobaciones.count ?? 0) + ctx.esperando.count
            ficha("checkmark.seal", piden == 1 ? "1 pide tu sí" : "\(piden) piden tu sí", punto: piden > 0 ? Tono.claude.base : nil)
            if let l = e.local { ficha("tray", "\(l.inbox) en el inbox", punto: nil) }
            if e.brief?.agendaLeida == true {
                let n = e.brief?.agenda?.count ?? 0
                ficha("calendar", n == 0 ? "Agenda libre" : "\(n) en la agenda", punto: nil)
            }
            ficha("sparkles", "\(ctx.trabajando.count) agentes trabajando", punto: nil)
            Spacer()
        }
        .frame(height: 30)
    }

    private func ficha(_ icono: String, _ t: String, punto: Color?) -> some View {
        HStack(spacing: 7) {
            if let punto { PuntoBrillante(color: punto, lado: 5) }
            Image(systemName: icono).font(.system(size: 11, weight: .medium))
            Text(t).font(.system(size: 11.5, weight: .medium))
        }
        .foregroundStyle(TextoCentro.secundario)
        .padding(.horizontal, 12).frame(height: 28)
        .background(Capsule().fill(.white.opacity(0.05)))
        .overlay(Capsule().strokeBorder(.white.opacity(0.07), lineWidth: 0.75))
    }
}

private struct TarjetaBriefCentro: View {
    let b: EstadoCentro.Brief

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Rotulo("El foco", color: Tono.ambar.claro)
            Text(b.foco.titulo).font(.system(size: 19)).foregroundStyle(Halo.texto)
                .lineSpacing(2).fixedSize(horizontal: false, vertical: true).padding(.top, 10)
            Text(b.foco.porque).font(.system(size: 12.5)).foregroundStyle(TextoCentro.secundario)
                .lineSpacing(3).fixedSize(horizontal: false, vertical: true).padding(.top, 8)
                .frame(maxWidth: 640, alignment: .leading)
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
            .padding(.top, 10)
            if !b.buenoSaber.isEmpty {
                Rotulo("Bueno saber", color: TextoCentro.terciario).padding(.top, 20)
                VStack(alignment: .leading, spacing: 7) {
                    ForEach(Array(b.buenoSaber.prefix(3).enumerated()), id: \.offset) { _, t in
                        HStack(alignment: .top, spacing: 9) {
                            Circle().fill(.white.opacity(0.4)).frame(width: 3, height: 3).padding(.top, 7)
                            Text(t).font(.system(size: 12)).foregroundStyle(TextoCentro.secundario)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .padding(.top, 9)
                .frame(maxWidth: 680, alignment: .leading)
            }
            Spacer(minLength: 0)
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .levantado(radio: 22, tono: .ambar)
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

/// Finanzas en resumen, sin cifra de vitrina: lo que importa en una lista corta y el colchón como regla de marcas.
/// El detalle vive en el tablero real (el enlace).
private struct TarjetaFinanzasCentro: View {
    let f: EstadoCentro.Finanzas
    let ctx: ContextoCentro

    var body: some View {
        let derecha: AnyView? = f.enlace.map { e in AnyView(enlace("Abrir el tablero") { ctx.abrir(e) }) }
        let piso = f.colchonPiso > 0 ? min(1, f.colchon / f.colchonPiso) : 0
        TarjetaCentro(rotulo: "Finanzas", derecha: derecha) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("Patrimonio neto").font(.system(size: 12)).foregroundStyle(TextoCentro.secundario)
                    Spacer()
                    Text(millonesCOP(f.patrimonio)).font(.system(size: 20, weight: .light)).monospacedDigit().foregroundStyle(Halo.texto)
                    Text(millonesCOP(f.delta, signo: true)).font(.system(size: 11, weight: .semibold)).monospacedDigit()
                        .foregroundStyle(f.delta >= 0 ? Tono.verde.claro : Tono.rojo.claro)
                }
                fila("Liquidez", millonesCOP(f.liquidez))
                fila("Neto del mes", millonesCOP(f.netoMes, signo: true))
                HStack(spacing: 10) {
                    Text("Colchón").font(.system(size: 12)).foregroundStyle(TextoCentro.secundario)
                    Regla(valor: piso, tono: .neutro, cuantas: 30, alto: 9, grosor: 1)
                    Text("\(Int((piso * 100).rounded())) % del piso").font(.system(size: 11.5, weight: .medium)).monospacedDigit()
                        .foregroundStyle(Halo.texto).fixedSize()
                }
                FiloCentro().padding(.vertical, 2)
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
    }

    private func fila(_ r: String, _ v: String) -> some View {
        HStack {
            Text(r).font(.system(size: 12)).foregroundStyle(TextoCentro.secundario)
            Spacer()
            Text(v).font(.system(size: 12.5, weight: .medium)).monospacedDigit().foregroundStyle(Halo.texto)
        }
    }
}

private struct TarjetaRadarCentro: View {
    let items: [EstadoCentro.Noticia]
    let ctx: ContextoCentro

    var body: some View {
        TarjetaCentro(rotulo: "En tu radar") {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, x in
                    Button { if let u = x.url { ctx.abrir(u) } } label: {
                        fila(x).padding(.vertical, 4).padding(.horizontal, 6).modifier(EncimaCentro(radio: 10))
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, -6)
                }
            }
        }
    }

    private func fila(_ x: EstadoCentro.Noticia) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Circle().fill(colorVertical(x.vertical)).frame(width: 6, height: 6).padding(.top, 5)
            VStack(alignment: .leading, spacing: 2) {
                Text(x.titulo).font(.system(size: 12, weight: .semibold)).foregroundStyle(Halo.texto).lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                if !x.porQue.isEmpty {
                    Text(x.porQue).font(.system(size: 11)).foregroundStyle(TextoCentro.secundario).lineLimit(1)
                }
                Text("\(x.vertical) · \(x.fuente) · \(x.fecha)").font(.system(size: 10.5)).foregroundStyle(TextoCentro.terciario).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
    }
}

private struct FranjaMetasCentro: View {
    let m: EstadoCentro.Metas

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array([m.semana, m.mes, m.trimestre].enumerated()), id: \.offset) { i, h in
                if i > 0 { Rectangle().fill(Halo.linea).frame(width: 0.75).padding(.vertical, 16) }
                columna(h)
            }
        }
        .superficie(radio: 18)
    }

    private func columna(_ h: EstadoCentro.Horizonte) -> some View {
        let hechas = h.metas.filter { $0.estado == "hecha" }.count
        let principal = h.metas.first { $0.estado != "hecha" } ?? h.metas.first
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Rotulo(h.nombre, color: TextoCentro.terciario)
                Spacer()
                Text("\(hechas) de \(h.metas.count)").font(.system(size: 11)).monospacedDigit().foregroundStyle(TextoCentro.terciario)
            }
            Text(principal?.texto ?? (h.vigente == false ? "Define las metas de esta semana" : "—"))
                .font(.system(size: 13.5, weight: .semibold)).foregroundStyle(Halo.texto).lineLimit(1)
            HStack(spacing: 10) {
                Regla(valor: h.tiempo, tono: .neutro, cuantas: 34, alto: 9, grosor: 1)
                Text("\(Int((h.tiempo * 100).rounded())) % del tiempo").font(.system(size: 11)).monospacedDigit()
                    .foregroundStyle(TextoCentro.terciario).fixedSize()
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

// MARK: - Metas

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
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 6) {
                    Rotulo(metas.borrador == true ? "Metas · borrador para que decidas" : "Metas", color: TextoCentro.terciario)
                    Text("¿Hacia dónde vas?").font(.system(size: 34, weight: .thin)).foregroundStyle(Halo.texto)
                    Text("Elige un resultado y dale una fecha. Las prioridades de cada mañana salen de aquí.")
                        .font(.system(size: 13)).foregroundStyle(TextoCentro.secundario)
                }
                Spacer()
                if let a = metas.archivo {
                    BotonCentro(titulo: "Editar metas", icono: "square.and.pencil", tipo: .principal) { ctx.abrir(a) }
                }
            }
            ReglaTrimestreCentro(t: metas.trimestre, hitos: metas.hitos ?? []).frame(height: 46)
            HStack(alignment: .top, spacing: 0) {
                TarjetaHorizonteCentro(h: metas.semana, dibujo: .semana, hito: hito, archivo: metas.archivo, ctx: ctx)
                Rectangle().fill(Halo.linea).frame(width: 0.75).padding(.vertical, 24)
                TarjetaHorizonteCentro(h: metas.mes, dibujo: .mes, hito: hito, archivo: metas.archivo, ctx: ctx)
                Rectangle().fill(Halo.linea).frame(width: 0.75).padding(.vertical, 24)
                TarjetaHorizonteCentro(h: metas.trimestre, dibujo: .trimestre, hito: hito, archivo: metas.archivo, ctx: ctx)
            }
            .superficie(radio: 22)
        }
        .padding(.horizontal, 28).padding(.vertical, 22)
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
    let archivo: String?
    let ctx: ContextoCentro

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
            if let archivo {
                BotonCentro(titulo: "Editar en \(archivo)", icono: "arrow.up.right", tipo: .enlace) { ctx.abrir(archivo) }
                    .padding(.horizontal, 22).padding(.bottom, 20)
            }
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
            RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color(white: 0.23))
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

private struct EscenaOrquestaCentro: View {
    let e: EstadoCentro
    let ctx: ContextoCentro

    var body: some View {
        let o = e.orquesta
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 6) {
                    Rotulo("Orquesta", color: TextoCentro.terciario)
                    Text("Tus agentes").font(.system(size: 34, weight: .thin)).foregroundStyle(Halo.texto)
                    Text("Claude Code en el Mac y Hermes en el VPS. Nada sale ni se mueve sin tu sí.")
                        .font(.system(size: 13)).foregroundStyle(TextoCentro.secundario)
                }
                Spacer()
                if let o, o.costoDisponible != false { GastoCentro(o: o) }
            }
            HStack(alignment: .top, spacing: 14) {
                ColumnaCentro(titulo: "Piden tu sí", cuenta: (o?.aprobaciones.count ?? 0) + ctx.esperando.count, tono: .claude,
                              vacio: "Nada pide tu sí ahora. Cuando una sesión de Claude o un agente necesite una decisión, aparece aquí.") {
                    ForEach(ctx.esperando) { s in TarjetaSesion(s: s, ctx: ctx) }
                    ForEach(Array((o?.aprobaciones ?? []).enumerated()), id: \.offset) { i, t in
                        TarjetaAprobacion(t: t, primera: i == 0 && ctx.esperando.isEmpty)
                    }
                }
                .frame(width: 330)
                VStack(alignment: .leading, spacing: 18) {
                    HStack(alignment: .top, spacing: 22) {
                        ColumnaCentro(titulo: "Trabajando", cuenta: ctx.trabajando.count + (o?.trabajando.count ?? 0),
                                      vacio: "Nadie trabajando.") {
                            ForEach(ctx.trabajando.prefix(4)) { s in TarjetaTrabajoSesion(s: s) }
                            ForEach(Array((o?.trabajando ?? []).enumerated()), id: \.offset) { _, t in FilaTareaCentro(t: t, hecha: false) }
                        }
                        ColumnaCentro(titulo: "Programado", cuenta: o?.programado.count ?? 0, vacio: "Nada programado.") {
                            ForEach(Array((o?.programado ?? []).prefix(5).enumerated()), id: \.offset) { _, t in FilaTareaCentro(t: t, hecha: false) }
                        }
                        ColumnaCentro(titulo: "Hecho hoy", cuenta: o?.hecho.count ?? 0, vacio: "Nada todavía.") {
                            ForEach(Array((o?.hecho ?? []).prefix(5).enumerated()), id: \.offset) { _, t in FilaTareaCentro(t: t, hecha: true) }
                        }
                    }
                    .padding(18)
                    .superficie(radio: 18)
                    if let c = o?.calendario, !c.filas.isEmpty { SemanaAgentesCentro(c: c).frame(minHeight: 220) }
                }
            }
            .frame(maxHeight: .infinity, alignment: .top)
        }
        .padding(.horizontal, 28).padding(.vertical, 22)
    }
}

private struct GastoCentro: View {
    let o: EstadoCentro.Orquesta

    var body: some View {
        VStack(alignment: .trailing, spacing: 6) {
            Cifra(numero: String(format: "%.2f", o.costoHoy).replacingOccurrences(of: ".", with: ","), unidad: "USD hoy", tamano: 30)
            Liquido(valor: o.presupuestoDia > 0 ? min(1, o.costoHoy / o.presupuestoDia) : 0, tono: .neutro, alto: 4).frame(width: 200)
            Text("de \(String(format: "%.2f", o.presupuestoDia).replacingOccurrences(of: ".", with: ",")) al día · el mes va en "
                 + "\(String(format: "%.2f", o.costoMes).replacingOccurrences(of: ".", with: ",")) de \(Int(o.presupuestoMes))")
                .font(.system(size: 11)).monospacedDigit().foregroundStyle(TextoCentro.terciario)
        }
    }
}

private struct ColumnaCentro<C: View>: View {
    let titulo: String
    let cuenta: Int
    var tono: Tono?
    let vacio: String
    @ViewBuilder let contenido: () -> C

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Rotulo(titulo, color: cuenta > 0 ? (tono?.claro ?? TextoCentro.terciario) : TextoCentro.terciario)
                Text("\(cuenta)").font(.system(size: 11, weight: .semibold)).monospacedDigit().foregroundStyle(TextoCentro.secundario)
                    .padding(.horizontal, 6).frame(height: 16).background(Capsule().fill(.white.opacity(0.08)))
                Spacer()
            }
            .frame(height: 18)
            if cuenta == 0 {
                Text(vacio).font(.system(size: 11.5)).foregroundStyle(TextoCentro.terciario).padding(.top, 2)
            }
            contenido()
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
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
        TarjetaCentro(rotulo: "La semana de tus agentes") {
            GeometryReader { g in
                let ancho = (g.size.width - etiqueta) / CGFloat(max(1, c.dias.count))
                let alto = (g.size.height - 22) / CGFloat(max(1, c.filas.count))
                ZStack(alignment: .topLeading) {
                    ForEach(Array(c.dias.enumerated()), id: \.offset) { i, d in
                        Text(d).font(.system(size: 10.5, weight: i == 0 ? .semibold : .regular))
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

private struct EscenaInboxCentro: View {
    let e: EstadoCentro
    let ctx: ContextoCentro
    @State private var confirmar = false

    private var items: [EstadoCentro.Propuesta] { e.inbox?.items ?? [] }
    private var archivables: [EstadoCentro.Propuesta] { items.filter { $0.accion == "archivar" && !ctx.aplicando.contains($0.id) } }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 6) {
                    Rotulo("Inbox", color: TextoCentro.terciario)
                    Text("Lo que capturaste").font(.system(size: 34, weight: .thin)).foregroundStyle(Halo.texto)
                    Text(resumen).font(.system(size: 13)).foregroundStyle(TextoCentro.secundario)
                }
                Spacer()
                if ctx.puedeActuar && archivables.count > 1 {
                    BotonCentro(titulo: "Archivar las \(archivables.count) viejas", icono: "archivebox", tipo: .principal) { confirmar = true }
                    .confirmationDialog("¿Archivar \(archivables.count) capturas?", isPresented: $confirmar) {
                        Button("Archivar \(archivables.count)") { for p in archivables { ctx.aplicarInbox(p.id, "archivar", nil) } }
                        Button("Cancelar", role: .cancel) {}
                    } message: {
                        Text("Se mueven a Archivo/inbox/ con git: nada se borra y todo se puede recuperar. Cada una deja su línea CONFIRMADO en el log.")
                    }
                }
            }
            if items.isEmpty {
                Vacio(texto: "Inbox al día. Lo que captures con ⌥⇧Espacio o por Telegram aparece aquí con su destino propuesto.")
            } else if ctx.enVentana {
                ScrollView { lista.padding(.bottom, 16) }
            } else {
                lista   // el render de maquetas no dibuja el contenido de un ScrollView
                Spacer(minLength: 0)
            }
            if !ctx.puedeActuar {
                Text("Para aprobar desde aquí: defaults write app.dictado centro -dict-add acciones /ruta/a/accion.sh")
                    .font(.system(size: 11)).foregroundStyle(TextoCentro.terciario).textSelection(.enabled)
            }
        }
        .padding(.horizontal, 28).padding(.vertical, 22)
    }

    private var lista: some View {
        // En la ventana van todas (con scroll); en el render de maquetas, las primeras seis.
        let visibles = ctx.enVentana ? items : Array(items.prefix(6))
        return VStack(spacing: 0) {
            ForEach(Array(visibles.enumerated()), id: \.element.id) { i, p in
                if i > 0 { FiloCentro().padding(.horizontal, 16) }
                FilaCaptura(p: p, destinos: e.inbox?.destinos ?? [], ctx: ctx)
            }
        }
        .padding(.vertical, 4)
        .superficie(radio: 18)
    }

    private var resumen: String {
        let cuenta = { (a: String) in items.filter { $0.accion == a }.count }
        var partes = [String]()
        for (a, t) in [("archivar", "archivar"), ("mover", "mover"), ("tarea", "volver tarea"), ("destilar", "destilar")] where cuenta(a) > 0 {
            partes.append("\(cuenta(a)) \(t)")
        }
        let propone = partes.isEmpty ? "" : " Claude propone: " + partes.joined(separator: ", ") + "."
        return "\(items.count) capturas.\(propone) Nada se mueve sin tu sí."
    }
}

private struct FilaCaptura: View {
    let p: EstadoCentro.Propuesta
    let destinos: [String]
    let ctx: ContextoCentro

    var body: some View {
        let ocupado = ctx.aplicando.contains(p.id)
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: icono).font(.system(size: 12, weight: .medium)).foregroundStyle(TextoCentro.secundario)
                .frame(width: 30, height: 30).background(Circle().fill(.white.opacity(0.06)))
            VStack(alignment: .leading, spacing: 4) {
                Text(p.titulo).font(.system(size: 13.5, weight: .semibold)).foregroundStyle(Halo.texto).lineLimit(2)
                Text(meta).font(.system(size: 11)).foregroundStyle(TextoCentro.terciario).lineLimit(1)
                if !p.extracto.isEmpty {
                    Text(p.extracto).font(.system(size: 11.5)).foregroundStyle(TextoCentro.secundario).lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: .trailing, spacing: 7) {
                propuesta
                Text(p.razon).font(.system(size: 11)).foregroundStyle(TextoCentro.terciario).lineLimit(2)
                    .multilineTextAlignment(.trailing).fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 6) { botones(ocupado) }
                if let f = ctx.fallos[p.id] {
                    Text(f).font(.system(size: 11, weight: .medium)).foregroundStyle(Tono.rojo.claro).lineLimit(2)
                }
            }
            .frame(width: 330, alignment: .trailing)
        }
        .padding(.horizontal, 16).padding(.vertical, 14)
        .modifier(EncimaCentro(radio: 16))
        .opacity(ocupado ? 0.5 : 1)
    }

    private var icono: String {
        if p.fuente == "hermes" { return "antenna.radiowaves.left.and.right" }
        switch p.tipo {
        case "tarea": return "checklist"
        case "nota": return "note.text"
        default: return "lightbulb"
        }
    }

    private var meta: String {
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

    private var propuesta: some View {
        let (simbolo, texto): (String, String) = {
            switch p.accion {
            case "archivar": return ("archivebox", "Archivar")
            case "mover": return ("folder", "Mover a \(p.destino ?? "")")
            case "tarea": return ("checklist", "Tarea: \(p.destino ?? "")")
            default: return ("text.book.closed", "Destilar con Claude")
            }
        }()
        return HStack(spacing: 5) {
            Text("Claude propone").foregroundStyle(TextoCentro.terciario)
            Image(systemName: simbolo).font(.system(size: 10.5, weight: .semibold)).foregroundStyle(TextoCentro.secundario)
            Text(texto).fontWeight(.semibold).foregroundStyle(Halo.texto).lineLimit(1)
        }
        .font(.system(size: 11.5))
        .frame(height: 20)
    }

    @ViewBuilder private func botones(_ ocupado: Bool) -> some View {
        if p.accion == "destilar" {
            BotonCentro(titulo: "Copiar el pedido para Claude", icono: "doc.on.doc") {
                ctx.copiar("Destila \(p.id) a la wiki (las páginas que toque) y luego archívalo.")
            }
        } else if ctx.puedeActuar {
            BotonCentro(titulo: ocupado ? "Aplicando…" : "Aprobar", tipo: .principal) { ctx.aplicarInbox(p.id, p.accion, p.destino) }
                .disabled(ocupado)
        }
        if ctx.puedeActuar && !ctx.enVentana {
            chip("Otro", fondo: .white.opacity(0.08), texto: Halo.texto)   // el render no dibuja menús
        } else if ctx.puedeActuar {
            Menu {
                Button("Archivar") { ctx.aplicarInbox(p.id, "archivar", nil) }
                Menu("Mover a") {
                    ForEach(destinos, id: \.self) { d in Button(d) { ctx.aplicarInbox(p.id, "mover", d) } }
                }
                Button("Volver tarea") { ctx.aplicarInbox(p.id, "tarea", p.titulo) }
            } label: {
                chip("Otro", fondo: .white.opacity(0.08), texto: Halo.texto)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .disabled(ocupado)
        }
    }

    private func chip(_ t: String, fondo: Color, texto: Color) -> some View {
        HStack(spacing: 4) {
            Text(t).font(.system(size: 12.5, weight: .semibold))
            Image(systemName: "chevron.down").font(.system(size: 8, weight: .bold)).opacity(0.7)
        }
        .foregroundStyle(texto)
        .padding(.horizontal, 13).frame(height: 28)
        .background(Capsule().fill(fondo))
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
