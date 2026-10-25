<?php
/** New baseline, codec-purpose and unchanged SQL guard controls only. */
require __DIR__.'/crypto-record-policy-restore-fixture.php';
use Kanboard\Plugin\FamilyHub\Model\NativeFinanceAccess;
use Kanboard\Plugin\FamilyHub\Model\NativeCryptoTableV2;
$baselineOld=$old;$baselineOld['metadata']='{}';
$entry=['createdByAccountId'=>id(2),'fieldCommitments'=>$f];
sql('INSERT INTO familyhub_crypto_record_policy_entries_v1 VALUES(?,?,?,?,?,?)',[id(3),id(90),$wire,$hashes[4],json_encode($entry),'{}']);
$policy->admit($record,$baselineOld,$scope,$creator);ck(true,'exact activated tombstone baseline preserves a legacy creator for explicit restore');
sql('UPDATE familyhub_crypto_record_policy_entries_v1 SET record_proof_hash=? WHERE id=?',[$hashes[3],$wire]);
deny(fn()=> $policy->admit($record,$baselineOld,$scope,$creator),'crypto_record_policy_baseline_changed','a stale baseline cannot authorize restore of another tombstone');
$technical=$record;$technical['type']='scopeMetadata';$technical['metadata']['identity']=['canonicalId'=>id(30),'sourceKind'=>'scope_metadata'];
$technical['id']=\Kanboard\Plugin\FamilyHub\Model\NativeCryptoRecordAddressV2::derive($server,id(3),'content','scope_metadata',id(30));
deny(fn()=> $codec->record($technical),'crypto_record_restore_invalid','technical record types cannot claim ordinary user restore intent');
sql("UPDATE familyhub_scopes SET kind='organization' WHERE id=?",[id(3)]);
sql('INSERT INTO familyhub_members VALUES(?,?,?,?,1)',[id(3),2,id(2),'viewer']);
$readUser=['id'=>2,'account_id'=>id(2)];
deny(fn()=> (new NativeFinanceAccess(['db'=>$db]))->policyForCrypto(id(3),$readUser,true,true),'finance_forbidden','restore policy does not change the independent real SQL finance write guard');
$table=$record;$table['type']='table';
$leaseActor=['user'=>$readUser,'device'=>['id'=>id(102)]];
$prepared=[id(3).':'.$table['id']=>['record'=>$table,'old'=>['deleted'=>1]]];
deny(fn()=> (new NativeCryptoTableV2(['db'=>$db],bearer(2)))->assertBatch([],$prepared,$leaseActor),'lease_lost','tombstoned table restore cannot bypass the existing real lease requirement');
ck((int)sql('SELECT COUNT(*) FROM familyhub_crypto_table_leases')->fetchColumn()===0&&(int)sql('SELECT COUNT(*) FROM familyhub_crypto_record_history')->fetchColumn()===4,'pending restore boundaries leave leases and original history intact');
echo json_encode(['test'=>'crypto-record-policy-restore-boundaries','status'=>'pass','checks'=>$checks,'fixture'=>'isolated-memory-sqlite','http'=>false,'receiverOrSignatureProof'=>false]).PHP_EOL;
