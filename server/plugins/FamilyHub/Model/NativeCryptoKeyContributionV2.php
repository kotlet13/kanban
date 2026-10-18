<?php

namespace Kanboard\Plugin\FamilyHub\Model;

/** Independently generated future-domain keys: immutable offers, then final-core countersignatures. */
class NativeCryptoKeyContributionV2 extends NativeDatabase
{
    protected $cryptoAccess = true;
    public const KEY_DOMAIN = "JivieE2EE/contentKeyProposal/v2\n";
    public const MANIFEST_DOMAIN = "JivieE2EE/contentGrantManifest/v2\n";

    public function verifyContent($body, $source, $scope, $managerAccount)
    {
        $proof = $body['contentKeyProposalProof'];
        $scopes = new NativeCryptoScopeV2($this->container, $this->bearer, $this->ip);
        if ($proof === null) {
            if (!$scopes->member($body, $managerAccount)) {
                throw new NativeError('crypto_content_contribution_required', 409);
            }
            return;
        }
        $card = $this->card($body, 'content', $proof, $source);
        if (!$this->selected($body, 'content', $proof)) {
            throw new NativeError('crypto_key_draft_expired', 409);
        }
        return $card;
    }

    public function authorizeNewGrant($body, $source, $scope, $actor, $domain)
    {
        $proof = $body[$domain.'KeyProposalProof'];
        if (!is_array($proof)) {
            throw new NativeError('crypto_key_contribution_required', 409);
        }
        $card = $this->card($body, $domain, $proof, $source);
        if ($card['accountId'] !== $actor['user']['account_id'] || $card['deviceId'] !== $actor['device']['id']) {
            throw new NativeError('crypto_key_contributor_required', 403);
        }
    }

    private function card($body, $domain, $proof, $source)
    {
        [$card, $bytes, $signature] = NativeCryptoCodec::decode($proof);
        $this->fields($card, ['version','operation','serverId','scopeId','epoch','previousHeadHash','proposalContextHash','keyId','keyCommitment','accountId','deviceId','authorDirectoryHeadHash']);
        if ($card['version'] !== 2 || $card['operation'] !== 'crypto2.scope.'.$domain.'KeyProposal' || $card['serverId'] !== $this->serverId() || $card['scopeId'] !== $body['scopeId'] || $card['epoch'] !== $body['epoch'] || $card['previousHeadHash'] !== $body['previousHeadHash'] || $card['proposalContextHash'] !== NativeCryptoFinanceContributionV2::coreHash(NativeCryptoFinanceContributionV2::core($body)) || $card['keyId'] !== $body['keyIds'][$domain] || $card['keyCommitment'] !== $body['keyCommitments'][$domain]) {
            throw new NativeError('crypto_key_contribution_binding', 403);
        }
        $key = $this->author($body, $source, $card, $domain);
        NativeCryptoV2Codec::verify($bytes, $signature, $key, $domain === 'content' ? self::KEY_DOMAIN : NativeCryptoFinanceContributionV2::KEY_DOMAIN);
        return $card;
    }

    private function author($body, $source, $card, $domain)
    {
        if ($domain === 'finance') {
            return (new NativeCryptoFinanceContributionV2($this->container, $this->bearer, $this->ip))->financeAuthor($body, $source, $card);
        }
        $scopes = new NativeCryptoScopeV2($this->container, $this->bearer, $this->ip);
        $id = $this->uuid($card['accountId']);
        $deviceId = $this->uuid($card['deviceId']);
        $member = $scopes->member($body, $id);
        if (!$member || $member['role'] !== 'owner' && !$member['manageKeys']) {
            throw new NativeError('crypto_key_contributor_forbidden', 403);
        }
        $user = $this->one('SELECT a.account_id,u.* FROM familyhub_accounts a JOIN users u ON u.id=a.user_id WHERE a.account_id=? AND u.is_active=1', [$id]);
        if (!$user) {
            throw new NativeError('permission_revoked', 403);
        }
        $this->scope($body['scopeId'], $user['id']);
        (new NativeConnectedWritePolicy($this->container))->requireAccount($id);
        $scopes->currentAuthorReference($card['authorDirectoryHeadHash'], ['user' => $user,'device' => ['id' => $deviceId]]);
        $directory = new NativeCryptoDirectoryV2($this->container);
        $current = $directory->current($id);
        $device = $directory->device(json_decode($current['snapshot'], true, 34, JSON_THROW_ON_ERROR), $deviceId);
        return $device['signingKeyBase64'];
    }

