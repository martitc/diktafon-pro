import 'package:flutter_test/flutter_test.dart';

import 'package:diktafon/domain/processing_progress.dart';

void main() {
  test('keeps measured progress within the 0–1 range', () {
    final progress = ProcessingProgress(
      targetId: 'memo-1',
      stage: ProcessingStage.transcribing,
      fraction: 0.42,
    );

    expect(progress.fraction, 0.42);
  });

  test('omits a fraction when the provider has no measured progress', () {
    final progress = ProcessingProgress(
      targetId: 'memo-1',
      stage: ProcessingStage.processingCloud,
    );

    expect(progress.fraction, isNull);
  });

  test('drops non-finite progress instead of displaying a false value', () {
    final progress = ProcessingProgress(
      targetId: 'memo-1',
      stage: ProcessingStage.transcribing,
      fraction: double.nan,
    );

    expect(progress.fraction, isNull);
  });
}
