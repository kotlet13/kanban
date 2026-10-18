<?php
namespace Kanboard\Plugin\FamilyHub\Model;

/** Private preparatory state for one finite inline-project conversion.
 * No source/target business effects occur while descriptors are staged.
 * The client manager attests semantic selection after decrypting the complete
 * source; server checks signatures, exact current proofs and graph barriers. */
class NativeCryptoProjectRelocationV2 extends NativeDatabase
{
    protected $cryptoAccess=true;
    const PLAN_DOMAIN="JivieProjectRelocationPlan/v2\n";

    private function hash($value)
    {
        return NativeCryptoProjectRelocationCodecV2::hash($value);
    }
    private function sourceContext($scopeId,$actor)
    {
        // Match NativeProjectSharingService: a managed policy3 household.
        // It is not sufficient merely to possess the old content DEK.
        $scope=$this->scope($scopeId,$actor['user']['id'],true,true);
        if($scope['kind']!=='household'||(int)$scope['access_policy_version']!==3){
            throw new NativeError('access_migration_required',409);
        }
        NativeCryptoScopeCreationV2::guardBusiness($this->pdo,$scopeId);
        $api=new NativeCryptoScopeV2($this->container,$this->bearer,$this->ip);
        $head=$api->current($scopeId);
        if(!$head)throw new NativeError('crypto_scope_head_missing',409);
        $api->manager($head,$scope,$actor);
        $api->author($scopeId,$head['head_hash'],(int)$head['epoch'],(int)$scope['effective_access_revision'],$actor,'content');
        return [$scope,$head,(new NativeCryptoLifecycleV2($this->container))->closingHash($scopeId)];
    }
    private function planRow($action,$actor,$active=true)
    {
        $row=$this->one('SELECT * FROM familyhub_crypto_project_relocations_v2 WHERE action_id=?'.$this->lockSuffix(),[$this->uuid($action)]);
        if(!$row||$row['account_id']!==$actor['user']['account_id'])throw new NativeError('permission_revoked',403);
        if($active&&(!in_array($row['state'],['preparing','staged'],true)||(int)$row['expires_at']<=time()||$row['device_id']!==$actor['device']['id'])){
            throw new NativeError('crypto_relocation_plan_expired',409);
        }
        [$body]=NativeCryptoCodec::decode(json_decode($row['authorization'],true,34,JSON_THROW_ON_ERROR));
        NativeCryptoProjectRelocationCodecV2::plan($body);
        if($this->hash(json_decode($row['authorization'],true,34,JSON_THROW_ON_ERROR))!==$row['plan_hash']){
            throw new NativeError('crypto_relocation_plan_immutable',409);
        }
        return [$row,$body];
    }
    private function assertContext($body,$actor)
    {
        [$scope,$head,$lifecycle]=$this->sourceContext($body['sourceScopeId'],$actor);
        if($body['sourceHeadHash']!==$head['head_hash']||$body['sourceAccessRevision']!==(int)$scope['effective_access_revision']||$body['sourceLifecycleHash']!==$lifecycle){
            throw new NativeError('project_sharing_preview_changed',409);
        }
        $owner=$this->one("SELECT account_id FROM familyhub_members WHERE scope_id=? AND role='owner' AND active=1",[$scope['id']]);
        if(!$owner||$body['targetOwnerAccountId']!==$owner['account_id'])throw new NativeError('crypto_relocation_owner_changed',409);
        $token=(new NativeCryptoLifecycleV2($this->container))->parentToken($body['targetScopeId'],$scope['id']);
        if($body['targetParentScopeToken']!==$token||$this->one('SELECT id FROM familyhub_scopes WHERE id=?',[$body['targetScopeId']])){
            throw new NativeError('project_sharing_preview_changed',409);
        }
        if($scope['project_root_id']===$body['projectId']||NativeCryptoRecordAddressV2::derive($this->serverId(),$scope['id'],'content','records',$body['projectId'])!==$body['projectWireId']){
            throw new NativeError('crypto_relocation_project_binding',409);
        }
        $root=$this->one("SELECT id FROM familyhub_crypto_records WHERE scope_id=? AND id=? AND type='project' AND deleted=0",[$scope['id'],$body['projectWireId']]);
        if(!$root)throw new NativeError('parent_missing',409);
        $metadataId=NativeCryptoRecordAddressV2::derive($this->serverId(),$scope['id'],'content','scope_metadata',NativeCryptoReservedRecordV2::derive($this->serverId(),$scope['id'],'scopeMetadata'));
        $metadata=$this->one("SELECT authorization,deleted,type FROM familyhub_crypto_records WHERE scope_id=? AND id=?",[$scope['id'],$metadataId]);
        if(!$metadata||$metadata['deleted']||$metadata['type']!=='scopeMetadata'||$this->hash(json_decode($metadata['authorization'],true,34,JSON_THROW_ON_ERROR)['recordProof'])!==$body['parentMetadataProofHash'])throw new NativeError('project_sharing_preview_changed',409);
        return [$scope,$head];
    }
    private function verifySource($body,$descriptor,$actor)
    {
        NativeCryptoProjectRelocationCodecV2::sourceDescriptor($descriptor);
        if(in_array($descriptor['type'],['scopeMetadata','garden','shoppingList','shoppingItem','table','paymentEvent','paymentProjection','cashMovement','financeAccountChoice'],true)){
            throw new NativeError('project_sharing_blocked',409);
        }
        if(NativeCryptoRecordAddressV2::derive($this->serverId(),$body['sourceScopeId'],$descriptor['domain'],NativeCryptoRecordAddressV2::sourceKind($descriptor['type']),$descriptor['id'])!==$descriptor['wireId']){
            throw new NativeError('crypto_record_identity_binding',409);
        }
        if($descriptor['domain']==='finance'){
            (new NativeFinanceAccess($this->container))->policyForCrypto($body['sourceScopeId'],$actor['user'],true,true);
        }
        $row=$this->one('SELECT * FROM familyhub_crypto_records WHERE scope_id=? AND id=?',[$body['sourceScopeId'],$descriptor['wireId']]);
        if(!$row||$row['type']!==$descriptor['type']||(int)$row['revision']!==$descriptor['revision']||(bool)$row['deleted']!==$descriptor['deleted']){
            throw new NativeError('project_sharing_preview_changed',409);
        }
        $authorization=json_decode($row['authorization'],true,34,JSON_THROW_ON_ERROR);
        if(!isset($authorization['recordProof'])||$this->hash($authorization['recordProof'])!==$descriptor['recordProofHash']){
            throw new NativeError('project_sharing_preview_changed',409);
        }
        if((new NativeCryptoModerationAvailabilityV2($this->container))->restriction($body['sourceScopeId'],$descriptor['wireId'],(int)$row['revision'])){
            throw new NativeError('crypto_content_restricted',403);
        }
        return $row;
    }
    public function prepare($p,$actor,$outerProof,$command,$key)
    {
        $this->fields($p,['planProof']);
        [$body,$bytes,$signature]=NativeCryptoCodec::decode($p['planProof']);
        NativeCryptoProjectRelocationCodecV2::plan($body);
        NativeCryptoV2Codec::verify($bytes,$signature,$key,self::PLAN_DOMAIN);
        if($body['serverId']!==$this->serverId()||$body['requestId']!==$command['requestId']||$body['accountId']!==$actor['user']['account_id']||$body['deviceId']!==$actor['device']['id']){
            throw new NativeError('crypto_relocation_plan',409);
        }
        (new NativeCryptoScopeV2($this->container))->currentAuthorReference($body['authorDirectoryHeadHash'],$actor);
        $this->assertContext($body,$actor);
        if($this->one('SELECT action_id FROM familyhub_crypto_project_relocations_v2 WHERE action_id=?',[$body['actionId']])){
            throw new NativeError('crypto_relocation_action_immutable',409);
        }
        $expiry=time()+1800;$hash=$this->hash($p['planProof']);
        $this->change('INSERT INTO familyhub_crypto_project_relocations_v2(action_id,source_scope_id,target_scope_id,account_id,device_id,plan_hash,authorization,state,expires_at) VALUES(?,?,?,?,?,?,?,?,?)',[$body['actionId'],$body['sourceScopeId'],$body['targetScopeId'],$body['accountId'],$body['deviceId'],$hash,json_encode($p['planProof'],JSON_THROW_ON_ERROR),'preparing',$expiry]);
        return ['actionId'=>$body['actionId'],'planHash'=>$hash,'sourceGraphRoot'=>$body['sourceGraphRoot'],'sourceGraphCount'=>$body['sourceGraphCount'],'expiresAt'=>$expiry];
    }
    public function sources($p,$actor)
    {
        $this->fields($p,['actionId','planHash','descriptors']);
        [$row,$body]=$this->planRow($p['actionId'],$actor);
        if($row['plan_hash']!==$p['planHash']||!is_array($p['descriptors'])||!array_is_list($p['descriptors'])||!$p['descriptors']||count($p['descriptors'])>32){
            throw new NativeError('validation_error');
        }
        $this->assertContext($body,$actor);$previous=null;
        foreach($p['descriptors'] as $descriptor){
            $this->verifySource($body,$descriptor,$actor);
            if($previous!==null&&strcmp($previous,$descriptor['wireId'])>=0)throw new NativeError('crypto_relocation_order');
            $previous=$descriptor['wireId'];$encoded=NativeCryptoCodec::canonical((object)$descriptor);
            $saved=$this->one('SELECT source_descriptor FROM familyhub_crypto_project_relocation_records_v2 WHERE action_id=? AND source_wire_id=?',[$row['action_id'],$descriptor['wireId']]);
            if($saved){
                if($saved['source_descriptor']!==$encoded)throw new NativeError('crypto_relocation_source_immutable',409);
                continue;
            }
            $this->change('INSERT INTO familyhub_crypto_project_relocation_records_v2(action_id,source_wire_id,source_descriptor) VALUES(?,?,?)',[$row['action_id'],$descriptor['wireId'],$encoded]);
        }
        $count=(int)$this->one('SELECT COUNT(*) AS n FROM familyhub_crypto_project_relocation_records_v2 WHERE action_id=?',[$row['action_id']])['n'];
        if($count>$body['sourceGraphCount'])throw new NativeError('crypto_relocation_capacity',409);
        return ['staged'=>true,'sourceCount'=>$count,'sourceGraphCount'=>$body['sourceGraphCount']];
    }

