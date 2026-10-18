<?php

namespace Kanboard\Plugin\FamilyHub\Model;

/** Voluntarily disclosed report bytes, isolated from ordinary encrypted blobs. */
class NativeCryptoModerationDisclosureV2 extends NativeDatabase
{
    protected $cryptoAccess = true;
    public const MAX_SIZE = 2097152;
    public const CHUNK = 196608;

    private function own($id, $actor, $live = true)
    {
        $row = $this->one('SELECT * FROM familyhub_crypto_moderation_stages_v2 WHERE id=? AND account_id=?', [$this->uuid($id),$actor['user']['account_id']]);
        if (!$row) {
            throw new NativeError('permission_revoked', 403);
        }
        if ($live && !(int)$row['included'] && (int)$row['expires_at'] <= time()) {
            throw new NativeError('crypto_report_stage_expired', 409);
        }
        return $row;
    }

    private function wire($row)
    {
        return ['stageId' => $row['id'],'reportId' => $row['report_id'],'size' => (int)$row['size'],
            'received' => (int)$row['received'],'sha256' => $row['sha256'],
            'complete' => (bool)$row['complete'],'expiresAtEpoch' => (int)$row['expires_at']];
    }

    public function status($payload, $actor)
    {
        $this->fields($payload, ['stageId']);
        return $this->wire($this->own($payload['stageId'], $actor, false));
    }

    public function replayAccess($operation, $payload, $actor)
    {
        if ($operation === 'crypto2.moderation.disclosure.begin') {
            (new NativeCryptoModerationV2($this->container, $this->bearer, $this->ip))->replayAccess($payload, $actor);
            return;
        }
        $row = $this->own($payload['stageId'] ?? null, $actor, false);
        if ($operation !== 'crypto2.moderation.disclosure.abort') {
            (new NativeCryptoModerationV2($this->container, $this->bearer, $this->ip))->replayAccess(
                ['sourceContext' => json_decode($row['source_context'], true, 34, JSON_THROW_ON_ERROR)], $actor
            );
        }
    }

