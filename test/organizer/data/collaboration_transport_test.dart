import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kanban/organizer/data/collaboration_transport.dart';
import 'package:kanban/organizer/domain/collaboration_models.dart';

class StreamingClient extends http.BaseClient {
  StreamingClient(this.response);
  final Future<http.StreamedResponse> Function(http.BaseRequest) response;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      response(request);
}

Matcher code(String value) =>
    isA<CollaborationException>().having((e) => e.code, 'code', value);
void main() {
  test(
    'canonical base path isolates installs; only explicit loopback HTTP',
    () {
      expect(
        normalizeCollaborationServer('HTTPS://EXAMPLE.test:443/a/../kanboard'),
        'https://example.test/kanboard/',
      );
      expect(
        normalizeCollaborationServer(
          'http://127.0.0.1:18380',
          allowLocalHttp: true,
        ),
        'http://127.0.0.1:18380/',
      );
      for (final url in [
        'http://example.test/',
        'https://user:password@example.test/',
        'https://example.test/?x=1',
        'https://example.test/#fragment',
      ]) {
        expect(
          () => normalizeCollaborationServer(url, allowLocalHttp: true),
          throwsA(code('invalid_server_url')),
        );
      }
      expect(
        () => normalizeCollaborationServer('http://127.0.0.1/'),
        throwsA(code('invalid_server_url')),
      );
    },
  );
  test('bearer is sent once and redirects are explicitly rejected', () async {
    var requests = 0;
    final transport = HttpCollaborationTransport(
      client: MockClient((request) async {
        requests++;
        expect(request.followRedirects, false);
        expect(
          request.headers['Authorization'],
          'Bearer synthetic-device-token',
        );
        expect(request.url.path, '/installation/index.php');
        expect(jsonDecode(request.body)['v'], 1);
        return http.Response(
          '',
          302,
          headers: {'location': 'https://other.invalid/'},
        );
      }),
    );
    await expectLater(
      transport.call(
        serverUrl: 'https://example.test/installation',
        operation: 'auth.me',
        token: 'synthetic-device-token',
      ),
      throwsA(code('redirect_rejected')),
    );
    expect(requests, 1);
    transport.close();
  });
  test(
    'total deadline cancels slow trickle even while chunks keep arriving',
    () async {
      late Timer timer;
      var cancelled = false;
      final stream = StreamController<List<int>>(
        onCancel: () {
          cancelled = true;
          timer.cancel();
        },
      );
      timer = Timer.periodic(const Duration(milliseconds: 5), (_) {
        stream.add([32]);
      });
      final transport = HttpCollaborationTransport(
        requestTimeout: const Duration(milliseconds: 35),
        client: StreamingClient(
          (_) async => http.StreamedResponse(stream.stream, 200),
        ),
      );
      await expectLater(
        transport.call(
          serverUrl: 'https://example.test/',
          operation: 'capabilities',
        ),
        throwsA(code('network')),
      );
      expect(cancelled, true);
      await stream.close();
      transport.close();
    },
  );
  test('unsupported contract fails explicitly without fallback', () async {
    final transport = HttpCollaborationTransport(
      client: MockClient((_) async => http.Response('{"v":2,"data":{}}', 200)),
    );
    await expectLater(
      transport.call(
        serverUrl: 'https://example.test/',
        operation: 'capabilities',
      ),
      throwsA(code('incompatible_server')),
    );
    transport.close();
  });
}
