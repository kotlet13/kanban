<?php

namespace Kanboard\Plugin\FamilyHub\Model;

/** Own immutable notification transforms. No scheduler mutation before cutover. */
class NativeCryptoMigrationNotificationStageV3 extends NativeDatabase
{
    protected $cryptoAccess = true;
    public const TABLES = [
        'familyhub_reminders', 'familyhub_inbox', 'familyhub_inbox_preferences',
        'familyhub_inbox_state', 'familyhub_deliveries', 'familyhub_push_jobs',
    ];

    private function transactionRequired()
    {
        if (!$this->transactionActive()) {
            throw new NativeError('crypto_migration_transaction_required', 409);
        }
    }

    private function digest($value)
    {
        if (!is_string($value) || !preg_match('/^[a-f0-9]{64}$/D', $value)) {
            throw new NativeError('crypto_notification_migration_context');
        }
        return $value;
    }

    private function integer($value, $minimum = 0)
    {
        if (!is_int($value) || $value < $minimum || $value > 9007199254740991) {
            throw new NativeError('crypto_notification_migration_count');
        }
        return $value;
    }

    private function same($a, $b)
    {
        return NativeCryptoCodec::canonical($a) === NativeCryptoCodec::canonical($b);
    }

    private function cells($typed)
    {
        if (!is_object($typed)) {
            throw new NativeError('crypto_notification_migration_source');
        }
        $out = [];
        foreach (get_object_vars($typed) as $name => $cell) {
            if (!is_array($cell) || !array_key_exists('valueBase64', $cell)) {
                throw new NativeError('crypto_notification_migration_source');
            }
            if ($cell['valueBase64'] === null) {
                $out[$name] = null;
            } else {
                $bytes = base64_decode($cell['valueBase64'], true);
                if ($bytes === false || base64_encode($bytes) !== $cell['valueBase64']) {
                    throw new NativeError('crypto_notification_migration_source');
                }
                $out[$name] = $bytes;
            }
        }
        return $out;
    }

    private function context($p, $actor)
    {
        return ['version' => 3, 'serverId' => $this->serverId(),
            'accountId' => $actor['user']['account_id'],
            'migrationId' => $this->uuid($p['migrationId']),
            'captureId' => $this->uuid($p['captureId']),
            'sourceInventoryRoot' => $this->digest($p['sourceInventoryRoot'])];
    }

    private function signer($account, $reference, $deviceId, $actor, $anchoredHistory = false)
    {
        $anchoredHistory = $anchoredHistory || NativeCryptoMigrationGenerationV3::retainedReference($this->pdo,$account,$reference,$deviceId);
        if ($account !== $actor['user']['account_id']) {
            throw new NativeError('permission_revoked', 403);
        }
        $directory = new NativeCryptoDirectoryV2($this->container);
        $current = $directory->current($account);
        $prefix = $this->one('SELECT * FROM familyhub_crypto_directory WHERE account_id=? AND head_hash=?', [$account, $reference]);
        if (!$current || !$prefix || (int)$prefix['generation'] > (int)$current['generation'] ||
            !$anchoredHistory && ($prefix['device_snapshot_hash'] !== $current['device_snapshot_hash'] ||
            $prefix['identity_epoch_id'] !== $current['identity_epoch_id'])) {
            throw new NativeError('crypto_notification_migration_signer_changed', 409);
        }
        $snapshot = $anchoredHistory
            ? $this->prefixState($account,(int)$prefix['generation'])['snapshotValue']
            : json_decode($current['snapshot'], true, 34, JSON_THROW_ON_ERROR);
        $device = $directory->device($snapshot, $deviceId);
        if (!$device || $device['revokedGeneration'] !== null ||
            $device['identityEpochId'] !== $snapshot['identityEpochId']) {
            throw new NativeError('crypto_notification_migration_signer_revoked', 403);
        }
        return $device['signingKeyBase64'];
    }

    /** Immutable log entries deliberately contain no snapshot cache. Rebuild
     * only the exact accepted prefix; never trust a historical blank/cache row.
     */
    private function prefixState($account, $generation)
    {
        $directory = new NativeCryptoDirectoryV2($this->container);
        $before = null;
        $after = 0;
        while ($after < $generation) {
            $rows = $this->many('SELECT * FROM familyhub_crypto_directory WHERE account_id=? AND generation>? AND generation<=? ORDER BY generation LIMIT 20',[$account,$after,$generation]);
            if (!$rows) {
                throw new NativeError('crypto_notification_migration_event_missing',409);
            }
            foreach ($rows as $row) {
                $proof = json_decode($row['authorization'],true,34,JSON_THROW_ON_ERROR);
                [$command,$bytes,$signature] = NativeCryptoCodec::decode($proof);
                if ((int)$row['generation'] !== $after + 1 || $command['accountId'] !== $account ||
                    $command['serverId'] !== $this->serverId() ||
                    $command['payload']['previousHeadHash'] !== ($before['head_hash'] ?? NativeCryptoDirectoryV2::ZERO)) {
                    throw new NativeError('crypto_notification_migration_event_invalid',409);
                }
                NativeCryptoV2Codec::verify($bytes,$signature,$directory->authorize($command,$before));
                $snapshot = $directory->reduce($command,$before);
                if (NativeCryptoV2Codec::head($command,$proof,$after+1) !== $row['head_hash'] ||
                    NativeCryptoDirectoryV2::snapshotHash($snapshot) !== $row['snapshot_hash'] ||
                    NativeCryptoDirectoryV2::deviceHash($snapshot) !== $row['device_snapshot_hash']) {
                    throw new NativeError('crypto_notification_migration_event_invalid',409);
                }
                $before = array_replace($row,['snapshot'=>NativeCryptoCodec::canonical((object)$snapshot),
                    'snapshotValue'=>$snapshot]);
                $after++;
            }
        }
        return $before;
    }

    private function exactColumns($canonical, $source, $mapping)
    {
        foreach ($mapping as $name => $column) {
            $value = is_bool($canonical[$name]) ? ($canonical[$name] ? '1' : '0') :
                (is_int($canonical[$name]) ? (string)$canonical[$name] : $canonical[$name]);
            if (!array_key_exists($column, $source) ||
                $value !== $source[$column]) {
                throw new NativeError('crypto_notification_migration_source_changed', 409);
            }
        }
    }

