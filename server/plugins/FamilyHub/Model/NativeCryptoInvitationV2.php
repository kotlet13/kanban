<?php

namespace Kanboard\Plugin\FamilyHub\Model;

/** Recipient-bound pending intents. Accepting an invitation never activates SQL membership. */
class NativeCryptoInvitationV2 extends NativeDatabase
{
    protected $cryptoAccess = true;
    private $legacyBridgeHelper;
    protected function bridgeHelper() { return $this->legacyBridgeHelper ??= new NativeCryptoMigrationInvitationStageV3($this->container); }

    public static function token($token)
    {
        if (!is_string($token) || !preg_match('/^fhi[1234]_[a-f0-9]{64}$/D', $token)) {
            throw new NativeError('invitation_invalid', 404);
        }
        return $token;
    }

    /** The inviter knows the token: only an independent email code verifies its recipient. */
    public function register(array $params)
    {
        if (!NativeCryptoService::enabled($this->pdo) || !NativeAccountMailCrypto::configured()) { throw new NativeError('crypto_unavailable',503); }
        $this->fields($params,['token','username','password','displayName','deviceName']);
        $username=$this->username($params['username']);$password=$this->text($params['password'],72);
        if (strlen($password)<12) { throw new NativeError('password_too_short'); }
        $name=$this->text($params['displayName'],100);$deviceName=$this->text($params['deviceName'],80);
        $this->rate([['crypto-register-ip:'.$this->ip,10,600]]);
        return $this->transaction(function()use($params,$username,$password,$name,$deviceName){
            $row=$this->tokenInvitation($params['token']);
            if ($row['recipient_kind']!=='email' || $row['recipient_account_id']!==null || $this->one('SELECT account_id FROM familyhub_email_identities WHERE email=? AND verified_at IS NOT NULL',[$row['recipient_value']])) { throw new NativeError('invitation_authentication_required',409); }
            if ($this->one('SELECT id FROM users WHERE LOWER(username)=?',[$username])) { throw new NativeError('username_unavailable',409); }
            $userId=$this->userModel->create(['username'=>$username,'password'=>$password,'name'=>$name,'role'=>'app-user','is_active'=>1]);
            if (!$userId) { throw new NativeError('registration_failed',500); }
            $user=$this->one('SELECT * FROM users WHERE id=?',[$userId]);
            $session=(new NativeAuthService($this->container))->issue($user,$deviceName);
            $user['account_id']=$session['user']['accountId'];
            $this->change('INSERT INTO familyhub_email_identities(account_id,pending_email,revision) VALUES(?,?,1)',[$user['account_id'],$row['recipient_value']]);
            (new NativeAccountTokens($this->container))->issue($user,'verify',$row['recipient_value'],1,$row['language']);
            return $session+['emailVerificationRequired'=>true,'pendingEmail'=>$row['recipient_value']];
        },true);
    }

    protected function recipient($value)
    {
        $value = $this->text($value, 254);
        if (str_contains($value, '@')) {
            $email = strtolower(trim($value));
            if (!filter_var($email, FILTER_VALIDATE_EMAIL)) {
                throw new NativeError('validation_error');
            }
            return ['kind' => 'email','value' => $email,'accountId' => null];
        }
        $username = $this->username($value);
        $user = $this->one('SELECT a.account_id FROM users u JOIN familyhub_accounts a ON a.user_id=u.id WHERE LOWER(u.username)=? AND u.is_active=1', [$username]);
        if (!$user || NativeCryptoAccountTombstoneV2::account($this->pdo,$user['account_id'])) {
            throw new NativeError('recipient_unavailable', 409);
        }
        return ['kind' => 'username','value' => $username,'accountId' => $user['account_id']];
    }

    protected function matches($row, $actor)
    {
        if ($row['recipient_kind'] === 'username') {
            return $row['recipient_account_id'] === $actor['user']['account_id'];
        }
        $identity = $this->one('SELECT email,verified_at FROM familyhub_email_identities WHERE account_id=?', [$actor['user']['account_id']]);
        return $identity && $identity['verified_at'] !== null && $identity['email'] === $row['recipient_value'] && ($row['recipient_account_id'] === null || $row['recipient_account_id'] === $actor['user']['account_id']);
    }

    public function usable($row)
    {
        if (!$row || !in_array($row['state'], ['pending','accepted'], true) || (int)$row['expires_at'] <= time()) {
            throw new NativeError('invitation_invalid', 404);
        }
        $user = $this->one('SELECT a.account_id,u.* FROM familyhub_accounts a JOIN users u ON u.id=a.user_id WHERE a.account_id=? AND u.is_active=1', [$row['creator_account_id']]);
        if (!$user) {
            throw new NativeError('invitation_invalid', 404);
        }
        $scope = $this->scope($row['scope_id'], $user['id']);
        if ((int)$scope['archived'] || $scope['kind'] === 'personal') {
            throw new NativeError('invitation_invalid', 404);
        }
        $scopes = new NativeCryptoScopeV2($this->container);
        $head = $scopes->current($scope['id']);
        if (!$head) {
            throw new NativeError('invitation_invalid', 404);
        }
        $actor = ['user' => $user,'device' => ['id' => $row['creator_device_id']]];
        $scopes->manager($head, $scope, $actor);
        [$command] = NativeCryptoCodec::decode(json_decode($row['authorization'], true, 34, JSON_THROW_ON_ERROR));
        $scopes->currentAuthorReference($command['payload']['authorDirectoryHeadHash'], $actor);
        if ($command['operation']==='crypto2.invitations.bridgeLegacy') {
            $bridge=$this->bridgeEvidence($row);
            if ($bridge===null) throw new NativeError('crypto_invitation_bridge_pending',409);
            if ($bridge['legacyAccepted'] || $bridge['legacyRevoked']) throw new NativeError('invitation_invalid',404);
        }
        return $scope;
    }

