<?php
namespace Kanboard\Plugin\FamilyHub\Model;

class NativeSyncService extends NativeDatabase
{
    private $version = 1;

    const MAX_PAYLOAD_BYTES = 8192;
    const MAX_PAGE_BYTES = 524288;

    public function execute($operation, array $params)
    {
        $linkedAware = $params['linkedPaymentsAware'] ?? false;
        if (!is_bool($linkedAware)) { throw new NativeError('validation_error'); }
        unset($params['linkedPaymentsAware']);
        $this->version = str_starts_with($operation, 'sync4.') ? 4 : (str_starts_with($operation, 'sync3.') ? 3 : (str_starts_with($operation, 'sync2.') ? 2 : 1));
        $this->rate([['sync-ip:'.$this->ip, 2400, 60]]);
        try { $result = $this->transaction(function () use ($operation, $params, $linkedAware) {
            $actor = $this->actor(); $userId = $actor['user']['id'];
            if (in_array($operation, ['sync.pull', 'sync2.pull', 'sync3.pull', 'sync4.pull'], true)) { return $this->pull($params, $userId); }
            if (!in_array($operation, ['sync.push', 'sync2.push', 'sync3.push', 'sync3.pushTaskWithCost', 'sync4.push', 'sync4.pushTaskWithCost'], true)) { throw new NativeError('unsupported_operation', 404); }
            $this->fields($params, ['scopeId', 'operation'], $this->version >= 3 ? ['operationContractVersion', 'financeOperation', 'financeOperationContractVersion'] : []);
            $payloadVersion = $this->version >= 3 ? ($params['operationContractVersion'] ?? $this->version) : $this->version;
            if (!is_int($payloadVersion) || !in_array($payloadVersion, [1,2,3,4], true) || $payloadVersion>$this->version) { throw new NativeError('validation_error'); }
            $compound = in_array($operation,['sync3.pushTaskWithCost','sync4.pushTaskWithCost'],true);
            if ($compound !== isset($params['financeOperation'])) { throw new NativeError('validation_error'); }
            $scopeId = $this->uuid($params['scopeId']);
            $scope = $this->scope($scopeId, $userId, true);
            $op = $params['operation'];
            if (!is_array($op)) { throw new NativeError('validation_error'); }
            $this->fields($op, ['opId', 'recordId', 'type', 'expectedRevision', 'deleted', 'payload']);
            $opId = $this->uuid($op['opId']); $recordId = $this->uuid($op['recordId']);
            if (!in_array($op['type'], ($payloadVersion >= 3 ? array_merge(['project', 'task', 'event', 'shoppingList', 'shoppingItem', 'householdPerson'],$payloadVersion===4 ? ['garden'] : []) : ($payloadVersion === 2 ? ['project', 'task', 'event', 'shoppingList', 'shoppingItem'] : ['project', 'task', 'shoppingList', 'shoppingItem'])), true) ||
                    !is_int($op['expectedRevision']) || $op['expectedRevision'] < 0 || !is_bool($op['deleted'])) {
                throw new NativeError('validation_error');
            }
            if ($op['type']==='garden' && !$op['deleted'] && ($op['payload']['id']??null)!==$recordId) { throw new NativeError('validation_error'); }
            if ($compound) {
                $financeAcl = (new NativeFinanceAccess($this->container))->policy($scopeId, $actor['user'], true, true);
                if ($financeAcl['linkedPaymentsRequired'] && !$linkedAware) { throw new NativeError('client_upgrade_required',409); }
            }
            if ($scope['kind']==='organization' && $op['type']==='project') { throw new NativeError('organization_projects_use_scopes',403); }
            $projectRoot=$scope['project_root_id']??(!empty($scope['organization_id']) ? $scopeId : null);
            if ($projectRoot!==null && $op['type']==='project') {
                if ($recordId!==$projectRoot || $op['deleted']) { throw new NativeError('project_scope_single_project',403); }
                if (!$op['deleted']) { $this->text($op['payload']['title']??null,200); }
            }
            $hashOperation = $compound ? 'sync3.pushTaskWithCost' : ($payloadVersion === 1 ? 'sync.push' : 'sync'.$payloadVersion.'.push');
            $hashParams = $compound ? $params : ['scopeId'=>$params['scopeId'], 'operation'=>$op];
            $hash = $this->hashRequest($hashOperation, $hashParams);
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
                if ($compound) { throw new NativeError('conflict',409,$details); }
                return new NativeError('conflict', 409, $details);
            }
            if ($current && (int)$current['contract_version'] > $payloadVersion) { throw new NativeError('client_upgrade_required',409,['serverRecord'=>$this->wire($current)]); }
            try {
                if ($op['deleted']) {
                    if ($op['payload'] !== null) { throw new NativeError('validation_error'); }
                    (new NativeRecordPolicy($this->container))->noChildren($scopeId, $recordId, $op['type']);
                } else {
                    (new NativeRecordPolicy($this->container))->validate($op['type'], $op['payload'], $scopeId, $current, $payloadVersion);
                }
            } catch (NativeError $error) {
                if (!in_array($error->errorCode, ['parent_missing', 'live_children', 'assignee_not_member'], true)) { throw $error; }
                $details = ['serverRecord' => $current ? $this->wire($current) : null];
                $this->remember($scopeId, $userId, $opId, $hash, ['errorCode' => $error->errorCode, 'details' => $details], 422);
                if ($compound) { throw new NativeError($error->errorCode,422,$details); }
                return new NativeError($error->errorCode, 422, $details);
            }
            $sequence = $this->advance($scope);
            if ($payloadVersion===4) { $this->change('UPDATE familyhub_scopes SET required_record_contract=4 WHERE id=?',[$scopeId]); } $revision = $op['expectedRevision'] + 1;
            $updated = gmdate('Y-m-d\TH:i:s\Z');
            $payload = $op['deleted'] ? null : json_encode($op['payload'], JSON_UNESCAPED_UNICODE | JSON_THROW_ON_ERROR);
            if ($current) {
                $this->change('UPDATE familyhub_records SET revision=?,deleted=?,payload=?,sequence=?,updated_at=?,contract_version=?,updated_by=? WHERE scope_id=? AND id=?', [$revision, (int)$op['deleted'], $payload, $sequence, $updated, $payloadVersion, $actor['user']['account_id'], $scopeId, $recordId]);
            } else {
                $this->change('INSERT INTO familyhub_records(scope_id,id,type,revision,deleted,payload,sequence,updated_at,contract_version,created_by,updated_by) VALUES(?,?,?,?,?,?,?,?,?,?,?)', [$scopeId, $recordId, $op['type'], $revision, 0, $payload, $sequence, $updated, $payloadVersion, $actor['user']['account_id'], $actor['user']['account_id']]);
            }
            if ($projectRoot!==null && $op['type']==='project' && !$op['deleted']) {
                $this->change('UPDATE familyhub_scopes SET name=? WHERE id=?',[$op['payload']['title'],$scopeId]);
            }
            $record = $this->wire($this->one('SELECT * FROM familyhub_records WHERE scope_id=? AND id=?', [$scopeId, $recordId]));
            (new NativeNotificationWriter($this->container))->recordChanged($scopeId, $record, $current, $actor['user']['account_id']);
            (new NativeReminderService($this->container))->reconcile($scopeId, $record, $current);
            if (!$compound && $op['type']==='task') { (new NativeFinanceService($this->container))->reconcileTaskInTransaction($scopeId,$actor['user'],$current,$record); }
            $financeResponse = null;
            if ($compound) {
                if ($op['type'] !== 'task' || ($params['financeOperationContractVersion'] ?? 2) !== 2) { throw new NativeError('validation_error'); }
                $financeOp = $params['financeOperation'];
                if (!is_array($financeOp) || !in_array($financeOp['type'] ?? '', ['personalFinanceEntry','financeEntry'], true) || (!$financeOp['deleted'] && !in_array($financeOp['payload']['taskId']??null,[$recordId,null],true))) { throw new NativeError('validation_error'); }
                if (!$financeOp['deleted'] && ($financeOp['payload']['taskId']??null)===null && !$op['deleted']) {
                    $existingCost=$this->one('SELECT payload FROM familyhub_finance_records WHERE scope_id=? AND id=? AND deleted=0',[$scopeId,$financeOp['recordId']??null]);
                    if (!$existingCost || (json_decode($existingCost['payload'],true,32,JSON_THROW_ON_ERROR)['taskId']??null)!==$recordId) { throw new NativeError('validation_error'); }
                }
                try {
                    $financeResponse = (new NativeFinanceService($this->container))->pushInTransaction($scopeId, $actor['user'], $financeOp, 'sync3.pushTaskWithCost', $params);
                } catch (NativeError $error) {
                    throw new NativeError($error->errorCode,$error->status,['serverRecord'=>$current ? $this->wire($current) : null,'financeRecord'=>$error->details['serverRecord']??null]);
                }
                if ($financeResponse instanceof NativeError) { throw $financeResponse; }
            }
            $response = ['status' => 'applied', 'record' => $record, 'cursor' => $sequence, 'replayed' => false];
            if ($compound) { $response['finance'] = $financeResponse; }
            if ($projectRoot!==null && $op['type']==='project' && !$op['deleted']) { $response['scope']=$this->scopeWire($this->scope($scopeId,$userId)); }
            $this->remember($scopeId, $userId, $opId, $hash, $response);
            return $response;
        });
        } catch (NativeError $error) {
            if (in_array($operation,['sync3.pushTaskWithCost','sync4.pushTaskWithCost'],true) && in_array($error->errorCode,['conflict','parent_missing','live_children','person_missing','person_archived','validation_error','created_at_immutable','duplicate_finance_reference','task_cost_date_mismatch','currency_mismatch'],true) && isset($params['operation']['opId'],$params['scopeId'])) {
                // The compound transaction rolled back BOTH records, audit and
                // notifications. Persist its immutable failed outcome separately
                // after checking current rights again; never cache denied data.
                $this->transaction(function() use($params,$operation,$error) {
                    $actor=$this->actor();$scope=$this->uuid($params['scopeId']);$id=$this->uuid($params['operation']['opId']);
                    $this->scope($scope,$actor['user']['id'],true);
                    (new NativeFinanceAccess($this->container))->policy($scope,$actor['user'],true,true);
                    $hash=$this->hashRequest('sync3.pushTaskWithCost',$params);$replay=$this->replay($scope,$actor['user']['id'],$id,$hash);
                    if(!$replay) $this->remember($scope,$actor['user']['id'],$id,$hash,['errorCode'=>$error->errorCode,'details'=>$error->details],$error->status);
                });
            }
            throw $error;
        }
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
        $scope = $this->one('SELECT required_record_contract FROM familyhub_scopes WHERE id=?', [$scopeId]);
        if ($this->version < (int)($scope['required_record_contract'] ?? 1) || $this->one('SELECT id FROM familyhub_records WHERE scope_id=? AND contract_version>? LIMIT 1', [$scopeId, $this->version])) {
            throw new NativeError('client_upgrade_required', 409);
        }
    }

    private function wire(array $row)
    {
        return (new NativeRecordPolicy($this->container))->wire($row, $this->version);
    }
}
