<?php
require __DIR__.'/crypto2-scope-integration.php';
use Kanboard\Plugin\FamilyHub\Model\NativeCryptoCodec;
function initializeMember2($u) {
    $root=keys();$device=keys();$e=uid();$bundle=base64_encode(random_bytes(96));
    $s=['version'=>2,'serverId'=>$u['serverId'],'accountId'=>$u['user']['accountId'],'rootSigningKeyBase64'=>$root['signPublic'],'rootEncryptionKeyBase64'=>$root['boxPublic'],'recoveryRootCiphertextHash'=>hash('sha256',base64_decode($bundle)),'recoveryRootEpochId'=>$e,'identityEpochId'=>$e,'devices'=>[dev2($u,$device,$e)],'keyringEntries'=>[]];
    call('crypto2.account.initialize',request2('crypto2.account.initialize',['rootSigningKeyBase64'=>$root['signPublic'],'rootEncryptionKeyBase64'=>$root['boxPublic'],'deviceSigningKeyBase64'=>$device['signPublic'],'deviceEncryptionKeyBase64'=>$device['boxPublic'],'keyringCiphertextBase64'=>$bundle],$u,$root,$s,null,'root'),$u);
    return [$root,$device,call('crypto2.account.status',[],$u)];
}
function member2($state,$role='member') {
    $s=$state['snapshot'];return ['accountId'=>$s['accountId'],'rootSigningKeyBase64'=>$s['rootSigningKeyBase64'],'rootEncryptionKeyBase64'=>$s['rootEncryptionKeyBase64'],'recoveryRootEpochId'=>$s['recoveryRootEpochId'],'identityEpochId'=>$s['identityEpochId'],'directoryHeadHash'=>$state['headHash'],'deviceSnapshotHash'=>$state['deviceSnapshotHash'],'role'=>$role,'financeRole'=>$role==='viewer'?'read':'write','manageKeys'=>$role!=='viewer'];
}
function memberGrants2($candidate,$sources,$target,$targetKey,$targetRoot,$targetState,$author,$authorKey) {
    foreach(['content','finance'] as $domain)foreach($sources as $source){
        $recipients=[['recipientKind'=>'device','recipientId'=>$target['device']['id'],'publicKeyBase64'=>$targetKey['boxPublic'],'sealedEnvelopeBase64'=>base64_encode(random_bytes(96))],['recipientKind'=>'recovery','recipientId'=>$targetState['snapshot']['recoveryRootEpochId'],'publicKeyBase64'=>$targetRoot['boxPublic'],'sealedEnvelopeBase64'=>base64_encode(random_bytes(96))]];
        send2('crypto2.grants.put',['scopeId'=>$candidate['scopeId'],'headHash'=>$candidate['headHash'],'keySourceHeadHash'=>$source['headHash'],'keyId'=>$source['payload']['keyIds'][$domain],'accountId'=>$target['user']['accountId'],'domain'=>$domain,'epoch'=>$source['payload']['epoch'],'expectedGeneration'=>0,'recipients'=>$recipients],$author,$authorKey);
    }
}
$bob=user('scope_successor');[$bobRoot,$bobKey,$bobState]=initializeMember2($bob);
$shared=scope($fresh);q('INSERT INTO familyhub_members(scope_id,user_id,account_id,role,active) VALUES(?,?,?,?,1)',[$shared['id'],$bob['user']['id'],$bob['user']['accountId'],'member']);q('UPDATE familyhub_scopes SET access_revision=1 WHERE id=?',[$shared['id']]);$shared['accessRevision']=1;
send2('crypto2.scope.prepare',['scopeId'=>$shared['id'],'expectedAccessRevision'=>1],$fresh,$freshKeys);
$sharedBody=candidate2($shared,$state);$sharedBody['members'][]=member2($bobState);usort($sharedBody['members'],fn($a,$b)=>strcmp($a['accountId'],$b['accountId']));
$sharedPending=send2('crypto2.scope.headPut',$sharedBody,$fresh,$freshKeys);$sharedHead=call('crypto2.scope.headGet',['scopeId'=>$shared['id'],'headHash'=>$sharedPending['headHash']],$fresh);
memberGrants2($sharedHead,[$sharedHead],$fresh,$freshKeys,$root,$state,$fresh,$freshKeys);memberGrants2($sharedHead,[$sharedHead],$bob,$bobKey,$bobRoot,$bobState,$fresh,$freshKeys);
$manifest=call('crypto2.grants.manifest',['scopeId'=>$shared['id'],'headHash'=>$sharedHead['headHash']],$fresh);
send2('crypto2.scope.activate',['scopeId'=>$shared['id'],'headHash'=>$sharedHead['headHash'],'grantManifestHash'=>$manifest['grantManifestHash'],'authorDirectoryHeadHash'=>$state['headHash']],$fresh,$freshKeys);
ck(call('crypto2.scope.headGet',['scopeId'=>$shared['id']],$bob)['headHash']===$sharedHead['headHash'],'accepted existing SQL member receives complete first cryptographic head');
// A concurrent legacy change reaching the desired result must not erase the signed base CAS.
$demotion=candidate2($shared,$state,2,$sharedHead['headHash'],['content'=>hash('sha256',''),'finance'=>hash('sha256','')]);$demotion['accessRevision']=2;$demotion['members'][]=member2($bobState,'viewer');usort($demotion['members'],fn($a,$b)=>strcmp($a['accountId'],$b['accountId']));
$demotionPending=send2('crypto2.scope.headPut',$demotion,$fresh,$freshKeys);
q('UPDATE familyhub_members SET role=? WHERE scope_id=? AND account_id=?',['viewer',$shared['id'],$bob['user']['accountId']]);q('UPDATE familyhub_scopes SET access_revision=2 WHERE id=?',[$shared['id']]);
deny(fn()=>send2('crypto2.scope.activate',['scopeId'=>$shared['id'],'headHash'=>$demotionPending['headHash'],'grantManifestHash'=>hash('sha256',''),'authorDirectoryHeadHash'=>$state['headHash']],$fresh,$freshKeys),'crypto_access_changed','same resulting roster/revision cannot bypass stale signed expected access base');
// Restore only this synthetic fixture to isolate the independent ownership case.
q('UPDATE familyhub_members SET role=? WHERE scope_id=? AND account_id=?',['member',$shared['id'],$bob['user']['accountId']]);q('UPDATE familyhub_scopes SET access_revision=1 WHERE id=?',[$shared['id']]);
// Departing-manager independent-key transfer lives in crypto2-key-contribution-integration.php.
// Its new future keys may never be generated by this old owner fixture.
// Policy2 leaders are derived readers even without a direct project membership.
$organization=scope($bob,'organization',2);$project=call('scopes.create',['id'=>uid(),'kind'=>'project','name'=>'Synthetic child','organizationId'=>$organization['id'],'accessPolicyVersion'=>2,'requestId'=>uid()],$bob)['scope'];
q('INSERT INTO familyhub_members(scope_id,user_id,account_id,role,active) VALUES(?,?,?,?,1)',[$organization['id'],$outsider['user']['id'],$outsider['user']['accountId'],'member']);q('INSERT INTO familyhub_organization_leaders(scope_id,account_id) VALUES(?,?)',[$organization['id'],$outsider['user']['accountId']]);
$external=user('project_external');q('INSERT INTO familyhub_members(scope_id,user_id,account_id,role,active) VALUES(?,?,?,?,1)',[$project['id'],$external['user']['id'],$external['user']['accountId'],'viewer']);
$leaderCatalog=call('crypto2.scopes.catalog',[],$outsider);$leaderProject=array_values(array_filter($leaderCatalog['scopes'],fn($r)=>$r['id']===$project['id']))[0];$leaderMember=array_values(array_filter($leaderProject['members'],fn($r)=>$r['accountId']===$outsider['user']['accountId']))[0];
ck($leaderProject['role']==='viewer'&&$leaderMember['role']==='viewer'&&!$leaderMember['manageKeys'],'policy2 inherited leader is preserved as project reader without key management');
$externalCatalog=call('crypto2.scopes.catalog',[],$external);$externalProject=array_values(array_filter($externalCatalog['scopes'],fn($r)=>$r['id']===$project['id']))[0];
ck($externalProject['parentScopeId']===null&&count($externalProject['accessBasis'])===2&&!str_contains(json_encode($externalProject['accessBasis']),$organization['id']),'project-only member gets opaque parent revision basis without inaccessible parent ID');
$ordinary=user('ordinary_parent');q('INSERT INTO familyhub_members(scope_id,user_id,account_id,role,active) VALUES(?,?,?,?,1)',[$organization['id'],$ordinary['user']['id'],$ordinary['user']['accountId'],'member']);
ck(!in_array($project['id'],array_column(call('crypto2.scopes.catalog',[],$ordinary)['scopes'],'id'),true),'ordinary policy2 parent member does not inherit project access');
echo 'Crypto2 membership integration: '.$checks.' checks PASS'.PHP_EOL;
