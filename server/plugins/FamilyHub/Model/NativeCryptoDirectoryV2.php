<?php

namespace Kanboard\Plugin\FamilyHub\Model;

/** Deterministic signed account state reducer. SQL is a projection, never authority for a certificate. */
class NativeCryptoDirectoryV2 extends NativeDatabase
{
    protected $cryptoAccess = true;
    public const ZERO = '0000000000000000000000000000000000000000000000000000000000000000';
    public function current($account)
    {
        $last = $this->one('SELECT * FROM familyhub_crypto_directory WHERE account_id=? ORDER BY generation DESC LIMIT 1', [$account]);
        $state = $this->one('SELECT * FROM familyhub_crypto_directory_state WHERE account_id=?', [$account]);
        if (!$last) {
            if ($state) {
                throw new NativeError('crypto_directory_cache_unavailable', 503);
            }return null;
        }
        if (!$state || (int)$state['generation'] !== (int)$last['generation'] || $state['head_hash'] !== $last['head_hash'] || $state['snapshot_hash'] !== $last['snapshot_hash'] || $state['device_snapshot_hash'] !== $last['device_snapshot_hash'] || $state['identity_epoch_id'] !== $last['identity_epoch_id']) {
            throw new NativeError('crypto_directory_cache_unavailable', 503);
        }
        try {
            $snapshot = json_decode($state['snapshot'], true, 34, JSON_THROW_ON_ERROR);
            $proof = json_decode($last['authorization'], true, 34, JSON_THROW_ON_ERROR);
            [$command] = NativeCryptoCodec::decode($proof);
            if (self::snapshotHash($snapshot) !== $last['snapshot_hash'] || self::deviceHash($snapshot) !== $last['device_snapshot_hash'] || $snapshot['identityEpochId'] !== $last['identity_epoch_id'] || $command['payload']['resultingSnapshotHash'] !== $last['snapshot_hash'] || $command['payload']['expectedGeneration'] + 1 !== (int)$last['generation'] || NativeCryptoV2Codec::head($command, $proof, (int)$last['generation']) !== $last['head_hash']) {
                throw new NativeError('crypto_directory_cache_unavailable', 503);
            }
        } catch (NativeError $e) {
            throw $e;
        } catch (\Throwable $e) {
            throw new NativeError('crypto_directory_cache_unavailable', 503);
        }
        return $state + array_intersect_key($last, array_flip(['authorization','previous_head_hash','command_hash']));
    }
    public static function rebindBody($command)
    {
        $p = $command['payload'];
        return ['version' => 2,'serverId' => $command['serverId'],'accountId' => $command['accountId'],'requestId' => $command['requestId'],'approvingDeviceId' => $p['approvingDeviceId'],'newDeviceId' => $command['deviceId'],'expectedGeneration' => $p['expectedGeneration'],'previousHeadHash' => $p['previousHeadHash'],'identityEpochId' => $p['identityEpochId'],'signingKeyBase64' => $p['signingKeyBase64'],'encryptionKeyBase64' => $p['encryptionKeyBase64'],'keyringWrite' => $p['keyringWrite'],'manageDevices' => $p['manageDevices'],'retireApprovingDevice' => $p['retireApprovingDevice'],'resultingSnapshotHash' => $p['resultingSnapshotHash']];
    }
    public static function snapshotHash($snapshot)
    {
        return NativeCryptoV2Codec::hash((object)$snapshot);
    }
    public static function deviceHash($s)
    {
        return NativeCryptoV2Codec::hash((object)array_intersect_key($s, array_flip(['version','serverId','accountId','rootSigningKeyBase64','rootEncryptionKeyBase64','recoveryRootEpochId','identityEpochId','devices'])));
    }
    public function authorize($command, $current)
    {
        $p = $command['payload'];
        $op = $command['operation'];
        $signer = $command['signer'];
        if (!$current) {
            if ($op !== 'crypto2.account.initialize' || $signer !== 'root') {
                throw new NativeError('crypto_directory_missing', 409);
            }return $p['rootSigningKeyBase64'] ?? null;
        }
        $s = json_decode($current['snapshot'], true, 34, JSON_THROW_ON_ERROR);
        if ($signer === 'root') {
            if (!in_array($op, ['crypto2.device.add','crypto2.device.revoke','crypto2.account.recoveryStart','crypto2.account.recoverEpoch','crypto2.account.rotateRoot'], true)) {
                throw new NativeError('crypto_signer_forbidden', 403);
            }return $s['rootSigningKeyBase64'];
        }
        if ($signer !== 'device') {
            throw new NativeError('crypto_signer_forbidden', 403);
        }
        if (!in_array($op, ['crypto2.account.keyringEntriesPut','crypto2.account.protectionReady','crypto2.account.migrationAttest','crypto2.account.scopeObserve','crypto2.account.scheduleUse','crypto2.account.scopeDeletion','crypto2.account.projectRelocation','crypto2.device.add','crypto2.device.revoke','crypto2.device.rebind'], true)) {
            throw new NativeError('crypto_signer_forbidden', 403);
        }
        $authorId = $op === 'crypto2.device.rebind' ? $this->uuid($p['approvingDeviceId'] ?? null) : $command['deviceId'];
        $d = $this->device($s, $authorId);
        if (!$d || $d['revokedGeneration'] !== null || $d['identityEpochId'] !== $s['identityEpochId']) {
            throw new NativeError('crypto_device_unapproved', 403);
        }
        if (in_array($op, ['crypto2.device.add','crypto2.device.revoke','crypto2.device.rebind'], true) && !$d['manageDevices']) {
            throw new NativeError('crypto_device_management_forbidden', 403);
        }
        if (in_array($op,['crypto2.account.keyringEntriesPut','crypto2.account.migrationAttest','crypto2.account.scopeObserve','crypto2.account.scopeDeletion','crypto2.account.projectRelocation'],true) && !$d['keyringWrite']) {
            throw new NativeError('crypto_keyring_forbidden', 403);
        }
        if (str_starts_with($op, 'crypto2.account.') && !in_array($op, ['crypto2.account.keyringEntriesPut','crypto2.account.protectionReady','crypto2.account.migrationAttest','crypto2.account.scopeObserve','crypto2.account.scheduleUse','crypto2.account.scopeDeletion','crypto2.account.projectRelocation'], true)) {
            throw new NativeError('crypto_signer_forbidden', 403);
        }
        return $d['signingKeyBase64'];
    }
    public function authorizeContent($command, $current)
    {
        if (!$current || $command['signer'] !== 'device') {
            throw new NativeError('crypto_device_unapproved', 403);
        }$s = json_decode($current['snapshot'], true, 34, JSON_THROW_ON_ERROR);
        $d = $this->device($s, $command['deviceId']);
        if (!$d || $d['revokedGeneration'] !== null || $d['identityEpochId'] !== $s['identityEpochId']) {
            throw new NativeError('crypto_device_unapproved', 403);
        }return $d['signingKeyBase64'];
    }
    public function reduce($command, $current)
    {
        $p = $command['payload'];
        $op = $command['operation'];
        $n = $current ? (int)$current['generation'] + 1 : 1;
        $common = ['expectedGeneration','previousHeadHash','identityEpochId','resultingSnapshotHash'];
        foreach ($common as $key) {
            if (!array_key_exists($key, $p)) {
                throw new NativeError('validation_error');
            }
        }
        if (!is_int($p['expectedGeneration']) || !is_string($p['previousHeadHash'])) {
            throw new NativeError('validation_error');
        }
        if ($p['expectedGeneration'] !== $n - 1 || $p['previousHeadHash'] !== ($current['head_hash'] ?? self::ZERO)) {
            throw new NativeError('crypto_generation_conflict', 409, ['generation' => $n - 1,'headHash' => $current['head_hash'] ?? self::ZERO]);
        }
        $this->uuid($p['identityEpochId']);
        $this->digest($p['resultingSnapshotHash']);
        $s = $current ? json_decode($current['snapshot'], true, 34, JSON_THROW_ON_ERROR) : null;
        if ($s && $p['identityEpochId'] !== $s['identityEpochId']) {
            throw new NativeError('crypto_identity_epoch_changed', 409);
        }
        if ($op === 'crypto2.account.initialize') {
            $this->fields($p, array_merge($common, ['rootSigningKeyBase64','rootEncryptionKeyBase64','deviceSigningKeyBase64','deviceEncryptionKeyBase64','keyringCiphertextBase64']));
            if ($s) {
                throw new NativeError('crypto_identity_exists', 409);
            }
            foreach (['rootSigningKeyBase64','rootEncryptionKeyBase64','deviceSigningKeyBase64','deviceEncryptionKeyBase64'] as $k) {
                NativeCryptoCodec::base64($p[$k], 32, 32);
            }
            $cipher = NativeCryptoCodec::base64($p['keyringCiphertextBase64'], 262144);
            if (strlen($cipher) < 48) {
                throw new NativeError('crypto_invalid_envelope');
            }
            $s = ['version' => 2,'serverId' => $command['serverId'],'accountId' => $command['accountId'],'rootSigningKeyBase64' => $p['rootSigningKeyBase64'],'rootEncryptionKeyBase64' => $p['rootEncryptionKeyBase64'],'recoveryRootCiphertextHash' => hash('sha256', $cipher),'recoveryRootEpochId' => $p['identityEpochId'],'identityEpochId' => $p['identityEpochId'],'devices' => [$this->newDevice($command['deviceId'], $p['deviceSigningKeyBase64'], $p['deviceEncryptionKeyBase64'], true, true, $n, $p['identityEpochId'])],'keyringEntries' => []];
        } elseif ($op === 'crypto2.account.recoveryStart') {
            $this->fields($p, $common);
        } elseif ($op === 'crypto2.account.scopeObserve') {
            $this->fields($p, array_merge($common, ['scopeToken','headHash','observationHash']));
            foreach (['scopeToken','headHash','observationHash'] as $field) {
                $this->digest($p[$field]);
            }
        } elseif ($op === 'crypto2.account.scheduleUse') {
            $this->fields($p,array_merge($common,['useToken','useProofHash','active']));
            $this->digest($p['useToken']);
            $this->digest($p['useProofHash']);
            if (!is_bool($p['active'])) { throw new NativeError('validation_error'); }
        } elseif ($op === 'crypto2.account.scopeDeletion') {
            $this->fields($p,array_merge($common,['scopeToken','certificateHash']));
            $this->digest($p['scopeToken']);
            $this->digest($p['certificateHash']);
        } elseif ($op === 'crypto2.account.projectRelocation') {
            $this->fields($p,array_merge($common,['actionId','publicationRoot']));
            $this->uuid($p['actionId']);
            $this->digest($p['publicationRoot']);
        } elseif ($op === 'crypto2.account.migrationAttest') {
            $this->fields($p,array_merge($common,['migrationId','scopeToken','domain','attestationHash']));
            $this->uuid($p['migrationId']);
            $this->digest($p['scopeToken']);
            $this->digest($p['attestationHash']);
            if (!in_array($p['domain'],['content','finance'],true)) { throw new NativeError('validation_error'); }
        } elseif ($op === 'crypto2.account.protectionReady') {
            $this->fields($p,array_merge($common,['deviceSnapshotHash','scopeManifestHash']));
            $this->digest($p['scopeManifestHash']);
            if ($p['deviceSnapshotHash']!==self::deviceHash($s)) { throw new NativeError('crypto_protection_catalog_changed',409); }
        } elseif ($op === 'crypto2.account.recoverEpoch') {
            $this->fields($p, array_merge($common, ['newIdentityEpochId','newDeviceSigningKeyBase64','newDeviceEncryptionKeyBase64']));
            $epoch = $this->uuid($p['newIdentityEpochId']);
            if ($epoch === $s['identityEpochId'] || $this->device($s, $command['deviceId'])) {
                throw new NativeError('crypto_fresh_device_required', 409);
            }
            foreach ($s['devices'] as $oldDevice) {
                if ($oldDevice['identityEpochId'] === $epoch) {
                    throw new NativeError('crypto_identity_epoch_exists', 409);
                }
            }
            NativeCryptoCodec::base64($p['newDeviceSigningKeyBase64'], 32, 32);
            NativeCryptoCodec::base64($p['newDeviceEncryptionKeyBase64'], 32, 32);
            foreach ($s['devices'] as &$d) {
                if ($d['revokedGeneration'] === null) {
                    $d['revokedGeneration'] = $n;
                }
            }unset($d);
            $s['identityEpochId'] = $epoch;
            $s['devices'][] = $this->newDevice($command['deviceId'], $p['newDeviceSigningKeyBase64'], $p['newDeviceEncryptionKeyBase64'], true, true, $n, $epoch);
        } elseif ($op === 'crypto2.device.add') {
            $this->fields($p, array_merge($common, ['deviceId','signingKeyBase64','encryptionKeyBase64','keyringWrite','manageDevices']));
            $id = $this->uuid($p['deviceId']);
            NativeCryptoCodec::base64($p['signingKeyBase64'], 32, 32);
            NativeCryptoCodec::base64($p['encryptionKeyBase64'], 32, 32);
            if (!is_bool($p['keyringWrite']) || !is_bool($p['manageDevices'])) {
                throw new NativeError('validation_error');
            }if ($this->device($s, $id)) {
                throw new NativeError('crypto_device_exists', 409);
            }
            $author = $this->device($s, $command['deviceId']);
            if ($command['signer'] === 'device' && ($p['keyringWrite'] && !$author['keyringWrite'] || $p['manageDevices'] && !$author['manageDevices'])) {
                throw new NativeError('crypto_delegation_forbidden', 403);
            }
            $s['devices'][] = $this->newDevice($id, $p['signingKeyBase64'], $p['encryptionKeyBase64'], $p['keyringWrite'], $p['manageDevices'], $n, $s['identityEpochId']);
        } elseif ($op === 'crypto2.device.rebind') {
            $this->fields($p, array_merge($common, ['approvingDeviceId','signingKeyBase64','encryptionKeyBase64','keyringWrite','manageDevices','retireApprovingDevice','newDeviceProof']));
            $approver = $this->uuid($p['approvingDeviceId']);
            $id = $this->uuid($command['deviceId']);
            $author = $this->device($s, $approver);
            if (!$author || $author['revokedGeneration'] !== null || $author['identityEpochId'] !== $s['identityEpochId'] || !$author['manageDevices'] || $p['retireApprovingDevice'] !== true || $command['signer'] !== 'device') {
                throw new NativeError('crypto_device_management_forbidden', 403);
            }
            if (!is_bool($p['keyringWrite']) || !is_bool($p['manageDevices']) || $p['keyringWrite'] && !$author['keyringWrite'] || $p['manageDevices'] && !$author['manageDevices']) {
                throw new NativeError('crypto_delegation_forbidden', 403);
            }
            NativeCryptoCodec::base64($p['signingKeyBase64'], 32, 32);
            NativeCryptoCodec::base64($p['encryptionKeyBase64'], 32, 32);
            if ($this->device($s, $id) || $p['signingKeyBase64'] === $s['rootSigningKeyBase64'] || $p['encryptionKeyBase64'] === $s['rootEncryptionKeyBase64']) {
                throw new NativeError('crypto_device_exists', 409);
            }
            foreach ($s['devices'] as $oldDevice) {
                if ($oldDevice['signingKeyBase64'] === $p['signingKeyBase64'] || $oldDevice['encryptionKeyBase64'] === $p['encryptionKeyBase64']) {
                    throw new NativeError('crypto_device_key_reused', 409);
                }
            }
            [$possession,$popBytes,$popSignature] = NativeCryptoCodec::decode($p['newDeviceProof']);
            if (NativeCryptoCodec::canonical((object)$possession) !== NativeCryptoCodec::canonical((object)self::rebindBody($command))) {
                throw new NativeError('crypto_device_rebind_binding', 403);
            }
            NativeCryptoV2Codec::verify($popBytes, $popSignature, $p['signingKeyBase64'], "JivieE2EE/deviceRebind/v2\n");
            foreach ($s['devices'] as &$oldDevice) {
                if ($oldDevice['deviceId'] === $approver) {
                    $oldDevice['revokedGeneration'] = $n;
                }
            } unset($oldDevice);
            $s['devices'][] = $this->newDevice($id, $p['signingKeyBase64'], $p['encryptionKeyBase64'], $p['keyringWrite'], $p['manageDevices'], $n, $s['identityEpochId']);
        } elseif ($op === 'crypto2.device.revoke') {
            $this->fields($p, array_merge($common, ['deviceId']));
            $id = $this->uuid($p['deviceId']);
            if ($id === $command['deviceId']) {
                throw new NativeError('crypto_self_revocation_forbidden', 403);
            }$found = false;
            foreach ($s['devices'] as &$d) {
                if ($d['deviceId'] === $id && $d['revokedGeneration'] === null) {
                    $d['revokedGeneration'] = $n;
                    $found = true;
                }
            }unset($d);
            if (!$found) {
                throw new NativeError('crypto_device_unapproved', 403);
            }
        } elseif ($op === 'crypto2.account.rotateRoot') {
            $this->fields($p, array_merge($common, ['transitionId','newRootSigningKeyBase64','newRootEncryptionKeyBase64','newIdentityEpochId','newDeviceSigningKeyBase64','newDeviceEncryptionKeyBase64','keyringCiphertextBase64','incomingRootProof']));
            $this->uuid($p['transitionId']);
            $epoch = $this->uuid($p['newIdentityEpochId']);
            foreach (['newRootSigningKeyBase64','newRootEncryptionKeyBase64','newDeviceSigningKeyBase64','newDeviceEncryptionKeyBase64'] as $k) {
                NativeCryptoCodec::base64($p[$k], 32, 32);
            }
            if ($p['newRootSigningKeyBase64'] === $s['rootSigningKeyBase64'] || $p['newRootEncryptionKeyBase64'] === $s['rootEncryptionKeyBase64'] || $command['deviceId'] === $epoch || $this->device($s, $command['deviceId'])) {
                throw new NativeError('crypto_root_transition_invalid', 409);
            }
            foreach ($s['devices'] as $d) {
                if ($d['identityEpochId'] === $epoch || $d['deviceId'] === $epoch) {
                    throw new NativeError('crypto_identity_epoch_exists', 409);
                }
            }
            $cipher = NativeCryptoCodec::base64($p['keyringCiphertextBase64'], 262144);
            if (strlen($cipher) < 48) {
                throw new NativeError('crypto_invalid_envelope');
            }
            $fingerprint = base64_encode(sodium_crypto_generichash(NativeCryptoCodec::canonical((object)['encryptionKeyBase64' => $s['rootEncryptionKeyBase64'],'signingKeyBase64' => $s['rootSigningKeyBase64'],'suite' => 'sodium-box-seal-xchacha20poly1305-ed25519-v1']), '', 32));
            $transition = ['version' => 2,'serverId' => $command['serverId'],'accountId' => $command['accountId'],'transitionId' => $p['transitionId'],'previousHeadHash' => $current['head_hash'],'previousSnapshotHash' => $current['snapshot_hash'],'oldFingerprint' => $fingerprint,'oldRootSigningKeyBase64' => $s['rootSigningKeyBase64'],'oldRootEncryptionKeyBase64' => $s['rootEncryptionKeyBase64'],'newRecoveryRootEpochId' => $epoch,'newRootSigningKeyBase64' => $p['newRootSigningKeyBase64'],'newRootEncryptionKeyBase64' => $p['newRootEncryptionKeyBase64'],'newIdentityEpochId' => $epoch,'newDeviceSigningKeyBase64' => $p['newDeviceSigningKeyBase64'],'newDeviceEncryptionKeyBase64' => $p['newDeviceEncryptionKeyBase64'],'newEncryptedRootCiphertextHash' => hash('sha256', $cipher),'resultingSnapshotHash' => $p['resultingSnapshotHash']];
            [$incoming,$incomingBytes,$incomingSignature] = NativeCryptoCodec::decode($p['incomingRootProof']);
            NativeCryptoV2Codec::verify($incomingBytes, $incomingSignature, $p['newRootSigningKeyBase64'], "JivieE2EE/rootTransition/v2\n");
            if (NativeCryptoCodec::canonical((object)$incoming) !== NativeCryptoCodec::canonical((object)$transition)) {
                throw new NativeError('crypto_root_transition_invalid', 409);
            }
            foreach ($s['devices'] as &$d) {
                if ($d['revokedGeneration'] === null) {
                    $d['revokedGeneration'] = $n;
                }
            }unset($d);
            $s['rootSigningKeyBase64'] = $p['newRootSigningKeyBase64'];
            $s['rootEncryptionKeyBase64'] = $p['newRootEncryptionKeyBase64'];
            $s['identityEpochId'] = $epoch;
            $s['recoveryRootEpochId'] = $epoch;
            $s['recoveryRootCiphertextHash'] = hash('sha256', $cipher);
            $s['devices'][] = $this->newDevice($command['deviceId'], $p['newDeviceSigningKeyBase64'], $p['newDeviceEncryptionKeyBase64'], true, true, $n, $epoch);
        } elseif ($op === 'crypto2.account.keyringEntriesPut') {
            $this->fields($p, array_merge($common, ['entries']));
            $entries = $p['entries'];
            if (!is_array($entries) || !array_is_list($entries) || count($entries) < 1 || count($entries) > 32) {
                throw new NativeError('validation_error');
            }$seen = [];
            foreach ($entries as $entry) {
                if (!is_array($entry)) {
                    throw new NativeError('validation_error');
                }$this->fields($entry, ['id','recipientId','recipientKind','recipientPublicKeyBase64','sealedEnvelopeBase64']);
                $id = $this->uuid($entry['id']);
                $rid = $this->uuid($entry['recipientId']);
                if (!in_array($entry['recipientKind'], ['device','recovery'], true)) {
                    throw new NativeError('validation_error');
                }$pair = $id.':'.$entry['recipientKind'].':'.$rid;
                if (isset($seen[$pair])) {
                    throw new NativeError('validation_error');
                }$seen[$pair] = true;
                if ($entry['recipientKind'] === 'recovery') {
                    $public = $rid === $s['recoveryRootEpochId'] ? $s['rootEncryptionKeyBase64'] : null;
                } else {
                    $this->uuid($rid);
                    $d = $this->device($s, $rid);
                    $public = $d && $d['revokedGeneration'] === null && $d['identityEpochId'] === $s['identityEpochId'] ? $d['encryptionKeyBase64'] : null;
                }
                if ($public === null || $public !== $entry['recipientPublicKeyBase64']) {
                    throw new NativeError('crypto_recipient_key_changed', 409);
                }NativeCryptoCodec::base64($public, 32, 32);
                $box = NativeCryptoCodec::base64($entry['sealedEnvelopeBase64'], 4096);
                if (strlen($box) < 48) {
                    throw new NativeError('crypto_invalid_envelope');
                }
                $old = null;
                foreach ($s['keyringEntries'] as $k) {
                    if ($k['id'] === $id && $k['recipientKind'] === $entry['recipientKind'] && $k['recipientId'] === $rid) {
                        $old = $k;
                        break;
                    }
                }
                if ($old) {
                    if ($old['recipientKind'] !== $entry['recipientKind'] || $old['recipientPublicKeyBase64'] !== $public || $old['envelopeHash'] !== hash('sha256', $box)) {
                        throw new NativeError('crypto_envelope_immutable', 409);
                    }
                } else {
                    $s['keyringEntries'][] = ['id' => $id,'recipientId' => $rid,'recipientKind' => $entry['recipientKind'],'recipientPublicKeyBase64' => $public,'envelopeHash' => hash('sha256', $box),'createdGeneration' => $n,'identityEpochId' => $s['identityEpochId']];
                }
            }
            foreach ($entries as $entry) {
                $found = false;
                foreach ($s['keyringEntries'] as $k) {
                    if ($k['id'] === $entry['id'] && $k['recipientKind'] === 'recovery' && $k['recipientId'] === $s['recoveryRootEpochId'] && $k['recipientPublicKeyBase64'] === $s['rootEncryptionKeyBase64']) {
                        $found = true;
                        break;
                    }
                }if (!$found) {
                    throw new NativeError('crypto_recovery_envelope_required', 409);
                }
            }
        } else {
            throw new NativeError('unsupported_operation', 404);
        }
        foreach ($s['devices'] as $d) {
            if ($s['recoveryRootEpochId'] === $d['deviceId']) {
                throw new NativeError('crypto_recipient_identity_collision', 409);
            }
        }
        usort($s['devices'], fn ($a, $b) => strcmp($a['deviceId'], $b['deviceId']));
        usort($s['keyringEntries'], fn ($a, $b) => strcmp($a['id'], $b['id']) ?: strcmp($a['recipientKind'], $b['recipientKind']) ?: strcmp($a['recipientId'], $b['recipientId']));
        if (count(array_filter($s['devices'], fn ($d) => $d['revokedGeneration'] === null)) > 128) {
            throw new NativeError('crypto_active_device_limit', 422);
        }
        if (!hash_equals(self::snapshotHash($s), $p['resultingSnapshotHash'])) {
            throw new NativeError('crypto_snapshot_mismatch', 409);
        }return $s;
    }
    public function append($command, $proof, $snapshot)
    {
        $n = $command['payload']['expectedGeneration'] + 1;
        $head = NativeCryptoV2Codec::head($command, $proof, $n);
        $snapshotHash = self::snapshotHash($snapshot);
        $deviceHash = self::deviceHash($snapshot);
        $this->change('INSERT INTO familyhub_crypto_directory(account_id,generation,head_hash,previous_head_hash,command_hash,authorization,snapshot,snapshot_hash,device_snapshot_hash,identity_epoch_id) VALUES(?,?,?,?,?,?,?,?,?,?)', [$command['accountId'],$n,$head,$command['payload']['previousHeadHash'],hash('sha256', base64_decode($proof['commandBase64'], true)),json_encode($proof, JSON_THROW_ON_ERROR),'',$snapshotHash,$deviceHash,$snapshot['identityEpochId']]);
        $encoded = NativeCryptoCodec::canonical((object)$snapshot);
        if ($this->one('SELECT account_id FROM familyhub_crypto_directory_state WHERE account_id=?', [$command['accountId']])) {
            $this->change('UPDATE familyhub_crypto_directory_state SET generation=?,head_hash=?,snapshot=?,snapshot_hash=?,device_snapshot_hash=?,identity_epoch_id=? WHERE account_id=?', [$n,$head,$encoded,$snapshotHash,$deviceHash,$snapshot['identityEpochId'],$command['accountId']]);
        } else {
            $this->change('INSERT INTO familyhub_crypto_directory_state VALUES(?,?,?,?,?,?,?)', [$command['accountId'],$n,$head,$encoded,$snapshotHash,$deviceHash,$snapshot['identityEpochId']]);
        }
        return ['generation' => $n,'headHash' => $head,'snapshotHash' => $snapshotHash,'deviceSnapshotHash' => $deviceHash];
    }
    private function newDevice($id, $sign, $box, $keyring, $manage, $n, $epoch)
    {
        return ['deviceId' => $id,'signingKeyBase64' => $sign,'encryptionKeyBase64' => $box,'keyringWrite' => $keyring,'manageDevices' => $manage,'addedGeneration' => $n,'revokedGeneration' => null,'identityEpochId' => $epoch];
    }
    public function device($s, $id)
    {
        foreach ($s['devices'] as $d) {
            if ($d['deviceId'] === $id) {
                return $d;
            }
        }return null;
    }
    private function digest($s)
    {
        if (!is_string($s) || !preg_match('/^[a-f0-9]{64}$/D', $s)) {
            throw new NativeError('validation_error');
        }
    }
}
