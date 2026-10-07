import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/organizer/data/account_deletion_preview.dart';
import 'package:kanban/organizer/domain/collaboration_models.dart';
import '../ui/sharing_ui_fixture.dart' show sharingSession, sharingScopeId;

Map<String, dynamic> preview() => {
  'serverId': sharingSession().serverId,
  'accountId': sharingSession().accountId,
  'policyVersion': 1,
  'previewHash': 'a' * 64,
  'canDelete': false,
  'impact': <String, dynamic>{'personalRecords': 2},
  'blockers': [
    {'code': 'shared_scope_owner', 'count': 1, 'scopeId': sharingScopeId},
  ],
  'sharedScopes': [
    {'id': sharingScopeId, 'kind': 'household', 'name': 'Dom', 'role': 'owner'},
  ],
  'ownedScopes': [
    {
      'id': sharingScopeId,
      'kind': 'household',
      'name': 'Dom',
      'canDeleteScope': false,
      'eligibleSuccessors': [
        {
          'accountId': sharingSession(second: true).accountId,
          'displayName': 'B',
        },
      ],
    },
  ],
  'resolutions': [
    {
      'scopeId': sharingScopeId,
      'recordId': sharingScopeId,
      'type': 'financeAccount',
      'action': 'preserveStructure',
      'name': 'Račun',
      'currency': 'EUR',
      'openingBalanceMinor': 12300,
    },
  ],
};
void main() {
  test('valid review decodes every consumed nested field', () {
    expect(
      decodeAccountDeletionPreview(preview(), sharingSession())['resolutions'],
      hasLength(1),
    );
  });
  final corruptions = <void Function(Map<String, dynamic>)>[
    (p) => (p['impact'] as Map)['personalRecords'] = 'many',
    (p) => ((p['ownedScopes'] as List).first as Map)['eligibleSuccessors'] = [
      'bad',
    ],
    (p) => ((p['ownedScopes'] as List).first as Map)['canDeleteScope'] = 'yes',
    (p) =>
        ((p['resolutions'] as List).first as Map)['openingBalanceMinor'] = 1.5,
    (p) => ((p['resolutions'] as List).first as Map)['action'] = 'erase',
    (p) => ((p['sharedScopes'] as List).first as Map)['name'] = 5,
    (p) => ((p['blockers'] as List).first as Map)['count'] = -1,
    (p) => p['canDelete'] = true,
  ];
  for (var i = 0; i < corruptions.length; i++) {
    test('malformed nested preview rejected before form $i', () {
      final p = jsonDecode(jsonEncode(preview())) as Map<String, dynamic>;
      corruptions[i](p);
      expect(
        () => decodeAccountDeletionPreview(p, sharingSession()),
        throwsA(
          isA<CollaborationException>().having(
            (e) => e.code,
            'code',
            'invalid_response',
          ),
        ),
      );
    });
  }
}
