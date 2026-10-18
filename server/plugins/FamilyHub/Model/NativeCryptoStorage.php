<?php

namespace Kanboard\Plugin\FamilyHub\Model;

/** Opaque transactions, immutable blob upload and scope-bound recipient envelopes. */
class NativeCryptoStorage extends NativeDatabase
{
    protected $cryptoAccess = true;
    public const CHUNK = 196608;
    public const MAX_BLOB = 22020096;
    public const TYPES = ['project','task','event','shoppingList','shoppingItem','householdPerson','garden','idea','financeAccount','financeEntry','financeTransfer','personalFinanceEntry','personalFinanceAccount','financeRecurrenceRule','paymentEvent','paymentProjection','cashMovement','table','attachment','scopeMetadata','notification','reminder'];

    public function readInTransaction($operation, $p, $actor)
    {
        if (str_starts_with($operation, 'crypto.migration.') || $operation === 'crypto.legacy.lookup') {
            return (new NativeCryptoMigration($this->container, $this->bearer, $this->ip))->readInTransaction($operation, $p, $actor);
        }
        $sid = $this->uuid($p['scopeId'] ?? null);
        $scope = $this->scope($sid, $actor['user']['id']);
        if ($operation === 'crypto.scope.status') {
            $this->fields($p, ['scopeId']);
            $r = $this->one('SELECT * FROM familyhub_crypto_scopes WHERE scope_id=?', [$sid]);
            return ['scopeId' => $sid,'state' => $r['state'] ?? 'legacy','epoch' => (int)($r['epoch'] ?? 0),'sequence' => (int)($r['sequence'] ?? 0),'accessRevision' => (int)$scope['effective_access_revision'],'cutoverSupported' => false];
        }
        if ($operation === 'crypto.grants.list') {
            $this->fields($p, ['scopeId','domain']);
            $this->domainAccess($p['domain'], $sid, $actor, false);
            $rows = $this->many('SELECT * FROM familyhub_crypto_grants WHERE scope_id=? AND account_id=? AND domain=? ORDER BY epoch', [$sid,$actor['user']['account_id'],$p['domain']]);
            $grants = [];
            foreach ($rows as $r) {
                $grants[] = ['scopeId' => $sid,'domain' => $r['domain'],'epoch' => (int)$r['epoch'],'generation' => (int)$r['generation'],'accessRevision' => (int)$r['access_revision'],'recipients' => json_decode($r['envelope'], true, 34, JSON_THROW_ON_ERROR),'authorization' => json_decode($r['authorization'], true, 34, JSON_THROW_ON_ERROR)];
            }return ['grants' => $grants,'accessRevision' => (int)$scope['effective_access_revision']];
        }
        $domain = $p['domain'] ?? 'content';
        $this->domainAccess($domain, $sid, $actor, false);
        $state = $this->active($sid, $scope, $actor, false, $domain);
        if ($operation === 'crypto.records.pull') {
            $this->fields($p, ['scopeId','cursor','accessRevision','domain'], ['limit']);
            $cursor = $p['cursor'];
            $limit = $p['limit'] ?? 20;
            if (!is_int($cursor) || $cursor < 0 || $cursor > (int)$state['sequence'] || !is_int($limit) || $limit < 1 || $limit > 50) {
                throw new NativeError('invalid_cursor');
            }
            if ($p['accessRevision'] !== (int)$scope['effective_access_revision']) {
                throw new NativeError('crypto_access_changed', 409);
            }
            $types = array_values(array_filter(self::TYPES, fn ($type) => $this->domain($type) === $domain));
            $rows = $this->many('SELECT * FROM familyhub_crypto_records WHERE scope_id=? AND sequence>? AND type IN ('.implode(',', array_fill(0, count($types), '?')).') ORDER BY sequence LIMIT '.($limit + 1), array_merge([$sid,$cursor], $types));
            $out = [];
            $bytes = 0;
            foreach ($rows as $r) {
                $wire = $this->wire($r);
                $n = strlen(json_encode($wire, JSON_THROW_ON_ERROR));
                if (count($out) >= $limit || ($out && $bytes + $n > 786432)) {
                    break;
                }$out[] = $wire;
                $bytes += $n;
            }
            $more = count($rows) > count($out);
            return ['records' => $out,'cursor' => $more ? end($out)['sequence'] : (int)$state['sequence'],'hasMore' => $more,'scopeSequence' => (int)$state['sequence'],'epoch' => (int)$state['epoch'],'accessRevision' => (int)$scope['effective_access_revision']];
        }
        if ($operation === 'crypto.blobs.get') {
            $this->fields($p, ['scopeId','id'], ['offset']);
            $id = $this->uuid($p['id']);
            $r = $this->one('SELECT * FROM familyhub_crypto_blobs WHERE scope_id=? AND id=? AND complete=1', [$sid,$id]);
            if (!$r) {
                throw new NativeError('crypto_blob_missing', 404);
            }
            $offset = $p['offset'] ?? 0;
            if (!is_int($offset) || $offset < 0 || $offset >= (int)$r['size'] || $offset % self::CHUNK !== 0) {
                throw new NativeError('validation_error');
            }
            $chunk = $this->one('SELECT data FROM familyhub_crypto_blob_chunks WHERE scope_id=? AND blob_id=? AND chunk_offset=?', [$sid,$id,$offset]);
            if (!$chunk) {
                throw new NativeError('crypto_blob_incomplete', 409);
            }
            return ['id' => $id,'offset' => $offset,'dataBase64' => $chunk['data'],'size' => (int)$r['size'],'sha256' => $r['sha256'],'epoch' => (int)$r['epoch'],'manifestBase64' => $r['manifest'],'done' => $offset + strlen(base64_decode($chunk['data'], true)) === (int)$r['size']];
        }
        throw new NativeError('unsupported_operation', 404);
    }

