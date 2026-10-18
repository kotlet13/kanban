import 'dart:convert';
import 'dart:typed_data';

import 'package:sodium/sodium.dart';

import 'account_directory_v2.dart';
import 'crypto_business_router.dart';
import 'crypto_json.dart';
import 'crypto_project_relocation_codec.dart';
import 'crypto_sync_repository.dart';
import 'scope_crypto_codec.dart';
import 'session_crypto_access.dart' show SessionCryptoAccess;

/// Private unpublished target. Even an activated shadow has no ordinary scope
/// capability: final publication is still mandatory before Session admission.
final class PreparedProjectRelocationTarget {
  PreparedProjectRelocationTarget._(
    this.head,
    this.activation,
    this.planHash,
    this._context,
  );
  final VerifiedScopeHead head;
  final Map<String, dynamic> activation;
  final String planHash;
  final CryptoBusinessSession _context;
  bool isFor(SessionCryptoAccess access, String scopeId) =>
      identical(_context.access, access) &&
      head.scopeId == scopeId &&
      head.epoch == 1 &&
      head.body['previousHeadHash'] == cryptoZeroHash &&
      head.body['keyIds']['finance'] != null;

  /// Checks only this unpublished candidate and the current own identity.
  /// It does not admit a normal target head or publish target keys.
  Future<String> requireFinanceTagContext(
    SessionCryptoAccess access,
    String scopeId, {
    String? ownHeadHash,
  }) async {
    if (!isFor(access, scopeId) || !_context.account.directory.isCurrent()) {
      throw const CryptoAuthorityPending('crypto_relocation_identity_changed');
    }
    final own = await _context.account.directory.requireFresh();
    if (!isFor(access, scopeId) ||
        !_context.account.directory.isCurrent() ||
        own.activeDevice(_context.account.deviceId)['keyringWrite'] != true ||
        ownHeadHash != null && own.headHash != ownHeadHash) {
      throw const CryptoAuthorityPending('crypto_relocation_identity_changed');
    }
    return own.headHash;
  }

  Future<SecureKey> key(String domain) async {
    final rows = await _context.database.rows(
      'SELECT key_bytes FROM crypto_scope_keys WHERE partition=? AND scope_id=? AND domain=? AND epoch_id=?',
      [_context.partition, head.scopeId, domain, head.headHash],
    );
    if (rows.length != 1)
      throw const CryptoAuthorityPending('crypto_relocation_key_pending');
    final raw = Uint8List.fromList(
      (rows.single['key_bytes'] as List).cast<int>(),
    );
    try {
      if (await _context.access.codec.keyCommitment(raw) !=
          head.commitment(domain))
        throw const FormatException('crypto_relocation_key_commitment');
      return _context.account.directory.reducer.crypto.sodium.secureCopy(raw);
    } finally {
      raw.fillRange(0, raw.length, 0);
    }
  }
}

typedef RelocationSend =
    Future<Map<String, dynamic>> Function(
      String key,
      String operation,
      Map<String, dynamic> payload,
    );

/// Reuses ordinary head/grant codecs inside the server's private shadow route.
/// Every random envelope and nested request is persisted before transmission.
class CryptoProjectRelocationTarget {
  CryptoProjectRelocationTarget(this.context, this.send);
  final CryptoBusinessSession context;
  final RelocationSend send;
  Map<String, dynamic> _body(Map proof) => Map<String, dynamic>.from(
    CryptoJson.decode(cryptoBase64(proof['commandBase64'])) as Map,
  );
  Future<Map<String, dynamic>> _saved(
    String scope,
    String id,
    Future<Map<String, dynamic>> Function() build,
  ) async {
    final rows = await context.database.rows(
      'SELECT payload FROM crypto_membership_intents WHERE partition=? AND scope_id=? AND intent_id=? AND state=?',
      [context.partition, scope, id, 'projectRelocationPrivate'],
    );
    if (rows.isNotEmpty)
      return Map<String, dynamic>.from(
        CryptoJson.decode(
              Uint8List.fromList((rows.single['payload'] as List).cast<int>()),
            )
            as Map,
      );
    return context.database.transaction(() async {
      final value = await build();
      await context.database.execute(
        'INSERT INTO crypto_membership_intents VALUES(?,?,?,?,?,NULL)',
        [
          context.partition,
          scope,
          id,
          'projectRelocationPrivate',
          CryptoJson.encode(value),
        ],
      );
      return value;
    });
  }

