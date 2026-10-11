part of 'collaboration_repository.dart';

extension CollaborationLocalSpacePublication on CollaborationRepository {
  Future<LocalSpacesPublicationPreview> previewLocalSpacesPublication(
    List<String> spaceIds, {
    bool refreshCapabilities = true,
  }) async {
    final session = _requireSession(), epoch = _epoch;
    if (refreshCapabilities) await _negotiate(session, epoch);
    final items = <LocalSpacePublicationItem>[], issues = <String>[];
    final content = <Object?>[session.profile.partition];
    final capabilityRows = await database.rows(
      'SELECT value FROM local_meta WHERE name=?',
      ['capabilities:${session.profile.partition}'],
    );
    final capabilities = capabilityRows.isEmpty
        ? <String, dynamic>{}
        : CollaborationRepository._map(capabilityRows.single['value']);
    final features = capabilities['features'] as Map? ?? const {};
    if (features['stableScopePublication'] != true ||
        features['scopeMetadata'] != true ||
        !(capabilities['organizationAccessPolicyVersions'] as List? ?? const [])
            .contains(2)) {
      issues.add('server_upgrade_required');
    }
    final ids = spaceIds.toSet().toList()..sort();
    final storage = SqliteOrganizerStorage(database);
    await storage.initialize();
    for (final id in ids) {
      final rows = await database.rows(
        'SELECT data FROM local_spaces WHERE id=?',
        [id],
      );
      if (rows.isEmpty) throw const CollaborationException('backup_stale');
      final space = LocalSpace.fromJson(
        CollaborationRepository._map(rows.single['data']),
      );
      final snapshot = await storage.localSnapshot(workspace: id);
      final savedCreation = await database.rows(
        'SELECT value FROM local_meta WHERE name=?',
        ['space_publication_create:${session.profile.partition}:$id'],
      );
      final splitProjects =
          space.kind == LocalSpaceKind.organization ||
          (space.kind == LocalSpaceKind.household &&
              _spaceProjectMembershipSupported &&
              (savedCreation.isEmpty ||
                  CollaborationRepository._map(
                        savedCreation.single['value'],
                      )['accessPolicyVersion'] ==
                      3));
      final gardens = await database.rows(
        'SELECT g.payload FROM device_gardens g JOIN garden_space_links l ON l.garden_id=g.id WHERE l.space_id=? ORDER BY g.id',
        [id],
      );
      final linked = await database.rows(
        'SELECT data FROM linked_payment_events WHERE space_key=? UNION ALL SELECT data FROM linked_payment_projections WHERE space_key=?',
        ['local:$id', 'local:$id'],
      );
      items.add(
        LocalSpacePublicationItem(
          space: space,
          recordCount: snapshot.recordIds.length,
          gardenCount: gardens.length,
          linkedPaymentCount: linked.length,
          projects: splitProjects
              ? [
                  for (final project in snapshot.projects)
                    LocalProjectPublicationDestination(
                      id: project.id,
                      name: project.title,
                      taskCount: snapshot.tasks
                          .where((t) => t.projectId == project.id)
                          .length,
                      financeCount: snapshot.financeEntries
                          .where((e) => e.projectId == project.id)
                          .length,
                      personCount: _publicationProjectPersonIds(
                        snapshot,
                        project.id,
                      ).length,
                      accountCount: snapshot.financeEntries
                          .where((e) => e.projectId == project.id)
                          .map((e) => e.ledgerAccountId ?? e.currency)
                          .toSet()
                          .length,
                    ),
                ]
              : const [],
        ),
      );
      content.add([
        Map<String, Object?>.of(space.toJson())..remove('binding'),
        snapshot.toJson(),
        gardens,
        linked,
      ]);
      if (space.binding != null &&
          space.binding!.partition != session.profile.partition) {
        issues.add('space_bound_to_other_account');
      }
      if (space.kind == LocalSpaceKind.personal) {
        issues.add(
          id == 'local'
              ? 'use_private_sync'
              : 'additional_personal_sync_unsupported',
        );
      }
      if (space.kind == LocalSpaceKind.organization &&
          !_organizationsSupported) {
        issues.add('client_upgrade_required');
      }
      if (gardens.isNotEmpty && _recordContractVersion < 4) {
        issues.add('garden_sync_unsupported');
      }
      if ((snapshot.financeEntries.isNotEmpty ||
              snapshot.financeAccounts.isNotEmpty ||
              snapshot.financeRecurrenceRules.isNotEmpty) &&
          _financeContractVersion < 2) {
        issues.add('finance_sync_unsupported');
      }
      if (splitProjects &&
          snapshot.financeEntries.any(
            (entry) =>
                entry.projectId != null && entry.recurrenceRuleId != null,
          )) {
        // Rules remain at organization level; server references are scope-local.
        issues.add('cross_scope_recurrence_rule');
      }
      if (splitProjects &&
          snapshot.financeEntries.any((entry) {
            final task = snapshot.tasks
                .where((t) => t.id == entry.taskId)
                .firstOrNull;
            return task != null && task.projectId != entry.projectId;
          })) {
        issues.add('cross_scope_finance_task');
      }
    }
    _checkEpoch(epoch);
    final digest = await Sha256().hash(utf8.encode(jsonEncode(content)));
    return LocalSpacesPublicationPreview(
      partition: session.profile.partition,
      serverUrl: session.profile.serverUrl,
      accountName: session.profile.displayName,
      fingerprint: base64Encode(digest.bytes),
      spaces: items,
      issues: issues,
    );
  }

