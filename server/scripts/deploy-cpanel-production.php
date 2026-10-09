<?php
// Fixed-target CLI helper: fresh Kanboard 1.2.54 / FamilyHub 0.7.0, schema 11.
// No networking, core bootstrap, database connection, migration, account or key generation.
// --check reads only; --prepare stages privately; --activate preserves maintenance.
if (PHP_SAPI !== 'cli') { http_response_code(404); exit; }
ini_set('display_errors', '0'); ini_set('log_errors', '0'); error_reporting(0);
final class ProductionDeployGuard extends RuntimeException {}
function stop(string $code): never { throw new ProductionDeployGuard($code); }
set_error_handler(static function (): never { stop('filesystem_or_php_warning'); });
const HOME_ROOT = '/home/tripar13';
const SITE = HOME_ROOT.'/jivie.triparna.si';
const PRIVATE_SITE = HOME_ROOT.'/private/jivie-production';
const INSTALL = PRIVATE_SITE.'/install';
const ZIP_FILE = INSTALL.'/FamilyHub-0.7.0-source.zip';
const ZIP_SHA256 = '1f201bb6c44c269af081bf629236db815fae3bf5518e8a1913f4a2c6f0bd67ba';
const MANIFEST = INSTALL.'/manifest.json';
const MANIFEST_SHA256 = '0e05619fbcbd33921c3c2a7a29d7b79ddc1f15785791f2ae77c5e076acf23bb1';
const DB_NAME_EXPECTED = 'tripar13_jivieprod';
const PROOF = INSTALL.'/fresh-install-proof.json';
const DATA_TARGET = PRIVATE_SITE.'/data';
const CONFIG_TARGET = PRIVATE_SITE.'/config.php';
const FEATURE_CONFIG = PRIVATE_SITE.'/familyhub-config.php';
const WORK = INSTALL.'/familyhub-deploy';
const STATE = WORK.'/state.json';
const BACKUP = WORK.'/config.before.php';
const CANDIDATE = WORK.'/config.candidate.php';
const PUBLIC_CANDIDATE = WORK.'/public-config.candidate.php';
const FEATURE_TEXT = "<?php\ndefine('FAMILYHUB_ENABLE_NATIVE_API', true);\ndefine('FAMILYHUB_ACCOUNT_MODE', 'self_hosted');\ndefine('FAMILYHUB_ENABLE_PROJECT_INVITATIONS', false);\ndefine('FAMILYHUB_ENABLE_FCM', false);\ndefine('FAMILYHUB_TRUSTED_PROXY_IPS', []);\ndefine('FAMILYHUB_CORS_ORIGINS', []);\n";
const PUBLIC_TEXT = "<?php\n// Jivie production: database configuration and data stay outside document roots.\nrequire '/home/tripar13/private/jivie-production/config.php';\n";

