<?php
if(PHP_SAPI!=='cli'){http_response_code(404);exit;}
function enabledConfig(string $body):string{
 if(!str_starts_with($body,'<?php')||str_contains($body,'FAMILYHUB_ENABLE_CRYPTO_PREVIEW'))stop('original_config_crypto_guard');
 $out=substr_replace($body,"\n// Reviewed schema23 encrypted transport activation.\ndefine('FAMILYHUB_ENABLE_CRYPTO_PREVIEW', true);\n",5,0);token_get_all($out,TOKEN_PARSE);if(hash('sha256',$out)!==CONFIG_ENABLED_SHA)stop('enabled_config_pin');return $out;
}
function configHashAllowed():bool{return in_array(hash('sha256',bytes(CONFIG)),[CONFIG_SHA,CONFIG_ENABLED_SHA],true);}
function requireConfigGateMatches():void{
 $enabled=hash('sha256',bytes(CONFIG))===CONFIG_ENABLED_SHA;
 if($enabled!==((defined('FAMILYHUB_ENABLE_CRYPTO_PREVIEW')&&FAMILYHUB_ENABLE_CRYPTO_PREVIEW===true)))stop('crypto_gate_config_hash_mismatch');
}
