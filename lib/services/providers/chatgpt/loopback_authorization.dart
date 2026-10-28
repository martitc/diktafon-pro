import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';

/// Transient callback data; never log or persist an authorization code.
class AuthorizationCode {
  const AuthorizationCode({required this.code, required this.clientId});

  final String code;
  final String clientId;
}

/// A safe, fixed diagnostic message without data supplied by the browser.
class LoopbackAuthorizationException implements Exception {
  const LoopbackAuthorizationException(this.message);

  final String message;

  @override
  String toString() => 'LoopbackAuthorizationException: $message';
}

/// One local OAuth attempt. The caller must persist and reuse its host ID.
/// This class neither opens a browser nor exchanges or stores credentials.
class LoopbackAuthorization {
  LoopbackAuthorization._(this._server, this._clientId)
    : _port = _server.port,
      state = _randomValue(),
      nonce = _randomValue(),
      codeVerifier = _randomValue();

  final HttpServer _server;
  final int _port;
  final String? _clientId;
  final Completer<AuthorizationCode> _result = Completer<AuthorizationCode>();
  Timer? _timer;
  bool _settled = false;
  Future<void>? _closing;

  final String state;
  final String nonce;
  final String codeVerifier;

  Uri get redirectUri => Uri(
    scheme: 'http',
    host: '127.0.0.1',
    port: _port,
    path: '/auth/callback',
  );

  String get codeChallenge => base64Url
      .encode(sha256.convert(ascii.encode(codeVerifier)).bytes)
      .replaceAll('=', '');

  Future<AuthorizationCode> get result => _result.future;

  static Future<LoopbackAuthorization> start({
    String? clientId,
    Duration timeout = const Duration(minutes: 3),
  }) async {
    if (clientId != null &&
        (clientId.trim().isEmpty || clientId == 'dynamic_agent_client')) {
      throw ArgumentError('An issued client ID is required.');
    }
    if (timeout <= Duration.zero) {
      throw ArgumentError('The timeout must be positive.');
    }
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final attempt = LoopbackAuthorization._(server, clientId);
    // Disposing before a caller awaits result must not create an unhandled error.
    unawaited(attempt.result.then<void>((_) {}, onError: (Object _) {}));
    server.listen(
      attempt._handle,
      onError: (Object _) {
        unawaited(
          attempt._finish(
            error: const LoopbackAuthorizationException(
              'Callback listener failed.',
            ),
          ),
        );
      },
    );
    attempt._timer = Timer(timeout, () {
      unawaited(
        attempt._finish(error: TimeoutException('Authorization timed out.')),
      );
    });
    return attempt;
  }

  Uri authorizationUri({
    required String hostId,
    String agentName = 'Diktafon Pro',
  }) {
    if (hostId.trim().isEmpty || agentName.trim().isEmpty) {
      throw ArgumentError('A host ID and application name are required.');
    }
    return Uri.https('auth.openai.com', '/api/accounts/authorize', {
      'client_id': _clientId ?? 'dynamic_agent_client',
      if (_clientId == null) 'agent_name_hint': agentName,
      'ext_agent_host_id': hostId,
      'response_type': 'code',
      'redirect_uri': redirectUri.toString(),
      'scope':
          'openid profile email offline_access resource.invoke chatgpt.tokens.use.direct',
      'resource': 'https://api.openai.com/v1',
      'state': state,
      'nonce': nonce,
      'code_challenge_method': 'S256',
      'code_challenge': codeChallenge,
    });
  }

  void _handle(HttpRequest request) {
    if (_settled) {
      unawaited(_respond(request, HttpStatus.gone));
      return;
    }
    if (request.uri.path != '/auth/callback') {
      unawaited(_respond(request, HttpStatus.notFound));
      return;
    }
    if (request.method != 'GET') {
      unawaited(_respond(request, HttpStatus.methodNotAllowed));
      return;
    }
    final parameters = request.uri.queryParametersAll;
    String? single(String key) {
      final values = parameters[key];
      return values != null && values.length == 1 ? values.single : null;
    }

    if (single('state') != state) {
      unawaited(_respond(request, HttpStatus.badRequest));
      return;
    }
    Object? error;
    AuthorizationCode? authorization;
    final returnedClientId = single('client_id');
    final code = single('code');
    if (parameters.containsKey('error')) {
      error = const LoopbackAuthorizationException(
        'Authorization was not granted.',
      );
    } else if (code == null || code.trim().isEmpty) {
      error = const LoopbackAuthorizationException(
        'Authorization code is missing.',
      );
    } else if (_clientId == null &&
        (returnedClientId == null ||
            returnedClientId.trim().isEmpty ||
            returnedClientId == 'dynamic_agent_client')) {
      error = const LoopbackAuthorizationException(
        'Registration is incomplete.',
      );
    } else if (_clientId != null &&
        parameters.containsKey('client_id') &&
        returnedClientId != _clientId) {
      error = const LoopbackAuthorizationException(
        'Registration does not match.',
      );
    } else {
      authorization = AuthorizationCode(
        code: code,
        clientId: _clientId ?? returnedClientId!,
      );
    }
    unawaited(
      _finish(authorization: authorization, error: error, request: request),
    );
  }

  Future<void> _respond(HttpRequest request, int status) async {
    try {
      request.response
        ..statusCode = status
        ..headers.contentType = ContentType.text
        ..headers.set(HttpHeaders.cacheControlHeader, 'no-store')
        ..headers.set('Referrer-Policy', 'no-referrer')
        ..write(
          status == HttpStatus.ok
              ? 'Return received. You can return to Diktafon Pro.'
              : 'Return could not be accepted.',
        );
      await request.response.close();
    } catch (_) {
      // Browser disconnects must not leak request contents or strand the attempt.
    }
  }

  Future<void> _finish({
    AuthorizationCode? authorization,
    Object? error,
    HttpRequest? request,
  }) {
    if (_settled) return _closing ?? Future<void>.value();
    _settled = true;
    _timer?.cancel();
    return _closing = () async {
      try {
        if (request != null) {
          await _respond(
            request,
            error == null ? HttpStatus.ok : HttpStatus.badRequest,
          );
        }
      } finally {
        await _server.close(force: true);
        if (error != null) {
          _result.completeError(error);
        } else {
          _result.complete(authorization!);
        }
      }
    }();
  }

  Future<void> dispose() => _finish(
    error: const LoopbackAuthorizationException('Authorization cancelled.'),
  );

  static String _randomValue() {
    final random = Random.secure();
    return base64Url
        .encode(List<int>.generate(32, (_) => random.nextInt(256)))
        .replaceAll('=', '');
  }
}
