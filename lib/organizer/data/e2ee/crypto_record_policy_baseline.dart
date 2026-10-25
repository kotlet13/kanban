part of 'crypto_business_router.dart';

class _CryptoRecordPolicyBaselineRejected implements Exception {
  const _CryptoRecordPolicyBaselineRejected(this.code);
  final String code;
}

/// Owner-signed adoption of existing verified records. The journal retains
/// original ciphertext sidecars and exact transport requests across restarts.
/// Status/discovery never supplies creator or write authority by itself.
class CryptoRecordPolicyBaseline {
  CryptoRecordPolicyBaseline(this.business);
  final CryptoBusinessSession business;
  static final _running = <String, Future<void>>{};
  static final _bootstrapZone = Object();
  final _statuses = <String, Future<Map<String, dynamic>>>{};
  Future<bool>? _supported;
  final _active = <String, bool>{};
  String get _partition => business.p;
  String get _server => business.account.directory.session.profile.serverId;
  CryptoCodec get _crypto => business.account.directory.reducer.crypto;

  Future<bool> supported() => _supported ??= () async {
    final directory = business.account.directory;
    final caps = await CryptoCapabilityDiscovery.read(
      transport: directory.transport,
      session: directory.session,
    );
    _current();
    if (caps['serverId'] != _server) {
      throw const FormatException('record_policy_server');
    }
    return (caps['recordPolicyVersions'] as List? ?? const []).contains(1);
  }();

  void _current() {
    if (!business.account.directory.isCurrent()) {
      throw const CryptoAuthorityPending('crypto_stale_identity');
    }
  }

  Future<Map<String, dynamic>> _call(
    String operation,
    Map<String, dynamic> payload,
  ) async {
    _current();
    final value = await business.account.directory.call(operation, payload);
    _current();
    return value;
  }

  void _identity(Map<String, dynamic> value, String scope) {
    final profile = business.account.directory.session.profile;
    if (value['version'] != 1 ||
        value['serverId'] != _server ||
        value['accountId'] != profile.accountId ||
        value['deviceId'] != profile.deviceId ||
        value['scopeId'] != scope ||
        value['active'] is! bool) {
      throw const FormatException('record_policy_status_binding');
    }
  }

  Future<Map<String, dynamic>> _status(String scope) =>
      _statuses.putIfAbsent(scope, () async {
        final result = await _call('crypto2.scope.recordPolicy.status', {
          'scopeId': scope,
        });
        _identity(result, scope);
        return result;
      });

  Future<bool> active(String scope) async {
    if (!await supported()) return false;
    if (_active.containsKey(scope)) return _active[scope]!;
    final status = await _status(scope);
    if (status['active'] != true) return _active[scope] = false;
    final evidence = await _call('crypto2.scope.recordPolicy.baseline', {
      'scopeId': scope,
      'baselineId': status['baselineId'],
      'limit': 1,
    });
    await _verifyHeaders(evidence, scope, expected: status);
    return _active[scope] = true;
  }

  /// Pending exact old operations drain with their existing contract before
  /// activation. They are never rewritten into policy-bearing operations.
  Future<bool> hasPendingWork(String scope) async {
    final rows = await business.db.rows(
      "SELECT 1 FROM outbox WHERE partition=? AND scope_id=? AND state IN ('pending','blocked') "
      "UNION ALL SELECT 1 FROM finance_outbox WHERE partition=? AND scope_id=? AND state IN ('pending','blocked') "
      "UNION ALL SELECT 1 FROM crypto_outbox o JOIN crypto_outbox_records r ON r.partition=o.partition AND r.request_id=o.request_id WHERE o.partition=? AND r.scope_id=? AND o.state IN ('pending','blocked') "
      "UNION ALL SELECT 1 FROM linked_payment_intents WHERE json_extract(data,'\$.partition')=? AND state IN ('pending','waiting_source_publication') AND "
      "(json_extract(data,'\$.source.space.id')=? OR json_extract(data,'\$.sourceScopeId')=? OR json_extract(data,'\$.source.space.id') IS NULL) LIMIT 1",
      [
        _partition,
        scope,
        _partition,
        scope,
        _partition,
        scope,
        _partition,
        scope,
        scope,
      ],
    );
    _current();
    if (rows.isNotEmpty) return true;
    final membership = await business.db.rows(
      "SELECT 1 FROM crypto_membership_intents WHERE partition=? AND scope_id=? AND state='pending' AND authorization IS NOT NULL LIMIT 1",
      [_partition, scope],
    );
    if (membership.isNotEmpty) return true;
    final commands = await business.db.rows(
      "SELECT operation,signed_body FROM crypto_outbox WHERE partition=? AND state IN ('pending','blocked') AND operation!='crypto2.records.batch' AND operation NOT LIKE 'crypto2.scope.recordPolicy.%' ORDER BY sequence LIMIT 32",
      [_partition],
    );
    for (final command in commands) {
      final signed = jsonDecode(command['signed_body'] as String) as Map;
      final body =
          CryptoJson.decode(cryptoBase64(signed['commandBase64'])) as Map;
      final payload = body['payload'];
      if ((command['operation'] as String).startsWith('crypto2.account.') ||
          payload is Map && payload['scopeId'] == scope) {
        return true;
      }
    }
    return false;
  }

