<?php
/** Synthetic loopback fixture; credentials must stay in the private output. */
ob_start();
require __DIR__.'/crypto2-migration-invitation-http-seed.php';
$fixture=json_decode(ob_get_clean(),true,128,JSON_THROW_ON_ERROR);
$username='retained_recipient_'.bin2hex(random_bytes(8));
$password=bin2hex(random_bytes(20));
$container['userModel']->create(['username'=>$username,'password'=>$password,'role'=>'app-user']);
$recipient=$api->dispatch('auth.login',['username'=>$username,'password'=>$password,'deviceName'=>'Synthetic retained recipient'],'',$username);
seedMigrationSql('INSERT INTO familyhub_email_identities(account_id,email,verified_at,revision) VALUES(?,?,?,1)',[$recipient['user']['accountId'],'synthetic_0@bridge.invalid',time()]);
$api->dispatch('moderation.acceptPolicy',['policyVersion'=>1],'Bearer '.$recipient['token'],$username);
$fixture['recipientSession']=$recipient;
echo json_encode($fixture,JSON_THROW_ON_ERROR).PHP_EOL;
