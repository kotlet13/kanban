import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/l10n/app_localizations.dart';
import 'package:kanban/organizer/data/e2ee/account_crypto_v2_workflow.dart';
import 'package:kanban/organizer/data/e2ee/crypto_scope_observations.dart';
import 'package:kanban/organizer/data/e2ee/crypto_sync_repository.dart';
import 'package:kanban/organizer/platform/recovery/recovery_file_io.dart';
import 'package:kanban/organizer/presentation/recovery/account_protection_page.dart';
import 'package:kanban/organizer/presentation/recovery/scope_recovery_page.dart';
import 'package:kanban/organizer/state/account_summary_refresh_provider.dart';
import 'package:kanban/organizer/state/collaboration_provider.dart';

import '../sharing_ui_fixture.dart';

class _Account implements AccountCryptoV2Workflow {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Driver implements AccountProtectionPageController {
  bool closed = false, legacy = false, incomplete = false;
  int completes = 0, reviews = 0, actionReads = 0, catalogReads = 0;
  final reviewed = <Map<String, dynamic>?>[];
  final imported = <Uint8List>[];
  final failures = <Object?>[];
  Map<String, dynamic>? unavailable;
  List<Map<String, dynamic>> actions = [];
  final labels = <String, String>{};
  Object? importFailure;
  Future<void> Function(void Function(int)? onPause)? completing;
  Future<bool> Function()? catalog;

  @override
  bool isCurrent(AccountSession? session) =>
      !closed &&
      session?.partition == sharingSession().partition &&
      session?.deviceId == sharingSession().deviceId;
  @override
  Future<bool> needsLegacyMigration() async {
    catalogReads++;
    return await catalog?.call() ?? legacy;
  }

  @override
  Future<Map<String, dynamic>?> unavailableReview() async {
    reviews++;
    return unavailable;
  }

  @override
  Future<void> complete({
    Map<String, dynamic>? reviewedUnavailable,
    void Function(int)? onPause,
  }) async {
    completes++;
    reviewed.add(reviewedUnavailable);
    if (completing != null) return completing!(onPause);
    if (failures.isNotEmpty) {
      final failure = failures.removeAt(0);
      if (failure != null) throw failure;
    }
  }

  @override
  Future<List<Map<String, dynamic>>> pendingScopeActions() async {
    actionReads++;
    return actions;
  }

  @override
  Future<bool> hasIncompleteScopeRecovery() async => incomplete;
  @override
  Future<void> restoreScopesFromFile(Uint8List file) async {
    expect(file.any((byte) => byte != 0), isTrue);
    imported.add(file);
    if (importFailure != null) throw importFailure!;
  }

