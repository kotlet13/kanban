<?php

namespace Kanboard\Plugin\FamilyHub\Model;

/** Public, explicitly selected issuer attestations; business values never enter this API. */
class NativeCryptoExportV2 extends NativeDatabase
{
    protected $cryptoAccess = true;
    public const FIELDS = [
        'financeAccountChoice' => ['accountId','accountScopeId','archived','currency','name','sourceRevision'],
        'paymentSource' => ['amountMinor','currency','eventId','expectReimbursement','paidAt','payerAccountId','reimbursements','revision','sourceEntryId','sourceRevision','sourceScopeId','sourceState'],
    ];

    private function hashValue($v)
    {
        if (!is_string($v) ||
            !preg_match('/^[a-f0-9]{64}$/D', $v)) {
            throw new NativeError('validation_error');
        }
        return $v;
    }

    private function scopes()
    {
        return new NativeCryptoScopeV2($this->container, $this->bearer, $this->ip);
    }

    private function target($scopeId, $headHash, $actor, $manager = false)
    {
        $scope = $this->scope($this->uuid($scopeId), $actor['user']['id'], false);
        $scopes = $this->scopes();
        $head = $scopes->current($scopeId);
        if (!$head ||
            $head['head_hash'] !== $headHash) {
            throw new NativeError('crypto_scope_head_changed', 409);
        }
        if ($manager) {
            $scopes->manager($head, $scope, $actor);
        } else {
            $scopes->author($scopeId, $headHash, (int)$head['epoch'], (int)$scope['effective_access_revision'], $actor, 'finance', false);
        }
        return [$scope,$head];
    }

    private function freshMembers($head, $actor)
    {
        $scope = $this->scope($head['scope_id'],$actor['user']['id']);
        $this->scopes()->assertCurrentMembership($scope,$head);
    }

    private function row($table, $hash)
    {
        $row = $this->one('SELECT * FROM familyhub_crypto_export_'.$table.'_v2 WHERE hash=?', [$this->hashValue($hash)]);
        if (!$row) {
            throw new NativeError('crypto_export_missing', 404);
        }
        return $row;
    }

    private function issuer($body, $actor)
    {
        $directory = new NativeCryptoDirectoryV2($this->container);
        $state = $directory->current($actor['user']['account_id']);
        $this->scopes()->currentAuthorReference($body['authorDirectoryHeadHash'], $actor);
        if (!$state ||
            $state['device_snapshot_hash'] !== $body['deviceSnapshotHash']) {
            throw new NativeError('crypto_member_directory_changed', 409);
        }
        $snapshot = json_decode($state['snapshot'], true, 34, JSON_THROW_ON_ERROR);
        $device = $directory->device($snapshot, $actor['device']['id']);
        if (!$device ||
            $device['revokedGeneration'] !== null) {
            throw new NativeError('crypto_device_unapproved', 403);
        }
        return [$state,$snapshot,$device];
    }

    private function publicBody($proof, $actor, $operation, $domain, $key)
    {
        [$body,$bytes,$signature] = NativeCryptoCodec::decode($proof);
        $fields = ['version','operation','serverId','purpose','scopeId','membershipHeadHash','sourceScopeToken','subjectToken','sourceMembershipHeadHash','sourceRecordProofHash','sourceRevision','accountId','deviceId','authorDirectoryHeadHash','deviceSnapshotHash','disclosureHash','permittedFields'];
        if ($operation === 'crypto2.exports.certificate') {
            $fields = array_merge($fields, ['offerHash','delegationProofHash','bridge']);
        }
        $this->fields($body, $fields, $operation === 'crypto2.exports.certificate' ? ['batchContext'] : []);
        if ($body['version'] !== 2 ||
            $body['operation'] !== $operation ||
            $body['serverId'] !== $this->serverId() ||
            $body['accountId'] !== $actor['user']['account_id'] ||
            $body['deviceId'] !== $actor['device']['id'] ||
            !isset(self::FIELDS[$body['purpose']]) ||
            $body['permittedFields'] !== self::FIELDS[$body['purpose']] ||
            !is_int($body['sourceRevision']) ||
            $body['sourceRevision'] < 1 ||
            $body['sourceRevision'] > 9007199254740991) {
            throw new NativeError('crypto_export_invalid', 403);
        }
        $this->uuid($body['scopeId']);
        foreach (['membershipHeadHash','sourceScopeToken','subjectToken','sourceMembershipHeadHash','sourceRecordProofHash','authorDirectoryHeadHash','deviceSnapshotHash','disclosureHash'] as $field) {
            $this->hashValue($body[$field]);
        }
        $this->issuer($body, $actor);
        NativeCryptoV2Codec::verify($bytes, $signature, $key, $domain);
        return $body;
    }

