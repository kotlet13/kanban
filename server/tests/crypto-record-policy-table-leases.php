<?php
/** Real lease SQL with an explicitly prevalidated membership/head seam. */
require __DIR__.'/account-changes-fixture.php';
use Kanboard\Plugin\FamilyHub\Model\NativeCryptoTableV2;
use Kanboard\Plugin\FamilyHub\Model\NativeError;
sql("UPDATE familyhub_scopes SET kind='organization' WHERE id=?",[id(3)]);
sql('INSERT INTO familyhub_members VALUES(?,?,?,?,1)',[id(3),2,id(2),'viewer']);
$f=['content'=>str_repeat('a',64),'assignment'=>str_repeat('b',64),'checked'=>str_repeat('c',64)];
$metadata=['recordPolicy'=>['version'=>1,'createdByAccountId'=>id(2),'operation'=>'edit','fieldCommitments'=>$f]];
sql('INSERT INTO familyhub_crypto_records VALUES(?,?,?,?,?,?,?,?,?,?)',[id(3),id(30),'table',1,0,1,1,'CIPHER_SENTINEL',json_encode($metadata),'{}']);
class AuthorizedTableLease extends NativeCryptoTableV2 {
    public $role='viewer';public $usedPolicy=false;
    protected function writeAuthority($p,$actor,$recordPolicy){
        $this->usedPolicy=$recordPolicy;
        if(!$recordPolicy&&$this->role==='viewer')throw new NativeError('permission_revoked',403);
        return [['id'=>$p['scopeId'],'role'=>$this->role,'kind'=>'organization'],['head_hash'=>$p['membershipHeadHash']]];
    }
    public function run($op,$p,$actor){return $this->transaction(fn()=> $this->write($op,$p,$actor));}
    public function checkBatch($payload,$prepared,$actor){return $this->transaction(fn()=> $this->assertBatch($payload,$prepared,$actor));}
}
$actor=['user'=>['id'=>2,'account_id'=>id(2)],'device'=>['id'=>id(102)]];
$service=new AuthorizedTableLease(['db'=>$db],bearer(2),'synthetic-table-policy');
$p=['scopeId'=>id(3),'id'=>id(30),'domain'=>'content','epoch'=>1,'accessRevision'=>0,'membershipHeadHash'=>str_repeat('d',64)];
deny(fn()=> $service->run('crypto2.table.acquire',$p,$actor),'permission_revoked','preactivation table viewer retains the original write guard');
sql('INSERT INTO familyhub_crypto_record_policy_state_v1 VALUES(?,?,1)',[id(3),id(90)]);
$acquired=$service->run('crypto2.table.acquire',$p,$actor);
ck($service->usedPolicy&&is_string($acquired['lease']['tokenBase64']),'active-policy table creator can acquire while its scope role is viewer');
$token=$acquired['lease']['tokenBase64'];$renewed=$service->run('crypto2.table.renew',$p+['tokenBase64'=>$token],$actor);
ck($renewed['lease']['tokenBase64']===$token,'author viewer renews the exact existing lease token');
$record=['scopeId'=>id(3),'id'=>id(30),'type'=>'table','deleted'=>false,'expectedRevision'=>1,'membershipHeadHash'=>$p['membershipHeadHash']];
$service->checkBatch(['tableLeases'=>[['scopeId'=>id(3),'id'=>id(30),'tokenBase64'=>$token]]],[id(3).':'.id(30)=>['record'=>$record,'old'=>['deleted'=>0]]],$actor);
ck(true,'table batch lease validation no longer reintroduces the broad scope writer gate');
$metadata['recordPolicy']['createdByAccountId']=id(1);sql('UPDATE familyhub_crypto_records SET metadata=? WHERE scope_id=? AND id=?',[json_encode($metadata),id(3),id(30)]);
$service->role='member';deny(fn()=> $service->run('crypto2.table.renew',$p+['tokenBase64'=>$token],$actor),'record_edit_forbidden','general member cannot renew a foreign table lease after policy applies');
$released=$service->run('crypto2.table.release',$p+['tokenBase64'=>$token],$actor);
ck($released['released']&&(int)sql('SELECT COUNT(*) FROM familyhub_crypto_table_leases')->fetchColumn()===0,'holder may release its own exact lease after edit permission changes');
deny(fn()=> $service->run('crypto2.table.acquire',$p,$actor),'record_edit_forbidden','general member cannot acquire a foreign table lock');
echo json_encode(['test'=>'crypto-record-policy-table-leases','status'=>'pass','checks'=>$checks,'fixture'=>'isolated-memory-sqlite','authority'=>'explicit prevalidated membership/head seam','http'=>false,'proofVerification'=>false]).PHP_EOL;
