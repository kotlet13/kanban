<?php
namespace Kanboard\Plugin\FamilyHub\Model;

/** Closed scoped activation framing. Authority/signatures/inclusion are separate. */
final class NativeCryptoMigrationActivationV3
{
    public const FIELDS=['version','serverId','migrationId','componentId','componentCommitment','inventoryCommitment','scopeId','membershipHeadHash','lifecycleHash','managerAccountId','managerDirectoryHeadHash','contentCertificateHash','financeCertificateHash','controlCount','controlRoot'];
    public const CONTROL_FIELDS=['version','scopeId','kind','portionToken','captureId','sourceInventoryRoot','verify3ProofHash','selectionCount','selectionRoot','certificateHash','eventCommandHash'];
    public static function validate($h)
    {
        self::fields($h,self::FIELDS);
        foreach(['serverId','migrationId','componentId','scopeId','managerAccountId'] as $k)self::uuid($h[$k]);
        foreach(['componentCommitment','inventoryCommitment','membershipHeadHash','lifecycleHash','managerDirectoryHeadHash','contentCertificateHash','financeCertificateHash','controlRoot'] as $k)self::digest($h[$k]);
        if($h['version']!==3||!is_int($h['controlCount'])||$h['controlCount']<5||$h['controlCount']>5000)self::fail();
    }
    public static function controlHash($v)
    {
        self::fields($v,self::CONTROL_FIELDS);self::uuid($v['scopeId']);self::uuid($v['captureId']);
        foreach(['portionToken','sourceInventoryRoot','verify3ProofHash','selectionRoot'] as $k)self::digest($v[$k]);
        if($v['version']!==3||!in_array($v['kind'],['audit','invitations','notifications','receipts','structure'],true)||!is_int($v['selectionCount'])||$v['selectionCount']<0||$v['selectionCount']>9007199254740991)self::fail();
        if(in_array($v['kind'],['notifications','invitations'],true)){self::digest($v['certificateHash']);self::digest($v['eventCommandHash']);}
        elseif($v['certificateHash']!==null||$v['eventCommandHash']!==null)self::fail();
        return hash('sha256',"JivieMigrationControl/v3\n".self::canonical($v));
    }
    public static function controlRoot($h,iterable $hashes)
    {
        self::validate($h);$context=$h;unset($context['controlRoot']);
        $sink=hash_init('sha256');hash_update($sink,"JivieMigrationControls/v3\n".self::canonical($context)."\n");$previous=null;$count=0;
        foreach($hashes as $hash){self::digest($hash);if($previous!==null&&strcmp($previous,$hash)>=0||++$count>$h['controlCount'])self::fail();$previous=$hash;hash_update($sink,$hash."\n");}
        if($count!==$h['controlCount'])self::fail();return hash_final($sink);
    }
    public static function token($h)
    {
        self::validate($h);return hash('sha256',"JivieMigrationActivationToken/v3\n".self::canonical(array_intersect_key($h,array_flip(['version','serverId','migrationId','scopeId','componentCommitment']))));
    }
    private static function canonical($v){return NativeCryptoCodec::canonical((object)$v);}
    private static function fields($v,$keys){if(!is_array($v)||count($v)!==count($keys)||array_diff(array_keys($v),$keys))self::fail();}
    private static function uuid($v){if(!is_string($v)||!preg_match('/^[a-f0-9]{8}-[a-f0-9]{4}-[1-5][a-f0-9]{3}-[89ab][a-f0-9]{3}-[a-f0-9]{12}$/D',$v))self::fail();}
    private static function digest($v){if(!is_string($v)||!preg_match('/^[a-f0-9]{64}$/D',$v))self::fail();}
    private static function fail(){throw new NativeError('crypto_migration_activation_context',409);}
}
