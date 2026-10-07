import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/organizer/presentation/onboarding/account_deletion_panel.dart';
import 'package:kanban/organizer/state/collaboration_provider.dart';
import 'sharing_ui_fixture.dart';
import 'onboarding_ui_test.dart' show pumpPanel;
import '../data/account_deletion_preview_test.dart' show preview;

class DeletionUiController extends SharingUiController {
  DeletionUiController()
    : super(initial: CollaborationState(session: sharingSession()));
  int loads = 0, confirms = 0;
  bool staleOnce = false;
  Map<String, dynamic>? reviewSent;
  List<Map<String, Object?>>? transfersSent, resolutionsSent;
  @override
  Future<Map<String, dynamic>> previewAccountDeletion() async {
    loads++;
    return preview();
  }

  @override
  Future<void> confirmAccountDeletion({
    required String previewHash,
    required String password,
    String? otp,
    List<Map<String, Object?>> ownershipTransfers = const [],
    List<Map<String, Object?>> resolutions = const [],
    List<String> ownedScopeDeletions = const [],
    Map<String, dynamic> review = const {},
  }) async {
    confirms++;
    reviewSent = review;
    transfersSent = ownershipTransfers;
    resolutionsSent = resolutions;
    if (staleOnce) {
      staleOnce = false;
      throw const CollaborationException('deletion_preview_stale');
    }
    replace(CollaborationState());
  }
}

Future<void> choices(WidgetTester tester, {bool withPassword = true}) async {
  final owner = find.byType(DropdownButtonFormField<String>);
  await tester.ensureVisible(owner);
  await tester.tap(owner);
  await tester.pumpAndSettle();
  await tester.tap(find.text('B').last);
  await tester.pumpAndSettle();
  await tester.ensureVisible(find.byType(CheckboxListTile).first);
  await tester.tap(find.byType(CheckboxListTile).first);
  await tester.pumpAndSettle();
  await tester.ensureVisible(find.byType(CheckboxListTile).last);
  await tester.tap(find.byType(CheckboxListTile).last);
  await tester.pumpAndSettle();
  if (withPassword) {
    await tester.ensureVisible(find.byKey(const ValueKey('deletion-password')));
    await tester.enterText(
      find.byKey(const ValueKey('deletion-password')),
      'step-up',
    );
  }
  await tester.ensureVisible(
    find.byKey(const ValueKey('deletion-confirmation')),
  );
  await tester.enterText(
    find.byKey(const ValueKey('deletion-confirmation')),
    'DELETE',
  );
  await tester.pumpAndSettle();
}

void main() {
  for (final width in [320.0, 390.0, 1280.0]) {
    for (final lang in ['sl', 'en']) {
      for (final dark in [false, true]) {
        testWidgets('complete deletion review $width $lang $dark', (
          tester,
        ) async {
          final controller = DeletionUiController();
          await pumpPanel(
            tester,
            controller,
            const AccountDeletionPanel(),
            width: width,
            language: lang,
            dark: dark,
          );
          await tester.tap(find.byIcon(Icons.person_remove_outlined));
          await tester.pumpAndSettle();
          expect(controller.confirms, 0);
          expect(find.textContaining('123.00 EUR'), findsOneWidget);
          await choices(tester);
          final button = find.byKey(const ValueKey('deletion-confirm'));
          await tester.ensureVisible(button);
          await tester.tap(button);
          await tester.pumpAndSettle();
          expect(controller.confirms, 1);
          expect(
            controller.transfersSent!.single['successorAccountId'],
            sharingSession(second: true).accountId,
          );
          expect(
            controller.resolutionsSent!.single['action'],
            'preserveStructure',
          );
          expect(
            find.text(
              lang == 'sl'
                  ? 'Strežnik je potrdil izbris. Nadaljujete lahko v lokalnem načinu.'
                  : 'The server confirmed deletion. You can continue in local mode.',
            ),
            findsOneWidget,
          );
          expect(tester.takeException(), null);
        });
      }
    }
  }
  testWidgets('stale review clears choices, acknowledgement and confirmation', (
    tester,
  ) async {
    final controller = DeletionUiController()..staleOnce = true;
    await pumpPanel(tester, controller, const AccountDeletionPanel());
    await tester.tap(find.byIcon(Icons.person_remove_outlined));
    await tester.pumpAndSettle();
    await choices(tester);
    await tester.ensureVisible(find.byKey(const ValueKey('deletion-confirm')));
    await tester.tap(find.byKey(const ValueKey('deletion-confirm')));
    await tester.pumpAndSettle();
    expect(controller.loads, 2);
    expect(find.byKey(const ValueKey('deletion-confirmation')), findsNothing);
    expect(find.byKey(const ValueKey('deletion-password')), findsNothing);
    expect(
      find.byType(CheckboxListTile),
      findsOneWidget,
    ); // structure remains unchecked; final confirmation hidden
    expect(
      tester.widget<CheckboxListTile>(find.byType(CheckboxListTile)).value,
      false,
    );
    expect(find.byKey(const ValueKey('deletion-confirm')), findsNothing);
  });
  testWidgets('account switch closes review before submission', (tester) async {
    final controller = DeletionUiController();
    await pumpPanel(tester, controller, const AccountDeletionPanel());
    await tester.tap(find.byIcon(Icons.person_remove_outlined));
    await tester.pumpAndSettle();
    controller.switchAccount();
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(controller.confirms, 0);
  });
}
