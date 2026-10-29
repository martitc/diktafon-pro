import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:background_downloader/background_downloader.dart';
import 'package:just_audio_media_kit/just_audio_media_kit.dart';
import 'package:path_provider/path_provider.dart';

import 'app.dart';
import 'application/navigation.dart';
import 'application/providers.dart';
import 'data/files/audio_file_store.dart';
import 'l10n/gen/app_localizations.dart';
import 'l10n/locale_resolution.dart';
import 'services/notifications/download_notifier.dart';
import 'services/notifications/activity_center.dart';
import 'services/notifications/local_notifications_sink.dart';
import 'services/notifications/processing_completion_notifier.dart';
import 'presentation/screens/activity_center_screen.dart';
import 'services/processing/job_queue.dart';
import 'services/providers/llm/llm_model_manager.dart';
import 'services/providers/model_manager.dart';
import 'services/providers/whisper/whisper_model_manager.dart';
import 'services/system/system_settings.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final downloader = FileDownloader();
  downloader.configureNotification(
    running: const TaskNotification(
      'Diktafon Pro',
      'Descargando modelo de IA…',
    ),
    complete: const TaskNotification(
      'Diktafon Pro',
      'Descarga de modelo completada',
    ),
    error: const TaskNotification(
      'Diktafon Pro',
      'Error al descargar el modelo',
    ),
    paused: const TaskNotification(
      'Diktafon Pro',
      'Descarga de modelo pausada',
    ),
    progressBar: true,
  );
  // A running notification alone does not enable long transfers. Without
  // this flag the Android downloader times out expedited jobs after 2 minutes.
  await downloader.configure(
    androidConfig: [(Config.runInForeground, Config.always)],
  );
  if (Platform.isLinux) {
    // Desktop dev target: just_audio has no Linux backend of its own.
    // LIBMPV_PATH lets dev machines point at a locally extracted libmpv.
    JustAudioMediaKit.ensureInitialized(
      linux: true,
      windows: false,
      libmpv: Platform.environment['LIBMPV_PATH'],
    );
  }

  final fileStore = await AudioFileStore.open();
  // Models are regenerable → app-support, excluded from backup (§7.1).
  final supportDir = await getApplicationSupportDirectory();
  final activityCenter = ActivityCenter(
    File('${supportDir.path}/activity-history.json'),
  );
  await activityCenter.load();
  final modelsDir = Directory('${supportDir.path}/models')
    ..createSync(recursive: true);
  unawaited(excludeFromIosBackup(modelsDir.path));
  final whisperModels = WhisperModelManager(
    Directory('${modelsDir.path}/whisper'),
  );
  final llmModels = LlmModelManager(Directory('${modelsDir.path}/llm'));
  whisperModels.attachBackgroundTasks();
  llmModels.attachBackgroundTasks();
  await downloader.start(autoCleanDatabase: false);
  await downloader.resumeFromBackground();
  final container = ProviderContainer(
    overrides: [
      audioFileStoreProvider.overrideWithValue(fileStore),
      activityCenterProvider.overrideWithValue(activityCenter),
      whisperModelManagerProvider.overrideWithValue(whisperModels),
      llmModelManagerProvider.overrideWithValue(llmModels),
      chimeFileProvider.overrideWithValue(
        await _materializeAsset('assets/audio/chime.wav', supportDir.path),
      ),
      vadModelFileProvider.overrideWithValue(
        await _materializeAsset(
          'assets/models/ggml-silero-v5.1.2.bin',
          modelsDir.path,
        ),
      ),
    ],
  );

  // iOS moves the data container on app updates/reinstalls — repoint stored
  // audio paths at the current root before jobs or playback read them
  // (§7.1). Best-effort: a failure just leaves per-memo missing audio.
  try {
    await container
        .read(memoRepositoryProvider)
        .rebaseAudioPaths(fileStore.rootPath);
  } catch (_) {}

  // Captures a process death cut short come back as memos (D13/§14).
  // Awaited before the UI (a fresh capture must never race the scan) and
  // before the orphan sweep below (which would eventually eat these files).
  try {
    await container.read(captureRecoveryProvider).recover();
  } catch (_) {}

  for (final models in <ModelManager<ModelSpec>>[whisperModels, llmModels]) {
    models.installed.listen((_) {
      unawaited(() async {
        try {
          await container.read(settingsProvider.future);
          await container.read(jobQueueProvider).drain();
        } catch (_) {}
      }());
    });
  }

  // Launch hygiene, off the critical path: audio files no memo references
  // (a capture killed before its stop() ever inserted a row, §7.1) and
  // stale temp dirs stranded by a mid-job kill (decoded PCM, import/export
  // staging). Both age-gated — a job may legitimately be starting up.
  unawaited(() async {
    try {
      final cutoff = DateTime.now().subtract(const Duration(hours: 1));
      final ids = await container.read(memoRepositoryProvider).allIds();
      await fileStore.sweepOrphans(ids.contains, cutoff: cutoff);
      await _sweepStaleTempDirs(cutoff);
    } catch (_) {}
  }());

  // Model downloads mirror into the notification area while they run.
  _attachDownloadNotifications(
    whisperModels,
    llmModels,
    container.read(jobQueueProvider),
    activityCenter,
  );

  // Resume any jobs persisted before the last shutdown (§6.5 durability) —
  // once settings have actually loaded: the providers fall back to default
  // tiers until the settings stream's first emission, and a job resolved in
  // that cold-start window would silently transcribe with the wrong model.
  Future<void>.microtask(() async {
    try {
      await container.read(settingsProvider.future);
    } catch (_) {}
    await container.read(jobQueueProvider).drain();
  });

  // A force-close mid-download left a `.part` behind — put it back on the
  // wire without waiting for a tap (§6.6; user-paused `.paused` stashes stay
  // put). When a model lands, jobs parked on it get released.
  for (final models in <ModelManager<ModelSpec>>[whisperModels, llmModels]) {
    unawaited(
      models.resumeInterrupted().then((landed) async {
        if (landed) await container.read(jobQueueProvider).drain();
      }),
    );
  }

  runApp(
    UncontrolledProviderScope(container: container, child: const DiktafonApp()),
  );
}

