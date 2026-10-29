import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:diktafon/services/audio/pcm_decoder.dart';
import 'package:diktafon/services/providers/credential_vault.dart';
import 'package:diktafon/services/providers/transcription_provider.dart';
import 'package:diktafon/services/providers/gemini/gemini_audio_chunks.dart';
import 'package:diktafon/services/providers/gemini/gemini_connection_probe.dart';
import 'package:diktafon/services/providers/gemini/gemini_transcription_provider.dart';

class _Vault extends CredentialVault {
  @override
  Future<String?> readGeminiKey() async => 'test-only-key';
}

class _Decoder implements PcmDecoder {
  @override
  Future<void> decodeToF32(String audioPath, String pcmPath) => File(
    pcmPath,
  ).writeAsBytes(Float32List(12 * 16000).buffer.asUint8List()).then((_) {});
}

void main() {
  test(
    'production adapter sends bounded WAV requests and resumes at failed part',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'gemini-provider-',
      );
      final audio = await File(
        '${directory.path}/source.m4a',
      ).writeAsString('source');
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() async {
        await server.close(force: true);
        await directory.delete(recursive: true);
      });
      var requests = 0;
      server.listen((request) async {
        requests++;
        final body = jsonDecode(await utf8.decoder.bind(request).join()) as Map;
        expect(
          request.uri.path,
          '/v1beta/models/gemini-2.5-flash:generateContent',
        );
        expect(request.uri.hasQuery, isFalse);
        expect(request.headers.value('x-goog-api-key'), 'test-only-key');
        final parts = body['contents'][0]['parts'] as List;
        expect(parts.any((p) => p.containsKey('fileData')), isFalse);
        final inline = parts.last['inlineData'];
        expect(inline['mimeType'], 'audio/wav');
        final wav = base64Decode(inline['data'] as String);
        expect(wav.length, lessThanOrEqualTo(44 + 5 * 16000 * 2));
        if (requests == 3) {
          request.response.statusCode = 503;
          request.response.write('private-provider-error-must-not-escape');
        } else {
          request.response.write(
            jsonEncode({
              'candidates': [
                {
                  'finishReason': 'STOP',
                  'content': {
                    'parts': [
                      {
                        'text': jsonEncode({
                          'lang': 'es',
                          'segments': [
                            {
                              's': 1300,
                              'e': 1500,
                              'w': [
                                {'t': 'Hola', 's': 1300, 'e': 1500},
                              ],
                            },
                          ],
                        }),
                      },
                    ],
                  },
                },
              ],
            }),
          );
        }
        await request.response.close();
      });
      final provider = GeminiTranscriptionProvider(
        vault: _Vault(),
        modelId: 'gemini-2.5-flash',
        chunks: GeminiAudioChunks(
          decoder: _Decoder(),
          chunkSeconds: 3,
          contextSeconds: 1,
        ),
        apiBase: Uri.parse('http://127.0.0.1:${server.port}/v1beta/'),
      );
      await expectLater(
        provider.transcribe(AudioRef(audio.path)),
        throwsA(
          isA<GeminiProbeException>().having(
            (e) => e.statusCode,
            'HTTP status',
            503,
          ),
        ),
      );
      final transcript = await provider.transcribe(AudioRef(audio.path));
      expect(requests, 5);
      expect(transcript.segments.map((s) => s.words.single.startMs), [
        1300,
        3300,
        6300,
        9300,
      ]);
      expect(await audio.readAsString(), 'source');
    },
  );
}
