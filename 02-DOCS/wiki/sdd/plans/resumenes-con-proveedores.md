---
type: plan
title: Plan — Proveedores de transcripción y resúmenes
description: Plan técnico para integrar transcripción y resúmenes locales y en la nube en Diktafon Android.
tags: [sdd, plan, android, transcription, summaries, ai]
timestamp: 2026-10-27T10:32:04Z
topic: sdd
slug: resumenes-con-proveedores
status: approved
---

# Plan — Proveedores de transcripción y resúmenes

> Spec: [../specs/resumenes-con-proveedores.md](../specs/resumenes-con-proveedores.md) · Constitution: [../constitution.md](../constitution.md) · Status: approved — revisión A1 aprobada por la persona propietaria
> Última actualización: 2026-10-27

## 0. Global Constraints

- **Stack:** La app Android existente se mantiene en Flutter y Dart. Una migración de stack requiere una decisión y especificación propias.
- **Modo local:** La app debe conservar su modo local. Las funciones en la nube son opcionales y se activan desde una elección visible de la persona.
- **Calidad:** Cada cambio funcional incorpora una comprobación automatizada adecuada a la capa afectada. Se ejecutan `dart format`, `flutter analyze` y las pruebas Flutter antes de declarar la entrega verificada.
- **Convenciones:** Los cambios siguen las capas y convenciones existentes del repo. Cada comportamiento nuevo queda descrito en su especificación y enlazado desde el índice de conocimiento.
- **Decisiones:** Las decisiones que afecten arquitectura, privacidad o compatibilidad se registran en `02-DOCS/wiki/sdd/decisions.md`.
- **Privacidad:** Las grabaciones y transcripciones permanecen locales salvo que la persona elija una función de nube que necesite esos datos. La interfaz identifica qué contenido se envía y a qué servicio.
- **Claves:** Las claves de API nunca se guardan en el código, manifiestos, registros ni archivos de exportación. Se almacenan con el mecanismo seguro de la plataforma y se excluyen de los diagnósticos.
- **Sin fallback:** La integración con un proveedor no sustituye ni desactiva silenciosamente el procesamiento local. Si la nube falla, se conserva el audio y se muestra una acción de reintento.
- **Localización:** Las nuevas pantallas y acciones respetan el estilo, accesibilidad y localización establecidos por Diktafon. No se publica texto visible nuevo sin traducción para los idiomas que mantiene el proyecto.
- **Rama y autoría:** El proyecto sigue la instrucción de trabajar en la rama principal abierta. No se crean ramas, se publica código ni se abre un PR sin instrucción expresa. No se añade autoría de IA a commits ni PRs.
- **OAuth:** Los tokens OAuth reciben el mismo nivel de protección que las claves: almacenamiento seguro y exclusión de logs, exportaciones y diagnósticos; al desconectar se revocan o eliminan según el resultado del servicio.
- **ChatGPT API:** Usar únicamente el flujo OAuth documentado para clientes OSS locales y el endpoint público `/v1/responses`; cada solicitud establece `store: false` y `stream: true`. No enviar audio a ChatGPT ni usar endpoints privados.
- **Cambios de modelo:** Una selección o instrucción nueva solo rige trabajos futuros o solicitados explícitamente. No reprocesar contenido de la biblioteca automáticamente.

## 1. Context & constraints

