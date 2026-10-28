import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';

import '../../domain/models.dart';
import '../db/database.dart';
import 'mappers.dart';

class MemoRepository {
  MemoRepository(this._db);

  final AppDatabase _db;

  static const _titlePrefix = 'memo-title:';

  Stream<Map<String, String>> watchTitles() =>
      (_db.select(
        _db.settingsEntries,
      )..where((s) => s.key.like('$_titlePrefix%'))).watch().map(
        (rows) => {
          for (final row in rows)
            row.key.substring(_titlePrefix.length): row.value,
        },
      );

  Future<void> setTitle(String memoId, String? title) async {
    final key = '$_titlePrefix$memoId';
    final clean = title?.trim();
    if (clean == null || clean.isEmpty) {
      await (_db.delete(
        _db.settingsEntries,
      )..where((s) => s.key.equals(key))).go();
      return;
    }
    await _db
        .into(_db.settingsEntries)
        .insertOnConflictUpdate(SettingRow(key: key, value: clean));
  }

  /// Tape order: chronological, append-only (§4.1, D6).
  Stream<List<Memo>> watchMemosOf(String cassetteId) => _memosOfQuery(
    cassetteId,
  ).watch().map((rows) => rows.map(memoFromRow).toList());

  /// One-shot tape-order read (export, §8).
  Future<List<Memo>> memosOf(String cassetteId) async {
    final memos = (await _memosOfQuery(cassetteId).get()).map(memoFromRow);
    final titles = await _readTitles();
    return [for (final memo in memos) memo.withTitle(titles[memo.id])];
  }

  Future<Map<String, String>> _readTitles() async {
    final rows = await (_db.select(
      _db.settingsEntries,
    )..where((s) => s.key.like('$_titlePrefix%'))).get();
    return {
      for (final row in rows) row.key.substring(_titlePrefix.length): row.value,
    };
  }

  SimpleSelectStatement<$MemosTable, MemoRow> _memosOfQuery(
    String cassetteId,
  ) => _db.select(_db.memos)
    ..where((m) => m.cassetteId.equals(cassetteId))
    // id as tie-break keeps tape order deterministic within the same ms.
    ..orderBy([
      (m) => OrderingTerm.asc(m.createdAt),
      (m) => OrderingTerm.asc(m.id),
    ]);

  Future<void> insert(Memo memo) async {
    await _db
        .into(_db.memos)
        .insert(
          MemoRow(
            id: memo.id,
            cassetteId: memo.cassetteId,
            filePath: memo.filePath,
            durationMs: memo.durationMs,
            createdAt: memo.createdAt.millisecondsSinceEpoch,
            detectedLang: memo.detectedLang,
            transcript: memo.transcript == null
                ? null
                : jsonEncode(memo.transcript!.toJson()),
            memoSummary: memo.memoSummary,
            status: memo.status.name,
          ),
        );
    if (memo.title != null) await setTitle(memo.id, memo.title);
  }

  /// Points the memo at its transcoded file (§6.4: capture is WAV, the
  /// archival form is AAC — the transcode job swaps once the encode landed).
  Future<void> updateFilePath(String id, String filePath) =>
      (_db.update(_db.memos)..where((m) => m.id.equals(id))).write(
        MemosCompanion(filePath: Value(filePath)),
      );

  Future<void> updateStatus(String id, MemoStatus status) =>
      (_db.update(_db.memos)..where((m) => m.id.equals(id))).write(
        MemosCompanion(status: Value(status.name)),
      );

  Future<void> setTranscript(
    String id,
    Transcript transcript,
    MemoStatus status,
  ) => (_db.update(_db.memos)..where((m) => m.id.equals(id))).write(
    MemosCompanion(
      transcript: Value(jsonEncode(transcript.toJson())),
      detectedLang: Value(transcript.languageCode),
      status: Value(status.name),
    ),
  );

  /// Manual correction (§6.9): the edited transcript replaces the engine's
  /// take, and the gist that described the old text goes with it — in one
  /// write. The detected language is deliberately untouched: the user fixed
  /// words, not the memo's language.
  Future<void> setEditedTranscript(
    String id,
    Transcript transcript,
    MemoStatus status,
  ) => (_db.update(_db.memos)..where((m) => m.id.equals(id))).write(
    MemosCompanion(
      transcript: Value(jsonEncode(transcript.toJson())),
      memoSummary: const Value(null),
      status: Value(status.name),
    ),
  );

  /// [summary] null → the memo yielded no usable gist (§6.7 skip).
  Future<void> setMemoSummary(String id, String? summary, MemoStatus status) =>
      (_db.update(_db.memos)..where((m) => m.id.equals(id))).write(
        MemosCompanion(memoSummary: Value(summary), status: Value(status.name)),
      );

  /// Wipes every enrichment artifact so the memo re-enters the pipeline
  /// from scratch (re-transcribe with a newly installed model): transcript,
  /// preserved raw take, gist and detected language all go; audio stays.
  Future<void> resetEnrichment(String id) =>
      (_db.update(_db.memos)..where((m) => m.id.equals(id))).write(
        MemosCompanion(
          transcript: const Value(null),
          rawTranscript: const Value(null),
          memoSummary: const Value(null),
          detectedLang: const Value(null),
          status: Value(MemoStatus.stored.name),
        ),
      );

  Future<void> delete(String id) async {
    await (_db.delete(
      _db.settingsEntries,
    )..where((s) => s.key.equals('$_titlePrefix$id'))).go();
    await (_db.delete(_db.memos)..where((m) => m.id.equals(id))).go();
  }

  /// Every memo id — the launch sweep uses it to tell live audio files
  /// from orphans (§7.1).
  Future<Set<String>> allIds() async {
    final id = _db.memos.id;
    final rows = await (_db.selectOnly(_db.memos)..addColumns([id])).get();
    return {for (final row in rows) row.read(id)!};
  }

  /// Heals stale absolute audio paths (§7.1): iOS moves the app's data
  /// container on every update/reinstall — the audio files migrate with it,
  /// but paths recorded by an older install keep pointing into the dead
  /// container. A memo whose stored file is gone but whose audio sits at
  /// the canonical `<root>/<cassetteId>/<memoId>.<ext>` under the *current*
  /// root is repointed there. Idempotent, runs at every launch; genuinely
  /// missing audio is left alone.
  Future<int> rebaseAudioPaths(String audioRoot) async {
    final rows = await _db.select(_db.memos).get();
    var rebased = 0;
    for (final row in rows) {
      if (File(row.filePath).existsSync()) continue;
      final slash = row.filePath.lastIndexOf('/');
      final dot = row.filePath.lastIndexOf('.');
      final ext = dot > slash ? row.filePath.substring(dot) : '.m4a';
      final candidate = '$audioRoot/${row.cassetteId}/${row.id}$ext';
      if (candidate == row.filePath || !File(candidate).existsSync()) {
        continue;
      }
      await (_db.update(_db.memos)..where((m) => m.id.equals(row.id))).write(
        MemosCompanion(filePath: Value(candidate)),
      );
      rebased++;
    }
    return rebased;
  }
}
