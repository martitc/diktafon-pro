---
type: progress
title: Progreso — Proveedores de transcripción y resúmenes
timestamp: 2026-10-27
topic: sdd
slug: resumenes-con-proveedores
---

## T001 — inicio 2026-10-27

- status: in_progress
- autorización: la persona aprobó la revisión A1 y pidió implementar.
- entorno: macOS arm64; no se detectan Flutter, Dart, adb ni Java instalados. SDK Flutter 3.44.0 oficial clonado en `/tmp/diktafon-flutter`; preparando Dart.
- dispositivo: la persona eligió probar con un móvil Android por USB.
- límites: validación real de OAuth/Gemini pendiente de dispositivo y autorización de cuenta. No se declaran pruebas reales de proveedor completadas.
- skill_resolution: implement, flutter, openai-docs. Conservar arquitectura actual; red→green; proteger credenciales; registrar evidencia real.

## T001 — avance de entorno y prototipo 2026-10-27

- status: in_progress
- entorno: Flutter 3.44.9 / Dart 3.12.2 en `/tmp/diktafon-flutter`; Android SDK36, NDK28.2.13676358, CMake3.22.1 y Temurin21 locales. La persona aceptó expresamente la licencia Android antes de instalar paquetes.
- prototipo: retorno local OAuth con state/nonce/PKCE; intercambio con firma RS256/JWKS, scopes, catálogo, renovación y revocación; prueba Gemini con audio breve e instrucciones y tiempos estructurados. Estos módulos aún no están conectados a los Ajustes de la app principal.
- pruebas: 14 loopback +21 OAuth +9 Gemini pasan con servidores locales simulados. No equivalen a validar una cuenta o un audio reales. El rojo Gemini inicial por import ausente no se cuenta como prueba funcional; posteriormente se ejercitó un stub compilable.
- revisión: se reprodujeron y corrigieron dos P2: cuerpo HTTP de error sin fin, y refresh token candidato perdido al fallar validación. Revisión posterior confirmó ambos cerrados. Los errores no incluyen tokens ni respuestas del proveedor.
- base: 72 pruebas previas de repositorios/cola pasan. Paridad de20idiomas pasa tras completar5mensajes de importación que faltaban. Análisis global Flutter sin incidencias.
- compilación: APK principal `artifacts/DiktafonPro.apk` y diagnóstico `artifacts/DiktafonPro-Conexiones.apk` construidas y etiquetas/identificadores comprobados. Ambos archivos copiados a Descargas del móvil por solicitud de la persona tras bloquear el teléfono la instalación por USB.
- suite completa: primer pase309correctas/22omitidas/7fallidas. Fallos aislados a finders que confunden título automático con transcripción, y fixtures de selectores que cargan el motor nativo no disponible en macOS. Correcciones en curso sin eliminar aserciones.
- bloqueo de T001: falta instalación manual y comprobación OAuth/Gemini reales en el teléfono. La persona tiene la pantalla de pruebas y selecciona los datos enviados; no se solicita ninguna clave por el chat.
- skill_resolution: implement, flutter, openai-docs, debug. El rol developer no pudo arrancar porque su modelo configurado no es compatible con esta cuenta; ejecución y revisiones delegadas a workers con propiedad de archivos explícita.

## T001 — verificación y distribución de prueba 2026-10-27

- status: in_progress
- suite completa tras corregir los fixtures: 317 correctas, 22 omitidas, 0 fallidas. Las omisiones requieren modelos o motores reales externos. Análisis global Flutter sin incidencias y diff sin errores de espacios.
- revisión independiente de las correcciones de pruebas: sin hallazgos materiales; se mantienen las comprobaciones de selección, descarga y transcripción.
- instalación: la persona comunica un aviso de desarrollador no reconocido o aplicación no segura. No se ha verificado aún el texto exacto ni se da por instalado el prototipo.
- siguiente paso autorizado: preparar distribución de prueba mediante su cuenta existente de Google Play. Se intentará compartir las APK internamente; no hay autorización para una publicación pública.
- T001 sigue pendiente de comprobar OAuth y Gemini con una cuenta y un audio reales en Android.

## T001 — bloqueo de cuenta Google Play 2026-10-27

