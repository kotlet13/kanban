<?php

namespace Kanboard\Plugin\FamilyHub\Model;

/** Administrator transport availability, never a client-authored state change. */
class NativeCryptoModerationAvailabilityV2 extends NativeDatabase
{
    protected $cryptoAccess = true;

    private function notice($row)
    {
        return ['scopeId' => $row['scope_id'],'id' => $row['record_id'],'domain' => 'content',
            'revision' => (int)$row['revision'],'recordProofHash' => $row['record_proof_hash'],
            'reportId' => $row['report_id'],'createdAtEpoch' => (int)$row['created_at'],'reason' => 'moderation'];
    }

    public function restriction($scopeId, $id, $revision, $proofHash = null)
    {
        $row = $this->one("SELECT * FROM familyhub_crypto_moderation_restrictions_v2 WHERE scope_id=? AND record_id=? AND revision=? AND state='active'", [$scopeId,$id,$revision]);
        return $row && ($proofHash === null || $row['record_proof_hash'] === $proofHash) ? $this->notice($row) : null;
    }

    /** Immutable failed receipts may contain a formerly visible conflict wire. */
    public function assertReceipt($receipt)
    {
        if ((int)$receipt['status'] === 200) {
            return;
        }
        $response = json_decode($receipt['response'],true,34,JSON_THROW_ON_ERROR);
        $remote = $response['details']['remote'] ?? null;
        if (is_array($remote) && isset($remote['scopeId'],$remote['id'],$remote['revision'])) {
            $notice = $this->restriction($remote['scopeId'],$remote['id'],$remote['revision']);
            if ($notice) {
                throw new NativeError('crypto_content_restricted',403,['unavailable'=>[$notice]]);
            }
        }
    }

    /** Called by the already authorized web-admin review under its SQL lock. */
    public function removeContent($report, $revision)
    {
        if (!in_array($report['target_type'], ['record','table','attachment'], true)) {
            throw new NativeError('financial_history_preserved', 403);
        }
        $context = $this->one('SELECT source_context FROM familyhub_crypto_moderation_reports_v2 WHERE report_id=?', [$report['id']]);
        $source = $context ? json_decode($context['source_context'], true, 34, JSON_THROW_ON_ERROR) : null;
        $record = $this->one('SELECT * FROM familyhub_crypto_records WHERE scope_id=? AND id=?', [$report['scope_id'],$report['target_id']]);
        if (!$source || $source['domain'] !== 'content' || !$record || (int)$record['deleted'] ||
            (int)$record['revision'] !== $revision || (int)$report['target_revision'] !== $revision) {
            throw new NativeError('report_preview_changed', 409);
        }
        $proof = json_decode($record['authorization'], true, 34, JSON_THROW_ON_ERROR)['recordProof'] ?? null;
        if (!$proof || NativeCryptoV2Codec::hash((object)$proof) !== $source['recordProofHash']) {
            throw new NativeError('report_preview_changed', 409);
        }
        $insert = $this->sqlite ? 'INSERT OR IGNORE' : 'INSERT IGNORE';
        $this->change($insert." INTO familyhub_crypto_moderation_restrictions_v2(scope_id,record_id,revision,record_proof_hash,report_id,created_at,state) VALUES(?,?,?,?,?,?,'active')", [$report['scope_id'],$record['id'],$revision,$source['recordProofHash'],$report['id'],time()]);
        $this->captureEvidence($report['scope_id'], $record['id'], $revision, $source['recordProofHash']);
        $metadata = json_decode($record['metadata'], true, 34, JSON_THROW_ON_ERROR);
        foreach ($metadata['blobIds'] as $id) {
            $this->change($insert.' INTO familyhub_crypto_moderation_blob_refs_v2 VALUES(?,?,?,?)', [$report['scope_id'],$id,$record['id'],$revision]);
        }
        (new NativeNotificationWriter($this->container))->configurationForScope($report['scope_id'],$record['id']);
        $this->change("UPDATE familyhub_crypto_reminders_v2 SET state='cancelled',revision=revision+1 WHERE scope_id=? AND target_id=? AND state='pending'",[$report['scope_id'],$record['id']]);
        // Leave record/history, revision floors, DEKs, ownership and membership
        // untouched. An availability notice is not a signed logical tombstone.
    }

