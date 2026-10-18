<?php

namespace Kanboard\Plugin\FamilyHub\Model;

/** RFC8032 Ed25519 signatures over bounded, immutable canonical command bytes. */
class NativeCryptoCodec
{
    public const DOMAIN = "JivieE2EE/v1\n";
    // Nested base64 command stays below the unchanged 1 MiB HTTP input bound.
    public const MAX_COMMAND = 524288;
    public static function available()
    {
        return function_exists('sodium_crypto_sign_verify_detached');
    }
    public static function base64($value, $max, $size = null)
    {
        if (!is_string($value) || strlen($value) > 4 * (int)ceil($max / 3)) {
            throw new NativeError('crypto_invalid_envelope');
        }
        $bytes = base64_decode($value, true);
        if ($bytes === false || strlen($bytes) > $max || base64_encode($bytes) !== $value || ($size !== null && strlen($bytes) !== $size)) {
            throw new NativeError('crypto_invalid_envelope');
        }
        return $bytes;
    }
    public static function canonical($value, $depth = 0)
    {
        if ($depth > 32) {
            throw new NativeError('crypto_invalid_envelope');
        }
        if (is_float($value) || is_int($value) && abs($value) > 9007199254740991) {
            throw new NativeError('crypto_invalid_envelope');
        }
        if (is_object($value)) {
            $fields = get_object_vars($value);
            ksort($fields, SORT_STRING);
            $out = new \stdClass();
            foreach ($fields as $key => $part) {
                if (!preg_match('/^[A-Za-z][A-Za-z0-9_]{0,79}$/D', $key)) {
                    throw new NativeError('crypto_invalid_envelope');
                }$out->$key = json_decode(self::canonical($part, $depth + 1), false, 34, JSON_THROW_ON_ERROR);
            }
            $value = $out;
        } elseif (is_array($value)) {
            if (!array_is_list($value)) {
                return self::canonical((object)$value, $depth);
            }
            foreach ($value as &$part) {
                $part = json_decode(self::canonical($part, $depth + 1), false, 34, JSON_THROW_ON_ERROR);
            }unset($part);
        } elseif (!is_string($value) && !is_bool($value) && !is_int($value) && $value !== null) {
            throw new NativeError('crypto_invalid_envelope');
        }
        return json_encode($value, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_LINE_TERMINATORS | JSON_THROW_ON_ERROR);
    }
    public static function decode($params)
    {
        if (array_keys($params) !== ['commandBase64','signatureBase64'] && array_keys($params) !== ['signatureBase64','commandBase64']) {
            throw new NativeError('crypto_invalid_envelope');
        }
        try {
            $bytes = self::base64($params['commandBase64'], self::MAX_COMMAND);
            $signature = self::base64($params['signatureBase64'], 64, 64);
            $object = json_decode($bytes, false, 34, JSON_THROW_ON_ERROR);
            if (!is_object($object) || self::canonical($object) !== $bytes) {
                throw new NativeError('crypto_invalid_envelope');
            }
            $command = json_decode($bytes, true, 34, JSON_THROW_ON_ERROR);
        } catch (NativeError $e) {
            throw $e;
        } catch (\Throwable $ignored) {
            throw new NativeError('crypto_invalid_envelope');
        }
        return [$command,$bytes,$signature,hash('sha256', $bytes)];
    }
    public static function verify($bytes, $signature, $key)
    {
        if (!self::available()) {
            throw new NativeError('crypto_unavailable', 503);
        }
        $public = self::base64($key, 32, 32);
        if (!sodium_crypto_sign_verify_detached($signature, self::DOMAIN.$bytes, $public)) {
            throw new NativeError('crypto_signature_invalid', 403);
        }
    }
}
