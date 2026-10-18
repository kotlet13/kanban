<?php
namespace Kanboard\Plugin\FamilyHub\Model;

/** Same-transaction parent metadata successor for a newly activated child. */
class NativeCryptoFinanceTopologyCreationV3 extends NativeDatabase
{
    protected $cryptoAccess=true;

    public function install($child,$actor,$outer,$authorKey,$bundle)
    {
        if(!$this->transactionActive() || !$outer || !$authorKey) throw new NativeError('crypto_topology_activation_required',409);
        $parent=$child['parent_scope_id']??$child['organization_id']??null;
        if($parent===null || $child['kind']!=='project') throw new NativeError('crypto_topology_activation_context',409);
        $this->fields($bundle,['parentScopeId','childScopeId','authorization']);
        if($bundle['parentScopeId']!==$parent || $bundle['childScopeId']!==$child['id']) throw new NativeError('crypto_topology_activation_context',409);
        $scope=$this->scope($parent,$actor['user']['id'],true,true);
        $scopes=new NativeCryptoScopeV2($this->container,$this->bearer,$this->ip);
        $scopes->manager($scopes->current($parent),$scope,$actor);
        NativeCryptoScopeCreationV2::guardBusiness($this->pdo,$parent);
        [$command,$bytes,$signature]=NativeCryptoCodec::decode($bundle['authorization']);
        $this->fields($command,['version','operation','serverId','accountId','deviceId','requestId','signer','payload']);
        if($command['version']!==2 || $command['operation']!=='crypto2.records.batch' || $command['signer']!=='device') throw new NativeError('crypto_topology_activation_context',409);
        foreach(['serverId','accountId','deviceId'] as $key) if($command[$key]!==$outer[$key]) throw new NativeError('crypto_topology_activation_context',409);
        $this->uuid($command['requestId']);
        NativeCryptoV2Codec::verify($bytes,$signature,$authorKey);
        $payload=$command['payload'];
        $this->fields($payload,['batchId','records','commitment']);
        $records=(new NativeCryptoRecordProofV2($this->container))->parseBatch($payload,$command,$authorKey);
        if(count($records)!==1) throw new NativeError('crypto_topology_activation_context',409);
        $r=$records[0]['record'];
        if($r['scopeId']!==$parent || $r['domain']!=='content' || $r['type']!=='scopeMetadata' || $r['deleted'] || $r['expectedRevision']<1) throw new NativeError('crypto_topology_activation_context',409);
        $hash=hash('sha256',"JivieReservedRecord/v2\n".$outer['serverId'].':'.$parent.':scopeMetadata');
        $canonical=substr($hash,0,8).'-'.substr($hash,8,4).'-4'.substr($hash,13,3).'-a'.substr($hash,17,3).'-'.substr($hash,20,12);
        if(($r['metadata']['identity']['canonicalId']??null)!==$canonical) throw new NativeError('crypto_topology_activation_context',409);
        foreach(['migrationOrigin','inlineDeletion','projectRelocation'] as $tag) if(isset($r['metadata'][$tag])) throw new NativeError('crypto_topology_activation_context',409);
        // The ordinary installer verifies author, exact current parent head,
        // previous proof/CAS and every metadata/reference constraint. Its SQL
        // effects roll back with the child's activation on any later failure.
        return (new NativeCryptoStorageV2($this->container,$this->bearer,$this->ip))->write('crypto2.records.batch',$payload,$actor,$bundle['authorization'],$command,$authorKey);
    }
}
