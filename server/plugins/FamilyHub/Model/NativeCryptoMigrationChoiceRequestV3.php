<?php
namespace Kanboard\Plugin\FamilyHub\Model;

/** Minimal, explicitly requested destination handoff in the existing scoped
 * context journal. A request is routing only; issuer derivation and target
 * manager endorsement remain mandatory. No private child row is returned. */
class NativeCryptoMigrationChoiceRequestV3 extends NativeDatabase
{
    protected $cryptoAccess=true;
    public const VARIANT='financeAccountChoicesRequest';
    private const PURPOSE='financeChoicesRequest';
    private function body($proof){[$b]=NativeCryptoCodec::decode($proof);return $b;}
    private function hash($v){return NativeCryptoV2Codec::hash((object)$v);}
    private function head($sid,$hash,$actor,$manager=false){
        $scope=$this->scope($sid,$actor['user']['id']);$scopes=new NativeCryptoScopeV2($this->container,$this->bearer,$this->ip);$h=$scopes->current($sid);
        if(!$h||$h['head_hash']!==$hash||(int)$h['epoch']!==1)throw new NativeError('crypto_account_choices_capture_target',409);
        if($manager)$scopes->manager($h,$scope,$actor);else $scopes->author($sid,$hash,1,(int)$scope['effective_access_revision'],$actor,'finance',false);
        return $h;
    }
    public function put($p,$actor,$proof,$resolve){
        $this->fields($p,['migrationId','captureId','sourceInventoryRoot','variant','scopeId','membershipHeadHash','sourceScopeId','binding']);
        if($p['variant']!==self::VARIANT)throw new NativeError('validation_error');
        $sid=$this->uuid($p['scopeId']);$parent=$this->uuid($p['sourceScopeId']);$this->head($sid,$p['membershipHeadHash'],$actor);
        $this->fields($p['binding'],['bindingId','scopeId','domain','sourceCommitment']);
        $source=$resolve($p['migrationId'],$p['captureId'],$p['binding']['bindingId'],$actor);
        if(NativeCryptoCodec::canonical((object)$source['binding'])!==NativeCryptoCodec::canonical((object)$p['binding'])||$source['context']['sourceTable']!=='familyhub_finance_records'||$source['context']['scopeId']!==$sid||$source['context']['domain']!=='finance')throw new NativeError('crypto_account_choices_capture_target',409);
        $cells=get_object_vars($source['typedRow']);$cell=$cells['payload']??null;
        if(!is_array($cell)||!array_key_exists('valueBase64',$cell)||!is_string($cell['valueBase64']))throw new NativeError('crypto_account_choices_capture_target',409);
        $bytes=base64_decode($cell['valueBase64'],true);if($bytes===false)throw new NativeError('crypto_account_choices_capture_target',409);
        $payload=json_decode($bytes,true,128,JSON_THROW_ON_ERROR);
        $scope=$this->one('SELECT parent_scope_id,organization_id FROM familyhub_scopes WHERE id=?',[$sid]);
        if(($payload['accountScopeId']??null)!==$parent||($scope['parent_scope_id']??$scope['organization_id']??null)!==$parent)throw new NativeError('crypto_account_choices_capture_target',409);
        $hash=$this->hash($proof);$old=$this->one('SELECT context_hash FROM familyhub_crypto_structure_contexts_v3 WHERE migration_id=? AND scope_id=? AND purpose=?',[$p['migrationId'],$sid,self::PURPOSE]);
        if($old&&$old['context_hash']!==$hash)throw new NativeError('crypto_account_choices_immutable_request',409);
        if(!$old)$this->change('INSERT INTO familyhub_crypto_structure_contexts_v3 VALUES(?,?,?,?,?,?)',[$p['migrationId'],$sid,self::PURPOSE,$hash,$hash,json_encode($proof,JSON_THROW_ON_ERROR)]);
        return ['requestHash'=>$hash];
    }
    public function read($p,$actor,$enumerate){
        $this->fields($p,['migrationId','captureId','sourceInventoryRoot','variant','scopeId','membershipHeadHash'],['afterScopeId','limit','targetRequest']);
        if($p['variant']!==self::VARIANT)throw new NativeError('validation_error');
        if(isset($p['targetRequest'])){
            if($p['targetRequest']!==true)throw new NativeError('validation_error');$sid=$this->uuid($p['scopeId']);$this->head($sid,$p['membershipHeadHash'],$actor,true);
            $row=$this->one('SELECT authorization FROM familyhub_crypto_structure_contexts_v3 WHERE migration_id=? AND scope_id=? AND purpose=?',[$p['migrationId'],$sid,self::PURPOSE]);
            return ['requests'=>$row?[json_decode($row['authorization'],true,64,JSON_THROW_ON_ERROR)]:[],'hasMore'=>false,'nextScopeId'=>$sid];
        }
        $sid=$this->uuid($p['scopeId']);$head=$this->head($sid,$p['membershipHeadHash'],$actor);
        $body=(new NativeCryptoScopeV2($this->container,$this->bearer,$this->ip))->body($head);$eligible=[];$owner=null;
        foreach($body['members'] as $member)if(in_array($member['financeRole'],['read','write'],true)){$eligible[]=$member['accountId'];if($member['role']==='owner')$owner=$member['accountId'];}
        sort($eligible,SORT_STRING);if(($owner??($eligible[0]??null))!==$actor['user']['account_id'])return ['requests'=>[],'hasMore'=>false,'nextScopeId'=>$p['afterScopeId']??''];
        // Empty source portions are selected by their immutable own prepare.
        $capture=$this->one('SELECT authorization FROM familyhub_crypto_captures_v3 WHERE migration_id=? AND account_id=? AND capture_id=? AND inventory_root=?',[$p['migrationId'],$actor['user']['account_id'],$p['captureId'],$p['sourceInventoryRoot']]);
        $selected=false;
        if($capture){$b=$this->body(json_decode($capture['authorization'],true,64,JSON_THROW_ON_ERROR));$selected=in_array($sid,$b['payload']['scopeIds'],true);foreach($b['payload']['receiptSelections'] as $selection)if($selection['scopeId']===$sid&&$selection['domain']==='finance')$selected=true;}
        if(!$selected)throw new NativeError('crypto_account_choices_capture_source',403);
        $after=$p['afterScopeId']??'';if($after!=='')$this->uuid($after);$limit=$p['limit']??20;if(!is_int($limit)||$limit<1||$limit>20)throw new NativeError('invalid_cursor');
        $rows=$this->many('SELECT scope_id,authorization FROM familyhub_crypto_structure_contexts_v3 WHERE migration_id=? AND purpose=? AND scope_id>? ORDER BY scope_id LIMIT '.($limit+1),[$p['migrationId'],self::PURPOSE,$after]);$out=[];
        foreach(array_slice($rows,0,$limit) as $r){$after=$r['scope_id'];$proof=json_decode($r['authorization'],true,64,JSON_THROW_ON_ERROR);$b=$this->body($proof);if(($b['payload']['sourceScopeId']??null)===$sid)$out[]=$proof;}
        return ['requests'=>$out,'hasMore'=>count($rows)>$limit,'nextScopeId'=>$after];
    }
}
