<?php

namespace Kanboard\Plugin\FamilyHub\Model;

/** Ciphertext staging only. The migration caller supplies frozen READ authority. */
class NativeCryptoMigrationBlobV2 extends NativeDatabase
{
    public const MAX_BYTES = 23068672;
    public const CHUNK_BYTES = 196608;
    public const BASE_FIELDS = [
        'migrationId', 'inventoryHash', 'componentHash', 'scopeId', 'id',
        'sourceTable', 'sourceId', 'sourceRowHash', 'domain', 'purpose',
        'epoch', 'membershipHeadHash', 'accessRevision',
    ];

    public function handle($operation, $params, $actor, $proof, $allowance)
    {
        $key = [$params['migrationId'], $params['id']];
        $row = $this->one(
            'SELECT * FROM familyhub_crypto_migration_blobs_v2 WHERE migration_id=? AND id=?',
            $key
        );
        if ($row) {
            $expected = [
                'inventoryHash' => 'source_inventory_hash', 'componentHash' => 'component_hash',
                'scopeId' => 'scope_id', 'sourceTable' => 'source_table', 'sourceId' => 'source_id',
                'sourceRowHash' => 'source_row_hash', 'domain' => 'domain', 'purpose' => 'purpose',
                'membershipHeadHash' => 'head_hash',
            ];
            foreach ($expected as $field => $column) {
                if ($params[$field] !== $row[$column]) {
                    throw new NativeError('crypto_migration_blob_immutable', 409);
                }
            }
            if ($row['account_id'] !== $actor['user']['account_id']
                || (int)$row['epoch'] !== $params['epoch']
                || (int)$row['access_revision'] !== $params['accessRevision']) {
                throw new NativeError('crypto_migration_blob_immutable', 409);
            }
        }
        if ($operation === 'crypto2.migration.blob.begin') {
            return $this->begin($params, $actor, $proof, $allowance, $row);
        }
        if (!$row) {
            throw new NativeError('crypto_migration_blob_missing', 404);
        }
        if ($operation === 'crypto2.migration.blob.chunk') {
            return $this->chunk($params, $row);
        }
        if ($operation === 'crypto2.migration.blob.complete') {
            return $this->complete($row);
        }
        if ($operation === 'crypto2.migration.blob.get') {
            return $this->get($params, $row);
        }
        throw new NativeError('unsupported_operation', 404);
    }

    private function begin($params, $actor, $proof, $allowance, $old)
    {
        $size = $params['size'];
        if (!is_int($size) || $size < 48 || $size > self::MAX_BYTES
            || !is_string($params['sha256']) || !preg_match('/^[a-f0-9]{64}$/D', $params['sha256'])) {
            throw new NativeError('crypto_migration_blob_size', 409);
        }
        $manifest = NativeCryptoCodec::base64($params['manifestBase64'], 16384);
        if (strlen($manifest) < 48) {
            throw new NativeError('crypto_invalid_envelope');
        }
        if ($old) {
            if ((int)$old['size'] !== $size || $old['sha256'] !== $params['sha256']
                || $old['manifest'] !== $params['manifestBase64']) {
                throw new NativeError('crypto_migration_blob_immutable', 409);
            }
            return $this->status($old);
        }
        // Count incomplete objects too. Unknown outcomes and aborted generations
        // never replenish this generation's trusted source allowance.
        $used = $this->one(
            'SELECT COALESCE(SUM(size),0) AS bytes,COUNT(*) AS objects FROM familyhub_crypto_migration_blobs_v2 WHERE migration_id=? AND account_id=? AND source_table=? AND source_id=? AND scope_id=?',
            [$params['migrationId'], $actor['user']['account_id'], $params['sourceTable'], $params['sourceId'], $params['scopeId']]
        );
        if ((int)$used['bytes'] + $size > $allowance['bytes']
            || (int)$used['objects'] + 1 > $allowance['objects']) {
            throw new NativeError('crypto_migration_blob_quota', 409);
        }
        $this->change(
            'INSERT INTO familyhub_crypto_migration_blobs_v2 VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,0,0,?,?)',
            [$params['migrationId'], $params['id'], $actor['user']['account_id'],
                $params['inventoryHash'], $params['componentHash'], $params['sourceTable'],
                $params['sourceId'], $params['sourceRowHash'], $params['scopeId'], $params['domain'],
                $params['purpose'], $params['epoch'], $params['membershipHeadHash'],
                $params['accessRevision'], $size, $params['sha256'], $params['manifestBase64'],
                NativeCryptoCodec::canonical((object)$proof)]
        );
        return ['id' => $params['id'], 'received' => 0, 'complete' => false];
    }

