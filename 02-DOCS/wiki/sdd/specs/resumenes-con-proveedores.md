---
type: spec
title: Spec — Proveedores de transcripción y resúmenes
description: Permitir elegir Whisper local o Gemini nube para transcribir, y Qwen local, Gemini nube o ChatGPT OAuth para crear y regenerar resúmenes.
tags: [sdd, spec, android, transcription, summaries, ai]
timestamp: 2026-10-26T22:15:56Z
topic: sdd
slug: resumenes-con-proveedores
status: approved
---

# Spec — Proveedores de transcripción y resúmenes

> Slug: `resumenes-con-proveedores` · Status: approved · Created: 2026-10-26
> Inherits: [constitution](../constitution.md)

## Problem & why

Diktafon usa Whisper local para transcribir y un modelo local para resumir, pero la persona no puede escoger Gemini nube como motor de transcripción ni Gemini o un modelo GPT disponible mediante su cuenta de ChatGPT para los resúmenes. Quien prefiere otro proveedor tiene que salir de la app y pierde continuidad con la cinta y la biblioteca.

## Cost of not building it

La persona seguirá limitada a los motores actuales o tendrá que sacar audios y transcripciones de Diktafon para procesarlos en otra herramienta. Se pierde la elección entre privacidad local y modelos en la nube, y no podrá volver a procesar las notas desde la biblioteca.

## The cheapest alternative

Usar otra app para transcribir o resumir no requiere cambios en Diktafon. No conserva la relación entre audio, transcripción, nota y casete, obliga a repetir el proceso y no permite volver a procesarlo dentro de la biblioteca.

## Goals

- Permitir elegir Whisper local o Gemini nube para transcribir audios nuevos e importados.
- Permitir elegir Qwen local, Gemini API o un modelo disponible mediante OAuth de ChatGPT para generar resúmenes.
- Permitir editar y guardar instrucciones de transcripción para Gemini e instrucciones de resumen, y aplicarlas a contenido nuevo o reprocesado.
- Permitir volver a transcribir un audio y volver a generar, por petición explícita, el resumen de una nota o el resumen general de su casete.
- Conservar el audio y el último resultado correcto al cambiar de proveedor o si el reprocesamiento falla.
- Mantener las opciones locales disponibles y hacer visible la elección persistente de nube, el proveedor activo y los datos que salen del dispositivo.

## Non-goals / out of scope

- Conectar Google Drive o sincronizar grabaciones entre dispositivos.
- Añadir un proveedor OpenAI independiente basado en API key.
- Cambiar el formato de las notas, la grabación, la reproducción o el editor de transcripciones.
- Regenerar resúmenes automáticamente al cambiar el proveedor o las instrucciones.

## Users & context

La persona usa Diktafon en Android para grabar o importar audios, leer transcripciones y organizar notas dentro de casetes. Quiere elegir en Ajustes entre Whisper local y Gemini nube para transcribir, y entre Qwen local, Gemini y GPT con su propia autorización para resumir; también quiere editar instrucciones y reprocesar contenido sin salir de la biblioteca.

## Behaviour

- Main path: en Ajustes, la persona elige Whisper local o Gemini nube para transcribir. Gemini requiere una clave propia y envía el audio al servicio de Google.
- Main path: en Ajustes, la persona elige Qwen local, Gemini o ChatGPT para resumir. Gemini requiere una clave propia; ChatGPT requiere conectar una cuenta y autorizar el uso del plan para solicitudes de IA.
- Security: la clave Gemini y los tokens OAuth de ChatGPT se guardan en almacenamiento seguro de la plataforma y no aparecen en registros, exportaciones ni diagnósticos. Desconectar ChatGPT elimina las credenciales locales de esa sesión.
- Main path: cuando la persona usa ChatGPT, Diktafon muestra los modelos que la cuenta conectada autoriza. GPT‑6 Luna aparece como opción solo si OpenAI lo incluye en esa lista; la app no lo sustituye en silencio por otro modelo.
- Main path: la selección de nube en Ajustes es autorización persistente mientras siga activa. La interfaz muestra el proveedor activo y etiqueta cada acción de transcripción o resumen que enviará datos a la nube; desde Ajustes se puede volver a una opción local.
- Main path: la persona puede editar y guardar instrucciones de transcripción para Gemini e instrucciones de resumen. El motor local Whisper no usa instrucciones de texto.
- Main path: desde una grabación/notas existentes, la persona puede volver a transcribir explícitamente el audio con el motor activo; desde una nota o casete, puede regenerar explícitamente el resumen correspondiente.
- Main path: no se reprocesan elementos existentes automáticamente cuando cambian proveedores o instrucciones.
- Main path: una nueva transcripción correcta reemplaza la transcripción previa; si falla, conserva la transcripción y el resumen existentes. Una regeneración correcta reemplaza solo el resumen solicitado.
- Edge cases: si la cuenta no permite usar el plan ChatGPT, la clave Gemini falta, la autorización caduca o la conexión no está disponible, se explica el estado y se ofrece corregir la conexión o reintentar.
- Edge cases: cambiar proveedor o instrucciones no altera resúmenes que ya existen hasta que la persona solicita regenerarlos.
- Error paths: un límite de uso o un fallo de un proveedor no cambia automáticamente a otro proveedor. Se conservan el audio, la transcripción y el último resumen disponible.
- Privacy: la selección persistente de Gemini nube autoriza enviar audio para transcribir y la selección de un proveedor de resumen autoriza enviar el texto correspondiente. Cada acción indica proveedor y tipo de dato antes de ejecutarse. Volver a Whisper/Qwen desactiva el envío para operaciones futuras.

