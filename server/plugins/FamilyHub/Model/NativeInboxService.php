<?php
namespace Kanboard\Plugin\FamilyHub\Model;

class NativeInboxService extends NativeDatabase
{
    const CATEGORIES = ['tasks', 'events', 'shopping', 'finance', 'reminders', 'membership'];

    public function execute($operation, array $params)
    {
        $this->rate([['inbox-ip:'.$this->ip, 600, 60]]);
        return $this->transaction(function () use ($operation, $params) {
            $user = $this->actor()['user']; $account = $user['account_id'];
            if ($operation === 'inbox.sync') { return $this->sync($params, $account); }
            if ($operation === 'inbox.group') { return (new NativeInboxGroup($this->container))->page($params,$user); }
            if ($operation === 'inbox.list') {
                $this->fields($params, [], ['beforeId', 'limit', 'scopeId']);
                $limit = $this->limit($params); $before = $params['beforeId'] ?? PHP_INT_MAX;
                if (!is_int($before) || $before < 1) { throw new NativeError('validation_error'); }
                $scope = isset($params['scopeId']) ? $this->uuid($params['scopeId']) : null;
                $rows = $this->many('SELECT * FROM familyhub_inbox WHERE recipient_account_id=? AND id<?'.($scope ? ' AND scope_id=?' : '').' ORDER BY id DESC LIMIT '.($limit + 1), $scope ? [$account, $before, $scope] : [$account, $before]);
                $scanned = array_slice($rows, 0, $limit);
                $page = array_values(array_filter($scanned, fn ($row) => (int)$row['in_app'] === 1 && $this->visible($row, $account)));
                return ['items' => array_map([$this, 'wire'], $page), 'nextBeforeId' => count($rows) > $limit ? (int)end($scanned)['id'] : null, 'hasMore' => count($rows) > $limit];
            }
            if (str_starts_with($operation, 'inbox.preferences.')) { return $this->preferences($operation, $params, $user); }
            if (!in_array($operation, ['inbox.read', 'inbox.open'], true)) { throw new NativeError('unsupported_operation', 404); }
            $this->fields($params, $operation === 'inbox.open' ? ['id'] : ['id', 'read', 'expectedRevision', 'requestId']);
            if (!is_int($params['id']) || $params['id'] < 1) { throw new NativeError('validation_error'); }
            $row = $this->one('SELECT * FROM familyhub_inbox WHERE id=? AND recipient_account_id=?', [$params['id'], $account]);
            if (!$row) { throw new NativeError('permission_revoked', 403); }
            $this->scope($row['scope_id'], $user['id']);
            if (!$this->visible($row, $account)) { throw new NativeError('permission_revoked', 403); }
            if ($operation === 'inbox.open') {
                $finance = str_starts_with($row['target_type'], 'finance');
                if ($finance) { (new NativeFinanceAccess($this->container))->policy($row['scope_id'], $user); }
                $target = ['scopeId' => $row['scope_id'], 'type' => $row['target_type'], 'id' => $row['target_id']];
                $record = $row['target_type'] === 'membership' ? null : $this->one('SELECT * FROM '.($finance ? 'familyhub_finance_records' : 'familyhub_records').' WHERE scope_id=? AND id=?', [$row['scope_id'], $row['target_id']]);
                return ['item' => $this->wire($row), 'target' => $target, 'record' => $record ? (new NativeRecordPolicy($this->container))->wire($record) : null];
            }
            if (!is_bool($params['read']) || !is_int($params['expectedRevision'])) { throw new NativeError('validation_error'); }
            $request = $this->uuid($params['requestId']); $hash = $this->hashRequest($operation, $params);
            $writer = new NativeNotificationWriter($this->container); $writer->state($account);
            $replay = $this->replay($row['scope_id'], $user['id'], $request, $hash);
            if ($replay) { return $replay['body']; }
            $row = $this->one('SELECT * FROM familyhub_inbox WHERE id=?', [$row['id']]);
            if ((int)$row['revision'] !== $params['expectedRevision']) { throw new NativeError('inbox_conflict', 409, ['item' => $this->wire($row)]); }
            $this->change('UPDATE familyhub_inbox SET read_at=?,revision=revision+1,sequence=? WHERE id=?', [$params['read'] ? gmdate('Y-m-d\TH:i:s\Z') : null, $writer->next($account), $row['id']]);
            $response = ['item' => $this->wire($this->one('SELECT * FROM familyhub_inbox WHERE id=?', [$row['id']]))];
            $this->remember($row['scope_id'], $user['id'], $request, $hash, $response);
            return $response;
        });
    }