    public function targetOrigin($p,$actor,$key)
    {
        $this->fields($p,['actionId','planHash','originProof']);
        [$row,$plan]=$this->planRow($p['actionId'],$actor);
        if($row['plan_hash']!==$p['planHash'])throw new NativeError('crypto_relocation_plan',409);
        $this->validateSources($row['action_id'],$actor);
        [$origin,$bytes,$signature]=NativeCryptoCodec::decode($p['originProof']);
        $this->fields($origin,['version','operation','serverId','scopeId','kind','accessPolicyVersion','parentScopeToken','requestId','accountId','deviceId','authorDirectoryHeadHash','projectRelocation']);
        $expected=['version'=>2,'operation'=>'crypto2.scope.origin','serverId'=>$this->serverId(),'scopeId'=>$plan['targetScopeId'],'kind'=>'project','accessPolicyVersion'=>3,'parentScopeToken'=>$plan['targetParentScopeToken'],'requestId'=>$plan['requestId'],'accountId'=>$actor['user']['account_id'],'deviceId'=>$actor['device']['id']];
        foreach($expected as $field=>$value)if($origin[$field]!==$value)throw new NativeError('crypto_relocation_origin',409);
        $this->fields($origin['projectRelocation'],['version','actionId','planHash']);
        // Canonical encoding deliberately ignores PHP associative key order.
        if(NativeCryptoCodec::canonical((object)$origin['projectRelocation'])!==NativeCryptoCodec::canonical((object)['version'=>2,'actionId'=>$row['action_id'],'planHash'=>$row['plan_hash']])){
            throw new NativeError('crypto_relocation_origin',409);
        }
        (new NativeCryptoScopeV2($this->container))->currentAuthorReference($origin['authorDirectoryHeadHash'],$actor);
        NativeCryptoV2Codec::verify($bytes,$signature,$key,"JivieE2EE/scopeOrigin/v2\n");
        $encoded=NativeCryptoCodec::canonical((object)$p['originProof']);
        if($row['target_origin']!==null&&$row['target_origin']!==$encoded)throw new NativeError('crypto_relocation_origin_immutable',409);
        $this->change('UPDATE familyhub_crypto_project_relocations_v2 SET target_origin=? WHERE action_id=?',[$encoded,$row['action_id']]);
        return ['staged'=>true,'originProofHash'=>$this->hash($p['originProof'])];
    }

