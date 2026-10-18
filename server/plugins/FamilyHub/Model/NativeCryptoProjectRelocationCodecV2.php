<?php
namespace Kanboard\Plugin\FamilyHub\Model;

/** Closed framing for the existing inline-project -> child conversion.
 * Private source/target correspondence never occurs in scoped publications.
 * All commitments cover signed encrypted proofs, not plaintext value hashes. */
class NativeCryptoProjectRelocationCodecV2
{
    const PUBLICATION_DOMAIN="JivieProjectRelocationPublication/v2\n";
    const MAX_RECORDS=10000;

    private static function exact($value,$fields)
    {
        NativeCryptoScopeDeletionCodecV2::fields($value,$fields);
    }
    public static function hash($value)
    {
        return hash('sha256',NativeCryptoCodec::canonical((object)$value));
    }
    public static function digest($value)
    {
        NativeCryptoScopeDeletionCodecV2::digest($value);
    }
    public static function uuid($value)
    {
        NativeCryptoScopeDeletionCodecV2::uuid($value);
    }
    public static function safe($value,$minimum=0,$maximum=9007199254740991)
    {
        NativeCryptoScopeDeletionCodecV2::safe($value,$minimum,$maximum);
    }
    public static function tag($value)
    {
        self::exact($value,['version','actionId','planHash','side']);
        if($value['version']!==2||!in_array($value['side'],['source','target'],true)){
            throw new NativeError('crypto_relocation_tag');
        }
        self::uuid($value['actionId']);self::digest($value['planHash']);
    }
    public static function sourceDescriptor($value)
    {
        self::exact($value,['id','wireId','type','domain','revision','logicalRevision','recordProofHash','deleted']);
        self::uuid($value['id']);NativeCryptoRecordAddressV2::wireId($value['wireId']);
        if(NativeCryptoRecordAddressV2::domain($value['type'])!==$value['domain']||!is_bool($value['deleted'])){
            throw new NativeError('crypto_relocation_domain');
        }
        self::safe($value['revision'],1);self::safe($value['logicalRevision']);self::digest($value['recordProofHash']);
    }
    public static function graphRoot($descriptors)
    {
        if(!is_array($descriptors)||!array_is_list($descriptors)||!$descriptors||count($descriptors)>self::MAX_RECORDS){
            throw new NativeError('crypto_relocation_capacity',409);
        }
        $last=null;$canonicalIds=[];
        foreach($descriptors as $descriptor){
            self::sourceDescriptor($descriptor);
            $canonicalKey=NativeCryptoRecordAddressV2::sourceKind($descriptor['type']).':'.$descriptor['id'];
            if($last!==null&&strcmp($last,$descriptor['wireId'])>=0||isset($canonicalIds[$canonicalKey])){
                throw new NativeError('crypto_relocation_order');
            }
            $last=$descriptor['wireId'];$canonicalIds[$canonicalKey]=true;
        }
        return self::hash(['domain'=>'JivieProjectRelocationGraph/v2','records'=>$descriptors]);
    }

    /** A private immutable proposal. It is never a child-reader response. */
    public static function plan($body)
    {
        self::exact($body,['version','serverId','actionId','requestId','accountId','deviceId','authorDirectoryHeadHash','sourceScopeId','targetScopeId','projectId','projectWireId','sourceHeadHash','sourceAccessRevision','sourceLifecycleHash','sourceGraphRoot','sourceGraphCount','sourceAuditRoot','sourceAuditCount','parentMetadataProofHash','parentTopologyGeneration','targetOwnerAccountId','targetParentScopeToken']);
        if($body['version']!==2||$body['targetScopeId']!==$body['projectId']||$body['sourceScopeId']===$body['targetScopeId']){
            throw new NativeError('crypto_relocation_plan');
        }
        foreach(['serverId','actionId','requestId','accountId','deviceId','sourceScopeId','targetScopeId','projectId','targetOwnerAccountId'] as $field)self::uuid($body[$field]);
        NativeCryptoRecordAddressV2::wireId($body['projectWireId']);
        foreach(['authorDirectoryHeadHash','sourceHeadHash','sourceLifecycleHash','sourceGraphRoot','sourceAuditRoot','parentMetadataProofHash','targetParentScopeToken'] as $field)self::digest($body[$field]);
        self::safe($body['sourceAccessRevision']);self::safe($body['sourceGraphCount'],1,self::MAX_RECORDS);
        self::safe($body['sourceAuditCount'],0,self::MAX_RECORDS);self::safe($body['parentTopologyGeneration'],0,9007199254740990);
    }

