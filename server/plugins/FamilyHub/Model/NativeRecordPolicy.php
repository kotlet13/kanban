<?php
namespace Kanboard\Plugin\FamilyHub\Model;

/** Versioned business payload validation, independent of sync transaction orchestration. */
class NativeRecordPolicy extends NativeDatabase
{
    public function validate($type, $payload, $scopeId, $current, $version)
    {
        if ($type==='garden') { if ($version!==4) { throw new NativeError('client_upgrade_required',409); }return (new NativeGardenPolicy($this->container))->validate($payload,$scopeId,$current); }
        $personal = ($this->one('SELECT kind FROM familyhub_scopes WHERE id=?', [$scopeId])['kind'] ?? '') === 'personal';
        if (!is_array($payload) || array_is_list($payload) || strlen(json_encode($payload, JSON_UNESCAPED_UNICODE | JSON_THROW_ON_ERROR)) > ($personal ? 524288 : 8192)) { throw new NativeError('validation_error'); }
        $specific = match ($type) {
            'project' => ['title', 'description', 'area'],
            'task' => ['title', 'notes', 'projectId', 'dueAt', 'isCompleted'],
            'event' => ['title', 'notes', 'projectId', 'startAt', 'endAt', 'assigneeAccountIds'],
            'householdPerson' => ['name', 'notes', 'archived'],
            'shoppingList' => ['title'],
            'shoppingItem' => ['listId', 'title', 'quantity', 'isChecked'],
            default => throw new NativeError('validation_error'),
        };
        if ($version >= 2 && in_array($type, ['project', 'task'], true)) {
            $specific = array_merge($specific, ['startAt', 'endAt'], $type === 'task' ? ['assigneeAccountIds'] : []);
        }
        if ($version >= 3 && $type === 'project') { $specific = array_merge($specific, ['phases','availabilityMinutes','availabilityPeriod']); }
        if ($version >= 3 && $type === 'task') { $specific = array_merge($specific, ['phaseId','estimateMinutes','availabilityMinutes','availabilityPeriod','timer','assigneePersonId','subjectPersonIds']); }
        if ($type === 'householdPerson' && $version < 3) { throw new NativeError('client_upgrade_required',409); }
        $this->fields($payload, array_merge($specific, ['createdAt', 'updatedAt']));
        $this->domainText($payload[$type === 'householdPerson' ? 'name' : 'title'], 300, 500, $personal); $this->date($payload['createdAt']); $this->date($payload['updatedAt']);
        if ($current && new \DateTimeImmutable(json_decode($current['payload'], true, 32, JSON_THROW_ON_ERROR)['createdAt']) != new \DateTimeImmutable($payload['createdAt'])) { throw new NativeError('created_at_immutable'); }
        if ($type === 'householdPerson') {
            $this->domainText($payload['notes'],4096,50000,$personal,true);
            if (!is_bool($payload['archived'])) { throw new NativeError('validation_error'); }
        }
        if ($version >= 3 && in_array($type,['project','task'],true)) { $this->planning($type,$payload,$scopeId,$current); }
        if ($type === 'project') {
            $this->domainText($payload['description'], 4096, 50000, $personal, true);
            if (!in_array($payload['area'], ['personal', 'home'], true)) { throw new NativeError('validation_error'); }
        }
        if (in_array($type,['task','event'],true)) {
            $s=$this->one('SELECT project_root_id,organization_id FROM familyhub_scopes WHERE id=?',[$scopeId]);
            $root=$s['project_root_id']??(!empty($s['organization_id']) ? $scopeId : null);
            if ($root!==null && $payload['projectId']!==$root) { throw new NativeError('parent_missing'); }
        }
        if (in_array($type, ['task', 'event'], true)) {
            $this->domainText($payload['notes'], 4096, 50000, $personal, true);
            if ($payload['projectId'] !== null) { $this->parentRecord($scopeId, $payload['projectId'], 'project'); }
        }
        if ($type === 'task') {
            if (!is_bool($payload['isCompleted'])) { throw new NativeError('validation_error'); }
            if ($payload['dueAt'] !== null) { $this->date($payload['dueAt']); }
        }
        if ($version >= 2 && in_array($type, ['project', 'task', 'event'], true)) {
            if ($payload['startAt'] !== null) { $this->date($payload['startAt']); }
            elseif ($type === 'event') { throw new NativeError('validation_error'); }
            if ($payload['endAt'] !== null) { $this->date($payload['endAt']); }
            if ($payload['startAt'] !== null && $payload['endAt'] !== null && new \DateTimeImmutable($payload['endAt']) < new \DateTimeImmutable($payload['startAt'])) { throw new NativeError('invalid_date_range'); }
        }
        if ($version >= 2 && in_array($type, ['task', 'event'], true)) { $this->assignees($scopeId, $payload['assigneeAccountIds']); }
        if ($type === 'shoppingItem') {
            $this->domainText($payload['quantity'], 100, 100, $personal, true);
            if (!is_bool($payload['isChecked'])) { throw new NativeError('validation_error'); }
            $this->parentRecord($scopeId, $payload['listId'], 'shoppingList');
        }
    }

