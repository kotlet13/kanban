<?php
/** Isolated synthetic worker: capture transport only, no SMTP connection. */
umask(0077);define('FAMILYHUB_ACCOUNT_MAIL_KEY_BASE64',base64_encode(random_bytes(32)));
define('FAMILYHUB_SMTP_HOST','127.0.0.1');define('FAMILYHUB_SMTP_PORT',39999);define('FAMILYHUB_SMTP_ENCRYPTION','none');define('FAMILYHUB_SMTP_ALLOW_LOCAL_PLAINTEXT',true);define('FAMILYHUB_SMTP_FROM','sender@capture.invalid');define('FAMILYHUB_PUBLIC_URL','http://127.0.0.1:18785');
require '/var/www/app/app/common.php';if(session_status()===PHP_SESSION_ACTIVE)session_abort();
if(!defined('FAMILYHUB_DEVELOPMENT_MODE')||FAMILYHUB_DEVELOPMENT_MODE!==true)throw new RuntimeException('Synthetic only');
use Kanboard\Plugin\FamilyHub\Model\NativeInvitationMailQueue;
use Kanboard\Plugin\FamilyHub\Model\NativeAccountMailCrypto;
use Kanboard\Plugin\FamilyHub\Model\NativeService;
use Kanboard\Plugin\FamilyHub\Schema\CryptoSchema;
$pdo=$container['db']->getConnection();CryptoSchema::create($pdo,$pdo->getAttribute(PDO::ATTR_DRIVER_NAME)==='mysql');
function qf($sql,$params=[]){global$pdo;$q=$pdo->prepare($sql);$q->execute($params);$r=$q->fetchAll(PDO::FETCH_ASSOC);$q->closeCursor();return$r;}
function idf(){$h=bin2hex(random_bytes(16));return substr($h,0,8).'-'.substr($h,8,4).'-4'.substr($h,13,3).'-a'.substr($h,17,3).'-'.substr($h,20);}
$checks=0;function cf($v,$label){global$checks;if(!$v)throw new RuntimeException($label);$checks++;echo 'PASS '.$label.PHP_EOL;}
$name='mail_fence_'.bin2hex(random_bytes(8));$pw=bin2hex(random_bytes(20));$container['userModel']->create(['username'=>$name,'password'=>$pw,'role'=>'app-user']);$api=new NativeService($container);$u=$api->dispatch('auth.login',['username'=>$name,'password'=>$pw,'deviceName'=>'Synthetic worker'],'',$name);
$scopes=[];foreach(['blocked','normal']as$kind){$id=idf();qf('INSERT INTO familyhub_scopes(id,kind,name,owner_id,sequence,created_at,access_policy_version) VALUES(?,?,?,?,0,?,1)',[$id,'household','Synthetic worker '.$kind,$u['user']['id'],time()]);qf('INSERT INTO familyhub_members VALUES(?,?,?,?,1)',[$id,$u['user']['id'],$u['user']['accountId'],'owner']);$scopes[$kind]=$id;}
qf("INSERT INTO familyhub_crypto_scopes VALUES(?,1,0,1,'fenced',NULL,?)",[$scopes['blocked'],idf()]);
class ObservedInvitationWorker extends NativeInvitationMailQueue{public $locks=[];protected function one($sql,array$params=[]){$this->locks[]=$sql;return parent::one($sql,$params);}}
$worker=new ObservedInvitationWorker($container);$blocked=[];
function jobf($id,$sid,$state,$when,$expired=false){global$u,$worker;$token='fhi3_'.bin2hex(random_bytes(32));qf('INSERT INTO familyhub_invitations(id,scope_id,creator_id,creator_account_id,recipient_username,role,token_hash,created_at,expires_at,recipient_email,invitation_contract) VALUES(?,?,?,?,?,?,?,?,?,?,3)',[$id,$sid,$u['user']['id'],$u['user']['accountId'],'','viewer',hash('sha256',$token),time()-100,$expired?time()-1:time()+3600,'synthetic@capture.invalid']);qf('INSERT INTO familyhub_invitation_mail VALUES(?,?,?,?,?,?,?,?,?)',[$id,NativeAccountMailCrypto::encrypt($token,$worker->aad($id)),'en',$state,2,$when,$state==='processing'?str_repeat('a',32):null,$state==='processing'?0:null,$state==='accepted'?time()-20:null]);}
for($i=0;$i<55;$i++){ $id=idf();jobf($id,$scopes['blocked'],$i===0?'accepted':($i%2?'processing':'pending'),0,$i===2);$blocked[]=$id; }
$before=qf('SELECT m.* FROM familyhub_invitation_mail m JOIN familyhub_invitations i ON i.id=m.invitation_id WHERE i.scope_id=? ORDER BY m.invitation_id',[$scopes['blocked']]);
$eligible=idf();jobf($eligible,$scopes['normal'],'pending',1);
$capture=new class{public$ids=[];public function send($to,$purpose,$url,$id,$language,$details){$this->ids[]=$id;return['accepted'=>true];}};
$run=$worker->run(1,$capture,microtime(true)+90);
if($capture->ids!==[$eligible])echo json_encode(['counts'=>$run,'target'=>qf('SELECT state,attempts FROM familyhub_invitation_mail WHERE invitation_id=?',[$eligible])]).PHP_EOL;
cf($capture->ids===[$eligible],'blocked earliest 55 jobs do not starve later eligible mail');
cf(qf('SELECT m.* FROM familyhub_invitation_mail m JOIN familyhub_invitations i ON i.id=m.invitation_id WHERE i.scope_id=? ORDER BY m.invitation_id',[$scopes['blocked']])===$before,'fenced ready processing accepted and expired mail remain byte exact');
cf(qf('SELECT state,attempts FROM familyhub_invitation_mail WHERE invitation_id=?',[$eligible])[0]['state']==='accepted','capture accepted result finalizes original job');
$lastUser=-1;$outcomeScope=-1;$lastJob=-1;foreach($worker->locks as$i=>$sql){if(str_starts_with($sql,'SELECT id FROM users'))$lastUser=$i;if($lastUser>=0&&str_starts_with($sql,'SELECT * FROM familyhub_scopes'))$outcomeScope=$i;if($outcomeScope>=0&&str_starts_with($sql,'SELECT * FROM familyhub_invitation_mail'))$lastJob=$i;}
cf($lastUser>=0&&$outcomeScope>$lastUser&&$lastJob>$outcomeScope,'outcome acquires creator before scope before job');
$beforeCount=count($capture->ids);$worker->run(1,$capture,microtime(true)+90);cf(count(array_filter($capture->ids,fn($v)=>$v===$eligible))===1,'accepted delivery cannot repeat on worker restart');
echo 'Invitation mail fence '.$checks.' PASS'.PHP_EOL;
