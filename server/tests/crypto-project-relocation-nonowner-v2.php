<?php
/** Exact nonowner policy3 manager; preparation/shadow, not final publication. */
require __DIR__.'/crypto2-invitation-integration.php';
require __DIR__.'/crypto2-record-helpers.php';
use Kanboard\Plugin\FamilyHub\Model\NativeCryptoProjectRelocationV2 as Relocation;
use Kanboard\Plugin\FamilyHub\Model\NativeCryptoProjectRelocationCodecV2 as R;
use Kanboard\Plugin\FamilyHub\Model\NativeCryptoLifecycleV2;
use Kanboard\Plugin\FamilyHub\Model\NativeCryptoCodec;

$sourceId=$shared['id'];$sourceHead=call('crypto2.scope.headGet',['scopeId'=>$sourceId],$recipient);
$catalog=call('crypto2.scopes.catalog',[],$recipient)['scopes'];$source=array_values(array_filter($catalog,fn($s)=>$s['id']===$sourceId))[0];
// The production schema is created by the imported integration fixture.
// This preparation-only fixture binds the real reserved parent metadata proof;
// generation 0 describes its initial opaque topology baseline, not a final move.
$metadataCanonical=\Kanboard\Plugin\FamilyHub\Model\NativeCryptoReservedRecordV2::derive($recipient['serverId'],$sourceId,'scopeMetadata');
$metadata=row2($sourceId,$sourceHead,$recipient,$recipientKey,$metadataCanonical,'scopeMetadata');
call('crypto2.records.batch',batch2([$metadata],$recipient,$recipientKey),$recipient);
$metadataProof=json_decode(q('SELECT authorization FROM familyhub_crypto_records WHERE scope_id=? AND id=?',[$sourceId,$metadata['id']])[0]['authorization'],true)['recordProof'];
$project=row2($sourceId,$sourceHead,$recipient,$recipientKey,null,'project');
$task=row2($sourceId,$sourceHead,$recipient,$recipientKey,null,'task',0,null,[['scopeId'=>$sourceId,'id'=>$project['id']]]);
$account=row2($sourceId,$sourceHead,$recipient,$recipientKey,null,'financeAccount');
$entry=row2($sourceId,$sourceHead,$recipient,$recipientKey,null,'financeEntry',0,null,[['scopeId'=>$sourceId,'id'=>$task['id']],['scopeId'=>$sourceId,'id'=>$account['id']]]);
call('crypto2.records.batch',batch2([$project,$task,$account,$entry],$recipient,$recipientKey),$recipient);
$descriptors=[];
foreach([$project,$task,$account,$entry] as $record){$saved=q('SELECT authorization FROM familyhub_crypto_records WHERE scope_id=? AND id=?',[$sourceId,$record['id']])[0];$proof=json_decode($saved['authorization'],true)['recordProof'];$descriptors[]=['id'=>$record['metadata']['identity']['canonicalId'],'wireId'=>$record['id'],'type'=>$record['type'],'domain'=>$record['domain'],'revision'=>1,'logicalRevision'=>1,'recordProofHash'=>R::hash($proof),'deleted'=>false];}
usort($descriptors,fn($a,$b)=>strcmp($a['wireId'],$b['wireId']));
$state=call('crypto2.account.status',[],$recipient);$target=$project['metadata']['identity']['canonicalId'];$action=uid();$request=uid();
$plan=['version'=>2,'serverId'=>$recipient['serverId'],'actionId'=>$action,'requestId'=>$request,'accountId'=>$recipient['user']['accountId'],'deviceId'=>$recipient['device']['id'],'authorDirectoryHeadHash'=>$state['headHash'],'sourceScopeId'=>$sourceId,'targetScopeId'=>$target,'projectId'=>$target,'projectWireId'=>$project['id'],'sourceHeadHash'=>$sourceHead['headHash'],'sourceAccessRevision'=>$source['accessRevision'],'sourceLifecycleHash'=>(new NativeCryptoLifecycleV2($container))->closingHash($sourceId),'sourceGraphRoot'=>R::graphRoot($descriptors),'sourceGraphCount'=>count($descriptors),'sourceAuditRoot'=>R::digestRoot('audit',[]),'sourceAuditCount'=>0,'parentMetadataProofHash'=>R::hash($metadataProof),'parentTopologyGeneration'=>0,'targetOwnerAccountId'=>$fresh['user']['accountId'],'targetParentScopeToken'=>(new NativeCryptoLifecycleV2($container))->parentToken($target,$sourceId)];
$planProof=inner2($plan,Relocation::PLAN_DOMAIN,$recipientKey);$outer=content2('crypto2.projectRelocation.prepare',['planProof'=>$planProof],$recipient,$recipientKey,$request);[$command]=NativeCryptoCodec::decode($outer);
$helper=new Relocation($container,'Bearer '.$recipient['token']);$actor=(new ReflectionMethod($helper,'actor'))->invoke($helper);$key=$recipientKey['signPublic'];
$prepared=$helper->prepare(['planProof'=>$planProof],$actor,$outer,$command,$key);$p=['actionId'=>$action,'planHash'=>$prepared['planHash']];
$helper->sources($p+['descriptors'=>$descriptors],$actor);
ck(count($helper->validateSources($action,$actor)['descriptors'])===4,'nonowner current policy3 manager with source financeWRITE may prepare exact finite financial project');
$origin=inner2(['version'=>2,'operation'=>'crypto2.scope.origin','serverId'=>$recipient['serverId'],'scopeId'=>$target,'kind'=>'project','accessPolicyVersion'=>3,'parentScopeToken'=>$plan['targetParentScopeToken'],'requestId'=>$request,'accountId'=>$recipient['user']['accountId'],'deviceId'=>$recipient['device']['id'],'authorDirectoryHeadHash'=>$state['headHash'],'projectRelocation'=>['version'=>2,'actionId'=>$action,'planHash'=>$prepared['planHash']]],"JivieE2EE/scopeOrigin/v2\n",$recipientKey);
$helper->targetOrigin($p+['originProof'=>$origin],$actor,$key);
$pdo->beginTransaction();
try{
    $preview=$helper->targetPreview($p,$actor);$members=$preview['scope']['members'];
    ck($preview['scope']['role']==='member'&&array_values(array_filter($members,fn($m)=>$m['accountId']===$fresh['user']['accountId']))[0]['role']==='owner','target retains original parent owner and actor remains inherited member');
    ck(array_values(array_filter($members,fn($m)=>$m['accountId']===$recipient['user']['accountId']))[0]['financeRole']==='write','actual policy3 resolver retains effective target WRITE without inventing a grant');
    $targetBody=candidate2($shared,$state);$targetBody['scopeId']=$target;$targetBody['initialLifecycleHash']=$preview['lifecycle']['initialLifecycleHash'];$targetBody['accessRevision']=$preview['scope']['accessRevision'];$targetBody['expectedAccessRevision']=$preview['scope']['expectedAccessRevision'];$targetBody['accessBasis']=$preview['scope']['accessBasis'];$targetBody['members']=$sourceHead['payload']['members'];
    $targetProof=content2('crypto2.scope.headPut',$targetBody,$recipient,$recipientKey);
    $staged=$helper->targetCommand($p+['authorization'=>$targetProof],$actor,$command,$key);
    ck($staged['result']['state']==='pendingKeys','nonowner genesis runs normal head membership/finance parity under closed relocation context');
    ck(q('SELECT id FROM familyhub_scopes WHERE id=?',[$target])===[],'nonowner target staging remains absent from normal SQL scopes');
    $restore=new ReflectionMethod($helper,'restoreTarget');$row=q('SELECT * FROM familyhub_crypto_project_relocations_v2 WHERE action_id=?',[$action])[0];
    $pdo->exec('SAVEPOINT inspect_target_acl');
    try{$restore->invoke($helper,$row,$plan,$actor);ck(q('SELECT account_id FROM familyhub_finance_grants WHERE scope_id=? AND account_id=?',[$target,$recipient['user']['accountId']])===[],'no raw target finance grant is manufactured for acting manager');$api=new \Kanboard\Plugin\FamilyHub\Model\NativeCryptoScopeV2($container,'Bearer '.$recipient['token']);deny(fn()=>$api->write('crypto2.scope.headPut',$targetBody,$actor,$targetProof),'crypto_project_relocation_required','normal route cannot consume a staged marked genesis despite valid source management');}finally{$pdo->exec('ROLLBACK TO SAVEPOINT inspect_target_acl');$pdo->exec('RELEASE SAVEPOINT inspect_target_acl');}
    $pdo->commit();
}catch(Throwable $error){if($pdo->inTransaction())$pdo->rollBack();throw $error;}
q('UPDATE familyhub_finance_policy SET enabled=0 WHERE scope_id=?',[$sourceId]);
deny(fn()=>$helper->validateSources($action,$actor),'finance_forbidden','content management and old DEK never substitute for current source financeWRITE');
echo 'Project relocation nonowner2 '.$checks.' cumulative checks PASS'.PHP_EOL;