  Future<void> publishLocalSpaces(LocalSpacesPublicationPreview preview) async {
    final session = _requireSession(), epoch = _epoch;
    if (!preview.canPublish || preview.partition != session.profile.partition) {
      throw const CollaborationException('backup_wrong_account');
    }
    final ids = preview.spaces.map((i) => i.space.id).toList();
    if ((await previewLocalSpacesPublication(
          ids,
          refreshCapabilities: false,
        )).fingerprint !=
        preview.fingerprint) {
      throw const CollaborationException('backup_stale');
    }
    for (final item in preview.spaces) {
      _checkEpoch(epoch);
      if (item.space.binding?.partition == session.profile.partition) continue;
      final space = item.space,
          snapshot = await SqliteOrganizerStorage(
            database,
          ).localSnapshot(workspace: item.space.id);
      final parent = await _ensureLocalPublishedScope(
        session,
        epoch,
        space.id,
        space.kind == LocalSpaceKind.organization
            ? SharedScopeKind.organization
            : SharedScopeKind.household,
        space.name,
        address: space.address,
      );
      final splitProjects =
          space.kind == LocalSpaceKind.organization ||
          (space.kind == LocalSpaceKind.household &&
              parent.accessPolicyVersion == 3);
      final projectScopes = <String, SharedScope>{};
      if (splitProjects) {
        for (final project in snapshot.projects) {
          projectScopes[project.id] = await _ensureLocalPublishedScope(
            session,
            epoch,
            project.id,
            SharedScopeKind.project,
            project.title,
            organizationId: space.kind == LocalSpaceKind.organization
                ? parent.id
                : null,
            parentScopeId: _spaceProjectMembershipSupported ? parent.id : null,
            projectPayload: _payload(project.toJson()),
          );
        }
      }
      final destinations = {parent.id, ...projectScopes.keys};
      final financePolicies = <String, SharedFinancePolicy>{};
      if (snapshot.financeEntries.isNotEmpty ||
          snapshot.financeAccounts.isNotEmpty ||
          snapshot.financeRecurrenceRules.isNotEmpty ||
          item.linkedPaymentCount > 0) {
        for (final scope in destinations) {
          var policy = await _fetchFinancePolicy(session, epoch, scope);
          if (!policy.canWrite) {
            await _callSession(session, epoch, 'finance.enable', {
              'scopeId': scope,
              'enabled': true,
              'requestId': await _publicationRequestId(
                session.profile.partition,
                scope,
                'finance',
              ),
            });
            policy = await _fetchFinancePolicy(session, epoch, scope);
          }
          if (!policy.canWrite) {
            throw const CollaborationException('finance_forbidden');
          }
          financePolicies[scope] = policy;
        }
      }
      // Server creation can complete before a user edits the local source.
      // Preserve that source and its persisted request IDs on a stale preview.
      if ((await previewLocalSpacesPublication(
            ids,
            refreshCapabilities: false,
          )).fingerprint !=
          preview.fingerprint) {
        throw const CollaborationException('backup_stale');
      }
      await database.transaction(() async {
        _checkEpoch(epoch);
        final currentPreview = await previewLocalSpacesPublication(
          ids,
          refreshCapabilities: false,
        );
        if (currentPreview.fingerprint != preview.fingerprint) {
          throw const CollaborationException('backup_stale');
        }
        for (final destination in destinations) {
          final referencedPeople = destination == parent.id
              ? null
              : _publicationProjectPersonIds(snapshot, destination);
          final people = snapshot.people
              .where(
                (person) =>
                    referencedPeople == null ||
                    referencedPeople.contains(person.id),
              )
              .map(
                (person) => destination == parent.id
                    ? person
                    : person.copyWith(notes: ''),
              );
          for (final person in people) {
            await _putPublicationRecord(
              session.profile.partition,
              destination,
              SharedRecordType.householdPerson,
              person.id,
              _payload(person.toJson()),
            );
          }
          final projects = splitProjects
              ? snapshot.projects.where((p) => p.id == destination)
              : snapshot.projects;
          for (final project in projects) {
            await _putPublicationRecord(
              session.profile.partition,
              destination,
              SharedRecordType.project,
              project.id,
              _payload(project.toJson()),
            );
          }
          for (final task in snapshot.tasks.where(
            (t) =>
                _publicationDestination(
                  space,
                  t.projectId,
                  parent.id,
                  splitProjects: splitProjects,
                ) ==
                destination,
          )) {
            await _putPublicationRecord(
              session.profile.partition,
              destination,
              SharedRecordType.task,
              task.id,
              _payload(task.toJson()),
            );
          }
          for (final event in snapshot.events.where(
            (e) =>
                _publicationDestination(
                  space,
                  e.projectId,
                  parent.id,
                  splitProjects: splitProjects,
                ) ==
                destination,
          )) {
            final payload = _payload(event.toJson());
            payload['startAt'] = payload.remove('startsAt');
            payload['endAt'] = payload.remove('endsAt');
            payload['assigneeAccountIds'] = <String>[];
            await _putPublicationRecord(
              session.profile.partition,
              destination,
              SharedRecordType.event,
              event.id,
              payload,
            );
          }
          if (destination == parent.id) {
            for (final list in snapshot.shoppingLists) {
              await _putPublicationRecord(
                session.profile.partition,
                destination,
                SharedRecordType.shoppingList,
                list.id,
                _payload(list.toJson()),
              );
            }
            for (final item in snapshot.shoppingItems) {
              await _putPublicationRecord(
                session.profile.partition,
                destination,
                SharedRecordType.shoppingItem,
                item.id,
                _payload(item.toJson()),
              );
            }
          }
          if (financePolicies.containsKey(destination)) {
            await _queuePublicationFinance(
              session.profile.partition,
              space,
              snapshot,
              destination,
              parent.id,
              splitProjects: splitProjects,
            );
          }
        }
        for (final row in await database.rows(
          'SELECT g.id,g.payload FROM device_gardens g JOIN garden_space_links l ON l.garden_id=g.id WHERE l.space_id=?',
          [space.id],
        )) {
          await _putPublicationRecord(
            session.profile.partition,
            parent.id,
            SharedRecordType.garden,
            row['id'] as String,
            CollaborationRepository._map(row['payload']),
          );
        }
        final linked = LocalSpace(
          id: space.id,
          kind: space.kind,
          name: space.name,
          address: space.address,
          binding: LocalSpaceBinding(
            partition: session.profile.partition,
            scopeId: parent.id,
          ),
        );
        await database.execute('UPDATE local_spaces SET data=? WHERE id=?', [
          jsonEncode(linked.toJson()),
          space.id,
        ]);
        await database.touchPersonal();
      });
      database.personalChanged();
    }
    await refreshLocal();
    await syncNow(resumePayments: false);
    await LinkedPaymentsRepository(
      database,
      collaboration: this,
    ).resumePending();
  }

