<?php

namespace Kanboard\Plugin\FamilyHub\Model;

/** Explicit target-specific permission to disclose future deadline changes. */
class NativeCryptoSchedulingUseV2 extends NativeDatabase
{
    protected $cryptoAccess = true;
    public const DOMAIN = "JivieE2EE/schedulingUse/v2\n";

    private function hashValue($value)
    {
        if (!is_string($value) || !preg_match('/^[a-f0-9]{64}$/D', $value)) {
            throw new NativeError('validation_error');
        }
        return $value;
    }

    public static function proofHash($proof)
    {
        return NativeCryptoV2Codec::hash((object)$proof);
    }

    private function token($body)
    {
        return hash('sha256', "JivieScheduleUse/v2\n".NativeCryptoCodec::canonical((object)[
            'serverId' => $body['serverId'], 'accountId' => $body['accountId'],
            'scopeId' => $body['scopeId'], 'targetId' => $body['targetId'], 'useId' => $body['useId'],
        ]));
    }

    public function body($proof)
    {
        [$body, $bytes, $signature] = NativeCryptoCodec::decode($proof);
        if (strlen($bytes) > 16384) {
            throw new NativeError('validation_error');
        }
        $fields = ['version','operation','serverId','scopeId','targetId','targetType','domain','useId','sourceScheduleRevision','schedulePutId','consentGeneration','scopeLifecycleHash','projectBarrier','expiresAtEpoch','mode','membershipHeadHash','accessRevision','targetRevision','targetRecordProofHash','accountId','deviceId','authorDirectoryHeadHash'];
        $migration = ($body['version'] ?? null) === 3;
        if ($migration) {
            $fields = array_merge($fields,['migrationId','captureId','sourceInventoryRoot','bindingId','originalState']);
        }
        $this->fields($body,$fields);
        foreach (['serverId','scopeId','useId','sourceScheduleRevision','schedulePutId','consentGeneration','accountId','deviceId'] as $field) {
            $this->uuid($body[$field]);
        }
        NativeCryptoRecordAddressV2::wireId($body['targetId']);
        foreach (['scopeLifecycleHash','membershipHeadHash','targetRecordProofHash','authorDirectoryHeadHash'] as $field) {
            $this->hashValue($body[$field]);
        }
        if ((!$migration && ($body['version'] !== 2 || $body['operation'] !== 'crypto2.scheduling.use') ||
            $migration && $body['operation'] !== 'crypto2.migration.schedulingUse') ||
            $body['serverId'] !== $this->serverId() || $body['mode'] !== 'relative' ||
            !in_array($body['targetType'], ['task','event','financeEntry','personalFinanceEntry'], true) ||
            (new NativeCryptoRecordProofV2($this->container))->domain($body['targetType']) !== $body['domain'] ||
            !is_int($body['accessRevision']) || $body['accessRevision'] < 0 ||
            !is_int($body['targetRevision']) || $body['targetRevision'] < 1 ||
            $body['expiresAtEpoch'] !== null && (!is_int($body['expiresAtEpoch']) || $body['expiresAtEpoch'] < 0 || $body['expiresAtEpoch'] > 253402300799)) {
            throw new NativeError('crypto_scheduling_use_invalid', 403);
        }
        if ($migration) {
            foreach (['migrationId','captureId','bindingId'] as $field) {
                $this->uuid($body[$field]);
            }
            $this->hashValue($body['sourceInventoryRoot']);
            if (!in_array($body['originalState'],['pending','delivered'],true)) {
                throw new NativeError('crypto_scheduling_use_invalid',403);
            }
        }
        if ($body['projectBarrier'] !== null) {
            $this->fields($body['projectBarrier'], ['id','consentGeneration']);
            NativeCryptoRecordAddressV2::wireId($body['projectBarrier']['id']);
            $this->uuid($body['projectBarrier']['consentGeneration']);
        }
        return [$body, $bytes, $signature];
    }

