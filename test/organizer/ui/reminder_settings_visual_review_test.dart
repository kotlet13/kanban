import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/organizer/presentation/inbox/inbox_preferences.dart';
import 'local_spaces_navigation_test.dart' show loadCaptureFonts;
import 'organizer_ui_test.dart'
    show MemoryOrganizerStorage, pumpOrganizer, mobileTab;
import 'inbox_preferences_ui_test.dart'
    show PreferencesController, preferencesState, secondScopeId;

void main() {
  testWidgets(
    'More opens the full reminder settings screen and keeps its global controls visible',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      await loadCaptureFonts(tester);
      if (Platform.environment['JIVIE_REMINDER_CAPTURE'] != null) {
        await tester.runAsync(() async {
          final sdk = Platform.resolvedExecutable.split('/bin/cache/').first;
          final fonts = '$sdk/bin/cache/artifacts/material_fonts';
          for (final entry in {
            'Roboto': 'Roboto-Regular.ttf',
            'MaterialIcons': 'MaterialIcons-Regular.otf',
          }.entries) {
            final bytes = await File('$fonts/${entry.value}').readAsBytes();
            await (FontLoader(
              entry.key,
            )..addFont(Future.value(ByteData.sublistView(bytes)))).load();
          }
        });
      }
      final key = GlobalKey();
      final controller = PreferencesController(
        preferencesState(selected: secondScopeId, secondPush: true),
      );
      await pumpOrganizer(
        tester,
        MemoryOrganizerStorage(),
        width: 390,
        height: 844,
        collaborationController: controller,
        repaintBoundaryKey: key,
      );
      await mobileTab(tester, 'Nastavitve opomnikov');
      expect(find.byType(InboxPreferences), findsOneWidget);
      expect(find.text('Vsi prostori'), findsOneWidget);
      expect(find.byType(NavigationBar), findsOneWidget);
      expect(controller.writes, isEmpty);
      expect(tester.takeException(), isNull);
      final output = Platform.environment['JIVIE_REMINDER_CAPTURE'];
      if (output != null) {
        await tester.runAsync(() async {
          final boundary =
              key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
          final img = await boundary.toImage(pixelRatio: 2);
          final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
          await File(output).parent.create(recursive: true);
          await File(output).writeAsBytes(bytes!.buffer.asUint8List());
          img.dispose();
        });
      }
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('content-_Area.more')), findsOneWidget);
      debugDefaultTargetPlatformOverride = null;
    },
  );
}