    private function source($offer, $body, $actor, $prepared = null)
    {
        $scope = $this->scope($offer['source_scope_id'], $actor['user']['id'], false);
        $head = $this->scopes()->current($scope['id']);
        if (!$head ||
            $head['head_hash'] !== $body['sourceMembershipHeadHash']) {
            throw new NativeError('crypto_scope_head_changed', 409);
        }
        $this->scopes()->author($scope['id'], $head['head_hash'], (int)$head['epoch'], (int)$scope['effective_access_revision'], $actor, 'finance', $prepared !== null);
        $this->scopes()->assertCurrentMembership($scope,$head);
        NativeCryptoScopeCreationV2::guardBusiness($this->pdo, $scope['id']);
        if ($prepared !== null) {
            $record = $prepared['record'];
            if ($body['purpose'] !== 'paymentSource' || $record['type'] !== 'paymentEvent' ||
                $record['scopeId'] !== $scope['id'] || $record['id'] !== $offer['source_id'] ||
                $record['membershipHeadHash'] !== $head['head_hash'] ||
                $record['accountId'] !== $actor['user']['account_id'] ||
                $record['deviceId'] !== $actor['device']['id']) {
                throw new NativeError('crypto_export_source_changed', 409);
            }
            $record['revision'] = $record['expectedRevision'] + 1;
            $recordProof = $prepared['recordProof'];
        } else {
            $record = $this->one('SELECT * FROM familyhub_crypto_records WHERE scope_id=? AND id=?', [$scope['id'],$offer['source_id']]);
            $authorization = $record ? json_decode($record['authorization'], true, 34, JSON_THROW_ON_ERROR) : [];
            $recordProof = $authorization['recordProof'] ?? null;
        }
        if (!$record ||
            (int)$record['deleted'] ||
            (int)$record['revision'] !== $body['sourceRevision']) {
            throw new NativeError('crypto_export_source_changed', 409);
        }
        if (!$recordProof ||
            NativeCryptoV2Codec::hash((object)$recordProof) !== $body['sourceRecordProofHash']) {
            throw new NativeError('crypto_export_source_changed', 409);
        }
        if ($body['purpose'] === 'financeAccountChoice') {
            if ($record['type'] !== 'financeAccount') {
                throw new NativeError('crypto_export_source_type', 403);
            }
            $target = $this->one('SELECT parent_scope_id,kind FROM familyhub_scopes WHERE id=?', [$body['scopeId']]);
            if (!$target ||
            $target['kind'] !== 'project' ||
            $target['parent_scope_id'] !== $scope['id']) {
                throw new NativeError('crypto_export_target_invalid', 403);
            }
        } elseif (!in_array($record['type'], ['financeEntry','personalFinanceEntry','paymentEvent','cashMovement'], true)) {
            throw new NativeError('crypto_export_source_type', 403);
        }
        return $record;
    }

    public function replayAccess($op, $p, $actor)
    {
        if (($p['variant']??null)===NativeCryptoAccountChoiceExportV2::VARIANT) return (new NativeCryptoAccountChoiceExportV2($this->container,$this->bearer,$this->ip))->replayAccess($op,$p,$actor);
        if ($op === 'crypto2.exports.propose') {
            $this->scope($this->uuid($p['sourceScopeId'] ?? null), $actor['user']['id'], false);
            (new NativeFinanceAccess($this->container))->policyForCrypto($p['sourceScopeId'], $actor['user'], false);
        } elseif ($op === 'crypto2.exports.certify') {
            $offer = $this->row('offers', $p['offerHash'] ?? null);
            if ($offer['issuer_account_id'] !== $actor['user']['account_id']) {
                throw new NativeError('permission_revoked', 403);
            }
            $this->scope($offer['source_scope_id'], $actor['user']['id'], false);
            (new NativeFinanceAccess($this->container))->policyForCrypto($offer['source_scope_id'], $actor['user'], false);
        }
    }