    /** Internal final-cutover insertion. The calling notification installer
     * already verified the complete source, transform, cert and own-log anchor.
     * This never appends a fabricated historical scheduleUse account event.
     */
    public function installMigrationBaseline($proof, $proofHash, array $coverage)
    {
        if (!$this->transactionActive() || ($coverage['state'] ?? null) !== 'anchored') {
            throw new NativeError('crypto_migration_transaction_required',409);
        }
        [$body] = $this->body($proof);
        if ($body['version'] !== 3 || self::proofHash($proof) !== $proofHash ||
            $body['accountId'] !== $coverage['accountId'] || $body['migrationId'] !== $coverage['migrationId'] ||
            $body['captureId'] !== $coverage['captureId'] || $body['sourceInventoryRoot'] !== $coverage['sourceInventoryRoot']) {
            throw new NativeError('crypto_scheduling_use_invalid',403);
        }
        $event = $this->one('SELECT generation FROM familyhub_crypto_directory WHERE account_id=? AND head_hash=? AND command_hash=?',[
            $body['accountId'],$coverage['eventHeadHash'],$coverage['eventCommandHash']]);
        $token = $this->token($body);
        if (!$event || $this->one('SELECT use_token FROM familyhub_crypto_scheduling_uses_v2 WHERE account_id=? AND (use_token=? OR reminder_id=?)',[$body['accountId'],$token,$body['schedulePutId']])) {
            throw new NativeError('crypto_scheduling_use_identity',409);
        }
        $this->change('INSERT INTO familyhub_crypto_scheduling_use_proofs_v2 VALUES(?,?,?,?,?,?,?)',[
            $body['accountId'],$token,$proofHash,$body['scopeId'],$body['targetId'],$body['schedulePutId'],json_encode($proof,JSON_THROW_ON_ERROR)]);
        $this->change('INSERT INTO familyhub_crypto_scheduling_uses_v2 VALUES(?,?,?,?,?,?,?,?,?)',[
            $body['accountId'],$token,$proofHash,(int)$event['generation'],$coverage['eventCommandHash'],
            $body['expiresAtEpoch'] === null || $body['expiresAtEpoch'] > time() ? 1 : 0,
            $body['scopeId'],$body['targetId'],$body['schedulePutId']]);
    }

    private function currentSigner($body)
    {
        $user = $this->one('SELECT user_id FROM familyhub_accounts WHERE account_id=?', [$body['accountId']]);
        if (!$user) {
            throw new NativeError('permission_revoked', 403);
        }
        $actor = ['user' => ['id' => $user['user_id'], 'account_id' => $body['accountId']], 'device' => ['id' => $body['deviceId']]];
        $scopes = new NativeCryptoScopeV2($this->container, $this->bearer, $this->ip);
        $scopes->currentAuthorReference($body['authorDirectoryHeadHash'], $actor);
        $directory = new NativeCryptoDirectoryV2($this->container);
        $current = $directory->current($body['accountId']);
        $snapshot = json_decode($current['snapshot'], true, 34, JSON_THROW_ON_ERROR);
        $device = $directory->device($snapshot, $body['deviceId']);
        if (!$device || $device['revokedGeneration'] !== null || $device['identityEpochId'] !== $snapshot['identityEpochId'] ||
            !(new NativeCryptoNotificationV2($this->container, $this->bearer, $this->ip))->recipientVisible($body['scopeId'], $body['accountId'], $body['domain'])) {
            throw new NativeError('crypto_scheduling_use_revoked', 403);
        }
        return [$device, $current];
    }

    private function barriers($body, $target)
    {
        $metadata = json_decode($target['metadata'], true, 34, JSON_THROW_ON_ERROR);
        $state = $metadata['reminderState'] ?? null;
        if ((int)$target['deleted'] || !$state || $state['closed'] ||
            ($state['consentGeneration'] ?? null) !== $body['consentGeneration'] ||
            (new NativeCryptoLifecycleV2($this->container))->closingHash($body['scopeId']) !== $body['scopeLifecycleHash'] ||
            $body['expiresAtEpoch'] !== null && $body['expiresAtEpoch'] <= time()) {
            throw new NativeError('crypto_scheduling_consent_changed', 409);
        }
        $pending = $metadata['references'];
        $seen = [];
        $projects = [];
        while ($pending) {
            $ref = array_shift($pending);
            if ($ref['scopeId'] !== $body['scopeId'] || isset($seen[$ref['id']])) {
                continue;
            }
            if (count($seen) >= 100) {
                throw new NativeError('crypto_reference_graph_limit', 409);
            }
            $seen[$ref['id']] = true;
            $row = $this->one('SELECT type,deleted,metadata FROM familyhub_crypto_records WHERE scope_id=? AND id=?', [$body['scopeId'], $ref['id']]);
            if (!$row) {
                continue;
            }
            $next = json_decode($row['metadata'], true, 34, JSON_THROW_ON_ERROR);
            if ($row['type'] === 'project') {
                if ((int)$row['deleted'] || ($next['projectState']['archived'] ?? true)) {
                    throw new NativeError('crypto_scheduling_consent_changed', 409);
                }
                $projects[] = ['id' => $ref['id'], 'consentGeneration' => $next['projectState']['consentGeneration'] ?? null];
            }
            foreach ($next['references'] as $reference) {
                $pending[] = $reference;
            }
        }
        if (count($projects) > 1 ||
            NativeCryptoCodec::canonical(($projects[0] ?? null) === null ? null : (object)$projects[0]) !==
            NativeCryptoCodec::canonical($body['projectBarrier'] === null ? null : (object)$body['projectBarrier'])) {
            throw new NativeError('crypto_scheduling_consent_changed', 409);
        }
    }

