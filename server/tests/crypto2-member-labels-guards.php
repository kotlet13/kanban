<?php
/** Standalone SQL/read seam. Synthetic active signed-head fixture; not a proof/auth test. */
namespace Kanboard\Core {
    class Base {
        protected $container;
        public function __construct($container) { $this->container=$container; }
        public function __get($name) { return $this->container[$name]; }
    }
}
namespace Kanboard\Plugin\FamilyHub\Model {
    // The endpoint's admission and label SQL run unchanged. Signed head crypto
    // validation is supplied as an already validated fixture at this seam.
    class NativeCryptoScopeV2 {
        public static $head;
        public function __construct($container, $bearer='', $ip='unknown') {}
        public function current($sid) { return self::$head; }
        public function body($head) { return $head['body']; }
        public function member($body, $account) {
            foreach ($body['members'] as $member) { if ($member['accountId']===$account) return $member; }
            return null;
        }
    }
}
namespace {
    use Kanboard\Plugin\FamilyHub\Model\NativeError;
    use Kanboard\Plugin\FamilyHub\Model\NativeCryptoMemberLabelsV2;
    use Kanboard\Plugin\FamilyHub\Model\NativeCryptoScopeV2;
    $model=__DIR__.'/../plugins/FamilyHub/Model/';
    foreach (['NativeError','NativeDatabase','NativeOrganizationAccess','NativeCryptoMemberLabelsV2'] as $file) require $model.$file.'.php';
    $pdo=new \PDO('sqlite::memory:');$pdo->setAttribute(\PDO::ATTR_ERRMODE,\PDO::ERRMODE_EXCEPTION);
    $pdo->exec('CREATE TABLE familyhub_instance(id INTEGER PRIMARY KEY,server_id TEXT);
      CREATE TABLE users(id INTEGER PRIMARY KEY,is_active INTEGER,username TEXT,name TEXT);
      CREATE TABLE familyhub_accounts(account_id TEXT PRIMARY KEY,user_id INTEGER);
      CREATE TABLE familyhub_scopes(id TEXT PRIMARY KEY,kind TEXT,name TEXT,owner_id INTEGER,parent_scope_id TEXT,organization_id TEXT,access_policy_version INTEGER,access_revision INTEGER,deleted_at INTEGER,archived INTEGER);
      CREATE TABLE familyhub_members(scope_id TEXT,user_id INTEGER,account_id TEXT,role TEXT,active INTEGER);
      CREATE TABLE familyhub_organization_leaders(scope_id TEXT,account_id TEXT);
      CREATE TABLE familyhub_moderation_blocks(scope_id TEXT,account_id TEXT);');
    function gid($n) { return sprintf('00000000-0000-4000-a000-%012d',$n); }
    function sql($query,$params=[]) { global $pdo;$s=$pdo->prepare($query);$s->execute($params); }
    $own=gid(1);$other=gid(2);$third=gid(3);$outsider=gid(4);$sid=gid(5);$server=gid(6);$device=gid(7);$head=str_repeat('a',64);
    sql('INSERT INTO familyhub_instance VALUES(1,?)',[$server]);
    foreach ([1,2,3,4] as $n) { sql('INSERT INTO users VALUES(?,1,?,?)',[$n,'user'.$n,'Preizkus '.$n]);sql('INSERT INTO familyhub_accounts VALUES(?,?)',[gid($n),$n]); }
    sql("INSERT INTO familyhub_scopes VALUES(?,'project','PRIVATE_CONTENT_SENTINEL',1,NULL,NULL,3,1,NULL,0)",[$sid]);
    foreach ([1,2,3] as $n) sql("INSERT INTO familyhub_members VALUES(?,?,?,'member',1)",[$sid,$n,gid($n)]);
    NativeCryptoScopeV2::$head=['head_hash'=>$head,'body'=>['accessRevision'=>1,'members'=>[['accountId'=>$own],['accountId'=>$other],['accountId'=>$third]]]];
    $db=new class($pdo) { private $pdo;public function __construct($pdo) {$this->pdo=$pdo;} public function getConnection() {return $this->pdo;} };
    $service=new NativeCryptoMemberLabelsV2(['db'=>$db]);$actor=['user'=>['id'=>1,'account_id'=>$own],'device'=>['id'=>$device]];
    $params=['scopeId'=>$sid,'headHash'=>$head,'accountIds'=>[$other,$third]];$checks=0;
    function ck($value,$label) { global $checks;if(!$value)throw new \RuntimeException('FAIL: '.$label);$checks++;echo 'PASS: '.$label.PHP_EOL; }
    function deny($params,$code,$label,$actorOverride=null) { global $service,$actor;try {$service->read($params,$actorOverride??$actor);$caught=false;}catch(NativeError $e) {$caught=$e->errorCode===$code;}ck($caught,$label); }
    $response=$service->read($params,$actor);
    ck($response['scopeId']===$sid&&$response['headHash']===$head&&$response['accountId']===$own&&$response['serverId']===$server&&$response['deviceId']===$device,'full caller scope current-head binding');
    ck($response['accountIds']===[$other,$third]&&count($response['labels'])===2&&$response['labels'][0]['displayName']==='Preizkus 2','one ordered batch returns account-bound names');
    ck(array_keys($response['labels'][0])===['accountId','userId','username','displayName']&&!str_contains(json_encode($response),'PRIVATE_CONTENT_SENTINEL'),'no roles email or plaintext content in labels');
    deny($params+['email'=>true],'validation_error','unknown fields rejected');
    deny(array_replace($params,['accountIds'=>[$third,$other]]),'validation_error','unsorted account list rejected');
    deny(array_replace($params,['accountIds'=>[$other,$other]]),'validation_error','duplicate account rejected');
    deny(array_replace($params,['accountIds'=>array_map('gid',range(10,110))]),'validation_error','batch larger than100 rejected');
    deny(array_replace($params,['accountIds'=>[$outsider]]),'permission_revoked','foreign account enumeration rejected');
    deny(array_replace($params,['headHash'=>str_repeat('b',64)]),'crypto_scope_head_changed','head substitution rejected');
    deny($params,'permission_revoked','SQL outsider rejected',['user'=>['id'=>4,'account_id'=>$outsider],'device'=>['id'=>$device]]);
    sql('UPDATE familyhub_members SET active=0 WHERE scope_id=? AND account_id=?',[$sid,$own]);
    deny($params,'permission_revoked','revoked SQL member rejected');
    sql('UPDATE familyhub_members SET active=1 WHERE scope_id=? AND account_id=?',[$sid,$own]);
    NativeCryptoScopeV2::$head['body']['members']=[['accountId'=>$other],['accountId'=>$third]];
    deny($params,'permission_revoked','SQL member absent from signed head rejected');
    NativeCryptoScopeV2::$head['body']['members'][]=['accountId'=>$own];
    sql('UPDATE familyhub_scopes SET access_revision=2 WHERE id=?',[$sid]);
    deny($params,'crypto_scope_head_changed','ACL revision differs from signed head rejected');
    sql('UPDATE familyhub_scopes SET access_revision=1 WHERE id=?',[$sid]);
    sql('UPDATE users SET is_active=0 WHERE id=3');
    $pdo->exec('PRAGMA query_only=ON');$before=(int)$pdo->query('SELECT total_changes()')->fetchColumn();
    $missing=$service->read($params,$actor);
    ck(count($missing['labels'])===1&&$missing['labels'][0]['accountId']===$other,'inactive display record omitted without changing roster authority');
    ck((int)$pdo->query('SELECT total_changes()')->fetchColumn()===$before,'label endpoint performs no SQL writes');
    echo json_encode(['guard'=>'crypto2-member-labels','status'=>'pass','checks'=>$checks,'fixture'=>'standalone-memory','proofVerification'=>'supplied head seam','retainedDatabaseAccess'=>false]).PHP_EOL;
}