    public function writeInTransaction($operation, $p, $actor, $proof)
    {
        if (str_starts_with($operation, 'crypto.migration.') || str_starts_with($operation, 'crypto.legacy.')) {
            return (new NativeCryptoMigration($this->container, $this->bearer, $this->ip))->writeInTransaction($operation, $p, $actor, $proof);
        }
        if ($operation === 'crypto.records.batch') {
            return $this->batch($p, $actor, $proof);
        }
        $sid = $this->uuid($p['scopeId'] ?? null);
        $scope = $this->scope($sid, $actor['user']['id'], true);
        if ($operation === 'crypto.scope.prepare') {
            $this->fields($p, ['scopeId','expectedAccessRevision']);
            $this->scope($sid, $actor['user']['id'], true, true);
            if ($p['expectedAccessRevision'] !== (int)$scope['effective_access_revision']) {
                throw new NativeError('crypto_access_changed', 409);
            }
            if ($this->one('SELECT scope_id FROM familyhub_crypto_scopes WHERE scope_id=?', [$sid])) {
                throw new NativeError('crypto_scope_exists', 409);
            }
            $inventory = (new NativeCryptoMigration($this->container, $this->bearer, $this->ip))->inventory([$sid], $actor);
            // A just-invited otherwise empty space can already have member.joined inbox references.
            $used = array_values(array_diff($inventory['usedFeatures'], ['familyhub_inbox']));
            if ($used !== []) {
                throw new NativeError('crypto_migration_required', 409, ['usedFeatures' => $used]);
            }
            // Empty scope is staged only; no legacy-to-E2EE switch is enabled here.
            $this->change('INSERT INTO familyhub_crypto_scopes(scope_id,epoch,sequence,access_revision,state) VALUES(?,1,0,?,?)', [$sid,(int)$scope['effective_access_revision'],'staged']);
            return ['scopeId' => $sid,'state' => 'staged','epoch' => 1,'cutoverSupported' => false];
        }
        if ($operation === 'crypto.grants.put') {
            return $this->grant($p, $scope, $actor, $proof);
        }
        $state = $this->active($sid, $scope, $actor, true);
        if ($operation === 'crypto.blobs.begin') {
            $this->fields($p, ['scopeId','id','epoch','size','sha256','manifestBase64']);
            $id = $this->uuid($p['id']);
            $size = $p['size'];
            $this->hash($p['sha256']);
            $this->opaque($p['manifestBase64'], 16384);
            if ($p['epoch'] !== (int)$state['epoch'] || !is_int($size) || $size < 48 || $size > self::MAX_BLOB) {
                throw new NativeError('validation_error');
            }
            if ($this->one('SELECT id FROM familyhub_crypto_blobs WHERE scope_id=? AND id=?', [$sid,$id])) {
                throw new NativeError('crypto_blob_exists', 409);
            }
            $quota = $this->one('SELECT COUNT(*) AS n,COALESCE(SUM(size),0) AS bytes FROM familyhub_crypto_blobs WHERE scope_id=?', [$sid]);
            if ((int)$quota['n'] >= 1000 || (int)$quota['bytes'] + $size > 268435456) {
                throw new NativeError('crypto_blob_quota', 422);
            }
            $this->change('INSERT INTO familyhub_crypto_blobs(scope_id,id,owner_account_id,size,sha256,epoch,manifest) VALUES(?,?,?,?,?,?,?)', [$sid,$id,$actor['user']['account_id'],$size,$p['sha256'],$p['epoch'],$p['manifestBase64']]);
            return ['id' => $id,'offset' => 0,'complete' => false];
        }
        if (in_array($operation, ['crypto.blobs.chunk','crypto.blobs.complete'], true)) {
            $this->fields($p, ['scopeId','id'], $operation === 'crypto.blobs.chunk' ? ['offset','dataBase64'] : []);
            $id = $this->uuid($p['id']);
            $r = $this->one('SELECT * FROM familyhub_crypto_blobs WHERE scope_id=? AND id=?', [$sid,$id]);
            if (!$r || $r['owner_account_id'] !== $actor['user']['account_id']) {
                throw new NativeError('crypto_blob_missing', 404);
            }
            if ((int)$r['epoch'] !== (int)$state['epoch']) {
                throw new NativeError('crypto_epoch_changed', 409);
            }
            if ($operation === 'crypto.blobs.chunk') {
                $offset = $p['offset'] ?? null;
                $data = $this->opaque($p['dataBase64'] ?? null, self::CHUNK, 1);
                if (!is_int($offset) || $offset < 0 || $offset % self::CHUNK !== 0 || $offset + strlen($data) > (int)$r['size'] || ($offset + strlen($data) < (int)$r['size'] && strlen($data) !== self::CHUNK)) {
                    throw new NativeError('validation_error');
                }
                if ($offset < (int)$r['received']) {
                    $old = $this->one('SELECT data FROM familyhub_crypto_blob_chunks WHERE scope_id=? AND blob_id=? AND chunk_offset=?', [$sid,$id,$offset]);
                    if (!$old || !hash_equals($old['data'], $p['dataBase64'])) {
                        throw new NativeError('crypto_blob_chunk_conflict', 409);
                    }return ['id' => $id,'offset' => (int)$r['received'],'complete' => (bool)$r['complete']];
                }
                if ($offset !== (int)$r['received'] || (int)$r['complete']) {
                    throw new NativeError('crypto_blob_offset', 409, ['offset' => (int)$r['received']]);
                }
                $this->change('INSERT INTO familyhub_crypto_blob_chunks VALUES(?,?,?,?)', [$sid,$id,$offset,$p['dataBase64']]);
                $this->change('UPDATE familyhub_crypto_blobs SET received=received+? WHERE scope_id=? AND id=?', [strlen($data),$sid,$id]);
                return ['id' => $id,'offset' => $offset + strlen($data),'complete' => false];
            }
            if ((int)$r['received'] !== (int)$r['size']) {
                throw new NativeError('crypto_blob_incomplete', 409);
            }$hash = hash_init('sha256');
            $offset = 0;
            foreach ($this->many('SELECT * FROM familyhub_crypto_blob_chunks WHERE scope_id=? AND blob_id=? ORDER BY chunk_offset', [$sid,$id]) as $chunk) {
                if ((int)$chunk['chunk_offset'] !== $offset) {
                    throw new NativeError('crypto_blob_incomplete', 409);
                }$data = base64_decode($chunk['data'], true);
                hash_update($hash, $data);
                $offset += strlen($data);
            }
            if ($offset !== (int)$r['size'] || !hash_equals($r['sha256'], hash_final($hash))) {
                throw new NativeError('crypto_blob_integrity', 422);
            }
            $this->change('UPDATE familyhub_crypto_blobs SET complete=1 WHERE scope_id=? AND id=?', [$sid,$id]);
            return ['id' => $id,'offset' => $offset,'complete' => true];
        }
        throw new NativeError('unsupported_operation', 404);
    }