  @override
  Future<String?> scopeLabel(String scopeId) async => labels[scopeId];
  @override
  void close() => closed = true;
}

class _Files extends RecoveryFileIo {
  int picks = 0;
  final selected = Completer<Uint8List?>();
  @override
  Future<Uint8List?> pick() {
    picks++;
    return selected.future;
  }
}

class _Harness {
  bool? result;
  late SharingUiController collaboration;
  late ProviderContainer container;
}

Future<_Harness> _open(
  WidgetTester tester,
  _Driver driver, {
  bool entry = false,
  bool settle = true,
  String locale = 'en',
  _Files? files,
  Widget Function(AccountCryptoV2Workflow, String, String)? scopeBuilder,
  Widget Function(
    AccountCryptoV2Workflow,
    Map<String, String>,
    Future<bool> Function(),
  )?
  legacyBuilder,
}) async {
  final harness = _Harness();
  harness.collaboration = SharingUiController(
    initial: CollaborationState(session: sharingSession()),
  );
  final account = _Account();
  final session = sharingSession();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        collaborationProvider.overrideWith(() => harness.collaboration),
        accountProtectionPageControllerProvider.overrideWithValue(
          (_) => driver,
        ),
        if (files != null) recoveryFileIoProvider.overrideWithValue(files),
        if (scopeBuilder != null)
          accountProtectionScopeReviewBuilderProvider.overrideWithValue(
            scopeBuilder,
          ),
        if (legacyBuilder != null)
          accountProtectionLegacyMigrationBuilderProvider.overrideWithValue(
            legacyBuilder,
          ),
      ],
      child: MaterialApp(
        locale: Locale(locale),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Consumer(
          builder: (context, ref, _) {
            ref.watch(collaborationProvider);
            harness.container = ProviderScope.containerOf(context);
            final refresh = ref.watch(
              accountSummaryRefreshProvider((
                session.partition,
                session.deviceId,
              )),
            );
            return Scaffold(
              body: Column(
                children: [
                  Text('refresh:$refresh'),
                  TextButton(
                    onPressed: () async {
                      harness.result = await Navigator.of(context).push<bool>(
                        MaterialPageRoute(
                          builder: (_) => entry
                              ? AccountProtectionEntry(account: account)
                              : AccountProtectionPage(account: account),
                        ),
                      );
                    },
                    child: const Text('Open protection'),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('Open protection'));
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }
  return harness;
}

Future<void> _tap(WidgetTester tester, String key, {bool settle = true}) async {
  final target = find.byKey(ValueKey(key));
  await tester.ensureVisible(target);
  await tester.tap(target);
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
  }
}

void main() {
  testWidgets(
    'trusted account preparation runs once on open and refreshes only after completion',
    (tester) async {
      final driver = _Driver();
      final harness = await _open(tester, driver);
      expect(driver.completes, 1);
      expect(driver.reviews, 1);
      expect(driver.reviewed, [null]);
      expect(driver.imported, isEmpty);
      expect(harness.result, isTrue);
      expect(find.text('refresh:1'), findsOneWidget);
      expect(driver.closed, isTrue);
    },
  );

  testWidgets(
    'unavailable scopes require explicit consent for the exact review before completion',
    (tester) async {
      final review = <String, dynamic>{
        'missingScopes': [
          {'scopeId': 'private-missing-scope'},
        ],
        'completionRequestId': 'private-request',
      };
      final driver = _Driver()
        ..unavailable = review
        ..labels['private-missing-scope'] = 'Retained private home';
      final harness = await _open(tester, driver, locale: 'sl');
      expect(driver.completes, 0);
      expect(find.text('• Retained private home'), findsOneWidget);
      expect(find.textContaining('private-missing-scope'), findsNothing);
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const ValueKey('account-protection-continue')),
            )
            .onPressed,
        isNull,
      );
      expect(harness.result, isNull);
      await _tap(tester, 'account-protection-unavailable-consent');
      await _tap(tester, 'account-protection-continue');
      expect(driver.completes, 1);
      expect(identical(driver.reviewed.single, review), isTrue);
      expect(harness.result, isTrue);
    },
  );

  testWidgets(
    'all blocked spaces show local names and bounded safe explanations with one account file selector',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final driver = _Driver()
        ..failures.add(
          const CryptoAuthorityPending('protection_scope_action_required'),
        )
        ..actions = [
          {
            'scopeId': 'one',
            'canManage': true,
            'reason': 'scope_review_confirmation_required',
          },
          {
            'scopeId': 'two',
            'canManage': false,
            'reason': 'scope_rotation_required',
          },
          {
            'scopeId': 'three',
            'canManage': true,
            'reason': 'scope_keys_pending',
          },
          {
            'scopeId': 'four',
            'canManage': true,
            'reason': 'finance_key_contribution_required',
          },
        ]
        ..labels.addAll({
          'one': 'Home A',
          'two': 'Home B',
          'three': 'Project C',
          'four': 'Project D',
        });
      final harness = await _open(tester, driver);
      for (final name in ['Home A', 'Home B', 'Project C', 'Project D']) {
        expect(find.text(name, skipOffstage: false), findsOneWidget);
      }
      expect(
        find.byKey(const ValueKey('account-protection-review-one')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('account-protection-review-two')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('account-protection-review-four')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('account-protection-import-file')),
        findsOneWidget,
      );
      expect(find.textContaining('manager of this space'), findsOneWidget);
      expect(
        find.textContaining('contribution from a collaborator'),
        findsOneWidget,
      );
      expect(driver.actionReads, 1);
      expect(harness.result, isNull);
      expect(find.text('refresh:0', skipOffstage: false), findsOneWidget);
    },
  );

