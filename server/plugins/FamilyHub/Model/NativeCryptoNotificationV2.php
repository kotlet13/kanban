<?php

namespace Kanboard\Plugin\FamilyHub\Model;

/** Minimal signed scheduling state. No decrypted title, amount, body, or content fingerprint. */
class NativeCryptoNotificationV2 extends NativeDatabase
{
    protected $cryptoAccess = true;

    /** Notification routing only; membership is never a business record type. */
    public function routingDomain($type)
    {
        return $type === 'membership' ? 'content' :
            (new NativeCryptoRecordProofV2($this->container))->domain($type);
    }

    /** Close every bounded keyset cursor before ACL checks and writes (MySQL unbuffered PDO). */
    private function reminderRows($where, $args)
    {
        $after = '';
        do {
            $rows = $this->many('SELECT * FROM familyhub_crypto_reminders_v2 WHERE '.$where.' AND id>? ORDER BY id LIMIT 100', array_merge($args, [$after]));
            foreach ($rows as $row) {
                $after = $row['id'];
                yield $row;
            }
        } while (count($rows) === 100);
    }

    public function validateConsentTransition($record, $previous)
    {
        $key = $record['type']==='project' ? 'projectState' : 'reminderState';
        $state=$record['metadata'][$key]??null;
        if (!$previous) { return; }
        $old=json_decode($previous['metadata'],true,34,JSON_THROW_ON_ERROR)[$key]??null;
        if ($old && isset($old['consentGeneration']) && (!$state || !isset($state['consentGeneration']))) {
            throw new NativeError('crypto_scheduling_consent_generation',409);
        }
        if (!$state || !isset($state['consentGeneration'])) { return; }
        if ($record['deleted'] && ($state[$key==='projectState'?'archived':'closed']!==true || $key==='reminderState' && $state['dueAtEpoch']!==null)) {
            throw new NativeError('crypto_scheduling_consent_generation',409);
        }
        if (!$old || !isset($old['consentGeneration'])) { return; }
        $field=$key==='projectState'?'archived':'closed';
        $changed=(bool)$previous['deleted']!==$record['deleted'] || $old[$field]!==$state[$field];
        if ($changed === ($old['consentGeneration']===$state['consentGeneration'])) {
            throw new NativeError('crypto_scheduling_consent_generation',409);
        }
    }

    public function emit($record, $previous)
    {
        if (!NativeCryptoRecordProofV2::notifiesType($record['type']) || $record['deleted'] && !$previous) {
            return;
        }
        $state = $record['metadata']['notificationState'];
        $old = $previous ? json_decode($previous['metadata'], true, 34, JSON_THROW_ON_ERROR)['notificationState'] ?? null : null;
        if ($previous && !$old) {
            throw new NativeError('crypto_notification_history_required', 409);
        }
        $scopes = new NativeCryptoScopeV2($this->container);
        $head = $scopes->current($record['scopeId']);
        $body = $scopes->body($head);
        foreach ($state['assigneeAccountIds'] as $id) {
            if (!$scopes->member($body, $id) || !$this->recipientVisible($record['scopeId'], $id, $record['domain'])) {
                throw new NativeError('crypto_notification_recipient_invalid', 409);
            }
        }
        if ($state['groupTargetId'] !== null && !$this->referencesTarget($record, $state['groupTargetId'], ['project','shoppingList'])) {
            throw new NativeError('crypto_notification_group_invalid', 409);
        }
        $category = $record['domain'] === 'finance' ? 'finance' : match($record['type']) {
            'task','project' => 'tasks','idea' => 'ideas','event' => 'events',default => 'shopping'
        };
        $scope = $this->one('SELECT access_policy_version FROM familyhub_scopes WHERE id=?', [$record['scopeId']]);
        foreach ($body['members'] as $member) {
            $account = $member['accountId'];
            if ($account === $record['accountId'] || !$this->recipientVisible($record['scopeId'], $account, $record['domain'])) {
                continue;
            }
            if ((int)$scope['access_policy_version'] === 2 && !$this->one('SELECT account_id FROM familyhub_members WHERE scope_id=? AND account_id=? AND active=1', [$record['scopeId'],$account]) && !$this->one('SELECT account_id FROM familyhub_inbox_preferences WHERE scope_id=? AND account_id=? AND category=?', [$record['scopeId'],$account,$category])) {
                continue;
            }
            $personal = in_array($account, $state['assigneeAccountIds'], true);
            $assigned = $personal && !in_array($account, $old['assigneeAccountIds'] ?? [], true);
            $kind = 'crypto2.'.$record['type'].'.'.($assigned ? 'assigned' : $state['kind']);
            $group = $state['groupTargetId'] ?? (in_array($record['type'], ['task','event'], true) ? $record['scopeId'] : null);
            (new NativeNotificationWriter($this->container))->insert($record['scopeId'], $account, $record['accountId'], $record['type'], $record['id'], $record['expectedRevision'] + 1, $kind, $category, $personal ? 'personal' : 'scope', hash('sha256', 'crypto2:'.$record['scopeId'].':'.$record['id'].':'.($record['expectedRevision'] + 1)), $group);
        }
    }

