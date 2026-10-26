<?php
/** Additive config hint, actual native metadata service with disposable SQLite. */
require __DIR__.'/account-changes-fixture.php';
$first = $probe(null);
ck($first['notificationHintsVersion'] === 1 && $first['notificationConfigurationChanged'], 'initial snapshot requires configuration');
$warm = $probe($first['cursor']);
ck(!$warm['changed'] && !$warm['notificationConfigurationChanged'], 'unchanged snapshot requires no configuration');
sql('INSERT INTO familyhub_inbox_state(account_id,sequence,visibility_revision,configuration_revision) VALUES(?,1,1,0)',[id(1)]);
$inbox = $probe($warm['cursor']);
ck($inbox['accountDomains'] === ['inbox'] && !$inbox['notificationConfigurationChanged'], 'new inbox event does not wake configuration');
sql('UPDATE familyhub_inbox_state SET visibility_revision=visibility_revision+1 WHERE account_id=?',[id(1)]);
$visibility = $probe($inbox['cursor']);
ck($visibility['accountDomains'] === ['inbox'] && !$visibility['notificationConfigurationChanged'], 'inbox visibility has separate configuration signal');
sql('UPDATE familyhub_inbox_state SET configuration_revision=configuration_revision+1 WHERE account_id=?',[id(1)]);
$config = $probe($visibility['cursor']);
ck($config['accountDomains'] === ['inbox'] && $config['notificationConfigurationChanged'], 'configuration change keeps legacy inbox hint and adds precise hint');
echo json_encode(['test'=>'account-changes-config-hint-split','status'=>'pass','checks'=>$checks,'fixture'=>'isolated-memory-sqlite','http'=>false]).PHP_EOL;
