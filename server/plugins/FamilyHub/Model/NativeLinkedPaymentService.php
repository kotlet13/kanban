<?php
namespace Kanboard\Plugin\FamilyHub\Model;

/** Canonical organization expenses plus managed, minimal cash/receivable projections. */
class NativeLinkedPaymentService extends NativeDatabase
{
    public function execute($operation, array $params)
    {
        $this->rate([['linked-payment-ip:'.$this->ip, 1200, 60]]);
        return $this->transaction(function () use ($operation, $params) {
            $user = $this->actor()['user'];
            $scope = $this->uuid($params['scopeId'] ?? null);
            if ($operation === 'finance3.payments') {
                $this->fields($params, ['scopeId']);
                $policy = (new NativeFinanceAccess($this->container))->policy($scope, $user, false, true);
                $result = ['events'=>[], 'projections'=>[], 'cashMovements'=>[], 'accessRevision'=>$policy['revision'], 'scopeSequence'=>$policy['sequence']];
                $bytes = 256;
                foreach (['events'=>'familyhub_payment_events','projections'=>'familyhub_payment_projections','cashMovements'=>'familyhub_payment_cash'] as $key=>$table) {
                    foreach ($this->iterate('SELECT data FROM '.$table.' WHERE scope_id=?', [$scope]) as $row) {
                        $bytes += strlen($row['data']) + 1;
                        if ($bytes > 524288) {
                            throw new NativeError('linked_payments_too_large',413);
                        }
                        $result[$key][] = json_decode($row['data'],true,32,JSON_THROW_ON_ERROR);
                    }
                }
                return $result;
            }
            // This order also serializes source writes and membership revocation.
            $source = $this->scope($scope, $user['id']);
            if ($source['kind'] !== 'organization' && ($source['kind'] !== 'project' || !$source['organization_id'])) {
                throw new NativeError('organization_project_required');
            }
            $write = $operation !== 'finance3.paymentProject';
            (new NativeFinanceAccess($this->container))->policy($scope, $user, $write, true);
            $request = $this->uuid($params['requestId'] ?? null);
            $hash = $this->hashRequest($operation, $params);
            $replay = $this->replay($scope, $user['id'], $request, $hash);
            if ($replay) {
                // Revalidate target ACL before returning a stored private receipt.
                $this->targets($params, $user);
                return $replay['body'];
            }
            if ($operation === 'finance3.paymentCommit') {
                $result = $this->commit($params, $scope, $user);
            } elseif ($operation === 'finance3.paymentReimburse') {
                $result = $this->reimburse($params, $scope, $user);
            } elseif ($operation === 'finance3.paymentProject') {
                $result = $this->project($params, $scope, $user);
            } else {
                throw new NativeError('unsupported_operation', 404);
            }
            $this->remember($scope, $user['id'], $request, $hash, $result);
            return $result;
        }, true);
    }

