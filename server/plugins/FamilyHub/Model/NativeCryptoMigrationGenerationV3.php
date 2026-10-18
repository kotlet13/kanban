<?php
namespace Kanboard\Plugin\FamilyHub\Model;

/** Explicit generation approval. A new device never silently rewrites an old
 * request, genesis, key or accepted activation. Historical exceptions exist
 * only while the final coordinator holds this exact transaction capability. */
class NativeCryptoMigrationGenerationV3 extends NativeDatabase
{
    protected $cryptoAccess=true;
    private static $contexts;
    private $historicalAccounts = [];
    const APPROVAL_DOMAIN="JivieMigrationGenerationApproval/v3\n";
    private function hash($v){return NativeCryptoV2Codec::hash((object)$v);}
    private function body($proof){return NativeCryptoCodec::decode($proof)[0];}
    private function same($a,$b){return NativeCryptoCodec::canonical($a)===NativeCryptoCodec::canonical($b);}
    private function row($id,$actor=null)
    {
        $row=$this->one('SELECT * FROM familyhub_crypto_migration_generations_v3 WHERE id=?',[$this->uuid($id)]);
        if(!$row||$actor&&!$this->one('SELECT account_id FROM familyhub_crypto_migration_portions_v2 WHERE migration_id=? AND account_id=?',[$row['migration_id'],$actor['user']['account_id']]))throw new NativeError('crypto_migration_generation_missing',404);
        return $row;
    }
    public static function token($server,$migration,$generation)
    {
        return hash('sha256',"JivieMigrationGenerationToken/v3\n".NativeCryptoCodec::canonical((object)['version'=>3,'serverId'=>$server,'migrationId'=>$migration,'generationId'=>$generation]));
    }
    private function required($migration)
    {
        $rows=$this->many('SELECT account_id FROM familyhub_crypto_migration_portions_v2 WHERE migration_id=? ORDER BY account_id LIMIT 1001',[$migration]);
        if(!$rows||count($rows)>1000)throw new NativeError('crypto_migration_generation_capacity',409);
        return array_column($rows,'account_id');
    }
    private function migrationRow($id)
    {
        $row=$this->one('SELECT * FROM familyhub_crypto_migrations_v2 WHERE id=?',[$this->uuid($id)]);
        if(!$row||in_array($row['state'],['committed','retired','aborted'],true))throw new NativeError('crypto_migration_generation_state',409);
        return $row;
    }
    /** Closed accepted metadata only. Never the legacy source or plaintext. */
    private function proofs($migration)
    {
        $sources=[
            ['familyhub_crypto_structure_sources_v3',['statement_authorization','certificate_authorization','event_authorization']],
            ['familyhub_crypto_structure_contexts_v3',['authorization']],
            ['familyhub_crypto_captures_v3',['authorization','seal_authorization']],
            ['familyhub_crypto_capture_sources_v3',['authorization']],
            ['familyhub_crypto_migration_stage_batches_v2',['authorization']],
            ['familyhub_crypto_migration_blobs_v2',['authorization']],
            ['familyhub_crypto_migration_audit_v3',['authorization']],
            ['familyhub_crypto_legacy_index_certificates_v3',['authorization','event_authorization']],
            ['familyhub_crypto_notification_transforms_v3',['authorization','stage_authorization']],
            ['familyhub_crypto_notification_certificates_v3',['authorization','event_authorization']],
            ['familyhub_crypto_invitation_bridges_v3',['authorization','stage_authorization']],
            ['familyhub_crypto_invitation_certificates_v3',['authorization','event_authorization']],
            ['familyhub_crypto_migration_contributions_v3',['authorization','event_authorization']],
            ['familyhub_crypto_migration_domain_attestations_v2',['authorization']],
        ];
        foreach($sources as [$table,$columns]){
            $offset=0;
            do {
                $page=$this->many('SELECT '.implode(',',$columns).' FROM '.$table.' WHERE migration_id=? LIMIT 20 OFFSET '.$offset,[$migration]);
                foreach($page as $row)foreach($columns as $column){if($row[$column]!==null){$proof=json_decode($row[$column],true,64,JSON_THROW_ON_ERROR);if(isset($proof['commandBase64'],$proof['signatureBase64']))yield $proof;}}
                $offset+=count($page);
                if($offset>1000000)throw new NativeError('crypto_migration_generation_capacity',409);
            }while(count($page)===20);
        }
        foreach([
            ['SELECT verification FROM familyhub_crypto_migration_portions_v2 WHERE migration_id=? AND verification IS NOT NULL','verification'],
            ['SELECT c.authorization FROM familyhub_crypto_structure_consents_v3 c JOIN familyhub_crypto_structure_contexts_v3 x ON x.context_hash=c.context_hash WHERE x.migration_id=?','authorization'],
        ] as [$sql,$column]) {
            $offset=0;
            do {
                $page=$this->many($sql.' LIMIT 20 OFFSET '.$offset,[$migration]);
                foreach($page as $r){$v=json_decode($r[$column],true,64,JSON_THROW_ON_ERROR);$proof=$column==='verification'?($v['authorization']??null):$v;if($proof!==null)yield $proof;}
                $offset+=count($page);
                if($offset>1000000)throw new NativeError('crypto_migration_generation_capacity',409);
            }while(count($page)===20);
        }
    }
    private function scopes($migration,$generation=null)
    {
        $ids=json_decode($migration['scope_ids'],true,34,JSON_THROW_ON_ERROR);sort($ids,SORT_STRING);
        $scopes=new NativeCryptoScopeV2($this->container,$this->bearer,$this->ip);$out=[];$server=$this->serverId();
        foreach($ids as $sid){
            $raw=$this->one('SELECT * FROM familyhub_scopes WHERE id=?',[$sid]);
            if(!$raw||$raw['deleted_at']!==null)throw new NativeError('crypto_migration_generation_read_only_hold',409);
            $head=$scopes->current($sid);$draft=$generation?$this->one('SELECT proposal_hash,head_hash FROM familyhub_crypto_migration_generation_drafts_v3 WHERE generation_id=? AND scope_id=?',[$generation,$sid]):null;
            $out[]=['scopeToken'=>NativeCryptoMigrationCommitmentsV3::scopeToken($server,$migration['id'],$sid,'content'),
                'headHash'=>$head['head_hash']??null,'accessRevision'=>(int)$raw['access_revision'],
                'lifecycleHash'=>(new NativeCryptoLifecycleV2($this->container))->closingHash($sid),
                'candidateHeadHash'=>$draft['head_hash']??null,'candidateProposalHash'=>$draft['proposal_hash']??null];
        }
        usort($out,static fn($a,$b)=>strcmp($a['scopeToken'],$b['scopeToken']));return $out;
    }
    private function published($migration)
    {
        $rows=$this->many('SELECT scope_id,activation_hash,authorization,event_authorization FROM familyhub_crypto_migration_activations_v3 WHERE migration_id=? ORDER BY scope_id LIMIT 1001',[$migration['id']]);
        if(count($rows)>1000)throw new NativeError('crypto_migration_generation_capacity',409);
        $out=[];$server=$this->serverId();
        foreach($rows as $row)$out[]=['scopeToken'=>NativeCryptoMigrationCommitmentsV3::scopeToken($server,$migration['id'],$row['scope_id'],'content'),'activationHash'=>$row['activation_hash'],'eventHash'=>$this->hash(json_decode($row['event_authorization'],true,64,JSON_THROW_ON_ERROR))];
        usort($out,static fn($a,$b)=>strcmp($a['scopeToken'],$b['scopeToken']));return $out;
    }
    private function noAdmission($migration)
    {
        foreach(json_decode($migration['scope_ids'],true,34,JSON_THROW_ON_ERROR) as $sid){
            if($this->one('SELECT scope_id FROM familyhub_crypto_scope_origins WHERE scope_id=?',[$sid])||$this->one('SELECT scope_id FROM familyhub_crypto_records WHERE scope_id=? LIMIT 1',[$sid]))throw new NativeError('crypto_migration_generation_admitted',409);
        }
    }
    public function prepare($p,$actor,$proof)
    {
        $this->fields($p,['migrationId','generationId','mode']);$id=$this->uuid($p['generationId']);
        if(!in_array($p['mode'],['supersede','continue'],true))throw new NativeError('validation_error');
        $migration=$this->migrationRow($p['migrationId']);$accounts=$this->required($migration['id']);
        if(!in_array($actor['user']['account_id'],$accounts,true))throw new NativeError('permission_revoked',403);
        $old=$this->one('SELECT * FROM familyhub_crypto_migration_generations_v3 WHERE id=?',[$id]);
        if($old){if($old['migration_id']!==$migration['id']||$old['mode']!==$p['mode'])throw new NativeError('idempotency_mismatch',409);return $this->status(['generationId'=>$id],$actor);}
        $published=$this->published($migration);$this->noAdmission($migration);
        if(($p['mode']==='supersede')!==(!$published))throw new NativeError('crypto_migration_generation_publication_boundary',409);
        $scopes=$this->scopes($migration);$context=['version'=>3,'serverId'=>$this->serverId(),'migrationId'=>$migration['id'],'generationId'=>$id,'mode'=>$p['mode'],'componentId'=>$migration['component_id'],
            'scopes'=>$scopes,'published'=>$published,'requiredAccountTokens'=>array_map(fn($a)=>hash('sha256',"JivieGenerationAccount/v3\n".$id."\n".$a),$accounts),
            'newMigrationId'=>$p['mode']==='supersede'?$this->newUuid():null];
        sort($context['requiredAccountTokens'],SORT_STRING);
        $this->change("UPDATE familyhub_crypto_migration_generations_v3 SET state='abandoned' WHERE migration_id=? AND mode=? AND state IN ('drafting','review')",[$migration['id'],$p['mode']]);
        $this->change('INSERT INTO familyhub_crypto_migration_generations_v3 VALUES(?,?,?,?,?,?,?,?,?,?)',[$id,$migration['id'],$p['mode'],$context['newMigrationId'],NativeCryptoCodec::canonical((object)$context),null,null,'drafting',NativeCryptoCodec::canonical((object)$proof),time()]);
        // Buffer each bounded page before INSERT: iterate() is unbuffered on
        // MySQL. No query/mutation occurs while its source cursor is active.
        foreach($this->proofs($migration['id']) as $accepted)$this->indexProof($id,$accepted);
        foreach($this->many('SELECT authorization,event_authorization FROM familyhub_crypto_migration_activations_v3 WHERE migration_id=?',[$migration['id']]) as $row){$this->indexProof($id,json_decode($row['authorization'],true,64,JSON_THROW_ON_ERROR));$this->indexProof($id,json_decode($row['event_authorization'],true,64,JSON_THROW_ON_ERROR));}
        return $this->status(['generationId'=>$id],$actor);
    }
    /** Reconstruct signed history, never the deliberately blank log snapshot
     * column. Match the complete replay to the current accepted directory before
     * using any prefix. Cache public device and member-identity tuples for this helper
     * and exact current head; do not retain keyring payloads or install trust.
     */
    private function historicalPrefix($account, $reference, $deviceId)
    {
        $directory = new NativeCryptoDirectoryV2($this->container,$this->bearer,$this->ip);
        $current = $directory->current($account);
        if (!$current) throw new NativeError('crypto_migration_generation_signer_unavailable',409);
        $cache = $this->historicalAccounts[$account] ?? null;
        if (!$cache || $cache['headHash'] !== $current['head_hash']) {
            if ((int)$current['generation'] > 1000000) throw new NativeError('crypto_migration_generation_capacity',409);
            $before = null; $after = 0; $prefixes = []; $latest = [];
            $server = $this->serverId();
            while ($after < (int)$current['generation']) {
                // Buffered page: reducer validation must not query while a
                // MariaDB/MySQL unbuffered source cursor remains active.
                $rows = $this->many('SELECT * FROM familyhub_crypto_directory WHERE account_id=? AND generation>? AND generation<=? ORDER BY generation LIMIT 20',[$account,$after,(int)$current['generation']]);
                if (!$rows) throw new NativeError('crypto_migration_generation_directory_fork',409);
                foreach ($rows as $row) {
                    $proof = json_decode($row['authorization'],true,34,JSON_THROW_ON_ERROR);
                    [$command,$bytes,$signature] = NativeCryptoCodec::decode($proof);
                    $previous = $before['head_hash'] ?? NativeCryptoDirectoryV2::ZERO;
                    if ((int)$row['generation'] !== $after+1 || $command['accountId'] !== $account ||
                        $command['serverId'] !== $server || $command['payload']['previousHeadHash'] !== $previous ||
                        $row['previous_head_hash'] !== $previous || $row['command_hash'] !== hash('sha256',$bytes)) {
                        throw new NativeError('crypto_migration_generation_directory_fork',409);
                    }
                    NativeCryptoV2Codec::verify($bytes,$signature,$directory->authorize($command,$before));
                    $snapshot = $directory->reduce($command,$before);
                    if (NativeCryptoV2Codec::head($command,$proof,$after+1) !== $row['head_hash'] ||
                        NativeCryptoDirectoryV2::snapshotHash($snapshot) !== $row['snapshot_hash'] ||
                        NativeCryptoDirectoryV2::deviceHash($snapshot) !== $row['device_snapshot_hash'] ||
                        $snapshot['identityEpochId'] !== $row['identity_epoch_id']) {
                        throw new NativeError('crypto_migration_generation_directory_fork',409);
                    }
                    $devices = [];
                    foreach ($snapshot['devices'] as $device) {
                        if ($device['revokedGeneration'] === null && $device['identityEpochId'] === $snapshot['identityEpochId']) {
                            $devices[$device['deviceId']] = $device;
                            $latest[$device['deviceId']] = $row['head_hash'];
                        }
                    }
                    $memberDirectory = array_intersect_key($snapshot,array_flip(['rootSigningKeyBase64','rootEncryptionKeyBase64','identityEpochId','recoveryRootEpochId']));
                    $memberDirectory['deviceSnapshotHash'] = $row['device_snapshot_hash'];
                    $prefixes[$row['head_hash']] = ['generation'=>(int)$row['generation'],'devices'=>$devices,'memberDirectory'=>$memberDirectory];
                    $before = array_replace($row,['snapshot'=>NativeCryptoCodec::canonical((object)$snapshot)]);
                    $after++;
                }
            }
            foreach (['head_hash','snapshot_hash','device_snapshot_hash','identity_epoch_id'] as $field) {
                if (($before[$field] ?? null) !== $current[$field]) throw new NativeError('crypto_migration_generation_directory_fork',409);
            }
            $cache = ['headHash'=>$current['head_hash'],'prefixes'=>$prefixes,'latest'=>$latest];
            $this->historicalAccounts[$account] = $cache;
        }
        $reference ??= $cache['latest'][$deviceId] ?? null;
        $prefix = $reference === null ? null : ($cache['prefixes'][$reference] ?? null);
        if (!$prefix || ($deviceId !== null && !isset($prefix['devices'][$deviceId]))) throw new NativeError('crypto_migration_generation_signer_unavailable',409);
        return $prefix + ['head_hash'=>$reference];
    }

