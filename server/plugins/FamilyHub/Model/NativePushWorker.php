<?php
namespace Kanboard\Plugin\FamilyHub\Model;

/** Locks user -> device -> scope -> registration -> job through bounded send. */
class NativePushWorker extends NativeDatabase
{
    public function deliver(array $candidate,$lease,$transport,$deadline)
    {
        return $this->transaction(function () use ($candidate,$lease,$transport,$deadline) {
            $device=$this->one('SELECT * FROM familyhub_devices WHERE id=?',[$candidate['device_id']]);
            $user=$device ? $this->one('SELECT * FROM users WHERE id=?'.$this->lockSuffix(),[$device['user_id']]) : null;
            $device=$device ? $this->one('SELECT * FROM familyhub_devices WHERE id=?'.$this->lockSuffix(),[$device['id']]) : null;
            $inbox=$this->one('SELECT * FROM familyhub_inbox WHERE id=?',[$candidate['inbox_id']]);
            if ($inbox) { $this->one('SELECT id FROM familyhub_scopes WHERE id=?'.$this->lockSuffix(),[$inbox['scope_id']]); }
            $registration=$this->one('SELECT * FROM familyhub_push_registrations WHERE device_id=?'.$this->lockSuffix(),[$candidate['device_id']]);
            $job=$this->one('SELECT * FROM familyhub_push_jobs WHERE inbox_id=? AND device_id=? AND registration_revision=?'.$this->lockSuffix(),[$candidate['inbox_id'],$candidate['device_id'],$candidate['registration_revision']]);
            if (!$job || $job['state']!=='processing' || $job['lease_token']!==$lease) { return ['status'=>'cancelled','coalesced'=>0]; }
            $account=$device ? $this->one('SELECT account_id FROM familyhub_accounts WHERE user_id=?',[$device['user_id']]) : null;
            $settings=$inbox ? $this->one('SELECT settings FROM familyhub_inbox_preferences WHERE scope_id=? AND account_id=? AND category=?',[$inbox['scope_id'],$inbox['recipient_account_id'],$inbox['category']]) : null;
            $settings=$settings ? json_decode($settings['settings'],true,32,JSON_THROW_ON_ERROR) : [];
            $sessionValid=$user && $device && $account && (int)$user['is_active']===1 && (int)$user['is_ldap_user']===0 && (int)$user['disable_login_form']===0 && $device['revoked_at']===null && (int)$device['expires_at']>time() && hash_equals($device['credentials_hash'],$this->fingerprint($user)) && $device['account_id']===$account['account_id'];
            $valid=$sessionValid && $registration && $inbox && $registration['account_id']===$account['account_id'] && $inbox['recipient_account_id']===$account['account_id'] && (int)$registration['active']===1 && $registration['project_id']===FAMILYHUB_FCM_PROJECT_ID && (int)$registration['revision']===(int)$job['registration_revision'] && $registration['token_hash']===$job['token_hash'];
            $visible=$inbox && (new NativeFinanceAccess($this->container))->visible($inbox['scope_id'],$inbox['recipient_account_id'],str_starts_with($inbox['target_type'],'finance'));
            $status='cancelled'; $retryAfter=0; $coalesced=0;
            if (microtime(true)+20>$deadline) {
                $this->change('UPDATE familyhub_push_jobs SET state=\'pending\',next_attempt=?,lease_token=NULL,lease_until=NULL WHERE inbox_id=? AND device_id=? AND registration_revision=? AND lease_token=?',[time()+60,$job['inbox_id'],$job['device_id'],$job['registration_revision'],$lease]);
                return ['status'=>'retry','coalesced'=>0];
            }
            if ($valid && $visible && ($settings['push'] ?? false) && (int)$job['expires_at']>time() && (int)$job['attempts']<=5) {
                $newer=$this->one('SELECT j.inbox_id FROM familyhub_push_jobs j JOIN familyhub_inbox i ON i.id=j.inbox_id WHERE j.device_id=? AND j.registration_revision=? AND j.state IN (\'pending\',\'processing\',\'sent\') AND j.inbox_id>? AND i.recipient_account_id=? AND i.scope_id=? AND i.group_key=? AND i.kind=? AND i.category=? AND i.audience=? ORDER BY j.inbox_id DESC LIMIT 1',[$job['device_id'],$job['registration_revision'],$job['inbox_id'],$inbox['recipient_account_id'],$inbox['scope_id'],$inbox['group_key'],$inbox['kind'],$inbox['category'],$inbox['audience']]);
                if ($newer) {
                    $this->change('UPDATE familyhub_push_jobs SET state=\'coalesced\',lease_token=NULL,lease_until=NULL WHERE inbox_id=? AND device_id=? AND registration_revision=? AND lease_token=?',[$job['inbox_id'],$job['device_id'],$job['registration_revision'],$lease]);
                    return ['status'=>'coalesced','coalesced'=>0];
                }
                try {
                    $token=NativePushCrypto::decrypt($registration['token_cipher'],NativePushCrypto::aad($this->serverId(),$registration));
                    $result=$transport->send(['token'=>$token,'accountId'=>$registration['account_id'],'inboxId'=>(int)$inbox['id'],'groupKey'=>$inbox['group_key'],'kind'=>$inbox['kind'],'language'=>$registration['language'],'platform'=>$registration['platform'],'sound'=>(bool)($settings['sound'] ?? false),'expiresAt'=>(int)$job['expires_at']],$this->serverId());
                    $status=$result['status']==='accepted' ? 'accepted' : ($result['status']==='retry' && (int)$job['attempts']<5 ? 'retry' : 'cancelled');
                    $retryAfter=(int)($result['retryAfter'] ?? 0);
                    if ($result['status']==='unregistered') { (new NativePushService($this->container))->revokeDevice($device['id']); }
                } catch (\Throwable $error) { $status=(int)$job['attempts']<5 ? 'retry' : 'cancelled'; }
            } elseif ($device && !$sessionValid) {
                (new NativePushService($this->container))->revokeDevice($device['id']);
            }
            $state=$status==='accepted' ? 'sent' : ($status==='retry' ? 'pending' : 'cancelled');
            $this->change('UPDATE familyhub_push_jobs SET state=?,next_attempt=?,sent_at=?,lease_token=NULL,lease_until=NULL WHERE inbox_id=? AND device_id=? AND registration_revision=? AND lease_token=?',[$state,time()+max(min(3600,60*(2**(int)$job['attempts'])),$retryAfter),$status==='accepted' ? time() : null,$job['inbox_id'],$job['device_id'],$job['registration_revision'],$lease]);
            if ($status==='accepted') {
                $older=$this->many('SELECT j.inbox_id FROM familyhub_push_jobs j JOIN familyhub_inbox i ON i.id=j.inbox_id WHERE j.device_id=? AND j.registration_revision=? AND j.state=\'pending\' AND j.inbox_id<? AND i.recipient_account_id=? AND i.scope_id=? AND i.group_key=? AND i.kind=? AND i.category=? AND i.audience=? ORDER BY j.inbox_id LIMIT 100',[$job['device_id'],$job['registration_revision'],$job['inbox_id'],$inbox['recipient_account_id'],$inbox['scope_id'],$inbox['group_key'],$inbox['kind'],$inbox['category'],$inbox['audience']]);
                foreach ($older as $row) { $coalesced+=$this->change('UPDATE familyhub_push_jobs SET state=\'coalesced\' WHERE inbox_id=? AND device_id=? AND registration_revision=? AND state=\'pending\'',[$row['inbox_id'],$job['device_id'],$job['registration_revision']]); }
            }
            return ['status'=>$status,'coalesced'=>$coalesced];
        });
    }
}
