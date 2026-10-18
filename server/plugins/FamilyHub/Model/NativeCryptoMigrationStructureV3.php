<?php

namespace Kanboard\Plugin\FamilyHub\Model;

/** Internal final-cutover checks. Never a normal business-write authorization. */
class NativeCryptoMigrationStructureV3 extends NativeDatabase
{
    protected $cryptoAccess = true;
    public const TABLES = [
        'familyhub_scopes', 'familyhub_members', 'familyhub_organization_leaders',
        'familyhub_scope_revocations', 'familyhub_finance_policy',
        'familyhub_finance_grants', 'familyhub_personal_scopes',
        'familyhub_record_relocations',
    ];

    private function digest($value)
    {
        if (!is_string($value) || !preg_match('/^[a-f0-9]{64}$/D', $value)) {
            throw new NativeError('crypto_migration_structure_context');
        }
        return $value;
    }

    private static function canonicalId($value)
    {
        if (!is_string($value) || !preg_match('/^[a-f0-9]{8}-[a-f0-9]{4}-[1-5][a-f0-9]{3}-[89ab][a-f0-9]{3}-[a-f0-9]{12}$/D',$value)) {
            throw new NativeError('crypto_migration_structure_context');
        }
    }

    /** Context cards affect only the semantic structure commitment; they do
     * not invent source bindings or change the original blinded source root. */
    public static function structureHash(array $header, array $section, $contextProofHashes = null)
    {
        $fields = ['version','serverId','migrationId','captureId','sourceInventoryRoot','scopeId'];
        $keys = array_keys($header);
        sort($fields);
        sort($keys);
        if ($keys !== $fields || $header['version'] !== 3) {
            throw new NativeError('crypto_migration_structure_context');
        }
        foreach (['serverId','migrationId','captureId','scopeId'] as $field) { self::canonicalId($header[$field]); }
        if (!is_string($header['sourceInventoryRoot']) || !preg_match('/^[a-f0-9]{64}$/D',$header['sourceInventoryRoot'])) {
            throw new NativeError('crypto_migration_structure_context');
        }
        if ($contextProofHashes !== null) {
            if (!is_array($contextProofHashes) || !array_is_list($contextProofHashes) || !$contextProofHashes || count($contextProofHashes) > 100) {
                throw new NativeError('crypto_migration_structure_context_proofs');
            }
            $previous = null;
            foreach ($contextProofHashes as $hash) {
                if (!is_string($hash) || !preg_match('/^[a-f0-9]{64}$/D',$hash) || $previous !== null && strcmp($previous,$hash) >= 0) {
                    throw new NativeError('crypto_migration_structure_context_proofs');
                }
                $previous = $hash;
            }
            $header['contextProofHashes'] = $contextProofHashes;
        }
        return hash('sha256', "JivieMigrationStructure/v3\n".NativeCryptoCodec::canonical((object)$header)
            ."\n".NativeCryptoCodec::canonical((object)$section));
    }

