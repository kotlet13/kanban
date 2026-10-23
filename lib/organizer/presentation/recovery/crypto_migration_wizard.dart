import 'crypto_migration_generation_page.dart';
import 'dart:async';
import 'dart:typed_data';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../platform/recovery/recovery_file_io.dart';
import 'scope_recovery_page.dart';
import 'finance_contribution_page.dart';
import 'scope_key_contribution_page.dart';

import 'package:flutter/material.dart';

import '../../../l10n/l10n.dart';
import '../../data/e2ee/crypto_migration_coordinator.dart';
import '../../data/e2ee/crypto_migration_structure_workflow.dart';

/// UI boundary permits deterministic state-machine tests without replacing any
/// production trust decision. The coordinator owns receipts and authority.
abstract interface class CryptoMigrationController {
  Stream<CryptoMigrationState> get changes;
  Future<List<CryptoMigrationCandidate>> discoverAvailable();
  Future<CryptoMigrationState> inspect(String scopeId);
  Future<CryptoMigrationState> prepare(String scopeId);
  Future<CryptoMigrationState> resume(String migrationId);
  Future<CryptoMigrationState> retryPending(String migrationId);
  Future<CryptoMigrationState> archiveAndVerify(
    String migrationId, {
    required Uint8List recoveryFile,
  });
  Future<CryptoMigrationInventoryReview> review(String migrationId);
  Future<CryptoMigrationState> fence(
    String migrationId, {
    required String reviewedInventoryHash,
  });
  Future<void> close();
}

class AccountMigrationController implements CryptoMigrationController {
  AccountMigrationController(this.coordinator);
  final CryptoMigrationCoordinator coordinator;
  @override
  Stream<CryptoMigrationState> get changes => coordinator.changes;
  @override
  Future<List<CryptoMigrationCandidate>> discoverAvailable() =>
      coordinator.discoverAvailable();
  @override
  Future<CryptoMigrationState> inspect(String scopeId) =>
      coordinator.inspect(scopeId);
  @override
  Future<CryptoMigrationState> prepare(String scopeId) =>
      coordinator.prepare(scopeId);
  @override
  Future<CryptoMigrationState> resume(String migrationId) =>
      coordinator.resume(migrationId);
  @override
  Future<CryptoMigrationState> retryPending(String migrationId) =>
      coordinator.retryPending(migrationId);
  @override
  Future<CryptoMigrationState> archiveAndVerify(
    String migrationId, {
    required Uint8List recoveryFile,
  }) => coordinator.archiveAndVerify(migrationId, recoveryFile: recoveryFile);
  @override
  Future<CryptoMigrationInventoryReview> review(String migrationId) =>
      coordinator.review(migrationId);
  @override
  Future<CryptoMigrationState> fence(
    String migrationId, {
    required String reviewedInventoryHash,
  }) => coordinator.fence(
    migrationId,
    reviewedInventoryHash: reviewedInventoryHash,
  );
  Future<CryptoMigrationState> abort(String migrationId) =>
      coordinator.abort(migrationId);
  Future<CryptoMigrationState> replan(String scopeId) =>
      coordinator.replan(scopeId);
  @override
  Future<void> close() => coordinator.close();
}

class CryptoMigrationWizard extends ConsumerStatefulWidget {
  const CryptoMigrationWizard({
    required this.controller,
    this.cachedLabels = const {},
    this.onFinished,
    super.key,
  });
  final CryptoMigrationController controller;
  final Map<String, String> cachedLabels;
  final Future<bool> Function()? onFinished;
  @override
  ConsumerState<CryptoMigrationWizard> createState() =>
      _CryptoMigrationWizardState();
}

class _CryptoMigrationWizardState extends ConsumerState<CryptoMigrationWizard> {
  List<CryptoMigrationCandidate>? _candidates;
  final _states = <String, CryptoMigrationState>{};
  StreamSubscription<CryptoMigrationState>? _subscription;
  bool _busy = false, _failed = false;
  @override
  void initState() {
    super.initState();
    _subscription = widget.controller.changes.listen((state) {
      if (mounted) setState(() => _states[state.scopeId] = state);
    });
    _discover();
  }

