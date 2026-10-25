import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/organizer/presentation/shared/sync_merge_notice.dart';
import 'package:kanban/organizer/state/collaboration_provider.dart';

import 'sharing_ui_fixture.dart';

const notice = CollaborationAutoMergeNotice(
  key: 'synthetic-exact-notice',
  scopeId: sharingScopeId,
  recordId: 'task',
  type: 'task',
  at: '2026-10-24T12:00:00.000Z',
);
CollaborationState shared({bool withNotice = true, bool second = false}) =>
    CollaborationState(
      session: sharingSession(second: second),
      scopes: [sharingScope()],
      autoMergeNotices: withNotice ? [notice] : [],
    );

class _Controller extends SharingUiController {
  _Controller() : super(initial: shared());
  final acknowledgements = <(String, String)>[];
  @override
  Future<void> acknowledgeAutoMergeNotice(String key, String at) async {
    acknowledgements.add((key, at));
    replace(shared(withNotice: false));
  }
}

Widget app(_Controller controller) => ProviderScope(
  overrides: [collaborationProvider.overrideWith(() => controller)],
  child: const MaterialApp(
    home: SyncMergeNotice(child: Scaffold(body: Text('Local content'))),
  ),
);

void main() {
  testWidgets(
    'merge notice is nonmodal and acknowledges exact durable version once',
    (tester) async {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      final controller = _Controller();
      await tester.pumpWidget(app(controller));
      await tester.pump();
      expect(find.text('Local content'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('sync-auto-merge-notice')),
        findsOneWidget,
      );
      await tester.pump(const Duration(seconds: 6));
      await tester.pump();
      expect(controller.acknowledgements, [(notice.key, notice.at)]);
      expect(
        find.byKey(const ValueKey('sync-auto-merge-notice')),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('hidden app retains merge notice until visible', (tester) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    final controller = _Controller();
    await tester.pumpWidget(app(controller));
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    await tester.pump(const Duration(seconds: 7));
    expect(controller.acknowledgements, isEmpty);
    // Hidden lifecycle disables frames; the retained tree is not a visible UI.
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    await tester.pump();
    expect(
      find.byKey(const ValueKey('sync-auto-merge-notice')),
      findsOneWidget,
    );
    await tester.tap(find.byTooltip('Dismiss'));
    await tester.pump();
    expect(controller.acknowledgements, [(notice.key, notice.at)]);
  });
  testWidgets('account switch cancels a previous account notice timer', (
    tester,
  ) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    final controller = _Controller();
    await tester.pumpWidget(app(controller));
    await tester.pump();
    controller.replace(shared(withNotice: false, second: true));
    await tester.pump(const Duration(seconds: 7));
    expect(controller.acknowledgements, isEmpty);
    expect(find.byKey(const ValueKey('sync-auto-merge-notice')), findsNothing);
  });
}
