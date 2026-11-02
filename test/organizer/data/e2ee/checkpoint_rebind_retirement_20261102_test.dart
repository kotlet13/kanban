import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/organizer/data/e2ee/account_directory_v2.dart';
import 'package:kanban/organizer/data/e2ee/crypto_active_outbox.dart';
import 'package:kanban/organizer/data/e2ee/crypto_checkpoint_supersession.dart';
import 'package:kanban/organizer/data/e2ee/crypto_json.dart';
import 'package:kanban/organizer/data/e2ee/crypto_sync_repository.dart';

import 'crypto_checkpoint_supersession_20261102_test.dart'
    show reboundCheckpointFixture, scope;

Future<Map<String, dynamic>> oldProof(dynamic f) async =>
    Map<String, dynamic>.from(
      jsonDecode((await f.runtime.queue.store.outgoing(f.old))['signed_body']),
    );

Future<int> reconcile(dynamic f) async => CryptoCheckpointSupersession(
  f.runtime,
).reconcile(scope, 'content', await f.access.readContext(scope, 'content'));

Future<void> resignOld(
  dynamic f,
  void Function(Map) change, {
  dynamic signingKey,
}) async {
  final proof = await oldProof(f);
  final command =
      CryptoJson.decode(cryptoBase64(proof['commandBase64'])) as Map;
  change(command);
  final replacement = f.runtime.codec.crypto.signDomain(
    Map<String, dynamic>.from(command),
    signingKey ?? f.access.signing.secretKey,
    cryptoDirectoryDomain,
  );
  await f.runtime.database.execute(
    'UPDATE crypto_outbox SET signed_body=?,request_hash=? WHERE request_id=?',
    [
      jsonEncode(replacement),
      await cryptoSha256(cryptoBase64(replacement['commandBase64'])),
      f.old,
    ],
  );
}