    public function write($op, $p, $actor, $proof, $command, $key, $batch = null)
    {
        if (($p['variant'] ?? null) === NativeCryptoAccountChoiceExportV2::VARIANT) {
            if ($batch !== null) throw new NativeError('crypto_account_choices_batch_context',409);
            return (new NativeCryptoAccountChoiceExportV2($this->container,$this->bearer,$this->ip))->write($op,$p,$actor,$proof,$command,$key);
        }
        if ($op === 'crypto2.exports.propose') {
            $this->fields($p, ['sourceScopeId','sourceId','subjectNonce','offerProof'], ['sourceProof']);
            $body = $this->publicBody($p['offerProof'], $actor, 'crypto2.exports.offer', "JivieE2EE/exportOffer/v2\n", $key);
            $sourceId = NativeCryptoRecordAddressV2::wireId($p['sourceId']);
            $sid = $this->uuid($p['sourceScopeId']);
            $nonce = $this->uuid($p['subjectNonce']);
            $scopeToken = hash('sha256', "JivieExportScope/v2\n".NativeCryptoCodec::canonical((object)['version' => 2,'serverId' => $this->serverId(),'scopeId' => $body['scopeId'],'sourceScopeId' => $sid]));
            $subjectToken = hash('sha256', "JivieExportSubject/v2\n".NativeCryptoCodec::canonical((object)['version' => 2,'serverId' => $this->serverId(),'scopeId' => $body['scopeId'],'purpose' => $body['purpose'],'sourceScopeToken' => $scopeToken,'sourceId' => $sourceId,'subjectNonce' => $nonce]));
            if ($body['sourceScopeToken'] !== $scopeToken ||
            $body['subjectToken'] !== $subjectToken) {
                throw new NativeError('crypto_export_invalid', 403);
            }
            $offer = ['source_scope_id' => $sid,'source_id' => $sourceId];
            $future = isset($p['sourceProof']) ? $this->futureSource($p['sourceProof'], $body, $actor, $key) : null;
            $this->source($offer, $body, $actor, $future);
            if ($body['purpose'] === 'paymentSource') {
                $this->target($body['scopeId'], $body['membershipHeadHash'], $actor, false);
            }
            $head = $this->scopes()->current($body['scopeId']);
            if (!$head ||
            $head['head_hash'] !== $body['membershipHeadHash']) {
                throw new NativeError('crypto_scope_head_changed', 409);
            }
            $pending = $this->one('SELECT COUNT(*) n FROM familyhub_crypto_export_offers_v2 WHERE issuer_account_id=? AND expires_at>?', [$actor['user']['account_id'],time()]);
            if ((int)$pending['n'] >= 64) {
                throw new NativeError('crypto_export_offers_full', 409);
            }
            $hash = NativeCryptoV2Codec::hash((object)$p['offerProof']);
            $old = $this->one('SELECT hash FROM familyhub_crypto_export_offers_v2 WHERE hash=?', [$hash]);
            if (!$old) {
                $this->change('INSERT INTO familyhub_crypto_export_offers_v2 VALUES(?,?,?,?,?,?,?,?,?,?)', [$hash,$sid,$sourceId,$nonce,$body['scopeId'],$head['head_hash'],$actor['user']['account_id'],json_encode($p['offerProof'], JSON_THROW_ON_ERROR),time(),time() + 1800]);
            }
            return ['offerHash' => $hash];
        }
        if ($op === 'crypto2.exports.delegate') {
            $this->fields($p, ['scopeId','membershipHeadHash','expectedAccessRevision','authorDirectoryHeadHash','delegationId','purpose','offerHash','issuerAccountId','issuerDirectoryHeadHash','issuerRootSigningKeyBase64','issuerRootEncryptionKeyBase64','issuerIdentityEpochId','issuerDeviceSnapshotHash','sourceScopeToken','subjectToken','permittedFields','bridgeRecipient']);
            [$scope,$targetHead] = $this->target($p['scopeId'], $p['membershipHeadHash'], $actor, true);
            $this->freshMembers($targetHead,$actor);
            $this->scopes()->currentAuthorReference($p['authorDirectoryHeadHash'], $actor);
            $this->uuid($p['delegationId']);
            if ($p['expectedAccessRevision'] !== (int)$scope['effective_access_revision']) {
                throw new NativeError('crypto_access_changed', 409);
            }
            $offer = $this->row('offers', $p['offerHash']);
            [$body] = NativeCryptoCodec::decode(json_decode($offer['authorization'], true, 34, JSON_THROW_ON_ERROR));
            if ((int)$offer['expires_at'] <= time() ||
            $offer['target_scope_id'] !== $p['scopeId'] ||
            $offer['target_head_hash'] !== $p['membershipHeadHash'] ||
            $offer['issuer_account_id'] !== $p['issuerAccountId']) {
                throw new NativeError('crypto_export_offer_expired', 409);
            }
            foreach (['purpose','sourceScopeToken','subjectToken','permittedFields'] as $field) {
                if ($body[$field] !== $p[$field]) {
                    throw new NativeError('crypto_export_invalid', 403);
                }
            }
            $this->validateIssuerPin($p);
            if ($p['bridgeRecipient'] !== null) {
                $this->recipient($p['bridgeRecipient'], $p['scopeId']);
            } elseif ($p['purpose'] === 'financeAccountChoice') {
                throw new NativeError('crypto_export_recipient_required', 409);
            }
            $hash = NativeCryptoV2Codec::hash((object)$proof);
            $existing = $this->one('SELECT hash FROM familyhub_crypto_export_delegations_v2 WHERE offer_hash=?', [$p['offerHash']]);
            if ($existing) {
                throw new NativeError('crypto_export_delegation_immutable', 409);
            }
            $this->change('INSERT INTO familyhub_crypto_export_delegations_v2 VALUES(?,?,?,?,?,?)', [$hash,$p['scopeId'],$p['membershipHeadHash'],$p['offerHash'],$p['issuerAccountId'],json_encode($proof, JSON_THROW_ON_ERROR)]);
            return ['delegationHash' => $hash];
        }
        if ($op !== 'crypto2.exports.certify') {
            throw new NativeError('unsupported_operation', 404);
        }
        $this->fields($p, ['offerHash','delegationHash','sourceRevision','sourceRecordProofHash','certificateProof']);
        $offer = $this->row('offers', $p['offerHash']);
        $delegation = $this->row('delegations', $p['delegationHash']);
        if ((int)$offer['expires_at'] <= time()) {
            throw new NativeError('crypto_export_offer_expired', 409);
        }
        [$delegateCommand] = NativeCryptoCodec::decode(json_decode($delegation['authorization'], true, 34, JSON_THROW_ON_ERROR));
        $d = $delegateCommand['payload'];
        if ($offer['issuer_account_id'] !== $actor['user']['account_id'] ||
            $delegation['offer_hash'] !== $p['offerHash']) {
            throw new NativeError('permission_revoked', 403);
        }
        $body = $this->publicBody($p['certificateProof'], $actor, 'crypto2.exports.certificate', "JivieE2EE/scopedExport/v2\n", $key);
        if ($batch === null && ($body['batchContext'] ?? null) !== null) {
            throw new NativeError('crypto_export_batch_required', 409);
        }
        if ($batch !== null) {
            $this->batchContext($body['batchContext'] ?? null, $batch);
        }
        foreach (['purpose','scopeId','membershipHeadHash','sourceScopeToken','subjectToken','permittedFields'] as $field) {
            if ($body[$field] !== $d[$field]) {
                throw new NativeError('crypto_export_invalid', 403);
            }
        }
        if ($body['offerHash'] !== $p['offerHash'] ||
            $body['delegationProofHash'] !== $p['delegationHash'] ||
            $body['sourceRevision'] !== $p['sourceRevision'] ||
            $body['sourceRecordProofHash'] !== $p['sourceRecordProofHash']) {
            throw new NativeError('crypto_export_invalid', 403);
        }
        $this->validateIssuerPin($d);
        $this->source($offer, $body, $actor, $batch['source'] ?? null);
        $target = $this->one('SELECT * FROM familyhub_scopes WHERE id=?', [$d['scopeId']]);
        $head = $this->scopes()->current($d['scopeId']);
        if (!$target ||
            !$head ||
            $head['head_hash'] !== $d['membershipHeadHash']) {
            throw new NativeError('crypto_scope_head_changed', 409);
        }
        $this->freshMembers($head,$actor);
        $manager = $this->one('SELECT user_id FROM familyhub_accounts WHERE account_id=?', [$delegateCommand['accountId']]);
        if (!$manager) {
            throw new NativeError('permission_revoked', 403);
        }
        $managerScope = $this->scope($d['scopeId'], $manager['user_id'], false);
        $managerActor = ['user' => ['id' => $manager['user_id'],'account_id' => $delegateCommand['accountId']],'device' => ['id' => $delegateCommand['deviceId']]];
        $this->scopes()->manager($head, $managerScope, $managerActor);
        $this->scopes()->currentAuthorReference($d['authorDirectoryHeadHash'], $managerActor);
        if ((int)$managerScope['effective_access_revision'] !== $d['expectedAccessRevision']) {
            throw new NativeError('crypto_access_changed', 409);
        }
        if ($d['bridgeRecipient'] !== null) {
            $this->recipient($d['bridgeRecipient'], $d['scopeId']);
            $bridge = $body['bridge'];
            $this->fields($bridge, ['recipient','requestId','sealedDisclosureBase64','ciphertextHash']);
            if ($bridge['recipient'] !== $d['bridgeRecipient'] ||
            $bridge['requestId'] !== $command['requestId']) {
                throw new NativeError('crypto_export_invalid', 403);
            }
            $cipher = base64_decode($bridge['sealedDisclosureBase64'], true);
            if ($cipher === false ||
            base64_encode($cipher) !== $bridge['sealedDisclosureBase64'] ||
            strlen($cipher) < 48 ||
            strlen($cipher) > 196608 ||
            hash('sha256', $cipher) !== $this->hashValue($bridge['ciphertextHash'])) {
                throw new NativeError('crypto_export_invalid', 403);
            }
        } elseif ($body['bridge'] !== null) {
            throw new NativeError('crypto_export_invalid', 403);
        } else {
            $this->target($d['scopeId'], $d['membershipHeadHash'], $actor, false);
        }
        $hash = NativeCryptoV2Codec::hash((object)$p['certificateProof']);
        $old = $this->one('SELECT hash FROM familyhub_crypto_export_certificates_v2 WHERE hash=?', [$hash]);
        if (!$old) {
            $this->change('INSERT INTO familyhub_crypto_export_certificates_v2 VALUES(?,?,?,?,?,?,?,?,?)', [$hash,$d['scopeId'],$d['membershipHeadHash'],$p['offerHash'],$p['delegationHash'],$body['sourceRevision'],$body['sourceRecordProofHash'],json_encode($p['certificateProof'], JSON_THROW_ON_ERROR),$actor['user']['account_id']]);
        }
        return ['certificateHash' => $hash];
    }

