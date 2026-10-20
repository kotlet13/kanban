<?php

namespace Kanboard\Plugin\FamilyHub\Model;

/** Signed-directory v2. Preview-v1 bytes and receipts retain their original meaning. */
class NativeCryptoV2Service extends NativeDatabase
{
    protected $cryptoAccess = true;
    public function execute($operation, array $params)
    {
        if (in_array($operation,['crypto2.account.scheduleUse','crypto2.account.scopeDeletion','crypto2.account.projectRelocation'],true)) {
            throw new NativeError('crypto_companion_only',400);
        }
        if (!NativeCryptoService::enabled($this->pdo)) {
            throw new NativeError('crypto_unavailable', 503);
        }
        $maintenanceLease = (str_starts_with($operation, 'crypto2.migration.') || $operation === 'crypto2.scope.lifecycle.attestBaseline') ? NativeCryptoMaintenanceLease::acquire(true) : null;
        $this->rate([['crypto2-ip:'.$this->ip,600,60]]);
        $decoded = null;
        $deliveryToken = null;
        $captureSecrets=null;
        if (array_key_exists('captureSecrets',$params)) {
            if (!in_array($operation,['crypto2.migration.capture.bind','crypto2.migration.recordsStage'],true)) {
                throw new NativeError('validation_error');
            }
            $captureSecrets=$params['captureSecrets'];
            unset($params['captureSecrets']);
            if (!is_array($captureSecrets) || !array_is_list($captureSecrets) || count($captureSecrets)>32) {
                throw new NativeError('validation_error');
            }
            foreach ($captureSecrets as $secret) {
                $this->fields($secret,['bindingId','sourceTable','sourceId','saltBase64']);
                $this->uuid($secret['bindingId']);
                if (!is_string($secret['sourceTable']) || strlen($secret['sourceTable'])<1 || strlen($secret['sourceTable'])>80 || !is_string($secret['sourceId']) || strlen($secret['sourceId'])<1 || strlen($secret['sourceId'])>256 || str_contains($secret['sourceId'],"\0")) {
                    throw new NativeError('validation_error');
                }
                NativeCryptoCodec::base64($secret['saltBase64'],32,32);
            }
        }

        if (in_array($operation, ['crypto2.invitations.create', 'crypto2.invitations.resend'], true) && array_key_exists('deliveryToken', $params)) {
            $deliveryToken = $params['deliveryToken'];
            unset($params['deliveryToken']);
        }
        $readOperations = ['crypto2.access.pending','crypto2.access.consequences','crypto2.access.invitationConsequences','crypto2.access.portions','crypto2.exports.offers','crypto2.exports.delegation.get','crypto2.exports.certificates.get','crypto2.exports.recipient.directory','crypto2.exports.delegation.directory','crypto2.migration.blob.get','crypto2.migration.capture.discover','crypto2.migration.capture.sources','crypto2.migration.capture.sourcePage','crypto2.migration.capture.sourceCell','crypto2.migration.capture.file','crypto2.migration.capture.fileChunk','crypto2.migration.capture.inventory','crypto2.migration.capture.status','crypto2.scope.financePolicy.current','crypto2.scope.lifecycle.pendingDelegations','crypto2.scope.lifecycle.baseline','crypto2.scope.lifecycle.current','crypto2.scope.lifecycle.list','crypto2.scope.lifecycle.children','crypto2.invitations.status', 'crypto2.invitations.acceptance', 'crypto2.invitations.resolve', 'crypto2.invitations.list', 'crypto2.invitations.pending', 'crypto2.invitations.preview', 'crypto2.invitations.directory', 'crypto2.account.scopeObservation.put', 'crypto2.account.scopeObservations', 'crypto2.account.status', 'crypto2.account.protectionCatalog', 'crypto2.account.entries', 'crypto2.account.directory', 'crypto2.receipt.get', 'crypto2.scopes.catalog', 'crypto2.directory.status', 'crypto2.directory.read', 'crypto2.scope.headGet', 'crypto2.scope.closureGet', 'crypto2.grants.manifest', 'crypto2.grants.list', 'crypto2.records.pull', 'crypto2.records.historyGet', 'crypto2.records.history', 'crypto2.blob.get', 'crypto2.domain.inventory', 'crypto2.domain.checkpoints', 'crypto2.table.lease', 'crypto2.reminders.list', 'crypto2.inbox.list', 'crypto2.inbox.sync', 'crypto2.inbox.open', 'crypto2.inbox.group', 'crypto2.inbox.preferences.get', 'crypto2.scope.financeDraft.list', 'crypto2.scope.financeDraft.get', 'crypto2.scope.keyDraft.list', 'crypto2.scope.keyDraft.get', 'crypto2.migration.discover', 'crypto2.migration.status', 'crypto2.migration.inventory', 'crypto2.migration.exportPage', 'crypto2.migration.exportCell', 'crypto2.migration.archiveGet', 'crypto2.migration.fileList', 'crypto2.migration.fileChunk', 'crypto2.migration.stagedRecords', 'crypto2.migration.blob.get', 'crypto2.migration.capture.discover','crypto2.migration.capture.sources','crypto2.migration.capture.sourcePage','crypto2.migration.capture.sourceCell','crypto2.migration.capture.file','crypto2.migration.capture.fileChunk','crypto2.migration.capture.inventory', 'crypto2.migration.capture.status', 'crypto2.legacy.lookup'];
        $readOperations=array_merge($readOperations,['crypto2.access.leaveRequests','crypto2.access.leaveStatus','crypto2.inlineDelete.preview','crypto2.inlineDelete.graph','crypto2.inlineDelete.evidence']);
        $readOperations=array_merge($readOperations,['crypto2.projectRelocation.targetPreview','crypto2.projectRelocation.status','crypto2.projectRelocation.evidence','crypto2.projectRelocation.own','crypto2.projectRelocation.auditSources','crypto2.projectRelocation.audit','crypto2.projectRelocation.routingUse','crypto2.projectRelocation.routingOwn']);
        $readOperations[] = 'crypto2.scheduling.uses';
        $readOperations[] = 'crypto2.migration.generation.status';
        $readOperations[] = 'crypto2.migration.capture.commitments';
        $readOperations[] = 'crypto2.migration.capture.topology';
        $readOperations[] = 'crypto2.migration.structure.targets';
        $readOperations[] = 'crypto2.migration.structure.contexts';
        $readOperations[] = 'crypto2.migration.notifications.transforms';
        $readOperations[] = 'crypto2.migration.invitations.bridges';
        $readOperations[] = 'crypto2.invitations.bridgeDigests';
        $readOperations[] = 'crypto2.scheduling.migrationWithdrawalEvidence';
        $readOperations[] = 'crypto2.scheduling.migrationEvidence';
        $readOperations[] = 'crypto2.migration.audit.artifact';
        $readOperations[] = 'crypto2.migration.audit.list';
        $readOperations[] = 'crypto2.migration.domains.get';
        $readOperations[] = 'crypto2.migration.domains.leaves';
        $readOperations[] = 'crypto2.migration.activation';
        $readOperations[] = 'crypto2.migration.activation.control';
        $readOperations[] = 'crypto2.migration.activation.refs';
        $readOperations[] = 'crypto2.migration.origin';
        $readOperations[] = 'crypto2.migration.ownAttestation';
        foreach (['crypto2.scope.deletionPreview','crypto2.scope.deletionStatus','crypto2.scope.deletionHead','crypto2.scope.deletionDirectory'] as $deletionRead) {
            $readOperations[]=$deletionRead;
        }
        $readOperations[] = 'crypto2.scheduling.own';
        $readOperations[] = 'crypto2.exports.evidence.directory';
        $readOperations=array_merge($readOperations,['crypto2.migration.legacy.status','crypto2.migration.legacy.inventory','crypto2.migration.legacy.lookup']);
        $readOperations[] = 'crypto2.moderation.reportPreview';
        $readOperations[] = 'crypto2.moderation.disclosure.status';
        $readOperations[] = 'crypto2.exports.delegation.forOffer';
        $readOperations[] = 'crypto2.authority.snapshot';
        if (!in_array($operation, $readOperations, true)) {
            $decoded = NativeCryptoCodec::decode($params);
            $command = $decoded[0];
            $this->fields($command, ['version','operation','requestId','serverId','accountId','deviceId','signer','payload']);
            if ($command['version'] !== 2 || $command['operation'] !== $operation || !is_array($command['payload'])) {
                throw new NativeError('crypto_identity_mismatch', 403);
            }
            foreach (['requestId', 'serverId', 'accountId', 'deviceId'] as $field) {
                $this->uuid($command[$field]);
            }
            if ($operation === 'crypto2.scope.headPut') {
                (new NativeCryptoScopeV2($this->container))->validateProposal($command['payload']);
            }
            if ($operation === 'crypto2.records.batch') {
                $proofs = $command['payload']['records'] ?? null;
                if (!is_array($proofs) || !array_is_list($proofs) || count($proofs) < 1 || count($proofs) > 32) {
                    throw new NativeError('validation_error');
                }
                foreach ($proofs as $proof) {
                    [$record] = NativeCryptoCodec::decode($proof);
                    (new NativeCryptoRecordProofV2($this->container))->record($record);
                }
            }
        }
        $result = $this->transaction(function () use ($operation, $params, $decoded, $deliveryToken, $captureSecrets) {
            if (in_array($operation, ['crypto2.invitations.preview', 'crypto2.invitations.directory','crypto2.invitations.bridgeDigests'], true) && isset($params['token'])) {
                return (new NativeCryptoInvitationV2($this->container, $this->bearer, $this->ip))->publicRead($operation, $params);
            }
            $actor = $this->actor();
            $account = $actor['user']['account_id'];
            $directory = new NativeCryptoDirectoryV2($this->container, $this->bearer, $this->ip);
            $current = $directory->current($account);
            if ($operation === 'crypto2.authority.snapshot') {
                return (new NativeCryptoAuthoritySnapshotV2($this->container, $this->bearer, $this->ip))->read(
                    $params, $actor, $this->status($account, $current),
                    fn($page)=> $this->logPage($page, $account, $current)
                );
            }
            if ($operation === 'crypto2.account.scopeObservation.put') {
                (new NativeConnectedWritePolicy($this->container, $this->bearer, $this->ip))->requireAccount($account);
                $directory->authorizeContent(['signer'=>'device','deviceId'=>$actor['device']['id']],$current);
                return (new NativeCryptoObservationV2($this->container, $this->bearer, $this->ip))->put($params,$actor);
            }
            if ($operation === 'crypto2.account.scopeObservations') {
                return (new NativeCryptoObservationV2($this->container, $this->bearer, $this->ip))->read($params,$actor);
            }
            if ($operation === 'crypto2.account.protectionCatalog') {
                $this->fields($params, []);
                return (new NativeCryptoScopeV2($this->container, $this->bearer, $this->ip))->protectionCatalog($actor) + ['deviceSnapshotHash' => $current['device_snapshot_hash'] ?? null];
            }
            if ($operation === 'crypto2.account.status') {
                $this->fields($params, []);
                return $this->status($account, $current);
            }
            if ($operation === 'crypto2.account.entries') {
                return $this->entries($params, $account, $current);
            }
            if ($operation === 'crypto2.account.directory') {
                return $this->logPage($params, $account, $current);
            }
            if ($operation === 'crypto2.receipt.get') {
                return $this->receipt($params, $account, $actor);
            }
            if (in_array($operation, ['crypto2.invitations.status', 'crypto2.invitations.acceptance', 'crypto2.invitations.resolve', 'crypto2.invitations.list', 'crypto2.invitations.pending', 'crypto2.invitations.preview', 'crypto2.invitations.directory','crypto2.invitations.bridgeDigests'], true)) {
                return (new NativeCryptoInvitationV2($this->container, $this->bearer, $this->ip))->read($operation, $params, $actor);
            }
            $scopes = new NativeCryptoScopeV2($this->container, $this->bearer, $this->ip);
            if (in_array($operation,['crypto2.scope.deletionPreview','crypto2.scope.deletionStatus','crypto2.scope.deletionHead','crypto2.scope.deletionDirectory'],true)) {
                $deletion=new NativeCryptoScopeDeletionV2($this->container,$this->bearer,$this->ip);
                return match ($operation) {
                    'crypto2.scope.deletionPreview'=>$deletion->preview($params,$actor),
                    'crypto2.scope.deletionStatus'=>$deletion->status($params,$actor),
                    'crypto2.scope.deletionHead'=>$deletion->head($params,$actor),
                    'crypto2.scope.deletionDirectory'=>$deletion->directory($params,$actor),
                };
            }
            if ($operation === 'crypto2.moderation.reportPreview') {
                return (new NativeCryptoModerationV2($this->container, $this->bearer, $this->ip))->preview($params, $actor);
            }
            if ($operation === 'crypto2.moderation.disclosure.status') {
                return (new NativeCryptoModerationDisclosureV2($this->container, $this->bearer, $this->ip))->status($params, $actor);
            }
            if (in_array($operation,['crypto2.exports.delegation.forOffer','crypto2.exports.offers','crypto2.exports.delegation.get','crypto2.exports.certificates.get','crypto2.exports.recipient.directory','crypto2.exports.delegation.directory','crypto2.exports.evidence.directory'],true)) {
                return (new NativeCryptoExportV2($this->container,$this->bearer,$this->ip))->read($operation,$params,$actor);
            }
            if ($operation === 'crypto2.scopes.catalog') {
                return $scopes->catalog($params, $actor);
            }
            if (in_array($operation, ['crypto2.directory.status', 'crypto2.directory.read'], true)) {
                return $scopes->directoryRead($operation, $params, $actor);
            }
            if (in_array($operation,['crypto2.migration.legacy.status','crypto2.migration.legacy.inventory','crypto2.migration.legacy.lookup'],true)) {
                return (new NativeCryptoMigrationV2($this->container,$this->bearer,$this->ip))->read($operation,$params,$actor);
            }
            if (in_array($operation,['crypto2.migration.generation.status','crypto2.migration.capture.topology','crypto2.migration.capture.commitments','crypto2.migration.structure.targets','crypto2.migration.structure.contexts','crypto2.migration.notifications.transforms','crypto2.migration.invitations.bridges','crypto2.migration.audit.artifact','crypto2.migration.audit.list','crypto2.migration.domains.get','crypto2.migration.domains.leaves','crypto2.migration.activation','crypto2.migration.activation.control','crypto2.migration.activation.refs','crypto2.migration.origin','crypto2.migration.ownAttestation'],true)) {
                return (new NativeCryptoMigrationV2($this->container,$this->bearer,$this->ip))->read($operation,$params,$actor);
            }
            if ($operation === 'crypto2.scheduling.migrationWithdrawalEvidence') {
                return (new NativeCryptoMigrationNotificationStageV3($this->container,$this->bearer,$this->ip))->withdrawalEvidence($params,$actor);
            }
            if ($operation === 'crypto2.scheduling.migrationEvidence') {
                return (new NativeCryptoMigrationNotificationReadV3($this->container,$this->bearer,$this->ip))->read($params,$actor);
            }
            if (in_array($operation, ['crypto2.scope.headGet', 'crypto2.scope.closureGet', 'crypto2.grants.manifest', 'crypto2.grants.list'], true)) {
                return $scopes->read($operation, $params, $actor);
            }
            if (in_array($operation, ['crypto2.migration.discover', 'crypto2.migration.status', 'crypto2.migration.inventory', 'crypto2.migration.exportPage', 'crypto2.migration.exportCell', 'crypto2.migration.archiveGet', 'crypto2.migration.fileList', 'crypto2.migration.fileChunk', 'crypto2.migration.stagedRecords', 'crypto2.migration.blob.get', 'crypto2.migration.capture.discover','crypto2.migration.capture.sources','crypto2.migration.capture.sourcePage','crypto2.migration.capture.sourceCell','crypto2.migration.capture.file','crypto2.migration.capture.fileChunk','crypto2.migration.capture.inventory', 'crypto2.migration.capture.status', 'crypto2.legacy.lookup'], true)) {
                return (new NativeCryptoMigrationV2($this->container, $this->bearer, $this->ip))->read($operation, $params, $actor);
            }
            if (in_array($operation, ['crypto2.scope.keyDraft.list', 'crypto2.scope.keyDraft.get'], true)) {
                return (new NativeCryptoKeyContributionV2($this->container, $this->bearer, $this->ip))->read($operation, $params, $actor);
            }
            if (in_array($operation, ['crypto2.scope.financeDraft.list', 'crypto2.scope.financeDraft.get'], true)) {
                return (new NativeCryptoFinanceContributionV2($this->container, $this->bearer, $this->ip))->read($operation, $params, $actor);
            }
            if ($operation === 'crypto2.scheduling.uses') {
                return (new NativeCryptoSchedulingUseV2($this->container,$this->bearer,$this->ip))->read($params,$actor);
            }
            if ($operation === 'crypto2.scheduling.own') {
                return (new NativeCryptoSchedulingUseV2($this->container,$this->bearer,$this->ip))->own($params,$actor);
            }
            if (in_array($operation, ['crypto2.reminders.list', 'crypto2.inbox.list', 'crypto2.inbox.sync', 'crypto2.inbox.open', 'crypto2.inbox.group', 'crypto2.inbox.preferences.get'], true)) {
                return (new NativeCryptoNotificationV2($this->container, $this->bearer, $this->ip))->read($operation, $params, $actor);
            }
            if (in_array($operation,['crypto2.access.leaveRequests','crypto2.access.leaveStatus'],true)) {
                return (new NativeCryptoLeaveV2($this->container,$this->bearer,$this->ip))->read($operation,$params,$actor);
            }
            if (in_array($operation,['crypto2.projectRelocation.targetPreview','crypto2.projectRelocation.status','crypto2.projectRelocation.evidence','crypto2.projectRelocation.own','crypto2.projectRelocation.auditSources','crypto2.projectRelocation.audit','crypto2.projectRelocation.routingUse','crypto2.projectRelocation.routingOwn'],true)) {
                return match($operation) {
                    'crypto2.projectRelocation.targetPreview'=>(new NativeCryptoProjectRelocationV2($this->container,$this->bearer,$this->ip))->targetPreview($params,$actor),
                    'crypto2.projectRelocation.status'=>(new NativeCryptoProjectRelocationV2($this->container,$this->bearer,$this->ip))->status($params,$actor),
                    'crypto2.projectRelocation.evidence'=>(new NativeCryptoProjectRelocationPublicationV2($this->container,$this->bearer,$this->ip))->evidence($params,$actor),
                    'crypto2.projectRelocation.own'=>(new NativeCryptoProjectRelocationPublicationV2($this->container,$this->bearer,$this->ip))->own($params,$actor),
                    'crypto2.projectRelocation.auditSources'=>(new NativeCryptoProjectRelocationAuditV2($this->container,$this->bearer,$this->ip))->sources($params,$actor),
                    'crypto2.projectRelocation.audit'=>(new NativeCryptoProjectRelocationAuditV2($this->container,$this->bearer,$this->ip))->read($params,$actor),
                    'crypto2.projectRelocation.routingUse'=>(new NativeCryptoProjectRelocationNotificationsV2($this->container,$this->bearer,$this->ip))->useEvidence($params,$actor),
                    'crypto2.projectRelocation.routingOwn'=>(new NativeCryptoProjectRelocationNotificationsV2($this->container,$this->bearer,$this->ip))->own($params,$actor),
                };
            }
            if (in_array($operation,['crypto2.inlineDelete.preview','crypto2.inlineDelete.graph','crypto2.inlineDelete.evidence'],true)) {
                $inline=new NativeCryptoInlineDeletionV2($this->container,$this->bearer,$this->ip);
                return match ($operation) {
                    'crypto2.inlineDelete.preview'=>$inline->preview($params,$actor),
                    'crypto2.inlineDelete.graph'=>$inline->leaves($params,$actor),
                    'crypto2.inlineDelete.evidence'=>$inline->evidence($params,$actor),
                };
            }
            if (in_array($operation,['crypto2.access.pending','crypto2.access.consequences','crypto2.access.invitationConsequences','crypto2.access.portions'],true)) {
                return (new NativeCryptoAccessV2($this->container,$this->bearer,$this->ip))->read($operation,$params,$actor);
            }
            if ($operation === 'crypto2.scope.financePolicy.current') {
                return (new NativeCryptoFinancePolicyV2($this->container, $this->bearer, $this->ip))->read($params, $actor);
            }
            if (in_array($operation, ['crypto2.scope.lifecycle.pendingDelegations','crypto2.scope.lifecycle.baseline','crypto2.scope.lifecycle.current','crypto2.scope.lifecycle.list','crypto2.scope.lifecycle.children'], true)) {
                return (new NativeCryptoLifecycleV2($this->container, $this->bearer, $this->ip))->read($operation, $params, $actor);
            }
            if ($operation === 'crypto2.table.lease') {
                return (new NativeCryptoTableV2($this->container, $this->bearer, $this->ip))->read($params, $actor);
            }
            if (in_array($operation, ['crypto2.domain.inventory', 'crypto2.domain.checkpoints'], true)) {
                return (new NativeCryptoCheckpointV2($this->container, $this->bearer, $this->ip))->read($operation, $params, $actor);
            }
            if (in_array($operation, ['crypto2.records.pull', 'crypto2.records.historyGet', 'crypto2.records.history', 'crypto2.blob.get'], true)) {
                return (new NativeCryptoStorageV2($this->container, $this->bearer, $this->ip))->read($operation, $params, $actor);
            }
            [$command,$bytes,$signature,$digest] = $decoded;
            $this->fields($command, ['version','operation','requestId','serverId','accountId','deviceId','signer','payload']);
            if ($command['version'] !== 2 || $command['operation'] !== $operation || $command['serverId'] !== $this->serverId() || $command['accountId'] !== $account || $command['deviceId'] !== $actor['device']['id'] || !is_array($command['payload'])) {
                throw new NativeError('crypto_identity_mismatch', 403);
            }
            $accountMutation = str_starts_with($operation, 'crypto2.account.') || str_starts_with($operation, 'crypto2.device.');
            $request = $this->uuid($command['requestId']);
            $saved = $this->one('SELECT * FROM familyhub_crypto_receipts WHERE account_id=? AND request_id=?', [$account,$request]);
            // An exact previously authenticated account proof is historical evidence, not a new grant of authority.
            // In particular the old root is no longer current after a successful rotateRoot with a lost ACK.
            if ($saved) {
                if (!hash_equals($saved['request_hash'], $digest)) {
                    throw new NativeError('idempotency_mismatch', 409);
                }$original = json_decode($saved['authorization'], true, 34, JSON_THROW_ON_ERROR);
                $digestOnly = ($original['format'] ?? null) === 'moderationReceiptDigest2';
                $same = $digestOnly
                    ? $this->moderationReceipt($operation) && $original['operation'] === $operation &&
                        $original['commandHash'] === $digest && $original['signatureBase64'] === $params['signatureBase64']
                    : $original['commandBase64'] === $params['commandBase64'] && $original['signatureBase64'] === $params['signatureBase64'];
                if (!$same) {
                    throw new NativeError('crypto_signature_invalid', 403);
                }
                if (!$accountMutation && !$this->minimalLifecycleReceipt($command, $saved) && !$this->minimalLeaveReceipt($command, $saved) && !$this->minimalModerationReceipt($operation, $saved)) {
                    $this->replayAccess($command['payload'], $actor, $command['operation']);
                }
                (new NativeCryptoModerationAvailabilityV2($this->container,$this->bearer,$this->ip))->assertReceipt($saved);
                return $this->savedResult($saved);
            }
            if (!in_array($operation, ['crypto2.moderation.disclosure.begin','crypto2.moderation.disclosure.chunk','crypto2.moderation.disclosure.complete','crypto2.moderation.disclosure.abort','crypto2.moderation.report', 'crypto2.device.revoke', 'crypto2.account.recoveryStart', 'crypto2.account.recoverEpoch', 'crypto2.scope.cancel', 'crypto2.scope.financeDraft.cancel', 'crypto2.scope.keyDraft.cancel', 'crypto2.table.release', 'crypto2.blob.abort', 'crypto2.reminders.cancel', 'crypto2.scope.lifecycle.cancel', 'crypto2.access.cancel', 'crypto2.inbox.read', 'crypto2.inbox.preferences.set'], true)) {
                (new NativeConnectedWritePolicy($this->container, $this->bearer, $this->ip))->requireAccount($account);
            }
            if (!$accountMutation) {
                $this->replayAccess($command['payload'], $actor, $command['operation']);
            }
            $key = $accountMutation ? $directory->authorize($command, $current) : $directory->authorizeContent($command, $current);
            NativeCryptoV2Codec::verify($bytes, $signature, $key);
            $this->uploadPolicy($operation, $command['payload'], $actor);
            $currentCas = ($command['payload']['expectedGeneration'] ?? null) === (int)($current['generation'] ?? 0) && ($command['payload']['previousHeadHash'] ?? null) === ($current['head_hash'] ?? NativeCryptoDirectoryV2::ZERO);
            if ($currentCas && ($operation === 'crypto2.account.recoveryStart' || in_array($operation, ['crypto2.account.recoverEpoch','crypto2.account.rotateRoot','crypto2.device.add'], true) && $command['signer'] === 'root' && !$this->hasRecoveryStart($current, $command['deviceId']))) {
                $retry = $this->recoveryRate($account);
                if ($retry > 0) {
                    return new NativeError('rate_limited', 429, ['retryAfter' => $retry]);
                }
            }
            $proof = ['commandBase64' => $params['commandBase64'],'signatureBase64' => $params['signatureBase64']];
            $status = 200;
            $this->pdo->exec('SAVEPOINT crypto2_command');
            try {
                if ($accountMutation) {
                    $snapshot = $directory->reduce($command, $current);
                    $this->project($command, $proof, $snapshot, $current, $actor);
                    if ($operation === 'crypto2.account.scopeObserve') {
                        (new NativeCryptoObservationV2($this->container))->includeEvent($command,(int)$current['generation']+1);
                    }
                    $out = $directory->append($command, $proof, $snapshot);
                } elseif (in_array($operation, ['crypto2.invitations.create', 'crypto2.invitations.resend', 'crypto2.invitations.revoke', 'crypto2.invitations.accept'], true)) {
                    $out = (new NativeCryptoInvitationV2($this->container, $this->bearer, $this->ip))->write($operation, $command['payload'], $actor, $proof, $deliveryToken);
                } elseif ($operation === 'crypto2.moderation.report') {
                    $out = (new NativeCryptoModerationV2($this->container, $this->bearer, $this->ip))->report($command['payload'], $actor, $proof, $command);
                } elseif (in_array($operation, ['crypto2.moderation.disclosure.begin','crypto2.moderation.disclosure.chunk','crypto2.moderation.disclosure.complete','crypto2.moderation.disclosure.abort'], true)) {
                    $out = (new NativeCryptoModerationDisclosureV2($this->container, $this->bearer, $this->ip))->write($operation, $command['payload'], $actor, $proof);
                } elseif (in_array($operation,['crypto2.exports.propose','crypto2.exports.delegate','crypto2.exports.certify'],true)) {
                    $out=(new NativeCryptoExportV2($this->container,$this->bearer,$this->ip))->write($operation,$command['payload'],$actor,$proof,$command,$key);
                } elseif (in_array($operation,['crypto2.access.leaveRequest','crypto2.access.leaveCancel'],true)) {
                    $out=(new NativeCryptoLeaveV2($this->container,$this->bearer,$this->ip))->write($operation,$command['payload'],$actor,$proof,$command);
                } elseif (in_array($operation,['crypto2.projectRelocation.prepare','crypto2.projectRelocation.sources','crypto2.projectRelocation.origin','crypto2.projectRelocation.targetCommand','crypto2.projectRelocation.targetActivation','crypto2.projectRelocation.records','crypto2.projectRelocation.blob','crypto2.projectRelocation.auditStage','crypto2.projectRelocation.notificationCandidates','crypto2.projectRelocation.notificationStage','crypto2.projectRelocation.commit','crypto2.projectRelocation.cancel'],true)) {
                    $relocation=new NativeCryptoProjectRelocationV2($this->container,$this->bearer,$this->ip);
                    $stage=new NativeCryptoProjectRelocationStageV2($this->container,$this->bearer,$this->ip);
                    $out=match($operation) {
                        'crypto2.projectRelocation.prepare'=>$relocation->prepare($command['payload'],$actor,$proof,$command,$key),
                        'crypto2.projectRelocation.sources'=>$relocation->sources($command['payload'],$actor),
                        'crypto2.projectRelocation.origin'=>$relocation->targetOrigin($command['payload'],$actor,$key),
                        'crypto2.projectRelocation.targetCommand'=>$relocation->targetCommand($command['payload'],$actor,$command,$key),
                        'crypto2.projectRelocation.targetActivation'=>$relocation->targetActivation($command['payload'],$actor,$key),
                        'crypto2.projectRelocation.records'=>$stage->records($command['payload'],$actor,$proof,$command,$key),
                        'crypto2.projectRelocation.blob'=>$stage->blob($command['payload'],$actor,$proof,$command,$key),
                        'crypto2.projectRelocation.auditStage'=>(new NativeCryptoProjectRelocationAuditV2($this->container,$this->bearer,$this->ip))->stage($command['payload'],$actor,$proof,$command,$key),
                        'crypto2.projectRelocation.notificationCandidates'=>(new NativeCryptoProjectRelocationNotificationsV2($this->container,$this->bearer,$this->ip))->discover($command['payload'],$actor,$command,$key),
                        'crypto2.projectRelocation.notificationStage'=>(new NativeCryptoProjectRelocationNotificationsV2($this->container,$this->bearer,$this->ip))->stage($command['payload'],$actor,$command,$key),
                        'crypto2.projectRelocation.commit'=>(new NativeCryptoProjectRelocationCommitV2($this->container,$this->bearer,$this->ip))->commit($command['payload'],$actor,$proof,$command,$key),
                        'crypto2.projectRelocation.cancel'=>$relocation->cancel($command['payload'],$actor),
                    };
                } elseif (in_array($operation,['crypto2.inlineDelete.prepare','crypto2.inlineDelete.stage','crypto2.inlineDelete.commit','crypto2.inlineDelete.cancel'],true)) {
                    $inline=new NativeCryptoInlineDeletionV2($this->container,$this->bearer,$this->ip);
                    $out=match ($operation) {
                        'crypto2.inlineDelete.prepare'=>$inline->prepare($command['payload'],$actor,$proof,$command),
                        'crypto2.inlineDelete.stage'=>$inline->stage($command['payload'],$actor,$proof,$command,$key),
                        'crypto2.inlineDelete.commit'=>$inline->commit($command['payload'],$actor,$proof,$command,$key),
                        'crypto2.inlineDelete.cancel'=>$inline->cancel($command['payload'],$actor),
                    };
                } elseif (in_array($operation,['crypto2.access.prepare','crypto2.access.approve','crypto2.access.activate','crypto2.access.cancel'],true)) {
                    $out=(new NativeCryptoAccessV2($this->container,$this->bearer,$this->ip))->write($operation,$command['payload'],$actor,$proof,$command);
                } elseif ($operation === 'crypto2.scope.delete') {
                    $out=(new NativeCryptoScopeDeletionV2($this->container,$this->bearer,$this->ip))->delete($command['payload'],$actor,$proof,$command);
                } elseif ($operation === 'crypto2.scope.financePolicy.propose') {
                    $out = (new NativeCryptoFinancePolicyV2($this->container, $this->bearer, $this->ip))->propose($command['payload'], $actor, $proof, $command);
                } elseif ($operation === 'crypto2.scope.archive' || str_starts_with($operation, 'crypto2.scope.lifecycle.')) {
                    $out = (new NativeCryptoLifecycleV2($this->container, $this->bearer, $this->ip))->write($operation, $command['payload'], $actor, $proof, $command);
                } elseif (in_array($operation, ['crypto2.scope.create', 'crypto2.scope.ensurePersonal'], true)) {
                    $out = (new NativeCryptoScopeCreationV2($this->container, $this->bearer, $this->ip))->write($operation, $command['payload'], $actor, $proof, $command, $key);
                } elseif (in_array($operation, ['crypto2.scope.prepare', 'crypto2.scope.headPut', 'crypto2.scope.activate', 'crypto2.scope.cancel', 'crypto2.scope.closeDomain', 'crypto2.grants.put'], true)) {
                    $out = $scopes->write($operation, $command['payload'], $actor, $proof, $command, $key);
                } elseif (str_starts_with($operation, 'crypto2.scope.keyDraft.') || in_array($operation, ['crypto2.scope.contentManifest.put', 'crypto2.scope.ownerAcceptance.put'], true)) {
                    $out = (new NativeCryptoKeyContributionV2($this->container, $this->bearer, $this->ip))->write($operation, $command['payload'], $actor, $proof, $command, $key);
                } elseif (in_array($operation, ['crypto2.scope.financeDraft.put', 'crypto2.scope.financeDraft.contribute', 'crypto2.scope.financeDraft.cancel', 'crypto2.scope.financeManifest.put'], true)) {
                    $out = (new NativeCryptoFinanceContributionV2($this->container, $this->bearer, $this->ip))->write($operation, $command['payload'], $actor, $proof, $command, $key);
                } elseif (in_array($operation, ['crypto2.table.acquire', 'crypto2.table.renew', 'crypto2.table.release'], true)) {
                    $out = (new NativeCryptoTableV2($this->container, $this->bearer, $this->ip))->write($operation, $command['payload'], $actor);
                } elseif (in_array($operation, ['crypto2.reminders.put', 'crypto2.reminders.cancel', 'crypto2.scope.lifecycle.cancel', 'crypto2.inbox.read', 'crypto2.inbox.preferences.set'], true)) {
                    $out = (new NativeCryptoNotificationV2($this->container, $this->bearer, $this->ip))->write($operation, $command['payload'], $actor, $proof, $command, $key);
                } elseif ($operation === 'crypto2.domain.checkpoint') {
                    $out = (new NativeCryptoCheckpointV2($this->container, $this->bearer, $this->ip))->write($command['payload'], $actor, $proof);
                } elseif ($operation === 'crypto2.records.batch' || in_array($operation, ['crypto2.blob.begin', 'crypto2.blob.chunk', 'crypto2.blob.complete', 'crypto2.blob.abort'], true)) {
                    $out = (new NativeCryptoStorageV2($this->container, $this->bearer, $this->ip))->write($operation, $command['payload'], $actor, $proof, $command, $key);
                } elseif (str_starts_with($operation, 'crypto2.migration.') || $operation === 'crypto2.legacy.reserveReplacement') {
                    $out = (new NativeCryptoMigrationV2($this->container, $this->bearer, $this->ip))->write($operation, $command['payload'], $actor, $proof, $command, $key, $captureSecrets);
                } else {
                    throw new NativeError('unsupported_operation', 404);
                }
            } catch (NativeError $error) {
                $this->pdo->exec('ROLLBACK TO SAVEPOINT crypto2_command');
                if (in_array($error->status, [401,403], true)) {
                    throw $error;
                }$status = $error->status;
                $out = ['errorCode' => $error->errorCode,'details' => $error->details];
            }
            $this->pdo->exec('RELEASE SAVEPOINT crypto2_command');
            $receiptProof = $this->moderationReceipt($operation) ? $this->moderationReceiptCard($command, $proof, $digest) : $proof;
            $this->change('INSERT INTO familyhub_crypto_receipts VALUES(?,?,?,?,?,?,?)', [$account,$request,$digest,json_encode($out, JSON_THROW_ON_ERROR),$status,time(),json_encode($receiptProof, JSON_THROW_ON_ERROR)]);
            return $status === 200 ? $out : new NativeError($out['errorCode'], $status, $out['details']);
        }, $operation !== 'crypto2.authority.snapshot', $operation === 'crypto2.authority.snapshot');
        if ($result instanceof NativeError) {
            throw $result;
        }return $result;
    }
    /** The existing shared-content policy is a server boundary, not merely a UI checkbox. */
    private function uploadPolicy($operation, $payload, $actor)
    {
        $uploads = ['crypto2.records.batch','crypto2.blob.begin','crypto2.blob.chunk','crypto2.blob.complete','crypto2.scope.create','crypto2.scope.headPut','crypto2.grants.put','crypto2.reminders.put','crypto2.scope.keyDraft.put','crypto2.scope.keyDraft.offer','crypto2.scope.keyDraft.sign','crypto2.scope.financeDraft.put','crypto2.scope.financeDraft.contribute'];
        if (!in_array($operation, $uploads, true) && !in_array($operation, ['crypto2.invitations.create','crypto2.invitations.resend'], true)) {
            return;
        }
        $ids = [];
        if (isset($payload['scopeId'])) {
            $ids[] = $payload['scopeId'];
        }
        foreach ($payload['records'] ?? [] as $proof) {
            [$record] = NativeCryptoCodec::decode($proof);
            $ids[] = $record['scopeId'];
        }
        $shared = $operation === 'crypto2.scope.create';
        foreach (array_unique($ids) as $sid) {
            $scope = $this->scope($this->uuid($sid), $actor['user']['id']);
            if ($scope['kind'] !== 'personal') {
                $shared = true;
            }
        }
        if ($shared && !$this->one('SELECT account_id FROM familyhub_policy_acceptances WHERE account_id=? AND policy_version=1', [$actor['user']['account_id']])) {
            throw new NativeError('policy_acceptance_required', 403, ['policyVersion' => 1,'serverId' => $this->serverId()]);
        }
    }

