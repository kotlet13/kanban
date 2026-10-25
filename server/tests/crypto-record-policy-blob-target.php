<?php
/** Target-bound upload SQL; membership/head/command signature prevalidated seam.
 * This is not an HTTP, native-client or recipient-decryption integration test. */
require __DIR__.'/account-changes-fixture.php';
use Kanboard\Plugin\FamilyHub\Model\NativeCryptoStorageV2;
use Kanboard\Plugin\FamilyHub\Model\NativeCryptoCodec;
use Kanboard\Plugin\FamilyHub\Model\NativeError;
sql("UPDATE familyhub_scopes SET kind='organization' WHERE id=?",[id(3)]);
sql('INSERT INTO familyhub_members VALUES(?,?,?,?,1)',[id(3),2,id(2),'viewer']);
$actor=['user'=>['id'=>2,'account_id'=>id(2)],'device'=>['id'=>id(102)]];
$f=['content'=>str_repeat('a',64),'assignment'=>str_repeat('b',64),'checked'=>str_repeat('c',64)];
$metadata=['recordPolicy'=>['version'=>1,'createdByAccountId'=>id(2),'operation'=>'edit','fieldCommitments'=>$f],'notificationState'=>['assigneeAccountIds'=>[]]];
$hash=str_repeat('d',64);
sql('INSERT INTO familyhub_crypto_records VALUES(?,?,?,?,?,?,?,?,?,?)',[id(3),id(30),'idea',1,0,1,1,'CIPHER_SENTINEL',json_encode($metadata),'{}']);
sql('INSERT INTO familyhub_crypto_record_history VALUES(?,?,?,?,?,?,?,?,?)',[id(3),id(30),1,1,1,'content',$hash,'{}','{}']);
sql('INSERT INTO familyhub_crypto_record_positions VALUES(?,?,?,?)',[id(3),id(30),'content',1]);
class TargetBlobStorage extends NativeCryptoStorageV2 {
    public $role='viewer';public $usedPolicy=false;
    protected function blobAuthority($p,$actor,$write,$recordPolicy=false){
        $this->usedPolicy=$recordPolicy;
        if($write&&!$recordPolicy&&$this->role==='viewer')throw new NativeError('permission_revoked',403);
        return [['id'=>$p['scopeId'],'kind'=>'organization','role'=>$this->role],['head_hash'=>$p['membershipHeadHash']??null]];
    }
    public function run($suffix,$p,$actor){
        $command=['version'=>2,'operation'=>'crypto2.blob.'.$suffix,'accountId'=>$actor['user']['account_id'],'deviceId'=>$actor['device']['id'],'payload'=>$p];
        $proof=['commandBase64'=>base64_encode(NativeCryptoCodec::canonical((object)$command)),'signatureBase64'=>base64_encode(str_repeat('S',64))];
        return $this->transaction(fn()=> $this->write($command['operation'],$p,$actor,$proof,$command,null));
    }
    public function binding($blob,$record){$this->assertBlobRecordBinding($blob,$record);}
}
$store=new TargetBlobStorage(['db'=>$db],bearer(2),'synthetic-blob-target');
$target=['type'=>'idea','wireId'=>id(30),'currentRecordProofHash'=>$hash];
$common=['scopeId'=>id(3),'id'=>id(60),'domain'=>'content','epoch'=>1,'accessRevision'=>0,'membershipHeadHash'=>str_repeat('e',64),'recordPolicyTarget'=>$target];
$data=str_repeat('X',96);$begin=['size'=>strlen($data),'sha256'=>hash('sha256',$data),'manifestBase64'=>base64_encode(str_repeat('M',48))];
deny(fn()=> $store->run('begin',$common+$begin,$actor),'permission_revoked','preactivation viewer receives no new blob upload permission');
sql('INSERT INTO familyhub_crypto_record_policy_state_v1 VALUES(?,?,1)',[id(3),id(90)]);
$unbound=$common;unset($unbound['recordPolicyTarget']);
deny(fn()=> $store->run('begin',$unbound+$begin,$actor),'permission_revoked','active viewer still cannot start an unbound blob');
$ack=$store->run('begin',$common+$begin,$actor);
ck($store->usedPolicy&&$ack['offset']===0,'active existing idea creator may begin an exact target-bound upload as viewer');
$row=sql('SELECT * FROM familyhub_crypto_blobs_v2 WHERE id=?',[id(60)])->fetch(PDO::FETCH_ASSOC);
[$signedBegin]=NativeCryptoCodec::decode(json_decode($row['authorization'],true));
ck(NativeCryptoCodec::canonical($signedBegin['payload']['recordPolicyTarget'])===NativeCryptoCodec::canonical($target),'original begin authorization durably preserves the signed target for readers');
$changed=$common;$changed['recordPolicyTarget']['wireId']=id(31);
deny(fn()=> $store->run('chunk',$changed+['offset'=>0,'dataBase64'=>base64_encode($data)],$actor),'crypto_blob_immutable','subsequent command cannot switch the signed target');
deny(fn()=> $store->run('chunk',$unbound+['offset'=>0,'dataBase64'=>base64_encode($data)],$actor),'permission_revoked','subsequent command cannot omit the persisted target');
$foreign=$metadata;$foreign['recordPolicy']['createdByAccountId']=id(1);
sql('UPDATE familyhub_crypto_records SET metadata=? WHERE id=?',[json_encode($foreign),id(30)]);
deny(fn()=> $store->run('chunk',$common+['offset'=>0,'dataBase64'=>base64_encode($data)],$actor),'record_edit_forbidden','chunk rechecks current record authority before accepting bytes');
ck((int)sql('SELECT received FROM familyhub_crypto_blobs_v2 WHERE id=?',[id(60)])->fetchColumn()===0,'denied chunk preserves existing bytes and offset');
sql('UPDATE familyhub_crypto_records SET metadata=? WHERE id=?',[json_encode($metadata),id(30)]);
$store->run('chunk',$common+['offset'=>0,'dataBase64'=>base64_encode($data)],$actor);
sql('UPDATE familyhub_crypto_record_history SET record_proof_hash=? WHERE id=?',[str_repeat('f',64),id(30)]);
deny(fn()=> $store->run('complete',$common,$actor),'crypto_blob_target_changed','completion rechecks exact accepted predecessor proof hash');
sql('UPDATE familyhub_crypto_record_history SET record_proof_hash=? WHERE id=?',[$hash,id(30)]);
sql('UPDATE familyhub_crypto_records SET metadata=? WHERE id=?',[json_encode($foreign),id(30)]);
deny(fn()=> $store->run('complete',$common,$actor),'record_edit_forbidden','completion rechecks authority after all chunks have arrived');
sql('UPDATE familyhub_crypto_records SET metadata=? WHERE id=?',[json_encode($metadata),id(30)]);
$complete=$store->run('complete',$common,$actor);
ck($complete['complete']&&$complete['offset']===strlen($data),'valid target creator completes the original exact upload');
$blob=sql('SELECT * FROM familyhub_crypto_blobs_v2 WHERE id=?',[id(60)])->fetch(PDO::FETCH_ASSOC);
$record=['domain'=>'content','id'=>id(30),'type'=>'idea','previousRecordHash'=>str_repeat('9',64)];
$store->binding($blob,$record);ck(true,'same target may retain a complete blob across later legitimate record predecessors');
$wrong=$record;$wrong['id']=id(31);
deny(fn()=> $store->binding($blob,$wrong),'crypto_blob_target_mismatch','complete blob cannot be attached to a different record');
$wrong=$record;$wrong['type']='task';
deny(fn()=> $store->binding($blob,$wrong),'crypto_blob_target_mismatch','complete blob cannot be attached to another type at the same wire id');
$other=$common;$other['id']=id(61);$other['recordPolicyTarget']['wireId']=id(31);
deny(fn()=> $store->run('begin',$other+$begin,$actor),'crypto_blob_target_changed','missing target never grants viewer creation');
sql('UPDATE familyhub_crypto_records SET deleted=1 WHERE id=?',[id(30)]);
$other=$common;$other['id']=id(61);
deny(fn()=> $store->run('begin',$other+$begin,$actor),'crypto_blob_target_changed','deleted record cannot authorize an upload');
sql('UPDATE familyhub_crypto_records SET deleted=0,metadata=? WHERE id=?',[json_encode($foreign),id(30)]);
$store->role='member';
deny(fn()=> $store->run('begin',$other+$begin,$actor),'record_edit_forbidden','target-bound path does not give a general member edit rights on foreign records');
$store->role='owner';$finance=$other;$finance['domain']='finance';
deny(fn()=> $store->run('begin',$finance+$begin,$actor),'crypto_blob_target_invalid','target exception never expands finance staging');
$store->run('begin',$other+$begin,$actor);ck(true,'actual owner may stage a bound blob for another creator');
$plain=$other;unset($plain['recordPolicyTarget']);$plain['id']=id(62);$store->role='member';
$store->run('begin',$plain+$begin,$actor);ck(!$store->usedPolicy,'ordinary unbound writer path keeps the original scope guard');
// Accepted assignee is the only nonauthor content edit exception here.
$store->role='viewer';$task=$foreign;$task['notificationState']['assigneeAccountIds']=[id(2)];
sql("UPDATE familyhub_crypto_records SET type='task',metadata=? WHERE id=?",[json_encode($task),id(30)]);
$taskCommon=$common;$taskCommon['id']=id(63);$taskCommon['recordPolicyTarget']['type']='task';
$store->run('begin',$taskCommon+$begin,$actor);ck(true,'current accepted task assignee may stage content without acquiring financial write permission');
$task['notificationState']['assigneeAccountIds']=[];
sql('UPDATE familyhub_crypto_records SET metadata=? WHERE id=?',[json_encode($task),id(30)]);
deny(fn()=> $store->run('chunk',$taskCommon+['offset'=>0,'dataBase64'=>base64_encode($data)],$actor),'record_edit_forbidden','removing accepted task assignment prevents the next upload chunk');
sql("UPDATE familyhub_crypto_records SET type='shoppingItem' WHERE id=?",[id(30)]);
$checkbox=$common;$checkbox['id']=id(64);$checkbox['recordPolicyTarget']['type']='shoppingItem';
deny(fn()=> $store->run('begin',$checkbox+$begin,$actor),'record_edit_forbidden','shopping checkbox access does not grant blob staging on foreign content');
sql("UPDATE familyhub_crypto_records SET type='idea',metadata='{}' WHERE id=?",[id(30)]);
$entry=['createdByAccountId'=>id(2),'fieldCommitments'=>$f];
sql('INSERT INTO familyhub_crypto_record_policy_entries_v1 VALUES(?,?,?,?,?,?)',[id(3),id(90),id(30),$hash,json_encode($entry),'{}']);
$baseline=$common;$baseline['id']=id(65);$store->run('begin',$baseline+$begin,$actor);
ck(true,'verified exact active baseline creator authorizes historical ciphertext without rewriting it');
sql('UPDATE familyhub_crypto_record_policy_entries_v1 SET record_proof_hash=? WHERE id=?',[str_repeat('8',64),id(30)]);
$baseline['id']=id(66);
deny(fn()=> $store->run('begin',$baseline+$begin,$actor),'crypto_record_policy_baseline_changed','unverified baseline predecessor cannot authorize staging');
echo json_encode(['test'=>'crypto-record-policy-blob-target','status'=>'pass','checks'=>$checks,'fixture'=>'isolated-memory-sqlite','authority'=>'explicit prevalidated membership/head/signature seam','http'=>false,'recipientVerification'=>false]).PHP_EOL;
