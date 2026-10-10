# Funciones opcionales

Cada función opcional de Dictado es un módulo independiente:

- vive en su propio archivo en `Sources/Dictado/`;
- se prende o apaga desde el menú **Funciones** (ícono de micrófono → Funciones);
- se instala con una línea en `App.instalarModulos()`.

Apagarla desde el menú la desactiva al instante, sin reiniciar. Para quitarla del todo:

1. Borra su archivo (o archivos).
2. Borra su línea en `App.instalarModulos()`.
3. Borra su caso en el `enum Funcion` (`Funciones.swift`).
4. Compila con `swift build -c release` y reinstala con `./instalar.sh`.

| Función | Archivo(s) | Atajo | Permiso | Ficha |
|---|---|---|---|---|
| Tecla hyper | (por completar) | Bloq Mayús | Accesibilidad | [↓](#tecla-hyper) |
| Ventanas por teclado | (por completar) | Hyper + flechas | Accesibilidad | [↓](#ventanas-por-teclado) |
| Buscador de ventanas | (por completar) | Hyper + Espacio | Accesibilidad | [↓](#buscador-de-ventanas) |
| Dictado pulido con IA local | `PulidoIA.swift`, `IALocal.swift` | — (automático al dictar) | — (necesita Apple Intelligence) | [↓](#dictado-pulido-con-ia-local) |
| Acciones sobre texto seleccionado | `AccionesTexto.swift`, `VistaAcciones.swift`, `IALocal.swift` | Hyper + T | Accesibilidad | [↓](#acciones-sobre-texto-seleccionado) |
| Quitar descargas de iCloud | (por completar) | — (en Limpieza) | — | [↓](#quitar-descargas-de-icloud) |
| Papelera que libera de verdad | `Salud.swift`, `VistaSalud.swift` | — (en Limpieza) | — | [↓](#papelera-que-libera-de-verdad) |

> La papelera que libera de verdad es parte de Limpieza, no un módulo con interruptor: el botón "Liberar ya" solo aparece cuando hay algo que liberar.

## Atajos con la tecla hyper

Hyper es Bloq Mayús mantenida, que equivale a ⌃⌥⌘⇧ pulsadas juntas. Pulsada sola funciona como Esc.

| Atajo | Acción |
|---|---|
| Hyper + T | Acciones sobre el texto seleccionado (traducir, corregir, resumir, más formal, a Claude, guardar idea) |

---

<!-- Cada módulo completa su ficha con: qué hace, cómo usarlo, archivos, permiso, cómo se apaga, cómo se quita y límites conocidos. -->

## Tecla hyper

## Ventanas por teclado

## Buscador de ventanas

## Dictado pulido con IA local

**Qué hace.** Antes de pegar un dictado (⌥Espacio) o de guardarlo como idea (⌥⇧Espacio), el modelo de lenguaje de Apple que corre en el Mac (Apple Intelligence, framework FoundationModels) lo limpia:

- quita muletillas ("eh", "o sea", "este", "pues"…), repeticiones y frases empezadas y abandonadas;
- arregla la puntuación, las mayúsculas y las tildes;
- mantiene el idioma, el sentido y las palabras de tu vocabulario (`vocabulario.txt`);
- no agrega contenido ni responde lo que dictas: si dictas una pregunta, pega la pregunta limpia.

El tono depende de la app que está al frente:

| Modo | Apps | Tono |
|---|---|---|
| Chat | WhatsApp, Mensajes, Slack, Discord, Telegram, Signal, Messenger, Teams | Natural y breve |
| Correo | Mail, Outlook, Spark, Superhuman, Mimestream; Gmail y Outlook en el navegador | Profesional |
| Prompt | Claude, ChatGPT, Terminal, iTerm, Warp, Ghostty, VS Code, Cursor, Zed, Windsurf, Xcode, JetBrains; Claude, ChatGPT, Gemini y Perplexity en el navegador | Claro y ordenado, sin adornos |
| Documento | Word, Pages; Google Docs en el navegador | Formal y cuidado |
| Neutro | El resto | Mantiene el tono |

En los navegadores (Safari, Chrome, Arc, Dia, Brave, Edge, Firefox, Opera, Vivaldi, Orion) el modo sale del título de la pestaña activa. La tabla vive en un solo lugar, fácil de editar: `TablaModos`, al inicio de `PulidoIA.swift`.

**Cómo usarla.** No hay nada que hacer: dicta como siempre. Los dictados de menos de 4 palabras se pegan tal cual. Para probarlo desde la terminal, sin abrir la app:

```bash
.build/release/Dictado --pulir "eh bueno o sea mañana nos vemos a las tres" --app net.whatsapp.WhatsApp
.build/release/Dictado --pulir "eh mándales el enlace" --app com.google.Chrome --titulo "Recibidos - Gmail"
.build/release/Dictado --pulir "…" --vocabulario "Término1,Término2"   # sin esta bandera usa tu vocabulario.txt
```

La salida dice el modo, el tiempo y el motivo: `pulido`, `corto`, `sin modelo`, `tardó` o `descartado` (con la razón).

**El dictado nunca se pierde ni se bloquea.** El modelo tiene unos 3 s (hasta el doble en dictados muy largos). Si no está, tarda, falla o se niega, se pega el texto original. Si tu Mac suele estar muy ocupado y el pulido se salta seguido, sube el límite con `defaults write app.dictado pulidoLimite -float 4`. También se pega el original si la respuesta:

- agrega más de un 30 % de palabras o recorta más de dos tercios;
- pierde un término del vocabulario que estaba en el dictado;
- cambia de idioma;
- empieza como una negativa ("Lo siento…").

**Archivos.**

- `PulidoIA.swift`: el módulo, la tabla de modos, las instrucciones y las comprobaciones.
- `IALocal.swift`: acceso al modelo con tiempo límite. Lo comparte con Acciones sobre texto seleccionado.

Se engancha con `registrarPulido` de `ContextoModulos`. `App.entregar` lo llama solo si la función está prendida.

**Permiso.** Ninguno nuevo. Necesita Apple Intelligence activado (Ajustes del Sistema → Apple Intelligence y Siri). Para leer el título de la pestaña del navegador usa la Accesibilidad que Dictado ya tiene para pegar.

**Cómo apagarla.** Menú → Funciones → Dictado pulido con IA local. Se apaga al instante.

**Cómo quitarla.** Borra `PulidoIA.swift`, la línea `modulos.append(PulidoIA(contexto))` en `App.instalarModulos()`, el caso `.pulido` de `Funcion` y el bloque `--pulir` de `CLI.swift`. Si también quitas Acciones, borra `IALocal.swift`.

**Límites.**

- **Sin Apple Intelligence** (apagado, modelo descargándose o Mac no compatible) no pule: pega el texto tal cual. Al prender la función, la isla avisa por qué.
- **Idiomas:** los de Apple Intelligence (español, inglés, portugués, francés, alemán, italiano, japonés, coreano, chino y otros). Mantiene el idioma del dictado; en un idioma no soportado pega el original.
- **Tiempo:** agrega entre 0,5 y 2,5 s a cada dictado de 4 palabras o más (medido en un Mac con chip de Apple; lo más lento, con el Mac compilando a la vez). Al abrir la app se precalienta el modelo, pero con el Mac muy ocupado un dictado puede pasar de 3 s y pegarse sin pulir.
- **Modelo pequeño:** a veces quita una frase corta que sí decía algo ("si puedes") o pasa de tú a usted en modo correo. Si te molesta en una app, ponla en neutro en la tabla.
- **Privacidad:** todo corre en el Mac. El texto no sale del equipo y no se guarda nada aparte del dictado.

## Acciones sobre texto seleccionado

**Qué hace.** Seleccionas un texto en cualquier app y pulsas **Hyper + T** (Bloq Mayús + T, o ⌃⌥⌘⇧T). Junto a la selección, o junto al puntero si la app no dice dónde está, aparece un panel de vidrio con un extracto del texto y seis acciones:

| Tecla | Acción | Con qué |
|---|---|---|
| 1 | **Traducir:** español → inglés; cualquier otro idioma → español | Traducción de Apple (framework Translation), en el Mac. El idioma se detecta con NaturalLanguage |
| 2 | **Corregir:** ortografía y gramática, sin cambiar el estilo | Modelo de Apple (FoundationModels) |
| 3 | **Resumir** | Modelo de Apple |
| 4 | **Más formal** | Modelo de Apple |
| 5 | **A Claude:** abre un chat nuevo en Claude para Mac con el texto | Enlace `claude://claude.ai/new?q=…` |
| 6 | **Guardar idea:** lo guarda en tu carpeta de ideas, como ⌥⇧Espacio | — |

El resultado aparece en el mismo panel con dos botones:

- **Reemplazar** (↩): lo pega encima de la selección y deja tu portapapeles como estaba.
- **Copiar** (⌘C).

**Esc** cierra el panel; hacer clic fuera, también.

**Cómo lee la selección.** Primero por Accesibilidad (el texto seleccionado del elemento con el foco). Chrome y las apps Electron no lo cuentan; ahí copia con ⌘C, lee el texto y devuelve el portapapeles como estaba. Durante esa copia de paso el historial del portapapeles se pausa, para no guardarla. Nunca lee campos de contraseña.

**El enlace a Claude.** Claude para Mac acepta `claude://claude.ai/new?q=<texto>`: es el mismo enlace que usa su propio servicio "Ask Claude" (revisado en su `app.asar`). Si el texto pasa de 14 000 caracteres, empieza por "/" (Claude rechaza ese `q`) o no tienes la app, Dictado copia el texto y abre un chat nuevo para que lo pegues con ⌘V.

**Cómo probarla sin abrir la app.**

```bash
.build/release/Dictado --accion corregir "ola, la reunion es el jueves"
.build/release/Dictado --accion traducir "Nos vemos el viernes."
.build/release/Dictado --vista-acciones /tmp/acciones.png   # render del panel con un ejemplo
.build/release/Dictado --probar-acciones                    # comprobaciones; no toca tu portapapeles
```

**Archivos.**

- `AccionesTexto.swift`: atajo, lectura de la selección, acciones, Reemplazar y Copiar, enlace a Claude.
- `VistaAcciones.swift`: el panel, su render y las comprobaciones.
- `IALocal.swift`: acceso al modelo de Apple, compartido con el pulido.

Usa `guardarIdea` y `pausarHistorial` de `ContextoModulos`; este último llama a `Historial.pausar` (`Portapapeles.swift`).

**Permiso.** Accesibilidad, la misma que usa Dictado para pegar: sirve para leer la selección y simular ⌘C y ⌘V. Corregir, Resumir y Más formal necesitan Apple Intelligence; Traducir necesita los idiomas descargados.

**Atajo.** Hyper + T (id 50 en `Atajos`). Si otra app lo tiene, Dictado avisa al prender la función.

**Cómo apagarla.** Menú → Funciones → Acciones sobre texto seleccionado. Suelta el atajo al instante.

**Cómo quitarla.** Borra:

1. `AccionesTexto.swift` y `VistaAcciones.swift`;
2. la línea `modulos.append(AccionesTexto(contexto))` en `App.instalarModulos()`;
3. el caso `.acciones` de `Funcion`;
4. los bloques `--accion` y `--probar-acciones` de `CLI.swift` y `--vista-acciones` de `main.swift`.

`pausarHistorial` puede quedarse (no estorba) o borrarse de `ContextoModulos`, `App` y `Historial`.

**Límites.**

- **Sin Apple Intelligence**, Corregir, Resumir y Más formal muestran en el panel por qué no funcionan (apagado, modelo descargándose o Mac no compatible). Traducir, A Claude y Guardar idea siguen funcionando.
- **Traducción:** solo con los idiomas descargados en el Mac. Si faltan, el panel lo dice y ofrece **Descargar** (macOS pide confirmación) o **Abrir Ajustes** (General → Idioma y región → Idiomas de traducción).
- **Texto largo:** el modelo del Mac admite unas 1500 palabras. Con más, el panel avisa.
- **Reemplazar** pega con ⌘V: la selección tiene que seguir marcada en la app de origen. Tu portapapeles se restaura medio segundo después.
- **Sin selección,** la isla dice "Selecciona un texto primero". Algunos editores (VS Code) copian la línea entera con ⌘C cuando no hay selección.
- **Privacidad:** traducir, corregir, resumir y volver formal corren en el Mac; el texto no sale del equipo. Solo "A Claude" manda el texto a Claude, y únicamente cuando lo eliges.

## Quitar descargas de iCloud

## Papelera que libera de verdad
