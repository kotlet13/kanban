<?php
/** Synthetic protocol staging only: a keysReady scope is not a plaintext migration commit. */
require __DIR__.'/crypto2-integration.php';
use Kanboard\Plugin\FamilyHub\Model\NativeCryptoCodec;
function inner2($body,$domain,$key) {
    $raw=NativeCryptoCodec::canonical((object)$body);
    return ['commandBase64'=>base64_encode($raw),'signatureBase64'=>base64_encode(sodium_crypto_sign_detached($domain.$raw,$key['sign']))];
}
function financeCard2($core,$u,$key,$authorHead) {
    unset($core['financeKeyProposalProof'],$core['contentKeyProposalProof']);
    return inner2(['version'=>2,'operation'=>'crypto2.scope.financeKeyProposal','serverId'=>$u['serverId'],'scopeId'=>$core['scopeId'],'epoch'=>$core['epoch'],'previousHeadHash'=>$core['previousHeadHash'],'proposalContextHash'=>hash('sha256',"JivieScopeHeadCore/v2\n".NativeCryptoCodec::canonical((object)$core)),'keyId'=>$core['keyIds']['finance'],'keyCommitment'=>$core['keyCommitments']['finance'],'accountId'=>$u['user']['accountId'],'deviceId'=>$u['device']['id'],'authorDirectoryHeadHash'=>$authorHead],"JivieE2EE/financeKeyProposal/v2\n",$key);
}
function content2($op, $p, $u, $key, $id=null) {
    $id=$id??uid();
    if ($op==='crypto2.access.prepare' && ($p['action']['kind']??null)==='accessPolicy' && ($p['action']['targetVersion']??null)===3 && !isset($p['consequenceSnapshot'])) { $p['consequenceSnapshot']=call('crypto2.access.consequences',['scopeId'=>$p['scopeId'],'membershipHeadHash'=>$p['membershipHeadHash'],'requestId'=>$id],$u)['consequenceSnapshot']; }
    if (in_array($op,['crypto2.scope.create','crypto2.scope.ensurePersonal'],true) && !isset($p['originProof'])) {
        $kind=$op==='crypto2.scope.ensurePersonal'?'personal':$p['kind'];
        $reference=call('crypto2.account.status',[],$u)['headHash'];
        $parentToken=isset($p['parentScopeId'])?(new \Kanboard\Plugin\FamilyHub\Model\NativeCryptoLifecycleV2($GLOBALS['container']))->parentToken($p['id'],$p['parentScopeId']):null;
        $p['originProof']=inner2(['version'=>2,'operation'=>'crypto2.scope.origin','serverId'=>$u['serverId'],'scopeId'=>$p['id'],'kind'=>$kind,'accessPolicyVersion'=>$kind==='personal'?1:3,'parentScopeToken'=>$parentToken,'requestId'=>$id,'accountId'=>$u['user']['accountId'],'deviceId'=>$u['device']['id'],'authorDirectoryHeadHash'=>$reference],"JivieE2EE/scopeOrigin/v2\n",$key);
    }
    if ($op==='crypto2.scope.closeDomain' && ($p['domain']??null)==='content' && !isset($p['closingLifecycleHash'])) { $p['closingLifecycleHash']=(new \Kanboard\Plugin\FamilyHub\Model\NativeCryptoLifecycleV2($GLOBALS['container']))->closingHash($p['scopeId']); }
    if ($op==='crypto2.scope.headPut' && $p['keyIds']['finance']!==null && $p['financeKeyProposalProof']===null) {
        $p['financeKeyProposalProof']=financeCard2($p,$u,$key,$p['authorDirectoryHeadHash']);
    }
    if ($op==='crypto2.scope.activate' && !isset($p['activationProof']) && !isset($p['financeGrantManifestProof'])) {
        $h=call('crypto2.scope.headGet',['scopeId'=>$p['scopeId'],'headHash'=>$p['headHash']],$u);
        if ($h['payload']['keyIds']['finance']!==null) {
            $root=call('crypto2.grants.manifest',['scopeId'=>$p['scopeId'],'headHash'=>$p['headHash']],$u)['domains']['finance'];
            $p['financeGrantManifestProof']=inner2(['version'=>2,'operation'=>'crypto2.scope.financeGrantManifest','serverId'=>$u['serverId'],'scopeId'=>$p['scopeId'],'headHash'=>$p['headHash'],'financeManifestHash'=>$root,'accountId'=>$u['user']['accountId'],'deviceId'=>$u['device']['id'],'authorDirectoryHeadHash'=>$p['authorDirectoryHeadHash']],"JivieE2EE/financeGrantManifest/v2\n",$key);
        }
    }
    $c=['version'=>2,'operation'=>$op,'requestId'=>$id??uid(),'serverId'=>$u['serverId'],'accountId'=>$u['user']['accountId'],'deviceId'=>$u['device']['id'],'signer'=>'device','payload'=>$p];
    $raw=NativeCryptoCodec::canonical((object)$c);
    return ['commandBase64'=>base64_encode($raw),'signatureBase64'=>base64_encode(sodium_crypto_sign_detached("JivieE2EE/v2\n".$raw,$key['sign']))];
}
function send2($op,$p,$u,$key) { return call($op,content2($op,$p,$u,$key),$u); }
function candidate2($scope,$state,$epoch=1,$old=null,$closures=null) {
    $snap=$state['snapshot'];
    return ['financePolicyIntentProof'=>null,'previousLifecycleHash'=>$epoch===1?null:(new \Kanboard\Plugin\FamilyHub\Model\NativeCryptoLifecycleV2($GLOBALS['container']))->closingHash($scope['id']),'initialLifecycleHash'=>q('SELECT initial_hash FROM familyhub_crypto_lifecycle_baselines_v2 WHERE scope_id=?',[$scope['id']])[0]['initial_hash'],'scopeId'=>$scope['id'],'epoch'=>$epoch,'previousHeadHash'=>$old??str_repeat('0',64),'authorDirectoryHeadHash'=>$state['headHash'],'expectedAccessRevision'=>$scope['accessRevision'],'accessBasis'=>[['scopeToken'=>hash('sha256',"JivieScopeAccessBasis/v2\n".$state['snapshot']['serverId'].':'.$scope['id'].':'.$scope['id']),'accessRevision'=>(int)q('SELECT access_revision FROM familyhub_scopes WHERE id=?',[$scope['id']])[0]['access_revision']]],'accessRevision'=>$scope['accessRevision'],'members'=>[['accountId'=>$snap['accountId'],'rootSigningKeyBase64'=>$snap['rootSigningKeyBase64'],'rootEncryptionKeyBase64'=>$snap['rootEncryptionKeyBase64'],'recoveryRootEpochId'=>$snap['recoveryRootEpochId'],'identityEpochId'=>$snap['identityEpochId'],'directoryHeadHash'=>$state['headHash'],'deviceSnapshotHash'=>$state['deviceSnapshotHash'],'role'=>'owner','financeRole'=>'write','manageKeys'=>true]],'membershipIntents'=>[],'closures'=>$closures??['content'=>null,'finance'=>null],'keyCommitments'=>['content'=>hash('sha256',"JivieScopeKey/v2\n".random_bytes(32)),'finance'=>hash('sha256',"JivieScopeKey/v2\n".random_bytes(32))],'keyIds'=>['content'=>uid(),'finance'=>uid()],'contentKeyProposalProof'=>null,'financeKeyProposalProof'=>null];
}
function grants2($head,$sources,$u,$key,$root,$epoch) {
    foreach(['content','finance'] as $domain) foreach($sources as $source) {
        $r=[['recipientKind'=>'device','recipientId'=>$u['device']['id'],'publicKeyBase64'=>$key['boxPublic'],'sealedEnvelopeBase64'=>base64_encode(sodium_crypto_box_seal('Synthetic domain key',base64_decode($key['boxPublic'])))],['recipientKind'=>'recovery','recipientId'=>$epoch,'publicKeyBase64'=>$root['boxPublic'],'sealedEnvelopeBase64'=>base64_encode(sodium_crypto_box_seal('Synthetic domain key',base64_decode($root['boxPublic'])))]];
        send2('crypto2.grants.put',['scopeId'=>$head['scopeId'],'headHash'=>$head['headHash'],'keySourceHeadHash'=>$source['headHash'],'keyId'=>$source['payload']['keyIds'][$domain],'accountId'=>$u['user']['accountId'],'domain'=>$domain,'epoch'=>$source['payload']['epoch'],'expectedGeneration'=>0,'recipients'=>$r],$u,$key);
    }
}
$state=call('crypto2.account.status',[],$fresh);
$space=scope($fresh,'organization');

