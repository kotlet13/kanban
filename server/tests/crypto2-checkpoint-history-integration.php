<?php
require __DIR__.'/crypto2-storage-integration.php';

use Kanboard\Plugin\FamilyHub\Model\NativeCryptoCodec;

$selector = ['membershipHeadHash'=>$checkpoint['membershipHeadHash'],
    'sequence'=>$checkpoint['expectedSequence'],'manifestHash'=>$checkpoint['manifestHash'],
    'recordCount'=>$checkpoint['recordCount'],'proofHash'=>$cp['proofHash']];
$snapshotRequest = ['scopeId'=>$space['id'],'domain'=>'content','accessRevision'=>$space['accessRevision'],'checkpoint'=>$selector,'limit'=>2];
$seen = [];
$after = null;
do {
    $page = call('crypto2.domain.inventory', $snapshotRequest + ($after === null ? [] : ['afterId'=>$after]), $fresh);
    ck($page['membershipHeadHash'] === $selector['membershipHeadHash'] && $page['scopeSequence'] === $selector['sequence'], 'historical inventory page labels its exact observed head and sequence, never current');
    array_push($seen,...$page['descriptors']);
    $after = $page['nextAfterId'];
} while ($page['hasMore']);
ck($seen === $inventory['descriptors'], 'highest immutable historical revision per wire/domain reconstructs exact original checkpoint after later writes');
$hash = hash_init('sha256');
foreach ($seen as $descriptor) hash_update($hash,NativeCryptoCodec::canonical((object)$descriptor)."\n");
ck(hash_final($hash) === $selector['manifestHash'] && count($seen) === $selector['recordCount'], 'complete bounded snapshot descriptor stream matches observed signed count/root');
$taskBefore = q('SELECT revision,authorization FROM familyhub_crypto_records WHERE scope_id=? AND id=?',[$space['id'],$task['id']])[0];
$beforeProof = json_decode($taskBefore['authorization'],true)['recordProof'];
$tombstone = row2($space['id'],$activeHead,$fresh,$freshKeys,$task['id'],'task',(int)$taskBefore['revision'],hash('sha256',NativeCryptoCodec::canonical((object)$beforeProof)),[],[],true);
call('crypto2.records.batch',batch2([$tombstone],$fresh,$freshKeys),$fresh);
$afterDelete = call('crypto2.domain.inventory',array_replace($snapshotRequest,['limit'=>50]),$fresh);
ck($afterDelete['descriptors'] === $inventory['descriptors'], 'later legitimate tombstone does not erase the exact older observed snapshot');
foreach (['manifestHash'=>str_repeat('0',64),'recordCount'=>$selector['recordCount']+1,'proofHash'=>str_repeat('0',64),'sequence'=>$selector['sequence']+1] as $field=>$value) {
    $bad = array_replace($selector,[$field=>$value]);
    deny(fn()=>call('crypto2.domain.inventory',array_replace($snapshotRequest,['checkpoint'=>$bad]),$fresh),'crypto_checkpoint_unavailable','snapshot selector rejects changed '.$field);
}
deny(fn()=>call('crypto2.domain.inventory',array_replace($snapshotRequest,['domain'=>'finance']),$fresh),'crypto_checkpoint_unavailable','observed content checkpoint cannot select financial inventory');
q('UPDATE familyhub_members SET active=0 WHERE scope_id=? AND account_id=?',[$space['id'],$fresh['user']['accountId']]);
deny(fn()=>call('crypto2.domain.inventory',$snapshotRequest,$fresh),'permission_revoked','historical selector does not bypass current scope READ');
q('UPDATE familyhub_members SET active=1 WHERE scope_id=? AND account_id=?',[$space['id'],$fresh['user']['accountId']]);
$digestOnly = ['scopeId'=>$space['id'],'domain'=>'content','accessRevision'=>$space['accessRevision'],'recordProofHash'=>$pair['records'][0]['recordProofHash']];
$found = call('crypto2.records.historyGet',$digestOnly,$fresh);
ck($found['record']['id']===$a['id'] && $found['record']['revision']===1,'opaque sibling digest resolves only its exact authorized historical proof without guessed wire ID');
ck($found['record']['authorization']===$oldRecord['record']['authorization'],'hash-only history candidate preserves exact record and batch authorization');
deny(fn()=>call('crypto2.records.historyGet',$digestOnly+['id'=>$a['id']],$fresh),'validation_error','history selector rejects unpaired wire ID/revision');
deny(fn()=>call('crypto2.records.historyGet',array_replace($digestOnly,['recordProofHash'=>str_repeat('0',64)]),$fresh),'crypto_record_missing','unknown opaque proof digest does not fabricate absence of a whole group');
deny(fn()=>call('crypto2.records.historyGet',array_replace($digestOnly,['domain'=>'finance']),$fresh),'crypto_record_missing','digest-only history lookup cannot cross authorized domain namespace');
echo 'Crypto2 exact checkpoint history integration: '.$checks.' checks PASS'.PHP_EOL;