  @override
  void dispose() {
    _subscription?.cancel();
    widget.controller.close();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _failed = false;
    });
    try {
      await action();
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _discover() => _run(() async {
    final candidates = await widget.controller.discoverAvailable();
    if (!mounted) return;
    setState(() => _candidates = candidates);
    for (final candidate in candidates) {
      final state = await widget.controller.inspect(candidate.scopeId);
      if (!mounted) return;
      setState(() => _states[candidate.scopeId] = state);
    }
  });
  Future<bool> _reviewStructure(CryptoMigrationStructureReview review) async {
    if (!mounted) return false;
    final sl = Localizations.localeOf(context).languageCode == 'sl';
    if (review.purpose == 'financeAccountChoices') {
      var accepted = false;
      return await showDialog<bool>(
            context: context,
            builder: (dialog) => StatefulBuilder(
              builder: (context, update) => AlertDialog(
                title: Text(
                  sl ? 'Potrdite seznam računov' : 'Approve account selection',
                ),
                content: SizedBox(
                  width: 440,
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          sl
                              ? 'Izdajatelj je podpisal celoten izbor ${review.facts['selectionCount']} računov za ta projekt. Prenesejo se le imena, valute in stanje arhiviranja. Saldi, knjižbe in dostop do starša se ne prenesejo.'
                              : 'The issuer signed the complete selection of ${review.facts['selectionCount']} accounts for this project. Only names, currencies and archive status are shared. Balances, transactions and parent access are not shared.',
                        ),
                        ExpansionTile(
                          title: Text(
                            sl ? 'Podrobnosti podpisa' : 'Signature details',
                          ),
                          children: [
                            SelectableText(
                              '${sl ? 'Račun izdajatelja' : 'Issuer account'}: ${review.facts['issuerAccountId']}\n${review.facts['selectionHash']}\n${sl ? 'Račun prejemnika' : 'Recipient account'}: ${review.facts['recipient']?['accountId']}\n${sl ? 'Naprava prejemnika' : 'Recipient device'}: ${review.facts['recipient']?['deviceId']}',
                            ),
                          ],
                        ),
                        CheckboxListTile(
                          value: accepted,
                          onChanged: (v) => update(() => accepted = v == true),
                          title: Text(
                            sl
                                ? 'Potrjujem ta točen izbor'
                                : 'I approve this exact selection',
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(dialog, false),
                    child: Text(sl ? 'Prekliči' : 'Cancel'),
                  ),
                  FilledButton(
                    onPressed: accepted
                        ? () => Navigator.pop(dialog, true)
                        : null,
                    child: Text(sl ? 'Potrdi' : 'Approve'),
                  ),
                ],
              ),
            ),
          ) ??
          false;
    }
    final descriptor = review.facts['descriptor'] is Map
        ? review.facts['descriptor'] as Map
        : review.facts;
    final policy = review.facts['financePolicy'];
    final signedMembers = (review.facts['members'] as List).cast<Map>();
    String role(Object? value) => switch (value) {
      'owner' => sl ? 'Lastnik' : 'Owner',
      'member' => sl ? 'Član' : 'Member',
      'viewer' => sl ? 'Bralec' : 'Viewer',
      _ => sl ? 'Ni določeno' : 'Unspecified',
    };
    String finance(Object? value) => switch (value) {
      'write' => sl ? 'Urejanje' : 'Edit',
      'read' => sl ? 'Ogled' : 'Read',
      _ => sl ? 'Brez dostopa' : 'No access',
    };
    String kind(Object? value) => switch (value) {
      'personal' => sl ? 'Osebni prostor' : 'Personal space',
      'household' => sl ? 'Gospodinjstvo' : 'Household',
      'organization' => sl ? 'Organizacija' : 'Organization',
      'project' => sl ? 'Projekt' : 'Project',
      _ => sl ? 'Prostor' : 'Space',
    };
    final policyMeaning = switch (descriptor['accessPolicyVersion']) {
      1 =>
        sl
            ? 'Ločene članske in finančne pravice'
            : 'Separate membership and finance permissions',
      2 =>
        sl
            ? 'Upravljanje in finance po pravilih organizacije'
            : 'Management and finance follow organization rules',
      3 =>
        sl
            ? 'Finančne pravice sledijo vlogam članov'
            : 'Finance permissions follow member roles',
      _ => throw const FormatException('crypto_structure_context_policy'),
    };
    String name(Map member) {
      final id = member['accountId'] as String;
      return review.labels[id] ??
          '${sl ? 'Član' : 'Member'} ${id.substring(0, 8)}';
    }

    var checked = false;
    return await showDialog<bool>(
          context: context,
          builder: (dialogContext) => StatefulBuilder(
            builder: (context, setDialogState) => AlertDialog(
              title: Text(
                review.purpose == 'parentAccess'
                    ? (sl
                          ? 'Preverite podedovani dostop'
                          : 'Review inherited access')
                    : (sl
                          ? 'Preverite dostop do prostora'
                          : 'Review space access'),
              ),
              content: SizedBox(
                width: 440,
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        sl
                            ? 'Drugi skrbnik je podpisal naslednja obstoječa pravila in člane. Preglejte jih pred potrditvijo. Ta korak ne dodeli novih pravic.'
                            : 'Another manager signed the following existing rules and members. Review them before approving. This step grants no new permissions.',
                      ),
                      const SizedBox(height: 12),
                      Text(kind(descriptor['kind'])),
                      Text(policyMeaning),
                      Text(
                        '${sl ? 'Arhiviran' : 'Archived'}: ${descriptor['ownArchived'] == true ? (sl ? 'da' : 'yes') : (sl ? 'ne' : 'no')}',
                      ),
                      if (policy is Map)
                        Text(
                          '${sl ? 'Finance' : 'Finance'}: ${policy['enabled'] == true ? (sl ? 'vključene' : 'enabled') : (sl ? 'izključene' : 'disabled')}',
                        ),
                      const SizedBox(height: 12),
                      Text(
                        review.purpose == 'parentAccess'
                            ? (sl
                                  ? 'Podpisani člani za podedovani dostop'
                                  : 'Signed members for inherited access')
                            : (sl
                                  ? 'Podpisani člani prostora'
                                  : 'Signed space members'),
                      ),
                      if (signedMembers.isEmpty)
                        Text(
                          sl
                              ? 'Ni podedovanih članov.'
                              : 'No inherited members.',
                        ),
                      for (final member in signedMembers)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Text(
                            '${name(member)} · ${role(member['role'])}${member['leader'] == true && descriptor['accessPolicyVersion'] != 3 ? (sl ? ' · Vodja' : ' · Leader') : ''}',
                          ),
                        ),
                      ExpansionTile(
                        tilePadding: EdgeInsets.zero,
                        title: Text(
                          sl ? 'Vloge v tem prostoru' : 'Roles in this space',
                        ),
                        children: [
                          for (final member in review.members)
                            ListTile(
                              contentPadding: EdgeInsets.zero,
                              title: Text(name(member)),
                              subtitle: Text(
                                '${role(member['role'])} · ${sl ? 'finance' : 'finance'}: ${finance(member['financeRole'])}${member['manageKeys'] == true ? (sl ? ' · Upravlja ključe' : ' · Manages keys') : ''}',
                              ),
                            ),
                        ],
                      ),
                      ExpansionTile(
                        tilePadding: EdgeInsets.zero,
                        title: Text(
                          sl
                              ? 'Identitete in podpis'
                              : 'Identities and signature',
                        ),
                        children: [
                          for (final member in signedMembers)
                            ListTile(
                              contentPadding: EdgeInsets.zero,
                              title: Text(name(member)),
                              subtitle: SelectableText(
                                member['accountId'] as String,
                              ),
                            ),
                          SelectableText(review.issuerFingerprint),
                        ],
                      ),
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        value: checked,
                        onChanged: (v) =>
                            setDialogState(() => checked = v == true),
                        title: Text(
                          sl
                              ? 'Podpisana pravila in člane sem pregledal.'
                              : 'I reviewed the signed rules and members.',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext, false),
                  child: Text(context.l10n.cancel),
                ),
                FilledButton(
                  onPressed: checked
                      ? () => Navigator.pop(dialogContext, true)
                      : null,
                  child: Text(context.l10n.cryptoMigrationConsent),
                ),
              ],
            ),
          ),
        ) ==
        true;
  }

  Future<void> _continue(CryptoMigrationCandidate candidate) => _run(() async {
    final state = _states[candidate.scopeId];
    if ((state?.phase == CryptoMigrationPhase.archiving ||
            state?.phase == CryptoMigrationPhase.verifying &&
                widget.controller is AccountMigrationController) &&
        state?.migrationId != null &&
        state?.canContinue == true) {
      final file = await ref.read(recoveryFileIoProvider).pick();
      if (file == null) return;
      try {
        var disclose = false;
        final controller = widget.controller;
        if (controller is AccountMigrationController &&
            await controller.coordinator.requiresRemoteDateDisclosure(
              state!.migrationId!,
            )) {
          if (!mounted) return;
          final sl = Localizations.localeOf(context).languageCode == 'sl';
          final accepted = await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: Text(
                sl
                    ? 'Obstoječi oddaljeni opomniki'
                    : 'Existing remote reminders',
              ),
              content: Text(
                sl
                    ? 'Za ohranitev obstoječih oddaljenih opomnikov strežniku dovolite uporabo njihovih datumov in časa. Naslovi in vsebina ostanejo šifrirani. Brez tega koraka nadgradnja ostane nedokončana.'
                    : 'To preserve existing remote reminders, allow the server to use their dates and times. Titles and content remain encrypted. Without this step the upgrade remains unfinished.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: Text(context.l10n.cancel),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: Text(context.l10n.cryptoMigrationConsent),
                ),
              ],
            ),
          );
          if (accepted != true) return;
          disclose = true;
        }
        final next = controller is AccountMigrationController
            ? await controller.coordinator.archiveAndVerify(
                state!.migrationId!,
                recoveryFile: file,
                acceptedRemoteDateDisclosure: disclose,
                reviewStructure: _reviewStructure,
              )
            : await controller.archiveAndVerify(
                state!.migrationId!,
                recoveryFile: file,
              );
        if (mounted) setState(() => _states[candidate.scopeId] = next);
      } finally {
        file.fillRange(0, file.length, 0);
      }
      return;
    }
    if (state?.phase == CryptoMigrationPhase.preparing &&
        state?.migrationId != null &&
        state?.canContinue == true) {
      final review = await widget.controller.review(state!.migrationId!);
      if (!mounted) return;
      final l = context.l10n;
      final accepted = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(l.cryptoMigrationReviewTitle),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l.cryptoMigrationReviewExplanation),
                const SizedBox(height: 12),
                Text(
                  l.cryptoMigrationReviewCounts(
                    review.rowCount,
                    review.fileCount,
                  ),
                ),
                Text(l.cryptoMigrationLocalAvailable),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(l.cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(l.cryptoMigrationConsent),
            ),
          ],
        ),
      );
      if (accepted != true || !mounted) return;
      final next = await widget.controller.fence(
        state.migrationId!,
        reviewedInventoryHash: review.inventoryHash,
      );
      if (mounted) setState(() => _states[candidate.scopeId] = next);
      return;
    }
    final next = state?.migrationId == null
        ? await widget.controller.prepare(candidate.scopeId)
        : await widget.controller.retryPending(state!.migrationId!);
    if (mounted) setState(() => _states[candidate.scopeId] = next);
  });
  Future<void> _abort(
    CryptoMigrationCandidate candidate,
    CryptoMigrationState state,
  ) => _run(() async {
    final sl = Localizations.localeOf(context).languageCode == 'sl';
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(sl ? 'Opustim ta poskus?' : 'Abandon this attempt?'),
        content: Text(
          sl
              ? 'Prejšnji način deljenja se lahko ponovno odpre samo, če je vir nespremenjen in še ni dokončne šifrirane objave. Prvotni zahtevki, ključi in pripravljene kopije ostanejo ohranjeni. Pri več upravljavcih so potrebne njihove odobritve.'
              : 'Previous sharing can reopen only if its source is unchanged and no final encrypted publication exists. Original requests, keys and prepared copies remain preserved. Multiple managers must approve together.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(context.l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(sl ? 'Preveri in opusti' : 'Check and abandon'),
          ),
        ],
      ),
    );
    if (accepted != true || !mounted) return;
    final controller = widget.controller as AccountMigrationController;
    final next = await controller.abort(state.migrationId!);
    if (mounted) setState(() => _states[candidate.scopeId] = next);
  });

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final canFinish =
        _candidates != null &&
        (_candidates!.isEmpty ||
            _candidates!.every(
              (c) =>
                  _states[c.scopeId]?.phase == CryptoMigrationPhase.committed,
            ));
    return Scaffold(
      appBar: AppBar(title: Text(l.cryptoMigrationTitle)),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                Text(
                  canFinish
                      ? l.cryptoMigrationReviewReady
                      : l.cryptoMigrationReviewDescription,
                ),
                const SizedBox(height: 16),
                Text(
                  l.cryptoMigrationLocalPreserved,
                  key: const ValueKey('migration_local_preserved'),
                ),
                if (_busy) const LinearProgressIndicator(),
                if (_busy &&
                    _states.values.any((s) => s.retryAfterSeconds != null))
                  TextButton(
                    key: const ValueKey('migration_leave_paused'),
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(l.cryptoContinueLocally),
                  ),
                if (_failed) ...[
                  const SizedBox(height: 16),
                  Text(l.accountRecoveryFailed),
                  TextButton(
                    onPressed: _busy ? null : _discover,
                    child: Text(l.cryptoMigrationRetry),
                  ),
                ],
                if (_candidates?.isEmpty == true)
                  Text(l.cryptoMigrationNoScopes),
                TextButton(
                  onPressed: _busy
                      ? () => Navigator.of(context).pop()
                      : () => _run(() async {
                          if (_candidates != null &&
                              (_candidates!.isEmpty ||
                                  _candidates!.every(
                                    (c) =>
                                        _states[c.scopeId]?.phase ==
                                        CryptoMigrationPhase.committed,
                                  ))) {
                            if (await widget.onFinished?.call() == false) {
                              return;
                            }
                          }
                          if (context.mounted) Navigator.of(context).pop();
                        }),
                  child: Text(
                    canFinish
                        ? l.cryptoMigrationFinishReview
                        : l.cryptoContinueLocally,
                  ),
                ),
                if (canFinish)
                  TextButton(
                    key: const ValueKey('migration_continue_local'),
                    onPressed: _busy ? null : () => Navigator.of(context).pop(),
                    child: Text(l.cryptoContinueLocally),
                  ),
                for (final candidate
                    in _candidates ?? <CryptoMigrationCandidate>[]) ...[
                  const SizedBox(height: 20),
                  _scope(context, candidate),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _scope(BuildContext context, CryptoMigrationCandidate candidate) {
    final l = context.l10n, state = _states[candidate.scopeId];
    final phase = state?.phase;
    final done = phase == CryptoMigrationPhase.committed;
    final text = switch (phase) {
      CryptoMigrationPhase.waitingContributors =>
        l.cryptoMigrationPendingContributors,
      CryptoMigrationPhase.verifying ||
      CryptoMigrationPhase.ready => l.cryptoMigrationVerifying,
      CryptoMigrationPhase.archiving => l.cryptoMigrationArchiving,
      CryptoMigrationPhase.unavailable => l.cryptoMigrationUnavailableHelp,
      CryptoMigrationPhase.blocked => l.cryptoMigrationBlockedHelp,
      CryptoMigrationPhase.committed => l.cryptoMigrationComplete,
      _ => l.cryptoMigrationPreparing,
    };
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // IDs are existing assigned scopes, never contact identity claims.
            Text(
              widget.cachedLabels[candidate.scopeId] ??
                  '${l.cryptoMigrationSpace} · ${candidate.scopeId.substring(0, 8)}',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 8), Text(text),
            if (state?.errorCode == 'crypto_migration_pending_upload')
              Text(
                Localizations.localeOf(context).languageCode == 'sl'
                    ? 'Najprej dokončajte prekinjeno prilogo v njenem prvotnem prostoru. Znova izberite isto izvorno datoteko; ohranili bomo prvotni prenos in njegov ID. Nato se vrnite in nadaljujte. Osnutek tabele z izteklim zaklepom najprej ponovno odprite in preglejte.'
                    : 'First finish the interrupted attachment in its original space. Select the same source file again; its original upload and ID will be retained. Then return and continue. Reopen and review a table draft whose lease has expired.',
              ),

            if (done && state?.legacyCleanupPending == true)
              Text(
                Localizations.localeOf(context).languageCode == 'sl'
                    ? 'Stari berljivi strežniški podatki in kopije še čakajo ločeno čiščenje. Aktivno šifriranje jih ne izbriše.'
                    : 'Old readable server data and backups still await separate cleanup. Active encryption does not erase them.',
              ),
            if (state?.retryAfterSeconds != null)
              Text(
                Localizations.localeOf(context).languageCode == 'sl'
                    ? 'Nadaljevanje bo samodejno čez ${state!.retryAfterSeconds} sekund. Zaslon lahko zaprete; prvotne zahteve ostanejo shranjene.'
                    : 'Resuming automatically in ${state!.retryAfterSeconds} seconds. You can leave this screen; your original requests stay saved.',
              ),
            if (state != null && state.progress > 0 && !done)
              LinearProgressIndicator(value: state.progress.clamp(0, 1)),
            if (state?.canContinue != true && !done)
              Text(l.cryptoMigrationWaitingHelp),
            if ((state?.pendingContributionCount ?? 0) > 0)
              Text(
                l.cryptoMigrationContributorCount(
                  state!.pendingContributionCount,
                ),
              ),
            if ((state?.unavailableContributionCount ?? 0) > 0)
              Text(
                l.cryptoMigrationUnavailableCount(
                  state!.unavailableContributionCount,
                ),
              ),
            if (widget.controller is AccountMigrationController &&
                candidate.cryptoState != null &&
                candidate.cryptoState != 'legacy')
              OutlinedButton(
                onPressed: _busy
                    ? null
                    : () => Navigator.of(context).push<void>(
                        MaterialPageRoute(
                          builder: (_) => ScopeRecoveryPage(
                            account:
                                (widget.controller
                                        as AccountMigrationController)
                                    .coordinator
                                    .account,
                            scopeId: candidate.scopeId,
                            label:
                                widget.cachedLabels[candidate.scopeId] ??
                                l.cryptoMigrationSpace,
                          ),
                        ),
                      ),
                child: Text(l.cryptoReviewConnectedSpace),
              ),
            if (widget.controller is AccountMigrationController)
              TextButton(
                onPressed: _busy
                    ? null
                    : () => Navigator.of(context).push<void>(
                        MaterialPageRoute(
                          builder: (_) => FinanceContributionPage(
                            account:
                                (widget.controller
                                        as AccountMigrationController)
                                    .coordinator
                                    .account,
                            scopeId: candidate.scopeId,
                            label:
                                widget.cachedLabels[candidate.scopeId] ??
                                l.cryptoMigrationSpace,
                          ),
                        ),
                      ),
                child: Text(l.cryptoFinanceContributionTitle),
              ),
            if (widget.controller is AccountMigrationController)
              TextButton(
                onPressed: _busy
                    ? null
                    : () => Navigator.of(context).push<void>(
                        MaterialPageRoute(
                          builder: (_) => ScopeKeyContributionPage(
                            account:
                                (widget.controller
                                        as AccountMigrationController)
                                    .coordinator
                                    .account,
                            scopeId: candidate.scopeId,
                            label:
                                widget.cachedLabels[candidate.scopeId] ??
                                l.cryptoMigrationSpace,
                          ),
                        ),
                      ),
                child: Text(l.cryptoKeyContributionTitle),
              ),
            if (!done &&
                state?.migrationId != null &&
                widget.controller is AccountMigrationController)
              TextButton(
                onPressed: _busy
                    ? null
                    : () async {
                        await Navigator.of(context).push<bool>(
                          MaterialPageRoute(
                            builder: (_) => CryptoMigrationGenerationPage(
                              coordinator:
                                  (widget.controller
                                          as AccountMigrationController)
                                      .coordinator,
                              scopeId: candidate.scopeId,
                              migrationId: state!.migrationId!,
                            ),
                          ),
                        );
                        if (mounted) await _discover();
                      },
                child: Text(
                  Localizations.localeOf(context).languageCode == 'sl'
                      ? 'Nadaljuj po menjavi naprave'
                      : 'Resume after changing devices',
                ),
              ),
            if (!done &&
                state?.migrationId != null &&
                widget.controller is AccountMigrationController)
              TextButton(
                key: ValueKey('migration_abort_${candidate.scopeId}'),
                onPressed: _busy
                    ? null
                    : state?.errorCode == 'crypto_migration_aborted'
                    ? () => _run(() async {
                        final next =
                            await (widget.controller
                                    as AccountMigrationController)
                                .replan(candidate.scopeId);
                        if (mounted) {
                          setState(() => _states[candidate.scopeId] = next);
                        }
                      })
                    : () => _abort(candidate, state!),
                child: Text(
                  Localizations.localeOf(context).languageCode == 'sl'
                      ? state?.errorCode == 'crypto_migration_aborted'
                            ? 'Pripravi nov poskus'
                            : 'Varno opusti poskus'
                      : state?.errorCode == 'crypto_migration_aborted'
                      ? 'Prepare another attempt'
                      : 'Safely abandon attempt',
                ),
              ),
            if (!done && state?.canContinue == true)
              TextButton(
                onPressed: _busy ? null : () => _continue(candidate),
                child: Text(
                  state?.migrationId == null
                      ? l.cryptoMigrationContinue
                      : l.cryptoMigrationRetry,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
