<?php
// Real loopback SMTP plus independent Native/core mutation processes. No real mail.
$port = random_int(30000, 40000);
define('FAMILYHUB_SMTP_HOST', '127.0.0.1'); define('FAMILYHUB_SMTP_PORT', $port);
define('FAMILYHUB_SMTP_ENCRYPTION', 'none'); define('FAMILYHUB_SMTP_ALLOW_LOCAL_PLAINTEXT', true);
define('FAMILYHUB_SMTP_FROM', 'sender@capture.invalid');
require '/var/www/app/app/common.php';
if (!defined('FAMILYHUB_DEVELOPMENT_MODE') || FAMILYHUB_DEVELOPMENT_MODE !== true) { throw new RuntimeException('Development only'); }
if (session_status() === PHP_SESSION_ACTIVE) { session_abort(); }
use Kanboard\Plugin\FamilyHub\Model\NativeDeliveryService;
use Kanboard\Plugin\FamilyHub\Model\NativeNotificationWriter;
use Kanboard\Plugin\FamilyHub\Model\NativeSmtpTransport;
$pdo = $container['db']->getConnection(); $checks = 0; $failures = 0;
$prefix = 'smtp_race_'.bin2hex(random_bytes(4));
$output = '/tmp/familyhub-smtp-'.bin2hex(random_bytes(8)).'.json';
function uuid() { $h = bin2hex(random_bytes(16)); return substr($h,0,8).'-'.substr($h,8,4).'-4'.substr($h,13,3).'-a'.substr($h,17,3).'-'.substr($h,20); }
function check($ok, $description) { global $checks, $failures; $checks++; if (!$ok) { $failures++; } echo ($ok ? 'PASS: ' : 'FAIL: ').$description.PHP_EOL; }
function query($sql, $params = []) { global $pdo; $q=$pdo->prepare($sql); $q->execute($params); $rows=$q->fetchAll(PDO::FETCH_ASSOC); $q->closeCursor(); return $rows; }
function change($sql, $params = []) { global $pdo; $q=$pdo->prepare($sql); $q->execute($params); $q->closeCursor(); }
function capture() { global $output; return json_decode(file_get_contents($output), true, 32, JSON_THROW_ON_ERROR)['messages']; }
function mutation($fixture) {
    $file = tempnam('/tmp', 'familyhub-smtp-race-'); chmod($file,0600); file_put_contents($file,json_encode($fixture,JSON_THROW_ON_ERROR));
    $process = proc_open([PHP_BINARY,'/familyhub-tests/smtp-race-child.php',$file],[0=>['pipe','r'],1=>['pipe','w'],2=>['pipe','w']],$pipes);
    if (!is_resource($process)) { unlink($file); throw new RuntimeException('Child unavailable'); }
    stream_set_timeout($pipes[1], 10);
    if (trim(fgets($pipes[1])) !== 'ready') { throw new RuntimeException('Child not ready'); }
    return [$process,$pipes,$file];
}
function startMutation($child) {
    fwrite($child[1][0],"go\n"); fflush($child[1][0]);
    if (trim(fgets($child[1][1])) !== 'attempting') { throw new RuntimeException('Child did not reach mutation'); }
}
function finishMutation($child) {
    stream_set_blocking($child[1][1], true); stream_set_timeout($child[1][1], 10);
    $done = trim(fgets($child[1][1])) === 'done';
    foreach ($child[1] as $pipe) { fclose($pipe); } $exit = proc_close($child[0]); unlink($child[2]);
    if (!$done || $exit !== 0) { throw new RuntimeException('Synthetic mutation did not complete'); }
}
function scenario($action) {
    global $container,$prefix;
    $password=bin2hex(random_bytes(16)); $scope=uuid();
    $ownerId=$container['userModel']->create(['username'=>$prefix.'_o_'.bin2hex(random_bytes(3)),'password'=>$password,'role'=>'app-user']);
    $userId=$container['userModel']->create(['username'=>$prefix.'_r_'.bin2hex(random_bytes(3)),'password'=>$password,'email'=>'old@capture.invalid','role'=>'app-user']);
    $auth=new \Kanboard\Plugin\FamilyHub\Model\NativeAuthService($container);
    $owner=$auth->issue($container['userModel']->getById($ownerId),'Synthetic SMTP owner');
    $recipient=$auth->issue($container['userModel']->getById($userId),'Synthetic SMTP recipient');
    change('INSERT INTO familyhub_scopes(id,kind,name,owner_id,sequence,created_at) VALUES(?,\'household\',\'Synthetic SMTP race\',?,0,?)',[$scope,$ownerId,time()]);
    foreach ([[$ownerId,$owner['user']['accountId'],'owner'],[$userId,$recipient['user']['accountId'],'member']] as $member) { change('INSERT INTO familyhub_members(scope_id,user_id,account_id,role,active) VALUES(?,?,?,?,1)',array_merge([$scope],$member)); }
    $finance=$action==='finance'; $category=$finance?'finance':'tasks'; $account=$recipient['user']['accountId'];
    change('INSERT INTO familyhub_inbox_preferences VALUES(?,?,?,?)',[$scope,$account,$category,json_encode(['inApp'=>true,'sound'=>false,'push'=>false,'email'=>true])]);
    if ($finance) { change('INSERT INTO familyhub_finance_policy(scope_id,enabled,revision,sequence) VALUES(?,1,1,0)',[$scope]); foreach ([$owner['user']['accountId'],$account] as $a) { change('INSERT INTO familyhub_finance_grants VALUES(?,?,\'write\')',[$scope,$a]); } }
    $GLOBALS['pdo']->beginTransaction();
    (new NativeNotificationWriter($container))->insert($scope,$account,null,$finance?'financeEntry':'task',uuid(),1,$finance?'financeEntry.created':'task.created',$category,'scope',hash('sha256',$scope));
    $GLOBALS['pdo']->commit();
    $inbox=(int)query('SELECT id FROM familyhub_inbox WHERE scope_id=?',[$scope])[0]['id'];
    return ['action'=>$action,'scope'=>$scope,'userId'=>$userId,'accountId'=>$account,'ownerToken'=>$owner['token'],'recipientToken'=>$recipient['token'],'password'=>$password,'ip'=>$prefix,'requestId'=>uuid(),'inboxId'=>$inbox];
}
class LeaseBarrierDelivery extends NativeDeliveryService {
    private $hook;
    public function __construct($container, $hook) { parent::__construct($container); $this->hook=$hook; }
    protected function transaction(callable $callback, $global=false) {
        $result=parent::transaction($callback,$global);
        // Pause after the actual durable lease commit, never within its lock.
        if ($this->hook) { $hook=$this->hook; $this->hook=null; $hook(); }
        return $result;
    }
}
$process=proc_open([PHP_BINARY,'/familyhub-tests/smtp-capture.php',$output,(string)$port,'900'],[0=>['pipe','r'],1=>['pipe','w'],2=>['pipe','w']],$pipes);
if (!is_resource($process)) { throw new RuntimeException('Capture unavailable'); }
stream_set_timeout($pipes[1],5); if (trim(fgets($pipes[1]))!=='ready') { throw new RuntimeException('Capture not ready'); }
try {
    foreach (['membership','finance','preference','deactivate','deletion','email'] as $action) {
        $fixture=scenario($action); $before=count(capture()); $child=mutation($fixture);
        $delivery=new LeaseBarrierDelivery($container,function() use($child) { startMutation($child); finishMutation($child); });
        $counts=$delivery->run(1); $messages=array_slice(capture(),$before);
        if ($action==='email') {
            check($counts['accepted']===1 && count($messages)===1 && $messages[0]['recipients']===['new@capture.invalid'],'completed core email change after lease uses fresh recipient');
        } else { check($counts['accepted']===0 && !$messages,'completed '.$action.' after lease prevents SMTP'); }
        $jobs=query('SELECT * FROM familyhub_deliveries WHERE inbox_id=?',[$fixture['inboxId']]);
        check(!$jobs || ((int)$jobs[0]['attempts']===1 && $jobs[0]['lease_token']===null),'durable attempt preserved and lease completed after '.$action);
    }
    if (!in_array('--leased-only',$argv,true)) {
        foreach (['email','membership','preference','finance','deletion'] as $action) {
            $fixture=scenario($action); $before=count(capture()); $child=mutation($fixture);
            $transport=new class($child) extends NativeSmtpTransport {
                private $child;
                public function __construct($child) { $this->child=$child; }
                public function send($recipient,$inboxId,$accountId) {
                    startMutation($this->child); stream_set_blocking($this->child[1][1],false); usleep(200000);
                    check(fread($this->child[1][1],8192)==='','concurrent mutation waits through in-flight SMTP');
                    return parent::send($recipient,$inboxId,$accountId);
                }
            };
            $counts=(new NativeDeliveryService($container))->run(1,$transport); finishMutation($child);
            $messages=array_slice(capture(),$before);
            check($counts['accepted']===1 && count($messages)===1 && $messages[0]['recipients']===['old@capture.invalid'],'SMTP linearizes before waiting '.$action.' commit');
            check((new NativeDeliveryService($container))->run(1)['accepted']===0 && count(capture())===$before+1,'acknowledged SMTP is not retried after '.$action);
        }
        $fixture=scenario('deliveryCrash'); $fixture['port']=$port; $before=count(capture()); $child=mutation($fixture);
        startMutation($child); stream_get_contents($child[1][1]);
        foreach ($child[1] as $pipe) { fclose($pipe); } $exit=proc_close($child[0]); unlink($child[2]);
        check($exit===73 && count(capture())===$before+1,'worker process exits after actual SMTP acceptance before DB acknowledgement');
        $job=query('SELECT * FROM familyhub_deliveries WHERE inbox_id=?',[$fixture['inboxId']])[0];
        check($job['state']==='processing' && (int)$job['attempts']===1 && $job['lease_token']!==null,'crash preserves committed lease and attempt while send transaction rolls back');
        check((new NativeDeliveryService($container))->run(1)['examined']===0 && count(capture())===$before+1,'unexpired durable lease prevents competing retry after crash');
        change('UPDATE familyhub_deliveries SET lease_until=0 WHERE inbox_id=?',[$fixture['inboxId']]);
        check((new NativeDeliveryService($container))->run(1)['accepted']===1,'expired crash lease permits bounded retry');
        $messages=array_slice(capture(),$before); $ids=[];
        foreach ($messages as $message) { preg_match('/Message-ID: ([^\r\n]+)/i',$message['body'],$match); $ids[]=$match[1]??null; }
        $job=query('SELECT * FROM familyhub_deliveries WHERE inbox_id=?',[$fixture['inboxId']])[0];
        check(count($messages)===2 && $ids[0]!==null && $ids[0]===$ids[1] && (int)$job['attempts']===2 && $job['state']==='sent','ambiguous crash can duplicate SMTP with stable Message-ID and durable attempt count');
        $fixture=scenario('email'); $before=count(capture());
        $transport=new class extends NativeSmtpTransport {
            public function send($recipient,$inboxId,$accountId) { parent::send($recipient,$inboxId,$accountId); throw new RuntimeException('Synthetic lost ACK'); }
        };
        check((new NativeDeliveryService($container))->run(1,$transport)['retry']===1 && count(capture())===$before+1,'lost SMTP acknowledgement persists retry despite actual provider acceptance');
        $fixture['action']='preference'; $child=mutation($fixture); startMutation($child); finishMutation($child);
        change('UPDATE familyhub_deliveries SET next_attempt=0 WHERE inbox_id=?',[$fixture['inboxId']]);
        check((new NativeDeliveryService($container))->run(1)['cancelled']===1 && count(capture())===$before+1,'completed mute prevents retry of ambiguous SMTP acceptance');
        foreach (['sl','en'] as $language) {
            $before=count(capture());
            (new \Kanboard\Plugin\FamilyHub\Model\NativeAccountMailTransport())->send('security@capture.invalid','verify','synthetic-one-time-code',uuid(),$language);
            $message=capture()[$before];
            check(strpos($message['body'],'From: Jivie <')!==false && strpos($message['body'],'Jivie')!==false && strpos($message['body'],'Vsakdan')===false,'security SMTP identifies Jivie in '.$language.' mail');
        }
    }
    echo ($failures?'FAILED ':'SUCCESS ').$checks.' SMTP race checks ('.$pdo->getAttribute(PDO::ATTR_DRIVER_NAME).', local capture only)'.PHP_EOL;
} finally { proc_terminate($process); foreach($pipes as $pipe) { if(is_resource($pipe)) { fclose($pipe); } } proc_close($process); @unlink($output); @unlink($output.'.mode'); }
exit($failures?1:0);
