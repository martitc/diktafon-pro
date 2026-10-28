/// Imports selected audio files into one cassette as new memos.
library;

import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:uuid/uuid.dart';

import '../../data/files/audio_file_store.dart';
import '../../data/repositories/cassette_repository.dart';
import '../../data/repositories/memo_repository.dart';
import '../../domain/models.dart';

class LocalAudioImportResult {
  const LocalAudioImportResult({
    required this.imported,
    required this.failures,
    required this.transcriptionFailures,
  });

  final int imported;
  final int failures;
  final int transcriptionFailures;
}

class LocalAudioImporter {
  LocalAudioImporter({
    required this._files,
    required this._cassettes,
    required this._memos,
    required this._probeDurationMs,
    required this._enqueueTranscription,
  });

  final AudioFileStore _files;
  final CassetteRepository _cassettes;
  final MemoRepository _memos;
  final Future<int?> Function(String path) _probeDurationMs;
  final Future<void> Function(String memoId) _enqueueTranscription;
  final _uuid = const Uuid();

  /// Copies each selected file into app-private storage before saving its
  /// memo. Individual failures do not stop the remaining selected files.
  Future<LocalAudioImportResult> importFiles(
    String cassetteId,
    List<XFile> selectedFiles,
  ) async {
    var imported = 0;
    var failures = 0;
    var transcriptionFailures = 0;
    var previousCreatedAt = DateTime.now().subtract(
      const Duration(milliseconds: 1),
    );

    for (final selected in selectedFiles) {
      final memoId = _uuid.v4();
      String? destination;
      var memoSaved = false;

      try {
        destination = await _files.pathFor(
          cassetteId,
          memoId,
          extension: _extension(selected.name),
        );
        await selected.openRead().cast<List<int>>().pipe(
          File(destination).openWrite(),
        );

        final durationMs = await _probeDurationMs(destination);
        if (durationMs == null || durationMs <= 0) {
          throw const FormatException('Could not read audio duration');
        }

        final createdAt = _nextCreatedAt(previousCreatedAt);
        await _memos.insert(
          Memo(
            id: memoId,
            cassetteId: cassetteId,
            filePath: destination,
            durationMs: durationMs,
            createdAt: createdAt,
            status: MemoStatus.stored,
          ),
        );
        memoSaved = true;
        previousCreatedAt = createdAt;
        imported++;
      } catch (_) {
        failures++;
        if (!memoSaved && destination != null) {
          try {
            await _files.deleteMemoFile(destination);
          } catch (_) {
            // The failed import stays unreferenced and is cleaned by the
            // audio-store orphan sweep on a later launch.
          }
        }
        continue;
      }

      try {
        await _cassettes.touch(cassetteId);
        await _enqueueTranscription(memoId);
      } catch (_) {
        transcriptionFailures++;
      }
    }

    return LocalAudioImportResult(
      imported: imported,
      failures: failures,
      transcriptionFailures: transcriptionFailures,
    );
  }

  DateTime _nextCreatedAt(DateTime previous) {
    final now = DateTime.now();
    if (now.millisecondsSinceEpoch > previous.millisecondsSinceEpoch) {
      return now;
    }
    return DateTime.fromMillisecondsSinceEpoch(
      previous.millisecondsSinceEpoch + 1,
    );
  }

  String _extension(String name) {
    final dot = name.lastIndexOf('.');
    if (dot < 0 || dot == name.length - 1) return 'm4a';
    final extension = name.substring(dot + 1).toLowerCase();
    return RegExp(r'^[a-z0-9]{1,8}$').hasMatch(extension) ? extension : 'm4a';
  }
}
