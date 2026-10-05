<?php
namespace Kanboard\Plugin\FamilyHub\Model;

class NativeFinanceService extends NativeDatabase
{
    public function execute($operation, array $params)
    {
        $this->rate([['finance-ip:'.$this->ip, 1200, 60]]);
        $result = $this->transaction(function () use ($operation, $params) {
            $user = $this->actor()['user']; $scope = $this->uuid($params['scopeId'] ?? null);
            if (in_array($operation, ['finance.enable', 'finance.grant'], true)) { return (new NativeFinanceSettings($this->container))->changePolicy($operation, $params, $user); }
            if ($operation === 'finance.grants') {
                $this->fields($params, ['scopeId']); $this->scope($scope, $user['id'], false, true);
                $policy = $this->one('SELECT enabled,revision FROM familyhub_finance_policy WHERE scope_id=?', [$scope]);
                $rows = $this->many('SELECT m.account_id,m.role,g.access_level FROM familyhub_members m JOIN familyhub_accounts a ON a.account_id=m.account_id AND a.user_id=m.user_id JOIN users u ON u.id=a.user_id LEFT JOIN familyhub_finance_grants g ON g.scope_id=m.scope_id AND g.account_id=m.account_id WHERE m.scope_id=? AND m.active=1 AND u.is_active=1 ORDER BY m.account_id', [$scope]);
                return ['enabled' => (bool)($policy['enabled'] ?? false), 'revision' => (int)($policy['revision'] ?? 0), 'grants' => array_map(fn ($r) => ['accountId' => $r['account_id'], 'grant' => $r['role'] === 'viewer' && $r['access_level'] === 'write' ? 'read' : ($r['access_level'] ?? 'none')], $rows)];
            }
            $acl = (new NativeFinanceAccess($this->container))->policy($scope, $user, $operation === 'finance.push', $operation !== 'finance.policy');
            if ($operation === 'finance.policy') { $this->fields($params, ['scopeId']); return array_diff_key($acl, ['sequence' => true]); }
            if ($operation === 'finance.pull') { return $this->pull($params, $scope, $acl); }
            if ($operation === 'finance.audit') { return $this->audit($params, $scope); }
            if ($operation !== 'finance.push') { throw new NativeError('unsupported_operation', 404); }
            return $this->push($operation, $params, $scope, $user, $acl);
        });
        if ($result instanceof NativeError) { throw $result; } return $result;
    }

    private function push($operation, $params, $scope, $user, $acl)
    {
        $this->fields($params, ['scopeId', 'operation']); $op = $params['operation'];
        if (!is_array($op)) { throw new NativeError('validation_error'); }
        $this->fields($op, ['opId', 'recordId', 'type', 'expectedRevision', 'deleted', 'payload']);
        $id = $this->uuid($op['recordId']); $opId = $this->uuid($op['opId']);
        if (!in_array($op['type'], ['financeAccount', 'financeEntry', 'financeTransfer', 'personalFinanceEntry'], true) || !is_int($op['expectedRevision']) || $op['expectedRevision'] < 0 || !is_bool($op['deleted'])) { throw new NativeError('validation_error'); }
        $kind = $this->one('SELECT kind FROM familyhub_scopes WHERE id=?', [$scope])['kind'];
        if (($op['type'] === 'personalFinanceEntry') !== ($kind === 'personal')) { throw new NativeError('validation_error'); }
        $hash = $this->hashRequest($operation, $params);
        $store = new NativeFinanceSettings($this->container); $replay = $store->replayFinance($scope, $user['account_id'], $opId, $hash);
        if ($replay) {
            if ($replay['status'] !== 200) { return new NativeError($replay['body']['errorCode'], $replay['status'], $replay['body']['details']); }
            $replay['body']['replayed'] = true; return $replay['body'];
        }
        $current = $this->one('SELECT * FROM familyhub_finance_records WHERE scope_id=? AND id=?', [$scope, $id]);
        if (($current && ((int)$current['revision'] !== $op['expectedRevision'] || (int)$current['deleted'] === 1 || $current['type'] !== $op['type'])) || (!$current && ($op['expectedRevision'] !== 0 || $op['deleted']))) {
            $details = ['serverRecord' => $current ? $this->wire($current) : null];
            $store->rememberFinance($scope, $user['account_id'], $opId, $hash, ['errorCode' => 'conflict', 'details' => $details], 409); return new NativeError('conflict', 409, $details);
        }
        $policy = new NativeFinancePolicy($this->container);
        try {
            if ($op['deleted']) { if ($op['payload'] !== null) { throw new NativeError('validation_error'); } $policy->noChildren($scope, $id, $op['type']); }
            else { $policy->validate($op['type'], $op['payload'], $scope, $current); }
        } catch (NativeError $error) {
            if (!in_array($error->errorCode, ['parent_missing', 'live_children', 'assignee_not_member'], true)) { throw $error; }
            $details = ['serverRecord' => $current ? $this->wire($current) : null];
            $store->rememberFinance($scope, $user['account_id'], $opId, $hash, ['errorCode' => $error->errorCode, 'details' => $details], 422); return new NativeError($error->errorCode, 422, $details);
        }
        $revision = $op['expectedRevision'] + 1; $sequence = $acl['sequence'] + 1; $now = gmdate('Y-m-d\TH:i:s\Z');
        $payload = $op['deleted'] ? null : json_encode($op['payload'], JSON_UNESCAPED_UNICODE | JSON_THROW_ON_ERROR);
        $this->change('UPDATE familyhub_finance_policy SET sequence=? WHERE scope_id=?', [$sequence, $scope]);
        if ($current) {
            $this->change('UPDATE familyhub_finance_records SET revision=?,deleted=?,payload=?,sequence=?,updated_at=?,updated_by=? WHERE scope_id=? AND id=?', [$revision, (int)$op['deleted'], $payload, $sequence, $now, $user['account_id'], $scope, $id]);
        } else {
            $this->change('INSERT INTO familyhub_finance_records(scope_id,id,type,revision,deleted,payload,sequence,updated_at,created_by,updated_by) VALUES(?,?,?,?,0,?,?,?,?,?)', [$scope, $id, $op['type'], $revision, $payload, $sequence, $now, $user['account_id'], $user['account_id']]);
        }
        $record = $this->wire($this->one('SELECT * FROM familyhub_finance_records WHERE scope_id=? AND id=?', [$scope, $id]));
        $this->change('INSERT INTO familyhub_finance_audit VALUES(?,?,?,?,?,?,?,?)', [$scope, $id, $revision, $user['account_id'], $now, $current ? json_encode($this->wire($current), JSON_THROW_ON_ERROR) : null, json_encode($record, JSON_THROW_ON_ERROR), $opId]);
        (new NativeNotificationWriter($this->container))->recordChanged($scope, $record, $current, $user['account_id'], true);
        (new NativeReminderService($this->container))->reconcile($scope, $record, $current);
        $response = ['status' => 'applied', 'record' => $record, 'cursor' => $sequence, 'accessRevision' => $acl['revision'], 'replayed' => false];
        $store->rememberFinance($scope, $user['account_id'], $opId, $hash, $response); return $response;
    }

