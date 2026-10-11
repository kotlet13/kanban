<?php
namespace Kanboard\Plugin\FamilyHub\Model;

/** Same authenticated encryption, SMTP transport and bounded leased worker as account mail. */
class NativeInvitationMailQueue extends NativeEmailInvitationService
{
    public function aad($id) { return $this->serverId().':email-invitation:'.$id; }
    public function run($limit=20,$transport=null,$deadline=null)
    {
        if (!defined('FAMILYHUB_ENABLE_NATIVE_API') || FAMILYHUB_ENABLE_NATIVE_API!==true || !self::available()) { throw new NativeError('email_unavailable',503); }
        if (!is_int($limit) || $limit<1 || $limit>50) { throw new NativeError('validation_error'); }
        $transport=$transport??new NativeAccountMailTransport(); $deadline=$deadline??microtime(true)+60;
        $counts=['examined'=>0,'accepted'=>0,'retry'=>0,'cancelled'=>0];
        // Remove undispatched secrets after accept/revoke/expiry, even beyond this batch.
        $this->change('UPDATE familyhub_invitation_mail SET state=\'cancelled\',token_cipher=NULL,lease_token=NULL WHERE state IN (\'pending\',\'processing\') AND invitation_id IN (SELECT id FROM familyhub_invitations WHERE accepted_at IS NOT NULL OR revoked_at IS NOT NULL OR expires_at<=?)',[time()]);
        $rows=$this->many('SELECT invitation_id FROM familyhub_invitation_mail WHERE (state=\'pending\' AND next_attempt<=?) OR (state=\'processing\' AND lease_until<=?) ORDER BY next_attempt,invitation_id LIMIT '.$limit,[time(),time()]);
        foreach ($rows as $row) {
            if (microtime(true)+50>$deadline) { break; }
            $lease=$this->transaction(function() use($row) {
                $job=$this->one('SELECT * FROM familyhub_invitation_mail WHERE invitation_id=?'.$this->lockSuffix(),[$row['invitation_id']]);
                if (!$job || !in_array($job['state'],['pending','processing'],true) || ($job['state']==='processing' && (int)$job['lease_until']>time()) || ($job['state']==='pending' && (int)$job['next_attempt']>time())) { return null; }
                $lease=bin2hex(random_bytes(16));
                $this->change('UPDATE familyhub_invitation_mail SET state=\'processing\',attempts=attempts+1,lease_token=?,lease_until=? WHERE invitation_id=?',[$lease,time()+120,$row['invitation_id']]); return $lease;
            });
            if (!$lease) { continue; } $counts['examined']++;
            $outcome=$this->transaction(function() use($row,$lease,$transport,$deadline) {
                $id=$row['invitation_id'];
                $invitation=$this->one('SELECT * FROM familyhub_invitations WHERE id=?',[$id]);
                if ($invitation) {
                    $this->one('SELECT id FROM users WHERE id=?'.$this->lockSuffix(),[$invitation['creator_id']]);
                    try { $scope=$this->usable($invitation); } catch (NativeError $error) { $scope=null; }
                } else { $scope=null; }
                $job=$this->one('SELECT * FROM familyhub_invitation_mail WHERE invitation_id=?'.$this->lockSuffix(),[$id]);
                if (!$job || $job['state']!=='processing' || $job['lease_token']!==$lease) { return 'cancelled'; }
                $invitation=$this->one('SELECT * FROM familyhub_invitations WHERE id=?',[$id]);
                try {
                    if (!$scope || (int)$job['attempts']>5 || empty($invitation['recipient_email'])) { throw new NativeError('invitation_invalid',404); }
                } catch (NativeError $error) { $this->finish($id,$lease,'cancelled'); return 'cancelled'; }
                if (microtime(true)+50>$deadline) { $this->retry($id,$lease,60); return 'retry'; }
                try {
                    $token=NativeAccountMailCrypto::decrypt($job['token_cipher'],$this->aad($id));
                    if (!hash_equals($invitation['token_hash'],hash('sha256',$token))) { throw new NativeError('email_unavailable',503); }
                    $url=self::publicUrl($this->configModel->get('application_url')).'/index.php?controller=InvitationController&action=show&plugin=FamilyHub&language='.$job['language'].'#token='.rawurlencode($token);
                    $creator=$this->one('SELECT name,username FROM users WHERE id=?',[$invitation['creator_id']]);
                    $details=['inviterName'=>$creator['name']?:$creator['username'],'scopeName'=>$scope['name'],'role'=>$invitation['role']];
                    if (($transport->send($invitation['recipient_email'],'invitation',$url,$id,$job['language'],$details)['accepted']??false)!==true) { throw new NativeError('email_unavailable',503); }
                    $this->finish($id,$lease,'accepted'); return 'accepted';
                } catch (\Throwable $ignored) {
                    if ((int)$job['attempts']>=5) { $this->finish($id,$lease,'cancelled'); return 'cancelled'; }
                    $this->retry($id,$lease,min(900,60*(2**(int)$job['attempts']))); return 'retry';
                }
            });
            $counts[$outcome]++;
        }
        return $counts;
    }
    private function finish($id,$lease,$state) { $this->change('UPDATE familyhub_invitation_mail SET state=?,token_cipher=NULL,lease_token=NULL,accepted_at=? WHERE invitation_id=? AND lease_token=?',[$state,$state==='accepted'?time():null,$id,$lease]); }
    private function retry($id,$lease,$seconds) { $this->change('UPDATE familyhub_invitation_mail SET state=\'pending\',lease_token=NULL,next_attempt=? WHERE invitation_id=? AND lease_token=?',[time()+$seconds,$id,$lease]); }
}
