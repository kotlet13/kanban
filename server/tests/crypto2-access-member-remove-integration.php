<?php
require __DIR__.'/crypto2-access-integration.php';

use Kanboard\Plugin\FamilyHub\Model\NativeCryptoCodec;
use Kanboard\Plugin\FamilyHub\Model\NativeCryptoV2Codec;

function approveRemovalPortion2($sid, $intent, $actor, $key, $state, $actors)
{
    $source = call('crypto2.scope.headGet', ['scopeId'=>$sid], $actor);
    $pending = array_values(array_filter(call('crypto2.access.pending',['scopeId'=>$sid],$actor)['intents'],fn($i)=>$i['intentHash']===$intent['intentHash']))[0];
    $scope = array_values(array_filter(call('crypto2.scopes.catalog',[],$actor)['scopes'],fn($s)=>$s['id']===$sid))[0];
    $body = candidate2($scope,$state,$source['payload']['epoch']+1,$source['headHash'],['content'=>hash('sha256',''),'finance'=>hash('sha256','')]);
    $body['accessBasis']=$pending['accessBasis'];
    $body['accessRevision']=$pending['future']['accessRevision'];
    $body['members']=accessMembers2($pending['future']['members'],$actors);
    $consent=['version'=>2,'operation'=>'crypto2.access.scopeConsent','serverId'=>$actor['serverId'],'scopeId'=>$sid,'intentHash'=>$intent['intentHash'],'affectedCount'=>$intent['affectedCount'],'affectedHash'=>$intent['affectedHash'],'previousHeadHash'=>$source['headHash'],'expectedAccessRevision'=>$pending['expectedAccessRevision'],'accessBasis'=>$pending['accessBasis'],'resultingAccessRevision'=>$body['accessRevision'],'resultingDescriptor'=>$pending['future']['descriptor'],'resultingFinancePolicy'=>$pending['future']['financePolicy'],'membersHash'=>NativeCryptoV2Codec::hash($body['members']),'accountId'=>$actor['user']['accountId'],'deviceId'=>$actor['device']['id'],'authorDirectoryHeadHash'=>$state['headHash']];
    $body['accessIntentProof']=inner2($consent,"JivieE2EE/accessScopeConsent/v2\n",$key);
    foreach (['revision','policyHash'] as $field) {
        $changed = $consent;
        $changed['resultingFinancePolicy'][$field] = $field === 'revision'
            ? $consent['resultingFinancePolicy']['revision'] + 1 : str_repeat('f',64);
        $invalid = $body;
        $invalid['accessIntentProof'] = inner2($changed,"JivieE2EE/accessScopeConsent/v2\n",$key);
        deny(fn()=>send2('crypto2.scope.headPut',$invalid,$actor,$key),'crypto_access_intent_invalid',
            'typed member removal rejects substituted resulting finance policy '.$field);
    }
    $put=send2('crypto2.scope.headPut',$body,$actor,$key);
    $next=call('crypto2.scope.headGet',['scopeId'=>$sid,'headHash'=>$put['headHash']],$actor);
    foreach(['content','finance'] as $domain) close2($sid,$next['headHash'],$source,$domain,$state,0,$actor,$key);
    $history=[];
    foreach(q("SELECT head_hash FROM familyhub_crypto_scope_heads WHERE scope_id=? AND state IN ('active','historical') ORDER BY epoch",[$sid]) as $old) {
        $history[]=call('crypto2.scope.headGet',['scopeId'=>$sid,'headHash'=>$old['head_hash']],$actor);
    }
    $history[]=$next;
    foreach($body['members'] as $m) { [$u,$k,$r,$st]=$actors[$m['accountId']];accessGrants2($next,$history,$u,$k,$r,$st,$actor,$key); }
    $manifest=call('crypto2.grants.manifest',['scopeId'=>$sid,'headHash'=>$next['headHash']],$actor);
    $activation=content2('crypto2.scope.activate',['scopeId'=>$sid,'headHash'=>$next['headHash'],'grantManifestHash'=>$manifest['grantManifestHash'],'authorDirectoryHeadHash'=>$state['headHash'],'accessIntentHash'=>$intent['intentHash'],'affectedCount'=>$intent['affectedCount'],'affectedHash'=>$intent['affectedHash']],$actor,$key);
    send2('crypto2.access.approve',['intentHash'=>$intent['intentHash'],'scopeId'=>$sid,'activationProof'=>$activation],$actor,$key);
    return $next;
}