    /** Cached ACKs still require current access to every scope carried by the original request. */
    private function replayAccess($payload, $actor, $operation = null)
    {
        if (str_starts_with($operation ?? '', 'crypto2.moderation.disclosure.')) {
            (new NativeCryptoModerationDisclosureV2($this->container, $this->bearer, $this->ip))->replayAccess($operation, $payload, $actor);
            return;
        }
        if ($operation === 'crypto2.moderation.report') {
            (new NativeCryptoModerationV2($this->container, $this->bearer, $this->ip))->replayAccess($payload, $actor);
            return;
        }
        if ($operation === 'crypto2.reminders.cancel') {
            $row=$this->one('SELECT account_id,scope_id FROM familyhub_crypto_reminders_v2 WHERE id=?',[$payload['id']??null]);
            if (!$row || $row['account_id']!==$actor['user']['account_id'] || $row['scope_id']!==($payload['scopeId']??null)) {
                throw new NativeError('permission_revoked',403);
            }
            return;
        }
        if (in_array($operation,['crypto2.exports.propose','crypto2.exports.certify'],true)) {
            (new NativeCryptoExportV2($this->container,$this->bearer,$this->ip))->replayAccess($operation,$payload,$actor);
            return;
        }
        if ($operation === 'crypto2.invitations.accept') {
            (new NativeCryptoInvitationV2($this->container, $this->bearer, $this->ip))->replayAccess($payload, $actor);
            return;
        }
        if (in_array($operation, ['crypto2.inbox.read', 'crypto2.reminders.put'], true)) {
            (new NativeCryptoNotificationV2($this->container, $this->bearer, $this->ip))->replayAccess($operation, $payload, $actor);
        }
        if (in_array($operation, ['crypto2.scope.create', 'crypto2.scope.ensurePersonal'], true)) {
            $scopeId = $payload['id'] ?? '';
            if ($operation === 'crypto2.scope.ensurePersonal') {
                $personal = $this->one('SELECT scope_id FROM familyhub_personal_scopes WHERE account_id=?', [$actor['user']['account_id']]);
                $scopeId = $personal['scope_id'] ?? $scopeId;
            }
            if ($this->one('SELECT id FROM familyhub_scopes WHERE id=?', [$scopeId])) {
                $this->scope($scopeId, $actor['user']['id']);
            }
        }
        (new NativeCryptoMigrationV2($this->container, $this->bearer, $this->ip))->replayAccess($payload, $actor);
        $ids = [];
        if (isset($payload['scopeId'])) {
            $ids[] = $payload['scopeId'];
        }
        foreach ($payload['scopeIds'] ?? [] as $sid) {
            $ids[] = $sid;
        }
        foreach ($payload['records'] ?? [] as $proof) {
            [$record] = NativeCryptoCodec::decode($proof);
            $ids[] = $record['scopeId'] ?? null;
            foreach ($record['metadata']['references'] ?? [] as $ref) {
                $ids[] = $ref['scopeId'] ?? null;
            }
            if (($record['domain'] ?? null) === 'finance') {
                (new NativeFinanceAccess($this->container))->policyForCrypto($this->uuid($record['scopeId']), $actor['user'], false, true);
            }
        }
        sort($ids, SORT_STRING);
        foreach (array_unique($ids) as $sid) {
            $this->scope($this->uuid($sid), $actor['user']['id']);
        }
        // These own-account Capture3 receipts carry a domain, not a business
        // scope. MigrationV2 already verifies the exact owned portion/selection;
        // its closed handler verifies the certificate/event/tuple context.
        $privateLegacyReceipt = in_array($operation, ['crypto2.migration.legacy.certify', 'crypto2.migration.legacy.anchor', 'crypto2.migration.legacy.reserveReplacement'], true);
        $opaqueDomainAnchor = false;
        if ($operation === 'crypto2.migration.domains.anchor') {
            // This appends the manager's own attestation of an already signed
            // opaque certificate. It neither reads nor materializes finance.
            // Enforce current management on first delivery AND receipt replay;
            // domain3Certificate retains the exact certificate/event checks.
            $sid = $this->uuid($payload['scopeId'] ?? null);
            $scopes = new NativeCryptoScopeV2($this->container, $this->bearer, $this->ip);
            $head = $scopes->current($sid);
            if (!$head) {
                throw new NativeError('crypto_scope_head_missing', 409);
            }
            $scopes->manager($head, $this->scope($sid, $actor['user']['id']), $actor);
            $opaqueDomainAnchor = true;
        }
        if (!$privateLegacyReceipt && !$opaqueDomainAnchor && (($payload['domain'] ?? null) === 'finance' || ($payload['finance'] ?? false) === true)) {
            $sid = $this->uuid($payload['scopeId'] ?? null);
            if ($operation === 'crypto2.grants.put') {
                $scopes = new NativeCryptoScopeV2($this->container, $this->bearer, $this->ip);
                $candidate = $scopes->head($sid, $payload['headHash'] ?? null);
                (new NativeCryptoFinancePolicyV2($this->container, $this->bearer, $this->ip))->financeRead($scopes->body($candidate), $scopes->current($sid), $actor['user']);
            } else {
                (new NativeFinanceAccess($this->container))->policyForCrypto($sid, $actor['user'], false, true);
            }
        }
    }

