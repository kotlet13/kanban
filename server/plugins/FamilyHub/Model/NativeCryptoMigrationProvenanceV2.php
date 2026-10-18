<?php
namespace Kanboard\Plugin\FamilyHub\Model;

/** One streaming, context-bound commitment. Authority is checked by its caller. */
final class NativeCryptoMigrationProvenanceV2
{
    public static function scopeToken($serverId, $migrationId, $scopeId, $domain)
    {
        foreach ([$serverId, $migrationId, $scopeId] as $id) {
            self::uuid($id);
        }
        self::domain($domain);
        return hash('sha256', "JivieMigrationScope/v2\n".NativeCryptoCodec::canonical((object)[
            'version' => 2, 'serverId' => $serverId, 'migrationId' => $migrationId,
            'scopeId' => $scopeId, 'domain' => $domain,
        ]));
    }

    public static function header($header)
    {
        self::fields($header, ['version', 'serverId', 'migrationId', 'componentHash', 'scopeToken',
            'scopeId', 'domain', 'inventoryHash', 'membershipHeadHash', 'managerAccountId',
            'managerDirectoryHeadHash', 'sourceRowCount', 'materializedRecordProofCount']);
        foreach (['serverId', 'migrationId', 'scopeId', 'managerAccountId'] as $key) {
            self::uuid($header[$key]);
        }
        foreach (['componentHash', 'scopeToken', 'inventoryHash', 'membershipHeadHash', 'managerDirectoryHeadHash'] as $key) {
            self::digest($header[$key]);
        }
        self::domain($header['domain']);
        if ($header['version'] !== 2 || !is_int($header['sourceRowCount']) || $header['sourceRowCount'] < 0
            || !is_int($header['materializedRecordProofCount'])
            || $header['materializedRecordProofCount'] < $header['sourceRowCount']
            || $header['materializedRecordProofCount'] > 10000000
            || $header['scopeToken'] !== self::scopeToken($header['serverId'], $header['migrationId'], $header['scopeId'], $header['domain'])) {
            throw new NativeError('crypto_migration_provenance_context', 409);
        }
    }

    public static function portionToken($serverId, $migrationId, $accountId)
    {
        foreach ([$serverId, $migrationId, $accountId] as $id) self::uuid($id);
        return hash('sha256', "JivieMigrationPortion/v2\n".NativeCryptoCodec::canonical((object)[
            'version' => 2, 'serverId' => $serverId, 'migrationId' => $migrationId, 'accountId' => $accountId,
        ]));
    }

    public static function inventoryHash($serverId, $migrationId, $componentHash, iterable $portions)
    {
        self::uuid($serverId);
        self::uuid($migrationId);
        self::digest($componentHash);
        $hash = hash_init('sha256');
        hash_update($hash, "JivieMigrationInventory/v2\n".NativeCryptoCodec::canonical((object)[
            'version' => 2, 'serverId' => $serverId, 'migrationId' => $migrationId, 'componentHash' => $componentHash,
        ])."\n");
        $previous = null;
        $count = 0;
        foreach ($portions as $portion) {
            self::fields($portion, ['portionToken', 'inventoryHash']);
            self::digest($portion['portionToken']);
            self::digest($portion['inventoryHash']);
            if (($previous !== null && strcmp($previous, $portion['portionToken']) >= 0) || ++$count > 10000) {
                throw new NativeError('crypto_migration_inventory_portions', 409);
            }
            hash_update($hash, NativeCryptoCodec::canonical((object)$portion)."\n");
            $previous = $portion['portionToken'];
        }
        if ($count === 0) throw new NativeError('crypto_migration_inventory_portions', 409);
        return hash_final($hash);
    }

