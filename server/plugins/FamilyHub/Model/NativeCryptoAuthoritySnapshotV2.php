<?php

namespace Kanboard\Plugin\FamilyHub\Model;

/** Bounded transport composition only. Every entry retains its original ACL and
 * signed proof; the envelope itself is never an authority certificate. */
class NativeCryptoAuthoritySnapshotV2 extends NativeDatabase
{
    protected $cryptoAccess = true;
    private const MAX_BYTES = 1250000;
    private const MAX_ENTRIES = 512;
    private const MAX_READS = 256;
    private $entries = [];
    private $seen = [];
    private $bytes = 0;
    private $reads = 0;
    private $directoryAfter = [];
    private $lifecycleAfter = [];
    private $directoryPages = [];
    private $omitted = false;

    private function entry($operation, $params, callable $reader)
    {
        $key = $operation."\n".NativeCryptoCodec::canonical((object)$params);
        if (array_key_exists($key, $this->seen)) { return $this->seen[$key]; }
        if (++$this->reads > self::MAX_READS) { throw new NativeError('crypto_authority_snapshot_capacity', 413); }
        try {
            $result = $reader();
            $entry = ['operation'=>$operation, 'params'=>(object)$params, 'result'=>$result];
        } catch (NativeError $error) {
            // Some legacy optional enrichment previews simulate writes in a
            // savepoint. They cannot run in this read-only snapshot. Omit the
            // scope and leave its exact original route to the caller instead
            // of replacing a successful route with an internal read-only error.
            if ($error->errorCode === 'crypto_authority_snapshot_read_only') {
                throw new NativeError('crypto_authority_snapshot_capacity', 413);
            }
            // Only the original route's finite public failure is returned. In
            // particular no SQL row, hidden parent, or stack escapes on denial.
            $entry = ['operation'=>$operation, 'params'=>(object)$params,
                'error'=>['code'=>$error->errorCode,'status'=>$error->status,'details'=>(object)$error->details]];
            $result = null;
        }
        $size = strlen(json_encode($entry, JSON_THROW_ON_ERROR));
        if (count($this->entries) >= self::MAX_ENTRIES || $this->bytes + $size > self::MAX_BYTES - 2048) {
            throw new NativeError('crypto_authority_snapshot_capacity', 413);
        }
        $this->bytes += $size;
        $this->entries[] = $entry;
        $this->seen[$key] = $result;
        return $result;
    }

    private function scopeReader() { return new NativeCryptoScopeV2($this->container, $this->bearer, $this->ip); }

    private function optionalEntry($operation, $params, callable $reader)
    {
        try { return $this->entry($operation, $params, $reader); }
        catch (NativeError $error) {
            if ($error->errorCode !== 'crypto_authority_snapshot_capacity') { throw $error; }
            $this->omitted = true;
            return null;
        }
    }

    private function cursors($value, $maximum)
    {
        if (!is_array($value) || count($value)>$maximum || $value && array_is_list($value)) { throw new NativeError('validation_error'); }
        foreach ($value as $id=>$generation) {
            $this->uuid($id);
            if (!is_int($generation) || $generation<0) { throw new NativeError('validation_error'); }
        }
        return $value;
    }

    /** Collect only explicitly retained public signer/member references. The
     * original directory route still authorizes each selector independently. */
    private function references($value, &$references, $depth = 0)
    {
        if (!is_array($value) || $depth > 20 || count($references) >= 64) { return; }
        if (isset($value['commandBase64'], $value['signatureBase64'])) {
            [$command] = NativeCryptoCodec::decode($value);
            $this->references($command, $references, $depth + 1);
        }
        $account = $value['accountId'] ?? null;
        if (is_string($account)) {
            foreach (['directoryHeadHash','authorDirectoryHeadHash'] as $field) {
                $hash = $value[$field] ?? $value['payload'][$field] ?? null;
                if (is_string($hash)) { $references[$account.':'.$hash] = [$account,$hash]; }
            }
        }
        foreach ($value as $child) { if (is_array($child)) { $this->references($child, $references, $depth + 1); } }
    }