    private function sync($params, $account)
    {
        $this->fields($params, ['cursor'], ['limit', 'visibilityRevision']);
        $state = (new NativeNotificationWriter($this->container))->state($account);
        $cursor = $params['cursor']; $revision = (int)$state['visibility_revision'];
        if (!is_int($cursor) || $cursor < 0 || $cursor > (int)$state['sequence']) { throw new NativeError('invalid_cursor'); }
        if (($cursor > 0 && !isset($params['visibilityRevision'])) || (isset($params['visibilityRevision']) && $params['visibilityRevision'] !== $revision)) {
            throw new NativeError('visibility_changed', 409, ['visibilityRevision' => $revision]);
        }
        $limit = $this->limit($params);
        $rows = $this->many('SELECT * FROM familyhub_inbox WHERE recipient_account_id=? AND sequence>? ORDER BY sequence LIMIT '.($limit + 1), [$account, $cursor]);
        $page = array_slice($rows, 0, $limit); $hasMore = count($rows) > $limit;
        return ['items' => array_map([$this, 'wire'], array_values(array_filter($page, fn ($row) => (int)$row['in_app'] === 1 && $this->visible($row, $account)))),
                'cursor' => $hasMore ? (int)end($page)['sequence'] : (int)$state['sequence'], 'hasMore' => $hasMore, 'visibilityRevision' => $revision];
    }

    private function preferences($operation, $params, $user)
    {
        $write = $operation === 'inbox.preferences.set';
        $this->fields($params, $write ? ['scopeId', 'category', 'settings', 'requestId'] : ['scopeId']);
        $scope = $this->uuid($params['scopeId']); $this->scope($scope, $user['id']);
        if ($write) {
            if (!in_array($params['category'], self::CATEGORIES, true) || !is_array($params['settings'])) { throw new NativeError('validation_error'); }
            $this->fields($params['settings'], ['inApp', 'sound', 'push', 'email']);
            foreach ($params['settings'] as $value) { if (!is_bool($value)) { throw new NativeError('validation_error'); } }
            $request = $this->uuid($params['requestId']); $hash = $this->hashRequest($operation, $params);
            $replay = $this->replay($scope, $user['id'], $request, $hash); if ($replay) { return $replay['body']; }
            $this->change('DELETE FROM familyhub_inbox_preferences WHERE scope_id=? AND account_id=? AND category=?', [$scope, $user['account_id'], $params['category']]);
            $this->change('INSERT INTO familyhub_inbox_preferences VALUES(?,?,?,?)', [$scope, $user['account_id'], $params['category'], json_encode($params['settings'], JSON_THROW_ON_ERROR)]);
        }
        $preferences = array_fill_keys(self::CATEGORIES, ['inApp' => true, 'sound' => false, 'push' => false, 'email' => false]);
        foreach ($this->many('SELECT * FROM familyhub_inbox_preferences WHERE scope_id=? AND account_id=?', [$scope, $user['account_id']]) as $row) { $preferences[$row['category']] = json_decode($row['settings'], true, 32, JSON_THROW_ON_ERROR); }
        $response = ['preferences' => $preferences];
        if ($write) { $this->remember($scope, $user['id'], $request, $hash, $response); }
        return $response;
    }

    private function limit($params)
    {
        $limit = $params['limit'] ?? 50;
        if (!is_int($limit) || $limit < 1 || $limit > 100) { throw new NativeError('validation_error'); }
        return $limit;
    }

    private function visible($row, $account)
    {
        return (new NativeFinanceAccess($this->container))->visible($row['scope_id'], $account, str_starts_with($row['target_type'], 'finance'));
    }

    public function wire($row)
    {
        return ['id' => (int)$row['id'], 'revision' => (int)$row['revision'], 'sequence' => (int)$row['sequence'], 'targetRevision' => (int)$row['target_revision'],
                'scopeId' => $row['scope_id'], 'kind' => $row['kind'], 'category' => $row['category'], 'audience' => $row['audience'], 'actorAccountId' => $row['actor_account_id'],
                'targetType' => $row['target_type'], 'targetId' => $row['target_id'], 'groupKey' => $row['group_key'], 'createdAt' => $row['created_at'], 'readAt' => $row['read_at']];
    }
}