    private function referencesTarget($record, $target, $types)
    {
        $pending = $record['metadata']['references'];
        $seen = [];
        $steps = 0;
        while ($pending) {
            $ref = array_shift($pending);
            if ($ref['scopeId'] !== $record['scopeId'] || isset($seen[$ref['id']])) {
                continue;
            }
            $seen[$ref['id']] = true;
            if (++$steps > 100) {
                throw new NativeError('crypto_reference_graph_limit', 409);
            }
            $row = $this->one('SELECT id,type,deleted,metadata FROM familyhub_crypto_records WHERE scope_id=? AND id=?', [$record['scopeId'],$ref['id']]);
            if (!$row) {
                continue;
            }
            if ($row['id'] === $target && in_array($row['type'], $types, true)) {
                return true;
            }
            if ((int)$row['deleted']) {
                continue;
            }
            foreach (json_decode($row['metadata'], true, 34, JSON_THROW_ON_ERROR)['references'] as $next) {
                $pending[] = $next;
            }
        }
        return false;
    }

    public function changed($record, $previous)
    {
        if ($record['type'] === 'project' && ($record['deleted'] || $record['metadata']['projectState']['archived'])) {
            foreach ($this->reminderRows("scope_id=? AND state='pending'", [$record['scopeId']]) as $intent) {
                $target = $this->one('SELECT metadata FROM familyhub_crypto_records WHERE scope_id=? AND id=?', [$record['scopeId'],$intent['target_id']]);
                if ($target && $this->referencesTarget(['scopeId' => $record['scopeId'],'metadata' => json_decode($target['metadata'], true, 34, JSON_THROW_ON_ERROR)], $record['id'], ['project'])) {
                    $this->change("UPDATE familyhub_crypto_reminders_v2 SET state='cancelled',revision=revision+1 WHERE id=?", [$intent['id']]);
                }
            }
        }
        if (!in_array($record['type'], ['task','event','financeEntry','personalFinanceEntry'], true)) {
            return;
        }
        $state = $record['metadata']['reminderState'] ?? null;
        $old = $previous ? json_decode($previous['metadata'], true, 34, JSON_THROW_ON_ERROR)['reminderState'] ?? null : null;
        if ($previous && !$record['deleted'] && !$old) {
            throw new NativeError('crypto_reminder_history_required', 409);
        }
        $closed = $record['deleted'] || !$state || $state['closed'];
        foreach ($this->reminderRows("scope_id=? AND target_id=? AND state='pending'", [$record['scopeId'],$record['id']]) as $row) {
            $cancel = $closed || !$this->recipientVisible($row['scope_id'], $row['account_id'], $row['domain']);
            $epoch = (int)$row['remind_epoch'];
            if (!$cancel && $row['schedule_mode'] === 'deadline') {
                if ($state['dueAtEpoch'] === null) {
                    if ($old && $old['scheduleRevision'] === $state['scheduleRevision']) {
                        // No deadline change: omission never recreates or moves an existing job.
                        $epoch = (int)$row['remind_epoch'];
                    } else {
                        throw new NativeError('crypto_scheduling_use_required',409);
                    }
                } else {
                    $epoch = $state['dueAtEpoch'] - (int)$row['offset_minutes'] * 60;
                }
            } elseif (!$cancel && (!$old || $row['schedule_revision'] !== $state['scheduleRevision'])) {
                $cancel = true;
            }
            $changed = $cancel || $epoch !== (int)$row['remind_epoch'] || ($state['scheduleRevision'] ?? $row['schedule_revision']) !== $row['schedule_revision'];
            $this->change('UPDATE familyhub_crypto_reminders_v2 SET state=?,target_revision=?,schedule_revision=?,remind_epoch=?,remind_at=?,revision=revision+? WHERE id=?', [$cancel ? 'cancelled' : 'pending',$record['expectedRevision'] + 1,$state['scheduleRevision'] ?? $row['schedule_revision'],$epoch,gmdate('Y-m-d\TH:i:s\Z', $epoch),$changed ? 1 : 0,$row['id']]);
        }
    }

