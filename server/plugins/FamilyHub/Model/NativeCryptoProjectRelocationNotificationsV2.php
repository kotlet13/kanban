<?php
namespace Kanboard\Plugin\FamilyHub\Model;

/** Routing transformations only. The manager never signs a substitute owner
 * put/use or receives another person's schedule, state, lease or attempts. */
class NativeCryptoProjectRelocationNotificationsV2 extends NativeDatabase
{
    protected $cryptoAccess=true;
    const DOMAIN="JivieProjectRelocationNotification/v2\n";
    private function hash($v){return NativeCryptoProjectRelocationCodecV2::hash($v);}
    private function same($a,$b){return NativeCryptoCodec::canonical($a)===NativeCryptoCodec::canonical($b);}

    private function rows($prepared)
    {
        $source=$prepared['body']['sourceScopeId'];$targets=[];
        foreach($prepared['leaves']['target'] as $leaf){
            $staged=$this->one('SELECT source_wire_id FROM familyhub_crypto_project_relocation_staged_v2 WHERE action_id=? AND scope_id=? AND wire_id=?',[$prepared['plan']['action_id'],$prepared['body']['targetScopeId'],$leaf['id']]);
            if($staged['source_wire_id']!==null)$targets[$staged['source_wire_id']]=$leaf;
        }
        $sources=[];foreach($prepared['descriptors'] as $d)$sources[$d['wireId']]=$d;
        foreach(['reminder'=>'familyhub_crypto_reminders_v2','inbox'=>'familyhub_inbox'] as $kind=>$table){
            $after=$kind==='inbox'?0:'';
            do{
                $page=$this->many('SELECT * FROM '.$table.' WHERE scope_id=? AND id>? ORDER BY id LIMIT 50',[$source,$after]);
                foreach($page as $row){
                    $after=$row['id'];$id=$row['target_id'];
                    if(!isset($targets[$id])||$row['target_type']!==$targets[$id]['type'])continue;
                    $use=$kind==='reminder'?$this->one('SELECT u.*,p.authorization FROM familyhub_crypto_scheduling_uses_v2 u JOIN familyhub_crypto_scheduling_use_proofs_v2 p ON p.account_id=u.account_id AND p.use_token=u.use_token AND p.proof_hash=u.proof_hash WHERE u.account_id=? AND u.reminder_id=?',[$row['account_id'],$row['id']]):null;
                    $put=$kind==='reminder'?($row['put_authorization']??$row['authorization']):null;
                    yield ['kind'=>$kind,'id'=>(string)$row['id'],'row'=>$row,'use'=>$use,
                        'target'=>$targets[$id],'source'=>$sources[$id],
                        'putHash'=>$put===null?null:$this->hash(json_decode($put,true,34,JSON_THROW_ON_ERROR))];
                }
            }while(count($page)===50);
        }
    }
    private function routing($prepared,$item,$route)
    {
        return ['version'=>2,'serverId'=>$this->serverId(),'actionId'=>$prepared['plan']['action_id'],
            'planHash'=>$prepared['plan']['plan_hash'],'routeId'=>$route,'kind'=>$item['kind'],
            'sourceRecordProofHash'=>$item['source']['recordProofHash'],
            'originalPutProofHash'=>$item['putHash'],'originalUseProofHash'=>$item['use']['proof_hash']??null,
            'originalUseEventCommandHash'=>$item['use']['event_command_hash']??null,
            'targetScopeId'=>$prepared['body']['targetScopeId'],'targetId'=>$item['target']['id'],
            'targetType'=>$item['target']['type'],'targetRecordProofHash'=>$item['target']['recordProofHash']];
    }

    /** Manager-visible fields contain only opaque routing commitments. The
     * complete original row stays private and immutable for final CAS. */
    public function discover($p,$actor,$command,$key)
    {
        $this->fields($p,['actionId','planHash'],['afterRouteId','limit']);
        $prepared=(new NativeCryptoProjectRelocationStageV2($this->container,$this->bearer,$this->ip))->prepareInstall($p['actionId'],$p['planHash'],$actor,$command,$key);
        return $this->candidates($prepared,$p['afterRouteId']??null,$p['limit']??32);
    }

