<?php
/** Isolated SQL helper parity only; not an activated cryptographic component. */
require __DIR__.'/crypto2-integration.php';
use Kanboard\Plugin\FamilyHub\Model\NativeCryptoAccessConsequencesV2;
use Kanboard\Plugin\FamilyHub\Model\NativeCryptoAccessV2;
use Kanboard\Plugin\FamilyHub\Model\NativeCryptoDirectoryV2;
$rootScope=uid();$childScope=uid();$requestId=uid();$account=$fresh['user']['accountId'];
foreach ([$rootScope,$childScope] as $sid) {
    q('INSERT INTO familyhub_scopes(id,kind,name,owner_id,created_at,access_policy_version,access_revision,parent_scope_id,organization_id) VALUES(?,?,?,?,?,1,0,?,?)',[$sid,$sid===$rootScope?'organization':'project','Synthetic consequence',$fresh['user']['id'],time(),$sid===$childScope?$rootScope:null,$sid===$childScope?$rootScope:null]);
    q("INSERT INTO familyhub_members(scope_id,user_id,account_id,role,active) VALUES(?,?,?,'owner',1)",[$sid,$fresh['user']['id'],$account]);
}
function consequenceInvitation2($sid,$u,$state,$bridge=true,$mismatch=false,$expired=false) {
    $id=uid();$token=hash('sha256',random_bytes(32));
    q("INSERT INTO familyhub_invitations(id,scope_id,creator_id,creator_account_id,recipient_username,role,token_hash,created_at,expires_at) VALUES(?,?,?,?,?,'viewer',?,?,?)",[$id,$sid,$u['user']['id'],$u['user']['accountId'],'synthetic-recipient',$token,time(),time()+($expired?-60:3600)]);
    if ($state!==null) {
        q('INSERT INTO familyhub_crypto_invitations_v2 VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)',[$id,$sid,$u['user']['accountId'],$u['device']['id'],'username','synthetic-recipient',null,'viewer',$mismatch?hash('sha256',random_bytes(32)):$token,time(),time()+3600,$state,'{}','en',null]);
    }
    if ($bridge) q('INSERT INTO familyhub_crypto_invitation_routes_v3 VALUES(?,?,?,?,?,?,?,?)',[$token,$id,uid(),$u['user']['accountId'],uid(),$sid,uid(),time()]);
    return $id;
}
$consumed=consequenceInvitation2($childScope,$fresh,'consumed');
$pending=consequenceInvitation2($childScope,$fresh,'pending');
$mismatch=consequenceInvitation2($childScope,$fresh,'pending',true,true);
$expired=consequenceInvitation2($rootScope,$fresh,null,false,false,true);
$helper=new NativeCryptoAccessConsequencesV2($container);$frame=$helper->collect($rootScope,$requestId);
ck($frame['snapshot']['invitationCount']===4,'exact installed consumed bridge is excluded; pending bridge counted canonically once; stale route remains two distinct typed intents');
ck($frame['scoped'][$childScope]['invitationCount']===3&&$frame['scoped'][$rootScope]['invitationCount']===1,'each child manager gets its own exact consequence count');
$leaves=array_keys($frame['leaves']);$sorted=$leaves;sort($sorted,SORT_STRING);
ck($leaves===$sorted&&count(array_unique($leaves))===4,'complete opaque entry digest stream is sorted and unique');
$before=$frame['snapshot']['invitationSetHash'];$new=consequenceInvitation2($childScope,$fresh,null,false);
ck($helper->collect($rootScope,$requestId)['snapshot']['invitationSetHash']!==$before,'new child invitation changes the frozen global consequence root');
q('DELETE FROM familyhub_invitations WHERE id=?',[$new]);
ck($helper->collect($rootScope,$requestId)['snapshot']===$frame['snapshot'],'wall-clock expiry is not used to change the exact outstanding set');
ck($helper->collect($rootScope,uid())['snapshot']['invitationSetHash']!==$before,'different stable prepare nonce cannot reuse a consequence commitment');
// Execute the same private SQL effect used by activation, inside the isolated
// fixture. Cryptographic approval/closure evidence is tested by the full route.
$intent=hash('sha256',random_bytes(32));
foreach ([$rootScope,$childScope] as $sid) q('INSERT INTO familyhub_crypto_access_portions_v2 VALUES(?,?,?,?,?,?,?,?,NULL,NULL)',[$intent,$sid,hash('sha256',$sid),NativeCryptoDirectoryV2::ZERO,0,0,1,'[]']);
$apply=new ReflectionMethod(NativeCryptoAccessV2::class,'apply');$apply->setAccessible(true);
$apply->invoke(new NativeCryptoAccessV2($container),['scope_id'=>$rootScope,'intent_hash'=>$intent,'action'=>json_encode(['kind'=>'accessPolicy','targetVersion'=>3])]);
ck(q('SELECT revoked_at FROM familyhub_invitations WHERE id=?',[$consumed])[0]['revoked_at']===null&&q('SELECT state FROM familyhub_crypto_invitations_v2 WHERE id=?',[$consumed])[0]['state']==='consumed','consumed canonical bridge preserves original captured pending row and canonical consumed outcome');
ck(q('SELECT revoked_at FROM familyhub_invitations WHERE id=?',[$pending])[0]['revoked_at']===null&&q('SELECT state FROM familyhub_crypto_invitations_v2 WHERE id=?',[$pending])[0]['state']==='revoked','pending bridge cancels only its canonical current intent');
ck(q('SELECT revoked_at FROM familyhub_invitations WHERE id=?',[$mismatch])[0]['revoked_at']!==null&&q('SELECT revoked_at FROM familyhub_invitations WHERE id=?',[$expired])[0]['revoked_at']!==null,'mismatched route and expired unbridged invitation retain legitimate legacy cancellation semantics');
ck($helper->collect($rootScope,$requestId)['snapshot']['invitationCount']===0,'SQL final effect enumerates the same complete logical outstanding set');
echo 'Crypto2 invitation consequences: '.$checks.' checks PASS'.PHP_EOL;
