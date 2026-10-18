<?php

namespace Kanboard\Plugin\FamilyHub\Model;

/** Signed own/inherited archive state. A SQL flag never replaces its proof log. */
class NativeCryptoLifecycleV2 extends NativeDatabase
{
    protected $cryptoAccess = true;
    public const ZERO = NativeCryptoDirectoryV2::ZERO;
    public const OBSERVATION_DOMAIN = "JivieE2EE/inheritedLifecycle/v2\n";

    public static function proofHash($proof)
    {
        return hash('sha256', "JivieScopeLifecycle/v2\n".NativeCryptoCodec::canonical((object)$proof));
    }

    public function parentToken($scopeId, $parentScopeId)
    {
        return hash('sha256', "JivieParentLifecycleScope/v2\n".NativeCryptoCodec::canonical((object)['version'=>2,'serverId'=>$this->serverId(),'scopeId'=>$scopeId,'parentScopeId'=>$parentScopeId]));
    }

    public function captureBaseline($scopeId, $kind, $proof)
    {
        $scope = $this->one('SELECT archived,parent_scope_id,organization_id FROM familyhub_scopes WHERE id=?', [$scopeId]);
        if (!$scope || !in_array($kind,['new','legacy'],true)) {
            throw new NativeError('crypto_lifecycle_baseline_required',409);
        }
        $parentId = $scope['parent_scope_id'] ?? $scope['organization_id'];
        $parent = $parentId ? $this->one('SELECT archived FROM familyhub_scopes WHERE id=?', [$parentId]) : null;
        $baseline = ['version'=>2,'scopeId'=>$scopeId,'originKind'=>$kind,'originProofHash'=>hash('sha256',NativeCryptoCodec::canonical((object)$proof)),'ownArchived'=>(bool)$scope['archived'],'inheritedArchived'=>(bool)($parent['archived'] ?? false)];
        if ($kind === 'new' && ($baseline['ownArchived'] || $baseline['inheritedArchived'])) {
            throw new NativeError('crypto_lifecycle_baseline_required',409);
        }
        [$originCommand] = NativeCryptoCodec::decode($proof);
        $originDirectory = (new NativeCryptoDirectoryV2($this->container))->current($originCommand['accountId']);
        if (!$originDirectory) { throw new NativeError('crypto_directory_missing',409); }
        $originReference = $originCommand['operation'] === 'crypto2.scope.origin' ? $originCommand['authorDirectoryHeadHash'] : $originDirectory['head_hash'];
        $hash = hash('sha256',"JivieLifecycleBaseline/v2\n".NativeCryptoCodec::canonical((object)$baseline));
        $old = $this->one('SELECT initial_hash FROM familyhub_crypto_lifecycle_baselines_v2 WHERE scope_id=?',[$scopeId]);
        if ($old && $old['initial_hash'] === $hash) {
            return $this->initialBaseline($scopeId);
        }
        if ($this->one('SELECT head_hash FROM familyhub_crypto_scope_heads WHERE scope_id=? LIMIT 1',[$scopeId])) {
            throw new NativeError('crypto_lifecycle_baseline_immutable',409);
        }
        if ($old) {
            $this->change('UPDATE familyhub_crypto_lifecycle_baselines_v2 SET initial_hash=?,baseline=?,origin_authorization=?,origin_directory_head_hash=? WHERE scope_id=?',[$hash,NativeCryptoCodec::canonical((object)$baseline),json_encode($proof,JSON_THROW_ON_ERROR),$originReference,$scopeId]);
        } else {
            $this->change('INSERT INTO familyhub_crypto_lifecycle_baselines_v2 VALUES(?,?,?,?,?)',[$scopeId,$hash,NativeCryptoCodec::canonical((object)$baseline),json_encode($proof,JSON_THROW_ON_ERROR),$originReference]);
        }
        return $this->initialBaseline($scopeId);
    }

    public function initialBaseline($scopeId)
    {
        $row = $this->one('SELECT * FROM familyhub_crypto_lifecycle_baselines_v2 WHERE scope_id=?',[$scopeId]);
        if (!$row) {
            throw new NativeError('crypto_lifecycle_baseline_required',409);
        }
        $baseline = json_decode($row['baseline'],true,34,JSON_THROW_ON_ERROR);
        $proof = json_decode($row['origin_authorization'],true,34,JSON_THROW_ON_ERROR);
        if ($baseline['scopeId'] !== $scopeId || $baseline['originProofHash'] !== hash('sha256',NativeCryptoCodec::canonical((object)$proof)) || $row['initial_hash'] !== hash('sha256',"JivieLifecycleBaseline/v2\n".NativeCryptoCodec::canonical((object)$baseline))) {
            throw new NativeError('crypto_lifecycle_log_unavailable',503);
        }
        return ['initialLifecycleHash'=>$row['initial_hash'],'initialLifecycleBaseline'=>$baseline,'originAuthorization'=>$proof,'originAuthorDirectoryHeadHash'=>$row['origin_directory_head_hash']];
    }

    public function closingHash($scopeId)
    {
        return $this->current($scopeId)['headHash'];
    }