- La persona inició sesión en Play Console y autorizó continuar con la distribución de prueba.
- Se intentó subir `DiktafonPro-Conexiones.apk` mediante compartir aplicaciones internamente. Google rechazó la validación porque el paquete no está publicado ni autorizado para esa función; no se generó un enlace de instalación.
- Al revisar la cuenta, Play Console indica «Google no ha podido verificar tu identidad», cuenta restringida desde el 22 de octubre de 2024 y cambios sin publicación. La solución indicada es presentar un nuevo documento conforme al correo de Google Payments.
- Se dejó abierta la página de solución para que la persona complete personalmente la verificación. No se enviaron documentos de identidad ni se presentó una apelación.
- Evidencia local: `artifacts/google-play-verificacion-pendiente.png`. No se creó una publicación pública ni una versión de prueba disponible.
- T001 permanece pendiente de instalación y pruebas reales; este bloqueo afecta a la distribución mediante esta cuenta de Google Play.

## T001 — pruebas reales en el teléfono 2026-10-28

- ChatGPT: la captura de pantalla muestra conexión y renovación correctas, catálogo de 8 modelos y Luna disponible. La app cerró la sesión de prueba; no hay evidencia de que el resumen ya esté conectado en la app principal.
- Gemini: el selector dejó elegir `AUD-20250805-WA0005.oga`, pero el prototipo lo rechazó localmente porque faltaba mapear la extensión OGA. No se envió ese audio a Google. Añadido OGA al selector con `audio/ogg` conforme al catálogo oficial de formatos de Gemini; M4A conserva `audio/m4a`.
- Artefacto de diagnóstico actualizado: `artifacts/DiktafonPro-Conexiones.apk` (paquete `io.github.martitc.diktafonpro.connections`, versión1.0.9, código102). Compilación Android completada; aún no se ha instalado ni probado en el móvil.
- Whisper: captura de pantalla muestra aserción Flutter `_dependents.isEmpty` al reintentar transcripción. El mensaje no incluye stack trace y el teléfono estaba desconectado al intentar leer ADB. Hace falta reproducir con el móvil conectado y capturar `logcat` para identificar la causa exacta.
- Evidencia: el usuario proporcionó tres capturas; las dos de conexiones muestran el flujo ChatGPT completado y OGA bloqueado antes del envío. No se guardan claves de API en el informe.

## T001 — diagnóstico del renombrado 2026-10-28

- Contexto confirmado por la persona: la pantalla roja apareció al renombrar una nota, no al reintentar Whisper. Se conectó el X7 Pro y Flutter attach permitió reproducirlo.
- Causa raíz: `_renameMemo` disponía el `TextEditingController` cuando `showDialog` completaba el `Future`, pero la ruta del diálogo seguía montada durante la animación de salida. La reconstrucción de `TextField` usaba entonces un controlador ya eliminado. La cascada generaba avisos secundarios de claves GlobalKey duplicadas y `_dependents.isEmpty`.
- Corrección: el nuevo `_RenameMemoDialog` es dueño del controlador y lo libera en `State.dispose`, cuando Flutter ha retirado el diálogo del árbol.
- Verificación: `flutter analyze --no-pub` sin incidencias; APK principal debug arm64 compilada y actualización instalada por ADB con `Success`. No se ejecutaron pruebas automatizadas.
- Nuevo SHA-256 de `artifacts/DiktafonPro.apk`: `83f393cc6388d50885912e05bafd3b5efd39626055fc3da1c1270ecde29a57a9`.
- Pendiente: que la persona confirme que puede renombrar una nota en el build actualizado. Después, instalar la APK de Conexiones actualizada para reintentar Gemini con OGA/M4A. Grabación de conversaciones telefónicas añadida al backlog para una fase posterior.

## T001 — seguimiento de transcripción extensa y prueba Gemini 2026-10-28

- La persona confirma que el renombrado ya funciona y que pudo importar un M4A de una hora; la transcripción seguía en curso y la app permanecía abierta. Solicita aviso del sistema al terminar cada etapa.
- Avisos implementados para transcripción y resumen de nota, con textos localizados en los 20 idiomas. No incluyen contenido privado. `flutter analyze --no-pub` pasó; APK principal compilada e instalada.
- La prueba de Conexiones rechazó OGA con un error genérico y no permitió elegir M4A. El filtro del selector ahora usa `audio/*` y `public.audio`, además de las extensiones aceptadas. Los errores Gemini ahora distinguen timeout/red de rechazo HTTP. Se recompiló e instaló la APK de Conexiones.
- Resultado seguro local anterior: Gemini falló y ChatGPT/retorno fueron correctos; no conserva el detalle de la causa ni datos del audio. La nueva versión aún requiere repetir manualmente el envío OGA/M4A; no se da la conexión Gemini por validada.
- Evidencia de distribución: `artifacts/DiktafonPro.apk` SHA-256 `0ebc897369d8f5d19caeeac4647ad94c8e9a57f7ef5b5658262bf03bdb173005`; `artifacts/DiktafonPro-Conexiones.apk` SHA-256 `8f56183bbb9bd4dfd632173cb45cc8df4e1687d5a83773cd1b81fcafd0d66470`. Instalación por ADB confirmada durante esta sesión de trabajo.
- Pendiente: confirmar los avisos en Android y repetir la muestra Gemini con un audio breve. No se accedió a la clave API ni se ejecutaron pruebas automatizadas del cambio de notificaciones.

