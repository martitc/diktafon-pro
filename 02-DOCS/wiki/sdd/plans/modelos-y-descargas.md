---
type: plan
title: Plan — Modelos Gemini y descargas locales
description: Arquitectura, contratos, pruebas y secuencia para los selectores Gemini/ChatGPT y las descargas locales en segundo plano.
tags: [sdd, plan, android, flutter, gemini, chatgpt, whisper, qwen]
timestamp: 2026-10-28
topic: sdd
slug: modelos-y-descargas
status: approved
---

# Plan — Modelos Gemini y descargas locales

> Spec: [../specs/modelos-y-descargas.md](../specs/modelos-y-descargas.md) · Constitution: [../constitution.md](../constitution.md) · Status: approved
> Last updated: 2026-10-28

## 0. Global Constraints

- **Stack:** Android en Flutter y Dart; no migrar de tecnología.
- **Privacidad:** las grabaciones y transcripciones siguen locales salvo que la persona elija una operación Gemini que las envíe a Google.
- **Credenciales:** claves y tokens nunca se incluyen en código, logs, exportaciones ni diagnósticos; las credenciales OAuth se guardan de forma segura.
- **Proveedores:** Whisper/Qwen y nube se mantienen seleccionables; un error no activa otro proveedor o modelo en silencio.
- **Interfaz:** todo texto nuevo se traduce a los 20 idiomas que mantiene el proyecto.
- **Modelos descargados:** activar un modelo solo después de verificar su tamaño y SHA-256 esperado; los modelos existentes no se sustituyen con archivos parciales.
- **Transferencias:** una descarga puede aplazarse o cancelarse por Android, red, ahorro de batería o cierre forzado. La app informa el estado y reanuda cuando el sistema lo permite.
- **OAuth ChatGPT:** utilizar el endpoint público Responses API, `store: false`, `stream: true`, y esperar `response.completed` antes de publicar un resultado.
- **Git:** mantener el trabajo en la rama principal que eligió la persona; no crear ramas, publicar ni abrir PR sin una instrucción expresa.
- **Autoría:** no añadir coautoría de IA a commits ni PRs.

## 1. Context & constraints

- La spec aprobada cubre selección de Gemini para transcripción, selección de modelo ChatGPT OAuth para resumen, etiquetas de Free Tier/pago, privacidad, modelos locales y descargas de fondo.
- Criterios de aceptación: spec §Acceptance #1–#14. La operación local no debe requerir conexión ni enviar datos.
- La constitución exige conservar el modo local, mostrar las transferencias a nube, proteger credenciales y localizar la interfaz: constitution §§1, 3 y 4.
- El repo ya contiene `TranscriptionProvider`, `SummarizationProvider`, cola de trabajos y almacenamiento key-value de ajustes. El catálogo actual tiene Whisper small/Large-v3-Turbo y Qwen3 1.7B/4B; los modelos grandes se restringen mediante comprobaciones de RAM.
- `ModelManager` descarga con `HttpClient`, conserva `.part`, reanuda con HTTP Range y verifica SHA-256, pero su ciclo de vida está dentro del proceso Flutter. Al ir la app al fondo, Android no garantiza que la transferencia siga corriendo.
- Los modelos actuales ya vienen de Hugging Face. Cambiar a Ollama no aceleraría por sí mismo la descarga y añadiría un runtime/modelo de servicio fuera del alcance.
- La prueba Gemini y la prueba OAuth existentes no sustituyen su integración en la aplicación principal. La arquitectura OAuth previa sigue siendo la fuente para renovar tokens y validar scopes.
- Fuera de alcance: OpenAI OAuth para transcribir audio, claves OpenAI API, Ollama, modelos/hosts arbitrarios, Google Drive, macOS/iOS y cambio automático de proveedor.

## 2. Architecture

```text
[Settings UI] --preferences--> [SettingsRepository]
      |                               |
      +--Gemini model---------------> [GeminiCatalog + TranscriptionProvider]
      |                                  |--audio file--> [Gemini API]
      |
      +--ChatGPT model/effort-------> [ChatGPT Summary Provider]
                                         |--OAuth Responses stream--> [OpenAI]
                                         |
[Model Picker UI] --actions--------> [ModelManager]
                                         |
                                         +--persistent task--> [Android Download Service]
                                                                 | WorkManager / UIDT
                                                                 v
                                                         [Hugging Face]
                                                                 |
                                      [temporary file -> integrity -> installed model]
```

