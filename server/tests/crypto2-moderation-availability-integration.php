<?php
require __DIR__.'/crypto2-moderation-integration.php';

use Kanboard\Plugin\FamilyHub\Model\NativeCryptoCodec;
use Kanboard\Plugin\FamilyHub\Model\NativeModerationAdminService;

$adminId = $container['userModel']->create(['username' => $prefix.'_availability_admin','password' => bin2hex(random_bytes(20)),'role' => 'app-admin']);
$admin = new NativeModerationAdminService($container);
function availabilityReport($id, $type = 'record') {
    global $newId,$fresh,$freshKeys,$state;
    $preview = call('crypto2.moderation.reportPreview',['scopeId'=>$newId,'targetType'=>$type,'targetId'=>$id],$fresh);
    $request = content2('crypto2.moderation.report',[
        'reportId'=>uid(),'sourceContext'=>$preview['sourceContext'],'authorDirectoryHeadHash'=>$state['headHash'],
        'consentVersion'=>1,'disclosure'=>['subject'=>['title'=>'Reviewed availability','type'=>$preview['sourceContext']['type']],'evidence'=>[]],
        'reason'=>'other','details'=>'Synthetic availability only',
    ],$fresh,$freshKeys);
    return [call('crypto2.moderation.report',$request,$fresh),$preview['sourceContext'],$request];
}
function restrictAvailability($report, $source) {
    global $admin,$adminId;
    return $admin->review($adminId,['reportId'=>$report['reportId'],'reviewRevision'=>0,'targetRevision'=>$source['targetRevision'],
        'action'=>'remove_content','note'=>'Availability only','confirmation'=>'APPLY']);
}
function currentProofHash($sid, $id) {
    return hash('sha256',NativeCryptoCodec::canonical((object)json_decode(q('SELECT authorization FROM familyhub_crypto_records WHERE scope_id=? AND id=?',[$sid,$id])[0]['authorization'],true)['recordProof']));
}
$access = $head['payload']['accessRevision'];
$read = ['scopeId'=>$newId,'domain'=>'content','accessRevision'=>$access];
$currentTarget = q('SELECT * FROM familyhub_crypto_records WHERE scope_id=? AND id=?',[$newId,$target['id']])[0];
$reference = row2($newId,$head,$fresh,$freshKeys,null,'task',0,null,[['scopeId'=>$newId,'id'=>$target['id']]]);
call('crypto2.records.batch',batch2([$reference],$fresh,$freshKeys),$fresh);
$anchor = ['scopeId'=>$newId,'id'=>$reference['id'],'revision'=>1,'recordProofHash'=>currentProofHash($newId,$reference['id'])];
[$reported,$source,$reportRequest] = availabilityReport($target['id']);
$before = q('SELECT * FROM familyhub_crypto_records WHERE scope_id=? AND id=?',[$newId,$target['id']])[0];
$oldConflict=batch2([row2($newId,$head,$fresh,$freshKeys,$target['id'],'task',0)],$fresh,$freshKeys);
deny(fn()=>call('crypto2.records.batch',$oldConflict,$fresh),'conflict','pre-restriction conflict is saved with exact immutable outcome');
[$oldConflictCommand,$oldConflictBytes]=NativeCryptoCodec::decode($oldConflict);
restrictAvailability($reported,$source);
deny(fn()=>call('crypto2.records.batch',$oldConflict,$fresh),'crypto_content_restricted','saved pre-restriction conflict cannot replay its blocked remote ciphertext');
deny(fn()=>call('crypto2.receipt.get',['requestId'=>$oldConflictCommand['requestId'],'requestHash'=>hash('sha256',$oldConflictBytes)],$fresh),'crypto_content_restricted','receipt lookup cannot bypass blocked conflict transport');
$newConflict=batch2([row2($newId,$head,$fresh,$freshKeys,$target['id'],'task',0)],$fresh,$freshKeys);
try { call('crypto2.records.batch',$newConflict,$fresh); throw new RuntimeException('Expected conflict'); }
catch (\Kanboard\Plugin\FamilyHub\Model\NativeError $error) {
    ck($error->errorCode==='conflict' && $error->details['remote']===null && count($error->details['unavailable'])===1,'new conflict retains exact error without disclosing blocked remote bytes');
}
ck(q('SELECT * FROM familyhub_crypto_records WHERE scope_id=? AND id=?',[$newId,$target['id']])[0] === $before,'admin availability preserves exact current signed record and ciphertext');
$pulled = call('crypto2.records.pull',$read+['cursor'=>0,'limit'=>50],$fresh);
ck(!in_array($target['id'],array_column($pulled['records'],'id'),true) && count($pulled['unavailable'])===1 && $pulled['unavailable'][0]['recordProofHash']===$source['recordProofHash'],'ordinary pull omits restricted bytes and marks exact missing proof rather than forging tombstone');
$targetRead = $read+['id'=>$target['id'],'revision'=>2,'recordProofHash'=>$source['recordProofHash']];
deny(fn()=>call('crypto2.records.historyGet',$targetRead,$fresh),'crypto_content_restricted','blocked historical bytes require narrow verification purpose');
$evidence = call('crypto2.records.historyGet',$targetRead+['evidenceFor'=>$anchor],$fresh);
ck($evidence['verificationEvidence'] && $evidence['record']['revision']===2 && $evidence['unavailable'][0]['reason']==='moderation','preexisting exact signed reference can obtain nondisplay historical verification bytes');
$unrelated = row2($newId,$head,$fresh,$freshKeys);
call('crypto2.records.batch',batch2([$unrelated],$fresh,$freshKeys),$fresh);
$unrelatedAnchor = ['scopeId'=>$newId,'id'=>$unrelated['id'],'revision'=>1,'recordProofHash'=>currentProofHash($newId,$unrelated['id'])];
deny(fn()=>call('crypto2.records.historyGet',$targetRead+['evidenceFor'=>$unrelatedAnchor],$fresh),'crypto_verification_evidence_denied','unrelated newly authored source cannot manufacture blocked-evidence access');
$newReference = row2($newId,$head,$fresh,$freshKeys,null,'task',0,null,[['scopeId'=>$newId,'id'=>$target['id']]]);
deny(fn()=>call('crypto2.records.batch',batch2([$newReference],$fresh,$freshKeys),$fresh),'crypto_content_restricted','fresh signed reference to still-current blocked fact is rejected despite exact current CAS');
// A legitimate author correction keeps canonical identity and exact predecessor.
$correction = row2($newId,$head,$fresh,$freshKeys,$target['id'],'task',2,$source['recordProofHash']);
call('crypto2.records.batch',batch2([$correction],$fresh,$freshKeys),$fresh);
$successor = ['scopeId'=>$newId,'id'=>$target['id'],'revision'=>3,'recordProofHash'=>currentProofHash($newId,$target['id'])];
$chain = call('crypto2.records.historyGet',$targetRead+['evidenceFor'=>$successor],$fresh);
[$predecessor] = NativeCryptoCodec::decode($chain['record']['authorization']['recordProof']);
$next = q('SELECT record_proof FROM familyhub_crypto_record_history WHERE scope_id=? AND id=? AND revision=3',[$newId,$target['id']])[0]['record_proof'];
[$nextBody] = NativeCryptoCodec::decode(json_decode($next,true));
ck($nextBody['previousRecordHash']===$source['recordProofHash'] && $predecessor['expectedRevision']===1,'fresh reader can verify corrected current successor through exact blocked predecessor without cached anchor');
$history = call('crypto2.records.history',$read+['id'=>$target['id'],'afterRevision'=>0],$fresh);
ck(array_column($history['records'],'revision')===[1,3] && count($history['unavailable'])===1 && $history['nextRevision']===3,'history transports clean revisions while retaining exact gap notice');
$pulled = call('crypto2.records.pull',$read+['cursor'=>0,'limit'=>50],$fresh);
ck(in_array($target['id'],array_column($pulled['records'],'id'),true),'corrected unblocked current revision remains ordinarily readable');
$staleSuccessor=$successor;$staleSuccessor['revision']=2;$staleSuccessor['recordProofHash']=$source['recordProofHash'];
deny(fn()=>call('crypto2.records.historyGet',$targetRead+['evidenceFor'=>$staleSuccessor],$fresh),'crypto_verification_evidence_denied','blocked noncurrent source cannot claim descendant authority');
q('UPDATE familyhub_crypto_record_history SET record_proof_hash=? WHERE scope_id=? AND id=? AND revision=3',[str_repeat('f',64),$newId,$target['id']]);
deny(fn()=>call('crypto2.records.historyGet',$targetRead+['evidenceFor'=>$successor],$fresh),'crypto_verification_evidence_denied','forked descendant hash cannot expose restricted predecessor');
q('UPDATE familyhub_crypto_record_history SET record_proof_hash=? WHERE scope_id=? AND id=? AND revision=3',[$successor['recordProofHash'],$newId,$target['id']]);
// A longer chain must include every exact revision, never skip missing links.
$fourth=row2($newId,$head,$fresh,$freshKeys,$target['id'],'task',3,$successor['recordProofHash']);
call('crypto2.records.batch',batch2([$fourth],$fresh,$freshKeys),$fresh);
$latest=['scopeId'=>$newId,'id'=>$target['id'],'revision'=>4,'recordProofHash'=>currentProofHash($newId,$target['id'])];
q('UPDATE familyhub_crypto_record_history SET revision=30 WHERE scope_id=? AND id=? AND revision=3',[$newId,$target['id']]);
deny(fn()=>call('crypto2.records.historyGet',$targetRead+['evidenceFor'=>$latest],$fresh),'crypto_verification_evidence_denied','omitted middle revision rejects descendant verification exception');
q('UPDATE familyhub_crypto_record_history SET revision=3 WHERE scope_id=? AND id=? AND revision=30',[$newId,$target['id']]);
ck(call('crypto2.records.historyGet',$targetRead+['evidenceFor'=>$latest],$fresh)['verificationEvidence'],'restored complete descendant chain verifies exact historical bytes');
// Exact current-proof CAS prevents admin restriction from suppressing corrections.
deny(fn()=>restrictAvailability($reported,$source),'review_changed','old admin review cannot mutate a newer signed revision');
ck(call('crypto2.moderation.report',$reportRequest,$fresh)['reportId']===$reported['reportId'],'original report ACK remains byte-exact after restriction and correction');
// Cipher blob with two authorized current refs remains available until both restricted.
$blobBytes=random_bytes(96);$blobId=uid();
$base=['scopeId'=>$newId,'id'=>$blobId,'domain'=>'content','epoch'=>$head['payload']['epoch'],'accessRevision'=>$access,'membershipHeadHash'=>$head['headHash']];
send2('crypto2.blob.begin',$base+['size'=>strlen($blobBytes),'sha256'=>hash('sha256',$blobBytes),'manifestBase64'=>base64_encode(random_bytes(64))],$fresh,$freshKeys);
send2('crypto2.blob.chunk',$base+['offset'=>0,'dataBase64'=>base64_encode($blobBytes)],$fresh,$freshKeys);
send2('crypto2.blob.complete',$base,$fresh,$freshKeys);
$blobA=row2($newId,$head,$fresh,$freshKeys,null,'task',0,null,[],[],false,[$blobId]);
$blobB=row2($newId,$head,$fresh,$freshKeys,null,'task',0,null,[],[],false,[$blobId]);
call('crypto2.records.batch',batch2([$blobA,$blobB],$fresh,$freshKeys),$fresh);
[$reportA,$sourceA]=availabilityReport($blobA['id']);restrictAvailability($reportA,$sourceA);
$blobRead=$read+['id'=>$blobId];
$blobWire=call('crypto2.blob.get',$blobRead,$fresh);
ck(base64_decode($blobWire['dataBase64'])===$blobBytes && $blobWire['sha256']===hash('sha256',$blobBytes),'blocked plus unblocked current refs retain exact same authorized ciphertext blob/hash');
[$reportB,$sourceB]=availabilityReport($blobB['id']);restrictAvailability($reportB,$sourceB);
deny(fn()=>call('crypto2.blob.get',$blobRead,$fresh),'crypto_content_restricted','blob transport stops when every current authorized reference is restricted');
deny(fn()=>call('crypto2.blob.get',$blobRead,$outsider),'permission_revoked','blob sharing exception never bypasses scope ACL');
$copy=row2($newId,$head,$fresh,$freshKeys,null,'task',0,null,[],[],false,[$blobId]);
deny(fn()=>call('crypto2.records.batch',batch2([$copy],$fresh,$freshKeys),$fresh),'crypto_content_restricted','new record cannot revive only-blocked blob by copying its ID');
$blobCorrection=row2($newId,$head,$fresh,$freshKeys,$blobA['id'],'task',1,$sourceA['recordProofHash']);
call('crypto2.records.batch',batch2([$blobCorrection],$fresh,$freshKeys),$fresh);
$blobSuccessor=['scopeId'=>$newId,'id'=>$blobA['id'],'revision'=>2,'recordProofHash'=>currentProofHash($newId,$blobA['id'])];
$blobEvidence=call('crypto2.blob.get',$blobRead+['evidenceFor'=>$blobSuccessor,'evidenceRecord'=>['id'=>$blobA['id'],'revision'=>1,'recordProofHash'=>$sourceA['recordProofHash']]],$fresh);
ck($blobEvidence['verificationEvidence'] && base64_decode($blobEvidence['dataBase64'])===$blobBytes,'corrected current record can retrieve blocked predecessor blob solely as marked chain evidence');
deny(fn()=>call('crypto2.blob.get',$blobRead+['evidenceFor'=>$unrelatedAnchor,'evidenceRecord'=>['id'=>$blobA['id'],'revision'=>1,'recordProofHash'=>$sourceA['recordProofHash']]],$fresh),'crypto_verification_evidence_denied','arbitrary current source cannot open a blocked historical blob');
$finance=row2($newId,$head,$fresh,$freshKeys,null,'financeEntry');
call('crypto2.records.batch',batch2([$finance],$fresh,$freshKeys),$fresh);
[$financeReport,$financeSource]=availabilityReport($finance['id'],'finance');
deny(fn()=>restrictAvailability($financeReport,$financeSource),'financial_history_preserved','administrator cannot turn reporting into financial history removal');
[$deleteReport,$deleteSource]=availabilityReport($blobA['id']);restrictAvailability($deleteReport,$deleteSource);
$delete=row2($newId,$head,$fresh,$freshKeys,$blobA['id'],'task',2,$deleteSource['recordProofHash'],[],[],true);
call('crypto2.records.batch',batch2([$delete],$fresh,$freshKeys),$fresh);
$deleteAnchor=['scopeId'=>$newId,'id'=>$blobA['id'],'revision'=>3,'recordProofHash'=>currentProofHash($newId,$blobA['id'])];
$deletedEvidence=call('crypto2.records.historyGet',$read+['id'=>$blobA['id'],'revision'=>2,'recordProofHash'=>$deleteSource['recordProofHash'],'evidenceFor'=>$deleteAnchor],$fresh);
ck($deletedEvidence['verificationEvidence'] && $deletedEvidence['record']['revision']===2,'fresh signed tombstone can verify exact blocked predecessor without resurrecting current content');
$deletedPull=call('crypto2.records.pull',$read+['cursor'=>0,'limit'=>50],$fresh);
$deletedCurrent=array_values(array_filter($deletedPull['records'],fn($r)=>$r['id']===$blobA['id']));
ck(count($deletedCurrent)===1 && $deletedCurrent[0]['deleted']===true && $deletedCurrent[0]['envelopeBase64']===null,'ordinary current pull preserves actual author tombstone with no restricted plaintext revival');
$referenceDelete=row2($newId,$head,$fresh,$freshKeys,$reference['id'],'task',1,$anchor['recordProofHash'],[],[],true);
call('crypto2.records.batch',batch2([$referenceDelete],$fresh,$freshKeys),$fresh);
$deletedReferenceAnchor=['scopeId'=>$newId,'id'=>$reference['id'],'revision'=>2,'recordProofHash'=>currentProofHash($newId,$reference['id'])];
deny(fn()=>call('crypto2.records.historyGet',$targetRead+['evidenceFor'=>$deletedReferenceAnchor],$fresh),'crypto_verification_evidence_denied','deleted unrelated source cannot use the tombstone-only same-record exception');
// Signed member restriction is an availability change, not a fake client head.
[$userReport,$userSource]=availabilityReport($fresh['user']['accountId'],'user');
$headBefore=q('SELECT head_hash FROM familyhub_crypto_scope_state WHERE scope_id=?',[$newId]);
$admin->review($adminId,['reportId'=>$userReport['reportId'],'reviewRevision'=>0,'targetRevision'=>$userSource['targetRevision'],'action'=>'restrict_member','note'=>'Availability only','confirmation'=>'APPLY']);
deny(fn()=>call('crypto2.records.batch',batch2([row2($newId,$head,$fresh,$freshKeys)],$fresh,$freshKeys),$fresh),'permission_revoked','restricted member cannot write business records under old signed head');
deny(fn()=>send2('crypto2.blob.begin',$base+['size'=>96,'sha256'=>hash('sha256',$blobBytes),'manifestBase64'=>base64_encode(random_bytes(64))],$fresh,$freshKeys),'permission_revoked','restricted member cannot upload ciphertext under old signed authority');
ck(q('SELECT head_hash FROM familyhub_crypto_scope_state WHERE scope_id=?',[$newId])===$headBefore,'administrator membership availability never signs or rewrites crypto authority head');
$admin->review($adminId,['reportId'=>$userReport['reportId'],'reviewRevision'=>1,'targetRevision'=>$userSource['targetRevision'],'action'=>'unrestrict_member','note'=>'Reallow transport','confirmation'=>'APPLY']);
deny(fn()=>call('crypto2.records.batch',batch2([row2($newId,$head,$fresh,$freshKeys)],$fresh,$freshKeys),$fresh),'crypto_scope_head_changed','lifting server restriction does not revive old head business writes before legitimate fresh transition');