    protected function bridgeEvidence($row)
    {
        [$creator]=NativeCryptoCodec::decode(json_decode($row['authorization'],true,34,JSON_THROW_ON_ERROR));
        return $creator['operation']==='crypto2.invitations.bridgeLegacy'
            ? $this->bridgeHelper()->retained($row['token_hash']) : null;
    }

    protected function invitation($id)
    {
        $row = $this->one('SELECT * FROM familyhub_crypto_invitations_v2 WHERE id=?', [$this->uuid($id)]);
        if (!$row) {
            throw new NativeError('invitation_invalid', 404);
        }
        return $row;
    }

    private function tokenInvitation($token)
    {
        $row = $this->one('SELECT * FROM familyhub_crypto_invitations_v2 WHERE token_hash=?', [hash('sha256', self::token($token))]);
        if (!str_starts_with($token,'fhi4_') && !$this->bridgeHelper()->retained(hash('sha256',$token))) { throw new NativeError('invitation_invalid',404); }
        $this->usable($row);
        return $row;
    }

    public function publicRead($op, $p, $actor = null)
    {
        $this->fields($p, [], ['token','invitationId','afterGeneration','afterHash','limit','bridgeActivation']);
        if(isset($p['bridgeActivation'])&&($p['bridgeActivation']!==true||$op!=='crypto2.invitations.directory'))throw new NativeError('validation_error');
        if (isset($p['token']) === isset($p['invitationId'])) {
            throw new NativeError('validation_error');
        }
        $retainedRecipient = false;
        $acceptance = null;
        if (isset($p['token'])) {
            $row = $this->tokenInvitation($p['token']);
        } else {
            if (!$actor) {
                throw new NativeError('auth_required', 401);
            }
            $row = $this->invitation($p['invitationId']);
            // A consumed link grants no public preview or renewed admission.
            // Its exact recipient may still verify the original scoped admission.
            $acceptance = $this->consumedRecipientProof($row, $actor);
            $retainedRecipient = $row && $row['state'] === 'consumed'
                && $row['recipient_account_id'] === $actor['user']['account_id']
                && ($this->bridgeEvidence($row) !== null
                    || $acceptance !== null && !isset($p['bridgeActivation'])
                        && in_array($op, ['crypto2.invitations.preview','crypto2.invitations.directory'], true));
            if (!$retainedRecipient) {
                $this->usable($row);
                if (!$this->matches($row, $actor)) {
                    throw new NativeError('invitation_invalid', 403);
                }
            }
        }
        if ($op==='crypto2.invitations.bridgeDigests') {
            return $this->bridgeHelper()->digestPage($row['token_hash'],$p['afterHash']??null,$p['limit']??20);
        }
        if(isset($p['bridgeActivation'])){
            $reference=$this->bridgeHelper()->activationDirectoryReference($row['token_hash']);
            return $this->directoryPrefix($reference['accountId'],$reference['headHash'],$p['afterGeneration']??0,$p['limit']??50);
        }
        $prefix = $this->creatorDirectory($row, $p['afterGeneration'] ?? 0, $p['limit'] ?? 50);
        if ($op === 'crypto2.invitations.directory') {
            return $prefix;
        }
        if ($acceptance === null && $actor && $row['recipient_account_id'] === $actor['user']['account_id']
            && in_array($row['state'], ['accepted','consumed'], true)) {
            $entry = $this->one("SELECT authorization FROM familyhub_crypto_invitation_acceptances_v2 WHERE invitation_id=? AND account_id=? AND state IN ('accepted','consumed') ORDER BY created_at DESC,proof_hash DESC LIMIT 1", [$row['id'],$actor['user']['account_id']]);
            if ($entry) $acceptance = json_decode($entry['authorization'],true,34,JSON_THROW_ON_ERROR);
        }
        return $this->preview($row, $prefix, $retainedRecipient, $acceptance);
    }

    /** Original proof lookup only: no token reuse, pending capability, or renewed admission. */
    private function consumedRecipientProof($row, $actor)
    {
        if ($row['state'] !== 'consumed' || $row['recipient_account_id'] !== $actor['user']['account_id']) return null;
        $creation = json_decode($row['authorization'], true, 34, JSON_THROW_ON_ERROR);
        [$creator] = NativeCryptoCodec::decode($creation);
        if (!in_array($creator['operation'], ['crypto2.invitations.create','crypto2.invitations.resend'], true)) return null;
        $entry = $this->one("SELECT proof_hash,device_id,authorization FROM familyhub_crypto_invitation_acceptances_v2 WHERE invitation_id=? AND account_id=? AND state IN ('accepted','consumed') ORDER BY created_at DESC,proof_hash DESC LIMIT 1", [$row['id'],$actor['user']['account_id']]);
        if (!$entry) return null;
        $proof = json_decode($entry['authorization'], true, 34, JSON_THROW_ON_ERROR);
        [$accepted] = NativeCryptoCodec::decode($proof);
        $payload = $accepted['payload'];
        if ($accepted['operation'] !== 'crypto2.invitations.accept'
            || $accepted['serverId'] !== $creator['serverId']
            || $accepted['accountId'] !== $actor['user']['account_id']
            || $accepted['deviceId'] !== $entry['device_id']
            || $payload['invitationId'] !== $row['id'] || $payload['scopeId'] !== $row['scope_id']
            || $payload['tokenHash'] !== $row['token_hash']
            || $payload['creatorProofHash'] !== NativeCryptoV2Codec::hash((object)$creation)
            || $payload['role'] !== $row['role'] || $payload['expiresAt'] !== (int)$row['expires_at']
            || $payload['membershipHeadHash'] !== $creator['payload']['membershipHeadHash']
            || NativeCryptoV2Codec::hash((object)$proof) !== $entry['proof_hash']) return null;
        return $proof;
    }