function directory(string $path, bool $private = false): void {
    clearstatcache(true, $path);
    if (is_link($path) || !is_dir($path) || realpath($path) !== $path) stop('directory_guard_failed');
    if ($private && (fileperms($path) & 0777) !== 0700) stop('private_directory_permissions_required_0700');
    if (fileowner($path) !== fileowner(HOME_ROOT)) stop('directory_owner_guard_failed');
}
function bytes(string $path, bool $private = false): string {
    clearstatcache(true, $path);
    if (is_link($path) || !is_file($path) || !is_readable($path)) stop('file_guard_failed');
    if ($private && (fileperms($path) & 0777) !== 0600) stop('private_file_permissions_required_0600');
    if (fileowner($path) !== fileowner(HOME_ROOT)) stop('file_owner_guard_failed');
    $text = file_get_contents($path); if (!is_string($text)) stop('file_read_failed'); return $text;
}
function newDirectory(string $path): void {
    if (file_exists($path) || is_link($path)) stop('destination_already_exists');
    if (!mkdir($path, 0700) || !chmod($path, 0700)) stop('private_mkdir_failed');
}
function writeNew(string $path, string $text, int $mode = 0600): void {
    $handle = fopen($path, 'xb'); if (!$handle) stop('exclusive_file_create_failed');
    try { if (fwrite($handle, $text) !== strlen($text) || !fflush($handle)) stop('file_write_failed'); }
    finally { fclose($handle); }
    if (!chmod($path, $mode)) stop('chmod_failed');
}
function jsonBytes(array $data): string { return json_encode($data, JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES | JSON_THROW_ON_ERROR)."\n"; }
function inventory(string $root, bool $private = false): array {
    directory($root, $private); $result = [];
    $walk = function (string $dir, string $prefix) use (&$walk, &$result, $private): void {
        directory($dir, $private);
        foreach (new DirectoryIterator($dir) as $file) {
            if ($file->isDot()) continue;
            if ($file->isLink()) stop('tree_symlink_rejected');
            $relative = $prefix.$file->getFilename();
            if ($file->isDir()) { $result[$relative.'/'] = 'directory'; $walk($file->getPathname(), $relative.'/'); }
            elseif ($file->isFile()) $result[$relative] = hash('sha256', bytes($file->getPathname(), $private));
            else stop('tree_entry_rejected');
        }
    };
    $walk($root, ''); ksort($result); return $result;
}
function copyTree(string $source, string $target): void {
    newDirectory($target);
    foreach (new DirectoryIterator($source) as $file) {
        if ($file->isDot()) continue;
        if ($file->isLink()) stop('tree_symlink_rejected');
        if ($file->isDir()) copyTree($file->getPathname(), $target.'/'.$file->getFilename());
        elseif ($file->isFile()) writeNew($target.'/'.$file->getFilename(), bytes($file->getPathname()));
        else stop('tree_entry_rejected');
    }
}
function parse(string $text): void { token_get_all($text, TOKEN_PARSE); }
function configDefines(string $text): array {
    // Only top-level literal define statements are accepted, never executed.
    // Includes, variables, conditionals and dynamic credentials require manual review.
    parse($text); $tokens = [];
    foreach (token_get_all($text) as $token) {
        if (is_array($token) && in_array($token[0], [T_OPEN_TAG, T_WHITESPACE, T_COMMENT, T_DOC_COMMENT], true)) continue;
        if (is_array($token) && $token[0] === T_CLOSE_TAG) stop('config_closing_tag_requires_review');
        $tokens[] = $token;
    }
    $result = []; $i = 0;
    $literal = static function ($token): ?string {
        if (!is_array($token) || $token[0] !== T_CONSTANT_ENCAPSED_STRING) return null;
        $value = $token[1]; if (str_contains($value, '\\')) return null;
        return substr($value, 1, -1);
    };
    while ($i < count($tokens)) {
        $call = $tokens[$i++] ?? null;
        if (!is_array($call) || $call[0] !== T_STRING || strtolower($call[1]) !== 'define' || ($tokens[$i++] ?? null) !== '(') stop('config_top_level_statement_requires_review');
        $name = $literal($tokens[$i++] ?? null);
        if (!is_string($name) || !preg_match('/^[A-Z][A-Z0-9_]*$/D', $name) || isset($result[$name]) || ($tokens[$i++] ?? null) !== ',') stop('config_define_name_or_duplicate');
        $expression = [];
        while ($i < count($tokens) && $tokens[$i] !== ')') {
            $token = $tokens[$i++];
            if (is_array($token)) {
                if (!in_array($token[0], [T_CONSTANT_ENCAPSED_STRING, T_LNUMBER, T_STRING, T_DIR], true)) stop('config_dynamic_expression_requires_review');
                if ($token[0] === T_STRING && !in_array($token[1], ['true', 'false', 'DATA_DIR', 'DIRECTORY_SEPARATOR'], true)) stop('config_expression_constant_requires_review');
                $expression[] = $token[1];
            } elseif ($token === '.') $expression[] = '.';
            else stop('config_expression_requires_review');
        }
        if (!$expression || ($tokens[$i++] ?? null) !== ')' || ($tokens[$i++] ?? null) !== ';') stop('config_define_syntax');
        $result[$name] = implode('', $expression);
    }
    return $result;
}
function literalEquals(string $expression, string $expected): bool { return $expression === var_export($expected, true) || $expression === '"'.$expected.'"'; }
function originalConfig(): string {
    $text = bytes(SITE.'/config.php'); $defs = configDefines($text);
    $allowed = ['DB_DRIVER','DB_HOSTNAME','DB_PORT','DB_NAME','DB_USERNAME','DB_PASSWORD','DATA_DIR','FILES_DIR','CACHE_DIR','LOG_FILE','DEBUG','PLUGIN_INSTALLER','LDAP_AUTH','REVERSE_PROXY_AUTH','ENABLE_URL_REWRITE','LOG_DRIVER','LOG_SYSLOG_IDENT','LANGUAGE','TIMEZONE'];
    if (array_diff(array_keys($defs), $allowed)) stop('config_unreviewed_constant');
    if (!literalEquals($defs['DB_DRIVER'] ?? '', 'mysql') || !literalEquals($defs['DB_NAME'] ?? '', DB_NAME_EXPECTED) ||
        (!literalEquals($defs['DB_HOSTNAME'] ?? '', 'localhost') && !literalEquals($defs['DB_HOSTNAME'] ?? '', '127.0.0.1'))) stop('fresh_database_identity_guard_failed');
    foreach (['DB_USERNAME', 'DB_PASSWORD'] as $name) if (!preg_match('~^(?:\x27(?:[^\x27\\\\]|\\\\.)*\x27|"(?:[^"\\\\]|\\\\.)*")$~sD', $defs[$name] ?? '')) stop('database_credential_literal_required');
    if (isset($defs['DB_PORT']) && $defs['DB_PORT'] !== '3306') stop('database_port_requires_review');
    $data = $defs['DATA_DIR'] ?? '';
    if (!literalEquals($data, SITE.'/data') && !in_array($data, ["__DIR__.DIRECTORY_SEPARATOR.'data'", '__DIR__.DIRECTORY_SEPARATOR."data"'], true)) stop('exact_data_dir_definition_required');
    foreach (['FILES_DIR'=>'files', 'CACHE_DIR'=>'cache', 'LOG_FILE'=>'debug.log'] as $name=>$suffix) {
        if (isset($defs[$name]) && !in_array($defs[$name], ["DATA_DIR.DIRECTORY_SEPARATOR.'$suffix'", 'DATA_DIR.DIRECTORY_SEPARATOR."'.$suffix.'"'], true)) stop('explicit_data_path_requires_review');
    }
    foreach (['LDAP_AUTH','REVERSE_PROXY_AUTH'] as $name) if (isset($defs[$name]) && $defs[$name] !== 'false') stop('external_auth_requires_review');
    return $text;
}
function configCandidate(string $original): string {
    // Token parser already excluded executable expressions and duplicate defines.
    $spans = []; $offset = 0; $start = null; $name = null;
    foreach (token_get_all($original) as $token) {
        $raw = is_array($token) ? $token[1] : $token;
        if (is_array($token) && $token[0] === T_STRING && strtolower($raw) === 'define') { $start = $offset; $name = null; }
        elseif ($start !== null && $name === null && is_array($token) && $token[0] === T_CONSTANT_ENCAPSED_STRING) $name = substr($raw,1,-1);
        elseif ($start !== null && $raw === ';') { $spans[$name] = [$start,$offset + 1 - $start]; $start = null; }
        $offset += strlen($raw);
    }
    $replacements = [];
    foreach (['DATA_DIR'=>var_export(DATA_TARGET,true), 'DEBUG'=>'false', 'PLUGIN_INSTALLER'=>'false'] as $name=>$value) {
        if (isset($spans[$name])) $replacements[] = [$spans[$name][0],$spans[$name][1],"define('$name', $value);"];
        elseif ($name === 'DATA_DIR') stop('config_rewrite_count');
        else $original .= "\ndefine('$name', $value);\n";
    }
    usort($replacements, static fn($a,$b)=>$b[0]<=>$a[0]);
    foreach ($replacements as [$offset,$length,$replacement]) $original = substr_replace($original,$replacement,$offset,$length);
    $original .= "\n// Separate production features; DB credentials above are preserved.\nrequire ".var_export(FEATURE_CONFIG,true).";\n"; parse($original); return $original;
}
function maintenanceHash(): string {
    $text = bytes(SITE.'/.htaccess');
    // Root establishes and verifies HTTPS 503 separately. This never removes it.
    if (!str_starts_with(str_replace("\r\n","\n",$text), "# JIVIE PRODUCTION MAINTENANCE\nRewriteEngine On\nRewriteRule ^ - [R=503,L]\n")) stop('production_maintenance_required');
    return hash('sha256',$text);
}
function freshProof(string $configHash): string {
    $text = bytes(PROOF,true); $proof = json_decode($text,true,32,JSON_THROW_ON_ERROR);
    if (!is_array($proof) || ($proof['format']??null)!=='jivie-fresh-install-operator-attestation-v1' || ($proof['site']??null)!==SITE || ($proof['database']??null)!==DB_NAME_EXPECTED || ($proof['kanboardVersion']??null)!=='1.2.54' || ($proof['configSha256']??null)!==$configHash) stop('fresh_operator_attestation_identity_required');
    foreach (['newSoftaculousInstallation','noImportedAccountsOrData','onlyInitialAdmin','initialAdminPasswordChanged','zeroProjects','zeroTasks','noFamilyHubTables','privateRootOutsideAllDocumentRoots','maintenanceHttps503Verified'] as $flag) if (($proof[$flag]??null)!==true) stop('fresh_operator_attestation_incomplete');
    // An operator statement is required evidence, never an automatic live DB check.
    return hash('sha256',$text);
}
function bundle(): array {
    if (!class_exists(ZipArchive::class)) stop('zip_extension_required');
    $manifestText = bytes(MANIFEST,true);
    if (!hash_equals(MANIFEST_SHA256,hash('sha256',$manifestText)) || !hash_equals(ZIP_SHA256,hash('sha256',bytes(ZIP_FILE,true)))) stop('pinned_bundle_checksum_mismatch');
    $manifest = json_decode($manifestText,true,32,JSON_THROW_ON_ERROR);
    if (($manifest['format']??null)!=='jivie-familyhub-upgrade-manifest-v1' || ($manifest['pluginVersion']??null)!=='0.7.0' || ($manifest['schemaVersion']??null)!==11 || ($manifest['archiveSha256']??null)!==ZIP_SHA256 || count($manifest['files']??[])!==63) stop('pinned_manifest_invalid');
    $zip = new ZipArchive(); if ($zip->open(ZIP_FILE,ZipArchive::RDONLY)!==true) stop('zip_open_failed'); $result = [];
    try {
        if ($zip->numFiles !== 63) stop('zip_entry_count_mismatch');
        for ($i=0;$i<$zip->numFiles;$i++) {
            $stat=$zip->statIndex($i); $name=$stat['name']??'';
            if (!preg_match('~^FamilyHub/[A-Za-z0-9_./-]+$~D',$name) || str_contains($name,'..') || str_ends_with($name,'/') || isset($result[$name]) || !isset($manifest['files'][$name])) stop('zip_entry_rejected');
            if (!$zip->getExternalAttributesIndex($i,$opsys,$attributes) || ($attributes>>16 & 0170000)!==0100000) stop('zip_entry_type_rejected');
            $text=$zip->getFromIndex($i);
            if (!is_string($text) || strlen($text)!==($stat['size']??-1) || strlen($text)>2097152 || !hash_equals($manifest['files'][$name],hash('sha256',$text)) || hash('crc32b',$text)!==sprintf('%08x',$stat['crc'])) stop('zip_entry_content_mismatch');
            if (str_ends_with($name,'.php')) parse($text);
            $result[$name]=$text;
        }
    } finally { $zip->close(); }
    ksort($result); return $result;
}
function pluginInventory(array $entries): array {
    $result=[];
    foreach ($entries as $name=>$text) {
        $relative=substr($name,10); $result[$relative]=hash('sha256',$text); $parent=dirname($relative);
        while ($parent!=='.') { $result[$parent.'/']='directory'; $parent=dirname($parent); }
    }
    ksort($result); return $result;
}
function verifiedPluginTree(string $root): array {
    directory($root,true);
    $iterator=new RecursiveIteratorIterator(new RecursiveDirectoryIterator($root,FilesystemIterator::SKIP_DOTS),RecursiveIteratorIterator::SELF_FIRST);
    foreach ($iterator as $entry) {
        if ($entry->isLink()) stop('tree_symlink_rejected');
        if ($entry->isDir()) directory($entry->getPathname(),true);
        elseif ($entry->isFile()) {
            bytes($entry->getPathname());
            if (($entry->getPerms() & 0777)!==0644) stop('plugin_file_permissions_required_0644');
        } else stop('tree_entry_rejected');
    }
    return inventory($root);
}
function state(): array { $state=json_decode(bytes(STATE,true),true,32,JSON_THROW_ON_ERROR);if (!is_array($state)) stop('state_invalid');return $state; }
function verifyState(array $state, array $entries): void {
    directory(WORK,true);
    if (bytes(WORK.'/lock',true)!=='') stop('lock_file_changed');
    if (($state['version']??null)!==1 || ($state['zipSha256']??null)!==ZIP_SHA256 || !in_array($state['phase']??null,['prepared','activated'],true)) stop('state_invalid');
    if (hash('sha256',bytes(BACKUP,true))!==($state['originalConfigSha256']??null) || freshProof($state['originalConfigSha256'])!==($state['proofSha256']??null)) stop('original_backup_or_attestation_changed');
    if (maintenanceHash()!==($state['maintenanceSha256']??null)) stop('maintenance_changed');
    if (bytes(FEATURE_CONFIG,true)!==FEATURE_TEXT) stop('feature_config_changed');
    if ($state['phase']==='prepared') {
        if (!is_file(CANDIDATE) || !is_file(PUBLIC_CANDIDATE) || file_exists(CONFIG_TARGET) || is_link(CONFIG_TARGET) || file_exists(SITE.'/plugins/FamilyHub') || is_link(SITE.'/plugins/FamilyHub')) stop('partial_or_unowned_activation_requires_review');
        if (hash('sha256',bytes(SITE.'/config.php'))!==$state['originalConfigSha256'] || hash('sha256',bytes(CANDIDATE,true))!==$state['candidateConfigSha256'] || bytes(PUBLIC_CANDIDATE,true)!==PUBLIC_TEXT) stop('prepared_config_changed');
        if (inventory(SITE.'/data')!==$state['dataInventory'] || inventory(DATA_TARGET,true)!==$state['dataInventory']) stop('data_changed_since_prepare');
        if (file_exists(CONFIG_TARGET) || is_link(CONFIG_TARGET) || file_exists(SITE.'/plugins/FamilyHub') || is_link(SITE.'/plugins/FamilyHub')) stop('activation_destination_exists');
        if (verifiedPluginTree(WORK.'/FamilyHub')!==pluginInventory($entries)) stop('staged_plugin_changed');
    } else {
        if (bytes(SITE.'/config.php',true)!==PUBLIC_TEXT || hash('sha256',bytes(CONFIG_TARGET,true))!==$state['candidateConfigSha256'] || verifiedPluginTree(SITE.'/plugins/FamilyHub')!==pluginInventory($entries)) stop('activated_deployment_changed');
        directory(DATA_TARGET,true); // Data may legitimately change after activation.
    }
}
try {
    umask(0077);
    if ($argc!==2 || !in_array($argv[1],['--check','--prepare','--activate'],true)) stop('usage_check_prepare_activate_no_overrides');
    directory(HOME_ROOT); directory(HOME_ROOT.'/private',true); directory(PRIVATE_SITE,true); directory(INSTALL,true);
    directory(SITE); directory(SITE.'/plugins'); directory(SITE.'/data');
    if (str_starts_with(PRIVATE_SITE,SITE.'/')) stop('private_root_inside_site');
    $entries=bundle();
    if (file_exists(STATE) || is_link(STATE)) {
        $state=state(); verifyState($state,$entries);
        if ($argv[1]==='--check') { echo "Checks passed; no files or database changed. State: ".$state['phase'].".\n"; exit(0); }
        if ($state['phase']==='activated') { echo "Already activated; maintenance retained, no files overwritten. Migrations and live checks are separate.\n"; exit(0); }
        if ($argv[1]==='--prepare') { echo "Already prepared and unchanged; maintenance retained.\n"; exit(0); }
        $lock=fopen(WORK.'/lock','rb'); if (!$lock || !flock($lock,LOCK_EX|LOCK_NB)) stop('deployment_busy');
        $state=state();verifyState($state,$entries);
        if (!rename(CANDIDATE,CONFIG_TARGET)) stop('private_config_activation_failed');
        if (!rename(WORK.'/FamilyHub',SITE.'/plugins/FamilyHub')) {
            if (!rename(CONFIG_TARGET,CANDIDATE)) stop('plugin_activation_failed_config_rollback_failed'); stop('plugin_activation_failed_config_rolled_back');
        }
        // Public config is the final switch; original public data/config remain until now.
        if (hash('sha256',bytes(SITE.'/config.php'))!==$state['originalConfigSha256'] || !rename(PUBLIC_CANDIDATE,SITE.'/config.php')) {
            if (!rename(SITE.'/plugins/FamilyHub',WORK.'/FamilyHub') || !rename(CONFIG_TARGET,CANDIDATE)) stop('public_config_activation_failed_rollback_failed'); stop('public_config_activation_failed_rolled_back');
        }
        $state['phase']='activated';writeNew(STATE.'.activated',jsonBytes($state));if (!rename(STATE.'.activated',STATE)) stop('activated_state_write_failed');
        verifyState($state,$entries);
        echo "Activated verified FamilyHub 0.7.0 files and private configuration. Maintenance remains active; old data/config preserved. No DB migration executed.\n";exit(0);
    }
    if ($argv[1]==='--activate') stop('prepare_required');
    $config=originalConfig();$configHash=hash('sha256',$config);$proofHash=freshProof($configHash);$maintenanceHash=maintenanceHash();
    if (file_exists(SITE.'/data/config.php') || is_link(SITE.'/data/config.php')) stop('secondary_data_config_requires_review');
    foreach (new DirectoryIterator(SITE.'/plugins') as $item) if (!$item->isDot()) stop('fresh_empty_plugin_directory_required');
    $before=inventory(SITE.'/data');
    foreach ($before as $relative=>$hash) {
        // Fresh source protections only; imported uploads, logs, caches/SQLite fail closed.
        if (!in_array($relative,['.htaccess','web.config','index.html','files/','cache/'],true)) stop('fresh_data_tree_requires_review');
    }
    foreach ([WORK,DATA_TARGET,CONFIG_TARGET,FEATURE_CONFIG] as $path) if (file_exists($path) || is_link($path)) stop('partial_prepare_or_unowned_destination_requires_review');
    $candidate=configCandidate($config);parse(FEATURE_TEXT);parse(PUBLIC_TEXT);
    if ($argv[1]==='--check') { echo "Checks passed: fixed site/database, operator attestation, maintenance, pinned 63-file bundle, private destinations. No live DB check or changes.\n";exit(0); }
    newDirectory(WORK);writeNew(WORK.'/lock','');$lock=fopen(WORK.'/lock','rb');if (!$lock || !flock($lock,LOCK_EX|LOCK_NB)) stop('deployment_busy');
    writeNew(BACKUP,$config);copyTree(SITE.'/data',DATA_TARGET);
    if (inventory(DATA_TARGET,true)!==$before || inventory(SITE.'/data')!==$before) stop('data_copy_verification_failed');
    writeNew(FEATURE_CONFIG,FEATURE_TEXT);writeNew(CANDIDATE,$candidate);writeNew(PUBLIC_CANDIDATE,PUBLIC_TEXT);newDirectory(WORK.'/FamilyHub');
    foreach ($entries as $name=>$text) {
        $target=WORK.'/'.$name;$parent=dirname($target);
        if (!is_dir($parent) && !mkdir($parent,0700,true)) stop('plugin_stage_mkdir_failed');
        writeNew($target,$text,0644);
    }
    $state=['version'=>1,'phase'=>'prepared','zipSha256'=>ZIP_SHA256,'originalConfigSha256'=>$configHash,'candidateConfigSha256'=>hash('sha256',$candidate),'proofSha256'=>$proofHash,'maintenanceSha256'=>$maintenanceHash,'dataInventory'=>$before];
    writeNew(STATE,jsonBytes($state));verifyState($state,$entries);
    echo "Prepared privately; live config/plugin/DB unchanged. Candidate syntax and copy hashes verified; maintenance retained.\n";
} catch (ProductionDeployGuard $error) {
    fwrite(STDERR,"Production deployment stopped: ".$error->getMessage().". No configuration or credentials printed. Review private state before retry.\n");exit(1);
} catch (Throwable $error) {
    fwrite(STDERR,"Production deployment stopped: parser_or_internal_failure. No exception, configuration or credentials printed.\n");exit(1);
}
