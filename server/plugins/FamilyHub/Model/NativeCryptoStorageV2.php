<?php

namespace Kanboard\Plugin\FamilyHub\Model;

/** Atomic opaque records with per-record provenance and independently scoped domain cursors. */
class NativeCryptoStorageV2 extends NativeDatabase
{
    protected $cryptoAccess = true;
    public const MAX_BLOB = 23068672; // 22 MiB ciphertext; 20 MiB legacy files plus authenticated stream framing.
    private $inlinePlan=null;
    private $inlineFinal=[];
    private $inlineValidationOnly=false;
    private $relocationPlan=null;
    private $relocationFinal=[];
    private $relocationValidationOnly=false;

    /** Internal all-graph installer, never called by records.batch. Every
     * existing signature/role/CAS/reference check runs before the first effect. */
    public function installProjectRelocation($prepared,$actor,$command,$authorKey)
    {
        if($this->inlinePlan!==null||$this->relocationPlan!==null||!$this->transactionActive()||
            ($command['operation']??null)!=='crypto2.projectRelocation.commit'){
            throw new NativeError('crypto_relocation_transaction',409);
        }
        $plan=$prepared['plan'];
        $row=$this->one('SELECT state,plan_hash,account_id,device_id FROM familyhub_crypto_project_relocations_v2 WHERE action_id=?'.$this->lockSuffix(),[$plan['action_id']]);
        if(!$row||$row['state']!=='committing'||$row['plan_hash']!==$plan['plan_hash']||
            $row['account_id']!==$actor['user']['account_id']||$row['device_id']!==$actor['device']['id']){
            throw new NativeError('crypto_relocation_plan',409);
        }
        $this->relocationPlan=$plan+['originalReminderStates'=>$prepared['originalReminderStates']??[]];$this->relocationFinal=$prepared['entries'];
        try{
            $this->relocationValidationOnly=true;
            foreach($prepared['groups'] as $payload)$this->batch($payload,$actor,$command,$authorKey);
            $this->relocationValidationOnly=false;$results=[];
            foreach($prepared['groups'] as $payload)$results[]=$this->batch($payload,$actor,$command,$authorKey);
            return $results;
        }finally{
            $this->relocationPlan=null;$this->relocationFinal=[];$this->relocationValidationOnly=false;
        }
    }

    /** Internal two-phase installer. Every ordinary signature/ACL/CAS/table
     * check runs against the complete final graph before the first effect.
     * The normal records.batch route never enters this context. */
    public function installInlineDeletion($actionId,$groups,$actor,$command,$authorKey)
    {
        if($this->inlinePlan!==null||!$this->transactionActive())throw new NativeError('crypto_inline_delete_transaction',409);
        $plan=$this->one('SELECT * FROM familyhub_crypto_inline_delete_plans_v2 WHERE action_id=?'.$this->lockSuffix(),[$actionId]);
        if(!$plan||$plan['state']!=='committing'||$plan['account_id']!==$actor['user']['account_id']||$plan['device_id']!==$actor['device']['id']||($command['operation']??null)!=='crypto2.inlineDelete.commit')throw new NativeError('crypto_inline_delete_plan',409);
        if(!is_array($groups)||!array_is_list($groups)||!$groups||count($groups)>NativeCryptoInlineDeletionCodecV2::MAX_RECORDS)throw new NativeError('crypto_inline_delete_limit',409);
        $codec=new NativeCryptoRecordProofV2($this->container);$final=[];$batchIds=[];
        foreach($groups as $payload){
            if(isset($payload['exportBindings'])&&$payload['exportBindings'])throw new NativeError('crypto_inline_delete_bindings',409);
            if(isset($batchIds[$payload['batchId']??'']))throw new NativeError('crypto_inline_delete_batch_duplicate',409);$batchIds[$payload['batchId']]=true;
            foreach($codec->parseBatch($payload,$command,$authorKey) as $entry){
                $r=$entry['record'];$tag=$r['metadata']['inlineDeletion']??null;
                if(!$r['deleted']||$r['scopeId']!==$plan['scope_id']||!is_array($tag)||$tag['actionId']!==$actionId||$tag['planHash']!==$plan['plan_hash']||isset($final[$r['scopeId'].':'.$r['id']]))throw new NativeError('crypto_inline_delete_binding',409);
                $source=$this->one('SELECT * FROM familyhub_crypto_inline_delete_leaves_v2 WHERE action_id=? AND id=?',[$actionId,$r['id']]);
                if(!$source||$source['type']!==$r['type']||$source['domain']!==$r['domain']||(int)$source['revision']!==$r['expectedRevision']||$source['record_proof_hash']!==$r['previousRecordHash']||$source['tombstone_hash']!==$entry['recordProofHash']||$source['batch_id']!==$payload['batchId'])throw new NativeError('crypto_inline_delete_source_changed',409);
                $final[$r['scopeId'].':'.$r['id']]=$entry;
            }
        }
        if(count($final)!==(int)$plan['graph_count']||count($final)>NativeCryptoInlineDeletionCodecV2::MAX_RECORDS)throw new NativeError('crypto_inline_delete_incomplete',409);
        $this->inlinePlan=$plan;$this->inlineFinal=$final;
        try{
            $this->inlineValidationOnly=true;
            foreach($groups as $payload)$this->batch($payload,$actor,$command,$authorKey);
            $this->inlineValidationOnly=false;$results=[];
            foreach($groups as $payload)$results[]=$this->batch($payload,$actor,$command,$authorKey);
            return $results;
        }finally{$this->inlinePlan=null;$this->inlineFinal=[];$this->inlineValidationOnly=false;}
    }

    public function write($op, $payload, $actor, $proof, $command, $authorKey)
    {
        if ($op === 'crypto2.records.batch') {
            return $this->batch($payload, $actor, $command, $authorKey);
        }
        return $this->blobWrite($op, $payload, $actor, $proof);
    }

