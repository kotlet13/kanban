<?php
/** Fixed staging-site upgrade. No account enrollment, secret output, shell or cron execution. */
if (PHP_SAPI !== 'cli') { http_response_code(404); exit; }
ini_set('display_errors','0');ini_set('log_errors','0');error_reporting(0);umask(0077);
final class JivieUpgradeFailure extends RuntimeException {}
function fail(string $code): never { throw new JivieUpgradeFailure($code); }
set_error_handler(static function(): never { fail('php_or_filesystem_warning'); });
const SITE='/home/tripar13/jivie-test.triparna.si';
const BASE='/home/tripar13/private/jivie-test';
const WORK=BASE.'/upgrade-0.9.0';
const PUBLIC_SITE='https://jivie-test.triparna.si/';
const STATE=WORK.'/state.json';
const ARCHIVE=WORK.'/FamilyHub-0.9.0-spaces-source-final.zip';
const ARCHIVE_SHA256='a018a4a87c9d32a3bcbf55efc53cf0c856cef825f95f67afd7902ab0d4cc05d3';
const MANIFEST=WORK.'/manifest.json';
const PAUSED=WORK.'/crontab.paused';
const ORIGINAL=WORK.'/crontab.original';
const CURRENT=WORK.'/crontab.current';
function bytes(string $path): string { if(is_link($path)||!is_file($path))fail('file_guard');$v=file_get_contents($path);if($v===false)fail('file_read_failed');return $v; }
function privateDir(string $path): void { if(is_link($path)||!is_dir($path)||realpath($path)!==$path||(fileperms($path)&0077)!==0)fail('private_directory_guard'); }
function writePrivate(string $path,string $value): void { $f=fopen($path,'xb');if(!$f)fail('exclusive_create_failed');try{if(fwrite($f,$value)!==strlen($value)||!fflush($f))fail('private_write_failed');}finally{fclose($f);}chmod($path,0600); }
function replacePrivate(string $path,string $value): void { $temp=$path.'.new';writePrivate($temp,$value);if(!rename($temp,$path))fail('atomic_write_failed'); }
function directory(string $path): void { if(!mkdir($path,0700))fail('directory_create_failed'); }
function data(string $path): array { $v=json_decode(bytes($path),true,64,JSON_THROW_ON_ERROR);if(!is_array($v))fail('json_shape');return $v; }
function json(array $value): string { return json_encode($value,JSON_UNESCAPED_SLASHES|JSON_PRETTY_PRINT|JSON_THROW_ON_ERROR)."\n"; }
function inventory(string $path,array $excluded=[]): array {
    if(is_link($path)||!is_dir($path))fail('tree_guard');$result=[];
    $walk=function(string $dir,string $prefix)use(&$walk,&$result,$excluded){foreach(new DirectoryIterator($dir)as$f){if($f->isDot())continue;$full=$f->getPathname();if(in_array($full,$excluded,true))continue;if($f->isLink())fail('tree_symlink');$relative=$prefix.$f->getFilename();if($f->isDir()){$walk($full,$relative.'/');}elseif($f->isFile()){$result[$relative]=hash_file('sha256',$full);}else fail('tree_entry_guard');}};
    $walk($path,'');ksort($result);return $result;
}
function copyTree(string $from,string $to,array $excluded=[]): void {
    directory($to);foreach(new DirectoryIterator($from)as$f){if($f->isDot())continue;$source=$f->getPathname();if(in_array($source,$excluded,true))continue;if($f->isLink())fail('tree_symlink');$target=$to.'/'.$f->getFilename();if($f->isDir())copyTree($source,$target,$excluded);else writePrivate($target,bytes($source));}
    if(inventory($from,$excluded)!==inventory($to))fail('copied_tree_hash_mismatch');
}
function config(): PDO {
    if(realpath(SITE)!==SITE||realpath(BASE)!==BASE||is_link(SITE)||is_link(BASE))fail('fixed_site_guard');privateDir(WORK);
    // Only the existing config is loaded. Kanboard common.php would migrate too early.
    require_once SITE.'/config.php';
    if(!defined('DB_DRIVER')||DB_DRIVER!=='mysql'||!defined('DB_NAME')||DB_NAME!=='tripar13_jivietest'||!in_array(DB_HOSTNAME,['localhost','127.0.0.1'],true)||!defined('DATA_DIR')||realpath(DATA_DIR)!==BASE.'/data')fail('existing_database_or_data_guard');
    if(defined('FAMILYHUB_DEVELOPMENT_MODE')&&FAMILYHUB_DEVELOPMENT_MODE)fail('development_config_rejected');
    if(!defined('FAMILYHUB_ENABLE_NATIVE_API')||FAMILYHUB_ENABLE_NATIVE_API!==true)fail('native_configuration_guard');
    $dsn='mysql:host='.DB_HOSTNAME.';port='.(defined('DB_PORT')?DB_PORT:3306).';dbname='.DB_NAME.';charset=utf8mb4';
    $pdo=new PDO($dsn,DB_USERNAME,DB_PASSWORD,[PDO::ATTR_TIMEOUT=>10,PDO::ATTR_ERRMODE=>PDO::ERRMODE_EXCEPTION,PDO::ATTR_DEFAULT_FETCH_MODE=>PDO::FETCH_ASSOC]);
    $pdo->exec('SET SESSION lock_wait_timeout=15');$pdo->exec('SET SESSION innodb_lock_wait_timeout=15');
    if(str_contains((string)$pdo->query('SELECT VERSION()')->fetchColumn(),'MariaDB'))$pdo->exec('SET SESSION max_statement_time=30');
    return $pdo;
}
function query(PDO $pdo,string $sql,array $params=[]): array { $q=$pdo->prepare($sql);$q->execute($params);$rows=$q->fetchAll(PDO::FETCH_ASSOC);$q->closeCursor();return $rows; }
function identifier(string $name): string { if(!preg_match('/^[A-Za-z0-9_]+$/D',$name))fail('sql_identifier_guard');return '`'.$name.'`'; }
function columns(PDO $pdo,string $table): array { return query($pdo,'SHOW COLUMNS FROM '.identifier($table)); }
function tableState(PDO $pdo,array $originalColumns=[]): array {
    $state=[];$tables=query($pdo,'SELECT TABLE_NAME,ENGINE FROM information_schema.TABLES WHERE TABLE_SCHEMA=DATABASE() AND TABLE_TYPE=\'BASE TABLE\' ORDER BY TABLE_NAME');
    foreach($tables as$t){if($t['ENGINE']!=='InnoDB')fail('nontransactional_table_requires_review');$name=$t['TABLE_NAME'];if($originalColumns&&!isset($originalColumns[$name]))continue;$defs=columns($pdo,$name);$names=$originalColumns[$name]??array_column($defs,'Field');$key=array_column(array_filter($defs,fn($c)=>$c['Key']==='PRI'),'Field');$order=$key?:$names;
      $sql='SELECT '.implode(',',array_map('identifier',$names)).' FROM '.identifier($name);
      if($name==='plugin_schema_versions')$sql.=" WHERE plugin<>'familyhub'";
      $sql.=' ORDER BY '.implode(',',array_map('identifier',$order));$q=$pdo->query($sql);$hash=hash_init('sha256');$count=0;while($row=$q->fetch(PDO::FETCH_ASSOC)){hash_update($hash,json_encode(array_map(fn($v)=>$v===null?null:base64_encode((string)$v),$row),JSON_THROW_ON_ERROR)."\n");$count++;}$q->closeCursor();$state[$name]=['columns'=>$names,'rows'=>$count,'sha256'=>hash_final($hash)];
    }return $state;
}
function validateNewSchema(PDO $pdo,array $before): void {
    $expected=['familyhub_organization_leaders','familyhub_payment_cash','familyhub_payment_events','familyhub_payment_projections','familyhub_scope_revocations'];
    $all=tableState($pdo);$added=array_values(array_diff(array_keys($all),array_keys($before['tables'])));sort($added);
    if($added!==$expected)fail('unexpected_migration_tables');
    foreach($expected as$table)if($all[$table]['rows']!==0)fail('new_table_not_empty');
    if(query($pdo,'SELECT id FROM familyhub_scopes WHERE access_policy_version<>1 OR access_revision<>0 OR metadata_revision<>0 OR address IS NOT NULL LIMIT 1'))fail('historic_scope_policy_widened');
}
function snapshot(PDO $pdo): array {
    $schema=(int)query($pdo,"SELECT version FROM plugin_schema_versions WHERE plugin='familyhub'")[0]['version'];
    $server=query($pdo,'SELECT server_id FROM familyhub_instance WHERE id=1')[0]['server_id'];
    $accounts=query($pdo,'SELECT user_id,account_id FROM familyhub_accounts ORDER BY user_id');
    if(!$accounts)fail('existing_enrolled_account_required');
    $users=query($pdo,'SELECT id,password FROM users ORDER BY id');
    return ['schema'=>$schema,'serverId'=>$server,'accountHash'=>hash('sha256',json($accounts)),'passwordHash'=>hash('sha256',json($users)),'enrollmentHash'=>hash('sha256',json(query($pdo,'SELECT * FROM familyhub_enrollment ORDER BY id'))),'bootstrapClosed'=>true,'tables'=>tableState($pdo)];
}
function dumpDatabase(PDO $pdo,string $target): void {
    $f=fopen($target,'xb');if(!$f)fail('dump_create_failed');chmod($target,0600);
    try{fwrite($f,"-- Jivie private consistent snapshot; contains personal data and hashes.\nSET NAMES utf8mb4;\nSET FOREIGN_KEY_CHECKS=0;\n");
      foreach(query($pdo,'SELECT TABLE_NAME,ENGINE FROM information_schema.TABLES WHERE TABLE_SCHEMA=DATABASE() AND TABLE_TYPE=\'BASE TABLE\' ORDER BY TABLE_NAME')as$t){if($t['ENGINE']!=='InnoDB')fail('nontransactional_table_requires_review');$table=$t['TABLE_NAME'];$id=identifier($table);$create=query($pdo,'SHOW CREATE TABLE '.$id)[0];fwrite($f,'DROP TABLE IF EXISTS '.$id.";\n".$create['Create Table'].";\n");$defs=columns($pdo,$table);$names=array_column($defs,'Field');$q=$pdo->query('SELECT * FROM '.$id);while($row=$q->fetch(PDO::FETCH_ASSOC)){$values=[];foreach($defs as$col){$v=$row[$col['Field']];if($v===null)$values[]='NULL';elseif(preg_match('/^(?:tinyint|smallint|mediumint|int|integer|bigint|decimal|float|double|real|year)\b/i',$col['Type'])){if(!preg_match('/^-?[0-9]+(?:\.[0-9]+)?(?:[eE][+-]?[0-9]+)?$/D',(string)$v))fail('numeric_dump_guard');$values[]=(string)$v;}else{$values[]="X'".bin2hex((string)$v)."'";}}fwrite($f,'INSERT INTO '.$id.' ('.implode(',',array_map('identifier',$names)).') VALUES ('.implode(',',$values).");\n");}$q->closeCursor();}
      fwrite($f,"SET FOREIGN_KEY_CHECKS=1;\n");if(!fflush($f))fail('dump_flush_failed');
    }finally{fclose($f);}
}
function verifyBundle(): array {
    $m=data(MANIFEST);if(!hash_equals(ARCHIVE_SHA256,hash_file('sha256',ARCHIVE)))fail('pinned_archive_hash');if(($m['format']??null)!=='jivie-familyhub-upgrade-manifest-v1'||($m['pluginVersion']??null)!=='0.9.0'||($m['schemaVersion']??null)!==13||!is_array($m['files']??null)||!hash_equals($m['archiveSha256']??'',hash_file('sha256',ARCHIVE)))fail('bundle_manifest_guard');
    $zip=new ZipArchive();if($zip->open(ARCHIVE)!==true)fail('zip_open');$seen=[];
    try{for($i=0;$i<$zip->numFiles;$i++){$name=$zip->getNameIndex($i);if(!is_string($name)||!preg_match('~^FamilyHub/[A-Za-z0-9_./-]+$~D',$name)||str_contains($name,'..')||str_ends_with($name,'/')||str_ends_with($name,'config.php')||isset($seen[$name])||!isset($m['files'][$name]))fail('zip_path_guard');$stat=$zip->statIndex($i);if(!$zip->getExternalAttributesIndex($i,$opsys,$attributes)||($attributes>>16&0170000)!==0100000)fail('zip_entry_type');$body=$zip->getFromIndex($i);if(!is_string($body)||strlen($body)!==($stat['size']??-1)||hash('crc32b',$body)!==sprintf('%08x',$stat['crc'])||strlen($body)>2097152||!hash_equals($m['files'][$name],hash('sha256',$body)))fail('zip_entry_hash');if(str_ends_with($name,'.php')){if(!function_exists('token_get_all'))fail('tokenizer_required_for_stage_lint');token_get_all($body,TOKEN_PARSE);}$seen[$name]=true;}if(count($seen)!==count($m['files']))fail('zip_manifest_count');}finally{$zip->close();}return $m;
}
function pauseCandidate(): void {
    $scripts=['reminders.php','delivery.php','account-mail.php','account-deletion-cleanup.php','push.php'];$counts=array_fill_keys($scripts,0);
    $original=bytes(ORIGINAL);$out='';
    foreach(preg_split('/(?<=\n)/',$original,-1,PREG_SPLIT_NO_EMPTY)as$line){
      $matches=[];if(!str_starts_with(ltrim($line),'#'))foreach($scripts as$script)if(preg_match('~'.preg_quote(SITE.'/plugins/FamilyHub/cli/'.$script,'~').'(?=\s|$)~',$line))$matches[]=$script;
      if(count($matches)>1)fail('combined_worker_cron_requires_review');
      if($matches){$counts[$matches[0]]++;$out.='# Jivie upgrade paused: '.$line;}else$out.=$line;
    }
    foreach($counts as$count)if($count!==1)fail('exact_five_distinct_staging_crons_required');writePrivate(PAUSED,$out);
}
function maintenance(): void {
    $path=SITE.'/.htaccess';$old=is_file($path)?bytes($path):null;writePrivate(WORK.'/htaccess.original',json(['existed'=>$old!==null,'bytes'=>$old===null?null:base64_encode($old)]));
    $text="# JIVIE STAGING UPGRADE MAINTENANCE\nRewriteEngine On\nRewriteRule ^ - [R=503,L]\n".($old??'');$tmp=$path.'.jivie-upgrade';writePrivate($tmp,$text);chmod($tmp,0644);if(!rename($tmp,$path))fail('maintenance_activate');writePrivate(WORK.'/maintenance.sha256',hash('sha256',$text));
}
function verifyMaintenance(): void {
    if(!function_exists('curl_init'))fail('curl_required_for_maintenance_proof');
    $h=curl_init(PUBLIC_SITE.'index.php');curl_setopt_array($h,[CURLOPT_RETURNTRANSFER=>true,CURLOPT_FOLLOWLOCATION=>false,CURLOPT_CONNECTTIMEOUT=>10,CURLOPT_TIMEOUT=>20,CURLOPT_SSL_VERIFYPEER=>true,CURLOPT_SSL_VERIFYHOST=>2]);
    $body=curl_exec($h);$status=curl_getinfo($h,CURLINFO_HTTP_CODE);curl_close($h);if($body===false||$status!==503)fail('public_maintenance_503_not_verified');
}
function unchangedConfig(array $state): void { foreach($state['configHashes']as$path=>$hash){if(!hash_equals($hash,hash_file('sha256',$path)))fail('configuration_changed');} }
function restoreMaintenance(): void {
    if(!is_file(WORK.'/htaccess.original'))return;
    if(hash_file('sha256',SITE.'/.htaccess')!==trim(bytes(WORK.'/maintenance.sha256')))fail('maintenance_changed');
    $original=data(WORK.'/htaccess.original');
    if($original['existed']){replacePrivate(SITE.'/.htaccess',base64_decode($original['bytes'],true));chmod(SITE.'/.htaccess',0644);}
    elseif(!unlink(SITE.'/.htaccess'))fail('maintenance_remove');
}
function abortGuard(PDO $pdo,array $state): void {
    if(!in_array($state['phase'],['prepared','paused','snapshot'],true)||is_dir(WORK.'/code-original'))fail('abort_before_activation_only');
    unchangedConfig($state);
    if(inventory(SITE.'/plugins/FamilyHub')!==$state['codeHashes']||(int)query($pdo,"SELECT version FROM plugin_schema_versions WHERE plugin='familyhub'")[0]['version']!==11)fail('abort_original_code_and_schema_required');
    $current=hash_file('sha256',CURRENT);
    if($current!==hash_file('sha256',ORIGINAL)&&$current!==hash_file('sha256',PAUSED))fail('abort_crons_changed');
    if(is_file(WORK.'/htaccess.original')&&hash_file('sha256',SITE.'/.htaccess')!==trim(bytes(WORK.'/maintenance.sha256')))fail('maintenance_changed');
}
function cronProof(): void { if(!hash_equals(hash_file('sha256',PAUSED),hash_file('sha256',CURRENT))||!is_file(WORK.'/crontab.paused-applied'))fail('cron_pause_proof_required'); }
function validateRestoreProof(array $proof,array $state,array $privateInventory): void {
    if (($proof['verifiedInIsolatedLocalDb']??false)!==true ||
        ($proof['sqlSha']??null)!==$state['sqlSha'] ||
        ($proof['privateSha']??null)!==$state['privateSha'] ||
        ($proof['serverId']??null)!==$state['before']['serverId'] ||
        ($proof['restoredSnapshot']??null)!==$state['before'] ||
        ($proof['restoredPrivateInventory']??null)!==$privateInventory) {
        fail('isolated_restore_proof_required');
    }
}
function manifestLocal(string $zipPath,string $output): void {
    $zip=new ZipArchive();if($zip->open($zipPath)!==true)fail('zip_open');$files=[];for($i=0;$i<$zip->numFiles;$i++){$name=$zip->getNameIndex($i);$body=$zip->getFromIndex($i);if(!is_string($name)||!is_string($body))fail('zip_entry');$files[$name]=hash('sha256',$body);}ksort($files);$zip->close();writePrivate($output,json(['format'=>'jivie-familyhub-upgrade-manifest-v1','pluginVersion'=>'0.9.0','schemaVersion'=>13,'archiveSha256'=>hash_file('sha256',$zipPath),'files'=>$files]));
}
try{
    $mode=$argv[1]??'';
    if($mode==='--manifest'){if(count($argv)!==4)fail('manifest_arguments');manifestLocal($argv[2],$argv[3]);echo "Manifest prepared locally.\n";exit;}
    privateDir(WORK);$lock=fopen(WORK.'/helper.lock','c');if(!$lock||!flock($lock,LOCK_EX|LOCK_NB))fail('concurrent_upgrade_operation');
    $pdo=config();
    if($mode==='--prepare'){
      if(is_file(STATE))fail('existing_upgrade_state');$bundle=verifyBundle();$before=snapshot($pdo);if($before['schema']!==11)fail('schema_11_required');
      $caps=data(WORK.'/before-capabilities.json');$caps=$caps['data']??$caps;if(($caps['serverId']??null)!==$before['serverId']||($caps['features']['accountEnrollment']??null)!==false)fail('captured_identity_guard');
      directory(WORK.'/stage');$zip=new ZipArchive();$zip->open(ARCHIVE);foreach($bundle['files']as$name=>$hash){$to=WORK.'/stage/'.$name;$parent=dirname($to);if(!is_dir($parent)&&!mkdir($parent,0700,true))fail('stage_directory');writePrivate($to,$zip->getFromName($name));}$zip->close();pauseCandidate();
      $configs=[SITE.'/config.php'];foreach(get_included_files()as$file){if($file!==__FILE__&&is_file($file))$configs[]=$file;}$hashes=[];foreach(array_unique($configs)as$file)$hashes[$file]=hash_file('sha256',$file);
      writePrivate(STATE,json(['phase'=>'prepared','before'=>$before,'bundleSha'=>$bundle['archiveSha256'],'codeHashes'=>inventory(SITE.'/plugins/FamilyHub'),'configHashes'=>$hashes]));echo "Prepared stage, manifest and five-cron pause candidate. Site unchanged.\n";
    }elseif($mode==='--record-paused'){
      if(data(STATE)['phase']!=='prepared')fail('prepared_phase_required');
      if(!hash_equals(hash_file('sha256',PAUSED),hash_file('sha256',CURRENT)))fail('cron_candidate_mismatch');writePrivate(WORK.'/crontab.paused-applied',hash_file('sha256',PAUSED));maintenance();verifyMaintenance();writePrivate(WORK.'/maintenance.started',(string)time());$s=data(STATE);$s['phase']='paused';replacePrivate(STATE,json($s));echo "Cron pause and public maintenance verified. Drain before snapshot.\n";
    }elseif($mode==='--snapshot'){
      $s=data(STATE);if($s['phase']!=='paused')fail('phase_guard');cronProof();unchangedConfig($s);if(time()-(int)trim(bytes(WORK.'/maintenance.started'))<65)fail('maintenance_drain_65_seconds_required');verifyMaintenance();
      if(!is_file(WORK.'/workers.drained')||trim(bytes(WORK.'/workers.drained'))!==hash_file('sha256',PAUSED)||time()-filemtime(WORK.'/workers.drained')>30)fail('fresh_worker_drain_proof_required');
      $tableNames=array_column(query($pdo,'SELECT TABLE_NAME FROM information_schema.TABLES WHERE TABLE_SCHEMA=DATABASE() AND TABLE_TYPE=\'BASE TABLE\' ORDER BY TABLE_NAME'),'TABLE_NAME');
      // Whole-DB read locks wait out in-flight SQL writers and prevent further
      // changes while both files and SQL are captured. No shell process is used.
      $pdo->exec('LOCK TABLES '.implode(',',array_map(fn($table)=>identifier($table).' READ',$tableNames)));
      try {
        directory(WORK.'/backup');copyTree(SITE.'/plugins/FamilyHub',WORK.'/backup/FamilyHub');copyTree(BASE,WORK.'/backup/private',[WORK]);writePrivate(WORK.'/backup/config.php',bytes(SITE.'/config.php'));
        if(is_dir(SITE.'/data'))copyTree(SITE.'/data',WORK.'/backup/site-data');
        $s['before']=snapshot($pdo);dumpDatabase($pdo,WORK.'/backup/database.sql');if(inventory(BASE,[WORK])!==inventory(WORK.'/backup/private'))fail('files_changed_during_locked_snapshot');if(snapshot($pdo)!==$s['before'])fail('data_changed_during_locked_snapshot');
        $s['freezeEvidence']=['maintenance503'=>true,'fiveWorkerCronsPaused'=>true,'freshNoActiveStagingPhpProcessProof'=>true,'mysqlAllTablesReadLocked'=>true];
      } finally { $pdo->exec('UNLOCK TABLES'); }
      $s['sqlSha']=hash_file('sha256',WORK.'/backup/database.sql');$s['privateSha']=hash('sha256',json(inventory(WORK.'/backup/private')));$s['phase']='snapshot';replacePrivate(STATE,json($s));echo "Private consistent snapshot ready. Keep maintenance and paused crons until isolated restore is verified.\n";
    }elseif($mode==='--bundle-backup'){
      $s=data(STATE);if($s['phase']!=='snapshot')fail('snapshot_phase_required');
      if(hash_file('sha256',WORK.'/backup/database.sql')!==$s['sqlSha']||hash('sha256',json(inventory(WORK.'/backup/private')))!==$s['privateSha'])fail('snapshot_changed');
      $public=['format'=>'jivie-upgrade-backup-evidence-v1','schema'=>$s['before']['schema'],'serverId'=>$s['before']['serverId'],'bootstrapClosed'=>true,'sqlSha'=>$s['sqlSha'],'privateSha'=>$s['privateSha'],'rows'=>array_map(fn($table)=>$table['rows'],$s['before']['tables']),'freezeEvidence'=>$s['freezeEvidence']];
      writePrivate(WORK.'/backup-metadata.json',json($public));
      $zipPath=WORK.'/Jivie-private-upgrade-backup.zip';if(is_file($zipPath))fail('backup_zip_exists');$zip=new ZipArchive();if($zip->open($zipPath,ZipArchive::CREATE|ZipArchive::EXCL)!==true)fail('backup_zip_create');
      try { foreach(inventory(WORK.'/backup')as$relative=>$hash){if(!$zip->addFile(WORK.'/backup/'.$relative,'backup/'.$relative))fail('backup_zip_entry');}
        foreach(['state.json','htaccess.original','maintenance.sha256','crontab.original','crontab.paused','backup-metadata.json']as$file){if(!$zip->addFile(WORK.'/'.$file,$file))fail('backup_zip_metadata');}
      }finally{if(!$zip->close())fail('backup_zip_close');}chmod($zipPath,0600);
      writePrivate(WORK.'/Jivie-private-upgrade-backup.zip.sha256',hash_file('sha256',$zipPath)."  Jivie-private-upgrade-backup.zip\n");
      echo "Single private backup ZIP and secret-free metadata prepared outside web roots. Download only to a private location.\n";
    }elseif($mode==='--activate'){
      $s=data(STATE);if($s['phase']!=='snapshot')fail('phase_guard');cronProof();unchangedConfig($s);verifyMaintenance();
      if(inventory(BASE,[WORK])!==inventory(WORK.'/backup/private'))fail('private_files_changed_since_snapshot');
      $nowState=snapshot($pdo);$oldCols=array_map(fn($table)=>$table['columns'],$s['before']['tables']);if(tableState($pdo,$oldCols)!==$s['before']['tables']||$nowState['schema']!==11)fail('database_changed_since_snapshot');validateRestoreProof(data(WORK.'/restore-proof.json'),$s,inventory(WORK.'/backup/private'));
      if(hash_file('sha256',SITE.'/.htaccess')!==trim(bytes(WORK.'/maintenance.sha256')))fail('maintenance_changed');$bundle=verifyBundle();if($bundle['archiveSha256']!==$s['bundleSha'])fail('bundle_changed');$expectedFiles=[];foreach($bundle['files']as$name=>$hash)$expectedFiles[substr($name,strlen('FamilyHub/'))]=$hash;ksort($expectedFiles);if(inventory(WORK.'/stage/FamilyHub')!==$expectedFiles)fail('staged_tree_changed');
      if(!rename(SITE.'/plugins/FamilyHub',WORK.'/code-original'))fail('old_code_move');if(!rename(WORK.'/stage/FamilyHub',SITE.'/plugins/FamilyHub')){rename(WORK.'/code-original',SITE.'/plugins/FamilyHub');fail('new_code_move');}
      $s['phase']='code-swapped';replacePrivate(STATE,json($s));
      $s['phase']='migration-started';replacePrivate(STATE,json($s));
      require SITE.'/plugins/FamilyHub/Schema/SpacesSchema.php';\Kanboard\Plugin\FamilyHub\Schema\SpacesSchema::create($pdo,true);
      require SITE.'/plugins/FamilyHub/Schema/LinkedPaymentsSchema.php';\Kanboard\Plugin\FamilyHub\Schema\LinkedPaymentsSchema::create($pdo,true);
      $pdo->prepare("UPDATE plugin_schema_versions SET version=13 WHERE plugin='familyhub' AND version=11")->execute();
      $after=snapshot($pdo);$oldCols=array_map(fn($table)=>$table['columns'],$s['before']['tables']);$afterTables=tableState($pdo,$oldCols);
      if($after['schema']!==13||$after['serverId']!==$s['before']['serverId']||$after['accountHash']!==$s['before']['accountHash']||$after['passwordHash']!==$s['before']['passwordHash']||$after['enrollmentHash']!==$s['before']['enrollmentHash']||$afterTables!==$s['before']['tables'])fail('post_migration_identity_or_data_changed');
      validateNewSchema($pdo,$s['before']);unchangedConfig($s);$s['phase']='healthy';$s['after']=$after;replacePrivate(STATE,json($s));echo "Schema 13 and code activated under maintenance; existing identities, passwords, config and data verified. No account or email created.\n";
    }elseif($mode==='--pre-release'){
      $s=data(STATE);if($s['phase']!=='healthy')fail('healthy_phase_required');cronProof();unchangedConfig($s);verifyMaintenance();
      if(inventory(BASE,[WORK])!==inventory(WORK.'/backup/private'))fail('private_files_changed_since_snapshot');
      if(hash_file('sha256',SITE.'/.htaccess')!==trim(bytes(WORK.'/maintenance.sha256')))fail('maintenance_changed');
      if((int)query($pdo,"SELECT version FROM plugin_schema_versions WHERE plugin='familyhub'")[0]['version']!==13)fail('schema_13_required');
      $oldCols=array_map(fn($table)=>$table['columns'],$s['before']['tables']);if(tableState($pdo,$oldCols)!==$s['before']['tables'])fail('data_changed_before_release');validateNewSchema($pdo,$s['before']);
      echo "Pre-release guard passed; original cron restore may now precede maintenance release.\n";
    }elseif($mode==='--release'){
      $s=data(STATE);if($s['phase']!=='healthy')fail('healthy_phase_required');unchangedConfig($s);if(!hash_equals(hash_file('sha256',ORIGINAL),hash_file('sha256',CURRENT)))fail('exact_original_crons_not_restored');
      restoreMaintenance();$s['phase']='released';replacePrivate(STATE,json($s));echo "Exact original cron/config retained and maintenance released. Verify public capabilities and the existing device separately.\n";
    }elseif($mode==='--abort-check'||$mode==='--abort'){
      $s=data(STATE);abortGuard($pdo,$s);
      if($mode==='--abort-check'){echo "Original code/schema/config verified. Only this upgrade's paused cron lines may be resumed.\n";}
      else{if(hash_file('sha256',CURRENT)!==hash_file('sha256',ORIGINAL))fail('exact_original_crons_not_restored');restoreMaintenance();$s['phase']='aborted';replacePrivate(STATE,json($s));echo "Original site resumed; no database or private data restored or removed.\n";}
    }elseif($mode==='--capture-recovery'){
      $s=data(STATE);if(!in_array($s['phase'],['code-swapped','migration-started','healthy'],true))fail('recovery_requires_paused_upgrade');cronProof();unchangedConfig($s);verifyMaintenance();
      // Capture every write and partial DDL before a human-directed repair. No restore/drop/reset is performed.
      $target=WORK.'/recovery-'.gmdate('Ymd-His');directory($target);
      dumpDatabase($pdo,$target.'/database.sql');copyTree(BASE,$target.'/private',[WORK]);copyTree(SITE.'/plugins/FamilyHub',$target.'/FamilyHub');
      writePrivate($target.'/state.json',json($s));echo "Current database, private files and active code retained privately. Maintenance remains. Never restore old SQL over later writes or account deletions.\n";
    }elseif($mode==='--rollback-code'){
      $s=data(STATE);if($s['phase']!=='code-swapped')fail('rollback_after_migration_requires_verified_database_restore');
      if((int)query($pdo,"SELECT version FROM plugin_schema_versions WHERE plugin='familyhub'")[0]['version']!==11)fail('rollback_after_migration_requires_verified_database_restore');
      if(!rename(SITE.'/plugins/FamilyHub',WORK.'/code-rejected')||!rename(WORK.'/code-original',SITE.'/plugins/FamilyHub'))fail('rollback_code_move');$s['phase']='snapshot';replacePrivate(STATE,json($s));echo "Original code restored; maintenance remains. Database/file restore and exact cron recovery are explicit owner operations.\n";
    }elseif($mode==='--check'){
      verifyBundle();$s=snapshot($pdo);if($s['schema']!==11)fail('schema_11_required');echo "Fixed staging site/config/database and upload manifest verified. Application site unchanged; private helper lock only.\n";
    }else fail('unknown_mode');
}catch(JivieUpgradeFailure$e){fwrite(STDERR,'Upgrade stopped: '.$e->getMessage().".\n");exit(1);}catch(Throwable$e){fwrite(STDERR,"Upgrade stopped: private diagnostic required; no exception or secret was logged.\n");exit(1);}
