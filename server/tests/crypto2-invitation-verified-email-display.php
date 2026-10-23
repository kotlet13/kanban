<?php
/** New read-only host display seam; no invitation admission, HTTP, SMTP or retained data. */
namespace Kanboard\Core {
    class Base {
        protected $container;
        public function __construct($container) { $this->container=$container; }
        public function __get($name) { return $this->container[$name]; }
    }
}
namespace {
    use Kanboard\Plugin\FamilyHub\Model\NativeCryptoInvitationV2;
    $model=__DIR__.'/../plugins/FamilyHub/Model/';
    foreach (['NativeError','NativeDatabase','NativeCryptoCodec','NativeCryptoV2Codec','NativeCryptoInvitationV2'] as $file) require $model.$file.'.php';
    $pdo=new \PDO('sqlite::memory:');$pdo->setAttribute(\PDO::ATTR_ERRMODE,\PDO::ERRMODE_EXCEPTION);
    $pdo->exec('CREATE TABLE users(id INTEGER PRIMARY KEY,is_active INTEGER,username TEXT,name TEXT,email TEXT);
      CREATE TABLE familyhub_accounts(account_id TEXT PRIMARY KEY,user_id INTEGER);
      CREATE TABLE familyhub_email_identities(account_id TEXT PRIMARY KEY,email TEXT,pending_email TEXT,verified_at INTEGER);');
    $creator='00000000-0000-4000-a000-000000000001';$other='00000000-0000-4000-a000-000000000002';
    $pdo->exec("INSERT INTO users VALUES(1,1,'owner','Owner','UNVERIFIED_USERS_EMAIL_SENTINEL'),(2,1,'recipient','Recipient','OTHER_USERS_EMAIL_SENTINEL')");
    $insert=$pdo->prepare('INSERT INTO familyhub_accounts VALUES(?,?)');$insert->execute([$creator,1]);$insert->execute([$other,2]);
    $insert=$pdo->prepare('INSERT INTO familyhub_email_identities VALUES(?,?,?,?)');
    $insert->execute([$creator,'owner@synthetic.invalid','PENDING_EMAIL_SENTINEL',100]);$insert->execute([$other,'other@synthetic.invalid',null,101]);
    $db=new class($pdo) { private $pdo;public function __construct($pdo) {$this->pdo=$pdo;} public function getConnection() {return $this->pdo;} };
    $service=new NativeCryptoInvitationV2(['db'=>$db]);
    $method=new \ReflectionMethod(NativeCryptoInvitationV2::class,'inviterDisplay');$method->setAccessible(true);
    $read=fn()=>$method->invoke($service,['creator_account_id'=>$creator]);
    $checks=0;
    function ck($condition,$label) { global $checks;if(!$condition)throw new \RuntimeException('FAIL: '.$label);$checks++;echo 'PASS: '.$label.PHP_EOL; }
    $pdo->exec('PRAGMA query_only=ON');$before=(int)$pdo->query('SELECT total_changes()')->fetchColumn();$display=$read();
    ck($display['inviterAccountId']===$creator&&$display['inviterEmail']==='owner@synthetic.invalid','verified email belongs to exact creator account');
    ck(!str_contains(json_encode($display),'SENTINEL')&&!str_contains(json_encode($display),'other@'),'pending and unrelated users email are absent');
    ck((int)$pdo->query('SELECT total_changes()')->fetchColumn()===$before&&array_keys($display)===['inviterAccountId','inviterUsername','inviterName','inviterEmail'],'email display is read-only metadata without authority or keys');
    $pdo->exec('PRAGMA query_only=OFF');
    $pdo->exec("UPDATE familyhub_email_identities SET verified_at=NULL WHERE account_id='$creator'");
    ck(!isset($read()['inviterEmail']),'unverified identity never supplies sender email');
    $pdo->exec("UPDATE familyhub_email_identities SET email='changed@synthetic.invalid',verified_at=102 WHERE account_id='$creator'");
    ck($read()['inviterEmail']==='changed@synthetic.invalid','confirmed address change uses current verified email');
    $update=$pdo->prepare('UPDATE familyhub_email_identities SET email=? WHERE account_id=?');
    foreach (["owner\nApproved@synthetic.invalid",str_repeat('a',255).'@synthetic.invalid','malformed-email','owner@synthetic.invalid'.chr(127)] as $invalid) {
        $update->execute([$invalid,$creator]);ck(!isset($read()['inviterEmail']),'invalid or unbounded verified email is omitted');
    }
    $pdo->exec("DELETE FROM familyhub_email_identities WHERE account_id='$creator'");
    ck(!isset($read()['inviterEmail'])&&$read()['inviterUsername']==='owner','missing verified identity retains name and username fallback');
    $pdo->exec('UPDATE users SET is_active=0 WHERE id=1');
    ck($read()===[],'inactive creator exposes no email or display labels');
    echo json_encode(['guard'=>'crypto2-invitation-verified-email-display','status'=>'pass','checks'=>$checks,'fixture'=>'standalone-memory','proofVerification'=>'supplied inviter display seam','retainedDatabaseAccess'=>false]).PHP_EOL;
}