$catalogScope=array_values(array_filter(call('crypto2.scopes.catalog',[],$fresh)['scopes'],fn($s)=>$s['id']===$newId))[0];
$attackHead=$head;$attackHead['payload']['accessRevision']=$catalogScope['accessRevision'];
deny(fn()=>call('crypto2.records.batch',batch2([row2($newId,$attackHead,$fresh,$freshKeys)],$fresh,$freshKeys),$fresh),'crypto_scope_rotation_required','attacker cannot reuse old signed head and DEK with newly observed SQL access revision');
$attackBlob=$base;$attackBlob['accessRevision']=$catalogScope['accessRevision'];$attackBlob['id']=uid();
deny(fn()=>send2('crypto2.blob.begin',$attackBlob+['size'=>96,'sha256'=>hash('sha256',$blobBytes),'manifestBase64'=>base64_encode(random_bytes(64))],$fresh,$freshKeys),'crypto_scope_rotation_required','updated SQL access scalar cannot revive old-head ciphertext uploads');
$hashes=[];$inventories=[];
foreach (['content','finance'] as $domain) {
    $inventory=call('crypto2.domain.inventory',['scopeId'=>$newId,'domain'=>$domain,'accessRevision'=>$catalogScope['accessRevision']],$fresh);
    ck(!$inventory['hasMore'],'fresh rekey fixture obtains complete bounded domain descriptor set');
    $ctx=hash_init('sha256');foreach($inventory['descriptors'] as $descriptor){hash_update($ctx,NativeCryptoCodec::canonical((object)$descriptor)."\n");}
    $hashes[$domain]=hash_final($ctx);$inventories[$domain]=$inventory;
}
$body=candidate2($catalogScope,$state,2,$head['headHash'],$hashes);
$body['accessBasis']=$catalogScope['accessBasis'];
$put=send2('crypto2.scope.headPut',$body,$fresh,$freshKeys);
$nextHead=call('crypto2.scope.headGet',['scopeId'=>$newId,'headHash'=>$put['headHash']],$fresh);
foreach (['content','finance'] as $domain) {
    send2('crypto2.scope.closeDomain',['scopeId'=>$newId,'candidateHeadHash'=>$nextHead['headHash'],'domain'=>$domain,
        'epoch'=>1,'membershipHeadHash'=>$head['headHash'],'authorDirectoryHeadHash'=>$state['headHash'],
        'expectedSequence'=>$inventories[$domain]['scopeSequence'],'recordCount'=>count($inventories[$domain]['descriptors']),
        'manifestHash'=>$hashes[$domain],'historyBasis'=>'reviewedRecoveryBaseline'],$fresh,$freshKeys);
}
grants2($nextHead,[$head,$nextHead],$fresh,$freshKeys,$root,$state['snapshot']['recoveryRootEpochId']);
$grantManifest=call('crypto2.grants.manifest',['scopeId'=>$newId,'headHash'=>$nextHead['headHash']],$fresh);
send2('crypto2.scope.activate',['scopeId'=>$newId,'headHash'=>$nextHead['headHash'],'grantManifestHash'=>$grantManifest['grantManifestHash'],'authorDirectoryHeadHash'=>$state['headHash']],$fresh,$freshKeys);
ck(call('crypto2.records.batch',batch2([row2($newId,$nextHead,$fresh,$freshKeys)],$fresh,$freshKeys),$fresh)['status']==='applied','actual approved fresh head/DEKs unlock business writes after restriction cleanup');

echo 'Crypto2 moderation availability integration: '.$checks.' checks PASS'.PHP_EOL;
