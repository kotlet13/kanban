<?php
namespace Kanboard\Plugin\FamilyHub\Model;

/** Authenticated immutable documents. No filenames, bytes or tokens in public paths. */
class NativeAttachmentService extends NativeDocumentService
{
    const CHUNK=262144;
    const MAX_BYTES=20971520;
    const SCOPE_BYTES=268435456;
    const MIME=[
        'pdf'=>'application/pdf','doc'=>'application/msword','docx'=>'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
        'odt'=>'application/vnd.oasis.opendocument.text','xls'=>'application/vnd.ms-excel','xlsx'=>'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
        'ods'=>'application/vnd.oasis.opendocument.spreadsheet','txt'=>'text/plain','csv'=>'text/csv','rtf'=>'application/rtf','png'=>'image/png','jpg'=>'image/jpeg','jpeg'=>'image/jpeg',
    ];
    public function execute($operation,array $p)
    {
        $action=substr($operation,12);if (!in_array($action,['list','begin','chunk','complete','get','delete'],true)) { throw new NativeError('unsupported_operation',404); }
        $this->documentGate();
        $result=$this->transaction(function()use($operation,$action,$p){
            $required=['scopeId','targetType','targetId'];$optional=[];
            if ($action!=='list') { $required[]='id'; }
            if ($action==='begin') { $required=array_merge($required,['name','mime','size','sha256','requestId']); }
            if (in_array($action,['complete','delete'],true)) { $required[]='requestId'; }
            if ($action==='chunk') { $required=array_merge($required,['offset','dataBase64']); }
            if ($action==='get') { $optional=['offset','limit']; }
            $this->fields($p,$required,$optional);$actor=$this->actor();$sid=$this->uuid($p['scopeId']);$target=$this->uuid($p['targetId']);$type=$p['targetType'];
            $write=!in_array($action,['list','get'],true);$scope=$this->scope($sid,$actor['user']['id'],$write);$this->target($scope,$type,$target,$write);
            if ($write) { (new NativeModerationService($this->container,$this->bearer,$this->ip))->guardWrite($operation,$p); }
            if ($action==='list') { return ['attachments'=>array_map(fn($r)=>$this->wire($r),$this->many('SELECT * FROM familyhub_attachments WHERE scope_id=? AND target_type=? AND target_id=? AND complete=1 AND deleted=0 ORDER BY created_at,id LIMIT 100',[$sid,$type,$target]))]; }
            $id=$this->uuid($p['id']);$r=$this->one('SELECT * FROM familyhub_attachments WHERE scope_id=? AND id=?'.$this->lockSuffix(),[$sid,$id]);
            if ($r && ($r['target_type']!==$type || $r['target_id']!==$target)) { throw new NativeError('attachment_unavailable',404); }
            $request=isset($p['requestId'])?$this->uuid($p['requestId']):null;$hash=$request?$this->hashRequest($operation,$p):null;
            $saved=$request?$this->receipt($sid,$actor,$request,$hash):null;
            if ($saved) {
                if (($saved['deleted']??false)===true) { return $saved; }
                if (!$r || (int)$r['deleted']) { throw new NativeError('attachment_unavailable',404); }
                if (!(int)$r['complete'] && !$this->uploadHolder($r,$actor)) { throw new NativeError('attachment_unavailable',404); }
                if ($action==='complete') { $this->bytes($r); }
                return ['attachment'=>$this->wire($r)];
            }
            if ($action==='begin') {
                $this->metadata($p);
                if ($r) { throw new NativeError('attachment_conflict',409); }
                $quota=$this->one('SELECT COALESCE(SUM(size),0) AS bytes,COUNT(*) AS n FROM familyhub_attachments WHERE scope_id=? AND deleted=0',[$sid]);
                $count=$this->one('SELECT COUNT(*) AS n FROM familyhub_attachments WHERE scope_id=? AND target_type=? AND target_id=? AND deleted=0',[$sid,$type,$target]);
                if ((int)$quota['bytes']+$p['size']>self::SCOPE_BYTES || (int)$quota['n']>=1000) { throw new NativeError('attachment_scope_limit',422); }
                if ((int)$count['n']>=100) { throw new NativeError('attachment_target_limit',422); }
                $this->change('INSERT INTO familyhub_attachments(scope_id,id,target_type,target_id,name,mime,size,sha256,owner_account_id,owner_device_id,created_at,updated_at) VALUES(?,?,?,?,?,?,?,?,?,?,?,?)',[$sid,$id,$type,$target,$p['name'],$p['mime'],$p['size'],$p['sha256'],$actor['user']['account_id'],$actor['device']['id'],time(),time()]);
                $r=$this->one('SELECT * FROM familyhub_attachments WHERE scope_id=? AND id=?',[$sid,$id]);$result=['attachment'=>$this->wire($r)];
            } else {
                if (!$r || (int)$r['deleted'] || (!(int)$r['complete'] && !$this->uploadHolder($r,$actor))) { throw new NativeError('attachment_unavailable',404); }
                if ($action==='get') {
                    if (!(int)$r['complete']) { throw new NativeError('attachment_unavailable',404); }
                    $offset=$p['offset']??0;$limit=$p['limit']??self::CHUNK;
                    if (!is_int($offset) || $offset<0 || $offset>(int)$r['size'] || !is_int($limit) || $limit<1 || $limit>self::CHUNK) { throw new NativeError('validation_error'); }
                    $bytes=$this->bytes($r);$chunk=substr($bytes,$offset,$limit);return ['attachment'=>$this->wire($r),'offset'=>$offset,'dataBase64'=>base64_encode($chunk),'total'=>(int)$r['size'],'done'=>$offset+strlen($chunk)===(int)$r['size']];
                }
                if ($action==='delete') {
                    $this->removeRow($r);$result=['deleted'=>true];
                } else {
                    if (!$this->uploadHolder($r,$actor)) { throw new NativeError('attachment_unavailable',404); }
                    if ($action==='chunk') {
                        $offset=$p['offset'];$encoded=$p['dataBase64'];
                        if (!is_int($offset) || $offset<0 || !is_string($encoded) || strlen($encoded)>349528) { throw new NativeError('validation_error'); }
                        $bytes=base64_decode($encoded,true);
                        if ($bytes===false || strlen($bytes)<1 || strlen($bytes)>self::CHUNK || base64_encode($bytes)!==$encoded || $offset+strlen($bytes)>(int)$r['size']) { throw new NativeError('validation_error'); }
                        if ($offset<(int)$r['received'] || (int)$r['complete']) {
                            $existing=(int)$r['complete']?substr($this->bytes($r),$offset,strlen($bytes)):null;
                            if ($existing===null) { $c=$this->one('SELECT data FROM familyhub_attachment_chunks WHERE scope_id=? AND attachment_id=? AND chunk_offset=?',[$sid,$id,$offset]);$existing=$c?base64_decode($c['data'],true):false; }
                            if (!is_string($existing) || !hash_equals($existing,$bytes)) { throw new NativeError('attachment_chunk_conflict',409); }
                            return ['attachment'=>$this->wire($r)];
                        }
                        if ($offset!==(int)$r['received']) { throw new NativeError('attachment_offset',409,['offset'=>(int)$r['received']]); }
                        $this->change('INSERT INTO familyhub_attachment_chunks VALUES(?,?,?,?)',[$sid,$id,$offset,$encoded]);$r['received']+=strlen($bytes);
                        $this->change('UPDATE familyhub_attachments SET received=?,updated_at=? WHERE scope_id=? AND id=?',[$r['received'],time(),$sid,$id]);$result=['attachment'=>$this->wire($r)];
                    } else {
                        if (!(int)$r['complete']) {
                            if ((int)$r['received']!==(int)$r['size']) { throw new NativeError('attachment_incomplete',409,['offset'=>(int)$r['received']]); }
                            $bytes='';foreach ($this->many('SELECT chunk_offset,data FROM familyhub_attachment_chunks WHERE scope_id=? AND attachment_id=? ORDER BY chunk_offset',[$sid,$id]) as $c) { if ((int)$c['chunk_offset']!==strlen($bytes)) { throw new NativeError('attachment_integrity',422); }$part=base64_decode($c['data'],true);if ($part===false) { throw new NativeError('attachment_integrity',422); }$bytes.=$part; }
                            $this->integrity($bytes,$r);$this->signature($bytes,$r);$this->store($r,$bytes);
                            $this->change('UPDATE familyhub_attachments SET complete=1,updated_at=? WHERE scope_id=? AND id=?',[time(),$sid,$id]);$this->change('DELETE FROM familyhub_attachment_chunks WHERE scope_id=? AND attachment_id=?',[$sid,$id]);$r['complete']=1;
                        } else { $this->bytes($r); }
                        $result=['attachment'=>$this->wire($r)];
                    }
                }
            }
            if ($request) { $this->rememberDocument($sid,$actor,$request,$hash,$id,$result); }return $result;
        });
        if ($action==='delete') { $this->finishFiles(); }return $result;
    }
    private function target($scope,$type,$id,$write)
    {
        if (!in_array($type,['scope','task','table'],true)) { throw new NativeError('validation_error'); }
        if ($type==='scope') { if ($id!==$scope['id']) { throw new NativeError('attachment_target_unavailable',404); }$root=$scope['project_root_id']??(!empty($scope['organization_id'])?$scope['id']:null);if ($write && $root!==null) { (new NativeRecordPolicy($this->container))->guardProjectMutation($scope['id'],'task',['projectId'=>$root]); }return; }
        if ($type==='table') {
            if ($scope['kind']!=='organization' || !$this->one('SELECT id FROM familyhub_tables WHERE scope_id=? AND id=? AND deleted=0',[$scope['id'],$id])) { throw new NativeError('attachment_target_unavailable',404); }return;
        }
        $r=$this->one("SELECT * FROM familyhub_records WHERE scope_id=? AND id=? AND type='task' AND deleted=0",[$scope['id'],$id]);
        if (!$r) { throw new NativeError('attachment_target_unavailable',404); }
        $payload=json_decode($r['payload'],true,32,JSON_THROW_ON_ERROR);$pid=$payload['projectId']??null;
        if ($pid!==null && !$this->one("SELECT id FROM familyhub_records WHERE scope_id=? AND id=? AND type='project' AND deleted=0",[$scope['id'],$pid])) { throw new NativeError('attachment_target_unavailable',404); }
        if ($write) { (new NativeRecordPolicy($this->container))->guardProjectMutation($scope['id'],'task',$payload,$r); }
    }
    private function metadata($p)
    {
        $this->text($p['name'],240);$name=$p['name'];$ext=strtolower(pathinfo($name,PATHINFO_EXTENSION));
        if (str_starts_with($name,'.') || trim($name)!==$name || preg_match('/[\\\\\/\x00-\x1f\x7f\x{202a}-\x{202e}\x{2066}-\x{2069}]/u',$name) || !isset(self::MIME[$ext]) || $p['mime']!==self::MIME[$ext] || !is_int($p['size']) || $p['size']<1 || $p['size']>self::MAX_BYTES || !is_string($p['sha256']) || !preg_match('/^[a-f0-9]{64}$/D',$p['sha256'])) { throw new NativeError('validation_error'); }
    }
    private function wire($r) { return ['id'=>$r['id'],'scopeId'=>$r['scope_id'],'targetType'=>$r['target_type'],'targetId'=>$r['target_id'],'name'=>$r['name'],'mime'=>$r['mime'],'size'=>(int)$r['size'],'sha256'=>$r['sha256'],'createdAt'=>(int)$r['created_at'],'complete'=>(bool)$r['complete'],'offset'=>(int)$r['received']]; }
    private function uploadHolder($r,$a) { return $r['owner_account_id']===$a['user']['account_id'] && $r['owner_device_id']===$a['device']['id']; }
    private function key($r) { return hash('sha256',$r['scope_id'].':'.$r['id']); }
    /** Verify every directory component rather than following a replaced parent symlink. */
    private function root($create=false)
    {
        $base=realpath(DATA_DIR);if ($base===false || is_link(DATA_DIR)) { throw new NativeError('attachment_storage_unavailable',503); }
        foreach (['familyhub','attachments'] as $part) {
            $base.='/'.$part;if (is_link($base)) { throw new NativeError('attachment_storage_unavailable',503); }
            if (!is_dir($base) && (!$create || (!@mkdir($base,0700) && !is_dir($base)))) { throw new NativeError('attachment_storage_unavailable',503); }
            if (realpath($base)!==$base) { throw new NativeError('attachment_storage_unavailable',503); }
        }return $base;
    }
    private function integrity($bytes,$r) { if (!is_string($bytes) || strlen($bytes)!==(int)$r['size'] || !hash_equals($r['sha256'],hash('sha256',$bytes))) { throw new NativeError('attachment_integrity',422); } }
    private function bytes($r)
    {
        $path=$this->root().'/'.$this->key($r);if (is_link($path) || !is_file($path)) { throw new NativeError('attachment_storage_unavailable',503); }
        $bytes=@file_get_contents($path);$this->integrity($bytes,$r);return $bytes;
    }
    private function store($r,$bytes)
    {
        $root=$this->root(true);$path=$root.'/'.$this->key($r);if (is_link($path)) { throw new NativeError('attachment_storage_unavailable',503); }
        if (is_file($path)) { $this->integrity(@file_get_contents($path),$r);return; }
        $temp=@tempnam($root,'.upload-');if ($temp===false) { throw new NativeError('attachment_storage_unavailable',503); }
        try { if (!@chmod($temp,0600) || @file_put_contents($temp,$bytes)!==strlen($bytes) || !@rename($temp,$path)) { throw new NativeError('attachment_storage_unavailable',503); } }
        finally { if (is_file($temp)) { @unlink($temp); } }
    }
    private function signature($bytes,$r)
    {
        $ext=strtolower(pathinfo($r['name'],PATHINFO_EXTENSION));$valid=false;
        $detected=class_exists('finfo')?(new \finfo(FILEINFO_MIME_TYPE))->buffer($bytes):null;
        if ($ext==='pdf') { $valid=str_starts_with($bytes,'%PDF-') && preg_match('/%%EOF\s*$/D',substr($bytes,-2048)); }
        elseif (in_array($ext,['txt','csv'],true)) { $valid=mb_check_encoding($bytes,'UTF-8') && !str_contains($bytes,"\0") && ($detected===null || in_array($detected,['text/plain','text/csv','application/csv'],true)); }
        elseif ($ext==='rtf') { $valid=str_starts_with($bytes,'{\\rtf') && ($detected===null || in_array($detected,['text/rtf','application/rtf'],true)) && str_ends_with(rtrim($bytes),'}'); }
        elseif (in_array($ext,['doc','xls'],true)) {
            $valid=str_starts_with($bytes,"\xd0\xcf\x11\xe0\xa1\xb1\x1a\xe1") && ($detected===null || in_array($detected,[$r['mime'],'application/CDFV2','application/x-ole-storage'],true));
            $stream=$ext==='doc'?'WordDocument':'Workbook';$valid=$valid && str_contains($bytes,mb_convert_encoding($stream,'UTF-16LE','UTF-8'));
        }
        elseif (in_array($ext,['png','jpg','jpeg'],true)) { $info=@getimagesizefromstring($bytes);$valid=$info && ($info['mime']??null)===$r['mime'] && ($detected===null || $detected===$r['mime']) && $info[0]>0 && $info[1]>0 && $info[0]<=20000 && $info[1]<=20000 && $info[0]*$info[1]<=40000000; }
        elseif (in_array($ext,['docx','xlsx','odt','ods'],true)) { $valid=$this->officeZip($bytes,$ext,$r['mime']); }
        if (!$valid) { throw new NativeError('attachment_type_mismatch',422); }
    }
    private function officeZip($bytes,$ext,$mime)
    {
        if (!class_exists('ZipArchive') || !str_starts_with($bytes,"PK\x03\x04")) { return false; }
        $temp=@tempnam($this->root(true),'.inspect-');if ($temp===false) { throw new NativeError('attachment_storage_unavailable',503); }if (!@chmod($temp,0600) || @file_put_contents($temp,$bytes)!==strlen($bytes)) { @unlink($temp);throw new NativeError('attachment_storage_unavailable',503); }$zip=new \ZipArchive();$opened=false;
        try {
            if (!(($opened=@$zip->open($temp)===true)) || $zip->numFiles>2048) { return false; }$total=0;
            for ($i=0;$i<$zip->numFiles;$i++) {
                $s=$zip->statIndex($i);$name=$s['name'];$total+=$s['size'];
                if ($total>104857600 || $s['size']>20971520 || ($s['comp_size']>0 && $s['size']/$s['comp_size']>1000) || preg_match('~(^/|(^|/)\.\.(/|$)|\\\\|\x00|vbaProject|\.exe$|\.dll$|\.bin$)~i',$name) || !empty($s['encryption_method'])) { return false; }
            }
            if (in_array($ext,['odt','ods'],true)) {
                $entry=@$zip->statName('mimetype');$length=strlen($mime);
                // Bound decompression independently of ZIP-advertised sizes.
                return $entry!==false && $entry['size']===$length && @$zip->getFromName('mimetype',$length+1)===$mime && $zip->locateName('content.xml')!==false;
            }
            return $zip->locateName('[Content_Types].xml')!==false && $zip->locateName($ext==='docx'?'word/document.xml':'xl/workbook.xml')!==false;
        } finally { if ($opened) { $zip->close(); }@unlink($temp); }
    }
    /** Reports retain metadata and exact live context, never document bytes. */
    public function moderationEvidence($scope,$id)
    {
        if (!$this->available() || ($scope['deleted_at']??null)!==null) { throw new NativeError('report_target_unavailable',404); }
        $r=$this->one('SELECT * FROM familyhub_attachments WHERE scope_id=? AND id=? AND deleted=0 AND complete=1',[$scope['id'],$id]);if (!$r) { throw new NativeError('report_target_unavailable',404); }
        try { $this->target($scope,$r['target_type'],$r['target_id'],false); } catch (NativeError $e) { throw new NativeError('report_target_unavailable',404); }
        $context=['type'=>$r['target_type'],'id'=>$r['target_id']];
        if ($r['target_type']==='scope') { $context['name']=$scope['name'];$context['revision']=(int)($scope['metadata_revision']??0); }
        elseif ($r['target_type']==='table') { $parent=$this->one('SELECT title,revision FROM familyhub_tables WHERE scope_id=? AND id=?',[$scope['id'],$r['target_id']]);$context['name']=$parent['title'];$context['revision']=(int)$parent['revision']; }
        else { $parent=$this->one('SELECT payload,revision FROM familyhub_records WHERE scope_id=? AND id=?',[$scope['id'],$r['target_id']]);$context['name']=json_decode($parent['payload'],true,32,JSON_THROW_ON_ERROR)['title'];$context['revision']=(int)$parent['revision']; }
        $evidence=['id'=>$id,'type'=>'attachment','scopeId'=>$scope['id'],'revision'=>1,'title'=>$r['name'],'attachment'=>$this->wire($r),'context'=>$context];$evidence['documentHash']=hash('sha256',$this->canonical($evidence));return $evidence;
    }
    public function removeInTransaction($sid,$id)
    {
        $r=$this->one('SELECT * FROM familyhub_attachments WHERE scope_id=? AND id=? AND deleted=0',[$sid,$id]);if (!$r) { throw new NativeError('report_target_unavailable',404); }$this->removeRow($r);
    }
    /** Called inside the enclosing task/table/scope deletion transaction. */
    public function removeTarget($sid,$type,$id,$operation=null)
    {
        if (!$this->available()) { return; }
        foreach ($this->many('SELECT * FROM familyhub_attachments WHERE scope_id=? AND target_type=? AND target_id=? AND deleted=0',[$sid,$type,$id]) as $r) { $this->removeRow($r,$operation); }
    }
    private function removeRow($r,$operation=null)
    {
        $key=$this->key($r);
        if ($operation!==null) { $path='familyhub/attachments/'.$key;if (!$this->one('SELECT path_hash FROM familyhub_deletion_files WHERE operation_id=? AND path_hash=?',[$operation,hash('sha256',$path)])) { $this->change('INSERT INTO familyhub_deletion_files(operation_id,path_hash,path) VALUES(?,?,?)',[$operation,hash('sha256',$path),$path]); } }
        if (!$this->one('SELECT storage_key FROM familyhub_document_cleanup WHERE storage_key=?',[$key])) { $this->change('INSERT INTO familyhub_document_cleanup VALUES(?,?)',[$key,time()]); }
        $this->change("UPDATE familyhub_attachments SET deleted=1,name='',mime='',size=0,sha256='',received=0,complete=0,created_at=0,owner_account_id='',owner_device_id='',updated_at=? WHERE scope_id=? AND id=?",[time(),$r['scope_id'],$r['id']]);
        $this->change('DELETE FROM familyhub_attachment_chunks WHERE scope_id=? AND attachment_id=?',[$r['scope_id'],$r['id']]);
        $this->change('DELETE FROM familyhub_document_requests WHERE scope_id=? AND object_id=?',[$r['scope_id'],$r['id']]);
    }
    public function removeScope($sid,$operation=null)
    {
        if (!$this->available()) { return; }
        foreach ($this->many('SELECT * FROM familyhub_attachments WHERE scope_id=? AND deleted=0',[$sid]) as $r) { $this->removeRow($r,$operation); }
        $this->change("UPDATE familyhub_tables SET deleted=1,title='',cells='{}',lease_hash=NULL,lease_nonce=NULL,lease_account_id=NULL,lease_device_id=NULL,lease_name=NULL,lease_expires=0 WHERE scope_id=?",[$sid]);
        $this->change('DELETE FROM familyhub_document_requests WHERE scope_id=?',[$sid]);
    }
    public function removeAccount($user,$deleteScopes,$operation=null)
    {
        if (!$this->available()) { return; }
        foreach ($this->many('SELECT * FROM familyhub_scopes WHERE kind=\'personal\' AND owner_id=?',[$user['id']]) as $s) { $deleteScopes[]=$s['id']; }
        foreach (array_unique($deleteScopes) as $sid) { $this->removeScope($sid,$operation);$this->change('DELETE FROM familyhub_attachments WHERE scope_id=?',[$sid]);$this->change('DELETE FROM familyhub_tables WHERE scope_id=?',[$sid]); }
        foreach ($this->many('SELECT * FROM familyhub_attachments WHERE owner_account_id=? AND deleted=0',[$user['account_id']]) as $r) {
            $targetAlive=$r['target_type']==='scope' || ($r['target_type']==='table'?$this->one('SELECT id FROM familyhub_tables WHERE scope_id=? AND id=? AND deleted=0',[$r['scope_id'],$r['target_id']]):$this->one("SELECT id FROM familyhub_records WHERE scope_id=? AND id=? AND type='task' AND deleted=0",[$r['scope_id'],$r['target_id']]));
            if (!(int)$r['complete'] || !$targetAlive) { $this->removeRow($r,$operation); }
            else { $this->change("UPDATE familyhub_attachments SET owner_account_id='',owner_device_id='' WHERE scope_id=? AND id=?",[$r['scope_id'],$r['id']]); }
        }
        $this->change("UPDATE familyhub_tables SET created_by='' WHERE created_by=?",[$user['account_id']]);
        $this->change('UPDATE familyhub_tables SET lease_hash=NULL,lease_nonce=NULL,lease_account_id=NULL,lease_device_id=NULL,lease_name=NULL,lease_expires=0 WHERE lease_account_id=?',[$user['account_id']]);
        $this->change('DELETE FROM familyhub_document_requests WHERE account_id=?',[$user['account_id']]);
    }
    /** Move task documents with a closed project extraction and a separate immutable destination key. */
    public function relocateTarget($source,$target,$type,$id)
    {
        if (!$this->available()) { return; }
        foreach ($this->many('SELECT * FROM familyhub_attachments WHERE scope_id=? AND target_type=? AND target_id=? AND deleted=0',[$source,$type,$id]) as $r) {
            if (!(int)$r['complete']) { $this->removeRow($r);continue; }
            $bytes=$this->bytes($r);$copy=$r;$copy['scope_id']=$target;$this->store($copy,$bytes);
            $columns=array_keys($copy);$this->change('INSERT INTO familyhub_attachments('.implode(',',$columns).') VALUES('.implode(',',array_fill(0,count($columns),'?')).')',array_values($copy));$this->removeRow($r);
        }
    }
    /** Exact private leaf cleanup, also shared by account-specific deletion receipts. */
    public function finishStorageKey($key)
    {
        if (!preg_match('/^[a-f0-9]{64}$/D',$key)) { return false; }
        try { $path=$this->root(true).'/'.$key; } catch (NativeError $e) { return false; }
        if ((file_exists($path)||is_link($path)) && !@unlink($path)) { return false; }
        return !file_exists($path) && !is_link($path);
    }
    public function finishFiles()
    {
        $cryptoLease=\Kanboard\Plugin\FamilyHub\Schema\CryptoSchema::ready($this->pdo)?NativeCryptoMaintenanceLease::acquire():null;
        if(NativeCryptoFence::cleanupPaused($this->pdo)){return 0;}
        if (!$this->available()) { return 0; }$removed=0;
        foreach ($this->many('SELECT storage_key FROM familyhub_document_cleanup ORDER BY created_at LIMIT 100') as $r) {
            if (!$this->finishStorageKey($r['storage_key'])) { continue; }
            $this->change('DELETE FROM familyhub_document_cleanup WHERE storage_key=?',[$r['storage_key']]);$removed++;
        }return $removed;
    }
    /** Worker retry + expired staging + crash-orphan files; never age out a live complete attachment. */
    public function cleanup()
    {
        $cryptoLease=\Kanboard\Plugin\FamilyHub\Schema\CryptoSchema::ready($this->pdo)?NativeCryptoMaintenanceLease::acquire():null;
        if(NativeCryptoFence::cleanupPaused($this->pdo)){return 0;}
        if (!$this->available()) { return 0; }
        $this->transaction(function(){foreach ($this->many('SELECT * FROM familyhub_attachments WHERE deleted=0 AND complete=0 AND updated_at<? ORDER BY updated_at LIMIT 100',[time()-7*86400]) as $r) { $this->lockScopeLifecycle($r['scope_id']);$fresh=$this->one('SELECT * FROM familyhub_attachments WHERE scope_id=? AND id=?'.$this->lockSuffix(),[$r['scope_id'],$r['id']]);if ($fresh && !(int)$fresh['deleted'] && !(int)$fresh['complete'] && (int)$fresh['updated_at']<time()-7*86400) { $this->removeRow($fresh); } }});
        $removed=$this->finishFiles();try { $root=$this->root(); } catch (NativeError $e) { return $removed; }
        // One bounded deterministic page per invocation, rotating the durable cursor file.
        $cursorFile=$root.'/.cleanup-cursor';$cursor=!is_link($cursorFile)&&is_file($cursorFile)?(@file_get_contents($cursorFile)?:''):'';$files=array_merge(glob($root.'/*')?:[],glob($root.'/.upload-*')?:[],glob($root.'/.inspect-*')?:[]);sort($files,SORT_STRING);$seen=0;$last='';
        foreach ($files as $path) { $name=basename($path);if (strcmp($name,$cursor)<=0) { continue; }$last=$name;$seen++;
            if (!is_link($path) && is_file($path) && @filemtime($path)<time()-7*86400) {
                $known=false;foreach ($this->many('SELECT scope_id,id FROM familyhub_attachments WHERE deleted=0 AND complete=1') as $r) { if (hash_equals($this->key($r),$name)) { $known=true;break; } }
                if (!$known && @unlink($path)) { $removed++; }
            }if ($seen>=100) { break; }
        }
        if ($seen<100) { $last=''; }$temp=@tempnam($root,'.cursor-');if ($temp!==false) { @chmod($temp,0600);@file_put_contents($temp,$last);if (!is_link($cursorFile)) { @rename($temp,$cursorFile); }if (is_file($temp)) { @unlink($temp); } }return $removed;
    }
}
