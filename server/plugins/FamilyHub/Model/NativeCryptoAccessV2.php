<?php

namespace Kanboard\Plugin\FamilyHub\Model;

/** Closed topology actions. Every affected scope independently approves its own future head. */
class NativeCryptoAccessV2 extends NativeDatabase
{
    protected $cryptoAccess = true;
    // Admission is private to one globally locked activation call. Never kept
    // across transactions or across an intentional topology apply.
    private static $validatedBases = [];
    private static $simulations = [];
    private static $finalConsequences = [];
    private static $simulationConsequences = [];
    private $consequenceCache = [];

    private function memoKey($row)
    {
        return spl_object_id($this->pdo).':'.$row['intent_hash'];
    }

    private function scopes()
    {
        return new NativeCryptoScopeV2($this->container, $this->bearer, $this->ip);
    }

    private function hashValue($value)
    {
        if (!is_string($value) ||
            !preg_match('/^[a-f0-9]{64}$/D', $value)) {
            throw new NativeError('validation_error');
        }
        return $value;
    }

    private function token($scopeId, $rootId)
    {
        return hash('sha256', "JivieAccessPortion/v2\n".NativeCryptoCodec::canonical((object)['version' => 2,'serverId' => $this->serverId(),'scopeId' => $scopeId,'rootScopeId' => $rootId]));
    }

    private function descriptor($scope)
    {
        $parent = $scope['parent_scope_id'] ?? $scope['organization_id'] ?? null;
        $descriptor = ['kind' => $scope['kind'],'accessPolicyVersion' => (int)$scope['effective_access_policy_version'],'parentScopeToken' => $parent ? (new NativeCryptoLifecycleV2($this->container))->parentToken($scope['id'], $parent) : null];
        if ($scope['kind'] === 'organization') {
            $leaders = [];
            // Policy3 preserves old rows as history; only its owner is an
            // effective leader. The owner is implicit in the signed roster.
            if ($descriptor['accessPolicyVersion'] < 3) {
                $access = new NativeOrganizationAccess($this->container);
                foreach ($this->scopes()->effectiveMembers($scope['id']) as $member) {
                    if ($member['role'] !== 'owner' && $access->leader($scope, $member['accountId'])) {
                        $leaders[] = $member['accountId'];
                    }
                }
                sort($leaders, SORT_STRING);
            }
            $descriptor['leaderAccountIds'] = $leaders;
        }
        return $descriptor;
    }

    private function consequenceFrame($row, $force = false)
    {
        $action=json_decode($row['action'],true,34,JSON_THROW_ON_ERROR);
        if (($action['kind']??null)!=='accessPolicy' || ($action['targetVersion']??null)!==3) return null;
        $memo=$this->memoKey($row);
        if (isset(self::$simulations[$memo],self::$simulationConsequences[$memo])) return self::$simulationConsequences[$memo];
        if ($row['state']==='committing') {
            if (!isset(self::$finalConsequences[$memo])) throw new NativeError('crypto_access_consequence_context',409);
            return self::$finalConsequences[$memo];
        }
        if (!$force && isset($this->consequenceCache[$memo])) return $this->consequenceCache[$memo];
        [$prepare]=NativeCryptoCodec::decode(json_decode($row['authorization'],true,34,JSON_THROW_ON_ERROR));
        $expected=$prepare['payload']['consequenceSnapshot']??null;
        $frame=(new NativeCryptoAccessConsequencesV2($this->container))->collect($row['scope_id'],$prepare['requestId']);
        if (!is_array($expected) || NativeCryptoCodec::canonical((object)$expected)!==NativeCryptoCodec::canonical((object)$frame['snapshot'])) {
            throw new NativeError('crypto_access_consequences_changed',409);
        }
        return $this->consequenceCache[$memo]=$frame;
    }

    private function ownerScope($scopeId)
    {
        $row = $this->one('SELECT a.account_id FROM familyhub_scopes s JOIN familyhub_accounts a ON a.user_id=s.owner_id WHERE s.id=?', [$scopeId]);
        $scope = $row ? (new NativeOrganizationAccess($this->container))->visibleScope($scopeId, $row['account_id']) : null;
        if (!$scope) {
            throw new NativeError('crypto_access_component_changed', 409);
        }
        return $scope;
    }

    private function action($scope, $action)
    {
        if (!is_array($action)) {
            throw new NativeError('validation_error');
        }
        if (($action['kind'] ?? null) === 'memberRemove') {
            $this->fields($action, ['kind', 'accountId']);
            $this->uuid($action['accountId']);
            $member = $this->one('SELECT m.role,a.user_id FROM familyhub_members m JOIN familyhub_accounts a ON a.account_id=m.account_id AND a.user_id=m.user_id WHERE m.scope_id=? AND m.account_id=? AND m.active=1', [$scope['id'], $action['accountId']]);
            if (!$member) {
                throw new NativeError('crypto_membership_parent_action_required', 409);
            }
            if ($member['role'] === 'owner') {
                throw new NativeError('cannot_remove_owner', 409);
            }
            $parentId = $scope['parent_scope_id'] ?? $scope['organization_id'] ?? null;
            $parent = $parentId ? $this->one('SELECT * FROM familyhub_scopes WHERE id=?', [$parentId]) : null;
            $access = new NativeOrganizationAccess($this->container);
            if ($scope['kind'] === 'project' && $parent &&
                ((int)$parent['access_policy_version'] === 3 && $access->directMember($parentId, $action['accountId']) ||
                 (int)$parent['access_policy_version'] === 2 && $access->leader($parent, $action['accountId']))) {
                throw new NativeError('crypto_membership_parent_action_required', 409);
            }
            if (!in_array($scope['kind'], ['household', 'organization', 'project'], true)) {
                throw new NativeError('personal_not_shareable', 403);
            }
            return;
        }
        if (($action['kind'] ?? null) === 'accessPolicy') {
            $this->fields($action, ['kind','targetVersion']);
            $version = (int)$scope['access_policy_version'];
            $target = $action['targetVersion'];
            if (!in_array($target, [2,3], true) ||
                ($target === 2 && ($scope['kind'] !== 'organization' || $version !== 1)) ||
                ($target === 3 && (
                    !in_array($scope['kind'], ['household','organization','project'], true) ||
                    $version >= 3 ||
                    !empty($scope['parent_scope_id']) ||
                    !empty($scope['organization_id'])
                ))) {
                throw new NativeError('access_migration_required', 409);
            }
            if ($target === 3 && $scope['kind'] === 'project') {
                $this->projectRoot($scope);
            }
            return;
        }
        if (($action['kind'] ?? null) !== 'leader') {
            throw new NativeError('validation_error');
        }
        $this->fields($action, ['kind','accountId','enabled']);
        $this->uuid($action['accountId']);
        if (!is_bool($action['enabled']) ||
            $scope['kind'] !== 'organization' ||
            (int)$scope['access_policy_version'] !== 2) {
            throw new NativeError('access_migration_required', 409);
        }
        $member = $this->one('SELECT m.role FROM familyhub_members m JOIN familyhub_accounts a ON a.account_id=m.account_id AND a.user_id=m.user_id JOIN users u ON u.id=a.user_id WHERE m.scope_id=? AND m.account_id=? AND m.active=1 AND u.is_active=1', [$scope['id'],$action['accountId']]);
        if (!$member) {
            throw new NativeError('assignee_not_member', 409);
        }
        if ($member['role'] === 'owner' &&
            !$action['enabled']) {
            throw new NativeError('cannot_remove_owner', 409);
        }
    }

