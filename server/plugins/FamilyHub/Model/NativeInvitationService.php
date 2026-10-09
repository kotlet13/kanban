<?php
namespace Kanboard\Plugin\FamilyHub\Model;

class NativeInvitationService extends NativeDatabase
{
    public function execute($operation, array $params)
    {
        $this->rate([['invitation-ip:'.$this->ip, 120, 60]]);
        return $this->transaction(function () use ($operation, $params) {
            if ($operation === 'invitations.preview') {
                $this->fields($params, ['token']);
                $invitation = $this->fromToken($params['token']);
                $scope = $this->usable($invitation);
                $user = $this->one('SELECT id FROM users WHERE LOWER(username)=?', [$invitation['recipient_username']]);
                return ['invitation' => $this->wire($invitation), 'scope' => ['id' => $scope['id'], 'kind' => $scope['kind'], 'name' => $scope['name'], 'projectFinanceIncluded'=>$this->projectFinanceIncluded($scope)], 'registrationAllowed' => !$user];
            }
            $actor = $this->actor(); $user = $actor['user'];
            if ($operation === 'invitations.accept') {
                $this->fields($params, ['token']);
                $invitation = $this->fromToken($params['token']);
                if (strtolower($user['username']) !== $invitation['recipient_username']) { throw new NativeError('invitation_invalid', 403); }
                if ($invitation['accepted_at'] !== null) {
                    if ($invitation['accepted_account_id'] !== $user['account_id']) { throw new NativeError('invitation_invalid', 403); }
                    return ['scope' => $this->scopeWire($this->scope($invitation['scope_id'], $user['id']))];
                }
                $scope = $this->usable($invitation);
                $this->grant($invitation, $user);
                $scope['role'] = $this->scope($scope['id'], $user['id'])['role'];
                $scope['sequence'] = $this->advance($scope);
                return ['scope' => $this->scopeWire($scope)];
            }
            if ($operation === 'invitations.create') {
                $this->fields($params, ['scopeId', 'recipientUsername', 'role', 'requestId'], ['expiresIn']);
                $scopeId = $this->uuid($params['scopeId']); $request = $this->uuid($params['requestId']);
                $scope = $this->scope($scopeId, $user['id'], true, true);
                if ($scope['kind'] === 'personal') { throw new NativeError('personal_not_shareable', 403); }
                $username = $this->username($params['recipientUsername']);
                if ($username === strtolower($user['username']) || !in_array($params['role'], ['member', 'viewer'], true)) { throw new NativeError('validation_error'); }
                $duration = $params['expiresIn'] ?? 86400;
                if (!is_int($duration) || $duration < 60 || $duration > 604800) { throw new NativeError('validation_error'); }
                $hash = $this->hashRequest($operation, $params);
                $replay = $this->replay($scopeId, $user['id'], $request, $hash);
                if ($replay) { return ['invitation' => $replay['body']['invitation'], 'token' => null]; }
                $token = 'fhi1_'.bin2hex(random_bytes(32)); $now = time();
                $row = ['id' => $this->newUuid(), 'scope_id' => $scopeId, 'recipient_username' => $username,
                        'role' => $params['role'], 'expires_at' => $now + $duration, 'accepted_at' => null, 'revoked_at' => null];
                $this->change('INSERT INTO familyhub_invitations(id,scope_id,creator_id,creator_account_id,recipient_username,role,token_hash,created_at,expires_at) VALUES(?,?,?,?,?,?,?,?,?)',
                    [$row['id'], $scopeId, $user['id'], $user['account_id'], $username, $params['role'], hash('sha256', $token), $now, $row['expires_at']]);
                $result = ['invitation' => $this->wire($row)];
                $this->remember($scopeId, $user['id'], $request, $hash, $result);
                $result['token'] = $token;
                return $result;
            }
            if ($operation === 'invitations.list') {
                $this->fields($params, ['scopeId']);
                $id = $this->uuid($params['scopeId']); $scope = $this->scope($id, $user['id'], false, true);
                if ($scope['kind'] === 'personal') { throw new NativeError('personal_not_shareable', 403); }
                return ['invitations' => array_map(fn ($row) => $this->wire($row), $this->many('SELECT * FROM familyhub_invitations WHERE scope_id=? ORDER BY created_at,id', [$id]))];
            }
            if ($operation === 'invitations.revoke') {
                $this->fields($params, ['scopeId', 'invitationId', 'requestId']);
                $scopeId = $this->uuid($params['scopeId']); $id = $this->uuid($params['invitationId']); $request = $this->uuid($params['requestId']);
                $scope = $this->scope($scopeId, $user['id'], false, true);
                if ($scope['kind'] === 'personal') { throw new NativeError('personal_not_shareable', 403); }
                $hash = $this->hashRequest($operation, $params);
                $replay = $this->replay($scopeId, $user['id'], $request, $hash);
                if ($replay) { return $replay['body']; }
                $row = $this->one('SELECT * FROM familyhub_invitations WHERE id=? AND scope_id=?', [$id, $scopeId]);
                if (!$row) { throw new NativeError('invitation_invalid', 404); }
                if ($row['accepted_at'] !== null) { throw new NativeError('invitation_already_accepted', 409); }
                $this->change('UPDATE familyhub_invitations SET revoked_at=? WHERE id=? AND accepted_at IS NULL AND revoked_at IS NULL', [time(), $id]);
                $result = ['revoked' => true]; $this->remember($scopeId, $user['id'], $request, $hash, $result);
                return $result;
            }
            throw new NativeError('unsupported_operation', 404);
        });
    }

