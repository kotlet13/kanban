<?php
namespace Kanboard\Plugin\FamilyHub\Model;

class NativeInboxGroup extends NativeDatabase
{
    public function page(array $params,array $user)
    {
        $this->fields($params,['id'],['beforeId','limit']);
        $limit=$params['limit'] ?? 100; $before=$params['beforeId'] ?? PHP_INT_MAX;
        if (!is_int($params['id']) || $params['id']<1 || !is_int($before) || $before<1 || !is_int($limit) || $limit<1 || $limit>100) { throw new NativeError('validation_error'); }
        $anchor=$this->one('SELECT * FROM familyhub_inbox WHERE id=? AND recipient_account_id=?',[$params['id'],$user['account_id']]);
        if (!$anchor) { throw new NativeError('permission_revoked',403); }
        $this->scope($anchor['scope_id'],$user['id']);
        if ($this->financialRecordType($anchor['target_type'])) { (new NativeFinanceAccess($this->container))->policy($anchor['scope_id'],$user); }
        $rows=$this->many('SELECT * FROM familyhub_inbox WHERE recipient_account_id=? AND scope_id=? AND group_key=? AND kind=? AND category=? AND audience=? AND id<=? AND id<? ORDER BY id DESC LIMIT '.($limit+1),[$user['account_id'],$anchor['scope_id'],$anchor['group_key'],$anchor['kind'],$anchor['category'],$anchor['audience'],$anchor['id'],$before]);
        $page=array_slice($rows,0,$limit); $more=count($rows)>$limit;
        return ['items'=>array_map([new NativeInboxService($this->container),'wire'],$page),'hasMore'=>$more,'nextBeforeId'=>$more ? (int)end($page)['id'] : null];
    }
}
