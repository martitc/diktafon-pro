/// Disk needed for a model download, based only on bytes that can be resumed.
/// Progress from a terminal/canceled downloader record is deliberately not a
/// resume source: its temporary file may no longer exist or be reusable.
int remainingModelDownloadBytes({
  required int modelSizeBytes,
  int? appPartialBytes,
  int? nativeResumeOffsetBytes,
}) {
  final retained = appPartialBytes ?? nativeResumeOffsetBytes ?? 0;
  return (modelSizeBytes - retained).clamp(0, modelSizeBytes);
}

int requiredModelDownloadStorageBytes({
  required int modelSizeBytes,
  int? appPartialBytes,
  int? nativeResumeOffsetBytes,
  int safetyMarginBytes = 128 * 1024 * 1024,
}) =>
    remainingModelDownloadBytes(
      modelSizeBytes: modelSizeBytes,
      appPartialBytes: appPartialBytes,
      nativeResumeOffsetBytes: nativeResumeOffsetBytes,
    ) +
    safetyMarginBytes;
