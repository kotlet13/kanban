<?php
/** Isolated backend regression: preview must remain exact and read-only. */
require __DIR__.'/crypto2-scope-integration.php';
require __DIR__.'/crypto2-record-helpers.php';
$source=send2('crypto2.scope.create',['id'=>uid(),'kind'=>'household'],$fresh,$freshKeys)['scope'];
$state=call('crypto2.account.status',[],$fresh);
$body=candidate2($source,$state);
$pending=send2('crypto2.scope.headPut',$body,$fresh,$freshKeys);
$head=call('crypto2.scope.headGet',['scopeId'=>$source['id'],'headHash'=>$pending['headHash']],$fresh);
grants2($head,[$head],$fresh,$freshKeys,$root,$epoch);
$manifest=call('crypto2.grants.manifest',['scopeId'=>$source['id'],'headHash'=>$head['headHash']],$fresh);
send2('crypto2.scope.activate',['scopeId'=>$source['id'],'headHash'=>$head['headHash'],'grantManifestHash'=>$manifest['grantManifestHash'],'authorDirectoryHeadHash'=>$state['headHash']],$fresh,$freshKeys);
$project=row2($source['id'],$head,$fresh,$freshKeys,null,'project');
$task=row2($source['id'],$head,$fresh,$freshKeys,null,'task',0,null,[['scopeId'=>$source['id'],'id'=>$project['id']]]);
$unrelated=row2($source['id'],$head,$fresh,$freshKeys,null,'task');
call('crypto2.records.batch',batch2([$project,$task,$unrelated],$fresh,$freshKeys),$fresh);
$params=['scopeId'=>$source['id'],'projectId'=>$project['metadata']['identity']['canonicalId'],'projectWireId'=>$project['id']];
$before=q('SELECT * FROM familyhub_crypto_records WHERE scope_id=? ORDER BY id',[$source['id']]);
$preview=call('crypto2.inlineDelete.preview',$params,$fresh);
ck($preview['canDelete']===true&&$preview['graphCount']===2,'inline deletion preview includes project and dependent task only');
ck($preview['counts']['projects']===1&&$preview['counts']['tasks']===1,'preview preserves exact type counts');
ck(call('crypto2.inlineDelete.preview',$params,$fresh)===$preview,'repeat preview preserves graph and authorization coordinates');
deny(fn()=>call('crypto2.inlineDelete.preview',array_replace($params,['projectId'=>uid()]),$fresh),'crypto_record_identity_binding','canonical/wire substitution remains rejected');
ck(q('SELECT * FROM familyhub_crypto_records WHERE scope_id=? ORDER BY id',[$source['id']])===$before,'preview and rejected substitution leave all records unchanged');
ck(!q('SELECT action_id FROM familyhub_crypto_inline_delete_plans_v2 WHERE scope_id=?',[$source['id']]),'preview creates no deletion plan');
echo 'Inline deletion preview regression: '.$checks.' cumulative checks PASS'.PHP_EOL;
