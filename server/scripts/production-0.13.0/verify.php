<?php
// Fixed production-only database preservation check. No app bootstrap or writes.
if(PHP_SAPI!=='cli'){http_response_code(404);exit;}
ini_set('display_errors','0');ini_set('log_errors','0');error_reporting(0);
try {
 require '/home/tripar13/jivie.triparna.si/config.php';
 if(DB_DRIVER!=='mysql'||DB_NAME!=='tripar13_jivieprod'||DB_HOSTNAME!=='localhost')throw new RuntimeException('identity');
 $p=new PDO('mysql:host='.DB_HOSTNAME.';dbname='.DB_NAME.';charset=utf8mb4',DB_USERNAME,DB_PASSWORD,[PDO::ATTR_ERRMODE=>PDO::ERRMODE_EXCEPTION]);
 $m=json_decode(file_get_contents('/home/tripar13/private/jivie-production/backups/fresh-before-familyhub-20261013/manifest.json'),true,64,JSON_THROW_ON_ERROR);
 $p->exec('SET TRANSACTION READ ONLY');$p->beginTransaction();
 $tables=$p->query('SHOW TABLES')->fetchAll(PDO::FETCH_COLUMN);$verified=0;
 $id=static function($s){if(!preg_match('/^[a-zA-Z0-9_]+$/D',$s))throw new RuntimeException('identifier');return '`'.$s.'`';};
 foreach($m['tables'] as $t=>$def){
  if($t==='plugin_schema_versions')continue;
  $rows=$p->query('SELECT '.implode(',',array_map($id,$def['columns'])).' FROM '.$id($t).' ORDER BY '.implode(',',array_map($id,$def['order'])));
  $h=hash_init('sha256');$count=0;
  while($row=$rows->fetch(PDO::FETCH_ASSOC)){hash_update($h,json_encode(array_map(fn($v)=>$v===null?null:base64_encode((string)$v),$row),JSON_UNESCAPED_SLASHES|JSON_THROW_ON_ERROR)."\n");$count++;}
  if(hash_final($h)!==$def['sha256']||$count!==$def['rows'])throw new RuntimeException('old_row_hash');
  $create=$p->query('SHOW CREATE TABLE '.$id($t))->fetch(PDO::FETCH_ASSOC)['Create Table'];
  if(hash('sha256',$create)!==$def['createSha256'])throw new RuntimeException('old_definition_hash');$verified++;
 }
 $schema=(int)$p->query("SELECT version FROM plugin_schema_versions WHERE plugin='FamilyHub' OR plugin='familyhub'")->fetchColumn();
 if($schema!==17)throw new RuntimeException('schema');
 $counts=[];foreach($tables as$t)if(str_starts_with($t,'familyhub_'))$counts[$t]=(int)$p->query('SELECT COUNT(*) FROM '.$id($t))->fetchColumn();
 foreach($counts as$t=>$n)if(!in_array($t,['familyhub_instance','familyhub_native_lock'],true)&&$n!==0)throw new RuntimeException('not_empty_familyhub');
 if(($counts['familyhub_native_lock']??0)!==1||(int)$p->query('SELECT counter FROM familyhub_native_lock WHERE id=1')->fetchColumn()!==0)throw new RuntimeException('fresh_lock');
 $sid=$p->query('SELECT server_id FROM familyhub_instance WHERE id=1')->fetchColumn();
 if(!is_string($sid)||!preg_match('/^[a-f0-9-]{36}$/D',$sid))throw new RuntimeException('new_instance');
 $p->rollBack();
 echo json_encode(['tables'=>count($tables),'oldTablesUnchanged'=>$verified,'schema'=>$schema,'serverId'=>$sid,'familyhubTables'=>count($counts),'allFamilyhubUserDataEmpty'=>true,'nativeAccounts'=>$counts['familyhub_accounts'],'devices'=>$counts['familyhub_devices'],'users'=>1,'initialAdminPreserved'=>true,'dataPrivate'=>DATA_DIR==='/home/tripar13/private/jivie-production/data','nativeEnabled'=>FAMILYHUB_ENABLE_NATIVE_API,'accountMode'=>FAMILYHUB_ACCOUNT_MODE,'pushEnabled'=>FAMILYHUB_ENABLE_FCM],JSON_PRETTY_PRINT|JSON_THROW_ON_ERROR)."\n";
} catch(Throwable $e){fwrite(STDERR,'Production verify failed: '.($e instanceof RuntimeException&&!($e instanceof PDOException)?$e->getMessage():'private_diagnostic_required')."; no sensitive details printed\n");exit(1);}