    private function batch($payload, $actor, $command, $authorKey)
    {
        $codec = new NativeCryptoRecordProofV2($this->container);
        $records = $codec->parseBatch($payload, $command, $authorKey);
        $scopes = new NativeCryptoScopeV2($this->container, $this->bearer, $this->ip);
        $prepared = [];
        $scopeIds = [];
        foreach ($records as $entry) {
            $r = $entry['record'];
            if (array_key_exists('projectRelocation',$r['metadata'])) {
                // Only the dedicated all-graph coordinator may install these
                // signed preparatory proofs. Normal batches never publish them.
                $tag=$r['metadata']['projectRelocation'];
                $expected=$this->relocationFinal[$r['scopeId'].':'.$r['id']]??null;
                if($this->relocationPlan===null||$tag['actionId']!==$this->relocationPlan['action_id']||
                    $tag['planHash']!==$this->relocationPlan['plan_hash']||!$expected||
                    $expected['recordProofHash']!==$entry['recordProofHash']){
                    throw new NativeError('crypto_project_relocation_forbidden',409);
                }
            }elseif($this->relocationPlan!==null){
                throw new NativeError('crypto_relocation_record_binding',409);
            }
            if (array_key_exists('migrationOrigin',$r['metadata'])) {
                throw new NativeError('crypto_migration_origin_forbidden',409);
            }
            if (array_key_exists('inlineDeletion',$r['metadata'])) {
                $tag=$r['metadata']['inlineDeletion'];
                if($this->inlinePlan===null||$tag['actionId']!==$this->inlinePlan['action_id']||$tag['planHash']!==$this->inlinePlan['plan_hash']||!$r['deleted'])throw new NativeError('crypto_inline_deletion_forbidden',409);
            } elseif($this->inlinePlan!==null) {throw new NativeError('crypto_inline_delete_binding',409);}

            $scopeIds[] = $r['scopeId'];
            foreach ($r['metadata']['references'] as $ref) {
                $scopeIds[] = $ref['scopeId'];
            }
        }
        sort($scopeIds, SORT_STRING);
        foreach (array_unique($scopeIds) as $sid) {
            $this->scope($sid, $actor['user']['id']);
        }
        foreach ($records as $entry) {
            $r = $entry['record'];
            $schedule = $r['metadata']['reminderState'] ?? null;
            if ($schedule && isset($schedule['consentGeneration']) && $schedule['dueAtEpoch'] !== null) {
                if ($schedule['closed'] || $r['deleted']) { throw new NativeError('crypto_scheduling_closed_date',409); }
                $preserved=$this->relocationPlan['originalReminderStates'][$r['scopeId'].':'.$r['id']]??null;
                if($preserved===null||NativeCryptoCodec::canonical((object)$preserved)!==NativeCryptoCodec::canonical((object)$schedule)) {
                    (new NativeCryptoSchedulingUseV2($this->container,$this->bearer,$this->ip))->validateMetadata($r);
                }
            }
            [$recordScope,$recordHead] = $scopes->author($r['scopeId'], $r['membershipHeadHash'], $r['epoch'], $r['accessRevision'], $actor, $r['domain']);
            if ($r['type']==='scopeMetadata') {
                $scopes->manager($recordHead,$recordScope,$actor);
            }
            $old = $this->one('SELECT * FROM familyhub_crypto_records WHERE scope_id=? AND id=?', [$r['scopeId'], $r['id']]);
            (new NativeCryptoNotificationV2($this->container,$this->bearer,$this->ip))->validateConsentTransition($r,$old);
            $oldProof = $old ? json_decode($old['authorization'], true, 34, JSON_THROW_ON_ERROR) : null;
            if ($old && !isset($oldProof['recordProof'])) {
                throw new NativeError('crypto_v1_record_migration_required', 409);
            }
            if ((int)($old['revision'] ?? 0) !== $r['expectedRevision']) {
                $notice = $old ? (new NativeCryptoModerationAvailabilityV2($this->container,$this->bearer,$this->ip))->restriction($r['scopeId'],$r['id'],(int)$old['revision']) : null;
                throw new NativeError('conflict', 409, ['scopeId' => $r['scopeId'], 'id' => $r['id'], 'remote' => $old && !$notice ? $this->wire($old) : null] + ($notice ? ['unavailable' => [$notice]] : []));
            }
            if ($old) {
                $oldIdentity=json_decode($old['metadata'],true,34,JSON_THROW_ON_ERROR)['identity']??null;
                if ($oldIdentity!==null && NativeCryptoCodec::canonical((object)$oldIdentity)!==NativeCryptoCodec::canonical((object)$r['metadata']['identity'])) { throw new NativeError('crypto_record_identity_collision',409); }
            }
            if ($old && ($old['type'] !== $r['type'] || NativeCryptoV2Codec::hash((object)$oldProof['recordProof']) !== $r['previousRecordHash'])) {
                throw new NativeError('crypto_record_chain', 409);
            }
            if ($old) {
                $position = $this->one('SELECT domain,sequence FROM familyhub_crypto_record_positions WHERE scope_id=? AND id=?', [$r['scopeId'], $r['id']]);
                if (!$position || $position['domain'] !== $r['domain']) {
                    throw new NativeError('crypto_domain_cursor_unavailable', 503);
                }
            }
            foreach ($r['metadata']['blobIds'] as $id) {
                $blob = $this->one('SELECT * FROM familyhub_crypto_blobs_v2 WHERE scope_id=? AND id=? AND complete=1', [$r['scopeId'], $id]);
                if (!$blob || $blob['domain'] !== $r['domain'] || (int)$blob['epoch'] > $r['epoch']) {
                    throw new NativeError('crypto_blob_incomplete', 409);
                }
                (new NativeCryptoModerationAvailabilityV2($this->container,$this->bearer,$this->ip))->assertBlob($r['scopeId'],$id,$r['domain']);
            }
            $entry['old'] = $old;
            $prepared[$r['scopeId'].':'.$r['id']] = $entry;
        }
        (new NativeCryptoTableV2($this->container, $this->bearer, $this->ip))->assertBatch($payload, $prepared, $actor);
        (new NativeCryptoExportV2($this->container, $this->bearer, $this->ip))->writeBatch(
            $payload['exportBindings'] ?? [], $prepared, $actor, $command, $authorKey
        );
        // Final overlay validation catches both ordering and included-but-deleted targets.
        foreach ($prepared as $entry) {
            $r = $entry['record'];
            if ($r['deleted']) {
                continue;
            }
            foreach ($r['metadata']['references'] as $ref) {
                $targetKey = $ref['scopeId'].':'.$ref['id'];
                $overlay=$this->relocationFinal+$prepared;
                $target = isset($overlay[$targetKey]) ? $overlay[$targetKey]['record'] : $this->one('SELECT * FROM familyhub_crypto_records WHERE scope_id=? AND id=?', [$ref['scopeId'], $ref['id']]);
                if (!$target || $target['deleted'] && !($r['type']==='taskDerivationResolution' && $target['type']==='task' && $r['scopeId']===$ref['scopeId'])) {
                    throw new NativeError('crypto_reference_missing', 409);
                }
                // An unchanged signed blocked CURRENT row is still unavailable;
                // fresh references cannot manufacture a historical-evidence bypass.
                if (!isset($overlay[$targetKey]) && (new NativeCryptoModerationAvailabilityV2($this->container))->restriction($ref['scopeId'],$ref['id'],(int)$target['revision'])) {
                    throw new NativeError('crypto_content_restricted', 403);
                }
                $this->referenceAccess($r, $ref, $target, $actor, $codec, $scopes);
                $versions=array_values(array_filter($r['metadata']['referenceVersions'],fn($v)=>$v['scopeId']===$ref['scopeId']&&$v['id']===$ref['id']));
                $version=$versions[0];
                $targetDomain=$codec->domain($target['type']);
                if (isset($overlay[$targetKey])) {
                    $targetRevision=$target['expectedRevision']+1;
                    $targetHash=$overlay[$targetKey]['recordProofHash'];
                } else {
                    $targetRevision=(int)$target['revision'];
                    $targetAuthorization=json_decode($target['authorization'],true,34,JSON_THROW_ON_ERROR);
                    if (!isset($targetAuthorization['recordProof'])) { throw new NativeError('crypto_v1_record_migration_required',409); }
                    $targetHash=NativeCryptoV2Codec::hash((object)$targetAuthorization['recordProof']);
                }
                if ($version['domain']!==$targetDomain||$version['revision']!==$targetRevision||$version['recordProofHash']!==$targetHash) {
                    throw new NativeError('crypto_reference_changed',409);
                }
            }
        }
        foreach ($prepared as $entry) {
            $r = $entry['record'];
            if ($r['deleted']) {
                $this->assertNoLiveChildren($r, $prepared);
            }
        }
        if($this->inlineValidationOnly||$this->relocationValidationOnly)return ['status'=>'validated','batchId'=>$payload['batchId']];
        // Release every old unique index entry before applying the final batch permutation.
        foreach ($prepared as $entry) {
            $r = $entry['record'];
            $this->change('DELETE FROM familyhub_crypto_unique_refs WHERE scope_id=? AND record_id=?', [$r['scopeId'], $r['id']]);
        }
        foreach ($prepared as $entry) {
            $r = $entry['record'];
            foreach ($r['deleted'] ? [] : $r['metadata']['uniqueRefs'] as $unique) {
                if ($this->one('SELECT record_id FROM familyhub_crypto_unique_refs WHERE scope_id=? AND reference_hash=?', [$r['scopeId'], $unique])) {
                    throw new NativeError('crypto_unique_conflict', 409);
                }
                $this->change('INSERT INTO familyhub_crypto_unique_refs VALUES(?,?,?)', [$r['scopeId'], $unique, $r['id']]);
            }
        }
        $out = [];
        foreach ($prepared as $entry) {
            $r = $entry['record'];
            $sid = $r['scopeId'];
            $domain = $r['domain'];
            $sequence = $scopes->domainSequence($sid, $domain) + 1;
            $global = $this->one('SELECT sequence FROM familyhub_crypto_scopes WHERE scope_id=?', [$sid]);
            if (!$global) {
                throw new NativeError('crypto_scope_not_ready', 409);
            }
            $globalSequence = (int)$global['sequence'] + 1;
            $revision = $r['expectedRevision'] + 1;
            $authorization = json_encode(['recordProof' => $entry['recordProof'], 'batchCommitment' => $entry['batchCommitment']], JSON_THROW_ON_ERROR);
            $values = [$r['type'], $revision, (int)$r['deleted'], $globalSequence, $r['epoch'], $r['envelopeBase64'] ?? '', NativeCryptoCodec::canonical((object)$r['metadata']), $authorization, $sid, $r['id']];
            if ($r['expectedRevision']) {
                $this->change('UPDATE familyhub_crypto_records SET type=?,revision=?,deleted=?,sequence=?,epoch=?,envelope=?,metadata=?,authorization=? WHERE scope_id=? AND id=?', $values);
                $this->change('UPDATE familyhub_crypto_record_positions SET sequence=? WHERE scope_id=? AND id=? AND domain=?', [$sequence, $sid, $r['id'], $domain]);
            } else {
                $this->change('INSERT INTO familyhub_crypto_records(type,revision,deleted,sequence,epoch,envelope,metadata,authorization,scope_id,id) VALUES(?,?,?,?,?,?,?,?,?,?)', $values);
                $this->change('INSERT INTO familyhub_crypto_record_positions VALUES(?,?,?,?)', [$sid, $r['id'], $domain, $sequence]);
            }
            $this->change('UPDATE familyhub_crypto_domain_cursors SET sequence=? WHERE scope_id=? AND domain=?', [$sequence, $sid, $domain]);
            $this->change('UPDATE familyhub_crypto_scopes SET sequence=? WHERE scope_id=?', [$globalSequence, $sid]);
            $this->change('INSERT INTO familyhub_crypto_record_history VALUES(?,?,?,?,?,?,?,?,?)', [$sid, $r['id'], $revision, $sequence, $r['epoch'], $domain, $entry['recordProofHash'], json_encode($entry['recordProof'], JSON_THROW_ON_ERROR), json_encode($entry['batchCommitment'], JSON_THROW_ON_ERROR)]);
            if ($r['type'] === 'table' && $r['deleted']) {
                $this->change('DELETE FROM familyhub_crypto_table_leases WHERE scope_id=? AND id=?', [$sid, $r['id']]);
            }
            $out[] = ['scopeId' => $sid, 'id' => $r['id'], 'revision' => $revision, 'sequence' => $sequence, 'recordProofHash' => $entry['recordProofHash']];
        }
        foreach ($this->relocationPlan===null?$prepared:[] as $entry) {
            $notifications = new NativeCryptoNotificationV2($this->container, $this->bearer, $this->ip);
            $notifications->changed($entry['record'], $entry['old']);
            $notifications->emit($entry['record'], $entry['old']);
        }
        return ['status' => 'applied', 'batchId' => $payload['batchId'], 'records' => $out];
    }

