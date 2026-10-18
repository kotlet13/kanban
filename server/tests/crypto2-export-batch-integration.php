<?php
require __DIR__.'/crypto2-export-integration.php';

function exactExportBatch($proofs, $bindings, $u, $key) {
    $digests=[];$groups=[];$batch=null;
    foreach($proofs as $proof){
        [$r]=\Kanboard\Plugin\FamilyHub\Model\NativeCryptoCodec::decode($proof);
        $batch=$batch??$r['batchId'];
        $hash=\Kanboard\Plugin\FamilyHub\Model\NativeCryptoV2Codec::hash((object)$proof);
        $digests[]=$hash;$groups[$r['scopeId'].':'.$r['domain']][]=$hash;
    }
    sort($digests,SORT_STRING);$projection=[];
    foreach($groups as $group=>$hashes){sort($hashes,SORT_STRING);$projection[]=['token'=>hash('sha256',$batch.':'.$group),'recordDigests'=>$hashes];}
    usort($projection,fn($a,$b)=>strcmp($a['token'],$b['token']));
    $commitment=inner2(['version'=>2,'operation'=>'crypto2.batchCommitment','serverId'=>$u['serverId'],'accountId'=>$u['user']['accountId'],'deviceId'=>$u['device']['id'],'batchId'=>$batch,'recordDigests'=>$digests,'projectionGroups'=>$projection],"JivieE2EE/batch/v2\n",$key);
    return content2('crypto2.records.batch',['batchId'=>$batch,'records'=>$proofs,'commitment'=>$commitment,'exportBindings'=>$bindings],$u,$key);
}

