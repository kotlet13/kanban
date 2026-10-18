<?php
namespace Kanboard\Plugin\FamilyHub\Model;

/** Scoped retained audit evidence. Discovery/index rows never authorize a read
 * or establish completeness: the final finance certificate, scoped control
 * leaves and the full signed artifact stream must agree. No legacy source is
 * consulted after cutover. */
class NativeCryptoMigrationAuditReadV3 extends NativeDatabase
{
    protected $cryptoAccess=true;
    private const MAX_RESPONSE=1310720;
    private function digest($v){if(!is_string($v)||!preg_match('/^[a-f0-9]{64}$/D',$v))throw new NativeError('crypto_migration_audit_context');return $v;}
    private function hash($v){return NativeCryptoV2Codec::hash((object)$v);}
    private function body($proof){[$body]=NativeCryptoCodec::decode($proof);return $body;}
    private function artifactHash($proof){return hash('sha256',"JivieMigrationAuditArtifact/v3\n".NativeCryptoCodec::canonical((object)$proof));}
    private function current($sid,$actor)
    {
        $scope=$this->scope($sid,$actor['user']['id']);$scopes=new NativeCryptoScopeV2($this->container,$this->bearer,$this->ip);$head=$scopes->current($sid);
        if(!$head)throw new NativeError('crypto_scope_head_missing',409);
        $scopes->author($sid,$head['head_hash'],(int)$head['epoch'],(int)$scope['effective_access_revision'],$actor,'finance',false);
        $crypto=$this->one('SELECT migration_id,state FROM familyhub_crypto_scopes WHERE scope_id=?',[$sid]);
        if(!$crypto||!$crypto['migration_id'])return null;
        $activation=$this->one("SELECT * FROM familyhub_crypto_migration_activations_v3 WHERE migration_id=? AND scope_id=? AND state='committed'",[$crypto['migration_id'],$sid]);
        if(!$activation)throw new NativeError('crypto_migration_audit_provenance_pending',409);
        $evidence=(new NativeCryptoMigrationV2($this->container,$this->bearer,$this->ip))->activation3Evidence($activation);
        $ah=$this->body($evidence['authorization']);
        $cert=$this->one("SELECT * FROM familyhub_crypto_migration_domain_attestations_v2 WHERE migration_id=? AND scope_id=? AND domain='finance' AND state='anchored'",[$activation['migration_id'],$sid]);
        if(!$cert)throw new NativeError('crypto_migration_audit_provenance_pending',409);
        $proof=json_decode($cert['authorization'],true,64,JSON_THROW_ON_ERROR);$body=$this->body($proof);$p=$body['payload'];
        if($this->hash($proof)!==$ah['financeCertificateHash']||$p['header']['scopeId']!==$sid||$p['header']['domain']!=='finance')throw new NativeError('crypto_migration_audit_provenance',409);
        $event=$this->one('SELECT authorization FROM familyhub_crypto_directory WHERE account_id=? AND head_hash=?',[$cert['manager_account_id'],$cert['event_head_hash']]);
        if(!$event)throw new NativeError('crypto_migration_audit_provenance_pending',409);
        $contexts=[];$seen=[];
        foreach($p['contributions'] as $contribution){
            $command=$this->body($contribution['authorization']);$cp=$command['payload'];$h=$cp['header'];$token=$h['portionToken'];
            if(isset($seen[$token])||count($contexts)>=100||$h['domain']!=='finance')throw new NativeError('crypto_migration_audit_provenance',409);$seen[$token]=true;
            $controls=$this->many('SELECT binding FROM familyhub_crypto_migration_controls_v3 WHERE migration_id=? AND scope_id=? AND portion_token=? ORDER BY kind',[$activation['migration_id'],$sid,$token]);
            if(count($controls)!==5)throw new NativeError('crypto_migration_audit_provenance_pending',409);
            $controls=array_map(static fn($r)=>json_decode($r['binding'],true,34,JSON_THROW_ON_ERROR),$controls);
            $audit=array_values(array_filter($controls,static fn($v)=>$v['kind']==='audit'));
            if(count($audit)!==1||!isset($cp['scopeControlSections']['audit'])||NativeCryptoCodec::canonical((object)$cp['scopeControlSections']['audit'])!==NativeCryptoCodec::canonical((object)['kind'=>'audit','count'=>$audit[0]['selectionCount'],'root'=>$audit[0]['selectionRoot']]))throw new NativeError('crypto_migration_audit_provenance',409);
            $contexts[$token]=['accountId'=>$command['accountId'],'captureId'=>$h['captureId'],'sourceInventoryRoot'=>$h['sourceInventoryRoot'],
                'contributionAuthorization'=>$contribution['authorization'],'contributionEventAuthorization'=>$contribution['eventAuthorization'],'controls'=>$controls];
        }
        if(!$contexts)throw new NativeError('crypto_migration_audit_provenance',409);
        ksort($contexts,SORT_STRING);
        return ['version'=>3,'scopeId'=>$sid,'migrationId'=>$activation['migration_id'],'activationEvidence'=>$evidence,
            'certificateAuthorization'=>$proof,'certificateEventAuthorization'=>json_decode($event['authorization'],true,64,JSON_THROW_ON_ERROR),'contexts'=>array_values($contexts)];
    }
    private function selected($row,$base,$serverId=null)
    {
        $proof=json_decode($row['authorization'],true,64,JSON_THROW_ON_ERROR);$command=$this->body($proof);$p=$command['payload'];
        $descriptor=json_decode($row['descriptor'],true,34,JSON_THROW_ON_ERROR);$c=$descriptor['context'];
        if($command['version']!==2||$command['operation']!=='crypto2.migration.audit.stage'||$command['signer']!=='device'||$command['serverId']!==($serverId??$this->serverId())
            ||$command['accountId']!==$row['account_id']||$p['migrationId']!==$base['migrationId']||$p['captureId']!==$row['capture_id']||$p['sourceInventoryRoot']!==$row['source_inventory_root']
            ||$p['bindingId']!==$row['binding_id']||$c['scopeId']!==$base['scopeId']||$c['domain']!=='finance'||$c['recordId']!==$row['record_id']||(int)$c['legacyRevision']!==(int)$row['legacy_revision']
            ||NativeCryptoCodec::canonical((object)$p['descriptor'])!==NativeCryptoCodec::canonical((object)$descriptor))throw new NativeError('crypto_migration_audit_storage',503);
        $matches=array_values(array_filter($base['contexts'],static fn($v)=>$v['accountId']===$row['account_id']&&$v['captureId']===$row['capture_id']&&$v['sourceInventoryRoot']===$row['source_inventory_root']));
        if(count($matches)!==1)throw new NativeError('crypto_migration_audit_unselected',409);
        return ['bindingId'=>$row['binding_id'],'descriptor'=>$descriptor,'authorization'=>$proof,'artifactHash'=>$this->artifactHash($proof)];
    }
    public function read($p,$actor)
    {
        $this->fields($p,['scopeId'],['afterBindingId','limit']);$sid=$this->uuid($p['scopeId']);$after=$p['afterBindingId']??'';if($after!=='')$this->uuid($after);
        $limit=$p['limit']??20;if(!is_int($limit)||$limit<1||$limit>20)throw new NativeError('validation_error');
        $base=$this->current($sid,$actor);
        if($base===null)return ['version'=>3,'scopeId'=>$sid,'migrationId'=>null,'artifacts'=>[],'hasMore'=>false,'nextAfterBindingId'=>$after];
        if(strlen(json_encode($base,JSON_THROW_ON_ERROR))>self::MAX_RESPONSE)throw new NativeError('crypto_migration_audit_read_capacity',409);
        $rows=$this->many("SELECT * FROM familyhub_crypto_migration_audit_v3 WHERE migration_id=? AND scope_id=? AND state='installed' AND binding_id>? ORDER BY binding_id LIMIT ".($limit+1),[$base['migrationId'],$sid,$after]);
        $more=count($rows)>$limit;$out=[];
        foreach(array_slice($rows,0,$limit) as $row){
            $item=$this->selected($row,$base);$next=[...$out,$item];
            if(strlen(json_encode($base+['artifacts'=>$next],JSON_THROW_ON_ERROR))>self::MAX_RESPONSE){if(!$out)throw new NativeError('crypto_migration_audit_read_capacity',409);$more=true;break;}
            $out=$next;$after=$row['binding_id'];
        }
        return $base+['artifacts'=>$out,'hasMore'=>$more,'nextAfterBindingId'=>$after];
    }
    /** Only exact historical signer prefixes named by the fully folded final
     * scoped audit selection. Surviving readers never gain a latest-log tail. */
    public function directoryReferences($scopeId,$headHash,$accountId,$actor)
    {
        $sid=$this->uuid($scopeId);$account=$this->uuid($accountId);
        $scopes=new NativeCryptoScopeV2($this->container,$this->bearer,$this->ip);
        $current=$scopes->current($sid);
        if(!$current||$current['head_hash']!==$headHash)return [];
        // This is optional enrichment of a CONTENT directory read. No finance
        // prefix exists for a NONE reader or an unfinished publication.
        $reader=$scopes->member($scopes->body($current),$actor['user']['account_id']);
        if(!$reader||($reader['financeRole']??'none')==='none')return [];
        $activation=$this->one("SELECT a.migration_id FROM familyhub_crypto_migration_activations_v3 a JOIN familyhub_crypto_scopes s ON s.scope_id=a.scope_id AND s.migration_id=a.migration_id WHERE a.scope_id=? AND a.state='committed'",[$sid]);
        if(!$activation)return [];
        $base=$this->current($sid,$actor);if($base===null)return [];
        // A nonexistent selector deliberately returns no records while the
        // shared complete-set validator still checks every selected artifact.
        $this->committedDescriptors($sid,'00000000-0000-4000-a000-000000000000',$actor);
        $refs=[];$instanceId=$this->serverId();
        foreach($this->iterate("SELECT * FROM familyhub_crypto_migration_audit_v3 WHERE migration_id=? AND scope_id=? AND account_id=? AND state='installed' ORDER BY binding_id",[$base['migrationId'],$sid,$account]) as $row){
            $selected=$this->selected($row,$base,$instanceId);$command=$this->body($selected['authorization']);
            $reference=$this->digest($command['payload']['authorDirectoryHeadHash']);$refs[$reference]=true;
            if(count($refs)>1000)throw new NativeError('crypto_migration_audit_read_capacity',409);
        }
        return array_keys($refs);
    }
    /** Relocation binds the complete opaque retained source evidence set, after
     * re-folding every signed scoped artifact root. No SQL installed flag alone
     * authorizes a source descriptor or a historical actor claim. */
    public function committedDescriptors($scopeId,$canonicalRecordId,$actor)
    {
        $sid=$this->uuid($scopeId);$record=$this->uuid($canonicalRecordId);$base=$this->current($sid,$actor);if($base===null)return [];
        $states=[];
        foreach($base['contexts'] as $ctx){$cmd=$this->body($ctx['contributionAuthorization']);$h=$cmd['payload']['header'];$common=['version'=>3,'serverId'=>$this->serverId(),'migrationId'=>$base['migrationId'],'captureId'=>$ctx['captureId'],'accountId'=>$ctx['accountId'],'sourceInventoryRoot'=>$ctx['sourceInventoryRoot'],'scopeId'=>$sid,'domain'=>'finance'];
            $hash=hash_init('sha256');hash_update($hash,"JivieMigrationAuditScopeSelection/v3\n".NativeCryptoCodec::canonical((object)$common)."\n");
            $states[$ctx['accountId'].':'.$ctx['captureId']]=['hash'=>$hash,'count'=>0,'expected'=>$cmd['payload']['scopeControlSections']['audit']];}
        $selected=[];$instanceId=$this->serverId();
        foreach($this->iterate("SELECT * FROM familyhub_crypto_migration_audit_v3 WHERE migration_id=? AND scope_id=? AND state='installed' ORDER BY binding_id",[$base['migrationId'],$sid]) as $row){
            $item=$this->selected($row,$base,$instanceId);$key=$row['account_id'].':'.$row['capture_id'];
            hash_update($states[$key]['hash'],NativeCryptoCodec::canonical((object)['bindingId'=>$row['binding_id'],'artifactHash'=>$item['artifactHash']])."\n");$states[$key]['count']++;
            if($row['record_id']===$record){if(count($selected)>=10000)throw new NativeError('crypto_migration_audit_read_capacity',409);$selected[]=['revisionNamespace'=>'legacy','revision'=>(int)$row['legacy_revision'],'sourceEvidenceHash'=>$item['artifactHash'],'bindingId'=>$row['binding_id']];}
        }
        foreach($states as $s){if($s['count']!==$s['expected']['count']||hash_final($s['hash'])!==$s['expected']['root'])throw new NativeError('crypto_migration_audit_coverage',409);}
        return $selected;
    }
}
