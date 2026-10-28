<?php
if(PHP_SAPI!=='cli'){http_response_code(404);exit;}
function deliveryGuard():void{
 foreach(DELIVERY_FILES as $path=>$pin)if(is_link($path)||!is_file($path)||fileowner($path)!==fileowner(SITE)||(fileperms($path)&0777)!==$pin['mode']||(hash_file('sha256',$path)!==$pin['sha256']&&!(defined('CONFIG_ENABLED_SHA')&&$path===CONFIG&&hash_file('sha256',$path)===CONFIG_ENABLED_SHA)))stop('delivery_config_key_or_mode_changed');
 // Recompute only after config was required; maintenance.php loads it explicitly.
 $constants=[];foreach(get_defined_constants()as$k=>$v)if(str_starts_with($k,'FAMILYHUB_')&&is_scalar($v))$constants[$k]=$v;unset($constants['FAMILYHUB_ENABLE_CRYPTO_PREVIEW']);ksort($constants);
 if(hash('sha256',serialize($constants))!==DELIVERY_CONSTANTS_SHA)stop('smtp_fcm_constants_changed');
}
