<?php

namespace Kanboard\Plugin\FamilyHub\Model;

/** Complete native invitation preservation. Stage never sends mail or grants keys. */
class NativeCryptoMigrationInvitationStageV3 extends NativeDatabase
{
    protected $cryptoAccess = true;
    private $verifiedPrefixes=[];
    public const TABLES = ['familyhub_invitations','familyhub_invitation_mail'];
    private function transactionRequired()
    {
        if (!$this->transactionActive()) {
            throw new NativeError('crypto_migration_transaction_required', 409);
        }
    }

    private function digest($value)
    {
        if (!is_string($value) || !preg_match('/^[a-f0-9]{64}$/D', $value)) {
            throw new NativeError('crypto_invitation_migration_context');
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
            throw new NativeError('crypto_invitation_migration_source');
        }
        $out = [];
        foreach (get_object_vars($typed) as $name => $cell) {
            if (!is_array($cell) || !array_key_exists('valueBase64', $cell)) {
                throw new NativeError('crypto_invitation_migration_source');
            }
            if ($cell['valueBase64'] === null) {
                $out[$name] = null;
            } else {
                $bytes = base64_decode($cell['valueBase64'], true);
                if ($bytes === false || base64_encode($bytes) !== $cell['valueBase64']) {
                    throw new NativeError('crypto_invitation_migration_source');
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
            throw new NativeError('crypto_invitation_migration_signer_changed', 409);
        }
        $snapshot = $anchoredHistory
            ? $this->prefixState($account,(int)$prefix['generation'])['snapshotValue']
            : json_decode($current['snapshot'], true, 34, JSON_THROW_ON_ERROR);
        $device = $directory->device($snapshot, $deviceId);
        if (!$device || $device['revokedGeneration'] !== null ||
            $device['identityEpochId'] !== $snapshot['identityEpochId']) {
            throw new NativeError('crypto_invitation_migration_signer_revoked', 403);
        }
        return $device['signingKeyBase64'];
    }

    /** Immutable log entries deliberately contain no snapshot cache. Rebuild
     * only the exact accepted prefix; never trust a historical blank/cache row.
     */
    private function prefixState($account, $generation)
    {
        $cache=$account.':'.$generation;
        if(isset($this->verifiedPrefixes[$cache]))return$this->verifiedPrefixes[$cache];
        $directory = new NativeCryptoDirectoryV2($this->container);
        $before = null;
        $after = 0;
        while ($after < $generation) {
            $rows = $this->many('SELECT * FROM familyhub_crypto_directory WHERE account_id=? AND generation>? AND generation<=? ORDER BY generation LIMIT 20',[$account,$after,$generation]);
            if (!$rows) {
                throw new NativeError('crypto_invitation_migration_event_missing',409);
            }
            foreach ($rows as $row) {
                $proof = json_decode($row['authorization'],true,34,JSON_THROW_ON_ERROR);
                [$command,$bytes,$signature] = NativeCryptoCodec::decode($proof);
                if ((int)$row['generation'] !== $after + 1 || $command['accountId'] !== $account ||
                    $command['serverId'] !== $this->serverId() ||
                    $command['payload']['previousHeadHash'] !== ($before['head_hash'] ?? NativeCryptoDirectoryV2::ZERO)) {
                    throw new NativeError('crypto_invitation_migration_event_invalid',409);
                }
                NativeCryptoV2Codec::verify($bytes,$signature,$directory->authorize($command,$before));
                $snapshot = $directory->reduce($command,$before);
                if (NativeCryptoV2Codec::head($command,$proof,$after+1) !== $row['head_hash'] ||
                    NativeCryptoDirectoryV2::snapshotHash($snapshot) !== $row['snapshot_hash'] ||
                    NativeCryptoDirectoryV2::deviceHash($snapshot) !== $row['device_snapshot_hash']) {
                    throw new NativeError('crypto_invitation_migration_event_invalid',409);
                }
                $before = array_replace($row,['snapshot'=>NativeCryptoCodec::canonical((object)$snapshot),
                    'snapshotValue'=>$snapshot]);
                $after++;
            }
        }
        return $this->verifiedPrefixes[$cache]=$before;
    }

    private function capsule($encoded, array $context, ?array $source, $expectedTokenHash=null)
    {
        if (!is_string($encoded) || strlen($encoded)>32768 ||
            ($bytes=base64_decode($encoded,true))===false || base64_encode($bytes)!==$encoded) {
            throw new NativeError('crypto_invitation_bridge_capsule');
        }
        $envelope=json_decode($bytes,true,34,JSON_THROW_ON_ERROR);
        $this->fields($envelope,['version','suite','context','nonceBase64','ciphertextBase64']);
        if ($envelope['version']!==1 || $envelope['suite']!=='sodium-box-seal-xchacha20poly1305-ed25519-v1' ||
            !$this->same((object)$envelope['context'],(object)$context)) {
            throw new NativeError('crypto_invitation_bridge_capsule');
        }
        $nonce=base64_decode($envelope['nonceBase64'],true);
        $cipher=base64_decode($envelope['ciphertextBase64'],true);
        if ($nonce===false || strlen($nonce)!==24 || base64_encode($nonce)!==$envelope['nonceBase64'] ||
            $cipher===false || strlen($cipher)<16 || base64_encode($cipher)!==$envelope['ciphertextBase64']) {
            throw new NativeError('crypto_invitation_bridge_capsule');
        }
        $tokenHash=$this->digest($source['token_hash']??$expectedTokenHash);
        $key=sodium_crypto_generichash("JivieLegacyInvitationCapsuleKey/v3\n".
            NativeCryptoCodec::canonical((object)['version'=>3,'serverId'=>$this->serverId(),'bridgeId'=>$context['bridgeId']])."\n".hex2bin($tokenHash),'',32);
        $plain=sodium_crypto_aead_xchacha20poly1305_ietf_decrypt($cipher,
            NativeCryptoCodec::canonical((object)$context),$nonce,$key);
        sodium_memzero($key);
        if ($plain===false) { throw new NativeError('crypto_invitation_bridge_capsule'); }
        try { $metadata=json_decode($plain,true,34,JSON_THROW_ON_ERROR); }
        finally { sodium_memzero($plain); }
        if ($source===null) {
            $this->fields($metadata,['version','invitationId','scopeId','recipient','role','expiresAtEpoch','acceptedAtEpoch','revokedAtEpoch','legacyContractVersion','tokenHash']);
            if ($metadata['tokenHash']!==$tokenHash || $metadata['scopeId']!==$context['scopeId']) { throw new NativeError('crypto_invitation_bridge_capsule'); }
            return $metadata;
        }
        $recipient=$source['recipient_email']!==null
            ? ['kind'=>'email','value'=>$source['recipient_email'],'accountId'=>$source['recipient_account_id']]
            : ['kind'=>'username','value'=>$source['recipient_username'],'accountId'=>$source['recipient_account_id']];
        $expected=['version'=>3,'invitationId'=>$source['id'],'scopeId'=>$source['scope_id'],
            'recipient'=>$recipient,'role'=>$source['role'],'expiresAtEpoch'=>(int)$source['expires_at'],
            'acceptedAtEpoch'=>$source['accepted_at']===null?null:(int)$source['accepted_at'],
            'revokedAtEpoch'=>$source['revoked_at']===null?null:(int)$source['revoked_at'],
            'legacyContractVersion'=>(int)$source['invitation_contract'],'tokenHash'=>$tokenHash];
        if (!$this->same((object)$metadata,(object)$expected)) {
            throw new NativeError('crypto_invitation_bridge_source_changed',409);
        }
        return $metadata;
    }

    private function bridge($proof,$encoded,$common,$source,$actor,$history=false)
    {
        [$command,$bytes,$signature]=NativeCryptoCodec::decode($proof);
        $this->fields($command,['version','operation','requestId','serverId','accountId','deviceId','signer','payload']);
        $b=$command['payload'];
        $this->fields($b,['context','sourceKind','invitationBindingId','authorDirectoryHeadHash','capsuleHash','capsuleSize']);
        $c=$b['context'];
        $this->fields($c,['version','purpose','serverId','migrationId','captureId','sourceInventoryRoot',
            'bridgeId','bindingId','sourceCommitment','scopeId','membershipHeadHash']);
        if ($command['version']!==2 || $command['operation']!=='crypto2.invitations.bridgeLegacy' ||
            $command['signer']!=='device' || $command['serverId']!==$common['serverId'] ||
            $command['accountId']!==$common['accountId'] || $c['version']!==3 ||
            $c['purpose']!=='legacyInvitationBridge' || strlen($bytes)>16384) {
            throw new NativeError('crypto_invitation_bridge_context');
        }
        foreach (['serverId','migrationId','captureId','sourceInventoryRoot'] as $k) {
            if ($c[$k]!==$common[$k]) { throw new NativeError('crypto_invitation_bridge_context'); }
        }
        foreach (['requestId','deviceId'] as $k) { $this->uuid($command[$k]); }
        foreach (['bridgeId','bindingId','scopeId'] as $k) { $this->uuid($c[$k]); }
        foreach (['sourceCommitment','membershipHeadHash'] as $k) { $this->digest($c[$k]); }
        $this->uuid($b['invitationBindingId']); $this->digest($b['authorDirectoryHeadHash']);
        $binding=NativeCryptoCaptureV3::binding($source['binding']);
        if ($binding['bindingId']!==$c['bindingId'] || $binding['sourceCommitment']!==$c['sourceCommitment'] ||
            $source['context']['domain']!=='private' || $source['context']['scopeId']!==null) {
            throw new NativeError('crypto_invitation_bridge_binding',409);
        }
        foreach (['serverId','accountId','migrationId','captureId'] as $k) {
            if (($source['context'][$k]??null)!==$common[$k]) { throw new NativeError('crypto_invitation_bridge_binding',409); }
        }
        $raw=$this->cells($source['typedRow']);
        $kind=match($source['context']['sourceTable']) {
            'familyhub_invitations'=>'invitation','familyhub_invitation_mail'=>'mail',
            default=>throw new NativeError('crypto_invitation_bridge_kind'),
        };
        if ($b['sourceKind']!==$kind) { throw new NativeError('crypto_invitation_bridge_kind'); }
        $scopes=new NativeCryptoScopeV2($this->container);
        $head=$scopes->current($c['scopeId']);
        if (!$history) {
            $scope=$this->scope($c['scopeId'],$actor['user']['id']);
            if (!$head || $head['head_hash']!==$c['membershipHeadHash']) {
                throw new NativeError('crypto_scope_head_conflict',409);
            }
            $scopes->manager($head,$scope,$actor);
        }
        NativeCryptoV2Codec::verify($bytes,$signature,
            $this->signer($common['accountId'],$b['authorDirectoryHeadHash'],$command['deviceId'],$actor,$history));
        if ($kind==='invitation') {
            if ($c['scopeId']!==$raw['scope_id'] || $c['bindingId']!==$b['invitationBindingId'] ||
                !is_string($encoded) || $b['capsuleHash']!==hash('sha256',base64_decode($encoded,true)?:'') ||
                $b['capsuleSize']!==strlen(base64_decode($encoded,true)?:'')) {
                throw new NativeError('crypto_invitation_bridge_capsule');
            }
            $metadata=$this->capsule($encoded,$c,$raw);
        } else {
            if ($encoded!==null || $b['capsuleHash']!==null || $b['capsuleSize']!==0) {
                throw new NativeError('crypto_invitation_bridge_mail');
            }
            $inv=$this->one('SELECT authorization FROM familyhub_crypto_invitation_bridges_v3 WHERE migration_id=? AND account_id=? AND binding_id=? AND kind=?',
                [$common['migrationId'],$common['accountId'],$b['invitationBindingId'],'invitation']);
            if (!$inv) { throw new NativeError('crypto_invitation_bridge_invitation_pending',409); }
            [$invCommand]=NativeCryptoCodec::decode(json_decode($inv['authorization'],true,34,JSON_THROW_ON_ERROR));
            $invContext=$invCommand['payload']['context'];
            foreach (['bridgeId','scopeId','membershipHeadHash'] as $k) {
                if ($invContext[$k]!==$c[$k]) { throw new NativeError('crypto_invitation_bridge_mail'); }
            }
            $route=$this->one('SELECT invitation_id FROM familyhub_crypto_invitation_routes_v3 WHERE migration_id=? AND account_id=? AND binding_id=?',
                [$common['migrationId'],$common['accountId'],$b['invitationBindingId']]);
            if (!$route || $route['invitation_id']!==$raw['invitation_id']) {
                throw new NativeError('crypto_invitation_bridge_mail');
            }
            $metadata=null;
        }
        $hash=NativeCryptoV2Codec::hash((object)$proof);
        $leaf=['bindingId'=>$c['bindingId'],'kind'=>$kind,'bridgeHash'=>$hash,'capsuleHash'=>$b['capsuleHash']];
        return ['body'=>$b,'source'=>$raw,'metadata'=>$metadata,'bridgeHash'=>$hash,'leaf'=>$leaf,
            'leafHash'=>NativeCryptoMigrationInvitationV3::leafDigest($leaf)];
    }

    public function stage($p,$actor,$proof,$command,callable $captureSourceBinding)
    {
        $this->transactionRequired();
        $this->fields($p,['migrationId','captureId','sourceInventoryRoot','bridges']);
        $common=$this->context($p,$actor);
        if ($command['operation']!=='crypto2.migration.invitations.stage' ||
            $command['accountId']!==$common['accountId'] || !$this->same((object)$command['payload'],(object)$p) ||
            !is_array($p['bridges']) || !array_is_list($p['bridges']) || !$p['bridges'] || count($p['bridges'])>20 ||
            strlen(NativeCryptoCodec::canonical((object)$p))>524288) {
            throw new NativeError('crypto_invitation_bridge_stage');
        }
        if ($this->certificate($common['migrationId'],$common['accountId'])) {
            throw new NativeError('crypto_invitation_bridge_certified',409);
        }
        $leaves=[]; $seen=[];
        foreach ($p['bridges'] as $item) {
            $this->fields($item,['authorization','capsuleBase64']);
            [$b]=NativeCryptoCodec::decode($item['authorization']);
            $binding=$this->uuid($b['payload']['context']['bindingId']??null);
            if(isset($seen[$binding])) throw new NativeError('crypto_invitation_bridge_duplicate');
            $seen[$binding]=true;
            $source=$captureSourceBinding($common['migrationId'],$common['captureId'],$binding,$actor);
            $v=$this->bridge($item['authorization'],$item['capsuleBase64'],$common,$source,$actor);
            $old=$this->one('SELECT bridge_hash,capsule FROM familyhub_crypto_invitation_bridges_v3 WHERE migration_id=? AND account_id=? AND binding_id=?',
                [$common['migrationId'],$common['accountId'],$binding]);
            if ($old) {
                if ($old['bridge_hash']!==$v['bridgeHash'] || $old['capsule']!==$item['capsuleBase64']) {
                    throw new NativeError('crypto_invitation_bridge_immutable',409);
                }
            } else {
                $this->change('INSERT INTO familyhub_crypto_invitation_bridges_v3 VALUES(?,?,?,?,?,?,?,?,?,?,?)',
                    [$common['migrationId'],$common['accountId'],$binding,$v['bridgeHash'],$v['leaf']['kind'],$v['leafHash'],
                    $v['leaf']['capsuleHash'],json_encode($item['authorization'],JSON_THROW_ON_ERROR),
                    json_encode($proof,JSON_THROW_ON_ERROR),$item['capsuleBase64'],time()]);
                if ($v['metadata']!==null) {
                    $m=$v['metadata']; $c=$v['body']['context'];
                    $this->change('INSERT INTO familyhub_crypto_invitation_routes_v3 VALUES(?,?,?,?,?,?,?,?)',
                        [$m['tokenHash'],$m['invitationId'],$common['migrationId'],$common['accountId'],$binding,
                        $m['scopeId'],$c['bridgeId'],time()]);
                }
            }
            $leaves[]=$v['leaf'];
        }
        return ['migrationId'=>$common['migrationId'],'captureId'=>$common['captureId'],
            'sourceInventoryRoot'=>$common['sourceInventoryRoot'],'leaves'=>$leaves,'state'=>'staged'];
    }

    private function leafRows($migrationId,$account)
    {
        $after='';
        do {
            $rows=$this->many('SELECT * FROM familyhub_crypto_invitation_bridges_v3 WHERE migration_id=? AND account_id=? AND leaf_hash>? ORDER BY leaf_hash LIMIT 20',[$migrationId,$account,$after]);
            foreach ($rows as $row) { $after=$row['leaf_hash']; yield $row; }
        } while (count($rows)===20);
    }

    public function bridges($p,$actor,callable $captureSourceBindings)
    {
        $this->fields($p,['migrationId','captureId','sourceInventoryRoot'],['afterBindingId','limit']);
        $common=$this->context($p,$actor);
        foreach ($captureSourceBindings($common['migrationId'],$common['captureId'],$common['sourceInventoryRoot'],$actor,self::TABLES) as $ignored) { break; }
        $after=isset($p['afterBindingId'])?$this->uuid($p['afterBindingId']):'';
        $limit=$p['limit']??20;
        if (!is_int($limit) || $limit<1 || $limit>20) { throw new NativeError('validation_error'); }
        $rows=$this->many('SELECT binding_id,authorization,capsule FROM familyhub_crypto_invitation_bridges_v3 WHERE migration_id=? AND account_id=? AND binding_id>? ORDER BY binding_id LIMIT '.($limit+1),[$common['migrationId'],$common['accountId'],$after]);
        $more=count($rows)>$limit; $rows=array_slice($rows,0,$limit);
        return ['bridges'=>array_map(fn($r)=>['bindingId'=>$r['binding_id'],'authorization'=>json_decode($r['authorization'],true,34,JSON_THROW_ON_ERROR),'capsuleBase64'=>$r['capsule']],$rows),
            'hasMore'=>$more,'nextAfterBindingId'=>$rows?end($rows)['binding_id']:($after?:null)];
    }

    /** Per-binding refold only AFTER complete stagedCoverage. This hash is not
     * itself coverage, a certificate, or permission to activate any invitation. */
    public function bindingArtifact($migrationId,$captureId,$sourceInventoryRoot,$bindingId,$actor)
    {
        $common=$this->context(compact('migrationId','captureId','sourceInventoryRoot'),$actor);
        $row=$this->one('SELECT * FROM familyhub_crypto_invitation_bridges_v3 WHERE migration_id=? AND account_id=? AND binding_id=?',[$migrationId,$common['accountId'],$this->uuid($bindingId)]);
        if(!$row)throw new NativeError('crypto_invitation_bridge_incomplete',409);
        $proof=json_decode($row['authorization'],true,34,JSON_THROW_ON_ERROR);[$b,$bytes,$signature]=NativeCryptoCodec::decode($proof);
        $c=$b['payload']['context'];
        foreach(['serverId','migrationId','captureId','sourceInventoryRoot']as$k)if($c[$k]!==$common[$k])throw new NativeError('crypto_invitation_bridge_context');
        if($b['accountId']!==$common['accountId']||$b['operation']!=='crypto2.invitations.bridgeLegacy'||$c['bindingId']!==$bindingId)throw new NativeError('crypto_invitation_bridge_context');
        NativeCryptoV2Codec::verify($bytes,$signature,$this->signer($common['accountId'],$b['payload']['authorDirectoryHeadHash'],$b['deviceId'],$actor));
        $hash=NativeCryptoV2Codec::hash((object)$proof);
        $leaf=['bindingId'=>$bindingId,'kind'=>$row['kind'],'bridgeHash'=>$hash,'capsuleHash'=>$row['capsule_hash']];
        if($hash!==$row['bridge_hash']||NativeCryptoMigrationInvitationV3::leafDigest($leaf)!==$row['leaf_hash'])throw new NativeError('crypto_invitation_bridge_storage',503);
        return $hash;
    }

    public function stagedCoverage($migrationId,$captureId,$sourceInventoryRoot,$actor,callable $captureSourceBindings,$history=false)
    {
        $this->transactionRequired(); $common=$this->context(compact('migrationId','captureId','sourceInventoryRoot'),$actor);
        $counts=['invitation'=>0,'mail'=>0]; $total=0;
        foreach ($captureSourceBindings($migrationId,$captureId,$sourceInventoryRoot,$actor,self::TABLES) as $entry) {
            $kind=$entry['context']['sourceTable']==='familyhub_invitations'?'invitation':'mail';
            $binding=NativeCryptoCaptureV3::binding($entry['binding']);
            $row=$this->one('SELECT * FROM familyhub_crypto_invitation_bridges_v3 WHERE migration_id=? AND account_id=? AND binding_id=?',[$migrationId,$common['accountId'],$binding['bindingId']]);
            if (!$row || $row['kind']!==$kind) { throw new NativeError('crypto_invitation_bridge_incomplete',409); }
            $proof=json_decode($row['authorization'],true,34,JSON_THROW_ON_ERROR);
            [$b,$bytes,$signature]=NativeCryptoCodec::decode($proof);
            NativeCryptoV2Codec::verify($bytes,$signature,$this->signer($common['accountId'],$b['payload']['authorDirectoryHeadHash'],$b['deviceId'],$actor,$history));
            if (!$history) {
                $c=$b['payload']['context'];
                $scope=$this->scope($c['scopeId'],$actor['user']['id']);
                $scopes=new NativeCryptoScopeV2($this->container);
                $head=$scopes->current($c['scopeId']);
                if (!$head || $head['head_hash']!==$c['membershipHeadHash']) { throw new NativeError('crypto_scope_head_conflict',409); }
                $scopes->manager($head,$scope,$actor);
            }
            $hash=NativeCryptoV2Codec::hash((object)$proof);
            $leaf=['bindingId'=>$binding['bindingId'],'kind'=>$kind,'bridgeHash'=>$hash,'capsuleHash'=>$row['capsule_hash']];
            if ($hash!==$row['bridge_hash'] || $row['leaf_hash']!==NativeCryptoMigrationInvitationV3::leafDigest($leaf) ||
                $b['payload']['context']['sourceCommitment']!==$binding['sourceCommitment'] ||
                $b['payload']['context']['bindingId']!==$binding['bindingId']) {
                throw new NativeError('crypto_invitation_bridge_storage',503);
            }
            $counts[$kind]++; $total++;
        }
        $n=$this->one('SELECT COUNT(*) n FROM familyhub_crypto_invitation_bridges_v3 WHERE migration_id=? AND account_id=?',[$migrationId,$common['accountId']]);
        if ((int)$n['n']!==$total) { throw new NativeError('crypto_invitation_bridge_extra_source',409); }
        $digests=(function()use($migrationId,$common){foreach($this->leafRows($migrationId,$common['accountId'])as$r)yield$r['leaf_hash'];})();
        return $common+['selectionRoot'=>NativeCryptoMigrationInvitationV3::selectionRoot($common,$total,$digests),
            'bridgeCount'=>$total,'sourceCounts'=>$counts,'state'=>'staged'];
    }

    /** The caller verifies the exact completed own archive and signed cold
     * comparison (which binds selectionRoot, never this certificate hash).
     */
    public function certify($p, $actor, $proof, $command,
        callable $captureSourceBindings, callable $verifyPrerequisites)
    {
        $this->transactionRequired();
        $this->fields($p,['header']);
        $header = NativeCryptoMigrationInvitationV3::header($p['header']);
        if ($header['serverId'] !== $this->serverId() || $header['accountId'] !== $actor['user']['account_id'] ||
            $command['operation'] !== 'crypto2.migration.invitations.certify' ||
            $command['accountId'] !== $header['accountId'] ||
            !$this->same((object)$command['payload'],(object)$p)) {
            throw new NativeError('crypto_invitation_migration_certificate');
        }
        [$decoded,$bytes,$signature] = NativeCryptoCodec::decode($proof);
        if (!$this->same((object)$decoded,(object)$command)) {
            throw new NativeError('crypto_invitation_migration_certificate');
        }
        NativeCryptoV2Codec::verify($bytes,$signature,
            $this->signer($header['accountId'],$header['authorDirectoryHeadHash'],$command['deviceId'],$actor));
        $selected = $this->stagedCoverage($header['migrationId'],$header['captureId'],
            $header['sourceInventoryRoot'],$actor,$captureSourceBindings);
        if ($selected['bridgeCount'] !== $header['bridgeCount'] ||
            !$this->same((object)$selected['sourceCounts'],(object)$header['sourceCounts']) ||
            $verifyPrerequisites($header,$selected,$actor) !== true) {
            throw new NativeError('crypto_invitation_migration_cold_parity',409);
        }
        $digests = (function () use ($header) {
            foreach ($this->leafRows($header['migrationId'],$header['accountId']) as $row) {
                yield $row['leaf_hash'];
            }
        })();
        if (NativeCryptoMigrationInvitationV3::bridgeRoot($header,$digests) !== $header['bridgeRoot']) {
            throw new NativeError('crypto_invitation_migration_incomplete',409);
        }
        $hash = NativeCryptoV2Codec::hash((object)$proof);
        $old = $this->certificate($header['migrationId'],$header['accountId']);
        if ($old) {
            if ($old['certificate_hash'] !== $hash) {
                throw new NativeError('crypto_invitation_migration_certificate_immutable',409);
            }
        } else {
            $this->change('INSERT INTO familyhub_crypto_invitation_certificates_v3 VALUES(?,?,?,?,?,?,?,?,?,?,NULL,NULL,NULL,?)', [
                $header['migrationId'],$header['accountId'],$header['captureId'],$header['sourceInventoryRoot'],
                $hash,$selected['selectionRoot'],$header['bridgeRoot'],$header['bridgeCount'],
                json_encode($header['sourceCounts'],JSON_THROW_ON_ERROR),json_encode($proof,JSON_THROW_ON_ERROR),'certified']);
        }
        return ['migrationId'=>$header['migrationId'],'captureId'=>$header['captureId'],
            'certificateHash'=>$hash,'selectionRoot'=>$selected['selectionRoot'],
            'bridgeRoot'=>$header['bridgeRoot'],'bridgeCount'=>$header['bridgeCount'],
            'scopeToken'=>NativeCryptoMigrationInvitationV3::scopeToken($header),'state'=>'certified'];
    }

    /** Called ONLY inside the final component cutover transaction. Both passes
     * finish validation before publication; legacy mail rows stay byte-exact and
     * no new mail job or recipient acceptance is fabricated. */
    public function prepareInstall(array $expected,$actor,callable $captureSourceBindings,callable $captureSourceBinding)
    {
        $this->transactionRequired();
        $coverage=$this->coverage($expected['migrationId'],$expected['captureId'],$expected['sourceInventoryRoot'],$actor,$captureSourceBindings);
        foreach (['certificateHash','selectionRoot','bridgeRoot','bridgeCount'] as $k) {
            if (($expected[$k]??null)!==$coverage[$k]) { throw new NativeError('crypto_invitation_bridge_install_context',409); }
        }
        foreach ($captureSourceBindings($expected['migrationId'],$expected['captureId'],$expected['sourceInventoryRoot'],$actor,self::TABLES) as $entry) {
            $source=$captureSourceBinding($expected['migrationId'],$expected['captureId'],$entry['binding']['bindingId'],$actor);
            $row=$this->one('SELECT * FROM familyhub_crypto_invitation_bridges_v3 WHERE migration_id=? AND account_id=? AND binding_id=?',[$expected['migrationId'],$actor['user']['account_id'],$entry['binding']['bindingId']]);
            $v=$this->bridge(json_decode($row['authorization'],true,34,JSON_THROW_ON_ERROR),$row['capsule'],$coverage,$source,$actor,true);
            if ($v['bridgeHash']!==$row['bridge_hash'] || $v['leafHash']!==$row['leaf_hash']) { throw new NativeError('crypto_invitation_bridge_storage',503); }
            if ($v['metadata']===null && $this->one('SELECT invitation_id FROM familyhub_crypto_invitation_mail_v2 WHERE invitation_id=?',[$v['source']['invitation_id']])) { throw new NativeError('crypto_invitation_bridge_target_conflict',409); }
            if ($v['metadata']!==null && $this->one('SELECT id FROM familyhub_crypto_invitations_v2 WHERE id=? OR token_hash=?',[$v['metadata']['invitationId'],$v['metadata']['tokenHash']])) {
                throw new NativeError('crypto_invitation_bridge_target_conflict',409);
            }
        }
        $used=false;
        return function()use($expected,$actor,$captureSourceBindings,$captureSourceBinding,$coverage,&$used){
            $this->transactionRequired();
            if($used)throw new NativeError('crypto_invitation_bridge_install_used',409);
            $used=true;
        foreach ($captureSourceBindings($expected['migrationId'],$expected['captureId'],$expected['sourceInventoryRoot'],$actor,['familyhub_invitations']) as $entry) {
            $source=$captureSourceBinding($expected['migrationId'],$expected['captureId'],$entry['binding']['bindingId'],$actor);
            $raw=$this->cells($source['typedRow']);
            $row=$this->one('SELECT * FROM familyhub_crypto_invitation_bridges_v3 WHERE migration_id=? AND account_id=? AND binding_id=?',[$expected['migrationId'],$actor['user']['account_id'],$entry['binding']['bindingId']]);
            [$b]=NativeCryptoCodec::decode(json_decode($row['authorization'],true,34,JSON_THROW_ON_ERROR));
            $recipient=$raw['recipient_email']!==null?'email':'username';
            $state=$raw['accepted_at']!==null?'accepted':($raw['revoked_at']!==null?'revoked':'pending');
            $this->change('INSERT INTO familyhub_crypto_invitations_v2 VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)',[
                $raw['id'],$raw['scope_id'],$actor['user']['account_id'],$b['deviceId'],$recipient,
                $raw['recipient_email']??$raw['recipient_username'],$raw['recipient_account_id'],$raw['role'],$raw['token_hash'],
                (int)$raw['created_at'],(int)$raw['expires_at'],$state,$row['authorization'],'sl',null]);
        }
        // This is the same original delivery intent, not a fresh send: no
        // identifier, attempt, accepted timestamp or in-flight lease is reset.
        foreach ($captureSourceBindings($expected['migrationId'],$expected['captureId'],$expected['sourceInventoryRoot'],$actor,['familyhub_invitation_mail']) as $entry) {
            $source=$captureSourceBinding($expected['migrationId'],$expected['captureId'],$entry['binding']['bindingId'],$actor);
            $raw=$this->cells($source['typedRow']);
            $this->change('INSERT INTO familyhub_crypto_invitation_mail_v2 VALUES(?,?,?,?,?,?,?,?,?)',[
                $raw['invitation_id'],$raw['token_cipher'],$raw['language'],$raw['state'],(int)$raw['attempts'],
                (int)$raw['next_attempt'],$raw['lease_token'],$raw['lease_until']===null?null:(int)$raw['lease_until'],
                $raw['accepted_at']===null?null:(int)$raw['accepted_at']]);
        }
        $this->change("UPDATE familyhub_crypto_invitation_certificates_v3 SET state='installed' WHERE migration_id=? AND account_id=?",[$expected['migrationId'],$actor['user']['account_id']]);
        return array_replace($coverage,['state'=>'installed']);
        };
    }

    public function install(array $expected,$actor,callable $captureSourceBindings,callable $captureSourceBinding)
    {
        return ($this->prepareInstall($expected,$actor,$captureSourceBindings,$captureSourceBinding))();
    }

    /** Token-specific public evidence. Never returns another leaf, private stage
     * outer, source row, mail state, recipient list, or another token. */
    public function retained($tokenHash)
    {
        $route=$this->one('SELECT * FROM familyhub_crypto_invitation_routes_v3 WHERE token_hash=?',[$this->digest($tokenHash)]);
        if (!$route) return null;
        $certificate=$this->certificate($route['migration_id'],$route['account_id']);
        if (!$certificate || $certificate['state']!=='installed') { throw new NativeError('crypto_invitation_bridge_pending',409); }
        $event=$this->includedEvent($certificate);
        [$command,$header,$proof,$bytes,$signature]=$this->certificateHeader($certificate);
        $actor=['user'=>['account_id'=>$route['account_id']]];
        NativeCryptoV2Codec::verify($bytes,$signature,$this->signer($route['account_id'],$header['authorDirectoryHeadHash'],$command['deviceId'],$actor,true));
        $this->assertCertificateStream($header);
        $row=$this->one('SELECT * FROM familyhub_crypto_invitation_bridges_v3 WHERE migration_id=? AND account_id=? AND binding_id=?',[$route['migration_id'],$route['account_id'],$route['binding_id']]);
        $authorization=json_decode($row['authorization'],true,34,JSON_THROW_ON_ERROR);
        [$leafCommand,$leafBytes,$leafSignature]=NativeCryptoCodec::decode($authorization);
        NativeCryptoV2Codec::verify($leafBytes,$leafSignature,$this->signer($route['account_id'],$leafCommand['payload']['authorDirectoryHeadHash'],$leafCommand['deviceId'],$actor,true));
        $leaf=['bindingId'=>$row['binding_id'],'kind'=>'invitation','bridgeHash'=>NativeCryptoV2Codec::hash((object)$authorization),'capsuleHash'=>$row['capsule_hash']];
        if ($leaf['bridgeHash']!==$row['bridge_hash'] || NativeCryptoMigrationInvitationV3::leafDigest($leaf)!==$row['leaf_hash'] ||
            hash('sha256',base64_decode($row['capsule'],true))!==$leaf['capsuleHash']) { throw new NativeError('crypto_invitation_bridge_storage',503); }
        $metadata=$this->capsule($row['capsule'],$leafCommand['payload']['context'],null,$tokenHash);
        $cutover=$this->retainedCutover($route,$certificate,$leafCommand['payload']['context']);
        return ['legacyAccepted'=>$metadata['acceptedAtEpoch']!==null,'legacyRevoked'=>$metadata['revokedAtEpoch']!==null,
            'legacyAcceptedAtEpoch'=>$metadata['acceptedAtEpoch'],'legacyRevokedAtEpoch'=>$metadata['revokedAtEpoch'],
            'authorization'=>$authorization,'capsuleBase64'=>$row['capsule'],'certificateAuthorization'=>$proof,
            'eventAuthorization'=>$event,'eventHeadHash'=>$certificate['event_head_hash'],
            'eventCommandHash'=>$certificate['event_command_hash'],'leafHash'=>$row['leaf_hash'],
            'bridgeRoot'=>$certificate['bridge_root'],'bridgeCount'=>(int)$certificate['bridge_count'],
            'cutover'=>$cutover];
    }

    /** Token holders get only this scope's final activation, their exact
     * invitation-control leaf and opaque sibling digests, never verify3 or a
     * private component archive/header. Installed SQL flags are insufficient. */
    private function retainedCutover($route,$certificate,$context)
    {
        $sid=$context['scopeId'];
        $activation=$this->one("SELECT * FROM familyhub_crypto_migration_activations_v3 WHERE migration_id=? AND scope_id=? AND state='committed'",[$route['migration_id'],$sid]);
        if(!$activation||$activation['membership_head_hash']!==$context['membershipHeadHash'])throw new NativeError('crypto_invitation_cutover_pending',409);
        $selected=null;$after='';$count=0;
        do{
            $page=$this->many('SELECT control_hash,binding FROM familyhub_crypto_migration_controls_v3 WHERE migration_id=? AND scope_id=? AND control_hash>? ORDER BY control_hash LIMIT 50',[$route['migration_id'],$sid,$after]);
            foreach($page as $item){$after=$item['control_hash'];if(++$count>5000)throw new NativeError('crypto_invitation_bridge_capacity',409);$leaf=json_decode($item['binding'],true,34,JSON_THROW_ON_ERROR);
                if(($leaf['kind']??null)!=='invitations'||($leaf['certificateHash']??null)!==$certificate['certificate_hash'])continue;
                if($selected!==null||$leaf['scopeId']!==$sid||$leaf['captureId']!==$certificate['capture_id']||$leaf['sourceInventoryRoot']!==$certificate['source_inventory_root']||$leaf['eventCommandHash']!==$certificate['event_command_hash']||$leaf['selectionRoot']!==$certificate['selection_root']||$leaf['selectionCount']!==(int)$certificate['bridge_count'])throw new NativeError('crypto_invitation_cutover_binding',409);
                $selected=$item['control_hash'];
            }
        }while(count($page)===50);
        if($selected===null)throw new NativeError('crypto_invitation_cutover_pending',409);
        $result=(new NativeCryptoMigrationV2($this->container,$this->bearer,$this->ip))->activation3Evidence($activation,['controlHash'=>$selected]);
        $head=(new NativeCryptoScopeV2($this->container))->head($sid,$activation['membership_head_hash']);
        $result['membershipAuthorization']=json_decode($head['authorization'],true,34,JSON_THROW_ON_ERROR);
        [$event,$eventBytes]=NativeCryptoCodec::decode($result['eventAuthorization']);
        $included=$this->one('SELECT head_hash FROM familyhub_crypto_directory WHERE account_id=? AND generation=? AND command_hash=?',[$event['accountId'],$event['payload']['expectedGeneration']+1,hash('sha256',$eventBytes)]);
        if(!$included)throw new NativeError('crypto_invitation_cutover_event_pending',409);
        $result['managerEventHeadHash']=$included['head_hash'];
        return $result;
    }

    public function activationDirectoryReference($tokenHash)
    {
        $evidence=$this->retained($tokenHash);
        if(!$evidence)throw new NativeError('invitation_invalid',404);
        [$event]=NativeCryptoCodec::decode($evidence['cutover']['eventAuthorization']);
        return ['accountId'=>$event['accountId'],'headHash'=>$evidence['cutover']['managerEventHeadHash']];
    }

    public function digestPage($tokenHash,$after=null,$limit=20)
    {
        $evidence=$this->retained($tokenHash);
        if (!$evidence) { throw new NativeError('invitation_invalid',404); }
        $route=$this->one('SELECT * FROM familyhub_crypto_invitation_routes_v3 WHERE token_hash=?',[$tokenHash]);
        if ($after!==null) $this->digest($after);
        if (!is_int($limit) || $limit<1 || $limit>20) { throw new NativeError('invalid_cursor'); }
        $rows=$this->many('SELECT leaf_hash FROM familyhub_crypto_invitation_bridges_v3 WHERE migration_id=? AND account_id=? AND leaf_hash>? ORDER BY leaf_hash LIMIT '.($limit+1),[$route['migration_id'],$route['account_id'],$after??'']);
        $more=count($rows)>$limit; $rows=array_slice($rows,0,$limit);
        return ['digests'=>array_column($rows,'leaf_hash'),'hasMore'=>$more,'nextAfterHash'=>$rows?end($rows)['leaf_hash']:$after];
    }

    private function assertCertificateStream($header)
    {
        $digests=(function()use($header){
            foreach($this->leafRows($header['migrationId'],$header['accountId'])as$row) {
                $proof=json_decode($row['authorization'],true,34,JSON_THROW_ON_ERROR);
                [$command,$bytes,$signature]=NativeCryptoCodec::decode($proof);
                NativeCryptoV2Codec::verify($bytes,$signature,$this->signer($header['accountId'],
                    $command['payload']['authorDirectoryHeadHash'],$command['deviceId'],['user'=>['account_id'=>$header['accountId']]],true));
                $leaf=['bindingId'=>$row['binding_id'],'kind'=>$row['kind'],
                    'bridgeHash'=>NativeCryptoV2Codec::hash((object)$proof),'capsuleHash'=>$row['capsule_hash']];
                if ($leaf['bridgeHash']!==$row['bridge_hash'] || NativeCryptoMigrationInvitationV3::leafDigest($leaf)!==$row['leaf_hash']) {
                    throw new NativeError('crypto_invitation_bridge_storage',503);
                }
                yield$row['leaf_hash'];
            }
        })();
        if (NativeCryptoMigrationInvitationV3::bridgeRoot($header,$digests)!==$header['bridgeRoot']) {
            throw new NativeError('crypto_invitation_bridge_storage',503);
        }
    }

    private function certificate($migrationId, $account)
    {
        return $this->one('SELECT * FROM familyhub_crypto_invitation_certificates_v3 WHERE migration_id=? AND account_id=?',[$migrationId,$account]);
    }

    private function certificateHeader($row)
    {
        $proof = json_decode($row['authorization'],true,34,JSON_THROW_ON_ERROR);
        [$command,$bytes,$signature] = NativeCryptoCodec::decode($proof);
        $this->fields($command,['version','operation','requestId','serverId','accountId','deviceId','signer','payload']);
        $this->fields($command['payload'],['header']);
        $header = NativeCryptoMigrationInvitationV3::header($command['payload']['header']);
        if (NativeCryptoV2Codec::hash((object)$proof) !== $row['certificate_hash'] ||
            $command['version'] !== 2 || $command['operation'] !== 'crypto2.migration.invitations.certify' ||
            $command['signer'] !== 'device' || $command['serverId'] !== $this->serverId() ||
            $command['accountId'] !== $row['account_id'] || $header['accountId'] !== $row['account_id'] ||
            $header['serverId'] !== $this->serverId() || $header['migrationId'] !== $row['migration_id'] ||
            $header['captureId'] !== $row['capture_id'] || $header['sourceInventoryRoot'] !== $row['source_inventory_root'] ||
            $header['bridgeRoot'] !== $row['bridge_root'] ||
            $header['bridgeCount'] !== (int)$row['bridge_count'] ||
            !$this->same((object)$header['sourceCounts'],(object)json_decode($row['source_counts'],true,34,JSON_THROW_ON_ERROR))) {
            throw new NativeError('crypto_invitation_migration_storage',503);
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
            throw new NativeError('crypto_invitation_migration_event_missing',409);
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
            $command['payload']['scopeToken'] !== NativeCryptoMigrationInvitationV3::scopeToken($header) ||
            $command['payload']['attestationHash'] !== $row['certificate_hash']) {
            throw new NativeError('crypto_invitation_migration_event_invalid',409);
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
            throw new NativeError('crypto_invitation_migration_certificate_missing',409);
        }
        if ($row['state'] === 'anchored' &&
            ($row['event_head_hash'] !== $p['eventHeadHash'] || $row['event_command_hash'] !== $p['eventCommandHash'])) {
            throw new NativeError('crypto_invitation_migration_event_immutable',409);
        }
        $row['event_head_hash'] = $p['eventHeadHash'];
        $row['event_command_hash'] = $p['eventCommandHash'];
        $eventProof = $this->includedEvent($row);
        [$certificate,$header,,$certificateBytes,$certificateSignature] = $this->certificateHeader($row);
        NativeCryptoV2Codec::verify($certificateBytes,$certificateSignature,
            $this->signer($row['account_id'],$header['authorDirectoryHeadHash'],$certificate['deviceId'],$actor,true));
        $this->change("UPDATE familyhub_crypto_invitation_certificates_v3 SET event_head_hash=?,event_command_hash=?,event_authorization=?,state='anchored' WHERE migration_id=? AND account_id=?",[
            $row['event_head_hash'],$row['event_command_hash'],json_encode($eventProof,JSON_THROW_ON_ERROR),$row['migration_id'],$row['account_id']]);
        return ['migrationId'=>$row['migration_id'],'certificateHash'=>$row['certificate_hash'],'state'=>'anchored'];
    }

    public function coverage($migrationId, $captureId, $sourceInventoryRoot, $actor,
        callable $captureSourceBindings)
    {
        $this->transactionRequired();
        $row = $this->certificate($this->uuid($migrationId),$actor['user']['account_id']);
        if (!$row || $row['capture_id'] !== $captureId || $row['source_inventory_root'] !== $sourceInventoryRoot ||
            !in_array($row['state'],['anchored','installed'],true)) {
            throw new NativeError('crypto_invitation_migration_anchor_pending',409);
        }
        $event = $this->includedEvent($row);
        [$command,$header,$proof,$bytes,$signature] = $this->certificateHeader($row);
        NativeCryptoV2Codec::verify($bytes,$signature,
            $this->signer($row['account_id'],$header['authorDirectoryHeadHash'],$command['deviceId'],$actor,true));
        // Historical transforms are admitted only after the exact certificate
        // has been found in the verified own account log, never fresh issuance.
        $this->assertCertificateStream($header);
        $selected = $this->stagedCoverage($migrationId,$captureId,$sourceInventoryRoot,$actor,$captureSourceBindings,true);
        if ($selected['selectionRoot'] !== $row['selection_root'] ||
            $selected['bridgeCount'] !== (int)$row['bridge_count'] ||
            !$this->same((object)$selected['sourceCounts'],(object)json_decode($row['source_counts'],true,34,JSON_THROW_ON_ERROR))) {
            throw new NativeError('crypto_invitation_migration_selection_changed',409);
        }
        return array_replace($selected, ['certificateHash'=>$row['certificate_hash'],'bridgeRoot'=>$row['bridge_root'],
            'eventHeadHash'=>$row['event_head_hash'],'eventCommandHash'=>$row['event_command_hash'],
            'authorization'=>$proof,'eventAuthorization'=>$event,'state'=>'anchored']);
    }

}
