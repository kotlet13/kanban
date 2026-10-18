<?php
namespace Kanboard\Plugin\FamilyHub\Model;

/** Existing JivieReservedRecord/v2 identity, including its literal 'a'
 * variant nibble. Shared by purpose coordinators; this is not a new UUID. */
class NativeCryptoReservedRecordV2
{
    public static function derive($serverId,$scopeId,$namespace)
    {
        NativeCryptoRecordAddressV2::canonicalId($serverId);
        NativeCryptoRecordAddressV2::canonicalId($scopeId);
        if(!is_string($namespace)||strlen($namespace)<1||strlen($namespace)>160){
            throw new NativeError('validation_error');
        }
        $h=hash('sha256',"JivieReservedRecord/v2\n".$serverId.':'.$scopeId.':'.$namespace);
        return substr($h,0,8).'-'.substr($h,8,4).'-4'.substr($h,13,3).'-a'.substr($h,17,3).'-'.substr($h,20,12);
    }
}
