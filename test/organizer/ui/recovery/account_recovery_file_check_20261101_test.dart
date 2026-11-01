import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/l10n/app_localizations.dart';
import 'package:kanban/organizer/data/e2ee/account_directory_v2.dart';
import 'package:kanban/organizer/data/e2ee/account_crypto_repository.dart';
import 'package:kanban/organizer/data/e2ee/account_crypto_v2_workflow.dart';
import 'package:kanban/organizer/platform/recovery/recovery_file_io.dart';
import 'package:kanban/organizer/presentation/recovery/account_recovery_file_check_card.dart';
import 'package:kanban/organizer/state/account_crypto_provider.dart';
import 'package:kanban/organizer/state/collaboration_provider.dart';

Widget _app(Widget child, {String locale = 'en'}) => MaterialApp(
  locale: Locale(locale),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(body: SingleChildScrollView(child: child)),
);

final _button = find.byKey(const ValueKey('recovery-file-check'));
final _result = find.byKey(const ValueKey('recovery-file-check-result'));

class _Controller extends CollaborationController {
  _Controller(this.session, {this.workflows = const []});
  AccountSession session;
  final List<AccountCryptoWorkflow?> workflows;
  int previewReads = 0;
  @override
  Future<AccountCryptoWorkflow?> accountCryptoPreview() async {
    final index = previewReads++;
    return index < workflows.length ? workflows[index] : null;
  }

  @override
  Future<CollaborationState> build() async =>
      CollaborationState(session: session);
  void replaceSession(AccountSession next) {
    session = next;
    state = AsyncData(CollaborationState(session: next));
  }
}

AccountSession _session() => AccountSession(
  serverUrl: 'https://example.test',
  serverId: 'server',
  accountId: 'account',
  userId: 1,
  username: 'user',
  displayName: 'User',
  deviceId: 'device',
  expiresAt: DateTime.utc(2030),
);

class _Files extends RecoveryFileIo {
  final picked = Completer<Uint8List?>();
  int picks = 0;
  @override
  Future<Uint8List?> pick() {
    picks++;
    return picked.future;
  }
}

class _Workflow implements AccountCryptoV2Workflow {
  int checks = 0;
  @override
  Future<void> checkRecoveryFile(Uint8List bytes) async {
    checks++;
    expect(bytes.any((value) => value != 0), isTrue);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _SequenceFiles extends RecoveryFileIo {
  _SequenceFiles(this.files);
  final List<Uint8List> files;
  int picks = 0;
  @override
  Future<Uint8List?> pick() async => files[picks++];
}

void main() {
  testWidgets('success clears before another selection; cancel has no check', (
    tester,
  ) async {
    final bytes = Uint8List.fromList([1, 2, 3]);
    final second = Completer<Uint8List?>();
    final verification = Completer<void>();
    int picks = 0, checks = 0;
    final identity = Object();
    await tester.pumpWidget(
      _app(
        RecoveryFileCheckCard(
          sessionIdentity: identity,
          isCurrent: () => true,
          pickFile: () async => ++picks == 1 ? bytes : await second.future,
          checkFile: (selected) async {
            checks++;
            expect(identical(selected, bytes), isTrue);
            expect(selected, [1, 2, 3]);
            await verification.future;
          },
        ),
      ),
    );
    expect(checks, 0);
    await tester.tap(_button);
    await tester.pump();
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(tester.widget<OutlinedButton>(_button).onPressed, isNull);
    verification.complete();
    await tester.pumpAndSettle();
    expect(find.textContaining('The selected file unlocks'), findsOneWidget);
    expect(bytes, [0, 0, 0]);
    await tester.tap(_button);
    await tester.pump();
    expect(find.textContaining('The selected file unlocks'), findsNothing);
    second.complete(null);
    await tester.pumpAndSettle();
    expect(
      find.text('File selection cancelled. No file was checked.'),
      findsOneWidget,
    );
    expect(checks, 1);
  });

  testWidgets('failure clears bytes and never exposes raw error details', (
    tester,
  ) async {
    final bytes = Uint8List.fromList([4, 5]);
    await tester.pumpWidget(
      _app(
        RecoveryFileCheckCard(
          sessionIdentity: Object(),
          isCurrent: () => true,
          pickFile: () async => bytes,
          checkFile: (_) async => throw StateError('secret-path-token-payload'),
        ),
      ),
    );
    await tester.tap(_button);
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Existing keys and data are preserved'),
      findsOneWidget,
    );
    expect(find.textContaining('secret-path-token-payload'), findsNothing);
    expect(bytes, [0, 0]);
  });

  testWidgets('obsolete picker cannot check and its bytes are cleared', (
    tester,
  ) async {
    final picker = Completer<Uint8List?>();
    final bytes = Uint8List.fromList([7, 8]);
    bool current = true;
    int checks = 0;
    await tester.pumpWidget(
      _app(
        RecoveryFileCheckCard(
          sessionIdentity: Object(),
          isCurrent: () => current,
          pickFile: () => picker.future,
          checkFile: (_) async => checks++,
        ),
      ),
    );
    await tester.tap(_button);
    await tester.pump();
    current = false;
    picker.complete(bytes);
    await tester.pumpAndSettle();
    expect(checks, 0);
    expect(bytes, [0, 0]);
    expect(_result, findsNothing);
  });

  testWidgets('session replacement suppresses old success and failure', (
    tester,
  ) async {
    final oldResult = Completer<void>();
    final bytes = Uint8List.fromList([9]);
    final oldIdentity = Object(), nextIdentity = Object();
    Widget card(Object identity) => _app(
      RecoveryFileCheckCard(
        sessionIdentity: identity,
        isCurrent: () => true,
        pickFile: () async => bytes,
        checkFile: (_) => oldResult.future,
      ),
    );
    await tester.pumpWidget(card(oldIdentity));
    await tester.tap(_button);
    await tester.pump();
    await tester.pumpWidget(card(nextIdentity));
    oldResult.completeError(
      const CryptoDirectoryException('directory_recovery_file_invalid'),
    );
    await tester.pumpAndSettle();
    expect(_result, findsNothing);
    expect(bytes, [0]);
    expect(tester.widget<OutlinedButton>(_button).onPressed, isNotNull);
  });

  testWidgets(
    'sync-required result is explicit and does not run another check',
    (tester) async {
      int checks = 0;
      final bytes = Uint8List.fromList([10]);
      await tester.pumpWidget(
        _app(
          RecoveryFileCheckCard(
            sessionIdentity: Object(),
            isCurrent: () => true,
            pickFile: () async => bytes,
            checkFile: (_) async {
              checks++;
              throw const CryptoDirectoryException(
                'directory_recovery_status_changed',
              );
            },
          ),
          locale: 'sl',
        ),
      );
      expect(find.text('Preveri obnovitveno datoteko'), findsNWidgets(2));
      expect(
        find.textContaining('Preverjanje ne zajema obnove lokalne namestitve'),
        findsOneWidget,
      );
      await tester.tap(_button);
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Uskladite podatke, nato znova izberite datoteko'),
        findsOneWidget,
      );
      expect(checks, 1);
      expect(bytes, [0]);
    },
  );

