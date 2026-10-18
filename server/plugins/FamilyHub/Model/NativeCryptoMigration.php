<?php

namespace Kanboard\Plugin\FamilyHub\Model;

/** Durable migration checkpoints. No destructive cutover until every used domain is implemented. */
class NativeCryptoMigration extends NativeDatabase
{
    protected $cryptoAccess = true;
    public function readInTransaction($operation, $p, $actor)
    {
        if ($operation === 'crypto.legacy.lookup') {
            $this->fields($p, ['scopeId','legacyId','requestHash','finance']);
            $sid = $this->uuid($p['scopeId']);
            $this->scope($sid, $actor['user']['id']);
            $id = $this->uuid($p['legacyId']);
            if (!is_bool($p['finance']) || !is_string($p['requestHash']) || !preg_match('/^[a-f0-9]{64}$/D', $p['requestHash'])) {
                throw new NativeError('validation_error');
            }
            if ($p['finance']) {
                (new NativeFinanceAccess($this->container))->policyForCrypto($sid, $actor['user']);
            }
            $table = $p['finance'] ? 'familyhub_finance_operations' : 'familyhub_operations';
            $column = $p['finance'] ? 'account_id' : 'user_id';
            $owner = $p['finance'] ? $actor['user']['account_id'] : $actor['user']['id'];
            $r = $this->one('SELECT request_hash,status FROM '.$table.' WHERE scope_id=? AND '.$column.'=? AND id=?', [$sid,$owner,$id]);
            $migration = $this->one('SELECT state FROM familyhub_crypto_scopes WHERE scope_id=?', [$sid]);
            if ($r && !hash_equals($r['request_hash'], $p['requestHash'])) {
                throw new NativeError('idempotency_mismatch', 409);
            }
            // No plaintext body is accepted or returned. Missing is conclusive only after a write fence.
            return ['legacyId' => $id,'outcome' => $r ? ((int)$r['status'] === 200 ? 'applied' : 'rejected') : ($migration && in_array($migration['state'], ['fenced','verified','active'], true) ? 'notApplied' : 'unknown'),'status' => $r ? (int)$r['status'] : null];
        }
        $this->fields($p, ['migrationId']);
        $m = $this->migration($this->uuid($p['migrationId']), $actor);
        if ($operation === 'crypto.migration.status') {
            return $this->wire($m);
        }
        if ($operation === 'crypto.migration.inventory') {
            $ids = json_decode($m['scope_ids'], true, 34, JSON_THROW_ON_ERROR);
            $inventory = $this->inventory($ids, $actor);
            return ['migrationId' => $m['id'],'state' => $m['state'],'inventory' => $inventory,'inventoryHash' => hash('sha256', $this->canonical($inventory)),'expectedInventoryHash' => $m['inventory_hash']];
        }
        throw new NativeError('unsupported_operation', 404);
    }
    public function writeInTransaction($operation, $p, $actor, $proof)
    {
        if ($operation === 'crypto.migration.prepare') {
            $this->fields($p, ['migrationId','scopeIds']);
            $id = $this->uuid($p['migrationId']);
            $ids = $p['scopeIds'];
            if (!is_array($ids) || !array_is_list($ids) || count($ids) < 1 || count($ids) > 100 || count(array_unique($ids)) !== count($ids)) {
                throw new NativeError('validation_error');
            }sort($ids, SORT_STRING);
            if ($this->one('SELECT id FROM familyhub_crypto_migrations WHERE id=?', [$id])) {
                throw new NativeError('crypto_migration_exists', 409);
            }
            foreach ($ids as $sid) {
                $scope = $this->scope($this->uuid($sid), $actor['user']['id'], true, true);
                $existing = $this->one('SELECT * FROM familyhub_crypto_scopes WHERE scope_id=?', [$sid]);
                if ($existing) {
                    throw new NativeError('crypto_migration_busy', 409);
                }
            }
            $inventory = $this->inventory($ids, $actor);
            $hash = hash('sha256', $this->canonical($inventory));
            $this->change('INSERT INTO familyhub_crypto_migrations(id,owner_account_id,state,scope_ids,inventory,inventory_hash,created_at,updated_at) VALUES(?,?,?,?,?,?,?,?)', [$id,$actor['user']['account_id'],'preparing',json_encode($ids),$this->canonical($inventory),$hash,time(),time()]);
            foreach ($ids as $sid) {
                $scope = $this->scope($sid, $actor['user']['id']);
                $this->change('INSERT INTO familyhub_crypto_scopes(scope_id,epoch,sequence,access_revision,state,migration_id) VALUES(?,1,0,?,?,?)', [$sid,(int)$scope['effective_access_revision'],'preparing',$id]);
            }
            return ['migrationId' => $id,'state' => 'preparing','inventoryHash' => $hash,'usedFeatures' => $inventory['usedFeatures'],'cutoverSupported' => false];
        }
        if ($operation === 'crypto.legacy.reserveReplacement') {
            $this->fields($p, ['scopeId','legacyId','requestHash','replacementId','finance']);
            $sid = $this->uuid($p['scopeId']);
            $this->scope($sid, $actor['user']['id'], true);
            $lookup = $this->readInTransaction('crypto.legacy.lookup', array_diff_key($p, ['replacementId' => true]), $actor);
            if ($lookup['outcome'] !== 'notApplied') {
                throw new NativeError('crypto_legacy_outcome_unresolved', 409, ['outcome' => $lookup['outcome']]);
            }
            $replacement = $this->uuid($p['replacementId']);
            $old = $this->one('SELECT * FROM familyhub_crypto_legacy_receipts WHERE scope_id=? AND account_id=? AND legacy_id=?', [$sid,$actor['user']['account_id'],$p['legacyId']]);
            if ($old) {
                if (!hash_equals($old['legacy_hash'], $p['requestHash']) || $old['replacement_id'] !== $replacement) {
                    throw new NativeError('idempotency_mismatch', 409);
                }
            } else {
                $this->change('INSERT INTO familyhub_crypto_legacy_receipts VALUES(?,?,?,?,?,?)', [$sid,$actor['user']['account_id'],$p['legacyId'],$p['requestHash'],'notApplied',$replacement]);
            }
            return ['legacyId' => $p['legacyId'],'replacementId' => $replacement,'outcome' => 'reserved'];
        }
        $required = ['migrationId'];
        if (in_array($operation, ['crypto.migration.fence','crypto.migration.verify'], true)) {
            $required[] = 'inventoryHash';
        }if ($operation === 'crypto.migration.verify') {
            $required[] = 'encryptedManifestBase64';
        }
        $this->fields($p, $required);
        $id = $this->uuid($p['migrationId']);
        $m = $this->migration($id, $actor);
        $ids = json_decode($m['scope_ids'], true, 34, JSON_THROW_ON_ERROR);
        if ($operation === 'crypto.migration.abort') {
            if (in_array($m['state'], ['committed','retired'], true)) {
                throw new NativeError('crypto_migration_committed', 409);
            }
            $this->change("DELETE FROM familyhub_crypto_scopes WHERE migration_id=? AND state IN ('preparing','fenced','verified')", [$id]);
            $this->change("UPDATE familyhub_crypto_migrations SET state='aborted',updated_at=? WHERE id=?", [time(),$id]);
            return ['migrationId' => $id,'state' => 'aborted','legacyPreserved' => true];
        }
        if ($operation === 'crypto.migration.commit') {
            // Deliberate refusal: transport is not finance/reminder/moderation equivalence.
            throw new NativeError('crypto_cutover_not_supported', 409, ['usedFeatures' => json_decode($m['inventory'], true, 34, JSON_THROW_ON_ERROR)['usedFeatures'],'legacyPreserved' => true]);
        }
        if (!in_array($operation, ['crypto.migration.fence','crypto.migration.verify'], true)) {
            throw new NativeError('unsupported_operation', 404);
        }
        if ($operation === 'crypto.migration.fence' && $m['state'] !== 'preparing' || $operation === 'crypto.migration.verify' && $m['state'] !== 'fenced') {
            throw new NativeError('crypto_migration_state', 409);
        }
        $inventory = $this->inventory($ids, $actor);
        $hash = hash('sha256', $this->canonical($inventory));
        if (!is_string($p['inventoryHash']) || !hash_equals($hash, $p['inventoryHash'])) {
            throw new NativeError('crypto_inventory_changed', 409, ['inventoryHash' => $hash]);
        }
        $verification = null;
        $state = 'fenced';
        if ($operation === 'crypto.migration.verify') {
            $bytes = NativeCryptoCodec::base64($p['encryptedManifestBase64'], 262144);
            if (strlen($bytes) < 48) {
                throw new NativeError('crypto_invalid_envelope');
            }$verification = json_encode(['manifestBase64' => $p['encryptedManifestBase64'],'authorization' => $proof], JSON_THROW_ON_ERROR);
            $state = 'verified';
        }
        $this->change('UPDATE familyhub_crypto_migrations SET state=?,inventory=?,inventory_hash=?,verification=?,updated_at=? WHERE id=?', [$state,$this->canonical($inventory),$hash,$verification,time(),$id]);
        $this->change('UPDATE familyhub_crypto_scopes SET state=? WHERE migration_id=?', [$state,$id]);
        return ['migrationId' => $id,'state' => $state,'inventoryHash' => $hash,'cutoverSupported' => false];
    }
    private function migration($id, $actor)
    {
        $m = $this->one('SELECT * FROM familyhub_crypto_migrations WHERE id=?', [$id]);
        if (!$m || $m['owner_account_id'] !== $actor['user']['account_id']) {
            throw new NativeError('crypto_migration_missing', 404);
        }
        foreach (json_decode($m['scope_ids'], true, 34, JSON_THROW_ON_ERROR) as $sid) {
            $this->scope($sid, $actor['user']['id'], false, true);
        }return $m;
    }
    private function wire($m)
    {
        return ['migrationId' => $m['id'],'state' => $m['state'],'scopeIds' => json_decode($m['scope_ids'], true, 34, JSON_THROW_ON_ERROR),'inventoryHash' => $m['inventory_hash'],'cutoverSupported' => false,'legacyPreserved' => true];
    }
    public function inventory($ids, $actor)
    {
        $scopeData = [];
        $features = [];
        $tables = [];
        // Hash raw bytes, not lossy domain model roundtrips. Never return other actors' replay content.
        $names = $this->sqlite ? array_column($this->many("SELECT name FROM sqlite_master WHERE type='table' AND name LIKE 'familyhub_%' ORDER BY name"), 'name') : array_column($this->many("SELECT TABLE_NAME AS name FROM information_schema.TABLES WHERE TABLE_SCHEMA=DATABASE() AND TABLE_NAME LIKE 'familyhub_%' ORDER BY TABLE_NAME"), 'name');
        foreach ($ids as $sid) {
            $scope = $this->scope($sid, $actor['user']['id']);
            $scopeData[$sid] = ['sequence' => (int)$scope['sequence'],'accessRevision' => (int)$scope['effective_access_revision'],'members' => array_column((new NativeOrganizationAccess($this->container))->members($sid), 'accountId')];
            $finance = $this->one('SELECT sequence FROM familyhub_finance_policy WHERE scope_id=?', [$sid]);
            if ($finance) {
                $scopeData[$sid]['financeSequence'] = (int)$finance['sequence'];
            }
            foreach ($names as $name) {
                if (str_starts_with($name, 'familyhub_crypto_') || !preg_match('/^[a-z_]+$/D', $name)) {
                    continue;
                }
                $cols = $this->sqlite ? array_column($this->many('PRAGMA table_info('.$name.')'), 'name') : array_column($this->many('SHOW COLUMNS FROM '.$name), 'Field');
                $where = in_array('scope_id', $cols, true) ? 'scope_id' : ($name === 'familyhub_scopes' ? 'id' : null);
                if ($where === null) {
                    continue;
                }
                $rows = $this->many('SELECT * FROM '.$name.' WHERE '.$where.'=?', [$sid]);
                if (!$rows) {
                    continue;
                }$encoded = [];
                foreach ($rows as $row) {
                    $normalized = [];
                    ksort($row);
                    foreach ($row as $key => $value) {
                        $normalized[$key] = $value === null ? null : base64_encode((string)$value);
                    }$encoded[] = json_encode($normalized, JSON_UNESCAPED_SLASHES | JSON_THROW_ON_ERROR);
                }sort($encoded, SORT_STRING);
                $tables[$sid][$name] = ['rows' => count($encoded),'sha256' => hash('sha256', implode("\n", $encoded))];
                if (in_array($name, ['familyhub_records','familyhub_finance_records','familyhub_tables','familyhub_attachments','familyhub_idea_assets','familyhub_payment_events','familyhub_payment_projections','familyhub_payment_cash','familyhub_reminders','familyhub_inbox','familyhub_moderation_reports'], true)) {
                    $features[$name] = true;
                }
            }
        }
        $used = array_keys($features);
        sort($used, SORT_STRING);
        return ['format' => 1,'scopes' => (object)$scopeData,'tables' => (object)$tables,'usedFeatures' => $used,'fileBytesIncluded' => true,'files' => (new NativeCryptoFileInventory($this->container, $this->bearer, $this->ip))->collect($ids),'fileCoverage' => 'sql-associated-live-and-retired'];
    }
}
