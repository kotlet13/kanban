<?php
require __DIR__.'/common.php';
try{
 if($argc!==3)stop('usage_profile_current_cron_file');$pdo=setup($argv[1]);if(sourceHashes()!==baseline())stop('exact_old101_source_required');
 $pdo->exec('LOCK TABLES '.implode(',',array_map(fn($t)=>id($t).' READ',tableNames($pdo))));
 try{$first=snapshot($pdo,$argv[2]);if(snapshot($pdo,$argv[2])!==$first||sourceHashes()!==baseline())stop('capture_changed');}finally{$pdo->exec('UNLOCK TABLES');}
 $sourceMeta=[];foreach(PATCH_FILES as$file)$sourceMeta[$file]=meta(cfg('site').'/plugins/FamilyHub/'.$file);
 echo encode(['format'=>'sound-default-code-patch-capture-v1','profile'=>$argv[1],'createdUtc'=>gmdate('c'),'snapshot'=>$first,'targetMetadata'=>$sourceMeta]);
}catch(Throwable$error){secretFreeFailure($error);}
