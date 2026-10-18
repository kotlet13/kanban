<?php
/** Disposable loopback only. Redirect the private fixture; never print tokens. */
putenv('JIVIE_CAPTURE_TEST_SHARED=0');
putenv('JIVIE_CAPTURE_TEST_AUDIT=0');
putenv('JIVIE_CAPTURE_TEST_INBOX_STATE=0');
ob_start();
require __DIR__.'/crypto2-migration-http-seed.php';
$fixture=json_decode(ob_get_clean(),true,128,JSON_THROW_ON_ERROR);
$owner=$fixture['session'];
// Keep the fixture small: owner content metadata plus one existing monetary
// account, and ordinary nonmanager READ materialization of that exact account.
foreach (['familyhub_records','familyhub_operations','familyhub_attachments'] as $table) {
    seedMigrationSql('DELETE FROM '.$table.' WHERE scope_id=?',[$scope]);
}
seedMigrationSql('DELETE FROM familyhub_finance_records WHERE scope_id=? AND id<>?',[$scope,$ledger]);
$readerName='context_reader_'.bin2hex(random_bytes(10));$readerPassword=bin2hex(random_bytes(20));
$container['userModel']->create(['username'=>$readerName,'password'=>$readerPassword,'role'=>'app-user']);
$reader=$api->dispatch('auth.login',['username'=>$readerName,'password'=>$readerPassword,
    'deviceName'=>'Scoped context READ contributor'],'',$readerName);
seedMigrationSql('INSERT INTO familyhub_email_identities(account_id,email,verified_at,revision) VALUES(?,?,?,1)',[
    $reader['user']['accountId'],$readerName.'@capture.invalid',time()]);
$api->dispatch('moderation.acceptPolicy',['policyVersion'=>1],'Bearer '.$reader['token'],$readerName);
seedMigrationSql('INSERT INTO familyhub_members VALUES(?,?,?,?,1)',[
    $scope,$reader['user']['id'],$reader['user']['accountId'],'member']);
seedMigrationSql('UPDATE familyhub_finance_grants SET access_level=? WHERE scope_id=? AND account_id=?',[
    'none',$scope,$owner['user']['accountId']]);
seedMigrationSql('INSERT INTO familyhub_finance_grants VALUES(?,?,?)',[$scope,$reader['user']['accountId'],'read']);
echo json_encode(['synthetic'=>true,'serverUrl'=>$fixture['serverUrl'],'scopeId'=>$scope,'ledgerId'=>$ledger,
    'owner'=>['session'=>$owner,'username'=>$fixture['username'],'password'=>$fixture['password']],
    'reader'=>['session'=>$reader,'username'=>$readerName,'password'=>$readerPassword]],JSON_THROW_ON_ERROR).PHP_EOL;
