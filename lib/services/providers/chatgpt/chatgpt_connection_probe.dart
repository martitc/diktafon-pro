import 'dart:io';
import 'dart:convert';
import 'package:jose/jose.dart';

class ProbeTokenSet {
  const ProbeTokenSet({
    required this.accessToken,
    required this.refreshToken,
    required this.idToken,
    required this.clientId,
    required this.subject,
    required this.scope,
    required this.expiresAt,
  });
  final String accessToken, refreshToken, idToken, clientId, subject, scope;
  final DateTime expiresAt;
}

class ProbeModel {
  const ProbeModel(this.slug, this.displayName);
  final String slug, displayName;
}

class ProbeException implements Exception {
  const ProbeException(this.code, {this.remoteCleanupUnconfirmed = false});
  final String code;
  final bool remoteCleanupUnconfirmed;
  @override
  String toString() => 'ChatGPT probe: $code';
}

/// Disposable feasibility client. Credentials stay in memory; no persistence.
class ChatGptConnectionProbe {
  ChatGptConnectionProbe({
    HttpClient? client,
    Uri? authBase,
    Uri? apiBase,
    DateTime Function()? now,
  }) : _client = client ?? HttpClient(),
       _auth = authBase ?? Uri.parse('https://auth.openai.com'),
       _api = apiBase ?? Uri.parse('https://api.openai.com/v1'),
       _now = now ?? DateTime.now {
    _checkBase(_auth, 'auth.openai.com');
    _checkBase(_api, 'api.openai.com');
  }
  final HttpClient _client;
  final Uri _auth, _api;
  final DateTime Function() _now;
  static const _issuer = 'https://auth.openai.com';
  static const _resource = 'https://api.openai.com/v1';
  static const _permission = 'chatgpt.tokens.use.direct';
  static bool _loopback(Uri uri) =>
      uri.scheme == 'http' && uri.host == '127.0.0.1';
  static void _checkBase(Uri uri, String host) {
    if ((!_loopback(uri) &&
            !(uri.scheme == 'https' && uri.host == host && uri.port == 443)) ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment) {
      throw const ProbeException('untrustedEndpoint');
    }
  }

  Uri _trustedEndpoint(String value) {
    final uri = Uri.parse(value);
    if (uri.scheme != _auth.scheme ||
        uri.host != _auth.host ||
        uri.port != _auth.port ||
        uri.userInfo.isNotEmpty ||
        uri.hasFragment ||
        uri.hasQuery) {
      throw const ProbeException('untrustedEndpoint');
    }
    return uri;
  }