    /** Validate the already authenticated public linkage, without reading content. */
    private function projectRoot($scope)
    {
        $roots = $this->many("SELECT id,type,metadata FROM familyhub_crypto_records WHERE scope_id=? AND type='project' AND deleted=0 ORDER BY id LIMIT 2", [$scope['id']]);
        if (count($roots) !== 1) {
            throw new NativeError('project_scope_requires_single_root', 409);
        }
        $root = $roots[0];
        $metadata = json_decode($root['metadata'], true, 34, JSON_THROW_ON_ERROR);
        NativeCryptoRecordAddressV2::verify([
            'serverId' => $this->serverId(),
            'scopeId' => $scope['id'],
            'id' => $root['id'],
            'type' => 'project',
            'domain' => 'content',
            'metadata' => $metadata,
        ]);
        $canonical = $metadata['identity']['canonicalId'];
        if (!empty($scope['project_root_id']) && $scope['project_root_id'] !== $canonical) {
            throw new NativeError('project_scope_root_changed', 409);
        }
        $after = '';
        do {
            $page = $this->many("SELECT id,metadata FROM familyhub_crypto_records WHERE scope_id=? AND type IN ('task','event','idea') AND deleted=0 AND id>? ORDER BY id LIMIT 100", [$scope['id'],$after]);
            foreach ($page as $record) {
                $after = $record['id'];
                $meta = json_decode($record['metadata'], true, 34, JSON_THROW_ON_ERROR);
                $linked = array_filter($meta['references'] ?? [], fn ($ref) =>
                    $ref['scopeId'] === $scope['id'] && $ref['id'] === $root['id']);
                if (!$linked) {
                    throw new NativeError('project_scope_unrelated_content', 409);
                }
            }
        } while (count($page) === 100);
        return $canonical;
    }

    private function apply($row)
    {
        $action = json_decode($row['action'], true, 34, JSON_THROW_ON_ERROR);
        if ($action['kind'] === 'memberRemove') {
            $scope = $this->ownerScope($row['scope_id']);
            $member = $this->one('SELECT user_id FROM familyhub_members WHERE scope_id=? AND account_id=? AND active=1', [$row['scope_id'], $action['accountId']]);
            if (!$member) {
                throw new NativeError('crypto_access_component_changed', 409);
            }
            // Reuse the exact existing resolver delta, including child-owner
            // transfer blockers, direct child grants and revocation notices.
            // All effects are SQL-only and roll back in savepoint previews.
            (new NativeMembershipRevocation($this->container))->apply($scope, $action['accountId'], $member['user_id']);
            $this->portions($row, function ($portion) use ($action) {
                $sid = $portion['scope_id'];
                (new NativeCryptoInvitationPreauthorizationV5($this->container))->retireForAccess($sid,$action['accountId']);
                $this->change("UPDATE familyhub_crypto_reminders_v2 SET state='cancelled',revision=revision+1 WHERE scope_id=? AND account_id=? AND state='pending'", [$sid, $action['accountId']]);
                $this->change("UPDATE familyhub_crypto_invitation_mail_v2 SET state='cancelled',token_cipher=NULL,lease_token=NULL,lease_until=NULL WHERE invitation_id IN (SELECT id FROM familyhub_crypto_invitations_v2 WHERE scope_id=? AND recipient_account_id=? AND state IN ('pending','accepted'))", [$sid, $action['accountId']]);
                $this->change("UPDATE familyhub_crypto_invitation_acceptances_v2 SET state='revoked' WHERE invitation_id IN (SELECT id FROM familyhub_crypto_invitations_v2 WHERE scope_id=? AND recipient_account_id=? AND state IN ('pending','accepted')) AND state='accepted'", [$sid, $action['accountId']]);
                $this->change("UPDATE familyhub_crypto_invitations_v2 SET state='revoked' WHERE scope_id=? AND recipient_account_id=? AND state IN ('pending','accepted')", [$sid, $action['accountId']]);
            });
            return;
        }
        if ($action['kind'] === 'accessPolicy') {
            $target = $action['targetVersion'];
            $rootScope = $this->one('SELECT * FROM familyhub_scopes WHERE id=?', [$row['scope_id']]);
            if ($target === 3 && $rootScope['kind'] === 'project') {
                // Recheck inside each preview/final transaction. The final
                // closed inventory CAS also prevents a post-review new child.
                $canonical = $this->projectRoot($rootScope);
                $this->change('UPDATE familyhub_scopes SET project_root_id=? WHERE id=?', [$canonical,$row['scope_id']]);
            }
            $this->change('UPDATE familyhub_scopes SET access_policy_version=?,access_revision=access_revision+1,sequence=sequence+1 WHERE id=?', [$target,$row['scope_id']]);
            $this->portions($row, function ($portion) use ($row, $target) {
                $sid = $portion['scope_id'];
                (new NativeCryptoInvitationPreauthorizationV5($this->container))->retireForAccess($sid,null,true);
                if ($target === 3 && $sid !== $row['scope_id']) {
                    $this->change('UPDATE familyhub_scopes SET access_policy_version=3,access_revision=access_revision+1 WHERE id=?', [$sid]);
                }
                $insert = $this->sqlite ? 'INSERT OR IGNORE' : 'INSERT IGNORE';
                $this->change($insert.' INTO familyhub_finance_policy(scope_id,enabled,revision,sequence) VALUES(?,0,0,0)', [$sid]);
                $this->change('UPDATE familyhub_finance_policy SET enabled=1,revision=revision+1 WHERE scope_id=?', [$sid]);
                if ($target === 2) {
                    $owner = $this->one("SELECT account_id FROM familyhub_members WHERE scope_id=? AND role='owner' AND active=1", [$sid]);
                    if ($owner) {
                        $this->change($insert." INTO familyhub_finance_grants(scope_id,account_id,access_level) VALUES(?,?,'write')", [$sid,$owner['account_id']]);
                    }
                } else {
                    $this->change("UPDATE familyhub_crypto_invitation_mail_v2 SET state='cancelled',token_cipher=NULL,lease_token=NULL,lease_until=NULL WHERE invitation_id IN (SELECT id FROM familyhub_crypto_invitations_v2 WHERE scope_id=? AND state IN ('pending','accepted'))", [$sid]);
                    $this->change("UPDATE familyhub_crypto_invitation_acceptances_v2 SET state='revoked' WHERE invitation_id IN (SELECT id FROM familyhub_crypto_invitations_v2 WHERE scope_id=? AND state IN ('pending','accepted')) AND state='accepted'", [$sid]);
                    $this->change("UPDATE familyhub_crypto_invitations_v2 SET state='revoked' WHERE scope_id=? AND state IN ('pending','accepted')", [$sid]);
                    // Legacy pending mail is retained/cancelled as the original
                    // policy3 operation did; no source payload is read or sent.
                    $this->change('UPDATE familyhub_invitations SET revoked_at=? WHERE scope_id=? AND accepted_at IS NULL AND revoked_at IS NULL AND NOT EXISTS (SELECT 1 FROM familyhub_crypto_invitation_routes_v3 r JOIN familyhub_crypto_invitations_v2 c ON c.id=r.invitation_id AND c.scope_id=r.scope_id AND c.token_hash=r.token_hash WHERE r.invitation_id=familyhub_invitations.id AND r.scope_id=familyhub_invitations.scope_id AND r.token_hash=familyhub_invitations.token_hash)', [time(),$sid]);
                    $this->change("UPDATE familyhub_invitation_mail SET state='cancelled',token_cipher=NULL,lease_token=NULL WHERE invitation_id IN (SELECT i.id FROM familyhub_invitations i WHERE i.scope_id=? AND i.revoked_at IS NOT NULL AND NOT EXISTS (SELECT 1 FROM familyhub_crypto_invitation_routes_v3 r JOIN familyhub_crypto_invitations_v2 c ON c.id=r.invitation_id AND c.scope_id=r.scope_id AND c.token_hash=r.token_hash WHERE r.invitation_id=i.id AND r.scope_id=i.scope_id AND r.token_hash=i.token_hash)) AND state<>'accepted'", [$sid]);
                }
            });
            return;
        }
        $this->change('DELETE FROM familyhub_organization_leaders WHERE scope_id=? AND account_id=?', [$row['scope_id'],$action['accountId']]);
        $member = $this->one('SELECT role FROM familyhub_members WHERE scope_id=? AND account_id=? AND active=1', [$row['scope_id'],$action['accountId']]);
        if ($action['enabled'] &&
            $member &&
            $member['role'] !== 'owner') {
            $this->change('INSERT INTO familyhub_organization_leaders VALUES(?,?)', [$row['scope_id'],$action['accountId']]);
        }
        $this->change('UPDATE familyhub_scopes SET access_revision=access_revision+1,sequence=sequence+1 WHERE id=?', [$row['scope_id']]);
    }

