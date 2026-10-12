import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/theme/jivie_theme.dart';

double contrast(Color a, Color b) {
  final first = a.computeLuminance(), second = b.computeLuminance();
  return ((first > second ? first : second) + .05) /
      ((first > second ? second : first) + .05);
}

void main() {
  for (final brightness in Brightness.values) {
    test('readable Jivie text in $brightness', () {
      final colors = buildJivieTheme(brightness).colorScheme;
      for (final surface in [
        colors.surface,
        colors.surfaceContainerLow,
        colors.surfaceContainerHighest,
      ]) {
        expect(contrast(colors.onSurface, surface), greaterThanOrEqualTo(4.5));
        expect(
          contrast(colors.onSurfaceVariant, surface),
          greaterThanOrEqualTo(4.5),
        );
        expect(contrast(colors.primary, surface), greaterThanOrEqualTo(4.5));
        expect(contrast(colors.tertiary, surface), greaterThanOrEqualTo(3));
      }
      expect(
        contrast(colors.onPrimary, colors.primary),
        greaterThanOrEqualTo(4.5),
      );
    });
  }

  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    testWidgets('platform transitions and labeled 48px controls $platform', (
      tester,
    ) async {
      debugDefaultTargetPlatformOverride = platform;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      final theme = buildJivieTheme(Brightness.light);
      expect(
        theme.pageTransitionsTheme.builders[platform].runtimeType,
        const PageTransitionsTheme().builders[platform].runtimeType,
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: Scaffold(
            body: Column(
              children: [
                FilledButton(onPressed: () {}, child: const Text('Shrani')),
                OutlinedButton(onPressed: () {}, child: const Text('Odpri')),
                TextButton(onPressed: () {}, child: const Text('Prekliči')),
                IconButton(
                  onPressed: () {},
                  tooltip: 'Nazaj',
                  icon: const Icon(Icons.arrow_back),
                ),
              ],
            ),
          ),
        ),
      );
      for (final type in [
        FilledButton,
        OutlinedButton,
        TextButton,
        IconButton,
      ]) {
        final size = tester.getSize(find.byType(type));
        expect(size.height, greaterThanOrEqualTo(48));
        expect(size.width, greaterThanOrEqualTo(48));
      }
      expect(find.byTooltip('Nazaj'), findsOneWidget);
      expect(tester.takeException(), isNull);
      debugDefaultTargetPlatformOverride = null;
    });
  }
}
