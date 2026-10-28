import 'dart:convert';
import 'dart:io';

import '../../../domain/models.dart';
import '../../../domain/processing_progress.dart';
import '../../audio/recorder_service.dart' show probeAudioDurationMs;
import '../credential_vault.dart';
import '../transcription_provider.dart';
import 'gemini_connection_probe.dart';
import 'gemini_model_catalog.dart';

/// Gemini transcription adapter. Gemini is only selected explicitly in
/// Settings; errors are surfaced to the job queue without changing providers.
class GeminiTranscriptionProvider implements TranscriptionProvider {
  GeminiTranscriptionProvider({
    required this._vault,
    required this.modelId,
    HttpClient Function()? httpClientFactory,
  }) : _httpClientFactory = httpClientFactory ?? HttpClient.new;

  final CredentialVault _vault;
  final String modelId;
  final HttpClient Function() _httpClientFactory;

  @override
  String get id => 'gemini/$modelId';

  @override
  Future<ModelStatus> modelStatus() async =>
      await _vault.readGeminiKey() == null
      ? ModelStatus.notInstalled
      : ModelStatus.ready;

  @override
  Future<void> ensureModel({ProgressSink? onProgress}) async {
    if ((await _vault.readGeminiKey())?.trim().isNotEmpty != true) {
      throw const GeminiProviderException('missingApiKey');
    }
  }

  @override
  Future<Transcript> transcribe(
    AudioRef audio, {
    String? languageCode,
    CancelToken? cancel,
    TranscriptionProgressSink? onProgress,
  }) async {
    cancel ??= CancelToken();
    if (cancel.isCancelled) throw const TranscriptionCancelled();
    final model = GeminiModelCatalog.byId(modelId);
    final key = await _vault.readGeminiKey();
    if (key == null || key.trim().isEmpty) {
      throw const GeminiProviderException('missingApiKey');
    }
    if (model.id == 'gemini-3.5-transcribe') {
      final duration = await probeAudioDurationMs(audio.filePath);
      if (duration != null &&
          duration > const Duration(minutes: 30).inMilliseconds) {
        throw const GeminiProviderException('wordTimestampDurationLimit');
      }
      return _transcribeDedicated(
        File(audio.filePath),
        key,
        languageCode,
        cancel,
        onProgress,
      );
    }
    final file = File(audio.filePath);
    final client = _httpClientFactory();
    cancel.addListener(() => client.close(force: true));
    String? remoteFile;
    try {
      remoteFile = await _upload(file, key, client, cancel, onProgress);
      if (cancel.isCancelled) throw const TranscriptionCancelled();
      onProgress?.call(ProcessingStage.processingCloud, null);
      final transcript = await GeminiConnectionProbe().transcribe(
        audioBytes: const [],
        audioFileUri: remoteFile,
        mimeType: _mime(file.path),
        apiKey: key,
        model: model.id,
        instructions: _instructions(languageCode),
      );
      if (transcript.isEmpty) {
        throw const GeminiProviderException('emptyTranscript');
      }
      onProgress?.call(ProcessingStage.finished, 1);
      return transcript;
    } catch (_) {
      if (cancel.isCancelled) throw const TranscriptionCancelled();
      rethrow;
    } finally {
      if (remoteFile != null) {
        final cleanup = _httpClientFactory();
        try {
          final request = await cleanup.deleteUrl(Uri.parse(remoteFile));
          request.followRedirects = false;
          request.headers.set('x-goog-api-key', key);
          await request.close().timeout(const Duration(seconds: 8));
        } catch (_) {}
        cleanup.close(force: true);
      }
      client.close(force: true);
    }
  }