    private function referenceAccess($record, $ref, $target, $actor, $codec, $scopes)
    {
        $targetDomain = $codec->domain($target['type']);
        $allowedFinanceContext = in_array($record['type'], ['financeEntry','personalFinanceEntry'], true) && in_array($target['type'], ['task','project','householdPerson'], true)
            || $record['type']==='taskDerivationResolution' && in_array($target['type'],['taskDerivationIntent','task'],true);
        $sameScopeFinanceContext = $record['domain'] === 'finance' && $targetDomain === 'content' && $record['scopeId'] === $ref['scopeId'] && $allowedFinanceContext;
        if ($targetDomain !== $record['domain'] && !$sameScopeFinanceContext) {
            throw new NativeError('crypto_private_reference_forbidden', 409);
        }
        $targetScope = $this->scope($ref['scopeId'], $actor['user']['id']);
        if ($targetDomain === 'finance') {
            (new NativeFinanceAccess($this->container))->policyForCrypto($ref['scopeId'], $actor['user'], false, true);
        }
        if ($ref['scopeId'] === $record['scopeId']) {
            if ($sameScopeFinanceContext) {
                $sourceHead = $scopes->current($record['scopeId']);
                $access = new NativeOrganizationAccess($this->container);
                foreach ($scopes->body($sourceHead)['members'] as $member) {
                    if ($member['financeRole'] !== 'none' && !$access->visibleScope($ref['scopeId'], $member['accountId'])) {
                        throw new NativeError('crypto_private_reference_forbidden', 409);
                    }
                }
            }
            return;
        }
        $source = $this->scope($record['scopeId'], $actor['user']['id']);
        $sourceParent = $source['parent_scope_id'] ?? $source['organization_id'] ?? null;
        $targetParent = $targetScope['parent_scope_id'] ?? $targetScope['organization_id'] ?? null;
        if ($sourceParent !== $ref['scopeId'] && $targetParent !== $record['scopeId']) {
            throw new NativeError('crypto_structural_reference_forbidden', 409);
        }
        // Plain reference metadata is visible to every source-domain recipient. No private payer IDs.
        $head = $scopes->current($record['scopeId']);
        $access = new NativeOrganizationAccess($this->container);
        foreach ($scopes->body($head)['members'] as $member) {
            if ($record['domain'] === 'finance' && $member['financeRole'] === 'none') {
                continue;
            }
            if (!$access->visibleScope($ref['scopeId'], $member['accountId']) || $targetDomain === 'finance' && !(new NativeFinanceAccess($this->container))->visible($ref['scopeId'], $member['accountId'], true)) {
                throw new NativeError('crypto_private_reference_forbidden', 409);
            }
        }
    }

