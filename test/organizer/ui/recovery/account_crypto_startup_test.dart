import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/organizer/presentation/recovery/account_crypto_startup.dart';

void main() {
  testWidgets(
    'stored-session action opens automatically and exit preserves local screen',
    (tester) async {
      final action = AccountCryptoStartupAction(
        identity: 'stored-profile:device',
        builder: (_) => const Scaffold(body: Text('Resume saved protection')),
      );
      final container = ProviderContainer(
        overrides: [
          accountCryptoStartupIdentityProvider.overrideWith(
            (ref) => 'stored-profile:device',
          ),
          accountCryptoStartupActionProvider.overrideWith(
            (ref) async => action,
          ),
        ],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: AccountCryptoStartupCoordinator(
              child: Scaffold(body: Text('Local retained data')),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Resume saved protection'), findsOneWidget);
      Navigator.of(tester.element(find.text('Resume saved protection'))).pop();
      await tester.pumpAndSettle();
      expect(find.text('Local retained data'), findsOneWidget);
      container.invalidate(accountCryptoStartupActionProvider);
      await tester.pumpAndSettle();
      expect(find.text('Resume saved protection'), findsNothing);
    },
  );
  testWidgets('offline startup failure leaves local screen accessible', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          accountCryptoStartupIdentityProvider.overrideWith(
            (ref) => 'stored-profile:device',
          ),
          accountCryptoStartupActionProvider.overrideWith(
            (ref) async => throw StateError('offline'),
          ),
        ],
        child: const MaterialApp(
          home: AccountCryptoStartupCoordinator(
            child: Scaffold(body: Text('Local retained data')),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Local retained data'), findsOneWidget);
  });
  testWidgets(
    'logout removes old protection route before a new profile opens',
    (tester) async {
      final identity = StateProvider<String?>((ref) => 'old:device');
      final container = ProviderContainer(
        overrides: [
          accountCryptoStartupIdentityProvider.overrideWith(
            (ref) => ref.watch(identity),
          ),
          accountCryptoStartupActionProvider.overrideWith((ref) async {
            final id = ref.watch(identity);
            return id == null
                ? null
                : AccountCryptoStartupAction(
                    identity: id,
                    builder: (_) => Scaffold(body: Text('Protection $id')),
                  );
          }),
        ],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: AccountCryptoStartupCoordinator(
              child: Scaffold(body: Text('Retained local data')),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Protection old:device'), findsOneWidget);
      container.read(identity.notifier).state = null;
      await tester.pumpAndSettle();
      expect(find.text('Protection old:device'), findsNothing);
      expect(find.text('Retained local data'), findsOneWidget);
      container.read(identity.notifier).state = 'new:device';
      await tester.pumpAndSettle();
      expect(find.text('Protection new:device'), findsOneWidget);
      expect(find.text('Protection old:device'), findsNothing);
    },
  );
}