// A policy2 leader cannot be removed from just a child: its authority is derived
// from the parent. Routing back to that parent is explicit, not a fabricated deny.
$childNow=call('crypto2.scope.headGet',['scopeId'=>$project['id']],$bob);
$childCatalog=array_values(array_filter(call('crypto2.scopes.catalog',[],$bob)['scopes'],fn($s)=>$s['id']===$project['id']))[0];
deny(fn()=>send2('crypto2.access.prepare',['scopeId'=>$project['id'],'membershipHeadHash'=>$childNow['headHash'],'expectedAccessRevision'=>$childCatalog['accessRevision'],'authorDirectoryHeadHash'=>$bobState['headHash'],'action'=>['kind'=>'memberRemove','accountId'=>$ordinary['user']['accountId']]],$bob,$bobKey),'crypto_membership_parent_action_required','pure inherited leader removal must route to parent authority');
$parentNow=call('crypto2.scope.headGet',['scopeId'=>$organization['id']],$bob);
$parentCatalog=array_values(array_filter(call('crypto2.scopes.catalog',[],$bob)['scopes'],fn($s)=>$s['id']===$organization['id']))[0];
$remove=send2('crypto2.access.prepare',['scopeId'=>$organization['id'],'membershipHeadHash'=>$parentNow['headHash'],'expectedAccessRevision'=>$parentCatalog['accessRevision'],'authorDirectoryHeadHash'=>$bobState['headHash'],'action'=>['kind'=>'memberRemove','accountId'=>$ordinary['user']['accountId']]],$bob,$bobKey);
ck($remove['affectedCount']===2,'parent member removal freezes parent plus every related child');
$parentNext=approveRemovalPortion2($organization['id'],$remove,$bob,$bobKey,$bobState,$actors);
$commitPayload=['intentHash'=>$remove['intentHash'],'affectedCount'=>$remove['affectedCount'],'affectedHash'=>$remove['affectedHash']];
deny(fn()=>send2('crypto2.access.activate',$commitPayload,$bob,$bobKey),'crypto_access_approval_required','one missing child removal approval leaves all SQL membership and heads unchanged');
ck(q('SELECT active FROM familyhub_members WHERE scope_id=? AND account_id=?',[$organization['id'],$ordinary['user']['accountId']])[0]['active']==1,'partial parent removal does not deactivate the original member');
$childNext=approveRemovalPortion2($project['id'],$remove,$bob,$bobKey,$bobState,$actors);
$commitProof=content2('crypto2.access.activate',$commitPayload,$bob,$bobKey);
$removed=call('crypto2.access.activate',$commitProof,$bob);
ck($removed['state']==='applied' && call('crypto2.access.activate',$commitProof,$bob)===$removed,'complete parent removal applies exactly once with immutable lost ACK');
ck(q('SELECT active FROM familyhub_members WHERE scope_id=? AND account_id=?',[$organization['id'],$ordinary['user']['accountId']])[0]['active']==0,'parent direct membership is deactivated only with both fresh heads');
ck(q('SELECT account_id FROM familyhub_organization_leaders WHERE scope_id=? AND account_id=?',[$organization['id'],$ordinary['user']['accountId']])===[],'removed leader no longer retains derived child authority');
ck(count(q('SELECT scope_id FROM familyhub_scope_revocations WHERE account_id=? AND scope_id IN (?,?)',[$ordinary['user']['accountId'],$organization['id'],$project['id']]))===2,'explicit revocation listing evidence covers both lost spaces');
deny(fn()=>call('crypto2.scope.headGet',['scopeId'=>$project['id']],$ordinary),'permission_revoked','removed inherited child reader cannot fetch future head or keys');
ck(call('crypto2.scope.headGet',['scopeId'=>$project['id']],$bob)['headHash']===$childNext['headHash'],'remaining child owner sees exact separately approved fresh head');

// External child-only membership can be removed without changing parent rights.
$childCatalog=array_values(array_filter(call('crypto2.scopes.catalog',[],$bob)['scopes'],fn($s)=>$s['id']===$project['id']))[0];
$direct=send2('crypto2.access.prepare',['scopeId'=>$project['id'],'membershipHeadHash'=>$childNext['headHash'],'expectedAccessRevision'=>$childCatalog['accessRevision'],'authorDirectoryHeadHash'=>$bobState['headHash'],'action'=>['kind'=>'memberRemove','accountId'=>$external['user']['accountId']]],$bob,$bobKey);
ck($direct['affectedCount']===1,'project-only direct removal has exactly one affected scope');
approveRemovalPortion2($project['id'],$direct,$bob,$bobKey,$bobState,$actors);
send2('crypto2.access.activate',['intentHash'=>$direct['intentHash'],'affectedCount'=>1,'affectedHash'=>$direct['affectedHash']],$bob,$bobKey);
ck(call('crypto2.scope.headGet',['scopeId'=>$organization['id']],$bob)['headHash']===$parentNext['headHash'],'project-only removal leaves authenticated parent head unchanged');
deny(fn()=>call('crypto2.scope.headGet',['scopeId'=>$project['id']],$external),'permission_revoked','removed direct project-only reader cannot regain inherited parent authority');
echo 'Crypto2 typed member removal integration: '.$checks.' checks PASS'.PHP_EOL;