  Future<void> ensure(String scope) async {
    if (!await supported() || await active(scope)) return;
    final key = '$_partition:$scope';
    // A nested derivation may finish its pre-activation intent while the owner
    // obtains a verified snapshot. An unrelated caller joins the original run.
    if (Zone.current[_bootstrapZone] == key) return;
    final prior = _running[key];
    if (prior != null) return prior;
    final done = Completer<void>();
    _running[key] = done.future;
    () async {
      try {
        await runZoned(() => _ensure(scope), zoneValues: {_bootstrapZone: key});
        done.complete();
      } catch (error, stack) {
        if (error is _CryptoRecordPolicyBaselineRejected &&
            const {
              'crypto_record_policy_baseline_changed',
              'crypto_record_policy_baseline_immutable',
              'crypto_record_policy_already_active',
            }.contains(error.code)) {
          try {
            await _archiveRejected(scope, error.code);
            done.completeError(
              const CryptoAuthorityPending(
                'crypto_record_policy_baseline_retry',
              ),
              stack,
            );
          } catch (archiveError, archiveStack) {
            done.completeError(archiveError, archiveStack);
          }
        } else {
          done.completeError(error, stack);
        }
      } finally {
        _running.remove(key);
      }
    }();
    return done.future;
  }

  Future<void> _ensure(String scope) async {
    final head = await business.access.currentHead(scope, online: true);
    if (!await business.access.isRecordOwner(
      scope,
      business.account.directory.accountId,
      head: head,
    )) {
      throw const CryptoAuthorityPending('crypto_record_policy_owner_pending');
    }
    if (await hasPendingWork(scope)) return;
    final profile = business.account.directory.session.profile;
    final markers = await business.db.rows(
      'SELECT value FROM local_meta WHERE name=?',
      ['record_policy_new_scope_v1:$_partition:$scope'],
    );
    final marker = markers.isEmpty
        ? null
        : jsonDecode(markers.single['value'] as String) as Map;
    if (marker == null ||
        marker['version'] != 1 ||
        marker['serverId'] != _server ||
        marker['scopeId'] != scope ||
        marker['accountId'] != profile.accountId ||
        marker['deviceId'] != profile.deviceId ||
        marker['originProofHash'] is! String ||
        !RegExp(
          r'^[a-f0-9]{64}$',
        ).hasMatch(marker['originProofHash'] as String) ||
        head.epoch != 1 ||
        head.members.length != 1 ||
        head.members.single['role'] != 'owner' ||
        head.members.single['accountId'] != profile.accountId) {
      throw const CryptoAuthorityPending(
        'crypto_record_policy_existing_scope_upgrade_pending',
      );
    }
    // Existing scopes remain on their original contract until receipt-bound
    // successor reauthorization also covers other devices' old exact requests.
    // Local queue emptiness cannot establish that account-wide condition.
    final existing = await business.db.rows(
      'SELECT type FROM crypto_business_records WHERE partition=? AND scope_id=?',
      [_partition, scope],
    );
    if (existing.any(
      (r) => CryptoRecordPolicy.businessTypes.contains(r['type']),
    )) {
      throw const CryptoAuthorityPending(
        'crypto_record_policy_existing_scope_upgrade_pending',
      );
    }
    final journalKey = 'record_policy_baseline_v1:$_partition:$scope';
    final saved = await business.db.rows(
      'SELECT value FROM local_meta WHERE name=?',
      [journalKey],
    );
    late Map<String, dynamic> journal;
    if (saved.isNotEmpty) {
      journal = Map<String, dynamic>.from(
        jsonDecode(saved.single['value'] as String) as Map,
      );
      if (journal['serverId'] != _server ||
          journal['scopeId'] != scope ||
          journal['accountId'] != business.account.directory.accountId) {
        throw const FormatException('record_policy_journal_binding');
      }
    } else {
      await business.queue.deliver();
      if (await hasPendingWork(scope)) return;
      final domains = [
        'content',
        if ((head.body['keyIds'] as Map)['finance'] != null) 'finance',
      ];
      for (final domain in domains) {
        await business.pullVerified(scope, domain);
      }
      if (await hasPendingWork(scope)) return;
      final current = await business.access.currentHead(scope, online: true);
      if (current.headHash != head.headHash ||
          current.accessRevision != head.accessRevision) {
        throw const CryptoAuthorityPending(
          'crypto_record_policy_baseline_changed',
        );
      }
      final positions = await business.db.rows(
        'SELECT domain,transport_cursor,complete FROM crypto_scope_state WHERE partition=? AND scope_id=? ORDER BY domain',
        [_partition, scope],
      );
      final sequences = <String, int>{
        if (!domains.contains('finance')) 'finance': 0,
      };
      for (final domain in domains) {
        final rows = positions.where((r) => r['domain'] == domain).toList();
        if (rows.length != 1 ||
            rows.single['complete'] != 1 ||
            rows.single['transport_cursor'] is! int) {
          throw const CryptoAuthorityPending(
            'crypto_record_policy_inventory_pending',
          );
        }
        sequences[domain] = rows.single['transport_cursor'] as int;
      }
      final snapshot = await business.db.rows(
        'SELECT * FROM crypto_business_records WHERE partition=? AND scope_id=? ORDER BY id',
        [_partition, scope],
      );
      if (!domains.contains('finance') &&
          snapshot.any((r) => r['domain'] == 'finance')) {
        throw const FormatException('record_policy_absent_finance_domain');
      }
      final entries = <Map<String, dynamic>>[];
      for (final row in snapshot) {
        entries.add(await _prepareEntry(scope, head, row));
      }
      journal = {
        'version': 1,
        'serverId': _server,
        'accountId': business.account.directory.accountId,
        'scopeId': scope,
        'baselineId': _crypto.randomId(),
        'membershipHeadHash': head.headHash,
        'accessRevision': head.accessRevision,
        'expectedContentSequence': sequences['content'],
        'expectedFinanceSequence': sequences['finance'],
        'records': entries,
        'baselineCount': entries.length,
        'baselineRoot': await root(entries),
      };
      final retry = await business.db.rows(
        'SELECT value FROM local_meta WHERE name=?',
        ['record_policy_baseline_retry:$_partition:$scope'],
      );
      if (retry.isNotEmpty) {
        final prior = jsonDecode(retry.single['value'] as String) as Map;
        if (prior['head'] == head.headHash &&
            prior['content'] == sequences['content'] &&
            prior['finance'] == sequences['finance'] &&
            (prior['attempts'] as int) >= 3) {
          throw const CryptoAuthorityPending(
            'crypto_record_policy_baseline_retry_exhausted',
          );
        }
      }
      await business.db.transaction(() async {
        _current();
        final now = await business.db.rows(
          'SELECT domain,transport_cursor,complete FROM crypto_scope_state WHERE partition=? AND scope_id=? ORDER BY domain',
          [_partition, scope],
        );
        final records = await business.db.rows(
          'SELECT id,record_proof_hash FROM crypto_business_records WHERE partition=? AND scope_id=? ORDER BY id',
          [_partition, scope],
        );
        if (CryptoBusinessJson.canonical(now) !=
                CryptoBusinessJson.canonical(positions) ||
            CryptoBusinessJson.canonical(records) !=
                CryptoBusinessJson.canonical([
                  for (final r in snapshot)
                    {
                      'id': r['id'],
                      'record_proof_hash': r['record_proof_hash'],
                    },
                ])) {
          throw const CryptoAuthorityPending(
            'crypto_record_policy_baseline_changed',
          );
        }
        await business.db.execute(
          'INSERT INTO local_meta(name,value) VALUES(?,?)',
          [journalKey, jsonEncode(journal)],
        );
      });
    }
    final common = <String, dynamic>{
      for (final key in [
        'baselineId',
        'scopeId',
        'membershipHeadHash',
        'accessRevision',
      ])
        key: journal[key],
    };
    await _command(
      '${journal['baselineId']}:prepare',
      'crypto2.scope.recordPolicy.prepare',
      {
        ...common,
        'policyVersion': 1,
        'expectedContentSequence': journal['expectedContentSequence'],
        'expectedFinanceSequence': journal['expectedFinanceSequence'],
      },
    );
    final entries = (journal['records'] as List)
        .map((r) => Map<String, dynamic>.from(r as Map))
        .toList();
    for (final domain in ['content', 'finance']) {
      final selected = entries.where((r) => r['domain'] == domain).toList();
      for (var offset = 0; offset < selected.length; offset += 32) {
        await _command(
          '${journal['baselineId']}:$domain:$offset',
          'crypto2.scope.recordPolicy.stage',
          {
            ...common,
            'records': selected.sublist(
              offset,
              offset + 32 < selected.length ? offset + 32 : selected.length,
            ),
          },
        );
      }
    }
    await _command(
      '${journal['baselineId']}:activate',
      'crypto2.scope.recordPolicy.activate',
      {
        ...common,
        'policyVersion': 1,
        'baselineCount': journal['baselineCount'],
        'baselineRoot': journal['baselineRoot'],
      },
    );
    _statuses.remove(scope);
    _active.remove(scope);
    if (!await active(scope)) {
      throw const CryptoAuthorityPending(
        'crypto_record_policy_activation_pending',
      );
    }
  }

