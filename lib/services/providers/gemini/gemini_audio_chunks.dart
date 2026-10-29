/// Bounded Gemini requests over decoded audio. Only completed chunks are cached
/// in memory for retries in this process; no partial transcript is published.
library;

import 'dart:io';
import 'dart:typed_data';

import '../../../domain/models.dart';
import '../../../domain/processing_progress.dart';
import '../../audio/pcm_decoder.dart';
import '../transcription_provider.dart';

const _sampleRate = 16000;

class GeminiAudioPart {
  const GeminiAudioPart(
    this.startFrame,
    this.endFrame,
    this.coreStartFrame,
    this.coreEndFrame,
  );
  final int startFrame;
  final int endFrame;
  final int coreStartFrame;
  final int coreEndFrame;
}

List<GeminiAudioPart> planGeminiAudioChunks(
  int frames, {
  int chunkSeconds = 180,
  int contextSeconds = 2,
}) {
  if (frames < 0 || chunkSeconds <= 0 || contextSeconds < 0) {
    throw ArgumentError('Invalid audio chunk geometry');
  }
  final step = chunkSeconds * _sampleRate;
  final context = contextSeconds * _sampleRate;
  return [
    for (var start = 0; start < frames; start += step)
      GeminiAudioPart(
        (start - context).clamp(0, frames),
        (start + step + context).clamp(0, frames),
        start,
        (start + step).clamp(0, frames),
      ),
  ];
}

class GeminiAudioChunks {
  GeminiAudioChunks({
    required this.decoder,
    this.chunkSeconds = 180,
    this.contextSeconds = 2,
  });
  final PcmDecoder decoder;
  final int chunkSeconds;
  final int contextSeconds;
  final _completed = <String, Map<int, Transcript>>{};

  Future<Transcript> transcribe(
    String audioPath, {
    required String namespace,
    required CancelToken cancel,
    required Future<Transcript> Function(List<int>) send,
    TranscriptionProgressSink? onProgress,
  }) async {
    void checkCancelled() {
      if (cancel.isCancelled) throw const TranscriptionCancelled();
    }

    checkCancelled();
    final stat = await File(audioPath).stat();
    final key =
        '$namespace:$audioPath:${stat.size}:${stat.modified.microsecondsSinceEpoch}';
    // Bound retention when several different memos fail. Changing the model,
    // language, source or instructions must not reuse a different result.
    if (!_completed.containsKey(key) && _completed.length >= 4) {
      _completed.remove(_completed.keys.first);
    }
    final cache = _completed.putIfAbsent(key, () => <int, Transcript>{});
    final temporary = await Directory.systemTemp.createTemp('diktafon-gemini-');
    RandomAccessFile? reader;
    try {
      final pcm = File('${temporary.path}/decoded.f32');
      onProgress?.call(ProcessingStage.transcribing, null);
      await decoder.decodeToF32(audioPath, pcm.path);
      checkCancelled();
      final bytes = await pcm.length();
      if (bytes % 4 != 0) throw const FormatException('Invalid decoded PCM');
      final frames = bytes ~/ 4;
      final parts = planGeminiAudioChunks(
        frames,
        chunkSeconds: chunkSeconds,
        contextSeconds: contextSeconds,
      );
      reader = await pcm.open();
      final segments = <Segment>[];
      final languages = <String, int>{};
      for (var i = 0; i < parts.length; i++) {
        checkCancelled();
        final part = parts[i];
        // This fraction measures audio covered by completed transcripts,
        // never Google's unreported progress inside the current request.
        onProgress?.call(
          ProcessingStage.transcribing,
          part.coreStartFrame / frames,
        );
        final transcript = cache[i] ?? await send(await _wav(reader, part));
        checkCancelled();
        final merged = _ownedSegments(transcript, part);
        cache[i] = transcript;
        segments.addAll(merged);
        languages.update(
          transcript.languageCode,
          (count) => count + merged.fold<int>(0, (n, s) => n + s.words.length),
          ifAbsent: () => merged.fold<int>(0, (n, s) => n + s.words.length),
        );
        onProgress?.call(
          ProcessingStage.transcribing,
          part.coreEndFrame / frames,
        );
      }
      _completed.remove(key);
      final language = languages.isEmpty
          ? 'und'
          : languages.keys.reduce(
              (a, b) => languages[a]! >= languages[b]! ? a : b,
            );
      return Transcript(languageCode: language, segments: segments);
    } on TranscriptionCancelled {
      _completed.remove(key);
      rethrow;
    } finally {
      await reader?.close();
      try {
        await temporary.delete(recursive: true);
      } catch (_) {
        // OS cache cleanup can reclaim an already removed temporary directory.
      }
    }
  }

  static Future<Uint8List> _wav(
    RandomAccessFile reader,
    GeminiAudioPart part,
  ) async {
    final frames = part.endFrame - part.startFrame;
    final input = Uint8List(frames * 4);
    await reader.setPosition(part.startFrame * 4);
    var read = 0;
    while (read < input.length) {
      final count = await reader.readInto(input, read);
      if (count == 0) throw const FormatException('Truncated decoded PCM');
      read += count;
    }
    final result = Uint8List(44 + frames * 2);
    final header = ByteData.sublistView(result);
    result.setRange(0, 4, 'RIFF'.codeUnits);
    header.setUint32(4, result.length - 8, Endian.little);
    result.setRange(8, 16, 'WAVEfmt '.codeUnits);
    header.setUint32(16, 16, Endian.little);
    header.setUint16(20, 1, Endian.little);
    header.setUint16(22, 1, Endian.little);
    header.setUint32(24, _sampleRate, Endian.little);
    header.setUint32(28, _sampleRate * 2, Endian.little);
    header.setUint16(32, 2, Endian.little);
    header.setUint16(34, 16, Endian.little);
    result.setRange(36, 40, 'data'.codeUnits);
    header.setUint32(40, frames * 2, Endian.little);
    final data = ByteData.sublistView(input);
    for (var i = 0; i < frames; i++) {
      final value = data.getFloat32(i * 4, Endian.little);
      header.setInt16(
        44 + i * 2,
        value.isFinite ? (value * 32768).round().clamp(-32768, 32767) : 0,
        Endian.little,
      );
    }
    return result;
  }

  static List<Segment> _ownedSegments(
    Transcript transcript,
    GeminiAudioPart part,
  ) {
    final offsetMs = part.startFrame * 1000 ~/ _sampleRate;
    final coreStartMs = part.coreStartFrame * 1000 ~/ _sampleRate;
    final coreEndMs = part.coreEndFrame * 1000 ~/ _sampleRate;
    final durationMs = (part.endFrame - part.startFrame) * 1000 ~/ _sampleRate;
    final output = <Segment>[];
    for (final segment in transcript.segments) {
      final words = <Word>[];
      for (final word in segment.words) {
        if (word.startMs < 0 ||
            word.endMs < word.startMs ||
            word.endMs > durationMs) {
          throw const FormatException('Chunk timestamps exceed audio bounds');
        }
        final start = offsetMs + word.startMs;
        final end = offsetMs + word.endMs;
        final midpoint = (start + end) / 2;
        // Overlap is context only. Each word belongs to one core window.
        if (midpoint >= coreStartMs && midpoint < coreEndMs) {
          words.add(Word(text: word.text, startMs: start, endMs: end));
        }
      }
      if (words.isNotEmpty) {
        output.add(
          Segment(
            startMs: words.first.startMs,
            endMs: words.last.endMs,
            words: words,
          ),
        );
      }
    }
    return output;
  }
}
