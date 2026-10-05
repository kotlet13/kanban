<?php
namespace Kanboard\Plugin\FamilyHub\Model;

/** Payload invariants and preserved historic participants, independent of UI. */
class NativeFinancePolicy extends NativeDatabase
{
    public function validate($type, $p, $scope, $current)
    {
        if (!is_array($p) || array_is_list($p) || strlen(json_encode($p, JSON_UNESCAPED_UNICODE | JSON_THROW_ON_ERROR)) > ($type === 'personalFinanceEntry' ? 524288 : 8192)) { throw new NativeError('validation_error'); }
        $fields = match ($type) {
            'personalFinanceEntry' => ['title', 'amountMinor', 'currency', 'kind', 'occurredAt', 'projectId', 'notes'],
            'financeAccount' => ['name', 'currency', 'openingBalanceMinor', 'ownerAccountId'],
            'financeEntry' => ['accountId', 'kind', 'status', 'amountMinor', 'currency', 'title', 'notes', 'category', 'payerAccountId', 'recipientAccountId', 'occurredAt'],
            'financeTransfer' => ['fromAccountId', 'toAccountId', 'amountMinor', 'currency', 'status', 'title', 'notes', 'occurredAt'],
            default => throw new NativeError('validation_error'),
        };
        $this->fields($p, array_merge($fields, ['createdAt', 'updatedAt']));
        $dates = new NativeRecordPolicy($this->container); $dates->date($p['createdAt']); $dates->date($p['updatedAt']);
        $previous = $current ? json_decode($current['payload'], true, 32, JSON_THROW_ON_ERROR) : null;
        if ($previous && new \DateTimeImmutable($previous['createdAt']) != new \DateTimeImmutable($p['createdAt'])) { throw new NativeError('created_at_immutable'); }
        if (!in_array($p['currency'], ['EUR', 'USD', 'GBP', 'CHF'], true)) { throw new NativeError('unsupported_currency'); }
        if ($type === 'personalFinanceEntry') {
            $this->money($p['amountMinor'], true); $dates->domainText($p['title'], 300, 500, true); $dates->domainText($p['notes'], 4096, 50000, true, true); $dates->date($p['occurredAt']);
            if (!in_array($p['kind'], ['income', 'expense'], true)) { throw new NativeError('validation_error'); }
            if ($p['projectId'] !== null) {
                $this->uuid($p['projectId']);
                if ($p['projectId'] !== ($previous['projectId'] ?? null) && !$this->one('SELECT id FROM familyhub_records WHERE scope_id=? AND id=? AND type=\'project\' AND deleted=0', [$scope, $p['projectId']])) { throw new NativeError('parent_missing'); }
            }
            return;
        }
        if ($type === 'financeAccount') {
            $this->text($p['name'], 300); $this->money($p['openingBalanceMinor']);
            if ($previous && ($previous['currency'] !== $p['currency'] || $previous['openingBalanceMinor'] !== $p['openingBalanceMinor'])) { throw new NativeError('opening_balance_immutable'); }
            $this->participant($scope, $p['ownerAccountId'], $previous['ownerAccountId'] ?? null);
            return;
        }
        $this->money($p['amountMinor'], true); $this->text($p['title'], 300); $this->text($p['notes'], 4096, true); $dates->date($p['occurredAt']);
        if (!in_array($p['status'], ['planned', 'posted'], true)) { throw new NativeError('validation_error'); }
        if ($type === 'financeEntry') {
            if (!in_array($p['kind'], ['income', 'expense'], true)) { throw new NativeError('validation_error'); }
            $this->text($p['category'], 100, true); $this->account($scope, $p['accountId'], $p['currency']);
            foreach (['payerAccountId', 'recipientAccountId'] as $field) { $this->participant($scope, $p[$field], $previous[$field] ?? null); }
        } else {
            if ($p['fromAccountId'] === $p['toAccountId']) { throw new NativeError('same_transfer_account'); }
            $this->account($scope, $p['fromAccountId'], $p['currency']); $this->account($scope, $p['toAccountId'], $p['currency']);
        }
    }

    private function money($value, $positive = false)
    {
        if (!is_int($value) || abs($value) > 9000000000000 || ($positive && $value <= 0)) { throw new NativeError('validation_error'); }
    }

    private function participant($scope, $id, $previous)
    {
        if ($id === null) { return; }
        $this->uuid($id);
        // Keep explicit historic attribution when a former member is unchanged.
        if ($id === $previous) { return; }
        (new NativeRecordPolicy($this->container))->assignees($scope, [$id]);
    }

    private function account($scope, $id, $currency)
    {
        $this->uuid($id); $row = $this->one('SELECT payload FROM familyhub_finance_records WHERE scope_id=? AND id=? AND type=\'financeAccount\' AND deleted=0', [$scope, $id]);
        if (!$row) { throw new NativeError('parent_missing'); }
        if (json_decode($row['payload'], true, 32, JSON_THROW_ON_ERROR)['currency'] !== $currency) { throw new NativeError('currency_mismatch'); }
    }

    public function noChildren($scope, $id, $type)
    {
        if ($type !== 'financeAccount') { return; }
        foreach ($this->iterate('SELECT payload FROM familyhub_finance_records WHERE scope_id=? AND type IN (\'financeEntry\',\'financeTransfer\') AND deleted=0', [$scope]) as $row) {
            $p = json_decode($row['payload'], true, 32, JSON_THROW_ON_ERROR);
            if (($p['accountId'] ?? null) === $id || ($p['fromAccountId'] ?? null) === $id || ($p['toAccountId'] ?? null) === $id) { throw new NativeError('live_children'); }
        }
    }
}