    /** A standalone task tombstone does not delete money. Existing exact
     * finance links remain historical until a FINANCE writer publishes a
     * proof-bound detach resolution. No project/other target gets this rule. */
    private function taskDeletionEvidence($deleted,$source,$ref)
    {
        if($deleted['type']!=='task'||($source['scopeId']??null)!==$deleted['scopeId']
            ||!in_array($source['type']??null,['financeEntry','personalFinanceEntry','taskDerivationResolution'],true))return false;
        foreach($source['metadata']['referenceVersions']??[] as $v){
            if($v['scopeId']===$ref['scopeId']&&$v['id']===$ref['id']&&$v['domain']==='content'
                &&is_int($v['revision'])&&$v['revision']>=1&&$v['revision']<=$deleted['expectedRevision'])return true;
        }
        return false;
    }

    private function assertNoLiveChildren($deleted, $prepared)
    {
        if($this->inlinePlan!==null)$prepared=$this->inlineFinal+$prepared;
        if($this->relocationPlan!==null)$prepared=$this->relocationFinal+$prepared;
        $scope = $this->one('SELECT parent_scope_id,organization_id FROM familyhub_scopes WHERE id=?', [$deleted['scopeId']]);
        $ids = [$deleted['scopeId']];
        foreach ($this->many('SELECT id FROM familyhub_scopes WHERE parent_scope_id=? OR organization_id=?', [$deleted['scopeId'], $deleted['scopeId']]) as $child) {
            $ids[] = $child['id'];
        }
        $parent = $scope['parent_scope_id'] ?? $scope['organization_id'] ?? null;
        if ($parent) {
            $ids[] = $parent;
        }
        foreach ($this->iterate('SELECT scope_id,id,type,deleted,metadata FROM familyhub_crypto_records WHERE scope_id IN ('.implode(',', array_fill(0, count($ids), '?')).')', $ids) as $row) {
            $key = $row['scope_id'].':'.$row['id'];
            $final = $prepared[$key]['record'] ?? ['type'=>$row['type'],'scopeId'=>$row['scope_id'],'deleted' => (bool)$row['deleted'], 'metadata' => json_decode($row['metadata'], true, 34, JSON_THROW_ON_ERROR)];
            if ($final['deleted']) {
                continue;
            }
            foreach ($final['metadata']['references'] as $ref) {
                if ($ref['scopeId'] === $deleted['scopeId'] && $ref['id'] === $deleted['id']) {
                    if($this->taskDeletionEvidence($deleted,$final,$ref))continue;
                    throw new NativeError('crypto_live_children', 409);
                }
            }
        }
        foreach ($prepared as $entry) {
            $r = $entry['record'];
            if (!$r['deleted']) {
                foreach ($r['metadata']['references'] as $ref) {
                    if ($ref['scopeId'] === $deleted['scopeId'] && $ref['id'] === $deleted['id']) {
                        if($this->taskDeletionEvidence($deleted,$r,$ref))continue;
                        throw new NativeError('crypto_live_children', 409);
                    }
                }
            }
        }
    }

