<?php
/** Targeted regression: exact acceptance notification fits production's VARCHAR(120).
 * Real model/proofs on SQLite and optional isolated strict MariaDB. No HTTP/auth dispatcher. */
use Kanboard\Plugin\FamilyHub\Model\NativeCryptoInvitationV2 as Invitations;
use Kanboard\Plugin\FamilyHub\Model\NativeCryptoInvitationNotificationV2 as Notices;
use Kanboard\Plugin\FamilyHub\Model\NativeCryptoV2Codec as V2;
require __DIR__.'/crypto5-invitation-preauthorization-memory-fixture.php';
if (getenv('INVITATION_TEST_MYSQL') === '1') {
    $source=$pdo;
    $target=new PDO('mysql:host=127.0.0.1;dbname=invitation_test','root','local-fixture-only',[PDO::ATTR_ERRMODE=>PDO::ERRMODE_EXCEPTION]);
    $target->exec("SET SESSION sql_mode='STRICT_ALL_TABLES,NO_ENGINE_SUBSTITUTION'");
    // Transfer only this disposable proof fixture. The inbox below uses production bounds.
    foreach ($source->query("SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'")->fetchAll(PDO::FETCH_COLUMN) as $table) {
        $cols=$source->query('PRAGMA table_info('.$table.')')->fetchAll(PDO::FETCH_ASSOC);
        $indexed=[];$unique=[];
        foreach ($source->query('PRAGMA index_list('.$table.')')->fetchAll(PDO::FETCH_ASSOC) as $index) {
            $names=$source->query('PRAGMA index_info('.$index['name'].')')->fetchAll(PDO::FETCH_COLUMN,2);
            foreach($names as $name)$indexed[$name]=true;
            if($index['unique'] && $index['origin']!=='pk')$unique[]=$names;
        }
        $defs=[];$pk=[];
        foreach($cols as $col){
            $name=$col['name'];$type=strtoupper($col['type']);
            if($col['pk'])$pk[$col['pk']]=$name;
            if(str_contains($type,'INT'))$type='BIGINT';
            elseif(isset($indexed[$name]) || $col['pk'])$type='VARCHAR(191) CHARACTER SET ascii';
            else $type='LONGTEXT';
            $defs[]='`'.$name.'` '.$type.($col['notnull']?' NOT NULL':'').($col['dflt_value']!==null?' DEFAULT '.$col['dflt_value']:'');
        }
        if($pk){ksort($pk);$defs[]='PRIMARY KEY (`'.implode('`,`',$pk).'`)';}
        foreach($unique as $names)$defs[]='UNIQUE (`'.implode('`,`',$names).'`)';
        $target->exec('CREATE TABLE `'.$table.'` ('.implode(',',$defs).')');
        foreach($source->query('SELECT * FROM `'.$table.'`')->fetchAll(PDO::FETCH_ASSOC) as $row){$s=$target->prepare('INSERT INTO `'.$table.'` VALUES('.implode(',',array_fill(0,count($row),'?')).')');$s->execute(array_values($row));}
    }
    $pdo=$target;
    $container['db']=new class($pdo){public function __construct(private $pdo){} public function getConnection(){return $this->pdo;}};
    $scopes=new \Kanboard\Plugin\FamilyHub\Model\NativeCryptoScopeV2($container);
}
$mysql=$pdo->getAttribute(PDO::ATTR_DRIVER_NAME)==='mysql';
$auto=$mysql?'BIGINT AUTO_INCREMENT PRIMARY KEY':'INTEGER PRIMARY KEY AUTOINCREMENT';
$pdo->exec("CREATE TABLE familyhub_inbox(id $auto,event_key VARCHAR(64),recipient_account_id VARCHAR(36),scope_id VARCHAR(36),category VARCHAR(20),kind VARCHAR(40),audience VARCHAR(20),actor_account_id VARCHAR(36),target_type VARCHAR(30),target_id VARCHAR(36),target_revision BIGINT,group_key VARCHAR(120),created_at VARCHAR(40),sequence BIGINT,in_app INTEGER,read_at VARCHAR(40) DEFAULT NULL,revision BIGINT DEFAULT 1,UNIQUE(event_key,recipient_account_id))");
$pdo->exec('CREATE TABLE familyhub_inbox_state(account_id VARCHAR(36) PRIMARY KEY,sequence BIGINT,visibility_revision BIGINT)');
$pdo->exec('CREATE TABLE familyhub_inbox_preferences(scope_id VARCHAR(36),account_id VARCHAR(36),category VARCHAR(20),settings TEXT)');
[$sid,$body,$head]=scopeFixture(3,$owner);
$id=uid();$payload=['scopeId'=>$sid,'invitationId'=>$id,'recipient'=>['kind'=>'email','value'=>$recipient['email'],'accountId'=>null],'role'=>'member','expiresAt'=>time()+86400,'language'=>'en','expectedAccessRevision'=>0,'membershipHeadHash'=>$head,'authorDirectoryHeadHash'=>$owner['head'],'tokenHash'=>hash('sha256','synthetic old invitation')];
$creation=signCommand('crypto2.invitations.create',$payload,$owner);
sql('INSERT INTO familyhub_crypto_invitations_v2 VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,NULL)',[$id,$sid,$owner['user']['account_id'],$owner['device']['id'],'email',$recipient['email'],null,'member',$payload['tokenHash'],time()-86400,$payload['expiresAt'],'pending',json_encode($creation),'en']);
$accept=['scopeId'=>$sid,'invitationId'=>$id,'tokenHash'=>$payload['tokenHash'],'creatorProofHash'=>V2::hash((object)$creation),'role'=>'member','expiresAt'=>$payload['expiresAt'],'membershipHeadHash'=>$head,'authorDirectoryHeadHash'=>$recipient['head']];
$proof=signCommand('crypto2.invitations.accept',$accept,$recipient);$hash=V2::hash((object)$proof);
$invites=new Invitations($container);$notices=new Notices($container);
$legacy=$sid.':'.$id.':'.$hash.':membership:personal:'.intdiv(time(),300);
if($mysql){
    try {sql('INSERT INTO familyhub_inbox(group_key) VALUES(?)',[$legacy]);throw new RuntimeException('old oversized group unexpectedly accepted');}
    catch(PDOException $error){ck($error->errorInfo[0]==='22001' && $error->errorInfo[1]===1406,'production SQLSTATE/driver failure reproduced with old group');}
}
$pdo->beginTransaction();
$result=$invites->write('crypto2.invitations.accept',$accept,$recipient,$proof);
$pdo->commit();
$row=sql('SELECT * FROM familyhub_inbox')[0];
ck(strlen($row['group_key'])<=120 && $result['state']==='pendingKeys','existing invitation acceptance commits within production column bound');
$reference=$notices->reference($row);
ck($reference!==null && $reference['acceptanceProofHash']===$hash && $reference['invitationId']===$id,'compact group resolves entire exact proof and invitation');
$legacyRow=$row;$legacyRow['group_key']=$legacy;
ck($notices->reference($legacyRow)===$reference,'already-stored legacy group remains readable');
$pdo->beginTransaction();$notices->accepted($id,$hash);$pdo->commit();
ck(count(sql('SELECT * FROM familyhub_inbox'))===1 && count(sql('SELECT * FROM familyhub_crypto_invitation_acceptances_v2'))===1,'retry keeps one acceptance and one notification');
$bad=$row;$parts=explode(':',$bad['group_key']);$parts[1]='a2_'.rtrim(strtr(base64_encode(str_repeat("\0",32)),'+/','-_'),'=');$bad['group_key']=implode(':',$parts);
ck($notices->reference($bad)===null,'substituted full proof hash rejected');
$bad=$row;$bad['target_id']=uid();ck($notices->reference($bad)===null,'invitation substitution rejected by full event binding');
$bad=$row;$bad['recipient_account_id']=$recipient['user']['account_id'];ck($notices->reference($bad)===null,'recipient substitution rejected');
$bad=$row;$parts=explode(':',$bad['group_key']);$alphabet='ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_';$last=strlen($parts[1])-1;$parts[1][$last]=$alphabet[strpos($alphabet,$parts[1][$last])+1];$bad['group_key']=implode(':',$parts);
ck($notices->reference($bad)===null,'noncanonical base64 padding bits rejected');
ck(count(sql('SELECT * FROM familyhub_members WHERE scope_id=?',[$sid]))===1,'notice does not grant membership or keys');
sql("UPDATE familyhub_crypto_invitations_v2 SET state='revoked' WHERE id=?",[$id]);
ck($notices->reference($row)===null,'revoked invitation remains unusable');
echo json_encode(['status'=>'pass','checks'=>$checks,'database'=>$mysql?'strict MariaDB':'SQLite','groupLength'=>strlen($row['group_key']),'legacyLength'=>strlen($legacy)]).PHP_EOL;