    public function current($scopeId)
    {
        $scope = $this->one('SELECT id,archived,parent_scope_id,organization_id FROM familyhub_scopes WHERE id=?', [$scopeId]);
        if (!$scope) {
            throw new NativeError('scope_unavailable', 409);
        }
        $row = $this->one('SELECT * FROM familyhub_crypto_lifecycle_log_v2 WHERE scope_id=? ORDER BY revision DESC LIMIT 1', [$scopeId]);
        if (!$row) {
            $initial = $this->initialBaseline($scopeId);
            $parentId = $scope['parent_scope_id'] ?? $scope['organization_id'];
            $parent = $parentId ? $this->one('SELECT archived FROM familyhub_scopes WHERE id=?', [$parentId]) : null;
            if ((bool)$scope['archived'] !== $initial['initialLifecycleBaseline']['ownArchived'] || (bool)($parent['archived'] ?? false) !== $initial['initialLifecycleBaseline']['inheritedArchived']) {
                throw new NativeError('crypto_lifecycle_log_unavailable', 503);
            }
            return ['scopeId'=>$scopeId,'revision'=>0,'headHash'=>self::ZERO,'ownArchived'=>$initial['initialLifecycleBaseline']['ownArchived'],'inheritedArchived'=>$initial['initialLifecycleBaseline']['inheritedArchived'],'authorization'=>null]+$initial;
        }
        $proof = json_decode($row['authorization'], true, 34, JSON_THROW_ON_ERROR);
        if (self::proofHash($proof) !== $row['head_hash'] || (int)$scope['archived'] !== (int)$row['own_archived']) {
            throw new NativeError('crypto_lifecycle_log_unavailable', 503);
        }
        return ['scopeId'=>$scopeId,'revision'=>(int)$row['revision'],'headHash'=>$row['head_hash'],'ownArchived'=>(bool)$row['own_archived'],'inheritedArchived'=>(bool)$row['inherited_archived'],'authorization'=>$proof,'originAuthorization'=>null];
    }

    private function digest($value)
    {
        if (!is_string($value) || !preg_match('/^[a-f0-9]{64}$/D', $value)) {
            throw new NativeError('validation_error');
        }
        return $value;
    }

    private function authority($scopeId, $headHash, $accessRevision, $authorReference, $actor)
    {
        $scope = $this->scope($scopeId, $actor['user']['id'], false, true);
        if (!in_array($scope['kind'], ['household','organization','project'], true)) {
            throw new NativeError('validation_error');
        }
        $scopes = new NativeCryptoScopeV2($this->container, $this->bearer, $this->ip);
        $head = $scopes->current($scopeId);
        $member = $head ? $scopes->member($scopes->body($head), $actor['user']['account_id']) : null;
        if (!$head || $head['head_hash'] !== $headHash || !$member || !$member['manageKeys'] || $accessRevision !== (int)$scope['effective_access_revision']) {
            throw new NativeError('crypto_access_changed', 409);
        }
        $scopes->currentAuthorReference($authorReference, $actor);
        foreach ($scopes->body($head)['members'] as $participant) {
            $directory = (new NativeCryptoDirectoryV2($this->container))->current($participant['accountId']);
            if (!$directory || $directory['device_snapshot_hash'] !== $participant['deviceSnapshotHash']) {
                throw new NativeError('crypto_scope_rotation_required', 409);
            }
        }
        $scopes->refreshPending($scopeId, $head);
        $state = $this->one('SELECT content_closed FROM familyhub_crypto_scope_state WHERE scope_id=?', [$scopeId]);
        if (!$state || (int)$state['content_closed']) {
            throw new NativeError('crypto_domain_closed', 409);
        }
        return [$scope, $head];
    }

    private function cas($scopeId, $revision, $hash)
    {
        if (!is_int($revision) || $revision < 0 || $revision >= 9007199254740991) {
            throw new NativeError('validation_error');
        }
        $this->digest($hash);
        $current = $this->current($scopeId);
        if ($revision !== $current['revision'] || $hash !== $current['headHash']) {
            throw new NativeError('crypto_lifecycle_conflict', 409);
        }
        return $current;
    }

    private function action($scopeId, $id, $actor)
    {
        $row = $this->one('SELECT * FROM familyhub_crypto_lifecycle_actions_v2 WHERE scope_id=? AND id=?', [$scopeId, $this->uuid($id)]);
        if (!$row || $row['account_id'] !== $actor['user']['account_id'] || $row['device_id'] !== $actor['device']['id'] || $row['state'] !== 'pending' || (int)$row['expires_at'] <= time()) {
            throw new NativeError('crypto_lifecycle_action_expired', 409);
        }
        return $row;
    }

    private function validateIntent($p)
    {
        $this->fields($p, ['scopeId','parentActionId','expectedLifecycleRevision','previousLifecycleHash','membershipHeadHash','expectedAccessRevision','authorDirectoryHeadHash','archived']);
        $this->uuid($p['scopeId']);
        $this->uuid($p['parentActionId']);
        $this->digest($p['previousLifecycleHash']);
        $this->digest($p['membershipHeadHash']);
        $this->digest($p['authorDirectoryHeadHash']);
        if (!is_bool($p['archived']) || !is_int($p['expectedAccessRevision']) || $p['expectedAccessRevision'] < 0) {
            throw new NativeError('validation_error');
        }
    }

