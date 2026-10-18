<?php

namespace Kanboard\Plugin\FamilyHub\Model;

/** Scope authority is a signed succession; SQL membership alone cannot mint a successor. */
class NativeCryptoScopeV2 extends NativeDatabase
{
    protected $cryptoAccess = true;
    private $pendingRead = null;
    private $accessContext = null;
    private $relocationContext = null;
    private $parentTopologyContext = null;
    public function current($sid)
    {
        $s = $this->one('SELECT * FROM familyhub_crypto_scope_state WHERE scope_id=?', [$sid]);
        if (!$s) {
            if ($this->one("SELECT head_hash FROM familyhub_crypto_scope_heads WHERE scope_id=? AND activation_authorization IS NOT NULL AND state<>'superseded' LIMIT 1", [$sid])) {
                throw new NativeError('crypto_scope_head_unavailable', 503);
            }
            return null;
        }
        $h = $this->one("SELECT * FROM familyhub_crypto_scope_heads WHERE scope_id=? AND head_hash=? AND state='active'", [$sid,$s['head_hash']]);
        if (!$h || (int)$h['epoch'] !== (int)$s['epoch'] || $h['activation_authorization'] === null) {
            throw new NativeError('crypto_scope_head_unavailable', 503);
        }
        $this->domainSequence($sid, 'content');
        $this->domainSequence($sid, 'finance');
        $body = $this->body($h);
        if (hash('sha256', "JivieScopeHead/v2\n".NativeCryptoCodec::canonical((object)$body)) !== $h['head_hash']) {
            throw new NativeError('crypto_scope_head_unavailable', 503);
        }
        $initial = (new NativeCryptoLifecycleV2($this->container))->initialBaseline($sid);
        if (($body['initialLifecycleHash'] ?? null) !== $initial['initialLifecycleHash']) {
            throw new NativeError('crypto_lifecycle_log_unavailable',503);
        }
        return $h;
    }
    public function head($sid, $hash)
    {
        $this->digest($hash);
        $r = $this->one('SELECT * FROM familyhub_crypto_scope_heads WHERE scope_id=? AND head_hash=?', [$sid,$hash]);
        if (!$r) {
            throw new NativeError('crypto_scope_head_missing', 404);
        }return $r;
    }
    public function body($head)
    {
        return json_decode($head['payload'], true, 34, JSON_THROW_ON_ERROR);
    }
    public function member($body, $account)
    {
        foreach ($body['members'] as $m) {
            if ($m['accountId'] === $account) {
                return $m;
            }
        }return null;
    }
    public function validateProposal($p)
    {
        $this->fields($p, ['scopeId','epoch','previousHeadHash','authorDirectoryHeadHash','expectedAccessRevision','accessBasis','accessRevision','members','membershipIntents','closures','keyCommitments','keyIds','contentKeyProposalProof','financeKeyProposalProof','initialLifecycleHash','previousLifecycleHash','financePolicyIntentProof'],['accessIntentProof']);
        $this->uuid($p['scopeId']);
        $this->digest($p['previousHeadHash']);
        $this->digest($p['authorDirectoryHeadHash']);
        $this->digest($p['initialLifecycleHash']);
        if ($p['previousLifecycleHash'] !== null) { $this->digest($p['previousLifecycleHash']); }
        if (!is_int($p['epoch']) || $p['epoch'] < 1 || !is_int($p['accessRevision']) || $p['accessRevision'] < 0 || !is_array($p['members']) || !array_is_list($p['members']) || !$p['members']) {
            throw new NativeError('validation_error');
        }
        if (isset($p['financePolicyIntentProof']) && !is_array($p['financePolicyIntentProof'])) {
            throw new NativeError('validation_error');
        }
        if (!is_int($p['expectedAccessRevision']) || $p['expectedAccessRevision'] < 0 || !is_array($p['accessBasis']) || !array_is_list($p['accessBasis']) || count($p['accessBasis']) < 1 || count($p['accessBasis']) > 2) {
            throw new NativeError('validation_error');
        }
        $lastToken = '';
        foreach ($p['accessBasis'] as $basis) {
            if (!is_array($basis)) {
                throw new NativeError('validation_error');
            }
            $this->fields($basis, ['scopeToken', 'accessRevision']);
            $this->digest($basis['scopeToken']);
            if (strcmp($basis['scopeToken'], $lastToken) <= 0 || !is_int($basis['accessRevision']) || $basis['accessRevision'] < 0) {
                throw new NativeError('validation_error');
            }
            $lastToken = $basis['scopeToken'];
        }
        if (!is_array($p['membershipIntents']) || !array_is_list($p['membershipIntents']) || count($p['membershipIntents']) > 100) {
            throw new NativeError('validation_error');
        }
        $lastIntent = '';
        foreach ($p['membershipIntents'] as $intent) {
            if (!is_array($intent)) {
                throw new NativeError('validation_error');
            }
            $this->fields($intent, ['accountId','invitationId','acceptanceProofHash']);
            $id = $this->uuid($intent['accountId']);
            $this->uuid($intent['invitationId']);
            $this->digest($intent['acceptanceProofHash']);
            if (strcmp($id, $lastIntent) <= 0) {
                throw new NativeError('validation_error');
            }
            $lastIntent = $id;
        }
        $previous = '';
        $owners = 0;
        foreach ($p['members'] as $m) {
            if (!is_array($m)) {
                throw new NativeError('validation_error');
            }$this->fields($m, ['accountId','rootSigningKeyBase64','rootEncryptionKeyBase64','recoveryRootEpochId','identityEpochId','directoryHeadHash','deviceSnapshotHash','role','financeRole','manageKeys']);
            $id = $this->uuid($m['accountId']);
            $this->uuid($m['identityEpochId']);
            $this->uuid($m['recoveryRootEpochId']);
            if (strcmp($id, $previous) <= 0 || !in_array($m['role'], ['owner','member','viewer'], true) || !in_array($m['financeRole'], ['none','read','write'], true) || !is_bool($m['manageKeys'])) {
                throw new NativeError('validation_error');
            }$previous = $id;
            $owners += $m['role'] === 'owner' ? 1 : 0;
            NativeCryptoCodec::base64($m['rootSigningKeyBase64'], 32, 32);
            NativeCryptoCodec::base64($m['rootEncryptionKeyBase64'], 32, 32);
            $this->digest($m['directoryHeadHash']);
            $this->digest($m['deviceSnapshotHash']);
        }if ($owners !== 1) {
            throw new NativeError('crypto_scope_owner_required', 409);
        }
        foreach (['closures','keyCommitments'] as $key) {
            if (!is_array($p[$key])) {
                throw new NativeError('validation_error');
            }$this->fields($p[$key], ['content','finance']);
            foreach ($p[$key] as $hash) {
                if ($hash !== null) {
                    $this->digest($hash);
                }
            }
        }
        if (!is_array($p['keyIds'])) {
            throw new NativeError('validation_error');
        }$this->fields($p['keyIds'], ['content','finance']);
        foreach (['content','finance'] as $domain) {
            if (($p['keyIds'][$domain] === null) !== ($p['keyCommitments'][$domain] === null)) {
                throw new NativeError('crypto_key_commitment_required', 409);
            }if ($p['keyIds'][$domain] !== null) {
                $this->uuid($p['keyIds'][$domain]);
            }
        }
        if (($p['contentKeyProposalProof'] !== null && !is_array($p['contentKeyProposalProof'])) || ($p['financeKeyProposalProof'] !== null && !is_array($p['financeKeyProposalProof']))) {
            throw new NativeError('validation_error');
        }
        if ($p['keyIds']['content'] === $p['keyIds']['finance'] || $p['keyCommitments']['content'] === $p['keyCommitments']['finance']) {
            throw new NativeError('crypto_scope_key_reused', 409);
        }
        if ($p['keyCommitments']['content'] === null) {
            throw new NativeError('crypto_key_commitment_required', 409);
        }
    }
    public function write($op, $p, $actor, $proof, $command = null, $key = null)
    {
        // The private parent proof never enters the child's retained public
        // activation. Only its purpose-separated digest is signed there.
        if ($op === 'crypto2.scope.activate' && array_key_exists('activationProof',$p)) {
            if (!$this->transactionActive() || $this->parentTopologyContext !== null || !$command || !$key) {
                throw new NativeError('crypto_topology_activation_context',409);
            }
            $this->fields($p,['scopeId','headHash','activationProof','parentTopologyBatch']);
            [$inner,$bytes,$signature]=NativeCryptoCodec::decode($p['activationProof']);
            $this->fields($inner,['version','operation','requestId','serverId','accountId','deviceId','signer','payload']);
            $this->uuid($inner['requestId']);
            if ($inner['version']!==2 || $inner['operation']!==$op || $inner['signer']!=='device') {
                throw new NativeError('crypto_topology_activation_context',409);
            }
            foreach (['serverId','accountId','deviceId'] as $field) {
                if ($inner[$field]!==$command[$field]) throw new NativeError('crypto_topology_activation_context',409);
            }
            NativeCryptoV2Codec::verify($bytes,$signature,$key);
            $bundleHash=hash('sha256',"JivieFinanceTopologyCreationBatch/v3\n".NativeCryptoCodec::canonical((object)$p['parentTopologyBatch']));
            if (($inner['payload']['scopeId']??null)!==$p['scopeId'] || ($inner['payload']['headHash']??null)!==$p['headHash']
                || ($inner['payload']['parentTopologyBatchHash']??null)!==$bundleHash) {
                throw new NativeError('crypto_topology_activation_context',409);
            }
            $this->parentTopologyContext=$p['parentTopologyBatch'];
            try {
                return $this->write($op,$inner['payload'],$actor,$p['activationProof'],$inner,$key);
            } finally {
                $this->parentTopologyContext=null;
            }
        }
        if ($op === 'crypto2.scope.prepare') {
            $this->fields($p,['scopeId','expectedAccessRevision']);
            $sid=$this->uuid($p['scopeId']);
            $scope=$this->scope($sid,$actor['user']['id'],false,true);
            if ($p['expectedAccessRevision'] !== (int)$scope['effective_access_revision']) {
                throw new NativeError('crypto_access_changed',409);
            }
            $generation=(new NativeCryptoMigrationGenerationV3($this->container,$this->bearer,$this->ip))->supersededPreparation($sid);
            if ($this->one('SELECT head_hash FROM familyhub_crypto_scope_heads WHERE scope_id=? LIMIT 1',[$sid]) && !$generation) {
                throw new NativeError('crypto_scope_exists',409);
            }
            if($generation)return ['scopeId'=>$sid,'state'=>'staged','epoch'=>1,'cutoverSupported'=>false]+(new NativeCryptoLifecycleV2($this->container))->initialBaseline($sid);
            if (!$this->one('SELECT scope_id FROM familyhub_crypto_scopes WHERE scope_id=?',[$sid])) {
                $this->change("INSERT INTO familyhub_crypto_scopes(scope_id,epoch,sequence,access_revision,state) VALUES(?,1,0,?,'staged')",[$sid,(int)$scope['effective_access_revision']]);
            }
            $initial=(new NativeCryptoLifecycleV2($this->container))->captureBaseline($sid,'legacy',$proof);
            return ['scopeId'=>$sid,'state'=>'staged','epoch'=>1,'cutoverSupported'=>false]+$initial;
        }
        $sid = $this->uuid($p['scopeId'] ?? null);
        $scope = $this->accessContext['scope'] ?? $this->scope($sid, $actor['user']['id']);
        $current = $this->current($sid);
        if (!$current && in_array($op,['crypto2.scope.headPut','crypto2.grants.put','crypto2.scope.activate'],true)) {
            $initial=(new NativeCryptoLifecycleV2($this->container))->initialBaseline($sid);
            [$origin]=NativeCryptoCodec::decode($initial['originAuthorization']);
            if(isset($origin['projectRelocation'])&&!$this->relocationContext){
                throw new NativeError('crypto_project_relocation_required',409);
            }
        }
        $this->refreshPending($sid, $current);
        if ($op === 'crypto2.scope.cancel') {
            $this->fields($p, ['scopeId', 'headHash']);
            $this->manager($current, $scope, $actor);
            if ($op === 'crypto2.scope.activate') {
                $this->currentAuthorReference($p['authorDirectoryHeadHash'], $actor);
            }
            $candidate = $this->head($sid, $p['headHash']);
            if (!in_array($candidate['state'], ['pending', 'expired'], true)) {
                throw new NativeError('crypto_scope_head_conflict', 409);
            }
            $this->change("UPDATE familyhub_crypto_scope_heads SET state='cancelled' WHERE scope_id=? AND head_hash=?", [$sid, $p['headHash']]);
            $this->refreshPending($sid, $current);
            $closed=$this->closedDomains($sid,$current['head_hash']??null);
            return ['scopeId' => $sid, 'headHash' => $p['headHash'], 'state' => 'cancelled',
                'cleanupRequired'=>(bool)$closed,'closedDomains'=>$closed];
        }
        if ($op === 'crypto2.scope.headPut') {
            $this->validateProposal($p);
            $this->assertNoDeletedMembers($p['members']);
            $authorDirectory = (new NativeCryptoDirectoryV2($this->container))->current($actor['user']['account_id']);
            $authorReference = $this->one('SELECT device_snapshot_hash FROM familyhub_crypto_directory WHERE account_id=? AND head_hash=?', [$actor['user']['account_id'], $p['authorDirectoryHeadHash']]);
            if (!$authorDirectory || !$authorReference || $authorReference['device_snapshot_hash'] !== $authorDirectory['device_snapshot_hash']) {
                throw new NativeError('crypto_member_directory_changed', 409);
            }
            $this->manager($current, $scope, $actor);
            $old = $current ? $this->body($current) : null;
            $initial=(new NativeCryptoLifecycleV2($this->container))->initialBaseline($sid);
            if (!$current) {
                $generation=(new NativeCryptoMigrationGenerationV3($this->container,$this->bearer,$this->ip))->approvedHead($sid,$p,$proof,$actor);
                if(!$generation&&$this->one('SELECT head_hash FROM familyhub_crypto_scope_heads WHERE scope_id=? AND activation_authorization IS NOT NULL LIMIT 1',[$sid]))throw new NativeError('crypto_migration_generation_approval_required',409);
                [$origin] = NativeCryptoCodec::decode($initial['originAuthorization']);
                $originDirectory = $this->one('SELECT device_snapshot_hash,identity_epoch_id FROM familyhub_crypto_directory WHERE account_id=? AND head_hash=?', [$origin['accountId'],$initial['originAuthorDirectoryHeadHash']]);
                if (!$generation && ($origin['accountId'] !== $actor['user']['account_id'] || $origin['deviceId'] !== $actor['device']['id'] || !$originDirectory || $originDirectory['identity_epoch_id'] !== $authorDirectory['identity_epoch_id'])) {
                    throw new NativeError('crypto_scope_origin_author_mismatch', 403);
                }
            }
            if ($p['initialLifecycleHash'] !== $initial['initialLifecycleHash'] || $old && $old['initialLifecycleHash'] !== $p['initialLifecycleHash']) {
                throw new NativeError('crypto_lifecycle_baseline_changed',409);
            }
            $lifecycle=(new NativeCryptoLifecycleV2($this->container))->current($sid);
            if ($p['previousLifecycleHash'] !== ($current ? $lifecycle['headHash'] : null)) {
                throw new NativeError('crypto_lifecycle_conflict',409);
            }
            if ($p['previousHeadHash'] !== ($current['head_hash'] ?? NativeCryptoDirectoryV2::ZERO) || $p['epoch'] !== ($current ? (int)$current['epoch'] + 1 : 1)) {
                throw new NativeError('crypto_scope_head_conflict', 409);
            }
            $state = $this->one('SELECT state FROM familyhub_crypto_scopes WHERE scope_id=?', [$sid]);
            if (!$state || !in_array($state['state'], ['staged','fenced','verified','active'], true)) {
                throw new NativeError('crypto_scope_not_ready', 409);
            }
            $this->validateMembershipPlan($scope, $p, $current, $actor);
            (new NativeCryptoKeyContributionV2($this->container, $this->bearer, $this->ip))->verifyContent($p, $current, $scope, $actor['user']['account_id']);
            (new NativeCryptoFinanceContributionV2($this->container, $this->bearer, $this->ip))->verifyKey($p, $current, $scope, $actor['user']['account_id']);
            $financeMembers = array_filter($p['members'], fn ($m) => $m['financeRole'] !== 'none');
            if (($p['keyIds']['finance'] === null) !== (!$financeMembers)) {
                throw new NativeError('crypto_finance_membership_changed', 409);
            }
            foreach (['content','finance'] as $domain) {
                if ($old && $old['keyCommitments'][$domain] !== null && $old['keyCommitments'][$domain] === $p['keyCommitments'][$domain]) {
                    throw new NativeError('crypto_scope_key_reused', 409);
                }if (!$old && $p['closures'][$domain] !== null) {
                    throw new NativeError('crypto_closure_unexpected', 409);
                }
            }
            $hash = hash('sha256', "JivieScopeHead/v2\n".NativeCryptoCodec::canonical((object)$p));
            $existing = $this->one('SELECT state FROM familyhub_crypto_scope_heads WHERE scope_id=? AND head_hash=?', [$sid, $hash]);
            if ($existing && $existing['state'] !== 'pending') {
                throw new NativeError('crypto_scope_candidate_expired', 409);
            }
            if (!$existing) {
                $count = $this->one("SELECT COUNT(*) AS n FROM familyhub_crypto_scope_heads WHERE scope_id=? AND state='pending'", [$sid]);
                if ((int)$count['n'] >= 16) {
                    throw new NativeError('crypto_scope_candidates_full', 409);
                }
                foreach (['content','finance'] as $domain) {
                    if ($p['keyIds'][$domain] === null) {
                        continue;
                    }
                    $reservation = $this->one('SELECT * FROM familyhub_crypto_domain_keys WHERE key_id=? OR key_commitment=?', [$p['keyIds'][$domain],$p['keyCommitments'][$domain]]);
                    if ($reservation && (new NativeCryptoKeyContributionV2($this->container, $this->bearer, $this->ip))->claimReservation($p, $domain, $reservation, $hash)) {
                        $reservation['head_hash'] = $hash;
                    }
                    if ($reservation && ($reservation['key_id'] !== $p['keyIds'][$domain] || $reservation['key_commitment'] !== $p['keyCommitments'][$domain] || $reservation['scope_id'] !== $sid || $reservation['head_hash'] !== $hash || $reservation['domain'] !== $domain)) {
                        throw new NativeError('crypto_scope_key_reused', 409);
                    }
                    if (!$reservation) {
                        $this->change('INSERT INTO familyhub_crypto_domain_keys VALUES(?,?,?,?,?)', [$p['keyIds'][$domain],$p['keyCommitments'][$domain],$sid,$hash,$domain]);
                    }
                }$this->change('INSERT INTO familyhub_crypto_scope_heads(scope_id,head_hash,epoch,previous_head_hash,access_revision,payload,authorization,state) VALUES(?,?,?,?,?,?,?,?)', [$sid,$hash,$p['epoch'],$p['previousHeadHash'],$p['accessRevision'],NativeCryptoCodec::canonical((object)$p),json_encode($proof, JSON_THROW_ON_ERROR),'pending']);
            }
            return ['scopeId' => $sid,'headHash' => $hash,'epoch' => $p['epoch'],'state' => 'pendingKeys'];
        }
        if ($op === 'crypto2.scope.closeDomain') {
            return $this->close($p, $scope, $current, $actor, $proof);
        }
        if ($op === 'crypto2.grants.put') {
            return $this->grant($p, $scope, $current, $actor, $proof);
        }
        if ($op === 'crypto2.scope.activate') {
            $relocation=$p['projectRelocation']??null;
            if($this->relocationContext){
                $expected=['version'=>2,'actionId'=>$this->relocationContext['actionId'],'planHash'=>$this->relocationContext['planHash']];
                if(!is_array($relocation)||NativeCryptoCodec::canonical((object)$relocation)!==NativeCryptoCodec::canonical((object)$expected)){
                    throw new NativeError('crypto_project_relocation_required',409);
                }
            }elseif($relocation!==null){
                throw new NativeError('crypto_project_relocation_required',409);
            }
            $candidateForAccess=$this->head($sid,$p['headHash'] ?? null);
            $accessProof=$this->body($candidateForAccess)['accessIntentProof'] ?? null;
            if ($accessProof!==null) {
                [$accessConsent]=NativeCryptoCodec::decode($accessProof);
                if (!$this->accessContext || $this->accessContext['intentHash']!==$accessConsent['intentHash']) {
                    throw new NativeError('crypto_access_component_required',409);
                }
                if (($p['accessIntentHash'] ?? null)!==$accessConsent['intentHash'] || ($p['affectedCount'] ?? null)!==$accessConsent['affectedCount'] || ($p['affectedHash'] ?? null)!==$accessConsent['affectedHash']) {
                    throw new NativeError('crypto_access_intent_invalid',409);
                }
            } elseif (isset($p['accessIntentHash']) || isset($p['affectedCount']) || isset($p['affectedHash'])) {
                throw new NativeError('crypto_access_intent_invalid',409);
            }
            $this->fields($p, ['scopeId','headHash','grantManifestHash','authorDirectoryHeadHash'], ['ownerAcceptanceProof','contentGrantManifestProof','financeGrantManifestProof','accessIntentHash','affectedCount','affectedHash','projectRelocation','parentTopologyBatchHash']);
            $this->manager($current, $scope, $actor);
            if ($op === 'crypto2.scope.activate') {
                $this->currentAuthorReference($p['authorDirectoryHeadHash'], $actor);
            }
            $candidate = $this->head($sid, $p['headHash']);
            $body = $this->body($candidate);
            $this->assertNoDeletedMembers($body['members']);
            if ($candidate['state'] !== 'pending' || $candidate['previous_head_hash'] !== ($current['head_hash'] ?? NativeCryptoDirectoryV2::ZERO)) {
                throw new NativeError('crypto_scope_head_conflict', 409);
            }
            $plan = $this->validateMembershipPlan($scope, $body, $current, $actor);
            $this->closuresReady($current, $body);
            $manifest = $this->grantManifest($body, true);
            $digest = NativeCryptoV2Codec::hash((object)$manifest);
            if ($p['grantManifestHash'] !== $digest) {
                throw new NativeError('crypto_grant_manifest_changed', 409, ['grantManifestHash' => $digest]);
            }
            $finance = new NativeCryptoFinanceContributionV2($this->container, $this->bearer, $this->ip);
            [$proposalCommand] = NativeCryptoCodec::decode(json_decode($candidate['authorization'], true, 34, JSON_THROW_ON_ERROR));
            $keys = new NativeCryptoKeyContributionV2($this->container, $this->bearer, $this->ip);
            $keys->verifyContent($body, $current, $scope, $proposalCommand['accountId']);
            $keys->verifyManifest($body, $current, $scope, $candidate['head_hash'], $manifest['content'], $p['contentGrantManifestProof'] ?? null);
            $proposalUser = $this->one('SELECT a.account_id,u.* FROM familyhub_accounts a JOIN users u ON u.id=a.user_id WHERE a.account_id=? AND u.is_active=1', [$proposalCommand['accountId']]);
            if (!$proposalUser) {
                throw new NativeError('crypto_device_unapproved', 403);
            }
            $this->currentAuthorReference($body['authorDirectoryHeadHash'], ['user' => $proposalUser, 'device' => ['id' => $proposalCommand['deviceId']]]);
            $finance->verifyKey($body, $current, $scope, $proposalCommand['accountId']);
            $finance->verifyManifest($body, $current, $scope, $candidate['head_hash'], $manifest['finance'], $p['financeGrantManifestProof'] ?? null);
            $this->ownerAcceptance($p, $body, $plan);
            $parent = $scope['parent_scope_id'] ?? $scope['organization_id'] ?? null;
            $newChild = !$current && !$this->relocationContext && $parent !== null
                && $scope['kind'] === 'project' && ($origin['operation'] ?? null) === 'crypto2.scope.origin';
            if ($newChild) {
                if ($this->parentTopologyContext === null || !isset($p['parentTopologyBatchHash'])) {
                    throw new NativeError('crypto_topology_activation_required',409);
                }
                (new NativeCryptoFinanceTopologyCreationV3($this->container,$this->bearer,$this->ip))
                    ->install($scope,$actor,$command,$key,$this->parentTopologyContext);
            } elseif (array_key_exists('parentTopologyBatchHash',$p) || $this->parentTopologyContext !== null) {
                throw new NativeError('crypto_topology_activation_context',409);
            }

            (new NativeCryptoFinancePolicyV2($this->container, $this->bearer, $this->ip))->applyForHead($scope, $body, $current, true);
            $future = $this->applyMembershipPlan($scope, $plan);
            $this->membershipParity($future, $body['members']);
            if ($current) {
                $this->change("UPDATE familyhub_crypto_scope_heads SET state='historical' WHERE scope_id=? AND head_hash=?", [$sid,$current['head_hash']]);
                $this->change('UPDATE familyhub_crypto_scope_state SET head_hash=?,epoch=?,access_revision=?,content_closed=0,finance_closed=0 WHERE scope_id=?', [$p['headHash'],$candidate['epoch'],$candidate['access_revision'],$sid]);
            } else {
                $this->change('INSERT INTO familyhub_crypto_scope_state VALUES(?,?,?,?,0,0)', [$sid,$p['headHash'],$candidate['epoch'],$candidate['access_revision']]);
                foreach (['content', 'finance'] as $domain) {
                    if (!$this->one('SELECT scope_id FROM familyhub_crypto_domain_cursors WHERE scope_id=? AND domain=?', [$sid, $domain])) {
                        $this->change('INSERT INTO familyhub_crypto_domain_cursors VALUES(?,?,0)', [$sid, $domain]);
                    }
                }
            }
            $this->change("UPDATE familyhub_crypto_scope_heads SET state='active',activation_authorization=? WHERE scope_id=? AND head_hash=?", [json_encode($proof, JSON_THROW_ON_ERROR),$sid,$p['headHash']]);
            $this->change('UPDATE familyhub_crypto_scopes SET epoch=?,access_revision=? WHERE scope_id=?', [$candidate['epoch'],$candidate['access_revision'],$sid]);
            $this->clearDeletionBlock($sid,$current,$candidate,$body);
            return ['scopeId' => $sid,'headHash' => $p['headHash'],'epoch' => (int)$candidate['epoch'],'state' => 'keysReady','grantManifestHash' => $digest];
        }
        throw new NativeError('unsupported_operation', 404);
    }
    public function activateAccess($intentHash,$scope,$actor,$command,$proof,$key)
    {
        $this->accessContext=['intentHash'=>$intentHash,'scope'=>$scope,'accountId'=>$actor['user']['account_id'],'deviceId'=>$actor['device']['id']];
        try {
            return $this->write('crypto2.scope.activate',$command['payload'],$actor,$proof,$command,$key);
        } finally {
            $this->accessContext=null;
        }
    }

