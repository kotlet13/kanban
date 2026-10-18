<?php

namespace Kanboard\Plugin\FamilyHub\Model;

/** Typed finance-only intent. It cannot alter membership or topology authority. */
class NativeCryptoFinancePolicyV2 extends NativeDatabase
{
    protected $cryptoAccess = true;
    public const HASH_DOMAIN = "JivieFinancePolicy/v2\n";

    public function policy($scopeId)
    {
        $row = $this->one('SELECT enabled,revision,required_contract_version FROM familyhub_finance_policy WHERE scope_id=?', [$scopeId]);
        $header = ['enabled'=>(bool)($row['enabled'] ?? false), 'revision'=>(int)($row['revision'] ?? 0), 'requiredContractVersion'=>(int)($row['required_contract_version'] ?? 1)];
        $hash = hash_init('sha256');
        hash_update($hash, self::HASH_DOMAIN.NativeCryptoCodec::canonical((object)$header)."\n");
        $after = '';
        $count = 0;
        do {
            $rows = $this->many('SELECT account_id,access_level FROM familyhub_finance_grants WHERE scope_id=? AND account_id>? ORDER BY account_id LIMIT 50', [$scopeId,$after]);
            foreach ($rows as $grant) {
                hash_update($hash, NativeCryptoCodec::canonical((object)['accountId'=>$grant['account_id'],'grant'=>$grant['access_level']])."\n");
                $after = $grant['account_id'];
                $count++;
            }
        } while (count($rows) === 50);
        hash_update($hash, NativeCryptoCodec::canonical((object)['grantCount'=>$count]));
        return $header + ['policyHash'=>hash_final($hash),'grantCount'=>$count];
    }

    private function authority($p, $actor)
    {
        $scope = $this->scope($this->uuid($p['scopeId']), $actor['user']['id'], false, true);
        if ($scope['kind'] === 'personal') {
            throw new NativeError('personal_not_shareable', 403);
        }
        $scopes = new NativeCryptoScopeV2($this->container, $this->bearer, $this->ip);
        $current = $scopes->current($scope['id']);
        if (!$current || $current['head_hash'] !== $p['membershipHeadHash'] || $p['expectedAccessRevision'] !== (int)$scope['effective_access_revision']) {
            throw new NativeError('crypto_access_changed', 409);
        }
        $scopes->manager($current, $scope, $actor);
        $scopes->currentAuthorReference($p['authorDirectoryHeadHash'], $actor);
        return [$scope,$current];
    }

    public function read($p, $actor)
    {
        $this->fields($p, ['scopeId'], ['afterAccountId','limit']);
        $scope = $this->scope($this->uuid($p['scopeId']), $actor['user']['id'], false, true);
        $scopes = new NativeCryptoScopeV2($this->container, $this->bearer, $this->ip);
        $scopes->manager($scopes->current($scope['id']), $scope, $actor);
        $after = isset($p['afterAccountId']) ? $this->uuid($p['afterAccountId']) : '';
        $limit = $p['limit'] ?? 50;
        if (!is_int($limit) || $limit < 1 || $limit > 50) {
            throw new NativeError('validation_error');
        }
        $rows = $this->many('SELECT account_id,access_level FROM familyhub_finance_grants WHERE scope_id=? AND account_id>? ORDER BY account_id LIMIT '.($limit+1), [$scope['id'],$after]);
        $page = array_slice($rows, 0, $limit);
        return $this->policy($scope['id']) + ['grants'=>array_map(fn($r)=>['accountId'=>$r['account_id'],'grant'=>$r['access_level']], $page),'hasMore'=>count($rows)>$limit,'nextAccountId'=>$page ? end($page)['account_id'] : null];
    }

    private function validateAction($action, $scope)
    {
        if (!is_array($action)) {
            throw new NativeError('validation_error');
        }
        if (($action['kind'] ?? null) === 'enable') {
            $this->fields($action, ['kind','enabled']);
            if (!is_bool($action['enabled'])) {
                throw new NativeError('validation_error');
            }
            if (!$action['enabled'] && (int)$scope['effective_access_policy_version'] >= 2) {
                throw new NativeError('managed_by_organization_policy', 409);
            }
            return;
        }
        if (($action['kind'] ?? null) !== 'grant') {
            throw new NativeError('validation_error');
        }
        $this->fields($action, ['kind','accountId','grant']);
        $this->uuid($action['accountId']);
        if (!in_array($action['grant'], ['none','read','write'], true)) {
            throw new NativeError('validation_error');
        }
        $member = (new NativeOrganizationAccess($this->container))->visibleScope($scope['id'], $action['accountId']);
        if (!$member || $member['role'] === 'viewer' && $action['grant'] === 'write') {
            throw new NativeError('invalid_finance_grant');
        }
    }

