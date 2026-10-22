// New L3 composition coverage. State/backend transitions are synthetic; widgets,
// status routing, session gating and the export helper are production code.
import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/l10n/app_localizations.dart';
import 'package:kanban/organizer/presentation/shared/sharing_conflicts.dart';
import 'package:kanban/organizer/presentation/shared/sharing_workspace.dart';
import 'package:kanban/organizer/state/collaboration_provider.dart';

import 'sharing_ui_fixture.dart';

const _draft = {
  'title': 'Ohranjeni lokalni osnutek L3',
  'notes': 'Samo sintetično',
};
final _conflict = SharedConflict(
  id: 'l3-terminal-conflict',
  scopeId: sharingScopeId,
  recordId: 'l3-task',
  recordType: SharedRecordType.task,
  reason: 'conflict',
  localPayload: _draft,
  // H4 permits an unknown remote winner after an exact terminal rejection.
  // This is deliberately not a remote deletion assertion.
  remotePayload: null,
);

CollaborationState _state({
  bool pending = false,
  bool revoked = false,
  bool expired = false,
}) {
  final session = sharingSession();
  return CollaborationState(
    session: expired
        ? AccountSession.fromJson({
            ...session.toJson(),
            'expiresAt': '2000-01-01T00:00:00.000Z',
          })
        : session,
    sessionInvalid: expired,
    scopes: [sharingScope(revoked: revoked, blocked: revoked)],
    selectedSpaceId: sharingScopeId,
    data: {sharingScopeId: sharingData()},
    pendingCount: pending ? 1 : 0,
    blockedCount: revoked ? 1 : 0,
    conflicts: pending ? [] : [_conflict],
    lastError: CollaborationException(
      expired
          ? 'session_expired'
          : revoked
          ? 'permission_revoked'
          : pending
          ? 'crypto_reconciliation_required'
          : 'conflict',
    ),
  );
}

class _Controller extends SharingUiController {
  _Controller({required CollaborationState initial}) : super(initial: initial);
  CollaborationState? retryResult;
  int exports = 0;
  @override
  Future<void> syncNow() async {
    calls.add('sync');
    if (retryResult != null) replace(retryResult!);
  }

  @override
  Future<String> exportUnsentWork() async {
    exports++;
    return jsonEncode({
      'drafts': [_draft],
    });
  }
}

class _Picker extends FilePicker {
  final saved = <Uint8List>[];
  @override
  Future<String?> saveFile({
    String? dialogTitle,
    String? fileName,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Uint8List? bytes,
    bool lockParentWindow = false,
  }) async {
    expect(type, FileType.custom);
    expect(allowedExtensions, ['json']);
    saved.add(Uint8List.fromList(bytes!));
    return null; // Synthetic cancel: capture the offered bytes, write no file.
  }
}