  Set<String> _publicationProjectPersonIds(
    OrganizerSnapshot snapshot,
    String projectId,
  ) => {
    for (final task in snapshot.tasks.where(
      (t) => t.projectId == projectId,
    )) ...[
      if (task.assigneePersonId != null) task.assigneePersonId!,
      ...task.subjectPersonIds,
    ],
    for (final entry in snapshot.financeEntries.where(
      (e) => e.projectId == projectId,
    )) ...[
      if (entry.payerPersonId != null) entry.payerPersonId!,
      if (entry.recipientPersonId != null) entry.recipientPersonId!,
      if (entry.createdByPersonId != null) entry.createdByPersonId!,
    ],
  };

  bool _splitPublicationProjects(LocalSpace space) =>
      space.kind == LocalSpaceKind.organization ||
      (space.kind == LocalSpaceKind.household &&
          _spaceProjectMembershipSupported);

  String _publicationDestination(
    LocalSpace space,
    String? projectId,
    String parent, {
    bool? splitProjects,
  }) => (splitProjects ?? _splitPublicationProjects(space)) && projectId != null
      ? projectId
      : parent;
  Future<String> _publicationRequestId(
    String partition,
    String id,
    String purpose,
  ) async {
    final key = 'space_publication_request:$partition:$id:$purpose';
    return database.transaction(() async {
      await database.execute(
        'INSERT OR IGNORE INTO local_meta(name,value) VALUES(?,?)',
        [key, newSharedId()],
      );
      return (await database.rows('SELECT value FROM local_meta WHERE name=?', [
            key,
          ])).single['value']
          as String;
    });
  }