$source=row2($newId,$sourceHead,$fresh,$freshKeys,null,'paymentEvent');
$sourceProof=inner2($source,"JivieE2EE/record/v2\n",$freshKeys);
$sourceHash=\Kanboard\Plugin\FamilyHub\Model\NativeCryptoV2Codec::hash((object)$sourceProof);
$futureNonce=uid();
$futureBody=$offerBody;
$futureBody['purpose']='paymentSource';
$futureBody['permittedFields']=\Kanboard\Plugin\FamilyHub\Model\NativeCryptoExportV2::FIELDS['paymentSource'];
$futureBody['sourceRevision']=1;$futureBody['sourceRecordProofHash']=$sourceHash;
$futureBody['disclosureHash']=bin2hex(random_bytes(32));
$futureBody['subjectToken']=hash('sha256',"JivieExportSubject/v2\n".\Kanboard\Plugin\FamilyHub\Model\NativeCryptoCodec::canonical((object)['version'=>2,'serverId'=>$fresh['serverId'],'scopeId'=>$child['id'],'purpose'=>'paymentSource','sourceScopeToken'=>$scopeToken,'sourceId'=>$source['id'],'subjectNonce'=>$futureNonce]));
$futureRequest=content2('crypto2.exports.propose',['sourceScopeId'=>$newId,'sourceId'=>$source['id'],'subjectNonce'=>$futureNonce,'offerProof'=>inner2($futureBody,"JivieE2EE/exportOffer/v2\n",$freshKeys),'sourceProof'=>$sourceProof],$fresh,$freshKeys);
$futureOffer=call('crypto2.exports.propose',$futureRequest,$fresh);
ck(!q('SELECT id FROM familyhub_crypto_records WHERE scope_id=? AND id=?',[$newId,$source['id']]),'future payment offer creates no business record or applied source');
ck(call('crypto2.exports.propose',$futureRequest,$fresh)===$futureOffer,'future offer lost ACK retains exact prepared proof without publishing');
$futureDelegate=$delegate;
$futureDelegate['delegationId']=uid();$futureDelegate['purpose']='paymentSource';
$futureDelegate['offerHash']=$futureOffer['offerHash'];$futureDelegate['subjectToken']=$futureBody['subjectToken'];
$futureDelegate['permittedFields']=$futureBody['permittedFields'];$futureDelegate['bridgeRecipient']=null;
$futureDelegation=send2('crypto2.exports.delegate',$futureDelegate,$fresh,$freshKeys);
$target=row2($child['id'],$childHead,$fresh,$freshKeys,null,'cashMovement');$target['batchId']=$source['batchId'];
$certificate=$futureBody;$certificate['operation']='crypto2.exports.certificate';
$certificate['offerHash']=$futureOffer['offerHash'];$certificate['delegationProofHash']=$futureDelegation['delegationHash'];$certificate['bridge']=null;
$certificate['batchContext']=['batchId'=>$source['batchId'],'sourceOperationId'=>$source['operationId'],'sourceExpectedRevision'=>0,'targetOperationId'=>$target['operationId'],'targetExpectedRevision'=>0,'targetId'=>$target['id'],'targetIdentity'=>$target['metadata']['identity'],'targetMembershipHeadHash'=>$target['membershipHeadHash']];
$certificateProof=inner2($certificate,"JivieE2EE/scopedExport/v2\n",$freshKeys);
deny(fn()=>send2('crypto2.exports.certify',['offerHash'=>$futureOffer['offerHash'],'delegationHash'=>$futureDelegation['delegationHash'],'sourceRevision'=>1,'sourceRecordProofHash'=>$sourceHash,'certificateProof'=>$certificateProof],$fresh,$freshKeys),'crypto_export_batch_required','future certificate cannot publish separately from atomic source and cash');
$targetProof=inner2($target,"JivieE2EE/record/v2\n",$freshKeys);
$binding=['sourceScopeId'=>$newId,'sourceId'=>$source['id'],'sourceRecordProofHash'=>$sourceHash,'targetScopeId'=>$child['id'],'targetId'=>$target['id'],'delegationHash'=>$futureDelegation['delegationHash'],'certificateProof'=>$certificateProof];
foreach(['batchId','sourceOperationId','targetId','targetMembershipHeadHash'] as $field){
    $bad=$certificate;$bad['batchContext'][$field]=$field==='targetMembershipHeadHash'?str_repeat('f',64):uid();
    $badBinding=$binding;$badBinding['certificateProof']=inner2($bad,"JivieE2EE/scopedExport/v2\n",$freshKeys);
    deny(fn()=>call('crypto2.records.batch',exactExportBatch([$sourceProof,$targetProof],[$badBinding],$fresh,$freshKeys),$fresh),'crypto_export_batch_binding','swapped '.$field.' rejects entire private compound');
}
ck(!q('SELECT id FROM familyhub_crypto_records WHERE (scope_id=? AND id=?) OR (scope_id=? AND id=?)',[$newId,$source['id'],$child['id'],$target['id']]),'rejected export binding leaves zero source and target writes');
$wrongHash=$binding;$wrongHash['sourceRecordProofHash']=str_repeat('c',64);
deny(fn()=>call('crypto2.records.batch',exactExportBatch([$sourceProof,$targetProof],[$wrongHash],$fresh,$freshKeys),$fresh),'crypto_export_batch_binding','substituted source hash cannot select another signed source');
$wrongIssuer=$binding;$wrongIssuer['certificateProof']=inner2($certificate,"JivieE2EE/scopedExport/v2\n",keys());
deny(fn()=>call('crypto2.records.batch',exactExportBatch([$sourceProof,$targetProof],[$wrongIssuer],$fresh,$freshKeys),$fresh),'crypto_signature_invalid','foreign issuer cannot authorize private compound cash');
q('UPDATE familyhub_crypto_export_offers_v2 SET expires_at=? WHERE hash=?',[time()-1,$futureOffer['offerHash']]);
deny(fn()=>call('crypto2.records.batch',exactExportBatch([$sourceProof,$targetProof],[$binding],$fresh,$freshKeys),$fresh),'crypto_export_offer_expired','expired future offer leaves entire source and target pending');
q('UPDATE familyhub_crypto_export_offers_v2 SET expires_at=? WHERE hash=?',[time()+1800,$futureOffer['offerHash']]);
$beforeCertificates=count(q('SELECT hash FROM familyhub_crypto_export_certificates_v2'));
$batchRequest=exactExportBatch([$sourceProof,$targetProof],[$binding],$fresh,$freshKeys);
$applied=call('crypto2.records.batch',$batchRequest,$fresh);
ck(count($applied['records'])===2&&$applied['status']==='applied','brand-new source and private target certificate commit atomically');
q('UPDATE familyhub_crypto_export_offers_v2 SET expires_at=? WHERE hash=?',[time()-1,$futureOffer['offerHash']]);
ck(call('crypto2.records.batch',$batchRequest,$fresh)===$applied&&count(q('SELECT hash FROM familyhub_crypto_export_certificates_v2'))===$beforeCertificates+1,'compound lost ACK adds neither certificate nor record twice');
deny(fn()=>call('crypto2.records.batch',exactExportBatch([$sourceProof,$targetProof],[$binding],$fresh,$freshKeys),$fresh),'conflict','fresh request cannot reuse a now stale source CAS');
ck((int)q('SELECT revision FROM familyhub_crypto_records WHERE scope_id=? AND id=?',[$child['id'],$target['id']])[0]['revision']===1,'stale source conflict leaves target revision unchanged');
$pull=call('crypto2.records.pull',['scopeId'=>$child['id'],'domain'=>'finance','accessRevision'=>$child['accessRevision'],'cursor'=>0],$fresh);
$publicWire=json_encode($pull,JSON_THROW_ON_ERROR);
ck(!str_contains($publicWire,$newId)&&!str_contains($publicWire,$source['id'])&&!str_contains($publicWire,'exportBindings'),'target pull exposes own proof and opaque digests without private source IDs or dispatch');
deny(fn()=>send2('crypto2.exports.propose',['sourceScopeId'=>$newId,'sourceId'=>$source['id'],'subjectNonce'=>$futureNonce,'offerProof'=>inner2($futureBody,"JivieE2EE/exportOffer/v2\n",$freshKeys),'sourceProof'=>$sourceProof],$fresh,$freshKeys),'crypto_export_future_source_invalid','future-only offer refuses a source already published');
echo 'Crypto2 same-batch export integration: '.$checks.' checks PASS'.PHP_EOL;
