<?php
namespace Kanboard\Plugin\FamilyHub\Model;

/** Send authorizes the signed roster and encrypted keys; acceptance is the trusted server/UI membership lifecycle. */
class NativeCryptoInvitationPreauthorizationV5 extends NativeCryptoInvitationV2
{
    private static $positiveReadiness;
    public static function ready(\PDO $pdo)
    {
        self::$positiveReadiness??=new \WeakMap();
        if(isset(self::$positiveReadiness[$pdo]))return true;
        try {
            foreach (['reservations'=>'scope_id,account_id,invitation_id,invitation_scope_id,proof_hash,member,state','publications'=>'invitation_id,head_hash,child_heads,authorization,created_at'] as $table=>$columns) {
                $statement=$pdo->query('SELECT '.$columns.' FROM familyhub_crypto_invitation_'.$table.'_v5 WHERE 1=0');$statement->closeCursor();
            }
            self::$positiveReadiness[$pdo]=true;return true;
        } catch (\Throwable $ignored) { return false; }
    }

    public function binding($row)
    {
        $proof=json_decode($row['authorization'],true,34,JSON_THROW_ON_ERROR);if(!isset($proof['commandBase64']))return null;
        [$command]=NativeCryptoCodec::decode($proof);
        return $command['payload']['preauthorization']??null;
    }

    public function resolveRecipient($value)
    {
        $recipient=$this->recipient($value);
        if ($recipient['kind']==='email') {
            $found=$this->one('SELECT e.account_id FROM familyhub_email_identities e JOIN familyhub_accounts a ON a.account_id=e.account_id JOIN users u ON u.id=a.user_id WHERE e.email=? AND e.verified_at IS NOT NULL AND u.is_active=1',[$recipient['value']]);
            if (!$found || NativeCryptoAccountTombstoneV2::account($this->pdo,$found['account_id'])) throw new NativeError('crypto_invitation_recipient_unregistered',409);
            $recipient['accountId']=$found['account_id'];
        }
        return $recipient;
    }

    private function context($scope,$account,$role)
    {
        if (!in_array((int)$scope['effective_access_policy_version'],[1,2,3],true) || !in_array($role,['member','viewer'],true)) throw new NativeError('crypto_invitation_preauthorization_policy',409);
        $directory=(new NativeCryptoDirectoryV2($this->container))->current($account);
        if (!$directory) throw new NativeError('crypto_invitation_recipient_setup_required',409);
        $snapshot=json_decode($directory['snapshot'],true,34,JSON_THROW_ON_ERROR);
        $member=['accountId'=>$account,'rootSigningKeyBase64'=>$snapshot['rootSigningKeyBase64'],'rootEncryptionKeyBase64'=>$snapshot['rootEncryptionKeyBase64'],'recoveryRootEpochId'=>$snapshot['recoveryRootEpochId'],'identityEpochId'=>$snapshot['identityEpochId'],'directoryHeadHash'=>$directory['head_hash'],'deviceSnapshotHash'=>$directory['device_snapshot_hash'],'role'=>$role]+$this->policy($scope,$role,$account);
        return ['version'=>1,'member'=>$member,'policyVersion'=>(int)$scope['effective_access_policy_version'],'accessBasis'=>(new NativeCryptoScopeV2($this->container))->accessBasis($scope)];
    }

    private function policy($scope,$role,$account=null)
    {
        $scope['effective_access_policy_version']=(int)($scope['effective_access_policy_version']??$scope['access_policy_version']??1);
        $policy=(new NativeFinanceAccess($this->container))->projectedInvitationPolicy($scope,$account,$role);
        return ['financeRole'=>$policy['enabled']?$policy['grant']:'none','manageKeys'=>$scope['effective_access_policy_version']===3&&$role==='member'];
    }

