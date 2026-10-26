<?php
namespace Kanboard\Plugin\FamilyHub\Model;

/** Metadata hints only. A cursor never authorizes a read or acknowledges a write.
 * Existing mutation transactions already commit these counters and tombstones
 * with their data. One repeatable snapshot avoids acknowledging mixed versions.
 */
class NativeAccountChanges extends NativeDatabase
{
    public const MAX_SCOPES = 2048;
    public const MAX_CURSOR = 524288;

    private static function key()
    {
        $key = defined('FAMILYHUB_ACCOUNT_MAIL_KEY_BASE64') && is_string(FAMILYHUB_ACCOUNT_MAIL_KEY_BASE64)
            ? base64_decode(FAMILYHUB_ACCOUNT_MAIL_KEY_BASE64, true) : false;
        return is_string($key) && strlen($key) === 32
            ? hash_hmac('sha256', "JivieAccountChanges/v1\n", $key, true) : null;
    }

    public static function available($pdo)
    {
        if (self::key() === null || !defined('FAMILYHUB_ENABLE_CRYPTO_PREVIEW') || FAMILYHUB_ENABLE_CRYPTO_PREVIEW !== true) { return false; }
        try {
            // Do not run the full crypto schema inventory on a 30s probe.
            $statement = $pdo->query("SELECT c.sequence,s.head_hash,sc.documents_sequence,i.configuration_revision FROM familyhub_crypto_domain_cursors c LEFT JOIN familyhub_crypto_scope_state s ON s.scope_id=c.scope_id LEFT JOIN familyhub_scopes sc ON sc.id=c.scope_id LEFT JOIN familyhub_inbox_state i ON i.account_id='' WHERE 1=0");
            $statement->closeCursor();
            return true;
        } catch (\PDOException $error) { return false; }
    }

    public function execute($operation, array $params)
    {
        if ($operation !== 'account.changes') { throw new NativeError('unsupported_operation', 404); }
        if (!self::available($this->pdo)) { throw new NativeError('account_changes_unavailable', 503); }
        $this->fields($params, ['cursor']);
        if ($params['cursor'] !== null && (!is_string($params['cursor']) || strlen($params['cursor']) > self::MAX_CURSOR)) {
            throw new NativeError('invalid_cursor');
        }
        $this->rate([['account-changes-ip:'.$this->ip, 2400, 60]]);
        return $this->transaction(function () use ($params) {
            $actor = $this->actor(false);
            return $this->read($params['cursor'], $actor);
        }, false, true);
    }

    private function digest($value) { return hash('sha256', json_encode($value, JSON_THROW_ON_ERROR)); }
    protected function now() { return time(); }

    private function previous($cursor, $binding)
    {
        if ($cursor === null) { return null; }
        $parts = explode('.', $cursor);
        if (count($parts) !== 2 || !preg_match('/^[a-f0-9]{64}$/D', $parts[1]) ||
            !hash_equals(hash_hmac('sha256', $parts[0], self::key()), $parts[1])) { throw new NativeError('invalid_cursor'); }
        $bytes = base64_decode($parts[0], true);
        if ($bytes === false || base64_encode($bytes) !== $parts[0]) { throw new NativeError('invalid_cursor'); }
        try { $value = json_decode($bytes, true, 8, JSON_THROW_ON_ERROR); }
        catch (\JsonException $e) { throw new NativeError('invalid_cursor'); }
        if (!is_array($value) || ($value['binding'] ?? null) !== $binding || !is_array($value['account'] ?? null) ||
            !is_array($value['scopes'] ?? null) || count($value['scopes']) > self::MAX_SCOPES) { throw new NativeError('invalid_cursor'); }
        return $value;
    }

