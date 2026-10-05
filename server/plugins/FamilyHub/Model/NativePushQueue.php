<?php
namespace Kanboard\Plugin\FamilyHub\Model;

/** Canonical inbox references and immutable registration generation snapshots. */
class NativePushQueue extends NativeDatabase
{
    public function enqueue($inboxId, $accountId)
    {
        if (!NativeFcmConfig::configured()) { return; }
        $insert=$this->sqlite ? 'INSERT OR IGNORE' : 'INSERT IGNORE';
        foreach ($this->many('SELECT r.* FROM familyhub_push_registrations r JOIN familyhub_devices d ON d.id=r.device_id AND d.account_id=r.account_id WHERE r.account_id=? AND r.active=1 AND d.revoked_at IS NULL AND d.expires_at>?',[$accountId,time()]) as $row) {
            if ($row['project_id'] !== FAMILYHUB_FCM_PROJECT_ID) { continue; }
            $this->change($insert.' INTO familyhub_push_jobs(inbox_id,device_id,registration_revision,token_hash,state,attempts,next_attempt,expires_at) VALUES(?,?,?,?,\'pending\',0,?,?)',[$inboxId,$row['device_id'],$row['revision'],$row['token_hash'],time(),time()+86400]);
        }
    }

    public function run($limit=20, $transport=null)
    {
        if (!NativeFcmConfig::configured() || !defined('FAMILYHUB_ENABLE_NATIVE_API') || FAMILYHUB_ENABLE_NATIVE_API !== true) { throw new NativeError('push_unavailable',503); }
        if (!is_int($limit) || $limit<1 || $limit>50) { throw new NativeError('validation_error'); }
        $previousTimeout=$this->sqlite ? (int)$this->one('PRAGMA busy_timeout')['timeout'] : (int)$this->one('SELECT @@SESSION.innodb_lock_wait_timeout AS seconds')['seconds'];
        $this->pdo->exec($this->sqlite ? 'PRAGMA busy_timeout=5000' : 'SET SESSION innodb_lock_wait_timeout=5');
        try {
        $deadline=microtime(true)+40; $counts=['examined'=>0,'accepted'=>0,'retry'=>0,'cancelled'=>0,'coalesced'=>0];
        $transport=$transport ?? new NativeFcmTransport();
        $rows=$this->many('SELECT * FROM familyhub_push_jobs WHERE (state=\'pending\' AND next_attempt<=?) OR (state=\'processing\' AND lease_until<=?) ORDER BY next_attempt,inbox_id DESC LIMIT '.$limit,[time(),time()]);
        $worker=new NativePushWorker($this->container);
        foreach ($rows as $row) {
            // Reserve the worst-case OAuth+send duration before taking DB locks.
            if (microtime(true)+20>$deadline) { break; }
            $counts['examined']++;
            $lease=$this->transaction(function () use ($row) {
                $job=$this->one('SELECT * FROM familyhub_push_jobs WHERE inbox_id=? AND device_id=? AND registration_revision=?'.$this->lockSuffix(),[$row['inbox_id'],$row['device_id'],$row['registration_revision']]);
                if (!$job || !in_array($job['state'],['pending','processing'],true) || ($job['state']==='processing' && (int)$job['lease_until']>time()) || ($job['state']==='pending' && (int)$job['next_attempt']>time())) { return null; }
                $lease=bin2hex(random_bytes(16));
                $this->change('UPDATE familyhub_push_jobs SET state=\'processing\',attempts=attempts+1,lease_token=?,lease_until=? WHERE inbox_id=? AND device_id=? AND registration_revision=?',[$lease,time()+120,$row['inbox_id'],$row['device_id'],$row['registration_revision']]); return $lease;
            });
            if (!$lease) { continue; }
            $result=$worker->deliver($row,$lease,$transport,$deadline);
            $counts[$result['status']]++;
            $counts['coalesced']+=$result['coalesced'];
        }
        return $counts;
        } finally {
            $this->pdo->exec($this->sqlite ? 'PRAGMA busy_timeout='.$previousTimeout : 'SET SESSION innodb_lock_wait_timeout='.$previousTimeout);
        }
    }
}
