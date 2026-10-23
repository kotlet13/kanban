import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/organizer/data/collaboration_database.dart';
import 'package:kanban/organizer/data/e2ee/account_crypto_store.dart';
import 'package:kanban/organizer/data/e2ee/account_crypto_v2_workflow.dart';
import 'package:kanban/organizer/data/e2ee/crypto_identity_store.dart';
import 'package:kanban/organizer/data/e2ee/crypto_inherited_invitation_grants.dart';
import 'package:kanban/organizer/data/e2ee/crypto_json.dart';
import 'package:kanban/organizer/data/e2ee/session_crypto_access.dart';

const parent = '11111111-1111-4111-8111-111111111111';
const invitation = '22222222-2222-4222-8222-222222222222';
const childA = '33333333-3333-4333-8333-333333333333';
const childB = '44444444-4444-4444-8444-444444444444';
const reviewA = '55555555-5555-4555-8555-555555555555';
const reviewB = '66666666-6666-4666-8666-666666666666';

class _Secure implements AccountCryptoStore {
  @override
  Future<String?> read(String key) async => null;
  @override
  Future<void> write(String key, String value) async {}
}

class _Account implements AccountCryptoV2Workflow {
  _Account(this.store);
  @override
  final CryptoIdentityStore store;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test(
    'UUID child automatic review journal persists canonical list and reopens exact review association',
    () async {
      final db = CollaborationDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final payload = {
        'version': 1,
        'parentScopeId': parent,
        'invitationId': invitation,
        'recipientAccountId': reviewB,
        'acceptanceProofHash': 'a' * 64,
        'foregroundOnly': true,
        'children': [childA, childB],
        'automaticReviewIds': InheritedInvitationReviewJournal.encode({
          childB: reviewB,
          childA: reviewA,
        }),
      };
      final bytes = CryptoJson.encode(payload);
      // Same canonical encoder/table/shape as the production _write path.
      await db.execute(
        'INSERT INTO crypto_membership_intents VALUES(?,?,?,?,?,NULL)',
        [
          'synthetic',
          parent,
          'inherited:$invitation',
          'invitationInheritedGrants',
          bytes,
        ],
      );
      final account = _Account(CryptoIdentityStore(db, _Secure(), 'synthetic'));
      final service = CryptoInheritedInvitationGrants(
        SessionCryptoAccess(account: account),
      );
      final reopened = (await service.pending()).single;
      final exact = InheritedInvitationReviewJournal.decode(
        reopened['automaticReviewIds'],
      );
      expect(exact, {childA: reviewA, childB: reviewB});
      expect((reopened['automaticReviewIds'] as List).first, {
        'scopeId': childA,
        'reviewId': reviewA,
      });
      expect(exact[childA], isNot(reviewB));
      expect(exact['77777777-7777-4777-8777-777777777777'], isNull);
      expect(CryptoJson.encode(reopened), bytes);
      final row = (await db.rows(
        'SELECT payload,authorization FROM crypto_membership_intents',
      )).single;
      expect(Uint8List.fromList((row['payload'] as List).cast<int>()), bytes);
      expect(row['authorization'], isNull);
    },
  );

  final malformed = <String, Object>{
    'legacy UUID property map': {childA: reviewA},
    'duplicate child scope': [
      {'scopeId': childA, 'reviewId': reviewA},
      {'scopeId': childA, 'reviewId': reviewB},
    ],
    'duplicate review across children': [
      {'scopeId': childA, 'reviewId': reviewA},
      {'scopeId': childB, 'reviewId': reviewA},
    ],
    'invalid scope UUID': [
      {'scopeId': 'not-a-uuid', 'reviewId': reviewA},
    ],
    'invalid review UUID': [
      {'scopeId': childA, 'reviewId': 'not-a-uuid'},
    ],
    'unknown field': [
      {'scopeId': childA, 'reviewId': reviewA, 'manual': true},
    ],
    'unsorted child scopes': [
      {'scopeId': childB, 'reviewId': reviewB},
      {'scopeId': childA, 'reviewId': reviewA},
    ],
  };
  for (final entry in malformed.entries) {
    test(
      'automatic review journal rejects ${entry.key} without selecting a review',
      () {
        expect(
          () => InheritedInvitationReviewJournal.decode(entry.value),
          throwsA(isA<FormatException>()),
        );
      },
    );
  }
  test(
    'historical inherited journal without automatic review ids remains readable',
    () {
      expect(InheritedInvitationReviewJournal.decode(null), isEmpty);
    },
  );
}