    public function resolve($p,$actor)
    {
        if (!self::ready($this->pdo)) throw new NativeError('crypto_invitation_preauthorization_unavailable',503);
        $this->fields($p,['scopeId','recipient','role'],['afterGeneration','limit']);
        $scope=$this->scope($this->uuid($p['scopeId']),$actor['user']['id']);
        $scopes=new NativeCryptoScopeV2($this->container);$scopes->manager($scopes->current($scope['id']),$scope,$actor);
        $recipient=$this->resolveRecipient($p['recipient']);
        if ($recipient['accountId']===$actor['user']['account_id']) throw new NativeError('validation_error');
        // Existing access/privilege upgrades require their ordinary explicit review.
        foreach ((new NativeOrganizationAccess($this->container))->relatedScopeIds($scope['id']) as $sid) {
            if ((new NativeOrganizationAccess($this->container))->visibleScope($sid,$recipient['accountId'])) throw new NativeError('crypto_invitation_already_member',409);
        }
        $context=$this->context($scope,$recipient['accountId'],$p['role']);
        return ['recipient'=>$recipient,'preauthorization'=>$context,'recipientDirectory'=>$this->directoryPrefix($recipient['accountId'],$context['member']['directoryHeadHash'],$p['afterGeneration']??0,$p['limit']??50)];
    }

    public function validateCreation($p,$scope,$recipient)
    {
        if (!self::ready($this->pdo)) throw new NativeError('crypto_invitation_preauthorization_unavailable',503);
        $expected=$this->context($scope,$recipient['accountId'],$p['role']);
        if (!is_array($p['preauthorization']) || NativeCryptoCodec::canonical((object)$p['preauthorization'])!==NativeCryptoCodec::canonical((object)$expected)) throw new NativeError('crypto_invitation_preauthorization_changed',409);
        foreach ((new NativeOrganizationAccess($this->container))->relatedScopeIds($scope['id']) as $sid) {
            if ((new NativeOrganizationAccess($this->container))->visibleScope($sid,$recipient['accountId'])) throw new NativeError('crypto_invitation_already_member',409);
        }
    }

    private function condition($scope,$entry,$member,$requireUsable=false)
    {
        $this->fields($entry,['accountId','invitationId','preauthorizationProofHash','invitationScopeId']);
        $row=$this->invitation($entry['invitationId']);$binding=$this->binding($row);
        $proof=json_decode($row['authorization'],true,34,JSON_THROW_ON_ERROR);
        $parent=$scope['parent_scope_id']??$scope['organization_id']??null;
        if (!$binding || $row['recipient_account_id']!==$entry['accountId'] || $row['scope_id']!==$entry['invitationScopeId'] || $entry['preauthorizationProofHash']!==NativeCryptoV2Codec::hash((object)$proof) || $scope['id']!==$row['scope_id'] && ($scope['kind']!=='project'||$parent!==$row['scope_id'])) throw new NativeError('crypto_invitation_preauthorization_invalid',409);
        if($this->consented($row['id']))return $row;
        if((int)$scope['effective_access_policy_version']!==$binding['policyVersion'])throw new NativeError('crypto_invitation_preauthorization_changed',409);
        $expected=$binding['member'];
        $expected=array_merge($expected,$this->policy($scope,$expected['role'],$expected['accountId']));
        if (NativeCryptoCodec::canonical((object)$expected)!==NativeCryptoCodec::canonical((object)$member)) throw new NativeError('crypto_invitation_preauthorization_changed',409);
        if ($requireUsable) $this->usable($row);
        return $row;
    }

    public function intent($scopeId,$intent,$member)
    {
        $scope=$this->one('SELECT * FROM familyhub_scopes WHERE id=?',[$scopeId]);
        $parent=$scope['parent_scope_id']??$scope['organization_id']??null;
        $policy=$parent?$this->one('SELECT access_policy_version FROM familyhub_scopes WHERE id=?',[$parent]):null;
        $scope['effective_access_policy_version']=(int)($policy['access_policy_version']??$scope['access_policy_version']);
        $invitation=$this->invitation($intent['invitationId']);
        $entry=['accountId'=>$intent['accountId'],'invitationId'=>$intent['invitationId'],'preauthorizationProofHash'=>$intent['preauthorizationProofHash'],'invitationScopeId'=>$invitation['scope_id']];
        $row=$this->condition($scope,$entry,$member,true);
        if ($row['state']!=='pending') throw new NativeError('crypto_invitation_preauthorization_invalid',409);
        $old=$this->one("SELECT * FROM familyhub_crypto_invitation_reservations_v5 WHERE scope_id=? AND account_id=? AND state='reserved'",[$scopeId,$member['accountId']]);
        if($old&&$old['invitation_id']!==$row['id'])$this->assertReplacement($old,$row);
        $account=$this->one('SELECT user_id FROM familyhub_accounts WHERE account_id=?',[$member['accountId']]);
        return ['accountId'=>$member['accountId'],'userId'=>(int)$account['user_id'],'role'=>$member['role'],'invitationId'=>$row['id'],'preauthorization'=>true,'preauthorizationReplacement'=>(bool)$old,'preauthorizationInherited'=>$row['scope_id']!==$scopeId];
    }

