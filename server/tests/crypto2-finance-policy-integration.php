<?php
require __DIR__.'/crypto2-membership-integration.php';
use Kanboard\Plugin\FamilyHub\Model\NativeCryptoFinancePolicyV2;
use Kanboard\Plugin\FamilyHub\Model\NativeCryptoCodec;

function policyProposal2($scopeId, $source, $state, $actor, $key, $action) {
    global $pdo,$container;
    $policies = new NativeCryptoFinancePolicyV2($container);
    $before=$policies->policy($scopeId);
    $pdo->beginTransaction();
    if ($action['kind']==='enable') {
        q('UPDATE familyhub_finance_policy SET enabled=?,revision=revision+1 WHERE scope_id=?',[(int)$action['enabled'],$scopeId]);
        if ($action['enabled']) {
            q('DELETE FROM familyhub_finance_grants WHERE scope_id=? AND account_id=?',[$scopeId,$actor['user']['accountId']]);
            q('INSERT INTO familyhub_finance_grants VALUES(?,?,?)',[$scopeId,$actor['user']['accountId'],'write']);
        }
    } else {
        q('DELETE FROM familyhub_finance_grants WHERE scope_id=? AND account_id=?',[$scopeId,$action['accountId']]);
        q('INSERT INTO familyhub_finance_grants VALUES(?,?,?)',[$scopeId,$action['accountId'],$action['grant']]);
        q('UPDATE familyhub_finance_policy SET revision=revision+1 WHERE scope_id=?',[$scopeId]);
    }
    $after=$policies->policy($scopeId);
    $pdo->rollBack();
    $payload=['scopeId'=>$scopeId,'membershipHeadHash'=>$source['headHash'],'expectedAccessRevision'=>$source['payload']['accessRevision'],'authorDirectoryHeadHash'=>$state['headHash'],'expectedFinancePolicyRevision'=>$before['revision'],'previousPolicyHash'=>$before['policyHash'],'resultingFinancePolicyRevision'=>$after['revision'],'resultingPolicyHash'=>$after['policyHash'],'action'=>$action];
    $proof=content2('crypto2.scope.financePolicy.propose',$payload,$actor,$key);
    $reply=call('crypto2.scope.financePolicy.propose',$proof,$actor);
    return [$proof,$reply,$before,$after];
}
function policyGrants2($candidate,$sources,$actor,$key,$root,$state) {
    foreach(['content','finance'] as $domain) foreach($sources as $source) {
        if ($source['payload']['keyIds'][$domain]===null) continue;
        $recipients=[['recipientKind'=>'device','recipientId'=>$actor['device']['id'],'publicKeyBase64'=>$key['boxPublic'],'sealedEnvelopeBase64'=>base64_encode(random_bytes(96))],['recipientKind'=>'recovery','recipientId'=>$state['snapshot']['recoveryRootEpochId'],'publicKeyBase64'=>$root['boxPublic'],'sealedEnvelopeBase64'=>base64_encode(random_bytes(96))]];
        send2('crypto2.grants.put',['scopeId'=>$candidate['scopeId'],'headHash'=>$candidate['headHash'],'keySourceHeadHash'=>$source['headHash'],'keyId'=>$source['payload']['keyIds'][$domain],'accountId'=>$actor['user']['accountId'],'domain'=>$domain,'epoch'=>$source['payload']['epoch'],'expectedGeneration'=>0,'recipients'=>$recipients],$actor,$key);
    }
}
// Actual signed empty origins, with synthetic pre-genesis policy1 setup.
// This isolates historical policy parity without claiming a P6 source commit.
$policyScope=send2('crypto2.scope.create',['id'=>uid(),'kind'=>'organization'],$fresh,$freshKeys)['scope'];
$policyChild=['id'=>uid()];
// Synthetic legacy child topology is seeded only to compare the unchanged ACL
// resolver; no child origin, cutover or business-write permission is asserted.
q('INSERT INTO familyhub_scopes(id,kind,name,owner_id,sequence,created_at,parent_scope_id,organization_id,access_policy_version,access_revision) VALUES(?,?,?,?,0,?,?,?,1,0)',[$policyChild['id'],'project','Synthetic dependency child',$fresh['user']['id'],time(),$policyScope['id'],$policyScope['id']]);
q('INSERT INTO familyhub_members(scope_id,user_id,account_id,role,active) VALUES(?,?,?,?,1)',[$policyChild['id'],$fresh['user']['id'],$fresh['user']['accountId'],'owner']);
q('INSERT INTO familyhub_finance_policy(scope_id,enabled,revision,sequence) VALUES(?,1,0,0)',[$policyChild['id']]);
q('INSERT INTO familyhub_finance_grants VALUES(?,?,?)',[$policyChild['id'],$fresh['user']['accountId'],'write']);
q('UPDATE familyhub_scopes SET access_policy_version=1 WHERE id IN (?,?)',[$policyScope['id'],$policyChild['id']]);
q('UPDATE familyhub_finance_policy SET enabled=0 WHERE scope_id=?',[$policyScope['id']]);
q('DELETE FROM familyhub_finance_grants WHERE scope_id=?',[$policyScope['id']]);
$childBefore=array_values(array_filter(call('crypto2.scopes.catalog',[],$fresh)['scopes'],fn($s)=>$s['id']===$policyChild['id']))[0];

