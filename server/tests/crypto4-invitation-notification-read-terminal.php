<?php
/** NEW retired notice read/replay controls. Historical thirteen controls are not invoked. */
use Kanboard\Plugin\FamilyHub\Model\NativeCryptoNotificationV2 as Notifications;
require __DIR__.'/crypto5-invitation-preauthorization-memory-fixture.php';
$pdo->exec('CREATE TABLE familyhub_inbox(id INTEGER PRIMARY KEY,event_key TEXT,recipient_account_id TEXT,scope_id TEXT,category TEXT,kind TEXT,audience TEXT,actor_account_id TEXT,target_type TEXT,target_id TEXT,target_revision INTEGER,group_key TEXT,created_at TEXT,sequence INTEGER,in_app INTEGER,read_at TEXT,revision INTEGER);');
[$sid,$body,$head]=scopeFixture(3,$owner);$id=uid();
$creation=signCommand('crypto2.invitations.create',['scopeId'=>$sid,'invitationId'=>$id,'recipient'=>['kind'=>'email','value'=>$recipient['email'],'accountId'=>null],'role'=>'member','expiresAt'=>time()+3600,'tokenHash'=>hash('sha256','synthetic new account token'),'membershipHeadHash'=>$head],$owner);
sql("INSERT INTO familyhub_crypto_invitations_v2 VALUES(?,?,?,?,?,?,?,?,?,?,?,'consumed',?,? ,NULL)",[$id,$sid,$owner['user']['account_id'],$owner['device']['id'],'email',$recipient['email'],$recipient['user']['account_id'],'member',hash('sha256','synthetic new account token'),time(),time()+3600,json_encode($creation),'en']);
sql("INSERT INTO familyhub_inbox VALUES(1,?,?,?,'membership','crypto2.invitation.accepted','personal',?,'membership',?,1,?,?,1,1,NULL,1)",[hash('sha256','crypto2-invitation-accepted:'.$id.':'.str_repeat('a',64)),$owner['user']['account_id'],$sid,$recipient['user']['account_id'],$id,$sid.':'.$id.':'.str_repeat('a',64).':membership:personal:1',gmdate('Y-m-d\TH:i:s\Z')]);
$notifications=new Notifications($container);$payload=['id'=>1,'read'=>true,'expectedRevision'=>1];
$before=sql('SELECT * FROM familyhub_inbox');
denied(fn()=>$notifications->write('crypto2.inbox.read',$payload,$owner,[]),'notification_missing','retired exact acceptance read is terminal notification missing while scope stays accessible');
denied(fn()=>$notifications->replayAccess('crypto2.inbox.read',$payload,$owner),'notification_missing','retired exact acceptance stored-command replay uses same terminal missing semantics');
denied(fn()=>$notifications->read('crypto2.inbox.open',['id'=>1],$owner),'permission_revoked','retired exact acceptance open still denies confirmation');
denied(fn()=>$notifications->write('crypto2.inbox.read',$payload,$recipient,[]),'permission_revoked','foreign account cannot turn invitation read into missing');
sql('UPDATE users SET is_active=0 WHERE id=?',[$owner['user']['id']]);
denied(fn()=>$notifications->write('crypto2.inbox.read',$payload,$owner,[]),'permission_revoked','real account or scope denial is not downgraded to missing');
ck(sql('SELECT * FROM familyhub_inbox')===$before,'terminal retired notification controls preserve read row and revision');
echo json_encode(['status'=>'pass','checks'=>$checks,'fixture'=>'new isolated memory notification terminal queue seam','limitations'=>'No HTTP or signature-dispatch proof']).PHP_EOL;