    private const TARGET_TABLES=[
        'familyhub_crypto_domain_keys',
        'familyhub_crypto_scope_heads',
        'familyhub_crypto_grant_states_v2',
        'familyhub_crypto_grant_entries_v2',
    ];
    private function targetBase($row,$plan,$actor)
    {
        if($row['target_origin']===null)throw new NativeError('crypto_relocation_origin_pending',409);
        $owner=$this->one('SELECT a.user_id FROM familyhub_accounts a JOIN users u ON u.id=a.user_id AND u.is_active=1 WHERE a.account_id=?',[$plan['targetOwnerAccountId']]);
        if(!$owner)throw new NativeError('crypto_relocation_owner_changed',409);
        $sid=$plan['targetScopeId'];
        $this->change("INSERT INTO familyhub_scopes(id,kind,name,owner_id,sequence,created_at,required_record_contract,access_policy_version,parent_scope_id,project_root_id) VALUES(?,'project','Encrypted project',?,0,?,6,3,?,?)",[$sid,$owner['user_id'],time(),$plan['sourceScopeId'],$sid]);
        $this->change("INSERT INTO familyhub_members(scope_id,user_id,account_id,role,active) VALUES(?,?,?,'owner',1)",[$sid,$owner['user_id'],$plan['targetOwnerAccountId']]);
        $this->change('INSERT INTO familyhub_finance_policy(scope_id,enabled,revision,sequence,required_contract_version) VALUES(?,1,1,0,3)',[$sid]);
        $this->change("INSERT INTO familyhub_finance_grants(scope_id,account_id,access_level) VALUES(?,?,'write')",[$sid,$plan['targetOwnerAccountId']]);
        $scope=$this->scope($sid,$actor['user']['id']);
        $this->change("INSERT INTO familyhub_crypto_scopes(scope_id,epoch,sequence,access_revision,state) VALUES(?,1,0,?,'staged')",[$sid,(int)$scope['effective_access_revision']]);
        $origin=json_decode($row['target_origin'],true,34,JSON_THROW_ON_ERROR);
        $this->change('INSERT INTO familyhub_crypto_scope_origins VALUES(?,?,?,?)',[$sid,$actor['user']['account_id'],json_encode($origin,JSON_THROW_ON_ERROR),time()]);
        (new NativeCryptoLifecycleV2($this->container))->captureBaseline($sid,'new',$origin);
        return $scope;
    }

