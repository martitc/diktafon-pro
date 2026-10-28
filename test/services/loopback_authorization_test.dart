import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:diktafon/services/providers/chatgpt/loopback_authorization.dart';

void main() {
  Future<int> callback(
    LoopbackAuthorization attempt,
    Map<String, String> values, {
    String? path,
    String method = 'GET',
  }) async {
    final client = HttpClient();
    try {
      final request = await client.openUrl(
        method,
        attempt.redirectUri.replace(path: path, queryParameters: values),
      );
      final response = await request.close();
      await response.drain<void>();
      return response.statusCode;
    } finally {
      client.close(force: true);
    }
  }

  test(
    'initial URI uses official flow and independent random PKCE values',
    () async {
      final attempt = await LoopbackAuthorization.start();
      final second = await LoopbackAuthorization.start();
      addTearDown(attempt.dispose);
      addTearDown(second.dispose);
      final parameters = attempt
          .authorizationUri(hostId: 'persistent-host')
          .queryParameters;
      expect(attempt.redirectUri.host, '127.0.0.1');
      expect(attempt.redirectUri.port, greaterThan(0));
      expect(attempt.redirectUri.path, '/auth/callback');
      for (final value in [
        attempt.state,
        attempt.nonce,
        attempt.codeVerifier,
      ]) {
        expect(
          base64Url.decode(base64Url.normalize(value)).length,
          greaterThanOrEqualTo(32),
        );
      }
      expect({attempt.state, attempt.nonce, attempt.codeVerifier}.length, 3);
      expect(second.state, isNot(attempt.state));
      expect(
        attempt.codeChallenge,
        base64Url
            .encode(sha256.convert(ascii.encode(attempt.codeVerifier)).bytes)
            .replaceAll('=', ''),
      );
      final uri = attempt.authorizationUri(hostId: 'persistent-host');
      expect(
        '${uri.scheme}://${uri.host}${uri.path}',
        'https://auth.openai.com/api/accounts/authorize',
      );
      expect(parameters['client_id'], 'dynamic_agent_client');
      expect(parameters['agent_name_hint'], 'Diktafon Pro');
      expect(parameters['ext_agent_host_id'], 'persistent-host');
      expect(parameters['nonce'], attempt.nonce);
      expect(parameters['state'], attempt.state);
      expect(parameters['redirect_uri'], attempt.redirectUri.toString());
      expect(parameters['code_challenge_method'], 'S256');
      expect(parameters['code_challenge'], attempt.codeChallenge);
      expect(parameters['response_type'], 'code');
      expect(parameters['resource'], 'https://api.openai.com/v1');
      expect(
        parameters['scope'],
        'openid profile email offline_access resource.invoke chatgpt.tokens.use.direct',
      );
    },
  );

  test('valid initial callback returns issued code and client id', () async {
    final attempt = await LoopbackAuthorization.start();
    addTearDown(attempt.dispose);
    expect(
      await callback(attempt, {
        'state': attempt.state,
        'code': 'fake-code',
        'client_id': 'issued-client',
      }),
      200,
    );
    final result = await attempt.result;
    expect(result.code, 'fake-code');
    expect(result.clientId, 'issued-client');
  });

  test(
    'invalid state and unexpected route or method do not consume attempt',
    () async {
      final attempt = await LoopbackAuthorization.start();
      addTearDown(attempt.dispose);
      expect(
        await callback(attempt, {
          'state': 'invalid',
          'code': 'fake',
          'client_id': 'client',
        }),
        400,
      );
      expect(await callback(attempt, {}, path: '/favicon.ico'), 404);
      expect(await callback(attempt, {}, method: 'POST'), 405);
      expect(
        await callback(attempt, {
          'state': attempt.state,
          'code': 'fake',
          'client_id': 'client',
        }),
        200,
      );
      expect((await attempt.result).clientId, 'client');
      await attempt.dispose();
      await expectLater(callback(attempt, {}), throwsA(isA<SocketException>()));
    },
  );

  for (final clientId in [null, '', 'dynamic_agent_client']) {
    test('initial callback rejects unissued client id $clientId', () async {
      final attempt = await LoopbackAuthorization.start();
      addTearDown(attempt.dispose);
      final failure = expectLater(
        attempt.result,
        throwsA(isA<LoopbackAuthorizationException>()),
      );
      expect(
        await callback(attempt, {
          'state': attempt.state,
          'code': 'fake',
          'client_id': ?clientId,
        }),
        400,
      );
      await failure;
    });
  }

  test(
    'existing account accepts absent or matching client id and omits registration hint',
    () async {
      for (final returned in [null, 'existing-client']) {
        final attempt = await LoopbackAuthorization.start(
          clientId: 'existing-client',
        );
        addTearDown(attempt.dispose);
        final params = attempt.authorizationUri(hostId: 'host').queryParameters;
        expect(params['client_id'], 'existing-client');
        expect(params.containsKey('agent_name_hint'), false);
        expect(
          await callback(attempt, {
            'state': attempt.state,
            'code': 'fake',
            'client_id': ?returned,
          }),
          200,
        );
        expect((await attempt.result).clientId, 'existing-client');
      }
    },
  );

  test(
    'existing callback rejects mismatched client id without exposing it',
    () async {
      final attempt = await LoopbackAuthorization.start(
        clientId: 'existing-client',
      );
      addTearDown(attempt.dispose);
      final failure = expectLater(
        attempt.result,
        throwsA(
          isA<LoopbackAuthorizationException>().having(
            (e) => e.toString(),
            'safe error',
            isNot(contains('secret')),
          ),
        ),
      );
      expect(
        await callback(attempt, {
          'state': attempt.state,
          'code': 'secret-code',
          'client_id': 'secret-client',
        }),
        400,
      );
      await failure;
    },
  );

  test('access_denied with valid state completes safely', () async {
    final attempt = await LoopbackAuthorization.start();
    addTearDown(attempt.dispose);
    final failure = expectLater(
      attempt.result,
      throwsA(
        isA<LoopbackAuthorizationException>().having(
          (e) => e.toString(),
          'safe error',
          isNot(contains('secret')),
        ),
      ),
    );
    expect(
      await callback(attempt, {
        'state': attempt.state,
        'error': 'access_denied',
        'error_description': 'secret',
      }),
      400,
    );
    await failure;
  });

  test(
    'OAuth error with invalid state cannot cancel a pending attempt',
    () async {
      final attempt = await LoopbackAuthorization.start();
      addTearDown(attempt.dispose);
      expect(
        await callback(attempt, {'state': 'wrong', 'error': 'access_denied'}),
        400,
      );
      expect(
        await callback(attempt, {
          'state': attempt.state,
          'code': 'fake',
          'client_id': 'client',
        }),
        200,
      );
      expect((await attempt.result).code, 'fake');
    },
  );

  test('invalid initial configuration is rejected', () async {
    for (final id in ['', 'dynamic_agent_client']) {
      await expectLater(
        LoopbackAuthorization.start(clientId: id),
        throwsArgumentError,
      );
    }
    await expectLater(
      LoopbackAuthorization.start(timeout: Duration.zero),
      throwsArgumentError,
    );
    final attempt = await LoopbackAuthorization.start();
    addTearDown(attempt.dispose);
    expect(() => attempt.authorizationUri(hostId: ''), throwsArgumentError);
  });

  test('missing code fails and closes listener', () async {
    final attempt = await LoopbackAuthorization.start();
    final failure = expectLater(
      attempt.result,
      throwsA(isA<LoopbackAuthorizationException>()),
    );
    expect(
      await callback(attempt, {'state': attempt.state, 'client_id': 'client'}),
      400,
    );
    await failure;
    await attempt.dispose();
    await expectLater(callback(attempt, {}), throwsA(isA<SocketException>()));
  });

  test('timeout closes listener and completes result', () async {
    final attempt = await LoopbackAuthorization.start(
      timeout: const Duration(milliseconds: 30),
    );
    await expectLater(attempt.result, throwsA(isA<TimeoutException>()));
    await attempt.dispose();
    await expectLater(callback(attempt, {}), throwsA(isA<SocketException>()));
  });

  test('dispose is idempotent, closes listener and completes result', () async {
    final attempt = await LoopbackAuthorization.start();
    final failure = expectLater(
      attempt.result,
      throwsA(isA<LoopbackAuthorizationException>()),
    );
    await attempt.dispose();
    await attempt.dispose();
    await failure;
    await expectLater(callback(attempt, {}), throwsA(isA<SocketException>()));
  });
}
