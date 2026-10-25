<?php
/** New bounded account metadata controls. Disposable SQLite only; no old PASS reruns. */
namespace Kanboard\Core {
    class Base { protected $container; public function __construct($c) {$this->container=$c;} public function __get($k) {return $this->container[$k];} }
}
namespace {
    use Kanboard\Plugin\FamilyHub\Model\NativeAccountChanges;
    use Kanboard\Plugin\FamilyHub\Model\NativeError;
    define('FAMILYHUB_ENABLE_CRYPTO_PREVIEW', true);
    define('FAMILYHUB_ENABLE_NATIVE_API', true);
    define('FAMILYHUB_ACCOUNT_MAIL_KEY_BASE64', base64_encode(str_repeat('S', 32)));
    spl_autoload_register(function($class) {
        $prefix='Kanboard\\Plugin\\FamilyHub\\';
        if(str_starts_with($class,$prefix)) require __DIR__.'/../plugins/FamilyHub/'.str_replace('\\','/',substr($class,strlen($prefix))).'.php';
    });
    require __DIR__.'/../plugins/FamilyHub/Schema/Sqlite.php';
    $pdo=new \PDO('sqlite::memory:');$pdo->setAttribute(\PDO::ATTR_ERRMODE,\PDO::ERRMODE_EXCEPTION);
    $pdo->exec('CREATE TABLE users(id INTEGER PRIMARY KEY,username TEXT,name TEXT,email TEXT,password TEXT,twofactor_activated INTEGER,twofactor_secret TEXT,is_active INTEGER,is_ldap_user INTEGER,disable_login_form INTEGER);');
    for($v=2;$v<=23;$v++){ $f='Kanboard\\Plugin\\FamilyHub\\Schema\\version_'.$v;$f($pdo); }
    function sql($q,$p=[]) {global $pdo;$s=$pdo->prepare($q);$s->execute($p);return $s;}
    $checks=0;
    function ck($v,$label) {global $checks;if(!$v)throw new \RuntimeException('FAIL: '.$label);$checks++;echo 'PASS: '.$label.PHP_EOL;}
    function deny($fn,$code,$label) {try{$fn();$ok=false;}catch(NativeError $e){$ok=$e->errorCode===$code;if(!$ok)throw $e;}ck($ok,$label);}
    function id($n){return sprintf('00000000-0000-4000-a000-%012d',$n);}
    $fingerprint=hash('sha256',json_encode(['synthetic-password',0,null]));
    foreach([1,2] as $n){
        sql('INSERT INTO users VALUES(?,?,?,?,?,0,NULL,1,0,0)',[$n,'synthetic'.$n,'Synthetic '.$n,'user'.$n.'@invalid','synthetic-password']);
        sql('INSERT INTO familyhub_accounts VALUES(?,?)',[$n,id($n)]);
        foreach([$n,$n+10] as $d){sql('INSERT INTO familyhub_devices VALUES(?,?,?,?,?,?,?,?,NULL)',[id(100+$d),$n,id($n),'Synthetic',hash('sha256','fh1_'.str_repeat(dechex($d),64/strlen(dechex($d)))),$fingerprint,time(),time()+3600]);}
    }
    function bearer($n){return 'Bearer fh1_'.str_repeat(dechex($n),64/strlen(dechex($n)));}
    foreach([3,4,5] as $s){sql("INSERT INTO familyhub_scopes(id,kind,name,owner_id,sequence,created_at,access_policy_version) VALUES(?,'project','PLAINTEXT_SCOPE_SENTINEL',?,0,1,3)",[id($s),$s===5?2:1]);sql('INSERT INTO familyhub_members VALUES(?,?,?,?,1)',[id($s),$s===5?2:1,id($s===5?2:1),'owner']);sql('INSERT INTO familyhub_finance_policy(scope_id,enabled,revision,sequence) VALUES(?,1,1,0)',[id($s)]);}
    sql("INSERT INTO familyhub_crypto_scopes(scope_id,epoch,sequence,access_revision,state) VALUES(?,1,0,0,'active')",[id(3)]);
    foreach(['content','finance'] as $d)sql('INSERT INTO familyhub_crypto_domain_cursors VALUES(?,?,0)',[id(3),$d]);
    $db=new class($pdo) {private $pdo;public function __construct($p){$this->pdo=$p;}public function getConnection(){return $this->pdo;}};
    class ObservedChanges extends NativeAccountChanges {
        public $queries=[];
        public $clock;
        protected function now(){return $this->clock ?? parent::now();}
        protected function query($sql,array $p=[]){$this->queries[]=$sql;return parent::query($sql,$p);}
        public function readOnly($cursor){return $this->transaction(fn()=> $this->read($cursor,$this->actor(false)),false,true);}
    }
    $service=new ObservedChanges(['db'=>$db],bearer(1),'synthetic-account-changes');
    $probe=fn($c)=>$service->execute('account.changes',['cursor'=>$c]);
}
