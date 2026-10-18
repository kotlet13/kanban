<?php

namespace Kanboard\Plugin\FamilyHub\Model;

/** Own notification migration commitments, separate from shared domain records. */
final class NativeCryptoMigrationNotificationV3
{
    public const HEADER_FIELDS = [
        'version', 'serverId', 'migrationId', 'captureId', 'accountId',
        'sourceInventoryRoot', 'archiveManifestHash', 'coldParityProofHash',
        'authorDirectoryHeadHash', 'transformCount', 'sourceCounts', 'transformRoot',
    ];
    public const KINDS = ['reminder', 'inbox', 'preference', 'inboxState'];

    private static function fields($value, $fields)
    {
        if (!is_array($value)) {
            throw new NativeError('crypto_notification_migration_shape');
        }
        $keys = array_keys($value);
        sort($keys, SORT_STRING);
        sort($fields, SORT_STRING);
        if ($keys !== $fields) {
            throw new NativeError('crypto_notification_migration_shape');
        }
    }

    private static function uuid($value)
    {
        if (!is_string($value) || !preg_match('/^[a-f0-9]{8}-[a-f0-9]{4}-[1-5][a-f0-9]{3}-[89ab][a-f0-9]{3}-[a-f0-9]{12}$/D', $value)) {
            throw new NativeError('crypto_notification_migration_context');
        }
    }

    private static function digest($value)
    {
        if (!is_string($value) || !preg_match('/^[a-f0-9]{64}$/D', $value)) {
            throw new NativeError('crypto_notification_migration_context');
        }
    }

    private static function count($value)
    {
        if (!is_int($value) || $value < 0 || $value > 9007199254740991) {
            throw new NativeError('crypto_notification_migration_count');
        }
    }

    public static function header($value)
    {
        self::fields($value, self::HEADER_FIELDS);
        if ($value['version'] !== 3) {
            throw new NativeError('crypto_notification_migration_version');
        }
        foreach (['serverId', 'migrationId', 'captureId', 'accountId'] as $field) {
            self::uuid($value[$field]);
        }
        foreach (['sourceInventoryRoot', 'archiveManifestHash', 'coldParityProofHash', 'authorDirectoryHeadHash', 'transformRoot'] as $field) {
            self::digest($value[$field]);
        }
        self::fields($value['sourceCounts'], self::KINDS);
        $sum = 0;
        foreach (self::KINDS as $kind) {
            self::count($value['sourceCounts'][$kind]);
            $sum += $value['sourceCounts'][$kind];
            self::count($sum);
        }
        self::count($value['transformCount']);
        if ($sum !== $value['transformCount']) {
            throw new NativeError('crypto_notification_migration_count');
        }
        return $value;
    }

    public static function scopeToken($header)
    {
        self::header($header);
        $context = ['version' => 3];
        foreach (['serverId', 'accountId', 'migrationId', 'captureId', 'sourceInventoryRoot'] as $field) {
            $context[$field] = $header[$field];
        }
        return hash('sha256', "JivieNotificationMigrationToken/v3\n".NativeCryptoCodec::canonical((object)$context));
    }

    public static function leafDigest($leaf)
    {
        self::fields($leaf, ['bindingId', 'kind', 'transformHash', 'useProofHash']);
        self::uuid($leaf['bindingId']);
        if (!in_array($leaf['kind'], self::KINDS, true)) {
            throw new NativeError('crypto_notification_migration_kind');
        }
        self::digest($leaf['transformHash']);
        if ($leaf['useProofHash'] !== null) {
            self::digest($leaf['useProofHash']);
            if ($leaf['kind'] !== 'reminder') {
                throw new NativeError('crypto_notification_migration_kind');
            }
        }
        return hash('sha256', "JivieNotificationTransformLeaf/v3\n".NativeCryptoCodec::canonical((object)$leaf));
    }