    /** Recreate only fixed target crypto tables. Target base ACL is always
     * derived afresh from the exact parent/owner, never caller SQL columns. */
    private function restoreTarget($row,$plan,$actor)
    {
        $scope=$this->targetBase($row,$plan,$actor);
        foreach($this->many('SELECT table_name,payload FROM familyhub_crypto_project_relocation_shadow_v2 WHERE action_id=? ORDER BY table_name,row_key',[$row['action_id']]) as $snapshot){
            if(!in_array($snapshot['table_name'],self::TARGET_TABLES,true))throw new NativeError('crypto_relocation_shadow',409);
            $values=json_decode($snapshot['payload'],true,34,JSON_THROW_ON_ERROR);
            if(!is_array($values)||($values['scope_id']??null)!==$plan['targetScopeId'])throw new NativeError('crypto_relocation_shadow',409);
            if($snapshot['table_name']==='familyhub_crypto_scope_heads'&&(($values['state']??null)!=='pending'||($values['activation_authorization']??null)!==null)){
                throw new NativeError('crypto_relocation_shadow',409);
            }
            // Column names originate only from server SELECT output. Reject any
            // malformed stored name rather than interpolating arbitrary SQL.
            foreach(array_keys($values) as $column)if(!preg_match('/^[a-z_]+$/D',$column))throw new NativeError('crypto_relocation_shadow',409);
            $this->change('INSERT INTO '.$snapshot['table_name'].'('.implode(',',array_keys($values)).') VALUES('.implode(',',array_fill(0,count($values),'?')).')',array_values($values));
        }
        return $scope;
    }