    private function commit($p, $scope, $user)
    {
        $this->fields($p, ['scopeId','entryId','expectedEntryRevision','eventId','paidAt','expectReimbursement','requestId'], ['personalTarget','householdScopeId']);
        $entry = $this->uuid($p['entryId']);
        $id = $this->uuid($p['eventId']);
        if (!is_int($p['expectedEntryRevision']) || $p['expectedEntryRevision'] < 1 || !is_bool($p['expectReimbursement'])) {
            throw new NativeError('validation_error');
        }
        (new NativeRecordPolicy($this->container))->date($p['paidAt']);
        $row = $this->one('SELECT * FROM familyhub_finance_records WHERE scope_id=? AND id=?', [$scope, $entry]);
        if (!$row || $row['type'] !== 'financeEntry' || (int)$row['deleted'] || (int)$row['revision'] !== $p['expectedEntryRevision']) {
            throw new NativeError('payment_source_changed', 409);
        }
        $payload = json_decode($row['payload'], true, 32, JSON_THROW_ON_ERROR);
        if ((int)$row['contract_version'] < 2 || $payload['kind'] !== 'expense' || $payload['status'] !== 'posted' ||
            ($payload['payerAccountId'] !== null && $payload['payerAccountId'] !== $user['account_id']) ||
            (($payload['paidAt'] ?? null) !== null && new \DateTimeImmutable($payload['paidAt']) != new \DateTimeImmutable($p['paidAt']))) {
            throw new NativeError('payment_source_changed', 409);
        }
        if ($this->one('SELECT event_id FROM familyhub_payment_events WHERE event_id=? OR (scope_id=? AND entry_id=?)', [$id,$scope,$entry]) ||
            $this->one('SELECT movement_id FROM familyhub_payment_cash WHERE movement_id=? LIMIT 1', [$id])) {
            throw new NativeError('payment_already_linked', 409);
        }
        $targets = $this->targets($p, $user, $payload['currency']);
        $payload['paidAt'] = $p['paidAt'];
        $payload['occurredAt'] = $p['paidAt'];
        $payload['payerAccountId'] = $user['account_id'];
        $now = gmdate('Y-m-d\\TH:i:s\\Z');
        $payload['updatedAt'] = new \DateTimeImmutable($payload['updatedAt']) > new \DateTimeImmutable($now) ? $payload['updatedAt'] : $now;
        $policy = $this->one('SELECT sequence FROM familyhub_finance_policy WHERE scope_id=?', [$scope]);
        $sequence = (int)$policy['sequence'] + 1;
        $revision = (int)$row['revision'] + 1;
        $this->change('UPDATE familyhub_finance_policy SET sequence=? WHERE scope_id=?', [$sequence,$scope]);
        $this->change('UPDATE familyhub_finance_records SET revision=?,sequence=?,payload=?,updated_at=?,updated_by=? WHERE scope_id=? AND id=?', [$revision,$sequence,json_encode($payload,JSON_THROW_ON_ERROR),$now,$user['account_id'],$scope,$entry]);
        $updatedRow = $this->one('SELECT * FROM familyhub_finance_records WHERE scope_id=? AND id=?', [$scope,$entry]);
        $recordPolicy = new NativeRecordPolicy($this->container);
        $record = $recordPolicy->wire($updatedRow);
        $this->change('INSERT INTO familyhub_finance_audit VALUES(?,?,?,?,?,?,?,?)', [$scope,$entry,$revision,$user['account_id'],$now,json_encode($recordPolicy->wire($row),JSON_THROW_ON_ERROR),json_encode($record,JSON_THROW_ON_ERROR),$p['requestId']]);
        (new NativeNotificationWriter($this->container))->recordChanged($scope,$record,$row,$user['account_id'],true);
        $event = [
            'eventId'=>$id, 'sourceScopeId'=>$scope, 'sourceEntryId'=>$entry,
            'sourceRevision'=>$revision, 'payerAccountId'=>$user['account_id'],
            'amountMinor'=>$payload['amountMinor'], 'currency'=>$payload['currency'],
            'paidAt'=>$p['paidAt'], 'expectReimbursement'=>$p['expectReimbursement'],
            'revision'=>1, 'reimbursements'=>[],
        ];
        $this->change('INSERT INTO familyhub_payment_events VALUES(?,?,?,?,?,?)', [$scope,$id,$entry,$user['account_id'],1,json_encode($event,JSON_THROW_ON_ERROR)]);
        $this->writeProjections($event, $targets, $user['account_id']);
        return ['event'=>$event];
    }