    public function candidates($prepared,$after=null,$limit=32)
    {
        if(!$this->transactionActive()||!is_int($limit)||$limit<1||$limit>32)throw new NativeError('validation_error');
        if($after!==null)$this->uuid($after);
        $action=$prepared['plan']['action_id'];$out=[];
        $frozen=$this->one('SELECT notifications_frozen FROM familyhub_crypto_project_relocations_v2 WHERE action_id=?',[$action]);
        if(!(int)$frozen['notifications_frozen']){
        $count=0;
        foreach($this->rows($prepared) as $item){
            if(++$count>10000)throw new NativeError('crypto_relocation_capacity',409);
            $saved=$this->one('SELECT route_id,source_snapshot FROM familyhub_crypto_project_relocation_notifications_v2 WHERE action_id=? AND kind=? AND source_id=?',[$action,$item['kind'],$item['id']]);
            $snapshot=['row'=>$item['row'],'use'=>$item['use']];
            if($saved){
                if(!$this->same(json_decode($saved['source_snapshot'],true,34,JSON_THROW_ON_ERROR),$snapshot))throw new NativeError('project_sharing_preview_changed',409);
                continue;
            }
            $route=$this->newUuid();$owner=$item['kind']==='reminder'?$item['row']['account_id']:$item['row']['recipient_account_id'];
            $this->change('INSERT INTO familyhub_crypto_project_relocation_notifications_v2(action_id,route_id,kind,source_id,account_id,source_snapshot,routing,authorization) VALUES(?,?,?,?,?,?,?,NULL)',[$action,$route,$item['kind'],$item['id'],$owner,json_encode($snapshot,JSON_THROW_ON_ERROR),json_encode($this->routing($prepared,$item,$route),JSON_THROW_ON_ERROR)]);
        }
        $this->change('UPDATE familyhub_crypto_project_relocations_v2 SET notifications_frozen=1 WHERE action_id=?',[$action]);
        }
        $rows=$this->many('SELECT route_id,routing,authorization FROM familyhub_crypto_project_relocation_notifications_v2 WHERE action_id=? AND route_id>? ORDER BY route_id LIMIT '.($limit+1),[$action,$after??'']);
        $more=count($rows)>$limit;$rows=array_slice($rows,0,$limit);
        foreach($rows as $row)$out[]=['routing'=>json_decode($row['routing'],true,34,JSON_THROW_ON_ERROR),'authorization'=>$row['authorization']===null?null:json_decode($row['authorization'],true,34,JSON_THROW_ON_ERROR)];
        return ['routes'=>$out,'hasMore'=>$more,'nextAfterId'=>$rows?end($rows)['route_id']:$after];
    }
    public function stage($p,$actor,$command,$key)
    {
        $this->fields($p,['actionId','planHash','authorizations']);
        if(!is_array($p['authorizations'])||!array_is_list($p['authorizations'])||!$p['authorizations']||count($p['authorizations'])>32)throw new NativeError('validation_error');
        $verified=(new NativeCryptoProjectRelocationV2($this->container,$this->bearer,$this->ip))->validateSources($p['actionId'],$actor);
        if($verified['plan']['plan_hash']!==$p['planHash'])throw new NativeError('crypto_relocation_plan',409);
        foreach($p['authorizations'] as $proof){
            [$body,$bytes,$signature]=NativeCryptoCodec::decode($proof);
            $saved=$this->one('SELECT * FROM familyhub_crypto_project_relocation_notifications_v2 WHERE action_id=? AND route_id=?',[$p['actionId'],$this->uuid($body['routeId']??null)]);
            if(!$saved)throw new NativeError('crypto_relocation_notification_binding',409);
            $expected=json_decode($saved['routing'],true,34,JSON_THROW_ON_ERROR)+['accountId'=>$actor['user']['account_id'],'deviceId'=>$actor['device']['id'],'authorDirectoryHeadHash'=>$body['authorDirectoryHeadHash']??null];
            if(!$this->same($body,$expected))throw new NativeError('crypto_relocation_notification_binding',409);
            (new NativeCryptoScopeV2($this->container,$this->bearer,$this->ip))->currentAuthorReference($body['authorDirectoryHeadHash'],$actor);
            NativeCryptoV2Codec::verify($bytes,$signature,$key,self::DOMAIN);
            $encoded=json_encode($proof,JSON_THROW_ON_ERROR);
            if($saved['authorization']!==null&&!$this->same(json_decode($saved['authorization'],true,34,JSON_THROW_ON_ERROR),$proof))throw new NativeError('crypto_relocation_notification_immutable',409);
            $this->change('UPDATE familyhub_crypto_project_relocation_notifications_v2 SET authorization=?,proof_hash=? WHERE action_id=? AND route_id=?',[$encoded,$this->hash($proof),$p['actionId'],$saved['route_id']]);
        }
        return ['staged'=>true];
    }