    /** Discard only expired unapplied staging bytes; durable receipts/logs remain. */
    private function expireStages($scopeId)
    {
        $rows = $this->many("SELECT id FROM familyhub_crypto_lifecycle_actions_v2 WHERE scope_id=? AND state='pending' AND expires_at<=? ORDER BY id LIMIT 16", [$scopeId,time()]);
        foreach ($rows as $row) {
            $this->change('DELETE FROM familyhub_crypto_lifecycle_children_v2 WHERE scope_id=? AND action_id=?', [$scopeId,$row['id']]);
            $this->change("UPDATE familyhub_crypto_lifecycle_actions_v2 SET state='expired' WHERE scope_id=? AND id=? AND state='pending'", [$scopeId,$row['id']]);
        }
    }

    public function write($operation, $p, $actor, $proof, $command)
    {
        if ($operation === 'crypto2.scope.lifecycle.attestBaseline') {
            $this->fields($p,['scopeId','membershipHeadHash','expectedAccessRevision','authorDirectoryHeadHash','migrationId','inventoryHash','initialLifecycleHash','ownArchived','inheritedArchived']);
            $sid = $this->uuid($p['scopeId']);
            $this->authority($sid,$p['membershipHeadHash'],$p['expectedAccessRevision'],$p['authorDirectoryHeadHash'],$actor);
            $initial = $this->initialBaseline($sid);
            $frozen = (new NativeCryptoMigrationV2($this->container,$this->bearer,$this->ip))->lifecycleBaseline($sid,$p['migrationId'],$p['inventoryHash'],$actor);
            if ($initial['initialLifecycleBaseline']['originKind'] !== 'legacy' || $initial['initialLifecycleHash'] !== $p['initialLifecycleHash'] || $p['ownArchived'] !== $frozen['ownArchived'] || $p['inheritedArchived'] !== $frozen['inheritedArchived'] || $p['ownArchived'] !== $initial['initialLifecycleBaseline']['ownArchived'] || $p['inheritedArchived'] !== $initial['initialLifecycleBaseline']['inheritedArchived']) {
                throw new NativeError('crypto_lifecycle_baseline_changed',409);
            }
            if ($this->one('SELECT revision FROM familyhub_crypto_lifecycle_log_v2 WHERE scope_id=? LIMIT 1',[$sid])) {
                throw new NativeError('crypto_lifecycle_baseline_immutable',409);
            }
            $prior=['revision'=>0,'headHash'=>self::ZERO,'ownArchived'=>$p['ownArchived'],'inheritedArchived'=>$p['inheritedArchived']];
            return ['lifecycle'=>$this->appendState($sid,$prior,$p['ownArchived'],$p['inheritedArchived'],$p['membershipHeadHash'],$proof,'baseline')]+$initial;
        }
        if ($operation === 'crypto2.scope.lifecycle.delegate') {
            return $this->delegate($p, $actor, $proof);
        }
        if ($operation === 'crypto2.scope.lifecycle.observation.put') {
            return $this->stageObservation($p, $actor);
        }
        if ($operation === 'crypto2.scope.lifecycle.cancel') {
            $this->fields($p, ['scopeId','parentActionId']);
            $row = $this->action($this->uuid($p['scopeId']), $p['parentActionId'], $actor);
            $intent = json_decode($row['intent'], true, 34, JSON_THROW_ON_ERROR);
            $this->authority($p['scopeId'], $intent['membershipHeadHash'], $intent['expectedAccessRevision'], $intent['authorDirectoryHeadHash'], $actor);
            $this->change("UPDATE familyhub_crypto_lifecycle_actions_v2 SET state='cancelled' WHERE scope_id=? AND id=?", [$p['scopeId'],$row['id']]);
            $this->change('DELETE FROM familyhub_crypto_lifecycle_children_v2 WHERE scope_id=? AND action_id=?', [$p['scopeId'],$row['id']]);
            return ['state'=>'cancelled','parentActionId'=>$row['id']];
        }
        if ($operation === 'crypto2.scope.lifecycle.prepare') {
            NativeCryptoScopeCreationV2::guardBusiness($this->pdo, $p['scopeId'] ?? null);
            $this->validateIntent($p);
            $sid = $p['scopeId'];
            $this->authority($sid, $p['membershipHeadHash'], $p['expectedAccessRevision'], $p['authorDirectoryHeadHash'], $actor);
            NativeCryptoScopeCreationV2::guardBusiness($this->pdo, $sid);
            $this->cas($sid, $p['expectedLifecycleRevision'], $p['previousLifecycleHash']);
            $this->expireStages($sid);
            if ($this->one('SELECT id FROM familyhub_crypto_lifecycle_actions_v2 WHERE scope_id=? AND id=?', [$sid,$p['parentActionId']])) {
                throw new NativeError('crypto_lifecycle_action_immutable', 409);
            }
            $active = $this->one("SELECT COUNT(*) AS n FROM familyhub_crypto_lifecycle_actions_v2 WHERE scope_id=? AND state='pending' AND expires_at>?", [$sid,time()]);
            if ((int)$active['n'] >= 16) {
                throw new NativeError('crypto_lifecycle_action_limit', 409);
            }
            $this->change('INSERT INTO familyhub_crypto_lifecycle_actions_v2 VALUES(?,?,?,?,?,?,?,?,?)', [$sid,$p['parentActionId'],$actor['user']['account_id'],$actor['device']['id'],NativeCryptoCodec::canonical((object)$p),json_encode($proof, JSON_THROW_ON_ERROR),time(),time()+1800,'pending']);
            // SQL INSERT SELECT preserves the entire existing child set without an in-memory list.
            $this->change('INSERT INTO familyhub_crypto_lifecycle_children_v2(scope_id,action_id,child_scope_id) SELECT ?,?,id FROM familyhub_scopes WHERE deleted_at IS NULL AND (parent_scope_id=? OR organization_id=?)', [$sid,$p['parentActionId'],$sid,$sid]);
            return ['parentActionId'=>$p['parentActionId'],'state'=>'pending','expiresAt'=>time()+1800,'intentProofHash'=>self::proofHash($proof)];
        }
        if ($operation === 'crypto2.scope.archive') {
            return $this->apply($p, $actor, $proof, $command);
        }
        throw new NativeError('unsupported_operation', 404);
    }