    public function selected($body, $domain, $proof)
    {
        $rows = $this->many("SELECT d.*,o.signature_proof FROM familyhub_crypto_key_drafts d JOIN familyhub_crypto_key_offers o ON o.scope_id=d.scope_id AND o.draft_id=d.id WHERE d.scope_id=? AND o.domain=? AND d.state='ready' AND d.expires_at>?", [$body['scopeId'],$domain,time()]);
        foreach ($rows as $row) {
            if ($row['signature_proof'] && json_decode($row['signature_proof'], true, 34, JSON_THROW_ON_ERROR) === $proof && NativeCryptoCodec::canonical((object)$this->filled($row)) === NativeCryptoCodec::canonical((object)NativeCryptoFinanceContributionV2::core($body))) {
                return true;
            }
        }
        return false;
    }

    public function claimReservation($body, $domain, $row, $headHash)
    {
        if ($row['key_id'] !== $body['keyIds'][$domain] || $row['key_commitment'] !== $body['keyCommitments'][$domain] || $row['scope_id'] !== $body['scopeId'] || $row['domain'] !== $domain || !is_array($body[$domain.'KeyProposalProof']) || !$this->selected($body, $domain, $body[$domain.'KeyProposalProof'])) {
            return false;
        }
        $draft = $this->one('SELECT draft_hash FROM familyhub_crypto_key_drafts WHERE scope_id=? AND draft_hash=? AND state=? AND expires_at>?', [$body['scopeId'],$row['head_hash'],'ready',time()]);
        if (!$draft) {
            return false;
        }
        $this->change('UPDATE familyhub_crypto_domain_keys SET head_hash=? WHERE key_id=?', [$headHash,$row['key_id']]);
        return true;
    }

    public function verifyManifest($body, $source, $scope, $headHash, $root, $proof)
    {
        if ($body['contentKeyProposalProof'] === null) {
            if ($proof !== null) {
                throw new NativeError('crypto_content_manifest_unexpected', 409);
            }
            return;
        }
        if (!is_array($proof)) {
            throw new NativeError('crypto_content_manifest_required', 409);
        }
        [$manifest,$bytes,$signature] = NativeCryptoCodec::decode($proof);
        $this->fields($manifest, ['version','operation','serverId','scopeId','headHash','contentManifestHash','accountId','deviceId','authorDirectoryHeadHash']);
        [$card] = NativeCryptoCodec::decode($body['contentKeyProposalProof']);
        if ($manifest['version'] !== 2 || $manifest['operation'] !== 'crypto2.scope.contentGrantManifest' || $manifest['serverId'] !== $this->serverId() || $manifest['scopeId'] !== $body['scopeId'] || $manifest['headHash'] !== $headHash || $manifest['contentManifestHash'] !== $root || $manifest['accountId'] !== $card['accountId'] || $manifest['deviceId'] !== $card['deviceId']) {
            throw new NativeError('crypto_content_manifest_binding', 403);
        }
        NativeCryptoV2Codec::verify($bytes, $signature, $this->author($body, $source, $manifest, 'content'), self::MANIFEST_DOMAIN);
    }