    private function assertReplacement($old,$row)
    {
        $prior=$this->invitation($old['invitation_id']);[$next]=NativeCryptoCodec::decode(json_decode($row['authorization'],true,34,JSON_THROW_ON_ERROR));
        $explicit=$next['operation']==='crypto2.invitations.resend'&&($next['payload']['replacesInvitationId']??null)===$prior['id'];
        if($prior['recipient_account_id']!==$row['recipient_account_id']||$prior['scope_id']!==$row['scope_id']||$old['invitation_scope_id']!==$row['scope_id']||$prior['state']==='consumed'||(!$explicit&&$prior['state']!=='revoked'&&(int)$prior['expires_at']>time()))throw new NativeError('crypto_invitation_preauthorization_conflict',409);
    }

    public function validatePreauthorizations($scope,$body)
    {
        $entries=$body['invitationPreauthorizations']??[];
        if (!$entries && !self::ready($this->pdo)) return [];
        if (!self::ready($this->pdo)||!is_array($entries)||!array_is_list($entries)||count($entries)>100) throw new NativeError('crypto_invitation_preauthorization_invalid',409);
        $members=[];foreach($body['members'] as $m)$members[$m['accountId']]=$m;
        $last='';$conditions=[];
        foreach($entries as $entry){
            if(!is_array($entry)||!isset($members[$entry['accountId']??''])||strcmp($entry['accountId'],$last)<=0)throw new NativeError('crypto_invitation_preauthorization_invalid',409);
            $this->condition($scope,$entry,$members[$entry['accountId']]);$last=$entry['accountId'];$conditions[$last]=$entry;
        }
        foreach($this->reservations($scope['id']) as $reservation){
            if(isset($members[$reservation['account_id']])&&!isset($conditions[$reservation['account_id']])&&!$this->consented($reservation['invitation_id']))throw new NativeError('crypto_invitation_consent_required',409);
        }
        return array_values($conditions);
    }

    public function reservations($sid)
    {
        if(!self::ready($this->pdo))return [];
        $scope=$this->one('SELECT * FROM familyhub_scopes WHERE id=?',[$sid]);if(!$scope)return [];
        $ids=[$sid];$parent=$scope['parent_scope_id']??$scope['organization_id']??null;
        if($parent&&$scope['kind']==='project'&&(int)($this->one('SELECT access_policy_version FROM familyhub_scopes WHERE id=?',[$parent])['access_policy_version']??0)===3)$ids[]=$parent;
        $rows=$this->many("SELECT r.*,a.user_id FROM familyhub_crypto_invitation_reservations_v5 r JOIN familyhub_accounts a ON a.account_id=r.account_id JOIN users u ON u.id=a.user_id WHERE r.scope_id IN (".implode(',',array_fill(0,count($ids),'?')).") AND r.state='reserved' AND u.is_active=1 ORDER BY r.scope_id,r.account_id",$ids);
        $out=[];foreach($rows as $row){
            if(isset($out[$row['account_id']])&&$out[$row['account_id']]['scope_id']===$sid&&$row['scope_id']!==$sid)continue;
            $m=json_decode($row['member'],true,34,JSON_THROW_ON_ERROR);
            if($parent){$scope['effective_access_policy_version']=(int)($this->one('SELECT access_policy_version FROM familyhub_scopes WHERE id=?',[$parent])['access_policy_version']??1);}
            $m=array_merge($m,$this->policy($scope,$m['role'],$m['accountId']));
            $row['projectedMember']=$m;$out[$row['account_id']]=$row;
        }return array_values($out);
    }

