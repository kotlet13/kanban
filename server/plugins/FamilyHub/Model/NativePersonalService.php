<?php
namespace Kanboard\Plugin\FamilyHub\Model;

/** Explicit device sync opt-in, with no new member/grant path. */
class NativePersonalService extends NativeDatabase
{
    public function execute($operation, array $params)
    {
        if ($operation !== 'personal.ensure') { throw new NativeError('unsupported_operation', 404); }
        $this->fields($params, []);
        $this->rate([['personal-ip:'.$this->ip, 120, 60]]);
        return $this->transaction(function () {
            $user = $this->actor()['user'];
            $row = $this->one('SELECT scope_id FROM familyhub_personal_scopes WHERE account_id=?', [$user['account_id']]);
            if ($row) { return ['scope' => $this->scopeWire($this->scope($row['scope_id'], $user['id'], true, true))]; }
            $id = $this->newUuid();
            $this->change('INSERT INTO familyhub_scopes(id,kind,name,owner_id,sequence,created_at) VALUES(?,\'personal\',\'Personal\',?,0,?)', [$id, $user['id'], time()]);
            $this->change('INSERT INTO familyhub_members(scope_id,user_id,account_id,role,active) VALUES(?,?,?,\'owner\',1)', [$id, $user['id'], $user['account_id']]);
            $this->change('INSERT INTO familyhub_personal_scopes VALUES(?,?)', [$user['account_id'], $id]);
            $this->change('INSERT INTO familyhub_finance_policy VALUES(?,1,1,0)', [$id]);
            $this->change('INSERT INTO familyhub_finance_grants VALUES(?,?,\'write\')', [$id, $user['account_id']]);
            return ['scope' => $this->scopeWire($this->scope($id, $user['id'], true, true))];
        }, true);
    }
}