    public function assertMembershipParity($scope,$members,$headHash=null)
    {
        $directories=$headHash===null?null:NativeCryptoMigrationGenerationV3::retainedMembershipDirectories($this->pdo,$scope['id'],$headHash,$members);
        $this->membershipParity($scope,$members,$directories);
    }

    public function manager($head, $scope, $actor)
    {
        $componentAuthorized=$this->accessContext && $this->accessContext['scope']['id']===$scope['id'] && $this->accessContext['accountId']===$actor['user']['account_id'] && $this->accessContext['deviceId']===$actor['device']['id'];
        $relocationAuthorized=$this->relocationContext&&$this->relocationContext['scopeId']===$scope['id']&&$this->relocationContext['accountId']===$actor['user']['account_id']&&$this->relocationContext['deviceId']===$actor['device']['id'];
        if (!$head) {
            if ((int)$scope['owner_id'] !== (int)$actor['user']['id'] && !$relocationAuthorized) {
                throw new NativeError('permission_revoked', 403);
            }
        } else {
            $member = $this->member($this->body($head), $actor['user']['account_id']);
            if (!$member || !$member['manageKeys']) {
                throw new NativeError('crypto_scope_management_forbidden', 403);
            }
            if (!$componentAuthorized) { $this->scope($scope['id'], $actor['user']['id'], false, true); }
        }
        $member = $head ? $this->member($this->body($head), $actor['user']['account_id']) : ['manageKeys' => true];
        if (!$member || !$member['manageKeys']) {
            throw new NativeError('crypto_scope_management_forbidden', 403);
        }
        if (!$componentAuthorized) { $this->scope($scope['id'], $actor['user']['id'], false, true); }
        $currentActor=NativeCryptoMigrationGenerationV3::continuedActor($this->pdo,$actor);
        $d = (new NativeCryptoDirectoryV2($this->container))->current($actor['user']['account_id']);
        $device = (new NativeCryptoDirectoryV2($this->container))->device(json_decode($d['snapshot'], true, 34, JSON_THROW_ON_ERROR), $currentActor['device']['id']);
        if (!$device || !$device['keyringWrite']) {
            throw new NativeError('crypto_keyring_forbidden', 403);
        }
    }

