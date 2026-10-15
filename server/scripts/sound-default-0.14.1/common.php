<?php
// CLI-only code patch support. No Kanboard application or worker bootstrap.
if(PHP_SAPI!=='cli'){http_response_code(404);exit;}
ini_set('display_errors','0');ini_set('log_errors','0');error_reporting(0);umask(0077);
function stop(string $code):never{throw new RuntimeException($code);}
set_error_handler(static function():never{stop('php_or_filesystem_warning');});
const BASELINE_SHA='f86da6da59df6ea2fb0230e70807cdcf1d888cb0452404ed4f5cfa1ae448a1c8';
const PATCH_FILES=['Model/NativePushWorker.php','Model/NativeNotificationPreferences.php','Plugin.php'];
function profiles():array{return ['production'=>['site'=>'/home/tripar13/jivie.triparna.si','base'=>'/home/tripar13/private/jivie-production','database'=>'tripar13_jivieprod','serverId'=>'ad56910f-ca2e-41ee-af0d-3f18081497cf'],'test1'=>['site'=>'/home/tripar13/jivie-test.triparna.si','base'=>'/home/tripar13/private/jivie-test','database'=>'tripar13_jivietest','serverId'=>'95c11fe0-916c-48be-a3f6-999732846266']];}
function cfg(string $key){return $GLOBALS['patchProfile'][$key];}
function bytes(string $path):string{if(is_link($path)||!is_file($path)||realpath($path)!==$path)stop('canonical_regular_file_required');$v=file_get_contents($path);if(!is_string($v))stop('file_read');return $v;}
function directory(string $path,bool $private=false):void{if(is_link($path)||!is_dir($path)||realpath($path)!==$path||fileowner($path)!==fileowner(cfg('site'))||($private&&(fileperms($path)&0077)!==0))stop('directory_owner_mode_guard');}
function encode(array $value):string{return json_encode($value,JSON_PRETTY_PRINT|JSON_UNESCAPED_SLASHES|JSON_THROW_ON_ERROR)."\n";}
function readJson(string $path):array{$v=json_decode(bytes($path),true,128,JSON_THROW_ON_ERROR);if(!is_array($v))stop('json_shape');return $v;}
function fresh(string $path):void{if(file_exists($path)||is_link($path))stop('fresh_destination_required');}
function writePrivate(string $path,string $value,int $mode=0600):void{fresh($path);$f=fopen($path,'xb');if(!$f)stop('exclusive_create');try{if(fwrite($f,$value)!==strlen($value)||!fflush($f))stop('private_write');}finally{fclose($f);}chmod($path,$mode);}
function meta(string $path):array{return ['mode'=>fileperms($path)&0777,'uid'=>fileowner($path),'gid'=>filegroup($path)];}
function tree(string $root,array $skip=[]):array{directory($root);$out=[];$walk=function($dir,$prefix)use(&$walk,&$out,$skip){foreach(new DirectoryIterator($dir)as$f){if($f->isDot())continue;$rel=$prefix.$f->getFilename();if(in_array($rel,$skip,true))continue;if($f->isLink())stop('tree_symlink');$entry=meta($f->getPathname());if($f->isDir()){$out[$rel]=['type'=>'directory']+$entry;$walk($f->getPathname(),$rel.'/');}elseif($f->isFile())$out[$rel]=['type'=>'file','bytes'=>$f->getSize(),'sha256'=>hash('sha256',bytes($f->getPathname()))]+$entry;else stop('tree_type');}};$walk($root,'');ksort($out);return $out;}
function sourceHashes():array{$out=[];foreach(tree(cfg('site').'/plugins/FamilyHub')as$name=>$value)if($value['type']==='file')$out[$name]=$value['sha256'];return $out;}
function baseline():array{if(hash('sha256',bytes(__DIR__.'/old-manifest.json'))!==BASELINE_SHA)stop('baseline_manifest_hash');$m=readJson(__DIR__.'/old-manifest.json');if(count($m)!==101)stop('baseline101_required');return $m;}
function setup(string $profile):PDO{
 $profiles=profiles();if(!isset($profiles[$profile]))stop('fixed_profile_required');$GLOBALS['patchProfile']=$profiles[$profile];directory(cfg('site'));directory(cfg('base'),true);directory(cfg('base').'/data',true);
 $before=get_included_files();require cfg('site').'/config.php';$GLOBALS['patchIncludes']=array_values(array_diff(get_included_files(),$before));
 if(DB_DRIVER!=='mysql'||DB_NAME!==cfg('database')||!in_array(DB_HOSTNAME,['localhost','127.0.0.1'],true)||DATA_DIR!==cfg('base').'/data'||FILES_DIR!==DATA_DIR.'/files'||CACHE_DIR!==DATA_DIR.'/cache'||FAMILYHUB_ENABLE_NATIVE_API!==true||FAMILYHUB_ACCOUNT_MODE!=='self_hosted'||FAMILYHUB_ENABLE_PROJECT_INVITATIONS!==false||(defined('FAMILYHUB_DEVELOPMENT_MODE')&&FAMILYHUB_DEVELOPMENT_MODE))stop('fixed_config_semantics');
 $port=defined('DB_PORT')&&DB_PORT?DB_PORT:3306;$pdo=new PDO('mysql:host='.DB_HOSTNAME.';port='.$port.';dbname='.DB_NAME.';charset=utf8mb4',DB_USERNAME,DB_PASSWORD,[PDO::ATTR_ERRMODE=>PDO::ERRMODE_EXCEPTION,PDO::ATTR_TIMEOUT=>10,PDO::ATTR_DEFAULT_FETCH_MODE=>PDO::FETCH_ASSOC]);
 if($pdo->query('SELECT DATABASE()')->fetchColumn()!==cfg('database')||!str_starts_with((string)$pdo->query('SELECT VERSION()')->fetchColumn(),'10.11.19-MariaDB'))stop('actual_database_version');$pdo->exec('SET SESSION lock_wait_timeout=10');return $pdo;
}
function configPins():array{
 $paths=$GLOBALS['patchIncludes'];foreach(glob(cfg('base').'/*')as$path)if(is_file($path))$paths[]=$path;if(defined('FAMILYHUB_FCM_SERVICE_ACCOUNT_FILE'))$paths[]=FAMILYHUB_FCM_SERVICE_ACCOUNT_FILE;$out=[];
 foreach(array_unique($paths)as$path){if($path!==cfg('site').'/config.php'&&!str_starts_with($path,cfg('base').'/'))stop('config_must_be_private_target');$body=bytes($path);$pin=meta($path);if($pin['uid']!==fileowner(cfg('site'))||($path!==cfg('site').'/config.php'&&$pin['mode']!==0600))stop('config_owner_private_mode');$out[$path]=['sha256'=>hash('sha256',$body)]+$pin;}ksort($out);
 $constants=[];foreach(get_defined_constants()as$key=>$value)if(str_starts_with($key,'FAMILYHUB_')&&is_scalar($value))$constants[$key]=$value;ksort($constants);return ['files'=>$out,'constantsSha256'=>hash('sha256',serialize($constants))];
}
function id(string $name):string{if(!preg_match('/^[A-Za-z0-9_]+$/D',$name))stop('sql_identifier');return '`'.$name.'`';}
function tableNames(PDO $pdo):array{$tables=$pdo->query("SELECT TABLE_NAME,ENGINE FROM information_schema.TABLES WHERE TABLE_SCHEMA=DATABASE() AND TABLE_TYPE='BASE TABLE' ORDER BY TABLE_NAME")->fetchAll();$out=[];foreach($tables as$t){if($t['ENGINE']!=='InnoDB')stop('all_tables_innodb');$out[]=$t['TABLE_NAME'];}return $out;}
function rowsHash(PDO $pdo,string $table,string $order):array{$q=$pdo->query('SELECT * FROM '.id($table).' ORDER BY '.$order);$h=hash_init('sha256');$count=0;while($row=$q->fetch(PDO::FETCH_ASSOC)){hash_update($h,json_encode(array_map(fn($v)=>$v===null?null:base64_encode((string)$v),$row),JSON_UNESCAPED_SLASHES|JSON_THROW_ON_ERROR)."\n");$count++;}$q->closeCursor();return ['rows'=>$count,'rawRowsSha256'=>hash_final($h)];}
function snapshot(PDO $pdo,string $cronFile):array{
 if($pdo->query('SELECT server_id FROM familyhub_instance WHERE id=1')->fetchColumn()!==cfg('serverId')||(int)$pdo->query("SELECT version FROM plugin_schema_versions WHERE plugin='familyhub'")->fetchColumn()!==18)stop('server_identity_schema18');
 $tables=[];foreach(tableNames($pdo)as$table){$definition=$pdo->query('SHOW CREATE TABLE '.id($table))->fetch();$tables[$table]=['rows'=>(int)$pdo->query('SELECT COUNT(*) FROM '.id($table))->fetchColumn(),'createSha256'=>hash('sha256',$definition['Create Table'])];}
 $identities=[];foreach(['users'=>'id','familyhub_accounts'=>'user_id','familyhub_devices'=>'id','familyhub_instance'=>'id','plugin_schema_versions'=>'plugin']as$table=>$order)$identities[$table]=rowsHash($pdo,$table,id($order));
 return ['serverId'=>cfg('serverId'),'schema'=>18,'tables'=>$tables,'identities'=>$identities,'preferences'=>rowsHash($pdo,'familyhub_inbox_preferences','scope_id,account_id,category'),'config'=>configPins(),'cronSha256'=>hash('sha256',bytes($cronFile)),'data'=>tree(DATA_DIR),'core'=>tree(cfg('site'),['plugins/FamilyHub'])];
}
function secretFreeFailure(Throwable $error):never{$code=$error instanceof RuntimeException&&preg_match('/^[a-z0-9_]+$/D',$error->getMessage())?$error->getMessage():'private_diagnostic_required';fwrite(STDERR,'Sound-default patch stopped: '.$code.'. Preserve private originals and checkpoints. No SQL, credentials or row contents printed.'."\n");exit(1);}