    private function useAuthorization($body, $record, $actor)
    {
        $proof = $body['useAuthorization'];
        $canonical = $body['canonical'];
        if ($proof === null) {
            if ($body['kind'] === 'reminder' && $canonical['state'] === 'pending' &&
                $canonical['scheduleMode'] === 'deadline') {
                throw new NativeError('crypto_notification_migration_use_required', 409);
            }
            return null;
        }
        if ($body['kind'] !== 'reminder' || !$record ||
            $canonical['scheduleMode'] !== 'deadline' || $canonical['state'] === 'cancelled') {
            throw new NativeError('crypto_notification_migration_use_invalid', 409);
        }
        [$use, $bytes, $signature] = NativeCryptoCodec::decode($proof);
        $this->fields($use, ['version','operation','serverId','scopeId','targetId','targetType','domain',
            'useId','sourceScheduleRevision','schedulePutId','consentGeneration','scopeLifecycleHash',
            'projectBarrier','expiresAtEpoch','mode','membershipHeadHash','accessRevision','targetRevision',
            'targetRecordProofHash','accountId','deviceId','authorDirectoryHeadHash',
            'migrationId','captureId','sourceInventoryRoot','bindingId','originalState']);
        if (strlen($bytes) > 16384 || $use['version'] !== 3 ||
            $use['operation'] !== 'crypto2.migration.schedulingUse' || $use['mode'] !== 'relative') {
            throw new NativeError('crypto_notification_migration_use_invalid');
        }
        foreach (['serverId','accountId','deviceId','authorDirectoryHeadHash','migrationId',
            'captureId','sourceInventoryRoot','bindingId'] as $field) {
            if ($use[$field] !== $body[$field]) {
                throw new NativeError('crypto_notification_migration_use_context',409);
            }
        }
        foreach (['scopeId','targetId','targetType','domain','consentGeneration','scopeLifecycleHash',
            'targetRevision','targetRecordProofHash'] as $field) {
            if ($use[$field] !== $canonical[$field]) {
                throw new NativeError('crypto_notification_migration_use_target',409);
            }
        }
        if ($use['originalState'] !== $canonical['state'] ||
            $use['schedulePutId'] !== $canonical['id'] ||
            $use['sourceScheduleRevision'] !== $canonical['scheduleRevision'] ||
            $use['membershipHeadHash'] !== $record['membershipHeadHash'] ||
            $use['accessRevision'] !== $record['accessRevision'] ||
            !$this->same($use['projectBarrier'] === null ? null : (object)$use['projectBarrier'],
                $canonical['projectBarrier'] === null ? null : (object)$canonical['projectBarrier']) ||
            $use['expiresAtEpoch'] !== null && (!is_int($use['expiresAtEpoch']) ||
                $use['expiresAtEpoch'] < 0 || $use['expiresAtEpoch'] > 253402300799 ||
                $canonical['state'] === 'pending' && $use['expiresAtEpoch'] <= time())) {
            throw new NativeError('crypto_notification_migration_use_target',409);
        }
        $this->uuid($use['useId']);
        NativeCryptoV2Codec::verify($bytes,$signature,
            $this->signer($body['accountId'],$body['authorDirectoryHeadHash'],$body['deviceId'],$actor),
            "JivieE2EE/migrationSchedulingUse/v3\n");
        return NativeCryptoV2Codec::hash((object)$proof);
    }

    private function targetAddress($canonical)
    {
        $type = $canonical['targetType'];
        $domain = NativeCryptoRecordAddressV2::domain($type);
        $id = NativeCryptoRecordAddressV2::derive($this->serverId(), $canonical['scopeId'],
            $domain, NativeCryptoRecordAddressV2::sourceKind($type), $canonical['canonicalTargetId']);
        if ($canonical['targetId'] !== $id) {
            throw new NativeError('crypto_notification_migration_target', 409);
        }
        return $domain;
    }

    private function reminder($canonical, $source, $context, $actor, callable $target)
    {
        $this->fields($canonical, ['id','scopeId','targetType','canonicalTargetId','targetId','domain',
            'targetRevision','targetRecordProofHash','scheduleRevision','consentGeneration',
            'scopeLifecycleHash','projectBarrier','remindAt','remindEpoch','revision','state',
            'scheduleMode','offsetMinutes']);
        $this->uuid($canonical['id']);
        $this->uuid($canonical['scopeId']);
        $this->uuid($canonical['scheduleRevision']);
        foreach (['remindEpoch','revision','targetRevision'] as $field) {
            $this->integer($canonical[$field], $field === 'revision' ? 1 : 0);
        }
        if ($source['account_id'] !== $actor['user']['account_id'] ||
            !in_array($canonical['targetType'], ['task','event','financeEntry','personalFinanceEntry'], true) ||
            !in_array($canonical['state'], ['pending','cancelled','delivered'], true) ||
            !in_array($canonical['scheduleMode'], ['absolute','deadline'], true) ||
            $this->targetAddress($canonical) !== $canonical['domain']) {
            throw new NativeError('crypto_notification_migration_reminder');
        }
        $this->exactColumns($canonical, $source, ['id'=>'id','scopeId'=>'scope_id',
            'targetType'=>'target_type','canonicalTargetId'=>'target_id','remindAt'=>'remind_at',
            'remindEpoch'=>'remind_epoch','revision'=>'revision','state'=>'state',
            'scheduleMode'=>'schedule_mode','offsetMinutes'=>'offset_minutes']);
        if ($canonical['targetRecordProofHash'] === null) {
            if ($canonical['state'] === 'pending' || $canonical['targetRevision'] !== 0 ||
                $canonical['consentGeneration'] !== null || $canonical['scopeLifecycleHash'] !== null ||
                $canonical['projectBarrier'] !== null) {
                throw new NativeError('crypto_notification_migration_target', 409);
            }
            return null;
        }
        $proofHash = $this->digest($canonical['targetRecordProofHash']);
        $staged = $target($context['migrationId'], $canonical['scopeId'], $canonical['targetId'], $proofHash, $actor);
        $record = $staged['record'];
        $metadata = $record['metadata'];
        $state = $metadata['reminderState'] ?? null;
        if ($record['type'] !== $canonical['targetType'] || $record['domain'] !== $canonical['domain'] ||
            $record['expectedRevision'] + 1 !== $canonical['targetRevision'] || !$state ||
            $state['scheduleRevision'] !== $canonical['scheduleRevision'] ||
            ($state['consentGeneration'] ?? null) !== $canonical['consentGeneration']) {
            throw new NativeError('crypto_notification_migration_target', 409);
        }
        $this->uuid($canonical['consentGeneration']);
        $this->digest($canonical['scopeLifecycleHash']);
        if ($canonical['state'] === 'pending') {
            if ($record['deleted'] || $state['closed']) {
                throw new NativeError('crypto_notification_migration_target_closed', 409);
            }
            (new NativeReminderService($this->container))->assertMigrationTargetConsent($source);
        }
        if ($canonical['state'] === 'pending' || $context['useAuthorization'] !== null) {
            if ((new NativeCryptoLifecycleV2($this->container))->closingHash($canonical['scopeId']) !== $canonical['scopeLifecycleHash']) {
                throw new NativeError('crypto_notification_migration_lifecycle_changed',409);
            }
            $project = null;
            $pending = $metadata['referenceVersions'] ?? [];
            $seen = [];
            while ($pending) {
                $ref = array_shift($pending);
                if ($ref['scopeId'] !== $canonical['scopeId'] || isset($seen[$ref['id']])) {
                    continue;
                }
                $seen[$ref['id']] = true;
                if (count($seen) > 100) {
                    throw new NativeError('crypto_reference_graph_limit',409);
                }
                $next = $target($context['migrationId'],$canonical['scopeId'],$ref['id'],$ref['recordProofHash'],$actor)['record'];
                if ($next['domain'] !== $ref['domain'] || $next['expectedRevision'] + 1 !== $ref['revision']) {
                    throw new NativeError('crypto_notification_migration_target',409);
                }
                if ($next['type'] === 'project') {
                    $projectState = $next['metadata']['projectState'] ?? null;
                    if ($project !== null || $next['deleted'] || !$projectState || $projectState['archived']) {
                        throw new NativeError('crypto_notification_migration_project_closed',409);
                    }
                    $this->uuid($projectState['consentGeneration'] ?? null);
                    $project = ['id'=>$ref['id'],'consentGeneration'=>$projectState['consentGeneration']];
                }
                foreach ($next['metadata']['referenceVersions'] ?? [] as $edge) {
                    $pending[] = $edge;
                }
            }
            if (!$this->same($project === null ? null : (object)$project,
                $canonical['projectBarrier'] === null ? null : (object)$canonical['projectBarrier'])) {
                throw new NativeError('crypto_notification_migration_project_changed',409);
            }
        }
        return $record;
    }