    /** One caller-local projection only; never retained across a savepoint or command. */
    public function projectedPolicies($sid)
    {
        $map=[];foreach($this->reservations($sid)as $r)$map[$r['account_id']]=['enabled'=>$r['projectedMember']['financeRole']!=='none','grant'=>$r['projectedMember']['financeRole']];return $map;
    }

    public function synchronize($scope,$entries,$members)
    {
        if(!self::ready($this->pdo))return;
        $byAccount=[];foreach($members as $m)$byAccount[$m['accountId']]=$m;
        $keep=[];
        foreach($entries as $entry){
            $keep[$entry['accountId']]=true;$old=$this->one('SELECT * FROM familyhub_crypto_invitation_reservations_v5 WHERE scope_id=? AND account_id=?',[$scope['id'],$entry['accountId']]);
            if($old&&$old['state']==='retired'&&$this->consented($entry['invitationId'])&&!(new NativeOrganizationAccess($this->container))->visibleScope($scope['id'],$entry['accountId']))throw new NativeError('crypto_invitation_consent_required',409);
            $args=[$entry['invitationId'],$entry['invitationScopeId'],$entry['preauthorizationProofHash'],NativeCryptoCodec::canonical((object)$byAccount[$entry['accountId']])];
            if($old){
                if($old['state']==='reserved'&&($old['invitation_id']!==$entry['invitationId']||$old['proof_hash']!==$entry['preauthorizationProofHash']))$this->assertReplacement($old,$this->invitation($entry['invitationId']));
                $this->change("UPDATE familyhub_crypto_invitation_reservations_v5 SET invitation_id=?,invitation_scope_id=?,proof_hash=?,member=?,state='reserved' WHERE scope_id=? AND account_id=?",array_merge($args,[$scope['id'],$entry['accountId']]));
            }else{$this->change("INSERT INTO familyhub_crypto_invitation_reservations_v5 VALUES(?,?,?,?,?,?,'reserved')",array_merge([$scope['id'],$entry['accountId']],$args));}
        }
        foreach($this->many("SELECT * FROM familyhub_crypto_invitation_reservations_v5 WHERE scope_id=? AND state='reserved'",[$scope['id']])as $row)if(!isset($keep[$row['account_id']])){
            if(isset($byAccount[$row['account_id']])&&!$this->consented($row['invitation_id']))throw new NativeError('crypto_invitation_consent_required',409);
            $this->change("UPDATE familyhub_crypto_invitation_reservations_v5 SET state='retired' WHERE scope_id=? AND account_id=?",[$scope['id'],$row['account_id']]);
            if(!isset($byAccount[$row['account_id']])&&$row['invitation_scope_id']===$scope['id'])$this->change("UPDATE familyhub_crypto_invitations_v2 SET state='revoked' WHERE id=? AND state IN ('pending','accepted')",[$row['invitation_id']]);
        }
    }

    public function consented($id)
    {
        return(bool)$this->one("SELECT proof_hash FROM familyhub_crypto_invitation_acceptances_v2 WHERE invitation_id=? AND state='consumed' LIMIT 1",[$id]);
    }

    public function publication($id)
    {
        return self::ready($this->pdo)?$this->one('SELECT * FROM familyhub_crypto_invitation_publications_v5 WHERE invitation_id=?',[$id]):null;
    }

    /** Called only inside the existing signed access transition/savepoint. */
    public function retireForAccess($sid,$account=null,$pendingOnly=false)
    {
        if(!self::ready($this->pdo))return;
        foreach($this->many("SELECT * FROM familyhub_crypto_invitation_reservations_v5 WHERE scope_id=? AND state='reserved'",[$sid])as $row){
            if($account!==null&&$row['account_id']!==$account||$pendingOnly&&$this->consented($row['invitation_id']))continue;
            $this->change("UPDATE familyhub_crypto_invitation_reservations_v5 SET state='retired' WHERE scope_id=? AND account_id=?",[$sid,$row['account_id']]);
            $this->change("UPDATE familyhub_crypto_invitations_v2 SET state='revoked' WHERE id=? AND state IN ('pending','accepted')",[$row['invitation_id']]);
        }
    }

