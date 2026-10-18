<?php
/** Legacy account erasure cannot bypass durable crypto evidence, even preview-off. */
require __DIR__.'/crypto2-integration.php';
$before=q('SELECT snapshot FROM familyhub_crypto_directory_state WHERE account_id=?',[$fresh['user']['accountId']]);
q('DELETE FROM familyhub_crypto_accounts WHERE account_id=?',[$fresh['user']['accountId']]);
deny(fn()=>call('account.deletion.preview',['policyVersion'=>3],$fresh),'crypto_account_deletion_preparation_required','v2 directory without v1 mirror blocks legacy deletion');
q('DELETE FROM familyhub_crypto_directory_state WHERE account_id=?',[$fresh['user']['accountId']]);
deny(fn()=>call('account.deletion.confirm',[],$fresh),'crypto_account_deletion_preparation_required','immutable directory survives missing derived cache as deletion floor');
$legacy=user('delete_member');$owner=user('delete_owner');$protected=scope($owner);
q("INSERT INTO familyhub_members(scope_id,user_id,account_id,role,active) VALUES(?,?,?,'member',1)",[$protected['id'],$legacy['user']['id'],$legacy['user']['accountId']]);
q('INSERT INTO familyhub_crypto_scope_origins(scope_id,account_id,authorization,created_at) VALUES(?,?,?,?)',[$protected['id'],$owner['user']['accountId'],'{}',time()]);
$membership=q('SELECT * FROM familyhub_members WHERE scope_id=? ORDER BY account_id',[$protected['id']]);
deny(fn()=>call('account.deletion.preview',['policyVersion'=>3],$legacy),'crypto_account_deletion_preparation_required','legacy-only member cannot erase protected foreign membership');
deny(fn()=>call('account.deletion.confirm',[],$legacy),'crypto_account_deletion_preparation_required','legacy-only confirm blocked before step-up or redaction');
ck(q('SELECT * FROM familyhub_members WHERE scope_id=? ORDER BY account_id',[$protected['id']])===$membership,'blocked legacy erase preserves exact membership and active owner');
$parent=scope($legacy,'organization');$child=call('scopes.create',['id'=>uid(),'kind'=>'project','name'=>'Protected descendant','parentScopeId'=>$parent['id'],'requestId'=>uid(),'accessPolicyVersion'=>3],$legacy)['scope'];
q('INSERT INTO familyhub_crypto_scope_origins(scope_id,account_id,authorization,created_at) VALUES(?,?,?,?)',[$child['id'],$legacy['user']['accountId'],'{}',time()]);
// Remove the unrelated direct membership so the descendant path is independently exercised.
q('DELETE FROM familyhub_members WHERE scope_id=? AND account_id=?',[$protected['id'],$legacy['user']['accountId']]);
deny(fn()=>call('account.deletion.preview',['policyVersion'=>3],$legacy),'crypto_account_deletion_preparation_required','owned legacy ancestor cannot detach protected descendant');
ck((bool)q('SELECT id FROM familyhub_scopes WHERE id=? AND parent_scope_id=?',[$child['id'],$parent['id']]),'blocked descendant deletion preserves parent relation');
echo 'Crypto2 deletion boundary integration: '.$checks.' checks PASS'.PHP_EOL;
