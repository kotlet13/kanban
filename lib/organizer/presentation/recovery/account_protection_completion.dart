import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../l10n/l10n.dart';
import '../../data/e2ee/account_crypto_v2_workflow.dart';
import '../../data/e2ee/account_protection_ready.dart';
import '../../data/e2ee/crypto_sync_repository.dart'
    show CryptoAuthorityPending;
import 'scope_recovery_page.dart';
import '../../state/account_summary_refresh_provider.dart';

Future<bool> finishAccountProtection(
  BuildContext context,
  AccountCryptoV2Workflow account,
) async {
  final l = context.l10n;
  final service = AccountProtectionReady(account);
  final review = await service.unavailableReview();
  if (review != null) {
    if (!context.mounted) return false;
    final labels = <String>[];
    for (final missing in review['missingScopes'] as List) {
      final rows = await account.store.database.rows(
        'SELECT data FROM scopes WHERE partition=? AND id=?',
        [account.store.partition, missing['scopeId']],
      );
      // Names are read only from the encrypted local cache.
      String? name;
      if (rows.isNotEmpty) {
        final text = rows.single['data'];
        if (text is String) {
          final value = jsonDecode(text);
          if (value is Map && value['name'] is String) name = value['name'];
        }
      }
      labels.add(name?.isNotEmpty == true ? name! : l.cryptoUnavailableSpace);
    }
    if (!context.mounted) return false;
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: Text(context.l10n.cryptoUnavailableTitle),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(context.l10n.cryptoUnavailableExplanation),
              const SizedBox(height: 16),
              for (final label in labels) Text('• $label'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog, false),
            child: Text(context.l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialog, true),
            child: Text(context.l10n.cryptoUnavailableConfirm),
          ),
        ],
      ),
    );
    if (accepted != true) return false;
  }
  if (!context.mounted) {
    service.close();
    return false;
  }
  final pause = ValueNotifier<int>(0);
  final navigator = Navigator.of(context, rootNavigator: true);
  var finished = false, progressClosed = false;
  late DialogRoute<void> progressRoute;
  void closeProgress() {
    if (progressClosed) return;
    progressClosed = true;
    if (progressRoute.isActive && navigator.mounted) {
      navigator.removeRoute(progressRoute);
    }
  }

  progressRoute = DialogRoute<void>(
    context: context,
    builder: (dialog) {
      final sl = Localizations.localeOf(dialog).languageCode == 'sl';
      return AlertDialog(
        title: Text(sl ? 'Dokončanje zaščite' : 'Finishing protection'),
        content: ValueListenableBuilder<int>(
          valueListenable: pause,
          builder: (_, seconds, __) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const LinearProgressIndicator(),
              const SizedBox(height: 16),
              Text(
                seconds > 0
                    ? (sl
                          ? 'Strežnik je začasno omejil zahteve. Nadaljevanje čez največ $seconds sekund. Postopek lahko zaprete in pozneje nadaljujete.'
                          : 'The server temporarily limited requests. Resuming in at most $seconds seconds. You can close this step and resume later.')
                    : (sl
                          ? 'Preverjanje obnovljenih prostorov …'
                          : 'Verifying recovered spaces …'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              service.close();
              closeProgress();
            },
            child: Text(sl ? 'Pozneje' : 'Later'),
          ),
        ],
      );
    },
  );
  final dialog = navigator.push<void>(progressRoute);
  unawaited(
    dialog.then((_) {
      progressClosed = true;
      if (!finished) service.close();
    }),
  );
  Map<String, dynamic>? scopeAction;
  var complete = false;
  try {
    await service.complete(
      reviewedUnavailable: review,
      onPause: (seconds) => pause.value = seconds,
    );
    complete = true;
  } on CryptoAuthorityPending catch (error) {
    if (error.reason == 'protection_scope_action_required') {
      scopeAction = await service.pendingScopeAction();
    } else if (error.reason != 'protection_completion_cancelled') {
      rethrow;
    }
  } finally {
    finished = true;
    closeProgress();
    service.close();
    // The route may still be animating; no later callbacks write this notifier.
    unawaited(dialog.then((_) => pause.dispose()));
  }
  if (scopeAction != null && context.mounted) {
    final action = scopeAction,
        sl = Localizations.localeOf(context).languageCode == 'sl';
    final rows = await account.store.database.rows(
      'SELECT data FROM scopes WHERE partition=? AND id=?',
      [account.store.partition, action['scopeId']],
    );
    final name = rows.isEmpty
        ? null
        : (jsonDecode(rows.single['data'] as String) as Map)['name'];
    if (!context.mounted) return false;
    final open = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: Text(
          name is String && name.isNotEmpty
              ? name
              : (sl ? 'Zaščita prostora' : 'Scope protection'),
        ),
        content: Text(
          action['canManage'] == true
              ? (sl
                    ? 'Obnovljeni podatki ostanejo berljivi. Pred novimi zapisi je potreben pregled zgodovine ali prispevek finančnega sodelavca. Nadaljujte v obstoječem pregledu zaščite.'
                    : 'Recovered data remains readable. New writes need a history review or a finance contributor. Continue in the existing protection review.')
              : (sl
                    ? 'Obnovljeni podatki ostanejo berljivi. Upravitelj skupnega prostora mora posodobiti zaščito za vašo obnovljeno napravo, preden lahko znova zapisujete.'
                    : 'Recovered data remains readable. A shared-space manager must update protection for your recovered device before you can write again.'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog, false),
            child: Text(sl ? 'Pozneje' : 'Later'),
          ),
          if (action['canManage'] == true)
            FilledButton(
              onPressed: () => Navigator.pop(dialog, true),
              child: Text(sl ? 'Pregled zaščite' : 'Review protection'),
            ),
        ],
      ),
    );
    if (open == true && context.mounted) {
      await Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) => ScopeRecoveryPage(
            account: account,
            scopeId: action['scopeId'],
            label: name is String ? name : (sl ? 'Prostor' : 'Space'),
          ),
        ),
      );
    }
  }
  if (complete && context.mounted && account.directory.isCurrent()) {
    refreshAccountSummaries(
      ProviderScope.containerOf(context, listen: false),
      partition: account.store.partition,
      deviceId: account.deviceId,
    );
  }
  return complete;
}
