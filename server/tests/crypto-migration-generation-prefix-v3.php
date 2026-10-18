<?php
/** Focused generation signer regression, not full business-parity/cutover proof. */
require __DIR__.'/crypto2-scope-integration.php';
use Kanboard\Plugin\FamilyHub\Model\NativeCryptoMigrationGenerationV3 as Generation;
use Kanboard\Plugin\FamilyHub\Model\NativeCryptoCodec;
use Kanboard\Plugin\FamilyHub\Model\NativeCryptoDirectoryV2 as Directory;
use Kanboard\Plugin\FamilyHub\Model\NativeCryptoV2Codec as V2;

$account=$fresh['user']['accountId'];$sid=$space['id'];$migration=uid();$component=uid();$zero=str_repeat('0',64);
$current=call('crypto2.account.status',[],$fresh);
// The preceding scope suite produced genuine accepted generic metadata with no
// directory selector, and an exact signed proposal with an explicit selector.
$generic=null;
foreach(q('SELECT authorization FROM familyhub_crypto_receipts WHERE account_id=?',[$account]) as $r){
    $candidate=json_decode($r['authorization'],true,34,JSON_THROW_ON_ERROR);[$c]=NativeCryptoCodec::decode($candidate);
    if($c['operation']==='crypto2.scope.prepare'){$generic=$candidate;break;}
}
ck($generic!==null,'accepted generic metadata fixture has original signed bytes');
$explicit=$cleanup['authorization'];
q('INSERT INTO familyhub_crypto_migrations_v2 VALUES(?,?,?,?,?,?,?,?,?)',[$migration,$component,str_repeat('1',64),json_encode([$sid]),str_repeat('2',64),'verified',str_repeat('3',64),time(),time()]);
q('INSERT INTO familyhub_crypto_migration_portions_v2 VALUES(?,?,?,?,?,?,?,?)',[$migration,$account,json_encode([$sid]),'{}',str_repeat('4',64),'verified',null,null]);
// Accepted-artifact index fixture only: the new regression tests reconstruction
// and approval boundaries; it does not claim these rows are a full Capture3 run.
q('INSERT INTO familyhub_crypto_captures_v3(migration_id,account_id,capture_id,key_id,state,inventory_root,source_count,authorization) VALUES(?,?,?,?,?,?,?,?)',[$migration,$account,uid(),uid(),'sealed',str_repeat('5',64),0,json_encode($generic)]);
$publication=inner2(['version'=>3,'serverId'=>$fresh['serverId'],'migrationId'=>$migration,'componentId'=>$component,
    'componentCommitment'=>str_repeat('1',64),'inventoryCommitment'=>str_repeat('4',64),'scopeId'=>$sid,
    'membershipHeadHash'=>$cleanup['headHash'],'lifecycleHash'=>(new \Kanboard\Plugin\FamilyHub\Model\NativeCryptoLifecycleV2($container))->closingHash($sid),
    'managerAccountId'=>$account,'managerDirectoryHeadHash'=>$current['headHash'],'contentCertificateHash'=>null,'financeCertificateHash'=>null,'controlCount'=>0,'controlRoot'=>str_repeat('6',64)],"JivieMigrationActivation/v3\n",$freshKeys);