    private function indexProof($id,$proof)
    {
        $body=$this->body($proof);$hash=$this->hash($proof);
        $account=$body['accountId']??$body['managerAccountId']??null;$device=$body['deviceId']??null;
        if($device===null&&isset($body['managerDirectoryHeadHash'])){
            $row=$this->one('SELECT event_authorization FROM familyhub_crypto_migration_activations_v3 WHERE migration_id=? AND activation_hash=?',[$body['migrationId'],$hash]);
            if($row)$device=$this->body(json_decode($row['event_authorization'],true,64,JSON_THROW_ON_ERROR))['deviceId'];
        }
        if(!$account||!$device)return;
        $reference=$body['managerDirectoryHeadHash']??$body['authorDirectoryHeadHash']??$body['payload']['authorDirectoryHeadHash']??$body['payload']['header']['authorDirectoryHeadHash']??$body['payload']['header']['managerDirectoryHeadHash']??null;
        // Explicit selectors and generic accepted metadata both require an
        // active device at an authenticated prefix included in current history.
        $reference = $this->historicalPrefix($account,$reference,$device)['head_hash'];
        if(!$this->one('SELECT proof_hash FROM familyhub_crypto_migration_generation_evidence_v3 WHERE generation_id=? AND proof_hash=?',[$id,$hash]))$this->change('INSERT INTO familyhub_crypto_migration_generation_evidence_v3 VALUES(?,?,?,?,?)',[$id,$hash,$account,$device,$reference]);
        if(isset($body['useAuthorization'])&&$body['useAuthorization']!==null)$this->indexProof($id,$body['useAuthorization']);
        foreach($body['payload']['batch']['records']??[] as $nested)$this->indexProof($id,$nested);
        if(isset($body['payload']['batch']['commitment']))$this->indexProof($id,$body['payload']['batch']['commitment']);
    }
    public function financeDraft($p,$actor)
    {
        $this->fields($p,['generationId','scopeId','draftId','core']);$row=$this->row($p['generationId'],$actor);
        if($row['mode']!=='supersede'||$row['state']!=='drafting')throw new NativeError('crypto_migration_generation_state',409);
        $migration=$this->migrationRow($row['migration_id']);$sid=$this->uuid($p['scopeId']);$draft=$this->uuid($p['draftId']);
        if($this->published($migration)||!in_array($sid,json_decode($migration['scope_ids'],true,34,JSON_THROW_ON_ERROR),true))throw new NativeError('crypto_migration_generation_publication_boundary',409);
        $scopes=new NativeCryptoScopeV2($this->container,$this->bearer,$this->ip);$scope=$this->scope($sid,$actor['user']['id']);
        $scopes->manager($scopes->current($sid),$scope,$actor);
        if((int)$scope['owner_id']!==(int)$actor['user']['id'])throw new NativeError('crypto_migration_generation_owner_required',409);
        $body=$p['core']+['contentKeyProposalProof'=>null,'financeKeyProposalProof'=>null];$scopes->validateProposal($body);
        if($body['scopeId']!==$sid||$body['epoch']!==1||$body['previousHeadHash']!==NativeCryptoDirectoryV2::ZERO||$body['accessIntentProof']!==null||$body['financePolicyIntentProof']!==null||$body['keyIds']['finance']!==null||$body['keyCommitments']['finance']!==null)throw new NativeError('crypto_migration_generation_draft',409);
        $scopes->currentAuthorReference($body['authorDirectoryHeadHash'],$actor);$scopes->assertMembershipParity($scope,$body['members']);
        $old=$this->one('SELECT finance_draft_id,core_hash FROM familyhub_crypto_migration_generation_drafts_v3 WHERE generation_id=? AND scope_id=?',[$row['id'],$sid]);$hash=$this->hash($p['core']);
        if($old&&($old['finance_draft_id']!==$draft||$old['core_hash']!==$hash))throw new NativeError('crypto_migration_generation_immutable',409);
        if(!$old)$this->change('INSERT INTO familyhub_crypto_migration_generation_drafts_v3(generation_id,scope_id,head_hash,proposal_hash,authorization,finance_draft_id,core_hash) VALUES(?,?,NULL,NULL,NULL,?,?)',[$row['id'],$sid,$draft,$hash]);
        return ['generationId'=>$row['id'],'draftId'=>$draft,'registered'=>true];
    }
    public function financePreview($scopeId,$draftId,$core=null)
    {
        if(!is_string($draftId))return false;
        $row=$this->one("SELECT g.*,d.core_hash FROM familyhub_crypto_migration_generation_drafts_v3 d JOIN familyhub_crypto_migration_generations_v3 g ON g.id=d.generation_id WHERE d.scope_id=? AND d.finance_draft_id=? AND g.mode='supersede' AND g.state='drafting'",[$scopeId,$draftId]);
        if(!$row)return false;
        $migration=$this->migrationRow($row['migration_id']);$this->noAdmission($migration);
        if($this->published($migration)||$core!==null&&$this->hash($core)!==$row['core_hash'])throw new NativeError('crypto_migration_generation_changed',409);
        return true;
    }
    public function draft($p,$actor,$key)
    {
        $this->fields($p,['generationId','authorization']);$row=$this->row($p['generationId'],$actor);
        if($row['mode']!=='supersede'||$row['state']!=='drafting')throw new NativeError('crypto_migration_generation_state',409);
        $migration=$this->migrationRow($row['migration_id']);if($this->published($migration))throw new NativeError('crypto_migration_generation_publication_boundary',409);
        [$command,$bytes,$signature]=NativeCryptoCodec::decode($p['authorization']);$b=$command['payload'];$sid=$this->uuid($b['scopeId']??null);
        $scopes=new NativeCryptoScopeV2($this->container,$this->bearer,$this->ip);$scope=$this->scope($sid,$actor['user']['id']);$head=$scopes->current($sid);
        if(!in_array($sid,json_decode($migration['scope_ids'],true,34,JSON_THROW_ON_ERROR),true)||$command['version']!==2||$command['operation']!=='crypto2.scope.headPut'||$command['accountId']!==$actor['user']['account_id']||$command['deviceId']!==$actor['device']['id']||$command['serverId']!==$this->serverId()||$command['signer']!=='device'||$b['epoch']!==1||$b['previousHeadHash']!==NativeCryptoDirectoryV2::ZERO||$b['accessIntentProof']!==null||$b['financePolicyIntentProof']!==null||$b['previousLifecycleHash']!==null)throw new NativeError('crypto_migration_generation_draft',409);
        $scopes->manager($head,$scope,$actor);if((int)$scope['owner_id']!==(int)$actor['user']['id'])throw new NativeError('crypto_migration_generation_owner_required',409);$scopes->currentAuthorReference($b['authorDirectoryHeadHash'],$actor);$scopes->validateProposal($b);$scopes->assertMembershipParity($scope,$b['members']);
        if($head){$oldBody=$scopes->body($head);foreach(['content','finance'] as $domain)if($b['keyCommitments'][$domain]!==null&&$b['keyCommitments'][$domain]===($oldBody['keyCommitments'][$domain]??null))throw new NativeError('crypto_migration_generation_fresh_keys_required',409);}
        $scopes->validateMembershipPlan($scope,$b,null,$actor);
        (new NativeCryptoKeyContributionV2($this->container,$this->bearer,$this->ip))->verifyContent($b,null,$scope,$actor['user']['account_id']);
        (new NativeCryptoFinanceContributionV2($this->container,$this->bearer,$this->ip))->verifyKey($b,null,$scope,$actor['user']['account_id']);
        if($b['initialLifecycleHash']!==(new NativeCryptoLifecycleV2($this->container))->initialBaseline($sid)['initialLifecycleHash'])throw new NativeError('crypto_migration_generation_draft',409);
        NativeCryptoV2Codec::verify($bytes,$signature,$key);
        $hash=$this->hash($p['authorization']);$headHash=hash('sha256',"JivieScopeHead/v2\n".NativeCryptoCodec::canonical((object)$b));
        $old=$this->one('SELECT proposal_hash FROM familyhub_crypto_migration_generation_drafts_v3 WHERE generation_id=? AND scope_id=?',[$row['id'],$sid]);
        if($old&&$old['proposal_hash']!==null&&$old['proposal_hash']!==$hash)throw new NativeError('crypto_migration_generation_immutable',409);
        if(!$old)$this->change('INSERT INTO familyhub_crypto_migration_generation_drafts_v3(generation_id,scope_id,head_hash,proposal_hash,authorization) VALUES(?,?,?,?,?)',[$row['id'],$sid,$headHash,$hash,NativeCryptoCodec::canonical((object)$p['authorization'])]);
        elseif($old['proposal_hash']===null)$this->change('UPDATE familyhub_crypto_migration_generation_drafts_v3 SET head_hash=?,proposal_hash=?,authorization=? WHERE generation_id=? AND scope_id=?',[$headHash,$hash,NativeCryptoCodec::canonical((object)$p['authorization']),$row['id'],$sid]);
        return ['generationId'=>$row['id'],'headHash'=>$headHash,'proposalHash'=>$hash];
    }
    public function seal($p,$actor)
    {
        $this->fields($p,['generationId']);$row=$this->row($p['generationId'],$actor);$migration=$this->migrationRow($row['migration_id']);
        if($row['state']!=='drafting')return $this->status($p,$actor);
        $context=json_decode($row['context'],true,64,JSON_THROW_ON_ERROR);$scopes=$this->scopes($migration,$row['id']);
        if($row['mode']==='supersede'&&array_filter($scopes,static fn($s)=>$s['candidateHeadHash']===null))throw new NativeError('crypto_migration_generation_drafts_pending',409);
        foreach($scopes as $i=>$scope){$old=$context['scopes'][$i];foreach(['scopeToken','headHash','accessRevision','lifecycleHash'] as $k)if($old[$k]!==$scope[$k])throw new NativeError('crypto_migration_generation_changed',409);}
        if(!$this->same($this->published($migration),$context['published']))throw new NativeError('crypto_migration_generation_publication_changed',409);
        $context['scopes']=$scopes;$hash=hash_init('sha256');hash_update($hash,"JivieMigrationRetainedEvidence/v3\n");$count=0;
        foreach($this->iterate('SELECT proof_hash FROM familyhub_crypto_migration_generation_evidence_v3 WHERE generation_id=? ORDER BY proof_hash',[$row['id']]) as $e){hash_update($hash,$e['proof_hash']."\n");$count++;}
        $context['retainedProofRoot']=hash_final($hash);$context['retainedProofCount']=$count;
        $contextHash=hash('sha256',"JivieMigrationGenerationContext/v3\n".NativeCryptoCodec::canonical((object)$context));
        $this->change("UPDATE familyhub_crypto_migration_generations_v3 SET context=?,context_hash=?,proof_root=?,state='review' WHERE id=?",[NativeCryptoCodec::canonical((object)$context),$contextHash,$context['retainedProofRoot'],$row['id']]);
        return $this->status($p,$actor);
    }
    public function approve($p,$actor)
    {
        $this->fields($p,['generationId','authorization','eventAuthorization']);$row=$this->row($p['generationId'],$actor);
        if($row['state']!=='review')throw new NativeError('crypto_migration_generation_state',409);
        [$b,$bytes,$signature]=NativeCryptoCodec::decode($p['authorization']);
        $this->fields($b,['version','serverId','migrationId','generationId','mode','contextHash','accountId','deviceId','authorDirectoryHeadHash','deviceSnapshotHash']);
        if($b['version']!==3||$b['serverId']!==$this->serverId()||$b['migrationId']!==$row['migration_id']||$b['generationId']!==$row['id']||$b['mode']!==$row['mode']||$b['contextHash']!==$row['context_hash']||$b['accountId']!==$actor['user']['account_id']||$b['deviceId']!==$actor['device']['id'])throw new NativeError('crypto_migration_generation_approval',409);
        $directory=new NativeCryptoDirectoryV2($this->container,$this->bearer,$this->ip);$current=$directory->current($b['accountId']);$snapshot=json_decode($current['snapshot'],true,34,JSON_THROW_ON_ERROR);$device=$directory->device($snapshot,$b['deviceId']);
        (new NativeCryptoScopeV2($this->container,$this->bearer,$this->ip))->currentAuthorReference($b['authorDirectoryHeadHash'],$actor);
        if(!$device||!$device['keyringWrite']||$current['device_snapshot_hash']!==$b['deviceSnapshotHash'])throw new NativeError('crypto_device_unapproved',403);
        NativeCryptoV2Codec::verify($bytes,$signature,$device['signingKeyBase64'],self::APPROVAL_DOMAIN);
        [$event]=NativeCryptoCodec::decode($p['eventAuthorization']);$ep=$event['payload'];$eventHash=hash('sha256',NativeCryptoCodec::base64($p['eventAuthorization']['commandBase64'],NativeCryptoCodec::MAX_COMMAND));
        $included=$this->one('SELECT authorization FROM familyhub_crypto_directory WHERE account_id=? AND command_hash=?',[$b['accountId'],$eventHash]);
        if(!$included||!$this->same(json_decode($included['authorization'],true,64,JSON_THROW_ON_ERROR),$p['eventAuthorization'])||$event['operation']!=='crypto2.account.migrationAttest'||$event['accountId']!==$b['accountId']||$ep['migrationId']!==$row['migration_id']||$ep['domain']!=='content'||$ep['scopeToken']!==self::token($b['serverId'],$row['migration_id'],$row['id'])||$ep['attestationHash']!==$this->hash($p['authorization']))throw new NativeError('crypto_migration_generation_anchor',409);
        $old=$this->one('SELECT authorization FROM familyhub_crypto_migration_generation_approvals_v3 WHERE generation_id=? AND account_id=?',[$row['id'],$b['accountId']]);
        if($old&&!$this->same(json_decode($old['authorization'],true,34,JSON_THROW_ON_ERROR),$p['authorization']))throw new NativeError('crypto_migration_generation_immutable',409);
        if(!$old)$this->change('INSERT INTO familyhub_crypto_migration_generation_approvals_v3 VALUES(?,?,?,?,?)',[$row['id'],$b['accountId'],NativeCryptoCodec::canonical((object)$p['authorization']),NativeCryptoCodec::canonical((object)$p['eventAuthorization']),$b['deviceSnapshotHash']]);
        return $this->status(['generationId'=>$row['id']],$actor);
    }

