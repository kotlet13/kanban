<?php
namespace Kanboard\Plugin\FamilyHub\Model;

/**
 * Capture3 comparison codec. Public proofs contain randomized commitments;
 * salts/selectors arrive only in the stripped transient captureSecrets sidecar.
 * This codec grants no access: the resolver must enforce the frozen selection.
 */
class NativeCryptoCaptureV3
{
    private const UUID = '/^[a-f0-9]{8}-[a-f0-9]{4}-[1-5][a-f0-9]{3}-[89ab][a-f0-9]{3}-[a-f0-9]{12}$/D';

    public static function context($value)
    {
        self::fields($value, ['version', 'serverId', 'captureId', 'migrationId',
            'accountId', 'scopeId', 'domain', 'sourceTable', 'sourceId']);
        if ($value['version'] !== 3) {
            throw new NativeError('crypto_capture_version');
        }
        foreach (['serverId', 'captureId', 'migrationId', 'accountId'] as $field) {
            self::uuid($value[$field]);
        }
        if ($value['scopeId'] !== null) {
            self::uuid($value['scopeId']);
        }
        if (!in_array($value['domain'], ['content', 'finance', 'private'], true)
            || ($value['scopeId'] === null && $value['domain'] !== 'private')
            || !is_string($value['sourceTable'])
            || !preg_match('/^familyhub_[a-z_]{1,69}$/D', $value['sourceTable'])
            || !is_string($value['sourceId']) || $value['sourceId'] === ''
            || strlen($value['sourceId']) > 256
            || preg_match('/[\x00-\x1f\x7f]/', $value['sourceId'])) {
            throw new NativeError('crypto_capture_context');
        }
        return $value;
    }

    public static function binding($value)
    {
        self::fields($value, ['bindingId', 'scopeId', 'domain', 'sourceCommitment']);
        self::uuid($value['bindingId']);
        if ($value['scopeId'] !== null) {
            self::uuid($value['scopeId']);
        }
        if (!in_array($value['domain'], ['content', 'finance', 'private'], true)
            || ($value['scopeId'] === null && $value['domain'] !== 'private')
            || !is_string($value['sourceCommitment'])
            || !preg_match('/^[a-f0-9]{64}$/D', $value['sourceCommitment'])) {
            throw new NativeError('crypto_capture_binding');
        }
        return $value;
    }

    public static function sourceCommitment($context, $salt, $typedRow)
    {
        self::context($context);
        if (!is_string($salt) || strlen($salt) !== 32 || !is_object($typedRow)) {
            throw new NativeError('crypto_capture_salt');
        }
        return hash('sha256', "JivieCaptureSource/v3\n"
            .NativeCryptoCodec::canonical((object)$context)."\n".$salt
            .NativeCryptoCodec::canonical($typedRow));
    }

    public static function inventoryRoot($header, $bindings)
    {
        self::fields($header, ['version', 'serverId', 'captureId', 'migrationId',
            'accountId', 'sourceCount']);
        foreach (['serverId', 'captureId', 'migrationId', 'accountId'] as $field) {
            self::uuid($header[$field]);
        }
        if ($header['version'] !== 3 || !is_int($header['sourceCount'])
            || $header['sourceCount'] < 0) {
            throw new NativeError('crypto_capture_inventory');
        }
        $hash = hash_init('sha256');
        hash_update($hash, "JivieCaptureInventory/v3\n"
            .NativeCryptoCodec::canonical((object)$header)."\n");
        $count = 0;
        $previous = null;
        foreach ($bindings as $binding) {
            self::binding($binding);
            if (($previous !== null && strcmp($previous, $binding['bindingId']) >= 0)
                || ++$count > $header['sourceCount']) {
                throw new NativeError('crypto_capture_inventory_order');
            }
            $previous = $binding['bindingId'];
            hash_update($hash, NativeCryptoCodec::canonical((object)$binding)."\n");
        }
        if ($count !== $header['sourceCount']) {
            throw new NativeError('crypto_capture_inventory_incomplete');
        }
        return hash_final($hash);
    }

    /**
     * Validate an exact bounded correspondence before resolving any source.
     * Salt values never appear in returned data or errors. The caller must not
     * retain the input sidecar in receipts, request hashes, journals or logs.
     */
    public static function verifyBindings($header, $bindings, $secrets, callable $resolve)
    {
        self::fields($header, ['version', 'serverId', 'captureId', 'migrationId', 'accountId']);
        if ($header['version'] !== 3 || !is_array($bindings) || !array_is_list($bindings)
            || count($bindings) < 1 || count($bindings) > 32
            || !is_array($secrets) || !array_is_list($secrets)
            || count($secrets) !== count($bindings)) {
            throw new NativeError('crypto_capture_sidecar');
        }
        $byId = [];
        foreach ($secrets as $secret) {
            self::fields($secret, ['bindingId', 'sourceTable', 'sourceId', 'saltBase64']);
            self::uuid($secret['bindingId']);
            if (isset($byId[$secret['bindingId']]) || !is_string($secret['saltBase64'])) {
                throw new NativeError('crypto_capture_sidecar');
            }
            $salt = base64_decode($secret['saltBase64'], true);
            if ($salt === false || strlen($salt) !== 32
                || base64_encode($salt) !== $secret['saltBase64']) {
                throw new NativeError('crypto_capture_sidecar');
            }
            sodium_memzero($salt);
            $byId[$secret['bindingId']] = $secret;
        }
        $previous = null;
        $verified = [];
        foreach ($bindings as $binding) {
            self::binding($binding);
            $id = $binding['bindingId'];
            if (($previous !== null && strcmp($previous, $id) >= 0) || !isset($byId[$id])) {
                throw new NativeError('crypto_capture_sidecar');
            }
            $previous = $id;
            $secret = $byId[$id];
            unset($byId[$id]);
            $context = self::context(array_merge($header, [
                'scopeId' => $binding['scopeId'], 'domain' => $binding['domain'],
                'sourceTable' => $secret['sourceTable'], 'sourceId' => $secret['sourceId'],
            ]));
            $source = $resolve($context);
            $salt = base64_decode($secret['saltBase64'], true);
            try {
                $commitment = self::sourceCommitment($context, $salt, $source);
                if (!hash_equals($binding['sourceCommitment'], $commitment)) {
                    throw new NativeError('crypto_capture_source_mismatch', 409);
                }
            } finally {
                sodium_memzero($salt);
                unset($secret);
            }
            $verified[] = ['binding' => $binding, 'context' => $context];
        }
        if ($byId) {
            throw new NativeError('crypto_capture_sidecar');
        }
        return $verified;
    }

    private static function uuid($value)
    {
        if (!is_string($value) || !preg_match(self::UUID, $value)) {
            throw new NativeError('crypto_capture_context');
        }
    }

    private static function fields($value, $fields)
    {
        if (!is_array($value) || count($value) !== count($fields)
            || array_diff(array_keys($value), $fields) || array_diff($fields, array_keys($value))) {
            throw new NativeError('crypto_capture_shape');
        }
    }
}