    private function scopeEntries($sid, $actor)
    {
        $p = ['scopeId'=>$sid];
        $head = $this->entry('crypto2.scope.headGet', $p, fn()=> $this->scopeReader()->read('crypto2.scope.headGet', $p, $actor));
        if ($head === null) { return; }
        $references = [];
        $this->references($head, $references);
        foreach (['baseline','current','list'] as $kind) {
            $params = $p + ($kind === 'list' ? ['afterRevision'=>$this->lifecycleAfter[$sid] ?? 0,'limit'=>20] : []);
            $operation = 'crypto2.scope.lifecycle.'.$kind;
            $wire = $this->entry($operation, $params, fn()=> (new NativeCryptoLifecycleV2($this->container, $this->bearer, $this->ip))->read($operation, $params, $actor));
            $this->references($wire, $references);
        }
        $params = $p + ['limit'=>50];
        $policy = $this->entry('crypto2.scope.financePolicy.current', $params, fn()=> (new NativeCryptoFinancePolicyV2($this->container, $this->bearer, $this->ip))->read($params, $actor));
        $this->references($policy, $references);
        // Head and baseline author references live alongside their proof.
        foreach (['authorization'=>'authorDirectoryHeadHash','originAuthorization'=>'originAuthorDirectoryHeadHash'] as $proofField=>$hashField) {
            if (isset($head[$proofField], $head[$hashField])) {
                [$author] = NativeCryptoCodec::decode($head[$proofField]);
                $references[$author['accountId'].':'.$head[$hashField]] = [$author['accountId'],$head[$hashField]];
            }
        }
        if (isset($head['authorization'], $head['payload']['authorDirectoryHeadHash'])) {
            [$author] = NativeCryptoCodec::decode($head['authorization']);
            $hash = $head['payload']['authorDirectoryHeadHash'];
            $references[$author['accountId'].':'.$hash] = [$author['accountId'],$hash];
        }
        $accounts = [];
        foreach ($head['payload']['members'] as $member) { $accounts[$member['accountId']] = true; }
        foreach ($references as [$account,$hash]) { $accounts[$account] = true; }
        ksort($accounts); ksort($references);
        // Bound selection work before beginning directory reads. Unincluded
        // selectors remain ordinary authenticated reads on the client.
        if (count($accounts) > 32 || count($references) > 64) { return; }
        foreach ($accounts as $account=>$unused) {
            $query = $p + ['headHash'=>$head['headHash'],'accountId'=>$account];
            $status = $this->entry('crypto2.directory.status', $query, fn()=> $this->scopeReader()->directoryRead('crypto2.directory.status', $query, $actor));
            // Contact discovery deliberately has no selected membership head.
            $contact = $p + ['accountId'=>$account];
            $this->entry('crypto2.directory.status', $contact, fn()=> $this->scopeReader()->directoryRead('crypto2.directory.status', $contact, $actor));
            if ($status !== null) { $references[$account.':'.$status['headHash']] = [$account,$status['headHash']]; }
        }
        foreach ($references as [$account,$hash]) {
            $query = $p + ['headHash'=>$head['headHash'],'accountId'=>$account,'directoryHeadHash'=>$hash];
            $selected = $this->entry('crypto2.directory.status', $query, fn()=> $this->scopeReader()->directoryRead('crypto2.directory.status', $query, $actor));
            $after = min($this->directoryAfter[$account] ?? 0, $selected['generation'] ?? 0);
            $query += ['afterGeneration'=>$after,'limit'=>50];
            $this->entry('crypto2.directory.read', $query, function () use ($query,$actor,$selected,$account,$hash,$after) {
                // Authorize the exact prefix in EACH scope before sharing only
                // the account's identical public log page between scopes.
                $key = $account.':'.$hash.':'.$after;
                if ($selected !== null && isset($this->directoryPages[$key])) { return $this->directoryPages[$key]; }
                $wire = $this->scopeReader()->directoryRead('crypto2.directory.read', $query, $actor);
                $this->directoryPages[$key] = $wire;
                return $wire;
            });
        }
    }

