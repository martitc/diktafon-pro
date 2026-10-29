import 'dart:async';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:diktafon/data/db/database.dart';
import 'package:diktafon/data/files/audio_file_store.dart';
import 'package:diktafon/data/repositories/cassette_repository.dart';
import 'package:diktafon/data/repositories/memo_repository.dart';
import 'package:diktafon/data/repositories/settings_repository.dart';
import 'package:diktafon/domain/models.dart';
import 'package:diktafon/services/import/cassette_importer.dart';
import 'package:diktafon/services/processing/job_queue.dart';
import 'package:diktafon/services/providers/transcription_provider.dart'
    show ModelStatus;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'job_queue_test.dart'
    show
        FakeSummarizationProvider,
        FakeTranscriptionProvider,
        longTranscript,
        shortTranscript;

void main() {
  late AppDatabase db;
  late MemoRepository memos;
  late CassetteRepository cassettes;
  late SettingsRepository settings;
  late FakeTranscriptionProvider engine;
  late FakeSummarizationProvider llm;
  late JobQueue queue;
  late Cassette cassette;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    memos = MemoRepository(db);
    cassettes = CassetteRepository(db);
    settings = SettingsRepository(db);
    engine = FakeTranscriptionProvider();
    llm = FakeSummarizationProvider();
    queue = JobQueue(
      db,
      memos,
      cassettes,
      settings,
      () => engine,
      () => llm,
      retryDelayUnit: Duration.zero,
    );
    cassette = await cassettes.create();
  });

  tearDown(() => db.close());

  Future<void> seed({bool long = false}) => memos.insert(
    Memo(
      id: 'memo',
      cassetteId: cassette.id,
      filePath: '/unused.m4a',
      durationMs: 1000,
      createdAt: DateTime.now(),
      status: MemoStatus.ready,
      transcript: long
          ? longTranscript('es', ['Original'])
          : shortTranscript('es', 'Texto anterior'),
      memoSummary: 'Resumen anterior',
    ),
  );

  test(
    'failed retranscription preserves previous text and retries transcription',
    () async {
      await seed();
      engine.failuresBeforeSuccess = 99;
      await queue.retranscribeCassette(cassette.id);
      await queue.drain();
      var memo = (await memos.memosOf(cassette.id)).single;
      expect(memo.status, MemoStatus.failed);
      expect(memo.transcript?.plainText, 'Texto anterior');
      expect(memo.memoSummary, 'Resumen anterior');
      expect(engine.calls, 5);

      engine.failuresBeforeSuccess = 0;
      engine.result = shortTranscript('es', 'Texto nuevo');
      await queue.retryEnrichment('memo');
      await queue.drain();
      memo = (await memos.memosOf(cassette.id)).single;
      expect(engine.calls, 6);
      expect(memo.transcript?.plainText, 'Texto nuevo');
      expect(memo.memoSummary, isNull);
      expect(memo.status, MemoStatus.ready);
    },
  );

  test('editing discards an in-flight summary of the old transcript', () async {
    await seed(long: true);
    llm.gate = Completer<void>();
    llm.memoResult = 'Resumen obsoleto';
    await queue.retryEnrichment('memo');
    while (llm.memoCalls == 0) {
      await Future<void>.delayed(Duration.zero);
    }
    await queue.applyTranscriptEdit(
      'memo',
      shortTranscript('es', 'Texto editado'),
    );
    llm.gate!.complete();
    await queue.drain();
    final memo = (await memos.memosOf(cassette.id)).single;
    expect(memo.transcript?.plainText, 'Texto editado');
    expect(memo.memoSummary, isNull);
    expect(memo.status, MemoStatus.ready);
    expect(
      (await cassettes.watchCassette(cassette.id).first)?.summary,
      contains('Texto editado'),
    );
  });

  test(
    'retranscription discards an in-flight summary even when transcription fails',
    () async {
      await seed(long: true);
      llm.gate = Completer<void>();
      llm.memoResult = 'Resumen obsoleto';
      await queue.retryEnrichment('memo');
      while (llm.memoCalls == 0) {
        await Future<void>.delayed(Duration.zero);
      }
      engine.failuresBeforeSuccess = 99;
      await queue.retranscribeCassette(cassette.id);
      llm.gate!.complete();
      await queue.drain();
      final memo = (await memos.memosOf(cassette.id)).single;
      expect(memo.memoSummary, 'Resumen anterior');
      expect(memo.transcript?.plainText, startsWith('Original'));
      expect(memo.status, MemoStatus.failed);
    },
  );

  test(
    'a queued retranscription survives restart without discarding old text',
    () async {
      await seed();
      engine.status = ModelStatus.notInstalled;
      await queue.retranscribeCassette(cassette.id);
      await queue.drain();
      expect(
        (await memos.memosOf(cassette.id)).single.memoSummary,
        'Resumen anterior',
      );
      final jobs = await db.select(db.jobs).get();
      expect(jobs.single.type, JobType.transcribe.name);
      engine.status = ModelStatus.ready;
      engine.result = shortTranscript('es', 'Tras reiniciar');
      final resumed = JobQueue(
        db,
        memos,
        cassettes,
        settings,
        () => engine,
        () => llm,
      );
      await resumed.drain();
      expect(
        (await memos.memosOf(cassette.id)).single.transcript?.plainText,
        'Tras reiniciar',
      );
    },
  );

  test(
    'a successful silent retranscription clears obsolete summaries',
    () async {
      await seed();
      await cassettes.setSummary(cassette.id, 'Resumen del casete anterior');
      engine.result = const Transcript(languageCode: 'es', segments: []);
      await queue.retranscribeCassette(cassette.id);
      await queue.drain();
      final memo = (await memos.memosOf(cassette.id)).single;
      expect(memo.transcript?.isEmpty, true);
      expect(memo.memoSummary, isNull);
      expect(
        (await cassettes.watchCassette(cassette.id).first)?.summary,
        isNull,
      );
    },
  );

  test(
    'editing discards transcription from an engine ignoring cancellation',
    () async {
      await seed();
      engine.gate = Completer<void>();
      await queue.retranscribeCassette(cassette.id);
      while (engine.calls == 0) {
        await Future<void>.delayed(Duration.zero);
      }
      await queue.applyTranscriptEdit(
        'memo',
        shortTranscript('es', 'Edición conservada'),
      );
      engine.gate!.complete();
      await queue.drain();
      expect(
        (await memos.memosOf(cassette.id)).single.transcript?.plainText,
        'Edición conservada',
      );
    },
  );

  test(
    'ZIP import rejects nested symlinks before writing outside staging',
    () async {
      final outside = await Directory.systemTemp.createTemp(
        'audit-p1-outside-',
      );
      final zipDir = await Directory.systemTemp.createTemp('audit-p1-zip-');
      final sentinel = File('${outside.path}/sentinel.txt');
      await sentinel.writeAsString('original');
      try {
        ArchiveFile link(String name, String target) =>
            ArchiveFile(name, target.length, target.codeUnits)..mode = 0xa1ff;
        final archive = Archive()
          ..add(ArchiveFile.directory('a/'))
          ..add(ArchiveFile.directory('a/b/'))
          ..add(link('a/b/c', '..'))
          ..add(
            link(
              'a/b/c/d',
              '../../${outside.uri.pathSegments.where((s) => s.isNotEmpty).last}',
            ),
          )
          ..add(ArchiveFile('a/b/c/d/sentinel.txt', 7, 'changed'.codeUnits));
        final zip = File('${zipDir.path}/malicious.zip');
        final bytes = ZipEncoder().encode(archive);
        // ZipEncoder writes DOS creator metadata. Mark the central-directory
        // records as Unix so the link modes are interpreted by a ZIP reader.
        for (var i = 0; i + 5 < bytes.length; i++) {
          if (bytes[i] == 0x50 &&
              bytes[i + 1] == 0x4b &&
              bytes[i + 2] == 1 &&
              bytes[i + 3] == 2) {
            bytes[i + 5] = 3;
          }
        }
        expect(
          ZipDecoder().decodeBytes(bytes).find('a/b/c')?.isSymbolicLink,
          isTrue,
        );
        await zip.writeAsBytes(bytes);
        final importer = CassetteImporter(
          cassettes: cassettes,
          memos: memos,
          files: AudioFileStore(Directory('${zipDir.path}/audio')),
          enqueueTranscription: (_) async {},
          retryEnrichment: (_) async {},
        );
        await expectLater(importer.importArchive(zip), throwsFormatException);
        expect(await sentinel.readAsString(), 'original');
        expect(await cassettes.watchOverviews().first, hasLength(1));
      } finally {
        await outside.delete(recursive: true);
        await zipDir.delete(recursive: true);
      }
    },
  );
}