    /** Internal savepoint/final coordinator entry only. The parent manager may
     * create the legacy-equivalent child with the ORIGINAL owner; it never
     * becomes owner merely by staging a head. No normal route sets this token. */
    public function relocationWrite($actionId,$planHash,$scope,$actor,$command,$proof)
    {
        if($this->relocationContext!==null||!$this->transactionActive()||!in_array($command['operation']??null,['crypto2.scope.headPut','crypto2.grants.put','crypto2.scope.activate'],true)){
            throw new NativeError('crypto_relocation_context',409);
        }
        $row=$this->one('SELECT * FROM familyhub_crypto_project_relocations_v2 WHERE action_id=?'.$this->lockSuffix(),[$actionId]);
        if(!$row||$row['plan_hash']!==$planHash||$row['account_id']!==$actor['user']['account_id']||$row['device_id']!==$actor['device']['id']||!in_array($row['state'],['preparing','staged','committing'],true)||(int)$row['expires_at']<=time()){
            throw new NativeError('crypto_relocation_context',409);
        }
        $planProof=json_decode($row['authorization'],true,34,JSON_THROW_ON_ERROR);[$plan]=NativeCryptoCodec::decode($planProof);
        NativeCryptoProjectRelocationCodecV2::plan($plan);
        if(NativeCryptoProjectRelocationCodecV2::hash($planProof)!==$planHash||$plan['targetScopeId']!==$scope['id']||($command['payload']['scopeId']??null)!==$scope['id']||($scope['parent_scope_id']??null)!==$plan['sourceScopeId']){
            throw new NativeError('crypto_relocation_context',409);
        }
        $parent=$this->scope($plan['sourceScopeId'],$actor['user']['id'],true,true);
        $parentHead=$this->current($parent['id']);
        if($parent['kind']!=='household'||(int)$parent['access_policy_version']!==3||!$parentHead||$parentHead['head_hash']!==$plan['sourceHeadHash']||(int)$parent['effective_access_revision']!==$plan['sourceAccessRevision']||(new NativeCryptoLifecycleV2($this->container))->closingHash($parent['id'])!==$plan['sourceLifecycleHash']){
            throw new NativeError('project_sharing_preview_changed',409);
        }
        $this->manager($parentHead,$parent,$actor);
        $this->author($parent['id'],$parentHead['head_hash'],(int)$parentHead['epoch'],(int)$parent['effective_access_revision'],$actor,'content');
        [$signedCommand,$commandBytes,$commandSignature]=NativeCryptoCodec::decode($proof);
        $this->fields($signedCommand,['version','operation','requestId','serverId','accountId','deviceId','signer','payload']);
        if(NativeCryptoCodec::canonical((object)$signedCommand)!==NativeCryptoCodec::canonical((object)$command)||$signedCommand['version']!==2||$signedCommand['serverId']!==$this->serverId()||$signedCommand['accountId']!==$actor['user']['account_id']||$signedCommand['deviceId']!==$actor['device']['id']||$signedCommand['signer']!=='device'){
            throw new NativeError('crypto_relocation_nested_command',409);
        }
        $this->uuid($signedCommand['requestId']);
        $directory=new NativeCryptoDirectoryV2($this->container);
        NativeCryptoV2Codec::verify($commandBytes,$commandSignature,$directory->authorizeContent($signedCommand,$directory->current($signedCommand['accountId'])));
        $owner=$this->one('SELECT account_id FROM familyhub_accounts WHERE user_id=?',[$scope['owner_id']]);
        if(!$owner||$owner['account_id']!==$plan['targetOwnerAccountId'])throw new NativeError('crypto_relocation_owner_changed',409);
        $initial=(new NativeCryptoLifecycleV2($this->container))->initialBaseline($scope['id']);[$origin]=NativeCryptoCodec::decode($initial['originAuthorization']);
        $marker=['version'=>2,'actionId'=>$actionId,'planHash'=>$planHash];
        if(!isset($origin['projectRelocation'])||NativeCryptoCodec::canonical((object)$origin['projectRelocation'])!==NativeCryptoCodec::canonical((object)$marker)){
            throw new NativeError('crypto_relocation_context',409);
        }
        $this->relocationContext=$marker+['scopeId'=>$scope['id'],'accountId'=>$actor['user']['account_id'],'deviceId'=>$actor['device']['id'],'headAuthorization'=>$row['target_head_authorization'],'expiresAt'=>(int)$row['expires_at']];
        try{
            return $this->write($command['operation'],$command['payload'],$actor,$proof);
        }finally{
            $this->relocationContext=null;
            $this->pendingRead=null;
        }
    }
    public function accessBasis($scope)
    {
        $parts = [$scope];
        $parent = $scope['parent_scope_id'] ?? $scope['organization_id'] ?? null;
        if ($parent) {
            $row = $this->one('SELECT id,access_revision FROM familyhub_scopes WHERE id=?', [$parent]);
            if (!$row) {
                throw new NativeError('crypto_membership_changed', 409);
            }
            $parts[] = $row;
        }
        $out = [];
        foreach ($parts as $part) {
            $revision = (int)$part['access_revision'];
            if ($revision < 0 || $revision > 9007199254740991) {
                throw new NativeError('crypto_access_revision_exhausted', 409);
            }
            $out[] = ['scopeToken' => hash('sha256', "JivieScopeAccessBasis/v2\n".$this->serverId().':'.$scope['id'].':'.$part['id']), 'accessRevision' => $revision];
        }
        usort($out, fn ($a, $b) => strcmp($a['scopeToken'], $b['scopeToken']));
        return $out;
    }

    private function membershipPlan($scope, $body, $current, $actor)
    {
        if ($body['expectedAccessRevision'] !== (int)$scope['effective_access_revision'] || NativeCryptoCodec::canonical($body['accessBasis']) !== NativeCryptoCodec::canonical($this->accessBasis($scope))) {
            throw new NativeError('crypto_access_changed', 409);
        }
        $actual = [];
        foreach ($this->effectiveMembers($scope['id']) as $member) {
            $actual[$member['accountId']] = $member;
        }
        $desired = [];
        $intents = [];
        foreach ($body['membershipIntents'] as $intent) {
            $intents[$intent['accountId']] = $intent;
        }
        $additions = [];
        $newOwner = null;
        foreach ($body['members'] as $member) {
            $account=$member['accountId'];
            $direct=$this->one('SELECT active FROM familyhub_members WHERE scope_id=? AND account_id=?',[$scope['id'],$account]);
            $hasDirect=$direct && (int)$direct['active']===1;
            $intent=$intents[$account]??null;
            $newDirect=$intent && !$hasDirect;
            $requiresIntent=!isset($actual[$account]) || !$hasDirect && isset($actual[$account]) && $actual[$account]['role']!==$member['role'];
            if ($newDirect || $requiresIntent) {
                if (!$intent) { throw new NativeError('crypto_invitation_acceptance_required',409); }
                $additions[$account]=(new NativeCryptoInvitationV2($this->container,$this->bearer,$this->ip))->intent($scope['id'],$intent,$member);
                unset($intents[$account]);
            }
            $desired[$member['accountId']] = $member;
            if ($member['role'] === 'owner') {
                $newOwner = $actual[$member['accountId']] ?? null;
            }
        }
        if ($intents) {
            throw new NativeError('crypto_invitation_intent_unexpected', 409);
        }
        $changed = count($actual) !== count($desired) || (bool)$additions;
        foreach ($actual as $account => $member) {
            if (!isset($desired[$account]) || $desired[$account]['role'] !== $member['role']) {
                $changed = true;
            }
        }
        if ($changed && (!$current || $scope['kind'] === 'personal')) {
            throw new NativeError('crypto_membership_changed', 409);
        }
        $transfer = $newOwner && (int)$newOwner['userId'] !== (int)$scope['owner_id'];
        if ($transfer) {
            $oldOwner = $this->member($this->body($current), $actor['user']['account_id']);
            if (!$oldOwner || $oldOwner['role'] !== 'owner' || (int)$scope['owner_id'] !== (int)$actor['user']['id']) {
                throw new NativeError('crypto_owner_transfer_forbidden', 403);
            }
        }
        if ($changed && (int)$scope['effective_access_revision'] >= 9007199254740991) {
            throw new NativeError('crypto_access_revision_exhausted', 409);
        }
        $expected = (int)$scope['effective_access_revision'] + ($changed ? 1 : 0);
        if ($body['accessRevision'] !== $expected) {
            throw new NativeError('crypto_access_changed', 409);
        }
        return ['changed' => $changed, 'transfer' => $transfer, 'actual' => $actual, 'desired' => $desired, 'newOwner' => $newOwner, 'additions' => $additions];
    }