    private function parentId($scopeId)
    {
        $scope = $this->one('SELECT parent_scope_id,organization_id FROM familyhub_scopes WHERE id=? AND deleted_at IS NULL', [$scopeId]);
        return $scope['parent_scope_id'] ?? $scope['organization_id'] ?? null;
    }

    private function parentIdentity($accountId, $reference)
    {
        $this->uuid($accountId);
        $this->digest($reference);
        $directory = new NativeCryptoDirectoryV2($this->container);
        $current = $directory->current($accountId);
        $ancestor = $this->one('SELECT device_snapshot_hash FROM familyhub_crypto_directory WHERE account_id=? AND head_hash=?', [$accountId, $reference]);
        if (!$current || !$ancestor || $ancestor['device_snapshot_hash'] !== $current['device_snapshot_hash']) {
            throw new NativeError('crypto_member_directory_changed', 409);
        }
        return json_decode($current['snapshot'], true, 34, JSON_THROW_ON_ERROR);
    }

    private function delegate($p, $actor, $proof)
    {
        $this->fields($p, ['scopeId','delegationId','membershipHeadHash','expectedAccessRevision','authorDirectoryHeadHash','parentScopeToken','parentAccountId','parentDirectoryHeadHash','parentRootSigningKeyBase64','parentRootEncryptionKeyBase64','parentIdentityEpochId','parentDeviceSnapshotHash','effect']);
        $this->uuid($p['delegationId']);
        $parentId = $this->parentId($p['scopeId']);
        if (!$parentId || $p['effect'] !== 'inheritedArchived' || $this->parentToken($p['scopeId'], $parentId) !== $p['parentScopeToken']) {
            throw new NativeError('crypto_lifecycle_delegation_invalid', 409);
        }
        $this->authority($p['scopeId'], $p['membershipHeadHash'], $p['expectedAccessRevision'], $p['authorDirectoryHeadHash'], $actor);
        $count = $this->one('SELECT COUNT(*) AS n FROM familyhub_crypto_lifecycle_delegations_v2 WHERE scope_id=? AND head_hash=? AND parent_account_id=?', [$p['scopeId'],$p['membershipHeadHash'],$p['parentAccountId']]);
        if ((int)$count['n'] >= 16) {
            throw new NativeError('crypto_lifecycle_delegation_limit',409);
        }
        $parent = $this->one('SELECT a.user_id FROM familyhub_accounts a WHERE a.account_id=?', [$p['parentAccountId']]);
        if (!$parent) {
            throw new NativeError('permission_revoked', 403);
        }
        $this->scope($parentId, $parent['user_id'], false, true);
        $identity = $this->parentIdentity($p['parentAccountId'], $p['parentDirectoryHeadHash']);
        if ($identity['rootSigningKeyBase64'] !== $p['parentRootSigningKeyBase64'] || $identity['rootEncryptionKeyBase64'] !== $p['parentRootEncryptionKeyBase64'] || $identity['identityEpochId'] !== $p['parentIdentityEpochId'] || NativeCryptoDirectoryV2::deviceHash($identity) !== $p['parentDeviceSnapshotHash']) {
            throw new NativeError('crypto_lifecycle_delegation_invalid', 409);
        }
        if ($this->one('SELECT id FROM familyhub_crypto_lifecycle_delegations_v2 WHERE scope_id=? AND id=?', [$p['scopeId'], $p['delegationId']])) {
            throw new NativeError('crypto_lifecycle_action_immutable', 409);
        }
        $hash = self::proofHash($proof);
        $this->change('INSERT INTO familyhub_crypto_lifecycle_delegations_v2 VALUES(?,?,?,?,?,?,?)', [$p['scopeId'],$p['delegationId'],$p['membershipHeadHash'],$parentId,$p['parentAccountId'],$hash,json_encode($proof, JSON_THROW_ON_ERROR)]);
        return ['scopeId'=>$p['scopeId'],'delegationId'=>$p['delegationId'],'delegationProofHash'=>$hash];
    }