Future<void> _pump(WidgetTester tester, _Controller controller) async {
  tester.view.physicalSize = const Size(800, 1200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        ...await sharingUiInfrastructureOverrides(
          tester,
          controller,
          emptyLocalCatalog: true,
        ),
        collaborationProvider.overrideWith(() => controller),
      ],
      child: MaterialApp(
        locale: const Locale('sl'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => Scaffold(
            body: SingleChildScrollView(
              child: SharingWorkspace(
                view: SharingView.tasks,
                selectedScopeId: sharingScopeId,
                showScopePicker: false,
                onScopeSelected: (_) {},
                onConnect: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) =>
                        const Scaffold(body: Text('L3 prijavna pot')),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Finder get _refresh =>
    find.byKey(const ValueKey('sharing-sync-dialog-refresh'));
Future<void> _details(WidgetTester tester) =>
    _tap(tester, find.byKey(const ValueKey('sharing-sync-status-cloud')));
Future<void> _export(
  WidgetTester tester,
  _Controller controller,
  _Picker picker,
) async {
  final buttons = find.widgetWithText(
    TextButton,
    'Shrani moje neusklajene spremembe',
  );
  final comparison = find.byType(SharingConflictsPage);
  await _tap(
    tester,
    comparison.evaluate().isNotEmpty
        ? find.descendant(of: comparison, matching: buttons)
        : buttons.first,
  );
  expect(controller.exports, 1);
  expect(picker.saved, hasLength(1));
  expect(jsonDecode(utf8.decode(picker.saved.single)), {
    'drafts': [_draft],
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _Picker picker;
  late FilePicker previousPicker;
  setUp(() {
    try {
      previousPicker = FilePicker.platform;
    } catch (_) {
      // A focused widget process need not have registered desktop plugins.
      FilePickerIO.registerWith();
      previousPicker = FilePicker.platform;
    }
    picker = _Picker();
    FilePicker.platform = picker;
  });
  tearDown(() => FilePicker.platform = previousPicker);

  testWidgets(
    'L3 pending encrypted work retries into retained task comparison',
    (tester) async {
      final controller = _Controller(initial: _state(pending: true))
        ..retryResult = _state();
      await _pump(tester, controller);
      await _details(tester);
      expect(
        find.textContaining(
          'Lokalni podatki in čakajoče spremembe so ohranjeni.',
        ),
        findsOneWidget,
      );
      expect(find.text('Čakajoče spremembe: 1'), findsOneWidget);
      expect(find.text('Prijavi se'), findsNothing);
      expect(tester.widget<TextButton>(_refresh).onPressed, isNotNull);
      await _tap(tester, _refresh);
      expect(controller.calls, ['sync']);
      expect(find.text('Sporne spremembe: 1'), findsOneWidget);
      expect(find.text('Čakajoče spremembe: 0'), findsOneWidget);
      await _tap(tester, find.widgetWithText(TextButton, 'Preglej spremembe'));
      expect(find.byType(SharingConflictsPage), findsOneWidget);
      expect(find.text(_draft['title']!), findsOneWidget);
      expect(
        controller.state.requireValue.conflicts.single.localPayload,
        _draft,
      );
      expect(controller.calls, ['sync']); // No automatic conflict resolution.
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'L3 revoked retained conflict stays readable with export and no resolution',
    (tester) async {
      final controller = _Controller(initial: _state(revoked: true));
      await _pump(tester, controller);
      expect(
        find.text('Dostop je preklican. Čakajoče spremembe niso bile poslane.'),
        findsOneWidget,
      );
      expect(find.text('Pripravi zemljo'), findsNothing);
      await _details(tester);
      expect(find.textContaining('Seja je potekla.'), findsNothing);
      expect(find.text('Prijavi se'), findsNothing);
      await _tap(tester, find.widgetWithText(TextButton, 'Preglej spremembe'));
      expect(find.byType(SharingConflictsPage), findsOneWidget);
      expect(find.text(_draft['title']!), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Obdrži mojo različico'),
            )
            .onPressed,
        isNull,
      );
      expect(
        tester
            .widget<OutlinedButton>(
              find.widgetWithText(
                OutlinedButton,
                'Obdrži strežniško različico',
              ),
            )
            .onPressed,
        isNull,
      );
      await _export(tester, controller, picker);
      expect(controller.calls, isEmpty);
      expect(controller.state.requireValue.conflicts.single, same(_conflict));
      expect(controller.state.requireValue.scopes.single.revoked, isTrue);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'L3 genuine expiry keeps draft export but routes retry to sign in',
    (tester) async {
      final controller = _Controller(initial: _state(expired: true));
      await _pump(tester, controller);
      await _details(tester);
      expect(
        find.textContaining('Seja je potekla. Ponovno se prijavi;'),
        findsOneWidget,
      );
      expect(find.textContaining('Račun se še nalaga'), findsNothing);
      expect(find.textContaining('Dostop je preklican.'), findsNothing);
      expect(tester.widget<TextButton>(_refresh).onPressed, isNull);
      await _export(tester, controller, picker);
      await _tap(tester, find.widgetWithText(TextButton, 'Prijavi se'));
      expect(find.text('L3 prijavna pot'), findsOneWidget);
      expect(controller.calls, isEmpty);
      expect(
        controller.state.requireValue.conflicts.single.localPayload,
        _draft,
      );
      expect(
        controller.state.requireValue.session!.expiresAt.isBefore(
          DateTime.now(),
        ),
        isTrue,
      );
      expect(tester.takeException(), isNull);
    },
  );
}
