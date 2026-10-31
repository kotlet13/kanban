import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/organizer/platform/email_verification/email_verification_link.dart';
import 'package:kanban/organizer/platform/invitation_links/invitation_link.dart';
import '../../ui/sharing_ui_fixture.dart';

void main() {
  final session = sharingSession();
  final link = EmailVerificationLink(
    serverUrl: session.serverUrl,
    serverId: session.serverId,
    accountId: session.accountId,
    email: 'name.surname@example.test',
    token: 'fhv1_${'a' * 64}',
  );
  test(
    'native verification is separate from invitations and matches exact account/server',
    () {
      final parsed = EmailVerificationLink.tryParse(link.toUri())!;
      expect(parsed.matches(session), isTrue);
      expect(parsed.email, link.email);
      expect(InvitationLink.tryParse(link.toUri()), isNull);
      for (final entry in {
        'server': 'https://other.test',
        'serverId': '00000000-0000-4000-a000-000000000099',
        'accountId': '00000000-0000-4000-a000-000000000099',
      }.entries) {
        final different = link.toUri().replace(
          queryParameters: {
            ...link.toUri().queryParameters,
            entry.key: entry.value,
          },
        );
        expect(
          EmailVerificationLink.tryParse(different)?.matches(session),
          isFalse,
        );
      }
    },
  );
  test(
    'HTTPS mail fragment roundtrips without putting token into request query',
    () {
      final uri = Uri.parse('${session.serverUrl}/index.php').replace(
        queryParameters: {
          'controller': 'EmailVerificationController',
          'action': 'show',
          'plugin': 'FamilyHub',
          'language': 'en',
        },
        fragment: Uri(
          queryParameters: {
            'serverId': link.serverId,
            'accountId': link.accountId,
            'email': link.email,
            'token': link.token,
          },
        ).query,
      );
      expect(uri.query.contains(link.token), isFalse);
      expect(EmailVerificationLink.tryParse(uri)?.toUri(), link.toUri());
      expect(
        EmailVerificationLink.tryParse(
          uri.replace(
            queryParameters: {...uri.queryParameters, 'action': 'confirm'},
          ),
        ),
        isNull,
      );
    },
  );
  test(
    'malformed duplicate and insecure verification link fields are rejected',
    () {
      final original = link.toUri();
      for (final uri in [
        original.replace(
          queryParameters: {
            ...original.queryParameters,
            'server': 'http://example.test',
          },
        ),
        original.replace(
          queryParameters: {
            ...original.queryParameters,
            'server': 'https://example.test/a/%2e%2e/b',
          },
        ),
        original.replace(
          queryParameters: {
            ...original.queryParameters,
            'token': 'fhi4_${'a' * 64}',
          },
        ),
        original.replace(
          queryParameters: {...original.queryParameters, 'accountId': 'other'},
        ),
        original.replace(
          queryParameters: {...original.queryParameters, 'extra': '1'},
        ),
        Uri.parse('$original&token=${link.token}'),
      ]) {
        expect(EmailVerificationLink.tryParse(uri), isNull);
      }
    },
  );
}
