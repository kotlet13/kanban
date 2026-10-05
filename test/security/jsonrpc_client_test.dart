import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kanban/kanboard/jsonrpc_client.dart';

JsonRpcClient client(http.Client transport, {bool logs = false}) =>
    JsonRpcClient(
      endpoint: Uri.parse('https://example.test/kanboard/jsonrpc.php'),
      username: 'alice',
      password: 'private-secret',
      enableDebugLogs: logs,
      httpClient: transport,
    );
http.Response success(http.Request request) => http.Response(
  jsonEncode({
    'jsonrpc': '2.0',
    'id': jsonDecode(request.body)['id'],
    'result': true,
  }),
  200,
);

void main() {
  test(
    'manual relative redirect preserves same-origin request and disables automatic redirects',
    () async {
      final seen = <http.Request>[];
      final api = client(
        MockClient((request) async {
          seen.add(request);
          expect(request.followRedirects, isFalse);
          return seen.length == 1
              ? http.Response(
                  '',
                  307,
                  headers: {'location': '/api/jsonrpc.php'},
                )
              : success(request);
        }),
      );
      expect(await api.call('changeTask', {'secret': 'private-data'}), isTrue);
      expect(seen, hasLength(2));
      expect(seen.last.url, Uri.parse('https://example.test/api/jsonrpc.php'));
      expect(seen.last.body, seen.first.body);
      expect(
        seen.last.headers['Authorization'],
        seen.first.headers['Authorization'],
      );
      api.close();
    },
  );

  for (final location in [
    'https://evil.test/jsonrpc.php',
    'http://example.test/jsonrpc.php',
    'https://example.test:8443/jsonrpc.php',
    'https://other:secret@example.test/jsonrpc.php',
  ]) {
    test('rejects unsafe redirect $location before a second request', () async {
      var requests = 0;
      final api = client(
        MockClient((request) async {
          requests++;
          return http.Response('', 302, headers: {'location': location});
        }),
      );
      await expectLater(api.call('getMe'), throwsA(isA<JsonRpcException>()));
      expect(requests, 1);
      api.close();
    });
  }

  test('redirect limit stops loops', () async {
    var requests = 0;
    final api = client(
      MockClient((request) async {
        requests++;
        return http.Response('', 308, headers: {'location': '/jsonrpc.php'});
      }),
    );
    await expectLater(api.call('getMe'), throwsA(isA<JsonRpcException>()));
    expect(requests, 3);
    api.close();
  });

  test('HTTP is limited to explicit loopback development', () {
    for (final url in [
      'http://example.test/jsonrpc.php',
      'https://user:secret@example.test/jsonrpc.php',
      'https://example.test/jsonrpc.php#fragment',
    ]) {
      expect(
        () => JsonRpcClient.validateEndpoint(
          Uri.parse(url),
          allowLocalHttp: true,
        ),
        throwsA(isA<JsonRpcException>()),
      );
    }
    expect(
      () => JsonRpcClient.validateEndpoint(
        Uri.parse('http://127.0.0.1:18380/jsonrpc.php'),
      ),
      throwsA(isA<JsonRpcException>()),
    );
    JsonRpcClient.validateEndpoint(
      Uri.parse('http://127.0.0.1:18380/jsonrpc.php'),
      allowLocalHttp: true,
    );
    JsonRpcClient.validateEndpoint(
      Uri.parse('http://[::1]/jsonrpc.php'),
      allowLocalHttp: true,
    );
  });

  test('global jsonrpc credentials are rejected without sending', () {
    expect(
      () => JsonRpcClient(
        endpoint: Uri.parse('https://example.test/jsonrpc.php'),
        username: 'jsonrpc',
        password: 'global-secret',
      ),
      throwsA(isA<JsonRpcException>()),
    );
  });

  test(
    'debug logs contain no payload, server identity or response content',
    () async {
      final previous = debugPrint;
      final logs = <String>[];
      debugPrint = (message, {wrapWidth}) {
        if (message != null) logs.add(message);
      };
      try {
        final api = client(
          MockClient((request) async => success(request)),
          logs: true,
        );
        await api.call('private-method', {
          'password': 'private-secret',
          'financial': 'private-finance',
        });
        final text = logs.join('\n');
        for (final secret in [
          'private-method',
          'private-secret',
          'private-finance',
          'alice',
          'example.test',
        ]) {
          expect(text, isNot(contains(secret)));
        }
        api.close();
      } finally {
        debugPrint = previous;
      }
    },
  );

  test('wrong response identity is rejected', () async {
    final api = client(
      MockClient(
        (request) async =>
            http.Response('{"jsonrpc":"2.0","id":999,"result":true}', 200),
      ),
    );
    await expectLater(api.call('getMe'), throwsA(isA<JsonRpcException>()));
    api.close();
  });

  test('web credential requests use the same redirect origin policy', () async {
    var requests = 0;
    final api = client(
      MockClient((request) async {
        requests++;
        expect(request.followRedirects, isFalse);
        return http.Response(
          '',
          302,
          headers: {'location': 'https://evil.test/login'},
        );
      }),
    );
    await expectLater(
      api.sendAuthenticatedRequest(
        Uri.parse('https://example.test/login'),
        bodyFields: {'password': 'private-secret'},
      ),
      throwsA(isA<JsonRpcException>()),
    );
    expect(requests, 1);
    api.close();
  });
}
