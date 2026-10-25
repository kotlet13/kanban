<?php
/** New SQL admission/coverage seams only. Authority fixtures are explicit stubs;
 * this does not claim signed HTTP, encrypted field binding or native proof. */
require __DIR__.'/account-changes-fixture.php';
use Kanboard\Plugin\FamilyHub\Model\NativeCryptoRecordPolicyV1;
use Kanboard\Plugin\FamilyHub\Model\NativeCryptoScopeV2;
use Kanboard\Plugin\FamilyHub\Model\NativeCryptoCodec;
use Kanboard\Plugin\FamilyHub\Model\NativeError;
$owner=['user'=>['id'=>1,'account_id'=>id(1)],'device'=>['id'=>id(101)]];
$member=['user'=>['id'=>2,'account_id'=>id(2)],'device'=>['id'=>id(102)]];
class CoveragePolicy extends NativeCryptoRecordPolicyV1 {
    protected function owner($p,$actor){
        if($actor['user']['account_id']!==id(1))throw new NativeError('crypto_record_policy_owner_required',403);
        return [['id'=>$p['scopeId'],'role'=>'owner','kind'=>'project'],['head_hash'=>$p['membershipHeadHash']],new NativeCryptoScopeV2($this->container)];
    }
    public function run($op,$p,$actor){return $this->transaction(fn()=> $this->write('crypto2.scope.recordPolicy.'.$op,$p,$actor,['fixture'=>'prevalidated-owner-authority']));}
}
$policy=new CoveragePolicy(['db'=>$db]);$f=['content'=>str_repeat('a',64),'assignment'=>str_repeat('b',64),'checked'=>str_repeat('c',64)];
$metadata=['references'=>[],'uniqueRefs'=>[],'blobIds'=>[],'identity'=>['sourceKind'=>'records','canonicalId'=>id(10)],'notificationState'=>['assigneeAccountIds'=>[id(2)],'groupTargetId'=>null]];
$entries=[];
foreach([10=>'task',11=>'shoppingItem'] as $n=>$type){
    $hash=hash('sha256','Synthetic proof '.$n);$entry=['id'=>id($n),'domain'=>'content','type'=>$type,'recordProofHash'=>$hash,'createdByAccountId'=>id(1),'fieldCommitments'=>$f,'policyEnvelopeBase64'=>base64_encode(str_repeat('E',48))];$entries[]=$entry;
    sql('INSERT INTO familyhub_crypto_records VALUES(?,?,?,?,?,?,?,?,?,?)',[id(3),id($n),$type,1,0,$n,1,'CIPHERTEXT_SENTINEL',json_encode($metadata),'{}']);
    sql('INSERT INTO familyhub_crypto_record_history VALUES(?,?,?,?,?,?,?,?,?)',[id(3),id($n),1,$n,1,'content',$hash,'PROOF_SENTINEL','COMMITMENT_SENTINEL']);
}
$common=['scopeId'=>id(3),'membershipHeadHash'=>str_repeat('d',64),'accessRevision'=>0,'baselineId'=>id(90)];
$prepare=$common+['policyVersion'=>1,'expectedContentSequence'=>0,'expectedFinanceSequence'=>0];
deny(fn()=> $policy->run('prepare',$prepare,$member),'crypto_record_policy_owner_required','nonowner cannot prepare authoritative baseline');
$policy->run('prepare',$prepare,$owner);ck(!$policy->active(id(3)),'preparing baseline leaves original admission active');
$bad=$entries[0];$bad['recordProofHash']=str_repeat('f',64);
deny(fn()=> $policy->run('stage',$common+['records'=>[$bad]],$owner),'crypto_record_policy_baseline_changed','stage binds exact current record proof hash');
ck((int)sql('SELECT COUNT(*) FROM familyhub_crypto_record_policy_entries_v1')->fetchColumn()===0,'rejected stage leaves no durable partial coverage');
$policy->run('stage',$common+['records'=>[$entries[0]]],$owner);
$rootFor=function($items){usort($items,fn($a,$b)=>strcmp($a['id'],$b['id']));$h=hash_init('sha256');hash_update($h,"JivieRecordPolicyBaseline/v1\n");foreach($items as $item)hash_update($h,hash('sha256',"JivieRecordPolicyBaselineLeaf/v1\n".NativeCryptoCodec::canonical((object)$item))."\n");return hash_final($h);};
$activate=$common+['policyVersion'=>1,'baselineCount'=>2,'baselineRoot'=>$rootFor($entries)];
deny(fn()=> $policy->run('activate',$activate,$owner),'crypto_record_policy_baseline_incomplete','partial baseline cannot switch admission');
ck(!$policy->active(id(3)),'failed activation preserves old policy and existing records');
$policy->run('stage',$common+['records'=>[$entries[1]]],$owner);
$prior=sql('SELECT id,envelope,authorization FROM familyhub_crypto_records ORDER BY id')->fetchAll(\PDO::FETCH_ASSOC);
$policy->run('activate',$activate,$owner);
ck((int)$policy->active(id(3))['policy_version']===1,'complete exact baseline activates policy atomically');
ck(sql('SELECT id,envelope,authorization FROM familyhub_crypto_records ORDER BY id')->fetchAll(\PDO::FETCH_ASSOC)===$prior,'activation preserves every original ciphertext and proof byte');
$old=['metadata'=>json_encode($metadata)];$scope=['id'=>id(3),'role'=>'member','kind'=>'project'];
$record=['scopeId'=>id(3),'id'=>id(10),'type'=>'task','domain'=>'content','contentContract'=>7,'deleted'=>false,'previousRecordHash'=>$entries[0]['recordProofHash'],'metadata'=>$metadata+['recordPolicy'=>['version'=>1,'createdByAccountId'=>id(1),'operation'=>'edit','fieldCommitments'=>$f]]];
$record['metadata']['recordPolicy']['fieldCommitments']['content']=str_repeat('e',64);
$policy->admit($record,$old,$scope,$member);ck(true,'accepted predecessor assignee can edit task with stable assignment');
$viewer=$scope;$viewer['role']='viewer';$policy->admit($record,$old,$viewer,$member);ck(true,'record admission includes a current reader who is the accepted task assignee');
$bad=$record;$bad['metadata']['recordPolicy']['fieldCommitments']['assignment']=str_repeat('f',64);
deny(fn()=> $policy->admit($bad,$old,$scope,$member),'record_assignment_forbidden','task assignee cannot change assignment commitment');
$bad=$record;$bad['metadata']['notificationState']['assigneeAccountIds']=[];
deny(fn()=> $policy->admit($bad,$old,$scope,$member),'record_assignment_forbidden','task assignee cannot change public accepted assignment');
$bad=$record;$bad['metadata']['recordPolicy']['createdByAccountId']=id(2);
deny(fn()=> $policy->admit($bad,$old,$scope,$member),'crypto_record_policy_creator','updater cannot replace original creator with itself');
$unassigned=$old;$m=$metadata;$m['notificationState']['assigneeAccountIds']=[];$unassigned['metadata']=json_encode($m);
deny(fn()=> $policy->admit($record,$unassigned,$scope,$member),'record_edit_forbidden','self assignment in new request grants no task edit');
$bad=$record;$bad['contentContract']=6;
deny(fn()=> $policy->admit($bad,$old,$scope,$member),'crypto_upgrade_required','old broad contract fails clearly only after policy activation');
$deleted=$record;$deleted['deleted']=true;$deleted['metadata']['recordPolicy']['operation']='delete';$deleted['metadata']['recordPolicy']['fieldCommitments']=$f;
deny(fn()=> $policy->admit($deleted,$old,$scope,$member),'record_delete_forbidden','assignee task edit does not grant delete');
$ownerScope=$scope;$ownerScope['role']='owner';$policy->admit($deleted,$old,$ownerScope,$owner);ck(true,'scope owner may delete while preserving author and field commitments');
$shopping=$record;$shopping['id']=id(11);$shopping['type']='shoppingItem';$shopping['previousRecordHash']=$entries[1]['recordProofHash'];$shopping['metadata']['recordPolicy']['operation']='shoppingCheck';$shopping['metadata']['recordPolicy']['fieldCommitments']=$f;$shopping['metadata']['recordPolicy']['fieldCommitments']['checked']=str_repeat('e',64);
$policy->admit($shopping,$old,$viewer,$member);ck(true,'all current readers may submit the shopping checkbox operation');
$bad=$shopping;$bad['metadata']['recordPolicy']['fieldCommitments']['content']=str_repeat('e',64);
deny(fn()=> $policy->admit($bad,$old,$scope,$member),'record_edit_forbidden','shopping checkbox cannot alter title quantity or other content commitment');
$bad=$shopping;$bad['metadata']['references']=[['scopeId'=>id(3),'id'=>id(99)]];
deny(fn()=> $policy->admit($bad,$old,$scope,$member),'record_edit_forbidden','checkbox-only operation cannot reroute server references');
$new=$record;$new['id']=id(20);$new['metadata']['recordPolicy']['operation']='create';$new['metadata']['recordPolicy']['createdByAccountId']=id(2);
$policy->admit($new,null,$scope,$member);ck(true,'new ordinary record binds creator to actual authenticated account');
deny(fn()=> $policy->admit($new,null,$viewer,$member),'record_edit_forbidden','viewer exception does not grant new record creation');
foreach(['scopeMetadata','financeAccountChoice','taskDerivationIntent','taskDerivationResolution','paymentEvent','paymentProjection','cashMovement','notification','reminder'] as $type){$internal=$record;$internal['type']=$type;unset($internal['metadata']['recordPolicy']);$internal['contentContract']=6;$policy->admit($internal,$old,$scope,$member);}
ck(true,'explicit technical record types retain their original purpose and finance guards');
$unknown=$record;$unknown['type']='futureUnreviewedType';deny(fn()=> $policy->admit($unknown,$old,$scope,$member),'crypto_record_policy_type','unknown future type receives no implicit policy bypass');
$foreign=$metadata;$foreign['references']=[['scopeId'=>id(3),'id'=>id(60)]];$foreign['recordPolicy']=['version'=>1,'createdByAccountId'=>id(2),'operation'=>'edit','fieldCommitments'=>$f];
sql('UPDATE familyhub_crypto_records SET metadata=? WHERE scope_id=? AND id=?',[json_encode($foreign),id(3),id(10)]);
$parent=$deleted;$parent['id']=id(60);$parent['type']='shoppingList';
deny(fn()=> $policy->admitCascade($parent,$scope,$owner),'record_delete_forbidden','author cannot cascade-delete a parent containing a foreign accepted child');
$policy->admitCascade($parent,$ownerScope,$owner);ck(true,'real scope owner may delete complete unit with foreign children');
$empty=$common;$empty['scopeId']=id(4);$empty['baselineId']=id(91);sql('INSERT INTO familyhub_crypto_domain_cursors VALUES(?,?,0)',[id(4),'content']);sql('INSERT INTO familyhub_crypto_domain_cursors VALUES(?,?,0)',[id(4),'finance']);
$policy->run('prepare',$empty+['policyVersion'=>1,'expectedContentSequence'=>0,'expectedFinanceSequence'=>0],$owner);
$policy->run('activate',$empty+['policyVersion'=>1,'baselineCount'=>0,'baselineRoot'=>$rootFor([])],$owner);ck((bool)$policy->active(id(4)),'new empty scope activates with exact zero coverage');
echo json_encode(['test'=>'crypto-record-policy-admission','status'=>'pass','checks'=>$checks,'fixture'=>'isolated-memory-sqlite','authority'=>'explicit prevalidated owner seam','http'=>false,'proofVerification'=>false]).PHP_EOL;
