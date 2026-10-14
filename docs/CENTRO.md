# Centro de mando

Es un espacio de Dictado para ver tu día y a tus agentes, al estilo visionOS. Al abrirlo, tu fondo de pantalla ocupa la pantalla y encima flotan tres ventanas de vidrio en curva que miran hacia ti. La del centro está de frente; la lateral que apuntas con el puntero se pone de frente para leerla y tocarla. Alrededor van los ornamentos: las pestañas a la izquierda (con tus módulos), el estado arriba y, bajo la ventana del centro, lo que acompaña a cada sección. Se cierra con esc, ⌘W o la ×, o al irte a otra app, como Launchpad.

Se abre en la pantalla donde está el puntero. En una pantalla vertical (un monitor girado) el espacio se apila: la ventana del centro arriba, las otras dos debajo lado a lado, luego el ornamento y las pestañas en fila abajo. En Metas, la semana va arriba.

Tiene cuatro secciones:

- **Hoy:** a la izquierda tus agentes (sesiones de Claude Code, tu servidor y lo último que llegó al inbox); al frente el brief del día, con el foco, tres prioridades atadas a tus metas y cosas buenas de saber; a la derecha finanzas en resumen y noticias que te importan; debajo, tus metas de la semana, el mes y el trimestre.
- **Metas:** la semana, el mes y el trimestre, una ventana cada uno, con el tiempo que va corrido frente al avance de cada meta; debajo, el trimestre como regla con sus hitos.
- **Orquesta:** lo que pide tu sí (la ventana se enciende si hay algo), lo que trabaja ahora con la semana de tus agentes, lo programado y lo hecho hoy; debajo, lo que va costando. Junta tus sesiones de Claude Code en vivo con lo que te reporte tu propio servidor.
- **Inbox:** el resumen y la acción en bloque, tus capturas y, a la derecha, la que elegiste con el destino que propone tu asistente (archivar, mover a una carpeta, volver tarea o destilar). Apruebas con un clic, una por una o todas las de archivo a la vez.

## Qué hace y qué no

- **Solo lee.** Dictado no calcula ni guarda nada del centro. Ejecuta un comando que tú configuras, decodifica el JSON que ese comando imprime y lo pinta.
- **Cerrado, no corre nada.** Lee al abrirse y cada 5 minutos mientras está abierto. Al cerrarlo se libera la ventana (y la imagen del fondo).
- **Sin conexión, muestra lo último.** Guarda una caché en `~/Library/Caches/app.dictado/centro.json` y muestra lo último que leyó.
- **Lo que se puede abrir:** el tablero de finanzas, el archivo de metas, una noticia (solo enlaces http o https) y una sesión de Claude Code.
- **Lo único que cambia algo es el inbox,** y solo cuando apruebas. Dictado corre tu script de acciones **sin shell**: los argumentos van tal cual y nada se interpreta ni se inyecta. El script valida y responde `{"ok": true}` o `{"ok": false, "error": "…"}`.
- **Lo que todavía no hace:** aprobar y delegar a los agentes.

## Configuración

```bash
defaults write app.dictado centro -dict comando "'/ruta/a/estado.sh'"
```

Las comillas simples permiten espacios en la ruta: el comando corre con `zsh -c`. Para aprobar desde el Inbox, agrega el script de acciones (se ejecuta directo, sin shell; la ruta va tal cual):

```bash
defaults write app.dictado centro -dict-add acciones "/ruta/a/accion.sh"
# lo llama así:  accion.sh inbox <ruta de la captura> archivar|mover|tarea [destino o texto de la tarea]
```

El estado puede traer `"inbox.json": { "items": [{ "id", "titulo", "tipo", "fuente", "fecha", "extracto", "accion", "destino", "razon" }], "destinos": ["Carpeta/"] }`. Debe imprimir **un** objeto JSON, en máximo 30 segundos. Ninguna parte es obligatoria: la que falte, se oculta.