  Future<void> _command(
    String action,
    String operation,
    Map<String, dynamic> payload,
  ) async {
    final request = await business.queue.enqueueCommand(
      actionKey: 'record-policy:$action',
      operation: operation,
      payload: payload,
    );
    // CryptoSyncRepository looks up the exact receipt before it asks for fresh
    // authority or sends the saved bytes; a lost ACK cannot restage a new key.
    await business.queue.deliver();
    final row = await CryptoSyncStore(
      business.db,
      _partition,
    ).outgoing(request);
    if (row == null || row['state'] == 'pending' || row['state'] == 'blocked') {
      throw const CryptoAuthorityPending(
        'crypto_record_policy_delivery_pending',
      );
    }
    final receipt = jsonDecode(row['response'] as String) as Map;
    if (receipt['requestId'] != row['request_id'] ||
        receipt['requestHash'] != row['request_hash'] ||
        CryptoBusinessJson.canonical(receipt['authorization']) !=
            CryptoBusinessJson.canonical(
              jsonDecode(row['signed_body'] as String),
            )) {
      throw const FormatException('record_policy_exact_receipt');
    }
    if (row['state'] != 'applied') {
      final response = receipt['response'];
      if (response is Map &&
          response['errorCode'] is String &&
          receipt['status'] is int &&
          receipt['status'] != 200) {
        throw _CryptoRecordPolicyBaselineRejected(
          response['errorCode'] as String,
        );
      }
      throw const CryptoAuthorityPending(
        'crypto_record_policy_baseline_rejected',
      );
    }
    if (receipt['status'] != 200 ||
        receipt['response'] is! Map ||
        receipt['response']['scopeId'] != payload['scopeId'] ||
        receipt['response']['baselineId'] != payload['baselineId']) {
      throw const FormatException('record_policy_receipt_binding');
    }
  }

