<?php
/** NEW replacement/CAS guards; historical successful invitation scenarios are not executed. */
use Kanboard\Plugin\FamilyHub\Model\NativeCryptoV2Codec as V2;
use Kanboard\Plugin\FamilyHub\Model\NativeCryptoScopeV2 as Scopes;
require __DIR__.'/crypto5-invitation-preauthorization-memory-fixture.php';
[$sid,$body,$head]=scopeFixture(3,$owner);
$scope=$prepared->access($sid,$owner);$resolved=$prepared->resolve(['scopeId'=>$sid,'recipient'=>$recipient['email'],'role'=>'member'],$owner);
function pendingReplacement($op,$replaces=null){global $sid,$head,$owner,$recipient,$resolved;
    $id=uid();$p=['scopeId'=>$sid,'invitationId'=>$id,'recipient'=>$resolved['recipient'],'role'=>'member','expiresAt'=>time()+3600,'language'=>'en','expectedAccessRevision'=>0,'membershipHeadHash'=>$head,'authorDirectoryHeadHash'=>$owner['head'],'tokenHash'=>hash('sha256',$id),'preauthorization'=>$resolved['preauthorization']];if($replaces!==null)$p['replacesInvitationId']=$replaces;
    $proof=signCommand($op,$p,$owner);$hash=V2::hash((object)$proof);
    sql('INSERT INTO familyhub_crypto_invitations_v2 VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,NULL)',[$id,$sid,$owner['user']['account_id'],$owner['device']['id'],'email',$recipient['email'],$recipient['user']['account_id'],'member',$p['tokenHash'],time(),$p['expiresAt'],'pending',json_encode($proof),'en']);
    return ['id'=>$id,'proof'=>$proof,'slot'=>['accountId'=>$recipient['user']['account_id'],'invitationId'=>$id,'preauthorizationProofHash'=>$hash,'invitationScopeId'=>$sid],'intent'=>['accountId'=>$recipient['user']['account_id'],'invitationId'=>$id,'preauthorizationProofHash'=>$hash]];
}
$old=pendingReplacement('crypto2.invitations.create');$member=$resolved['preauthorization']['member'];$body['members'][]=$member;
$prepared->synchronize($scope,[$old['slot']],$body['members']);sql("INSERT INTO familyhub_members VALUES(?,?,?,'member',0)",[$sid,$recipient['user']['id'],$recipient['user']['account_id']]);
$unrelated=pendingReplacement('crypto2.invitations.create');
denied(fn()=>$prepared->synchronize($scope,[$unrelated['slot']],$body['members']),'crypto_invitation_preauthorization_conflict','a live pending slot cannot be overwritten by an unrelated create');
ck(sql('SELECT invitation_id FROM familyhub_crypto_invitation_reservations_v5 WHERE scope_id=?',[$sid])[0]['invitation_id']===$old['id'],'denied replacement preserves the exact prior reservation');
$next=pendingReplacement('crypto2.invitations.resend',$old['id']);
$body['membershipIntents']=[$next['intent']];$body['invitationPreauthorizations']=[$next['slot']];$body['expectedAccessRevision']=0;$body['accessRevision']=0;$body['accessBasis']=$scopes->accessBasis($scope);
$planner=new \ReflectionMethod(Scopes::class,'membershipPlan');$planner->setAccessible(true);$apply=new \ReflectionMethod(Scopes::class,'applyMembershipPlan');$apply->setAccessible(true);
$plan=$planner->invoke($scopes,$scope,$body,$scopes->current($sid),$owner);
ck($plan['changed']===false&&$plan['additions'][$recipient['user']['account_id']]['preauthorizationReplacement']===true,'exact signed resend consumes its intent without inventing a roster access revision');
$apply->invoke($scopes,$scope,$plan);
$reservation=sql('SELECT * FROM familyhub_crypto_invitation_reservations_v5 WHERE scope_id=?',[$sid])[0];
ck($reservation['invitation_id']===$next['id']&&$reservation['proof_hash']===$next['slot']['preauthorizationProofHash']&&sql('SELECT active FROM familyhub_members WHERE scope_id=? AND account_id=?',[$sid,$recipient['user']['account_id']])[0]['active']==0,'same-account resend replaces metadata while retaining inactive membership');
ck(sql('SELECT access_revision FROM familyhub_scopes WHERE id=?',[$sid])[0]['access_revision']==0&&json_decode(sql('SELECT authorization FROM familyhub_crypto_invitations_v2 WHERE id=?',[$old['id']])[0]['authorization'],true)===$old['proof'],'replacement keeps exact prior signed invitation and unchanged access CAS');
sql("UPDATE familyhub_crypto_invitations_v2 SET state='revoked' WHERE id=?",[$next['id']]);
$reinvite=pendingReplacement('crypto2.invitations.create');$body['membershipIntents']=[$reinvite['intent']];$body['invitationPreauthorizations']=[$reinvite['slot']];$plan=$planner->invoke($scopes,$scope,$body,$scopes->current($sid),$owner);$apply->invoke($scopes,$scope,$plan);
ck($plan['changed']===false&&sql('SELECT invitation_id FROM familyhub_crypto_invitation_reservations_v5 WHERE scope_id=?',[$sid])[0]['invitation_id']===$reinvite['id'],'new explicit create can replace a revoked same-account slot without an extra roster revision');
sql('UPDATE familyhub_crypto_invitations_v2 SET expires_at=? WHERE id=?',[time()-1,$reinvite['id']]);
$afterExpiry=pendingReplacement('crypto2.invitations.create');$body['membershipIntents']=[$afterExpiry['intent']];$body['invitationPreauthorizations']=[$afterExpiry['slot']];$plan=$planner->invoke($scopes,$scope,$body,$scopes->current($sid),$owner);$apply->invoke($scopes,$scope,$plan);
ck($plan['changed']===false&&sql('SELECT invitation_id FROM familyhub_crypto_invitation_reservations_v5 WHERE scope_id=?',[$sid])[0]['invitation_id']===$afterExpiry['id'],'new explicit create can replace an expired same-account slot');
echo json_encode(['status'=>'pass','checks'=>$checks,'fixture'=>'new in-memory SQLite replacement model/CAS seams','limitations'=>'No HTTP, native, key rotation or receipt transport claim']).PHP_EOL;
