import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/l10n/app_localizations.dart';
import 'package:kanban/organizer/presentation/editor_actions.dart';
import 'package:kanban/organizer/domain/idea_models.dart';
import 'package:kanban/organizer/domain/organizer_models.dart';
import 'package:kanban/organizer/presentation/collection_actions.dart';
import 'package:kanban/organizer/presentation/ideas/idea_canvas.dart';
import 'package:kanban/organizer/presentation/shopping_page.dart';
import 'package:kanban/theme/jivie_theme.dart';

import '../../jivie_design_theme_test.dart' show contrast;

class _UnusedShoppingActions implements OrganizerCollectionActions {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  for (final platform in [
    TargetPlatform.android,
    TargetPlatform.iOS,
    TargetPlatform.macOS,
  ]) {
    for (final brightness in Brightness.values) {
      for (final state in ['enabled', 'disabled', 'busy']) {
        testWidgets('save contrast $platform/$brightness/$state', (
          tester,
        ) async {
          debugDefaultTargetPlatformOverride = platform;
          addTearDown(() => debugDefaultTargetPlatformOverride = null);
          final theme = buildJivieTheme(brightness);
          var saved = 0;
          Widget button(String location) => EditorSaveButton(
            key: ValueKey(location),
            onPressed: () => saved++,
            enabled: state != 'disabled',
            busy: state == 'busy',
          );
          await tester.pumpWidget(
            MaterialApp(
              theme: theme,
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              locale: const Locale('sl'),
              home: Scaffold(
                appBar: AppBar(
                  title: const Text('Nov vrt'),
                  actions: [button('toolbar')],
                ),
                body: Center(child: button('footer')),
              ),
            ),
          );
          // Busy has an intentionally repeating progress animation.
          await tester.pump(const Duration(milliseconds: 300));
          for (final location in ['toolbar', 'footer']) {
            final host = find.byKey(ValueKey(location));
            final icon = find.descendant(
              of: host,
              matching: state == 'busy'
                  ? find.byType(CircularProgressIndicator)
                  : find.byIcon(Icons.save_outlined),
            );
            final material = tester.widget<Material>(
              find.ancestor(of: icon, matching: find.byType(Material)).first,
            );
            final background = Color.alphaBlend(
              material.color!,
              theme.colorScheme.surface,
            );
            final foreground = state == 'busy'
                ? tester.widget<CircularProgressIndicator>(icon).color!
                : IconTheme.of(tester.element(icon)).color!;
            if (state != 'disabled') {
              expect(
                contrast(Color.alphaBlend(foreground, background), background),
                greaterThanOrEqualTo(state == 'busy' ? 3 : 4.5),
                reason: '$location foreground must contrast with its own fill',
              );
            } else {
              expect(background, isNot(theme.colorScheme.primary));
            }
            expect(tester.getSize(host).shortestSide, greaterThanOrEqualTo(48));
            expect(
              tester
                  .widget<IconButton>(
                    find.descendant(
                      of: host,
                      matching: find.byType(IconButton),
                    ),
                  )
                  .tooltip,
              'Shrani',
            );
            await tester.tap(host);
          }
          expect(saved, state == 'enabled' ? 2 : 0);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
          debugDefaultTargetPlatformOverride = null;
        });
      }
    }
  }
  for (final brightness in Brightness.values) {
    testWidgets('other filled controls contrast in $brightness', (
      tester,
    ) async {
      final theme = buildJivieTheme(brightness);
      final now = DateTime(2026, 10, 15);
      var boardChanges = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Column(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    child: OrganizerShoppingPage(
                      snapshot: OrganizerSnapshot().copyWith(
                        shoppingLists: [
                          LocalShoppingList(
                            id: 'list',
                            title: 'Groceries',
                            createdAt: now,
                            updatedAt: now,
                          ),
                        ],
                      ),
                      actions: _UnusedShoppingActions(),
                      selectedId: 'list',
                      onSelection: (_) {},
                    ),
                  ),
                ),
                Expanded(
                  child: IdeaCanvas(
                    board: IdeaBoard(
                      id: 'board',
                      title: 'Ideas',
                      createdAt: now,
                      updatedAt: now,
                    ),
                    onChanged: (_) => boardChanges++,
                    tool: IdeaTool.pan,
                    images: const {},
                    editable: true,
                    onSelected: (_) {},
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      for (final glyph in [Icons.add, Icons.fit_screen]) {
        final icon = glyph == Icons.add
            ? find.descendant(
                of: find.byTooltip('Add item'),
                matching: find.byIcon(glyph),
              )
            : find.byIcon(glyph);
        expect(icon, findsOneWidget);
        final material = tester.widget<Material>(
          find.ancestor(of: icon, matching: find.byType(Material)).first,
        );
        final background = Color.alphaBlend(
          material.color!,
          theme.colorScheme.surface,
        );
        expect(
          contrast(IconTheme.of(tester.element(icon)).color!, background),
          greaterThanOrEqualTo(4.5),
        );
      }
      await tester.tap(find.byIcon(Icons.fit_screen));
      await tester.pumpAndSettle();
      expect(boardChanges, 0);
      expect(tester.takeException(), isNull);
    });
  }
}
