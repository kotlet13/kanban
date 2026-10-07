<?php
// Guarded deployment ONLY for the new jivie-test.triparna.si installation.
// Run with /opt/alt/php84/usr/bin/php; never via HTTP. No accounts/keys created.
// --prepare copies data, backs up config and stages plugin/config privately.
// Then php -l the staged config BEFORE --activate. Root controls maintenance.
if (PHP_SAPI !== 'cli') { http_response_code(404); exit; }
ini_set('display_errors', '0'); ini_set('log_errors', '0'); error_reporting(0);
final class DeployGuard extends RuntimeException {}
function stop(string $code): never { throw new DeployGuard($code); }
set_error_handler(static function (): never { stop('filesystem_or_php_warning'); });
const SITE = '/home/tripar13/jivie-test.triparna.si';
const PRIVATE_SITE = '/home/tripar13/private/jivie-test';
const INSTALL = PRIVATE_SITE.'/install';
const ZIP_FILE = INSTALL.'/FamilyHub-0.6.0-source.zip';
const ZIP_SHA256 = '433d45fbb8c7aa350e92beab812a7b9e7ffc1ed07bdae5d003fa1fce4e9624c0';
const DATA_TARGET = PRIVATE_SITE.'/data';
const WORK = INSTALL.'/familyhub-deploy';
const STATE = WORK.'/state.json';
const BACKUP = WORK.'/config.before.php';
const CANDIDATE = WORK.'/config.candidate.php';
const FEATURE_CONFIG = PRIVATE_SITE.'/familyhub-config.php';
const FEATURE_TEXT = "<?php\ndefine('FAMILYHUB_ENABLE_NATIVE_API', true);\ndefine('FAMILYHUB_ACCOUNT_MODE', 'self_hosted');\ndefine('FAMILYHUB_ENABLE_PROJECT_INVITATIONS', false);\ndefine('FAMILYHUB_ENABLE_FCM', false);\ndefine('FAMILYHUB_TRUSTED_PROXY_IPS', []);\ndefine('FAMILYHUB_CORS_ORIGINS', []);\n";
const PLUGIN_FILES = ["Api/IdentityMiddleware.php", "Controller/AccountDeletionController.php", "Controller/EnrollmentController.php", "Controller/NativeApiController.php", "LICENSE", "Model/InvitationService.php", "Model/NativeAccountDeletionService.php", "Model/NativeAccountMailCrypto.php", "Model/NativeAccountMailQueue.php", "Model/NativeAccountMailTransport.php", "Model/NativeAccountService.php", "Model/NativeAccountTokens.php", "Model/NativeAuthService.php", "Model/NativeDatabase.php", "Model/NativeDeletionPlan.php", "Model/NativeDeliveryService.php", "Model/NativeEnrollmentService.php", "Model/NativeError.php", "Model/NativeFcmConfig.php", "Model/NativeFcmTransport.php", "Model/NativeFinanceAccess.php", "Model/NativeFinancePolicy.php", "Model/NativeFinanceService.php", "Model/NativeFinanceSettings.php", "Model/NativeInboxGroup.php", "Model/NativeInboxService.php", "Model/NativeInvitationService.php", "Model/NativeNotificationWriter.php", "Model/NativePasswordResetService.php", "Model/NativePersonalService.php", "Model/NativePushCrypto.php", "Model/NativePushQueue.php", "Model/NativePushService.php", "Model/NativePushWorker.php", "Model/NativeRecordPolicy.php", "Model/NativeReminderService.php", "Model/NativeScopeService.php", "Model/NativeService.php", "Model/NativeSmtpTransport.php", "Model/NativeSyncService.php", "Model/NativeVerifiedSmtp.php", "Plugin.php", "README.md", "Schema/AccountDeletionSchema.php", "Schema/AccountSchema.php", "Schema/CollaborationSchema.php", "Schema/Mysql.php", "Schema/NativeSchema.php", "Schema/PushSchema.php", "Schema/Sqlite.php", "Template/account_deletion/index.php", "Template/enrollment/index.php", "Template/enrollment/sidebar.php", "cli/account-deletion-cleanup.php", "cli/account-mail.php", "cli/delivery.php", "cli/enrollment.php", "cli/push-preflight.php", "cli/push.php", "cli/reminders.php", "docs/account-deletion-contract.md"];