  Future<Transcript> _transcribeDedicated(
    File file,
    String key,
    String? languageCode,
    CancelToken cancel,
    TranscriptionProgressSink? onProgress,
  ) async {
    final client = _httpClientFactory();
    cancel.addListener(() => client.close(force: true));
    String? remoteFile;
    try {
      final uri = await _upload(file, key, client, cancel, onProgress);
      remoteFile = uri;
      onProgress?.call(ProcessingStage.processingCloud, null);
      final response = await _jsonRequest(
        client,
        Uri.https('generativelanguage.googleapis.com', '/v1beta/interactions'),
        key,
        {
          'model': modelId,
          'input': [
            {'type': 'audio', 'uri': uri, 'mime_type': _mime(file.path)},
          ],
          'generation_config': {
            'transcription_config': {
              if (languageCode != null) 'language_codes': [languageCode],
              'mode': {
                'type': 'verbatim',
                'timestamp_granularities': ['word'],
              },
            },
          },
        },
        cancel,
      );
      if (response['status'] != 'completed') {
        throw const GeminiProviderException('incompleteResponse');
      }
      final transcript = _parseInteraction(response, languageCode);
      onProgress?.call(ProcessingStage.finished, 1);
      return transcript;
    } on GeminiProviderException {
      rethrow;
    } catch (_) {
      if (cancel.isCancelled) throw const TranscriptionCancelled();
      throw const GeminiProviderException('networkOrResponse');
    } finally {
      if (remoteFile != null) {
        final cleanup = _httpClientFactory();
        try {
          final request = await cleanup.deleteUrl(Uri.parse(remoteFile));
          request.followRedirects = false;
          request.headers.set('x-goog-api-key', key);
          await request.close().timeout(const Duration(seconds: 8));
        } catch (_) {}
        cleanup.close(force: true);
      }
      client.close(force: true);
    }
  }

  Future<String> _upload(
    File file,
    String key,
    HttpClient client,
    CancelToken cancel,
    TranscriptionProgressSink? onProgress,
  ) async {
    if (cancel.isCancelled) throw const TranscriptionCancelled();
    final length = await file.length();
    final mime = _mime(file.path);
    final start = await client.postUrl(
      Uri.https('generativelanguage.googleapis.com', '/upload/v1beta/files'),
    );
    start.followRedirects = false;
    start.headers
      ..set('x-goog-api-key', key)
      ..set('X-Goog-Upload-Protocol', 'resumable')
      ..set('X-Goog-Upload-Command', 'start')
      ..set('X-Goog-Upload-Header-Content-Length', '$length')
      ..set('X-Goog-Upload-Header-Content-Type', mime)
      ..contentType = ContentType.json;
    start.write(
      jsonEncode({
        'file': {'display_name': file.uri.pathSegments.last},
      }),
    );
    final started = await start.close().timeout(const Duration(seconds: 30));
    if (started.statusCode < 200 || started.statusCode >= 300) {
      await started.drain<void>();
      throw GeminiProviderException(
        'uploadRejected',
        statusCode: started.statusCode,
      );
    }
    final uploadUrl = started.headers.value('x-goog-upload-url');
    await started.drain<void>();
    if (uploadUrl == null) {
      throw const GeminiProviderException('uploadRejected');
    }
    final upload = await client.postUrl(Uri.parse(uploadUrl));
    upload.followRedirects = false;
    upload.headers
      ..set('x-goog-api-key', key)
      ..set('X-Goog-Upload-Offset', '0')
      ..set('X-Goog-Upload-Command', 'upload, finalize')
      ..contentType = ContentType(mime.split('/').first, mime.split('/').last);
    onProgress?.call(ProcessingStage.uploadingAudio, 0);
    var uploaded = 0;
    await upload.addStream(
      file.openRead().map((chunk) {
        uploaded += chunk.length;
        onProgress?.call(
          ProcessingStage.uploadingAudio,
          length == 0 ? 1 : uploaded / length,
        );
        return chunk;
      }),
    );
    final response = await upload.close().timeout(const Duration(minutes: 10));
    if (cancel.isCancelled) throw const TranscriptionCancelled();
    final data = await _readJson(response);
    final uri = ((data['file'] as Map?)?['uri'] as String?)?.trim();
    if (response.statusCode < 200 ||
        response.statusCode >= 300 ||
        uri == null) {
      throw GeminiProviderException(
        'uploadRejected',
        statusCode: response.statusCode,
      );
    }
    return uri;
  }