    private function creatorDirectory($row, $after, $limit)
    {
        [$creator]=NativeCryptoCodec::decode(json_decode($row['authorization'],true,34,JSON_THROW_ON_ERROR));
        $reference=$creator['operation']==='crypto2.invitations.bridgeLegacy'
            ? (new NativeCryptoDirectoryV2($this->container))->current($row['creator_account_id'])['head_hash']
            : $creator['payload']['authorDirectoryHeadHash'];
        return $this->directoryPrefix($row['creator_account_id'],$reference,$after,$limit);
    }

    protected function directoryPrefix($account,$hash,$after,$limit)
    {
        if (!is_int($after) || $after < 0 || !is_int($limit) || $limit < 1 || $limit > 50) {
            throw new NativeError('invalid_cursor');
        }
        $head = $this->one('SELECT generation,head_hash,snapshot_hash,device_snapshot_hash,identity_epoch_id FROM familyhub_crypto_directory WHERE account_id=? AND head_hash=?', [$account,$hash]);
        if (!$head || $after > (int)$head['generation']) {
            throw new NativeError('crypto_directory_head_missing', 409);
        }
        $rows = $this->many('SELECT generation,head_hash,previous_head_hash,command_hash,authorization FROM familyhub_crypto_directory WHERE account_id=? AND generation>? AND generation<=? ORDER BY generation LIMIT '.($limit + 1), [$account,$after,$head['generation']]);
        $out = [];
        $bytes = 0;
        foreach ($rows as $entry) {
            $item = ['generation' => (int)$entry['generation'],'headHash' => $entry['head_hash'],'previousHeadHash' => $entry['previous_head_hash'],'commandHash' => $entry['command_hash'],'authorization' => json_decode($entry['authorization'], true, 34, JSON_THROW_ON_ERROR)];
            $size = strlen(json_encode($item, JSON_THROW_ON_ERROR));
            if (count($out) === $limit || $out && $bytes + $size > 1100000) {
                break;
            }
            $out[] = $item;
            $bytes += $size;
        }
        return ['serverId' => $this->serverId(),'accountId' => $account,'generation' => (int)$head['generation'],'headHash' => $head['head_hash'],'snapshotHash' => $head['snapshot_hash'],'deviceSnapshotHash' => $head['device_snapshot_hash'],'identityEpochId' => $head['identity_epoch_id'],'entries' => $out,'hasMore' => count($rows) > count($out),'nextGeneration' => $out ? end($out)['generation'] : $after];
    }

    private function preview($row, $prefix = null, $retainedRecipient = false, $recipientAcceptance = null)
    {
        $scope = $retainedRecipient ? $this->one('SELECT * FROM familyhub_scopes WHERE id=?', [$row['scope_id']]) : $this->usable($row);
        if (!$scope) throw new NativeError('invitation_invalid',404);
        $prepared=new NativeCryptoInvitationPreauthorizationV5($this->container);$publication=$prepared->binding($row)?$prepared->publication($row['id']):null;
        return $this->inviterDisplay($row)+($recipientAcceptance===null?[]:['recipientAcceptanceAuthorization'=>$recipientAcceptance])+($publication?['preauthorizationHeadHash'=>$publication['head_hash'],'publicationAuthorization'=>json_decode($publication['authorization'],true,34,JSON_THROW_ON_ERROR)]:[])+['invitation' => $this->wire($row),'scope' => ['id' => $scope['id'],'kind' => $scope['kind'],'name' => 'Encrypted space','projectFinanceIncluded' => (int)($scope['effective_access_policy_version']??$scope['access_policy_version']??1) >= 2],'registrationAllowed' => $row['recipient_kind'] === 'email'&&$row['recipient_account_id']===null,'creatorAuthorization' => json_decode($row['authorization'], true, 34, JSON_THROW_ON_ERROR),'creatorDirectory' => $prefix ?? $this->creatorDirectory($row, 0, 50),'candidateHeads' => $this->candidateHeads($row)]+($this->bridgeEvidence($row)===null?[]:['legacyBridge'=>$this->bridgeEvidence($row)]);
    }

    /** Host display metadata only. The scope title and domain keys stay private. */
    private function inviterDisplay($row)
    {
        $creator = $this->one('SELECT a.account_id,u.username,u.name,e.email AS verified_email FROM familyhub_accounts a JOIN users u ON u.id=a.user_id LEFT JOIN familyhub_email_identities e ON e.account_id=a.account_id AND e.verified_at IS NOT NULL WHERE a.account_id=? AND u.is_active=1', [$row['creator_account_id']]);
        if (!$creator || !is_string($creator['username']) || $creator['username']==='' || strlen($creator['username'])>100 || preg_match('/[\x00-\x1f\x7f]/', $creator['username'])) return [];
        $name = $creator['name'] ?: $creator['username'];
        if (!is_string($name) || strlen($name)>200 || preg_match('/[\x00-\x1f\x7f]/', $name)) $name=$creator['username'];
        $display = ['inviterAccountId'=>$creator['account_id'],'inviterUsername'=>$creator['username'],'inviterName'=>$name];
        $email = $creator['verified_email'];
        if (is_string($email) && strlen($email)<=254 && preg_match('/^[\x21-\x7e]+$/D',$email) && filter_var($email,FILTER_VALIDATE_EMAIL)) $display['inviterEmail']=$email;
        return $display;
    }