    /** Append the inner event under the outer reminder transaction and receipt. */
    public function companion($proof, $eventProof, $active, $outer, $actor, $target = null)
    {
        [$body, $bytes, $signature] = $this->body($proof);
        $hash = self::proofHash($proof);
        $token = $this->token($body);
        $account = $actor['user']['account_id'];
        $old = $this->one('SELECT * FROM familyhub_crypto_scheduling_uses_v2 WHERE account_id=? AND use_token=?', [$account, $token]);
        $sameReminder=$this->one('SELECT use_token FROM familyhub_crypto_scheduling_uses_v2 WHERE account_id=? AND reminder_id=?',[$account,$body['schedulePutId']]);
        $routed = null;
        if (!$active && $old && ($old['scope_id']!==$body['scopeId'] || $old['target_id']!==$body['targetId'])) {
            $routed=(new NativeCryptoProjectRelocationNotificationsV2($this->container,$this->bearer,$this->ip))->installedUse($body,$hash,$old['scope_id'],$old['target_id']);
        }
        if ($old && ((!$routed && ($old['scope_id']!==$body['scopeId'] || $old['target_id']!==$body['targetId'])) || $old['reminder_id']!==$body['schedulePutId']) ||
            $sameReminder && $sameReminder['use_token']!==$token) {
            throw new NativeError('crypto_scheduling_use_identity',409);
        }
        if ($body['accountId'] !== $account || ($routed['body']['scopeId']??$body['scopeId']) !== $outer['payload']['scopeId'] || $body['schedulePutId'] !== $outer['payload']['id'] ||
            !$active && (!$old || $old['proof_hash'] !== $hash)) {
            throw new NativeError('crypto_scheduling_use_invalid', 403);
        }
        if ($active) {
            if ($body['version'] !== 2) {
                throw new NativeError('crypto_scheduling_migration_issuance_forbidden',403);
            }
            [$device] = $this->currentSigner($body);
            NativeCryptoV2Codec::verify($bytes, $signature, $device['signingKeyBase64'], self::DOMAIN);
            (new NativeCryptoScopeV2($this->container, $this->bearer, $this->ip))->author(
                $body['scopeId'], $body['membershipHeadHash'],
                (int)(new NativeCryptoScopeV2($this->container))->current($body['scopeId'])['epoch'],
                $body['accessRevision'], $actor, $body['domain'], false
            );
            $this->barriers($body, $target);
            $authorization = json_decode($target['authorization'], true, 34, JSON_THROW_ON_ERROR);
            if ($body['deviceId'] !== $actor['device']['id'] || $body['targetId'] !== $target['id'] || $body['targetType'] !== $target['type'] ||
                $body['targetRevision'] !== (int)$target['revision'] ||
                $body['sourceScheduleRevision'] !== json_decode($target['metadata'], true)['reminderState']['scheduleRevision'] ||
                $body['targetRecordProofHash'] !== self::proofHash($authorization['recordProof'])) {
                throw new NativeError('crypto_scheduling_target_changed', 409);
            }
        }
        [$event, $eventBytes, $eventSignature] = NativeCryptoCodec::decode($eventProof);
        $this->fields($event, ['version','operation','requestId','serverId','accountId','deviceId','signer','payload']);
        foreach (['requestId','serverId','accountId','deviceId'] as $field) {
            $this->uuid($event[$field]);
        }
        if (!is_array($event['payload'])) {
            throw new NativeError('validation_error');
        }
        if (($event['operation'] ?? null) !== 'crypto2.account.scheduleUse' ||
            ($event['version'] ?? null) !== 2 || ($event['serverId'] ?? null) !== $this->serverId() ||
            ($event['accountId'] ?? null) !== $account || ($event['deviceId'] ?? null) !== $actor['device']['id'] ||
            ($event['requestId'] ?? null) !== $outer['requestId'] || ($event['signer'] ?? null) !== 'device' ||
            ($event['payload']['useToken'] ?? null) !== $token || ($event['payload']['useProofHash'] ?? null) !== $hash ||
            ($event['payload']['active'] ?? null) !== $active) {
            throw new NativeError('crypto_scheduling_event_binding', 403);
        }
        $directory = new NativeCryptoDirectoryV2($this->container);
        $current = $directory->current($account);
        $key = $directory->authorize($event, $current);
        NativeCryptoV2Codec::verify($eventBytes, $eventSignature, $key);
        $snapshot = $directory->reduce($event, $current);
        $appended = $directory->append($event, $eventProof, $snapshot);
        $eventHash = hash('sha256', $eventBytes);
        $this->change('UPDATE familyhub_crypto_accounts SET generation=?,generation_certificate=?,updated_at=? WHERE account_id=?', [$appended['generation'], json_encode($eventProof, JSON_THROW_ON_ERROR), time(), $account]);
        if (!$this->one('SELECT proof_hash FROM familyhub_crypto_scheduling_use_proofs_v2 WHERE account_id=? AND use_token=? AND proof_hash=?', [$account,$token,$hash])) {
            $this->change('INSERT INTO familyhub_crypto_scheduling_use_proofs_v2 VALUES(?,?,?,?,?,?,?)', [$account,$token,$hash,$body['scopeId'],$body['targetId'],$body['schedulePutId'],json_encode($proof,JSON_THROW_ON_ERROR)]);
        }
        if ($old) {
            $this->change('UPDATE familyhub_crypto_scheduling_uses_v2 SET proof_hash=?,generation=?,event_command_hash=?,active=? WHERE account_id=? AND use_token=?', [$hash,$appended['generation'],$eventHash,(int)$active,$account,$token]);
        } else {
            $this->change('INSERT INTO familyhub_crypto_scheduling_uses_v2 VALUES(?,?,?,?,?,?,?,?,?)', [$account,$token,$hash,$appended['generation'],$eventHash,(int)$active,$body['scopeId'],$body['targetId'],$body['schedulePutId']]);
        }
        return $appended;
    }

