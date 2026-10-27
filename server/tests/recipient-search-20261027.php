<?php
/** Real native dispatch against a fresh in-memory SQLite fixture only. */
namespace Kanboard\Core {
    class Base { protected $container; public function __construct($c) {$this->container=$c;} public function __get($k) {return $this->container[$k];} }
}
namespace {
    use Kanboard\Plugin\FamilyHub\Model\NativeService;
    use Kanboard\Plugin\FamilyHub\Model\NativeError;
    define('FAMILYHUB_ENABLE_NATIVE_API',true);
    spl_autoload_register(function($class) {$prefix='Kanboard\\Plugin\\FamilyHub\\';if(str_starts_with($class,$prefix)) require __DIR__.'/../plugins/FamilyHub/'.str_replace('\\','/',substr($class,strlen($prefix))).'.php';});
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
    function user($n,$username,$name,$active=1,$account=true) {
        global $fingerprint;
        sql('INSERT INTO users VALUES(?,?,?,?,?,0,NULL,?,0,0)',[$n,$username,$name,'PRIVATE_EMAIL_SENTINEL'.$n.'@invalid','synthetic-password',$active]);
        if($account)sql('INSERT INTO familyhub_accounts VALUES(?,?)',[$n,id($n)]);
    }
    user(1,'search_owner','Search Owner');user(2,'bob_example','Bob Example');user(3,'disabled_bob','Bob Disabled',0);user(4,'coreonly_bob','Bob Core only',1,false);user(5,'other_actor','Other Actor');user(6,'literal_under','Žan Slovenija');user(7,'ldap_bob','Bob LDAP');user(8,'loginblocked_bob','Bob login disabled');
    sql('UPDATE users SET is_ldap_user=1 WHERE id=7');sql('UPDATE users SET disable_login_form=1 WHERE id=8');
    foreach([1,5] as $n)sql('INSERT INTO familyhub_devices VALUES(?,?,?,?,?,?,?,?,NULL)',[id(100+$n),$n,id($n),'Synthetic',hash('sha256','fh1_'.str_repeat((string)$n,64)),$fingerprint,time(),time()+3600]);
    foreach([20,21] as $s){sql("INSERT INTO familyhub_scopes(id,kind,name,owner_id,sequence,created_at,access_policy_version) VALUES(?,'household','Search household',1,0,1,3)",[id($s)]);sql('INSERT INTO familyhub_members VALUES(?,?,?,?,1)',[id($s),1,id(1),'owner']);}
    sql('INSERT INTO familyhub_policy_acceptances(account_id,policy_version,accepted_at) VALUES(?,1,?)',[id(1),time()]);
    $db=new class($pdo) {private $pdo;public function __construct($p){$this->pdo=$p;}public function getConnection(){return $this->pdo;}};
    $api=new NativeService(['db'=>$db]);$owner='Bearer fh1_'.str_repeat('1',64);$other='Bearer fh1_'.str_repeat('5',64);
    function call($op,$p=[],$token=null) {global $api,$owner;return $api->dispatch($op,$p,$token??$owner,'recipient-search-synthetic');}
    function search($q,$scope=20) {return call('recipients.search',['scopeId'=>id($scope),'query'=>$q])['recipients'];}
    ck(call('capabilities')['features']['recipientSearch']===true,'capability advertises bounded authenticated discovery');
    deny(fn()=>call('recipients.search',['scopeId'=>id(20),'query'=>'Bo'],''),'auth_required','unauthenticated callers cannot search');
    $found=search('bOb');ck(count($found)===1&&$found[0]===['accountId'=>id(2),'username'=>'bob_example','displayName'=>'Bob Example'],'partial case-insensitive username or name excludes inactive core-only LDAP and login-disabled users');
    ck(search('Owner')===[],'self is excluded');
    ck(search('žAN')===[['accountId'=>id(6),'username'=>'literal_under','displayName'=>'Žan Slovenija']],'Unicode display names match case insensitively in SQLite');
    ck(count(search('literal_'))===1&&search('%%')===[]&&search('__')===[],'wildcards are literal and cannot list every user');
    deny(fn()=>search('a'),'validation_error','short queries denied');
    deny(fn()=>search(str_repeat('a',65)),'validation_error','oversized queries denied');
    deny(fn()=>search('mail@example.invalid'),'validation_error','email searches denied');
    deny(fn()=>call('recipients.search',['scopeId'=>id(20),'query'=>'Bo'],$other),'permission_revoked','unrelated authenticated user cannot use scope directory');
    sql('INSERT INTO familyhub_members VALUES(?,?,?,?,1)',[id(21),5,id(5),'viewer']);
    deny(fn()=>call('recipients.search',['scopeId'=>id(21),'query'=>'Bo'],$other),'permission_revoked','viewers cannot use invitation discovery');
    sql('UPDATE familyhub_scopes SET archived=1 WHERE id=?',[id(21)]);
    deny(fn()=>search('Bo',21),'permission_revoked','archived scope cannot search');
    for($n=30;$n<45;$n++)user($n,'many_bob_'.$n,'Bounded group');
    ck(count(search('many_bob'))===10,'result count is capped at ten');
    $request=['scopeId'=>id(20),'recipient'=>'bob_example','recipientAccountId'=>id(2),'role'=>'member','language'=>'en','accessScope'=>'space','requestId'=>id(300)];
    $before=(int)sql('SELECT count(*) FROM familyhub_members')->fetchColumn();
    $inv=call('invitations3.create',$request)['invitation'];
    ck($inv['recipientUsername']==='bob_example'&&sql('SELECT recipient_account_id FROM familyhub_invitations WHERE id=?',[$inv['id']])->fetchColumn()===id(2)&&(int)sql('SELECT count(*) FROM familyhub_members')->fetchColumn()===$before,'selected account remains bound and invitation creation grants no membership');
    sql('UPDATE users SET username=? WHERE id=2',['renamed_bob']);user(60,'bob_example','Recycled name');
    deny(fn()=>call('invitations3.create',array_replace($request,['requestId'=>id(301)])),'recipient_unavailable','recycled username cannot redirect selected account');
    ck((int)sql('SELECT count(*) FROM familyhub_invitations')->fetchColumn()===1,'rejected recycled recipient creates no invitation');
    // Exact username compatibility uses its existing server-side resolution.
    $legacy=$request;unset($legacy['recipientAccountId']);$legacy['requestId']=id(302);
    ck(call('invitations3.create',$legacy)['invitation']['recipientUsername']==='bob_example','exact username without selection remains supported');
    sql('UPDATE familyhub_rate_limits SET attempts=60 WHERE id=?',[hash('sha256','recipient-search-account:'.id(1))]);
    deny(fn()=>search('Bo'),'rate_limited','account search limit is enforced');
    echo json_encode(['test'=>'recipient-search-20261027','status'=>'pass','checks'=>$checks,'fixture'=>'fresh-memory-sqlite-real-dispatch','http'=>false,'cryptoSignatures'=>false]).PHP_EOL;
}