    /** A future offer carries evidence of intent, never a published record or reservation. */
    private function futureSource($proof, $body, $actor, $key)
    {
        [$record, $bytes, $signature] = NativeCryptoCodec::decode($proof);
        (new NativeCryptoRecordProofV2($this->container))->record($record);
        NativeCryptoV2Codec::verify($bytes, $signature, $key, NativeCryptoV2Codec::RECORD_DOMAIN);
        if ($body['purpose'] !== 'paymentSource' || $record['type'] !== 'paymentEvent' ||
            $record['expectedRevision'] !== 0 || $record['deleted'] ||
            $record['serverId'] !== $this->serverId() ||
            $record['accountId'] !== $actor['user']['account_id'] ||
            $record['deviceId'] !== $actor['device']['id'] ||
            $this->one('SELECT id FROM familyhub_crypto_records WHERE scope_id=? AND id=?', [$record['scopeId'], $record['id']])) {
            throw new NativeError('crypto_export_future_source_invalid', 409);
        }
        $this->scopes()->author($record['scopeId'], $record['membershipHeadHash'], $record['epoch'], $record['accessRevision'], $actor, 'finance', true);
        return ['record' => $record, 'recordProof' => $proof];
    }

    private function batchContext($context, $batch)
    {
        if (!is_array($context)) {
            throw new NativeError('crypto_export_batch_binding', 403);
        }
        $this->fields($context, ['batchId', 'sourceOperationId', 'sourceExpectedRevision', 'targetOperationId', 'targetExpectedRevision', 'targetId', 'targetIdentity', 'targetMembershipHeadHash']);
        $source = $batch['source']['record'];
        $target = $batch['target']['record'];
        $expected = [
            'batchId' => $batch['batchId'],
            'sourceOperationId' => $source['operationId'],
            'sourceExpectedRevision' => $source['expectedRevision'],
            'targetOperationId' => $target['operationId'],
            'targetExpectedRevision' => $target['expectedRevision'],
            'targetId' => $target['id'],
            'targetIdentity' => $target['metadata']['identity'],
            'targetMembershipHeadHash' => $target['membershipHeadHash'],
        ];
        if (NativeCryptoCodec::canonical((object)$context) !== NativeCryptoCodec::canonical((object)$expected)) {
            throw new NativeError('crypto_export_batch_binding', 403);
        }
    }