    /** Complete set framing, including the valid empty selection. */
    public static function aggregate(array $context, iterable $sections)
    {
        $expected = ['version','serverId','migrationId','captureId','accountId','sourceInventoryRoot'];
        $actual = array_keys($context);
        sort($expected);
        sort($actual);
        if ($actual !== $expected || $context['version'] !== 3 ||
            !preg_match('/^[a-f0-9]{64}$/D', $context['sourceInventoryRoot'])) {
            throw new NativeError('crypto_migration_structure_context');
        }
        foreach (['serverId','migrationId','captureId','accountId'] as $field) {
            self::canonicalId($context[$field]);
        }
        $sink = hash_init('sha256');
        hash_update($sink, "JivieMigrationStructureSet/v3\n".NativeCryptoCodec::canonical((object)$context)."\n");
        $previous = null;
        $count = 0;
        foreach ($sections as $section) {
            $fields = ['version','scopeId','membershipHeadHash','scopeMetadataProofHash','lifecycleHash',
                'sourceBindingCount','sourceCommitmentRoot','structureHash'];
            $keys = array_keys($section);
            sort($fields);
            sort($keys);
            if ($keys !== $fields || $section['version'] !== 3 ||
                !is_int($section['sourceBindingCount']) || $section['sourceBindingCount'] < 0 ||
                $section['sourceBindingCount'] > 9007199254740991 - $count ||
                $previous !== null && strcmp($previous,$section['scopeId']) >= 0) {
                throw new NativeError('crypto_migration_structure_order');
            }
            self::canonicalId($section['scopeId']);
            foreach (['membershipHeadHash','scopeMetadataProofHash','lifecycleHash','sourceCommitmentRoot','structureHash'] as $field) {
                if (!is_string($section[$field]) || !preg_match('/^[a-f0-9]{64}$/D',$section[$field])) {
                    throw new NativeError('crypto_migration_structure_context');
                }
            }
            $count += $section['sourceBindingCount'];
            hash_update($sink,NativeCryptoCodec::canonical((object)$section)."\n");
            $previous = $section['scopeId'];
        }
        return ['kind'=>'structure','count'=>$count,'root'=>hash_final($sink)];
    }

    private function cells($typed)
    {
        if (!is_object($typed)) {
            throw new NativeError('crypto_migration_structure_source');
        }
        $result = [];
        foreach (get_object_vars($typed) as $column => $cell) {
            if (!is_array($cell) || !array_key_exists('valueBase64', $cell)) {
                throw new NativeError('crypto_migration_structure_source');
            }
            if ($cell['valueBase64'] === null) {
                $result[$column] = null;
            } else {
                $bytes = base64_decode($cell['valueBase64'], true);
                if ($bytes === false || base64_encode($bytes) !== $cell['valueBase64']) {
                    throw new NativeError('crypto_migration_structure_source');
                }
                $result[$column] = $bytes;
            }
        }
        return $result;
    }

    private function accountIdentity($account, $userId = null)
    {
        $this->uuid($account);
        $known = $this->one('SELECT user_id FROM familyhub_accounts WHERE account_id=?', [$account]);
        if (!$known || $userId !== null && (string)$known['user_id'] !== (string)$userId) {
            throw new NativeError('crypto_migration_structure_identity', 409);
        }
    }

    private function validateSource($context, $row, $actor)
    {
        $table = $context['sourceTable'];
        if (!in_array($table, self::TABLES, true)) {
            throw new NativeError('crypto_migration_structure_source');
        }
        $scope = $table === 'familyhub_scopes' ? $row['id'] : $row['scope_id'];
        $this->uuid($scope);
        if ($context['scopeId'] !== null && $context['scopeId'] !== $scope) {
            throw new NativeError('crypto_migration_structure_source', 409);
        }
        if ($table === 'familyhub_members') {
            $this->accountIdentity($row['account_id'], $row['user_id']);
            if (!in_array($row['role'], ['owner', 'member', 'viewer'], true) ||
                !in_array($row['active'], ['0', '1'], true)) {
                throw new NativeError('crypto_migration_structure_source', 409);
            }
        } elseif (in_array($table, ['familyhub_organization_leaders', 'familyhub_scope_revocations', 'familyhub_finance_grants', 'familyhub_personal_scopes'], true)) {
            $this->accountIdentity($row['account_id']);
        }
        if ($table === 'familyhub_personal_scopes' && $row['account_id'] !== $actor['user']['account_id']) {
            throw new NativeError('permission_revoked', 403);
        }
        if ($table === 'familyhub_finance_grants' && !in_array($row['access_level'], ['none', 'read', 'write'], true)) {
            throw new NativeError('crypto_migration_structure_source', 409);
        }
        if ($table === 'familyhub_finance_policy' &&
            (!in_array($row['enabled'], ['0', '1'], true) ||
             !preg_match('/^(0|[1-9][0-9]*)$/D', $row['revision']))) {
            throw new NativeError('crypto_migration_structure_source', 409);
        }
        if ($table === 'familyhub_scopes') {
            $owner = $this->one('SELECT account_id FROM familyhub_accounts WHERE user_id=?', [$row['owner_id']]);
            if (!$owner || !in_array($row['access_policy_version'], ['1', '2', '3'], true)) {
                throw new NativeError('crypto_migration_structure_identity', 409);
            }
            foreach (['parent_scope_id', 'organization_id'] as $field) {
                if ($row[$field] !== null) {
                    $this->uuid($row[$field]);
                }
            }
        }
        if ($table === 'familyhub_record_relocations') {
            $this->uuid($row['record_id']);
            $this->uuid($row['target_scope_id']);
            if (!in_array($row['finance'], ['0', '1'], true)) {
                throw new NativeError('crypto_migration_structure_source', 409);
            }
        }
        return $scope;
    }