    private function reimburse($p, $scope, $user)
    {
        $this->fields($p, ['scopeId','eventId','expectedRevision','legId','amountMinor','paidAt','organizationAccountId','requestId'], ['organizationAccountScopeId']);
        $event = $this->event($scope, $p['eventId'], $p['expectedRevision']);
        if (!$event['expectReimbursement']) {
            throw new NativeError('reimbursement_not_expected', 409);
        }
        $leg = $this->uuid($p['legId']);
        if ($this->one('SELECT movement_id FROM familyhub_payment_cash WHERE movement_id=? LIMIT 1', [$leg]) ||
            $this->one('SELECT event_id FROM familyhub_payment_events WHERE event_id=? LIMIT 1', [$leg])) {
            throw new NativeError('idempotency_mismatch',409);
        }
        if (!is_int($p['amountMinor']) || $p['amountMinor'] <= 0 || $p['amountMinor'] > 9000000000000) {
            throw new NativeError('validation_error');
        }
        (new NativeRecordPolicy($this->container))->date($p['paidAt']);
        if (new \DateTimeImmutable($p['paidAt']) < new \DateTimeImmutable($event['paidAt'])) {
            throw new NativeError('invalid_date_range');
        }
        $account = $this->uuid($p['organizationAccountId']);
        $accountScope = $this->uuid($p['organizationAccountScopeId'] ?? $scope);
        if ($accountScope !== $scope) {
            $source = $this->one('SELECT organization_id FROM familyhub_scopes WHERE id=?', [$scope]);
            if ($source['organization_id'] !== $accountScope) {
                throw new NativeError('finance_forbidden',403);
            }
            (new NativeFinanceAccess($this->container))->policy($accountScope,$user,true,true);
        }
        $this->account($accountScope, $account, 'financeAccount', $event['currency']);
        $total = array_sum(array_column($event['reimbursements'], 'amountMinor')) + $p['amountMinor'];
        if (count($event['reimbursements']) >= 500 || $total > $event['amountMinor'] || in_array($leg, array_column($event['reimbursements'], 'legId'), true)) {
            throw new NativeError('reimbursement_exceeds_payment', 409);
        }
        $event['reimbursements'][] = [
            'legId'=>$leg, 'amountMinor'=>$p['amountMinor'], 'paidAt'=>$p['paidAt'],
            'organizationAccountId'=>$account, 'organizationAccountScopeId'=>$accountScope,
            'approvedByAccountId'=>$user['account_id'],
        ];
        $event['revision']++;
        $this->change('UPDATE familyhub_payment_events SET revision=?,data=? WHERE scope_id=? AND event_id=?', [$event['revision'],json_encode($event,JSON_THROW_ON_ERROR),$scope,$event['eventId']]);
        $this->cash($accountScope, ['id'=>$leg,'accountId'=>$account,'amountMinor'=>-$p['amountMinor'],'currency'=>$event['currency'],'paidAt'=>$p['paidAt']]);
        $this->signal($scope);
        if ($accountScope !== $scope) {
            $this->signal($accountScope);
        }
        // Existing private targets are managed internally; the writer sees no target IDs.
        foreach ($this->many('SELECT * FROM familyhub_payment_projections WHERE source_scope_id=? AND event_id=? ORDER BY scope_id', [$scope,$event['eventId']]) as $projection) {
            $previous = json_decode($projection['data'], true, 32, JSON_THROW_ON_ERROR);
            $this->writeProjection($event, $projection['scope_id'], $projection['owner_account_id'], $previous['privateAccountId'] ?? null);
        }
        // A refund changes the sidecar rather than the expense revision. Route
        // through its canonical source and deduplicate by the immutable leg ID.
        $sourceRecord = $this->one('SELECT * FROM familyhub_finance_records WHERE scope_id=? AND id=?', [$scope,$event['sourceEntryId']]);
        $record = (new NativeRecordPolicy($this->container))->wire($sourceRecord);
        $eventKey = hash('sha256', $scope.':paymentRefund:'.$event['eventId'].':'.$leg);
        (new NativeNotificationWriter($this->container))->recordChanged($scope, $record, $sourceRecord, $user['account_id'], true, $eventKey);
        return ['event'=>$event];
    }

    private function project($p, $scope, $user)
    {
        $this->fields($p, ['scopeId','eventId','expectedRevision','requestId'], ['personalTarget','householdScopeId']);
        $event = $this->event($scope, $p['eventId'], $p['expectedRevision']);
        if ($event['payerAccountId'] !== $user['account_id']) {
            throw new NativeError('finance_forbidden', 403);
        }
        $targets = $this->targets($p, $user, $event['currency']);
        if (!$targets) {
            throw new NativeError('validation_error');
        }
        $this->writeProjections($event, $targets, $user['account_id']);
        return ['event'=>$event];
    }

    private function event($scope, $id, $revision)
    {
        $id = $this->uuid($id);
        $row = $this->one('SELECT * FROM familyhub_payment_events WHERE scope_id=? AND event_id=?', [$scope,$id]);
        if (!$row || !is_int($revision) || (int)$row['revision'] !== $revision) {
            throw new NativeError('payment_changed', 409);
        }
        return json_decode($row['data'], true, 32, JSON_THROW_ON_ERROR);
    }

    private function targets($p, $user, $currency = null)
    {
        $targets = [];
        if (isset($p['personalTarget'])) {
            $personal = $p['personalTarget'];
            if (!is_array($personal)) {
                throw new NativeError('validation_error');
            }
            $this->fields($personal, ['scopeId','accountId']);
            $id = $this->uuid($personal['scopeId']);
            $account = $this->uuid($personal['accountId']);
            $scope = $this->scope($id, $user['id'], true);
            if ($scope['kind'] !== 'personal') {
                throw new NativeError('finance_forbidden', 403);
            }
            (new NativeFinanceAccess($this->container))->policy($id,$user,true,true);
            if ($currency !== null) {
                $this->account($id,$account,'personalFinanceAccount',$currency);
            }
            $targets[] = ['scopeId'=>$id,'privateAccountId'=>$account];
        }
        if (isset($p['householdScopeId'])) {
            $id = $this->uuid($p['householdScopeId']);
            $scope = $this->scope($id, $user['id'], true);
            if ($scope['kind'] !== 'household') {
                throw new NativeError('finance_forbidden', 403);
            }
            (new NativeFinanceAccess($this->container))->policy($id,$user,true,true);
            $targets[] = ['scopeId'=>$id,'privateAccountId'=>null];
        }
        return $targets;
    }

