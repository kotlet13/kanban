<?php

namespace Kanboard\Plugin\FamilyHub\Model;

/** Explicit reporter-disclosed evidence. No decryption key reaches the server. */
class NativeCryptoModerationV2 extends NativeDatabase
{
    protected $cryptoAccess = true;

    private function recipient()
    {
        return ['kind' => 'serverAdministrator', 'name' => 'FamilyHub server administrator'];
    }

    private function source($params, $actor)
    {
        $this->fields($params, ['scopeId','targetType','targetId']);
        $scopeId = $this->uuid($params['scopeId']);
        $scope = $this->scope($scopeId, $actor['user']['id']);
        if ($scope['kind'] === 'personal') {
            throw new NativeError('personal_not_shareable', 403);
        }
        $targetType = $params['targetType'];
        if (!in_array($targetType, ['record','finance','table','attachment','user'], true)) {
            throw new NativeError('validation_error');
        }
        $scopes = new NativeCryptoScopeV2($this->container, $this->bearer, $this->ip);
        $head = $scopes->current($scopeId);
        if (!$head) {
            throw new NativeError('crypto_scope_head_missing', 409);
        }
        $domain = null;
        $proofHash = null;
        if ($targetType === 'user') {
            $targetId = $this->uuid($params['targetId']);
            $member = $scopes->member($scopes->body($head), $targetId);
            if (!$member || !(new NativeOrganizationAccess($this->container))->visibleScope($scopeId, $targetId)) {
                throw new NativeError('report_target_unavailable', 404);
            }
            $type = 'user';
            $revision = (int)$scope['effective_access_revision'];
        } else {
            $targetId = NativeCryptoRecordAddressV2::wireId($params['targetId']);
            $record = $this->one('SELECT * FROM familyhub_crypto_records WHERE scope_id=? AND id=?', [$scopeId,$targetId]);
            if (!$record || (int)$record['deleted']) {
                throw new NativeError('report_target_unavailable', 404);
            }
            $type = $record['type'];
            $domain = NativeCryptoRecordAddressV2::domain($type);
            $expectedKind = $domain === 'finance' ? 'finance' : (in_array($type, ['table','attachment'], true) ? $type : 'record');
            if ($targetType !== $expectedKind) {
                throw new NativeError('report_target_unavailable', 404);
            }
            $scopes->author($scopeId, $head['head_hash'], (int)$head['epoch'], (int)$scope['effective_access_revision'], $actor, $domain, false);
            $authorization = json_decode($record['authorization'], true, 34, JSON_THROW_ON_ERROR);
            if (!isset($authorization['recordProof'])) {
                throw new NativeError('crypto_v1_record_migration_required', 409);
            }
            $proofHash = NativeCryptoV2Codec::hash((object)$authorization['recordProof']);
            $revision = (int)$record['revision'];
        }
        return [
            'scopeId' => $scopeId,
            'targetType' => $targetType,
            'targetId' => $targetId,
            'type' => $type,
            'domain' => $domain,
            'targetRevision' => $revision,
            'recordProofHash' => $proofHash,
            'membershipHeadHash' => $head['head_hash'],
            'accessRevision' => (int)$scope['effective_access_revision'],
        ];
    }

    public function preview($params, $actor)
    {
        return [
            'serverId' => $this->serverId(),
            'accountId' => $actor['user']['account_id'],
            'sourceContext' => $this->source($params, $actor),
            'recipient' => $this->recipient(),
            'reportRetentionDays' => 180,
            'evidenceTrust' => 'reporterDisclosed',
        ];
    }

    public function currentSource($source, $actor)
    {
        if (!is_array($source)) {
            throw new NativeError('validation_error');
        }
        $this->fields($source, ['scopeId','targetType','targetId','type','domain','targetRevision','recordProofHash','membershipHeadHash','accessRevision']);
        $current = $this->source(array_intersect_key($source, array_flip(['scopeId','targetType','targetId'])), $actor);
        if (NativeCryptoCodec::canonical((object)$source) !== NativeCryptoCodec::canonical((object)$current)) {
            throw new NativeError('report_preview_changed', 409);
        }
        return $current;
    }

    /** A prior receipt remains readable only by its own currently scoped reader. */
    public function replayAccess($payload, $actor)
    {
        $source = $payload['sourceContext'] ?? null;
        if (!is_array($source)) {
            throw new NativeError('validation_error');
        }
        $scopeId = $this->uuid($source['scopeId'] ?? null);
        $scope = $this->scope($scopeId, $actor['user']['id']);
        if ($scope['kind'] === 'personal') {
            throw new NativeError('personal_not_shareable', 403);
        }
        if (($source['domain'] ?? null) === 'finance') {
            (new NativeFinanceAccess($this->container))->policyForCrypto($scopeId, $actor['user'], false, true);
        }
    }