    private function intent($hash, $live = true)
    {
        $row = $this->one('SELECT * FROM familyhub_crypto_access_intents_v2 WHERE intent_hash=?', [$this->hashValue($hash)]);
        if (!$row ||
            $live &&
            (!in_array($row['state'], ['pending','committing'], true) ||
            (int)$row['expires_at'] <= time())) {
            throw new NativeError('crypto_access_intent_expired', 409);
        }
        return $row;
    }

    private function portions($row, callable $visit)
    {
        $after = '';
        do {
            $page = $this->many('SELECT * FROM familyhub_crypto_access_portions_v2 WHERE intent_hash=? AND scope_id>? ORDER BY scope_id LIMIT 20', [$row['intent_hash'],$after]);
            foreach ($page as $portion) {
                $after = $portion['scope_id'];
                $visit($portion);
            }
        } while (count($page) === 20);
    }

    private function affectedRoot($row)
    {
        $after = '';
        $hash = hash_init('sha256');
        $count = 0;
        hash_update($hash, "JivieAccessComponent/v2\n".NativeCryptoCodec::canonical((object)['version' => 2,'serverId' => $this->serverId(),'intentHash' => $row['intent_hash']])."\n");
        do {
            $page = $this->many('SELECT * FROM familyhub_crypto_access_portions_v2 WHERE intent_hash=? AND scope_token>? ORDER BY scope_token LIMIT 20', [$row['intent_hash'],$after]);
            foreach ($page as $portion) {
                $after = $portion['scope_token'];
                hash_update($hash, NativeCryptoCodec::canonical((object)['scopeToken' => $portion['scope_token'],'headHash' => $portion['old_head_hash'],'accessRevision' => (int)$portion['access_revision'],'rawAccessRevision' => (int)$portion['raw_access_revision'],'policyVersion' => (int)$portion['policy_version']])."\n");
                $count++;
            }
        } while (count($page) === 20);
        return ['affectedCount' => $count,'affectedHash' => hash_final($hash)];
    }

    private function assertBase($row, $final = false)
    {
        (new NativeCryptoLeaveV2($this->container,$this->bearer,$this->ip))->validatePlan($row);
        $this->consequenceFrame($row,$final);
        $after = '';
        $hash = hash_init('sha256');
        $count = 0;
        do {
            $page = $this->many('SELECT * FROM familyhub_scopes WHERE (id=? OR parent_scope_id=? OR organization_id=?) AND id>? AND deleted_at IS NULL ORDER BY id LIMIT 20', [$row['scope_id'],$row['scope_id'],$row['scope_id'],$after]);
            foreach ($page as $scope) {
                $after = $scope['id'];
                $portion = $this->one('SELECT * FROM familyhub_crypto_access_portions_v2 WHERE intent_hash=? AND scope_id=?', [$row['intent_hash'],$scope['id']]);
                $head = $this->scopes()->current($scope['id']);
                $owner = $this->ownerScope($scope['id']);
                if (!$portion ||
            !$head ||
            $head['head_hash'] !== $portion['old_head_hash'] ||
            (int)$scope['access_revision'] !== (int)$portion['raw_access_revision'] ||
            (int)$owner['effective_access_revision'] !== (int)$portion['access_revision'] ||
            (int)$scope['access_policy_version'] !== (int)$portion['policy_version']) {
                    throw new NativeError('crypto_access_component_changed', 409);
                }
                $basis = json_decode($portion['access_basis'], true, 34, JSON_THROW_ON_ERROR);
                if (NativeCryptoCodec::canonical($basis) !== NativeCryptoCodec::canonical($this->scopes()->accessBasis($owner))) {
                    throw new NativeError('crypto_access_component_changed', 409);
                }
                hash_update($hash, NativeCryptoCodec::canonical((object)['scopeToken' => $portion['scope_token'],'headHash' => $portion['old_head_hash'],'accessRevision' => (int)$portion['access_revision'],'rawAccessRevision' => (int)$portion['raw_access_revision'],'policyVersion' => (int)$portion['policy_version']])."\n");
                $count++;
            }
        } while (count($page) === 20);
        $root = $this->affectedRoot($row);
        if ($count !== (int)$row['affected_count'] ||
            $root['affectedCount'] !== $count ||
            $root['affectedHash'] !== $row['affected_hash']) {
            throw new NativeError('crypto_access_component_changed', 409);
        }
    }

