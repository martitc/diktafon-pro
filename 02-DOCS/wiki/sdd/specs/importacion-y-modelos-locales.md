---
type: spec
title: Spec — Importación rápida y resúmenes locales configurables
description: Acceso visible para importar audio dentro de cada casete, instrucciones propias para resúmenes locales y más modelos GGUF para Android.
tags: [sdd, spec, android, flutter, import, local-llm, gemma, qwen]
timestamp: 2026-10-28
topic: sdd
slug: importacion-y-modelos-locales
status: approved
---

# Spec — Importación rápida y resúmenes locales configurables

> Slug: `importacion-y-modelos-locales` · Status: approved · Created: 2026-10-28
> Inherits: [constitution](../constitution.md)

## Problema

La importación de archivos ya existe dentro del menú de tres puntos del casete, pero cuesta descubrirla mientras se trabaja con una grabación. La persona quiere un botón claro junto al botón rojo del micrófono, dentro del propio casete.

El resumen local solo usa instrucciones fijas. La persona quiere escribir cómo desea que se resuman sus audios. El selector local también solo ofrece Qwen3, aunque la app ya usa `llama.cpp` y el motor vendorizado reconoce Gemma 4 y Qwen3.5.

## Objetivos

- Mostrar dentro de cada casete un botón permanente de importación, junto al botón de grabar, con un icono claro de flecha hacia una bandeja y el mismo lenguaje visual pixel/retro.
- Reutilizar el importador actual, el selector Android y el procesamiento de la cola. La importación queda ligada al casete abierto.
- Añadir en Ajustes un campo de varias líneas para personalizar los resúmenes que genera el proveedor local.
- Añadir al catálogo local Gemma 4 E2B, Gemma 4 E4B y un modelo adicional con licencia Apache-2.0, comenzando por Qwen3.5 2B GGUF.
- Conservar los modelos y notas existentes; verificar tamaño y SHA-256 antes de instalar cualquier archivo nuevo.
- Explicar tamaño de descarga, requisitos de memoria y licencia de cada modelo sin ocultar opciones incompatibles con el dispositivo.

## Fuera de alcance

- Cambiar el motor local actual, añadir Ollama o instalar un segundo runtime para LiteRT.
- Cambiar el proveedor de transcripción o mandar contenido local a Gemini/ChatGPT.
- Aplicar el prompt personalizado a Gemini, ChatGPT o la generación del nombre automático del casete.
- Hacer disponible un modelo que no quepa en memoria, afirmar que una variante GGUF usa los tamaños menores de LiteRT, ni descargar modelos al emulador sin consentimiento de la persona.
- Instalar la APK en el X7 Pro en esta fase.

## Comportamiento

### Importar desde el casete

- La fila inferior del casete conserva las teclas de transporte y muestra, en el extremo derecho, un botón de importar claramente reconocible junto al botón rojo de micrófono.
- El botón usa un icono Material de flecha que entra en una bandeja, trazo/contorno y tamaño táctil acordes con las teclas del deck; incluye etiqueta accesible y tooltip localizados.
- Al pulsarlo se abre el selector de archivos Android y se llama al importador ya usado por «Import audio». El casete activo recibe el archivo y muestra el mismo progreso y mensajes actuales.
- Mientras se importan archivos, se evita iniciar el mismo flujo dos veces. Los fallos de selección o procesamiento conservan el comportamiento actual.
- La opción de importación deja de estar duplicada en el menú de overflow; renombrar, color, retranscribir y borrar siguen en ese menú.

### Instrucciones locales de resumen

- Ajustes muestra un campo de varias líneas, en la sección de resumen local, cuando el proveedor de resúmenes seleccionado es local.
- El campo guarda una preferencia local persistente. Vacío equivale a las instrucciones actuales.
- El texto personalizado modifica solo la intención/formato de los resúmenes de notas y el resumen acumulado del casete. El prompt fijo sigue imponiendo idioma, límites y salida breve; el título automático mantiene su instrucción propia.
- Cambiar de modelo local no borra el prompt. El proveedor Gemini/ChatGPT nunca recibe este texto ni lo aplica.
- La persona puede borrar el texto para volver al comportamiento predeterminado. La app limita la longitud y muestra contador/límite sin truncar silenciosamente.

### Modelos locales adicionales

- El selector añade Gemma 4 E2B, Gemma 4 E4B y Qwen3.5 2B; muestra etiqueta, cuantización, tamaño y memoria estimada, y conserva Qwen3 1.7B/4B.
- Gemma E2B/E4B se ofrecen como GGUF Q4_0/QAT compatibles con el `llama.cpp` incluido. La lista no presenta como tamaño del GGUF las cifras menores de las variantes móviles LiteRT.
- Qwen3.5 2B y las variantes oficiales Gemma 4 QAT GGUF se marcan con licencia Apache-2.0, según sus fichas, y mantienen el crédito a Google para Gemma.
- Se fijan repositorio, revisión, bytes, hash y licencia de cada archivo antes de publicarlo en catálogo. El modelo permanece desactivado hasta que el hash y tamaño sean válidos.
- Los modelos incompatibles con RAM o almacenamiento siguen visibles con motivo. Los umbrales finales se derivan de pruebas de memoria del runtime; no se deducen solo del número de parámetros.

## Criterios de aceptación

1. En un casete abierto, el botón de importación aparece siempre junto al micrófono, es accesible, coincide visualmente con el deck y abre el selector al casete activo.
2. La importación sigue mostrando progreso/errores, no duplica una selección simultánea y el overflow no mantiene una segunda acción de importación.
3. Ajustes ofrece un campo local multilínea con guardado persistente, limpieza/restauración del valor vacío y límite visible de longitud.
4. El prompt local afecta a resumen de nota y resumen del casete, pero no a transcripción, sugerencia de título, Gemini ni ChatGPT.
5. El catálogo muestra los modelos nuevos con fuente, licencia, cuantización, tamaño y restricciones RAM/almacenamiento; el catálogo previo permanece intacto.
6. Un modelo nuevo solo cambia a instalado si bytes y SHA-256 coinciden; una descarga corrupta conserva el modelo anterior y muestra error accionable.
7. El prompt y sus textos de UI están localizados en los 20 ARB mantenidos; los selectores y botones tienen etiquetas de semántica.
8. En el AVD API 36 ARM64 se importa una muestra de voz, Whisper no cierra el proceso, Qwen produce un resumen y se puede renombrar la nota/casete y cambiar color.
9. La batería automatizada cubre importación, persistencia de prompt, construcción del prompt final, catálogo, selección, hash incorrecto y límites de memoria con fixtures pequeños; no descarga archivos reales de varios GB en cada ejecución.
10. Una prueba manual del permiso de notificaciones denegado confirma que la descarga no se encola sin permiso cuando el AVD tenga un modelo descargable disponible.

## Evidencia y decisiones de catálogo

- Google documenta Gemma 4 E2B/E4B para móviles. En GGUF Q4_0 las estimaciones publicadas son mayores que los paquetes LiteRT móviles; se elige GGUF para conservar el runtime integrado.
- Qwen3.5 2B declara Apache-2.0 y el código vendorizado de llama.cpp incluye su arquitectura `qwen35`.
- Antes del plan aprobado no se añaden archivos de pesos, hashes supuestos ni enlaces `main` sin revisión fijada.

## Siguiente paso

Revisar y aprobar el plan técnico antes de escribir código de estas nuevas funciones.
