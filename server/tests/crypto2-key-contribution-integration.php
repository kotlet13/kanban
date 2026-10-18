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

function domainGrantKey2($domain,$candidate,$source,$target,$targetKey,$targetRoot,$targetState,$author,$authorKey) {
    $recipients=[['recipientKind'=>'device','recipientId'=>$target['device']['id'],'publicKeyBase64'=>$targetKey['boxPublic'],'sealedEnvelopeBase64'=>base64_encode(random_bytes(96))],['recipientKind'=>'recovery','recipientId'=>$targetState['snapshot']['recoveryRootEpochId'],'publicKeyBase64'=>$targetRoot['boxPublic'],'sealedEnvelopeBase64'=>base64_encode(random_bytes(96))]];
    return send2('crypto2.grants.put',['scopeId'=>$candidate['scopeId'],'headHash'=>$candidate['headHash'],'keySourceHeadHash'=>$source['headHash'],'keyId'=>$source['payload']['keyIds'][$domain],'accountId'=>$target['user']['accountId'],'domain'=>$domain,'epoch'=>$source['payload']['epoch'],'expectedGeneration'=>0,'recipients'=>$recipients],$author,$authorKey);
}
function domainCard2($core,$domain,$u,$key,$state) {
    return inner2(['version'=>2,'operation'=>'crypto2.scope.'.$domain.'KeyProposal','serverId'=>$u['serverId'],'scopeId'=>$core['scopeId'],'epoch'=>$core['epoch'],'previousHeadHash'=>$core['previousHeadHash'],'proposalContextHash'=>hash('sha256',"JivieScopeHeadCore/v2\n".NativeCryptoCodec::canonical((object)$core)),'keyId'=>$core['keyIds'][$domain],'keyCommitment'=>$core['keyCommitments'][$domain],'accountId'=>$u['user']['accountId'],'deviceId'=>$u['device']['id'],'authorDirectoryHeadHash'=>$state['headHash']],"JivieE2EE/".$domain."KeyProposal/v2\n",$key);
}
$successor=user('key_successor');[$successorRoot,$successorKey,$successorState]=initializeMember2($successor);
$contributor=user('key_finance');[$financeRoot,$financeKey,$financeState]=initializeMember2($contributor);
$shared=scope($fresh,'household',1);
foreach([$successor,$contributor] as $member){q('INSERT INTO familyhub_members(scope_id,user_id,account_id,role,active) VALUES(?,?,?,?,1)',[$shared['id'],$member['user']['id'],$member['user']['accountId'],'member']);}
q('UPDATE familyhub_scopes SET access_revision=1 WHERE id=?',[$shared['id']]);$shared['accessRevision']=1;
send2('crypto2.scope.prepare',['scopeId'=>$shared['id'],'expectedAccessRevision'=>1],$fresh,$freshKeys);
$initial=candidate2($shared,$state);$initial['members'][0]['financeRole']='none';
foreach([[$successorState,'member'],[$financeState,'member']] as [$st,$role]){$member=member2($st,$role);$member['financeRole']='none';$member['manageKeys']=false;$initial['members'][]=$member;}
usort($initial['members'],fn($a,$b)=>strcmp($a['accountId'],$b['accountId']));$initial['keyIds']['finance']=null;$initial['keyCommitments']['finance']=null;
$pending=send2('crypto2.scope.headPut',$initial,$fresh,$freshKeys);$initialHead=call('crypto2.scope.headGet',['scopeId'=>$shared['id'],'headHash'=>$pending['headHash']],$fresh);
foreach([[$fresh,$freshKeys,$root,$state],[$successor,$successorKey,$successorRoot,$successorState],[$contributor,$financeKey,$financeRoot,$financeState]] as [$u,$key,$r,$st]){domainGrantKey2('content',$initialHead,$initialHead,$u,$key,$r,$st,$fresh,$freshKeys);}
$manifest=call('crypto2.grants.manifest',['scopeId'=>$shared['id'],'headHash'=>$initialHead['headHash']],$fresh);
send2('crypto2.scope.activate',['scopeId'=>$shared['id'],'headHash'=>$initialHead['headHash'],'grantManifestHash'=>$manifest['grantManifestHash'],'authorDirectoryHeadHash'=>$state['headHash']],$fresh,$freshKeys);
q('INSERT INTO familyhub_finance_policy(scope_id,enabled,revision,sequence) VALUES(?,1,1,0)',[$shared['id']]);q('INSERT INTO familyhub_finance_grants(scope_id,account_id,access_level) VALUES(?,?,?)',[$shared['id'],$contributor['user']['accountId'],'read']);q('UPDATE familyhub_scopes SET access_revision=2 WHERE id=?',[$shared['id']]);$shared['accessRevision']=2;
$next=candidate2($shared,$state,2,$initialHead['headHash'],['content'=>hash('sha256',''),'finance'=>null]);$next['accessRevision']=3;
$owner=member2($successorState,'owner');$owner['financeRole']='none';$finance=member2($financeState,'member');$finance['financeRole']='read';$finance['manageKeys']=false;$next['members']=[$owner,$finance];usort($next['members'],fn($a,$b)=>strcmp($a['accountId'],$b['accountId']));
$next['keyIds']=['content'=>null,'finance'=>null];$next['keyCommitments']=['content'=>null,'finance'=>null];unset($next['contentKeyProposalProof'],$next['financeKeyProposalProof']);
$draftId=uid();$putProof=content2('crypto2.scope.keyDraft.put',['scopeId'=>$shared['id'],'draftId'=>$draftId,'requestedDomains'=>['content','finance'],'core'=>$next],$fresh,$freshKeys);$draft=call('crypto2.scope.keyDraft.put',$putProof,$fresh);
ck($draft['finalCore']===null&&count($draft['offers'])===0,'departing manager publishes only signed keyless skeleton');
$offer=['scopeId'=>$shared['id'],'draftId'=>$draftId,'managerDraftHash'=>$draft['managerDraftHash'],'domain'=>'content','keyId'=>uid(),'keyCommitment'=>hash('sha256',random_bytes(32)),'authorDirectoryHeadHash'=>$successorState['headHash']];
deny(fn()=>send2('crypto2.scope.keyDraft.offer',$offer,$fresh,$freshKeys),'crypto_key_contributor_forbidden','departing manager cannot offer own future content key');
$offered=send2('crypto2.scope.keyDraft.offer',$offer,$successor,$successorKey);
deny(fn()=>send2('crypto2.scope.keyDraft.sign',['scopeId'=>$shared['id'],'draftId'=>$draftId,'domain'=>'content','keyProposalProof'=>domainCard2($offered['core'],'content',$successor,$successorKey,$successorState)],$successor,$successorKey),'crypto_key_offers_incomplete','final card waits for both independent key offers');
$offered=send2('crypto2.scope.keyDraft.offer',['scopeId'=>$shared['id'],'draftId'=>$draftId,'managerDraftHash'=>$draft['managerDraftHash'],'domain'=>'finance','keyId'=>uid(),'keyCommitment'=>hash('sha256',random_bytes(32)),'authorDirectoryHeadHash'=>$financeState['headHash'],'financeClosureHash'=>null],$contributor,$financeKey);
$core=$offered['finalCore'];$contentCard=domainCard2($core,'content',$successor,$successorKey,$successorState);$financeCard=domainCard2($core,'finance',$contributor,$financeKey,$financeState);
send2('crypto2.scope.keyDraft.sign',['scopeId'=>$shared['id'],'draftId'=>$draftId,'domain'=>'content','keyProposalProof'=>$contentCard],$successor,$successorKey);
$ready=send2('crypto2.scope.keyDraft.sign',['scopeId'=>$shared['id'],'draftId'=>$draftId,'domain'=>'finance','keyProposalProof'=>$financeCard],$contributor,$financeKey);
ck($ready['state']==='ready'&&count($ready['signatures'])===2,'two distinct contributors sign identical final head core');
$body=$core+['contentKeyProposalProof'=>$contentCard,'financeKeyProposalProof'=>$financeCard];$pending=send2('crypto2.scope.headPut',$body,$fresh,$freshKeys);$head=call('crypto2.scope.headGet',['scopeId'=>$shared['id'],'headHash'=>$pending['headHash']],$fresh);
close2($shared['id'],$head['headHash'],$initialHead,'content',$state,0,$fresh,$freshKeys);
foreach([[$successor,$successorKey,$successorRoot,$successorState],[$contributor,$financeKey,$financeRoot,$financeState]] as [$u,$key,$r,$st]) {
 domainGrantKey2('content',$head,$initialHead,$u,$key,$r,$st,$fresh,$freshKeys);
 domainGrantKey2('content',$head,$head,$u,$key,$r,$st,$successor,$successorKey);
}
deny(fn()=>domainGrantKey2('content',$head,$head,$successor,$successorKey,$successorRoot,$successorState,$fresh,$freshKeys),'crypto_key_contributor_required','departing owner cannot upload or receive new-epoch content grants');
domainGrantKey2('finance',$head,$head,$contributor,$financeKey,$financeRoot,$financeState,$contributor,$financeKey);
$roots=call('crypto2.grants.manifest',['scopeId'=>$shared['id'],'headHash'=>$head['headHash']],$fresh);
$contentManifest=inner2(['version'=>2,'operation'=>'crypto2.scope.contentGrantManifest','serverId'=>$fresh['serverId'],'scopeId'=>$shared['id'],'headHash'=>$head['headHash'],'contentManifestHash'=>$roots['domains']['content'],'accountId'=>$successor['user']['accountId'],'deviceId'=>$successor['device']['id'],'authorDirectoryHeadHash'=>$successorState['headHash']],"JivieE2EE/contentGrantManifest/v2\n",$successorKey);
$financeManifest=inner2(['version'=>2,'operation'=>'crypto2.scope.financeGrantManifest','serverId'=>$fresh['serverId'],'scopeId'=>$shared['id'],'headHash'=>$head['headHash'],'financeManifestHash'=>$roots['domains']['finance'],'accountId'=>$contributor['user']['accountId'],'deviceId'=>$contributor['device']['id'],'authorDirectoryHeadHash'=>$financeState['headHash']],"JivieE2EE/financeGrantManifest/v2\n",$financeKey);
send2('crypto2.scope.contentManifest.put',['scopeId'=>$shared['id'],'headHash'=>$head['headHash'],'contentGrantManifestProof'=>$contentManifest],$successor,$successorKey);
send2('crypto2.scope.financeManifest.put',['scopeId'=>$shared['id'],'headHash'=>$head['headHash'],'financeGrantManifestProof'=>$financeManifest],$contributor,$financeKey);
$acceptance=inner2(['version'=>2,'operation'=>'crypto2.scope.ownerAccept','serverId'=>$fresh['serverId'],'scopeId'=>$shared['id'],'headHash'=>$head['headHash'],'previousHeadHash'=>$initialHead['headHash'],'grantManifestHash'=>$roots['grantManifestHash'],'accountId'=>$successor['user']['accountId'],'deviceId'=>$successor['device']['id'],'authorDirectoryHeadHash'=>$successorState['headHash']],"JivieE2EE/scopeOwnerAcceptance/v2\n",$successorKey);
send2('crypto2.scope.ownerAcceptance.put',['scopeId'=>$shared['id'],'headHash'=>$head['headHash'],'ownerAcceptanceProof'=>$acceptance],$successor,$successorKey);
$activation=content2('crypto2.scope.activate',['scopeId'=>$shared['id'],'headHash'=>$head['headHash'],'grantManifestHash'=>$roots['grantManifestHash'],'authorDirectoryHeadHash'=>$state['headHash'],'ownerAcceptanceProof'=>$acceptance,'contentGrantManifestProof'=>$contentManifest,'financeGrantManifestProof'=>$financeManifest],$fresh,$freshKeys);
$result=call('crypto2.scope.activate',$activation,$fresh);ck($result['state']==='keysReady','two-party independent future keys activate atomic ownership transfer');ck(call('crypto2.scope.activate',$activation,$fresh)===$result,'departed owner exact activation lost ACK is minimal and replayable');
ck(count(q('SELECT account_id FROM familyhub_crypto_grant_entries_v2 WHERE scope_id=? AND head_hash=? AND epoch=2 AND account_id=?',[$shared['id'],$head['headHash'],$fresh['user']['accountId']]))===0,'departed owner has zero new-epoch recipient envelopes');