    public function replayAccess($op, $p, $actor)
    {
        if ($op === 'crypto2.inbox.read') {
            $row = $this->one('SELECT * FROM familyhub_inbox WHERE id=?', [$p['id'] ?? 0]);
            if (!$this->inboxVisible($row, $actor)) {
                throw new NativeError('permission_revoked', 403);
            }
        }
        if ($op === 'crypto2.reminders.put') {
            $domain = (new NativeCryptoRecordProofV2($this->container))->domain($p['targetType'] ?? '');
            if (!$this->recipientVisible($p['scopeId'] ?? '', $actor['user']['account_id'], $domain)) {
                throw new NativeError('permission_revoked', 403);
            }
        }
    }

    public function write($op, $p, $actor, $proof, $command = null, $key = null)
    {
        if (str_starts_with($op, 'crypto2.inbox.')) {
            return $this->inboxWrite($op, $p, $actor);
        }
        $cancel = $op === 'crypto2.reminders.cancel';
        $this->fields($p, $cancel ? ['id','scopeId','expectedRevision'] : ['id','scopeId','targetType','targetId','targetIdentity','remindAt','expectedRevision'], $cancel ? ['useProof','accountEventProof'] : ['scheduleMode','offsetMinutes','useProof','accountEventProof','targetDueAtEpoch','targetRevision','targetRecordProofHash']);
        $sid = $this->uuid($p['scopeId']);
        $id = $this->uuid($p['id']);
        if (!$cancel) {
            $scope = $this->scope($sid, $actor['user']['id']);
            $scopes = new NativeCryptoScopeV2($this->container,$this->bearer,$this->ip);
            $head = $scopes->current($sid);
            if (!$head) { throw new NativeError('crypto_scope_head_missing',404); }
            // READ/viewer scheduling remains permitted; freshness is independent
            // of content edit privilege. Own cancellation remains an escape.
            $scopes->assertCurrentMembership($scope,$head);
            NativeCryptoScopeCreationV2::guardBusiness($this->pdo, $sid);
        }
        $row = $this->one('SELECT * FROM familyhub_crypto_reminders_v2 WHERE id=?', [$id]);
        if ($row && ($row['scope_id'] !== $sid || $row['account_id'] !== $actor['user']['account_id'])) {
            throw new NativeError('permission_revoked', 403);
        }
        if (!is_int($p['expectedRevision']) || $p['expectedRevision'] !== (int)($row['revision'] ?? 0)) {
            throw new NativeError('reminder_conflict', 409);
        }
        if ($cancel) {
            if (!$row) {
                throw new NativeError('reminder_missing', 404);
            }
            $uses = new NativeCryptoSchedulingUseV2($this->container, $this->bearer, $this->ip);
            $use = $uses->forReminder($actor['user']['account_id'], $id);
            if ($use && ($use['active'] || isset($p['accountEventProof']))) {
                $uses->companion($use['authorization'], $p['accountEventProof'] ?? [], false, $command, $actor);
            } elseif (isset($p['accountEventProof']) || isset($p['useProof'])) {
                throw new NativeError('crypto_scheduling_event_binding',409);
            }
            $this->change("UPDATE familyhub_crypto_reminders_v2 SET state='cancelled',revision=revision+1,authorization=? WHERE id=?", [json_encode($proof, JSON_THROW_ON_ERROR),$id]);
            return ['reminder' => $this->wireReminder($this->one('SELECT * FROM familyhub_crypto_reminders_v2 WHERE id=?', [$id]))];
        }
        if (!in_array($p['targetType'], ['task','event','financeEntry','personalFinanceEntry'], true)) {
            throw new NativeError('validation_error');
        }
        if (!is_array($p['targetIdentity'])) {
            throw new NativeError('validation_error');
        }
        $this->fields($p['targetIdentity'], ['sourceKind', 'canonicalId']);
        $targetId = NativeCryptoRecordAddressV2::wireId($p['targetId']);
        $domain = (new NativeCryptoRecordProofV2($this->container))->domain($p['targetType']);
        if (!$this->recipientVisible($sid, $actor['user']['account_id'], $domain)) {
            throw new NativeError('permission_revoked', 403);
        }
        $target = $this->one('SELECT * FROM familyhub_crypto_records WHERE scope_id=? AND id=? AND type=?', [$sid,$targetId,$p['targetType']]);
        if ($target && (new NativeCryptoModerationAvailabilityV2($this->container,$this->bearer,$this->ip))->restriction($sid,$targetId,(int)$target['revision'])) {
            throw new NativeError('crypto_content_restricted',403);
        }
        $metadata = $target ? json_decode($target['metadata'], true, 34, JSON_THROW_ON_ERROR) : null;
        if (!$metadata || NativeCryptoCodec::canonical((object)$p['targetIdentity']) !== NativeCryptoCodec::canonical((object)($metadata['identity'] ?? []))) {
            throw new NativeError('crypto_reminder_identity_binding', 409);
        }
        NativeCryptoRecordAddressV2::verify([
            'serverId' => $this->serverId(),
            'scopeId' => $sid, 'id' => $targetId, 'type' => $p['targetType'],
            'domain' => $domain, 'metadata' => ['identity' => $p['targetIdentity']],
        ]);
        $state = $metadata['reminderState'] ?? null;
        if (!$target || (int)$target['deleted'] || !$state || $state['closed'] || !$this->ancestorsOpen($sid, json_decode($target['metadata'], true, 34, JSON_THROW_ON_ERROR))) {
            throw new NativeError('reminder_target_unavailable', 409);
        }
        if ($row && ($row['target_id'] !== $targetId || $row['target_type'] !== $p['targetType'])) {
            throw new NativeError('reminder_target_immutable', 409);
        }
        (new NativeRecordPolicy($this->container))->date($p['remindAt']);
        $at = (new \DateTimeImmutable($p['remindAt']))->getTimestamp();
        $mode = $p['scheduleMode'] ?? 'absolute';
        $offset = $p['offsetMinutes'] ?? null;
        if ($mode === 'deadline') {
            if ($p['targetType'] !== 'task' || !is_int($offset) || !in_array($offset, [0,60,1440], true)) {
                throw new NativeError('validation_error');
            }
            if (isset($p['useProof'])) {
                $authorization=json_decode($target['authorization'],true,34,JSON_THROW_ON_ERROR);
                if (!is_int($p['targetDueAtEpoch']??null) || $p['targetDueAtEpoch']<0 || $p['targetDueAtEpoch']>253402300799 ||
                    ($p['targetRevision']??null)!==(int)$target['revision'] ||
                    ($p['targetRecordProofHash']??null)!==NativeCryptoSchedulingUseV2::proofHash($authorization['recordProof'])) {
                    throw new NativeError('crypto_scheduling_target_changed',409);
                }
                $uses=new NativeCryptoSchedulingUseV2($this->container,$this->bearer,$this->ip);
                if(isset($p['accountEventProof']))$uses->companion($p['useProof'],$p['accountEventProof'],true,$command,$actor,$target);
                else $uses->reuse($p['useProof'],$command,$actor,$target);
                $due=$p['targetDueAtEpoch'];
            } else {
                throw new NativeError('crypto_scheduling_use_required',409);
            }
            $at = $due - $offset * 60;
            if (isset($p['useProof']) && (new \DateTimeImmutable($p['remindAt']))->getTimestamp() !== $at) {
                throw new NativeError('crypto_scheduling_target_changed',409);
            }
            if ($at <= time()) {
                throw new NativeError('reminder_target_unavailable', 409);
            }
        } elseif ($mode !== 'absolute' || $offset !== null) {
            throw new NativeError('validation_error');
        } else {
            $uses = new NativeCryptoSchedulingUseV2($this->container,$this->bearer,$this->ip);
            $use = $uses->forReminder($actor['user']['account_id'],$id);
            if ($use && ($use['active'] || isset($p['accountEventProof']))) {
                $uses->companion($use['authorization'],$p['accountEventProof']??[],false,$command,$actor);
            } elseif (isset($p['accountEventProof']) || isset($p['useProof'])) {
                throw new NativeError('crypto_scheduling_event_binding',409);
            }
        }
        $values = [$sid,$actor['user']['account_id'],$p['targetType'],$targetId,$domain,(int)$target['revision'],$state['scheduleRevision'],gmdate('Y-m-d\TH:i:s\Z', $at),$at,$p['expectedRevision'] + 1,'pending',$mode,$offset,json_encode($proof, JSON_THROW_ON_ERROR)];
        if ($row) {
            $this->change('UPDATE familyhub_crypto_reminders_v2 SET scope_id=?,account_id=?,target_type=?,target_id=?,domain=?,target_revision=?,schedule_revision=?,remind_at=?,remind_epoch=?,revision=?,state=?,schedule_mode=?,offset_minutes=?,authorization=?,put_authorization=? WHERE id=?', array_merge($values, [json_encode($proof, JSON_THROW_ON_ERROR),$id]));
        } else {
            $count = $this->one("SELECT COUNT(*) AS n FROM familyhub_crypto_reminders_v2 WHERE account_id=? AND state='pending'", [$actor['user']['account_id']]);
            if ((int)$count['n'] >= 10000) {
                throw new NativeError('reminder_limit', 409);
            }
            $this->change('INSERT INTO familyhub_crypto_reminders_v2(scope_id,account_id,target_type,target_id,domain,target_revision,schedule_revision,remind_at,remind_epoch,revision,state,schedule_mode,offset_minutes,authorization,put_authorization,id) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)', array_merge($values, [json_encode($proof, JSON_THROW_ON_ERROR),$id]));
        }
        return ['reminder' => $this->wireReminder($this->one('SELECT * FROM familyhub_crypto_reminders_v2 WHERE id=?', [$id]))];
    }

