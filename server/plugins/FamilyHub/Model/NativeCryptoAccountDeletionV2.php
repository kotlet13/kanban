<?php
namespace Kanboard\Plugin\FamilyHub\Model;

/** Password/OTP deletion is deliberately independent of E2EE device/file keys. */
class NativeCryptoAccountDeletionV2 extends NativeAccountDeletionService
{
    public function hasCryptoUser($id)
    {
        $a=$this->one('SELECT account_id FROM familyhub_accounts WHERE user_id=?',[(int)$id]);
        if(!$a){return false;}
        if(NativeCryptoV2Boundary::account($this->pdo,$a['account_id'])){return true;}
        foreach($this->many('SELECT id FROM familyhub_scopes WHERE owner_id=? OR id IN (SELECT scope_id FROM familyhub_members WHERE user_id=?)',[(int)$id,(int)$id]) as $s){if(NativeCryptoV2Boundary::scope($this->pdo,$s['id'])){return true;}}
        return false;
    }
    public function execute($operation,array $p)
    {
        if(in_array($operation,['account.deletion.status','account.deletion.cancelPending'],true)){return parent::execute($operation,$p);}
        if(!self::available()){throw new NativeError('feature_disabled',503);}
        if(!in_array($operation,['account.deletion.preview','account.deletion.confirm'],true)){throw new NativeError('unsupported_operation',404);}
        $actor=$this->actor(false);
        $this->rate([['account-delete-ip:'.$this->ip,120,60],[$operation.':'.$actor['user']['account_id'],$operation==='account.deletion.preview'?60:10,$operation==='account.deletion.preview'?60:900]]);
        $result=$this->transaction(function()use($operation,$p){
            $user=$this->actor()['user'];
            $this->many('SELECT id FROM users ORDER BY id'.$this->lockSuffix());
            $scopes=$this->many("SELECT * FROM familyhub_scopes WHERE deleted_at IS NULL ORDER BY CASE WHEN kind='organization' THEN 0 ELSE 1 END,id".$this->lockSuffix());
            $graph=$this->plan($user,$scopes);$wire=$graph['wire'];
            if($operation==='account.deletion.preview'){
                $this->fields($p,[],['policyVersion']);
                if(($p['policyVersion']??0)!==4){throw new NativeError('client_upgrade_required',409);}
                return $wire;
            }
            $this->fields($p,['operationId','receiptToken','previewHash','password','confirmation','policyVersion','cryptoResolutions'],['otp','ownershipTransfers','resolutions','ownedScopeDeletions']);
            if($p['policyVersion']!==4||$p['confirmation']!=='DELETE'){throw new NativeError('validation_error');}
            $operationId=$this->uuid($p['operationId']);$tokenHash=$this->receiptHash($p['receiptToken']);
            $old=$this->one('SELECT token_hash,cancelled FROM familyhub_deletion_receipts WHERE operation_id=?',[$operationId]);
            if($old){throw new NativeError(hash_equals($old['token_hash'],$tokenHash)&&(int)$old['cancelled']===1?'deletion_cancelled':'idempotency_mismatch',409);}
            if(!is_string($p['previewHash'])||!hash_equals($wire['previewHash'],$p['previewHash'])){throw new NativeError('deletion_preview_stale',409);}
            if(array_filter($wire['blockers'],fn($b)=>$b['code']==='crypto_migration_in_progress')){throw new NativeError('deletion_blocked',409,['blockers'=>$wire['blockers']]);}
            $this->resolutions($wire,$p['cryptoResolutions']);
            $legacy=$wire;$legacy['policyVersion']=$graph['legacyPolicyVersion'];
            $deleteScopes=$this->resolve($legacy,$p,$user);
            $error=(new NativeAuthService($this->container))->stepUp($user,$p['password'],$p['otp']??null);
            if($error){return $error;}
            $this->change('INSERT INTO familyhub_deletion_receipts(operation_id,token_hash,deleted_at) VALUES(?,?,?)',[$operationId,$tokenHash,time()]);
            $this->applyLegacyTransfers($p,$user);
            $this->applyShared($graph,$user,$deleteScopes,$operationId);
            $this->queueIdeaFiles($operationId,$user,$deleteScopes);
            (new NativeAttachmentService($this->container))->removeAccount($user,$deleteScopes,$operationId);
            // Private ciphertext removal and shared evidence preservation are
            // one transaction with the original users FK deletion.
            foreach($p['cryptoResolutions'] as $r){if($r['action']==='deletePrivate'){$this->erasePrivate($r['scopeId']);}}
            $retained=array_values(array_filter($graph['cryptoScopes'],fn($s)=>!in_array($s['id'],array_column(array_filter($p['cryptoResolutions'],fn($r)=>$r['action']==='deletePrivate'),'scopeId'),true)));
            (new NativeCryptoAccountTombstoneV2($this->container))->preserve($user,$operationId,$retained);
            $this->purge($user,$graph['legacyScopes'],$deleteScopes);
            $this->purgeLegacy($user,$graph['privateProjects'],$operationId);
            return ['operationId'=>$operationId];
        },true);
        if($result instanceof NativeError){throw $result;}
        return isset($result['operationId'])?$this->finishFiles($result['operationId']):$result;
    }
    private function resolutions($wire,$rows)
    {
        if(!is_array($rows)||!array_is_list($rows)||count($rows)!==count($wire['cryptoScopes'])){throw new NativeError('validation_error');}
        $seen=[];
        foreach($rows as $r){
            $this->fields($r,['scopeId','action','headHash','accessRevision']);
            $id=$this->uuid($r['scopeId']);
            $matched=array_values(array_filter($wire['cryptoScopes'],fn($s)=>$s['scopeId']===$id));
            if(isset($seen[$id])||count($matched)!==1||!in_array($r['action'],$matched[0]['allowedActions'],true)||$r['headHash']!==$matched[0]['headHash']||$r['accessRevision']!==$matched[0]['accessRevision']){throw new NativeError('deletion_preview_stale',409);}
            $seen[$id]=true;
        }
    }
    private function plan($user,$scopes)
    {
        $crypto=[];$legacy=[];$account=$user['account_id'];$uid=(int)$user['id'];
        foreach($scopes as $s){
            if(!NativeCryptoV2Boundary::scope($this->pdo,$s['id'])){$legacy[]=$s;continue;}
            $head=$this->one('SELECT * FROM familyhub_crypto_scope_state WHERE scope_id=?',[$s['id']]);
            $members=$head?$this->one('SELECT payload FROM familyhub_crypto_scope_heads WHERE scope_id=? AND head_hash=?',[$s['id'],$head['head_hash']]):null;
            $body=$members?json_decode($members['payload'],true,34,JSON_THROW_ON_ERROR):null;
            $member=null;foreach($body['members']??[] as $m){if($m['accountId']===$account){$member=$m;break;}}
            $sqlMember=$this->one('SELECT role FROM familyhub_members WHERE scope_id=? AND account_id=?',[$s['id'],$account]);
            $related=$member||$sqlMember||(int)$s['owner_id']===$uid;
            // An inaccessible descendant still depends on the departing owner
            // as bookkeeping; it is retained without disclosing its roster.
            if(!$related){continue;}
            $private=$this->privateOwned($s,$user);
            $crypto[]=$s+['_head'=>$head,'_member'=>$member,'_private'=>$private];
        }
        $this->retainedCryptoScopeIds=array_column(array_filter($scopes,fn($s)=>NativeCryptoV2Boundary::scope($this->pdo,$s['id'])),'id');
        $graph=(new NativeDeletionPlan($this->container))->build($user,$legacy);
        $wire=$graph['wire'];$graph['legacyPolicyVersion']=$wire['policyVersion'];$wire['policyVersion']=4;
        $wire['cryptoScopes']=array_map(fn($s)=>[
            'scopeId'=>$s['id'],'kind'=>$s['kind'],'role'=>$s['_member']['role']??((int)$s['owner_id']===$uid?'owner':'member'),
            'headHash'=>$s['_head']['head_hash']??null,'accessRevision'=>(int)$s['access_revision'],
            'memberCount'=>$s['_head']?count(json_decode($this->one('SELECT payload FROM familyhub_crypto_scope_heads WHERE scope_id=? AND head_hash=?',[$s['id'],$s['_head']['head_hash']])['payload'],true,34,JSON_THROW_ON_ERROR)['members']):1,
            'privateOwned'=>$s['_private'],'allowedActions'=>$s['_private']?['deletePrivate','preserveReadOnly']:['preserveReadOnly'],
        ],$crypto);
        $wire['cryptoRetention']=['version'=>1,'retainsSharedSignedEvidence'=>true,'mayRetainEncryptedWrappers'=>true,'mayRetainEncryptedHistoricalBackups'=>true,'mayRetainLegacyMigrationSources'=>true,'erasesOtherKeyCopies'=>false,'requiresFutureScopeRotation'=>true];
        $wire['legacyCleanupPending']=(bool)array_filter($crypto,fn($s)=>(new NativeCryptoScopeDeletionV2($this->container))->retainedLegacySources($s['id']));
        $wire['impact']['cryptoScopesRetainedIfSelected']=count($crypto);
        foreach($crypto as $affected){if(in_array(NativeCryptoFence::state($this->pdo,$affected['id']),['fenced','verified'],true)){$wire['blockers'][]=['code'=>'crypto_migration_in_progress','scopeId'=>$affected['id'],'count'=>1];$wire['canDelete']=false;}}
        $wire['previewHash']=hash('sha256',$this->canonical([$wire,$this->fingerprint($user)]));
        $graph['wire']=$wire;$graph['cryptoScopes']=$crypto;$graph['legacyScopes']=$legacy;return $graph;
    }
    private function privateOwned($s,$user)
    {
        if((int)$s['owner_id']!==(int)$user['id']||$s['kind']!=='personal'){return false;}
        if($this->one('SELECT id FROM familyhub_scopes WHERE deleted_at IS NULL AND (parent_scope_id=? OR organization_id=?) LIMIT 1',[$s['id'],$s['id']])){return false;}
        foreach($this->many('SELECT payload FROM familyhub_crypto_scope_heads WHERE scope_id=?',[$s['id']]) as $h){foreach(json_decode($h['payload'],true,34,JSON_THROW_ON_ERROR)['members'] as $m){if($m['accountId']!==$user['account_id']){return false;}}}
        if($this->one('SELECT account_id FROM familyhub_crypto_grant_entries_v2 WHERE scope_id=? AND account_id<>? LIMIT 1',[$s['id'],$user['account_id']])){return false;}
        if($this->one('SELECT id FROM familyhub_moderation_reports WHERE scope_id=? AND reporter_account_id<>? LIMIT 1',[$s['id'],$user['account_id']])){return false;}
        if($this->one('SELECT hash FROM familyhub_crypto_export_offers_v2 WHERE source_scope_id=? LIMIT 1',[$s['id']])){return false;}
        // Public references and immutable history can retain a private source.
        foreach($this->iterate('SELECT metadata FROM familyhub_crypto_records WHERE scope_id<>?',[$s['id']]) as $r){foreach(json_decode($r['metadata'],true,34,JSON_THROW_ON_ERROR)['references']??[] as $ref){if(($ref['scopeId']??null)===$s['id']){return false;}}}
        foreach($this->iterate('SELECT record_proof FROM familyhub_crypto_record_history WHERE scope_id<>?',[$s['id']]) as $r){[$b]=NativeCryptoCodec::decode(json_decode($r['record_proof'],true,34,JSON_THROW_ON_ERROR));foreach($b['metadata']['references']??[] as $ref){if(($ref['scopeId']??null)===$s['id']){return false;}}}
        return true;
    }
    private function erasePrivate($sid)
    {
        (new NativeCryptoScopeDeletionV2($this->container))->erasePrivateData($sid);
    }
    private function applyLegacyTransfers($p,$user)
    {
        foreach($p['ownershipTransfers']??[] as $t){$next=$this->one('SELECT user_id FROM familyhub_accounts WHERE account_id=?',[$t['successorAccountId']]);
            $this->change("UPDATE familyhub_members SET role='member' WHERE scope_id=? AND user_id=?",[$t['scopeId'],$user['id']]);
            $this->change('DELETE FROM familyhub_members WHERE scope_id=? AND user_id=?',[$t['scopeId'],$next['user_id']]);
            $this->change("INSERT INTO familyhub_members(scope_id,user_id,account_id,role,active) VALUES(?,?,?,'owner',1)",[$t['scopeId'],$next['user_id'],$t['successorAccountId']]);
            $this->change('UPDATE familyhub_scopes SET owner_id=?,sequence=sequence+1 WHERE id=?',[$next['user_id'],$t['scopeId']]);
        }
    }
    public function removeFromCore($id)
    {
        $result=$this->transaction(function()use($id){
            $user=$this->one('SELECT u.*,a.account_id FROM users u JOIN familyhub_accounts a ON a.user_id=u.id WHERE u.id=?'.$this->lockSuffix(),[(int)$id]);
            if(!$user){return false;}
            $this->many('SELECT id FROM users ORDER BY id'.$this->lockSuffix());
            $scopes=$this->many("SELECT * FROM familyhub_scopes WHERE deleted_at IS NULL ORDER BY CASE WHEN kind='organization' THEN 0 ELSE 1 END,id".$this->lockSuffix());
            $g=$this->plan($user,$scopes);
            // The core admin UI has no ownership/contribution resolution
            // controls. A genuine legacy dependency must be reviewed there
            // first; it cannot justify deleting somebody else's contribution.
            foreach($g['wire']['blockers'] as $blocker){
                if(!in_array($blocker['code'],['shared_scope_owner','shared_structure_resolution'],true)){return false;}
            }
            $op=$this->newUuid();
            $this->change('INSERT INTO familyhub_deletion_receipts(operation_id,token_hash,deleted_at) VALUES(?,?,?)',[$op,hash('sha256',random_bytes(32)),time()]);
            $this->queueIdeaFiles($op,$user,[]);
            (new NativeAttachmentService($this->container))->removeAccount($user,[],$op);
            $retained=[];
            foreach($g['cryptoScopes'] as $scope){
                if($scope['_private']){$this->erasePrivate($scope['id']);}else{$retained[]=$scope;}
            }
            (new NativeCryptoAccountTombstoneV2($this->container))->preserve($user,$op,$retained);
            $this->purge($user,$g['legacyScopes'],[]);
            $this->purgeLegacy($user,$g['privateProjects'],$op);
            return $op;
        },true);
        if($result===false){return false;}
        $this->finishFiles($result);
        return true;
    }
}
