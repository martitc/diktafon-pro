---
type: spec
title: Spec — Modelos Gemini y descargas locales
description: Elegir modelos Gemini con información de coste y privacidad, mostrar modelos locales de transcripción y resumen, y terminar sus descargas largas aunque Diktafon pase a segundo plano.
tags: [sdd, spec, android, gemini, whisper, qwen, downloads, privacy]
timestamp: 2026-10-28
topic: sdd
slug: modelos-y-descargas
status: planned
---

# Spec — Modelos Gemini y descargas locales

> Slug: `modelos-y-descargas` · Status: planned · Created: 2026-10-28
> Inherits: [constitution](../constitution.md)

## Problem & why

Diktafon Pro permite elegir proveedores locales o Gemini, pero falta escoger claramente el modelo Gemini que procesará el audio. La lista también debe distinguir disponibilidad gratuita y de pago sin prometer que una clave o un modelo garantizan una tarifa o privacidad concretas. En local, los modelos grandes pueden no aparecer por la detección de memoria y las descargas extensas se interrumpen al dejar la app abierta en segundo plano.

La persona quiere elegir modelos de Gemini, conocer el efecto de Free Tier sobre sus datos, acceder a Whisper Large y a los modelos Qwen disponibles, y dejar que las descargas largas avancen sin mantener Diktafon en primer plano.

## Cost of not building it

La persona seguirá sin saber qué modelo procesa el audio, si puede generar un cargo o cómo se tratarán los datos bajo Free Tier. No podrá completar cómodamente descargas de varios gigabytes y puede concluir que faltan modelos locales cuando la app los oculta por su estimación de memoria.

## The cheapest alternative

Se puede mantener la selección actual de proveedores y pedir a la persona que deje Diktafon abierto hasta que termine cada descarga. También puede usar el modelo Gemini predeterminado. Esto no resuelve la falta de elección de modelo, la explicación de privacidad/coste ni las interrupciones que ya ha experimentado.

## Goals

- Permitir elegir un modelo Gemini compatible con transcripción de audio desde Ajustes.
- Permitir usar ChatGPT OAuth para resúmenes, con selección del modelo disponible en la cuenta.
- Preferir GPT-6 Luna con razonamiento alto como opción inicial de ChatGPT, solo si figura en el catálogo autorizado y el nivel está admitido.
- Mostrar qué modelos tienen disponibilidad de precio Free Tier, cuáles son solo de pago y que el nivel efectivo depende del proyecto de Google.
- Explicar que Google puede usar solicitudes procesadas en Free Tier para mejorar sus productos; explicar que Google dice que no usa para ese fin el contenido del nivel de pago.
- Mantener disponibles y visibles Whisper small, Whisper Large-v3-Turbo, Whisper Large-v3 y los modelos Qwen3 incluidos en la app, indicando los requisitos del dispositivo.
- Completar o reanudar descargas grandes iniciadas por la persona mientras Diktafon está en segundo plano, con progreso y estado recuperable.
- Mantener los modelos descargados verificados y conservar intactos los modelos ya instalados, las notas y los trabajos existentes.

## Non-goals / out of scope

- Google Drive, sincronización, la app macOS o descargas en segundo plano para macOS/iOS.
- Instalar o integrar un servidor Ollama. La app seguirá usando sus formatos de modelo locales compatibles.
- Crear una cuenta compartida o financiar el uso de Gemini con una clave de desarrollador.
- Cambiar Whisper, Qwen o Gemini como proveedor de forma automática ante errores.
- Garantizar que un modelo sea gratuito en cualquier proyecto, que una descarga termine pese a restricciones del sistema operativo o que una velocidad concreta de descarga se alcance.
- Añadir modelos de Gemini que no admitan entrada de audio para la ruta de transcripción.

## Users & context

La persona graba o importa audios en Android, decide si quiere procesarlos localmente o con Gemini y administra modelos de hasta varios gigabytes desde Diktafon Pro. Quiere poder salir de Ajustes o bloquear el móvil mientras se descarga un modelo.

## Behaviour