    private function applyMembershipPlan($scope, $plan)
    {
        if (isset($plan['accessTransition'])) {
            return $plan['futureScope'];
        }
        if (!$plan['changed']) {
            return $scope;
        }
        foreach ($plan['actual'] as $account => $member) {
            $desired = $plan['desired'][$account] ?? null;
            $direct = $this->one('SELECT active,role FROM familyhub_members WHERE scope_id=? AND account_id=?', [$scope['id'], $account]);
            if (!$desired) {
                if ($direct) {
                    $this->change('UPDATE familyhub_members SET active=0 WHERE scope_id=? AND account_id=?', [$scope['id'], $account]);
                }
            } elseif ($direct) {
                $this->change('UPDATE familyhub_members SET role=?,active=1 WHERE scope_id=? AND account_id=?', [$desired['role'], $scope['id'], $account]);
            } elseif ($member['role'] !== $desired['role']) {
                $this->change('INSERT INTO familyhub_members(scope_id,user_id,account_id,role,active) VALUES(?,?,?,?,1)', [$scope['id'], $member['userId'], $account, $desired['role']]);
            }
        }
        foreach ($plan['additions'] as $account => $addition) {
            $old = $this->one('SELECT user_id FROM familyhub_members WHERE scope_id=? AND user_id=?', [$scope['id'], $addition['userId']]);
            if ($old) {
                $this->change('UPDATE familyhub_members SET account_id=?,role=?,active=1 WHERE scope_id=? AND user_id=?', [$account, $plan['desired'][$account]['role'], $scope['id'], $addition['userId']]);
            } else {
                $this->change('INSERT INTO familyhub_members(scope_id,user_id,account_id,role,active) VALUES(?,?,?,?,1)', [$scope['id'], $addition['userId'], $account, $plan['desired'][$account]['role']]);
            }
            (new NativeCryptoInvitationV2($this->container))->consume($addition);
        }
        if ($plan['transfer']) {
            $scope['owner_id'] = (int)$plan['newOwner']['userId'];
            $this->change('UPDATE familyhub_scopes SET owner_id=? WHERE id=?', [$scope['owner_id'], $scope['id']]);
        }
        $this->change('UPDATE familyhub_scopes SET access_revision=access_revision+1 WHERE id=?', [$scope['id']]);
        $scope['access_revision'] = (int)$scope['access_revision'] + 1;
        $scope['effective_access_revision'] = (int)$scope['effective_access_revision'] + 1;
        return $scope;
    }

    public function validateMembershipPlan($scope, $body, $current, $actor)
    {
        if (($body['accessIntentProof'] ?? null)!==null) {
            return (new NativeCryptoAccessV2($this->container,$this->bearer,$this->ip))->validateHead($scope,$body,$current,$actor);
        }
        $plan = $this->membershipPlan($scope, $body, $current, $actor);
        $this->pdo->exec('SAVEPOINT crypto2_membership_preview');
        try {
            (new NativeCryptoFinancePolicyV2($this->container, $this->bearer, $this->ip))->applyForHead($scope, $body, $current);
            $future = $this->applyMembershipPlan($scope, $plan);
            $this->membershipParity($future, $body['members']);
        } finally {
            $this->pdo->exec('ROLLBACK TO SAVEPOINT crypto2_membership_preview');
            $this->pdo->exec('RELEASE SAVEPOINT crypto2_membership_preview');
        }
        return $plan;
    }

    public function ownerAcceptance($payload, $body, $plan)
    {
        if (!$plan['transfer']) {
            if (isset($payload['ownerAcceptanceProof'])) {
                throw new NativeError('crypto_owner_acceptance_unexpected', 409);
            }
            return;
        }
        $proof = $payload['ownerAcceptanceProof'] ?? null;
        if (!is_array($proof)) {
            throw new NativeError('crypto_owner_acceptance_required', 409);
        }
        [$acceptance, $bytes, $signature] = NativeCryptoCodec::decode($proof);
        $this->fields($acceptance, ['version', 'operation', 'serverId', 'scopeId', 'headHash', 'previousHeadHash', 'grantManifestHash', 'accountId', 'deviceId', 'authorDirectoryHeadHash']);
        if ($acceptance['version'] !== 2 || $acceptance['operation'] !== 'crypto2.scope.ownerAccept' || $acceptance['serverId'] !== $this->serverId() || $acceptance['scopeId'] !== $body['scopeId'] || $acceptance['headHash'] !== $payload['headHash'] || $acceptance['previousHeadHash'] !== $body['previousHeadHash'] || $acceptance['grantManifestHash'] !== $payload['grantManifestHash'] || $acceptance['accountId'] !== $plan['newOwner']['accountId']) {
            throw new NativeError('crypto_owner_acceptance_invalid', 403);
        }
        $directory = new NativeCryptoDirectoryV2($this->container);
        $current = $directory->current($acceptance['accountId']);
        $reference = $this->one('SELECT device_snapshot_hash FROM familyhub_crypto_directory WHERE account_id=? AND head_hash=?', [$acceptance['accountId'], $acceptance['authorDirectoryHeadHash']]);
        if (!$current || !$reference || $reference['device_snapshot_hash'] !== $current['device_snapshot_hash']) {
            throw new NativeError('crypto_member_directory_changed', 409);
        }
        $snapshot = json_decode($current['snapshot'], true, 34, JSON_THROW_ON_ERROR);
        $device = $directory->device($snapshot, $acceptance['deviceId']);
        if (!$device || $device['revokedGeneration'] !== null || !$device['keyringWrite'] || $device['identityEpochId'] !== $snapshot['identityEpochId']) {
            throw new NativeError('crypto_device_unapproved', 403);
        }
        NativeCryptoV2Codec::verify($bytes, $signature, $device['signingKeyBase64'], "JivieE2EE/scopeOwnerAcceptance/v2\n");
    }

    private function membershipParity($scope, $members, $retainedDirectories=null)
    {
        $actual = $this->effectiveMembers($scope['id']);
        $mapped = [];
        foreach ($actual as $m) {
            $mapped[$m['accountId']] = $m;
        }if (count($mapped) !== count($members)) {
            throw new NativeError('crypto_membership_changed', 409);
        }
        $finance = new NativeFinanceAccess($this->container);
        $directory = new NativeCryptoDirectoryV2($this->container);
        foreach ($members as $m) {
            $sql = $mapped[$m['accountId']] ?? null;
            if (!$sql || $sql['role'] !== $m['role'] || $m['manageKeys'] !== ($sql['role'] === 'owner' || (int)$scope['effective_access_policy_version'] === 3 && $sql['role'] === 'member')) {
                throw new NativeError('crypto_membership_changed', 409);
            }
            $user = $this->one('SELECT a.account_id,u.* FROM familyhub_accounts a JOIN users u ON u.id=a.user_id WHERE a.account_id=? AND u.is_active=1', [$m['accountId']]);
            if (!$user) {
                throw new NativeError('crypto_membership_changed', 409);
            }$policy = $finance->policyForCrypto($scope['id'], $user, false, false);
            $role = $policy['enabled'] ? $policy['grant'] : 'none';
            if ($role !== $m['financeRole']) {
                throw new NativeError('crypto_finance_membership_changed', 409);
            }
            $current = $directory->current($m['accountId']);
            if (!$current) {
                throw new NativeError('crypto_member_directory_pending', 409);
            }$s = $retainedDirectories[$m['accountId']] ?? json_decode($current['snapshot'], true, 34, JSON_THROW_ON_ERROR);
            foreach (['rootSigningKeyBase64','rootEncryptionKeyBase64','identityEpochId','recoveryRootEpochId'] as $key) {
                if ($m[$key] !== $s[$key]) {
                    throw new NativeError('crypto_member_directory_changed', 409);
                }
            }
            $reference = $this->one('SELECT device_snapshot_hash,identity_epoch_id FROM familyhub_crypto_directory WHERE account_id=? AND head_hash=?', [$m['accountId'],$m['directoryHeadHash']]);
            $expectedSnapshot=$retainedDirectories[$m['accountId']]['deviceSnapshotHash']??$current['device_snapshot_hash'];
            if (!$reference || $m['deviceSnapshotHash'] !== $expectedSnapshot || $reference['device_snapshot_hash'] !== $expectedSnapshot || $reference['identity_epoch_id'] !== $m['identityEpochId']) {
                throw new NativeError('crypto_member_directory_changed', 409);
            }
        }
    }
    public function author($sid, $headHash, $epoch, $access, $actor, $domain, $write = true)
    {
        $this->domain($domain);
        $this->digest($headHash);
        if (!is_int($epoch) || $epoch < 1 || !is_int($access) || $access < 0) {
            throw new NativeError('validation_error');
        }
        $scope = $this->scope($sid, $actor['user']['id'], $write);
        $current = $this->current($sid);
        if (!$current || $current['head_hash'] !== $headHash || (int)$current['epoch'] !== $epoch || (int)$scope['effective_access_revision'] !== $access) {
            throw new NativeError('crypto_scope_head_changed', 409);
        }
        $m = $this->member($this->body($current), $actor['user']['account_id']);
        if (!$m || $write && $m['role'] === 'viewer') {
            throw new NativeError('permission_revoked', 403);
        }
        if ($domain === 'finance') {
            (new NativeFinanceAccess($this->container))->policyForCrypto($sid, $actor['user'], $write, true);
            if ($m['financeRole'] === 'none' || $write && $m['financeRole'] !== 'write') {
                throw new NativeError('finance_forbidden', 403);
            }
        }
        if ($write) {
            NativeCryptoScopeCreationV2::guardBusiness($this->pdo, $sid);
            $this->assertCurrentMembership($scope,$current);
        }
        $this->refreshPending($sid, $current);
        $state = $this->one('SELECT * FROM familyhub_crypto_scope_state WHERE scope_id=?', [$sid]);
        if ($write && (int)$state[$domain.'_closed']) {
            throw new NativeError('crypto_domain_closed', 409);
        }return [$scope,$current,$m];
    }
    /** Business writes need the same ACL revision as the signed active head. */
    public function assertCurrentMembership($scope, $head)
    {
        if ($this->one('SELECT scope_id FROM familyhub_crypto_scope_deletion_blocks_v2 WHERE scope_id=?',[$scope['id']])) {
            throw new NativeError('crypto_scope_rotation_required',409);
        }
        if ((int)$head['access_revision'] !== (int)$scope['effective_access_revision']) {
            throw new NativeError('crypto_scope_rotation_required',409);
        }
        foreach ($this->body($head)['members'] as $participant) {
            if (NativeCryptoAccountTombstoneV2::account($this->pdo,$participant['accountId'])) {
                throw new NativeError('crypto_scope_rotation_required',409);
            }
            $directory = (new NativeCryptoDirectoryV2($this->container))->current($participant['accountId']);
            if (!$directory || $participant['deviceSnapshotHash'] !== $directory['device_snapshot_hash'] && !NativeCryptoMigrationGenerationV3::retainedScope($this->pdo,$scope['id'],$head['head_hash'])) {
                throw new NativeError('crypto_scope_rotation_required',409);
            }
        }
    }

    private function assertNoDeletedMembers(array $members)
    {
        foreach ($members as $member) {
            if (NativeCryptoAccountTombstoneV2::account($this->pdo,$member['accountId'])) {
                throw new NativeError('crypto_scope_member_deleted',409);
            }
        }
    }

    /** Called only after all ordinary successor authority/closures/new keys and
     * SQL membership CAS succeeded, in the same activation transaction. */
    private function clearDeletionBlock($sid,$current,$candidate,$body)
    {
        $block=$this->one('SELECT * FROM familyhub_crypto_scope_deletion_blocks_v2 WHERE scope_id=?',[$sid]);
        if (!$block) { return; }
        $this->assertNoDeletedMembers($body['members']);
        if ($block['head_hash']!==null) {
            $cursor=$current;
            while ($cursor && $cursor['head_hash']!==$block['head_hash']) {
                if ($cursor['previous_head_hash']===NativeCryptoDirectoryV2::ZERO) { $cursor=null;break; }
                $previous=$this->head($sid,$cursor['previous_head_hash']);
                if ((int)$previous['epoch'] >= (int)$cursor['epoch']) {
                    throw new NativeError('crypto_scope_rotation_required',409);
                }
                $cursor=$previous;
            }
            if (!$cursor || (int)$candidate['epoch'] <= (int)$cursor['epoch']) {
                throw new NativeError('crypto_scope_rotation_required',409);
            }
        }
        $this->change('DELETE FROM familyhub_crypto_scope_deletion_blocks_v2 WHERE scope_id=?',[$sid]);
    }

