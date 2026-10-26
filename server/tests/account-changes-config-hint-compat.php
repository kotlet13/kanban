<?php
require __DIR__.'/account-changes-fixture.php';
$config=$probe(null);
// Recreate a correctly signed cursor using the old envelope shape.
$body = json_decode(base64_decode(explode('.', $config['cursor'])[0]), true);
unset($body['notificationConfiguration']);
$encoded = base64_encode(json_encode($body, JSON_THROW_ON_ERROR));
$old = $encoded.'.'.hash_hmac('sha256',$encoded,hash_hmac('sha256', "JivieAccountChanges/v1\n", base64_decode(FAMILYHUB_ACCOUNT_MAIL_KEY_BASE64), true));
$upgraded = $probe($old);
ck($upgraded['changed'] && $upgraded['notificationConfigurationChanged'] && $upgraded['accountDomains'] === ['inbox'], 'old cursor gets one conservative refresh');
ck(!$probe($upgraded['cursor'])['changed'], 'upgraded cursor settles without another refresh');
$other = new ObservedChanges(['db'=>$db],bearer(2),'config-hint-other');
$beforeOther = $other->execute('account.changes',['cursor'=>null]);
sql('UPDATE familyhub_inbox_state SET configuration_revision=configuration_revision+1 WHERE account_id=?',[id(1)]);
$afterOther = $other->execute('account.changes',['cursor'=>$beforeOther['cursor']]);
ck(!$afterOther['changed'] && !$afterOther['notificationConfigurationChanged'], 'configuration cannot cross account binding');
echo json_encode(['test'=>'account-changes-config-hint-compat','status'=>'pass','checks'=>$checks,'fixture'=>'isolated-memory-sqlite','http'=>false]).PHP_EOL;