    private function ready($row)
    {
        if(!in_array($row['state'],['review','superseded'],true))throw new NativeError('crypto_migration_generation_state',409);
        $context=json_decode($row['context'],true,64,JSON_THROW_ON_ERROR);
        if(hash('sha256',"JivieMigrationGenerationContext/v3\n".NativeCryptoCodec::canonical((object)$context))!==$row['context_hash'])throw new NativeError('crypto_migration_generation_storage',503);
        $sink=hash_init('sha256');hash_update($sink,"JivieMigrationRetainedEvidence/v3\n");$count=0;
        foreach($this->iterate('SELECT proof_hash FROM familyhub_crypto_migration_generation_evidence_v3 WHERE generation_id=? ORDER BY proof_hash',[$row['id']]) as $e){hash_update($sink,$e['proof_hash']."\n");$count++;}
        if(hash_final($sink)!==$context['retainedProofRoot']||$count!==$context['retainedProofCount'])throw new NativeError('crypto_migration_generation_storage',503);
        $directory=new NativeCryptoDirectoryV2($this->container,$this->bearer,$this->ip);
        foreach($this->required($row['migration_id']) as $account){
            $approval=$this->one('SELECT * FROM familyhub_crypto_migration_generation_approvals_v3 WHERE generation_id=? AND account_id=?',[$row['id'],$account]);
            $user=$this->one('SELECT u.*,a.account_id FROM users u JOIN familyhub_accounts a ON a.user_id=u.id WHERE a.account_id=?',[$account]);
            if(!$approval||!$user||!(int)$user['is_active']||NativeCryptoAccountTombstoneV2::account($this->pdo,$account))throw new NativeError('crypto_migration_generation_approvals_pending',409);
            $proof=json_decode($approval['authorization'],true,34,JSON_THROW_ON_ERROR);[$b,$bytes,$signature]=NativeCryptoCodec::decode($proof);
            $current=$directory->current($account);$snapshot=json_decode($current['snapshot'],true,34,JSON_THROW_ON_ERROR);$device=$directory->device($snapshot,$b['deviceId']);
            if($b['version']!==3||$b['serverId']!==$this->serverId()||$b['generationId']!==$row['id']||$b['migrationId']!==$row['migration_id']||$b['mode']!==$row['mode']||$b['accountId']!==$account||$b['contextHash']!==$row['context_hash']||$current['device_snapshot_hash']!==$approval['device_snapshot_hash']||!$device||$device['revokedGeneration']!==null||!$device['keyringWrite']||$device['identityEpochId']!==$snapshot['identityEpochId'])throw new NativeError('crypto_migration_generation_authority_changed',409);
            (new NativeCryptoScopeV2($this->container,$this->bearer,$this->ip))->currentAuthorReference($b['authorDirectoryHeadHash'],['user'=>$user,'device'=>['id'=>$b['deviceId']]]);
            NativeCryptoV2Codec::verify($bytes,$signature,$device['signingKeyBase64'],self::APPROVAL_DOMAIN);
            $event=json_decode($approval['event_authorization'],true,64,JSON_THROW_ON_ERROR);$hash=hash('sha256',NativeCryptoCodec::base64($event['commandBase64'],NativeCryptoCodec::MAX_COMMAND));
            $stored=$this->one('SELECT authorization FROM familyhub_crypto_directory WHERE account_id=? AND command_hash=?',[$account,$hash]);
            $eb=$this->body($event);$ep=$eb['payload'];
            if(!$stored||!$this->same(json_decode($stored['authorization'],true,64,JSON_THROW_ON_ERROR),$event)||$eb['accountId']!==$account||$eb['operation']!=='crypto2.account.migrationAttest'||$ep['migrationId']!==$row['migration_id']||$ep['domain']!=='content'||$ep['scopeToken']!==self::token($this->serverId(),$row['migration_id'],$row['id'])||$ep['attestationHash']!==$this->hash($proof))throw new NativeError('crypto_migration_generation_anchor',409);
        }
        $migration=$this->migrationRowForApproval($row);
        $scopes=new NativeCryptoScopeV2($this->container,$this->bearer,$this->ip);
        foreach($row['state']==='superseded'?[]:json_decode($migration['scope_ids'],true,34,JSON_THROW_ON_ERROR) as $sid){
            $head=$scopes->current($sid);$managed=false;
            if(!$head&&$row['mode']==='supersede'){
                $owner=$this->one('SELECT u.*,a.account_id FROM familyhub_scopes s JOIN users u ON u.id=s.owner_id JOIN familyhub_accounts a ON a.user_id=u.id WHERE s.id=?',[$sid]);
                $approval=$owner?$this->one('SELECT authorization FROM familyhub_crypto_migration_generation_approvals_v3 WHERE generation_id=? AND account_id=?',[$row['id'],$owner['account_id']]):null;
                if($approval){$b=$this->body(json_decode($approval['authorization'],true,34,JSON_THROW_ON_ERROR));$scopes->manager(null,$this->scope($sid,$owner['id']),['user'=>$owner,'device'=>['id'=>$b['deviceId']]]);$managed=true;}
            }
            foreach($head?$scopes->body($head)['members']:[] as $member){
                if(!$member['manageKeys'])continue;
                $a=$this->one('SELECT authorization FROM familyhub_crypto_migration_generation_approvals_v3 WHERE generation_id=? AND account_id=?',[$row['id'],$member['accountId']]);
                if(!$a)continue;
                $b=$this->body(json_decode($a['authorization'],true,34,JSON_THROW_ON_ERROR));
                $user=$this->one('SELECT u.*,a.account_id FROM users u JOIN familyhub_accounts a ON a.user_id=u.id WHERE a.account_id=?',[$member['accountId']]);
                if(!$user)continue;
                $scopes->manager($head,$this->scope($sid,$user['id']),['user'=>$user,'device'=>['id'=>$b['deviceId']]]);$managed=true;break;
            }
            if(!$managed)throw new NativeError('crypto_migration_generation_manager_pending',409);
        }
        return $context;
    }