    private function pull($params, $scope, $acl)
    {
        $this->fields($params, ['scopeId', 'cursor'], ['limit', 'accessRevision']); $cursor = $params['cursor']; $limit = $params['limit'] ?? 100;
        if (!is_int($cursor) || $cursor < 0 || $cursor > $acl['sequence'] || !is_int($limit) || $limit < 1 || $limit > 500) { throw new NativeError('invalid_cursor'); }
        if (($cursor > 0 && !isset($params['accessRevision'])) || (isset($params['accessRevision']) && $params['accessRevision'] !== $acl['revision'])) { throw new NativeError('finance_access_changed', 409, ['accessRevision' => $acl['revision']]); }
        $rows = $this->many('SELECT * FROM familyhub_finance_records WHERE scope_id=? AND sequence>? ORDER BY sequence LIMIT '.($limit + 1), [$scope, $cursor]);
        $records = []; $bytes = 0;
        foreach ($rows as $row) { $record = $this->wire($row); $size = strlen(json_encode($record, JSON_UNESCAPED_UNICODE | JSON_THROW_ON_ERROR)); if (count($records) >= $limit || ($records && $bytes + $size > 524288)) { break; } $records[] = $record; $bytes += $size; }
        $more = count($rows) > count($records);
        return ['records' => $records, 'cursor' => $more ? end($records)['sequence'] : $acl['sequence'], 'hasMore' => $more, 'scopeSequence' => $acl['sequence'], 'accessRevision' => $acl['revision']];
    }

    private function audit($params, $scope)
    {
        $this->fields($params, ['scopeId', 'recordId'], ['beforeRevision', 'limit']); $id = $this->uuid($params['recordId']); $before = $params['beforeRevision'] ?? PHP_INT_MAX; $limit = $params['limit'] ?? 50;
        if (!is_int($before) || $before < 1 || !is_int($limit) || $limit < 1 || $limit > 100) { throw new NativeError('validation_error'); }
        $rows = $this->many('SELECT * FROM familyhub_finance_audit WHERE scope_id=? AND record_id=? AND revision<? ORDER BY revision DESC LIMIT '.($limit + 1), [$scope, $id, $before]); $more = count($rows) > $limit; $page = array_slice($rows, 0, $limit);
        $entries = array_map(fn ($r) => ['scopeId' => $r['scope_id'], 'recordId' => $r['record_id'], 'revision' => (int)$r['revision'], 'actorAccountId' => $r['actor_account_id'], 'changedAt' => $r['changed_at'], 'before' => $r['before_json'] ? json_decode($r['before_json'], true, 32, JSON_THROW_ON_ERROR) : null, 'after' => json_decode($r['after_json'], true, 32, JSON_THROW_ON_ERROR), 'opId' => $r['op_id']], $page);
        $bounded = []; $bytes = 0;
        foreach ($entries as $entry) { $size = strlen(json_encode($entry, JSON_UNESCAPED_UNICODE | JSON_THROW_ON_ERROR)); if ($bounded && $bytes + $size > 524288) { break; } $bounded[] = $entry; $bytes += $size; }
        $more = count($rows) > count($bounded);
        return ['entries' => $bounded, 'hasMore' => $more, 'nextBeforeRevision' => $more ? end($bounded)['revision'] : null];
    }

    private function wire($row) { return (new NativeRecordPolicy($this->container))->wire($row); }
}
