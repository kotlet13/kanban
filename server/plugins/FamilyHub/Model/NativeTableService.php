<?php
namespace Kanboard\Plugin\FamilyHub\Model;

/** Whole-document CAS plus an exclusive renewable device lease. No formula execution. */
class NativeTableService extends NativeDocumentService
{
    const LEASE_SECONDS=90;
    public function execute($operation,array $p)
    {
        $action=substr($operation,7);if (!in_array($action,['list','get','create','acquire','renew','release','save','delete'],true)) { throw new NativeError('unsupported_operation',404); }
        $this->documentGate();
        return $this->transaction(function()use($operation,$action,$p){
            $required=['scopeId'];$optional=[];
            if ($action!=='list') { $required[]='id'; }
            if ($action==='create') { $required=array_merge($required,['title','requestId']); }
            if (in_array($action,['renew','release','save','delete'],true)) { $required[]='token'; }
            if (in_array($action,['save','delete'],true)) { $required=array_merge($required,['expectedRevision','requestId']); }
            if ($action==='save') { $required=array_merge($required,['title','cells']); }
            if (in_array($action,['acquire','renew','release'],true)) { $optional=['requestId']; }
            if ($action==='acquire') { $optional[]='token'; }
            $this->fields($p,$required,$optional);$actor=$this->actor();$sid=$this->uuid($p['scopeId']);
            $write=!in_array($action,['list','get'],true);$scope=$this->scope($sid,$actor['user']['id'],$write);
            if ($scope['kind']!=='organization') { throw new NativeError('tables_scope_unsupported',403); }
            if ($write) { (new NativeModerationService($this->container,$this->bearer,$this->ip))->guardWrite($operation,$p); }
            if ($action==='list') { return ['sheets'=>array_map(fn($r)=>$this->sheet($r,false),$this->many('SELECT * FROM familyhub_tables WHERE scope_id=? AND deleted=0 ORDER BY updated_at DESC,id LIMIT 100',[$sid]))]; }
            $id=$this->uuid($p['id']);$r=$this->one('SELECT * FROM familyhub_tables WHERE scope_id=? AND id=?'.$this->lockSuffix(),[$sid,$id]);
            $request=isset($p['requestId'])?$this->uuid($p['requestId']):null;$hash=$request?$this->hashRequest($operation,$p):null;
            // Fresh ACL is checked before replay; a device never receives another device's lease.
            $saved=$request?$this->receipt($sid,$actor,$request,$hash):null;
            if ($saved) {
                if (($saved['deleted']??false)===true) { return $saved; }
                if (!$r || (int)$r['deleted']) { throw new NativeError('table_unavailable',404); }
                if (in_array($action,['acquire','renew'],true)) {
                    if (!$this->holder($r,$actor) || !$this->active($r) || ($saved['leaseNonce']??null)!==$r['lease_nonce']) { throw new NativeError('lease_lost',409); }
                    return ['lease'=>$this->lease($r,$actor)];
                }
                if ($action==='release') { return ['released'=>true]; }
                if (isset($saved['sheet']['cells'])) { $saved['sheet']['cells']=(object)$saved['sheet']['cells']; }
                return $saved;
            }
            if ($action==='create') {
                $this->text($p['title'],200);if ($r) { throw new NativeError('table_conflict',409); }
                $count=$this->one('SELECT COUNT(*) AS n FROM familyhub_tables WHERE scope_id=? AND deleted=0',[$sid]);if ((int)$count['n']>=100) { throw new NativeError('table_limit',422); }
                $this->change('INSERT INTO familyhub_tables(scope_id,id,title,cells,revision,updated_at,created_by) VALUES(?,?,?, ?,1,?,?)',[$sid,$id,$p['title'],'{}',time(),$actor['user']['account_id']]);
                $r=$this->one('SELECT * FROM familyhub_tables WHERE scope_id=? AND id=?',[$sid,$id]);$result=['sheet'=>$this->sheet($r)];
            } else {
                if (!$r || (int)$r['deleted']) { throw new NativeError('table_unavailable',404); }
                if ($action==='get') { return ['sheet'=>$this->sheet($r),'lease'=>$this->lease($r,$actor)]; }
                if ($action==='acquire') {
                    if ($this->active($r)) {
                        if (!$this->validToken($r,$actor,$p['token']??null) && !( !isset($p['token']) && $this->holder($r,$actor) && hash_equals($r['lease_hash'],hash('sha256',$this->derive($r))) )) { throw new NativeError('table_locked',409,['lease'=>$this->lease($r,null)]); }
                    } else {
                        $r['lease_nonce']=bin2hex(random_bytes(32));$r['lease_account_id']=$actor['user']['account_id'];$r['lease_device_id']=$actor['device']['id'];$r['lease_name']=mb_strcut($actor['user']['name']?:$actor['user']['username'],0,200,'UTF-8');$r['lease_hash']=hash('sha256',$this->derive($r));
                    }
                    $r['lease_expires']=time()+self::LEASE_SECONDS;$this->persistLease($r);$result=['lease'=>$this->lease($r,$actor)];
                } else {
                    if (!$this->validToken($r,$actor,$p['token'])) { throw new NativeError('lease_lost',409,['lease'=>$this->lease($r,null)]); }
                    if ($action==='renew') { $r['lease_expires']=time()+self::LEASE_SECONDS;$this->persistLease($r);$result=['lease'=>$this->lease($r,$actor)]; }
                    elseif ($action==='release') { $this->clearLease($sid,$id);$result=['released'=>true]; }
                    else {
                        if (!is_int($p['expectedRevision']) || $p['expectedRevision']<1) { throw new NativeError('validation_error'); }
                        if ($p['expectedRevision']!==(int)$r['revision']) { throw new NativeError('table_conflict',409,['sheet'=>$this->sheet($r)]); }
                        if ($action==='delete') {
                            $this->removeInTransaction($sid,$id);$result=['deleted'=>true];
                        } else {
                            $this->text($p['title'],200);$cells=$this->cells($p['cells']);
                            $this->change('UPDATE familyhub_tables SET title=?,cells=?,revision=revision+1,updated_at=? WHERE scope_id=? AND id=?',[$p['title'],$cells,time(),$sid,$id]);$r=$this->one('SELECT * FROM familyhub_tables WHERE scope_id=? AND id=?',[$sid,$id]);$result=['sheet'=>$this->sheet($r)];
                        }
                    }
                }
            }
            if ($request) { $stored=in_array($action,['acquire','renew'],true)?['leaseNonce'=>$r['lease_nonce']]:$result;$this->rememberDocument($sid,$actor,$request,$hash,$id,$stored); }
            return $result;
        });
    }
    /** Explicit administrator removal uses the same durable target cleanup as the lease owner. */
    public function removeInTransaction($sid,$id)
    {
        (new NativeAttachmentService($this->container))->removeTarget($sid,'table',$id);
        $this->change("UPDATE familyhub_tables SET deleted=1,title='',cells='{}',revision=revision+1,updated_at=? WHERE scope_id=? AND id=?",[time(),$sid,$id]);$this->clearLease($sid,$id);
        $this->change('DELETE FROM familyhub_document_requests WHERE scope_id=? AND object_id=?',[$sid,$id]);
    }
    public function moderationEvidence($scope,$id)
    {
        if (!$this->available() || $scope['kind']!=='organization' || ($scope['deleted_at']??null)!==null) { throw new NativeError('report_target_unavailable',404); }
        $r=$this->one('SELECT * FROM familyhub_tables WHERE scope_id=? AND id=? AND deleted=0',[$scope['id'],$id]);if (!$r) { throw new NativeError('report_target_unavailable',404); }
        $sheet=$this->sheet($r);$all=(array)$sheet['cells'];ksort($all);$cells=[];$truncated=count($all)>100;
        foreach (array_slice($all,0,100,true) as $address=>$raw) { $cells[$address]=mb_strcut($raw,0,200,'UTF-8');if ($cells[$address]!==$raw) { $truncated=true; } }
        $attachments=$this->many("SELECT id,name,mime,size,sha256 FROM familyhub_attachments WHERE scope_id=? AND target_type='table' AND target_id=? AND complete=1 AND deleted=0 ORDER BY id",[$scope['id'],$id]);
        return ['id'=>$id,'type'=>'table','scopeId'=>$scope['id'],'revision'=>(int)$r['revision'],'title'=>$r['title'],'cells'=>(object)$cells,'cellCount'=>count($all),'cellsTruncated'=>$truncated,'attachments'=>$attachments,'documentHash'=>hash('sha256',$this->canonical([$sheet,$attachments]))];
    }
    private function cells($cells)
    {
        if (!is_array($cells) || ($cells && array_is_list($cells)) || count($cells)>10000) { throw new NativeError('validation_error'); }
        $clean=[];foreach ($cells as $address=>$raw) { if (!is_string($address) || !preg_match('/^[A-Z]{1,3}([1-9][0-9]{0,4}|100000)$/D',$address)) { throw new NativeError('validation_error'); }$this->text($raw,4096,true);if ($raw!=='') { $clean[$address]=$raw; } }
        $json=json_encode((object)$clean,JSON_UNESCAPED_UNICODE|JSON_THROW_ON_ERROR);if (strlen($json)>524288) { throw new NativeError('validation_error'); }return $json;
    }
    private function sheet($r,$full=true) { return ['id'=>$r['id'],'scopeId'=>$r['scope_id'],'title'=>$r['title'],'cells'=>$full?(object)json_decode($r['cells'],true,32,JSON_THROW_ON_ERROR):(object)[],'revision'=>(int)$r['revision'],'updatedAt'=>(int)$r['updated_at']]; }
    private function active($r) { return !empty($r['lease_hash']) && (int)$r['lease_expires']>time(); }
    private function holder($r,$a) { return $a && $r['lease_account_id']===$a['user']['account_id'] && $r['lease_device_id']===$a['device']['id']; }
    private function derive($r) { return hash_hmac('sha256',$r['scope_id'].':'.$r['id'].':'.$r['lease_nonce'],$this->bearer); }
    private function validToken($r,$a,$token) { return is_string($token) && preg_match('/^[a-f0-9]{64}$/D',$token) && $this->active($r) && $this->holder($r,$a) && hash_equals($r['lease_hash'],hash('sha256',$token)); }
    private function lease($r,$a)
    {
        if (!$this->active($r)) { return null; }
        $wire=['holderName'=>$r['lease_name'],'holderAccountId'=>$r['lease_account_id'],'holderDeviceId'=>$r['lease_device_id'],'expiresAt'=>(int)$r['lease_expires']];
        if ($this->holder($r,$a)) { $token=$this->derive($r);if (hash_equals($r['lease_hash'],hash('sha256',$token))) { $wire['token']=$token; } }return $wire;
    }
    private function persistLease($r) { $this->change('UPDATE familyhub_tables SET lease_hash=?,lease_nonce=?,lease_account_id=?,lease_device_id=?,lease_name=?,lease_expires=? WHERE scope_id=? AND id=?',[$r['lease_hash'],$r['lease_nonce'],$r['lease_account_id'],$r['lease_device_id'],$r['lease_name'],$r['lease_expires'],$r['scope_id'],$r['id']]); }
    private function clearLease($scope,$id) { $this->change('UPDATE familyhub_tables SET lease_hash=NULL,lease_nonce=NULL,lease_account_id=NULL,lease_device_id=NULL,lease_name=NULL,lease_expires=0 WHERE scope_id=? AND id=?',[$scope,$id]); }
}
