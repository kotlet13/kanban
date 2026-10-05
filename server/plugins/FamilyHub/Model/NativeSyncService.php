<?php
namespace Kanboard\Plugin\FamilyHub\Model;

class NativeSyncService extends NativeDatabase
{
    private $version = 1;

    const MAX_PAYLOAD_BYTES = 8192;
    const MAX_PAGE_BYTES = 524288;

    public function execute($operation, array $params)
    {
        $this->version = str_starts_with($operation, 'sync2.') ? 2 : 1;
        $this->rate([['sync-ip:'.$this->ip, 2400, 60]]);
        $result = $this->transaction(function () use ($operation, $params) {
            $actor = $this->actor(); $userId = $actor['user']['id'];
            if (in_array($operation, ['sync.pull', 'sync2.pull'], true)) { return $this->pull($params, $userId); }
            if (!in_array($operation, ['sync.push', 'sync2.push'], true)) { throw new NativeError('unsupported_operation', 404); }
            $this->fields($params, ['scopeId', 'operation']);
            $scopeId = $this->uuid($params['scopeId']);
            $scope = $this->scope($scopeId, $userId, true);
            $op = $params['operation'];
            if (!is_array($op)) { throw new NativeError('validation_error'); }
            $this->fields($op, ['opId', 'recordId', 'type', 'expectedRevision', 'deleted', 'payload']);
            $opId = $this->uuid($op['opId']); $recordId = $this->uuid($op['recordId']);
            if (!in_array($op['type'], ($this->version === 2 ? ['project', 'task', 'event', 'shoppingList', 'shoppingItem'] : ['project', 'task', 'shoppingList', 'shoppingItem']), true) ||
                    !is_int($op['expectedRevision']) || $op['expectedRevision'] < 0 || !is_bool($op['deleted'])) {
                throw new NativeError('validation_error');
            }
            $hash = $this->hashRequest($operation, $params);
            $replay = $this->replay($scopeId, $userId, $opId, $hash);
            if ($replay) {
                if ($replay['status'] !== 200) { return new NativeError($replay['body']['errorCode'], $replay['status'], $replay['body']['details']); }
                $replay['body']['replayed'] = true;
                return $replay['body'];
            }
            $this->requireCompatible($scopeId);
            $current = $this->one('SELECT * FROM familyhub_records WHERE scope_id=? AND id=?', [$scopeId, $recordId]);
            if (($current && ((int)$current['revision'] !== $op['expectedRevision'] || (int)$current['deleted'] === 1 || $current['type'] !== $op['type'])) ||
                    (!$current && ($op['expectedRevision'] !== 0 || $op['deleted']))) {
                $details = ['serverRecord' => $current ? $this->wire($current) : null];
                $this->remember($scopeId, $userId, $opId, $hash, ['errorCode' => 'conflict', 'details' => $details], 409);
                // Return error as a value: the durable conflict outcome must commit.
                return new NativeError('conflict', 409, $details);
            }
            try {
                if ($op['deleted']) {
                    if ($op['payload'] !== null) { throw new NativeError('validation_error'); }
                    (new NativeRecordPolicy($this->container))->noChildren($scopeId, $recordId, $op['type']);
                } else {
                    (new NativeRecordPolicy($this->container))->validate($op['type'], $op['payload'], $scopeId, $current, $this->version);
                }
            } catch (NativeError $error) {
                if (!in_array($error->errorCode, ['parent_missing', 'live_children', 'assignee_not_member'], true)) { throw $error; }
                $details = ['serverRecord' => $current ? $this->wire($current) : null];
                $this->remember($scopeId, $userId, $opId, $hash, ['errorCode' => $error->errorCode, 'details' => $details], 422);
                return new NativeError($error->errorCode, 422, $details);
            }
            $sequence = $this->advance($scope); $revision = $op['expectedRevision'] + 1;
            $updated = gmdate('Y-m-d\TH:i:s\Z');
            $payload = $op['deleted'] ? null : json_encode($op['payload'], JSON_UNESCAPED_UNICODE | JSON_THROW_ON_ERROR);
            if ($current) {
                $this->change('UPDATE familyhub_records SET revision=?,deleted=?,payload=?,sequence=?,updated_at=?,contract_version=?,updated_by=? WHERE scope_id=? AND id=?', [$revision, (int)$op['deleted'], $payload, $sequence, $updated, $this->version, $actor['user']['account_id'], $scopeId, $recordId]);
            } else {
                $this->change('INSERT INTO familyhub_records(scope_id,id,type,revision,deleted,payload,sequence,updated_at,contract_version,created_by,updated_by) VALUES(?,?,?,?,?,?,?,?,?,?,?)', [$scopeId, $recordId, $op['type'], $revision, 0, $payload, $sequence, $updated, $this->version, $actor['user']['account_id'], $actor['user']['account_id']]);
            }
            $record = $this->wire($this->one('SELECT * FROM familyhub_records WHERE scope_id=? AND id=?', [$scopeId, $recordId]));
            (new NativeNotificationWriter($this->container))->recordChanged($scopeId, $record, $current, $actor['user']['account_id']);
            (new NativeReminderService($this->container))->reconcile($scopeId, $record, $current);
            $response = ['status' => 'applied', 'record' => $record, 'cursor' => $sequence, 'replayed' => false];
            $this->remember($scopeId, $userId, $opId, $hash, $response);
            return $response;
        });
        if ($result instanceof NativeError) { throw $result; }
        return $result;
    }

    private function pull(array $params, $userId)
    {
        $this->fields($params, ['scopeId', 'cursor'], ['limit']);
        $scopeId = $this->uuid($params['scopeId']); $scope = $this->scope($scopeId, $userId);
        $this->requireCompatible($scopeId);
        $limit = $params['limit'] ?? 100;
        if (!is_int($params['cursor']) || $params['cursor'] < 0 || $params['cursor'] > (int)$scope['sequence'] || !is_int($limit) || $limit < 1 || $limit > 500) { throw new NativeError('invalid_cursor'); }
        $rows = $this->many('SELECT * FROM familyhub_records WHERE scope_id=? AND sequence>? ORDER BY sequence LIMIT '.($limit + 1), [$scopeId, $params['cursor']]);
        $records = []; $bytes = 0;
        foreach ($rows as $row) {
            $record = $this->wire($row); $size = strlen(json_encode($record, JSON_UNESCAPED_UNICODE | JSON_THROW_ON_ERROR));
            if (count($records) >= $limit || ($records && $bytes + $size > self::MAX_PAGE_BYTES)) { break; }
            $records[] = $record; $bytes += $size;
        }
        $hasMore = count($rows) > count($records);
        $cursor = $hasMore ? $records[count($records) - 1]['sequence'] : (int)$scope['sequence'];
        return ['records' => $records, 'cursor' => $cursor, 'hasMore' => $hasMore, 'scopeSequence' => (int)$scope['sequence']];
    }

    private function requireCompatible($scopeId)
    {
        if ($this->version === 1 && $this->one('SELECT id FROM familyhub_records WHERE scope_id=? AND contract_version=2 LIMIT 1', [$scopeId])) {
            throw new NativeError('client_upgrade_required', 409);
        }
    }

    private function wire(array $row)
    {
        return (new NativeRecordPolicy($this->container))->wire($row, $this->version);
    }
}
