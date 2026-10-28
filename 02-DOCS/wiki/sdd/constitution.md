---
type: constitution
title: Diktafon Pro — Constitution
description: Ratified project rules for the Android app and its future macOS companion.
tags: [sdd, constitution]
timestamp: 2026-10-26
topic: sdd
status: ratified
version: v1.0.0
---

# Diktafon Pro — reglas del proyecto

> Ratificada por la persona propietaria el 2026-10-26. Estas reglas guían las siguientes especificaciones y cambios.

## 1. Stack y alcance

1. La app Android existente se mantiene en Flutter y Dart. Una migración de stack requiere una decisión y especificación propias.
2. La app debe conservar su modo local. Las funciones en la nube son opcionales y se activan desde una elección visible de la persona.

## 2. Calidad y convenciones

3. Cada cambio funcional incorpora una comprobación automatizada adecuada a la capa afectada. Se ejecutan `dart format`, `flutter analyze` y las pruebas Flutter antes de declarar la entrega verificada.
4. Los cambios siguen las capas y convenciones existentes del repo. Cada comportamiento nuevo queda descrito en su especificación y enlazado desde el índice de conocimiento.
5. Las decisiones que afecten arquitectura, privacidad o compatibilidad se registran en `02-DOCS/wiki/sdd/decisions.md`.

## 3. Privacidad y seguridad

6. Las grabaciones y transcripciones permanecen locales salvo que la persona elija una función de nube que necesite esos datos. La interfaz identifica qué contenido se envía y a qué servicio.
7. Las claves de API nunca se guardan en el código, manifiestos, registros ni archivos de exportación. Se almacenan con el mecanismo seguro de la plataforma y se excluyen de los diagnósticos.
8. La integración con un proveedor no sustituye ni desactiva silenciosamente el procesamiento local. Si la nube falla, se conserva el audio y se muestra una acción de reintento.

## 4. Interfaz y accesibilidad

9. Las nuevas pantallas y acciones respetan el estilo, accesibilidad y localización establecidos por Diktafon. No se publica texto visible nuevo sin traducción para los idiomas que mantiene el proyecto.

## 5. Flujo de cambios

10. Los cambios se hacen sobre la rama principal por decisión de la persona. No se crean ramas, se publica código ni se abre un PR sin una instrucción expresa.
11. Los commits y PRs quedan atribuidos a la persona propietaria; no se añade autoría de IA.

## Definición de terminado

- Se cumplen los criterios de aceptación de la especificación aprobada.
- La revisión automatizada aplicable está limpia, o las limitaciones y errores pendientes se describen con claridad.
- La clave y los datos del usuario no aparecen en logs, exportaciones ni cambios versionados.
- La guía del usuario y el registro de decisiones reflejan el comportamiento nuevo cuando corresponde.

## Registro de enmiendas

| Fecha | Versión | Cambio | Motivo |
|---|---|---|---|
| 2026-10-26 | v1.0.0 | Ratificación del borrador preparado a partir del onboarding, el código Flutter existente y la preferencia de conservar opciones locales y en la nube. | Confirmación explícita de la persona propietaria. |