    public function write($op, $p, $actor, $proof)
    {
        $sid = $this->uuid($p['scopeId'] ?? null);
        $scope = $this->scope($sid, $actor['user']['id']);
        $scopes = new NativeCryptoScopeV2($this->container, $this->bearer, $this->ip);
        $source = $scopes->current($sid);
        $scopes->refreshPending($sid, $source);
        if ($op === 'crypto2.scope.ownerAcceptance.put') {
            $this->fields($p, ['scopeId','headHash','ownerAcceptanceProof']);
            $candidate = $scopes->head($sid, $p['headHash']);
            if ($candidate['state'] !== 'pending' || $candidate['previous_head_hash'] !== ($source['head_hash'] ?? NativeCryptoDirectoryV2::ZERO)) {
                throw new NativeError('crypto_scope_head_conflict', 409);
            }
            $body = $scopes->body($candidate);
            [$proposal] = NativeCryptoCodec::decode(json_decode($candidate['authorization'], true, 34, JSON_THROW_ON_ERROR));
            $creator = $this->one('SELECT a.account_id,u.* FROM familyhub_accounts a JOIN users u ON u.id=a.user_id WHERE a.account_id=?', [$proposal['accountId']]);
            $plan = $scopes->validateMembershipPlan($scope, $body, $source, ['user' => $creator,'device' => ['id' => $proposal['deviceId']]]);
            [$acceptance] = NativeCryptoCodec::decode($p['ownerAcceptanceProof']);
            if ($acceptance['accountId'] !== $actor['user']['account_id'] || $acceptance['deviceId'] !== $actor['device']['id']) {
                throw new NativeError('crypto_identity_mismatch', 403);
            }
            $roots = $scopes->grantManifest($body, true);
            $hash = NativeCryptoV2Codec::hash((object)$roots);
            $scopes->ownerAcceptance($p + ['grantManifestHash' => $hash], $body, $plan);
            $old = $this->one('SELECT authorization FROM familyhub_crypto_owner_acceptances WHERE scope_id=? AND head_hash=?', [$sid,$p['headHash']]);
            if ($old && json_decode($old['authorization'], true, 34, JSON_THROW_ON_ERROR) !== $p['ownerAcceptanceProof']) {
                throw new NativeError('crypto_owner_acceptance_immutable', 409);
            }
            if (!$old) {
                $this->change('INSERT INTO familyhub_crypto_owner_acceptances VALUES(?,?,?)', [$sid,$p['headHash'],json_encode($p['ownerAcceptanceProof'], JSON_THROW_ON_ERROR)]);
            }
            return ['scopeId' => $sid,'headHash' => $p['headHash'],'grantManifestHash' => $hash];
        }
        if ($op === 'crypto2.scope.contentManifest.put') {
            $this->fields($p, ['scopeId','headHash','contentGrantManifestProof']);
            $candidate = $scopes->head($sid, $p['headHash']);
            if ($candidate['state'] !== 'pending' || $candidate['previous_head_hash'] !== ($source['head_hash'] ?? NativeCryptoDirectoryV2::ZERO)) {
                throw new NativeError('crypto_scope_head_conflict', 409);
            }
            $body = $scopes->body($candidate);
            [$manifest] = NativeCryptoCodec::decode($p['contentGrantManifestProof']);
            if ($manifest['accountId'] !== $actor['user']['account_id'] || $manifest['deviceId'] !== $actor['device']['id']) {
                throw new NativeError('crypto_identity_mismatch', 403);
            }
            $root = $scopes->grantDomainRoot($body, 'content', true);
            $this->verifyManifest($body, $source, $scope, $p['headHash'], $root, $p['contentGrantManifestProof']);
            $old = $this->one('SELECT authorization FROM familyhub_crypto_content_manifests WHERE scope_id=? AND head_hash=?', [$sid,$p['headHash']]);
            if ($old && json_decode($old['authorization'], true, 34, JSON_THROW_ON_ERROR) !== $p['contentGrantManifestProof']) {
                throw new NativeError('crypto_content_manifest_immutable', 409);
            }
            if (!$old) {
                $this->change('INSERT INTO familyhub_crypto_content_manifests VALUES(?,?,?,?)', [$sid,$p['headHash'],$root,json_encode($p['contentGrantManifestProof'], JSON_THROW_ON_ERROR)]);
            }
            return ['scopeId' => $sid,'headHash' => $p['headHash'],'contentManifestHash' => $root];
        }
        if ($op === 'crypto2.scope.keyDraft.put') {
            $this->fields($p, ['scopeId','draftId','requestedDomains','core']);
            $id = $this->uuid($p['draftId']);
            if (!in_array($p['requestedDomains'], [['content'],['finance'],['content','finance']], true) || !is_array($p['core']) || array_key_exists('contentKeyProposalProof', $p['core']) || array_key_exists('financeKeyProposalProof', $p['core'])) {
                throw new NativeError('validation_error');
            }
            $body = $p['core'] + ['contentKeyProposalProof' => null,'financeKeyProposalProof' => null];
            // Validate the complete public skeleton while preserving requested placeholders.
            $validation = $body;
            foreach ($p['requestedDomains'] as $domain) {
                if ($body['keyIds'][$domain] !== null || $body['keyCommitments'][$domain] !== null || $domain === 'finance' && $body['closures']['finance'] !== null) {
                    throw new NativeError('crypto_key_draft_invalid', 409);
                }
                $validation['keyIds'][$domain] = $domain === 'content' ? '11111111-1111-4111-8111-111111111111' : '22222222-2222-4222-8222-222222222222';
                $validation['keyCommitments'][$domain] = str_repeat($domain === 'content' ? '1' : '2', 64);
            }
            $scopes->validateProposal($validation);
            $scopes->manager($source, $scope, $actor);
            $scopes->currentAuthorReference($body['authorDirectoryHeadHash'], $actor);
            $scopes->validateMembershipPlan($scope, $body, $source, $actor);
            if ($body['scopeId'] !== $sid || $body['previousHeadHash'] !== ($source['head_hash'] ?? NativeCryptoDirectoryV2::ZERO) || $body['epoch'] !== ($source ? (int)$source['epoch'] + 1 : 1)) {
                throw new NativeError('crypto_scope_head_conflict', 409);
            }
            $old = $this->one('SELECT * FROM familyhub_crypto_key_drafts WHERE scope_id=? AND id=?', [$sid,$id]);
            $hash = NativeCryptoV2Codec::hash((object)$proof);
            if ($old) {
                throw new NativeError('crypto_key_draft_immutable', 409);
            }
            $count = $this->one("SELECT COUNT(*) AS n FROM familyhub_crypto_key_drafts WHERE scope_id=? AND expires_at>? AND state IN ('pending','ready')", [$sid,time()]);
            if ((int)$count['n'] >= 16) {
                throw new NativeError('crypto_scope_candidates_full', 409);
            }
            $this->change('INSERT INTO familyhub_crypto_key_drafts VALUES(?,?,?,?,?,?,?,?,?,?,?)', [$sid,$id,$actor['user']['account_id'],$actor['device']['id'],$hash,json_encode($p['requestedDomains'], JSON_THROW_ON_ERROR),NativeCryptoCodec::canonical((object)$p['core']),json_encode($proof, JSON_THROW_ON_ERROR),time(),time() + 1800,'pending']);
            return $this->wire($this->draft($sid, $id));
        }
        $required = ['scopeId','draftId'];
        $this->fields($p, array_merge($required, $op === 'crypto2.scope.keyDraft.offer' ? ['managerDraftHash','domain','keyId','keyCommitment','authorDirectoryHeadHash'] : ($op === 'crypto2.scope.keyDraft.sign' ? ['domain','keyProposalProof'] : [])), $op === 'crypto2.scope.keyDraft.offer' ? ['financeClosureHash'] : []);
        $draft = $this->draft($sid, $p['draftId']);
        $this->managerStillAuthorized($draft, $scope, $source, $scopes);
        if ($op === 'crypto2.scope.keyDraft.cancel') {
            $scopes->manager($source, $scope, $actor);
            $this->change("UPDATE familyhub_crypto_key_drafts SET state='cancelled' WHERE scope_id=? AND id=?", [$sid,$draft['id']]);
            $scopes->refreshPending($sid, $source);
            return ['scopeId' => $sid,'draftId' => $draft['id'],'state' => 'cancelled'];
        }
        $domain = $p['domain'] ?? null;
        if (!in_array($domain, json_decode($draft['domains'], true, 4, JSON_THROW_ON_ERROR), true)) {
            throw new NativeError('crypto_key_contribution_binding', 403);
        }
        $offer = $this->one('SELECT * FROM familyhub_crypto_key_offers WHERE scope_id=? AND draft_id=? AND domain=?', [$sid,$draft['id'],$domain]);
        if ($op === 'crypto2.scope.keyDraft.offer') {
            $this->uuid($p['keyId']);
            if ($p['managerDraftHash'] !== $draft['draft_hash'] || !is_string($p['keyCommitment']) || !preg_match('/^[0-9a-f]{64}$/D', $p['keyCommitment']) || ($domain === 'finance') !== array_key_exists('financeClosureHash', $p)) {
                throw new NativeError('crypto_key_contribution_binding', 403);
            }
            $body = $this->filled($draft);
            $body['keyIds'][$domain] = $p['keyId'];
            $body['keyCommitments'][$domain] = $p['keyCommitment'];
            if ($domain === 'finance') {
                $closure = $p['financeClosureHash'];
                $prior = $source ? $scopes->body($source)['keyIds']['finance'] : null;
                if (($prior === null) !== ($closure === null) || $closure !== null && (!is_string($closure) || !preg_match('/^[a-f0-9]{64}$/D', $closure))) {
                    throw new NativeError('crypto_closure_required', 409);
                }
                $body['closures']['finance'] = $closure;
            }
            $this->author($body, $source, ['accountId' => $actor['user']['account_id'],'deviceId' => $actor['device']['id'],'authorDirectoryHeadHash' => $p['authorDirectoryHeadHash']], $domain);
            if ($offer) {
                throw new NativeError('crypto_key_offer_immutable', 409);
            }
            if ($this->one('SELECT key_id FROM familyhub_crypto_domain_keys WHERE key_id=? OR key_commitment=?', [$p['keyId'],$p['keyCommitment']])) {
                throw new NativeError('crypto_scope_key_reused', 409);
            }
            $this->change('INSERT INTO familyhub_crypto_domain_keys VALUES(?,?,?,?,?)', [$p['keyId'],$p['keyCommitment'],$sid,$draft['draft_hash'],$domain]);
            $this->change('INSERT INTO familyhub_crypto_key_offers VALUES(?,?,?,?,?,?,?,?,?,NULL)', [$sid,$draft['id'],$domain,$p['keyId'],$p['keyCommitment'],$actor['user']['account_id'],$actor['device']['id'],$p['financeClosureHash'] ?? null,json_encode($proof, JSON_THROW_ON_ERROR)]);
        } elseif ($op === 'crypto2.scope.keyDraft.sign') {
            $body = $this->filled($draft);
            foreach (json_decode($draft['domains'], true, 4, JSON_THROW_ON_ERROR) as $needed) {
                if ($body['keyIds'][$needed] === null) {
                    throw new NativeError('crypto_key_offers_incomplete', 409);
                }
            }
            $scopes->validateProposal($body + ['contentKeyProposalProof' => null,'financeKeyProposalProof' => null]);
            $card = $this->card($body, $domain, $p['keyProposalProof'], $source);
            if (!$offer || $offer['account_id'] !== $actor['user']['account_id'] || $offer['device_id'] !== $actor['device']['id'] || $card['accountId'] !== $offer['account_id'] || $card['deviceId'] !== $offer['device_id']) {
                throw new NativeError('crypto_key_contributor_required', 403);
            }
            if ($offer['signature_proof']) {
                throw new NativeError('crypto_key_signature_immutable', 409);
            }
            $this->change('UPDATE familyhub_crypto_key_offers SET signature_proof=? WHERE scope_id=? AND draft_id=? AND domain=?', [json_encode($p['keyProposalProof'], JSON_THROW_ON_ERROR),$sid,$draft['id'],$domain]);
            $remaining = $this->one('SELECT COUNT(*) AS n FROM familyhub_crypto_key_offers WHERE scope_id=? AND draft_id=? AND signature_proof IS NOT NULL', [$sid,$draft['id']]);
            if ((int)$remaining['n'] === count(json_decode($draft['domains'], true, 4, JSON_THROW_ON_ERROR))) {
                $this->change("UPDATE familyhub_crypto_key_drafts SET state='ready' WHERE scope_id=? AND id=?", [$sid,$draft['id']]);
            }
        } else {
            throw new NativeError('unsupported_operation', 404);
        }
        return $this->wire($this->draft($sid, $draft['id']));
    }

