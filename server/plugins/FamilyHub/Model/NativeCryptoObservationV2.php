<?php

namespace Kanboard\Plugin\FamilyHub\Model;

/** Own-account recovery witnesses, authoritative only through exact log inclusion. */
class NativeCryptoObservationV2 extends NativeDatabase
{
    protected $cryptoAccess = true;
    public const MAX_BUNDLE = 131072;

    public function token($accountId, $scopeId)
    {
        return hash('sha256', "JivieScopeObservation/v2\n".NativeCryptoCodec::canonical((object)['serverId'=>$this->serverId(),'accountId'=>$accountId,'scopeId'=>$scopeId]));
    }

    private function digest($value)
    {
        if (!is_string($value) || !preg_match('/^[a-f0-9]{64}$/D', $value)) {
            throw new NativeError('validation_error');
        }
    }

    private function integer($value)
    {
        if (!is_int($value) || $value < 0 || $value > 9007199254740991) {
            throw new NativeError('validation_error');
        }
    }

    public function validate($bundle, $accountId)
    {
        if (!is_array($bundle)) {
            throw new NativeError('validation_error');
        }
        $this->fields($bundle, ['version','serverId','accountId','scopeId','headHash','proposalProofHash','activationProofHash','grantManifestHash','members','acceptanceProofHash','checkpoints','lifecycleHash']);
        if ($bundle['version'] !== 2 || $bundle['serverId'] !== $this->serverId() || $bundle['accountId'] !== $accountId) {
            throw new NativeError('crypto_identity_mismatch',403);
        }
        $this->uuid($bundle['scopeId']);
        foreach (['headHash','proposalProofHash','activationProofHash','grantManifestHash','lifecycleHash'] as $key) {
            $this->digest($bundle[$key]);
        }
        if ($bundle['acceptanceProofHash'] !== null) {
            $this->digest($bundle['acceptanceProofHash']);
        }
        if (!is_array($bundle['members']) || !array_is_list($bundle['members']) || !$bundle['members']) {
            throw new NativeError('validation_error');
        }
        $previous = '';
        foreach ($bundle['members'] as $member) {
            $this->fields($member, ['accountId','directoryHeadHash','deviceSnapshotHash','rootFingerprint']);
            $this->uuid($member['accountId']);
            $this->digest($member['directoryHeadHash']);
            $this->digest($member['deviceSnapshotHash']);
            NativeCryptoCodec::base64($member['rootFingerprint'],32,32);
            if (strcmp($member['accountId'],$previous) <= 0) {
                throw new NativeError('validation_error');
            }
            $previous = $member['accountId'];
        }
        if (!is_array($bundle['checkpoints']) || !array_is_list($bundle['checkpoints']) || count($bundle['checkpoints']) > 2) {
            throw new NativeError('validation_error');
        }
        $previous = '';
        foreach ($bundle['checkpoints'] as $checkpoint) {
            $this->fields($checkpoint, ['domain','membershipHeadHash','sequence','manifestHash','recordCount','proofHashes']);
            if (!in_array($checkpoint['domain'],['content','finance'],true) || strcmp($checkpoint['domain'],$previous) <= 0) {
                throw new NativeError('validation_error');
            }
            $previous = $checkpoint['domain'];
            $this->digest($checkpoint['membershipHeadHash']);
            $this->digest($checkpoint['manifestHash']);
            $this->integer($checkpoint['sequence']);
            $this->integer($checkpoint['recordCount']);
            if (!is_array($checkpoint['proofHashes']) || !array_is_list($checkpoint['proofHashes']) || !$checkpoint['proofHashes']) {
                throw new NativeError('validation_error');
            }
            $last = '';
            foreach ($checkpoint['proofHashes'] as $hash) {
                $this->digest($hash);
                if (strcmp($hash,$last) <= 0) {
                    throw new NativeError('validation_error');
                }
                $last = $hash;
            }
        }
        $bytes = NativeCryptoCodec::canonical((object)$bundle);
        if (strlen($bytes) > self::MAX_BUNDLE) {
            throw new NativeError('crypto_observation_too_large',413);
        }
        return [$bytes,hash('sha256',"JivieScopeObservationBundle/v2\n".$bytes)];
    }