    public function read($op, $p, $actor)
    {
        if ($op === 'crypto2.records.historyGet') {
            return $this->historyGet($p, $actor);
        }
        if ($op === 'crypto2.records.history') {
            return $this->history($p, $actor);
        }
        if (str_starts_with($op, 'crypto2.blob.')) {
            return $this->blobRead($op, $p, $actor);
        }
        $this->fields($p, ['scopeId', 'domain', 'cursor', 'accessRevision'], ['limit']);
        $sid = $this->uuid($p['scopeId']);
        $scopes = new NativeCryptoScopeV2($this->container, $this->bearer, $this->ip);
        $head = $scopes->current($sid);
        if (!$head) {
            throw new NativeError('crypto_scope_head_missing', 404);
        }
        $scopes->author($sid, $head['head_hash'], (int)$head['epoch'], $p['accessRevision'], $actor, $p['domain'], false);
        $sequence = $scopes->domainSequence($sid, $p['domain']);
        $cursor = $p['cursor'];
        $limit = $p['limit'] ?? 20;
        if (!is_int($cursor) || $cursor < 0 || $cursor > $sequence || !is_int($limit) || $limit < 1 || $limit > 50) {
            throw new NativeError('invalid_cursor');
        }
        $rows = $this->many('SELECT r.*,p.sequence AS domain_sequence FROM familyhub_crypto_records r JOIN familyhub_crypto_record_positions p ON p.scope_id=r.scope_id AND p.id=r.id WHERE p.scope_id=? AND p.domain=? AND p.sequence>? ORDER BY p.sequence LIMIT '.($limit + 1), [$sid, $p['domain'], $cursor]);
        $out = [];
        $unavailable = [];
        $bytes = 0;
        $scanned = 0;
        $last = $cursor;
        $availability = new NativeCryptoModerationAvailabilityV2($this->container,$this->bearer,$this->ip);
        foreach ($rows as $row) {
            if ($scanned === $limit) {
                break;
            }
            $notice = $availability->restriction($sid,$row['id'],(int)$row['revision']);
            $wire = $notice ? null : $this->wire($row);
            $size = strlen(json_encode($wire ?? $notice, JSON_THROW_ON_ERROR));
            if ($scanned && $bytes + $size > 1250000) {
                break;
            }
            if ($notice) {
                $unavailable[] = $notice;
            } else {
                $out[] = $wire;
            }
            $scanned++;
            $last = (int)$row['domain_sequence'];
            $bytes += $size;
        }
        $more = count($rows) > $scanned;
        // This cursor is transport progress only; missing proofs keep signed
        // checkpoint/inventory coverage incomplete on the receiving client.
        return ['records' => $out, 'unavailable' => $unavailable, 'cursor' => $more ? $last : $sequence, 'hasMore' => $more, 'scopeSequence' => $sequence, 'epoch' => (int)$head['epoch'], 'accessRevision' => $p['accessRevision']];
    }

    private function historyGet($p, $actor)
    {
        $this->fields($p, ['scopeId', 'domain', 'accessRevision', 'recordProofHash'], ['id', 'revision', 'evidenceFor']);
        $sid = $this->uuid($p['scopeId']);
        $hasId = array_key_exists('id', $p);
        if ($hasId !== array_key_exists('revision', $p) ||
            $hasId && (!is_int($p['revision']) || $p['revision'] < 1) ||
            !is_string($p['recordProofHash']) || !preg_match('/^[a-f0-9]{64}$/D', $p['recordProofHash'])) {
            throw new NativeError('validation_error');
        }
        $scopes = new NativeCryptoScopeV2($this->container, $this->bearer, $this->ip);
        $head = $scopes->current($sid);
        if (!$head) {
            throw new NativeError('crypto_scope_head_missing', 404);
        }
        $scopes->author($sid, $head['head_hash'], (int)$head['epoch'], $p['accessRevision'], $actor, $p['domain'], false);
        if ($hasId) {
            $id = NativeCryptoRecordAddressV2::wireId($p['id']);
            $row = $this->one('SELECT * FROM familyhub_crypto_record_history WHERE scope_id=? AND id=? AND revision=? AND domain=?', [$sid, $id, $p['revision'], $p['domain']]);
        } else {
            // The authenticated projection group commits sibling digests while
            // intentionally withholding their IDs. This is an exact indexed
            // candidate lookup, never proof that a sibling is current/applied.
            $rows = $this->many('SELECT * FROM familyhub_crypto_record_history WHERE scope_id=? AND domain=? AND record_proof_hash=? LIMIT 2', [$sid, $p['domain'], $p['recordProofHash']]);
            if (count($rows) > 1) {
                throw new NativeError('crypto_record_history_ambiguous', 503);
            }
            $row = $rows[0] ?? null;
            $id = $row['id'] ?? null;
        }
        if (!$row) {
            throw new NativeError('crypto_record_missing', 404);
        }
        if (!hash_equals($row['record_proof_hash'], $p['recordProofHash'])) {
            throw new NativeError('crypto_record_proof_mismatch', 409);
        }
        $availability = new NativeCryptoModerationAvailabilityV2($this->container,$this->bearer,$this->ip);
        $notice = $availability->restriction($sid,$id,(int)$row['revision'],$p['recordProofHash']);
        if ($notice) {
            if (!isset($p['evidenceFor'])) {
                throw new NativeError('crypto_content_restricted',403,['unavailable' => $notice]);
            }
            $availability->evidence($row,$p['evidenceFor'],$actor);
            return ['record' => $this->historyWire($row),'verificationEvidence' => true,'unavailable' => [$notice]];
        }
        return ['record' => $this->historyWire($row)];
    }

