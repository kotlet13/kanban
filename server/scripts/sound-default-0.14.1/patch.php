<?php
require __DIR__.'/common.php';
try{
 require __DIR__.'/deployment.php';if(realpath(__DIR__)!==PATCH_WORK)stop('exact_private_work_required');
 if(hash('sha256',bytes(PATCH_WORK.'/pins.json'))!==PATCH_PINS_SHA)stop('sealed_pins_hash');$pins=readJson(PATCH_WORK.'/pins.json');if(($pins['format']??null)!=='sound-default-code-patch-v1')stop('sealed_format');$pdo=setup($pins['capture']['profile']);directory(PATCH_WORK,true);if(!preg_match('~^'.preg_quote(cfg('base'),'~').'/sound-default-0\.14\.1-[0-9]{8}-[0-9]{6}$~D',PATCH_WORK))stop('fixed_private_work_path');
 $mode=$argv[1]??'';if($argc!==2||!in_array($mode,['--check','--apply'],true))stop('usage_check_apply');if(time()-strtotime($pins['capture']['createdUtc'])>21600)stop('fresh_capture_required');
 $lock=fopen(PATCH_WORK.'/patch.lock','c');if(!$lock||!flock($lock,LOCK_EX|LOCK_NB))stop('concurrent_patch');chmod(PATCH_WORK.'/patch.lock',0600);
 foreach(['patch-intent.json','patch-checkpoint.json','FamilyHub.before']as$name)fresh(PATCH_WORK.'/'.$name);
 $old=baseline();$new=$pins['newManifest'];if(count($new)!==101||array_keys($new)!==array_keys($old))stop('exact101_manifest_shape');$changed=[];foreach($old as$name=>$sha)if($new[$name]!==$sha)$changed[]=$name;$allowed=PATCH_FILES;sort($changed);sort($allowed);if($changed!==$allowed)stop('only_three_php_changes_allowed');
 foreach(PATCH_FILES as$file){$body=bytes(PATCH_WORK.'/files/'.$file);if(hash('sha256',$body)!==$new[$file])stop('staged_php_hash');token_get_all($body,TOKEN_PARSE);}
 $cron=PATCH_WORK.'/crontab.current';if((fileperms($cron)&0077)!==0||time()-filemtime($cron)>120)stop('fresh_private_cron_required');
 $pdo->exec('LOCK TABLES '.implode(',',array_map(fn($t)=>id($t).' READ',tableNames($pdo))));
 try{
  if(sourceHashes()!==$old)stop('exact_old101_source_required');$before=snapshot($pdo,$cron);if($before!==$pins['capture']['snapshot'])stop('database_data_config_cron_changed_recapture_required');foreach(PATCH_FILES as$file)if(meta(cfg('site').'/plugins/FamilyHub/'.$file)!==$pins['capture']['targetMetadata'][$file])stop('target_mode_owner_changed');
  if($mode==='--check'){echo "Exact old101/schema18/identity/config/keys/cron/data/core and all table counts/CREATE/preference hashes checked; staged3PHP parse PASS. No source or database rows changed.\n";}
  else{
   $backup=PATCH_WORK.'/FamilyHub.before';if(!mkdir($backup,0700))stop('private_source_backup_create');
   foreach($old as$file=>$sha){$target=$backup.'/'.$file;if(!is_dir(dirname($target))&&!mkdir(dirname($target),0700,true))stop('private_backup_directory');$body=bytes(cfg('site').'/plugins/FamilyHub/'.$file);if(hash('sha256',$body)!==$sha)stop('source_changed_during_backup');writePrivate($target,$body);}
   $temporary=[];foreach(PATCH_FILES as$file){$path=cfg('site').'/plugins/FamilyHub/'.$file;$temp=dirname($path).'/.'.basename($path).'.sound-default-tmp';fresh($temp);writePrivate($temp,bytes(PATCH_WORK.'/files/'.$file),$pins['capture']['targetMetadata'][$file]['mode']);if(meta($temp)!==$pins['capture']['targetMetadata'][$file])stop('temporary_owner_mode_mismatch');$temporary[$file]=$temp;}
   if(snapshot($pdo,$cron)!==$before)stop('changed_before_source_swap');writePrivate(PATCH_WORK.'/patch-intent.json',encode(['phase'=>'applying-three-php-files','createdUtc'=>gmdate('c'),'profile'=>$pins['capture']['profile'],'serverId'=>cfg('serverId'),'schema'=>18,'preferenceRawHash'=>$before['preferences'],'oldManifest'=>$old,'newManifest'=>$new]));
   foreach(PATCH_FILES as$file){$path=cfg('site').'/plugins/FamilyHub/'.$file;if(hash('sha256',bytes($path))!==$old[$file]||!rename($temporary[$file],$path))stop('atomic_file_replace_failed_keep_private_state');}
   if(sourceHashes()!==$new||snapshot($pdo,$cron)!==$before)stop('post_patch_preservation_guard');foreach(PATCH_FILES as$file)if(meta(cfg('site').'/plugins/FamilyHub/'.$file)!==$pins['capture']['targetMetadata'][$file])stop('post_patch_mode_owner_guard');
   $checkpoint=['phase'=>'code-patch-complete','profile'=>$pins['capture']['profile'],'completedUtc'=>gmdate('c'),'serverId'=>cfg('serverId'),'schema'=>18,'oldVersion'=>'0.14.0','newVersion'=>'0.14.1','changedPhpFiles'=>PATCH_FILES,'sourceFiles'=>101,'oldSourcePrivateBackup'=>$backup,'tablesVerified'=>count($before['tables']),'rowsVerified'=>array_sum(array_column($before['tables'],'rows')),'nativeAccounts'=>$before['identities']['familyhub_accounts']['rows'],'nativeDevices'=>$before['identities']['familyhub_devices']['rows'],'preferenceRows'=>$before['preferences']['rows'],'preferenceRawRowsSha256'=>$before['preferences']['rawRowsSha256'],'allPreferenceBytesPreserved'=>true,'allTableCountsAndCreatePreserved'=>true,'identitiesPasswordsDevicesPreserved'=>true,'configKeysCronDataCoreAndModesPreserved'=>true,'databaseRowsWritten'=>false,'ddlExecuted'=>false,'cronChanged'=>false,'applicationOrWorkersBootstrapped'=>false];writePrivate(PATCH_WORK.'/patch-checkpoint.json',encode($checkpoint));echo encode($checkpoint);
  }
 }finally{$pdo->exec('UNLOCK TABLES');}
}catch(Throwable$error){secretFreeFailure($error);}
