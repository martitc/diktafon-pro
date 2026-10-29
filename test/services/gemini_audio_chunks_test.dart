import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:diktafon/domain/models.dart';
import 'package:diktafon/services/audio/pcm_decoder.dart';
import 'package:diktafon/services/providers/transcription_provider.dart';
import 'package:diktafon/services/providers/gemini/gemini_audio_chunks.dart';

class _Decoder implements PcmDecoder {
  @override
  Future<void> decodeToF32(String audioPath, String pcmPath) async {
    final pcm = Float32List(12 * 16000);
    pcm[0] = 0.5;
    await File(pcmPath).writeAsBytes(pcm.buffer.asUint8List());
  }
}

void main() {
  late Directory directory;
  late File audio;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('gemini-chunks-test-');
    audio = await File(
      '${directory.path}/recording.m4a',
    ).writeAsString('input');
  });
  tearDown(() => directory.delete(recursive: true));

  Transcript reply() => const Transcript(
    languageCode: 'es',
    segments: [
      Segment(
        startMs: 1300,
        endMs: 1500,
        words: [Word(text: 'Hola', startMs: 1300, endMs: 1500)],
      ),
    ],
  );

  test('one hour is bounded to twenty requests plus boundary context', () {
    final parts = planGeminiAudioChunks(3600 * 16000);
    expect(parts, hasLength(20));
    expect(parts.first.coreStartFrame, 0);
    expect(parts.last.coreEndFrame, 3600 * 16000);
    for (var i = 0; i < parts.length; i++) {
      expect(
        parts[i].endFrame - parts[i].startFrame,
        lessThanOrEqualTo(184 * 16000),
      );
      if (i > 0) expect(parts[i].coreStartFrame, parts[i - 1].coreEndFrame);
    }
  });

  test('sends bounded PCM16 WAV and restores original timestamps', () async {
    final chunker = GeminiAudioChunks(
      decoder: _Decoder(),
      chunkSeconds: 3,
      contextSeconds: 1,
    );
    var calls = 0;
    final transcript = await chunker.transcribe(
      audio.path,
      namespace: 'model/es',
      cancel: CancelToken(),
      send: (bytes) async {
        final data = ByteData.sublistView(Uint8List.fromList(bytes));
        expect(String.fromCharCodes(bytes.take(4)), 'RIFF');
        expect(data.getUint16(20, Endian.little), 1);
        expect(data.getUint32(24, Endian.little), 16000);
        expect(data.getUint32(40, Endian.little), bytes.length - 44);
        if (calls == 0) expect(data.getInt16(44, Endian.little), 16384);
        calls++;
        return reply();
      },
    );
    expect(calls, 4);
    expect(transcript.segments.map((s) => s.words.single.startMs), [
      1300,
      3300,
      6300,
      9300,
    ]);
  });

  test(
    'retry reuses completed parts and never returns partial success',
    () async {
      final chunker = GeminiAudioChunks(
        decoder: _Decoder(),
        chunkSeconds: 3,
        contextSeconds: 1,
      );
      var calls = 0;
      Future<Transcript> send(List<int> bytes) async {
        calls++;
        if (calls == 3) throw const HttpException('test failure');
        return reply();
      }

      await expectLater(
        chunker.transcribe(
          audio.path,
          namespace: 'model/es',
          cancel: CancelToken(),
          send: send,
        ),
        throwsA(isA<HttpException>()),
      );
      final complete = await chunker.transcribe(
        audio.path,
        namespace: 'model/es',
        cancel: CancelToken(),
        send: send,
      );
      expect(calls, 5);
      expect(complete.segments, hasLength(4));
      await chunker.transcribe(
        audio.path,
        namespace: 'model/es',
        cancel: CancelToken(),
        send: send,
      );
      expect(
        calls,
        9,
        reason: 'successful results release their in-memory cache',
      );
    },
  );

  test('cancellation stops before sending another part', () async {
    final cancel = CancelToken();
    var calls = 0;
    await expectLater(
      GeminiAudioChunks(decoder: _Decoder(), chunkSeconds: 3).transcribe(
        audio.path,
        namespace: 'model',
        cancel: cancel,
        send: (bytes) async {
          calls++;
          cancel.cancel();
          return reply();
        },
      ),
      throwsA(isA<TranscriptionCancelled>()),
    );
    expect(calls, 1);
  });
  test('overlapping context keeps a boundary word only once', () async {
    var calls = 0;
    final result =
        await GeminiAudioChunks(
          decoder: _Decoder(),
          chunkSeconds: 3,
          contextSeconds: 1,
        ).transcribe(
          audio.path,
          namespace: 'model',
          cancel: CancelToken(),
          send: (bytes) async {
            final current = calls++;
            if (current > 1) {
              return const Transcript(languageCode: 'es', segments: []);
            }
            final words = current == 0
                ? const [
                    Word(text: 'antes', startMs: 2500, endMs: 2700),
                    Word(text: 'borde', startMs: 2900, endMs: 3100),
                  ]
                : const [
                    Word(text: 'borde', startMs: 900, endMs: 1100),
                    Word(text: 'despues', startMs: 2000, endMs: 2200),
                  ];
            return Transcript(
              languageCode: 'es',
              segments: [
                Segment(
                  startMs: words.first.startMs,
                  endMs: words.last.endMs,
                  words: words,
                ),
              ],
            );
          },
        );
    expect(result.segments.expand((s) => s.words).map((w) => w.text), [
      'antes',
      'borde',
      'despues',
    ]);
    expect(result.segments.expand((s) => s.words).map((w) => w.startMs), [
      2500,
      2900,
      4000,
    ]);
  });

  test('changing the namespace never reuses previous model results', () async {
    final chunker = GeminiAudioChunks(
      decoder: _Decoder(),
      chunkSeconds: 3,
      contextSeconds: 1,
    );
    var calls = 0;
    Future<Transcript> send(List<int> bytes) async {
      if (++calls == 3) throw const HttpException('test failure');
      return reply();
    }

    await expectLater(
      chunker.transcribe(
        audio.path,
        namespace: 'model-a/es',
        cancel: CancelToken(),
        send: send,
      ),
      throwsA(isA<HttpException>()),
    );
    await chunker.transcribe(
      audio.path,
      namespace: 'model-b/es',
      cancel: CancelToken(),
      send: send,
    );
    expect(calls, 7);
  });

  test(
    'rejects output outside chunk duration instead of saving corrupt times',
    () async {
      await expectLater(
        GeminiAudioChunks(
          decoder: _Decoder(),
          chunkSeconds: 3,
          contextSeconds: 1,
        ).transcribe(
          audio.path,
          namespace: 'model',
          cancel: CancelToken(),
          send: (bytes) async => const Transcript(
            languageCode: 'es',
            segments: [
              Segment(
                startMs: 0,
                endMs: 999999,
                words: [Word(text: 'wrong', startMs: 0, endMs: 999999)],
              ),
            ],
          ),
        ),
        throwsA(isA<FormatException>()),
      );
    },
  );
}
