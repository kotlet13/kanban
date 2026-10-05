<?php
namespace Kanboard\Plugin\FamilyHub\Model;

/** Versioned business payload validation, independent of sync transaction orchestration. */
class NativeRecordPolicy extends NativeDatabase
{
    public function validate($type, $payload, $scopeId, $current, $version)
    {
        $personal = ($this->one('SELECT kind FROM familyhub_scopes WHERE id=?', [$scopeId])['kind'] ?? '') === 'personal';
        if (!is_array($payload) || array_is_list($payload) || strlen(json_encode($payload, JSON_UNESCAPED_UNICODE | JSON_THROW_ON_ERROR)) > ($personal ? 524288 : 8192)) { throw new NativeError('validation_error'); }
        $specific = match ($type) {
            'project' => ['title', 'description', 'area'],
            'task' => ['title', 'notes', 'projectId', 'dueAt', 'isCompleted'],
            'event' => ['title', 'notes', 'projectId', 'startAt', 'endAt', 'assigneeAccountIds'],
            'shoppingList' => ['title'],
            'shoppingItem' => ['listId', 'title', 'quantity', 'isChecked'],
            default => throw new NativeError('validation_error'),
        };
        if ($version === 2 && in_array($type, ['project', 'task'], true)) {
            $specific = array_merge($specific, ['startAt', 'endAt'], $type === 'task' ? ['assigneeAccountIds'] : []);
        }
        $this->fields($payload, array_merge($specific, ['createdAt', 'updatedAt']));
        $this->domainText($payload['title'], 300, 500, $personal); $this->date($payload['createdAt']); $this->date($payload['updatedAt']);
        if ($current && new \DateTimeImmutable(json_decode($current['payload'], true, 32, JSON_THROW_ON_ERROR)['createdAt']) != new \DateTimeImmutable($payload['createdAt'])) { throw new NativeError('created_at_immutable'); }
        if ($type === 'project') {
            $this->domainText($payload['description'], 4096, 50000, $personal, true);
            if (!in_array($payload['area'], ['personal', 'home'], true)) { throw new NativeError('validation_error'); }
        }
        if (in_array($type, ['task', 'event'], true)) {
            $this->domainText($payload['notes'], 4096, 50000, $personal, true);
            if ($payload['projectId'] !== null) { $this->parentRecord($scopeId, $payload['projectId'], 'project'); }
        }
        if ($type === 'task') {
            if (!is_bool($payload['isCompleted'])) { throw new NativeError('validation_error'); }
            if ($payload['dueAt'] !== null) { $this->date($payload['dueAt']); }
        }
        if ($version === 2 && in_array($type, ['project', 'task', 'event'], true)) {
            if ($payload['startAt'] !== null) { $this->date($payload['startAt']); }
            elseif ($type === 'event') { throw new NativeError('validation_error'); }
            if ($payload['endAt'] !== null) { $this->date($payload['endAt']); }
            if ($payload['startAt'] !== null && $payload['endAt'] !== null && new \DateTimeImmutable($payload['endAt']) < new \DateTimeImmutable($payload['startAt'])) { throw new NativeError('invalid_date_range'); }
        }
        if ($version === 2 && in_array($type, ['task', 'event'], true)) { $this->assignees($scopeId, $payload['assigneeAccountIds']); }
        if ($type === 'shoppingItem') {
            $this->domainText($payload['quantity'], 100, 100, $personal, true);
            if (!is_bool($payload['isChecked'])) { throw new NativeError('validation_error'); }
            $this->parentRecord($scopeId, $payload['listId'], 'shoppingList');
        }
    }

    public function domainText($value, $sharedBytes, $privateUnits, $personal, $empty = false)
    {
        $this->text($value, $personal ? $privateUnits * 4 : $sharedBytes, $empty);
        if ($personal && strlen(mb_convert_encoding($value, 'UTF-16LE', 'UTF-8')) > $privateUnits * 2) { throw new NativeError('validation_error'); }
    }

    public function date($value)
    {
        if (!is_string($value) || !preg_match('/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,6})?Z$/D', $value)) { throw new NativeError('validation_error'); }
        try { $date = new \DateTimeImmutable($value); } catch (\Throwable $error) { throw new NativeError('validation_error'); }
        if ($date->format('Y-m-d\TH:i:s') !== substr($value, 0, 19)) { throw new NativeError('validation_error'); }
    }

    public function assignees($scopeId, $ids)
    {
        if (!is_array($ids) || !array_is_list($ids) || count($ids) > 20 || count(array_unique($ids, SORT_REGULAR)) !== count($ids)) { throw new NativeError('validation_error'); }
        foreach ($ids as $id) {
            $this->uuid($id);
            if (!(new NativeFinanceAccess($this->container))->visible($scopeId, $id) || !$this->one('SELECT m.account_id FROM familyhub_members m JOIN familyhub_accounts a ON a.account_id=m.account_id JOIN users u ON u.id=a.user_id WHERE m.scope_id=? AND m.account_id=? AND m.active=1 AND u.is_active=1', [$scopeId, $id])) { throw new NativeError('assignee_not_member'); }
        }
    }

    public function parentRecord($scope, $id, $type)
    {
        $this->uuid($id);
        $row = $this->one('SELECT type,deleted FROM familyhub_records WHERE scope_id=? AND id=?', [$scope, $id]);
        if (!$row || $row['type'] !== $type || (int)$row['deleted'] !== 0) { throw new NativeError('parent_missing'); }
    }

    public function noChildren($scope, $id, $type)
    {
        $types = $type === 'project' ? ['task', 'event'] : ($type === 'shoppingList' ? ['shoppingItem'] : []);
        if ($type === 'project') {
            foreach ($this->iterate('SELECT payload FROM familyhub_finance_records WHERE scope_id=? AND type=\'personalFinanceEntry\' AND deleted=0', [$scope]) as $row) {
                if ((json_decode($row['payload'], true, 32, JSON_THROW_ON_ERROR)['projectId'] ?? null) === $id) { throw new NativeError('live_children'); }
            }
        }
        foreach ($types as $childType) {
            $field = $type === 'project' ? 'projectId' : 'listId';
            foreach ($this->iterate('SELECT payload FROM familyhub_records WHERE scope_id=? AND type=? AND deleted=0', [$scope, $childType]) as $row) {
                if (json_decode($row['payload'], true, 32, JSON_THROW_ON_ERROR)[$field] === $id) { throw new NativeError('live_children'); }
            }
        }
    }

    public function wire(array $row, $version = 2)
    {
        $payload = $row['payload'] === null ? null : json_decode($row['payload'], true, 32, JSON_THROW_ON_ERROR);
        if ($version === 2 && $payload !== null && in_array($row['type'], ['project', 'task'], true)) {
            $payload += ['startAt' => null, 'endAt' => null];
            if ($row['type'] === 'task') { $payload += ['assigneeAccountIds' => []]; }
        }
        $wire = ['id' => $row['id'], 'type' => $row['type'], 'revision' => (int)$row['revision'], 'deleted' => (int)$row['deleted'] === 1,
                 'payload' => $payload, 'sequence' => (int)$row['sequence'], 'updatedAt' => $row['updated_at']];
        if ($version === 2) { $wire += ['createdByAccountId' => $row['created_by'], 'updatedByAccountId' => $row['updated_by']]; }
        return $wire;
    }
}
