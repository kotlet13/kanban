<?php
namespace Kanboard\Plugin\FamilyHub\Model;

/** Web administrator only. No broad native bearer privilege or financial mutation. */
class NativeModerationAdminService extends NativeDatabase
{
    private function admin($id)
    {
        $user=$this->one('SELECT id,role,is_active FROM users WHERE id=?'.$this->lockSuffix(),[$id]);
        if (!$user || $user['role']!=='app-admin' || (int)$user['is_active']!==1) { throw new NativeError('permission_revoked',403); }
    }
    public function reports($adminId,$page=0)
    {
        $this->admin($adminId);$page=max(0,min(100000,(int)$page));
        $rows=$this->many('SELECT * FROM familyhub_moderation_reports ORDER BY created_at DESC,id LIMIT 26 OFFSET '.($page*25));
        foreach ($rows as &$row) { $snapshot=$row['snapshot']===null?[]:json_decode($row['snapshot'],true,32,JSON_THROW_ON_ERROR);$row['ideaImage']=isset($snapshot['evidence']['board']);$row['ideaAssets']=$snapshot['evidence']['assets']??[];$row['ideaTexts']=[];foreach($snapshot['evidence']['board']['elements']??[] as $element){if(is_string($element['text']??null)&&$element['text']!=='')$row['ideaTexts'][]=$element['text'];}$row['audit']=$this->many('SELECT admin_id,action,note,created_at,review_revision FROM familyhub_moderation_audit WHERE report_id=? ORDER BY review_revision DESC LIMIT 50',[$row['id']]); }unset($row);
        return ['reports'=>array_slice($rows,0,25),'page'=>$page,'hasNext'=>count($rows)>25];
    }
    public function board($adminId,$reportId)
    {
        $this->admin($adminId);$this->uuid($reportId);if(!NativeIdeaAssetService::available()){throw new NativeError('ideas_unavailable',503);}$r=$this->one('SELECT * FROM familyhub_moderation_reports WHERE id=? AND redacted_at IS NULL AND snapshot IS NOT NULL',[$reportId]);
        if(!$r){throw new NativeError('report_target_unavailable',404);}$image=(new NativeIdeaRenderer($this->container))->reportImage($r);
        if($image===null){throw new NativeError('report_target_unavailable',404);}return ['mime'=>'image/png','bytes'=>base64_decode(explode(',',$image,2)[1])];
    }
    /** Full immutable report photo; web APP_ADMIN/TLS remains required by controller. */
    public function asset($adminId,$reportId,$sha)
    {
        $this->admin($adminId);$this->uuid($reportId);
        if (!is_string($sha) || !preg_match('/^[a-f0-9]{64}$/D',$sha)) { throw new NativeError('validation_error'); }
        $r=$this->one('SELECT a.* FROM familyhub_idea_assets a JOIN familyhub_idea_report_assets ar ON ar.scope_id=a.scope_id AND ar.board_id=a.board_id AND ar.sha256=a.sha256 JOIN familyhub_moderation_reports r ON r.id=ar.report_id WHERE r.id=? AND a.sha256=? AND r.redacted_at IS NULL AND r.snapshot IS NOT NULL',[$reportId,$sha]);
        if (!$r && \Kanboard\Plugin\FamilyHub\Schema\CryptoSchema::ready($this->pdo)) {
            $selected = $this->one("SELECT s.* FROM familyhub_crypto_moderation_stages_v2 s JOIN familyhub_moderation_reports r ON r.id=s.report_id WHERE s.report_id=? AND s.sha256=? AND s.kind='asset' AND s.included=1 AND s.complete=1 AND r.redacted_at IS NULL AND r.snapshot IS NOT NULL", [$reportId,$sha]);
            if ($selected) {
                return ['mime' => $selected['mime'],'bytes' => (new NativeCryptoModerationDisclosureV2($this->container))->bytes($selected)];
            }
        }
        if (!$r) { throw new NativeError('report_target_unavailable',404); }
        return ['mime'=>$r['mime'],'bytes'=>(new NativeIdeaAssetService($this->container))->bytes($r)];
    }
    public function review($adminId,array $params)
    {
        $this->fields($params,['reportId','reviewRevision','targetRevision','action','note'],['confirmation']);
        if (in_array($params['action'],['remove_content','restrict_member','unrestrict_member'],true) && ($params['confirmation']??null)!=='APPLY') { throw new NativeError('confirmation_required',422); }
        $id=$this->uuid($params['reportId']);$note=$this->text($params['note'],2000);
        if (!is_int($params['reviewRevision']) || !is_int($params['targetRevision']) || !in_array($params['action'],['reviewed','resolved','dismissed','remove_content','restrict_member','unrestrict_member'],true)) { throw new NativeError('validation_error'); }
        return $this->transaction(function()use($adminId,$params,$id,$note){
            $this->admin($adminId);$report=$this->one('SELECT * FROM familyhub_moderation_reports WHERE id=?'.$this->lockSuffix(),[$id]);
            if (!$report) { throw new NativeError('report_target_unavailable',404); }
            $mutating = in_array($params['action'], ['remove_content','restrict_member','unrestrict_member'], true);
            $cryptoReport = \Kanboard\Plugin\FamilyHub\Schema\CryptoSchema::ready($this->pdo) &&
                $this->one('SELECT report_id FROM familyhub_crypto_moderation_reports_v2 WHERE report_id=?', [$id]);
            if ($mutating && !$cryptoReport) { NativeCryptoFence::guard($this->pdo,$report['scope_id']); }
            if ((int)$report['review_revision']!==$params['reviewRevision']) { throw new NativeError('review_changed',409); }
            if ($report['redacted_at']!==null && in_array($params['action'],['remove_content','restrict_member'],true)) { throw new NativeError('report_evidence_expired',409); }
            $scope=$this->one('SELECT * FROM familyhub_scopes WHERE id=?'.$this->lockSuffix(),[$report['scope_id']]);
            if ($mutating && !$cryptoReport) { NativeCryptoFence::guard($this->pdo,$report['scope_id']); }
            if (in_array($params['action'],['remove_content','restrict_member'],true)) {
                if (!$scope || $scope['kind']==='personal') { throw new NativeError('report_target_unavailable',404); }
                if ($params['targetRevision']!==(int)$report['target_revision']) { throw new NativeError('report_preview_changed',409); }
            }
            if ($params['action']==='remove_content') {
                if ($cryptoReport) {
                    (new NativeCryptoModerationAvailabilityV2($this->container))->removeContent($report, $params['targetRevision']);
                } elseif (in_array($report['target_type'],['table','attachment'],true)) {
                    $service=$report['target_type']==='table'?new NativeTableService($this->container):new NativeAttachmentService($this->container);
                    try { $current=$service->moderationEvidence($scope,$report['target_id']); } catch (NativeError $e) { throw new NativeError('report_preview_changed',409); }
                    $snapshot=json_decode($report['snapshot'],true,32,JSON_THROW_ON_ERROR);
                    if ($current['revision']!==$params['targetRevision'] || !hash_equals($snapshot['evidence']['documentHash']??'',$current['documentHash'])) { throw new NativeError('report_preview_changed',409); }
                    $service->removeInTransaction($scope['id'],$report['target_id']);
                } else {
                    if ($report['target_type']!=='record') { throw new NativeError('financial_history_preserved',403); }
                    $record=$this->one('SELECT * FROM familyhub_records WHERE scope_id=? AND id=?',[$scope['id'],$report['target_id']]);
                    if (!$record || (int)$record['revision']!==$params['targetRevision'] || (int)$record['deleted']===1) { throw new NativeError('report_preview_changed',409); }
                    // Preserve project structure and any dependencies; remove the reported text only when needed.
                    $structural=($scope['project_root_id']??null)===$record['id'];
                    try { (new NativeRecordPolicy($this->container))->noChildren($scope['id'],$record['id'],$record['type']); }
                    catch (NativeError $error) { if ($error->errorCode!=='live_children') { throw $error; }$structural=true; }
                    $sequence=$this->advance($scope);$stamp=gmdate('Y-m-d\TH:i:s\Z');
                    if ($structural) {
                        $payload=json_decode($record['payload'],true,32,JSON_THROW_ON_ERROR);
                        foreach (['title','name'] as $field) { if (isset($payload[$field])) { $payload[$field]='[Content removed by administrator]'; } }
                        foreach (['notes','description'] as $field) { if (isset($payload[$field])) { $payload[$field]=''; } }
                        $this->change('UPDATE familyhub_records SET payload=?,revision=revision+1,sequence=?,updated_at=?,updated_by=NULL WHERE scope_id=? AND id=?',[$this->canonical($payload),$sequence,$stamp,$scope['id'],$record['id']]);
                        if (($scope['project_root_id']??null)===$record['id']) { $this->change('UPDATE familyhub_scopes SET name=?,metadata_revision=metadata_revision+1 WHERE id=?',['[Content removed by administrator]',$scope['id']]); }
                    } else { $this->change('UPDATE familyhub_records SET deleted=1,payload=NULL,revision=revision+1,sequence=?,updated_at=?,updated_by=NULL WHERE scope_id=? AND id=?',[$sequence,$stamp,$scope['id'],$record['id']]); }
                    if (!$structural && $record['type']==='task') { (new NativeAttachmentService($this->container))->removeTarget($scope['id'],'task',$record['id']); }
                    $this->change("UPDATE familyhub_reminders SET state='cancelled',revision=revision+1 WHERE scope_id=? AND target_id=? AND target_type=? AND state='pending'",[$scope['id'],$record['id'],$record['type']]);
                    $accounts=array_column((new NativeOrganizationAccess($this->container))->members($scope['id']),'accountId');
                    (new NativeNotificationWriter($this->container))->visibilityChanged($accounts);
                }
            }
            if ($params['action']==='restrict_member') {
                if ($report['target_type']!=='user') { throw new NativeError('validation_error'); }
                $member=(new NativeOrganizationAccess($this->container))->visibleScope($scope['id'],$report['target_id']);
                if (!$member || (int)$member['effective_access_revision']!==$params['targetRevision']) { throw new NativeError('report_preview_changed',409); }
                (new NativeMembershipRevocation($this->container))->apply($scope,$report['target_id'],null,true);
            }
            if ($params['action']==='unrestrict_member') {
                if (!$scope || $scope['kind']==='personal' || $report['target_type']!=='user' || !$this->one('SELECT scope_id FROM familyhub_moderation_blocks WHERE scope_id=? AND account_id=?',[$scope['id'],$report['target_id']])) { throw new NativeError('report_target_unavailable',404); }
                (new NativeMembershipRevocation($this->container))->undoModeration($scope,$report['target_id']);
            }
            $status=in_array($params['action'],['remove_content','restrict_member','resolved'],true)?'resolved':($params['action']==='unrestrict_member'?'reviewed':$params['action']);$revision=(int)$report['review_revision']+1;
            $resolved=in_array($status,['resolved','dismissed'],true)?time():null;
            $this->change('UPDATE familyhub_moderation_reports SET status=?,review_revision=?,resolved_at=? WHERE id=?',[$status,$revision,$resolved,$id]);
            $this->change('INSERT INTO familyhub_moderation_audit VALUES(?,?,?,?,?,?,?)',[$this->newUuid(),$id,$adminId,$params['action'],$note,time(),$revision]);
            return ['reportId'=>$id,'status'=>$status,'reviewRevision'=>$revision];
        },true);
    }
}
