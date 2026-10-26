import '../support/synthetic_content_route_guard.dart';
import 'dart:async';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/l10n/app_localizations.dart';
import 'package:kanban/organizer/data/collaboration_database.dart';
import 'package:kanban/organizer/data/collaboration_repository.dart';
import 'package:kanban/organizer/presentation/shared/content_moderation.dart';
import 'package:kanban/organizer/presentation/shared/content_actions_menu.dart';
import 'package:kanban/organizer/state/collaboration_provider.dart';
import '../data/collaboration_moderation_test.dart' show ModerationServer;
import '../data/collaboration_repository_test.dart'
    show FakeTransport, MemorySessionStore;

const policy = SharedContentPolicy(
  serverId: 'server',
  partition: 'account',
  deviceId: 'device',
  policyVersion: 1,
  title: 'Rules',
  textSl:
      'Prepovedani so nadlegovanje, sovraštvo, nasilje in razkritje zasebnosti.',
  textEn: 'Harassment, hate, violence and privacy violations are prohibited.',
  recipientName: 'Selected server administrator',
  accepted: false,
);
ContentReportPreview preview() => ContentReportPreview(
  serverId: 'server',
  partition: 'account',
  deviceId: 'device',
  requestId: 'stable-request',
  scopeId: 'scope',
  targetType: 'record',
  targetId: 'task',
  previewHash: 'hash',
  targetRevision: 3,
  title: 'The selected shared task',
  type: 'task',
  recipientName: 'Selected server administrator',
  evidence: {
    'id': 'task',
    'title': 'The selected shared task',
    'notes': 'Only this record’s notes',
  },
);
ContentReportReceipt receipt() => ContentReportReceipt(
  reportId: 'report',
  status: 'submitted',
  createdAt: DateTime.utc(2026),
);
Future<void> pumpDialog(
  WidgetTester tester,
  Widget dialog, {
  double width = 360,
  String language = 'en',
}) async {
  tester.view.physicalSize = Size(width, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      locale: Locale(language),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () =>
                showDialog<void>(context: context, builder: (_) => dialog),
            child: const Text('Open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
}

Future<void> selectReason(WidgetTester tester) async {
  await tester.ensureVisible(find.byKey(const ValueKey('report-reason')));
  await tester.tap(find.byKey(const ValueKey('report-reason')));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Privacy violation').last);
  await tester.pumpAndSettle();
}

void main() {
  for (final language in ['sl', 'en']) {
    testWidgets(
      'separate rules allow reading without accepting at 320 and 2x $language',
      (tester) async {
        tester.platformDispatcher.textScaleFactorTestValue = 2;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        var accepts = 0;
        await pumpDialog(
          tester,
          SharedContentPolicyDialog(
            policy: policy,
            serverUrl: 'https://selected.example/',
            allowReadOnly: true,
            onAccept: () async {
              accepts++;
            },
          ),
          width: 320,
          language: language,
        );
        expect(tester.takeException(), isNull);
        final full = find.byKey(const ValueKey('shared-policy-full-rules'));
        await tester.ensureVisible(full);
        await tester.tap(full);
        await tester.pumpAndSettle();
        expect(
          find.text(language == 'sl' ? policy.textSl : policy.textEn),
          findsOneWidget,
        );
        expect(accepts, 0);
        await tester.tap(
          find.text(
            language == 'sl'
                ? 'Za zdaj samo poglej'
                : 'Just look around for now',
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byType(SharedContentPolicyDialog), findsNothing);
        expect(accepts, 0);
        expect(tester.takeException(), isNull);
      },
    );
  }
  for (final width in [320.0, 390.0, 800.0, 1280.0]) {
    for (final language in ['en', 'sl']) {
      testWidgets('policy is unchecked and fits $width $language', (
        tester,
      ) async {
        var accepted = 0;
        await pumpDialog(
          tester,
          SharedContentPolicyDialog(
            policy: policy,
            serverUrl: 'https://selected.example/',
            onAccept: () async {
              accepted++;
            },
          ),
          width: width,
          language: language,
        );
        expect(
          tester
              .widget<CheckboxListTile>(
                find.byKey(const ValueKey('shared-policy-checkbox')),
              )
              .value,
          false,
        );
        expect(
          tester
              .widget<FilledButton>(
                find.byKey(const ValueKey('shared-policy-accept')),
              )
              .onPressed,
          isNull,
        );
        expect(find.textContaining('selected.example'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.tap(find.text(language == 'en' ? 'Cancel' : 'Prekliči'));
        await tester.pumpAndSettle();
        expect(accepted, 0);
      });
      testWidgets('report exact recipient and evidence fits $width $language', (
        tester,
      ) async {
        var reports = 0;
        await pumpDialog(
          tester,
          ContentReportDialog(
            preview: preview(),
            serverUrl: 'https://selected.example/',
            onSubmit: (_, __, ___) async {
              reports++;
              return receipt();
            },
          ),
          width: width,
          language: language,
        );
        expect(find.textContaining('selected.example'), findsOneWidget);
        expect(find.textContaining('Only this record’s notes'), findsOneWidget);
        expect(find.textContaining('TriparNA'), findsOneWidget);
        expect(
          tester
              .widget<FilledButton>(find.byKey(const ValueKey('report-send')))
              .onPressed,
          isNull,
        );
        expect(tester.takeException(), isNull);
        await tester.tap(find.text(language == 'en' ? 'Cancel' : 'Prekliči'));
        await tester.pumpAndSettle();
        expect(reports, 0);
      });
    }
  }
  testWidgets(
    'uncertain report retry keeps same preview and locks submitted reason/details',
    (tester) async {
      final sent = <(String, String, String)>[];
      final p = preview();
      await pumpDialog(
        tester,
        ContentReportDialog(
          preview: p,
          serverUrl: 'https://selected.example/',
          onSubmit: (value, reason, details) async {
            sent.add((value.requestId, reason, details));
            if (sent.length == 1) throw const CollaborationException('network');
            return receipt();
          },
        ),
      );
      await selectReason(tester);
      await tester.enterText(
        find.byKey(const ValueKey('report-details')),
        'This exposed private information',
      );
      await tester.tap(find.byKey(const ValueKey('report-send')));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('report-details')))
            .readOnly,
        true,
      );
      expect(
        tester
            .widget<DropdownButtonFormField<String>>(
              find.byKey(const ValueKey('report-reason')),
            )
            .onChanged,
        isNull,
      );
      expect(
        find.textContaining('Delivery could not be confirmed'),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('report-send')));
      await tester.pumpAndSettle();
      expect(sent, hasLength(2));
      expect(sent.first, sent.last);
      expect(find.byType(ContentReportDialog), findsNothing);
    },
  );
  testWidgets('UTF-8 details limit rejects multibyte oversize before sending', (
    tester,
  ) async {
    var sent = 0;
    await pumpDialog(
      tester,
      ContentReportDialog(
        preview: preview(),
        serverUrl: 'https://selected.example/',
        onSubmit: (_, __, ___) async {
          sent++;
          return receipt();
        },
      ),
    );
    await selectReason(tester);
    await tester.enterText(
      find.byKey(const ValueKey('report-details')),
      'ž' * 1001,
    );
    await tester.tap(find.byKey(const ValueKey('report-send')));
    await tester.pumpAndSettle();
    expect(sent, 0);
    expect(find.textContaining('2,000 UTF-8 bytes'), findsOneWidget);
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('report-details')))
          .readOnly,
      false,
    );
  });

  testWidgets(
    'real controller policy cancellation sends nothing; checked acceptance publishes; account change closes report',
    (tester) async {
      driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
      final server = ModerationServer();
      late CollaborationRepository repo;
      late FakeTransport transport;
      late ProviderContainer container;
      late CollaborationController controller;
      late String scope;
      await tester.runAsync(() async {
        transport = FakeTransport(server);
        repo = CollaborationRepository(
          CollaborationDatabase(NativeDatabase.memory()),
          transport,
          MemorySessionStore(),
          contentRouteGuard: const SyntheticContentRouteGuard(),
        );
        await repo.initialize();
        container = ProviderContainer(
          overrides: [
            collaborationRepositoryProvider.overrideWith((ref) async => repo),
          ],
        );
        container.listen(
          collaborationProvider,
          (_, __) {},
          fireImmediately: true,
        );
        await container.read(collaborationProvider.future);
        controller = container.read(collaborationProvider.notifier);
        await controller.login(
          serverUrl: 'https://synthetic.invalid/',
          username: 'alice',
          password: 'synthetic-password',
        );
        scope = await controller.createScope('Shared home');
        server.moderationAccepted = false;
        await controller.sharedContentPolicy(scopeId: scope);
        await Future<void>.delayed(const Duration(milliseconds: 20));
      });
      addTearDown(() async {
        container.dispose();
        await repo.close();
      });
      Completer<void>? saved;
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            locale: const Locale('en'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: Consumer(
                builder: (context, ref, _) => Column(
                  children: [
                    TextButton(
                      onPressed: () async {
                        saved = Completer<void>();
                        try {
                          if (await showSharedContentPolicy(
                            context,
                            scopeId: scope,
                          )) {
                            await controller.createShoppingList(
                              scopeId: scope,
                              title: 'Published only with consent',
                            );
                          }
                        } finally {
                          saved!.complete();
                        }
                      },
                      child: const Text('Publish'),
                    ),
                    SharedContentActionsMenu(
                      scopeId: scope,
                      targetId: '11111111-1111-4111-8111-111111111111',
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      Future<void> openPolicy() async {
        await tester.runAsync(() async {
          await tester.tap(find.text('Publish'));
          await Future<void>.delayed(const Duration(milliseconds: 25));
        });
        await tester.pumpAndSettle();
      }

      await openPolicy();
      expect(find.byType(SharedContentPolicyDialog), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const ValueKey('shared-policy-accept')),
            )
            .onPressed,
        isNull,
      );
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      await tester.runAsync(() => saved!.future);
      expect(
        server.calls.where((c) => c.operation == 'moderation.acceptPolicy'),
        isEmpty,
      );
      expect(repo.state.dataForScope(scope).shoppingLists, isEmpty);
      await openPolicy();
      await tester.ensureVisible(
        find.byKey(const ValueKey('shared-policy-checkbox')),
      );
      await tester.tap(find.byKey(const ValueKey('shared-policy-checkbox')));
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        await tester.tap(find.byKey(const ValueKey('shared-policy-accept')));
        await saved!.future;
      });
      await tester.pumpAndSettle();
      expect(
        server.calls.where((c) => c.operation == 'moderation.acceptPolicy'),
        hasLength(1),
      );
      expect(
        repo.state.dataForScope(scope).shoppingLists.single.title,
        'Published only with consent',
      );
      Future<void> openReport() async {
        await tester.tap(find.byType(PopupMenuButton<String>));
        await tester.pumpAndSettle();
        await tester.runAsync(() async {
          await tester.tap(find.text('Report content'));
          await Future<void>.delayed(const Duration(milliseconds: 25));
        });
        await tester.pump(const Duration(milliseconds: 300));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 25)),
        );
        await tester.pumpAndSettle();
      }

      transport.offline = true;
      await openReport();
      expect(
        find.textContaining('Reporting requires a connection'),
        findsOneWidget,
      );
      expect(find.byType(ContentReportDialog), findsNothing);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(server.reports, 0);
      transport.offline = false;
      server.moderationSupported = false;
      await openReport();
      expect(find.textContaining('FamilyHub 0.12.0'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(server.reports, 0);
      server.moderationSupported = true;
      await openReport();
      expect(find.byType(ContentReportDialog), findsOneWidget);
      await tester.runAsync(() async {
        await controller.login(
          serverUrl: 'https://synthetic.invalid/',
          username: 'bob',
          password: 'synthetic-password',
        );
        await Future<void>.delayed(const Duration(milliseconds: 25));
      });
      await tester.pumpAndSettle();
      expect(find.byType(ContentReportDialog), findsNothing);
      expect(server.reports, 0);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