    private function validateCanonical($body, $entry, $actor, callable $target)
    {
        $source = $this->cells($entry['typedRow']);
        $table = $entry['context']['sourceTable'];
        $canonical = $body['canonical'];
        if ($body['kind'] === 'reminder' && $table === 'familyhub_reminders') {
            return $this->reminder($canonical, $source, $body, $actor, $target);
        }
        if ($body['kind'] === 'preference' && $table === 'familyhub_inbox_preferences') {
            $this->fields($canonical, ['scopeId','category','settings']);
            $this->exactColumns($canonical, $source, ['scopeId'=>'scope_id','category'=>'category']);
            if ($source['account_id'] !== $actor['user']['account_id'] ||
                !in_array($canonical['category'], NativeNotificationPreferences::CATEGORIES, true) ||
                !$this->same((object)$canonical['settings'], (object)NativeNotificationPreferences::resolve($source['settings']))) {
                throw new NativeError('crypto_notification_migration_preference', 409);
            }
            $this->fields($canonical['settings'], ['inApp','sound','push','email']);
            foreach ($canonical['settings'] as $value) {
                if (!is_bool($value)) {
                    throw new NativeError('crypto_notification_migration_preference');
                }
            }
            return null;
        }
        if ($body['kind'] === 'inboxState' && $table === 'familyhub_inbox_state') {
            $this->fields($canonical, ['sequence','visibilityRevision']);
            $this->integer($canonical['sequence']);
            $this->integer($canonical['visibilityRevision']);
            $this->exactColumns($canonical, $source, ['sequence'=>'sequence','visibilityRevision'=>'visibility_revision']);
            if ($source['account_id'] !== $actor['user']['account_id']) {
                throw new NativeError('permission_revoked', 403);
            }
            return null;
        }
        if ($body['kind'] !== 'inbox') {
            throw new NativeError('crypto_notification_migration_kind');
        }
        if ($table === 'familyhub_inbox') {
            $this->fields($canonical, ['rowKind','id','eventKey','scopeId','category','kind','audience',
                'actorAccountId','targetType','canonicalTargetId','targetId','targetRevision','groupKey',
                'createdAt','readAt','revision','sequence','inApp']);
            $this->exactColumns($canonical, $source, ['id'=>'id','eventKey'=>'event_key','scopeId'=>'scope_id',
                'category'=>'category','audience'=>'audience','actorAccountId'=>'actor_account_id',
                'targetType'=>'target_type','canonicalTargetId'=>'target_id','targetRevision'=>'target_revision',
                'groupKey'=>'group_key','createdAt'=>'created_at','readAt'=>'read_at','revision'=>'revision',
                'sequence'=>'sequence','inApp'=>'in_app']);
            if ($source['recipient_account_id'] !== $actor['user']['account_id'] ||
                $canonical['rowKind'] !== 'inbox' || $canonical['kind'] !== 'crypto2.'.$source['kind']) {
                throw new NativeError('crypto_notification_migration_inbox', 409);
            }
            foreach (['id','targetRevision','revision','sequence'] as $field) {
                $this->integer($canonical[$field]);
            }
            if ($canonical['targetType'] === 'membership') {
                if ($canonical['targetId'] !== $canonical['canonicalTargetId']) {
                    throw new NativeError('crypto_notification_migration_inbox');
                }
                $this->uuid($canonical['targetId']);
            } else {
                $this->targetAddress($canonical);
            }
            return null;
        }
        $push = $table === 'familyhub_push_jobs';
        if (!$push && $table !== 'familyhub_deliveries') {
            throw new NativeError('crypto_notification_migration_kind');
        }
        $columns = ['inboxId'=>'inbox_id','state'=>'state','attempts'=>'attempts',
            'nextAttempt'=>'next_attempt','expiresAt'=>'expires_at','leaseToken'=>'lease_token',
            'leaseUntil'=>'lease_until','sentAt'=>'sent_at'];
        if ($push) {
            $columns += ['deviceId'=>'device_id','registrationRevision'=>'registration_revision','tokenHash'=>'token_hash'];
        }
        $this->fields($canonical, array_merge(['rowKind'], array_keys($columns)));
        $this->exactColumns($canonical, $source, $columns);
        if ($canonical['rowKind'] !== ($push ? 'push' : 'delivery')) {
            throw new NativeError('crypto_notification_migration_job');
        }
        $inbox = $this->one('SELECT recipient_account_id FROM familyhub_inbox WHERE id=?', [$source['inbox_id']]);
        if (!$inbox || $inbox['recipient_account_id'] !== $actor['user']['account_id']) {
            throw new NativeError('permission_revoked', 403);
        }
        return null;
    }

    /** Caller holds the exclusive maintenance lease and global migration SQL lock. */
    public function stage($p, $actor, $proof, $command,
        callable $captureSourceBinding, callable $stagedCaptureTarget)
    {
        $this->transactionRequired();
        $this->fields($p, ['migrationId','captureId','sourceInventoryRoot','transforms']);
        $context = $this->context($p, $actor);
        $capture = $this->one('SELECT capture_id,inventory_root,state FROM familyhub_crypto_captures_v3 WHERE migration_id=? AND account_id=?', [$context['migrationId'],$context['accountId']]);
        if (!$capture || $capture['capture_id'] !== $context['captureId'] ||
            $capture['inventory_root'] !== $context['sourceInventoryRoot'] || $capture['state'] !== 'sealed') {
            throw new NativeError('crypto_capture_generation_conflict',409);
        }
        if (($command['operation'] ?? null) !== 'crypto2.migration.notifications.stage' ||
            ($command['accountId'] ?? null) !== $context['accountId'] ||
            !$this->same((object)$command['payload'], (object)$p) ||
            !is_array($p['transforms']) || !array_is_list($p['transforms']) ||
            !$p['transforms'] || count($p['transforms']) > 20 ||
            strlen(NativeCryptoCodec::canonical((object)$p)) > 524288) {
            throw new NativeError('crypto_notification_migration_stage');
        }
        if ($this->one('SELECT migration_id FROM familyhub_crypto_notification_certificates_v3 WHERE migration_id=? AND account_id=?', [$context['migrationId'],$context['accountId']])) {
            throw new NativeError('crypto_notification_migration_certified', 409);
        }
        $leaves = [];
        $seen = [];
        foreach ($p['transforms'] as $item) {
            $this->fields($item, ['authorization','previousTransformHash']);
            [$body] = NativeCryptoCodec::decode($item['authorization']);
            $bindingId = $this->uuid($body['bindingId'] ?? null);
            if (isset($seen[$bindingId])) {
                throw new NativeError('crypto_notification_migration_duplicate');
            }
            $seen[$bindingId] = true;
            $kind = $body['kind'] ?? null;
            $hash = NativeCryptoMigrationNotificationV3::transformHash($item['authorization'], $context,
                $bindingId, $kind, fn ($account, $reference, $device) => $this->signer($account,$reference,$device,$actor));
            $source = $captureSourceBinding($context['migrationId'],$context['captureId'],$bindingId,$actor);
            foreach (['serverId','accountId','migrationId','captureId'] as $field) {
                if (($source['context'][$field] ?? null) !== $context[$field]) {
                    throw new NativeError('crypto_notification_migration_source', 409);
                }
            }
            $record = $this->validateCanonical($body,$source,$actor,$stagedCaptureTarget);
            $useHash = $this->useAuthorization($body,$record,$actor);
            $leaf = ['bindingId'=>$bindingId,'kind'=>$kind,'transformHash'=>$hash,'useProofHash'=>$useHash];
            $leafHash = NativeCryptoMigrationNotificationV3::leafDigest($leaf);
            $old = $this->one('SELECT transform_hash FROM familyhub_crypto_notification_selections_v3 WHERE migration_id=? AND account_id=? AND binding_id=?', [$context['migrationId'],$context['accountId'],$bindingId]);
            if ($old && $old['transform_hash'] === $hash) {
                $leaves[] = $leaf;
                continue;
            }
            if (($old['transform_hash'] ?? null) !== $item['previousTransformHash']) {
                throw new NativeError('crypto_notification_migration_conflict',409);
            }
            $this->change('INSERT INTO familyhub_crypto_notification_transforms_v3 VALUES(?,?,?,?,?,?,?,?,?,?)', [
                $context['migrationId'],$context['accountId'],$bindingId,$hash,$kind,$leafHash,
                $useHash,json_encode($item['authorization'],JSON_THROW_ON_ERROR),json_encode($proof,JSON_THROW_ON_ERROR),time()]);
            if ($old) {
                $this->change('UPDATE familyhub_crypto_notification_selections_v3 SET transform_hash=? WHERE migration_id=? AND account_id=? AND binding_id=?', [$hash,$context['migrationId'],$context['accountId'],$bindingId]);
            } else {
                $this->change('INSERT INTO familyhub_crypto_notification_selections_v3 VALUES(?,?,?,?)', [$context['migrationId'],$context['accountId'],$bindingId,$hash]);
            }
            $leaves[] = $leaf;
        }
        return ['migrationId'=>$context['migrationId'],'captureId'=>$context['captureId'],
            'sourceInventoryRoot'=>$context['sourceInventoryRoot'],'leaves'=>$leaves,'state'=>'staged'];
    }