    public function put($p, $actor)
    {
        $this->fields($p, ['observation']);
        $accountId = $actor['user']['account_id'];
        [$bytes,$hash] = $this->validate($p['observation'], $accountId);
        $old = $this->one('SELECT observation,included,expires_at FROM familyhub_crypto_scope_observations_v2 WHERE account_id=? AND observation_hash=?', [$accountId,$hash]);
        if ($old) {
            if ($old['observation'] !== $bytes) {
                throw new NativeError('crypto_observation_immutable',409);
            }
            if (!(int)$old['included'] && (int)$old['expires_at']<=time()) {
                $count=$this->one('SELECT COUNT(*) AS n FROM familyhub_crypto_scope_observations_v2 WHERE account_id=? AND included=0 AND expires_at>?',[$accountId,time()]);
                if ((int)$count['n']>=16) {
                    throw new NativeError('crypto_observation_candidates_full',409);
                }
                $expiry=time()+1800;
                $this->change('UPDATE familyhub_crypto_scope_observations_v2 SET created_at=?,expires_at=? WHERE account_id=? AND observation_hash=? AND included=0',[time(),$expiry,$accountId,$hash]);
                $old['expires_at']=$expiry;
            }
            return ['observationHash'=>$hash,'state'=>(int)$old['included'] ? 'included' : 'candidate','expiresAt'=>(int)$old['expires_at']];
        }
        // Only unauthoritative, expired candidates are garbage-collected.
        foreach ($this->many('SELECT observation_hash FROM familyhub_crypto_scope_observations_v2 WHERE account_id=? AND included=0 AND expires_at<=? ORDER BY observation_hash LIMIT 20', [$accountId,time()]) as $row) {
            $this->change('DELETE FROM familyhub_crypto_scope_observations_v2 WHERE account_id=? AND observation_hash=? AND included=0',[$accountId,$row['observation_hash']]);
        }
        $count = $this->one('SELECT COUNT(*) AS n FROM familyhub_crypto_scope_observations_v2 WHERE account_id=? AND included=0', [$accountId]);
        if ((int)$count['n'] >= 16) {
            throw new NativeError('crypto_observation_candidates_full',409);
        }
        $scopeId = $p['observation']['scopeId'];
        $this->change('INSERT INTO familyhub_crypto_scope_observations_v2 VALUES(?,?,?,?,?,?,?,?,0)', [$accountId,$hash,$this->token($accountId,$scopeId),$p['observation']['headHash'],$bytes,time(),time()+1800,$scopeId]);
        return ['observationHash'=>$hash,'state'=>'candidate','expiresAt'=>time()+1800];
    }

    /** Same transaction as the immutable signed directory event. */
    public function includeEvent($command, $generation)
    {
        $p = $command['payload'];
        $row = $this->one('SELECT * FROM familyhub_crypto_scope_observations_v2 WHERE account_id=? AND observation_hash=?', [$command['accountId'],$p['observationHash']]);
        if (!$row || !(int)$row['included'] && (int)$row['expires_at'] <= time() || $row['scope_token'] !== $p['scopeToken'] || $row['head_hash'] !== $p['headHash']) {
            throw new NativeError('crypto_observation_candidate_required',409);
        }
        [$bytes,$hash] = $this->validate(json_decode($row['observation'],true,34,JSON_THROW_ON_ERROR),$command['accountId']);
        if ($hash !== $p['observationHash'] || $bytes !== $row['observation']) {
            throw new NativeError('crypto_observation_immutable',409);
        }
        $commandHash = hash('sha256',NativeCryptoCodec::canonical((object)$command));
        $this->change('INSERT INTO familyhub_crypto_scope_observation_events_v2 VALUES(?,?,?,?)',[$command['accountId'],$generation,$commandHash,$hash]);
        $this->change('UPDATE familyhub_crypto_scope_observations_v2 SET included=1 WHERE account_id=? AND observation_hash=?',[$command['accountId'],$hash]);
    }

    public function read($p, $actor)
    {
        $this->fields($p, [], ['afterGeneration','limit']);
        $after = $p['afterGeneration'] ?? 0;
        $limit = $p['limit'] ?? 20;
        $this->integer($after);
        if (!is_int($limit) || $limit < 1 || $limit > 20) {
            throw new NativeError('validation_error');
        }
        $rows = $this->many('SELECT e.generation,e.command_hash,b.observation FROM familyhub_crypto_scope_observation_events_v2 e JOIN familyhub_crypto_scope_observations_v2 b ON b.account_id=e.account_id AND b.observation_hash=e.observation_hash AND b.included=1 WHERE e.account_id=? AND e.generation>? ORDER BY e.generation LIMIT '.($limit+1),[$actor['user']['account_id'],$after]);
        $out = [];
        $bytes = 0;
        foreach ($rows as $row) {
            $next = ['generation'=>(int)$row['generation'],'eventCommandHash'=>$row['command_hash'],'observation'=>json_decode($row['observation'],true,34,JSON_THROW_ON_ERROR)];
            $size = strlen(json_encode($next,JSON_THROW_ON_ERROR));
            if (count($out) >= $limit || $out && $bytes+$size > 1250000) {
                break;
            }
            $out[]=$next;
            $bytes+=$size;
        }
        return ['observations'=>$out,'hasMore'=>count($rows)>count($out),'nextGeneration'=>$out ? end($out)['generation'] : $after];
    }
}
