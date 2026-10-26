import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/organizer/data/local_vault.dart';
import 'package:kanban/l10n/app_localizations.dart';
import 'package:kanban/organizer/platform/recovery/recovery_file_io.dart';
import 'package:kanban/organizer/presentation/recovery/local_vault_bootstrap.dart';
import 'package:kanban/organizer/state/app_preferences_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Vault implements LocalVaultService {
  _Vault(this.status);
  final LocalVaultStatus status;
  @override
  Future<LocalVaultStatus> inspect() async => status;
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('No recovery, migration or data mutation allowed');
}

class _Files extends RecoveryFileIo {
  _Files({this.fail = false});
  final bool fail;
  @override
  Future<void> cleanup() async {
    if (fail) throw const LocalVaultException('vault_io');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('No file action allowed');
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  Future<void> pump(
    WidgetTester tester,
    LocalVaultStatus status, {
    String language = 'en',
    bool failCleanup = false,
  }) async {
    SharedPreferences.setMockInitialValues({'app_locale_code': language});
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          localVaultServiceProvider.overrideWith((ref) async => _Vault(status)),
          recoveryFileIoProvider.overrideWithValue(_Files(fail: failCleanup)),
          appLocaleProvider.overrideWith((ref) => Locale(language)),
        ],
        child: const LocalVaultBootstrap(
          child: MaterialApp(home: Text('existing encrypted workspace')),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  for (final language in ['en', 'sl']) {
    testWidgets(
      'new retained-only startup opens with persistent $language notice',
      (tester) async {
        await pump(
          tester,
          const LocalVaultStatus(
            LocalVaultPhase.cleanupPending,
            retainedCopiesOnly: true,
            errorCode: 'vault_historical_exports_retained',
          ),
          language: language,
        );
        expect(find.text('existing encrypted workspace'), findsOneWidget);
        expect(
          find.byKey(const ValueKey('vault_continue_cleanup')),
          findsNothing,
        );
        final banner = tester.widget<Banner>(
          find.byKey(const ValueKey('vault_retained_copies_notice')),
        );
        expect(
          banner.message,
          language == 'sl' ? 'Kopije' : 'Copies',
        );
        expect(find.byType(Semantics), findsWidgets);
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets('new compact retained banner fits at large app text scale', (
    tester,
  ) async {
    tester.platformDispatcher.textScaleFactorTestValue = 2.4;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await pump(
      tester,
      const LocalVaultStatus(
        LocalVaultPhase.cleanupPending,
        retainedCopiesOnly: true,
      ),
      language: 'sl',
    );
    final banner = tester.widget<Banner>(
      find.byKey(const ValueKey('vault_retained_copies_notice')),
    );
    for (final language in ['en', 'sl']) {
      final text = lookupAppLocalizations(
        Locale(language),
      ).recoveryHistoricalExportsLabel;
      // Flutter BannerPainter lays out a fixed 80 px diagonal ribbon using
      // its explicit textStyle, independently of the app's larger text scale.
      final painter = TextPainter(
        text: TextSpan(text: text, style: banner.textStyle),
        textDirection: TextDirection.ltr,
      )..layout(minWidth: 80, maxWidth: 80);
      expect(painter.computeLineMetrics(), hasLength(1));
      expect(painter.height, lessThanOrEqualTo(13));
      painter.dispose();
    }
    expect(tester.takeException(), isNull);
    expect(find.text('existing encrypted workspace'), findsOneWidget);
  });
  testWidgets(
    'new residual status cannot bypass a bootstrap operation failure',
    (tester) async {
      await pump(
        tester,
        const LocalVaultStatus(
          LocalVaultPhase.cleanupPending,
          retainedCopiesOnly: true,
        ),
        failCleanup: true,
      );
      expect(find.text('existing encrypted workspace'), findsNothing);
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('vault_error')),
        200,
      );
      expect(find.byKey(const ValueKey('vault_error')), findsOneWidget);
    },
  );
  testWidgets('new retained flag never opens recovery or real cleanup', (
    tester,
  ) async {
    for (final status in [
      const LocalVaultStatus(
        LocalVaultPhase.cleanupPending,
        errorCode: 'vault_historical_exports_retained',
      ),
      const LocalVaultStatus(
        LocalVaultPhase.recoveryRequired,
        retainedCopiesOnly: true,
      ),
      const LocalVaultStatus(
        LocalVaultPhase.migrationPending,
        retainedCopiesOnly: true,
      ),
    ]) {
      await pump(tester, status);
      expect(find.text('existing encrypted workspace'), findsNothing);
      expect(
        find.byKey(const ValueKey('vault_retained_copies_notice')),
        findsNothing,
      );
      await tester.pumpWidget(const SizedBox());
    }
  });
}
