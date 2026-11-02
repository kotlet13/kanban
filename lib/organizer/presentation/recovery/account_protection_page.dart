import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/l10n.dart';
import '../../data/e2ee/account_crypto_v2_workflow.dart';
import '../../data/e2ee/account_directory_v2.dart'
    show CryptoDirectoryException;
import '../../data/e2ee/account_protection_ready.dart';
import '../../data/e2ee/crypto_migration_coordinator.dart';
import '../../data/e2ee/crypto_scope_observations.dart'
    show CryptoScopeObservations, CryptoScopeRecoveryIncomplete;
import '../../data/e2ee/crypto_sync_repository.dart'
    show CryptoAuthorityPending;
import '../../platform/recovery/recovery_file_io.dart';
import '../../state/account_summary_refresh_provider.dart';
import '../../state/collaboration_provider.dart';
import '../shared/sharing_session_boundary.dart';
import 'scope_recovery_page.dart';
import 'crypto_migration_wizard.dart';

/// Presentation seam. The production implementation retains the existing
/// signed completion, recovery import and explicit history-review workflows.
abstract interface class AccountProtectionPageController {
  bool isCurrent(AccountSession? session);
  Future<bool> needsLegacyMigration();
  Future<Map<String, dynamic>?> unavailableReview();
  Future<void> complete({
    Map<String, dynamic>? reviewedUnavailable,
    void Function(int)? onPause,
  });
  Future<List<Map<String, dynamic>>> pendingScopeActions();
  Future<bool> hasIncompleteScopeRecovery();
  Future<void> restoreScopesFromFile(Uint8List file);
  Future<String?> scopeLabel(String scopeId);
  void close();
}

class _AccountProtectionPageController
    implements AccountProtectionPageController {
  _AccountProtectionPageController(this.account)
    : service = AccountProtectionReady(account);
  final AccountCryptoV2Workflow account;
  final AccountProtectionReady service;
  bool _closed = false;

  @override
  bool isCurrent(AccountSession? session) =>
      !_closed &&
      session?.partition == account.store.partition &&
      session?.deviceId == account.deviceId &&
      account.directory.isCurrent();
  @override
  Future<bool> needsLegacyMigration() async =>
      (await service.catalog()).any((scope) => scope['cryptoOrigin'] != true);
  @override
  Future<Map<String, dynamic>?> unavailableReview() =>
      service.unavailableReview();
  @override
  Future<void> complete({
    Map<String, dynamic>? reviewedUnavailable,
    void Function(int)? onPause,
  }) => service.complete(
    reviewedUnavailable: reviewedUnavailable,
    onPause: onPause,
  );
  @override
  Future<List<Map<String, dynamic>>> pendingScopeActions() =>
      service.pendingScopeActions();
  @override
  Future<bool> hasIncompleteScopeRecovery() =>
      account.hasIncompleteScopeRecovery();
  @override
  Future<void> restoreScopesFromFile(Uint8List file) => CryptoScopeObservations(
    account,
    isCurrent: () => !_closed && account.directory.isCurrent(),
  ).hydrateAllAvailableObservedScopes(file);
  @override
  Future<String?> scopeLabel(String scopeId) async {
    final rows = await account.store.database.rows(
      'SELECT data FROM scopes WHERE partition=? AND id=?',
      [account.store.partition, scopeId],
    );
    if (rows.isEmpty || rows.single['data'] is! String) return null;
    final value = jsonDecode(rows.single['data'] as String);
    return value is Map && value['name'] is String
        ? value['name'] as String
        : null;
  }

  @override
  void close() {
    _closed = true;
    service.close();
  }
}

final accountProtectionPageControllerProvider =
    Provider<AccountProtectionPageController Function(AccountCryptoV2Workflow)>(
      (ref) => _AccountProtectionPageController.new,
    );

final accountProtectionScopeReviewBuilderProvider =
    Provider<Widget Function(AccountCryptoV2Workflow, String, String)>(
      (ref) =>
          (account, scope, label) => ScopeRecoveryPage(
            account: account,
            scopeId: scope,
            label: label,
            allowFileImport: false,
          ),
    );

final accountProtectionLegacyMigrationBuilderProvider =
    Provider<
      Widget Function(
        AccountCryptoV2Workflow,
        Map<String, String>,
        Future<bool> Function(),
      )
    >(
      (ref) =>
          (account, labels, onFinished) => CryptoMigrationWizard(
            controller: AccountMigrationController(
              CryptoMigrationCoordinator(account: account),
            ),
            cachedLabels: labels,
            onFinished: onFinished,
          ),
    );