    private function candidateHeads($row)
    {
        if ($row['state'] !== 'accepted') {
            return [];
        }
        $scopes = new NativeCryptoScopeV2($this->container);
        $scopes->refreshPending($row['scope_id'], $scopes->current($row['scope_id']));
        $heads = $this->many("SELECT head_hash,payload FROM familyhub_crypto_scope_heads WHERE scope_id=? AND state='pending' ORDER BY epoch,head_hash LIMIT 16", [$row['scope_id']]);
        $out = [];
        foreach ($heads as $head) {
            $body = json_decode($head['payload'], true, 34, JSON_THROW_ON_ERROR);
            foreach ($body['membershipIntents'] ?? [] as $intent) {
                if ($intent['invitationId'] === $row['id'] && $intent['accountId'] === $row['recipient_account_id']) {
                    $out[] = ['headHash' => $head['head_hash'],'acceptanceProofHash' => $intent['acceptanceProofHash']];
                }
            }
        }
        return $out;
    }

    private function wire($row)
    {
        return ['id' => $row['id'],'scopeId' => $row['scope_id'],'role' => $row['role'],'expiresAt' => gmdate('Y-m-d\TH:i:s\Z', (int)$row['expires_at']),'expiresAtEpoch' => (int)$row['expires_at'],'state' => $row['state'],'recipient' => ['kind' => $row['recipient_kind'],'value' => $row['recipient_value'],'accountId' => $row['recipient_account_id']],'createdAt' => gmdate('Y-m-d\TH:i:s\Z', (int)$row['created_at']),'contractVersion' => 4,'tokenHash' => $row['token_hash'],'creatorProofHash' => NativeCryptoV2Codec::hash((object)json_decode($row['authorization'], true, 34, JSON_THROW_ON_ERROR))]+((new NativeCryptoInvitationPreauthorizationV5($this->container))->binding($row)?['admissionMode'=>'preauthorized']:[])+(($legacy=$this->bridgeEvidence($row))===null?[]:['legacyAcceptedAtEpoch'=>$legacy['legacyAcceptedAtEpoch'],'legacyRevokedAtEpoch'=>$legacy['legacyRevokedAtEpoch']]);
    }

