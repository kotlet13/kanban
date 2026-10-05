<?php
namespace Kanboard\Plugin\FamilyHub\Model;

class NativePushService extends NativeDatabase
{
    public function wire($row)
    {
        $active = $row && (int)$row['active'] === 1;
        return ['registered'=>(bool)$active,'platform'=>$active ? $row['platform'] : null,'language'=>$active ? $row['language'] : null,'revision'=>$row ? (int)$row['revision'] : 0,'updatedAt'=>$row ? gmdate('Y-m-d\TH:i:s\Z',(int)$row['updated_at']) : null];
    }

    public function revokeDevice($deviceId)
    {
        $this->change('UPDATE familyhub_push_registrations SET active=0,token_hash=NULL,token_cipher=NULL,revision=revision+1,updated_at=? WHERE device_id=? AND active=1', [time(),$deviceId]);
        $this->change('UPDATE familyhub_push_jobs SET state=\'cancelled\',lease_token=NULL,lease_until=NULL WHERE device_id=? AND state IN (\'pending\',\'processing\')', [$deviceId]);
    }

    public function execute($operation, array $params)
    {
        $this->rate([['push-ip:'.$this->ip,120,60]]);
        return $this->transaction(function () use ($operation,$params) {
            $actor=$this->actor(); $device=$actor['device']['id']; $account=$actor['user']['account_id'];
            $row=$this->one('SELECT * FROM familyhub_push_registrations WHERE device_id=?'.$this->lockSuffix(), [$device]);
            if ($operation === 'push.state') { $this->fields($params,[]); return ['registration'=>$this->wire($row)]; }
            if ($operation === 'push.unregister') {
                $this->fields($params,[],['expectedRevision']);
                if (isset($params['expectedRevision']) && (!is_int($params['expectedRevision']) || $params['expectedRevision'] < 0)) { throw new NativeError('validation_error'); }
                // Lost-response retry is safe only while currently unregistered.
                if ($row && (int)$row['active'] === 1) { $this->expected($params,$row); $this->revokeDevice($device); }
                $row=$this->one('SELECT * FROM familyhub_push_registrations WHERE device_id=?', [$device]);
                return ['registration'=>$this->wire($row)];
            }
            if ($operation !== 'push.register') { throw new NativeError('unsupported_operation',404); }
            if (!NativeFcmConfig::configured()) { throw new NativeError('push_unavailable',503); }
            $this->fields($params,['token','platform','language'],['expectedRevision','projectId']);
            if (isset($params['projectId']) && $params['projectId'] !== FAMILYHUB_FCM_PROJECT_ID) { throw new NativeError('push_project_mismatch',409); }
            if (!is_string($params['token']) || !preg_match('/^[\x21-\x7e]{1,4096}$/D',$params['token']) || !in_array($params['platform'],['android','ios'],true) || !in_array($params['language'],['sl','en'],true) || isset($params['expectedRevision']) && (!is_int($params['expectedRevision']) || $params['expectedRevision'] < 0)) { throw new NativeError('validation_error'); }
            $hash=hash('sha256',$params['token']);
            if ($row && (int)$row['active'] === 1 && hash_equals($row['token_hash'],$hash) && $row['platform'] === $params['platform'] && $row['language'] === $params['language'] && $row['project_id'] === FAMILYHUB_FCM_PROJECT_ID) { return ['registration'=>$this->wire($row)]; }
            $this->expected($params,$row);
            if ($this->one('SELECT device_id FROM familyhub_push_registrations WHERE token_hash=? AND device_id<>?',[$hash,$device])) { throw new NativeError('push_token_bound',409); }
            $revision=($row ? (int)$row['revision'] : 0)+1;
            $data=['device_id'=>$device,'account_id'=>$account,'revision'=>$revision];
            $cipher=NativePushCrypto::encrypt($params['token'],NativePushCrypto::aad($this->serverId(),$data));
            $this->change('UPDATE familyhub_push_jobs SET state=\'cancelled\',lease_token=NULL,lease_until=NULL WHERE device_id=? AND state IN (\'pending\',\'processing\')',[$device]);
            if ($row) {
                $this->change('UPDATE familyhub_push_registrations SET account_id=?,token_hash=?,token_cipher=?,project_id=?,platform=?,language=?,revision=?,active=1,updated_at=? WHERE device_id=?',[$account,$hash,$cipher,FAMILYHUB_FCM_PROJECT_ID,$params['platform'],$params['language'],$revision,time(),$device]);
            } else {
                $this->change('INSERT INTO familyhub_push_registrations(device_id,account_id,token_hash,token_cipher,project_id,platform,language,revision,active,updated_at) VALUES(?,?,?,?,?,?,?,?,1,?)',[$device,$account,$hash,$cipher,FAMILYHUB_FCM_PROJECT_ID,$params['platform'],$params['language'],$revision,time()]);
            }
            return ['registration'=>$this->wire($this->one('SELECT * FROM familyhub_push_registrations WHERE device_id=?',[$device]))];
        },true);
    }

    private function expected(array $params,$row)
    {
        if (isset($params['expectedRevision']) && $params['expectedRevision'] !== ($row ? (int)$row['revision'] : 0)) { throw new NativeError('push_conflict',409,['registration'=>$this->wire($row)]); }
    }
}
