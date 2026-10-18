<?php
namespace Kanboard\Plugin\FamilyHub\Model;

/** Opaque final receipt provenance. Caller verifies full inventories, signed
 * account inclusion and actual cold private bytes before using this codec. */
final class NativeCryptoMigrationReceiptV3
{
    private static function fields($v,$expected) {
        if (!is_array($v)) self::fail();
        $keys=array_keys($v);sort($keys);sort($expected);
        if ($keys!==$expected) self::fail();
    }
    private static function fail() { throw new NativeError('crypto_receipts_context',409); }
    private static function hashValue($v) { if (!is_string($v)||!preg_match('/^[a-f0-9]{64}$/D',$v)) self::fail(); }
    private static function countValue($v) { if (!is_int($v)||$v<0||$v>9007199254740991) self::fail(); }
    private static function id($v,$binding=false) { if (!is_string($v)||!preg_match($binding?'/^[a-f0-9]{8}-[a-f0-9]{4}-4[a-f0-9]{3}-[89ab][a-f0-9]{3}-[a-f0-9]{12}$/D':'/^[a-f0-9]{8}-[a-f0-9]{4}-[1-5][a-f0-9]{3}-[89ab][a-f0-9]{3}-[a-f0-9]{12}$/D',$v)) self::fail(); }
    public static function common($v) {
        self::fields($v,['version','serverId','migrationId','captureId','accountId','sourceInventoryRoot']);
        if ($v['version']!==3) self::fail();
        foreach (['serverId','migrationId','captureId','accountId'] as $k) self::id($v[$k]);
        self::hashValue($v['sourceInventoryRoot']);
    }
    public static function certificate($v) { self::fields($v,['certificateHash','manifestRoot','receiptCount']);self::hashValue($v['certificateHash']);self::hashValue($v['manifestRoot']);self::countValue($v['receiptCount']); }
    public static function local($v) { self::fields($v,['artifactId','cipherManifestHash','intentCount','ownEventCommandHash']);self::id($v['artifactId'],true);self::hashValue($v['cipherManifestHash']);self::hashValue($v['ownEventCommandHash']);self::countValue($v['intentCount']); }
    public static function artifact($bindingId,$sourceCommitment,$domain,$cert) {
        self::certificate($cert);self::id($bindingId,true);self::hashValue($sourceCommitment);
        if (!in_array($domain,['content','finance'],true)) self::fail();
        return hash('sha256',"JivieMigrationReceiptArtifact/v3\n".NativeCryptoCodec::canonical((object)['bindingId'=>$bindingId,'sourceCommitment'=>$sourceCommitment,'domain'=>$domain,'certificateHash'=>$cert['certificateHash'],'manifestRoot'=>$cert['manifestRoot']]));
    }
    public static function section($common,$content,$finance,$local) {
        self::common($common);self::certificate($content);self::certificate($finance);self::local($local);
        $count=$content['receiptCount']+$finance['receiptCount']+$local['intentCount'];self::countValue($count);
        return ['kind'=>'receipts','count'=>$count,'root'=>hash('sha256',"JivieMigrationReceipts/v3\n".NativeCryptoCodec::canonical((object)$common)."\n".NativeCryptoCodec::canonical((object)['content'=>$content,'finance'=>$finance,'localIntents'=>$local])."\n")];
    }
}
