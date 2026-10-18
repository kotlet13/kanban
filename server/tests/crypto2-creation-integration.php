<?php
require __DIR__.'/crypto2-scope-integration.php';
use Kanboard\Plugin\FamilyHub\Model\NativeCryptoCodec;
require __DIR__.'/crypto2-record-helpers.php';
$oldHead=call('crypto2.scope.headGet',['scopeId'=>$space['id']],$fresh);
deny(fn()=>call('crypto2.records.batch',batch2([row2($space['id'],$oldHead,$fresh,$freshKeys)],$fresh,$freshKeys),$fresh),'crypto_migration_required','active legacy head is not permission to write before verified P6 commit');
$newId=uid();$create=content2('crypto2.scope.create',['id'=>$newId,'kind'=>'organization'],$fresh,$freshKeys);$created=call('crypto2.scope.create',$create,$fresh)['scope'];
deny(fn()=>call('sync6.push',['scopeId'=>$newId,'operation'=>['opId'=>uid(),'recordId'=>uid(),'type'=>'task','expectedRevision'=>0,'deleted'=>false,'payload'=>['title'=>'PLAINTEXT_SENTINEL']]],$fresh),'crypto_upgrade_required','new signed origin rejects old plaintext upload before first crypto head');
ck($created['id']===$newId&&$created['cryptoState']==='staged'&&!isset($created['name']),'signed empty origin creates only generic structural scope and no plaintext name');
ck(call('crypto2.scope.create',$create,$fresh)['scope']===$created,'creation lost ACK returns exact same durable origin');
deny(fn()=>send2('crypto2.scope.create',['id'=>$newId,'kind'=>'organization'],$fresh,$freshKeys),'crypto_scope_id_conflict','new creation request cannot reinterpret existing scope identity');
$body=candidate2($created,$state);$pending=send2('crypto2.scope.headPut',$body,$fresh,$freshKeys);$head=call('crypto2.scope.headGet',['scopeId'=>$newId,'headHash'=>$pending['headHash']],$fresh);grants2($head,[$head],$fresh,$freshKeys,$root,$state['snapshot']['recoveryRootEpochId']);$manifest=call('crypto2.grants.manifest',['scopeId'=>$newId,'headHash'=>$head['headHash']],$fresh);
send2('crypto2.scope.activate',['scopeId'=>$newId,'headHash'=>$head['headHash'],'grantManifestHash'=>$manifest['grantManifestHash'],'authorDirectoryHeadHash'=>$state['headHash']],$fresh,$freshKeys);
$record=row2($newId,$head,$fresh,$freshKeys);ck(call('crypto2.records.batch',batch2([$record],$fresh,$freshKeys),$fresh)['status']==='applied','new signed origin accepts cipher business traffic only after actual head and grants');
deny(fn()=>call('finance.grant',['scopeId'=>$newId,'accountId'=>$fresh['user']['accountId'],'grant'=>'write','requestId'=>uid()],$fresh),'crypto_upgrade_required','legacy finance policy cannot mutate a staged-origin cryptographic scope');
$personal=send2('crypto2.scope.ensurePersonal',['id'=>uid()],$fresh,$freshKeys)['scope'];$again=send2('crypto2.scope.ensurePersonal',['id'=>uid()],$fresh,$freshKeys)['scope'];ck($personal['id']===$again['id'],'personal canonical origin remains one scope across new exact commands');
$child=send2('crypto2.scope.create',['id'=>uid(),'kind'=>'project','parentScopeId'=>$newId,'expectedParentAccessRevision'=>$created['accessRevision'],'expectedParentAccessBasis'=>$created['accessBasis']],$fresh,$freshKeys)['scope'];ck($child['parentScopeId']===$newId&&count($child['accessBasis'])===2,'new child creation binds exact accessible parent basis without plaintext project record');
ck(count(q('SELECT id FROM familyhub_records WHERE scope_id=?',[$child['id']]))===0,'project origin never materializes plaintext title or default project payload');
echo 'Crypto2 creation integration: '.$checks.' checks PASS'.PHP_EOL;
