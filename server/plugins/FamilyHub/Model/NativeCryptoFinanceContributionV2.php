<?php

namespace Kanboard\Plugin\FamilyHub\Model;

/** Two-party finance-key rotation. A content manager never needs a finance domain key. */
class NativeCryptoFinanceContributionV2 extends NativeDatabase
{
    protected $cryptoAccess = true;
    public const KEY_DOMAIN = "JivieE2EE/financeKeyProposal/v2\n";
    public const MANIFEST_DOMAIN = "JivieE2EE/financeGrantManifest/v2\n";

    public static function core($body)
    {
        unset($body['financeKeyProposalProof'], $body['contentKeyProposalProof']);
        return $body;
    }

    public static function coreHash($core)
    {
        return hash('sha256', "JivieScopeHeadCore/v2\n".NativeCryptoCodec::canonical((object)$core));
    }

    public function verifyKey($body, $source, $scope, $headAuthorAccount, $requireDraft = true)
    {
        $proof = $body['financeKeyProposalProof'];
        if ($body['keyIds']['finance'] === null) {
            if ($proof !== null) {
                throw new NativeError('crypto_finance_contribution_unexpected', 409);
            }
            return null;
        }
        if (!is_array($proof)) {
            throw new NativeError('crypto_finance_contribution_required', 409);
        }
        [$card, $bytes, $signature] = NativeCryptoCodec::decode($proof);
        $this->fields($card, ['version', 'operation', 'serverId', 'scopeId', 'epoch', 'previousHeadHash', 'proposalContextHash', 'keyId', 'keyCommitment', 'accountId', 'deviceId', 'authorDirectoryHeadHash']);
        if ($card['version'] !== 2 || $card['operation'] !== 'crypto2.scope.financeKeyProposal' || $card['serverId'] !== $this->serverId() || $card['scopeId'] !== $body['scopeId'] || $card['epoch'] !== $body['epoch'] || $card['previousHeadHash'] !== $body['previousHeadHash'] || $card['proposalContextHash'] !== self::coreHash(self::core($body)) || $card['keyId'] !== $body['keyIds']['finance'] || $card['keyCommitment'] !== $body['keyCommitments']['finance']) {
            throw new NativeError('crypto_finance_contribution_binding', 403);
        }
        $key = $this->financeAuthor($body, $source, $card);
        NativeCryptoV2Codec::verify($bytes, $signature, $key, self::KEY_DOMAIN);
        if ($requireDraft && $card['accountId'] !== $headAuthorAccount && !(new NativeCryptoKeyContributionV2($this->container, $this->bearer, $this->ip))->selected($body, 'finance', $proof)) {
            $draft = $this->one("SELECT * FROM familyhub_crypto_finance_drafts WHERE scope_id=? AND contribution_proof_hash=? AND state='contributed'", [$scope['id'], NativeCryptoV2Codec::hash((object)$proof)]);
            if (!$draft || (int)$draft['expires_at'] <= time() || $draft['contribution_core'] !== NativeCryptoCodec::canonical((object)self::core($body))) {
                throw new NativeError('crypto_finance_draft_expired', 409);
            }
        }
        return $card;
    }