  testWidgets(
    'history review opens only on explicit action and returning rescans the account',
    (tester) async {
      var scopeReviews = 0;
      final driver = _Driver()
        ..failures.add(
          const CryptoAuthorityPending('protection_scope_action_required'),
        )
        ..actions = [
          {
            'scopeId': 'private-history',
            'canManage': true,
            'reason': 'scope_review_confirmation_required',
          },
        ]
        ..labels['private-history'] = 'History home';
      final harness = await _open(
        tester,
        driver,
        scopeBuilder: (account, scope, label) {
          scopeReviews++;
          expect(scope, 'private-history');
          expect(label, 'History home');
          return Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Finish scope review'),
              ),
            ),
          );
        },
      );
      expect(scopeReviews, 0);
      await _tap(tester, 'account-protection-review-private-history');
      expect(scopeReviews, 1);
      expect(driver.completes, 1);
      await tester.tap(find.text('Finish scope review'));
      await tester.pumpAndSettle();
      expect(driver.completes, 2);
      expect(harness.result, isTrue);
    },
  );

  testWidgets(
    'one file selection restores the whole account and clears the selected bytes after success',
    (tester) async {
      final bytes = Uint8List.fromList([3, 4, 5]);
      final files = _Files()..selected.complete(bytes);
      final driver = _Driver()
        ..failures.add(const CryptoAuthorityPending('scope_keys_pending'));
      final harness = await _open(tester, driver, files: files);
      await _tap(tester, 'account-protection-import-file');
      expect(files.picks, 1);
      expect(driver.imported, hasLength(1));
      expect(driver.imported.single, same(bytes));
      expect(bytes, everyElement(0));
      expect(driver.completes, 2);
      expect(harness.result, isTrue);
    },
  );

  testWidgets(
    'partial file restoration rescans blockers and never displays ready while recovery remains incomplete',
    (tester) async {
      final bytes = Uint8List.fromList([7, 8, 9]);
      final files = _Files()..selected.complete(bytes);
      final driver = _Driver()
        ..incomplete = true
        ..failures.addAll([
          const CryptoAuthorityPending('scope_keys_pending'),
          const CryptoAuthorityPending('protection_scope_action_required'),
        ])
        ..importFailure = const CryptoScopeRecoveryIncomplete(
          pendingScopes: 2,
          unmatchedOwnAnchors: 1,
          discoveryPending: true,
        )
        ..actions = [
          {
            'scopeId': 'still-blocked',
            'canManage': true,
            'reason': 'scope_review_confirmation_required',
          },
        ]
        ..labels['still-blocked'] = 'Still blocked home';
      final harness = await _open(tester, driver, files: files);
      await _tap(tester, 'account-protection-import-file');
      expect(bytes, everyElement(0));
      expect(driver.completes, 2);
      expect(driver.actionReads, 1);
      expect(find.text('Still blocked home'), findsOneWidget);
      expect(harness.result, isNull);
      expect(find.text('refresh:0', skipOffstage: false), findsOneWidget);
      expect(
        find.byKey(const ValueKey('account-protection-import-file')),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'switching accounts during selection clears bytes and prevents restore and later callbacks',
    (tester) async {
      final files = _Files();
      final driver = _Driver()
        ..failures.add(const CryptoAuthorityPending('scope_keys_pending'));
      final harness = await _open(tester, driver, files: files);
      await _tap(tester, 'account-protection-import-file', settle: false);
      harness.collaboration.switchAccount();
      final bytes = Uint8List.fromList([1, 2, 3]);
      files.selected.complete(bytes);
      await tester.pumpAndSettle();
      expect(bytes, everyElement(0));
      expect(driver.imported, isEmpty);
      expect(driver.completes, 1);
      expect(driver.closed, isTrue);
      expect(harness.result, isNot(isTrue));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'incomplete recovery reports pending evidence without claiming missing keys',
    (tester) async {
      final driver = _Driver()
        ..failures.add(
          const CryptoAuthorityPending('crypto_scope_recovery_incomplete'),
        );
      final harness = await _open(tester, driver);
      expect(
        find.textContaining('Some evidence or data is still pending'),
        findsOneWidget,
      );
      expect(
        find.textContaining('Verified keys are still missing'),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('account-protection-import-file')),
        findsNothing,
      );
      expect(harness.result, isNull);
      expect(find.text('refresh:0', skipOffstage: false), findsOneWidget);
      await _tap(tester, 'account-protection-details');
      final snapshot = tester
          .widget<SelectableText>(
            find.byKey(const ValueKey('account-protection-safe-details')),
          )
          .data!;
      expect(snapshot, contains('crypto_scope_recovery_incomplete'));
    },
  );

  testWidgets(
    'unknown failures export only safe stage and reason and do not invent file recovery',
    (tester) async {
      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied = (call.arguments as Map)['text'] as String;
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      final driver = _Driver()
        ..failures.add(
          const CryptoAuthorityPending(
            'private-scope;token=secret@example.test',
          ),
        );
      await _open(tester, driver);
      expect(
        find.byKey(const ValueKey('account-protection-import-file')),
        findsNothing,
      );
      expect(find.textContaining('secret@'), findsNothing);
      await _tap(tester, 'account-protection-details');
      final snapshot = tester
          .widget<SelectableText>(
            find.byKey(const ValueKey('account-protection-safe-details')),
          )
          .data!;
      await _tap(tester, 'account-protection-copy-details');
      expect(copied, snapshot);
      expect(jsonDecode(copied!), {
        'version': 1,
        'syncFailures': [
          {'stage': 'completion', 'reason': 'unknown'},
        ],
      });
      expect(snapshot, isNot(contains('secret')));
      expect(snapshot, isNot(contains(sharingSession().accountId)));
    },
  );

  testWidgets(
    'closing a paused completion cancels its driver and ignores a late success',
    (tester) async {
      final completed = Completer<void>();
      final driver = _Driver()
        ..completing = (onPause) {
          onPause?.call(5);
          return completed.future;
        };
      final harness = await _open(tester, driver, settle: false);
      expect(find.textContaining('at most 5 seconds'), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(driver.closed, isTrue);
      completed.complete();
      await tester.pumpAndSettle();
      expect(harness.result, isNot(isTrue));
      expect(find.text('refresh:0'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'legacy catalog selects existing migration controls without running account completion',
    (tester) async {
      final driver = _Driver()..legacy = true;
      var migrations = 0;
      await _open(
        tester,
        driver,
        entry: true,
        legacyBuilder: (_, labels, onFinished) {
          migrations++;
          return const Scaffold(body: Text('Existing migration controls'));
        },
      );
      expect(driver.catalogReads, 1);
      expect(driver.completes, 0);
      expect(driver.imported, isEmpty);
      expect(migrations, 1);
      expect(find.text('Existing migration controls'), findsOneWidget);
    },
  );

  testWidgets(
    'unknown catalog stays pending and retry selects account preparation only after a verified crypto catalog',
    (tester) async {
      var catalogAttempts = 0;
      final driver = _Driver()
        ..catalog = () async {
          if (++catalogAttempts == 1) {
            throw StateError('private catalog payload');
          }
          return false;
        };
      final harness = await _open(tester, driver, entry: true);
      expect(driver.completes, 0);
      expect(find.textContaining('could not yet be verified'), findsOneWidget);
      expect(find.textContaining('private catalog payload'), findsNothing);
      await _tap(tester, 'account-protection-entry-continue');
      expect(driver.catalogReads, 2);
      expect(driver.completes, 1);
      expect(harness.result, isTrue);
    },
  );

  test('managed history review suppresses the per-space file selector', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final page =
        container.read(accountProtectionScopeReviewBuilderProvider)(
              _Account(),
              'scope',
              'Local label',
            )
            as ScopeRecoveryPage;
    expect(page.allowFileImport, isFalse);
  });
}
