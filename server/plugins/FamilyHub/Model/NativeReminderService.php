<?php
namespace Kanboard\Plugin\FamilyHub\Model;

class NativeReminderService extends NativeDatabase
{
    public function execute($operation, array $params)
    {
        $this->rate([['reminders-ip:'.$this->ip, 600, 60]]);
        return $this->transaction(function () use ($operation, $params) {
            $user = $this->actor()['user'];
            (new NativeModerationService($this->container,$this->bearer,$this->ip))->guardWrite($operation,$params);
            $this->fields($params, match ($operation) {
                'reminders.list' => ['scopeId'],
                'reminders.put' => ['id', 'scopeId', 'targetType', 'targetId', 'remindAt', 'expectedRevision', 'requestId'],
                'reminders.cancel' => ['id', 'scopeId', 'expectedRevision', 'requestId'],
                default => throw new NativeError('unsupported_operation', 404),
            }, $operation === 'reminders.list' ? ['beforeId', 'limit'] : ($operation === 'reminders.put' ? ['scheduleMode','offsetMinutes'] : []));
            $scope = $this->uuid($params['scopeId']); $this->scope($scope, $user['id'], $operation==='reminders.put');
            if ($operation === 'reminders.list') {
                $limit = $params['limit'] ?? 100; $before = isset($params['beforeId']) ? $this->uuid($params['beforeId']) : null;
                if (!is_int($limit) || $limit < 1 || $limit > 100) { throw new NativeError('validation_error'); }
                $rows = $this->many('SELECT * FROM familyhub_reminders WHERE scope_id=? AND account_id=?'.($before ? ' AND id<?' : '').' ORDER BY id DESC LIMIT '.($limit + 1), $before ? [$scope, $user['account_id'], $before] : [$scope, $user['account_id']]);
                $scanned = array_slice($rows, 0, $limit); $more = count($rows) > $limit;
                $acl = new NativeFinanceAccess($this->container);
                return ['nextBeforeId' => $more ? end($scanned)['id'] : null, 'hasMore' => $more, 'reminders' => array_map([$this, 'wire'], array_values(array_filter($scanned, fn ($row) => $acl->visible($scope, $user['account_id'], $this->financialRecordType($row['target_type'])))))];
            }
            $id = $this->uuid($params['id']); $request = $this->uuid($params['requestId']); $hash = $this->hashRequest($operation, $params);
            $row = $this->one('SELECT * FROM familyhub_reminders WHERE id=?', [$id]);
            if ($row && $row['account_id'] !== $user['account_id']) { throw new NativeError('permission_revoked',403); }
            if ($row && $this->financialRecordType($row['target_type'])) { (new NativeFinanceAccess($this->container))->policy($scope, $user); }
            $replay = $this->replay($scope, $user['id'], $request, $hash); if ($replay) { return $replay['body']; }
            if ($row && $row['scope_id'] !== $scope) { throw new NativeError('permission_revoked',403); }
            if (!is_int($params['expectedRevision']) || $params['expectedRevision'] !== (int)($row['revision'] ?? 0)) { throw new NativeError('reminder_conflict', 409); }
            if ($operation === 'reminders.cancel') {
                if (!$row) { throw new NativeError('reminder_missing', 404); }
                $this->change('UPDATE familyhub_reminders SET state=\'cancelled\',revision=revision+1 WHERE id=?', [$id]);
            } else {
                $type = $params['targetType']; $targetId = $this->uuid($params['targetId']);
                if (!in_array($type, ['task', 'event', 'financeEntry','personalFinanceEntry'], true)) { throw new NativeError('validation_error'); }
                if ($type === 'financeEntry') { (new NativeFinanceAccess($this->container))->policy($scope, $user); }
                (new NativeRecordPolicy($this->container))->date($params['remindAt']);
                $record = $this->target($scope, $type, $targetId);
                $fingerprint = $record ? $this->fingerprintTarget($record) : null;
                if (!$fingerprint) { throw new NativeError('reminder_target_unavailable'); }
                $mode=$params['scheduleMode']??'absolute';$offset=$params['offsetMinutes']??null;
                if ($mode==='deadline') {
                    if ($type!=='task' || !is_int($offset) || !in_array($offset,[0,60,1440],true)) { throw new NativeError('validation_error'); }
                    $at=$this->deadlineAt($record,$offset);
                    if ($at===null || $at->getTimestamp()<=time()) { throw new NativeError('reminder_target_unavailable'); }
                    $params['remindAt']=$at->format('Y-m-d\TH:i:s.u\Z');
                } elseif ($mode!=='absolute' || $offset!==null) { throw new NativeError('validation_error'); }
                $revision = $params['expectedRevision'] + 1;
                $values = [$scope, $user['account_id'], $type, $targetId, $fingerprint, $params['remindAt'], (new \DateTimeImmutable($params['remindAt']))->getTimestamp(), $revision, 'pending', $mode, $offset];
                if ($row) {
                    if ($row['target_type'] !== $type || $row['target_id'] !== $targetId) { throw new NativeError('reminder_target_immutable'); }
                    $this->change('UPDATE familyhub_reminders SET scope_id=?,account_id=?,target_type=?,target_id=?,target_fingerprint=?,remind_at=?,remind_epoch=?,revision=?,state=?,schedule_mode=?,offset_minutes=? WHERE id=?', array_merge($values, [$id]));
                } else { $this->change('INSERT INTO familyhub_reminders(scope_id,account_id,target_type,target_id,target_fingerprint,remind_at,remind_epoch,revision,state,schedule_mode,offset_minutes,id) VALUES(?,?,?,?,?,?,?,?,?,?,?,?)', array_merge($values, [$id])); }
            }
            $response = ['reminder' => $this->wire($this->one('SELECT * FROM familyhub_reminders WHERE id=?', [$id]))];
            $this->remember($scope, $user['id'], $request, $hash, $response); return $response;
        });
    }