    public function validateMetadata($record)
    {
        $use = $record['metadata']['schedulingUse'] ?? null;
        if ($use === null) {
            throw new NativeError('crypto_scheduling_use_required', 409);
        }
        $this->fields($use, ['authorization','directoryHeadHash','eventCommandHash']);
        [$body, $bytes, $signature] = $this->body($use['authorization']);
        $token = $this->token($body);
        $hash = self::proofHash($use['authorization']);
        $row = $this->one('SELECT * FROM familyhub_crypto_scheduling_uses_v2 WHERE account_id=? AND use_token=?', [$body['accountId'],$token]);
        $routed=null;
        if($row && ($body['scopeId']!==$record['scopeId'] || $body['targetId']!==$record['id'])) {
            $routed=(new NativeCryptoProjectRelocationNotificationsV2($this->container,$this->bearer,$this->ip))->installedUse($body,$hash,$record['scopeId'],$record['id']);
        }
        if (!$row || !(int)$row['active'] || $row['proof_hash'] !== $hash || $row['event_command_hash'] !== $use['eventCommandHash'] ||
            $row['scope_id'] !== $record['scopeId'] || $row['target_id'] !== $record['id'] ||
            (!$routed && ($body['scopeId'] !== $record['scopeId'] || $body['targetId'] !== $record['id'])) || $body['targetType'] !== $record['type']) {
            throw new NativeError('crypto_scheduling_use_revoked', 409);
        }
        if ($routed) {
            $key=(new NativeCryptoMigrationNotificationStageV3($this->container,$this->bearer,$this->ip))->installedRelocationUseSigner($body,$hash,$record['scopeId'],$record['id']);
            if (!(new NativeCryptoNotificationV2($this->container,$this->bearer,$this->ip))->recipientVisible($record['scopeId'],$body['accountId'],$body['domain'])) throw new NativeError('crypto_scheduling_use_revoked',403);
        } elseif ($body['version'] === 3) {
            // Final inclusion proves that this was prior consent. A later
            // device revocation forbids new issuance, not this historical
            // signature. Current target READ and every consent barrier remain
            // independent requirements below.
            $key=(new NativeCryptoMigrationNotificationStageV3($this->container,$this->bearer,$this->ip))->installedUseSigner($body,$hash);
            if (!(new NativeCryptoNotificationV2($this->container,$this->bearer,$this->ip))->recipientVisible($body['scopeId'],$body['accountId'],$body['domain'])) {
                throw new NativeError('crypto_scheduling_use_revoked',403);
            }
        } else {
            [$device] = $this->currentSigner($body);
            $key=$device['signingKeyBase64'];
        }
        $reference = $this->one('SELECT generation FROM familyhub_crypto_directory WHERE account_id=? AND head_hash=?', [$body['accountId'],$this->hashValue($use['directoryHeadHash'])]);
        if (!$reference || (int)$reference['generation'] < (int)$row['generation']) {
            throw new NativeError('crypto_scheduling_event_binding', 409);
        }
        NativeCryptoV2Codec::verify($bytes, $signature, $key,
            $body['version'] === 3 ? "JivieE2EE/migrationSchedulingUse/v3\n" : self::DOMAIN);
        $this->barriers($routed['body']??$body, ['metadata' => json_encode($record['metadata'],JSON_THROW_ON_ERROR), 'deleted' => (int)$record['deleted']]);
    }

