<?php
namespace Kanboard\Plugin\FamilyHub\Model;

/** Finance v2 keeps planned/posted money and person references outside sync3. */
class NativeFinancePlanningPolicy extends NativeDatabase
{
    public function validate($type, $p, $scope, $current)
    {
        if (!is_array($p) || array_is_list($p) || strlen(json_encode($p, JSON_UNESCAPED_UNICODE | JSON_THROW_ON_ERROR)) > 524288) { throw new NativeError('validation_error'); }
        $extra = ['status','plannedAt','paidAt','taskId','ledgerAccountId','payerPersonId','recipientPersonId','createdByPersonId','recurrenceRuleId','occurrenceKey'];
        $specific = match ($type) {
            'personalFinanceAccount' => ['name','openingBalanceMinor','openingBalanceAt','archived'],
            'financeRecurrenceRule' => ['title','kind','ledgerAccountId','estimatedAmountMinor','loanPrincipalMinor','startYear','startMonth','monthDay','endYear','endMonth','active','remindersEnabled','reminderMinuteOfDay'],
            'personalFinanceEntry' => array_merge(['title','amountMinor','kind','occurredAt','projectId','notes'], $extra),
            'financeAccount' => ['name','openingBalanceMinor','ownerAccountId','openingBalanceAt','archived'],
            'financeEntry' => array_merge(['accountId','kind','amountMinor','title','notes','category','payerAccountId','recipientAccountId','occurredAt'], $extra),
            'financeTransfer' => ['fromAccountId','toAccountId','amountMinor','status','title','notes','occurredAt'],
            default => throw new NativeError('validation_error'),
        };
        $this->fields($p, array_merge($specific,['currency','createdAt','updatedAt']));
        $dates = new NativeRecordPolicy($this->container);
        $dates->date($p['createdAt']); $dates->date($p['updatedAt']);
        if (new \DateTimeImmutable($p['updatedAt']) < new \DateTimeImmutable($p['createdAt'])) { throw new NativeError('validation_error'); }
        $previous = $current && $current['payload'] !== null ? json_decode($current['payload'],true,32,JSON_THROW_ON_ERROR) : null;
        if ($previous && new \DateTimeImmutable($previous['createdAt']) != new \DateTimeImmutable($p['createdAt'])) { throw new NativeError('created_at_immutable'); }
        if (!in_array($p['currency'],['EUR','USD','GBP','CHF'],true)) { throw new NativeError('unsupported_currency'); }
        if (in_array($type,['personalFinanceAccount','financeAccount'],true)) {
            $dates->domainText($p['name'],300,500,true);
            if (!is_bool($p['archived']) || ($p['openingBalanceMinor'] === null && $p['openingBalanceAt'] !== null)) { throw new NativeError('validation_error'); }
            if ($p['openingBalanceMinor'] !== null) { $this->money($p['openingBalanceMinor'],false); }
            if($p['openingBalanceAt']!==null) {$dates->date($p['openingBalanceAt']);}
            if ($previous && $previous['currency'] !== $p['currency']) { throw new NativeError('opening_balance_immutable'); }
            if ($type === 'financeAccount' && $p['ownerAccountId'] !== null) {
                $this->uuid($p['ownerAccountId']);
                if ($p['ownerAccountId'] !== ($previous['ownerAccountId'] ?? null)) { $dates->assignees($scope,[$p['ownerAccountId']]); }
            }
            return;
        }
        $dates->domainText($p['title'],300,500,true);
        if ($type === 'financeRecurrenceRule') {
            if($previous && ($previous['currency']!==$p['currency'] || $previous['kind']!==$p['kind'])) {throw new NativeError('rule_currency_immutable');}
            if (!in_array($p['kind'],['salary','income','loanInstallment','cardSettlement','expense'],true) || !is_bool($p['active']) || !is_bool($p['remindersEnabled'])) { throw new NativeError('validation_error'); }
            $this->money($p['estimatedAmountMinor'],true);
            if ($p['loanPrincipalMinor'] !== null) { $this->money($p['loanPrincipalMinor'],true); if ($p['kind'] !== 'loanInstallment') { throw new NativeError('validation_error'); } }
            foreach (['startYear'=>[1900,2200],'startMonth'=>[1,12],'monthDay'=>[1,31],'reminderMinuteOfDay'=>[0,1439]] as $key => [$min,$max]) { $this->integer($p[$key],$min,$max); }
            if (($p['endYear'] === null) !== ($p['endMonth'] === null)) { throw new NativeError('validation_error'); }
            if ($p['endYear'] !== null) {
                $this->integer($p['endYear'],1900,2200); $this->integer($p['endMonth'],1,12);
                if ($p['endYear']*12+$p['endMonth'] < $p['startYear']*12+$p['startMonth']) { throw new NativeError('validation_error'); }
            }
            $this->account($scope,$p['ledgerAccountId'],$p['currency'],$previous['ledgerAccountId'] ?? null);
            return;
        }
        $this->money($p['amountMinor'],true); $dates->date($p['occurredAt']); $dates->domainText($p['notes'],4096,50000,true,true);
        if (!in_array($p['status'],['planned','posted'],true)) { throw new NativeError('validation_error'); }
        if ($type === 'financeTransfer') {
            if ($p['fromAccountId'] === $p['toAccountId']) { throw new NativeError('same_transfer_account'); }
            $this->account($scope,$p['fromAccountId'],$p['currency'],$previous['fromAccountId'] ?? null); $this->account($scope,$p['toAccountId'],$p['currency'],$previous['toAccountId'] ?? null); return;
        }
        if (!in_array($p['kind'],['income','expense'],true)) { throw new NativeError('validation_error'); }
        foreach (['plannedAt','paidAt'] as $field) { if ($p[$field] !== null) { $dates->date($p[$field]); } }
        if ($p['status'] === 'planned' && $p['paidAt'] !== null) { throw new NativeError('validation_error'); }
        if ($p['paidAt'] !== null && new \DateTimeImmutable($p['paidAt']) != new \DateTimeImmutable($p['occurredAt'])) { throw new NativeError('validation_error'); }
        $this->account($scope,$p['ledgerAccountId'],$p['currency'],$previous['ledgerAccountId'] ?? null);
        if($p['createdByPersonId']!==null) {throw new NativeError('validation_error');}
        foreach (['payerPersonId','recipientPersonId','createdByPersonId'] as $field) { $this->person($scope,$p[$field],$previous[$field] ?? null); }
        if ($type === 'financeEntry') {
            if($p['ledgerAccountId']!==null && $p['ledgerAccountId']!==$p['accountId']) {throw new NativeError('validation_error');}
            $this->account($scope,$p['accountId'],$p['currency'],$previous['accountId'] ?? null); $this->text($p['category'],100,true);
            foreach (['payerAccountId','recipientAccountId'] as $field) {
                if ($p[$field] !== null && $p[$field] !== ($previous[$field] ?? null)) { $dates->assignees($scope,[$this->uuid($p[$field])]); }
            }
        } elseif ($p['projectId'] !== null && $p['projectId'] !== ($previous['projectId'] ?? null)) {
            $this->parent($scope,$p['projectId'],'project');
        }
        if ($p['taskId'] !== null) {
            if ($p['kind'] !== 'expense') { throw new NativeError('validation_error'); }
            $task = $this->parent($scope,$p['taskId'],'task');
            $due = json_decode($task['payload'],true,32,JSON_THROW_ON_ERROR)['dueAt'];
            if (($due === null) !== ($p['plannedAt'] === null) || ($due !== null && new \DateTimeImmutable($due) != new \DateTimeImmutable($p['plannedAt']))) { throw new NativeError('task_cost_date_mismatch'); }
            $this->uniqueReference($scope,$current['id'] ?? null,'taskId',$p['taskId']);
        }
        if (($p['recurrenceRuleId'] === null) !== ($p['occurrenceKey'] === null)) { throw new NativeError('validation_error'); }
        if ($p['recurrenceRuleId'] !== null) {
            $this->uuid($p['recurrenceRuleId']);
            if (!is_string($p['occurrenceKey']) || !preg_match('/^\d{4}-(0[1-9]|1[0-2])$/D',$p['occurrenceKey'])) { throw new NativeError('validation_error'); }
            $rule = $this->one("SELECT payload FROM familyhub_finance_records WHERE scope_id=? AND id=? AND type='financeRecurrenceRule' AND deleted=0",[$scope,$p['recurrenceRuleId']]);
            if (!$rule) {throw new NativeError('parent_missing');}
            $rulePayload=json_decode($rule['payload'],true,32,JSON_THROW_ON_ERROR);
            if($rulePayload['currency']!==$p['currency'] || (in_array($rulePayload['kind'],['salary','income'],true)?'income':'expense')!==$p['kind']) {throw new NativeError('validation_error');}
            $this->uniqueReference($scope,$current['id'] ?? null,'recurrenceRuleId',$p['recurrenceRuleId'],$p['occurrenceKey']);
        }
    }
    public function validateLegacyReferences($type,$payload,$scope,$current)
    {
        $previous=$current && $current['payload']!==null ? json_decode($current['payload'],true,32,JSON_THROW_ON_ERROR):[];
        foreach (match($type) {'financeEntry'=>['accountId'],'financeTransfer'=>['fromAccountId','toAccountId'],default=>[]} as $field) {
            $this->account($scope,$payload[$field],$payload['currency'],$previous[$field] ?? null);
        }
    }
    private function uniqueReference($scope,$id,$field,$reference,$occurrence=null)
    {
        $sql = "SELECT * FROM familyhub_finance_records WHERE scope_id=? AND id<>? AND deleted=0 AND type IN ('financeEntry','personalFinanceEntry') AND json_extract(payload,'$.".$field."')=?";
        $params = [$scope,$id ?? '',$reference];
        if ($occurrence !== null) { $sql .= " AND json_extract(payload,'$.occurrenceKey')=?"; $params[]=$occurrence; }
        $existing=$this->one($sql.' LIMIT 1',$params);
        if ($existing) { $wire=(new NativeRecordPolicy($this->container))->wire($existing); $wire['contractVersion']=(int)($existing['contract_version'] ?? 1); throw new NativeError('duplicate_finance_reference',409,['existingRecord'=>$wire]); }
    }
    private function parent($scope,$id,$type)
    {
        $this->uuid($id); $row=$this->one('SELECT payload FROM familyhub_records WHERE scope_id=? AND id=? AND type=? AND deleted=0',[$scope,$id,$type]);
        if (!$row) { throw new NativeError('parent_missing'); } return $row;
    }
    private function person($scope,$id,$previous)
    {
        if ($id===null) { return; } $this->uuid($id);
        if ($id===$previous) { return; }
        $row=$this->parent($scope,$id,'householdPerson');
        if (json_decode($row['payload'],true,32,JSON_THROW_ON_ERROR)['archived'] ?? false) { throw new NativeError('person_not_member'); }
    }
    private function account($scope,$id,$currency,$previous=null)
    {
        if ($id===null) { return; } $this->uuid($id);
        $row=$this->one("SELECT payload FROM familyhub_finance_records WHERE scope_id=? AND id=? AND type IN ('financeAccount','personalFinanceAccount') AND deleted=0",[$scope,$id]);
        if (!$row) { throw new NativeError('parent_missing'); }
        $account=json_decode($row['payload'],true,32,JSON_THROW_ON_ERROR);
        if(($account['archived'] ?? false) && $id!==$previous) {throw new NativeError('parent_missing');}
        if ($account['currency']!==$currency) { throw new NativeError('currency_mismatch'); }
    }
    private function money($v,$positive) { if (!is_int($v) || abs($v)>9000000000000 || ($positive && $v<=0)) { throw new NativeError('validation_error'); } }
    private function integer($v,$min,$max) { if (!is_int($v) || $v<$min || $v>$max) { throw new NativeError('validation_error'); } }
    public function noChildren($scope,$id,$type)
    {
        if(in_array($type,['financeEntry','personalFinanceEntry'],true)) {
            $entry=$this->one('SELECT payload FROM familyhub_finance_records WHERE scope_id=? AND id=?',[$scope,$id]);
            $payload=$entry && $entry['payload']!==null?json_decode($entry['payload'],true,32,JSON_THROW_ON_ERROR):[];
            if(($payload['recurrenceRuleId'] ?? null)!==null) {
                $rule=$this->one("SELECT payload FROM familyhub_finance_records WHERE scope_id=? AND id=? AND type='financeRecurrenceRule' AND deleted=0",[$scope,$payload['recurrenceRuleId']]);
                $allowed=false;
                if(($payload['status'] ?? 'posted')==='planned' && $rule) {
                    $r=json_decode($rule['payload'],true,32,JSON_THROW_ON_ERROR); $parts=explode('-',$payload['occurrenceKey']);
                    $month=(int)$parts[0]*12+(int)$parts[1];
                    $allowed=!$r['active'] || $month<$r['startYear']*12+$r['startMonth'] ||
                        ($r['endYear']!==null && $month>$r['endYear']*12+$r['endMonth']);
                }
                if(!$allowed)throw new NativeError('recurring_entry_managed_by_rule');
            }
        }
        $fields=match($type) { 'financeAccount','personalFinanceAccount'=>['accountId','fromAccountId','toAccountId','ledgerAccountId'], 'financeRecurrenceRule'=>['recurrenceRuleId'], default=>[] };
        foreach ($fields as $field) { if ($this->one("SELECT id FROM familyhub_finance_records WHERE scope_id=? AND deleted=0 AND json_extract(payload,'$.".$field."')=? LIMIT 1",[$scope,$id])) { throw new NativeError('live_children'); } }
    }
}
