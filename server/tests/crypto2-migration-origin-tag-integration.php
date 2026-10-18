<?php
/** Signed baseline tags are not ordinary business-write permission. */
require __DIR__.'/crypto2-creation-integration.php';
use Kanboard\Plugin\FamilyHub\Model\NativeCryptoRecordProofV2;

$codec=new NativeCryptoRecordProofV2($container);
$row=row2($newId,$head,$fresh,$freshKeys);
$tag=['version'=>3,'migrationId'=>uid(),'captureId'=>uid(),'bindingId'=>uid(),
    'sourceInventoryRoot'=>hash('sha256',random_bytes(32))];
$row['metadata']['migrationOrigin']=$tag;
$codec->record($row);
ck(true,'closed Capture3 origin tag parses only as genesis evidence context');
$before=(int)q('SELECT COUNT(*) n FROM familyhub_crypto_records WHERE scope_id=?',[$newId])[0]['n'];
deny(fn()=>call('crypto2.records.batch',batch2([$row],$fresh,$freshKeys),$fresh),
    'crypto_migration_origin_forbidden','ordinary authenticated business writer cannot publish a migration-tagged baseline');
ck((int)q('SELECT COUNT(*) n FROM familyhub_crypto_records WHERE scope_id=?',[$newId])[0]['n']===$before,
    'rejected migration tag leaves business records and cursor unchanged');
foreach ([null,$tag+['unexpected'=>true],array_merge($tag,['version'=>2]),
    array_merge($tag,['bindingId'=>'11111111-1111-8111-8111-111111111111'])] as $bad) {
    $changed=$row;$changed['metadata']['migrationOrigin']=$bad;
    deny(fn()=>$codec->record($changed),'validation_error','malformed or noncanonical origin tag is rejected');
}
$changed=$row;$changed['expectedRevision']=1;$changed['previousRecordHash']=hash('sha256','prior');
deny(fn()=>$codec->record($changed),'crypto_migration_origin_context',
    'ordinary later revision cannot retain or reissue the baseline migration tag');
$untagged=$row;unset($untagged['metadata']['migrationOrigin']);
ck(call('crypto2.records.batch',batch2([$untagged],$fresh,$freshKeys),$fresh)['status']==='applied',
    'normal fresh authorized untagged business creation remains available');
echo 'Crypto2 signed migration origin boundary: '.$checks.' cumulative checks PASS'.PHP_EOL;
