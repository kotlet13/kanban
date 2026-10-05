<?php
namespace Kanboard\Plugin\FamilyHub\Model;

/** Swift is already pinned inside Kanboard; bypass core queue/BCC/error swallowing. */
class NativeSmtpTransport
{
    public static function configuration()
    {
        $host = defined('FAMILYHUB_SMTP_HOST') ? FAMILYHUB_SMTP_HOST : '';
        $port = defined('FAMILYHUB_SMTP_PORT') ? FAMILYHUB_SMTP_PORT : 465;
        $encryption = defined('FAMILYHUB_SMTP_ENCRYPTION') ? FAMILYHUB_SMTP_ENCRYPTION : 'ssl';
        $from = defined('FAMILYHUB_SMTP_FROM') ? FAMILYHUB_SMTP_FROM : '';
        $localPlain = defined('FAMILYHUB_DEVELOPMENT_MODE') && FAMILYHUB_DEVELOPMENT_MODE === true && defined('FAMILYHUB_SMTP_ALLOW_LOCAL_PLAINTEXT') && FAMILYHUB_SMTP_ALLOW_LOCAL_PLAINTEXT === true && in_array($host, ['127.0.0.1', '::1'], true);
        if (!is_string($host) || $host === '' || preg_match('/[\s\x00-\x1f\/:]/', $host) && $host !== '::1' || !is_int($port) || $port < 1 || $port > 65535 || !is_string($from) || !filter_var($from, FILTER_VALIDATE_EMAIL) || (!in_array($encryption, ['ssl', 'tls'], true) && !($localPlain && $encryption === 'none'))) { return null; }
        return ['host' => $host, 'port' => $port, 'encryption' => $encryption, 'from' => $from, 'localPlain' => $localPlain];
    }

    public static function configured() { return self::configuration() !== null; }

    public function send($recipient, $inboxId, $accountId)
    {
        $config = self::configuration();
        if (!$config || !filter_var($recipient, FILTER_VALIDATE_EMAIL) || ($config['localPlain'] && !str_ends_with(strtolower($recipient), '.invalid'))) { throw new NativeError('smtp_unavailable', 503); }
        $transport = new NativeVerifiedSmtp($config['host'], $config['port'], $config['encryption'] === 'none' ? null : $config['encryption']);
        $transport->setTimeout(10)->setStreamOptions(['ssl' => ['allow_self_signed' => false, 'verify_peer' => true, 'verify_peer_name' => true, 'peer_name' => $config['host']]]);
        if (defined('FAMILYHUB_SMTP_USERNAME')) { $transport->setUsername(FAMILYHUB_SMTP_USERNAME); }
        if (defined('FAMILYHUB_SMTP_PASSWORD')) { $transport->setPassword(FAMILYHUB_SMTP_PASSWORD); }
        $domain = substr(strrchr($config['from'], '@'), 1);
        $message = new \Swift_Message('Novo obvestilo v aplikaciji');
        $message->setId('familyhub.'.$inboxId.'.'.substr(hash('sha256', $accountId), 0, 16).'@'.$domain);
        $message->setFrom([$config['from'] => 'FamilyHub'])->setTo([$recipient]);
        $body = "V skupnem prostoru je novo obvestilo. Odprite center obvestil v aplikaciji.\n";
        if (defined('FAMILYHUB_APP_URL') && is_string(FAMILYHUB_APP_URL)) {
            $url = parse_url(FAMILYHUB_APP_URL);
            if ($url && ($url['scheme'] ?? '') === 'https' && !isset($url['user']) && !isset($url['pass']) && !isset($url['fragment'])) {
                $body .= FAMILYHUB_APP_URL."\n";
            }
        }
        $message->setBody($body, 'text/plain', 'UTF-8');
        try { if ((new \Swift_Mailer($transport))->send($message) !== 1) { throw new NativeError('smtp_not_accepted', 503); } }
        finally { try { $transport->stop(); } catch (\Throwable $ignored) {} }
        return ['accepted' => true, 'messageId' => $message->getId()];
    }
}
