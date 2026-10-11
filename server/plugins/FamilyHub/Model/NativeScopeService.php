<?php
namespace Kanboard\Plugin\FamilyHub\Model;

class NativeScopeService extends NativeDatabase
{
    public function execute($operation, array $params)
    {
        if (in_array($operation, ['scopes.list', 'scopes.members'], true)) {
            // Household devices share a NAT address. Reads have an individual
            // account budget as well as a broader pre-authentication IP envelope.
            $this->rate([['scopes-read-ip:'.$this->ip, 2400, 60]]);
            $actor = $this->actor(false);
            $this->rate([['scopes-read-account:'.$actor['user']['account_id'], 600, 60]]);
        } else {
            $this->rate([['scopes-ip:'.$this->ip, 120, 60]]);
        }
        return $this->transaction(function () use ($operation, $params) {
            $actor = $this->actor(); $user = $actor['user'];
            if (in_array($operation,['scopes.setLeader','scopes.accessMigrationPreview','scopes.accessMigrationApply'],true)) { return (new NativeSpacesAccessService($this->container))->inTransaction($operation,$params,$user); }
            if (in_array($operation,['scopes.projectSharingPreview','scopes.projectSharingApply'],true)) { return (new NativeProjectSharingService($this->container))->inTransaction($operation,$params,$user); }
            if ($operation === 'scopes.list') {
                $this->fields($params, [], ['includePersonal', 'includeOrganizations','includeArchived','includeAccessChanges']);
                $includePersonal = $params['includePersonal'] ?? false;
                $includeOrganizations = $params['includeOrganizations'] ?? false;
                $includeArchived=$params['includeArchived']??false;
                if (isset($params['includeAccessChanges']) && !is_bool($params['includeAccessChanges'])) { throw new NativeError('validation_error'); }
                if (!is_bool($includeArchived)) { throw new NativeError('validation_error'); }
                if (!is_bool($includeOrganizations)) { throw new NativeError('validation_error'); }
                if (!is_bool($includePersonal)) { throw new NativeError('validation_error'); }
                $rows = $this->many('SELECT s.*,m.role FROM familyhub_scopes s LEFT JOIN familyhub_members m ON s.id=m.scope_id AND m.user_id=? AND m.account_id=? AND m.active=1 WHERE m.scope_id IS NOT NULL OR EXISTS (SELECT 1 FROM familyhub_members om JOIN familyhub_scopes o ON o.id=om.scope_id LEFT JOIN familyhub_organization_leaders l ON l.scope_id=o.id AND l.account_id=om.account_id WHERE (o.id=s.parent_scope_id OR o.id=s.organization_id) AND om.user_id=? AND om.account_id=? AND om.active=1 AND (o.access_policy_version=3 OR (o.access_policy_version=2 AND (om.role=\'owner\' OR l.account_id IS NOT NULL)))) ORDER BY s.created_at,s.id', [$user['id'], $user['account_id'],$user['id'],$user['account_id']]);
                $access=new NativeOrganizationAccess($this->container);
                $rows=array_values(array_filter(array_map(fn($row)=>$access->decorate($row,$user['account_id'],$row['role']),$rows)));
                $rows=array_values(array_filter($rows,fn($row)=>$row['kind']!=='personal' || ((int)$row['owner_id']===(int)$user['id'] && $row['role']==='owner' && $this->one('SELECT scope_id FROM familyhub_personal_scopes WHERE account_id=? AND scope_id=?',[$user['account_id'],$row['id']]))));
                $result=['scopes' => array_map(fn ($row) => $this->scopeWire($row), array_values(array_filter($rows, fn ($row) => ($includePersonal || $row['kind'] !== 'personal') && ($includeOrganizations || $row['kind'] !== 'organization') && ($includeArchived || !(int)($row['archived']??0)))))];
                if ($params['includeAccessChanges']??false) {
                    $revoked=$this->many('SELECT r.scope_id FROM familyhub_scope_revocations r JOIN familyhub_scopes s ON s.id=r.scope_id WHERE r.account_id=? ORDER BY r.scope_id',[$user['account_id']]);
                    $result['revokedScopeIds']=array_values(array_filter(array_column($revoked,'scope_id'),fn($sid)=>!$access->visibleScope($sid,$user['account_id'])));
                }
                return $result;
            }
            if ($operation === 'scopes.create') {
                $this->fields($params, ['id', 'kind', 'name', 'requestId'], ['organizationId','parentScopeId','accessPolicyVersion','projectPayload','address']);
                $id = $this->uuid($params['id']); $request = $this->uuid($params['requestId']);
                if (!in_array($params['kind'], ['household', 'project', 'organization'], true)) { throw new NativeError('validation_error'); }
                $accessVersion=$params['accessPolicyVersion']??1;
                if (!is_int($accessVersion) || !in_array($accessVersion,[1,2,3],true) || (isset($params['accessPolicyVersion']) && !in_array($params['kind'],['organization','household','project'],true)) || ($params['kind']==='household' && $accessVersion===2)) { throw new NativeError('validation_error'); }
                $parentId = $params['parentScopeId'] ?? $params['organizationId'] ?? null;
                $organizationId = null;
                if ($parentId !== null) {
                    $this->uuid($parentId);
                    if ($params['kind'] !== 'project' || (isset($params['organizationId']) && $params['organizationId']!==$parentId)) { throw new NativeError('validation_error'); }
                    $parent = $this->scope($parentId, $user['id'], true, true);
                    if (!in_array($parent['kind'],['organization','household'],true) || ($parent['kind']==='household' && (int)$parent['access_policy_version']!==3)) { throw new NativeError('validation_error'); }
                    if ($accessVersion===3 && (int)$parent['access_policy_version']!==3) { throw new NativeError('access_migration_required',409); }
                    $organizationId=$parent['kind']==='organization'?$parentId:null;
                    if ((int)$parent['access_policy_version']===3) { $accessVersion=3; }
                }
                if (isset($params['projectPayload']) && $parentId===null && !($params['kind']==='project' && $accessVersion===3)) { throw new NativeError('validation_error'); }
                $address=$params['address']??null;
                if ($address!==null) { $this->text($address,2000,true); }
                $name = $this->text($params['name'], 200); $hash = $this->hashRequest($operation, $params);
                $existing = $this->one('SELECT * FROM familyhub_scopes WHERE id = ?'.$this->lockSuffix(), [$id]);
                if ($existing) {
                    $this->scope($id, $user['id'], true, true);
                    $replay = $this->replay($id, $user['id'], $request, $hash);
                    if ($replay) { return $replay['body']; }
                    throw new NativeError('conflict', 409);
                }
                $projectRoot=$params['kind']==='project' && ($parentId!==null || $accessVersion===3);
                $contract = $projectRoot || $params['kind'] === 'organization' ? 3 : 1;
                $this->change('INSERT INTO familyhub_scopes(id,kind,name,owner_id,sequence,created_at,organization_id,required_record_contract) VALUES(?,?,?,?,0,?,?,?)', [$id, $params['kind'], $name, $user['id'], time(), $organizationId, $contract]);
                $this->change('UPDATE familyhub_scopes SET access_policy_version=?,address=?,parent_scope_id=? WHERE id=?',[$accessVersion,$address,$parentId,$id]);
                $this->change('INSERT INTO familyhub_members(scope_id,user_id,account_id,role,active) VALUES(?,?,?,\'owner\',1)', [$id, $user['id'], $user['account_id']]);
                if ($projectRoot) { $this->change('UPDATE familyhub_scopes SET project_root_id=? WHERE id=?',[$id,$id]); }
                $sequence=0;
                if ($projectRoot) {
                    $stamp=gmdate('Y-m-d\TH:i:s\Z');
                    $payload=['title'=>$name,'description'=>'','area'=>'home','startAt'=>null,'endAt'=>null,'phases'=>[],'availabilityMinutes'=>null,'availabilityPeriod'=>null,'createdAt'=>$stamp,'updatedAt'=>$stamp];
                    if (isset($params['projectPayload'])) {
                        (new NativeRecordPolicy($this->container))->validate('project',$params['projectPayload'],$id,null,3);
                        if ($params['projectPayload']['title']!==$name) { throw new NativeError('validation_error'); }
                        $payload=$params['projectPayload'];
                    }
                    $sequence=1;
                    $this->change('INSERT INTO familyhub_records(scope_id,id,type,revision,deleted,payload,sequence,updated_at,contract_version,created_by,updated_by) VALUES(?,?,\'project\',1,0,?,1,?,3,?,?)',[$id,$id,json_encode($payload,JSON_UNESCAPED_UNICODE|JSON_THROW_ON_ERROR),$stamp,$user['account_id'],$user['account_id']]);
                    $this->change('UPDATE familyhub_scopes SET sequence=1 WHERE id=?',[$id]);
                }
                $effective=$this->scope($id,$user['id']);
                if ((int)($effective['effective_access_policy_version']??1)>=2) {
                    $this->change('INSERT INTO familyhub_finance_policy(scope_id,enabled,revision,sequence) VALUES(?,1,1,0)',[$id]);
                    $this->change('INSERT INTO familyhub_finance_grants VALUES(?,?,\'write\')',[$id,$user['account_id']]);
                }
                $result = ['scope' => $this->scopeWire($effective)];
                if ($projectRoot) { $result['projectRoot']=(new NativeRecordPolicy($this->container))->wire($this->one('SELECT * FROM familyhub_records WHERE scope_id=? AND id=?',[$id,$id]),3); }
                $this->remember($id, $user['id'], $request, $hash, $result);
                return $result;
            }
            if ($operation==='scopes.updateMetadata') {
                $this->fields($params,['scopeId','name','address','expectedRevision','requestId']);
                $id=$this->uuid($params['scopeId']);$request=$this->uuid($params['requestId']);
                $scope=$this->scope($id,$user['id'],false,true);
                if (!in_array($scope['kind'],['household','organization'],true)) { throw new NativeError('validation_error'); }
                $name=$this->text($params['name'],200);$address=$params['address'];
                if ($address!==null) { $this->text($address,2000,true); }
                if (!is_int($params['expectedRevision']) || $params['expectedRevision']<0) { throw new NativeError('validation_error'); }
                $hash=$this->hashRequest($operation,$params);$replay=$this->replay($id,$user['id'],$request,$hash);
                if ($replay) { return $replay['body']; }
                if ((int)$scope['metadata_revision']!==$params['expectedRevision']) { throw new NativeError('metadata_conflict',409,['scope'=>$this->scopeWire($scope)]); }
                $this->change('UPDATE familyhub_scopes SET name=?,address=?,metadata_revision=metadata_revision+1,sequence=sequence+1 WHERE id=?',[$name,$address,$id]);
                $result=['scope'=>$this->scopeWire($this->scope($id,$user['id']))];$this->remember($id,$user['id'],$request,$hash,$result);return $result;
            }
            if ($operation==='scopes.archive') {
                $this->fields($params,['scopeId','archived','requestId']);
                $id=$this->uuid($params['scopeId']);$request=$this->uuid($params['requestId']);
                if (!is_bool($params['archived'])) { throw new NativeError('validation_error'); }
                $scope=$this->scope($id,$user['id'],false,true);
                if ($scope['kind']!=='project' || empty($scope['project_root_id'])) { throw new NativeError('validation_error'); }
                $hash=$this->hashRequest($operation,$params);$replay=$this->replay($id,$user['id'],$request,$hash);
                if ($replay) { return $replay['body']; }
                if ((int)($scope['archived']??0)!==(int)$params['archived']) {
                    $this->change('UPDATE familyhub_scopes SET archived=?,sequence=sequence+1 WHERE id=?',[(int)$params['archived'],$id]);
                    $this->change('UPDATE familyhub_finance_policy SET revision=revision+1 WHERE scope_id=?',[$id]);
                    if (!$params['archived']) { $this->change("UPDATE familyhub_reminders SET state='cancelled',revision=revision+1 WHERE scope_id=? AND state='pending' AND remind_epoch<=?",[$id,time()]); }
                }
                $result=['scope'=>$this->scopeWire($this->scope($id,$user['id'],false,true))];$this->remember($id,$user['id'],$request,$hash,$result);return $result;
            }
            if ($operation === 'scopes.members') {
                $this->fields($params, ['scopeId']);
                $id = $this->uuid($params['scopeId']); $authorized = $this->scope($id, $user['id']);
                $rows = $this->many('SELECT m.user_id,m.role,u.username,u.name,m.account_id FROM familyhub_members m JOIN users u ON u.id=m.user_id JOIN familyhub_accounts a ON a.user_id=m.user_id AND a.account_id=m.account_id WHERE m.scope_id=? AND m.active=1 AND u.is_active=1 ORDER BY m.user_id', [$id]);
                if ((int)$authorized['effective_access_policy_version']===3) { return ['members'=>(new NativeOrganizationAccess($this->container))->members($id)]; }
                if ($authorized['kind']==='organization') { return ['members'=>(new NativeSpacesAccessService($this->container))->members($id)]; }
                if ($authorized['kind'] === 'personal') { $rows = array_values(array_filter($rows, fn ($row) => $row['account_id'] === $user['account_id'])); }
                return ['members' => array_map(fn ($row) => ['userId' => (int)$row['user_id'], 'accountId' => $row['account_id'], 'username' => $row['username'], 'displayName' => $row['name'] ?: $row['username'], 'role' => $row['role'], 'active' => true], $rows)];
            }
            if ($operation === 'scopes.removeMember') {
                $this->fields($params, ['scopeId', 'userId', 'requestId']);
                $id = $this->uuid($params['scopeId']); $request = $this->uuid($params['requestId']);
                $scope = $this->scope($id, $user['id'], false, true);
                if ($scope['kind'] === 'personal') { throw new NativeError('personal_not_shareable', 403); }
                if (!is_int($params['userId']) || $params['userId'] <= 0) { throw new NativeError('validation_error'); }
                $hash = $this->hashRequest($operation, $params);
                $replay = $this->replay($id, $user['id'], $request, $hash);
                if ($replay) { return $replay['body']; }
                $member = $this->one('SELECT * FROM familyhub_members WHERE scope_id = ? AND user_id = ?', [$id, $params['userId']]);
                if (!$member || $member['role'] === 'owner') { throw new NativeError('cannot_remove_owner'); }
                $access=new NativeOrganizationAccess($this->container);$formerlyVisible=array_values(array_filter($access->relatedScopeIds($id),fn($sid)=>$access->visibleScope($sid,$member['account_id'])));
                $this->change('UPDATE familyhub_members SET active=0 WHERE scope_id=? AND user_id=?', [$id, $params['userId']]);
                if ($scope['kind']==='organization' || (int)$scope['effective_access_policy_version']===3) {
                    $this->change('DELETE FROM familyhub_organization_leaders WHERE scope_id=? AND account_id=?',[$id,$member['account_id']]);
                    $this->change('UPDATE familyhub_scopes SET access_revision=access_revision+1 WHERE id=?',[$id]);
                }
                $this->change('UPDATE familyhub_finance_grants SET access_level=\'none\' WHERE scope_id=? AND account_id=?', [$id, $member['account_id']]);
                $this->change('UPDATE familyhub_finance_policy SET revision=revision+1 WHERE scope_id=?', [$id]);
                if ($member['account_id']) { $access=new NativeOrganizationAccess($this->container);$access->reconcileRevocations($formerlyVisible,$member['account_id']); }
                if ($member['account_id']) { (new NativeNotificationWriter($this->container))->visibilityChanged([$member['account_id']]); }
                $this->advance($scope);
                $result = ['removed' => true]; $this->remember($id, $user['id'], $request, $hash, $result);
                return $result;
            }
            throw new NativeError('unsupported_operation', 404);
        }, $operation === 'scopes.create');
    }
}
