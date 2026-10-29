/// Bounded Gemini transcription request, also used by the connection probe.
/// Protocol: https://ai.google.dev/gemini-api/docs/generate-content/audio
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../../domain/models.dart';

enum GeminiProbeFailure {
  configuration,
  invalidAudio,
  requestTooLarge,
  timeout,
  transport,
  http,
  invalidResponse,
}

/// Contains only fixed categories and an HTTP status, never provider content.
class GeminiProbeException implements Exception {
  const GeminiProbeException(this.kind, {this.statusCode});
  final GeminiProbeFailure kind;
  final int? statusCode;

  @override
  String toString() =>
      'GeminiProbeException(${kind.name}'
      '${statusCode == null ? '' : ', status=$statusCode'})';
}

class GeminiConnectionProbe {
  GeminiConnectionProbe({
    this.client,
    Uri? apiBase,
    this.requestTimeout = const Duration(seconds: 90),
  }) : _apiBase =
           apiBase ??
           Uri.parse('https://generativelanguage.googleapis.com/v1beta/');

  /// Optional caller-owned transport; the caller is responsible for closing it.
  final HttpClient? client;
  final Uri _apiBase;
  static const _maxRequestBytes = 20000000;
  static const _maxResponseBytes = 4000000;
  final Duration requestTimeout;

  /// Uses inline audio for a short sample. Larger requests need Files API,
  /// which is deliberately outside this probe. Model availability and actual
  /// word timing accuracy still require a real account/audio smoke test.
  Future<Transcript> transcribe({
    required List<int> audioBytes,
    required String mimeType,
    required String apiKey,
    required String model,
    String? audioFileUri,
    String instructions = '',
  }) async {
    if (apiKey.trim().isEmpty ||
        !RegExp(r'^[A-Za-z0-9._-]+$').hasMatch(model) ||
        _apiBase.userInfo.isNotEmpty ||
        _apiBase.hasQuery ||
        _apiBase.hasFragment ||
        !(_apiBase.scheme == 'https' ||
            (_apiBase.scheme == 'http' &&
                ['127.0.0.1', '::1', 'localhost'].contains(_apiBase.host)))) {
      throw const GeminiProbeException(GeminiProbeFailure.configuration);
    }
    if ((audioFileUri == null && audioBytes.isEmpty) ||
        (audioFileUri != null &&
            (!audioFileUri.startsWith(
                  'https://generativelanguage.googleapis.com/',
                ) ||
                audioFileUri.contains('?') ||
                audioFileUri.contains('#'))) ||
        !RegExp(r'^audio/[A-Za-z0-9.+-]+$').hasMatch(mimeType) ||
        audioBytes.any((byte) => byte < 0 || byte > 255)) {
      throw const GeminiProbeException(GeminiProbeFailure.invalidAudio);
    }
    if (audioFileUri == null && audioBytes.length >= _maxRequestBytes) {
      throw const GeminiProbeException(GeminiProbeFailure.requestTooLarge);
    }
    final payload = utf8.encode(
      jsonEncode({
        'contents': [
          {
            'role': 'user',
            'parts': [
              {
                'text':
                    'Transcribe the attached audio in its original language. '
                    'Return lang as its language code and segments containing '
                    'words. All s/e timestamps are integer milliseconds from '
                    'the start of the audio, in chronological order. Each word '
                    'must lie within its segment. Use only timings supported by '
                    'the audio; do not fabricate timestamps. Return JSON only.',
              },
              if (instructions.isNotEmpty) {'text': instructions},
              if (audioFileUri == null)
                {
                  'inlineData': {
                    'mimeType': mimeType,
                    'data': base64Encode(audioBytes),
                  },
                }
              else
                {
                  'fileData': {'mimeType': mimeType, 'fileUri': audioFileUri},
                },
            ],
          },
        ],
        'generationConfig': {
          'responseMimeType': 'application/json',
          'responseSchema': _schema,
        },
      }),
    );
    if (audioFileUri == null && payload.length >= _maxRequestBytes) {
      throw const GeminiProbeException(GeminiProbeFailure.requestTooLarge);
    }
    final transport = client ?? HttpClient();
    try {
      // Query-free URI and no redirects keep the key solely in this header.
      final basePath = _apiBase.path.endsWith('/')
          ? _apiBase.path
          : '${_apiBase.path}/';
      final uri = _apiBase.replace(
        path: '${basePath}models/$model:generateContent',
      );
      final request = await transport.postUrl(uri).timeout(requestTimeout);
      request.followRedirects = false;
      request.headers.contentType = ContentType.json;
      request.headers.set('x-goog-api-key', apiKey);
      request.add(payload);
      final response = await request.close().timeout(requestTimeout);
      if (response.statusCode != HttpStatus.ok) {
        // Cancel without draining an unbounded body, including caller-owned clients.
        await response.listen((_) {}).cancel();
        // Never decode or propagate a provider's error body.
        throw GeminiProbeException(
          GeminiProbeFailure.http,
          statusCode: response.statusCode,
        );
      }
      final bytes = <int>[];
      await for (final chunk in response.timeout(requestTimeout)) {
        if (bytes.length + chunk.length > _maxResponseBytes) {
          throw const GeminiProbeException(GeminiProbeFailure.invalidResponse);
        }
        bytes.addAll(chunk);
      }
      return _parseResponse(jsonDecode(utf8.decode(bytes)));
    } on GeminiProbeException {
      rethrow;
    } on FormatException {
      throw const GeminiProbeException(GeminiProbeFailure.invalidResponse);
    } on TimeoutException {
      throw const GeminiProbeException(GeminiProbeFailure.timeout);
    } catch (_) {
      // Transport exceptions can contain URLs or server-supplied information.
      throw const GeminiProbeException(GeminiProbeFailure.transport);
    } finally {
      if (client == null) transport.close(force: true);
    }
  }

