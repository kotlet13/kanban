<?php
namespace Kanboard\Plugin\FamilyHub\Model;

/** Final scoped notification inclusion. Only the requested use (or the caller's
 * own reminder transform) and opaque digests leave private migration storage. */
class NativeCryptoMigrationNotificationReadV3 extends NativeDatabase
{
    protected $cryptoAccess = true;

    private function body($proof) { return NativeCryptoCodec::decode($proof)[0]; }
    private function digest($value)
    {
        if (!is_string($value) || !preg_match('/^[a-f0-9]{64}$/D', $value)) {
            throw new NativeError('validation_error');
        }
        return $value;
    }

    public function directoryReferences($scopeId, $headHash, $accountId)
    {
        $sid=$this->uuid($scopeId); $account=$this->uuid($accountId);
        $head=(new NativeCryptoScopeV2($this->container))->current($sid);
        if (!$head || $head['head_hash']!==$headHash) return [];
        $activation=$this->one("SELECT migration_id FROM familyhub_crypto_migration_activations_v3 WHERE scope_id=? AND state='committed'",[$sid]);
        if (!$activation) return [];
        $certificate=$this->one("SELECT migration_id FROM familyhub_crypto_notification_certificates_v3 WHERE migration_id=? AND account_id=? AND state='installed'",[$activation['migration_id'],$account]);
        if (!$certificate) return [];
        $refs=[];
        foreach ($this->iterate('SELECT t.authorization FROM familyhub_crypto_notification_selections_v3 s JOIN familyhub_crypto_notification_transforms_v3 t ON t.migration_id=s.migration_id AND t.account_id=s.account_id AND t.binding_id=s.binding_id AND t.transform_hash=s.transform_hash WHERE t.migration_id=? AND t.account_id=? AND t.kind=?',[$activation['migration_id'],$account,'reminder']) as $row) {
            $body=$this->body(json_decode($row['authorization'],true,34,JSON_THROW_ON_ERROR));
            if ($body['canonical']['scopeId']!==$sid) continue;
            $refs[$this->digest($body['authorDirectoryHeadHash'])]=true;
            if ($body['useAuthorization']!==null) {
                $use=$this->body($body['useAuthorization']);
                $refs[$this->digest($use['authorDirectoryHeadHash'])]=true;
            }
            if (count($refs)>1000) throw new NativeError('crypto_notification_migration_read_capacity',409);
        }
        return array_keys($refs);
    }

