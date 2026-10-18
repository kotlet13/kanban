<?php

namespace Kanboard\Plugin\FamilyHub\Model;

/** Signer-observed inventory attestations; never a proof of an unseen remote history's freshness. */
class NativeCryptoCheckpointV2 extends NativeDatabase
{
    protected $cryptoAccess = true;

    public function write($p, $actor, $proof)
    {
        $this->fields($p, ['scopeId', 'domain', 'epoch', 'membershipHeadHash', 'accessRevision', 'authorDirectoryHeadHash', 'expectedSequence', 'recordCount', 'manifestHash', 'historyBasis']);
        if (!in_array($p['historyBasis'], ['verifiedCheckpoint', 'reviewedRecoveryBaseline'], true) || !is_int($p['expectedSequence']) || $p['expectedSequence'] < 0 || !is_int($p['recordCount']) || $p['recordCount'] < 0 || !is_string($p['manifestHash']) || !preg_match('/^[a-f0-9]{64}$/D', $p['manifestHash'])) {
            throw new NativeError('validation_error');
        }
        $scopes = new NativeCryptoScopeV2($this->container, $this->bearer, $this->ip);
        $scopes->author($p['scopeId'], $p['membershipHeadHash'], $p['epoch'], $p['accessRevision'], $actor, $p['domain'], false);
        $scopes->currentAuthorReference($p['authorDirectoryHeadHash'], $actor);
        $sequence = $scopes->domainSequence($p['scopeId'], $p['domain']);
        if ($sequence !== $p['expectedSequence']) {
            throw new NativeError('crypto_checkpoint_changed', 409);
        }
        $hash = hash_init('sha256');
        $count = 0;
        foreach ($scopes->manifestRows($p['scopeId'], $p['domain']) as $descriptor) {
            hash_update($hash, NativeCryptoCodec::canonical((object)$descriptor)."\n");
            $count++;
        }
        if ($p['recordCount'] !== $count || !hash_equals(hash_final($hash), $p['manifestHash'])) {
            throw new NativeError('crypto_checkpoint_changed', 409);
        }
        $where = [$p['scopeId'], $p['domain'], $p['membershipHeadHash'], $sequence];
        $old = $this->one('SELECT * FROM familyhub_crypto_domain_checkpoints WHERE scope_id=? AND domain=? AND head_hash=? AND sequence=?', $where);
        if ($old && ($old['manifest_hash'] !== $p['manifestHash'] || (int)$old['record_count'] !== $count)) {
            throw new NativeError('crypto_checkpoint_immutable', 409);
        }
        if (!$old) {
            $this->change('INSERT INTO familyhub_crypto_domain_checkpoints VALUES(?,?,?,?,?,?)', array_merge($where, [$p['manifestHash'], $count]));
        }
        $proofHash = NativeCryptoV2Codec::hash((object)$proof);
        if (!$this->one('SELECT proof_hash FROM familyhub_crypto_domain_attestations WHERE scope_id=? AND domain=? AND head_hash=? AND sequence=? AND proof_hash=?', array_merge($where, [$proofHash]))) {
            $this->change('INSERT INTO familyhub_crypto_domain_attestations VALUES(?,?,?,?,?,?,?,?)', array_merge($where, [$proofHash, $actor['user']['account_id'], $actor['device']['id'], json_encode($proof, JSON_THROW_ON_ERROR)]));
        }
        return ['scopeId' => $p['scopeId'], 'domain' => $p['domain'], 'membershipHeadHash' => $p['membershipHeadHash'], 'sequence' => $sequence, 'recordCount' => $count, 'manifestHash' => $p['manifestHash'], 'proofHash' => $proofHash];
    }

