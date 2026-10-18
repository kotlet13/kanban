<?php
namespace Kanboard\Plugin\FamilyHub\Model;

/** Exact closed scoped-deletion signature framing, shared with Dart. */
class NativeCryptoScopeDeletionCodecV2
{
    const CERTIFICATE="JivieScopeDeletion/v2\n";
    const HEADER="JivieScopeDeletionHeader/v2\n";
    const LEAF="JivieScopeDeletionLeaf/v2\n";
    const MAX_SCOPES=100;
    public static function fields($v,$keys){if(!is_array($v)||count($v)!==count($keys)||array_diff($keys,array_keys($v))){throw new NativeError('crypto_scope_deletion_shape');}}
    public static function uuid($v){if(!is_string($v)||!preg_match('/^[a-f0-9]{8}-[a-f0-9]{4}-[1-5][a-f0-9]{3}-[89ab][a-f0-9]{3}-[a-f0-9]{12}$/D',$v)){throw new NativeError('crypto_scope_deletion_context');}}
    public static function digest($v){if(!is_string($v)||!preg_match('/^[a-f0-9]{64}$/D',$v)){throw new NativeError('crypto_scope_deletion_context');}}
    public static function safe($v,$min=0,$max=9007199254740991){if(!is_int($v)||$v<$min||$v>$max){throw new NativeError('crypto_scope_deletion_count');}}
    public static function retention(){return ['version'=>1,'retainsSignedEvidence'=>true,'mayRetainEncryptedHistoricalBackups'=>true,'mayRetainLegacyMigrationSources'=>true,'erasesOtherKeyCopies'=>false];}
    public static function retained($v){self::fields($v,array_keys(self::retention()));foreach(self::retention() as $k=>$x){if($v[$k]!==$x){throw new NativeError('crypto_scope_deletion_retention');}}}
    public static function scope($v){self::fields($v,['scopeId','headHash','accessRevision','lifecycleHash']);self::uuid($v['scopeId']);self::digest($v['headHash']);self::digest($v['lifecycleHash']);self::safe($v['accessRevision']);}
    public static function certificate($v){
        self::fields($v,array_merge(['version','serverId','rootScopeId','requestId','actorAccountId','actorDeviceId','scopes','graphRoot','graphCount','retention'],array_key_exists('parentTopologyHash',$v)?['parentTopologyHash']:[]));
        if(array_key_exists('parentTopologyHash',$v))self::digest($v['parentTopologyHash']);
        if($v['version']!==2){throw new NativeError('crypto_scope_deletion_version');}
        foreach(['serverId','rootScopeId','requestId','actorAccountId','actorDeviceId'] as $k){self::uuid($v[$k]);}
        self::digest($v['graphRoot']);self::safe($v['graphCount'],1,self::MAX_SCOPES);self::retained($v['retention']);
        if(!is_array($v['scopes'])||!array_is_list($v['scopes'])||count($v['scopes'])!==$v['graphCount']){throw new NativeError('crypto_scope_deletion_count');}
        $previous=null;$root=false;foreach($v['scopes'] as $scope){self::scope($scope);if($previous!==null&&strcmp($previous,$scope['scopeId'])>=0){throw new NativeError('crypto_scope_deletion_order');}$previous=$scope['scopeId'];$root=$root||$scope['scopeId']===$v['rootScopeId'];}
        if(!$root){throw new NativeError('crypto_scope_deletion_context');}return $v;
    }
    public static function header($v){
        self::fields($v,array_merge(['version','serverId','requestId','actorAccountId','actorDeviceId','authorDirectoryHeadHash','privateCertificateHash','rootToken','graphRoot','graphCount','retention','scopeLeafRoot','scopeLeafCount'],array_key_exists('parentTopologyHash',$v)?['parentTopologyHash']:[]));
        if(array_key_exists('parentTopologyHash',$v))self::digest($v['parentTopologyHash']);
        if($v['version']!==2){throw new NativeError('crypto_scope_deletion_version');}
        foreach(['serverId','requestId','actorAccountId','actorDeviceId'] as $k){self::uuid($v[$k]);}
        foreach(['authorDirectoryHeadHash','privateCertificateHash','rootToken','graphRoot','scopeLeafRoot'] as $k){self::digest($v[$k]);}
        self::safe($v['graphCount'],1,self::MAX_SCOPES);self::retained($v['retention']);
        if($v['scopeLeafCount']!==$v['graphCount']){throw new NativeError('crypto_scope_deletion_count');}return $v;
    }
    public static function leaf($v){self::fields($v,['version','serverId','requestId','headerContextHash','scopeId','headHash','accessRevision','lifecycleHash']);if($v['version']!==2){throw new NativeError('crypto_scope_deletion_version');}self::uuid($v['serverId']);self::uuid($v['requestId']);self::digest($v['headerContextHash']);self::scope(array_intersect_key($v,array_flip(['scopeId','headHash','accessRevision','lifecycleHash'])));return $v;}
    public static function hash($proof){return NativeCryptoV2Codec::hash((object)$proof);}
    public static function rootToken($c){self::certificate($c);return hash('sha256',"JivieScopeDeletionRootToken/v2\n".NativeCryptoCodec::canonical((object)['version'=>2,'serverId'=>$c['serverId'],'requestId'=>$c['requestId'],'rootScopeId'=>$c['rootScopeId']]));}
    public static function headerContext($h){self::header($h);unset($h['scopeLeafRoot'],$h['scopeLeafCount']);return hash('sha256',"JivieScopeDeletionHeaderContext/v2\n".NativeCryptoCodec::canonical((object)$h));}
    public static function leafRoot($h,$hashes){self::header($h);if(!is_array($hashes)||count($hashes)!==$h['scopeLeafCount']){throw new NativeError('crypto_scope_deletion_count');}$previous=null;foreach($hashes as $hash){self::digest($hash);if($previous!==null&&strcmp($previous,$hash)>=0){throw new NativeError('crypto_scope_deletion_order');}$previous=$hash;}return hash('sha256',"JivieScopeDeletionLeaves/v2\n".implode("\n",$hashes)."\n");}
}
