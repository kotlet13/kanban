<?php
require __DIR__.'/crypto2-creation-integration.php';
// Keep original signed requests across natural production rate windows.
define('JIVIE_CRYPTO_TEST_LIFECYCLE_RATE_RETRY',true);
use Kanboard\Plugin\FamilyHub\Model\NativeCryptoLifecycleV2;
use Kanboard\Plugin\FamilyHub\Model\NativeCryptoCodec;

function activateLifecycleHead2($scope,$head,$manifest,$state,$u,$key) {
    $activation=['scopeId'=>$scope['id'],'headHash'=>$head['headHash'],'grantManifestHash'=>$manifest['grantManifestHash'],'authorDirectoryHeadHash'=>$state['headHash']];
    $parent=$scope['parentScopeId']??null;
    if($parent===null)return send2('crypto2.scope.activate',$activation,$u,$key);
    $parentHead=call('crypto2.scope.headGet',['scopeId'=>$parent],$u);
    $id=\Kanboard\Plugin\FamilyHub\Model\NativeCryptoReservedRecordV2::derive($u['serverId'],$parent,'scopeMetadata');
    $metadata=row2($parent,$parentHead,$u,$key,$id,'scopeMetadata');
    $saved=q('SELECT revision,authorization FROM familyhub_crypto_records WHERE scope_id=? AND id=?',[$parent,$metadata['id']]);
    if(!$saved){
        $ack=call('crypto2.records.batch',batch2([$metadata],$u,$key),$u)['records'][0];
        $revision=1;$previous=$ack['recordProofHash'];
    }else{
        $revision=(int)$saved[0]['revision'];
        $previous=\Kanboard\Plugin\FamilyHub\Model\NativeCryptoV2Codec::hash((object)json_decode($saved[0]['authorization'],true)['recordProof']);
    }
    $next=row2($parent,$parentHead,$u,$key,$id,'scopeMetadata',$revision,$previous);
    $bundle=['parentScopeId'=>$parent,'childScopeId'=>$scope['id'],'authorization'=>batch2([$next],$u,$key)];
    $activation['parentTopologyBatchHash']=hash('sha256',"JivieFinanceTopologyCreationBatch/v3\n".NativeCryptoCodec::canonical((object)$bundle));
    $inner=content2('crypto2.scope.activate',$activation,$u,$key);
    return send2('crypto2.scope.activate',['scopeId'=>$scope['id'],'headHash'=>$head['headHash'],'activationProof'=>$inner,'parentTopologyBatch'=>$bundle],$u,$key);
}