    public function read($op, $p, $actor)
    {
        $optional = $op === 'crypto2.domain.inventory' ? ['afterId', 'limit', 'afterProofHash', 'checkpoint'] : ['membershipHeadHash', 'sequence', 'afterProofHash', 'limit'];
        $this->fields($p, ['scopeId', 'domain', 'accessRevision'], $optional);
        $sid = $this->uuid($p['scopeId']);
        $scopes = new NativeCryptoScopeV2($this->container, $this->bearer, $this->ip);
        $head = $scopes->current($sid);
        if (!$head) {
            throw new NativeError('crypto_scope_head_missing', 404);
        }
        $scopes->author($sid, $head['head_hash'], (int)$head['epoch'], $p['accessRevision'], $actor, $p['domain'], false);
        $sequence = $scopes->domainSequence($sid, $p['domain']);
        $limit = $p['limit'] ?? 50;
        if (!is_int($limit) || $limit < 1 || $limit > 50) {
            throw new NativeError('invalid_cursor');
        }
        $checkpointHead = $p['membershipHeadHash'] ?? $head['head_hash'];
        $checkpointSequence = $p['sequence'] ?? $sequence;
        if (!is_string($checkpointHead) || !preg_match('/^[a-f0-9]{64}$/D', $checkpointHead) || !is_int($checkpointSequence) || $checkpointSequence < 0) {
            throw new NativeError('invalid_cursor');
        }
        $snapshot = null;
        if (isset($p['checkpoint'])) {
            $snapshot = $this->selectedCheckpoint($sid, $p['domain'], $p['checkpoint'], $head);
            $checkpointHead = $snapshot['membershipHeadHash'];
            $checkpointSequence = $snapshot['sequence'];
        }
        $checkpoint = $this->checkpoint($sid, $p['domain'], $checkpointHead, $checkpointSequence, $p['afterProofHash'] ?? '');
        $out = ['scopeId' => $sid, 'domain' => $p['domain'],
            'scopeSequence' => $snapshot === null ? $sequence : $checkpointSequence,
            'epoch' => $snapshot === null ? (int)$head['epoch'] : $snapshot['epoch'],
            'membershipHeadHash' => $snapshot === null ? $head['head_hash'] : $checkpointHead,
            'checkpoint' => $checkpoint];
        if ($op === 'crypto2.domain.checkpoints') {
            return $out;
        }
        $after = isset($p['afterId']) ? NativeCryptoRecordAddressV2::wireId($p['afterId']) : '';
        if ($snapshot !== null) {
            $rows = $this->many('SELECT h.id,h.revision,h.record_proof_hash,h.sequence,h.epoch FROM familyhub_crypto_record_history h WHERE h.scope_id=? AND h.domain=? AND h.sequence<=? AND h.id>? AND NOT EXISTS (SELECT 1 FROM familyhub_crypto_record_history newer WHERE newer.scope_id=h.scope_id AND newer.domain=h.domain AND newer.id=h.id AND newer.sequence<=? AND newer.revision>h.revision) ORDER BY h.id LIMIT '.($limit + 1),
                [$sid, $p['domain'], $checkpointSequence, $after, $checkpointSequence]);
            $page = [];
            foreach (array_slice($rows, 0, $limit) as $row) {
                $page[] = ['id' => $row['id'], 'revision' => (int)$row['revision'],
                    'recordProofHash' => $row['record_proof_hash'], 'sequence' => (int)$row['sequence'],
                    'recordEpoch' => (int)$row['epoch']];
            }
            return $out + ['descriptors' => $page, 'hasMore' => count($rows) > $limit,
                'nextAfterId' => $page ? end($page)['id'] : null];
        }
        $page = [];
        $more = false;
        foreach ($scopes->manifestRows($sid, $p['domain']) as $descriptor) {
            if (strcmp($descriptor['id'], $after) <= 0) {
                continue;
            }
            if (count($page) === $limit) {
                $more = true;
                break;
            }
            $page[] = $descriptor;
        }
        return $out + ['descriptors' => $page, 'hasMore' => $more, 'nextAfterId' => $page ? end($page)['id'] : null];
    }

