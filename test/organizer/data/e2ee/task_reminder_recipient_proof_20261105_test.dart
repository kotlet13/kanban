import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/organizer/data/e2ee/account_crypto_v2_workflow.dart';
import 'package:kanban/organizer/data/e2ee/account_directory_repository.dart';
import 'package:kanban/organizer/data/e2ee/account_directory_v2.dart';
import 'package:kanban/organizer/data/e2ee/crypto_business_notifications.dart';
import 'package:kanban/organizer/data/e2ee/crypto_business_router.dart';
import 'package:kanban/organizer/data/e2ee/crypto_record_address.dart';
import 'package:kanban/organizer/data/e2ee/session_crypto_access.dart';
import 'package:kanban/organizer/domain/notification_models.dart';

import 'crypto_checkpoint_supersession_20261102_test.dart'
    show reauthorizationFixture, scope;

// Only acquisition is synthetic: the existing fixture initializes and reduces
// a genuinely signed own directory and supplies its active device signing key.
// Production reminder parsing/signature checks run here. Terminal metadata does
// not mint a scheduling-use lease or establish active target content authority.
class _Directory extends AccountDirectoryRepository {
  _Directory(AccountDirectoryRepository source, this.own)
    : super(
        reducer: source.reducer,
        session: source.session,
        transport: source.transport,
        store: source.store,
        isCurrent: source.isCurrent,
      );
  final VerifiedAccountDirectory own;
  late Map<String, dynamic> reminder;
  @override
  Future<VerifiedAccountDirectory> cachedVerifiedDirectory() async => own;
  @override
  Future<Map<String, dynamic>> call(
    String operation, [
    Map<String, dynamic> params = const {},
  ]) async {
    if (operation != 'crypto2.reminders.list') {
      throw StateError('unexpected_recipient_proof_request');
    }
    return {
      'reminders': [reminder],
      'hasMore': false,
    };
  }
}

Future<
  ({
    CryptoBusinessNotifications adapter,
    _Directory directory,
    Map<String, dynamic> wire,
  })
>
_fixture({String? policy, bool conflictingCurrentPut = false}) async {
  final f = await reauthorizationFixture();
  final original = f.runtime.account as AccountCryptoV2Workflow;
  final own = await original.directory.requireFresh();
  final directory = _Directory(original.directory, own);
  final account = AccountCryptoV2Workflow(directory);
  final address = CryptoRecordAddress.forType(
    serverId: own.serverId,
    scopeId: scope,
    type: 'task',
    canonicalId: '10000000-0000-4000-8000-000000000002',
  );
  final payload = {
    'id': '10000000-0000-4000-8000-000000000003',
    'scopeId': scope,
    'targetType': 'task',
    'targetId': address.wireId,
    'targetIdentity': address.identity,
    'remindAt': '2026-11-06T12:00:00.000Z',
    'expectedRevision': 0,
    if (policy != null) 'recipientPolicy': policy,
  };
  final proof = directory.reducer.crypto.signDomain(
    {
      'version': 2,
      'operation': 'crypto2.reminders.put',
      'requestId': '10000000-0000-4000-8000-000000000004',
      'serverId': own.serverId,
      'accountId': own.accountId,
      'deviceId': account.deviceId,
      'signer': 'device',
      'payload': payload,
    },
    f.access.signing.secretKey,
    cryptoDirectoryDomain,
  );
  final wire = <String, dynamic>{
    'id': payload['id'],
    'scopeId': scope,
    'targetType': 'task',
    'targetId': address.wireId,
    'targetIdentity': address.identity,
    'remindAt': payload['remindAt'],
    'revision': 1,
    'state': 'delivered',
    'targetRevision': 1,
    'scheduleRevision': '10000000-0000-4000-8000-000000000005',
    'authorization': proof,
    'putAuthorization': proof,
    if (policy != null) 'recipientPolicy': policy,
  };
  if (conflictingCurrentPut) {
    // Both device signatures are valid, with the same target and timestamp.
    // A server must not pair a newer shared PUT authorization with an older
    // scheduler-only putAuthorization and project the older recipient policy.
    wire['authorization'] = directory.reducer.crypto.signDomain(
      {
        'version': 2,
        'operation': 'crypto2.reminders.put',
        'requestId': '10000000-0000-4000-8000-000000000006',
        'serverId': own.serverId,
        'accountId': own.accountId,
        'deviceId': account.deviceId,
        'signer': 'device',
        'payload': {
          ...payload,
          'expectedRevision': 1,
          'recipientPolicy': taskReminderRecipientPolicy,
        },
      },
      f.access.signing.secretKey,
      cryptoDirectoryDomain,
    );
    wire['revision'] = 2;
  }
  directory.reminder = Map<String, dynamic>.from(
    jsonDecode(jsonEncode(wire)) as Map,
  );
  return (
    adapter: CryptoBusinessNotifications(
      CryptoBusinessSession(
        account,
        SessionCryptoAccess(account: account),
        f.runtime.database,
      ),
    ),
    directory: directory,
    wire: wire,
  );
}

void main() {
  test(
    'current signed PUT cannot project an older opposite-policy PUT',
    () async {
      final f = await _fixture(conflictingCurrentPut: true);
      await expectLater(
        f.adapter.dispatch('reminders.list', {'scopeId': scope}),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            'crypto_reminder_recipient_substitution',
          ),
        ),
      );
    },
  );
  test(
    'verified signed explicit recipient policy survives a delivered own outcome',
    () async {
      final f = await _fixture(policy: taskReminderRecipientPolicy);
      final result = await f.adapter.dispatch('reminders.list', {
        'scopeId': scope,
      });
      expect(
        (result['reminders'] as List).single['recipientPolicy'],
        taskReminderRecipientPolicy,
      );
      expect((result['reminders'] as List).single['state'], 'delivered');
    },
  );

  test('server omission cannot downgrade signed explicit recipients', () async {
    final f = await _fixture(policy: taskReminderRecipientPolicy);
    f.directory.reminder.remove('recipientPolicy');
    await expectLater(
      f.adapter.dispatch('reminders.list', {'scopeId': scope}),
      throwsA(
        isA<FormatException>().having(
          (e) => e.message,
          'message',
          'crypto_reminder_recipient_substitution',
        ),
      ),
    );
  });

  test(
    'server addition cannot expand a signed legacy scheduler-only reminder',
    () async {
      final f = await _fixture();
      final legacy = await f.adapter.dispatch('reminders.list', {
        'scopeId': scope,
      });
      expect(
        (legacy['reminders'] as List).single.containsKey('recipientPolicy'),
        isFalse,
      );
      f.directory.reminder['recipientPolicy'] = taskReminderRecipientPolicy;
      await expectLater(
        f.adapter.dispatch('reminders.list', {'scopeId': scope}),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            'crypto_reminder_recipient_substitution',
          ),
        ),
      );
    },
  );

  test(
    'matching audience cannot conceal an altered original put signature',
    () async {
      final f = await _fixture(policy: taskReminderRecipientPolicy);
      final proof = f.directory.reminder['putAuthorization'] as Map;
      final original = proof['signatureBase64'] as String;
      final bytes = base64Decode(original)..[0] ^= 1;
      proof['signatureBase64'] = base64Encode(bytes);
      await expectLater(
        f.adapter.dispatch('reminders.list', {'scopeId': scope}),
        throwsA(anything),
      );
    },
  );
}