- La especificación aprobada define opciones locales y nube, prompts editables, consentimiento persistente visible y reprocesamiento explícito: spec §Goals, §Behaviour y §Clarifications.
- Selección de transcripción: spec §Acceptance #1–#3 y #5. Selección de resumen: #6–#11.
- Integridad de resultados: spec §Acceptance #12–#15. Un fallo no debe reemplazar el último resultado correcto ni activar otro proveedor.
- Privacidad y credenciales: spec §Behaviour Security/Privacy y §Acceptance #2–#4, #7, #9.
- La app ya usa interfaces `TranscriptionProvider` y `SummarizationProvider`, una `SettingsRepository` key-value y un `JobQueue` durable que resuelve motores al ejecutar cada trabajo.
- La app ya serializa tareas ML con concurrencia uno. Whisper y Qwen conservan su flujo local y sus gestores de modelos.
- El contenido está en SQLite/archivos locales. Credenciales nuevas no deben guardarse en SQLite ordinario ni en los paquetes de exportación.
- Fuera de alcance: Google Drive, sincronización, app macOS, proveedor OpenAI con API key y cambios de grabación/reproducción: spec §Non-goals.
- OpenAI documenta modelos por cuenta y solicitudes Responses en streaming; el catálogo determina qué modelos se pueden elegir. La ruta no ofrece entrada de audio ni transcripción.
- Gemini admite entrada de audio, indicaciones de transcripción, palabras con marcas de tiempo y carga de archivos grandes. Sus límites de duración y formatos deben validarse frente a los audios reales.

## 2. Architecture

```text
[Ajustes y biblioteca / INTERNAL]
       | elige proveedor, ve destino y pide reprocesar
       v
[SettingsRepository + credenciales / INTERNAL]
       | configuración normal          | secretos
       v                                 v
[ProviderFactory / INTERNAL] -----> [CredentialVault / INTERNAL]
       |                                 |
       v                                 v
[JobQueue durable / INTERNAL]       [Keystore/Keychain / EXTERNAL]
       | selecciona en cada trabajo
       +--> [Whisper + Qwen / INTERNAL]
       +--> [Gemini adapters / INTERNAL] --> [Gemini API / EXTERNAL]
       +--> [ChatGPT adapter / INTERNAL] --> [OAuth + Responses API / EXTERNAL]
       |
       v
[SQLite repositories + audio files / INTERNAL]
```

- **Ajustes y biblioteca (interno):** muestran motores, credenciales, estado, prompts, destino de nube y acciones explícitas de reprocesamiento.
- **SettingsRepository (interno):** conserva selecciones, modelo elegido y prompts no secretos. Mantiene compatibilidad con los ajustes locales existentes.
- **CredentialVault (interno):** ofrece guardar, leer, actualizar y borrar clave Gemini y credenciales ChatGPT sin exponerlas a repositorios de contenido.
- **ProviderFactory (interno):** resuelve el proveedor configurado al iniciar cada trabajo y bloquea el envío cuando faltan credenciales o permiso.
- **JobQueue (interno):** serializa trabajos, aplica reintentos, conserva resultados publicados y evita fallback automático.
- **Adaptadores locales (internos):** mantienen Whisper/Qwen actuales detrás de sus interfaces.
- **Adaptadores nube (internos):** normalizan solicitudes, respuestas y errores de Gemini y ChatGPT a los contratos de la app.
- **Gemini API y ChatGPT OAuth/Responses (externos):** procesan audio/transcripción o texto/resumen bajo la selección activa.
- **Repositorios y archivos (internos):** conservan audio, transcripción, resúmenes y estado durable.

**Decisión arquitectónica principal:** mantener los dos límites de proveedor existentes y resolver cada implementación al ejecutar un trabajo. Esto evita que credenciales, solicitudes HTTP y diferencias de cada modelo se filtren a widgets o al dominio. Para el reprocesamiento, guardar el candidato en columnas provisionales de la nota y avanzar el trabajo durable entre etapas; publicar en una transacción al completar. Así, un cierre de Android conserva tanto el resultado previo como la etapa pendiente.

**Diseños alternativos:** un cliente genérico que conozca todos los proveedores reduciría el número de clases, pero mezclaría OAuth, clave Gemini, formatos y errores. Se eligen adaptadores independientes que cumplen las interfaces actuales.

## 3. Interfaces & contracts