    private function observation($proof, $intent, $actor, $intentProofHash)
    {
        [$card,$bytes,$signature] = NativeCryptoCodec::decode($proof);
        $this->fields($card, ['version','serverId','accountId','deviceId','authorDirectoryHeadHash','parentActionId','parentScopeToken','parentMembershipHeadHash','parentExpectedLifecycleRevision','parentPreviousLifecycleHash','parentIntentProofHash','parentDeviceSnapshotHash','archived','scopeId','membershipHeadHash','expectedLifecycleRevision','previousLifecycleHash','delegationProofHash']);
        foreach (['scopeId','accountId','deviceId','parentActionId'] as $field) {
            $this->uuid($card[$field]);
        }
        if ($card['version'] !== 2 || $card['serverId'] !== $this->serverId() || $card['accountId'] !== $actor['user']['account_id'] || $card['deviceId'] !== $actor['device']['id'] || $card['parentActionId'] !== $intent['parentActionId'] || $card['parentScopeToken'] !== $this->parentToken($card['scopeId'], $intent['scopeId']) || $card['parentMembershipHeadHash'] !== $intent['membershipHeadHash'] || $card['parentExpectedLifecycleRevision'] !== $intent['expectedLifecycleRevision'] || $card['parentPreviousLifecycleHash'] !== $intent['previousLifecycleHash'] || $card['archived'] !== $intent['archived'] || $this->parentId($card['scopeId']) !== $intent['scopeId']) {
            throw new NativeError('crypto_lifecycle_observation_binding', 409);
        }
        if (($card['parentIntentProofHash'] ?? null) !== $intentProofHash) {
            throw new NativeError('crypto_lifecycle_observation_binding', 409);
        }
        $scopes = new NativeCryptoScopeV2($this->container);
        $scopes->currentAuthorReference($card['authorDirectoryHeadHash'], $actor);
        $identity = $this->parentIdentity($card['accountId'], $card['authorDirectoryHeadHash']);
        if ($card['parentDeviceSnapshotHash'] !== NativeCryptoDirectoryV2::deviceHash($identity)) {
            throw new NativeError('crypto_lifecycle_observation_binding', 409);
        }
        $device = (new NativeCryptoDirectoryV2($this->container))->device($identity, $card['deviceId']);
        NativeCryptoV2Codec::verify($bytes, $signature, $device['signingKeyBase64'], self::OBSERVATION_DOMAIN);
        NativeCryptoScopeCreationV2::guardBusiness($this->pdo,$card['scopeId']);
        $childHead = $scopes->current($card['scopeId']);
        if (!$childHead || $childHead['head_hash'] !== $card['membershipHeadHash']) {
            throw new NativeError('crypto_scope_head_conflict', 409);
        }
        $scopes->refreshPending($card['scopeId'], $childHead);
        $state = $this->one('SELECT content_closed FROM familyhub_crypto_scope_state WHERE scope_id=?', [$card['scopeId']]);
        if (!$state || (int)$state['content_closed']) {
            throw new NativeError('crypto_domain_closed', 409);
        }
        $this->cas($card['scopeId'], $card['expectedLifecycleRevision'], $card['previousLifecycleHash']);
        if ($card['delegationProofHash'] === null) {
            $this->authority($card['scopeId'], $card['membershipHeadHash'], (int)$childHead['access_revision'], $card['authorDirectoryHeadHash'], $actor);
        } else {
            $this->digest($card['delegationProofHash']);
            $delegation = $this->one('SELECT * FROM familyhub_crypto_lifecycle_delegations_v2 WHERE scope_id=? AND head_hash=? AND parent_scope_id=? AND parent_account_id=? AND proof_hash=?', [$card['scopeId'],$card['membershipHeadHash'],$intent['scopeId'],$card['accountId'],$card['delegationProofHash']]);
            if (!$delegation) {
                throw new NativeError('crypto_lifecycle_delegation_invalid', 409);
            }
            [$signed] = NativeCryptoCodec::decode(json_decode($delegation['authorization'], true, 34, JSON_THROW_ON_ERROR));
            $grant = $signed['payload'];
            $issuer = $this->one('SELECT a.account_id,u.* FROM familyhub_accounts a JOIN users u ON u.id=a.user_id WHERE a.account_id=? AND u.is_active=1', [$signed['accountId']]);
            if (!$issuer) {
                throw new NativeError('crypto_lifecycle_delegation_invalid', 409);
            }
            // A previously issued delegation cannot outlive its issuing
            // manager's current device/role or the authenticated child head.
            $this->authority($card['scopeId'], $card['membershipHeadHash'], $grant['expectedAccessRevision'], $grant['authorDirectoryHeadHash'], ['user'=>$issuer,'device'=>['id'=>$signed['deviceId']]]);
            if ($identity['rootSigningKeyBase64'] !== $grant['parentRootSigningKeyBase64'] || $identity['rootEncryptionKeyBase64'] !== $grant['parentRootEncryptionKeyBase64'] || $identity['identityEpochId'] !== $grant['parentIdentityEpochId'] || NativeCryptoDirectoryV2::deviceHash($identity) !== $grant['parentDeviceSnapshotHash']) {
                throw new NativeError('crypto_lifecycle_delegation_invalid', 409);
            }
        }
        return $card;
    }

