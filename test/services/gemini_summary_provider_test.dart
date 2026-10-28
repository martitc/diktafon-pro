import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:diktafon/domain/models.dart';
import 'package:diktafon/services/providers/credential_vault.dart';
import 'package:diktafon/services/providers/gemini/gemini_summary_provider.dart';
import 'package:diktafon/services/providers/summarization_provider.dart';
import 'package:flutter_test/flutter_test.dart';

class _Vault extends CredentialVault {
  _Vault(this.key);
  final String? key;

  @override
  Future<String?> readGeminiKey() async => key;
}

void main() {
  late HttpServer server;
  late Uri endpoint;
  late Map<String, dynamic> requestBody;
  late String apiKey;
  late int statusCode;
  late String requestPath;

  Transcript transcript() => const Transcript(
    languageCode: 'es',
    segments: [
      Segment(
        startMs: 0,
        endMs: 1900,
        words: [
          Word(startMs: 0, endMs: 900, text: 'Hola'),
          Word(startMs: 950, endMs: 1900, text: 'mundo'),
        ],
      ),
    ],
  );

  Uri apiBase() => endpoint.replace(path: '/v1beta/');

  setUp(() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    endpoint = Uri.parse('http://${server.address.address}:${server.port}');
    requestBody = {};
    apiKey = '';
    requestPath = '';
    statusCode = HttpStatus.ok;
    unawaited(() async {
      await for (final request in server) {
        apiKey = request.headers.value('x-goog-api-key') ?? '';
        requestPath = request.uri.path;
        requestBody =
            jsonDecode(await utf8.decoder.bind(request).join())
                as Map<String, dynamic>;
        request.response.statusCode = statusCode;
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode({
            'candidates': [
              {
                'content': {
                  'parts': [
                    {'text': '  Resumen breve.  '},
                  ],
                },
              },
            ],
          }),
        );
        await request.response.close();
      }
    }());
  });

  tearDown(() async => server.close(force: true));

  test('sends only text with the Gemini key and cleans the summary', () async {
    final provider = GeminiSummaryProvider(
      vault: _Vault('secret-test-key'),
      modelId: 'gemini-2.5-flash',
      instructions: 'Incluye los acuerdos.',
      endpointBase: apiBase(),
    );

    final summary = await provider.summarizeMemo(
      transcript(),
      languageCode: 'es',
    );

    expect(summary, 'Resumen breve.');
    expect(apiKey, 'secret-test-key');
    expect(requestPath, '/v1beta/models/gemini-2.5-flash:generateContent');
    expect(requestBody['contents'], isA<List<dynamic>>());
    expect(jsonEncode(requestBody), contains('Hola mundo'));
    expect(jsonEncode(requestBody), contains('Spanish'));
    expect(jsonEncode(requestBody), contains('Incluye los acuerdos.'));
    expect(jsonEncode(requestBody), isNot(contains('secret-test-key')));
  });

  test('requires a Gemini key before sending a request', () async {
    final provider = GeminiSummaryProvider(
      vault: _Vault(null),
      modelId: 'gemini-2.5-flash',
      endpointBase: apiBase(),
    );

    await expectLater(
      provider.summarizeMemo(transcript(), languageCode: 'es'),
      throwsA(isA<GeminiSummaryProviderException>()),
    );
    expect(apiKey, isEmpty);
    expect(requestBody, isEmpty);
  });

  test('maps provider errors without exposing response content', () async {
    statusCode = HttpStatus.tooManyRequests;
    final provider = GeminiSummaryProvider(
      vault: _Vault('secret-test-key'),
      modelId: 'gemini-2.5-flash',
      endpointBase: apiBase(),
    );

    await expectLater(
      provider.summarizeMemo(transcript(), languageCode: 'es'),
      throwsA(
        isA<GeminiSummaryProviderException>().having(
          (error) => error.code,
          'code',
          'usageLimit',
        ),
      ),
    );
  });

  test(
    'updates cassette summaries and suggests titles with text prompts',
    () async {
      final provider = GeminiSummaryProvider(
        vault: _Vault('secret-test-key'),
        modelId: 'gemini-2.5-flash',
        endpointBase: apiBase(),
      );

      final summary = await provider.updateCassetteSummary(
        previousSummary: 'Resumen anterior.',
        newMemos: [
          MemoDigest(
            memoSummary: 'Se acordó reunirse el martes.',
            createdAt: DateTime.utc(2026),
          ),
        ],
        languageCode: 'es',
      );
      expect(summary, 'Resumen breve.');
      expect(jsonEncode(requestBody), contains('Resumen anterior.'));
      expect(jsonEncode(requestBody), contains('martes'));

      final title = await provider.suggestTitle(
        'Organizar la reunión del martes.',
        languageCode: 'es',
      );
      expect(title, 'Resumen breve');
      expect(
        jsonEncode(requestBody),
        contains('Organizar la reunión del martes'),
      );
    },
  );
}
