import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/l10n/app_localizations.dart';
import 'package:kanban/organizer/presentation/desktop/desktop_commands.dart';
import 'package:kanban/organizer/presentation/navigation/organizer_navigation.dart';

Future<void> _pump(
  WidgetTester tester, {
  required TargetPlatform platform,
  required Widget child,
  VoidCallback? onNew,
  VoidCallback? onSearch,
  VoidCallback? onSettings,
  VoidCallback? onBack,
  ValueChanged<OrganizerArea>? onNavigate,
  List<OrganizerArea> areas = const [OrganizerArea.today, OrganizerArea.plans],
}) async {
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: OrganizerDesktopCommands(
          platform: platform,
          onNew: onNew,
          onSearch: onSearch ?? () {},
          onSettings: onSettings ?? () {},
          canGoBack: onBack != null,
          onBack: onBack,
          onNavigate: onNavigate ?? (_) {},
          visibleAreas: areas,
          areaLabel: (area) => area.name,
          child: child,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _chord(
  WidgetTester tester,
  LogicalKeyboardKey key, {
  bool mac = false,
  bool alt = false,
}) async {
  final modifier = alt
      ? LogicalKeyboardKey.altLeft
      : mac
      ? LogicalKeyboardKey.metaLeft
      : LogicalKeyboardKey.controlLeft;
  await tester.sendKeyDownEvent(modifier);
  await tester.sendKeyEvent(key);
  await tester.sendKeyUpEvent(modifier);
  await tester.pumpAndSettle();
}

Iterable<PlatformMenuItem> _leaves(PlatformMenuItem item) sync* {
  yield item;
  if (item is PlatformMenu) {
    for (final child in item.menus) {
      yield* _leaves(child);
    }
  } else if (item is PlatformMenuItemGroup) {
    for (final child in item.members) {
      yield* _leaves(child);
    }
  }
}

void main() {
  testWidgets('macOS installs one native menu and preserves OS actions', (
    tester,
  ) async {
    await _pump(
      tester,
      platform: TargetPlatform.macOS,
      child: const Text('body'),
    );
    expect(find.byType(MenuBar), findsNothing);
    final menu = tester.widget<PlatformMenuBar>(find.byType(PlatformMenuBar));
    final leaves = menu.menus.expand(_leaves).toList();
    expect(
      leaves.whereType<PlatformProvidedMenuItem>().map((m) => m.type),
      containsAll([
        PlatformProvidedMenuItemType.quit,
        PlatformProvidedMenuItemType.hide,
        PlatformProvidedMenuItemType.minimizeWindow,
        PlatformProvidedMenuItemType.zoomWindow,
        PlatformProvidedMenuItemType.toggleFullScreen,
      ]),
    );
    expect(leaves.where((m) => m.label == 'New…').single.onSelected, isNull);
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

  for (final platform in [
    TargetPlatform.macOS,
    TargetPlatform.windows,
    TargetPlatform.linux,
  ]) {
    testWidgets('${platform.name} uses Command or Control for shell commands', (
      tester,
    ) async {
      var newCalls = 0, searchCalls = 0, settingsCalls = 0;
      await _pump(
        tester,
        platform: platform,
        onNew: () => newCalls++,
        onSearch: () => searchCalls++,
        onSettings: () => settingsCalls++,
        child: const Focus(autofocus: true, child: Text('body')),
      );
      final mac = platform == TargetPlatform.macOS;
      await _chord(tester, LogicalKeyboardKey.keyN, mac: mac);
      await _chord(tester, LogicalKeyboardKey.keyF, mac: mac);
      await _chord(tester, LogicalKeyboardKey.comma, mac: mac);
      expect([newCalls, searchCalls, settingsCalls], [1, 1, 1]);
      await _chord(tester, LogicalKeyboardKey.keyN, mac: !mac);
      expect(newCalls, 1);
    }, variant: TargetPlatformVariant.only(platform));
  }

  testWidgets('View only offers supplied destinations and invokes navigation', (
    tester,
  ) async {
    OrganizerArea? destination;
    await _pump(
      tester,
      platform: TargetPlatform.linux,
      onNavigate: (area) => destination = area,
      areas: const [OrganizerArea.today, OrganizerArea.ideas],
      child: const Text('body'),
    );
    await tester.tap(find.text('View'));
    await tester.pumpAndSettle();
    expect(find.text('settings'), findsNothing);
    expect(find.text('garden'), findsNothing);
    await tester.tap(find.text('ideas'));
    await tester.pumpAndSettle();
    expect(destination, OrganizerArea.ideas);
  });

  testWidgets('Back shortcut leaves an editing field and plain typing intact', (
    tester,
  ) async {
    var calls = 0;
    final controller = TextEditingController();
    final bodyFocus = FocusNode();
    addTearDown(controller.dispose);
    addTearDown(bodyFocus.dispose);
    await _pump(
      tester,
      platform: TargetPlatform.windows,
      onBack: () => calls++,
      child: Column(
        children: [
          TextField(controller: controller),
          Focus(focusNode: bodyFocus, child: const Text('body')),
        ],
      ),
    );
    await tester.tap(find.byType(TextField));
    await tester.enterText(find.byType(TextField), 'unchanged');
    await _chord(tester, LogicalKeyboardKey.arrowLeft, alt: true);
    expect(calls, 0);
    expect(controller.text, 'unchanged');
    bodyFocus.requestFocus();
    await tester.pumpAndSettle();
    await _chord(tester, LogicalKeyboardKey.arrowLeft, alt: true);
    expect(calls, 1);
  });

  testWidgets('Edit menu selects and copies from the field that had focus', (
    tester,
  ) async {
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
    final controller = TextEditingController(text: 'Jivie text');
    addTearDown(controller.dispose);
    await _pump(
      tester,
      platform: TargetPlatform.windows,
      child: TextField(controller: controller),
    );
    await tester.tap(find.byType(TextField));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Select all'));
    await tester.pumpAndSettle();
    expect(
      controller.selection,
      const TextSelection(baseOffset: 0, extentOffset: 10),
    );
    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Copy'));
    await tester.pumpAndSettle();
    expect(copied, 'Jivie text');
  });

  testWidgets('native Back shortcut is suspended while editing text', (
    tester,
  ) async {
    await _pump(
      tester,
      platform: TargetPlatform.macOS,
      onBack: () {},
      child: const TextField(),
    );
    await tester.tap(find.byType(TextField));
    await tester.pumpAndSettle();
    final menu = tester.widget<PlatformMenuBar>(find.byType(PlatformMenuBar));
    final back = menu.menus
        .expand(_leaves)
        .where((m) => m.label == 'Back')
        .single;
    expect(back.shortcut, isNull);
    expect(back.onSelected, isNotNull);
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

  testWidgets('canvas undo shortcuts remain in the child action', (
    tester,
  ) async {
    var undoCalls = 0;
    await _pump(
      tester,
      platform: TargetPlatform.macOS,
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.keyZ, meta: true): () =>
              undoCalls++,
        },
        child: const Focus(autofocus: true, child: Text('canvas')),
      ),
    );
    await _chord(tester, LogicalKeyboardKey.keyZ, mac: true);
    expect(undoCalls, 1);
    final menu = tester.widget<PlatformMenuBar>(find.byType(PlatformMenuBar));
    final undo = menu.menus
        .expand((m) => m.descendants)
        .where((m) => m.label == 'Undo')
        .single;
    expect(undo.onSelected, isNull);
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

  testWidgets('mobile retains its child without desktop menus', (tester) async {
    await _pump(
      tester,
      platform: TargetPlatform.android,
      child: const Text('body'),
    );
    expect(find.byType(MenuBar), findsNothing);
    expect(find.byType(PlatformMenuBar), findsNothing);
    expect(find.text('body'), findsOneWidget);
  });
}
