<?php
namespace Kanboard\Plugin\FamilyHub\Model;

/** Email invitations are a separate contract; login/registration never grant membership. */
class NativeEmailInvitationService extends NativeInvitationService
{
    public static function available() { return NativeAccountMailCrypto::configured(); }

    public function execute($operation, array $params)
    {
        $this->rate([['email-invitation-ip:'.$this->ip,120,60]]);
        if ($operation==='invitations2.create') {
            if (!self::available()) { throw new NativeError('email_unavailable',503); }
            $this->fields($params,['scopeId','recipientEmail','role','requestId','language'],['expiresIn']);
            $email=$this->email($params['recipientEmail']);
            $actor=$this->actor(false);
            $this->rate([['invite-sender:'.$actor['user']['account_id'],30,86400],['invite-recipient:'.$email,5,86400]]);
        }
        return $this->transaction(function() use($operation,$params) {
            if ($operation==='invitations2.preview') {
                $this->fields($params,['token']); $row=$this->fromEmailToken($params['token']);
                if ($row['accepted_at']!==null && $this->bearer!=='') {
                    $user=$this->actor()['user'];
                    if ($row['accepted_account_id']!==$user['account_id']) { throw new NativeError('invitation_invalid',403); }
                    return $this->previewWire($row,$this->scope($row['scope_id'],$user['id']),false);
                }
                return $this->previewWire($row,$this->usable($row),true);
            }
            $user=$this->actor()['user'];
            if ($operation==='invitations2.pending') {
                $this->fields($params,[]);
                $identity=$this->verifiedIdentity($user['account_id']);
                $previews=[];
                if ($identity) {
                    $rows=$this->many('SELECT * FROM familyhub_invitations WHERE recipient_email=? AND (recipient_account_id IS NULL OR recipient_account_id=?) AND accepted_at IS NULL AND revoked_at IS NULL AND expires_at>? ORDER BY created_at,id',[$identity['email'],$user['account_id'],time()]);
                    foreach ($rows as $row) {
                        try { $previews[]=$this->previewWire($row,$this->usable($row),false); }
                        catch (NativeError $error) { /* Stale issuer rights never expose a scope. */ }
                    }
                }
                return ['invitations'=>$previews];
            }
            if ($operation==='invitations2.accept') {
                if (array_keys($params)===['token']) { $row=$this->fromEmailToken($params['token']); }
                elseif (array_keys($params)===['invitationId']) { $row=$this->one('SELECT * FROM familyhub_invitations WHERE id=? AND recipient_email IS NOT NULL',[$this->uuid($params['invitationId'])]); }
                else { throw new NativeError('validation_error'); }
                if (!$row) { throw new NativeError('invitation_invalid',404); }
                if ($row['accepted_at']!==null) {
                    if ($row['accepted_account_id']!==$user['account_id']) { throw new NativeError('invitation_invalid',403); }
                    return ['scope'=>$this->scopeWire($this->scope($row['scope_id'],$user['id']))];
                }
                $identity=$this->verifiedIdentity($user['account_id']);
                if (!$identity || $identity['email']!==$row['recipient_email'] || ($row['recipient_account_id']!==null && $row['recipient_account_id']!==$user['account_id'])) { throw new NativeError('invitation_invalid',403); }
                $scope=$this->usable($row);
                $this->change('UPDATE familyhub_invitations SET recipient_account_id=? WHERE id=?',[$user['account_id'],$row['id']]);
                $this->grant($row,$user); $scope=$this->scope($scope['id'],$user['id']); $scope['sequence']=$this->advance($scope);
                return ['scope'=>$this->scopeWire($scope)];
            }
            if ($operation==='invitations2.create') {
                $scopeId=$this->uuid($params['scopeId']); $request=$this->uuid($params['requestId']);
                $scope=$this->scope($scopeId,$user['id'],true,true);
                if ($scope['kind']==='personal') { throw new NativeError('personal_not_shareable',403); }
                $email=$this->email($params['recipientEmail']);
                if (!in_array($params['role'],['member','viewer'],true) || !in_array($params['language'],['sl','en'],true)) { throw new NativeError('validation_error'); }
                $duration=$params['expiresIn']??86400;
                if (!is_int($duration) || $duration<60 || $duration>604800) { throw new NativeError('validation_error'); }
                $hash=$this->hashRequest($operation,$params); $replay=$this->replay($scopeId,$user['id'],$request,$hash);
                if ($replay) { return $replay['body']; }
                // URL comes from administrator configuration, never an HTTP Host header.
                self::publicUrl($this->configModel->get('application_url'));
                $matches=$this->verifiedMatches($email); $bound=count($matches)===1?$matches[0]['account_id']:(count($matches)>1?'ambiguous':null);
                $token='fhi2_'.bin2hex(random_bytes(32)); $now=time(); $id=$this->newUuid();
                $this->change('INSERT INTO familyhub_invitations(id,scope_id,creator_id,creator_account_id,recipient_username,recipient_email,recipient_account_id,role,token_hash,created_at,expires_at) VALUES(?,?,?,?,?,?,?,?,?,?,?)',[$id,$scopeId,$user['id'],$user['account_id'],'',$email,$bound,$params['role'],hash('sha256',$token),$now,$now+$duration]);
                $queue=new NativeInvitationMailQueue($this->container);
                $this->change('INSERT INTO familyhub_invitation_mail(invitation_id,token_cipher,language,state,next_attempt) VALUES(?,?,?,\'pending\',?)',[$id,NativeAccountMailCrypto::encrypt($token,$queue->aad($id)),$params['language'],$now]);
                $row=$this->one('SELECT * FROM familyhub_invitations WHERE id=?',[$id]);
                $result=['invitation'=>$this->wire($row),'deliveryQueued'=>true]; $this->remember($scopeId,$user['id'],$request,$hash,$result);
                return $result;
            }
            throw new NativeError('unsupported_operation',404);
        },$operation==='invitations2.create');
    }