    /** An observed historical snapshot selector is not a statement of latestness. */
    private function selectedCheckpoint($sid, $domain, $selector, $current)
    {
        if (!is_array($selector)) {
            throw new NativeError('invalid_cursor');
        }
        $this->fields($selector, ['membershipHeadHash', 'sequence', 'manifestHash', 'recordCount', 'proofHash']);
        foreach (['membershipHeadHash', 'manifestHash', 'proofHash'] as $field) {
            if (!is_string($selector[$field]) || !preg_match('/^[a-f0-9]{64}$/D', $selector[$field])) {
                throw new NativeError('invalid_cursor');
            }
        }
        foreach (['sequence', 'recordCount'] as $field) {
            if (!is_int($selector[$field]) || $selector[$field] < 0 || $selector[$field] > 9007199254740991) {
                throw new NativeError('invalid_cursor');
            }
        }
        $where = [$sid, $domain, $selector['membershipHeadHash'], $selector['sequence']];
        $checkpoint = $this->one('SELECT * FROM familyhub_crypto_domain_checkpoints WHERE scope_id=? AND domain=? AND head_hash=? AND sequence=?', $where);
        $attestation = $this->one('SELECT authorization FROM familyhub_crypto_domain_attestations WHERE scope_id=? AND domain=? AND head_hash=? AND sequence=? AND proof_hash=?', array_merge($where, [$selector['proofHash']]));
        $head = (new NativeCryptoScopeV2($this->container))->head($sid, $selector['membershipHeadHash']);
        if (!$checkpoint || !$attestation || !$head ||
            !in_array($head['state'], ['active', 'historical'], true) || (int)$head['epoch'] > (int)$current['epoch'] ||
            $checkpoint['manifest_hash'] !== $selector['manifestHash'] ||
            (int)$checkpoint['record_count'] !== $selector['recordCount']) {
            throw new NativeError('crypto_checkpoint_unavailable', 409);
        }
        $proof = json_decode($attestation['authorization'], true, 34, JSON_THROW_ON_ERROR);
        [$command] = NativeCryptoCodec::decode($proof);
        $payload = $command['payload'];
        if (NativeCryptoV2Codec::hash((object)$proof) !== $selector['proofHash'] ||
            $command['operation'] !== 'crypto2.domain.checkpoint' ||
            $payload['scopeId'] !== $sid || $payload['domain'] !== $domain ||
            $payload['membershipHeadHash'] !== $selector['membershipHeadHash'] ||
            $payload['expectedSequence'] !== $selector['sequence'] ||
            $payload['manifestHash'] !== $selector['manifestHash'] ||
            $payload['recordCount'] !== $selector['recordCount']) {
            throw new NativeError('crypto_checkpoint_proof_unavailable', 503);
        }
        return $selector + ['epoch' => (int)$head['epoch']];
    }

    private function checkpoint($sid, $domain, $headHash, $sequence, $after)
    {
        if (!is_string($after) || $after !== '' && !preg_match('/^[a-f0-9]{64}$/D', $after)) {
            throw new NativeError('invalid_cursor');
        }
        $where = [$sid, $domain, $headHash, $sequence];
        $row = $this->one('SELECT * FROM familyhub_crypto_domain_checkpoints WHERE scope_id=? AND domain=? AND head_hash=? AND sequence=?', $where);
        if (!$row) {
            return null;
        }
        $rows = $this->many('SELECT proof_hash,authorization FROM familyhub_crypto_domain_attestations WHERE scope_id=? AND domain=? AND head_hash=? AND sequence=? AND proof_hash>? ORDER BY proof_hash LIMIT 21', array_merge($where, [$after]));
        $proofs = [];
        $bytes = 0;
        foreach ($rows as $proof) {
            $authorization = json_decode($proof['authorization'], true, 34, JSON_THROW_ON_ERROR);
            $size = strlen($proof['authorization']);
            if (count($proofs) === 20 || $proofs && $bytes + $size > 786432) {
                break;
            }
            $proofs[] = ['proofHash' => $proof['proof_hash'], 'authorization' => $authorization];
            $bytes += $size;
        }
        return ['membershipHeadHash' => $headHash, 'domainSequence' => $sequence, 'manifestHash' => $row['manifest_hash'], 'recordCount' => (int)$row['record_count'], 'attestations' => $proofs, 'hasMore' => count($rows) > count($proofs), 'nextAfterProofHash' => $proofs ? end($proofs)['proofHash'] : null];
    }
}
