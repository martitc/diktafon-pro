---
type: feature
title: Identidad de Diktafon Pro
timestamp: 2026-10-27
status: in_progress
---

# Identidad de Diktafon Pro

## Intención y alcance

La persona propietaria pidió llamar a la app y al fork **Diktafon Pro**, conservando la atribución a `jaromiru/diktafon`. Esta mejora cambia el nombre visible de Android, el título de la interfaz, las referencias de marca en los idiomas del proyecto, el encabezado del README y el remoto del fork.

El identificador Android de la app propia es `io.github.martitc.diktafonpro`. El diagnóstico de conexiones usa `io.github.martitc.diktafonpro.connections`, para poder probarlo junto a la app original.

## Comprobaciones

- [x] Fork renombrado y verificado: [martitc/diktafon-pro](https://github.com/martitc/diktafon-pro).
- [x] Descripción de GitHub identifica el fork como Diktafon Pro en desarrollo.
- [x] Remoto local `origin` actualizado; `upstream` conserva la app original.
- [x] Nombre visible y referencias de marca actualizados en el código local.
- [x] Verificar nombre e identificador en la APK recién compilada: etiqueta `Diktafon Pro`; paquete `io.github.martitc.diktafonpro`.

## Evidencia y siguiente paso

GitHub devolvió `repository_full_name: martitc/diktafon-pro`, con la misma identidad de repositorio y relación de fork. Captura local de la página: `artifacts/diktafon-pro-github.png`. La APK está compilada y copiada a Descargas del teléfono; la instalación manual queda a cargo de la persona.

El README y los cambios de código siguen locales. No se ha publicado una versión nueva en las tiendas.

## Mejoras futuras

Se revisaron los issues originales y se registraron como candidatos en [el backlog](../backlog/mejoras-upstream.md). Las nuevas funciones requieren su propia selección de alcance.