$initial=candidate2($policyScope,$state);$initial['members'][0]['financeRole']='none';$initial['keyIds']['finance']=null;$initial['keyCommitments']['finance']=null;
$pending=send2('crypto2.scope.headPut',$initial,$fresh,$freshKeys);$policyHead=call('crypto2.scope.headGet',['scopeId'=>$policyScope['id'],'headHash'=>$pending['headHash']],$fresh);
policyGrants2($policyHead,[$policyHead],$fresh,$freshKeys,$root,$state);$m=call('crypto2.grants.manifest',['scopeId'=>$policyScope['id'],'headHash'=>$policyHead['headHash']],$fresh);
send2('crypto2.scope.activate',['scopeId'=>$policyScope['id'],'headHash'=>$policyHead['headHash'],'grantManifestHash'=>$m['grantManifestHash'],'authorDirectoryHeadHash'=>$state['headHash']],$fresh,$freshKeys);
[$intentProof,$intentAck,$beforePolicy,$afterPolicy]=policyProposal2($policyScope['id'],$policyHead,$state,$fresh,$freshKeys,['kind'=>'enable','enabled'=>true]);
ck(call('crypto2.scope.financePolicy.propose',$intentProof,$fresh)===$intentAck,'typed finance policy lost ACK returns exact immutable intent');
ck(q('SELECT enabled FROM familyhub_finance_policy WHERE scope_id=?',[$policyScope['id']])[0]['enabled']==0,'pending policy intent does not mutate active SQL authority');
$next=candidate2($policyScope,$state,2,$policyHead['headHash'],['content'=>hash('sha256',''),'finance'=>null]);$next['financePolicyIntentProof']=$intentProof;
$pending=send2('crypto2.scope.headPut',$next,$fresh,$freshKeys);$nextHead=call('crypto2.scope.headGet',['scopeId'=>$policyScope['id'],'headHash'=>$pending['headHash']],$fresh);
close2($policyScope['id'],$nextHead['headHash'],$policyHead,'content',$state,0,$fresh,$freshKeys);
policyGrants2($nextHead,[$policyHead,$nextHead],$fresh,$freshKeys,$root,$state);$m=call('crypto2.grants.manifest',['scopeId'=>$policyScope['id'],'headHash'=>$nextHead['headHash']],$fresh);
$activation=content2('crypto2.scope.activate',['scopeId'=>$policyScope['id'],'headHash'=>$nextHead['headHash'],'grantManifestHash'=>$m['grantManifestHash'],'authorDirectoryHeadHash'=>$state['headHash']],$fresh,$freshKeys);
ck(call('crypto2.scope.activate',$activation,$fresh)['state']==='keysReady','first enabling finance commits policy and fresh finance keys atomically');
ck(q('SELECT access_level FROM familyhub_finance_grants WHERE scope_id=? AND account_id=?',[$policyScope['id'],$fresh['user']['accountId']])[0]['access_level']==='write','enable(true) preserves legacy actor WRITE behavior');
ck((new NativeCryptoFinancePolicyV2($container))->policy($policyScope['id'])['policyHash']===$afterPolicy['policyHash'],'activated raw policy exactly matches signed resulting hash');
$childAfter=array_values(array_filter(call('crypto2.scopes.catalog',[],$fresh)['scopes'],fn($s)=>$s['id']===$policyChild['id']))[0];
ck($childBefore['accessBasis']===$childAfter['accessBasis']&&$childBefore['members']===$childAfter['members'],'finance-only policy change preserves child topology basis and effective roles');
ck(call('crypto2.scope.activate',$activation,$fresh)['state']==='keysReady','policy-consuming activation exact replay survives consumed intent');
// The public plan validator runs the exact typed intent in a rollback-only
// simulation, preserving owner NONE without requiring a future finance key.
$grantScope=send2('crypto2.scope.create',['id'=>uid(),'kind'=>'household'],$fresh,$freshKeys)['scope'];
q('UPDATE familyhub_scopes SET access_policy_version=1 WHERE id=?',[$grantScope['id']]);
q('DELETE FROM familyhub_finance_grants WHERE scope_id=?',[$grantScope['id']]);
q('INSERT INTO familyhub_members(scope_id,user_id,account_id,role,active) VALUES(?,?,?,?,1)',[$grantScope['id'],$bob['user']['id'],$bob['user']['accountId'],'member']);

