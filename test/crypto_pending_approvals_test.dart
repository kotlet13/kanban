import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/organizer/data/e2ee/crypto_pending_approvals.dart';
import 'package:kanban/organizer/presentation/recovery/crypto_approvals_page.dart';

Map<String, dynamic> member(
  String id, {
  String role = 'member',
  String finance = 'none',
  bool keys = false,
}) => {
  'accountId': id,
  'role': role,
  'financeRole': finance,
  'manageKeys': keys,
};

void main() {
  test(
    'complete roster diff includes additions, removal, finance and management',
    () {
      final before = [member('a'), member('b'), member('c'), member('d')];
      final after = [
        member('b', finance: 'read'),
        member('c', keys: true),
        member('d'),
        member('e'),
      ];
      final diff = cryptoApprovalRosterDiff(before, after);
      expect(diff.map((v) => v['accountId']), ['a', 'b', 'c', 'e']);
      expect(diff.first['after'], isNull);
      expect(diff.last['before'], isNull);
      expect(
        () => cryptoApprovalRosterDiff([member('a'), member('a')], []),
        throwsFormatException,
      );
    },
  );

  Future<void> mount(
    WidgetTester tester, {
    String basis = 'verifiedCheckpoint',
    Future<List<String>> Function()? preview,
    int historyCount = 2,
    Map? invitationConsequences,
    List<Map<String, dynamic>> invitations = const [],
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showDialog<bool>(
                context: context,
                builder: (_) => CryptoAccessApprovalDialog(
                  scopeName: 'Exact child',
                  sourceMembers: [member('removed'), member('changed')],
                  proposedMembers: [
                    member('changed', finance: 'write', keys: true),
                  ],
                  sourceDescriptor: const {
                    'kind': 'project',
                    'accessPolicyVersion': 2,
                    'parentScopeToken': 'old',
                  },
                  proposedDescriptor: const {
                    'kind': 'project',
                    'accessPolicyVersion': 3,
                    'parentScopeToken': 'new',
                  },
                  historyBasis: basis,
                  historyDomains: {
                    'content': {'count': historyCount},
                  },
                  invitationConsequences: invitationConsequences,
                  invitations: invitations,
                  loadPreview: preview,
                ),
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
  }

  testWidgets('review shows exact removed account and all increased authority', (
    tester,
  ) async {
    await mount(tester);
    expect(
      find.textContaining(
        'removed\nmember; no finance; does not manage protection → no access',
      ),
      findsOneWidget,
    );
    expect(
      find.textContaining('finance write; manages protection'),
      findsOneWidget,
    );
    expect(
      find.text(
        'Project members see finances; leaders see all projects → Space membership includes all projects and finances',
      ),
      findsOneWidget,
    );
    expect(find.text('The parent space relationship changes.'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Approve change'),
          )
          .onPressed,
      isNotNull,
    );
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.byType(CryptoAccessApprovalDialog), findsNothing);
  });

  testWidgets(
    'recovered baseline requires preview and separate explicit consent',
    (tester) async {
      var loads = 0;
      await mount(
        tester,
        basis: 'reviewedRecoveryBaseline',
        preview: () async {
          loads++;
          return ['Actual protected title'];
        },
      );
      FilledButton approve() => tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Approve change'),
      );
      expect(approve().onPressed, isNull);
      expect(
        tester
            .widget<CheckboxListTile>(find.byType(CheckboxListTile))
            .onChanged,
        isNull,
      );
      await tester.ensureVisible(find.text('Review next records'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Review next records'));
      await tester.pumpAndSettle();
      expect(loads, 1);
      expect(find.text('Actual protected title'), findsOneWidget);
      expect(approve().onPressed, isNull);
      await tester.ensureVisible(find.byType(CheckboxListTile));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(Checkbox));
      await tester.pumpAndSettle();
      expect(approve().onPressed, isNotNull);
    },
  );

  testWidgets(
    'missing recovery preview never enables consent for nonempty history',
    (tester) async {
      await mount(tester, basis: 'reviewedRecoveryBaseline');
      expect(
        tester
            .widget<CheckboxListTile>(find.byType(CheckboxListTile))
            .onChanged,
        isNull,
      );
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Approve change'),
            )
            .onPressed,
        isNull,
      );
    },
  );
  testWidgets('failed protected preview never enables recovery acceptance', (
    tester,
  ) async {
    await mount(
      tester,
      basis: 'reviewedRecoveryBaseline',
      preview: () async => throw StateError('unavailable'),
    );
    await tester.ensureVisible(find.text('Review next records'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Review next records'));
    await tester.pumpAndSettle();
    expect(
      find.text('The preview is not available yet. Retry.'),
      findsOneWidget,
    );
    expect(
      tester.widget<CheckboxListTile>(find.byType(CheckboxListTile)).onChanged,
      isNull,
    );
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Approve change'),
          )
          .onPressed,
      isNull,
    );
  });
  testWidgets('claimed empty inventory without actual preview stays gated', (
    tester,
  ) async {
    await mount(tester, basis: 'reviewedRecoveryBaseline', historyCount: 0);
    expect(
      tester.widget<CheckboxListTile>(find.byType(CheckboxListTile)).onChanged,
      isNull,
    );
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Approve change'),
          )
          .onPressed,
      isNull,
    );
  });

  testWidgets('successful empty preview still requires explicit acceptance', (
    tester,
  ) async {
    await mount(
      tester,
      basis: 'reviewedRecoveryBaseline',
      historyCount: 0,
      preview: () async => [],
    );
    await tester.ensureVisible(find.text('Review next records'));
    await tester.tap(find.text('Review next records'));
    await tester.pumpAndSettle();
    expect(
      find.text('No records are available in this preview.'),
      findsOneWidget,
    );
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Approve change'),
          )
          .onPressed,
      isNull,
    );
    await tester.ensureVisible(find.byType(CheckboxListTile));
    await tester.tap(find.byType(Checkbox));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Approve change'),
          )
          .onPressed,
      isNotNull,
    );
  });

  testWidgets(
    'own invitation consequences are explicit and bounded for review',
    (tester) async {
      await mount(
        tester,
        invitationConsequences: {
          'version': 1,
          'invitationCount': 21,
          'invitationSetHash': 'opaque',
        },
        invitations: [
          for (var i = 0; i < 21; i++) {'id': 'exact-invite-$i'},
        ],
      );
      expect(
        find.textContaining('cancels 21 outstanding invitations'),
        findsOneWidget,
      );
      expect(find.text('Invitation · exact-invite-20'), findsNothing);
      await tester.ensureVisible(find.text('Review next invitations'));
      await tester.tap(find.text('Review next invitations'));
      await tester.pumpAndSettle();
      expect(find.text('Invitation · exact-invite-20'), findsOneWidget);
    },
  );
}
