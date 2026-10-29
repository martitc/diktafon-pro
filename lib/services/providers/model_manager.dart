/// Model provisioning core (§6.6), shared by the whisper and LLM catalogs:
/// models are downloaded on demand into `<app-support>/models/…` (regenerable
/// — excluded from backup, §7.1) with streamed progress and sha256
/// verification against pinned upstream hashes (a truncated/corrupt model
/// would crash native code).
library;

import 'dart:async';
import 'dart:io';

import 'package:background_downloader/background_downloader.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import 'model_download_storage.dart';
import 'model_download_persistence.dart';
import 'transcription_provider.dart' show ModelStatus, ProgressSink;

/// One downloadable model file, pinned by byte size + sha256.
abstract interface class ModelSpec {
  /// Stable identifier persisted in settings (e.g. 'small', 'qwen3-1.7b').
  String get tier;
  String get label;
  String get description;
  String get fileName;
  int get sizeBytes;
  String get sha256Hex;

  /// Unlisted tiers don't appear in the Settings picker unless installed
  /// (tiny models exist for tests/dev — too weak for real use, §6.6).
  bool get listed;

  Uri get url;

  /// Human size for picker rows, e.g. '181 MB' / '1.8 GB'.
  String get sizeLabel;
}

/// Snapshot of one tier for the Settings picker.
class ModelState<M extends ModelSpec> {
  const ModelState(this.model, this.status, this.progress, {this.failureCode});

  final M model;
  final ModelStatus status;
  final String? failureCode;

  /// Download progress in [0..1]; only meaningful while [status] is
  /// [ModelStatus.downloading] or [ModelStatus.paused] (the fraction already
  /// on disk).
  final double progress;
}

class ModelVerificationException implements Exception {
  const ModelVerificationException(this.message);
  final String message;

  @override
  String toString() => 'ModelVerificationException: $message';
}

/// Completes a download future aborted by [ModelManager.cancel] — callers
/// tell an intentional abort (tier switched mid-download, §5.6) from a
/// real failure and stay quiet about it.
class ModelDownloadCancelled implements Exception {
  const ModelDownloadCancelled();
}

/// Completes a download future halted by [ModelManager.pause]: the partial
/// is stashed on disk (`.paused`) and a later [ModelManager.download] picks
/// it back up. Unlike a plain interruption, a stashed pause is *not*
/// auto-resumed at startup — the user chose to stop (metered connection).
class ModelDownloadPaused implements Exception {
  const ModelDownloadPaused();
}

class InsufficientModelStorage implements Exception {
  const InsufficientModelStorage({
    required this.requiredBytes,
    required this.availableBytes,
  });
  final int requiredBytes;
  final int availableBytes;
}

class ModelNotificationPermissionDenied implements Exception {
  const ModelNotificationPermissionDenied();
}

/// Safe diagnostic codes: never include a signed download URL or response body.
class ModelDownloadFailure implements Exception {
  const ModelDownloadFailure(this.code);
  final String code;

  factory ModelDownloadFailure.fromUpdate(TaskStatusUpdate update) {
    final exception = update.exception;
    final code =
        update.responseStatusCode ??
        (exception is TaskHttpException ? exception.httpResponseCode : null);
    return ModelDownloadFailure(
      code != null && code > 0
          ? 'HTTP $code'
          : switch (exception) {
              TaskConnectionException() => 'NETWORK',
              TaskFileSystemException() => 'STORAGE_IO',
              TaskResumeException() => 'RESUME',
              TaskUrlException() => 'MODEL_URL',
              _ => 'DOWNLOAD_FAILED',
            },
    );
  }
}

class ModelManager<M extends ModelSpec> {
  ModelManager(
    this._dir, {
    HttpClient Function()? httpClientFactory,
    required this.catalog,
    this._stallTimeout = const Duration(seconds: 30),
  }) : _httpClientFactory = httpClientFactory ?? HttpClient.new;

  final Directory _dir;
  final HttpClient Function() _httpClientFactory;

  /// Max body-stream inactivity before the download is failed transiently
  /// (partial kept, resumable) — see the timeout in [_download].
  final Duration _stallTimeout;

  /// The tiers this install knows about; tests swap in local specs.
  final List<M> catalog;

