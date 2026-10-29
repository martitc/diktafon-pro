/// Real Android downloader regression: starting the other model manager must
/// never remove a running task's temporary file. No real model or API key.
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:background_downloader/background_downloader.dart';
import 'package:crypto/crypto.dart';
import 'package:diktafon/services/providers/transcription_provider.dart';
import 'package:diktafon/services/providers/model_download_persistence.dart';
import 'package:diktafon/services/providers/whisper/whisper_model_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() {
    createModelDownloader();
  });

  testWidgets('another catalog cannot erase an active model partial', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: Scaffold()));
    await tester.runAsync(() async {
      final downloader = FileDownloader();
      await downloader.configure(
        androidConfig: [
          (Config.runInForeground, Config.always),
          (Config.useCacheDir, Config.never),
        ],
      );
      final dir = Directory(
        '${(await getApplicationSupportDirectory()).path}/models/recovery-test',
      );
      final payload = Uint8List(8 * 1024 * 1024);
      for (var i = 0; i < payload.length; i++) {
        payload[i] = i % 251;
      }
      final gate = Completer<void>();
      final progressing = Completer<void>();
      var requests = 0;
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) async {
        requests++;
        debugPrint('Recovery server received ${request.method}');
        try {
          request.response.contentLength = payload.length;
          request.response.headers.set('Accept-Ranges', 'bytes');
          request.response.bufferOutput = false;
          for (var offset = 0; offset < payload.length ~/ 2; offset += 262144) {
            request.response.add(payload.sublist(offset, offset + 262144));
            await request.response.flush();
            await Future<void>.delayed(const Duration(milliseconds: 100));
          }
          await gate.future;
          request.response.add(payload.sublist(payload.length ~/ 2));
          await request.response.close();
        } catch (_) {}
      });
      final model = WhisperModel(
        tier: 'recovery-test',
        label: 'Recovery test',
        description: '',
        fileName: 'recovery-test.bin',
        sizeBytes: payload.length,
        sha256Hex: sha256.convert(payload).toString(),
        urlOverride: Uri.parse('http://127.0.0.1:${server.port}/model'),
      );
      final active = WhisperModelManager(dir, catalog: [model]);
      final other = WhisperModelManager(
        Directory('${dir.path}/other'),
        catalog: [],
      );
      active.attachBackgroundTasks();
      other.attachBackgroundTasks();
      await downloader.start(autoCleanDatabase: false);
      Object? failure;
      final download = active
          .download(
            model,
            onProgress: (value) {
              if (value > .1 && !progressing.isCompleted) {
                progressing.complete();
              }
            },
          )
          .catchError((Object error) {
            failure = error;
          });
      try {
        await progressing.future.timeout(const Duration(seconds: 30));
        await other.resumeInterrupted();
        gate.complete();
        await download.timeout(const Duration(seconds: 45));
        expect(requests, 1, reason: 'Cleanup must not force a full redownload');
        expect(
          failure,
          isNull,
          reason: 'Other catalog removed live native temp',
        );
        expect(active.statusOf(model), ModelStatus.ready);
      } finally {
        if (!gate.isCompleted) gate.complete();
        await downloader.cancelTaskWithId('model-${model.tier}');
        await server.close(force: true);
        active.delete(model);
        active.dispose();
        other.dispose();
        if (await dir.exists()) await dir.delete(recursive: true);
      }
    });
  });

  testWidgets('exhausted retries retain valid model resume metadata', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final downloader = FileDownloader();
      final support = await getApplicationSupportDirectory();
      final partial = File(
        '${support.path}/com.bbflight.background_downloader-retry-test',
      );
      await partial.writeAsBytes(Uint8List(2 * 1024 * 1024));
      final task = DownloadTask(
        taskId: 'model-retry-recovery-test',
        url: 'https://example.invalid/model',
        retries: 0,
        group: 'diktafon-models',
      );
      // Exercise the exact plugin terminal-status path, after a native
      // transfer has supplied valid resume data and exhausted its retries.
      final native = downloader.downloaderForTesting;
      await native.setResumeData(
        ResumeData(task, partial.path, partial.lengthSync(), 'etag'),
      );
      native.processStatusUpdate(TaskStatusUpdate(task, TaskStatus.failed));
      // The package schedules metadata removal without awaiting it.
      await Future<void>.delayed(const Duration(milliseconds: 100));
      final retained = await native.getResumeData(task.taskId);
      try {
        expect(
          retained,
          isNotNull,
          reason: 'Network failure must not erase the resume checkpoint',
        );
        expect(retained?.requiredStartByte, partial.lengthSync());
      } finally {
        await partial.delete();
        await native.removeResumeData(task.taskId);
        expect(
          await native.getResumeData(task.taskId),
          isNull,
          reason: 'A missing/consumed partial must not remain resumable',
        );
        await downloader.database.deleteRecordWithId(task.taskId);
      }
    });
  });

  testWidgets(
    'a failed model resumes its retained bytes after manager restart',
    (tester) async {
      await tester.runAsync(() async {
        final downloader = FileDownloader();
        final support = await getApplicationSupportDirectory();
        final payload = Uint8List.fromList(
          List.generate(8 * 1024 * 1024, (i) => i % 251),
        );
        const offset = 2 * 1024 * 1024;
        final ranges = <String?>[];
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        server.listen((request) async {
          ranges.add(request.headers.value(HttpHeaders.rangeHeader));
          final start = int.parse(
            RegExp(r'bytes=(\d+)-').firstMatch(ranges.last ?? '')?.group(1) ??
                '0',
          );
          request.response.statusCode = start > 0 ? 206 : 200;
          request.response.headers.set('Accept-Ranges', 'bytes');
          request.response.headers.set('ETag', '"recovery-test"');
          if (start > 0) {
            request.response.headers.set(
              'Content-Range',
              'bytes $start-${payload.length - 1}/${payload.length}',
            );
          }
          request.response.contentLength = payload.length - start;
          request.response.add(payload.sublist(start));
          await request.response.close();
        });
        final model = WhisperModel(
          tier: 'failed-resume-test',
          label: 'Retained model',
          description: '',
          fileName: 'retained.bin',
          sizeBytes: payload.length,
          sha256Hex: sha256.convert(payload).toString(),
          urlOverride: Uri.parse('http://127.0.0.1:${server.port}/model'),
        );
        final task = DownloadTask(
          taskId: 'model-${model.tier}',
          url: model.url.toString(),
          filename: '${model.fileName}.part',
          directory: 'models/failed-resume-test',
          baseDirectory: BaseDirectory.applicationSupport,
          group: 'diktafon-models',
          updates: Updates.statusAndProgress,
          allowPause: true,
          retries: 0,
        );
        final partial = File(
          '${support.path}/com.bbflight.background_downloader-retained-test',
        );
        await partial.writeAsBytes(payload.sublist(0, offset));
        await modelDownloadPersistence.storeResumeData(
          ResumeData(task, partial.path, offset, '"recovery-test"'),
        );
        await downloader.database.updateRecord(
          TaskRecord(task, TaskStatus.failed, .25, payload.length),
        );
        // New manager, same persistent downloader state, as after reopening.
        final manager = WhisperModelManager(
          Directory('${support.path}/models/failed-resume-test'),
          catalog: [model],
        );
        manager.attachBackgroundTasks();
        try {
          await manager.resumeInterrupted();
          expect(manager.stateOf(model).status, ModelStatus.paused);
          expect(manager.stateOf(model).progress, .25);
          await manager.download(model).timeout(const Duration(seconds: 30));
          expect(ranges, ['bytes=$offset-']);
          expect(manager.statusOf(model), ModelStatus.ready);
          expect(await manager.fileOf(model).readAsBytes(), payload);
        } finally {
          manager.delete(model);
          manager.dispose();
          await modelDownloadPersistence.discard(task.taskId);
          await server.close(force: true);
          if (await partial.exists()) {
            await partial.delete();
          }
        }
      });
    },
  );
}
