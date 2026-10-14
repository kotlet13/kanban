<?php
/** Pre-DDL abort only: restore exact HTTPS, then confirm shell-restored original cron. */
if(PHP_SAPI!=='cli'){http_response_code(404);exit;}
ini_set('display_errors','0');ini_set('log_errors','0');error_reporting(0);umask(0077);
final class Lifecycle18AbortStop extends RuntimeException{}
function stop(string $code):never{throw new Lifecycle18AbortStop($code);}
set_error_handler(static function():never{stop('php_or_filesystem_warning');});
require __DIR__.'/deployment.php';
function bytes(string $path):string{if(is_link($path)||!is_file($path)||!is_readable($path)||realpath($path)!==$path)stop('file_guard');$v=file_get_contents($path);if(!is_string($v))stop('file_read');return $v;}
function directory(string $path,bool $private=false):void{if(is_link($path)||!is_dir($path)||realpath($path)!==$path||fileowner($path)!==fileowner(SITE)||($private&&(fileperms($path)&0077)!==0))stop('directory_owner_mode_guard');}
function writePrivate(string $path,array $value):void{if(file_exists($path)||is_link($path))stop('exclusive_abort_checkpoint');$v=json_encode($value,JSON_PRETTY_PRINT|JSON_UNESCAPED_SLASHES|JSON_THROW_ON_ERROR)."\n";$f=fopen($path,'xb');if(!$f)stop('exclusive_create');try{if(fwrite($f,$v)!==strlen($v)||!fflush($f))stop('checkpoint_write');}finally{fclose($f);}chmod($path,0600);}
function readJson(string $path):array{$v=json_decode(bytes($path),true,64,JSON_THROW_ON_ERROR);if(!is_array($v))stop('json_guard');return $v;}
function hashes(string $root):array{directory($root);$out=[];foreach(new RecursiveIteratorIterator(new RecursiveDirectoryIterator($root,FilesystemIterator::SKIP_DOTS))as$f){if($f->isLink())stop('source_symlink');if($f->isFile())$out[substr($f->getPathname(),strlen($root)+1)]=hash('sha256',bytes($f->getPathname()));}ksort($out);return $out;}
function preDdlGuard():array{
 directory(SITE);foreach([BASE,WORK,DATA]as$dir)directory($dir,true);if(realpath(__DIR__)!==WORK)stop('exact_sealed_work_required');
 foreach(['state.json','state.json.next','stage','FamilyHub.before','FamilyHub.original','apply-checkpoint.json','http-release-checkpoint.json','release-checkpoint.json']as$name)if(file_exists(WORK.'/'.$name)||is_link(WORK.'/'.$name))stop('stage_migration_or_release_detected');
 if(hash('sha256',bytes(CONFIG))!==CONFIG_SHA||(fileperms(CONFIG)&0777)!==CONFIG_MODE||file_exists(SITE.'/data/config.php'))stop('original_config_guard');deliveryGuard();
 if(hash('sha256',bytes(MANIFEST))!==MANIFEST_SHA)stop('manifest_hash');$m=readJson(MANIFEST);if(count($m['old']??[])!==96||count($m['new']??[])!==SOURCE_COUNT||hashes(SITE.'/plugins/FamilyHub')!==$m['old'])stop('exact_old96_source_guard');
 if(hash('sha256',bytes(WORK.'/htaccess.original'))!==HTACCESS_SHA||hash('sha256',bytes(WORK.'/crontab.original'))!==CRON_SHA)stop('exact_private_originals_guard');
 if(DB_DRIVER!=='mysql'||DB_NAME!==DB_EXPECTED||!in_array(DB_HOSTNAME,['localhost','127.0.0.1'],true)||DATA_DIR!==DATA||FILES_DIR!==DATA.'/files'||CACHE_DIR!==DATA.'/cache'||FAMILYHUB_ENABLE_NATIVE_API!==true||FAMILYHUB_ACCOUNT_MODE!=='self_hosted'||FAMILYHUB_ENABLE_PROJECT_INVITATIONS!==false||(defined('FAMILYHUB_DEVELOPMENT_MODE')&&FAMILYHUB_DEVELOPMENT_MODE))stop('fixed_database_config_guard');
 $port=defined('DB_PORT')&&DB_PORT?DB_PORT:3306;$p=new PDO('mysql:host='.DB_HOSTNAME.';port='.$port.';dbname='.DB_NAME.';charset=utf8mb4',DB_USERNAME,DB_PASSWORD,[PDO::ATTR_ERRMODE=>PDO::ERRMODE_EXCEPTION,PDO::ATTR_TIMEOUT=>10]);
 if($p->query('SELECT DATABASE()')->fetchColumn()!==DB_EXPECTED||!str_starts_with((string)$p->query('SELECT VERSION()')->fetchColumn(),'10.11.19-MariaDB')||$p->query('SELECT server_id FROM familyhub_instance WHERE id=1')->fetchColumn()!==SERVER_ID||(int)$p->query("SELECT version FROM plugin_schema_versions WHERE plugin='familyhub'")->fetchColumn()!==17)stop('actual_schema17_identity_guard');
 foreach(['familyhub_scopes'=>['deleted_at'],'familyhub_push_registrations'=>['notification_format'],'familyhub_reminders'=>['schedule_mode','offset_minutes']]as$table=>$columns){$q=$p->prepare('SELECT COLUMN_NAME FROM information_schema.COLUMNS WHERE TABLE_SCHEMA=DATABASE() AND TABLE_NAME=?');$q->execute([$table]);$present=$q->fetchAll(PDO::FETCH_COLUMN);foreach($columns as$column)if(in_array($column,$present,true))stop('schema18_column_detected');}
 if((int)$p->query("SELECT COUNT(*) FROM information_schema.TABLES WHERE TABLE_SCHEMA=DATABASE() AND TABLE_NAME='familyhub_scope_deletion_files'")->fetchColumn()!==0)stop('schema18_table_detected');
 return ['format'=>'lifecycle18-preddl-abort-v1','serverId'=>SERVER_ID,'schema'=>17,'sourceFiles'=>96,'manifestSha256'=>MANIFEST_SHA,'configSha256'=>CONFIG_SHA,'originalHttpsSha256'=>HTACCESS_SHA,'originalCronSha256'=>CRON_SHA,'noMigrationOrStage'=>true,'noSqlRowsWritten'=>true,'noApplicationOrWorkersBootstrappedByHelper'=>true,'backupFilesRetained'=>true];
}
function pausedCronGuard():void{if(hash('sha256',bytes(WORK.'/crontab.current'))!==hash('sha256',bytes(WORK.'/crontab.paused')))stop('paused_cron_required');}
function httpsStatus(int $expected):void{
 if(!in_array($expected,[503,200],true))stop('http_status_guard');
 $url=PUBLIC_URL.'/index.php';
 $options=[CURLOPT_RETURNTRANSFER=>true,CURLOPT_FOLLOWLOCATION=>false,CURLOPT_CONNECTTIMEOUT=>10,CURLOPT_TIMEOUT=>20,CURLOPT_SSL_VERIFYPEER=>true,CURLOPT_SSL_VERIFYHOST=>2];
 if($expected===200){
  $url.='?controller=NativeApiController&action=handle&plugin=FamilyHub';
  $options[CURLOPT_POST]=true;$options[CURLOPT_HTTPHEADER]=['Content-Type: application/json'];
  $options[CURLOPT_POSTFIELDS]=json_encode(['v'=>1,'op'=>'capabilities','params'=>(object)[]],JSON_THROW_ON_ERROR);
 }
 $h=curl_init($url);curl_setopt_array($h,$options);$b=curl_exec($h);$status=curl_getinfo($h,CURLINFO_HTTP_CODE);curl_close($h);
 if(!is_string($b)||$status!==$expected)stop($expected===503?'tls_http503_required':'tls_http200_required');
 if($expected===200){
  if(strlen($b)>1048576)stop('native_capabilities_size_guard');
  try{$response=json_decode($b,true,32,JSON_THROW_ON_ERROR);}catch(JsonException$e){stop('native_capabilities_json_guard');}
  if(!is_array($response)||($response['v']??null)!==1||array_key_exists('error',$response)||!is_array($response['data']??null))stop('native_capabilities_envelope_guard');
  $data=$response['data'];if(($data['api']??null)!=='familyhub_native'||($data['version']??null)!==1||($data['serverId']??null)!==SERVER_ID||($data['enabled']??null)!==true)stop('native_capabilities_identity_guard');
 }
}
function intentGuard():void{$intent=readJson(WORK.'/abort-intent.json');if(($intent['format']??null)!=='lifecycle18-preddl-abort-v1'||($intent['serverId']??null)!==SERVER_ID||($intent['schema']??null)!==17||($intent['originalHttpsSha256']??null)!==HTACCESS_SHA||($intent['originalCronSha256']??null)!==CRON_SHA||($intent['manifestSha256']??null)!==MANIFEST_SHA)stop('abort_intent_guard');}
try{
 $mode=$argv[1]??'';if($argc!==2||!in_array($mode,['--check','--restore-http','--verify-http','--confirm-cron'],true))stop('usage_guard');require WORK.'/maintenance-guards.php';require WORK.'/delivery-guards.php';require CONFIG;
 $lock=fopen(WORK.'/helper.lock','c');if(!$lock||!flock($lock,LOCK_EX|LOCK_NB))stop('concurrent_operation');chmod(WORK.'/helper.lock',0600);$proof=preDdlGuard();
 if(file_exists(WORK.'/abort-checkpoint.json')||is_link(WORK.'/abort-checkpoint.json'))stop('abort_already_completed');
 if($mode==='--check'||$mode==='--restore-http'){
  if(file_exists(WORK.'/abort-intent.json')||is_link(WORK.'/abort-intent.json')||file_exists(WORK.'/abort-http-checkpoint.json'))stop('abort_already_started');pausedGuard();httpsStatus(503);
  if($mode==='--check'){echo json_encode($proof+['phase'=>'verified-preddl-paused'],JSON_UNESCAPED_SLASHES|JSON_THROW_ON_ERROR)."\n";exit;}
  writePrivate(WORK.'/abort-intent.json',$proof+['startedUtc'=>gmdate('c')]);$temporary=SITE.'/.htaccess.lifecycle18-abort';if(file_exists($temporary)||is_link($temporary))stop('abort_temporary_exists');$f=fopen($temporary,'xb');if(!$f)stop('abort_temporary_create');$original=bytes(WORK.'/htaccess.original');try{if(fwrite($f,$original)!==strlen($original)||!fflush($f))stop('abort_https_write');}finally{fclose($f);}chmod($temporary,0644);if(hash('sha256',bytes($temporary))!==HTACCESS_SHA||!rename($temporary,SITE.'/.htaccess'))stop('atomic_original_https_restore');
  // Fall through to live TLS verification while all five worker crons remain paused.
 }
 if($mode==='--restore-http'||$mode==='--verify-http'){
  intentGuard();pausedCronGuard();if(hash('sha256',bytes(SITE.'/.htaccess'))!==HTACCESS_SHA)stop('restored_https_hash_guard');httpsStatus(200);$proof=preDdlGuard();pausedCronGuard();writePrivate(WORK.'/abort-http-checkpoint.json',$proof+['phase'=>'http-restored-workers-paused','tlsHttpStatus'=>200,'verifiedUtc'=>gmdate('c')]);echo "Original HTTPS restored and TLS200 verified; original96/schema17/config/keys unchanged. Worker cron remains paused; restore exact original cron next.\n";
 }elseif($mode==='--confirm-cron'){
  intentGuard();$http=readJson(WORK.'/abort-http-checkpoint.json');if(($http['phase']??null)!=='http-restored-workers-paused'||($http['tlsHttpStatus']??null)!==200||($http['serverId']??null)!==SERVER_ID)stop('verified_http_checkpoint_required');originalCronGuard();if(hash('sha256',bytes(SITE.'/.htaccess'))!==HTACCESS_SHA)stop('restored_https_hash_guard');httpsStatus(200);$proof=preDdlGuard();originalCronGuard();writePrivate(WORK.'/abort-checkpoint.json',$proof+['phase'=>'aborted-before-ddl','tlsHttpStatus'=>200,'workerCronRestored'=>true,'completedUtc'=>gmdate('c')]);echo "Pre-DDL abort complete: original HTTPS200/cron restored; exact old96/schema17/config/keys preserved. All private backups retained. No migration or SQL writes.\n";
 }
}catch(Lifecycle18AbortStop$e){fwrite(STDERR,'Lifecycle18 abort stopped: '.$e->getMessage().". Preserve all private originals/state/backups; do not migrate or blindly restore cron. No secret printed.\n");exit(1);}
catch(Throwable$e){fwrite(STDERR,"Lifecycle18 abort stopped: private diagnostic required. Preserve originals/backups; no exception, SQL or credentials printed.\n");exit(1);}