    private function account($scope, $id, $type, $currency)
    {
        $row = $this->one('SELECT payload FROM familyhub_finance_records WHERE scope_id=? AND id=? AND type=? AND deleted=0', [$scope,$id,$type]);
        if (!$row || json_decode($row['payload'],true,32,JSON_THROW_ON_ERROR)['currency'] !== $currency) {
            throw new NativeError('currency_mismatch');
        }
        if (json_decode($row['payload'],true,32,JSON_THROW_ON_ERROR)['archived'] ?? false) {
            throw new NativeError('parent_missing');
        }
    }

    private function writeProjections($event, $targets, $owner)
    {
        foreach ($targets as $target) {
            $this->writeProjection($event,$target['scopeId'],$owner,$target['privateAccountId']);
        }
    }

    private function writeProjection($event, $scope, $owner, $account)
    {
        $previous = $this->one('SELECT data,source_scope_id FROM familyhub_payment_projections WHERE scope_id=? AND event_id=?', [$scope,$event['eventId']]);
        if ($previous) {
            $old = json_decode($previous['data'],true,32,JSON_THROW_ON_ERROR);
            if ($previous['source_scope_id'] !== $event['sourceScopeId'] || ($old['privateAccountId']??null) !== $account) {
                throw new NativeError('payment_projection_locked',409);
            }
        }
        $data = $event;
        $data['paymentRevision'] = $event['revision'];
        $data['state'] = 'complete';
        foreach ($data['reimbursements'] as &$leg) {
            unset($leg['organizationAccountId']);
            unset($leg['organizationAccountScopeId']);
        }
        unset($leg);
        if ($account !== null) {
            $data['privateAccountId'] = $account;
        }
        $this->change('DELETE FROM familyhub_payment_projections WHERE scope_id=? AND event_id=?', [$scope,$event['eventId']]);
        $this->change('INSERT INTO familyhub_payment_projections VALUES(?,?,?,?,?)', [$scope,$event['eventId'],$event['sourceScopeId'],$owner,json_encode($data,JSON_THROW_ON_ERROR)]);
        if ($account !== null) {
            $this->cash($scope, ['id'=>$event['eventId'],'accountId'=>$account,'amountMinor'=>-$event['amountMinor'],'currency'=>$event['currency'],'paidAt'=>$event['paidAt']]);
            foreach ($event['reimbursements'] as $leg) {
                $this->cash($scope, ['id'=>$leg['legId'],'accountId'=>$account,'amountMinor'=>$leg['amountMinor'],'currency'=>$event['currency'],'paidAt'=>$leg['paidAt']]);
            }
        }
        $this->signal($scope);
    }

    private function cash($scope, $movement)
    {
        $this->change('DELETE FROM familyhub_payment_cash WHERE scope_id=? AND movement_id=?', [$scope,$movement['id']]);
        $this->change('INSERT INTO familyhub_payment_cash VALUES(?,?,?)', [$scope,$movement['id'],json_encode($movement,JSON_THROW_ON_ERROR)]);
    }

    private function signal($scope)
    {
        $this->change('UPDATE familyhub_finance_policy SET sequence=sequence+1 WHERE scope_id=?', [$scope]);
    }

    /** Called only by authorized canonical finance writes in the same transaction. */
    public function sourceRevisionChangedInTransaction($scope, $entry, $revision)
    {
        $row = $this->one('SELECT * FROM familyhub_payment_events WHERE scope_id=? AND entry_id=?', [$scope,$entry]);
        if (!$row) { return; }
        $event = json_decode($row['data'],true,32,JSON_THROW_ON_ERROR);
        $event['sourceRevision'] = $revision;
        $event['revision']++;
        $this->change('UPDATE familyhub_payment_events SET revision=?,data=? WHERE scope_id=? AND event_id=?', [$event['revision'],json_encode($event,JSON_THROW_ON_ERROR),$scope,$event['eventId']]);
        foreach ($this->many('SELECT * FROM familyhub_payment_projections WHERE source_scope_id=? AND event_id=?', [$scope,$event['eventId']]) as $projection) {
            $previous = json_decode($projection['data'],true,32,JSON_THROW_ON_ERROR);
            $this->writeProjection($event,$projection['scope_id'],$projection['owner_account_id'],$previous['privateAccountId']??null);
        }
    }
}