- **Settings UI (internal)** — muestra y guarda las elecciones y avisos de coste/privacidad.
- **SettingsRepository (internal)** — persiste proveedor, ID de modelo, esfuerzo y selecciones locales mediante las preferencias existentes.
- **GeminiCatalog (internal)** — catálogo curado con etiqueta de tarifa conocida, capacidad de audio y modalidad de transcripción admitida.
- **GeminiTranscriptionProvider (internal)** — adapta Gemini 3.5 Transcribe a su configuración específica y los modelos generales a la salida `Transcript` del producto.
- **ChatGPT model catalog/client (internal)** — consulta los modelos visibles de la cuenta OAuth elegida, los cruza con los niveles de razonamiento documentados y transmite solicitudes de resumen por Responses API.
- **Google Gemini API / OpenAI Responses API (external)** — reciben únicamente el contenido correspondiente al proveedor elegido.
- **ModelManager (internal)** — conserva catálogo local, verifica archivos y publica el modelo solo al completar la descarga.
- **Android background transfer adapter (internal)** — puente a tareas nativas persistentes; primera opción `background_downloader`, usando UIDT cuando la versión Android lo permita y trabajo reintentable en versiones anteriores.
- **Hugging Face (external)** — fuente primaria de los ficheros de modelo y metadatos de procedencia.

**Decisión arquitectónica principal:** delegar la transferencia larga a una tarea Android persistida y dejar a `ModelManager` la validación/instalación. Mantener la descarga Dart actual mejora continuidad solo mientras el proceso sigue activo; duplicar todo el modelo de transferencia en código nativo aumenta mantenimiento. `background_downloader` ya ofrece tareas nativas y reanudación para Android, sujeto a validar compatibilidad con el gradle/Kotlin actuales.

