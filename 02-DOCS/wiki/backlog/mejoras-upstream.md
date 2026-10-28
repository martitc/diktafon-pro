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
| Mejora propuesta — Google Drive y sincronización con escritorio | Subir o respaldar audios en carpetas nombradas según los casetes, para recuperarlos y compartirlos más adelante con una app de escritorio. Definir también cómo sincronizar transcripciones, resúmenes y cambios, cómo resolver conflictos, y cómo restaurar copias. | Objetivo de fase futura; excluido explícitamente de los planes Android aprobados actuales. Requiere una spec propia de OAuth, permisos mínimos, estructura de carpetas, estrategia de copia/restauración y sincronización bidireccional. |
| Mejora propuesta — grabación de llamadas telefónicas | Grabar conversaciones telefónicas desde la app | Pendiente para una fase posterior a la estabilización de Diktafon Pro. Antes hay que comprobar qué permiten Android y Google Play en los dispositivos objetivo y definir consentimiento, privacidad y requisitos legales por país. |

No se han escrito comentarios, cerrado issues ni publicado cambios en el repositorio original.