    /** Private outer dispatch is intentionally excluded from every scoped read proof. */
    public function writeBatch($bindings, array $prepared, array $actor, array $command, $key)
    {
        if (!is_array($bindings) || !array_is_list($bindings) || count($bindings) > 32) {
            throw new NativeError('validation_error');
        }
        $seen = [];
        foreach ($bindings as $binding) {
            if (!is_array($binding)) {
                throw new NativeError('validation_error');
            }
            $this->fields($binding, ['sourceScopeId', 'sourceId', 'sourceRecordProofHash', 'targetScopeId', 'targetId', 'delegationHash', 'certificateProof']);
            $source = $prepared[$binding['sourceScopeId'].':'.$binding['sourceId']] ?? null;
            $target = $prepared[$binding['targetScopeId'].':'.$binding['targetId']] ?? null;
            if (!$source || !$target || $source['record']['deleted'] || $target['record']['deleted'] ||
                $source['record']['type'] !== 'paymentEvent' ||
                !in_array($target['record']['type'], ['cashMovement', 'paymentProjection'], true) ||
                $binding['sourceRecordProofHash'] !== $source['recordProofHash']) {
                throw new NativeError('crypto_export_batch_binding', 403);
            }
            $targetKey = $binding['targetScopeId'].':'.$binding['targetId'];
            if (isset($seen[$targetKey])) {
                throw new NativeError('crypto_export_batch_binding', 403);
            }
            $seen[$targetKey] = true;
            [$certificate] = NativeCryptoCodec::decode($binding['certificateProof']);
            if (($certificate['purpose'] ?? null) !== 'paymentSource' ||
                ($certificate['scopeId'] ?? null) !== $binding['targetScopeId'] ||
                ($certificate['membershipHeadHash'] ?? null) !== $target['record']['membershipHeadHash'] ||
                ($certificate['sourceMembershipHeadHash'] ?? null) !== $source['record']['membershipHeadHash']) {
                throw new NativeError('crypto_export_batch_binding', 403);
            }
            $this->write('crypto2.exports.certify', [
                'offerHash' => $certificate['offerHash'] ?? null,
                'delegationHash' => $binding['delegationHash'],
                'sourceRevision' => $source['record']['expectedRevision'] + 1,
                'sourceRecordProofHash' => $source['recordProofHash'],
                'certificateProof' => $binding['certificateProof'],
            ], $actor, $binding['certificateProof'], $command, $key, [
                'source' => $source, 'target' => $target, 'batchId' => $command['payload']['batchId'],
            ]);
        }
    }

    private function validateIssuerPin($p)
    {
        $state = (new NativeCryptoDirectoryV2($this->container))->current($this->uuid($p['issuerAccountId']));
        $ref = $this->one('SELECT device_snapshot_hash FROM familyhub_crypto_directory WHERE account_id=? AND head_hash=?', [$p['issuerAccountId'],$p['issuerDirectoryHeadHash']]);
        if (!$state ||
            !$ref ||
            $ref['device_snapshot_hash'] !== $state['device_snapshot_hash'] ||
            $state['device_snapshot_hash'] !== $p['issuerDeviceSnapshotHash']) {
            throw new NativeError('crypto_member_directory_changed', 409);
        }
        $s = json_decode($state['snapshot'], true, 34, JSON_THROW_ON_ERROR);
        if ($p['issuerRootSigningKeyBase64'] !== $s['rootSigningKeyBase64'] ||
            $p['issuerRootEncryptionKeyBase64'] !== $s['rootEncryptionKeyBase64'] ||
            $p['issuerIdentityEpochId'] !== $s['identityEpochId']) {
            throw new NativeError('crypto_export_issuer_changed', 409);
        }
    }

    private function recipient($r, $sid)
    {
        $this->fields($r, ['accountId','deviceId','directoryHeadHash','deviceSnapshotHash','encryptionPublicKeyBase64']);
        $this->uuid($r['accountId']);
        $this->uuid($r['deviceId']);
        $scope = (new NativeOrganizationAccess($this->container))->visibleScope($sid, $r['accountId']);
        $head = $this->scopes()->current($sid);
        $member = $head ? $this->scopes()->member($this->scopes()->body($head), $r['accountId']) : null;
        $user = $this->one('SELECT user_id FROM familyhub_accounts WHERE account_id=?', [$r['accountId']]);
        if (!$scope ||
            !$member ||
            $member['financeRole'] === 'none' ||
            !$user) {
            throw new NativeError('finance_forbidden', 403);
        }
        (new NativeFinanceAccess($this->container))->policyForCrypto($sid, ['id' => $user['user_id'],'account_id' => $r['accountId']], false);
        $d = new NativeCryptoDirectoryV2($this->container);
        $state = $d->current($r['accountId']);
        $ref = $this->one('SELECT device_snapshot_hash FROM familyhub_crypto_directory WHERE account_id=? AND head_hash=?', [$r['accountId'],$r['directoryHeadHash']]);
        if (!$state ||
            !$ref ||
            $state['device_snapshot_hash'] !== $r['deviceSnapshotHash'] ||
            $ref['device_snapshot_hash'] !== $r['deviceSnapshotHash']) {
            throw new NativeError('crypto_member_directory_changed', 409);
        }
        $snapshot = json_decode($state['snapshot'], true, 34, JSON_THROW_ON_ERROR);
        $device = $d->device($snapshot, $r['deviceId']);
        if (!$device ||
            $device['revokedGeneration'] !== null ||
            $device['identityEpochId'] !== $snapshot['identityEpochId'] ||
            $device['encryptionKeyBase64'] !== $r['encryptionPublicKeyBase64']) {
            throw new NativeError('crypto_export_recipient_changed', 409);
        }
    }

