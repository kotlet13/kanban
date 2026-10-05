<?php
namespace Kanboard\Plugin\FamilyHub\Model;

class NativeFcmConfig
{
    public static function credentials()
    {
        if (!defined('FAMILYHUB_ENABLE_FCM') || FAMILYHUB_ENABLE_FCM !== true || !defined('FAMILYHUB_FCM_SERVICE_ACCOUNT_FILE') || !is_string(FAMILYHUB_FCM_SERVICE_ACCOUNT_FILE) || !function_exists('curl_init')) {
            throw new NativeError('push_unavailable', 503);
        }
        NativePushCrypto::key();
        $publicRoot=defined('FAMILYHUB_PUBLIC_ROOT') && is_string(FAMILYHUB_PUBLIC_ROOT) ? realpath(FAMILYHUB_PUBLIC_ROOT) : false;
        if (!$publicRoot || !is_dir($publicRoot)) { throw new NativeError('push_unavailable',503); }
        $file = realpath(FAMILYHUB_FCM_SERVICE_ACCOUNT_FILE);
        if (!$file || !is_file($file) || !is_readable($file) || filesize($file) > 65536) { throw new NativeError('push_unavailable', 503); }
        foreach ([$publicRoot,defined('ROOT_DIR') ? ROOT_DIR : dirname(__DIR__, 4), $_SERVER['DOCUMENT_ROOT'] ?? ''] as $root) {
            $root = $root ? realpath($root) : false;
            if ($root && ($file === $root || str_starts_with($file, $root.DIRECTORY_SEPARATOR))) { throw new NativeError('push_unavailable', 503); }
        }
        $json = json_decode(file_get_contents($file), true, 16, JSON_THROW_ON_ERROR);
        if (!is_array($json) || ($json['type'] ?? null) !== 'service_account' || !is_string($json['project_id'] ?? null) || !preg_match('/^[a-z][a-z0-9-]{4,28}[a-z0-9]$/D', $json['project_id']) || !defined('FAMILYHUB_FCM_PROJECT_ID') || FAMILYHUB_FCM_PROJECT_ID !== $json['project_id'] || !is_string($json['client_email'] ?? null) || !preg_match('/^[a-zA-Z0-9._-]+@[a-zA-Z0-9.-]+\.gserviceaccount\.com$/D', $json['client_email']) || ($json['token_uri'] ?? null) !== 'https://oauth2.googleapis.com/token' || !is_string($json['private_key'] ?? null)) {
            throw new NativeError('push_unavailable', 503);
        }
        $key = @openssl_pkey_get_private($json['private_key']);
        $details = $key ? openssl_pkey_get_details($key) : false;
        if (!$details || $details['type'] !== OPENSSL_KEYTYPE_RSA || $details['bits'] < 2048) { throw new NativeError('push_unavailable', 503); }
        return $json;
    }

    public static function configured()
    {
        try { self::credentials(); return true; }
        catch (\Throwable $error) { return false; }
    }
}