    /** Internal candidate capability. The target exists only inside this
     * savepoint; callers cannot retain SQL authority after the callback. */
    public function withTarget($actionId,$planHash,$actor,callable $callback)
    {
        [$row,$plan]=$this->planRow($actionId,$actor);
        if(!$this->transactionActive()||$row['plan_hash']!==$planHash){
            throw new NativeError('crypto_relocation_transaction',409);
        }
        $this->validateSources($actionId,$actor);
        $this->pdo->exec('SAVEPOINT jivie_project_relocation_candidate');
        try{
            $scope=$this->restoreTarget($row,$plan,$actor);
            $this->activateTarget($row,$plan,$scope,$actor);
            return $callback($row,$plan,$scope);
        }finally{
            $this->pdo->exec('ROLLBACK TO SAVEPOINT jivie_project_relocation_candidate');
            $this->pdo->exec('RELEASE SAVEPOINT jivie_project_relocation_candidate');
        }
    }

    private function activateTarget($row,$plan,$scope,$actor)
    {
        if(($row['target_activation']??null)===null){
            throw new NativeError('crypto_relocation_target_keys_pending',409);
        }
        $proof=json_decode($row['target_activation'],true,34,JSON_THROW_ON_ERROR);
        [$command]=NativeCryptoCodec::decode($proof);
        return (new NativeCryptoScopeV2($this->container,$this->bearer,$this->ip))
            ->relocationWrite($row['action_id'],$row['plan_hash'],$scope,$actor,$command,$proof);
    }

    /** Validate a marked activation without publishing its target. Final
     * installation repeats the same validator in the enclosing transaction. */
    public function targetActivation($p,$actor,$key)
    {
        $this->fields($p,['actionId','planHash','authorization']);
        [$row,$plan]=$this->planRow($p['actionId'],$actor);
        if(!$this->transactionActive()||$row['plan_hash']!==$p['planHash']){
            throw new NativeError('crypto_relocation_transaction',409);
        }
        $this->validateSources($row['action_id'],$actor);
        [$command,$bytes,$signature]=NativeCryptoCodec::decode($p['authorization']);
        $this->fields($command,['version','operation','requestId','serverId','accountId','deviceId','signer','payload']);
        if($command['version']!==2||$command['operation']!=='crypto2.scope.activate'||
            $command['serverId']!==$this->serverId()||$command['accountId']!==$actor['user']['account_id']||
            $command['deviceId']!==$actor['device']['id']||$command['signer']!=='device'||
            ($command['payload']['scopeId']??null)!==$plan['targetScopeId']){
            throw new NativeError('crypto_relocation_nested_command',409);
        }
        $this->uuid($command['requestId']);NativeCryptoV2Codec::verify($bytes,$signature,$key);
        $encoded=NativeCryptoCodec::canonical((object)$p['authorization']);
        if(($row['target_activation']??null)!==null&&$row['target_activation']!==$encoded){
            throw new NativeError('crypto_relocation_target_immutable',409);
        }
        $this->pdo->exec('SAVEPOINT jivie_project_relocation_activation');
        try{
            $scope=$this->restoreTarget($row,$plan,$actor);
            $result=(new NativeCryptoScopeV2($this->container,$this->bearer,$this->ip))
                ->relocationWrite($row['action_id'],$row['plan_hash'],$scope,$actor,$command,$p['authorization']);
        }finally{
            $this->pdo->exec('ROLLBACK TO SAVEPOINT jivie_project_relocation_activation');
            $this->pdo->exec('RELEASE SAVEPOINT jivie_project_relocation_activation');
        }
        $this->change('UPDATE familyhub_crypto_project_relocations_v2 SET target_activation=? WHERE action_id=?',[$encoded,$row['action_id']]);
        return ['candidate'=>true,'result'=>$result,'activationProofHash'=>$this->hash($p['authorization'])];
    }

