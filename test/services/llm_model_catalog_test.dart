import 'package:diktafon/services/providers/llm/llm_model_manager.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('new model artifacts are pinned, licensed and integrity checked', () {
    final models = [
      LlmModel.gemma4E2b,
      LlmModel.gemma4E4b,
      LlmModel.qwen3_5_2b,
    ];

    expect(LlmModel.all, containsAll(models));
    expect(models.map((model) => model.tier).toSet(), hasLength(3));
    for (final model in models) {
      expect(model.license, 'Apache-2.0');
      expect(model.url.path, contains('/resolve/'));
      expect(model.url.path, isNot(contains('/resolve/main/')));
      expect(model.sha256Hex, matches(RegExp(r'^[a-f0-9]{64}$')));
      expect(model.sizeBytes, greaterThan(1000000000));
      expect(model.minRamGb, greaterThan(0));
    }

    expect(LlmModel.gemma4E2b.sizeBytes, 3349516256);
    expect(LlmModel.gemma4E4b.sizeBytes, 5154941280);
    expect(LlmModel.qwen3_5_2b.sizeBytes, 1312165056);
    expect(LlmModel.gemma4E2b.minRamGb, 6);
    expect(LlmModel.gemma4E4b.minRamGb, 8);
    expect(LlmModel.qwen3_5_2b.minRamGb, 4);
    expect(LlmModel.qwen3_5_2b.quantization, 'Q4_K_M');
  });
}