## Acceptance criteria

- Given la configuración inicial, When la persona abre las opciones de transcripción, Then ve Whisper local y Gemini nube como opciones distinguibles.
- Given Gemini nube seleccionado sin una clave, When la persona intenta transcribir, Then recibe una indicación para añadir la clave y no se envía ningún audio.
- Given Gemini nube seleccionado, When la persona inicia la transcripción de un audio grabado o importado, Then antes del envío la interfaz identifica Gemini y que se enviará el audio; al completar, se guarda la transcripción recibida.
- Given ChatGPT está conectado, When la app guarda la autorización, Then conserva los tokens en almacenamiento seguro y los omite de registros, exportaciones y diagnósticos; al desconectar, elimina esos tokens locales.
- Given un audio importado o grabado con una transcripción, When la persona solicita volver a transcribirlo, Then se usa el motor seleccionado y se conserva la transcripción anterior si falla.
- Given la configuración inicial, When la persona abre las opciones de resumen, Then ve Qwen local, Gemini y ChatGPT como opciones distinguibles.
- Given Gemini seleccionado sin una clave, When la persona intenta configurarlo, Then recibe una indicación para añadir la clave y no se envía ninguna transcripción.
- Given una cuenta ChatGPT conectada, When la persona abre el selector de modelo, Then ve solo los modelos disponibles para esa cuenta; GPT‑6 Luna aparece únicamente si figura en el catálogo autorizado.
- Given la persona usa un proveedor en la nube, When Diktafon procesa o regenera un resumen, Then la persona puede identificar qué texto se envía y qué proveedor lo recibe, con el flujo de autorización resuelto en Clarifications.
- Given instrucciones de Gemini guardadas, When la persona transcribe o genera un resumen con Gemini, Then se usan las instrucciones correspondientes guardadas.
- Given instrucciones de resumen guardadas, When se genera o regenera un resumen con cualquier proveedor que las admita, Then la salida usa las instrucciones guardadas.
- Given una nota con resumen, When la persona pide regenerar el resumen de la nota, Then audio y transcripción no cambian y el resumen anterior permanece si la generación falla.
- Given un casete con resumen general, When la persona pide regenerarlo, Then la app actualiza solo ese resumen tras completarse la operación.
- Given un error o límite de un proveedor, When el procesamiento falla, Then el resumen anterior permanece y no se llama a otro proveedor automáticamente.
- Given cualquier proveedor configurado, When cambia la selección, Then los resúmenes existentes permanecen iguales hasta que la persona solicite regenerarlos.

## Clarifications

- **2026-10-27 — Proveedor de transcripción:** la persona podrá elegir en Ajustes entre Whisper local y Gemini nube. Gemini también será proveedor de transcripción en esta entrega.
- **2026-10-27 — Autorización de nube:** la elección en Ajustes constituye autorización persistente mientras el proveedor de nube siga activo. La interfaz mostrará el proveedor activo y el destino en cada acción de reprocesamiento; no pedirá una confirmación modal en cada solicitud.
- **2026-10-28 — Modelo Gemini para resúmenes:** el proveedor de resúmenes ofrece modelos locales, Gemini API y ChatGPT OAuth. El modelo Gemini para resúmenes se configura independientemente del modelo Gemini de transcripción. Gemini recibe únicamente la transcripción, resúmenes previos e instrucciones guardadas; nunca recibe audio por la ruta de resumen.

## Points to clarify

- **suposición tomada** — La selección de proveedor y sus instrucciones son ajustes globales para resúmenes nuevos y regenerados. *Base:* Diktafon ya configura globalmente su motor local de resumen. *Riesgo:* una selección por casete exigiría controles adicionales y un modo para conservar proveedores distintos en la misma biblioteca.
- **suposición tomada** — La selección de proveedor de transcripción también es global para audios nuevos e importados y para el reprocesamiento solicitado. *Base:* el usuario pidió escoger Whisper o Gemini en Ajustes. *Riesgo:* proveedores distintos por nota requerirían controles adicionales.
- **suposición tomada** — GPT‑6 Luna es una preferencia, no una disponibilidad garantizada. *Base:* OpenAI requiere usar los modelos que aparecen en el catálogo de la cuenta conectada. *Riesgo:* si Luna no aparece, la persona podrá escoger otro modelo permitido o mantener Qwen/Gemini.
- **decisión diferida** — Añadir OpenAI API con clave propia como otra modalidad de autenticación y facturación.
- **decisión diferida** — Sincronizar preferencias, proveedores o credenciales con Google Drive o la futura app macOS.

## References

- [OpenAI: uso del plan ChatGPT en apps de código abierto](https://developers.openai.com/siwc/token-sharing-open-source)
- [OpenAI: catálogo de modelos e inferencia con la cuenta autorizada](https://developers.openai.com/siwc/token-sharing-open-source/models-and-inference)
- [Google: claves de Gemini API](https://ai.google.dev/gemini-api/docs/api-key)