    private function hasRecoveryStart($current, $deviceId)
    {
        if (!$current) {
            return false;
        }$proof = json_decode($current['authorization'], true, 34, JSON_THROW_ON_ERROR);
        [$c] = NativeCryptoCodec::decode($proof);
        return $c['operation'] === 'crypto2.account.recoveryStart' && $c['signer'] === 'root' && $c['deviceId'] === $deviceId && ($c['payload']['expectedGeneration'] ?? -2) + 1 === (int)$current['generation'];
    }
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
    private function status($account, $current)
    {
        if (!$current) {
            return ['initialized' => false,'serverId' => $this->serverId(),'accountId' => $account,'generation' => 0,'headHash' => NativeCryptoDirectoryV2::ZERO];
        }
        $identity = $this->one('SELECT * FROM familyhub_crypto_accounts WHERE account_id=?', [$account]);
        $out = ['initialized' => true,'serverId' => $this->serverId(),'accountId' => $account,'generation' => (int)$current['generation'],'headHash' => $current['head_hash'],'snapshotHash' => $current['snapshot_hash'],'deviceSnapshotHash' => $current['device_snapshot_hash'],'snapshot' => json_decode($current['snapshot'], true, 34, JSON_THROW_ON_ERROR),'genesisCertificate' => json_decode($identity['genesis_certificate'], true, 34, JSON_THROW_ON_ERROR),'generationCertificate' => json_decode($current['authorization'], true, 34, JSON_THROW_ON_ERROR),'keyringCiphertextBase64' => $identity['keyring']];
        $protection = $this->one('SELECT device_snapshot_hash,scope_manifest_hash,authorization FROM familyhub_crypto_protection_v2 WHERE account_id=?', [$account]);
        $out['protectionReady'] = $protection ? ['deviceSnapshotHash' => $protection['device_snapshot_hash'],'scopeManifestHash' => $protection['scope_manifest_hash'],'authorization' => json_decode($protection['authorization'], true, 34, JSON_THROW_ON_ERROR)] : null;
        $out['snapshotIncluded'] = strlen($current['snapshot']) <= 1048576;
        if (!$out['snapshotIncluded']) {
            $snapshot = $out['snapshot'];
            $out['snapshotHeader'] = array_diff_key($snapshot, array_flip(['devices','keyringEntries']));
            $out['deviceCount'] = count($snapshot['devices']);
            $out['keyringEntryCount'] = count($snapshot['keyringEntries']);
            unset($out['snapshot']);
        }
        return $out;
    }
    private function logPage($p, $account, $current)
    {
        $this->fields($p, ['afterGeneration'], ['limit']);
        $after = $p['afterGeneration'];
        $limit = $p['limit'] ?? 50;
        if (!is_int($after) || $after < 0 || $after > (int)($current['generation'] ?? 0) || !is_int($limit) || $limit < 1 || $limit > 50) {
            throw new NativeError('invalid_cursor');
        }
        $rows = $this->many('SELECT generation,head_hash,previous_head_hash,command_hash,authorization FROM familyhub_crypto_directory WHERE account_id=? AND generation>? ORDER BY generation LIMIT '.($limit + 1), [$account,$after]);
        $out = [];
        $bytes = 0;
        foreach ($rows as $r) {
            $entry = ['generation' => (int)$r['generation'],'headHash' => $r['head_hash'],'previousHeadHash' => $r['previous_head_hash'],'commandHash' => $r['command_hash'],'authorization' => json_decode($r['authorization'], true, 34, JSON_THROW_ON_ERROR)];
            $size = strlen(json_encode($entry, JSON_THROW_ON_ERROR));
            if (count($out) >= $limit || $out && $bytes + $size > 1250000) {
                break;
            }$out[] = $entry;
            $bytes += $size;
        }
        return ['entries' => $out,'hasMore' => count($rows) > count($out),'nextGeneration' => $out ? end($out)['generation'] : $after,'headHash' => $current['head_hash'] ?? NativeCryptoDirectoryV2::ZERO,'generation' => (int)($current['generation'] ?? 0)];
    }
    private function entries($p, $account, $current)
    {
        $this->fields($p, [], ['afterId','limit']);
        $after = isset($p['afterId']) ? $this->uuid($p['afterId']) : '';
        $limit = $p['limit'] ?? 20;
        if (!is_int($limit) || $limit < 1 || $limit > 50) {
            throw new NativeError('validation_error');
        }
        $ids = $this->many('SELECT DISTINCT id FROM familyhub_crypto_keyring_entries_v2 WHERE account_id=? AND id>? ORDER BY id LIMIT '.($limit + 1), [$account,$after]);
        $out = [];
        $proofs = [];
        $included = 0;
        $last = null;
        foreach (array_slice($ids, 0, $limit) as $key) {
            $group = [];
            $newProofs = $proofs;
            foreach ($this->many('SELECT * FROM familyhub_crypto_keyring_entries_v2 WHERE account_id=? AND id=? ORDER BY recipient_kind,recipient_id', [$account,$key['id']]) as $r) {
                $proofId = hash('sha256', $r['authorization']);
                $newProofs[$proofId] = json_decode($r['authorization'], true, 34, JSON_THROW_ON_ERROR);
                $group[] = ['id' => $r['id'],'recipientId' => $r['recipient_id'],'recipientKind' => $r['recipient_kind'],'recipientPublicKeyBase64' => $r['recipient_key'],'sealedEnvelopeBase64' => $r['envelope'],'authorizationId' => $proofId];
            }
            if (strlen(json_encode(['entries' => array_merge($out, $group),'authorizations' => $newProofs], JSON_THROW_ON_ERROR)) > 1572864) {
                if (!$out) {
                    throw new NativeError('crypto_keyring_page_too_large', 413);
                }break;
            }$out = array_merge($out, $group);
            $proofs = $newProofs;
            $included++;
            $last = $key['id'];
        }
        return ['entries' => $out,'authorizations' => (object)$proofs,'hasMore' => $included < count($ids),'nextAfterId' => $last,'generation' => (int)($current['generation'] ?? 0),'headHash' => $current['head_hash'] ?? NativeCryptoDirectoryV2::ZERO];
    }
    private function receipt($p, $account, $actor)
    {
        $this->fields($p, ['requestId','requestHash']);
        $id = $this->uuid($p['requestId']);
        $r = $this->one('SELECT * FROM familyhub_crypto_receipts WHERE account_id=? AND request_id=?', [$account,$id]);
        if (!$r) {
            return ['requestId' => $id,'outcome' => 'unknown'];
        }
        if (!is_string($p['requestHash']) || !hash_equals($r['request_hash'], $p['requestHash'])) {
            throw new NativeError('idempotency_mismatch', 409);
        }
        $proof = json_decode($r['authorization'], true, 34, JSON_THROW_ON_ERROR);
        if (($proof['format'] ?? null) === 'moderationReceiptDigest2') {
            if (!$this->moderationReceipt($proof['operation'] ?? null) || $proof['commandHash'] !== $r['request_hash']) {
                throw new NativeError('crypto_receipt_scope_required', 403);
            }
            if ($proof['replayPayload'] !== null && !$this->minimalModerationReceipt($proof['operation'], $r)) {
                $this->replayAccess($proof['replayPayload'], $actor, $proof['operation']);
            }
            return ['requestId' => $id,'requestHash' => $r['request_hash'],'status' => (int)$r['status'],
                'response' => json_decode($r['response'], true, 34, JSON_THROW_ON_ERROR),
                'authorization' => $proof,'authorizationRetained' => false];
        }
        [$command] = NativeCryptoCodec::decode($proof);
        if ($command['version'] !== 2 || !str_starts_with($command['operation'], 'crypto2.')) {
            throw new NativeError('crypto_receipt_scope_required', 403);
        }
        if (!str_starts_with($command['operation'], 'crypto2.account.') && !str_starts_with($command['operation'], 'crypto2.device.') && !$this->minimalLifecycleReceipt($command, $r) && !$this->minimalLeaveReceipt($command, $r)) {
            $this->replayAccess($command['payload'], $actor, $command['operation']);
        }
        (new NativeCryptoModerationAvailabilityV2($this->container,$this->bearer,$this->ip))->assertReceipt($r);
        return ['requestId' => $id,'requestHash' => $r['request_hash'],'status' => (int)$r['status'],'response' => json_decode($r['response'], true, 34, JSON_THROW_ON_ERROR),'authorization' => $proof];
    }

