<?php
/** MariaDB/MySQL real two-PDO concurrency boundary. Disposable fixtures only. */
umask(0077);
require '/var/www/app/app/common.php';
if(session_status()===PHP_SESSION_ACTIVE){session_abort();}
if(!defined('FAMILYHUB_DEVELOPMENT_MODE') || FAMILYHUB_DEVELOPMENT_MODE!==true || DB_DRIVER!=='mysql'){throw new RuntimeException('Synthetic MariaDB/MySQL only');}
use Kanboard\Plugin\FamilyHub\Model\NativeService;
use Kanboard\Plugin\FamilyHub\Model\NativeError;
use Kanboard\Plugin\FamilyHub\Model\NativeCryptoV2Service;
use Kanboard\Plugin\FamilyHub\Schema\CryptoSchema;
$pdo=$container['db']->getConnection(); CryptoSchema::create($pdo,true);
$other=new PDO('mysql:host='.DB_HOSTNAME.';dbname='.DB_NAME,DB_USERNAME,DB_PASSWORD,[PDO::ATTR_ERRMODE=>PDO::ERRMODE_EXCEPTION]);
$api=new NativeService($container); $prefix='snapshot_concurrency_'.bin2hex(random_bytes(6)); $checks=0;
function checkSnapshot($value,$label){global $checks;if(!$value)throw new RuntimeException('FAIL: '.$label);$checks++;echo 'PASS: '.$label.PHP_EOL;}
function snapshotCall($op,$params=[],$actor=null){global $api,$prefix;return $api->dispatch($op,$params,$actor?'Bearer '.$actor['token']:'',$prefix);}
function snapshotUuid(){ $h=bin2hex(random_bytes(16));return substr($h,0,8).'-'.substr($h,8,4).'-4'.substr($h,13,3).'-a'.substr($h,17,3).'-'.substr($h,20); }
$password=bin2hex(random_bytes(20));$container['userModel']->create(['username'=>$prefix,'password'=>$password,'role'=>'app-user']);
$actor=snapshotCall('auth.login',['username'=>$prefix,'password'=>$password,'deviceName'=>'Snapshot concurrency']);
$statement=$pdo->prepare('INSERT INTO familyhub_email_identities(account_id,email,verified_at,revision) VALUES(?,?,?,1)');$statement->execute([$actor['user']['accountId'],$prefix.'@snapshot.invalid',time()]);
snapshotCall('moderation.acceptPolicy',['policyVersion'=>1],$actor);
$scope=snapshotCall('scopes.create',['id'=>snapshotUuid(),'kind'=>'organization','name'=>'Synthetic concurrency','requestId'=>snapshotUuid(),'accessPolicyVersion'=>3],$actor)['scope'];

class ConcurrentSnapshotService extends NativeCryptoV2Service {
    public $afterFirstRead;
    protected function query($sql,array $params=[]){
        $statement=parent::query($sql,$params);
        if($this->snapshotRead() && $this->afterFirstRead!==null && str_starts_with($sql,'SELECT * FROM familyhub_devices WHERE token_hash')){
            $callback=$this->afterFirstRead;$this->afterFirstRead=null;$callback();
        }
        return $statement;
    }
    public function enforcedReadOnly(){
        return $this->transaction(function(){
            try{$this->pdo->exec('UPDATE familyhub_native_lock SET counter=counter WHERE id=1');return false;}
            catch(PDOException $error){return ($error->errorInfo[0]??null)==='25006';}
        },false,true);
    }
    public function ordinaryWritesRemainEnabled(){return $this->transaction(function(){return $this->change('UPDATE familyhub_native_lock SET counter=counter WHERE id=1')>=0;});}
}
$service=new ConcurrentSnapshotService($container,'Bearer '.$actor['token'],$prefix);
$service->afterFirstRead=function()use($other,$scope,$actor){$s=$other->prepare('UPDATE familyhub_members SET active=0 WHERE scope_id=? AND account_id=?');$s->execute([$scope['id'],$actor['user']['accountId']]);};
$before=$service->execute('crypto2.authority.snapshot',['scopeId'=>$scope['id']]);
$included=false;foreach($before['entries'] as $entry){if($entry['operation']==='crypto2.scope.headGet' && (array)$entry['params']===['scopeId'=>$scope['id']]){$included=true;}}
checkSnapshot($included,'in-flight snapshot retains one coherent pre-revocation ACL view after concurrent commit');
try{snapshotCall('crypto2.authority.snapshot',['scopeId'=>$scope['id']],$actor);$denied=false;}catch(NativeError $error){$denied=$error->errorCode==='permission_revoked';}
checkSnapshot($denied,'next snapshot after committed concurrent revocation denies scope');
checkSnapshot($service->enforcedReadOnly(),'database rejects writes even outside the PHP snapshot write guard');
checkSnapshot($service->ordinaryWritesRemainEnabled(),'snapshot isolation and PHP write guard clean up for ordinary transactions');
// A bearer revoked after the first SELECT is also a coherent in-flight read;
// the next request must fail before any account or scope authority is returned.
$service->afterFirstRead=function()use($other,$actor){$s=$other->prepare('UPDATE familyhub_devices SET revoked_at=? WHERE id=?');$s->execute([time(),$actor['device']['id']]);};
$account=$service->execute('crypto2.authority.snapshot',[]);
checkSnapshot($account['accountId']===$actor['user']['accountId'],'in-flight device snapshot retains its original account view');
try{snapshotCall('crypto2.authority.snapshot',[],$actor);$denied=false;}catch(NativeError $error){$denied=$error->errorCode==='device_revoked';}
checkSnapshot($denied,'fresh snapshot rejects concurrently revoked bearer before returning authority');
echo 'Crypto2 authority snapshot concurrent SQL: '.$checks.' controls PASS'.PHP_EOL;