    private function leafRows($migrationId, $account)
    {
        $after = '';
        do {
            $rows = $this->many('SELECT t.* FROM familyhub_crypto_notification_selections_v3 s JOIN familyhub_crypto_notification_transforms_v3 t ON t.migration_id=s.migration_id AND t.account_id=s.account_id AND t.binding_id=s.binding_id AND t.transform_hash=s.transform_hash WHERE s.migration_id=? AND s.account_id=? AND t.leaf_hash>? ORDER BY t.leaf_hash LIMIT 20', [$migrationId,$account,$after]);
            foreach ($rows as $row) {
                $after = $row['leaf_hash'];
                yield $row;
            }
        } while (count($rows) === 20);
    }

    private function selectedRows($migrationId, $account)
    {
        $after = '';
        do {
            $rows = $this->many('SELECT t.* FROM familyhub_crypto_notification_selections_v3 s JOIN familyhub_crypto_notification_transforms_v3 t ON t.migration_id=s.migration_id AND t.account_id=s.account_id AND t.binding_id=s.binding_id AND t.transform_hash=s.transform_hash WHERE s.migration_id=? AND s.account_id=? AND s.binding_id>? ORDER BY s.binding_id LIMIT 20',[$migrationId,$account,$after]);
            foreach ($rows as $row) {
                $after = $row['binding_id'];
                yield $row;
            }
        } while (count($rows) === 20);
    }

    /** Own private cold-comparison candidates. These bytes confer no authority
     * until the reader independently verifies its complete captured source.
     */
    public function transforms($p, $actor, callable $captureSourceBindings)
    {
        $this->fields($p,['migrationId','captureId','sourceInventoryRoot'],['afterBindingId','limit']);
        $context = $this->context($p,$actor);
        $after = isset($p['afterBindingId']) ? $this->uuid($p['afterBindingId']) : '';
        $limit = $p['limit'] ?? 20;
        if (!is_int($limit) || $limit < 1 || $limit > 20) {
            throw new NativeError('validation_error');
        }
        foreach ($captureSourceBindings($context['migrationId'],$context['captureId'],
            $context['sourceInventoryRoot'],$actor,self::TABLES) as $unused) {
            break;
        }
        $rows = $this->many('SELECT t.binding_id,t.authorization FROM familyhub_crypto_notification_selections_v3 s JOIN familyhub_crypto_notification_transforms_v3 t ON t.migration_id=s.migration_id AND t.account_id=s.account_id AND t.binding_id=s.binding_id AND t.transform_hash=s.transform_hash WHERE s.migration_id=? AND s.account_id=? AND s.binding_id>? ORDER BY s.binding_id LIMIT '.($limit+1),[$context['migrationId'],$context['accountId'],$after]);
        $more = count($rows) > $limit;
        $rows = array_slice($rows,0,$limit);
        $out = array_map(fn($row)=>['bindingId'=>$row['binding_id'],
            'authorization'=>json_decode($row['authorization'],true,34,JSON_THROW_ON_ERROR)],$rows);
        if (strlen(json_encode($out,JSON_THROW_ON_ERROR)) > 1250000) {
            throw new NativeError('crypto_notification_migration_page_limit',409);
        }
        return ['transforms'=>$out,'hasMore'=>$more,
            'nextAfterBindingId'=>$rows ? end($rows)['binding_id'] : ($after ?: null)];
    }

    /** ONLY the final globally locked component SQL transaction calls this.
     * Validate every immutable source/target before the first effect. The
     * second bounded pass never reinterprets a source after mutation begins.
     */
    public function install(array $expected, $actor, callable $captureSourceBindings,
        callable $captureSourceBinding, callable $stagedCaptureTarget)
    {
        $apply = $this->prepareInstall($expected,$actor,$captureSourceBindings,
            $captureSourceBinding,$stagedCaptureTarget);
        return $apply();
    }

