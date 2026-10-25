<?php

namespace Kanboard\Plugin\FamilyHub\Model;

/** A reader receives one scoped record proof plus an opaque batch commitment, never the author's batch. */
class NativeCryptoRecordProofV2 extends NativeDatabase
{
    public function parseBatch(array $payload, array $command, $authorKey)
    {
        $this->fields($payload, ['batchId','records','commitment'], ['tableLeases', 'exportBindings']);
        $batch = $this->uuid($payload['batchId']);
        $proofs = $payload['records'];
        if (!is_array($proofs) || !array_is_list($proofs) || count($proofs) < 1 || count($proofs) > 32) {
            throw new NativeError('validation_error');
        }
        [$commitment,$bytes,$signature] = NativeCryptoCodec::decode($payload['commitment']);
        NativeCryptoV2Codec::verify($bytes, $signature, $authorKey, NativeCryptoV2Codec::BATCH_DOMAIN);
        $this->fields($commitment, ['version','operation','serverId','accountId','deviceId','batchId','recordDigests','projectionGroups']);
        if ($commitment['version'] !== 2 || $commitment['operation'] !== 'crypto2.batchCommitment' || $commitment['batchId'] !== $batch) {
            throw new NativeError('crypto_batch_binding', 403);
        }
        foreach (['serverId','accountId','deviceId'] as $key) {
            if ($commitment[$key] !== $command[$key]) {
                throw new NativeError('crypto_batch_binding', 403);
            }
        }
        $records = [];
        $digests = [];
        $seen = [];
        $expectedGroups = [];
        foreach ($proofs as $proof) {
            [$record,$raw,$sig] = NativeCryptoCodec::decode($proof);
            NativeCryptoV2Codec::verify($raw, $sig, $authorKey, NativeCryptoV2Codec::RECORD_DOMAIN);
            $this->record($record);
            foreach (['serverId','accountId','deviceId','batchId'] as $key) {
                if ($record[$key] !== $commitment[$key]) {
                    throw new NativeError('crypto_record_binding', 403);
                }
            }
            $id = $record['scopeId'].':'.$record['id'];
            if (isset($seen[$id])) {
                throw new NativeError('crypto_duplicate_record', 409);
            }$seen[$id] = true;
            $digest = NativeCryptoV2Codec::hash((object)$proof);
            $digests[] = $digest;
            $group = $record['scopeId'].':'.$record['domain'];
            $expectedGroups[$group][] = $digest;
            $records[] = ['record' => $record,'recordProof' => $proof,'recordProofHash' => $digest,'batchCommitment' => $payload['commitment']];
        }
        sort($digests, SORT_STRING);
        if ($commitment['recordDigests'] !== $digests || count(array_unique($digests)) !== count($digests)) {
            throw new NativeError('crypto_batch_binding', 403);
        }
        if (!is_array($commitment['projectionGroups']) || !array_is_list($commitment['projectionGroups']) || count($commitment['projectionGroups']) !== count($expectedGroups)) {
            throw new NativeError('crypto_projection_group_binding', 403);
        }
        $expectedSets = [];
        foreach ($expectedGroups as $group) {
            sort($group, SORT_STRING);
            $expectedSets[] = implode(':', $group);
        }
        $last = '';
        foreach ($commitment['projectionGroups'] as $group) {
            if (!is_array($group)) {
                throw new NativeError('crypto_projection_group_binding', 403);
            }
            $this->fields($group, ['token', 'recordDigests']);
            $this->digest($group['token']);
            if (strcmp($last, $group['token']) >= 0 || !is_array($group['recordDigests']) || !array_is_list($group['recordDigests']) || !$group['recordDigests']) {
                throw new NativeError('crypto_projection_group_binding', 403);
            }
            $last = $group['token'];
            $ordered = $group['recordDigests'];
            foreach ($ordered as $hash) {
                $this->digest($hash);
            }
            sort($ordered, SORT_STRING);
            if ($ordered !== $group['recordDigests'] || count(array_unique($ordered)) !== count($ordered)) {
                throw new NativeError('crypto_projection_group_binding', 403);
            }
            $index = array_search(implode(':', $ordered), $expectedSets, true);
            if ($index === false) {
                throw new NativeError('crypto_projection_group_binding', 403);
            }
            unset($expectedSets[$index]);
        }
        if ($expectedSets) {
            throw new NativeError('crypto_projection_group_binding', 403);
        }
        return $records;
    }
    public function record(array $r)
    {
        $this->fields($r, ['version','operation','serverId','accountId','deviceId','batchId','scopeId','id','type','expectedRevision','deleted','epoch','accessRevision','membershipHeadHash','domain','contentContract','operationId','previousRecordHash','envelopeBase64','metadata']);
        foreach (['serverId','accountId','deviceId','batchId','scopeId','operationId'] as $key) {
            $this->uuid($r[$key]);
        }
        if ($r['version'] !== 2 || $r['operation'] !== 'crypto2.record' || !in_array($r['type'], array_merge(NativeCryptoStorage::TYPES, ['financeAccountChoice', 'taskDerivationIntent', 'taskDerivationResolution']), true) || !is_int($r['expectedRevision']) || $r['expectedRevision'] < 0 || !is_int($r['epoch']) || $r['epoch'] < 1 || !is_int($r['accessRevision']) || $r['accessRevision'] < 0 || !is_bool($r['deleted'])) {
            throw new NativeError('validation_error');
        }
        $domain = $this->domain($r['type']);
        if ($r['domain'] !== $domain || !in_array($r['contentContract'], $domain === 'finance' ? [3,4] : [6,7], true)) {
            throw new NativeError('crypto_domain_contract', 409);
        }
        $this->digest($r['membershipHeadHash']);
        $this->digest($r['previousRecordHash']);
        if (($r['expectedRevision'] === 0) !== ($r['previousRecordHash'] === NativeCryptoDirectoryV2::ZERO)) {
            throw new NativeError('crypto_record_chain', 409);
        }
        if ($r['deleted']) {
            if ($r['envelopeBase64'] !== null) {
                throw new NativeError('validation_error');
            }
        } else {
            $raw = NativeCryptoCodec::base64($r['envelopeBase64'], 196608);
            if (strlen($raw) < 48) {
                throw new NativeError('crypto_invalid_envelope');
            }
        }
        NativeCryptoRecordAddressV2::wireId($r['id']);
        NativeCryptoRecordAddressV2::verify($r);
        $this->metadata($r['metadata']);
        if(isset($r['metadata']['recordPolicyCompanion'])&&($r['type']!=='taskDerivationIntent'||$r['contentContract']!==6))throw new NativeError('crypto_record_policy_companion',409);
        $restore=$r['metadata']['recordRestore']??null;
        if(($restore!==null)!==(($r['metadata']['recordPolicy']['operation']??null)==='restore')||$restore!==null&&
            ($r['deleted']||$r['expectedRevision']<1||$r['contentContract']!==($domain==='finance'?4:7)||!(new NativeCryptoRecordPolicyV1($this->container))->business($r['type'])||$restore['tombstoneProofHash']!==$r['previousRecordHash']))throw new NativeError('crypto_record_restore_invalid',409);
        if (array_key_exists('migrationOrigin',$r['metadata']) &&
            ($r['expectedRevision']!==0 || $r['previousRecordHash']!==NativeCryptoDirectoryV2::ZERO)) {
            throw new NativeError('crypto_migration_origin_context',409);
        }
        if (array_key_exists('inlineDeletion',$r['metadata']) &&
            (!$r['deleted'] || $r['expectedRevision']<1)) {
            throw new NativeError('crypto_inline_deletion_tag',409);
        }
        if (isset($r['metadata']['projectRelocation'])) {
            $side=$r['metadata']['projectRelocation']['side'];
            if($side==='source'&&(($r['type']==='scopeMetadata'?$r['deleted']:!$r['deleted'])||$r['expectedRevision']<1)||$side==='target'&&$r['expectedRevision']!==0){
                throw new NativeError('crypto_relocation_tag',409);
            }
        }
        if (isset($r['metadata']['auditState']) && $domain !== 'finance') {
            throw new NativeError('crypto_audit_state_domain',409);
        }
        $remindable = in_array($r['type'], ['task','event','financeEntry','personalFinanceEntry'], true);
        if (!$r['deleted'] && $remindable !== isset($r['metadata']['reminderState'])) {
            throw new NativeError('crypto_reminder_state_required', 409);
        }
        if (!$remindable && isset($r['metadata']['reminderState'])) {
            throw new NativeError('validation_error');
        }
        $notifiable = self::notifiesType($r['type']);
        if ($notifiable !== isset($r['metadata']['notificationState']) || ($r['type'] === 'project') !== isset($r['metadata']['projectState'])) {
            throw new NativeError('crypto_notification_state_required', 409);
        }
        if ($notifiable) {
            $kind = $r['metadata']['notificationState']['kind'];
            if (($r['deleted'] !== ($kind === 'deleted')) || $kind === 'created' && $r['expectedRevision'] !== 0 || $kind === 'updated' && $r['expectedRevision'] === 0 || $kind === 'completed' && $r['type'] !== 'task' || $kind === 'checked' && $r['type'] !== 'shoppingItem') {
                throw new NativeError('crypto_notification_state_binding', 409);
            }
            if ($r['domain'] === 'finance' && ($r['metadata']['notificationState']['assigneeAccountIds'] || $r['metadata']['notificationState']['groupTargetId'] !== null)) {
                throw new NativeError('crypto_private_reference_forbidden', 409);
            }
        }
        if (isset($r['metadata']['repairOf']) && ($r['metadata']['repairOf']['revision'] !== $r['expectedRevision'] || $r['metadata']['repairOf']['recordProofHash'] !== $r['previousRecordHash'])) {
            throw new NativeError('crypto_repair_binding', 409);
        }
    }
    public function metadata($m)
    {
        if (!is_array($m)) {
            throw new NativeError('validation_error');
        }$this->fields($m, ['references','uniqueRefs','blobIds','identity'], ['referenceVersions','repairOf','reminderState','notificationState','projectState','auditState','schedulingUse','migrationOrigin','inlineDeletion','projectRelocation','recordPolicy','recordPolicyCompanion','recordRestore']);
        if(array_key_exists('recordPolicy',$m)) (new NativeCryptoRecordPolicyV1($this->container))->validate($m['recordPolicy']);
        if(array_key_exists('recordRestore',$m)) (new NativeCryptoRecordPolicyV1($this->container))->validateRestore($m['recordRestore']);
        if(array_key_exists('recordPolicyCompanion',$m)){
            $companion=$m['recordPolicyCompanion'];
            if(!is_array($companion))throw new NativeError('crypto_record_policy_companion',409);
            $this->fields($companion,['version','taskId','taskRevision','taskProofHash']);
            if($companion['version']!==1||!is_int($companion['taskRevision'])||$companion['taskRevision']<1)throw new NativeError('crypto_record_policy_companion',409);
            NativeCryptoRecordAddressV2::wireId($companion['taskId']);$this->digest($companion['taskProofHash']);
        }
        if (array_key_exists('projectRelocation',$m)) {
            if(array_key_exists('migrationOrigin',$m)||array_key_exists('inlineDeletion',$m))throw new NativeError('crypto_relocation_tag');
            NativeCryptoProjectRelocationCodecV2::tag($m['projectRelocation']);
        }
        if (array_key_exists('inlineDeletion',$m)) {
            if (!is_array($m['inlineDeletion']) || array_key_exists('migrationOrigin',$m)) throw new NativeError('crypto_inline_deletion_tag');
            $this->fields($m['inlineDeletion'],['version','actionId','planHash']);
            if ($m['inlineDeletion']['version']!==2) throw new NativeError('crypto_inline_deletion_tag');
            $this->uuid($m['inlineDeletion']['actionId']);$this->digest($m['inlineDeletion']['planHash']);
        }
        if (array_key_exists('migrationOrigin',$m)) {
            if (!is_array($m['migrationOrigin'])) throw new NativeError('validation_error');
            $this->fields($m['migrationOrigin'],['version','migrationId','captureId','bindingId','sourceInventoryRoot']);
            if ($m['migrationOrigin']['version']!==3) throw new NativeError('validation_error');
            foreach (['migrationId','captureId','bindingId'] as $field) $this->uuid($m['migrationOrigin'][$field]);
            $this->digest($m['migrationOrigin']['sourceInventoryRoot']);
        }
        if (isset($m['schedulingUse'])) {
            $this->fields($m['schedulingUse'], ['authorization','directoryHeadHash','eventCommandHash']);
            $this->digest($m['schedulingUse']['directoryHeadHash']);
            $this->digest($m['schedulingUse']['eventCommandHash']);
            (new NativeCryptoSchedulingUseV2($this->container))->body($m['schedulingUse']['authorization']);
        }
        if (isset($m['auditState'])) {
            if (!is_array($m['auditState'])) { throw new NativeError('validation_error'); }
            $this->fields($m['auditState'],['version','changedAt']);
            if ($m['auditState']['version'] !== 1) { throw new NativeError('validation_error'); }
            (new NativeRecordPolicy($this->container))->date($m['auditState']['changedAt']);
            if ((int)substr($m['auditState']['changedAt'],0,4) < 1970) { throw new NativeError('validation_error'); }
        }
        if (!isset($m['referenceVersions'])) {
            if ($m['references'] ?? null) { throw new NativeError('crypto_reference_version_binding',409); }
            $m['referenceVersions']=[];
        }
        foreach (['references' => 32,'referenceVersions' => 32,'uniqueRefs' => 10,'blobIds' => 20] as $key => $limit) {
            if (!is_array($m[$key]) || !array_is_list($m[$key]) || count($m[$key]) > $limit) {
                throw new NativeError('validation_error');
            }
        }
        $expected=[];
        foreach ($m['references'] as $reference) {
            if (!is_array($reference)) { throw new NativeError('validation_error'); }
            $this->fields($reference,['scopeId','id']);
            $this->uuid($reference['scopeId']);NativeCryptoRecordAddressV2::wireId($reference['id']);
            $pair=$reference['scopeId'].':'.$reference['id'];
            if (isset($expected[$pair])) { throw new NativeError('crypto_reference_version_binding',409); }
            $expected[$pair]=true;
        }
        $last='';
        foreach ($m['referenceVersions'] as $version) {
            if (!is_array($version)) { throw new NativeError('validation_error'); }
            $this->fields($version,['scopeId','id','domain','revision','recordProofHash']);
            $this->uuid($version['scopeId']);NativeCryptoRecordAddressV2::wireId($version['id']);$this->digest($version['recordProofHash']);
            $pair=$version['scopeId'].':'.$version['id'];
            $sort=$version['scopeId'].':'.$version['domain'].':'.$version['id'];
            if (!in_array($version['domain'],['content','finance'],true)||!is_int($version['revision'])||$version['revision']<1||$version['revision']>9007199254740991||strcmp($last,$sort)>=0||!isset($expected[$pair])) { throw new NativeError('crypto_reference_version_binding',409); }
            $last=$sort;unset($expected[$pair]);
        }
        if ($expected) { throw new NativeError('crypto_reference_version_binding',409); }
        if (isset($m['projectState'])) {
            if (!is_array($m['projectState'])) {
                throw new NativeError('validation_error');
            }
            $this->fields($m['projectState'], ['version','archived'], ['consentGeneration']);
            if (isset($m['projectState']['consentGeneration'])) { $this->uuid($m['projectState']['consentGeneration']); }
            if ($m['projectState']['version'] !== 1 || !is_bool($m['projectState']['archived'])) {
                throw new NativeError('validation_error');
            }
        }
        if (isset($m['notificationState'])) {
            $state = $m['notificationState'];
            if (!is_array($state)) {
                throw new NativeError('validation_error');
            }
            $this->fields($state, ['version','kind','assigneeAccountIds','groupTargetId']);
            if ($state['version'] !== 1 || !in_array($state['kind'], ['created','updated','completed','checked','deleted'], true) || !is_array($state['assigneeAccountIds']) || !array_is_list($state['assigneeAccountIds']) || count($state['assigneeAccountIds']) > 20) {
                throw new NativeError('validation_error');
            }
            $last = '';
            foreach ($state['assigneeAccountIds'] as $id) {
                $this->uuid($id);
                if (strcmp($id, $last) <= 0) {
                    throw new NativeError('validation_error');
                } $last = $id;
            }
            if ($state['groupTargetId'] !== null) {
                NativeCryptoRecordAddressV2::wireId($state['groupTargetId']);
            }
        }
        if (isset($m['reminderState'])) {
            $state = $m['reminderState'];
            if (!is_array($state)) {
                throw new NativeError('validation_error');
            }
            $this->fields($state, ['version','dueAtEpoch','closed','scheduleRevision'], ['consentGeneration']);
            if (isset($state['consentGeneration'])) { $this->uuid($state['consentGeneration']); }
            $this->uuid($state['scheduleRevision']);
            if ($state['version'] !== 1 || !is_bool($state['closed']) || $state['dueAtEpoch'] !== null && (!is_int($state['dueAtEpoch']) || $state['dueAtEpoch'] < 0 || $state['dueAtEpoch'] > 253402300799)) {
                throw new NativeError('validation_error');
            }
        }
        $seen = [];
        foreach ($m['references'] as $ref) {
            if (!is_array($ref)) {
                throw new NativeError('validation_error');
            }$this->fields($ref, ['scopeId','id']);
            $this->uuid($ref['scopeId']);
            NativeCryptoRecordAddressV2::wireId($ref['id']);
            $key = $ref['scopeId'].':'.$ref['id'];
            if (isset($seen[$key])) {
                throw new NativeError('validation_error');
            }$seen[$key] = true;
        }
        foreach ($m['uniqueRefs'] as $value) {
            $this->digest($value);
        }foreach ($m['blobIds'] as $value) {
            $this->uuid($value);
        }
        if (count(array_unique($m['uniqueRefs'])) !== count($m['uniqueRefs']) || count(array_unique($m['blobIds'])) !== count($m['blobIds'])) {
            throw new NativeError('validation_error');
        }
        if (isset($m['repairOf'])) {
            if (!is_array($m['repairOf'])) {
                throw new NativeError('validation_error');
            }$this->fields($m['repairOf'], ['revision','recordProofHash']);
            if (!is_int($m['repairOf']['revision']) || $m['repairOf']['revision'] < 1) {
                throw new NativeError('validation_error');
            }$this->digest($m['repairOf']['recordProofHash']);
        }
    }
    public static function notifiesType($type)
    {
        return !in_array($type, ['householdPerson','garden','table','attachment','scopeMetadata','notification','reminder','financeAccountChoice','taskDerivationIntent','taskDerivationResolution'], true);
    }

    public function domain($type)
    {
        return $this->financialRecordType($type) || in_array($type, ['paymentEvent','paymentProjection','cashMovement','financeAccountChoice','taskDerivationResolution'], true) ? 'finance' : 'content';
    }
    private function digest($value)
    {
        if (!is_string($value) || !preg_match('/^[a-f0-9]{64}$/D', $value)) {
            throw new NativeError('validation_error');
        }
    }
}
