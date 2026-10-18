<?php
namespace Kanboard\Plugin\FamilyHub\Model;

/** Closed purpose framing for atomic inline project deletion. Digests commit
 * encrypted signed records; no plaintext titles or monetary values occur here. */
class NativeCryptoInlineDeletionCodecV2
{
    const DOMAIN="JivieInlineDeletion/v2\n";
    const MAX_RECORDS=10000;
    public static function exact($v,$keys){NativeCryptoScopeDeletionCodecV2::fields($v,$keys);}
    public static function digest($v){NativeCryptoScopeDeletionCodecV2::digest($v);return $v;}
    public static function uuid($v){NativeCryptoScopeDeletionCodecV2::uuid($v);return $v;}
    public static function safe($v,$min=0,$max=9007199254740991){NativeCryptoScopeDeletionCodecV2::safe($v,$min,$max);}
    public static function hash($v){return hash('sha256',NativeCryptoCodec::canonical((object)$v));}
    public static function graphDescriptor($v)
    {
        self::exact($v,['scopeId','id','type','domain','revision','recordProofHash']);
        self::uuid($v['scopeId']);NativeCryptoRecordAddressV2::wireId($v['id']);
        if(NativeCryptoRecordAddressV2::domain($v['type'])!==$v['domain'])throw new NativeError('crypto_inline_delete_domain');
        self::safe($v['revision'],1);self::digest($v['recordProofHash']);
    }
    public static function graphRoot($descriptors)
    {
        $hash=hash_init('sha256');hash_update($hash,"JivieInlineDeletionGraph/v2\n");$previous=null;$count=0;
        foreach($descriptors as $d){self::graphDescriptor($d);if($previous!==null&&strcmp($previous,$d['id'])>=0)throw new NativeError('crypto_inline_delete_order');if(++$count>self::MAX_RECORDS)throw new NativeError('crypto_inline_delete_limit',409);$previous=$d['id'];hash_update($hash,NativeCryptoCodec::canonical((object)$d)."\n");}
        return ['root'=>hash_final($hash),'count'=>$count];
    }
    public static function tombstoneDescriptor($v)
    {
        self::exact($v,['id','domain','type','expectedRevision','previousRecordHash','recordProofHash','batchCommitmentHash']);
        NativeCryptoRecordAddressV2::wireId($v['id']);if(NativeCryptoRecordAddressV2::domain($v['type'])!==$v['domain'])throw new NativeError('crypto_inline_delete_domain');
        self::safe($v['expectedRevision'],1);foreach(['previousRecordHash','recordProofHash','batchCommitmentHash'] as $field)self::digest($v[$field]);
    }
    public static function tombstoneLeaf($descriptor)
    {
        self::tombstoneDescriptor($descriptor);return hash('sha256',"JivieInlineDeletionLeaf/v2\n".NativeCryptoCodec::canonical((object)$descriptor));
    }
    public static function tombstoneDigestRoot($digests)
    {
        $h=hash_init('sha256');hash_update($h,"JivieInlineDeletionTombstones/v2\n");$previous=null;$count=0;
        foreach($digests as $digest){self::digest($digest);if($previous!==null&&strcmp($previous,$digest)>=0)throw new NativeError('crypto_inline_delete_order');if(++$count>self::MAX_RECORDS)throw new NativeError('crypto_inline_delete_limit',409);$previous=$digest;hash_update($h,$digest."\n");}return ['root'=>hash_final($h),'count'=>$count];
    }
    public static function tombstoneRoot($descriptors)
    {
        $digests=[];$seen=[];foreach($descriptors as $d){if(isset($seen[$d['id']]))throw new NativeError('crypto_inline_delete_order');$seen[$d['id']]=true;$digests[]=self::tombstoneLeaf($d);}sort($digests,SORT_STRING);return self::tombstoneDigestRoot($digests);
    }
    public static function batchRoot($digests)
    {
        $h=hash_init('sha256');hash_update($h,"JivieInlineDeletionBatches/v2\n");$previous=null;$count=0;
        foreach($digests as $digest){self::digest($digest);if($previous!==null&&strcmp($previous,$digest)>=0)throw new NativeError('crypto_inline_delete_order');if(++$count>self::MAX_RECORDS)throw new NativeError('crypto_inline_delete_limit',409);$previous=$digest;hash_update($h,$digest."\n");}return ['root'=>hash_final($h),'count'=>$count];
    }
    public static function certificate($v)
    {
        self::exact($v,['version','serverId','scopeId','projectId','projectWireId','actionId','planHash','requestId','membershipHeadHash','accessRevision','lifecycleHash','graphRoot','graphCount','tombstoneRoot','tombstoneCount','batchRoot','batchCount','accountId','deviceId','authorDirectoryHeadHash']);
        if($v['version']!==2)throw new NativeError('crypto_inline_delete_version');
        foreach(['serverId','scopeId','projectId','actionId','requestId','accountId','deviceId'] as $field)self::uuid($v[$field]);NativeCryptoRecordAddressV2::wireId($v['projectWireId']);
        foreach(['planHash','membershipHeadHash','lifecycleHash','graphRoot','tombstoneRoot','batchRoot','authorDirectoryHeadHash'] as $field)self::digest($v[$field]);
        self::safe($v['accessRevision']);self::safe($v['graphCount'],1,self::MAX_RECORDS);self::safe($v['tombstoneCount'],1,self::MAX_RECORDS);self::safe($v['batchCount'],1,self::MAX_RECORDS);
        if($v['graphCount']!==$v['tombstoneCount']||$v['batchCount']>$v['tombstoneCount'])throw new NativeError('crypto_inline_delete_count');
    }
    public static function token($v)
    {
        return hash('sha256',"JivieInlineDeletionToken/v2\n".NativeCryptoCodec::canonical((object)['version'=>2,'serverId'=>$v['serverId'],'scopeId'=>$v['scopeId'],'projectWireId'=>$v['projectWireId'],'actionId'=>$v['actionId']]));
    }
}
