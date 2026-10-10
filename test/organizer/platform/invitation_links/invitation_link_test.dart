import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/organizer/platform/invitation_links/invitation_link.dart';
import 'package:kanban/organizer/platform/invitation_links/invitation_link_providers.dart';

void main() {
  final token = 'fhi1_${List.filled(64, 'a').join()}';
  Uri link(String server, {String? value, String scheme = 'jivie'}) => Uri(
    scheme: scheme,
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
  test('email version 2 link requires matching token and explicit version', () {
    final email = InvitationLink(
      serverUrl: 'https://example.test/kanboard',
      token: 'fhi2_${'b' * 64}',
    );
    final parsed = InvitationLink.tryParse(email.toUri())!;
    expect(parsed.token, email.token);
    expect(parsed.toUri().queryParameters['v'], '2');
    expect(
      InvitationLink.tryParse(
        email.toUri().replace(
          queryParameters: {'server': email.serverUrl, 'token': email.token},
        ),
      ),
      isNull,
    );
    expect(
      InvitationLink.tryParse(
        link('https://example.test').replace(
          queryParameters: {
            'server': 'https://example.test',
            'token': token,
            'v': '2',
          },
        ),
      ),
      isNull,
    );
    expect(
      InvitationLink.tryParse(
        email.toUri().replace(
          queryParameters: {...email.toUri().queryParameters, 'extra': 'value'},
        ),
      ),
      isNull,
    );
  });
  test('accepts legacy invitations and emits the Jivie scheme', () {
    final legacy = link('https://example.test/kanboard', scheme: 'vsakdan');
    final parsed = InvitationLink.tryParse(legacy)!;
    expect(parsed.serverUrl, 'https://example.test/kanboard');
    expect(parsed.token, token);
    expect(parsed.toUri(), legacy.replace(scheme: 'jivie'));
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
        for (final scheme in InvitationLink.supportedSchemes) {
          expect(
            InvitationLink.tryParse(link(server, scheme: scheme)),
            isNull,
            reason: '$scheme $server',
          );
        }
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
        valid.replaceFirst('jivie:', 'https:'),
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