```text
SettingsRepository.getProviderPreferences() -> ProviderPreferences
  - contiene proveedor de transcripción, proveedor/modelo de resumen y prompts no secretos
  - cambiar preferencias no agenda trabajos ni modifica artefactos existentes

CredentialVault.put(provider, secret) -> Stored | StorageFailure
CredentialVault.get(provider) -> Secret? | StorageFailure
CredentialVault.remove(provider) -> Removed | RevocationUnconfirmed
  - los valores no pasan por logs, exportadores ni diagnósticos

ProviderFactory.transcription(preferences, credentials) -> TranscriptionProvider | ConfigurationRequired
ProviderFactory.summarization(preferences, credentials) -> SummarizationProvider | ConfigurationRequired
  - no sustituye un proveedor por otro al fallar

TranscriptionProvider.transcribe(audio, language, prompt, cancel) -> Transcript | ProviderFailure
  - acepta archivos válidos del almacén local y normaliza idioma, segmentos y tiempos
  - la configuración nube valida consentimiento activo y clave antes de subir bytes

SummarizationProvider.summarizeMemo(transcript, language, instructions) -> Summary | ProviderFailure
SummarizationProvider.updateCassetteSummary(digests, language, instructions) -> Summary | ProviderFailure
  - ChatGPT recibe solo texto y usa el modelo permitido seleccionado en la cuenta

JobQueue.retranscribeMemo(memoId) -> Queued | MemoNotFound | AudioUnavailable | ConfigurationRequired
JobQueue.regenerateMemoSummary(memoId) -> Queued | MemoNotFound | NoTranscript | ConfigurationRequired
JobQueue.regenerateCassetteSummary(cassetteId) -> Queued | CassetteNotFound | ConfigurationRequired
  - las acciones señalan proveedor/datos antes de empezar; ninguna muta contenido al encolarse
  - fallo: mantener el último artefacto publicado y ofrecer reintento
  - cada trabajo conserva `configSnapshot = { transcriptionProvider?, summaryProvider?, model?, instructions? }`; nunca incluye secretos
  - el reprocesamiento escribe `pendingTranscript` y `pendingMemoSummary`; publica ambos y los limpia atómicamente al completar
  - si la app reinicia en etapa de resumen, reanuda con `pendingTranscript`; no vuelve a transcribir el audio
```

## 4. Data model & flow

**Entidades**

- **ProviderPreferences:** proveedor de transcripción (`whisper`/`gemini`) y modelo Gemini de transcripción; proveedor de resumen (local/Gemini/ChatGPT), modelo Gemini de resumen independiente, modelo ChatGPT elegido y prompts editables. Se persiste en las claves de configuración existentes.
- **Credential record:** clave Gemini o datos de cuenta, `client_id`, `host_id`, tokens, scopes y expiración de ChatGPT. Solo en el almacén seguro del sistema.
- **Memo:** añadir `pendingTranscript` y `pendingMemoSummary`, ambos anulables. Nunca se muestran ni exportan como transcripción o resumen publicados. Un trabajo de reprocesamiento los escribe y los limpia al publicar o cancelar.
- **Job:** añadir `configSnapshot`, JSON anulable que conserva proveedor, modelo e instrucciones no secretos al crear un trabajo. No contiene clave Gemini ni tokens OAuth. Los trabajos anteriores a la migración con snapshot nulo siguen usando el motor local actual.
- **Memo/Cassette:** conservan los resultados publicados hasta la confirmación correcta. El resumen de casete conserva su última versión hasta que la reconstrucción finalice.

**Flujo primario: transcribir audio importado con Gemini**

1. La persona selecciona Gemini en Ajustes y guarda la clave en el almacén seguro.
2. El indicador de configuración muestra Gemini activo. La acción de transcripción nombra Gemini y el audio que saldrá.
3. La app encola un trabajo y el `ProviderFactory` obtiene el adaptador Gemini con la clave en memoria solo durante el uso.
4. El adaptador envía el audio al endpoint documentado, usa las instrucciones admitidas y normaliza la respuesta a `Transcript`.
5. La cola guarda la transcripción candidata en `pendingTranscript` y avanza el mismo trabajo durable a la etapa de resumen. Al completar esa etapa, publica transcripción y resumen de nota, limpia las columnas provisionales, elimina el trabajo de reprocesamiento y encola la actualización del resumen de casete en una sola transacción.
6. Si una etapa falla, la app conserva los resultados publicados, registra el estado sin secretos y ofrece reintentar con el proveedor activo.

**Flujo ChatGPT para resumen**