    private function managerStillAuthorized($draft, $scope, $source, $scopes)
    {
        $body = json_decode($draft['core'], true, 34, JSON_THROW_ON_ERROR);
        $user = $this->one('SELECT a.account_id,u.* FROM familyhub_accounts a JOIN users u ON u.id=a.user_id WHERE a.account_id=? AND u.is_active=1', [$draft['owner_account_id']]);
        if (!$user || $body['previousHeadHash'] !== ($source['head_hash'] ?? NativeCryptoDirectoryV2::ZERO)) {
            throw new NativeError('crypto_scope_head_conflict', 409);
        }
        $actor = ['user' => $user,'device' => ['id' => $draft['owner_device_id']]];
        $scopes->manager($source, $scope, $actor);
        $scopes->currentAuthorReference($body['authorDirectoryHeadHash'], $actor);
        $scopes->validateMembershipPlan($scope, $body, $source, $actor);
    }

    private function draft($sid, $id)
    {
        $row = $this->one('SELECT * FROM familyhub_crypto_key_drafts WHERE scope_id=? AND id=?', [$sid,$this->uuid($id)]);
        if (!$row || (int)$row['expires_at'] <= time() || !in_array($row['state'], ['pending','ready'], true)) {
            throw new NativeError('crypto_key_draft_expired', 409);
        }
        return $row;
    }

