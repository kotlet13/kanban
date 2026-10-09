<?php
namespace Kanboard\Plugin\FamilyHub\Model;

/** Financial ACL is a separate gate, including for historical references and errors. */
class NativeFinanceAccess extends NativeDatabase
{
    public function policy($scopeId, array $user, $write = false, $require = true)
    {
        $scope = $this->scope($scopeId, $user['id']);
        $policy = $this->one('SELECT * FROM familyhub_finance_policy WHERE scope_id=?', [$scopeId]);
        $grant = $this->one('SELECT access_level FROM familyhub_finance_grants WHERE scope_id=? AND account_id=?', [$scopeId, $user['account_id']]);
        $access = $grant['access_level'] ?? 'none';
        if ($access==='none' && (new NativeOrganizationAccess($this->container))->automaticFinanceRead($scope)) { $access='read'; }
        $enabled = $policy && (int)$policy['enabled'] === 1;
        if (($scope['role'] === 'viewer' || (int)($scope['archived'] ?? 0)===1) && $access === 'write') { $access = 'read'; }
        if ($write && (int)($scope['archived'] ?? 0)===1) { throw new NativeError('scope_archived',403); }
        if ($require && (!$enabled || $access === 'none' || ($write && $access !== 'write'))) { throw new NativeError('finance_forbidden', 403); }
        $linked = $this->one('SELECT event_id FROM familyhub_payment_events WHERE scope_id=? LIMIT 1', [$scopeId]) ||
            $this->one('SELECT event_id FROM familyhub_payment_projections WHERE scope_id=? LIMIT 1', [$scopeId]) ||
            $this->one('SELECT movement_id FROM familyhub_payment_cash WHERE scope_id=? LIMIT 1', [$scopeId]);
        return ['linkedPaymentsRequired'=>(bool)$linked,'managedByOrganizationPolicy'=>(int)($scope['effective_access_policy_version']??1)===2,'readAccessFromMembership'=>(new NativeOrganizationAccess($this->container))->automaticFinanceRead($scope),'enabled' => (bool)$enabled, 'grant' => $access, 'revision' => (int)($policy['revision'] ?? 0)+(int)($scope['effective_access_revision']??0), 'sequence' => (int)($policy['sequence'] ?? 0), 'requiredContractVersion' => (int)($policy['required_contract_version'] ?? 1)];
    }

    /** Nonlocking visibility check for inbox, inside READ COMMITTED transaction. */
    public function visible($scopeId, $accountId, $finance = false)
    {
        $effective=(new NativeOrganizationAccess($this->container))->visibleScope($scopeId,$accountId);
        if (!$effective) { return false; }
        $member = $this->one('SELECT m.role FROM familyhub_members m JOIN familyhub_accounts a ON a.account_id=m.account_id AND a.user_id=m.user_id JOIN users u ON u.id=a.user_id WHERE m.scope_id=? AND m.account_id=? AND m.active=1 AND u.is_active=1', [$scopeId, $accountId]);
        if (!$member && $effective['access_source']!=='leadership') { return false; }
        $scope = $this->one('SELECT kind,owner_id FROM familyhub_scopes WHERE id=?', [$scopeId]);
        if (!$scope) { return false; }
        if ($scope['kind'] === 'personal') {
            $binding = $this->one('SELECT p.scope_id,a.user_id FROM familyhub_personal_scopes p JOIN familyhub_accounts a ON a.account_id=p.account_id WHERE p.account_id=?', [$accountId]);
            if (!$binding || $binding['scope_id'] !== $scopeId || (int)$binding['user_id'] !== (int)$scope['owner_id'] || $member['role'] !== 'owner') { return false; }
        }
        if (!$finance) { return true; }
        $row = $this->one('SELECT p.enabled,g.access_level FROM familyhub_finance_policy p LEFT JOIN familyhub_finance_grants g ON g.scope_id=p.scope_id AND g.account_id=? WHERE p.scope_id=?', [$accountId,$scopeId]);
        return $row && (int)$row['enabled'] === 1 && (in_array($row['access_level'], ['read', 'write'], true) || (new NativeOrganizationAccess($this->container))->automaticFinanceRead($effective));
    }
}