    private function planning($type, array $payload, $scope, $current)
    {
        $minutes = $payload['availabilityMinutes']; $period = $payload['availabilityPeriod'];
        if (($minutes === null) !== ($period === null) || ($minutes !== null && (!is_int($minutes) || $minutes < 1 || $minutes > ($period==='day' ? 1440 : 10080) || !in_array($period,['day','week'],true)))) { throw new NativeError('validation_error'); }
        if ($type === 'project') {
            if (!is_array($payload['phases']) || !array_is_list($payload['phases']) || count($payload['phases']) > 200) { throw new NativeError('validation_error'); }
            $ids=[];
            foreach ($payload['phases'] as $phase) {
                if (!is_array($phase)) { throw new NativeError('validation_error'); }
                $this->fields($phase,['id','title','milestone','startAt','endAt']); $this->text($phase['id'],200); $this->text($phase['title'],300); $this->text($phase['milestone'],4096,true);
                if (isset($ids[$phase['id']])) { throw new NativeError('validation_error'); } $ids[$phase['id']]=true;
                foreach (['startAt','endAt'] as $key) { if ($phase[$key]!==null) { $this->date($phase[$key]); } }
                if ($phase['startAt']!==null && $phase['endAt']!==null && new \DateTimeImmutable($phase['endAt']) < new \DateTimeImmutable($phase['startAt'])) { throw new NativeError('invalid_date_range'); }
            }
            // Phase removal preserves references; explicitly detach tasks first.
            if ($current) {
                foreach ($this->many("SELECT payload FROM familyhub_records WHERE scope_id=? AND type='task' AND deleted=0",[$scope]) as $task) {
                    $p=json_decode($task['payload'],true,32,JSON_THROW_ON_ERROR);
                    if (($p['projectId']??null)===$current['id'] && ($p['phaseId']??null)!==null && !isset($ids[$p['phaseId']])) { throw new NativeError('live_children'); }
                }
            }
            return;
        }
        if ($payload['estimateMinutes']!==null && (!is_int($payload['estimateMinutes']) || $payload['estimateMinutes']<1 || $payload['estimateMinutes']>10000000)) { throw new NativeError('validation_error'); }
        if ($payload['phaseId']!==null) {
            $this->text($payload['phaseId'],200);
            if ($payload['projectId']===null) { throw new NativeError('parent_missing'); }
            $project=$this->one("SELECT payload FROM familyhub_records WHERE scope_id=? AND id=? AND type='project' AND deleted=0",[$scope,$payload['projectId']]);
            $phases=$project ? (json_decode($project['payload'],true,32,JSON_THROW_ON_ERROR)['phases']??[]) : [];
            if (!in_array($payload['phaseId'],array_column($phases,'id'),true)) { throw new NativeError('parent_missing'); }
        }
        $timer=$payload['timer'];
        if (!is_array($timer)) { throw new NativeError('validation_error'); }
        $this->fields($timer,['elapsedSeconds','runningSince','runId']);
        if (!is_int($timer['elapsedSeconds']) || $timer['elapsedSeconds']<0 || $timer['elapsedSeconds']>315360000 || (($timer['runningSince']===null)!==($timer['runId']===null))) { throw new NativeError('validation_error'); }
        if ($timer['runningSince']!==null) { $this->date($timer['runningSince']); $this->text($timer['runId'],200); }
        $before=$current ? json_decode($current['payload'],true,32,JSON_THROW_ON_ERROR) : [];
        $this->person($scope,$payload['assigneePersonId'],$before['assigneePersonId']??null);
        $ids=$payload['subjectPersonIds'];
        if (!is_array($ids) || !array_is_list($ids) || count($ids)>20 || count(array_unique($ids,SORT_REGULAR))!==count($ids)) { throw new NativeError('validation_error'); }
        foreach ($ids as $id) { $this->person($scope,$id,in_array($id,$before['subjectPersonIds']??[],true)?$id:null); }
    }