    /** Final component coordinator prepares ALL portions before invoking any
     * returned one-shot closure, in the SAME outer SQL transaction/lock. */
    public function prepareInstall(array $expected, $actor, callable $captureSourceBindings,
        callable $captureSourceBinding, callable $stagedCaptureTarget)
    {
        $this->transactionRequired();
        if (($expected['state'] ?? null) !== 'anchored') {
            throw new NativeError('crypto_notification_migration_anchor_pending',409);
        }
        $coverage = $this->coverage($expected['migrationId'],$expected['captureId'],
            $expected['sourceInventoryRoot'],$actor,$captureSourceBindings);
        foreach (['certificateHash','selectionRoot','transformRoot','transformCount','eventHeadHash','eventCommandHash'] as $field) {
            if (($expected[$field] ?? null) !== $coverage[$field]) {
                throw new NativeError('crypto_notification_migration_selection_changed',409);
            }
        }
        if (!$this->same((object)$expected['sourceCounts'],(object)$coverage['sourceCounts'])) {
            throw new NativeError('crypto_notification_migration_selection_changed',409);
        }
        // Fresh cutover authority is separate from historical anchored reads.
        // A revoked original contributor cannot issue/install a new baseline.
        foreach ($this->selectedRows($coverage['migrationId'],$coverage['accountId']) as $row) {
            $proof = json_decode($row['authorization'],true,34,JSON_THROW_ON_ERROR);
            [$body] = NativeCryptoCodec::decode($proof);
            NativeCryptoMigrationNotificationV3::transformHash($proof,
                array_intersect_key($coverage,array_flip(['version','serverId','migrationId','captureId','accountId','sourceInventoryRoot'])),
                $row['binding_id'],$row['kind'],
                fn($account,$reference,$device)=>$this->signer($account,$reference,$device,$actor));
            $source = $captureSourceBinding($coverage['migrationId'],$coverage['captureId'],$row['binding_id'],$actor);
            $record = $this->validateCanonical($body,$source,$actor,$stagedCaptureTarget);
            if ($this->useAuthorization($body,$record,$actor) !== $row['use_hash']) {
                throw new NativeError('crypto_notification_migration_storage',503);
            }
            if ($body['kind'] === 'reminder' &&
                $this->one('SELECT id FROM familyhub_crypto_reminders_v2 WHERE id=?',[$body['canonical']['id']])) {
                throw new NativeError('crypto_notification_migration_reminder_conflict',409);
            }
        }
        $used = false;
        return function () use ($coverage,&$used) {
            $this->transactionRequired();
            if ($used) {
                throw new NativeError('crypto_notification_migration_install_used',409);
            }
            $used = true;
            return $this->applyInstall($coverage);
        };
    }

    private function applyInstall(array $coverage)
    {
        foreach ($this->selectedRows($coverage['migrationId'],$coverage['accountId']) as $row) {
            $proof = json_decode($row['authorization'],true,34,JSON_THROW_ON_ERROR);
            [$body] = NativeCryptoCodec::decode($proof);
            $c = $body['canonical'];
            if ($body['kind'] === 'reminder') {
                $encoded = json_encode($proof,JSON_THROW_ON_ERROR);
                $this->change('INSERT INTO familyhub_crypto_reminders_v2(id,scope_id,account_id,target_type,target_id,domain,target_revision,schedule_revision,remind_at,remind_epoch,revision,state,schedule_mode,offset_minutes,authorization,put_authorization) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)',[
                    $c['id'],$c['scopeId'],$coverage['accountId'],$c['targetType'],$c['targetId'],$c['domain'],
                    $c['targetRevision'],$c['scheduleRevision'],$c['remindAt'],$c['remindEpoch'],$c['revision'],
                    $c['state'],$c['scheduleMode'],$c['offsetMinutes'],$encoded,$encoded]);
                // Retain the old exact source for retirement evidence, while
                // making the plaintext worker incapable of delivering it.
                (new NativeNotificationWriter($this->container))->configurationChanged($coverage['accountId']);
                $this->change("UPDATE familyhub_reminders SET state='migrated' WHERE id=? AND account_id=?",[$c['id'],$coverage['accountId']]);
                if ($body['useAuthorization'] !== null) {
                    (new NativeCryptoSchedulingUseV2($this->container,$this->bearer,$this->ip))->installMigrationBaseline(
                        $body['useAuthorization'],$row['use_hash'],$coverage);
                }
            } elseif ($body['kind'] === 'inbox' && $c['rowKind'] === 'inbox') {
                $identity = ['sourceKind'=>$c['targetType'] === 'membership' ? 'membership' :
                    NativeCryptoRecordAddressV2::sourceKind($c['targetType']),
                    'canonicalId'=>$c['canonicalTargetId']];
                $this->change('INSERT INTO familyhub_crypto_migration_inbox_v3 VALUES(?,?,?,?,?)',[
                    $coverage['accountId'],$c['id'],$coverage['migrationId'],$row['binding_id'],
                    json_encode($identity,JSON_THROW_ON_ERROR)]);
                $this->change('UPDATE familyhub_inbox SET kind=?,target_id=? WHERE id=? AND recipient_account_id=?',[
                    $c['kind'],$c['targetId'],$c['id'],$coverage['accountId']]);
            }
            // Preferences, global monotone counters, deliveries and push jobs
            // already occupy their canonical SQL tables. Preserve all bytes,
            // read/dedup/lease/attempt/sent state; never enqueue or re-lease.
        }
        $this->change("UPDATE familyhub_crypto_notification_certificates_v3 SET state='installed' WHERE migration_id=? AND account_id=? AND state='anchored'",[$coverage['migrationId'],$coverage['accountId']]);
        return ['certificateHash'=>$coverage['certificateHash'],'selectionRoot'=>$coverage['selectionRoot'],
            'transformRoot'=>$coverage['transformRoot'],'transformCount'=>$coverage['transformCount'],
            'sourceCounts'=>$coverage['sourceCounts'],'state'=>'installed'];
    }

    /** Exact complete frozen source selection, without claiming cert authority. */
    public function stagedCoverage($migrationId, $captureId, $sourceInventoryRoot, $actor,
        callable $captureSourceBindings, $anchoredHistory = false)
    {
        $this->transactionRequired();
        $context = $this->context(['migrationId'=>$migrationId,'captureId'=>$captureId,
            'sourceInventoryRoot'=>$sourceInventoryRoot],$actor);
        $counts = array_fill_keys(NativeCryptoMigrationNotificationV3::KINDS,0);
        $total = 0;
        $previous = null;
        foreach ($captureSourceBindings($migrationId,$captureId,$sourceInventoryRoot,$actor,self::TABLES) as $entry) {
            $binding = NativeCryptoCaptureV3::binding($entry['binding']);
            if ($previous !== null && strcmp($previous,$binding['bindingId']) >= 0) {
                throw new NativeError('crypto_notification_migration_order');
            }
            $previous = $binding['bindingId'];
            $table = $entry['context']['sourceTable'];
            $kind = match ($table) {
                'familyhub_reminders'=>'reminder',
                'familyhub_inbox_preferences'=>'preference',
                'familyhub_inbox_state'=>'inboxState',
                'familyhub_inbox','familyhub_deliveries','familyhub_push_jobs'=>'inbox',
                default=>throw new NativeError('crypto_notification_migration_kind'),
            };
            $selected = $this->one('SELECT t.* FROM familyhub_crypto_notification_selections_v3 s JOIN familyhub_crypto_notification_transforms_v3 t ON t.migration_id=s.migration_id AND t.account_id=s.account_id AND t.binding_id=s.binding_id AND t.transform_hash=s.transform_hash WHERE s.migration_id=? AND s.account_id=? AND s.binding_id=?', [$migrationId,$context['accountId'],$binding['bindingId']]);
            if (!$selected || $selected['kind'] !== $kind) {
                throw new NativeError('crypto_notification_migration_incomplete',409);
            }
            $proof = json_decode($selected['authorization'],true,34,JSON_THROW_ON_ERROR);
            $hash = NativeCryptoMigrationNotificationV3::transformHash($proof,$context,$binding['bindingId'],$kind,
                fn ($account,$reference,$device)=>$this->signer($account,$reference,$device,$actor,$anchoredHistory));
            [$transform] = NativeCryptoCodec::decode($proof);
            if (!$anchoredHistory && $transform['useAuthorization'] !== null) {
                [$use] = NativeCryptoCodec::decode($transform['useAuthorization']);
                if ($use['expiresAtEpoch'] !== null && $use['expiresAtEpoch'] <= time() &&
                    $transform['canonical']['state'] === 'pending') {
                    throw new NativeError('crypto_notification_migration_use_expired',409);
                }
            }
            $leaf = ['bindingId'=>$binding['bindingId'],'kind'=>$kind,'transformHash'=>$hash,
                'useProofHash'=>$selected['use_hash']];
            if ($selected['transform_hash'] !== $hash ||
                $selected['leaf_hash'] !== NativeCryptoMigrationNotificationV3::leafDigest($leaf)) {
                throw new NativeError('crypto_notification_migration_storage',503);
            }
            $counts[$kind]++;
            $total++;
        }
        $selectedCount = $this->one('SELECT COUNT(*) n FROM familyhub_crypto_notification_selections_v3 WHERE migration_id=? AND account_id=?', [$migrationId,$context['accountId']]);
        if ((int)$selectedCount['n'] !== $total) {
            throw new NativeError('crypto_notification_migration_extra_source',409);
        }
        $digests = (function () use ($migrationId,$context) {
            foreach ($this->leafRows($migrationId,$context['accountId']) as $row) {
                yield $row['leaf_hash'];
            }
        })();
        return $context + ['selectionRoot'=>NativeCryptoMigrationNotificationV3::selectionRoot($context,$total,$digests),
            'transformCount'=>$total,'sourceCounts'=>$counts,'state'=>'staged'];
    }