    private function moderationReceipt($operation)
    {
        return in_array($operation, ['crypto2.moderation.report','crypto2.moderation.disclosure.begin',
            'crypto2.moderation.disclosure.chunk','crypto2.moderation.disclosure.complete','crypto2.moderation.disclosure.abort'], true);
    }

    /** Internal retention helper for previously authenticated moderation proofs. */
    public function moderationRetentionCard($proof)
    {
        [$command,$bytes] = NativeCryptoCodec::decode($proof);
        if (($command['version'] ?? null) !== 2 || !$this->moderationReceipt($command['operation'] ?? null)) {
            throw new NativeError('validation_error');
        }
        return $this->moderationReceiptCard($command, $proof, hash('sha256', $bytes));
    }

    /** Receipt evidence only. This card can never authorize any new command. */
    private function moderationReceiptCard($command, $proof, $digest)
    {
        $payload = $command['payload'];
        $replay = null;
        if (in_array($command['operation'], ['crypto2.moderation.report','crypto2.moderation.disclosure.begin'], true)) {
            $source = $payload['sourceContext'] ?? null;
            if (is_array($source) && is_string($source['scopeId'] ?? null) &&
                preg_match('/^[a-f0-9]{8}-[a-f0-9]{4}-[1-5][a-f0-9]{3}-[89ab][a-f0-9]{3}-[a-f0-9]{12}$/D', $source['scopeId']) &&
                in_array($source['domain'] ?? null, [null,'content','finance'], true)) {
                $replay = ['sourceContext' => ['scopeId' => $source['scopeId'],'domain' => $source['domain']]];
            }
        } elseif (is_string($payload['stageId'] ?? null) &&
            preg_match('/^[a-f0-9]{8}-[a-f0-9]{4}-[1-5][a-f0-9]{3}-[89ab][a-f0-9]{3}-[a-f0-9]{12}$/D', $payload['stageId'])) {
            $replay = ['stageId' => $payload['stageId']];
        }
        return ['format' => 'moderationReceiptDigest2','operation' => $command['operation'],
            'commandHash' => $digest,'signatureBase64' => $proof['signatureBase64'],'replayPayload' => $replay];
    }
    /** Own successful report outcome only; no disclosed snapshot or current ACL data. */
    private function minimalModerationReceipt($operation, $receipt)
    {
        if ($operation !== 'crypto2.moderation.report' || (int)$receipt['status'] !== 200) {
            return false;
        }
        $response = json_decode($receipt['response'], true, 34, JSON_THROW_ON_ERROR);
        $keys = array_keys($response);
        sort($keys, SORT_STRING);
        return $keys === ['createdAt', 'reportId', 'serverId', 'status']
            && $response['status'] === 'submitted'
            && $response['serverId'] === $this->serverId()
            && is_string($response['createdAt'])
            && is_string($response['reportId'])
            && preg_match('/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/D', $response['reportId']) === 1;
    }

