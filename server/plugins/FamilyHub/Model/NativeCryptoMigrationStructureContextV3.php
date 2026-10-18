<?php
namespace Kanboard\Plugin\FamilyHub\Model;

/** Scoped source attestations. Private source statements never leave their
 * contributor; child readers receive only explicitly consented minimal cards.
 * This is a manager attestation, not selective proof of unseen SQL plaintext. */
class NativeCryptoMigrationStructureContextV3 extends NativeDatabase
{
    protected $cryptoAccess = true;
    public const SOURCE_DOMAIN = "JivieE2EE/structureSource/v3\n";
    public const CERTIFICATE_DOMAIN = "JivieE2EE/structureSourceCertificate/v3\n";
    public const CONTEXT_DOMAIN = "JivieE2EE/structureContext/v3\n";
    public const CONSENT_DOMAIN = "JivieE2EE/structureContextConsent/v3\n";
    public const TABLES = ['familyhub_scopes','familyhub_members','familyhub_organization_leaders',
        'familyhub_scope_revocations','familyhub_personal_scopes','familyhub_record_relocations',
        'familyhub_finance_policy','familyhub_finance_grants'];

    private function requiredTransaction()
    {
        if (!$this->transactionActive()) throw new NativeError('crypto_migration_transaction_required',409);
    }
    private function digest($v)
    {
        if (!is_string($v) || !preg_match('/^[a-f0-9]{64}$/D',$v)) throw new NativeError('crypto_structure_context');
        return $v;
    }
    private function same($a,$b)
    {
        return NativeCryptoCodec::canonical($a) === NativeCryptoCodec::canonical($b);
    }
    public static function proofHash($proof)
    {
        return hash('sha256',NativeCryptoCodec::canonical((object)$proof));
    }
    public static function sourceToken($body)
    {
        return hash('sha256',"JivieStructureSourceToken/v3\n".NativeCryptoCodec::canonical((object)[
            'version'=>3,'serverId'=>$body['serverId'],'migrationId'=>$body['migrationId'],
            'accountId'=>$body['accountId'],'scopeId'=>$body['scopeId']]));
    }
    private function context($body,$actor)
    {
        if (($body['version']??null)!==3 || ($body['serverId']??null)!==$this->serverId() ||
            ($body['accountId']??null)!==$actor['user']['account_id']) throw new NativeError('crypto_identity_mismatch',403);
        foreach (['migrationId','captureId','accountId','deviceId'] as $key) $this->uuid($body[$key]);
        $this->digest($body['sourceInventoryRoot']);$this->digest($body['authorDirectoryHeadHash']);
    }
    private function sameCapture($p,$body)
    {
        foreach (['migrationId','captureId','sourceInventoryRoot'] as $field) {
            if ($p[$field]!==$body[$field]) throw new NativeError('crypto_capture_generation_conflict',409);
        }
    }
    private function signed($proof,$domain,$actor)
    {
        [$body,$bytes,$signature]=NativeCryptoCodec::decode($proof);
        $this->context($body,$actor);
        $retained=NativeCryptoMigrationGenerationV3::retainedSigningKey($this->pdo,$proof,$body['accountId']);
        if($retained!==null){
            NativeCryptoV2Codec::verify($bytes,$signature,$retained,$domain);
            $prefix=$this->one('SELECT * FROM familyhub_crypto_directory WHERE account_id=? AND head_hash=?',[$body['accountId'],$body['authorDirectoryHeadHash']]);
            if(!$prefix)throw new NativeError('crypto_structure_source_signer_changed',409);
            return [$body,$prefix,json_decode($prefix['snapshot'],true,34,JSON_THROW_ON_ERROR)];
        }
        if ($body['deviceId']!==$actor['device']['id']) throw new NativeError('crypto_identity_mismatch',403);
        $directory=new NativeCryptoDirectoryV2($this->container);
        $current=$directory->current($body['accountId']);
        $ref=$this->one('SELECT device_snapshot_hash,identity_epoch_id FROM familyhub_crypto_directory WHERE account_id=? AND head_hash=?',[$body['accountId'],$body['authorDirectoryHeadHash']]);
        if (!$current || !$ref || $ref['device_snapshot_hash']!==$current['device_snapshot_hash'] ||
            $ref['identity_epoch_id']!==$current['identity_epoch_id']) throw new NativeError('crypto_structure_source_signer_changed',409);
        $snapshot=json_decode($current['snapshot'],true,34,JSON_THROW_ON_ERROR);
        $device=$directory->device($snapshot,$body['deviceId']);
        if (!$device || $device['revokedGeneration']!==null || $device['identityEpochId']!==$snapshot['identityEpochId']) throw new NativeError('crypto_device_unapproved',403);
        NativeCryptoV2Codec::verify($bytes,$signature,$device['signingKeyBase64'],$domain);
        return [$body,$current,$snapshot];
    }
    private function manager($sid,$headHash,$actor,$owner=false)
    {
        $scope=$this->scope($this->uuid($sid),$actor['user']['id']);
        $scopes=new NativeCryptoScopeV2($this->container,$this->bearer,$this->ip);$head=$scopes->current($sid);
        if (!$head || $head['head_hash']!==$this->digest($headHash)) throw new NativeError('crypto_structure_source_head_changed',409);
        $member=$scopes->member($scopes->body($head),$actor['user']['account_id']);
        if (!$member || !$member['manageKeys'] || $owner && ((int)$scope['owner_id']!==(int)$actor['user']['id'] || $member['role']!=='owner')) throw new NativeError('permission_revoked',403);
        $current=(new NativeCryptoDirectoryV2($this->container))->current($actor['user']['account_id']);
        if (!$current || $member['deviceSnapshotHash']!==$current['device_snapshot_hash'] && !NativeCryptoMigrationGenerationV3::retainedScope($this->pdo,$sid,$headHash)) {
            throw new NativeError('crypto_structure_source_signer_changed',409);
        }
        $scopes->assertCurrentMembership($scope,$head);
        return [$scope,$head];
    }
    /** A consent authenticates this contributor's own comparison. It does not
     * manage another member's keys. Receipt-only/empty content contributors
     * require the exact scope assignment in their signed capture.prepare. */
    private function reviewer($body,$actor,callable $bindings)
    {
        $scope=$this->scope($this->uuid($body['scopeId']),$actor['user']['id']);
        $scopes=new NativeCryptoScopeV2($this->container);$head=$scopes->current($body['scopeId']);
        if (!$head || $head['head_hash']!==$body['membershipHeadHash']) throw new NativeError('crypto_structure_context_head_changed',409);
        $member=$scopes->member($scopes->body($head),$actor['user']['account_id']);
        if (!$member) throw new NativeError('permission_revoked',403);
        $scopes->assertCurrentMembership($scope,$head);
        // Iterating an empty closed set still authenticates owned sealed
        // capture/root/fence. There is no READ-to-WRITE or manageKeys grant.
        foreach ($bindings($body['migrationId'],$body['captureId'],$body['sourceInventoryRoot'],$actor,[]) as $unused) {}
        $capture=$this->one('SELECT authorization FROM familyhub_crypto_captures_v3 WHERE migration_id=? AND account_id=? AND capture_id=?',[
            $body['migrationId'],$actor['user']['account_id'],$body['captureId']]);
        if (!$capture) throw new NativeError('crypto_capture_generation_conflict',409);
        [$prepare]=NativeCryptoCodec::decode(json_decode($capture['authorization'],true,64,JSON_THROW_ON_ERROR));
        foreach ($prepare['payload']['receiptSelections']??[] as $selection) {
            if ($selection===['scopeId'=>$body['scopeId'],'domain'=>'content'] ||
                $this->same($selection,['scopeId'=>$body['scopeId'],'domain'=>'content'])) return;
        }
        throw new NativeError('permission_revoked',403);
    }
    private function cells($typed)
    {
        if (!is_object($typed)) throw new NativeError('crypto_structure_source');$out=[];
        foreach (get_object_vars($typed) as $key=>$cell) {
            if (!is_array($cell) || !array_key_exists('valueBase64',$cell)) throw new NativeError('crypto_structure_source');
            $value=$cell['valueBase64'];$decoded=$value===null?null:base64_decode($value,true);
            if ($value!==null && ($decoded===false || base64_encode($decoded)!==$value)) throw new NativeError('crypto_structure_source');
            $out[$key]=$decoded;
        }
        return $out;
    }
    private function sourceFacts($rows,$sid)
    {
        $scope=$rows['familyhub_scopes']??[];
        if (count($scope)!==1 || $scope[0]['id']!==$sid || $scope[0]['deleted_at']!==null) throw new NativeError('crypto_structure_source_incomplete',409);
        $raw=$scope[0];$owner=$this->one('SELECT account_id FROM familyhub_accounts WHERE user_id=?',[$raw['owner_id']]);
        if (!$owner) throw new NativeError('crypto_structure_source_identity',409);
        $parent=$raw['parent_scope_id']??$raw['organization_id']??null;
        $descriptor=['kind'=>$raw['kind'],'accessPolicyVersion'=>(int)$raw['access_policy_version'],
            'ownArchived'=>$raw['archived']==='1','parentScopeToken'=>$parent===null?null:(new NativeCryptoLifecycleV2($this->container))->parentToken($sid,$parent),
            'ownerAccountId'=>$owner['account_id']];
        if (!in_array($descriptor['kind'],['personal','household','organization','project'],true) ||
            !in_array($descriptor['accessPolicyVersion'],[1,2,3],true) || !in_array($raw['archived'],['0','1'],true)) throw new NativeError('crypto_structure_source');
        $leaders=array_column($rows['familyhub_organization_leaders']??[],'account_id');$members=[];
        foreach ($rows['familyhub_members']??[] as $row) {
            if ($row['active']!=='1') continue;
            $account=$this->one('SELECT user_id FROM familyhub_accounts WHERE account_id=?',[$row['account_id']]);
            if (!$account || (string)$account['user_id']!==$row['user_id'] || !in_array($row['role'],['owner','member','viewer'],true) || isset($members[$row['account_id']])) throw new NativeError('crypto_structure_source_identity',409);
            $members[$row['account_id']]=['accountId'=>$row['account_id'],'role'=>$row['role'],'leader'=>in_array($row['account_id'],$leaders,true)];
        }
        ksort($members,SORT_STRING);
        if (count($members)>100 || ($members[$owner['account_id']]['role']??null)!=='owner') throw new NativeError('crypto_structure_source_incomplete',409);
        $policies=$rows['familyhub_finance_policy']??[];
        if (count($policies)>1) throw new NativeError('crypto_structure_source_finance_policy',409);
        $policy=$policies ? $policies[0] : ['enabled'=>'0','revision'=>'0','required_contract_version'=>'1'];
        if (!in_array($policy['enabled'],['0','1'],true) || !preg_match('/^(0|[1-9][0-9]*)$/D',$policy['revision']) ||
            !preg_match('/^[1-3]$/D',$policy['required_contract_version']) ||
            strlen($policy['revision'])>16 || (int)$policy['revision']>9007199254740991) {
            throw new NativeError('crypto_structure_source_finance_policy',409);
        }
        $grants=[];
        foreach ($rows['familyhub_finance_grants']??[] as $grant) {
            $this->uuid($grant['account_id']);
            if (isset($grants[$grant['account_id']]) || !in_array($grant['access_level'],['none','read','write'],true)) throw new NativeError('crypto_structure_source_finance_policy',409);
            $grants[$grant['account_id']]=['accountId'=>$grant['account_id'],'grant'=>$grant['access_level']];
        }
        ksort($grants,SORT_STRING);
        $finance=['enabled'=>$policy['enabled']==='1','revision'=>(int)$policy['revision'],
            'requiredContractVersion'=>(int)$policy['required_contract_version'],'grants'=>array_values($grants)];
        return [$descriptor,array_values($members),$finance];
    }

