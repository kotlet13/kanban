import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kanban/organizer/data/collaboration_transport.dart';
import 'package:kanban/organizer/domain/collaboration_models.dart';
import 'collaboration_transport_test.dart' show StreamingClient;

Matcher failure(String expected) => isA<CollaborationException>().having(
  (error) => error.code,
  'code',
  expected,
);

Future<void> checkResponse(int status, List<int> body, String expected) async {
  final transport = HttpCollaborationTransport(
    client: MockClient((_) async => http.Response.bytes(body, status)),
  );
  addTearDown(transport.close);
  await expectLater(
    transport.call(serverUrl: 'https://outage.invalid/', operation: 'auth.me'),
    throwsA(failure(expected)),
  );
}

void main() {
  for (final status in [500, 502, 503, 504, 599]) {
    test('plain outage HTTP$status is a network failure', () async {
      await checkResponse(
        status,
        utf8.encode('Test2 setup is closed.'),
        'network',
      );
    });
  }
  for (final text in [
    '<html>Maintenance</html>',
    '{"maintenance":true}',
    '[]',
  ]) {
    test('nonprotocol 503 body $text is an outage', () async {
      await checkResponse(503, utf8.encode(text), 'network');
    });
  }
  test('malformed UTF-8 at503 is an outage', () async {
    await checkResponse(503, [0xc3, 0x28], 'network');
  });
  for (final status in [200, 403]) {
    test('plain or malformed UTF-8 HTTP$status stays fail closed', () async {
      await checkResponse(
        status,
        utf8.encode('Not a Native response'),
        'invalid_response',
      );
      await checkResponse(status, [0xc3, 0x28], 'invalid_response');
    });
  }
  for (final status in [200, 503]) {
    test(
      'explicit protocol version/type mismatch HTTP$status is not an outage',
      () async {
        await checkResponse(
          status,
          utf8.encode('{"v":2,"data":{}}'),
          'incompatible_server',
        );
        await checkResponse(
          status,
          utf8.encode('{"v":"1","data":{}}'),
          'incompatible_server',
        );
      },
    );
    test('malformed Native error type HTTP$status stays fail closed', () async {
      await checkResponse(
        status,
        utf8.encode('{"v":1,"error":{"code":42}}'),
        'invalid_response',
      );
    });
  }
  test('malformed v1 success payload remains invalid even at503', () async {
    await checkResponse(
      200,
      utf8.encode('{"v":1,"data":[]}'),
      'invalid_response',
    );
    await checkResponse(
      503,
      utf8.encode('{"v":1,"data":{}}'),
      'invalid_response',
    );
  });
  for (final status in [200, 403, 503]) {
    for (final code in [
      'finance_forbidden',
      'permission_revoked',
      'device_revoked',
      'server_identity_changed',
    ]) {
      test(
        'typed $code atHTTP$status retains authoritative API denial',
        () async {
          final transport = HttpCollaborationTransport(
            client: MockClient(
              (_) async => http.Response(
                jsonEncode({
                  'v': 1,
                  'error': {
                    'code': code,
                    'details': {'reason': 'synthetic'},
                  },
                }),
                status,
              ),
            ),
          );
          addTearDown(transport.close);
          await expectLater(
            transport.call(
              serverUrl: 'https://outage.invalid/',
              operation: 'auth.me',
            ),
            throwsA(
              isA<CollaborationApiException>()
                  .having((error) => error.code, 'code', code)
                  .having((error) => error.details, 'details', {
                    'reason': 'synthetic',
                  }),
            ),
          );
        },
      );
    }
  }
  test('ordinary Native200 success remains usable', () async {
    final transport = HttpCollaborationTransport(
      client: MockClient(
        (_) async => http.Response('{"v":1,"data":{"ok":true}}', 200),
      ),
    );
    addTearDown(transport.close);
    expect(
      await transport.call(
        serverUrl: 'https://outage.invalid/',
        operation: 'auth.me',
      ),
      {'ok': true},
    );
  });
  test('redirect remains rejected before decoding maintenance text', () async {
    await checkResponse(
      302,
      utf8.encode('Service unavailable'),
      'redirect_rejected',
    );
  });
  test(
    'oversized503 stays invalid rather than using outage fallback',
    () async {
      final transport = HttpCollaborationTransport(
        client: StreamingClient(
          (_) async => http.StreamedResponse(
            Stream.value(List<int>.filled(2 * 1024 * 1024 + 1, 32)),
            503,
          ),
        ),
      );
      addTearDown(transport.close);
      await expectLater(
        transport.call(
          serverUrl: 'https://outage.invalid/',
          operation: 'auth.me',
        ),
        throwsA(failure('invalid_response')),
      );
    },
  );
  test(
    '503 slow trickle still obeys total deadline and cancels stream',
    () async {
      late Timer timer;
      var cancelled = false;
      final stream = StreamController<List<int>>(
        onCancel: () {
          cancelled = true;
          timer.cancel();
        },
      );
      timer = Timer.periodic(
        const Duration(milliseconds: 5),
        (_) => stream.add([32]),
      );
      final transport = HttpCollaborationTransport(
        requestTimeout: const Duration(milliseconds: 35),
        client: StreamingClient(
          (_) async => http.StreamedResponse(stream.stream, 503),
        ),
      );
      addTearDown(transport.close);
      await expectLater(
        transport.call(
          serverUrl: 'https://outage.invalid/',
          operation: 'auth.me',
        ),
        throwsA(failure('network')),
      );
      expect(cancelled, true);
      await stream.close();
    },
  );
}