    public function prepareInstall($prepared,$actor,$command,$key)
    {
        $action=$prepared['plan']['action_id'];$items=[];$hashes=[];
        foreach($this->rows($prepared) as $item){
            $row=$this->one('SELECT * FROM familyhub_crypto_project_relocation_notifications_v2 WHERE action_id=? AND kind=? AND source_id=?',[$action,$item['kind'],$item['id']]);
            if(!$row||$row['authorization']===null||!$this->same(json_decode($row['source_snapshot'],true,34,JSON_THROW_ON_ERROR),['row'=>$item['row'],'use'=>$item['use']])||!$this->same(json_decode($row['routing'],true,34,JSON_THROW_ON_ERROR),$this->routing($prepared,$item,$row['route_id'])))throw new NativeError('project_sharing_preview_changed',409);
            $proof=json_decode($row['authorization'],true,34,JSON_THROW_ON_ERROR);[$body,$bytes,$signature]=NativeCryptoCodec::decode($proof);
            $expected=$this->routing($prepared,$item,$row['route_id'])+['accountId'=>$actor['user']['account_id'],'deviceId'=>$actor['device']['id'],'authorDirectoryHeadHash'=>$body['authorDirectoryHeadHash']??null];
            if(!$this->same($body,$expected))throw new NativeError('crypto_relocation_notification_binding',409);
            (new NativeCryptoScopeV2($this->container,$this->bearer,$this->ip))->currentAuthorReference($body['authorDirectoryHeadHash'],$actor);
            NativeCryptoV2Codec::verify($bytes,$signature,$key,self::DOMAIN);
            $digest=$this->hash($proof);
            if($row['proof_hash']!==$digest)throw new NativeError('crypto_relocation_notification_binding',409);
            $hashes[]=$digest;$items[]=$item+['route'=>$row];
        }
        $count=(int)$this->one('SELECT COUNT(*) AS n FROM familyhub_crypto_project_relocation_notifications_v2 WHERE action_id=?',[$action])['n'];
        if($count!==count($items)||$count>10000)throw new NativeError('crypto_relocation_notification_incomplete',409);
        sort($hashes,SORT_STRING);
        return ['root'=>NativeCryptoProjectRelocationCodecV2::digestRoot('notifications',$hashes,1000000),'count'=>$count,'items'=>$items,'targetScopeId'=>$prepared['body']['targetScopeId']];
    }

    public function install($prepared)
    {
        if(!$this->transactionActive())throw new NativeError('crypto_relocation_transaction',409);
        foreach($prepared['items'] as $item){$row=$item['row'];$target=$item['target'];
            if($item['kind']==='reminder'){
                (new NativeNotificationWriter($this->container))->configurationChanged($row['account_id']);
                $this->change('UPDATE familyhub_crypto_reminders_v2 SET scope_id=?,target_id=?,target_revision=1 WHERE id=?',[$prepared['targetScopeId'],$target['id'],$row['id']]);
                $this->change('UPDATE familyhub_crypto_scheduling_uses_v2 SET scope_id=?,target_id=? WHERE account_id=? AND reminder_id=?',[$prepared['targetScopeId'],$target['id'],$row['account_id'],$row['id']]);
            }else{
                $this->change('UPDATE familyhub_inbox SET scope_id=?,target_id=? WHERE id=?',[$prepared['targetScopeId'],$target['id'],$row['id']]);
            }
            // IDs, original signatures, read/sent state, schedule revision,
            // dedupe, attempts and existing device/delivery leases stay exact.
        }
    }

