<?php
namespace Kanboard\Plugin\FamilyHub\Model;

/** Authenticated invitation discovery only; never returns addresses or grants access. */
class NativeRecipientSearchService extends NativeDatabase
{
    public function execute($operation, array $params)
    {
        if ($operation !== 'recipients.search') { throw new NativeError('unsupported_operation',404); }
        $this->fields($params,['scopeId','query']);
        $query=trim($this->text($params['query'],256));
        if (mb_strlen($query,'UTF-8')<2 || mb_strlen($query,'UTF-8')>64 ||
            preg_match('/[\x{0000}-\x{001f}\x{007f}-\x{009f}@]/u',$query)) {
            throw new NativeError('validation_error');
        }
        $actor=$this->actor(false);
        $this->rate([['recipient-search-account:'.$actor['user']['account_id'],60,60],['recipient-search-ip:'.$this->ip,120,60]]);
        return $this->transaction(function() use($params,$query) {
            $actor=$this->actor();
            // This endpoint exposes public recipient labels only. Its own ACL
            // and current encrypted management guard replace the content fence.
            $this->cryptoAccess=true;
            $scope=$this->scope($this->uuid($params['scopeId']),$actor['user']['id'],false,true);
            if ($scope['kind']==='personal' || (int)$scope['effective_access_policy_version']!==3 || (int)($scope['archived']??0)===1) {
                throw new NativeError('permission_revoked',403);
            }
            if (NativeCryptoV2Boundary::scope($this->pdo,$scope['id'])) {
                $scopes=new NativeCryptoScopeV2($this->container);
                $scopes->manager($scopes->current($scope['id']),$scope,$actor);
            }
            // Escape SQL wildcard characters so a query is always literal.
            $pattern='%'.strtr(mb_strtolower($query,'UTF-8'),['!'=>'!!','%'=>'!%','_'=>'!_']).'%';
            $nameExpression='LOWER(u.name)';
            if ($this->sqlite) {
                $this->pdo->sqliteCreateFunction('familyhub_recipient_fold',static fn($value)=>mb_strtolower($value??'','UTF-8'),1);
                $nameExpression='familyhub_recipient_fold(u.name)';
            }
            $rows=$this->many("SELECT a.account_id,u.username,u.name FROM users u JOIN familyhub_accounts a ON a.user_id=u.id WHERE u.is_active=1 AND u.is_ldap_user=0 AND u.disable_login_form=0 AND a.account_id<>? AND (LOWER(u.username) LIKE ? ESCAPE '!' OR $nameExpression LIKE ? ESCAPE '!') ORDER BY LOWER(u.username),a.account_id LIMIT 10",[$actor['user']['account_id'],$pattern,$pattern]);
            $result=[];
            foreach ($rows as $row) {
                if (!preg_match('/^[a-zA-Z0-9_.-]{3,64}$/D',$row['username']) || NativeCryptoAccountTombstoneV2::account($this->pdo,$row['account_id'])) { continue; }
                $result[]=['accountId'=>$row['account_id'],'username'=>$row['username'],'displayName'=>mb_substr(trim($row['name']??''),0,100,'UTF-8')];
            }
            return ['recipients'=>$result];
        });
    }
}