    /** Final coordinator only. No target is materialized before all staged
     * source/target proofs, bytes and audit commitments have been checked. */
    public function installTarget($actionId,$planHash,$actor)
    {
        [$row,$plan]=$this->planRow($actionId,$actor,false);
        if(!$this->transactionActive()||$row['state']!=='committing'||$row['plan_hash']!==$planHash||
            $row['device_id']!==$actor['device']['id']||(int)$row['expires_at']<=time()){
            throw new NativeError('crypto_relocation_transaction',409);
        }
        // validateSources uses the active preparatory state. This temporary
        // state change stays inside the final enclosing SQL transaction.
        $this->change("UPDATE familyhub_crypto_project_relocations_v2 SET state='staged' WHERE action_id=?",[$actionId]);
        try{$this->validateSources($actionId,$actor);}finally{
            $this->change("UPDATE familyhub_crypto_project_relocations_v2 SET state='committing' WHERE action_id=?",[$actionId]);
        }
        $scope=$this->restoreTarget($row,$plan,$actor);
        $this->activateTarget($row,$plan,$scope,$actor);
        $this->change("UPDATE familyhub_crypto_scopes SET state='active' WHERE scope_id=?",[$plan['targetScopeId']]);
        return ['plan'=>$row,'body'=>$plan,'scope'=>$scope];
    }

    public function targetPreview($p,$actor)
    {
        $this->fields($p,['actionId','planHash']);[$row,$plan]=$this->planRow($p['actionId'],$actor);
        if($row['plan_hash']!==$p['planHash']||!$this->transactionActive())throw new NativeError('crypto_relocation_transaction',409);
        $this->validateSources($row['action_id'],$actor);
        $this->pdo->exec('SAVEPOINT jivie_project_relocation_preview');
        try{
            $this->restoreTarget($row,$plan,$actor);
            $api=new NativeCryptoScopeV2($this->container,$this->bearer,$this->ip);
            $head=$this->one("SELECT * FROM familyhub_crypto_scope_heads WHERE scope_id=? AND state='pending'",[$plan['targetScopeId']]);
            $roots=$head?$api->grantManifest($api->body($head),false):null;
            return ['candidate'=>true,'scope'=>$api->catalogScope($plan['targetScopeId'],$actor),'lifecycle'=>(new NativeCryptoLifecycleV2($this->container))->initialBaseline($plan['targetScopeId']),'authorization'=>$head?json_decode($head['authorization'],true,34,JSON_THROW_ON_ERROR):null,'grantManifest'=>$roots,'grantManifestHash'=>$roots?NativeCryptoV2Codec::hash((object)$roots):null];
        }finally{
            $this->pdo->exec('ROLLBACK TO SAVEPOINT jivie_project_relocation_preview');
            $this->pdo->exec('RELEASE SAVEPOINT jivie_project_relocation_preview');
            unset($api);
        }
    }

