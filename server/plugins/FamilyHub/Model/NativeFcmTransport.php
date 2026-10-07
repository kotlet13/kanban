<?php
namespace Kanboard\Plugin\FamilyHub\Model;

/** Fixed Google endpoints. Injectable HTTP is a test seam, never server config. */
class NativeFcmTransport
{
    private $http;
    private $accessToken;
    private $expires = 0;
    public function __construct($http = null) { $this->http = $http; }

    private static function base64url($bytes) { return rtrim(strtr(base64_encode($bytes), '+/', '-_'), '='); }

    private function request($url, array $headers, $body)
    {
        if ($this->http) { return ($this->http)($url, $headers, $body); }
        $response = ''; $retryAfter = 0; $ch = curl_init($url);
        curl_setopt_array($ch, [CURLOPT_POST=>true,CURLOPT_POSTFIELDS=>$body,CURLOPT_HTTPHEADER=>$headers,CURLOPT_FOLLOWLOCATION=>false,CURLOPT_MAXREDIRS=>0,CURLOPT_PROTOCOLS=>CURLPROTO_HTTPS,CURLOPT_SSL_VERIFYPEER=>true,CURLOPT_SSL_VERIFYHOST=>2,CURLOPT_CONNECTTIMEOUT=>5,CURLOPT_TIMEOUT=>10,
            CURLOPT_WRITEFUNCTION=>function ($handle, $chunk) use (&$response) { if (strlen($response)+strlen($chunk)>65536) { return 0; } $response.=$chunk; return strlen($chunk); },
            CURLOPT_HEADERFUNCTION=>function ($handle, $line) use (&$retryAfter) { if (preg_match('/^Retry-After:\s*([0-9]+)\s*$/iD', $line, $m)) { $retryAfter=min(3600,(int)$m[1]); } return strlen($line); }]);
        $ok = curl_exec($ch); $status = (int)curl_getinfo($ch, CURLINFO_HTTP_CODE); curl_close($ch);
        return ['status'=>$ok === false ? 0 : $status, 'body'=>$response, 'retryAfter'=>$retryAfter];
    }

    private function token(array $credentials)
    {
        if ($this->accessToken && $this->expires > time()+60) { return $this->accessToken; }
        $header = self::base64url(json_encode(['alg'=>'RS256','typ'=>'JWT'], JSON_THROW_ON_ERROR));
        $claims = self::base64url(json_encode(['iss'=>$credentials['client_email'],'scope'=>'https://www.googleapis.com/auth/firebase.messaging','aud'=>'https://oauth2.googleapis.com/token','iat'=>time(),'exp'=>time()+3600], JSON_THROW_ON_ERROR));
        if (!openssl_sign($header.'.'.$claims, $signature, $credentials['private_key'], OPENSSL_ALGO_SHA256)) { throw new NativeError('push_unavailable', 503); }
        $response = $this->request('https://oauth2.googleapis.com/token', ['Content-Type: application/x-www-form-urlencoded'], http_build_query(['grant_type'=>'urn:ietf:params:oauth:grant-type:jwt-bearer','assertion'=>$header.'.'.$claims.'.'.self::base64url($signature)], '', '&', PHP_QUERY_RFC3986));
        $json = json_decode($response['body'], true);
        if ($response['status'] !== 200 || !is_array($json) || !is_string($json['access_token'] ?? null) || !preg_match('/^[\x21-\x7e]{1,4096}$/D', $json['access_token']) || ($json['token_type'] ?? null) !== 'Bearer' || !is_int($json['expires_in'] ?? null) || $json['expires_in'] < 60 || $json['expires_in'] > 3600) { throw new NativeError('push_unavailable', 503); }
        $this->accessToken = $json['access_token']; $this->expires = time()+$json['expires_in']; return $this->accessToken;
    }

    public static function message(array $job, $serverId)
    {
        $sound = $job['sound']; $en = $job['language'] === 'en';
        $group = hash('sha256', $job['accountId'].':'.$job['groupKey'].':'.$job['kind']);
        return ['token'=>$job['token'], 'notification'=>['title'=>'Jivie','body'=>$en ? 'You have a new notification.' : 'Imate novo obvestilo.'],
            'data'=>['type'=>'familyhub.inbox.v1','serverId'=>$serverId,'accountId'=>$job['accountId'],'notificationId'=>(string)$job['inboxId']],
            'android'=>['ttl'=>max(1,min(86400,$job['expiresAt']-time())).'s','notification'=>array_merge(['channel_id'=>$sound ? 'familyhub_push_sound_v1' : 'familyhub_push_silent_v1','tag'=>$group,'default_sound'=>$sound],$sound ? ['sound'=>'default'] : [])],
            'apns'=>['headers'=>['apns-push-type'=>'alert','apns-priority'=>'10','apns-expiration'=>(string)$job['expiresAt'],'apns-collapse-id'=>$group], 'payload'=>['aps'=>array_merge(['thread-id'=>$group], $sound ? ['sound'=>'default'] : [])]]];
    }

    public function send(array $job, $serverId)
    {
        $credentials = NativeFcmConfig::credentials();
        $response = $this->request('https://fcm.googleapis.com/v1/projects/'.$credentials['project_id'].'/messages:send', ['Content-Type: application/json','Authorization: Bearer '.$this->token($credentials)], json_encode(['message'=>self::message($job,$serverId)], JSON_THROW_ON_ERROR));
        $json = json_decode($response['body'], true);
        if ($response['status'] === 401) { $this->accessToken=null; $this->expires=0; }
        if ($response['status'] === 200 && is_array($json) && is_string($json['name'] ?? null) && preg_match('#^projects/'.preg_quote($credentials['project_id'],'#').'/messages/[A-Za-z0-9%:._~-]{1,256}$#D',$json['name'])) { return ['status'=>'accepted','retryAfter'=>0]; }
        $code = null;
        $details=is_array($json) && is_array($json['error'] ?? null) && is_array($json['error']['details'] ?? null) ? $json['error']['details'] : [];
        foreach ($details as $detail) { if (is_array($detail) && ($detail['@type'] ?? null) === 'type.googleapis.com/google.firebase.fcm.v1.FcmError') { $code=$detail['errorCode'] ?? null; } }
        if ($response['status'] === 404 && $code === 'UNREGISTERED') { return ['status'=>'unregistered','retryAfter'=>0]; }
        if ($code === 'SENDER_ID_MISMATCH' || $code === 'THIRD_PARTY_AUTH_ERROR') { return ['status'=>'rejected','retryAfter'=>0]; }
        // INVALID_ARGUMENT can describe a payload defect; do not erase tokens.
        $transient = $response['status'] === 0 || $response['status'] === 429 || $response['status'] >= 500 || $response['status'] === 401 || $response['status'] === 403;
        return ['status'=>$transient || $response['status'] === 200 ? 'retry' : 'rejected','retryAfter'=>min(3600,max(0,(int)($response['retryAfter'] ?? 0)))];
    }
}