## T001 — pruebas Gemini con emulador 2026-10-28

- Se instaló el emulador oficial Android 16/API 36 ARM64 y se creó el AVD Pixel 7 `DiktafonPro_API36`. ADB lo detecta como `emulator-5554`; ambas APK se instalaron y abrieron.
- La persona probó `gemini-3.6-flash` con el WAV de campana incluido en el proyecto y obtuvo HTTP 503. Google clasifica 503 como indisponibilidad temporal; las cuotas agotadas suelen responder 429. El cuerpo HTTP se descarta deliberadamente en la prueba, así que no se guardó detalle del servidor.
- Con la misma clave en el emulador, `gemini-2.5-flash` procesó primero la campana y devolvió 0 palabras (`und`), y después una frase española sintética de 152596 bytes: 13 palabras, idioma `es` y tiempos válidos. La metadata local confirma `passed: true, count: 13`; no guarda clave, audio ni transcripción. Esto confirma acceso a la API y a 2.5 Flash en el proyecto del usuario.
- La prueba anterior de `gemini-3.5-transcribe-live` en el teléfono obtuvo HTTP 400. El código de la prueba usa `models/{model}:generateContent`; la documentación reserva `gemini-3.5-transcribe-live` para Live API/streaming. Para procesar archivos, el modelo dedicado es `gemini-3.5-transcribe` y usa Interactions API. El mismatch de protocolo explica probablemente el 400; la respuesta exacta no se conserva.
- Conclusión: no hay evidencia de que la cuota general esté agotada. `gemini-2.5-flash` sí funciona para una transcripción con voz. `gemini-3.6-flash` debe repetirse más tarde para comprobar si el 503 fue temporal. No se modificó código para soportar Interactions o Live API.

## T007/T013 — Gemini para resúmenes 2026-10-28

- status: implementation and emulator smoke complete; GitHub release pending.
- gap fixed: el plan aprobado incluía Gemini para resúmenes, pero la app principal solo exponía Qwen local y ChatGPT OAuth.
- implementation: nuevo `GeminiSummaryProvider` para GenerateContent; envía texto de transcripción/digests e instrucciones, nunca audio. Usa la clave del `CredentialVault`, errores tipados y sin fallback.
- settings: proveedor y modelo Gemini de resumen se guardan por separado de los ajustes de transcripción. Gemini muestra selector de modelo, clave API y un campo de instrucciones de resumen con aviso de Free Tier; Qwen/Gemma permanecen en el selector local y ChatGPT OAuth conserva su modelo/razonamiento.
- output placement: el resumen general aparece encima de la reproducción del casete y se expande al tocarlo. Los resúmenes individuales se generan para transcripciones largas; las breves se incorporan directamente al resumen general del casete.
- tests: contrato HTTP (solo texto, clave en header, instrucciones, limpieza de salida y cuota), persistencia de preferencias/modelo/prompt y prueba de widget del selector Gemini.
- live check: el usuario confirma que Gemini 2.5 Flash ya transcribe en su cuenta; falta verificar una solicitud de resumen real en el X7 Pro.
- build: Flutter analysis limpio; suite completa: 327 pruebas correctas, 22 omitidas por depender de motores o muestras externas. APK release ARM64 `1.0.10+11` compilada, instalada y abierta en emulador Android API 36. La interfaz de selección Gemini se verificó visualmente; la llamada real de resumen queda pendiente en el X7 Pro. APK: 33 MB; SHA-256 `fe3ae41ec334375d8b7ebe537d5e3ead683873449067fe50e0e71d829004b398`.
- publicación: la persona autorizó subir código, descripción del repositorio y release a `martitc/diktafon-pro`. El workspace actual no tiene historial Git, así que se prepara el cambio sobre el `main` remoto existente y se preserva su HEAD; publicar ahora está en curso.