    public function publish($p,$actor,$proof)
    {
        $this->fields($p,['scopeId','invitationId','preauthorizationHeadHash','childHeads','authorDirectoryHeadHash']);
        $row=$this->invitation($p['invitationId']);$scope=$this->usable($row);
        $scopes=new NativeCryptoScopeV2($this->container);$scopes->manager($scopes->current($scope['id']),$scope,$actor);$scopes->currentAuthorReference($p['authorDirectoryHeadHash'],$actor);
        if($scope['id']!==$p['scopeId']||!$this->binding($row)||$row['state']!=='pending'||!is_array($p['childHeads'])||!array_is_list($p['childHeads'])||count($p['childHeads'])>100)throw new NativeError('crypto_invitation_preauthorization_invalid',409);
        if($actor['user']['account_id']!==$row['creator_account_id'])throw new NativeError('permission_revoked',403);
        $related=(int)$this->binding($row)['policyVersion']===3?$this->many('SELECT id FROM familyhub_scopes WHERE (parent_scope_id=? OR organization_id=?) AND deleted_at IS NULL ORDER BY id',[$scope['id'],$scope['id']]):[];
        if(array_column($related,'id')!==array_column($p['childHeads'],'scopeId'))throw new NativeError('crypto_invitation_children_changed',409);
        $heads=array_merge([['scopeId'=>$scope['id'],'headHash'=>$p['preauthorizationHeadHash']]],$p['childHeads']);
        foreach($heads as $ref){
            $this->fields($ref,['scopeId','headHash']);$head=$scopes->current($ref['scopeId']);$body=$head?$scopes->body($head):null;
            if(!$head||$head['head_hash']!==$ref['headHash'])throw new NativeError('crypto_invitation_preauthorization_changed',409);
            $found=false;foreach($body['invitationPreauthorizations']??[]as $entry)if($entry['invitationId']===$row['id']&&$entry['accountId']===$row['recipient_account_id']&&$entry['preauthorizationProofHash']===NativeCryptoV2Codec::hash((object)json_decode($row['authorization'],true,34,JSON_THROW_ON_ERROR)))$found=true;
            if(!$found)throw new NativeError('crypto_invitation_preauthorization_invalid',409);
            $scopes->grantManifest($body,true);
        }
        if($this->publication($row['id']))throw new NativeError('crypto_invitation_preauthorization_immutable',409);
        $this->change('INSERT INTO familyhub_crypto_invitation_publications_v5 VALUES(?,?,?,?,?)',[$row['id'],$p['preauthorizationHeadHash'],NativeCryptoCodec::canonical($p['childHeads']),json_encode($proof,JSON_THROW_ON_ERROR),time()]);
        $this->change("UPDATE familyhub_crypto_invitation_mail_v2 SET state='pending',next_attempt=? WHERE invitation_id=? AND state='held'",[time(),$row['id']]);
        $mail=$this->one('SELECT state FROM familyhub_crypto_invitation_mail_v2 WHERE invitation_id=?',[$row['id']]);
        return ['invitationId'=>$row['id'],'state'=>'ready','admissionMode'=>'preauthorized','preauthorizationHeadHash'=>$p['preauthorizationHeadHash'],'deliveryQueued'=>$mail&&in_array($mail['state'],['pending','processing'],true)];
    }