  Future<SharedScope> _ensureLocalPublishedScope(
    DeviceSession session,
    int epoch,
    String id,
    SharedScopeKind kind,
    String name, {
    String? organizationId,
    String? parentScopeId,
    String? address,
    Map<String, Object?>? projectPayload,
  }) async {
    final key = 'space_publication_create:${session.profile.partition}:$id';
    final saved = await database.rows(
      'SELECT value FROM local_meta WHERE name=?',
      [key],
    );
    final params = saved.isNotEmpty
        ? CollaborationRepository._map(saved.single['value'])
        : <String, Object?>{
            'id': id,
            'kind': kind.name,
            'name': name,
            'requestId': await _publicationRequestId(
              session.profile.partition,
              id,
              'create',
            ),
            if (organizationId != null) 'organizationId': organizationId,
            if (parentScopeId != null) 'parentScopeId': parentScopeId,
            if (address != null) 'address': address,
            if (projectPayload != null) 'projectPayload': projectPayload,
            if (_spaceProjectMembershipSupported &&
                (kind == SharedScopeKind.organization ||
                    kind == SharedScopeKind.household))
              'accessPolicyVersion': 3
            else if (kind == SharedScopeKind.organization)
              'accessPolicyVersion': 2,
          };
    if (saved.isEmpty) {
      await database.execute('INSERT INTO local_meta(name,value) VALUES(?,?)', [
        key,
        jsonEncode(params),
      ]);
    }
    final result = await _callSession(session, epoch, 'scopes.create', params);
    final scope = SharedScope.fromJson(result['scope'] as Map<String, dynamic>);
    if (scope.id != id ||
        scope.kind != kind ||
        scope.parentSpaceId != (parentScopeId ?? organizationId)) {
      throw const CollaborationException('invalid_response');
    }
    await database.transaction(() async {
      _checkEpoch(epoch);
      await _upsertScope(session.profile.partition, scope);
      if (result['projectRoot'] != null) {
        await _applyRemote(
          session.profile.partition,
          id,
          _canonical(result['projectRoot']),
        );
      }
    });
    return scope;
  }

