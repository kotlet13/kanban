<?php
/** Runtime gate shared by read-only capture and migration helper; no keys retained. */
if(PHP_SAPI!=='cli'){http_response_code(404);exit;}
function cryptoRuntime():array{
 foreach(['sodium_memzero','sodium_crypto_sign_secretkey','sodium_crypto_sign_publickey','sodium_crypto_sign_keypair','sodium_crypto_sign_detached','sodium_crypto_sign_verify_detached','sodium_crypto_aead_xchacha20poly1305_ietf_encrypt','sodium_crypto_aead_xchacha20poly1305_ietf_decrypt','sodium_crypto_box_seal','sodium_crypto_generichash','sodium_crypto_pwhash','random_bytes','hash_hmac','json_encode','mb_strtolower']as$fn)if(!function_exists($fn))throw new RuntimeException('crypto_runtime_function_missing');
 if(!extension_loaded('sodium')||!extension_loaded('openssl')||!extension_loaded('curl')||PHP_VERSION_ID<80100||!in_array('mysql',PDO::getAvailableDrivers(),true))throw new RuntimeException('crypto_runtime_extension_missing');
 $pair=sodium_crypto_sign_keypair();$message=random_bytes(32);$signature=sodium_crypto_sign_detached($message,sodium_crypto_sign_secretkey($pair));if(!sodium_crypto_sign_verify_detached($signature,$message,sodium_crypto_sign_publickey($pair)))throw new RuntimeException('sodium_sign_roundtrip');
 $key=random_bytes(SODIUM_CRYPTO_AEAD_XCHACHA20POLY1305_IETF_KEYBYTES);$nonce=random_bytes(SODIUM_CRYPTO_AEAD_XCHACHA20POLY1305_IETF_NPUBBYTES);$cipher=sodium_crypto_aead_xchacha20poly1305_ietf_encrypt($message,'schema23-readiness',$nonce,$key);if(sodium_crypto_aead_xchacha20poly1305_ietf_decrypt($cipher,'schema23-readiness',$nonce,$key)!==$message)throw new RuntimeException('sodium_aead_roundtrip');sodium_memzero($key);
 return ['sodium'=>true,'signRoundtrip'=>true,'xchachaRoundtrip'=>true,'phpVersion'=>PHP_VERSION,'pdoMysql'=>true,'openssl'=>true,'curl'=>true,'mbstring'=>true];
}