$publicationHash=V2::hash((object)$publication);
$publicationEvent=request2('crypto2.account.migrationAttest',['migrationId'=>$migration,'scopeToken'=>str_repeat('7',64),'domain'=>'content','attestationHash'=>$publicationHash],$fresh,$freshKeys,$current['snapshot'],$current);
call('crypto2.account.migrationAttest',$publicationEvent,$fresh);
q('INSERT INTO familyhub_crypto_migration_activations_v3 VALUES(?,?,?,?,?,?,?,?,?,?,?)',[$migration,$sid,$publicationHash,$cleanup['headHash'],json_decode(base64_decode($publication['commandBase64']),true)['lifecycleHash'],$account,json_encode($publication),json_encode($publicationEvent),0,str_repeat('6',64),'anchored']);
// Real root/FILE epoch recovery revokes the historical signing device. The
// immutable directory rows remain deliberately blank in their snapshot column.
$before=call('crypto2.account.status',[],$fresh);$replacement=call('auth.login',['username'=>$alice['username'],'password'=>$alice['password'],'deviceName'=>'Generation prefix recovery']);$replacementKeys=keys();$newEpoch=uid();$snapshot=$before['snapshot'];
foreach($snapshot['devices'] as &$d){if($d['revokedGeneration']===null)$d['revokedGeneration']=$before['generation']+1;}unset($d);
$snapshot['identityEpochId']=$newEpoch;$snapshot['devices'][]=dev2($replacement,$replacementKeys,$newEpoch,$before['generation']+1);$snapshot=sorted2($snapshot);
$recovery=request2('crypto2.account.recoverEpoch',['newIdentityEpochId'=>$newEpoch,'newDeviceSigningKeyBase64'=>$replacementKeys['signPublic'],'newDeviceEncryptionKeyBase64'=>$replacementKeys['boxPublic']],$replacement,$root,$snapshot,$before,'root');
call('crypto2.account.recoverEpoch',$recovery,$replacement);
ck(count(array_filter(q('SELECT snapshot FROM familyhub_crypto_directory WHERE account_id=?',[$account]),fn($r)=>$r['snapshot']!==''))===0,'genuine appended historical rows contain no snapshot cache');
$helper=new Generation($container);$actor=['user'=>['id'=>$replacement['user']['id'],'account_id'=>$account],'device'=>['id'=>$replacement['device']['id']]];$generation=uid();
$prepare=['migrationId'=>$migration,'generationId'=>$generation,'mode'=>'continue'];$prepareProof=content2('crypto2.migration.generation.prepare',$prepare,$replacement,$replacementKeys);
$prepared=$helper->prepare($prepare,$actor,$prepareProof);
$index=new ReflectionMethod($helper,'indexProof');$index->invoke($helper,$generation,$explicit);
ck(q('SELECT author_reference FROM familyhub_crypto_migration_generation_evidence_v3 WHERE generation_id=? AND proof_hash=?',[$generation,V2::hash((object)$generic)])[0]['author_reference']===$before['headHash'],'generic old metadata selects latest authenticated active prefix, not current revoked state');
[$explicitBody]=NativeCryptoCodec::decode($explicit);$explicitReference=$explicitBody['payload']['authorDirectoryHeadHash'];
ck(q('SELECT author_reference FROM familyhub_crypto_migration_generation_evidence_v3 WHERE generation_id=? AND proof_hash=?',[$generation,V2::hash((object)$explicit)])[0]['author_reference']===$explicitReference,'explicit reference is authenticated before sealing retained evidence');
$badExplicitBody=$explicitBody;$badExplicitBody['payload']['authorDirectoryHeadHash']=str_repeat('f',64);
$badExplicit=inner2($badExplicitBody,"JivieE2EE/v2\n",$freshKeys);
deny(fn()=>$index->invoke($helper,$generation,$badExplicit),'crypto_migration_generation_signer_unavailable','explicit missing prefix rejected before retained set is sealed');
$sealed=$helper->seal(['generationId'=>$generation],$actor);$now=call('crypto2.account.status',[],$replacement);
$approval=inner2(['version'=>3,'serverId'=>$replacement['serverId'],'migrationId'=>$migration,'generationId'=>$generation,'mode'=>'continue','contextHash'=>$sealed['contextHash'],'accountId'=>$account,'deviceId'=>$replacement['device']['id'],'authorDirectoryHeadHash'=>$now['headHash'],'deviceSnapshotHash'=>$now['deviceSnapshotHash']],Generation::APPROVAL_DOMAIN,$replacementKeys);
$approvalEvent=request2('crypto2.account.migrationAttest',['migrationId'=>$migration,'scopeToken'=>Generation::token($replacement['serverId'],$migration,$generation),'domain'=>'content','attestationHash'=>V2::hash((object)$approval)],$replacement,$replacementKeys,$now['snapshot'],$now);
call('crypto2.account.migrationAttest',$approvalEvent,$replacement);$helper->approve(['generationId'=>$generation,'authorization'=>$approval,'eventAuthorization'=>$approvalEvent],$actor);
ck(Generation::retainedSigningKey($pdo,$generic,$account)===null,'retained historical key unavailable outside final transaction context');
$scopeModel=new \Kanboard\Plugin\FamilyHub\Model\NativeCryptoScopeV2($container);
$scopeMethod=new ReflectionMethod($scopeModel,'scope');$liveScope=$scopeMethod->invoke($scopeModel,$sid,$replacement['user']['id']);
$retainedHead=$scopeModel->current($sid);$retainedMembers=$scopeModel->body($retainedHead)['members'];
deny(fn()=>$scopeModel->assertMembershipParity($liveScope,$retainedMembers,$retainedHead['head_hash']),'crypto_member_directory_changed','ordinary parity still rejects recovered member epoch outside continuation');
$pdo->beginTransaction();
try{
    $helper->withContinuedEvidence($migration,$actor,fn($m)=>true,function()use($pdo,$generic,$explicit,$account,$freshKeys,$scopeModel,$liveScope,$retainedHead,$retainedMembers){
        ck(Generation::retainedSigningKey($pdo,$generic,$account)===$freshKeys['signPublic'],'approved locked context resolves generic historical signer after recovery');
        ck(Generation::retainedSigningKey($pdo,$explicit,$account)===$freshKeys['signPublic'],'approved locked context resolves exact explicit historical signer');
        $scopeModel->assertMembershipParity($liveScope,$retainedMembers,$retainedHead['head_hash']);
        ck(true,'approved exact retained head keeps live ACL and historical directory parity after recovery');
        deny(fn()=>$scopeModel->assertMembershipParity($liveScope,$retainedMembers,str_repeat('f',64)),'crypto_member_directory_changed','wrong head cannot use historical member tuple');
        $changed=$retainedMembers;$changed[0]['identityEpochId']=uid();
        deny(fn()=>$scopeModel->assertMembershipParity($liveScope,$changed,$retainedHead['head_hash']),'crypto_migration_generation_changed','changed member cannot borrow exact retained head');
        $changed=$retainedMembers;$changed[0]['rootSigningKeyBase64']=base64_encode(random_bytes(32));
        deny(fn()=>$scopeModel->assertMembershipParity($liveScope,$changed,$retainedHead['head_hash']),'crypto_migration_generation_changed','changed signed root cannot borrow retained authority');
        $state=q('SELECT snapshot FROM familyhub_crypto_directory_state WHERE account_id=?',[$account])[0];$changed=json_decode($state['snapshot'],true,34,JSON_THROW_ON_ERROR);$changed['rootEncryptionKeyBase64']=base64_encode(random_bytes(32));
        q('UPDATE familyhub_crypto_directory_state SET snapshot=? WHERE account_id=?',[json_encode($changed),$account]);
        deny(fn()=>$scopeModel->assertMembershipParity($liveScope,$retainedMembers,$retainedHead['head_hash']),'crypto_directory_cache_unavailable','current root substitution is not a continuation');
        q('UPDATE familyhub_crypto_directory_state SET snapshot=? WHERE account_id=?',[$state['snapshot'],$account]);
    });
    ck(Generation::retainedSigningKey($pdo,$generic,$account)===null,'retained context removed immediately after final callback');
}finally{$pdo->rollBack();}
$directory=new Directory($container);[$oldCommand]=NativeCryptoCodec::decode($generic);
deny(fn()=>$directory->authorizeContent($oldCommand,$directory->current($account)),'crypto_device_unapproved','ordinary old-device authorization remains denied');
$prefix=new ReflectionMethod($helper,'historicalPrefix');
deny(fn()=>$prefix->invoke(new Generation($container),$account,str_repeat('f',64),$fresh['device']['id']),'crypto_migration_generation_signer_unavailable','unknown prefix cannot authorize retained signer');
$middle=q('SELECT generation,head_hash,authorization FROM familyhub_crypto_directory WHERE account_id=? AND generation=2',[$account])[0];
$pdo->beginTransaction();
try{
    q('DELETE FROM familyhub_crypto_directory WHERE account_id=? AND generation=2',[$account]);
    deny(fn()=>$prefix->invoke(new Generation($container),$account,$explicitReference,$fresh['device']['id']),'crypto_migration_generation_directory_fork','missing intermediate prefix remains closed');
}finally{$pdo->rollBack();}
$pdo->beginTransaction();
try{
    q('UPDATE familyhub_crypto_directory SET previous_head_hash=? WHERE account_id=? AND generation=2',[str_repeat('e',64),$account]);
    deny(fn()=>$prefix->invoke(new Generation($container),$account,$explicitReference,$fresh['device']['id']),'crypto_migration_generation_directory_fork','forked intermediate prefix remains closed');
}finally{$pdo->rollBack();}
$pdo->beginTransaction();
try{
    $corrupt=json_decode($middle['authorization'],true,34,JSON_THROW_ON_ERROR);$corrupt['signatureBase64']=base64_encode(str_repeat("\0",64));
    q('UPDATE familyhub_crypto_directory SET authorization=? WHERE account_id=? AND generation=2',[json_encode($corrupt),$account]);
    deny(fn()=>$prefix->invoke(new Generation($container),$account,$explicitReference,$fresh['device']['id']),'crypto_signature_invalid','invalid intermediate signature remains closed');
}finally{$pdo->rollBack();}
echo 'Generation historical prefix: '.$checks.' cumulative checks PASS'.PHP_EOL;
