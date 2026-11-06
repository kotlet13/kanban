import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/organizer/data/collaboration_transport.dart';
import 'package:kanban/organizer/data/e2ee/account_directory_v2.dart';
import 'package:kanban/organizer/data/e2ee/crypto_json.dart';
import 'package:kanban/organizer/data/e2ee/crypto_scope_observations.dart';
import 'package:kanban/organizer/data/e2ee/crypto_sync_repository.dart';
import 'package:kanban/organizer/data/e2ee/scope_crypto_codec.dart';
import 'package:kanban/organizer/domain/collaboration_models.dart';

import 'support/deleted_scope_fixture_20261105.dart';

Map<String, dynamic> _copy(Map value) =>
    Map<String, dynamic>.from(jsonDecode(jsonEncode(value)) as Map);

Matcher _pending(String reason) => isA<CryptoAuthorityPending>().having(
  (error) => error.reason,
  'reason',
  reason,
);

const _historyPending = 'crypto_scope_deletion_history_pending';
const _expired = 'crypto_deleted_scope_evidence_expired';

Future<void> _reject(
  DeletedScopeFixture f,
  Map<String, dynamic> wire, {
  Matcher? matcher,
  bool unchangedPins = true,
}) async {
  final before = await f.durableDigest();
  final pins = Map<String, String>.from(f.secureMemory.values);
  var callbacks = 0;
  await expectLater(
    f.access.withVerifiedDeletedScope(f.scope, wire, (_) async {
      callbacks++;
      return true;
    }),
    throwsA(
      matcher ??
          anyOf(
            isA<CryptoAuthorityPending>(),
            isA<FormatException>(),
            isA<CollaborationException>(),
          ),
    ),
  );
  expect(callbacks, 0);
  expect(await f.durableDigest(), before);
  if (unchangedPins) expect(f.secureMemory.values, pins);
  expect(f.directory.calls, isNot(contains('crypto2.scope.headGet')));
  expect(f.directory.calls, isNot(contains('crypto2.directory.read')));
}

Future<void> _observe(DeletedScopeFixture f, VerifiedScopeHead head) async {
  final wire = f.wires[head.headHash]!;
  final bundle = <String, dynamic>{
    'version': 2,
    'serverId': f.own.serverId,
    'accountId': f.own.accountId,
    'scopeId': f.scope,
    'headHash': head.headHash,
    'proposalProofHash': await cryptoSha256(
      CryptoJson.encode(head.authorization),
    ),
    'activationProofHash': await cryptoSha256(
      CryptoJson.encode(wire['activationAuthorization']),
    ),
    'grantManifestHash': '8' * 64,
    'members': [
      for (final member in head.members)
        {
          'accountId': member['accountId'],
          'directoryHeadHash': member['directoryHeadHash'],
          'deviceSnapshotHash': member['deviceSnapshotHash'],
          'rootFingerprint': f.crypto.fingerprint(
            cryptoBase64(member['rootSigningKeyBase64']),
            cryptoBase64(member['rootEncryptionKeyBase64']),
          ),
        },
    ],
    'acceptanceProofHash': null,
    'checkpoints': <Object>[],
    'lifecycleHash': f.baselineWire['initialLifecycleHash'],
  };
  final hash = await CryptoScopeObservations.digest(bundle);
  final event = await f.prepareOwnEvent(
    operation: 'crypto2.account.scopeObserve',
    payload: {
      'scopeToken': await CryptoScopeObservations.token(
        f.own.serverId,
        f.own.accountId,
        f.scope,
      ),
      'headHash': head.headHash,
      'observationHash': hash,
    },
  );
  // These are exact entries already verified by the production reducer above;
  // raw mutable observation rows alone are never used as an anchor.
  for (final entry in f.directory.entries) {
    await f.db
        .execute('INSERT INTO crypto_directory_entries VALUES(?,?,?,?,?,?,?)', [
          f.partition,
          f.own.accountId,
          entry['generation'],
          entry['headHash'],
          entry['previousHeadHash'],
          entry['commandHash'],
          CryptoJson.encode(entry['authorization']),
        ]);
  }
  await f.db.execute(
    'INSERT INTO crypto_membership_intents VALUES(?,?,?,?,?,NULL)',
    [
      f.partition,
      f.scope,
      hash,
      'scopeObservationIncluded',
      CryptoJson.encode({
        'generation': event.result.generation,
        'eventCommandHash': event.entry['commandHash'],
        'observation': bundle,
      }),
    ],
  );
}