  Future<void> _archiveRejected(String scope, String reason) async {
    final key = 'record_policy_baseline_v1:$_partition:$scope';
    await business.db.transaction(() async {
      _current();
      final saved = await business.db.rows(
        'SELECT value FROM local_meta WHERE name=?',
        [key],
      );
      if (saved.isEmpty) return;
      final journal = jsonDecode(saved.single['value'] as String) as Map;
      final id = journal['baselineId'] as String;
      final pending = await business.db.rows(
        "SELECT 1 FROM crypto_command_keys k JOIN crypto_outbox o ON o.partition=k.partition AND o.request_id=k.request_id WHERE k.partition=? AND k.action_key LIKE ? AND o.state IN ('pending','blocked') LIMIT 1",
        [_partition, 'record-policy:$id:%'],
      );
      if (pending.isNotEmpty) {
        throw const CryptoAuthorityPending(
          'crypto_record_policy_delivery_pending',
        );
      }
      await business.db.execute(
        'INSERT INTO local_meta(name,value) VALUES(?,?) ON CONFLICT(name) DO NOTHING',
        [
          'record_policy_baseline_archive:$_partition:$scope:$id',
          jsonEncode({'reason': reason, 'journal': journal}),
        ],
      );
      final retryKey = 'record_policy_baseline_retry:$_partition:$scope';
      final prior = await business.db.rows(
        'SELECT value FROM local_meta WHERE name=?',
        [retryKey],
      );
      var attempts = 0;
      if (prior.isNotEmpty) {
        final value = jsonDecode(prior.single['value'] as String) as Map;
        if (value['head'] == journal['membershipHeadHash'] &&
            value['content'] == journal['expectedContentSequence'] &&
            value['finance'] == journal['expectedFinanceSequence']) {
          attempts = value['attempts'] as int;
        }
      }
      await business.db.execute(
        'INSERT INTO local_meta(name,value) VALUES(?,?) ON CONFLICT(name) DO UPDATE SET value=excluded.value',
        [
          retryKey,
          jsonEncode({
            'head': journal['membershipHeadHash'],
            'content': journal['expectedContentSequence'],
            'finance': journal['expectedFinanceSequence'],
            'attempts': attempts + 1,
          }),
        ],
      );
      await business.db.execute(
        'DELETE FROM local_meta WHERE name=? AND value=?',
        [key, saved.single['value']],
      );
    });
    _statuses.remove(scope);
    _active.remove(scope);
  }

