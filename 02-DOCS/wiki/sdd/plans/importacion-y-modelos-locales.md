---
type: plan
title: Plan — Importación rápida y resúmenes locales configurables
description: Implementación y verificación incremental del botón de importación del deck, el prompt local y el catálogo Gemma/Qwen adicional.
tags: [sdd, plan, flutter, android, import, local-llm]
timestamp: 2026-10-28
topic: sdd
slug: importacion-y-modelos-locales
status: approved
---

# Plan — Importación rápida y resúmenes locales configurables

> Spec: [../specs/importacion-y-modelos-locales.md](../specs/importacion-y-modelos-locales.md) · Constitution: [../constitution.md](../constitution.md) · Status: approved
> Last updated: 2026-10-28

## 1. Límites de implementación

- Flutter/Dart existente; Android primero. Conservar diseño pixel/retro, Riverpod actual, Drift/key-value y cola durable.
- No migrar la base de datos si las nuevas preferencias caben en `SettingsRepository` key-value.
- Mantener `LocalLlmSummarizationProvider` y `LlamaWorker`; modelos GGUF separados por catálogo y no cambiar proveedor en silencio.
- Mantener el importador y filtro de extensiones actuales; el botón nuevo solo llama esa ruta.
- Todo texto nuevo en los 20 ARB; no guardar prompt dentro de notas exportadas ni enviarlo a proveedores nube.

## 2. Arquitectura

```text
[CassetteScreen: import DeckKey] ──> [_importAudio existente] ──> [LocalAudioImporter] ──> [JobQueue]

[Settings UI: prompt local] ──> [SettingsRepository] ──> [SummaryPrompt builder]
                                      │                          │
                                      └── local only ───────────┘

[Local model catalog] ──> [LlmModelManager + ModelManager]
                                   │ bytes / SHA-256
                                   └──> [llama.cpp worker]
```

- **UI del deck:** añadir un `DeckKey` de importación de estilo outline al lado de `DeckKey` de grabación; mantener acciones de cassette y diálogos existentes.
- **Preferencia:** añadir `localSummaryInstructions` a `AppSettings` y un setter key-value; guardar texto limpio con tope explícito.
- **Prompt:** inyectar instrucciones personalizadas en `memoSummaryPrompt` y `cassetteSummaryPrompt`; el valor vacío reproduce literalmente el default actual. `titlePrompt` no cambia.
- **Catálogo:** extender `LlmModel` con los tres modelos, sus revisiones/bytes/hashes, etiquetas de licencia y umbral de RAM; conservar `all`, `byTier`, fallback migratorio actual y modelos previos.
- **CMake Android:** conservar la regresión del kernel VAD: `GGML_LLAMAFILE=OFF` en Android.

## 3. Contratos

```text
SettingsRepository.setLocalSummaryInstructions(String value)
  -> persiste en la tabla key-value; longitud validada antes de escribir

memoSummaryPrompt(transcript, language, instructions)
  -> mantiene salida/idioma/presupuesto del producto y añade instrucción opcional

cassetteSummaryPrompt(digests, language, instructions)
  -> mantiene síntesis de colección y añade instrucción opcional

LlmModel.all
  -> catálogo inmutable con identificador, URL revisionada, tamaño, SHA-256,
     licencia visible y mínimo de memoria medido

CassetteScreen._importAudio()
  -> conserva su contrato; el botón visible comparte el estado de importación
```

- Si guardar la preferencia falla, se conserva el valor anterior y se informa; no queda una UI que aparente guardar.
- Si el modelo no está instalado, la cola espera a su instalación como hoy. Error de integridad no sustituye el archivo válido.
- El prompt personalizado se lee al preparar cada trabajo; un trabajo ya iniciado conserva el texto con el que comenzó.
- Para restaurar el default, se guarda una cadena vacía. Los modelos remotos nunca reciben este campo.

## 4. Secuencia y tareas