function lifecycleIntent2($sid,$head,$state,$actor,$key,$archived) {
    $prior=call('crypto2.scope.lifecycle.current',['scopeId'=>$sid],$actor)['lifecycle'];
    $intent=['scopeId'=>$sid,'parentActionId'=>uid(),'expectedLifecycleRevision'=>$prior['revision'],'previousLifecycleHash'=>$prior['headHash'],'membershipHeadHash'=>$head['headHash'],'expectedAccessRevision'=>$head['payload']['accessRevision'],'authorDirectoryHeadHash'=>$state['headHash'],'archived'=>$archived];
    $prepared=send2('crypto2.scope.lifecycle.prepare',$intent,$actor,$key);
    return [$intent,$prepared];
}
function lifecycleCommit2($intent,$cards,$actor,$key) {
    $descriptors=[];foreach($cards as $card){[$body]=NativeCryptoCodec::decode($card);send2('crypto2.scope.lifecycle.observation.put',['scopeId'=>$intent['scopeId'],'parentActionId'=>$intent['parentActionId'],'observation'=>$card],$actor,$key);$descriptors[]=['scopeId'=>$body['scopeId'],'observationProofHash'=>NativeCryptoLifecycleV2::proofHash($card)];}
    usort($descriptors,fn($a,$b)=>strcmp($a['scopeId'],$b['scopeId']));$hash=hash_init('sha256');foreach($descriptors as $descriptor)hash_update($hash,NativeCryptoCodec::canonical((object)$descriptor)."\n");
    $command=content2('crypto2.scope.archive',['scopeId'=>$intent['scopeId'],'parentActionId'=>$intent['parentActionId'],'intentProofHash'=>NativeCryptoLifecycleV2::proofHash(json_decode(q('SELECT authorization FROM familyhub_crypto_lifecycle_actions_v2 WHERE scope_id=? AND id=?',[$intent['scopeId'],$intent['parentActionId']])[0]['authorization'],true)),'childCount'=>count($cards),'childrenHash'=>hash_final($hash)],$actor,$key);
    return [$command,call('crypto2.scope.archive',$command,$actor)];
}
function lifecycleCard2($intent,$sid,$head,$state,$actor,$key,$delegation=null) {
    $old=call('crypto2.scope.lifecycle.current',['scopeId'=>$sid],$actor)['lifecycle'];
    $card=['version'=>2,'serverId'=>$actor['serverId'],'accountId'=>$actor['user']['accountId'],'deviceId'=>$actor['device']['id'],'authorDirectoryHeadHash'=>$state['headHash'],'parentActionId'=>$intent['parentActionId'],'parentScopeToken'=>(new NativeCryptoLifecycleV2($GLOBALS['container']))->parentToken($sid,$intent['scopeId']),'parentMembershipHeadHash'=>$intent['membershipHeadHash'],'parentExpectedLifecycleRevision'=>$intent['expectedLifecycleRevision'],'parentPreviousLifecycleHash'=>$intent['previousLifecycleHash'],'parentIntentProofHash'=>NativeCryptoLifecycleV2::proofHash(json_decode(q('SELECT authorization FROM familyhub_crypto_lifecycle_actions_v2 WHERE scope_id=? AND id=?',[$intent['scopeId'],$intent['parentActionId']])[0]['authorization'],true)),'parentDeviceSnapshotHash'=>$state['deviceSnapshotHash'],'archived'=>$intent['archived'],'scopeId'=>$sid,'membershipHeadHash'=>$head['headHash'],'expectedLifecycleRevision'=>$old['revision'],'previousLifecycleHash'=>$old['headHash'],'delegationProofHash'=>$delegation];
    return proof2($card,NativeCryptoLifecycleV2::OBSERVATION_DOMAIN,$key);
}
$childBody=candidate2($child,$state);$childBody['accessBasis']=$child['accessBasis'];$childPending=send2('crypto2.scope.headPut',$childBody,$fresh,$freshKeys);$childHead=call('crypto2.scope.headGet',['scopeId'=>$child['id'],'headHash'=>$childPending['headHash']],$fresh);grants2($childHead,[$childHead],$fresh,$freshKeys,$root,$state['snapshot']['recoveryRootEpochId']);$childManifest=call('crypto2.grants.manifest',['scopeId'=>$child['id'],'headHash'=>$childHead['headHash']],$fresh);activateLifecycleHead2($child,$childHead,$childManifest,$state,$fresh,$freshKeys);
$baseline=call('crypto2.scope.lifecycle.current',['scopeId'=>$child['id']],$fresh)['lifecycle'];ck($baseline['revision']===0&&!$baseline['ownArchived']&&$baseline['originAuthorization']!==null,'new false lifecycle baseline is authenticated by exact signed origin');
[$ownIntent]=lifecycleIntent2($child['id'],$childHead,$state,$fresh,$freshKeys,true);[$ownCommand,$ownAck]=lifecycleCommit2($ownIntent,[],$fresh,$freshKeys);ck($ownAck['lifecycle']['ownArchived']&&!$ownAck['lifecycle']['inheritedArchived']&&$ownAck['lifecycle']['revision']===1,'own archive atomically appends proof and SQL flag without rotating DEK');ck(call('crypto2.scope.archive',$ownCommand,$fresh)===$ownAck,'known lifecycle lost ACK returns immutable result before expired action checks');
$originalIntentProof=q('SELECT authorization FROM familyhub_crypto_lifecycle_actions_v2 WHERE scope_id=? AND id=?',[$child['id'],$ownIntent['parentActionId']])[0]['authorization'];[$forgedIntent]=NativeCryptoCodec::decode(json_decode($originalIntentProof,true));$forgedIntent['payload']['archived']=false;$forgedProof=proof2($forgedIntent,"JivieE2EE/v2\n",$freshKeys);q('UPDATE familyhub_crypto_lifecycle_actions_v2 SET authorization=? WHERE scope_id=? AND id=?',[json_encode($forgedProof),$child['id'],$ownIntent['parentActionId']]);deny(fn()=>call('crypto2.scope.lifecycle.current',['scopeId'=>$child['id']],$fresh),'crypto_lifecycle_log_unavailable','substituting another signed prepare under same action ID cannot preserve final/closing proof hash');q('UPDATE familyhub_crypto_lifecycle_actions_v2 SET authorization=? WHERE scope_id=? AND id=?',[$originalIntentProof,$child['id'],$ownIntent['parentActionId']]);
[$parentIntent]=lifecycleIntent2($newId,$head,$state,$fresh,$freshKeys,true);$missing=content2('crypto2.scope.archive',['scopeId'=>$newId,'parentActionId'=>$parentIntent['parentActionId'],'intentProofHash'=>NativeCryptoLifecycleV2::proofHash(json_decode(q('SELECT authorization FROM familyhub_crypto_lifecycle_actions_v2 WHERE scope_id=? AND id=?',[$newId,$parentIntent['parentActionId']])[0]['authorization'],true)),'childCount'=>0,'childrenHash'=>hash('sha256','')],$fresh,$freshKeys);deny(fn()=>call('crypto2.scope.archive',$missing,$fresh),'crypto_lifecycle_children_incomplete','missing child observation causes zero parent or child archive effects');ck(call('crypto2.scope.lifecycle.current',['scopeId'=>$newId],$fresh)['lifecycle']['revision']===0&&call('crypto2.scope.lifecycle.current',['scopeId'=>$child['id']],$fresh)['lifecycle']['revision']===1,'failed aggregate CAS preserves all original lifecycle revisions');
$card=lifecycleCard2($parentIntent,$child['id'],$childHead,$state,$fresh,$freshKeys);[$parentCommand,$parentAck]=lifecycleCommit2($parentIntent,[$card],$fresh,$freshKeys);$childState=call('crypto2.scope.lifecycle.current',['scopeId'=>$child['id']],$fresh)['lifecycle'];ck($parentAck['lifecycle']['ownArchived']&&$childState['ownArchived']&&$childState['inheritedArchived'],'parent archive keeps child own state independent from inherited state');
[$restoreIntent]=lifecycleIntent2($newId,$head,$state,$fresh,$freshKeys,false);$restoreCard=lifecycleCard2($restoreIntent,$child['id'],$childHead,$state,$fresh,$freshKeys);lifecycleCommit2($restoreIntent,[$restoreCard],$fresh,$freshKeys);$after=call('crypto2.scope.lifecycle.current',['scopeId'=>$child['id']],$fresh)['lifecycle'];ck($after['ownArchived']&&!$after['inheritedArchived'],'parent unarchive never unarchives an independently archived child');
$childProof=call('crypto2.scope.lifecycle.list',['scopeId'=>$child['id'],'afterRevision'=>1,'limit'=>1],$fresh);ck(count($childProof['states'])===1&&$childProof['hasMore']&&!isset($childProof['states'][0]['intentAuthorization']),'child receives only its scoped proof and no parent action/sibling roster');
[$cancelIntent]=lifecycleIntent2($newId,$head,$state,$fresh,$freshKeys,true);send2('crypto2.scope.lifecycle.cancel',['scopeId'=>$newId,'parentActionId'=>$cancelIntent['parentActionId']],$fresh,$freshKeys);deny(fn()=>lifecycleCommit2($cancelIntent,[],$fresh,$freshKeys),'crypto_lifecycle_action_expired','cancelled unknown lifecycle action cannot be silently rebased or reused');
[$expiredIntent]=lifecycleIntent2($newId,$head,$state,$fresh,$freshKeys,true);q('UPDATE familyhub_crypto_lifecycle_actions_v2 SET expires_at=? WHERE scope_id=? AND id=?',[time()-1,$newId,$expiredIntent['parentActionId']]);deny(fn()=>call('crypto2.scope.lifecycle.children',['scopeId'=>$newId,'parentActionId'=>$expiredIntent['parentActionId']],$fresh),'crypto_lifecycle_action_expired','crashed expired parent stage leaves current scope writable rather than frozen');
$taskAfter=row2($newId,$head,$fresh,$freshKeys);ck(call('crypto2.records.batch',batch2([$taskAfter],$fresh,$freshKeys),$fresh)['status']==='applied','staging cancellation and expiry never freeze normal business writes');
echo 'Crypto2 lifecycle integration: '.$checks.' checks PASS'.PHP_EOL;
function activateLifecycleScope2($scope,$state,$u,$key,$root) {
    $body=candidate2($scope,$state);$body['accessBasis']=$scope['accessBasis'];
    $p=send2('crypto2.scope.headPut',$body,$u,$key);$h=call('crypto2.scope.headGet',['scopeId'=>$scope['id'],'headHash'=>$p['headHash']],$u);
    grants2($h,[$h],$u,$key,$root,$state['snapshot']['recoveryRootEpochId']);$m=call('crypto2.grants.manifest',['scopeId'=>$scope['id'],'headHash'=>$h['headHash']],$u);activateLifecycleHead2($scope,$h,$m,$state,$u,$key);return $h;
}
$wide=send2('crypto2.scope.create',['id'=>uid(),'kind'=>'organization'],$fresh,$freshKeys)['scope'];$wideHead=activateLifecycleScope2($wide,$state,$fresh,$freshKeys,$root);$wideChildren=[];
for($i=0;$i<51;$i++){$c=send2('crypto2.scope.create',['id'=>uid(),'kind'=>'project','parentScopeId'=>$wide['id'],'expectedParentAccessRevision'=>$wide['accessRevision'],'expectedParentAccessBasis'=>$wide['accessBasis']],$fresh,$freshKeys)['scope'];$wideChildren[$c['id']]=activateLifecycleScope2($c,$state,$fresh,$freshKeys,$root);}
[$wideIntent]=lifecycleIntent2($wide['id'],$wideHead,$state,$fresh,$freshKeys,true);$cursor=null;$listed=0;$pages=0;do{$page=call('crypto2.scope.lifecycle.children',array_filter(['scopeId'=>$wide['id'],'parentActionId'=>$wideIntent['parentActionId'],'limit'=>20,'afterId'=>$cursor],fn($v)=>$v!==null),$fresh);$listed+=count($page['children']);$pages++;$cursor=$page['nextAfterId'];}while($page['hasMore']);ck($listed===51&&$pages===3,'existing project count is preserved through bounded lifecycle child pages');
// A second synthetic client IP exercises the staged archive without weakening production rate limits.
$prefix.='_archive_client';
$wideCards=[];foreach($wideChildren as $sid=>$h)$wideCards[]=lifecycleCard2($wideIntent,$sid,$h,$state,$fresh,$freshKeys);lifecycleCommit2($wideIntent,$wideCards,$fresh,$freshKeys);ck((int)q('SELECT COUNT(*) AS n FROM familyhub_crypto_lifecycle_log_v2 WHERE kind=? AND scope_id IN (SELECT id FROM familyhub_scopes WHERE parent_scope_id=?)',['inherited',$wide['id']])[0]['n']===51,'final bounded stage atomically archives all51 children with no command-size project limit');
echo 'Crypto2 lifecycle paged integration: '.$checks.' checks PASS'.PHP_EOL;
