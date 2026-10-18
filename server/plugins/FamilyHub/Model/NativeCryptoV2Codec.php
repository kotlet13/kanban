<?php

namespace Kanboard\Plugin\FamilyHub\Model;

/** Versioned domains keep immutable preview-v1 proofs out of the v2 protocol. */
class NativeCryptoV2Codec extends NativeCryptoCodec
{
    public const DOMAIN = "JivieE2EE/v2\n";
    public const RECORD_DOMAIN = "JivieE2EE/record/v2\n";
    public const BATCH_DOMAIN = "JivieE2EE/batch/v2\n";
    public static function verify($bytes, $signature, $key, $domain = self::DOMAIN)
    {
        if (!parent::available()) {
            throw new NativeError('crypto_unavailable', 503);
        }
        $public = parent::base64($key, 32, 32);
        if (!sodium_crypto_sign_verify_detached($signature, $domain.$bytes, $public)) {
            throw new NativeError('crypto_signature_invalid', 403);
        }
    }
    public static function hash($value)
    {
        return hash('sha256', parent::canonical(is_array($value) && !array_is_list($value) ? (object)$value : $value));
    }
    public static function head($command, $proof, $generation)
    {
        $bytes = parent::base64($proof['commandBase64'], parent::MAX_COMMAND);
        return hash('sha256', "JivieAccountLog/v2\n".parent::canonical((object)['serverId' => $command['serverId'],'accountId' => $command['accountId'],'generation' => $generation,'previousHeadHash' => $command['payload']['previousHeadHash'],'commandHash' => hash('sha256', $bytes),'signatureBase64' => $proof['signatureBase64']]));
    }
}
