<?php
namespace Kanboard\Plugin\FamilyHub\Model;

/** Server-authenticated display metadata; never cryptographic identity evidence. */
class NativeCryptoMemberLabelsV2 extends NativeDatabase
{
    protected $cryptoAccess = true;

    public function read(array $params, array $actor)
    {
        $this->fields($params, ['scopeId', 'headHash', 'accountIds']);
        $sid = $this->uuid($params['scopeId']);
        $hash = $params['headHash'];
        if (!is_string($hash) || !preg_match('/^[a-f0-9]{64}$/D', $hash)) {
            throw new NativeError('validation_error');
        }
        $ids = $params['accountIds'];
        if (!is_array($ids) || !array_is_list($ids) || count($ids) < 1 || count($ids) > 100) {
            throw new NativeError('validation_error');
        }
        $previous = '';
        foreach ($ids as $id) {
            $this->uuid($id);
            if (strcmp($id, $previous) <= 0) { throw new NativeError('validation_error'); }
            $previous = $id;
        }
        $scope = $this->scope($sid, $actor['user']['id']);
        $scopes = new NativeCryptoScopeV2($this->container, $this->bearer, $this->ip);
        $head = $scopes->current($sid);
        if (!$head || $head['head_hash'] !== $hash) {
            throw new NativeError('crypto_scope_head_changed', 409);
        }
        $body = $scopes->body($head);
        if (!$scopes->member($body, $actor['user']['account_id'])) {
            throw new NativeError('permission_revoked', 403);
        }
        if ((int)$scope['effective_access_revision'] !== $body['accessRevision']) {
            throw new NativeError('crypto_scope_head_changed', 409);
        }
        foreach ($ids as $id) {
            if (!$scopes->member($body, $id)) { throw new NativeError('permission_revoked', 403); }
        }
        $rows = $this->many('SELECT a.account_id,a.user_id,u.username,u.name FROM familyhub_accounts a JOIN users u ON u.id=a.user_id WHERE u.is_active=1 AND a.account_id IN ('.implode(',', array_fill(0, count($ids), '?')).') ORDER BY a.account_id', $ids);
        return ['version'=>1, 'serverId'=>$this->serverId(),
            'accountId'=>$actor['user']['account_id'], 'deviceId'=>$actor['device']['id'],
            'scopeId'=>$sid, 'headHash'=>$hash, 'accountIds'=>$ids,
            'labels'=>array_map(fn($row)=>['accountId'=>$row['account_id'],
                'userId'=>(int)$row['user_id'], 'username'=>$row['username'],
                'displayName'=>$row['name'] ?: $row['username']], $rows)];
    }
}
