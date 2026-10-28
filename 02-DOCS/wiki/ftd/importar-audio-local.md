---
author: git user.name not configured
branch: main
status: in-progress
---
# Importar audio local

## Intent
Seleccionar audios guardados en el móvil e incorporarlos al casete abierto como notas reproducibles y transcribibles.

## Scope
Añadir una acción en el menú del casete para elegir uno o varios archivos de audio del dispositivo. Copiar cada archivo al almacenamiento privado de la app, añadirlo a la cinta y encolarlo para transcripción local. Mostrar resultados y errores con mensajes localizados en español e inglés. El archivo original no se modifica.

No incluye Google Drive, Gemini API, la aplicación de macOS ni cambios al formato de exportación.

## Checklist
- [x] Añadir una acción para elegir uno o varios audios desde el selector del sistema; cancelar deja la cinta intacta.
- [x] Copiar cada audio a almacenamiento privado, añadir una nota al casete abierto y encolar su transcripción local.
- [x] Mostrar resultados parciales para importaciones fallidas y avisar si una transcripción no se pudo encolar.
- [ ] Compilar y comprobar el selector en Android.

## Evidence
`git diff --check` y el análisis JSON de `app_en.arb` y `app_es.arb` finalizaron sin errores. El selector `openFiles` devuelve una lista vacía al cancelar, según la [API de file_selector](https://pub.dev/documentation/file_selector/latest/file_selector/openFiles.html). No hay Flutter ni Dart en PATH, así que no se pudo compilar ni comprobar la interfaz en un dispositivo.

## Next
Validar en Android cuando haya un SDK Flutter y un dispositivo o emulador disponibles.
