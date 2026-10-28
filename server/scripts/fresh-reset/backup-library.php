<?php
/** Fresh-reset23-only consistent private backup; derived from upgrade-0.16.0 backup, with separate reviewed schema/source pins. No application bootstrap, accounts, mail or workers. */
if(PHP_SAPI!=='cli'){http_response_code(404);exit;}
ini_set('display_errors','0');ini_set('log_errors','0');error_reporting(0);umask(0077);
final class Crypto23BackupStop extends RuntimeException{}
function stop(string $code): never{throw new Crypto23BackupStop($code);}
set_error_handler(static function():never{stop('php_or_filesystem_warning');});
require __DIR__.'/deployment.php';
const MARKER=WORK.'/crontab.original';
function bytes(string $p): string{if(is_link($p)||!is_file($p)||!is_readable($p))stop('file_guard');$v=file_get_contents($p);if(!is_string($v))stop('file_read');return $v;}
function directory(string $p,bool $private=false):void{if(is_link($p)||!is_dir($p)||realpath($p)!==$p||fileowner($p)!==fileowner(SITE))stop('directory_or_owner_guard');if($private&&(fileperms($p)&0077)!==0)stop('private_mode_guard');}
function writePrivate(string $p,string $v,int $mode=0600):void{if(!in_array($mode,[0600,0644],true))stop('explicit_file_mode_guard');if(file_exists($p)||is_link($p))stop('exclusive_destination_guard');$f=fopen($p,'xb');if(!$f)stop('exclusive_create');try{if(fwrite($f,$v)!==strlen($v)||!fflush($f))stop('write_failed');}finally{fclose($f);}if(!chmod($p,$mode)||(fileperms($p)&0777)!==$mode)stop('written_file_mode_guard');}
function makeDir(string $p):void{if(file_exists($p)||is_link($p)||!mkdir($p,0700))stop('fresh_directory_required');chmod($p,0700);}
function json(array $v):string{return json_encode($v,JSON_PRETTY_PRINT|JSON_UNESCAPED_SLASHES|JSON_THROW_ON_ERROR)."\n";}
function id(string $v):string{if(!preg_match('/^[a-zA-Z0-9_]+$/D',$v))stop('identifier_guard');return '`'.$v.'`';}
function rows(PDO $p,string $sql):array{$q=$p->query($sql);$v=$q->fetchAll(PDO::FETCH_ASSOC);$q->closeCursor();return $v;}
function inventory(string $root):array{
 directory($root,true);$out=[];$walk=function(string $d,string $prefix)use(&$walk,&$out){foreach(new DirectoryIterator($d)as$f){if($f->isDot())continue;$r=$prefix.$f->getFilename();if($f->isLink())stop('private_tree_symlink');if(($f->getPerms()&0077)!==0||$f->getOwner()!==fileowner(SITE))stop('private_data_modes_guard');if($f->isDir()){$walk($f->getPathname(),$r.'/');}elseif($f->isFile()){if($f->getSize()>268435456)stop('private_file_size_guard');$out[$r]=['bytes'=>$f->getSize(),'sha256'=>hash('sha256',bytes($f->getPathname()))];}else stop('private_tree_type_guard');}};$walk($root,'');ksort($out);return $out;
}
function dataDirectories(string $root):array{directory($root,true);$out=[];foreach(new RecursiveIteratorIterator(new RecursiveDirectoryIterator($root,FilesystemIterator::SKIP_DOTS),RecursiveIteratorIterator::SELF_FIRST)as$f){if($f->isLink())stop('private_directory_symlink');if($f->isDir()){$path=$f->getPathname();directory($path,true);$out[]=substr($path,strlen($root)+1);}}sort($out,SORT_STRING);return $out;}
function copyPrivate(string $from,string $to):void{makeDir($to);foreach(new DirectoryIterator($from)as$f){if($f->isDot())continue;if($f->isLink())stop('copy_symlink');$dest=$to.'/'.$f->getFilename();if($f->isDir())copyPrivate($f->getPathname(),$dest);elseif($f->isFile())writePrivate($dest,bytes($f->getPathname()));else stop('copy_file_guard');}}
function hashes(string $root):array{$out=[];$walk=function(string $dir,string $prefix)use(&$walk,&$out){foreach(new DirectoryIterator($dir)as$f){if($f->isDot())continue;if($f->isLink())stop('source_tree_symlink');$r=$prefix.$f->getFilename();if($f->isDir())$walk($f->getPathname(),$r.'/');elseif($f->isFile())$out[$r]=hash('sha256',bytes($f->getPathname()));else stop('source_tree_type');}};directory($root);$walk($root,'');ksort($out);return $out;}
function sourceManifest():array{if(hash('sha256',bytes(MANIFEST))!==MANIFEST_SHA)stop('manifest_hash');$m=json_decode(bytes(MANIFEST),true,64,JSON_THROW_ON_ERROR);if(!is_array($m)||count($m['old']??[])!==SOURCE_COUNT||count($m['new']??[])!==SOURCE_COUNT)stop('manifest_counts');return $m;}
function gdPreflight():array{
 foreach(['gd_info','imagecreatetruecolor','imagecreatefromstring','imagepng','imagejpeg','imagecopyresampled','imagerotate','imagestring','imagecolorallocatealpha']as$fn)if(!function_exists($fn))stop('gd_png_jpeg_required');$info=gd_info();if(empty($info['PNG Support'])||empty($info['JPEG Support']))stop('gd_png_jpeg_required');
 foreach(['imagepng','imagejpeg']as$encoder){$image=imagecreatetruecolor(2,2);imagefill($image,0,0,imagecolorallocate($image,20,100,220));ob_start();$encoder($image);$bytes=ob_get_clean();imagedestroy($image);$decoded=imagecreatefromstring($bytes);if(!$decoded||imagesx($decoded)!==2||imagesy($decoded)!==2)stop('gd_roundtrip_failed');imagedestroy($decoded);}return ['png'=>true,'jpeg'=>true];
}
function databaseObjectGuard(PDO $p):void{
 foreach(["SELECT COUNT(*) FROM information_schema.VIEWS WHERE TABLE_SCHEMA=DATABASE()","SELECT COUNT(*) FROM information_schema.TRIGGERS WHERE TRIGGER_SCHEMA=DATABASE()","SELECT COUNT(*) FROM information_schema.ROUTINES WHERE ROUTINE_SCHEMA=DATABASE()","SELECT COUNT(*) FROM information_schema.EVENTS WHERE EVENT_SCHEMA=DATABASE()"]as$query)if((int)$p->query($query)->fetchColumn()!==0)stop('unsupported_database_object_requires_full_dump_review');
}
function tableDefs(PDO $p):array{
 databaseObjectGuard($p);
 $v=rows($p,"SELECT TABLE_NAME,ENGINE FROM information_schema.TABLES WHERE TABLE_SCHEMA=DATABASE() AND TABLE_TYPE='BASE TABLE' ORDER BY TABLE_NAME");$out=[];
 foreach($v as$t){if($t['ENGINE']!=='InnoDB')stop('innodb_required');$name=$t['TABLE_NAME'];id($name);$cols=rows($p,'SHOW COLUMNS FROM '.id($name));$keys=array_column(array_filter($cols,fn($c)=>$c['Key']==='PRI'),'Field');$names=array_column($cols,'Field');$out[$name]=['columns'=>$names,'types'=>array_column($cols,'Type'),'order'=>$keys?:$names,'create'=>rows($p,'SHOW CREATE TABLE '.id($name))[0]['Create Table']];}
 if(!$out||!isset($out['familyhub_instance'],$out['familyhub_accounts'],$out['familyhub_devices']))stop('expected_familyhub_tables_required');return $out;
}
function snapshot(PDO $p,array $defs):array{
 $out=[];foreach($defs as$name=>$def){$q=$p->query('SELECT '.implode(',',array_map('id',$def['columns'])).' FROM '.id($name).' ORDER BY '.implode(',',array_map('id',$def['order'])));$h=hash_init('sha256');$count=0;while($row=$q->fetch(PDO::FETCH_ASSOC)){hash_update($h,json_encode(array_map(fn($v)=>$v===null?null:base64_encode((string)$v),$row),JSON_UNESCAPED_SLASHES|JSON_THROW_ON_ERROR)."\n");$count++;}$q->closeCursor();$out[$name]=['columns'=>$def['columns'],'order'=>$def['order'],'types'=>$def['types'],'rows'=>$count,'sha256'=>hash_final($h),'createSha256'=>hash('sha256',$def['create'])];}return $out;
}
function db():PDO{
 foreach([BASE,DATA]as$d)directory($d,true);directory(SITE);directory(WORK,true);if((fileperms(CONFIG)&0777)!==CONFIG_MODE||hash('sha256',bytes(CONFIG))!==CONFIG_SHA||file_exists(SITE.'/data/config.php'))stop('private_config_or_enabled_marker_guard');
 require CONFIG;deliveryGuard();
 if(!defined('DB_DRIVER')||DB_DRIVER!=='mysql'||!defined('DB_NAME')||DB_NAME!==DB_EXPECTED||!defined('DB_HOSTNAME')||!in_array(DB_HOSTNAME,['localhost','127.0.0.1'],true)||!defined('DB_USERNAME')||!defined('DB_PASSWORD')||DATA_DIR!==DATA||FILES_DIR!==DATA.'/files'||CACHE_DIR!==DATA.'/cache'||FAMILYHUB_ENABLE_NATIVE_API!==true||FAMILYHUB_ACCOUNT_MODE!=='self_hosted'||FAMILYHUB_ENABLE_PROJECT_INVITATIONS!==false)stop('fixed_crypto23_config_guard');
 if(defined('FAMILYHUB_DEVELOPMENT_MODE')&&FAMILYHUB_DEVELOPMENT_MODE)stop('development_rejected');
 $port=defined('DB_PORT')&&DB_PORT?DB_PORT:3306;$p=new PDO('mysql:host='.DB_HOSTNAME.';port='.$port.';dbname='.DB_NAME.';charset=utf8mb4',DB_USERNAME,DB_PASSWORD,[PDO::ATTR_ERRMODE=>PDO::ERRMODE_EXCEPTION,PDO::ATTR_TIMEOUT=>10,PDO::ATTR_DEFAULT_FETCH_MODE=>PDO::FETCH_ASSOC]);if($p->query('SELECT DATABASE()')->fetchColumn()!==DB_EXPECTED)stop('actual_database_guard');
 if(!str_starts_with((string)$p->query('SELECT VERSION()')->fetchColumn(),'10.11.19-MariaDB'))stop('actual_mariadb_version_guard');$p->exec('SET SESSION lock_wait_timeout=15');$p->exec('SET SESSION innodb_lock_wait_timeout=15');return $p;
}
function identity(PDO $p):array{
 $id=$p->query('SELECT server_id FROM familyhub_instance WHERE id=1')->fetchColumn();$schema=(int)$p->query("SELECT version FROM plugin_schema_versions WHERE plugin='familyhub'")->fetchColumn();$accounts=(int)$p->query('SELECT COUNT(*) FROM familyhub_accounts')->fetchColumn();
 if($id!==SERVER_ID||$schema!==23||$accounts<1)stop('existing_crypto23_identity_guard');
 if(hashes(SITE.'/plugins/FamilyHub')!==sourceManifest()['old'])stop('current_source_manifest_mismatch');
 return ['serverId'=>$id,'schema'=>$schema,'pluginVersion'=>'0.16.0','nativeAccounts'=>$accounts,'nativeDevices'=>(int)$p->query('SELECT COUNT(*) FROM familyhub_devices')->fetchColumn()];
}
function dump(PDO $p,array $defs,string $path):void{
 if(file_exists($path)||is_link($path))stop('dump_exists');$f=fopen($path,'xb');if(!$f)stop('dump_create');chmod($path,0600);
 $put=function(string $v)use($f){if(fwrite($f,$v)!==strlen($v))stop('dump_write');};
 try{$put("-- Private fresh-reset23 logical backup. Never import to live hosting.\nSET NAMES utf8mb4;\nSET FOREIGN_KEY_CHECKS=0;\n");foreach($defs as$name=>$def){$put($def['create'].";\n");$q=$p->query('SELECT * FROM '.id($name).' ORDER BY '.implode(',',array_map('id',$def['order'])));while($row=$q->fetch(PDO::FETCH_ASSOC)){$values=[];foreach($row as$val)$values[]=$val===null?'NULL':"X'".bin2hex((string)$val)."'";$put('INSERT INTO '.id($name).' ('.implode(',',array_map('id',$def['columns'])).') VALUES ('.implode(',',$values).");\n");}$q->closeCursor();}$put("SET FOREIGN_KEY_CHECKS=1;\n");if(!fflush($f))stop('dump_flush');}finally{fclose($f);}
}
function archive(string $work):array{
 $items=inventory($work);$z=new ZipArchive();$path=$work.'/FreshReset23-private-backup.zip';if($z->open($path,ZipArchive::CREATE|ZipArchive::EXCL)!==true)stop('zip_create');
 try{foreach($items as$n=>$m){$info=fileperms($work.'/'.$n);if(($info&0077)!==0)stop('archive_source_permissions');if(!$z->addFile($work.'/'.$n,$n))stop('zip_add');$z->setExternalAttributesName($n,ZipArchive::OPSYS_UNIX,0100600<<16);}}finally{if(!$z->close())stop('zip_close');}chmod($path,0600);
 $check=new ZipArchive();if($check->open($path,ZipArchive::RDONLY)!==true)stop('archive_reopen');try{if($check->numFiles!==count($items))stop('archive_count');foreach($items as$n=>$m){$body=$check->getFromName($n);if(!is_string($body)||strlen($body)!==$m['bytes']||hash('sha256',$body)!==$m['sha256'])stop('archive_hash');$stat=$check->statName($n);if(hash('crc32b',$body)!==sprintf('%08x',$stat['crc']))stop('archive_crc');}}finally{$check->close();}
 $sha=hash('sha256',bytes($path));writePrivate($path.'.sha256',$sha."  FreshReset23-private-backup.zip\n");return ['archivePath'=>$path,'archiveSha256'=>$sha,'archiveBytes'=>filesize($path),'archiveEntries'=>count($items)];
}
/** Same fixed runtime lock used by NativeCryptoMaintenanceLease. Export creates it
 * before the frozen full-file inventory; subsequent steps require that inode. */
function resetLease(bool $create=false) {
 $dir=DATA.'/familyhub/crypto';foreach([DATA.'/familyhub',$dir]as$d){if(is_link($d))stop('lease_directory_symlink');if(!is_dir($d)){if(!$create||!mkdir($d,0700))stop('lease_directory_required');chmod($d,0700);}directory($d,true);}
 $path=$dir.'/migration.lock';if(is_link($path)||(!$create&&!is_file($path)))stop('existing_lease_inode_required');$h=fopen($path,'c');if(!$h||!flock($h,LOCK_EX|LOCK_NB))stop('exclusive_crypto_lease_required');chmod($path,0600);$a=fstat($h);$b=stat($path);if($a['ino']!==$b['ino']||$a['dev']!==$b['dev'])stop('lease_inode_changed');return $h;
}