send2('crypto2.scope.prepare',['scopeId'=>$space['id'],'expectedAccessRevision'=>$space['accessRevision']],$fresh,$freshKeys);
q('UPDATE familyhub_finance_policy SET enabled=1,required_contract_version=3 WHERE scope_id=?',[$space['id']]);
$body=candidate2($space,$state);
$pending=send2('crypto2.scope.headPut',$body,$fresh,$freshKeys);
ck($pending['state']==='pendingKeys','signed scope proposal remains pending before key evidence');
$head=call('crypto2.scope.headGet',['scopeId'=>$space['id'],'headHash'=>$pending['headHash']],$fresh);
$manifest=call('crypto2.grants.manifest',['scopeId'=>$space['id'],'headHash'=>$pending['headHash']],$fresh);
deny(fn()=>send2('crypto2.scope.activate',['scopeId'=>$space['id'],'headHash'=>$pending['headHash'],'grantManifestHash'=>$manifest['grantManifestHash'],'authorDirectoryHeadHash'=>$state['headHash']],$fresh,$freshKeys),'crypto_keys_pending','scope activation refuses missing recipient groups');
grants2($head,[$head],$fresh,$freshKeys,$root,$epoch);
$manifest=call('crypto2.grants.manifest',['scopeId'=>$space['id'],'headHash'=>$pending['headHash']],$fresh);
$activate=content2('crypto2.scope.activate',['scopeId'=>$space['id'],'headHash'=>$pending['headHash'],'grantManifestHash'=>$manifest['grantManifestHash'],'authorDirectoryHeadHash'=>$state['headHash']],$fresh,$freshKeys);
$ready=call('crypto2.scope.activate',$activate,$fresh);
ck($ready['state']==='keysReady'&&call('crypto2.scope.activate',$activate,$fresh)===$ready,'complete durable grants activate atomically and replay exact lost ACK');
ck(q('SELECT state FROM familyhub_crypto_scopes WHERE scope_id=?',[$space['id']])[0]['state']==='staged','keysReady never silently commits plaintext migration');
$catalog=call('crypto2.scopes.catalog',[],$fresh);
$entry=array_values(array_filter($catalog['scopes'],fn($r)=>$r['id']===$space['id']))[0];
ck(!isset($entry['name'])&&!isset($entry['address'])&&$entry['members'][0]['accountId']===$fresh['user']['accountId'],'new catalog exposes structural ACL without plaintext names or address');
$memberDirectory=call('crypto2.directory.read',['scopeId'=>$space['id'],'accountId'=>$fresh['user']['accountId'],'afterGeneration'=>0,'limit'=>2],$fresh);
ck(count($memberDirectory['entries'])===2&&$memberDirectory['hasMore']&&$memberDirectory['headHash']===$state['headHash'],'member directory read is bounded and binds captured final prefix');
$outsider=user('scope_outsider');
deny(fn()=>call('crypto2.directory.status',['scopeId'=>$space['id'],'accountId'=>$fresh['user']['accountId']],$outsider),'permission_revoked','directory is not an outsider public-key oracle');
q('UPDATE familyhub_email_identities SET verified_at=NULL WHERE account_id=?',[$fresh['user']['accountId']]);
ck(call('crypto2.scope.headGet',['scopeId'=>$space['id']],$fresh)['headHash']===$head['headHash'],'existing scope reads work without verified email');
$secondBody=candidate2($space,$state,2,$head['headHash'],['content'=>hash('sha256',''),'finance'=>hash('sha256','')]);
deny(fn()=>send2('crypto2.scope.headPut',$secondBody,$fresh,$freshKeys),'email_verification_required','scope writes still require verified email');
q('UPDATE familyhub_email_identities SET verified_at=? WHERE account_id=?',[time(),$fresh['user']['accountId']]);
$secondPending=send2('crypto2.scope.headPut',$secondBody,$fresh,$freshKeys);
$secondHead=call('crypto2.scope.headGet',['scopeId'=>$space['id'],'headHash'=>$secondPending['headHash']],$fresh);
function close2($sid,$candidate,$source,$domain,$state,$sequence,$u,$key) {
    return send2('crypto2.scope.closeDomain',['scopeId'=>$sid,'candidateHeadHash'=>$candidate,'domain'=>$domain,'epoch'=>$source['payload']['epoch'],'membershipHeadHash'=>$source['headHash'],'authorDirectoryHeadHash'=>$state['headHash'],'expectedSequence'=>$sequence,'recordCount'=>0,'manifestHash'=>hash('sha256',''),'historyBasis'=>'reviewedRecoveryBaseline'],$u,$key);
}
close2($space['id'],$secondHead['headHash'],$head,'content',$state,0,$fresh,$freshKeys);
// A concurrent financial write advances only finance's durable cursor. Its inventory is still empty here.
q('UPDATE familyhub_crypto_domain_cursors SET sequence=1 WHERE scope_id=? AND domain=?',[$space['id'],'finance']);
close2($space['id'],$secondHead['headHash'],$head,'finance',$state,1,$fresh,$freshKeys);
grants2($secondHead,[$head,$secondHead],$fresh,$freshKeys,$root,$epoch);
$manifest=call('crypto2.grants.manifest',['scopeId'=>$space['id'],'headHash'=>$secondHead['headHash']],$fresh);
$activated=send2('crypto2.scope.activate',['scopeId'=>$space['id'],'headHash'=>$secondHead['headHash'],'grantManifestHash'=>$manifest['grantManifestHash'],'authorDirectoryHeadHash'=>$state['headHash']],$fresh,$freshKeys);
ck($activated['epoch']===2,'finance interleave between closures does not invalidate unchanged content cursor');
$page1=call('crypto2.grants.list',['scopeId'=>$space['id'],'headHash'=>$secondHead['headHash'],'domain'=>'content'],$fresh);
$page2=call('crypto2.grants.list',['scopeId'=>$space['id'],'headHash'=>$secondHead['headHash'],'domain'=>'content','afterEpoch'=>$page1['nextEpoch']],$fresh);
ck(count($page1['grants'])===1&&$page1['hasMore']&&count($page2['grants'])===1&&!$page2['hasMore'],'historical grants pages preserve whole bounded epoch groups');
$closure=call('crypto2.scope.closureGet',['scopeId'=>$space['id'],'candidateHeadHash'=>$secondHead['headHash'],'domain'=>'content','epoch'=>1,'manifestHash'=>hash('sha256','')],$fresh);
ck($closure['sequence']===0&&$closure['historyBasis']==='reviewedRecoveryBaseline'&&$closure['authorization']['commandBase64']!=='','closing proof retains author provenance and explicit recovery history basis');
// Cancellation retires candidate authority, never reopens an immutable closed epoch.
$thirdBody=candidate2($space,$state,3,$secondHead['headHash'],['content'=>hash('sha256',''),'finance'=>hash('sha256','')]);
$thirdPending=send2('crypto2.scope.headPut',$thirdBody,$fresh,$freshKeys);
close2($space['id'],$thirdPending['headHash'],$secondHead,'content',$state,0,$fresh,$freshKeys);
ck(q('SELECT content_closed,finance_closed FROM familyhub_crypto_scope_state WHERE scope_id=?',[$space['id']])[0]==['content_closed'=>1,'finance_closed'=>0],'candidate closure freezes only its own domain');
$cancelled=send2('crypto2.scope.cancel',['scopeId'=>$space['id'],'headHash'=>$thirdPending['headHash']],$fresh,$freshKeys);
ck($cancelled['cleanupRequired']&&(int)q('SELECT content_closed FROM familyhub_crypto_scope_state WHERE scope_id=?',[$space['id']])[0]['content_closed']===1&&count(q('SELECT * FROM familyhub_crypto_closures WHERE scope_id=?',[$space['id']]))===3,'cancel preserves irreversible closed epoch and reports resumable successor cleanup');
$fourthBody=candidate2($space,$state,3,$secondHead['headHash'],['content'=>hash('sha256',''),'finance'=>hash('sha256','')]);
$fourthProof=content2('crypto2.scope.headPut',$fourthBody,$fresh,$freshKeys);$fourth=call('crypto2.scope.headPut',$fourthProof,$fresh);
close2($space['id'],$fourth['headHash'],$secondHead,'content',$state,0,$fresh,$freshKeys);
[$fourthCommand]=NativeCryptoCodec::decode($fourthProof);
q('UPDATE familyhub_crypto_receipts SET created_at=? WHERE account_id=? AND request_id=?',[time()-1801,$fresh['user']['accountId'],$fourthCommand['requestId']]);
$newBody=candidate2($space,$state,3,$secondHead['headHash'],['content'=>hash('sha256',''),'finance'=>hash('sha256','')]);
$newCandidate=send2('crypto2.scope.headPut',$newBody,$fresh,$freshKeys);
ck(q('SELECT state FROM familyhub_crypto_scope_heads WHERE scope_id=? AND head_hash=?',[$space['id'],$fourth['headHash']])[0]['state']==='expired'&&(int)q('SELECT content_closed FROM familyhub_crypto_scope_state WHERE scope_id=?',[$space['id']])[0]['content_closed']===1,'expired candidate cannot authorize activation or erase an existing immutable closure');
$reused=$newBody;$reused['keyCommitments']['content']=$body['keyCommitments']['content'];$reused['keyIds']['content']=uid();
deny(fn()=>send2('crypto2.scope.headPut',$reused,$fresh,$freshKeys),'crypto_scope_key_reused','rotation rejects a DEK commitment reused from any historical epoch');
$cleanup=call('crypto2.scope.headGet',['scopeId'=>$space['id'],'headHash'=>$newCandidate['headHash']],$fresh);
foreach(['content','finance'] as $domain){close2($space['id'],$cleanup['headHash'],$secondHead,$domain,$state,$domain==='finance'?1:0,$fresh,$freshKeys);}
grants2($cleanup,[$head,$secondHead,$cleanup],$fresh,$freshKeys,$root,$epoch);
$cleanupManifest=call('crypto2.grants.manifest',['scopeId'=>$space['id'],'headHash'=>$cleanup['headHash']],$fresh);
send2('crypto2.scope.activate',['scopeId'=>$space['id'],'headHash'=>$cleanup['headHash'],'grantManifestHash'=>$cleanupManifest['grantManifestHash'],'authorDirectoryHeadHash'=>$state['headHash']],$fresh,$freshKeys);
ck(q('SELECT content_closed,finance_closed FROM familyhub_crypto_scope_state WHERE scope_id=?',[$space['id']])[0]==['content_closed'=>0,'finance_closed'=>0]&&q('SELECT head_hash FROM familyhub_crypto_scope_state WHERE scope_id=?',[$space['id']])[0]['head_hash']===$cleanup['headHash'],'fresh authorized successor completes canceled or expired closure cleanup without changing membership');
echo 'Crypto2 scope integration: '.$checks.' checks PASS'.PHP_EOL;
