import 'dart:io';

import 'package:background_downloader/background_downloader.dart';

/// The downloader clears resume metadata on every terminal status, including
/// an exhausted network retry. Keep valid model checkpoints until the model
/// lands or the user explicitly discards it. Uses the plugin's public storage
/// interface and existing on-disk format; no dependency fork or migration.
class ModelDownloadPersistence extends LocalStorePersistentStorage {
  @override
  Future<void> removeResumeData(String? taskId) async {
    if (Platform.isAndroid && taskId != null && taskId.startsWith('model-')) {
      final resume = await retrieveResumeData(taskId);
      if (await validCheckpoint(resume)) return;
    }
    await super.removeResumeData(taskId);
  }

  Future<void> discard(String taskId) => super.removeResumeData(taskId);

  static Future<bool> validCheckpoint(ResumeData? resume) async {
    if (resume == null || resume.requiredStartByte <= 0) return false;
    try {
      return await File(resume.tempFilepath).length() >=
          resume.requiredStartByte;
    } on FileSystemException {
      return false;
    }
  }
}

final modelDownloadPersistence = ModelDownloadPersistence();

/// Must be the first FileDownloader construction in an app process.
FileDownloader createModelDownloader() =>
    FileDownloader(persistentStorage: modelDownloadPersistence);
