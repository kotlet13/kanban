<?php
namespace Kanboard\Plugin\FamilyHub\Model;

/** Explicit policy acceptance and accountable reports to this server's administrators. */
class NativeModerationService extends NativeDatabase
{
    const REASONS=['harassment','hate','sexual','violence','illegal','spam','privacy','other'];
    public function policy()
    {
        return ['contractVersion'=>1,'serverId'=>$this->serverId(),'policyVersion'=>1,'title'=>'Pravila skupne vsebine / Shared content rules',
            'textSl'=>'Pred objavo skupne vsebine morate izrecno sprejeti ta pravila za ta strežnik. Prepovedani so nadlegovanje in grožnje, sovražni govor, spolno eksplicitna vsebina in golota, spolno izkoriščanje (zlasti otrok), nasilna ali nezakonita vsebina, neželena pošta ter objava osebnih podatkov brez upravičenja. Objavite le vsebino, za katero imate pravico do deljenja. Vsebino ali vidnega člana lahko prijavite brez sprejema pravil. Pred oddajo vidite točne podatke, ki jih prejme skrbnik tega strežnika; prijava ni javna in se ne pošlje TriparNA samodejno. Skrbnik pregleda prijavo, lahko odstrani skupno vsebino ali omeji dostop do skupnega prostora. Prijava sama ne izbriše vsebine. Finančna zgodovina se ne briše. Osebna lokalna uporaba in zasebna osebna sinhronizacija ne zahtevata sprejema teh pravil.',
            'textEn'=>'Before publishing shared content, explicitly accept these rules for this server. Harassment and threats, hate speech, sexually explicit content and nudity, sexual exploitation (especially of children), violent or illegal content, spam, and unauthorized disclosure of personal information are prohibited. Share only content you have the right to share. You may report content or a visible member without accepting the rules. Before submission you see the exact evidence sent to this server administrator; reports are private and are not automatically sent to TriparNA. The administrator reviews reports and may remove shared content or restrict shared space access. A report alone does not delete content. Financial history is preserved. Local personal use and private personal synchronization do not require acceptance.',
            'recipient'=>$this->recipient(),'prohibitedCategories'=>self::REASONS,'reportRetentionDays'=>180];
    }
    private function recipient() { return ['kind'=>'serverAdministrator','name'=>'FamilyHub server administrator']; }
    public function guardWrite($operation,array $params)
    {
        $parts=explode('.',$operation);$group=$parts[0];$action=$parts[1]??'';
        $mutating=($group==='scopes' && in_array($action,['create','updateMetadata','setLeader','accessMigrationApply','projectSharingApply'],true)) ||
            (in_array($group,['invitations','invitations2','invitations3'],true) && $action==='create') ||
            (in_array($group,['sync','sync2','sync3','sync4','sync5'],true) && in_array($action,['push','pushTaskWithCost'],true)) ||
            (in_array($group,['finance','finance2'],true) && in_array($action,['push','enable','grant'],true)) ||
            ($group==='finance3' && in_array($action,['paymentCommit','paymentReimburse'],true)) ||
            ($group==='reminders' && in_array($action,['put'],true));
        if ($group==='ideas' && $action==='asset' && in_array($parts[2]??'', ['begin','chunk','complete'],true)) { $mutating=true; }
        if (!$mutating) { return; }
        $user=$this->actor(false)['user'];
        if (isset($params['scopeId'])) {
            $scope=$this->scope($this->uuid($params['scopeId']),$user['id']);
            if ($scope['kind']==='personal') { return; }
        }
        if (!$this->one('SELECT account_id FROM familyhub_policy_acceptances WHERE account_id=? AND policy_version=1',[$user['account_id']])) {
            throw new NativeError('policy_acceptance_required',403,['policyVersion'=>1,'serverId'=>$this->serverId()]);
        }
    }
    private function status($user)
    {
        $row=$this->one('SELECT accepted_at FROM familyhub_policy_acceptances WHERE account_id=? AND policy_version=1',[$user['account_id']]);
        return ['serverId'=>$this->serverId(),'accountId'=>$user['account_id'],'policyVersion'=>1,'accepted'=>(bool)$row,'acceptedAt'=>$row?gmdate('Y-m-d\TH:i:s\Z',(int)$row['accepted_at']):null];
    }
    public function execute($operation,array $params)
    {
        if ($operation==='moderation.policy') { $this->fields($params,[]);return $this->policy(); }
        $this->rate([['moderation-ip:'.$this->ip,300,60]]);
        $user=$this->actor(false)['user'];
        $this->rate([['moderation-account:'.$user['account_id'],120,60]]);
        if ($operation==='moderation.report') { $this->rate([['moderation-report:'.$user['account_id'],20,3600]]); }
        return $this->transaction(function()use($operation,$params){
            $user=$this->actor()['user'];
            if ($operation==='moderation.policyStatus') { $this->fields($params,[]);return $this->status($user); }
            if ($operation==='moderation.acceptPolicy') {
                $this->fields($params,['policyVersion']);if ($params['policyVersion']!==1) { throw new NativeError('unsupported_version',409); }
                if (!$this->status($user)['accepted']) { $this->change('INSERT INTO familyhub_policy_acceptances VALUES(?,1,?)',[$user['account_id'],time()]); }
                return $this->status($user);
            }
            if ($operation==='moderation.reportPreview') { $this->fields($params,['scopeId','targetType','targetId']);return $this->preview($params,$user); }
            if ($operation!=='moderation.report') { throw new NativeError('unsupported_operation',404); }
            $this->fields($params,['requestId','scopeId','targetType','targetId','previewHash','reason','details']);
            $request=$this->uuid($params['requestId']);$this->text($params['details'],2000,true);
            if (!in_array($params['reason'],self::REASONS,true) || !is_string($params['previewHash']) || !preg_match('/^[a-f0-9]{64}$/D',$params['previewHash'])) { throw new NativeError('validation_error'); }
            $hash=$this->hashRequest($operation,$params);
            // Recheck scope authorization even for a replay; never disclose another account receipt.
            $scope=$this->scope($this->uuid($params['scopeId']),$user['id']);
            if ($scope['kind']==='personal') { throw new NativeError('personal_not_shareable',403); }
            $saved=$this->one('SELECT * FROM familyhub_moderation_reports WHERE reporter_account_id=? AND request_id=?',[$user['account_id'],$request]);
            if ($saved) {
                if (!hash_equals($hash,$saved['request_hash'])) { throw new NativeError('idempotency_mismatch',409); }
                return $this->receipt($saved);
            }
            $preview=$this->preview($params,$user);
            if (!hash_equals($preview['previewHash'],$params['previewHash'])) { throw new NativeError('report_preview_changed',409); }
            $id=$this->newUuid();$created=time();
            $this->change('INSERT INTO familyhub_moderation_reports(id,reporter_account_id,request_id,request_hash,scope_id,target_type,target_id,target_revision,preview_hash,reason,details,snapshot,created_at,status) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?)',[$id,$user['account_id'],$request,$hash,$scope['id'],$params['targetType'],$params['targetId'],$preview['targetRevision'],$preview['previewHash'],$params['reason'],$params['details'],$this->canonical($preview),$created,'submitted']);
            if (($preview['subject']['type']??'')==='idea') { (new NativeIdeaAssetService($this->container))->retainReport($id,$scope['id'],$params['targetId'],$preview['evidence']['assets']); }
            return $this->receipt(['id'=>$id,'created_at'=>$created]);
        },true);
    }
    private function receipt($row) { return ['reportId'=>$row['id'],'status'=>'submitted','createdAt'=>gmdate('Y-m-d\TH:i:s\Z',(int)$row['created_at']),'serverId'=>$this->serverId()]; }
    private function preview($params,$user)
    {
        $scopeId=$this->uuid($params['scopeId']);$target=$this->uuid($params['targetId']);$kind=$params['targetType'];
        if (!in_array($kind,['record','finance','user'],true)) { throw new NativeError('validation_error'); }
        $scope=$this->scope($scopeId,$user['id']);if ($scope['kind']==='personal') { throw new NativeError('personal_not_shareable',403); }
        if ($kind==='user') {
            $member=null;foreach ((new NativeOrganizationAccess($this->container))->members($scopeId) as $candidate) { if ($candidate['accountId']===$target) { $member=$candidate;break; } }
            if (!$member) { throw new NativeError('report_target_unavailable',404); }
            $evidence=['accountId'=>$target,'displayName'=>mb_strcut($member['displayName'],0,200,'UTF-8'),'username'=>mb_strcut($member['username'],0,64,'UTF-8'),'role'=>$member['role']];$title=$member['displayName'];$type='user';$revision=(int)$scope['effective_access_revision'];
        } else {
            if ($kind==='finance') { (new NativeFinanceAccess($this->container))->policy($scopeId,$user,false,true); }
            $table=$kind==='finance'?'familyhub_finance_records':'familyhub_records';
            $row=$this->one('SELECT * FROM '.$table.' WHERE scope_id=? AND id=?',[$scopeId,$target]);
            if (!$row || (int)$row['deleted']===1) { throw new NativeError('report_target_unavailable',404); }
            $payload=json_decode($row['payload'],true,32,JSON_THROW_ON_ERROR);$type=$row['type'];$revision=(int)$row['revision'];$title=(string)($payload['title']??$payload['name']??$type);
            // Bounded single-entry text only: no attachments, related entries or private payment graph.
            $evidence=['id'=>$target,'type'=>$type,'revision'=>$revision];
            if ($type==='idea' && !NativeIdeaAssetService::available()) { throw new NativeError('ideas_unavailable',503); }
            if ($type==='idea') { $evidence=['id'=>$target,'type'=>$type,'revision'=>$revision,'board'=>$payload,'assets'=>(new NativeIdeaAssetService($this->container))->evidence($scopeId,$target,$payload)]; }
            foreach (['title','name','notes','description'] as $field) { if (is_string($payload[$field]??null)) { $evidence[$field]=mb_strcut($payload[$field],0,$field==='notes'||$field==='description'?2000:200,'UTF-8'); } }
        }
        $preview=['serverId'=>$this->serverId(),'accountId'=>$user['account_id'],'scopeId'=>$scopeId,'targetType'=>$kind,'targetId'=>$target,'targetRevision'=>$revision,'subject'=>['title'=>mb_strcut($title,0,200,'UTF-8'),'type'=>$type],'evidence'=>$evidence,'recipient'=>$this->recipient()];
        $preview['previewHash']=hash('sha256',$this->canonical($preview));return $preview;
    }
    /** Resolved/dismissed evidence is retained 180 days after resolution; open reports remain for review. */
    public function purgeExpired()
    {
        return $this->transaction(function(){
            $ids=array_column($this->many('SELECT id FROM familyhub_moderation_reports WHERE resolved_at IS NOT NULL AND resolved_at<=? AND redacted_at IS NULL ORDER BY resolved_at,id LIMIT 100',[time()-180*86400]),'id');
            foreach ($ids as $id) {
                $this->change('UPDATE familyhub_moderation_reports SET snapshot=NULL,details=NULL,redacted_at=? WHERE id=?',[time(),$id]);
                $this->change('DELETE FROM familyhub_idea_report_assets WHERE report_id=?',[$id]);
                $this->change("UPDATE familyhub_moderation_audit SET note='[Retention expired]' WHERE report_id=?",[$id]);
            }
            return count($ids);
        },true);
    }
}
