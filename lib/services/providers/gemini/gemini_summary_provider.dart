import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../../domain/models.dart';
import '../credential_vault.dart';
import '../llm/summary_prompts.dart';
import '../summarization_provider.dart';
import '../transcription_provider.dart' show ModelStatus, ProgressSink;

/// Text-only Gemini adapter. It receives transcripts and memo digests; audio
/// is never sent through the summary path.
class GeminiSummaryProvider implements SummarizationProvider {
  GeminiSummaryProvider({
    required this.vault,
    required this.modelId,
    this.instructions = '',
    HttpClient Function()? httpClientFactory,
    Uri? endpointBase,
  }) : _httpClientFactory = httpClientFactory ?? HttpClient.new,
       _endpointBase =
           endpointBase ??
           Uri.https('generativelanguage.googleapis.com', '/v1beta/');

  final CredentialVault vault;
  final String modelId;
  final String instructions;
  final HttpClient Function() _httpClientFactory;
  final Uri _endpointBase;

  @override
  String get id => 'gemini/$modelId';

  @override
  Future<ModelStatus> modelStatus() async =>
      (await vault.readGeminiKey())?.trim().isNotEmpty == true
      ? ModelStatus.ready
      : ModelStatus.notInstalled;

  @override
  Future<void> ensureModel({ProgressSink? onProgress}) async {
    if ((await vault.readGeminiKey())?.trim().isNotEmpty != true) {
      throw const GeminiSummaryProviderException('missingApiKey');
    }
  }

  @override
  Future<String> summarizeMemo(
    Transcript transcript, {
    required String languageCode,
  }) => _complete(
    memoSummaryPrompt(
      transcript,
      languageCode: languageCode,
      instructions: instructions,
    ),
  );

  @override
  Future<String> updateCassetteSummary({
    required String? previousSummary,
    required List<MemoDigest> newMemos,
    required String languageCode,
  }) => _complete(
    cassetteSummaryPrompt(
      previousSummary: previousSummary,
      newMemos: newMemos,
      languageCode: languageCode,
      instructions: instructions,
    ),
  );

  @override
  Future<String> suggestTitle(
    String cassetteSummary, {
    required String languageCode,
  }) => _complete(titlePrompt(cassetteSummary, languageCode: languageCode));

  Future<String> _complete(LlmPrompt prompt) async {
    final key = await vault.readGeminiKey();
    if (key == null || key.trim().isEmpty) {
      throw const GeminiSummaryProviderException('missingApiKey');
    }

    final client = _httpClientFactory();
    try {
      final uri = _endpointBase.resolve(
        'models/${Uri.encodeComponent(modelId)}:generateContent',
      );
      final request = await client
          .postUrl(uri)
          .timeout(const Duration(seconds: 30));
      request.followRedirects = false;
      request.headers
        ..set('x-goog-api-key', key)
        ..contentType = ContentType.json
        ..set(HttpHeaders.acceptHeader, ContentType.json.mimeType);
      request.write(
        jsonEncode({
          'systemInstruction': {
            'parts': [
              {'text': prompt.system},
            ],
          },
          'contents': [
            {
              'role': 'user',
              'parts': [
                {'text': prompt.user},
              ],
            },
          ],
          'generationConfig': {
            'maxOutputTokens': prompt.maxTokens,
            'temperature': 0.3,
          },
        }),
      );

      final response = await request.close().timeout(
        const Duration(minutes: 3),
      );
      if (response.statusCode != HttpStatus.ok) {
        await response.drain<void>();
        throw GeminiSummaryProviderException(
          response.statusCode == HttpStatus.tooManyRequests
              ? 'usageLimit'
              : 'requestRejected',
          statusCode: response.statusCode,
        );
      }

      final decoded = jsonDecode(await utf8.decoder.bind(response).join());
      if (decoded is! Map<String, dynamic>) {
        throw const GeminiSummaryProviderException('invalidResponse');
      }
      final candidates = decoded['candidates'];
      if (candidates is! List || candidates.isEmpty) {
        throw const GeminiSummaryProviderException('emptyResponse');
      }
      final content = candidates.first;
      final contentData = content is Map ? content['content'] : null;
      final parts = contentData is Map ? contentData['parts'] : null;
      if (parts is! List) {
        throw const GeminiSummaryProviderException('invalidResponse');
      }
      final raw = parts
          .whereType<Map>()
          .map((part) => part['text'])
          .whereType<String>()
          .join('\n');
      if (raw.trim().isEmpty) {
        throw const GeminiSummaryProviderException('emptyResponse');
      }
      return prompt.maxTokens <= 32 ? cleanTitle(raw) : cleanLlmOutput(raw);
    } on GeminiSummaryProviderException {
      rethrow;
    } on TimeoutException {
      throw const GeminiSummaryProviderException('timeout');
    } catch (_) {
      throw const GeminiSummaryProviderException('networkOrResponse');
    } finally {
      client.close(force: true);
    }
  }
}

class GeminiSummaryProviderException implements Exception {
  const GeminiSummaryProviderException(this.code, {this.statusCode});

  final String code;
  final int? statusCode;

  @override
  String toString() => 'GeminiSummaryProviderException($code)';
}