    private function chunk($params, $row)
    {
        $offset = $params['offset'];
        if (!is_int($offset) || $offset < 0 || $offset % self::CHUNK_BYTES !== 0
            || $offset >= (int)$row['size']) {
            throw new NativeError('crypto_migration_blob_offset', 409);
        }
        $bytes = NativeCryptoCodec::base64($params['dataBase64'], self::CHUNK_BYTES);
        if (strlen($bytes) !== min(self::CHUNK_BYTES, (int)$row['size'] - $offset)) {
            throw new NativeError('crypto_migration_blob_chunk_size', 409);
        }
        $key = [$row['migration_id'], $row['id'], $offset];
        $old = $this->one(
            'SELECT data FROM familyhub_crypto_migration_blob_chunks_v2 WHERE migration_id=? AND blob_id=? AND chunk_offset=?',
            $key
        );
        if ($old) {
            if ($old['data'] !== $params['dataBase64']) {
                throw new NativeError('crypto_migration_blob_chunk_changed', 409);
            }
            return $this->status($row);
        }
        if ((int)$row['complete'] !== 0 || (int)$row['received'] !== $offset) {
            throw new NativeError('crypto_migration_blob_offset', 409);
        }
        $this->change('INSERT INTO familyhub_crypto_migration_blob_chunks_v2 VALUES(?,?,?,?)',
            [...$key, $params['dataBase64']]);
        $received = $offset + strlen($bytes);
        $this->change('UPDATE familyhub_crypto_migration_blobs_v2 SET received=? WHERE migration_id=? AND id=?',
            [$received, $row['migration_id'], $row['id']]);
        $row['received'] = $received;
        return $this->status($row);
    }

    private function complete($row)
    {
        if ((int)$row['received'] !== (int)$row['size']) {
            throw new NativeError('crypto_migration_blob_incomplete', 409);
        }
        $hash = hash_init('sha256');
        $offset = 0;
        foreach ($this->iterate(
            'SELECT chunk_offset,data FROM familyhub_crypto_migration_blob_chunks_v2 WHERE migration_id=? AND blob_id=? ORDER BY chunk_offset',
            [$row['migration_id'], $row['id']]
        ) as $chunk) {
            $bytes = NativeCryptoCodec::base64($chunk['data'], self::CHUNK_BYTES);
            if ((int)$chunk['chunk_offset'] !== $offset
                || strlen($bytes) !== min(self::CHUNK_BYTES, (int)$row['size'] - $offset)) {
                throw new NativeError('crypto_migration_blob_integrity', 409);
            }
            hash_update($hash, $bytes);
            $offset += strlen($bytes);
        }
        if ($offset !== (int)$row['size'] || !hash_equals($row['sha256'], hash_final($hash))) {
            throw new NativeError('crypto_migration_blob_integrity', 409);
        }
        $this->change('UPDATE familyhub_crypto_migration_blobs_v2 SET complete=1 WHERE migration_id=? AND id=?',
            [$row['migration_id'], $row['id']]);
        $row['complete'] = 1;
        return $this->status($row);
    }

    /** Internal immutable-row reader. The migration caller has already bound
     * exact signed stage/begin evidence and current scoped CONTENT READ. */
    public function readVerifiedCipher($row,$offset)
    {
        return $this->get(['offset'=>$offset],$row);
    }

    private function get($params, $row)
    {
        $offset = $params['offset'];
        if ((int)$row['complete'] !== 1 || !is_int($offset) || $offset < 0
            || $offset > (int)$row['size'] || $offset % self::CHUNK_BYTES !== 0) {
            throw new NativeError('crypto_migration_blob_incomplete', 409);
        }
        $chunk = $this->one(
            'SELECT data FROM familyhub_crypto_migration_blob_chunks_v2 WHERE migration_id=? AND blob_id=? AND chunk_offset=?',
            [$row['migration_id'], $row['id'], $offset]
        );
        if (!$chunk && $offset !== (int)$row['size']) {
            throw new NativeError('crypto_migration_blob_integrity', 409);
        }
        $data = $chunk['data'] ?? '';
        return array_merge($this->status($row), [
            'size' => (int)$row['size'], 'sha256' => $row['sha256'],
            'manifestBase64' => $row['manifest'], 'offset' => $offset,
            'nextOffset' => $offset + strlen(base64_decode($data, true)),
            'dataBase64' => $data, 'authorization' => json_decode($row['authorization'], true, 34, JSON_THROW_ON_ERROR),
        ]);
    }

    private function status($row)
    {
        return ['id' => $row['id'], 'received' => (int)$row['received'], 'complete' => (int)$row['complete'] === 1];
    }
}