  Future<void> _putPublicationRecord(
    String partition,
    String scope,
    SharedRecordType type,
    String id,
    Map<String, Object?> payload,
  ) async {
    final rows = await database.rows(
      'SELECT payload FROM records WHERE partition=? AND scope_id=? AND id=?',
      [partition, scope, id],
    );
    if (rows.isNotEmpty &&
        jsonEncode(CollaborationRepository._map(rows.single['payload'])) ==
            jsonEncode(payload)) {
      return;
    }
    await _put(partition, scope, type, id, payload);
  }

  Future<void> _queuePublicationFinance(
    String partition,
    LocalSpace space,
    OrganizerSnapshot snapshot,
    String destination,
    String parent, {
    bool? splitProjects,
  }) async {
    final entries = snapshot.financeEntries
        .where(
          (e) =>
              _publicationDestination(
                space,
                e.projectId,
                parent,
                splitProjects: splitProjects,
              ) ==
              destination,
        )
        .toList();
    final accounts = {
      for (final account in snapshot.financeAccounts.where(
        (a) =>
            destination == parent ||
            entries.any((e) => e.ledgerAccountId == a.id),
      ))
        account.id: SharedFinanceAccount(
          id: account.id,
          name: account.name,
          currency: account.currency,
          openingBalanceMinor: destination == parent
              ? account.openingBalanceMinor
              : null,
          openingBalanceAt: destination == parent
              ? account.openingBalanceAt
              : null,
          archived: account.archived,
          createdAt: account.createdAt,
          updatedAt: account.updatedAt,
        ),
    };
    for (final entry in entries.where((e) => e.ledgerAccountId == null)) {
      final id = await _publicationRequestId(
        partition,
        space.id,
        'default_finance:${entry.currency}',
      );
      accounts.putIfAbsent(
        id,
        () => SharedFinanceAccount(
          id: id,
          name: entry.currency,
          currency: entry.currency,
          openingBalanceMinor: null,
          createdAt: entry.createdAt,
          updatedAt: entry.createdAt,
        ),
      );
    }
    for (final account in accounts.values) {
      await _putFinance(
        partition,
        destination,
        SharedFinanceRecordType.financeAccount,
        account.id,
        account.toPayload(contractVersion: 2),
      );
    }
    for (final rule in snapshot.financeRecurrenceRules.where(
      (r) => destination == parent,
    )) {
      await _putFinance(
        partition,
        destination,
        SharedFinanceRecordType.financeRecurrenceRule,
        rule.id,
        _payload(rule.toJson()),
      );
    }
    for (final entry in entries) {
      final account =
          entry.ledgerAccountId ??
          await _publicationRequestId(
            partition,
            space.id,
            'default_finance:${entry.currency}',
          );
      final shared = SharedFinanceEntry(
        id: entry.id,
        accountId: account,
        ledgerAccountId: account,
        kind: entry.kind,
        status: entry.status == FinanceEntryStatus.planned
            ? SharedFinanceStatus.planned
            : SharedFinanceStatus.posted,
        amountMinor: entry.amountMinor,
        currency: entry.currency,
        title: entry.title,
        notes: entry.notes,
        occurredAt: entry.occurredAt,
        plannedAt: entry.plannedAt,
        paidAt: entry.paidAt,
        taskId: entry.taskId,
        payerPersonId: entry.payerPersonId,
        recipientPersonId: entry.recipientPersonId,
        createdByPersonId: entry.createdByPersonId,
        recurrenceRuleId: entry.recurrenceRuleId,
        occurrenceKey: entry.occurrenceKey,
        createdAt: entry.createdAt,
        updatedAt: entry.updatedAt,
      );
      await _putFinance(
        partition,
        destination,
        SharedFinanceRecordType.financeEntry,
        entry.id,
        shared.toPayload(contractVersion: 2),
      );
    }
  }
}
