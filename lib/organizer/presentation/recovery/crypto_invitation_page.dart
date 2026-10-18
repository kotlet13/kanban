import 'package:flutter/material.dart';
import '../../../l10n/l10n.dart';
import '../../data/e2ee/account_crypto_v2_workflow.dart';
import '../../data/e2ee/invite_crypto_repository.dart';
import '../../data/e2ee/session_crypto_access.dart';
import '../../data/e2ee/scope_crypto_manager.dart';

/// Initial identity comparison is deliberate; routine membership and envelope
/// contributions travel through the authenticated queue without copying JSON.
class CryptoInvitationPage extends StatefulWidget {
  const CryptoInvitationPage({required this.account,required this.invitationId,this.scopeId,this.label,super.key});
  final AccountCryptoV2Workflow account;
  final String invitationId;
  final String? scopeId,label;
  @override State<CryptoInvitationPage> createState()=>_CryptoInvitationPageState();
}
class _CryptoInvitationPageState extends State<CryptoInvitationPage> {
  late final invites=InviteCryptoRepository(SessionCryptoAccess(account:widget.account));
  bool _busy=false,_failed=false,_pending=false,_verified=false;
  VerifiedCryptoInvitation? _invite;
  ScopeRotationReview? _review;
  @override void initState(){super.initState();_load();}
  Future<void> _run(Future<void> Function() action)async {
    if(_busy)return;
    setState((){_busy=true;_failed=false;});
    try {await action();}catch(_){if(mounted)setState(()=>_failed=true);}
    finally {if(mounted)setState(()=>_busy=false);}
  }
  Future<void> _load()=>_run(()async {
    if(widget.scopeId==null) {
      final opened=await invites.resumeAccepted(widget.invitationId);
      if(!mounted)return;
      if(opened!=null){Navigator.of(context).pop(opened);return;}
    }
    final invite=widget.scopeId==null?await invites.inspect(invitationId:widget.invitationId):await invites.acceptedRecipient(widget.scopeId!,widget.invitationId);
    var trusted=false;
    try {await invites.access.identities.requireVerified(invite.creator.accountId,invites.access.identities.fingerprint(invite.creator));trusted=true;}catch(_){/* Comparison remains explicit. */}
    if(mounted)setState((){_invite=invite;_verified=trusted;});
  });
  Future<void> _compare()=>_run(()async {
    final invite=_invite;if(invite==null)return;
    final input=TextEditingController();
    String? card;
    try {card=await showDialog<String>(context:context,builder:(dialog)=>AlertDialog(
      title:Text(context.l10n.cryptoCompareContact),content:SingleChildScrollView(child:Column(mainAxisSize:MainAxisSize.min,children:[
        Text(context.l10n.cryptoVerifyContactExplanation),const SizedBox(height:16),TextField(controller:input,minLines:2,maxLines:6,decoration:InputDecoration(labelText:context.l10n.cryptoPastePublicCard)),
      ])),actions:[TextButton(onPressed:()=>Navigator.pop(dialog),child:Text(context.l10n.cancel)),FilledButton(onPressed:()=>Navigator.pop(dialog,input.text),child:Text(context.l10n.cryptoCompareContact))]));}
    finally {input.dispose();}
    if(card==null || !mounted)return;
    await invites.compareCreator(invite,card);
    if(mounted)setState(()=>_verified=true);
  });
  Future<void> _continue()=>_run(()async {
    final invite=_invite;if(invite==null || !_verified)return;
    if(widget.scopeId==null) {
      await invites.accept(invite,actionId:widget.invitationId);
      if(mounted)setState(()=>_pending=true);
      return;
    }
    final manager=invites.manager;
    final pending=await manager.pendingRotationReviews(widget.scopeId!);
    final review=pending.isNotEmpty?pending.first:await manager.reviewRotation(widget.scopeId!);
    if(!mounted)return;
    if(_review?.id!=review.id) {
      final allowed=await showDialog<bool>(context:context,builder:(dialog)=>AlertDialog(
        title:Text(context.l10n.cryptoInvitationGrantTitle),
        content:SingleChildScrollView(child:Column(mainAxisSize:MainAxisSize.min,crossAxisAlignment:CrossAxisAlignment.start,children:[
          Text(context.l10n.cryptoInvitationGrantExplanation),
          for(final domain in review.domains.entries)Text('${domain.key=="finance"?context.l10n.organizerFinances:context.l10n.cryptoMigrationTitle}: ${domain.value['count']}'),
        ])),actions:[TextButton(onPressed:()=>Navigator.pop(dialog,false),child:Text(context.l10n.cancel)),FilledButton(onPressed:()=>Navigator.pop(dialog,true),child:Text(context.l10n.cryptoInvitationGrantConfirm))]));
      if(allowed!=true || !mounted)return;
      _review=review;
    }
    await invites.admit(invite,review);
    if(mounted)Navigator.of(context).pop(widget.scopeId);
  });
  @override Widget build(BuildContext context) {
    final l=context.l10n;
    return Scaffold(appBar:AppBar(title:Text(widget.label??l.cryptoInvitationGrantTitle)),body:SafeArea(child:Center(child:ConstrainedBox(constraints:const BoxConstraints(maxWidth:640),child:ListView(padding:const EdgeInsets.all(24),children:[
      Text(widget.scopeId==null?l.cryptoInvitationVerifyCreator:l.cryptoInvitationGrantExplanation),
      if(_busy)const LinearProgressIndicator(),
      if(_failed)Text(l.accountRecoveryFailed,style:TextStyle(color:Theme.of(context).colorScheme.error)),
      if(_pending)Text(l.cryptoInvitationPendingKeys),
      if(_invite!=null && !_verified)OutlinedButton(onPressed:_busy?null:_compare,child:Text(l.cryptoCompareContact)),
      if(_verified)Text(l.cryptoContactVerified),
      if(_verified && !_pending)FilledButton(onPressed:_busy?null:_continue,child:Text(widget.scopeId==null?l.invitationFlowJoinSpace:l.cryptoInvitationGrantConfirm)),
      TextButton(onPressed:_busy?null:_load,child:Text(l.cryptoMigrationRetry)),
      TextButton(onPressed:()=>Navigator.of(context).pop(),child:Text(l.cryptoContinueLocally)),
    ])))));
  }
}