    private function digest($hash)
    {
        if (!is_string($hash) || !preg_match('/^[a-f0-9]{64}$/D', $hash)) {
            throw new NativeError('validation_error');
        }
    }
    private function grant($p, $scope, $current, $actor, $proof)
    {
        $this->fields($p, ['scopeId','headHash','keySourceHeadHash','keyId','accountId','domain','epoch','expectedGeneration','recipients']);
        $this->domain($p['domain']);
        $candidate = $this->head($scope['id'], $p['headHash']);
        $body = $this->body($candidate);
        $this->assertNoDeletedMembers($body['members']);
        if ($candidate['state'] !== 'pending' || $candidate['previous_head_hash'] !== ($current['head_hash'] ?? NativeCryptoDirectoryV2::ZERO)) {
            throw new NativeError('crypto_scope_head_conflict', 409);
        }
        $source = $this->keySource($candidate, $p['keySourceHeadHash'], $p['epoch'], $p['domain']);
        if ($p['keyId'] !== $source['keyIds'][$p['domain']]) {
            throw new NativeError('crypto_grant_key_mismatch', 409);
        }
        if ($p['domain'] === 'content') {
            if ($p['epoch'] === (int)$candidate['epoch'] && is_array($body['contentKeyProposalProof'])) {
                (new NativeCryptoKeyContributionV2($this->container, $this->bearer, $this->ip))->authorizeNewGrant($body, $current, $scope, $actor, 'content');
            } else {
                $this->manager($current, $scope, $actor);
            }
        } else {
            if ($p['epoch'] === (int)$candidate['epoch']) {
                (new NativeCryptoKeyContributionV2($this->container, $this->bearer, $this->ip))->authorizeNewGrant($body, $current, $scope, $actor, 'finance');
            }
            (new NativeCryptoFinancePolicyV2($this->container, $this->bearer, $this->ip))->financeRead($body, $current, $actor['user']);
            $author = $this->member($current ? $this->body($current) : $body, $actor['user']['account_id']);
            $futureAuthor = $this->member($body, $actor['user']['account_id']);
            $firstDomain = $current && $this->body($current)['keyIds']['finance'] === null;
            if (!$author || !$firstDomain && $author['financeRole'] === 'none' || $p['epoch'] === (int)$candidate['epoch'] && (!$futureAuthor || $futureAuthor['financeRole'] === 'none')) {
                throw new NativeError('finance_forbidden', 403);
            }
            if ($firstDomain) {
                (new NativeCryptoFinanceContributionV2($this->container))->verifyKey($body, $current, $scope, $actor['user']['account_id'], false);
            }
        }
        $target = $this->member($body, $this->uuid($p['accountId']));
        if (!$target || $p['domain'] === 'finance' && $target['financeRole'] === 'none') {
            throw new NativeError('permission_revoked', 403);
        }
        $required = $this->requiredRecipients($target);
        $recipients = $p['recipients'];
        if (!is_array($recipients) || !array_is_list($recipients) || count($recipients) < 1 || count($recipients) > 32) {
            throw new NativeError('validation_error');
        }$seen = [];
        $where = [$scope['id'],$p['headHash'],$p['accountId'],$p['domain'],$p['epoch']];
        $old = $this->one('SELECT * FROM familyhub_crypto_grant_states_v2 WHERE scope_id=? AND head_hash=? AND account_id=? AND domain=? AND epoch=?', $where);
        $n = (int)($old['generation'] ?? 0);
        if ($p['expectedGeneration'] !== $n) {
            throw new NativeError('crypto_generation_conflict', 409, ['generation' => $n]);
        }if ($old && ($old['key_source_head_hash'] !== $p['keySourceHeadHash'] || $old['key_id'] !== $p['keyId'])) {
            throw new NativeError('crypto_grant_key_mismatch', 409);
        }
        foreach ($recipients as $r) {
            if (!is_array($r)) {
                throw new NativeError('validation_error');
            }$this->fields($r, ['recipientId','recipientKind','publicKeyBase64','sealedEnvelopeBase64']);
            $key = $r['recipientKind'].':'.$r['recipientId'];
            if (isset($seen[$key]) || !isset($required[$key]) || $required[$key] !== $r['publicKeyBase64']) {
                throw new NativeError('crypto_recipient_key_changed', 409);
            }NativeCryptoCodec::base64($r['publicKeyBase64'], 32, 32);
            $box = NativeCryptoCodec::base64($r['sealedEnvelopeBase64'], 4096);
            if (strlen($box) < 48) {
                throw new NativeError('crypto_invalid_envelope');
            }$seen[$key] = true;
            $args = array_merge($where, [$r['recipientKind'],$r['recipientId']]);
            $existing = $this->one('SELECT recipient_key,envelope FROM familyhub_crypto_grant_entries_v2 WHERE scope_id=? AND head_hash=? AND account_id=? AND domain=? AND epoch=? AND recipient_kind=? AND recipient_id=?', $args);
            if ($existing) {
                if ($existing['recipient_key'] !== $r['publicKeyBase64'] || $existing['envelope'] !== $r['sealedEnvelopeBase64']) {
                    throw new NativeError('crypto_envelope_immutable', 409);
                }
            } else {
                $this->change('INSERT INTO familyhub_crypto_grant_entries_v2 VALUES(?,?,?,?,?,?,?,?,?,?)', array_merge($args, [$r['publicKeyBase64'],$r['sealedEnvelopeBase64'],json_encode($proof, JSON_THROW_ON_ERROR)]));
            }
        }
        if ($old) {
            $this->change('UPDATE familyhub_crypto_grant_states_v2 SET generation=generation+1 WHERE scope_id=? AND head_hash=? AND account_id=? AND domain=? AND epoch=?', $where);
        } else {
            $this->change('INSERT INTO familyhub_crypto_grant_states_v2 VALUES(?,?,?,?,?,?,?,?)', array_merge($where, [$p['keySourceHeadHash'],$p['keyId'],1]));
        }
        return ['scopeId' => $scope['id'],'headHash' => $p['headHash'],'epoch' => $p['epoch'],'generation' => $n + 1];
    }
    private function keySource($candidate, $hash, $epoch, $domain)
    {
        if (!is_int($epoch) || $epoch < 1) {
            throw new NativeError('validation_error');
        }
        $source = $this->head($candidate['scope_id'], $hash);
        if ((int)$source['epoch'] !== $epoch || $epoch > (int)$candidate['epoch'] || $hash !== $candidate['head_hash'] && !in_array($source['state'], ['active','historical'], true)) {
            throw new NativeError('crypto_grant_key_mismatch', 409);
        }$body = $this->body($source);
        if ($body['keyIds'][$domain] === null) {
            throw new NativeError('crypto_grant_key_mismatch', 409);
        }return $body;
    }
    private function keySources($body, $domain)
    {
        $out = [];
        foreach ($this->many("SELECT * FROM familyhub_crypto_scope_heads WHERE scope_id=? AND epoch<? AND state IN ('active','historical') ORDER BY epoch", [$body['scopeId'],$body['epoch']]) as $head) {
            $s = $this->body($head);
            if ($s['keyIds'][$domain] !== null) {
                $out[] = ['headHash' => $head['head_hash'],'epoch' => (int)$head['epoch'],'keyId' => $s['keyIds'][$domain]];
            }
        }
        if ($body['keyIds'][$domain] !== null) {
            $out[] = ['headHash' => hash('sha256', "JivieScopeHead/v2\n".NativeCryptoCodec::canonical((object)$body)),'epoch' => $body['epoch'],'keyId' => $body['keyIds'][$domain]];
        }return $out;
    }
    private function requiredRecipients($member)
    {
        $current = (new NativeCryptoDirectoryV2($this->container))->current($member['accountId']);
        if (!$current || $current['device_snapshot_hash'] !== $member['deviceSnapshotHash']) {
            throw new NativeError('crypto_member_directory_changed', 409);
        }$s = json_decode($current['snapshot'], true, 34, JSON_THROW_ON_ERROR);
        $out = ['recovery:'.$s['recoveryRootEpochId'] => $s['rootEncryptionKeyBase64']];
        foreach ($s['devices'] as $d) {
            if ($d['revokedGeneration'] === null && $d['identityEpochId'] === $s['identityEpochId']) {
                $out['device:'.$d['deviceId']] = $d['encryptionKeyBase64'];
            }
        }ksort($out, SORT_STRING);
        return $out;
    }
    public function grantDomainRoot($body, $domain, $complete)
    {
        $this->domain($domain);
        $hash = hash_init('sha256');
        foreach ($this->grantDescriptors($body, $domain, $complete) as $descriptor) {
            hash_update($hash, NativeCryptoCodec::canonical((object)$descriptor)."\n");
        }
        return hash_final($hash);
    }

    public function grantManifest($body, $complete)
    {
        $roots = [];
        foreach (['content', 'finance'] as $domain) {
            $hash = hash_init('sha256');
            foreach ($this->grantDescriptors($body, $domain, $complete) as $descriptor) {
                hash_update($hash, NativeCryptoCodec::canonical((object)$descriptor)."\n");
            }
            $roots[$domain] = hash_final($hash);
        }
        return $roots;
    }

    private function grantDescriptors($body, $domain, $complete)
    {
        $headHash = hash('sha256', "JivieScopeHead/v2\n".NativeCryptoCodec::canonical((object)$body));
        $sources = $this->keySources($body, $domain);
        foreach ($body['members'] as $member) {
            if ($domain === 'finance' && $member['financeRole'] === 'none') {
                continue;
            }
            foreach ($sources as $source) {
                $args = [$body['scopeId'], $headHash, $member['accountId'], $domain, $source['epoch']];
                $g = $this->one('SELECT * FROM familyhub_crypto_grant_states_v2 WHERE scope_id=? AND head_hash=? AND account_id=? AND domain=? AND epoch=?', $args);
                if (!$g) {
                    if ($complete) {
                        throw new NativeError('crypto_keys_pending', 409);
                    }
                    continue;
                }
                if ($g['key_source_head_hash'] !== $source['headHash'] || $g['key_id'] !== $source['keyId']) {
                    throw new NativeError('crypto_grant_key_mismatch', 409);
                }
                $expected = $complete ? $this->requiredRecipients($member) : null;
                $actual = [];
                $proofHashes = [];
                foreach ($this->many('SELECT * FROM familyhub_crypto_grant_entries_v2 WHERE scope_id=? AND head_hash=? AND account_id=? AND domain=? AND epoch=? ORDER BY recipient_kind,recipient_id', $args) as $r) {
                    $actual[$r['recipient_kind'].':'.$r['recipient_id']] = $r['recipient_key'];
                    $proofHashes[] = NativeCryptoV2Codec::hash((object)json_decode($r['authorization'], true, 34, JSON_THROW_ON_ERROR));
                }
                ksort($actual, SORT_STRING);
                if ($complete && $actual !== $expected) {
                    throw new NativeError('crypto_recipients_incomplete', 409);
                }
                yield ['accountId' => $member['accountId'], 'epoch' => $source['epoch'], 'keyId' => $g['key_id'], 'keySourceHeadHash' => $g['key_source_head_hash'], 'generation' => (int)$g['generation'], 'recipientProofHashes' => $proofHashes];
            }
        }
    }

    private function close($p, $scope, $current, $actor, $proof)
    {
        $this->fields($p, array_merge(['scopeId','candidateHeadHash','domain','epoch','membershipHeadHash','authorDirectoryHeadHash','expectedSequence','recordCount','manifestHash','historyBasis'], ($p['domain'] ?? null) === 'content' ? ['closingLifecycleHash'] : []));
        if (($p['domain'] ?? null) === 'content') {
            $this->digest($p['closingLifecycleHash']);
            if ($p['closingLifecycleHash'] !== (new NativeCryptoLifecycleV2($this->container))->closingHash($scope['id'])) {
                throw new NativeError('crypto_lifecycle_conflict',409);
            }
        }
        if (!in_array($p['historyBasis'], ['verifiedCheckpoint','reviewedRecoveryBaseline'], true)) {
            throw new NativeError('validation_error');
        }$this->domain($p['domain']);
        $this->digest($p['manifestHash']);
        if (!$current || $current['head_hash'] !== $p['membershipHeadHash'] || (int)$current['epoch'] !== $p['epoch']) {
            throw new NativeError('crypto_scope_head_changed', 409);
        }
        $candidate = $this->head($scope['id'], $p['candidateHeadHash']);
        $body = $this->body($candidate);
        if ($p['domain'] === 'content' && $body['previousLifecycleHash'] !== $p['closingLifecycleHash']) {
            throw new NativeError('crypto_lifecycle_conflict',409);
        }
        if ($candidate['state'] !== 'pending' || $candidate['previous_head_hash'] !== $current['head_hash'] || $body['closures'][$p['domain']] !== $p['manifestHash']) {
            throw new NativeError('crypto_closure_candidate_required', 409);
        }
        $member = $this->member($this->body($current), $actor['user']['account_id']);
        if (!$member) {
            throw new NativeError('permission_revoked', 403);
        }if ($p['domain'] === 'finance') {
            (new NativeFinanceAccess($this->container))->policyForCrypto($scope['id'], $actor['user'], false, true);
            if ($member['financeRole'] === 'none') {
                throw new NativeError('finance_forbidden', 403);
            }
        }
        $this->currentAuthorReference($p['authorDirectoryHeadHash'], $actor);
        $sequence = $this->domainSequence($scope['id'], $p['domain']);
        if ($p['expectedSequence'] !== $sequence) {
            throw new NativeError('crypto_closure_changed', 409);
        }
        $hash = hash_init('sha256');
        $count = 0;
        foreach ($this->manifestRows($scope['id'], $p['domain']) as $r) {
            hash_update($hash, NativeCryptoCodec::canonical((object)$r)."\n");
            $count++;
        }
        if ($p['recordCount'] !== $count || !hash_equals($p['manifestHash'], hash_final($hash))) {
            throw new NativeError('crypto_closure_changed', 409);
        }
        $old = $this->one('SELECT manifest_hash FROM familyhub_crypto_closures WHERE scope_id=? AND domain=? AND epoch=? AND candidate_head_hash=? AND manifest_hash=?', [$scope['id'],$p['domain'],$p['epoch'],$p['candidateHeadHash'],$p['manifestHash']]);
        if (!$old) {
            $this->change('INSERT INTO familyhub_crypto_closures VALUES(?,?,?,?,?,?,?,?,?)', [$scope['id'],$p['domain'],$p['epoch'],$p['candidateHeadHash'],$current['head_hash'],$p['expectedSequence'],$p['manifestHash'],'',json_encode($proof, JSON_THROW_ON_ERROR)]);
        }
        // Each immutable descriptor is stored separately to support bounded full-manifest verification.
        if (!$old) {
            foreach ($this->manifestRows($scope['id'], $p['domain']) as $r) {
                $this->change('INSERT INTO familyhub_crypto_closure_records VALUES(?,?,?,?,?,?,?,?,?,?)', [$scope['id'],$p['domain'],$p['epoch'],$p['candidateHeadHash'],$p['manifestHash'],$r['id'],$r['revision'],$r['sequence'],$r['recordEpoch'],$r['recordProofHash']]);
            }
        }
        $this->change('UPDATE familyhub_crypto_scope_state SET '.$p['domain'].'_closed=1 WHERE scope_id=?', [$scope['id']]);
        return ['scopeId' => $scope['id'],'domain' => $p['domain'],'epoch' => $p['epoch'],'manifestHash' => $p['manifestHash'],'recordCount' => $count,'sequence' => $p['expectedSequence']];
    }
    public function domainSequence($sid, $domain)
    {
        $this->domain($domain);
        $row = $this->one('SELECT sequence FROM familyhub_crypto_domain_cursors WHERE scope_id=? AND domain=?', [$sid, $domain]);
        if (!$row) {
            throw new NativeError('crypto_domain_cursor_unavailable', 503);
        }
        return (int)$row['sequence'];
    }