    public function write($operation, $payload, $actor, $proof)
    {
        $moderation = new NativeCryptoModerationV2($this->container, $this->bearer, $this->ip);
        if ($operation === 'crypto2.moderation.disclosure.begin') {
            $this->fields($payload, ['stageId','reportId','sourceContext','authorDirectoryHeadHash','consentVersion','kind','mime','size','sha256']);
            $id = $this->uuid($payload['stageId']);
            $reportId = $this->uuid($payload['reportId']);
            $source = $moderation->currentSource($payload['sourceContext'], $actor);
            (new NativeCryptoScopeV2($this->container))->currentAuthorReference($payload['authorDirectoryHeadHash'], $actor);
            if ($payload['consentVersion'] !== 1 ||
                !in_array($payload['kind'], ['snapshot','asset'], true) ||
                !is_int($payload['size']) || $payload['size'] < 1 || $payload['size'] > self::MAX_SIZE ||
                !is_string($payload['sha256']) || !preg_match('/^[a-f0-9]{64}$/D', $payload['sha256']) ||
                ($payload['kind'] === 'snapshot' ? $payload['mime'] !== 'application/json' :
                    (!in_array($payload['mime'], ['image/jpeg','image/png'], true) || $source['type'] !== 'idea'))) {
                throw new NativeError('validation_error');
            }
            if ($this->one('SELECT id FROM familyhub_crypto_moderation_stages_v2 WHERE id=?', [$id])) {
                throw new NativeError('idempotency_mismatch', 409);
            }
            $quota = $this->one('SELECT COUNT(*) AS objects,COALESCE(SUM(size),0) AS bytes FROM familyhub_crypto_moderation_stages_v2 WHERE account_id=? AND included=0 AND (expires_at>? OR received>0 OR complete=1)', [$actor['user']['account_id'],time()]);
            if ((int)$quota['objects'] >= 64 || (int)$quota['bytes'] + $payload['size'] > 67108864) {
                throw new NativeError('crypto_report_staging_limit', 413);
            }
            $this->change('INSERT INTO familyhub_crypto_moderation_stages_v2(id,report_id,account_id,source_context,kind,mime,size,sha256,expires_at,authorization) VALUES(?,?,?,?,?,?,?,?,?,?)', [
                $id,$reportId,$actor['user']['account_id'],NativeCryptoCodec::canonical((object)$source),
                $payload['kind'],$payload['mime'],$payload['size'],$payload['sha256'],time() + 1800,json_encode($proof, JSON_THROW_ON_ERROR),
            ]);
            return $this->wire($this->own($id, $actor));
        }
        $this->fields($payload, $operation === 'crypto2.moderation.disclosure.chunk' ? ['stageId','offset','dataBase64'] : ['stageId']);
        $row = $this->own($payload['stageId'], $actor, $operation !== 'crypto2.moderation.disclosure.abort');
        if ($operation === 'crypto2.moderation.disclosure.abort') {
            if ((int)$row['included']) {
                throw new NativeError('crypto_report_evidence_retained', 409);
            }
            $this->change('DELETE FROM familyhub_crypto_moderation_chunks_v2 WHERE stage_id=?', [$row['id']]);
            // Keep the original authorization/size/hash tombstone for retries.
            $this->change('UPDATE familyhub_crypto_moderation_stages_v2 SET expires_at=0,received=0,complete=0 WHERE id=?', [$row['id']]);
            return ['stageId' => $row['id'],'state' => 'aborted'];
        }
        if ((int)$row['included']) {
            throw new NativeError('crypto_report_evidence_retained', 409);
        }
        $moderation->currentSource(json_decode($row['source_context'], true, 34, JSON_THROW_ON_ERROR), $actor);
        if ($operation === 'crypto2.moderation.disclosure.chunk') {
            $offset = $payload['offset'];
            $bytes = is_string($payload['dataBase64']) ? base64_decode($payload['dataBase64'], true) : false;
            if (!is_int($offset) || $offset < 0 || $bytes === false ||
                base64_encode($bytes) !== $payload['dataBase64'] || strlen($bytes) < 1 ||
                strlen($bytes) > self::CHUNK || $offset + strlen($bytes) > (int)$row['size']) {
                throw new NativeError('validation_error');
            }
            $old = $this->one('SELECT data FROM familyhub_crypto_moderation_chunks_v2 WHERE stage_id=? AND chunk_offset=?', [$row['id'],$offset]);
            if ($old) {
                if ($old['data'] !== $payload['dataBase64']) {
                    throw new NativeError('idempotency_mismatch', 409);
                }
                return $this->wire($row);
            }
            if ((int)$row['complete'] || $offset !== (int)$row['received'] ||
                strlen($bytes) !== min(self::CHUNK, (int)$row['size'] - $offset)) {
                throw new NativeError('crypto_report_chunk_conflict', 409);
            }
            $this->change('INSERT INTO familyhub_crypto_moderation_chunks_v2 VALUES(?,?,?)', [$row['id'],$offset,$payload['dataBase64']]);
            $this->change('UPDATE familyhub_crypto_moderation_stages_v2 SET received=received+? WHERE id=?', [strlen($bytes),$row['id']]);
            return $this->wire($this->own($row['id'], $actor));
        }
        if ($operation !== 'crypto2.moderation.disclosure.complete') {
            throw new NativeError('unsupported_operation', 404);
        }
        if ((int)$row['received'] !== (int)$row['size']) {
            throw new NativeError('crypto_report_disclosure_incomplete', 409);
        }
        $bytes = $this->bytes($row);
        if ($row['kind'] === 'snapshot') {
            $this->snapshot($row, $bytes);
        } else {
            $this->assetDescriptor($row, $bytes);
        }
        $this->change('UPDATE familyhub_crypto_moderation_stages_v2 SET complete=1 WHERE id=?', [$row['id']]);
        return $this->wire($this->own($row['id'], $actor));
    }

    public function forReport($id, $reportId, $source, $actor, $kind)
    {
        $row = $this->own($id, $actor);
        if ($row['report_id'] !== $reportId || $row['kind'] !== $kind || !(int)$row['complete'] ||
            (int)$row['included'] || $row['source_context'] !== NativeCryptoCodec::canonical((object)$source)) {
            throw new NativeError('crypto_report_disclosure_incomplete', 409);
        }
        return $row;
    }

