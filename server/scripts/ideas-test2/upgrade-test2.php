<?php
/** Fixed test2 additive upgrade, derived from reviewed private backup/deploy guards. */
if(PHP_SAPI!=='cli'){http_response_code(404);exit;}
ini_set('display_errors','0');ini_set('log_errors','0');error_reporting(0);umask(0077);
final class Test2UpgradeStop extends RuntimeException{}
function stop(string $code):never{throw new Test2UpgradeStop($code);}
set_error_handler(static function():never{stop('php_or_filesystem_warning');});
const SITE='/home/tripar13/jivie-test2.triparna.si';
const BASE='/home/tripar13/private/jivie-test2';
const WORK=BASE.'/upgrade-0.13.0';
const CONFIG=BASE.'/config.php';
const DATA=BASE.'/data';
const STATE=WORK.'/state.json';
const MARKER=BASE.'/install/deploy-0.11.2/native-api.enabled';
const PAUSED=WORK.'/native-api.paused';
const CONFIG_SHA='6886ea49c2735c48150ea466a11309d3e3e832a7110783e28a33b91d02b1416a';
const MARKER_SHA='81be8fabad0dbf59d7b7df1074556d45598b02112979d37c366e90133ec82f5b';
const ARCHIVE=WORK.'/FamilyHub-0.13.0-source.zip';
const ARCHIVE_SHA='00df4cec3baebb66d4e67adad20c235149529b2ee9853b614b0a74ef85cfbe52';
const MANIFEST=WORK.'/source-manifests.json';
const MANIFEST_SHA='8eb3f1d438b16b60b19fdf48368e64bc92bbffee147790828cb4789f129a3941';
const RESTORE_PROOF=WORK.'/restore-proof.json';
const SERVER_ID='f48b41ae-c6bb-4f2d-ae13-0aa7fa255993';
const NEW_TABLE_COLUMNS=[
 'familyhub_idea_assets'=>['scope_id','board_id','sha256','owner_account_id','mime','size','width','height','received','complete','published','data','created_at','updated_at'],
 'familyhub_idea_report_assets'=>['report_id','scope_id','board_id','sha256']
];
function bytes(string $p):string{if(is_link($p)||!is_file($p)||!is_readable($p))stop('file_guard');$v=file_get_contents($p);if(!is_string($v))stop('file_read');return $v;}
function directory(string $p,bool $private=false):void{if(is_link($p)||!is_dir($p)||realpath($p)!==$p||fileowner($p)!==fileowner(SITE))stop('directory_owner_guard');if($private&&(fileperms($p)&0077)!==0)stop('private_mode_guard');}
function fresh(string $p):void{if(file_exists($p)||is_link($p))stop('exclusive_destination_guard');}
function makeDir(string $p):void{fresh($p);if(!mkdir($p,0700))stop('directory_create');chmod($p,0700);}
function writePrivate(string $p,string $v,int $mode=0600):void{fresh($p);$f=fopen($p,'xb');if(!$f)stop('exclusive_create');try{if(fwrite($f,$v)!==strlen($v)||!fflush($f))stop('private_write');}finally{fclose($f);}chmod($p,$mode);}
function json(array $v):string{return json_encode($v,JSON_PRETTY_PRINT|JSON_UNESCAPED_SLASHES|JSON_THROW_ON_ERROR)."\n";}
function readJson(string $p):array{$v=json_decode(bytes($p),true,64,JSON_THROW_ON_ERROR);if(!is_array($v))stop('json_guard');return $v;}
function save(array $s):void{$tmp=STATE.'.next';writePrivate($tmp,json($s));if(!rename($tmp,STATE))stop('state_replace');}
function state():array{$s=readJson(STATE);if(($s['format']??null)!=='test2-ideas-upgrade-v1')stop('state_format');return $s;}
function inventory(string $root,array $skip=[]):array{
 directory($root);$out=[];$walk=function(string $d,string $prefix)use(&$walk,&$out,$skip){foreach(new DirectoryIterator($d)as$f){if($f->isDot())continue;$r=$prefix.$f->getFilename();if(in_array($r,$skip,true))continue;if($f->isLink())stop('tree_symlink');if($f->isDir())$walk($f->getPathname(),$r.'/');elseif($f->isFile())$out[$r]=['bytes'=>$f->getSize(),'sha256'=>hash('sha256',bytes($f->getPathname()))];else stop('tree_type');}};$walk($root,'');ksort($out);return $out;
}
function hashes(string $root):array{$out=[];foreach(inventory($root)as$n=>$v)$out[$n]=$v['sha256'];return $out;}
function directories(string $root):array{$out=[];foreach(new RecursiveIteratorIterator(new RecursiveDirectoryIterator($root,FilesystemIterator::SKIP_DOTS),RecursiveIteratorIterator::SELF_FIRST)as$f){if($f->isLink())stop('tree_symlink');if($f->isDir())$out[]=substr($f->getPathname(),strlen($root)+1);}sort($out,SORT_STRING);return $out;}
function copyPrivate(string $from,string $to):void{makeDir($to);foreach(new DirectoryIterator($from)as$f){if($f->isDot())continue;if($f->isLink())stop('copy_symlink');$dest=$to.'/'.$f->getFilename();if($f->isDir())copyPrivate($f->getPathname(),$dest);elseif($f->isFile())writePrivate($dest,bytes($f->getPathname()),0644);else stop('copy_type');}if(hashes($from)!==hashes($to))stop('copied_source_hash');}
function id(string $v):string{if(!preg_match('/^[a-zA-Z0-9_]+$/D',$v))stop('sql_identifier');return '`'.$v.'`';}
function rows(PDO $p,string $sql):array{$q=$p->query($sql);$v=$q->fetchAll(PDO::FETCH_ASSOC);$q->closeCursor();return $v;}
function db():PDO{
 directory(SITE);foreach([BASE,DATA,WORK,BASE.'/install/deploy-0.11.2']as$d)directory($d,true);
 if((fileperms(CONFIG)&0777)!==0600||hash('sha256',bytes(CONFIG))!==CONFIG_SHA||file_exists(SITE.'/data/config.php'))stop('config_hash_or_secondary_config');
 define('TEST2_DEPLOY_BOOTSTRAP',true);require CONFIG; // Config only: permits guarded CLI while marker is paused.
 if(DB_DRIVER!=='mysql'||DB_NAME!=='tripar13_jivietest2'||!in_array(DB_HOSTNAME,['localhost','127.0.0.1'],true)||DATA_DIR!==DATA||FILES_DIR!==DATA.'/files'||CACHE_DIR!==DATA.'/cache'||FAMILYHUB_ACCOUNT_MODE!=='self_hosted'||FAMILYHUB_ENABLE_PROJECT_INVITATIONS!==false||FAMILYHUB_ENABLE_FCM!==false)stop('fixed_test2_database_paths');
 foreach(get_defined_constants()as$n=>$v)if(str_starts_with($n,'FAMILYHUB_SMTP_')||str_starts_with($n,'FAMILYHUB_DEVELOPMENT'))stop('smtp_or_development_rejected');
 $port=defined('DB_PORT')&&DB_PORT?DB_PORT:3306;$p=new PDO('mysql:host='.DB_HOSTNAME.';port='.$port.';dbname='.DB_NAME.';charset=utf8mb4',DB_USERNAME,DB_PASSWORD,[PDO::ATTR_ERRMODE=>PDO::ERRMODE_EXCEPTION,PDO::ATTR_TIMEOUT=>10,PDO::ATTR_DEFAULT_FETCH_MODE=>PDO::FETCH_ASSOC]);
 if($p->query('SELECT DATABASE()')->fetchColumn()!=='tripar13_jivietest2'||strtoupper((string)$p->query('SELECT @@default_storage_engine')->fetchColumn())!=='INNODB')stop('actual_database_or_engine');$p->exec('SET SESSION lock_wait_timeout=15');return $p;
}
function identity(PDO $p,int $schema):array{
 $sid=$p->query('SELECT server_id FROM familyhub_instance WHERE id=1')->fetchColumn();$version=(int)$p->query("SELECT version FROM plugin_schema_versions WHERE plugin='familyhub'")->fetchColumn();$accts=(int)$p->query('SELECT COUNT(*) FROM familyhub_accounts')->fetchColumn();if($sid!==SERVER_ID||$version!==$schema||$accts<1)stop('server_identity_or_schema');return ['serverId'=>$sid,'schema'=>$version,'nativeAccounts'=>$accts,'nativeDevices'=>(int)$p->query('SELECT COUNT(*) FROM familyhub_devices')->fetchColumn()];
}
function defs(PDO $p):array{
 $out=[];foreach(rows($p,"SELECT TABLE_NAME,ENGINE FROM information_schema.TABLES WHERE TABLE_SCHEMA=DATABASE() AND TABLE_TYPE='BASE TABLE' ORDER BY TABLE_NAME")as$t){if($t['ENGINE']!=='InnoDB')stop('all_tables_innodb');$name=$t['TABLE_NAME'];$c=rows($p,'SHOW COLUMNS FROM '.id($name));$names=array_column($c,'Field');$keys=array_column(array_filter($c,fn($v)=>$v['Key']==='PRI'),'Field');$out[$name]=['columns'=>$names,'types'=>array_column($c,'Type'),'order'=>$keys?:$names,'createSha256'=>hash('sha256',rows($p,'SHOW CREATE TABLE '.id($name))[0]['Create Table'])];}return $out;
}
function snapshot(PDO $p,array $defs):array{
 $out=[];foreach($defs as$n=>$d){$q=$p->query('SELECT '.implode(',',array_map('id',$d['columns'])).' FROM '.id($n).' ORDER BY '.implode(',',array_map('id',$d['order'])));$h=hash_init('sha256');$count=0;while($r=$q->fetch(PDO::FETCH_ASSOC)){hash_update($h,json_encode(array_map(fn($v)=>$v===null?null:base64_encode((string)$v),$r),JSON_UNESCAPED_SLASHES|JSON_THROW_ON_ERROR)."\n");$count++;}$q->closeCursor();$out[$n]=['columns'=>$d['columns'],'order'=>$d['order'],'types'=>$d['types'],'rows'=>$count,'sha256'=>hash_final($h),'createSha256'=>$d['createSha256']];}return $out;
}
function gdPreflight():array{
 foreach(['gd_info','imagecreatetruecolor','imagecreatefromstring','imagepng','imagejpeg','imagecopyresampled','imagerotate','imagestring','imagecolorallocatealpha']as$fn)if(!function_exists($fn))stop('gd_png_jpeg_required');$info=gd_info();if(empty($info['PNG Support'])||empty($info['JPEG Support']))stop('gd_png_jpeg_required');
 foreach(['imagepng','imagejpeg']as$encoder){$image=imagecreatetruecolor(2,2);imagefill($image,0,0,imagecolorallocate($image,20,100,220));ob_start();$encoder($image);$bytes=ob_get_clean();imagedestroy($image);$decoded=imagecreatefromstring($bytes);if(!$decoded||imagesx($decoded)!==2||imagesy($decoded)!==2)stop('gd_roundtrip_failed');imagedestroy($decoded);}return ['png'=>true,'jpeg'=>true];
}
function sourceManifest():array{
 if(hash('sha256',bytes(MANIFEST))!==MANIFEST_SHA)stop('manifest_hash');$m=readJson(MANIFEST);if(count($m['old']??[])!==91||count($m['new']??[])!==96)stop('manifest_counts');return $m;
}
function package():array{
 $m=sourceManifest()['new'];if(!class_exists(ZipArchive::class)||!function_exists('token_get_all'))stop('zip_and_tokenizer_required');if(hash('sha256',bytes(ARCHIVE))!==ARCHIVE_SHA)stop('archive_hash');$z=new ZipArchive();if($z->open(ARCHIVE,ZipArchive::RDONLY)!==true)stop('archive_open');$out=[];
 try{if($z->numFiles!==96)stop('zip_entry_count');for($i=0;$i<$z->numFiles;$i++){$s=$z->statIndex($i);$name=$s['name']??'';if(!str_starts_with($name,'FamilyHub/'))stop('zip_prefix');$r=substr($name,10);if(!isset($m[$r])||isset($out[$r]))stop('zip_allowlist');if(!$z->getExternalAttributesIndex($i,$os,$attrs)||($attrs>>16&0170000)!==0100000)stop('zip_file_type');$b=$z->getFromIndex($i);if(!is_string($b)||strlen($b)!==($s['size']??-1)||strlen($b)>2097152||hash('crc32b',$b)!==sprintf('%08x',$s['crc'])||hash('sha256',$b)!==$m[$r])stop('zip_entry_hash_crc');if(str_ends_with($r,'.php'))token_get_all($b,TOKEN_PARSE);$out[$r]=$b;}}finally{$z->close();}return $out;
}
function marker(bool $paused):void{
 $p=$paused?PAUSED:MARKER;$other=$paused?MARKER:PAUSED;if(file_exists($other)||is_link($other)||hash('sha256',bytes($p))!==MARKER_SHA||(fileperms($p)&0777)!==0600||FAMILYHUB_ENABLE_NATIVE_API!==!$paused)stop('enabled_or_paused_marker_guard');
}
function backup(string $path,string $sha):array{
 if(!preg_match('/^[a-f0-9]{64}$/D',$sha)||!preg_match('~^'.preg_quote(BASE,'~').'/backups/ideas-preupgrade-20261012-[0-9]{8}-[0-9]{6}-[a-f0-9]{8}/Test2-private-backup\.zip$~D',$path))stop('fixed_private_backup_path');directory(dirname($path),true);if((fileperms($path)&0077)!==0||hash('sha256',bytes($path))!==$sha)stop('backup_archive_hash');
 $z=new ZipArchive();if($z->open($path,ZipArchive::RDONLY)!==true)stop('backup_zip_open');try{$txt=$z->getFromName('manifest.json');if(!is_string($txt))stop('backup_manifest_missing');$m=json_decode($txt,true,64,JSON_THROW_ON_ERROR);}finally{$z->close();}
 if(($m['format']??null)!=='test2-ideas-preupgrade-backup-v1'||($m['identity']['serverId']??null)!==SERVER_ID||($m['identity']['schema']??null)!==16||($m['database']??null)!=='tripar13_jivietest2'||($m['privateConfigSha256']??null)!==CONFIG_SHA||($m['markerSha256']??null)!==MARKER_SHA)stop('backup_manifest_identity');
 $created=strtotime((string)($m['createdUtc']??''));if($created===false || time()-$created>21600 || $created>time()+300)stop('fresh_backup_required');
 $proof=readJson(RESTORE_PROOF);$expected=['format'=>'test2-ideas-preupgrade-restore-proof-v1','archiveSha256'=>$sha,'sqlSha256'=>$m['databaseSqlSha256'],'serverId'=>SERVER_ID,'schema'=>16,'database'=>'MariaDB 10.11.19','isolatedNetwork'=>'none','ports'=>false,'hostBindMounts'=>false,'onlyAnonymousMysqlVolume'=>true,'tablesVerified'=>count($m['tables']),'rowsVerified'=>array_sum(array_column($m['tables'],'rows')),'privateFilesVerified'=>count($m['dataFiles']),'privateDirectoriesVerified'=>count($m['dataDirectories']),'everyRowAndFileHashMatches'=>true,'everyTableDefinitionHashMatches'=>true,'passwordsAccountsSessionsRecordsPreserved'=>true,'privateConfigAndEnabledMarkerHashesMatch'=>true,'applicationOrWorkersStarted'=>false,'liveHostedDatabaseTouched'=>false];foreach($expected as$k=>$v)if(!array_key_exists($k,$proof)||$proof[$k]!==$v)stop('actual_restore_proof_guard');if((fileperms(RESTORE_PROOF)&0077)!==0)stop('proof_private_mode');return $m;
}
function originalDb(PDO $p,array $anchor):void{
 $d=defs($p);if(snapshot($p,$d)!==$anchor['tables'])stop('old_database_differs_from_verified_backup');if(inventory(DATA)!==$anchor['dataFiles']||directories(DATA)!==$anchor['dataDirectories'])stop('data_differs_from_verified_backup');if(hash('sha256',bytes(SITE.'/config.php'))!==$anchor['rootConfigSha256']||hash('sha256',bytes(SITE.'/.htaccess'))!==$anchor['rootHtaccessSha256'])stop('original_root_config_or_https_changed');
 foreach(array_keys(NEW_TABLE_COLUMNS)as$t)if(isset($d[$t]))stop('idea_tables_already_exist');identity($p,16);
}
function schemaRows(PDO $p):array{$v=rows($p,'SELECT * FROM plugin_schema_versions ORDER BY plugin');foreach($v as&$r)$r['version']=(int)$r['version'];unset($r);return $v;}
function staged(array $s):array{
 $m=backup($s['backupPath'],$s['backupSha256']);if(hash('sha256',bytes(RESTORE_PROOF))!==$s['restoreProofSha256'])stop('restore_proof_changed');if(hashes(WORK.'/stage/FamilyHub')!==sourceManifest()['new']||hashes(WORK.'/FamilyHub.before')!==sourceManifest()['old'])stop('staged_or_backup_code_changed');return $m;
}
function preserved(PDO $p,array $s,bool $schema17):void{
 $d=defs($p);$old=$s['tables'];$all=array_keys($old);foreach(NEW_TABLE_COLUMNS as$t=>$cols){if(!isset($d[$t])||$d[$t]['columns']!==$cols||(int)$p->query('SELECT COUNT(*) FROM '.id($t))->fetchColumn()!==0)stop('two_new_empty_tables_guard');$all[]=$t;}sort($all,SORT_STRING);$actualNames=array_keys($d);sort($actualNames,SORT_STRING);if($actualNames!==$all)stop('unexpected_new_or_removed_tables');
 $oldDefs=array_intersect_key($d,$old);$now=snapshot($p,$oldDefs);$expected=$old;unset($now['plugin_schema_versions'],$expected['plugin_schema_versions']);if($now!==$expected||$d['plugin_schema_versions']['createSha256']!==$old['plugin_schema_versions']['createSha256'])stop('historic_rows_or_definitions_changed');
 $psr=$s['pluginSchemaRows'];if($schema17)foreach($psr as&$r){if($r['plugin']==='familyhub')$r['version']=17;}unset($r);if(schemaRows($p)!==$psr)stop('plugin_version_rows_guard');
 $who=identity($p,$schema17?17:16);if($who['nativeAccounts']!==$s['identity']['nativeAccounts']||$who['nativeDevices']!==$s['identity']['nativeDevices'])stop('accounts_or_devices_changed');if(inventory(DATA)!==$s['dataFiles']||directories(DATA)!==$s['dataDirectories']||inventory(SITE,['plugins'])!==$s['coreFiles']||hash('sha256',bytes(CONFIG))!==CONFIG_SHA)stop('private_data_config_or_core_changed');
}
function publicCodePermissions(string $root):void{directory($root,true);chmod($root,0755);foreach(new RecursiveIteratorIterator(new RecursiveDirectoryIterator($root,FilesystemIterator::SKIP_DOTS),RecursiveIteratorIterator::SELF_FIRST)as$f){if($f->isLink())stop('public_code_symlink');if(!chmod($f->getPathname(),$f->isDir()?0755:0644))stop('public_code_mode');}}
function checkpoint(array $s):array{return ['phase'=>$s['phase'],'serverId'=>SERVER_ID,'oldSchema'=>16,'newSchema'=>17,'oldTables'=>count($s['tables']),'newEmptyTables'=>array_keys(NEW_TABLE_COLUMNS),'oldRows'=>array_sum(array_column($s['tables'],'rows')),'nativeAccounts'=>$s['identity']['nativeAccounts'],'nativeDevices'=>$s['identity']['nativeDevices'],'sourceFiles'=>96,'historicRowsDefsPasswordsDevicesAndFilesPreserved'=>true,'coreAndHttpsUnchanged'=>true,'smtpFcmCronUnchanged'=>true,'apiPaused'=>$s['phase']!=='released','backupSha256'=>$s['backupSha256']];}
try{
 $mode=$argv[1]??'';if(!in_array($mode,['--check','--stage','--pause','--apply','--verify','--release'],true))stop('usage_guard');$gd=gdPreflight();$p=db();$packageEntries=package();if(count($packageEntries)!==96)stop('verified_package_count');$lock=fopen(WORK.'/helper.lock','c');if(!$lock||!flock($lock,LOCK_EX|LOCK_NB))stop('concurrent_operation');chmod(WORK.'/helper.lock',0600);
 if($mode==='--check'){
  if($argc!==2)stop('argument_guard');marker(false);identity($p,16);if(hashes(SITE.'/plugins/FamilyHub')!==sourceManifest()['old'])stop('old_source_manifest_mismatch');$d=defs($p);foreach(array_keys(NEW_TABLE_COLUMNS)as$t)if(isset($d[$t]))stop('idea_tables_already_exist');echo "Exact test2/config/serverId, old 0.12.0/schema16 and 91 code files, new ZIP96/SHA/CRC/PHP checked. No site or SQL writes; private lock only.\n";
 }elseif($mode==='--stage'){
  if($argc!==4)stop('stage_requires_backup_path_and_sha');fresh(STATE);fresh(WORK.'/stage');fresh(WORK.'/FamilyHub.before');marker(false);$m=backup($argv[2],$argv[3]);originalDb($p,$m);if(hashes(SITE.'/plugins/FamilyHub')!==sourceManifest()['old'])stop('old_code_changed');
  makeDir(WORK.'/stage');makeDir(WORK.'/stage/FamilyHub');foreach(package()as$n=>$b){$to=WORK.'/stage/FamilyHub/'.$n;if(!is_dir(dirname($to))&&!mkdir(dirname($to),0700,true))stop('stage_parent');writePrivate($to,$b,0644);}copyPrivate(SITE.'/plugins/FamilyHub',WORK.'/FamilyHub.before');
  writePrivate(STATE,json(['format'=>'test2-ideas-upgrade-v1','phase'=>'staged','backupPath'=>$argv[2],'backupSha256'=>$argv[3],'restoreProofSha256'=>hash('sha256',bytes(RESTORE_PROOF)),'tables'=>$m['tables'],'dataFiles'=>$m['dataFiles'],'dataDirectories'=>$m['dataDirectories'],'identity'=>identity($p,16),'pluginSchemaRows'=>schemaRows($p),'coreFiles'=>inventory(SITE,['plugins'])]));echo "New96 staged privately; old91 copied and hash checked; actual restored backup matches every live row/file. API unchanged.\n";
 }elseif($mode==='--pause'){
  if($argc!==3)stop('backup_sha_required');$s=state();if($s['phase']!=='staged'||$argv[2]!==$s['backupSha256'])stop('phase_or_backup_sha');$m=staged($s);marker(false);originalDb($p,$m);if(hashes(SITE.'/plugins/FamilyHub')!==sourceManifest()['old'])stop('old_code_changed');
  $s['phase']='pausing';save($s);fresh(PAUSED);if(!rename(MARKER,PAUSED))stop('marker_pause_failed');$s['phase']='paused';$s['pausedAt']=time();save($s);echo "Only test2 native marker retained privately; HTTP/ordinary CLI stay503. Wait at least65seconds before --apply. No SQL/schema/code changes.\n";
 }elseif($mode==='--apply'){
  if($argc!==3)stop('backup_sha_required');$s=state();if($s['phase']!=='paused'||$argv[2]!==$s['backupSha256'])stop('paused_phase_or_backup_sha');marker(true);if(time()-$s['pausedAt']<65)stop('drain_65_seconds_required');$m=staged($s);originalDb($p,$m);if(hashes(SITE.'/plugins/FamilyHub')!==sourceManifest()['old'])stop('old_code_changed');
  $s['phase']='migrating';save($s);require WORK.'/stage/FamilyHub/Schema/IdeasSchema.php';require WORK.'/stage/FamilyHub/Schema/Mysql.php';\Kanboard\Plugin\FamilyHub\Schema\version_17($p);preserved($p,$s,false);
  $p->beginTransaction();try{$q=$p->prepare("UPDATE plugin_schema_versions SET version=17 WHERE plugin='familyhub' AND version=16");$q->execute();if($q->rowCount()!==1)stop('schema_update_one_row_required');preserved($p,$s,true);$p->commit();}catch(Throwable$e){if($p->inTransaction())$p->rollBack();throw $e;}
  $s['phase']='schema17-code-pending';save($s);publicCodePermissions(WORK.'/stage/FamilyHub');fresh(WORK.'/FamilyHub.original');if(!rename(SITE.'/plugins/FamilyHub',WORK.'/FamilyHub.original'))stop('original_code_retain_failed');if(!rename(WORK.'/stage/FamilyHub',SITE.'/plugins/FamilyHub'))stop('new_code_swap_failed_keep_paused');$s['phase']='applied-paused';save($s);if(hashes(SITE.'/plugins/FamilyHub')!==sourceManifest()['new'])stop('new96_code_hash');preserved($p,$s,true);writePrivate(WORK.'/apply-checkpoint.json',json(checkpoint($s)));echo json(checkpoint($s));
 }elseif($mode==='--verify'||$mode==='--release'){
  if($argc!==3)stop('backup_sha_required');$s=state();if($s['phase']!=='applied-paused'||$argv[2]!==$s['backupSha256'])stop('applied_paused_phase_or_backup_sha');marker(true);backup($s['backupPath'],$s['backupSha256']);if(hash('sha256',bytes(RESTORE_PROOF))!==$s['restoreProofSha256']||hashes(SITE.'/plugins/FamilyHub')!==sourceManifest()['new']||hashes(WORK.'/FamilyHub.original')!==sourceManifest()['old']||hashes(WORK.'/FamilyHub.before')!==sourceManifest()['old'])stop('active_or_retained_code_guard');preserved($p,$s,true);
  if($mode==='--verify'){echo json(checkpoint($s));}
  else{$s['phase']='releasing';save($s);fresh(MARKER);if(!rename(PAUSED,MARKER))stop('marker_release_failed');$s['phase']='released';save($s);writePrivate(WORK.'/release-checkpoint.json',json(checkpoint($s)));echo json(checkpoint($s));}
 }
}catch(Test2UpgradeStop$e){fwrite(STDERR,'Test2 upgrade stopped: '.$e->getMessage().". Preserve private state/data/code; do not retry blindly or release a paused API. No secret printed.\n");exit(1);}
catch(Throwable$e){try{directory(WORK,true);writePrivate(WORK.'/diagnostic-'.gmdate('Ymd-His').'-'.bin2hex(random_bytes(4)).'.json',json(['exceptionClass'=>get_class($e),'file'=>$e->getFile(),'line'=>$e->getLine(),'sqlState'=>$e instanceof PDOException&&preg_match('/^[A-Z0-9]{5}$/D',(string)$e->getCode())?(string)$e->getCode():null]));}catch(Throwable$ignored){}fwrite(STDERR,"Test2 upgrade stopped: secret-free private diagnostic saved where possible. Keep API paused and all data/code. No exception/SQL/credentials printed.\n");exit(1);}
