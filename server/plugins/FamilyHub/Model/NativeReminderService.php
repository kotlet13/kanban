<?php
namespace Kanboard\Plugin\FamilyHub\Model;

class NativeReminderService extends NativeDatabase
{
    public function execute($operation, array $params)
    {
        $this->rate([['reminders-ip:'.$this->ip, 600, 60]]);
        return $this->transaction(function () use ($operation, $params) {
            $user = $this->actor()['user'];
            $this->fields($params, match ($operation) {
                'reminders.list' => ['scopeId'],
                'reminders.put' => ['id', 'scopeId', 'targetType', 'targetId', 'remindAt', 'expectedRevision', 'requestId'],
                'reminders.cancel' => ['id', 'scopeId', 'expectedRevision', 'requestId'],
                default => throw new NativeError('unsupported_operation', 404),
            }, $operation === 'reminders.list' ? ['beforeId', 'limit'] : []);
            $scope = $this->uuid($params['scopeId']); $this->scope($scope, $user['id']);
            if ($operation === 'reminders.list') {
                $limit = $params['limit'] ?? 100; $before = isset($params['beforeId']) ? $this->uuid($params['beforeId']) : null;
                if (!is_int($limit) || $limit < 1 || $limit > 100) { throw new NativeError('validation_error'); }
                $rows = $this->many('SELECT * FROM familyhub_reminders WHERE scope_id=? AND account_id=?'.($before ? ' AND id<?' : '').' ORDER BY id DESC LIMIT '.($limit + 1), $before ? [$scope, $user['account_id'], $before] : [$scope, $user['account_id']]);
                $scanned = array_slice($rows, 0, $limit); $more = count($rows) > $limit;
                $acl = new NativeFinanceAccess($this->container);
                return ['nextBeforeId' => $more ? end($scanned)['id'] : null, 'hasMore' => $more, 'reminders' => array_map([$this, 'wire'], array_values(array_filter($scanned, fn ($row) => $acl->visible($scope, $user['account_id'], str_starts_with($row['target_type'], 'finance')))))];
            }
            $id = $this->uuid($params['id']); $request = $this->uuid($params['requestId']); $hash = $this->hashRequest($operation, $params);
            $row = $this->one('SELECT * FROM familyhub_reminders WHERE id=?', [$id]);
            if ($row && ($row['account_id'] !== $user['account_id'] || $row['scope_id'] !== $scope)) { throw new NativeError('permission_revoked', 403); }
            if ($row && str_starts_with($row['target_type'], 'finance')) { (new NativeFinanceAccess($this->container))->policy($scope, $user); }
            $replay = $this->replay($scope, $user['id'], $request, $hash); if ($replay) { return $replay['body']; }
            if (!is_int($params['expectedRevision']) || $params['expectedRevision'] !== (int)($row['revision'] ?? 0)) { throw new NativeError('reminder_conflict', 409); }
            if ($operation === 'reminders.cancel') {
                if (!$row) { throw new NativeError('reminder_missing', 404); }
                $this->change('UPDATE familyhub_reminders SET state=\'cancelled\',revision=revision+1 WHERE id=?', [$id]);
            } else {
                $type = $params['targetType']; $targetId = $this->uuid($params['targetId']);
                if (!in_array($type, ['task', 'event', 'financeEntry'], true)) { throw new NativeError('validation_error'); }
                if ($type === 'financeEntry') { (new NativeFinanceAccess($this->container))->policy($scope, $user); }
                (new NativeRecordPolicy($this->container))->date($params['remindAt']);
                $record = $this->target($scope, $type, $targetId);
                $fingerprint = $record ? $this->fingerprintTarget($record) : null;
                if (!$fingerprint) { throw new NativeError('reminder_target_unavailable'); }
                $revision = $params['expectedRevision'] + 1;
                $values = [$scope, $user['account_id'], $type, $targetId, $fingerprint, $params['remindAt'], (new \DateTimeImmutable($params['remindAt']))->getTimestamp(), $revision, 'pending'];
                if ($row) {
                    if ($row['target_type'] !== $type || $row['target_id'] !== $targetId) { throw new NativeError('reminder_target_immutable'); }
                    $this->change('UPDATE familyhub_reminders SET scope_id=?,account_id=?,target_type=?,target_id=?,target_fingerprint=?,remind_at=?,remind_epoch=?,revision=?,state=? WHERE id=?', array_merge($values, [$id]));
                } else { $this->change('INSERT INTO familyhub_reminders(scope_id,account_id,target_type,target_id,target_fingerprint,remind_at,remind_epoch,revision,state,id) VALUES(?,?,?,?,?,?,?,?,?,?)', array_merge($values, [$id])); }
            }
            $response = ['reminder' => $this->wire($this->one('SELECT * FROM familyhub_reminders WHERE id=?', [$id]))];
            $this->remember($scope, $user['id'], $request, $hash, $response); return $response;
        });
    }