    private function applyAction($scopeId, $action, $accountId)
    {
        $insert = $this->sqlite ? 'INSERT OR IGNORE' : 'INSERT IGNORE';
        $this->change($insert.' INTO familyhub_finance_policy(scope_id,enabled,revision,sequence) VALUES(?,0,0,0)', [$scopeId]);
        if ($action['kind'] === 'enable') {
            $this->change('UPDATE familyhub_finance_policy SET enabled=?,revision=revision+1 WHERE scope_id=?', [(int)$action['enabled'],$scopeId]);
            if ($action['enabled']) {
                $this->replaceGrant($scopeId, $accountId, 'write');
            }
        } else {
            $this->replaceGrant($scopeId, $action['accountId'], $action['grant']);
            $this->change('UPDATE familyhub_finance_policy SET revision=revision+1 WHERE scope_id=?', [$scopeId]);
        }
    }

    private function replaceGrant($scopeId, $accountId, $grant)
    {
        $this->change('DELETE FROM familyhub_finance_grants WHERE scope_id=? AND account_id=?', [$scopeId,$accountId]);
        $this->change('INSERT INTO familyhub_finance_grants VALUES(?,?,?)', [$scopeId,$accountId,$grant]);
    }

    /** Explicit pre-capture owner consent, never a general fenced write bypass. */
    public function enableLegacyForMigration($scopeId,$expectedRevision,$actor)
    {
        $scope=$this->scope($this->uuid($scopeId),$actor['user']['id'],false,true);
        if ($scope['role']!=='owner' || $scope['kind']==='personal') {
            throw new NativeError('permission_revoked',403);
        }
        if ($this->one('SELECT head_hash FROM familyhub_crypto_scope_heads WHERE scope_id=? LIMIT 1',[$scopeId])) {
            throw new NativeError('crypto_finance_prepare_restart_required',409);
        }
        $crypto=$this->one('SELECT state FROM familyhub_crypto_scopes WHERE scope_id=?',[$scopeId]);
        if ($crypto && !in_array($crypto['state'],['staged','preparing','aborted'],true)) {
            throw new NativeError('crypto_migration_in_progress',409);
        }
        $before=$this->policy($scopeId);
        if (!is_int($expectedRevision) || $expectedRevision<0 || $expectedRevision>=9007199254740991 || $expectedRevision!==$before['revision']) {
            throw new NativeError('crypto_finance_policy_changed',409);
        }
        $this->applyAction($scopeId,['kind'=>'enable','enabled'=>true],$actor['user']['account_id']);
        return ['previousPolicy'=>$before,'resultingPolicy'=>$this->policy($scopeId)];
    }

    public function propose($p, $actor, $proof, $command)
    {
        $this->fields($p, ['scopeId','membershipHeadHash','expectedAccessRevision','authorDirectoryHeadHash','expectedFinancePolicyRevision','previousPolicyHash','resultingFinancePolicyRevision','resultingPolicyHash','action']);
        [$scope] = $this->authority($p, $actor);
        NativeCryptoScopeCreationV2::guardBusiness($this->pdo,$scope['id']);
        $pending = $this->one("SELECT COUNT(*) AS n FROM familyhub_crypto_finance_policy_intents_v2 i JOIN familyhub_crypto_receipts r ON r.account_id=i.account_id AND r.request_id=i.request_id WHERE i.scope_id=? AND i.state='pending' AND r.created_at>?", [$scope['id'],time()-1800]);
        if ((int)$pending['n'] >= 16) {
            throw new NativeError('crypto_scope_candidates_full',409);
        }
        $this->validateAction($p['action'], $scope);
        $before = $this->policy($scope['id']);
        if (!is_int($p['expectedFinancePolicyRevision']) || $p['expectedFinancePolicyRevision'] < 0 || $p['expectedFinancePolicyRevision'] >= 9007199254740991 || $p['expectedFinancePolicyRevision'] !== $before['revision'] || $p['previousPolicyHash'] !== $before['policyHash']) {
            throw new NativeError('crypto_finance_policy_changed', 409);
        }
        $this->pdo->exec('SAVEPOINT crypto2_finance_policy_preview');
        try {
            $this->applyAction($scope['id'], $p['action'], $actor['user']['account_id']);
            $after = $this->policy($scope['id']);
        } finally {
            $this->pdo->exec('ROLLBACK TO SAVEPOINT crypto2_finance_policy_preview');
            $this->pdo->exec('RELEASE SAVEPOINT crypto2_finance_policy_preview');
        }
        if ($p['resultingFinancePolicyRevision'] !== $after['revision'] || $p['resultingPolicyHash'] !== $after['policyHash']) {
            throw new NativeError('crypto_finance_policy_changed',409);
        }
        $hash = NativeCryptoV2Codec::hash((object)$proof);
        $this->change('INSERT INTO familyhub_crypto_finance_policy_intents_v2 VALUES(?,?,?,?,?,?,?,?)', [$scope['id'],$hash,$command['accountId'],$command['requestId'],json_encode($proof,JSON_THROW_ON_ERROR),$after['revision'],$after['policyHash'],'pending']);
        return ['scopeId'=>$scope['id'],'intentProof'=>$proof,'intentHash'=>$hash,'previousPolicy'=>$before,'resultingPolicy'=>$after];
    }