1. En Ajustes, la persona inicia OAuth en navegador del sistema.
2. El adaptador valida `state`, PKCE, identidad, scopes y catálogo de modelos; una cuenta sin permiso de plan no queda activa.
3. Al resumir, la cola pasa solo el texto requerido al adaptador ChatGPT.
4. El adaptador envía el modelo seleccionado al endpoint público Responses con streaming y sin almacenamiento de respuesta, consume la respuesta completa y devuelve el texto.
5. Solo al recibir un resultado válido se publica. Un error conserva el resumen previo y no cambia a Qwen o Gemini.

**Flujo Gemini para resumen**

1. En Ajustes, la persona selecciona Gemini, elige el modelo de texto para resúmenes y configura su clave API.
2. La app envía solo la transcripción/digest y las instrucciones Gemini guardadas a `models/{model}:generateContent` mediante `x-goog-api-key`.
3. La respuesta solo se publica si contiene texto utilizable. Una cuota agotada, respuesta inválida o fallo de red conserva el resumen previo y no activa un proveedor alternativo.

- **Persistencia:** actualizar SQLite de versión 3 a 4 con tres columnas de texto anulables: `Memos.pendingTranscript`, `Memos.pendingMemoSummary` y `Jobs.configSnapshot`. La migración solo añade columnas, conserva filas existentes y no reescribe datos publicados. Los ajustes de selección/prompts siguen en la tabla key-value.
- **Consistencia:** el trabajo guarda el snapshot de proveedor/modelo/instrucciones al encolarse. Una sola transacción publica transcripción y resumen candidatos, limpia las columnas provisionales, elimina el trabajo de reprocesamiento e inserta el trabajo de actualización del casete. Una caída antes de publicar deja el resultado previo intacto y permite reanudar desde la etapa registrada en `Jobs.type`.
- **Exportación:** la interfaz `Memo` y el exportador siguen exponiendo solo `transcript` y `memoSummary` publicados; columnas provisionales y snapshots nunca entran en `cassette.json` ni en los registros de diagnóstico.
- **Cancelación/edición:** cancelar o borrar la nota elimina su trabajo y candidato. Una edición manual descarta el reprocesamiento pendiente antes de aplicar la edición.
- **Archivos Gemini:** para audios que requieran carga por Files API, intentar borrar la copia remota al terminar incluso tras error/cancelación. Si la red impide borrarla o la app se cierra, Google la elimina automáticamente a las 48 horas.
- **Credenciales:** al cerrar sesión, revocar el token renovable si la red responde y borrar tokens localmente. Si no se confirma revocación, dejar claro que el usuario puede revocar desde ChatGPT.

## 5. Testing strategy

| Criterio de aceptación | Nivel | Comprueba | Fakes / mocks |
| --- | --- | --- | --- |
| spec §Acceptance #1 | widget | Ajustes ofrece Whisper y Gemini diferenciados | modelos locales y vault fake |
| #2 | widget + contract | sin clave no se crea solicitud ni se serializa audio | vault vacío, servidor HTTP fake |
| #3 | contract + integration | aviso identifica Gemini/audio; petición realista y respuesta normalizada se guardan | servidor Gemini fake; audio fixture local |
| #4 | unit + integration | persistencia segura abstraída; desconexión borra token y reporta fallo de revocación | secure storage fake y endpoint OAuth fake; integración manual de dispositivo para plugin real |
| #5 | unit + integration | el audio permanece; el reproceso usa proveedor seleccionado; fallo conserva transcripción y resumen publicados | repositorios SQLite reales en memoria, proveedores fake que fallan/éxito |
| #6 | widget | Qwen, Gemini y ChatGPT aparecen como opciones diferenciadas | estado local sin modelo descargado |
| #7 | widget + contract | Gemini sin clave no manda texto ni cambia resumen | vault vacío, HTTP fake |
| #8 | contract + widget | catálogo autorizado alimenta selector; GPT‑6 Luna aparece solo si el servidor lo incluye | catálogo/respuestas OAuth fake con y sin Luna |
| #9 | widget + contract | resumen nube muestra proveedor y texto de destino antes de solicitarlo | proveedor fake que captura input |
| #10 | unit + contract | instrucciones guardadas llegan a proveedor Gemini para la operación correspondiente | Gemini fake que captura configuración |
| #11 | unit + contract | instrucciones guardadas se aplican a resumen nuevo y regenerado | proveedores locales/nube fake |
| #12 | unit + integration | regenerar nota conserva audio/transcripción; fallo mantiene resumen y éxito reemplaza solo ese resumen | DB en memoria, proveedor de resumen controlable |
| #13 | unit + integration | regenerar casete actualiza solo su resumen tras éxito y conserva el previo si falla | DB en memoria y fake provider |
| #14 | contract + integration | error/límite no llama segundo proveedor y preserva artefactos | proveedor primero con fallo y segundo con contador |
| #15 | unit + integration | cambiar selección no encola trabajos ni altera resultados anteriores | `SettingsRepository` real en DB en memoria y queue fake |

