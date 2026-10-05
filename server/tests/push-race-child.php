<?php
// Private synthetic fixture, no token/key in argv or output. Local tests only.
if (PHP_SAPI !== 'cli') { exit(2); }
$fixture=json_decode(file_get_contents($argv[1]),true,16,JSON_THROW_ON_ERROR);
define('FAMILYHUB_ENABLE_FCM',true);define('FAMILYHUB_FCM_PROJECT_ID','synthetic-fcm');
define('FAMILYHUB_PUBLIC_ROOT','/var/www');
define('FAMILYHUB_FCM_SERVICE_ACCOUNT_FILE',$fixture['credentialFile']);define('FAMILYHUB_PUSH_KEY_BASE64',$fixture['encryptionKey']);
require '/var/www/app/app/common.php';
if (!defined('FAMILYHUB_DEVELOPMENT_MODE') || FAMILYHUB_DEVELOPMENT_MODE !== true) { exit(2); }
if (session_status() === PHP_SESSION_ACTIVE) { session_abort(); }
echo "ready\n";flush();
if (trim(fgets(STDIN)) !== 'go') { exit(2); }
$result=(new \Kanboard\Plugin\FamilyHub\Model\NativePushService($container,'Bearer '.$fixture['bearer'],$fixture['ip']))->execute('push.register',['token'=>$fixture['newToken'],'platform'=>'android','language'=>'sl','expectedRevision'=>$fixture['expectedRevision']]);
echo json_encode(['registered'=>$result['registration']['registered'],'revision'=>$result['registration']['revision']],JSON_THROW_ON_ERROR)."\n";