    public function write($op, $p, $actor, $proof, $deliveryToken = null)
    {
        if($op==='crypto2.invitations.publishPreauthorization')return (new NativeCryptoInvitationPreauthorizationV5($this->container,$this->bearer,$this->ip))->publish($p,$actor,$proof);
        if ($op === 'crypto2.invitations.accept') {
            return $this->accept($p, $actor, $proof);
        }
        $scopes = new NativeCryptoScopeV2($this->container, $this->bearer, $this->ip);
        $sid = $this->uuid($p['scopeId'] ?? null);
        $scope = $this->scope($sid, $actor['user']['id']);
        $current = $scopes->current($sid);
        $scopes->manager($current, $scope, $actor);
        NativeCryptoScopeCreationV2::guardBusiness($this->pdo, $sid);
        if (!$current || $scope['kind'] === 'personal') {
            throw new NativeError('personal_not_shareable', 403);
        }
        if (($p['membershipHeadHash'] ?? null) !== $current['head_hash'] || ($p['expectedAccessRevision'] ?? null) !== (int)$scope['effective_access_revision']) {
            throw new NativeError('crypto_access_changed', 409);
        }
        $scopes->currentAuthorReference($p['authorDirectoryHeadHash'] ?? null, $actor);
        if ($op === 'crypto2.invitations.revoke') {
            $this->fields($p, ['scopeId','invitationId','membershipHeadHash','expectedAccessRevision','authorDirectoryHeadHash']);
            $row = $this->invitation($p['invitationId']);
            if ($row['scope_id'] !== $sid) {
                throw new NativeError('invitation_invalid', 404);
            }
            if ($row['state'] === 'consumed') {
                throw new NativeError('invitation_already_accepted', 409);
            }
            $this->cancel($row['id'], 'revoked');
            return ['revoked' => true];
        }
        $optional=['preauthorization'];if($op==='crypto2.invitations.resend')$optional[]='replacesInvitationId';
        $this->fields($p, ['scopeId','invitationId','recipient','role','expiresAt','language','expectedAccessRevision','membershipHeadHash','authorDirectoryHeadHash','tokenHash'], $optional);
        if (!in_array($op, ['crypto2.invitations.create','crypto2.invitations.resend'], true) || !is_array($p['recipient'])) {
            throw new NativeError('validation_error');
        }
        $this->fields($p['recipient'], ['kind','value','accountId']);
        $prepared=new NativeCryptoInvitationPreauthorizationV5($this->container);
        $recipient = isset($p['preauthorization'])?$prepared->resolveRecipient($p['recipient']['value']):$this->recipient($p['recipient']['value']);
        if(isset($p['preauthorization']))$prepared->validateCreation($p,$scope,$recipient);
        if (NativeCryptoCodec::canonical((object)$recipient) !== NativeCryptoCodec::canonical((object)$p['recipient']) || $recipient['accountId'] === $actor['user']['account_id'] || !in_array($p['role'], ['member','viewer'], true) || !in_array($p['language'], ['sl','en'], true) || !is_int($p['expiresAt']) || $p['expiresAt'] < time() + 60 || $p['expiresAt'] > time() + 604800 || !is_string($p['tokenHash']) || !preg_match('/^[0-9a-f]{64}$/D', $p['tokenHash'])) {
            throw new NativeError('validation_error');
        }
        if ($deliveryToken !== null && !hash_equals($p['tokenHash'], hash('sha256', self::token($deliveryToken)))) {
            throw new NativeError('invitation_token_mismatch', 403);
        }
        if ($recipient['kind'] === 'email' && ($deliveryToken === null || !NativeAccountMailCrypto::configured())) {
            throw new NativeError('email_unavailable', 503);
        }
        $id = $this->uuid($p['invitationId']);
        if ($this->one('SELECT id FROM familyhub_crypto_invitations_v2 WHERE id=? OR token_hash=?', [$id,$p['tokenHash']])) {
            throw new NativeError('invitation_immutable', 409);
        }
        $old = null;
        if ($op === 'crypto2.invitations.resend') {
            $old = $this->invitation($p['replacesInvitationId'] ?? null);
            if ($old['scope_id'] !== $sid || $old['state'] === 'consumed' || $old['state'] === 'revoked' || $old['recipient_kind'] !== $recipient['kind'] || $old['recipient_value'] !== $recipient['value'] || $old['recipient_account_id'] !== $recipient['accountId'] || $old['role'] !== $p['role']) {
                throw new NativeError('invitation_invalid', 409);
            }
        }
        // The enclosing global transaction serializes successful invitation creation.
        // Transport IP limits cover denied attempts; no nested SQL transaction.
        $senderCount = $this->one('SELECT COUNT(*) AS n FROM familyhub_crypto_invitations_v2 WHERE creator_account_id=? AND created_at>?', [$actor['user']['account_id'],time() - 86400]);
        $recipientCount = $this->one('SELECT COUNT(*) AS n FROM familyhub_crypto_invitations_v2 WHERE recipient_value=? AND created_at>?', [$recipient['value'],time() - 86400]);
        if ((int)$senderCount['n'] >= 30 || (int)$recipientCount['n'] >= 5) {
            throw new NativeError('rate_limited', 429, ['retryAfter' => 86400]);
        }
        $this->change('INSERT INTO familyhub_crypto_invitations_v2 VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,NULL)', [$id,$sid,$actor['user']['account_id'],$actor['device']['id'],$recipient['kind'],$recipient['value'],$recipient['accountId'],$p['role'],$p['tokenHash'],time(),$p['expiresAt'],'pending',json_encode($proof, JSON_THROW_ON_ERROR),$p['language']]);
        if ($recipient['kind'] === 'email') {
            $this->change("INSERT INTO familyhub_crypto_invitation_mail_v2(invitation_id,token_cipher,language,state,next_attempt) VALUES(?,?,?,?,?)", [$id,NativeAccountMailCrypto::encrypt($deliveryToken, $this->aad($id)),$p['language'],isset($p['preauthorization'])?'held':'pending',time()]);
        }
        if ($old) {
            $this->cancel($old['id'], 'revoked');
            $this->change('UPDATE familyhub_crypto_invitations_v2 SET replaced_by=? WHERE id=?', [$id,$old['id']]);
        }
        return ['invitation' => $this->wire($this->invitation($id)),'token' => null];
    }

    private function accept($p, $actor, $proof)
    {
        $this->fields($p, ['scopeId','invitationId','tokenHash','creatorProofHash','role','expiresAt','membershipHeadHash','authorDirectoryHeadHash'],['preauthorizationHeadHash']);
        $row = $this->invitation($p['invitationId']);
        $scope = $this->usable($row);
        $prepared=new NativeCryptoInvitationPreauthorizationV5($this->container);$preauthorization=$prepared->binding($row);
        if(!$preauthorization&&isset($p['preauthorizationHeadHash']))throw new NativeError('validation_error');
        $creation = json_decode($row['authorization'], true, 34, JSON_THROW_ON_ERROR);
        [$command] = NativeCryptoCodec::decode($creation);
        if ($row['scope_id'] !== $p['scopeId'] || !$this->matches($row, $actor) || $row['token_hash'] !== $p['tokenHash'] || $p['creatorProofHash'] !== NativeCryptoV2Codec::hash((object)$creation) || $p['role'] !== $row['role'] || $p['expiresAt'] !== (int)$row['expires_at'] || $p['membershipHeadHash'] !== ($command['payload']['context']['membershipHeadHash']??$command['payload']['membershipHeadHash'])) {
            throw new NativeError('invitation_invalid', 403);
        }
        $scopes = new NativeCryptoScopeV2($this->container);
        $scopes->currentAuthorReference($p['authorDirectoryHeadHash'], $actor);
        $current = (new NativeCryptoDirectoryV2($this->container))->current($actor['user']['account_id']);
        $snapshot = json_decode($current['snapshot'], true, 34, JSON_THROW_ON_ERROR);
        $hash = NativeCryptoV2Codec::hash((object)$proof);
        if (!$this->one('SELECT proof_hash FROM familyhub_crypto_invitation_acceptances_v2 WHERE invitation_id=? AND proof_hash=?', [$row['id'],$hash])) {
            $this->change('INSERT INTO familyhub_crypto_invitation_acceptances_v2 VALUES(?,?,?,?,?,?,?,?,?,?,?)', [$row['id'],$hash,$actor['user']['account_id'],$actor['device']['id'],$snapshot['rootSigningKeyBase64'],$snapshot['rootEncryptionKeyBase64'],$snapshot['identityEpochId'],$p['authorDirectoryHeadHash'],json_encode($proof, JSON_THROW_ON_ERROR),time(),'accepted']);
        }
        $this->change("UPDATE familyhub_crypto_invitations_v2 SET state='accepted',recipient_account_id=? WHERE id=?", [$actor['user']['account_id'],$row['id']]);
        $this->change("UPDATE familyhub_crypto_invitation_mail_v2 SET state='cancelled',token_cipher=NULL,lease_token=NULL WHERE invitation_id=? AND state<>'accepted'", [$row['id']]);
        $activation=$preauthorization?$prepared->acceptPrepared($row,$p,$actor,$hash):[];
        return $activation+['scope' => ['id' => $scope['id'],'kind' => $scope['kind'],'name' => 'Encrypted space','role' => $row['role']],'state' => 'pendingKeys','invitationId' => $row['id'],'acceptanceProofHash' => $hash,'candidateHeads' => []];
    }

