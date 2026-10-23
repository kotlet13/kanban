<?php
/** NEW isolated SQL/proof-model seams. No old test entrypoint, network, auth session, SMTP or retained database. */
namespace Kanboard\Core {
    class Base {
        protected $container;
        public function __construct($container){$this->container=$container;}
        public function __get($name){return $this->container[$name];}
    }
}
namespace {
    spl_autoload_register(function($class){$prefix='Kanboard\\Plugin\\FamilyHub\\';if(str_starts_with($class,$prefix)){ $path=__DIR__.'/../plugins/FamilyHub/'.str_replace('\\','/',substr($class,strlen($prefix))).'.php';if(is_file($path))require_once $path;}});
    use Kanboard\Plugin\FamilyHub\Model\NativeCryptoCodec as Codec;
    use Kanboard\Plugin\FamilyHub\Model\NativeCryptoV2Codec as V2;
    use Kanboard\Plugin\FamilyHub\Model\NativeCryptoDirectoryV2 as Directory;
    use Kanboard\Plugin\FamilyHub\Model\NativeCryptoInvitationPreauthorizationV5 as Prepared;
    use Kanboard\Plugin\FamilyHub\Model\NativeCryptoScopeV2 as Scopes;
    use Kanboard\Plugin\FamilyHub\Model\NativeError;
    $pdo=new \PDO('sqlite::memory:');$pdo->setAttribute(\PDO::ATTR_ERRMODE,\PDO::ERRMODE_EXCEPTION);
    $pdo->exec('CREATE TABLE users(id INTEGER PRIMARY KEY,username TEXT,name TEXT,email TEXT,is_active INTEGER);
      CREATE TABLE familyhub_accounts(user_id INTEGER PRIMARY KEY,account_id TEXT UNIQUE);
      CREATE TABLE familyhub_instance(id INTEGER PRIMARY KEY,server_id TEXT);
      CREATE TABLE familyhub_scopes(id TEXT PRIMARY KEY,kind TEXT,name TEXT,owner_id INTEGER,access_policy_version INTEGER,access_revision INTEGER,archived INTEGER DEFAULT 0,deleted_at INTEGER,parent_scope_id TEXT,organization_id TEXT,sequence INTEGER DEFAULT 0);
      CREATE TABLE familyhub_members(scope_id TEXT,user_id INTEGER,account_id TEXT,role TEXT,active INTEGER,PRIMARY KEY(scope_id,user_id));
      CREATE TABLE familyhub_email_identities(account_id TEXT PRIMARY KEY,email TEXT,verified_at INTEGER,pending_email TEXT);
      CREATE TABLE familyhub_finance_policy(scope_id TEXT PRIMARY KEY,enabled INTEGER,revision INTEGER,sequence INTEGER,required_contract_version INTEGER);
      CREATE TABLE familyhub_finance_grants(scope_id TEXT,account_id TEXT,access_level TEXT,PRIMARY KEY(scope_id,account_id));
      CREATE TABLE familyhub_moderation_blocks(scope_id TEXT,account_id TEXT);
      CREATE TABLE familyhub_organization_leaders(scope_id TEXT,account_id TEXT);
      CREATE TABLE familyhub_payment_events(scope_id TEXT,event_id TEXT);
      CREATE TABLE familyhub_payment_projections(scope_id TEXT,event_id TEXT);
      CREATE TABLE familyhub_payment_cash(scope_id TEXT,movement_id TEXT);');
    \Kanboard\Plugin\FamilyHub\Schema\CryptoSchema::create($pdo,false);
    \Kanboard\Plugin\FamilyHub\Schema\PreauthorizedInvitationSchema::create($pdo,false);
    function uid(){ $h=bin2hex(random_bytes(16));return substr($h,0,8).'-'.substr($h,8,4).'-4'.substr($h,13,3).'-a'.substr($h,17,3).'-'.substr($h,20);}
    function sql($q,$args=[]){global $pdo;$s=$pdo->prepare($q);$s->execute($args);$rows=$s->fetchAll(\PDO::FETCH_ASSOC);$s->closeCursor();return $rows;}
    $server=uid();sql('INSERT INTO familyhub_instance VALUES(1,?)',[$server]);$checks=0;
    function ck($ok,$label){global $checks;if(!$ok)throw new \RuntimeException('FAIL: '.$label);$checks++;echo 'PASS: '.$label.PHP_EOL;}
    function denied($fn,$code,$label){try{$fn();throw new \RuntimeException('FAIL: missing denial '.$label);}catch(NativeError $e){ck($e->errorCode===$code,$label.' ('.$e->errorCode.')');}}
    function signCommand($operation,$payload,$actor){global $server;$raw=['version'=>2,'operation'=>$operation,'requestId'=>uid(),'serverId'=>$server,'accountId'=>$actor['user']['account_id'],'deviceId'=>$actor['device']['id'],'signer'=>'device','payload'=>$payload];$bytes=Codec::canonical((object)$raw);return ['commandBase64'=>base64_encode($bytes),'signatureBase64'=>base64_encode(sodium_crypto_sign_detached("JivieE2EE/v2\n".$bytes,$actor['secret']))];}
    function person($id,$username){global $server;
        $account=uid();$device=uid();$epoch=uid();$root=sodium_crypto_sign_keypair();$box=sodium_crypto_box_keypair();$deviceSign=sodium_crypto_sign_keypair();$deviceBox=sodium_crypto_box_keypair();
        $actor=['user'=>['id'=>$id,'account_id'=>$account],'device'=>['id'=>$device],'secret'=>sodium_crypto_sign_secretkey($deviceSign)];
        $snapshot=['version'=>2,'serverId'=>$server,'accountId'=>$account,'rootSigningKeyBase64'=>base64_encode(sodium_crypto_sign_publickey($root)),'rootEncryptionKeyBase64'=>base64_encode(sodium_crypto_box_publickey($box)),'recoveryRootCiphertextHash'=>hash('sha256','synthetic'),'recoveryRootEpochId'=>$epoch,'identityEpochId'=>$epoch,'devices'=>[['deviceId'=>$device,'signingKeyBase64'=>base64_encode(sodium_crypto_sign_publickey($deviceSign)),'encryptionKeyBase64'=>base64_encode(sodium_crypto_box_publickey($deviceBox)),'keyringWrite'=>true,'manageDevices'=>true,'addedGeneration'=>1,'revokedGeneration'=>null,'identityEpochId'=>$epoch]],'keyringEntries'=>[]];
        $snapshotHash=Directory::snapshotHash($snapshot);$deviceHash=Directory::deviceHash($snapshot);
        $proof=signCommand('crypto2.account.initialize',['resultingSnapshotHash'=>$snapshotHash,'expectedGeneration'=>0,'previousHeadHash'=>Directory::ZERO],$actor);[$command]=Codec::decode($proof);$head=V2::head($command,$proof,1);
        sql('INSERT INTO users VALUES(?,?,?,?,1)',[$id,$username,$username,$username.'@unverified.invalid']);sql('INSERT INTO familyhub_accounts VALUES(?,?)',[$id,$account]);sql('INSERT INTO familyhub_email_identities VALUES(?,?,?,NULL)',[$account,$username.'@synthetic.invalid',time()]);
        sql('INSERT INTO familyhub_crypto_directory VALUES(?,1,?,?,?,?,?,?,?,?)',[$account,$head,Directory::ZERO,hash('sha256','command'),json_encode($proof),'',$snapshotHash,$deviceHash,$epoch]);
        sql('INSERT INTO familyhub_crypto_directory_state VALUES(?,1,?,?,?,?,?)',[$account,$head,json_encode($snapshot),$snapshotHash,$deviceHash,$epoch]);
        $actor['snapshot']=$snapshot;$actor['head']=$head;$actor['deviceHash']=$deviceHash;$actor['email']=$username.'@synthetic.invalid';return $actor;
    }
    $owner=person(1,'synthetic_owner');$recipient=person(2,'synthetic_recipient');
    $db=new class($pdo){private $pdo;public function __construct($pdo){$this->pdo=$pdo;}public function getConnection(){return $this->pdo;}};
    $container=['db'=>$db];$prepared=new class($container) extends Prepared {public function access($sid,$actor){return $this->scope($sid,$actor['user']['id']);}};$scopes=new Scopes($container);
    function scopeFixture($version,$owner,$kind='household',$parent=null){global $scopes;
        $sid=uid();sql('INSERT INTO familyhub_scopes(id,kind,name,owner_id,access_policy_version,access_revision,parent_scope_id,organization_id) VALUES(?,?,?,?,?,0,?,?)',[$sid,$kind,'Synthetic encrypted',$owner['user']['id'],$version,$parent,$parent]);sql("INSERT INTO familyhub_members VALUES(?,?,?,'owner',1)",[$sid,$owner['user']['id'],$owner['user']['account_id']]);sql('INSERT INTO familyhub_finance_policy VALUES(?,1,0,0,3)',[$sid]);
        $proof=signCommand('synthetic.origin',['scopeId'=>$sid],$owner);$baseline=['scopeId'=>$sid,'originProofHash'=>V2::hash((object)$proof),'ownArchived'=>false,'inheritedArchived'=>false];$initial=hash('sha256',"JivieLifecycleBaseline/v2\n".Codec::canonical((object)$baseline));sql('INSERT INTO familyhub_crypto_lifecycle_baselines_v2 VALUES(?,?,?,?,?)',[$sid,$initial,json_encode($baseline),json_encode($proof),$owner['head']]);
        $member=['accountId'=>$owner['user']['account_id'],'rootSigningKeyBase64'=>$owner['snapshot']['rootSigningKeyBase64'],'rootEncryptionKeyBase64'=>$owner['snapshot']['rootEncryptionKeyBase64'],'recoveryRootEpochId'=>$owner['snapshot']['recoveryRootEpochId'],'identityEpochId'=>$owner['snapshot']['identityEpochId'],'directoryHeadHash'=>$owner['head'],'deviceSnapshotHash'=>$owner['deviceHash'],'role'=>'owner','financeRole'=>'write','manageKeys'=>true];
        $body=['scopeId'=>$sid,'epoch'=>1,'previousHeadHash'=>Directory::ZERO,'initialLifecycleHash'=>$initial,'members'=>[$member],'membershipIntents'=>[],'keyIds'=>['content'=>uid(),'finance'=>null],'keyCommitments'=>['content'=>hash('sha256',random_bytes(32)),'finance'=>null]];
        $head=installHead($sid,$body,$owner);return [$sid,$body,$head];
    }
    function installHead($sid,$body,$owner){$hash=hash('sha256',"JivieScopeHead/v2\n".Codec::canonical((object)$body));$proof=signCommand('crypto2.scope.headPut',$body,$owner);sql("INSERT INTO familyhub_crypto_scope_heads VALUES(?,?,?,?,?,?,?,?,'active')",[$sid,$hash,$body['epoch'],$body['previousHeadHash'],0,Codec::canonical((object)$body),json_encode($proof),json_encode($proof)]);if(sql('SELECT scope_id FROM familyhub_crypto_scope_state WHERE scope_id=?',[$sid]))sql('UPDATE familyhub_crypto_scope_state SET head_hash=?,epoch=? WHERE scope_id=?',[$hash,$body['epoch'],$sid]);else{sql('INSERT INTO familyhub_crypto_scope_state VALUES(?,?,1,0,0,0)',[$sid,$hash]);foreach(['content','finance']as $domain)sql('INSERT INTO familyhub_crypto_domain_cursors VALUES(?,?,0)',[$sid,$domain]);}return $hash;}
}
