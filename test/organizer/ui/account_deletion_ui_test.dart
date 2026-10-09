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
  Map<String, dynamic>? providedPreview;
  Map<String, dynamic>? reviewSent;
  List<Map<String, Object?>>? transfersSent, resolutionsSent;
  @override
  Future<Map<String, dynamic>> previewAccountDeletion() async {
    loads++;
    return providedPreview ?? preview();
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
  for (final width in [320.0, 1280.0]) {
    for (final lang in ['sl', 'en']) {
      testWidgets('policy3 conditional shared payment facts $width $lang', (
        tester,
      ) async {
        final p = preview()..['policyVersion'] = 3;
        p['impact'] = {
          'privatePaymentProjectionsDeleted': 1,
          'sharedPaymentReceiptsRetained': 1,
        };
        p['linkedFinancialFacts'] = [
          {
            'scopeId': sharingScopeId,
            'eventsRetainedIfScopeKept': 1,
            'eventsDeletedIfScopeDeleted': 1,
            'refundLegs': 2,
            'reason': 'retained_shared_financial_fact',
          },
        ];
        p['resolutions'] = [
          {
            'scopeId': sharingScopeId,
            'recordId': sharingScopeId,
            'type': 'financeEntry',
            'action': 'preserveStructure',
            'name': 'Expense',
          },
        ];
        final controller = DeletionUiController()..providedPreview = p;
        await pumpPanel(
          tester,
          controller,
          const AccountDeletionPanel(),
          width: width,
          language: lang,
        );
        await tester.tap(find.byIcon(Icons.person_remove_outlined));
        await tester.pumpAndSettle();
        expect(
          find.textContaining(
            lang == 'sl' ? 'ob ohranitvi 1 plačil' : '1 payments if kept',
          ),
          findsOneWidget,
        );
        expect(
          find.textContaining(
            lang == 'sl'
                ? 'povezave z zasebnimi računi'
                : 'Private projections and account links',
          ),
          findsOneWidget,
        );
        expect(controller.confirms, 0);
        await choices(tester);
        await tester.ensureVisible(
          find.byKey(const ValueKey('deletion-confirm')),
        );
        await tester.tap(find.byKey(const ValueKey('deletion-confirm')));
        await tester.pumpAndSettle();
        expect(controller.reviewSent!['policyVersion'], 3);
        expect(
          controller.resolutionsSent!.single['action'],
          'preserveStructure',
        );
        expect(tester.takeException(), isNull);
      });
    }
  }
  testWidgets('policy3 deleted source does not request expense retention', (
    tester,
  ) async {
    final p = preview()..['policyVersion'] = 3;
    (p['ownedScopes'] as List).first['canDeleteScope'] = true;
    p['linkedFinancialFacts'] = [
      {
        'scopeId': sharingScopeId,
        'eventsRetainedIfScopeKept': 1,
        'eventsDeletedIfScopeDeleted': 1,
        'refundLegs': 2,
        'reason': 'retained_shared_financial_fact',
      },
    ];
    p['resolutions'] = [
      {
        'scopeId': sharingScopeId,
        'recordId': sharingScopeId,
        'type': 'financeEntry',
        'action': 'preserveStructure',
        'name': 'Expense',
      },
    ];
    final controller = DeletionUiController()..providedPreview = p;
    await pumpPanel(tester, controller, const AccountDeletionPanel());
    await tester.tap(find.byIcon(Icons.person_remove_outlined));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byType(DropdownButtonFormField<String>));
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(
      find
          .byWidgetPredicate(
            (w) => w is DropdownMenuItem<String> && w.value == 'delete',
          )
          .last,
    );
    await tester.pumpAndSettle();
    expect(find.text('Expense'), findsNothing);
    expect(find.byType(CheckboxListTile), findsOneWidget);
    expect(controller.confirms, 0);
    expect(tester.takeException(), isNull);
  });
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