    /** Pre-certificate selection commitment. It has no cold-proof dependency. */
    public static function selectionRoot($context, $count, iterable $digests)
    {
        self::fields($context, ['version','serverId','migrationId','captureId','accountId','sourceInventoryRoot']);
        if ($context['version'] !== 3) {
            throw new NativeError('crypto_notification_migration_version');
        }
        foreach (['serverId','migrationId','captureId','accountId'] as $field) {
            self::uuid($context[$field]);
        }
        self::digest($context['sourceInventoryRoot']);
        self::count($count);
        $sink = hash_init('sha256');
        hash_update($sink,"JivieNotificationSelection/v3\n".NativeCryptoCodec::canonical((object)$context)."\n");
        $previous = null;
        $total = 0;
        foreach ($digests as $hash) {
            self::digest($hash);
            if ($previous !== null && strcmp($previous,$hash) >= 0 || ++$total > $count) {
                throw new NativeError('crypto_notification_migration_order');
            }
            hash_update($sink,$hash."\n");
            $previous = $hash;
        }
        if ($total !== $count) {
            throw new NativeError('crypto_notification_migration_incomplete');
        }
        return hash_final($sink);
    }

    /** Hash only after exact author/context signature verification. Never hash
     * a standalone low-entropy settings or legacy payload object publicly.
     */
    public static function transformHash($proof, $header, $bindingId, $kind, callable $resolveSigner)
    {
        // Staging precedes the finalized cold comparison/certificate. Its
        // common context has no certificate root or event hash (no cycle).
        if (count($header) === count(self::HEADER_FIELDS)) {
            self::header($header);
        } else {
            self::fields($header, ['version','serverId','accountId','migrationId','captureId','sourceInventoryRoot']);
            if ($header['version'] !== 3) {
                throw new NativeError('crypto_notification_migration_version');
            }
            foreach (['serverId','accountId','migrationId','captureId'] as $field) {
                self::uuid($header[$field]);
            }
            self::digest($header['sourceInventoryRoot']);
        }
        self::uuid($bindingId);
        [$body, $bytes, $signature] = NativeCryptoCodec::decode($proof);
        self::fields($body, ['version', 'operation', 'serverId', 'accountId', 'migrationId',
            'captureId', 'sourceInventoryRoot', 'bindingId', 'kind', 'canonical', 'deviceId',
            'authorDirectoryHeadHash', 'useAuthorization']);
        if (strlen($bytes) > 131072 || $body['version'] !== 3 ||
            $body['operation'] !== 'crypto2.migration.notificationTransform' ||
            $body['bindingId'] !== $bindingId || $body['kind'] !== $kind ||
            !in_array($kind, self::KINDS, true) || !is_array($body['canonical'])) {
            throw new NativeError('crypto_notification_migration_transform');
        }
        foreach (['serverId', 'accountId', 'migrationId', 'captureId', 'sourceInventoryRoot'] as $field) {
            if ($body[$field] !== $header[$field]) {
                throw new NativeError('crypto_notification_migration_transform');
            }
        }
        self::digest($body['authorDirectoryHeadHash']);
        self::uuid($body['deviceId']);
        if ($body['useAuthorization'] !== null && $kind !== 'reminder') {
            throw new NativeError('crypto_notification_migration_transform');
        }
        // The caller resolves this exact own directory/device reference from a
        // verified prefix and applies fresh-versus-finalized-history authority.
        // An arbitrary caller-supplied public key is never a trust decision here.
        $authorPublicKey = $resolveSigner($body['accountId'], $body['authorDirectoryHeadHash'], $body['deviceId']);
        NativeCryptoV2Codec::verify($bytes, $signature, $authorPublicKey, "JivieE2EE/notificationTransform/v3\n");
        return hash('sha256', "JivieNotificationTransform/v3\n".NativeCryptoCodec::canonical((object)$proof));
    }

    /** Bounded pages may feed this stream; order/count are authenticated, not cursors. */
    public static function transformRoot($header, iterable $digests)
    {
        self::header($header);
        $context = $header;
        unset($context['transformRoot']);
        $sink = hash_init('sha256');
        hash_update($sink, "JivieNotificationTransforms/v3\n".NativeCryptoCodec::canonical((object)$context)."\n");
        $previous = null;
        $count = 0;
        foreach ($digests as $digest) {
            self::digest($digest);
            if ($previous !== null && strcmp($previous, $digest) >= 0) {
                throw new NativeError('crypto_notification_migration_order');
            }
            if (++$count > $header['transformCount']) {
                throw new NativeError('crypto_notification_migration_count');
            }
            hash_update($sink, $digest."\n");
            $previous = $digest;
        }
        if ($count !== $header['transformCount']) {
            throw new NativeError('crypto_notification_migration_incomplete');
        }
        return hash_final($sink);
    }
}