    /** Exact proofs already referenced before restriction; no timestamp trust. */
    private function captureEvidence($scopeId, $id, $revision, $proofHash)
    {
        $afterScope = '';
        $afterId = '';
        $insert = $this->sqlite ? 'INSERT OR IGNORE' : 'INSERT IGNORE';
        do {
            $page = $this->many('SELECT scope_id,id,revision,metadata,authorization FROM familyhub_crypto_records WHERE deleted=0 AND (scope_id>? OR (scope_id=? AND id>?)) ORDER BY scope_id,id LIMIT 20', [$afterScope,$afterScope,$afterId]);
            foreach ($page as $source) {
                $afterScope = $source['scope_id'];
                $afterId = $source['id'];
                $metadata = json_decode($source['metadata'], true, 34, JSON_THROW_ON_ERROR);
                foreach ($metadata['referenceVersions'] ?? [] as $reference) {
                    if ($reference['scopeId'] !== $scopeId || $reference['id'] !== $id || $reference['domain'] !== 'content' || $reference['revision'] !== $revision || $reference['recordProofHash'] !== $proofHash) {
                        continue;
                    }
                    $authorization = json_decode($source['authorization'], true, 34, JSON_THROW_ON_ERROR);
                    if (isset($authorization['recordProof'])) {
                        $sourceHash = NativeCryptoV2Codec::hash((object)$authorization['recordProof']);
                        $this->change($insert.' INTO familyhub_crypto_moderation_evidence_v2 VALUES(?,?,?,?,?,?,?)', [$scopeId,$id,$revision,$source['scope_id'],$source['id'],(int)$source['revision'],$sourceHash]);
                    }
                }
            }
        } while (count($page) === 20);
    }

    /** Only verification evidence for one exact, still-current preexisting source. */
    public function evidence($target, $source, $actor)
    {
        if (!is_array($source)) {
            throw new NativeError('validation_error');
        }
        $this->fields($source, ['scopeId','id','revision','recordProofHash']);
        $sid = $this->uuid($source['scopeId']);
        $id = NativeCryptoRecordAddressV2::wireId($source['id']);
        if (!is_int($source['revision']) || $source['revision'] < 1 || !is_string($source['recordProofHash']) || !preg_match('/^[a-f0-9]{64}$/D', $source['recordProofHash'])) {
            throw new NativeError('validation_error');
        }
        $row = $this->one('SELECT * FROM familyhub_crypto_records WHERE scope_id=? AND id=? AND revision=?', [$sid,$id,$source['revision']]);
        $indexed = $this->one('SELECT source_proof_hash FROM familyhub_crypto_moderation_evidence_v2 WHERE scope_id=? AND record_id=? AND revision=? AND source_scope_id=? AND source_id=? AND source_revision=?', [$target['scope_id'],$target['id'],(int)$target['revision'],$sid,$id,$source['revision']]);
        $descendant = $sid === $target['scope_id'] && $id === $target['id'] && $source['revision'] > (int)$target['revision'];
        if (!$row || (!$descendant && ((int)$row['deleted'] || !$indexed || $indexed['source_proof_hash'] !== $source['recordProofHash'])) || $this->restriction($sid,$id,$source['revision'])) {
            throw new NativeError('crypto_verification_evidence_denied', 403);
        }
        $authorization = json_decode($row['authorization'], true, 34, JSON_THROW_ON_ERROR);
        if (!isset($authorization['recordProof']) || NativeCryptoV2Codec::hash((object)$authorization['recordProof']) !== $source['recordProofHash']) {
            throw new NativeError('crypto_verification_evidence_denied', 403);
        }
        $scopes = new NativeCryptoScopeV2($this->container, $this->bearer, $this->ip);
        $scope = $this->scope($sid, $actor['user']['id']);
        $head = $scopes->current($sid);
        if (!$head) {
            throw new NativeError('crypto_scope_head_missing', 404);
        }
        $domain = (new NativeCryptoRecordProofV2($this->container))->domain($row['type']);
        $scopes->author($sid,$head['head_hash'],(int)$head['epoch'],(int)$scope['effective_access_revision'],$actor,$domain,false);
        if ($descendant) {
            // A corrected current revision still needs its exact signed chain.
            // This grants verification bytes only, never display of the blocked fact.
            $expected = $source['recordProofHash'];
            $revision = $source['revision'];
            while ($revision > (int)$target['revision']) {
                $page = $this->many('SELECT revision,record_proof_hash,record_proof FROM familyhub_crypto_record_history WHERE scope_id=? AND id=? AND domain=? AND revision<=? AND revision>? ORDER BY revision DESC LIMIT 20',[$sid,$id,$domain,$revision,(int)$target['revision']]);
                if (!$page) {
                    throw new NativeError('crypto_verification_evidence_denied',403);
                }
                foreach ($page as $link) {
                    if ((int)$link['revision'] !== $revision || $link['record_proof_hash'] !== $expected) {
                        throw new NativeError('crypto_verification_evidence_denied',403);
                    }
                    [$body] = NativeCryptoCodec::decode(json_decode($link['record_proof'],true,34,JSON_THROW_ON_ERROR));
                    $expected = $body['previousRecordHash'];
                    $revision--;
                }
            }
            if ($expected === $target['record_proof_hash']) {
                return;
            }
            throw new NativeError('crypto_verification_evidence_denied',403);
        }
        $metadata = json_decode($row['metadata'], true, 34, JSON_THROW_ON_ERROR);
        foreach ($metadata['referenceVersions'] ?? [] as $reference) {
            if ($reference['scopeId'] === $target['scope_id'] && $reference['id'] === $target['id'] && $reference['domain'] === $target['domain'] && $reference['revision'] === (int)$target['revision'] && $reference['recordProofHash'] === $target['record_proof_hash']) {
                return;
            }
        }
        throw new NativeError('crypto_verification_evidence_denied', 403);
    }