    public function read($op, $p, $actor)
    {
        if (($p['variant']??null)===NativeCryptoAccountChoiceExportV2::VARIANT) return (new NativeCryptoAccountChoiceExportV2($this->container,$this->bearer,$this->ip))->read($op,$p,$actor);
        if ($op === 'crypto2.exports.delegation.forOffer') {
            return $this->delegationForOffer($p, $actor);
        }
        if ($op==='crypto2.exports.evidence.directory') {
            return $this->historicalDirectory($p,$actor);
        }
        if (in_array($op, ['crypto2.exports.recipient.directory','crypto2.exports.delegation.directory'], true)) {
            $this->fields($p, ['delegationHash'], ['afterGeneration','limit']);
            $delegation = $this->row('delegations', $p['delegationHash']);
            if ($delegation['issuer_account_id'] !== $actor['user']['account_id']) {
                throw new NativeError('permission_revoked', 403);
            }
            $offer = $this->row('offers', $delegation['offer_hash']);
            $this->scope($offer['source_scope_id'], $actor['user']['id']);
            (new NativeFinanceAccess($this->container))->policyForCrypto($offer['source_scope_id'], $actor['user'], false, true);
            [$command] = NativeCryptoCodec::decode(json_decode($delegation['authorization'], true, 34, JSON_THROW_ON_ERROR));
            $payload = $command['payload'];
            $head = $this->scopes()->current($delegation['scope_id']);
            if (!$head ||
            $head['head_hash'] !== $delegation['head_hash'] ||
            $payload['bridgeRecipient'] === null) {
                throw new NativeError('crypto_scope_head_changed', 409);
            }
            $this->validateIssuerPin($payload);
            $this->recipient($payload['bridgeRecipient'], $delegation['scope_id']);
            $recipient = $payload['bridgeRecipient'];
            $managerUser = $this->one('SELECT user_id FROM familyhub_accounts WHERE account_id=?', [$command['accountId']]);
            if (!$managerUser) {
                throw new NativeError('permission_revoked', 403);
            }
            $managerActor = ['user' => ['id' => $managerUser['user_id'],'account_id' => $command['accountId']],'device' => ['id' => $command['deviceId']]];
            $managerScope = $this->scope($delegation['scope_id'], $managerUser['user_id']);
            $this->scopes()->manager($head, $managerScope, $managerActor);
            $this->scopes()->currentAuthorReference($payload['authorDirectoryHeadHash'], $managerActor);
            if ($op === 'crypto2.exports.delegation.directory') {
                $recipient = ['accountId' => $command['accountId']];
            }
            $current = (new NativeCryptoDirectoryV2($this->container))->current($recipient['accountId']);
            $after = $p['afterGeneration'] ?? 0;
            $limit = $p['limit'] ?? 20;
            if (!is_int($after) ||
            $after < 0 ||
            !is_int($limit) ||
            $limit < 1 ||
            $limit > 20) {
                throw new NativeError('validation_error');
            }
            $rows = $this->many('SELECT generation,authorization FROM familyhub_crypto_directory WHERE account_id=? AND generation>? ORDER BY generation LIMIT '.($limit + 1), [$recipient['accountId'],$after]);
            $page = array_slice($rows, 0, $limit);
            $out = ['accountId' => $recipient['accountId'],'generation' => (int)$current['generation'],'headHash' => $current['head_hash'],'snapshotHash' => $current['snapshot_hash'],'deviceSnapshotHash' => $current['device_snapshot_hash'],'proofs' => array_map(fn ($r) => json_decode($r['authorization'], true, 34, JSON_THROW_ON_ERROR), $page),'hasMore' => count($rows) > $limit,'nextGeneration' => $page ? (int)end($page)['generation'] : $after];
            if (strlen(json_encode($out, JSON_THROW_ON_ERROR)) > 1250000) {
                throw new NativeError('crypto_directory_page_too_large', 413);
            }
            return $out;
        }
        if ($op === 'crypto2.exports.offers') {
            $this->fields($p, ['scopeId'], ['afterHash','limit']);
            $head = $this->scopes()->current($this->uuid($p['scopeId']));
            $this->target($p['scopeId'], $head['head_hash'] ?? '', $actor, true);
            $after = isset($p['afterHash']) ? $this->hashValue($p['afterHash']) : '';
            $limit = $p['limit'] ?? 20;
            if (!is_int($limit) ||
            $limit < 1 ||
            $limit > 20) {
                throw new NativeError('validation_error');
            }
            $rows = $this->many('SELECT hash,authorization,expires_at FROM familyhub_crypto_export_offers_v2 WHERE target_scope_id=? AND target_head_hash=? AND hash>? AND expires_at>? ORDER BY hash LIMIT '.($limit + 1), [$p['scopeId'],$head['head_hash'],$after,time()]);
            $page = array_slice($rows, 0, $limit);
            return ['offers' => array_map(fn ($r) => ['offerHash' => $r['hash'],'authorization' => json_decode($r['authorization'], true, 34, JSON_THROW_ON_ERROR),'expiresAt' => (int)$r['expires_at']], $page),'hasMore' => count($rows) > $limit,'nextAfterHash' => $page ? end($page)['hash'] : null];
        }
        $certificate = $op === 'crypto2.exports.certificates.get';
        $this->fields($p, ['scopeId',$certificate ? 'certificateHash' : 'delegationHash']);
        $row = $this->row($certificate ? 'certificates' : 'delegations', $p[$certificate ? 'certificateHash' : 'delegationHash']);
        if ($row['scope_id'] !== $p['scopeId']) {
            throw new NativeError('permission_revoked', 403);
        }
        if ($row['issuer_account_id'] === $actor['user']['account_id']) {
            $offer = $this->row('offers', $row['offer_hash']);
            $this->scope($offer['source_scope_id'], $actor['user']['id'], false);
            (new NativeFinanceAccess($this->container))->policyForCrypto($offer['source_scope_id'], $actor['user'], false);
        } else {
            $currentHead = $this->scopes()->current($row['scope_id']);
            if (!$currentHead) {
                throw new NativeError('permission_revoked', 403);
            }
            try {
                $this->target($row['scope_id'], $currentHead['head_hash'], $actor, false);
            } catch (NativeError $error) {
                if ($error->status !== 403) {
                    throw $error;
                }
                $this->target($row['scope_id'], $currentHead['head_hash'], $actor, true);
            }
        }
        $authorization=json_decode($row['authorization'], true, 34, JSON_THROW_ON_ERROR);
        if ($certificate) {
            [$selection]=NativeCryptoCodec::decode($authorization);
            if (($selection['variant']??null)===NativeCryptoAccountChoiceExportV2::VARIANT) {
                (new NativeCryptoAccountChoiceExportV2($this->container,$this->bearer,$this->ip))->available($authorization,$actor);
            }
        }
        return ['authorization' => $authorization];
    }

