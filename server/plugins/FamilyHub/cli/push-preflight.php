<?php
// Offline only: parses configuration/signing key; makes no OAuth/FCM request.
if (PHP_SAPI !== 'cli') { http_response_code(404); exit; }
require dirname(__DIR__,3).'/app/common.php';
if (session_status() === PHP_SESSION_ACTIVE) { session_abort(); }
$configured=\Kanboard\Plugin\FamilyHub\Model\NativeFcmConfig::configured();
echo json_encode(['configured'=>$configured,'nativeEnabled'=>defined('FAMILYHUB_ENABLE_NATIVE_API') && FAMILYHUB_ENABLE_NATIVE_API===true,'providerVerified'=>false,'networkRequests'=>0],JSON_THROW_ON_ERROR)."\n";
exit($configured ? 0 : 1);