$initial=candidate2($grantScope,$state);$initial['members'][0]['financeRole']='none';$initial['members'][]=member2($bobState);$initial['members'][1]['financeRole']='none';$initial['members'][1]['manageKeys']=false;usort($initial['members'],fn($a,$b)=>strcmp($a['accountId'],$b['accountId']));$initial['keyIds']['finance']=null;$initial['keyCommitments']['finance']=null;
$pending=send2('crypto2.scope.headPut',$initial,$fresh,$freshKeys);$grantHead=call('crypto2.scope.headGet',['scopeId'=>$grantScope['id'],'headHash'=>$pending['headHash']],$fresh);
policyGrants2($grantHead,[$grantHead],$fresh,$freshKeys,$root,$state);
$recipients=[['recipientKind'=>'device','recipientId'=>$bob['device']['id'],'publicKeyBase64'=>$bobKey['boxPublic'],'sealedEnvelopeBase64'=>base64_encode(random_bytes(96))],['recipientKind'=>'recovery','recipientId'=>$bobState['snapshot']['recoveryRootEpochId'],'publicKeyBase64'=>$bobRoot['boxPublic'],'sealedEnvelopeBase64'=>base64_encode(random_bytes(96))]];
send2('crypto2.grants.put',['scopeId'=>$grantScope['id'],'headHash'=>$grantHead['headHash'],'keySourceHeadHash'=>$grantHead['headHash'],'keyId'=>$grantHead['payload']['keyIds']['content'],'accountId'=>$bob['user']['accountId'],'domain'=>'content','epoch'=>1,'expectedGeneration'=>0,'recipients'=>$recipients],$fresh,$freshKeys);
$m=call('crypto2.grants.manifest',['scopeId'=>$grantScope['id'],'headHash'=>$grantHead['headHash']],$fresh);send2('crypto2.scope.activate',['scopeId'=>$grantScope['id'],'headHash'=>$grantHead['headHash'],'grantManifestHash'=>$m['grantManifestHash'],'authorDirectoryHeadHash'=>$state['headHash']],$fresh,$freshKeys);
[$grantProof,$grantAck,$beforeGrant]=policyProposal2($grantScope['id'],$grantHead,$state,$fresh,$freshKeys,['kind'=>'grant','accountId'=>$bob['user']['accountId'],'grant'=>'read']);
$future=$initial;$future['epoch']=2;$future['previousHeadHash']=$grantHead['headHash'];$future['financePolicyIntentProof']=$grantProof;foreach($future['members'] as &$member){if($member['accountId']===$bob['user']['accountId'])$member['financeRole']='read';}unset($member);
$scopes=new \Kanboard\Plugin\FamilyHub\Model\NativeCryptoScopeV2($container);$sqlScope=(new \Kanboard\Plugin\FamilyHub\Model\NativeOrganizationAccess($container))->visibleScope($grantScope['id'],$fresh['user']['accountId']);
$actor=['user'=>q('SELECT a.account_id,u.* FROM familyhub_accounts a JOIN users u ON u.id=a.user_id WHERE a.account_id=?',[$fresh['user']['accountId']])[0],'device'=>['id'=>$fresh['device']['id']]];
$pdo->beginTransaction();$plan=$scopes->validateMembershipPlan($sqlScope,$future,$scopes->current($grantScope['id']),$actor);$pdo->commit();
ck(!$plan['changed']&&$future['members'][array_search($fresh['user']['accountId'],array_column($future['members'],'accountId'))]['financeRole']==='none','grant(other) future parity preserves owner NONE and does not invent membership changes');
ck((new NativeCryptoFinancePolicyV2($container))->policy($grantScope['id'])['policyHash']===$beforeGrant['policyHash']&&!q('SELECT account_id FROM familyhub_finance_grants WHERE scope_id=? AND account_id=?',[$grantScope['id'],$fresh['user']['accountId']]),'future grant simulation rolls back all SQL authority and never grants owner a finance key');
$mutated=NativeCryptoCodec::decode($grantProof)[0];$mutated['payload']['action']['grant']='write';$changed=inner2($mutated,"JivieE2EE/v2\n",$freshKeys);deny(fn()=>call('crypto2.scope.financePolicy.propose',$changed,$fresh),'idempotency_mismatch','changed action cannot overwrite exact immutable policy intent receipt');
[$grantCommand]=NativeCryptoCodec::decode($grantProof);q('UPDATE familyhub_crypto_receipts SET created_at=? WHERE account_id=? AND request_id=?',[time()-1801,$fresh['user']['accountId'],$grantCommand['requestId']]);
ck(call('crypto2.scope.financePolicy.propose',$grantProof,$fresh)===$grantAck,'original policy ACK survives its original intent TTL without extending it');
$pdo->beginTransaction();deny(fn()=>$scopes->validateMembershipPlan($sqlScope,$future,$scopes->current($grantScope['id']),$actor),'crypto_finance_policy_intent_expired','expired typed intent cannot change future membership authority');$pdo->rollBack();
$expired=call('crypto2.scope.financePolicy.current',['scopeId'=>$grantScope['id'],'limit'=>20],$fresh);ck($expired['revision']===$beforeGrant['revision'],'failed expiry validation preserves active finance policy revision');
echo 'Crypto2 finance policy integration: '.$checks.' checks PASS'.PHP_EOL;