    private function delegationForOffer($p, $actor)
    {
        $this->fields($p, ['scopeId','offerHash']);
        $offer = $this->row('offers', $p['offerHash']);
        if ($offer['target_scope_id'] !== $this->uuid($p['scopeId'])) {
            throw new NativeError('permission_revoked', 403);
        }
        $head = $this->scopes()->current($p['scopeId']);
        if (!$head || $head['head_hash'] !== $offer['target_head_hash'] || (int)$offer['expires_at'] <= time()) {
            throw new NativeError('crypto_export_offer_expired', 409);
        }
        if ($offer['issuer_account_id'] === $actor['user']['account_id']) {
            $this->scope($offer['source_scope_id'], $actor['user']['id']);
            (new NativeFinanceAccess($this->container))->policyForCrypto($offer['source_scope_id'], $actor['user'], false, true);
        } else {
            $this->target($p['scopeId'], $head['head_hash'], $actor, false);
        }
        $rows = $this->many('SELECT authorization FROM familyhub_crypto_export_delegations_v2 WHERE scope_id=? AND head_hash=? AND offer_hash=? AND issuer_account_id=? ORDER BY hash LIMIT 2', [$p['scopeId'],$head['head_hash'],$offer['hash'],$offer['issuer_account_id']]);
        if (!$rows) {
            return ['authorization' => null];
        }
        if (count($rows) !== 1) {
            throw new NativeError('crypto_export_delegation_ambiguous', 409);
        }
        $proof = json_decode($rows[0]['authorization'], true, 34, JSON_THROW_ON_ERROR);
        [$command] = NativeCryptoCodec::decode($proof);
        $payload = $command['payload'];
        $this->validateIssuerPin($payload);
        $manager = $this->one('SELECT user_id FROM familyhub_accounts WHERE account_id=?', [$command['accountId']]);
        if (!$manager) {
            throw new NativeError('permission_revoked', 403);
        }
        $managerActor = ['user' => ['id' => $manager['user_id'],'account_id' => $command['accountId']],'device' => ['id' => $command['deviceId']]];
        $scope = $this->scope($p['scopeId'], $manager['user_id']);
        $this->scopes()->manager($head, $scope, $managerActor);
        $this->scopes()->currentAuthorReference($payload['authorDirectoryHeadHash'], $managerActor);
        if ($payload['bridgeRecipient'] !== null) {
            $this->recipient($payload['bridgeRecipient'], $p['scopeId']);
        }
        return ['authorization' => $proof];
    }

