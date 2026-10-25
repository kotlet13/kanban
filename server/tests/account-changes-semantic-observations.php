<?php
require __DIR__.'/account-changes-semantic-fixture.php';
use Kanboard\Plugin\FamilyHub\Model\NativeCryptoDirectoryV2;
use Kanboard\Plugin\FamilyHub\Model\NativeNotificationWriter;
$initial=$probe(null);$cursor=$initial['cursor'];
ck($initial['directoryHintsVersion']===1,'new server explicitly advertises semantic directory hint version1');
ck(!$probe($cursor)['changed']&&$probe($cursor)['cursor']===$cursor,'prepared idle account has an exact stable cursor');
$events=[
 'scopeObserve'=>['scopeToken'=>str_repeat('a',64),'headHash'=>str_repeat('b',64),'observationHash'=>str_repeat('c',64)],
 'protectionReady'=>['scopeManifestHash'=>str_repeat('d',64),'deviceSnapshotHash'=>NativeCryptoDirectoryV2::deviceHash(json_decode($directory->current(id(1))['snapshot'],true))],
 'migrationAttest'=>['migrationId'=>id(50),'scopeToken'=>str_repeat('e',64),'domain'=>'content','attestationHash'=>str_repeat('f',64)],
 'recoveryStart'=>[],
 'scheduleUse'=>['useToken'=>str_repeat('1',64),'useProofHash'=>str_repeat('2',64),'active'=>false],
 'scopeDeletion'=>['scopeToken'=>str_repeat('3',64),'certificateHash'=>str_repeat('4',64)],
 'projectRelocation'=>['actionId'=>id(60),'publicationRoot'=>str_repeat('5',64)],
];
foreach($events as $kind=>$fields){
    $before=$directory->current(id(1));
    semanticAppend(id(1),'crypto2.account.'.$kind,$fields,null,$kind==='recoveryStart'?'root':'device');
    $after=$directory->current(id(1));$reply=$probe($cursor);
    ck($after['generation']===$before['generation']+1&&$after['head_hash']!==$before['head_hash']&&$after['snapshot_hash']===$before['snapshot_hash'], $kind.' real verified reducer advances log but preserves security snapshot');
    ck($reply['accountDomains']===['directory']&&$reply['scopes']===[], $kind.' log-only model event selects directory only without content finance access');
    $cursor=$reply['cursor'];ck(!$probe($cursor)['changed'],$kind.' acknowledged event returns to idle');
}
// The following are central paired-effect seams, not fabricated claim that
// companions are noise. scheduleUse is companion-only at ServiceV2:11 and both
// NotificationV2 reminder cancel:218 / put:303 call this exact counter hook.
$pdo->beginTransaction();(new NativeNotificationWriter(['db'=>$db]))->configurationChanged(id(1));$pdo->commit();
$schedule=$probe($cursor);ck($schedule['accountDomains']===['inbox']&&$schedule['scopes']===[],'paired reminder consent uses actual configurationChanged hook and inbox only');$cursor=$schedule['cursor'];
semanticTaskCommit();$task=$probe($cursor);
ck($task['accountDomains']===[]&&$task['scopes']===[['scopeId'=>id(3),'domains'=>['content']]],'committed task counter selects only changed scope content');
semanticAppend(id(1),'crypto2.account.scopeObserve',['scopeToken'=>str_repeat('a',64),'headHash'=>str_repeat('b',64),'observationHash'=>str_repeat('6',64)]);
$taskObserved=$probe($cursor);
ck($taskObserved['accountDomains']===['directory']&&$taskObserved['scopes']===[['scopeId'=>id(3),'domains'=>['content']]],'task followed by real observation retains content-only selection and adds directory hint');
$cursor=$taskObserved['cursor'];ck(!$probe($cursor)['changed']&&$probe($cursor)['cursor']===$cursor,'task plus observation durable cursor returns to exact idle');
semanticTaskCommit(true);$deleted=$probe($cursor);ck($deleted['scopes']===[['scopeId'=>id(3),'domains'=>['content']]],'inline deletion uses normal batch domain-counter seam, no finance fanout');$cursor=$deleted['cursor'];
// Full deletion removes current visibility (ScopeDeletionV2:67); relocation
// install creates visible target + records (RelocationCommitV2:27-35).
$pdo->beginTransaction();sql('UPDATE familyhub_scopes SET deleted_at=1 WHERE id=?',[id(6)]);$pdo->commit();
$removed=$probe($cursor);ck($removed['accountDomains']===['access']&&$removed['scopes']===[],'paired full scope deletion changes visible keyset without leaking removed scope');$cursor=$removed['cursor'];
$pdo->beginTransaction();sql("INSERT INTO familyhub_scopes(id,kind,name,owner_id,sequence,created_at,access_policy_version,parent_scope_id) VALUES(?,'project','RELOCATION_SENTINEL',1,1,1,3,?)",[id(7),id(3)]);$pdo->commit();
$moved=$probe($cursor);ck($moved['accountDomains']===['access']&&array_column($moved['scopes'],'scopeId')===[id(7)],'paired relocation target/catalog seam wakes newly visible target');
$service->queries=[];$stable=$probe($moved['cursor']);
ck(!$stable['changed']&&!preg_match('/familyhub_(crypto_records|records|finance_records|crypto_directory\b|tables|attachments)|\b(snapshot|envelope|authorization|payload|manifest|keyring)\b/',implode("\n",$service->queries)),'stable semantic probe selects hashes not signed snapshots business rows or envelopes');
semanticResult('account-changes-semantic-observations');