    /** The caller verifies the exact completed own archive and signed cold
     * comparison (which binds selectionRoot, never this certificate hash).
     */
    public function certify($p, $actor, $proof, $command,
        callable $captureSourceBindings, callable $verifyPrerequisites)
    {
        $this->transactionRequired();
        $this->fields($p,['header']);
        $header = NativeCryptoMigrationNotificationV3::header($p['header']);
        if ($header['serverId'] !== $this->serverId() || $header['accountId'] !== $actor['user']['account_id'] ||
            $command['operation'] !== 'crypto2.migration.notifications.certify' ||
            $command['accountId'] !== $header['accountId'] ||
            !$this->same((object)$command['payload'],(object)$p)) {
            throw new NativeError('crypto_notification_migration_certificate');
        }
        [$decoded,$bytes,$signature] = NativeCryptoCodec::decode($proof);
        if (!$this->same((object)$decoded,(object)$command)) {
            throw new NativeError('crypto_notification_migration_certificate');
        }
        NativeCryptoV2Codec::verify($bytes,$signature,
            $this->signer($header['accountId'],$header['authorDirectoryHeadHash'],$command['deviceId'],$actor));
        $selected = $this->stagedCoverage($header['migrationId'],$header['captureId'],
            $header['sourceInventoryRoot'],$actor,$captureSourceBindings);
        if ($selected['transformCount'] !== $header['transformCount'] ||
            !$this->same((object)$selected['sourceCounts'],(object)$header['sourceCounts']) ||
            $verifyPrerequisites($header,$selected,$actor) !== true) {
            throw new NativeError('crypto_notification_migration_cold_parity',409);
        }
        $digests = (function () use ($header) {
            foreach ($this->leafRows($header['migrationId'],$header['accountId']) as $row) {
                yield $row['leaf_hash'];
            }
        })();
        if (NativeCryptoMigrationNotificationV3::transformRoot($header,$digests) !== $header['transformRoot']) {
            throw new NativeError('crypto_notification_migration_incomplete',409);
        }
        $hash = NativeCryptoV2Codec::hash((object)$proof);
        $old = $this->certificate($header['migrationId'],$header['accountId']);
        if ($old) {
            if ($old['certificate_hash'] !== $hash) {
                throw new NativeError('crypto_notification_migration_certificate_immutable',409);
            }
        } else {
            $this->change('INSERT INTO familyhub_crypto_notification_certificates_v3 VALUES(?,?,?,?,?,?,?,?,?,?,NULL,NULL,NULL,?)', [
                $header['migrationId'],$header['accountId'],$header['captureId'],$header['sourceInventoryRoot'],
                $hash,$selected['selectionRoot'],$header['transformRoot'],$header['transformCount'],
                json_encode($header['sourceCounts'],JSON_THROW_ON_ERROR),json_encode($proof,JSON_THROW_ON_ERROR),'certified']);
        }
        return ['migrationId'=>$header['migrationId'],'captureId'=>$header['captureId'],
            'certificateHash'=>$hash,'selectionRoot'=>$selected['selectionRoot'],
            'transformRoot'=>$header['transformRoot'],'transformCount'=>$header['transformCount'],
            'scopeToken'=>NativeCryptoMigrationNotificationV3::scopeToken($header),'state'=>'certified'];
    }

    private function certificate($migrationId, $account)
    {
        return $this->one('SELECT * FROM familyhub_crypto_notification_certificates_v3 WHERE migration_id=? AND account_id=?',[$migrationId,$account]);
    }

    private function assertCertificateStream($header)
    {
        $digests = (function () use ($header) {
            foreach ($this->leafRows($header['migrationId'],$header['accountId']) as $row) {
                yield $row['leaf_hash'];
            }
        })();
        if (NativeCryptoMigrationNotificationV3::transformRoot($header,$digests) !== $header['transformRoot']) {
            throw new NativeError('crypto_notification_migration_selection_changed',409);
        }
    }

    private function certificateHeader($row)
    {
        $proof = json_decode($row['authorization'],true,34,JSON_THROW_ON_ERROR);
        [$command,$bytes,$signature] = NativeCryptoCodec::decode($proof);
        $this->fields($command,['version','operation','requestId','serverId','accountId','deviceId','signer','payload']);
        $this->fields($command['payload'],['header']);
        $header = NativeCryptoMigrationNotificationV3::header($command['payload']['header']);
        if (NativeCryptoV2Codec::hash((object)$proof) !== $row['certificate_hash'] ||
            $command['version'] !== 2 || $command['operation'] !== 'crypto2.migration.notifications.certify' ||
            $command['signer'] !== 'device' || $command['serverId'] !== $this->serverId() ||
            $command['accountId'] !== $row['account_id'] || $header['accountId'] !== $row['account_id'] ||
            $header['serverId'] !== $this->serverId() || $header['migrationId'] !== $row['migration_id'] ||
            $header['captureId'] !== $row['capture_id'] || $header['sourceInventoryRoot'] !== $row['source_inventory_root'] ||
            $header['transformRoot'] !== $row['transform_root'] ||
            $header['transformCount'] !== (int)$row['transform_count'] ||
            !$this->same((object)$header['sourceCounts'],(object)json_decode($row['source_counts'],true,34,JSON_THROW_ON_ERROR))) {
            throw new NativeError('crypto_notification_migration_storage',503);
        }
        $this->uuid($command['requestId']);
        $this->uuid($command['deviceId']);
        return [$command,$header,$proof,$bytes,$signature];
    }