    /** Historical verification evidence only; it cannot certify a new export. */
    private function historicalDirectory($p, $actor)
    {
        $this->fields($p, ['scopeId','certificateHash','accountId','directoryHeadHash'], ['afterGeneration','limit']);
        $sid = $this->uuid($p['scopeId']);
        $account = $this->uuid($p['accountId']);
        $ref = $this->hashValue($p['directoryHeadHash']);
        $certificate = $this->row('certificates', $p['certificateHash']);
        if ($certificate['scope_id'] !== $sid) {
            throw new NativeError('permission_revoked', 403);
        }
        $current = $this->scopes()->current($sid);
        if (!$current) {
            throw new NativeError('permission_revoked', 403);
        }
        $this->target($sid, $current['head_hash'], $actor, false);
        $historical = $this->scopes()->head($sid, $certificate['head_hash']);
        if (!in_array($historical['state'], ['active','historical'], true)) {
            throw new NativeError('permission_revoked', 403);
        }
        $cursor = $current;
        while ((int)$cursor['epoch'] > (int)$historical['epoch']) {
            $previous = $this->scopes()->head($sid, $cursor['previous_head_hash']);
            if ((int)$previous['epoch'] + 1 !== (int)$cursor['epoch']) {
                throw new NativeError('crypto_scope_chain', 409);
            }
            $cursor = $previous;
        }
        if ($cursor['head_hash'] !== $historical['head_hash']) {
            throw new NativeError('permission_revoked', 403);
        }
        [$body] = NativeCryptoCodec::decode(json_decode($certificate['authorization'], true, 34, JSON_THROW_ON_ERROR));
        $delegation = $this->row('delegations', $certificate['delegation_hash']);
        if ($delegation['scope_id'] !== $sid ||
            $delegation['head_hash'] !== $certificate['head_hash'] ||
            $delegation['offer_hash'] !== $certificate['offer_hash']) {
            throw new NativeError('permission_revoked', 403);
        }
        [$command] = NativeCryptoCodec::decode(json_decode($delegation['authorization'], true, 34, JSON_THROW_ON_ERROR));
        $d = $command['payload'];
        $allowed = [
            $body['accountId'].':'.$body['authorDirectoryHeadHash'] => true,
            $command['accountId'].':'.$d['authorDirectoryHeadHash'] => true,
            $d['issuerAccountId'].':'.$d['issuerDirectoryHeadHash'] => true,
        ];
        if ($d['bridgeRecipient'] !== null) {
            $recipient = $d['bridgeRecipient'];
            $allowed[$recipient['accountId'].':'.$recipient['directoryHeadHash']] = true;
        }
        if (!isset($allowed[$account.':'.$ref])) {
            throw new NativeError('permission_revoked', 403);
        }
        $prefix = $this->one('SELECT generation,head_hash,snapshot_hash,device_snapshot_hash FROM familyhub_crypto_directory WHERE account_id=? AND head_hash=?', [$account,$ref]);
        if (!$prefix) {
            throw new NativeError('crypto_export_evidence_unavailable', 503);
        }
        $after = $p['afterGeneration'] ?? 0;
        $limit = $p['limit'] ?? 20;
        if (!is_int($after) || $after < 0 || $after > (int)$prefix['generation'] ||
            !is_int($limit) || $limit < 1 || $limit > 20) {
            throw new NativeError('validation_error');
        }
        $rows = $this->many('SELECT generation,authorization FROM familyhub_crypto_directory WHERE account_id=? AND generation>? AND generation<=? ORDER BY generation LIMIT '.($limit + 1), [$account,$after,$prefix['generation']]);
        $page = array_slice($rows, 0, $limit);
        $out = [
            'accountId' => $account,
            'generation' => (int)$prefix['generation'],
            'headHash' => $prefix['head_hash'],
            'snapshotHash' => $prefix['snapshot_hash'],
            'deviceSnapshotHash' => $prefix['device_snapshot_hash'],
            'proofs' => array_map(fn ($row) => json_decode($row['authorization'], true, 34, JSON_THROW_ON_ERROR), $page),
            'hasMore' => count($rows) > $limit,
            'nextGeneration' => $page ? (int)end($page)['generation'] : $after,
        ];
        if (strlen(json_encode($out, JSON_THROW_ON_ERROR)) > 1250000) {
            throw new NativeError('crypto_directory_page_too_large', 413);
        }
        return $out;
    }

    /** Scope-limited public directory discovery for an explicitly offered/delegated issuer. */
    public function directoryReference($sid, $headHash, $target, $actor)
    {
        $head = $this->scopes()->current($sid);
        if (!$head ||
            $head['head_hash'] !== $headHash) {
            return null;
        }
        try {
            $this->target($sid,$headHash,$actor,true);
            $offer = $this->one('SELECT authorization FROM familyhub_crypto_export_offers_v2 WHERE target_scope_id=? AND target_head_hash=? AND issuer_account_id=? AND expires_at>? LIMIT 1',[$sid,$headHash,$target,time()]);
            if ($offer) {
                [$body] = NativeCryptoCodec::decode(json_decode($offer['authorization'],true,34,JSON_THROW_ON_ERROR));
                return $body['authorDirectoryHeadHash'];
            }
        } catch (NativeError $error) {
            if ($error->status !== 403) {
                throw $error;
            }
        }
        try {
            $this->target($sid,$headHash,$actor,false);
        } catch (NativeError $error) {
            if ($error->status === 403) {
                return null;
            }
            throw $error;
        }
        $row = $this->one('SELECT authorization FROM familyhub_crypto_export_delegations_v2 WHERE scope_id=? AND head_hash=? AND issuer_account_id=? LIMIT 1',[$sid,$headHash,$target]);
        if (!$row) {
            return null;
        }
        [$c] = NativeCryptoCodec::decode(json_decode($row['authorization'],true,34,JSON_THROW_ON_ERROR));
        return $c['payload']['issuerDirectoryHeadHash'];
    }
}
