<?php
/** NEW final-contract guards: no execution of the historical 17-control entrypoint. */
use Kanboard\Plugin\FamilyHub\Model\NativeCryptoV2Codec as V2;
require __DIR__.'/crypto5-invitation-preauthorization-memory-fixture.php';
[$sid,$body,$head]=scopeFixture(3,$owner);
denied(fn()=>$prepared->resolveRecipient('unknown@synthetic.invalid'),'crypto_invitation_recipient_unregistered','wholly unknown email is the explicit unregistered fallback result');
sql('SAVEPOINT incomplete_directory');sql('DELETE FROM familyhub_crypto_directory WHERE account_id=?',[$recipient['user']['account_id']]);sql('DELETE FROM familyhub_crypto_directory_state WHERE account_id=?',[$recipient['user']['account_id']]);
denied(fn()=>$prepared->resolve(['scopeId'=>$sid,'recipient'=>$recipient['email'],'role'=>'member'],$owner),'crypto_invitation_recipient_setup_required','registered account without crypto directory cannot fall back to manual unknown-recipient mode');sql('ROLLBACK TO SAVEPOINT incomplete_directory');sql('RELEASE SAVEPOINT incomplete_directory');
$resolved=$prepared->resolve(['scopeId'=>$sid,'recipient'=>$recipient['email'],'role'=>'member'],$owner);$id=uid();
$payload=['scopeId'=>$sid,'invitationId'=>$id,'recipient'=>$resolved['recipient'],'role'=>'member','expiresAt'=>time()+3600,'language'=>'en','expectedAccessRevision'=>0,'membershipHeadHash'=>$head,'authorDirectoryHeadHash'=>$owner['head'],'tokenHash'=>hash('sha256','new guard token'),'preauthorization'=>$resolved['preauthorization']];$creation=signCommand('crypto2.invitations.create',$payload,$owner);$proofHash=V2::hash((object)$creation);
sql('INSERT INTO familyhub_crypto_invitations_v2 VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,NULL)',[$id,$sid,$owner['user']['account_id'],$owner['device']['id'],'email',$recipient['email'],$recipient['user']['account_id'],'member',$payload['tokenHash'],time(),$payload['expiresAt'],'pending',json_encode($creation),'en']);
$slot=['accountId'=>$recipient['user']['account_id'],'invitationId'=>$id,'preauthorizationProofHash'=>$proofHash,'invitationScopeId'=>$sid];$member=$resolved['preauthorization']['member'];$body['members'][]=$member;$body['invitationPreauthorizations']=[$slot];
$prepared->synchronize($prepared->access($sid,$owner),[$slot],$body['members']);sql("INSERT INTO familyhub_members VALUES(?,?,?,'member',0)",[$sid,$recipient['user']['id'],$recipient['user']['account_id']]);
sql('SAVEPOINT policy_transition');$prepared->retireForAccess($sid,null,true);
ck(count($scopes->effectiveMembers($sid))===1&&sql('SELECT state FROM familyhub_crypto_invitations_v2 WHERE id=?',[$id])[0]['state']==='revoked','access policy projection retires and revokes an unaccepted prepared slot');sql('ROLLBACK TO SAVEPOINT policy_transition');sql('RELEASE SAVEPOINT policy_transition');
// Trusted consent projection must have both a retained recipient signature and the inactive row.
$acceptance=signCommand('crypto2.invitations.accept',['scopeId'=>$sid,'invitationId'=>$id],$recipient);$acceptedHash=V2::hash((object)$acceptance);
sql("INSERT INTO familyhub_crypto_invitation_acceptances_v2 VALUES(?,?,?,?,?,?,?,?,?,?,'consumed')",[$id,$acceptedHash,$recipient['user']['account_id'],$recipient['device']['id'],$member['rootSigningKeyBase64'],$member['rootEncryptionKeyBase64'],$member['identityEpochId'],$recipient['head'],json_encode($acceptance),time()]);
sql("UPDATE familyhub_crypto_invitations_v2 SET state='consumed' WHERE id=?",[$id]);sql('UPDATE familyhub_members SET active=1 WHERE scope_id=? AND account_id=?',[$sid,$recipient['user']['account_id']]);
$prepared->retireForAccess($sid,$recipient['user']['account_id']);sql('UPDATE familyhub_members SET active=0 WHERE scope_id=? AND account_id=?',[$sid,$recipient['user']['account_id']]);
denied(fn()=>$prepared->synchronize($prepared->access($sid,$owner),[$slot],$body['members']),'crypto_invitation_consent_required','an access transition cannot resurrect removed membership through a stale prepared slot');
ck(count($scopes->effectiveMembers($sid))===1,'failed stale-slot resurrection leaves the removed member absent from projected roster');
ck(!method_exists($prepared,'proofs'),'final protocol exposes no global cryptographic consent overlay endpoint');
echo json_encode(['status'=>'pass','checks'=>$checks,'fixture'=>'new in-memory SQLite model lifecycle guards','authorizationSemantics'=>'Send signs recipient roster and sealed grants; acceptance is trusted server/UI lifecycle','limitations'=>'No HTTP, native or complete rotation proof; fixture signatures and projections supplied']).PHP_EOL;
