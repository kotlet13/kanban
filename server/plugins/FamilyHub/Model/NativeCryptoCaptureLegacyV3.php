<?php
namespace Kanboard\Plugin\FamilyHub\Model;

/** Opaque receipt inventory. Original request/response bytes stay encrypted. */
final class NativeCryptoCaptureLegacyV3
{
    public static function tuple($value)
    {
        self::fields($value, ['scopeId', 'receiptKind', 'legacyId', 'legacyDeviceId']);
        self::uuid($value['scopeId']);
        self::uuid($value['legacyId']);
        if (!in_array($value['receiptKind'], ['records', 'finance', 'documents'], true)) {
            throw new NativeError('crypto_legacy_receipt_identity');
        }
        if ($value['receiptKind'] === 'documents') {
            self::uuid($value['legacyDeviceId']);
        } elseif ($value['legacyDeviceId'] !== null) {
            throw new NativeError('crypto_legacy_receipt_identity');
        }
        return $value;
    }

    public static function descriptor($value)
    {
        self::fields($value, ['scopeId', 'receiptKind', 'legacyId', 'legacyDeviceId', 'bindingId', 'sourceCommitment']);
        self::tuple(array_intersect_key($value, array_flip(['scopeId', 'receiptKind', 'legacyId', 'legacyDeviceId'])));
        self::uuid($value['bindingId']);
        self::digest($value['sourceCommitment']);
        return $value;
    }

    public static function header($value)
    {
        self::fields($value, ['captureVersion', 'serverId', 'accountId', 'captureId', 'migrationId',
            'domain', 'sourceInventoryRoot', 'archiveManifestHash', 'receiptCount', 'receiptSelectionHash']);
        foreach (['serverId', 'accountId', 'captureId', 'migrationId'] as $field) {
            self::uuid($value[$field]);
        }
        foreach (['sourceInventoryRoot', 'archiveManifestHash', 'receiptSelectionHash'] as $field) {
            self::digest($value[$field]);
        }
        if ($value['captureVersion'] !== 3 || !in_array($value['domain'], ['content', 'finance'], true)
            || !is_int($value['receiptCount']) || $value['receiptCount'] < 0) {
            throw new NativeError('crypto_legacy_inventory_context');
        }
        return $value;
    }

    public static function orderKey($descriptor)
    {
        self::descriptor($descriptor);
        return $descriptor['scopeId']."\0".$descriptor['receiptKind']."\0"
            .$descriptor['legacyId']."\0".($descriptor['legacyDeviceId'] ?? '');
    }

    /** Binding uniqueness is enforced by the immutable capture source mapping. */
    public static function root($header, iterable $descriptors)
    {
        self::header($header);
        $hash = hash_init('sha256');
        hash_update($hash, "JivieCaptureLegacyInventory/v3\n".NativeCryptoCodec::canonical((object)$header)."\n");
        $count = 0;
        $previous = null;
        foreach ($descriptors as $descriptor) {
            $key = self::orderKey($descriptor);
            $domain = $descriptor['receiptKind'] === 'finance' ? 'finance' : 'content';
            if ($domain !== $header['domain'] || ($previous !== null && strcmp($previous, $key) >= 0)
                || ++$count > $header['receiptCount']) {
                throw new NativeError('crypto_legacy_inventory_order');
            }
            hash_update($hash, NativeCryptoCodec::canonical((object)$descriptor)."\n");
            $previous = $key;
        }
        if ($count !== $header['receiptCount']) {
            throw new NativeError('crypto_legacy_inventory_incomplete');
        }
        return hash_final($hash);
    }

    public static function scopeToken($header)
    {
        self::header($header);
        $context = array_intersect_key($header, array_flip(['captureVersion', 'serverId', 'accountId', 'captureId', 'migrationId', 'domain']));
        return hash('sha256', "JivieCaptureLegacyScope/v3\n".NativeCryptoCodec::canonical((object)$context));
    }

    public static function selectionHash($context)
    {
        self::fields($context, ['captureVersion', 'serverId', 'accountId', 'captureId', 'migrationId', 'receiptSelections']);
        foreach (['serverId','accountId','captureId','migrationId'] as $key) {
            self::uuid($context[$key]);
        }
        if ($context['captureVersion'] !== 3 || !is_array($context['receiptSelections'])
            || !array_is_list($context['receiptSelections']) || count($context['receiptSelections']) > 2000) {
            throw new NativeError('crypto_capture_receipt_selection');
        }
        $previous = null;
        foreach ($context['receiptSelections'] as $selection) {
            self::fields($selection, ['scopeId', 'domain']);
            self::uuid($selection['scopeId']);
            $order = $selection['scopeId'].'/'.$selection['domain'];
            if (!in_array($selection['domain'], ['content','finance'], true)
                || ($previous !== null && strcmp($previous, $order) >= 0)) {
                throw new NativeError('crypto_capture_receipt_selection');
            }
            $previous = $order;
        }
        return hash('sha256', "JivieCaptureReceiptSelection/v3\n".NativeCryptoCodec::canonical((object)$context));
    }

    private static function fields($value, $keys)
    {
        if (!is_array($value) || count($value) !== count($keys) || array_diff(array_keys($value), $keys)) {
            throw new NativeError('crypto_legacy_inventory_shape');
        }
    }

    private static function uuid($value)
    {
        if (!is_string($value) || !preg_match('/^[a-f0-9]{8}-[a-f0-9]{4}-[1-5][a-f0-9]{3}-[89ab][a-f0-9]{3}-[a-f0-9]{12}$/D', $value)) {
            throw new NativeError('crypto_legacy_receipt_identity');
        }
    }

    private static function digest($value)
    {
        if (!is_string($value) || !preg_match('/^[a-f0-9]{64}$/D', $value)) {
            throw new NativeError('crypto_legacy_receipt_binding');
        }
    }
}