    private function future($row, callable $work)
    {
        if ($row['state'] === 'committing') {
            return $work();
        }
        $memo=$this->memoKey($row);
        if (isset(self::$simulations[$memo])) {
            return $work();
        }
        if (!isset(self::$validatedBases[$memo])) {
            $this->assertBase($row);
        }
        $frame=$this->consequenceFrame($row);
        if ($frame!==null) self::$simulationConsequences[$memo]=$frame;
        $this->pdo->exec('SAVEPOINT crypto2_access_future');
        try {
            $this->apply($row);
            self::$simulations[$memo]=true;
            return $work();
        } finally {
            unset(self::$simulations[$memo],self::$simulationConsequences[$memo]);
            $this->pdo->exec('ROLLBACK TO SAVEPOINT crypto2_access_future');
            $this->pdo->exec('RELEASE SAVEPOINT crypto2_access_future');
        }
    }

    public function preview($body, callable $work)
    {
        $proof = $body['accessIntentProof'] ?? null;
        if ($proof === null) {
            return $work();
        }
        [$consent] = NativeCryptoCodec::decode($proof);
        $row = $this->intent($consent['intentHash'] ?? null, false);
        if ($row['state'] === 'applied') {
            // Historical key reads use present ACL, never reapply an old action.
            return $work();
        }
        return $this->future($this->intent($consent['intentHash']), $work);
    }

    public function expiresAt($body)
    {
        if (($body['accessIntentProof'] ?? null) === null) {
            return null;
        }
        [$consent] = NativeCryptoCodec::decode($body['accessIntentProof']);
        try {
            return (int)$this->intent($consent['intentHash'])['expires_at'];
        } catch (NativeError $error) {
            if ($error->status === 409) {
                return 0;
            }
            throw $error;
        }
    }

    public function validateHead($scope, $body, $current, $actor)
    {
        if (!$current ||
            ($body['financePolicyIntentProof'] ?? null) !== null ||
            $body['membershipIntents'] !== []) {
            throw new NativeError('crypto_access_intent_invalid', 409);
        }
        [$consent,$bytes,$signature] = NativeCryptoCodec::decode($body['accessIntentProof']);
        $this->fields($consent, ['version','operation','serverId','scopeId','intentHash','affectedCount','affectedHash','previousHeadHash','expectedAccessRevision','accessBasis','resultingAccessRevision','resultingDescriptor','resultingFinancePolicy','membersHash','accountId','deviceId','authorDirectoryHeadHash'], ['invitationConsequences']);
        $this->fields($consent['resultingFinancePolicy'], ['revision','policyHash']);
        if (!is_int($consent['resultingFinancePolicy']['revision']) ||
            $consent['resultingFinancePolicy']['revision'] < 0 ||
            $consent['resultingFinancePolicy']['revision'] > 9007199254740991) {
            throw new NativeError('crypto_access_intent_invalid',409);
        }
        $this->hashValue($consent['resultingFinancePolicy']['policyHash']);
        $row = $this->intent($consent['intentHash']);
        $consequences=$this->consequenceFrame($row);
        $expectedConsequences=$consequences['scoped'][$scope['id']]??null;
        if ($expectedConsequences===null ? array_key_exists('invitationConsequences',$consent) :
            (!isset($consent['invitationConsequences']) || NativeCryptoCodec::canonical((object)$consent['invitationConsequences'])!==NativeCryptoCodec::canonical((object)$expectedConsequences))) {
            throw new NativeError('crypto_access_consequences_changed',409);
        }
        $portion = $this->one('SELECT * FROM familyhub_crypto_access_portions_v2 WHERE intent_hash=? AND scope_id=?', [$row['intent_hash'],$scope['id']]);
        if (!$portion ||
            $consent['version'] !== 2 ||
            $consent['operation'] !== 'crypto2.access.scopeConsent' ||
            $consent['serverId'] !== $this->serverId() ||
            $consent['scopeId'] !== $scope['id'] ||
            $consent['accountId'] !== $actor['user']['account_id'] ||
            $consent['deviceId'] !== $actor['device']['id'] ||
            $consent['authorDirectoryHeadHash'] !== $body['authorDirectoryHeadHash'] ||
            $consent['previousHeadHash'] !== $current['head_hash'] ||
            $portion['old_head_hash'] !== $current['head_hash'] ||
            $consent['affectedCount'] !== (int)$row['affected_count'] ||
            $consent['affectedHash'] !== $row['affected_hash'] ||
            $consent['membersHash'] !== NativeCryptoV2Codec::hash($body['members']) ||
            $consent['expectedAccessRevision'] !== (int)$portion['access_revision'] ||
            $body['expectedAccessRevision'] !== (int)$portion['access_revision'] ||
            NativeCryptoCodec::canonical($body['accessBasis']) !== $portion['access_basis'] ||
            $consent['accessBasis'] !== $body['accessBasis']) {
            throw new NativeError('crypto_access_intent_invalid', 409);
        }
        $this->scopes()->currentAuthorReference($consent['authorDirectoryHeadHash'], $actor);
        $directory = new NativeCryptoDirectoryV2($this->container);
        $command = ['signer' => 'device','deviceId' => $actor['device']['id']];
        $key = $directory->authorizeContent($command, $directory->current($actor['user']['account_id']));
        NativeCryptoV2Codec::verify($bytes, $signature, $key, "JivieE2EE/accessScopeConsent/v2\n");
        $future = $this->future($row, function () use ($scope, $body, $consent) {
            $future = $this->ownerScope($scope['id']);
            $policy = (new NativeCryptoFinancePolicyV2($this->container))->policy($scope['id']);
            if ($consent['resultingFinancePolicy']['revision'] !== $policy['revision'] ||
                $consent['resultingFinancePolicy']['policyHash'] !== $policy['policyHash']) {
                throw new NativeError('crypto_access_intent_invalid',409);
            }
            if ($body['accessRevision'] !== (int)$future['effective_access_revision'] ||
            $consent['resultingAccessRevision'] !== $body['accessRevision'] ||
            NativeCryptoCodec::canonical((object)$consent['resultingDescriptor']) !== NativeCryptoCodec::canonical((object)$this->descriptor($future))) {
                throw new NativeError('crypto_access_intent_invalid', 409);
            }
            $prepared=new NativeCryptoInvitationPreauthorizationV5($this->container);
            $conditions=$prepared->validatePreauthorizations($future,$body);
            $prepared->synchronize($future,$conditions,$body['members']);
            $this->scopes()->assertMembershipParity($future, $body['members']);
            return $future;
        });
        return ['changed' => false,'transfer' => false,'accessTransition' => true,'futureScope' => $future,'actual' => [],'desired' => $body['members'],'additions' => [],'invitationPreauthorizations'=>$body['invitationPreauthorizations']??[]];
    }

