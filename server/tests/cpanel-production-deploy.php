<?php
// Offline filesystem fixtures only. Helper copies cannot resolve a real cPanel path.
// Run in a disposable PHP+zip container with --network none and repo mounted :ro.
if (PHP_SAPI !== 'cli' || $argc !== 1) exit(1);
umask(0077);
$repository=dirname(__DIR__,2);
$source=file_get_contents($repository.'/server/scripts/deploy-cpanel-production.php');
$archive=$repository.'/build/releases/FamilyHub-0.7.0-source.zip';
$manifest=$repository.'/build/qa/jivie-upgrade/cpanel-upload/manifest.json';
$root=sys_get_temp_dir().'/jivie-production-deploy-test-'.bin2hex(random_bytes(8));mkdir($root,0700);
$assertions=0;
function check(bool $condition,string $message): void { global $assertions;$assertions++;if (!$condition) throw new RuntimeException($message); }
function privateFile(string $path,string $contents): void { file_put_contents($path,$contents);chmod($path,0600); }
function removeTree(string $path): void { if (is_link($path) || !is_dir($path)) { unlink($path);return; }foreach (scandir($path) as $entry) if ($entry!=='.' && $entry!=='..') removeTree($path.'/'.$entry);rmdir($path); }
function snapshot(string $root): array {
    $result=[];
    $iterator=new RecursiveIteratorIterator(new RecursiveDirectoryIterator($root,FilesystemIterator::SKIP_DOTS),RecursiveIteratorIterator::SELF_FIRST);
    foreach ($iterator as $entry) $result[substr($entry->getPathname(),strlen($root))]=[$entry->isLink()?'link':($entry->isDir()?'directory':hash_file('sha256',$entry->getPathname())),$entry->getPerms()&0777];
    ksort($result);return $result;
}
function fixture(string $name,?string $config=null): array {
    global $root,$source,$archive,$manifest;
    $home=$root.'/'.$name;$site=$home.'/jivie.triparna.si';$base=$home.'/private/jivie-production';
    foreach ([$home,$site,$site.'/plugins',$site.'/data',$site.'/data/files',$site.'/data/cache',$home.'/private',$base,$base.'/install'] as $dir) mkdir($dir,0700);
    $helper=str_replace('/home/tripar13',$home,$source);
    check(!str_contains($helper,'/home/tripar13'),'Fixture helper retained live host path');
    privateFile($home.'/helper.php',$helper);
    $config??="<?php\n// define('DEBUG', true); sample ignored\ndefine('DB_DRIVER', 'mysql');\ndefine('DB_HOSTNAME', 'localhost');\ndefine('DB_PORT', 3306);\ndefine('DB_NAME', 'tripar13_jivieprod');\ndefine('DB_USERNAME', 'synthetic_admin');\ndefine('DB_PASSWORD', 'offline_secret_only');\ndefine('DATA_DIR', __DIR__ . DIRECTORY_SEPARATOR . 'data');\ndefine('DEBUG', true);\ndefine('PLUGIN_INSTALLER', true);\n";
    privateFile($site.'/config.php',$config);
    privateFile($site.'/.htaccess',"# JIVIE PRODUCTION MAINTENANCE\nRewriteEngine On\nRewriteRule ^ - [R=503,L]\n# unrelated original protection\n");
    privateFile($site.'/data/.htaccess',"Deny from all\n");privateFile($site.'/data/web.config',"<configuration/>\n");
    privateFile($base.'/install/FamilyHub-0.7.0-source.zip',file_get_contents($archive));
    privateFile($base.'/install/manifest.json',file_get_contents($manifest));
    $proof=['format'=>'jivie-fresh-install-operator-attestation-v1','site'=>$site,'database'=>'tripar13_jivieprod','kanboardVersion'=>'1.2.54','configSha256'=>hash('sha256',$config)];
    foreach (['newSoftaculousInstallation','noImportedAccountsOrData','onlyInitialAdmin','initialAdminPasswordChanged','zeroProjects','zeroTasks','noFamilyHubTables','privateRootOutsideAllDocumentRoots','maintenanceHttps503Verified'] as $flag) $proof[$flag]=true;
    privateFile($base.'/install/fresh-install-proof.json',json_encode($proof,JSON_THROW_ON_ERROR));
    return ['home'=>$home,'site'=>$site,'base'=>$base,'helper'=>$home.'/helper.php','config'=>$config,'proof'=>$proof];
}
function invoke(array $f,string $mode,array $extra=[]): array {
    $process=proc_open(array_merge([PHP_BINARY,$f['helper'],$mode],$extra),[0=>['pipe','r'],1=>['pipe','w'],2=>['pipe','w']],$pipes);fclose($pipes[0]);
    $output=stream_get_contents($pipes[1]).stream_get_contents($pipes[2]);fclose($pipes[1]);fclose($pipes[2]);$status=proc_close($process);
    check(!str_contains($output,'offline_secret_only') && !str_contains($output,'synthetic_admin'),'Credential appeared in output');
    return [$status,$output];
}
function succeeds(array $f,string $mode): string { [$status,$output]=invoke($f,$mode);check($status===0,'Expected success: '.$mode.' '.$output);return $output; }
function fails(array $f,string $mode,string $reason,array $extra=[]): void { [$status,$output]=invoke($f,$mode,$extra);check($status!==0 && str_contains($output,$reason),'Expected '.$reason.', got '.$output); }
function proof(array $f,array $overrides): void { privateFile($f['base'].'/install/fresh-install-proof.json',json_encode(array_replace($f['proof'],$overrides),JSON_THROW_ON_ERROR)); }
try {
    check(hash_file('sha256',$archive)==='1f201bb6c44c269af081bf629236db815fae3bf5518e8a1913f4a2c6f0bd67ba','Reviewed ZIP missing or changed');
    check(hash_file('sha256',$manifest)==='0e05619fbcbd33921c3c2a7a29d7b79ddc1f15785791f2ae77c5e076acf23bb1','Reviewed manifest missing or changed');
    $valid=fixture('valid');$site=$valid['site'];$base=$valid['base'];$originalData=snapshot($site.'/data');$maintenance=file_get_contents($site.'/.htaccess');
    $before=snapshot($valid['home']);succeeds($valid,'--check');check(snapshot($valid['home'])===$before,'Check wrote files');
    fails($valid,'--activate','prepare_required');fails($valid,'--prepare','usage_check_prepare_activate_no_overrides',['--site=/home/tripar13/jivie-test.triparna.si']);
    succeeds($valid,'--prepare');check(file_get_contents($site.'/config.php')===$valid['config'],'Prepare activated config');check(!is_dir($site.'/plugins/FamilyHub'),'Prepare activated plugin');
    check(snapshot($site.'/data')===$originalData,'Prepare changed old public data');check(file_get_contents($base.'/install/familyhub-deploy/config.before.php')===$valid['config'],'Backup changed DB config');
    $candidate=file_get_contents($base.'/install/familyhub-deploy/config.candidate.php');check(str_contains($candidate,"define('DB_PASSWORD', 'offline_secret_only');"),'Candidate lost credentials');
    check(str_contains($candidate,"define('DEBUG', false);") && str_contains($candidate,"define('PLUGIN_INSTALLER', false);"),'Candidate lacks safe flags');
    $before=snapshot($valid['home']);succeeds($valid,'--check');succeeds($valid,'--prepare');check(snapshot($valid['home'])===$before,'Prepared check/retry mutated files');
    foreach ([$base.'/familyhub-config.php',$base.'/install/familyhub-deploy/config.before.php',$base.'/install/familyhub-deploy/config.candidate.php',$base.'/install/familyhub-deploy/public-config.candidate.php',$base.'/install/familyhub-deploy/state.json',$base.'/install/familyhub-deploy/lock'] as $p) check((fileperms($p)&0777)===0600,'Private file permissions not 0600');
    $iterator=new RecursiveIteratorIterator(new RecursiveDirectoryIterator($base.'/data',FilesystemIterator::SKIP_DOTS),RecursiveIteratorIterator::SELF_FIRST);
    foreach ($iterator as $p) check(($p->getPerms()&0777)===($p->isDir()?0700:0600),'Private data permissions too broad');
    succeeds($valid,'--activate');check(!str_contains(file_get_contents($site.'/config.php'),'offline_secret_only'),'Public config contains credentials');
    check(file_get_contents($base.'/config.php')===$candidate,'Private live config mismatched');check((fileperms($site.'/config.php')&0777)===0600,'Public include permissions wrong');
    check(is_dir($site.'/plugins/FamilyHub') && !is_dir($base.'/install/familyhub-deploy/FamilyHub'),'Plugin was not moved');
    check(file_get_contents($site.'/.htaccess')===$maintenance && snapshot($site.'/data')===$originalData,'Activation changed maintenance/original data');
    $before=snapshot($valid['home']);succeeds($valid,'--check');succeeds($valid,'--prepare');succeeds($valid,'--activate');check(snapshot($valid['home'])===$before,'Activated retry mutated files');
    privateFile($base.'/data/files/new-local-data','new data after activation');succeeds($valid,'--check');

    $missing=fixture('missing-proof');unlink($missing['base'].'/install/fresh-install-proof.json');fails($missing,'--check','file_guard_failed');
    foreach (['zeroProjects'=>false,'onlyInitialAdmin'=>false,'initialAdminPasswordChanged'=>false,'noFamilyHubTables'=>false,'privateRootOutsideAllDocumentRoots'=>false,'maintenanceHttps503Verified'=>false,'configSha256'=>str_repeat('a',64)] as $flag=>$value) {
        $f=fixture('bad-proof-'.$flag);proof($f,[$flag=>$value]);$before=snapshot($f['home']);fails($f,'--prepare',str_ends_with($flag,'Sha256')?'fresh_operator_attestation_identity_required':'fresh_operator_attestation_incomplete');check(snapshot($f['home'])===$before,'Bad proof created files');
    }
    $wrong=fixture('wrong-db',str_replace('tripar13_jivieprod','tripar13_jivietest',$valid['config']));fails($wrong,'--check','fresh_database_identity_guard_failed');
    $dynamic=fixture('dynamic',$valid['config']."require '/must/not/be/executed';\n");fails($dynamic,'--check','config_top_level_statement_requires_review');
    $duplicate=fixture('duplicate',$valid['config']."define('DB_NAME', 'tripar13_jivieprod');\n");fails($duplicate,'--check','config_define_name_or_duplicate');
    $credentialPattern=fixture('credential-pattern',str_replace('offline_secret_only',"define(\\'DEBUG\\', true);",$valid['config']));succeeds($credentialPattern,'--prepare');check(str_contains(file_get_contents($credentialPattern['base'].'/install/familyhub-deploy/config.candidate.php'),"define(\\'DEBUG\\', true);"),'Replacement altered string inside password');
    $emptyFlags=fixture('absent-flags',str_replace(["define('DEBUG', true);\n","define('PLUGIN_INSTALLER', true);\n"],'',$valid['config']));succeeds($emptyFlags,'--prepare');
    $plugin=fixture('existing-plugin');mkdir($plugin['site'].'/plugins/FamilyHub',0700);fails($plugin,'--prepare','fresh_empty_plugin_directory_required');
    $uploads=fixture('uploads');privateFile($uploads['site'].'/data/files/not-fresh.txt','old personal data');fails($uploads,'--prepare','fresh_data_tree_requires_review');
    $maintenanceMissing=fixture('no-maintenance');privateFile($maintenanceMissing['site'].'/.htaccess',"RewriteEngine On\n");fails($maintenanceMissing,'--prepare','production_maintenance_required');
    $maintenanceLate=fixture('late-maintenance');privateFile($maintenanceLate['site'].'/.htaccess',"RewriteRule ^ - [L]\n".file_get_contents($maintenanceLate['site'].'/.htaccess'));fails($maintenanceLate,'--check','production_maintenance_required');
    $broad=fixture('broad');chmod($broad['base'],0755);fails($broad,'--check','private_directory_permissions_required_0700');
    $broadProof=fixture('broad-proof');chmod($broadProof['base'].'/install/fresh-install-proof.json',0644);fails($broadProof,'--check','private_file_permissions_required_0600');
    $symlink=fixture('symlink');symlink($symlink['site'].'/config.php',$symlink['site'].'/data/linked');fails($symlink,'--check','tree_symlink_rejected');
    $tamper=fixture('tamper');privateFile($tamper['base'].'/install/FamilyHub-0.7.0-source.zip','invalid');fails($tamper,'--prepare','pinned_bundle_checksum_mismatch');
    $changed=fixture('changed');succeeds($changed,'--prepare');privateFile($changed['site'].'/config.php',$changed['config']."// later edit\n");fails($changed,'--activate','prepared_config_changed');check(!is_dir($changed['site'].'/plugins/FamilyHub'),'Late config edit activated plugin');
    $dataChanged=fixture('data-changed');succeeds($dataChanged,'--prepare');privateFile($dataChanged['site'].'/data/files/late','new');fails($dataChanged,'--activate','data_changed_since_prepare');
    $stageChanged=fixture('stage-changed');succeeds($stageChanged,'--prepare');privateFile($stageChanged['base'].'/install/familyhub-deploy/FamilyHub/Plugin.php',"<?php\n");chmod($stageChanged['base'].'/install/familyhub-deploy/FamilyHub/Plugin.php',0644);fails($stageChanged,'--activate','staged_plugin_changed');
    $featureChanged=fixture('feature-changed');succeeds($featureChanged,'--prepare');privateFile($featureChanged['base'].'/familyhub-config.php',"<?php\n");fails($featureChanged,'--activate','feature_config_changed');
    $maintenanceChanged=fixture('maintenance-changed');succeeds($maintenanceChanged,'--prepare');privateFile($maintenanceChanged['site'].'/.htaccess',file_get_contents($maintenanceChanged['site'].'/.htaccess')."# changed\n");fails($maintenanceChanged,'--activate','maintenance_changed');
    $pluginMode=fixture('plugin-mode');succeeds($pluginMode,'--prepare');chmod($pluginMode['base'].'/install/familyhub-deploy/FamilyHub/Plugin.php',0666);fails($pluginMode,'--activate','plugin_file_permissions_required_0644');
    $privateMode=fixture('private-mode');succeeds($privateMode,'--prepare');chmod($privateMode['base'].'/data/.htaccess',0644);fails($privateMode,'--activate','private_file_permissions_required_0600');
    $proofChanged=fixture('proof-changed');succeeds($proofChanged,'--prepare');proof($proofChanged,['zeroTasks'=>false]);fails($proofChanged,'--activate','fresh_operator_attestation_incomplete');
    $manifestChanged=fixture('manifest-changed');privateFile($manifestChanged['base'].'/install/manifest.json',file_get_contents($manifestChanged['base'].'/install/manifest.json')."\n");fails($manifestChanged,'--check','pinned_bundle_checksum_mismatch');
    $partialPrepare=fixture('partial-prepare');mkdir($partialPrepare['base'].'/install/familyhub-deploy',0700);$before=snapshot($partialPrepare['home']);fails($partialPrepare,'--prepare','partial_prepare_or_unowned_destination_requires_review');check(snapshot($partialPrepare['home'])===$before,'Partial prepare was altered');
    foreach ([1,2,3] as $step) {
        $partial=fixture('partial-activate-'.$step);succeeds($partial,'--prepare');$work=$partial['base'].'/install/familyhub-deploy';
        rename($work.'/config.candidate.php',$partial['base'].'/config.php');
        if ($step>=2) rename($work.'/FamilyHub',$partial['site'].'/plugins/FamilyHub');
        if ($step>=3) rename($work.'/public-config.candidate.php',$partial['site'].'/config.php');
        $before=snapshot($partial['home']);fails($partial,'--activate','partial_or_unowned_activation_requires_review');check(snapshot($partial['home'])===$before,'Partial activation was altered');check(str_starts_with(file_get_contents($partial['site'].'/.htaccess'),'# JIVIE PRODUCTION MAINTENANCE'),'Partial activation lost maintenance');
    }
    $busy=fixture('busy');succeeds($busy,'--prepare');$lock=fopen($busy['base'].'/install/familyhub-deploy/lock','rb');flock($lock,LOCK_EX);fails($busy,'--activate','deployment_busy');flock($lock,LOCK_UN);fclose($lock);
    echo "PASS: $assertions production deploy assertions; offline synthetic files only, no live hosting/DB.\n";
} finally { removeTree($root); }
