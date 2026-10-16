// Real current Android widgets, isolated synthetic gateways, no live accounts.
// JIVIE_UI_CAPTURE=1 flutter test tools/release/invitations_documents_capture_test.dart
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/l10n/app_localizations.dart';
import 'package:kanban/theme/jivie_theme.dart';
import 'package:kanban/organizer/data/pending_invitation_store.dart';
import 'package:kanban/organizer/domain/spreadsheet_models.dart';
import 'package:kanban/organizer/platform/invitation_links/invitation_link.dart';
import 'package:kanban/organizer/presentation/tables/spreadsheet_tables_page.dart';
import 'package:kanban/organizer/presentation/shared/invitation_wizard.dart';
import 'package:kanban/organizer/state/collaboration_provider.dart';
import '../../test/organizer/ui/spreadsheet_ui_test.dart' show MemorySheets;
import '../../test/organizer/ui/sharing_ui_fixture.dart';

String _t(String locale, String sl, String en) => locale == 'sl' ? sl : en;

class _InviteController extends SharingUiController {
  _InviteController(this.locale);
  final String locale;
  @override
  Future<SharedInvitationPreview> previewInvitation({
    required String serverUrl,
    required String token,
    bool allowLocalHttp = false,
  }) async => SharedInvitationPreview(
    scopeName: _t(locale, 'Naš dom', 'Our home'),
    scopeId: sharingScopeId,
    kind: SharedScopeKind.household,
    recipientUsername: 'ana',
    recipientEmail: 'ana@example.invalid',
    inviterName: _t(locale, 'Luka', 'Luke'),
    role: SharedRole.member,
    expiresAt: DateTime.now().add(const Duration(days: 1)),
    registrationAllowed: false,
    contractVersion: 3,
    accessScope: 'space',
    requiresExplicitAcceptance: true,
  );
}

Future<void> _fonts(WidgetTester tester) async {
  await tester.runAsync(() async {
    final sdk = Platform.resolvedExecutable.split('/bin/cache/').first;
    final root = '$sdk/bin/cache/artifacts/material_fonts';
    for (final family in [
      'Roboto',
      'CupertinoSystemText',
      'CupertinoSystemDisplay',
    ]) {
      final bytes = await File('$root/Roboto-Regular.ttf').readAsBytes();
      await (FontLoader(
        family,
      )..addFont(Future.value(ByteData.sublistView(bytes)))).load();
    }
    final icons = await File('$root/MaterialIcons-Regular.otf').readAsBytes();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(Future.value(ByteData.sublistView(icons)))).load();
  });
}

Future<void> _capture(
  WidgetTester tester,
  GlobalKey key,
  String name,
  String locale,
) async {
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull);
  await tester.runAsync(() async {
    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 2);
    expect((image.width, image.height), (720, 1280));
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final root =
        Platform.environment['JIVIE_STORE_CAPTURE_OUT'] ??
        'build/qa/invitations-documents-store-20261016';
    final file = File('$root/android-phone/$locale/$name.png');
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

void main() {
  for (final locale in ['sl', 'en']) {
    testWidgets('Android table and invitation store capture $locale', (
      tester,
    ) async {
      final oldShadows = debugDisableShadows;
      debugDisableShadows = false;
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      addTearDown(() {
        debugDisableShadows = oldShadows;
        debugDefaultTargetPlatformOverride = null;
      });
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await _fonts(tester);
      final sheets = MemorySheets()
        ..document = SpreadsheetDocument(
          id: 'capture-table',
          scopeId: 'organization-1',
          title: _t(locale, 'Načrt skupnega vrta', 'Community garden plan'),
          revision: 1,
          updatedAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
          cells: {
            'A1': _t(locale, 'Postavka', 'Item'),
            'B1': _t(locale, 'Načrt EUR', 'Plan EUR'),
            'C1': _t(locale, 'Poraba EUR', 'Spent EUR'),
            'A2': _t(locale, 'Semena', 'Seeds'),
            'B2': '35',
            'C2': '32',
            'A3': _t(locale, 'Zemlja', 'Soil'),
            'B3': '80',
            'C3': '74',
            'A4': _t(locale, 'Orodje', 'Tools'),
            'B4': '60',
            'C4': '48',
            'A5': _t(locale, 'Zelišča', 'Herbs'),
            'B5': '25',
            'C5': '21',
            'A6': _t(locale, 'Lončki', 'Pots'),
            'B6': '30',
            'C6': '26',
            'A7': _t(locale, 'Skupaj', 'Total'),
            'B7': '=SUM(B2:B6)',
            'C7': '=SUM(C2:C6)',
          },
        );
      final controller = _InviteController(locale);
      final key = GlobalKey();
      Widget host(Widget home) => ProviderScope(
        overrides: [
          collaborationProvider.overrideWith(() => controller),
          pendingInvitationStoreProvider.overrideWithValue(
            MemoryPendingInvitationStore(),
          ),
          securePendingInvitationProvider.overrideWith(
            (ref) async => controller.savedInvitation,
          ),
        ],
        child: RepaintBoundary(
          key: key,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            locale: Locale(locale),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            theme: buildJivieTheme(Brightness.light),
            home: home,
          ),
        ),
      );
      await tester.pumpWidget(host(SpreadsheetTablesPage(gateway: sheets)));
      await tester.pumpAndSettle();
      await tester.tap(find.text(sheets.document.title));
      await tester.pumpAndSettle();
      expect(find.byType(SpreadsheetDetailPage), findsOneWidget);
      await tester.tapAt(const Offset(90, 560));
      await tester.pumpAndSettle();
      await _capture(tester, key, '09-spreadsheet', locale);
      expect(sheets.saves, 0);
      expect(sheets.lease, isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpWidget(
        host(
          Consumer(
            builder: (context, ref, _) => Scaffold(
              body: TextButton(
                onPressed: () => showInvitationWizard(
                  context,
                  ref,
                  initialLink: InvitationLink(
                    serverUrl: sharingSession().serverUrl,
                    token: 'fhi3_${'a' * 64}',
                  ),
                  originConfirmed: true,
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await _capture(tester, key, '10-invitation', locale);
      expect(controller.calls, isNot(contains('accept')));
      await tester.pumpWidget(const SizedBox.shrink());
      debugDisableShadows = oldShadows;
      debugDefaultTargetPlatformOverride = null;
    }, skip: Platform.environment['JIVIE_UI_CAPTURE'] != '1');
  }
}