    private function migrationRowForApproval($row)
    {
        $migration=$this->one('SELECT * FROM familyhub_crypto_migrations_v2 WHERE id=?',[$row['migration_id']]);
        if(!$migration)throw new NativeError('crypto_migration_generation_missing',404);
        return $migration;
    }

    /** All old proof bytes remain in their original tables. Only the current
     * preparatory pointer is detached, after every exact candidate is reviewed. */
    public function finish($p,$actor,callable $unchanged,callable $createMigration)
    {
        if(!$this->transactionActive())throw new NativeError('crypto_migration_transaction_required',409);
        $this->fields($p,['generationId','contextHash']);$row=$this->row($p['generationId'],$actor);
        if($p['contextHash']!==$row['context_hash'])throw new NativeError('crypto_migration_generation_changed',409);
        if($row['mode']!=='supersede')throw new NativeError('crypto_migration_generation_state',409);
        if($row['state']==='superseded')return ['generationId'=>$row['id'],'state'=>'superseded','migrationId'=>$row['new_migration_id']];
        $context=$this->ready($row);$migration=$this->migrationRow($row['migration_id']);$unchanged($migration);
        $this->noAdmission($migration);
        if($this->published($migration)||!$this->same($this->scopes($migration,$row['id']),$context['scopes']))throw new NativeError('crypto_migration_generation_publication_changed',409);
        $scopes=new NativeCryptoScopeV2($this->container,$this->bearer,$this->ip);
        foreach(json_decode($migration['scope_ids'],true,34,JSON_THROW_ON_ERROR) as $sid){
            $draft=$this->one('SELECT authorization FROM familyhub_crypto_migration_generation_drafts_v3 WHERE generation_id=? AND scope_id=?',[$row['id'],$sid]);
            $proposal=$this->body(json_decode($draft['authorization'],true,34,JSON_THROW_ON_ERROR));
            $approval=$this->one('SELECT authorization FROM familyhub_crypto_migration_generation_approvals_v3 WHERE generation_id=? AND account_id=?',[$row['id'],$proposal['accountId']]);
            $approved=$this->body(json_decode($approval['authorization'],true,34,JSON_THROW_ON_ERROR));
            $user=$this->one('SELECT u.*,a.account_id FROM users u JOIN familyhub_accounts a ON a.user_id=u.id WHERE a.account_id=?',[$proposal['accountId']]);
            $scope=$this->scope($sid,$user['id']);$scopes->manager($scopes->current($sid),$scope,['user'=>$user,'device'=>['id'=>$approved['deviceId']]]);
            $scopes->currentAuthorReference($proposal['payload']['authorDirectoryHeadHash'],['user'=>$user,'device'=>['id'=>$proposal['deviceId']]]);
        }
        $this->change("UPDATE familyhub_crypto_migrations_v2 SET state='aborted',updated_at=? WHERE id=?",[time(),$migration['id']]);
        $this->change("UPDATE familyhub_crypto_migration_generations_v3 SET state='superseded' WHERE id=?",[$row['id']]);
        foreach(json_decode($migration['scope_ids'],true,34,JSON_THROW_ON_ERROR) as $sid){
            $this->change("UPDATE familyhub_crypto_scope_heads SET state='superseded' WHERE scope_id=?",[$sid]);
            $this->change('DELETE FROM familyhub_crypto_scope_state WHERE scope_id=?',[$sid]);
            $this->change("UPDATE familyhub_crypto_scopes SET state='staged',migration_id=?,epoch=1,sequence=0 WHERE scope_id=?",[$row['new_migration_id'],$sid]);
        }
        $createMigration($migration,$row['new_migration_id'],$actor);
        return ['generationId'=>$row['id'],'state'=>'superseded','migrationId'=>$row['new_migration_id'],'legacyPreserved'=>true];
    }