function pendingFinanceDraft2($scopeId,$source,$owner,$ownerKey,$ownerState,$finance,$financeKey,$financeState) {
 $catalog=call('crypto2.scopes.catalog',[],$owner);$scope=array_values(array_filter($catalog['scopes'],fn($r)=>$r['id']===$scopeId))[0];
 $core=$source['payload'];unset($core['contentKeyProposalProof'],$core['financeKeyProposalProof']);$core['epoch']++;$core['previousHeadHash']=$source['headHash'];$core['authorDirectoryHeadHash']=$ownerState['headHash'];$core['expectedAccessRevision']=$scope['accessRevision'];$core['accessRevision']=$scope['accessRevision'];$core['accessBasis']=$scope['accessBasis'];$core['keyIds']=['content'=>uid(),'finance'=>null];$core['keyCommitments']=['content'=>hash('sha256',random_bytes(32)),'finance'=>null];$core['closures']=['content'=>hash('sha256',''),'finance'=>null];
 $draftId=uid();$draft=send2('crypto2.scope.keyDraft.put',['scopeId'=>$scopeId,'draftId'=>$draftId,'requestedDomains'=>['finance'],'core'=>$core],$owner,$ownerKey);
 $offered=send2('crypto2.scope.keyDraft.offer',['scopeId'=>$scopeId,'draftId'=>$draftId,'managerDraftHash'=>$draft['managerDraftHash'],'domain'=>'finance','keyId'=>uid(),'keyCommitment'=>hash('sha256',random_bytes(32)),'authorDirectoryHeadHash'=>$financeState['headHash'],'financeClosureHash'=>hash('sha256','')],$finance,$financeKey);
 $card=domainCard2($offered['finalCore'],'finance',$finance,$financeKey,$financeState);send2('crypto2.scope.keyDraft.sign',['scopeId'=>$scopeId,'draftId'=>$draftId,'domain'=>'finance','keyProposalProof'=>$card],$finance,$financeKey);
 $pending=send2('crypto2.scope.headPut',$offered['finalCore']+['contentKeyProposalProof'=>null,'financeKeyProposalProof'=>$card],$owner,$ownerKey);
 return [$draftId,$pending];
}
$current=call('crypto2.scope.headGet',['scopeId'=>$shared['id']],$successor);
[$cancelId,$cancelHead]=pendingFinanceDraft2($shared['id'],$current,$successor,$successorKey,$successorState,$contributor,$financeKey,$financeState);
send2('crypto2.scope.keyDraft.cancel',['scopeId'=>$shared['id'],'draftId'=>$cancelId],$successor,$successorKey);
deny(fn()=>send2('crypto2.scope.activate',['scopeId'=>$shared['id'],'headHash'=>$cancelHead['headHash'],'authorDirectoryHeadHash'=>$successorState['headHash'],'grantManifestHash'=>hash('sha256','')],$successor,$successorKey),'crypto_scope_head_conflict','cancel after head proposal prevents activation without erasing source or offers');
[$expiryId,$expiryHead]=pendingFinanceDraft2($shared['id'],$current,$successor,$successorKey,$successorState,$contributor,$financeKey,$financeState);
q('UPDATE familyhub_crypto_key_drafts SET expires_at=? WHERE scope_id=? AND id=?',[time()-1,$shared['id'],$expiryId]);
deny(fn()=>send2('crypto2.scope.activate',['scopeId'=>$shared['id'],'headHash'=>$expiryHead['headHash'],'authorDirectoryHeadHash'=>$successorState['headHash'],'grantManifestHash'=>hash('sha256','')],$successor,$successorKey),'crypto_scope_head_conflict','original draft expiry before activation cannot be refreshed by final card or proposed head');
ck(call('crypto2.scope.headGet',['scopeId'=>$shared['id']],$successor)['headHash']===$current['headHash'],'cancelled and expired successors preserve existing active source head');
echo 'Crypto2 key contribution integration: '.$checks.' checks PASS'.PHP_EOL;
