---
author: marti
branch: main
status: in-progress
---
# Avisos al completar el procesamiento de audio

## Intent
Avisar al usuario cuando una nota termine de transcribirse o resumirse, para que pueda dejar la app en segundo plano sin tener que comprobarla a mano.

## Scope
Mostrar notificaciones del sistema al completar una transcripción y al completar el resumen de una nota. Reutilizar el permiso y la infraestructura de notificaciones existentes. No añadir preferencias, notificaciones de progreso ni avisos para resúmenes de toda la casete en esta mejora.

## Checklist
- [x] Añadir textos localizados de finalización para los idiomas compatibles; `flutter gen-l10n` y `flutter analyze --no-pub` terminaron sin incidencias.
- [x] Emitir avisos separados para transcripción y resumen completados, sin fallos ni etapas canceladas. El aviso de resumen solo se emite si se generó texto.
- [x] Compilar las APK Android e instalarlas en el X7 Pro; ambas compilaciones finalizaron correctamente.
- [ ] Revisar en el móvil los avisos al terminar una transcripción y un resumen. La revisión manual sigue pendiente.

## Evidence
La app ya inicializa `flutter_local_notifications` en Android y Linux para descargas de modelos. `JobQueue` separa transcripción y resumen de nota; el aviso final debe corresponder a cada etapa y no incluir transcripciones ni contenido privado.

## Evidence
La cola emite eventos de finalización por nota y etapa. El sink reutiliza el permiso ya usado por las notificaciones de descarga, muestra los avisos aunque la app esté en segundo plano y no incluye el contenido del audio ni la transcripción. Los textos existen en los 20 idiomas de la app. `flutter analyze --no-pub` no encontró incidencias; las APK debug arm64 se compilaron y se instalaron por ADB.

## Next
Confirmar manualmente en el teléfono la recepción de los dos avisos. No se ejecutaron pruebas automatizadas para este cambio.