    public function register(array $params)
    {
        $this->fields($params, ['token', 'username', 'password', 'displayName', 'deviceName']);
        $username = $this->username($params['username']);
        $password = $this->text($params['password'], 72);
        if (strlen($password) < 12) { throw new NativeError('password_too_short'); }
        $displayName = $this->text($params['displayName'], 100); $deviceName = $this->text($params['deviceName'], 80);
        $this->rate([['register-ip:'.$this->ip, 10, 600]]);
        return $this->transaction(function () use ($params, $username, $password, $displayName, $deviceName) {
            $row = $this->fromToken($params['token']);
            if ($row['recipient_username'] !== $username) { throw new NativeError('invitation_invalid', 403); }
            $scope = $this->usable($row);
            if ($this->one('SELECT id FROM users WHERE LOWER(username)=?', [$username])) { throw new NativeError('username_unavailable', 409); }
            $userId = $this->userModel->create(['username' => $username, 'password' => $password, 'name' => $displayName, 'role' => 'app-user', 'is_active' => 1]);
            if (!$userId) { throw new NativeError('registration_failed', 500); }
            $user = $this->one('SELECT * FROM users WHERE id=?', [$userId]);
            $session = (new NativeAuthService($this->container))->issue($user, $deviceName);
            $user['account_id'] = $session['user']['accountId'];
            $this->grant($row, $user);
            $this->advance($scope);
            return $session;
        }, true);
    }

    private function fromToken($token)
    {
        if (!is_string($token) || !preg_match('/^fhi1_[a-f0-9]{64}$/D', $token)) { throw new NativeError('invitation_invalid', 404); }
        $row = $this->one('SELECT * FROM familyhub_invitations WHERE token_hash=?', [hash('sha256', $token)]);
        if (!$row) { throw new NativeError('invitation_invalid', 404); }
        return $row;
    }

    private function usable(array $row)
    {
        // Scope lock serializes native accept/revoke/role removal and sequence commits.
        $scope = $this->scope($row['scope_id'], $row['creator_id'], false, true);
        if ((int)($scope['archived']??0)===1) { throw new NativeError('scope_archived',403); }
        if ($scope['kind'] === 'personal') { throw new NativeError('invitation_invalid', 404); }
        $account = $this->one('SELECT account_id FROM familyhub_accounts WHERE user_id=?', [$row['creator_id']]);
        $creator = $this->one('SELECT is_active FROM users WHERE id=?', [$row['creator_id']]);
        // Refresh invitation after waiting for the scope mutex (critical for races).
        $current = $this->one('SELECT * FROM familyhub_invitations WHERE id=?', [$row['id']]);
        if (!$account || $account['account_id'] !== $row['creator_account_id'] || !$creator || (int)$creator['is_active'] !== 1 ||
                !$current || $current['revoked_at'] !== null || $current['accepted_at'] !== null || (int)$current['expires_at'] <= time()) {
            throw new NativeError('invitation_invalid', 404);
        }
        return $scope;
    }

    private function grant(array $row, array $user)
    {
        if ($this->change('UPDATE familyhub_invitations SET accepted_at=?,accepted_by=?,accepted_account_id=? WHERE id=? AND accepted_at IS NULL AND revoked_at IS NULL AND expires_at>?',
                [time(), $user['id'], $user['account_id'], $row['id'], time()]) !== 1) { throw new NativeError('invitation_invalid', 409); }
        $writer = new NativeNotificationWriter($this->container);
        $writer->visibilityChanged([$user['account_id']]);
        $writer->insert($row['scope_id'], $user['account_id'], $row['creator_account_id'], 'membership', $user['account_id'], 1, 'member.joined', 'membership', 'personal', hash('sha256', 'join:'.$row['id']));
        $member = $this->one('SELECT * FROM familyhub_members WHERE scope_id=? AND user_id=?', [$row['scope_id'], $user['id']]);
        if (!$member) {
            $this->change('INSERT INTO familyhub_members(scope_id,user_id,account_id,role,active) VALUES(?,?,?,?,1)', [$row['scope_id'], $user['id'], $user['account_id'], $row['role']]);
        } elseif ((int)$member['active'] !== 1 || $member['account_id'] !== $user['account_id']) {
            $this->change('UPDATE familyhub_members SET account_id=?,role=?,active=1 WHERE scope_id=? AND user_id=?', [$user['account_id'], $row['role'], $row['scope_id'], $user['id']]);
        }
        (new NativeOrganizationAccess($this->container))->reconcileRevocations([$row['scope_id']],$user['account_id']);
    }

    private function projectFinanceIncluded($scope)
    {
        if (!$scope || $scope['kind']!=='project' || empty($scope['organization_id'])) { return false; }
        $organization=$this->one('SELECT access_policy_version FROM familyhub_scopes WHERE id=?',[$scope['organization_id']]);
        return (int)($organization['access_policy_version']??1)===2;
    }

    private function wire(array $row)
    {
        return ['id' => $row['id'], 'scopeId' => $row['scope_id'], 'recipientUsername' => $row['recipient_username'], 'role' => $row['role'],
                'projectFinanceIncluded'=>$this->projectFinanceIncluded($this->one('SELECT * FROM familyhub_scopes WHERE id=?',[$row['scope_id']])), 'expiresAt' => (int)$row['expires_at'], 'acceptedAt' => $row['accepted_at'] === null ? null : (int)$row['accepted_at'],
                'revokedAt' => $row['revoked_at'] === null ? null : (int)$row['revoked_at']];
    }
}
