import 'dart:ui' show ImageByteFormat;
import 'dart:typed_data';
import 'dart:io';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart' show FontLoader;
import 'package:kanban/organizer/data/e2ee/account_crypto_v2_workflow.dart';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/l10n/l10n.dart';
import 'package:kanban/organizer/data/e2ee/account_crypto_repository.dart';
import 'package:kanban/organizer/platform/recovery/recovery_file_io.dart';
import 'package:kanban/organizer/presentation/backup/backup_file_io.dart';
import 'package:kanban/organizer/presentation/recovery/account_crypto_wizard.dart';
import 'package:kanban/organizer/presentation/shared/sharing_auth.dart';
import 'package:kanban/organizer/state/account_crypto_provider.dart';
import 'package:kanban/organizer/state/collaboration_provider.dart';

import '../sharing_ui_fixture.dart';

class _Workflow implements AccountCryptoWorkflow {
  bool initialized = false, failVerification = false, failResume = false;
  String phase = 'locked';
  int verifications = 0, recoveries = 0, resumes = 0;
  @override
  Future<Map<String, dynamic>> status() async => {'initialized': initialized};
  @override
  Future<String> localPhase() async => phase;
  @override
  Future<Uint8List> prepareRecoveryFile() async {
    phase = 'prepared';
    return Uint8List.fromList([1, 2, 3]);
  }

  @override
  Future<void> verifyAndInitialize(Uint8List externalFile) async {
    verifications++;
    if (failVerification) throw const FormatException('never show secret/path');
    initialized = true;
    phase = 'ready';
  }

  @override
  Future<void> recover(Uint8List externalFile) async {
    recoveries++;
    phase = 'ready';
  }

  @override
  Future<void> resume() async {
    resumes++;
    if (failResume)
      throw const AccountCryptoException('crypto_generation_conflict');
    phase = 'ready';
  }
}

class _RebindWorkflow extends _Workflow implements AccountCryptoV2Workflow {
  bool scopePending = false;
  int scopeRestores = 0;
  @override
  Future<bool> hasIncompleteScopeRecovery() async => scopePending;
  @override
  Future<void> restoreScopesFromFile(Uint8List file) async {
    scopeRestores++;
    scopePending = false;
  }