    private function grant($p, $scope, $actor, $proof)
    {
        $this->fields($p, ['scopeId','accountId','domain','epoch','accessRevision','expectedGeneration','recipients']);
        $sid = $scope['id'];
        $this->scope($sid, $actor['user']['id'], true, true);
        $aid = $this->uuid($p['accountId']);
        $this->domainAccess($p['domain'], $sid, $actor, true);
        if (!(new NativeOrganizationAccess($this->container))->visibleScope($sid, $aid)) {
            throw new NativeError('permission_revoked', 403);
        }
        if ($p['domain'] === 'finance' && !(new NativeFinanceAccess($this->container))->visible($sid, $aid, true)) {
            throw new NativeError('finance_forbidden', 403);
        }
        if ($p['accessRevision'] !== (int)$scope['effective_access_revision']) {
            throw new NativeError('crypto_access_changed', 409);
        }
        $state = $this->one('SELECT * FROM familyhub_crypto_scopes WHERE scope_id=?', [$sid]);
        if (!$state || $p['epoch'] !== (int)$state['epoch']) {
            throw new NativeError('crypto_epoch_changed', 409);
        }
        $recipients = $p['recipients'];
        if (!is_array($recipients) || !array_is_list($recipients) || count($recipients) < 1 || count($recipients) > 100) {
            throw new NativeError('validation_error');
        }
        $seen = [];
        $recovery = false;
        foreach ($recipients as $recipient) {
            if (!is_array($recipient)) {
                throw new NativeError('validation_error');
            }$this->fields($recipient, ['recipientId','publicKeyBase64','sealedEnvelopeBase64']);
            $key = $recipient['publicKeyBase64'];
            NativeCryptoCodec::base64($key, 32, 32);
            $this->opaque($recipient['sealedEnvelopeBase64'], 16384);
            $id = $recipient['recipientId'];
            if (isset($seen[$id])) {
                throw new NativeError('validation_error');
            }$seen[$id] = $recipient;
            if ($id === 'recovery') {
                $root = $this->one('SELECT root_encryption_key FROM familyhub_crypto_accounts WHERE account_id=?', [$aid]);
                if (!$root || !hash_equals($root['root_encryption_key'], $key)) {
                    throw new NativeError('crypto_recipient_key_changed', 409);
                }$recovery = true;
            } else {
                $this->uuid($id);
                $device = $this->one('SELECT encryption_key FROM familyhub_crypto_devices WHERE account_id=? AND device_id=? AND revoked_at IS NULL', [$aid,$id]);
                if (!$device || !hash_equals($device['encryption_key'], $key)) {
                    throw new NativeError('crypto_recipient_key_changed', 409);
                }
            }
        }
        if (!$recovery) {
            throw new NativeError('crypto_recovery_envelope_required', 409);
        }
        $previous = $this->one('SELECT * FROM familyhub_crypto_grants WHERE scope_id=? AND account_id=? AND domain=? AND epoch=?', [$sid,$aid,$p['domain'],$p['epoch']]);
        $generation = (int)($previous['generation'] ?? 0);
        if ($p['expectedGeneration'] !== $generation) {
            throw new NativeError('crypto_generation_conflict', 409, ['generation' => $generation]);
        }
        if ($previous) {
            foreach (json_decode($previous['envelope'], true, 34, JSON_THROW_ON_ERROR) as $old) {
                if (!isset($seen[$old['recipientId']]) || $seen[$old['recipientId']] !== $old) {
                    throw new NativeError('crypto_envelope_immutable', 409);
                }
            }
        }
        $values = [(int)$p['accessRevision'],$generation + 1,json_encode($recipients, JSON_THROW_ON_ERROR),json_encode($proof, JSON_THROW_ON_ERROR),$sid,$aid,$p['domain'],$p['epoch']];
        if ($previous) {
            $this->change('UPDATE familyhub_crypto_grants SET access_revision=?,generation=?,envelope=?,authorization=? WHERE scope_id=? AND account_id=? AND domain=? AND epoch=?', $values);
        } else {
            $this->change('INSERT INTO familyhub_crypto_grants(access_revision,generation,envelope,authorization,scope_id,account_id,domain,epoch) VALUES(?,?,?,?,?,?,?,?)', $values);
        }
        return ['scopeId' => $sid,'epoch' => $p['epoch'],'generation' => $generation + 1];
    }