    public function reconcile($scope, array $record, $previous = null)
    {
        if ($record['type'] === 'householdPerson') { return; }
        if ($record['type']==='project' && ($record['deleted'] || ($record['payload']['archived']??false))) {
            foreach ($this->many('SELECT * FROM familyhub_reminders WHERE scope_id=? AND state=\'pending\'',[$scope]) as $row) {
                $target=$this->target($scope,$row['target_type'],$row['target_id']);
                if ($target && $this->targetProjectId($scope,$target)===$record['id']) {
                    $this->change('UPDATE familyhub_reminders SET state=\'cancelled\',revision=revision+1 WHERE id=?',[$row['id']]);
                }
            }
        }
        $fingerprint = $this->fingerprintTarget($record,true,$scope);
        foreach ($this->many('SELECT * FROM familyhub_reminders WHERE scope_id=? AND target_type=? AND target_id=? AND state=\'pending\'', [$scope, $record['type'], $record['id']]) as $row) {
            if (($row['schedule_mode']??'absolute')==='deadline') {
                $at=$this->deadlineAt($record,(int)$row['offset_minutes']);
                if (!$fingerprint || $at===null) {
                    $this->change('UPDATE familyhub_reminders SET state=\'cancelled\',revision=revision+1 WHERE id=?',[$row['id']]);
                } else {
                    $stamp=$at->format('Y-m-d\TH:i:s.u\Z');
                    if (!hash_equals($row['target_fingerprint'],$fingerprint) || (new \DateTimeImmutable($row['remind_at']))!=$at) {
                        $this->change('UPDATE familyhub_reminders SET target_fingerprint=?,remind_at=?,remind_epoch=?,revision=revision+1 WHERE id=?',[$fingerprint,$stamp,$at->getTimestamp(),$row['id']]);
                    }
                }
                continue;
            }
            $legacy = $previous ? (new NativeRecordPolicy($this->container))->wire($previous) : $record;
            if ($fingerprint && hash_equals($row['target_fingerprint'], $this->fingerprintTarget($legacy, false,$scope) ?? '') && $this->fingerprintTarget($legacy,true,$scope) === $fingerprint) {
                $this->change('UPDATE familyhub_reminders SET target_fingerprint=? WHERE id=?', [$fingerprint, $row['id']]); continue;
            }
            if (!$fingerprint || !hash_equals($row['target_fingerprint'], $fingerprint)) { $this->change('UPDATE familyhub_reminders SET state=\'cancelled\',revision=revision+1 WHERE id=?', [$row['id']]); }
        }
    }