// The previous diagnostic passed on the old implementation's exact-head
// rejection. Its historical result is preserved in the investigation record.
// This changed expectation exercises the completed retained-descendant path.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'deleted retained scope verifies signed unseen descendant without durable promotion',
    () async {
      final f = await deletedScopeFixture();
      // Force acquisition through the narrowly scoped retained endpoint rather
      // than satisfying all predecessor reads from the synthetic SQL seed.
      await f.db.execute('DELETE FROM crypto_scope_heads WHERE partition=?', [
        f.partition,
      ]);
      final before = await f.durableDigest();
      final pins = Map<String, String>.from(f.secureMemory.values);
      var callbacks = 0;
      final result = await f.access.withVerifiedDeletedScope(
        f.scope,
        f.wires[f.heads[2].headHash]!,
        (head) async {
          callbacks++;
          expect(head.active, isTrue);
          expect(head.epoch, 3);
          expect(head.headHash, f.heads[2].headHash);
          expect(head.body['previousHeadHash'], f.heads[1].headHash);
          expect(await f.secureMemory.read(f.scopePinKey), f.initialPin);
          return 'verified';
        },
      );
      expect(result, 'verified');
      expect(callbacks, 1);
      expect(f.secureMemory.values, pins);
      expect(await f.durableDigest(), before);
      expect(f.directory.calls, contains('crypto2.scope.deletionHead'));
      expect(f.directory.calls, contains('crypto2.scope.deletionDirectory'));
      expect(
        f.directory.calls,
        everyElement(
          isIn(const {
            'crypto2.account.scopeObservations',
            'crypto2.scope.deletionHead',
            'crypto2.scope.deletionDirectory',
          }),
        ),
      );
    },
  );

  test(
    'deleted retained scope accepts an exact previously anchored head',
    () async {
      final f = await deletedScopeFixture();
      final before = await f.durableDigest();
      final pins = Map<String, String>.from(f.secureMemory.values);
      final head = await f.access.withVerifiedDeletedScope(
        f.scope,
        f.wires[f.heads[1].headHash]!,
        (value) async => value,
      );
      expect(head.headHash, f.heads[1].headHash);
      expect(await f.durableDigest(), before);
      expect(f.secureMemory.values, pins);
    },
  );

  for (final proofName in ['authorization', 'activationAuthorization']) {
    test('deleted retained scope rejects tampered $proofName', () async {
      final f = await deletedScopeFixture();
      final wire = _copy(f.wires[f.heads[2].headHash]!);
      final proof = wire[proofName] as Map;
      final signature = base64Decode(proof['signatureBase64'] as String);
      signature[0] ^= 1;
      proof['signatureBase64'] = base64Encode(signature);
      await _reject(f, wire, matcher: isA<FormatException>());
    });
  }

  test(
    'deleted retained scope rejects a genuinely signed fork beyond the floor',
    () async {
      final f = await deletedScopeFixture();
      await f.makeHead(previous: f.heads[0]);
      final fork = f.heads.last;
      final wire = await f.makeHead(previous: fork);
      expect(fork.epoch, 2);
      expect(fork.headHash, isNot(f.heads[1].headHash));
      await _reject(f, wire, matcher: _pending(_historyPending));
    },
  );

  test(
    'deleted retained scope refuses rollback below its secure floor',
    () async {
      final f = await deletedScopeFixture();
      await _reject(
        f,
        f.wires[f.heads[0].headHash]!,
        matcher: _pending(_historyPending),
      );
    },
  );

  test('deleted retained scope rejects a cross-scope candidate', () async {
    final f = await deletedScopeFixture();
    final wire = _copy(f.wires[f.heads[2].headHash]!);
    final body = Map<String, dynamic>.from(wire['payload'] as Map);
    body['scopeId'] = f.crypto.randomId();
    wire['payload'] = body;
    wire['headHash'] = await ScopeCryptoCodec(f.crypto).headHash(body);
    await _reject(f, wire, matcher: isA<FormatException>());
  });

  test(
    'deleted retained scope rejects a signed proposal from another server',
    () async {
      final f = await deletedScopeFixture();
      final wire = _copy(f.wires[f.heads[2].headHash]!);
      final command = Map<String, dynamic>.from(
        CryptoJson.decode(cryptoBase64(wire['authorization']['commandBase64']))
            as Map,
      );
      command['serverId'] = f.crypto.randomId();
      wire['authorization'] = f.sign(command, cryptoDirectoryDomain);
      await _reject(f, wire, matcher: isA<FormatException>());
    },
  );

  test('deleted retained scope rejects a skipped ancestry epoch', () async {
    final f = await deletedScopeFixture();
    final wire = _copy(f.wires[f.heads[2].headHash]!);
    final body = Map<String, dynamic>.from(wire['payload'] as Map);
    body['previousHeadHash'] = f.heads[0].headHash;
    wire['payload'] = body;
    wire['headHash'] = await ScopeCryptoCodec(f.crypto).headHash(body);
    await _reject(f, wire, matcher: isA<FormatException>());
  });

  test(
    'deleted retained scope holds when an ancestor cannot be acquired',
    () async {
      final f = await deletedScopeFixture();
      f.wires.remove(f.heads[0].headHash);
      await f.db.execute('DELETE FROM crypto_scope_heads WHERE head_hash=?', [
        f.heads[0].headHash,
      ]);
      await _reject(f, f.wires[f.heads[2].headHash]!);
    },
  );

  test(
    'deleted retained scope cannot use raw SQL or a candidate as an anchor',
    () async {
      final f = await deletedScopeFixture();
      f.secureMemory.values.remove(f.scopePinKey);
      await f.db.execute(
        'INSERT INTO crypto_membership_intents VALUES(?,?,?,?,?,NULL)',
        [
          f.partition,
          f.scope,
          'untrusted-candidate',
          'scopeObservationCandidate',
          CryptoJson.encode({'headHash': f.heads[2].headHash}),
        ],
      );
      await _reject(
        f,
        f.wires[f.heads[2].headHash]!,
        matcher: _pending(_historyPending),
      );
    },
  );

  test(
    'deleted retained scope accepts an independently included own observation without a floor',
    () async {
      final f = await deletedScopeFixture();
      await _observe(f, f.heads[1]);
      f.secureMemory.values.remove(f.scopePinKey);
      final before = await f.durableDigest();
      final pins = Map<String, String>.from(f.secureMemory.values);
      final head = await f.access.withVerifiedDeletedScope(
        f.scope,
        f.wires[f.heads[2].headHash]!,
        (value) async => value,
      );
      expect(head.epoch, 3);
      expect(await f.durableDigest(), before);
      expect(f.secureMemory.values, pins);
      expect(await f.secureMemory.read(f.scopePinKey), isNull);
    },
  );

  test(
    'deleted retained scope must cover a newer included own observation as well as the floor',
    () async {
      final f = await deletedScopeFixture();
      await f.makeHead(previous: f.heads[2]);
      await _observe(f, f.heads.last);
      await _reject(
        f,
        f.wires[f.heads[2].headHash]!,
        matcher: _pending(_historyPending),
      );
    },
  );

  test(
    'deleted retained scope bounds a long signed ancestry before admitting it',
    () async {
      final f = await deletedScopeFixture(headCount: 65);
      await _reject(
        f,
        f.wires[f.heads.last.headHash]!,
        matcher: _pending(_historyPending),
      );
      expect(
        f.directory.calls
            .where((op) => op == 'crypto2.scope.deletionHead')
            .length,
        lessThanOrEqualTo(64),
      );
    },
  );

  test(
    'deleted retained scope rejects an oversized candidate before callback',
    () async {
      final f = await deletedScopeFixture();
      final wire = _copy(f.wires[f.heads[2].headHash]!);
      wire['oversizedTransportField'] = 'x' * (2 * 1024 * 1024 + 1);
      await _reject(f, wire, matcher: isA<FormatException>());
    },
  );

  test(
    'deleted retained scope bounds an oversized retained directory response',
    () async {
      final f = await deletedScopeFixture();
      f.directory.handlers['crypto2.scope.deletionDirectory'] = (_) async => {
        'entries': f.directory.entries,
        'hasMore': false,
        'oversizedTransportField': 'x' * (8 * 1024 * 1024 + 1),
      };
      await _reject(f, f.wires[f.heads[2].headHash]!);
    },
  );

  test(
    'deleted retained scope bounds retained requests even when caller handles missing evidence',
    () async {
      final f = await deletedScopeFixture();
      final before = await f.durableDigest();
      var exhausted = false;
      await f.access.withVerifiedDeletedScope(
        f.scope,
        f.wires[f.heads[2].headHash]!,
        (_) async {
          for (var i = 0; i < 260; i++) {
            try {
              await f.access.directoryAt(
                scopeId: f.scope,
                scopeHeadHash: f.heads[2].headHash,
                accountId: f.own.accountId,
                directoryHeadHash: 'f' * 64,
                online: true,
              );
            } on CryptoAuthorityPending catch (error) {
              if (error.reason == _historyPending) {
                exhausted = true;
                break;
              }
              rethrow;
            } on CollaborationApiException catch (error) {
              expect(error.code, 'record_missing');
            }
          }
          expect(exhausted, isTrue);
          return true;
        },
      );
      expect(
        f.directory.calls
            .where((op) => op.startsWith('crypto2.scope.deletion'))
            .length,
        lessThanOrEqualTo(256),
      );
      expect(await f.durableDigest(), before);
    },
  );

  test(
    'deleted retained scope detects a floor race during ancestor acquisition',
    () async {
      final f = await deletedScopeFixture();
      await f.db.execute('DELETE FROM crypto_scope_heads WHERE partition=?', [
        f.partition,
      ]);
      final changed = '${f.initialPin} ';
      f.directory.onCall = (operation, _) async {
        if (operation == 'crypto2.scope.deletionHead') {
          f.directory.onCall = null;
          await f.secureMemory.write(f.scopePinKey, changed);
        }
      };
      await _reject(
        f,
        f.wires[f.heads[2].headHash]!,
        matcher: _pending(_expired),
        unchangedPins: false,
      );
      expect(await f.secureMemory.read(f.scopePinKey), changed);
    },
  );

  test(
    'deleted retained scope detects session loss during directory acquisition',
    () async {
      final f = await deletedScopeFixture();
      f.directory.onCall = (operation, _) async {
        if (operation == 'crypto2.scope.deletionDirectory') {
          f.directory.current = false;
        }
      };
      await _reject(
        f,
        f.wires[f.heads[2].headHash]!,
        matcher: _pending(_expired),
      );
    },
  );

  test(
    'deleted retained scope rejects a changed own prefix after callback',
    () async {
      final f = await deletedScopeFixture();
      final before = await f.durableDigest();
      final pin = await f.secureMemory.read(f.scopePinKey);
      var callbacks = 0;
      await expectLater(
        f.access.withVerifiedDeletedScope(
          f.scope,
          f.wires[f.heads[2].headHash]!,
          (_) async {
            callbacks++;
            await f.prepareOwnEvent(
              operation: 'crypto2.account.scopeDeletion',
              payload: {'scopeToken': '1' * 64, 'certificateHash': '2' * 64},
            );
            return true;
          },
        ),
        throwsA(_pending(_expired)),
      );
      expect(callbacks, 1);
      expect(f.own.generation, 2);
      expect(await f.secureMemory.read(f.scopePinKey), pin);
      expect(await f.durableDigest(), before);
    },
  );

  test(
    'deleted retained scope does not overwrite a floor changed by its callback',
    () async {
      final f = await deletedScopeFixture();
      final before = await f.durableDigest();
      final changed = '${f.initialPin} ';
      await expectLater(
        f.access.withVerifiedDeletedScope(
          f.scope,
          f.wires[f.heads[2].headHash]!,
          (_) async {
            await f.secureMemory.write(f.scopePinKey, changed);
            return true;
          },
        ),
        throwsA(_pending(_expired)),
      );
      expect(await f.secureMemory.read(f.scopePinKey), changed);
      expect(await f.durableDigest(), before);
    },
  );

  test(
    'deleted retained scope discards callback failure context and durable caches',
    () async {
      final f = await deletedScopeFixture();
      final before = await f.durableDigest();
      final pins = Map<String, String>.from(f.secureMemory.values);
      final failure = StateError('intentional_caller_failure');
      await expectLater(
        f.access.withVerifiedDeletedScope(
          f.scope,
          f.wires[f.heads[2].headHash]!,
          (_) async => throw failure,
        ),
        throwsA(same(failure)),
      );
      expect(await f.durableDigest(), before);
      expect(f.secureMemory.values, pins);
    },
  );

  test('deleted retained scope cannot grant active writes or keys', () async {
    final f = await deletedScopeFixture();
    final before = await f.durableDigest();
    await f.access.withVerifiedDeletedScope(
      f.scope,
      f.wires[f.heads[2].headHash]!,
      (_) async {
        await expectLater(
          f.access.writeContext(f.scope, 'content'),
          throwsA(_pending('crypto_frozen_source_read_only')),
        );
        await expectLater(
          f.access.getScopeKey(f.scope, 'content', 3),
          throwsA(_pending('crypto_deleted_scope_evidence_only')),
        );
        return true;
      },
    );
    expect(await f.durableDigest(), before);
    expect(f.directory.calls, isNot(contains('crypto2.scope.headGet')));
    expect(f.directory.calls, isNot(contains('crypto2.grants.list')));
  });
}
