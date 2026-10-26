import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/l10n/app_localizations.dart';
import 'package:kanban/organizer/data/collaboration_repository.dart';
import 'package:kanban/organizer/presentation/shared/access_review_button.dart';
import 'package:kanban/organizer/state/collaboration_provider.dart';
import 'sharing_ui_fixture.dart';

class _Controller extends SharingUiController {
  _Controller()
    : super(
        initial: CollaborationState(
          session: sharingSession(),
          scopes: const [],
        ),
      );
  final result = Completer<CollaborationAccessReview>();
  int reviewCalls = 0;
  @override
  Future<CollaborationAccessReview> checkAllAccess() {
    reviewCalls++;
    return result.future;
  }
}

void main() {
  for (final switchAccount in [false, true]) {
    testWidgets(
      'check all access works with no visible spaces and suppresses stale result switch=$switchAccount',
      (tester) async {
        final c = _Controller();
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              ...await sharingUiInfrastructureOverrides(tester, c),
              collaborationProvider.overrideWith(() => c),
            ],
            child: MaterialApp(
              locale: const Locale('sl'),
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: const Scaffold(body: AccessReviewButton()),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Preveri vse dostope'), findsOneWidget);
        await tester.tap(find.text('Preveri vse dostope'));
        await tester.pump();
        expect(find.text('Preverjam dostope …'), findsOneWidget);
        expect(
          tester.widget<OutlinedButton>(find.byType(OutlinedButton)).onPressed,
          isNull,
        );
        expect(c.reviewCalls, 1);
        if (switchAccount)
          c.replace(CollaborationState(session: sharingSession(second: true)));
        c.result.complete(
          const CollaborationAccessReview(
            available: 14,
            restored: 1,
            revoked: 0,
            unresolved: 0,
          ),
        );
        await tester.pumpAndSettle();
        expect(
          find.byType(SnackBar),
          switchAccount ? findsNothing : findsOneWidget,
        );
        if (!switchAccount)
          expect(find.textContaining('Obnovljeni dostopi: 1'), findsOneWidget);
        expect(c.reviewCalls, 1);
      },
    );
  }
}