    public function approvedHead($scopeId,$body,$proof,$actor)
    {
        $row=$this->one("SELECT g.* FROM familyhub_crypto_migration_generations_v3 g JOIN familyhub_crypto_scopes s ON s.migration_id=g.new_migration_id WHERE s.scope_id=? AND g.state='superseded'",[$scopeId]);
        if(!$row)return false;
        $this->ready($row);
        $draft=$this->one('SELECT proposal_hash,head_hash FROM familyhub_crypto_migration_generation_drafts_v3 WHERE generation_id=? AND scope_id=?',[$row['id'],$scopeId]);
        return $draft&&$draft['proposal_hash']===$this->hash($proof)&&$draft['head_hash']===hash('sha256',"JivieScopeHead/v2\n".NativeCryptoCodec::canonical((object)$body))&&$body['epoch']===1&&$body['previousHeadHash']===NativeCryptoDirectoryV2::ZERO;
    }

    public function supersededPreparation($scopeId)
    {
        return (bool)$this->one("SELECT g.id FROM familyhub_crypto_migration_generations_v3 g JOIN familyhub_crypto_scopes s ON s.migration_id=g.new_migration_id JOIN familyhub_crypto_migration_generation_drafts_v3 d ON d.generation_id=g.id AND d.scope_id=s.scope_id WHERE s.scope_id=? AND g.state='superseded'",[$scopeId]);
    }