    public function acceptPrepared($row,$p,$actor,$acceptanceHash)
    {
        $publication=$this->publication($row['id']);$binding=$this->binding($row);
        if(!$publication||($p['preauthorizationHeadHash']??null)!==$publication['head_hash'])throw new NativeError('crypto_invitation_preparation_pending',409);
        $directory=(new NativeCryptoDirectoryV2($this->container))->current($actor['user']['account_id']);
        if(!$directory||$directory['device_snapshot_hash']!==$binding['member']['deviceSnapshotHash']||$directory['identity_epoch_id']!==$binding['member']['identityEpochId'])throw new NativeError('crypto_invitation_recipient_changed',409);
        $scopes=new NativeCryptoScopeV2($this->container);$refs=array_merge([['scopeId'=>$row['scope_id'],'headHash'=>$publication['head_hash']]],json_decode($publication['child_heads'],true,34,JSON_THROW_ON_ERROR));
        $related=(int)$binding['policyVersion']===3?$this->many('SELECT id FROM familyhub_scopes WHERE (parent_scope_id=? OR organization_id=?) AND deleted_at IS NULL ORDER BY id',[$row['scope_id'],$row['scope_id']]):[];
        $expectedChildren=array_column($related,'id');$actualChildren=array_column(array_slice($refs,1),'scopeId');
        // New child scopes are safe only if their current head carries the same Send-time preauthorization marker.
        foreach(array_diff($expectedChildren,$actualChildren)as $sid)$refs[]=['scopeId'=>$sid,'headHash'=>null];
        foreach($refs as $ref){
            $scopeRow=$this->one('SELECT * FROM familyhub_scopes WHERE id=?',[$ref['scopeId']]);
            if(!$scopeRow||($scopeRow['deleted_at']??null)!==null||$ref['scopeId']!==$row['scope_id']&&($scopeRow['parent_scope_id']??$scopeRow['organization_id']??null)!==$row['scope_id'])throw new NativeError('crypto_invitation_children_changed',409);
            $head=$scopes->current($ref['scopeId']);if(!$head)throw new NativeError('crypto_invitation_preparation_pending',409);
            if($ref['headHash']!==null){
                $cursor=$head;$steps=0;
                while($cursor['head_hash']!==$ref['headHash']){
                    if(++$steps>1000||$cursor['previous_head_hash']===NativeCryptoDirectoryV2::ZERO)throw new NativeError('crypto_invitation_preauthorization_changed',409);
                    $cursor=$scopes->head($ref['scopeId'],$cursor['previous_head_hash']);
                }
            }
            $found=false;foreach($scopes->body($head)['invitationPreauthorizations']??[]as $entry)if($entry['invitationId']===$row['id']&&$entry['accountId']===$row['recipient_account_id'])$found=true;
            if(!$found)throw new NativeError('crypto_invitation_preparation_pending',409);
            $creator=$this->one('SELECT user_id FROM familyhub_accounts WHERE account_id=?',[$row['creator_account_id']]);
            $currentScope=$this->scope($ref['scopeId'],$creator['user_id']);
            $scopes->assertMembershipParity($currentScope,$scopes->body($head)['members']);
            $scopes->grantManifest($scopes->body($head),true);
        }
        $user=$this->one('SELECT user_id FROM familyhub_accounts WHERE account_id=?',[$row['recipient_account_id']]);
        $member=$this->one('SELECT active,role FROM familyhub_members WHERE scope_id=? AND account_id=? AND user_id=?',[$row['scope_id'],$row['recipient_account_id'],$user['user_id']]);
        if(!$member||(int)$member['active']!==0||$member['role']!==$row['role'])throw new NativeError('crypto_invitation_preauthorization_changed',409);
        $this->change('UPDATE familyhub_members SET active=1 WHERE scope_id=? AND account_id=? AND user_id=?',[$row['scope_id'],$row['recipient_account_id'],$user['user_id']]);
        $this->consume(['invitationId'=>$row['id'],'acceptanceProofHash'=>$acceptanceHash]);
        return ['state'=>'keysReady','admissionMode'=>'preauthorized','activatedHeadHash'=>$publication['head_hash']];
    }

    public function directoryReferences($body,$target)
    {
        $refs=[];foreach($body['invitationPreauthorizations']??[]as $entry){
            $row=$this->invitation($entry['invitationId']);[$creator]=NativeCryptoCodec::decode(json_decode($row['authorization'],true,34,JSON_THROW_ON_ERROR));
            if($creator['accountId']===$target)$refs[]=$creator['payload']['authorDirectoryHeadHash'];
            $publication=$this->publication($row['id']);if($publication){[$publisher]=NativeCryptoCodec::decode(json_decode($publication['authorization'],true,34,JSON_THROW_ON_ERROR));if($publisher['accountId']===$target)$refs[]=$publisher['payload']['authorDirectoryHeadHash'];}
            foreach($this->many("SELECT authorization FROM familyhub_crypto_invitation_acceptances_v2 WHERE invitation_id=? AND account_id=? AND state='consumed'",[$row['id'],$target])as $accepted){[$raw]=NativeCryptoCodec::decode(json_decode($accepted['authorization'],true,34,JSON_THROW_ON_ERROR));$refs[]=$raw['payload']['authorDirectoryHeadHash'];}
        }return $refs;
    }
}