    /** Exact finalized routing of prior consent; never new owner issuance. */
    public function installedUse($body,$hash,$scopeId,$targetId)
    {
        $row=$this->one("SELECT n.*,r.target_scope_id FROM familyhub_crypto_project_relocation_notifications_v2 n JOIN familyhub_crypto_project_relocations_v2 r ON r.action_id=n.action_id WHERE r.state='committed' AND r.target_scope_id=? AND n.kind='reminder' AND n.source_id=? AND n.account_id=?",[$scopeId,$body['schedulePutId'],$body['accountId']]);
        if(!$row || $row['authorization']===null)throw new NativeError('crypto_relocation_notification_pending',409);
        $route=json_decode($row['routing'],true,34,JSON_THROW_ON_ERROR);
        $publication=$this->one("SELECT authorization FROM familyhub_crypto_project_relocation_publications_v2 WHERE action_id=? AND scope_id=? AND side='target'",[$row['action_id'],$scopeId]);
        $snapshot=json_decode($row['source_snapshot'],true,34,JSON_THROW_ON_ERROR);
        if(!$publication || $route['targetId']!==$targetId || $route['originalUseProofHash']!==$hash ||
            !$snapshot['use'] || $snapshot['use']['proof_hash']!==$hash ||
            $this->hash(json_decode($snapshot['use']['authorization'],true,34,JSON_THROW_ON_ERROR))!==$hash) {
            throw new NativeError('crypto_relocation_notification_binding',409);
        }
        [$header]=NativeCryptoCodec::decode(json_decode($publication['authorization'],true,34,JSON_THROW_ON_ERROR));
        $digests=array_column($this->many('SELECT proof_hash FROM familyhub_crypto_project_relocation_notifications_v2 WHERE action_id=? ORDER BY proof_hash',[$row['action_id']]),'proof_hash');
        if(count($digests)!==$header['notificationCount'] || !in_array($row['proof_hash'],$digests,true) ||
            NativeCryptoProjectRelocationCodecV2::digestRoot('notifications',$digests,1000000)!==$header['notificationRoot']) {
            throw new NativeError('crypto_relocation_notification_incomplete',409);
        }
        $mapped=$body;$mapped['scopeId']=$scopeId;$mapped['targetId']=$targetId;$mapped['scopeLifecycleHash']=$header['lifecycleHash'];
        if($body['projectBarrier']!==null) {
            $project=$this->one('SELECT wire_id FROM familyhub_crypto_project_relocation_staged_v2 WHERE action_id=? AND scope_id=? AND source_wire_id=?',[$row['action_id'],$scopeId,$body['projectBarrier']['id']]);
            if(!$project)throw new NativeError('crypto_relocation_notification_binding',409);
            $mapped['projectBarrier']=['id'=>$project['wire_id'],'consentGeneration'=>$body['projectBarrier']['consentGeneration']];
        }
        return ['body'=>$mapped,'route'=>$row,'source'=>$snapshot];
    }

    public function useEvidence($p,$actor)
    {
        $this->fields($p,['scopeId','targetId','useProofHash'],['afterHash','limit']);
        $sid=$this->uuid($p['scopeId']);$target=NativeCryptoRecordAddressV2::wireId($p['targetId']);
        NativeCryptoProjectRelocationCodecV2::digest($p['useProofHash']);
        $row=$this->one('SELECT authorization FROM familyhub_crypto_scheduling_use_proofs_v2 WHERE proof_hash=?',[$p['useProofHash']]);
        if(!$row)throw new NativeError('permission_revoked',403);
        $proof=json_decode($row['authorization'],true,34,JSON_THROW_ON_ERROR);
        [$body]=(new NativeCryptoSchedulingUseV2($this->container))->body($proof);
        if(!(new NativeCryptoNotificationV2($this->container,$this->bearer,$this->ip))->recipientVisible($sid,$actor['user']['account_id'],$body['domain']))throw new NativeError('permission_revoked',403);
        $verified=$this->installedUse($body,$p['useProofHash'],$sid,$target);
        return $this->routeEvidence($verified['route'],$p,false);
    }

    public function directoryReferences($scopeId,$headHash,$accountId)
    {
        $head=(new NativeCryptoScopeV2($this->container))->current($scopeId);
        if(!$head || $head['head_hash']!==$headHash)return [];
        $refs=[];
        foreach($this->iterate("SELECT n.source_snapshot FROM familyhub_crypto_project_relocation_notifications_v2 n JOIN familyhub_crypto_project_relocations_v2 r ON r.action_id=n.action_id WHERE r.state='committed' AND r.target_scope_id=? AND n.account_id=? AND n.kind='reminder'",[$scopeId,$accountId]) as $row) {
            $snapshot=json_decode($row['source_snapshot'],true,34,JSON_THROW_ON_ERROR);
            foreach([$snapshot['row']['put_authorization']??$snapshot['row']['authorization'],$snapshot['use']['authorization']??null] as $encoded) {
                if($encoded===null)continue;
                [$body]=NativeCryptoCodec::decode(json_decode($encoded,true,34,JSON_THROW_ON_ERROR));
                $reference=$body['authorDirectoryHeadHash']??$body['payload']['authorDirectoryHeadHash']??null;
                if($reference===null)continue;
                NativeCryptoProjectRelocationCodecV2::digest($reference);$refs[$reference]=true;
                if(count($refs)>1000)throw new NativeError('crypto_relocation_capacity',409);
            }
        }
        return array_keys($refs);
    }