    /** Complete independent owner-content FILE/control statement, before full
     * component parity. Finance ACL metadata is included; monetary controls and
     * child portions do not participate in this prerequisite. */
    public function source($p,$actor,callable $bindings,callable $resolve,callable $target,callable $topology)
    {
        $this->requiredTransaction();$this->fields($p,['migrationId','captureId','sourceInventoryRoot','statementAuthorization','certificateAuthorization']);
        [$s]=$this->signed($p['statementAuthorization'],self::SOURCE_DOMAIN,$actor);
        $this->sameCapture($p,$s);
        $this->fields($s,['version','operation','serverId','migrationId','captureId','accountId','sourceInventoryRoot',
            'scopeId','membershipHeadHash','scopeMetadataWireId','scopeMetadataProofHash','lifecycleHash',
            'sourceBindingCount','sourceCommitmentRoot','contentStructureHash','descriptor','members','financePolicy','deviceId','authorDirectoryHeadHash'],['contextProofHashes','financeTopology']);
        if ($s['operation']!=='crypto2.migration.structure.sourceStatement') throw new NativeError('crypto_structure_source');
        [$scope,$head]=$this->manager($s['scopeId'],$s['membershipHeadHash'],$actor,true);
        $header=['version'=>3,'serverId'=>$s['serverId'],'migrationId'=>$s['migrationId'],'captureId'=>$s['captureId'],'sourceInventoryRoot'=>$s['sourceInventoryRoot'],'scopeId'=>$s['scopeId']];
        $sink=hash_init('sha256');
        hash_update($sink,"JivieMigrationStructureSources/v3\n".NativeCryptoCodec::canonical((object)$header)."\n");
        $rows=[];$sourceScopes=[];$sourceCount=0;$last=null;$scopeBindingId=null;
        foreach ($bindings($s['migrationId'],$s['captureId'],$s['sourceInventoryRoot'],$actor,self::TABLES) as $entry) {
            $b=NativeCryptoCaptureV3::binding($entry['binding']);
            if ($last!==null && strcmp($last,$b['bindingId'])>=0) throw new NativeError('crypto_structure_source_order');$last=$b['bindingId'];
            if ($entry['context']['sourceTable']==='familyhub_scopes') $sourceScopes[$entry['context']['scopeId']]=true;
            if ($entry['context']['scopeId']!==$s['scopeId']) continue;
            $source=$resolve($s['migrationId'],$s['captureId'],$b['bindingId'],$actor);
            if (!$this->same($b,$source['binding']) || !$this->same($entry['context'],$source['context']) || !in_array($source['context']['sourceTable'],self::TABLES,true)) throw new NativeError('crypto_structure_source');
            $table=$source['context']['sourceTable'];
            if ($table==='familyhub_scopes') $scopeBindingId=$b['bindingId'];
            if (in_array($table,['familyhub_scopes','familyhub_members','familyhub_organization_leaders',
                'familyhub_finance_policy','familyhub_finance_grants'],true)) {
                $cells=$this->cells($source['typedRow']);
                if ($table!=='familyhub_members' || ($cells['active']??null)==='1') $rows[$table][]=$cells;
            }
            hash_update($sink,NativeCryptoCodec::canonical((object)[
                'bindingId'=>$b['bindingId'],'sourceCommitment'=>$b['sourceCommitment']])."\n");
            ++$sourceCount;
        }
        [$descriptor,$members,$finance]=$this->sourceFacts($rows,$s['scopeId']);
        $rootScope=in_array($descriptor['kind'],['household','organization'],true);
        if ($rootScope) {
            $observed=$topology($s['migrationId'],$s['captureId'],$s['sourceInventoryRoot'],$scopeBindingId,$actor);
            if (!array_key_exists('financeTopology',$s) || !$this->same($s['financeTopology'],$observed['topology'])) {
                throw new NativeError('crypto_structure_source_topology',409);
            }
        } elseif (array_key_exists('financeTopology',$s)) {
            throw new NativeError('crypto_structure_source_topology',409);
        }
        if (!$this->same($s['descriptor'],$descriptor) || !$this->same($s['members'],$members) ||
            !$this->same($s['financePolicy'],$finance)) throw new NativeError('crypto_structure_source_facts',409);
        $root=hash_final($sink);$this->digest($s['scopeMetadataProofHash']);$this->digest($s['lifecycleHash']);
        $section=['version'=>3,'scopeId'=>$s['scopeId'],'membershipHeadHash'=>$s['membershipHeadHash'],
            'scopeMetadataProofHash'=>$s['scopeMetadataProofHash'],'lifecycleHash'=>$s['lifecycleHash'],
            'sourceBindingCount'=>$sourceCount,'sourceCommitmentRoot'=>$root];
        if ($s['sourceBindingCount']!==$sourceCount || $s['sourceCommitmentRoot']!==$root ||
            $s['contentStructureHash']!==NativeCryptoMigrationStructureV3::structureHash($header,$section,$s['contextProofHashes']??null) ||
            (new NativeCryptoLifecycleV2($this->container))->closingHash($s['scopeId'])!==$s['lifecycleHash']) throw new NativeError('crypto_structure_source_commitment',409);
        $parent=$scope['parent_scope_id']??$scope['organization_id']??null;
        $required=$parent!==null && !isset($sourceScopes[$parent])?['parentAccess']:[];
        if ($required || array_key_exists('contextProofHashes',$s)) {
            $this->verify($s['scopeId'],$s['membershipHeadHash'],$s['contextProofHashes']??[],$actor,
                $required,$s['captureId'],$s['sourceInventoryRoot'],$bindings);
        }
        $metadata=$target($s['migrationId'],$s['scopeId'],$s['scopeMetadataWireId'],$s['scopeMetadataProofHash'],$actor);
        $record=$metadata['record'];$scopes=new NativeCryptoScopeV2($this->container);
        if ($record['type']!=='scopeMetadata' || $record['deleted'] || !($scopes->member($scopes->body($head),$record['accountId'])['manageKeys']??false)) throw new NativeError('crypto_migration_metadata_authority',403);
        [$c]=$this->signed($p['certificateAuthorization'],self::CERTIFICATE_DOMAIN,$actor);
        $expected=array_intersect_key($s,array_flip(['version','serverId','migrationId','captureId','accountId','sourceInventoryRoot','membershipHeadHash','sourceBindingCount','sourceCommitmentRoot','contentStructureHash','deviceId','authorDirectoryHeadHash']));
        $expected+=['operation'=>'crypto2.migration.structure.sourceCertificate','scopeToken'=>self::sourceToken($s),'sourceStatementHash'=>self::proofHash($p['statementAuthorization'])];
        if (!$this->same($c,$expected)) throw new NativeError('crypto_structure_source_certificate',409);
        $hash=self::proofHash($p['certificateAuthorization']);
        $old=$this->one('SELECT * FROM familyhub_crypto_structure_sources_v3 WHERE migration_id=? AND account_id=? AND scope_id=?',[$s['migrationId'],$s['accountId'],$s['scopeId']]);
        if ($old) {
            if ($old['certificate_hash']!==$hash || !$this->same(json_decode($old['statement_authorization'],true,34,JSON_THROW_ON_ERROR),$p['statementAuthorization'])) throw new NativeError('crypto_structure_source_immutable',409);
        } else {
            $this->change('INSERT INTO familyhub_crypto_structure_sources_v3(migration_id,account_id,scope_id,certificate_hash,statement_authorization,certificate_authorization,event_authorization) VALUES(?,?,?,?,?,?,NULL)',[$s['migrationId'],$s['accountId'],$s['scopeId'],$hash,json_encode($p['statementAuthorization'],JSON_THROW_ON_ERROR),json_encode($p['certificateAuthorization'],JSON_THROW_ON_ERROR)]);
        }
        return ['certificateHash'=>$hash,'sourceBindingCount'=>$sourceCount,'sourceCommitmentRoot'=>$root];
    }
    private function sourceRow($hash)
    {
        $row=$this->one('SELECT * FROM familyhub_crypto_structure_sources_v3 WHERE certificate_hash=?',[$this->digest($hash)]);
        if (!$row) throw new NativeError('crypto_structure_source_pending',409);
        return $row;
    }
    private function included($row,$eventProof)
    {
        [$e]=NativeCryptoCodec::decode($eventProof);$p=$e['payload']??[];
        [$cert]=NativeCryptoCodec::decode(json_decode($row['certificate_authorization'],true,34,JSON_THROW_ON_ERROR));
        $stored=$this->one('SELECT authorization FROM familyhub_crypto_directory WHERE account_id=? AND command_hash=?',[$row['account_id'],hash('sha256',base64_decode($eventProof['commandBase64'],true))]);
        if (!$stored || !$this->same(json_decode($stored['authorization'],true,34,JSON_THROW_ON_ERROR),$eventProof) ||
            $e['operation']!=='crypto2.account.migrationAttest' || $e['accountId']!==$row['account_id'] || $e['serverId']!==$this->serverId() ||
            ($p['migrationId']??null)!==$row['migration_id'] || ($p['domain']??null)!=='content' ||
            ($p['scopeToken']??null)!==$cert['scopeToken'] || ($p['attestationHash']??null)!==$row['certificate_hash']) throw new NativeError('crypto_structure_source_anchor',409);
        (new NativeCryptoDirectoryV2($this->container))->current($row['account_id']);
    }
    public function anchor($p,$actor)
    {
        $this->requiredTransaction();$this->fields($p,['migrationId','captureId','sourceInventoryRoot','certificateHash','eventAuthorization']);$row=$this->sourceRow($p['certificateHash']);
        if ($row['account_id']!==$actor['user']['account_id']) throw new NativeError('permission_revoked',403);
        [$certificate]=NativeCryptoCodec::decode(json_decode($row['certificate_authorization'],true,34,JSON_THROW_ON_ERROR));
        $this->sameCapture($p,$certificate);
        $this->included($row,$p['eventAuthorization']);$encoded=json_encode($p['eventAuthorization'],JSON_THROW_ON_ERROR);
        if ($row['event_authorization']!==null && !$this->same(json_decode($row['event_authorization'],true,34,JSON_THROW_ON_ERROR),$p['eventAuthorization'])) throw new NativeError('crypto_structure_source_immutable',409);
        $this->change('UPDATE familyhub_crypto_structure_sources_v3 SET event_authorization=? WHERE certificate_hash=?',[$encoded,$p['certificateHash']]);
        return ['certificateHash'=>$p['certificateHash'],'state'=>'anchored'];
    }
    private function sourceCurrent($row)
    {
        if ($row['event_authorization']===null) throw new NativeError('crypto_structure_source_anchor_pending',409);
        $proof=json_decode($row['statement_authorization'],true,34,JSON_THROW_ON_ERROR);[$s]=NativeCryptoCodec::decode($proof);
        $user=$this->one('SELECT a.user_id FROM familyhub_accounts a JOIN users u ON u.id=a.user_id WHERE a.account_id=? AND u.is_active=1',[$row['account_id']]);
        if (!$user) throw new NativeError('crypto_structure_source_signer_changed',409);
        $actor=['user'=>['id'=>(int)$user['user_id'],'account_id'=>$row['account_id']],'device'=>['id'=>$s['deviceId']]];
        $this->signed($proof,self::SOURCE_DOMAIN,$actor);$this->signed(json_decode($row['certificate_authorization'],true,34,JSON_THROW_ON_ERROR),self::CERTIFICATE_DOMAIN,$actor);
        $this->manager($s['scopeId'],$s['membershipHeadHash'],$actor,true);
        $this->included($row,json_decode($row['event_authorization'],true,34,JSON_THROW_ON_ERROR));
        return [$s,$actor];
    }
    private function expectedFacts($s,$purpose)
    {
        $d=$s['descriptor'];$members=$s['members'];
        if ($purpose==='parentAccess') {
            if ($d['accessPolicyVersion']===1) $members=[];
            elseif ($d['accessPolicyVersion']===2) $members=array_values(array_filter($members,fn($m)=>$d['kind']==='organization' && ($m['role']==='owner'||$m['leader'])));
            return ['kind'=>$d['kind'],'accessPolicyVersion'=>$d['accessPolicyVersion'],'ownArchived'=>$d['ownArchived'],'members'=>$members];
        }
        if ($purpose==='scopeContext') {
            $finance=$s['financePolicy'];
            if (!is_array($finance)) throw new NativeError('crypto_structure_source_finance_policy',409);
            $header=array_intersect_key($finance,array_flip(['enabled','revision','requiredContractVersion']));
            $hash=hash_init('sha256');
            hash_update($hash,NativeCryptoFinancePolicyV2::HASH_DOMAIN.NativeCryptoCodec::canonical((object)$header)."\n");
            foreach ($finance['grants'] as $grant) hash_update($hash,NativeCryptoCodec::canonical((object)$grant)."\n");
            hash_update($hash,NativeCryptoCodec::canonical((object)['grantCount'=>count($finance['grants'])]));
            return ['descriptor'=>$d,'members'=>$members,
                'scopeMetadataProofHash'=>$s['scopeMetadataProofHash'],'lifecycleHash'=>$s['lifecycleHash'],
                'financePolicy'=>$header+['policyHash'=>hash_final($hash),'grantCount'=>count($finance['grants'])]]
                +(isset($s['financeTopology'])?['financeTopology'=>$s['financeTopology']]:[]);
        }
        throw new NativeError('crypto_structure_context_purpose');
    }
    public function project($p,$actor)
    {
        $this->requiredTransaction();$this->fields($p,['migrationId','captureId','sourceInventoryRoot','authorization']);[$c]=$this->signed($p['authorization'],self::CONTEXT_DOMAIN,$actor);
        $this->sameCapture($p,$c);
        $this->fields($c,['version','operation','serverId','migrationId','captureId','accountId','sourceInventoryRoot',
            'purpose','targetScopeId','targetMembershipHeadHash','parentScopeToken','sourceCertificateHash','facts','deviceId','authorDirectoryHeadHash']);
        if ($c['operation']!=='crypto2.migration.structure.context') throw new NativeError('crypto_structure_context');
        $row=$this->sourceRow($c['sourceCertificateHash']);[$s]=$this->sourceCurrent($row);
        foreach (['migrationId','captureId','accountId','sourceInventoryRoot'] as $key) if ($c[$key]!==$s[$key]) throw new NativeError('crypto_structure_context');
        $target=$this->one('SELECT * FROM familyhub_scopes WHERE id=?',[$this->uuid($c['targetScopeId'])]);
        $head=(new NativeCryptoScopeV2($this->container))->current($c['targetScopeId']);
        if (!$target || !$head || $head['head_hash']!==$this->digest($c['targetMembershipHeadHash'])) throw new NativeError('crypto_structure_context_head_changed',409);
        $parent=$target['parent_scope_id']??$target['organization_id']??null;
        if ($c['purpose']==='scopeContext') {
            if ($s['scopeId']!==$target['id'] || $c['parentScopeToken']!==$s['descriptor']['parentScopeToken']) throw new NativeError('crypto_structure_context_scope',403);
        } elseif ($c['purpose']==='parentAccess') {
            if ($parent!==$s['scopeId'] || $c['parentScopeToken']!==(new NativeCryptoLifecycleV2($this->container))->parentToken($target['id'],$parent)) throw new NativeError('crypto_structure_context_scope',403);
        } else throw new NativeError('crypto_structure_context_purpose');
        if (!$this->same($c['facts'],$this->expectedFacts($s,$c['purpose']))) throw new NativeError('crypto_structure_context_facts',409);
        $hash=self::proofHash($p['authorization']);$old=$this->one('SELECT context_hash FROM familyhub_crypto_structure_contexts_v3 WHERE migration_id=? AND scope_id=? AND purpose=?',[$c['migrationId'],$target['id'],$c['purpose']]);
        if ($old && $old['context_hash']!==$hash) throw new NativeError('crypto_structure_context_immutable',409);
        if (!$old) $this->change('INSERT INTO familyhub_crypto_structure_contexts_v3(migration_id,scope_id,purpose,context_hash,certificate_hash,authorization) VALUES(?,?,?,?,?,?)',[$c['migrationId'],$target['id'],$c['purpose'],$hash,$row['certificate_hash'],json_encode($p['authorization'],JSON_THROW_ON_ERROR)]);
        return ['contextProofHash'=>$hash,'state'=>'awaitingConsent'];
    }
    private function contextRow($hash)
    {
        $row=$this->one('SELECT * FROM familyhub_crypto_structure_contexts_v3 WHERE context_hash=?',[$this->digest($hash)]);
        if (!$row) throw new NativeError('crypto_structure_context_pending',409);return $row;
    }
    public function approve($p,$actor,callable $bindings)
    {
        $this->requiredTransaction();$this->fields($p,['migrationId','captureId','sourceInventoryRoot','authorization']);[$c]=$this->signed($p['authorization'],self::CONSENT_DOMAIN,$actor);
        $this->sameCapture($p,$c);
        $this->fields($c,['version','operation','serverId','migrationId','captureId','accountId','sourceInventoryRoot','scopeId','membershipHeadHash','contextProofHash','sourceAuthority','deviceId','authorDirectoryHeadHash']);
        if ($c['operation']!=='crypto2.migration.structure.contextConsent') throw new NativeError('crypto_structure_context');
        $this->reviewer($c,$actor,$bindings);
        $row=$this->contextRow($c['contextProofHash']);[$card]=NativeCryptoCodec::decode(json_decode($row['authorization'],true,34,JSON_THROW_ON_ERROR));
        if ($row['migration_id']!==$c['migrationId'] || $row['scope_id']!==$c['scopeId'] || $card['targetMembershipHeadHash']!==$c['membershipHeadHash']) throw new NativeError('crypto_structure_context_head_changed',409);
        $source=$this->sourceRow($row['certificate_hash']);[$s]=$this->sourceCurrent($source);
        $directory=(new NativeCryptoDirectoryV2($this->container))->current($source['account_id']);$snapshot=json_decode($directory['snapshot'],true,34,JSON_THROW_ON_ERROR);
        $this->fields($c['sourceAuthority'],['accountId','rootSigningKeyBase64','rootEncryptionKeyBase64',
            'identityEpochId','deviceSnapshotHash','directoryHeadHash']);
        $reviewedReference=$this->one('SELECT generation,device_snapshot_hash,identity_epoch_id FROM familyhub_crypto_directory WHERE account_id=? AND head_hash=?',[
            $source['account_id'],$this->digest($c['sourceAuthority']['directoryHeadHash'])]);
        $event=json_decode($source['event_authorization'],true,34,JSON_THROW_ON_ERROR);
        $eventRow=$this->one('SELECT generation FROM familyhub_crypto_directory WHERE account_id=? AND command_hash=?',[
            $source['account_id'],hash('sha256',base64_decode($event['commandBase64'],true))]);
        $cardReference=$this->one('SELECT generation FROM familyhub_crypto_directory WHERE account_id=? AND head_hash=?',[
            $source['account_id'],$card['authorDirectoryHeadHash']]);
        if (!$reviewedReference || !$eventRow || !$cardReference ||
            $reviewedReference['device_snapshot_hash']!==$directory['device_snapshot_hash'] ||
            $reviewedReference['identity_epoch_id']!==$snapshot['identityEpochId'] ||
            (int)$reviewedReference['generation'] < max((int)$eventRow['generation'],(int)$cardReference['generation'])) {
            throw new NativeError('crypto_structure_context_authority_changed',409);
        }
        $authority=['accountId'=>$source['account_id'],'rootSigningKeyBase64'=>$snapshot['rootSigningKeyBase64'],'rootEncryptionKeyBase64'=>$snapshot['rootEncryptionKeyBase64'],
            'identityEpochId'=>$snapshot['identityEpochId'],'deviceSnapshotHash'=>$directory['device_snapshot_hash'],
            'directoryHeadHash'=>$c['sourceAuthority']['directoryHeadHash']];
        if (!$this->same($c['sourceAuthority'],$authority)) throw new NativeError('crypto_structure_context_authority_changed',409);
        $old=$this->one('SELECT * FROM familyhub_crypto_structure_consents_v3 WHERE context_hash=? AND account_id=?',[$c['contextProofHash'],$c['accountId']]);
        if ($old && ($old['capture_id']!==$c['captureId'] || $old['source_inventory_root']!==$c['sourceInventoryRoot'] ||
            !$this->same(json_decode($old['authorization'],true,34,JSON_THROW_ON_ERROR),$p['authorization']))) throw new NativeError('crypto_structure_context_immutable',409);
        if (!$old) $this->change('INSERT INTO familyhub_crypto_structure_consents_v3(context_hash,account_id,capture_id,source_inventory_root,authorization) VALUES(?,?,?,?,?)',[
            $c['contextProofHash'],$c['accountId'],$c['captureId'],$c['sourceInventoryRoot'],json_encode($p['authorization'],JSON_THROW_ON_ERROR)]);
        return ['contextProofHash'=>$c['contextProofHash'],'state'=>'approved'];
    }
    /** Fresh cutover only. Historical consumers use exact finalized cutover
     * inclusion and referenced prefixes, never this current-author path. */
    public function verify($sid,$headHash,$hashes,$actor,$requiredPurposes,$captureId,$sourceInventoryRoot,callable $bindings)
    {
        $seen=[];
        foreach ($hashes as $hash) {
            $row=$this->contextRow($hash);
            $approval=$this->one('SELECT * FROM familyhub_crypto_structure_consents_v3 WHERE context_hash=? AND account_id=?',[$hash,$actor['user']['account_id']]);
            if ($row['scope_id']!==$sid || !$approval || $approval['capture_id']!==$captureId ||
                $approval['source_inventory_root']!==$sourceInventoryRoot || isset($seen[$row['purpose']])) throw new NativeError('crypto_structure_context_pending',409);
            $seen[$row['purpose']]=true;$source=$this->sourceRow($row['certificate_hash']);[, $sourceActor]=$this->sourceCurrent($source);
            [$card]=$this->signed(json_decode($row['authorization'],true,34,JSON_THROW_ON_ERROR),self::CONTEXT_DOMAIN,$sourceActor);
            [$consent]=NativeCryptoCodec::decode(json_decode($approval['authorization'],true,34,JSON_THROW_ON_ERROR));
            $user=$this->one('SELECT user_id FROM familyhub_accounts WHERE account_id=?',[$consent['accountId']]);
            if (!$user || $card['targetMembershipHeadHash']!==$headHash || $consent['membershipHeadHash']!==$headHash || $consent['contextProofHash']!==$hash) throw new NativeError('crypto_structure_context_head_changed',409);
            $consenter=['user'=>['id'=>(int)$user['user_id'],'account_id'=>$consent['accountId']],'device'=>['id'=>$consent['deviceId']]];
            $this->signed(json_decode($approval['authorization'],true,34,JSON_THROW_ON_ERROR),self::CONSENT_DOMAIN,$consenter);
            $this->reviewer($consent,$consenter,$bindings);
            $scopes=new NativeCryptoScopeV2($this->container);$head=$scopes->current($sid);
            if (!$scopes->member($scopes->body($head),$actor['user']['account_id'])) throw new NativeError('permission_revoked',403);
        }
        $actual=array_keys($seen);sort($actual,SORT_STRING);sort($requiredPurposes,SORT_STRING);
        if ($actual!==$requiredPurposes) throw new NativeError('crypto_structure_context_incomplete',409);
        return true;
    }
    /** Exact registered scoped issuer only. Never exposes the private source
     * statement, parent UUID, finance grants or an unrelated account prefix. */
    public function directoryReferences($sid,$headHash,$account)
    {
        $references=[];
        foreach ($this->many('SELECT c.authorization,s.certificate_authorization,s.event_authorization FROM familyhub_crypto_structure_contexts_v3 c JOIN familyhub_crypto_structure_sources_v3 s ON s.certificate_hash=c.certificate_hash WHERE c.scope_id=? AND s.account_id=?',[$sid,$account]) as $row) {
            [$card]=NativeCryptoCodec::decode(json_decode($row['authorization'],true,34,JSON_THROW_ON_ERROR));
            if ($card['targetMembershipHeadHash']!==$headHash || $card['accountId']!==$account) continue;
            [$certificate]=NativeCryptoCodec::decode(json_decode($row['certificate_authorization'],true,34,JSON_THROW_ON_ERROR));
            $references[]=$card['authorDirectoryHeadHash'];$references[]=$certificate['authorDirectoryHeadHash'];
            if ($row['event_authorization']!==null) {
                $event=json_decode($row['event_authorization'],true,34,JSON_THROW_ON_ERROR);
                $entry=$this->one('SELECT head_hash FROM familyhub_crypto_directory WHERE account_id=? AND command_hash=?',[
                    $account,hash('sha256',base64_decode($event['commandBase64'],true))]);
                if ($entry) $references[]=$entry['head_hash'];
            }
        }
        foreach ($this->many('SELECT a.authorization FROM familyhub_crypto_structure_consents_v3 a JOIN familyhub_crypto_structure_contexts_v3 c ON c.context_hash=a.context_hash WHERE c.scope_id=?',[$sid]) as $row) {
            [$consent]=NativeCryptoCodec::decode(json_decode($row['authorization'],true,34,JSON_THROW_ON_ERROR));
            if ($consent['membershipHeadHash']===$headHash && $consent['sourceAuthority']['accountId']===$account) {
                $references[]=$consent['sourceAuthority']['directoryHeadHash'];
            }
        }
        return array_values(array_unique($references));
    }
    public function evidence($p,$actor)
    {
        $this->fields($p,['migrationId','captureId','sourceInventoryRoot','scopeId','membershipHeadHash'],['afterHash','limit']);$sid=$this->uuid($p['scopeId']);$this->digest($p['membershipHeadHash']);
        $this->scope($sid,$actor['user']['id']);$scopes=new NativeCryptoScopeV2($this->container);$head=$scopes->current($sid);
        if (!$head || $head['head_hash']!==$p['membershipHeadHash']) throw new NativeError('crypto_structure_context_head_changed',409);
        $limit=$p['limit']??20;if(!is_int($limit)||$limit<1||$limit>20)throw new NativeError('validation_error');
        $after=isset($p['afterHash'])?$this->digest($p['afterHash']):'';
        $rows=$this->many('SELECT * FROM familyhub_crypto_structure_contexts_v3 WHERE migration_id=? AND scope_id=? AND purpose IN (\'scopeContext\',\'parentAccess\') AND context_hash>? ORDER BY context_hash LIMIT '.($limit+1),[$p['migrationId'],$sid,$after]);$out=[];
        $scan=$after;
        foreach(array_slice($rows,0,$limit) as $row){
            $scan=$row['context_hash'];
            [$card]=NativeCryptoCodec::decode(json_decode($row['authorization'],true,34,JSON_THROW_ON_ERROR));
            if($card['targetMembershipHeadHash']!==$head['head_hash']) continue;
            $source=$this->sourceRow($row['certificate_hash']);
            $consent=$this->one('SELECT authorization FROM familyhub_crypto_structure_consents_v3 WHERE context_hash=? AND account_id=? AND capture_id=? AND source_inventory_root=?',[$row['context_hash'],$actor['user']['account_id'],$p['captureId'],$p['sourceInventoryRoot']]);
            $out[]=['contextProofHash'=>$row['context_hash'],'authorization'=>json_decode($row['authorization'],true,34,JSON_THROW_ON_ERROR),
                'consentAuthorization'=>$consent===null?null:json_decode($consent['authorization'],true,34,JSON_THROW_ON_ERROR),
                'certificateAuthorization'=>json_decode($source['certificate_authorization'],true,34,JSON_THROW_ON_ERROR),
                'eventAuthorization'=>$source['event_authorization']===null?null:json_decode($source['event_authorization'],true,34,JSON_THROW_ON_ERROR)];
        }
        return ['contexts'=>$out,'hasMore'=>count($rows)>$limit,'nextAfterHash'=>$scan?:null];
    }
}
