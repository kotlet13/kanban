import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app_router.dart';
import 'theme/jivie_theme.dart';
import 'l10n/l10n.dart';
import 'organizer/state/app_preferences_provider.dart';
import 'organizer/platform/notification_coordinator.dart';
import 'organizer/platform/backup_preferences_replay.dart';
import 'organizer/presentation/onboarding/getting_started.dart';
import 'organizer/platform/invitation_links/invitation_link_coordinator.dart';
import 'organizer/platform/remote_push/remote_push_coordinator.dart';
import 'organizer/presentation/shared/sync_merge_notice.dart';

class JivieApp extends ConsumerStatefulWidget {
  const JivieApp({super.key});

  @override
  ConsumerState<JivieApp> createState() => _JivieAppState();
}

class _JivieAppState extends ConsumerState<JivieApp> {
  bool _didLoadLocale = false;
  bool _didLoadThemeMode = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadSavedLocale();
      _loadSavedThemeMode();
    });
  }

  Future<void> _loadSavedLocale() async {
    if (_didLoadLocale) return;
    _didLoadLocale = true;
    final locale = await ref.read(localeStoreProvider).read();
    if (!mounted) return;
    ref.read(appLocaleProvider.notifier).state = locale;
  }

  Future<void> _loadSavedThemeMode() async {
    if (_didLoadThemeMode) return;
    _didLoadThemeMode = true;
    final mode = await ref.read(themeModeStoreProvider).read();
    if (!mounted) return;
    ref.read(themeModeProvider.notifier).state = mode;
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(backupPreferencesReplayProvider, (previous, next) {
      next.whenData((values) {
        if (values.containsKey('app_locale_code')) {
          final code = values['app_locale_code'] as String?;
          ref.read(appLocaleProvider.notifier).state = code == null
              ? null
              : Locale(code);
        }
        if (values.containsKey('app_theme_mode')) {
          ref.read(themeModeProvider.notifier).state = ThemeMode.values.byName(
            values['app_theme_mode'] as String,
          );
        }
        ref.invalidate(gettingStartedSeenProvider);
      });
    });
    final themeMode = ref.watch(themeModeProvider);
    final appLocale = ref.watch(appLocaleProvider);

    return MaterialApp.router(
      onGenerateTitle: (context) => context.l10n.organizerAppName,
      debugShowCheckedModeBanner: false,
      localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      locale: appLocale,
      scrollBehavior: const _AppScrollBehavior(),
      themeMode: themeMode,
      theme: buildJivieTheme(Brightness.light),
      darkTheme: buildJivieTheme(Brightness.dark),
      routerConfig: appRouter,
      builder: (context, child) => InvitationLinkCoordinator(
        child: RemotePushCoordinator(
          child: LocalNotificationCoordinator(
            child: SyncMergeNotice(child: child ?? const SizedBox.shrink()),
          ),
        ),
      ),
    );
  }
}

class _AppScrollBehavior extends MaterialScrollBehavior {
  const _AppScrollBehavior();

  bool _usesAppleScrollPhysics(TargetPlatform platform) {
    return platform == TargetPlatform.iOS || platform == TargetPlatform.macOS;
  }

  @override
  Set<PointerDeviceKind> get dragDevices => const <PointerDeviceKind>{
    PointerDeviceKind.touch,
    PointerDeviceKind.mouse,
    PointerDeviceKind.trackpad,
    PointerDeviceKind.stylus,
    PointerDeviceKind.invertedStylus,
  };

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) {
    final platform = getPlatform(context);
    if (_usesAppleScrollPhysics(platform)) {
      return const BouncingScrollPhysics(
        parent: AlwaysScrollableScrollPhysics(),
      );
    }
    return const ClampingScrollPhysics();
  }

  @override
  Widget buildOverscrollIndicator(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) {
    return child;
  }
}
