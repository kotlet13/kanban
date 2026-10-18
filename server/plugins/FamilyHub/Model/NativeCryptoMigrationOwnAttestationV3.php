<?php
namespace Kanboard\Plugin\FamilyHub\Model;

/** Own recovery routing only. Returned signatures are reverified by the client;
 * neither a database kind nor a missing lookup proves recovery completeness. */
class NativeCryptoMigrationOwnAttestationV3 extends NativeDatabase
{
    protected $cryptoAccess = true;

    public function read($p, $actor)
    {
        $this->fields($p, ['eventCommandHash','migrationId','domain','scopeToken','attestationHash']);
        $this->uuid($p['migrationId']);
        foreach (['eventCommandHash','scopeToken','attestationHash'] as $key) {
            if (!is_string($p[$key]) || !preg_match('/^[0-9a-f]{64}$/D', $p[$key])) throw new NativeError('invalid_hash');
        }
        if (!in_array($p['domain'], ['content','finance'], true)) throw new NativeError('invalid_domain');
        $account = $actor['user']['account_id'];
        $row = $this->one('SELECT authorization,head_hash FROM familyhub_crypto_directory WHERE account_id=? AND command_hash=?', [$account,$p['eventCommandHash']]);
        if (!$row) throw new NativeError('crypto_own_attestation_pending',409);
        $event = json_decode($row['authorization'], true, 64, JSON_THROW_ON_ERROR);
        [$command] = NativeCryptoCodec::decode($event);
        $payload = $command['payload'];
        if ($command['accountId'] !== $account || $command['serverId'] !== $this->serverId() || $command['operation'] !== 'crypto2.account.migrationAttest'
            || hash('sha256', NativeCryptoCodec::base64($event['commandBase64'], NativeCryptoCodec::MAX_COMMAND)) !== $p['eventCommandHash']) throw new NativeError('crypto_own_attestation_context',409);
        foreach (['migrationId','domain','scopeToken','attestationHash'] as $key) if (($payload[$key] ?? null) !== $p[$key]) throw new NativeError('crypto_own_attestation_context',409);
        $proofs = [];
        $add = static function ($raw) use (&$proofs,$p) {
            if ($raw === null) return;
            $proof = is_string($raw) ? json_decode($raw,true,128,JSON_THROW_ON_ERROR) : $raw;
            if (!is_array($proof) || count($proof)!==2 || !isset($proof['commandBase64'],$proof['signatureBase64'])) throw new NativeError('crypto_own_attestation_proof',409);
            $hash = hash('sha256', NativeCryptoCodec::canonical((object)$proof));
            if ($hash === $p['attestationHash']) $proofs[$hash] = $proof;
        };
        // Each query is restricted to one own migration and its exact stored
        // event/hash. No scan through arbitrary signed command history.
        foreach ([
            ['familyhub_crypto_migration_contributions_v3','account_id','event_command_hash','authorization',$p['eventCommandHash']],
            ['familyhub_crypto_migration_domain_attestations_v2','manager_account_id','event_head_hash','authorization',$row['head_hash']],
            ['familyhub_crypto_structure_sources_v3','account_id','certificate_hash','certificate_authorization',$p['attestationHash']],
            ['familyhub_crypto_invitation_certificates_v3','account_id','certificate_hash','authorization',$p['attestationHash']],
            ['familyhub_crypto_notification_certificates_v3','account_id','certificate_hash','authorization',$p['attestationHash']],
            ['familyhub_crypto_migration_activations_v3','manager_account_id','activation_hash','authorization',$p['attestationHash']],
        ] as [$table,$owner,$column,$proofColumn,$value]) {
            foreach($this->many("SELECT $proofColumn FROM $table WHERE migration_id=? AND $owner=? AND $column=? LIMIT 2",[$p['migrationId'],$account,$value]) as $match) $add($match[$proofColumn]);
        }
        foreach($this->many('SELECT a.authorization FROM familyhub_crypto_migration_generation_approvals_v3 a JOIN familyhub_crypto_migration_generations_v3 g ON g.id=a.generation_id WHERE g.migration_id=? AND a.account_id=?',[$p['migrationId'],$account]) as $approval)$add($approval['authorization']);
        foreach($this->many('SELECT authorization FROM familyhub_crypto_legacy_index_certificates_v3 WHERE migration_id=? AND account_id=? AND domain=? LIMIT 2',[$p['migrationId'],$account,$p['domain']]) as $match) $add($match['authorization']);
        // Local-intent descriptors are committed inside the original signed
        // verify3 command. Return that command, never an unsigned descriptor.
        $portion=$this->one('SELECT verification FROM familyhub_crypto_migration_portions_v2 WHERE migration_id=? AND account_id=?',[$p['migrationId'],$account]);
        if ($portion && $portion['verification'] !== null) {
            $v=json_decode($portion['verification'],true,128,JSON_THROW_ON_ERROR);
            $proof=$v['authorization']??null;
            if (is_array($proof)) {
                [$body]=NativeCryptoCodec::decode($proof);
                $descriptor=$body['payload']['localIntent']['descriptor']??null;
                if ($body['operation']==='crypto2.migration.verify3' && $body['accountId']===$account && is_array($descriptor)
                    && hash('sha256',NativeCryptoMigrationV2::inventoryCanonical((object)$descriptor))===$p['attestationHash']) $proofs['localIntent']=$proof;
            }
        }
        if (count($proofs)!==1) throw new NativeError('crypto_own_attestation_pending',409);
        $result=['eventAuthorization'=>$event,'authorizations'=>array_values($proofs)];
        if (strlen(json_encode($result,JSON_THROW_ON_ERROR))>1310720) throw new NativeError('crypto_own_attestation_capacity',409);
        return $result;
    }
}
