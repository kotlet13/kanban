<?php
/** Preparatory helper only; not a final relocation/normal repository claim. */
require __DIR__.'/crypto2-scope-integration.php';
require __DIR__.'/crypto2-record-helpers.php';
use Kanboard\Plugin\FamilyHub\Model\NativeCryptoProjectRelocationV2 as Relocation;
use Kanboard\Plugin\FamilyHub\Model\NativeCryptoProjectRelocationCodecV2 as R;
use Kanboard\Plugin\FamilyHub\Model\NativeCryptoCodec;
use Kanboard\Plugin\FamilyHub\Model\NativeCryptoLifecycleV2;

$source=send2('crypto2.scope.create',['id'=>uid(),'kind'=>'household'],$fresh,$freshKeys)['scope'];
$state=call('crypto2.account.status',[],$fresh);
$body=candidate2($source,$state);$pending=send2('crypto2.scope.headPut',$body,$fresh,$freshKeys);
$head=call('crypto2.scope.headGet',['scopeId'=>$source['id'],'headHash'=>$pending['headHash']],$fresh);
grants2($head,[$head],$fresh,$freshKeys,$root,$epoch);
$manifest=call('crypto2.grants.manifest',['scopeId'=>$source['id'],'headHash'=>$head['headHash']],$fresh);
send2('crypto2.scope.activate',['scopeId'=>$source['id'],'headHash'=>$head['headHash'],'grantManifestHash'=>$manifest['grantManifestHash'],'authorDirectoryHeadHash'=>$state['headHash']],$fresh,$freshKeys);
// The production schema is created by the imported integration fixture.
// Keep the parent metadata outside the moved graph and bind its exact proof.
$metadataCanonical=\Kanboard\Plugin\FamilyHub\Model\NativeCryptoReservedRecordV2::derive($fresh['serverId'],$source['id'],'scopeMetadata');
$metadata=row2($source['id'],$head,$fresh,$freshKeys,$metadataCanonical,'scopeMetadata');
call('crypto2.records.batch',batch2([$metadata],$fresh,$freshKeys),$fresh);
$metadataProof=json_decode(q('SELECT authorization FROM familyhub_crypto_records WHERE scope_id=? AND id=?',[$source['id'],$metadata['id']])[0]['authorization'],true)['recordProof'];
$project=row2($source['id'],$head,$fresh,$freshKeys,null,'project');
call('crypto2.records.batch',batch2([$project],$fresh,$freshKeys),$fresh);
$records=[$project];
for($n=0;$n<52;$n++)$records[]=row2($source['id'],$head,$fresh,$freshKeys,null,'task',0,null,[['scopeId'=>$source['id'],'id'=>$project['id']]]);
foreach(array_chunk(array_slice($records,1),32) as $group)call('crypto2.records.batch',batch2($group,$fresh,$freshKeys),$fresh);
$descriptors=[];
foreach($records as $record){
    $saved=q('SELECT * FROM familyhub_crypto_records WHERE scope_id=? AND id=?',[$source['id'],$record['id']])[0];
    $proof=json_decode($saved['authorization'],true)['recordProof'];
    $descriptors[]=['id'=>$record['metadata']['identity']['canonicalId'],'wireId'=>$record['id'],'type'=>$record['type'],'domain'=>$record['domain'],'revision'=>1,'logicalRevision'=>1,'recordProofHash'=>R::hash($proof),'deleted'=>false];
}
usort($descriptors,fn($a,$b)=>strcmp($a['wireId'],$b['wireId']));
$action=uid();$request=uid();$target=$project['metadata']['identity']['canonicalId'];
$plan=['version'=>2,'serverId'=>$fresh['serverId'],'actionId'=>$action,'requestId'=>$request,'accountId'=>$fresh['user']['accountId'],'deviceId'=>$fresh['device']['id'],'authorDirectoryHeadHash'=>$state['headHash'],'sourceScopeId'=>$source['id'],'targetScopeId'=>$target,'projectId'=>$target,'projectWireId'=>$project['id'],'sourceHeadHash'=>$head['headHash'],'sourceAccessRevision'=>$source['accessRevision'],'sourceLifecycleHash'=>(new NativeCryptoLifecycleV2($container))->closingHash($source['id']),'sourceGraphRoot'=>R::graphRoot($descriptors),'sourceGraphCount'=>count($descriptors),'sourceAuditRoot'=>R::digestRoot('audit',[]),'sourceAuditCount'=>0,'parentMetadataProofHash'=>R::hash($metadataProof),'parentTopologyGeneration'=>0,'targetOwnerAccountId'=>$fresh['user']['accountId'],'targetParentScopeToken'=>(new NativeCryptoLifecycleV2($container))->parentToken($target,$source['id'])];
$planProof=inner2($plan,Relocation::PLAN_DOMAIN,$freshKeys);
$outer=content2('crypto2.projectRelocation.prepare',['planProof'=>$planProof],$fresh,$freshKeys,$request);[$command]=NativeCryptoCodec::decode($outer);
$helper=new Relocation($container,'Bearer '.$fresh['token']);$actor=(new ReflectionMethod($helper,'actor'))->invoke($helper);
$before=q('SELECT id,revision,authorization FROM familyhub_crypto_records WHERE scope_id=? ORDER BY id',[$source['id']]);
$prepared=$helper->prepare(['planProof'=>$planProof],$actor,$outer,$command,base64_encode(sodium_crypto_sign_publickey_from_secretkey($freshKeys['sign'])));
ck($prepared['sourceGraphCount']===53,'exact manager plan handles a graph larger than one batch without publishing target');
$params=['actionId'=>$action,'planHash'=>$prepared['planHash']];
$helper->sources($params+['descriptors'=>array_slice($descriptors,0,32)],$actor);
deny(fn()=>$helper->validateSources($action,$actor),'crypto_relocation_source_incomplete','partial source pages cannot become a complete graph');
$tail=$params+['descriptors'=>array_slice($descriptors,32)];$saved=$helper->sources($tail,$actor);
ck($saved['sourceCount']===53&&$helper->sources($tail,$actor)===$saved,'source descriptor exact retries are immutable and do not duplicate rows');
ck(count($helper->validateSources($action,$actor)['descriptors'])===53,'complete sorted source graph reconstructs exact signed root');
ck(q('SELECT id FROM familyhub_scopes WHERE id=?',[$target])===[]&&q('SELECT scope_id FROM familyhub_crypto_scope_state WHERE scope_id=?',[$target])===[],'preparation never publishes an empty target scope or active target head');
$origin=inner2(['version'=>2,'operation'=>'crypto2.scope.origin','serverId'=>$fresh['serverId'],'scopeId'=>$target,'kind'=>'project','accessPolicyVersion'=>3,'parentScopeToken'=>$plan['targetParentScopeToken'],'requestId'=>$request,'accountId'=>$fresh['user']['accountId'],'deviceId'=>$fresh['device']['id'],'authorDirectoryHeadHash'=>$state['headHash'],'projectRelocation'=>['version'=>2,'actionId'=>$action,'planHash'=>$prepared['planHash']]],"JivieE2EE/scopeOrigin/v2\n",$freshKeys);
$key=base64_encode(sodium_crypto_sign_publickey_from_secretkey($freshKeys['sign']));
$helper->targetOrigin($params+['originProof'=>$origin],$actor,$key);
$pdo=$container['db']->getConnection();$pdo->beginTransaction();
try{
    $preview=$helper->targetPreview($params,$actor);
    $targetBody=candidate2($source,$state);$targetBody['scopeId']=$target;$targetBody['initialLifecycleHash']=$preview['lifecycle']['initialLifecycleHash'];$targetBody['accessRevision']=$preview['scope']['accessRevision'];$targetBody['expectedAccessRevision']=$preview['scope']['expectedAccessRevision'];$targetBody['accessBasis']=$preview['scope']['accessBasis'];
    $targetCommand=content2('crypto2.scope.headPut',$targetBody,$fresh,$freshKeys);
    $staged=$helper->targetCommand($params+['authorization'=>$targetCommand],$actor,$command,$key);
    ck($staged['candidate']&&$staged['result']['state']==='pendingKeys','savepoint target uses normal signed head validator under exact relocation context');
    foreach(['content','finance'] as $domain){
        $recipients=[['recipientKind'=>'device','recipientId'=>$fresh['device']['id'],'publicKeyBase64'=>$freshKeys['boxPublic'],'sealedEnvelopeBase64'=>base64_encode(random_bytes(96))],['recipientKind'=>'recovery','recipientId'=>$epoch,'publicKeyBase64'=>$root['boxPublic'],'sealedEnvelopeBase64'=>base64_encode(random_bytes(96))]];
        $grant=content2('crypto2.grants.put',['scopeId'=>$target,'headHash'=>$staged['result']['headHash'],'keySourceHeadHash'=>$staged['result']['headHash'],'keyId'=>$targetBody['keyIds'][$domain],'accountId'=>$fresh['user']['accountId'],'domain'=>$domain,'epoch'=>1,'expectedGeneration'=>0,'recipients'=>$recipients],$fresh,$freshKeys);
        $grantParams=$params+['authorization'=>$grant];$firstGrant=$helper->targetCommand($grantParams,$actor,$command,$key);
        ck($helper->targetCommand($grantParams,$actor,$command,$key)===$firstGrant,'exact nested '.$domain.' grant lost ACK is stable without fabricated normal receipt');
    }
    $firstPreview=$helper->targetPreview($params,$actor);
    ck($helper->targetPreview($params,$actor)===$firstPreview&&$firstPreview['authorization']===$targetCommand&&$firstPreview['lifecycle']['initialLifecycleHash']===$preview['lifecycle']['initialLifecycleHash'],'reconstructed head grants lifecycle and access basis remain byte-identical across preview retries');
    ck(q('SELECT id FROM familyhub_scopes WHERE id=?',[$target])===[]&&q('SELECT scope_id FROM familyhub_crypto_scope_heads WHERE scope_id=?',[$target])===[],'successful target staging leaves no scope or head in normal storage');
    $changed=$targetBody;$changed['keyIds']['content']=uid();$changed['keyCommitments']['content']=hash('sha256',random_bytes(32));
    $changedProof=content2('crypto2.scope.headPut',$changed,$fresh,$freshKeys);
    deny(fn()=>$helper->targetCommand($params+['authorization'=>$changedProof],$actor,$command,$key),'crypto_relocation_target_immutable','different candidate cannot silently replace reviewed target genesis');
    ck(q('SELECT id FROM familyhub_scopes WHERE id=?',[$target])===[],'failed target validation also rolls every temporary target row back');
    $pdo->commit();
}catch(Throwable $error){if($pdo->inTransaction())$pdo->rollBack();throw $error;}
$outside=row2($source['id'],$head,$fresh,$freshKeys,null,'task',0,null,[['scopeId'=>$source['id'],'id'=>$project['id']]]);call('crypto2.records.batch',batch2([$outside],$fresh,$freshKeys),$fresh);
deny(fn()=>$helper->validateSources($action,$actor),'project_sharing_blocked','newly created outside dependant prevents final graph without silently moving it');
$cancel=$helper->cancel($params,$actor);
ck($cancel['sourceUnchanged']&&q('SELECT id,revision,authorization FROM familyhub_crypto_records WHERE scope_id=? AND id<>? ORDER BY id',[$source['id'],$outside['id']])===$before,'cancellation preserves all original source record bytes and revisions');
ck(q('SELECT id FROM familyhub_scopes WHERE id=?',[$target])===[],'cancel leaves no duplicate project scope');
$tag=['version'=>2,'actionId'=>$action,'planHash'=>$prepared['planHash'],'side'=>'source'];
$sourceTombstone=row2($source['id'],$head,$fresh,$freshKeys,$project['id'],'project',1,array_values(array_filter($descriptors,fn($d)=>$d['wireId']===$project['id']))[0]['recordProofHash'],[],[],true);
$sourceTombstone['metadata']['projectRelocation']=$tag;
deny(fn()=>call('crypto2.records.batch',batch2([$sourceTombstone],$fresh,$freshKeys),$fresh),'crypto_project_relocation_forbidden','normal batch cannot publish a signed staged source tombstone');
$targetCopy=row2($target,$head,$fresh,$freshKeys,null,'project');$targetCopy['metadata']['projectRelocation']=array_replace($tag,['side'=>'target']);
deny(fn()=>call('crypto2.records.batch',batch2([$targetCopy],$fresh,$freshKeys),$fresh),'scope_unavailable','normal batch cannot publish a staged target even if creator has source WRITE');
$ambiguous=$sourceTombstone;$ambiguous['metadata']['inlineDeletion']=['version'=>2,'actionId'=>$action,'planHash'=>$prepared['planHash']];
deny(fn()=>call('crypto2.records.batch',batch2([$ambiguous],$fresh,$freshKeys),$fresh),'crypto_relocation_tag','one proof cannot claim both deletion and relocation purposes');
$event=request2('crypto2.account.projectRelocation',['actionId'=>$action,'publicationRoot'=>str_repeat('2',64)],$fresh,$freshKeys,$state['snapshot'],$state);
deny(fn()=>call('crypto2.account.projectRelocation',$event,$fresh),'crypto_companion_only','dedicated publication event cannot be appended as a standalone RPC');
[$eventBody]=NativeCryptoCodec::decode($event);$directory=new \Kanboard\Plugin\FamilyHub\Model\NativeCryptoDirectoryV2($container);$current=$directory->current($fresh['user']['accountId']);
$directory->authorize($eventBody,$current);$reduced=$directory->reduce($eventBody,$current);
ck(NativeCryptoCodec::canonical((object)$reduced)===NativeCryptoCodec::canonical((object)$state['snapshot']),'dedicated event reducer preserves exact account snapshot and device capabilities');
$bad=$eventBody;$bad['payload']['sourceScopeId']=$source['id'];
deny(fn()=>$directory->reduce($bad,$current),'validation_error','publication account log cannot expose private source/target identifiers');
echo 'Project relocation prepare2 '.$checks.' cumulative checks PASS'.PHP_EOL;
