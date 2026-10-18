<?php
namespace Kanboard\Plugin\FamilyHub\Model;

/** Captured audit history is domain-readable encrypted evidence, never a new
 * transaction, author claim, WRITE grant or account-private archive shortcut. */
class NativeCryptoMigrationAuditV3 extends NativeDatabase
{
    protected $cryptoAccess = true;
    public const TABLES = ['familyhub_finance_audit'];

    private function transactionRequired()
    {
        if (!$this->transactionActive()) throw new NativeError('crypto_migration_transaction_required',409);
    }
    private function digest($v)
    {
        if (!is_string($v) || !preg_match('/^[a-f0-9]{64}$/D',$v)) throw new NativeError('crypto_migration_audit_context');
        return $v;
    }
    private function common($p,$actor)
    {
        return ['version'=>3,'serverId'=>$this->serverId(),'migrationId'=>$this->uuid($p['migrationId']),
            'captureId'=>$this->uuid($p['captureId']),'accountId'=>$actor['user']['account_id'],
            'sourceInventoryRoot'=>$this->digest($p['sourceInventoryRoot'])];
    }
    private function auditCanonical($v) { return NativeCryptoCodec::canonical((object)$v); }
    private function same($a,$b) { return $this->auditCanonical($a)===$this->auditCanonical($b); }
    private function cellText($row,$key)
    {
        $cells=is_object($row)?get_object_vars($row):null;
        if ($cells===null || !isset($cells[$key]) || !is_array($cells[$key]) || !array_key_exists('valueBase64',$cells[$key])) {
            throw new NativeError('crypto_migration_audit_source',409);
        }
        if ($cells[$key]['valueBase64']===null) return null;
        $bytes=base64_decode($cells[$key]['valueBase64'],true);
        if ($bytes===false || base64_encode($bytes)!==$cells[$key]['valueBase64']) throw new NativeError('crypto_migration_audit_source',409);
        return $bytes;
    }
    private function source($common,$bindingId,$actor,callable $resolve)
    {
        $source=$resolve($common['migrationId'],$common['captureId'],$this->uuid($bindingId),$actor);
        $context=NativeCryptoCaptureV3::context($source['context']);
        $binding=NativeCryptoCaptureV3::binding($source['binding']);
        if ($context['sourceTable']!=='familyhub_finance_audit' || $context['domain']!=='finance'
            || $context['scopeId']===null || $binding['bindingId']!==$bindingId
            || $this->cellText($source['typedRow'],'scope_id')!==$context['scopeId']) {
            throw new NativeError('crypto_migration_audit_source',409);
        }
        foreach (['serverId','migrationId','captureId','accountId'] as $k) if ($context[$k]!==$common[$k]) throw new NativeError('crypto_migration_audit_context',409);
        $record=$this->uuid($this->cellText($source['typedRow'],'record_id'));
        $revision=$this->cellText($source['typedRow'],'revision');
        if (!is_string($revision) || !preg_match('/^[1-9][0-9]{0,15}$/D',$revision)
            || strlen($revision)===16 && strcmp($revision,'9007199254740991')>0) throw new NativeError('crypto_migration_audit_source',409);
        return $source+['recordId'=>$record,'legacyRevision'=>(int)$revision];
    }
    private function descriptor($d,$common,$source,$actor)
    {
        $this->fields($d,['version','purpose','context','cipherManifestHash','segments','manifestBase64']);
        $context=$d['context'];
        $this->fields($context,['version','purpose','serverId','accountId','captureId','migrationId','bindingId',
            'sourceInventoryRoot','sourceCommitment','scopeId','domain','epoch','accessRevision','membershipHeadHash','recordId','legacyRevision']);
        foreach (['version','serverId','migrationId','captureId','accountId','sourceInventoryRoot'] as $k) {
            if ($context[$k]!==$common[$k]) throw new NativeError('crypto_migration_audit_context',409);
        }
        $scope=$source['context']['scopeId'];
        if ($d['version']!==3 || $d['purpose']!=='migrationAudit' || $context['purpose']!=='migrationAudit'
            || $context['bindingId']!==$source['binding']['bindingId'] || $context['sourceCommitment']!==$source['binding']['sourceCommitment']
            || $context['scopeId']!==$scope || $context['domain']!=='finance'
            || $context['recordId']!==$source['recordId'] || $context['legacyRevision']!==$source['legacyRevision']
            || !is_int($context['epoch']) || $context['epoch']<1 || !is_int($context['accessRevision']) || $context['accessRevision']<0) {
            throw new NativeError('crypto_migration_audit_context',409);
        }
        $this->digest($context['membershipHeadHash']);
        (new NativeCryptoScopeV2($this->container,$this->bearer,$this->ip))->author(
            $scope,$context['membershipHeadHash'],$context['epoch'],$context['accessRevision'],$actor,'finance',false);
        $this->digest($d['cipherManifestHash']);
        if (!is_array($d['segments']) || !array_is_list($d['segments']) || !$d['segments'] || count($d['segments'])>4) throw new NativeError('crypto_migration_audit_descriptor',409);
        $manifest=NativeCryptoCodec::base64($d['manifestBase64'],16384);
        $envelope=json_decode($manifest,true,34,JSON_THROW_ON_ERROR);
        if (!isset($envelope['context']) || !$this->same($envelope['context'],$context)) throw new NativeError('crypto_migration_audit_descriptor',409);
        $seen=[];$total=0;
        foreach ($d['segments'] as $i=>$segment) {
            $this->fields($segment,['id','index','size','sha256']);
            $this->uuid($segment['id']);$this->digest($segment['sha256']);
            if ($segment['index']!==$i || !is_int($segment['size']) || $segment['size']<48 || $segment['size']>NativeCryptoMigrationBlobV2::MAX_BYTES
                || isset($seen[$segment['id']])) throw new NativeError('crypto_migration_audit_descriptor',409);
            $seen[$segment['id']]=true;$total+=$segment['size'];
            $row=$this->one('SELECT * FROM familyhub_crypto_migration_blobs_v2 WHERE migration_id=? AND id=?',[$common['migrationId'],$segment['id']]);
            if (!$row || $row['account_id']!==$common['accountId'] || $row['purpose']!=='auditWitness'
                || $row['source_table']!=='familyhub_finance_audit' || $row['source_id']!==$source['recordId'].':'.$source['legacyRevision']
                || $row['scope_id']!==$scope || $row['domain']!=='finance' || $row['head_hash']!==$context['membershipHeadHash']
                || (int)$row['epoch']!==$context['epoch'] || (int)$row['access_revision']!==$context['accessRevision']
                || (int)$row['complete']!==1 || (int)$row['received']!==$segment['size'] || (int)$row['size']!==$segment['size']
                || $row['sha256']!==$segment['sha256'] || $row['manifest']!==$d['manifestBase64']) {
                throw new NativeError('crypto_migration_audit_cipher_pending',409);
            }
            // The private engine's old comparison columns are not v3 roots.
            // Exact public Capture3 binding comes from its retained signed begin.
            $beginProof=json_decode($row['authorization'],true,34,JSON_THROW_ON_ERROR);
            [$begin,$beginBytes,$beginSignature]=NativeCryptoCodec::decode($beginProof);
            $this->fields($begin,['version','operation','requestId','serverId','accountId','deviceId','signer','payload']);
            $expected=['captureVersion'=>3,'migrationId'=>$common['migrationId'],'captureId'=>$common['captureId'],
                'sourceInventoryRoot'=>$common['sourceInventoryRoot'],'bindingId'=>$source['binding']['bindingId'],
                'scopeId'=>$scope,'id'=>$segment['id'],'domain'=>'finance','purpose'=>'auditWitness',
                'epoch'=>$context['epoch'],'membershipHeadHash'=>$context['membershipHeadHash'],
                'accessRevision'=>$context['accessRevision'],'size'=>$segment['size'],'sha256'=>$segment['sha256'],
                'manifestBase64'=>$d['manifestBase64']];
            if ($begin['version']!==2 || $begin['operation']!=='crypto2.migration.blob.begin' || $begin['signer']!=='device'
                || $begin['serverId']!==$common['serverId'] || $begin['accountId']!==$common['accountId']
                || !$this->same($begin['payload'],$expected)
                || $row['source_row_hash']!==hash('sha256',NativeCryptoCodec::canonical($source['typedRow']))) {
                throw new NativeError('crypto_migration_audit_cipher_binding',409);
            }
            $directory=new NativeCryptoDirectoryV2($this->container);
            NativeCryptoV2Codec::verify($beginBytes,$beginSignature,
                NativeCryptoMigrationGenerationV3::retainedSigningKey($this->pdo,$beginProof,$common['accountId'])??$directory->authorizeContent($begin,$directory->current($common['accountId'])));
        }
        if ($total>69206016 || hash('sha256',NativeCryptoCodec::canonical($d['segments']))!==$d['cipherManifestHash']) {
            // Segment list is the same canonical array used by ArchiveStaging.
            throw new NativeError('crypto_migration_audit_descriptor',409);
        }
    }
    private function artifactHash($proof)
    {
        return hash('sha256',"JivieMigrationAuditArtifact/v3\n".$this->auditCanonical($proof));
    }
    private function selected($common,$bindingId,$actor,callable $resolve)
    {
        $row=$this->one('SELECT * FROM familyhub_crypto_migration_audit_v3 WHERE migration_id=? AND account_id=? AND binding_id=?',
            [$common['migrationId'],$common['accountId'],$bindingId]);
        if (!$row || $row['capture_id']!==$common['captureId'] || $row['source_inventory_root']!==$common['sourceInventoryRoot']) throw new NativeError('crypto_migration_audit_incomplete',409);
        $proof=json_decode($row['authorization'],true,34,JSON_THROW_ON_ERROR);
        [$command,$bytes,$signature]=NativeCryptoCodec::decode($proof);
        $this->fields($command,['version','operation','requestId','serverId','accountId','deviceId','signer','payload']);
        if ($command['version']!==2 || $command['operation']!=='crypto2.migration.audit.stage' || $command['serverId']!==$common['serverId']
            || $command['accountId']!==$common['accountId'] || $command['signer']!=='device') throw new NativeError('crypto_migration_audit_authorization',409);
        $scopes=new NativeCryptoScopeV2($this->container,$this->bearer,$this->ip);
        $this->fields($command['payload'],['migrationId','captureId','sourceInventoryRoot','bindingId','descriptor','authorDirectoryHeadHash']);
        foreach (['migrationId','captureId','sourceInventoryRoot'] as $k) if ($command['payload'][$k]!==$common[$k]) throw new NativeError('crypto_migration_audit_authorization',409);
        if ($command['payload']['bindingId']!==$bindingId) throw new NativeError('crypto_migration_audit_authorization',409);
        $scopes->currentAuthorReference($command['payload']['authorDirectoryHeadHash'],$actor);
        $directory=new NativeCryptoDirectoryV2($this->container);
        NativeCryptoV2Codec::verify($bytes,$signature,NativeCryptoMigrationGenerationV3::retainedSigningKey($this->pdo,$proof,$common['accountId'])??$directory->authorizeContent($command,$directory->current($common['accountId'])));
        $source=$this->source($common,$bindingId,$actor,$resolve);
        $d=json_decode($row['descriptor'],true,34,JSON_THROW_ON_ERROR);
        $this->descriptor($d,$common,$source,$actor);
        if (!$this->same($command['payload']['descriptor'],$d) || $row['scope_id']!==$source['context']['scopeId']
            || $row['record_id']!==$source['recordId'] || (int)$row['legacy_revision']!==$source['legacyRevision']
            || $row['source_commitment']!==$source['binding']['sourceCommitment']) throw new NativeError('crypto_migration_audit_storage',503);
        return ['descriptor'=>$d,'authorization'=>$proof,'artifactHash'=>$this->artifactHash($proof),'source'=>$source];
    }
    public function stage($p,$actor,$proof,$command,callable $resolve)
    {
        $this->transactionRequired();
        $this->fields($p,['migrationId','captureId','sourceInventoryRoot','bindingId','descriptor','authorDirectoryHeadHash']);
        $common=$this->common($p,$actor);
        [$decoded,$bytes,$signature]=NativeCryptoCodec::decode($proof);
        if (!$this->same($decoded,$command) || ($command['version'] ?? null)!==2
            || ($command['operation'] ?? null)!=='crypto2.migration.audit.stage'
            || ($command['serverId'] ?? null)!==$common['serverId'] || ($command['accountId'] ?? null)!==$common['accountId']
            || ($command['deviceId'] ?? null)!==$actor['device']['id'] || ($command['signer'] ?? null)!=='device'
            || !$this->same($command['payload'] ?? [],$p)) throw new NativeError('crypto_migration_audit_authorization',409);
        $directory=new NativeCryptoDirectoryV2($this->container);
        NativeCryptoV2Codec::verify($bytes,$signature,NativeCryptoMigrationGenerationV3::retainedSigningKey($this->pdo,$proof,$common['accountId'])??$directory->authorizeContent($command,$directory->current($common['accountId'])));
        (new NativeCryptoScopeV2($this->container,$this->bearer,$this->ip))->currentAuthorReference($p['authorDirectoryHeadHash'],$actor);
        $source=$this->source($common,$p['bindingId'],$actor,$resolve);
        $this->descriptor($p['descriptor'],$common,$source,$actor);
        $old=$this->one('SELECT authorization FROM familyhub_crypto_migration_audit_v3 WHERE migration_id=? AND (binding_id=? OR (scope_id=? AND record_id=? AND legacy_revision=?))',
            [$common['migrationId'],$p['bindingId'],$source['context']['scopeId'],$source['recordId'],$source['legacyRevision']]);
        if ($old) {
            if ($old['authorization']!==$this->auditCanonical($proof)) throw new NativeError('crypto_migration_audit_immutable',409);
        } else {
            $this->change('INSERT INTO familyhub_crypto_migration_audit_v3(migration_id,account_id,capture_id,binding_id,scope_id,record_id,legacy_revision,source_inventory_root,source_commitment,descriptor,authorization,state) VALUES(?,?,?,?,?,?,?,?,?,?,?,?)',
                [$common['migrationId'],$common['accountId'],$common['captureId'],$p['bindingId'],$source['context']['scopeId'],
                    $source['recordId'],$source['legacyRevision'],$common['sourceInventoryRoot'],$source['binding']['sourceCommitment'],
                    $this->auditCanonical($p['descriptor']),$this->auditCanonical($proof),'staged']);
        }
        return ['bindingId'=>$p['bindingId'],'artifactHash'=>$this->artifactHash($proof),'active'=>false];
    }
    public function artifact($p,$actor,callable $resolve)
    {
        $this->fields($p,['migrationId','captureId','sourceInventoryRoot','bindingId']);
        $common=$this->common($p,$actor);
        $out=$this->selected($common,$this->uuid($p['bindingId']),$actor,$resolve);
        unset($out['source']);
        return $out;
    }
    public function coverage($migrationId,$captureId,$root,$actor,callable $enumerate,callable $resolve)
    {
        $this->transactionRequired();
        $common=$this->common(['migrationId'=>$migrationId,'captureId'=>$captureId,'sourceInventoryRoot'=>$root],$actor);
        $hash=hash_init('sha256');hash_update($hash,"JivieMigrationAuditSelection/v3\n".$this->auditCanonical($common)."\n");
        $count=0;$previous=null;
        foreach ($enumerate($migrationId,$captureId,$root,$actor,self::TABLES) as $entry) {
            $id=$entry['binding']['bindingId'];
            if ($previous!==null && strcmp($previous,$id)>=0) throw new NativeError('crypto_migration_audit_order',409);
            $previous=$id;
            $artifact=$this->selected($common,$id,$actor,$resolve);
            hash_update($hash,$this->auditCanonical(['bindingId'=>$id,'artifactHash'=>$artifact['artifactHash']])."\n");
            $count++;
        }
        $stored=$this->one('SELECT COUNT(*) n FROM familyhub_crypto_migration_audit_v3 WHERE migration_id=? AND account_id=?',[$migrationId,$common['accountId']]);
        if ((int)$stored['n']!==$count) throw new NativeError('crypto_migration_audit_coverage',409);
        return ['kind'=>'audit','count'=>$count,'root'=>hash_final($hash)];
    }
    /** Scoped counterpart of the unchanged private verify3 aggregate. The
     * complete frozen source stream, not an unsigned filtered SQL list,
     * determines both absence and the exact selected artifact set. */
    public function scopedCoverage($migrationId,$captureId,$root,$scopeId,$actor,callable $enumerate,callable $resolve)
    {
        $this->transactionRequired();$scopeId=$this->uuid($scopeId);
        $common=$this->common(['migrationId'=>$migrationId,'captureId'=>$captureId,'sourceInventoryRoot'=>$root],$actor);
        $context=$common+['scopeId'=>$scopeId,'domain'=>'finance'];
        $hash=hash_init('sha256');hash_update($hash,"JivieMigrationAuditScopeSelection/v3\n".$this->auditCanonical($context)."\n");
        $count=0;$all=0;$previous=null;
        foreach($enumerate($migrationId,$captureId,$root,$actor,self::TABLES) as $entry){
            $id=$entry['binding']['bindingId'];
            if($previous!==null&&strcmp($previous,$id)>=0)throw new NativeError('crypto_migration_audit_order',409);
            $previous=$id;$all++;
            $artifact=$this->selected($common,$id,$actor,$resolve);
            if($artifact['source']['context']['scopeId']!==$scopeId)continue;
            hash_update($hash,$this->auditCanonical(['bindingId'=>$id,'artifactHash'=>$artifact['artifactHash']])."\n");$count++;
        }
        $stored=$this->one('SELECT COUNT(*) n FROM familyhub_crypto_migration_audit_v3 WHERE migration_id=? AND account_id=?',[$migrationId,$common['accountId']]);
        if((int)$stored['n']!==$all)throw new NativeError('crypto_migration_audit_coverage',409);
        return ['kind'=>'audit','count'=>$count,'root'=>hash_final($hash)];
    }

}
