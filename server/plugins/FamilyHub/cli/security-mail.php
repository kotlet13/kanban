<?php
// Opt-in generic security notices. Never reads or sends recovery material.
if(PHP_SAPI!=='cli'){http_response_code(404);exit;}
require dirname(__DIR__,3).'/app/common.php';
if(session_status()===PHP_SESSION_ACTIVE){session_abort();}
try{echo json_encode((new \Kanboard\Plugin\FamilyHub\Model\NativeSecurityMailQueue($container))->run(isset($argv[1])?(int)$argv[1]:20),JSON_THROW_ON_ERROR).PHP_EOL;}
catch(\Throwable $ignored){fwrite(STDERR,"Security mail unavailable; no private details logged\n");exit(1);}