| ID | Tarea | Hecho cuando | Depende |
|---|---|---|---|
| T001 | Escribir pruebas del botón visible y accesible del deck | widget test confirma ubicación respecto al botón record, tooltip, invocación una vez y deshabilitado al importar | aprobación |
| T002 | Exponer el botón y retirar importación duplicada del overflow | el mismo picker existente importa al casete abierto; localización/semántica completas | T001 |
| T003 | Escribir pruebas de persistencia y composición del prompt | default vacío no cambia prompts previos; texto personalizado aparece solo en dos resumenes locales | aprobación |
| T004 | Añadir preferencia y campo de varias líneas a Ajustes | restaurar app mantiene texto, borrar restaura default, límite y contador se prueban | T003 |
| T005 | Auditar variantes GGUF, licencias, hashes, RAM/espacio | fuente, commit, bytes y SHA-256 verificados; riesgos y tamaño visibles | aprobación |
| T006 | Añadir Gemma4 E2B/E4B y Qwen3.5-2B al catálogo | pruebas de catálogo/download manager; modelos antiguos no cambian; corruptos no se instalan | T005 |
| T007 | Añadir traducciones de UI y revisar accesibilidad | 20 ARB tienen el mismo conjunto de claves; botones/labels leen con Semantics | T002, T004, T006 |
| T008 | Integrar el cambio de prompt con la cola local | fixture con transcripción larga usa prompt en gist, fixture de colección lo usa en resumen; title estable | T004 |
| T009 | Ejecutar gates y ciclos del emulador | format/analyze/tests; APK ARM64; importar WAV, Whisper+Qwen, renombrar nota/casete, color; no nuevo crash | T002–T008 |
| T010 | Verificar denegación de permiso de descarga | permiso denegado no muestra tarea UIDT ni ANR; se comprueba cuando un modelo sin instalar está habilitado | T006, emulador |

**Orden:** contratos y pruebas primero; T002 y T004 son componentes independientes; fijar procedencia antes de T006; prompt local debe probarse antes de conectar a Qwen/Gemma; integración UI y 20 locales antes de la APK. Descargas de multi-GB no se ejecutan como parte de la batería automática.

## 5. Verificación

- Dart: `dart format --set-exit-if-changed`, `flutter analyze`, `flutter test`.
- Catálogo: SHA-256 exacto con un servidor/archivo fixture; error de bytes/hash no altera modelos instalados.
- Widget: DeckKey import accesible, compactación/teclado/cassette abierto y segundo toque durante picker.
- Prompt: golden/text tests para default, personalizado, idiomas, límites y aislamiento de título/nube.
- Emulador API 36 ARM64: importación corta actual `DiktafonPro-speech-test.wav`, transcripción Whisper small, resumen Qwen local, cambio de nota/casete/color y logcat sin SIGABRT/ANR.
- Gemma y Qwen3.5: comprobar lectura GGUF/plantilla e inferencia solo cuando el umbral RAM del AVD lo permita; si no, el selector debe explicar la restricción y se registra la prueba en un dispositivo compatible antes de habilitar por defecto.
- Permiso: probar la ruta de permiso denegado con modelo no instalado, sin borrar ni reemplazar los modelos actuales del emulador.

## 6. Riesgos y límites

- **Tamaño:** GGUF Gemma4 Q4_0 pesa mucho más que su variante móvil LiteRT. Advertir bytes y requerimiento de espacio antes de descargar; no subestimar por el número E2B/E4B.
- **RAM:** las cifras del picker son umbrales conservadores iniciales (Gemma E2B 6 GiB, E4B 8 GiB, Qwen3.5 2B 4 GiB), no mediciones RSS en Android. Confirmarlas en un teléfono compatible antes de rebajar o llamarles requisitos medidos.
- **Compatibilidad GGUF:** la arquitectura figura en el llama.cpp vendorizado, pero cada variante/cuántización requiere fixture e inferencia real. Descargar desde revisión fija y verificar checksum.
- **Calidad/licencia:** Las fichas de Gemma 4 QAT GGUF y Qwen3.5 declaran Apache-2.0. Conservar los créditos a Google para Gemma.
- **Prompt ambiguo o excesivo:** límite explícito y concatenación segura; instrucciones del prompt no modifican idioma, conservación de transcript ni privacidad del proveedor.
- **Emulador limitado:** el AVD actual bloquea modelos por RAM. No forzar pruebas de varios GB mediante borrado de modelos instalados; planificar X7 solo después de revisar APK emulador.