    /**
     * Call only inside the globally locked migration validation transaction.
     * The binding iterator authenticates the complete selected capture inventory;
     * the source resolver rechecks its immutable generation and physical fence.
     * Target descriptors are previously cold-verified staged proofs, never raw
     * decrypted metadata or caller-provided SQL policy replacements.
     */
    public function verify($migrationId, $captureId, $sourceInventoryRoot, $actor,
        callable $captureSourceBindings, callable $captureSourceBinding,
        callable $stagedCaptureTarget, array $targets, ?callable $verifyContextProofs = null)
    {
        if (!$this->transactionActive()) {
            throw new NativeError('crypto_migration_transaction_required', 409);
        }
        $this->uuid($migrationId);
        $this->uuid($captureId);
        $this->digest($sourceInventoryRoot);
        $sources = [];
        $sourceTables = [];
        $previous = null;
        foreach ($captureSourceBindings($migrationId, $captureId, $sourceInventoryRoot, $actor, self::TABLES) as $entry) {
            $binding = NativeCryptoCaptureV3::binding($entry['binding']);
            if ($previous !== null && strcmp($previous, $binding['bindingId']) >= 0) {
                throw new NativeError('crypto_migration_structure_order', 409);
            }
            $previous = $binding['bindingId'];
            $resolved = $captureSourceBinding($migrationId, $captureId, $binding['bindingId'], $actor);
            if ($resolved['binding'] !== $binding || $resolved['context'] !== $entry['context']) {
                throw new NativeError('crypto_migration_structure_source', 409);
            }
            $scope = $this->validateSource($resolved['context'], $this->cells($resolved['typedRow']), $actor);
            $sourceTables[$scope][$resolved['context']['sourceTable']] = true;
            $sources[$scope][] = ['bindingId' => $binding['bindingId'], 'sourceCommitment' => $binding['sourceCommitment']];
        }
        ksort($sources, SORT_STRING);
        $sections = [];
        foreach ($targets as $scopeId => $target) {
            $this->uuid($scopeId);
            $this->fields($target, ['membershipHeadHash', 'scopeMetadataWireId', 'scopeMetadataProofHash', 'lifecycleHash'], ['contextProofHashes']);
            foreach (['membershipHeadHash', 'scopeMetadataProofHash', 'lifecycleHash'] as $field) {
                $this->digest($target[$field]);
            }
            $scope = $this->scope($scopeId, $actor['user']['id']);
            $requiredContextPurposes = [];
            if (!isset($sourceTables[$scopeId]['familyhub_scopes'])) { $requiredContextPurposes[] = 'scopeContext'; }
            $parentScopeId = $scope['parent_scope_id'] ?? $scope['organization_id'] ?? null;
            if ($parentScopeId !== null && !isset($sourceTables[$parentScopeId]['familyhub_scopes'])) { $requiredContextPurposes[] = 'parentAccess'; }
            $scopes = new NativeCryptoScopeV2($this->container, $this->bearer, $this->ip);
            $head = $scopes->current($scopeId);
            if (!$head || $head['head_hash'] !== $target['membershipHeadHash']) {
                throw new NativeError('crypto_migration_structure_head_changed', 409);
            }
            $scopes->assertCurrentMembership($scope, $head);
            $scopes->assertMembershipParity($scope, $scopes->body($head)['members'], $head['head_hash']);
            if ((new NativeCryptoLifecycleV2($this->container))->closingHash($scopeId) !== $target['lifecycleHash']) {
                throw new NativeError('crypto_migration_structure_lifecycle_changed', 409);
            }
            $metadata = $stagedCaptureTarget($migrationId, $scopeId, $target['scopeMetadataWireId'], $target['scopeMetadataProofHash'], $actor);
            $record = $metadata['record'];
            $member = $scopes->member($scopes->body($head), $record['accountId']);
            if ($record['type'] !== 'scopeMetadata' || $record['deleted'] || !$member || !$member['manageKeys']) {
                throw new NativeError('crypto_migration_metadata_authority', 403);
            }
            $header = ['version' => 3, 'serverId' => $this->serverId(), 'migrationId' => $migrationId,
                'captureId' => $captureId, 'sourceInventoryRoot' => $sourceInventoryRoot, 'scopeId' => $scopeId];
            $sink = hash_init('sha256');
            hash_update($sink, "JivieMigrationStructureSources/v3\n".NativeCryptoCodec::canonical((object)$header)."\n");
            foreach ($sources[$scopeId] ?? [] as $source) {
                hash_update($sink, NativeCryptoCodec::canonical((object)$source)."\n");
            }
            $section = ['version' => 3, 'scopeId' => $scopeId,
                'membershipHeadHash' => $target['membershipHeadHash'], 'scopeMetadataProofHash' => $target['scopeMetadataProofHash'],
                'lifecycleHash' => $target['lifecycleHash'], 'sourceBindingCount' => count($sources[$scopeId] ?? []),
                'sourceCommitmentRoot' => hash_final($sink)];
            $contextProofHashes = $target['contextProofHashes'] ?? null;
            // Validate canonical framing before resolving authority. A missing
            // resolver cannot turn a caller-selected digest into parity.
            $structureHash = self::structureHash($header,$section,$contextProofHashes);
            if (($requiredContextPurposes || array_key_exists('contextProofHashes',$target)) &&
                ($contextProofHashes === null || !$verifyContextProofs ||
                $verifyContextProofs($scopeId,$target['membershipHeadHash'],$contextProofHashes,$actor,
                    $requiredContextPurposes,$captureId,$sourceInventoryRoot) !== true)) {
                throw new NativeError('crypto_migration_structure_context_pending',409);
            }
            $section['structureHash'] = $structureHash;
            $sections[$scopeId] = $section;
            unset($sources[$scopeId]);
        }
        if ($sources) {
            throw new NativeError('crypto_migration_structure_incomplete', 409);
        }
        ksort($sections, SORT_STRING);
        return $sections;
    }