- En Ajustes, la persona ve un selector explícito del modelo Gemini para transcribir archivos. La lista inicial incluye Gemini 3.5 Transcribe, Gemini 3.5 Flash-Lite, Gemini 2.5 Flash, Gemini 3.8 Flash y Gemini 4 Argon. El catálogo muestra los identificadores de API correspondientes y evita aliases retirados o redirigidos.
- Para resúmenes con ChatGPT, Diktafon usa la conexión OAuth y muestra el catálogo actual de modelos de la cuenta, con sus nombres recibidos de OpenAI. La selección se actualiza al cambiar de cuenta y no incluye modelos que no ofrezca el catálogo.
- Si GPT-6 Luna aparece en el catálogo, se selecciona inicialmente con razonamiento alto cuando la cuenta/modelo permite ese nivel. La persona puede escoger otros modelos disponibles, incluidos Terra, Sol y variantes 6/6.1 si están en el catálogo; los niveles de razonamiento se limitan a los admitidos por el modelo.
- ChatGPT OAuth no aparece como motor para transcribir archivos: el uso de plan documentado por OpenAI permite solicitudes Responses API, mientras que la transcripción de archivos requiere la API de Audio. La persona conserva Whisper local y Gemini para transcribir. Un futuro uso de OpenAI para transcripción requeriría credenciales y facturación de API independientes.
- Los modelos con precio Free Tier disponible se marcan como «Free Tier disponible»; un modelo no disponible en Free Tier se marca como «De pago». Los rótulos describen la disponibilidad publicada del modelo, no verifican el nivel de facturación del proyecto de la persona.
- Antes de usar Gemini, la app explica que el nivel de uso depende del proyecto/API key. Si la solicitud se procesa en Free Tier, Google puede usar el contenido para mejorar sus productos; Google indica que no lo hace en el nivel de pago. La app no afirma poder detectar el nivel real de facturación solo a partir de la clave.
- Gemini 3.5 Transcribe se identifica como la opción específica para reconocimiento de voz. Los modelos generales compatibles con audio se distinguen de ella. El modelo seleccionado se guarda y se usa en las transcripciones posteriores hasta que la persona lo cambie.
- Gemini 3.5 Transcribe usa Interactions API y modalidad verbatim con tiempos por palabra. Google admite hasta una hora de audio sin esos tiempos, pero limita a 30 minutos cada solicitud con marcas temporales; Diktafon detecta y rechaza localmente audios más largos antes de subirlos.
- Si el modelo seleccionado requiere pago o el proyecto no tiene acceso, la app muestra el error del proveedor y un siguiente paso comprensible. No cambia a otro modelo ni proveedor sin permiso.
- En los selectores locales de Ajustes, Whisper small, Large-v3-Turbo, Large-v3 completo y Qwen3 1.7B y 4B aparecen con tamaño de descarga y nota de requisitos. Los modelos no compatibles con la memoria detectada siguen visibles con el motivo; la app no intenta transcribir o resumir si el dispositivo no cumple el requisito declarado.
- La persona puede iniciar, observar y pausar o reanudar una descarga. Al minimizar la app, navegar a otra pantalla o bloquear el dispositivo, una descarga iniciada continúa en segundo plano mientras Android y la red lo permitan; el estado y progreso vuelven a mostrarse al regresar.
- Si Android detiene o aplaza una tarea, o se pierde la red, Diktafon mantiene el progreso parcial verificable y reanuda la transferencia cuando sea posible. Al completarse, la app valida el modelo antes de activarlo y notifica el resultado. Un archivo inválido no se presenta como instalado.
- Los modelos se descargan desde fuentes con procedencia y licencia identificables. Cambiar de host solo se acepta si la copia corresponde byte por byte al modelo aprobado y pasa la misma validación de integridad.

## Acceptance criteria

- Given los Ajustes de Gemini, When la persona abre el selector, Then ve los cinco modelos compatibles de la lista inicial, diferenciados por especialización y disponibilidad Free Tier/de pago.
- Given un modelo listado como «Free Tier disponible», When se muestra el aviso de privacidad, Then queda claro que Google puede usar los datos en Free Tier y que la etiqueta no garantiza que el proyecto esté usando ese nivel.
- Given Gemini configurado para nivel de pago, When se muestra la explicación, Then se informa que Google dice que no usa ese contenido para mejorar sus productos y que se aplicará el precio vigente del proyecto.
- Given Gemini 3.5 Transcribe y un modelo general de audio, When la persona los compara, Then puede distinguir el reconocimiento de voz dedicado del modelo de uso general.
- Given ChatGPT OAuth conectado, When se abre el selector de resumen, Then se muestran los modelos visibles del catálogo de esa cuenta y se guarda la selección elegida.
- Given GPT-6 Luna aparece en el catálogo y admite razonamiento alto, When se conecta ChatGPT sin una preferencia previa, Then GPT-6 Luna queda seleccionado con razonamiento alto.
- Given la persona escoge otro modelo ChatGPT, When se presenta la opción de razonamiento, Then solo se pueden seleccionar niveles compatibles con ese modelo.
- Given la persona selecciona ChatGPT OAuth como proveedor de transcripción, When intenta procesar un archivo, Then la opción no se ofrece como compatible; Whisper y Gemini permanecen disponibles.
- Given un error de acceso, facturación o cuota, When Gemini rechaza una solicitud, Then la app conserva los datos y la selección y no cambia de modelo o proveedor automáticamente.
- Given un móvil que ejecuta Diktafon Pro, When se abre la selección local, Then Whisper small, Large-v3-Turbo, Large-v3, Qwen3 1.7B y Qwen3 4B aparecen con su tamaño; cualquier incompatibilidad de hardware se explica sin ocultar el modelo.
- Given una descarga de modelo iniciada con la app visible, When la persona minimiza la app o bloquea el teléfono, Then la descarga sigue o Android la deja pendiente para reanudarse y el estado no se pierde.
- Given una interrupción de red o del sistema operativo, When la descarga se reanuda, Then conserva bytes parciales válidos, no reinicia innecesariamente y solo activa el modelo tras verificar su integridad.
- Given un modelo descargado correctamente, When la persona vuelve a Diktafon, Then puede seleccionarlo sin descargarlo de nuevo y recibe una notificación de finalización.
- Given una descarga incompleta o con checksum incorrecto, When termina el intento, Then ese archivo no aparece como modelo instalado ni sustituye otro modelo válido.