    public function recipientVisible($sid, $account, $domain)
    {
        $user = $this->one('SELECT a.account_id,u.* FROM familyhub_accounts a JOIN users u ON u.id=a.user_id WHERE a.account_id=? AND u.is_active=1', [$account]);
        if (!$user) {
            return false;
        }
        try {
            $this->scope($sid, $user['id']);
            $scopes = new NativeCryptoScopeV2($this->container);
            $head = $scopes->current($sid);
            $member = $head ? $scopes->member($scopes->body($head), $account) : null;
            if (!$member) {
                return false;
            }
            if ($domain === 'finance') {
                if ($member['financeRole'] === 'none') {
                    return false;
                }
                (new NativeFinanceAccess($this->container))->policyForCrypto($sid, $user, false, true);
            }
            return true;
        } catch (NativeError $error) {
            if (in_array($error->status, [403,409], true)) {
                return false;
            }
            throw $error;
        }
    }

    /** Worker lock order matches ordinary scope mutations; fences never substitute for active crypto provenance. */
    public function lockDeliveryScope($sid)
    {
        $row = $this->one('SELECT parent_scope_id,organization_id FROM familyhub_scopes WHERE id=?', [$sid]);
        if (!$row) {
            return null;
        }
        $parent = $row['parent_scope_id'] ?? $row['organization_id'] ?? null;
        $parentRow = $parent ? $this->one('SELECT archived,deleted_at FROM familyhub_scopes WHERE id=?'.$this->lockSuffix(), [$parent]) : null;
        $scope = $this->one('SELECT * FROM familyhub_scopes WHERE id=?'.$this->lockSuffix(), [$sid]);
        if (!$scope || $parent && !$parentRow) {
            return null;
        }
        try {
            NativeCryptoScopeCreationV2::guardBusiness($this->pdo, $sid);
        } catch (NativeError $error) {
            if ($error->errorCode === 'crypto_migration_required') { return null; }
            throw $error;
        }
        $scope['archived'] = (int)$scope['archived'] || (int)($parentRow['archived'] ?? 0);
        if (($parentRow['deleted_at'] ?? null) !== null) {
            $scope['deleted_at'] = $parentRow['deleted_at'];
        }
        return $scope;
    }