    public function manifestRows($sid, $domain)
    {
        $proofs = new NativeCryptoRecordProofV2($this->container);
        $after = '';
        do {
            // Close the bounded SELECT before yielding: the closure consumer
            // persists each descriptor on the same unbuffered MySQL connection.
            $page = $this->many('SELECT r.id,r.type,r.revision,r.sequence,r.epoch,r.authorization,p.sequence AS domain_sequence,p.domain AS position_domain FROM familyhub_crypto_records r LEFT JOIN familyhub_crypto_record_positions p ON p.scope_id=r.scope_id AND p.id=r.id WHERE r.scope_id=? AND r.id>? ORDER BY r.id LIMIT 20', [$sid,$after]);
            foreach ($page as $r) {
                $after = $r['id'];
                if ($proofs->domain($r['type']) !== $domain) {
                    continue;
                }
                $authorization = json_decode($r['authorization'], true, 34, JSON_THROW_ON_ERROR);
                if (!isset($authorization['recordProof'])) {
                    throw new NativeError('crypto_v1_record_migration_required', 409);
                }
                if ($r['domain_sequence'] === null || $r['position_domain'] !== $domain) {
                    throw new NativeError('crypto_domain_cursor_unavailable', 503);
                }
                yield [
                    'id' => $r['id'],
                    'revision' => (int)$r['revision'],
                    'recordProofHash' => NativeCryptoV2Codec::hash((object)$authorization['recordProof']),
                    'sequence' => (int)$r['domain_sequence'],
                    'recordEpoch' => (int)$r['epoch'],
                ];
            }
        } while (count($page) === 20);
    }
    public function domainHasRecords($sid, $domain)
    {
        $codec = new NativeCryptoRecordProofV2($this->container);
        foreach ($this->iterate('SELECT type FROM familyhub_crypto_records WHERE scope_id=?', [$sid]) as $row) {
            if ($codec->domain($row['type']) === $domain) {
                return true;
            }
        }return false;
    }
    private function closuresReady($current, $next)
    {
        if (!$current) {
            return;
        }
        foreach (['content','finance'] as $domain) {
            $hash = $next['closures'][$domain];
            if ($hash === null) {
                if ($domain === 'finance' && $this->body($current)['keyIds']['finance'] === null && !$this->domainHasRecords($next['scopeId'], 'finance')) {
                    continue;
                }throw new NativeError('crypto_closure_required', 409);
            }$c = $this->one('SELECT * FROM familyhub_crypto_closures WHERE scope_id=? AND domain=? AND epoch=? AND candidate_head_hash=? AND manifest_hash=?', [$next['scopeId'],$domain,$current['epoch'],hash('sha256', "JivieScopeHead/v2\n".NativeCryptoCodec::canonical((object)$next)),$hash]);
            if ($c && $domain === 'content') {
                [$closed]=NativeCryptoCodec::decode(json_decode($c['authorization'],true,34,JSON_THROW_ON_ERROR));
                if (($closed['payload']['closingLifecycleHash'] ?? null) !== $next['previousLifecycleHash'] || $next['previousLifecycleHash'] !== (new NativeCryptoLifecycleV2($this->container))->closingHash($next['scopeId'])) {
                    throw new NativeError('crypto_lifecycle_conflict',409);
                }
            }
            if (!$c || $c['head_hash'] !== $current['head_hash'] || (int)$c['sequence'] !== $this->domainSequence($next['scopeId'], $domain)) {
                throw new NativeError('crypto_closure_changed', 409);
            }
        }
    }
    private function authorizeRead($sid, $p, $actor)
    {
        if (isset($p['pendingCapability'])) {
            $this->pendingRead = (new NativeCryptoInvitationV2($this->container, $this->bearer, $this->ip))->capability($sid, $p['pendingCapability'], $actor);
            return;
        }
        $this->scope($sid, $actor['user']['id']);
    }

    private function pendingHead($head)
    {
        if (!$this->pendingRead) {
            return;
        }
        $candidate = $this->pendingRead['candidate'];
        if ($head['head_hash'] === $candidate['head_hash']) {
            return;
        }
        if (!in_array($head['state'], ['active','historical'], true) || (int)$head['epoch'] >= (int)$candidate['epoch']) {
            throw new NativeError('permission_revoked', 403);
        }
        // Only the exact signed predecessor chain is promised by this invitation.
        $cursor = $candidate;
        while ((int)$cursor['epoch'] > (int)$head['epoch']) {
            $parent = $this->head($candidate['scope_id'], $cursor['previous_head_hash']);
            if ((int)$parent['epoch'] !== (int)$cursor['epoch'] - 1 || !in_array($parent['state'], ['active','historical'], true)) {
                throw new NativeError('crypto_scope_chain_unavailable', 503);
            }
            $cursor = $parent;
        }
        if ($cursor['head_hash'] !== $head['head_hash']) {
            throw new NativeError('permission_revoked', 403);
        }
    }

    public function read($op, $p, $actor)
    {
        $sid = $this->uuid($p['scopeId'] ?? null);
        $this->authorizeRead($sid, $p, $actor);
        $current = $this->current($sid);
        if ($op === 'crypto2.scope.headGet') {
            $this->fields($p, ['scopeId'], ['headHash','pendingCapability']);
            $head = isset($p['headHash']) ? $this->head($sid, $p['headHash']) : $current;
            if (!$head) {
                throw new NativeError('crypto_scope_head_missing', 404);
            }
            $this->requireParticipant($head, $current, $actor);
            $financeManifest = $this->one('SELECT authorization FROM familyhub_crypto_finance_manifests WHERE scope_id=? AND head_hash=?', [$sid, $head['head_hash']]);
            $ownerAcceptance = $this->one('SELECT authorization FROM familyhub_crypto_owner_acceptances WHERE scope_id=? AND head_hash=?', [$sid, $head['head_hash']]);
            $contentManifest = $this->one('SELECT authorization FROM familyhub_crypto_content_manifests WHERE scope_id=? AND head_hash=?', [$sid, $head['head_hash']]);
            return (new NativeCryptoLifecycleV2($this->container))->initialBaseline($sid) + ['ownerAcceptanceProof' => $ownerAcceptance ? json_decode($ownerAcceptance['authorization'], true, 34, JSON_THROW_ON_ERROR) : null, 'contentGrantManifestProof' => $contentManifest ? json_decode($contentManifest['authorization'], true, 34, JSON_THROW_ON_ERROR) : null, 'financeGrantManifestProof' => $financeManifest ? json_decode($financeManifest['authorization'], true, 34, JSON_THROW_ON_ERROR) : null, 'scopeId' => $sid, 'headHash' => $head['head_hash'], 'state' => $head['state'], 'payload' => $this->body($head), 'authorization' => json_decode($head['authorization'], true, 34, JSON_THROW_ON_ERROR), 'activationAuthorization' => $head['activation_authorization'] ? json_decode($head['activation_authorization'], true, 34, JSON_THROW_ON_ERROR) : null];
        }
        if ($op === 'crypto2.grants.manifest') {
            $this->fields($p, ['scopeId', 'headHash'], ['domain', 'afterAccountId', 'afterEpoch', 'limit','pendingCapability']);
            $head = $this->head($sid, $p['headHash']);
            if ($this->pendingRead && $head['head_hash'] !== $this->pendingRead['candidate']['head_hash']) {
                throw new NativeError('permission_revoked', 403);
            }
            $member = $this->requireParticipant($head, $current, $actor);
            $body = $this->body($head);
            $roots = $this->grantManifest($body, false);
            $out = ['scopeId' => $sid, 'headHash' => $p['headHash'], 'domains' => $roots, 'grantManifestHash' => NativeCryptoV2Codec::hash((object)$roots)];
            if (!isset($p['domain'])) {
                return $out;
            }
            $domain = $p['domain'];
            $this->domain($domain);
            $this->readDomain($sid, $domain, $member, $actor, $head, $current);
            $after = isset($p['afterAccountId']) ? $this->uuid($p['afterAccountId']) : '';
            $afterEpoch = $p['afterEpoch'] ?? 0;
            $limit = $p['limit'] ?? 50;
            if (!is_int($afterEpoch) || $afterEpoch < 0 || !is_int($limit) || $limit < 1 || $limit > 50) {
                throw new NativeError('invalid_cursor');
            }
            $page = [];
            $more = false;
            foreach ($this->grantDescriptors($body, $domain, false) as $descriptor) {
                if (strcmp($descriptor['accountId'], $after) < 0 || $descriptor['accountId'] === $after && $descriptor['epoch'] <= $afterEpoch) {
                    continue;
                }
                if (count($page) === $limit) {
                    $more = true;
                    break;
                }
                $page[] = $descriptor;
            }
            $last = $page ? end($page) : null;
            return $out + ['descriptors' => $page, 'hasMore' => $more, 'nextAccountId' => $last['accountId'] ?? null, 'nextEpoch' => $last['epoch'] ?? null];
        }
        if ($op === 'crypto2.grants.list') {
            $this->fields($p, ['scopeId', 'headHash', 'domain'], ['epoch', 'afterEpoch','pendingCapability']);
            $this->domain($p['domain']);
            $head = $this->head($sid, $p['headHash']);
            if ($this->pendingRead && $head['head_hash'] !== $this->pendingRead['candidate']['head_hash']) {
                throw new NativeError('permission_revoked', 403);
            }
            $member = $this->requireParticipant($head, $current, $actor);
            $this->readDomain($sid, $p['domain'], $member, $actor, $head, $current);
            $args = [$sid, $p['headHash'], $actor['user']['account_id'], $p['domain']];
            $sql = 'SELECT * FROM familyhub_crypto_grant_states_v2 WHERE scope_id=? AND head_hash=? AND account_id=? AND domain=?';
            if (isset($p['epoch'])) {
                if (!is_int($p['epoch']) || $p['epoch'] < 1) {
                    throw new NativeError('validation_error');
                }
                $sql .= ' AND epoch=?';
                $args[] = $p['epoch'];
            }
            $after = $p['afterEpoch'] ?? 0;
            if (!is_int($after) || $after < 0) {
                throw new NativeError('invalid_cursor');
            }
            $sql .= ' AND epoch>?';
            $args[] = $after;
            $states = $this->many($sql.' ORDER BY epoch LIMIT 2', $args);
            $groups = [];
            foreach (array_slice($states, 0, 1) as $state) {
                $recipients = [];
                $authorizations = [];
                foreach ($this->many('SELECT * FROM familyhub_crypto_grant_entries_v2 WHERE scope_id=? AND head_hash=? AND account_id=? AND domain=? AND epoch=? ORDER BY recipient_kind,recipient_id', array_merge(array_slice($args, 0, 4), [(int)$state['epoch']])) as $row) {
                    $proof = json_decode($row['authorization'], true, 34, JSON_THROW_ON_ERROR);
                    $hash = NativeCryptoV2Codec::hash((object)$proof);
                    $authorizations[$hash] = $proof;
                    $recipients[] = ['recipientKind' => $row['recipient_kind'], 'recipientId' => $row['recipient_id'], 'publicKeyBase64' => $row['recipient_key'], 'sealedEnvelopeBase64' => $row['envelope'], 'authorizationId' => $hash];
                }
                $groups[] = ['scopeId' => $sid, 'headHash' => $state['head_hash'], 'keySourceHeadHash' => $state['key_source_head_hash'], 'epoch' => (int)$state['epoch'], 'domain' => $state['domain'], 'keyId' => $state['key_id'], 'generation' => (int)$state['generation'], 'recipients' => $recipients, 'authorizations' => (object)$authorizations];
            }
            return ['grants' => $groups, 'hasMore' => count($states) > 1, 'nextEpoch' => $groups ? end($groups)['epoch'] : $after];
        }
        if ($op === 'crypto2.scope.closureGet') {
            $this->fields($p, ['scopeId', 'candidateHeadHash', 'domain', 'epoch', 'manifestHash'], ['afterId', 'limit','pendingCapability']);
            $this->domain($p['domain']);
            if (!$current) {
                throw new NativeError('crypto_scope_head_missing', 404);
            }
            $member = $this->requireParticipant($current, $current, $actor);
            $this->readDomain($sid, $p['domain'], $member, $actor);
            $this->digest($p['manifestHash']);
            $candidate = $this->head($sid, $p['candidateHeadHash']);
            $this->pendingHead($candidate);
            $after = isset($p['afterId']) ? NativeCryptoRecordAddressV2::wireId($p['afterId']) : '';
            $limit = $p['limit'] ?? 50;
            if (!is_int($p['epoch']) || $p['epoch'] < 1 || !is_int($limit) || $limit < 1 || $limit > 50) {
                throw new NativeError('invalid_cursor');
            }
            $where = [$sid, $p['domain'], $p['epoch'], $candidate['head_hash'], $p['manifestHash']];
            $closure = $this->one('SELECT * FROM familyhub_crypto_closures WHERE scope_id=? AND domain=? AND epoch=? AND candidate_head_hash=? AND manifest_hash=?', $where);
            if (!$closure) {
                throw new NativeError('crypto_closure_missing', 404);
            }
            $authorization = json_decode($closure['authorization'], true, 34, JSON_THROW_ON_ERROR);
            [$command] = NativeCryptoCodec::decode($authorization);
            $rows = $this->many('SELECT * FROM familyhub_crypto_closure_records WHERE scope_id=? AND domain=? AND epoch=? AND candidate_head_hash=? AND manifest_hash=? AND id>? ORDER BY id LIMIT '.($limit + 1), array_merge($where, [$after]));
            $descriptors = [];
            foreach (array_slice($rows, 0, $limit) as $row) {
                $descriptors[] = ['id' => $row['id'], 'revision' => (int)$row['revision'], 'recordProofHash' => $row['record_proof_hash'], 'sequence' => (int)$row['sequence'], 'recordEpoch' => (int)$row['record_epoch']];
            }
            return ['scopeId' => $sid, 'candidateHeadHash' => $candidate['head_hash'], 'domain' => $p['domain'], 'epoch' => $p['epoch'], 'manifestHash' => $closure['manifest_hash'], 'recordCount' => $command['payload']['recordCount'], 'sequence' => (int)$closure['sequence'], 'historyBasis' => $command['payload']['historyBasis'], 'descriptors' => $descriptors, 'authorization' => $authorization, 'hasMore' => count($rows) > count($descriptors), 'nextAfterId' => $descriptors ? end($descriptors)['id'] : null];
        }
        throw new NativeError('unsupported_operation', 404);
    }

