<?php
/** Read-only preview SQL seam. Admission/proof checks are supplied fixtures. */
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
    foreach (['NativeError','NativeDatabase','NativeCryptoCodec','NativeCryptoV2Codec','NativeCryptoInvitationV2','NativeCryptoInvitationPreauthorizationV5'] as $file) require $model.$file.'.php';
    $pdo=new \PDO('sqlite::memory:');$pdo->setAttribute(\PDO::ATTR_ERRMODE,\PDO::ERRMODE_EXCEPTION);
    $pdo->exec('CREATE TABLE users(id INTEGER PRIMARY KEY,is_active INTEGER,username TEXT,name TEXT);
      CREATE TABLE familyhub_accounts(account_id TEXT PRIMARY KEY,user_id INTEGER);
      CREATE TABLE familyhub_email_identities(account_id TEXT PRIMARY KEY,email TEXT,verified_at INTEGER);
      CREATE TABLE familyhub_scopes(id TEXT PRIMARY KEY,kind TEXT,name TEXT,access_policy_version INTEGER);');
    $creator='00000000-0000-4000-a000-000000000001';$other='00000000-0000-4000-a000-000000000002';$sid='00000000-0000-4000-a000-000000000003';
    $pdo->exec("INSERT INTO users VALUES(1,1,'synthetic_owner','Synthetic owner'),(2,1,'other_user','Other user')");
    $insert=$pdo->prepare('INSERT INTO familyhub_accounts VALUES(?,?)');$insert->execute([$creator,1]);$insert->execute([$other,2]);
    $insert=$pdo->prepare("INSERT INTO familyhub_scopes VALUES(?,'project','PRIVATE_TITLE_SENTINEL',3)");$insert->execute([$sid]);
    $db=new class($pdo) { private $pdo;public function __construct($pdo) {$this->pdo=$pdo;} public function getConnection() {return $this->pdo;} };
    $service=new class(['db'=>$db]) extends NativeCryptoInvitationV2 {
        protected function bridgeEvidence($row) { return null; }
    };
    $method=new \ReflectionMethod(NativeCryptoInvitationV2::class,'preview');$method->setAccessible(true);
    $row=['id'=>$sid,'scope_id'=>$sid,'role'=>'member','expires_at'=>2000000000,'state'=>'pending','recipient_kind'=>'username','recipient_value'=>'recipient','recipient_account_id'=>$other,'created_at'=>100,'token_hash'=>str_repeat('a',64),'creator_account_id'=>$creator,'authorization'=>'{}'];
    $checks=0;
    function ck($condition,$label) { global $checks;if(!$condition)throw new \RuntimeException('FAIL: '.$label);$checks++;echo 'PASS: '.$label.PHP_EOL; }
    $pdo->exec('PRAGMA query_only=ON');$before=(int)$pdo->query('SELECT total_changes()')->fetchColumn();
    $preview=$method->invoke($service,$row,[],true);
    ck($preview['inviterAccountId']===$creator&&$preview['inviterUsername']==='synthetic_owner'&&$preview['inviterName']==='Synthetic owner','preview labels follow creator account rather than recipient');
    ck($preview['scope']['name']==='Encrypted space'&&!str_contains(json_encode($preview),'PRIVATE_TITLE_SENTINEL'),'preaccept preview retains protected title fallback');
    ck($preview['invitation']['role']==='member'&&$preview['candidateHeads']===[]&&!isset($preview['keys']),'display read neither changes invitation role nor exposes access keys');
    ck((int)$pdo->query('SELECT total_changes()')->fetchColumn()===$before,'preview metadata performs no writes');
    $pdo->exec('PRAGMA query_only=OFF');$pdo->exec("UPDATE users SET name=char(10)||'Spoofed' WHERE id=1");
    $preview=$method->invoke($service,$row,[],true);
    ck($preview['inviterName']==='synthetic_owner','unsafe display name falls back to bounded username');
    $pdo->exec('UPDATE users SET is_active=0 WHERE id=1');
    $preview=$method->invoke($service,$row,[],true);
    ck(!isset($preview['inviterAccountId'])&&!isset($preview['inviterName']),'missing active creator label uses explicit client fallback');
    echo json_encode(['guard'=>'crypto2-invitation-display','status'=>'pass','checks'=>$checks,'fixture'=>'standalone-memory','proofVerification'=>'supplied preview seam','retainedDatabaseAccess'=>false]).PHP_EOL;
}