    private function ancestorsOpen($sid, $metadata)
    {
        $pending = $metadata['references'];
        $seen = [];
        $steps = 0;
        while ($pending) {
            $ref = array_shift($pending);
            if ($ref['scopeId'] !== $sid || isset($seen[$ref['id']])) {
                continue;
            }
            $seen[$ref['id']] = true;
            if (++$steps > 100) {
                throw new NativeError('crypto_reference_graph_limit', 409);
            }
            $row = $this->one('SELECT type,deleted,metadata FROM familyhub_crypto_records WHERE scope_id=? AND id=?', [$sid,$ref['id']]);
            if (!$row) {
                return false;
            }
            $meta = json_decode($row['metadata'], true, 34, JSON_THROW_ON_ERROR);
            if ($row['type'] === 'project' && ((int)$row['deleted'] || !isset($meta['projectState']) || $meta['projectState']['archived'])) {
                return false;
            }
            foreach ($meta['references'] as $next) {
                $pending[] = $next;
            }
        }
        return true;
    }

    public function runDue($limit = 100)
    {
        if (!is_int($limit) || $limit < 1 || $limit > 500) {
            throw new NativeError('validation_error');
        }
        $rows = $this->many("SELECT r.id,r.scope_id FROM familyhub_crypto_reminders_v2 r WHERE r.state='pending' AND r.remind_epoch<=? AND ".NativeCryptoFence::workerDiscoverySql($this->pdo,'r.scope_id',true).' ORDER BY r.remind_epoch,r.id LIMIT '.$limit, [time()]);
        $counts = ['examined' => count($rows),'delivered' => 0,'cancelled' => 0];
        foreach ($rows as $candidate) {
            $out = $this->transaction(function () use ($candidate) {
                $scope = $this->lockDeliveryScope($candidate['scope_id']);
                if (!$scope) { return null; }
                $row = $this->one('SELECT * FROM familyhub_crypto_reminders_v2 WHERE id=?', [$candidate['id']]);
                if (!$row || $row['state'] !== 'pending' || (int)$row['remind_epoch'] > time()) {
                    return null;
                }
                $target = $this->one('SELECT * FROM familyhub_crypto_records WHERE scope_id=? AND id=?', [$row['scope_id'],$row['target_id']]);
                $state = $target ? json_decode($target['metadata'], true, 34, JSON_THROW_ON_ERROR)['reminderState'] ?? null : null;
                if (!$scope || (int)$scope['archived'] || $scope['deleted_at'] !== null || !$target || (int)$target['deleted'] || (new NativeCryptoModerationAvailabilityV2($this->container,$this->bearer,$this->ip))->restriction($row['scope_id'],$row['target_id'],(int)$target['revision']) || !$state || $state['closed'] || $row['schedule_revision'] !== $state['scheduleRevision'] || !$this->ancestorsOpen($row['scope_id'], json_decode($target['metadata'], true, 34, JSON_THROW_ON_ERROR)) || !$this->recipientVisible($row['scope_id'], $row['account_id'], $row['domain'])) {
                    $this->change("UPDATE familyhub_crypto_reminders_v2 SET state='cancelled',revision=revision+1 WHERE id=?", [$row['id']]);
                    return 'cancelled';
                }
                (new NativeNotificationWriter($this->container))->insert($row['scope_id'], $row['account_id'], null, $row['target_type'], $row['target_id'], (int)$target['revision'], 'crypto2.reminder.due', 'reminders', 'personal', hash('sha256', 'crypto2-reminder:'.$row['id'].':'.$row['revision']));
                $this->change("UPDATE familyhub_crypto_reminders_v2 SET state='delivered' WHERE id=?", [$row['id']]);
                return 'delivered';
            });
            if ($out !== null) {
                $counts[$out]++;
            }
        }
        return $counts;
    }