    private function stageObservation($p, $actor)
    {
        $this->fields($p, ['scopeId','parentActionId','observation']);
        $action = $this->action($this->uuid($p['scopeId']), $p['parentActionId'], $actor);
        $intent = json_decode($action['intent'], true, 34, JSON_THROW_ON_ERROR);
        $this->authority($intent['scopeId'], $intent['membershipHeadHash'], $intent['expectedAccessRevision'], $intent['authorDirectoryHeadHash'], $actor);
        $card = $this->observation($p['observation'], $intent, $actor, self::proofHash(json_decode($action['authorization'], true, 34, JSON_THROW_ON_ERROR)));
        $row = $this->one('SELECT * FROM familyhub_crypto_lifecycle_children_v2 WHERE scope_id=? AND action_id=? AND child_scope_id=?', [$p['scopeId'],$p['parentActionId'],$card['scopeId']]);
        if (!$row) {
            throw new NativeError('crypto_lifecycle_children_changed', 409);
        }
        $hash = self::proofHash($p['observation']);
        if ($row['proof_hash'] !== null && $row['proof_hash'] !== $hash) {
            throw new NativeError('crypto_lifecycle_action_immutable', 409);
        }
        $this->change('UPDATE familyhub_crypto_lifecycle_children_v2 SET observation=?,proof_hash=? WHERE scope_id=? AND action_id=? AND child_scope_id=?', [json_encode($p['observation'], JSON_THROW_ON_ERROR),$hash,$p['scopeId'],$p['parentActionId'],$card['scopeId']]);
        return ['parentActionId'=>$p['parentActionId'],'scopeId'=>$card['scopeId'],'observationProofHash'=>$hash];
    }

    private function children($scopeId, $actionId)
    {
        $after = '';
        do {
            $page = $this->many('SELECT * FROM familyhub_crypto_lifecycle_children_v2 WHERE scope_id=? AND action_id=? AND child_scope_id>? ORDER BY child_scope_id LIMIT 50', [$scopeId,$actionId,$after]);
            foreach ($page as $row) {
                $after = $row['child_scope_id'];
                yield $row;
            }
        } while (count($page) === 50);
    }

    private function appendState($scopeId, $prior, $own, $inherited, $membershipHead, $proof, $kind)
    {
        $hash = self::proofHash($proof);
        $this->change('INSERT INTO familyhub_crypto_lifecycle_log_v2 VALUES(?,?,?,?,?,?,?,?,?)', [$scopeId,$prior['revision']+1,$hash,$prior['headHash'],$kind,(int)$own,(int)$inherited,$membershipHead,json_encode($proof, JSON_THROW_ON_ERROR)]);
        if ($own !== $prior['ownArchived']) {
            $this->change('UPDATE familyhub_scopes SET archived=?,sequence=sequence+1 WHERE id=?', [(int)$own,$scopeId]);
        }
        if ($own || $inherited) {
            $this->change("UPDATE familyhub_crypto_reminders_v2 SET state='cancelled',revision=revision+1 WHERE scope_id=? AND state='pending'", [$scopeId]);
        }
        return $this->current($scopeId);
    }

    private function apply($p, $actor, $proof, $command)
    {
        $this->fields($p, ['scopeId','parentActionId','intentProofHash','childCount','childrenHash']);
        if (!is_int($p['childCount']) || $p['childCount'] < 0) {
            throw new NativeError('validation_error');
        }
        $this->digest($p['childrenHash']);
        NativeCryptoScopeCreationV2::guardBusiness($this->pdo, $p['scopeId']);
        $action = $this->action($this->uuid($p['scopeId']), $p['parentActionId'], $actor);
        $intent = json_decode($action['intent'], true, 34, JSON_THROW_ON_ERROR);
        $this->digest($p['intentProofHash']);
        if ($p['intentProofHash'] !== self::proofHash(json_decode($action['authorization'],true,34,JSON_THROW_ON_ERROR))) {
            throw new NativeError('crypto_lifecycle_intent_binding',409);
        }
        [$scope] = $this->authority($intent['scopeId'], $intent['membershipHeadHash'], $intent['expectedAccessRevision'], $intent['authorDirectoryHeadHash'], $actor);
        $prior = $this->cas($p['scopeId'], $intent['expectedLifecycleRevision'], $intent['previousLifecycleHash']);
        $counts = $this->one('SELECT COUNT(*) AS n FROM familyhub_scopes WHERE deleted_at IS NULL AND (parent_scope_id=? OR organization_id=?)', [$p['scopeId'],$p['scopeId']]);
        $hash = hash_init('sha256');
        $seen = 0;
        foreach ($this->children($p['scopeId'], $p['parentActionId']) as $child) {
            if ($child['observation'] === null || $this->parentId($child['child_scope_id']) !== $p['scopeId']) {
                throw new NativeError('crypto_lifecycle_children_incomplete', 409);
            }
            $observation = json_decode($child['observation'], true, 34, JSON_THROW_ON_ERROR);
            $card = $this->observation($observation, $intent, $actor, $p['intentProofHash']);
            hash_update($hash, NativeCryptoCodec::canonical((object)['scopeId'=>$card['scopeId'],'observationProofHash'=>$child['proof_hash']])."\n");
            $seen++;
        }
        if ($seen !== $p['childCount'] || $seen !== (int)$counts['n'] || hash_final($hash) !== $p['childrenHash']) {
            throw new NativeError('crypto_lifecycle_children_changed', 409);
        }
        // The shared crypto transaction lock prevents a graph/write change
        // between the complete validation pass and these append-only effects.
        foreach ($this->children($p['scopeId'], $p['parentActionId']) as $child) {
            $observation = json_decode($child['observation'], true, 34, JSON_THROW_ON_ERROR);
            [$card] = NativeCryptoCodec::decode($observation);
            $old = $this->current($card['scopeId']);
            $this->appendState($card['scopeId'], $old, $old['ownArchived'], $intent['archived'], $card['membershipHeadHash'], $observation, 'inherited');
        }
        $result = $this->appendState($p['scopeId'], $prior, $intent['archived'], $prior['inheritedArchived'], $intent['membershipHeadHash'], $proof, 'own');
        $this->change("UPDATE familyhub_crypto_lifecycle_actions_v2 SET state='applied' WHERE scope_id=? AND id=?", [$p['scopeId'],$p['parentActionId']]);
        return ['lifecycle'=>$this->wireState($p['scopeId'], $result),'intentAuthorization'=>json_decode($action['authorization'], true, 34, JSON_THROW_ON_ERROR)];
    }