    /** Preserve every effective legacy reader, including policy2 organizational leaders. */
    public function effectiveMembers($sid)
    {
        $access = new NativeOrganizationAccess($this->container);
        $members = [];
        foreach ($access->members($sid) as $member) {
            $members[$member['accountId']] = $member;
        }
        $scope = $this->one('SELECT * FROM familyhub_scopes WHERE id=?', [$sid]);
        $parent = $scope['parent_scope_id'] ?? $scope['organization_id'] ?? null;
        if ($parent) {
            $rows = $this->many("SELECT m.account_id,m.user_id FROM familyhub_members m JOIN familyhub_scopes p ON p.id=m.scope_id LEFT JOIN familyhub_organization_leaders l ON l.scope_id=p.id AND l.account_id=m.account_id JOIN users u ON u.id=m.user_id JOIN familyhub_accounts a ON a.user_id=m.user_id AND a.account_id=m.account_id WHERE m.scope_id=? AND p.kind='organization' AND p.access_policy_version=2 AND m.active=1 AND u.is_active=1 AND (m.role='owner' OR l.account_id IS NOT NULL) ORDER BY m.account_id", [$parent]);
            foreach ($rows as $row) {
                $effective = $access->visibleScope($sid, $row['account_id']);
                if ($effective && !isset($members[$row['account_id']])) {
                    $members[$row['account_id']] = ['accountId' => $row['account_id'], 'userId' => (int)$row['user_id'], 'role' => $effective['role']];
                }
            }
        }
        ksort($members, SORT_STRING);
        return array_values($members);
    }

    /** Metadata-only discovery; names and all content remain in the encrypted projection. */
    public function catalog($p, $actor)
    {
        $this->fields($p, [], ['afterId', 'limit']);
        $after = isset($p['afterId']) ? NativeCryptoRecordAddressV2::wireId($p['afterId']) : '';
        $limit = $p['limit'] ?? 50;
        if (!is_int($limit) || $limit < 1 || $limit > 50) {
            throw new NativeError('invalid_cursor');
        }
        $access = new NativeOrganizationAccess($this->container);
        $account = $actor['user']['account_id'];
        $rows = $this->many('SELECT s.id FROM familyhub_scopes s WHERE s.id>? AND s.deleted_at IS NULL AND (EXISTS (SELECT 1 FROM familyhub_members m WHERE m.scope_id=s.id AND m.account_id=? AND m.user_id=? AND m.active=1) OR EXISTS (SELECT 1 FROM familyhub_members m JOIN familyhub_scopes parent ON parent.id=m.scope_id LEFT JOIN familyhub_organization_leaders leader ON leader.scope_id=parent.id AND leader.account_id=m.account_id WHERE (parent.id=s.parent_scope_id OR parent.id=s.organization_id) AND m.account_id=? AND m.user_id=? AND m.active=1 AND (parent.access_policy_version=3 OR (parent.access_policy_version=2 AND (m.role=\'owner\' OR leader.account_id IS NOT NULL))))) ORDER BY s.id LIMIT '.($limit + 1), [$after, $account, $actor['user']['id'], $account, $actor['user']['id']]);
        $out = [];
        $bytes = 0;
        foreach (array_slice($rows, 0, $limit) as $row) {
            $descriptor = $this->catalogScope($row['id'], $actor);
            $size = strlen(json_encode($descriptor, JSON_THROW_ON_ERROR));
            if ($out && $bytes + $size > 1250000) {
                break;
            }
            $out[] = $descriptor;
            $bytes += $size;
        }
        return ['scopes' => $out, 'hasMore' => count($rows) > count($out), 'nextAfterId' => $out ? end($out)['id'] : null];
    }

    public function catalogScope($sid, $actor)
    {
        $access = new NativeOrganizationAccess($this->container);
        $account = $actor['user']['account_id'];
        $scope = $this->scope($sid, $actor['user']['id']);
        $parent = $scope['parent_scope_id'] ?? $scope['organization_id'] ?? null;
        if ($parent && !$access->visibleScope($parent, $account)) {
            $parent = null;
        }
        $members = [];
        foreach ($this->effectiveMembers($sid) as $m) {
            $user = $this->one('SELECT a.account_id,u.* FROM familyhub_accounts a JOIN users u ON u.id=a.user_id WHERE a.account_id=?', [$m['accountId']]);
            $policy = (new NativeFinanceAccess($this->container))->policyForCrypto($sid, $user, false, false);
            $memberDirectory = (new NativeCryptoDirectoryV2($this->container))->current($m['accountId']);
            $members[] = ['deviceSnapshotHash' => $memberDirectory['device_snapshot_hash'] ?? null, 'accountId' => $m['accountId'], 'role' => $m['role'], 'financeRole' => $policy['enabled'] ? $policy['grant'] : 'none', 'manageKeys' => $m['role'] === 'owner' || (int)$scope['effective_access_policy_version'] === 3 && $m['role'] === 'member'];
        }
        $head = $this->current($sid);
        $crypto = $this->one('SELECT state,migration_id FROM familyhub_crypto_scopes WHERE scope_id=?', [$sid]);
        $migration = !empty($crypto['migration_id']) ? $this->one('SELECT state FROM familyhub_crypto_migrations_v2 WHERE id=?', [$crypto['migration_id']]) : null;
        $origin = $this->one('SELECT scope_id FROM familyhub_crypto_scope_origins WHERE scope_id=?', [$sid]);
        return ['cryptoOrigin' => (bool)$origin, 'migrationId' => $crypto['migration_id'] ?? null, 'migrationState' => $migration['state'] ?? null, 'expectedAccessRevision' => (int)$scope['effective_access_revision'], 'accessBasis' => $this->accessBasis($scope), 'cryptoState' => $crypto['state'] ?? 'legacy', 'headHash' => $head['head_hash'] ?? null, 'epoch' => $head ? (int)$head['epoch'] : 0, 'id' => $sid, 'kind' => $scope['kind'], 'parentScopeId' => $parent, 'role' => $scope['role'], 'accessRevision' => (int)$scope['effective_access_revision'], 'members' => $members];
    }

    public function protectionCatalog($actor)
    {
        $hash = hash_init('sha256');
        hash_update($hash, "JivieProtectionCatalog/v2\n");
        $count = 0;
        $after = null;
        do {
            $page = $this->catalog($after === null ? ['limit' => 50] : ['limit' => 50,'afterId' => $after], $actor);
            foreach ($page['scopes'] as $descriptor) {
                hash_update($hash, NativeCryptoCodec::canonical((object)$descriptor)."\n");
                $count++;
            }
            $after = $page['nextAfterId'];
        } while ($page['hasMore']);
        hash_update($hash, NativeCryptoCodec::canonical((object)['count' => $count]));
        return ['scopeManifestHash' => hash_final($hash),'count' => $count];
    }