  final _changes = StreamController<void>.broadcast();
  final _installed = StreamController<M>.broadcast();
  final Map<String, double> _progress = {};
  final Map<String, String> _failures = {};
  final Map<String, Future<void>> _downloads = {};
  final Map<String, HttpClient> _clients = {};
  final Set<String> _cancelRequested = {};
  final Set<String> _pauseRequested = {};
  final Map<String, DownloadTask> _nativeTasks = {};
  final Map<String, TaskStatus> _nativeStatus = {};
  final Map<String, int> _nativeResumeOffsets = {};
  final Map<String, Completer<void>> _nativeCompletions = {};
  static StreamSubscription<TaskUpdate>? _sharedNativeUpdates;
  static final Set<void Function(TaskUpdate)> _nativeUpdateListeners = {};
  late final void Function(TaskUpdate) _nativeUpdateListener =
      _handleNativeUpdate;
  bool _backgroundTasksAttached = false;

  /// Emits whenever any tier's status/progress changes.
  Stream<void> get changes => _changes.stream;
  Stream<M> get installed => _installed.stream;

  /// Subscribe before FileDownloader.start(), so persisted completion events
  /// are replayed and validated when Android relaunches the app.
  void attachBackgroundTasks() {
    if (_backgroundTasksAttached) return;
    _backgroundTasksAttached = true;
    _nativeUpdateListeners.add(_nativeUpdateListener);
    _sharedNativeUpdates ??= FileDownloader().updates.listen((update) {
      for (final listener in List.of(_nativeUpdateListeners)) {
        listener(update);
      }
    });
  }

  void _handleNativeUpdate(TaskUpdate update) {
    final model = catalog
        .where((item) => update.task.taskId == 'model-${item.tier}')
        .firstOrNull;
    if (model == null) return;
    switch (update) {
      case TaskProgressUpdate(:final progress):
        if (progress < 0) {
          return; // Plugin status sentinels are not percentages.
        }
        _progress[model.tier] = progress;
        _changes.add(null);
      case TaskStatusUpdate(:final status):
        _nativeStatus[model.tier] = status;
        if (status == TaskStatus.complete) {
          _nativeCompletions.remove(model.tier)?.complete();
        } else if (status == TaskStatus.paused) {
          _nativeCompletions.remove(model.tier)?.completeError(
            const ModelDownloadPaused(),
          );
        } else if (status == TaskStatus.failed ||
            status == TaskStatus.canceled) {
          if (status == TaskStatus.failed) {
            _failures[model.tier] = ModelDownloadFailure.fromUpdate(
              update,
            ).code;
            unawaited(
              _refreshNativeCheckpoint(model).then((_) {
                _changes.add(null);
              }),
            );
          }
          final completion = _nativeCompletions.remove(model.tier);
          if (completion != null) {
            completion.completeError(ModelDownloadFailure.fromUpdate(update));
          }
        }
        if (status == TaskStatus.complete &&
            !_downloads.containsKey(model.tier)) {
          unawaited(_finalizeNative(model));
        }
        _changes.add(null);
    }
  }

  File fileOf(M model) => File('${_dir.path}/${model.fileName}');

  /// The in-flight partial: interrupted attempts leave it for resume.
  File _partFileOf(M model) => File('${fileOf(model).path}.part');

  /// A partial stashed by [pause] — kept out of `.part` so a restart's
  /// [resumeInterrupted] leaves it alone.
  File _pausedFileOf(M model) => File('${fileOf(model).path}.paused');

  ModelStatus statusOf(M model) {
    if (_downloads.containsKey(model.tier)) return ModelStatus.downloading;
    if (fileOf(model).existsSync()) return ModelStatus.ready;
    if (_nativeStatus[model.tier] == TaskStatus.enqueued ||
        _nativeStatus[model.tier] == TaskStatus.running ||
        _nativeStatus[model.tier] == TaskStatus.waitingToRetry) {
      return ModelStatus.downloading;
    }
    if (_nativeStatus[model.tier] == TaskStatus.paused) {
      return ModelStatus.paused;
    }
    if ((_nativeResumeOffsets[model.tier] ?? 0) > 0) return ModelStatus.paused;
    if (_partFileOf(model).existsSync() || _pausedFileOf(model).existsSync()) {
      return ModelStatus.paused;
    }
    return ModelStatus.notInstalled;
  }