Future<void> retained(dynamic f, Object before) async {
  expect(await f.runtime.queue.store.outgoing(f.old), before);
  expect(
    await f.runtime.database.rows(
      "SELECT * FROM crypto_outbox WHERE state='blocked' AND ${cryptoActiveOutboxPredicate()}",
    ),
    hasLength(1),
  );
  expect(
    await f.runtime.database.rows(
      "SELECT * FROM crypto_outbox_attempts WHERE event='checkpoint_superseded_locally'",
    ),
    isEmpty,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'rebound local assertion retires without becoming historical authority',
    () async {
      final f = await reboundCheckpointFixture();
      final proof = await oldProof(f);
      final before = await f.runtime.queue.store.outgoing(f.old);
      final applied = await f.runtime.database.rows(
        "SELECT * FROM crypto_outbox WHERE state='applied'",
      );
      expect(
        f.access.old.member(
          f.runtime.account.directory.accountId,
        )['deviceSnapshotHash'],
        isNot(f.access.verified.deviceSnapshotHash),
      );
      await expectLater(
        f.access.verifyDomainCheckpoint(proof, onlineAuthorDirectory: true),
        throwsA(
          isA<CryptoAuthorityPending>().having(
            (e) => e.reason,
            'reason',
            'history_freshness_pending',
          ),
        ),
      );
      expect(await reconcile(f), 1);
      expect(await f.runtime.queue.store.outgoing(f.old), before);
      expect(
        await f.runtime.database.rows(
          "SELECT * FROM crypto_outbox WHERE state='blocked' AND ${cryptoActiveOutboxPredicate()}",
        ),
        isEmpty,
      );
      expect(
        await f.runtime.database.rows(
          "SELECT * FROM crypto_outbox WHERE state='applied'",
        ),
        applied,
      );
      expect(f.wire.lookups, 1);
      // Retirement is not historical-data acceptance, even after its marker exists.
      await expectLater(
        f.access.verifyDomainCheckpoint(proof, onlineAuthorDirectory: true),
        throwsA(
          isA<CryptoAuthorityPending>().having(
            (e) => e.reason,
            'reason',
            'history_freshness_pending',
          ),
        ),
      );
    },
  );

  for (final mode in [
    'extraPayloadField',
    'negativeRecordCount',
    'badAuthorHash',
    'foreignAccount',
    'badSignature',
    'missingScopeHistory',
    'claimedRecord',
    'terminalReceipt',
    'coverageLostDuringReceipt',
  ]) {
    test('rebound retirement preserves evidence when $mode', () async {
      final f = await reboundCheckpointFixture();
      if (mode == 'extraPayloadField') {
        await resignOld(f, (c) => (c['payload'] as Map)['extra'] = true);
      }
      if (mode == 'negativeRecordCount') {
        await resignOld(f, (c) => (c['payload'] as Map)['recordCount'] = -1);
      }
      if (mode == 'badAuthorHash') {
        await resignOld(
          f,
          (c) => (c['payload'] as Map)['authorDirectoryHeadHash'] = 'bad',
        );
      }
      if (mode == 'foreignAccount') {
        await resignOld(
          f,
          (c) => c['accountId'] = f.runtime.codec.crypto.randomId(),
        );
      }
      if (mode == 'badSignature') {
        final proof = await oldProof(f);
        proof['signatureBase64'] = base64Encode(Uint8List(64));
        await f.runtime.database.execute(
          'UPDATE crypto_outbox SET signed_body=? WHERE request_id=?',
          [jsonEncode(proof), f.old],
        );
      }
      if (mode == 'missingScopeHistory') f.access.historyMissing = true;
      if (mode == 'claimedRecord') {
        await f.runtime.database.execute(
          'INSERT INTO crypto_outbox_records VALUES(?,?,?,?,?,?)',
          [f.runtime.partition, scope, 'content', 'claim', 0, f.old],
        );
      }
      if (mode == 'terminalReceipt') f.wire.outcome = 'applied';
      if (mode == 'coverageLostDuringReceipt') {
        f.wire.afterLookup = () async {
          await f.runtime.database.execute(
            'UPDATE crypto_scope_state SET complete=0',
          );
        };
      }
      final before = await f.runtime.queue.store.outgoing(f.old);
      expect(await reconcile(f), 0);
      await retained(f, before);
    });
  }

  test(
    'original retired device assertion keeps historical signature binding',
    () async {
      final f = await reboundCheckpointFixture();
      final original = f.access.historicalDirectory;
      await resignOld(f, (c) {
        c['deviceId'] = original.devices.single['deviceId'];
        (c['payload'] as Map)['authorDirectoryHeadHash'] = original.headHash;
      }, signingKey: f.access.retiredSigning.secretKey);
      final proof = await oldProof(f);
      final before = await f.runtime.queue.store.outgoing(f.old);
      await expectLater(
        f.access.verifyDomainCheckpoint(proof, onlineAuthorDirectory: true),
        throwsA(
          isA<CryptoAuthorityPending>().having(
            (e) => e.reason,
            'reason',
            'history_freshness_pending',
          ),
        ),
      );
      expect(await reconcile(f), 1);
      expect(await f.runtime.queue.store.outgoing(f.old), before);
      expect(f.wire.lookups, 1);
    },
  );

  test(
    'rebound retirement still requires current replacement freshness',
    () async {
      final f = await reboundCheckpointFixture();
      final store = f.runtime.account.store;
      final account = f.runtime.account.directory.accountId;
      final anchor = Map<String, dynamic>.from(await store.anchor(account));
      anchor['deviceSnapshotHash'] = 'e' * 64;
      await store.secure.write(
        'directory2:${f.runtime.partition}:$account',
        utf8.decode(CryptoJson.encode(anchor)),
      );
      final before = await f.runtime.queue.store.outgoing(f.old);
      await expectLater(
        reconcile(f),
        throwsA(
          isA<CryptoAuthorityPending>().having(
            (e) => e.reason,
            'reason',
            'history_freshness_pending',
          ),
        ),
      );
      expect(f.wire.lookups, 0);
      await retained(f, before);
    },
  );

  test(
    'rebound assertion cannot cite an author directory outside the own chain',
    () async {
      final f = await reboundCheckpointFixture();
      final crypto = f.runtime.codec.crypto;
      final profile = f.runtime.account.directory.session.profile;
      final root = crypto.sodium.crypto.sign.keyPair();
      final rootBox = crypto.sodium.crypto.box.keyPair();
      final deviceBox = crypto.sodium.crypto.box.keyPair();
      addTearDown(root.secretKey.dispose);
      addTearDown(rootBox.secretKey.dispose);
      addTearDown(deviceBox.secretKey.dispose);
      final unrelated = (await AccountDirectoryV2(crypto).prepare(
        previous: null,
        serverId: profile.serverId,
        accountId: profile.accountId,
        deviceId: profile.deviceId,
        identityEpochId: crypto.randomId(),
        operation: 'crypto2.account.initialize',
        signer: 'root',
        pinnedRootFingerprint: crypto.fingerprint(
          root.publicKey,
          rootBox.publicKey,
        ),
        signingKey: root.secretKey,
        payload: {
          'rootSigningKeyBase64': base64Encode(root.publicKey),
          'rootEncryptionKeyBase64': base64Encode(rootBox.publicKey),
          'deviceSigningKeyBase64': base64Encode(f.access.signing.publicKey),
          'deviceEncryptionKeyBase64': base64Encode(deviceBox.publicKey),
          'keyringCiphertextBase64': base64Encode(Uint8List(48)),
        },
      )).result;
      f.access.otherDirectory = unrelated;
      await resignOld(f, (c) {
        (c['payload'] as Map)['authorDirectoryHeadHash'] = unrelated.headHash;
      });
      final before = await f.runtime.queue.store.outgoing(f.old);
      expect(await reconcile(f), 0);
      expect(f.wire.lookups, 0);
      await retained(f, before);
    },
  );
}
