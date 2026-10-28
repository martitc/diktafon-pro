---
type: progress
title: Progreso — Modelos Gemini y descargas locales
timestamp: 2026-10-28
topic: sdd
slug: modelos-y-descargas
---

## Implementación inicial — 2026-10-28

- status: in_progress
- autorización: la persona aprobó la especificación y el plan y pidió iniciar la implementación.
- completado en código: preferencias separadas para proveedor/modelo; vault con `flutter_secure_storage`; catálogo Gemini y avisos Free/Paid; proveedor Gemini conectado a la cola con Files API, Interactions API y GenerateContent; OAuth de ChatGPT conectado al proveedor de resúmenes y Responses API con `store:false`, `stream:true` y espera de `response.completed`; catálogo dinámico de cuenta; Whisper Large-v3 fijado a una revisión de Hugging Face con SHA-256; bloqueo de inferencia según RAM; descargas Android mediante `background_downloader`, notificaciones, recuperación desde registros persistentes, comprobación previa de espacio libre mediante `StatFs` y reanudación de trabajos de la cola cuando un modelo se instala.
- limitación conocida: Gemini 3.5 Transcribe con tiempos de palabra se limita a audios de 30 minutos; la app rechaza archivos más largos antes de subirlos. Los modelos generales usan Files API para audio grande.
- pendiente: trasladar los textos del nuevo diálogo de nube a los 20 locales; probar transcripción Gemini y resumen ChatGPT OAuth con credenciales en el emulador; validar finalización/recuperación de descargas grandes en segundo plano y el comportamiento específico del X7 Pro.
- restricciones: conservar Hugging Face como origen; proteger credenciales; ChatGPT OAuth solo para resúmenes; no usar fallback silencioso.
- verificación realizada: `flutter analyze` sin incidencias; `flutter test` terminó con 317 pruebas aprobadas y 22 omitidas por requerir muestras/engines externos. La primera compilación completa reveló que Flutter también intentaba construir `armeabi-v7a`, incompatible con los intrinsics fp16 de `llama.cpp`; la APK se generó para ARM64 con `--split-per-abi --target-platform android-arm64`. Instalación y arranque limpio comprobados en el AVD API 36. El primer ciclo encontró y corrigió una escucha duplicada de `FileDownloader.updates`, que impedía llamar a `runApp`. La inspección visual encontró y corrigió el ancho excesivo del selector Gemini; modelo y etiqueta Free Tier quedan visibles en el ancho del emulador. Se verificaron los selectores de Whisper/Turbo/Large-v3/Qwen y los formularios Gemini y ChatGPT OAuth; no se guardaron credenciales ni se enviaron audios durante esta comprobación. `flutter gen-l10n` y la validación JSON de los 20 ARB siguen correctos.

## Incidencia de bloqueo al iniciar una descarga — 2026-10-28

- causa confirmada en el informe ANR de Android: Android 14+ inició el servicio de transferencia prioritaria (UIDT), pero faltaba la notificación obligatoria porque `POST_NOTIFICATIONS` aún no se había concedido. Android terminó declarando la app «no responde» al elegir Qwen3.
- corrección: solicitar el permiso de notificaciones antes de encolar una descarga; si se deniega, detenerla y mostrar un aviso localizado. La recuperación automática de descargas interrumpidas no abre un diálogo al iniciar la app.
- comprobación en emulador API 36 ARM64: APK recompilada e instalada; pantalla de ajustes volvió a responder. Con el permiso concedido, los registros muestran la notificación `model_downloads`, el inicio del servicio UIDT y la descarga completa de `model-small`; Whisper small y Qwen3 1.7B aparecen instalados. No se registró un nuevo ANR tras instalar la corrección.
- validación de código: `flutter analyze` sin incidencias; `flutter test`: 317 aprobadas y 22 omitidas por dependencias externas. La APK de depuración ARM64 está en `diktafon/build/app/outputs/flutter-apk/app-arm64-v8a-debug.apk`.
- pendiente: probar en el emulador el camino donde el usuario deniega el permiso y validar las descargas grandes en segundo plano; aún no se ha instalado esta APK en el X7 Pro.

## Prueba adicional de audio local — 2026-10-28

- repro: importar `/sdcard/Download/DiktafonPro-speech-test.wav` (muestra de 4 segundos, voz española) con Whisper small y VAD Silero en AVD API 36 ARM64.
- fallo observado: `SIGABRT` en el hilo DartWorker. `ggml` abortó en `llamafile_sgemm` con `assertion "ldb >= k" failed`; la traza entra por `whisper_vad_detect_speech_no_reset` durante `whisper_full`.
- causa aislada: el kernel LLAMAFILE SGEMM se había habilitado en el build Android y aborta con la forma de matriz válida que produce el VAD Silero. El error ocurría dentro de `libdiktafon_whisper.so`, no en el selector de archivos ni en la cola de notas.
- corrección aplicada: desactivar `GGML_LLAMAFILE` únicamente en compilaciones Android y usar los kernels CPU portables de ggml. El `CMakeCache.txt` ARM64 confirma `GGML_LLAMAFILE:BOOL=OFF`.
- evidencia tras recompilar e instalar: la misma importación terminó sin cierre; Whisper produjo «Hola, esta es una prueba de transcripción para DictaFonPro. 1, 2, 3.» Qwen3 1.7B generó el resumen de la colección y propuso «Lista de compras». Se renombró la nota a `Prueba_local_Qwen`, el casete a `Prueba_modelos` y se cambió su acento a turquesa; los tres cambios quedaron visibles.
- compilación: `flutter build apk --debug --split-per-abi --target-platform android-arm64` aprobada. APK instalada en el AVD; el proceso siguió activo tras la transcripción y no se registró un nuevo crash.
- permiso de notificaciones denegado: comprobación parcial. Se revocó y restauró el permiso en el emulador; el selector no ofrecía un modelo descargable porque los demás están bloqueados por RAM o el actual ya está instalado. No se eliminó ningún modelo para forzar el diálogo; queda pendiente verificar el caso denegado con un modelo disponible sin instalar.
