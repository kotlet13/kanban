<?php

namespace Kanboard\Plugin\FamilyHub\Model;

/** Durable protocol minimum; runtime availability flags cannot downgrade persisted evidence. */
class NativeCryptoV2Boundary
{
    public static function account($pdo, $account)
    {
        // Probe separately: a damaged/missing derived cache cannot hide an immutable log.
        return self::exists($pdo, 'SELECT account_id FROM familyhub_crypto_directory_state WHERE account_id=?', [$account])
            || self::exists($pdo, 'SELECT account_id FROM familyhub_crypto_directory WHERE account_id=? LIMIT 1', [$account]);
    }

    public static function scope($pdo, $id)
    {
        if (!is_string($id) || strpbrk($id, '%_\\\"') !== false) {
            throw new NativeError('validation_error');
        }
        if (self::exists($pdo, 'SELECT scope_id FROM familyhub_crypto_lifecycle_baselines_v2 WHERE scope_id=?', [$id])
            || self::exists($pdo, 'SELECT scope_id FROM familyhub_crypto_scope_origins WHERE scope_id=?', [$id])
            || self::exists($pdo, 'SELECT scope_id FROM familyhub_crypto_scope_state WHERE scope_id=?', [$id])
            || self::exists($pdo, 'SELECT scope_id FROM familyhub_crypto_scope_heads WHERE scope_id=? LIMIT 1', [$id])) {
            return true;
        }
        // Canonical scope lists contain quoted UUIDs, not substring relationships.
        return self::exists($pdo, "SELECT p.migration_id FROM familyhub_crypto_migration_portions_v2 p JOIN familyhub_crypto_migrations_v2 m ON m.id=p.migration_id WHERE p.scope_ids LIKE ? AND p.state<>'aborted' AND m.state<>'aborted' LIMIT 1", ['%"'.$id.'"%']);
    }

    public static function guardV1($pdo, $account, array $payload)
    {
        if (self::account($pdo, $account)) {
            throw new NativeError('crypto_upgrade_required', 409);
        }
        $ids = [];
        if (isset($payload['scopeId'])) {
            $ids[] = $payload['scopeId'];
        }
        foreach ($payload['scopeIds'] ?? [] as $id) {
            $ids[] = $id;
        }
        foreach ($payload['records'] ?? [] as $record) {
            if (is_array($record) && isset($record['scopeId'])) {
                $ids[] = $record['scopeId'];
            }
        }
        foreach (array_unique($ids) as $id) {
            if (self::scope($pdo, $id)) {
                throw new NativeError('crypto_upgrade_required', 409);
            }
        }
    }

    /** A legacy parent mutation may change effective child ACL even without its own crypto head. */
    public static function guardStructural($pdo, $scopeId)
    {
        $ids = [$scopeId => true];
        $q = $pdo->prepare('SELECT id,parent_scope_id,organization_id FROM familyhub_scopes WHERE id=? OR parent_scope_id=? OR organization_id=?');
        $q->execute([$scopeId,$scopeId,$scopeId]);
        foreach ($q->fetchAll(\PDO::FETCH_ASSOC) as $row) {
            $ids[$row['id']] = true;
            $parent = $row['parent_scope_id'] ?? $row['organization_id'] ?? null;
            if ($parent) {
                $ids[$parent] = true;
            }
        }
        $q->closeCursor();
        foreach (array_keys($ids) as $id) {
            if (self::scope($pdo, $id)) {
                throw new NativeError('crypto_upgrade_required', 409);
            }
        }
    }

    private static function exists($pdo, $sql, $params)
    {
        try {
            $query = $pdo->prepare($sql);
            $query->execute($params);
            $found = $query->fetchColumn() !== false;
            $query->closeCursor();
            return $found;
        } catch (\PDOException $error) {
            $state = $error->errorInfo[0] ?? $error->getCode();
            $number = (int)($error->errorInfo[1] ?? 0);
            if ($state === '42S02' || $number === 1146 || $state === 'HY000' && $number === 1 && str_contains($error->getMessage(), 'no such table:')) {
                return false;
            }
            throw new NativeError('crypto_protocol_floor_unavailable', 503);
        }
    }
}