- **Límite E2E:** probar recorridos UI con providers falsos; los servicios reales se validan en pruebas manuales de humo, no en CI, para evitar claves personales, coste y dependencia de red.
- **Dependencias reales obligatorias:** Drift en memoria para integridad y transacciones; plugin de almacenamiento seguro en Android real antes de dar por válido el almacenamiento de secretos; callback OAuth en dispositivo para el cierre de factibilidad.
- **Verificación final:** ejecutar los comandos Flutter configurados en `sdd/config.yaml` y revisar todos los criterios. Si el SDK o un dispositivo faltan, registrar esa limitación en la evidencia en lugar de afirmar que está verificado.

## 6. Sequencing & dependencies

1. **Cerrar factibilidad externa** — probar en un Android real el callback OAuth loopback, la renovación/revocación y el catálogo; validar el endpoint Gemini con una muestra autorizada y el formato temporal esperado. Depende de: ninguna — **serial**. Si el callback o el formato de transcripción no cumplen la spec, volver a aclaración antes de continuar.
2. **Definir preferencias y secretos** — añadir selecciones/prompts persistentes, vault seguro y estados de conexión sin UI final. Depende de: #1 aprobado — **serial**.
3. **Integrar transcripción Gemini** — adaptador, validación de audio/idioma, normalización, limpieza de cargas remotas y errores. Depende de: #2 — **paralelizable** con #4 si se fijan los contratos.
4. **Integrar resúmenes nube** — adaptador Gemini y adaptador ChatGPT OAuth/Responses; catálogo de cuenta, streaming, renovación y revocación. Depende de: #2 y #1 — **paralelizable** con #3 en módulos separados.
5. **Conectar fábrica y cola durable** — escoger proveedor en ejecución, bloquear credenciales ausentes, añadir acciones explícitas y conservar artefactos anteriores al fallar. Depende de: #3 y #4 — **serial**.
6. **Actualizar Ajustes y biblioteca** — selectores, prompts editables, aviso de destino, estado OAuth y acciones de regeneración. Depende de: #2 y contratos de #5 — **serial**.
7. **Localización, pruebas y pulido** — completar todas las traducciones y accesibilidad; ejecutar unitarias, integración, análisis, formato y humo Android; corregir cualquier regresión. Depende de: #3–#6 — **serial**.

- **Candidatos a paralelizar:** #3 y #4 tienen dueños de interfaces distintos; solo se separan si las tareas de SDD asignan archivos exclusivos.
- **Orden estricto:** validar las APIs antes de escribir integraciones; no mostrar controles nube como disponibles hasta saber el estado de claves/autorización; no sustituir resultados publicados antes de éxito.
- **Aislamiento:** el proyecto indica trabajar sobre `main` abierta. Esta fase no crea ramas ni worktrees; la implementación seguirá esa instrucción de proyecto.

## 7. Risks & open decisions

**Riesgos**

