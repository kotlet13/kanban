import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/l10n/app_localizations.dart';
import 'package:kanban/organizer/presentation/shared/space_settings_page.dart';
import 'package:kanban/organizer/state/collaboration_provider.dart';

import 'sharing_ui_fixture.dart';

void main() {
  for (final language in ['en', 'sl']) {
    testWidgets(
      'policy card $language preserves unknown, required and accepted states',
      (tester) async {
        for (final accepted in [null, false, true]) {
          final session = sharingSession();
          const scopeId = '10000000-0000-4000-8000-000000000003';
          final controller = SharingUiController(
            initial: CollaborationState(
              session: session,
              selectedSpaceId: scopeId,
              scopes: const [
                SharedScope(
                  id: scopeId,
                  name: 'Project',
                  kind: SharedScopeKind.project,
                  role: SharedRole.viewer,
                ),
              ],
              sharedContentPolicy: accepted == null
                  ? null
                  : SharedContentPolicy(
                      serverId: session.serverId,
                      partition: session.partition,
                      deviceId: session.deviceId,
                      policyVersion: 1,
                      title: 'Rules',
                      textSl: 'Pravila',
                      textEn: 'Rules',
                      recipientName: 'Operator',
                      accepted: accepted,
                    ),
            ),
          );
          final infrastructure = await sharingUiInfrastructureOverrides(
            tester,
            controller,
            emptyLocalCatalog: true,
          );
          await tester.pumpWidget(
            ProviderScope(
              key: ValueKey(accepted),
              overrides: [
                ...infrastructure,
                collaborationProvider.overrideWith(() => controller),
              ],
              child: MaterialApp(
                locale: Locale(language),
                supportedLocales: AppLocalizations.supportedLocales,
                localizationsDelegates: AppLocalizations.localizationsDelegates,
                home: Scaffold(
                  body: SingleChildScrollView(
                    child: SpaceSettingsPage(
                      selectedScopeId: scopeId,
                      onScopeSelected: (_) {},
                      onConnect: () {},
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          final card = find.byKey(const ValueKey('shared-content-rules'));
          expect(card, findsOneWidget);
          final l = AppLocalizations.of(tester.element(card))!;
          final subtitle = tester.widget<ListTile>(card).subtitle as Text;
          expect(subtitle.data, switch (accepted) {
            true => l.moderationPolicyAccepted,
            false => l.moderationPolicyRequired,
            null => l.moderationPolicyUnknown,
          });
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
        }
      },
    );
  }
}