    private function cancel($id, $state)
    {
        $this->change('UPDATE familyhub_crypto_invitations_v2 SET state=? WHERE id=?', [$state,$id]);
        $this->change("UPDATE familyhub_crypto_invitation_mail_v2 SET state='cancelled',token_cipher=NULL,lease_token=NULL WHERE invitation_id=? AND state<>'accepted'", [$id]);
    }

    /** Preview a new direct member without publishing membership or side effects. */
    protected function proposedMember($scopeId,$accepted,$role)
    {
        $account=$accepted['account_id'];
        $user=$this->one('SELECT a.account_id,u.* FROM familyhub_accounts a JOIN users u ON u.id=a.user_id WHERE a.account_id=? AND u.is_active=1',[$account]);
        if (!$user) { throw new NativeError('crypto_invitation_recipient_changed',409); }
        $this->pdo->exec('SAVEPOINT crypto2_invitation_role_preview');
        try {
            $existing=$this->one('SELECT user_id FROM familyhub_members WHERE scope_id=? AND user_id=?',[$scopeId,$user['id']]);
            if($existing){$this->change('UPDATE familyhub_members SET account_id=?,role=?,active=1 WHERE scope_id=? AND user_id=?',[$account,$role,$scopeId,$user['id']]);}
            else{$this->change('INSERT INTO familyhub_members(scope_id,user_id,account_id,role,active) VALUES(?,?,?,?,1)',[$scopeId,$user['id'],$account,$role]);}
            $scope=$this->scope($scopeId,$user['id']);
            $policy=(new NativeFinanceAccess($this->container))->policyForCrypto($scopeId,$user,false,false);
            return ['accountId'=>$account,'role'=>$scope['role'],'financeRole'=>$policy['enabled']?$policy['grant']:'none','manageKeys'=>$scope['role']==='owner'||(int)$scope['effective_access_policy_version']===3&&$scope['role']==='member'];
        } finally {
            $this->pdo->exec('ROLLBACK TO SAVEPOINT crypto2_invitation_role_preview');
            $this->pdo->exec('RELEASE SAVEPOINT crypto2_invitation_role_preview');
        }
    }