    /** Cross-account prefix access is scope-local, never a global public-key directory. */
    public function directoryRead($op, $p, $actor)
    {
        $this->fields($p, ['scopeId', 'accountId'], ['headHash', 'directoryHeadHash', 'afterGeneration', 'limit','pendingCapability']);
        $sid = $this->uuid($p['scopeId']);
        $target = $this->uuid($p['accountId']);
        $this->authorizeRead($sid, $p, $actor);
        $active = $this->current($sid);
        if (($p['headHash'] ?? null) === NativeCryptoDirectoryV2::ZERO && $active) {
            throw new NativeError('crypto_scope_head_conflict',409);
        }
        $head = isset($p['headHash']) && $p['headHash'] !== NativeCryptoDirectoryV2::ZERO ? $this->head($sid, $p['headHash']) : ($this->pendingRead['candidate'] ?? $active);
        if (!$head) {
            $access = new NativeOrganizationAccess($this->container);
            if (!$access->visibleScope($sid, $target)) {
                throw new NativeError('permission_revoked', 403);
            }
        } else {
            $this->requireParticipant($head, $active, $actor);
        }
        $body = $head ? $this->body($head) : ['members' => []];
        $member = $this->member($body, $target);
        $activeMember = $active ? $this->member($this->body($active), $target) : null;
        $references = [];
        if ($member) {
            $references[] = $member['directoryHeadHash'];
        }
        $author = $head ? json_decode($head['authorization'], true, 34, JSON_THROW_ON_ERROR) : null;
        $authorCommand = $author ? NativeCryptoCodec::decode($author)[0] : null;
        if ($authorCommand && $authorCommand['accountId'] === $target) {
            $references[] = $body['authorDirectoryHeadHash'];
        }
        foreach ($this->many('SELECT authorization FROM familyhub_crypto_closures WHERE scope_id=? AND candidate_head_hash=?', [$sid, $head['head_hash'] ?? NativeCryptoDirectoryV2::ZERO]) as $row) {
            [$c] = NativeCryptoCodec::decode(json_decode($row['authorization'], true, 34, JSON_THROW_ON_ERROR));
            if ($c['accountId'] === $target) {
                $references[] = $c['payload']['authorDirectoryHeadHash'];
            }
        }
        // A policy1/2 parent manager need not be a child member. A child
        // reader may verify only the exact signer prefixes named by its own
        // delegation or inherited lifecycle proof, never a parent directory.
        foreach ($this->many('SELECT authorization FROM familyhub_crypto_lifecycle_delegations_v2 WHERE scope_id=? AND head_hash=? AND parent_account_id=?', [$sid,$head['head_hash'] ?? NativeCryptoDirectoryV2::ZERO,$target]) as $row) {
            [$delegation] = NativeCryptoCodec::decode(json_decode($row['authorization'],true,34,JSON_THROW_ON_ERROR));
            $references[] = $delegation['payload']['parentDirectoryHeadHash'];
        }
        $afterLifecycle = 0;
        do {
            $proofs = $this->many('SELECT revision,authorization FROM familyhub_crypto_lifecycle_log_v2 WHERE scope_id=? AND membership_head_hash=? AND revision>? ORDER BY revision LIMIT 50', [$sid,$head['head_hash'] ?? NativeCryptoDirectoryV2::ZERO,$afterLifecycle]);
            foreach ($proofs as $row) {
                $afterLifecycle = (int)$row['revision'];
                [$observation] = NativeCryptoCodec::decode(json_decode($row['authorization'],true,34,JSON_THROW_ON_ERROR));
                if (($observation['operation'] ?? null) === 'crypto2.scope.archive') {
                    $action=$this->one('SELECT authorization FROM familyhub_crypto_lifecycle_actions_v2 WHERE scope_id=? AND id=?',[$sid,$observation['payload']['parentActionId']]);
                    if (!$action) { throw new NativeError('crypto_lifecycle_log_unavailable',503); }
                    [$observation]=NativeCryptoCodec::decode(json_decode($action['authorization'],true,34,JSON_THROW_ON_ERROR));
                }
                $reference=$observation['payload']['authorDirectoryHeadHash'] ?? $observation['authorDirectoryHeadHash'] ?? null;
                if ($observation['accountId'] === $target && ($p['directoryHeadHash'] ?? null) === $reference) {
                    $references[] = $reference;
                    break 2;
                }
            }
        } while (count($proofs) === 50);
        $baselineRow=$this->one('SELECT scope_id FROM familyhub_crypto_lifecycle_baselines_v2 WHERE scope_id=?',[$sid]);
        if ($baselineRow || $head) {
            $initial=(new NativeCryptoLifecycleV2($this->container))->initialBaseline($sid);
            [$origin]=NativeCryptoCodec::decode($initial['originAuthorization']);
            if ($origin['accountId'] === $target) {
                $references[]=$initial['originAuthorDirectoryHeadHash'];
            }
        }
        if ($head) {
            $reader = $this->member($body,$actor['user']['account_id']);
            if ($reader && $reader['manageKeys']) {
                $pendingReference=(new NativeCryptoLifecycleV2($this->container,$this->bearer,$this->ip))->pendingDirectoryReference($sid,$target,$actor);
                if ($pendingReference !== null) {
                    $references[]=$pendingReference;
                }
            }
        }
        if ($head) {
            $exportReference=(new NativeCryptoExportV2($this->container,$this->bearer,$this->ip))->directoryReference($sid,$head['head_hash'],$target,$actor);
            if ($exportReference!==null) {
                $references[]=$exportReference;
            }
        }
        if ($head && ($reader=$this->member($body,$actor['user']['account_id'])) && $reader['manageKeys']) {
            $accessReference=(new NativeCryptoAccessV2($this->container,$this->bearer,$this->ip))->directoryReference($sid,$target,$actor);
            if ($accessReference!==null) {
                $references[]=$accessReference;
            }
        }
        if ($head) {
            $contextReferences=(new NativeCryptoMigrationStructureContextV3($this->container,$this->bearer,$this->ip))
                ->directoryReferences($sid,$head['head_hash'],$target);
            if ($contextReferences) {
                $references=array_merge($references,$contextReferences);
            }
            $references=array_merge($references,
                (new NativeCryptoProjectRelocationPublicationV2($this->container,$this->bearer,$this->ip))
                    ->directoryReferences($sid,$head['head_hash'],$target),
                (new NativeCryptoMigrationAuditReadV3($this->container,$this->bearer,$this->ip))
                    ->directoryReferences($sid,$head['head_hash'],$target,$actor),
                (new NativeCryptoMigrationNotificationReadV3($this->container,$this->bearer,$this->ip))
                    ->directoryReferences($sid,$head['head_hash'],$target),
                (new NativeCryptoProjectRelocationNotificationsV2($this->container,$this->bearer,$this->ip))
                    ->directoryReferences($sid,$head['head_hash'],$target));
            $inlineReferences=(new NativeCryptoInlineDeletionV2($this->container,$this->bearer,$this->ip))
                ->directoryReferences($sid,$head['head_hash'],$target);
            if ($inlineReferences) {
                $references=array_merge($references,$inlineReferences);
            }
        }
        // A scoped issuer is not a current member. Its delegation permits only
        // named signer/anchor prefixes, never an arbitrary newer account log.
        $currentParticipant = !$head || $activeMember || $member && $head['state'] === 'pending';
        if (!$references && !$currentParticipant) {
            throw new NativeError('permission_revoked', 403);
        }
        $directory = new NativeCryptoDirectoryV2($this->container);
        $current = $directory->current($target);
        if (!$current) {
            throw new NativeError('crypto_member_directory_pending', 409);
        }
        $hash = $p['directoryHeadHash'] ?? null;
        if ($hash === null) {
            if ($currentParticipant) {
                $hash=$current['head_hash'];
            } else {
                // No selector chooses the latest *referenced* prefix only.
                $generation=-1;
                foreach (array_unique($references) as $reference) {
                    $entry=$this->one('SELECT generation FROM familyhub_crypto_directory WHERE account_id=? AND head_hash=?',[$target,$reference]);
                    if ($entry && (int)$entry['generation']>$generation) {
                        $hash=$reference;$generation=(int)$entry['generation'];
                    }
                }
            }
        }
        $this->digest($hash);
        if (!$currentParticipant && !in_array($hash, $references, true)) {
            throw new NativeError('permission_revoked', 403);
        }
        $targetHead = $this->one('SELECT generation,head_hash,snapshot_hash,device_snapshot_hash,identity_epoch_id FROM familyhub_crypto_directory WHERE account_id=? AND head_hash=?', [$target, $hash]);
        if (!$targetHead) {
            throw new NativeError('crypto_directory_head_missing', 404);
        }
        $out = ['serverId' => $this->serverId(), 'accountId' => $target, 'generation' => (int)$targetHead['generation'], 'headHash' => $targetHead['head_hash'], 'snapshotHash' => $targetHead['snapshot_hash'], 'deviceSnapshotHash' => $targetHead['device_snapshot_hash'], 'identityEpochId' => $targetHead['identity_epoch_id']];
        if ($op === 'crypto2.directory.status') {
            return $out;
        }
        $after = $p['afterGeneration'] ?? 0;
        $limit = $p['limit'] ?? 50;
        if (!is_int($after) || $after < 0 || $after > $out['generation'] || !is_int($limit) || $limit < 1 || $limit > 50) {
            throw new NativeError('invalid_cursor');
        }
        $rows = $this->many('SELECT generation,head_hash,previous_head_hash,command_hash,authorization FROM familyhub_crypto_directory WHERE account_id=? AND generation>? AND generation<=? ORDER BY generation LIMIT '.($limit + 1), [$target, $after, $out['generation']]);
        $entries = [];
        $bytes = 0;
        foreach ($rows as $row) {
            $entry = ['generation' => (int)$row['generation'], 'headHash' => $row['head_hash'], 'previousHeadHash' => $row['previous_head_hash'], 'commandHash' => $row['command_hash'], 'authorization' => json_decode($row['authorization'], true, 34, JSON_THROW_ON_ERROR)];
            $size = strlen(json_encode($entry, JSON_THROW_ON_ERROR));
            if (count($entries) === $limit || $entries && $bytes + $size > 1250000) {
                break;
            }
            $entries[] = $entry;
            $bytes += $size;
        }
        return $out + ['entries' => $entries, 'hasMore' => count($rows) > count($entries), 'nextGeneration' => $entries ? end($entries)['generation'] : $after];
    }

    /** Candidate authority expires, but an immutable old-epoch closure never reopens. */
    public function refreshPending($sid, $current)
    {
        foreach ($this->many("SELECT * FROM familyhub_crypto_scope_heads WHERE scope_id=? AND state='pending'", [$sid]) as $candidate) {
            $proof = json_decode($candidate['authorization'], true, 34, JSON_THROW_ON_ERROR);
            [$command] = NativeCryptoCodec::decode($proof);
            $receipt = $this->one('SELECT created_at,status,authorization FROM familyhub_crypto_receipts WHERE account_id=? AND request_id=?', [$command['accountId'], $command['requestId']]);
            $shadow=$this->relocationContext;
            if($shadow&&$shadow['scopeId']===$sid){
                $body=$this->body($candidate);
                if((int)$candidate['epoch']!==1||$candidate['previous_head_hash']!==NativeCryptoDirectoryV2::ZERO||$shadow['headAuthorization']===null||NativeCryptoCodec::canonical((object)$proof)!==$shadow['headAuthorization']||(int)$shadow['expiresAt']<=time()){
                    throw new NativeError('crypto_scope_candidate_unavailable',503);
                }
                // This exact nested head was accepted only by the private
                // shadow stage. It has no normal receipt or standalone route.
                // Its signed initialLifecycleHash binds the marked origin.
                continue;
            }
            if (!$receipt || (int)$receipt['status'] !== 200 || json_decode($receipt['authorization'], true, 34, JSON_THROW_ON_ERROR) !== $proof) {
                throw new NativeError('crypto_scope_candidate_unavailable', 503);
            }
            $keyExpiry = (new NativeCryptoKeyContributionV2($this->container))->expiresAt($this->body($candidate));
            $financeExpiry = (new NativeCryptoFinanceContributionV2($this->container))->expiresAt($this->body($candidate));
            $policyExpiry = (new NativeCryptoFinancePolicyV2($this->container))->expiresAt($this->body($candidate));
            $accessExpiry=(new NativeCryptoAccessV2($this->container))->expiresAt($this->body($candidate));
            if ($accessExpiry!==null) { $financeExpiry=$financeExpiry===null?$accessExpiry:min($financeExpiry,$accessExpiry); }
            if ($policyExpiry !== null) {
                $financeExpiry = $financeExpiry === null ? $policyExpiry : min($financeExpiry, $policyExpiry);
            }
            if ($keyExpiry !== null) {
                $financeExpiry = $financeExpiry === null ? $keyExpiry : min($keyExpiry, $financeExpiry);
            }
            if ((int)$receipt['created_at'] + 1800 <= time() || $financeExpiry !== null && $financeExpiry <= time()) {
                $this->change("UPDATE familyhub_crypto_scope_heads SET state='expired' WHERE scope_id=? AND head_hash=? AND state='pending'", [$sid, $candidate['head_hash']]);
            }
        }
        if (!$current) {
            return;
        }
        foreach (['content', 'finance'] as $domain) {
            $closed = $this->one('SELECT manifest_hash FROM familyhub_crypto_closures WHERE scope_id=? AND domain=? AND head_hash=? LIMIT 1', [$sid,$domain,$current['head_hash']]);
            $this->change('UPDATE familyhub_crypto_scope_state SET '.$domain.'_closed=? WHERE scope_id=?', [$closed ? 1 : 0, $sid]);
        }
    }

    public function closedDomains($sid, $headHash)
    {
        if ($headHash===null) {return [];}
        $out=[];
        foreach(['content','finance'] as $domain) {
            if ($this->one('SELECT manifest_hash FROM familyhub_crypto_closures WHERE scope_id=? AND domain=? AND head_hash=? LIMIT 1',[$sid,$domain,$headHash])) {$out[]=$domain;}
        }
        return $out;
    }

    public function currentAuthorReference($hash, $actor)
    {
        $this->digest($hash);
        if(NativeCryptoMigrationGenerationV3::retainedReference($this->pdo,$actor['user']['account_id'],$hash,$actor['device']['id']))return;
        $directory = new NativeCryptoDirectoryV2($this->container);
        $current = $directory->current($actor['user']['account_id']);
        $ref = $this->one('SELECT device_snapshot_hash FROM familyhub_crypto_directory WHERE account_id=? AND head_hash=?', [$actor['user']['account_id'], $hash]);
        if (!$current || !$ref || $ref['device_snapshot_hash'] !== $current['device_snapshot_hash']) {
            throw new NativeError('crypto_member_directory_changed', 409);
        }
        $snapshot = json_decode($current['snapshot'], true, 34, JSON_THROW_ON_ERROR);
        $device = $directory->device($snapshot, $actor['device']['id']);
        if (!$device || $device['revokedGeneration'] !== null || $device['identityEpochId'] !== $snapshot['identityEpochId']) {
            throw new NativeError('crypto_device_unapproved', 403);
        }
    }

    private function requireParticipant($head, $current, $actor)
    {
        if ($this->pendingRead) {
            $this->pendingHead($head);
            return $this->pendingRead['member'];
        }
        $member = $this->member($this->body($head), $actor['user']['account_id']);
        if (!$member && $current) {
            $member = $this->member($this->body($current), $actor['user']['account_id']);
        }
        if (!$member) {
            throw new NativeError('crypto_keys_pending', 403);
        }
        return $member;
    }

    private function readDomain($sid, $domain, $member, $actor, $candidate = null, $source = null)
    {
        if ($domain === 'finance') {
            if ($member['financeRole'] === 'none') {
                throw new NativeError('finance_forbidden', 403);
            }
            if (!$this->pendingRead) {
                if ($candidate && $candidate['state'] === 'pending') {
                    (new NativeCryptoFinancePolicyV2($this->container, $this->bearer, $this->ip))->financeRead($this->body($candidate), $source, $actor['user']);
                } else {
                    (new NativeFinanceAccess($this->container))->policyForCrypto($sid, $actor['user'], false, true);
                }
            }
        }
    }

    private function domain($d)
    {
        if (!in_array($d, ['content','finance'], true)) {
            throw new NativeError('validation_error');
        }
    }
}