    private function historyWire($row)
    {
        $recordProof = json_decode($row['record_proof'], true, 34, JSON_THROW_ON_ERROR);
        [$record] = NativeCryptoCodec::decode($recordProof);
        $authorization=$this->withMigrationOrigin($row['scope_id'],$row['id'],$record['domain'],
            $recordProof,json_decode($row['batch_commitment'],true,34,JSON_THROW_ON_ERROR));
        return ['scopeId' => $row['scope_id'], 'id' => $row['id'], 'type' => $record['type'], 'revision' => (int)$row['revision'], 'sequence' => (int)$row['sequence'], 'deleted' => $record['deleted'], 'epoch' => (int)$row['epoch'], 'envelopeBase64' => $record['envelopeBase64'], 'metadata' => $record['metadata'], 'authorization' => $authorization];
    }

    /** Signed record metadata selects mandatory provenance verification.
     * Authorization transport stays the exact original two-proof object. */
    private function withMigrationOrigin($scopeId,$wireId,$domain,$recordProof,$batchCommitment)
    {
        return ['recordProof'=>$recordProof,'batchCommitment'=>$batchCommitment];
    }

    private function history($p, $actor)
    {
        $this->fields($p, ['scopeId', 'id', 'domain', 'accessRevision', 'afterRevision'], ['limit']);
        $sid = $this->uuid($p['scopeId']);
        $id = NativeCryptoRecordAddressV2::wireId($p['id']);
        $scopes = new NativeCryptoScopeV2($this->container, $this->bearer, $this->ip);
        $head = $scopes->current($sid);
        if (!$head) {
            throw new NativeError('crypto_scope_head_missing', 404);
        }
        $scopes->author($sid, $head['head_hash'], (int)$head['epoch'], $p['accessRevision'], $actor, $p['domain'], false);
        $after = $p['afterRevision'];
        $limit = $p['limit'] ?? 20;
        if (!is_int($after) || $after < 0 || !is_int($limit) || $limit < 1 || $limit > 50) {
            throw new NativeError('invalid_cursor');
        }
        $rows = $this->many('SELECT * FROM familyhub_crypto_record_history WHERE scope_id=? AND id=? AND domain=? AND revision>? ORDER BY revision LIMIT '.($limit + 1), [$sid, $id, $p['domain'], $after]);
        $out = [];
        $unavailable = [];
        $bytes = 0;
        $scanned = 0;
        $last = $after;
        $availability = new NativeCryptoModerationAvailabilityV2($this->container,$this->bearer,$this->ip);
        foreach ($rows as $row) {
            if ($scanned === $limit) {
                break;
            }
            $notice = $availability->restriction($sid,$id,(int)$row['revision'],$row['record_proof_hash']);
            $wire = $notice ? null : $this->historyWire($row);
            $size = strlen(json_encode($wire ?? $notice, JSON_THROW_ON_ERROR));
            if ($scanned && $bytes + $size > 1250000) {
                break;
            }
            if ($notice) {
                $unavailable[] = $notice;
            } else {
                $out[] = $wire;
            }
            $scanned++;
            $last = (int)$row['revision'];
            $bytes += $size;
        }
        return ['records' => $out,'unavailable' => $unavailable,'hasMore' => count($rows) > $scanned,'nextRevision' => $last];
    }

    private function wire($row)
    {
        $proof = json_decode($row['authorization'], true, 34, JSON_THROW_ON_ERROR);
        if (!isset($proof['recordProof'], $proof['batchCommitment'])) {
            throw new NativeError('crypto_v1_record_migration_required', 409);
        }
        $position = isset($row['domain_sequence']) ? (int)$row['domain_sequence'] : (int)($this->one('SELECT sequence FROM familyhub_crypto_record_positions WHERE scope_id=? AND id=?', [$row['scope_id'], $row['id']])['sequence'] ?? -1);
        if ($position < 0) {
            throw new NativeError('crypto_domain_cursor_unavailable', 503);
        }
        [$record]=NativeCryptoCodec::decode($proof['recordProof']);
        $authorization=$this->withMigrationOrigin($row['scope_id'],$row['id'],$record['domain'],
            $proof['recordProof'],$proof['batchCommitment']);
        return ['scopeId' => $row['scope_id'], 'id' => $row['id'], 'type' => $row['type'], 'revision' => (int)$row['revision'], 'deleted' => (bool)$row['deleted'], 'sequence' => $position, 'epoch' => (int)$row['epoch'], 'envelopeBase64' => (bool)$row['deleted'] ? null : $row['envelope'], 'metadata' => json_decode($row['metadata'], true, 34, JSON_THROW_ON_ERROR), 'authorization' => $authorization];
    }

    private function blobAuthority($p, $actor, $write)
    {
        $sid = $this->uuid($p['scopeId'] ?? null);
        $scopes = new NativeCryptoScopeV2($this->container, $this->bearer, $this->ip);
        $head = $scopes->current($sid);
        if (!$head) {
            throw new NativeError('crypto_scope_head_missing', 404);
        }
        $scopes->author($sid, $write ? ($p['membershipHeadHash'] ?? null) : $head['head_hash'], $write ? ($p['epoch'] ?? null) : (int)$head['epoch'], $p['accessRevision'] ?? null, $actor, $p['domain'] ?? null, $write);
        return $head;
    }