**Fuentes de decisión:** [OpenAI SIWC: catálogo e inferencia](https://developers.openai.com/siwc/token-sharing-open-source/models-and-inference), [Google: transcripción Gemini](https://ai.google.dev/gemini-api/docs/generate-content/transcribe), [Android: transferencias iniciadas por usuario](https://developer.android.com/develop/background-work/background-tasks/uidt), [background_downloader](https://pub.dev/packages/background_downloader), [modelos Whisper en Hugging Face](https://huggingface.co/ggerganov/whisper.cpp/blob/main/README.md).

## 3. Interfaces & contracts

```text
SettingsRepository.setGeminiTranscriptionModel(modelId: String) -> Saved | InvalidModel
  - solo acepta identificadores presentes en GeminiCatalog y compatibles con audio/archivo
  - conserva preferencias anteriores si la escritura falla

GeminiCatalog.listForTranscription() -> List<GeminiModelOption>
  - cada opción incluye ID, etiqueta, modo de transcripción, capacidad de audio,
    disponibilidad Free Tier publicada y nota de tarifa
  - «Free Tier disponible» no declara el nivel efectivo del proyecto

GeminiTranscriptionProvider.transcribe(audio: AudioRef, modelId: String) -> Transcript | ProviderError
  - usa la ruta específica para gemini-3.5-transcribe y la ruta general para modelos de audio
  - valida idioma/tiempos requeridos por Transcript; ante respuesta inválida, no publica candidato

ChatGPTModelCatalog.list(account: OAuthAccount) -> List<AccountModel> | AuthError | CatalogError
  - mantiene el orden del servidor y solo devuelve visibility=list
  - cada AccountModel conserva slug y display_name originales
  - niveles de razonamiento se cruzan con una tabla de capacidades vigente; no se infieren del catálogo de cuenta

ChatGPTSummaryProvider.summarize(text: String, model: String, effort: String) -> Summary | UsageLimit | ProviderError
  - exige permiso de uso del plan, usa streaming Responses, store=false
  - effort debe ser compatible con modelo; solo `response.completed` completa el trabajo

LocalModelTransfer.enqueue(model: ModelSpec) -> TransferId | InsufficientStorage | TransferError
LocalModelTransfer.pause(id: TransferId) -> Paused | NotPausable
LocalModelTransfer.resume(id: TransferId) -> Running | TransferError
LocalModelTransfer.cancel(id: TransferId, keepPartial: Bool) -> Cancelled
LocalModelTransfer.observe(id: TransferId) -> TransferState stream
  - estado se recupera después de cerrar/abrir la app
  - datos parciales no se consideran un modelo instalado

ModelManager.finalize(id: TransferId, model: ModelSpec) -> Installed | IntegrityError
  - valida tamaño y SHA-256 antes de mover el temporal a la ruta final
  - conserva otra versión instalada hasta que la nueva esté completa
```

## 4. Data model & flow

**Entidades**

- **AppSettings:** añade ID de modelo Gemini de transcripción; ID de modelo OAuth de resumen; esfuerzo; mantiene `whisperTier` y `llmTier`. Valores ausentes o inválidos migran a defaults seguros sin sobrescribir datos ni claves.
- **GeminiModelOption:** ID, nombre visible, capacidad (`fileTranscription`, `generalAudio`), protocolo, disponibilidad de Free Tier, etiqueta de tarifa y URL pública de precio. La tarifa es metadata de producto versionada, no una consulta fiable de facturación.
- **AccountModel:** cuenta asociada, slug y display name originales. Los esfuerzos admitidos provienen de metadatos oficiales por modelo y se intersectan con el catálogo de la cuenta; el catálogo API por cuenta no se trata como fuente de capacidades.
- **LocalModelAsset:** ID estable, origen, nombre, tamaño esperado, SHA-256, requisito de RAM, progreso/estado, ETag/validador y tarea nativa asociada.
- **OAuth credentials:** permanecen en el vault existente; ninguna copia de tokens se añade a AppSettings o a la cola de trabajo.

**Flujo principal — transcribir con modelo Gemini elegido**

1. Ajustes valida el modelo contra `GeminiCatalog` y persiste el ID.
2. La cola captura proveedor/modelo/instrucciones no secretas para el trabajo nuevo.
3. El proveedor entrega el audio a la modalidad adecuada; la salida se normaliza y valida contra el contrato de transcripción.
4. Solo un resultado completo y válido sustituye el candidato; errores conservan el resultado anterior y muestran una acción de reintento.

**Flujo principal — resumen mediante ChatGPT OAuth**

1. Conectar o seleccionar cuenta y verificar permiso `chatgpt.tokens.use.direct`.
2. Consultar modelos visibles con el token de esa cuenta; ofrecer GPT-6 Luna/high como default solo si el catálogo y modelo lo aceptan.
3. Guardar slug/esfuerzo; incluirlos en el snapshot del trabajo de resumen.
4. Consumir stream de Responses hasta `response.completed`; errores de uso del plan no activan Gemini/Qwen silenciosamente.

**Flujo principal — descargar Large-v3 o Qwen con la app en segundo plano**

1. La persona selecciona un modelo y acepta el tamaño/requisito visible; se comprueba espacio libre suficiente.
2. Se crea una transferencia nativa persistente desde Hugging Face a un temporal aislado. Se conserva/resume el temporal previo si el servidor soporta Range y el ETag coincide.
3. El sistema informa progreso por notificación; el usuario puede volver a Ajustes, pausar o reanudar.
4. Al finalizar, `ModelManager` verifica número de bytes y checksum, finaliza atómicamente y reanuda trabajos locales que estaban esperando.
5. Si el sistema suspende, cancela o pierde red, queda una tarea recuperable o un temporal para reanudar; no se borra un modelo válido.

- **Consistencia:** la preferencia de modelo se escribe antes de encolar trabajos nuevos; cada trabajo conserva su snapshot. La publicación de transcript/summary requiere respuesta válida y éxito de escritura.
- **Migración:** preferencias nuevas en la tabla key-value, sin cambio de esquema Drift previsto. La nueva transferencia debe adoptar temporales `.part` actuales si ETag/Range lo permiten; de otro modo los conserva y ofrece reintento seguro sin declarar instalación.
- **Recursos:** el Large-v3 completo requiere aproximadamente 2,9 GiB de espacio de descarga y alrededor de 4,7 GiB de RAM de ejecución según el modelo oficial. Debe aparecer en selector aunque el hardware no cumpla; se bloquea la ejecución con explicación si la medición de memoria no es suficiente.

## 5. Testing strategy

| Acceptance criterion | Level | Asserts | Fakes / mocks |
| --- | --- | --- | --- |
| spec §Acceptance #1–#4 | unit + widget | Modelo Gemini, etiquetas, disclosure, especialización y reglas por tier | catálogo Gemini fijado; estado de cuenta/proyecto simulado |
| #5, #8 | contract | errores Gemini/OpenAI conservan datos y no cambian modelo/proveedor | servidor HTTP falso; fake provider |
| #6–#7 | unit + widget | catálogo ChatGPT por cuenta, Luna/high inicial y esfuerzos válidos | endpoint `/v1/models` falso + matriz de capacidades falsa |
| #9 | unit + widget | Whisper/Gemini disponibles y ChatGPT OAuth no aparece como transcriptor | preferencias locales y vault falso |
| #10 | unit + widget | los cinco modelos locales visibles con tamaños y explicación de RAM | RAM detector controlable |
| #11–#13 | contract + Android integration | progreso, notificación, reanudación, retorno a pantalla y modelo instalado | servidor local Range/ETag; tarea nativa falsa en unit; emulador real para ciclo de fondo |
| #14 | unit + integration | checksum/tamaño incorrectos nunca activan/reemplazan modelo | archivo de fixture truncado/corrupto y repositorio temporal |
| Criterios de privacidad/credenciales | security + contract | no se registran tokens, audio, transcripciones ni API keys; Responses lleva `store=false` | logger capturable y HTTP fake |
| Localización (constitution §4) | unit | paridad de claves en los 20 ARB y textos accesibles | comparación de recursos; sin proveedor externo |

- **Límite e2e:** el emulador valida interacción, notificaciones, suspensión/reanudación; el X7 Pro real valida restricciones OEM y descarga continuada con pantalla bloqueada. La prueba real debe usar la APK del usuario, su clave/token en la app y nunca registrarlos en el harness.
- **Dependencia que debe ser real:** al menos una descarga iniciada manualmente debe probar una tarea nativa en Android; un mock de Dart no demuestra que Android mantenga trabajo en segundo plano.
- **Sin dependencias reales en suite repetible:** Gemini/OpenAI se simulan con HTTP local; los casos de modelos de varios GB usan ficheros pequeños con checksum de fixture.

## 6. Sequencing & dependencies

1. **Cerrar contratos de catálogos y preferencias** — mapear tipos y defaults en `SettingsRepository`; decide catálogo Gemini, default GPT-6 Luna/high y compatibilidad de esfuerzo — depende de spec aprobada — serial.
2. **Añadir catálogo Gemini y selector** — opciones diferenciadas por uso/precio, aviso de Free Tier/pago y persistencia — depende de #1 — serial.
3. **Conectar transcripción Gemini al catálogo** — ruta Transcribe específica, modelos generales de audio, validación y errores — depende de #2 — serial.
4. **Completar ChatGPT OAuth de resumen y selector** — integrar el flujo OAuth y proveedor de resumen definidos en las tareas correspondientes de `resumenes-con-proveedores`, sumar catálogo por cuenta, opción seleccionada, esfuerzo, stream y manejo de límites — depende de #1 y de los componentes OAuth del plan aprobado `resumenes-con-proveedores` — serial.
5. **Agregar Large-v3 completo y corregir disponibilidad local** — pin del artefacto/hash, tamaño, RAM/almacenamiento y textos UI; mantener small/Turbo/Qwen 1.7B/4B — depende de #1 — puede ir en paralelo con #2–#4 mientras no se edite `settings_screen.dart` a la vez.
6. **Integrar transferencias nativas** — validar `background_downloader` con Gradle/Kotlin/Android target actuales; migrar progreso/pausa/reanudación, notificaciones, Range/ETag, checksums y limpieza — depende de #5 — serial y de mayor riesgo.
7. **Unificar Ajustes y localización** — privacidad Gemini, selecciones y estados de descarga en todos los idiomas; revisar accesibilidad y modelos incompatibles — depende de #2–#6 — serial.
8. **Verificar y revisar** — unit/contract/integration, analyze, test suite, APK, prueba de fondo en emulador y X7 Pro cuando estén disponibles — depende de #7 — serial.

- **Paralelismo posible:** #2–#4 pueden dividirse una vez fijados los contratos en #1; #5 puede avanzar en un módulo separado. La UI compartida de ajustes y el archivo de locales se integran al final para evitar conflictos.
- **Orden duro:** no exponer un modelo Gemini antes de saber cómo normalizar su salida; no integrar tareas de fondo antes de fijar catálogo y destino final del fichero; no publicar un trabajo antes de verificar transferencia y resultado.

## 7. Risks & open decisions

**Risks**

| Risk | Trigger | Impact | Mitigation / spike to retire it |
| --- | --- | --- | --- |
| Android/plugin corta descargas largas | OEM, Doze, fuerza de detención, restricción de batería o API target incompatible | Large queda incompleto pese a notificación | spike nativo en API 36; usar UIDT/WorkManager compatible; mostrar pausa del sistema y reanudar; documentar fuerza de detención como límite |
| El SDK no entrega hash utilizable o cambia el recurso HF | LFS/Xet/ETag cambia o se corta la descarga | Modelo corrupto o reinicio no reanudable | fijar versión/origen y digest independiente; test Range/ETag; no habilitar el modelo sin verificación |
| Gran tamaño o RAM de Large-v3 excede el móvil | poco espacio o `MemTotal` no refleja memoria utilizable | app se queda sin almacenamiento/memoria o Android la mata | mostrar 2.9 GiB/4.7 GiB estimados, comprobar espacio, bloquear inference por requisito; conservar Turbo como alternativa |
| Gemini muestra tarifa/privacidad equivocada | el catálogo Free/Paid cambia o se confunde precio del modelo con tier del proyecto | coste inesperado o consentimiento incorrecto | metadata revisada/versionada; lenguaje «disponible en Free Tier»; explicar proyecto y enlace a precios; no afirmar tier detectado |
| Gemini no devuelve el esquema temporal esperado | modelo general o endpoint especializado cambia formato | transcripción no sincroniza audio | contrato de parser por modo, fixture real autorizada, rechazo seguro y conservación de transcript previo |
| Catálogo OAuth cambia o Luna no está habilitada | cuenta/plan/rollout/Workspace | modelo elegido no autorizado o esfuerzo da HTTP 400 | actualizar del catálogo por cuenta, validar effort por modelo, mantener selección solo mientras exista; pedir elección, nunca fallback silencioso |
| Las afirmaciones de privacidad se interpretan como garantía absoluta | Free Tier vs paid tier se simplifica demasiado | persona envía audio pensando que nunca se retiene | explicar solo la afirmación oficial de uso para mejora de productos; enlazar términos/precios; revelar que la app no conoce por API el tier del proyecto |

**Open decisions**

- Ninguna bloqueante. Las elecciones de catálogo, OpenAI solo para resúmenes, Whisper Large en ambas variantes y Hugging Face como fuente primaria están en la spec aprobada. La compatibilidad exacta del plugin y del modelo Gemini se resolverá mediante pruebas técnicas de implementación sin cambiar el alcance; si exige otro comportamiento, volver a la persona antes de desviarse.

## Tasks

| ID | Estado | Tarea | Done-check previsto | Depende de | Spec |
| --- | --- | --- | --- | --- | --- |
| T001 | done | Añadir preferencias y catálogos Gemini/OAuth | defaults, persistencia segura separada, etiquetas de tarifa y catálogo OAuth por cuenta | — | §Acceptance #1–#7 |
| T002 | done | Implementar selector Gemini, disclosures y transcriptor multimodelo | Files API, Interactions API para Transcribe, GenerateContent para audio general, sin fallback | T001 | #1–#5, #8–#9 |
| T003 | done | Integrar selector ChatGPT OAuth al resumen | OAuth, catálogo visible por cuenta, selección Luna/high, Responses streaming y errores de uso | T001 + plan previo OAuth | #2–#3, #5–#8 |
| T004 | done | Añadir Whisper Large-v3 y revisar catálogo de RAM local | fichero fijado por revisión, tamaño/SHA verificados y bloqueo al ejecutar | — | #10 |
| T005 | in progress | Adaptar ModelManager a tareas Android de fondo | transferencias nativas, notificaciones, recuperación, pausa/reanudación y checksum | T004 | #11–#14 |
| T006 | in progress | Completar Ajustes, localización y errores | paridad 20 idiomas y mensajes accesibles de privacidad/coste/estados | T002–T005 | #1–#14 |
| T007 | in progress | Verificar app Android y revisión | analyzer + suite Flutter + APK + smoke en API36/X7 Pro | T006 | #1–#14 |
