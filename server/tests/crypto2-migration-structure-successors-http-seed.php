<?php
/** Optional post-cutover management fixture; private output, no live service. */
putenv('JIVIE_CAPTURE_TEST_SHARED=0');
putenv('JIVIE_CAPTURE_TEST_INBOX_STATE=0');
ob_start();
require __DIR__.'/crypto2-migration-http-seed.php';
$fixture=json_decode(ob_get_clean(),true,128,JSON_THROW_ON_ERROR);
seedMigrationSql("UPDATE familyhub_scopes SET kind='organization' WHERE id=?",[$fixture['scopeId']]);
$guestName='successor_guest_'.bin2hex(random_bytes(10));$guestPassword=bin2hex(random_bytes(20));
$container['userModel']->create(['username'=>$guestName,'password'=>$guestPassword,'role'=>'app-user']);
$guest=$api->dispatch('auth.login',['username'=>$guestName,'password'=>$guestPassword,'deviceName'=>'Synthetic later member'],'',$guestName);
seedMigrationSql('INSERT INTO familyhub_email_identities(account_id,email,verified_at,revision) VALUES(?,?,?,1)',[$guest['user']['accountId'],$guestName.'@capture.invalid',time()]);
$api->dispatch('moderation.acceptPolicy',['policyVersion'=>1],'Bearer '.$guest['token'],$guestName);
$fixture['successorGuest']=['session'=>$guest,'username'=>$guestName,'password'=>$guestPassword];
echo json_encode($fixture,JSON_THROW_ON_ERROR).PHP_EOL;