    public function financeAuthor($body, $source, $card)
    {
        $account = $this->uuid($card['accountId']);
        $deviceId = $this->uuid($card['deviceId']);
        $scopes = new NativeCryptoScopeV2($this->container, $this->bearer, $this->ip);
        $member = $scopes->member($body, $account);
        $previous = $source ? $scopes->member($scopes->body($source), $account) : $member;
        $firstDomain = $source && $scopes->body($source)['keyIds']['finance'] === null;
        if ($firstDomain) {
            if ($scopes->domainHasRecords($body['scopeId'], 'finance') || $this->one("SELECT id FROM familyhub_crypto_record_history WHERE scope_id=? AND domain='finance' LIMIT 1", [$body['scopeId']])) {
                throw new NativeError('crypto_finance_history_migration_required', 409);
            }
            foreach (['finance_records', 'finance_audit', 'payment_events', 'payment_projections', 'payment_cash'] as $table) {
                if ($this->one('SELECT scope_id FROM familyhub_'.$table.' WHERE scope_id=? LIMIT 1', [$body['scopeId']])) {
                    throw new NativeError('crypto_finance_history_migration_required', 409);
                }
            }
        }
        if (!$member || $member['financeRole'] === 'none' || !$previous || !$firstDomain && $previous['financeRole'] === 'none') {
            throw new NativeError('finance_forbidden', 403);
        }
        $user = $this->one('SELECT a.account_id,u.* FROM familyhub_accounts a JOIN users u ON u.id=a.user_id WHERE a.account_id=? AND u.is_active=1', [$account]);
        if (!$user) {
            throw new NativeError('finance_forbidden', 403);
        }
        (new NativeCryptoFinancePolicyV2($this->container, $this->bearer, $this->ip))->financeRead($body, $source, $user);
        (new NativeConnectedWritePolicy($this->container))->requireAccount($account);
        $scopes->currentAuthorReference($card['authorDirectoryHeadHash'], ['user' => $user, 'device' => ['id' => $deviceId]]);
        $directory = new NativeCryptoDirectoryV2($this->container);
        $current = $directory->current($account);
        $device = $directory->device(json_decode($current['snapshot'], true, 34, JSON_THROW_ON_ERROR), $deviceId);
        return $device['signingKeyBase64'];
    }

    public function verifyManifest($body, $source, $scope, $headHash, $root, $proof)
    {
        if ($body['keyIds']['finance'] === null) {
            if ($proof !== null) {
                throw new NativeError('crypto_finance_contribution_unexpected', 409);
            }
            return;
        }
        if (!is_array($proof)) {
            throw new NativeError('crypto_finance_manifest_required', 409);
        }
        [$manifest, $bytes, $signature] = NativeCryptoCodec::decode($proof);
        $this->fields($manifest, ['version', 'operation', 'serverId', 'scopeId', 'headHash', 'financeManifestHash', 'accountId', 'deviceId', 'authorDirectoryHeadHash']);
        if ($manifest['version'] !== 2 || $manifest['operation'] !== 'crypto2.scope.financeGrantManifest' || $manifest['serverId'] !== $this->serverId() || $manifest['scopeId'] !== $scope['id'] || $manifest['headHash'] !== $headHash || $manifest['financeManifestHash'] !== $root) {
            throw new NativeError('crypto_finance_manifest_binding', 403);
        }
        [$card] = NativeCryptoCodec::decode($body['financeKeyProposalProof']);
        if ($manifest['accountId'] !== $card['accountId'] || $manifest['deviceId'] !== $card['deviceId']) {
            // Successor delegation needs a separate verified proof; no unsigned issuer substitution.
            throw new NativeError('crypto_finance_contributor_changed', 403);
        }
        NativeCryptoV2Codec::verify($bytes, $signature, $this->financeAuthor($body, $source, $manifest), self::MANIFEST_DOMAIN);
    }

    public function expiresAt($body)
    {
        if (!is_array($body['financeKeyProposalProof'] ?? null)) {
            return null;
        }
        $row = $this->one('SELECT expires_at,state FROM familyhub_crypto_finance_drafts WHERE scope_id=? AND contribution_proof_hash=?', [$body['scopeId'], NativeCryptoV2Codec::hash((object)$body['financeKeyProposalProof'])]);
        return $row ? ($row['state'] === 'cancelled' ? 0 : (int)$row['expires_at']) : null;
    }