    private function active($sid, $scope, $actor, $write, $domain = 'content')
    {
        $state = $this->one('SELECT * FROM familyhub_crypto_scopes WHERE scope_id=?', [$sid]);
        // Staging transport is usable by test clients, but never shadows the legacy projection.
        if (!$state || !in_array($state['state'], ['staged','active'], true)) {
            throw new NativeError('crypto_scope_not_ready', 409);
        }
        if ((int)$state['access_revision'] !== (int)$scope['effective_access_revision']) {
            throw new NativeError('crypto_access_changed', 409);
        }
        $grant = $this->one('SELECT envelope FROM familyhub_crypto_grants WHERE scope_id=? AND account_id=? AND domain=? AND epoch=? AND access_revision=?', [$sid,$actor['user']['account_id'],$domain,$state['epoch'],(int)$scope['effective_access_revision']]);
        if (!$grant) {
            throw new NativeError('crypto_keys_pending', 409);
        }$found = false;
        foreach (json_decode($grant['envelope'], true, 34, JSON_THROW_ON_ERROR) as $r) {
            if ($r['recipientId'] === $actor['device']['id']) {
                $found = true;
            }
        }
        if (!$found) {
            throw new NativeError('crypto_device_keys_pending', 409);
        }return $state;
    }

    private function batch($p, $actor, $proof)
    {
        $this->fields($p, ['records']);
        $records = $p['records'];
        if (!is_array($records) || !array_is_list($records) || count($records) < 1 || count($records) > 32) {
            throw new NativeError('validation_error');
        }
        $this->authorizeBatch($p, $actor);
        $seen = [];
        $states = [];
        $prepared = [];
        $overlay = [];
        foreach ($records as $r) {
            if (!is_array($r)) {
                throw new NativeError('validation_error');
            }$this->fields($r, ['scopeId','id','type','expectedRevision','deleted','epoch','envelopeBase64','metadata']);
            $sid = $this->uuid($r['scopeId']);
            $id = $this->uuid($r['id']);
            $key = $sid.':'.$id;
            if (isset($seen[$key]) || !in_array($r['type'], self::TYPES, true) || !is_bool($r['deleted']) || !is_int($r['expectedRevision']) || $r['expectedRevision'] < 0) {
                throw new NativeError('validation_error');
            }$seen[$key] = true;
            $scope = $this->scope($sid, $actor['user']['id'], true);
            $domain = $this->domain($r['type']);
            $this->domainAccess($domain, $sid, $actor, true);
            $state = $this->active($sid, $scope, $actor, true, $domain);
            $states[$sid] = $state;
            if ($r['epoch'] !== (int)$state['epoch']) {
                throw new NativeError('crypto_epoch_changed', 409);
            }
            if ($r['deleted']) {
                if ($r['envelopeBase64'] !== null) {
                    throw new NativeError('validation_error');
                }
            } else {
                $this->opaque($r['envelopeBase64'], 196608);
            }
            $current = $this->one('SELECT * FROM familyhub_crypto_records WHERE scope_id=? AND id=?', [$sid,$id]);
            if (($current && ((int)$current['revision'] !== $r['expectedRevision'] || (int)$current['deleted'] || $current['type'] !== $r['type'])) || (!$current && ($r['expectedRevision'] !== 0 || $r['deleted']))) {
                throw new NativeError('crypto_conflict', 409, ['scopeId' => $sid,'recordId' => $id,'serverRecord' => $current ? $this->wire($current) : null]);
            }
            $this->metadata($r['metadata']);
            $prepared[] = [$r,$current];
            $overlay[$key] = $r;
        }
        // Check the final graph, including unchanged children and in-batch tombstones.
        foreach ($prepared as [$r]) {
            if ($r['deleted']) {
                continue;
            }
            foreach ($r['metadata']['references'] as $ref) {
                $key = $ref['scopeId'].':'.$ref['id'];
                $target = $overlay[$key] ?? $this->one('SELECT deleted,type FROM familyhub_crypto_records WHERE scope_id=? AND id=?', [$ref['scopeId'],$ref['id']]);
                if (!$target || $target['deleted']) {
                    throw new NativeError('parent_missing', 422);
                }
            }
        }
        foreach ($prepared as [$r]) {
            if (!$r['deleted']) {
                continue;
            }foreach ($this->iterate('SELECT scope_id,id,metadata FROM familyhub_crypto_records WHERE scope_id=? AND deleted=0', [$r['scopeId']]) as $other) {
                $key = $other['scope_id'].':'.$other['id'];
                $final = $overlay[$key] ?? null;
                if ($final && $final['deleted']) {
                    continue;
                }$metadata = $final ? $final['metadata'] : json_decode($other['metadata'], true, 34, JSON_THROW_ON_ERROR);
                foreach ($metadata['references'] as $ref) {
                    if ($ref['scopeId'] === $r['scopeId'] && $ref['id'] === $r['id']) {
                        throw new NativeError('live_children', 422);
                    }
                }
            }
        }
        // Release every changed unique token before reserving its final owner.
        foreach ($prepared as [$r]) {
            $this->change('DELETE FROM familyhub_crypto_unique_refs WHERE scope_id=? AND record_id=?', [$r['scopeId'],$r['id']]);
        }
        foreach ($prepared as [$r,$current]) {
            $sid = $r['scopeId'];
            $id = $r['id'];
            if (!$r['deleted']) {
                foreach ($r['metadata']['uniqueRefs'] as $ref) {
                    $old = $this->one('SELECT record_id FROM familyhub_crypto_unique_refs WHERE scope_id=? AND reference_hash=?', [$sid,$ref]);
                    if ($old && $old['record_id'] !== $id) {
                        throw new NativeError('duplicate_finance_reference', 409);
                    } $this->change('INSERT INTO familyhub_crypto_unique_refs VALUES(?,?,?)', [$sid,$ref,$id]);
                }
            }
            $sequence = ++$states[$sid]['sequence'];
            $revision = $r['expectedRevision'] + 1;
            $values = [$r['type'],$revision,(int)$r['deleted'],$sequence,$r['epoch'],$r['envelopeBase64'] ?? '',json_encode($r['metadata'], JSON_THROW_ON_ERROR),json_encode($proof, JSON_THROW_ON_ERROR),$sid,$id];
            if ($current) {
                $this->change('UPDATE familyhub_crypto_records SET type=?,revision=?,deleted=?,sequence=?,epoch=?,envelope=?,metadata=?,authorization=? WHERE scope_id=? AND id=?', $values);
            } else {
                $this->change('INSERT INTO familyhub_crypto_records(type,revision,deleted,sequence,epoch,envelope,metadata,authorization,scope_id,id) VALUES(?,?,?,?,?,?,?,?,?,?)', $values);
            }
        }
        foreach ($states as $sid => $state) {
            $this->change('UPDATE familyhub_crypto_scopes SET sequence=? WHERE scope_id=?', [$state['sequence'],$sid]);
        }
        $out = [];
        foreach ($prepared as [$r]) {
            $row = $this->one('SELECT revision,sequence FROM familyhub_crypto_records WHERE scope_id=? AND id=?', [$r['scopeId'],$r['id']]);
            $out[] = ['scopeId' => $r['scopeId'],'id' => $r['id'],'revision' => (int)$row['revision'],'sequence' => (int)$row['sequence']];
        }return ['status' => 'applied','records' => $out];
    }
    /** Includes replay authorization: cached ciphertext never bypasses a current grant. */
    public function authorizeBatch($p, $actor)
    {
        if (!isset($p['records']) || !is_array($p['records']) || !array_is_list($p['records']) || count($p['records']) < 1 || count($p['records']) > 32) {
            throw new NativeError('validation_error');
        }
        $scopeIds = [];
        $domains = [];
        foreach ($p['records'] as $r) {
            if (!is_array($r)) {
                throw new NativeError('validation_error');
            }$scopeIds[] = $this->uuid($r['scopeId'] ?? null);
            $domains[$this->domain($r['type'] ?? '')] = true;
            $this->metadata($r['metadata'] ?? null);
            foreach ($r['metadata']['references'] as $ref) {
                if ($ref['scopeId'] !== $r['scopeId']) {
                    throw new NativeError('crypto_cross_scope_proof_required', 409);
                }
            }
        }
        if (count(array_unique($scopeIds)) !== 1 || count($domains) !== 1) {
            throw new NativeError('crypto_cross_scope_proof_required', 409);
        }
        $scopeIds = array_values(array_unique($scopeIds));
        sort($scopeIds, SORT_STRING);
        foreach ($scopeIds as $sid) {
            $this->scope($sid, $actor['user']['id']);
        }
        foreach ($p['records'] as $r) {
            $sid = $r['scopeId'];
            $scope = $this->scope($sid, $actor['user']['id'], true);
            $domain = $this->domain($r['type'] ?? '');
            $this->domainAccess($domain, $sid, $actor, true);
            $this->active($sid, $scope, $actor, true, $domain);
            foreach ($r['metadata']['references'] as $ref) {
                $target = $this->one('SELECT type FROM familyhub_crypto_records WHERE scope_id=? AND id=?', [$ref['scopeId'],$ref['id']]);
                if ($target) {
                    $this->domainAccess($this->domain($target['type']), $ref['scopeId'], $actor, false);
                }
            }
        }
    }
    private function domain($type)
    {
        return $this->financialRecordType($type) || in_array($type, ['paymentEvent','paymentProjection','cashMovement'], true) ? 'finance' : 'content';
    }
    private function domainAccess($domain, $sid, $actor, $write)
    {
        if (!in_array($domain, ['content','finance'], true)) {
            throw new NativeError('validation_error');
        }
        if ($domain === 'finance') {
            (new NativeFinanceAccess($this->container))->policyForCrypto($sid, $actor['user'], $write, true);
        }
    }
    private function metadata($m)
    {
        if (!is_array($m)) {
            throw new NativeError('validation_error');
        }$this->fields($m, ['references','uniqueRefs']);
        if (!is_array($m['references']) || !array_is_list($m['references']) || count($m['references']) > 100 || !is_array($m['uniqueRefs']) || !array_is_list($m['uniqueRefs']) || count($m['uniqueRefs']) > 10) {
            throw new NativeError('validation_error');
        }
        foreach ($m['references'] as $r) {
            if (!is_array($r)) {
                throw new NativeError('validation_error');
            }$this->fields($r, ['scopeId','id']);
            $this->uuid($r['scopeId']);
            $this->uuid($r['id']);
        }
        foreach ($m['uniqueRefs'] as $r) {
            $this->hash($r);
        }
        if (count(array_unique($m['uniqueRefs'])) !== count($m['uniqueRefs'])) {
            throw new NativeError('validation_error');
        }
    }
    private function wire($r)
    {
        return ['scopeId' => $r['scope_id'],'id' => $r['id'],'type' => $r['type'],'revision' => (int)$r['revision'],'deleted' => (bool)$r['deleted'],'sequence' => (int)$r['sequence'],'epoch' => (int)$r['epoch'],'envelopeBase64' => $r['envelope'] ?: null,'metadata' => json_decode($r['metadata'], true, 34, JSON_THROW_ON_ERROR),'authorization' => json_decode($r['authorization'], true, 34, JSON_THROW_ON_ERROR)];
    }
    private function opaque($value, $max, $min = 48)
    {
        $raw = NativeCryptoCodec::base64($value, $max);
        if (strlen($raw) < $min) {
            throw new NativeError('crypto_invalid_envelope');
        }return $raw;
    }
    private function hash($value)
    {
        if (!is_string($value) || !preg_match('/^[a-f0-9]{64}$/D', $value)) {
            throw new NativeError('validation_error');
        }
    }
}
