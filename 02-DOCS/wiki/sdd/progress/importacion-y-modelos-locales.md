---
type: progress
title: Progreso — Importación y modelos locales configurables
description: Registro de implementación y comprobaciones del plan aprobado.
tags: [sdd, progress, flutter]
timestamp: 2026-10-28
topic: sdd
slug: importacion-y-modelos-locales
status: in-progress
---

# Progreso — Importación y modelos locales configurables

## T001–T002 — 2026-10-28
- status: complete
- red: se añadió la prueba de semántica y acción del botón del deck.
- green: nuevo `CassetteDeckControls` muestra la flecha a bandeja junto al micrófono, con etiqueta, tooltip y layout compacto; la importación del overflow se retiró.
- edge cases: el estado de importación se activa antes de abrir el selector, bloqueando toques repetidos; el AVD de 280 px pasa el widget test.
- files: `diktafon/lib/presentation/widgets/cassette_deck_controls.dart`, `diktafon/lib/presentation/widgets/deck.dart`, `diktafon/lib/presentation/screens/cassette_screen.dart`, `diktafon/test/presentation/deck_test.dart`.
- evidence: widget test y revisión visual del AVD.

## T003–T004 — 2026-10-28
- status: complete
- red: las pruebas fallaron porque faltaban `instructions`, la preferencia y el setter.
- green: preferencia key-value local, máximo 2000 caracteres, campo multilínea y persistencia; al elegir ChatGPT el campo desaparece y el texto no se pasa a su proveedor.
- edge cases: vacío conserva literalmente el prompt anterior; el título automático permanece independiente.
- files: `settings_repository.dart`, `summary_prompts.dart`, `llm_summarization_provider.dart`, `providers.dart`, `settings_screen.dart`, ARB locales.
- evidence: tests de prompt, repositorio, UI, localización y `flutter analyze`.

## T005–T006 — 2026-10-28
- status: complete
- sources: Hugging Face API `?blobs=true`, revisiones, bytes, SHA-256 y licencias Apache-2.0 registrados en el plan (§7).
- green: añadidos Gemma 4 E2B/E4B QAT Q4_0 y Qwen3.5 2B Q4_K_M con enlaces fijados por commit y validación del gestor de descarga.
- RAM: umbrales iniciales conservadores 6/8/4 GiB; no son resultados de medición RSS.
- evidence: test de catálogo valida revisión, SHA-256, tamaño y licencia.

## T007–T008 — 2026-10-28
- status: complete
- green: cinco textos nuevos localizados en 20 ARB; el selector muestra etiqueta, cuantización, licencia, tamaño y memoria estimada. El prompt solo entra en los dos resúmenes locales.
- evidence: prueba de paridad ARB, prueba de selector y pruebas de composición del prompt.

## T009 — 2026-10-28
- status: complete
- evidence: `flutter analyze` limpio; `flutter test`: 322 aprobadas, 22 omitidas por muestras/modelos externos; APK ARM64 compilada e instalada en AVD API 36.
- smoke: el deck importador y el campo local se verificaron visualmente; se importó `DiktafonPro-speech-test.wav`, Whisper produjo «Hola, esta es una prueba de transcripción para DiktaFonPro. 1, 2, 3.» y el resumen del casete se actualizó. La app permaneció activa sin FATAL/SIGABRT/ANR nuevos en logcat.
- rename: el diálogo de renombrado guardó un título de prueba y la nota permaneció visible. La automatización de teclado escapó `_` como texto literal `%5F`; es una limitación de esta entrada de prueba, no un fallo de guardado. El renombrado de casete y el color ya se habían validado en la ronda anterior del AVD.
- model tests: no se descargaron GGUF nuevos. La memoria física del AVD es 4,014,920 kB, inferior al umbral 4 GiB incluso para Qwen3.5; las opciones grandes quedan deshabilitadas.
- prior audio regression: la WAV local ya se transcribió con Whisper y Qwen en este AVD durante la prueba del arreglo VAD; renombrar nota/casete y color funcionaron.

## T010 — 2026-10-28
- status: pending-device
- blocker: no hay modelo no instalado elegible en el AVD con su memoria actual. No se elimina ningún modelo instalado ni se inicia una descarga multi-GB solo para forzar el prompt de permiso.
- next: verificar el permiso denegado en un teléfono o emulador con al menos 4 GiB utilizables y un modelo descargable habilitado.