## 7. Auditoría de artefactos T005

Los metadatos se consultaron en el API público de Hugging Face el 2026-10-28. El catálogo usa SHA-256 de cada blob LFS y URL con revisión inmutable.

| Modelo | Repo / revisión | Archivo | Bytes | SHA-256 | Licencia |
|---|---|---|---:|---|---|
| Gemma 4 E2B QAT Q4_0 | [`google/gemma-4-E2B-it-qat-q4_0-gguf`](https://huggingface.co/google/gemma-4-E2B-it-qat-q4_0-gguf/tree/675cff42a74c774d6cb76f76d8eacb49b48c9b93) · `675cff42a74c774d6cb76f76d8eacb49b48c9b93` | `gemma-4-E2B_q4_0-it.gguf` | 3,349,516,256 | `fa401b55b07ee70a54c6dae3903c783a6e65064312529ea57175cb5f8dec6634` | Apache-2.0 |
| Gemma 4 E4B QAT Q4_0 | [`google/gemma-4-E4B-it-qat-q4_0-gguf`](https://huggingface.co/google/gemma-4-E4B-it-qat-q4_0-gguf/tree/4b4a2c1d584be7264f87aac328a1bc739ce81b6c) · `4b4a2c1d584be7264f87aac328a1bc739ce81b6c` | `gemma-4-E4B_q4_0-it.gguf` | 5,154,941,280 | `676c35070db6dbe52f93e9c864ee0fba4eddea94b9c875d9cb10daff453fbaee` | Apache-2.0 |
| Qwen3.5 2B Q4_K_M | [`SoAIHQ/Qwen3.5-2B-GGUF`](https://huggingface.co/SoAIHQ/Qwen3.5-2B-GGUF/tree/377fa65bb36aa83414de1ab3b40f6f15b0324cdc) · `377fa65bb36aa83414de1ab3b40f6f15b0324cdc` | `Qwen3.5-2B-Q4_K_M.gguf` | 1,312,165,056 | `a8b50de00b780c0f3c16f07cb041a1ecd678b6e22fd8cde91e57fe4b5031523b` | Apache-2.0 |

## 8. Fuentes

- [Gemma 4 — modelos y estimaciones de memoria](https://ai.google.dev/gemma/docs/core)
- [Google Gemma 4 — modelo y licencia](https://ai.google.dev/gemma/docs/core/model_card_4)
- [Despliegue oficial de Gemma en móviles con MediaPipe](https://ai.google.dev/gemma/docs/integrations/mobile)
- [Modelos Gemma GGUF para llama.cpp](https://github.com/google-gemma/docs/blob/main/docs/deployment/llamacpp.md)
- [Qwen3.5-2B — ficha y licencia Apache-2.0](https://huggingface.co/Qwen/Qwen3.5-2B)
- [Llama.cpp — compatibilidad de Qwen3.5](https://github.com/ggml-org/llama.cpp/tree/master/src/models)
- [Qwen3.5-2B GGUF Q4_K_M — artefacto cuantizado de referencia](https://huggingface.co/SoAIHQ/Qwen3.5-2B-GGUF)
- [Hugging Face API — Gemma 4 E2B file metadata](https://huggingface.co/api/models/google/gemma-4-E2B-it-qat-q4_0-gguf?blobs=true)
- [Hugging Face API — Gemma 4 E4B file metadata](https://huggingface.co/api/models/google/gemma-4-E4B-it-qat-q4_0-gguf?blobs=true)
- [Hugging Face API — Qwen3.5 2B GGUF file metadata](https://huggingface.co/api/models/SoAIHQ/Qwen3.5-2B-GGUF?blobs=true)

## Estado

Plan aprobado por la persona propietaria el 2026-10-28. Implementación iniciada.
