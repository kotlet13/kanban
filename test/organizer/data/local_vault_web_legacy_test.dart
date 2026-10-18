import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kanban/organizer/data/local_vault.dart';
import 'package:kanban/organizer/data/local_vault_stub.dart';
import 'package:kanban/organizer/state/local_vault_preferences_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'explicit unsupported web branch preserves legacy settings and export access',
    () async {
      SharedPreferences.setMockInitialValues({
        'organizer_notification_ids_v1': 'legacy web routing',
        'organizer_local_reminders_enabled_v1': true,
        'app_locale_code': 'sl',
      });
      final vault = await openLocalVaultService();
      expect((await vault.inspect()).phase, LocalVaultPhase.unsupported);
      final container = ProviderContainer(
        overrides: [
          localVaultPreferencesProvider.overrideWith(
            (ref) => openLocalVaultPreferences(),
          ),
        ],
      );
      addTearDown(container.dispose);
      final preferences = await container.read(
        localVaultPreferencesProvider.future,
      );
      expect(
        preferences.getString('organizer_notification_ids_v1'),
        'legacy web routing',
      );
      expect(preferences.getBool('organizer_local_reminders_enabled_v1'), true);
      await preferences.setBool('organizer_local_reminders_sound_v1', false);
      final raw = await SharedPreferences.getInstance();
      expect(raw.getString('app_locale_code'), 'sl');
      expect(raw.getBool('organizer_local_reminders_sound_v1'), false);
      await expectLater(vault.migrate(), throwsA(isA<LocalVaultException>()));
    },
  );
}