    /** Fixed metadata columns only: never select records, envelopes, proofs,
     * blobs/chunks, table cells, manifests, keyrings or notification payloads. */
    public function read($cursor, $actor)
    {
        $account = $actor['user']['account_id'];
        $binding = [1, $this->serverId(), $account, $actor['device']['id']];
        $old = $this->previous($cursor, $binding);
        $args = [$account, $actor['user']['id'], $account, $actor['user']['id'], $account, $account, $account, $account];
        $rows = $this->many('SELECT s.id,s.kind,s.parent_scope_id,s.organization_id,s.project_root_id,s.sequence,s.documents_sequence,s.metadata_revision,s.access_revision,s.access_policy_version,s.archived,m.role,
            p.access_revision AS parent_revision,p.access_policy_version AS parent_policy,p.archived AS parent_archived,pm.role AS parent_role,ol.account_id AS own_leader,
            c.state AS crypto_state,c.epoch,c.sequence AS crypto_sequence,cs.head_hash,cs.content_closed,cs.finance_closed,
            dc.sequence AS content_sequence,df.sequence AS finance_sequence,f.enabled,f.revision AS finance_revision,f.sequence AS legacy_finance_sequence,g.access_level AS own_finance_grant
            FROM familyhub_scopes s
            LEFT JOIN familyhub_members m ON m.scope_id=s.id AND m.account_id=? AND m.user_id=? AND m.active=1
            LEFT JOIN familyhub_scopes p ON p.id=COALESCE(s.parent_scope_id,s.organization_id)
            LEFT JOIN familyhub_members pm ON pm.scope_id=p.id AND pm.account_id=? AND pm.user_id=? AND pm.active=1
            LEFT JOIN familyhub_organization_leaders l ON l.scope_id=p.id AND l.account_id=pm.account_id
            LEFT JOIN familyhub_moderation_blocks b ON b.scope_id=s.id AND b.account_id=?
            LEFT JOIN familyhub_moderation_blocks pb ON pb.scope_id=p.id AND pb.account_id=?
            LEFT JOIN familyhub_organization_leaders ol ON ol.scope_id=s.id AND ol.account_id=?
            LEFT JOIN familyhub_crypto_scopes c ON c.scope_id=s.id
            LEFT JOIN familyhub_crypto_scope_state cs ON cs.scope_id=s.id
            LEFT JOIN familyhub_crypto_domain_cursors dc ON dc.scope_id=s.id AND dc.domain=\'content\'
            LEFT JOIN familyhub_crypto_domain_cursors df ON df.scope_id=s.id AND df.domain=\'finance\'
            LEFT JOIN familyhub_finance_policy f ON f.scope_id=s.id
            LEFT JOIN familyhub_finance_grants g ON g.scope_id=s.id AND g.account_id=?
            WHERE s.deleted_at IS NULL AND (p.id IS NULL OR p.deleted_at IS NULL) AND b.scope_id IS NULL
              AND (m.scope_id IS NOT NULL OR (pm.scope_id IS NOT NULL AND pb.scope_id IS NULL AND
                ((p.access_policy_version=3 AND s.kind=\'project\' AND p.kind IN (\'household\',\'organization\')) OR
                 (p.access_policy_version=2 AND p.kind=\'organization\' AND s.kind=\'project\' AND (pm.role=\'owner\' OR l.account_id IS NOT NULL)))))
            ORDER BY s.id LIMIT '.(self::MAX_SCOPES + 1), $args);
        if (count($rows) > self::MAX_SCOPES) { throw new NativeError('account_changes_too_large', 413); }
        $scopes = []; $metadataIds = [];
        foreach ($rows as $row) {
            $id = $row['id'];
            $access = $row;
            foreach (['sequence','documents_sequence','crypto_sequence','content_sequence','finance_sequence','legacy_finance_sequence'] as $field) { unset($access[$field]); }
            $version = (int)($row['parent_policy'] ?? $row['access_policy_version']);
            $financeVisible = (int)$row['enabled'] === 1 &&
                (in_array($row['own_finance_grant'], ['read','write'], true) ||
                 $version === 3 && $row['kind'] !== 'personal' ||
                 $version === 2 && ($row['kind'] === 'project' && $row['organization_id'] !== null ||
                    $row['kind'] === 'organization' && ($row['role'] === 'owner' || $row['own_leader'] !== null)));
            $scopes[$id] = [
                'access' => [$this->digest($access)],
                'content' => [$row['sequence'], $row['content_sequence'], $row['crypto_sequence'] === null ? null : ($row['content_sequence'] === null ? $row['crypto_sequence'] : null)],
                'finance' => $financeVisible ? [$row['legacy_finance_sequence'], $row['finance_sequence']] : [],
                'documents' => [$row['documents_sequence']],
            ];
            $metadataIds[$id] = true;
            $parent = $row['parent_scope_id'] ?? $row['organization_id'];
            if ($parent !== null) { $metadataIds[$parent] = true; }
        }
        // Hash ordered metadata into bounded per-scope/domain stamps. No record
        // inventory scans are required, including on the unchanged path.
        $metadata = [];
        foreach (array_chunk(array_keys($metadataIds), 256) as $ids) {
            $in = implode(',', array_fill(0, count($ids), '?'));
            $specs = [
                // Journal-only attestations change generation/head, but not
                // the signed security snapshot. Preserve roots, devices and
                // keyring changes without turning observations into access.
                'members' => 'SELECT m.scope_id,m.account_id,m.role,m.active,d.snapshot_hash,d.device_snapshot_hash,d.identity_epoch_id,u.is_active,u.username,u.name FROM familyhub_members m LEFT JOIN familyhub_crypto_directory_state d ON d.account_id=m.account_id LEFT JOIN users u ON u.id=m.user_id WHERE m.scope_id IN ('.$in.') ORDER BY m.scope_id,m.account_id',
                'grants' => 'SELECT scope_id,account_id,access_level FROM familyhub_finance_grants WHERE scope_id IN ('.$in.') ORDER BY scope_id,account_id',
                'lifecycle' => 'SELECT scope_id,MAX(revision) AS revision FROM familyhub_crypto_lifecycle_log_v2 WHERE scope_id IN ('.$in.') GROUP BY scope_id ORDER BY scope_id',
            ];
            foreach ($specs as $kind => $sql) {
                foreach ($this->iterate($sql, $ids) as $item) {
                    $sid = $item['scope_id'];
                    if (!isset($metadata[$sid][$kind])) { $metadata[$sid][$kind] = hash_init('sha256'); }
                    hash_update($metadata[$sid][$kind], json_encode($item, JSON_THROW_ON_ERROR)."\n");
                }
            }
        }
        foreach ($metadata as $sid => $kinds) {
            foreach ($kinds as $kind => $hash) { $metadata[$sid][$kind] = hash_final($hash); }
        }
        foreach ($rows as $row) {
            $sid = $row['id']; $parent = $row['parent_scope_id'] ?? $row['organization_id'];
            $scopes[$sid]['access'][] = [$metadata[$sid]['members'] ?? null, $metadata[$sid]['grants'] ?? null, $metadata[$sid]['lifecycle'] ?? null,
                $parent === null ? null : [$metadata[$parent]['members'] ?? null, $metadata[$parent]['grants'] ?? null, $metadata[$parent]['lifecycle'] ?? null]];
            foreach ($scopes[$sid] as $domain => $stamp) { $scopes[$sid][$domain] = $this->digest($stamp); }
        }
        $directory = $this->one('SELECT generation,head_hash,snapshot_hash,device_snapshot_hash,identity_epoch_id FROM familyhub_crypto_directory_state WHERE account_id=?', [$account]);
        $directoryLog = $directory === null ? null : array_intersect_key($directory, array_flip(['generation','head_hash','device_snapshot_hash']));
        $directoryAccess = $directory === null ? null : array_intersect_key($directory, array_flip(['snapshot_hash','device_snapshot_hash','identity_epoch_id']));
        $inboxState = $this->one('SELECT sequence,visibility_revision,configuration_revision FROM familyhub_inbox_state WHERE account_id=?', [$account]);
        $notificationConfiguration = $this->digest((int)($inboxState['configuration_revision'] ?? 0));
        $configurationChanged = ($old['notificationConfiguration'] ?? null) !== $notificationConfiguration;
        $accountState = [
            // Every signed event still wakes ordinary directory verification.
            'directory' => $this->digest($directoryLog),
            'inbox' => $this->digest($inboxState),
            'access' => $this->digest([array_keys($scopes), $directoryAccess]),
            'metadata' => $this->digest([$actor['user']['username'], $actor['user']['name'], $this->one('SELECT revision,verified_at FROM familyhub_email_identities WHERE account_id=?', [$account])]),
        ];
        $hash = hash_init('sha256');
        // Accepted invitations must wake the original inviter even before a
        // new membership head or content record exists. Expiry is a hint too.
        $activeInvitations = [];
        $now = $this->now();
        foreach (['creator_account_id'=>$account, 'recipient_account_id'=>$account] as $column => $value) {
            foreach ($this->many("SELECT id,scope_id,state,recipient_account_id,replaced_by,expires_at FROM familyhub_crypto_invitations_v2 WHERE ".$column."=? AND state IN ('pending','accepted') AND expires_at>? ORDER BY id LIMIT 1025", [$value,$now]) as $invitation) {
                $activeInvitations['crypto:'.$invitation['id']]=$invitation;
            }
        }
        foreach (['creator_account_id'=>$account, 'recipient_account_id'=>$account, 'recipient_username'=>$actor['user']['username']] as $column => $value) {
            foreach ($this->many('SELECT id,recipient_account_id,expires_at FROM familyhub_invitations WHERE '.$column.'=? AND accepted_at IS NULL AND revoked_at IS NULL AND expires_at>? ORDER BY id LIMIT 1025', [$value,$now]) as $invitation) {
                $activeInvitations['legacy:'.$invitation['id']]=$invitation;
            }
        }
        if (count($activeInvitations)>1024) { throw new NativeError('account_changes_too_large', 413); }
        ksort($activeInvitations, SORT_STRING);
        foreach ($activeInvitations as $key => $invitation) { hash_update($hash, $key."\n".json_encode($invitation, JSON_THROW_ON_ERROR)."\n"); }
        $accountState['invitations'] = hash_final($hash);
        $changedScopes = []; $accountDomains = [];
        foreach ($accountState as $domain => $stamp) { if (($old['account'][$domain] ?? null) !== $stamp) { $accountDomains[] = $domain; } }
        // Keep the v1 inbox domain unchanged for old clients. A cursor written
        // before this additive hint needs one conservative configuration read.
        if ($configurationChanged && !in_array('inbox', $accountDomains, true)) { $accountDomains[] = 'inbox'; }
        foreach ($scopes as $sid => $domains) {
            $changed = [];
            foreach ($domains as $domain => $stamp) { if (($old['scopes'][$sid][$domain] ?? null) !== $stamp) { $changed[] = $domain; } }
            if ($changed) { $changedScopes[] = ['scopeId' => $sid, 'domains' => $changed]; }
        }
        $bytes = base64_encode(json_encode(['binding'=>$binding,'account'=>$accountState,'scopes'=>$scopes,'notificationConfiguration'=>$notificationConfiguration], JSON_THROW_ON_ERROR));
        $next = $bytes.'.'.hash_hmac('sha256', $bytes, self::key());
        if (strlen($next) > self::MAX_CURSOR) { throw new NativeError('account_changes_too_large', 413); }
        return ['version'=>1,'directoryHintsVersion'=>1,'notificationHintsVersion'=>1,'notificationConfigurationChanged'=>$configurationChanged,'serverId'=>$binding[1],'accountId'=>$account,'deviceId'=>$binding[3],
            'cursor'=>$next,'changed'=>(bool)($accountDomains || $changedScopes),'accountDomains'=>$accountDomains,
            'scopes'=>$changedScopes,'hasMore'=>false,'resetRequired'=>$old === null];
    }
}