  Future<T> _safe<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on ProbeException {
      rethrow;
    } catch (_) {
      throw const ProbeException('invalidResponseOrNetwork');
    }
  }

  Future<String> _request(
    Uri uri, {
    Map<String, String>? form,
    String? bearer,
  }) async {
    final request = await _client
        .openUrl(form == null ? 'GET' : 'POST', uri)
        .timeout(const Duration(seconds: 20));
    request.followRedirects = false;
    if (form != null) {
      request.headers.contentType = ContentType(
        'application',
        'x-www-form-urlencoded',
        charset: 'utf-8',
      );
      request.write(Uri(queryParameters: form).query);
    }
    if (bearer != null) {
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $bearer');
    }
    final response = await request.close().timeout(const Duration(seconds: 20));
    if (response.statusCode != 200) {
      // No error payload is needed. Abort rather than draining an unbounded
      // response, which can otherwise keep a rejected request alive forever.
      final socket = await response.detachSocket();
      socket.destroy();
      throw const ProbeException('httpFailure');
    }
    return utf8.decoder
        .bind(response)
        .join()
        .timeout(const Duration(seconds: 20));
  }

  Future<Map<String, dynamic>> _json(
    Uri uri, {
    Map<String, String>? form,
    String? bearer,
  }) async =>
      jsonDecode(await _request(uri, form: form, bearer: bearer))
          as Map<String, dynamic>;
  Future<Map<String, dynamic>> _metadata() async {
    final metadata = await _json(
      _auth.resolve('/.well-known/openid-configuration'),
    );
    if (metadata['issuer'] != _issuer) {
      throw const ProbeException('invalidIssuer');
    }
    return metadata;
  }

  Future<Map<String, dynamic>> _identity(
    String idToken,
    String clientId, {
    String? nonce,
    String? subject,
  }) async {
    final segments = idToken.split('.');
    if (segments.length != 3) throw const ProbeException('invalidIdentity');
    final header =
        jsonDecode(
              utf8.decode(
                base64Url.decode(base64Url.normalize(segments.first)),
              ),
            )
            as Map<String, dynamic>;
    if (header['alg'] != 'RS256') {
      throw const ProbeException('invalidSignature');
    }
    final metadata = await _metadata();
    final jwks = await _json(_trustedEndpoint(metadata['jwks_uri'] as String));
    final store = JsonWebKeyStore();
    for (final raw in jwks['keys'] as List) {
      final key = raw as Map<String, dynamic>;
      if (key['kty'] == 'RSA' &&
          (key['alg'] == null || key['alg'] == 'RS256') &&
          (key['use'] == null || key['use'] == 'sig')) {
        store.addKey(JsonWebKey.fromJson(key));
      }
    }
    final jwt = JsonWebToken.unverified(idToken);
    if (!await jwt.verify(store, allowedArguments: ['RS256'])) {
      throw const ProbeException('invalidSignature');
    }
    final claims = jwt.claims.toJson();
    final audience = claims['aud'];
    final audienceMatches =
        audience == clientId ||
        (audience is List &&
            audience.contains(clientId) &&
            (audience.length == 1 || claims['azp'] == clientId));
    final exp = claims['exp'];
    if (claims['iss'] != _issuer ||
        !audienceMatches ||
        exp is! num ||
        !exp.isFinite ||
        exp <= _now().millisecondsSinceEpoch / 1000 ||
        claims['sub'] is! String ||
        (claims['sub'] as String).isEmpty ||
        (nonce != null && claims['nonce'] != nonce) ||
        (subject != null && claims['sub'] != subject)) {
      throw const ProbeException('invalidIdentity');
    }
    return claims;
  }

  String _required(Map<String, dynamic> data, String key) {
    final value = data[key];
    if (value is! String || value.isEmpty) {
      throw const ProbeException('invalidTokenResponse');
    }
    return value;
  }

  Future<ProbeTokenSet> _tokens(
    Map<String, dynamic> data,
    String clientId, {
    String? nonce,
    ProbeTokenSet? previous,
  }) async {
    final scope = data['scope'] ?? previous?.scope;
    if (scope is! String ||
        !scope.split(RegExp(r'\s+')).contains(_permission)) {
      throw const ProbeException('planPermissionMissing');
    }
    if ((data['token_type'] as String?)?.toLowerCase() != 'bearer') {
      throw const ProbeException('invalidTokenResponse');
    }
    final idToken = data['id_token'] as String? ?? previous?.idToken;
    if (idToken == null) throw const ProbeException('invalidIdentity');
    final identity = data['id_token'] != null || previous == null
        ? await _identity(
            idToken,
            clientId,
            nonce: nonce,
            subject: previous?.subject,
          )
        : null;
    final lifetime = data['expires_in'];
    if (lifetime is! int || lifetime <= 0) {
      throw const ProbeException('invalidTokenResponse');
    }
    return ProbeTokenSet(
      accessToken: _required(data, 'access_token'),
      refreshToken: data['refresh_token'] == null && previous != null
          ? previous.refreshToken
          : _required(data, 'refresh_token'),
      idToken: idToken,
      clientId: clientId,
      subject: identity?['sub'] as String? ?? previous!.subject,
      scope: scope,
      expiresAt: _now().add(Duration(seconds: lifetime)),
    );
  }

  Future<ProbeTokenSet> _validateCandidate(
    Map<String, dynamic> data,
    String clientId, {
    String? nonce,
    ProbeTokenSet? previous,
  }) async {
    try {
      return await _tokens(data, clientId, nonce: nonce, previous: previous);
    } catch (error) {
      final original = error is ProbeException
          ? error
          : const ProbeException('invalidResponseOrNetwork');
      var cleanupUnconfirmed = original.remoteCleanupUnconfirmed;
      final candidate = data['refresh_token'];
      if (candidate is String && candidate.isNotEmpty) {
        try {
          // The candidate has never become an active session. Revoke its raw
          // renewable token using only the trusted discovery endpoint.
          await _revokeRefreshToken(candidate, clientId);
        } catch (_) {
          cleanupUnconfirmed = true;
        }
      }
      throw ProbeException(
        original.code,
        remoteCleanupUnconfirmed: cleanupUnconfirmed,
      );
    }
  }

  Future<ProbeTokenSet> exchangeCode({
    required String code,
    required String clientId,
    required String codeVerifier,
    required Uri redirectUri,
    required String nonce,
  }) => _safe(() async {
    if (clientId.isEmpty ||
        clientId == 'dynamic_agent_client' ||
        code.isEmpty ||
        codeVerifier.isEmpty ||
        nonce.isEmpty) {
      throw const ProbeException('invalidAuthorization');
    }
    final data = await _json(
      _auth.resolve('/api/accounts/oauth/token'),
      form: {
        'grant_type': 'authorization_code',
        'code': code,
        'client_id': clientId,
        'code_verifier': codeVerifier,
        'redirect_uri': redirectUri.toString(),
        'resource': _resource,
      },
    );
    return _validateCandidate(data, clientId, nonce: nonce);
  });
  Future<List<ProbeModel>> listModels(ProbeTokenSet tokens) => _safe(() async {
    if (!tokens.scope.split(RegExp(r'\s+')).contains(_permission) ||
        !tokens.expiresAt.isAfter(_now())) {
      throw const ProbeException('inactiveSession');
    }
    final data = await _json(
      Uri.parse('${_api.toString().replaceFirst(RegExp(r'/$'), '')}/models'),
      bearer: tokens.accessToken,
    );
    return (data['models'] as List)
        .cast<Map<String, dynamic>>()
        .where((m) => m['visibility'] == 'list')
        .map(
          (m) => ProbeModel(_required(m, 'slug'), _required(m, 'display_name')),
        )
        .toList(growable: false);
  });
  Future<ProbeTokenSet> refresh(ProbeTokenSet tokens) => _safe(() async {
    final data = await _json(
      _auth.resolve('/api/accounts/oauth/token'),
      form: {
        'grant_type': 'refresh_token',
        'client_id': tokens.clientId,
        'refresh_token': tokens.refreshToken,
        'resource': _resource,
      },
    );
    return _validateCandidate(data, tokens.clientId, previous: tokens);
  });
  Future<void> _revokeRefreshToken(String refreshToken, String clientId) async {
    final metadata = await _metadata();
    await _request(
      _trustedEndpoint(metadata['revocation_endpoint'] as String),
      form: {
        'token': refreshToken,
        'token_type_hint': 'refresh_token',
        'client_id': clientId,
      },
    );
  }

  Future<void> revoke(ProbeTokenSet tokens) =>
      _safe(() => _revokeRefreshToken(tokens.refreshToken, tokens.clientId));

  /// Close only after the caller has attempted revocation.
  void close() => _client.close(force: true);
}