    /** No target SQL survives this function. Fresh validator objects and a
     * finally rollback prevent cached target authority escaping the savepoint.
     * Only SQL head/grant operations are accepted; no blobs/jobs/FS effects. */
    public function targetCommand($p,$actor,$outer,$key)
    {
        $this->fields($p,['actionId','planHash','authorization']);
        [$row,$plan]=$this->planRow($p['actionId'],$actor);
        if($row['plan_hash']!==$p['planHash']||!$this->transactionActive())throw new NativeError('crypto_relocation_transaction',409);
        $this->validateSources($row['action_id'],$actor);
        [$command,$bytes,$signature]=NativeCryptoCodec::decode($p['authorization']);
        $this->fields($command,['version','operation','requestId','serverId','accountId','deviceId','signer','payload']);
        if($command['version']!==2||!in_array($command['operation'],['crypto2.scope.headPut','crypto2.grants.put'],true)||$command['serverId']!==$this->serverId()||$command['accountId']!==$actor['user']['account_id']||$command['deviceId']!==$actor['device']['id']||$command['signer']!=='device'||($command['payload']['scopeId']??null)!==$plan['targetScopeId']){
            throw new NativeError('crypto_relocation_nested_command',409);
        }
        $this->uuid($command['requestId']);NativeCryptoV2Codec::verify($bytes,$signature,$key);
        $commandHash=$this->hash($p['authorization']);
        $saved=$this->one('SELECT command_hash,response FROM familyhub_crypto_project_relocation_nested_v2 WHERE action_id=? AND request_id=?',[$row['action_id'],$command['requestId']]);
        if($saved){
            if($saved['command_hash']!==$commandHash)throw new NativeError('idempotency_mismatch',409);
            return json_decode($saved['response'],true,34,JSON_THROW_ON_ERROR);
        }
        if($command['operation']==='crypto2.scope.headPut'&&$row['target_head_authorization']!==null&&$row['target_head_authorization']!==NativeCryptoCodec::canonical((object)$p['authorization'])){
            throw new NativeError('crypto_relocation_target_immutable',409);
        }
        $snapshots=[];$result=null;$this->pdo->exec('SAVEPOINT jivie_project_relocation_target');
        try{
            $scope=$this->restoreTarget($row,$plan,$actor);
            $api=new NativeCryptoScopeV2($this->container,$this->bearer,$this->ip);
            $result=$api->relocationWrite($row['action_id'],$row['plan_hash'],$scope,$actor,$command,$p['authorization']);
            if((int)$this->one('SELECT COUNT(*) AS n FROM familyhub_crypto_scope_heads WHERE scope_id=?',[$plan['targetScopeId']])['n']!==1){
                throw new NativeError('crypto_relocation_target_immutable',409);
            }
            foreach(self::TARGET_TABLES as $table){
                foreach($this->many('SELECT * FROM '.$table.' WHERE scope_id=?',[$plan['targetScopeId']]) as $values){
                    $encoded=NativeCryptoCodec::canonical((object)$values);
                    $snapshots[]=['table'=>$table,'key'=>hash('sha256',$encoded),'payload'=>$encoded];
                }
            }
        }finally{
            $this->pdo->exec('ROLLBACK TO SAVEPOINT jivie_project_relocation_target');
            $this->pdo->exec('RELEASE SAVEPOINT jivie_project_relocation_target');
            unset($api);
        }
        $this->change('DELETE FROM familyhub_crypto_project_relocation_shadow_v2 WHERE action_id=?',[$row['action_id']]);
        foreach($snapshots as $snapshot)$this->change('INSERT INTO familyhub_crypto_project_relocation_shadow_v2(action_id,table_name,row_key,payload) VALUES(?,?,?,?)',[$row['action_id'],$snapshot['table'],$snapshot['key'],$snapshot['payload']]);
        if($command['operation']==='crypto2.scope.headPut'){
            $headAuthorization=NativeCryptoCodec::canonical((object)$p['authorization']);
            if($row['target_head_authorization']!==null&&$row['target_head_authorization']!==$headAuthorization)throw new NativeError('crypto_relocation_target_immutable',409);
            $this->change('UPDATE familyhub_crypto_project_relocations_v2 SET target_head_authorization=? WHERE action_id=?',[$headAuthorization,$row['action_id']]);
        }
        $response=['candidate'=>true,'result'=>$result];
        $this->change('INSERT INTO familyhub_crypto_project_relocation_nested_v2(action_id,request_id,command_hash,authorization,response) VALUES(?,?,?,?,?)',[$row['action_id'],$command['requestId'],$commandHash,json_encode($p['authorization'],JSON_THROW_ON_ERROR),json_encode($response,JSON_THROW_ON_ERROR)]);
        return $response;
    }
    /** Complete exact source set, rechecked at final under the global lock.
     * A newly created outside dependency cannot be silently moved or severed. */
    public function validateSources($action,$actor)
    {
        [$row,$body]=$this->planRow($action,$actor);$this->assertContext($body,$actor);
        $descriptors=[];$selected=[];
        foreach($this->many('SELECT source_descriptor FROM familyhub_crypto_project_relocation_records_v2 WHERE action_id=? ORDER BY source_wire_id',[$action]) as $source){
            $d=json_decode($source['source_descriptor'],true,34,JSON_THROW_ON_ERROR);$this->verifySource($body,$d,$actor);
            $descriptors[]=$d;$selected[$d['wireId']]=true;
            if(count($descriptors)>$body['sourceGraphCount'])throw new NativeError('crypto_relocation_capacity',409);
        }
        if(count($descriptors)!==$body['sourceGraphCount']||!isset($selected[$body['projectWireId']])||NativeCryptoProjectRelocationCodecV2::graphRoot($descriptors)!==$body['sourceGraphRoot']){
            throw new NativeError('crypto_relocation_source_incomplete',409);
        }
        foreach($this->iterate('SELECT scope_id,id,type,metadata FROM familyhub_crypto_records WHERE deleted=0 ORDER BY scope_id,id') as $record){
            if($record['scope_id']===$body['sourceScopeId']&&isset($selected[$record['id']]))continue;
            $metadata=json_decode($record['metadata'],true,34,JSON_THROW_ON_ERROR);
            foreach($metadata['references']??[] as $ref){
                if($ref['scopeId']===$body['sourceScopeId']&&isset($selected[$ref['id']]))throw new NativeError('project_sharing_blocked',409);
            }
        }
        foreach($this->iterate('SELECT record_proof FROM familyhub_crypto_record_history ORDER BY scope_id,id,revision') as $record){
            [$historic]=NativeCryptoCodec::decode(json_decode($record['record_proof'],true,34,JSON_THROW_ON_ERROR));
            if(!in_array($historic['type'],['paymentEvent','paymentProjection','cashMovement'],true))continue;
            foreach($historic['metadata']['references']??[] as $ref){
                if($ref['scopeId']===$body['sourceScopeId']&&isset($selected[$ref['id']]))throw new NativeError('project_linked_payment_dependency',409);
            }
        }
        return ['plan'=>$row,'body'=>$body,'descriptors'=>$descriptors];
    }
    /** Own minimal outcome remains readable after loss of source READ. */
    public function status($p,$actor)
    {
        $this->fields($p,['actionId']);
        [$row,$plan]=$this->planRow($p['actionId'],$actor,false);
        return ['actionId'=>$row['action_id'],'planHash'=>$row['plan_hash'],'state'=>$row['state'],'expiresAt'=>(int)$row['expires_at'],'targetScopeId'=>$plan['targetScopeId'],'projectId'=>$plan['projectId']];
    }

    public function cancel($p,$actor)
    {
        $this->fields($p,['actionId','planHash']);[$row]=$this->planRow($p['actionId'],$actor,false);
        if($row['plan_hash']!==$p['planHash']||$row['state']==='committed')throw new NativeError('crypto_relocation_plan',409);
        $this->change("UPDATE familyhub_crypto_project_relocations_v2 SET state='cancelled' WHERE action_id=?",[$row['action_id']]);
        return ['cancelled'=>true,'sourceUnchanged'=>true];
    }
}