    private function filled($row)
    {
        $core = json_decode($row['core'], true, 34, JSON_THROW_ON_ERROR);
        foreach ($this->many('SELECT * FROM familyhub_crypto_key_offers WHERE scope_id=? AND draft_id=? ORDER BY domain', [$row['scope_id'],$row['id']]) as $offer) {
            $domain = $offer['domain'];
            $core['keyIds'][$domain] = $offer['key_id'];
            $core['keyCommitments'][$domain] = $offer['key_commitment'];
            if ($domain === 'finance') {
                $core['closures']['finance'] = $offer['closure_hash'];
            }
        }
        return $core;
    }

    private function wire($row)
    {
        $offers = [];
        $signatures = [];
        foreach ($this->many('SELECT * FROM familyhub_crypto_key_offers WHERE scope_id=? AND draft_id=? ORDER BY domain', [$row['scope_id'],$row['id']]) as $offer) {
            $item = ['domain' => $offer['domain'],'authorization' => json_decode($offer['authorization'], true, 34, JSON_THROW_ON_ERROR),'keyId' => $offer['key_id'],'keyCommitment' => $offer['key_commitment']];
            if ($offer['domain'] === 'finance') {
                $item['financeClosureHash'] = $offer['closure_hash'];
            }
            $offers[] = $item;
            if ($offer['signature_proof']) {
                $signatures[] = ['domain' => $offer['domain'],'keyProposalProof' => json_decode($offer['signature_proof'], true, 34, JSON_THROW_ON_ERROR)];
            }
        }
        $domains = json_decode($row['domains'], true, 4, JSON_THROW_ON_ERROR);
        return ['scopeId' => $row['scope_id'],'draftId' => $row['id'],'managerDraftHash' => $row['draft_hash'],'requestedDomains' => $domains,'core' => json_decode($row['core'], true, 34, JSON_THROW_ON_ERROR),'authorization' => json_decode($row['authorization'], true, 34, JSON_THROW_ON_ERROR),'state' => $row['state'],'expiresAt' => (int)$row['expires_at'],'offers' => $offers,'finalCore' => count($offers) === count($domains) ? $this->filled($row) : null,'signatures' => $signatures];
    }

