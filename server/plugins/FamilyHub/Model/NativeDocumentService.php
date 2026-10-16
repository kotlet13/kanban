<?php
namespace Kanboard\Plugin\FamilyHub\Model;

/** Shared authenticated receipts. Lease tokens are never stored in response snapshots. */
abstract class NativeDocumentService extends NativeDatabase
{
    public function available() { return \Kanboard\Plugin\FamilyHub\Schema\DocumentsSchema::ready($this->pdo); }
    protected function receipt($scope,$actor,$request,$hash)
    {
        $r=$this->one('SELECT * FROM familyhub_document_requests WHERE scope_id=? AND account_id=? AND device_id=? AND request_id=?',[$scope,$actor['user']['account_id'],$actor['device']['id'],$request]);
        if (!$r) { return null; }
        if (!hash_equals($r['request_hash'],$hash)) { throw new NativeError('idempotency_mismatch',409); }
        return json_decode($r['response'],true,32,JSON_THROW_ON_ERROR);
    }
    protected function rememberDocument($scope,$actor,$request,$hash,$id,$response)
    {
        $this->change('INSERT INTO familyhub_document_requests VALUES(?,?,?,?,?,?,?)',[$scope,$actor['user']['account_id'],$actor['device']['id'],$request,$id,$hash,json_encode($response,JSON_UNESCAPED_UNICODE|JSON_THROW_ON_ERROR)]);
    }
    protected function documentGate()
    {
        if (!$this->available()) { throw new NativeError('feature_disabled',503); }
        $this->rate([['documents-ip:'.$this->ip,1200,60]]);
        $actor=$this->actor(false);$this->rate([['documents-account:'.$actor['user']['account_id'],900,60]]);
    }
}