    private function blobWrite($op, $p, $actor, $proof)
    {
        $common = ['scopeId', 'id', 'domain', 'epoch', 'accessRevision', 'membershipHeadHash'];
        $extra = $op === 'crypto2.blob.begin' ? ['size', 'sha256', 'manifestBase64'] : ($op === 'crypto2.blob.chunk' ? ['offset', 'dataBase64'] : ($op === 'crypto2.blob.abort' ? ['sha256'] : []));
        if (!in_array($op, ['crypto2.blob.begin', 'crypto2.blob.chunk', 'crypto2.blob.complete', 'crypto2.blob.abort'], true)) {
            throw new NativeError('unsupported_operation', 404);
        }
        $this->fields($p, array_merge($common, $extra));
        $this->blobAuthority($p, $actor, $op !== 'crypto2.blob.abort');
        $sid = $p['scopeId'];
        $id = $this->uuid($p['id']);
        $old = $this->one('SELECT * FROM familyhub_crypto_blobs_v2 WHERE scope_id=? AND id=?', [$sid, $id]);
        if ($op === 'crypto2.blob.begin') {
            if (!is_int($p['size']) || $p['size'] < 48 || $p['size'] > self::MAX_BLOB || !is_string($p['sha256']) || !preg_match('/^[a-f0-9]{64}$/D', $p['sha256'])) {
                throw new NativeError('validation_error');
            }
            if (strlen(NativeCryptoCodec::base64($p['manifestBase64'], 16384)) < 48) {
                throw new NativeError('crypto_invalid_envelope');
            }
            if ($old) {
                if ((int)$old['complete'] < 0) {
                    throw new NativeError('crypto_blob_aborted', 409);
                }
                if ($old['owner_account_id'] !== $actor['user']['account_id'] || $old['head_hash'] !== $p['membershipHeadHash'] || $old['domain'] !== $p['domain'] || (int)$old['epoch'] !== $p['epoch'] || (int)$old['size'] !== $p['size'] || $old['sha256'] !== $p['sha256'] || $old['manifest'] !== $p['manifestBase64']) {
                    throw new NativeError('crypto_blob_immutable', 409);
                }
            } else {
                $this->assertBlobQuota($sid, $p['domain'], $p['size'], $actor);
                $this->change('INSERT INTO familyhub_crypto_blobs_v2(scope_id,id,head_hash,domain,owner_account_id,epoch,size,sha256,manifest,authorization) VALUES(?,?,?,?,?,?,?,?,?,?)', [$sid, $id, $p['membershipHeadHash'], $p['domain'], $actor['user']['account_id'], $p['epoch'], $p['size'], $p['sha256'], $p['manifestBase64'], json_encode($proof, JSON_THROW_ON_ERROR)]);
            }
            return ['id' => $id, 'offset' => (int)($old['received'] ?? 0), 'complete' => (bool)($old['complete'] ?? false)];
        }
        if (!$old || $old['owner_account_id'] !== $actor['user']['account_id'] || $old['domain'] !== $p['domain'] || $old['head_hash'] !== $p['membershipHeadHash'] || (int)$old['epoch'] !== $p['epoch']) {
            throw new NativeError('crypto_blob_missing', 404);
        }
        if ($op === 'crypto2.blob.abort') {
            if ((int)$old['complete'] !== 0 || !is_string($p['sha256']) || !hash_equals($old['sha256'], $p['sha256'])) {
                throw new NativeError('crypto_blob_abort_forbidden', 409);
            }
            foreach ($this->iterate('SELECT record_proof FROM familyhub_crypto_record_history WHERE scope_id=?', [$sid]) as $history) {
                [$record] = NativeCryptoCodec::decode(json_decode($history['record_proof'], true, 34, JSON_THROW_ON_ERROR));
                if (in_array($id, $record['metadata']['blobIds'], true)) {
                    throw new NativeError('crypto_blob_referenced', 409);
                }
            }
            // SQL chunk removal, tombstone and immutable service receipt commit in the same transaction.
            $this->change('UPDATE familyhub_crypto_blobs_v2 SET complete=-1 WHERE scope_id=? AND id=?', [$sid, $id]);
            $this->change('DELETE FROM familyhub_crypto_blob_chunks_v2 WHERE scope_id=? AND blob_id=?', [$sid, $id]);
            return ['id' => $id, 'state' => 'aborted', 'sha256' => $old['sha256']];
        }
        if ((int)$old['complete'] < 0) {
            throw new NativeError('crypto_blob_aborted', 409);
        }
        if ($op === 'crypto2.blob.chunk') {
            $data = NativeCryptoCodec::base64($p['dataBase64'], NativeCryptoStorage::CHUNK);
            $offset = $p['offset'];
            if (strlen($data) < 1 || !is_int($offset) || $offset < 0 || $offset % NativeCryptoStorage::CHUNK !== 0 || $offset + strlen($data) > (int)$old['size'] || $offset + strlen($data) < (int)$old['size'] && strlen($data) !== NativeCryptoStorage::CHUNK) {
                throw new NativeError('validation_error');
            }
            if ($offset < (int)$old['received']) {
                $chunk = $this->one('SELECT data FROM familyhub_crypto_blob_chunks_v2 WHERE scope_id=? AND blob_id=? AND chunk_offset=?', [$sid, $id, $offset]);
                if (!$chunk || !hash_equals($chunk['data'], $p['dataBase64'])) {
                    throw new NativeError('crypto_blob_chunk_conflict', 409);
                }
                return ['id' => $id, 'offset' => (int)$old['received'], 'complete' => (bool)$old['complete']];
            }
            if ($offset !== (int)$old['received'] || (int)$old['complete']) {
                throw new NativeError('crypto_blob_offset', 409, ['offset' => (int)$old['received']]);
            }
            $this->change('INSERT INTO familyhub_crypto_blob_chunks_v2 VALUES(?,?,?,?)', [$sid, $id, $offset, $p['dataBase64']]);
            $this->change('UPDATE familyhub_crypto_blobs_v2 SET received=received+? WHERE scope_id=? AND id=?', [strlen($data), $sid, $id]);
            return ['id' => $id, 'offset' => $offset + strlen($data), 'complete' => false];
        }
        if ((int)$old['received'] !== (int)$old['size']) {
            throw new NativeError('crypto_blob_incomplete', 409);
        }
        $hash = hash_init('sha256');
        $offset = 0;
        foreach ($this->iterate('SELECT chunk_offset,data FROM familyhub_crypto_blob_chunks_v2 WHERE scope_id=? AND blob_id=? ORDER BY chunk_offset', [$sid, $id]) as $chunk) {
            if ((int)$chunk['chunk_offset'] !== $offset) {
                throw new NativeError('crypto_blob_incomplete', 409);
            }
            $data = NativeCryptoCodec::base64($chunk['data'], NativeCryptoStorage::CHUNK);
            hash_update($hash, $data);
            $offset += strlen($data);
        }
        if ($offset !== (int)$old['size'] || !hash_equals($old['sha256'], hash_final($hash))) {
            throw new NativeError('crypto_blob_integrity', 422);
        }
        $this->change('UPDATE familyhub_crypto_blobs_v2 SET complete=1 WHERE scope_id=? AND id=?', [$sid, $id]);
        return ['id' => $id, 'offset' => $offset, 'complete' => true];
    }