| Riesgo | Disparador | Impacto | Mitigación / prueba para retirarlo |
| --- | --- | --- | --- |
| Alto — OAuth ChatGPT puede no completar su retorno desde navegador Android | OpenAI usa callback local `127.0.0.1`; Android tiene restricciones de ciclo de vida y listeners | La opción ChatGPT puede no ser implementable con el flujo aprobado en Android | Spike #1 en dispositivo real; no crear backend alternativo ni endpoint privado. Si falla, detener esa parte y pedir decisión para ajustar la spec |
| Alto — salida Gemini no encaja con el transcript temporizado de Diktafon | El formato/precisión de palabra y prompt varían por modelo y modalidad | Texto sin tiempos rompe la navegación por palabra y la sincronización de reproducción | Spike #1 con audio breve y largo; comprobar instrucciones, idioma y correspondencia start/end; rechazar respuesta inválida sin reemplazar datos |
| Alto — clave de Gemini extraíble de una app móvil | APK controlado por quien instala la app | Uso/coste no autorizado si se filtra la clave | Solo usar clave propia del usuario, guardar con almacenamiento seguro, no incluir clave de desarrollador; explicar límites y recomendar clave restringida; nunca registrar la solicitud completa |
| Medio — cargas de audio remotas quedan huérfanas | Cancelación, cierre de app o error de red tras subir el fichero | Retención temporal de una copia de audio hasta el vencimiento de Google | Limpiar siempre en `finally`; si no se puede borrar o la app se cierra, Google elimina la copia a las 48 horas |
| Medio — regeneración concurrente o reinicio pisa resultados | Cambio de proveedor durante una cola o cierre del proceso | Se puede publicar salida de modelo equivocado o perder el último resultado | Capturar proveedor/configuración al encolar, versionar el trabajo y publicar por compare-and-set/transacción |
| Medio — catálogo, scopes o límite de uso ChatGPT cambian | Cambia disponibilidad de cuenta, OAuth preview o cuota | Selector o resumen deja de funcionar | Consultar catálogo con token vigente, mapear errores sin fallback y permitir desconectar/reconectar; mantener los motores locales |
| Medio — faltan traducciones o mensajes exponen error técnico | Nueva configuración y rutas de error | Interfaz incoherente o datos técnicos/secreto visibles | Revisar todos los ARB y mensajes mapeados; test de paridad de localización y búsqueda de secretos en logs |

**Decisión pendiente**

- Factibilidad del retorno OAuth y la transcripción Gemini — se cierra con spike #1; si la evidencia contradice la spec, regresar a `clarify` y no iniciar integración completa.

## Referencias técnicas verificadas

