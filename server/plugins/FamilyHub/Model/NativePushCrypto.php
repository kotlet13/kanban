<?php
namespace Kanboard\Plugin\FamilyHub\Model;

class NativePushCrypto
{
    public static function key()
    {
        $key = defined('FAMILYHUB_PUSH_KEY_BASE64') && is_string(FAMILYHUB_PUSH_KEY_BASE64) ? base64_decode(FAMILYHUB_PUSH_KEY_BASE64, true) : false;
        if ($key === false || strlen($key) !== 32 || !function_exists('openssl_encrypt')) { throw new NativeError('push_unavailable', 503); }
        return $key;
    }

    public static function encrypt($token, $aad)
    {
        $nonce = random_bytes(12); $tag = '';
        $cipher = openssl_encrypt($token, 'aes-256-gcm', self::key(), OPENSSL_RAW_DATA, $nonce, $tag, $aad, 16);
        if ($cipher === false) { throw new NativeError('push_unavailable', 503); }
        return base64_encode($nonce.$tag.$cipher);
    }

    public static function decrypt($cipher, $aad)
    {
        $raw = is_string($cipher) ? base64_decode($cipher, true) : false;
        if ($raw === false || strlen($raw) < 29) { throw new NativeError('push_unavailable', 503); }
        $token = openssl_decrypt(substr($raw, 28), 'aes-256-gcm', self::key(), OPENSSL_RAW_DATA, substr($raw, 0, 12), substr($raw, 12, 16), $aad);
        if ($token === false) { throw new NativeError('push_unavailable', 503); }
        return $token;
    }

    public static function aad($serverId, array $row)
    {
        return json_encode([$serverId, $row['account_id'], $row['device_id'], (int)$row['revision']], JSON_THROW_ON_ERROR);
    }
}
