<?php
/** New signed-dispatch/receipt checks in fresh memory SQL. Authentication actor is injected; no HTTP or retained server. */
use Kanboard\Plugin\FamilyHub\Model\NativeCryptoV2Codec as V2;
use Kanboard\Plugin\FamilyHub\Model\NativeCryptoCodec as Codec;
use Kanboard\Plugin\FamilyHub\Model\NativeCryptoV2Service;
use Kanboard\Plugin\FamilyHub\Model\NativeCryptoInvitationV2;
define('FAMILYHUB_ENABLE_CRYPTO_PREVIEW',true);
require __DIR__.'/crypto5-invitation-preauthorization-memory-fixture.php';
$pdo->exec('CREATE TABLE familyhub_native_lock(id INTEGER PRIMARY KEY,counter INTEGER); INSERT INTO familyhub_native_lock VALUES(1,0);');
class DeclineDispatchFixture extends NativeCryptoV2Service {
    public $fixtureActor;
    protected function actor($lock=true){return $this->fixtureActor;}
    public function rate(array $buckets){}
}
$api=new DeclineDispatchFixture($container);$api->fixtureActor=$recipient;
$invitations=new NativeCryptoInvitationV2($container);
[$sid,$body,$head]=scopeFixture(3,$owner);
$scope=$prepared->access($sid,$owner);
$resolved=$prepared->resolve(['scopeId'=>$sid,'recipient'=>$recipient['email'],'role'=>'member'],$owner);
function makeDeclinable($state='pending') {global $sid,$head,$owner,$recipient,$resolved;
    $id=uid();$p=['scopeId'=>$sid,'invitationId'=>$id,'recipient'=>$resolved['recipient'],'role'=>'member','expiresAt'=>time()+3600,'language'=>'en','expectedAccessRevision'=>0,'membershipHeadHash'=>$head,'authorDirectoryHeadHash'=>$owner['head'],'tokenHash'=>hash('sha256',$id),'preauthorization'=>$resolved['preauthorization']];
    $proof=signCommand('crypto2.invitations.create',$p,$owner);
    sql('INSERT INTO familyhub_crypto_invitations_v2 VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,NULL)',[$id,$sid,$owner['user']['account_id'],$owner['device']['id'],'email',$recipient['email'],$recipient['user']['account_id'],'member',$p['tokenHash'],time(),$p['expiresAt'],$state,json_encode($proof),'en']);
    return ['id'=>$id,'creation'=>$proof,'payload'=>['scopeId'=>$sid,'invitationId'=>$id,'tokenHash'=>$p['tokenHash'],'creatorProofHash'=>V2::hash((object)$proof),'authorDirectoryHeadHash'=>$recipient['head']]];
}
$inv=makeDeclinable();
$slot=['accountId'=>$recipient['user']['account_id'],'invitationId'=>$inv['id'],'preauthorizationProofHash'=>$inv['payload']['creatorProofHash'],'invitationScopeId'=>$sid];
$body['members'][]=$resolved['preauthorization']['member'];$body['invitationPreauthorizations']=[$slot];
$prepared->synchronize($scope,[$slot],$body['members']);
sql("INSERT INTO familyhub_members VALUES(?,?,?,'member',0)",[$sid,$recipient['user']['id'],$recipient['user']['account_id']]);
sql("INSERT INTO familyhub_crypto_invitation_mail_v2(invitation_id,token_cipher,language,state,next_attempt) VALUES(?,'synthetic-secret','en','pending',?)",[$inv['id'],time()]);
function preservedState(){global $pdo; $out=[];foreach(['familyhub_members','familyhub_crypto_scope_heads','familyhub_crypto_scope_state','familyhub_crypto_invitation_reservations_v5','familyhub_crypto_grants','familyhub_finance_grants']as $table)$out[$table]=sql('SELECT * FROM '.$table);return json_encode($out);}
$before=preservedState();
$proof=signCommand('crypto2.invitations.decline',$inv['payload'],$recipient);
$tampered=$proof;$tampered['signatureBase64']=base64_encode(str_repeat("\0",64));
denied(fn()=>$api->execute('crypto2.invitations.decline',$tampered),'crypto_signature_invalid','unsigned/tampered refusal cannot alter invitation');
$wrong=signCommand('crypto2.invitations.decline',$inv['payload'],$owner);$api->fixtureActor=$owner;
denied(fn()=>$api->execute('crypto2.invitations.decline',$wrong),'permission_revoked','inviter cannot exercise recipient refusal');$api->fixtureActor=$recipient;
$substitute=signCommand('crypto2.invitations.decline',array_replace($inv['payload'],['creatorProofHash'=>str_repeat('a',64)]),$recipient);
denied(fn()=>$api->execute('crypto2.invitations.decline',$substitute),'invitation_invalid','refusal binds exact original creator authorization');
$result=$api->execute('crypto2.invitations.decline',$proof);
ck($result===['declined'=>true,'invitationId'=>$inv['id']]&&sql('SELECT state FROM familyhub_crypto_invitations_v2 WHERE id=?',[$inv['id']])[0]['state']==='declined','authenticated signed recipient refusal reaches terminal declined state');
ck(preservedState()===$before,'decline preserves signed heads grants exact reservation and inactive membership');
$mail=sql('SELECT state,token_cipher,lease_token FROM familyhub_crypto_invitation_mail_v2 WHERE invitation_id=?',[$inv['id']])[0];
ck($mail===['state'=>'cancelled','token_cipher'=>null,'lease_token'=>null],'decline cancels only invitation mail delivery');
[$command,$bytes,$signature,$digest]=Codec::decode($proof);
$receipt=$api->execute('crypto2.receipt.get',['requestId'=>$command['requestId'],'requestHash'=>$digest]);
ck($receipt['status']===200&&$receipt['response']===$result&&$receipt['authorization']===$proof,'lost acknowledgement is recovered from exact signed receipt without membership access');
ck($api->execute('crypto2.invitations.decline',$proof)===$result&&count(sql('SELECT * FROM familyhub_crypto_receipts'))===1&&preservedState()===$before,'exact signed retry is idempotent and creates no duplicate receipt or access change');
$modified=$command;$modified['payload']['tokenHash']=str_repeat('b',64);$badBytes=Codec::canonical((object)$modified);$modifiedProof=['commandBase64'=>base64_encode($badBytes),'signatureBase64'=>base64_encode(sodium_crypto_sign_detached("JivieE2EE/v2\n".$badBytes,$recipient['secret']))];
denied(fn()=>$api->execute('crypto2.invitations.decline',$modifiedProof),'idempotency_mismatch','same request id cannot replace immutable refusal payload');
ck($invitations->read('crypto2.invitations.pending',[],$recipient)['invitations']===[],'declined invitation no longer appears in recipient pending list');
denied(fn()=>$invitations->usable(sql('SELECT * FROM familyhub_crypto_invitations_v2 WHERE id=?',[$inv['id']])[0]),'invitation_invalid','declined invitation cannot be previewed or accepted');
denied(fn()=>$prepared->synchronize($scope,[],$body['members']),'crypto_invitation_consent_required','retained declined reservation still fences activation without consent');
foreach(['accepted','consumed'] as $state){$accepted=makeDeclinable($state);$before=preservedState();$refusal=signCommand('crypto2.invitations.decline',$accepted['payload'],$recipient);denied(fn()=>$api->execute('crypto2.invitations.decline',$refusal),'invitation_already_accepted',$state.' invitation cannot be refused');ck(sql('SELECT state FROM familyhub_crypto_invitations_v2 WHERE id=?',[$accepted['id']])[0]['state']===$state&&preservedState()===$before,$state.' consent and all membership evidence remain unchanged');}
echo json_encode(['status'=>'pass','checks'=>$checks,'fixture'=>'fresh-memory-SQLite signed real dispatcher with injected authenticated actor','http'=>false,'native'=>false]).PHP_EOL;