/// Best-effort, off the critical startup path: no notification backend →
/// no notifier, downloads run exactly as before. Copy is localized through
/// the system locale (the UI follows it too, §13); the notifier lives for
/// the whole process, so it is never disposed.
Future<void> _attachDownloadNotifications(
  WhisperModelManager whisperModels,
  LlmModelManager llmModels,
  JobQueue jobQueue,
  ActivityCenter history,
) async {
  final sink = await LocalNotificationsSink.init(
    onNotificationTap: () {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final navigator = appNavigatorKey.currentState;
        if (navigator == null) return;
        unawaited(
          navigator
              .push<ActivityEntry>(
                MaterialPageRoute<ActivityEntry>(
                  builder: (_) => const ActivityCenterScreen(),
                ),
              )
              .then((_) => history.markAllRead()),
        );
      });
    },
  );
  if (sink == null) return;
  AppLocalizations l10n;
  try {
    l10n = lookupAppLocalizations(
      padZhLocale(ui.PlatformDispatcher.instance.locale),
    );
  } catch (_) {
    l10n = lookupAppLocalizations(const Locale('en'));
  }
  ModelDownloadNotifier(
      sink,
      DownloadNotificationTexts(
        downloading: l10n.notifDownloading,
        installed: l10n.notifModelInstalled,
      ),
      history: history,
    )
    ..attach(whisperModels, idBase: 100)
    ..attach(llmModels, idBase: 200);
  ProcessingCompletionNotifier(
    sink,
    ProcessingNotificationTexts(
      transcriptionTitle: l10n.notifTranscriptionCompleted,
      transcriptionBody: l10n.notifTranscriptionCompletedBody,
      summaryTitle: l10n.notifSummaryCompleted,
      summaryBody: l10n.notifSummaryCompletedBody,
    ),
    history: history,
  ).attach(jobQueue.completions);
}

/// Neither just_audio's media_kit backend nor the native engines read
/// bundle assets — copy the asset out once (chime → app-support, Silero VAD
/// → the backup-excluded models dir). Null (asset missing) → the feature
/// quietly stays off rather than failing startup.
///
/// Write-then-rename plus a byte-length check: a process kill mid-write
/// (first launch is exactly when the OS is busiest) must not leave a
/// truncated copy that every later launch trusts — a short VAD model fails
/// natively on every small-tier transcription.
Future<String?> _materializeAsset(String assetKey, String dir) async {
  try {
    final file = File('$dir/${assetKey.split('/').last}');
    final data = await rootBundle.load(assetKey);
    if (await file.exists() && await file.length() == data.lengthInBytes) {
      return file.path;
    }
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsBytes(data.buffer.asUint8List(), flush: true);
    await tmp.rename(file.path);
    return file.path;
  } catch (_) {
    return null;
  }
}

/// Deletes stale `dk_pcm_*` / `diktafon_import_*` / `diktafon_export_*`
/// temp entries a killed process left behind. Age-gated by [cutoff]: /tmp
/// is shared on desktop and another instance may be mid-job.
Future<void> _sweepStaleTempDirs(DateTime cutoff) async {
  const prefixes = ['dk_pcm_', 'diktafon_import_', 'diktafon_export_'];
  await for (final entry in Directory.systemTemp.list()) {
    final name = entry.uri.pathSegments.lastWhere((s) => s.isNotEmpty);
    if (!prefixes.any(name.startsWith)) continue;
    try {
      if (entry.statSync().modified.isAfter(cutoff)) continue;
      entry.deleteSync(recursive: true);
    } catch (_) {
      // Best-effort hygiene.
    }
  }
}