    public function expiresAt($body)
    {
        $expiry = null;
        foreach (['content','finance'] as $domain) {
            if (!is_array($body[$domain.'KeyProposalProof'] ?? null)) {
                continue;
            }
            $rows = $this->many('SELECT d.* FROM familyhub_crypto_key_drafts d JOIN familyhub_crypto_key_offers o ON o.scope_id=d.scope_id AND o.draft_id=d.id WHERE d.scope_id=? AND o.domain=? AND o.signature_proof=?', [$body['scopeId'],$domain,json_encode($body[$domain.'KeyProposalProof'], JSON_THROW_ON_ERROR)]);
            if ($rows) {
                foreach ($rows as $row) {
                    $candidateExpiry = $row['state'] === 'cancelled' ? 0 : (int)$row['expires_at'];
                    $expiry = $expiry === null ? $candidateExpiry : min($expiry, $candidateExpiry);
                }
            }
        }
        return $expiry;
    }

    public function read($op, $p, $actor)
    {
        $list = $op === 'crypto2.scope.keyDraft.list';
        $this->fields($p, $list ? ['scopeId'] : ['scopeId','draftId'], $list ? ['afterId','limit'] : []);
        $sid = $this->uuid($p['scopeId']);
        $this->scope($sid, $actor['user']['id']);
        if (!$list) {
            return $this->wire($this->draft($sid, $p['draftId']));
        }
        $after = isset($p['afterId']) ? $this->uuid($p['afterId']) : '';
        $limit = $p['limit'] ?? 20;
        if (!is_int($limit) || $limit < 1 || $limit > 20) {
            throw new NativeError('invalid_cursor');
        }
        $rows = $this->many("SELECT * FROM familyhub_crypto_key_drafts WHERE scope_id=? AND id>? AND state IN ('pending','ready') AND expires_at>? ORDER BY id LIMIT ".($limit + 1), [$sid,$after,time()]);
        $out = [];
        $bytes = 0;
        foreach ($rows as $row) {
            $wire = $this->wire($row);
            $size = strlen(json_encode($wire, JSON_THROW_ON_ERROR));
            if (count($out) === $limit || $out && $bytes + $size > 1250000) {
                break;
            }
            $out[] = $wire;
            $bytes += $size;
        }
        return ['drafts' => $out,'hasMore' => count($rows) > count($out),'nextAfterId' => $out ? end($out)['draftId'] : null];
    }
}