    public function write($op, $p, $actor, $proof)
    {
        $sid = $this->uuid($p['scopeId'] ?? null);
        $scope = $this->scope($sid, $actor['user']['id']);
        $scopes = new NativeCryptoScopeV2($this->container, $this->bearer, $this->ip);
        $source = $scopes->current($sid);
        if((new NativeCryptoMigrationGenerationV3($this->container,$this->bearer,$this->ip))->financePreview($sid,$p['draftId']??null,$p['core']??null))$source=null;
        $scopes->refreshPending($sid, $source);
        if ($op === 'crypto2.scope.financeDraft.cancel') {
            $this->fields($p, ['scopeId', 'draftId']);
            $scopes->manager($source, $scope, $actor);
            $draft = $this->draft($sid, $p['draftId']);
            $this->change("UPDATE familyhub_crypto_finance_drafts SET state='cancelled' WHERE scope_id=? AND id=?", [$sid, $draft['id']]);
            $scopes->refreshPending($sid, $source);
            return ['scopeId' => $sid, 'draftId' => $draft['id'], 'state' => 'cancelled'];
        }
        if ($op === 'crypto2.scope.financeManifest.put') {
            $this->fields($p, ['scopeId', 'headHash', 'financeGrantManifestProof']);
            $candidate = $scopes->head($sid, $p['headHash']);
            if ($candidate['state'] !== 'pending' || $candidate['previous_head_hash'] !== ($source['head_hash'] ?? NativeCryptoDirectoryV2::ZERO)) {
                throw new NativeError('crypto_scope_head_conflict', 409);
            }
            $body = $scopes->body($candidate);
            [$manifest] = NativeCryptoCodec::decode($p['financeGrantManifestProof']);
            if ($manifest['accountId'] !== $actor['user']['account_id'] || $manifest['deviceId'] !== $actor['device']['id']) {
                throw new NativeError('crypto_identity_mismatch', 403);
            }
            $roots = ['finance' => $scopes->grantDomainRoot($body, 'finance', true)];
            $this->verifyManifest($body, $source, $scope, $candidate['head_hash'], $roots['finance'], $p['financeGrantManifestProof']);
            $old = $this->one('SELECT authorization FROM familyhub_crypto_finance_manifests WHERE scope_id=? AND head_hash=?', [$sid, $candidate['head_hash']]);
            $encoded = json_encode($p['financeGrantManifestProof'], JSON_THROW_ON_ERROR);
            if ($old && json_decode($old['authorization'], true, 34, JSON_THROW_ON_ERROR) !== $p['financeGrantManifestProof']) {
                throw new NativeError('crypto_finance_manifest_immutable', 409);
            }
            if (!$old) {
                $this->change('INSERT INTO familyhub_crypto_finance_manifests VALUES(?,?,?,?)', [$sid, $candidate['head_hash'], $roots['finance'], $encoded]);
            }
            return ['scopeId' => $sid, 'headHash' => $candidate['head_hash'], 'financeManifestHash' => $roots['finance']];
        }
        if ($op === 'crypto2.scope.financeDraft.put') {
            $this->fields($p, ['scopeId', 'draftId', 'core']);
            $id = $this->uuid($p['draftId']);
            if (!is_array($p['core']) || isset($p['core']['financeKeyProposalProof'])) {
                throw new NativeError('validation_error');
            }
            $body = $p['core'] + ['contentKeyProposalProof' => null, 'financeKeyProposalProof' => null];
            $scopes->validateProposal($body);
            if ($body['scopeId'] !== $sid || $body['previousHeadHash'] !== ($source['head_hash'] ?? NativeCryptoDirectoryV2::ZERO) || $body['epoch'] !== ($source ? (int)$source['epoch'] + 1 : 1) || $body['keyIds']['finance'] !== null || $body['keyCommitments']['finance'] !== null || $body['closures']['finance'] !== null || !array_filter($body['members'], fn ($m) => $m['financeRole'] !== 'none')) {
                throw new NativeError('crypto_finance_draft_invalid', 409);
            }
            $scopes->manager($source, $scope, $actor);
            $scopes->currentAuthorReference($body['authorDirectoryHeadHash'], $actor);
            $scopes->validateMembershipPlan($scope, $body, $source, $actor);
            $old = $this->one('SELECT * FROM familyhub_crypto_finance_drafts WHERE scope_id=? AND id=?', [$sid, $id]);
            $core = NativeCryptoCodec::canonical((object)$p['core']);
            if ($old) {
                if ($old['core'] !== $core || $old['owner_account_id'] !== $actor['user']['account_id'] || (int)$old['expires_at'] <= time()) {
                    throw new NativeError('crypto_finance_draft_immutable', 409);
                }
                return ['scopeId' => $sid, 'draftId' => $id, 'state' => $old['state'], 'expiresAt' => (int)$old['expires_at']];
            }
            $count = $this->one("SELECT COUNT(*) AS n FROM familyhub_crypto_finance_drafts WHERE scope_id=? AND state IN ('pending','contributed') AND expires_at>?", [$sid, time()]);
            if ((int)$count['n'] >= 16) {
                throw new NativeError('crypto_scope_candidates_full', 409);
            }
            $this->change('INSERT INTO familyhub_crypto_finance_drafts(scope_id,id,owner_account_id,owner_device_id,core,authorization,created_at,expires_at,state) VALUES(?,?,?,?,?,?,?,?,?)', [$sid, $id, $actor['user']['account_id'], $actor['device']['id'], $core, json_encode($proof, JSON_THROW_ON_ERROR), time(), time() + 1800, 'pending']);
            return ['scopeId' => $sid, 'draftId' => $id, 'state' => 'pending', 'expiresAt' => time() + 1800];
        }
        $this->fields($p, ['scopeId', 'draftId', 'keyId', 'keyCommitment', 'financeClosureHash', 'financeKeyProposalProof']);
        if ($op !== 'crypto2.scope.financeDraft.contribute') {
            throw new NativeError('unsupported_operation', 404);
        }
        $draft = $this->draft($sid, $p['draftId']);
        $core = json_decode($draft['core'], true, 34, JSON_THROW_ON_ERROR);
        $core['keyIds']['finance'] = $this->uuid($p['keyId']);
        $core['keyCommitments']['finance'] = $p['keyCommitment'];
        $core['closures']['finance'] = $p['financeClosureHash'];
        $body = $core + ['contentKeyProposalProof' => null, 'financeKeyProposalProof' => $p['financeKeyProposalProof']];
        $scopes->validateProposal($body);
        $card = $this->verifyKey($body, $source, $scope, $draft['owner_account_id'], false);
        if ($card['accountId'] !== $actor['user']['account_id'] || $card['deviceId'] !== $actor['device']['id'] || $body['previousHeadHash'] !== ($source['head_hash'] ?? NativeCryptoDirectoryV2::ZERO)) {
            throw new NativeError('crypto_finance_contribution_binding', 403);
        }
        $creator = $this->one('SELECT a.account_id,u.* FROM familyhub_accounts a JOIN users u ON u.id=a.user_id WHERE a.account_id=?', [$draft['owner_account_id']]);
        $creatorActor = ['user' => $creator, 'device' => ['id' => $draft['owner_device_id']]];
        $scopes->manager($source, $scope, $creatorActor);
        $scopes->currentAuthorReference($body['authorDirectoryHeadHash'], $creatorActor);
        $scopes->validateMembershipPlan($scope, $body, $source, $creatorActor);
        $priorFinance = $source ? $scopes->body($source)['keyIds']['finance'] : null;
        if (($priorFinance === null) !== ($body['closures']['finance'] === null)) {
            throw new NativeError('crypto_closure_required', 409);
        }
        $encoded = NativeCryptoCodec::canonical((object)$core);
        $proofHash = NativeCryptoV2Codec::hash((object)$p['financeKeyProposalProof']);
        if ($draft['state'] === 'contributed') {
            if ($draft['contribution_core'] !== $encoded || $draft['contribution_proof_hash'] !== $proofHash) {
                throw new NativeError('crypto_finance_contribution_immutable', 409);
            }
        } else {
            $headHash = hash('sha256', "JivieScopeHead/v2\n".NativeCryptoCodec::canonical((object)$body));
            foreach (['content','finance'] as $domain) {
                if ($this->one('SELECT key_id FROM familyhub_crypto_domain_keys WHERE key_id=? OR key_commitment=?', [$body['keyIds'][$domain], $body['keyCommitments'][$domain]])) {
                    throw new NativeError('crypto_scope_key_reused', 409);
                }
                $this->change('INSERT INTO familyhub_crypto_domain_keys VALUES(?,?,?,?,?)', [$body['keyIds'][$domain], $body['keyCommitments'][$domain], $sid, $headHash, $domain]);
            }
            $this->change("UPDATE familyhub_crypto_finance_drafts SET state='contributed',contribution_core=?,contribution_proof=?,contribution_proof_hash=? WHERE scope_id=? AND id=?", [$encoded, json_encode($p['financeKeyProposalProof'], JSON_THROW_ON_ERROR), $proofHash, $sid, $draft['id']]);
        }
        return ['scopeId' => $sid, 'draftId' => $draft['id'], 'core' => $core, 'financeKeyProposalProof' => $p['financeKeyProposalProof'], 'state' => 'contributed', 'expiresAt' => (int)$draft['expires_at']];
    }