    public function read($op, $p, $actor)
    {
        if($op==='crypto2.invitations.resolvePreauthorization')return (new NativeCryptoInvitationPreauthorizationV5($this->container))->resolve($p,$actor);
        if ($op==='crypto2.invitations.status') {
            $this->fields($p,['invitationId']);
            $row=$this->invitation($p['invitationId']);
            if ($row['state']!=='consumed' || !$this->matches($row,$actor)) { throw new NativeError('invitation_invalid',403); }
            $scope=$this->scope($row['scope_id'],$actor['user']['id']);
            $acceptances=$this->many("SELECT proof_hash FROM familyhub_crypto_invitation_acceptances_v2 WHERE invitation_id=? AND account_id=? AND state='consumed'",[$row['id'],$actor['user']['account_id']]);
            $hashes=array_column($acceptances,'proof_hash');
            $publication=(new NativeCryptoInvitationPreauthorizationV5($this->container))->publication($row['id']);
            if($publication&&$hashes){
                $accepted=$this->one("SELECT authorization FROM familyhub_crypto_invitation_acceptances_v2 WHERE invitation_id=? AND proof_hash=? AND account_id=? AND state='consumed'",[$row['id'],$hashes[0],$actor['user']['account_id']]);
                return ['state'=>'consumed','admissionMode'=>'preauthorized','invitationId'=>$row['id'],'acceptanceProofHash'=>$hashes[0],'recipientAcceptanceAuthorization'=>json_decode($accepted['authorization'],true,34,JSON_THROW_ON_ERROR),'activatedHeadHash'=>$publication['head_hash'],'scope'=>['id'=>$scope['id'],'kind'=>$scope['kind'],'role'=>$scope['role'],'name'=>'Encrypted space']];
            }
            $heads=$this->many('SELECT head_hash,payload FROM familyhub_crypto_scope_heads WHERE scope_id=? AND activation_authorization IS NOT NULL AND payload LIKE ? ORDER BY epoch DESC LIMIT 2',[$row['scope_id'],'%'.$row['id'].'%']);
            foreach($heads as $head){
                $body=json_decode($head['payload'],true,34,JSON_THROW_ON_ERROR);
                foreach($body['membershipIntents'] as $intent){
                    if($intent['invitationId']===$row['id'] && $intent['accountId']===$actor['user']['account_id'] && in_array($intent['acceptanceProofHash'],$hashes,true)){
                        return ['state'=>'consumed','invitationId'=>$row['id'],'acceptanceProofHash'=>$intent['acceptanceProofHash'],'activatedHeadHash'=>$head['head_hash'],'scope'=>['id'=>$scope['id'],'kind'=>$scope['kind'],'role'=>$scope['role'],'name'=>'Encrypted space']];
                    }
                }
            }
            throw new NativeError('crypto_invitation_activation_unavailable',503);
        }

        if ($op==='crypto2.invitations.acceptance') {
            $this->fields($p,['scopeId','invitationId'],['afterGeneration','limit','acceptanceProofHash']);
            $scope=$this->scope($this->uuid($p['scopeId']),$actor['user']['id']);
            $scopes=new NativeCryptoScopeV2($this->container);$scopes->manager($scopes->current($scope['id']),$scope,$actor);
            $row=$this->invitation($p['invitationId']);$this->usable($row);
            if ($row['scope_id']!==$scope['id']||$row['state']!=='accepted') { throw new NativeError('crypto_invitation_acceptance_required',409); }
            $accepted=$this->one("SELECT * FROM familyhub_crypto_invitation_acceptances_v2 WHERE invitation_id=? AND state='accepted'".(isset($p['acceptanceProofHash'])?' AND proof_hash=?':'').' ORDER BY created_at DESC,proof_hash DESC LIMIT 1',isset($p['acceptanceProofHash'])?[$row['id'],$p['acceptanceProofHash']]:[$row['id']]);
            if (!$accepted) { throw new NativeError('crypto_invitation_acceptance_required',409); }
            $current=(new NativeCryptoDirectoryV2($this->container))->current($accepted['account_id']);
            $snapshot=$current?json_decode($current['snapshot'],true,34,JSON_THROW_ON_ERROR):null;
            if (!$snapshot) { throw new NativeError('crypto_member_directory_pending',409); }
            $member=['accountId'=>$accepted['account_id'],'rootSigningKeyBase64'=>$snapshot['rootSigningKeyBase64'],'rootEncryptionKeyBase64'=>$snapshot['rootEncryptionKeyBase64'],'identityEpochId'=>$snapshot['identityEpochId'],'role'=>$row['role']];
            $this->intent($scope['id'],['invitationId'=>$row['id'],'acceptanceProofHash'=>$accepted['proof_hash']],$member);
            return ['acceptanceProofHash'=>$accepted['proof_hash'],'authorization'=>json_decode($accepted['authorization'],true,34,JSON_THROW_ON_ERROR),'recipientDirectory'=>$this->directoryPrefix($accepted['account_id'],$current['head_hash'],$p['afterGeneration']??0,$p['limit']??50),'proposedMember'=>$this->proposedMember($scope['id'],$accepted,$row['role'])];
        }

        if ($op === 'crypto2.invitations.resolve') {
            $this->fields($p, ['scopeId','recipient']);
            $scope = $this->scope($this->uuid($p['scopeId']), $actor['user']['id']);
            $scopes = new NativeCryptoScopeV2($this->container);
            $scopes->manager($scopes->current($scope['id']), $scope, $actor);
            return ['recipient' => $this->recipient($p['recipient'])];
        }
        if (in_array($op, ['crypto2.invitations.preview','crypto2.invitations.directory','crypto2.invitations.bridgeDigests'], true)) {
            return $this->publicRead($op, $p, $actor);
        }
        $list = $op === 'crypto2.invitations.list';
        $this->fields($p, $list ? ['scopeId'] : [], $list ? ['afterId','limit'] : ['afterId','limit']);
        $limit = $p['limit'] ?? 50;
        $after = isset($p['afterId']) ? $this->uuid($p['afterId']) : '';
        if (!is_int($limit) || $limit < 1 || $limit > 50) {
            throw new NativeError('invalid_cursor');
        }
        if ($list) {
            $scope = $this->scope($this->uuid($p['scopeId']), $actor['user']['id']);
            $scopes = new NativeCryptoScopeV2($this->container);
            $scopes->manager($scopes->current($scope['id']), $scope, $actor);
            $rows = $this->many('SELECT * FROM familyhub_crypto_invitations_v2 WHERE scope_id=? AND id>? ORDER BY id LIMIT '.($limit + 1), [$scope['id'],$after]);
        } else {
            $identity = $this->one('SELECT email FROM familyhub_email_identities WHERE account_id=? AND verified_at IS NOT NULL', [$actor['user']['account_id']]);
            $rows = $this->many("SELECT * FROM familyhub_crypto_invitations_v2 WHERE id>? AND state IN ('pending','accepted') AND expires_at>? AND ((recipient_kind='username' AND recipient_account_id=?) OR (recipient_kind='email' AND recipient_value=? AND (recipient_account_id IS NULL OR recipient_account_id=?))) ORDER BY id LIMIT ".($limit + 1), [$after,time(),$actor['user']['account_id'],$identity['email'] ?? '',$actor['user']['account_id']]);
        }
        $out = [];
        $scanned = [];
        $bytes = 0;
        foreach (array_slice($rows, 0, $limit) as $row) {
            try {
                $wire = $list ? $this->wire($row) : $this->preview($row);
            } catch (NativeError $e) {
                if (!in_array($e->errorCode, ['invitation_invalid','permission_revoked','crypto_device_unapproved','crypto_member_directory_changed'], true)) {
                    throw $e;
                }$scanned[] = $row['id'];
                continue;
            }
            $size = strlen(json_encode($wire, JSON_THROW_ON_ERROR));
            if ($out && $bytes + $size > 1250000) {
                break;
            }$scanned[] = $row['id'];
            $out[] = $wire;
            $bytes += $size;
        }
        return ['invitations' => $out,'hasMore' => count($rows) > count($scanned),'nextAfterId' => $scanned ? end($scanned) : null];
    }

