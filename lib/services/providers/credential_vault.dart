import 'dart:convert';
import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'chatgpt/chatgpt_connection_probe.dart';

/// Device protected storage for cloud credentials. Secrets never enter Drift,
/// job records, logs, or model preferences.
class CredentialVault {
  CredentialVault({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;
  static const _geminiKey = 'gemini_api_key';
  static const _chatGptTokens = 'chatgpt_oauth_tokens_v1';
  static const _hostId = 'chatgpt_oauth_host_id_v1';

  Future<String?> readGeminiKey() => _storage.read(key: _geminiKey);
  Future<void> writeGeminiKey(String value) =>
      _storage.write(key: _geminiKey, value: value.trim());
  Future<void> deleteGeminiKey() => _storage.delete(key: _geminiKey);

  Future<ProbeTokenSet?> readChatGptTokens() async {
    final raw = await _storage.read(key: _chatGptTokens);
    if (raw == null) return null;
    try {
      final data = jsonDecode(raw) as Map<String, dynamic>;
      return ProbeTokenSet(
        accessToken: data['accessToken'] as String,
        refreshToken: data['refreshToken'] as String,
        idToken: data['idToken'] as String,
        clientId: data['clientId'] as String,
        subject: data['subject'] as String,
        scope: data['scope'] as String,
        expiresAt: DateTime.parse(data['expiresAt'] as String),
      );
    } catch (_) {
      await _storage.delete(key: _chatGptTokens);
      return null;
    }
  }

  Future<void> writeChatGptTokens(ProbeTokenSet tokens) => _storage.write(
    key: _chatGptTokens,
    value: jsonEncode({
      'accessToken': tokens.accessToken,
      'refreshToken': tokens.refreshToken,
      'idToken': tokens.idToken,
      'clientId': tokens.clientId,
      'subject': tokens.subject,
      'scope': tokens.scope,
      'expiresAt': tokens.expiresAt.toUtc().toIso8601String(),
    }),
  );

  Future<void> deleteChatGptTokens() => _storage.delete(key: _chatGptTokens);

  Future<String> getOrCreateChatGptHostId() async {
    final saved = await _storage.read(key: _hostId);
    if (saved != null && saved.length >= 24) return saved;
    final random = Random.secure();
    final bytes = List<int>.generate(32, (_) => random.nextInt(256));
    // Host ID is a stable opaque identifier, not an authentication secret.
    final value = base64Url.encode(bytes).replaceAll('=', '');
    await _storage.write(key: _hostId, value: value);
    return value;
  }
}
