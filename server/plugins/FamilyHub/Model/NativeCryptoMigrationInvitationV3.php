<?php

namespace Kanboard\Plugin\FamilyHub\Model;

/** Own notification migration commitments, separate from shared domain records. */
final class NativeCryptoMigrationInvitationV3
{
    public const HEADER_FIELDS = [
        'version', 'serverId', 'migrationId', 'captureId', 'accountId',
        'sourceInventoryRoot', 'archiveManifestHash', 'coldParityProofHash',
        'authorDirectoryHeadHash', 'bridgeCount', 'sourceCounts', 'bridgeRoot',
    ];
    public const KINDS = ['invitation', 'mail'];

    private static function fields($value, $fields)
    {
        if (!is_array($value)) {
            throw new NativeError('crypto_invitation_migration_shape');
        }
        $keys = array_keys($value);
        sort($keys, SORT_STRING);
        sort($fields, SORT_STRING);
        if ($keys !== $fields) {
            throw new NativeError('crypto_invitation_migration_shape');
        }
    }

    private static function uuid($value)
    {
        if (!is_string($value) || !preg_match('/^[a-f0-9]{8}-[a-f0-9]{4}-[1-5][a-f0-9]{3}-[89ab][a-f0-9]{3}-[a-f0-9]{12}$/D', $value)) {
            throw new NativeError('crypto_invitation_migration_context');
        }
    }

    private static function digest($value)
    {
        if (!is_string($value) || !preg_match('/^[a-f0-9]{64}$/D', $value)) {
            throw new NativeError('crypto_invitation_migration_context');
        }
    }

    private static function count($value)
    {
        if (!is_int($value) || $value < 0 || $value > 9007199254740991) {
            throw new NativeError('crypto_invitation_migration_count');
        }
    }

    public static function header($value)
    {
        self::fields($value, self::HEADER_FIELDS);
        if ($value['version'] !== 3) {
            throw new NativeError('crypto_invitation_migration_version');
        }
        foreach (['serverId', 'migrationId', 'captureId', 'accountId'] as $field) {
            self::uuid($value[$field]);
        }
        foreach (['sourceInventoryRoot', 'archiveManifestHash', 'coldParityProofHash', 'authorDirectoryHeadHash', 'bridgeRoot'] as $field) {
            self::digest($value[$field]);
        }
        self::fields($value['sourceCounts'], self::KINDS);
        $sum = 0;
        foreach (self::KINDS as $kind) {
            self::count($value['sourceCounts'][$kind]);
            $sum += $value['sourceCounts'][$kind];
            self::count($sum);
        }
        self::count($value['bridgeCount']);
        if ($sum !== $value['bridgeCount']) {
            throw new NativeError('crypto_invitation_migration_count');
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
        return hash('sha256', "JivieInvitationMigrationToken/v3\n".NativeCryptoCodec::canonical((object)$context));
    }

    public static function leafDigest($leaf)
    {
        self::fields($leaf, ['bindingId', 'kind', 'bridgeHash', 'capsuleHash']);
        self::uuid($leaf['bindingId']);
        if (!in_array($leaf['kind'], self::KINDS, true)) {
            throw new NativeError('crypto_invitation_migration_kind');
        }
        self::digest($leaf['bridgeHash']);
        if ($leaf['capsuleHash'] !== null) {
            self::digest($leaf['capsuleHash']);
            if ($leaf['kind'] !== 'invitation') {
                throw new NativeError('crypto_invitation_migration_kind');
            }
        }
        return hash('sha256', "JivieInvitationBridgeLeaf/v3\n".NativeCryptoCodec::canonical((object)$leaf));
    }

    /** Pre-certificate selection commitment. It has no cold-proof dependency. */
    public static function selectionRoot($context, $count, iterable $digests)
    {
        self::fields($context, ['version','serverId','migrationId','captureId','accountId','sourceInventoryRoot']);
        if ($context['version'] !== 3) {
            throw new NativeError('crypto_invitation_migration_version');
        }
        foreach (['serverId','migrationId','captureId','accountId'] as $field) {
            self::uuid($context[$field]);
        }
        self::digest($context['sourceInventoryRoot']);
        self::count($count);
        $sink = hash_init('sha256');
        hash_update($sink,"JivieInvitationSelection/v3\n".NativeCryptoCodec::canonical((object)$context)."\n");
        $previous = null;
        $total = 0;
        foreach ($digests as $hash) {
            self::digest($hash);
            if ($previous !== null && strcmp($previous,$hash) >= 0 || ++$total > $count) {
                throw new NativeError('crypto_invitation_migration_order');
            }
            hash_update($sink,$hash."\n");
            $previous = $hash;
        }
        if ($total !== $count) {
            throw new NativeError('crypto_invitation_migration_incomplete');
        }
        return hash_final($sink);
    }

    /** Bounded pages may feed this stream; order/count are authenticated, not cursors. */
    public static function bridgeRoot($header, iterable $digests)
    {
        self::header($header);
        $context = $header;
        unset($context['bridgeRoot']);
        $sink = hash_init('sha256');
        hash_update($sink, "JivieInvitationBridges/v3\n".NativeCryptoCodec::canonical((object)$context)."\n");
        $previous = null;
        $count = 0;
        foreach ($digests as $digest) {
            self::digest($digest);
            if ($previous !== null && strcmp($previous, $digest) >= 0) {
                throw new NativeError('crypto_invitation_migration_order');
            }
            if (++$count > $header['bridgeCount']) {
                throw new NativeError('crypto_invitation_migration_count');
            }
            hash_update($sink, $digest."\n");
            $previous = $digest;
        }
        if ($count !== $header['bridgeCount']) {
            throw new NativeError('crypto_invitation_migration_incomplete');
        }
        return hash_final($sink);
    }
}