```json
{
  "brief.json":    { "fecha": "…", "semana": 41, "modelo": "…", "generado": "ISO", "clima": {…}, "agenda": [], "agenda_leida": true,
                     "foco": { "titulo": "…", "porque": "…" },
                     "prioridades": [{ "texto": "…", "vertical": "…", "meta": "…", "minutos": 15, "delegable": null, "hecha": false }],
                     "bueno_saber": ["…"], "fuentes": 10 },
  "metas.json":    { "archivo": "metas/2026-T4.md", "borrador": false,
                     "semana": { "nombre": "…", "rango": "…", "subtitulo": "…", "tiempo": 0.8, "metas": [{ "texto": "…", "vertical": "…", "estado": "en_curso", "avance": 0.3, "medida": "…" }] },
                     "mes": {…}, "trimestre": { …, "semana": 2, "semanas": 14, "dia": 10, "dias": 92, "desde": "2026-10-01" },
                     "hitos": [{ "fecha": "2026-10-29", "dia": 29, "texto": "…", "alerta": true, "dias_restantes": 19 }] },
  "noticias.json": { "items": [{ "vertical": "…", "titulo": "…", "fuente": "…", "fecha": "9 oct", "por_que": "…", "url": "https://…" }] },
  "orquesta.json": { "costo_hoy": 0.02, "costo_mes": 0.4, "presupuesto_dia": 0.5, "presupuesto_mes": 15,
                     "aprobaciones": [], "trabajando": [], "programado": [{ "titulo": "…", "agente": "…", "tipo": "hermes", "detalle": "…", "cuando": "dom 5:30" }], "hecho": [],
                     "calendario": { "dias": ["sáb 10", "…"], "ahora": 10.3, "filas": [{ "nombre": "…", "tipo": "hermes", "continuo": false, "corridas": [[0, 5.5]] }], "avisos": [] } },
  "salud.json":    { "capacidades": [{ "nombre": "…", "estado": "viva | alerta | rota | apagada", "detalle": "…" }] },
  "finanzas.json": { "patrimonio": 0, "delta": 0, "liquidez": 0, "neto_mes": 0, "colchon": 0, "colchon_piso": 0,
                     "proximos": [{ "concepto": "…", "monto": 0, "fecha": "15 oct" }], "alerta": null, "enlace": "ruta/al/tablero.html" },
  "modulos.json":  [{ "nombre": "…", "valor": "…", "abrir": "ruta relativa o https://…" }],
  "local":         { "cerebro": "/ruta/a/tu/carpeta", "inbox": 12 },
  "vps": true
}
```

Las rutas relativas (`enlace`, `abrir`, `archivo`) se abren dentro de `local.cerebro`.

## Atajos

**Hyper + A** (Bloq Mayús + A, o ⌃⌥⇧⌘A) lo abre desde cualquier app y, si ya está abierto, lo cierra. También: menú de Dictado → *Centro de mando…*, o `Dictado --abrir-centro` desde Atajos o Raycast.

Con el espacio abierto: **⌘1** Hoy · **⌘2** Metas · **⌘3** Orquesta · **⌘4** Inbox · **⌘R** actualizar · **esc** o **⌘W** cerrar.

Accesibilidad: con *Reducir movimiento* las ventanas quedan de frente y no se animan; con *Reducir transparencia* el vidrio y el fondo se vuelven sólidos.

## Probar sin abrir la app

```bash
Dictado --vista-centro2 salida.png [hoy|metas|orquesta|inbox]      # con DICTADO_CENTRO_ESTADO=<carpeta con los .json sueltos>
Dictado --vista-centro-real salida.png [hoy|metas|orquesta|inbox]  # con el comando configurado (DICTADO_FONDO=imagen para el fondo)
Dictado --probar-ventana-centro salida.png [hoy|metas|orquesta|inbox]  # abre el espacio real, espera los datos y guarda una foto
                                                                    # (sin vidrio ni giro 3D: eso se revisa con los renders)
```