    public function read($p, $actor, $status, callable $accountDirectory)
    {
        $this->fields($p, [], ['scopeId','includeChildren','afterScopeId','scopeLimit','pendingCapability','accountAfterGeneration','directoryAfterGenerations','lifecycleAfterRevisions']);
        $include = $p['includeChildren'] ?? true;
        $limit = $p['scopeLimit'] ?? 20;
        $after = isset($p['afterScopeId']) ? $this->uuid($p['afterScopeId']) : '';
        if (!is_bool($include) || !is_int($limit) || $limit < 1 || $limit > 20) { throw new NativeError('validation_error'); }
        $this->directoryAfter = $this->cursors($p['directoryAfterGenerations'] ?? [], 32);
        $this->lifecycleAfter = $this->cursors($p['lifecycleAfterRevisions'] ?? [], 20);
        if (isset($p['accountAfterGeneration']) && (!is_int($p['accountAfterGeneration']) || $p['accountAfterGeneration']<0)) { throw new NativeError('validation_error'); }
        $envelope = ['version'=>1,'serverId'=>$this->serverId(),'accountId'=>$actor['user']['account_id'],'deviceId'=>$actor['device']['id']];
        // Pending-candidate proof access is intentionally left to the exact
        // private route. It must never expand into current whole-space access.
        if (array_key_exists('pendingCapability',$p)) {
            if (!is_string($p['pendingCapability']) || strlen($p['pendingCapability']) > 4096) { throw new NativeError('validation_error'); }
            return $envelope + ['entries'=>[],'hasMoreScopes'=>false,'nextAfterScopeId'=>null,'complete'=>false];
        }
        $ids = [];
        $more = false;
        if (isset($p['scopeId'])) {
            $sid = $this->uuid($p['scopeId']);
            // Unknown/deleted/revoked selectors disclose the same original
            // route error, without a catalog or sibling response alongside it.
            $selected = $this->scope($sid, $actor['user']['id']);
            $root = $sid;
            $parent = $selected['parent_scope_id'] ?? $selected['organization_id'] ?? null;
            $access = new NativeOrganizationAccess($this->container);
            if ($include && $parent && $access->visibleScope($parent, $actor['user']['account_id'])) { $root = $parent; }
            // Same direct/inherited visibility admission as scopes.catalog,
            // restricted to this root. Bound SQL rows before assembling proofs.
            $account = $actor['user']['account_id']; $user = $actor['user']['id'];
            $visible = "(EXISTS (SELECT 1 FROM familyhub_members m WHERE m.scope_id=s.id AND m.account_id=? AND m.user_id=? AND m.active=1) OR EXISTS (SELECT 1 FROM familyhub_members m JOIN familyhub_scopes parent ON parent.id=m.scope_id LEFT JOIN familyhub_organization_leaders leader ON leader.scope_id=parent.id AND leader.account_id=m.account_id WHERE (parent.id=s.parent_scope_id OR parent.id=s.organization_id) AND m.account_id=? AND m.user_id=? AND m.active=1 AND (parent.access_policy_version=3 OR (parent.access_policy_version=2 AND (m.role='owner' OR leader.account_id IS NOT NULL)))))";
            $rows = $include ? $this->many('SELECT s.id FROM familyhub_scopes s WHERE s.deleted_at IS NULL AND (s.id=? OR s.parent_scope_id=? OR s.organization_id=?) AND s.id>? AND '.$visible.' ORDER BY s.id LIMIT '.($limit+1), [$root,$root,$root,$after,$account,$user,$account,$user]) : [['id'=>$sid]];
            foreach ($rows as $row) {
                if (!$access->visibleScope($row['id'], $actor['user']['account_id'])) { continue; }
                $ids[] = $row['id'];
                if (count($ids) > $limit) { $more = true; array_pop($ids); break; }
            }
        } else {
            $catalogParams = ['limit'=>50];
            if ($after !== '') { $catalogParams['afterId'] = $after; }
            $catalog = $this->optionalEntry('crypto2.scopes.catalog', $catalogParams, fn()=> $this->scopeReader()->catalog($catalogParams, $actor));
            $ids = $catalog === null ? [] : array_column(array_slice($catalog['scopes'], 0, $limit), 'id');
            $more = $catalog === null || $catalog['hasMore'] || count($catalog['scopes']) > count($ids);
        }
        $this->optionalEntry('crypto2.account.status', [], fn()=> $status);
        if (isset($p['accountAfterGeneration'])) {
            $accountParams = ['afterGeneration'=>$p['accountAfterGeneration'],'limit'=>50];
            $this->optionalEntry('crypto2.account.directory', $accountParams, fn()=> $accountDirectory($accountParams));
        }
        $last = $after !== '' ? $after : null;
        foreach ($ids as $sid) {
            $oldEntries = $this->entries; $oldSeen = $this->seen; $oldBytes = $this->bytes;
            try { $this->scopeEntries($sid, $actor); }
            catch (NativeError $error) {
                if ($error->errorCode !== 'crypto_authority_snapshot_capacity') { throw $error; }
                $this->entries = $oldEntries; $this->seen = $oldSeen; $this->bytes = $oldBytes;
                $more = true;
                break;
            }
            $last = $sid;
        }
        return $envelope + ['entries'=>$this->entries,'hasMoreScopes'=>$more,'nextAfterScopeId'=>$more ? $last : null,'complete'=>!$more && !$this->omitted];
    }
}
