part of 'portable_backup_repository.dart';

/// Explicitly creates device-owned copies. Exact server work remains encrypted
/// in restored_backups, with its original operation IDs and canonical evidence.
extension PortableBackupLocalRecovery on PortableBackupRepository {
  bool _hasOfflineLinkedPayments(Map<String, dynamic> doc, Set<String> scopes) {
    final linked = doc['linkedPayments'];
    if (linked is! Map) return false;
    for (final kind in ['events', 'projections', 'cashMovements']) {
      if ((linked[kind] as List? ?? []).any(
        (raw) => scopes.any(
          (scope) => (raw['space_key'] as String).endsWith(':$scope'),
        ),
      )) {
        return true;
      }
    }
    return (linked['intents'] as List? ?? []).any(
      (raw) => scopes.contains(
        PaymentSourceRef.fromJson(
          backupMap(backupMap(jsonDecode(raw['data'] as String))['source']),
        ).space.id,
      ),
    );
  }

  Future<void> _validateLocalLinkedPayments() async {
    final refundEvents = <String, PaymentEvent>{},
        refunds = <String, PaymentReimbursement>{};
    for (final row in await database.rows(
      "SELECT space_key,data FROM linked_payment_events WHERE space_key LIKE 'local:%'",
    )) {
      final event = PaymentEvent.fromJson(
        backupMap(jsonDecode(row['data'] as String)),
      );
      final source = await storage.localSnapshot(
        workspace: event.sourceScopeId,
      );
      final entry = source.financeEntries
          .where((e) => e.id == event.sourceEntryId)
          .firstOrNull;
      if (row['space_key'] != 'local:${event.sourceScopeId}' ||
          entry == null ||
          entry.kind != FinanceEntryKind.expense ||
          entry.amountMinor != event.amountMinor ||
          entry.currency != event.currency ||
          entry.paidAt != event.paidAt) {
        throw const CollaborationException('backup_conflict');
      }
      for (final leg in event.reimbursements) {
        if (refunds.containsKey(leg.legId)) {
          throw const CollaborationException('backup_conflict');
        }
        refunds[leg.legId] = leg;
        refundEvents[leg.legId] = event;
      }
    }
    for (final row in await database.rows(
      "SELECT space_key,data FROM linked_payment_projections WHERE space_key LIKE 'local:%'",
    )) {
      final projection = PaymentProjection.fromJson(
        backupMap(jsonDecode(row['data'] as String)),
      );
      if (projection.privateAccountId == null) continue;
      final target = await storage.localSnapshot(
        workspace: (row['space_key'] as String).substring(6),
      );
      if (!target.financeAccounts.any(
        (a) =>
            a.id == projection.privateAccountId &&
            a.currency == projection.event.currency,
      )) {
        throw const CollaborationException('backup_conflict');
      }
    }
    for (final row in await database.rows(
      "SELECT space_key,data FROM linked_payment_cash WHERE space_key LIKE 'local:%'",
    )) {
      final movement = PaymentCashMovement.fromJson(
        backupMap(jsonDecode(row['data'] as String)),
      );
      final snapshot = await storage.localSnapshot(
        workspace: (row['space_key'] as String).substring(6),
      );
      final leg = refunds[movement.id], event = refundEvents[movement.id];
      if (leg == null ||
          event == null ||
          movement.amountMinor != -leg.amountMinor ||
          movement.paidAt != leg.paidAt ||
          movement.currency != event.currency ||
          movement.accountId != leg.organizationAccountId ||
          (row['space_key'] as String) !=
              'local:${leg.organizationAccountScopeId ?? event.sourceScopeId}' ||
          !snapshot.financeAccounts.any(
            (a) =>
                a.id == movement.accountId && a.currency == movement.currency,
          )) {
        throw const CollaborationException('backup_conflict');
      }
    }
  }

