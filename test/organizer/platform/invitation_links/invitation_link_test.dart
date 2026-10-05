import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/organizer/platform/invitation_links/invitation_link.dart';
import 'package:kanban/organizer/platform/invitation_links/invitation_link_providers.dart';

void main() {
  final token = 'fhi1_${List.filled(64, 'a').join()}';
  Uri link(String server, {String? value}) => Uri(
    scheme: 'vsakdan',
    host: 'invite',
    queryParameters: {'server': server, 'token': value ?? token},
  );
  test('valid HTTPS invitation round trips without changing server path', () {
    final original = link('https://example.test/kanboard');
    final parsed = InvitationLink.tryParse(original)!;
    expect(parsed.serverUrl, 'https://example.test/kanboard');
    expect(parsed.token, token);
    expect(parsed.toUri(), original);
  });
  test(
    'rejects credentials, non HTTPS, query, fragment, traversal and unsafe ports',
    () {
      for (final server in [
        'http://example.test',
        'https://user:pass@example.test',
        'https://example.test?q=1',
        'https://example.test/#x',
        'https://example.test/%2E%2E/data',
        'https://example.test/%2Fdata',
        'https://example.test/%5Cdata',
        'https://example.test:65536',
      ]) {
        expect(InvitationLink.tryParse(link(server)), isNull, reason: server);
      }
    },
  );
  test(
    'rejects duplicate or extra parameters and non invitation locations',
    () {
      final valid = link('https://example.test').toString();
      for (final uri in [
        '$valid&token=$token',
        '$valid&extra=1',
        valid.replaceFirst('vsakdan:', 'https:'),
        valid.replaceFirst('invite?', 'invite/other?'),
        '$valid#fragment',
      ]) {
        expect(InvitationLink.tryParse(Uri.parse(uri)), isNull, reason: uri);
      }
    },
  );
  test('rejects malformed and oversized tokens', () {
    for (final value in [
      'fhi1_abc',
      token.toUpperCase(),
      '${token}a',
      'x' * 5000,
    ]) {
      expect(
        InvitationLink.tryParse(link('https://example.test', value: value)),
        isNull,
      );
    }
    expect(
      InvitationLink.tryParse(
        Uri.parse('vsakdan://invite?server=%FF&token=$token'),
      ),
      isNull,
    );
  });
  test(
    'stream then initial duplicates only the first delivery; later retry is allowed',
    () {
      final received = <InvitationLink>[];
      var invalid = 0;
      final receiver = InvitationLinkReceiver(
        onLink: received.add,
        onInvalid: () => invalid++,
      );
      final uri = link('https://example.test');
      receiver.receive(uri);
      receiver.receiveInitial(uri);
      expect(received, hasLength(1));
      receiver.receive(uri);
      expect(received, hasLength(2));
      receiver.receive(Uri.parse('https://example.test'));
      expect(invalid, 1);
    },
  );
}