- [OpenAI — Sign in with ChatGPT para apps OSS locales](https://developers.openai.com/siwc/token-sharing-open-source)
- [OpenAI — registro y callback loopback OAuth](https://developers.openai.com/siwc/token-sharing-open-source/sign-in)
- [OpenAI — catálogo, Responses API y modelos autorizados](https://developers.openai.com/siwc/token-sharing-open-source/models-and-inference)
- [OpenAI — límites: audio no disponible en este flujo, `store: false` y streaming](https://developers.openai.com/siwc/token-sharing-open-source/preview-limitations)
- [OpenAI — renovación y seguridad de credenciales](https://developers.openai.com/siwc/token-sharing-open-source/profiles-and-sessions)
- [Google — transcripción de audio Gemini](https://ai.google.dev/gemini-api/docs/transcribe)
- [Google — gestión de claves Gemini](https://ai.google.dev/gemini-api/docs/api-key)
- [Google — carga y eliminación de archivos temporales Gemini](https://ai.google.dev/gemini-api/docs/files)

## Tasks
<!-- generated by tasks on 2026-10-27; IDs are stable, do not renumber -->

| ID | [P] | Tarea | Comprobación de término | Depende de | Traza |
| --- | --- | --- | --- | --- | --- |
| T001 |  | Validar OAuth y el formato Gemini | Prueba manual en Android registra inicio/callback OAuth, renovación y revocación; una muestra de audio produce idioma, texto y tiempos utilizables o documenta el bloqueo | — | spec §Acceptance #3–#5, #8 |
| T002 |  | Escribir pruebas de preferencias y secretos | `cd diktafon && flutter test test/data/provider_preferences_repository_test.dart` falla por ausencia de las preferencias/vault esperados | T001 | spec §Acceptance #1–#2, #4, #6–#7 |
| T003 |  | Implementar preferencias y almacén seguro | `cd diktafon && flutter test test/data/provider_preferences_repository_test.dart` pasa; la clave y los tokens no aparecen en SQLite de ajustes ni exportaciones | T002 | spec §Acceptance #1–#2, #4, #6–#7 |
| T004 |  | Escribir pruebas del transcriptor Gemini | `cd diktafon && flutter test test/services/gemini_transcription_provider_test.dart` falla por solicitud o normalización ausente | T003 | spec §Acceptance #2–#3, #10 |
| T005 |  | Implementar transcripción Gemini | `cd diktafon && flutter test test/services/gemini_transcription_provider_test.dart` pasa; normaliza `Transcript`, bloquea el envío sin clave y limpia el archivo remoto en éxito/error/cancelación o conserva una tarea de limpieza si no hay red | T004 | spec §Acceptance #2–#3, #10 |
| T006 |  | Escribir pruebas de resúmenes Gemini y ChatGPT | `cd diktafon && flutter test test/services/cloud_summarization_provider_test.dart` falla por solicitudes, instrucciones o errores ausentes | T003 | spec §Acceptance #7–#11, #14 |
| T007 |  | Implementar resúmenes nube | `cd diktafon && flutter test test/services/cloud_summarization_provider_test.dart` pasa; Gemini y ChatGPT reciben el texto e instrucciones correctos, y los errores no activan fallback | T006 | spec §Acceptance #7–#11, #14 |
| T008 |  | Escribir pruebas del cliente OAuth ChatGPT | `cd diktafon && flutter test test/services/chatgpt_oauth_client_test.dart` falla para state/PKCE/scopes/catálogo/refresh/revocación sin implementar | T003 | spec §Acceptance #4, #8 |
| T009 |  | Implementar cliente OAuth ChatGPT | `cd diktafon && flutter test test/services/chatgpt_oauth_client_test.dart` pasa; catálogo filtrado por cuenta, tokens excluidos de logs/exportaciones/diagnósticos y desconexión revoca o borra credenciales locales | T008 | spec §Acceptance #4, #8 |
| T010 |  | Escribir pruebas de migración y reprocesamiento durable | `cd diktafon && flutter test test/services/job_queue_cloud_reprocess_test.dart && flutter test test/data/reprocess_schema_migration_test.dart` falla porque faltan columnas, snapshot, reanudación de etapa o conservación del resultado publicado | T005, T007, T009 | spec §Acceptance #5, #12–#15 |
| T011 |  | Implementar migración y reprocesamiento durable | `cd diktafon && flutter test test/services/job_queue_cloud_reprocess_test.dart && flutter test test/data/reprocess_schema_migration_test.dart` pasa; reanudar desde `pendingTranscript` no repite transcripción y la transacción publica resultados, borra el trabajo viejo y encola el resumen de casete | T010 | spec §Acceptance #3, #5, #9–#15 |
| T012 |  | Escribir pruebas de Ajustes y proveedores | `cd diktafon && flutter test test/presentation/cloud_provider_settings_test.dart` falla si faltan opciones, estado, prompt, destino o bloqueo por credenciales | T003, T005, T007, T009 | spec §Acceptance #1–#2, #4, #6–#11, #15 |
| T013 |  | Implementar Ajustes de proveedores | `cd diktafon && flutter test test/presentation/cloud_provider_settings_test.dart` pasa; selección persistente e indicador no requieren confirmación modal en cada solicitud | T012 | spec §Acceptance #1–#2, #4, #6–#11, #15 |
| T014 |  | Escribir pruebas de acciones de biblioteca | `cd diktafon && flutter test test/presentation/cloud_reprocess_actions_test.dart` falla si la nota/casete no muestra destino antes de encolar o modifica datos prematuramente | T011, T013 | spec §Acceptance #3, #5, #9, #12–#14 |
| T015 |  | Implementar acciones de reprocesamiento | `cd diktafon && flutter test test/presentation/cloud_reprocess_actions_test.dart` pasa; la nota y el casete ejecutan solo la acción solicitada | T014 | spec §Acceptance #3, #5, #9, #12–#14 |
| T016 |  | Completar traducciones y errores seguros | `cd diktafon && flutter test test/l10n_parity_test.dart` pasa; pantallas y errores cubren los idiomas del proyecto y no exponen tokens | T013, T015 | spec §Acceptance #1–#15 |
| T017 |  | Ejecutar la verificación completa | `cd diktafon && dart format --set-exit-if-changed lib test && flutter analyze && flutter test` termina con código 0; prueba de humo Android cubre Whisper local y las rutas nube configuradas | T016 | spec §Acceptance #1–#15 |

**Interfaces por tarea**

- **T003 — Interfaces**
  - Consume: `SettingsRepository.get() -> AppSettings`; `CredentialVault.get(provider) -> Secret?`.
  - Produce: preferencias globales persistentes sin claves; operaciones `put/get/remove` protegidas para Gemini y ChatGPT.
- **T005 — Interfaces**
  - Consume: `TranscriptionProvider.transcribe(AudioRef, languageCode, cancel)` y clave Gemini desde `CredentialVault`.
  - Produce: adaptador Gemini que devuelve `Transcript` con idioma y tiempos compatibles, o un error tipado sin mutar `Memo`.
- **T007 — Interfaces**
  - Consume: `SummarizationProvider.summarizeMemo(Transcript, languageCode)` y `updateCassetteSummary(previousSummary, newMemos, languageCode)`.
  - Produce: adaptadores Gemini y ChatGPT que devuelven texto o error; ChatGPT recibe solo texto y requiere modelo del catálogo autorizado.
- **T009 — Interfaces**
  - Consume: credenciales protegidas y callback de navegador con `code`, `state` y `client_id`.
  - Produce: sesión validada con scopes, access/refresh token y catálogo de modelos; error de autorización/catálogo sin activar cuenta parcial.
- **T011 — Interfaces**
  - Consume: proveedores y acciones `retranscribeMemo`, `regenerateMemoSummary`, `regenerateCassetteSummary`; `Jobs.configSnapshot`; `Memos.pendingTranscript` y `Memos.pendingMemoSummary`.
  - Produce: migración SQLite v3→v4 que añade esas tres columnas anulables; el trabajo `reprocessMemo` avanza a `summarizeReprocessedMemo`; publicación atómica y limpieza de los dos campos provisionales.
  - Invariante: si la etapa `summarizeReprocessedMemo` se reanuda y `pendingTranscript != null`, no vuelve a leer/transcribir el audio; si cualquier etapa falla, `transcript` y `memoSummary` publicados no cambian. Al publicar, la misma transacción elimina el trabajo pendiente y encola la actualización del casete.
- **T013 — Interfaces**
  - Consume: `ProviderPreferences`, estado del `CredentialVault` y estados de conexión.
  - Produce: selección persistente, editor de instrucciones, proveedor activo y aviso de datos/destino antes de la acción.
- **T015 — Interfaces**
  - Consume: `JobQueue.retranscribeMemo(memoId)`, `regenerateMemoSummary(memoId)`, `regenerateCassetteSummary(cassetteId)`.
  - Produce: acciones de biblioteca que encolan solo la operación elegida y dejan contenido sin cambios hasta éxito.

## Review Workload Forecast

| Dimensión | Estimación | Motivo |
| --- | --- | --- |
| Líneas modificadas | 750–1.150 | dos proveedores Gemini, OAuth ChatGPT, migración durable, UI, traducciones y pruebas |
| Archivos / áreas | 19–27 | servicios, base de datos/repositorios, cola, Ajustes, biblioteca, ARB y pruebas |
| Riesgo de revisión | alto | credenciales, OAuth móvil, transferencia de audio y retención de resultados |
| Entrega sugerida | ask-on-risk | supera el presupuesto de 400 líneas / 12 archivos de `sdd/config.yaml`; validar el spike y hacer revisión por hitos |