function directory(string $path): void {
    if (is_link($path) || !is_dir($path) || realpath($path) !== $path) stop('directory_guard_failed');
}
function newDirectory(string $path): void {
    if (file_exists($path) || is_link($path)) stop('destination_already_exists');
    if (!mkdir($path, 0700)) stop('mkdir_failed');
    chmod($path, 0700);
}
function bytes(string $path): string {
    if (is_link($path) || !is_file($path) || !is_readable($path)) stop('file_guard_failed');
    $data=file_get_contents($path); if ($data===false) stop('file_read_failed'); return $data;
}
function writeNew(string $path, string $text, int $mode=0600): void {
    $handle=fopen($path,'xb'); if ($handle===false) stop('exclusive_file_create_failed');
    try { if (fwrite($handle,$text)!==strlen($text) || !fflush($handle)) stop('file_write_failed'); }
    finally { fclose($handle); }
    chmod($path,$mode);
}
function inventory(string $path): array {
    directory($path); $items=[];
    $iterator=new RecursiveIteratorIterator(new RecursiveDirectoryIterator($path,FilesystemIterator::SKIP_DOTS));
    foreach($iterator as $file) {
        if ($file->isLink() || !$file->isFile()) stop('source_tree_contains_unsupported_entry');
        $relative=substr($file->getPathname(),strlen($path)+1);
        $items[$relative]=hash('sha256',bytes($file->getPathname()));
    }
    ksort($items);return $items;
}
function copyTree(string $source,string $destination): void {
    directory($source);newDirectory($destination);
    foreach(new DirectoryIterator($source) as $file) {
        if ($file->isDot()) continue;
        if ($file->isLink()) stop('data_symlink_rejected');
        $from=$file->getPathname();$to=$destination.'/'.$file->getFilename();
        if ($file->isDir()) copyTree($from,$to);
        elseif($file->isFile()) writeNew($to,bytes($from));
        else stop('data_entry_rejected');
    }
}
function readState(): array { $s=json_decode(bytes(STATE),true,32,JSON_THROW_ON_ERROR);if (!is_array($s)) stop('state_invalid');return $s; }
function featureCheck(): void {
    if (!hash_equals(hash('sha256',FEATURE_TEXT),hash('sha256',bytes(FEATURE_CONFIG)))) stop('feature_config_changed');
}
function zipContents(): array {
    if (!class_exists(ZipArchive::class)) stop('zip_extension_required');
    if (!hash_equals(ZIP_SHA256,hash('sha256',bytes(ZIP_FILE)))) stop('zip_checksum_mismatch');
    $zip=new ZipArchive();if ($zip->open(ZIP_FILE,ZipArchive::RDONLY)!==true) stop('zip_open_failed');
    try {
        if($zip->numFiles!==count(PLUGIN_FILES)) stop('zip_entry_count_mismatch');
        $result=[];
        for($i=0;$i<$zip->numFiles;$i++) {
            $stat=$zip->statIndex($i);$name=$stat['name']??'';
            if (!str_starts_with($name,'FamilyHub/')) stop('zip_prefix_rejected');
            $relative=substr($name,10);
            if (!in_array($relative,PLUGIN_FILES,true) || isset($result[$relative])) stop('zip_entry_rejected');
            $zip->getExternalAttributesIndex($i,$opsys,$attributes);
            if (($attributes>>16 & 0170000)===0120000) stop('zip_symlink_rejected');
            $text=$zip->getFromIndex($i);if ($text===false || strlen($text)!==($stat['size']??-1)) stop('zip_entry_read_failed');
            if (hash('crc32b',$text)!==sprintf('%08x',$stat['crc'])) stop('zip_crc_mismatch');
            $result[$relative]=$text;
        }
        ksort($result);return $result;
    } finally { $zip->close(); }
}
function expectedPlugin(array $entries): array { $out=[];foreach($entries as $name=>$text)$out[$name]=hash('sha256',$text);ksort($out);return $out; }
function validateConfig(string $text): void {
    // Parses without evaluating database credentials, requires or other code.
    if (!function_exists("token_get_all")) stop("tokenizer_extension_required");
    token_get_all($text,TOKEN_PARSE);
}
function configScan(string $text): string {
    validateConfig($text); $scan='';
    foreach (token_get_all($text) as $token) {
        // Keep original byte offsets while excluding commented sample defines.
        $scan.=is_array($token) && in_array($token[0],[T_COMMENT,T_DOC_COMMENT],true)
            ? preg_replace('/[^\r\n]/',' ',$token[1])
            : (is_array($token) ? $token[1] : $token);
    }
    return $scan;
}
function originalConfig(): string {
    $config=bytes(SITE.'/config.php'); $scan=configScan($config);
    if (file_exists(SITE.'/data/config.php')) stop('secondary_data_config_requires_review');
    if (str_contains($scan,'FAMILYHUB_') || str_contains($scan,FEATURE_CONFIG)) stop('existing_familyhub_configuration_requires_review');
    if (preg_match('~define\s*\(\s*([\'\"])DB_DRIVER\1\s*,\s*([\'\"])mysql\2\s*\)~',$scan)!==1 ||
        preg_match('~define\s*\(\s*([\'\"])DB_NAME\1\s*,\s*([\'\"])tripar13_jivietest\2\s*\)~',$scan)!==1) stop('fresh_database_identity_guard_failed');
    if (preg_match_all('~define\s*\(\s*([\'\"])DATA_DIR\1\s*,~',$scan)!==1) stop('data_dir_definition_count_mismatch');
    // Only these observed relative expressions may follow the relocated DATA_DIR.
    foreach (['FILES_DIR'=>'files','CACHE_DIR'=>'cache','LOG_FILE'=>'debug.log','DB_FILENAME'=>null] as $constant=>$suffix) {
        $count=preg_match_all('~define\s*\(\s*([\'\"])'.$constant.'\1\s*,~',$scan);
        if ($count===0) continue;
        if ($count!==1 || $suffix===null || preg_match('~define\s*\(\s*([\'\"])'.$constant.'\1\s*,\s*DATA_DIR\s*\.\s*DIRECTORY_SEPARATOR\s*\.\s*([\'\"])'.preg_quote($suffix,'~').'\2\s*\)\s*;~',$scan)!==1) stop('explicit_data_path_requires_review');
    }
    return $config;
}
function preparedCheck(array $state,array $entries): void {
    if (($state['version']??null)!==1 || ($state['zipSha256']??'')!==ZIP_SHA256 || ($state['phase']??'')!=='prepared') stop('prepared_state_invalid');
    if (hash('sha256',bytes(SITE.'/config.php'))!==$state['originalConfigSha256'] || hash('sha256',bytes(BACKUP))!==$state['originalConfigSha256']) stop('original_config_changed');
    if (hash('sha256',bytes(CANDIDATE))!==$state['candidateConfigSha256']) stop('candidate_config_changed');
    validateConfig(bytes(CANDIDATE));featureCheck();
    if (inventory(SITE.'/data')!==$state['dataInventory'] || inventory(DATA_TARGET)!==$state['dataInventory']) stop('data_changed_since_prepare');
    if (inventory(WORK.'/FamilyHub')!==expectedPlugin($entries)) stop('staged_plugin_changed');
    if (file_exists(SITE.'/plugins/FamilyHub') || is_link(SITE.'/plugins/FamilyHub')) stop('live_plugin_already_exists');
}
try {
    umask(0077);
    if ($argc!==2 || !in_array($argv[1],['--check','--prepare','--activate'],true)) stop('usage_check_prepare_or_activate');
    directory('/home/tripar13');directory('/home/tripar13/private');directory(PRIVATE_SITE);directory(INSTALL);
    foreach (['/home/tripar13/private',PRIVATE_SITE,INSTALL] as $privatePath) {
        if ((fileperms($privatePath) & 0077)!==0) stop('private_directory_permissions_too_broad');
    }
    directory(SITE);directory(SITE.'/plugins');directory(SITE.'/data');
    if (realpath(PRIVATE_SITE)===SITE || str_starts_with(realpath(PRIVATE_SITE),SITE.'/')) stop('private_root_inside_site');
    $entries=zipContents();
    if (file_exists(STATE)) {
        $state=readState();
        if (($state['phase']??'')==='activated') {
            if (hash('sha256',bytes(SITE.'/config.php'))!==$state['candidateConfigSha256'] || inventory(SITE.'/plugins/FamilyHub')!==expectedPlugin($entries)) stop('activated_deployment_changed');
            featureCheck();directory(DATA_TARGET);
            echo "Already activated; no files overwritten. Verify HTTPS capabilities and migrations separately.\n";exit(0);
        }
        preparedCheck($state,$entries);
        if ($argv[1]!=='--activate') {echo "Already prepared and unchanged; PHP-lint the private candidate, then activate.\n";exit(0);}
        // Do not bootstrap Kanboard here: no DB connection or migrations occur in this script.
        if (!rename(WORK.'/FamilyHub',SITE.'/plugins/FamilyHub')) stop('plugin_activation_failed');
        if (hash('sha256',bytes(SITE.'/config.php'))!==$state['originalConfigSha256']) {
            if (!rename(SITE.'/plugins/FamilyHub',WORK.'/FamilyHub')) stop('late_config_change_plugin_rollback_failed');
            stop('late_config_change_plugin_rolled_back');
        }
        if (!rename(CANDIDATE,SITE.'/config.php')) {
            if (!rename(SITE.'/plugins/FamilyHub',WORK.'/FamilyHub')) stop('config_activation_failed_plugin_rollback_failed');
            stop('config_activation_failed_plugin_rolled_back');
        }
        chmod(SITE.'/config.php',0600);
        $state['phase']='activated';$temporary=STATE.'.activated';
        writeNew($temporary,json_encode($state,JSON_PRETTY_PRINT|JSON_THROW_ON_ERROR)."\n");
        if(!rename($temporary,STATE)) stop('activated_state_write_failed');
        echo "Activated: configuration and verified plugin installed. Original config/data preserved privately. No DB migration executed by this script.\n";exit(0);
    }
    if ($argv[1]==='--activate') stop('prepare_required');
    $config=originalConfig();validateConfig($config);
    if (file_exists(SITE.'/plugins/FamilyHub') || is_link(SITE.'/plugins/FamilyHub') || file_exists(DATA_TARGET) || is_link(DATA_TARGET) || file_exists(WORK) || is_link(WORK) || file_exists(FEATURE_CONFIG) || is_link(FEATURE_CONFIG)) stop('unowned_destination_already_exists');
    $pattern='~define\s*\(\s*([\'\"])DATA_DIR\1\s*,\s*(?:([\'\"])'.preg_quote(SITE.'/data','~').'\2|__DIR__\s*\.\s*DIRECTORY_SEPARATOR\s*\.\s*([\'\"])data\3)\s*\)\s*;~';
    $count=preg_match_all($pattern,configScan($config),$matches,PREG_OFFSET_CAPTURE);
    if ($count!==1) stop('exact_data_dir_definition_not_found');
    $match=$matches[0][0];
    $candidate=substr_replace($config,"define('DATA_DIR', '".DATA_TARGET."');",$match[1],strlen($match[0]));
    $candidate=preg_replace('~\?>\s*$~','',$candidate);
    $candidate.="\n// Jivie fresh self-hosted configuration; preserved DB settings above.\nrequire '".FEATURE_CONFIG."';\n";
    validateConfig($candidate);validateConfig(FEATURE_TEXT);
    $before=inventory(SITE.'/data');
    if ($argv[1]==='--check') {echo "Checks passed: exact fresh site/database paths, config parse, ZIP SHA256/61 entries/CRC, unused destinations. No changes made.\n";exit(0);}
    newDirectory(WORK);writeNew(BACKUP,$config);copyTree(SITE.'/data',DATA_TARGET);
    if (inventory(DATA_TARGET)!==$before || inventory(SITE.'/data')!==$before) stop('data_copy_verification_failed');
    writeNew(FEATURE_CONFIG,FEATURE_TEXT);writeNew(CANDIDATE,$candidate);
    newDirectory(WORK.'/FamilyHub');
    foreach($entries as $relative=>$text) {
        $target=WORK.'/FamilyHub/'.$relative;$parent=dirname($target);
        if (!is_dir($parent)) {if (!mkdir($parent,0700,true)) stop('plugin_stage_mkdir_failed');}
        writeNew($target,$text,0644);
    }
    $state=['version'=>1,'phase'=>'prepared','zipSha256'=>ZIP_SHA256,'originalConfigSha256'=>hash('sha256',$config),'candidateConfigSha256'=>hash('sha256',$candidate),'dataInventory'=>$before];
    writeNew(STATE,json_encode($state,JSON_PRETTY_PRINT|JSON_THROW_ON_ERROR)."\n");
    preparedCheck($state,$entries);
    echo "Prepared privately. Run PHP -l on config.candidate.php and familyhub-config.php, then --activate. No live plugin/config/DB changed.\n";
} catch (DeployGuard $error) {
    fwrite(STDERR,"Deployment stopped: ".$error->getMessage().". No configuration or credentials printed. Review private files before retry.\n");exit(1);
} catch (Throwable $error) {
    fwrite(STDERR,"Deployment stopped: parser_or_internal_failure. No exception detail, configuration or credentials printed.\n");exit(1);
}
