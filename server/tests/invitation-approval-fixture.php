<?php
/** Private helper for the new owned 59780 synthetic fixture; never an HTTP endpoint. */
define('FAMILYHUB_PUBLIC_URL', 'http://127.0.0.1:59780');
require '/var/www/app/app/common.php';
if (session_status() === PHP_SESSION_ACTIVE) session_abort();
if (!defined('FAMILYHUB_DEVELOPMENT_MODE') || FAMILYHUB_DEVELOPMENT_MODE !== true) throw new RuntimeException('Synthetic only');
$pdo=$container['db']->getConnection();
$action=$argv[1]??'';$id=$argv[2]??'';
if (!preg_match('/^[a-f0-9-]{36}$/D',$id)) throw new RuntimeException('Exact synthetic UUID required');
$query=function($sql,$args)use($pdo){$q=$pdo->prepare($sql);$q->execute($args);$rows=$q->fetchAll(PDO::FETCH_ASSOC);$q->closeCursor();return $rows;};
if ($action==='verification') {
    $users=$query("SELECT u.username FROM familyhub_accounts a JOIN users u ON u.id=a.user_id WHERE a.account_id=? AND u.username LIKE 'inviteapproval_%'",[$id]);
    if(count($users)!==1)throw new RuntimeException('Exact synthetic account required');
    $rows=$query("SELECT t.id,t.account_id,m.token_cipher FROM familyhub_account_tokens t JOIN familyhub_account_mail m ON m.token_id=t.id WHERE t.account_id=? AND t.purpose='verify' AND t.consumed_at IS NULL AND t.revoked_at IS NULL",[$id]);
    if(count($rows)!==1)throw new RuntimeException('Exact pending verification required');$row=$rows[0];
    $token=\Kanboard\Plugin\FamilyHub\Model\NativeAccountMailCrypto::decrypt($row['token_cipher'],(new \Kanboard\Plugin\FamilyHub\Model\NativeAccountTokens($container))->aad($row['id'],$row['account_id']));
    echo json_encode(['token'=>$token],JSON_THROW_ON_ERROR);return;
}
$rows=$query("SELECT i.* FROM familyhub_crypto_invitations_v2 i JOIN familyhub_accounts a ON a.account_id=i.creator_account_id JOIN users u ON u.id=a.user_id WHERE i.id=? AND u.username LIKE 'inviteapproval_%'",[$id]);
if(count($rows)!==1)throw new RuntimeException('Exact synthetic invitation required');$invitation=$rows[0];
if($action==='continuation-state'){
    $child=$argv[3]??'';$request=$argv[4]??'';
    foreach([$child,$request]as$value)if(!preg_match('/^[a-f0-9-]{36}$/D',$value))throw new RuntimeException('Exact continuation IDs required');
    $out=[];
    foreach(['parent'=>$invitation['scope_id'],'child'=>$child]as$label=>$sid){
        $heads=$query('SELECT h.head_hash,h.epoch,h.payload FROM familyhub_crypto_scope_state s JOIN familyhub_crypto_scope_heads h ON h.scope_id=s.scope_id AND h.head_hash=s.head_hash WHERE s.scope_id=?',[$sid]);
        if(count($heads)!==1)throw new RuntimeException('Exact current scope required');$head=$heads[0];$body=json_decode($head['payload'],true,34,JSON_THROW_ON_ERROR);
        $out[$label]=['headHash'=>$head['head_hash'],'epoch'=>(int)$head['epoch'],'memberCount'=>count($body['members']),'hasRecipient'=>in_array($invitation['recipient_account_id'],array_column($body['members'],'accountId'),true)];
    }
    $receipts=$query('SELECT status,request_hash,authorization FROM familyhub_crypto_receipts WHERE account_id=? AND request_id=?',[$invitation['creator_account_id'],$request]);
    if(count($receipts)!==1)throw new RuntimeException('Exact retained receipt required');$receipt=$receipts[0];
    $out['parentActivationReceipt']=['status'=>(int)$receipt['status'],'commandHash'=>$receipt['request_hash'],'proofHash'=>\Kanboard\Plugin\FamilyHub\Model\NativeCryptoV2Codec::hash((object)json_decode($receipt['authorization'],true,34,JSON_THROW_ON_ERROR))];
    $out['creationProofHash']=\Kanboard\Plugin\FamilyHub\Model\NativeCryptoV2Codec::hash((object)json_decode($invitation['authorization'],true,34,JSON_THROW_ON_ERROR));
    $out['acceptances']=$query('SELECT proof_hash AS proofHash,state FROM familyhub_crypto_invitation_acceptances_v2 WHERE invitation_id=?',[$id]);
    $out['invitationState']=$invitation['state'];
    $out['pushReferences']=$query('SELECT j.state,j.attempts FROM familyhub_push_jobs j JOIN familyhub_inbox i ON i.id=j.inbox_id WHERE i.target_id=?',[$id]);
    echo json_encode($out,JSON_THROW_ON_ERROR);return;
}
if($action==='capture-invitation'){
    $fake=new class($id){public $messages=[];private $id;public function __construct($id){$this->id=$id;}public function send($to,$purpose,$url,$id,$language,$details=[]){if($id!==$this->id||$purpose!=='invitation')throw new RuntimeException('Wrong synthetic mail');$this->messages[]=['to'=>$to,'url'=>$url,'id'=>$id];return ['accepted'=>true];}};
    $result=(new \Kanboard\Plugin\FamilyHub\Model\NativeCryptoInvitationMailV2($container))->run(1,$fake);
    if($result['accepted']!==1||count($fake->messages)!==1)throw new RuntimeException('Capture did not accept exact invitation');
    echo json_encode($fake->messages[0],JSON_THROW_ON_ERROR);return;
}
if($action==='arm-unsent-reference'){
    $notices=$query("SELECT id FROM familyhub_inbox WHERE target_id=? AND kind='crypto2.invitation.accepted'",[$id]);
    if(count($notices)!==1)throw new RuntimeException('Exact acceptance notice required');
    $query("INSERT INTO familyhub_push_jobs(inbox_id,device_id,registration_revision,token_hash,state,attempts,next_attempt,expires_at) VALUES(?,?,1,?,'pending',0,?,?)",[$notices[0]['id'],'00000000-0000-4000-a000-000000059780',hash('sha256','synthetic no registration'),time()+3600,time()+7200]);
}
$notices=$query("SELECT id,target_id,recipient_account_id,kind FROM familyhub_inbox WHERE target_id=? AND kind='crypto2.invitation.accepted'",[$id]);
$jobs=$query('SELECT j.state,j.attempts FROM familyhub_push_jobs j JOIN familyhub_inbox i ON i.id=j.inbox_id WHERE i.target_id=?',[$id]);
$mail=$query('SELECT state,token_cipher IS NOT NULL AS hasCipher FROM familyhub_crypto_invitation_mail_v2 WHERE invitation_id=?',[$id]);
echo json_encode(['invitationState'=>$invitation['state'],'mail'=>$mail[0]??null,'acceptanceNotices'=>$notices,'pushReferences'=>$jobs,'pushRegistrationCreated'=>false,'externalDeliveryAttempted'=>false],JSON_THROW_ON_ERROR);