  ModelState<M> stateOf(M model) {
    final status = statusOf(model);
    return ModelState(model, status, switch (status) {
      ModelStatus.downloading => _progress[model.tier] ?? 0,
      ModelStatus.paused => _progress[model.tier] ?? _partialFraction(model),
      _ => 0,
    }, failureCode: _failures[model.tier]);
  }

  double _partialFraction(M model) {
    final nativeOffset = _nativeResumeOffsets[model.tier];
    if (nativeOffset != null) {
      return (nativeOffset / model.sizeBytes).clamp(0.0, 1.0);
    }
    for (final file in [_partFileOf(model), _pausedFileOf(model)]) {
      if (file.existsSync()) {
        return (file.lengthSync() / model.sizeBytes).clamp(0.0, 1.0);
      }
    }
    return 0;
  }

  List<ModelState<M>> snapshot() => [
    for (final model in catalog) stateOf(model),
  ];

  /// Total disk footprint of installed models (Settings shows storage used).
  int installedBytes() => catalog
      .map((m) => fileOf(m))
      .where((f) => f.existsSync())
      .fold(0, (sum, f) => sum + f.lengthSync());

  /// Downloads and verifies a tier; concurrent calls for the same tier join
  /// the in-flight download. Progress is reported both through [onProgress]
  /// and the [changes] stream. A partial file left by an interrupted attempt
  /// is resumed with an HTTP Range request, not thrown away.
  Future<void> download(
    M model, {
    ProgressSink? onProgress,
    bool requestNotificationPermission = true,
  }) {
    if (statusOf(model) == ModelStatus.ready) return Future.value();
    final inFlight = _downloads[model.tier];
    if (inFlight != null) return inFlight;
    _failures.remove(model.tier);

    final download =
        _download(
          model,
          onProgress,
          requestNotificationPermission: requestNotificationPermission,
        ).whenComplete(() {
          _downloads.remove(model.tier);
          _progress.remove(model.tier);
          _changes.add(null);
        });
    _downloads[model.tier] = download;
    // A resume already has bytes on disk — start the visible progress there,
    // not at 0 % (re-hashing a big partial takes a while and the bar would
    // sit wrong the whole time).
    _progress[model.tier] = _partialFraction(model);
    _changes.add(null);
    return download;
  }

  /// Aborts [model]'s in-flight download: its future completes with
  /// [ModelDownloadCancelled] and the partial file is removed. No-op when
  /// the tier isn't downloading.
  void cancel(M model) {
    if (!_downloads.containsKey(model.tier)) return;
    _cancelRequested.add(model.tier);
    final task = _nativeTasks[model.tier];
    if (task != null) {
      unawaited(FileDownloader().cancelTaskWithId(task.taskId));
      return;
    }
    _clients[model.tier]?.close(force: true);
  }

  /// Halts [model]'s in-flight download but keeps its bytes: the future
  /// completes with [ModelDownloadPaused], the partial is stashed as
  /// `.paused` (status [ModelStatus.paused]) and a later [download] resumes
  /// it. No-op when the tier isn't downloading.
  void pause(M model) {
    if (!_downloads.containsKey(model.tier)) return;
    _pauseRequested.add(model.tier);
    final task = _nativeTasks[model.tier];
    if (task != null) {
      unawaited(FileDownloader().pause(task));
      return;
    }
    _clients[model.tier]?.close(force: true);
  }

