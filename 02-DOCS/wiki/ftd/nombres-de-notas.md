---
author: git user.name not configured
branch: main
status: in-progress
---
# Nombres de notas

## Intent
Permitir que cada nota tenga un nombre legible y propio. Si la persona no lo cambia, usar una frase corta de la transcripción como nombre automático.

## Scope
Mostrar el nombre junto a la fecha en cada separador de nota. Añadir una acción para renombrar desde el menú de la nota. Guardar solo el nombre manual en el almacenamiento local; el nombre automático se deriva de la transcripción y se actualiza cuando esta cambia. Exportar e importar el nombre manual.

Un nombre manual siempre prevalece sobre el automático. Si se borra, vuelve a mostrarse el nombre derivado de la transcripción o el ordinal mientras no haya transcripción.

## Checklist
- [x] Conservar el nombre manual en la base local y reflejar cambios en la cinta.
- [x] Derivar un nombre breve de la primera frase transcrita; mantener el ordinal mientras no haya transcripción.
- [x] Añadir renombrado en el menú y copiar el nombre manual al exportar e importar.
- [x] Revisar diferencias con `git diff --check`; no ejecutar pruebas automatizadas.

## Evidence
`Memo.automaticTitle` deriva el nombre de la transcripción y `Memo.title` conserva la elección manual en las filas existentes de ajustes. La vista de cinta prioriza el nombre manual, después el automático y finalmente «Nota N». El menú permite renombrar o volver al automático. El exportador añade el título al manifiesto y lo usa en el encabezado legible; el importador lo restaura.

La traza reproducida en el X7 Pro mostró que el `TextEditingController` del diálogo se disponía antes de que terminara la animación de cierre. El nuevo `_RenameMemoDialog` conserva el controlador hasta `State.dispose`. `flutter analyze --no-pub` no encontró incidencias. La APK debug arm64 actualizada se compiló y se instaló por ADB sobre la instalación existente. No se ejecutaron pruebas automatizadas.

## Next
Confirmar en el X7 Pro que el flujo de renombrado ya no muestra el error rojo.