  Future<Map<String, dynamic>> _jsonRequest(
    HttpClient client,
    Uri uri,
    String key,
    Map<String, Object?> body,
    CancelToken cancel,
  ) async {
    if (cancel.isCancelled) throw const TranscriptionCancelled();
    final request = await client
        .postUrl(uri)
        .timeout(const Duration(seconds: 30));
    request.followRedirects = false;
    request.headers
      ..set('x-goog-api-key', key)
      ..contentType = ContentType.json;
    request.write(jsonEncode(body));
    final response = await request.close().timeout(const Duration(minutes: 15));
    final data = await _readJson(response);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw GeminiProviderException(
        'requestRejected',
        statusCode: response.statusCode,
      );
    }
    return data;
  }

  Future<Map<String, dynamic>> _readJson(HttpClientResponse response) async {
    final bytes = <int>[];
    await for (final chunk in response.timeout(const Duration(minutes: 15))) {
      if (bytes.length + chunk.length > 8 * 1024 * 1024) {
        throw const GeminiProviderException('invalidResponse');
      }
      bytes.addAll(chunk);
    }
    try {
      return jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
    } catch (_) {
      throw const GeminiProviderException('invalidResponse');
    }
  }

  Transcript _parseInteraction(
    Map<String, dynamic> response,
    String? requestedLanguage,
  ) {
    final words = <Map<String, Object>>[];
    final text = StringBuffer();
    final steps = response['steps'];
    if (steps is! List) throw const GeminiProviderException('invalidResponse');
    for (final step in steps.whereType<Map>()) {
      final contents = step['content'];
      if (contents is! List) continue;
      for (final content in contents.whereType<Map>()) {
        if (content['text'] is String) text.write('${content['text']} ');
        final annotations = content['annotations'];
        if (annotations is! List) continue;
        for (final annotation in annotations.whereType<Map>()) {
          if (annotation['type'] != 'word_info' ||
              annotation['text'] is! String ||
              annotation['start_offset'] is! String ||
              annotation['end_offset'] is! String) {
            continue;
          }
          final start = _offsetMs(annotation['start_offset'] as String);
          final end = _offsetMs(annotation['end_offset'] as String);
          if (end < start) {
            throw const GeminiProviderException('invalidResponse');
          }
          words.add({'t': annotation['text'], 's': start, 'e': end});
        }
      }
    }
    if (words.isEmpty) throw const GeminiProviderException('missingTimestamps');
    words.sort((a, b) => (a['s'] as int).compareTo(b['s'] as int));
    final segments = <Map<String, Object>>[];
    for (final word in words) {
      final start = word['s'] as int;
      final end = word['e'] as int;
      if (segments.isEmpty || start - (segments.last['e'] as int) > 1200) {
        segments.add({
          's': start,
          'e': end,
          'w': [word],
        });
      } else {
        segments.last['e'] = end;
        (segments.last['w'] as List).add(word);
      }
    }
    final plain = text.toString().trim();
    final language = _guessLanguageCode(
      response['language_code'] ?? response['detected_language'],
      requestedLanguage,
    );
    return Transcript.fromJson({
      'lang': language,
      'segments': segments,
      'text': plain,
    });
  }

  int _offsetMs(String value) {
    final match = RegExp(r'^(\d+(?:\.\d+)?)s$').firstMatch(value);
    if (match == null) throw const GeminiProviderException('invalidResponse');
    return (double.parse(match.group(1)!) * 1000).round();
  }

  String _guessLanguageCode(Object? returned, String? requested) {
    if (returned is String && returned.trim().isNotEmpty) return returned;
    return requested ?? 'und';
  }

  String _instructions(String? language) =>
      'Transcribe in ${language ?? 'the original language'}. Return word-level timestamps in milliseconds.';

  String _mime(String path) => switch (path.split('.').last.toLowerCase()) {
    'm4a' => 'audio/m4a',
    'mp3' => 'audio/mpeg',
    'wav' => 'audio/wav',
    'oga' || 'ogg' => 'audio/ogg',
    'aac' => 'audio/aac',
    'flac' => 'audio/flac',
    'opus' => 'audio/opus',
    'webm' => 'audio/webm',
    _ => 'audio/mpeg',
  };
}

class GeminiProviderException implements Exception {
  const GeminiProviderException(this.code, {this.statusCode});
  final String code;
  final int? statusCode;
  @override
  String toString() => 'GeminiProviderException($code)';
}
