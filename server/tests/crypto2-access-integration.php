<?php
require __DIR__.'/crypto2-membership-integration.php';
use Kanboard\Plugin\FamilyHub\Model\NativeCryptoCodec;
use Kanboard\Plugin\FamilyHub\Model\NativeCryptoV2Codec;

// Synthetic committed legacy state isolates the topology protocol. It is NOT
// evidence that canonical P6 source conversion/cold-restore gates are complete.
[$ordinaryRoot,$ordinaryKey,$ordinaryState]=initializeMember2($ordinary);
[$outsideRoot,$outsideKey,$outsideState]=initializeMember2($outsider);
[$externalRoot,$externalKey,$externalState]=initializeMember2($external);
$actors=[$bob['user']['accountId']=>[$bob,$bobKey,$bobRoot,$bobState],$ordinary['user']['accountId']=>[$ordinary,$ordinaryKey,$ordinaryRoot,$ordinaryState],$outsider['user']['accountId']=>[$outsider,$outsideKey,$outsideRoot,$outsideState],$external['user']['accountId']=>[$external,$externalKey,$externalRoot,$externalState]];
function accessMembers2($rows,$actors) {
    $members=[];
    foreach($rows as $row) {
        $m=member2($actors[$row['accountId']][3],$row['role']);
        $m['financeRole']=$row['financeRole'];$m['manageKeys']=$row['manageKeys'];$members[]=$m;
    }
    usort($members,fn($a,$b)=>strcmp($a['accountId'],$b['accountId']));return $members;
}
function accessGrants2($candidate,$sources,$target,$targetKey,$targetRoot,$targetState,$author,$authorKey) {
    $m=array_values(array_filter($candidate['payload']['members'],fn($m)=>$m['accountId']===$target['user']['accountId']))[0];
    foreach(['content','finance'] as $domain) {
        if ($domain==='finance'&&$m['financeRole']==='none') continue;
        foreach($sources as $source) {
            if ($source['payload']['keyIds'][$domain]===null) continue;
            $recipients=[['recipientKind'=>'device','recipientId'=>$target['device']['id'],'publicKeyBase64'=>$targetKey['boxPublic'],'sealedEnvelopeBase64'=>base64_encode(random_bytes(96))],['recipientKind'=>'recovery','recipientId'=>$targetState['snapshot']['recoveryRootEpochId'],'publicKeyBase64'=>$targetRoot['boxPublic'],'sealedEnvelopeBase64'=>base64_encode(random_bytes(96))]];
            send2('crypto2.grants.put',['scopeId'=>$candidate['scopeId'],'headHash'=>$candidate['headHash'],'keySourceHeadHash'=>$source['headHash'],'keyId'=>$source['payload']['keyIds'][$domain],'accountId'=>$target['user']['accountId'],'domain'=>$domain,'epoch'=>$source['payload']['epoch'],'expectedGeneration'=>0,'recipients'=>$recipients],$author,$authorKey);
        }
    }
}
function accessInitial2($sid,$actor,$key,$state,$actors) {
    $scope=array_values(array_filter(call('crypto2.scopes.catalog',[],$actor)['scopes'],fn($s)=>$s['id']===$sid))[0];
    send2('crypto2.scope.prepare',['scopeId'=>$sid,'expectedAccessRevision'=>$scope['accessRevision']],$actor,$key);
    $body=candidate2($scope,$state);$body['accessBasis']=$scope['accessBasis'];$body['members']=accessMembers2($scope['members'],$actors);
    $pending=send2('crypto2.scope.headPut',$body,$actor,$key);$head=call('crypto2.scope.headGet',['scopeId'=>$sid,'headHash'=>$pending['headHash']],$actor);
    foreach($body['members'] as $member){[$u,$k,$r,$st]=$actors[$member['accountId']];accessGrants2($head,[$head],$u,$k,$r,$st,$actor,$key);}
    $manifest=call('crypto2.grants.manifest',['scopeId'=>$sid,'headHash'=>$head['headHash']],$actor);
    send2('crypto2.scope.activate',['scopeId'=>$sid,'headHash'=>$head['headHash'],'grantManifestHash'=>$manifest['grantManifestHash'],'authorDirectoryHeadHash'=>$state['headHash']],$actor,$key);
    return $head;
}
$parentHead=accessInitial2($organization['id'],$bob,$bobKey,$bobState,$actors);
$childHead=accessInitial2($project['id'],$bob,$bobKey,$bobState,$actors);
$syntheticMigration=uid();q('INSERT INTO familyhub_crypto_migrations_v2 VALUES(?,?,?,?,?,?,?,?,?)',[$syntheticMigration,uid(),hash('sha256','synthetic access component'),json_encode([$organization['id'],$project['id']]),hash('sha256','synthetic participants'),'committed',hash('sha256','synthetic challenge'),time(),time()]);
q("UPDATE familyhub_crypto_scopes SET state='active',migration_id=? WHERE scope_id IN (?,?)",[$syntheticMigration,$organization['id'],$project['id']]);
$parentScope=array_values(array_filter(call('crypto2.scopes.catalog',[],$bob)['scopes'],fn($s)=>$s['id']===$organization['id']))[0];
$prepare=content2('crypto2.access.prepare',['scopeId'=>$organization['id'],'membershipHeadHash'=>$parentHead['headHash'],'expectedAccessRevision'=>$parentScope['accessRevision'],'authorDirectoryHeadHash'=>$bobState['headHash'],'action'=>['kind'=>'leader','accountId'=>$ordinary['user']['accountId'],'enabled'=>true]],$bob,$bobKey);
$intent=call('crypto2.access.prepare',$prepare,$bob);
ck($intent['affectedCount']===2&&call('crypto2.access.prepare',$prepare,$bob)===$intent,'leader prepare freezes complete parent/child set and replays exact original TTL');
ck(!in_array($project['id'],array_column(call('crypto2.scopes.catalog',[],$ordinary)['scopes'],'id'),true),'pending leader intent does not grant child data or SQL membership');
$first=call('crypto2.access.portions',['intentHash'=>$intent['intentHash'],'limit'=>1],$bob);
ck(count($first['portions'])===1&&$first['hasMore']&&!str_contains(json_encode($first),$project['id']),'parent approval status is bounded opaque child commitments only');
$activation=content2('crypto2.access.activate',['intentHash'=>$intent['intentHash'],'affectedCount'=>2,'affectedHash'=>$intent['affectedHash']],$bob,$bobKey);
deny(fn()=>call('crypto2.access.activate',$activation,$bob),'crypto_access_approval_required','missing one approval gives zero topology/head writes');
ck(q('SELECT account_id FROM familyhub_organization_leaders WHERE scope_id=? AND account_id=?',[$organization['id'],$ordinary['user']['accountId']])===[],'failed component activation preserves old leader authority');
$sourceHeads=[$organization['id']=>$parentHead,$project['id']=>$childHead];$newHeads=[];
foreach($sourceHeads as $sid=>$source){
    $pending=call('crypto2.access.pending',['scopeId'=>$sid],$bob)['intents'][0];
    $scope=array_values(array_filter(call('crypto2.scopes.catalog',[],$bob)['scopes'],fn($s)=>$s['id']===$sid))[0];
    $body=candidate2($scope,$bobState,2,$source['headHash'],['content'=>hash('sha256',''),'finance'=>hash('sha256','')]);$body['accessBasis']=$pending['accessBasis'];$body['accessRevision']=$pending['future']['accessRevision'];$body['members']=accessMembers2($pending['future']['members'],$actors);
    $consent=['version'=>2,'operation'=>'crypto2.access.scopeConsent','serverId'=>$bob['serverId'],'scopeId'=>$sid,'intentHash'=>$intent['intentHash'],'affectedCount'=>2,'affectedHash'=>$intent['affectedHash'],'previousHeadHash'=>$source['headHash'],'expectedAccessRevision'=>$pending['expectedAccessRevision'],'accessBasis'=>$pending['accessBasis'],'resultingAccessRevision'=>$body['accessRevision'],'resultingDescriptor'=>$pending['future']['descriptor'],'resultingFinancePolicy'=>$pending['future']['financePolicy'],'membersHash'=>NativeCryptoV2Codec::hash($body['members']),'accountId'=>$bob['user']['accountId'],'deviceId'=>$bob['device']['id'],'authorDirectoryHeadHash'=>$bobState['headHash']];
    $body['accessIntentProof']=inner2($consent,"JivieE2EE/accessScopeConsent/v2\n",$bobKey);
    $put=send2('crypto2.scope.headPut',$body,$bob,$bobKey);$next=call('crypto2.scope.headGet',['scopeId'=>$sid,'headHash'=>$put['headHash']],$bob);$newHeads[$sid]=$next;
    foreach(['content','finance'] as $domain){close2($sid,$next['headHash'],$source,$domain,$bobState,0,$bob,$bobKey);}
    foreach($body['members'] as $member){[$u,$k,$r,$st]=$actors[$member['accountId']];accessGrants2($next,[$source,$next],$u,$k,$r,$st,$bob,$bobKey);}
    $manifest=call('crypto2.grants.manifest',['scopeId'=>$sid,'headHash'=>$next['headHash']],$bob);
    $scopeActivation=content2('crypto2.scope.activate',['scopeId'=>$sid,'headHash'=>$next['headHash'],'grantManifestHash'=>$manifest['grantManifestHash'],'authorDirectoryHeadHash'=>$bobState['headHash'],'accessIntentHash'=>$intent['intentHash'],'affectedCount'=>2,'affectedHash'=>$intent['affectedHash']],$bob,$bobKey);
    deny(fn()=>call('crypto2.scope.activate',$scopeActivation,$bob),'crypto_access_component_required','prepared topology head cannot activate independently');
    deny(fn()=>send2('crypto2.access.approve',['intentHash'=>$intent['intentHash'],'scopeId'=>$sid,'activationProof'=>$scopeActivation],$bob,$bobKey),'crypto_access_activation_nonce_used','known rejected activation request cannot be reinterpreted as applied through component');
    [$activationBody]=NativeCryptoCodec::decode($scopeActivation);$scopeActivation=content2('crypto2.scope.activate',$activationBody['payload'],$bob,$bobKey);
    send2('crypto2.access.approve',['intentHash'=>$intent['intentHash'],'scopeId'=>$sid,'activationProof'=>$scopeActivation],$bob,$bobKey);
}
$commit=content2('crypto2.access.activate',['intentHash'=>$intent['intentHash'],'affectedCount'=>2,'affectedHash'=>$intent['affectedHash']],$bob,$bobKey);
$applied=call('crypto2.access.activate',$commit,$bob);
ck($applied['state']==='applied'&&call('crypto2.access.activate',$commit,$bob)===$applied,'complete leader component switches SQL plus all signed heads atomically and exact ACK replays');
ck(call('crypto2.scope.headGet',['scopeId'=>$project['id']],$ordinary)['headHash']===$newHeads[$project['id']]['headHash'],'new inherited leader gets exact approved child head only after component activation');
ck(call('crypto2.scope.headGet',['scopeId'=>$organization['id']],$bob)['headHash']===$newHeads[$organization['id']]['headHash'],'parent authority advances to the same frozen component result');
ck(call('crypto2.scope.activate',$scopeActivation,$bob)['state']==='keysReady','successful nested activation nonce has exact durable success receipt for later lookup');
$grants=call('crypto2.grants.list',['scopeId'=>$project['id'],'headHash'=>$newHeads[$project['id']]['headHash'],'domain'=>'finance','epoch'=>2],$ordinary);
ck(count($grants['grants'])>0,'applied access intent never replays old SQL action during current historical key reads');

echo 'Crypto2 access integration: '.$checks.' checks PASS'.PHP_EOL;
