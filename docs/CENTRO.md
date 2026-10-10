# Centro de mando

Es una ventana de Dictado para ver tu día y a tus agentes. Tiene tres secciones:

- **Hoy:** el brief del día, con el foco, tres prioridades atadas a tus metas, cosas buenas de saber, un resumen de finanzas y noticias que te importan.
- **Metas:** la semana, el mes y el trimestre, con el tiempo que va corrido frente al avance de cada meta.
- **Orquesta:** lo que pide tu sí, lo que está trabajando, lo programado, lo hecho hoy y la semana de tus agentes. Junta tus sesiones de Claude Code en vivo con lo que te reporte tu propio servidor.

## Qué hace y qué no

- **Solo lee.** Dictado no calcula ni guarda nada del centro. Ejecuta un comando que tú configuras, decodifica el JSON que ese comando imprime y lo pinta.
- **Cerrada, no corre nada.** Lee al abrirse y cada 5 minutos mientras está abierta. Al cerrarla se libera la ventana.
- **Sin conexión, muestra lo último.** Guarda una caché en `~/Library/Caches/app.dictado/centro.json` y muestra lo último que leyó.
- **Lo que se puede abrir:** el tablero de finanzas, el archivo de metas, una noticia (solo enlaces http o https) y una sesión de Claude Code.
- **Lo que todavía no hace:** aprobar y delegar a los agentes.

## Configuración

```bash
defaults write app.dictado centro -dict comando "'/ruta/a/estado.sh'"
```

Las comillas simples permiten espacios en la ruta: el comando corre con `zsh -c`. Debe imprimir **un** objeto JSON, en máximo 30 segundos. Ninguna parte es obligatoria: la que falte, se oculta.

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

Con la ventana al frente: **⌘1** Hoy · **⌘2** Metas · **⌘3** Orquesta · **⌘R** actualizar · **⌘W** cerrar.

## Probar sin abrir la app

```bash
Dictado --vista-centro2 salida.png [hoy|metas|orquesta]      # con DICTADO_CENTRO_ESTADO=<carpeta con los .json sueltos>
Dictado --vista-centro-real salida.png [hoy|metas|orquesta]  # con el comando configurado
Dictado --probar-ventana-centro salida.png [hoy|metas|orquesta]  # abre la ventana real, espera los datos y guarda una foto
```