    /** One opaque frame artifact after verify() authenticated the full set. */
    public function bindingArtifact($migrationId, $captureId, $sourceInventoryRoot, $bindingId,
        $actor, callable $captureSourceBinding, array $verifiedSections)
    {
        if (!$this->transactionActive()) {
            throw new NativeError('crypto_migration_transaction_required',409);
        }
        $source = $captureSourceBinding($migrationId,$captureId,$bindingId,$actor);
        $binding = NativeCryptoCaptureV3::binding($source['binding']);
        if ($binding['bindingId'] !== $bindingId) {
            throw new NativeError('crypto_migration_structure_source',409);
        }
        $scope = $this->validateSource($source['context'],$this->cells($source['typedRow']),$actor);
        $section = $verifiedSections[$scope] ?? null;
        if (!$section || $section['scopeId'] !== $scope || $section['sourceBindingCount'] < 1) {
            throw new NativeError('crypto_migration_structure_incomplete',409);
        }
        $this->digest($sourceInventoryRoot);
        $this->digest($section['structureHash']);
        return hash('sha256',"JivieMigrationStructureArtifact/v3\n".NativeCryptoCodec::canonical((object)[
            'version'=>3,'serverId'=>$this->serverId(),'accountId'=>$actor['user']['account_id'],
            'migrationId'=>$migrationId,'captureId'=>$captureId,'sourceInventoryRoot'=>$sourceInventoryRoot,
            'binding'=>(object)$binding,'scopeId'=>$scope,'structureHash'=>$section['structureHash'],
        ]));
    }

