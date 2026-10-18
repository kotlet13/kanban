import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'l10n/l10n.dart';
import 'organizer/presentation/organizer_shell.dart';
import 'organizer/presentation/recovery/account_crypto_startup.dart';
import 'organizer/presentation/navigation/organizer_navigation_observer.dart';

final appRouter = GoRouter(
  initialLocation: '/',
  observers: [OrganizerNavigationObserver()],
  routes: <RouteBase>[
    GoRoute(
      path: '/',
      builder: (context, state) =>
          const AccountCryptoStartupCoordinator(child: OrganizerShell()),
    ),
  ],
  errorBuilder: (context, state) {
    final isApple = switch (Theme.of(context).platform) {
      TargetPlatform.iOS || TargetPlatform.macOS => true,
      _ => false,
    };
    final errorText = state.error?.toString() ?? context.l10n.unknownError;

    final cardBody = Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(
            isApple
                ? CupertinoIcons.exclamationmark_triangle_fill
                : Icons.route_outlined,
            size: 28,
          ),
          const SizedBox(height: 10),
          Text(errorText, textAlign: TextAlign.center),
        ],
      ),
    );

    final content = Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: isApple
            ? CupertinoPopupSurface(isSurfacePainted: true, child: cardBody)
            : Card(child: cardBody),
      ),
    );

    if (isApple) {
      return CupertinoPageScaffold(
        navigationBar: CupertinoNavigationBar(
          middle: Text(context.l10n.routeError),
        ),
        child: SafeArea(child: content),
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.routeError)),
      body: content,
    );
  },
);
