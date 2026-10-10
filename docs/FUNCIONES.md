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
| Dictado pulido con IA local | (por completar) | — (automático al dictar) | — | [↓](#dictado-pulido-con-ia-local) |
| Acciones sobre texto seleccionado | (por completar) | Hyper + T | Accesibilidad | [↓](#acciones-sobre-texto-seleccionado) |
| Quitar descargas de iCloud | (por completar) | — (en Limpieza) | — | [↓](#quitar-descargas-de-icloud) |
| Papelera que libera de verdad | `Salud.swift`, `VistaSalud.swift` | — (en Limpieza) | — | [↓](#papelera-que-libera-de-verdad) |

> La papelera que libera de verdad es parte de Limpieza, no un módulo con interruptor: el botón "Liberar ya" solo aparece cuando hay algo que liberar.

## Atajos con la tecla hyper

Hyper es Bloq Mayús mantenida, que equivale a ⌃⌥⌘⇧ pulsadas juntas. Pulsada sola funciona como Esc.

| Atajo | Acción |
|---|---|
| (por completar) | |

---

<!-- Cada módulo completa su ficha con: qué hace, cómo usarlo, archivos, permiso, cómo se apaga, cómo se quita y límites conocidos. -->

## Tecla hyper

## Ventanas por teclado

## Buscador de ventanas

## Dictado pulido con IA local

## Acciones sobre texto seleccionado

## Quitar descargas de iCloud

## Papelera que libera de verdad