  static Never _invalid() =>
      throw const GeminiProbeException(GeminiProbeFailure.invalidResponse);

  static Transcript _parseResponse(Object? response) {
    if (response is! Map) _invalid();
    final candidates = response['candidates'];
    if (candidates is! List || candidates.length != 1) _invalid();
    final candidate = candidates.single;
    if (candidate is! Map || candidate['finishReason'] != 'STOP') _invalid();
    final content = candidate['content'];
    if (content is! Map || content['parts'] is! List) _invalid();
    final text = StringBuffer();
    for (final part in content['parts'] as List) {
      if (part is! Map) _invalid();
      if (part['thought'] == true) continue;
      if (part['text'] is! String) _invalid();
      text.write(part['text']);
    }
    final decoded = jsonDecode(text.toString());
    if (decoded is! Map<String, dynamic> ||
        decoded['lang'] is! String ||
        (decoded['lang'] as String).trim().isEmpty ||
        decoded['segments'] is! List) {
      _invalid();
    }
    var previousEnd = 0;
    for (final segment in decoded['segments'] as List) {
      if (segment is! Map || segment['w'] is! List) _invalid();
      final (start, end) = _interval(segment, previousEnd);
      var previousWordEnd = start;
      for (final word in segment['w'] as List) {
        if (word is! Map ||
            word['t'] is! String ||
            (word['t'] as String).trim().isEmpty) {
          _invalid();
        }
        final (_, wordEnd) = _interval(word, previousWordEnd);
        if (wordEnd > end) _invalid();
        previousWordEnd = wordEnd;
      }
      previousEnd = end;
    }
    return Transcript.fromJson(decoded);
  }

  static (int, int) _interval(Map value, int earliest) {
    final start = value['s'];
    final end = value['e'];
    if (start is! int || end is! int || start < earliest || end < start) {
      _invalid();
    }
    return (start, end);
  }

  static const _time = {'type': 'INTEGER', 'minimum': 0};
  static const _schema = {
    'type': 'OBJECT',
    'required': ['lang', 'segments'],
    'properties': {
      'lang': {'type': 'STRING'},
      'segments': {
        'type': 'ARRAY',
        'items': {
          'type': 'OBJECT',
          'required': ['s', 'e', 'w'],
          'properties': {
            's': _time,
            'e': _time,
            'w': {
              'type': 'ARRAY',
              'items': {
                'type': 'OBJECT',
                'required': ['t', 's', 'e'],
                'properties': {
                  't': {'type': 'STRING'},
                  's': _time,
                  'e': _time,
                },
              },
            },
          },
        },
      },
    },
  };
}
