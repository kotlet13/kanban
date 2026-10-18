<?php
/** Synthetic source-bound staged bridge; final verify3 callback isolated here. */
define('FAMILYHUB_ACCOUNT_MAIL_KEY_BASE64',base64_encode(random_bytes(32)));
define('FAMILYHUB_PUBLIC_URL','http://127.0.0.1:18785');
define('FAMILYHUB_SMTP_HOST','127.0.0.1');define('FAMILYHUB_SMTP_PORT',39999);define('FAMILYHUB_SMTP_ENCRYPTION','none');define('FAMILYHUB_SMTP_ALLOW_LOCAL_PLAINTEXT',true);define('FAMILYHUB_SMTP_FROM','sender@capture.invalid');
require __DIR__.'/crypto2-scope-integration.php';
use Kanboard\Plugin\FamilyHub\Model\NativeCryptoMigrationInvitationStageV3 as Bridge;
use Kanboard\Plugin\FamilyHub\Model\NativeCryptoMigrationInvitationV3 as Cert;
use Kanboard\Plugin\FamilyHub\Model\NativeCryptoCodec;

$state=call('crypto2.account.status',[],$fresh);$account=$fresh['user']['accountId'];$sid=$space['id'];
$actor=['user'=>['id'=>$fresh['user']['id'],'account_id'=>$account],'device'=>['id'=>$fresh['device']['id']]];
$mig=uid();$cap=uid();$rootHash=hash('sha256',random_bytes(32));$bridge=new Bridge($container);
$guest=user('bridge_guest');
$guestEmail=q('SELECT email FROM familyhub_email_identities WHERE account_id=?',[$guest['user']['accountId']])[0]['email'];
$common=['version'=>3,'serverId'=>$fresh['serverId'],'migrationId'=>$mig,'captureId'=>$cap,'accountId'=>$account,'sourceInventoryRoot'=>$rootHash];
$head=call('crypto2.scope.headGet',['scopeId'=>$sid],$fresh);$entries=[];$items=[];$original=[];$tokens=[];
foreach(['pending','accepted','revoked','expired']as$i=>$status){
    $id=uid();$token='fhi'.($i%3+1).'_'.bin2hex(random_bytes(32));$tokens[$status]=$token;
    $raw=['id'=>$id,'scope_id'=>$sid,'creator_id'=>$fresh['user']['id'],'creator_account_id'=>$account,
        'recipient_username'=>'','recipient_email'=>$status==='pending'?$guestEmail:'bridge_'.$i.'@example.invalid','recipient_account_id'=>null,'role'=>'viewer',
        'token_hash'=>hash('sha256',$token),'created_at'=>time()-1000,'expires_at'=>$status==='expired'?time()-1:time()+3600,
        'accepted_at'=>$status==='accepted'?time()-500:null,'accepted_by'=>null,'accepted_account_id'=>null,
        'revoked_at'=>$status==='revoked'?time()-500:null,'invitation_contract'=>3,'access_scope'=>'space'];
    q('INSERT INTO familyhub_invitations('.implode(',',array_keys($raw)).') VALUES('.implode(',',array_fill(0,count($raw),'?')).')',array_values($raw));
    $original[$status]=$raw;$binding=uid();$bridgeId=uid();$commit=hash('sha256',random_bytes(32));
    $context=['version'=>3,'purpose'=>'legacyInvitationBridge','serverId'=>$fresh['serverId'],'migrationId'=>$mig,'captureId'=>$cap,
        'sourceInventoryRoot'=>$rootHash,'bridgeId'=>$bridgeId,'bindingId'=>$binding,'sourceCommitment'=>$commit,'scopeId'=>$sid,'membershipHeadHash'=>$head['headHash']];
    $metadata=['version'=>3,'invitationId'=>$id,'scopeId'=>$sid,'recipient'=>['kind'=>'email','value'=>$raw['recipient_email'],'accountId'=>null],
        'role'=>'viewer','expiresAtEpoch'=>$raw['expires_at'],'acceptedAtEpoch'=>$raw['accepted_at'],'revokedAtEpoch'=>$raw['revoked_at'],
        'legacyContractVersion'=>3,'tokenHash'=>$raw['token_hash']];
    $key=sodium_crypto_generichash("JivieLegacyInvitationCapsuleKey/v3\n".NativeCryptoCodec::canonical((object)['version'=>3,'serverId'=>$fresh['serverId'],'bridgeId'=>$bridgeId])."\n".hex2bin($raw['token_hash']),'',32);
    $nonce=random_bytes(24);$cipher=sodium_crypto_aead_xchacha20poly1305_ietf_encrypt(NativeCryptoCodec::canonical((object)$metadata),NativeCryptoCodec::canonical((object)$context),$nonce,$key);sodium_memzero($key);
    $encoded=base64_encode(NativeCryptoCodec::canonical((object)['version'=>1,'suite'=>'sodium-box-seal-xchacha20poly1305-ed25519-v1','context'=>$context,'nonceBase64'=>base64_encode($nonce),'ciphertextBase64'=>base64_encode($cipher)]));
    $body=['context'=>$context,'sourceKind'=>'invitation','invitationBindingId'=>$binding,'authorDirectoryHeadHash'=>$state['headHash'],'capsuleHash'=>hash('sha256',base64_decode($encoded)),'capsuleSize'=>strlen(base64_decode($encoded))];
    $items[]=['authorization'=>content2('crypto2.invitations.bridgeLegacy',$body,$fresh,$freshKeys),'capsuleBase64'=>$encoded];
    $entries[$binding]=['context'=>['version'=>3,'serverId'=>$fresh['serverId'],'migrationId'=>$mig,'captureId'=>$cap,'accountId'=>$account,'scopeId'=>null,'domain'=>'private','sourceTable'=>'familyhub_invitations','sourceId'=>'row:'.$i],
        'binding'=>['bindingId'=>$binding,'scopeId'=>null,'domain'=>'private','sourceCommitment'=>$commit],
        'typedRow'=>(object)array_map(fn($v)=>['type'=>$v===null?'null':'text','valueBase64'=>$v===null?null:base64_encode((string)$v)],$raw)];
    if($status==='pending'){
        $mail=['invitation_id'=>$id,'token_cipher'=>\Kanboard\Plugin\FamilyHub\Model\NativeAccountMailCrypto::encrypt($token,$fresh['serverId'].':email-invitation:'.$id),'language'=>'en','state'=>'processing','attempts'=>3,'next_attempt'=>time()+40,'lease_token'=>str_repeat('d',32),'lease_until'=>time()+80,'accepted_at'=>null];
        q('INSERT INTO familyhub_invitation_mail VALUES(?,?,?,?,?,?,?,?,?)',array_values($mail));
        $mailBinding=uid();$mailContext=$context;$mailContext['bindingId']=$mailBinding;$mailContext['sourceCommitment']=hash('sha256',random_bytes(32));
        $mailBody=$body;$mailBody['context']=$mailContext;$mailBody['sourceKind']='mail';$mailBody['capsuleHash']=null;$mailBody['capsuleSize']=0;
        $items[]=['authorization'=>content2('crypto2.invitations.bridgeLegacy',$mailBody,$fresh,$freshKeys),'capsuleBase64'=>null];
        $entries[$mailBinding]=['context'=>array_replace($entries[$binding]['context'],['sourceTable'=>'familyhub_invitation_mail','sourceId'=>'row:0']),
            'binding'=>['bindingId'=>$mailBinding,'scopeId'=>null,'domain'=>'private','sourceCommitment'=>$mailContext['sourceCommitment']],
            'typedRow'=>(object)array_map(fn($v)=>['type'=>$v===null?'null':'text','valueBase64'=>$v===null?null:base64_encode((string)$v)],$mail)];
        $mailBefore=q('SELECT * FROM familyhub_invitation_mail WHERE invitation_id=?',[$id]);
    }
}
ksort($entries,SORT_STRING);
$resolve=function($m,$c,$b,$a)use(&$entries,$mig,$cap,$account){if($m!==$mig||$c!==$cap||$a['user']['account_id']!==$account||!isset($entries[$b]))throw new RuntimeException('test source');return$entries[$b];};
$iterate=function($m,$c,$r,$a,$tables)use(&$entries,$rootHash){if($r!==$rootHash)throw new RuntimeException('test root');foreach($entries as$entry){if(in_array($entry['context']['sourceTable'],$tables,true))yield array_intersect_key($entry,array_flip(['context','binding']));}};
$p=['migrationId'=>$mig,'captureId'=>$cap,'sourceInventoryRoot'=>$rootHash,'bridges'=>$items];$proof=content2('crypto2.migration.invitations.stage',$p,$fresh,$freshKeys);[$command]=NativeCryptoCodec::decode($proof);
$pdo->beginTransaction();
$bad=$p;$bad['bridges'][0]['capsuleBase64']=base64_encode('substituted');$bp=content2('crypto2.migration.invitations.stage',$bad,$fresh,$freshKeys);[$bc]=NativeCryptoCodec::decode($bp);
deny(fn()=>$bridge->stage($bad,$actor,$bp,$bc,$resolve),'crypto_invitation_bridge_capsule','substituted capsule rejected before active effects');
$staged=$bridge->stage($p,$actor,$proof,$command,$resolve);
ck(count($staged['leaves'])===5,'all invitation states and private mail staged');
ck($bridge->stage($p,$actor,$proof,$command,$resolve)===$staged,'exact immutable replay retains original cipher and proof');
ck(q('SELECT * FROM familyhub_crypto_invitations_v2 WHERE scope_id=?',[$sid])===[],'stage creates no active invitation or membership');
$coverage=$bridge->stagedCoverage($mig,$cap,$rootHash,$actor,$iterate);
ck($coverage['bridgeCount']===5&&$coverage['sourceCounts']===['invitation'=>4,'mail'=>1],'full frozen coverage counts exact native sources');
$extra=uid();$entries[$extra]=['context'=>['sourceTable'=>'familyhub_invitations'],'binding'=>['bindingId'=>$extra,'scopeId'=>null,'domain'=>'private','sourceCommitment'=>str_repeat('e',64)]];ksort($entries);
deny(fn()=>$bridge->stagedCoverage($mig,$cap,$rootHash,$actor,$iterate),'crypto_invitation_bridge_incomplete','omitted native source blocks final completeness');unset($entries[$extra]);
$hashes=array_map(fn($leaf)=>Cert::leafDigest($leaf),$staged['leaves']);sort($hashes,SORT_STRING);
$header=$common+['archiveManifestHash'=>str_repeat('c',64),'coldParityProofHash'=>str_repeat('d',64),'authorDirectoryHeadHash'=>$state['headHash'],'bridgeCount'=>5,'sourceCounts'=>$coverage['sourceCounts'],'bridgeRoot'=>str_repeat('0',64)];$header['bridgeRoot']=Cert::bridgeRoot($header,$hashes);
$certProof=content2('crypto2.migration.invitations.certify',['header'=>$header],$fresh,$freshKeys);[$cc]=NativeCryptoCodec::decode($certProof);
deny(fn()=>$bridge->certify(['header'=>$header],$actor,$certProof,$cc,$iterate,fn()=>false),'crypto_invitation_migration_cold_parity','final certificate requires verified cold parity callback');
$cert=$bridge->certify(['header'=>$header],$actor,$certProof,$cc,$iterate,fn()=>true);$pdo->commit();
$eventProof=request2('crypto2.account.migrationAttest',['migrationId'=>$mig,'scopeToken'=>Cert::scopeToken($header),'domain'=>'content','attestationHash'=>$cert['certificateHash']],$fresh,$freshKeys,$state['snapshot'],$state);$event=call('crypto2.account.migrationAttest',$eventProof,$fresh);
$pdo->beginTransaction();$bridge->anchor(['migrationId'=>$mig,'captureId'=>$cap,'sourceInventoryRoot'=>$rootHash,'certificateHash'=>$cert['certificateHash'],'eventHeadHash'=>$event['headHash'],'eventCommandHash'=>hash('sha256',base64_decode($eventProof['commandBase64']))],$actor);
$anchored=$bridge->coverage($mig,$cap,$rootHash,$actor,$iterate);
$pdo->exec('SAVEPOINT bridge_abort');$abortPlan=$bridge->prepareInstall($anchored,$actor,$iterate,$resolve);$abortPlan();
ck(count(q('SELECT invitation_id FROM familyhub_crypto_invitation_mail_v2 WHERE invitation_id=?',[$original['pending']['id']]))===1,'prepared cutover mirrors same original delivery identity');
$pdo->exec('ROLLBACK TO SAVEPOINT bridge_abort');$pdo->exec('RELEASE SAVEPOINT bridge_abort');
ck(q('SELECT invitation_id FROM familyhub_crypto_invitation_mail_v2 WHERE invitation_id=?',[$original['pending']['id']])===[],'aborted cutover leaves no canonical delivery continuation');
$installed=$bridge->install($anchored,$actor,$iterate,$resolve);$pdo->commit();
ck($installed['state']==='installed','only exact anchored certificate installs inside final transaction');
ck(q('SELECT * FROM familyhub_invitation_mail WHERE invitation_id=?',[$original['pending']['id']])===$mailBefore,'mail bytes attempts lease and SMTP state preserved with no resend');
ck(q('SELECT * FROM familyhub_crypto_invitation_mail_v2 WHERE invitation_id=?',[$original['pending']['id']])===$mailBefore,'all nine delivery columns mirror exact original intent without reset');
foreach($original as$status=>$raw){$v=q('SELECT * FROM familyhub_crypto_invitations_v2 WHERE id=?',[$raw['id']])[0];ck($v['token_hash']===$raw['token_hash']&&(int)$v['expires_at']===$raw['expires_at']&&$v['id']===$raw['id'],'retained exact original token association id and expiry '.$status);}
// This isolated stage/install fixture has no final scoped publication. An
// installed helper flag alone must not expose token or digest evidence; the
// existing retained HTTP representative covers the complete cutover proof.
deny(fn()=>$bridge->retained(hash('sha256',$tokens['pending'])),'crypto_invitation_cutover_pending','installed stage alone cannot expose retained token evidence');
deny(fn()=>$bridge->digestPage(hash('sha256',$tokens['pending']),null,2),'crypto_invitation_cutover_pending','installed stage alone cannot expose retained digest stream');
$stored=q('SELECT * FROM familyhub_crypto_invitation_bridges_v3 WHERE migration_id=? ORDER BY binding_id LIMIT 1',[$mig])[0];q('UPDATE familyhub_crypto_invitation_bridges_v3 SET leaf_hash=? WHERE migration_id=? AND binding_id=?',[str_repeat('0',64),$mig,$stored['binding_id']]);
deny(fn()=>$bridge->retained(hash('sha256',$tokens['pending'])),'crypto_invitation_bridge_storage','retained evidence revalidates complete signed leaf stream');q('UPDATE familyhub_crypto_invitation_bridges_v3 SET leaf_hash=? WHERE migration_id=? AND binding_id=?',[$stored['leaf_hash'],$mig,$stored['binding_id']]);
echo 'Invitation bridge focus: '.$checks.' cumulative checks PASS'.PHP_EOL;