  Future<Map<String, dynamic>> _prepareEntry(
    String scope,
    VerifiedScopeHead head,
    Map<String, dynamic> row,
  ) async {
    final domain = row['domain'] as String,
        type = row['type'] as String,
        id = row['id'] as String;
    final projection = Map<String, dynamic>.from(
      jsonDecode(row['projection'] as String) as Map,
    );
    String? creator;
    if (CryptoRecordPolicy.businessTypes.contains(type)) {
      if (!const {
            'verifiedCreation',
            'verifiedSource',
          }.contains(projection['creatorProvenance']) ||
          !projection.containsKey('createdByAccountId')) {
        throw const CryptoAuthorityPending(
          'crypto_record_creator_provenance_pending',
        );
      }
      creator = CryptoRecordAuthorship.account(
        projection['createdByAccountId'],
      );
    }
    final raw = row['raw_payload'] == null
        ? <String, dynamic>{}
        : Map<String, dynamic>.from(
            jsonDecode(row['raw_payload'] as String) as Map,
          );
    final key = raw.containsKey(CryptoRecordPolicy.secretField)
        ? CryptoRecordPolicy.secret(raw)
        : _crypto.sodium.randombytes.buf(32);
    final lease = await business.access.getScopeKey(scope, domain, head.epoch);
    Uint8List? plaintext;
    try {
      final policy = await CryptoRecordPolicy.prepare(
        serverId: _server,
        scopeId: scope,
        domain: domain,
        wireId: id,
        type: type,
        creator: creator,
        operation: row['deleted'] == 1 ? 'delete' : 'edit',
        payload: CryptoRecordPolicy.attachSecret(raw, key),
        deleted: row['deleted'] == 1,
      );
      final context = _context(
        scope,
        domain,
        id,
        type,
        row['record_proof_hash'] as String,
        creator,
        head.headHash,
        head.accessRevision,
      );
      plaintext = CryptoJson.encode({
        'version': 1,
        'keyBase64': base64Encode(key),
      });
      final envelope = _crypto.encrypt(
        plaintext: plaintext,
        key: lease.key,
        context: context,
      );
      return {
        'id': id,
        'domain': domain,
        'type': type,
        'recordProofHash': row['record_proof_hash'],
        'createdByAccountId': creator,
        'fieldCommitments': policy['fieldCommitments'],
        'policyEnvelopeBase64': base64Encode(CryptoJson.encode(envelope)),
      };
    } finally {
      key.fillRange(0, key.length, 0);
      plaintext?.fillRange(0, plaintext.length, 0);
      lease.release();
    }
  }

  Map<String, dynamic> _context(
    String scope,
    String domain,
    String id,
    String type,
    String proof,
    String? creator,
    String head,
    int access,
  ) => {
    'version': 1,
    'purpose': 'recordPolicyBaseline',
    'serverId': _server,
    'scopeId': scope,
    'domain': domain,
    'id': id,
    'type': type,
    'recordProofHash': proof,
    'createdByAccountId': creator,
    'membershipHeadHash': head,
    'accessRevision': access,
  };

