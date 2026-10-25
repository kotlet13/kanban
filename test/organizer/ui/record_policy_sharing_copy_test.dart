import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/l10n/app_localizations.dart';
import 'package:kanban/organizer/data/e2ee/account_directory_v2.dart';
import 'package:kanban/organizer/data/e2ee/crypto_json.dart';
import 'package:kanban/organizer/data/e2ee/invite_crypto_repository.dart';
import 'package:kanban/organizer/presentation/shared/sharing_role_permissions.dart';
import 'package:kanban/organizer/presentation/shared/verified_invitation_permissions.dart';

class _Creator implements VerifiedAccountDirectory {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test(
    'active sharing copy distinguishes records and preserves legacy in SL and EN',
    () async {
      for (final locale in const [Locale('en'), Locale('sl')]) {
        final l = await AppLocalizations.delegate.load(locale);
        expect(
          sharingInvitationRoleLabel(l, 'member', recordPolicyVersion: 1),
          l.sharingMember,
        );
        expect(
          sharingPermissionDescription(l, 'member', recordPolicyVersion: 1),
          l.sharingRecordMemberDescription,
        );
        expect(
          sharingPermissionDescription(l, 'owner', recordPolicyVersion: 1),
          l.sharingRecordOwnerDescription,
        );
        expect(
          sharingPermissionDescription(l, 'viewer', recordPolicyVersion: 1),
          l.sharingRecordViewerDescription,
        );
        expect(
          l.sharingRecordMemberDescription,
          isNot(
            contains(
              locale.languageCode == 'en' ? 'Full access' : 'Polni dostop',
            ),
          ),
        );
        expect(
          l.sharingRecordMemberDescription,
          contains(
            locale.languageCode == 'en'
                ? 'assigned tasks'
                : 'dodeljena opravila',
          ),
        );
        expect(
          l.sharingRecordMemberDescription,
          contains(
            locale.languageCode == 'en'
                ? 'Finance permissions are separate'
                : 'Finančne pravice so ločene',
          ),
        );
        expect(
          sharingPermissionDescription(l, 'member', recordPolicyVersion: 0),
          l.sharingMemberFullDescription,
        );
        expect(
          sharingPermissionDescription(l, 'viewer', recordPolicyVersion: 0),
          l.sharingViewerDescription,
        );
        expect(
          sharingInvitationRoleLabel(l, 'member', recordPolicyVersion: 0),
          l.spaceFlowFullAccess,
        );
      }
    },
  );

  testWidgets(
    'recipient policy copy follows signed role while finance remains separate',
    (tester) async {
      for (final locale in const [Locale('en'), Locale('sl')]) {
        final l = await AppLocalizations.delegate.load(locale);
        final response = <String, dynamic>{
          'scope': {'recordPolicyVersion': 1},
          // Display-only host proposal must not replace the signed recipient role.
          'proposedMember': {'role': 'owner'},
          'creatorAuthorization': {
            'commandBase64': base64Encode(
              CryptoJson.encode({
                'payload': {
                  'role': 'member',
                  'preauthorization': {
                    'member': {'financeRole': 'read', 'manageKeys': false},
                  },
                },
              }),
            ),
          },
        };
        final invite = VerifiedCryptoInvitation(response, _Creator(), []);
        Future<void> render() => tester.pumpWidget(
          MaterialApp(
            locale: locale,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: VerifiedInvitationPermissions(invitation: invite),
            ),
          ),
        );
        await render();
        await tester.pumpAndSettle();
        expect(find.text(l.sharingRecordMemberDescription), findsOneWidget);
        expect(find.text(l.sharingRecordOwnerDescription), findsNothing);
        expect(find.text(l.cryptoSharingFinanceRead), findsOneWidget);
        expect(find.text(l.cryptoSharingFinanceWrite), findsNothing);
        response['scope'] = <String, dynamic>{};
        await render();
        await tester.pumpAndSettle();
        expect(find.text(l.sharingRecordMemberDescription), findsNothing);
        expect(find.text(l.cryptoSharingFinanceRead), findsOneWidget);
      }
    },
  );
}