    public function bytes($row)
    {
        $out = '';
        foreach ($this->iterate('SELECT chunk_offset,data FROM familyhub_crypto_moderation_chunks_v2 WHERE stage_id=? ORDER BY chunk_offset', [$row['id']]) as $chunk) {
            $bytes = base64_decode($chunk['data'], true);
            if ($bytes === false || (int)$chunk['chunk_offset'] !== strlen($out)) {
                throw new NativeError('crypto_report_disclosure_incomplete', 409);
            }
            $out .= $bytes;
            if (strlen($out) > self::MAX_SIZE) {
                throw new NativeError('crypto_report_disclosure_incomplete', 409);
            }
        }
        if (strlen($out) !== (int)$row['size'] || !hash_equals($row['sha256'], hash('sha256', $out))) {
            throw new NativeError('crypto_report_disclosure_incomplete', 409);
        }
        return $out;
    }

    public function assetDescriptor($row, $bytes = null)
    {
        $bytes = $bytes ?? $this->bytes($row);
        $image = @getimagesizefromstring($bytes);
        if (!$image || !in_array($image['mime'] ?? null, ['image/jpeg','image/png'], true) ||
            $image['mime'] !== $row['mime'] || $image[0] < 1 || $image[0] > 4096 || $image[1] < 1 || $image[1] > 4096) {
            throw new NativeError('validation_error');
        }
        $descriptor = ['sha256' => $row['sha256'],'mime' => $row['mime'],'size' => (int)$row['size'],'width' => $image[0],'height' => $image[1]];
        (new NativeIdeaAssetService($this->container))->validateDisclosureBytes($bytes, $descriptor);
        return $descriptor;
    }

    public function snapshot($row, $bytes = null)
    {
        try {
            $snapshot = json_decode($bytes ?? $this->bytes($row), true, 34, JSON_THROW_ON_ERROR);
        } catch (\JsonException $error) {
            throw new NativeError('validation_error');
        }
        if (!is_array($snapshot)) {
            throw new NativeError('validation_error');
        }
        return $snapshot;
    }

    /** Called only inside the existing maintenance lease/global SQL boundary. */
    public function purgeInTransaction($accountId = null)
    {
        $service = new NativeCryptoV2Service($this->container);
        $count = 0;
        $filter = $accountId === null ? '' : ' AND p.account_id=?';
        $parameters = ['{"format":"moderationReceiptDigest2"%'];
        if ($accountId !== null) { $parameters[] = $this->uuid($accountId); }
        $proofs = $this->many('SELECT p.* FROM familyhub_crypto_moderation_reports_v2 p JOIN familyhub_moderation_reports r ON r.id=p.report_id WHERE r.redacted_at IS NOT NULL AND p.authorization NOT LIKE ?'.$filter.' ORDER BY p.report_id LIMIT 100', $parameters);
        foreach ($proofs as $row) {
            $proof = json_decode($row['authorization'], true, 34, JSON_THROW_ON_ERROR);
            [$command] = NativeCryptoCodec::decode($proof);
            $card = json_encode($service->moderationRetentionCard($proof), JSON_THROW_ON_ERROR);
            $this->change('UPDATE familyhub_crypto_moderation_reports_v2 SET authorization=? WHERE report_id=?', [$card,$row['report_id']]);
            // Covers earlier unadvertised source receipts too, without changing
            // their original digest, signature, status or minimal response.
            $this->change('UPDATE familyhub_crypto_receipts SET authorization=? WHERE account_id=? AND request_id=?', [$card,$row['account_id'],$command['requestId']]);
            $count++;
        }
        $parameters = [time()];
        $filter = '';
        if ($accountId !== null) { $filter = ' AND s.account_id=?'; $parameters[] = $accountId; }
        $stages = $this->many('SELECT s.* FROM familyhub_crypto_moderation_stages_v2 s LEFT JOIN familyhub_moderation_reports r ON r.id=s.report_id WHERE ((s.included=0 AND s.expires_at<=?) OR (s.included=1 AND r.redacted_at IS NOT NULL)) AND (s.received>0 OR s.complete=1)'.$filter.' ORDER BY s.id LIMIT 100', $parameters);
        foreach ($stages as $row) {
            $proof = json_decode($row['authorization'], true, 34, JSON_THROW_ON_ERROR);
            $card = ($proof['format'] ?? null) === 'moderationReceiptDigest2' ? $proof : $service->moderationRetentionCard($proof);
            $this->change('DELETE FROM familyhub_crypto_moderation_chunks_v2 WHERE stage_id=?', [$row['id']]);
            $this->change('UPDATE familyhub_crypto_moderation_stages_v2 SET received=0,complete=0,authorization=? WHERE id=?', [json_encode($card, JSON_THROW_ON_ERROR),$row['id']]);
            $count++;
        }
        return $count;
    }
}