    private function minimalLeaveReceipt($command, $receipt)
    {
        if (!in_array($command['operation'],['crypto2.access.leaveRequest','crypto2.access.leaveCancel'],true) || (int)$receipt['status']!==200) return false;
        $response=json_decode($receipt['response'],true,34,JSON_THROW_ON_ERROR);
        $keys=array_keys($response);sort($keys,SORT_STRING);
        $original=json_decode($receipt['authorization'],true,34,JSON_THROW_ON_ERROR);
        $expectedHash=$command['operation']==='crypto2.access.leaveRequest'
            ? NativeCryptoV2Codec::hash((object)$original) : ($command['payload']['requestHash']??null);
        return $keys===['requestHash','state'] && $response['requestHash']===$expectedHash &&
            $response['state']===($command['operation']==='crypto2.access.leaveRequest'?'pending':'cancelled');
    }

    private function minimalLifecycleReceipt($command, $receipt)
    {
        if ($command['operation'] !== 'crypto2.scope.activate' || (int)$receipt['status'] !== 200) {
            return false;
        }
        // A child activation stores the topology wrapper, not the signed inner payload.
        // This recognizes only an already authenticated, minimal historical outcome;
        // anything else must retain the caller's normal current-access check.
        try {
            $payload = $command['payload'];
            if (!is_array($payload)) return false;
            if (array_key_exists('activationProof', $payload)) {
                $this->fields($payload, ['scopeId', 'headHash', 'activationProof', 'parentTopologyBatch']);
                [$inner] = NativeCryptoCodec::decode($payload['activationProof']);
                $this->fields($inner, ['version', 'operation', 'requestId', 'serverId', 'accountId', 'deviceId', 'signer', 'payload']);
                $this->uuid($inner['requestId']);
                if ($inner['version'] !== 2 || $command['version'] !== 2 ||
                    $inner['operation'] !== $command['operation'] ||
                    $inner['signer'] !== 'device' || $command['signer'] !== 'device') return false;
                foreach (['serverId', 'accountId', 'deviceId'] as $field) {
                    if ($inner[$field] !== $command[$field]) return false;
                }
                $bundle = $payload['parentTopologyBatch'];
                $this->fields($bundle, ['parentScopeId', 'childScopeId', 'authorization']);
                $this->uuid($bundle['parentScopeId']);
                $this->uuid($bundle['childScopeId']);
                NativeCryptoCodec::decode($bundle['authorization']);
                if ($bundle['childScopeId'] !== $payload['scopeId'] ||
                    $bundle['parentScopeId'] === $bundle['childScopeId'] ||
                    !is_array($inner['payload']) ||
                    ($inner['payload']['scopeId'] ?? null) !== $payload['scopeId'] ||
                    ($inner['payload']['headHash'] ?? null) !== $payload['headHash'] ||
                    ($inner['payload']['parentTopologyBatchHash'] ?? null) !== hash('sha256',
                        "JivieFinanceTopologyCreationBatch/v3\n".NativeCryptoCodec::canonical((object)$bundle))) return false;
                $payload = $inner['payload'];
            }
            $manifestHash = $payload['grantManifestHash'] ?? null;
            if (!is_string($manifestHash) || preg_match('/^[a-f0-9]{64}$/D', $manifestHash) !== 1) return false;
            $this->uuid($payload['scopeId'] ?? null);
            if (!is_string($payload['headHash'] ?? null) || preg_match('/^[a-f0-9]{64}$/D', $payload['headHash']) !== 1) return false;
            $response = json_decode($receipt['response'], true, 34, JSON_THROW_ON_ERROR);
            if (!is_array($response)) return false;
        } catch (\Throwable $error) {
            return false;
        }
        $keys = array_keys($response);
        sort($keys, SORT_STRING);
        $expected = ['scopeId', 'headHash', 'epoch', 'state', 'grantManifestHash'];
        sort($expected, SORT_STRING);
        return $keys === $expected
            && $response['scopeId'] === $payload['scopeId']
            && $response['headHash'] === $payload['headHash']
            && $response['grantManifestHash'] === $manifestHash;
    }

