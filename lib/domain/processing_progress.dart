/// Processing stage currently visible for one memo or cassette.
enum ProcessingStage {
  transcribing,
  uploadingAudio,
  processingCloud,
  summarizing,
  finished,
}

/// A measured fraction is null when the provider cannot report real progress.
class ProcessingProgress {
  ProcessingProgress({
    required this.targetId,
    required this.stage,
    double? fraction,
  }) : fraction = _measuredFraction(fraction);

  final String targetId;
  final ProcessingStage stage;
  final double? fraction;

  static double? _measuredFraction(double? value) =>
      value != null && value.isFinite && value >= 0 && value <= 1
      ? value
      : null;
}
