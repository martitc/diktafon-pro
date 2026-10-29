---
type: backlog
title: Mejoras solicitadas en Diktafon original
timestamp: 2026-10-27
status: proposed
---

# Mejoras solicitadas en Diktafon original

Consulta de issues abiertos del repositorio original el 2026-10-27. Esta página recoge candidatos; no amplía la entrega de proveedores ya aprobada.

| Issue original | Solicitud | Relación con Diktafon Pro |
| --- | --- | --- |
| [#31 — More flexibility in organising and summarising memos](https://github.com/jaromiru/diktafon/issues/31) | Nombres de notas, idioma de interfaz independiente, transcripciones plegables, prompts por casete y resúmenes editables | Los nombres de notas ya tienen código local; los prompts globales forman parte de la entrega aprobada. Los demás puntos quedan como candidatos. |
| [#32 — Add search functionality](https://github.com/jaromiru/diktafon/issues/32) | Buscar en las transcripciones | Candidato de alto valor para bibliotecas grandes. |
| [#34 — Export android intent or shortcut](https://github.com/jaromiru/diktafon/issues/34) | Iniciar una grabación con acceso directo, intent o tecla física | Candidato Android; requiere definir grabación en segundo plano y permisos. |
| [#39 — Audio Loop](https://github.com/jaromiru/diktafon/issues/39) | Repetir automáticamente el audio al llegar al final | Candidato acotado de reproducción. |
| [#38 — Parakeet TDT 0.6b v3](https://github.com/jaromiru/diktafon/issues/38) | Añadir otro motor de transcripción local | Candidato sujeto a compatibilidad Android, memoria y comparación de precisión. |
| [#30 — Importing local offline models](https://github.com/jaromiru/diktafon/issues/30) | Importar modelos locales sin descargarlos otra vez | Candidato; validar formato, tamaño e integridad antes de cargar motores nativos. |
| [#29 — Allow choosing custom AI model](https://github.com/jaromiru/diktafon/issues/29) | Reutilizar modelos ya descargados en el dispositivo | Relacionado con #30; conviene evaluarlos como una sola mejora. |
| [#33 — Bengali Transcription Support](https://github.com/jaromiru/diktafon/issues/33) | Idioma bengalí para transcripción automática y manual | Candidato de compatibilidad lingüística; no implica traducir toda la interfaz. |
| Mejora propuesta — cliente de escritorio Mac y Windows con Google Drive | Crear un programa para macOS y Windows que sincronice con Android los mismos casetes, audios, transcripciones, resúmenes y configuraciones mediante Google Drive; permitir ordenar y trabajar notas en escritorio y usar los modelos locales más potentes del ordenador para transcribir y resumir con mayor rapidez. | Objetivo confirmado para una fase posterior. No se implementa en esta entrega. Requiere una spec propia para OAuth/permisos mínimos, formato compartido de datos, sincronización bidireccional y conflictos, protección de claves por proveedor, almacenamiento y procesamiento local multiplataforma. |
| Mejora propuesta — grabación de llamadas telefónicas | Grabar conversaciones telefónicas desde la app | Pendiente para una fase posterior a la estabilización de Diktafon Pro. Antes hay que comprobar qué permiten Android y Google Play en los dispositivos objetivo y definir consentimiento, privacidad y requisitos legales por país. |

No se han escrito comentarios, cerrado issues ni publicado cambios en el repositorio original.