    /** Discovery only; the child manager must independently verify the target identity. */
    public function pendingDelegations($scopeId, $actor, $after = '', $limit = 20)
    {
        $scope = $this->scope($scopeId, $actor['user']['id'], false, true);
        $scopes = new NativeCryptoScopeV2($this->container, $this->bearer, $this->ip);
        $head = $scopes->current($scopeId);
        $scopes->manager($head, $scope, $actor);
        if (!$head) {
            throw new NativeError('crypto_child_genesis_pending',409);
        }
        $parentId = $this->parentId($scopeId);
        if (!$parentId) {
            return ['requests'=>[],'hasMore'=>false,'nextAfterId'=>null];
        }
        $rows = $this->many("SELECT a.* FROM familyhub_crypto_lifecycle_actions_v2 a JOIN familyhub_crypto_lifecycle_children_v2 c ON c.scope_id=a.scope_id AND c.action_id=a.id WHERE c.child_scope_id=? AND a.scope_id=? AND a.state='pending' AND a.expires_at>? AND a.id>? ORDER BY a.id LIMIT ".($limit+1), [$scopeId,$parentId,time(),$after]);
        $out = [];
        foreach (array_slice($rows,0,$limit) as $row) {
            $intent = json_decode($row['intent'],true,34,JSON_THROW_ON_ERROR);
            $user = $this->one('SELECT a.account_id,u.* FROM familyhub_accounts a JOIN users u ON u.id=a.user_id WHERE a.account_id=? AND u.is_active=1',[$row['account_id']]);
            if (!$user) {
                continue;
            }
            try {
                $this->authority($parentId,$intent['membershipHeadHash'],$intent['expectedAccessRevision'],$intent['authorDirectoryHeadHash'],['user'=>$user,'device'=>['id'=>$row['device_id']]]);
                $identity = $this->parentIdentity($row['account_id'],$intent['authorDirectoryHeadHash']);
            } catch (NativeError $error) {
                if (in_array($error->status,[403,409],true)) {
                    continue;
                }
                throw $error;
            }
            $out[] = ['parentActionId'=>$row['id'],'parentScopeToken'=>$this->parentToken($scopeId,$parentId),'parentAccountId'=>$row['account_id'],'parentDirectoryHeadHash'=>$intent['authorDirectoryHeadHash'],'parentRootSigningKeyBase64'=>$identity['rootSigningKeyBase64'],'parentRootEncryptionKeyBase64'=>$identity['rootEncryptionKeyBase64'],'parentIdentityEpochId'=>$identity['identityEpochId'],'parentDeviceSnapshotHash'=>NativeCryptoDirectoryV2::deviceHash($identity),'parentIntentProofHash'=>self::proofHash(json_decode($row['authorization'],true,34,JSON_THROW_ON_ERROR)),'archived'=>$intent['archived'],'expiresAt'=>(int)$row['expires_at'],'membershipHeadHash'=>$head['head_hash'],'expectedAccessRevision'=>(int)$scope['effective_access_revision']];
        }
        $page = array_slice($rows,0,$limit);
        return ['requests'=>$out,'hasMore'=>count($rows)>$limit,'nextAfterId'=>$page ? end($page)['id'] : null];
    }

    public function pendingDirectoryReference($scopeId, $target, $actor)
    {
        $page = $this->pendingDelegations($scopeId,$actor,'',20);
        foreach ($page['requests'] as $request) {
            if ($request['parentAccountId'] === $target) {
                return $request['parentDirectoryHeadHash'];
            }
        }
        return null;
    }