/// Reads the catalog before choosing the existing legacy migration controls or
/// account-wide protection preparation. A failed catalog never assumes ready.
class AccountProtectionEntry extends ConsumerStatefulWidget {
  const AccountProtectionEntry({required this.account, super.key});
  final AccountCryptoV2Workflow account;
  @override
  ConsumerState<AccountProtectionEntry> createState() =>
      _AccountProtectionEntryState();
}

class _AccountProtectionEntryState
    extends ConsumerState<AccountProtectionEntry> {
  late final AccountProtectionPageController _controller;
  late final SharingSessionGuard _guard;
  bool _initialized = false, _busy = false;
  bool? _legacy;
  bool _failed = false;
  Widget? _legacyChild;

  bool get _current =>
      mounted &&
      _guard.isCurrent &&
      _controller.isCurrent(
        ref.read(collaborationProvider).valueOrNull?.session,
      );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;
    _guard = SharingSessionGuard(context, ref);
    _controller = ref.read(accountProtectionPageControllerProvider)(
      widget.account,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_current) unawaited(_load());
    });
  }

  @override
  void dispose() {
    if (_initialized) _controller.close();
    super.dispose();
  }

  Future<void> _load() async {
    if (_busy || !_current) return;
    setState(() {
      _busy = true;
      _failed = false;
    });
    try {
      final legacy = await _controller.needsLegacyMigration();
      if (_current) setState(() => _legacy = legacy);
    } catch (_) {
      if (_current) setState(() => _failed = true);
    } finally {
      if (_current) setState(() => _busy = false);
    }
  }

  Future<bool> _finishLegacy() async {
    if (!_current) return false;
    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => AccountProtectionPage(account: widget.account),
      ),
    );
    return _current && result == true;
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(collaborationProvider, (_, __) {
      if (!_current) _controller.close();
    });
    final Widget child;
    if (_legacy == true) {
      final labels = <String, String>{
        for (final scope
            in ref.read(collaborationProvider).valueOrNull?.scopes ?? [])
          scope.id: scope.name,
      };
      child = _legacyChild ??= ref.read(
        accountProtectionLegacyMigrationBuilderProvider,
      )(widget.account, labels, _finishLegacy);
    } else if (_legacy == false) {
      child = AccountProtectionPage(account: widget.account);
    } else {
      child = Scaffold(
        appBar: AppBar(
          title: Text(
            _text(
              context,
              'Priprava zaščite računa',
              'Account protection preparation',
            ),
          ),
        ),
        body: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              if (_busy) const LinearProgressIndicator(),
              Text(
                _failed
                    ? _text(
                        context,
                        'Seznama prostorov še ni bilo mogoče preveriti. Podatki ostanejo ohranjeni.',
                        'The list of spaces could not yet be verified. Data is retained.',
                      )
                    : _text(
                        context,
                        'Preverjanje prostorov …',
                        'Checking spaces …',
                      ),
              ),
              if (_failed)
                FilledButton(
                  onPressed: _busy ? null : _load,
                  key: const ValueKey('account-protection-entry-continue'),
                  child: Text(_text(context, 'Nadaljuj', 'Continue')),
                ),
            ],
          ),
        ),
      );
    }
    return SharingSessionBoundary(guard: _guard, child: child);
  }
}

String _text(BuildContext context, String sl, String en) =>
    Localizations.localeOf(context).languageCode == 'sl' ? sl : en;

const _keyReasons = {
  'scope_key_recovery_required',
  'scope_history_keys_pending',
  'scope_keys_pending',
  'recovery_historical_key_pending',
  'scope_observation_bundle_missing',
  'restore_historical_file_required',
};
const _historyReviewReasons = {
  'scope_review_confirmation_required',
  'scope_review_changed',
  'scope_review_policy_projection_pending',
  'scope_rotation_required',
  'scope_reauthorization_required',
  'scope_rotation_reauthorization_required',
  'finance_inventory_review_required',
};

class AccountProtectionPage extends ConsumerStatefulWidget {
  const AccountProtectionPage({required this.account, super.key});
  final AccountCryptoV2Workflow account;
  @override
  ConsumerState<AccountProtectionPage> createState() =>
      _AccountProtectionPageState();
}

