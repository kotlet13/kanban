<?php
namespace Kanboard\Plugin\FamilyHub\Model;

/** Modern recipient invitations keep authentication separate from explicit membership acceptance. */
class NativeEmailInvitationService extends NativeInvitationService
{
    public static function available() { return NativeAccountMailCrypto::configured(); }

    public function execute($operation, array $params)
    {
        $hashOperation=$operation;
        $v3=str_starts_with($operation,'invitations3.');
        $operation=$v3 ? 'invitations2.'.substr($operation,13) : $operation;
        $this->rate([['email-invitation-ip:'.$this->ip,120,60]]);
        if ($operation==='invitations2.create') {
            $this->fields($params,['scopeId','role','requestId','language'],['recipientEmail','recipient','expiresIn','accessScope']);
            if (isset($params['recipient'])===isset($params['recipientEmail']) || (!$v3 && isset($params['recipient']))) { throw new NativeError('validation_error'); }
            $recipient=$this->text($params['recipient']??$params['recipientEmail'],254);
            $isEmail=isset($params['recipientEmail']) || str_contains($recipient,'@');
            $key=$isEmail?$this->email($recipient):$this->username($recipient);
            if ($isEmail && !self::available()) { throw new NativeError('email_unavailable',503); }
            $actor=$this->actor(false);
            $this->rate([['invite-sender:'.$actor['user']['account_id'],30,86400],['invite-recipient:'.$key,5,86400]]);
        } elseif ($operation==='invitations2.resend' && $v3) {
            $this->fields($params,['scopeId','invitationId','requestId','language'],['expiresIn']);
            $actor=$this->actor(false);
            $row=$this->one('SELECT recipient_email,recipient_username FROM familyhub_invitations WHERE id=? AND scope_id=?',[$this->uuid($params['invitationId']),$this->uuid($params['scopeId'])]);
            $key=$row?($row['recipient_email']??$row['recipient_username']):$params['invitationId'];
            $this->rate([['invite-sender:'.$actor['user']['account_id'],30,86400],['invite-recipient:'.$key,5,86400]]);
        }
        return $this->transaction(function() use($operation,$params,$v3,$hashOperation) {
            if ($operation==='invitations2.preview') {
                $this->fields($params,['token']); $row=$this->fromEmailToken($params['token']);
                if (((int)($row['invitation_contract']??1)===3)!==$v3) { throw new NativeError('client_upgrade_required',409); }
                if ($row['accepted_at']!==null && $this->bearer!=='') {
                    $user=$this->actor()['user'];
                    if ($row['accepted_account_id']!==$user['account_id']) { throw new NativeError('invitation_invalid',403); }
                    return $this->previewWire($row,$this->scope($row['scope_id'],$user['id']),false);
                }
                return $this->previewWire($row,$this->usable($row),!empty($row['recipient_email']));
            }
            $user=$this->actor()['user'];
            (new NativeModerationService($this->container,$this->bearer,$this->ip))->guardWrite($operation,$params);
            if ($operation==='invitations2.pending') {
                $this->fields($params,[]);
                $identity=$this->verifiedIdentity($user['account_id']);
                $previews=[];
                if ($identity || $v3) {
                    $rows=$this->many('SELECT * FROM familyhub_invitations WHERE ((recipient_email=? AND (recipient_account_id IS NULL OR recipient_account_id=?))'.($v3?' OR (recipient_email IS NULL AND recipient_account_id=?)':'').') AND invitation_contract'.($v3?'=3':'<>3').' AND accepted_at IS NULL AND revoked_at IS NULL AND expires_at>? ORDER BY created_at,id',$v3?[$identity['email']??'', $user['account_id'],$user['account_id'],time()]:[$identity['email'],$user['account_id'],time()]);
                    foreach ($rows as $row) {
                        try { $previews[]=$this->previewWire($row,$this->usable($row),false); }
                        catch (NativeError $error) { /* Stale issuer rights never expose a scope. */ }
                    }
                }
                return ['invitations'=>$previews];
            }
            if ($operation==='invitations2.accept') {
                if (array_keys($params)===['token']) { $row=$this->fromEmailToken($params['token']); }
                elseif (array_keys($params)===['invitationId']) { $row=$this->one('SELECT * FROM familyhub_invitations WHERE id=? AND (recipient_email IS NOT NULL OR invitation_contract=3)',[$this->uuid($params['invitationId'])]); }
                else { throw new NativeError('validation_error'); }
                if (!$row) { throw new NativeError('invitation_invalid',404); }
                if (((int)($row['invitation_contract']??1)===3)!==$v3) { throw new NativeError('client_upgrade_required',409); }
                if ($row['accepted_at']!==null) {
                    if ($row['accepted_account_id']!==$user['account_id']) { throw new NativeError('invitation_invalid',403); }
                    return ['scope'=>$this->scopeWire($this->scope($row['scope_id'],$user['id']))];
                }
                $identity=$this->verifiedIdentity($user['account_id']);
                $recipientMatches=$row['recipient_email']===null
                    ? $v3 && $row['recipient_account_id']===$user['account_id']
                    : $identity && $identity['email']===$row['recipient_email'] && ($row['recipient_account_id']===null || $row['recipient_account_id']===$user['account_id']);
                if (!$recipientMatches) { throw new NativeError('invitation_invalid',403); }
                $scope=$this->usable($row);
                $this->change('UPDATE familyhub_invitations SET recipient_account_id=? WHERE id=?',[$user['account_id'],$row['id']]);
                $this->grant($row,$user); $scope=$this->scope($scope['id'],$user['id']); $scope['sequence']=$this->advance($scope);
                return ['scope'=>$this->scopeWire($scope)];
            }
            if ($operation==='invitations2.create' || ($v3 && $operation==='invitations2.resend')) {
                $scopeId=$this->uuid($params['scopeId']); $request=$this->uuid($params['requestId']);
                $scope=$this->scope($scopeId,$user['id'],true,true);
                if ($scope['kind']==='personal') { throw new NativeError('personal_not_shareable',403); }
                $accessScope=$scope['kind']==='project'?'project':'space';
                if ($v3) { if ((int)$scope['effective_access_policy_version']!==3 || ($operation==='invitations2.create' && ($params['accessScope']??null)!==$accessScope)) { throw new NativeError('validation_error'); } }
                elseif ((int)$scope['effective_access_policy_version']===3 || isset($params['accessScope'])) { throw new NativeError('client_upgrade_required',409); }
                if (!in_array($params['language'],['sl','en'],true)) { throw new NativeError('validation_error'); }
                $duration=$params['expiresIn']??86400;
                if (!is_int($duration) || $duration<60 || $duration>604800) { throw new NativeError('validation_error'); }
                $hash=$this->hashRequest($hashOperation,$params); $replay=$this->replay($scopeId,$user['id'],$request,$hash);
                if ($replay) { return $replay['body']; }
                if ($operation==='invitations2.resend') {
                    $old=$this->one('SELECT * FROM familyhub_invitations WHERE id=? AND scope_id=?',[$this->uuid($params['invitationId']),$scopeId]);
                    if (!$old || (int)$old['invitation_contract']!==3) { throw new NativeError('invitation_invalid',404); }
                    if ($old['accepted_at']!==null) { throw new NativeError('invitation_already_accepted',409); }
                    if ($old['revoked_at']!==null) { throw new NativeError('invitation_invalid',404); }
                    $recipient=['email'=>$old['recipient_email'],'username'=>$old['recipient_username'],'account'=>$old['recipient_account_id']];
                    // Username identity is durable; never redirect a resend to a recycled name.
                    if ($recipient['email']===null && !$this->one('SELECT u.id FROM users u JOIN familyhub_accounts a ON a.user_id=u.id WHERE a.account_id=? AND u.is_active=1',[$recipient['account']])) { throw new NativeError('recipient_unavailable',409); }
                    $role=$old['role'];
                } else {
                    if (!in_array($params['role'],['member','viewer'],true)) { throw new NativeError('validation_error'); }
                    $role=$params['role']; $recipient=$this->recipient($params,$user);
                }
                $result=$this->issueInvitation($scopeId,$user,$recipient,$role,$params['language'],$duration,$v3,$accessScope);
                if (isset($old)) {
                    $this->change('UPDATE familyhub_invitations SET revoked_at=? WHERE id=?',[time(),$old['id']]);
                    $this->change("UPDATE familyhub_invitation_mail SET state='cancelled',token_cipher=NULL,lease_token=NULL WHERE invitation_id=? AND state<>'accepted'",[$old['id']]);
                }
                $this->remember($scopeId,$user['id'],$request,$hash,$result);
                return $result;
            }
            throw new NativeError('unsupported_operation',404);
        },in_array($operation,['invitations2.create','invitations2.resend'],true));
    }

