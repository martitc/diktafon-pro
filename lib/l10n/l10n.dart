/// Convenience seam over gen-l10n (§13): `context.l10n.<key>`.
library;

import 'package:flutter/widgets.dart';

import 'gen/app_localizations.dart';

export 'gen/app_localizations.dart';

extension L10nX on BuildContext {
  AppLocalizations get l10n => AppLocalizations.of(this);
}

/// Local-file import strings. These will move into generated translations
/// when the supported-language catalogue next receives a full translation.
extension LocalAudioImportL10n on AppLocalizations {
  bool get _isSpanish => localeName.toLowerCase().startsWith('es');

  String get renameMemo => _isSpanish ? 'Renombrar nota' : 'Rename memo';
  String get memoName => _isSpanish ? 'Nombre de la nota' : 'Memo name';
  String get memoNameHint => _isSpanish
      ? 'Se usará el nombre de la transcripción'
      : 'Transcript title will be used';
  String get useAutomaticName =>
      _isSpanish ? 'Usar nombre automático' : 'Use automatic name';

  String get importAudio => _isSpanish ? 'Importar audio' : 'Import audio';

  String get importingAudio =>
      _isSpanish ? 'Importando audio…' : 'Importing audio…';

  String importedAudioFiles(int count) {
    if (_isSpanish) {
      return count == 1
          ? 'Audio añadido al casete. La transcripción comenzará automáticamente.'
          : '$count audios añadidos al casete. La transcripción comenzará automáticamente.';
    }
    return count == 1
        ? 'Added 1 audio memo. Transcription starts automatically.'
        : 'Added $count audio memos. Transcription starts automatically.';
  }

  String localAudioImportFailures(int count) {
    if (_isSpanish) {
      return count == 1
          ? 'No se pudo importar 1 archivo de audio.'
          : 'No se pudieron importar $count archivos de audio.';
    }
    return count == 1
        ? '1 audio file could not be imported.'
        : '$count audio files could not be imported.';
  }

  String localAudioTranscriptionFailures(int count) {
    if (_isSpanish) {
      return count == 1
          ? 'Se importó 1 audio, pero no se pudo poner su transcripción en cola.'
          : 'Se importaron $count audios, pero no se pudieron poner sus transcripciones en cola.';
    }
    return count == 1
        ? '1 audio memo was imported, but its transcription could not be queued.'
        : '$count audio memos were imported, but their transcriptions could not be queued.';
  }
}