    /** Only own-scope proofs are returned. Parent actions never disclose siblings. */
    public function read($operation, $p, $actor)
    {
        if ($operation === 'crypto2.scope.lifecycle.pendingDelegations') {
            $this->fields($p,['scopeId'],['afterId','limit']);
            $limit=$p['limit'] ?? 20;
            if (!is_int($limit) || $limit<1 || $limit>20) {
                throw new NativeError('validation_error');
            }
            return $this->pendingDelegations($this->uuid($p['scopeId']),$actor,isset($p['afterId']) ? $this->uuid($p['afterId']) : '',$limit);
        }
        if ($operation === 'crypto2.scope.lifecycle.baseline') {
            $this->fields($p,['scopeId']);
            $sid=$this->uuid($p['scopeId']);
            $this->scope($sid,$actor['user']['id']);
            return $this->initialBaseline($sid);
        }
        if ($operation === 'crypto2.scope.lifecycle.children') {
            $this->fields($p, ['scopeId','parentActionId'], ['afterId','limit']);
            $action = $this->action($this->uuid($p['scopeId']), $p['parentActionId'], $actor);
            $intent = json_decode($action['intent'], true, 34, JSON_THROW_ON_ERROR);
            $this->authority($p['scopeId'], $intent['membershipHeadHash'], $intent['expectedAccessRevision'], $intent['authorDirectoryHeadHash'], $actor);
            $after = isset($p['afterId']) ? $this->uuid($p['afterId']) : '';
            $limit = $p['limit'] ?? 50;
            if (!is_int($limit) || $limit < 1 || $limit > 50) {
                throw new NativeError('validation_error');
            }
            $rows = $this->many('SELECT child_scope_id,proof_hash FROM familyhub_crypto_lifecycle_children_v2 WHERE scope_id=? AND action_id=? AND child_scope_id>? ORDER BY child_scope_id LIMIT '.($limit+1), [$p['scopeId'],$p['parentActionId'],$after]);
            $page = array_slice($rows, 0, $limit);
            $out = [];
            foreach ($page as $row) {
                $head = (new NativeCryptoScopeV2($this->container))->current($row['child_scope_id']);
                $delegations = $head ? $this->many('SELECT authorization,proof_hash FROM familyhub_crypto_lifecycle_delegations_v2 WHERE scope_id=? AND head_hash=? AND parent_account_id=? ORDER BY id LIMIT 16', [$row['child_scope_id'],$head['head_hash'],$actor['user']['account_id']]) : [];
                $out[] = ['pendingReason'=>$head ? null : 'crypto_child_genesis_pending','scopeId'=>$row['child_scope_id'],'membershipHeadHash'=>$head['head_hash'] ?? null,'lifecycle'=>$this->current($row['child_scope_id']),'delegations'=>array_map(fn($d)=>['authorization'=>json_decode($d['authorization'],true,34,JSON_THROW_ON_ERROR),'proofHash'=>$d['proof_hash']],$delegations),'observationProofHash'=>$row['proof_hash']];
            }
            return ['children'=>$out,'hasMore'=>count($rows)>$limit,'nextAfterId'=>count($rows)>$limit ? end($page)['child_scope_id'] : null];
        }
        $this->fields($p, ['scopeId'], ['afterRevision','limit']);
        $sid = $this->uuid($p['scopeId']);
        $this->scope($sid, $actor['user']['id']);
        if ($operation === 'crypto2.scope.lifecycle.current') {
            return ['lifecycle'=>$this->wireState($sid, $this->current($sid))];
        }
        if ($operation !== 'crypto2.scope.lifecycle.list') {
            throw new NativeError('unsupported_operation', 404);
        }
        $after = $p['afterRevision'] ?? 0;
        $limit = $p['limit'] ?? 20;
        if (!is_int($after) || $after < 0 || !is_int($limit) || $limit < 1 || $limit > 20) {
            throw new NativeError('validation_error');
        }
        $rows = $this->many('SELECT * FROM familyhub_crypto_lifecycle_log_v2 WHERE scope_id=? AND revision>? ORDER BY revision LIMIT '.($limit+1), [$sid,$after]);
        $page = array_slice($rows,0,$limit);
        $out = [];
        foreach ($page as $row) {
            $out[] = $this->wireState($sid, ['scopeId'=>$sid,'revision'=>(int)$row['revision'],'headHash'=>$row['head_hash'],'ownArchived'=>(bool)$row['own_archived'],'inheritedArchived'=>(bool)$row['inherited_archived'],'authorization'=>json_decode($row['authorization'],true,34,JSON_THROW_ON_ERROR),'originAuthorization'=>null]);
        }
        return ['states'=>$out,'hasMore'=>count($rows)>$limit,'nextAfterRevision'=>count($rows)>$limit ? (int)end($page)['revision'] : null,'currentRevision'=>$this->current($sid)['revision']];
    }

    private function wireState($sid, $state)
    {
        if ($state['authorization'] === null) {
            return $state;
        }
        [$command] = NativeCryptoCodec::decode($state['authorization']);
        if (isset($command['operation']) && $command['operation'] === 'crypto2.scope.archive') {
            $action = $this->one('SELECT authorization FROM familyhub_crypto_lifecycle_actions_v2 WHERE scope_id=? AND id=?', [$sid,$command['payload']['parentActionId']]);
            if (!$action) {
                throw new NativeError('crypto_lifecycle_log_unavailable',503);
            }
            $state['intentAuthorization'] = json_decode($action['authorization'],true,34,JSON_THROW_ON_ERROR);
            if (($command['payload']['intentProofHash'] ?? null) !== self::proofHash($state['intentAuthorization'])) {
                throw new NativeError('crypto_lifecycle_log_unavailable',503);
            }
        } elseif (!isset($command['operation']) && $command['delegationProofHash'] !== null) {
            $delegation = $this->one('SELECT authorization FROM familyhub_crypto_lifecycle_delegations_v2 WHERE scope_id=? AND proof_hash=?', [$sid,$command['delegationProofHash']]);
            if (!$delegation) {
                throw new NativeError('crypto_lifecycle_log_unavailable',503);
            }
            $state['delegationAuthorization'] = json_decode($delegation['authorization'],true,34,JSON_THROW_ON_ERROR);
        }
        return $state;
    }
}
