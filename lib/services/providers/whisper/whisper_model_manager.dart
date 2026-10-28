/// The whisper model catalog (§6.6): tiers pinned from the git-lfs pointers
/// at huggingface.co/ggerganov/whisper.cpp (2026-07-07). Download/verify
/// mechanics live in the shared ModelManager. The `description` fields are
/// dev-only fallbacks — listed tiers show localized, device-aware copy from
/// the ARBs (ModelPickerDialog.describe).
library;

import '../model_manager.dart';

export '../model_manager.dart'
    show
        ModelDownloadCancelled,
        ModelDownloadPaused,
        ModelVerificationException;

/// One downloadable whisper tier.
class WhisperModel implements ModelSpec {
  const WhisperModel({
    required this.tier,
    required this.label,
    required this.description,
    required this.fileName,
    required this.sizeBytes,
    required this.sha256Hex,
    this.listed = true,
    this.urlOverride,
  });

  @override
  final String tier;
  @override
  final String label;
  @override
  final String description;
  @override
  final String fileName;
  @override
  final int sizeBytes;
  @override
  final String sha256Hex;
  @override
  final bool listed;

  /// Tests point this at a local server; production uses the HF mirror.
  final Uri? urlOverride;

  @override
  Uri get url {
    if (urlOverride != null) return urlOverride!;
    if (tier == 'large-v3') {
      return Uri.parse(
        'https://huggingface.co/ggerganov/whisper.cpp/resolve/c521a4b02f422512d734391fdf08bb08c0862f68/$fileName',
      );
    }
    return Uri.parse(
      'https://huggingface.co/ggerganov/whisper.cpp/resolve/main/$fileName',
    );
  }

  @override
  String get sizeLabel => sizeBytes >= 1024 * 1024 * 1024
      ? '${(sizeBytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GiB'
      : '${(sizeBytes / (1024 * 1024)).round()} MB';

  static const tiny = WhisperModel(
    tier: 'tiny',
    label: 'Whisper tiny',
    description: 'For quick tests only — not offered to users.',
    fileName: 'ggml-tiny-q5_1.bin',
    sizeBytes: 32152673,
    sha256Hex:
        '818710568da3ca15689e31a743197b520007872ff9576237bda97bd1b469c3d7',
    listed: false,
  );

  static const small = WhisperModel(
    tier: 'small',
    label: 'Whisper small',
    description: 'Recommended — best size/quality balance.',
    fileName: 'ggml-small-q5_1.bin',
    sizeBytes: 190085487,
    sha256Hex:
        'ae85e4a935d7a567bd102fe55afc16bb595bdb618e11b2fc7591bc08120411bb',
  );

  static const largeV3Turbo = WhisperModel(
    tier: 'large-v3-turbo',
    label: 'Whisper large-v3-turbo',
    description:
        'Higher accuracy; needs a capable device (~2.5 GB RAM '
        'while transcribing).',
    fileName: 'ggml-large-v3-turbo-q5_0.bin',
    sizeBytes: 574041195,
    sha256Hex:
        '394221709cd5ad1f40c46e6031ca61bce88931e6e088c188294c6d5a55ffa7e2',
  );

  static const largeV3 = WhisperModel(
    tier: 'large-v3',
    label: 'Whisper large-v3',
    description: 'Highest accuracy; 2.9 GiB download and high memory use.',
    fileName: 'ggml-large-v3.bin',
    sizeBytes: 3095033483,
    sha256Hex:
        '64d182b440b98d5203c4f9bd541544d84c605196c4f7b845dfa11fb23594d1e2',
    // Immutable upstream revision with byte size and SHA-256 from the
    // official Hugging Face Xet metadata for this exact file.
  );

  static const all = [tiny, small, largeV3Turbo, largeV3];

  static WhisperModel byTier(String tier) =>
      all.firstWhere((m) => m.tier == tier, orElse: () => small);
}

typedef WhisperModelState = ModelState<WhisperModel>;

class WhisperModelManager extends ModelManager<WhisperModel> {
  WhisperModelManager(
    super.dir, {
    super.httpClientFactory,
    super.catalog = WhisperModel.all,
    super.stallTimeout,
  });
}