    /** One authorized scope's final proof. Counterpart coordinates remain
     * opaque even if a recipient has access to only the new child. */
    public static function publication($body)
    {
        self::exact($body,['version','serverId','scopeId','side','actionId','planHash','requestId','accountId','deviceId','authorDirectoryHeadHash','membershipHeadHash','proposalProofHash','activationProofHash','accessRevision','lifecycleHash','counterpartToken','recordRoot','recordCount','batchRoot','batchCount','auditRoot','auditCount','notificationRoot','notificationCount']);
        if($body['version']!==2||!in_array($body['side'],['source','target'],true))throw new NativeError('crypto_relocation_publication');
        foreach(['serverId','scopeId','actionId','requestId','accountId','deviceId'] as $field)self::uuid($body[$field]);
        foreach(['planHash','authorDirectoryHeadHash','membershipHeadHash','proposalProofHash','activationProofHash','lifecycleHash','counterpartToken','recordRoot','batchRoot','auditRoot','notificationRoot'] as $field)self::digest($body[$field]);
        self::safe($body['accessRevision']);self::safe($body['recordCount'],1,self::MAX_RECORDS+1);self::safe($body['batchCount'],1,self::MAX_RECORDS+1);
        self::safe($body['auditCount'],0,self::MAX_RECORDS*100);
        self::safe($body['notificationCount'],0,self::MAX_RECORDS*100);
        if($body['batchCount']>$body['recordCount'])throw new NativeError('crypto_relocation_count');
        if($body['side']==='source'&&$body['auditCount']!==0)throw new NativeError('crypto_relocation_count');
    }
    public static function recordLeaf($value)
    {
        self::exact($value,['id','type','domain','recordProofHash','logicalRevision']);
        NativeCryptoRecordAddressV2::wireId($value['id']);
        if(NativeCryptoRecordAddressV2::domain($value['type'])!==$value['domain'])throw new NativeError('crypto_relocation_domain');
        self::digest($value['recordProofHash']);self::safe($value['logicalRevision']);
        return hash('sha256',"JivieProjectRelocationRecord/v2\n".NativeCryptoCodec::canonical((object)$value));
    }
    public static function digestRoot($domain,$digests,$maximum=self::MAX_RECORDS+1)
    {
        if(!in_array($domain,['records','batches','audit','notifications'],true)||!is_array($digests)||!array_is_list($digests)||(!$digests&&!in_array($domain,['audit','notifications'],true))||count($digests)>$maximum){
            throw new NativeError('crypto_relocation_capacity');
        }
        $h=hash_init('sha256');hash_update($h,"JivieProjectRelocation/".$domain."/v2\n");$last=null;
        foreach($digests as $digest){
            self::digest($digest);
            if($last!==null&&strcmp($last,$digest)>=0)throw new NativeError('crypto_relocation_order');
            hash_update($h,$digest."\n");$last=$digest;
        }
        return hash_final($h);
    }
    public static function counterpartToken($server,$action,$scope,$other)
    {
        foreach([$server,$action,$scope,$other] as $id)self::uuid($id);
        return hash('sha256',"JivieProjectRelocationCounterpart/v2\n".NativeCryptoCodec::canonical((object)['version'=>2,'serverId'=>$server,'actionId'=>$action,'scopeId'=>$scope,'counterpartScopeId'=>$other]));
    }
    public static function publicationRoot($sourceHash,$targetHash)
    {
        self::digest($sourceHash);self::digest($targetHash);
        return hash('sha256',"JivieProjectRelocationPair/v2\n".NativeCryptoCodec::canonical((object)['version'=>2,'sourcePublicationHash'=>$sourceHash,'targetPublicationHash'=>$targetHash]));
    }
}