    public function read($op, $p, $actor)
    {
        if (str_starts_with($op, 'crypto2.inbox.')) {
            return $this->inboxRead($op, $p, $actor);
        }
        $this->fields($p, ['scopeId'], ['beforeId','limit']);
        $sid = $this->uuid($p['scopeId']);
        $this->scope($sid, $actor['user']['id']);
        $limit = $p['limit'] ?? 100;
        $before = isset($p['beforeId']) ? $this->uuid($p['beforeId']) : null;
        if (!is_int($limit) || $limit < 1 || $limit > 100) {
            throw new NativeError('invalid_cursor');
        }
        $rows = $this->many('SELECT * FROM familyhub_crypto_reminders_v2 WHERE scope_id=? AND account_id=?'.($before ? ' AND id<?' : '').' ORDER BY id DESC LIMIT '.($limit + 1), $before ? [$sid,$actor['user']['account_id'],$before] : [$sid,$actor['user']['account_id']]);
        $page = array_slice($rows, 0, $limit);
        $out = [];
        foreach ($page as $row) {
            if ($this->recipientVisible($sid, $actor['user']['account_id'], $row['domain'])) {
                $out[] = $this->wireReminder($row);
            }
        }
        return ['reminders' => $out,'hasMore' => count($rows) > $limit,'nextBeforeId' => count($rows) > $limit ? end($page)['id'] : null];
    }

    private function wireReminder($row)
    {
        $out = ['id' => $row['id'],'scopeId' => $row['scope_id'],'targetType' => $row['target_type'],'targetId' => $row['target_id'],'remindAt' => $row['remind_at'],'revision' => (int)$row['revision'],'state' => $row['state'],'authorization' => json_decode($row['authorization'], true, 34, JSON_THROW_ON_ERROR),'putAuthorization' => $row['put_authorization'] === null ? null : json_decode($row['put_authorization'], true, 34, JSON_THROW_ON_ERROR),'targetRevision' => (int)$row['target_revision'],'scheduleRevision' => $row['schedule_revision']];
        $out['schedulingUse']=(new NativeCryptoSchedulingUseV2($this->container,$this->bearer,$this->ip))->forReminder($row['account_id'],$row['id']);
        if ($out['putAuthorization'] !== null) {
            [$put] = NativeCryptoCodec::decode($out['putAuthorization']);
            $out['targetIdentity'] = $put['payload']['targetIdentity'] ?? null;
        }
        if ($row['schedule_mode'] === 'deadline') {
            $out += ['scheduleMode' => 'deadline','offsetMinutes' => (int)$row['offset_minutes']];
        }
        return $out;
    }