  Future<Map<String, dynamic>> _sign(
    String scope,
    String id,
    Map<String, dynamic> body, {
    String domain = cryptoDirectoryDomain,
  }) => _saved(scope, id, () async {
    final lease = await context.account.signingKey();
    try {
      return context.account.directory.reducer.crypto.signDomain(
        body,
        lease.key,
        domain,
      );
    } finally {
      lease.release();
    }
  });
  Future<Map<String, dynamic>> _command(
    String scope,
    String id,
    String op,
    Map<String, dynamic> payload,
  ) async {
    final own = await context.account.directory.requireFresh();
    final proof = await _sign(scope, id, {
      'version': 2,
      'operation': op,
      'requestId': context.account.directory.reducer.crypto.randomId(),
      'serverId': own.serverId,
      'accountId': own.accountId,
      'deviceId': context.account.deviceId,
      'signer': 'device',
      'payload': payload,
    });
    final old = _body(proof);
    if (old['operation'] != op ||
        base64Encode(CryptoJson.encode(old['payload'])) !=
            base64Encode(CryptoJson.encode(payload)))
      throw const FormatException('crypto_relocation_nested_immutable');
    return proof;
  }

  Future<void> uploadBlob({
    required String actionId,
    required String planHash,
    required Map<String, dynamic> descriptor,
  }) async {
    final scope = descriptor['scopeId'] as String,
        id = descriptor['id'] as String;
    final common = {
      'scopeId': scope,
      'id': id,
      'domain': descriptor['domain'],
      'epoch': descriptor['epoch'],
      'accessRevision': descriptor['accessRevision'],
      'membershipHeadHash': descriptor['membershipHeadHash'],
    };
    Future<Map<String, dynamic>> step(
      String suffix,
      String op,
      Map<String, dynamic> payload,
    ) async {
      final key = 'relocation:$actionId:blob:$id:$suffix';
      final inner = await _command(scope, '$key:inner', op, payload);
      final ack = await send(key, 'crypto2.projectRelocation.blob', {
        'actionId': actionId,
        'planHash': planHash,
        'authorization': inner,
      });
      return Map<String, dynamic>.from(ack['result'] as Map);
    }

    await step('begin', 'crypto2.blob.begin', {
      ...common,
      'size': descriptor['cipherSize'],
      'sha256': descriptor['cipherSha256'],
      'manifestBase64': descriptor['manifestBase64'],
    });
    var offset = 0;
    while (offset < descriptor['cipherSize']) {
      final rows = await context.database.rows(
        'SELECT offset,cipher FROM crypto_document_chunks WHERE partition=? AND id=? AND offset=?',
        [context.partition, id, offset],
      );
      if (rows.length != 1)
        throw const FormatException('crypto_relocation_blob_chunks');
      final bytes = Uint8List.fromList(
        (rows.single['cipher'] as List).cast<int>(),
      );
      final ack = await step('$offset', 'crypto2.blob.chunk', {
        ...common,
        'offset': offset,
        'dataBase64': base64Encode(bytes),
      });
      offset += bytes.length;
      if (ack['offset'] is! int || ack['offset'] < offset)
        throw const FormatException('crypto_relocation_blob_ack');
    }
    final ack = await step('complete', 'crypto2.blob.complete', common);
    if (ack['complete'] != true || ack['offset'] != descriptor['cipherSize'])
      throw const FormatException('crypto_relocation_blob_ack');
  }

