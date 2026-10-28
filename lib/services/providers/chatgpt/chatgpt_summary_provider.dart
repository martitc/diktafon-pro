import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../../domain/models.dart';
import '../credential_vault.dart';
import '../summarization_provider.dart';
import '../transcription_provider.dart' show ModelStatus, ProgressSink;
import '../llm/summary_prompts.dart';
import 'chatgpt_connection_probe.dart';

/// Responses API adapter for the OAuth subscription. It is only used for
/// summaries; audio remains on Whisper or Gemini.
class ChatGptSummaryProvider implements SummarizationProvider {
  ChatGptSummaryProvider({
    required this._vault,
    required this.model,
    required this.reasoning,
    HttpClient Function()? httpClientFactory,
  }) : _httpClientFactory = httpClientFactory ?? HttpClient.new;

  final CredentialVault _vault;
  final String model;
  final String reasoning;
  final HttpClient Function() _httpClientFactory;

  @override
  String get id => 'chatgpt/$model/$reasoning';

  @override
  Future<ModelStatus> modelStatus() async =>
      await _vault.readChatGptTokens() == null
      ? ModelStatus.notInstalled
      : ModelStatus.ready;

  @override
  Future<void> ensureModel({ProgressSink? onProgress}) async {
    if (await _vault.readChatGptTokens() == null) {
      throw const ChatGptSummaryException('notConnected');
    }
  }

  @override
  Future<String> summarizeMemo(
    Transcript t, {
    required String languageCode,
  }) async => _complete(memoSummaryPrompt(t, languageCode: languageCode));

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
    ),
  );

  @override
  Future<String> suggestTitle(
    String cassetteSummary, {
    required String languageCode,
  }) => _complete(titlePrompt(cassetteSummary, languageCode: languageCode));

  Future<String> _complete(LlmPrompt prompt) async {
    final tokens = await _usableTokens();
    final client = _httpClientFactory();
    try {
      final request = await client
          .postUrl(Uri.https('api.openai.com', '/v1/responses'))
          .timeout(const Duration(seconds: 30));
      request.followRedirects = false;
      request.headers
        ..set(HttpHeaders.authorizationHeader, 'Bearer ${tokens.accessToken}')
        ..contentType = ContentType.json
        ..set(HttpHeaders.acceptHeader, 'text/event-stream');
      request.write(
        jsonEncode({
          'model': model,
          'store': false,
          'stream': true,
          'reasoning': {'effort': reasoning},
          'input': [
            {'role': 'system', 'content': prompt.system},
            {'role': 'user', 'content': prompt.user},
          ],
          'max_output_tokens': prompt.maxTokens,
        }),
      );
      final response = await request.close().timeout(
        const Duration(minutes: 3),
      );
      if (response.statusCode != HttpStatus.ok) {
        await response.drain<void>();
        throw ChatGptSummaryException(
          response.statusCode == HttpStatus.tooManyRequests
              ? 'usageLimit'
              : 'requestRejected',
          statusCode: response.statusCode,
        );
      }
      final output = StringBuffer();
      var completed = false;
      String data = '';
      await for (final line
          in response
              .transform(utf8.decoder)
              .transform(const LineSplitter())
              .timeout(const Duration(minutes: 3))) {
        if (line.startsWith('data:')) {
          data = line.substring(5).trim();
          if (data == '[DONE]') continue;
          try {
            final event = jsonDecode(data) as Map<String, dynamic>;
            switch (event['type']) {
              case 'response.output_text.delta':
                final delta = event['delta'];
                if (delta is String) output.write(delta);
              case 'response.completed':
                completed = true;
              case 'response.failed':
              case 'error':
                throw const ChatGptSummaryException('responseFailed');
            }
          } catch (error) {
            if (error is ChatGptSummaryException) rethrow;
            throw const ChatGptSummaryException('invalidStream');
          }
        }
      }
      if (!completed) throw const ChatGptSummaryException('incompleteResponse');
      return prompt.maxTokens <= 32
          ? cleanTitle(output.toString())
          : cleanLlmOutput(output.toString());
    } on ChatGptSummaryException {
      rethrow;
    } on TimeoutException {
      throw const ChatGptSummaryException('timeout');
    } catch (_) {
      throw const ChatGptSummaryException('networkFailure');
    } finally {
      client.close(force: true);
    }
  }

  Future<ProbeTokenSet> _usableTokens() async {
    var tokens = await _vault.readChatGptTokens();
    if (tokens == null) throw const ChatGptSummaryException('notConnected');
    if (tokens.expiresAt.isBefore(
      DateTime.now().add(const Duration(minutes: 1)),
    )) {
      final api = ChatGptConnectionProbe();
      try {
        tokens = await api.refresh(tokens);
        await _vault.writeChatGptTokens(tokens);
      } on ProbeException {
        throw const ChatGptSummaryException('reauthorizationRequired');
      } finally {
        api.close();
      }
    }
    return tokens;
  }
}

class ChatGptSummaryException implements Exception {
  const ChatGptSummaryException(this.code, {this.statusCode});
  final String code;
  final int? statusCode;
  @override
  String toString() => 'ChatGptSummaryException($code)';
}
