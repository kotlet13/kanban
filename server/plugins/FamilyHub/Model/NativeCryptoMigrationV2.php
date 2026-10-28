<?php
namespace Kanboard\Plugin\FamilyHub\Model;

/**
 * Component-wide migration with account-private contributions. This class runs
 * only inside the v2 service's authenticated, signed, globally locked SQL
 * transaction. Raw export does not inherit authority from migration ownership.
 */
class NativeCryptoMigrationV2 extends NativeDatabase
{
    protected $cryptoAccess = true;
    private const MAX_ARCHIVE = 23068672;
    private const ARCHIVE_CHUNK = 196608;

    // Every FamilyHub table and column has an explicit classification. Unknown
    // schema is evidence of an unimplemented domain, never permission to omit it.
    private const COLUMNS = [
        'familyhub_account_mail' => 'token_id,token_cipher,language,state,attempts,next_attempt,lease_token,lease_until,accepted_at',
        'familyhub_account_tokens' => 'id,account_id,purpose,token_hash,email,identity_revision,fingerprint,created_at,expires_at,consumed_at,revoked_at',
        'familyhub_accounts' => 'user_id,account_id',
        'familyhub_attachment_chunks' => 'scope_id,attachment_id,chunk_offset,data',
        'familyhub_attachments' => 'scope_id,id,target_type,target_id,name,mime,size,sha256,owner_account_id,owner_device_id,received,complete,deleted,created_at,updated_at',
        'familyhub_deletion_files' => 'operation_id,path_hash,path',
        'familyhub_deletion_receipts' => 'operation_id,token_hash,deleted_at,complete,cancelled',
        'familyhub_deliveries' => 'inbox_id,state,attempts,next_attempt,expires_at,lease_token,lease_until,sent_at',
        'familyhub_devices' => 'id,user_id,account_id,name,token_hash,credentials_hash,created_at,expires_at,revoked_at',
        'familyhub_document_cleanup' => 'storage_key,created_at',
        'familyhub_document_requests' => 'scope_id,account_id,device_id,request_id,object_id,request_hash,response',
        'familyhub_email_identities' => 'account_id,email,verified_at,pending_email,revision',
        'familyhub_enrollment' => 'id,token_hash,created_at,expires_at,consumed_at,revoked_at',
        'familyhub_finance_audit' => 'scope_id,record_id,revision,actor_account_id,changed_at,before_json,after_json,op_id',
        'familyhub_finance_grants' => 'scope_id,account_id,access_level',
        'familyhub_finance_operations' => 'scope_id,account_id,id,request_hash,response,status',
        'familyhub_finance_policy' => 'scope_id,enabled,revision,sequence,required_contract_version',
        'familyhub_finance_records' => 'scope_id,id,type,revision,deleted,payload,sequence,updated_at,created_by,updated_by,contract_version',
        'familyhub_idea_assets' => 'scope_id,board_id,sha256,owner_account_id,mime,size,width,height,received,complete,published,data,created_at,updated_at',
        'familyhub_idea_report_assets' => 'report_id,scope_id,board_id,sha256',
        'familyhub_inbox' => 'id,event_key,recipient_account_id,scope_id,category,kind,audience,actor_account_id,target_type,target_id,target_revision,group_key,created_at,read_at,revision,sequence,in_app',
        'familyhub_inbox_preferences' => 'scope_id,account_id,category,settings',
        'familyhub_inbox_state' => 'account_id,sequence,visibility_revision,configuration_revision',
        'familyhub_instance' => 'id,server_id',
        'familyhub_invitation_mail' => 'invitation_id,token_cipher,language,state,attempts,next_attempt,lease_token,lease_until,accepted_at',
        'familyhub_invitations' => 'id,scope_id,creator_id,creator_account_id,recipient_username,role,token_hash,created_at,expires_at,accepted_at,accepted_by,accepted_account_id,revoked_at,recipient_email,recipient_account_id,invitation_contract,access_scope',
        'familyhub_members' => 'scope_id,user_id,account_id,role,active',
        'familyhub_moderation_audit' => 'id,report_id,admin_id,action,note,created_at,review_revision',
        'familyhub_moderation_blocks' => 'scope_id,account_id,created_at',
        'familyhub_moderation_reports' => 'id,reporter_account_id,request_id,request_hash,scope_id,target_type,target_id,target_revision,preview_hash,reason,details,snapshot,created_at,status,review_revision,resolved_at,redacted_at',
        'familyhub_native_lock' => 'id,counter',
        'familyhub_operations' => 'scope_id,user_id,id,request_hash,response,status',
        'familyhub_organization_leaders' => 'scope_id,account_id',
        'familyhub_payment_cash' => 'scope_id,movement_id,data',
        'familyhub_payment_events' => 'scope_id,event_id,entry_id,payer_account_id,revision,data',
        'familyhub_payment_projections' => 'scope_id,event_id,source_scope_id,owner_account_id,data',
        'familyhub_personal_scopes' => 'account_id,scope_id',
        'familyhub_policy_acceptances' => 'account_id,policy_version,accepted_at',
        'familyhub_project_invitations' => 'id,project_id,creator_id,recipient_id,request_id,token_hash,created_at,expires_at,accepted_at,revoked_at',
        'familyhub_push_jobs' => 'inbox_id,device_id,registration_revision,token_hash,state,attempts,next_attempt,expires_at,lease_token,lease_until,sent_at',
        'familyhub_push_registrations' => 'device_id,account_id,token_hash,token_cipher,project_id,platform,language,revision,active,updated_at,notification_format',
        'familyhub_rate_limits' => 'id,window_start,attempts',
        'familyhub_record_relocations' => 'scope_id,record_id,finance,target_scope_id',
        'familyhub_records' => 'scope_id,id,type,revision,deleted,payload,sequence,updated_at,contract_version,created_by,updated_by',
        'familyhub_reminders' => 'id,scope_id,account_id,target_type,target_id,target_fingerprint,remind_at,remind_epoch,revision,state,schedule_mode,offset_minutes',
        'familyhub_scope_deletion_files' => 'scope_id,path_hash,path',
        'familyhub_scope_revocations' => 'scope_id,account_id',
        'familyhub_scopes' => 'id,kind,name,owner_id,sequence,created_at,organization_id,required_record_contract,project_root_id,archived,access_policy_version,access_revision,address,metadata_revision,parent_scope_id,deleted_at,documents_sequence',
        'familyhub_tables' => 'scope_id,id,title,cells,revision,deleted,updated_at,created_by,lease_hash,lease_nonce,lease_account_id,lease_device_id,lease_name,lease_expires',
        'familyhub_totp_state' => 'user_id,secret_hash,last_step',
    ];

    private const CONTENT = [
        'familyhub_scopes', 'familyhub_members', 'familyhub_records',
        'familyhub_finance_policy', 'familyhub_finance_grants',
        'familyhub_organization_leaders', 'familyhub_scope_revocations',
        'familyhub_tables', 'familyhub_attachments', 'familyhub_attachment_chunks',
        'familyhub_idea_assets',
    ];
    private const FINANCE = [
        'familyhub_finance_records', 'familyhub_finance_audit',
        'familyhub_payment_events', 'familyhub_payment_projections', 'familyhub_payment_cash',
    ];
    private const PRIVATE_ACCOUNT = [
        'familyhub_document_requests' => 'account_id',
        'familyhub_finance_operations' => 'account_id',
        'familyhub_inbox' => 'recipient_account_id',
        'familyhub_inbox_preferences' => 'account_id',
        'familyhub_reminders' => 'account_id',
        'familyhub_moderation_reports' => 'reporter_account_id',
    ];
    private const SERVER_ONLY_COLUMNS = [
        'familyhub_tables' => ['lease_hash', 'lease_nonce'],
    ];

    /** Cached acknowledgements cannot revive an inaccessible contribution. */
    public function replayAccess($payload, $actor)
    {
        if (isset($payload['header']['captureVersion']) && $payload['header']['captureVersion'] === 3) {
            // A receipt inventory is private to its immutable contributor,
            // including after old permission rows are retired.
            $this->migration($payload['header']['migrationId'], $actor);
            return;
        }
        if (isset($payload['migrationId'])) {
            if (($payload['captureVersion'] ?? null) === 3 && isset($payload['componentId'], $payload['rootScopeId'], $payload['keyId'], $payload['scopeIds'])
                && !$this->one('SELECT id FROM familyhub_crypto_migrations_v2 WHERE id=?', [$payload['migrationId']])) {
                $this->scope($this->uuid($payload['rootScopeId']), $actor['user']['id']);
                return;
            }
            [, $portion] = $this->migration($payload['migrationId'], $actor);
            if (!$this->contributorAvailable($actor['user']['account_id'], json_decode($portion['scope_ids'], true, 34, JSON_THROW_ON_ERROR))) {
                throw new NativeError('permission_revoked', 403);
            }
        }
    }

    /** Exact frozen lifecycle seed; no legacy write or inferred SQL default. */
    public function lifecycleBaseline($scopeId, $migrationId, $inventoryHash, $actor)
    {
        $scopeId = $this->uuid($scopeId);
        $this->digest($inventoryHash);
        [$migration, $portion] = $this->migration($migrationId, $actor);
        if (!in_array($migration['state'], ['fenced', 'verified'], true)
            || !in_array($portion['state'], ['fenced', 'verified'], true)
            || !hash_equals($portion['inventory_hash'], $inventoryHash)) {
            throw new NativeError('crypto_migration_not_fenced', 409);
        }
        $this->unchanged($migration);
        $scope = $this->scope($scopeId, $actor['user']['id']);
        if ((int)$scope['owner_id'] !== (int)$actor['user']['id']) {
            throw new NativeError('permission_revoked', 403);
        }
        $selection = $this->selections($migration, $actor)['familyhub_scopes:content'] ?? null;
        if (!$selection) {
            throw new NativeError('permission_revoked', 403);
        }
        $selection['where'] = '('.$selection['where'].') AND id=?';
        $selection['params'][] = $scopeId;
        $captured = null;
        foreach ($this->rawRows($selection) as $row) {
            if ($captured !== null) {
                throw new NativeError('crypto_migration_source_binding', 409);
            }
            $captured = $row;
        }
        if ($captured === null) {
            throw new NativeError('permission_revoked', 403);
        }
        $cells = get_object_vars($captured);
        if (!isset($cells['archived']) || $cells['archived']['valueBase64'] === null) {
            throw new NativeError('crypto_migration_schema_unsupported', 409);
        }
        $own = base64_decode($cells['archived']['valueBase64'], true);
        if (!in_array($own, ['0', '1'], true)) {
            throw new NativeError('crypto_migration_source_binding', 409);
        }
        $parentId = $scope['parent_scope_id'] ?? $scope['organization_id'] ?? null;
        $inherited = false;
        if ($parentId !== null) {
            if (!in_array($parentId, json_decode($migration['scope_ids'], true, 34, JSON_THROW_ON_ERROR), true)) {
                throw new NativeError('crypto_migration_component_changed', 409);
            }
            // unchanged() has just checked the complete component's frozen
            // source digest. The parent is read only for this minimal bit; no
            // ancestor roster, name, finance ID or key leaves this callback.
            $parent = $this->one('SELECT archived FROM familyhub_scopes WHERE id=?', [$parentId]);
            if (!$parent || !in_array((string)$parent['archived'], ['0', '1'], true)) {
                throw new NativeError('crypto_migration_source_binding', 409);
            }
            $inherited = (string)$parent['archived'] === '1';
        }
        return ['ownArchived' => $own === '1', 'inheritedArchived' => $inherited];
    }

    public function read($operation, $params, $actor)
    {
        if($operation==='crypto2.migration.generation.status')return (new NativeCryptoMigrationGenerationV3($this->container,$this->bearer,$this->ip))->status($params,$actor);
        if($operation==='crypto2.migration.ownAttestation')return (new NativeCryptoMigrationOwnAttestationV3($this->container,$this->bearer,$this->ip))->read($params,$actor);
        if($operation==='crypto2.migration.origin')return $this->origin3Read($params,$actor);
        if($operation==='crypto2.migration.activation.refs')return $this->activation3Refs($params,$actor);
        if(in_array($operation,['crypto2.migration.activation','crypto2.migration.activation.control'],true))return $this->activation3Read($operation,$params,$actor);
        if (in_array($operation,['crypto2.migration.domains.get','crypto2.migration.domains.leaves'],true)) return $this->domain3($operation,$params,$actor);
        if (str_starts_with($operation, 'crypto2.migration.capture.')) {
            return $this->captureRead($operation, $params, $actor);
        }
        if (str_starts_with($operation, 'crypto2.migration.legacy.')) {
            return $this->captureLegacyRead($operation, $params, $actor);
        }
        if ($operation === 'crypto2.migration.blob.get') {
            return $this->migrationBlob($operation, $params, $actor, null);
        }
        if ($operation === 'crypto2.migration.structure.contexts') {
            $this->structureContextGuard($params,$actor);
            if(($params['variant']??null)===NativeCryptoMigrationChoiceRequestV3::VARIANT)return (new NativeCryptoMigrationChoiceRequestV3($this->container,$this->bearer,$this->ip))->read($params,$actor,[$this,'captureSourceBindings']);
            return (new NativeCryptoMigrationStructureContextV3($this->container,$this->bearer,$this->ip))->evidence($params,$actor);
        }
        if ($operation === 'crypto2.migration.structure.targets') {
            return (new NativeCryptoMigrationStructureV3($this->container,$this->bearer,$this->ip))->targets(
                $params,$actor,[$this,'captureSourceBindings'],[$this,'stagedCaptureTarget']);
        }
        if ($operation === 'crypto2.migration.audit.artifact') {
            return (new NativeCryptoMigrationAuditV3($this->container,$this->bearer,$this->ip))->artifact(
                $params,$actor,[$this,'captureSourceBinding']);
        }
        if ($operation === 'crypto2.migration.audit.list') {
            return (new NativeCryptoMigrationAuditReadV3($this->container,$this->bearer,$this->ip))->read($params,$actor);
        }
        if ($operation === 'crypto2.migration.invitations.bridges') {
            return (new NativeCryptoMigrationInvitationStageV3($this->container,$this->bearer,$this->ip))->bridges(
                $params,$actor,[$this,'captureSourceBindings']);
        }
        if ($operation === 'crypto2.migration.notifications.transforms') {
            return (new NativeCryptoMigrationNotificationStageV3($this->container,$this->bearer,$this->ip))->transforms(
                $params,$actor,[$this,'captureSourceBindings']);
        }
        if ($operation === 'crypto2.migration.discover') {
            $this->fields($params, ['scopeId']);
            $scopeId = $this->uuid($params['scopeId']);
            $this->scope($scopeId, $actor['user']['id']);
            $component = $this->component($scopeId);
            return $this->discovery($component, $actor);
        }
        if ($operation === 'crypto2.legacy.lookup') {
            return $this->legacyLookup($params, $actor);
        }
        $required = ['migrationId'];
        $optional = [];
        if ($operation === 'crypto2.migration.stagedRecords') {
            $required = ['migrationId', 'scopeId', 'domain'];
            $optional = ['afterId', 'limit'];
        }
        if ($operation === 'crypto2.migration.exportPage') {
            $required = ['migrationId', 'table', 'domain', 'cursor', 'limit'];
        } elseif ($operation === 'crypto2.migration.exportCell') {
            $required = ['migrationId', 'table', 'domain', 'cursor', 'column', 'offset', 'limit'];
        } elseif ($operation === 'crypto2.migration.archiveGet') {
            $required = ['migrationId', 'id', 'offset'];
        } elseif ($operation === 'crypto2.migration.fileList') {
            $required = ['migrationId', 'scopeId', 'cursor', 'limit'];
        } elseif ($operation === 'crypto2.migration.fileChunk') {
            $required = ['migrationId', 'scopeId', 'kind', 'fileId', 'offset', 'limit', 'stamp'];
        }
        $this->fields($params, $required, $optional);
        [$migration, $portion] = $this->migration($params['migrationId'], $actor);
        if ($operation === 'crypto2.migration.stagedRecords') {
            return $this->stagedRecords($params, $migration, $portion, $actor);
        }
        if ($operation === 'crypto2.migration.status') {
            return $this->status($migration, $portion);
        }
        if ($operation === 'crypto2.migration.archiveGet') {
            return $this->archiveGet($params, $migration, $portion, $actor);
        }
        if (!$this->contributorAvailable($actor['user']['account_id'], json_decode($portion['scope_ids'], true, 34, JSON_THROW_ON_ERROR))) {
            throw new NativeError('crypto_migration_contributor_unavailable', 409);
        }
        if (in_array($operation, ['crypto2.migration.fileList', 'crypto2.migration.fileChunk'], true)) {
            $this->archiveAccess($migration, $portion, $actor);
            $scopeId = $this->uuid($params['scopeId']);
            if (!in_array($scopeId, json_decode($portion['scope_ids'], true, 34, JSON_THROW_ON_ERROR), true)) {
                throw new NativeError('crypto_migration_export_forbidden', 403);
            }
            // Files are content: a private/finance-only contributor gains no
            // content archive merely by sharing the component migration ID.
            $scope = $this->scope($scopeId, $actor['user']['id'], false, true);
            if ((int)$scope['owner_id'] !== (int)$actor['user']['id']) {
                throw new NativeError('crypto_migration_export_forbidden', 403);
            }
            $files = new NativeCryptoMigrationFileExportV2($this->container);
            $result = $operation === 'crypto2.migration.fileList'
                ? $files->page($scopeId, $params['cursor'], $params['limit'])
                : $files->chunk($scopeId, $params['kind'], $params['fileId'], $params['offset'], $params['limit'], $params['stamp']);
            return array_merge(['migrationId' => $migration['id'], 'scopeId' => $scopeId, 'inventoryHash' => $portion['inventory_hash']], $result);
        }
        if (in_array($operation, ['crypto2.migration.exportPage', 'crypto2.migration.exportCell'], true)) {
            $this->archiveAccess($migration, $portion, $actor);
            // The consented frozen descriptor is the streaming snapshot. Each
            // page still checks row/domain rights; final verify rehashes the
            // complete current source once. Do not rehash every file per cell.
            $inventory = (array)json_decode($portion['inventory'], false, 128, JSON_THROW_ON_ERROR);
            return $operation === 'crypto2.migration.exportPage'
                ? $this->exportPage($params, $migration, $portion, $inventory, $actor)
                : $this->exportCell($params, $migration, $portion, $inventory, $actor);
        }
        $this->unchanged($migration);
        $inventory = $this->ownInventory($migration, $actor);
        if ($operation === 'crypto2.migration.inventory') {
            return [
                'migrationId' => $migration['id'],
                'state' => $portion['state'],
                'inventory' => $inventory,
                'inventoryHash' => self::inventoryHash((object)$inventory),
                'expectedInventoryHash' => $portion['inventory_hash'],
                'challenge' => $migration['challenge'],
            ];
        }
        if ($operation === 'crypto2.migration.exportCell') {
            return $this->exportCell($params, $migration, $portion, $inventory, $actor);
        }
        if ($operation === 'crypto2.migration.exportPage') {
            return $this->exportPage($params, $migration, $portion, $inventory, $actor);
        }
        throw new NativeError('unsupported_operation', 404);
    }

    public function write($operation, $params, $actor, $proof, $command = null, $authorKey = null, $captureSecrets = null)
    {
        if(in_array($operation,['crypto2.migration.generation.prepare','crypto2.migration.generation.financeDraft','crypto2.migration.generation.draft','crypto2.migration.generation.seal','crypto2.migration.generation.approve','crypto2.migration.generation.finish'],true)) {
            $generation=new NativeCryptoMigrationGenerationV3($this->container,$this->bearer,$this->ip);
            return match($operation) {
                'crypto2.migration.generation.prepare'=>$generation->prepare($params,$actor,$proof),
                'crypto2.migration.generation.financeDraft'=>$generation->financeDraft($params,$actor),
                'crypto2.migration.generation.draft'=>$generation->draft($params,$actor,$authorKey),
                'crypto2.migration.generation.seal'=>$generation->seal($params,$actor),
                'crypto2.migration.generation.approve'=>$generation->approve($params,$actor),
                'crypto2.migration.generation.finish'=>$generation->finish($params,$actor,fn($migration)=>$this->unchanged($migration),fn($old,$newId,$contributor)=>$this->prepareGenerationSuccessor($old,$newId,$contributor)),
            };
        }
        if($operation==='crypto2.migration.commit3')return $this->commit3($params,$actor);
        if($operation==='crypto2.migration.activation.stage')return $this->activation3Stage($params,$actor);
        if (in_array($operation,['crypto2.migration.domains.prepare','crypto2.migration.domains.contribute','crypto2.migration.domains.anchorContribution','crypto2.migration.domains.certify','crypto2.migration.domains.anchor'],true)) return $this->domain3($operation,$params,$actor,$proof);
        if(in_array($operation,['crypto2.migration.structure.source','crypto2.migration.structure.sourceAnchor','crypto2.migration.structure.context','crypto2.migration.structure.contextApprove'],true)) {
            $this->structureContextGuard($params,$actor);
            if($operation==='crypto2.migration.structure.context'&&($params['variant']??null)===NativeCryptoMigrationChoiceRequestV3::VARIANT)return (new NativeCryptoMigrationChoiceRequestV3($this->container,$this->bearer,$this->ip))->put($params,$actor,$proof,[$this,'captureSourceBinding']);
            $helper=new NativeCryptoMigrationStructureContextV3($this->container,$this->bearer,$this->ip);
            return match($operation){
                'crypto2.migration.structure.source'=>$helper->source($params,$actor,[$this,'captureSourceBindings'],[$this,'captureSourceBinding'],[$this,'stagedCaptureTarget'],[$this,'captureTopology']),
                'crypto2.migration.structure.sourceAnchor'=>$helper->anchor($params,$actor),
                'crypto2.migration.structure.context'=>$helper->project($params,$actor),
                'crypto2.migration.structure.contextApprove'=>$helper->approve($params,$actor,[$this,'captureSourceBindings']),
            };
        }
        if ($operation === 'crypto2.migration.verify3') {
            return $this->verifyCapture3($params,$actor,$proof);
        }
        if (str_starts_with($operation, 'crypto2.migration.capture.')) {
            return $this->captureWrite($operation, $params, $actor, $proof, $captureSecrets);
        }
        if (str_starts_with($operation, 'crypto2.migration.legacy.')) {
            return $this->captureLegacyWrite($operation, $params, $actor, $proof);
        }
        if (in_array($operation,['crypto2.migration.invitations.stage','crypto2.migration.invitations.certify','crypto2.migration.invitations.anchor'],true)) {
            return $this->invitationMigration($operation,$params,$actor,$proof,$command);
        }
        if (in_array($operation,['crypto2.migration.notifications.stage','crypto2.migration.notifications.certify','crypto2.migration.notifications.anchor'],true)) {
            return $this->notificationMigration($operation,$params,$actor,$proof,$command);
        }
        if ($operation === 'crypto2.migration.audit.stage') {
            [$migration,$portion] = $this->migration($params['migrationId'] ?? null,$actor);
            $this->archiveAccess($migration,$portion,$actor);
            $this->unchanged($migration);
            return (new NativeCryptoMigrationAuditV3($this->container,$this->bearer,$this->ip))->stage(
                $params,$actor,$proof,$command,[$this,'captureSourceBinding']);
        }
        if ($operation === 'crypto2.migration.recordsStage' && ($params['captureVersion'] ?? null) === 3) {
            return $this->recordsStageCapture3($params, $actor, $proof, $command, $authorKey, $captureSecrets);
        }
        if ($operation === 'crypto2.migration.legacyFinanceEnable') {
            $this->fields($params, ['scopeId', 'expectedRevision', 'consentVersion']);
            if ($params['consentVersion'] !== 1 || !is_int($params['expectedRevision']) || $params['expectedRevision'] < 0) {
                throw new NativeError('crypto_migration_consent_required', 409);
            }
            return (new NativeCryptoFinancePolicyV2($this->container, $this->bearer, $this->ip))
                ->enableLegacyForMigration($params['scopeId'], $params['expectedRevision'], $actor);
        }
        if (in_array($operation, ['crypto2.migration.blob.begin',
            'crypto2.migration.blob.chunk', 'crypto2.migration.blob.complete'], true)) {
            return $this->migrationBlob($operation, $params, $actor, $proof);
        }
        if ($operation === 'crypto2.legacy.reserveReplacement') {
            return $this->reserveLegacy($params, $actor);
        }
        if ($operation === 'crypto2.migration.prepare') {
            $existing = $this->one("SELECT id FROM familyhub_crypto_migrations_v2 WHERE component_id=? AND state NOT IN ('aborted','retired')", [$params['componentId'] ?? null]);
            if ($existing && $this->one('SELECT capture_id FROM familyhub_crypto_captures_v3 WHERE migration_id=? LIMIT 1', [$existing['id']])) {
                throw new NativeError('crypto_capture_version', 409);
            }
            return $this->prepare($params, $actor);
        }
        $required = ['migrationId'];
        if ($operation === 'crypto2.migration.fence') {
            $required[] = 'inventoryHash';
        } elseif ($operation === 'crypto2.migration.recordsStage') {
            $required = ['migrationId', 'inventoryHash', 'sourceBindings', 'batch'];
        } elseif ($operation === 'crypto2.migration.verify') {
            $required = ['migrationId', 'inventoryHash', 'encryptedManifestBase64', 'contributions', 'coldRestoreProof'];
        } elseif ($operation === 'crypto2.migration.commit') {
            $required = ['migrationId', 'inventoryHash', 'expectedComponentHash'];
        } elseif ($operation === 'crypto2.migration.archiveBegin') {
            $required = ['migrationId', 'id', 'size', 'sha256', 'manifestBase64'];
        } elseif ($operation === 'crypto2.migration.archiveChunk') {
            $required = ['migrationId', 'id', 'offset', 'dataBase64'];
        } elseif ($operation === 'crypto2.migration.archiveComplete') {
            $required = ['migrationId', 'id'];
        }
        $this->fields($params, $required);
        [$migration, $portion] = $this->migration($params['migrationId'], $actor);
        if ($this->one('SELECT capture_id FROM familyhub_crypto_captures_v3 WHERE migration_id=? LIMIT 1', [$migration['id']])
            && !in_array($operation, ['crypto2.migration.abort', 'crypto2.migration.archiveBegin',
                'crypto2.migration.archiveChunk', 'crypto2.migration.archiveComplete'], true)) {
            throw new NativeError('crypto_capture_version', 409);
        }
        if ($operation === 'crypto2.migration.abort') {
            return $this->abort($migration, $actor);
        }
        if (in_array($operation, ['crypto2.migration.archiveBegin', 'crypto2.migration.archiveChunk', 'crypto2.migration.archiveComplete'], true)) {
            return $this->archiveWrite($operation, $params, $migration, $portion, $actor, $proof);
        }
        $this->unchanged($migration);
        if ($operation === 'crypto2.migration.fence') {
            return $this->fence($params, $migration, $portion, $actor, $proof);
        }
        if ($operation === 'crypto2.migration.recordsStage') {
            return $this->recordsStage($params,$migration,$portion,$actor,$proof,$command,$authorKey);
        }
        if ($operation === 'crypto2.migration.verify') {
            return $this->verify($params, $migration, $portion, $actor, $proof);
        }
        if ($operation === 'crypto2.migration.commit') {
            return $this->commit($params, $migration, $portion);
        }
        throw new NativeError('unsupported_operation', 404);
    }

    /** Capture3 never returns the private raw component/portion digest. */
    /** Own account-private frozen structural observation, never active authority. */
    public function captureTopology($migrationId, $captureId, $root, $bindingId, $actor)
    {
        [$migration] = $this->migration($migrationId, $actor);
        $capture = $this->captureRow($migration, $actor);
        if ($capture['capture_id']!==$captureId || $capture['inventory_root']!==$root
            || !in_array($migration['state'], ['preparing','fenced','verified'], true)) {
            throw new NativeError('crypto_capture_context',409);
        }
        $source=$this->captureSourceBinding($migrationId,$captureId,$bindingId,$actor);
        $context=$source['context'];
        if ($context['sourceTable']!=='familyhub_scopes' || $context['domain']!=='content') {
            throw new NativeError('crypto_migration_export_forbidden',403);
        }
        $this->unchanged($migration);
        $scope=$this->one('SELECT * FROM familyhub_scopes WHERE id=?',[$context['scopeId']]);
        if (!$scope || !in_array($scope['kind'],['household','organization'],true)
            || (int)$scope['owner_id']!==(int)$actor['user']['id']) {
            throw new NativeError('crypto_migration_export_forbidden',403);
        }
        $tokens=[];
        $serverId=$this->serverId();
        foreach($this->iterate('SELECT id FROM familyhub_scopes WHERE (parent_scope_id=? OR organization_id=?) AND deleted_at IS NULL ORDER BY id',[$scope['id'],$scope['id']]) as $child) {
            if ($child['id']===$scope['id']) throw new NativeError('crypto_migration_graph_invalid',409);
            $tokens[]=NativeCryptoFinanceTopologyV3::childToken($serverId,$scope['id'],$child['id']);
            if(count($tokens)>1000) throw new NativeError('crypto_finance_topology_set',409);
        }
        return ['captureVersion'=>3,'bindingId'=>$bindingId,'scopeId'=>$scope['id'],
            'topology'=>NativeCryptoFinanceTopologyV3::baseline($serverId,$scope['id'],$tokens)];
    }

    private function captureRead($operation, $params, $actor)
    {
        if ($operation === 'crypto2.migration.capture.discover') {
            $this->fields($params, ['scopeId']);
            $scopeId = $this->uuid($params['scopeId']);
            $this->scope($scopeId, $actor['user']['id']);
            $component = $this->component($scopeId);
            $found = $this->discovery($component, $actor);
            $assigned = $this->participants($component)[$actor['user']['account_id']] ?? [];
            $found['receiptSelections'] = $this->captureReceiptSelections($assigned, $actor);
            unset($found['componentHash']);
            $existing = $this->one("SELECT id FROM familyhub_crypto_migrations_v2 WHERE component_id=? AND state NOT IN ('aborted','retired')", [$found['componentId']]);
            $own = $existing ? $this->one('SELECT capture_id,key_id,authorization FROM familyhub_crypto_captures_v3 WHERE migration_id=? AND account_id=?', [$existing['id'], $actor['user']['account_id']]) : null;
            return ['captureVersion' => 3, 'migrationId' => $existing['id'] ?? null,
                'ownCapture' => $own ? ['captureId' => $own['capture_id'], 'keyId' => $own['key_id'],
                    'authorization' => json_decode($own['authorization'], true, 34, JSON_THROW_ON_ERROR)] : null] + $found;
        }
        $required = ['migrationId'];
        $optional = match ($operation) {
            'crypto2.migration.capture.inventory' => ['afterId','limit'],
            'crypto2.migration.capture.commitments' => ['afterToken','limit'],
            default => [],
        };
        if ($operation === 'crypto2.migration.capture.sourcePage') {
            $required = ['migrationId', 'table', 'domain', 'cursor', 'limit'];
        } elseif ($operation === 'crypto2.migration.capture.sourceCell') {
            $required = ['migrationId', 'table', 'domain', 'cursor', 'column', 'offset', 'limit'];
        } elseif ($operation === 'crypto2.migration.capture.topology') {
            $required = ['migrationId', 'captureId', 'sourceInventoryRoot', 'bindingId'];
        } elseif ($operation === 'crypto2.migration.capture.file') {
            $required = ['migrationId', 'captureId', 'bindingId'];
        } elseif ($operation === 'crypto2.migration.capture.fileChunk') {
            $required = ['migrationId', 'captureId', 'bindingId', 'offset', 'limit', 'stamp'];
        }
        $this->fields($params, $required, $optional);
        [$migration, $portion] = $this->migration($params['migrationId'], $actor);
        $capture = $this->captureRow($migration, $actor);
        if ($operation === 'crypto2.migration.capture.topology') {
            return $this->captureTopology($migration['id'], $params['captureId'], $params['sourceInventoryRoot'], $params['bindingId'], $actor);
        }
        if ($operation === 'crypto2.migration.capture.commitments') {
            $commitments = $this->captureCommitments($migration);
            $after = $params['afterToken'] ?? '';
            if ($after !== '') $this->digest($after);
            $limit = $params['limit'] ?? 50;
            if (!is_int($limit) || $limit < 1 || $limit > 50) throw new NativeError('validation_error');
            $remaining = array_values(array_filter($commitments['portions'], static fn($p) => strcmp($p['portionToken'],$after)>0));
            $page = array_slice($remaining,0,$limit);
            unset($commitments['portions']);
            return ['captureVersion'=>3,'candidate'=>true] + $commitments + [
                'portions'=>$page,'hasMore'=>count($remaining)>$limit,
                'nextAfterToken'=>$page ? end($page)['portionToken'] : null,
            ];
        }
        if (in_array($operation, ['crypto2.migration.capture.file', 'crypto2.migration.capture.fileChunk'], true)) {
            $source = $this->captureSourceBinding($migration['id'], $params['captureId'], $params['bindingId'], $actor);
            $context = $source['context'];
            if ($context['domain'] !== 'content' || !in_array($context['sourceTable'],
                ['familyhub_attachments', 'familyhub_idea_assets'], true)) {
                throw new NativeError('crypto_migration_export_forbidden', 403);
            }
            $this->unchanged($migration);
            $cells = get_object_vars($source['typedRow']);
            $text = static fn($k) => isset($cells[$k]['valueBase64'])
                ? base64_decode($cells[$k]['valueBase64'], true) : null;
            $scopeId = $this->uuid($context['scopeId']);
            $this->scope($scopeId, $actor['user']['id'], false, true);
            $kind = $context['sourceTable'] === 'familyhub_attachments' ? 'attachment' : 'idea';
            if ($kind === 'idea') $this->digest($text('sha256'));
            $id = $kind === 'attachment' ? $this->uuid($text('id')) : $this->uuid($text('board_id')).':'.$text('sha256');
            $files = new NativeCryptoMigrationFileExportV2($this->container);
            $result = $operation === 'crypto2.migration.capture.file'
                ? $files->describe($scopeId, $kind, $id)
                : $files->chunk($scopeId, $kind, $id, $params['offset'], $params['limit'], $params['stamp']);
            // Raw comparison SHA is already present in the encrypted typed row.
            // It is not repeated in any public capture commitment/receipt.
            unset($result['sha256'], $result['id']);
            return ['captureVersion' => 3, 'bindingId' => $params['bindingId']] + $result;
        }
        if (in_array($operation, ['crypto2.migration.capture.sources',
            'crypto2.migration.capture.sourcePage', 'crypto2.migration.capture.sourceCell'], true)) {
            if (!in_array($migration['state'], ['preparing', 'fenced', 'verified'], true)) {
                throw new NativeError('crypto_capture_source_unavailable', 409);
            }
            $this->unchanged($migration);
            $inventory = (array)json_decode($portion['inventory'], false, 128, JSON_THROW_ON_ERROR);
            if ($operation === 'crypto2.migration.capture.sources') {
                $tables = [];
                foreach ((array)$inventory['tables'] as $key => $value) {
                    $row = (array)$value;
                    unset($row['sha256']);
                    $tables[] = $row;
                }
                return ['captureVersion' => 3, 'migrationId' => $migration['id'], 'tables' => $tables];
            }
            $result = $operation === 'crypto2.migration.capture.sourcePage'
                ? $this->exportPage($params, $migration, $portion, $inventory, $actor, true)
                : $this->exportCell($params, $migration, $portion, $inventory, $actor, true);
            unset($result['inventoryHash']);
            return ['captureVersion' => 3] + $result;
        }
        if ($operation === 'crypto2.migration.capture.status') {
            return $this->captureStatus($migration, $portion, $capture);
        }
        if ($operation !== 'crypto2.migration.capture.inventory') {
            throw new NativeError('unsupported_operation', 404);
        }
        $after = isset($params['afterId']) ? $this->uuid($params['afterId']) : '';
        $limit = $params['limit'] ?? 32;
        if (!is_int($limit) || $limit < 1 || $limit > 32) {
            throw new NativeError('validation_error');
        }
        $rows = $this->many('SELECT binding_id,scope_id,domain,source_commitment FROM familyhub_crypto_capture_sources_v3 WHERE migration_id=? AND account_id=? AND binding_id>? ORDER BY binding_id LIMIT '.($limit + 1),
            [$migration['id'], $actor['user']['account_id'], $after]);
        $page = array_slice($rows, 0, $limit);
        return $this->captureStatus($migration, $portion, $capture) + [
            'bindings' => array_map(fn($r) => $this->captureBinding($r), $page),
            'hasMore' => count($rows) > $limit,
            'nextAfterId' => $page ? end($page)['binding_id'] : null,
        ];
    }

    /** The complete opaque component inventory is retained by final certificate
     * ancestry. No private old component/row hash leaves this method. */
    private function captureCommitments($migration)
    {
        if (!in_array($migration['state'],['fenced','verified','committed','retired'],true)) {
            throw new NativeError('crypto_migration_contributions_pending',409);
        }
        $rows=$this->many('SELECT p.account_id,p.scope_ids,p.state,c.capture_id,c.state AS capture_state,c.inventory_root,c.source_count,c.seal_authorization FROM familyhub_crypto_migration_portions_v2 p LEFT JOIN familyhub_crypto_captures_v3 c ON c.migration_id=p.migration_id AND c.account_id=p.account_id WHERE p.migration_id=? ORDER BY p.account_id LIMIT 1001',[$migration['id']]);
        if (!$rows || count($rows)>1000) throw new NativeError('crypto_migration_contributions_pending',409);
        $participants=[];
        foreach($rows as $row) $participants[$row['account_id']]=json_decode($row['scope_ids'],true,34,JSON_THROW_ON_ERROR);
        if (!hash_equals($migration['participants_hash'],self::inventoryHash((object)$participants))) {
            throw new NativeError('crypto_migration_contributions_pending',409);
        }
        $portions=[];
        foreach($rows as $row) {
            if (!in_array($row['state'],['fenced','verified','committed','retired'],true) || $row['capture_state']!=='sealed' || !$row['seal_authorization']) {
                throw new NativeError('crypto_migration_contributions_pending',409);
            }
            $this->uuid($row['capture_id']); $this->digest($row['inventory_root']);
            $authorization=json_decode($row['seal_authorization'],true,34,JSON_THROW_ON_ERROR);
            [$seal]=NativeCryptoCodec::decode($authorization);
            if (($seal['operation']??null)!=='crypto2.migration.capture.seal' ||
                ($seal['accountId']??null)!==$row['account_id'] ||
                ($seal['payload']['captureVersion']??null)!==3 ||
                ($seal['payload']['migrationId']??null)!==$migration['id'] ||
                ($seal['payload']['captureId']??null)!==$row['capture_id'] ||
                ($seal['payload']['inventoryRoot']??null)!==$row['inventory_root'] ||
                ($seal['payload']['sourceCount']??null)!==(int)$row['source_count']) {
                throw new NativeError('crypto_capture_generation_conflict',409);
            }
            $portions[]=['portionToken'=>NativeCryptoMigrationProvenanceV2::portionToken($this->serverId(),$migration['id'],$row['account_id']),
                'captureId'=>$row['capture_id'],'sourceInventoryRoot'=>$row['inventory_root']];
        }
        usort($portions,static fn($a,$b)=>strcmp($a['portionToken'],$b['portionToken']));
        $inventory=NativeCryptoMigrationCommitmentsV3::inventoryCommitment($this->serverId(),$migration['id'],$migration['component_id'],count($rows),$portions);
        return ['serverId'=>$this->serverId(),'migrationId'=>$migration['id'],'componentId'=>$migration['component_id'],
            'portionCount'=>count($rows),'inventoryCommitment'=>$inventory,
            'componentCommitment'=>NativeCryptoMigrationCommitmentsV3::componentCommitment($this->serverId(),$migration['id'],$migration['component_id'],$inventory),
            'portions'=>$portions];
    }

    private function captureWrite($operation, $params, $actor, $proof, $secrets)
    {
        if ($operation === 'crypto2.migration.capture.prepare') {
            $this->fields($params, ['captureVersion', 'captureId', 'migrationId', 'componentId', 'rootScopeId', 'scopeIds', 'receiptSelections', 'keyId', 'authorDirectoryHeadHash']);
            if ($params['captureVersion'] !== 3) {
                throw new NativeError('crypto_capture_version');
            }
            foreach (['captureId', 'migrationId', 'componentId', 'keyId'] as $field) {
                $this->uuid($params[$field]);
            }
            if (!is_array($params['scopeIds']) || !array_is_list($params['scopeIds']) || count($params['scopeIds']) > 1000) {
                throw new NativeError('validation_error');
            }
            $sorted = array_map(fn($id) => $this->uuid($id), $params['scopeIds']);
            sort($sorted, SORT_STRING);
            if ($sorted !== $params['scopeIds'] || count(array_unique($sorted)) !== count($sorted)) {
                throw new NativeError('crypto_capture_context');
            }
            (new NativeCryptoScopeV2($this->container, $this->bearer, $this->ip))->currentAuthorReference($params['authorDirectoryHeadHash'], $actor);
            $directory = (new NativeCryptoDirectoryV2($this->container))->current($actor['user']['account_id']);
            $snapshot = $directory ? json_decode($directory['snapshot'], true, 34, JSON_THROW_ON_ERROR) : null;
            $recovery = false;
            $device = false;
            foreach ($snapshot['keyringEntries'] ?? [] as $entry) {
                if ($entry['id'] !== $params['keyId']) {
                    continue;
                }
                $recovery = $recovery || ($entry['recipientKind'] === 'recovery'
                    && $entry['recipientId'] === $snapshot['recoveryRootEpochId']
                    && $entry['recipientPublicKeyBase64'] === $snapshot['rootEncryptionKeyBase64']);
                $device = $device || ($entry['recipientKind'] === 'device'
                    && $entry['recipientId'] === $actor['device']['id']);
            }
            if (!$recovery || !$device) {
                throw new NativeError('crypto_capture_recovery_pending', 409);
            }
            $existing = $this->one('SELECT * FROM familyhub_crypto_migrations_v2 WHERE id=?', [$params['migrationId']]);
            if ($existing) {
                if (!$this->one('SELECT capture_id FROM familyhub_crypto_captures_v3 WHERE migration_id=? LIMIT 1', [$existing['id']])
                    && !$this->one("SELECT id FROM familyhub_crypto_migration_generations_v3 WHERE new_migration_id=? AND mode='supersede' AND state='superseded'",[$existing['id']])) {
                    throw new NativeError('crypto_capture_version', 409);
                }
                $ids = json_decode($existing['scope_ids'], true, 34, JSON_THROW_ON_ERROR);
                $component = $this->component($ids[0]);
            } else {
                $scopeId = $this->uuid($params['rootScopeId']);
                $this->scope($scopeId, $actor['user']['id']);
                $component = $this->component($scopeId);
            }
            $this->scope($this->uuid($params['rootScopeId']), $actor['user']['id']);
            if ($component['id'] !== $params['componentId'] || !in_array($params['rootScopeId'], $component['ids'], true)) {
                throw new NativeError('crypto_migration_component_changed', 409);
            }
            $assigned = $this->participants($component)[$actor['user']['account_id']] ?? [];
            if (!$assigned || NativeCryptoCodec::canonical($params['receiptSelections']) !== NativeCryptoCodec::canonical($this->captureReceiptSelections($assigned, $actor))) {
                throw new NativeError('crypto_capture_receipt_selection', 409);
            }
            $prepared = $this->prepare(['componentId' => $component['id'],
                'componentHash' => $component['hash'], 'scopeIds' => $params['scopeIds']],
                $actor, $params['migrationId'], $params['rootScopeId']);
            if ($prepared['migrationId'] !== $params['migrationId']) {
                throw new NativeError('crypto_capture_generation_conflict', 409);
            }
            [$migration, $portion] = $this->migration($params['migrationId'], $actor);
            $capture = $this->one('SELECT * FROM familyhub_crypto_captures_v3 WHERE migration_id=? AND account_id=?',
                [$migration['id'], $actor['user']['account_id']]);
            if ($capture) {
                if ($capture['capture_id'] !== $params['captureId'] || $capture['key_id'] !== $params['keyId']) {
                    throw new NativeError('crypto_capture_generation_conflict', 409);
                }
            } else {
                $inboxRow = null;
                foreach ($this->rawRows(['table'=>'familyhub_inbox_state',
                    'columns'=>explode(',',self::COLUMNS['familyhub_inbox_state']),
                    'where'=>'account_id=?','params'=>[$actor['user']['account_id']]]) as $row) {
                    if ($inboxRow !== null) throw new NativeError('crypto_capture_inbox_state_snapshot',409);
                    $inboxRow = $row;
                }
                $observation = NativeCryptoCaptureInboxStateV3::observe($actor['user']['account_id'],$inboxRow);
                $this->change("INSERT INTO familyhub_crypto_captures_v3(migration_id,account_id,capture_id,key_id,state,source_count,authorization,private_inbox_baseline) VALUES(?,?,?,?,'capturing',0,?,?)",
                    [$migration['id'], $actor['user']['account_id'], $params['captureId'], $params['keyId'], json_encode($proof, JSON_THROW_ON_ERROR),
                        NativeCryptoCodec::canonical((object)$observation)]);
                $capture = $this->captureRow($migration, $actor);
            }
            return $this->captureStatus($migration, $portion, $capture);
        }
        if ($operation === 'crypto2.migration.capture.bind') {
            $this->fields($params, ['captureVersion', 'migrationId', 'captureId', 'bindings', 'authorDirectoryHeadHash']);
        } elseif ($operation === 'crypto2.migration.capture.seal') {
            $this->fields($params, ['captureVersion', 'migrationId', 'captureId', 'sourceCount', 'inventoryRoot', 'authorDirectoryHeadHash']);
        } elseif ($operation === 'crypto2.migration.capture.fence') {
            $this->fields($params, ['captureVersion', 'migrationId', 'captureId', 'inventoryRoot', 'consentVersion', 'authorDirectoryHeadHash']);
        } else {
            throw new NativeError('unsupported_operation', 404);
        }
        if ($params['captureVersion'] !== 3) {
            throw new NativeError('crypto_capture_version');
        }
        (new NativeCryptoScopeV2($this->container, $this->bearer, $this->ip))->currentAuthorReference($params['authorDirectoryHeadHash'], $actor);
        [$migration, $portion] = $this->migration($params['migrationId'], $actor);
        $capture = $this->captureRow($migration, $actor);
        if ($params['captureId'] !== $capture['capture_id']) {
            throw new NativeError('crypto_capture_generation_conflict', 409);
        }
        $this->unchanged($migration);
        if ($operation === 'crypto2.migration.capture.bind') {
            if ($capture['state'] !== 'capturing' || $migration['state'] !== 'preparing') {
                throw new NativeError('crypto_capture_sealed', 409);
            }
            $privateBaselines = [];
            $verified = NativeCryptoCaptureV3::verifyBindings([
                'version' => 3, 'serverId' => $this->serverId(), 'captureId' => $capture['capture_id'],
                'migrationId' => $migration['id'], 'accountId' => $actor['user']['account_id'],
            ], $params['bindings'], $secrets, function ($context) use ($migration, $actor, &$privateBaselines) {
                $source = $this->captureSource($migration, $actor, $context);
                if ($context['sourceTable'] === 'familyhub_inbox_state') {
                    NativeCryptoCaptureInboxStateV3::snapshot($actor['user']['account_id'],$source,$source);
                    $privateBaselines[$context['sourceId']] = NativeCryptoCodec::canonical($source);
                }
                return $source;
            });
            foreach ($verified as $entry) {
                $binding = $entry['binding'];
                $context = $entry['context'];
                $prior = $this->one('SELECT * FROM familyhub_crypto_capture_sources_v3 WHERE migration_id=? AND account_id=? AND (binding_id=? OR (source_table=? AND domain=? AND source_id=?))',
                    [$migration['id'], $actor['user']['account_id'], $binding['bindingId'], $context['sourceTable'], $context['domain'], $context['sourceId']]);
                if ($prior) {
                    if ($prior['binding_id'] !== $binding['bindingId'] || $prior['scope_id'] !== $binding['scopeId']
                        || $prior['source_commitment'] !== $binding['sourceCommitment']
                        || $prior['source_table'] !== $context['sourceTable'] || $prior['source_id'] !== $context['sourceId']) {
                        throw new NativeError('crypto_capture_binding_immutable', 409);
                    }
                    $expectedBaseline = $privateBaselines[$context['sourceId']] ?? null;
                    if ($context['sourceTable'] === 'familyhub_inbox_state'
                        ? $prior['private_baseline'] !== $expectedBaseline
                        : $prior['private_baseline'] !== null) {
                        throw new NativeError('crypto_capture_binding_immutable',409);
                    }
                    continue;
                }
                $this->change('INSERT INTO familyhub_crypto_capture_sources_v3(migration_id,account_id,binding_id,scope_id,domain,source_table,source_id,source_commitment,authorization,private_baseline) VALUES(?,?,?,?,?,?,?,?,?,?)',
                    [$migration['id'], $actor['user']['account_id'], $binding['bindingId'], $binding['scopeId'],
                        $binding['domain'], $context['sourceTable'], $context['sourceId'],
                        $binding['sourceCommitment'], json_encode($proof, JSON_THROW_ON_ERROR),
                        $context['sourceTable'] === 'familyhub_inbox_state' ? $privateBaselines[$context['sourceId']] : null]);
            }
            return $this->captureStatus($migration, $portion, $capture);
        }
        if ($operation === 'crypto2.migration.capture.seal') {
            if ($capture['state'] !== 'capturing' || !is_int($params['sourceCount']) || $params['sourceCount'] < 0) {
                throw new NativeError('crypto_capture_sealed', 409);
            }
            // Full source coverage, not just the uploaded subset. Private rows
            // remain private; only their randomized commitments enter the root.
            $expected = 0;
            foreach ($this->selections($migration, $actor) as $selection) {
                foreach ($this->rawRows($selection) as $row) {
                    $expected++;
                }
            }
            $rows = $this->iterate('SELECT * FROM familyhub_crypto_capture_sources_v3 WHERE migration_id=? AND account_id=? ORDER BY binding_id',
                [$migration['id'], $actor['user']['account_id']]);
            $root = NativeCryptoCaptureV3::inventoryRoot([
                'version' => 3, 'serverId' => $this->serverId(), 'captureId' => $capture['capture_id'],
                'migrationId' => $migration['id'], 'accountId' => $actor['user']['account_id'],
                'sourceCount' => $params['sourceCount'],
            ], (function () use ($rows) {
                foreach ($rows as $row) {
                    yield $this->captureBinding($row);
                }
            })());
            if ($expected !== $params['sourceCount'] || !hash_equals($root, $params['inventoryRoot'])) {
                throw new NativeError('crypto_capture_inventory_incomplete', 409);
            }
            $this->change("UPDATE familyhub_crypto_captures_v3 SET state='sealed',inventory_root=?,source_count=?,seal_authorization=? WHERE migration_id=? AND account_id=? AND state='capturing'",
                [$root, $expected, json_encode($proof, JSON_THROW_ON_ERROR), $migration['id'], $actor['user']['account_id']]);
            // Only the account-global counter observation can advance outside
            // this component. Rebase private preview bookkeeping to the exact
            // authenticated Capture3 snapshot, never the later live counters.
            $inventory = $this->ownInventory($migration,$actor);
            $previousInventory = json_decode($portion['inventory'],true,128,JSON_THROW_ON_ERROR);
            $currentInventory = json_decode(self::inventoryCanonical((object)$inventory),true,128,JSON_THROW_ON_ERROR);
            unset($previousInventory['tables']['familyhub_inbox_state:private'], $currentInventory['tables']['familyhub_inbox_state:private']);
            if (self::inventoryCanonical((object)$previousInventory) !== self::inventoryCanonical((object)$currentInventory)) {
                throw new NativeError('crypto_inventory_changed',409);
            }
            $portion['inventory_hash'] = self::inventoryHash((object)$inventory);
            $this->change('UPDATE familyhub_crypto_migration_portions_v2 SET inventory=?,inventory_hash=? WHERE migration_id=? AND account_id=?',
                [self::inventoryCanonical((object)$inventory),$portion['inventory_hash'],$migration['id'],$actor['user']['account_id']]);
            return $this->captureStatus($migration, $portion, $this->captureRow($migration, $actor));
        }
        if ($capture['state'] !== 'sealed' || $capture['inventory_root'] !== $params['inventoryRoot']
            || $params['consentVersion'] !== 1) {
            throw new NativeError('crypto_migration_consent_required', 409);
        }
        $scopes = json_decode($migration['scope_ids'],true,34,JSON_THROW_ON_ERROR);
        $marks = implode(',',array_fill(0,count($scopes),'?'));
        if ($this->one('SELECT id FROM familyhub_attachments WHERE complete=0 AND deleted=0 AND scope_id IN ('.$marks.') LIMIT 1',$scopes)
            || $this->one('SELECT board_id FROM familyhub_idea_assets WHERE complete=0 AND scope_id IN ('.$marks.') LIMIT 1',$scopes)) {
            // Refuse before fencing. An interrupted legacy upload must have an
            // explicit draft/receipt bridge or be resolved before recapture.
            throw new NativeError('crypto_migration_pending_upload',409);
        }
        // The private v2 comparison baseline is an implementation detail only;
        // its digest is never inserted into the capture3 command or response.
        $this->fence(['inventoryHash' => $portion['inventory_hash'], 'captureVersion' => 3],
            $migration, $portion, $actor, $proof);
        [$migration, $portion] = $this->migration($migration['id'], $actor);
        return $this->captureStatus($migration, $portion, $capture);
    }

    private function captureReceiptSelections($assigned, $actor)
    {
        $selections = [];
        foreach ($assigned as $scopeId) {
            $this->scope($scopeId, $actor['user']['id']);
            // Records and documents are private own-request histories. Their
            // eligible empty tables are included, not inferred from row count.
            $selections[] = ['scopeId' => $scopeId, 'domain' => 'content'];
            $policy = (new NativeFinanceAccess($this->container))
                ->policyForCrypto($scopeId, $actor['user'], false, false);
            if ($policy['enabled'] && $policy['grant'] !== 'none') {
                $selections[] = ['scopeId' => $scopeId, 'domain' => 'finance'];
            }
        }
        usort($selections, fn($a, $b) => strcmp($a['scopeId'].'/'.$a['domain'], $b['scopeId'].'/'.$b['domain']));
        return $selections;
    }

    private function captureSource($migration, $actor, $context)
    {
        if (!preg_match('/^row:(0|[1-9][0-9]{0,14})$/D', $context['sourceId'], $match)) {
            throw new NativeError('crypto_capture_selector');
        }
        // The ordinal belongs to the full actor/domain authorized selection,
        // whose primary-key ordering is frozen by the component baseline.
        $selection = $this->selections($migration, $actor)[$context['sourceTable'].':'.$context['domain']] ?? null;
        if (!$selection) {
            throw new NativeError('crypto_migration_export_forbidden', 403);
        }
        $found = null;
        foreach ($this->rawRows($selection, (int)$match[1], 1) as $row) {
            $found = $row;
        }
        if ($found === null) {
            throw new NativeError('crypto_capture_source_missing', 409);
        }
        $cells = get_object_vars($found);
        $column = $context['sourceTable'] === 'familyhub_scopes' ? 'id' : 'scope_id';
        $scope = isset($cells[$column]['valueBase64']) ? base64_decode($cells[$column]['valueBase64'], true) : null;
        if (($context['domain'] === 'private' && $context['scopeId'] !== null)
            || ($context['domain'] !== 'private' && $scope !== $context['scopeId'])) {
            throw new NativeError('crypto_capture_source_mismatch', 409);
        }
        return $found;
    }

    private function captureRow($migration, $actor)
    {
        $row = $this->one('SELECT * FROM familyhub_crypto_captures_v3 WHERE migration_id=? AND account_id=?',
            [$migration['id'], $actor['user']['account_id']]);
        if (!$row) {
            throw new NativeError('crypto_capture_missing', 404);
        }
        return $row;
    }

    /** Closed own notification control; no scheduler effect before commit. */
    private function notificationMigration($operation,$params,$actor,$proof,$command)
    {
        $context = $operation === 'crypto2.migration.notifications.certify' ? ($params['header'] ?? []) : $params;
        [$migration,$portion] = $this->migration($context['migrationId'] ?? null,$actor);
        $this->archiveAccess($migration,$portion,$actor);
        $this->unchanged($migration);
        $capture = $this->captureRow($migration,$actor);
        if ($capture['state'] !== 'sealed' || $capture['capture_id'] !== ($context['captureId'] ?? null)
            || $capture['inventory_root'] !== ($context['sourceInventoryRoot'] ?? null)) {
            throw new NativeError('crypto_capture_generation_conflict',409);
        }
        $helper = new NativeCryptoMigrationNotificationStageV3($this->container,$this->bearer,$this->ip);
        if ($operation === 'crypto2.migration.notifications.stage') {
            return $helper->stage($params,$actor,$proof,$command,[$this,'captureSourceBinding'],[$this,'stagedCaptureTarget']);
        }
        if ($operation === 'crypto2.migration.notifications.anchor') return $helper->anchor($params,$actor);
        return $helper->certify($params,$actor,$proof,$command,[$this,'captureSourceBindings'],
            function($header,$selected,$actor) use ($portion) {
                if ($portion['verification'] === null) return false;
                $verified = json_decode($portion['verification'],true,128,JSON_THROW_ON_ERROR);
                if (($verified['version'] ?? null) !== 3 || !isset($verified['authorization'],$verified['header'],$verified['sections']['notifications'])) return false;
                $cold = $verified['header'];
                $section = $verified['sections']['notifications'];
                return ($cold['captureId'] ?? null) === $header['captureId']
                    && ($cold['sourceInventoryRoot'] ?? null) === $header['sourceInventoryRoot']
                    && ($cold['archiveManifestHash'] ?? null) === $header['archiveManifestHash']
                    && NativeCryptoV2Codec::hash((object)$verified['authorization']) === $header['coldParityProofHash']
                    && ($section['count'] ?? null) === $selected['transformCount']
                    && ($section['root'] ?? null) === $selected['selectionRoot'];
            });
    }

    /** Own invitation preservation follows the same pre-cert cold-parity gate. */
    private function invitationMigration($operation,$params,$actor,$proof,$command)
    {
        $context = $operation === 'crypto2.migration.invitations.certify' ? ($params['header'] ?? []) : $params;
        [$migration,$portion] = $this->migration($context['migrationId'] ?? null,$actor);
        $this->archiveAccess($migration,$portion,$actor);
        $this->unchanged($migration);
        $capture = $this->captureRow($migration,$actor);
        if ($capture['state'] !== 'sealed' || $capture['capture_id'] !== ($context['captureId'] ?? null)
            || $capture['inventory_root'] !== ($context['sourceInventoryRoot'] ?? null)) {
            throw new NativeError('crypto_capture_generation_conflict',409);
        }
        $helper = new NativeCryptoMigrationInvitationStageV3($this->container,$this->bearer,$this->ip);
        if ($operation === 'crypto2.migration.invitations.stage') return $helper->stage($params,$actor,$proof,$command,[$this,'captureSourceBinding']);
        if ($operation === 'crypto2.migration.invitations.anchor') return $helper->anchor($params,$actor);
        return $helper->certify($params,$actor,$proof,$command,[$this,'captureSourceBindings'],
            function($header,$selected,$actor) use ($portion) {
                if ($portion['verification'] === null) return false;
                $v = json_decode($portion['verification'],true,128,JSON_THROW_ON_ERROR);
                if (($v['version'] ?? null) !== 3 || !isset($v['authorization'],$v['header'],$v['sections']['invitations'])) return false;
                return ($v['header']['captureId'] ?? null) === $header['captureId']
                    && ($v['header']['sourceInventoryRoot'] ?? null) === $header['sourceInventoryRoot']
                    && ($v['header']['archiveManifestHash'] ?? null) === $header['archiveManifestHash']
                    && NativeCryptoV2Codec::hash((object)$v['authorization']) === $header['coldParityProofHash']
                    && ($v['sections']['invitations']['count'] ?? null) === $selected['bridgeCount']
                    && ($v['sections']['invitations']['root'] ?? null) === $selected['selectionRoot'];
            });
    }

    /** Server-internal private source access for closed canonical installers.
     * No salt or raw hash enters a public proof. The caller must validate its
     * signed transformation and run inside the common migration SQL boundary.
     */
    public function captureSourceBinding($migrationId, $captureId, $bindingId, $actor)
    {
        [$migration, $portion] = $this->migration($migrationId, $actor);
        $this->archiveAccess($migration, $portion, $actor);
        $capture = $this->captureRow($migration, $actor);
        if ($capture['capture_id'] !== $this->uuid($captureId) || $capture['state'] !== 'sealed') {
            throw new NativeError('crypto_capture_generation_conflict', 409);
        }
        $row = $this->one('SELECT * FROM familyhub_crypto_capture_sources_v3 WHERE migration_id=? AND account_id=? AND binding_id=?',
            [$migration['id'], $actor['user']['account_id'], $this->uuid($bindingId)]);
        if (!$row) {
            throw new NativeError('crypto_capture_source_missing', 409);
        }
        if ($row['source_table'] !== 'familyhub_inbox_state' && $row['private_baseline'] !== null) {
            throw new NativeError('crypto_capture_inbox_state_snapshot',409);
        }
        $context = ['version' => 3, 'serverId' => $this->serverId(),
            'captureId' => $capture['capture_id'], 'migrationId' => $migration['id'],
            'accountId' => $actor['user']['account_id'], 'scopeId' => $row['scope_id'],
            'domain' => $row['domain'], 'sourceTable' => $row['source_table'], 'sourceId' => $row['source_id']];
        return ['context' => $context, 'binding' => $this->captureBinding($row),
            'typedRow' => $this->captureSource($migration, $actor, $context)];
    }

    /** Internal bounded source enumeration; never a public export endpoint. */
    public function captureSourceBindings($migrationId, $captureId, $sourceInventoryRoot, $actor, array $tables)
    {
        [$migration,$portion] = $this->migration($migrationId,$actor);
        $this->archiveAccess($migration,$portion,$actor);
        $capture = $this->captureRow($migration,$actor);
        if ($capture['capture_id'] !== $captureId || $capture['state'] !== 'sealed' || $capture['inventory_root'] !== $sourceInventoryRoot) {
            throw new NativeError('crypto_capture_generation_conflict',409);
        }
        foreach ($tables as $table) {
            if (!is_string($table) || !isset(self::COLUMNS[$table])) throw new NativeError('crypto_migration_source_table',409);
        }
        if (!$tables) return;
        $after = null;
        do {
            $params = [$migrationId,$actor['user']['account_id'],...$tables];
            $sql = 'SELECT binding_id FROM familyhub_crypto_capture_sources_v3 WHERE migration_id=? AND account_id=? AND source_table IN ('
                .implode(',',array_fill(0,count($tables),'?')).')';
            if ($after !== null) { $sql .= ' AND binding_id>?'; $params[] = $after; }
            $page = $this->many($sql.' ORDER BY binding_id LIMIT 20',$params);
            foreach ($page as $row) {
                $after = $row['binding_id'];
                $source = $this->captureSourceBinding($migrationId,$captureId,$after,$actor);
                yield ['context'=>$source['context'],'binding'=>$source['binding']];
            }
        } while (count($page) === 20);
    }

    /** Internal ciphertext-only target resolver for closed migration adapters. */
    public function stagedCaptureTarget($migrationId, $scopeId, $wireId, $recordProofHash, $actor)
    {
        [$migration, $portion] = $this->migration($migrationId, $actor);
        $this->archiveAccess($migration, $portion, $actor);
        $scopeId = $this->uuid($scopeId);
        NativeCryptoRecordAddressV2::wireId($wireId);
        $this->digest($recordProofHash);
        $row = $this->one('SELECT * FROM familyhub_crypto_migration_stage_records_v2 WHERE migration_id=? AND scope_id=? AND wire_id=? AND record_proof_hash=?',
            [$migration['id'], $scopeId, $wireId, $recordProofHash]);
        if (!$row) throw new NativeError('crypto_migration_target_pending', 409);
        $proof = json_decode($row['record_proof'], true, 34, JSON_THROW_ON_ERROR);
        if (hash('sha256', NativeCryptoCodec::canonical((object)$proof)) !== $recordProofHash) {
            throw new NativeError('crypto_migration_stage_unavailable', 503);
        }
        [$record] = NativeCryptoCodec::decode($proof);
        (new NativeCryptoScopeV2($this->container, $this->bearer, $this->ip))->author(
            $scopeId, $record['membershipHeadHash'], $record['epoch'], $record['accessRevision'],
            $actor, $record['domain'], false);
        $batch = $this->one('SELECT authorization FROM familyhub_crypto_migration_stage_batches_v2 WHERE migration_id=? AND batch_id=?',
            [$migration['id'], $record['batchId']]);
        if (!$batch) throw new NativeError('crypto_migration_stage_unavailable', 503);
        $stage = json_decode($batch['authorization'], true, 34, JSON_THROW_ON_ERROR);
        [$command] = NativeCryptoCodec::decode($stage);
        if (($command['payload']['captureVersion'] ?? null) !== 3
            || $record['scopeId'] !== $scopeId || $record['id'] !== $wireId) {
            throw new NativeError('crypto_migration_target_pending', 409);
        }
        return ['record' => $record, 'recordProof' => $proof, 'recordProofHash' => $recordProofHash,
            'batchCommitment' => json_decode($row['batch_commitment'], true, 34, JSON_THROW_ON_ERROR),
            'stageAuthorization' => $stage];
    }

    private function captureBinding($row)
    {
        return ['bindingId' => $row['binding_id'], 'scopeId' => $row['scope_id'],
            'domain' => $row['domain'], 'sourceCommitment' => $row['source_commitment']];
    }

    private function captureStatus($migration, $portion, $capture)
    {
        $status = $this->status($migration, $portion);
        unset($status['componentHash'], $status['inventoryHash']);
        return ['captureVersion' => 3, 'captureId' => $capture['capture_id'],
            'keyId' => $capture['key_id'], 'captureState' => $capture['state'],
            'inventoryRoot' => $capture['inventory_root'], 'sourceCount' => (int)$capture['source_count'],
            'prepareAuthorization' => json_decode($capture['authorization'], true, 34, JSON_THROW_ON_ERROR),
            'sealAuthorization' => $capture['seal_authorization'] === null ? null : json_decode($capture['seal_authorization'], true, 34, JSON_THROW_ON_ERROR)] + $status;
    }

    /** Metadata-only keyset scan; large response bytes are never buffered here. */
    private function captureReceiptMetadata($selection)
    {
        $schema = $this->sqlite ? $this->many('PRAGMA table_info('.$selection['table'].')')
            : $this->many('SHOW COLUMNS FROM '.$selection['table']);
        $keys = [];
        foreach ($schema as $column) {
            if ($this->sqlite ? (int)$column['pk'] > 0 : $column['Key'] === 'PRI') {
                $keys[] = $column[$this->sqlite ? 'name' : 'Field'];
            }
        }
        if (!$keys) {
            throw new NativeError('crypto_migration_schema_unsupported', 409);
        }
        $cursor = null;
        while (true) {
            $where = $selection['where'];
            $params = $selection['params'];
            if ($cursor !== null) {
                $alternatives = [];
                foreach ($keys as $index => $key) {
                    $clauses = [];
                    for ($prior = 0; $prior < $index; $prior++) {
                        $clauses[] = $keys[$prior].'=?';
                        $params[] = $cursor[$keys[$prior]];
                    }
                    $clauses[] = $key.'>?';
                    $params[] = $cursor[$key];
                    $alternatives[] = '('.implode(' AND ', $clauses).')';
                }
                $where = '('.$where.') AND ('.implode(' OR ', $alternatives).')';
            }
            $page = $this->many('SELECT '.implode(',', $keys).' FROM '.$selection['table']
                .' WHERE '.$where.' ORDER BY '.implode(',', $keys).' LIMIT 128', $params);
            if (!$page) {
                return;
            }
            foreach ($page as $row) {
                yield $row;
                $cursor = $row;
            }
        }
    }

    private function captureLegacyDescriptor($row)
    {
        return NativeCryptoCaptureLegacyV3::descriptor([
            'scopeId' => $row['scope_id'], 'receiptKind' => $row['receipt_kind'],
            'legacyId' => $row['legacy_id'], 'legacyDeviceId' => $row['legacy_device_id'] ?: null,
            'bindingId' => $row['binding_id'], 'sourceCommitment' => $row['source_commitment'],
        ]);
    }

    private function captureLegacyCertificate($migration, $actor, $domain)
    {
        if (!in_array($domain, ['content', 'finance'], true)) {
            throw new NativeError('crypto_legacy_inventory_context');
        }
        $row = $this->one('SELECT * FROM familyhub_crypto_legacy_index_certificates_v3 WHERE migration_id=? AND account_id=? AND domain=?',
            [$migration['id'], $actor['user']['account_id'], $domain]);
        if (!$row) {
            throw new NativeError('crypto_legacy_inventory_pending', 409);
        }
        return $row;
    }

    /** A NULL lookup is merely a candidate; only the complete anchored client stream proves absence. */
    private function captureLegacyRead($operation, $params, $actor)
    {
        $required = ['migrationId', 'domain'];
        $optional = [];
        if ($operation === 'crypto2.migration.legacy.inventory') {
            $optional = ['after', 'limit'];
        } elseif ($operation === 'crypto2.migration.legacy.lookup') {
            $required[] = 'tuple';
        } elseif ($operation !== 'crypto2.migration.legacy.status') {
            throw new NativeError('unsupported_operation', 404);
        }
        $this->fields($params, $required, $optional);
        [$migration, $portion] = $this->migration($params['migrationId'], $actor);
        $capture = $this->captureRow($migration, $actor);
        $certificate = $this->captureLegacyCertificate($migration, $actor, $params['domain']);
        $result = ['captureVersion' => 3, 'captureId' => $capture['capture_id'],
            'certificateAuthorization' => json_decode($certificate['authorization'], true, 64, JSON_THROW_ON_ERROR),
            'eventAuthorization' => $certificate['event_authorization'] === null ? null
                : json_decode($certificate['event_authorization'], true, 64, JSON_THROW_ON_ERROR)];
        $args = [$migration['id'], $actor['user']['account_id']];
        $where = 'migration_id=? AND account_id=?';
        if ($params['domain'] === 'finance') {
            $where .= " AND receipt_kind='finance'";
        } else {
            $where .= " AND receipt_kind IN ('records','documents')";
        }
        if ($operation === 'crypto2.migration.legacy.status') {
            return $result;
        }
        if ($operation === 'crypto2.migration.legacy.lookup') {
            $tuple = NativeCryptoCaptureLegacyV3::tuple($params['tuple']);
            $domain = $tuple['receiptKind'] === 'finance' ? 'finance' : 'content';
            if ($domain !== $params['domain']) {
                throw new NativeError('crypto_legacy_receipt_identity');
            }
            $row = $this->one('SELECT * FROM familyhub_crypto_legacy_index_v3 WHERE '.$where
                .' AND scope_id=? AND receipt_kind=? AND legacy_id=? AND legacy_device_id=?',
                array_merge($args, [$tuple['scopeId'], $tuple['receiptKind'], $tuple['legacyId'], $tuple['legacyDeviceId'] ?? '']));
            return $result + ['descriptor' => $row ? $this->captureLegacyDescriptor($row) : null];
        }
        $limit = $params['limit'] ?? 128;
        if (!is_int($limit) || $limit < 1 || $limit > 128) {
            throw new NativeError('validation_error');
        }
        if (isset($params['after'])) {
            $after = NativeCryptoCaptureLegacyV3::tuple($params['after']);
            $keys = ['scope_id' => $after['scopeId'], 'receipt_kind' => $after['receiptKind'],
                'legacy_id' => $after['legacyId'], 'legacy_device_id' => $after['legacyDeviceId'] ?? ''];
            $alternatives = [];
            $prefix = [];
            foreach ($keys as $key => $value) {
                $clauses = [];
                foreach ($prefix as $prior => $priorValue) {
                    $clauses[] = $prior.'=?';
                    $args[] = $priorValue;
                }
                $clauses[] = $key.'>?';
                $args[] = $value;
                $alternatives[] = '('.implode(' AND ', $clauses).')';
                $prefix[$key] = $value;
            }
            $where .= ' AND ('.implode(' OR ', $alternatives).')';
        }
        $rows = $this->many('SELECT * FROM familyhub_crypto_legacy_index_v3 WHERE '.$where
            .' ORDER BY scope_id,receipt_kind,legacy_id,legacy_device_id LIMIT '.($limit + 1), $args);
        $page = array_slice($rows, 0, $limit);
        return $result + ['descriptors' => array_map(fn($r) => $this->captureLegacyDescriptor($r), $page),
            'hasMore' => count($rows) > $limit,
            'nextAfter' => $page ? array_intersect_key($this->captureLegacyDescriptor(end($page)),
                array_flip(['scopeId', 'receiptKind', 'legacyId', 'legacyDeviceId'])) : null];
    }

    private function captureLegacyWrite($operation, $params, $actor, $proof)
    {
        if ($operation === 'crypto2.migration.legacy.certify') {
            $this->fields($params, ['header', 'manifestRoot', 'archiveSegments', 'authorDirectoryHeadHash']);
            $this->digest($params['manifestRoot']);
            $header = NativeCryptoCaptureLegacyV3::header($params['header']);
            if ($header['serverId'] !== $this->serverId() || $header['accountId'] !== $actor['user']['account_id']) {
                throw new NativeError('crypto_legacy_inventory_context');
            }
            [$migration, $portion] = $this->migration($header['migrationId'], $actor);
            $capture = $this->captureRow($migration, $actor);
            $this->archiveAccess($migration, $portion, $actor);
            $this->unchanged($migration);
            (new NativeCryptoScopeV2($this->container, $this->bearer, $this->ip))
                ->currentAuthorReference($params['authorDirectoryHeadHash'], $actor);
            if ($capture['state'] !== 'sealed' || $capture['capture_id'] !== $header['captureId']
                || $capture['inventory_root'] !== $header['sourceInventoryRoot']) {
                throw new NativeError('crypto_capture_generation_conflict', 409);
            }
            [$prepare] = NativeCryptoCodec::decode(json_decode($capture['authorization'], true, 64, JSON_THROW_ON_ERROR));
            $selectionContext = array_intersect_key($header, array_flip(['captureVersion','serverId','accountId','captureId','migrationId']));
            $selectionContext['receiptSelections'] = $prepare['payload']['receiptSelections'];
            if ($header['receiptSelectionHash'] !== NativeCryptoCaptureLegacyV3::selectionHash($selectionContext)) {
                throw new NativeError('crypto_capture_receipt_selection', 409);
            }
            $segments = $params['archiveSegments'];
            if (!is_array($segments) || !array_is_list($segments) || !$segments || count($segments) > 256) {
                throw new NativeError('crypto_migration_archive_manifest');
            }
            $ids = [];
            foreach ($segments as $index => $segment) {
                $this->fields($segment, ['id', 'index', 'size', 'sha256']);
                $id = $this->uuid($segment['id']);
                $archive = $this->archiveRow($migration, $actor, $id);
                if ($segment['index'] !== $index || isset($ids[$id]) || !is_int($segment['size'])
                    || (int)$archive['complete'] !== 1 || (int)$archive['size'] !== $segment['size']
                    || $archive['sha256'] !== $segment['sha256']) {
                    throw new NativeError('crypto_migration_archive_incomplete', 409);
                }
                $ids[$id] = true;
            }
            if (hash('sha256', NativeCryptoCodec::canonical($segments)) !== $header['archiveManifestHash']) {
                throw new NativeError('crypto_migration_archive_manifest');
            }
            $this->captureLegacyIndex($migration, $actor, $capture, $header, $proof);
            $root = NativeCryptoCaptureLegacyV3::root($header, (function () use ($migration, $actor, $header) {
                $where = $header['domain'] === 'finance' ? "receipt_kind='finance'" : "receipt_kind IN ('records','documents')";
                foreach ($this->iterate('SELECT * FROM familyhub_crypto_legacy_index_v3 WHERE migration_id=? AND account_id=? AND '.$where
                    .' ORDER BY scope_id,receipt_kind,legacy_id,legacy_device_id', [$migration['id'], $actor['user']['account_id']]) as $row) {
                    yield $this->captureLegacyDescriptor($row);
                }
            })());
            if (!hash_equals($root, $params['manifestRoot'])) {
                throw new NativeError('crypto_legacy_inventory_incomplete', 409);
            }
            $old = $this->one('SELECT * FROM familyhub_crypto_legacy_index_certificates_v3 WHERE migration_id=? AND account_id=? AND domain=?',
                [$migration['id'], $actor['user']['account_id'], $header['domain']]);
            if ($old) {
                if ($old['manifest_root'] !== $root || $old['authorization'] !== json_encode($proof, JSON_THROW_ON_ERROR)) {
                    throw new NativeError('crypto_legacy_inventory_immutable', 409);
                }
            } else {
                $this->change('INSERT INTO familyhub_crypto_legacy_index_certificates_v3(migration_id,account_id,capture_id,domain,archive_manifest_hash,receipt_count,manifest_root,authorization,event_authorization) VALUES(?,?,?,?,?,?,?,?,NULL)',
                    [$migration['id'], $actor['user']['account_id'], $capture['capture_id'], $header['domain'],
                        $header['archiveManifestHash'], $header['receiptCount'], $root, json_encode($proof, JSON_THROW_ON_ERROR)]);
            }
            return $this->captureLegacyRead('crypto2.migration.legacy.status',
                ['migrationId' => $migration['id'], 'domain' => $header['domain']], $actor);
        }
        if ($operation === 'crypto2.migration.legacy.reserveReplacement') {
            return $this->captureLegacyReserve($params, $actor, $proof);
        }
        if ($operation !== 'crypto2.migration.legacy.anchor') {
            throw new NativeError('unsupported_operation', 404);
        }
        $this->fields($params, ['migrationId', 'domain', 'eventAuthorization']);
        [$migration] = $this->migration($params['migrationId'], $actor);
        $certificate = $this->captureLegacyCertificate($migration, $actor, $params['domain']);
        $authorization = json_decode($certificate['authorization'], true, 64, JSON_THROW_ON_ERROR);
        [$cert] = NativeCryptoCodec::decode($authorization);
        [$event] = NativeCryptoCodec::decode($params['eventAuthorization']);
        $header = $cert['payload']['header'];
        $eventRow = $this->one('SELECT authorization FROM familyhub_crypto_directory WHERE account_id=? AND command_hash=?',
            [$actor['user']['account_id'], hash('sha256', base64_decode($params['eventAuthorization']['commandBase64'], true))]);
        if (!$eventRow || NativeCryptoCodec::canonical(json_decode($eventRow['authorization']))
                !== NativeCryptoCodec::canonical((object)$params['eventAuthorization'])
            || $event['operation'] !== 'crypto2.account.migrationAttest'
            || $event['accountId'] !== $actor['user']['account_id'] || $event['serverId'] !== $this->serverId()
            || $event['payload']['migrationId'] !== $migration['id'] || $event['payload']['domain'] !== $params['domain']
            || $event['payload']['scopeToken'] !== NativeCryptoCaptureLegacyV3::scopeToken($header)
            || $event['payload']['attestationHash'] !== hash('sha256', NativeCryptoCodec::canonical((object)$authorization))) {
            throw new NativeError('crypto_legacy_inventory_anchor', 409);
        }
        // Inclusion is established by the server's already accepted immutable
        // directory chain. Clients independently replay their trusted prefix.
        (new NativeCryptoDirectoryV2($this->container))->current($actor['user']['account_id']);
        $encoded = json_encode($params['eventAuthorization'], JSON_THROW_ON_ERROR);
        if ($certificate['event_authorization'] !== null && $certificate['event_authorization'] !== $encoded) {
            throw new NativeError('crypto_legacy_inventory_immutable', 409);
        }
        $this->change('UPDATE familyhub_crypto_legacy_index_certificates_v3 SET event_authorization=? WHERE migration_id=? AND account_id=? AND domain=? AND event_authorization IS NULL',
            [$encoded, $migration['id'], $actor['user']['account_id'], $params['domain']]);
        return $this->captureLegacyRead('crypto2.migration.legacy.status',
            ['migrationId' => $migration['id'], 'domain' => $params['domain']], $actor);
    }

    private function captureLegacyReserve($params, $actor, $proof)
    {
        $this->fields($params, ['migrationId', 'domain', 'tuple', 'replacementId',
            'absenceCertificateHash', 'originalIntentArchiveId', 'originalIntentCipherHash']);
        [$migration, $portion] = $this->migration($params['migrationId'], $actor);
        $capture = $this->captureRow($migration, $actor);
        $this->archiveAccess($migration, $portion, $actor);
        $certificate = $this->captureLegacyCertificate($migration, $actor, $params['domain']);
        $tuple = NativeCryptoCaptureLegacyV3::tuple($params['tuple']);
        $replacement = $this->uuid($params['replacementId']);
        foreach (['absenceCertificateHash', 'originalIntentCipherHash'] as $key) {
            $this->digest($params[$key]);
        }
        if ($certificate['event_authorization'] === null
            || ($tuple['receiptKind'] === 'finance' ? 'finance' : 'content') !== $params['domain']
            || !in_array($tuple['scopeId'], json_decode($portion['scope_ids'], true, 34, JSON_THROW_ON_ERROR), true)) {
            throw new NativeError('crypto_legacy_outcome_unresolved', 409);
        }
        $authorization = json_decode($certificate['authorization'], true, 64, JSON_THROW_ON_ERROR);
        if (hash('sha256', NativeCryptoCodec::canonical((object)$authorization)) !== $params['absenceCertificateHash']) {
            throw new NativeError('crypto_legacy_inventory_anchor', 409);
        }
        $present = $this->one('SELECT binding_id FROM familyhub_crypto_legacy_index_v3 WHERE migration_id=? AND account_id=? AND scope_id=? AND receipt_kind=? AND legacy_id=? AND legacy_device_id=?',
            [$migration['id'], $actor['user']['account_id'], $tuple['scopeId'], $tuple['receiptKind'],
                $tuple['legacyId'], $tuple['legacyDeviceId'] ?? '']);
        if ($present) {
            // Applied OR rejected remain original encrypted evidence. Neither
            // is absence, and unavailable evidence is never a reason to retry.
            throw new NativeError('crypto_legacy_outcome_unresolved', 409);
        }
        [$command] = NativeCryptoCodec::decode($authorization);
        $archiveId = $this->uuid($params['originalIntentArchiveId']);
        $included = false;
        foreach ($command['payload']['archiveSegments'] as $segment) {
            $included = $included || ($segment['id'] === $archiveId
                && $segment['sha256'] === $params['originalIntentCipherHash']);
        }
        $archive = $this->archiveRow($migration, $actor, $archiveId);
        $intentDescription = json_decode($archive['manifest'], true, 32, JSON_THROW_ON_ERROR);
        if (!$included || (int)$archive['complete'] !== 1
            || $archive['sha256'] !== $params['originalIntentCipherHash']
            || ($intentDescription['artifactKind'] ?? null) !== 'capture3OriginalIntents') {
            throw new NativeError('crypto_legacy_original_intent_pending', 409);
        }
        // The account archive must include the immutable original intent. Its
        // exact private frame is checked locally after decryption; this server
        // check establishes only recovery-reachable ciphertext and tuple CAS.
        $key = [$tuple['scopeId'], $actor['user']['account_id'], $tuple['receiptKind'],
            $tuple['legacyId'], $tuple['legacyDeviceId'] ?? ''];
        $old = $this->one('SELECT * FROM familyhub_crypto_legacy_replacements_v3 WHERE scope_id=? AND account_id=? AND receipt_kind=? AND legacy_id=? AND legacy_device_id=?', $key);
        if ($old) {
            if ($old['migration_id'] !== $migration['id'] || $old['capture_id'] !== $capture['capture_id']
                || $old['replacement_id'] !== $replacement
                || $old['absence_certificate_hash'] !== $params['absenceCertificateHash']
                || $old['original_intent_cipher_hash'] !== $params['originalIntentCipherHash']) {
                throw new NativeError('crypto_legacy_replacement_immutable', 409);
            }
        } else {
            $other = $this->one('SELECT legacy_id FROM familyhub_crypto_legacy_replacements_v3 WHERE account_id=? AND replacement_id=?',
                [$actor['user']['account_id'], $replacement]);
            if ($other) {
                throw new NativeError('crypto_legacy_replacement_immutable', 409);
            }
            $this->change('INSERT INTO familyhub_crypto_legacy_replacements_v3(scope_id,account_id,receipt_kind,legacy_id,legacy_device_id,migration_id,capture_id,replacement_id,absence_certificate_hash,original_intent_cipher_hash,archive_manifest_hash,authorization) VALUES(?,?,?,?,?,?,?,?,?,?,?,?)',
                array_merge($key, [$migration['id'], $capture['capture_id'], $replacement,
                    $params['absenceCertificateHash'], $params['originalIntentCipherHash'],
                    $certificate['archive_manifest_hash'], json_encode($proof, JSON_THROW_ON_ERROR)]));
        }
        return ['captureVersion' => 3, 'replacementId' => $replacement,
            'absenceCertificateHash' => $params['absenceCertificateHash'], 'state' => 'reserved'];
    }

    /** Each public descriptor is derived from one already sealed real source. */
    private function captureLegacyIndex($migration, $actor, $capture, $header, $proof)
    {
        $kinds = ['familyhub_operations' => 'records', 'familyhub_document_requests' => 'documents',
            'familyhub_finance_operations' => 'finance'];
        foreach ($this->selections($migration, $actor) as $selection) {
            $kind = $kinds[$selection['table']] ?? null;
            if ($kind === null || ($kind === 'finance' ? 'finance' : 'content') !== $header['domain']) {
                continue;
            }
            $ordinal = 0;
            foreach ($this->captureReceiptMetadata($selection) as $row) {
                $source = $this->one('SELECT * FROM familyhub_crypto_capture_sources_v3 WHERE migration_id=? AND account_id=? AND source_table=? AND domain=? AND source_id=?',
                    [$migration['id'], $actor['user']['account_id'], $selection['table'], 'private', 'row:'.$ordinal++]);
                if (!$source || $source['scope_id'] !== null) {
                    throw new NativeError('crypto_capture_inventory_incomplete', 409);
                }
                $tuple = NativeCryptoCaptureLegacyV3::tuple(['scopeId' => $row['scope_id'], 'receiptKind' => $kind,
                    'legacyId' => $row[$kind === 'documents' ? 'request_id' : 'id'],
                    'legacyDeviceId' => $kind === 'documents' ? $row['device_id'] : null]);
                $args = [$migration['id'], $actor['user']['account_id'], $tuple['scopeId'], $kind,
                    $tuple['legacyId'], $tuple['legacyDeviceId'] ?? ''];
                $old = $this->one('SELECT * FROM familyhub_crypto_legacy_index_v3 WHERE migration_id=? AND account_id=? AND scope_id=? AND receipt_kind=? AND legacy_id=? AND legacy_device_id=?', $args);
                if ($old) {
                    if ($old['binding_id'] !== $source['binding_id'] || $old['source_commitment'] !== $source['source_commitment']
                        || $old['archive_manifest_hash'] !== $header['archiveManifestHash']) {
                        throw new NativeError('crypto_legacy_inventory_immutable', 409);
                    }
                    continue;
                }
                $this->change('INSERT INTO familyhub_crypto_legacy_index_v3(migration_id,account_id,capture_id,scope_id,receipt_kind,legacy_id,legacy_device_id,binding_id,source_commitment,archive_manifest_hash,authorization) VALUES(?,?,?,?,?,?,?,?,?,?,?)',
                    [$migration['id'], $actor['user']['account_id'], $capture['capture_id'], $tuple['scopeId'], $kind,
                        $tuple['legacyId'], $tuple['legacyDeviceId'] ?? '', $source['binding_id'], $source['source_commitment'],
                        $header['archiveManifestHash'], json_encode($proof, JSON_THROW_ON_ERROR)]);
            }
        }
    }

    /** No WRITE bypass: this authority is only for an immutable frozen source. */
    private function migrationBlob($operation, $params, $actor, $proof)
    {
        if (($params['captureVersion'] ?? null) === 3) {
            return $this->migrationBlobCapture3($operation, $params, $actor, $proof);
        }
        if ($this->one('SELECT capture_id FROM familyhub_crypto_captures_v3 WHERE migration_id=? LIMIT 1', [$params['migrationId'] ?? null])) {
            throw new NativeError('crypto_capture_version', 409);
        }
        $extra = match ($operation) {
            'crypto2.migration.blob.begin' => ['size', 'sha256', 'manifestBase64'],
            'crypto2.migration.blob.chunk' => ['offset', 'dataBase64'],
            'crypto2.migration.blob.get' => ['offset'],
            default => [],
        };
        $this->fields($params, array_merge(NativeCryptoMigrationBlobV2::BASE_FIELDS, $extra));
        [$migration, $portion] = $this->migration($params['migrationId'], $actor);
        if (!in_array($migration['state'], ['fenced', 'verified'], true)
            || !in_array($portion['state'], ['fenced', 'verified'], true)
            || $params['inventoryHash'] !== $portion['inventory_hash']
            || $params['componentHash'] !== $migration['component_hash']) {
            throw new NativeError('crypto_migration_not_fenced', 409);
        }
        $scope = $this->uuid($params['scopeId']);
        $this->uuid($params['id']);
        $this->digest($params['sourceRowHash']);
        $this->digest($params['membershipHeadHash']);
        if (!is_int($params['epoch']) || $params['epoch'] < 1
            || !is_int($params['accessRevision']) || $params['accessRevision'] < 0
            || !in_array($params['purpose'], ['canonicalPayload', 'typedWitness', 'ideaAsset'], true)) {
            throw new NativeError('validation_error');
        }
        $table = $params['sourceTable'];
        $domains = [
            'familyhub_records' => 'content', 'familyhub_finance_records' => 'finance',
            'familyhub_tables' => 'content', 'familyhub_attachments' => 'content',
            'familyhub_idea_assets' => 'content',
        ];
        // The privacy-exception scope SQL witness is account-private archive
        // material. No child domain blob route can publish that full row.
        if (!isset($domains[$table]) || $domains[$table] !== $params['domain']
            || ($params['purpose'] === 'ideaAsset' && $table !== 'familyhub_idea_assets')) {
            throw new NativeError('crypto_migration_blob_source', 409);
        }
        $selection = $this->selections($migration, $actor)[$table.':'.$params['domain']] ?? null;
        if (!$selection) {
            throw new NativeError('crypto_migration_export_forbidden', 403);
        }
        if ($table === 'familyhub_idea_assets') {
            if (!is_string($params['sourceId'])) throw new NativeError('validation_error');
            $identity = explode(':', $params['sourceId']);
            if (count($identity) !== 2) throw new NativeError('validation_error');
            $this->uuid($identity[0]);
            $this->digest($identity[1]);
            $selection['where'] .= ' AND scope_id=? AND board_id=? AND sha256=?';
            $selection['params'] = array_merge($selection['params'], [$scope, ...$identity]);
        } else {
            $this->uuid($params['sourceId']);
            $selection['where'] .= ' AND scope_id=? AND id=?';
            $selection['params'] = array_merge($selection['params'], [$scope, $params['sourceId']]);
        }
        // Current scoped READ, current head, current approved actor device. The
        // normal business gate is intentionally never entered or disabled.
        (new NativeCryptoScopeV2($this->container, $this->bearer, $this->ip))->author(
            $scope, $params['membershipHeadHash'], $params['epoch'], $params['accessRevision'],
            $actor, $params['domain'], false
        );
        $allowance = ['bytes' => 0, 'objects' => 0];
        if ($operation === 'crypto2.migration.blob.begin') {
            $this->unchanged($migration);
            $captured = null;
            foreach ($this->rawRows($selection) as $row) {
                if ($captured !== null) throw new NativeError('crypto_migration_source_binding', 409);
                $captured = $row;
            }
            if ($captured === null || !hash_equals($params['sourceRowHash'], self::inventoryHash($captured))) {
                throw new NativeError('crypto_migration_source_changed', 409);
            }
            $bytes = 0;
            foreach (get_object_vars($captured) as $cell) {
                if ($cell['valueBase64'] !== null) $bytes += strlen(base64_decode($cell['valueBase64'], true));
            }
            $fileBytes = 0;
            if ($table === 'familyhub_attachments') {
                $value = base64_decode($captured->size['valueBase64'], true);
                if (!preg_match('/^(?:0|[1-9][0-9]*)$/D', $value) || (int)$value > 20971520) {
                    throw new NativeError('crypto_migration_blob_source', 409);
                }
                $fileBytes = (int)$value;
            }
            // Covers source JSON, exact base64 typed witness, authenticated
            // stream framing and separate object manifests. Physical attachment
            // bytes are counted once, in addition to their small SQL metadata.
            $allowance['bytes'] = $bytes * 4 + $fileBytes + 1048576;
            $allowance['objects'] = (int)ceil($allowance['bytes'] / NativeCryptoMigrationBlobV2::MAX_BYTES) + 4;
        }
        return (new NativeCryptoMigrationBlobV2($this->container))->handle(
            $operation, $params, $actor, $proof, $allowance
        );
    }

    private function migrationBlobCapture3($operation, $params, $actor, $proof)
    {
        $extra = match ($operation) {
            'crypto2.migration.blob.begin' => ['size', 'sha256', 'manifestBase64'],
            'crypto2.migration.blob.chunk' => ['offset', 'dataBase64'],
            'crypto2.migration.blob.get' => ['offset'], default => [],
        };
        $this->fields($params, array_merge(['captureVersion', 'migrationId', 'captureId',
            'sourceInventoryRoot', 'bindingId', 'scopeId', 'id', 'domain', 'purpose',
            'epoch', 'membershipHeadHash', 'accessRevision'], $extra));
        [$migration, $portion] = $this->migration($params['migrationId'], $actor);
        if($operation==='crypto2.migration.blob.get') {
            $shared=$this->one('SELECT * FROM familyhub_crypto_migration_blobs_v2 WHERE migration_id=? AND id=?',[$migration['id'],$params['id']]);
            if($shared&&$shared['account_id']!==$actor['user']['account_id'])return $this->taskDependencyCipher($params,$actor,$migration,$portion,$shared);
        }
        $capture = $this->captureRow($migration, $actor);
        if ($capture['capture_id'] !== $params['captureId'] || $capture['state'] !== 'sealed'
            || $capture['inventory_root'] !== $params['sourceInventoryRoot']) {
            throw new NativeError('crypto_capture_generation_conflict', 409);
        }
        $source = $this->captureSourceBinding($migration['id'], $capture['capture_id'], $params['bindingId'], $actor);
        $context = $source['context'];
        $table = $context['sourceTable'];
        if ($context['scopeId'] !== $params['scopeId'] || $context['domain'] !== $params['domain']
            || !in_array($table, ['familyhub_records', 'familyhub_finance_records', 'familyhub_tables',
                'familyhub_attachments', 'familyhub_idea_assets','familyhub_finance_audit',
                'familyhub_payment_events','familyhub_payment_projections','familyhub_payment_cash'], true)
            || !in_array($params['purpose'], ['typedWitness', 'canonicalPayload', 'ideaAsset','auditWitness'], true)
            || ($params['purpose'] === 'ideaAsset' && $table !== 'familyhub_idea_assets')
            || (($params['purpose'] === 'auditWitness') !== ($table === 'familyhub_finance_audit'))
            || ($table === 'familyhub_finance_audit' && $params['domain'] !== 'finance')) {
            // Full private scope SQL witnesses must never be child domain blobs.
            throw new NativeError('crypto_migration_blob_source', 409);
        }
        $this->uuid($params['scopeId']);
        $this->uuid($params['id']);
        $this->digest($params['membershipHeadHash']);
        if (!is_int($params['epoch']) || $params['epoch'] < 1
            || !is_int($params['accessRevision']) || $params['accessRevision'] < 0) {
            throw new NativeError('validation_error');
        }
        (new NativeCryptoScopeV2($this->container, $this->bearer, $this->ip))->author(
            $params['scopeId'], $params['membershipHeadHash'], $params['epoch'],
            $params['accessRevision'], $actor, $params['domain'], false);
        $cells = get_object_vars($source['typedRow']);
        $text = static function ($column) use ($cells) {
            return isset($cells[$column]['valueBase64'])
                ? base64_decode($cells[$column]['valueBase64'], true) : null;
        };
        if ($table === 'familyhub_idea_assets') {
            $sourceId = $this->uuid($text('board_id')).':'.$text('sha256');
            $this->digest($text('sha256'));
        } elseif ($table === 'familyhub_finance_audit') {
            $revision = $text('revision');
            if (!is_string($revision) || !preg_match('/^[1-9][0-9]{0,15}$/D',$revision)
                || strlen($revision)===16 && strcmp($revision,'9007199254740991')>0) {
                throw new NativeError('crypto_migration_audit_source',409);
            }
            $sourceId = $this->uuid($text('record_id')).':'.$revision;
        } else {
            $column = match ($table) {
                'familyhub_payment_events','familyhub_payment_projections'=>'event_id',
                'familyhub_payment_cash'=>'movement_id', default=>'id',
            };
            $sourceId = $this->uuid($text($column));
        }
        $allowance = ['bytes' => 0, 'objects' => 0];
        if ($operation === 'crypto2.migration.blob.begin') {
            $this->unchanged($migration);
            $bytes = 0;
            foreach ($cells as $cell) {
                if ($cell['valueBase64'] !== null) {
                    $bytes += strlen(base64_decode($cell['valueBase64'], true));
                }
            }
            $fileBytes = 0;
            if ($table === 'familyhub_attachments') {
                $size = $text('size');
                if (!is_string($size) || !preg_match('/^(?:0|[1-9][0-9]*)$/D', $size) || (int)$size > 20971520) {
                    throw new NativeError('crypto_migration_blob_source', 409);
                }
                $fileBytes = (int)$size;
            }
            // Same explicit framing budget as v2, without public raw hashes.
            $allowance['bytes'] = $bytes * 4 + $fileBytes + 1048576;
            $allowance['objects'] = (int)ceil($allowance['bytes'] / NativeCryptoMigrationBlobV2::MAX_BYTES) + 4;
        }
        $private = array_diff_key($params, array_flip(['captureVersion', 'captureId', 'sourceInventoryRoot', 'bindingId']));
        $private['inventoryHash'] = $portion['inventory_hash'];
        $private['componentHash'] = $migration['component_hash'];
        $private['sourceTable'] = $table;
        $private['sourceId'] = $sourceId;
        $private['sourceRowHash'] = hash('sha256', NativeCryptoCodec::canonical($source['typedRow']));
        // Only the original secret-free v3 authorization is retained by the
        // ciphertext engine. Private normalized parameters never become proof.
        return (new NativeCryptoMigrationBlobV2($this->container))->handle(
            $operation, $private, $actor, $proof, $allowance);
    }

    /** Existing GET, restricted to the exact retained owner task dependency.
     * No foreign capture archive, private scope row or FINANCE witness is read. */
    private function taskDependencyCipher($p,$actor,$migration,$portion,$blob)
    {
        $this->archiveAccess($migration,$portion,$actor);
        $own=$this->captureRow($migration,$actor);
        if($own['state']!=='sealed'||!in_array($migration['state'],['fenced','verified'],true)
            ||$p['domain']!=='content'||$p['purpose']!=='typedWitness'
            ||$blob['domain']!=='content'||$blob['purpose']!=='typedWitness'
            ||$blob['source_table']!=='familyhub_records'||(int)$blob['complete']!==1)throw new NativeError('crypto_migration_dependency_forbidden',403);
        [$prepared]=NativeCryptoCodec::decode(json_decode($own['authorization'],true,64,JSON_THROW_ON_ERROR));
        $selected=in_array($p['scopeId'],$prepared['payload']['scopeIds'],true);
        foreach($prepared['payload']['receiptSelections'] as $selection)if($selection['scopeId']===$p['scopeId']&&$selection['domain']==='content')$selected=true;
        if(!$selected)throw new NativeError('crypto_migration_dependency_forbidden',403);
        $scopes=new NativeCryptoScopeV2($this->container,$this->bearer,$this->ip);
        [$scope,$head]=$scopes->author($p['scopeId'],$p['membershipHeadHash'],$p['epoch'],$p['accessRevision'],$actor,'content',false);
        $owner=$scopes->member($scopes->body($head),$blob['account_id']);
        if(!$owner||$owner['role']!=='owner')throw new NativeError('crypto_migration_dependency_forbidden',403);
        $begin=json_decode($blob['authorization'],true,64,JSON_THROW_ON_ERROR);[$beginBody]=NativeCryptoCodec::decode($begin);
        if($beginBody['operation']!=='crypto2.migration.blob.begin'||$beginBody['accountId']!==$blob['account_id'])throw new NativeError('crypto_migration_dependency_binding',409);
        foreach($p as $field=>$value)if($field!=='offset'&&($beginBody['payload'][$field]??null)!==$value)throw new NativeError('crypto_migration_dependency_binding',409);
        $capture=$this->one('SELECT inventory_root,state FROM familyhub_crypto_captures_v3 WHERE migration_id=? AND account_id=? AND capture_id=?',[$migration['id'],$blob['account_id'],$p['captureId']]);
        if(!$capture||$capture['state']!=='sealed'||$capture['inventory_root']!==$p['sourceInventoryRoot'])throw new NativeError('crypto_migration_dependency_binding',409);
        $record=$this->one('SELECT record_proof,record_proof_hash FROM familyhub_crypto_migration_stage_records_v2 WHERE migration_id=? AND scope_id=? AND domain=? AND source_table=? AND source_id=? AND staged_by=?',[$migration['id'],$p['scopeId'],'content','familyhub_records',$blob['source_id'],$blob['account_id']]);
        if(!$record)throw new NativeError('crypto_migration_dependency_binding',409);
        [$task]=NativeCryptoCodec::decode(json_decode($record['record_proof'],true,34,JSON_THROW_ON_ERROR));
        if($task['type']!=='task'||$task['expectedRevision']!==0||$task['membershipHeadHash']!==$p['membershipHeadHash'])throw new NativeError('crypto_migration_dependency_binding',409);
        $batch=$this->one('SELECT authorization FROM familyhub_crypto_migration_stage_batches_v2 WHERE migration_id=? AND batch_id=?',[$migration['id'],$task['batchId']]);
        if(!$batch)throw new NativeError('crypto_migration_dependency_binding',409);
        [$stage]=NativeCryptoCodec::decode(json_decode($batch['authorization'],true,64,JSON_THROW_ON_ERROR));$sp=$stage['payload'];
        if($stage['accountId']!==$blob['account_id']||$stage['operation']!=='crypto2.migration.recordsStage'||($sp['captureVersion']??null)!==3||$sp['migrationId']!==$migration['id']||$sp['captureId']!==$p['captureId']||$sp['sourceInventoryRoot']!==$p['sourceInventoryRoot']||count($sp['sourceBindings'])!==1||count($sp['batch']['records'])!==2)throw new NativeError('crypto_migration_dependency_binding',409);
        $binding=$sp['sourceBindings'][0];$segment=null;$intent=false;
        if($binding['bindingId']!==$p['bindingId']||$binding['recordProofHash']!==$record['record_proof_hash']||count($binding['companionProofHashes'])!==1||$binding['witness']===null)throw new NativeError('crypto_migration_dependency_binding',409);
        foreach($binding['witness']['segments'] as $s)if($s['id']===$p['id']){if($segment!==null)throw new NativeError('crypto_migration_dependency_binding',409);$segment=$s;}
        foreach($sp['batch']['records'] as $proof){[$r]=NativeCryptoCodec::decode($proof);$hash=NativeCryptoV2Codec::hash((object)$proof);if($hash===$binding['companionProofHashes'][0]&&$r['type']==='taskDerivationIntent'&&$r['scopeId']===$p['scopeId']&&$r['domain']==='content'&&$r['membershipHeadHash']===$p['membershipHeadHash']&&$r['operationId']===$task['operationId'])$intent=true;}
        if(!$intent||!$segment||$segment['size']!==(int)$blob['size']||$segment['sha256']!==$blob['sha256']||$binding['witness']['manifestBase64']!==$blob['manifest'])throw new NativeError('crypto_migration_dependency_binding',409);
        return (new NativeCryptoMigrationBlobV2($this->container))->readVerifiedCipher($blob,$p['offset']);
    }

    private function schema()
    {
        $tables = $this->sqlite
            ? array_column($this->many("SELECT name FROM sqlite_master WHERE type='table' AND name LIKE 'familyhub_%' ORDER BY name"), 'name')
            : array_column($this->many("SELECT TABLE_NAME AS name FROM information_schema.TABLES WHERE TABLE_SCHEMA=DATABASE() AND TABLE_NAME LIKE 'familyhub_%' ORDER BY TABLE_NAME"), 'name');
        $knownCrypto = [
            // Schema 21/23 operational crypto tables; not legacy plaintext sources.
            'invitation_publications_v5', 'invitation_reservations_v5',
            'record_policy_baselines_v1', 'record_policy_entries_v1', 'record_policy_state_v1',
            'accounts', 'directory_state', 'directory', 'devices', 'keyring_entries_v2',
            'keyring_entries', 'receipts', 'scopes', 'domain_keys', 'scope_heads',
            'scope_state', 'closures', 'closure_records', 'record_history',
            'grant_states_v2', 'grant_entries_v2', 'grants', 'records', 'unique_refs',
            'blobs_v2', 'blob_chunks_v2', 'blobs', 'blob_chunks', 'migrations',
            'legacy_receipts', 'security_events', 'migrations_v2',
            'migration_portions_v2', 'migration_legacy_v2', 'domain_cursors', 'record_positions',
            'migration_archives_v2', 'migration_archive_chunks_v2',
            'migration_stage_batches_v2', 'migration_stage_records_v2',
            'migration_generations_v3', 'migration_generation_approvals_v3', 'migration_generation_drafts_v3', 'migration_generation_evidence_v3',
            'migration_blobs_v2', 'migration_blob_chunks_v2', 'migration_audit_v3', 'migration_inbox_v3',
            'migration_domain_attestations_v2', 'migration_domain_leaves_v2',
            'domain_checkpoints', 'domain_attestations', 'table_leases',
            'legacy_index_v2', 'legacy_index_scopes_v2', 'legacy_index_generations_v2',
            'legacy_index_v3', 'legacy_index_certificates_v3', 'legacy_replacements_v3',
            'finance_drafts', 'finance_manifests',
            'owner_acceptances', 'key_drafts', 'key_offers', 'content_manifests',
            'scope_origins', 'reminders_v2', 'invitations_v2',
            'invitation_acceptances_v2', 'invitation_mail_v2', 'protection_v2',
            'lifecycle_log_v2', 'lifecycle_actions_v2', 'lifecycle_children_v2', 'lifecycle_delegations_v2',
            'lifecycle_baselines_v2',
            'finance_policy_intents_v2',
            'scope_observations_v2', 'scope_observation_events_v2',
            'export_offers_v2', 'export_delegations_v2', 'export_certificates_v2',
            'access_intents_v2', 'access_portions_v2', 'captures_v3', 'capture_sources_v3',
            'scheduling_use_proofs_v2', 'scheduling_uses_v2',
            'moderation_reports_v2', 'moderation_stages_v2', 'moderation_chunks_v2',
            'moderation_restrictions_v2', 'moderation_blob_refs_v2', 'moderation_evidence_v2',
            'notification_transforms_v3', 'notification_selections_v3', 'notification_certificates_v3',
            'invitation_bridges_v3', 'invitation_certificates_v3', 'invitation_routes_v3',
            'account_tombstones_v2', 'scope_deletion_blocks_v2', 'scope_deletions_v2',
            'structure_sources_v3', 'structure_contexts_v3', 'structure_consents_v3',
            'migration_contributions_v3', 'migration_activations_v3', 'migration_controls_v3', 'migration_origins_v3','inline_delete_plans_v2','inline_delete_leaves_v2','inline_delete_batches_v2', 'leave_requests_v2',
            'project_relocations_v2','project_relocation_records_v2','project_relocation_shadow_v2','project_relocation_nested_v2','project_relocation_batches_v2','project_relocation_staged_v2','project_relocation_blobs_v2','project_relocation_blob_chunks_v2','project_relocation_audit_v2','project_relocation_notifications_v2','project_relocation_publications_v2','project_relocation_publication_leaves_v2','project_relocation_publication_batches_v2',
        ];
        $descriptors = [];
        foreach ($tables as $table) {
            if (str_starts_with($table, 'familyhub_crypto_')) {
                if (!in_array(substr($table, strlen('familyhub_crypto_')), $knownCrypto, true)) {
                    throw new NativeError('crypto_migration_schema_unsupported', 409);
                }
                continue;
            }
            if (!isset(self::COLUMNS[$table])) {
                throw new NativeError('crypto_migration_schema_unsupported', 409);
            }
            $columns = $this->sqlite
                ? $this->many('PRAGMA table_info('.$table.')')
                : $this->many('SHOW COLUMNS FROM '.$table);
            $actual = array_column($columns, $this->sqlite ? 'name' : 'Field');
            $expected = explode(',', self::COLUMNS[$table]);
            sort($actual, SORT_STRING);
            sort($expected, SORT_STRING);
            if ($actual !== $expected) {
                throw new NativeError('crypto_migration_schema_unsupported', 409);
            }
            $descriptors[$table] = $columns;
        }
        foreach (array_keys(self::COLUMNS) as $required) {
            if (!isset($descriptors[$required])) {
                throw new NativeError('crypto_migration_schema_unsupported', 409);
            }
        }
        return $descriptors;
    }

    /** Global graph is never returned: private payer scopes affect its digest. */
    private function component($rootScopeId)
    {
        $schema = $this->schema();
        $scopes = [];
        $edges = [];
        foreach ($this->many('SELECT * FROM familyhub_scopes ORDER BY id') as $scope) {
            $scopes[$scope['id']] = $scope;
            $edges[$scope['id']] = [];
        }
        if (!isset($scopes[$rootScopeId])) {
            throw new NativeError('permission_revoked', 403);
        }
        $connect = function ($left, $right) use (&$edges, $scopes) {
            if ($left !== $right && isset($scopes[$left], $scopes[$right])) {
                $edges[$left][$right] = true;
                $edges[$right][$left] = true;
            }
        };
        foreach ($scopes as $scope) {
            foreach (['parent_scope_id', 'organization_id'] as $field) {
                if ($scope[$field] !== null) {
                    $connect($scope['id'], $scope[$field]);
                }
            }
        }
        $personal = [];
        foreach ($this->many('SELECT account_id,scope_id FROM familyhub_personal_scopes') as $row) {
            $personal[$row['account_id']] = $row['scope_id'];
        }
        $recordScopes = [];
        foreach (['familyhub_records', 'familyhub_finance_records', 'familyhub_tables', 'familyhub_attachments'] as $table) {
            foreach ($this->many('SELECT id,scope_id FROM '.$table) as $record) {
                $recordScopes[$record['id']][$record['scope_id']] = true;
            }
        }
        // Conservative historical graph: all scope UUID references in legacy
        // JSON remain connected, including unknown preserved extension fields.
        $scan = function ($value, $source, $field = '') use (&$scan, $connect, $scopes, $personal, $recordScopes) {
            if (is_array($value)) {
                foreach ($value as $key => $child) {
                    $scan($child, $source, (string)$key);
                }
            } elseif (is_string($value)) {
                if (isset($scopes[$value])) {
                    $connect($source, $value);
                }
                foreach (array_keys($recordScopes[$value] ?? []) as $target) {
                    $connect($source, $target);
                }
                if (in_array($field, ['payerAccountId', 'payer_account_id', 'owner_account_id'], true) && isset($personal[$value])) {
                    $connect($source, $personal[$value]);
                }
            }
        };
        foreach (['familyhub_records', 'familyhub_finance_records', 'familyhub_operations',
            'familyhub_finance_operations', 'familyhub_document_requests',
            'familyhub_finance_audit', 'familyhub_payment_events', 'familyhub_payment_projections',
            'familyhub_payment_cash', 'familyhub_moderation_reports', 'familyhub_record_relocations'] as $table) {
            foreach ($this->iterate('SELECT * FROM '.$table) as $row) {
                $source = $row['scope_id'];
                if (!isset($scopes[$source])) {
                    throw new NativeError('crypto_migration_graph_invalid', 409);
                }
                foreach (['source_scope_id', 'target_scope_id'] as $field) {
                    if (isset($row[$field])) {
                        $connect($source, $row[$field]);
                    }
                }
                foreach (['payer_account_id', 'owner_account_id'] as $field) {
                    if (isset($row[$field], $personal[$row[$field]])) {
                        $connect($source, $personal[$row[$field]]);
                    }
                }
                foreach (['payload', 'response', 'data', 'before_json', 'after_json', 'snapshot'] as $field) {
                    if (isset($row[$field])) {
                        try {
                            $decoded = json_decode($row[$field], true, 128, JSON_THROW_ON_ERROR);
                        } catch (\JsonException $error) {
                            throw new NativeError('crypto_migration_graph_invalid', 409);
                        }
                        $scan($decoded, $source);
                    }
                }
            }
        }
        $ids = [$rootScopeId => true];
        $pending = [$rootScopeId];
        while ($pending) {
            $id = array_pop($pending);
            foreach (array_keys($edges[$id]) as $next) {
                if (!isset($ids[$next])) {
                    $ids[$next] = true;
                    $pending[] = $next;
                }
            }
        }
        $ids = array_keys($ids);
        sort($ids, SORT_STRING);
        $graph = [];
        foreach ($ids as $id) {
            $neighbors = array_keys($edges[$id]);
            sort($neighbors, SORT_STRING);
            $graph[] = ['scopeId' => $id, 'neighbors' => $neighbors, 'scope' => $scopes[$id]];
        }
        $identity = hash('sha256', "JivieMigrationComponent/v2\n".$this->serverId().implode('', $ids));
        $componentId = substr($identity, 0, 8).'-'.substr($identity, 8, 4).'-4'.substr($identity, 13, 3).'-a'.substr($identity, 17, 3).'-'.substr($identity, 20, 12);
        // The fence binds every classified component row, including private
        // reminders/replay/audit and finance sequence changes invisible to a
        // content editor. Only the combined digest leaves this method.
        $rowDigests = [];
        $placeholders = implode(',', array_fill(0, count($ids), '?'));
        foreach (self::COLUMNS as $table => $columnList) {
            $columns = explode(',', $columnList);
            if (!in_array('scope_id', $columns, true)) {
                continue;
            }
            $selection = ['table' => $table, 'columns' => $columns,
                'where' => 'scope_id IN ('.$placeholders.')', 'params' => $ids];
            $hash = hash_init('sha256');
            foreach ($this->rawRows($selection) as $row) {
                hash_update($hash, NativeCryptoCodec::canonical($row)."\n");
            }
            $rowDigests[$table] = hash_final($hash);
        }
        $files = (new NativeCryptoFileInventory($this->container))->collect($ids);
        $digest = self::inventoryHash((object)[
            'graph' => $graph, 'rows' => (object)$rowDigests, 'files' => $files,
        ]);
        return ['id' => $componentId, 'hash' => $digest, 'ids' => $ids, 'scopes' => $scopes, 'schema' => $schema];
    }

    private function discovery($component, $actor)
    {
        $owned = [];
        $visible = [];
        foreach ($component['ids'] as $id) {
            if ((int)$component['scopes'][$id]['owner_id'] === (int)$actor['user']['id']) {
                $owned[] = $id;
            }
            if ((new NativeOrganizationAccess($this->container))->visibleScope($id, $actor['user']['account_id'])) {
                $visible[] = $id;
            }
        }
        $participants = $this->participants($component);
        return [
            'componentId' => $component['id'],
            'componentHash' => $component['hash'],
            'ownedScopeIds' => $owned,
            'visibleScopeIds' => $visible,
            'pendingOwnerCount' => count(array_diff(array_keys($participants), [$actor['user']['account_id']])),
            'participant' => isset($participants[$actor['user']['account_id']]),
        ];
    }

    private function participants($component)
    {
        $parts = [];
        $add = function ($account, $scopeId) use (&$parts) {
            if (!$account) {
                throw new NativeError('crypto_migration_contributor_unavailable', 409);
            }
            $parts[$account][$scopeId] = true;
        };
        foreach ($component['ids'] as $scopeId) {
            $scope = $component['scopes'][$scopeId];
            $owner = $this->one('SELECT account_id FROM familyhub_accounts WHERE user_id=?', [$scope['owner_id']]);
            $add($owner['account_id'] ?? $this->missingContributorId('owner:'.$scope['owner_id']), $scopeId);
            foreach (self::PRIVATE_ACCOUNT as $table => $column) {
                foreach ($this->many('SELECT DISTINCT '.$column.' AS account FROM '.$table.' WHERE scope_id=?', [$scopeId]) as $row) {
                    $add($row['account'], $scopeId);
                }
            }
            foreach ($this->many('SELECT DISTINCT a.account_id,o.user_id FROM familyhub_operations o LEFT JOIN familyhub_accounts a ON a.user_id=o.user_id WHERE o.scope_id=?', [$scopeId]) as $row) {
                $add($row['account_id'] ?? $this->missingContributorId('legacy-user:'.$row['user_id']), $scopeId);
            }
            // A legacy owner need not have financial access. An authorized
            // financial contributor must preserve that separate domain.
            if ($this->hasFinanceData($scopeId)) {
                $materializer = $this->financeMaterializer($scopeId, $owner['account_id'] ?? null);
                $add($materializer ?? $this->missingContributorId('finance:'.$scopeId), $scopeId);
            }
        }
        ksort($parts, SORT_STRING);
        foreach ($parts as &$scoped) {
            $scoped = array_keys($scoped);
            sort($scoped, SORT_STRING);
        }
        unset($scoped);
        return $parts;
    }

    /** One shared-domain materializer, independent of private receipt participation. */
    private function financeMaterializer($scopeId, $ownerAccount)
    {
        $eligible = [];
        $access = new NativeFinanceAccess($this->container);
        foreach ((new NativeOrganizationAccess($this->container))->members($scopeId) as $member) {
            if ($access->visible($scopeId, $member['accountId'], true)) {
                $eligible[$member['accountId']] = true;
            }
        }
        if ($ownerAccount !== null && isset($eligible[$ownerAccount])) {
            return $ownerAccount;
        }
        $accounts = array_keys($eligible);
        sort($accounts, SORT_STRING);
        return $accounts[0] ?? null;
    }

    private function missingContributorId($identity)
    {
        $hash = hash('sha256', "JivieUnavailableContributor/v2\n".$this->serverId().$identity);
        return substr($hash, 0, 8).'-'.substr($hash, 8, 4).'-4'.substr($hash, 13, 3).'-a'.substr($hash, 17, 3).'-'.substr($hash, 20, 12);
    }

    private function contributorAvailable($account, $scopeIds)
    {
        $user = $this->one('SELECT u.id FROM users u JOIN familyhub_accounts a ON a.user_id=u.id WHERE a.account_id=? AND u.is_active=1', [$account]);
        if (!$user) {
            return false;
        }
        foreach ($scopeIds as $id) {
            if (!(new NativeOrganizationAccess($this->container))->visibleScope($id, $account)) {
                return false;
            }
            if ($this->one('SELECT id FROM familyhub_finance_operations WHERE scope_id=? AND account_id=? LIMIT 1', [$id, $account]) &&
                !(new NativeFinanceAccess($this->container))->visible($id, $account, true)) {
                return false;
            }
        }
        return true;
    }

    private function hasFinanceData($scopeId)
    {
        foreach (['familyhub_finance_records', 'familyhub_finance_audit', 'familyhub_payment_events', 'familyhub_payment_projections', 'familyhub_payment_cash'] as $table) {
            if ($this->one('SELECT scope_id FROM '.$table.' WHERE scope_id=? LIMIT 1', [$scopeId])) {
                return true;
            }
        }
        return (bool)$this->one('SELECT scope_id FROM familyhub_finance_policy WHERE scope_id=? AND enabled=1', [$scopeId]);
    }

    /** A reviewed successor uses the same component and this actor's original
     * owned selection. No old capture, signature, key or request is relabelled. */
    private function prepareGenerationSuccessor($old,$newId,$actor)
    {
        [, $portion]=$this->migration($old['id'],$actor);
        $capture=$this->captureRow($old,$actor);
        [$prepared]=NativeCryptoCodec::decode(json_decode($capture['authorization'],true,64,JSON_THROW_ON_ERROR));
        $root=$prepared['payload']['rootScopeId']??null;
        $this->uuid($root);
        return $this->prepare(['componentId'=>$old['component_id'],'componentHash'=>$old['component_hash'],
            'scopeIds'=>json_decode($portion['scope_ids'],true,34,JSON_THROW_ON_ERROR)],$actor,$newId,$root);
    }

    private function prepare($params, $actor, $requestedId = null, $contributionRoot = null)
    {
        $this->fields($params, ['componentId', 'componentHash', 'scopeIds']);
        $this->uuid($params['componentId']);
        $this->digest($params['componentHash']);
        $owned = $params['scopeIds'];
        if (!is_array($owned) || !array_is_list($owned) || count($owned) > 1000) {
            throw new NativeError('validation_error');
        }
        $owned = array_map(fn($id) => $this->uuid($id), $owned);
        sort($owned, SORT_STRING);
        if (count(array_unique($owned)) !== count($owned)) {
            throw new NativeError('validation_error');
        }
        $existing = $this->one("SELECT * FROM familyhub_crypto_migrations_v2 WHERE component_id=? AND state NOT IN ('aborted','retired')", [$params['componentId']]);
        if ($existing) {
            [$migration, $portion] = $this->migration($existing['id'], $actor);
            $component = $this->unchanged($migration);
            if ($params['componentHash'] !== $migration['component_hash'] || $owned !== $this->discovery($component, $actor)['ownedScopeIds']) {
                throw new NativeError('crypto_migration_owned_portion_mismatch', 403);
            }
            $inventory = $this->ownInventory($migration, $actor);
            $hash = self::inventoryHash((object)$inventory);
            if (in_array($portion['state'], ['preparing', 'unavailable'], true)) {
                $this->change("UPDATE familyhub_crypto_migration_portions_v2 SET inventory=?,inventory_hash=?,state='preparing' WHERE migration_id=? AND account_id=?", [self::inventoryCanonical((object)$inventory), $hash, $migration['id'], $actor['user']['account_id']]);
                $portion['inventory_hash'] = $hash;
                $portion['state'] = 'preparing';
            }
            return $this->status($migration, $portion);
        }
        if (!$owned) {
            if ($contributionRoot === null) {
                throw new NativeError('crypto_migration_owner_required', 409);
            }
            $this->scope($this->uuid($contributionRoot), $actor['user']['id']);
            $component = $this->component($contributionRoot);
            if (!isset($this->participants($component)[$actor['user']['account_id']])) {
                throw new NativeError('crypto_migration_contributor_unavailable', 409);
            }
        } else {
            $this->scope($owned[0], $actor['user']['id'], false, true);
            $component = $this->component($owned[0]);
        }
        if ($component['id'] !== $params['componentId'] || $component['hash'] !== $params['componentHash']) {
            throw new NativeError('crypto_migration_component_changed', 409);
        }
        $expected = $this->discovery($component, $actor)['ownedScopeIds'];
        if ($owned !== $expected) {
            throw new NativeError('crypto_migration_owned_portion_mismatch', 403);
        }
        $existing = $this->one("SELECT id FROM familyhub_crypto_migrations_v2 WHERE component_id=? AND state NOT IN ('aborted','retired')", [$component['id']]);
        if ($existing) {
            [$migration, $portion] = $this->migration($existing['id'], $actor);
            return $this->status($migration, $portion);
        }
        $participants = $this->participants($component);
        $id = $requestedId === null ? $this->newId() : $this->uuid($requestedId);
        $now = time();
        $this->change('INSERT INTO familyhub_crypto_migrations_v2 VALUES(?,?,?,?,?,?,?,?,?)', [
            $id, $component['id'], $component['hash'], json_encode($component['ids'], JSON_THROW_ON_ERROR),
            self::inventoryHash((object)$participants), 'preparing', bin2hex(random_bytes(32)), $now, $now,
        ]);
        // Each account receives only its own assigned scope IDs. Private payer
        // IDs and other actors' receipt rows never appear in another portion.
        foreach ($participants as $account => $ids) {
            $this->change('INSERT INTO familyhub_crypto_migration_portions_v2(migration_id,account_id,scope_ids,inventory,inventory_hash,state) VALUES(?,?,?,?,?,?)', [
                $id, $account, json_encode($ids, JSON_THROW_ON_ERROR), '', str_repeat('0', 64), $this->contributorAvailable($account, $ids) ? 'preparing' : 'unavailable',
            ]);
        }
        [$migration, $portion] = $this->migration($id, $actor);
        $inventory = $this->ownInventory($migration, $actor);
        $hash = self::inventoryHash((object)$inventory);
        $this->change('UPDATE familyhub_crypto_migration_portions_v2 SET inventory=?,inventory_hash=? WHERE migration_id=? AND account_id=?', [
            self::inventoryCanonical((object)$inventory), $hash, $id, $actor['user']['account_id'],
        ]);
        return $this->status($migration, array_replace($portion, ['inventory_hash' => $hash]));
    }

    private function migration($id, $actor)
    {
        $migration = $this->one('SELECT * FROM familyhub_crypto_migrations_v2 WHERE id=?', [$this->uuid($id)]);
        $portion = $migration ? $this->one('SELECT * FROM familyhub_crypto_migration_portions_v2 WHERE migration_id=? AND account_id=?', [$id, $actor['user']['account_id']]) : null;
        if (!$portion) {
            throw new NativeError('crypto_migration_missing', 404);
        }
        // Membership loss does not erase the actor's private contribution.
        // Status remains reachable; raw exports recheck each live scope below.
        return [$migration, $portion];
    }

    private function unchanged($migration)
    {
        $ids = json_decode($migration['scope_ids'], true, 34, JSON_THROW_ON_ERROR);
        $component = $this->component($ids[0]);
        if ($component['id'] !== $migration['component_id'] || $component['hash'] !== $migration['component_hash'] ||
            self::inventoryHash((object)$this->participants($component)) !== $migration['participants_hash']) {
            throw new NativeError('crypto_migration_component_changed', 409);
        }
        return $component;
    }

    private function status($migration, $portion)
    {
        $pending = $this->one("SELECT COUNT(*) AS n FROM familyhub_crypto_migration_portions_v2 WHERE migration_id=? AND state<>'verified'", [$migration['id']]);
        $account = $portion['account_id'];
        $visible = [];
        foreach (json_decode($portion['scope_ids'], true, 34, JSON_THROW_ON_ERROR) as $id) {
            if ((new NativeOrganizationAccess($this->container))->visibleScope($id, $account)) {
                $visible[] = $id;
            }
        }
        $unavailable = $this->one("SELECT COUNT(*) AS n FROM familyhub_crypto_migration_portions_v2 WHERE migration_id=? AND state='unavailable'", [$migration['id']]);
        return [
            'migrationId' => $migration['id'], 'componentId' => $migration['component_id'],
            'componentHash' => $migration['component_hash'], 'state' => $migration['state'],
            'ownState' => $this->contributorAvailable($account, json_decode($portion['scope_ids'], true, 34, JSON_THROW_ON_ERROR)) ? $portion['state'] : 'unavailable', 'scopeIds' => $visible,
            'unavailableContributionCount' => (int)$unavailable['n'],
            'inventoryHash' => $portion['inventory_hash'], 'challenge' => $migration['challenge'],
            'pendingContributionCount' => (int)$pending['n'], 'legacyPreserved' => true,
            'cutoverSupported' => true, 'cutoverVersion' => 3,
        ];
    }

    /** Authorized selection descriptors are used identically for hashing/export. */
    private function selections($migration, $actor)
    {
        [, $portion] = $this->migration($migration['id'], $actor);
        $ids = json_decode($portion['scope_ids'], true, 34, JSON_THROW_ON_ERROR);
        if (!$this->contributorAvailable($actor['user']['account_id'], $ids)) {
            throw new NativeError('crypto_migration_contributor_unavailable', 409);
        }
        $content = [];
        $finance = [];
        $readableFinance = [];
        foreach ($ids as $id) {
            $scope = $this->scope($id, $actor['user']['id']);
            if ((int)$scope['owner_id'] === (int)$actor['user']['id']) {
                $content[] = $id;
            }
            $policy = (new NativeFinanceAccess($this->container))->policyForCrypto($id, $actor['user'], false, false);
            if ($policy['enabled'] && $policy['grant'] !== 'none') {
                // Private original intents remain actor-owned even when another
                // portion alone materializes the shared canonical finance rows.
                $readableFinance[] = $id;
                $owner = $this->one('SELECT account_id FROM familyhub_accounts WHERE user_id=?', [$scope['owner_id']]);
                if ($this->financeMaterializer($id, $owner['account_id'] ?? null) === $actor['user']['account_id']) {
                    $finance[] = $id;
                }
            }
        }
        $result = [];
        $add = function ($table, $domain, $where, $params) use (&$result) {
            $columns = explode(',', self::COLUMNS[$table]);
            $columns = array_values(array_diff($columns, self::SERVER_ONLY_COLUMNS[$table] ?? []));
            $result[$table.':'.$domain] = ['table' => $table, 'domain' => $domain, 'where' => $where, 'params' => $params, 'columns' => $columns];
        };
        $in = fn($values) => implode(',', array_fill(0, count($values), '?'));
        if ($content) {
            foreach (self::CONTENT as $table) {
                $column = $table === 'familyhub_scopes' ? 'id' : 'scope_id';
                $add($table, 'content', $column.' IN ('.$in($content).')', $content);
            }
            $add('familyhub_record_relocations', 'content', 'scope_id IN ('.$in($content).') AND finance=0', $content);
            $add('familyhub_personal_scopes','content','scope_id IN ('.$in($content).') AND account_id=?',array_merge($content,[$actor['user']['account_id']]));
        }
        if ($finance) {
            foreach (self::FINANCE as $table) {
                $add($table, 'finance', 'scope_id IN ('.$in($finance).')', $finance);
            }
            $add('familyhub_record_relocations', 'finance', 'scope_id IN ('.$in($finance).') AND finance=1', $finance);
        }
        foreach (self::PRIVATE_ACCOUNT as $table => $column) {
            $scoped = $table === 'familyhub_finance_operations' ? $readableFinance : $ids;
            if ($scoped) {
                $add($table, 'private', 'scope_id IN ('.$in($scoped).') AND '.$column.'=?', array_merge($scoped, [$actor['user']['account_id']]));
            }
        }
        $add('familyhub_operations', 'private', 'scope_id IN ('.$in($ids).') AND user_id=?', array_merge($ids, [$actor['user']['id']]));
        $add('familyhub_inbox_state', 'private', 'account_id=?', [$actor['user']['account_id']]);
        $captureObservation = $this->one('SELECT private_inbox_baseline FROM familyhub_crypto_captures_v3 WHERE migration_id=? AND account_id=?',
            [$migration['id'],$actor['user']['account_id']]);
        if ($captureObservation) {
            if ($captureObservation['private_inbox_baseline'] === null) throw new NativeError('crypto_capture_generation_conflict',409);
            $snapshot = NativeCryptoCaptureInboxStateV3::prepared($actor['user']['account_id'],
                json_decode($captureObservation['private_inbox_baseline'],true,16,JSON_THROW_ON_ERROR));
            $selection = &$result['familyhub_inbox_state:private'];
            $selection['baselineAccount'] = $actor['user']['account_id'];
            if ($snapshot === null) $selection['privateBaselineAbsent'] = true;
            else $selection['privateBaseline'] = NativeCryptoCodec::canonical($snapshot);
            unset($selection);
            $bound = $this->one("SELECT private_baseline FROM familyhub_crypto_capture_sources_v3 WHERE migration_id=? AND account_id=? AND source_table='familyhub_inbox_state' AND domain='private'",
                [$migration['id'],$actor['user']['account_id']]);
            if ($bound && ($snapshot === null || $bound['private_baseline'] !== NativeCryptoCodec::canonical($snapshot))) {
                throw new NativeError('crypto_capture_inbox_state_snapshot',409);
            }
        }
        // Active invitations and queued notification effects need canonical
        // cutover adapters. Their exact private rows must exist in the frozen
        // capture first; a component digest alone is not recoverable coverage.
        if ($content) {
            $add('familyhub_invitations', 'private', 'scope_id IN ('.$in($content).')', $content);
            // Numeric Kanboard project invitations belong to the separate
            // familyHub*ProjectInvitation RPCs, not native UUID scope content.
            $add('familyhub_invitation_mail', 'private', 'invitation_id IN (SELECT id FROM familyhub_invitations WHERE scope_id IN ('.$in($content).'))', $content);
        }
        $ownInbox = 'inbox_id IN (SELECT id FROM familyhub_inbox WHERE scope_id IN ('.$in($ids).') AND recipient_account_id=?)';
        $inboxArgs = array_merge($ids,[$actor['user']['account_id']]);
        $add('familyhub_deliveries','private',$ownInbox,$inboxArgs);
        $add('familyhub_push_jobs','private',$ownInbox,$inboxArgs);
        $add('familyhub_idea_report_assets', 'private', 'report_id IN (SELECT id FROM familyhub_moderation_reports WHERE reporter_account_id=? AND scope_id IN ('.$in($ids).'))', array_merge([$actor['user']['account_id']], $ids));
        ksort($result, SORT_STRING);
        return $result;
    }

    private function rawRows($selection, $offset = null, $limit = null)
    {
        if (isset($selection['privateBaselineAbsent'])) {
            if ($selection['table'] !== 'familyhub_inbox_state') throw new NativeError('crypto_capture_inbox_state_snapshot',409);
            unset($selection['privateBaselineAbsent']);
            foreach ($this->rawRows($selection,$offset,$limit) as $current) {
                NativeCryptoCaptureInboxStateV3::snapshot($selection['baselineAccount'],$current,$current);
            }
            return; // A later global row never broadens this captured selection.
        }
        if (isset($selection['privateBaseline'])) {
            if ($selection['table'] !== 'familyhub_inbox_state') throw new NativeError('crypto_capture_inbox_state_snapshot',409);
            $baseline = (object)json_decode($selection['privateBaseline'],true,16,JSON_THROW_ON_ERROR);
            unset($selection['privateBaseline']);
            $seen = 0;
            foreach ($this->rawRows($selection,$offset,$limit) as $current) {
                if (++$seen !== 1) throw new NativeError('crypto_capture_inbox_state_snapshot',409);
                yield NativeCryptoCaptureInboxStateV3::snapshot($selection['baselineAccount'],$current,$baseline);
            }
            // A missing live row cannot authorize absence or counter rollback.
            if ($seen === 0 && ($offset === null || $offset === 0)) throw new NativeError('crypto_capture_inbox_state_conflict',409);
            return;
        }
        $table = $selection['table'];
        $columns = $selection['columns'];
        $types = [];
        $schema = $this->sqlite ? $this->many('PRAGMA table_info('.$table.')') : $this->many('SHOW COLUMNS FROM '.$table);
        $primary = [];
        foreach ($schema as $column) {
            $name = $column[$this->sqlite ? 'name' : 'Field'];
            $types[$name] = $column[$this->sqlite ? 'type' : 'Type'];
            if ($this->sqlite ? (int)$column['pk'] > 0 : $column['Key'] === 'PRI') {
                $primary[] = $name;
            }
        }
        if (!$primary) {
            throw new NativeError('crypto_migration_schema_unsupported', 409);
        }
        $select = $columns;
        if ($this->sqlite) {
            foreach ($columns as $index => $column) {
                $select[] = 'typeof('.$column.') AS crypto_type_'.$index;
            }
        }
        $sql = 'SELECT '.implode(',', $select).' FROM '.$table.' WHERE '.$selection['where'].' ORDER BY '.implode(',', $primary);
        if ($offset !== null) {
            $sql .= ' LIMIT '.(int)$limit.' OFFSET '.(int)$offset;
        }
        foreach ($this->iterate($sql, $selection['params']) as $row) {
            $cells = [];
            foreach ($columns as $index => $column) {
                $type = $this->sqlite ? $row['crypto_type_'.$index] : $types[$column];
                $value = $row[$column];
                $floating = $this->sqlite ? $type === 'real' : (bool)preg_match('/^(?:float|double|real)(?:\(|$)/i', $type);
                if (!$this->sqlite && preg_match('/^(?:decimal|numeric)(?:\(|$)/i', $type) && is_float($value)) {
                    throw new NativeError('crypto_migration_numeric_precision_unavailable', 409);
                }
                $bytes = $value === null ? null : ($floating ? pack('E', (float)$value) : (string)$value);
                $cells[$column] = ['type' => $type, 'valueBase64' => $bytes === null ? null : base64_encode($bytes)];
            }
            ksort($cells, SORT_STRING);
            yield (object)$cells;
        }
    }

    private function ownInventory($migration, $actor)
    {
        $tables = [];
        foreach ($this->selections($migration, $actor) as $key => $selection) {
            $hash = hash_init('sha256');
            $count = 0;
            $bytes = 0;
            foreach ($this->rawRows($selection) as $row) {
                $encoded = NativeCryptoCodec::canonical($row)."\n";
                hash_update($hash, $encoded);
                $bytes += strlen($encoded);
                $count++;
            }
            $tables[$key] = ['table' => $selection['table'], 'domain' => $selection['domain'], 'columns' => $selection['columns'], 'rows' => $count, 'bytes' => $bytes, 'sha256' => hash_final($hash)];
        }
        $owned = $this->discovery($this->component(json_decode($migration['scope_ids'], true, 34, JSON_THROW_ON_ERROR)[0]), $actor)['ownedScopeIds'];
        $budgets = [];
        foreach ($this->selections($migration, $actor) as $selection) {
            if (!in_array($selection['domain'], ['content', 'finance'], true)) {
                continue;
            }
            $scopeColumn = $selection['table'] === 'familyhub_scopes' ? 'id' : 'scope_id';
            foreach (json_decode($migration['scope_ids'], true, 34, JSON_THROW_ON_ERROR) as $scopeId) {
                $scoped = $selection;
                $scoped['where'] = '('.$selection['where'].') AND '.$scopeColumn.'=?';
                $scoped['params'][] = $scopeId;
                $bytes = 0;
                $objects = 0;
                foreach ($this->rawRows($scoped) as $row) {
                    $bytes += strlen(NativeCryptoCodec::canonical($row)) + 1;
                    $objects++;
                }
                if (!$objects) {
                    continue;
                }
                $domain = $selection['domain'];
                $old = $budgets[$scopeId][$domain] ?? ['bytes' => 0, 'objects' => 0];
                $budgets[$scopeId][$domain] = ['bytes' => $old['bytes'] + (int)ceil($bytes * 1.25) + $objects * 4096,
                    'objects' => $old['objects'] + $objects];
            }
        }
        $files = (new NativeCryptoFileInventory($this->container))->collect($owned);
        foreach (get_object_vars($files) as $scopeId => $summary) {
            $old = $budgets[$scopeId]['content'] ?? ['bytes' => 0, 'objects' => 0];
            $budgets[$scopeId]['content'] = ['bytes' => $old['bytes'] + (int)ceil($summary['bytes'] * 1.01) + $summary['files'] * 4096,
                'objects' => $old['objects'] + $summary['files']];
        }
        return [
            'format' => 2, 'serverId' => $this->serverId(), 'accountId' => $actor['user']['account_id'],
            'componentId' => $migration['component_id'], 'componentHash' => $migration['component_hash'],
            'tables' => (object)$tables, 'files' => $files, 'budgets' => (object)$budgets,
            'fileCoverage' => 'sql-associated-live-and-retired',
            'secretCoverage' => 'server-auth-smtp-fcm-retained-never-exported',
        ];
    }

    /** Original source allowance is shared once, never multiplied per uploader.
     * These are server-computed, fenced inventories, retained after retirement.
     */
    public function blobAllowance($scopeId, $domain, $actor)
    {
        $this->scope($this->uuid($scopeId), $actor['user']['id']);
        if (!in_array($domain, ['content', 'finance'], true)) {
            throw new NativeError('validation_error');
        }
        if ($domain === 'finance') {
            (new NativeFinanceAccess($this->container))->policyForCrypto($scopeId, $actor['user']);
        }
        $state = $this->one('SELECT migration_id FROM familyhub_crypto_scopes WHERE scope_id=?', [$scopeId]);
        $migration = $state && $state['migration_id'] ? $this->one("SELECT id FROM familyhub_crypto_migrations_v2 WHERE id=? AND state IN ('fenced','verified','committed','retired')", [$state['migration_id']]) : null;
        $allowance = ['bytes' => 0, 'objects' => 0];
        if (!$migration) {
            return $allowance;
        }
        foreach ($this->many("SELECT inventory FROM familyhub_crypto_migration_portions_v2 WHERE migration_id=? AND state IN ('fenced','verified')", [$migration['id']]) as $portion) {
            $inventory = json_decode($portion['inventory'], true, 128, JSON_THROW_ON_ERROR);
            $budget = $inventory['budgets'][$scopeId][$domain] ?? null;
            if ($budget) {
                $allowance['bytes'] = max($allowance['bytes'], $budget['bytes']);
                $allowance['objects'] = max($allowance['objects'], $budget['objects']);
            }
        }
        return $allowance;
    }

    public function blobAccountAllowance($actor)
    {
        $budgets = [];
        foreach ($this->many("SELECT p.inventory FROM familyhub_crypto_migration_portions_v2 p JOIN familyhub_crypto_migrations_v2 m ON m.id=p.migration_id WHERE p.account_id=? AND p.state IN ('fenced','verified') AND m.state IN ('fenced','verified','committed','retired')", [$actor['user']['account_id']]) as $portion) {
            $inventory = json_decode($portion['inventory'], true, 128, JSON_THROW_ON_ERROR);
            foreach ($inventory['budgets'] ?? [] as $scopeId => $domains) {
                foreach ($domains as $domain => $value) {
                    $key = $scopeId.':'.$domain;
                    $old = $budgets[$key] ?? ['bytes' => 0, 'objects' => 0];
                    $budgets[$key] = ['bytes' => max($old['bytes'], $value['bytes']),
                        'objects' => max($old['objects'], $value['objects'])];
                }
            }
        }
        $result = ['bytes' => 0, 'objects' => 0];
        foreach ($budgets as $value) {
            $result['bytes'] += $value['bytes'];
            $result['objects'] += $value['objects'];
        }
        return $result;
    }

    private function exportPage($params, $migration, $portion, $inventory, $actor, $preparingCapture = false)
    {
        $states = $preparingCapture ? ['preparing', 'fenced', 'verified'] : ['fenced', 'verified'];
        if (!in_array($migration['state'], $states, true) || !in_array($portion['state'], $states, true)) {
            throw new NativeError('crypto_migration_not_fenced', 409);
        }
        if (!is_string($params['table']) || !is_string($params['domain']) ||
            !is_int($params['cursor']) || $params['cursor'] < 0 ||
            !is_int($params['limit']) || $params['limit'] < 1 || $params['limit'] > 20) {
            throw new NativeError('validation_error');
        }
        $key = $params['table'].':'.$params['domain'];
        $selections = $this->selections($migration, $actor);
        if (!isset($selections[$key])) {
            throw new NativeError('crypto_migration_export_forbidden', 403);
        }
        $currentHash = self::inventoryHash((object)$inventory);
        if ($currentHash !== $portion['inventory_hash']) {
            throw new NativeError('crypto_inventory_changed', 409);
        }
        $rows = [];
        $bytes = 0;
        foreach ($this->rawRows($selections[$key], $params['cursor'], $params['limit'] + 1) as $row) {
            // Large former records remain migratable. Pages carry bounded
            // references; exportCell returns their exact typed bytes in chunks.
            foreach (get_object_vars($row) as $column => $cell) {
                if ($cell['valueBase64'] !== null && strlen($cell['valueBase64']) > 32768) {
                    $raw = base64_decode($cell['valueBase64'], true);
                    $row->{$column} = ['type' => $cell['type'], 'external' => [
                        'rowCursor' => $params['cursor'] + count($rows), 'column' => $column,
                        'size' => strlen($raw), 'sha256' => hash('sha256', $raw),
                    ]];
                }
            }
            $size = strlen(self::inventoryCanonical($row));
            if (count($rows) >= $params['limit'] || $rows && $bytes + $size > 1048576) {
                break;
            }
            // An old supported document must not be silently skipped. Large
            // raw cells require bounded byte export, handled by exportCell.
            if ($size > 1048576) {
                throw new NativeError('crypto_migration_large_cell_required', 409);
            }
            $rows[] = $row;
            $bytes += $size;
        }
        $next = $params['cursor'] + count($rows);
        return ['migrationId' => $migration['id'], 'inventoryHash' => $currentHash, 'table' => $params['table'], 'domain' => $params['domain'], 'rows' => $rows, 'cursor' => $next, 'hasMore' => $next < ((array)$inventory['tables']->{$key})['rows']];
    }

    private function exportCell($params, $migration, $portion, $inventory, $actor, $preparingCapture = false)
    {
        $states = $preparingCapture ? ['preparing', 'fenced', 'verified'] : ['fenced', 'verified'];
        if (!in_array($migration['state'], $states, true) || !in_array($portion['state'], $states, true)) {
            throw new NativeError('crypto_migration_not_fenced', 409);
        }
        if (!is_string($params['table']) || !is_string($params['domain']) || !is_string($params['column']) ||
            !is_int($params['cursor']) || $params['cursor'] < 0 || !is_int($params['offset']) || $params['offset'] < 0 ||
            !is_int($params['limit']) || $params['limit'] < 1 || $params['limit'] > 196608) {
            throw new NativeError('validation_error');
        }
        $key = $params['table'].':'.$params['domain'];
        $selections = $this->selections($migration, $actor);
        if (!isset($selections[$key]) || !in_array($params['column'], $selections[$key]['columns'], true)) {
            throw new NativeError('crypto_migration_export_forbidden', 403);
        }
        $hash = self::inventoryHash((object)$inventory);
        if ($hash !== $portion['inventory_hash']) {
            throw new NativeError('crypto_inventory_changed', 409);
        }
        $row = null;
        foreach ($this->rawRows($selections[$key], $params['cursor'], 1) as $value) {
            $row = $value;
        }
        if ($row === null || $row->{$params['column']}['valueBase64'] === null) {
            throw new NativeError('crypto_migration_cell_missing', 404);
        }
        $cell = $row->{$params['column']};
        $raw = base64_decode($cell['valueBase64'], true);
        if ($params['offset'] > strlen($raw)) {
            throw new NativeError('invalid_cursor');
        }
        $chunk = substr($raw, $params['offset'], $params['limit']);
        return ['migrationId' => $migration['id'], 'inventoryHash' => $hash, 'table' => $params['table'],
            'domain' => $params['domain'], 'rowCursor' => $params['cursor'], 'column' => $params['column'],
            'type' => $cell['type'], 'offset' => $params['offset'], 'nextOffset' => $params['offset'] + strlen($chunk),
            'size' => strlen($raw), 'sha256' => hash('sha256', $raw), 'dataBase64' => base64_encode($chunk)];
    }

    private function fence($params, $migration, $portion, $actor, $proof)
    {
        if (!in_array($migration['state'], ['preparing', 'fenced'], true)) {
            throw new NativeError('crypto_migration_state', 409);
        }
        $inventory = $this->ownInventory($migration, $actor);
        $hash = self::inventoryHash((object)$inventory);
        if ($params['inventoryHash'] !== $hash) {
            throw new NativeError('crypto_inventory_changed', 409);
        }
        $this->change("UPDATE familyhub_crypto_migration_portions_v2 SET inventory=?,inventory_hash=?,state='fenced',verification=NULL,authorization=? WHERE migration_id=? AND account_id=?", [
            self::inventoryCanonical((object)$inventory), $hash,
            json_encode($proof, JSON_THROW_ON_ERROR), $migration['id'], $actor['user']['account_id'],
        ]);
        $pending = $this->one("SELECT COUNT(*) AS n FROM familyhub_crypto_migration_portions_v2 WHERE migration_id=? AND state NOT IN ('fenced','verified')", [$migration['id']]);
        if ((int)$pending['n'] === 0 && $migration['state'] === 'preparing') {
            // Every owner/private contributor has consented. Recheck all signed
            // snapshots now, before placing a global write fence on the graph.
            foreach ($this->many('SELECT * FROM familyhub_crypto_migration_portions_v2 WHERE migration_id=? ORDER BY account_id', [$migration['id']]) as $candidate) {
                $user = $this->one('SELECT u.*,a.account_id FROM users u JOIN familyhub_accounts a ON a.user_id=u.id WHERE a.account_id=? AND u.is_active=1', [$candidate['account_id']]);
                if (!$user || self::inventoryHash((object)$this->ownInventory($migration, ['user' => $user])) !== $candidate['inventory_hash']) {
                    throw new NativeError('crypto_migration_contribution_changed', 409);
                }
            }
            foreach (json_decode($migration['scope_ids'], true, 34, JSON_THROW_ON_ERROR) as $scopeId) {
                if (($params['captureVersion'] ?? null) !== 3) {
                    $this->indexLegacyReceipts($scopeId, $migration['id']);
                }
                $state = $this->one('SELECT * FROM familyhub_crypto_scopes WHERE scope_id=?', [$scopeId]);
                if ($state && !in_array($state['state'], ['staged', 'preparing'], true)) {
                    throw new NativeError('crypto_migration_busy', 409);
                }
                if ($state) {
                    $this->change("UPDATE familyhub_crypto_scopes SET state='fenced',migration_id=? WHERE scope_id=?", [$migration['id'], $scopeId]);
                } else {
                    $scope = $this->one('SELECT access_revision FROM familyhub_scopes WHERE id=?', [$scopeId]);
                    $this->change("INSERT INTO familyhub_crypto_scopes(scope_id,epoch,sequence,access_revision,state,migration_id) VALUES(?,1,0,?,'fenced',?)", [$scopeId, $scope['access_revision'], $migration['id']]);
                }
            }
            $this->change("UPDATE familyhub_crypto_migrations_v2 SET state='fenced',updated_at=? WHERE id=?", [time(), $migration['id']]);
            $migration['state'] = 'fenced';
        }
        $portion['state'] = 'fenced';
        $portion['inventory_hash'] = $hash;
        return $this->status($migration, $portion);
    }

    /** Ciphertext staging is account-private, never a shared scope blob. */
    private function archiveAccess($migration, $portion, $actor, $read = false)
    {
        // Finished private archives belong to the authenticated account, not to
        // the retired legacy scope membership graph. migration() already binds
        // this immutable portion to exactly that account.
        if ($read && in_array($migration['state'], ['committed', 'retired'], true) &&
            in_array($portion['state'], ['verified','committed'], true)) {
            return;
        }
        if (!in_array($migration['state'], ['fenced', 'verified'], true) ||
            !in_array($portion['state'], ['fenced', 'verified'], true)) {
            throw new NativeError('crypto_migration_not_fenced', 409);
        }
        $ids = json_decode($portion['scope_ids'], true, 34, JSON_THROW_ON_ERROR);
        if (!$this->contributorAvailable($actor['user']['account_id'], $ids)) {
            throw new NativeError('crypto_migration_contributor_unavailable', 409);
        }
    }

    /** Quota is derived from the server's consented typed inventory, not flags. */
    private function archiveAllowance($portion)
    {
        $inventory = json_decode($portion['inventory'], true, 128, JSON_THROW_ON_ERROR);
        $bytes = 2097152;
        foreach ($inventory['tables'] as $table) {
            // Raw cells are base64 framed. Leave explicit framing headroom for
            // type/column names and authenticated stream headers per segment.
            $bytes += (int)ceil($table['bytes'] * 1.5) + $table['rows'] * 2048;
        }
        foreach ($inventory['files'] as $files) {
            $bytes += (int)ceil($files['bytes'] * 1.5) + $files['files'] * 8192;
        }
        if (!is_int($bytes) || $bytes < 0) {
            throw new NativeError('crypto_migration_inventory_overflow', 409);
        }
        return $bytes;
    }

    private function archiveRow($migration, $actor, $id)
    {
        $row = $this->one('SELECT * FROM familyhub_crypto_migration_archives_v2 WHERE migration_id=? AND account_id=? AND id=?', [
            $migration['id'], $actor['user']['account_id'], $this->uuid($id),
        ]);
        if (!$row) {
            throw new NativeError('crypto_migration_archive_missing', 404);
        }
        return $row;
    }

    private function archiveStatus($row)
    {
        return ['id' => $row['id'], 'size' => (int)$row['size'], 'sha256' => $row['sha256'],
            'received' => (int)$row['received'], 'complete' => (int)$row['complete'] === 1];
    }

    /** Closed account-private snapshot namespace; no live work is installed. */
    private function localArtifactDescription($description,$params,$migration,$actor)
    {
        $d = $description['artifact'];
        $this->fields($d,['context','manifest','intentCount']);
        if (!is_int($d['intentCount']) || $d['intentCount'] < 0 || $d['intentCount'] > 9007199254740991) throw new NativeError('crypto_receipts_count',409);
        $c = $d['context'];
        $this->fields($c,['version','serverId','migrationId','captureId','accountId','sourceInventoryRoot','artifactId','purpose']);
        $capture=$this->captureRow($migration,$actor);
        $this->uuid($c['artifactId']);
        if ($capture['state'] !== 'sealed' || $c['version']!==3 || $c['serverId']!==$this->serverId()
            || $c['migrationId']!==$migration['id'] || $c['captureId']!==$capture['capture_id']
            || $c['accountId']!==$actor['user']['account_id'] || $c['sourceInventoryRoot']!==$capture['inventory_root']
            || $c['purpose']!=='migrationLocalIntents') throw new NativeError('crypto_local_artifact_context',409);
        $m=$d['manifest'];
        $this->fields($m,['migrationId','keyId','segments','cipherManifestHash','artifactId','artifactKind','artifactContext']);
        if ($m['migrationId']!==$migration['id'] || $m['keyId']!==$description['keyId']
            || $m['artifactId']!==$c['artifactId'] || $m['artifactKind']!=='migrationLocalIntentsV3'
            || NativeCryptoCodec::canonical((object)$m['artifactContext'])!==NativeCryptoCodec::canonical((object)$c)
            || $m['cipherManifestHash']!==$description['cipherManifestHash']
            || !is_array($m['segments']) || !array_is_list($m['segments']) || count($m['segments'])<1 || count($m['segments'])>16
            || hash('sha256',NativeCryptoCodec::canonical($m['segments']))!==$m['cipherManifestHash']) throw new NativeError('crypto_local_artifact_manifest',409);
        $seen=[];$total=0;$selected=null;
        foreach($m['segments'] as $i=>$segment){
            $this->fields($segment,['id','index','size','sha256']);$this->uuid($segment['id']);$this->digest($segment['sha256']);
            if ($segment['index']!==$i || !is_int($segment['size']) || $segment['size']<41 || $segment['size']>22*1024*1024 || isset($seen[$segment['id']])) throw new NativeError('crypto_local_artifact_manifest',409);
            $seen[$segment['id']]=true;$total+=$segment['size'];
            if ($description['index']===$i) $selected=$segment;
        }
        if ($total>256*1024*1024 || !$selected || $selected['id']!==$params['id'] || $selected['size']!==$params['size'] || $selected['sha256']!==$params['sha256']) throw new NativeError('crypto_local_artifact_manifest',409);
    }

    private function archiveWrite($operation, $params, $migration, $portion, $actor, $proof)
    {
        $this->archiveAccess($migration, $portion, $actor);
        $id = $this->uuid($params['id']);
        $key = [$migration['id'], $actor['user']['account_id'], $id];
        if ($operation === 'crypto2.migration.archiveBegin') {
            $this->digest($params['sha256']);
            if (!is_int($params['size']) || $params['size'] < 41 || $params['size'] > self::MAX_ARCHIVE) {
                throw new NativeError('crypto_migration_archive_size');
            }
            $manifest = NativeCryptoCodec::base64($params['manifestBase64'], 16384);
            try {
                $description = json_decode($manifest, true, 16, JSON_THROW_ON_ERROR);
            } catch (\JsonException $error) {
                throw new NativeError('crypto_migration_archive_manifest');
            }
            if (!is_array($description)) {
                throw new NativeError('crypto_migration_archive_manifest');
            }
            $localArtifact = ($description['artifactKind'] ?? null) === 'migrationLocalIntentsV3';
            $this->fields($description, $localArtifact
                ? ['version','keyId','cipherManifestHash','index','artifactKind','artifact']
                : ['version','keyId','cipherManifestHash','index']);
            if ($localArtifact) $this->localArtifactDescription($description,$params,$migration,$actor);
            $this->uuid($description['keyId']);
            $this->digest($description['cipherManifestHash']);
            $captureVersion = $this->one('SELECT capture_id FROM familyhub_crypto_captures_v3 WHERE migration_id=? AND account_id=?',
                [$migration['id'], $actor['user']['account_id']]) ? 3 : 2;
            if ($description['version'] !== $captureVersion || !is_int($description['index']) || $description['index'] < 0 ||
                self::inventoryCanonical((object)$description) !== $manifest) {
                throw new NativeError('crypto_migration_archive_manifest');
            }
            $existing = $this->one('SELECT * FROM familyhub_crypto_migration_archives_v2 WHERE migration_id=? AND account_id=? AND id=?', $key);
            if ($existing) {
                if ((int)$existing['size'] !== $params['size'] || $existing['sha256'] !== $params['sha256'] ||
                    $existing['manifest'] !== $manifest) {
                    throw new NativeError('idempotency_mismatch', 409);
                }
                return $this->archiveStatus($existing);
            }
            $used = 0;
            foreach ($this->iterate('SELECT size,manifest FROM familyhub_crypto_migration_archives_v2 WHERE migration_id=? AND account_id=?',array_slice($key,0,2)) as $charged) {
                $kind = json_decode($charged['manifest'],true,64,JSON_THROW_ON_ERROR)['artifactKind'] ?? null;
                if (($kind === 'migrationLocalIntentsV3') === $localArtifact) $used += (int)$charged['size'];
            }
            if ($used + $params['size'] > ($localArtifact ? 256*1024*1024 : $this->archiveAllowance($portion))) {
                throw new NativeError('crypto_migration_archive_quota', 409);
            }
            $this->change('INSERT INTO familyhub_crypto_migration_archives_v2(migration_id,account_id,id,size,sha256,received,complete,manifest,authorization) VALUES(?,?,?,?,?,0,0,?,?)', [
                ...$key, $params['size'], $params['sha256'], $manifest, json_encode($proof, JSON_THROW_ON_ERROR),
            ]);
            return $this->archiveStatus($this->archiveRow($migration, $actor, $id));
        }
        $row = $this->archiveRow($migration, $actor, $id);
        if ($operation === 'crypto2.migration.archiveChunk') {
            if (!is_int($params['offset']) || $params['offset'] < 0) {
                throw new NativeError('invalid_cursor');
            }
            $bytes = NativeCryptoCodec::base64($params['dataBase64'], self::ARCHIVE_CHUNK);
            if (!$bytes || $params['offset'] + strlen($bytes) > (int)$row['size']) {
                throw new NativeError('crypto_migration_archive_size');
            }
            $old = $this->one('SELECT data FROM familyhub_crypto_migration_archive_chunks_v2 WHERE migration_id=? AND account_id=? AND archive_id=? AND chunk_offset=?', [...$key, $params['offset']]);
            if ($old) {
                if (!hash_equals($old['data'], $params['dataBase64'])) {
                    throw new NativeError('idempotency_mismatch', 409);
                }
                return $this->archiveStatus($row);
            }
            if ((int)$row['complete'] !== 0 || $params['offset'] !== (int)$row['received']) {
                throw new NativeError('invalid_cursor', 409);
            }
            $this->change('INSERT INTO familyhub_crypto_migration_archive_chunks_v2(migration_id,account_id,archive_id,chunk_offset,data) VALUES(?,?,?,?,?)', [...$key, $params['offset'], $params['dataBase64']]);
            $this->change('UPDATE familyhub_crypto_migration_archives_v2 SET received=? WHERE migration_id=? AND account_id=? AND id=?', [
                $params['offset'] + strlen($bytes), ...$key,
            ]);
            return $this->archiveStatus($this->archiveRow($migration, $actor, $id));
        }
        if ((int)$row['received'] !== (int)$row['size']) {
            throw new NativeError('crypto_migration_archive_incomplete', 409);
        }
        $hash = hash_init('sha256');
        $offset = 0;
        foreach ($this->iterate('SELECT chunk_offset,data FROM familyhub_crypto_migration_archive_chunks_v2 WHERE migration_id=? AND account_id=? AND archive_id=? ORDER BY chunk_offset', $key) as $chunk) {
            $bytes = NativeCryptoCodec::base64($chunk['data'], self::ARCHIVE_CHUNK);
            if ((int)$chunk['chunk_offset'] !== $offset) {
                throw new NativeError('crypto_migration_archive_incomplete', 409);
            }
            hash_update($hash, $bytes);
            $offset += strlen($bytes);
        }
        if ($offset !== (int)$row['size'] || !hash_equals($row['sha256'], hash_final($hash))) {
            throw new NativeError('crypto_migration_archive_integrity', 409);
        }
        $this->change('UPDATE familyhub_crypto_migration_archives_v2 SET complete=1 WHERE migration_id=? AND account_id=? AND id=?', $key);
        return $this->archiveStatus($this->archiveRow($migration, $actor, $id));
    }

    private function archiveGet($params, $migration, $portion, $actor)
    {
        $this->archiveAccess($migration, $portion, $actor, true);
        if (!is_int($params['offset']) || $params['offset'] < 0) {
            throw new NativeError('invalid_cursor');
        }
        $row = $this->archiveRow($migration, $actor, $params['id']);
        $result = $this->archiveStatus($row);
        $result['manifestBase64'] = base64_encode($row['manifest']);
        $result['authorization'] = json_decode($row['authorization'], true, 32, JSON_THROW_ON_ERROR);
        $result['offset'] = $params['offset'];
        $result['dataBase64'] = '';
        $result['nextOffset'] = $params['offset'];
        if ($params['offset'] > (int)$row['received']) {
            throw new NativeError('invalid_cursor');
        }
        if ($params['offset'] < (int)$row['received']) {
            $chunk = $this->one('SELECT data FROM familyhub_crypto_migration_archive_chunks_v2 WHERE migration_id=? AND account_id=? AND archive_id=? AND chunk_offset=?', [
                $migration['id'], $actor['user']['account_id'], $row['id'], $params['offset'],
            ]);
            if (!$chunk) {
                throw new NativeError('invalid_cursor');
            }
            $result['dataBase64'] = $chunk['data'];
            $result['nextOffset'] += strlen(NativeCryptoCodec::base64($chunk['data'], self::ARCHIVE_CHUNK));
        }
        return $result;
    }

    /** Privacy3 exact public cold attestation. No caller-supplied frames. */
    private function verifyCapture3($params,$actor,$proof)
    {
        $this->fields($params,['header','summary','localIntent']);
        $h=$params['header'];
        [$migration,$portion]=$this->migration($h['migrationId']??null,$actor);
        $this->archiveAccess($migration,$portion,$actor);$this->unchanged($migration);
        $capture=$this->captureRow($migration,$actor);$component=$this->captureCommitments($migration);
        if($capture['state']!=='sealed' || ($h['captureId']??null)!==$capture['capture_id'] || ($h['componentId']??null)!==$migration['component_id']
            || ($h['componentCommitment']??null)!==$component['componentCommitment'] || ($h['accountId']??null)!==$actor['user']['account_id']
            || ($h['serverId']??null)!==$this->serverId() || ($h['sourceInventoryRoot']??null)!==$capture['inventory_root'] || ($h['sourceCount']??null)!==(int)$capture['source_count']) throw new NativeError('crypto_business_parity_context',409);
        $common=['version'=>3,'serverId'=>$this->serverId(),'migrationId'=>$migration['id'],'captureId'=>$capture['capture_id'],'accountId'=>$actor['user']['account_id'],'sourceInventoryRoot'=>$capture['inventory_root']];
        $this->businessArchive($migration,$actor,$h['archiveManifestHash']??null);
        $structure=new NativeCryptoMigrationStructureV3($this->container,$this->bearer,$this->ip);
        $targets=[];$after=null;
        do{
            $p=['migrationId'=>$migration['id'],'captureId'=>$capture['capture_id'],'sourceInventoryRoot'=>$capture['inventory_root'],'limit'=>20];if($after!==null)$p['afterScopeId']=$after;
            $page=$structure->targets($p,$actor,[$this,'captureSourceBindings'],[$this,'stagedCaptureTarget']);
            foreach($page['targets'] as $target){$id=$target['scopeId'];if(isset($targets[$id]))throw new NativeError('crypto_migration_structure_order',409);$targets[$id]=array_intersect_key($target,array_flip(['membershipHeadHash','scopeMetadataWireId','scopeMetadataProofHash','lifecycleHash','contextProofHashes']));}
            $after=$page['nextAfterScopeId'];
        }while($page['hasMore']);
        $structures=$structure->verify($migration['id'],$capture['capture_id'],$capture['inventory_root'],$actor,[$this,'captureSourceBindings'],[$this,'captureSourceBinding'],[$this,'stagedCaptureTarget'],$targets,
            fn($sid,$headHash,$hashes,$contextActor,$purposes,$captureId,$root)=>(new NativeCryptoMigrationStructureContextV3($this->container,$this->bearer,$this->ip))->verify(
                $sid,$headHash,$hashes,$contextActor,$purposes,$captureId,$root,[$this,'captureSourceBindings']));
        $notification=new NativeCryptoMigrationNotificationStageV3($this->container,$this->bearer,$this->ip);
        $notifications=$notification->stagedCoverage($migration['id'],$capture['capture_id'],$capture['inventory_root'],$actor,[$this,'captureSourceBindings']);
        $invitation=new NativeCryptoMigrationInvitationStageV3($this->container,$this->bearer,$this->ip);
        $invitations=$invitation->stagedCoverage($migration['id'],$capture['capture_id'],$capture['inventory_root'],$actor,[$this,'captureSourceBindings']);
        $audit=new NativeCryptoMigrationAuditV3($this->container,$this->bearer,$this->ip);
        $receipts=$this->businessReceipts($migration,$capture,$actor,$h,$params['localIntent']);
        $sections=[
            'audit'=>$audit->coverage($migration['id'],$capture['capture_id'],$capture['inventory_root'],$actor,[$this,'captureSourceBindings'],[$this,'captureSourceBinding']),
            'structure'=>NativeCryptoMigrationStructureV3::aggregate($common,$structures),
            'notifications'=>['kind'=>'notifications','count'=>$notifications['transformCount'],'root'=>$notifications['selectionRoot']],
            'invitations'=>['kind'=>'invitations','count'=>$invitations['bridgeCount'],'root'=>$invitations['selectionRoot']],
            'receipts'=>$receipts['section'],
        ];
        $summary=NativeCryptoMigrationParityFramesV3::compute($h,
            fn()=>$this->captureSourceBindings($migration['id'],$capture['capture_id'],$capture['inventory_root'],$actor,array_keys(self::COLUMNS)),
            fn($source,$bytes)=>$this->businessCanonical($migration,$capture,$actor,$source,$bytes),
            function($source,$adapter)use($migration,$capture,$actor,$structure,$structures,$notification,$invitation,$audit,$receipts){
                $id=$source['binding']['bindingId'];
                return match($adapter){
                    'canonicalFile'=>$this->businessIdeaFile($migration,$capture,$actor,$source,true),
                    'structure'=>$structure->bindingArtifact($migration['id'],$capture['capture_id'],$capture['inventory_root'],$id,$actor,[$this,'captureSourceBinding'],$structures),
                    'notification'=>$notification->bindingArtifact($migration['id'],$capture['capture_id'],$capture['inventory_root'],$id,$actor),
                    'invitation'=>$invitation->bindingArtifact($migration['id'],$capture['capture_id'],$capture['inventory_root'],$id,$actor),
                    'auditHistory'=>$audit->artifact(['migrationId'=>$migration['id'],'captureId'=>$capture['capture_id'],'sourceInventoryRoot'=>$capture['inventory_root'],'bindingId'=>$id],$actor,[$this,'captureSourceBinding'])['artifactHash'],
                    'immutableReceipt'=>$this->businessReceiptArtifact($migration,$actor,$source,$receipts['certificates']),
                    default=>throw new NativeError('crypto_business_parity_adapter_pending',409),
                };
            },$sections);
        if(self::inventoryCanonical((object)$summary)!==self::inventoryCanonical((object)$params['summary']))throw new NativeError('crypto_business_parity_mismatch',409);
        $v=['version'=>3,'header'=>$h,'summary'=>$summary,'sections'=>$sections,'authorization'=>$proof,'localIntent'=>$params['localIntent']];
        $this->change("UPDATE familyhub_crypto_migration_portions_v2 SET state='verified',verification=? WHERE migration_id=? AND account_id=?",[self::inventoryCanonical((object)$v),$migration['id'],$actor['user']['account_id']]);
        $portion['state']='verified';
        if((int)$this->one("SELECT COUNT(*) n FROM familyhub_crypto_migration_portions_v2 WHERE migration_id=? AND state<>'verified'",[$migration['id']])['n']===0){$this->change("UPDATE familyhub_crypto_migrations_v2 SET state='verified',updated_at=? WHERE id=?",[time(),$migration['id']]);$migration['state']='verified';}
        return ['version'=>3,'coldParityProofHash'=>NativeCryptoV2Codec::hash((object)$proof),'summary'=>$summary]+$this->captureStatus($migration,$portion,$capture);
    }

    private function businessArchive($migration,$actor,$root)
    {
        $this->digest($root);$segments=[];$key=null;
        // Inventory-derived quota bounds the number of segments; each row is
        // metadata only and each actual ciphertext is rehashed in bounded chunks.
        $after='';
        do{
            $page=$this->many('SELECT * FROM familyhub_crypto_migration_archives_v2 WHERE migration_id=? AND account_id=? AND id>? ORDER BY id LIMIT 20',[$migration['id'],$actor['user']['account_id'],$after]);
            foreach($page as $row){$after=$row['id'];$d=json_decode($row['manifest'],true,64,JSON_THROW_ON_ERROR);if(isset($d['artifactKind'])||$d['cipherManifestHash']!==$root)continue;
                if($key!==null&&$key!==$d['keyId']||isset($segments[$d['index']])||(int)$row['complete']!==1)throw new NativeError('crypto_migration_archive_incomplete',409);
                $key=$d['keyId'];$segments[$d['index']]=['id'=>$row['id'],'index'=>$d['index'],'size'=>(int)$row['size'],'sha256'=>$row['sha256']];
                $this->businessCipher($migration['id'],$row['id'],(int)$row['size'],$row['sha256'],true,$actor['user']['account_id']);
            }
        }while(count($page)===20);
        ksort($segments,SORT_NUMERIC);
        if(!$segments||array_keys($segments)!==range(0,count($segments)-1)||hash('sha256',NativeCryptoCodec::canonical(array_values($segments)))!==$root)throw new NativeError('crypto_migration_archive_integrity',409);
    }

    private function businessCipher($migrationId,$id,$size,$hash,$archive=false,$account=null)
    {
        $offset=0;$sink=hash_init('sha256');
        while($offset<$size){$row=$archive?$this->one('SELECT data FROM familyhub_crypto_migration_archive_chunks_v2 WHERE migration_id=? AND account_id=? AND archive_id=? AND chunk_offset=?',[$migrationId,$account,$id,$offset]):$this->one('SELECT data FROM familyhub_crypto_migration_blob_chunks_v2 WHERE migration_id=? AND blob_id=? AND chunk_offset=?',[$migrationId,$id,$offset]);
            if(!$row)throw new NativeError('crypto_migration_cipher_incomplete',409);$bytes=NativeCryptoCodec::base64($row['data'],self::ARCHIVE_CHUNK);if($bytes===''||$offset+strlen($bytes)>$size)throw new NativeError('crypto_migration_cipher_incomplete',409);hash_update($sink,$bytes);$offset+=strlen($bytes);
        }
        if($offset!==$size||hash_final($sink)!==$hash)throw new NativeError('crypto_migration_cipher_integrity',409);
    }

    private function businessCanonical($migration,$capture,$actor,$source,$bytes)
    {
        $resolved=$this->captureSourceBinding($migration['id'],$capture['capture_id'],$source['binding']['bindingId'],$actor);
        if($resolved['binding']!==$source['binding']||$resolved['context']!==$source['context'])throw new NativeError('crypto_business_parity_context',409);
        $context=$source['context'];$cells=get_object_vars($resolved['typedRow']);
        $column=match($context['sourceTable']){'familyhub_payment_events','familyhub_payment_projections'=>'event_id','familyhub_payment_cash'=>'movement_id',default=>'id'};
        $canonical=isset($cells[$column]['valueBase64'])?base64_decode($cells[$column]['valueBase64'],true):null;$this->uuid($canonical);
        $row=$this->one('SELECT * FROM familyhub_crypto_migration_stage_records_v2 WHERE migration_id=? AND source_table=? AND scope_id=? AND source_id=?',[$migration['id'],$context['sourceTable'],$context['scopeId'],$canonical]);
        if(!$row||$row['staged_by']!==$actor['user']['account_id']||$row['source_row_hash']!==hash('sha256',NativeCryptoCodec::canonical($resolved['typedRow'])))throw new NativeError('crypto_migration_canonical_coverage_pending',409);
        $recordProof=json_decode($row['record_proof'],true,34,JSON_THROW_ON_ERROR);[$record]=NativeCryptoCodec::decode($recordProof);
        $batch=$this->one('SELECT authorization FROM familyhub_crypto_migration_stage_batches_v2 WHERE migration_id=? AND batch_id=?',[$migration['id'],$record['batchId']]);if(!$batch)throw new NativeError('crypto_migration_stage_unavailable',503);
        $stage=json_decode($batch['authorization'],true,64,JSON_THROW_ON_ERROR);[$command,$raw,$signature]=NativeCryptoCodec::decode($stage);
        $directory=new NativeCryptoDirectoryV2($this->container,$this->bearer,$this->ip);$key=NativeCryptoMigrationGenerationV3::retainedSigningKey($this->pdo,$stage,$actor['user']['account_id'])??$directory->authorizeContent($command,$directory->current($actor['user']['account_id']));NativeCryptoV2Codec::verify($raw,$signature,$key);
        $p=$command['payload'];if($command['operation']!=='crypto2.migration.recordsStage'||$command['accountId']!==$actor['user']['account_id']||($p['captureVersion']??null)!==3||$p['migrationId']!==$migration['id']||$p['captureId']!==$capture['capture_id']||$p['sourceInventoryRoot']!==$capture['inventory_root'])throw new NativeError('crypto_business_parity_context',409);
        $binding=null;foreach($p['sourceBindings'] as $candidate){if($candidate['bindingId']===$source['binding']['bindingId']){if($binding!==null)throw new NativeError('crypto_migration_source_binding',409);$binding=$candidate;}}
        if(!$binding||$binding['recordProofHash']!==$row['record_proof_hash']||$binding['wireId']!==$row['wire_id'])throw new NativeError('crypto_migration_source_binding',409);
        $entries=(new NativeCryptoRecordProofV2($this->container))->parseBatch($p['batch'],$command,$key);$by=[];foreach($entries as $entry)$by[$entry['recordProofHash']]=$entry;
        if(!isset($by[$binding['recordProofHash']]))throw new NativeError('crypto_migration_source_binding',409);
        (new NativeCryptoScopeV2($this->container,$this->bearer,$this->ip))->author($record['scopeId'],$record['membershipHeadHash'],$record['epoch'],$record['accessRevision'],$actor,$record['domain'],false);
        $captured=$this->one('SELECT * FROM familyhub_crypto_capture_sources_v3 WHERE migration_id=? AND account_id=? AND binding_id=?',[$migration['id'],$actor['user']['account_id'],$binding['bindingId']]);
        $this->validateCaptureWitness($binding,$captured,$capture,$migration,$actor,$by,$resolved['typedRow']);
        foreach($binding['objects'] as $object){$d=$object['blob'];$fileBinding=$binding;$fileBinding['bindingId']=$object['sourceBindingId'];$this->businessBlobBinding($migration,$capture,$actor,$fileBinding,$record,$d['id'],$object['kind']==='ideaAsset'?'ideaAsset':'canonicalPayload');if($bytes)$this->businessCipher($migration['id'],$d['id'],$d['cipherSize'],$d['cipherSha256']);}
        if($binding['witness']!==null)foreach($binding['witness']['segments'] as $segment){$this->businessBlobBinding($migration,$capture,$actor,$binding,$record,$segment['id'],'typedWitness');if($bytes)$this->businessCipher($migration['id'],$segment['id'],$segment['size'],$segment['sha256']);}
        return $binding;
    }

    private function businessBlobBinding($migration,$capture,$actor,$binding,$record,$id,$purpose)
    {
        $blob=$this->one('SELECT authorization FROM familyhub_crypto_migration_blobs_v2 WHERE migration_id=? AND id=?',[$migration['id'],$id]);if(!$blob)throw new NativeError('crypto_migration_blob_missing',409);
        $proof=json_decode($blob['authorization'],true,64,JSON_THROW_ON_ERROR);[$b,$raw,$signature]=NativeCryptoCodec::decode($proof);$p=$b['payload'];
        $expected=['captureVersion'=>3,'migrationId'=>$migration['id'],'captureId'=>$capture['capture_id'],'sourceInventoryRoot'=>$capture['inventory_root'],'bindingId'=>$binding['bindingId'],'scopeId'=>$record['scopeId'],'domain'=>$record['domain'],'epoch'=>$record['epoch'],'membershipHeadHash'=>$record['membershipHeadHash'],'accessRevision'=>$record['accessRevision'],'id'=>$id,'purpose'=>$purpose];
        if($b['operation']!=='crypto2.migration.blob.begin'||$b['accountId']!==$actor['user']['account_id'])throw new NativeError('crypto_migration_blob_binding',409);
        foreach($expected as $k=>$v)if(($p[$k]??null)!==$v)throw new NativeError('crypto_migration_blob_binding',409);
        $directory=new NativeCryptoDirectoryV2($this->container,$this->bearer,$this->ip);$key=NativeCryptoMigrationGenerationV3::retainedSigningKey($this->pdo,$proof,$actor['user']['account_id'])??$directory->authorizeContent($b,$directory->current($actor['user']['account_id']));NativeCryptoV2Codec::verify($raw,$signature,$key);
    }

    /** Exact complete signed receipt sets plus a distinct private local snapshot. */
    private function businessReceipts($migration,$capture,$actor,$header,$local)
    {
        $this->fields($local,['descriptor','eventAuthorization']);$d=$local['descriptor'];$this->fields($d,['context','manifest','intentCount']);
        $manifest=$d['manifest'];$common=['version'=>3,'serverId'=>$this->serverId(),'migrationId'=>$migration['id'],'captureId'=>$capture['capture_id'],'accountId'=>$actor['user']['account_id'],'sourceInventoryRoot'=>$capture['inventory_root']];
        NativeCryptoMigrationReceiptV3::common($common);
        if(!isset($manifest['segments'][0]))throw new NativeError('crypto_local_artifact_manifest',409);
        foreach($manifest['segments'] as $segment){
            $description=['version'=>3,'keyId'=>$manifest['keyId'],'cipherManifestHash'=>$manifest['cipherManifestHash'],'index'=>$segment['index'],'artifactKind'=>'migrationLocalIntentsV3','artifact'=>$d];
            $this->localArtifactDescription($description,['id'=>$segment['id'],'size'=>$segment['size'],'sha256'=>$segment['sha256']],$migration,$actor);
            $row=$this->archiveRow($migration,$actor,$segment['id']);
            if((int)$row['complete']!==1||(int)$row['received']!==$segment['size']||$row['sha256']!==$segment['sha256']||$row['manifest']!==NativeCryptoCodec::canonical((object)$description))throw new NativeError('crypto_local_artifact_incomplete',409);
            $this->businessCipher($migration['id'],$segment['id'],$segment['size'],$segment['sha256'],true,$actor['user']['account_id']);
        }
        $event=$local['eventAuthorization'];[$body]=NativeCryptoCodec::decode($event);
        $eventHash=hash('sha256',NativeCryptoCodec::base64($event['commandBase64'],NativeCryptoCodec::MAX_COMMAND));
        $token=hash('sha256',"JivieMigrationLocalIntentToken/v3\n".NativeCryptoCodec::canonical((object)($common+['artifactId'=>$manifest['artifactId']])));
        $this->businessOwnEvent($body,$event,$actor,$migration['id'],'content',$token,NativeCryptoV2Codec::hash((object)$d));
        $localSummary=['artifactId'=>$manifest['artifactId'],'cipherManifestHash'=>$manifest['cipherManifestHash'],'intentCount'=>$d['intentCount'],'ownEventCommandHash'=>$eventHash];NativeCryptoMigrationReceiptV3::local($localSummary);
        $certificates=[];
        foreach(['content','finance'] as $domain){
            $row=$this->captureLegacyCertificate($migration,$actor,$domain);if($row['event_authorization']===null)throw new NativeError('crypto_legacy_inventory_anchor',409);
            $cert=json_decode($row['authorization'],true,64,JSON_THROW_ON_ERROR);[$command,$bytes,$signature]=NativeCryptoCodec::decode($cert);$p=$command['payload'];$h=$p['header'];
            if($command['operation']!=='crypto2.migration.legacy.certify'||$command['accountId']!==$actor['user']['account_id']||$h['captureId']!==$capture['capture_id']||$h['migrationId']!==$migration['id']||$h['sourceInventoryRoot']!==$capture['inventory_root']||$h['archiveManifestHash']!==$header['archiveManifestHash']||$h['domain']!==$domain)throw new NativeError('crypto_receipts_context',409);
            $directory=new NativeCryptoDirectoryV2($this->container,$this->bearer,$this->ip);NativeCryptoV2Codec::verify($bytes,$signature,NativeCryptoMigrationGenerationV3::retainedSigningKey($this->pdo,$cert,$actor['user']['account_id'])??$directory->authorizeContent($command,$directory->current($actor['user']['account_id'])));
            $root=NativeCryptoCaptureLegacyV3::root($h,(function()use($migration,$actor,$domain){
                $where=$domain==='finance'?"receipt_kind='finance'":"receipt_kind IN ('records','documents')";
                foreach($this->iterate('SELECT * FROM familyhub_crypto_legacy_index_v3 WHERE migration_id=? AND account_id=? AND '.$where.' ORDER BY scope_id,receipt_kind,legacy_id,legacy_device_id',[$migration['id'],$actor['user']['account_id']]) as $entry)yield $this->captureLegacyDescriptor($entry);
            })());
            if($root!==$p['manifestRoot']||$root!==$row['manifest_root']||$h['receiptCount']!==(int)$row['receipt_count'])throw new NativeError('crypto_receipts_coverage',409);
            $event=json_decode($row['event_authorization'],true,64,JSON_THROW_ON_ERROR);[$eventBody]=NativeCryptoCodec::decode($event);$certHash=NativeCryptoV2Codec::hash((object)$cert);
            $this->businessOwnEvent($eventBody,$event,$actor,$migration['id'],$domain,NativeCryptoCaptureLegacyV3::scopeToken($h),$certHash);
            $certificates[$domain]=['certificateHash'=>$certHash,'manifestRoot'=>$root,'receiptCount'=>$h['receiptCount']];
        }
        return ['section'=>NativeCryptoMigrationReceiptV3::section($common,$certificates['content'],$certificates['finance'],$localSummary),'certificates'=>$certificates];
    }

    private function businessOwnEvent($body,$proof,$actor,$migrationId,$domain,$token,$hash)
    {
        $p=$body['payload'];$commandHash=hash('sha256',NativeCryptoCodec::base64($proof['commandBase64'],NativeCryptoCodec::MAX_COMMAND));
        $row=$this->one('SELECT authorization FROM familyhub_crypto_directory WHERE account_id=? AND command_hash=?',[$actor['user']['account_id'],$commandHash]);
        if(!$row||NativeCryptoCodec::canonical(json_decode($row['authorization']))!==NativeCryptoCodec::canonical((object)$proof)||$body['operation']!=='crypto2.account.migrationAttest'||$body['accountId']!==$actor['user']['account_id']||$body['serverId']!==$this->serverId()||$p['migrationId']!==$migrationId||$p['domain']!==$domain||$p['scopeToken']!==$token||$p['attestationHash']!==$hash)throw new NativeError('crypto_receipts_anchor',409);
        (new NativeCryptoDirectoryV2($this->container,$this->bearer,$this->ip))->current($actor['user']['account_id']);
    }

    private function businessReceiptArtifact($migration,$actor,$source,$certificates)
    {
        $table=$source['context']['sourceTable'];$domain=$table==='familyhub_finance_operations'?'finance':'content';
        if(!in_array($table,['familyhub_operations','familyhub_finance_operations','familyhub_document_requests'],true))throw new NativeError('crypto_receipts_context',409);
        $resolved=$this->captureSourceBinding($migration['id'],$source['context']['captureId'],$source['binding']['bindingId'],$actor);$cells=get_object_vars($resolved['typedRow']);
        $value=static function($column)use($cells){if(!isset($cells[$column]['valueBase64']))throw new NativeError('crypto_receipts_context',409);return base64_decode($cells[$column]['valueBase64'],true);};
        $kind=$table==='familyhub_operations'?'records':($table==='familyhub_document_requests'?'documents':'finance');
        $row=$this->one('SELECT * FROM familyhub_crypto_legacy_index_v3 WHERE migration_id=? AND account_id=? AND binding_id=?',[$migration['id'],$actor['user']['account_id'],$source['binding']['bindingId']]);
        if(!$row||$row['source_commitment']!==$source['binding']['sourceCommitment']||$row['scope_id']!==$value('scope_id')||$row['receipt_kind']!==$kind||$row['legacy_id']!==$value($kind==='documents'?'request_id':'id')||$row['legacy_device_id']!==($kind==='documents'?$value('device_id'):''))throw new NativeError('crypto_receipts_coverage',409);
        return NativeCryptoMigrationReceiptV3::artifact($source['binding']['bindingId'],$source['binding']['sourceCommitment'],$domain,$certificates[$domain]);
    }


    private function verify($params, $migration, $portion, $actor, $proof)
    {
        if ($migration['state'] !== 'fenced' || $portion['state'] !== 'fenced') {
            throw new NativeError('crypto_migration_not_fenced', 409);
        }
        $inventory = $this->ownInventory($migration, $actor);
        $hash = self::inventoryHash((object)$inventory);
        if ($params['inventoryHash'] !== $hash || $portion['inventory_hash'] !== $hash) {
            throw new NativeError('crypto_inventory_changed', 409);
        }
        $manifest = NativeCryptoCodec::base64($params['encryptedManifestBase64'], 196608);
        if (strlen($manifest) < 48) {
            throw new NativeError('crypto_invalid_envelope');
        }
        $restore = $params['coldRestoreProof'];
        if (!is_array($restore)) {
            throw new NativeError('validation_error');
        }
        $this->fields($restore, ['version', 'challenge', 'inventoryHash', 'manifestCipherHash', 'archiveCipherHash', 'restoredInventoryHash']);
        foreach (['inventoryHash', 'manifestCipherHash', 'archiveCipherHash', 'restoredInventoryHash'] as $field) {
            $this->digest($restore[$field]);
        }
        if ($restore['version'] !== 2 || $restore['challenge'] !== $migration['challenge'] ||
            $restore['inventoryHash'] !== $hash || $restore['restoredInventoryHash'] !== $hash ||
            $restore['manifestCipherHash'] !== hash('sha256', $manifest)) {
            throw new NativeError('crypto_migration_restore_proof_invalid', 409);
        }
        $contribution = $params['contributions'];
        if (!is_array($contribution)) {
            throw new NativeError('validation_error');
        }
        $this->fields($contribution, ['keyId', 'cipherManifestHash', 'segmentCount']);
        $this->uuid($contribution['keyId']);
        $this->digest($contribution['cipherManifestHash']);
        if (!is_int($contribution['segmentCount']) || $contribution['segmentCount'] < 1 ||
            $restore['archiveCipherHash'] !== $contribution['cipherManifestHash']) {
            throw new NativeError('crypto_migration_restore_proof_invalid', 409);
        }
        $cipherRoot = hash_init('sha256');
        hash_update($cipherRoot, '[');
        $count = 0;
        // Canonical public manifests are SQL-stored JSON. Numeric ordering is
        // identical on SQLite/MariaDB/MySQL; no unbounded array is assembled.
        foreach ($this->iterate("SELECT * FROM familyhub_crypto_migration_archives_v2 WHERE migration_id=? AND account_id=? ORDER BY JSON_EXTRACT(manifest,'$.index')+0,id", [
            $migration['id'], $actor['user']['account_id'],
        ]) as $archive) {
            $description = json_decode($archive['manifest'], true, 16, JSON_THROW_ON_ERROR);
            if ((int)$archive['complete'] !== 1 || (int)$archive['received'] !== (int)$archive['size'] ||
                $description['index'] !== $count || $description['keyId'] !== $contribution['keyId'] ||
                $description['cipherManifestHash'] !== $contribution['cipherManifestHash']) {
                throw new NativeError('crypto_migration_archive_incomplete', 409);
            }
            if ($count) hash_update($cipherRoot, ',');
            hash_update($cipherRoot, self::inventoryCanonical((object)[
                'id' => $archive['id'], 'index' => $count, 'size' => (int)$archive['size'], 'sha256' => $archive['sha256'],
            ]));
            $count++;
        }
        hash_update($cipherRoot, ']');
        if ($count !== $contribution['segmentCount'] ||
            !hash_equals($contribution['cipherManifestHash'], hash_final($cipherRoot))) {
            throw new NativeError('crypto_migration_archive_integrity', 409);
        }
        $verification = ['inventoryHash' => $hash, 'encryptedManifestBase64' => $params['encryptedManifestBase64'],
            'contributions' => $contribution, 'coldRestoreProof' => $restore, 'authorization' => $proof];
        $this->change("UPDATE familyhub_crypto_migration_portions_v2 SET state='verified',verification=? WHERE migration_id=? AND account_id=?", [
            self::inventoryCanonical((object)$verification), $migration['id'], $actor['user']['account_id'],
        ]);
        $portion['state'] = 'verified';
        $pending = $this->one("SELECT COUNT(*) AS n FROM familyhub_crypto_migration_portions_v2 WHERE migration_id=? AND state<>'verified'", [$migration['id']]);
        if ((int)$pending['n'] === 0) {
            $this->change("UPDATE familyhub_crypto_migrations_v2 SET state='verified',updated_at=? WHERE id=?", [time(), $migration['id']]);
            $migration['state'] = 'verified';
        }
        return $this->status($migration, $portion);
    }

    /** Capture3 public ancestry contains only randomized source commitments.
     * Private raw comparisons are reused internally, never re-signed/exposed.
     */
    private function recordsStageCapture3($params, $actor, $proof, $command, $authorKey, $secrets)
    {
        $this->fields($params, ['captureVersion', 'migrationId', 'captureId',
            'sourceInventoryRoot', 'sourceBindings', 'batch']);
        [$migration, $portion] = $this->migration($params['migrationId'], $actor);
        $this->archiveAccess($migration, $portion, $actor);
        $this->unchanged($migration);
        $capture = $this->captureRow($migration, $actor);
        if ($capture['capture_id'] !== $params['captureId'] || $capture['state'] !== 'sealed'
            || $capture['inventory_root'] !== $params['sourceInventoryRoot']) {
            throw new NativeError('crypto_capture_generation_conflict', 409);
        }
        $bindings = $params['sourceBindings'];
        if (!is_array($bindings) || !array_is_list($bindings) || !$bindings || count($bindings) > 32) {
            throw new NativeError('crypto_migration_source_binding', 409);
        }
        $captured = [];
        $rows = [];
        foreach ($bindings as $binding) {
            $this->fields($binding, ['bindingId', 'scopeId', 'sourceKind', 'canonicalId',
                'wireId', 'domain', 'type', 'legacyRevision', 'recordProofHash', 'companionProofHashes', 'witness', 'objects']);
            $id = $this->uuid($binding['bindingId']);
            if (isset($rows[$id])) {
                throw new NativeError('crypto_migration_source_binding', 409);
            }
            $row = $this->one('SELECT * FROM familyhub_crypto_capture_sources_v3 WHERE migration_id=? AND account_id=? AND binding_id=?',
                [$migration['id'], $actor['user']['account_id'], $id]);
            if (!$row || $row['scope_id'] !== $binding['scopeId'] || $row['domain'] !== $binding['domain']
                || !in_array($row['domain'], ['content', 'finance'], true)) {
                throw new NativeError('crypto_migration_source_binding', 409);
            }
            $rows[$id] = $row;
            $captured[] = $this->captureBinding($row);
        }
        usort($captured, static fn($a, $b) => strcmp($a['bindingId'], $b['bindingId']));
        $verified = NativeCryptoCaptureV3::verifyBindings([
            'version' => 3, 'serverId' => $this->serverId(), 'captureId' => $capture['capture_id'],
            'migrationId' => $migration['id'], 'accountId' => $actor['user']['account_id'],
        ], $captured, $secrets, fn($context) => $this->captureSource($migration, $actor, $context));
        $contexts = [];
        foreach ($verified as $entry) {
            $id = $entry['binding']['bindingId'];
            $context = $entry['context'];
            if ($rows[$id]['source_table'] !== $context['sourceTable'] || $rows[$id]['source_id'] !== $context['sourceId']) {
                throw new NativeError('crypto_migration_source_binding', 409);
            }
            $contexts[$id] = $context;
        }
        $entries = (new NativeCryptoRecordProofV2($this->container))->parseBatch($params['batch'], $command, $authorKey);
        $byDigest = [];
        foreach ($entries as $entry) $byDigest[$entry['recordProofHash']] = $entry;
        $private = [];
        foreach ($bindings as $binding) {
            $context = $contexts[$binding['bindingId']];
            $raw = $this->captureSource($migration, $actor, $context);
            $cells = get_object_vars($raw);
            $idColumn = match ($context['sourceTable']) {
                'familyhub_payment_events', 'familyhub_payment_projections' => 'event_id',
                'familyhub_payment_cash' => 'movement_id', default => 'id',
            };
            $sourceId = isset($cells[$idColumn]['valueBase64'])
                ? base64_decode($cells[$idColumn]['valueBase64'], true) : null;
            $this->uuid($sourceId);
            $internal = $binding;
            if (!isset($byDigest[$binding['recordProofHash']])) {
                throw new NativeError('crypto_migration_source_binding', 409);
            }
            $this->validateCaptureWitness($binding, $rows[$binding['bindingId']], $capture, $migration, $actor, $byDigest, $raw);
            unset($internal['bindingId'], $internal['witness'], $internal['objects']);
            $internal['sourceTable'] = $context['sourceTable'];
            $internal['sourceId'] = $sourceId;
            $internal['sourceRowHash'] = hash('sha256', NativeCryptoCodec::canonical($raw));
            $private[] = $internal;
        }
        usort($private, static fn($a, $b) => strcmp($a['scopeId'].':'.$a['wireId'], $b['scopeId'].':'.$b['wireId']));
        // The inner helper retains its closed source/type/role/namespace and
        // companion validation. Only its private comparison parameters differ;
        // retained outer authorization remains the EXACT capture3 proof.
        return ['captureVersion' => 3, 'captureId' => $capture['capture_id']]
            + $this->recordsStage(['migrationId' => $migration['id'],
                'inventoryHash' => $portion['inventory_hash'], 'sourceBindings' => $private,
                'batch' => $params['batch']], $migration, $portion, $actor, $proof, $command, $authorKey);
    }

    /** One exact immutable primary batch, bounded to the protocol's 32 proofs. */
    private function stagedCompanionHash($migrationId, $scopeId, $wireId, $primaryWireId)
    {
        $primary = $this->one('SELECT record_proof,record_proof_hash FROM familyhub_crypto_migration_stage_records_v2 WHERE migration_id=? AND scope_id=? AND wire_id=?',
            [$migrationId,$scopeId,$primaryWireId]);
        if (!$primary) return null;
        [$body] = NativeCryptoCodec::decode(json_decode($primary['record_proof'],true,34,JSON_THROW_ON_ERROR));
        $row = $this->one('SELECT authorization FROM familyhub_crypto_migration_stage_batches_v2 WHERE migration_id=? AND batch_id=?',
            [$migrationId,$body['batchId']]);
        if (!$row) return null;
        [$stage] = NativeCryptoCodec::decode(json_decode($row['authorization'],true,34,JSON_THROW_ON_ERROR));
        $payload = $stage['payload'];
        $authorized = [];
        foreach ($payload['sourceBindings'] as $binding) {
            if ($binding['recordProofHash'] === $primary['record_proof_hash']) $authorized = $binding['companionProofHashes'];
        }
        foreach ($payload['batch']['records'] as $proof) {
            [$record] = NativeCryptoCodec::decode($proof);
            $hash = hash('sha256',NativeCryptoCodec::canonical((object)$proof));
            if ($record['scopeId'] === $scopeId && $record['id'] === $wireId && in_array($hash,$authorized,true)) {
                return ['record_proof_hash'=>$hash];
            }
        }
        return null;
    }

    /** Cipher commitments only; plaintext witness comparison belongs to the reader. */
    /** A physical asset has no synthetic business record. Its exact own signed
     * Capture3 begin is the closed canonical-file artifact. */
    private function businessIdeaFile($migration,$capture,$actor,$source,$bytes)
    {
        if($source['context']['sourceTable']!=='familyhub_idea_assets')throw new NativeError('crypto_migration_file_binding',409);
        $resolved=$this->captureSourceBinding($migration['id'],$capture['capture_id'],$source['binding']['bindingId'],$actor);
        if($source['binding']!==$resolved['binding']||$source['context']!==$resolved['context'])throw new NativeError('crypto_migration_file_binding',409);
        $source['typedRow']=$resolved['typedRow'];
        $cells=get_object_vars($source['typedRow']);
        $text=static fn($k)=>isset($cells[$k]['valueBase64'])?base64_decode($cells[$k]['valueBase64'],true):null;
        $board=$this->uuid($text('board_id'));$sha=$this->digest($text('sha256'));
        $rows=$this->many("SELECT * FROM familyhub_crypto_migration_blobs_v2 WHERE migration_id=? AND account_id=? AND source_table='familyhub_idea_assets' AND scope_id=? AND source_id=? AND purpose='ideaAsset' ORDER BY id LIMIT 2",[$migration['id'],$actor['user']['account_id'],$source['context']['scopeId'],$board.':'.$text('sha256')]);
        if(count($rows)!==1)throw new NativeError('crypto_migration_idea_files_pending',409);
        $blob=$rows[0];$proof=json_decode($blob['authorization'],true,64,JSON_THROW_ON_ERROR);[$command]=NativeCryptoCodec::decode($proof);$p=$command['payload'];
        $this->fields($p,['captureVersion','migrationId','captureId','sourceInventoryRoot','bindingId','scopeId','domain','epoch','membershipHeadHash','accessRevision','id','purpose','size','sha256','manifestBase64']);
        $d=['version'=>2,'id'=>$blob['id'],'scopeId'=>$blob['scope_id'],'domain'=>$blob['domain'],'epoch'=>(int)$blob['epoch'],'accessRevision'=>(int)$blob['access_revision'],'membershipHeadHash'=>$blob['head_hash'],'cipherSize'=>(int)$blob['size'],'cipherSha256'=>$blob['sha256'],'manifestBase64'=>$blob['manifest']];
        $object=['version'=>3,'kind'=>'ideaAsset','canonicalId'=>$board,'sourceBindingId'=>$source['binding']['bindingId'],'plainSize'=>(int)$text('size'),'blob'=>$d];
        $record=['type'=>'idea','deleted'=>false,'scopeId'=>$blob['scope_id'],'domain'=>'content','epoch'=>(int)$blob['epoch'],'accessRevision'=>(int)$blob['access_revision'],'membershipHeadHash'=>$blob['head_hash'],'metadata'=>['blobIds'=>[$blob['id']]]];
        $binding=['bindingId'=>$source['binding']['bindingId'],'canonicalId'=>$board];
        $this->validateCaptureObject($object,$binding,$record,$capture,$migration,$actor,$source['typedRow']);
        $this->businessBlobBinding($migration,$capture,$actor,$binding,$record,$blob['id'],'ideaAsset');
        if($p['size']!==$d['cipherSize']||$p['sha256']!==$d['cipherSha256']||$p['manifestBase64']!==$d['manifestBase64'])throw new NativeError('crypto_migration_file_binding',409);
        (new NativeCryptoScopeV2($this->container,$this->bearer,$this->ip))->author($record['scopeId'],$record['membershipHeadHash'],$record['epoch'],$record['accessRevision'],$actor,'content',false);
        if($bytes)$this->businessCipher($migration['id'],$blob['id'],$d['cipherSize'],$d['cipherSha256']);
        return ['artifactHash'=>NativeCryptoMigrationBusinessParityV3::canonicalFileArtifact($proof),'object'=>$object];
    }

    private function validateCaptureObject($object,$binding,$record,$capture,$migration,$actor,$typedSource)
    {
        $this->fields($object,['version','kind','canonicalId','sourceBindingId','plainSize','blob']);
        $idea=$record['type']==='idea';$kind=$idea?'ideaAsset':'attachment';
        if($idea){
            $source=$this->captureSourceBinding($migration['id'],$capture['capture_id'],$object['sourceBindingId'],$actor);
            if($source['context']['sourceTable']!=='familyhub_idea_assets'||$source['context']['scopeId']!==$record['scopeId']||$source['context']['domain']!=='content')throw new NativeError('crypto_migration_file_binding',409);
            $typedSource=$source['typedRow'];
        }elseif($object['sourceBindingId']!==$binding['bindingId'])throw new NativeError('crypto_migration_file_binding',409);
        $cells=get_object_vars($typedSource);$text=static fn($k)=>isset($cells[$k]['valueBase64'])?base64_decode($cells[$k]['valueBase64'],true):null;
        $sourceSize=$text('size');
        if($idea&&($text('board_id')!==$binding['canonicalId']||$text('scope_id')!==$record['scopeId']||$text('complete')!=='1'||$text('received')!==$sourceSize))throw new NativeError('crypto_migration_file_binding',409);
        $d=$object['blob'];$this->fields($d,['version','id','scopeId','domain','epoch','accessRevision','membershipHeadHash','cipherSize','cipherSha256','manifestBase64']);
        $this->uuid($d['id']);$this->digest($d['cipherSha256']);
        if($object['version']!==3||$object['kind']!==$kind||$object['canonicalId']!==$binding['canonicalId']
            ||!is_int($object['plainSize'])||$object['plainSize']<0||$object['plainSize']>($idea?2:20)*1024*1024
            ||!is_string($sourceSize)||!preg_match('/^(?:0|[1-9][0-9]*)$/D',$sourceSize)||(string)$object['plainSize']!==$sourceSize
            ||$d['version']!==2||$d['scopeId']!==$record['scopeId']||$d['domain']!==$record['domain']
            ||!is_int($d['cipherSize'])||$d['cipherSize']<41||$d['cipherSize']>NativeCryptoMigrationBlobV2::MAX_BYTES
            ||$d['epoch']!==$record['epoch']||$d['accessRevision']!==$record['accessRevision']||$d['membershipHeadHash']!==$record['membershipHeadHash'])throw new NativeError('crypto_migration_file_binding',409);
        $blob=$this->one('SELECT * FROM familyhub_crypto_migration_blobs_v2 WHERE migration_id=? AND id=?',[$migration['id'],$d['id']]);
        if(!$blob||(int)$blob['complete']!==1||(int)$blob['received']!==$d['cipherSize']||(int)$blob['size']!==$d['cipherSize']||$blob['sha256']!==$d['cipherSha256']||$blob['manifest']!==$d['manifestBase64']
            ||$blob['account_id']!==$actor['user']['account_id']||$blob['scope_id']!==$record['scopeId']||$blob['domain']!==$record['domain']||$blob['purpose']!==($idea?'ideaAsset':'canonicalPayload')
            ||$blob['source_table']!==($idea?'familyhub_idea_assets':'familyhub_attachments')||$blob['source_id']!==($idea?$binding['canonicalId'].':'.$text('sha256'):$binding['canonicalId'])
            ||$blob['head_hash']!==$record['membershipHeadHash']||(int)$blob['epoch']!==$record['epoch']||(int)$blob['access_revision']!==$record['accessRevision']
            ||!in_array($d['id'],$record['metadata']['blobIds'],true))throw new NativeError('crypto_migration_file_incomplete',409);
        $recordBinding=$binding;$recordBinding['bindingId']=$object['sourceBindingId'];
        $this->businessBlobBinding($migration,$capture,$actor,$recordBinding,$record,$d['id'],$idea?'ideaAsset':'canonicalPayload');
        $encrypted=json_decode(NativeCryptoCodec::base64($d['manifestBase64'],16384),true,34,JSON_THROW_ON_ERROR);
        $expected=['version'=>2,'purpose'=>'documentObject','serverId'=>$this->serverId(),'scopeId'=>$record['scopeId'],'id'=>$d['id'],'domain'=>$record['domain'],'epoch'=>$record['epoch'],'membershipHeadHash'=>$record['membershipHeadHash']];
        if(!is_array($encrypted)||!isset($encrypted['context'])||NativeCryptoCodec::canonical($encrypted['context'])!==NativeCryptoCodec::canonical($expected))throw new NativeError('crypto_migration_file_manifest',409);
    }

    private function validateCaptureWitness($binding, $captured, $capture, $migration, $actor, $byDigest, $typedSource)
    {
        $tag=['version'=>3,'migrationId'=>$migration['id'],'captureId'=>$capture['capture_id'],'bindingId'=>$binding['bindingId'],'sourceInventoryRoot'=>$capture['inventory_root']];
        foreach([$binding['recordProofHash'],...$binding['companionProofHashes']] as $hash){
            if(!isset($byDigest[$hash])||NativeCryptoCodec::canonical((object)($byDigest[$hash]['record']['metadata']['migrationOrigin']??[]))!==NativeCryptoCodec::canonical((object)$tag))throw new NativeError('crypto_migration_origin_tag',409);
        }
        $entry = $byDigest[$binding['recordProofHash']];
        $record = $entry['record'];
        $objects=$binding['objects'];
        if(!is_array($objects)||!array_is_list($objects)||count($objects)>($record['type']==='idea'?20:1)
            ||($objects&&(!in_array($record['type'],['idea','attachment'],true)||$record['deleted']))
            ||($record['type']==='attachment'&&!$record['deleted']&&count($objects)!==1))throw new NativeError('crypto_migration_file_binding',409);
        $ids=[];$bindings=[];
        foreach($objects as $object){
            $this->validateCaptureObject($object,$binding,$record,$capture,$migration,$actor,$typedSource);
            if(isset($ids[$object['blob']['id']])||isset($bindings[$object['sourceBindingId']]))throw new NativeError('crypto_migration_file_binding',409);
            $ids[$object['blob']['id']]=true;$bindings[$object['sourceBindingId']]=true;
        }
        if ($record['type'] === 'scopeMetadata') {
            if ($binding['witness'] !== null) throw new NativeError('crypto_migration_witness_private_scope', 409);
            return; // Actual manager-only sanitized transformation checked below.
        }
        $witness = $binding['witness'];
        $this->fields($witness, ['version', 'purpose', 'context', 'cipherManifestHash', 'segments', 'manifestBase64']);
        $expected = [
            'version' => 3, 'purpose' => 'migrationWitness', 'serverId' => $this->serverId(),
            'accountId' => $actor['user']['account_id'], 'captureId' => $capture['capture_id'],
            'migrationId' => $migration['id'], 'bindingId' => $binding['bindingId'],
            'sourceInventoryRoot' => $capture['inventory_root'], 'sourceCommitment' => $captured['source_commitment'],
            'scopeId' => $binding['scopeId'], 'domain' => $binding['domain'], 'epoch' => $record['epoch'],
            'accessRevision' => $record['accessRevision'], 'membershipHeadHash' => $record['membershipHeadHash'],
            'type' => $binding['type'], 'sourceKind' => $binding['sourceKind'],
            'canonicalId' => $binding['canonicalId'], 'wireId' => $binding['wireId'],
        ];
        if ($witness['version'] !== 3 || $witness['purpose'] !== 'migrationWitness'
            || NativeCryptoCodec::canonical($witness['context']) !== NativeCryptoCodec::canonical($expected)
            || !is_array($witness['segments']) || !array_is_list($witness['segments'])
            || !$witness['segments'] || count($witness['segments']) > 4) {
            throw new NativeError('crypto_migration_witness_context', 409);
        }
        $this->digest($witness['cipherManifestHash']);
        if (hash('sha256', NativeCryptoCodec::canonical($witness['segments'])) !== $witness['cipherManifestHash']) {
            throw new NativeError('crypto_migration_witness_manifest', 409);
        }
        $manifest = NativeCryptoCodec::base64($witness['manifestBase64'], 16384);
        $envelope = json_decode($manifest, true, 34, JSON_THROW_ON_ERROR);
        if (!is_array($envelope) || !isset($envelope['context'])
            || NativeCryptoCodec::canonical($envelope['context']) !== NativeCryptoCodec::canonical($expected)) {
            throw new NativeError('crypto_migration_witness_manifest', 409);
        }
        $ids = [];
        $size = 0;
        foreach ($witness['segments'] as $index => $segment) {
            $this->fields($segment, ['id', 'index', 'size', 'sha256']);
            $id = $this->uuid($segment['id']);
            $this->digest($segment['sha256']);
            if (isset($ids[$id]) || $segment['index'] !== $index || !is_int($segment['size'])
                || $segment['size'] < 48 || $segment['size'] > NativeCryptoMigrationBlobV2::MAX_BYTES) {
                throw new NativeError('crypto_migration_witness_manifest', 409);
            }
            $ids[$id] = true;
            $size += $segment['size'];
            $blob = $this->one('SELECT * FROM familyhub_crypto_migration_blobs_v2 WHERE migration_id=? AND id=?', [$migration['id'], $id]);
            if (!$blob || (int)$blob['complete'] !== 1 || (int)$blob['size'] !== $segment['size']
                || $blob['sha256'] !== $segment['sha256'] || $blob['manifest'] !== $witness['manifestBase64']
                || $blob['account_id'] !== $actor['user']['account_id'] || $blob['scope_id'] !== $binding['scopeId']
                || $blob['domain'] !== $binding['domain'] || $blob['purpose'] !== 'typedWitness'
                || $blob['source_table'] !== $captured['source_table']
                || $blob['head_hash'] !== $record['membershipHeadHash'] || (int)$blob['epoch'] !== $record['epoch']
                || (int)$blob['access_revision'] !== $record['accessRevision']) {
                throw new NativeError('crypto_migration_witness_incomplete', 409);
            }
        }
        if ($size > 65 * 1024 * 1024) throw new NativeError('crypto_migration_witness_size', 409);
        foreach (array_merge([$binding['recordProofHash']], $binding['companionProofHashes']) as $hash) {
            if (!isset($byDigest[$hash])) throw new NativeError('crypto_migration_source_binding', 409);
            if($byDigest[$hash]['record']['type']==='financeAccountChoice')continue; // Sanitized purpose companion never exposes the original private expense witness.
            foreach ($ids as $id => $_) {
                if (!in_array($id, $byDigest[$hash]['record']['metadata']['blobIds'], true)) {
                    throw new NativeError('crypto_migration_witness_unbound', 409);
                }
            }
        }
    }

    /** Source-bound ciphertext staging has no active business side effects. */
    private function stagedRecords($params, $migration, $portion, $actor)
    {
        if (!in_array($migration['state'], ['fenced', 'verified'], true)
            || !in_array($portion['state'], ['fenced', 'verified'], true)) {
            throw new NativeError('crypto_migration_not_fenced', 409);
        }
        $scopeId = $this->uuid($params['scopeId']);
        $domain = $params['domain'];
        if (!in_array($domain, ['content', 'finance'], true)) {
            throw new NativeError('validation_error');
        }
        $limit = $params['limit'] ?? 20;
        if (!is_int($limit) || $limit < 1 || $limit > 20) {
            throw new NativeError('invalid_cursor');
        }
        $after = isset($params['afterId']) ? NativeCryptoRecordAddressV2::wireId($params['afterId']) : '';
        $scopes = new NativeCryptoScopeV2($this->container, $this->bearer, $this->ip);
        $head = $scopes->current($scopeId);
        if (!$head) {
            throw new NativeError('crypto_scope_head_missing', 404);
        }
        $scope = $this->scope($scopeId, $actor['user']['id']);
        // Being a component manager or contributor never grants finance READ.
        $scopes->author($scopeId, $head['head_hash'], (int)$head['epoch'],
            (int)$scope['effective_access_revision'], $actor, $domain, false);
        $rows = $this->many('SELECT wire_id,record_proof FROM familyhub_crypto_migration_stage_records_v2 WHERE migration_id=? AND scope_id=? AND domain=? AND wire_id>? ORDER BY wire_id LIMIT '.($limit + 1),
            [$migration['id'], $scopeId, $domain, $after]);
        $out = [];
        $seen = [];
        $bytes = 0;
        $consumed = 0;
        foreach ($rows as $row) {
            if ($consumed === $limit) break;
            $recordProof = json_decode($row['record_proof'], true, 34, JSON_THROW_ON_ERROR);
            [$record] = NativeCryptoCodec::decode($recordProof);
            if ($record['scopeId'] !== $scopeId || $record['domain'] !== $domain
                || $record['membershipHeadHash'] !== $head['head_hash']) {
                throw new NativeError('crypto_migration_authority_changed', 409);
            }
            if (!isset($seen[$record['batchId']])) {
                $batch = $this->one('SELECT authorization FROM familyhub_crypto_migration_stage_batches_v2 WHERE migration_id=? AND batch_id=?',
                    [$migration['id'], $record['batchId']]);
                if (!$batch) throw new NativeError('crypto_migration_stage_unavailable', 503);
                $size = strlen($batch['authorization']);
                if ($out && $bytes + $size > 1250000) break;
                $out[] = ['batchId' => $record['batchId'],
                    'authorization' => json_decode($batch['authorization'], true, 34, JSON_THROW_ON_ERROR)];
                $bytes += $size;
                $seen[$record['batchId']] = true;
            }
            $consumed++;
            $after = $row['wire_id'];
        }
        return ['migrationId' => $migration['id'], 'scopeId' => $scopeId, 'domain' => $domain,
            'stages' => $out, 'nextAfterId' => $after ?: null, 'hasMore' => count($rows) > $consumed];
    }

    /** Source-bound ciphertext staging has no active business side effects. */
    private function recordsStage($params, $migration, $portion, $actor, $proof, $command, $authorKey)
    {
        if (!in_array($migration['state'], ['fenced', 'verified'], true)
            || !in_array($portion['state'], ['fenced', 'verified'], true)
            || $params['inventoryHash'] !== $portion['inventory_hash']) {
            throw new NativeError('crypto_migration_not_fenced', 409);
        }
        if (!is_array($command) || !is_string($authorKey)) {
            throw new NativeError('crypto_migration_author_required', 403);
        }
        $bindings = $params['sourceBindings'];
        if (!is_array($bindings) || !array_is_list($bindings) || count($bindings) < 1 || count($bindings) > 32) {
            throw new NativeError('validation_error');
        }
        $codec = new NativeCryptoRecordProofV2($this->container);
        $records = $codec->parseBatch($params['batch'], $command, $authorKey);
        if (count($records) < count($bindings)) {
            throw new NativeError('crypto_migration_source_binding', 409);
        }
        $byWire = [];
        $byDigest = [];
        $covered = [];
        $batchScope = $records[0]['record']['scopeId'];
        $batchDomain = $records[0]['record']['domain'];
        foreach ($records as $entry) {
            $record = $entry['record'];
            // The outer stage proof binds source rows and is disclosed only to
            // readers of this complete domain subset. A private sibling scope
            // or another domain must never leak through that authorization.
            if ($record['scopeId'] !== $batchScope || $record['domain'] !== $batchDomain) {
                throw new NativeError('crypto_migration_stage_domain', 409);
            }
            $byWire[$record['scopeId'].':'.$record['id']] = $entry;
            $byDigest[$entry['recordProofHash']] = $entry;
        }
        $selections = $this->selections($migration, $actor);
        $prepared = [];
        $last = '';
        foreach ($bindings as $binding) {
            $this->fields($binding, ['sourceTable', 'scopeId', 'sourceId', 'sourceKind', 'canonicalId',
                'wireId', 'domain', 'type', 'legacyRevision', 'sourceRowHash', 'recordProofHash', 'companionProofHashes']);
            $scopeId = $this->uuid($binding['scopeId']);
            $sourceId = $this->uuid($binding['sourceId']);
            $this->uuid($binding['canonicalId']);
            NativeCryptoRecordAddressV2::wireId($binding['wireId']);
            $this->digest($binding['sourceRowHash']);
            $this->digest($binding['recordProofHash']);
            $key = $scopeId.':'.$binding['wireId'];
            if (strcmp($last, $key) >= 0 || !isset($byWire[$key])) {
                throw new NativeError('crypto_migration_source_binding', 409);
            }
            $last = $key;
            $entry = $byWire[$key];
            $record = $entry['record'];
            if (isset($covered[$entry['recordProofHash']])) {
                throw new NativeError('crypto_migration_source_binding', 409);
            }
            $covered[$entry['recordProofHash']] = true;
            $companions = $binding['companionProofHashes'];
            if (!is_array($companions) || !array_is_list($companions) || count($companions) > (($command['payload']['captureVersion']??null)===3?2:1)) {
                throw new NativeError('crypto_migration_source_binding', 409);
            }
            $companionRoles=[];
            foreach ($companions as $digest) {
                $this->digest($digest);
                if (isset($covered[$digest]) || !isset($byDigest[$digest])) {
                    throw new NativeError('crypto_migration_source_binding', 409);
                }
                $derived = $byDigest[$digest]['record'];
                if(isset($companionRoles[$derived['type']]))throw new NativeError('crypto_migration_companion_binding',409);
                $companionRoles[$derived['type']]=true;
                $choice = ($command['payload']['captureVersion']??null)===3 && $binding['sourceTable']==='familyhub_finance_records' && $record['type']==='financeEntry' && !$record['deleted'] && $derived['type']==='financeAccountChoice';
                $taskIntent = $binding['sourceTable'] === 'familyhub_records' && $record['type'] === 'task'
                    && $derived['type'] === 'taskDerivationIntent';
                $taskResolution = $binding['sourceTable'] === 'familyhub_finance_records' && $record['type'] === 'financeEntry'
                    && $record['deleted'] === false && $derived['type'] === 'taskDerivationResolution';
                $reserved = $this->reservedSourceId($scopeId, 'taskDerivation:'.$sourceId);
                if ($choice) {
                    $source = $this->one('SELECT payload FROM familyhub_finance_records WHERE scope_id=? AND id=?',[$scopeId,$sourceId]);
                    $fact = $source ? json_decode($source['payload'],true,128,JSON_THROW_ON_ERROR) : null;
                    $scope = $this->one('SELECT parent_scope_id,organization_id FROM familyhub_scopes WHERE id=?',[$scopeId]);
                    $parent = $scope['parent_scope_id']??$scope['organization_id']??null;
                    if(!is_array($fact)||!isset($fact['accountScopeId'])||$fact['accountScopeId']===$scopeId||$fact['accountScopeId']!==$parent
                        || $derived['metadata']['references'] || $derived['metadata']['referenceVersions'] || $derived['metadata']['uniqueRefs'] || $derived['metadata']['blobIds'])throw new NativeError('crypto_migration_companion_binding',409);
                    $reserved=$this->reservedSourceId($scopeId,'financeAccountChoices');
                }
                if ($taskResolution) {
                    $source = $this->one('SELECT payload FROM familyhub_finance_records WHERE scope_id=? AND id=?', [$scopeId,$sourceId]);
                    $fact = $source ? json_decode($source['payload'], true, 128, JSON_THROW_ON_ERROR) : null;
                    if (!is_array($fact) || ($fact['kind'] ?? null) !== 'expense' || !isset($fact['taskId'])) {
                        throw new NativeError('crypto_migration_companion_binding', 409);
                    }
                    $taskId = $this->uuid($fact['taskId']);
                    $reserved = $this->reservedSourceId($scopeId, 'taskResolution:'.$taskId);
                    $intentId = $this->reservedSourceId($scopeId, 'taskDerivation:'.$taskId);
                    $expectedRefs = [
                        NativeCryptoRecordAddressV2::derive($this->serverId(),$scopeId,'content','records',$taskId),
                        NativeCryptoRecordAddressV2::derive($this->serverId(),$scopeId,'content','task_derivation_intents',$intentId),
                        $record['id'],
                    ];
                    $seenRefs = [];
                    foreach ($derived['metadata']['referenceVersions'] ?? [] as $ref) {
                        if ($ref['scopeId'] !== $scopeId || $ref['revision'] !== 1 || !in_array($ref['id'],$expectedRefs,true)
                            || isset($seenRefs[$ref['id']])) throw new NativeError('crypto_migration_companion_binding',409);
                        $seenRefs[$ref['id']] = true;
                        if ($ref['id'] === $record['id']) {
                            if ($ref['domain'] !== 'finance' || $ref['recordProofHash'] !== $entry['recordProofHash']) {
                                throw new NativeError('crypto_migration_companion_binding',409);
                            }
                        } else {
                            $target = $this->one('SELECT record_proof_hash FROM familyhub_crypto_migration_stage_records_v2 WHERE migration_id=? AND scope_id=? AND wire_id=?',
                                [$migration['id'],$scopeId,$ref['id']]);
                            // Task intents are materialized companions and live
                            // in the exact retained signed stage batch, not a
                            // fabricated second legacy SQL source row.
                            if (!$target) $target = $this->stagedCompanionHash($migration['id'],$scopeId,$ref['id'],$expectedRefs[0]);
                            if ($ref['domain'] !== 'content' || !$target || $target['record_proof_hash'] !== $ref['recordProofHash']) {
                                throw new NativeError('crypto_migration_companion_binding',409);
                            }
                        }
                    }
                    if (count($seenRefs) !== 3) throw new NativeError('crypto_migration_companion_binding',409);
                }
                if ((!$taskIntent && !$taskResolution && !$choice) || $derived['scopeId'] !== $scopeId
                    || $derived['domain'] !== $record['domain'] || $derived['epoch'] !== $record['epoch']
                    || $derived['membershipHeadHash'] !== $record['membershipHeadHash']
                    || $derived['accessRevision'] !== $record['accessRevision']
                    || $derived['operationId'] !== $record['operationId']
                    || $derived['expectedRevision'] !== 0 || $derived['previousRecordHash'] !== NativeCryptoDirectoryV2::ZERO
                    || $derived['deleted'] !== false || $derived['metadata']['identity']['canonicalId'] !== $reserved) {
                    throw new NativeError('crypto_migration_companion_binding', 409);
                }
                $covered[$digest] = true;
            }
            if ($record['expectedRevision'] !== 0 || $record['previousRecordHash'] !== NativeCryptoDirectoryV2::ZERO
                || $record['domain'] !== $binding['domain'] || $record['type'] !== $binding['type']
                || $entry['recordProofHash'] !== $binding['recordProofHash']
                || $record['metadata']['identity']['sourceKind'] !== $binding['sourceKind']
                || $record['metadata']['identity']['canonicalId'] !== $binding['canonicalId']) {
                throw new NativeError('crypto_migration_source_binding', 409);
            }
            $table = $binding['sourceTable'];
            if (!in_array($table, ['familyhub_records', 'familyhub_finance_records', 'familyhub_tables',
                'familyhub_attachments', 'familyhub_scopes', 'familyhub_payment_events',
                'familyhub_payment_projections', 'familyhub_payment_cash'], true)) {
                throw new NativeError('crypto_migration_source_type_pending', 409);
            }
            $expectedSourceKind = [
                'familyhub_records' => 'records', 'familyhub_finance_records' => 'finance_records',
                'familyhub_tables' => 'tables', 'familyhub_attachments' => 'attachments',
                'familyhub_scopes' => 'scope_metadata',
                'familyhub_payment_events' => 'payment_events',
                'familyhub_payment_projections' => 'payment_projections',
                'familyhub_payment_cash' => 'payment_cash',
            ][$table];
            if ($binding['sourceKind'] !== $expectedSourceKind) {
                throw new NativeError('crypto_migration_source_type', 409);
            }
            $selection = $selections[$table.':'.$binding['domain']] ?? null;
            if (!$selection) {
                throw new NativeError('permission_revoked', 403);
            }
            $idColumn = match ($table) {
                'familyhub_payment_events', 'familyhub_payment_projections' => 'event_id',
                'familyhub_payment_cash' => 'movement_id', default => 'id',
            };
            $selection['where'] = '('.$selection['where'].') AND '.$idColumn.'=?';
            $selection['params'][] = $sourceId;
            if ($table !== 'familyhub_scopes') {
                $selection['where'] .= ' AND scope_id=?';
                $selection['params'][] = $scopeId;
            } elseif ($sourceId !== $scopeId) {
                throw new NativeError('crypto_migration_source_binding', 409);
            }
            $raw = null;
            foreach ($this->rawRows($selection) as $row) {
                if ($raw !== null) {
                    throw new NativeError('crypto_migration_source_binding', 409);
                }
                $raw = $row;
            }
            if ($raw === null || !hash_equals(hash('sha256', NativeCryptoCodec::canonical($raw)), $binding['sourceRowHash'])) {
                throw new NativeError('crypto_migration_source_changed', 409);
            }
            $cells = get_object_vars($raw);
            $text = static function ($column) use ($cells) {
                if (!isset($cells[$column]) || $cells[$column]['valueBase64'] === null) {
                    return null;
                }
                return base64_decode($cells[$column]['valueBase64'], true);
            };
            // Attachment metadata has no revision column. Its source version1
            // is an explicit migration convention, fenced by the exact whole
            // typed row hash; completed files and deleted tombstones retain it.
            // An incomplete live upload needs its own private resumable upload
            // conversion, and must never be omitted from coverage or published
            // as a completed attachment.
            $payment = in_array($table, ['familyhub_payment_events', 'familyhub_payment_projections', 'familyhub_payment_cash'], true);
            if ($payment) {
                $facts = json_decode($text('data'), true, 128, JSON_THROW_ON_ERROR);
                if (!is_array($facts) || ($table === 'familyhub_payment_cash'
                    ? ($facts['id'] ?? null) !== $sourceId
                    : ($facts['eventId'] ?? null) !== $sourceId)) {
                    throw new NativeError('crypto_migration_source_binding',409);
                }
                if ($table === 'familyhub_payment_events' &&
                    (($facts['sourceScopeId'] ?? null) !== $scopeId ||
                     ($facts['sourceEntryId'] ?? null) !== $text('entry_id') ||
                     ($facts['payerAccountId'] ?? null) !== $text('payer_account_id'))) {
                    throw new NativeError('crypto_migration_source_binding',409);
                }
                if ($table === 'familyhub_payment_projections' &&
                    (($facts['sourceScopeId'] ?? null) !== $text('source_scope_id') ||
                     ($facts['payerAccountId'] ?? null) !== $text('owner_account_id'))) {
                    throw new NativeError('crypto_migration_source_binding',409);
                }
                $revision = $table === 'familyhub_payment_cash' ? '1'
                    : (string)($facts['paymentRevision'] ?? $facts['revision'] ?? '');
                if ($table === 'familyhub_payment_events' && $text('revision') !== $revision) {
                    throw new NativeError('crypto_migration_source_revision',409);
                }
            } elseif ($table === 'familyhub_attachments') {
                if (!in_array($text('complete'), ['0','1'], true)) {
                    throw new NativeError('crypto_migration_source_binding', 409);
                }
                if ($text('complete') !== '1' && $text('deleted') !== '1') {
                    throw new NativeError('crypto_migration_pending_upload', 409);
                }
                $revision = '1';
            } else {
                $revision = $text($table === 'familyhub_scopes' ? 'metadata_revision' : 'revision');
            }
            if (!is_string($revision) || !preg_match('/^(?:0|[1-9][0-9]*)$/D', $revision)
                || !is_int($binding['legacyRevision']) || $binding['legacyRevision'] < 0
                || ($binding['legacyRevision'] === 0 && $table !== 'familyhub_scopes')
                || (string)$binding['legacyRevision'] !== $revision) {
                throw new NativeError('crypto_migration_source_revision', 409);
            }
            $expectedType = match ($table) {
                'familyhub_tables' => 'table', 'familyhub_attachments' => 'attachment',
                'familyhub_scopes' => 'scopeMetadata',
                'familyhub_payment_events' => 'paymentEvent',
                'familyhub_payment_projections' => 'paymentProjection',
                'familyhub_payment_cash' => 'cashMovement', default => $text('type'),
            };
            if ($expectedType !== $record['type']) {
                throw new NativeError('crypto_migration_source_type', 409);
            }
            $canonical = $sourceId;
            if ($table === 'familyhub_scopes') {
                $canonical = $this->reservedSourceId($scopeId, 'scopeMetadata');
            }
            if (($table !== 'familyhub_scopes' && !$payment && !in_array($text('deleted'), ['0','1'], true))
                || $binding['canonicalId'] !== $canonical
                || $record['deleted'] !== ($table !== 'familyhub_scopes' && !$payment && $text('deleted') === '1')) {
                throw new NativeError('crypto_migration_source_binding', 409);
            }
            // Staging requires current scoped READ and the exact current head.
            // A separate manager-signed cutover certificate is mandatory before
            // this narrow source contribution can become active provenance.
            $scopeAuthority = new NativeCryptoScopeV2($this->container, $this->bearer, $this->ip);
            [$authorizedScope, $authorizedHead] = $scopeAuthority->author(
                $scopeId, $record['membershipHeadHash'], $record['epoch'], $record['accessRevision'],
                $actor, $record['domain'], false
            );
            if ($record['type'] === 'scopeMetadata') {
                // This closed transformation omits private SQL owner/parent
                // columns from the child record. It therefore needs actual
                // management authority, beyond the ordinary READ witness path.
                $scopeAuthority->manager($authorizedHead, $authorizedScope, $actor);
            }
            $old = $this->one('SELECT * FROM familyhub_crypto_migration_stage_records_v2 WHERE migration_id=? AND source_table=? AND scope_id=? AND source_id=?',
                [$migration['id'], $table, $scopeId, $sourceId]);
            if ($old && ($old['record_proof_hash'] !== $entry['recordProofHash'] || $old['source_row_hash'] !== $binding['sourceRowHash']
                || $old['wire_id'] !== $binding['wireId'] || $old['staged_by'] !== $actor['user']['account_id'])) {
                throw new NativeError('crypto_migration_stage_immutable', 409);
            }
            $wire = $this->one('SELECT source_table,source_id FROM familyhub_crypto_migration_stage_records_v2 WHERE migration_id=? AND scope_id=? AND wire_id=?',
                [$migration['id'], $scopeId, $binding['wireId']]);
            if ($wire && ($wire['source_table'] !== $table || $wire['source_id'] !== $sourceId)) {
                throw new NativeError('crypto_migration_stage_collision', 409);
            }
            $prepared[] = [$binding, $entry, $old];
        }
        if (count($covered) !== count($records)) {
            throw new NativeError('crypto_migration_unbound_record', 409);
        }
        $requestHash = hash('sha256', NativeCryptoCodec::canonical((object)$command));
        $batchId = $params['batch']['batchId'];
        $batch = $this->one('SELECT * FROM familyhub_crypto_migration_stage_batches_v2 WHERE migration_id=? AND batch_id=?', [$migration['id'], $batchId]);
        if ($batch && ($batch['account_id'] !== $actor['user']['account_id']
            || $batch['inventory_hash'] !== $portion['inventory_hash'] || $batch['request_hash'] !== $requestHash)) {
            throw new NativeError('crypto_migration_stage_immutable', 409);
        }
        if (!$batch) {
            $this->change('INSERT INTO familyhub_crypto_migration_stage_batches_v2 VALUES(?,?,?,?,?,?,?,?)', [
                $migration['id'], $batchId, $actor['user']['account_id'], $portion['inventory_hash'], $requestHash,
                NativeCryptoCodec::canonical((object)$proof), NativeCryptoCodec::canonical((object)$params['batch']['commitment']), 'staged',
            ]);
        }
        foreach ($prepared as [$binding, $entry, $old]) {
            if ($old) {
                continue;
            }
            $this->change('INSERT INTO familyhub_crypto_migration_stage_records_v2 VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)', [
                $migration['id'], $binding['sourceTable'], $binding['scopeId'], $binding['sourceId'],
                $binding['sourceKind'], $binding['canonicalId'], $binding['wireId'], $binding['domain'], $binding['type'],
                $binding['legacyRevision'], $binding['sourceRowHash'], $entry['recordProofHash'],
                NativeCryptoCodec::canonical((object)$entry['recordProof']), NativeCryptoCodec::canonical((object)$entry['batchCommitment']),
                $actor['user']['account_id'],
            ]);
        }
        return ['migrationId' => $migration['id'], 'batchId' => $params['batch']['batchId'], 'staged' => count($prepared), 'active' => false];
    }

    private function reservedSourceId($scopeId, $namespace)
    {
        $hash = hash('sha256', 'JivieReservedRecord/v2' . "\n" . $this->serverId().':'.$scopeId.':'.$namespace);
        return substr($hash, 0, 8).'-'.substr($hash, 8, 4).'-4'.substr($hash, 13, 3).'-a'.substr($hash, 17, 3).'-'.substr($hash, 20, 12);
    }

    /** Compact transport hint, never authority. The client lazily verifies the
     * full scoped activation/certificate/witness for this exact immutable hash. */
    public function recordOrigin($sid,$wireId,$domain,$recordProofHash)
    {
        $scope=$this->one("SELECT migration_id FROM familyhub_crypto_scopes WHERE scope_id=? AND state IN ('active','committed','retired')",[$sid]);
        if(!$scope||$scope['migration_id']===null)return null;
        $activation=$this->one("SELECT activation_hash FROM familyhub_crypto_migration_activations_v3 WHERE migration_id=? AND scope_id=? AND state='committed'",[$scope['migration_id'],$sid]);
        if(!$activation)return null;
        $leaf=$this->one('SELECT leaf_hash,binding FROM familyhub_crypto_migration_domain_leaves_v2 WHERE migration_id=? AND scope_id=? AND domain=? AND record_proof_hash=?',[$scope['migration_id'],$sid,$domain,$recordProofHash]);
        if(!$leaf)return null;$body=json_decode($leaf['binding'],true,34,JSON_THROW_ON_ERROR);
        if($body['wireId']!==$wireId||$body['recordProofHash']!==$recordProofHash)throw new NativeError('crypto_migration_origin_context',409);
        return ['version'=>3,'migrationId'=>$scope['migration_id'],'leafHash'=>$leaf['leaf_hash']];
    }

    private function origin3Read($p,$actor)
    {
        $this->fields($p,['scopeId','domain','id'],['recordProofHash','recordBodyHash','afterHash','limit','evidenceFor']);
        if(isset($p['recordProofHash'])&&isset($p['recordBodyHash']))throw new NativeError('validation_error');
        $sid=$this->uuid($p['scopeId']);NativeCryptoRecordAddressV2::wireId($p['id']);
        if(isset($p['recordProofHash'])||isset($p['recordBodyHash']))$this->digest($p['recordProofHash']??$p['recordBodyHash']);
        $scopes=new NativeCryptoScopeV2($this->container,$this->bearer,$this->ip);$scope=$this->scope($sid,$actor['user']['id']);$head=$scopes->current($sid);
        if(!$head)throw new NativeError('crypto_scope_head_missing',409);
        $scopes->author($sid,$head['head_hash'],(int)$head['epoch'],(int)$scope['effective_access_revision'],$actor,$p['domain'],false);
        // Signed migration origins exist only at the genesis revision. Resolve
        // the exact retained bytes; the body selector never authenticates them.
        $recordRow=$this->one('SELECT * FROM familyhub_crypto_record_history WHERE scope_id=? AND domain=? AND id=? AND revision=1',[$sid,$p['domain'],$p['id']]);
        if(!$recordRow)throw new NativeError('crypto_migration_origin_missing',404);
        $recordProof=json_decode($recordRow['record_proof'],true,64,JSON_THROW_ON_ERROR);[$recordBody,$recordBytes]=NativeCryptoCodec::decode($recordProof);
        if(isset($p['recordBodyHash'])&&hash('sha256',$recordBytes)!==$p['recordBodyHash']||isset($p['recordProofHash'])&&$recordRow['record_proof_hash']!==$p['recordProofHash'])throw new NativeError('crypto_migration_origin_context',409);
        $p['recordProofHash']=$recordRow['record_proof_hash'];
        $availability=new NativeCryptoModerationAvailabilityV2($this->container,$this->bearer,$this->ip);
        $notice=$availability->restriction($sid,$p['id'],1,$p['recordProofHash']);
        if($notice){if(!isset($p['evidenceFor']))throw new NativeError('crypto_content_restricted',403,['unavailable'=>$notice]);$availability->evidence($recordRow,$p['evidenceFor'],$actor);}
        $hint=$this->recordOrigin($sid,$p['id'],$p['domain'],$p['recordProofHash']);if(!$hint)throw new NativeError('crypto_migration_origin_missing',404);
        $activation=$this->one("SELECT * FROM familyhub_crypto_migration_activations_v3 WHERE migration_id=? AND scope_id=? AND state='committed'",[$hint['migrationId'],$sid]);
        $leafRow=$this->one('SELECT binding FROM familyhub_crypto_migration_domain_leaves_v2 WHERE migration_id=? AND scope_id=? AND domain=? AND leaf_hash=?',[$hint['migrationId'],$sid,$p['domain'],$hint['leafHash']]);
        $leaf=json_decode($leafRow['binding'],true,34,JSON_THROW_ON_ERROR);
        $cert=$this->one("SELECT * FROM familyhub_crypto_migration_domain_attestations_v2 WHERE migration_id=? AND scope_id=? AND domain=? AND state='anchored'",[$hint['migrationId'],$sid,$p['domain']]);
        if(!$cert)throw new NativeError('crypto_migration_origin_missing',409);
        $event=$this->one('SELECT authorization FROM familyhub_crypto_directory WHERE account_id=? AND head_hash=?',[$cert['manager_account_id'],$cert['event_head_hash']]);if(!$event)throw new NativeError('crypto_migration_origin_missing',409);
        $contribution=$this->one("SELECT authorization,event_authorization FROM familyhub_crypto_migration_contributions_v3 WHERE migration_id=? AND scope_id=? AND domain=? AND account_id=? AND state='anchored'",[$hint['migrationId'],$sid,$p['domain'],$leaf['contributorAccountId']]);if(!$contribution)throw new NativeError('crypto_migration_origin_missing',409);
        $origin=$this->one('SELECT source_binding FROM familyhub_crypto_migration_origins_v3 WHERE migration_id=? AND scope_id=? AND domain=? AND record_proof_hash=? AND leaf_hash=?',[$hint['migrationId'],$sid,$p['domain'],$p['recordProofHash'],$hint['leafHash']]);
        $stageBinding=$origin?json_decode($origin['source_binding'],true,64,JSON_THROW_ON_ERROR):null;
        if(!$stageBinding||!in_array($p['recordProofHash'],[$stageBinding['recordProofHash'],...$stageBinding['companionProofHashes']],true))throw new NativeError('crypto_migration_origin_missing',409);
        [$contributionBody]=NativeCryptoCodec::decode(json_decode($contribution['authorization'],true,64,JSON_THROW_ON_ERROR));
        $controls=$this->many('SELECT binding FROM familyhub_crypto_migration_controls_v3 WHERE migration_id=? AND scope_id=? AND portion_token=? ORDER BY kind',[$hint['migrationId'],$sid,$contributionBody['payload']['header']['portionToken']]);
        if(count($controls)!==5)throw new NativeError('crypto_migration_origin_controls',409);
        $controlEvidence=$this->activation3Evidence($activation);
        $controlEvidence['controls']=array_map(static fn($r)=>json_decode($r['binding'],true,34,JSON_THROW_ON_ERROR),$controls);
        return ['version'=>3,'controlEvidence'=>$controlEvidence,'recordProof'=>$recordProof,'batchCommitment'=>json_decode($recordRow['batch_commitment'],true,64,JSON_THROW_ON_ERROR),'activationAuthorization'=>json_decode($activation['authorization'],true,64,JSON_THROW_ON_ERROR),'activationEventAuthorization'=>json_decode($activation['event_authorization'],true,64,JSON_THROW_ON_ERROR),'certificateAuthorization'=>json_decode($cert['authorization'],true,64,JSON_THROW_ON_ERROR),'certificateEventAuthorization'=>json_decode($event['authorization'],true,64,JSON_THROW_ON_ERROR),'contributionAuthorization'=>json_decode($contribution['authorization'],true,64,JSON_THROW_ON_ERROR),'contributionEventAuthorization'=>json_decode($contribution['event_authorization'],true,64,JSON_THROW_ON_ERROR),'leaf'=>$leaf,'leafHash'=>$hint['leafHash'],'sourceBinding'=>$stageBinding]+$this->domain3DigestPage($p,$hint['migrationId'],$sid,$p['domain']);
    }

    /** Reconstruct scoped final controls exclusively from exact anchored domain
     * contributors. Nothing private from verify3/local intent payloads escapes. */
    private function activation3Expected($migration,$sid)
    {
        $certs=[];$proofs=[];
        foreach(['content','finance'] as $domain){
            $row=$this->one("SELECT * FROM familyhub_crypto_migration_domain_attestations_v2 WHERE migration_id=? AND scope_id=? AND domain=? AND state='anchored'",[$migration['id'],$sid,$domain]);
            if(!$row)throw new NativeError('crypto_migration_domain_pending',409);
            $proof=json_decode($row['authorization'],true,64,JSON_THROW_ON_ERROR);[$body]=NativeCryptoCodec::decode($proof);
            if($body['operation']!=='crypto2.migration.domains.certify'||$body['payload']['header']['scopeId']!==$sid||$body['payload']['header']['domain']!==$domain)throw new NativeError('crypto_migration_activation_context',409);
            $certs[$domain]=['row'=>$row,'proof'=>$proof,'body'=>$body];$proofs[$domain]=NativeCryptoV2Codec::hash((object)$proof);
        }
        $controls=[];
        foreach($certs['content']['body']['payload']['contributions'] as $item){
            [$contribution]=NativeCryptoCodec::decode($item['authorization']);$ch=$contribution['payload']['header'];$account=$contribution['accountId'];
            $portion=$this->one('SELECT verification FROM familyhub_crypto_migration_portions_v2 WHERE migration_id=? AND account_id=?',[$migration['id'],$account]);
            $capture=$this->one("SELECT capture_id,inventory_root FROM familyhub_crypto_captures_v3 WHERE migration_id=? AND account_id=? AND state='sealed'",[$migration['id'],$account]);
            if(!$portion||!$capture)throw new NativeError('crypto_migration_activation_controls',409);
            $v=json_decode($portion['verification'],true,64,JSON_THROW_ON_ERROR);
            if(($v['version']??null)!==3||$ch['coldParityProofHash']!==NativeCryptoV2Codec::hash((object)$v['authorization'])||$ch['captureId']!==$capture['capture_id']||$ch['sourceInventoryRoot']!==$capture['inventory_root']||NativeCryptoCodec::canonical((object)$contribution['payload']['controlSections'])!==NativeCryptoCodec::canonical((object)$v['sections']))throw new NativeError('crypto_migration_activation_controls',409);
            foreach(['audit','invitations','notifications','receipts','structure'] as $kind){
                $section=$v['sections'][$kind];$certificate=null;$event=null;
                if($kind==='audit'){ $scoped=$contribution['payload']['scopeControlSections']??null;$this->fields($scoped,['audit']);$section=$scoped['audit'];$this->fields($section,['kind','count','root']);if($section['kind']!=='audit'||!is_int($section['count'])||$section['count']<0||$section['count']>9007199254740991)throw new NativeError('crypto_migration_domain_scoped_audit',409);$this->digest($section['root']); }
                if(in_array($kind,['invitations','notifications'],true)){
                    $table=$kind==='invitations'?'familyhub_crypto_invitation_certificates_v3':'familyhub_crypto_notification_certificates_v3';
                    $cert=$this->one("SELECT * FROM $table WHERE migration_id=? AND account_id=? AND state IN ('anchored','installed')",[$migration['id'],$account]);
                    if(!$cert||$cert['capture_id']!==$capture['capture_id']||$cert['source_inventory_root']!==$capture['inventory_root']||$cert['selection_root']!==$section['root']||(int)$cert[$kind==='invitations'?'bridge_count':'transform_count']!==$section['count'])throw new NativeError('crypto_migration_activation_controls',409);
                    $authorization=json_decode($cert['authorization'],true,64,JSON_THROW_ON_ERROR);[$certBody]=NativeCryptoCodec::decode($authorization);
                    if($certBody['payload']['header']['coldParityProofHash']!==$ch['coldParityProofHash'])throw new NativeError('crypto_migration_activation_controls',409);
                    $certificate=$cert['certificate_hash'];$event=$cert['event_command_hash'];
                    if(NativeCryptoCodec::canonical((object)($contribution['payload']['controlLinks'][$kind]??[]))!==NativeCryptoCodec::canonical((object)['certificateHash'=>$certificate,'eventCommandHash'=>$event]))throw new NativeError('crypto_migration_activation_controls',409);
                }
                $leaf=['version'=>3,'scopeId'=>$sid,'kind'=>$kind,'portionToken'=>$ch['portionToken'],'captureId'=>$ch['captureId'],'sourceInventoryRoot'=>$ch['sourceInventoryRoot'],'verify3ProofHash'=>$ch['coldParityProofHash'],'selectionCount'=>$section['count'],'selectionRoot'=>$section['root'],'certificateHash'=>$certificate,'eventCommandHash'=>$event];
                $hash=NativeCryptoMigrationActivationV3::controlHash($leaf);if(isset($controls[$hash]))throw new NativeError('crypto_migration_activation_controls',409);$controls[$hash]=$leaf;
            }
        }
        if(count($controls)<5||count($controls)>5000)throw new NativeError('crypto_migration_activation_capacity',409);
        ksort($controls,SORT_STRING);
        return ['certificates'=>$certs,'certificateHashes'=>$proofs,'controls'=>$controls];
    }

    /** Opaque routing candidates only; commit3 independently reconstructs the
     * exact complete frozen scope set and revalidates every manager and event. */
    private function activation3Refs($p,$actor)
    {
        $this->fields($p,['migrationId'],['afterScopeToken','limit']);
        [$migration]=$this->migration($this->uuid($p['migrationId']),$actor);
        $component=$this->captureCommitments($migration);
        $after=$p['afterScopeToken']??'';if($after!=='')$this->digest($after);
        $limit=$p['limit']??50;if(!is_int($limit)||$limit<1||$limit>50)throw new NativeError('invalid_cursor');
        $scopes=json_decode($migration['scope_ids'],true,34,JSON_THROW_ON_ERROR);
        if(!$scopes||count($scopes)>1000)throw new NativeError('crypto_migration_activation_capacity',409);
        $refs=[];
        foreach($scopes as $sid){
            $row=$this->one('SELECT activation_hash,authorization,event_authorization FROM familyhub_crypto_migration_activations_v3 WHERE migration_id=? AND scope_id=?',[$migration['id'],$sid]);
            if(!$row)throw new NativeError('crypto_migration_activation_pending',409);
            $proof=json_decode($row['authorization'],true,64,JSON_THROW_ON_ERROR);
            [$header]=NativeCryptoCodec::decode($proof);NativeCryptoMigrationActivationV3::validate($header);
            if($header['scopeId']!==$sid||$header['migrationId']!==$migration['id']||$header['componentCommitment']!==$component['componentCommitment']||$header['inventoryCommitment']!==$component['inventoryCommitment']||NativeCryptoV2Codec::hash((object)$proof)!==$row['activation_hash'])throw new NativeError('crypto_migration_activation_context',409);
            $event=json_decode($row['event_authorization'],true,64,JSON_THROW_ON_ERROR);[$eventBody]=NativeCryptoCodec::decode($event);
            $stored=$this->one('SELECT authorization FROM familyhub_crypto_directory WHERE account_id=? AND command_hash=?',[$header['managerAccountId'],hash('sha256',NativeCryptoCodec::base64($event['commandBase64'],NativeCryptoCodec::MAX_COMMAND))]);
            if(!$stored||NativeCryptoCodec::canonical(json_decode($stored['authorization'],true,64,JSON_THROW_ON_ERROR))!==NativeCryptoCodec::canonical($event)||($eventBody['operation']??null)!=='crypto2.account.migrationAttest'||($eventBody['payload']['attestationHash']??null)!==$row['activation_hash'])throw new NativeError('crypto_migration_activation_pending',409);
            $token=NativeCryptoMigrationCommitmentsV3::scopeToken($this->serverId(),$migration['id'],$sid,'content');
            if(isset($refs[$token]))throw new NativeError('crypto_migration_activation_context',409);
            $refs[$token]=['scopeToken'=>$token,'activationHash'=>$row['activation_hash']];
        }
        ksort($refs,SORT_STRING);$selected=[];
        foreach($refs as $token=>$ref)if(strcmp($token,$after)>0){$selected[]=$ref;if(count($selected)>$limit)break;}
        $more=count($selected)>$limit;if($more)array_pop($selected);
        return ['version'=>3,'candidate'=>true,'migrationId'=>$migration['id'],'inventoryCommitment'=>$component['inventoryCommitment'],'componentCommitment'=>$component['componentCommitment'],'scopeActivations'=>$selected,'hasMore'=>$more,'nextAfterScopeToken'=>$selected?end($selected)['scopeToken']:null];
    }

    private function activation3Read($operation,$p,$actor)
    {
        $this->fields($p,['scopeId'],['afterHash','limit','controlHash']);$sid=$this->uuid($p['scopeId']);
        $scope=$this->scope($sid,$actor['user']['id']);$scopes=new NativeCryptoScopeV2($this->container,$this->bearer,$this->ip);$head=$scopes->current($sid);
        if(!$head)throw new NativeError('crypto_scope_head_missing',409);
        $row=$this->one('SELECT a.* FROM familyhub_crypto_migration_activations_v3 a JOIN familyhub_crypto_scopes s ON s.scope_id=a.scope_id AND s.migration_id=a.migration_id WHERE a.scope_id=?',[$sid]);
        if($row&&$row['state']==='committed')return $this->activation3Evidence($row,$p);
        $scopes->manager($head,$scope,$actor);
        $migrationRow=$this->one("SELECT m.id FROM familyhub_crypto_migrations_v2 m JOIN familyhub_crypto_scopes s ON s.migration_id=m.id WHERE m.state='verified' AND s.scope_id=?",[$sid]);
        if(!$migrationRow)throw new NativeError('crypto_migration_activation_pending',409);
        [$migration]=$this->migration($migrationRow['id'],$actor);$this->unchanged($migration);
        $expected=$this->activation3Expected($migration,$sid);$component=$this->captureCommitments($migration);
        $directory=(new NativeCryptoDirectoryV2($this->container))->current($actor['user']['account_id']);
        $h=['version'=>3,'serverId'=>$this->serverId(),'migrationId'=>$migration['id'],'componentId'=>$migration['component_id'],'componentCommitment'=>$component['componentCommitment'],'inventoryCommitment'=>$component['inventoryCommitment'],'scopeId'=>$sid,'membershipHeadHash'=>$head['head_hash'],'lifecycleHash'=>(new NativeCryptoLifecycleV2($this->container))->closingHash($sid),'managerAccountId'=>$actor['user']['account_id'],'managerDirectoryHeadHash'=>$directory['head_hash'],'contentCertificateHash'=>$expected['certificateHashes']['content'],'financeCertificateHash'=>$expected['certificateHashes']['finance'],'controlCount'=>count($expected['controls']),'controlRoot'=>NativeCryptoDirectoryV2::ZERO];
        $h['controlRoot']=NativeCryptoMigrationActivationV3::controlRoot($h,array_keys($expected['controls']));
        $after=$p['afterHash']??'';if($after!=='')$this->digest($after);$limit=$p['limit']??20;if(!is_int($limit)||$limit<1||$limit>20)throw new NativeError('invalid_cursor');
        $selected=[];foreach($expected['controls'] as $hash=>$leaf)if(strcmp($hash,$after)>0){$selected[]=['controlHash'=>$hash,'control'=>$leaf];if(count($selected)>$limit)break;}
        $more=count($selected)>$limit;if($more)array_pop($selected);
        $events=[];foreach($expected['certificates'] as $domain=>$cert){$event=$this->one('SELECT authorization FROM familyhub_crypto_directory WHERE account_id=? AND head_hash=?',[$cert['row']['manager_account_id'],$cert['row']['event_head_hash']]);if(!$event)throw new NativeError('crypto_migration_domain_pending',409);$events[$domain]=json_decode($event['authorization'],true,64,JSON_THROW_ON_ERROR);}
        return ['version'=>3,'candidate'=>true,'header'=>$h,'domainCertificates'=>array_map(static fn($c)=>$c['proof'],$expected['certificates']),'domainEvents'=>$events,'controls'=>$selected,'hasMore'=>$more,'nextAfterHash'=>$selected?end($selected)['controlHash']:null];
    }

    /** Current READ is required by the public wrapper. Token recipients use a
     * separate exact retained invitation route returning only their control. */
    public function activation3Evidence($row,$p=[])
    {
        if($row['state']!=='committed')throw new NativeError('crypto_migration_activation_pending',409);
        $proof=json_decode($row['authorization'],true,64,JSON_THROW_ON_ERROR);[$header]=NativeCryptoCodec::decode($proof);NativeCryptoMigrationActivationV3::validate($header);
        $hashes=[];$after='';do{$page=$this->many('SELECT control_hash FROM familyhub_crypto_migration_controls_v3 WHERE migration_id=? AND scope_id=? AND control_hash>? ORDER BY control_hash LIMIT 50',[$row['migration_id'],$row['scope_id'],$after]);foreach($page as $r){$after=$r['control_hash'];$hashes[]=$after;if(count($hashes)>5000)throw new NativeError('crypto_migration_activation_capacity',409);}}while(count($page)===50);
        if(count($hashes)!==$header['controlCount']||NativeCryptoMigrationActivationV3::controlRoot($header,$hashes)!==$header['controlRoot'])throw new NativeError('crypto_migration_activation_controls',409);
        $result=['version'=>3,'candidate'=>false,'authorization'=>$proof,'eventAuthorization'=>json_decode($row['event_authorization'],true,64,JSON_THROW_ON_ERROR),'activationHash'=>$row['activation_hash'],'controlDigests'=>$hashes];
        if(isset($p['controlHash'])){$this->digest($p['controlHash']);$leaf=$this->one('SELECT binding FROM familyhub_crypto_migration_controls_v3 WHERE migration_id=? AND scope_id=? AND control_hash=?',[$row['migration_id'],$row['scope_id'],$p['controlHash']]);if(!$leaf)throw new NativeError('crypto_migration_activation_control_missing',404);$result['control']=json_decode($leaf['binding'],true,34,JSON_THROW_ON_ERROR);}
        return $result;
    }

    private function activation3Stage($p,$actor)
    {
        $this->fields($p,['authorization','eventAuthorization']);[$h,$raw,$signature]=NativeCryptoCodec::decode($p['authorization']);NativeCryptoMigrationActivationV3::validate($h);
        [$migration,$portion]=$this->migration($h['migrationId'],$actor);$this->unchanged($migration);
        $component=$this->captureCommitments($migration);
        if($h['serverId']!==$this->serverId()||$h['componentId']!==$migration['component_id']||$h['componentCommitment']!==$component['componentCommitment']||$h['inventoryCommitment']!==$component['inventoryCommitment']||!in_array($h['scopeId'],json_decode($migration['scope_ids'],true,34,JSON_THROW_ON_ERROR),true)||$h['managerAccountId']!==$actor['user']['account_id'])throw new NativeError('crypto_migration_activation_context',409);
        $scopes=new NativeCryptoScopeV2($this->container,$this->bearer,$this->ip);$head=$scopes->current($h['scopeId']);$scope=$this->scope($h['scopeId'],$actor['user']['id']);
        if(!$head||$head['head_hash']!==$h['membershipHeadHash']||(new NativeCryptoLifecycleV2($this->container))->closingHash($h['scopeId'])!==$h['lifecycleHash'])throw new NativeError('crypto_migration_authority_changed',409);
        $scopes->manager($head,$scope,$actor);$scopes->currentAuthorReference($h['managerDirectoryHeadHash'],$actor);
        [$event]=NativeCryptoCodec::decode($p['eventAuthorization']);$device=$event['deviceId'];$directory=new NativeCryptoDirectoryV2($this->container,$this->bearer,$this->ip);$current=$directory->current($actor['user']['account_id']);$key=$directory->device(json_decode($current['snapshot'],true,34,JSON_THROW_ON_ERROR),$device);
        $retainedKey=NativeCryptoMigrationGenerationV3::retainedSigningKey($this->pdo,$p['authorization'],$actor['user']['account_id']);
        if($retainedKey===null&&(!$key||$key['revokedGeneration']!==null||$device!==$actor['device']['id']))throw new NativeError('crypto_device_unapproved',403);
        NativeCryptoV2Codec::verify($raw,$signature,$retainedKey??$key['signingKeyBase64'],"JivieMigrationActivation/v3\n");
        $hash=NativeCryptoV2Codec::hash((object)$p['authorization']);$this->businessOwnEvent($event,$p['eventAuthorization'],$actor,$migration['id'],'content',NativeCryptoMigrationActivationV3::token($h),$hash);
        $expected=$this->activation3Expected($migration,$h['scopeId']);
        if($h['contentCertificateHash']!==$expected['certificateHashes']['content']||$h['financeCertificateHash']!==$expected['certificateHashes']['finance']||$h['controlCount']!==count($expected['controls'])||$h['controlRoot']!==NativeCryptoMigrationActivationV3::controlRoot($h,array_keys($expected['controls'])))throw new NativeError('crypto_migration_activation_controls',409);
        $old=$this->one('SELECT activation_hash FROM familyhub_crypto_migration_activations_v3 WHERE migration_id=? AND scope_id=?',[$migration['id'],$h['scopeId']]);
        if($old&&$old['activation_hash']!==$hash)throw new NativeError('crypto_migration_activation_immutable',409);
        if(!$old){$this->change('INSERT INTO familyhub_crypto_migration_activations_v3(migration_id,scope_id,activation_hash,membership_head_hash,lifecycle_hash,manager_account_id,authorization,event_authorization,control_count,control_root,state) VALUES(?,?,?,?,?,?,?,?,?,?,?)',[$migration['id'],$h['scopeId'],$hash,$h['membershipHeadHash'],$h['lifecycleHash'],$h['managerAccountId'],NativeCryptoCodec::canonical((object)$p['authorization']),NativeCryptoCodec::canonical((object)$p['eventAuthorization']),$h['controlCount'],$h['controlRoot'],'staged']);
            foreach($expected['controls'] as $digest=>$leaf)$this->change('INSERT INTO familyhub_crypto_migration_controls_v3(migration_id,scope_id,control_hash,kind,portion_token,certificate_hash,binding) VALUES(?,?,?,?,?,?,?)',[$migration['id'],$h['scopeId'],$digest,$leaf['kind'],$leaf['portionToken'],$leaf['certificateHash'],NativeCryptoCodec::canonical((object)$leaf)]);
        }
        return ['version'=>3,'activationHash'=>$hash,'state'=>'staged'];
    }

    private function structureContextGuard($p,$actor)
    {
        [$migration,$portion]=$this->migration($p['migrationId']??null,$actor);
        $this->archiveAccess($migration,$portion,$actor);$this->unchanged($migration);
        $capture=$this->captureRow($migration,$actor);
        if($capture['state']!=='sealed'||$capture['capture_id']!==($p['captureId']??null)||$capture['inventory_root']!==($p['sourceInventoryRoot']??null))throw new NativeError('crypto_capture_generation_conflict',409);
    }

    /** Domain3 staging joins already FILE-verified portions. Manager-only
     * responses expose opaque digests, never another domain's source leaves. */
    private function domain3($operation,$p,$actor,$proof=null)
    {
        if ($operation==='crypto2.migration.domains.prepare') {
            $this->fields($p,['header','assignments']);$h=$p['header'];
            NativeCryptoMigrationCommitmentsV3::validateHeader($h);
            [$migration,$portion]=$this->migration($h['migrationId'],$actor);
            $this->unchanged($migration);$components=$this->captureCommitments($migration);
            if ($h['serverId']!==$this->serverId() || $h['componentId']!==$migration['component_id'] ||
                $h['componentCommitment']!==$components['componentCommitment'] || $h['inventoryCommitment']!==$components['inventoryCommitment'] ||
                !in_array($h['scopeId'],json_decode($migration['scope_ids'],true,34,JSON_THROW_ON_ERROR),true) ||
                $h['managerAccountId']!==$actor['user']['account_id']) throw new NativeError('crypto_migration_domain_context',409);
            $scopes=new NativeCryptoScopeV2($this->container,$this->bearer,$this->ip);
            $scope=$this->scope($h['scopeId'],$actor['user']['id']);$head=$scopes->current($h['scopeId']);
            if (!$head || $head['head_hash']!==$h['membershipHeadHash']) throw new NativeError('crypto_scope_head_changed',409);
            $scopes->manager($head,$scope,$actor);$scopes->currentAuthorReference($h['managerDirectoryHeadHash'],$actor);
            // The sanitized metadata exception belongs to the exact captured
            // owner transformation, not an arbitrary later READ contributor.
            if ((int)$scope['owner_id']!==(int)$actor['user']['id']) throw new NativeError('crypto_migration_domain_manager',403);
            if ((int)$this->one("SELECT COUNT(*) n FROM familyhub_crypto_migration_portions_v2 WHERE migration_id=? AND state<>'verified'",[$migration['id']])['n']!==0) throw new NativeError('crypto_migration_contributions_pending',409);
            $assignments=$this->domain3Assignments($migration,$h['scopeId'],$h['domain']);
            if(NativeCryptoCodec::canonical($p['assignments'])!==NativeCryptoCodec::canonical($assignments))throw new NativeError('crypto_migration_domain_assignment',409);
            $counts=$this->domain3Counts($migration['id'],$h['scopeId'],$h['domain']);
            if ($h['sourceRowCount']!==$counts['sources'] || $h['materializedRecordProofCount']!==$counts['records']) throw new NativeError('crypto_migration_domain_coverage',409);
            $old=$this->one('SELECT * FROM familyhub_crypto_migration_domain_attestations_v2 WHERE migration_id=? AND scope_id=? AND domain=?',[$migration['id'],$h['scopeId'],$h['domain']]);
            if ($old) {
                $saved=json_decode($old['authorization'],true,64,JSON_THROW_ON_ERROR);[$body]=NativeCryptoCodec::decode($saved);
                if (($body['payload']['header']??null)!==$h) throw new NativeError('crypto_migration_domain_immutable',409);
            } else $this->change('INSERT INTO familyhub_crypto_migration_domain_attestations_v2 (migration_id,scope_id,domain,root_hash,source_row_count,materialized_count,membership_head_hash,manager_account_id,manager_directory_head_hash,authorization,event_head_hash,state) VALUES(?,?,?,?,?,?,?,?,?,?,NULL,?)',
                [$migration['id'],$h['scopeId'],$h['domain'],NativeCryptoDirectoryV2::ZERO,$h['sourceRowCount'],$h['materializedRecordProofCount'],$h['membershipHeadHash'],$h['managerAccountId'],$h['managerDirectoryHeadHash'],NativeCryptoCodec::canonical((object)$proof),'prepared']);
            return ['version'=>3,'header'=>$h,'headerHash'=>NativeCryptoMigrationCommitmentsV3::headerHash($h),'state'=>'prepared'];
        }
        $required=match($operation){'crypto2.migration.domains.contribute'=>['header','leafSetRoot','controlSections','scopeControlSections','controlLinks'],'crypto2.migration.domains.certify'=>['header','assignments','domainRoot','contributions'],'crypto2.migration.domains.anchor'=>['migrationId','scopeId','domain','certificateHash','eventAuthorization'],default=>['migrationId','scopeId','domain']};
        if ($operation==='crypto2.migration.domains.anchorContribution') $required=array_merge($required,['contributionHash','eventAuthorization']);
        $this->fields($p,$required,in_array($operation,['crypto2.migration.domains.leaves','crypto2.migration.domains.get'],true)?['afterHash','limit']:[]);
        $migrationId=$p['migrationId']??($p['header']['migrationId']??null);
        [$migration,$portion]=$this->migration($migrationId,$actor);if($operation!=='crypto2.migration.domains.leaves'&&!($operation==='crypto2.migration.domains.get'&&isset($p['afterHash'])))$this->unchanged($migration);
        $sid=$p['scopeId']??($p['header']['scopeId']??null);$domain=$p['domain']??($p['header']['domain']??null);
        if ($sid===null) {
            // scopeToken, not a raw source coordinate, selects the exact prepared
            // scope. Never infer an ambiguous first domain row.
            $candidate=null;
            foreach (json_decode($migration['scope_ids'],true,34,JSON_THROW_ON_ERROR) as $id) if (NativeCryptoMigrationCommitmentsV3::scopeToken($this->serverId(),$migrationId,$id,$domain)===($p['header']['scopeToken']??null)) {if($candidate!==null)throw new NativeError('crypto_migration_domain_context',409);$candidate=$id;}
            $sid=$candidate;
        }
        $this->uuid($sid);if(!in_array($domain,['content','finance'],true))throw new NativeError('validation_error');
        $row=$this->one('SELECT * FROM familyhub_crypto_migration_domain_attestations_v2 WHERE migration_id=? AND scope_id=? AND domain=?',[$migrationId,$sid,$domain]);
        if(!$row && $operation==='crypto2.migration.domains.get') {
            $scope=$this->scope($sid,$actor['user']['id']);$scopes=new NativeCryptoScopeV2($this->container,$this->bearer,$this->ip);$head=$scopes->current($sid);
            if(!$head)throw new NativeError('crypto_scope_head_missing',409);$scopes->manager($head,$scope,$actor);
            if(!in_array($sid,json_decode($migration['scope_ids'],true,34,JSON_THROW_ON_ERROR),true)||(int)$scope['owner_id']!==(int)$actor['user']['id'])throw new NativeError('crypto_migration_domain_manager',403);
            $component=$this->captureCommitments($migration);$counts=$this->domain3Counts($migrationId,$sid,$domain);$directory=(new NativeCryptoDirectoryV2($this->container))->current($actor['user']['account_id']);
            $h=['version'=>3,'serverId'=>$this->serverId(),'migrationId'=>$migrationId,'componentId'=>$migration['component_id'],'componentCommitment'=>$component['componentCommitment'],'inventoryCommitment'=>$component['inventoryCommitment'],'scopeId'=>$sid,'scopeToken'=>NativeCryptoMigrationCommitmentsV3::scopeToken($this->serverId(),$migrationId,$sid,$domain),'domain'=>$domain,'membershipHeadHash'=>$head['head_hash'],'managerAccountId'=>$actor['user']['account_id'],'managerDirectoryHeadHash'=>$directory['head_hash'],'sourceRowCount'=>$counts['sources'],'materializedRecordProofCount'=>$counts['records']];
            NativeCryptoMigrationCommitmentsV3::validateHeader($h);
            return ['version'=>3,'header'=>$h,'prepareAuthorization'=>null,'contributorAccounts'=>array_column($this->domain3Assignments($migration,$sid,$domain),'accountId'),'assignments'=>$this->domain3Assignments($migration,$sid,$domain),'contributions'=>[]];
        }
        if(!$row)throw new NativeError('crypto_migration_domain_pending',409);
        $prepare=json_decode($row['authorization'],true,64,JSON_THROW_ON_ERROR);[$prepared]=NativeCryptoCodec::decode($prepare);$h=$prepared['payload']['header'];
        NativeCryptoMigrationCommitmentsV3::validateHeader($h);
        $scope=$this->scope($sid,$actor['user']['id']);$scopes=new NativeCryptoScopeV2($this->container,$this->bearer,$this->ip);$head=$scopes->current($sid);
        if(!$head||$head['head_hash']!==$h['membershipHeadHash'])throw new NativeError('crypto_scope_head_changed',409);
        $assignments=$this->domain3Assignments($migration,$sid,$domain,['sources'=>(int)$row['source_row_count'],'records'=>(int)$row['materialized_count']]);
        $savedAssignments=$prepared['payload']['assignments']??null;
        if(NativeCryptoCodec::canonical($savedAssignments)!==NativeCryptoCodec::canonical($assignments))throw new NativeError('crypto_migration_domain_assignment',409);
        $assigned=$this->domain3Contributor($migration,$sid,$domain);
        if(in_array($operation,['crypto2.migration.domains.certify','crypto2.migration.domains.anchor'],true))return $this->domain3Certificate($operation,$p,$actor,$proof,$migration,$row,$h,$head,$scope,$assignments);
        if ($operation==='crypto2.migration.domains.get') {
            $scopes->manager($head,$scope,$actor);
            $items=$this->many("SELECT account_id,authorization,event_authorization,state FROM familyhub_crypto_migration_contributions_v3 WHERE migration_id=? AND scope_id=? AND domain=? AND state<>'candidate' ORDER BY account_id",[$migrationId,$sid,$domain]);
            return ['version'=>3,'header'=>$h,'prepareAuthorization'=>$prepare,'contributorAccounts'=>array_column($assignments,'accountId'),'assignments'=>$assignments,
                'contributions'=>array_map(static fn($r)=>['accountId'=>$r['account_id'],'authorization'=>json_decode($r['authorization'],true,64,JSON_THROW_ON_ERROR),'eventAuthorization'=>$r['event_authorization']===null?null:json_decode($r['event_authorization'],true,64,JSON_THROW_ON_ERROR),'state'=>$r['state']],$items)]+$this->domain3DigestPage($p,$migrationId,$sid,$domain);
        }
        $ownAssignment=null;foreach($assignments as $assignment)if($assignment['accountId']===$actor['user']['account_id'])$ownAssignment=$assignment;
        if($ownAssignment===null&&$operation==='crypto2.migration.domains.leaves'){
            $member=$scopes->member($scopes->body($head),$actor['user']['account_id']);
            if($domain==='finance'&&($member['financeRole']??'none')==='none')$scopes->manager($head,$scope,$actor);
            else $scopes->author($sid,$head['head_hash'],(int)$head['epoch'],(int)$scope['effective_access_revision'],$actor,$domain,false);
            return ['version'=>3,'header'=>$h,'prepareAuthorization'=>$prepare,'assignment'=>null,'leaves'=>[],'nextAfterHash'=>null,'hasMore'=>false];
        }
        if($ownAssignment===null)throw new NativeError('crypto_migration_domain_contributor',403);
        $assigned=$actor['user']['account_id'];
        $capture=$this->captureRow($migration,$actor);
        $verification=$portion['verification']?json_decode($portion['verification'],true,64,JSON_THROW_ON_ERROR):null;
        if($portion['state']!=='verified'||($verification['version']??null)!==3||$capture['state']!=='sealed')throw new NativeError('crypto_migration_verification_pending',409);
        $count=['sources'=>$ownAssignment['sourceRowCount'],'records'=>$ownAssignment['leafCount']];
        $scopeMember=$scopes->member($scopes->body($head),$assigned);
        if($domain==='content' || ($scopeMember['financeRole']??'none')!=='none')$scopes->author($sid,$head['head_hash'],(int)$head['epoch'],(int)$scope['effective_access_revision'],$actor,$domain,false);
        elseif($count['records']===0)$scopes->manager($head,$scope,$actor); // Exact independently empty, no eligible READ fallback only.
        else throw new NativeError('crypto_migration_contributor_unavailable',409);
        if($operation==='crypto2.migration.domains.anchorContribution') {
            $this->digest($p['contributionHash']);
            $own=$this->one('SELECT * FROM familyhub_crypto_migration_contributions_v3 WHERE migration_id=? AND scope_id=? AND domain=? AND account_id=?',[$migrationId,$sid,$domain,$assigned]);
            if(!$own)throw new NativeError('crypto_migration_domain_pending',409);
            $authorization=json_decode($own['authorization'],true,64,JSON_THROW_ON_ERROR);
            if(NativeCryptoV2Codec::hash((object)$authorization)!==$p['contributionHash'])throw new NativeError('crypto_migration_domain_context',409);
            [$event]=NativeCryptoCodec::decode($p['eventAuthorization']);
            $this->businessOwnEvent($event,$p['eventAuthorization'],$actor,$migrationId,$domain,$h['scopeToken'],$p['contributionHash']);
            $eventHash=hash('sha256',NativeCryptoCodec::base64($p['eventAuthorization']['commandBase64'],NativeCryptoCodec::MAX_COMMAND));
            $entry=$this->one('SELECT head_hash FROM familyhub_crypto_directory WHERE account_id=? AND command_hash=?',[$assigned,$eventHash]);
            if($own['event_authorization']!==null&&NativeCryptoCodec::canonical(json_decode($own['event_authorization']))!==NativeCryptoCodec::canonical((object)$p['eventAuthorization']))throw new NativeError('crypto_migration_domain_immutable',409);
            $this->change("UPDATE familyhub_crypto_migration_contributions_v3 SET event_head_hash=?,event_command_hash=?,event_authorization=?,state='anchored' WHERE migration_id=? AND scope_id=? AND domain=? AND account_id=?",[$entry['head_hash'],$eventHash,NativeCryptoCodec::canonical((object)$p['eventAuthorization']),$migrationId,$sid,$domain,$assigned]);
            return ['version'=>3,'contributionHash'=>$p['contributionHash'],'state'=>'anchored'];
        }
        $candidate=$this->domain3Candidates($migration,$capture,$actor,$h,$verification,$count);
        if($operation==='crypto2.migration.domains.leaves') {
            $after=$p['afterHash']??'';if($after!=='')$this->digest($after);$limit=$p['limit']??20;if(!is_int($limit)||$limit<1||$limit>20)throw new NativeError('invalid_cursor');
            $page=$this->many('SELECT leaf_hash,binding FROM familyhub_crypto_migration_domain_leaves_v2 WHERE migration_id=? AND scope_id=? AND domain=? AND leaf_hash>? ORDER BY leaf_hash LIMIT '.($limit+1),[$migrationId,$sid,$domain,$after]);
            $more=count($page)>$limit;if($more)array_pop($page);if($count['records']===0){$page=[];$more=false;}$selected=[];foreach($page as $leaf)$selected[]=['leafHash'=>$leaf['leaf_hash'],'leaf'=>json_decode($leaf['binding'],true,34,JSON_THROW_ON_ERROR)];
            return ['version'=>3,'header'=>$h,'prepareAuthorization'=>$prepare,'assignment'=>$ownAssignment,'leaves'=>$selected,'nextAfterHash'=>$selected?end($selected)['leafHash']:null,'hasMore'=>$more];
        }
        if(NativeCryptoCodec::canonical((object)$p['controlSections'])!==NativeCryptoCodec::canonical((object)$verification['sections']))throw new NativeError('crypto_migration_domain_control_sections',409);
        $this->fields($p['scopeControlSections'],['audit']);
        $scopedAudit=(new NativeCryptoMigrationAuditV3($this->container,$this->bearer,$this->ip))->scopedCoverage($migrationId,$capture['capture_id'],$capture['inventory_root'],$sid,$actor,[$this,'captureSourceBindings'],[$this,'captureSourceBinding']);
        if(NativeCryptoCodec::canonical((object)$p['scopeControlSections']['audit'])!==NativeCryptoCodec::canonical((object)$scopedAudit))throw new NativeError('crypto_migration_domain_scoped_audit',409);
        if(NativeCryptoCodec::canonical((object)$p['controlLinks'])!==NativeCryptoCodec::canonical((object)$this->domain3ControlLinks($migrationId,$actor['user']['account_id'],$p['header']['captureId'],$p['header']['sourceInventoryRoot'],$p['header']['coldParityProofHash'],$verification['sections'])))throw new NativeError('crypto_migration_domain_control_links',409);
        $ch=$p['header'];$expected=['version'=>3,'serverId'=>$this->serverId(),'migrationId'=>$migrationId,'scopeToken'=>$h['scopeToken'],'domain'=>$domain,'headerHash'=>NativeCryptoMigrationCommitmentsV3::headerHash($h),'portionToken'=>NativeCryptoMigrationProvenanceV2::portionToken($this->serverId(),$migrationId,$assigned),'captureId'=>$capture['capture_id'],'sourceInventoryRoot'=>$capture['inventory_root'],'coldParityProofHash'=>NativeCryptoV2Codec::hash((object)$verification['authorization']),'leafCount'=>$count['records'],'sourceRowCount'=>$count['sources'],'authorDirectoryHeadHash'=>$ch['authorDirectoryHeadHash']??null];
        if(NativeCryptoCodec::canonical((object)$ch)!==NativeCryptoCodec::canonical((object)$expected) || $p['leafSetRoot']!==NativeCryptoMigrationCommitmentsV3::contributionRoot($ch,$count['records']===0?[]:$this->domain3Digests($migrationId,$sid,$domain)))throw new NativeError('crypto_migration_domain_coverage',409);
        $scopes->currentAuthorReference($ch['authorDirectoryHeadHash'],$actor);
        $old=$this->one('SELECT authorization,state FROM familyhub_crypto_migration_contributions_v3 WHERE migration_id=? AND scope_id=? AND domain=? AND account_id=?',[$migrationId,$sid,$domain,$assigned]);
        if($old&&$old['state']!=='candidate'&&NativeCryptoCodec::canonical(json_decode($old['authorization']))!==NativeCryptoCodec::canonical((object)$proof))throw new NativeError('crypto_migration_domain_immutable',409);
        if($old&&$old['state']==='candidate')$this->change("UPDATE familyhub_crypto_migration_contributions_v3 SET authorization=?,state='staged',leaf_root=? WHERE migration_id=? AND scope_id=? AND domain=? AND account_id=?",[NativeCryptoCodec::canonical((object)$proof),$p['leafSetRoot'],$migrationId,$sid,$domain,$assigned]);
        if(!$old)$this->change('INSERT INTO familyhub_crypto_migration_contributions_v3 (migration_id,scope_id,domain,account_id,capture_id,header_hash,leaf_root,leaf_count,source_count,authorization,event_head_hash,event_command_hash,event_authorization,state) VALUES(?,?,?,?,?,?,?,?,?,?,NULL,NULL,NULL,?)',[$migrationId,$sid,$domain,$assigned,$capture['capture_id'],$ch['headerHash'],$p['leafSetRoot'],$count['records'],$count['sources'],NativeCryptoCodec::canonical((object)$proof),'staged']);
        return ['version'=>3,'header'=>$ch,'leafSetRoot'=>$p['leafSetRoot'],'contributionHash'=>NativeCryptoV2Codec::hash((object)$proof),'state'=>'staged'];
    }

    private function domain3ControlLinks($migrationId,$account,$captureId,$root,$coldHash,$sections)
    {
        $links=[];
        foreach(['invitations','notifications'] as $kind){
            $table=$kind==='invitations'?'familyhub_crypto_invitation_certificates_v3':'familyhub_crypto_notification_certificates_v3';
            $row=$this->one("SELECT * FROM $table WHERE migration_id=? AND account_id=? AND state IN ('anchored','installed')",[$migrationId,$account]);
            if(!$row||$row['capture_id']!==$captureId||$row['source_inventory_root']!==$root||$row['selection_root']!==$sections[$kind]['root']||(int)$row[$kind==='invitations'?'bridge_count':'transform_count']!==$sections[$kind]['count'])throw new NativeError('crypto_migration_domain_control_links',409);
            [$cert]=NativeCryptoCodec::decode(json_decode($row['authorization'],true,64,JSON_THROW_ON_ERROR));
            if($cert['payload']['header']['coldParityProofHash']!==$coldHash)throw new NativeError('crypto_migration_domain_control_links',409);
            $links[$kind]=['certificateHash'=>$row['certificate_hash'],'eventCommandHash'=>$row['event_command_hash']];
        }
        return $links;
    }

    private function domain3DigestPage($p,$migrationId,$sid,$domain)
    {
        $after=$p['afterHash']??'';if($after!=='')$this->digest($after);$limit=$p['limit']??20;if(!is_int($limit)||$limit<1||$limit>50)throw new NativeError('invalid_cursor');
        $rows=$this->many('SELECT leaf_hash FROM familyhub_crypto_migration_domain_leaves_v2 WHERE migration_id=? AND scope_id=? AND domain=? AND leaf_hash>? ORDER BY leaf_hash LIMIT '.($limit+1),[$migrationId,$sid,$domain,$after]);
        $more=count($rows)>$limit;if($more)array_pop($rows);$hashes=array_column($rows,'leaf_hash');
        return ['leafDigests'=>$hashes,'nextAfterHash'=>$hashes?end($hashes):null,'hasMore'=>$more];
    }

    private function domain3Certificate($operation,$p,$actor,$proof,$migration,$row,$h,$head,$scope,$assignments,$validateOnly=false)
    {
        $scopes=new NativeCryptoScopeV2($this->container,$this->bearer,$this->ip);$scopes->manager($head,$scope,$actor);
        if($h['managerAccountId']!==$actor['user']['account_id'])throw new NativeError('crypto_migration_domain_manager',403);
        $scopes->currentAuthorReference($h['managerDirectoryHeadHash'],$actor);
        $migrationId=$migration['id'];$sid=$h['scopeId'];$domain=$h['domain'];
        if($operation==='crypto2.migration.domains.anchor') {
            if(!in_array($row['state'],['certified','anchored'],true))throw new NativeError('crypto_migration_domain_pending',409);
            $cert=json_decode($row['authorization'],true,64,JSON_THROW_ON_ERROR);$hash=NativeCryptoV2Codec::hash((object)$cert);
            if($hash!==$p['certificateHash'])throw new NativeError('crypto_migration_domain_context',409);
            [$event]=NativeCryptoCodec::decode($p['eventAuthorization']);$this->businessOwnEvent($event,$p['eventAuthorization'],$actor,$migrationId,$domain,$h['scopeToken'],$hash);
            $commandHash=hash('sha256',NativeCryptoCodec::base64($p['eventAuthorization']['commandBase64'],NativeCryptoCodec::MAX_COMMAND));$entry=$this->one('SELECT head_hash FROM familyhub_crypto_directory WHERE account_id=? AND command_hash=?',[$actor['user']['account_id'],$commandHash]);
            if($row['event_head_hash']!==null&&$row['event_head_hash']!==$entry['head_hash'])throw new NativeError('crypto_migration_domain_immutable',409);
            $this->change("UPDATE familyhub_crypto_migration_domain_attestations_v2 SET event_head_hash=?,state='anchored' WHERE migration_id=? AND scope_id=? AND domain=?",[$entry['head_hash'],$migrationId,$sid,$domain]);
            return ['version'=>3,'certificateHash'=>$hash,'domainRoot'=>$row['root_hash'],'eventHeadHash'=>$entry['head_hash'],'state'=>'anchored'];
        }
        if(NativeCryptoCodec::canonical((object)$p['header'])!==NativeCryptoCodec::canonical((object)$h))throw new NativeError('crypto_migration_domain_context',409);
        $items=$p['contributions'];if(!is_array($items)||!array_is_list($items)||count($items)!==count($assignments))throw new NativeError('crypto_migration_domain_coverage',409);
        if(NativeCryptoCodec::canonical($p['assignments'])!==NativeCryptoCodec::canonical($assignments))throw new NativeError('crypto_migration_domain_assignment',409);
        foreach($assignments as $index=>$assignment){$assigned=$assignment['accountId'];$item=$items[$index];$this->fields($item,['accountId','authorization','eventAuthorization']);if($item['accountId']!==$assigned)throw new NativeError('crypto_migration_domain_contributor',409);
        $saved=$this->one("SELECT * FROM familyhub_crypto_migration_contributions_v3 WHERE migration_id=? AND scope_id=? AND domain=? AND account_id=? AND state='anchored'",[$migrationId,$sid,$domain,$assigned]);
        if(!$saved||NativeCryptoCodec::canonical(json_decode($saved['authorization']))!==NativeCryptoCodec::canonical((object)$item['authorization'])||NativeCryptoCodec::canonical(json_decode($saved['event_authorization']))!==NativeCryptoCodec::canonical((object)$item['eventAuthorization']))throw new NativeError('crypto_migration_domain_coverage',409);
        [$contribution,$raw,$signature]=NativeCryptoCodec::decode($item['authorization']);$ch=$contribution['payload']['header'];
        $user=$this->one('SELECT u.*,a.account_id FROM users u JOIN familyhub_accounts a ON a.user_id=u.id WHERE a.account_id=?',[$assigned]);if(!$user)throw new NativeError('crypto_migration_contributor_unavailable',409);
        $contributor=['user'=>$user,'device'=>['id'=>$contribution['deviceId']]];
        $directory=new NativeCryptoDirectoryV2($this->container,$this->bearer,$this->ip);$key=NativeCryptoMigrationGenerationV3::retainedSigningKey($this->pdo,$item['authorization'],$assigned)??$directory->authorizeContent($contribution,$directory->current($assigned));NativeCryptoV2Codec::verify($raw,$signature,$key);$scopes->currentAuthorReference($ch['authorDirectoryHeadHash'],$contributor);
        $member=$scopes->member($scopes->body($head),$assigned);
        if($domain==='content'||($member['financeRole']??'none')!=='none')$scopes->author($sid,$head['head_hash'],(int)$head['epoch'],(int)$scope['effective_access_revision'],$contributor,$domain,false);
        elseif((int)$row['materialized_count']!==0)throw new NativeError('crypto_migration_contributor_unavailable',409);
        if($contribution['operation']!=='crypto2.migration.domains.contribute'||$ch['headerHash']!==NativeCryptoMigrationCommitmentsV3::headerHash($h)||$ch['leafCount']!==$assignment['leafCount']||$ch['sourceRowCount']!==$assignment['sourceRowCount']||$contribution['payload']['leafSetRoot']!==NativeCryptoMigrationCommitmentsV3::contributionRoot($ch,$assignment['leafCount']===0?[]:$this->domain3Digests($migrationId,$sid,$domain)))throw new NativeError('crypto_migration_domain_coverage',409);
        [$event]=NativeCryptoCodec::decode($item['eventAuthorization']);$this->businessOwnEvent($event,$item['eventAuthorization'],$contributor,$migrationId,$domain,$h['scopeToken'],NativeCryptoV2Codec::hash((object)$item['authorization']));
        }
        $root=NativeCryptoMigrationCommitmentsV3::domainRoot($h,$this->domain3Digests($migrationId,$sid,$domain));
        if($root!==$p['domainRoot'])throw new NativeError('crypto_migration_domain_coverage',409);
        if($row['state']!=='prepared'&&NativeCryptoCodec::canonical(json_decode($row['authorization']))!==NativeCryptoCodec::canonical((object)$proof))throw new NativeError('crypto_migration_domain_immutable',409);
        if($validateOnly)return ['version'=>3,'domainRoot'=>$root];
        $this->change("UPDATE familyhub_crypto_migration_domain_attestations_v2 SET root_hash=?,authorization=?,state='certified' WHERE migration_id=? AND scope_id=? AND domain=?",[$root,NativeCryptoCodec::canonical((object)$proof),$migrationId,$sid,$domain]);
        return ['version'=>3,'certificateHash'=>NativeCryptoV2Codec::hash((object)$proof),'domainRoot'=>$root,'state'=>'certified'];
    }

    /** Candidate generation is one bounded keyset pass per immutable prepared
     * header/capture/verification/DS. It spools metadata only; readers still
     * compare every leaf with their complete FILE capability before signing. */
    private function domain3Candidates($migration,$capture,$actor,$h,$verification,$count)
    {
        $account=$actor['user']['account_id'];$migrationId=$migration['id'];$sid=$h['scopeId'];$domain=$h['domain'];
        $context=['version'=>3,'headerHash'=>NativeCryptoMigrationCommitmentsV3::headerHash($h),'captureId'=>$capture['capture_id'],'sourceInventoryRoot'=>$capture['inventory_root'],'coldParityProofHash'=>NativeCryptoV2Codec::hash((object)$verification['authorization']),'deviceSnapshotHash'=>(new NativeCryptoDirectoryV2($this->container))->current($account)['device_snapshot_hash']];
        $old=$this->one('SELECT * FROM familyhub_crypto_migration_contributions_v3 WHERE migration_id=? AND scope_id=? AND domain=? AND account_id=?',[$migrationId,$sid,$domain,$account]);
        if($old){
            if($old['header_hash']!==$context['headerHash']||$old['capture_id']!==$capture['capture_id']||(int)$old['leaf_count']!==$count['records']||(int)$old['source_count']!==$count['sources'])throw new NativeError('crypto_migration_domain_immutable',409);
            if($old['state']==='candidate'&&NativeCryptoCodec::canonical(json_decode($old['authorization']))!==NativeCryptoCodec::canonical((object)$context))throw new NativeError('crypto_migration_domain_immutable',409);
            return $old;
        }
        $this->unchanged($migration);
        // All generation writes share the outer SQL transaction; a failed candidate leaves no partial rows. Other zero contributors never erase the materializer's leaves.
        $n=0;
        foreach($this->domain3Leaves($migration,$capture,$actor,$h,$verification,$count) as $hash=>$leaf){
            $this->change('INSERT INTO familyhub_crypto_migration_domain_leaves_v2 (migration_id,scope_id,domain,leaf_hash,record_proof_hash,binding) VALUES(?,?,?,?,?,?)',[$migrationId,$sid,$domain,$hash,$leaf['recordProofHash'],NativeCryptoCodec::canonical((object)$leaf)]);$n++;
        }
        if($n!==$count['records'])throw new NativeError('crypto_migration_domain_coverage',409);
        $this->change('INSERT INTO familyhub_crypto_migration_contributions_v3 (migration_id,scope_id,domain,account_id,capture_id,header_hash,leaf_root,leaf_count,source_count,authorization,event_head_hash,event_command_hash,event_authorization,state) VALUES(?,?,?,?,?,?,?,?,?,?,NULL,NULL,NULL,?)',[$migrationId,$sid,$domain,$account,$capture['capture_id'],$context['headerHash'],NativeCryptoDirectoryV2::ZERO,$n,$count['sources'],NativeCryptoCodec::canonical((object)$context),'candidate']);
        return ['state'=>'candidate'];
    }

    private function domain3Digests($migrationId,$sid,$domain)
    {
        $after='';do{$page=$this->many('SELECT leaf_hash FROM familyhub_crypto_migration_domain_leaves_v2 WHERE migration_id=? AND scope_id=? AND domain=? AND leaf_hash>? ORDER BY leaf_hash LIMIT 20',[$migrationId,$sid,$domain,$after]);foreach($page as $row){$after=$row['leaf_hash'];yield $after;}}while(count($page)===20);
    }

    /** Scoped assignment certificate is the manager-signed prepare payload.
     * It binds every frozen assigned CONTENT portion, including explicit zero
     * source contributors, to the complete blinded component inventory. */
    private function domain3Assignments($migration,$sid,$domain,$knownCounts=null)
    {
        $materializer=$this->domain3Contributor($migration,$sid,$domain);
        $counts=$knownCounts??$this->domain3Counts($migration['id'],$sid,$domain);
        $rows=$this->many('SELECT p.account_id,p.scope_ids,c.capture_id,c.inventory_root,c.state FROM familyhub_crypto_migration_portions_v2 p JOIN familyhub_crypto_captures_v3 c ON c.migration_id=p.migration_id AND c.account_id=p.account_id WHERE p.migration_id=? ORDER BY p.account_id LIMIT 1001',[$migration['id']]);
        if(count($rows)>1000)throw new NativeError('crypto_migration_domain_assignment',409);
        $scopes=new NativeCryptoScopeV2($this->container,$this->bearer,$this->ip);$head=$scopes->current($sid);
        if(!$head)throw new NativeError('crypto_scope_head_missing',409);
        $members=array_column($scopes->body($head)['members'],'accountId');
        $out=[];
        foreach($rows as $r){
            // Independently reproducible scoped set: signed current members
            // intersect the COMPLETE authenticated frozen portion inventory.
            if(!in_array($r['account_id'],$members,true)||$domain==='finance'&&$r['account_id']!==$materializer)continue;
            if($r['state']!=='sealed')throw new NativeError('crypto_migration_contributions_pending',409);
            $owns=$r['account_id']===$materializer;
            $out[]=['accountId'=>$r['account_id'],'portionToken'=>NativeCryptoMigrationProvenanceV2::portionToken($this->serverId(),$migration['id'],$r['account_id']),'captureId'=>$r['capture_id'],'sourceInventoryRoot'=>$r['inventory_root'],'sourceRowCount'=>$owns?$counts['sources']:0,'leafCount'=>$owns?$counts['records']:0];
        }
        if(!$out)throw new NativeError('crypto_migration_domain_assignment',409);
        return $out;
    }

    private function domain3Contributor($migration,$sid,$domain)
    {
        $scope=$this->one('SELECT owner_id FROM familyhub_scopes WHERE id=?',[$sid]);$owner=$scope?$this->one('SELECT account_id FROM familyhub_accounts WHERE user_id=?',[$scope['owner_id']]):null;
        if(!$owner)throw new NativeError('crypto_migration_domain_contributor',409);
        if($domain==='content')return $owner['account_id'];
        $materializer=$this->financeMaterializer($sid,$owner['account_id']);if($materializer!==null)return $materializer;
        // Missing READ is never equated with empty. Every monetary/history
        // table must be independently empty before the owner's zero statement.
        foreach(self::FINANCE as $table)if($this->one('SELECT scope_id FROM '.$table.' WHERE scope_id=? LIMIT 1',[$sid]))throw new NativeError('crypto_migration_contributor_unavailable',409);
        return $owner['account_id'];
    }

    private function domain3Counts($migrationId,$sid,$domain)
    {
        $sources=0;$records=0;$after='';
        do{$page=$this->many('SELECT b.batch_id,b.authorization FROM familyhub_crypto_migration_stage_batches_v2 b WHERE b.migration_id=? AND b.batch_id>? AND EXISTS(SELECT 1 FROM familyhub_crypto_migration_stage_records_v2 r WHERE r.migration_id=b.migration_id AND r.scope_id=? AND r.domain=?) ORDER BY b.batch_id LIMIT 20',[$migrationId,$after,$sid,$domain]);
            // Signed batch coordinates, not a transport row count, determine
            // all primary and companion effects. Each source appears once.
            foreach($page as $batch){$after=$batch['batch_id'];[$body]=NativeCryptoCodec::decode(json_decode($batch['authorization'],true,64,JSON_THROW_ON_ERROR));$p=$body['payload'];if(($p['captureVersion']??null)!==3)throw new NativeError('crypto_capture_version',409);$proofs=$p['batch']['records'];if(!$proofs)throw new NativeError('crypto_migration_domain_coverage',409);[$first]=NativeCryptoCodec::decode($proofs[0]);if($first['scopeId']!==$sid||$first['domain']!==$domain)continue;$sources+=count($p['sourceBindings']);$records+=count($proofs);if($records>10000000)throw new NativeError('crypto_migration_domain_coverage',409);}
        }while(count($page)===20);
        return ['sources'=>$sources,'records'=>$records];
    }

    private function domain3Leaves($migration,$capture,$actor,$h,$verification,$expected)
    {
        $after='';$sources=0;
        do{$page=$this->many('SELECT * FROM familyhub_crypto_migration_stage_records_v2 WHERE migration_id=? AND scope_id=? AND domain=? AND staged_by=? AND wire_id>? ORDER BY wire_id LIMIT 20',[$migration['id'],$h['scopeId'],$h['domain'],$actor['user']['account_id'],$after]);
            foreach($page as $row){$sources++;$after=$row['wire_id'];[$record]=NativeCryptoCodec::decode(json_decode($row['record_proof'],true,34,JSON_THROW_ON_ERROR));$batch=$this->one('SELECT authorization FROM familyhub_crypto_migration_stage_batches_v2 WHERE migration_id=? AND batch_id=?',[$migration['id'],$record['batchId']]);if(!$batch)throw new NativeError('crypto_migration_domain_coverage',409);[$stage]=NativeCryptoCodec::decode(json_decode($batch['authorization'],true,64,JSON_THROW_ON_ERROR));$binding=null;foreach($stage['payload']['sourceBindings'] as $b)if($b['recordProofHash']===$row['record_proof_hash']){if($binding!==null)throw new NativeError('crypto_migration_domain_coverage',409);$binding=$b;}if(!$binding)throw new NativeError('crypto_migration_domain_coverage',409);
                $source=$this->captureSourceBinding($migration['id'],$capture['capture_id'],$binding['bindingId'],$actor);$validated=$this->businessCanonical($migration,$capture,$actor,$source,false);if($binding!==$validated)throw new NativeError('crypto_migration_domain_coverage',409);
                $by=[];foreach($stage['payload']['batch']['records'] as $proof){[$body]=NativeCryptoCodec::decode($proof);$by[NativeCryptoV2Codec::hash((object)$proof)]=[$body,$proof];}
                foreach([$binding['recordProofHash'],...$binding['companionProofHashes']] as $hash){if(!isset($by[$hash]))throw new NativeError('crypto_migration_domain_coverage',409);[$body]=$by[$hash];$leaf=['version'=>3,'migrationId'=>$migration['id'],'scopeId'=>$h['scopeId'],'domain'=>$h['domain'],'membershipHeadHash'=>$h['membershipHeadHash'],'captureId'=>$capture['capture_id'],'sourceInventoryRoot'=>$capture['inventory_root'],'bindingId'=>$binding['bindingId'],'sourceCommitment'=>$source['binding']['sourceCommitment'],'legacyRevision'=>$binding['legacyRevision'],'sourceKind'=>$body['metadata']['identity']['sourceKind'],'canonicalId'=>$body['metadata']['identity']['canonicalId'],'wireId'=>$body['id'],'type'=>$body['type'],'recordProofHash'=>$hash,'materializationRole'=>$hash===$binding['recordProofHash']?'primary':$body['type'],'contributorAccountId'=>$actor['user']['account_id'],'contributorDeviceId'=>$body['deviceId'],'contributorDeviceSnapshotHash'=>(new NativeCryptoDirectoryV2($this->container))->current($actor['user']['account_id'])['device_snapshot_hash'],'archiveManifestHash'=>$verification['header']['archiveManifestHash'],'coldParityHash'=>NativeCryptoV2Codec::hash((object)$verification['authorization']),'witnessCipherManifestHash'=>$binding['witness']['cipherManifestHash']??null];$digest=NativeCryptoMigrationCommitmentsV3::leafHash($h,$leaf);
                    $origin=$this->one('SELECT source_binding,leaf_hash FROM familyhub_crypto_migration_origins_v3 WHERE scope_id=? AND record_proof_hash=?',[$h['scopeId'],$hash]);$encoded=NativeCryptoCodec::canonical((object)$binding);
                    if($origin&&($origin['leaf_hash']!==$digest||$origin['source_binding']!==$encoded))throw new NativeError('crypto_migration_origin_ambiguous',409);
                    if(!$origin)$this->change('INSERT INTO familyhub_crypto_migration_origins_v3(migration_id,scope_id,domain,wire_id,record_proof_hash,leaf_hash,source_binding) VALUES(?,?,?,?,?,?,?)',[$migration['id'],$h['scopeId'],$h['domain'],$body['id'],$hash,$digest,$encoded]);
                    yield $digest=>$leaf;}
            }
        }while(count($page)===20);
        if($sources!==$expected['sources'])throw new NativeError('crypto_migration_domain_coverage',409);
    }

    /** Private trigger references opaque scoped approvals. Every scope manager
     * supplies its own signature; the trigger actor cannot delegate for them. */
    private function commit3($p,$actor)
    {
        [$migration]=$this->migration($p['migrationId']??null,$actor);
        // Original completed receipts remain usable after device/head changes.
        // A continuation exception exists only within this final locked call.
        if(in_array($migration['state'],['committed','retired'],true))return $this->commit3Validated($p,$actor);
        return (new NativeCryptoMigrationGenerationV3($this->container,$this->bearer,$this->ip))->withContinuedEvidence(
            $migration['id'],$actor,fn($current)=>$this->unchanged($current),fn()=>$this->commit3Validated($p,$actor));
    }

    private function commit3Validated($p,$actor)
    {
        $this->fields($p,['version','migrationId','componentId','componentCommitment','inventoryCommitment','scopeActivations']);
        [$migration,$portion]=$this->migration($p['migrationId'],$actor);
        if($p['version']!==3||$p['componentId']!==$migration['component_id'])throw new NativeError('crypto_migration_commit_context',409);
        $component=$this->captureCommitments($migration);
        if($p['componentCommitment']!==$component['componentCommitment']||$p['inventoryCommitment']!==$component['inventoryCommitment'])throw new NativeError('crypto_migration_commit_context',409);
        $refs=$p['scopeActivations'];if(!is_array($refs)||!array_is_list($refs)||!$refs||count($refs)>1000)throw new NativeError('crypto_migration_commit_context',409);
        $scopes=json_decode($migration['scope_ids'],true,34,JSON_THROW_ON_ERROR);$expected=[];
        foreach($scopes as $sid){
            $row=$this->one('SELECT * FROM familyhub_crypto_migration_activations_v3 WHERE migration_id=? AND scope_id=?',[$migration['id'],$sid]);if(!$row)throw new NativeError('crypto_migration_activation_pending',409);
            $token=NativeCryptoMigrationCommitmentsV3::scopeToken($this->serverId(),$migration['id'],$sid,'content');
            if(isset($expected[$token]))throw new NativeError('crypto_migration_commit_context',409);$expected[$token]=['scopeToken'=>$token,'activationHash'=>$row['activation_hash']];
        }
        ksort($expected,SORT_STRING);
        foreach($refs as $ref){$this->fields($ref,['scopeToken','activationHash']);$this->digest($ref['scopeToken']);$this->digest($ref['activationHash']);}
        if(NativeCryptoCodec::canonical($refs)!==NativeCryptoCodec::canonical(array_values($expected)))throw new NativeError('crypto_migration_commit_scope_set',409);
        // Exact successful retry is resolved before any mutable current head or
        // source CAS. Generic receipt lookup normally settles it even earlier.
        if(in_array($migration['state'],['committed','retired'],true))return ['version'=>3,'migrationId'=>$migration['id'],'state'=>'committed','componentCommitment'=>$component['componentCommitment'],'scopeActivations'=>array_values($expected),'legacyCleanupPending'=>true];
        if($migration['state']!=='verified')throw new NativeError('crypto_migration_verification_pending',409);
        $this->unchanged($migration);
        $portions=$this->many('SELECT * FROM familyhub_crypto_migration_portions_v2 WHERE migration_id=? ORDER BY account_id LIMIT 1001',[$migration['id']]);
        if(!$portions||count($portions)>1000)throw new NativeError('crypto_migration_contributions_pending',409);
        $plans=[];
        foreach($portions as $part){
            if($part['state']!=='verified'||$part['verification']===null)throw new NativeError('crypto_migration_contributions_pending',409);
            $v=json_decode($part['verification'],true,64,JSON_THROW_ON_ERROR);if(($v['version']??null)!==3)throw new NativeError('crypto_capture_version',409);
            [$verify,$bytes,$signature]=NativeCryptoCodec::decode($v['authorization']);
            $user=$this->one('SELECT u.*,a.account_id FROM users u JOIN familyhub_accounts a ON a.user_id=u.id WHERE a.account_id=?',[$part['account_id']]);
            if(!$user||!(int)$user['is_active'])throw new NativeError('crypto_migration_contributor_unavailable',409);
            $contributor=['user'=>$user,'device'=>['id'=>$verify['deviceId']]];
            $directory=new NativeCryptoDirectoryV2($this->container,$this->bearer,$this->ip);$key=NativeCryptoMigrationGenerationV3::retainedSigningKey($this->pdo,$v['authorization'],$part['account_id'])??$directory->authorizeContent($verify,$directory->current($part['account_id']));NativeCryptoV2Codec::verify($bytes,$signature,$key);
            // Reconstruct the SAME originally signed FILE comparison. Server
            // checks exact ciphertext/coverage/source CAS, never decrypts or
            // claims it independently established plaintext business parity.
            $this->verifyCapture3($verify['payload'],$contributor,$v['authorization']);
            $capture=$this->captureRow($migration,$contributor);
            $notifications=new NativeCryptoMigrationNotificationStageV3($this->container,$this->bearer,$this->ip);
            $nc=$notifications->coverage($migration['id'],$capture['capture_id'],$capture['inventory_root'],$contributor,[$this,'captureSourceBindings']);
            $invitations=new NativeCryptoMigrationInvitationStageV3($this->container,$this->bearer,$this->ip);
            $ic=$invitations->coverage($migration['id'],$capture['capture_id'],$capture['inventory_root'],$contributor,[$this,'captureSourceBindings']);
            $plans[]=$notifications->prepareInstall($nc,$contributor,[$this,'captureSourceBindings'],[$this,'captureSourceBinding'],[$this,'stagedCaptureTarget']);
            $plans[]=$invitations->prepareInstall($ic,$contributor,[$this,'captureSourceBindings'],[$this,'captureSourceBinding']);
        }
        // Validate ALL independent manager signatures/current identity/heads,
        // domain contributions and lifecycle before any active installation.
        foreach($scopes as $sid){
            if($this->one('SELECT scope_id FROM familyhub_crypto_scope_origins WHERE scope_id=?',[$sid])||$this->one('SELECT scope_id FROM familyhub_crypto_records WHERE scope_id=? LIMIT 1',[$sid]))throw new NativeError('crypto_migration_active_collision',409);
            $activation=$this->one('SELECT * FROM familyhub_crypto_migration_activations_v3 WHERE migration_id=? AND scope_id=?',[$migration['id'],$sid]);
            $authorization=json_decode($activation['authorization'],true,64,JSON_THROW_ON_ERROR);$event=json_decode($activation['event_authorization'],true,64,JSON_THROW_ON_ERROR);[$eventBody]=NativeCryptoCodec::decode($event);
            $user=$this->one('SELECT u.*,a.account_id FROM users u JOIN familyhub_accounts a ON a.user_id=u.id WHERE a.account_id=?',[$activation['manager_account_id']]);if(!$user||!(int)$user['is_active'])throw new NativeError('crypto_migration_contributor_unavailable',409);
            $manager=['user'=>$user,'device'=>['id'=>$eventBody['deviceId']]];
            $this->activation3Stage(['authorization'=>$authorization,'eventAuthorization'=>$event],$manager);
            $scope=$this->scope($sid,$manager['user']['id']);$head=(new NativeCryptoScopeV2($this->container,$this->bearer,$this->ip))->current($sid);
            foreach(['content','finance'] as $domain){
                $cert=$this->one("SELECT * FROM familyhub_crypto_migration_domain_attestations_v2 WHERE migration_id=? AND scope_id=? AND domain=? AND state='anchored'",[$migration['id'],$sid,$domain]);
                if(!$cert)throw new NativeError('crypto_migration_domain_pending',409);
                $proof=json_decode($cert['authorization'],true,64,JSON_THROW_ON_ERROR);[$body]=NativeCryptoCodec::decode($proof);
                $this->domain3Certificate('crypto2.migration.domains.certify',$body['payload'],$manager,$proof,$migration,$cert,$body['payload']['header'],$head,$scope,$body['payload']['assignments'],true);
                $anchor=$this->one('SELECT authorization FROM familyhub_crypto_directory WHERE account_id=? AND head_hash=?',[$cert['manager_account_id'],$cert['event_head_hash']]);if(!$anchor)throw new NativeError('crypto_migration_domain_pending',409);
                $ownEvent=json_decode($anchor['authorization'],true,64,JSON_THROW_ON_ERROR);[$eventBody]=NativeCryptoCodec::decode($ownEvent);
                $this->businessOwnEvent($eventBody,$ownEvent,$manager,$migration['id'],$domain,$body['payload']['header']['scopeToken'],NativeCryptoV2Codec::hash((object)$proof));
            }
        }
        $this->idea3Blobs($migration, false);
        $this->audit3Blobs($migration, false);
        // Every actual blob was hash-checked above. SQL copies reference the
        // same immutable ciphertext and roll back with all business effects;
        // no filesystem rename/delete or original-source deletion occurs.
        foreach($scopes as $sid)$this->install3Records($migration,$sid);
        $this->idea3Blobs($migration, true);
        $this->audit3Blobs($migration, true);
        foreach($plans as $apply)$apply();
        foreach($scopes as $sid){
            $this->change("UPDATE familyhub_crypto_scopes SET state='active',migration_id=? WHERE scope_id=?",[$migration['id'],$sid]);
            $this->change("UPDATE familyhub_crypto_migration_activations_v3 SET state='committed' WHERE migration_id=? AND scope_id=?",[$migration['id'],$sid]);
        }
        $this->change("UPDATE familyhub_crypto_migration_portions_v2 SET state='committed' WHERE migration_id=?",[$migration['id']]);
        $this->change("UPDATE familyhub_crypto_migrations_v2 SET state='committed',updated_at=? WHERE id=?",[time(),$migration['id']]);
        return ['version'=>3,'migrationId'=>$migration['id'],'state'=>'committed','componentCommitment'=>$component['componentCommitment'],'scopeActivations'=>array_values($expected),'legacyCleanupPending'=>true];
    }

    private function install3Records($migration,$sid)
    {
        $scopes=new NativeCryptoScopeV2($this->container,$this->bearer,$this->ip);$head=$scopes->current($sid);$scopeState=$this->one('SELECT sequence FROM familyhub_crypto_scopes WHERE scope_id=?',[$sid]);
        $global=(int)$scopeState['sequence'];
        foreach(['content','finance'] as $domain){
            $sequence=$scopes->domainSequence($sid,$domain);$after='';
            do{$page=$this->many('SELECT leaf_hash,record_proof_hash,binding FROM familyhub_crypto_migration_domain_leaves_v2 WHERE migration_id=? AND scope_id=? AND domain=? AND leaf_hash>? ORDER BY leaf_hash LIMIT 20',[$migration['id'],$sid,$domain,$after]);
                foreach($page as $row){$after=$row['leaf_hash'];$leaf=json_decode($row['binding'],true,34,JSON_THROW_ON_ERROR);
                    // Recover exact original batch including companion proofs;
                    // never manufacture an ordinary WRITE authorization.
                    $origin=$this->one('SELECT source_binding FROM familyhub_crypto_migration_origins_v3 WHERE migration_id=? AND scope_id=? AND domain=? AND record_proof_hash=? AND leaf_hash=?',[$migration['id'],$sid,$domain,$leaf['recordProofHash'],$row['leaf_hash']]);
                    if(!$origin)throw new NativeError('crypto_migration_origin_missing',409);$preparedBinding=json_decode($origin['source_binding'],true,64,JSON_THROW_ON_ERROR);
                    $primary=$this->one('SELECT record_proof FROM familyhub_crypto_migration_stage_records_v2 WHERE migration_id=? AND scope_id=? AND wire_id=? AND record_proof_hash=?',[$migration['id'],$sid,$preparedBinding['wireId'],$preparedBinding['recordProofHash']]);
                    if(!$primary)throw new NativeError('crypto_migration_stage_unavailable',409);[$body]=NativeCryptoCodec::decode(json_decode($primary['record_proof'],true,34,JSON_THROW_ON_ERROR));$batch=$this->one('SELECT authorization FROM familyhub_crypto_migration_stage_batches_v2 WHERE migration_id=? AND batch_id=?',[$migration['id'],$body['batchId']]);
                    if(!$batch)throw new NativeError('crypto_migration_stage_unavailable',409);[$stage]=NativeCryptoCodec::decode(json_decode($batch['authorization'],true,64,JSON_THROW_ON_ERROR));$entry=null;$sourceBinding=null;
                    foreach($stage['payload']['batch']['records'] as $proof)if(NativeCryptoV2Codec::hash((object)$proof)===$leaf['recordProofHash']){[$body]=NativeCryptoCodec::decode($proof);$entry=['record'=>$body,'recordProof'=>$proof,'batchCommitment'=>$stage['payload']['batch']['commitment']];}
                    foreach($stage['payload']['sourceBindings'] as $binding)if($binding['bindingId']===$leaf['bindingId'])$sourceBinding=$binding;
                    if(!$entry||!$sourceBinding||$entry['record']['id']!==$leaf['wireId']||$entry['record']['membershipHeadHash']!==$head['head_hash']||$entry['record']['expectedRevision']!==0)throw new NativeError('crypto_migration_install_binding',409);
                    $r=$entry['record'];$sequence++;$global++;
                    $authorization=NativeCryptoCodec::canonical((object)['recordProof'=>$entry['recordProof'],'batchCommitment'=>$entry['batchCommitment']]);
                    $this->change('INSERT INTO familyhub_crypto_records(type,revision,deleted,sequence,epoch,envelope,metadata,authorization,scope_id,id) VALUES(?,1,?,?,?,?,?,?,?,?)',[$r['type'],(int)$r['deleted'],$global,$r['epoch'],$r['envelopeBase64']??'',NativeCryptoCodec::canonical((object)$r['metadata']),$authorization,$sid,$r['id']]);
                    $this->change('INSERT INTO familyhub_crypto_record_positions(scope_id,id,domain,sequence) VALUES(?,?,?,?)',[$sid,$r['id'],$domain,$sequence]);
                    $this->change('INSERT INTO familyhub_crypto_record_history(scope_id,id,revision,sequence,epoch,domain,record_proof_hash,record_proof,batch_commitment) VALUES(?,?,1,?,?,?,?,?,?)',[$sid,$r['id'],$sequence,$r['epoch'],$domain,$leaf['recordProofHash'],NativeCryptoCodec::canonical((object)$entry['recordProof']),NativeCryptoCodec::canonical((object)$entry['batchCommitment'])]);
                    foreach($r['deleted']?[]:$r['metadata']['uniqueRefs'] as $unique){if($this->one('SELECT record_id FROM familyhub_crypto_unique_refs WHERE scope_id=? AND reference_hash=?',[$sid,$unique]))throw new NativeError('crypto_unique_conflict',409);$this->change('INSERT INTO familyhub_crypto_unique_refs(scope_id,reference_hash,record_id) VALUES(?,?,?)',[$sid,$unique,$r['id']]);}
                    if(NativeCryptoCodec::canonical((object)$preparedBinding)!==NativeCryptoCodec::canonical((object)$sourceBinding))throw new NativeError('crypto_migration_origin_ambiguous',409);
                    foreach($r['metadata']['blobIds'] as $id)$this->install3Blob($migration['id'],$sid,$id,$domain);
                }
            }while(count($page)===20);
            $this->change('UPDATE familyhub_crypto_domain_cursors SET sequence=? WHERE scope_id=? AND domain=?',[$sequence,$sid,$domain]);
        }
        $this->change('UPDATE familyhub_crypto_scopes SET sequence=? WHERE scope_id=?',[$global,$sid]);
    }

    /** Complete audit controls reference independent encrypted witnesses, not
     * business record blobIds. Validate every byte before ANY active mutation;
     * the second pass only publishes immutable SQL references in the same TX. */
    private function idea3Blobs($migration,$install)
    {
        $parts=$this->many('SELECT * FROM familyhub_crypto_migration_portions_v2 WHERE migration_id=? ORDER BY account_id',[$migration['id']]);
        foreach($parts as $part){
            $user=$this->one('SELECT u.*,a.account_id FROM users u JOIN familyhub_accounts a ON a.user_id=u.id WHERE a.account_id=?',[$part['account_id']]);
            if(!$user||!(int)$user['is_active'])throw new NativeError('crypto_migration_contributor_unavailable',409);
            $actor=['user'=>$user];$capture=$this->captureRow($migration,$actor);
            foreach($this->captureSourceBindings($migration['id'],$capture['capture_id'],$capture['inventory_root'],$actor,['familyhub_idea_assets']) as $source){
                if($install){
                    // Preparation has already validated every source/cipher;
                    // only immutable staged references are published here.
                    $resolved=$this->captureSourceBinding($migration['id'],$capture['capture_id'],$source['binding']['bindingId'],$actor);
                    $cells=get_object_vars($resolved['typedRow']);$id=base64_decode($cells['board_id']['valueBase64'],true).':'.base64_decode($cells['sha256']['valueBase64'],true);
                    $blobs=$this->many("SELECT id FROM familyhub_crypto_migration_blobs_v2 WHERE migration_id=? AND account_id=? AND scope_id=? AND source_table='familyhub_idea_assets' AND source_id=? AND purpose='ideaAsset' ORDER BY id LIMIT 2",[$migration['id'],$part['account_id'],$source['context']['scopeId'],$id]);
                    if(count($blobs)!==1)throw new NativeError('crypto_migration_idea_files_pending',409);
                    $this->install3Blob($migration['id'],$source['context']['scopeId'],$blobs[0]['id'],'content');
                }else{
                    $result=$this->businessIdeaFile($migration,$capture,$actor,$source,true);$d=$result['object']['blob'];
                    $old=$this->one('SELECT * FROM familyhub_crypto_blobs_v2 WHERE scope_id=? AND id=?',[$source['context']['scopeId'],$d['id']]);
                    if($old&&($old['sha256']!==$d['cipherSha256']||(int)$old['size']!==$d['cipherSize']||$old['manifest']!==$d['manifestBase64']))throw new NativeError('crypto_migration_blob_collision',409);
                }
            }
        }
    }

    private function audit3Blobs($migration, $install)
    {
        $after='';
        do {
            $page=$this->many('SELECT * FROM familyhub_crypto_migration_audit_v3 WHERE migration_id=? AND binding_id>? ORDER BY binding_id LIMIT 20',[$migration['id'],$after]);
            foreach($page as $row) {
                $after=$row['binding_id'];$d=json_decode($row['descriptor'],true,34,JSON_THROW_ON_ERROR);$c=$d['context']??[];
                if(($c['migrationId']??null)!==$migration['id']||($c['captureId']??null)!==$row['capture_id']||($c['bindingId']??null)!==$row['binding_id']||($c['accountId']??null)!==$row['account_id']||($c['scopeId']??null)!==$row['scope_id']||($c['domain']??null)!=='finance'||($c['sourceInventoryRoot']??null)!==$row['source_inventory_root']||($c['sourceCommitment']??null)!==$row['source_commitment']||!isset($d['segments'])||!is_array($d['segments'])||!array_is_list($d['segments'])||!$d['segments']||count($d['segments'])>4)throw new NativeError('crypto_migration_audit_cipher_binding',409);
                foreach($d['segments'] as $segment) {
                    if($install){$this->install3Blob($migration['id'],$row['scope_id'],$segment['id'],'finance');continue;}
                    $blob=$this->one('SELECT * FROM familyhub_crypto_migration_blobs_v2 WHERE migration_id=? AND scope_id=? AND id=? AND domain=? AND complete=1',[$migration['id'],$row['scope_id'],$segment['id'],'finance']);
                    if(!$blob||$blob['purpose']!=='auditWitness'||$blob['account_id']!==$row['account_id']||$blob['head_hash']!==$c['membershipHeadHash']||(int)$blob['epoch']!==$c['epoch']||(int)$blob['access_revision']!==$c['accessRevision']||(int)$blob['size']!==$segment['size']||(int)$blob['received']!==$segment['size']||$blob['sha256']!==$segment['sha256']||$blob['manifest']!==$d['manifestBase64'])throw new NativeError('crypto_migration_audit_cipher_binding',409);
                    $this->businessCipher($migration['id'],$segment['id'],$segment['size'],$segment['sha256']);
                    $old=$this->one('SELECT * FROM familyhub_crypto_blobs_v2 WHERE scope_id=? AND id=?',[$row['scope_id'],$segment['id']]);
                    if($old&&($old['sha256']!==$blob['sha256']||(int)$old['size']!==(int)$blob['size']||$old['manifest']!==$blob['manifest']||$old['authorization']!==$blob['authorization']))throw new NativeError('crypto_migration_blob_collision',409);
                }
                if($install)$this->change("UPDATE familyhub_crypto_migration_audit_v3 SET state='installed' WHERE migration_id=? AND binding_id=?",[$migration['id'],$row['binding_id']]);
            }
        }while(count($page)===20);
    }

    private function install3Blob($migrationId,$sid,$id,$domain)
    {
        $blob=$this->one('SELECT * FROM familyhub_crypto_migration_blobs_v2 WHERE migration_id=? AND scope_id=? AND id=? AND domain=? AND complete=1',[$migrationId,$sid,$id,$domain]);if(!$blob)throw new NativeError('crypto_migration_blob_missing',409);
        $old=$this->one('SELECT * FROM familyhub_crypto_blobs_v2 WHERE scope_id=? AND id=?',[$sid,$id]);
        if($old){if($old['sha256']!==$blob['sha256']||(int)$old['size']!==(int)$blob['size']||$old['manifest']!==$blob['manifest']||$old['authorization']!==$blob['authorization'])throw new NativeError('crypto_migration_blob_collision',409);return;}
        $this->change('INSERT INTO familyhub_crypto_blobs_v2(scope_id,id,head_hash,domain,owner_account_id,epoch,size,sha256,received,complete,manifest,authorization) VALUES(?,?,?,?,?,?,?,?,?,1,?,?)',[$sid,$id,$blob['head_hash'],$domain,$blob['account_id'],(int)$blob['epoch'],(int)$blob['size'],$blob['sha256'],(int)$blob['size'],$blob['manifest'],$blob['authorization']]);
        $this->change('INSERT INTO familyhub_crypto_blob_chunks_v2(scope_id,blob_id,chunk_offset,data) SELECT ?,blob_id,chunk_offset,data FROM familyhub_crypto_migration_blob_chunks_v2 WHERE migration_id=? AND blob_id=?',[$sid,$migrationId,$id]);
    }

    private function commit($params, $migration, $portion)
    {
        $this->digest($params['expectedComponentHash']);
        if ($params['expectedComponentHash'] !== $migration['component_hash'] || $params['inventoryHash'] !== $portion['inventory_hash']) {
            throw new NativeError('crypto_migration_component_changed', 409);
        }
        $pending = $this->one("SELECT COUNT(*) AS n FROM familyhub_crypto_migration_portions_v2 WHERE migration_id=? AND state<>'verified'", [$migration['id']]);
        if ((int)$pending['n'] !== 0) {
            throw new NativeError('crypto_migration_contributions_pending', 409);
        }
        // No arbitrary list of implemented features, SDK capability boolean,
        // opaque archive or caller assertion can enable destructive cutover.
        // Domain parity and retirement must be wired to actual verified rows.
        throw new NativeError('crypto_cutover_not_supported', 409);
    }

    private function abort($migration, $actor)
    {
        if (in_array($migration['state'], ['committed', 'retired'], true)) {
            throw new NativeError('crypto_migration_committed', 409);
        }
        // No one participant may silently unfreeze another owner's signed
        // migration. Abort is presently allowed only for a one-account graph.
        $parts = $this->many('SELECT account_id FROM familyhub_crypto_migration_portions_v2 WHERE migration_id=?', [$migration['id']]);
        if (count($parts) !== 1 || $parts[0]['account_id'] !== $actor['user']['account_id']) {
            throw new NativeError('crypto_migration_abort_consent_required', 409);
        }
        // The original plan permits reopening ONLY the unchanged authoritative
        // legacy generation before final publication/admission. Uploaded stage
        // remains immutable and charged to quota; it is never a reset/delete.
        $this->unchanged($migration);
        if ($this->one('SELECT scope_id FROM familyhub_crypto_migration_activations_v3 WHERE migration_id=? LIMIT 1', [$migration['id']])) {
            // Every stored scoped activation already passed own-log inclusion.
            throw new NativeError('crypto_migration_abort_publication_exists', 409);
        }
        foreach (json_decode($migration['scope_ids'], true, 34, JSON_THROW_ON_ERROR) as $scopeId) {
            // Candidate heads/keys are preparatory and intentionally retained.
            // Actual ordinary/public-origin admission is a permanent boundary.
            if ($this->one('SELECT scope_id FROM familyhub_crypto_scope_origins WHERE scope_id=?', [$scopeId]) ||
                $this->one('SELECT scope_id FROM familyhub_crypto_records WHERE scope_id=? LIMIT 1', [$scopeId])) {
                throw new NativeError('crypto_migration_abort_publication_exists',409);
            }
            if ($this->one('SELECT legacy_id FROM familyhub_crypto_migration_legacy_v2 WHERE scope_id=? AND replacement_id IS NOT NULL LIMIT 1', [$scopeId])) {
                throw new NativeError('crypto_migration_abort_receipts_pending', 409);
            }
        }
        $this->change("UPDATE familyhub_crypto_scopes SET state='staged',migration_id=NULL WHERE migration_id=? AND state IN ('preparing','fenced','verified')", [$migration['id']]);
        $this->change("UPDATE familyhub_crypto_migrations_v2 SET state='aborted',updated_at=? WHERE id=?", [time(), $migration['id']]);
        return ['migrationId' => $migration['id'], 'state' => 'aborted', 'legacyPreserved' => true];
    }

    /** Copy outcomes before any source response can be retired. No plaintext. */
    private function indexLegacyReceipts($scopeId, $migrationId)
    {
        foreach (['records', 'finance', 'documents'] as $kind) {
            $hash = hash_init('sha256');
            $count = 0;
            foreach ($this->legacyReceiptRows($scopeId, $kind) as $receipt) {
                $account = $receipt['account_id'] ?? $this->missingContributorId('legacy-user:'.$receipt['user_id']);
                // Document request identity was (account,device,request), unlike
                // record/finance identity. Preserve it with a domain-separated
                // deterministic UUID; the original tuple remains in raw archive.
                $id = $kind === 'documents'
                    ? $this->documentReceiptId($receipt['device_id'], $receipt['id']) : $receipt['id'];
                $status = $kind === 'documents' ? 200 : (int)$receipt['status'];
                $value = ['legacyHash' => $receipt['request_hash'],
                    'outcome' => $status === 200 ? 'applied' : 'rejected',
                    'status' => $status, 'responseHash' => hash('sha256', $receipt['response'])];
                $key = [$scopeId, $account, $kind, $id];
                $old = $this->one('SELECT * FROM familyhub_crypto_legacy_index_v2 WHERE scope_id=? AND account_id=? AND kind=? AND legacy_id=?', $key);
                if ($old) {
                    if ($old['legacy_hash'] !== $value['legacyHash'] || $old['outcome'] !== $value['outcome'] ||
                        (int)$old['status'] !== $status || $old['response_hash'] !== $value['responseHash']) {
                        throw new NativeError('crypto_legacy_index_changed', 409);
                    }
                } else {
                    $this->change('INSERT INTO familyhub_crypto_legacy_index_v2 VALUES(?,?,?,?,?,?,?,?)', [
                        ...$key, $value['legacyHash'], $value['outcome'], $status, $value['responseHash'],
                    ]);
                }
                hash_update($hash, self::inventoryCanonical((object)['accountId' => $account, 'id' => $id, 'receipt' => $value])."\n");
                $count++;
            }
            $digest = hash_final($hash);
            $old = $this->one('SELECT * FROM familyhub_crypto_legacy_index_generations_v2 WHERE migration_id=? AND scope_id=? AND kind=?', [$migrationId, $scopeId, $kind]);
            if ($old) {
                if ((int)$old['record_count'] !== $count || $old['inventory_hash'] !== $digest || $old['state'] !== 'complete') {
                    throw new NativeError('crypto_legacy_index_changed', 409);
                }
            } else {
                $this->change('INSERT INTO familyhub_crypto_legacy_index_generations_v2 VALUES(?,?,?,?,?,?)', [$migrationId, $scopeId, $kind, 'complete', $count, $digest]);
            }
        }
    }

    /** Keyset metadata pages close before reading one large response or writing. */
    private function legacyReceiptRows($scopeId, $kind)
    {
        if ($kind === 'records') {
            $select = 'SELECT o.id,o.user_id,a.account_id,o.request_hash,o.status FROM familyhub_operations o LEFT JOIN familyhub_accounts a ON a.user_id=o.user_id WHERE o.scope_id=?';
            $keys = ['o.user_id' => 'user_id', 'o.id' => 'id'];
        } elseif ($kind === 'finance') {
            $select = 'SELECT id,account_id,request_hash,status FROM familyhub_finance_operations WHERE scope_id=?';
            $keys = ['account_id' => 'account_id', 'id' => 'id'];
        } else {
            $select = 'SELECT request_id AS id,device_id,account_id,request_hash FROM familyhub_document_requests WHERE scope_id=?';
            $keys = ['account_id' => 'account_id', 'device_id' => 'device_id', 'request_id' => 'id'];
        }
        $cursor = null;
        while (true) {
            $where = [];
            $params = [$scopeId];
            if ($cursor !== null) {
                $prefix = [];
                foreach ($keys as $sql => $field) {
                    $clauses = $prefix;
                    $clauses[] = $sql.'>?';
                    $where[] = '('.implode(' AND ', $clauses).')';
                    foreach (array_slice(array_values($keys), 0, count($prefix)) as $prior) {
                        $params[] = $cursor[$prior];
                    }
                    $params[] = $cursor[$field];
                    $prefix[] = $sql.'=?';
                }
            }
            $query = $select.($where ? ' AND ('.implode(' OR ', $where).')' : '').' ORDER BY '.implode(',', array_keys($keys)).' LIMIT 128';
            $page = $this->many($query, $params);
            if (!$page) break;
            foreach ($page as $row) {
                if ($kind === 'records') {
                    $response = $this->one('SELECT response FROM familyhub_operations WHERE scope_id=? AND user_id=? AND id=?', [$scopeId, $row['user_id'], $row['id']]);
                } elseif ($kind === 'finance') {
                    $response = $this->one('SELECT response FROM familyhub_finance_operations WHERE scope_id=? AND account_id=? AND id=?', [$scopeId, $row['account_id'], $row['id']]);
                } else {
                    $response = $this->one('SELECT response FROM familyhub_document_requests WHERE scope_id=? AND account_id=? AND device_id=? AND request_id=?', [$scopeId, $row['account_id'], $row['device_id'], $row['id']]);
                }
                if (!$response) throw new NativeError('crypto_legacy_index_changed', 409);
                $row['response'] = $response['response'];
                yield $row;
                $cursor = $row;
            }
        }
    }

    private function documentReceiptId($device, $request)
    {
        $hash = hash('sha256', "JivieDocumentReceipt/v2\n".$this->uuid($device).':'.$this->uuid($request));
        return substr($hash, 0, 8).'-'.substr($hash, 8, 4).'-4'.substr($hash, 13, 3).'-a'.substr($hash, 17, 3).'-'.substr($hash, 20, 12);
    }

    private function legacyLookup($params, $actor)
    {
        $this->fields($params, ['scopeId', 'legacyId', 'finance'], ['requestHash', 'receiptKind', 'legacyDeviceId']);
        $scopeId = $this->uuid($params['scopeId']);
        $legacyId = $this->uuid($params['legacyId']);
        $this->scope($scopeId, $actor['user']['id']);
        $cryptoScope = $this->one('SELECT migration_id FROM familyhub_crypto_scopes WHERE scope_id=?', [$scopeId]);
        if ($cryptoScope && $cryptoScope['migration_id']
            && $this->one('SELECT capture_id FROM familyhub_crypto_captures_v3 WHERE migration_id=? LIMIT 1', [$cryptoScope['migration_id']])) {
            // Capture3 resolves only an authenticated complete random-ID
            // inventory plus encrypted receipt evidence, never a raw hash or
            // an unsigned not-found response from the old preview index.
            throw new NativeError('crypto_capture_legacy_evidence_required', 409);
        }
        if (!is_bool($params['finance'])) {
            throw new NativeError('validation_error');
        }
        if (isset($params['requestHash'])) {
            $this->digest($params['requestHash']);
        }
        $kind = $params['receiptKind'] ?? ($params['finance'] ? 'finance' : 'records');
        if (!in_array($kind, ['records', 'finance', 'documents'], true) ||
            ($params['finance'] !== ($kind === 'finance')) ||
            (isset($params['legacyDeviceId']) && $kind !== 'documents')) {
            throw new NativeError('validation_error');
        }
        if ($params['finance']) {
            (new NativeFinanceAccess($this->container))->policyForCrypto($scopeId, $actor['user']);
        }
        $device = $params['legacyDeviceId'] ?? $actor['device']['id'];
        $indexedId = $kind === 'documents' ? $this->documentReceiptId($device, $legacyId) : $legacyId;
        $index = $this->one('SELECT * FROM familyhub_crypto_legacy_index_v2 WHERE scope_id=? AND account_id=? AND kind=? AND legacy_id=?', [
            $scopeId, $actor['user']['account_id'], $kind, $indexedId,
        ]);
        if ($index) {
            if (isset($params['requestHash']) && !hash_equals($index['legacy_hash'], $params['requestHash'])) {
                throw new NativeError('idempotency_mismatch', 409);
            }
            return ['legacyId' => $legacyId, 'outcome' => $index['outcome'],
                'storedRequestHash' => $index['legacy_hash'], 'responseHash' => $index['response_hash'],
                'status' => (int)$index['status']];
        }
        if ($kind === 'documents') {
            $row = $this->one('SELECT request_hash,response FROM familyhub_document_requests WHERE scope_id=? AND account_id=? AND device_id=? AND request_id=?', [$scopeId, $actor['user']['account_id'], $this->uuid($device), $legacyId]);
            if ($row) $row['status'] = 200;
        } else {
            $table = $kind === 'finance' ? 'familyhub_finance_operations' : 'familyhub_operations';
            $column = $kind === 'finance' ? 'account_id' : 'user_id';
            $owner = $kind === 'finance' ? $actor['user']['account_id'] : $actor['user']['id'];
            $row = $this->one('SELECT request_hash,response,status FROM '.$table.' WHERE scope_id=? AND '.$column.'=? AND id=?', [$scopeId, $owner, $legacyId]);
        }
        if ($row && isset($params['requestHash']) && !hash_equals($row['request_hash'], $params['requestHash'])) {
            throw new NativeError('idempotency_mismatch', 409);
        }
        $state = $this->one('SELECT state,migration_id FROM familyhub_crypto_scopes WHERE scope_id=?', [$scopeId]);
        $migration = $state && $state['migration_id'] ? $this->one('SELECT state FROM familyhub_crypto_migrations_v2 WHERE id=?', [$state['migration_id']]) : null;
        $indexed = $state && $state['migration_id'] ? $this->one("SELECT state FROM familyhub_crypto_legacy_index_generations_v2 WHERE migration_id=? AND scope_id=? AND kind=? AND state='complete'", [$state['migration_id'], $scopeId, $kind]) : null;
        $fenced = $migration && $indexed && in_array($migration['state'], ['fenced', 'verified', 'committed', 'retired'], true);
        return [
            'legacyId' => $legacyId,
            'outcome' => $row ? ((int)$row['status'] === 200 ? 'applied' : 'rejected') : ($fenced ? 'notApplied' : 'unknown'),
            'storedRequestHash' => $row['request_hash'] ?? null,
            'responseHash' => $row ? hash('sha256', $row['response']) : null,
            'status' => $row ? (int)$row['status'] : null,
        ];
    }

    private function reserveLegacy($params, $actor)
    {
        $this->fields($params, ['scopeId', 'legacyId', 'requestHash', 'replacementId', 'finance']);
        $this->digest($params['requestHash']);
        $replacement = $this->uuid($params['replacementId']);
        $lookup = $this->legacyLookup(array_diff_key($params, ['replacementId' => true]), $actor);
        if ($lookup['outcome'] !== 'notApplied') {
            throw new NativeError('crypto_legacy_outcome_unresolved', 409);
        }
        $domain = $params['finance'] ? 'finance' : 'content';
        $key = [$params['scopeId'], $actor['user']['account_id'], $domain, $params['legacyId']];
        $old = $this->one('SELECT * FROM familyhub_crypto_migration_legacy_v2 WHERE scope_id=? AND account_id=? AND domain=? AND legacy_id=?', $key);
        if ($old) {
            if ($old['legacy_hash'] !== $params['requestHash'] || $old['replacement_id'] !== $replacement) {
                throw new NativeError('idempotency_mismatch', 409);
            }
        } else {
            $this->change('INSERT INTO familyhub_crypto_migration_legacy_v2(scope_id,account_id,domain,legacy_id,legacy_hash,outcome,replacement_id,response_hash) VALUES(?,?,?,?,?,?,?,NULL)', array_merge($key, [$params['requestHash'], 'notApplied', $replacement]));
        }
        return ['legacyId' => $params['legacyId'], 'replacementId' => $replacement, 'outcome' => 'reserved', 'requestHash' => $params['requestHash']];
    }

    /** General sorted JSON for typed legacy inventories, never signed commands.
     * UUID/table:domain map keys are deliberately outside crypto2 command JSON.
     */
    public static function inventoryCanonical($value)
    {
        if (is_object($value)) {
            $properties = get_object_vars($value);
            ksort($properties, SORT_STRING);
            $parts = [];
            foreach ($properties as $key => $child) {
                $parts[] = json_encode((string)$key, JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE | JSON_THROW_ON_ERROR).':'.self::inventoryCanonical($child);
            }
            return '{'.implode(',', $parts).'}';
        }
        if (is_array($value)) {
            if (!array_is_list($value)) {
                return self::inventoryCanonical((object)$value);
            }
            return '['.implode(',', array_map([self::class, 'inventoryCanonical'], $value)).']';
        }
        return json_encode($value, JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE | JSON_THROW_ON_ERROR);
    }

    public static function inventoryHash($value)
    {
        return hash('sha256', self::inventoryCanonical($value));
    }

    private function digest($value)
    {
        if (!is_string($value) || !preg_match('/^[a-f0-9]{64}$/D', $value)) {
            throw new NativeError('validation_error');
        }
    }

    private function newId()
    {
        $hex = bin2hex(random_bytes(16));
        return substr($hex, 0, 8).'-'.substr($hex, 8, 4).'-4'.substr($hex, 13, 3).'-a'.substr($hex, 17, 3).'-'.substr($hex, 20);
    }
}