## Clarifications

- **2026-10-28 — Variantes Whisper:** se mostrarán tanto Large-v3-Turbo como Large-v3 completo, además de small. La persona eligió expresamente ambas variantes; Large-v3 completo ocupa aproximadamente 2,9 GB.
- **2026-10-28 — Modelos locales:** el inventario actual ya ofrece Qwen3 1.7B y 4B y Whisper Large-v3-Turbo; la ampliación añade Large-v3 completo y corrige que los modelos grandes no se escondan por el cálculo de memoria.
- **2026-10-28 — Free Tier y nivel de pago:** «Free Tier disponible» identifica elegibilidad publicada del modelo, no el nivel de facturación efectivo del proyecto. El aviso debe separar explícitamente uso de datos y coste, y no debe prometer privacidad absoluta.
- **2026-10-28 — Descargas:** el objetivo es continuar en segundo plano cuando Android lo permita, informar del estado y reanudar interrupciones; no se promete ejecución ininterrumpida si el usuario fuerza la detención o el sistema impone restricciones.
- **2026-10-28 — ChatGPT para resúmenes:** se usará el catálogo OAuth por cuenta. GPT-6 Luna con razonamiento alto es la preferencia inicial si ambos aparecen como admitidos; los modelos y esfuerzos compatibles varían por cuenta/modelo.
- **2026-10-28 — Límite de transcripción OpenAI OAuth:** la documentación consultada describe el uso de plan por Responses API y transcripción de archivos por Audio API; GPT-6 Luna no acepta audio. No se considera confirmada la transcripción con una suscripción OAuth.
- **2026-10-28 — Alcance de OpenAI:** la persona elige mantener ChatGPT OAuth para resúmenes y Whisper/Gemini para transcribir. No se añadirá una clave OpenAI API independiente para transcripción en esta entrega.

## Points to clarify

- **suposición tomada** — La selección Gemini descrita aquí corresponde a transcripción de audio, no a selección de modelos para resumir. *Base:* la conversación aprobó el selector tras revisar la prueba de audio Gemini. *Riesgo:* si también se requiere un catálogo distinto para resúmenes, los criterios y lista cambian.
- **suposición tomada** — El catálogo OAuth de ChatGPT se usa solo para el proveedor de resumen; la selección Whisper/Gemini gobierna transcripción. *Base:* la persona confirmó esta separación y descartó añadir una clave OpenAI API separada para transcribir en esta entrega. *Riesgo:* transcripción OpenAI requeriría otra spec con credenciales y facturación API independientes.
- **suposición tomada** — Mantener Hugging Face como fuente primaria y no añadir un segundo mirror en esta entrega. *Base:* la app ya descarga desde repositorios de Hugging Face, y el problema observado es que el trabajo no sobrevive bien al cambio de contexto. *Riesgo:* la velocidad seguirá dependiendo de la red y disponibilidad del host.
- **decisión diferida** — Permitir que la persona configure repositorios de descarga arbitrarios.
- **decisión diferida** — Añadir más modelos locales aparte de los modelos nombrados en esta especificación.

## References

- [Google: precios de Gemini API](https://ai.google.dev/gemini-api/docs/pricing)
- [Google: transcripción de audio Gemini e Interactions API](https://ai.google.dev/gemini-api/docs/transcribe)
- [Google: modelo Gemini 4 Argon y entrada de audio](https://ai.google.dev/gemini-api/docs/models/gemini-4-argon)
- [Google: límites de uso](https://ai.google.dev/gemini-api/docs/rate-limits)
- [OpenAI: uso del plan ChatGPT en apps de código abierto](https://developers.openai.com/siwc/token-sharing-open-source)
- [OpenAI: catálogo por cuenta y Responses API para OAuth](https://developers.openai.com/siwc/token-sharing-open-source/models-and-inference)
- [OpenAI: modelos y niveles de razonamiento](https://developers.openai.com/api/docs/models)
- [OpenAI: transcripción de archivos de audio](https://developers.openai.com/api/docs/guides/speech-to-text)
- [Android: transferencias de datos iniciadas por el usuario](https://developer.android.com/develop/background-work/background-tasks/uidt)
- [Hugging Face: modelos Whisper ggml, tamaño y hashes](https://huggingface.co/ggerganov/whisper.cpp/blob/main/README.md)
- [Paquete Flutter background_downloader](https://pub.dev/packages/background_downloader)
