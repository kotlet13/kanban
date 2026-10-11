<?php
namespace Kanboard\Plugin\FamilyHub\Model;

class NativeFinanceSettings extends NativeDatabase
{
    /** Caller already holds transaction/user lock. */
    public function changePolicy($operation, $params, $user)
    {
        $this->fields($params, $operation === 'finance.enable' ? ['scopeId', 'enabled', 'requestId'] : ['scopeId', 'accountId', 'grant', 'requestId']);
        $scope = $this->uuid($params['scopeId']); $authorized = $this->scope($scope, $user['id'], false, true);
        if ($authorized['kind'] === 'personal') { throw new NativeError('personal_not_shareable', 403); }
        if ($operation==='finance.enable' && ($params['enabled']??null)===false && (int)($authorized['effective_access_policy_version']??1)>=2) { throw new NativeError('managed_by_organization_policy',409); }
        $request = $this->uuid($params['requestId']); $hash = $this->hashRequest($operation, $params);
        $replay = $this->replayFinance($scope, $user['account_id'], $request, $hash); if ($replay) { return $replay['body']; }
        $insert = $this->sqlite ? 'INSERT OR IGNORE' : 'INSERT IGNORE'; $this->change($insert.' INTO familyhub_finance_policy(scope_id,enabled,revision,sequence) VALUES(?,0,0,0)', [$scope]);
        if ($operation === 'finance.enable') {
            if (!is_bool($params['enabled'])) { throw new NativeError('validation_error'); }
            $this->change('UPDATE familyhub_finance_policy SET enabled=?,revision=revision+1 WHERE scope_id=?', [(int)$params['enabled'], $scope]);
            if ($params['enabled']) { $this->grant($scope, $user['account_id'], 'write'); }
            $affected = array_column($this->many('SELECT account_id FROM familyhub_members WHERE scope_id=?', [$scope]), 'account_id');
        } else {
            $account = $this->uuid($params['accountId']);
            if (!in_array($params['grant'], ['none', 'read', 'write'], true)) { throw new NativeError('validation_error'); }
            $member = $this->one('SELECT m.role FROM familyhub_members m JOIN familyhub_accounts a ON a.account_id=m.account_id AND a.user_id=m.user_id JOIN users u ON u.id=a.user_id WHERE m.scope_id=? AND m.account_id=? AND m.active=1 AND u.is_active=1', [$scope, $account]);
            if ((int)$authorized['effective_access_policy_version']===3) { $member=(new NativeOrganizationAccess($this->container))->visibleScope($scope,$account); }
            if (!$member || ($member['role'] === 'viewer' && $params['grant'] === 'write')) { throw new NativeError('invalid_finance_grant'); }
            $this->grant($scope, $account, $params['grant']);
            $this->change('UPDATE familyhub_finance_policy SET revision=revision+1 WHERE scope_id=?', [$scope]);
            $affected = [$account];
        }
        (new NativeNotificationWriter($this->container))->visibilityChanged($affected);
        $response = (new NativeFinanceAccess($this->container))->policy($scope, $user, false, false); unset($response['sequence']);
        $this->rememberFinance($scope, $user['account_id'], $request, $hash, $response); return $response;
    }

    private function grant($scope, $account, $grant)
    {
        $this->change('DELETE FROM familyhub_finance_grants WHERE scope_id=? AND account_id=?', [$scope, $account]);
        $this->change('INSERT INTO familyhub_finance_grants VALUES(?,?,?)', [$scope, $account, $grant]);
    }

    public function replayFinance($scope, $account, $id, $hash)
    {
        $row = $this->one('SELECT * FROM familyhub_finance_operations WHERE scope_id=? AND account_id=? AND id=?', [$scope, $account, $id]);
        if (!$row) { return null; } if (!hash_equals($row['request_hash'], $hash)) { throw new NativeError('idempotency_mismatch', 409); }
        return ['status' => (int)$row['status'], 'body' => json_decode($row['response'], true, 32, JSON_THROW_ON_ERROR)];
    }

    public function rememberFinance($scope, $account, $id, $hash, $body, $status = 200)
    {
        $this->change('INSERT INTO familyhub_finance_operations VALUES(?,?,?,?,?,?)', [$scope, $account, $id, $hash, json_encode($body, JSON_THROW_ON_ERROR), $status]);
    }
}