    public function write($op, $p, $actor, $proof, $command)
    {
        if ($op === 'crypto2.access.prepare') {
            $this->fields($p, ['scopeId','membershipHeadHash','expectedAccessRevision','authorDirectoryHeadHash','action'], ['consequenceSnapshot','leaveRequestHash']);
            $scope = $this->scope($this->uuid($p['scopeId']), $actor['user']['id'], false, true);
            $head = $this->scopes()->current($scope['id']);
            $this->scopes()->manager($head, $scope, $actor);
            $this->scopes()->currentAuthorReference($p['authorDirectoryHeadHash'], $actor);
            if (($p['action']['kind'] ?? null) !== 'memberRemove' && $scope['role'] !== 'owner' ||
            !$head ||
            $head['head_hash'] !== $p['membershipHeadHash'] ||
            $p['expectedAccessRevision'] !== (int)$scope['effective_access_revision']) {
                throw new NativeError('crypto_access_changed', 409);
            }
            NativeCryptoScopeCreationV2::guardBusiness($this->pdo, $scope['id']);
            $this->action($scope, $p['action']);
            if (array_key_exists('leaveRequestHash',$p)) {
                if (($p['action']['kind']??null)!=='memberRemove') throw new NativeError('validation_error');
                (new NativeCryptoLeaveV2($this->container,$this->bearer,$this->ip))->assertPending($p['leaveRequestHash'],$scope['id'],$p['action']['accountId']);
            }
            $revokes=($p['action']['kind']??null)==='accessPolicy' && ($p['action']['targetVersion']??null)===3;
            if ($revokes) {
                $frame=(new NativeCryptoAccessConsequencesV2($this->container))->collect($scope['id'],$command['requestId']);
                if (!isset($p['consequenceSnapshot']) || NativeCryptoCodec::canonical((object)$p['consequenceSnapshot'])!==NativeCryptoCodec::canonical((object)$frame['snapshot'])) throw new NativeError('crypto_access_consequences_changed',409);
            } elseif (array_key_exists('consequenceSnapshot',$p)) {
                throw new NativeError('validation_error');
            }
            $count = $this->one("SELECT COUNT(*) n FROM familyhub_crypto_access_intents_v2 WHERE scope_id=? AND state='pending' AND expires_at>?", [$scope['id'],time()]);
            if ((int)$count['n'] >= 16) {
                throw new NativeError('crypto_access_intents_full', 409);
            }
            $hash = NativeCryptoV2Codec::hash((object)$proof);
            $this->change('INSERT INTO familyhub_crypto_access_intents_v2 VALUES(?,?,?,?,?,?,?,?,?,?,?)', [$hash,$scope['id'],$actor['user']['account_id'],$actor['device']['id'],json_encode($p['action'], JSON_THROW_ON_ERROR),json_encode($proof, JSON_THROW_ON_ERROR),0,NativeCryptoDirectoryV2::ZERO,time(),time() + 1800,'pending']);
            $digest = hash_init('sha256');
            $affected = 0;
            $after = '';
            do {
                $page = $this->many('SELECT * FROM familyhub_scopes WHERE (id=? OR parent_scope_id=? OR organization_id=?) AND id>? AND deleted_at IS NULL ORDER BY id LIMIT 20', [$scope['id'],$scope['id'],$scope['id'],$after]);
                foreach ($page as $raw) {
                    $after = $raw['id'];
                    $source = $this->scopes()->current($raw['id']);
                    if (!$source) {
                        throw new NativeError('crypto_child_genesis_pending', 409);
                    }
                    $owner = $this->ownerScope($raw['id']);
                    if ((int)$raw['access_revision'] >= 9007199254740991 ||
            (int)$owner['effective_access_revision'] >= 9007199254740991) {
                        throw new NativeError('crypto_access_revision_exhausted', 409);
                    }
                    $token = $this->token($raw['id'], $scope['id']);
                    $basis = NativeCryptoCodec::canonical($this->scopes()->accessBasis($owner));
                    $this->change('INSERT INTO familyhub_crypto_access_portions_v2 VALUES(?,?,?,?,?,?,?,?,NULL,NULL)', [$hash,$raw['id'],$token,$source['head_hash'],(int)$owner['effective_access_revision'],(int)$raw['access_revision'],(int)$raw['access_policy_version'],$basis]);
                    hash_update($digest, NativeCryptoCodec::canonical((object)['scopeToken' => $token,'headHash' => $source['head_hash'],'accessRevision' => (int)$owner['effective_access_revision'],'rawAccessRevision' => (int)$raw['access_revision'],'policyVersion' => (int)$raw['access_policy_version']])."\n");
                    $affected++;
                }
            } while (count($page) === 20);
            $root = $this->affectedRoot(['intent_hash' => $hash])['affectedHash'];
            $this->change('UPDATE familyhub_crypto_access_intents_v2 SET affected_count=?,affected_hash=? WHERE intent_hash=?', [$affected,$root,$hash]);
            return ['intentHash' => $hash,'affectedCount' => $affected,'affectedHash' => $root,'expiresAt' => time() + 1800];
        }
        $this->fields($p, $op === 'crypto2.access.approve' ? ['intentHash','scopeId','activationProof'] : ['intentHash','affectedCount','affectedHash']);
        $row = $this->intent($p['intentHash'], $op !== 'crypto2.access.cancel');
        if ($op === 'crypto2.access.approve') {
            $sid = $this->uuid($p['scopeId']);
            $scope = $this->scope($sid, $actor['user']['id'], false, true);
            $head = $this->scopes()->current($sid);
            $this->scopes()->manager($head, $scope, $actor);
            [$activation,$bytes,$signature] = NativeCryptoCodec::decode($p['activationProof']);
            $this->fields($activation, ['version','operation','requestId','serverId','accountId','deviceId','signer','payload']);
            if ($activation['version'] !== 2 ||
            $activation['operation'] !== 'crypto2.scope.activate' ||
            $activation['serverId'] !== $this->serverId() ||
            $activation['accountId'] !== $actor['user']['account_id'] ||
            $activation['deviceId'] !== $actor['device']['id'] ||
            $activation['signer'] !== 'device' ||
            ($activation['payload']['scopeId'] ?? null) !== $sid) {
                throw new NativeError('crypto_access_approval_invalid', 403);
            }
            $this->uuid($activation['requestId']);
            if (($activation['payload']['accessIntentHash'] ?? null) !== $row['intent_hash'] ||
            ($activation['payload']['affectedCount'] ?? null) !== (int)$row['affected_count'] ||
            ($activation['payload']['affectedHash'] ?? null) !== $row['affected_hash']) {
                throw new NativeError('crypto_access_intent_invalid', 409);
            }
            if ($this->one('SELECT request_id FROM familyhub_crypto_receipts WHERE account_id=? AND request_id=?', [$activation['accountId'],$activation['requestId']])) {
                throw new NativeError('crypto_access_activation_nonce_used', 409);
            }
            $this->portions($row, function ($portion) use ($activation, $sid) {
                if ($portion['scope_id'] === $sid ||
            $portion['approval'] === null) {
                    return;
                }
                [$other] = NativeCryptoCodec::decode(json_decode($portion['approval'], true, 34, JSON_THROW_ON_ERROR));
                if ($other['accountId'] === $activation['accountId'] &&
            $other['requestId'] === $activation['requestId']) {
                    throw new NativeError('crypto_access_activation_nonce_used', 409);
                }
            });
            $directory = new NativeCryptoDirectoryV2($this->container);
            NativeCryptoV2Codec::verify($bytes, $signature, $directory->authorizeContent($activation, $directory->current($actor['user']['account_id'])));
            $candidate = $this->scopes()->head($sid, $activation['payload']['headHash']);
            $this->validateHead($scope, $this->scopes()->body($candidate), $head, $actor);
            $old = $this->one('SELECT approval FROM familyhub_crypto_access_portions_v2 WHERE intent_hash=? AND scope_id=?', [$row['intent_hash'],$sid]);
            if ($old &&
            $old['approval'] !== null &&
            json_decode($old['approval'], true, 34, JSON_THROW_ON_ERROR) !== $p['activationProof']) {
                throw new NativeError('crypto_access_approval_immutable', 409);
            }
            $this->change('UPDATE familyhub_crypto_access_portions_v2 SET approval=? WHERE intent_hash=? AND scope_id=?', [json_encode($p['activationProof'], JSON_THROW_ON_ERROR),$row['intent_hash'],$sid]);
            return ['intentHash' => $row['intent_hash'],'scopeId' => $sid,'state' => 'approved'];
        }
        if ($row['account_id'] !== $actor['user']['account_id'] ||
            $p['affectedCount'] !== (int)$row['affected_count'] ||
            $p['affectedHash'] !== $row['affected_hash']) {
            throw new NativeError('permission_revoked', 403);
        }
        if ($op === 'crypto2.access.cancel') {
            if ($row['state']==='applied') {
                throw new NativeError('crypto_access_intent_applied',409);
            }
            $this->change("UPDATE familyhub_crypto_access_intents_v2 SET state='cancelled' WHERE intent_hash=?", [$row['intent_hash']]);
            $cleanup=0;
            $this->portions($row,function($portion)use(&$cleanup){
                $current=$this->scopes()->current($portion['scope_id']);
                $this->scopes()->refreshPending($portion['scope_id'],$current);
                if ($this->scopes()->closedDomains($portion['scope_id'],$current['head_hash']??null)) {$cleanup++;}
            });
            return ['intentHash' => $row['intent_hash'],'state' => 'cancelled','cleanupRequired'=>$cleanup>0,'cleanupCount'=>$cleanup];
        }
        $scope = $this->scope($row['scope_id'], $actor['user']['id'], false, true);
        $this->scopes()->manager($this->scopes()->current($scope['id']), $scope, $actor);
        [$prepare] = NativeCryptoCodec::decode(json_decode($row['authorization'], true, 34, JSON_THROW_ON_ERROR));
        $this->scopes()->currentAuthorReference($prepare['payload']['authorDirectoryHeadHash'], ['user' => $actor['user'],'device' => ['id' => $row['device_id']]]);
        $this->assertBase($row);
        if ($op !== 'crypto2.access.activate') {
            throw new NativeError('unsupported_operation', 404);
        }
        $memo=$this->memoKey($row);
        self::$validatedBases[$memo]=true;
        try {
            return $this->activateValidated($row);
        } finally {
            unset(self::$validatedBases[$memo],self::$finalConsequences[$memo]);
        }
    }