  testWidgets('account entry is lazy and same-account re-login during picker '
      'cannot acquire a new workflow', (tester) async {
    final session = _session();
    final controller = _Controller(session);
    final files = _Files();
    final container = ProviderContainer(
      overrides: [
        collaborationProvider.overrideWith(() => controller),
        recoveryFileIoProvider.overrideWithValue(files),
      ],
    );
    addTearDown(container.dispose);
    await container.read(collaborationProvider.future);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: _app(AccountRecoveryFileCheckCard(session: session)),
      ),
    );
    expect(controller.previewReads, 0);
    expect(files.picks, 0);
    await tester.tap(_button);
    await tester.pump();
    controller.replaceSession(_session());
    final bytes = Uint8List.fromList([11, 12]);
    files.picked.complete(bytes);
    await tester.pumpAndSettle();
    expect(controller.previewReads, 0);
    expect(bytes, [0, 0]);
    expect(_result, findsNothing);
  });

  testWidgets('leaving during picker clears eventual bytes without checking', (
    tester,
  ) async {
    final picker = Completer<Uint8List?>();
    int checks = 0;
    await tester.pumpWidget(
      _app(
        RecoveryFileCheckCard(
          sessionIdentity: Object(),
          isCurrent: () => true,
          pickFile: () => picker.future,
          checkFile: (_) async => checks++,
        ),
      ),
    );
    await tester.tap(_button);
    await tester.pump();
    await tester.pumpWidget(const SizedBox.shrink());
    final bytes = Uint8List.fromList([13]);
    picker.complete(bytes);
    await tester.pumpAndSettle();
    expect(checks, 0);
    expect(bytes, [0]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('renewed session check obtains a fresh workflow without cached '
      'preview or setup', (tester) async {
    final firstWorkflow = _Workflow(), nextWorkflow = _Workflow();
    final firstBytes = Uint8List.fromList([14, 15]);
    final nextBytes = Uint8List.fromList([16, 17]);
    final files = _SequenceFiles([firstBytes, nextBytes]);
    final controller = _Controller(
      _session(),
      workflows: [firstWorkflow, nextWorkflow],
    );
    final container = ProviderContainer(
      overrides: [
        collaborationProvider.overrideWith(() => controller),
        recoveryFileIoProvider.overrideWithValue(files),
        accountCryptoPreviewProvider.overrideWith(
          (ref) async => throw StateError('Cached preview must not be used'),
        ),
      ],
    );
    addTearDown(container.dispose);
    await container.read(collaborationProvider.future);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: _app(
          Consumer(
            builder: (context, ref, _) {
              final session = ref
                  .watch(collaborationProvider)
                  .valueOrNull!
                  .session!;
              return AccountRecoveryFileCheckCard(session: session);
            },
          ),
        ),
      ),
    );
    expect(controller.previewReads, 0);
    await tester.tap(_button);
    await tester.pumpAndSettle();
    expect(find.textContaining('The selected file unlocks'), findsOneWidget);
    expect(firstWorkflow.checks, 1);
    expect(firstBytes, [0, 0]);
    controller.replaceSession(_session());
    await tester.pumpAndSettle();
    expect(_result, findsNothing);
    expect(controller.previewReads, 1);
    await tester.tap(_button);
    await tester.pumpAndSettle();
    expect(find.textContaining('The selected file unlocks'), findsOneWidget);
    expect(controller.previewReads, 2);
    expect(firstWorkflow.checks, 1);
    expect(nextWorkflow.checks, 1);
    expect(nextBytes, [0, 0]);
  });
}
