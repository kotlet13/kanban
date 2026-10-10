<?php
namespace Kanboard\Plugin\FamilyHub\Model;

/** No global BCC, core queue, URLs or inbox preferences for security mail. */
class NativeAccountMailTransport
{
    public function send($recipient, $purpose, $code, $id, $language, array $details = [])
    {
        $config = NativeSmtpTransport::configuration();
        if (!$config || !filter_var($recipient, FILTER_VALIDATE_EMAIL) || ($config['localPlain'] && !str_ends_with(strtolower($recipient), '.invalid'))) { throw new NativeError('email_unavailable', 503); }
        $transport = new NativeVerifiedSmtp($config['host'], $config['port'], $config['encryption'] === 'none' ? null : $config['encryption']);
        $transport->setTimeout(10)->setStreamOptions(['ssl' => ['allow_self_signed' => false, 'verify_peer' => true, 'verify_peer_name' => true, 'peer_name' => $config['host']]]);
        if (defined('FAMILYHUB_SMTP_USERNAME')) { $transport->setUsername(FAMILYHUB_SMTP_USERNAME); }
        if (defined('FAMILYHUB_SMTP_PASSWORD')) { $transport->setPassword(FAMILYHUB_SMTP_PASSWORD); }
        $english = $language === 'en';
        $title = $purpose === 'verify' ? ($english ? 'Confirm your email' : 'Potrdite e-pošto') : ($english ? 'Reset your password' : 'Ponastavite geslo');
        $body = ($english ? 'Enter this one-time code in the Jivie app:' : 'To enkratno kodo vnesite v aplikacijo Jivie:')."\n\n".$code."\n\n".($english ? 'If you did not request this, ignore the message.' : 'Če tega niste zahtevali, sporočilo prezrite.');
        if ($purpose === 'invitation') {
            $title=$english?'Invitation to Jivie':'Povabilo v Jivie';
            $body=($details['inviterName']??'Jivie').($english?' invited you to ':' vas vabi v ').($details['scopeName']??'Jivie')."\n".
                ($english?'Role: ':'Vloga: ').(($details['role']??'member')==='viewer'?($english?'Viewer':'Ogledovalec'):($english?'Member':'Član'))."\n\n".
                ($english?'Open this invitation:':'Odprite povabilo:')."\n".$code."\n\n".
                ($english?'Sign in or create an account, then explicitly accept the invitation. Opening this link does not grant access.':'Prijavite se ali ustvarite račun in nato izrecno sprejmite povabilo. Odprtje povezave ne dodeli dostopa.');
        }
        $message = new \Swift_Message($title);
        $message->setId('familyhub.account.'.$id.'@'.substr(strrchr($config['from'], '@'), 1));
        $message->setFrom([$config['from'] => 'Jivie'])->setTo([$recipient])->setBody($body, 'text/plain', 'UTF-8');
        try { if ((new \Swift_Mailer($transport))->send($message) !== 1) { throw new NativeError('email_unavailable', 503); } }
        finally { try { $transport->stop(); } catch (\Throwable $ignored) {} }
        return ['accepted' => true];
    }
}