  static Future<String> root(List<Map<String, dynamic>> entries) async {
    final sorted = List<Map<String, dynamic>>.of(entries)
      ..sort((a, b) => (a['id'] as String).compareTo(b['id'] as String));
    if (sorted.map((r) => r['id']).toSet().length != sorted.length) {
      throw const FormatException('record_policy_duplicate');
    }
    final leaves = <String>[];
    for (final entry in sorted) {
      leaves.add(
        await cryptoSha256([
          ...utf8.encode('JivieRecordPolicyBaselineLeaf/v1\n'),
          ...CryptoJson.encode(entry),
        ]),
      );
    }
    return cryptoSha256(
      utf8.encode(
        'JivieRecordPolicyBaseline/v1\n${leaves.map((h) => '$h\n').join()}',
      ),
    );
  }

  Future<Map<String, dynamic>> _authorization(
    Map<String, dynamic> proof,
    String operation,
    String scope,
    String baseline,
    String hash,
    int access,
  ) async {
    final raw = CryptoJson.decode(cryptoBase64(proof['commandBase64'])) as Map;
    if (raw.length != 8 ||
        raw['version'] != 2 ||
        raw['operation'] != operation ||
        raw['serverId'] != _server ||
        raw['signer'] != 'device' ||
        raw['payload'] is! Map) {
      throw const FormatException('record_policy_authorization');
    }
    final payload = Map<String, dynamic>.from(raw['payload'] as Map);
    if (payload['scopeId'] != scope ||
        payload['baselineId'] != baseline ||
        payload['membershipHeadHash'] != hash ||
        payload['accessRevision'] != access) {
      throw const FormatException('record_policy_authorization_binding');
    }
    final head = await business.access.headAt(scope, hash);
    if (head.accessRevision != access ||
        !await business.access.isRecordOwner(
          scope,
          raw['accountId'] as String,
          head: head,
        )) {
      throw const CryptoAuthorityPending(
        'crypto_record_policy_owner_evidence_pending',
      );
    }
    final members = head.members
        .where((m) => m['accountId'] == raw['accountId'])
        .toList();
    if (members.length != 1) {
      throw const CryptoAuthorityPending(
        'crypto_record_policy_owner_directory_pending',
      );
    }
    final directory = await business.access.directoryAt(
      scopeId: scope,
      scopeHeadHash: hash,
      accountId: raw['accountId'] as String,
      directoryHeadHash: members.single['directoryHeadHash'] as String,
    );
    _crypto.verifyDomain(
      proof,
      cryptoBase64(
        directory.activeDevice(raw['deviceId'])['signingKeyBase64'],
        length: 32,
      ),
      cryptoDirectoryDomain,
    );
    _current();
    return payload;
  }

  Future<void> _verifyHeaders(
    Map<String, dynamic> page,
    String scope, {
    Map<String, dynamic>? expected,
  }) async {
    _identity(page, scope);
    final baseline = page['baselineId'],
        head = page['membershipHeadHash'],
        access = page['accessRevision'];
    if (page['active'] != true ||
        page['activeBaselineId'] != baseline ||
        page['policyVersion'] != 1 ||
        baseline is! String ||
        head is! String ||
        access is! int ||
        page['prepareAuthorization'] is! Map ||
        page['activationAuthorization'] is! Map ||
        page['baselineCount'] is! int ||
        (page['baselineCount'] as int) < 0 ||
        page['baselineRoot'] is! String ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(page['baselineRoot'] as String) ||
        page['records'] is! List ||
        page['hasMore'] is! bool) {
      throw const FormatException('record_policy_baseline_binding');
    }
    if (expected != null)
      for (final key in [
        'baselineId',
        'membershipHeadHash',
        'accessRevision',
        'baselineRoot',
        'baselineCount',
        'expectedContentSequence',
        'expectedFinanceSequence',
      ]) {
        if (page[key] != expected[key]) {
          throw const FormatException('record_policy_baseline_substitution');
        }
      }
    final prepared = await _authorization(
      Map<String, dynamic>.from(page['prepareAuthorization'] as Map),
      'crypto2.scope.recordPolicy.prepare',
      scope,
      baseline,
      head,
      access,
    );
    final activated = await _authorization(
      Map<String, dynamic>.from(page['activationAuthorization'] as Map),
      'crypto2.scope.recordPolicy.activate',
      scope,
      baseline,
      head,
      access,
    );
    if (prepared['policyVersion'] != 1 ||
        prepared['expectedContentSequence'] !=
            page['expectedContentSequence'] ||
        prepared['expectedFinanceSequence'] !=
            page['expectedFinanceSequence'] ||
        activated['policyVersion'] != 1 ||
        activated['baselineCount'] != page['baselineCount'] ||
        activated['baselineRoot'] != page['baselineRoot']) {
      throw const FormatException('record_policy_activation_binding');
    }
  }

