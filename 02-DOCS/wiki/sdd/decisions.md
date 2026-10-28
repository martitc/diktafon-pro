# Decisiones SDD

## 2026-10-26 — Ratificación de reglas del proyecto

- **Decisión:** adoptar la constitución v1.0.0 como guía del trabajo en Diktafon Pro.
- **Opciones consideradas:** mantener el borrador sin efecto; ratificar las reglas propuestas.
- **Motivo:** la persona propietaria confirmó explícitamente «ratifico y apruebo» el 2026-10-26.
- **Consecuencia:** las siguientes fases preservan el modo local, hacen visibles las transferencias a la nube y protegen claves y datos.

## 2026-10-27 — Mantener los límites de proveedores existentes

- **Decisión:** integrar los motores nube detrás de las interfaces actuales `TranscriptionProvider` y `SummarizationProvider`, y seguir usando la cola durable para trabajo nuevo y reprocesado.
- **Opciones consideradas:** sustituir las interfaces locales por un cliente único multiproveedor; mantener los motores locales y sumar adaptadores por proveedor.
- **Motivo:** la app ya resuelve sus motores mediante proveedores intercambiables y la cola serializa el trabajo ML. Los adaptadores conservan esa estructura y evitan mezclar credenciales, transporte y reglas de transcripción con la interfaz.
- **Consecuencia:** Gemini y ChatGPT tendrán adaptadores separados; el proveedor se resolverá por la configuración al ejecutar cada trabajo. Los trabajos de reprocesamiento conservarán el resultado vigente hasta publicar correctamente el nuevo resultado.
- **Límite externo:** ChatGPT OAuth usará el flujo documentado para apps OSS locales y `POST /v1/responses` con `store: false` y `stream: true`; el audio solo se enviará a Gemini.

## 2026-10-27 — Persistir candidatos de reprocesamiento en la nota

- **Decisión:** agregar `pendingTranscript` y `pendingMemoSummary` anulables a `Memos`, y `configSnapshot` anulable a `Jobs`. El trabajo durable conserva proveedor/modelo/instrucciones no secretos y su etapa; publica los candidatos juntos en una transacción al completar.
- **Opciones consideradas:** guardar el contenido candidato en la fila del trabajo; agregar campos provisionales a `Memos` y conservar la etapa/configuración en `Jobs`.
- **Motivo:** `Memos` ya es el registro canónico de transcripciones y resúmenes. Esta separación permite persistir un candidato grande, reanudar desde la etapa de resumen y no exponerlo como resultado antes del éxito.
- **Consecuencia:** migrar SQLite de versión 3 a 4 con tres columnas anulables. Los campos provisionales no se exportan. Los trabajos viejos sin `configSnapshot` permanecen en los motores locales existentes.

## 2026-10-28 — Separar Gemini GenerateContent de Transcribe Live

- **Reproducción:** la prueba de conexiones con `gemini-3.5-transcribe-live` devolvió HTTP 400 en el teléfono. El código envía cualquier modelo por `models/{model}:generateContent`; las pruebas reales con `gemini-2.5-flash` en el emulador sí funcionaron.
- **Diagnóstico:** Live requiere el protocolo de streaming Live API; no es un modelo de archivo para `generateContent`. La documentación ofrece `gemini-3.5-transcribe` para archivos mediante Interactions API. La respuesta 400 de Google se descarta, por lo que el cuerpo exacto no se conoce.
- **Acción:** todavía no se implementó el adaptador específico. Para archivos, usar modelos compatibles con `generateContent` o añadir el endpoint Interactions; no aceptar `-live` en el selector de la prueba actual.
- **Evidencia:** una frase española sintética produjo 13 palabras y tiempos válidos con `gemini-2.5-flash`. La prueba `gemini-3.6-flash` devolvió 503, que Google documenta como servicio temporalmente no disponible, distinto del 429 de cuota.
- **Por qué pasó inadvertido:** el campo de modelo acepta nombres libres, aunque el transporte solo implementa GenerateContent y no valida a qué familia de API pertenece el modelo.

## 2026-10-28 — Propuesta pendiente: selector de modelos y descargas nativas

- **Estado:** aceptada; la persona propietaria aprobó el plan el 2026-10-28.
- **Propuesta:** mantener Hugging Face como fuente primaria y delegar descargas largas iniciadas por la persona a tareas Android persistentes mediante `background_downloader`; `ModelManager` conservará responsabilidad de validación SHA-256 y activación atómica.
- **Opciones consideradas:** mantener `HttpClient` del proceso Flutter; integrar descargas nativas persistentes; incorporar Ollama como runtime y origen alternativo.
- **Motivo:** el repositorio ya descarga los formatos requeridos desde Hugging Face y ya soporta Range/SHA-256. El síntoma principal es que el trabajo no sigue fiable al pasar la app a segundo plano; Ollama no es un CDN de modelos y añadiría otro runtime.
- **Consecuencia si se aprueba:** conservar la ruta/identidad de los modelos, mostrar estado del sistema y reanudar cuando Android lo permita. La velocidad seguirá dependiendo del host y la red.

## 2026-10-28 — bug: cierre nativo durante VAD local  (feature: modelos-y-descargas)

- **Reproducción:** AVD Android 16/API 36 ARM64; importar `/sdcard/Download/DiktafonPro-speech-test.wav` con Whisper small y Qwen3 1.7B configurados. `logcat -b crash` mostró `SIGABRT` en `DartWorker`: `llamafile_sgemm ... assertion "ldb >= k" failed`; la traza pasó por `whisper_vad_detect_speech_no_reset`.
- **Causa:** `GGML_LLAMAFILE=ON` seleccionaba una ruta SGEMM que no acepta la forma de matriz emitida por Silero VAD en Android ARM64. La aserción abortaba el proceso entero dentro de `libdiktafon_whisper.so`.
- **Corrección:** forzar `GGML_LLAMAFILE=OFF` solo para Android; mantener los kernels CPU portables. Prueba de regresión real: misma muestra importada y transcrita correctamente tras recompilar e instalar, seguida de resumen Qwen y cambio de nombre/color.
- **Por qué pasó inadvertido:** las pruebas anteriores validaban configuración/selector y el camino de descarga, no ejecutaban la combinación real Whisper small + VAD en Android ARM64. La pantalla de error nativa no podía convertirse en excepción Dart.
## 2026-10-28 — Botón, prompt y catálogo local

- **Contexto:** El plan aprobado `importacion-y-modelos-locales` añade importación al deck, instrucciones solo locales para resúmenes y tres GGUF comprobados.
- **Decisión:** Reutilizar el importador actual tras una tecla visible del deck, bloquear toques repetidos desde que abre el selector del sistema y guardar en ajustes locales el prompt limitado a 2000 caracteres. Aplicarlo solo a los resúmenes locales de notas y casete.
- **Procedencia:** Fijar los archivos oficiales Gemma 4 QAT E2B/E4B de Google y Qwen3.5 2B de SoAIHQ por commit de Hugging Face, bytes exactos y SHA-256. Las tres fichas declaran Apache-2.0; la etiqueta Gemma conserva el crédito a Google.
- **RAM:** Aplicar umbrales conservadores iniciales de 6, 8 y 4 GiB hasta medir RSS e inferencia en Android compatible.
- **Evidencia:** 322 pruebas Flutter pasan; el análisis estático está limpio; la APK ARM64 compila y arranca en AVD. El AVD tiene 4,014,920 kB de RAM total, por lo que los modelos nuevos siguen bloqueados y no se descargaron.
- **Impacto:** La importación y el prompt funcionan sin conexión; instalar un modelo requiere conexión a internet.
