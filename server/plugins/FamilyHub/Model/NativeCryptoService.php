<?php

namespace Kanboard\Plugin\FamilyHub\Model;

/** Authenticated ciphertext transport, independent of legacy content contracts. */
class NativeCryptoService extends NativeDatabase
{
    protected $cryptoAccess = true;
    public static function enabled($pdo)
    {
        return defined('FAMILYHUB_ENABLE_CRYPTO_PREVIEW') && FAMILYHUB_ENABLE_CRYPTO_PREVIEW === true && NativeCryptoCodec::available() && \Kanboard\Plugin\FamilyHub\Schema\CryptoSchema::ready($pdo);
    }
    public function execute($operation, array $params)
    {
        if (!self::enabled($this->pdo)) {
            throw new NativeError('crypto_unavailable', 503);
        }
        $maintenanceLease = in_array($operation, ['crypto.migration.prepare','crypto.migration.fence','crypto.migration.verify','crypto.migration.inventory'], true) ? NativeCryptoMaintenanceLease::acquire(true) : null;
        $this->rate([['crypto-ip:'.$this->ip,600,60]]);
        $result = $this->transaction(function () use ($operation, $params) {
            $actor = $this->actor();
            $user = $actor['user'];
            $account = $user['account_id'];
            $identity = $this->one('SELECT * FROM familyhub_crypto_accounts WHERE account_id=?'.$this->lockSuffix(), [$account]);
            if ($operation === 'crypto.account.status') {
                $this->fields($params, []);
                return $this->status($identity, $account);
            }
            if ($operation === 'crypto.account.entries') {
                return $this->entries($params, $account, $identity);
            }
            if ($operation === 'crypto.receipt.get') {
                $this->fields($params, ['requestId','requestHash']);
                $id = $this->uuid($params['requestId']);
                $r = $this->one('SELECT * FROM familyhub_crypto_receipts WHERE account_id=? AND request_id=?', [$account,$id]);
                if (!$r) {
                    return ['requestId' => $id,'outcome' => 'unknown'];
                }if (!is_string($params['requestHash']) || !hash_equals($r['request_hash'], $params['requestHash'])) {
                    throw new NativeError('idempotency_mismatch', 409);
                }
                $proof = json_decode($r['authorization'], true, 34, JSON_THROW_ON_ERROR);
                [$savedCommand] = NativeCryptoCodec::decode($proof);
                $p = $savedCommand['payload'];
                if (isset($p['scopeId'])) {
                    $this->scope($this->uuid($p['scopeId']), $user['id']);
                }if (isset($p['scopeIds'])) {
                    foreach ($p['scopeIds'] as $sid) {
                        $this->scope($this->uuid($sid), $user['id']);
                    }
                }
                if ($savedCommand['operation'] === 'crypto.records.batch') {
                    (new NativeCryptoStorage($this->container, $this->bearer, $this->ip))->authorizeBatch($p, $actor);
                }
                return ['requestId' => $id,'requestHash' => $r['request_hash'],'status' => (int)$r['status'],'response' => json_decode($r['response'], true, 34, JSON_THROW_ON_ERROR),'authorization' => $proof];
            }
            if (in_array($operation, ['crypto.records.pull','crypto.blobs.get','crypto.grants.list','crypto.scope.status','crypto.migration.status','crypto.migration.inventory','crypto.legacy.lookup'], true)) {
                return (new NativeCryptoStorage($this->container, $this->bearer, $this->ip))->readInTransaction($operation, $params, $actor);
            }
            $email = $this->one('SELECT * FROM familyhub_email_identities WHERE account_id=? AND verified_at IS NOT NULL', [$account]);
            if (!$email) {
                throw new NativeError('email_verification_required', 403);
            }
            [$command,$bytes,$signature,$digest] = NativeCryptoCodec::decode($params);
            $this->fields($command, ['version','operation','requestId','serverId','accountId','deviceId','signer','payload']);
            if ($command['version'] !== 1 || $command['operation'] !== $operation || $command['serverId'] !== $this->serverId() || $command['accountId'] !== $account || $command['deviceId'] !== $actor['device']['id'] || !is_array($command['payload'])) {
                throw new NativeError('crypto_identity_mismatch', 403);
            }
            $request = $this->uuid($command['requestId']);
            $p = $command['payload'];
            $rootOperation = $command['signer'] === 'root';
            if (!in_array($command['signer'], ['root','device'], true) || in_array($operation, ['crypto.account.initialize','crypto.account.recoveryStart'], true) && !$rootOperation || $rootOperation && !in_array($operation, ['crypto.account.initialize','crypto.account.recoveryStart','crypto.device.add','crypto.device.revoke'], true)) {
                throw new NativeError('crypto_signer_forbidden', 403);
            }
            $device = $this->one('SELECT * FROM familyhub_crypto_devices WHERE account_id=? AND device_id=?', [$account,$actor['device']['id']]);
            if ($operation === 'crypto.account.initialize') {
                $key = $p['rootSigningKeyBase64'] ?? null;
            } elseif ($rootOperation) {
                if (!$identity) {
                    throw new NativeError('crypto_account_missing', 409);
                }$key = $identity['root_signing_key'];
            } else {
                if (!$identity || !$device || $device['revoked_at'] !== null) {
                    throw new NativeError('crypto_device_unapproved', 403);
                }$key = $device['signing_key'];
            }
            NativeCryptoCodec::verify($bytes, $signature, $key);
            if (in_array($operation, ['crypto.device.add','crypto.device.revoke'], true) && !$rootOperation && !(int)$device['manage_devices']) {
                throw new NativeError('crypto_device_management_forbidden', 403);
            }
            // Recheck object access before returning any cached response.
            if (isset($p['scopeId'])) {
                $this->scope($this->uuid($p['scopeId']), $user['id'], true);
            }
            if (isset($p['scopeIds'])) {
                if (!is_array($p['scopeIds']) || count($p['scopeIds']) > 100) {
                    throw new NativeError('validation_error');
                }foreach ($p['scopeIds'] as $scope) {
                    $this->scope($this->uuid($scope), $user['id'], true);
                }
            }
            if ($operation === 'crypto.records.batch') {
                (new NativeCryptoStorage($this->container, $this->bearer, $this->ip))->authorizeBatch($p, $actor);
            }
            $saved = $this->one('SELECT * FROM familyhub_crypto_receipts WHERE account_id=? AND request_id=?', [$account,$request]);
            if ($saved) {
                if (!hash_equals($saved['request_hash'], $digest)) {
                    throw new NativeError('idempotency_mismatch', 409);
                }$response = json_decode($saved['response'], true, 34, JSON_THROW_ON_ERROR);
                return (int)$saved['status'] === 200 ? $response : new NativeError($response['errorCode'], (int)$saved['status'], $response['details']);
            }
            NativeCryptoV2Boundary::guardV1($this->pdo, $account, $p);
            // A signed fresh recovery attempt consumes budget; exact receipt replay does not.
            if ($operation === 'crypto.account.recoveryStart') {
                $retry = $this->recoveryRate($account);
                if ($retry > 0) {
                    return new NativeError('rate_limited', 429, ['retryAfter' => $retry]);
                }
            }
            $proof = ['commandBase64' => $params['commandBase64'],'signatureBase64' => $params['signatureBase64']];
            $this->pdo->exec('SAVEPOINT crypto_command');
            $status = 200;
            try {
                if (str_starts_with($operation, 'crypto.account.') || str_starts_with($operation, 'crypto.device.')) {
                    $result = $this->accountWrite($operation, $p, $actor, $identity, $device, $proof, $rootOperation);
                } else {
                    $result = (new NativeCryptoStorage($this->container, $this->bearer, $this->ip))->writeInTransaction($operation, $p, $actor, $proof);
                }
            } catch (NativeError $error) {
                $this->pdo->exec('ROLLBACK TO SAVEPOINT crypto_command');
                if (in_array($error->status, [401,403], true)) {
                    throw $error;
                }
                $status = $error->status;
                $result = ['errorCode' => $error->errorCode,'details' => $error->details];
            }
            $this->pdo->exec('RELEASE SAVEPOINT crypto_command');
            $this->change('INSERT INTO familyhub_crypto_receipts VALUES(?,?,?,?,?,?,?)', [$account,$request,$digest,json_encode($result, JSON_THROW_ON_ERROR),$status,time(),json_encode($proof, JSON_THROW_ON_ERROR)]);
            if ($status !== 200) {
                return new NativeError($result['errorCode'], $status, $result['details']);
            }
            return $result;
        }, true);
        if ($result instanceof NativeError) {
            throw $result;
        }return $result;
    }
    private function status($identity, $account)
    {
        $result = ['initialized' => $identity !== null,'serverId' => $this->serverId(),'accountId' => $account,'generation' => (int)($identity['generation'] ?? 0)];
        if (!$identity) {
            return $result;
        }
        $result += ['rootSigningKeyBase64' => $identity['root_signing_key'],'rootEncryptionKeyBase64' => $identity['root_encryption_key'],'keyringCiphertextBase64' => $identity['keyring'],'genesisCertificate' => json_decode($identity['genesis_certificate'], true, 34, JSON_THROW_ON_ERROR),'keyringCertificate' => json_decode($identity['keyring_certificate'], true, 34, JSON_THROW_ON_ERROR),'devices' => [],'entryCount' => (int)$this->one('SELECT COUNT(*) AS n FROM familyhub_crypto_keyring_entries WHERE account_id=?', [$account])['n']];
        foreach ($this->many('SELECT * FROM familyhub_crypto_devices WHERE account_id=? ORDER BY device_id', [$account]) as $d) {
            $result['devices'][] = ['deviceId' => $d['device_id'],'signingKeyBase64' => $d['signing_key'],'encryptionKeyBase64' => $d['encryption_key'],'keyringWrite' => (bool)$d['keyring_write'],'manageDevices' => (bool)$d['manage_devices'],'revoked' => $d['revoked_at'] !== null,'certificate' => json_decode($d['certificate'], true, 34, JSON_THROW_ON_ERROR),'revocationCertificate' => $d['revocation_certificate'] ? json_decode($d['revocation_certificate'], true, 34, JSON_THROW_ON_ERROR) : null];
        }
        if ($identity) {
            $result['generationCertificate'] = json_decode($identity['generation_certificate'], true, 34, JSON_THROW_ON_ERROR);
        }return $result;
    }
    private function accountWrite($operation, $p, $actor, $identity, $device, $proof, $rootOperation)
    {
        $account = $actor['user']['account_id'];
        $generation = (int)($identity['generation'] ?? 0);
        if (!isset($p['expectedGeneration']) || $p['expectedGeneration'] !== $generation) {
            throw new NativeError('crypto_generation_conflict', 409, ['generation' => $generation]);
        }
        if ($operation === 'crypto.account.initialize') {
            $this->fields($p, ['expectedGeneration','rootSigningKeyBase64','rootEncryptionKeyBase64','deviceSigningKeyBase64','deviceEncryptionKeyBase64','keyringCiphertextBase64']);
            if ($identity) {
                throw new NativeError('crypto_identity_exists', 409);
            }
            foreach (['rootSigningKeyBase64','rootEncryptionKeyBase64','deviceSigningKeyBase64','deviceEncryptionKeyBase64'] as $field) {
                NativeCryptoCodec::base64($p[$field], 32, 32);
            }
            $this->cipher($p['keyringCiphertextBase64']);
            $certificate = json_encode($proof, JSON_THROW_ON_ERROR);
            $this->change('INSERT INTO familyhub_crypto_accounts VALUES(?,?,?,?,?,?,?,?,?,?)', [$account,$p['rootSigningKeyBase64'],$p['rootEncryptionKeyBase64'],$p['keyringCiphertextBase64'],$certificate,$certificate,$certificate,1,time(),time()]);
            $this->change('INSERT INTO familyhub_crypto_devices(account_id,device_id,signing_key,encryption_key,certificate,keyring_write,manage_devices) VALUES(?,?,?,?,?,?,?)', [$account,$actor['device']['id'],$p['deviceSigningKeyBase64'],$p['deviceEncryptionKeyBase64'],$certificate,1,1]);
            $this->event($account, 'crypto.initialized');
            return ['initialized' => true,'generation' => 1];
        }
        if (!$identity) {
            throw new NativeError('crypto_account_missing', 409);
        }
        if ($operation === 'crypto.account.recoveryStart') {
            $this->fields($p, ['expectedGeneration']);
            $this->advanceAccount($account, $proof);
            $this->event($account, 'crypto.recoveryStarted');
        } elseif ($operation === 'crypto.account.keyringEntriesPut') {
            $this->fields($p, ['expectedGeneration','entries']);
            if (!$device || !(int)$device['keyring_write']) {
                throw new NativeError('crypto_keyring_forbidden', 403);
            }
            if (!is_array($p['entries']) || !array_is_list($p['entries']) || count($p['entries']) < 1 || count($p['entries']) > 32) {
                throw new NativeError('validation_error');
            }$seen = [];
            foreach ($p['entries'] as $entry) {
                if (!is_array($entry)) {
                    throw new NativeError('validation_error');
                }$this->fields($entry, ['id','recipientId','recipientPublicKeyBase64','sealedEnvelopeBase64']);
                $id = $this->uuid($entry['id']);
                $recipient = $entry['recipientId'];
                NativeCryptoCodec::base64($entry['recipientPublicKeyBase64'], 32, 32);
                $cipher = NativeCryptoCodec::base64($entry['sealedEnvelopeBase64'], 4096);
                if (strlen($cipher) < 48) {
                    throw new NativeError('crypto_invalid_envelope');
                }
                if ($recipient === 'recovery') {
                    $key = $identity['root_encryption_key'];
                } else {
                    $this->uuid($recipient);
                    $d = $this->one('SELECT encryption_key FROM familyhub_crypto_devices WHERE account_id=? AND device_id=? AND revoked_at IS NULL', [$account,$recipient]);
                    $key = $d['encryption_key'] ?? null;
                }
                if ($key === null || !hash_equals($key, $entry['recipientPublicKeyBase64'])) {
                    throw new NativeError('crypto_recipient_key_changed', 409);
                }
                if (isset($seen[$id.':'.$recipient])) {
                    throw new NativeError('validation_error');
                }$seen[$id.':'.$recipient] = true;
                $old = $this->one('SELECT * FROM familyhub_crypto_keyring_entries WHERE account_id=? AND id=? AND recipient_id=?', [$account,$id,$recipient]);
                if ($old) {
                    if ($old['recipient_key'] !== $key || !hash_equals($old['envelope'], $entry['sealedEnvelopeBase64'])) {
                        throw new NativeError('crypto_envelope_immutable', 409);
                    }
                } else {
                    $this->change('INSERT INTO familyhub_crypto_keyring_entries VALUES(?,?,?,?,?,?)', [$account,$id,$recipient,$key,$entry['sealedEnvelopeBase64'],json_encode($proof, JSON_THROW_ON_ERROR)]);
                }
            }
            foreach ($p['entries'] as $entry) {
                if (!$this->one('SELECT id FROM familyhub_crypto_keyring_entries WHERE account_id=? AND id=? AND recipient_id=?', [$account,$entry['id'],'recovery'])) {
                    throw new NativeError('crypto_recovery_envelope_required', 409);
                }
            }
            $this->change('UPDATE familyhub_crypto_accounts SET keyring_certificate=?,generation_certificate=?,generation=generation+1,updated_at=? WHERE account_id=?', [json_encode($proof, JSON_THROW_ON_ERROR),json_encode($proof, JSON_THROW_ON_ERROR),time(),$account]);
        } elseif ($operation === 'crypto.device.add') {
            $this->fields($p, ['expectedGeneration','deviceId','signingKeyBase64','encryptionKeyBase64','keyringWrite','manageDevices']);
            $id = $this->uuid($p['deviceId']);
            NativeCryptoCodec::base64($p['signingKeyBase64'], 32, 32);
            NativeCryptoCodec::base64($p['encryptionKeyBase64'], 32, 32);
            if (!is_bool($p['keyringWrite']) || !is_bool($p['manageDevices'])) {
                throw new NativeError('validation_error');
            }
            if (!$rootOperation && ($p['keyringWrite'] && !(int)$device['keyring_write'] || $p['manageDevices'] && !(int)$device['manage_devices'])) {
                throw new NativeError('crypto_delegation_forbidden', 403);
            }
            if (!$this->one('SELECT id FROM familyhub_devices WHERE id=? AND account_id=? AND revoked_at IS NULL AND expires_at>?', [$id,$account,time()])) {
                throw new NativeError('device_revoked', 403);
            }
            if ($this->one('SELECT device_id FROM familyhub_crypto_devices WHERE account_id=? AND device_id=?', [$account,$id])) {
                throw new NativeError('crypto_device_exists', 409);
            }
            if ($rootOperation && !$this->hasRecoveryStart($identity, $actor['device']['id'], $generation)) {
                $this->event($account, 'crypto.recoveryStarted');
            }
            $this->change('INSERT INTO familyhub_crypto_devices(account_id,device_id,signing_key,encryption_key,certificate,keyring_write,manage_devices) VALUES(?,?,?,?,?,?,?)', [$account,$id,$p['signingKeyBase64'],$p['encryptionKeyBase64'],json_encode($proof, JSON_THROW_ON_ERROR),(int)$p['keyringWrite'],(int)$p['manageDevices']]);
            $this->advanceAccount($account, $proof);
            $this->event($account, 'crypto.deviceAdded');
            if ($rootOperation) {
                $this->event($account, 'crypto.recoveryCompleted');
            }
        } elseif ($operation === 'crypto.device.revoke') {
            $this->fields($p, ['expectedGeneration','deviceId']);
            $id = $this->uuid($p['deviceId']);
            if ($id === $actor['device']['id']) {
                throw new NativeError('crypto_self_revocation_forbidden', 403);
            }
            if (!$this->one('SELECT device_id FROM familyhub_crypto_devices WHERE account_id=? AND device_id=? AND revoked_at IS NULL', [$account,$id])) {
                throw new NativeError('crypto_device_unapproved', 403);
            }
            $this->change('UPDATE familyhub_crypto_devices SET revoked_at=?,revocation_certificate=? WHERE account_id=? AND device_id=?', [time(),json_encode($proof, JSON_THROW_ON_ERROR),$account,$id]);
            $this->change('UPDATE familyhub_devices SET revoked_at=? WHERE id=? AND account_id=?', [time(),$id,$account]);
            (new NativePushService($this->container))->revokeDevice($id);
            $this->advanceAccount($account, $proof);
            $this->event($account, 'crypto.deviceRevoked');
        } else {
            throw new NativeError('unsupported_operation', 404);
        }
        return ['generation' => $generation + 1];
    }
    public function entries($p, $account, $identity)
    {
        $this->fields($p, [], ['afterId','limit']);
        $after = isset($p['afterId']) ? $this->uuid($p['afterId']) : '';
        $limit = $p['limit'] ?? 20;
        if (!is_int($limit) || $limit < 1 || $limit > 50) {
            throw new NativeError('validation_error');
        }
        $ids = $this->many('SELECT DISTINCT id FROM familyhub_crypto_keyring_entries WHERE account_id=? AND id>? ORDER BY id LIMIT '.($limit + 1), [$account,$after]);
        $out = [];
        $proofs = [];
        $included = 0;
        $last = null;
        foreach (array_slice($ids, 0, $limit) as $key) {
            $group = [];
            $newProofs = $proofs;
            foreach ($this->many('SELECT * FROM familyhub_crypto_keyring_entries WHERE account_id=? AND id=? ORDER BY recipient_id', [$account,$key['id']]) as $r) {
                $proofId = hash('sha256', $r['authorization']);
                $newProofs[$proofId] = json_decode($r['authorization'], true, 34, JSON_THROW_ON_ERROR);
                $group[] = ['id' => $r['id'],'recipientId' => $r['recipient_id'],'recipientPublicKeyBase64' => $r['recipient_key'],'sealedEnvelopeBase64' => $r['envelope'],'authorizationId' => $proofId];
            }
            if (strlen(json_encode(['entries' => array_merge($out, $group),'authorizations' => $newProofs], JSON_THROW_ON_ERROR)) > 1572864) {
                if (!$out) {
                    throw new NativeError('crypto_keyring_page_too_large', 413);
                }break;
            }
            $out = array_merge($out, $group);
            $proofs = $newProofs;
            $included++;
            $last = $key['id'];
        }
        return ['entries' => $out,'authorizations' => (object)$proofs,'hasMore' => $included < count($ids),'nextAfterId' => $last,'generation' => (int)($identity['generation'] ?? 0)];
    }
    private function hasRecoveryStart($identity, $deviceId, $generation)
    {
        $proof = json_decode($identity['generation_certificate'], true, 34, JSON_THROW_ON_ERROR);
        [$previous] = NativeCryptoCodec::decode($proof);
        return $previous['operation'] === 'crypto.account.recoveryStart' && $previous['signer'] === 'root' && $previous['deviceId'] === $deviceId && ($previous['payload']['expectedGeneration'] ?? -2) + 1 === $generation;
    }
    /** Already inside the serialized command transaction: counters commit on a rate denial. */
    private function recoveryRate($account)
    {
        $id = hash('sha256', 'crypto-recovery:'.$account);
        $now = time();
        $row = $this->one('SELECT * FROM familyhub_rate_limits WHERE id=?', [$id]);
        if (!$row) {
            $this->change('INSERT INTO familyhub_rate_limits(id,window_start,attempts) VALUES(?,?,1)', [$id,$now]);
            return 0;
        }
        if ((int)$row['window_start'] + 900 <= $now) {
            $this->change('UPDATE familyhub_rate_limits SET window_start=?,attempts=1 WHERE id=?', [$now,$id]);
            return 0;
        }
        $attempts = (int)$row['attempts'] + 1;
        $this->change('UPDATE familyhub_rate_limits SET attempts=? WHERE id=?', [$attempts,$id]);
        return $attempts > 3 ? (int)$row['window_start'] + 900 - $now : 0;
    }
    private function cipher($value)
    {
        $bytes = NativeCryptoCodec::base64($value, 262144);
        if (strlen($bytes) < 48) {
            throw new NativeError('crypto_invalid_envelope');
        }
    }
    private function advanceAccount($account, $proof)
    {
        $this->change('UPDATE familyhub_crypto_accounts SET generation_certificate=?,generation=generation+1,updated_at=? WHERE account_id=?', [json_encode($proof, JSON_THROW_ON_ERROR),time(),$account]);
    }
    public function event($account, $kind)
    {
        if (!\Kanboard\Plugin\FamilyHub\Schema\CryptoSchema::ready($this->pdo)) {
            return;
        }
        $identity = $this->one('SELECT * FROM familyhub_email_identities WHERE account_id=? AND verified_at IS NOT NULL', [$account]);
        if (!$identity || !filter_var($identity['email'], FILTER_VALIDATE_EMAIL)) {
            return;
        }
        $this->change('INSERT INTO familyhub_crypto_security_events(id,account_id,kind,email,identity_revision,state,next_attempt,created_at) VALUES(?,?,?,?,?,?,?,?)', [$this->newUuid(),$account,$kind,$identity['email'],(int)$identity['revision'],'pending',time(),time()]);
    }
}