    public function read($op, $p, $actor)
    {
        $required = $op === 'crypto2.scope.financeDraft.list' ? ['scopeId'] : ['scopeId', 'draftId'];
        $this->fields($p, $required, $op === 'crypto2.scope.financeDraft.list' ? ['afterId','limit'] : []);
        $sid = $this->uuid($p['scopeId']);
        $scope = $this->scope($sid, $actor['user']['id']);
        $scopes = new NativeCryptoScopeV2($this->container, $this->bearer, $this->ip);
        $source = $scopes->current($sid);
        if((new NativeCryptoMigrationGenerationV3($this->container,$this->bearer,$this->ip))->financePreview($sid,$p['draftId']??null,$p['core']??null))$source=null;
        $member = $source ? $scopes->member($scopes->body($source), $actor['user']['account_id']) : null;
        try {
            (new NativeFinanceAccess($this->container))->policyForCrypto($sid, $actor['user'], false, true);
            if ($source && (!$member || $member['financeRole'] === 'none')) {
                throw new NativeError('finance_forbidden', 403);
            }
        } catch (NativeError $error) {
            if ($error->status !== 403) {
                throw $error;
            }
            $scopes->manager($source, $scope, $actor);
        }
        if ($op === 'crypto2.scope.financeDraft.get') {
            return $this->draftWire($this->draft($sid, $p['draftId']));
        }
        $after = isset($p['afterId']) ? $this->uuid($p['afterId']) : '';
        $limit = $p['limit'] ?? 20;
        if (!is_int($limit) || $limit < 1 || $limit > 20) {
            throw new NativeError('invalid_cursor');
        }
        $rows = $this->many("SELECT * FROM familyhub_crypto_finance_drafts WHERE scope_id=? AND id>? AND state IN ('pending','contributed') AND expires_at>? ORDER BY id LIMIT ".($limit + 1), [$sid,$after,time()]);
        $out = [];
        $bytes = 0;
        foreach ($rows as $row) {
            $wire = $this->draftWire($row);
            $size = strlen(json_encode($wire, JSON_THROW_ON_ERROR));
            if (count($out) === $limit || $out && $bytes + $size > 1250000) {
                break;
            }
            $out[] = $wire;
            $bytes += $size;
        }
        return ['drafts' => $out, 'hasMore' => count($rows) > count($out), 'nextAfterId' => $out ? end($out)['draftId'] : null];
    }

    private function draft($sid, $id)
    {
        $row = $this->one('SELECT * FROM familyhub_crypto_finance_drafts WHERE scope_id=? AND id=?', [$sid, $this->uuid($id)]);
        if (!$row || (int)$row['expires_at'] <= time() || !in_array($row['state'], ['pending','contributed'], true)) {
            throw new NativeError('crypto_finance_draft_expired', 409);
        }
        return $row;
    }

    private function draftWire($row)
    {
        return ['scopeId' => $row['scope_id'], 'draftId' => $row['id'], 'core' => json_decode($row['core'], true, 34, JSON_THROW_ON_ERROR), 'authorization' => json_decode($row['authorization'], true, 34, JSON_THROW_ON_ERROR), 'state' => $row['state'], 'expiresAt' => (int)$row['expires_at'], 'contribution' => $row['contribution_core'] ? ['core' => json_decode($row['contribution_core'], true, 34, JSON_THROW_ON_ERROR), 'financeKeyProposalProof' => json_decode($row['contribution_proof'], true, 34, JSON_THROW_ON_ERROR)] : null];
    }
}