    private function routeEvidence($row,$p,$includePut)
    {
        $publication=$this->one("SELECT * FROM familyhub_crypto_project_relocation_publications_v2 WHERE action_id=? AND side='target'",[$row['action_id']]);
        if(!$publication)throw new NativeError('crypto_relocation_publication_pending',409);
        $source=json_decode($row['source_snapshot'],true,34,JSON_THROW_ON_ERROR);
        $after=$p['afterHash']??'';if($after!=='')NativeCryptoProjectRelocationCodecV2::digest($after);
        $limit=$p['limit']??32;if(!is_int($limit)||$limit<1||$limit>32)throw new NativeError('validation_error');
        $digests=$this->many('SELECT proof_hash FROM familyhub_crypto_project_relocation_notifications_v2 WHERE action_id=? AND proof_hash>? ORDER BY proof_hash LIMIT '.($limit+1),[$row['action_id'],$after]);
        $more=count($digests)>$limit;$digests=array_column(array_slice($digests,0,$limit),'proof_hash');
        return ['authorization'=>json_decode($row['authorization'],true,34,JSON_THROW_ON_ERROR),
            'publication'=>json_decode($publication['authorization'],true,34,JSON_THROW_ON_ERROR),
            'eventAuthorization'=>json_decode($publication['event_authorization'],true,34,JSON_THROW_ON_ERROR),
            'eventHeadHash'=>$publication['event_head_hash'],'eventCommandHash'=>$publication['event_command_hash'],
            'otherPublicationHash'=>$publication['other_publication_hash'],
            'putAuthorization'=>$includePut&&$row['kind']==='reminder'?json_decode($source['row']['put_authorization']??$source['row']['authorization'],true,34,JSON_THROW_ON_ERROR):null,
            'useAuthorization'=>$source['use']===null?null:json_decode($source['use']['authorization'],true,34,JSON_THROW_ON_ERROR),
            'digests'=>$digests,'hasMore'=>$more,'nextAfterHash'=>$digests?end($digests):$after];
    }

    /** Exact old owner may verify its own routing without parent READ. Other
     * owners' cards, original puts/uses and schedules are never returned. */
    public function own($p,$actor)
    {
        $this->fields($p,['scopeId','kind','id'],['afterHash','limit']);
        $scope=$this->uuid($p['scopeId']);$this->scope($scope,$actor['user']['id']);
        if(!in_array($p['kind'],['reminder','inbox'],true)||!is_string($p['id'])||strlen($p['id'])>36)throw new NativeError('validation_error');
        $row=$this->one("SELECT n.* FROM familyhub_crypto_project_relocation_notifications_v2 n JOIN familyhub_crypto_project_relocations_v2 r ON r.action_id=n.action_id WHERE r.state='committed' AND r.target_scope_id=? AND n.kind=? AND n.source_id=? AND n.account_id=?",[$scope,$p['kind'],$p['id'],$actor['user']['account_id']]);
        if(!$row||$row['authorization']===null)throw new NativeError('crypto_relocation_notification_pending',409);
        $routing=json_decode($row['routing'],true,34,JSON_THROW_ON_ERROR);
        $domain=NativeCryptoRecordAddressV2::domain($routing['targetType']);
        if($domain==='finance')(new NativeFinanceAccess($this->container))->policyForCrypto($scope,$actor['user'],false,true);
        $publication=$this->one("SELECT * FROM familyhub_crypto_project_relocation_publications_v2 WHERE action_id=? AND scope_id=? AND side='target'",[$row['action_id'],$scope]);
        if(!$publication)throw new NativeError('crypto_relocation_publication_pending',409);
        return $this->routeEvidence($row,$p,true);
    }
}