  /// Puts downloads that were interrupted mid-flight (app force-closed,
  /// crash, network drop) back on the wire: any tier with a `.part` on disk.
  /// Explicitly paused tiers (`.paused`) stay put until the user resumes
  /// them. Failures are quiet — the tier shows as paused in Settings and a
  /// tap retries. Completes when every resumed download settles; true when
  /// at least one model landed (callers drain parked jobs then).
  Future<bool> resumeInterrupted() async {
    var landed = false;
    if (Platform.isAndroid) {
      for (final model in catalog) {
        final record = await FileDownloader().database.recordForId(
          'model-${model.tier}',
        );
        if (record == null || record.task is! DownloadTask) continue;
        await _refreshNativeCheckpoint(model);
        if (record.status == TaskStatus.complete) {
          landed = await _finalizeNative(model) || landed;
        } else if (record.status == TaskStatus.paused) {
          _progress[model.tier] = record.progress;
          if (await FileDownloader().resume(record.task as DownloadTask)) {
            _nativeStatus[model.tier] = TaskStatus.running;
          }
        } else if (record.status == TaskStatus.enqueued ||
            record.status == TaskStatus.running ||
            record.status == TaskStatus.waitingToRetry) {
          _nativeStatus[model.tier] = record.status;
          _progress[model.tier] = record.progress;
        }
      }
    }
    await Future.wait([
      for (final model in catalog)
        if (statusOf(model) == ModelStatus.paused &&
            _partFileOf(model).existsSync())
          download(model, requestNotificationPermission: false)
              .then<void>((_) {
                landed = true;
              })
              .catchError((_) {}),
    ]);
    await _cleanupAbandonedNativeTempFiles();
    return landed;
  }

  /// The native downloader keeps large temporary files in app support. If
  /// Android kills a task before its resume metadata is committed, its record
  /// can be terminal while a large `com.bbflight.background_downloader*` file
  /// remains. Preserve every file still referenced by resumable task data and
  /// remove only unreferenced files when no catalog task is actively running.
  Future<void> _cleanupAbandonedNativeTempFiles() async {
    if (!Platform.isAndroid) return;
    // Both catalogs share this directory. A catalog-local check can unlink
    // the other engine's live file. Check every task and every checkpoint.
    final records = await FileDownloader().database.allRecords();
    for (final record in records) {
      if (record.status == TaskStatus.enqueued ||
          record.status == TaskStatus.running ||
          record.status == TaskStatus.waitingToRetry ||
          record.status == TaskStatus.paused) {
        return;
      }
    }
    final protectedPaths = {
      for (final resume
          in await modelDownloadPersistence.retrieveAllResumeData())
        resume.tempFilepath,
    };
    final cutoff = DateTime.now().subtract(const Duration(days: 1));
    final supportDirectory = await getApplicationSupportDirectory();
    await for (final entry in supportDirectory.list(followLinks: false)) {
      if (entry is! File ||
          !entry.uri.pathSegments.last.startsWith(
            'com.bbflight.background_downloader',
          )) {
        continue;
      }
      if (!protectedPaths.contains(entry.path) &&
          (await entry.lastModified()).isBefore(cutoff)) {
        await entry.delete();
      }
    }
  }

  Future<void> _refreshNativeCheckpoint(M model) async {
    final resume = await modelDownloadPersistence.retrieveResumeData(
      'model-${model.tier}',
    );
    if (await ModelDownloadPersistence.validCheckpoint(resume)) {
      _nativeResumeOffsets[model.tier] = resume!.requiredStartByte;
    } else {
      _nativeResumeOffsets.remove(model.tier);
    }
  }

  Future<bool> _finalizeNative(M model) async {
    final part = _partFileOf(model);
    if (!await part.exists() || await part.length() != model.sizeBytes) {
      _nativeStatus.remove(model.tier);
      return false;
    }
    final digestSink = _DigestSink();
    final hasher = sha256.startChunkedConversion(digestSink);
    await for (final chunk in part.openRead()) {
      hasher.add(chunk);
    }
    hasher.close();
    if (digestSink.digest.toString() != model.sha256Hex) return false;
    if (await fileOf(model).exists()) await fileOf(model).delete();
    await part.rename(fileOf(model).path);
    _installed.add(model);
    _nativeStatus[model.tier] = TaskStatus.complete;
    _progress[model.tier] = 1;
    _changes.add(null);
    return true;
  }

  /// Switch-mid-download semantics (§5.6): selecting a tier cancels every
  /// other tier still on the wire.
  void cancelExcept(String tier) {
    for (final model in catalog) {
      if (model.tier != tier) cancel(model);
    }
  }