    private function activateValidated($row)
    {
        $this->portions($row, function ($portion) {
            if ($portion['approval'] === null) {
                throw new NativeError('crypto_access_approval_required', 409);
            }
            $proof = json_decode($portion['approval'], true, 34, JSON_THROW_ON_ERROR);
            [$activation,$bytes,$signature] = NativeCryptoCodec::decode($proof);
            if ($this->one('SELECT request_id FROM familyhub_crypto_receipts WHERE account_id=? AND request_id=?', [$activation['accountId'],$activation['requestId']])) {
                throw new NativeError('crypto_access_activation_nonce_used', 409);
            }
            $user = $this->one('SELECT a.account_id,u.* FROM familyhub_accounts a JOIN users u ON u.id=a.user_id WHERE a.account_id=? AND u.is_active=1', [$activation['accountId']]);
            if (!$user) {
                throw new NativeError('permission_revoked', 403);
            }
            $author = ['user' => $user,'device' => ['id' => $activation['deviceId']]];
            $scope = $this->scope($portion['scope_id'], $user['id'], false, true);
            $head = $this->scopes()->current($scope['id']);
            $this->scopes()->manager($head, $scope, $author);
            $directory = new NativeCryptoDirectoryV2($this->container);
            $key = $directory->authorizeContent($activation, $directory->current($activation['accountId']));
            NativeCryptoV2Codec::verify($bytes, $signature, $key);
            $candidate = $this->scopes()->head($scope['id'], $activation['payload']['headHash']);
            $this->validateHead($scope, $this->scopes()->body($candidate), $head, $author);
            $safe = array_intersect_key($scope, array_flip(['id','kind','role','owner_id','effective_access_policy_version','effective_access_revision','access_policy_version','access_revision','parent_scope_id','organization_id']));
            $this->change('UPDATE familyhub_crypto_access_portions_v2 SET approval_scope=? WHERE intent_hash=? AND scope_id=?', [json_encode($safe, JSON_THROW_ON_ERROR),$portion['intent_hash'],$portion['scope_id']]);
        });
        // Preserve a full final CAS after all approval validation, immediately
        // before the one intentional apply. Approval caches are not authority.
        $this->assertBase($row,true);
        $frame=$this->consequenceFrame($row);
        if ($frame!==null) self::$finalConsequences[$this->memoKey($row)]=$frame;
        $this->change("UPDATE familyhub_crypto_access_intents_v2 SET state='committing' WHERE intent_hash=?", [$row['intent_hash']]);
        unset(self::$validatedBases[$this->memoKey($row)]);
        $this->apply($row);
        $this->portions($row, function ($portion) use ($row) {
            $proof = json_decode($portion['approval'], true, 34, JSON_THROW_ON_ERROR);
            [$activation] = NativeCryptoCodec::decode($proof);
            $user = $this->one('SELECT a.account_id,u.* FROM familyhub_accounts a JOIN users u ON u.id=a.user_id WHERE a.account_id=? AND u.is_active=1', [$activation['accountId']]);
            $author = ['user' => $user,'device' => ['id' => $activation['deviceId']]];
            $scope = json_decode($portion['approval_scope'], true, 34, JSON_THROW_ON_ERROR);
            $directory = new NativeCryptoDirectoryV2($this->container);
            $key = $directory->authorizeContent($activation, $directory->current($activation['accountId']));
            $result = $this->scopes()->activateAccess($row['intent_hash'], $scope, $author, $activation, $proof, $key);
            [,,$signature,$digest] = NativeCryptoCodec::decode($proof);
            $this->change('INSERT INTO familyhub_crypto_receipts VALUES(?,?,?,?,?,?,?)', [$activation['accountId'],$activation['requestId'],$digest,json_encode($result, JSON_THROW_ON_ERROR),200,time(),json_encode($proof, JSON_THROW_ON_ERROR)]);
        });
        (new NativeCryptoLeaveV2($this->container,$this->bearer,$this->ip))->completePlan($row);
        $this->change("UPDATE familyhub_crypto_access_intents_v2 SET state='applied' WHERE intent_hash=?", [$row['intent_hash']]);
        return ['intentHash' => $row['intent_hash'],'state' => 'applied','affectedCount' => (int)$row['affected_count'],'affectedHash' => $row['affected_hash']];
    }

