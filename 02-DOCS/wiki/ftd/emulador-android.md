---
author: marti
branch: main
status: in-progress
---
# Emulador Android para Diktafon Pro

## Intent
Usar un Android virtual controlable por ADB para repetir pruebas y recoger registros de Diktafon Pro desde el Mac.

## Scope
Instalar el emulador oficial y una imagen ARM64 de Android, crear un dispositivo virtual, comprobar el arranque y dejarlo listo para instalar APKs. El X7 Pro seguirá siendo necesario para validar grabación y comportamiento del fabricante.

## Checklist
- [x] Instalar los componentes oficiales del emulador y una imagen Android ARM64; comprobar que el SDK los registra.
- [x] Crear e iniciar un dispositivo virtual; comprobar que ADB lo detecta.
- [x] Instalar las APK de Diktafon Pro y Conexiones; comprobar que Android las inicia.

## Evidence
El Mac tiene Apple M1 y 16 GB de memoria. El SDK temporal está en `/tmp/diktafon-android-sdk`; se instalaron Emulator 37.2.12 y `system-images;android-36;google_apis;arm64-v8a`.

El AVD `DiktafonPro_API36` usa perfil Pixel 7 y Android 16/API 36. ADB lo detecta como `emulator-5554`. Las dos APK devolvieron `Success` al instalarse; Android abrió ambas actividades, y Conexiones quedó en primer plano.

Para iniciarlo desde Terminal en esta sesión:

```sh
ANDROID_HOME=/tmp/diktafon-android-sdk \
ANDROID_USER_HOME=/tmp/diktafon-android-user \
ANDROID_AVD_HOME=/tmp/diktafon-android-user/avd \
ANDROID_SDK_ROOT=/tmp/diktafon-android-sdk \
/tmp/diktafon-android-sdk/emulator/emulator -avd DiktafonPro_API36 -memory 4096 -gpu host
```

En el entorno aislado, Qt no podía leer el indicador NEON y abortaba al iniciar. El mismo emulador arrancó fuera del aislamiento, con aceleración disponible en el Mac M1.

## Next
Usar el emulador para repetir la prueba Gemini y capturar registros de la app. Validar grabación y peculiaridades del X7 Pro en el teléfono físico.