  Future<void> _download(
    M model,
    ProgressSink? onProgress, {
    required bool requestNotificationPermission,
  }) async {
    await _dir.create(recursive: true);
    final part = _partFileOf(model);
    final paused = _pausedFileOf(model);
    final client = _httpClientFactory();
    _clients[model.tier] = client;
    try {
      // A stashed pause resumes exactly like an interruption — move it back
      // into the live partial slot ('.part' wins if both somehow exist).
      if (await paused.exists()) {
        await part.exists()
            ? await paused.delete()
            : await paused.rename(part.path);
      }

      if (Platform.isAndroid) {
        final permissions = FileDownloader().permissions;
        var notificationPermission = await permissions.status(
          PermissionType.notifications,
        );
        if (notificationPermission != PermissionStatus.granted) {
          notificationPermission = await permissions.request(
            PermissionType.notifications,
          );
        }
        if (notificationPermission != PermissionStatus.granted) {
          throw const ModelNotificationPermissionDenied();
        }

        await _cleanupAbandonedNativeTempFiles();
        final available = await _availableStorageBytes();
        int? resumableNativeOffset;
        final existingTask = await FileDownloader().database.recordForId(
          'model-${model.tier}',
        );
        await _refreshNativeCheckpoint(model);
        if (existingTask != null &&
            (_nativeResumeOffsets[model.tier] ?? 0) > 0) {
          // A paused task is the plugin state that owns a resumable partial.
          // Terminal records are not a disk-space discount even if their
          // last progress was nonzero.
          resumableNativeOffset = _nativeResumeOffsets[model.tier];
        }
        final required = requiredModelDownloadStorageBytes(
          modelSizeBytes: model.sizeBytes,
          appPartialBytes: await part.exists() ? await part.length() : null,
          nativeResumeOffsetBytes: resumableNativeOffset,
        );
        if (available != null && available < required) {
          throw InsufficientModelStorage(
            requiredBytes: required,
            availableBytes: available,
          );
        }
        await _downloadAndroid(
          model,
          part,
          onProgress,
          requestNotificationPermission: requestNotificationPermission,
        );
        final digestSink = _DigestSink();
        final hasher = sha256.startChunkedConversion(digestSink);
        await for (final chunk in part.openRead()) {
          if (_cancelRequested.contains(model.tier)) {
            throw const ModelDownloadCancelled();
          }
          hasher.add(chunk);
        }
        hasher.close();
        final received = await part.length();
        if (received != model.sizeBytes ||
            digestSink.digest.toString() != model.sha256Hex) {
          throw const ModelVerificationException(
            'Downloaded model failed integrity check.',
          );
        }
        await part.rename(fileOf(model).path);
        _installed.add(model);
        return;
      }

      // An interrupted attempt (network drop, app killed mid-download) left
      // a partial file behind — ask the server for just the rest.
      var existing = 0;
      if (await part.exists()) {
        final length = await part.length();
        if (length > 0 && length < model.sizeBytes) existing = length;
      }

      final request = await client.getUrl(model.url);
      if (existing > 0) {
        request.headers.set(HttpHeaders.rangeHeader, 'bytes=$existing-');
      }
      final response = await request.close();
      final resumed =
          existing > 0 && response.statusCode == HttpStatus.partialContent;
      if (response.statusCode == HttpStatus.requestedRangeNotSatisfiable) {
        // The remote file no longer matches the partial — start over.
        await part.delete();
        throw HttpException('HTTP ${response.statusCode}', uri: model.url);
      }
      if (response.statusCode != HttpStatus.ok && !resumed) {
        throw HttpException('HTTP ${response.statusCode}', uri: model.url);
      }

      var received = 0;
      final digestSink = _DigestSink();
      final hasher = sha256.startChunkedConversion(digestSink);
      if (resumed) {
        // The pinned sha256 covers the whole file — feed the bytes already
        // on disk through the hasher before appending the new ones.
        await for (final chunk in part.openRead()) {
          if (_cancelRequested.contains(model.tier)) {
            throw const ModelDownloadCancelled();
          }
          if (_pauseRequested.contains(model.tier)) {
            throw const ModelDownloadPaused();
          }
          hasher.add(chunk);
        }
        received = existing;
        final fraction = (received / model.sizeBytes).clamp(0.0, 1.0);
        _progress[model.tier] = fraction;
        onProgress?.call(fraction);
        _changes.add(null);
      }

      final sink = part.openWrite(
        mode: resumed ? FileMode.append : FileMode.write,
      );
      try {
        // A WiFi→cellular handover or a silent carrier drop (no FIN) can
        // freeze the body stream forever with no error — the progress bar
        // would sit at N % until a manual pause/resume. An inactivity
        // timeout turns the stall into a transient failure: the partial
        // stays on disk and the next attempt resumes it.
        final body = response.timeout(_stallTimeout);
        await for (final chunk in body) {
          if (_cancelRequested.contains(model.tier)) {
            throw const ModelDownloadCancelled();
          }
          if (_pauseRequested.contains(model.tier)) {
            throw const ModelDownloadPaused();
          }
          hasher.add(chunk);
          sink.add(chunk);
          received += chunk.length;
          final fraction = (received / model.sizeBytes).clamp(0.0, 1.0);
          _progress[model.tier] = fraction;
          onProgress?.call(fraction);
          _changes.add(null);
        }
      } finally {
        await sink.close();
      }
      hasher.close();

      if (received != model.sizeBytes ||
          digestSink.digest.toString() != model.sha256Hex) {
        throw ModelVerificationException(
          '${model.fileName}: got $received bytes, '
          'sha256 ${digestSink.digest}',
        );
      }
      await part.rename(fileOf(model).path);
      _installed.add(model);
    } catch (e) {
      // Proven-bad bytes and explicit aborts drop the partial file; a pause
      // stashes it; a transient failure keeps it so the next attempt
      // resumes. Cancel wins over pause when both raced in (tier switch
      // right after a pause).
      final cancelled = _cancelRequested.contains(model.tier);
      final pausedNow = !cancelled &&
          (_pauseRequested.contains(model.tier) || e is ModelDownloadPaused);
      if (!cancelled && !pausedNow) {
        _failures[model.tier] = e is ModelDownloadFailure
            ? e.code
            : e is ModelVerificationException
            ? 'INTEGRITY'
            : 'DOWNLOAD_FAILED';
      }
      if (Platform.isAndroid && !cancelled) {
        await _refreshNativeCheckpoint(model);
      } else if (Platform.isAndroid && cancelled) {
        _nativeResumeOffsets.remove(model.tier);
        await modelDownloadPersistence.discard('model-${model.tier}');
      }
      if ((cancelled || e is ModelVerificationException) &&
          await part.exists()) {
        await part.delete();
      } else if (pausedNow && await part.exists()) {
        await part.rename(paused.path);
      }
      // A force-closed connection surfaces as an I/O error — report the
      // cancel/pause, not the symptom.
      if (cancelled) throw const ModelDownloadCancelled();
      if (pausedNow) throw const ModelDownloadPaused();
      rethrow;
    } finally {
      _cancelRequested.remove(model.tier);
      _pauseRequested.remove(model.tier);
      _clients.remove(model.tier);
      client.close(force: true);
    }
  }