    /** The final coordinator is the sole caller. Context lifetime is exactly
     * one locked SQL transaction and is reset even when validation throws. */
    public function withContinuedEvidence($migrationId,$actor,callable $unchanged,callable $body)
    {
        if(!$this->transactionActive())throw new NativeError('crypto_migration_transaction_required',409);
        $row=$this->one("SELECT * FROM familyhub_crypto_migration_generations_v3 WHERE migration_id=? AND mode='continue' AND state='review' ORDER BY created_at DESC,id DESC LIMIT 1",[$migrationId]);
        if(!$row)return $body();
        $context=$this->ready($row);$migration=$this->migrationRow($migrationId);$unchanged($migration);$this->noAdmission($migration);
        $expected=$context['scopes'];$actual=$this->scopes($migration);
        foreach($actual as $i=>$scope){foreach(['scopeToken','headHash','accessRevision','lifecycleHash'] as $key)if($scope[$key]!==$expected[$i][$key])throw new NativeError('crypto_migration_generation_changed',409);}
        $published=$this->published($migration);$by=[];foreach($published as $p)$by[$p['scopeToken']]=$p;
        foreach($context['published'] as $p)if(!isset($by[$p['scopeToken']])||!$this->same($by[$p['scopeToken']],$p))throw new NativeError('crypto_migration_generation_publication_changed',409);
        self::$contexts??=new \WeakMap();
        if(isset(self::$contexts[$this->pdo]))throw new NativeError('crypto_migration_generation_nested',409);
        self::$contexts[$this->pdo]=[$this,$row['id']];
        try{return $body();}finally{unset(self::$contexts[$this->pdo]);}
    }