  Future<bool> _offlineScopeDenied(
    String partition,
    String id, {
    String? sourceDeviceId,
  }) async {
    final current = database.personalProfile;
    final deviceId = current?.partition == partition
        ? current!.deviceId
        : sourceDeviceId;
    if ((await database.rows(
      'SELECT name,value FROM local_meta WHERE name=? OR name=?',
      ['deleted_account:$partition', 'invalid_session:$partition:$deviceId'],
    )).any(
      (r) =>
          (r['name'] as String).startsWith('deleted_account:') ||
          r['value'] == 'device_revoked',
    )) {
      return true;
    }
    final rows = await database.rows(
      'SELECT data,blocked FROM scopes WHERE partition=? AND id=?',
      [partition, id],
    );
    return rows.isNotEmpty &&
        (rows.single['blocked'] == 1 ||
            SharedScope.fromJson(
              backupMap(jsonDecode(rows.single['data'] as String)),
            ).revoked);
  }

  Future<bool> _offlineFinanceDenied(Map<String, dynamic> scopeRow) async {
    bool denied(Map<String, dynamic> row) =>
        row['finance_blocked'] == 1 ||
        row['finance_policy'] == null ||
        !SharedFinancePolicy.fromJson(
          backupMap(jsonDecode(row['finance_policy'] as String)),
        ).canRead;
    if (denied(scopeRow)) return true;
    final current = await database.rows(
      'SELECT finance_blocked,finance_policy FROM scopes WHERE partition=? AND id=?',
      [scopeRow['partition'], scopeRow['id']],
    );
    return current.isNotEmpty && denied(current.single);
  }

  Future<OfflineSpacesRecoveryPreview> reviewRestoredSpacesAsLocal(
    String id,
    String password,
  ) async {
    final doc = await _restored(id, password),
        source = doc['source'] == null
            ? <String, dynamic>{}
            : backupMap(doc['source']);
    final rows = backupRows(doc, 'scopes');
    final blocked = <String>[];
    var financeUnavailable = false;
    for (final row in rows) {
      financeUnavailable =
          await _offlineFinanceDenied(row) || financeUnavailable;
      final scope = SharedScope.fromJson(
        backupMap(jsonDecode(row['data'] as String)),
      );
      if (scope.revoked ||
          row['blocked'] == 1 ||
          await _offlineScopeDenied(
            row['partition'] as String,
            scope.id,
            sourceDeviceId: source['deviceId'] as String?,
          )) {
        blocked.add(scope.id);
      }
    }
    final available = rows.where((r) => !blocked.contains(r['id'])).toList();
    final scopes = {
      for (final row in available)
        row['id'] as String: SharedScope.fromJson(
          backupMap(jsonDecode(row['data'] as String)),
        ),
    };
    final items = <OfflineSpaceRecoveryItem>[];
    for (final scope in scopes.values) {
      if (scope.organizationId != null &&
          scopes.containsKey(scope.organizationId)) {
        continue;
      }
      final members = {
        scope.id,
        ...scopes.values
            .where((s) => s.organizationId == scope.id)
            .map((s) => s.id),
      };
      final records = backupRows(doc, 'records')
          .where((r) => members.contains(r['scope_id']) && r['deleted'] == 0)
          .toList();
      items.add(
        OfflineSpaceRecoveryItem(
          scopeId: scope.id,
          name: scope.name,
          kind: scope.kind == SharedScopeKind.personal
              ? LocalSpaceKind.personal
              : scope.kind == SharedScopeKind.household
              ? LocalSpaceKind.household
              : LocalSpaceKind.organization,
          recordCount:
              records.length +
              backupRows(doc, 'finance_records')
                  .where(
                    (r) => members.contains(r['scope_id']) && r['deleted'] == 0,
                  )
                  .length,
          gardenCount: records.where((r) => r['type'] == 'garden').length,
        ),
      );
    }
    final digest = await Sha256().hash(
      utf8.encode(jsonEncode([doc, await _rightsStamp(), blocked])),
    );
    return OfflineSpacesRecoveryPreview(
      backupId: id,
      fingerprint: base64Encode(digest.bytes),
      sourceAccount: source['displayName'] as String?,
      sourceServer: source['serverUrl'] as String?,
      spaces: items,
      blockedScopeIds: blocked,
      limitations: [
        'original_server_operations_audit_and_access_remain_archived',
        'new_local_copy_does_not_grant_server_access',
        if (backupRows(
          doc,
          'finance_records',
        ).any((r) => r['type'] == 'financeTransfer'))
          'finance_transfers_remain_archived',
        if (_hasOfflineLinkedPayments(doc, scopes.keys.toSet()))
          'linked_payments_require_reconciliation',
        if (financeUnavailable) 'finance_access_unavailable',
        if ((doc['completeness'] as List).isNotEmpty)
          'source_copy_may_be_incomplete',
      ],
    );
  }

