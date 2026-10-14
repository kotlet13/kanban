import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:kanban/organizer/state/local_notification_preferences_provider.dart';
import 'package:kanban/organizer/domain/notification_models.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test(
    'workspace and project exceptions inherit only unspecified channels',
    () {
      var prefs = LocalNotificationPreferences(
        defaults: const SharedNotificationSettings(push: false),
      );
      prefs = prefs.change('push', true, workspace: 'home');
      prefs = prefs.change('sound', true, workspace: 'home', project: 'p1');
      prefs = prefs.change('inApp', false, workspace: 'home', project: 'p1');
      expect(prefs.resolve('home', 'p1').toJson(), {
        'inApp': false,
        'sound': true,
        'push': true,
        'email': false,
      });
      expect(prefs.resolve('home', 'p2').sound, isFalse);
      expect(prefs.resolve('other', 'p1').push, isFalse);
      expect(prefs.resolve('private:another-account', 'p1').sound, isFalse);
      final bulk = prefs.change('sound', false);
      expect(bulk.resolve('home', 'p1').sound, isFalse);
      expect(bulk.resolve('home', 'p1').inApp, isFalse);
      expect(bulk.resolve('home', 'p1').push, isTrue);
      expect(
        LocalNotificationPreferences.fromJson(
          jsonDecode(jsonEncode(bulk.toJson())),
        ).toJson(),
        bulk.toJson(),
      );
    },
  );
  test(
    'legacy optin and sound survive reading without storage writes',
    () async {
      SharedPreferences.setMockInitialValues({
        'organizer_local_reminders_enabled_v1': true,
        'organizer_local_reminders_sound_v1': true,
      });
      final c = ProviderContainer();
      addTearDown(c.dispose);
      final value = await c.read(localNotificationPreferencesProvider.future);
      expect(value.defaults.push, isTrue);
      expect(value.defaults.sound, isTrue);
      expect(
        (await SharedPreferences.getInstance()).getString(
          LocalNotificationPreferencesController.storageKey,
        ),
        isNull,
      );
    },
  );
  test(
    'serialized saves retain simultaneous channel changes across a restart',
    () async {
      final c = ProviderContainer();
      await c.read(localNotificationPreferencesProvider.future);
      await Future.wait([
        c
            .read(localNotificationPreferencesProvider.notifier)
            .change('sound', true, workspace: 'home', project: 'p1'),
        c
            .read(localNotificationPreferencesProvider.notifier)
            .change('push', true, workspace: 'home', project: 'p1'),
      ]);
      c.dispose();
      final fresh = ProviderContainer();
      addTearDown(fresh.dispose);
      final saved = await fresh.read(
        localNotificationPreferencesProvider.future,
      );
      expect(saved.resolve('home', 'p1').sound, isTrue);
      expect(saved.resolve('home', 'p1').push, isTrue);
      expect(saved.resolve('home', 'p2').push, isFalse);
    },
  );
  test(
    'corrupt stored settings fail visibly without resetting optouts',
    () async {
      SharedPreferences.setMockInitialValues({
        LocalNotificationPreferencesController.storageKey: 'broken',
      });
      final c = ProviderContainer();
      addTearDown(c.dispose);
      await expectLater(
        c.read(localNotificationPreferencesProvider.future),
        throwsA(isA<FormatException>()),
      );
      expect(
        (await SharedPreferences.getInstance()).getString(
          LocalNotificationPreferencesController.storageKey,
        ),
        'broken',
      );
    },
  );
  test('bulk reset preserves explicit exceptions of unavailable accounts', () {
    var prefs = LocalNotificationPreferences(
      defaults: const SharedNotificationSettings(),
    );
    prefs = prefs.change('sound', false, workspace: 'private:old-account');
    prefs = prefs.change('sound', false, workspace: 'home', project: 'p1');
    final changed = prefs.change('sound', true, resetWorkspaces: {'home'});
    expect(changed.resolve('home', 'p1').sound, isTrue);
    expect(changed.resolve('private:old-account').sound, isFalse);
  });
  test(
    'late account guard rejects a local write before it reaches storage',
    () async {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      await c.read(localNotificationPreferencesProvider.future);
      await expectLater(
        c
            .read(localNotificationPreferencesProvider.notifier)
            .change('sound', true, stillCurrent: () => false),
        throwsA(isA<StateError>()),
      );
      expect(
        (await SharedPreferences.getInstance()).getString(
          LocalNotificationPreferencesController.storageKey,
        ),
        isNull,
      );
    },
  );
}