  @override
  Future<bool> canRebindLocalDevice() async => true;
  @override
  Future<void> rebindLocalDevice() async {
    phase = 'ready';
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Files extends RecoveryFileIo {
  Uint8List? file;
  bool? accountOnly;
  int shares = 0;
  @override
  bool get canShare => true;
  @override
  Future<void> share(
    Uint8List bytes,
    String title, {
    bool accountOnly = false,
  }) async {
    shares++;
    this.accountOnly = accountOnly;
  }

  @override
  Future<BackupSaveStatus> save(
    Uint8List bytes,
    String title, {
    bool accountOnly = false,
  }) async {
    this.accountOnly = accountOnly;
    return BackupSaveStatus.cancelled;
  }

  @override
  Future<Uint8List?> pick() async => file;
}

void main() {
  Future<void> pump(
    WidgetTester tester,
    _Workflow workflow,
    _Files files, {
    Locale locale = const Locale('en'),
    bool largeText = false,
  }) async {
    if (largeText) {
      await tester.runAsync(() async {
        final sdk = Platform.resolvedExecutable.split('/bin/cache/').first;
        final bytes = await File(
          '$sdk/bin/cache/artifacts/material_fonts/Roboto-Regular.ttf',
        ).readAsBytes();
        await (FontLoader(
          'Roboto',
        )..addFont(Future.value(ByteData.sublistView(bytes)))).load();
        final icons = await File(
          '$sdk/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
        ).readAsBytes();
        await (FontLoader(
          'MaterialIcons',
        )..addFont(Future.value(ByteData.sublistView(icons)))).load();
      });
    }
    await tester.pumpWidget(
      ProviderScope(
        overrides: [recoveryFileIoProvider.overrideWithValue(files)],
        child: MaterialApp(
          locale: locale,
          theme: ThemeData(fontFamily: largeText ? 'Roboto' : null),
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(largeText ? 2 : 1)),
            child: child!,
          ),
          home: RepaintBoundary(
            key: const ValueKey('crypto_capture'),
            child: AccountCryptoWizard(workflow: workflow),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'partial scope restore stays explicit; canceled FILE and retry never recover the account again',
    (tester) async {
      final flow = _RebindWorkflow()
        ..initialized = true
        ..phase = 'ready'
        ..scopePending = true;
      final files = _Files();
      await pump(tester, flow, files);
      expect(
        find.byKey(const ValueKey('account_crypto_scopes_pending')),
        findsOneWidget,
      );
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('account_crypto_scopes_partial')),
        200,
      );
      expect(
        find.byKey(const ValueKey('account_crypto_scopes_partial')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('account_crypto_prepared')),
        findsNothing,
      );
      final retry = find.byKey(const ValueKey('account_crypto_scopes_retry'));
      await tester.ensureVisible(retry);
      await tester.tap(retry);
      await tester.pumpAndSettle();
      expect(flow.scopeRestores, 0);
      expect(flow.recoveries, 0);
      expect(flow.scopePending, isTrue);
      expect(
        find.byKey(const ValueKey('account_crypto_prepared')),
        findsNothing,
      );
      files.file = Uint8List.fromList([1, 2, 3]);
      await tester.ensureVisible(retry);
      await tester.tap(retry);
      await tester.pumpAndSettle();
      expect(flow.scopeRestores, 1);
      expect(flow.recoveries, 0);
      expect(flow.scopePending, isFalse);
      expect(
        find.byKey(const ValueKey('account_crypto_prepared')),
        findsOneWidget,
      );
      expect(flow.phase, 'ready');
      expect(tester.takeException(), isNull);
    },
  );

  for (final locale in ['sl', 'en']) {
    testWidgets(
      '320px 2x $locale account save, reimport, lost ACK and local-device rebind remain reachable',
      (tester) async {
        tester.view.physicalSize = const Size(320, 640);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        for (final stage in ['save', 'prepared', 'pending', 'rebind']) {
          final flow = stage == 'rebind'
              ? (_RebindWorkflow()
                  ..initialized = true
                  ..phase = 'recoveryRequired')
              : (_Workflow()
                  ..phase = (stage == 'save' ? 'locked' : stage)
                  ..initialized = (stage == 'pending'));
          await pump(
            tester,
            flow,
            _Files(),
            locale: Locale(locale),
            largeText: true,
          );
          expect(tester.takeException(), isNull, reason: stage);
          final key = stage == 'save'
              ? 'account_crypto_save'
              : stage == 'prepared'
              ? 'account_crypto_verify'
              : stage == 'pending'
              ? 'account_crypto_resume'
              : 'account_crypto_local_approval';
          final button = find.byKey(ValueKey(key));
          await tester.scrollUntilVisible(button, 180, maxScrolls: 50);
          await tester.ensureVisible(button);
          await tester.pumpAndSettle();
          expect(button.hitTestable(), findsOneWidget, reason: stage);
          final boundary = tester.renderObject<RenderRepaintBoundary>(
            find.byKey(const ValueKey('crypto_capture')),
          );
          await tester.runAsync(() async {
            final image = await boundary.toImage(pixelRatio: 1);
            try {
              final bytes = await image.toByteData(format: ImageByteFormat.png);
              final out = File(
                'build/qa/e2ee-source-upgrade/ux-$locale-account-$stage.png',
              );
              await out.parent.create(recursive: true);
              await out.writeAsBytes(bytes!.buffer.asUint8List());
            } finally {
              image.dispose();
            }
          });
          await tester.pumpWidget(const SizedBox());
        }
      },
    );
  }

  testWidgets(
    'system share keeps account setup unverified until external reimport',
    (tester) async {
      final workflow = _Workflow(), files = _Files();
      await pump(tester, workflow, files);
      final share = find.byKey(const ValueKey('account_crypto_share'));
      await tester.ensureVisible(share);
      await tester.tap(share);
      await tester.pumpAndSettle();
      expect(files.shares, 1);
      expect(files.accountOnly, true);
      expect(workflow.phase, 'prepared');
      expect(workflow.verifications, 0);
      expect(workflow.initialized, false);
      expect(
        find.byKey(const ValueKey('account_crypto_verify')),
        findsOneWidget,
      );
    },
  );
  testWidgets(
    'failed pending request requires another external file selection for conflict retry',
    (tester) async {
      final workflow = _Workflow()
        ..initialized = true
        ..phase = 'verified'
        ..failResume = true;
      final files = _Files()..file = Uint8List.fromList([1]);
      await pump(tester, workflow, files);
      final resume = find.byKey(const ValueKey('account_crypto_resume'));
      await tester.scrollUntilVisible(resume, 200);
      await tester.ensureVisible(resume);
      await tester.pumpAndSettle();
      await tester.tap(resume);
      await tester.pumpAndSettle();
      expect(workflow.recoveries, 0);
      final rebase = find.byKey(const ValueKey('account_crypto_rebase'));
      await tester.scrollUntilVisible(rebase, 200);
      await tester.ensureVisible(rebase);
      await tester.pumpAndSettle();
      await tester.tap(rebase);
      await tester.pumpAndSettle();
      await tester.tap(
        find.text('Recover account and revoke previous devices'),
      );
      await tester.pumpAndSettle();
      expect(workflow.recoveries, 1);
      expect(files.file, [0]);
    },
  );

  testWidgets(
    'preview login offers account wizard and back preserves the authenticated account',
    (tester) async {
      final controller = SharingUiController(initial: CollaborationState());
      final workflow = _Workflow();
      var connected = 0;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            collaborationProvider.overrideWith(() => controller),
            accountCryptoPreviewProvider.overrideWith((ref) async => workflow),
          ],
          child: MaterialApp(
            locale: const Locale('en'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Consumer(
              builder: (context, ref, child) {
                ref.watch(collaborationProvider);
                return Scaffold(
                  body: SingleChildScrollView(
                    child: SharingAuthPanel(
                      initialServer: 'https://sharing.example.test',
                      loginOnly: true,
                      onStart: () {},
                      onConnected: () => connected++,
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('sharing-username')),
        'first',
      );
      await tester.enterText(
        find.byKey(const ValueKey('sharing-password')),
        'synthetic-password',
      );
      final connect = find.byKey(const ValueKey('sharing-connect'));
      await tester.ensureVisible(connect);
      await tester.pumpAndSettle();
      await tester.tap(connect);
      await tester.pumpAndSettle();
      expect(find.byType(AccountCryptoWizard), findsOneWidget);
      expect(controller.state.valueOrNull?.session?.username, 'first');
      expect(workflow.verifications, 0);
      expect(connected, 0);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(connected, 1);
      expect(controller.state.valueOrNull?.session?.username, 'first');
      expect(workflow.verifications, 0);
    },
  );

  testWidgets(
    'save cancellation cannot activate account; external reimport explicitly prepares keys',
    (tester) async {
      final workflow = _Workflow();
      final files = _Files();
      await pump(tester, workflow, files);
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('account_crypto_save')),
        200,
      );
      await tester.ensureVisible(
        find.byKey(const ValueKey('account_crypto_save')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('account_crypto_save')));
      await tester.pumpAndSettle();
      expect(files.accountOnly, true);
      expect(workflow.verifications, 0);
      expect(workflow.initialized, false);
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('account_crypto_verify')),
        200,
      );
      await tester.ensureVisible(
        find.byKey(const ValueKey('account_crypto_verify')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('account_crypto_verify')));
      await tester.pumpAndSettle();
      expect(workflow.verifications, 0);
      files.file = Uint8List.fromList([1, 2, 3]);
      await tester.ensureVisible(
        find.byKey(const ValueKey('account_crypto_verify')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('account_crypto_verify')));
      await tester.pumpAndSettle();
      expect(workflow.verifications, 1);
      expect(files.file, [0, 0, 0]);
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('account_crypto_prepared')),
        200,
      );
      expect(
        find.textContaining('Shared spaces have not been switched'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'existing account offers recovery without creating a new identity',
    (tester) async {
      final workflow = _Workflow()..initialized = true;
      final files = _Files()..file = Uint8List.fromList([1]);
      await pump(tester, workflow, files);
      expect(find.byKey(const ValueKey('account_crypto_save')), findsNothing);
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('account_crypto_recover')),
        200,
      );
      await tester.ensureVisible(
        find.byKey(const ValueKey('account_crypto_recover')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('account_crypto_recover')));
      await tester.pumpAndSettle();
      expect(workflow.recoveries, 0);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(workflow.recoveries, 0);
      expect(files.file, [1]);
      await tester.tap(find.byKey(const ValueKey('account_crypto_recover')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.text('Recover account and revoke previous devices'),
      );
      await tester.pumpAndSettle();
      expect(workflow.recoveries, 1);
      expect(workflow.verifications, 0);
    },
  );

  testWidgets('unknown ACK offers resume of the persisted request', (
    tester,
  ) async {
    final workflow = _Workflow()
      ..initialized = true
      ..phase = 'verified';
    await pump(tester, workflow, _Files(), locale: const Locale('sl'));
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('account_crypto_resume')),
      200,
    );
    expect(find.text('Preveri in nadaljuj čakajočo zahtevo'), findsOneWidget);
    await tester.ensureVisible(
      find.byKey(const ValueKey('account_crypto_resume')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('account_crypto_resume')));
    await tester.pumpAndSettle();
    expect(workflow.resumes, 1);
    expect(workflow.verifications, 0);
  });

  testWidgets(
    'file verification failure preserves pending setup and hides raw errors',
    (tester) async {
      final workflow = _Workflow()
        ..phase = 'prepared'
        ..failVerification = true;
      final files = _Files()..file = Uint8List.fromList([1]);
      await pump(tester, workflow, files);
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('account_crypto_verify')),
        200,
      );
      await tester.ensureVisible(
        find.byKey(const ValueKey('account_crypto_verify')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('account_crypto_verify')));
      await tester.pumpAndSettle();
      expect(workflow.phase, 'prepared');
      expect(workflow.initialized, false);
      expect(find.textContaining('never show secret/path'), findsNothing);
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('account_crypto_error')),
        -200,
      );
      expect(
        find.byKey(const ValueKey('account_crypto_error')),
        findsOneWidget,
      );
    },
  );
}