    private function inboxVisible($row, $actor)
    {
        if (!$row || $row['recipient_account_id'] !== $actor['user']['account_id'] || !str_starts_with($row['kind'], 'crypto2.') || NativeInboxRetention::expired($row)) {
            return false;
        }
        $domain = $this->routingDomain($row['target_type']);
        return $this->recipientVisible($row['scope_id'], $row['recipient_account_id'], $domain);
    }

    private function inboxWire($row)
    {
        $wire = (new NativeInboxService($this->container))->wire($row);
        $wire['kind'] = substr($row['kind'], 8);
        $target = $this->one('SELECT metadata FROM familyhub_crypto_records WHERE scope_id=? AND id=? AND type=?', [$row['scope_id'], $row['target_id'], $row['target_type']]);
        $wire['targetIdentity'] = $target ? (json_decode($target['metadata'], true, 34, JSON_THROW_ON_ERROR)['identity'] ?? null) : null;
        if ($row['target_type'] === 'membership') {
            $wire['targetIdentity'] = ['sourceKind'=>'membership','canonicalId'=>$row['target_id']];
        } elseif ($wire['targetIdentity'] === null) {
            $baseline = $this->one('SELECT target_identity FROM familyhub_crypto_migration_inbox_v3 WHERE account_id=? AND inbox_id=?',[$row['recipient_account_id'],$row['id']]);
            $wire['targetIdentity'] = $baseline ? json_decode($baseline['target_identity'],true,34,JSON_THROW_ON_ERROR) : null;
        }
        return $wire;
    }

    private function preferences($p, $actor, $write)
    {
        $this->fields($p, $write ? ['scopeId','category','settings'] : ['scopeId']);
        $sid = $this->uuid($p['scopeId']);
        $account = $actor['user']['account_id'];
        $this->scope($sid, $actor['user']['id']);
        if ($write) {
            if (!in_array($p['category'], NativeNotificationPreferences::CATEGORIES, true) || !is_array($p['settings'])) {
                throw new NativeError('validation_error');
            }
            $this->fields($p['settings'], ['inApp','sound','push','email']);
            foreach ($p['settings'] as $value) {
                if (!is_bool($value)) {
                    throw new NativeError('validation_error');
                }
            }
            $this->change('DELETE FROM familyhub_inbox_preferences WHERE scope_id=? AND account_id=? AND category=?', [$sid,$account,$p['category']]);
            $this->change('INSERT INTO familyhub_inbox_preferences VALUES(?,?,?,?)', [$sid,$account,$p['category'],json_encode($p['settings'], JSON_THROW_ON_ERROR)]);
        }
        $out = array_fill_keys(NativeNotificationPreferences::CATEGORIES, NativeNotificationPreferences::resolve());
        foreach ($this->many('SELECT category,settings FROM familyhub_inbox_preferences WHERE scope_id=? AND account_id=?', [$sid,$account]) as $row) {
            $out[$row['category']] = NativeNotificationPreferences::resolve($row['settings']);
        }
        return ['preferences' => $out];
    }

    private function inboxWrite($op, $p, $actor)
    {
        if ($op === 'crypto2.inbox.preferences.set') {
            return $this->preferences($p, $actor, true);
        }
        $this->fields($p, ['id','read','expectedRevision']);
        if ($op !== 'crypto2.inbox.read' || !is_int($p['id']) || $p['id'] < 1 || !is_bool($p['read']) || !is_int($p['expectedRevision'])) {
            throw new NativeError('validation_error');
        }
        $row = $this->one('SELECT * FROM familyhub_inbox WHERE id=?', [$p['id']]);
        if (!$this->inboxVisible($row, $actor)) {
            throw new NativeError('permission_revoked', 403);
        }
        if ((int)$row['revision'] !== $p['expectedRevision']) {
            throw new NativeError('inbox_conflict', 409, ['item' => $this->inboxWire($row)]);
        }
        if ($p['read'] !== ($row['read_at'] !== null)) {
            $sequence = (new NativeNotificationWriter($this->container))->next($actor['user']['account_id']);
            $this->change('UPDATE familyhub_inbox SET read_at=?,revision=revision+1,sequence=? WHERE id=?', [$p['read'] ? gmdate('Y-m-d\TH:i:s\Z') : null,$sequence,$p['id']]);
        }
        return ['item' => $this->inboxWire($this->one('SELECT * FROM familyhub_inbox WHERE id=?', [$p['id']]))];
    }

