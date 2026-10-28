import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:diktafon/services/providers/gemini/gemini_connection_probe.dart';

void main() {
  late HttpServer server;
  late GeminiConnectionProbe probe;
  late HttpClient client;
  late Object result;
  late int status;
  late String finishReason;
  late bool keepErrorOpen;
  late List<Map<String, Object?>> requests;
  final transcript = <String, Object?>{
    'lang': 'es',
    'segments': [
      {
        's': 100,
        'e': 700,
        'w': [
          {'t': 'Hola', 's': 100, 'e': 700},
        ],
      },
    ],
  };

  setUp(() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    client = HttpClient();
    probe = GeminiConnectionProbe(
      client: client,
      apiBase: Uri.parse('http://127.0.0.1:${server.port}/v1beta/'),
    );
    status = 200;
    finishReason = 'STOP';
    keepErrorOpen = false;
    result = transcript;
    requests = [];
    server.listen((request) async {
      final body = await utf8.decoder.bind(request).join();
      requests.add({
        'uri': request.uri.toString(),
        'key': request.headers.value('x-goog-api-key'),
        'method': request.method,
        'body': jsonDecode(body),
      });
      request.response.statusCode = status;
      if (status == 302) {
        request.response.headers.set('location', '/redirected');
      }
      request.response.write(
        jsonEncode(
          status == 200
              ? {
                  'candidates': [
                    {
                      'finishReason': finishReason,
                      'content': {
                        'parts': [
                          {
                            'text': result is String
                                ? result
                                : jsonEncode(result),
                          },
                        ],
                      },
                    },
                  ],
                }
              : {
                  'error': {'message': 'SECRET-key private prompt audio'},
                },
        ),
      );
      if (keepErrorOpen) {
        await request.response.flush();
      } else {
        await request.response.close();
      }
    });
  });

  tearDown(() async {
    client.close(force: true);
    await server.close(force: true);
  });

  Future<dynamic> transcribe({
    String key = 'SECRET-key',
    String model = 'test-model',
    List<int> bytes = const [1, 2, 3],
    String mime = 'audio/wav',
    String instructions = 'Conserva nombres propios',
  }) => probe.transcribe(
    audioBytes: bytes,
    mimeType: mime,
    apiKey: key,
    model: model,
    instructions: instructions,
  );

  test(
    'sends audio, editable instructions and schema; key only in header',
    () async {
      final actual = await transcribe();
      expect(actual.toJson(), transcript);
      expect(requests, hasLength(1));
      final request = requests.single;
      expect(request['uri'], '/v1beta/models/test-model:generateContent');
      expect(request['method'], 'POST');
      expect(request['key'], 'SECRET-key');
      expect(jsonEncode(request['body']), isNot(contains('SECRET-key')));
      final body = request['body'] as Map;
      final parts = (body['contents'] as List).single['parts'] as List;
      expect(parts.any((p) => p['text'] == 'Conserva nombres propios'), isTrue);
      expect(parts.last['inlineData'], {
        'mimeType': 'audio/wav',
        'data': 'AQID',
      });
      expect(body['generationConfig']['responseMimeType'], 'application/json');
      final schema = body['generationConfig']['responseSchema'];
      expect(schema['required'], containsAll(['lang', 'segments']));
      expect(
        schema['properties']['segments']['items']['required'],
        containsAll(['s', 'e', 'w']),
      );
    },
  );

  test('rejects absent key or model before any request', () async {
    for (final call in [
      () => transcribe(key: ' '),
      () => transcribe(model: ''),
    ]) {
      await expectLater(call(), throwsA(isA<GeminiProbeException>()));
    }
    expect(requests, isEmpty);
  });

  test(
    'rejects empty audio, invalid MIME and size including encoded payload',
    () async {
      for (final call in [
        () => transcribe(bytes: []),
        () => transcribe(mime: 'text/plain'),
        () => transcribe(bytes: List.filled(20000000, 0)),
        () => transcribe(bytes: List.filled(15000000, 0)),
      ]) {
        await expectLater(call(), throwsA(isA<GeminiProbeException>()));
      }
      expect(requests, isEmpty);
    },
  );

  test('rejects JSON syntax and missing required schema fields', () async {
    for (final invalid in [
      'not json',
      {'lang': 'es'},
      {'lang': '', 'segments': []},
      {
        'lang': 'es',
        'segments': [
          {'s': 0, 'e': 1},
        ],
      },
    ]) {
      result = invalid;
      await expectLater(transcribe(), throwsA(isA<GeminiProbeException>()));
    }
  });

  test(
    'rejects negative, reversed, unordered and out of segment timestamps',
    () async {
      for (final segments in [
        [
          {'s': -1, 'e': 1, 'w': []},
        ],
        [
          {'s': 2, 'e': 1, 'w': []},
        ],
        [
          {'s': 0.5, 'e': 1, 'w': []},
        ],
        [
          {'s': 2, 'e': 3, 'w': []},
          {'s': 0, 'e': 1, 'w': []},
        ],
        [
          {
            's': 0,
            'e': 3,
            'w': [
              {'t': 'x', 's': 0, 'e': 4},
            ],
          },
        ],
        [
          {
            's': 0,
            'e': 3,
            'w': [
              {'t': 'x', 's': 2, 'e': 3},
              {'t': 'y', 's': 0, 'e': 1},
            ],
          },
        ],
      ]) {
        result = {'lang': 'es', 'segments': segments};
        await expectLater(transcribe(), throwsA(isA<GeminiProbeException>()));
      }
    },
  );

  test(
    'rejects truncated generation instead of publishing a partial transcript',
    () async {
      finishReason = 'MAX_TOKENS';
      await expectLater(transcribe(), throwsA(isA<GeminiProbeException>()));
    },
  );

  test('does not follow redirects with credentials', () async {
    status = 302;
    await expectLater(transcribe(), throwsA(isA<GeminiProbeException>()));
    expect(requests, hasLength(1));
  });

  test('rejects HTTP error without waiting for an endless body', () async {
    status = 401;
    keepErrorOpen = true;
    await expectLater(
      transcribe().timeout(const Duration(seconds: 2)),
      throwsA(isA<GeminiProbeException>()),
    );
  });

  test(
    '401 reports safe typed failure without provider body or secrets',
    () async {
      status = 401;
      try {
        await transcribe();
        fail('Expected rejection');
      } on GeminiProbeException catch (error) {
        expect(error.kind, GeminiProbeFailure.http);
        expect(error.statusCode, 401);
        for (final secret in ['SECRET-key', 'private', 'prompt', 'audio']) {
          expect(error.toString(), isNot(contains(secret)));
        }
      }
    },
  );
}