    public static function continuedActor($pdo,$actor)
    {
        if(!self::$contexts||!isset(self::$contexts[$pdo]))return $actor;
        [$helper,$generation]=self::$contexts[$pdo];
        $row=$helper->one('SELECT authorization FROM familyhub_crypto_migration_generation_approvals_v3 WHERE generation_id=? AND account_id=?',[$generation,$actor['user']['account_id']]);
        if(!$row)throw new NativeError('crypto_migration_generation_approvals_pending',409);
        $b=$helper->body(json_decode($row['authorization'],true,34,JSON_THROW_ON_ERROR));
        $actor['device']['id']=$b['deviceId'];return $actor;
    }

    public static function retainedScope($pdo,$scopeId,$headHash)
    {
        if(!self::$contexts||!isset(self::$contexts[$pdo]))return false;
        [$helper,$generation]=self::$contexts[$pdo];$row=$helper->row($generation);
        $context=json_decode($row['context'],true,64,JSON_THROW_ON_ERROR);
        $token=NativeCryptoMigrationCommitmentsV3::scopeToken($helper->serverId(),$row['migration_id'],$scopeId,'content');
        foreach($context['scopes'] as $scope)if($scope['scopeToken']===$token&&$scope['headHash']===$headHash)return true;
        return false;
    }