    private function assertBlobQuota($sid, $domain, $size, $actor)
    {
        $migration = new NativeCryptoMigrationV2($this->container, $this->bearer, $this->ip);
        $scopeAllowance = $migration->blobAllowance($sid, $domain, $actor);
        $accountAllowance = $migration->blobAccountAllowance($actor);
        $scopeBytes = $this->quotaSetting('FAMILYHUB_CRYPTO_MAX_SCOPE_BYTES', 536870912, self::MAX_BLOB);
        $scopeObjects = $this->quotaSetting('FAMILYHUB_CRYPTO_MAX_SCOPE_OBJECTS', 1000, 1);
        $accountBytes = $this->quotaSetting('FAMILYHUB_CRYPTO_MAX_ACCOUNT_BYTES', 2147483648, self::MAX_BLOB);
        $accountObjects = $this->quotaSetting('FAMILYHUB_CRYPTO_MAX_ACCOUNT_OBJECTS', 10000, 1);
        $scopeUsage = $this->one('SELECT COUNT(*) AS objects,COALESCE(SUM(size),0) AS bytes FROM familyhub_crypto_blobs_v2 WHERE scope_id=? AND domain=? AND complete>=0', [$sid, $domain]);
        $accountUsage = $this->one('SELECT COUNT(*) AS objects,COALESCE(SUM(size),0) AS bytes FROM familyhub_crypto_blobs_v2 WHERE owner_account_id=? AND complete>=0', [$actor['user']['account_id']]);
        foreach ([[$scopeUsage, $scopeAllowance, $scopeBytes, $scopeObjects], [$accountUsage, $accountAllowance, $accountBytes, $accountObjects]] as [$usage, $allowance, $bytes, $objects]) {
            if (!is_array($allowance) || !isset($allowance['bytes'], $allowance['objects']) || !is_int($allowance['bytes']) || !is_int($allowance['objects']) || $allowance['bytes'] < 0 || $allowance['objects'] < 0 || $allowance['bytes'] > 9007199254740991 - $bytes || $allowance['objects'] > 9007199254740991 - $objects) {
                throw new NativeError('crypto_storage_budget_unavailable', 503);
            }
            if ((int)$usage['objects'] >= $objects + $allowance['objects'] || (int)$usage['bytes'] > $bytes + $allowance['bytes'] - $size) {
                // Do not reveal another financial recipient's reserved byte/count totals.
                throw new NativeError('crypto_storage_quota', 409);
            }
        }
    }

    private function quotaSetting($name, $fallback, $minimum)
    {
        $value = defined($name) ? constant($name) : $fallback;
        if (!is_int($value) || $value < $minimum || $value > 9007199254740991) {
            throw new NativeError('crypto_storage_budget_unavailable', 503);
        }
        return $value;
    }

    private function blobRead($op, $p, $actor)
    {
        $this->fields($p, ['scopeId', 'id', 'domain', 'accessRevision'], ['offset','evidenceFor','evidenceRecord']);
        $this->blobAuthority($p, $actor, false);
        $id = $this->uuid($p['id']);
        $row = $this->one('SELECT * FROM familyhub_crypto_blobs_v2 WHERE scope_id=? AND id=? AND domain=? AND complete=1', [$p['scopeId'], $id, $p['domain']]);
        if (!$row) {
            throw new NativeError('crypto_blob_missing', 404);
        }
        $notice = (new NativeCryptoModerationAvailabilityV2($this->container,$this->bearer,$this->ip))->assertBlob($p['scopeId'],$id,$p['domain'],$p,$actor);
        $offset = $p['offset'] ?? 0;
        if (!is_int($offset) || $offset < 0 || $offset >= (int)$row['size'] || $offset % NativeCryptoStorage::CHUNK !== 0) {
            throw new NativeError('validation_error');
        }
        $chunk = $this->one('SELECT data FROM familyhub_crypto_blob_chunks_v2 WHERE scope_id=? AND blob_id=? AND chunk_offset=?', [$p['scopeId'], $id, $offset]);
        if (!$chunk) {
            throw new NativeError('crypto_blob_incomplete', 409);
        }
        return ['scopeId' => $p['scopeId'], 'id' => $id, 'domain' => $row['domain'], 'membershipHeadHash' => $row['head_hash'], 'offset' => $offset, 'dataBase64' => $chunk['data'], 'size' => (int)$row['size'], 'sha256' => $row['sha256'], 'epoch' => (int)$row['epoch'], 'manifestBase64' => $row['manifest'], 'authorization' => json_decode($row['authorization'], true, 34, JSON_THROW_ON_ERROR), 'done' => $offset + strlen(base64_decode($chunk['data'], true)) === (int)$row['size']] + ($notice ? ['verificationEvidence' => true,'unavailable' => [$notice]] : []);
    }
}