    private function includedEvent($row)
    {
        $entry = $this->one('SELECT * FROM familyhub_crypto_directory WHERE account_id=? AND head_hash=? AND command_hash=?',
            [$row['account_id'],$row['event_head_hash'],$row['event_command_hash']]);
        $current = (new NativeCryptoDirectoryV2($this->container))->current($row['account_id']);
        if (!$entry || !$current || (int)$entry['generation'] > (int)$current['generation']) {
            throw new NativeError('crypto_notification_migration_event_missing',409);
        }
        $proof = json_decode($entry['authorization'],true,34,JSON_THROW_ON_ERROR);
        [$command,$bytes,$signature] = NativeCryptoCodec::decode($proof);
        $before = (int)$entry['generation'] === 1 ? null :
            $this->prefixState($row['account_id'],(int)$entry['generation']-1);
        $directory = new NativeCryptoDirectoryV2($this->container);
        NativeCryptoV2Codec::verify($bytes,$signature,$directory->authorize($command,$before));
        [, $header] = $this->certificateHeader($row);
        if ($command['operation'] !== 'crypto2.account.migrationAttest' ||
            $command['serverId'] !== $this->serverId() || $command['accountId'] !== $row['account_id'] ||
            $command['payload']['migrationId'] !== $row['migration_id'] ||
            $command['payload']['domain'] !== 'content' ||
            $command['payload']['scopeToken'] !== NativeCryptoMigrationNotificationV3::scopeToken($header) ||
            $command['payload']['attestationHash'] !== $row['certificate_hash']) {
            throw new NativeError('crypto_notification_migration_event_invalid',409);
        }
        return $proof;
    }

    public function anchor($p, $actor)
    {
        $this->transactionRequired();
        $this->fields($p,['migrationId','captureId','sourceInventoryRoot','certificateHash','eventHeadHash','eventCommandHash']);
        $context = $this->context($p,$actor);
        foreach (['certificateHash','eventHeadHash','eventCommandHash'] as $field) {
            $this->digest($p[$field]);
        }
        $row = $this->certificate($context['migrationId'],$context['accountId']);
        if (!$row || $row['capture_id'] !== $context['captureId'] ||
            $row['source_inventory_root'] !== $context['sourceInventoryRoot'] ||
            $row['certificate_hash'] !== $p['certificateHash']) {
            throw new NativeError('crypto_notification_migration_certificate_missing',409);
        }
        if ($row['state'] === 'anchored' &&
            ($row['event_head_hash'] !== $p['eventHeadHash'] || $row['event_command_hash'] !== $p['eventCommandHash'])) {
            throw new NativeError('crypto_notification_migration_event_immutable',409);
        }
        $row['event_head_hash'] = $p['eventHeadHash'];
        $row['event_command_hash'] = $p['eventCommandHash'];
        $eventProof = $this->includedEvent($row);
        [$certificate,$header,,$certificateBytes,$certificateSignature] = $this->certificateHeader($row);
        NativeCryptoV2Codec::verify($certificateBytes,$certificateSignature,
            $this->signer($row['account_id'],$header['authorDirectoryHeadHash'],$certificate['deviceId'],$actor,true));
        $this->change("UPDATE familyhub_crypto_notification_certificates_v3 SET event_head_hash=?,event_command_hash=?,event_authorization=?,state='anchored' WHERE migration_id=? AND account_id=?",[
            $row['event_head_hash'],$row['event_command_hash'],json_encode($eventProof,JSON_THROW_ON_ERROR),$row['migration_id'],$row['account_id']]);
        return ['migrationId'=>$row['migration_id'],'certificateHash'=>$row['certificate_hash'],'state'=>'anchored'];
    }

    public function coverage($migrationId, $captureId, $sourceInventoryRoot, $actor,
        callable $captureSourceBindings)
    {
        $this->transactionRequired();
        $row = $this->certificate($this->uuid($migrationId),$actor['user']['account_id']);
        if (!$row || $row['capture_id'] !== $captureId || $row['source_inventory_root'] !== $sourceInventoryRoot ||
            $row['state'] !== 'anchored') {
            throw new NativeError('crypto_notification_migration_anchor_pending',409);
        }
        $event = $this->includedEvent($row);
        [$command,$header,$proof,$bytes,$signature] = $this->certificateHeader($row);
        NativeCryptoV2Codec::verify($bytes,$signature,
            $this->signer($row['account_id'],$header['authorDirectoryHeadHash'],$command['deviceId'],$actor,true));
        $this->assertCertificateStream($header);
        // Historical transforms are admitted only after the exact certificate
        // has been found in the verified own account log, never fresh issuance.
        $selected = $this->stagedCoverage($migrationId,$captureId,$sourceInventoryRoot,$actor,$captureSourceBindings,true);
        if ($selected['selectionRoot'] !== $row['selection_root'] ||
            $selected['transformCount'] !== (int)$row['transform_count'] ||
            !$this->same((object)$selected['sourceCounts'],(object)json_decode($row['source_counts'],true,34,JSON_THROW_ON_ERROR))) {
            throw new NativeError('crypto_notification_migration_selection_changed',409);
        }
        return array_replace($selected, ['certificateHash'=>$row['certificate_hash'],'transformRoot'=>$row['transform_root'],
            'eventHeadHash'=>$row['event_head_hash'],'eventCommandHash'=>$row['event_command_hash'],
            'authorization'=>$proof,'eventAuthorization'=>$event,'state'=>'anchored']);
    }

    public function assertInstalledUse(array $body, $useHash)
    {
        $this->digest($useHash);
        $row = $this->certificate($body['migrationId'],$body['accountId']);
        $leaf = $this->one('SELECT t.* FROM familyhub_crypto_notification_selections_v3 s JOIN familyhub_crypto_notification_transforms_v3 t ON t.migration_id=s.migration_id AND t.account_id=s.account_id AND t.binding_id=s.binding_id AND t.transform_hash=s.transform_hash WHERE s.migration_id=? AND s.account_id=? AND s.binding_id=? AND t.use_hash=?',[
            $body['migrationId'],$body['accountId'],$body['bindingId'],$useHash]);
        if (!$row || $row['state'] !== 'installed' || !$leaf || $leaf['kind'] !== 'reminder' ||
            $row['capture_id'] !== $body['captureId'] || $row['source_inventory_root'] !== $body['sourceInventoryRoot']) {
            throw new NativeError('crypto_scheduling_migration_baseline_pending',409);
        }
        $proof = json_decode($leaf['authorization'],true,34,JSON_THROW_ON_ERROR);
        [$transform] = NativeCryptoCodec::decode($proof);
        if ($transform['useAuthorization'] === null ||
            NativeCryptoV2Codec::hash((object)$transform['useAuthorization']) !== $useHash ||
            $transform['canonical']['scopeId'] !== $body['scopeId'] ||
            $transform['canonical']['targetId'] !== $body['targetId']) {
            throw new NativeError('crypto_scheduling_migration_baseline_pending',409);
        }
        $this->includedEvent($row);
        [, $header] = $this->certificateHeader($row);
        $this->assertCertificateStream($header);
        $historyActor = ['user'=>['account_id'=>$body['accountId']]];
        $transformHash = NativeCryptoMigrationNotificationV3::transformHash($proof,$header,
            $body['bindingId'],'reminder',
            fn($account,$reference,$device)=>$this->signer($account,$reference,$device,$historyActor,true));
        if ($transformHash !== $leaf['transform_hash'] || $leaf['leaf_hash'] !==
            NativeCryptoMigrationNotificationV3::leafDigest(['bindingId'=>$body['bindingId'],
                'kind'=>'reminder','transformHash'=>$transformHash,'useProofHash'=>$useHash])) {
            throw new NativeError('crypto_notification_migration_storage',503);
        }
        return [$row,$leaf];
    }

    public function installedUseSigner(array $body, $useHash)
    {
        $this->assertInstalledUse($body,$useHash);
        return $this->signer($body['accountId'],$body['authorDirectoryHeadHash'],
            $body['deviceId'],['user'=>['account_id'=>$body['accountId']]],true);
    }