  Future<List<LocalSpace>> recoverRestoredSpacesAsLocal(
    OfflineSpacesRecoveryPreview preview, {
    required String password,
  }) async {
    await _restored(preview.backupId, password);
    final recovered = await database.rows(
      'SELECT value FROM local_meta WHERE name=?',
      ['offline_recovery:${preview.backupId}'],
    );
    if (recovered.isNotEmpty) {
      return (jsonDecode(recovered.single['value'] as String) as List)
          .map((s) => LocalSpace.fromJson(backupMap(s)))
          .toList();
    }
    final current = await reviewRestoredSpacesAsLocal(
      preview.backupId,
      password,
    );
    if (current.fingerprint != preview.fingerprint) {
      throw const CollaborationException('backup_stale');
    }
    final doc = await _restored(preview.backupId, password);
    final marker = 'offline_recovery:${preview.backupId}';
    final created = await database.transaction(() async {
      final already = await database.rows(
        'SELECT value FROM local_meta WHERE name=?',
        [marker],
      );
      if (already.isNotEmpty) {
        return (jsonDecode(already.single['value'] as String) as List)
            .map((s) => LocalSpace.fromJson(backupMap(s)))
            .toList();
      }
      if ((await reviewRestoredSpacesAsLocal(
            preview.backupId,
            password,
          )).fingerprint !=
          preview.fingerprint) {
        throw const CollaborationException('backup_stale');
      }
      final scopes = {
        for (final row in backupRows(doc, 'scopes'))
          row['id'] as String: SharedScope.fromJson(
            backupMap(jsonDecode(row['data'] as String)),
          ),
      };
      final result = <LocalSpace>[];
      for (final item in preview.spaces) {
        final deniedFinance = <String>{};
        final scopeRows = backupRows(doc, 'scopes')
            .where(
              (r) =>
                  r['id'] == item.scopeId ||
                  scopes[r['id']]?.organizationId == item.scopeId,
            )
            .toList();
        for (final row in scopeRows) {
          if (await _offlineFinanceDenied(row)) {
            deniedFinance.add(row['id'] as String);
          }
        }
        final space = LocalSpace(
          id: newSharedId(),
          kind: item.kind,
          name: item.name,
          address: scopes[item.scopeId]?.address ?? '',
          financeRecoveryIncomplete:
              deniedFinance.isNotEmpty ||
              _hasOfflineLinkedPayments(doc, {
                for (final row in scopeRows) row['id'] as String,
              }) ||
              backupRows(doc, 'finance_records').any(
                (r) =>
                    scopeRows.any((s) => s['id'] == r['scope_id']) &&
                    r['type'] == 'financeTransfer',
              ),
        );
        final group = {
          item.scopeId,
          ...scopes.values
              .where(
                (s) =>
                    s.organizationId == item.scopeId &&
                    !preview.blockedScopeIds.contains(s.id),
              )
              .map((s) => s.id),
        };
        final ordinary = backupRows(
              doc,
              'records',
            ).where((r) => group.contains(r['scope_id'])).toList(),
            finance = backupRows(doc, 'finance_records')
                .where(
                  (r) =>
                      group.contains(r['scope_id']) &&
                      !deniedFinance.contains(r['scope_id']),
                )
                .toList();
        final ids = <String, String>{};
        String key(String scope, String id) => '$scope:$id';
        void collect(String scope, Object? value) {
          if (value is Map) {
            if (value['id'] is String) {
              ids.putIfAbsent(key(scope, value['id'] as String), newSharedId);
            }
            for (final child in value.values) {
              collect(scope, child);
            }
          } else if (value is List) {
            for (final child in value) {
              collect(scope, child);
            }
          }
        }

        for (final row in [...ordinary, ...finance]) {
          ids.putIfAbsent(
            key(row['scope_id'] as String, row['id'] as String),
            newSharedId,
          );
          if (row['payload'] != null) {
            collect(
              row['scope_id'] as String,
              jsonDecode(row['payload'] as String),
            );
          }
        }
        Object? remap(String scope, Object? value, {String? field}) {
          if (value is Map) {
            return {
              for (final entry in value.entries)
                entry.key as String: remap(
                  scope,
                  entry.value,
                  field: entry.key as String,
                ),
            };
          }
          if (value is List) {
            return value.map((v) => remap(scope, v, field: field)).toList();
          }
          if (value is String &&
              (field == 'id' ||
                  field?.endsWith('Id') == true ||
                  field?.endsWith('Ids') == true)) {
            return ids[key(scope, value)] ?? value;
          }
          return value;
        }

        final localRows = <Map<String, dynamic>>[], gardens = <Garden>[];
        for (final row in [...ordinary, ...finance]) {
          if (row['deleted'] == 1 || row['payload'] == null) continue;
          final scope = row['scope_id'] as String, type = row['type'] as String;
          final rejected =
              backupRows(
                doc,
                finance.contains(row) ? 'finance_outbox' : 'outbox',
              ).any(
                (q) =>
                    q['scope_id'] == scope &&
                    q['record_id'] == row['id'] &&
                    q['state'] != 'pending',
              );
          final remote = row['remote'] == null
              ? null
              : backupMap(jsonDecode(row['remote'] as String));
          if (rejected && (remote == null || remote['deleted'] == true)) {
            continue;
          }
          final raw = Map<String, dynamic>.from(
            rejected
                ? remote!['payload'] as Map
                : jsonDecode(row['payload'] as String) as Map,
          );
          raw['id'] = row['id'];
          raw['revision'] = 0;
          if (type == 'financeTransfer') continue;
          if (type == 'event') {
            raw['startsAt'] = raw.remove('startAt');
            raw['endsAt'] = raw.remove('endAt');
          }
          if (type == 'financeEntry') {
            raw['ledgerAccountId'] ??= raw['accountId'];
            raw['projectId'] =
                scopes[scope]?.organizationId != null ||
                    scopes[scope]?.kind == SharedScopeKind.project
                ? scopes[scope]?.projectRootId
                : null;
          }
          if (type == 'financeAccount' || type == 'personalFinanceAccount') {
            raw['archived'] ??= false;
            raw.putIfAbsent('openingBalanceAt', () => null);
          }
          final payload = backupMap(remap(scope, raw));
          if (type == 'garden') {
            gardens.add(Garden.fromJson(payload));
            continue;
          }
          final localType = type == 'personalFinanceEntry'
              ? 'financeEntry'
              : type == 'personalFinanceAccount'
              ? 'financeAccount'
              : type;
          if (![
            'project',
            'task',
            'event',
            'householdPerson',
            'shoppingList',
            'shoppingItem',
            'financeEntry',
            'financeAccount',
            'financeRecurrenceRule',
          ].contains(localType)) {
            continue;
          }
          localRows.add({'type': localType, 'payload': jsonEncode(payload)});
        }
        final snapshot = snapshotFromRows(localRows, revision: 0);
        snapshot.validate();
        await database.execute(
          'INSERT INTO local_spaces(id,data) VALUES(?,?)',
          [space.id, jsonEncode(space.toJson())],
        );
        await database.execute(
          'INSERT INTO personal_workspaces(id) VALUES(?)',
          [space.id],
        );
        for (final row in snapshotRows(snapshot)) {
          await commitPersonalRow(database, space.id, row);
        }
        for (final garden in gardens) {
          await database.execute(
            'INSERT INTO device_gardens(id,payload) VALUES(?,?)',
            [garden.id, jsonEncode(garden.toJson())],
          );
          await database.execute(
            'INSERT INTO garden_space_links(garden_id,space_id) VALUES(?,?)',
            [garden.id, space.id],
          );
        }
        result.add(space);
      }
      await database.execute('INSERT INTO local_meta(name,value) VALUES(?,?)', [
        marker,
        jsonEncode(result.map((s) => s.toJson()).toList()),
      ]);
      await database.touchPersonal();
      return result;
    });
    database.personalChanged();
    return created;
  }
}