    public function register(array $params, $contract=2)
    {
        $this->fields($params,['token','username','password','displayName','deviceName']);
        $username=$this->username($params['username']); $password=$this->text($params['password'],72);
        if (strlen($password)<12) { throw new NativeError('password_too_short'); }
        $name=$this->text($params['displayName'],100); $device=$this->text($params['deviceName'],80);
        $this->rate([['register-ip:'.$this->ip,10,600]]);
        return $this->transaction(function() use($params,$username,$password,$name,$device,$contract) {
            $row=$this->fromEmailToken($params['token']);
            if (((int)($row['invitation_contract']??1)===3)!==($contract===3)) { throw new NativeError('client_upgrade_required',409); }
            $this->usable($row);
            // Lock shared with email confirmation, enrollment and deletion. Legacy
            // unverified users.email/pending_email cannot reserve another address.
            if (empty($row['recipient_email']) || $row['recipient_account_id']!==null || $this->verifiedMatches($row['recipient_email'])) { throw new NativeError('invitation_authentication_required',409); }
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

    private function recipient(array $params,array $user)
    {
        $value=$this->text($params['recipient']??$params['recipientEmail'],254);
        if (isset($params['recipientEmail']) || str_contains($value,'@')) {
            $email=$this->email($value); $matches=$this->verifiedMatches($email);
            return ['email'=>$email,'username'=>'','account'=>count($matches)===1?$matches[0]['account_id']:(count($matches)>1?'ambiguous':null)];
        }
        $username=$this->username($value);
        $target=$this->one('SELECT a.account_id,u.username FROM users u JOIN familyhub_accounts a ON a.user_id=u.id WHERE LOWER(u.username)=? AND u.is_active=1',[$username]);
        if (!$target || $target['account_id']===$user['account_id']) { throw new NativeError('recipient_unavailable',409); }
        // No public directory, no core/unverified address disclosure, and no legacy registration path.
        return ['email'=>null,'username'=>strtolower($target['username']),'account'=>$target['account_id']];
    }
    private function issueInvitation($scopeId,$user,$recipient,$role,$language,$duration,$v3,$accessScope)
    {
        $email=$recipient['email'];
        if ($email!==null) {
            if (!self::available()) { throw new NativeError('email_unavailable',503); }
            self::publicUrl($this->configModel->get('application_url'));
        }
        $token=($v3?'fhi3_':'fhi2_').bin2hex(random_bytes(32)); $now=time(); $id=$this->newUuid();
        $this->change('INSERT INTO familyhub_invitations(id,scope_id,creator_id,creator_account_id,recipient_username,recipient_email,recipient_account_id,role,token_hash,created_at,expires_at) VALUES(?,?,?,?,?,?,?,?,?,?,?)',[$id,$scopeId,$user['id'],$user['account_id'],$recipient['username'],$email,$recipient['account'],$role,hash('sha256',$token),$now,$now+$duration]);
        if ($v3) { $this->change('UPDATE familyhub_invitations SET invitation_contract=3,access_scope=? WHERE id=?',[$accessScope,$id]); }
        if ($email!==null) {
            $queue=new NativeInvitationMailQueue($this->container);
            $this->change("INSERT INTO familyhub_invitation_mail(invitation_id,token_cipher,language,state,next_attempt) VALUES(?,?,?,'pending',?)",[$id,NativeAccountMailCrypto::encrypt($token,$queue->aad($id)),$language,$now]);
        }
        return ['invitation'=>$this->wire($this->one('SELECT * FROM familyhub_invitations WHERE id=?',[$id])),'deliveryQueued'=>$email!==null];
    }
    private function fromEmailToken($token)
    {
        if (!is_string($token) || !preg_match('/^fhi[23]_[a-f0-9]{64}$/D',$token)) { throw new NativeError('invitation_invalid',404); }
        $row=$this->one('SELECT * FROM familyhub_invitations WHERE token_hash=? AND (recipient_email IS NOT NULL OR invitation_contract=3)',[hash('sha256',$token)]);
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
        return ['invitation'=>$this->wire($row),'scope'=>['id'=>$scope['id'],'kind'=>$scope['kind'],'name'=>$scope['name'],'parentScopeId'=>$scope['parent_scope_id']??$scope['organization_id']??null,'parentScopeKind'=>$scope['parent_scope_kind']??null,'accessPolicyVersion'=>(int)($scope['effective_access_policy_version']??1),'projectFinanceIncluded'=>$this->projectFinanceIncluded($scope)],'inviterName'=>$creator['name']?:$creator['username'],'registrationAllowed'=>$registration,'requiresExplicitAcceptance'=>true];
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
