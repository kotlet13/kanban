import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/l10n/app_localizations.dart';
import 'package:kanban/organizer/data/e2ee/account_crypto_v2_workflow.dart';
import 'package:kanban/organizer/data/e2ee/account_directory_repository.dart';
import 'package:kanban/organizer/data/e2ee/crypto_restore_reconciler.dart';
import 'package:kanban/organizer/presentation/recovery/crypto_restore_page.dart';

class _Directory implements AccountDirectoryRepository {
  @override bool Function() get isCurrent=>()=>true;
  @override dynamic noSuchMethod(Invocation invocation)=>super.noSuchMethod(invocation);
}
class _Account implements AccountCryptoV2Workflow {
  @override AccountDirectoryRepository get directory=>_Directory();
  @override dynamic noSuchMethod(Invocation invocation)=>super.noSuchMethod(invocation);
}
class _Service extends CryptoRestoreReconciler {
  _Service(super.account,{required this.pending});
  final bool pending;
  int commits=0;
  @override Future<CryptoRestoreReport> inspect()async=>CryptoRestoreReport(backupCount:2,directoryCount:2,scopeCount:1,recordCount:4,unconfirmedHistoryCount:pending?1:0,identityReviewAccounts:pending?['private-account-id']:[],historyReviewScopes:pending?['private-scope-id']:[]);
  @override Future<void> reconcile()async {commits++;}
}
void main(){
  for(final language in ['sl','en']) {
    testWidgets('320px 2x $language restore preserves pending work and requires explicit confirmation',(tester)async {
      tester.view.physicalSize=const Size(320,640);tester.view.devicePixelRatio=1;
      addTearDown(tester.view.resetPhysicalSize);addTearDown(tester.view.resetDevicePixelRatio);
      final account=_Account(),service=_Service(_Account(),pending:false);
      await tester.pumpWidget(MaterialApp(locale:Locale(language),localizationsDelegates:AppLocalizations.localizationsDelegates,supportedLocales:AppLocalizations.supportedLocales,builder:(context,child)=>MediaQuery(data:MediaQuery.of(context).copyWith(textScaler:TextScaler.linear(2)),child:child!),home:CryptoRestorePage(account:account,serviceFactory:(_)=>service)));
      await tester.pumpAndSettle();
      expect(service.commits,0);
      final context=tester.element(find.byType(CryptoRestorePage)),l=AppLocalizations.of(context)!;
      await tester.scrollUntilVisible(find.text(l.cryptoRestoreConfirm),160,scrollable:find.byType(Scrollable).first,maxScrolls:30);
      await tester.ensureVisible(find.text(l.cryptoRestoreConfirm));await tester.pumpAndSettle();
      expect(find.text(l.cryptoRestoreConfirm).hitTestable(),findsOneWidget);
      await tester.tap(find.text(l.cryptoRestoreConfirm));await tester.pumpAndSettle();
      expect(service.commits,1);expect(find.text(l.cryptoRestoreComplete),findsOneWidget);expect(tester.takeException(),isNull);
      final pending=_Service(account,pending:true);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(MaterialApp(locale:Locale(language),localizationsDelegates:AppLocalizations.localizationsDelegates,supportedLocales:AppLocalizations.supportedLocales,home:CryptoRestorePage(account:account,serviceFactory:(_)=>pending)));
      await tester.pumpAndSettle();
      expect(find.text(l.cryptoRestoreConfirm),findsNothing);
      expect(find.text('private-account-id'),findsNothing);expect(find.text('private-scope-id'),findsNothing);
      await tester.scrollUntilVisible(find.text(l.cryptoContinueLocally),160,scrollable:find.byType(Scrollable).first,maxScrolls:30);
      expect(pending.commits,0);expect(tester.takeException(),isNull);
    });
  }
}
