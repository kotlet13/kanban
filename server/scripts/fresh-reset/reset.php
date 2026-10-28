<?php
/** Private schema23 reset controller. CLI only, no application bootstrap. */
require __DIR__.'/backup-library.php';
require __DIR__.'/ResetDatabase.php';require __DIR__.'/InventoryFiles.php';
require WORK.'/maintenance-guards.php';require WORK.'/delivery-guards.php';
function stateRead():array{return json_decode(bytes(WORK.'/reset-state.json'),true,512,JSON_THROW_ON_ERROR);}
function stateSave(array $s):void{$tmp=WORK.'/reset-state.next';writePrivate($tmp,json($s));$h=fopen($tmp,'r+');if(!$h||!fflush($h)||(function_exists('fsync')&&!fsync($h)))stop('journal_sync');fclose($h);if(!rename($tmp,WORK.'/reset-state.json'))stop('journal_replace');}
function jsonFile(string $path):array{return json_decode(bytes($path),true,512,JSON_THROW_ON_ERROR);}
function approvedDefinitions():array{if(hash('sha256',bytes(WORK.'/schema-definitions.json'))!==SCHEMA_DEFINITIONS_SHA)stop('independent_schema_manifest_hash');return jsonFile(WORK.'/schema-definitions.json');}
function originalPins():void{if(hash('sha256',bytes(WORK.'/crontab.original'))!==CRON_SHA||hash('sha256',bytes(WORK.'/htaccess.original'))!==HTACCESS_SHA)stop('saved_original_pins');}
function proof(string $sha,array $m):void{
 $r=jsonFile(WORK.'/restore-proof.json');
 foreach(['everyRowAndFileHashMatches','everyTableDefinitionHashMatches','passwordsAccountsSessionsRecordsPreserved','configHttpsAndCronHashesMatch','deliveryConfigAndKeysMatch','completeSiteSourceHashesMatch','sourceHashesMatch','onlyAnonymousMysqlVolume']as$k)if(($r[$k]??null)!==true)stop('isolated_restore_proof_flag');
 if(($r['format']??'')!=='fresh-reset23-restore-proof-v1'||($r['archiveSha256']??'')!==$sha||($r['serverId']??'')!==SERVER_ID||($r['schema']??0)!==23||($r['sqlSha256']??'')!==$m['databaseSqlSha256']||($r['database']??'')!=='MariaDB 10.11.19'||($r['isolatedNetwork']??'')!=='none'||($r['ports']??null)!==false||($r['hostBindMounts']??null)!==false||($r['applicationOrWorkersStarted']??null)!==false||($r['liveHostedDatabaseTouched']??null)!==false||($r['tablesVerified']??0)!==count($m['tables'])||($r['rowsVerified']??-1)!==array_sum(array_column($m['tables'],'rows'))||($r['sourceFilesVerified']??0)!==SOURCE_COUNT)stop('isolated_restore_proof_binding');
}
function archiveManifest(string $archive,string $sha):array{
 if(!preg_match('/^[a-f0-9]{64}$/D',$sha)||!str_starts_with($archive,BACKUPS.'/fresh-reset23-before-')||!str_ends_with($archive,'/FreshReset23-private-backup.zip')||hash('sha256',bytes($archive))!==$sha)stop('fresh_backup_archive_guard');
 $z=new ZipArchive();if($z->open($archive,ZipArchive::RDONLY)!==true)stop('backup_open');try{$raw=$z->getFromName('manifest.json');$sql=$z->getFromName('database.sql');if(!is_string($raw)||!is_string($sql))stop('backup_entries');$m=json_decode($raw,true,512,JSON_THROW_ON_ERROR);if(hash('sha256',$sql)!==($m['databaseSqlSha256']??''))stop('backup_sql_hash');}finally{$z->close();}
 if(($m['format']??'')!=='fresh-reset23-backup-v1'||($m['identity']['schema']??0)!==23||($m['identity']['serverId']??'')!==SERVER_ID||($m['database']??'')!==DB_EXPECTED||($m['identity']['nativeAccounts']??0)!==count(TARGET_USERS)||$m['sourceFiles']!==sourceManifest()['old']||$m['rootConfigSha256']!==CONFIG_SHA||$m['cronSha256']!==CRON_SHA||$m['rootHtaccessSha256']!==HTACCESS_SHA||$m['deliveryFiles']!==DELIVERY_FILES)stop('backup_target_binding');
 proof($sha,$m);return $m;
}
function expectedRemaining(array $m):array{$files=$m['dataFiles'];foreach(array_keys($files)as$n)if(str_starts_with($n,'familyhub/attachments/')||str_starts_with($n,'familyhub/ideas/'))unset($files[$n]);return $files;}
function verifyQuarantine(array $s):void{
 $actual=FamilyHubFreshResetFiles::inspect(WORK.'/quarantine-data');if($actual!==$s['files'])stop('quarantined_file_manifest_changed');
 $current=FamilyHubFreshResetFiles::inspect(DATA);if($current['files']!==0)stop('live_business_files_nonempty');
 foreach($current['entries']as$n=>$entry)if(str_contains($n,'/'))stop('unexpected_live_business_directory');
}
function verifyReset(PDO $p,array $s,array $m,bool $afterHttp=false):void{
 if(($s['phase']??'')!=='database_committed'&&($s['phase']??'')!=='verified')stop('committed_phase_required');
 $engine=new FamilyHubFreshReset($p);if($engine->definitions()!==approvedDefinitions())stop('post_reset_schema_changed');
 foreach($s['plan']['deleteOrder']as$t){$rows=rows($p,'SELECT * FROM '.id($t));if($t==='familyhub_instance'){if($rows!==[['id'=>1,'server_id'=>$s['result']['newServerId']]])stop('new_instance_seed_changed');}elseif($t==='familyhub_native_lock'){if(count($rows)!==1||(int)$rows[0]['id']!==1||(int)$rows[0]['counter']!==0)stop('lock_seed_changed');}elseif($rows&&!($afterHttp&&$t==='familyhub_rate_limits'))stop('post_reset_familyhub_table_nonempty');}
 $defs=tableDefs($p);$current=snapshot($p,$defs);foreach($s['retainedTables']as$t=>$before){if($current[$t]!==$before)stop('retained_core_table_changed');}
 if(rows($p,'SELECT * FROM users ORDER BY id')!==$s['retainedUsers'])stop('retained_users_changed');
 if(inventory(DATA)!==expectedRemaining($m))stop('retained_data_file_changed');
 verifyQuarantine($s);deliveryGuard();$siteExpected=$m['siteFiles'];if($afterHttp)$siteExpected['.htaccess']=HTACCESS_SHA;ksort($siteExpected);if(hashes(SITE)!==$siteExpected)stop('complete_live_site_source_changed');
}
try{
 $mode=$argv[1]??'';$p=db();originalPins();$engine=new FamilyHubFreshReset($p);
 if($mode==='--inspect'){
  if($argc!==2)stop('inspect_usage');identity($p);$plan=$engine->plan(approvedDefinitions(),TARGET_USERS,count(TARGET_USERS));echo json(['mode'=>'read_only_reset_inspect','oldServerId'=>SERVER_ID,'users'=>TARGET_USERS,'tables'=>count($plan['deleteOrder']),'rows'=>array_sum($plan['counts']),'files'=>FamilyHubFreshResetFiles::inspect(DATA),'beforeHash'=>$plan['beforeHash']]);exit;
 }
 if(in_array($mode,['--worker-release-check','--confirm-workers-released'],true)){
  if($argc!==2)stop('worker_release_usage');$s=stateRead();if(($s['phase']??'')!=='http_released_workers_paused')stop('worker_release_phase');
  $m=archiveManifest($s['archive'],$s['archiveSha256']);$lease=resetLease(false);$check=$s;$check['phase']='verified';verifyReset($p,$check,$m,true);
  if(hash('sha256',bytes(SITE.'/.htaccess'))!==HTACCESS_SHA)stop('original_https_not_restored');
  $wanted=$mode==='--worker-release-check'?'crontab.paused':'crontab.original';if(bytes(WORK.'/crontab.current')!==bytes(WORK.'/'.$wanted))stop('worker_cron_state');
  if($mode==='--confirm-workers-released'){$cap=jsonFile(WORK.'/public-capabilities.json');if(($cap['data']['serverId']??'')!==$s['result']['newServerId'])stop('new_public_identity_not_verified');$s['phase']='released';stateSave($s);}
  echo json(['phase'=>$mode==='--confirm-workers-released'?'released':'http_released_workers_paused','newServerId'=>$s['result']['newServerId'],'emptyOldDeliveryQueues'=>true,'retainedCoreExact'=>true]);exit;
 }
 if(!in_array($mode,['--stage','--apply','--verify','--release-http'],true)||$argc!==4)stop('reset_usage');
 $archive=$argv[2];$sha=$argv[3];pausedGuard();$lease=resetLease(false);$m=archiveManifest($archive,$sha);
 if($mode==='--stage'){
  if(file_exists(WORK.'/reset-state.json'))stop('stage_already_exists');identity($p);$defs=tableDefs($p);if(snapshot($p,$defs)!==$m['tables']||inventory(DATA)!==$m['dataFiles']||dataDirectories(DATA)!==$m['dataDirectories']||hashes(SITE)!==$m['siteFiles'])stop('fresh_backup_no_longer_matches');
  $plan=$engine->plan(approvedDefinitions(),TARGET_USERS,count(TARGET_USERS));$files=FamilyHubFreshResetFiles::inspect(DATA);$retained=snapshot($p,$defs);foreach(array_keys($retained)as$t)if(str_starts_with($t,'familyhub_')||$t==='users')unset($retained[$t]);$targetIds=array_column(TARGET_USERS,'id');$users=array_values(array_filter(rows($p,'SELECT * FROM users ORDER BY id'),fn($u)=>!in_array((int)$u['id'],$targetIds,true)));
  stateSave(['format'=>'fresh-reset23-operation-v1','phase'=>'staged','archive'=>$archive,'archiveSha256'=>$sha,'plan'=>$plan,'files'=>$files,'retainedTables'=>$retained,'retainedUsers'=>$users]);echo json(['phase'=>'staged','backupRestoreVerified'=>true,'tables'=>count($plan['deleteOrder']),'users'=>count(TARGET_USERS),'businessFiles'=>$files['files']]);exit;
 }
 $s=stateRead();if(($s['archive']??'')!==$archive||($s['archiveSha256']??'')!==$sha||($s['format']??'')!=='fresh-reset23-operation-v1')stop('operation_archive_binding');
 if($mode==='--apply'){
  if($s['phase']!=='staged')stop('apply_requires_staged_once');identity($p);if($engine->plan(approvedDefinitions(),TARGET_USERS,count(TARGET_USERS))!==$s['plan']||FamilyHubFreshResetFiles::inspect(DATA)!==$s['files']||inventory(DATA)!==$m['dataFiles']||hashes(SITE)!==$m['siteFiles'])stop('staged_state_changed');
  makeDir(WORK.'/quarantine-data');makeDir(WORK.'/quarantine-data/familyhub');if(stat(WORK)['dev']!==stat(DATA)['dev'])stop('same_filesystem_quarantine_required');
  $s['phase']='quarantine_started';$s['moved']=[];stateSave($s);
  foreach(['attachments','ideas']as$n){$from=DATA.'/familyhub/'.$n;$to=WORK.'/quarantine-data/familyhub/'.$n;if(is_dir($from)){if(!rename($from,$to))stop('quarantine_rename_failed');$s['moved'][]=$n;stateSave($s);if(!mkdir($from,0700))stop('empty_business_root_create');chmod($from,0700);}}
  verifyQuarantine($s);$s['phase']='files_quarantined';stateSave($s);
  $s['result']=$engine->apply($s['plan'],['http503'=>true,'allWorkersPaused'=>true,'restoreVerified'=>true,'filesQuarantined'=>true,'drainedSeconds'=>time()-(int)trim(bytes(WORK.'/maintenance.started'))]);
  $s['phase']='database_committed';stateSave($s);verifyReset($p,$s,$m);$s['phase']='verified';stateSave($s);echo json(['phase'=>'verified','newServerId'=>$s['result']['newServerId'],'usersDeleted'=>count(TARGET_USERS),'businessFilesQuarantined'=>$s['files']['files'],'retainedCoreExact'=>true,'retainedFilesAndConfigExact'=>true]);exit;
 }
 verifyReset($p,$s,$m);
 if($mode==='--verify'){echo json(['phase'=>'verified','newServerId'=>$s['result']['newServerId'],'retainedCoreExact'=>true,'quarantineExact'=>true]);exit;}
 if($s['phase']!=='verified')stop('release_requires_verified');
 // Manual final release is explicit: this command restores HTTPS only; cron remains paused.
 $tmp=SITE.'/.htaccess.fresh-reset-release';writePrivate($tmp,bytes(WORK.'/htaccess.original'),0644);if((fileperms($tmp)&0777)!==0644)stop('https_release_mode');if(!rename($tmp,SITE.'/.htaccess')||(fileperms(SITE.'/.htaccess')&0777)!==0644)stop('https_release_rename');$s['phase']='http_released_workers_paused';stateSave($s);echo json(['phase'=>$s['phase'],'newServerId'=>$s['result']['newServerId'],'next'=>'verify real TLS capabilities/new SID then explicitly restore original cron']);
}catch(Throwable $e){$code=$e instanceof RuntimeException&&preg_match('/^[a-z0-9_]+$/D',$e->getMessage())?$e->getMessage():'private_diagnostic_required';fwrite(STDERR,'Fresh reset stopped: '.$code.'. Keep maintenance/cron pause, full backup and quarantine; no automatic rollback. No credentials printed.'."\n");exit(1);}
