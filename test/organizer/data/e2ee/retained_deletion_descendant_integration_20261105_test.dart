import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/organizer/data/e2ee/account_directory_v2.dart';
import 'package:kanban/organizer/data/e2ee/crypto_business_router.dart';
import 'package:kanban/organizer/data/e2ee/crypto_json.dart';
import 'package:kanban/organizer/data/e2ee/crypto_scope_deletion_codec.dart';

import 'support/deleted_scope_fixture_20261105.dart';

Future<Map<String, dynamic>> _deletionStatus(DeletedScopeFixture f) async {
  final before = f.own;
  final head = f.heads.last;
  final requestId = f.crypto.randomId();
  Future<String> hash(Map value) => cryptoSha256(CryptoJson.encode(value));
  final descriptor = {
    'scopeId': f.scope,
    'headHash': head.headHash,
    'accessRevision': head.accessRevision,
    'lifecycleHash': '1' * 64,
  };
  final certificate = {
    'version': 2,
    'serverId': before.serverId,
    'rootScopeId': f.scope,
    'requestId': requestId,
    'actorAccountId': before.accountId,
    'actorDeviceId': f.account.deviceId,
    'scopes': [descriptor],
    'graphRoot': '2' * 64,
    'graphCount': 1,
    'retention': CryptoScopeDeletionCodec.retention,
  };
  final certificateProof = f.sign(
    certificate,
    CryptoScopeDeletionCodec.certificateDomain,
  );
  final header = <String, dynamic>{
    'version': 2,
    'serverId': before.serverId,
    'requestId': requestId,
    'actorAccountId': before.accountId,
    'actorDeviceId': f.account.deviceId,
    'authorDirectoryHeadHash': before.headHash,
    'privateCertificateHash': await hash(certificateProof),
    'rootToken': await CryptoScopeDeletionCodec.rootToken(certificate),
    'graphRoot': certificate['graphRoot'],
    'graphCount': 1,
    'retention': CryptoScopeDeletionCodec.retention,
    'scopeLeafRoot': '0' * 64,
    'scopeLeafCount': 1,
  };
  final leaf = f.sign({
    'version': 2,
    'serverId': before.serverId,
    'requestId': requestId,
    'headerContextHash': await CryptoScopeDeletionCodec.headerContext(header),
    ...descriptor,
  }, CryptoScopeDeletionCodec.leafDomain);
  final digest = await hash(leaf);
  header['scopeLeafRoot'] = await CryptoScopeDeletionCodec.leafRoot(header, [
    digest,
  ]);
  final headerProof = f.sign(header, CryptoScopeDeletionCodec.headerDomain);
  final event = await f.prepareOwnEvent(
    operation: 'crypto2.account.scopeDeletion',
    requestId: requestId,
    payload: {
      'scopeToken': header['rootToken'],
      'certificateHash': await hash(headerProof),
    },
  );
  return {
    'scopeId': f.scope,
    'certificateHash': await hash(headerProof),
    'headerProof': headerProof,
    'leafProof': leaf,
    'leafDigests': [digest],
    'membershipHead': f.wires[head.headHash],
    'eventAuthorization': event.authorization,
    'eventHeadHash': event.result.headHash,
    'eventCommandHash': await cryptoSha256(
      cryptoBase64(event.authorization['commandBase64']),
    ),
  };
}

Future<String> _protectedSql(DeletedScopeFixture f) async => jsonEncode({
  for (final table in [
    'scopes',
    'crypto_scope_heads',
    'crypto_restore_scoped_directories',
    'crypto_outbox',
    'crypto_export_drafts',
    'local_meta',
  ])
    table: await f.db.rows('SELECT * FROM $table ORDER BY rowid'),
});

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final validEvent in [true, false]) {
    test(
      'retained deletion discovery verifies unseen descendant with valid event=$validEvent',
      () async {
        final f = await deletedScopeFixture();
        final status = await _deletionStatus(f);
        if (!validEvent) status['eventHeadHash'] = 'f' * 64;
        f.directory.responses['crypto2.scopes.catalog'] = {
          'scopes': <Object>[],
          'hasMore': false,
          'nextAfterId': null,
        };
        f.directory.responses['crypto2.scope.deletionStatus'] = status;
        await f.db.execute(
          'INSERT INTO scopes(partition,id,data) VALUES(?,?,?)',
          [
            f.account.store.partition,
            f.scope,
            jsonEncode({
              'id': f.scope,
              'name': 'Retained diagnostic household',
              'deleted': false,
              'revoked': false,
            }),
          ],
        );
        final beforeSql = await _protectedSql(f);
        final beforePins = Map<String, String>.from(f.secureMemory.values);
        final runtime = CryptoBusinessSession(f.account, f.access, f.db);
        final result = await runtime.scopes();
        expect(result['deletedScopeIds'], validEvent ? [f.scope] : isEmpty);
        expect(result['revokedScopeIds'], validEvent ? [f.scope] : isEmpty);
        expect(await _protectedSql(f), beforeSql);
        expect(f.secureMemory.values, beforePins);
        expect(
          f.directory.calls.where((c) => c == 'crypto2.scope.deletionStatus'),
          hasLength(1),
        );
        expect(
          f.directory.calls,
          isNot(
            contains(anyOf('crypto2.scope.delete', 'crypto2.scope.headGet')),
          ),
        );
      },
    );
  }
}