  Future<int?> _availableStorageBytes() async {
    try {
      return await const MethodChannel(
        'diktafon/model_storage',
      ).invokeMethod<int>('availableBytes', {'path': _dir.path});
    } catch (_) {
      // Storage probing is best-effort on older or restricted Android builds.
      return null;
    }
  }

  Future<void> _downloadAndroid(
    M model,
    File partial,
    ProgressSink? onProgress, {
    required bool requestNotificationPermission,
  }) async {
    final permissions = FileDownloader().permissions;
    var notificationPermission = await permissions.status(
      PermissionType.notifications,
    );
    if (notificationPermission != PermissionStatus.granted &&
        requestNotificationPermission) {
      notificationPermission = await permissions.request(
        PermissionType.notifications,
      );
    }
    if (notificationPermission != PermissionStatus.granted) {
      throw const ModelNotificationPermissionDenied();
    }

    final support = await getApplicationSupportDirectory();
    final normalizedSupport = '${support.path}${Platform.pathSeparator}';
    final normalizedDir = _dir.absolute.path;
    if (!normalizedDir.startsWith(normalizedSupport)) {
      throw const FileSystemException(
        'Model folder is outside app support storage.',
      );
    }
    final directory = normalizedDir.substring(normalizedSupport.length);
    final task = DownloadTask(
      taskId: 'model-${model.tier}',
      url: model.url.toString(),
      filename: partial.uri.pathSegments.last,
      directory: directory,
      baseDirectory: BaseDirectory.applicationSupport,
      group: 'diktafon-models',
      updates: Updates.statusAndProgress,
      retries: 3,
      allowPause: true,
      priority: 0,
      displayName: model.label,
      metaData: model.tier,
    );
    final existing = await FileDownloader().database.recordForId(task.taskId);
    if (existing != null &&
        (existing.status == TaskStatus.paused ||
            existing.status == TaskStatus.failed) &&
        (_nativeResumeOffsets[model.tier] ?? 0) > 0) {
      final completion = Completer<void>();
      _nativeCompletions[model.tier] = completion;
      final resumeTask = (existing.task as DownloadTask).copyWith(
        retriesRemaining: 3,
      );
      _nativeTasks[model.tier] = resumeTask;
      if (!await FileDownloader().resume(resumeTask)) {
        _nativeTasks.remove(model.tier);
        _nativeCompletions.remove(model.tier);
        // The task record outlived its temporary file. Drop the stale
        // terminal state, clean its orphaned native temp, and check storage
        // for a fresh full download before starting over.
        await FileDownloader().database.deleteRecordWithId(task.taskId);
        await modelDownloadPersistence.discard(task.taskId);
        _nativeResumeOffsets.remove(model.tier);
        await _cleanupAbandonedNativeTempFiles();
        final available = await _availableStorageBytes();
        final required = requiredModelDownloadStorageBytes(
          modelSizeBytes: model.sizeBytes,
        );
        if (available != null && available < required) {
          throw InsufficientModelStorage(
            requiredBytes: required,
            availableBytes: available,
          );
        }
      } else {
        try {
          await completion.future;
        } finally {
          _nativeTasks.remove(model.tier);
        }
        return;
      }
    }
    if (existing != null && existing.status == TaskStatus.complete) {
      if (await _finalizeNative(model)) return;
    }
    if (existing != null &&
        (existing.status == TaskStatus.failed ||
            existing.status == TaskStatus.canceled ||
            existing.status == TaskStatus.complete)) {
      await FileDownloader().database.deleteRecordWithId(task.taskId);
    }
    _nativeTasks[model.tier] = task;
    try {
      final update = await FileDownloader().download(
        task,
        onProgress: (fraction) {
          if (fraction < 0) return;
          _progress[model.tier] = fraction;
          onProgress?.call(fraction);
          _changes.add(null);
        },
        onStatus: (status) {
          if (status == TaskStatus.paused) _pauseRequested.add(model.tier);
          _changes.add(null);
        },
      );
      if (update.status == TaskStatus.paused ||
          _pauseRequested.contains(model.tier)) {
        throw const ModelDownloadPaused();
      }
      if (update.status == TaskStatus.canceled ||
          _cancelRequested.contains(model.tier)) {
        throw const ModelDownloadCancelled();
      }
      if (update.status != TaskStatus.complete) {
        throw ModelDownloadFailure.fromUpdate(update);
      }
    } finally {
      _nativeTasks.remove(model.tier);
    }
  }

  /// Removes the installed file *and* any partial — the picker's delete
  /// action also discards a paused download the user changed their mind on.
  void delete(M model) {
    if (Platform.isAndroid) {
      unawaited(FileDownloader().cancelTaskWithId('model-${model.tier}'));
      unawaited(modelDownloadPersistence.discard('model-${model.tier}'));
      unawaited(
        FileDownloader().database.deleteRecordWithId('model-${model.tier}'),
      );
    }
    _nativeStatus.remove(model.tier);
    _failures.remove(model.tier);
    _nativeResumeOffsets.remove(model.tier);
    _progress.remove(model.tier);
    for (final file in [
      fileOf(model),
      _partFileOf(model),
      _pausedFileOf(model),
    ]) {
      if (file.existsSync()) file.deleteSync();
    }
    _changes.add(null);
  }

  void dispose() {
    if (_backgroundTasksAttached) {
      _nativeUpdateListeners.remove(_nativeUpdateListener);
      _backgroundTasksAttached = false;
    }
    _changes.close();
    _installed.close();
  }
}

class _DigestSink implements Sink<Digest> {
  late Digest digest;

  @override
  void add(Digest data) => digest = data;

  @override
  void close() {}
}