    public function installedRelocationUseSigner(array $body,$useHash,$scopeId,$targetId)
    {
        (new NativeCryptoProjectRelocationNotificationsV2($this->container,$this->bearer,$this->ip))
            ->installedUse($body,$useHash,$scopeId,$targetId);
        return $this->signer($body['accountId'],$body['authorDirectoryHeadHash'],
            $body['deviceId'],['user'=>['account_id'=>$body['accountId']]],true);
    }

    /** Own withdrawal needs no target READ. This reveals only this account's
     * prior certificate and exact reminder use; it cannot activate a schedule. */
    public function withdrawalEvidence($p,$actor)
    {
        $this->fields($p,['reminderId','useProofHash'],['afterDigest','limit']);
        $id=$this->uuid($p['reminderId']);$hash=$this->digest($p['useProofHash']);
        $after=isset($p['afterDigest'])?$this->digest($p['afterDigest']):'';
        $limit=$p['limit']??20;if(!is_int($limit)||$limit<1||$limit>20)throw new NativeError('validation_error');
        $row=$this->one('SELECT authorization FROM familyhub_crypto_scheduling_use_proofs_v2 WHERE account_id=? AND reminder_id=? AND proof_hash=?',[$actor['user']['account_id'],$id,$hash]);
        if(!$row)throw new NativeError('permission_revoked',403);
        $proof=json_decode($row['authorization'],true,34,JSON_THROW_ON_ERROR);
        [$body]=(new NativeCryptoSchedulingUseV2($this->container))->body($proof);
        if($body['version']!==3||$body['accountId']!==$actor['user']['account_id']||$body['schedulePutId']!==$id)throw new NativeError('permission_revoked',403);
        [$certificate,$leaf]=$this->assertInstalledUse($body,$hash);
        $rows=$this->many('SELECT t.leaf_hash FROM familyhub_crypto_notification_selections_v3 s JOIN familyhub_crypto_notification_transforms_v3 t ON t.migration_id=s.migration_id AND t.account_id=s.account_id AND t.binding_id=s.binding_id AND t.transform_hash=s.transform_hash WHERE t.migration_id=? AND t.account_id=? AND t.leaf_hash>? ORDER BY t.leaf_hash LIMIT '.($limit+1),[$body['migrationId'],$body['accountId'],$after]);
        $more=count($rows)>$limit;$rows=array_slice($rows,0,$limit);
        return ['authorization'=>$proof,'certificateAuthorization'=>json_decode($certificate['authorization'],true,34,JSON_THROW_ON_ERROR),
            'eventAuthorization'=>$this->includedEvent($certificate),'eventHeadHash'=>$certificate['event_head_hash'],'eventCommandHash'=>$certificate['event_command_hash'],
            'leaf'=>['bindingId'=>$leaf['binding_id'],'kind'=>'reminder','transformHash'=>$leaf['transform_hash'],'useProofHash'=>$hash],
            'digests'=>array_column($rows,'leaf_hash'),'hasMore'=>$more,'nextAfterDigest'=>$rows?end($rows)['leaf_hash']:($after?:null)];
    }

    /** Only exact target readers see this one use and opaque digest stream.
     * Private transforms, settings, other recipients and source rows stay out.
     */
    public function useEvidence($p, $actor)
    {
        $this->fields($p,['scopeId','targetId','useProofHash'],['afterDigest','limit']);
        $scope = $this->uuid($p['scopeId']);
        $id = NativeCryptoRecordAddressV2::wireId($p['targetId']);
        $hash = $this->digest($p['useProofHash']);
        $after = isset($p['afterDigest']) ? $this->digest($p['afterDigest']) : '';
        $limit = $p['limit'] ?? 20;
        if (!is_int($limit) || $limit < 1 || $limit > 20) {
            throw new NativeError('validation_error');
        }
        $stored = $this->one('SELECT authorization FROM familyhub_crypto_scheduling_use_proofs_v2 WHERE scope_id=? AND target_id=? AND proof_hash=?',[$scope,$id,$hash]);
        if (!$stored) {
            throw new NativeError('permission_revoked',403);
        }
        $proof = json_decode($stored['authorization'],true,34,JSON_THROW_ON_ERROR);
        [$body] = (new NativeCryptoSchedulingUseV2($this->container))->body($proof);
        if ($body['version'] !== 3 ||
            !(new NativeCryptoNotificationV2($this->container,$this->bearer,$this->ip))->recipientVisible($scope,$actor['user']['account_id'],$body['domain'])) {
            throw new NativeError('permission_revoked',403);
        }
        [$certificate,$selected] = $this->assertInstalledUse($body,$hash);
        $rows = $this->many('SELECT t.leaf_hash FROM familyhub_crypto_notification_selections_v3 s JOIN familyhub_crypto_notification_transforms_v3 t ON t.migration_id=s.migration_id AND t.account_id=s.account_id AND t.binding_id=s.binding_id AND t.transform_hash=s.transform_hash WHERE s.migration_id=? AND s.account_id=? AND t.leaf_hash>? ORDER BY t.leaf_hash LIMIT '.($limit+1),[$body['migrationId'],$body['accountId'],$after]);
        $more = count($rows) > $limit;
        $rows = array_slice($rows,0,$limit);
        return ['authorization'=>$proof,
            'certificateAuthorization'=>json_decode($certificate['authorization'],true,34,JSON_THROW_ON_ERROR),
            'eventAuthorization'=>$this->includedEvent($certificate),
            'eventHeadHash'=>$certificate['event_head_hash'],'eventCommandHash'=>$certificate['event_command_hash'],
            'leaf'=>['bindingId'=>$selected['binding_id'],'kind'=>'reminder',
                'transformHash'=>$selected['transform_hash'],'useProofHash'=>$hash],
            'digests'=>array_column($rows,'leaf_hash'),'hasMore'=>$more,
            'nextAfterDigest'=>$rows ? end($rows)['leaf_hash'] : ($after ?: null)];
    }

    /** Candidate frame only; caller first verifies the complete stagedCoverage. */
    public function bindingArtifact($migrationId, $captureId, $sourceInventoryRoot, $bindingId, $actor)
    {
        $this->transactionRequired();
        $context = $this->context(['migrationId'=>$migrationId,'captureId'=>$captureId,
            'sourceInventoryRoot'=>$sourceInventoryRoot],$actor);
        $this->uuid($bindingId);
        $row = $this->one('SELECT t.* FROM familyhub_crypto_notification_selections_v3 s JOIN familyhub_crypto_notification_transforms_v3 t ON t.migration_id=s.migration_id AND t.account_id=s.account_id AND t.binding_id=s.binding_id AND t.transform_hash=s.transform_hash WHERE s.migration_id=? AND s.account_id=? AND s.binding_id=?',[$migrationId,$context['accountId'],$bindingId]);
        if (!$row) {
            throw new NativeError('crypto_notification_migration_incomplete',409);
        }
        $proof = json_decode($row['authorization'],true,34,JSON_THROW_ON_ERROR);
        $hash = NativeCryptoMigrationNotificationV3::transformHash($proof,$context,$bindingId,$row['kind'],
            fn ($account,$reference,$device)=>$this->signer($account,$reference,$device,$actor));
        if ($hash !== $row['transform_hash']) {
            throw new NativeError('crypto_notification_migration_storage',503);
        }
        return $hash;
    }
}