    public function directoryReference($sid, $target, $actor)
    {
        $scope = $this->scope($sid, $actor['user']['id'], false, true);
        $this->scopes()->manager($this->scopes()->current($sid), $scope, $actor);
        $rows = $this->many("SELECT i.* FROM familyhub_crypto_access_intents_v2 i JOIN familyhub_crypto_access_portions_v2 p ON p.intent_hash=i.intent_hash WHERE p.scope_id=? AND i.state='pending' AND i.expires_at>? ORDER BY i.intent_hash LIMIT 16", [$sid,time()]);
        foreach ($rows as $row) {
            $visible = $this->future($row, fn () => (new NativeOrganizationAccess($this->container))->visibleScope($sid, $target));
            if ($visible) {
                $directory = (new NativeCryptoDirectoryV2($this->container))->current($target);
                return $directory['head_hash'] ?? null;
            }
        }
        return null;
    }

    public function read($op, $p, $actor)
    {
        if ($op==='crypto2.access.consequences' || $op==='crypto2.access.invitationConsequences') {
            $global=$op==='crypto2.access.consequences';
            $this->fields($p,$global ? ['scopeId','membershipHeadHash','requestId'] : ['scopeId','intentHash'],['afterHash','limit']);
            $scope=$this->scope($this->uuid($p['scopeId']),$actor['user']['id'],false,true);
            $head=$this->scopes()->current($scope['id']);
            $this->scopes()->manager($head,$scope,$actor);
            if ($global) {
                if ($scope['role']!=='owner' || !$head || $head['head_hash']!==$p['membershipHeadHash']) throw new NativeError('permission_revoked',403);
                $requestId=$this->uuid($p['requestId']);
                $root=$scope['id'];
                $frame=(new NativeCryptoAccessConsequencesV2($this->container))->collect($root,$requestId);
                $entries=$frame['leaves'];
            } else {
                $intent=$this->intent($p['intentHash']);
                $portion=$this->one('SELECT scope_id FROM familyhub_crypto_access_portions_v2 WHERE intent_hash=? AND scope_id=?',[$intent['intent_hash'],$scope['id']]);
                if (!$portion) throw new NativeError('permission_revoked',403);
                $root=$intent['scope_id'];
                $frame=$this->consequenceFrame($intent);
                if ($frame===null) throw new NativeError('crypto_access_consequences_not_applicable',409);
                [$prepare]=NativeCryptoCodec::decode(json_decode($intent['authorization'],true,34,JSON_THROW_ON_ERROR));
                $requestId=$prepare['requestId'];
                $entries=[];
                foreach ($frame['entries'][$scope['id']] as $hash=>$entry) $entries[$hash]=['scopeId'=>$scope['id'],'entry'=>$entry];
            }
            $after=isset($p['afterHash']) ? $this->hashValue($p['afterHash']) : '';
            $limit=$p['limit']??20;
            if (!is_int($limit) || $limit<1 || $limit>20) throw new NativeError('validation_error');
            $out=[];$more=false;$next=null;$authorized=[];
            foreach ($entries as $hash=>$value) {
                if (strcmp($hash,$after)<=0) continue;
                if (count($out)===$limit) {$more=true;break;}
                $sid=$value['scopeId'];
                if (!array_key_exists($sid,$authorized)) {
                    $visible=(new NativeOrganizationAccess($this->container))->visibleScope($sid,$actor['user']['account_id']);
                    $authorized[$sid]=false;
                    if ($visible) {
                        try {$this->scopes()->manager($this->scopes()->current($sid),$visible,$actor);$authorized[$sid]=true;}
                        catch (NativeError $ignored) {}
                    }
                }
                $item=['leafHash'=>$hash];
                if (!$global || $authorized[$sid]) $item['invitation']=['scopeToken'=>$this->token($sid,$root),'kind'=>$value['entry']['kind'],'id'=>$value['entry']['id']];
                $out[]=$item;$next=$hash;
            }
            return ['requestId'=>$requestId,'scopeToken'=>$this->token($scope['id'],$root),
                'consequenceSnapshot'=>$global ? $frame['snapshot'] : null,
                'invitationConsequences'=>$global ? null : $frame['scoped'][$scope['id']],
                'entries'=>$out,'hasMore'=>$more,'nextAfterHash'=>$next];
        }
        if ($op === 'crypto2.access.portions') {
            $this->fields($p, ['intentHash'], ['afterToken','limit']);
            $row = $this->intent($p['intentHash'],false);
            if ($row['account_id'] !== $actor['user']['account_id']) {
                throw new NativeError('permission_revoked', 403);
            }
            $scope = $this->scope($row['scope_id'], $actor['user']['id'], false, true);
            $this->scopes()->manager($this->scopes()->current($scope['id']), $scope, $actor);
            $after = isset($p['afterToken']) ? $this->hashValue($p['afterToken']) : '';
            $limit = $p['limit'] ?? 20;
            if (!is_int($limit) ||
            $limit < 1 ||
            $limit > 20) {
                throw new NativeError('validation_error');
            }
            $rows = $this->many('SELECT * FROM familyhub_crypto_access_portions_v2 WHERE intent_hash=? AND scope_token>? ORDER BY scope_token LIMIT '.($limit + 1), [$row['intent_hash'],$after]);
            $page = array_slice($rows, 0, $limit);
            $descriptors = [];
            foreach ($page as $portion) {
                $current=$this->scopes()->current($portion['scope_id']);
                $descriptors[] = ['scopeToken' => $portion['scope_token'],'headHash' => $portion['old_head_hash'],'accessRevision' => (int)$portion['access_revision'],'rawAccessRevision' => (int)$portion['raw_access_revision'],'policyVersion' => (int)$portion['policy_version'],'approvalHash' => $portion['approval'] === null ? null : NativeCryptoV2Codec::hash((object)json_decode($portion['approval'], true, 34, JSON_THROW_ON_ERROR)),
                    'cleanupRequired'=>(bool)$this->scopes()->closedDomains($portion['scope_id'],$current['head_hash']??null)];
            }
            return ['intentHash' => $row['intent_hash'],'affectedCount' => (int)$row['affected_count'],'affectedHash' => $row['affected_hash'],'portions' => $descriptors,'hasMore' => count($rows) > $limit,'nextAfterToken' => $page ? end($page)['scope_token'] : null];
        }
        $this->fields($p, ['scopeId'], ['intentHash','afterHash','limit']);
        $scope = $this->scope($this->uuid($p['scopeId']), $actor['user']['id'], false, true);
        $this->scopes()->manager($this->scopes()->current($scope['id']), $scope, $actor);
        $after = isset($p['afterHash']) ? $this->hashValue($p['afterHash']) : '';
        $limit = $p['limit'] ?? 20;
        if (!is_int($limit) ||
            $limit < 1 ||
            $limit > 20) {
            throw new NativeError('validation_error');
        }
        $rows = $this->many("SELECT i.* FROM familyhub_crypto_access_intents_v2 i JOIN familyhub_crypto_access_portions_v2 p ON p.intent_hash=i.intent_hash WHERE p.scope_id=? AND i.state='pending' AND i.expires_at>? AND i.intent_hash>? ORDER BY i.intent_hash LIMIT ".($limit + 1), [$scope['id'],time(),$after]);
        $page = array_slice($rows, 0, $limit);
        $result = [];
        foreach ($page as $row) {
            $portion = $this->one('SELECT * FROM familyhub_crypto_access_portions_v2 WHERE intent_hash=? AND scope_id=?', [$row['intent_hash'],$scope['id']]);
            $frame=$this->consequenceFrame($row);
            $ownConsequence=$frame['scoped'][$scope['id']]??null;
            $future = $this->future($row, function () use ($scope,$ownConsequence) {
                $future = $this->ownerScope($scope['id']);
                $members = [];
                $effectiveMembers=$this->scopes()->effectiveMembers($scope['id']);
                $projectedPolicies=array_filter($effectiveMembers,fn($m)=>!empty($m['invitationPreauthorization']))?(new NativeCryptoInvitationPreauthorizationV5($this->container))->projectedPolicies($scope['id']):[];
                foreach ($effectiveMembers as $member) {
                    $user = $this->one('SELECT a.account_id,u.* FROM familyhub_accounts a JOIN users u ON u.id=a.user_id WHERE a.account_id=?', [$member['accountId']]);
                    $finance = (!empty($member['invitationPreauthorization'])?($projectedPolicies[$member['accountId']]??null):null)??(new NativeFinanceAccess($this->container))->policyForCrypto($scope['id'], $user, false, false);
                    $members[] = ['accountId' => $member['accountId'],'role' => $member['role'],'financeRole' => $finance['enabled'] ? $finance['grant'] : 'none','manageKeys' => $member['role'] === 'owner' || (int)$future['effective_access_policy_version'] === 3 && $member['role'] === 'member'];
                }
                $policy = (new NativeCryptoFinancePolicyV2($this->container))->policy($scope['id']);
                return ['descriptor' => $this->descriptor($future),'accessRevision' => (int)$future['effective_access_revision'],'members' => $members,
                    'financePolicy'=>['revision'=>$policy['revision'],'policyHash'=>$policy['policyHash']],
                    'invitationConsequences'=>$ownConsequence];
            });
            $result[] = ['intentHash' => $row['intent_hash'],'affectedCount' => (int)$row['affected_count'],'affectedHash' => $row['affected_hash'],'expiresAt' => (int)$row['expires_at'],'scopeId' => $scope['id'],'previousHeadHash' => $portion['old_head_hash'],'expectedAccessRevision' => (int)$portion['access_revision'],'accessBasis' => json_decode($portion['access_basis'],true,34,JSON_THROW_ON_ERROR),'future' => $future,'state' => $portion['approval'] === null ? 'approvalRequired' : 'approved'];
        }
        $current=$this->scopes()->current($scope['id']);
        $closed=$this->scopes()->closedDomains($scope['id'],$current['head_hash']??null);
        return ['intents' => $result,'hasMore' => count($rows) > $limit,'nextAfterHash' => $page ? end($page)['intent_hash'] : null,
            'cleanupRequired'=>(bool)$closed,'closedDomains'=>$closed];
    }
}