    public static function leafHash($header, $leaf)
    {
        self::header($header);
        self::fields($leaf, ['version', 'migrationId', 'inventoryHash', 'sourceInventoryHash', 'scopeId', 'domain',
            'membershipHeadHash', 'sourceTable', 'sourceId', 'sourceRowHash', 'legacyRevision',
            'sourceKind', 'canonicalId', 'wireId', 'type', 'recordProofHash', 'materializationRole',
            'contributorAccountId', 'contributorDeviceId', 'contributorDeviceSnapshotHash',
            'archiveManifestHash', 'coldParityHash']);
        foreach (['migrationId', 'inventoryHash', 'scopeId', 'domain', 'membershipHeadHash'] as $key) {
            if ($leaf[$key] !== $header[$key]) {
                throw new NativeError('crypto_migration_provenance_context', 409);
            }
        }
        foreach (['sourceId', 'canonicalId', 'contributorAccountId', 'contributorDeviceId'] as $key) {
            self::uuid($leaf[$key]);
        }
        foreach (['sourceRowHash', 'sourceInventoryHash', 'recordProofHash', 'contributorDeviceSnapshotHash', 'archiveManifestHash', 'coldParityHash'] as $key) {
            self::digest($leaf[$key]);
        }
        if ($leaf['version'] !== 2 || !is_int($leaf['legacyRevision']) || $leaf['legacyRevision'] < 0
            || !is_string($leaf['sourceTable'])
            || !in_array($leaf['materializationRole'], ['primary', 'taskDerivationIntent', 'taskDerivationResolution'], true)) {
            throw new NativeError('crypto_migration_provenance_leaf', 409);
        }
        $wireId = NativeCryptoRecordAddressV2::derive($header['serverId'], $leaf['scopeId'], $leaf['domain'], $leaf['sourceKind'], $leaf['canonicalId']);
        if ($wireId !== $leaf['wireId'] || NativeCryptoRecordAddressV2::sourceKind($leaf['type']) !== $leaf['sourceKind']
            || NativeCryptoRecordAddressV2::domain($leaf['type']) !== $leaf['domain']) {
            throw new NativeError('crypto_migration_provenance_address', 409);
        }
        return hash('sha256', "JivieMigrationLeaf/v2\n".NativeCryptoCodec::canonical((object)$leaf));
    }

    /** Caller supplies a bounded SQL iterator, never an unbounded request list. */
    public static function root($header, iterable $leaves)
    {
        self::header($header);
        $hash = hash_init('sha256');
        hash_update($hash, "JivieMigrationDomain/v2\n".NativeCryptoCodec::canonical((object)$header)."\n");
        $previous = null;
        $count = 0;
        foreach ($leaves as $leaf) {
            self::digest($leaf);
            if (($previous !== null && strcmp($previous, $leaf) >= 0)
                || ++$count > $header['materializedRecordProofCount']) {
                throw new NativeError('crypto_migration_provenance_stream', 409);
            }
            hash_update($hash, $leaf."\n");
            $previous = $leaf;
        }
        if ($count !== $header['materializedRecordProofCount']) {
            throw new NativeError('crypto_migration_provenance_count', 409);
        }
        return hash_final($hash);
    }

    private static function fields($value, $fields)
    {
        if (!is_array($value) || count($value) !== count($fields) || array_diff(array_keys($value), $fields)) {
            throw new NativeError('crypto_migration_provenance_shape', 409);
        }
    }

    private static function uuid($value)
    {
        if (!is_string($value) || !preg_match('/^[a-f0-9]{8}-[a-f0-9]{4}-[1-5][a-f0-9]{3}-[89ab][a-f0-9]{3}-[a-f0-9]{12}$/D', $value)) {
            throw new NativeError('crypto_migration_provenance_context', 409);
        }
    }

    private static function digest($value)
    {
        if (!is_string($value) || !preg_match('/^[a-f0-9]{64}$/D', $value)) {
            throw new NativeError('crypto_migration_provenance_context', 409);
        }
    }

    private static function domain($value)
    {
        if (!in_array($value, ['content', 'finance'], true)) {
            throw new NativeError('crypto_migration_provenance_context', 409);
        }
    }
}
