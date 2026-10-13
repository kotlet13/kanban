<?php
/** ProductionFresh-only consistent private backup. No application bootstrap, accounts, mail or workers. */
if(PHP_SAPI!=='cli'){http_response_code(404);exit;}
ini_set('display_errors','0');ini_set('log_errors','0');error_reporting(0);umask(0077);
final class ProductionFreshBackupStop extends RuntimeException{}
function stop(string $code): never{throw new ProductionFreshBackupStop($code);}
set_error_handler(static function():never{stop('php_or_filesystem_warning');});
const SITE='/home/tripar13/jivie.triparna.si';
const BASE='/home/tripar13/private/jivie-production';
const CONFIG=SITE.'/config.php';
const DATA=SITE.'/data';
const BACKUPS=BASE.'/backups';
const WORK=BASE.'/install/production-0.13.0';
const DB_EXPECTED='tripar13_jivieprod';
const MARKER=WORK.'/crontab.original';
function bytes(string $p): string{if(is_link($p)||!is_file($p)||!is_readable($p))stop('file_guard');$v=file_get_contents($p);if(!is_string($v))stop('file_read');return $v;}
function directory(string $p,bool $private=false):void{if(is_link($p)||!is_dir($p)||realpath($p)!==$p||fileowner($p)!==fileowner(SITE))stop('directory_or_owner_guard');if($private&&(fileperms($p)&0077)!==0)stop('private_mode_guard');}
function writePrivate(string $p,string $v):void{if(file_exists($p)||is_link($p))stop('exclusive_destination_guard');$f=fopen($p,'xb');if(!$f)stop('exclusive_create');try{if(fwrite($f,$v)!==strlen($v)||!fflush($f))stop('write_failed');}finally{fclose($f);}chmod($p,0600);}
function makeDir(string $p):void{if(file_exists($p)||is_link($p)||!mkdir($p,0700))stop('fresh_directory_required');chmod($p,0700);}
function json(array $v):string{return json_encode($v,JSON_PRETTY_PRINT|JSON_UNESCAPED_SLASHES|JSON_THROW_ON_ERROR)."\n";}
function id(string $v):string{if(!preg_match('/^[a-zA-Z0-9_]+$/D',$v))stop('identifier_guard');return '`'.$v.'`';}
function rows(PDO $p,string $sql):array{$q=$p->query($sql);$v=$q->fetchAll(PDO::FETCH_ASSOC);$q->closeCursor();return $v;}
function inventory(string $root):array{
 directory($root);$out=[];$walk=function(string $d,string $prefix)use(&$walk,&$out){foreach(new DirectoryIterator($d)as$f){if($f->isDot())continue;$r=$prefix.$f->getFilename();if($f->isLink())stop('private_tree_symlink');if($f->isDir()){$walk($f->getPathname(),$r.'/');}elseif($f->isFile()){if($f->getSize()>268435456)stop('private_file_size_guard');$out[$r]=['bytes'=>$f->getSize(),'sha256'=>hash('sha256',bytes($f->getPathname()))];}else stop('private_tree_type_guard');}};$walk($root,'');ksort($out);return $out;
}
function dataDirectories(string $root):array{directory($root);$out=[];foreach(new RecursiveIteratorIterator(new RecursiveDirectoryIterator($root,FilesystemIterator::SKIP_DOTS),RecursiveIteratorIterator::SELF_FIRST)as$f){if($f->isLink())stop('private_directory_symlink');if($f->isDir()){$path=$f->getPathname();directory($path);$out[]=substr($path,strlen($root)+1);}}sort($out,SORT_STRING);return $out;}
function copyPrivate(string $from,string $to):void{makeDir($to);foreach(new DirectoryIterator($from)as$f){if($f->isDot())continue;if($f->isLink())stop('copy_symlink');$dest=$to.'/'.$f->getFilename();if($f->isDir())copyPrivate($f->getPathname(),$dest);elseif($f->isFile())writePrivate($dest,bytes($f->getPathname()));else stop('copy_file_guard');}}
function hashes(string $root):array{$out=[];$walk=function(string $dir,string $prefix)use(&$walk,&$out){foreach(new DirectoryIterator($dir)as$f){if($f->isDot())continue;if($f->isLink())stop('source_tree_symlink');$r=$prefix.$f->getFilename();if($f->isDir())$walk($f->getPathname(),$r.'/');elseif($f->isFile())$out[$r]=hash('sha256',bytes($f->getPathname()));else stop('source_tree_type');}};directory($root);$walk($root,'');ksort($out);return $out;}
function gdPreflight():array{
 foreach(['gd_info','imagecreatetruecolor','imagecreatefromstring','imagepng','imagejpeg','imagecopyresampled','imagerotate','imagestring','imagecolorallocatealpha']as$fn)if(!function_exists($fn))stop('gd_png_jpeg_required');$info=gd_info();if(empty($info['PNG Support'])||empty($info['JPEG Support']))stop('gd_png_jpeg_required');
 foreach(['imagepng','imagejpeg']as$encoder){$image=imagecreatetruecolor(2,2);imagefill($image,0,0,imagecolorallocate($image,20,100,220));ob_start();$encoder($image);$bytes=ob_get_clean();imagedestroy($image);$decoded=imagecreatefromstring($bytes);if(!$decoded||imagesx($decoded)!==2||imagesy($decoded)!==2)stop('gd_roundtrip_failed');imagedestroy($decoded);}return ['png'=>true,'jpeg'=>true];
}
function tableDefs(PDO $p):array{
 $v=rows($p,"SELECT TABLE_NAME,ENGINE FROM information_schema.TABLES WHERE TABLE_SCHEMA=DATABASE() AND TABLE_TYPE='BASE TABLE' ORDER BY TABLE_NAME");$out=[];
 foreach($v as$t){if($t['ENGINE']!=='InnoDB')stop('innodb_required');$name=$t['TABLE_NAME'];id($name);$cols=rows($p,'SHOW COLUMNS FROM '.id($name));$keys=array_column(array_filter($cols,fn($c)=>$c['Key']==='PRI'),'Field');$names=array_column($cols,'Field');$out[$name]=['columns'=>$names,'types'=>array_column($cols,'Type'),'order'=>$keys?:$names,'create'=>rows($p,'SHOW CREATE TABLE '.id($name))[0]['Create Table']];}
 if(!$out||!isset($out['users'],$out['tasks'],$out['projects']))stop('expected_core_tables_required');return $out;
}
function snapshot(PDO $p,array $defs):array{
 $out=[];foreach($defs as$name=>$def){$q=$p->query('SELECT '.implode(',',array_map('id',$def['columns'])).' FROM '.id($name).' ORDER BY '.implode(',',array_map('id',$def['order'])));$h=hash_init('sha256');$count=0;while($row=$q->fetch(PDO::FETCH_ASSOC)){hash_update($h,json_encode(array_map(fn($v)=>$v===null?null:base64_encode((string)$v),$row),JSON_UNESCAPED_SLASHES|JSON_THROW_ON_ERROR)."\n");$count++;}$q->closeCursor();$out[$name]=['columns'=>$def['columns'],'order'=>$def['order'],'types'=>$def['types'],'rows'=>$count,'sha256'=>hash_final($h),'createSha256'=>hash('sha256',$def['create'])];}return $out;
}
function db():PDO{
 directory(BASE,true);directory(WORK,true);directory(SITE);directory(DATA);
 if(hash('sha256',bytes(CONFIG))!==trim(bytes(WORK.'/config.before.sha256')))stop('config_changed');
 require CONFIG;
 if(DB_DRIVER!=='mysql'||DB_NAME!==DB_EXPECTED||DB_HOSTNAME!=='localhost'||DATA_DIR!==DATA)stop('fixed_production_identity');
 $p=new PDO('mysql:host='.DB_HOSTNAME.';dbname='.DB_NAME.';charset=utf8mb4',DB_USERNAME,DB_PASSWORD,[PDO::ATTR_ERRMODE=>PDO::ERRMODE_EXCEPTION,PDO::ATTR_DEFAULT_FETCH_MODE=>PDO::FETCH_ASSOC]);return $p;
}
function identity(PDO $p):array{
 $tables=$p->query('SHOW TABLES')->fetchAll(PDO::FETCH_COLUMN);
 foreach($tables as$t)if(str_starts_with($t,'familyhub_'))stop('not_fresh_familyhub');
 $users=rows($p,'SELECT id,username,role,password FROM users');
 if(count($users)!==1||$users[0]['username']!=='jivie_admin'||$users[0]['role']!=='app-admin'||password_verify('admin',$users[0]['password']))stop('initial_admin_guard');
 foreach(['projects','tasks']as$t)if((int)$p->query('SELECT COUNT(*) FROM '.id($t))->fetchColumn()!==0)stop('not_fresh_content');
 return ['onlyInitialAdmin'=>true,'zeroProjects'=>true,'zeroTasks'=>true,'noFamilyHubTables'=>true];
}
function pausedGuard():void{
 if(!str_starts_with(bytes(SITE.'/.htaccess'),"# JIVIE PRODUCTION MAINTENANCE\nRewriteEngine On\nRewriteRule ^ - [R=503,L]\n"))stop('maintenance_required');
 if(time()-(int)trim(bytes(WORK.'/paused-at'))<65)stop('drain_65_seconds_required');
}
function dump(PDO $p,array $defs,string $path):void{
 if(file_exists($path)||is_link($path))stop('dump_exists');$f=fopen($path,'xb');if(!$f)stop('dump_create');chmod($path,0600);
 $put=function(string $v)use($f){if(fwrite($f,$v)!==strlen($v))stop('dump_write');};
 try{$put("-- Private production-fresh logical backup. Never import to live hosting.\nSET NAMES utf8mb4;\nSET FOREIGN_KEY_CHECKS=0;\n");foreach($defs as$name=>$def){$put($def['create'].";\n");$q=$p->query('SELECT * FROM '.id($name).' ORDER BY '.implode(',',array_map('id',$def['order'])));while($row=$q->fetch(PDO::FETCH_ASSOC)){$values=[];foreach($row as$val)$values[]=$val===null?'NULL':"X'".bin2hex((string)$val)."'";$put('INSERT INTO '.id($name).' ('.implode(',',array_map('id',$def['columns'])).') VALUES ('.implode(',',$values).");\n");}$q->closeCursor();}$put("SET FOREIGN_KEY_CHECKS=1;\n");if(!fflush($f))stop('dump_flush');}finally{fclose($f);}
}
function archive(string $work):array{
 $items=inventory($work);$z=new ZipArchive();$path=$work.'/ProductionFresh-private-backup.zip';if($z->open($path,ZipArchive::CREATE|ZipArchive::EXCL)!==true)stop('zip_create');
 try{foreach($items as$n=>$m){$info=fileperms($work.'/'.$n);if(($info&0077)!==0)stop('archive_source_permissions');if(!$z->addFile($work.'/'.$n,$n))stop('zip_add');$z->setExternalAttributesName($n,ZipArchive::OPSYS_UNIX,0100600<<16);}}finally{if(!$z->close())stop('zip_close');}chmod($path,0600);
 $check=new ZipArchive();if($check->open($path,ZipArchive::RDONLY)!==true)stop('archive_reopen');try{if($check->numFiles!==count($items))stop('archive_count');foreach($items as$n=>$m){$body=$check->getFromName($n);if(!is_string($body)||strlen($body)!==$m['bytes']||hash('sha256',$body)!==$m['sha256'])stop('archive_hash');$stat=$check->statName($n);if(hash('crc32b',$body)!==sprintf('%08x',$stat['crc']))stop('archive_crc');}}finally{$check->close();}
 $sha=hash('sha256',bytes($path));writePrivate($path.'.sha256',$sha."  ProductionFresh-private-backup.zip\n");return ['archivePath'=>$path,'archiveSha256'=>$sha,'archiveBytes'=>filesize($path),'archiveEntries'=>count($items)];
}
try{
 $mode=$argv[1]??'';if($argc!==2||!in_array($mode,['--check','--export'],true))stop('usage_check_or_export');if(!class_exists(ZipArchive::class))stop('zip_required');$gd=gdPreflight();$p=db();$who=identity($p);$defs=tableDefs($p);
 if($mode==='--check'){echo json($who+['gdPngJpegRoundtrip'=>true,'tables'=>count($defs),'privateFiles'=>count(inventory(DATA)),'mode'=>'read_only_check','databaseAndLiveMarkerUnchanged'=>true]);exit;}
 if(!is_dir(BACKUPS))makeDir(BACKUPS);directory(BACKUPS,true);$lock=fopen(BACKUPS.'/backup.lock','c');if(!$lock||!flock($lock,LOCK_EX|LOCK_NB))stop('concurrent_backup');chmod(BACKUPS.'/backup.lock',0600);
 pausedGuard();$work=BACKUPS.'/fresh-before-familyhub-20261013';makeDir($work);$beforeConfig=hash('sha256',bytes(CONFIG));$beforeMarker=hash('sha256',bytes(MARKER));$beforeData=inventory(DATA);$beforeDirs=dataDirectories(DATA);
 // Root first pauses user editing/uploads. No cron or maintenance file is changed here.
 // Read locks block DB writers while SQL/files are captured; double file hash checks
 // reject a concurrent attachment/cache writer. LOCK/UNLOCK do not alter table data.
 $p->exec('LOCK TABLES '.implode(',',array_map(fn($t)=>id($t).' READ',array_keys($defs))));
 try{$before=identity($p);$tables=snapshot($p,$defs);dump($p,$defs,$work.'/database.sql');copyPrivate(DATA,$work.'/data');writePrivate($work.'/config.php',bytes(CONFIG));writePrivate($work.'/root-config.php',bytes(SITE.'/config.php'));writePrivate($work.'/root-htaccess',bytes(WORK.'/htaccess.original'));writePrivate($work.'/crontab.original',bytes(MARKER));
  if(dataDirectories(DATA)!==$beforeDirs||dataDirectories($work.'/data')!==$beforeDirs||inventory(DATA)!==$beforeData||inventory($work.'/data')!==$beforeData||snapshot($p,$defs)!==$tables||identity($p)!==$before||hash('sha256',bytes(CONFIG))!==$beforeConfig||hash('sha256',bytes(MARKER))!==$beforeMarker)stop('capture_changed_no_verified_archive');
  $manifest=['format'=>'production-fresh-preupgrade-backup-v1','createdUtc'=>gmdate('c'),'identity'=>$before,'database'=>DB_EXPECTED,'tables'=>$tables,'dataFiles'=>$beforeData,'dataDirectories'=>$beforeDirs,'dataFilesCount'=>count($beforeData),'databaseSqlSha256'=>hash('sha256',bytes($work.'/database.sql')),'privateConfigSha256'=>$beforeConfig,'rootConfigSha256'=>hash('sha256',bytes($work.'/root-config.php')),'rootHtaccessSha256'=>hash('sha256',bytes($work.'/root-htaccess')),'cronSha256'=>$beforeMarker,'capture'=>['mysqlAllTablesReadLocked'=>true,'twoMatchingDatabaseSnapshots'=>true,'twoMatchingSourceAndCopiedFileInventories'=>true,'liveConfigurationUnchanged'=>true,'noApplicationOrWorkersStarted'=>true,'noSqlRowsWritten'=>true]];writePrivate($work.'/manifest.json',json($manifest));
 }finally{$p->exec('UNLOCK TABLES');}
 $result=archive($work);writePrivate(WORK.'/backup-result.json',json($result));echo json($result+['tables'=>count($tables),'rows'=>array_sum(array_column($tables,'rows')),'privateFiles'=>count($beforeData),'mode'=>'private_read_only_export','liveConfigurationUnchanged'=>true,'noAccountsOrSqlRowsWritten'=>true]);
}catch(ProductionFreshBackupStop $e){fwrite(STDERR,'ProductionFresh backup stopped: '.$e->getMessage().". Incomplete private files retained; no verified backup assumed. No credentials printed.\n");exit(1);}
catch(Throwable $e){try{directory(BASE,true);$path=BASE.'/backup-diagnostic-'.gmdate('Ymd-His').'-'.bin2hex(random_bytes(4)).'.json';writePrivate($path,json(['exceptionClass'=>get_class($e),'file'=>$e->getFile(),'line'=>$e->getLine(),'sqlState'=>$e instanceof PDOException&&preg_match('/^[A-Z0-9]{5}$/D',(string)$e->getCode())?(string)$e->getCode():null]));}catch(Throwable $ignored){}fwrite(STDERR,"ProductionFresh backup stopped: private diagnostic required; no exception, SQL or credential detail printed. Incomplete private files retained.\n");exit(1);}