    /** Profiles are data references, never accounts or recipients. */
    public function person($scope, $id, $previous = null)
    {
        if ($id===null) { return; } $this->uuid($id);
        $person=$this->one("SELECT payload FROM familyhub_records WHERE scope_id=? AND id=? AND type='householdPerson' AND deleted=0",[$scope,$id]);
        if (!$person) { throw new NativeError('person_missing'); }
        if ($id!==$previous && (json_decode($person['payload'],true,32,JSON_THROW_ON_ERROR)['archived']??true)) { throw new NativeError('person_archived'); }
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
        if ($type==='householdPerson') {
            foreach ($this->many("SELECT payload FROM familyhub_records WHERE scope_id=? AND type='task' AND deleted=0",[$scope]) as $row) {
                $p=json_decode($row['payload'],true,32,JSON_THROW_ON_ERROR);
                if (($p['assigneePersonId']??null)===$id || in_array($id,$p['subjectPersonIds']??[],true)) { throw new NativeError('live_children'); }
            }
            foreach ($this->many("SELECT payload FROM familyhub_finance_records WHERE scope_id=? AND deleted=0",[$scope]) as $row) {
                $p=json_decode($row['payload'],true,32,JSON_THROW_ON_ERROR);
                foreach (['payerPersonId','recipientPersonId','createdByPersonId'] as $field) { if (($p[$field]??null)===$id) { throw new NativeError('live_children'); } }
            }
        }
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
        if ($version >= 2 && $payload !== null && in_array($row['type'], ['project', 'task'], true)) {
            $payload += ['startAt' => null, 'endAt' => null];
            if ($row['type'] === 'task') { $payload += ['assigneeAccountIds' => []]; }
        }
        if ($version >= 3 && $payload !== null && in_array($row['type'],['project','task'],true)) {
            $payload += ['availabilityMinutes'=>null,'availabilityPeriod'=>null];
            if ($row['type']==='project') { $payload += ['phases'=>[]]; }
            else { $payload += ['phaseId'=>null,'estimateMinutes'=>null,'timer'=>['elapsedSeconds'=>0,'runningSince'=>null,'runId'=>null],'assigneePersonId'=>null,'subjectPersonIds'=>[]]; }
        }
        $wire = ['id' => $row['id'], 'type' => $row['type'], 'revision' => (int)$row['revision'], 'deleted' => (int)$row['deleted'] === 1,
                 'payload' => $payload, 'sequence' => (int)$row['sequence'], 'updatedAt' => $row['updated_at']];
        if ($this->financialRecordType($row['type'])) { $wire['contractVersion']=(int)($row['contract_version']??1); }
        if ($version >= 2) { $wire += ['createdByAccountId' => $row['created_by'], 'updatedByAccountId' => $row['updated_by']]; }
        return $wire;
    }
}
