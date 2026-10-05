<?php
namespace Kanboard\Plugin\FamilyHub\Model;

/** No global BCC, core queue, URLs or inbox preferences for security mail. */
class NativeAccountMailTransport
{
    public function send($recipient, $purpose, $code, $id, $language)
    {
        $config = NativeSmtpTransport::configuration();
        if (!$config || !filter_var($recipient, FILTER_VALIDATE_EMAIL) || ($config['localPlain'] && !str_ends_with(strtolower($recipient), '.invalid'))) { throw new NativeError('email_unavailable', 503); }
        $transport = new NativeVerifiedSmtp($config['host'], $config['port'], $config['encryption'] === 'none' ? null : $config['encryption']);
        $transport->setTimeout(10)->setStreamOptions(['ssl' => ['allow_self_signed' => false, 'verify_peer' => true, 'verify_peer_name' => true, 'peer_name' => $config['host']]]);
        if (defined('FAMILYHUB_SMTP_USERNAME')) { $transport->setUsername(FAMILYHUB_SMTP_USERNAME); }
        if (defined('FAMILYHUB_SMTP_PASSWORD')) { $transport->setPassword(FAMILYHUB_SMTP_PASSWORD); }
        $english = $language === 'en';
        $title = $purpose === 'verify' ? ($english ? 'Confirm your email' : 'Potrdite e-pošto') : ($english ? 'Reset your password' : 'Ponastavite geslo');
        $body = ($english ? 'Enter this one-time code in the Vsakdan app:' : 'To enkratno kodo vnesite v aplikacijo Vsakdan:')."\n\n".$code."\n\n".($english ? 'If you did not request this, ignore the message.' : 'Če tega niste zahtevali, sporočilo prezrite.');
        $message = new \Swift_Message($title);
        $message->setId('familyhub.account.'.$id.'@'.substr(strrchr($config['from'], '@'), 1));
        $message->setFrom([$config['from'] => 'Vsakdan'])->setTo([$recipient])->setBody($body, 'text/plain', 'UTF-8');
        try { if ((new \Swift_Mailer($transport))->send($message) !== 1) { throw new NativeError('email_unavailable', 503); } }
        finally { try { $transport->stop(); } catch (\Throwable $ignored) {} }
        return ['accepted' => true];
    }
}
