import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:jose/jose.dart';
import 'package:diktafon/services/providers/chatgpt/chatgpt_connection_probe.dart';

void main() {
  late HttpServer server;
  late HttpClient client;
  late Uri base;
  late ChatGptConnectionProbe probe;
  late JsonWebKey key;
  final now = DateTime.utc(2026, 10, 27);
  late Map<String, dynamic> claims;
  late Map<String, dynamic> response;
  late List<Map<String, String>> forms;
  late int apiCalls;
  late bool badSignature;
  late bool badJwksHost;
  late bool redirectToken;
  late bool hmacToken;
  late bool includeLuna;
  late int revokeStatus;
  late String? endlessErrorPath;
  late int endlessErrorStatus;
  late Completer<void> errorConnectionClosed;
  late List<Socket> detachedSockets;
  String sign(Map<String, dynamic> payload, JsonWebKey signingKey) =>
      (JsonWebSignatureBuilder()
            ..jsonContent = payload
            ..addRecipient(signingKey, algorithm: 'RS256'))
          .build()
          .toCompactSerialization();
  setUpAll(() {
    key = JsonWebKey.generate('RS256', keyBitLength: 2048);
  });
  setUp(() async {
    forms = [];
    apiCalls = 0;
    badSignature = false;
    badJwksHost = false;
    redirectToken = false;
    hmacToken = false;
    includeLuna = true;
    revokeStatus = 200;
    endlessErrorPath = null;
    endlessErrorStatus = 401;
    errorConnectionClosed = Completer<void>();
    detachedSockets = [];
    claims = {
      'iss': 'https://auth.openai.com',
      'aud': 'oaiapp_test',
      'sub': 'subject',
      'nonce': 'nonce',
      'exp': now.millisecondsSinceEpoch ~/ 1000 + 3600,
    };
    response = {
      'access_token': 'access-secret',
      'refresh_token': 'refresh-secret',
      'scope': 'openid chatgpt.tokens.use.direct',
      'token_type': 'Bearer',
      'expires_in': 3600,
    };
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    base = Uri.parse('http://127.0.0.1:${server.port}');
    client = HttpClient();
    probe = ChatGptConnectionProbe(
      client: client,
      authBase: base,
      apiBase: base.resolve('/v1'),
      now: () => now,
    );
    server.listen((request) async {
      if (request.uri.path == endlessErrorPath) {
        await request.drain<void>();
        final socket = await request.response.detachSocket(writeHeaders: false);
        detachedSockets.add(socket);
        socket.write(
          'HTTP/1.1 $endlessErrorStatus Error\r\nTransfer-Encoding: chunked\r\n\r\n15\r\nincomplete-error-body\r\n',
        );
        socket.listen(
          (_) {},
          onDone: () {
            if (!errorConnectionClosed.isCompleted) {
              errorConnectionClosed.complete();
            }
            socket.destroy();
          },
          onError: (Object _) {
            if (!errorConnectionClosed.isCompleted) {
              errorConnectionClosed.complete();
            }
            socket.destroy();
          },
        );
        await socket.flush();
        return; // Deliberately never terminate the body.
      }
      Object? data;
      switch (request.uri.path) {
        case '/.well-known/openid-configuration':
          data = {
            'issuer': 'https://auth.openai.com',
            'jwks_uri': badJwksHost
                ? 'https://untrusted.invalid/keys'
                : base.resolve('/keys').toString(),
            'revocation_endpoint': base.resolve('/revoke').toString(),
          };
        case '/keys':
          final public = Map<String, dynamic>.from(key.toJson())
            ..removeWhere(
              (k, v) => ['d', 'p', 'q', 'dp', 'dq', 'qi'].contains(k),
            );
          data = {
            'keys': [public],
          };
        case '/api/accounts/oauth/token':
          forms.add(
            Uri.splitQueryString(await utf8.decoder.bind(request).join()),
          );
          if (redirectToken) {
            request.response.statusCode = 307;
            request.response.headers.set('location', base.resolve('/leak'));
            break;
          }
          data = {
            ...response,
            'id_token': sign(
              claims,
              badSignature
                  ? JsonWebKey.generate('RS256', keyBitLength: 2048)
                  : key,
            ),
          };
          if (hmacToken) {
            (data as Map)['id_token'] =
                (JsonWebSignatureBuilder()
                      ..jsonContent = claims
                      ..addRecipient(
                        JsonWebKey.generate('HS256'),
                        algorithm: 'HS256',
                      ))
                    .build()
                    .toCompactSerialization();
          }
          if (forms.last['grant_type'] == 'refresh_token' &&
              !response.containsKey('include_new_id')) {
            (data as Map).remove('id_token');
          }
        case '/v1/models':
          apiCalls++;
          expect(
            request.headers.value('authorization'),
            'Bearer access-secret',
          );
          data = {
            'models': [
              {'slug': 'sol', 'display_name': 'Sol', 'visibility': 'list'},
              {
                'slug': 'hidden',
                'display_name': 'Hidden',
                'visibility': 'hidden',
              },
              if (includeLuna)
                {'slug': 'luna', 'display_name': 'Luna', 'visibility': 'list'},
            ],
          };
        case '/revoke':
          forms.add(
            Uri.splitQueryString(await utf8.decoder.bind(request).join()),
          );
          request.response.statusCode = revokeStatus;
        default:
          request.response.statusCode = 500;
          data = {'error': 'access-secret refresh-secret'};
      }
      if (data != null) request.response.write(jsonEncode(data));
      await request.response.close();
    });
  });
  tearDown(() async {
    client.close(force: true);
    for (final socket in detachedSockets) {
      socket.destroy();
    }
    await server.close(force: true);
  });
  Future<ProbeTokenSet> exchange() => probe.exchangeCode(
    code: 'code',
    clientId: 'oaiapp_test',
    codeVerifier: 'verifier',
    redirectUri: Uri.parse('http://127.0.0.1:1455/auth/callback'),
    nonce: 'nonce',
  );
  test(
    'valid signature activates only scoped identity and lists visible models in order',
    () async {
      final tokens = await exchange();
      expect(tokens.subject, 'subject');
      expect(tokens.clientId, 'oaiapp_test');
      expect(tokens.expiresAt, now.add(const Duration(hours: 1)));
      expect(forms.single, {
        'grant_type': 'authorization_code',
        'code': 'code',
        'client_id': 'oaiapp_test',
        'code_verifier': 'verifier',
        'redirect_uri': 'http://127.0.0.1:1455/auth/callback',
        'resource': 'https://api.openai.com/v1',
      });
      expect((await probe.listModels(tokens)).map((m) => m.slug), [
        'sol',
        'luna',
      ]);
      expect(tokens.toString(), isNot(contains('secret')));
    },
  );
  test('does not invent Luna when absent from account catalog', () async {
    includeLuna = false;
    expect((await probe.listModels(await exchange())).map((m) => m.slug), [
      'sol',
    ]);
  });
  for (final mutation in [
    'signature',
    'nonce',
    'aud',
    'iss',
    'exp',
    'scope',
    'jwks',
    'redirect',
    'alg',
  ]) {
    test('rejects $mutation before any API request', () async {
      switch (mutation) {
        case 'signature':
          badSignature = true;
        case 'nonce':
          claims['nonce'] = 'wrong';
        case 'aud':
          claims['aud'] = 'other';
        case 'iss':
          claims['iss'] = 'https://attacker.invalid';
        case 'exp':
          claims['exp'] = now.millisecondsSinceEpoch ~/ 1000;
        case 'scope':
          response['scope'] = 'openid';
        case 'jwks':
          badJwksHost = true;
        case 'redirect':
          redirectToken = true;
        case 'alg':
          hmacToken = true;
      }
      await expectLater(exchange(), throwsA(isA<ProbeException>()));
      expect(apiCalls, 0);
    });
  }
  test(
    'refresh rotates tokens using issued client and preserves identity',
    () async {
      final tokens = await exchange();
      response['access_token'] = 'rotated-access';
      response['refresh_token'] = 'rotated-refresh';
      response.remove('scope');
      final refreshed = await probe.refresh(tokens);
      expect(refreshed.accessToken, 'rotated-access');
      expect(refreshed.refreshToken, 'rotated-refresh');
      expect(refreshed.subject, tokens.subject);
      expect(refreshed.idToken, tokens.idToken);
      expect(forms.last, {
        'grant_type': 'refresh_token',
        'client_id': 'oaiapp_test',
        'refresh_token': 'refresh-secret',
        'resource': 'https://api.openai.com/v1',
      });
    },
  );
  for (final operation in ['exchange', 'refresh', 'revoke']) {
    test(
      '$operation aborts error response with an unterminated body',
      () async {
        final tokens = await exchange();
        endlessErrorPath = operation == 'revoke'
            ? '/revoke'
            : '/api/accounts/oauth/token';
        endlessErrorStatus = operation == 'refresh' ? 307 : 401;
        final Future<Object?> pending = switch (operation) {
          'exchange' => exchange(),
          'refresh' => probe.refresh(tokens),
          _ => probe.revoke(tokens),
        };
        await expectLater(
          pending.timeout(const Duration(seconds: 1)),
          throwsA(isA<ProbeException>()),
        );
        await errorConnectionClosed.future.timeout(const Duration(seconds: 1));
      },
    );
  }
  for (final invalid in ['scope', 'identity']) {
    test(
      'exchange revokes rejected $invalid candidate without activating it',
      () async {
        if (invalid == 'scope') {
          response['scope'] = 'openid';
        } else {
          claims['nonce'] = 'incorrect';
        }
        try {
          await exchange();
          fail('candidate must be rejected');
        } on ProbeException catch (error) {
          expect(
            error.code,
            invalid == 'scope' ? 'planPermissionMissing' : 'invalidIdentity',
          );
          expect(error.remoteCleanupUnconfirmed, isFalse);
        }
        expect(forms.last, {
          'token': 'refresh-secret',
          'token_type_hint': 'refresh_token',
          'client_id': 'oaiapp_test',
        });
        expect(apiCalls, 0);
      },
    );
  }
  test(
    'refresh revokes rotated candidate whose identity is rejected',
    () async {
      final tokens = await exchange();
      response['include_new_id'] = true;
      response['refresh_token'] = 'rotated-candidate-secret';
      claims['sub'] = 'different-subject';
      await expectLater(probe.refresh(tokens), throwsA(isA<ProbeException>()));
      expect(forms.last, {
        'token': 'rotated-candidate-secret',
        'token_type_hint': 'refresh_token',
        'client_id': 'oaiapp_test',
      });
      expect(apiCalls, 0);
    },
  );
  test(
    'failed rejected-candidate cleanup flags manual revocation without leaking secrets',
    () async {
      response['scope'] = 'openid';
      revokeStatus = 500;
      try {
        await exchange();
        fail('candidate must be rejected');
      } on ProbeException catch (error) {
        expect(error.code, 'planPermissionMissing');
        expect(error.remoteCleanupUnconfirmed, isTrue);
        expect(error.toString(), isNot(contains('secret')));
      }
      expect(forms.last['token'], 'refresh-secret');
      expect(apiCalls, 0);
    },
  );
  test('refresh checks replacement identity', () async {
    final tokens = await exchange();
    response['include_new_id'] = true;
    claims['sub'] = 'someone-else';
    await expectLater(probe.refresh(tokens), throwsA(isA<ProbeException>()));
  });
  test('revocation sends refresh token and reports a safe failure', () async {
    final tokens = await exchange();
    await probe.revoke(tokens);
    expect(forms.last, {
      'token': 'refresh-secret',
      'token_type_hint': 'refresh_token',
      'client_id': 'oaiapp_test',
    });
    revokeStatus = 500;
    try {
      await probe.revoke(tokens);
      fail('expected rejection');
    } on ProbeException catch (e) {
      expect(e.toString(), isNot(contains('secret')));
    }
  });
}
