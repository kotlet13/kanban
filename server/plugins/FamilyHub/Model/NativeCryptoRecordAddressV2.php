<?php

namespace Kanboard\Plugin\FamilyHub\Model;

/** Public opaque identity binding; never derives keys or decrypts application data. */
class NativeCryptoRecordAddressV2
{
    public static function sourceKind($type)
    {
        return match ($type) {
            'project','task','event','shoppingList','shoppingItem','householdPerson','garden','idea' => 'records',
            'financeAccount','financeEntry','financeTransfer','personalFinanceEntry','personalFinanceAccount','financeRecurrenceRule' => 'finance_records',
            'table' => 'tables',
            'attachment' => 'attachments',
            'ideaAsset' => 'idea_assets',
            'paymentEvent' => 'payment_events',
            'paymentProjection' => 'payment_projections',
            'cashMovement' => 'payment_cash',
            'scopeMetadata' => 'scope_metadata',
            'taskDerivationIntent' => 'task_derivation_intents',
            'taskDerivationResolution' => 'task_derivation_resolutions',
            'financeAccountChoice' => 'finance_account_choices',
            default => throw new NativeError('crypto_record_identity_type', 409),
        };
    }

    public static function domain($type)
    {
        $kind=self::sourceKind($type);
        return in_array($kind,['finance_records','payment_events','payment_projections','payment_cash','finance_account_choices','task_derivation_resolutions'],true)?'finance':'content';
    }

    public static function canonicalId($id)
    {
        if (!is_string($id) || !preg_match('/^[a-f0-9]{8}-[a-f0-9]{4}-[1-5][a-f0-9]{3}-[89ab][a-f0-9]{3}-[a-f0-9]{12}$/D', $id)) {
            throw new NativeError('validation_error');
        }
        return $id;
    }

    /** Accept immutable earlier preview IDs for reads; every new mapped write is version8. */
    public static function wireId($id)
    {
        if (!is_string($id) || !preg_match('/^[a-f0-9]{8}-[a-f0-9]{4}-[1-58][a-f0-9]{3}-[89ab][a-f0-9]{3}-[a-f0-9]{12}$/D', $id)) {
            throw new NativeError('validation_error');
        }
        return $id;
    }

    public static function derive($serverId, $scopeId, $domain, $sourceKind, $canonicalId)
    {
        self::canonicalId($serverId);
        self::canonicalId($scopeId);
        self::canonicalId($canonicalId);
        if (!in_array($domain, ['content','finance'], true) || !is_string($sourceKind)) {
            throw new NativeError('validation_error');
        }
        $context = ['version'=>2,'serverId'=>$serverId,'scopeId'=>$scopeId,'domain'=>$domain,'sourceKind'=>$sourceKind,'canonicalId'=>$canonicalId];
        $bytes = substr(hash('sha256', "JivieRecordAddress/v2\n".NativeCryptoCodec::canonical((object)$context), true), 0, 16);
        $bytes[6] = chr((ord($bytes[6]) & 15) | 128);
        $bytes[8] = chr((ord($bytes[8]) & 63) | 128);
        $hex = bin2hex($bytes);
        return substr($hex,0,8).'-'.substr($hex,8,4).'-'.substr($hex,12,4).'-'.substr($hex,16,4).'-'.substr($hex,20);
    }

    public static function verify($record)
    {
        $identity = $record['metadata']['identity'] ?? null;
        if (!is_array($identity) || count($identity) !== 2 || !isset($identity['canonicalId'],$identity['sourceKind']) || $identity['sourceKind'] !== self::sourceKind($record['type']) || $record['domain'] !== self::domain($record['type'])) {
            throw new NativeError('crypto_record_identity_binding', 409);
        }
        $expected = self::derive($record['serverId'], $record['scopeId'], $record['domain'], $identity['sourceKind'], $identity['canonicalId']);
        if ($record['id'] !== $expected) {
            throw new NativeError('crypto_record_identity_binding', 409);
        }
    }
}