    private function inboxRead($op, $p, $actor)
    {
        if ($op === 'crypto2.inbox.preferences.get') {
            return $this->preferences($p, $actor, false);
        }
        $account = $actor['user']['account_id'];
        if (in_array($op, ['crypto2.inbox.open','crypto2.inbox.group'], true)) {
            $this->fields($p, ['id'], $op === 'crypto2.inbox.group' ? ['beforeId','limit'] : []);
            if (!is_int($p['id']) || $p['id'] < 1) {
                throw new NativeError('validation_error');
            }
            $anchor = $this->one('SELECT * FROM familyhub_inbox WHERE id=?', [$p['id']]);
            if (!$this->inboxVisible($anchor, $actor)) {
                throw new NativeError('permission_revoked', 403);
            }
            if ($op === 'crypto2.inbox.open') {
                return ['item' => $this->inboxWire($anchor),'target' => ['scopeId' => $anchor['scope_id'],'type' => $anchor['target_type'],'id' => $anchor['target_id']],'record' => null,'contextRecord' => null];
            }
        } else {
            $this->fields($p, $op === 'crypto2.inbox.sync' ? ['cursor'] : [], $op === 'crypto2.inbox.sync' ? ['limit','visibilityRevision'] : ['beforeId','limit','scopeId']);
        }
        $limit = $p['limit'] ?? 50;
        if (!is_int($limit) || $limit < 1 || $limit > 100) {
            throw new NativeError('invalid_cursor');
        }
        $args = [$account,NativeInboxRetention::cutoff()];
        $where = "recipient_account_id=? AND (read_at IS NULL OR read_at>?) AND kind LIKE 'crypto2.%'";
        if ($op === 'crypto2.inbox.sync') {
            $state = (new NativeNotificationWriter($this->container))->state($account);
            if (!is_int($p['cursor']) || $p['cursor'] < 0 || $p['cursor'] > (int)$state['sequence']) {
                throw new NativeError('invalid_cursor');
            }
            if (($p['cursor'] > 0 && !isset($p['visibilityRevision'])) || isset($p['visibilityRevision']) && $p['visibilityRevision'] !== (int)$state['visibility_revision']) {
                throw new NativeError('visibility_changed', 409, ['visibilityRevision' => (int)$state['visibility_revision']]);
            }
            $where .= ' AND sequence>?';
            $args[] = $p['cursor'];
            $order = 'sequence';
        } else {
            $before = $p['beforeId'] ?? PHP_INT_MAX;
            if (!is_int($before) || $before < 1) {
                throw new NativeError('invalid_cursor');
            }
            $where .= ' AND id<?';
            $args[] = $before;
            $order = 'id DESC';
            if (isset($p['scopeId'])) {
                $sid = $this->uuid($p['scopeId']);
                $this->scope($sid, $actor['user']['id']);
                $where .= ' AND scope_id=?';
                $args[] = $sid;
            }
            if (isset($anchor)) {
                $where .= ' AND scope_id=? AND group_key=? AND kind=? AND category=? AND audience=? AND id<=?';
                array_push($args, $anchor['scope_id'], $anchor['group_key'], $anchor['kind'], $anchor['category'], $anchor['audience'], $anchor['id']);
            }
        }
        $rows = $this->many('SELECT * FROM familyhub_inbox WHERE '.$where.' ORDER BY '.$order.' LIMIT '.($limit + 1), $args);
        $page = array_slice($rows, 0, $limit);
        $out = [];
        foreach ($page as $row) {
            if ((int)$row['in_app'] === 1 && $this->inboxVisible($row, $actor)) {
                $out[] = $this->inboxWire($row);
            }
        }
        $more = count($rows) > $limit;
        if ($op === 'crypto2.inbox.sync') {
            return ['items' => $out,'cursor' => $more ? (int)end($page)['sequence'] : (int)$state['sequence'],'hasMore' => $more,'visibilityRevision' => (int)$state['visibility_revision']];
        }
        return ['items' => $out,'hasMore' => $more,'nextBeforeId' => $more ? (int)end($page)['id'] : null];
    }
}
