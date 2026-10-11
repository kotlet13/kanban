import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/l10n/app_localizations.dart';
import 'package:kanban/organizer/presentation/inbox/inbox_page.dart';
import 'package:kanban/organizer/state/collaboration_provider.dart';
import 'package:kanban/organizer/state/notification_local_spaces_provider.dart';
import 'package:kanban/organizer/state/organizer_provider.dart';
import 'package:kanban/organizer/state/reminder_snooze_provider.dart';

import 'inbox_visibility_ui_test.dart' show EmptyPersonal, entry, now, shared;
import 'local_spaces_navigation_test.dart' show loadCaptureFonts;
import 'sharing_ui_fixture.dart';

void main() {
  for (final width in [320.0, 360.0, 1200.0]) {
    for (final brightness in Brightness.values) {
      testWidgets(
        'read and unread cards fit $width with enlarged text and $brightness',
        (tester) async {
          tester.view.physicalSize = Size(width, 900);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          await loadCaptureFonts(tester);
          if (Platform.environment['JIVIE_UI_CAPTURE'] == '1') {
            await tester.runAsync(() async {
              final root = Platform.resolvedExecutable
                  .split('/bin/cache/')
                  .first;
              final systemFont = File('/System/Library/Fonts/SFNS.ttf');
              final bytes =
                  await (await systemFont.exists()
                          ? systemFont
                          : File(
                              '$root/bin/cache/artifacts/material_fonts/Roboto-Regular.ttf',
                            ))
                      .readAsBytes();
              await (FontLoader(
                'Roboto',
              )..addFont(Future.value(ByteData.sublistView(bytes)))).load();
            });
          }
          final key = GlobalKey();
          await tester.pumpWidget(
            ProviderScope(
              overrides: [
                notificationLocalSnapshotsProvider.overrideWith(
                  (ref) async => [await ref.watch(organizerProvider.future)],
                ),
                organizerProvider.overrideWith(EmptyPersonal.new),
                collaborationProvider.overrideWith(
                  () => SharingUiController(
                    initial: shared(
                      inbox: [
                        entry(id: 1, read: true, kind: 'task.created'),
                        entry(id: 2, kind: 'task.created'),
                      ],
                    ),
                  ),
                ),
                effectiveReminderPlansProvider.overrideWith((ref) async => []),
                organizerClockProvider.overrideWithValue(() => now),
                organizerReminderSchedulerProvider.overrideWithValue(
                  (_) => () {},
                ),
              ],
              child: RepaintBoundary(
                key: key,
                child: MaterialApp(
                  debugShowCheckedModeBanner: false,
                  locale: const Locale('sl'),
                  localizationsDelegates:
                      AppLocalizations.localizationsDelegates,
                  supportedLocales: AppLocalizations.supportedLocales,
                  theme: ThemeData(
                    colorScheme: ColorScheme.fromSeed(
                      seedColor: const Color(0xFF365BD9),
                      brightness: brightness,
                    ),
                  ),
                  builder: (context, child) => MediaQuery(
                    data: MediaQuery.of(
                      context,
                    ).copyWith(textScaler: const TextScaler.linear(1.3)),
                    child: child!,
                  ),
                  home: Scaffold(
                    body: SingleChildScrollView(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: OrganizerInboxPage(
                          onSettings: () {},
                          onAccount: () {},
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(find.byIcon(Icons.mark_email_read_outlined), findsOneWidget);
          expect(find.byIcon(Icons.mark_email_unread_outlined), findsOneWidget);
          expect(find.byTooltip('Označi kot prebrano'), findsOneWidget);
          expect(find.byTooltip('Označi kot neprebrano'), findsOneWidget);
          expect(tester.takeException(), isNull);
          if (Platform.environment['JIVIE_UI_CAPTURE'] == '1') {
            await tester.runAsync(() async {
              final boundary =
                  key.currentContext!.findRenderObject()!
                      as RenderRepaintBoundary;
              final image = await boundary.toImage(pixelRatio: 2);
              final bytes = await image.toByteData(
                format: ui.ImageByteFormat.png,
              );
              final file = File(
                'build/qa/inbox-read-state/inbox-${width.toInt()}-${brightness.name}.png',
              );
              await file.parent.create(recursive: true);
              await file.writeAsBytes(bytes!.buffer.asUint8List());
              image.dispose();
            });
          }
        },
      );
    }
  }
}
