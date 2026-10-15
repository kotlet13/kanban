<?php
/** Read-only live verification; never loads Kanboard common.php or launches workers. */
if (PHP_SAPI !== 'cli') { http_response_code(404); exit; }
ini_set('display_errors','0');ini_set('log_errors','0');error_reporting(0);umask(0077);
try {
    $helper='/home/tripar13/private/jivie-test/upgrade-0.11.1/upgrade-cpanel-jivie-notifications.php';
    if(is_link($helper)||!is_file($helper))throw new RuntimeException();
    $source=file_get_contents($helper);$boundary=strpos($source,"try{\n    \$mode=");
    if($boundary===false)throw new RuntimeException();
    // Definitions only. The helper's CLI dispatch, file lock and mutations are omitted.
    eval(substr($source,5,$boundary-5));
    $pdo=config();$state=data(STATE);if(($state['phase']??null)!=='released')fail('released_phase_required');
    unchangedConfig($state);$manifest=verifyBundle();$expected=[];
    foreach($manifest['files']as$name=>$hash)$expected[substr($name,strlen('FamilyHub/'))]=$hash;
    ksort($expected);if(inventory(SITE.'/plugins/FamilyHub')!==$expected)fail('active_manifest_mismatch');
    if(!preg_match("/function getPluginVersion\\(\\)\\s*\\{\\s*return '0\\.11\\.1';\\s*\\}/",bytes(SITE.'/plugins/FamilyHub/Plugin.php')))fail('plugin_version_mismatch');
    // Fresh crontab bytes arrive through stdin; the verifier writes no proof file.
    $freshCron=stream_get_contents(STDIN);if(!is_string($freshCron)||!hash_equals(hash_file('sha256',ORIGINAL),hash('sha256',$freshCron)))fail('fresh_original_cron_mismatch');
    $oldHt=data(WORK.'/htaccess.original');
    if($oldHt['existed']){if(bytes(SITE.'/.htaccess')!==base64_decode($oldHt['bytes'],true))fail('original_htaccess_mismatch');}
    elseif(file_exists(SITE.'/.htaccess'))fail('original_htaccess_mismatch');
    require SITE.'/app/Core/Base.php';
    require SITE.'/plugins/FamilyHub/Model/NativeDatabase.php';
    require SITE.'/plugins/FamilyHub/Model/NativeNotificationPreferences.php';
    $preferenceClass='Kanboard\\Plugin\\FamilyHub\\Model\\NativeNotificationPreferences';
    if($preferenceClass::CATEGORIES!==['tasks','events','shopping','finance','reminders','membership'])fail('category_contract_mismatch');
    $defaults=$preferenceClass::resolve();
    if($defaults!==['inApp'=>true,'sound'=>true,'push'=>true,'email'=>false])fail('notification_defaults_mismatch');
    $allOff=['inApp'=>false,'push'=>false,'email'=>false,'sound'=>false];
    if($preferenceClass::resolve(json_encode($allOff))!==array_replace($defaults,$allOff))fail('explicit_opt_out_mismatch');
    $pdo->exec('SET TRANSACTION READ ONLY');$pdo->exec('START TRANSACTION WITH CONSISTENT SNAPSHOT');
    try {
      $now=snapshot($pdo);if($now['schema']!==15)fail('schema_15_required');
      if($state['before']!==$state['after'])fail('activation_database_mismatch');
      if(databaseDefinition($pdo)!==$state['databaseDefinition']||query($pdo,'SELECT * FROM plugin_schema_versions ORDER BY plugin')!==$state['pluginSchemaRows'])fail('live_schema_definition_mismatch');
      $savedPreferences=query($pdo,'SELECT settings FROM familyhub_inbox_preferences');$savedOptOuts=0;
      foreach($savedPreferences as $row){
        $saved=json_decode($row['settings'],true,32,JSON_THROW_ON_ERROR);if(!is_array($saved))fail('saved_preference_shape');$resolved=$preferenceClass::resolve($row['settings']);
        foreach(['inApp','push','email','sound'] as $channel){if(array_key_exists($channel,$saved)){if($resolved[$channel]!==$saved[$channel])fail('saved_preference_not_preserved');if($saved[$channel]===false)$savedOptOuts++;}}
      }
      $preferenceRowsMatch=$now['tables']['familyhub_inbox_preferences']===$state['before']['tables']['familyhub_inbox_preferences'];
      foreach(['serverId','accountHash','passwordHash','enrollmentHash']as$field){
        if($now[$field]!==$state['before'][$field]||$state['after'][$field]!==$state['before'][$field])fail('identity_or_enrollment_mismatch');
      }
      $oldColumns=array_map(fn($table)=>$table['columns'],$state['before']['tables']);
      $oldTablesNow=tableState($pdo,$oldColumns);$matchingOldTables=0;
      foreach($state['before']['tables']as$name=>$old){if(($oldTablesNow[$name]??null)===$old)$matchingOldTables++;}
      // Workers and permitted users may write after release. Report current hashes
      // separately from the activation guard, without treating those writes as loss.
      $policiesNowMatch=$oldTablesNow['familyhub_scopes']===$state['before']['tables']['familyhub_scopes'];
      $invitationsNowMatch=$oldTablesNow['familyhub_invitations']===$state['before']['tables']['familyhub_invitations'];
    } finally { $pdo->rollBack(); }
    $workers=[];
    foreach(['reminders','account-mail','delivery','deletion','push']as$name){
      $path=BASE.'/'.$name.'-status.json';$valid=false;$modified=null;$mode=null;$counters=[];$shape=false;
      if(is_link($path))fail('worker_status_symlink');
      if(!is_link($path)&&is_file($path)){
        $body=file_get_contents($path);if(strlen($body)>65536)fail('worker_status_size');
        $decoded=json_decode($body,true);$valid=json_last_error()===JSON_ERROR_NONE&&is_array($decoded);
        $modified=gmdate('c',filemtime($path));$mode=decoct(fileperms($path)&0777);
        $required=match($name){'reminders'=>['examined','delivered','cancelled'],'deletion'=>['complete','pending'],'push'=>['examined','accepted','retry','cancelled','coalesced'],default=>['examined','accepted','retry','cancelled']};
        $shape=$valid;foreach($required as $key){if(!isset($decoded[$key])||!is_int($decoded[$key])||$decoded[$key]<0)$shape=false;else $counters[$key]=$decoded[$key];}
      }
      $updated=is_file($path)?filemtime($path):null;$age=$updated===null?null:time()-$updated;
      $workers[$name]=['updatedUtc'=>$modified,'validJson'=>$valid,'mode'=>$mode,'ageSeconds'=>$age,'updatedAfterRelease'=>$updated!==null&&$updated>=filemtime(STATE),'expectedStatusShape'=>$shape,'counters'=>$counters];
    }
    $result=['verifiedAtUtc'=>gmdate('c'),'phase'=>$state['phase'],'schema'=>$now['schema'],'pluginVersion'=>'0.11.1',
      'manifestFiles'=>count($expected),'manifestMatches'=>true,'configMatches'=>true,'originalCronMatches'=>true,
      'originalHtaccessMatches'=>true,'sameAccountPasswordsEnrollmentAndServerId'=>true,
      'notificationPreferences'=>['categories'=>$preferenceClass::CATEGORIES,'defaults'=>$defaults,'savedRowsChecked'=>count($savedPreferences),'savedChannelOptOutsChecked'=>$savedOptOuts,'existingSavedValuesResolveExactly'=>true,'savedRowsCurrentlyMatchBackup'=>$preferenceRowsMatch,'savedRowsUnchangedAtActivation'=>true],
      'codeOnlyUpgradeEvidence'=>['beforeSchema'=>$state['before']['schema'],'afterSchema'=>$state['after']['schema'],
        'guardRecordedHealthyBeforeRelease'=>true,'historicTablesGuardedAtActivation'=>count($state['before']['tables']),
        'currentHistoricTablesMatching'=> $matchingOldTables,'schemaDefinitionsAndAllPluginVersionRowsUnchanged'=>true,'currentScopesHistoricColumnsMatch'=>$policiesNowMatch,
        'currentInvitationsHistoricColumnsMatch'=>$invitationsNowMatch,'liveWritesAllowedAfterRelease'=>true],
      'workers'=>$workers,'applicationOrWorkersLaunchedByVerifier'=>false];
    echo json($result);
} catch(Throwable $error) { fwrite(STDERR,"Hosted verification stopped; no secret or exception was logged.\n");exit(1); }