class _AccountProtectionPageState extends ConsumerState<AccountProtectionPage> {
  late final AccountProtectionPageController _controller;
  late final SharingSessionGuard _guard;
  bool _initialized = false, _busy = false, _accepted = false;
  bool _fileNeeded = false;
  int _pause = 0;
  String? _reason;
  Map<String, dynamic>? _unavailable;
  List<String> _unavailableLabels = [];
  List<({String scopeId, String label, String reason, bool canManage})>
  _actions = [];

  bool get _current =>
      mounted &&
      _guard.isCurrent &&
      _controller.isCurrent(
        ref.read(collaborationProvider).valueOrNull?.session,
      );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;
    _guard = SharingSessionGuard(context, ref);
    _controller = ref.read(accountProtectionPageControllerProvider)(
      widget.account,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_current) unawaited(_continue());
    });
  }

  @override
  void dispose() {
    if (_initialized) _controller.close();
    super.dispose();
  }

  String _safeReason(Object error) => safeSyncFailureReason(switch (error) {
    CryptoAuthorityPending() => error.reason,
    CryptoDirectoryException() => error.code,
    CollaborationException() => error.code,
    _ => 'unknown',
  });

  Future<String> _label(String scope) async {
    try {
      final label = await _controller.scopeLabel(scope);
      if (label?.isNotEmpty == true) return label!;
    } catch (_) {
      // An absent local name does not alter account protection or reveal IDs.
    }
    if (!mounted || !_current) return '';
    return _text(context, 'Prostor', 'Space');
  }

  void _clearResult() {
    _reason = null;
    _actions = [];
    _unavailable = null;
    _unavailableLabels = [];
    _accepted = false;
    _fileNeeded = false;
    _pause = 0;
  }

  Future<void> _recordFailure(Object error) async {
    if (!_current) return;
    final reason = _safeReason(error);
    final actions =
        <({String scopeId, String label, String reason, bool canManage})>[];
    if (reason == 'protection_scope_action_required') {
      try {
        final pending = await _controller.pendingScopeActions();
        if (!_current) return;
        for (final action in pending) {
          final scope = action['scopeId'];
          if (scope is! String || actions.any((a) => a.scopeId == scope)) {
            continue;
          }
          final label = await _label(scope);
          if (!_current) return;
          actions.add((
            scopeId: scope,
            label: label,
            reason: safeSyncFailureReason(
              AccountProtectionReady.safeScopeActionReason(action['reason']),
            ),
            canManage: action['canManage'] == true,
          ));
        }
      } catch (_) {
        // Keep the original safe failure when optional local details fail.
      }
    }
    var fileNeeded =
        _keyReasons.contains(reason) ||
        actions.any((a) => _keyReasons.contains(a.reason));
    try {
      fileNeeded |= await _controller.hasIncompleteScopeRecovery();
    } catch (_) {
      // Unknown evidence must not invent a need for a recovery file.
    }
    if (!_current) return;
    setState(() {
      _reason = reason;
      _actions = actions;
      _fileNeeded = fileNeeded;
      _pause = 0;
    });
  }

  Future<void> _attempt({Map<String, dynamic>? reviewedUnavailable}) async {
    if (!_current) return;
    if (reviewedUnavailable == null) {
      final review = await _controller.unavailableReview();
      if (!_current) return;
      if (review != null) {
        final labels = <String>[];
        final missing = review['missingScopes'];
        if (missing is List) {
          for (final item in missing) {
            if (item is Map && item['scopeId'] is String) {
              labels.add(await _label(item['scopeId'] as String));
              if (!_current) return;
            }
          }
        }
        setState(() {
          _unavailable = review;
          _unavailableLabels = labels;
        });
        return;
      }
    }
    if (!_current) return;
    await _controller.complete(
      reviewedUnavailable: reviewedUnavailable,
      onPause: (seconds) {
        if (_current) setState(() => _pause = seconds);
      },
    );
    if (!mounted || !_current) return;
    final session = _guard.session!;
    refreshAccountSummaries(
      ProviderScope.containerOf(context, listen: false),
      partition: session.partition,
      deviceId: session.deviceId,
    );
    Navigator.of(context).pop(true);
  }

  Future<void> _continue() async {
    if (_busy || !_current || (_unavailable != null && !_accepted)) return;
    final reviewed = _accepted ? _unavailable : null;
    setState(() {
      _busy = true;
      _clearResult();
    });
    try {
      await _attempt(reviewedUnavailable: reviewed);
    } catch (error) {
      await _recordFailure(error);
    } finally {
      if (_current) setState(() => _busy = false);
    }
  }

  Future<void> _importFile() async {
    if (_busy || !_current || !_fileNeeded) return;
    setState(() => _busy = true);
    Uint8List? file;
    try {
      file = await ref.read(recoveryFileIoProvider).pick();
      if (file == null || !_current) return;
      if (file.isEmpty || file.length > RecoveryFileIo.maxBytes) {
        throw const FormatException('recovery_file_size');
      }
      setState(_clearResult);
      try {
        await _controller.restoreScopesFromFile(file);
      } on CryptoScopeRecoveryIncomplete {
        // Partial progress retains the recovery journal. Recheck the entire
        // account to collect its current blockers; completion still owns all
        // readiness checks and cannot treat an incomplete import as success.
      }
      if (!_current) return;
      await _attempt();
    } catch (error) {
      await _recordFailure(error);
    } finally {
      file?.fillRange(0, file.length, 0);
      if (_current) setState(() => _busy = false);
    }
  }

  Future<void> _reviewScope(
    ({String scopeId, String label, String reason, bool canManage}) action,
  ) async {
    if (_busy ||
        !_current ||
        !action.canManage ||
        !_historyReviewReasons.contains(action.reason)) {
      return;
    }
    final reviewPage = ref.read(accountProtectionScopeReviewBuilderProvider)(
      widget.account,
      action.scopeId,
      action.label,
    );
    if (!_current) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) =>
            SharingSessionBoundary(guard: _guard, child: reviewPage),
      ),
    );
    if (_current) await _continue();
  }

  Future<void> _details() async {
    if (!_current) return;
    final snapshot = syncFailureDiagnosticsJson([
      if (_reason != null)
        SyncFailureDetails(
          stage: SyncFailureStage.completion,
          occurredAt: null,
          reason: _reason!,
        ),
      for (final action in _actions)
        SyncFailureDetails(
          stage: SyncFailureStage.completion,
          occurredAt: null,
          reason: action.reason,
        ),
    ]);
    await showDialog<void>(
      context: context,
      builder: (dialog) => SharingSessionBoundary(
        guard: _guard,
        child: AlertDialog(
          title: Text(_text(dialog, 'Podrobnosti', 'Details')),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _text(
                    dialog,
                    'Kopija vsebuje le korak in varne oznake vzrokov. Imena, identifikatorji in vsebina niso vključeni.',
                    'The copy contains only the stage and safe reason codes. Names, identifiers and contents are excluded.',
                  ),
                ),
                const SizedBox(height: 12),
                SelectableText(
                  snapshot,
                  key: const ValueKey('account-protection-safe-details'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              key: const ValueKey('account-protection-copy-details'),
              onPressed: () async {
                if (!_current) return;
                await Clipboard.setData(ClipboardData(text: snapshot));
              },
              child: Text(_text(dialog, 'Kopiraj', 'Copy')),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dialog),
              child: Text(dialog.l10n.close),
            ),
          ],
        ),
      ),
    );
  }

  String _explanation(String reason, {bool? canManage}) {
    if (reason == 'crypto_scope_recovery_incomplete') {
      return _text(
        context,
        'Preverjanje obnovljenih prostorov še ni dokončano. Nekatera dokazila ali podatki še čakajo; že obnovljeni podatki ostanejo ohranjeni.',
        'Verification of recovered spaces is not yet complete. Some evidence or data is still pending; already recovered data is retained.',
      );
    }
    if (_keyReasons.contains(reason)) {
      return _text(
        context,
        'Za del podatkov še manjkajo preverjeni ključi. Obstoječo obnovitveno datoteko izberi enkrat za celoten račun.',
        'Verified keys are still missing for some data. Select the existing recovery file once for the whole account.',
      );
    }
    if (const {
      'finance_key_contribution_required',
      'scope_successor_key_contribution_required',
      'scope_key_contributor_required',
    }.contains(reason)) {
      return _text(
        context,
        'Čakamo na prispevek sodelavca z ustreznimi ključi. Podatki ostanejo ohranjeni.',
        'A contribution from a collaborator with the required keys is pending. Data is retained.',
      );
    }
    if (_historyReviewReasons.contains(reason)) {
      return canManage == false
          ? _text(
              context,
              'Za nadaljevanje je potreben pregled upravitelja tega prostora.',
              'A manager of this space must review protection before continuing.',
            )
          : _text(
              context,
              'Zgodovina ali sprememba zaščite zahteva izrecen pregled. Pred potrditvijo preglej prikazano vsebino.',
              'History or a protection change needs explicit review. Inspect the displayed contents before confirming.',
            );
    }
    if (reason == 'protection_scope_action_required') {
      return _text(
        context,
        'Nekateri prostori še potrebujejo spodaj prikazana dejanja. Zaščita računa še ni dokončana.',
        'Some spaces still need the actions shown below. Account protection is not yet complete.',
      );
    }
    if (const {
      'network',
      'network_error',
      'network_unavailable',
      'timeout',
      'server_unavailable',
    }.contains(reason)) {
      return _text(
        context,
        'Povezava ni uspela. Preveri omrežje in izberi Nadaljuj.',
        'The connection failed. Check your network and choose Continue.',
      );
    }
    return _text(
      context,
      'Preverjanja še ni bilo mogoče varno dokončati. Podatki in čakajoče spremembe ostanejo ohranjeni. Izberi Nadaljuj za nov poskus.',
      'Verification could not yet be completed safely. Data and pending changes are retained. Choose Continue to retry.',
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(collaborationProvider, (_, __) {
      if (!_current) _controller.close();
    });
    return SharingSessionBoundary(
      guard: _guard,
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            _text(
              context,
              'Priprava zaščite računa',
              'Account protection preparation',
            ),
          ),
        ),
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 700),
              child: ListView(
                padding: const EdgeInsets.all(24),
                children: [
                  Text(
                    _text(
                      context,
                      'Preverimo vse prostore tega računa z obstoječimi zaupanja vrednimi ključi. Morebitni pregled zgodovine potrdiš sam.',
                      'We check all spaces in this account using existing trusted keys. You explicitly confirm any history review.',
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (_busy) ...[
                    const LinearProgressIndicator(),
                    const SizedBox(height: 12),
                    Text(
                      _pause > 0
                          ? _text(
                              context,
                              'Strežnik začasno omejuje zahteve. Nadaljevanje čez največ $_pause sekund.',
                              'The server is temporarily limiting requests. Resuming in at most $_pause seconds.',
                            )
                          : _text(
                              context,
                              'Preverjanje zaščite …',
                              'Checking protection …',
                            ),
                    ),
                  ],
                  if (_reason != null) ...[
                    const SizedBox(height: 16),
                    Text(
                      _explanation(_reason!),
                      key: const ValueKey('account-protection-result'),
                    ),
                  ],
                  if (_unavailable != null) ...[
                    const SizedBox(height: 16),
                    Text(context.l10n.cryptoUnavailableTitle),
                    Text(context.l10n.cryptoUnavailableExplanation),
                    for (final label in _unavailableLabels) Text('• $label'),
                    CheckboxListTile(
                      key: const ValueKey(
                        'account-protection-unavailable-consent',
                      ),
                      value: _accepted,
                      onChanged: _busy
                          ? null
                          : (value) =>
                                setState(() => _accepted = value == true),
                      title: Text(context.l10n.cryptoUnavailableConfirm),
                    ),
                  ],
                  for (final action in _actions) ...[
                    const SizedBox(height: 16),
                    Text(
                      action.label,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    Text(
                      _explanation(action.reason, canManage: action.canManage),
                    ),
                    if (action.canManage &&
                        _historyReviewReasons.contains(action.reason))
                      OutlinedButton(
                        key: ValueKey(
                          'account-protection-review-${action.scopeId}',
                        ),
                        onPressed: _busy ? null : () => _reviewScope(action),
                        child: Text(
                          _text(
                            context,
                            'Pregled zaščite',
                            'Review protection',
                          ),
                        ),
                      ),
                  ],
                  if (_fileNeeded) ...[
                    const SizedBox(height: 16),
                    Text(
                      _text(
                        context,
                        'Obnovitvena datoteka se uporabi za vse prostore tega računa. Ne začenja nove obnove računa.',
                        'The recovery file is used for all spaces in this account. It does not start a new account recovery.',
                      ),
                    ),
                    OutlinedButton(
                      key: const ValueKey('account-protection-import-file'),
                      onPressed: _busy ? null : _importFile,
                      child: Text(
                        _text(
                          context,
                          'Izberi obnovitveno datoteko',
                          'Select recovery file',
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  FilledButton(
                    key: const ValueKey('account-protection-continue'),
                    onPressed: _busy || (_unavailable != null && !_accepted)
                        ? null
                        : _continue,
                    child: Text(_text(context, 'Nadaljuj', 'Continue')),
                  ),
                  if (_reason != null)
                    TextButton(
                      key: const ValueKey('account-protection-details'),
                      onPressed: _details,
                      child: Text(_text(context, 'Podrobnosti', 'Details')),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