    private function savedResult($r)
    {
        $out = json_decode($r['response'], true, 34, JSON_THROW_ON_ERROR);
        return (int)$r['status'] === 200 ? $out : new NativeError($out['errorCode'], (int)$r['status'], $out['details']);
    }
    private function project($command, $proof, $snapshot, $current, $actor)
    {
        $p = $command['payload'];
        $account = $command['accountId'];
        $n = $p['expectedGeneration'] + 1;
        $op = $command['operation'];
        $encoded = json_encode($proof, JSON_THROW_ON_ERROR);
        $events = new NativeCryptoService($this->container, $this->bearer, $this->ip);
        if ($op === 'crypto2.account.protectionReady') {
            $observed = (new NativeCryptoScopeV2($this->container, $this->bearer, $this->ip))->protectionCatalog($actor);
            if ($p['scopeManifestHash'] !== $observed['scopeManifestHash'] || $p['deviceSnapshotHash'] !== NativeCryptoDirectoryV2::deviceHash($snapshot)) {
                throw new NativeError('crypto_protection_catalog_changed', 409);
            }
            $this->change('DELETE FROM familyhub_crypto_protection_v2 WHERE account_id=?', [$account]);
            $this->change('INSERT INTO familyhub_crypto_protection_v2 VALUES(?,?,?,?)', [$account,$p['deviceSnapshotHash'],$p['scopeManifestHash'],$encoded]);
        }
        if ($op === 'crypto2.account.initialize') {
            if ($this->one('SELECT account_id FROM familyhub_crypto_accounts WHERE account_id=?', [$account])) {
                throw new NativeError('crypto_directory_upgrade_required', 409);
            }
            $this->change('INSERT INTO familyhub_crypto_accounts VALUES(?,?,?,?,?,?,?,?,?,?)', [$account,$p['rootSigningKeyBase64'],$p['rootEncryptionKeyBase64'],$p['keyringCiphertextBase64'],$encoded,$encoded,$encoded,$n,time(),time()]);
            $events->event($account, 'crypto.initialized');
        } else {
            $this->change('UPDATE familyhub_crypto_accounts SET generation=?,generation_certificate=?,updated_at=? WHERE account_id=?', [$n,$encoded,time(),$account]);
        }
        if (in_array($op, ['crypto2.account.initialize','crypto2.device.add','crypto2.device.rebind','crypto2.account.recoverEpoch','crypto2.account.rotateRoot'], true)) {
            $id = $op === 'crypto2.device.add' ? $p['deviceId'] : $command['deviceId'];
            $d = (new NativeCryptoDirectoryV2($this->container))->device($snapshot, $id);
            if (!$this->one('SELECT id FROM familyhub_devices WHERE id=? AND account_id=? AND revoked_at IS NULL AND expires_at>?', [$id,$account,time()])) {
                throw new NativeError('device_revoked', 403);
            }
            $this->change('INSERT INTO familyhub_crypto_devices(account_id,device_id,signing_key,encryption_key,certificate,keyring_write,manage_devices) VALUES(?,?,?,?,?,?,?)', [$account,$id,$d['signingKeyBase64'],$d['encryptionKeyBase64'],$encoded,(int)$d['keyringWrite'],(int)$d['manageDevices']]);
            if (in_array($op, ['crypto2.account.recoverEpoch','crypto2.account.rotateRoot','crypto2.device.add'], true) && $command['signer'] === 'root' && !$this->hasRecoveryStart($current, $command['deviceId'])) {
                $events->event($account, 'crypto.recoveryStarted');
            }
            if ($op !== 'crypto2.account.initialize') {
                $events->event($account, 'crypto.deviceAdded');
                if ($command['signer'] === 'root') {
                    $events->event($account, 'crypto.recoveryCompleted');
                }
            }
        }
        if ($op === 'crypto2.account.rotateRoot') {
            $this->change('UPDATE familyhub_crypto_accounts SET root_signing_key=?,root_encryption_key=?,keyring=?,keyring_certificate=? WHERE account_id=?', [$snapshot['rootSigningKeyBase64'],$snapshot['rootEncryptionKeyBase64'],$p['keyringCiphertextBase64'],$encoded,$account]);
        }
        foreach ($snapshot['devices'] as $d) {
            if ($d['revokedGeneration'] !== $n) {
                continue;
            }$id = $d['deviceId'];
            $this->change('UPDATE familyhub_crypto_devices SET revoked_at=?,revocation_certificate=? WHERE account_id=? AND device_id=?', [time(),$encoded,$account,$id]);
            $this->change('UPDATE familyhub_devices SET revoked_at=? WHERE account_id=? AND id=?', [time(),$account,$id]);
            (new NativePushService($this->container))->revokeDevice($id);
        }
        if (in_array($op, ['crypto2.device.revoke','crypto2.device.rebind'], true)) {
            $events->event($account, 'crypto.deviceRevoked');
        }
        if ($op === 'crypto2.account.recoveryStart') {
            $events->event($account, 'crypto.recoveryStarted');
        }
        if ($op === 'crypto2.account.keyringEntriesPut') {
            foreach ($p['entries'] as $entry) {
                if (!$this->one('SELECT id FROM familyhub_crypto_keyring_entries_v2 WHERE account_id=? AND id=? AND recipient_kind=? AND recipient_id=?', [$account,$entry['id'],$entry['recipientKind'],$entry['recipientId']])) {
                    $this->change('INSERT INTO familyhub_crypto_keyring_entries_v2 VALUES(?,?,?,?,?,?,?)', [$account,$entry['id'],$entry['recipientId'],$entry['recipientKind'],$entry['recipientPublicKeyBase64'],$entry['sealedEnvelopeBase64'],$encoded]);
                }
            }
            $this->change('UPDATE familyhub_crypto_accounts SET keyring_certificate=? WHERE account_id=?', [$encoded,$account]);
        }
    }
}