class TargetBridgeMail extends \Kanboard\Plugin\FamilyHub\Model\NativeCryptoInvitationMailV2 {
    public $target;
    protected function many($sql,array $params=[]) {
        if(str_starts_with($sql,'SELECT invitation_id FROM familyhub_crypto_invitation_mail_v2 WHERE')) {
            $split=explode(' ORDER BY ',$sql,2);$start=strpos($split[0],' WHERE ');
            $sql=substr($split[0],0,$start).' WHERE ('.substr($split[0],$start+7).') AND invitation_id=? ORDER BY '.$split[1];$params[]=$this->target;
        }
        return parent::many($sql,$params);
    }
}
$worker=new TargetBridgeMail($container);$worker->target=$original['pending']['id'];
$captureMail=new class{public $messages=[];public function send($to,$purpose,$url,$id,$language,$details){$this->messages[]=compact('url','id','details');return['accepted'=>true];}};
$worker->run(1,$captureMail,microtime(true)+90);
ck($captureMail->messages===[],'processing original lease waits unchanged after cutover');
q('UPDATE familyhub_crypto_invitation_mail_v2 SET lease_until=0,next_attempt=0 WHERE invitation_id=?',[$worker->target]);
$worker->run(1,$captureMail,microtime(true)+90);
ck($captureMail->messages===[],'expired original lease cannot deliver without final scoped publication');
$worker->run(1,$captureMail,microtime(true)+90);
ck($captureMail->messages===[],'restart cannot deliver unpublished retained invitation');
ck(q('SELECT * FROM familyhub_invitation_mail WHERE invitation_id=?',[$worker->target])===$mailBefore,'canonical continuation leaves original frozen delivery evidence unchanged');
// Remove exact installed provenance: the worker must not use legacy AAD.
q("UPDATE familyhub_crypto_invitation_mail_v2 SET state='pending',token_cipher=?,next_attempt=0,attempts=2 WHERE invitation_id=?",[$mailBefore[0]['token_cipher'],$worker->target]);
q("UPDATE familyhub_crypto_invitation_certificates_v3 SET state='anchored' WHERE migration_id=?",[$mig]);
$worker->run(1,$captureMail,microtime(true)+90);
ck($captureMail->messages===[],'missing installed provenance cannot authorize legacy AAD');
q("UPDATE familyhub_crypto_invitation_certificates_v3 SET state='installed' WHERE migration_id=?",[$mig]);
// Restore the accepted canonical state for the independent Dart fixture.
q("UPDATE familyhub_crypto_invitation_mail_v2 SET state='accepted',token_cipher=NULL,lease_token=NULL WHERE invitation_id=?",[$worker->target]);
echo 'Invitation continuation focus: '.$checks.' cumulative checks PASS'.PHP_EOL;
$fixturePath=getenv('JIVIE_BRIDGE_FIXTURE');
if($fixturePath){
    if(!str_starts_with($fixturePath,'/tmp/'))throw new RuntimeException('private tmp fixture only');
    file_put_contents($fixturePath,json_encode(['synthetic'=>true,'serverUrl'=>'http://127.0.0.1:18785',
      'session'=>$guest,'username'=>$guest['username'],'password'=>$guest['password'],'scopeId'=>$sid,
      'token'=>$tokens['pending'],'acceptedToken'=>$tokens['accepted'],'revokedToken'=>$tokens['revoked'],
      'expiredToken'=>$tokens['expired'],'invitationId'=>$original['pending']['id'],
      'creatorRootSigningKeyBase64'=>$root['signPublic'],'creatorRootEncryptionKeyBase64'=>$root['boxPublic']],JSON_THROW_ON_ERROR));
    chmod($fixturePath,0600);
}