    public function register(array $params)
    {
        $this->fields($params,['token','username','password','displayName','deviceName']);
        $username=$this->username($params['username']); $password=$this->text($params['password'],72);
        if (strlen($password)<12) { throw new NativeError('password_too_short'); }
        $name=$this->text($params['displayName'],100); $device=$this->text($params['deviceName'],80);
        $this->rate([['register-ip:'.$this->ip,10,600]]);
        return $this->transaction(function() use($params,$username,$password,$name,$device) {
            $row=$this->fromEmailToken($params['token']); $this->usable($row);
            // Lock shared with email confirmation, enrollment and deletion. Legacy
            // unverified users.email/pending_email cannot reserve another address.
            if ($row['recipient_account_id']!==null || $this->verifiedMatches($row['recipient_email'])) { throw new NativeError('invitation_authentication_required',409); }
            if ($this->one('SELECT id FROM users WHERE LOWER(username)=?',[$username])) { throw new NativeError('username_unavailable',409); }
            $id=$this->userModel->create(['username'=>$username,'password'=>$password,'name'=>$name,'email'=>$row['recipient_email'],'role'=>'app-user','is_active'=>1]);
            if (!$id) { throw new NativeError('registration_failed',500); }
            $session=(new NativeAuthService($this->container))->issue($this->one('SELECT * FROM users WHERE id=?',[$id]),$device);
            $account=$session['user']['accountId'];
            $this->change('INSERT INTO familyhub_email_identities(account_id,email,verified_at,revision) VALUES(?,?,?,1)',[$account,$row['recipient_email'],time()]);
            $this->change('UPDATE familyhub_invitations SET recipient_account_id=? WHERE recipient_email=? AND recipient_account_id IS NULL',[$account,$row['recipient_email']]);
            return $session;
        },true);
    }

    private function fromEmailToken($token)
    {
        if (!is_string($token) || !preg_match('/^fhi2_[a-f0-9]{64}$/D',$token)) { throw new NativeError('invitation_invalid',404); }
        $row=$this->one('SELECT * FROM familyhub_invitations WHERE token_hash=? AND recipient_email IS NOT NULL',[hash('sha256',$token)]);
        if (!$row) { throw new NativeError('invitation_invalid',404); } return $row;
    }
    private function email($email)
    {
        $email=strtolower(trim($this->text($email,254)));
        if (!filter_var($email,FILTER_VALIDATE_EMAIL) || !preg_match('/^[\x21-\x7e]+$/D',$email)) { throw new NativeError('validation_error'); } return $email;
    }
    private function verifiedMatches($email) { return $this->many('SELECT account_id FROM familyhub_email_identities WHERE email=? AND verified_at IS NOT NULL',[$email]); }
    private function verifiedIdentity($account)
    {
        $row=$this->one('SELECT * FROM familyhub_email_identities WHERE account_id=? AND verified_at IS NOT NULL',[$account]);
        return $row && count($this->verifiedMatches($row['email']))===1?$row:null;
    }
    private function previewWire($row,$scope,$registration)
    {
        $creator=$this->one('SELECT name,username FROM users WHERE id=?',[$row['creator_id']]);
        return ['invitation'=>$this->wire($row),'scope'=>['id'=>$scope['id'],'kind'=>$scope['kind'],'name'=>$scope['name'],'projectFinanceIncluded'=>$this->projectFinanceIncluded($scope)],'inviterName'=>$creator['name']?:$creator['username'],'registrationAllowed'=>$registration,'requiresExplicitAcceptance'=>true];
    }
    public static function publicUrl($configured)
    {
        $url=defined('FAMILYHUB_PUBLIC_URL')?FAMILYHUB_PUBLIC_URL:$configured;
        $parts=is_string($url)?parse_url($url):false;
        $dev=defined('FAMILYHUB_DEVELOPMENT_ENVIRONMENT') && FAMILYHUB_DEVELOPMENT_ENVIRONMENT===true;
        if (!$parts || empty($parts['host']) || isset($parts['user']) || isset($parts['pass']) || isset($parts['query']) || isset($parts['fragment']) || (($parts['scheme']??'')!=='https' && !($dev && ($parts['scheme']??'')==='http' && in_array($parts['host'],['127.0.0.1','localhost','::1'],true)))) { throw new NativeError('email_unavailable',503); }
        return rtrim($url,'/');
    }
}
