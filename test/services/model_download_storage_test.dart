import 'package:diktafon/services/providers/model_download_storage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const modelBytes = 1000;

  test('a canceled task without resume data requires the full model size', () {
    expect(
      requiredModelDownloadStorageBytes(
        modelSizeBytes: modelBytes,
        safetyMarginBytes: 100,
      ),
      1100,
    );
  });

  test('counts only a retained app partial or native resume offset', () {
    expect(
      remainingModelDownloadBytes(
        modelSizeBytes: modelBytes,
        appPartialBytes: 300,
      ),
      700,
    );
    expect(
      remainingModelDownloadBytes(
        modelSizeBytes: modelBytes,
        nativeResumeOffsetBytes: 450,
      ),
      550,
    );
  });

  test('clamps offsets so they cannot make required space negative', () {
    expect(
      remainingModelDownloadBytes(
        modelSizeBytes: modelBytes,
        nativeResumeOffsetBytes: 1200,
      ),
      0,
    );
  });
}