    public function assertBlob($scopeId, $id, $domain, $payload = null, $actor = null)
    {
        $blocked = $this->one("SELECT r.* FROM familyhub_crypto_moderation_blob_refs_v2 b JOIN familyhub_crypto_moderation_restrictions_v2 r ON r.scope_id=b.scope_id AND r.record_id=b.record_id AND r.revision=b.record_revision WHERE b.scope_id=? AND b.blob_id=? AND r.state='active' LIMIT 1", [$scopeId,$id]);
        if (!$blocked) {
            return;
        }
        $after = '';
        do {
            $page = $this->many('SELECT id,type,revision,metadata FROM familyhub_crypto_records WHERE scope_id=? AND deleted=0 AND id>? ORDER BY id LIMIT 20', [$scopeId,$after]);
            foreach ($page as $record) {
                $after = $record['id'];
                $metadata = json_decode($record['metadata'], true, 34, JSON_THROW_ON_ERROR);
                if ((new NativeCryptoRecordProofV2($this->container))->domain($record['type']) === $domain && in_array($id, $metadata['blobIds'], true) && !$this->restriction($scopeId, $record['id'], (int)$record['revision'])) {
                    return;
                }
            }
        } while (count($page) === 20);
        if (isset($payload['evidenceFor'],$payload['evidenceRecord']) && $actor) {
            $requested = $payload['evidenceRecord'];
            if (!is_array($requested)) {
                throw new NativeError('validation_error');
            }
            $this->fields($requested,['id','revision','recordProofHash']);
            $recordId = NativeCryptoRecordAddressV2::wireId($requested['id']);
            if (!is_int($requested['revision']) || $requested['revision'] < 1 || !is_string($requested['recordProofHash']) || !preg_match('/^[a-f0-9]{64}$/D',$requested['recordProofHash'])) {
                throw new NativeError('validation_error');
            }
            $target = $this->one('SELECT * FROM familyhub_crypto_record_history WHERE scope_id=? AND id=? AND revision=? AND domain=? AND record_proof_hash=?',[$scopeId,$recordId,$requested['revision'],$domain,$requested['recordProofHash']]);
            if ($target && $this->restriction($scopeId,$recordId,$requested['revision'],$requested['recordProofHash'])) {
                $proof = json_decode($target['record_proof'],true,34,JSON_THROW_ON_ERROR);
                [$body] = NativeCryptoCodec::decode($proof);
                if (in_array($id,$body['metadata']['blobIds'],true)) {
                    $this->evidence($target,$payload['evidenceFor'],$actor);
                    return $this->restriction($scopeId,$recordId,$requested['revision'],$requested['recordProofHash']);
                }
            }
            throw new NativeError('crypto_verification_evidence_denied',403);
        }
        throw new NativeError('crypto_content_restricted', 403, ['unavailable' => [$this->notice($blocked)]]);
    }
}