    /** An owner may retain already-active consent while editing its own exact
     * reminder. This does not create an account event or reactivate a cancel. */
    public function reuse($proof,$outer,$actor,$target)
    {
        [$body]=$this->body($proof);
        $use=$this->forReminder($actor['user']['account_id'],$outer['payload']['id']);
        if(!$use || !$use['active'] || $body['accountId']!==$actor['user']['account_id'] ||
            self::proofHash($proof)!==self::proofHash($use['authorization']) || $body['schedulePutId']!==$outer['payload']['id']) {
            throw new NativeError('crypto_scheduling_use_invalid',403);
        }
        $record=['scopeId'=>$outer['payload']['scopeId'],'id'=>$target['id'],'type'=>$target['type'],
            'deleted'=>(bool)$target['deleted'],'metadata'=>json_decode($target['metadata'],true,34,JSON_THROW_ON_ERROR)];
        $record['metadata']['schedulingUse']=array_intersect_key($use,array_flip(['authorization','directoryHeadHash','eventCommandHash']));
        $this->validateMetadata($record);
    }

    public function forReminder($account, $id)
    {
        $row = $this->one('SELECT u.*,p.authorization FROM familyhub_crypto_scheduling_uses_v2 u JOIN familyhub_crypto_scheduling_use_proofs_v2 p ON p.account_id=u.account_id AND p.use_token=u.use_token AND p.proof_hash=u.proof_hash WHERE u.account_id=? AND u.reminder_id=?', [$account,$id]);
        return $row ? [
            'authorization' => json_decode($row['authorization'],true,34,JSON_THROW_ON_ERROR),
            'directoryHeadHash' => (new NativeCryptoDirectoryV2($this->container))->current($account)['head_hash'],
            'eventCommandHash' => $row['event_command_hash'], 'active' => (bool)$row['active'],
            'scopeId'=>$row['scope_id'],'targetId'=>$row['target_id'],
        ] : null;
    }

    public function read($p, $actor)
    {
        $this->fields($p, ['scopeId','targetId','domain'], ['afterToken','limit']);
        $sid=$this->uuid($p['scopeId']);$target=NativeCryptoRecordAddressV2::wireId($p['targetId']);
        if (!in_array($p['domain'],['content','finance'],true) ||
            !(new NativeCryptoNotificationV2($this->container,$this->bearer,$this->ip))->recipientVisible($sid,$actor['user']['account_id'],$p['domain'])) {
            throw new NativeError('permission_revoked',403);
        }
        $after=$p['afterToken']??'';
        if ($after!=='') {$this->hashValue($after);}
        $limit=$p['limit']??20;
        if (!is_int($limit)||$limit<1||$limit>20) {throw new NativeError('validation_error');}
        $rows=$this->many('SELECT * FROM familyhub_crypto_scheduling_uses_v2 WHERE scope_id=? AND target_id=? AND use_token>? ORDER BY use_token,account_id LIMIT '.($limit+1),[$sid,$target,$after]);
        $more=count($rows)>$limit;$rows=array_slice($rows,0,$limit);$out=[];
        foreach($rows as $row){
            $proof=$this->one('SELECT authorization FROM familyhub_crypto_scheduling_use_proofs_v2 WHERE account_id=? AND use_token=? AND proof_hash=?',[$row['account_id'],$row['use_token'],$row['proof_hash']]);
            if (!$proof) {throw new NativeError('crypto_scheduling_use_unavailable',503);}
            $directory=(new NativeCryptoDirectoryV2($this->container))->current($row['account_id']);
            $out[]=['authorization'=>json_decode($proof['authorization'],true,34,JSON_THROW_ON_ERROR),'directoryHeadHash'=>$directory['head_hash'],'eventCommandHash'=>$row['event_command_hash']];
        }
        return ['uses'=>$out,'hasMore'=>$more,'nextAfterToken'=>$rows?end($rows)['use_token']:$after];
    }

    public function own($p, $actor)
    {
        $this->fields($p,['reminderId']);
        return ['use'=>$this->forReminder($actor['user']['account_id'],$this->uuid($p['reminderId']))];
    }
}