    public function reconcile($scope, array $record, $previous = null)
    {
        $fingerprint = $this->fingerprintTarget($record);
        foreach ($this->many('SELECT * FROM familyhub_reminders WHERE scope_id=? AND target_type=? AND target_id=? AND state=\'pending\'', [$scope, $record['type'], $record['id']]) as $row) {
            $legacy = $previous ? (new NativeRecordPolicy($this->container))->wire($previous) : $record;
            if ($fingerprint && hash_equals($row['target_fingerprint'], $this->fingerprintTarget($legacy, false) ?? '') && $this->fingerprintTarget($legacy) === $fingerprint) {
                $this->change('UPDATE familyhub_reminders SET target_fingerprint=? WHERE id=?', [$fingerprint, $row['id']]); continue;
            }
            if (!$fingerprint || !hash_equals($row['target_fingerprint'], $fingerprint)) { $this->change('UPDATE familyhub_reminders SET state=\'cancelled\',revision=revision+1 WHERE id=?', [$row['id']]); }
        }
    }

    public function runDue($limit = 100)
    {
        if (!is_int($limit) || $limit < 1 || $limit > 500 || !defined('FAMILYHUB_ENABLE_NATIVE_API') || FAMILYHUB_ENABLE_NATIVE_API !== true) { throw new NativeError('feature_disabled', 503); }
        $rows = $this->many('SELECT id,scope_id FROM familyhub_reminders WHERE state=\'pending\' AND remind_epoch<=? ORDER BY remind_epoch,id LIMIT '.$limit, [time()]);
        $delivered = 0; $cancelled = 0;
        foreach ($rows as $candidate) {
            $state = $this->transaction(function () use ($candidate) {
                $this->one('SELECT id FROM familyhub_scopes WHERE id=?'.$this->lockSuffix(), [$candidate['scope_id']]);
                $row = $this->one('SELECT * FROM familyhub_reminders WHERE id=?', [$candidate['id']]);
                if (!$row || $row['state'] !== 'pending' || (int)$row['remind_epoch'] > time()) { return null; }
                $acl = new NativeFinanceAccess($this->container);
                $record = $this->target($row['scope_id'], $row['target_type'], $row['target_id']);
                $fingerprint = $record ? $this->fingerprintTarget($record) : null;
                if (!$acl->visible($row['scope_id'], $row['account_id'], str_starts_with($row['target_type'], 'finance')) || !$fingerprint || (!hash_equals($row['target_fingerprint'], $fingerprint) && !hash_equals($row['target_fingerprint'], $this->fingerprintTarget($record, false)))) {
                    $this->change('UPDATE familyhub_reminders SET state=\'cancelled\',revision=revision+1 WHERE id=?', [$row['id']]); return 'cancelled';
                }
                (new NativeNotificationWriter($this->container))->insert($row['scope_id'], $row['account_id'], null, $row['target_type'], $row['target_id'], $record['revision'], 'reminder.due', 'reminders', 'personal', hash('sha256', 'reminder:'.$row['id'].':'.$row['revision']));
                $this->change('UPDATE familyhub_reminders SET state=\'delivered\' WHERE id=?', [$row['id']]); return 'delivered';
            });
            if ($state === 'delivered') { $delivered++; } elseif ($state === 'cancelled') { $cancelled++; }
        }
        return ['examined' => count($rows), 'delivered' => $delivered, 'cancelled' => $cancelled, 'externalPush' => false, 'smtp' => false];
    }

    private function target($scope, $type, $id)
    {
        $finance = str_starts_with($type, 'finance');
        $row = $this->one('SELECT * FROM '.($finance ? 'familyhub_finance_records' : 'familyhub_records').' WHERE scope_id=? AND id=? AND type=?', [$scope, $id, $type]);
        return $row ? (new NativeRecordPolicy($this->container))->wire($row) : null;
    }

    private function fingerprintTarget(array $record, $canonical = true)
    {
        $p = $record['payload'];
        if ($record['deleted'] || !$p || ($record['type'] === 'task' && $p['isCompleted']) || ($record['type'] === 'financeEntry' && $p['status'] !== 'planned')) { return null; }
        if (!in_array($record['type'], ['task', 'event', 'financeEntry'], true)) { return null; }
        $dates = [$p['dueAt'] ?? null, $p['startAt'] ?? null, $p['endAt'] ?? null, $p['occurredAt'] ?? null];
        if ($canonical) { $dates = array_map(fn ($date) => $date === null ? null : (new \DateTimeImmutable($date))->format('Y-m-d\\TH:i:s.u\\Z'), $dates); }
        return hash('sha256', json_encode($dates, JSON_THROW_ON_ERROR));
    }

    public function wire($row)
    {
        return ['id' => $row['id'], 'scopeId' => $row['scope_id'], 'targetType' => $row['target_type'], 'targetId' => $row['target_id'], 'remindAt' => $row['remind_at'], 'revision' => (int)$row['revision'], 'state' => $row['state']];
    }
}
