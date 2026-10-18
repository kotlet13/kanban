import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sodium/sodium.dart';
import 'package:kanban/organizer/data/e2ee/crypto_codec.dart';
import 'package:kanban/organizer/data/e2ee/crypto_consent_generation.dart';
import 'package:kanban/organizer/data/e2ee/crypto_record_address.dart';
import 'package:kanban/organizer/data/e2ee/crypto_record_proof_codec.dart';

const generation = '11111111-1111-4111-8111-111111111111';
const rotated = '22222222-2222-4222-8222-222222222222';
const schedule = '33333333-3333-4333-8333-333333333333';
Map<String, dynamic> state({int? due = 100, bool closed = false}) => {
  'version': 1,
  'dueAtEpoch': due,
  'closed': closed,
  'scheduleRevision': schedule,
};

void main() {
  test(
    'canonical mint is signed and accepted by the real record codec',
    () async {
      final crypto = CryptoCodec(await SodiumInit.init());
      final codec = CryptoRecordProofCodec(crypto);
      final signer = crypto.sodium.crypto.sign.keyPair();
      final key = crypto.sodium.secureRandom(32);
      try {
        final server = crypto.randomId(),
            scope = crypto.randomId(),
            id = crypto.randomId();
        final metadata = <String, dynamic>{
          'identity': {'sourceKind': 'records', 'canonicalId': id},
          'references': <dynamic>[],
          'uniqueRefs': <String>[],
          'blobIds': <String>[],
          'notificationState': {
            'version': 1,
            'kind': 'updated',
            'assigneeAccountIds': <String>[],
            'groupTargetId': null,
          },
          'reminderState': state(),
        };
        CryptoConsentGeneration.mintCanonical(metadata, () => generation);
        final proof = codec.sealRecord(
          serverId: server,
          accountId: crypto.randomId(),
          deviceId: crypto.randomId(),
          batchId: crypto.randomId(),
          scopeId: scope,
          id: cryptoWireRecordId(server, scope, 'task', id),
          type: 'task',
          expectedRevision: 0,
          epoch: 1,
          accessRevision: 1,
          membershipHeadHash: '1' * 64,
          domain: 'content',
          contentContract: 6,
          operationId: crypto.randomId(),
          previousRecordHash: '0' * 64,
          deleted: false,
          plaintext: Uint8List.fromList(utf8.encode('private task')),
          metadata: metadata,
          contentKey: key,
          signingKey: signer.secretKey,
        );
        final body = crypto.verifyDomain(
          proof,
          signer.publicKey,
          'JivieE2EE/record/v2\n',
        );
        codec.validateUntrustedRecord(body);
        expect(
          body['metadata']['reminderState']['consentGeneration'],
          generation,
        );
        expect(body['metadata']['reminderState']['scheduleRevision'], schedule);
        expect(
          CryptoConsentGeneration.matchesReminder(
            body['metadata']['reminderState'],
            {'version': 1, 'dueAtEpoch': 100, 'closed': false},
          ),
          isTrue,
        );
        // Metadata parsing must accept the already-supported migration use
        // variant too; actual consent authority remains the full use verifier.
        for (final version in [2, 3]) {
          final use = crypto.signDomain(
            {
              'version': version,
              'operation': version == 3
                  ? 'crypto2.migration.schedulingUse'
                  : 'crypto2.scheduling.use',
              'serverId': server,
              'scopeId': scope,
              'targetId': body['id'],
              'targetType': 'task',
              'domain': 'content',
            },
            signer.secretKey,
            version == 3
                ? 'JivieE2EE/migrationSchedulingUse/v3\n'
                : 'JivieE2EE/schedulingUse/v2\n',
          );
          final attached = {
            ...body,
            'metadata': {
              ...metadata,
              'schedulingUse': {
                'authorization': use,
                'directoryHeadHash': '2' * 64,
                'eventCommandHash': '3' * 64,
              },
            },
          };
          expect(
            () => codec.validateUntrustedRecord(attached),
            returnsNormally,
          );
          final wrong = crypto.signDomain(
            {
              ...crypto.verifyDomain(
                use,
                signer.publicKey,
                version == 3
                    ? 'JivieE2EE/migrationSchedulingUse/v3\n'
                    : 'JivieE2EE/schedulingUse/v2\n',
              ),
              'operation': 'crypto2.scheduling.cancel',
            },
            signer.secretKey,
            'JivieE2EE/schedulingUse/v2\n',
          );
          expect(
            () => codec.validateUntrustedRecord({
              ...body,
              'metadata': {
                ...metadata,
                'schedulingUse': {
                  'authorization': wrong,
                  'directoryHeadHash': '2' * 64,
                  'eventCommandHash': '3' * 64,
                },
              },
            }),
            throwsFormatException,
          );
        }
        final project = <String, dynamic>{
          'projectState': {'version': 1, 'archived': false},
        };
        CryptoConsentGeneration.mintCanonical(project, () => rotated);
        expect(project['projectState']['consentGeneration'], rotated);
      } finally {
        signer.secretKey.dispose();
        key.dispose();
      }
    },
  );

  test('only close/reopen/delete/archive rotates an existing generation', () {
    var minted = 0;
    Map<String, dynamic> bind(
      Map<String, dynamic> next,
      Map<String, dynamic> old, {
      String field = 'closed',
      bool beforeDeleted = false,
      bool deleted = false,
    }) => CryptoConsentGeneration.transition(
      state: next,
      previous: old,
      field: field,
      wasDeleted: beforeDeleted,
      deleted: deleted,
      mint: () {
        minted++;
        return rotated;
      },
    );
    final old = {...state(), 'consentGeneration': generation};
    expect(bind(state(due: 200), old)['consentGeneration'], generation);
    expect(
      minted,
      0,
    ); // Ordinary title/date changes do not revoke existing consent.
    expect(
      bind(state(due: null, closed: true), old)['consentGeneration'],
      rotated,
    );
    expect(
      bind(state(), {
        ...state(due: null, closed: true),
        'consentGeneration': generation,
      })['consentGeneration'],
      rotated,
    );
    expect(
      bind(state(due: null, closed: true), {
        ...state(due: null, closed: true),
        'consentGeneration': generation,
      }, deleted: true)['consentGeneration'],
      rotated,
    );
    expect(
      bind(
        {'version': 1, 'archived': true},
        {'version': 1, 'archived': false, 'consentGeneration': generation},
        field: 'archived',
      )['consentGeneration'],
      rotated,
    );
    for (final invalid in [
      state(),
      {...state(), 'consentGeneration': rotated},
    ]) {
      expect(
        () => CryptoConsentGeneration.validate(
          invalid,
          old,
          'closed',
          false,
          false,
        ),
        throwsFormatException,
      );
    }
    expect(
      () => CryptoConsentGeneration.validate(
        {...state(due: null, closed: true), 'consentGeneration': generation},
        old,
        'closed',
        false,
        false,
      ),
      throwsFormatException,
    );
  });

  test(
    'unrelated ordinary records keep old metadata and never query consent',
    () async {
      final old = state();
      final next = CryptoConsentGeneration.transition(
        state: state(due: 200),
        previous: old,
        field: 'closed',
        wasDeleted: false,
        deleted: false,
        mint: () => throw StateError('unexpected upgrade'),
      );
      expect(next.containsKey('consentGeneration'), isFalse);
      final metadata = {'reminderState': next};
      expect(
        await CryptoConsentGeneration.disclosure(
          metadata,
          (_) async => throw StateError('unexpected lookup'),
        ),
        same(metadata),
      );
    },
  );

  test(
    'no consent masks only clear date; verified use attaches without new issuance',
    () async {
      final raw = {'dueAt': '2030-01-01T00:00:00Z', 'title': 'private'};
      final rawBefore = jsonEncode(raw);
      final metadata = <String, dynamic>{
        'reminderState': {...state(), 'consentGeneration': generation},
      };
      final masked = await CryptoConsentGeneration.disclosure(
        metadata,
        (_) async => null,
      );
      expect(masked['reminderState']['dueAtEpoch'], isNull);
      expect(masked.containsKey('schedulingUse'), isFalse);
      expect(jsonEncode(raw), rawBefore);
      expect(metadata['reminderState']['dueAtEpoch'], 100);
      expect(
        CryptoConsentGeneration.matchesReminder(masked['reminderState'], {
          'version': 1,
          'dueAtEpoch': 100,
          'closed': false,
        }),
        isTrue,
      );
      expect(
        CryptoConsentGeneration.matchesReminder(
          {...state(due: null)},
          {'version': 1, 'dueAtEpoch': 100, 'closed': false},
        ),
        isFalse,
      );
      expect(
        CryptoConsentGeneration.matchesReminder(
          {...state(due: 101), 'consentGeneration': generation},
          {'version': 1, 'dueAtEpoch': 100, 'closed': false},
        ),
        isFalse,
      );
      final verified = <String, dynamic>{
        'authorization': {'original': 'proof'},
        'directoryHeadHash': '1' * 64,
        'eventCommandHash': '2' * 64,
      };
      final disclosed = await CryptoConsentGeneration.disclosure(
        metadata,
        (_) async => verified,
      );
      expect(disclosed['schedulingUse'], same(verified));
      expect(disclosed['reminderState']['dueAtEpoch'], 100);
      expect(disclosed['reminderState']['consentGeneration'], generation);
      await expectLater(
        CryptoConsentGeneration.disclosure(
          metadata,
          (_) async => throw const FormatException('unavailable_verified_use'),
        ),
        throwsFormatException,
      );
      final closed = <String, dynamic>{
        'reminderState': {
          ...state(due: null, closed: true),
          'consentGeneration': rotated,
        },
      };
      expect(
        await CryptoConsentGeneration.disclosure(
          closed,
          (_) async => throw StateError('closed target lookup'),
        ),
        same(closed),
      );
    },
  );
}