    public function intent($scopeId, $intent, $member)
    {
        $row = $this->invitation($intent['invitationId']);
        $this->usable($row);
        $acceptance = $this->one("SELECT * FROM familyhub_crypto_invitation_acceptances_v2 WHERE invitation_id=? AND proof_hash=? AND state='accepted'", [$row['id'],$intent['acceptanceProofHash']]);
        if (!$acceptance || $row['scope_id'] !== $scopeId || $row['state'] !== 'accepted' || $acceptance['account_id'] !== $member['accountId'] || $row['recipient_account_id'] !== $member['accountId'] || $row['role'] !== $member['role'] || $acceptance['root_signing_key'] !== $member['rootSigningKeyBase64'] || $acceptance['root_encryption_key'] !== $member['rootEncryptionKeyBase64'] || $acceptance['identity_epoch_id'] !== $member['identityEpochId']) {
            throw new NativeError('crypto_invitation_acceptance_required', 409);
        }
        $current = (new NativeCryptoDirectoryV2($this->container))->current($member['accountId']);
        $snapshot = $current ? json_decode($current['snapshot'], true, 34, JSON_THROW_ON_ERROR) : null;
        $device = $snapshot ? (new NativeCryptoDirectoryV2($this->container))->device($snapshot, $acceptance['device_id']) : null;
        if (!$device || $device['revokedGeneration'] !== null || $device['identityEpochId'] !== $snapshot['identityEpochId'] || $snapshot['rootSigningKeyBase64'] !== $acceptance['root_signing_key'] || $snapshot['rootEncryptionKeyBase64'] !== $acceptance['root_encryption_key'] || $snapshot['identityEpochId'] !== $acceptance['identity_epoch_id']) {
            throw new NativeError('crypto_invitation_recipient_changed', 409);
        }
        $user = $this->one('SELECT user_id FROM familyhub_accounts WHERE account_id=?', [$member['accountId']]);
        return ['accountId' => $member['accountId'],'userId' => (int)$user['user_id'],'role' => $row['role'],'invitationId' => $row['id'],'acceptanceProofHash' => $acceptance['proof_hash']];
    }

    public function capability($sid, $cap, $actor)
    {
        if (!is_array($cap)) {
            throw new NativeError('permission_revoked', 403);
        }
        $this->fields($cap, ['invitationId','acceptanceProofHash','candidateHeadHash']);
        $row = $this->invitation($cap['invitationId']);
        $this->usable($row);
        if ($row['scope_id'] !== $sid || !$this->matches($row, $actor)) {
            throw new NativeError('permission_revoked', 403);
        }
        $scopes = new NativeCryptoScopeV2($this->container);
        $current = $scopes->current($sid);
        $scopes->refreshPending($sid, $current);
        $candidate = $scopes->head($sid, $cap['candidateHeadHash']);
        if ($candidate['state'] !== 'pending' || $candidate['previous_head_hash'] !== ($current['head_hash'] ?? NativeCryptoDirectoryV2::ZERO)) {
            throw new NativeError('permission_revoked', 403);
        }
        $body = $scopes->body($candidate);
        $member = $scopes->member($body, $actor['user']['account_id']);
        $found = false;
        if (!$member) {
            throw new NativeError('permission_revoked', 403);
        }
        foreach ($body['membershipIntents'] as $intent) {
            if ($intent['accountId'] === $actor['user']['account_id'] && $intent['invitationId'] === $row['id'] && $intent['acceptanceProofHash'] === $cap['acceptanceProofHash']) {
                $this->intent($sid, $intent, $member);
                $found = true;
            }
        }
        $acceptance = $this->one('SELECT device_id FROM familyhub_crypto_invitation_acceptances_v2 WHERE invitation_id=? AND proof_hash=?', [$row['id'],$cap['acceptanceProofHash']]);
        if (!$found || !$member || !$acceptance || $acceptance['device_id'] !== $actor['device']['id']) {
            throw new NativeError('permission_revoked',403);
        }
        return ['member' => $member,'candidate' => $candidate];
    }

    public function replayAccess($p,$actor)
    {
        $row = $this->invitation($p['invitationId'] ?? null);
        if (!$this->matches($row,$actor) || $row['scope_id'] !== ($p['scopeId'] ?? null)) {
            throw new NativeError('permission_revoked',403);
        }
    }

    public function consume($intent)
    {
        $this->change("UPDATE familyhub_crypto_invitation_acceptances_v2 SET state='consumed' WHERE invitation_id=? AND proof_hash=?",[$intent['invitationId'],$intent['acceptanceProofHash']]);
        $this->change("UPDATE familyhub_crypto_invitations_v2 SET state='consumed' WHERE id=?",[$intent['invitationId']]);
    }

    public function aad($id)
    {
        return $this->serverId().':crypto2-invitation:'.$id;
    }
}