  Future<PreparedProjectRelocationTarget> prepare({
    required Map<String, dynamic> planProof,
    required Map<String, dynamic> originProof,
  }) async {
    final plan = _body(planProof), scope = plan['targetScopeId'] as String;
    final action = plan['actionId'] as String;
    final prefix = 'relocation:$action';
    final hash = await CryptoProjectRelocationCodec.proofHash(planProof);
    final own = await context.account.directory.requireFresh();
    final crypto = context.account.directory.reducer.crypto;
    await send('$prefix:origin', 'crypto2.projectRelocation.origin', {
      'actionId': action,
      'planHash': hash,
      'originProof': originProof,
    });
    final preview = await context.account.directory.call(
      'crypto2.projectRelocation.targetPreview',
      {'actionId': action, 'planHash': hash},
    );
    final descriptor = preview['scope'] as Map;
    final lifecycle = Map<String, dynamic>.from(preview['lifecycle'] as Map);
    final source = await context.access.currentHead(
      plan['sourceScopeId'],
      online: true,
    );
    final directories = <String, VerifiedAccountDirectory>{};
    final roster = <Map<String, dynamic>>[];
    for (final previous in source.members) {
      final directory = previous['accountId'] == own.accountId
          ? own
          : await context.access.directoryAt(
              scopeId: source.scopeId,
              scopeHeadHash: source.headHash,
              accountId: previous['accountId'],
              directoryHeadHash: previous['directoryHeadHash'],
              online: true,
            );
      if (directory.deviceSnapshotHash != previous['deviceSnapshotHash'])
        throw const CryptoAuthorityPending('crypto_relocation_roster_changed');
      if (directory.accountId != own.accountId)
        await context.access.identities.requireVerified(
          directory.accountId,
          context.access.identities.fingerprint(directory),
        );
      directories[directory.accountId] = directory;
      roster.add({
        ...previous,
        'financeRole': previous['role'] == 'viewer' ? 'read' : 'write',
        'manageKeys': previous['role'] != 'viewer',
      });
    }
    final draft = await _saved(scope, '$prefix:headDraft', () async {
      final ids = <String, dynamic>{}, commitments = <String, dynamic>{};
      final keys = <String, SecureKey>{};
      try {
        for (final domain in ['content', 'finance']) {
          final key = crypto.sodium.secureRandom(32);
          keys[domain] = key;
          ids[domain] = crypto.randomId();
          final raw = key.extractBytes();
          try {
            commitments[domain] = await context.access.codec.keyCommitment(raw);
          } finally {
            raw.fillRange(0, raw.length, 0);
          }
        }
        final body = <String, dynamic>{
          'scopeId': scope,
          'epoch': 1,
          'initialLifecycleHash': lifecycle['initialLifecycleHash'],
          'previousLifecycleHash': null,
          'financePolicyIntentProof': null,
          'accessIntentProof': null,
          'previousHeadHash': cryptoZeroHash,
          'accessRevision': descriptor['accessRevision'],
          'expectedAccessRevision': descriptor['expectedAccessRevision'],
          'accessBasis': descriptor['accessBasis'],
          'authorDirectoryHeadHash': own.headHash,
          'members': roster,
          'membershipIntents': <Map<String, dynamic>>[],
          'closures': {'content': null, 'finance': null},
          'keyIds': ids,
          'keyCommitments': commitments,
          'financeKeyProposalProof': null,
          'contentKeyProposalProof': null,
        };
        body['financeKeyProposalProof'] =
            await _sign(scope, '$prefix:financeKeyProposal', {
              'version': 2,
              'operation': 'crypto2.scope.financeKeyProposal',
              'serverId': own.serverId,
              'scopeId': scope,
              'epoch': 1,
              'previousHeadHash': cryptoZeroHash,
              'proposalContextHash': await context.access.codec.financeCoreHash(
                body,
              ),
              'keyId': ids['finance'],
              'keyCommitment': commitments['finance'],
              'accountId': own.accountId,
              'deviceId': context.account.deviceId,
              'authorDirectoryHeadHash': own.headHash,
            }, domain: 'JivieE2EE/financeKeyProposal/v2\n');
        context.access.codec.validateBody(body);
        final headHash = await context.access.codec.headHash(body);
        for (final item in keys.entries) {
          final keyContext = {
            'version': 2,
            'purpose': 'pendingScopeKey',
            'scopeId': scope,
            'domain': item.key,
            'keyId': ids[item.key],
            'intentId': action,
            'serverId': own.serverId,
            'accountId': own.accountId,
            'recipientKind': 'recovery',
            'recipientId': own.snapshot['recoveryRootEpochId'],
            'recipientPublicKeyBase64': own.snapshot['rootEncryptionKeyBase64'],
          };
          final sealed = crypto.sealKey(
            key: item.value,
            recipientPublicKey: cryptoBase64(
              own.snapshot['rootEncryptionKeyBase64'],
              length: 32,
            ),
            context: keyContext,
          );
          final recovery =
              await _sign(scope, '$prefix:keyRecovery:${item.key}', {
                'version': 2,
                'operation': 'crypto2.localScopeKeyIntent',
                'serverId': own.serverId,
                'accountId': own.accountId,
                'deviceId': context.account.deviceId,
                'context': keyContext,
                'sealedEnvelopeBase64': sealed,
              }, domain: 'JivieE2EE/localKeyIntent/v2\n');
          final raw = item.value.extractBytes();
          try {
            await context.database.execute(
              'INSERT INTO crypto_scope_keys VALUES(?,?,?,?,?,?,?,?,?,?,?)',
              [
                context.partition,
                scope,
                item.key,
                1,
                headHash,
                ids[item.key],
                raw,
                headHash,
                CryptoJson.encode(recovery),
                0,
                0,
              ],
            );
          } finally {
            raw.fillRange(0, raw.length, 0);
          }
        }
        return {'body': body, 'headHash': headHash};
      } finally {
        for (final key in keys.values) {
          key.dispose();
        }
      }
    });
    final body = Map<String, dynamic>.from(draft['body'] as Map);
    // Persisted proposal references are immutable. Resolve those exact old
    // prefixes; current source/own DS checks remain separate before disclosure.
    directories.clear();
    for (final member in (body['members'] as List).cast<Map>()) {
      final d = await context.access.directoryAt(
        scopeId: source.scopeId,
        scopeHeadHash: source.headHash,
        accountId: member['accountId'],
        directoryHeadHash: member['directoryHeadHash'],
        online: true,
      );
      if (d.deviceSnapshotHash != member['deviceSnapshotHash'])
        throw const FormatException('crypto_relocation_directory');
      directories[d.accountId] = d;
    }
    final author = await context.access.directoryAt(
      scopeId: source.scopeId,
      scopeHeadHash: source.headHash,
      accountId: own.accountId,
      directoryHeadHash: body['authorDirectoryHeadHash'],
      online: true,
    );
    if (author.deviceSnapshotHash != own.deviceSnapshotHash ||
        author.identityEpochId != own.identityEpochId ||
        author.rootFingerprint != own.rootFingerprint)
      throw const CryptoAuthorityPending('crypto_relocation_identity_changed');
    final prepared = await context.access.prepareProjectRelocationGenesis(
      planProof: planProof,
      originProof: originProof,
      proposal: body,
    );
    final proposal = await _command(
      scope,
      '$prefix:headPut',
      'crypto2.scope.headPut',
      body,
    );
    Future<VerifiedAccountDirectory> directoryAtHead(
      String id,
      String ref,
    ) async {
      final member = (body['members'] as List).cast<Map>().singleWhere(
        (m) => m['accountId'] == id,
      );
      final cached = directories[id];
      final d = cached?.headHash == ref
          ? cached!
          : await context.access.directoryAt(
              scopeId: source.scopeId,
              scopeHeadHash: source.headHash,
              accountId: id,
              directoryHeadHash: ref,
              online: true,
            );
      if (d.deviceSnapshotHash != member['deviceSnapshotHash'] ||
          const [
            'rootSigningKeyBase64',
            'rootEncryptionKeyBase64',
            'identityEpochId',
            'recoveryRootEpochId',
          ].any((k) => d.snapshot[k] != member[k])) {
        throw const FormatException('crypto_relocation_directory');
      }
      return d;
    }

    final pending = await context.access.codec.verifyProposal(
      serverId: own.serverId,
      authorization: proposal,
      previous: null,
      authorDirectory: author,
      directoryAtHead: directoryAtHead,
      checkIdentity: (id, fp) async {
        if (id != own.accountId)
          await context.access.identities.requireVerified(id, fp);
      },
      expectedProjectRelocation: prepared,
    );
    await send(
      '$prefix:headPutOuter',
      'crypto2.projectRelocation.targetCommand',
      {'actionId': action, 'planHash': hash, 'authorization': proposal},
    );
    final domainDescriptors = <String, List<Map<String, dynamic>>>{
      'content': [],
      'finance': [],
    };
    final target = PreparedProjectRelocationTarget._(
      pending,
      {},
      hash,
      context,
    );
    for (final domain in ['content', 'finance']) {
      final key = await target.key(domain);
      try {
        for (final member in pending.members) {
          final directory = directories[member['accountId']]!;
          final recipients = <Map<String, dynamic>>[
            {
              'recipientKind': 'recovery',
              'recipientId': member['recoveryRootEpochId'],
              'publicKeyBase64': member['rootEncryptionKeyBase64'],
            },
            for (final device in directory.devices.where(
              (d) =>
                  d['revokedGeneration'] == null &&
                  d['identityEpochId'] == directory.identityEpochId,
            ))
              {
                'recipientKind': 'device',
                'recipientId': device['deviceId'],
                'publicKeyBase64': device['encryptionKeyBase64'],
              },
          ];
          recipients.sort((a, b) {
            final c = (a['recipientKind'] as String).compareTo(
              b['recipientKind'],
            );
            return c != 0
                ? c
                : (a['recipientId'] as String).compareTo(b['recipientId']);
          });
          var generation = 0;
          final hashes = <String>[];
          for (var offset = 0; offset < recipients.length; offset += 32) {
            final id = '$prefix:grants:$domain:${member['accountId']}:$offset';
            final inner = await _saved(scope, id, () async {
              final chunk = recipients
                  .skip(offset)
                  .take(32)
                  .map(
                    (r) => {
                      ...r,
                      'sealedEnvelopeBase64': crypto.sealKey(
                        key: key,
                        recipientPublicKey: cryptoBase64(
                          r['publicKeyBase64'],
                          length: 32,
                        ),
                        context: context.access.codec.wrapperContext(
                          serverId: own.serverId,
                          head: pending,
                          keySourceHead: pending,
                          domain: domain,
                          keyId: body['keyIds'][domain],
                          recipient: {
                            ...r,
                            'recoveryRootEpochId':
                                member['recoveryRootEpochId'],
                          },
                        ),
                      ),
                    },
                  )
                  .toList();
              return _command(scope, '$id:proof', 'crypto2.grants.put', {
                'scopeId': scope,
                'headHash': pending.headHash,
                'keySourceHeadHash': pending.headHash,
                'accountId': member['accountId'],
                'domain': domain,
                'epoch': 1,
                'keyId': body['keyIds'][domain],
                'expectedGeneration': generation,
                'recipients': chunk,
              });
            });
            final ack = await send(
              '$id:outer',
              'crypto2.projectRelocation.targetCommand',
              {'actionId': action, 'planHash': hash, 'authorization': inner},
            );
            final result = ack['result'] as Map;
            final proofHash = await CryptoProjectRelocationCodec.proofHash(
              inner,
            );
            hashes.addAll(
              List.filled(
                (_body(inner)['payload']['recipients'] as List).length,
                proofHash,
              ),
            );
            generation = result['generation'];
          }
          domainDescriptors[domain]!.add({
            'accountId': member['accountId'],
            'epoch': 1,
            'keyId': body['keyIds'][domain],
            'keySourceHeadHash': pending.headHash,
            'generation': generation,
            'recipientProofHashes': hashes,
          });
        }
      } finally {
        key.dispose();
      }
    }
    final roots = <String, dynamic>{};
    for (final domain in ['content', 'finance']) {
      domainDescriptors[domain]!.sort(
        (a, b) => (a['accountId'] as String).compareTo(b['accountId']),
      );
      roots[domain] = await cryptoSha256([
        for (final item in domainDescriptors[domain]!) ...[
          ...CryptoJson.encode(item),
          10,
        ],
      ]);
    }
    final manifestHash = await cryptoSha256(CryptoJson.encode(roots));
    final current = await context.account.directory.call(
      'crypto2.projectRelocation.targetPreview',
      {'actionId': action, 'planHash': hash},
    );
    if (current['grantManifestHash'] != manifestHash ||
        base64Encode(CryptoJson.encode(current['grantManifest'])) !=
            base64Encode(CryptoJson.encode(roots)))
      throw const FormatException('crypto_relocation_grant_manifest');
    final financeProof = await _sign(scope, '$prefix:financeManifest', {
      'version': 2,
      'operation': 'crypto2.scope.financeGrantManifest',
      'serverId': own.serverId,
      'scopeId': scope,
      'headHash': pending.headHash,
      'financeManifestHash': roots['finance'],
      'accountId': own.accountId,
      'deviceId': context.account.deviceId,
      'authorDirectoryHeadHash': author.headHash,
    }, domain: 'JivieE2EE/financeGrantManifest/v2\n');
    final activation =
        await _command(scope, '$prefix:activate', 'crypto2.scope.activate', {
          'scopeId': scope,
          'headHash': pending.headHash,
          'grantManifestHash': manifestHash,
          'authorDirectoryHeadHash': author.headHash,
          'financeGrantManifestProof': financeProof,
          'projectRelocation': prepared.activationContext,
        });
    final active = await context.access.codec.verifyActivation(
      pending: pending,
      previous: null,
      authorization: activation,
      authorDirectory: author,
      grantManifestHash: manifestHash,
      directoryAtHead: directoryAtHead,
      expectedProjectRelocation: prepared,
    );
    await send(
      '$prefix:activateOuter',
      'crypto2.projectRelocation.targetActivation',
      {'actionId': action, 'planHash': hash, 'authorization': activation},
    );
    return PreparedProjectRelocationTarget._(active, activation, hash, context);
  }
}