    /** Private candidate evidence, never an unsigned claim that the list is
     * complete. The cold reader derives its required scopes from its own full
     * authenticated capture and independently verifies every returned proof.
     */
    public function targets($p, $actor, callable $captureSourceBindings, callable $stagedCaptureTarget)
    {
        $this->fields($p,['migrationId','captureId','sourceInventoryRoot'],['afterScopeId','limit']);
        $migrationId = $this->uuid($p['migrationId']);
        $captureId = $this->uuid($p['captureId']);
        $this->digest($p['sourceInventoryRoot']);
        $after = isset($p['afterScopeId']) ? $this->uuid($p['afterScopeId']) : '';
        $limit = $p['limit'] ?? 20;
        if (!is_int($limit) || $limit < 1 || $limit > 20) {
            throw new NativeError('validation_error');
        }
        // Invoking the closed iterator validates own capture/generation/fence,
        // including the valid empty own structural selection.
        foreach ($captureSourceBindings($migrationId,$captureId,$p['sourceInventoryRoot'],$actor,self::TABLES) as $unused) {
            break;
        }
        $out = [];
        $scan = $after;
        $access = new NativeOrganizationAccess($this->container);
        do {
            $rows = $this->many("SELECT scope_id,wire_id,record_proof_hash FROM familyhub_crypto_migration_stage_records_v2 WHERE migration_id=? AND record_type='scopeMetadata' AND scope_id>? ORDER BY scope_id LIMIT 20",[$migrationId,$scan]);
            foreach ($rows as $row) {
                $scan = $row['scope_id'];
                if (!$access->visibleScope($row['scope_id'],$actor['user']['account_id'])) {
                    continue;
                }
                $staged = $stagedCaptureTarget($migrationId,$row['scope_id'],$row['wire_id'],$row['record_proof_hash'],$actor);
                $target = ['scopeId'=>$row['scope_id'],'membershipHeadHash'=>$staged['record']['membershipHeadHash'],
                    'scopeMetadataWireId'=>$row['wire_id'],'scopeMetadataProofHash'=>$row['record_proof_hash'],
                    'lifecycleHash'=>(new NativeCryptoLifecycleV2($this->container))->closingHash($row['scope_id']),
                    'recordProof'=>$staged['recordProof'],'batchCommitment'=>$staged['batchCommitment'],
                    'stageAuthorization'=>$staged['stageAuthorization']];
                $consents=$this->many('SELECT c.context_hash FROM familyhub_crypto_structure_contexts_v3 c JOIN familyhub_crypto_structure_consents_v3 a ON a.context_hash=c.context_hash WHERE c.migration_id=? AND c.scope_id=? AND a.account_id=? AND a.capture_id=? AND a.source_inventory_root=? ORDER BY c.context_hash',[
                    $migrationId,$row['scope_id'],$actor['user']['account_id'],$captureId,$p['sourceInventoryRoot']]);
                if ($consents) $target['contextProofHashes']=array_column($consents,'context_hash');
                $out[]=$target;
                if (count($out) > $limit) {
                    break 2;
                }
            }
        } while (count($rows) === 20);
        $more = count($out) > $limit;
        $out = array_slice($out,0,$limit);
        return ['targets'=>$out,'hasMore'=>$more,'nextAfterScopeId'=>$out ? end($out)['scopeId'] : ($after ?: null)];
    }
}