    public function report($payload, $actor, $proof, $command)
    {
        $this->fields($payload, ['reportId','sourceContext','authorDirectoryHeadHash','consentVersion','disclosure','reason','details'], ['snapshotStageId','assetStageIds']);
        $id = $this->uuid($payload['reportId']);
        if ($payload['consentVersion'] !== 1 ||
            !in_array($payload['reason'], NativeModerationService::REASONS, true)) {
            throw new NativeError('validation_error');
        }
        $this->text($payload['details'], 2000, true);
        $source = $this->currentSource($payload['sourceContext'], $actor);
        (new NativeCryptoScopeV2($this->container))->currentAuthorReference($payload['authorDirectoryHeadHash'], $actor);
        $disclosure = $payload['disclosure'];
        $staging = new NativeCryptoModerationDisclosureV2($this->container, $this->bearer, $this->ip);
        $snapshotStage = $payload['snapshotStageId'] ?? null;
        if ($snapshotStage !== null) {
            if ($disclosure !== null) {
                throw new NativeError('validation_error');
            }
            $stage = $staging->forReport($snapshotStage, $id, $source, $actor, 'snapshot');
            $disclosure = $staging->snapshot($stage);
        }
        if (!is_array($disclosure)) {
            throw new NativeError('validation_error');
        }
        $this->fields($disclosure, ['subject','evidence']);
        if (!is_array($disclosure['subject']) || !is_array($disclosure['evidence'])) {
            throw new NativeError('validation_error');
        }
        $this->fields($disclosure['subject'], ['title','type']);
        $this->text($disclosure['subject']['title'], 200, true);
        if ($disclosure['subject']['type'] !== $source['type']) {
            throw new NativeError('report_preview_changed', 409);
        }
        if ($snapshotStage === null && strlen(json_encode($disclosure, JSON_THROW_ON_ERROR)) > 131072) {
            throw new NativeError('crypto_report_disclosure_stage_required', 413);
        }
        $assets = $payload['assetStageIds'] ?? [];
        if (!is_array($assets) || !array_is_list($assets) || count($assets) > 20 || count(array_unique($assets, SORT_REGULAR)) !== count($assets)) {
            throw new NativeError('validation_error');
        }
        $assetDescriptors = [];
        foreach ($assets as $assetId) {
            $asset = $staging->forReport($assetId, $id, $source, $actor, 'asset');
            $assetDescriptors[] = $staging->assetDescriptor($asset);
        }
        usort($assetDescriptors, fn ($a, $b) => strcmp($a['sha256'], $b['sha256']));
        if ((isset($disclosure['evidence']['assets']) || $assetDescriptors) && ($source['type'] !== 'idea' ||
            NativeCryptoCodec::canonical($disclosure['evidence']['assets'] ?? null) !== NativeCryptoCodec::canonical($assetDescriptors))) {
            throw new NativeError('crypto_report_assets_changed', 409);
        }
        if (isset($disclosure['evidence']['board'])) {
            if ($source['type'] !== 'idea') {
                throw new NativeError('validation_error');
            }
            (new NativeIdeaPolicy($this->container))->disclosure($disclosure['evidence']['board']);
            $used = [];
            foreach ($disclosure['evidence']['board']['elements'] as $element) {
                if ($element['kind'] === 'image') {
                    $used[$element['asset']['sha256']] = true;
                }
            }
            $selected = array_column($assetDescriptors, 'sha256');
            if (array_diff(array_keys($used), $selected) || array_diff($selected, array_keys($used))) {
                throw new NativeError('crypto_report_assets_changed', 409);
            }
        } elseif ($assetDescriptors) {
            throw new NativeError('crypto_report_assets_changed', 409);
        }
        // This hash is inside the intentionally disclosed moderation exception.
        // It is never a public commitment to otherwise secret source plaintext.
        $snapshot = [
            'serverId' => $this->serverId(),
            'accountId' => $actor['user']['account_id'],
            'scopeId' => $source['scopeId'],
            'targetType' => $source['targetType'],
            'targetId' => $source['targetId'],
            'targetRevision' => $source['targetRevision'],
            'subject' => $disclosure['subject'],
            'evidence' => $disclosure['evidence'],
            'recipient' => $this->recipient(),
            'evidenceTrust' => 'reporterDisclosed',
            'sourceContext' => $source,
        ];
        $snapshot['previewHash'] = hash('sha256', $this->canonical($snapshot));
        if ($this->one('SELECT id FROM familyhub_moderation_reports WHERE id=?', [$id])) {
            throw new NativeError('idempotency_mismatch', 409);
        }
        // The caller already holds the global SQL lock. Count durable outcomes
        // here instead of opening a nested rate-limit transaction; exact saved
        // receipts bypass this path and never consume another report slot.
        $recent = $this->one('SELECT COUNT(*) AS count,MIN(created_at) AS first_at FROM familyhub_moderation_reports WHERE reporter_account_id=? AND created_at>?', [$actor['user']['account_id'],time() - 3600]);
        if ((int)$recent['count'] >= 20) {
            throw new NativeError('rate_limited', 429, ['retryAfter' => max(1,(int)$recent['first_at'] + 3600 - time())]);
        }
        $created = time();
        $requestHash = hash('sha256', base64_decode($proof['commandBase64'], true));
        $this->change('INSERT INTO familyhub_moderation_reports(id,reporter_account_id,request_id,request_hash,scope_id,target_type,target_id,target_revision,preview_hash,reason,details,snapshot,created_at,status) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?)', [
            $id,$actor['user']['account_id'],$command['requestId'],$requestHash,
            $source['scopeId'],$source['targetType'],$source['targetId'],$source['targetRevision'],
            $snapshot['previewHash'],$payload['reason'],$payload['details'],
            $this->canonical($snapshot),$created,'submitted',
        ]);
        $this->change('INSERT INTO familyhub_crypto_moderation_reports_v2(report_id,account_id,authorization,source_context) VALUES(?,?,?,?)', [
            $id,$actor['user']['account_id'],json_encode($proof, JSON_THROW_ON_ERROR),NativeCryptoCodec::canonical((object)$source),
        ]);
        foreach (array_merge($snapshotStage === null ? [] : [$snapshotStage], $assets) as $stageId) {
            $this->change('UPDATE familyhub_crypto_moderation_stages_v2 SET included=1 WHERE id=?', [$stageId]);
        }
        return ['reportId' => $id,'status' => 'submitted','createdAt' => gmdate('Y-m-d\TH:i:s\Z', $created),'serverId' => $this->serverId()];
    }
}