    public function runDue($limit = 100)
    {
        if (!is_int($limit) || $limit < 1 || $limit > 500 || !defined('FAMILYHUB_ENABLE_NATIVE_API') || FAMILYHUB_ENABLE_NATIVE_API !== true) { throw new NativeError('feature_disabled', 503); }
        $retention = (new NativeInboxRetention($this->container))->run($limit);
        $rows = $this->many('SELECT r.id,r.scope_id FROM familyhub_reminders r JOIN familyhub_scopes s ON s.id=r.scope_id LEFT JOIN familyhub_scopes parent ON parent.id=COALESCE(s.parent_scope_id,s.organization_id) WHERE r.state=\'pending\' AND s.archived=0 AND s.deleted_at IS NULL AND (parent.id IS NULL OR (parent.archived=0 AND parent.deleted_at IS NULL)) AND r.remind_epoch<=? ORDER BY r.remind_epoch,r.id LIMIT '.$limit, [time()]);
        $delivered = 0; $cancelled = 0;
        foreach ($rows as $candidate) {
            $state = $this->transaction(function () use ($candidate) {
                $scopeState=$this->lockScopeLifecycle($candidate['scope_id']);
                if (!$scopeState || (int)($scopeState['archived']??0)===1 || $scopeState['deleted_at']!==null) { return null; }
                $row = $this->one('SELECT * FROM familyhub_reminders WHERE id=?', [$candidate['id']]);
                if (!$row || $row['state'] !== 'pending' || (int)$row['remind_epoch'] > time()) { return null; }
                $acl = new NativeFinanceAccess($this->container);
                $record = $this->target($row['scope_id'], $row['target_type'], $row['target_id']);
                $fingerprint = $record ? $this->fingerprintTarget($record) : null;
                if (!$acl->visible($row['scope_id'], $row['account_id'], $this->financialRecordType($row['target_type'])) || !$fingerprint || (!hash_equals($row['target_fingerprint'], $fingerprint) && !hash_equals($row['target_fingerprint'], $this->fingerprintTarget($record, false)))) {
                    $this->change('UPDATE familyhub_reminders SET state=\'cancelled\',revision=revision+1 WHERE id=?', [$row['id']]); return 'cancelled';
                }
                (new NativeNotificationWriter($this->container))->insert($row['scope_id'], $row['account_id'], null, $row['target_type'], $row['target_id'], $record['revision'], 'reminder.due', 'reminders', 'personal', hash('sha256', 'reminder:'.$row['id'].':'.$row['revision']));
                $this->change('UPDATE familyhub_reminders SET state=\'delivered\' WHERE id=?', [$row['id']]); return 'delivered';
            });
            if ($state === 'delivered') { $delivered++; } elseif ($state === 'cancelled') { $cancelled++; }
        }
        return ['examined' => count($rows), 'delivered' => $delivered, 'cancelled' => $cancelled, 'readNotificationsDeleted' => $retention['deleted'], 'externalPush' => false, 'smtp' => false];
    }

    private function deadlineAt(array $record,$offset)
    {
        if ($record['type']!=='task' || $record['deleted'] || !$record['payload'] || $record['payload']['isCompleted'] || empty($record['payload']['dueAt'])) { return null; }
        return (new \DateTimeImmutable($record['payload']['dueAt']))->setTimezone(new \DateTimeZone('UTC'))->sub(new \DateInterval('PT'.$offset.'M'));
    }

    private function target($scope, $type, $id)
    {
        $finance = $this->financialRecordType($type);
        $row = $this->one('SELECT * FROM '.($finance ? 'familyhub_finance_records' : 'familyhub_records').' WHERE scope_id=? AND id=? AND type=?', [$scope, $id, $type]);
        return $row ? ['scopeId'=>$scope]+(new NativeRecordPolicy($this->container))->wire($row) : null;
    }

    private function targetProjectId($scope,array $record)
    {
        $p=$record['payload'];
        if (!empty($p['projectId'])) { return $p['projectId']; }
        if (!empty($p['taskId'])) {
            $task=$this->target($scope,'task',$p['taskId']);
            return $task['payload']['projectId']??null;
        }
        return null;
    }

    private function fingerprintTarget(array $record, $canonical = true,$scope=null)
    {
        $p = $record['payload'];
        // The record's stored scope is retained in every wire envelope. An
        // archived inline parent suppresses both new schedules and cron delivery.
        $scope=$scope??($record['scopeId']??null);
        $project=$this->targetProjectId($scope,$record);
        if ($project!==null) {
            $parent=$this->target($scope,'project',$project);
            if (!$parent || $parent['deleted'] || ($parent['payload']['archived']??false)) { return null; }
        }
        if ($record['deleted'] || !$p || ($record['type'] === 'task' && $p['isCompleted']) || (in_array($record['type'],['financeEntry','personalFinanceEntry'],true) && ($p['status']??'posted') !== 'planned')) { return null; }
        if (!in_array($record['type'], ['task', 'event', 'financeEntry','personalFinanceEntry'], true)) { return null; }
        $dates = [$p['dueAt'] ?? null, $p['startAt'] ?? null, $p['endAt'] ?? null, $p['occurredAt'] ?? null];
        if (array_key_exists('plannedAt',$p)) { $dates[]=$p['plannedAt']; }
        if ($canonical) { $dates = array_map(fn ($date) => $date === null ? null : (new \DateTimeImmutable($date))->format('Y-m-d\\TH:i:s.u\\Z'), $dates); }
        return hash('sha256', json_encode($dates, JSON_THROW_ON_ERROR));
    }

    public function wire($row)
    {
        $extra=($row['schedule_mode']??'absolute')==='deadline'?['scheduleMode'=>'deadline','offsetMinutes'=>(int)$row['offset_minutes']]:[];
        return $extra+['id' => $row['id'], 'scopeId' => $row['scope_id'], 'targetType' => $row['target_type'], 'targetId' => $row['target_id'], 'remindAt' => $row['remind_at'], 'revision' => (int)$row['revision'], 'state' => $row['state']];
    }
}