  /// Caller recomputes field commitments against verified plaintext and must
  /// zero the returned key after use. No decrypted secret is cached here.
  Future<({Map<String, dynamic> policy, Uint8List key})?> record({
    required String scopeId,
    required String domain,
    required String id,
    required String recordProofHash,
  }) async {
    if (!await active(scopeId)) return null;
    final status = await _status(scopeId);
    final page = await _call('crypto2.scope.recordPolicy.baseline', {
      'scopeId': scopeId,
      'baselineId': status['baselineId'],
      'recordId': id,
    });
    await _verifyHeaders(page, scopeId, expected: status);
    final records = page['records'] as List;
    if (records.isEmpty) return null;
    if (records.length != 1) {
      throw const FormatException('record_policy_target_binding');
    }
    final item = records.single as Map,
        entry = Map<String, dynamic>.from(item['entry'] as Map);
    if (entry.length != 7 ||
        !entry.keys.every(
          const {
            'id',
            'domain',
            'type',
            'recordProofHash',
            'createdByAccountId',
            'fieldCommitments',
            'policyEnvelopeBase64',
          }.contains,
        ) ||
        entry['id'] != id ||
        entry['domain'] != domain ||
        entry['recordProofHash'] != recordProofHash ||
        entry['type'] is! String ||
        (entry['createdByAccountId'] != null &&
            !isCryptoCanonicalUuid(entry['createdByAccountId'])) ||
        entry['policyEnvelopeBase64'] is! String) {
      throw const FormatException('record_policy_record_binding');
    }
    final type = entry['type'] as String;
    final policy = <String, dynamic>{
      'version': 1,
      'createdByAccountId': entry['createdByAccountId'],
      'operation': 'edit',
      'fieldCommitments': entry['fieldCommitments'],
    };
    CryptoRecordPolicy.validate(policy);
    final payload = await _authorization(
      Map<String, dynamic>.from(item['stageAuthorization'] as Map),
      'crypto2.scope.recordPolicy.stage',
      scopeId,
      status['baselineId'] as String,
      status['membershipHeadHash'] as String,
      status['accessRevision'] as int,
    );
    final staged = payload['records'];
    if (staged is! List ||
        staged.isEmpty ||
        staged.length > 32 ||
        staged.any((r) => (r as Map)['domain'] != domain) ||
        staged
                .where(
                  (r) =>
                      CryptoBusinessJson.canonical(r) ==
                      CryptoBusinessJson.canonical(entry),
                )
                .length !=
            1) {
      throw const FormatException('record_policy_stage_binding');
    }
    final head = await business.access.headAt(
      scopeId,
      status['membershipHeadHash'] as String,
    );
    final lease = await business.access.getScopeKey(
      scopeId,
      domain,
      head.epoch,
    );
    Uint8List? plaintext;
    try {
      final envelope = Map<String, dynamic>.from(
        CryptoJson.decode(cryptoBase64(entry['policyEnvelopeBase64'])) as Map,
      );
      plaintext = _crypto.decrypt(
        envelope: envelope,
        key: lease.key,
        context: _context(
          scopeId,
          domain,
          id,
          type,
          recordProofHash,
          entry['createdByAccountId'] as String?,
          head.headHash,
          head.accessRevision,
        ),
      );
      final value = CryptoJson.decode(plaintext) as Map;
      if (value.length != 2 || value['version'] != 1) {
        throw const FormatException('record_policy_secret');
      }
      final key = cryptoBase64(value['keyBase64'], length: 32);
      return (policy: policy, key: key);
    } finally {
      plaintext?.fillRange(0, plaintext.length, 0);
      lease.release();
    }
  }
}