    /** Historical membership is usable only for the exact unchanged signed
     * head reviewed by fresh managers in this final locked transaction. Live
     * SQL roles/users/finance parity remains the caller's normal validation. */
    public static function retainedMembershipDirectories($pdo,$scopeId,$headHash,$members)
    {
        if(!self::$contexts||!isset(self::$contexts[$pdo])||!self::retainedScope($pdo,$scopeId,$headHash))return null;
        [$helper,$generation]=self::$contexts[$pdo];
        $head=$helper->one("SELECT h.payload FROM familyhub_crypto_scope_heads h JOIN familyhub_crypto_scope_state s ON s.scope_id=h.scope_id AND s.head_hash=h.head_hash WHERE h.scope_id=? AND h.head_hash=? AND h.state='active'",[$scopeId,$headHash]);
        $body=$head?json_decode($head['payload'],true,34,JSON_THROW_ON_ERROR):null;
        if(!$body||($body['scopeId']??null)!==$scopeId||hash('sha256',"JivieScopeHead/v2\n".NativeCryptoCodec::canonical((object)$body))!==$headHash||!$helper->same($body['members'],$members))throw new NativeError('crypto_migration_generation_changed',409);
        $directory=new NativeCryptoDirectoryV2($helper->container,$helper->bearer,$helper->ip);$result=[];
        foreach($members as $member){
            if(NativeCryptoAccountTombstoneV2::account($pdo,$member['accountId']))throw new NativeError('crypto_scope_rotation_required',409);
            $prefix=$helper->historicalPrefix($member['accountId'],$member['directoryHeadHash'],null);
            $historical=$prefix['memberDirectory'];
            foreach($historical as $field=>$value)if(($member[$field]??null)!==$value)throw new NativeError('crypto_member_directory_changed',409);
            $current=$directory->current($member['accountId']);$snapshot=json_decode($current['snapshot'],true,34,JSON_THROW_ON_ERROR);
            foreach(['rootSigningKeyBase64','rootEncryptionKeyBase64','recoveryRootEpochId'] as $field)if($snapshot[$field]!==$historical[$field])throw new NativeError('crypto_member_directory_changed',409);
            $result[$member['accountId']]=$historical;
        }
        return $result;
    }

    public static function retainedSigningKey($pdo,$proof,$account)
    {
        if(!self::$contexts||!isset(self::$contexts[$pdo]))return null;
        [$helper,$generation]=self::$contexts[$pdo];
        $row=$helper->one('SELECT * FROM familyhub_crypto_migration_generation_evidence_v3 WHERE generation_id=? AND proof_hash=? AND account_id=?',[$generation,$helper->hash($proof),$account]);
        if(!$row)return null;
        $prefix = $helper->historicalPrefix($account,$row['author_reference'],$row['device_id']);
        $device = $prefix['devices'][$row['device_id']];
        return $device['signingKeyBase64'];
    }

    public static function retainedReference($pdo,$account,$reference,$device)
    {
        if(!self::$contexts||!isset(self::$contexts[$pdo]))return false;
        [$helper,$generation]=self::$contexts[$pdo];
        return (bool)$helper->one('SELECT proof_hash FROM familyhub_crypto_migration_generation_evidence_v3 WHERE generation_id=? AND account_id=? AND device_id=? AND author_reference=? LIMIT 1',[$generation,$account,$device,$reference]);
    }
    public function status($p,$actor)
    {
        $this->fields($p,[],['generationId','migrationId']);
        if(count($p)!==1)throw new NativeError('validation_error');
        if(isset($p['migrationId'])){
            $this->uuid($p['migrationId']);
            $selected=$this->one('SELECT id FROM familyhub_crypto_migration_generations_v3 WHERE migration_id=? ORDER BY created_at DESC,id DESC LIMIT 1',[$p['migrationId']]);
            if(!$selected)throw new NativeError('crypto_migration_generation_missing',404);
            $p=['generationId'=>$selected['id']];
        }
        $row=$this->row($p['generationId'],$actor);$context=json_decode($row['context'],true,64,JSON_THROW_ON_ERROR);
        $approvals=$this->many('SELECT account_id,authorization,event_authorization FROM familyhub_crypto_migration_generation_approvals_v3 WHERE generation_id=? ORDER BY account_id',[$row['id']]);
        $targets=[];$migration=$this->migrationRowForApproval($row);$scopes=new NativeCryptoScopeV2($this->container,$this->bearer,$this->ip);
        foreach(json_decode($migration['scope_ids'],true,34,JSON_THROW_ON_ERROR) as $sid){
            try{$scope=$this->scope($sid,$actor['user']['id']);}catch(NativeError $e){continue;}
            $head=$scopes->current($sid);$member=$head?$scopes->member($scopes->body($head),$actor['user']['account_id']):null;
            if(!$member&&(int)$scope['owner_id']!==(int)$actor['user']['id'])continue;
            $draft=$this->one('SELECT authorization FROM familyhub_crypto_migration_generation_drafts_v3 WHERE generation_id=? AND scope_id=?',[$row['id'],$sid]);
            $targets[]=['scopeId'=>$sid,'scopeToken'=>NativeCryptoMigrationCommitmentsV3::scopeToken($this->serverId(),$row['migration_id'],$sid,'content'),
                'accessRevision'=>(int)$scope['access_revision'],'headHash'=>$head['head_hash']??null,'canDraft'=>(int)$scope['owner_id']===(int)$actor['user']['id'],
                'candidateAuthorization'=>$draft&&$draft['authorization']!==null?json_decode($draft['authorization'],true,64,JSON_THROW_ON_ERROR):null];
        }
        return ['version'=>3,'targets'=>$targets,'generationId'=>$row['id'],'migrationId'=>$row['migration_id'],'mode'=>$row['mode'],'state'=>$row['state'],
            'context'=>$context,'contextHash'=>$row['context_hash'],'approvals'=>array_map(fn($a)=>['accountToken'=>hash('sha256',"JivieGenerationAccount/v3\n".$row['id']."\n".$a['account_id']),'approvalHash'=>$this->hash(json_decode($a['authorization'],true,34,JSON_THROW_ON_ERROR))]+($a['account_id']===$actor['user']['account_id']?['authorization'=>json_decode($a['authorization'],true,34,JSON_THROW_ON_ERROR),'eventAuthorization'=>json_decode($a['event_authorization'],true,64,JSON_THROW_ON_ERROR)]:[]),$approvals)];
    }
}