    public function read($p, $actor)
    {
        $this->fields($p, ['scopeId','targetId'], ['useProofHash','transformHash','afterDigest','limit']);
        $sid = $this->uuid($p['scopeId']);
        $target = NativeCryptoRecordAddressV2::wireId($p['targetId']);
        if (isset($p['useProofHash']) === isset($p['transformHash'])) {
            throw new NativeError('validation_error');
        }
        $ownTransform = isset($p['transformHash']);
        $hash = $this->digest($p[$ownTransform ? 'transformHash' : 'useProofHash']);
        $after = isset($p['afterDigest']) ? $this->digest($p['afterDigest']) : '';
        $limit = $p['limit'] ?? 20;
        if (!is_int($limit) || $limit < 1 || $limit > 20) throw new NativeError('validation_error');
        $column = $ownTransform ? 'transform_hash' : 'use_hash';
        $rows = $this->many('SELECT t.* FROM familyhub_crypto_notification_selections_v3 s JOIN familyhub_crypto_notification_transforms_v3 t ON t.migration_id=s.migration_id AND t.account_id=s.account_id AND t.binding_id=s.binding_id AND t.transform_hash=s.transform_hash WHERE t.'.$column.'=?', [$hash]);
        if (count($rows) !== 1 || $rows[0]['kind'] !== 'reminder') throw new NativeError('permission_revoked',403);
        $selected = $rows[0];
        $transformProof = json_decode($selected['authorization'],true,34,JSON_THROW_ON_ERROR);
        $transform = $this->body($transformProof);
        $canonical = $transform['canonical'];
        if ($canonical['scopeId'] !== $sid || $canonical['targetId'] !== $target ||
            $ownTransform && $selected['account_id'] !== $actor['user']['account_id'] ||
            !(new NativeCryptoNotificationV2($this->container,$this->bearer,$this->ip))->recipientVisible($sid,$actor['user']['account_id'],$canonical['domain'])) {
            throw new NativeError('permission_revoked',403);
        }
        $activation = $this->one("SELECT * FROM familyhub_crypto_migration_activations_v3 WHERE migration_id=? AND scope_id=? AND state='committed'",[$selected['migration_id'],$sid]);
        $certificate = $this->one("SELECT * FROM familyhub_crypto_migration_domain_attestations_v2 WHERE migration_id=? AND scope_id=? AND domain='content' AND state='anchored'",[$selected['migration_id'],$sid]);
        $private = $this->one("SELECT * FROM familyhub_crypto_notification_certificates_v3 WHERE migration_id=? AND account_id=? AND state='installed'",[$selected['migration_id'],$selected['account_id']]);
        if (!$activation || !$certificate || !$private) throw new NativeError('crypto_notification_migration_provenance_pending',409);
        $certProof = json_decode($certificate['authorization'],true,64,JSON_THROW_ON_ERROR);
        $cert = $this->body($certProof)['payload'];
        $activationBody = $this->body(json_decode($activation['authorization'],true,64,JSON_THROW_ON_ERROR));
        if (NativeCryptoV2Codec::hash((object)$certProof) !== $activationBody['contentCertificateHash']) throw new NativeError('crypto_notification_migration_provenance',409);
        $contributions = array_values(array_filter($cert['contributions'], fn($c) => $this->body($c['authorization'])['accountId'] === $selected['account_id']));
        if (count($contributions) !== 1) throw new NativeError('crypto_notification_migration_provenance',409);
        $contribution = $contributions[0];
        $cp = $this->body($contribution['authorization'])['payload'];
        $h = $cp['header'];
        $control = $this->one("SELECT binding FROM familyhub_crypto_migration_controls_v3 WHERE migration_id=? AND scope_id=? AND portion_token=? AND kind='notifications'",[$selected['migration_id'],$sid,$h['portionToken']]);
        if (!$control) throw new NativeError('crypto_notification_migration_provenance_pending',409);
        $control = json_decode($control['binding'],true,34,JSON_THROW_ON_ERROR);
        if ($control['certificateHash'] !== $private['certificate_hash'] || $control['eventCommandHash'] !== $private['event_command_hash'] ||
            $control['selectionRoot'] !== $private['selection_root'] || (int)$control['selectionCount'] !== (int)$private['transform_count'] ||
            $control['captureId'] !== $transform['captureId'] || $control['sourceInventoryRoot'] !== $transform['sourceInventoryRoot']) {
            throw new NativeError('crypto_notification_migration_provenance',409);
        }
        $event = $this->one('SELECT authorization FROM familyhub_crypto_directory WHERE account_id=? AND head_hash=?',[$certificate['manager_account_id'],$certificate['event_head_hash']]);
        if (!$event) throw new NativeError('crypto_notification_migration_provenance_pending',409);
        $evidence = (new NativeCryptoMigrationV2($this->container,$this->bearer,$this->ip))->activation3Evidence($activation);
        $evidence['controls'] = [$control];
        $digests = $this->many('SELECT t.leaf_hash FROM familyhub_crypto_notification_selections_v3 s JOIN familyhub_crypto_notification_transforms_v3 t ON t.migration_id=s.migration_id AND t.account_id=s.account_id AND t.binding_id=s.binding_id AND t.transform_hash=s.transform_hash WHERE t.migration_id=? AND t.account_id=? AND t.leaf_hash>? ORDER BY t.leaf_hash LIMIT '.($limit+1),[$selected['migration_id'],$selected['account_id'],$after]);
        $more = count($digests)>$limit;
        $digests = array_slice($digests,0,$limit);
        return ['version'=>3,'activationEvidence'=>$evidence,'certificateAuthorization'=>$certProof,
            'certificateEventAuthorization'=>json_decode($event['authorization'],true,64,JSON_THROW_ON_ERROR),
            'contributionAuthorization'=>$contribution['authorization'],'contributionEventAuthorization'=>$contribution['eventAuthorization'],
            'authorization'=>$ownTransform ? $transformProof : $transform['useAuthorization'],
            'leaf'=>['bindingId'=>$selected['binding_id'],'kind'=>'reminder','transformHash'=>$selected['transform_hash'],'useProofHash'=>$selected['use_hash']],
            'digests'=>array_column($digests,'leaf_hash'),'hasMore'=>$more,
            'nextAfterDigest'=>$digests ? end($digests)['leaf_hash'] : ($after ?: null)];
    }
}
