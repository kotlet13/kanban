<?php
namespace Kanboard\Plugin\FamilyHub\Model;

/** Called in source transaction. Only IDs/provenance, never content snapshots. */
class NativeNotificationWriter extends NativeDatabase
{
    public function state($accountId)
    {
        $insert = $this->sqlite ? 'INSERT OR IGNORE' : 'INSERT IGNORE';
        $this->change($insert.' INTO familyhub_inbox_state(account_id,sequence,visibility_revision) VALUES(?,0,0)', [$accountId]);
        return $this->one('SELECT * FROM familyhub_inbox_state WHERE account_id=?'.$this->lockSuffix(), [$accountId]);
    }

    public function next($accountId)
    {
        $state = $this->state($accountId); $sequence = (int)$state['sequence'] + 1;
        $this->change('UPDATE familyhub_inbox_state SET sequence=? WHERE account_id=?', [$sequence, $accountId]);
        return $sequence;
    }

    public function visibilityChanged($accountIds)
    {
        sort($accountIds, SORT_STRING);
        foreach (array_unique($accountIds) as $id) {
            $this->state($id);
            $this->change('UPDATE familyhub_inbox_state SET visibility_revision=visibility_revision+1 WHERE account_id=?', [$id]);
        }
    }

    public function insert($scope, $recipient, $actor, $type, $id, $revision, $kind, $category, $audience, $eventKey, $groupTarget = null)
    {
        $preference = $this->one('SELECT settings FROM familyhub_inbox_preferences WHERE scope_id=? AND account_id=? AND category=?', [$scope, $recipient, $category]);
        $settings = $preference ? json_decode($preference['settings'], true, 32, JSON_THROW_ON_ERROR) : ['inApp' => true, 'email' => false, 'push' => false];
        if (!$settings['inApp'] && !$settings['email'] && !$settings['push']) { return; }
        $this->state($recipient);
        if ($this->one('SELECT id FROM familyhub_inbox WHERE event_key=? AND recipient_account_id=?', [$eventKey, $recipient])) { return; }
        $sequence = $this->next($recipient);
        $group = $scope.':'.($groupTarget ?? $id).':'.$category.':'.$audience.':'.intdiv(time(), 300);
        $this->change('INSERT INTO familyhub_inbox(event_key,recipient_account_id,scope_id,category,kind,audience,actor_account_id,target_type,target_id,target_revision,group_key,created_at,sequence,in_app) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?)',
            [$eventKey, $recipient, $scope, $category, $kind, $audience, $actor, $type, $id, $revision, $group, gmdate('Y-m-d\TH:i:s\Z'), $sequence, (int)$settings['inApp']]);
        $row = $this->one('SELECT id FROM familyhub_inbox WHERE event_key=? AND recipient_account_id=?', [$eventKey, $recipient]);
        if ($settings['email']) {
            (new NativeDeliveryService($this->container))->enqueue((int)$row['id']);
        }
        if ($settings['push']) { (new NativePushQueue($this->container))->enqueue((int)$row['id'],$recipient); }
    }

    public function recordChanged($scope, array $record, $previous, $actorId, $finance = false, $eventKey = null)
    {
        if (in_array($record['type'],['householdPerson','garden'],true)) { return; }
        $type = $record['type']; $payload = $record['payload'];
        $before = $previous ? json_decode($previous['payload'] ?? 'null', true, 32, JSON_THROW_ON_ERROR) : null;
        $category = $finance ? 'finance' : match ($type) { 'task', 'project' => 'tasks', 'event' => 'events', default => 'shopping' };
        $base = $record['deleted'] ? 'deleted' : ($previous ? 'updated' : 'created');
        if (!$record['deleted'] && $type === 'task' && $payload['isCompleted'] && !($before['isCompleted'] ?? false)) { $base = 'completed'; }
        if (!$record['deleted'] && $type === 'shoppingItem' && $payload['isChecked'] && !($before['isChecked'] ?? false)) { $base = 'checked'; }
        $assignees = ($payload ?? $before)['assigneeAccountIds'] ?? [];
        $rows = $this->many('SELECT m.account_id FROM familyhub_members m JOIN familyhub_accounts a ON a.account_id=m.account_id AND a.user_id=m.user_id JOIN users u ON u.id=a.user_id WHERE m.scope_id=? AND m.active=1 AND u.is_active=1 ORDER BY m.account_id', [$scope]);
        // Derived leaders receive project events only after explicit delivery preferences.
        $subscribers=$this->many('SELECT DISTINCT account_id FROM familyhub_inbox_preferences WHERE scope_id=? AND category=?',[$scope,$category]);
        $known=array_column($rows,'account_id');
        foreach ($subscribers as $subscriber) { if (!in_array($subscriber['account_id'],$known,true)) { $rows[]=$subscriber; } }
        usort($rows,fn($a,$b)=>strcmp($a['account_id'],$b['account_id']));
        $acl = new NativeFinanceAccess($this->container);
        foreach ($rows as $row) {
            $recipient = $row['account_id'];
            if ($recipient === $actorId || !$acl->visible($scope, $recipient, $finance)) { continue; }
            $personal = in_array($recipient, $assignees, true);
            $assigned = $personal && !in_array($recipient, $before['assigneeAccountIds'] ?? [], true);
            $kind = $type.'.'.($assigned ? 'assigned' : $base);
            $key = $eventKey ?? hash('sha256', $scope.':'.$type.':'.$record['id'].':'.$record['revision']);
            $this->insert($scope, $recipient, $actorId, $type, $record['id'], $record['revision'], $kind, $category,
                          $personal ? 'personal' : 'scope', $key, $payload['listId'] ?? ($payload['projectId'] ?? (in_array($type, ['task', 'event'], true) ? $scope : null)));
        }
    }
}