    public function preview($scope, $body, $current, callable $work)
    {
        if (($body['financePolicyIntentProof'] ?? null) === null) {
            return $work();
        }
        $this->pdo->exec('SAVEPOINT crypto2_finance_policy_authority');
        try {
            $this->applyForHead($scope, $body, $current);
            return $work();
        } finally {
            $this->pdo->exec('ROLLBACK TO SAVEPOINT crypto2_finance_policy_authority');
            $this->pdo->exec('RELEASE SAVEPOINT crypto2_finance_policy_authority');
        }
    }

    public function financeRead($body, $source, $user)
    {
        if (($body['accessIntentProof'] ?? null)!==null) {
            return (new NativeCryptoAccessV2($this->container,$this->bearer,$this->ip))->preview($body,fn()=>(new NativeFinanceAccess($this->container))->policyForCrypto($body['scopeId'],$user,false,true));
        }
        try {
            return (new NativeFinanceAccess($this->container))->policyForCrypto($body['scopeId'], $user, false, true);
        } catch (NativeError $error) {
            if ($error->errorCode !== 'finance_forbidden' || ($body['financePolicyIntentProof'] ?? null) === null) {
                throw $error;
            }
        }
        $scope = $this->scope($body['scopeId'], $user['id']);
        return $this->preview($scope, $body, $source, fn () => (new NativeFinanceAccess($this->container))->policyForCrypto($body['scopeId'], $user, false, true));
    }

    public function expiresAt($body)
    {
        $proof = $body['financePolicyIntentProof'] ?? null;
        if ($proof === null) {
            return null;
        }
        [$command] = NativeCryptoCodec::decode($proof);
        $receipt = $this->one('SELECT created_at,status,authorization FROM familyhub_crypto_receipts WHERE account_id=? AND request_id=?', [$command['accountId'],$command['requestId']]);
        if (!$receipt || (int)$receipt['status'] !== 200 || json_decode($receipt['authorization'],true,34,JSON_THROW_ON_ERROR) !== $proof) {
            return 0;
        }
        return (int)$receipt['created_at'] + 1800;
    }

    /** Called inside the scope simulation or its final activation transaction. */
    public function applyForHead($scope, $body, $current, $consume = false)
    {
        $proof = $body['financePolicyIntentProof'] ?? null;
        if ($proof === null) {
            return;
        }
        if (!$current) {
            throw new NativeError('crypto_finance_policy_intent_unexpected', 409);
        }
        NativeCryptoScopeCreationV2::guardBusiness($this->pdo,$scope['id']);
        [$command,$bytes,$signature] = NativeCryptoCodec::decode($proof);
        $p = $command['payload'];
        $hash = NativeCryptoV2Codec::hash((object)$proof);
        $row = $this->one('SELECT * FROM familyhub_crypto_finance_policy_intents_v2 WHERE scope_id=? AND intent_hash=?', [$scope['id'],$hash]);
        if ($this->expiresAt($body) <= time()) {
            throw new NativeError('crypto_finance_policy_intent_expired',409);
        }
        if (!$row || $row['state'] !== 'pending' || json_decode($row['authorization'],true,34,JSON_THROW_ON_ERROR) !== $proof || $command['operation'] !== 'crypto2.scope.financePolicy.propose' || $p['membershipHeadHash'] !== $current['head_hash']) {
            throw new NativeError('crypto_finance_policy_intent_invalid', 409);
        }
        $user = $this->one('SELECT a.account_id,u.* FROM familyhub_accounts a JOIN users u ON u.id=a.user_id WHERE a.account_id=? AND u.is_active=1', [$command['accountId']]);
        if (!$user) {
            throw new NativeError('permission_revoked',403);
        }
        $actor = ['user'=>$user,'device'=>['id'=>$command['deviceId']]];
        $this->authority($p, $actor);
        $directory = new NativeCryptoDirectoryV2($this->container);
        $key = $directory->authorizeContent($command, $directory->current($command['accountId']));
        NativeCryptoV2Codec::verify($bytes,$signature,$key);
        $before = $this->policy($scope['id']);
        if ($before['revision'] !== $p['expectedFinancePolicyRevision'] || $before['policyHash'] !== $p['previousPolicyHash']) {
            throw new NativeError('crypto_finance_policy_changed',409);
        }
        $this->validateAction($p['action'], $scope);
        $this->applyAction($scope['id'], $p['action'], $command['accountId']);
        $after = $this->policy($scope['id']);
        if ($after['revision'] !== (int)$row['resulting_revision'] || $after['policyHash'] !== $row['resulting_hash']) {
            throw new NativeError('crypto_finance_policy_changed',409);
        }
        if ($consume) {
            $this->change("UPDATE familyhub_crypto_finance_policy_intents_v2 SET state='consumed' WHERE scope_id=? AND intent_hash=? AND state='pending'", [$scope['id'],$hash]);
        }
    }
}
