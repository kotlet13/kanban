<?php

namespace Kanboard\Plugin\FamilyHub\Model;

/** Also applied when the preview flag is later disabled: a durable fence cannot disappear. */
class NativeCryptoFence
{
    public static function state($pdo, $sid)
    {
        try {
            $q = $pdo->prepare("SELECT s.state, o.scope_id AS encrypted_origin FROM (SELECT ? AS scope_id) requested LEFT JOIN familyhub_crypto_scopes s ON s.scope_id=requested.scope_id LEFT JOIN familyhub_crypto_scope_origins o ON o.scope_id=requested.scope_id");
            $q->execute([$sid]);
            $row = $q->fetch(\PDO::FETCH_ASSOC);
            $q->closeCursor();
            if ($row && $row['encrypted_origin'] !== null) {
                return 'active';
            }
            return $row['state'] ?? null;
        } catch (\PDOException $error) {
            if (!self::missingTable($error)) {
                throw new NativeError('crypto_fence_unavailable', 503);
            }
        }
        // Source compatibility with schema19 and older preview schemas. Query
        // independently so a missing derived scope table cannot hide an origin.
        $state = null;
        foreach (['SELECT state FROM familyhub_crypto_scopes WHERE scope_id=?','SELECT scope_id FROM familyhub_crypto_scope_origins WHERE scope_id=?'] as $index => $sql) {
            try {
                $q = $pdo->prepare($sql);
                $q->execute([$sid]);
                $value = $q->fetchColumn();
                $q->closeCursor();
                if ($index === 1 && $value !== false) {
                    return 'active';
                }
                if ($index === 0 && $value !== false) {
                    $state = $value;
                }
            } catch (\PDOException $error) {
                if (!self::missingTable($error)) {
                    throw new NativeError('crypto_fence_unavailable', 503);
                }
            }
        }
        return $state;
    }
    public static function guard($pdo, $sid)
    {
        $state = self::state($pdo, $sid);
        if (in_array($state, ['fenced','verified'], true)) {
            throw new NativeError('crypto_migration_in_progress', 409);
        }
        if ($state !== null && !in_array($state, ['preparing','staged','aborted'], true)) {
            throw new NativeError('crypto_upgrade_required', 409);
        }
    }
    public static function workerBlocked($pdo, $sid)
    {
        $state = self::state($pdo, $sid);
        return $state !== null && !in_array($state, ['preparing','staged','aborted'], true);
    }
    /** Discovery only: exclude paused rows BEFORE LIMIT, then recheck under
     * parent/scope locks before taking a lease or changing any source state.
     * The expression is an internal qualified column, never request input. */
    public static function workerDiscoverySql($pdo, $scopeColumn, $crypto = false)
    {
        if (!is_string($scopeColumn) || !preg_match('/^[a-z][a-z0-9_]*\.[a-z][a-z0-9_]*$/D', $scopeColumn)) {
            throw new \InvalidArgumentException('Invalid worker scope column');
        }
        $hasScopes = self::hasTable($pdo, 'familyhub_crypto_scopes');
        $hasOrigins = self::hasTable($pdo, 'familyhub_crypto_scope_origins');
        if ($crypto) {
            // Match guardBusiness: an exact new origin, or an atomically
            // committed migration. A preparing/fenced candidate is inert.
            $origin = $hasOrigins ? 'EXISTS (SELECT 1 FROM familyhub_crypto_scope_origins worker_origin WHERE worker_origin.scope_id='.$scopeColumn.')' : '1=0';
            $committed = $hasScopes && self::hasTable($pdo, 'familyhub_crypto_migrations_v2')
                ? "EXISTS (SELECT 1 FROM familyhub_crypto_scopes worker_state JOIN familyhub_crypto_migrations_v2 worker_migration ON worker_migration.id=worker_state.migration_id WHERE worker_state.scope_id=".$scopeColumn." AND worker_state.state='active' AND worker_migration.state IN ('committed','retired'))" : '1=0';
            return '('.$origin.' OR '.$committed.')';
        }
        $ids = $scopeColumn.',(SELECT COALESCE(worker_scope.parent_scope_id,worker_scope.organization_id) FROM familyhub_scopes worker_scope WHERE worker_scope.id='.$scopeColumn.')';
        $conditions = [];
        if ($hasScopes) {
            $conditions[] = "NOT EXISTS (SELECT 1 FROM familyhub_crypto_scopes worker_state WHERE worker_state.scope_id IN (".$ids.") AND worker_state.state NOT IN ('preparing','staged','aborted'))";
        }
        if ($hasOrigins) {
            $conditions[] = 'NOT EXISTS (SELECT 1 FROM familyhub_crypto_scope_origins worker_origin WHERE worker_origin.scope_id IN ('.$ids.'))';
        }
        return $conditions ? '('.implode(' AND ', $conditions).')' : '1=1';
    }
    private static function hasTable($pdo, $table)
    {
        try {
            $q = $pdo->query('SELECT 1 FROM '.$table.' WHERE 1=0');
            $q->closeCursor();
            return true;
        } catch (\PDOException $error) {
            if (self::missingTable($error)) { return false; }
            throw new NativeError('crypto_fence_unavailable', 503);
        }
    }
    public static function cleanupPaused($pdo)
    {
        try {
            $q = $pdo->query("SELECT scope_id FROM familyhub_crypto_scopes WHERE state IN ('fenced','verified') LIMIT 1");
            $r = $q->fetch();
            $q->closeCursor();
            return (bool)$r;
        } catch (\PDOException $e) {
            if (self::missingTable($e)) {
                return false;
            }throw new NativeError('crypto_fence_unavailable', 503);
        }
    }
    private static function missingTable($e)
    {
        return ($e->errorInfo[0] ?? '') === '42S02' || ($e->errorInfo[1] ?? null) === 1 && str_contains($e->getMessage(), 'no such table: familyhub_crypto_');
    }
}
