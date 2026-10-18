<?php
namespace Kanboard\Plugin\FamilyHub\Model;

/** No global BCC, core queue, URLs or inbox preferences for security mail. */
class NativeAccountMailTransport
{
    public static function securityMessage($kind, $language)
    {
        $labels = [
            'crypto.initialized'=>['Zaščita računa je pripravljena.','Account protection has been prepared.'],
            'crypto.deviceAdded'=>['Potrjena je nova naprava.','A new device has been approved.'],
            'crypto.deviceRevoked'=>['Dostop naprave je preklican.','A device has been revoked.'],
            'auth.resetRequested'=>['Zahtevana je bila ponastavitev prijavnega gesla.','A login password reset was requested.'],
            'auth.resetCompleted'=>['Prijavno geslo je bilo ponastavljeno.','The login password was reset.'],
            'crypto.recoveryStarted'=>['Začela se je obnova dostopa.','Account access recovery has started.'],
            'crypto.recoveryCompleted'=>['Obnova dostopa je zaključena.','Account access recovery has completed.'],
        ];
        if (!isset($labels[$kind])) {
            throw new NativeError('validation_error');
        }
        $sl='Na vašem računu Jivie se je zgodila varnostna sprememba. '.$labels[$kind][0].' Odprite aplikacijo in preverite naprave.' . "\n\n" . 'To obvestilo ne vsebuje obnovitvenega ključa.';
        $en='There was a security change to your Jivie account. '.$labels[$kind][1].' Open the app and review your devices.' . "\n\n" . 'This notice contains no recovery key.';
        return match ($language) {
            'sl'=>['Varnost računa Jivie',$sl],
            'en'=>['Jivie account security',$en],
            default=>['Varnost računa Jivie / Jivie account security',$sl."\n\n---\n\n".$en],
        };
    }

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
            $project=($details['scopeKind']??'')==='project';
            $viewer=($details['role']??'member')==='viewer';
            $modern=in_array(($details['contractVersion']??2),[3,4],true);
            $scopeLabel=$project?($english?'project ':'projekt '):($english?'space ':'prostor ');
            $access=$viewer?($english?'You can view this '.$scopeLabel.'in Jivie.':'V Jivie si lahko ogledaš ta '.trim($scopeLabel).'.'):
                ($english?'You can collaborate in this '.$scopeLabel.'in Jivie.':'V Jivie lahko sodelujete v tem '.($project?'projektu.':'prostoru.'));
            if ($modern) {
                $access.="\n".($english?'Access: ':'Dostop: ').($viewer?($english?'View only':'Samo ogled'):($english?'Full access (including deleting content and managing members)':'Polni dostop (tudi brisanje vsebine in upravljanje članov)'));
            }
            $expiry=(int)($details['expiresAt']??0);
            $formatted=$expiry>0?gmdate($english?'Y-m-d H:i':'d. m. Y H:i',$expiry).' UTC':'';
            $body=($details['inviterName']??'Jivie').($english?' invites you to ':' te vabi v ').$scopeLabel.($details['scopeName']??'Jivie')."\n\n".
                $access."\n\n".
                ($english?'Open invitation:':'Odpri povabilo:')."\n".$code."\n\n".
                ($english?'Review the access and choose whether to join. If you need an account, create one there.':'Preveri dostop in se odloči, ali se pridružiš. Če še nimaš računa, ga ustvariš tam.').
                ($formatted!==''?"\n\n".($english?'Valid until ':'Velja do ').$formatted.'.':'');
        }
        if ($purpose === 'security') {
            [$title,$body]=self::securityMessage($details['eventKind'] ?? '',$language);
        }
        $message = new \Swift_Message($title);
        $message->setId('familyhub.account.'.$id.'@'.substr(strrchr($config['from'], '@'), 1));
        $message->setFrom([$config['from'] => 'Jivie'])->setTo([$recipient])->setBody($body, 'text/plain', 'UTF-8');
        try { if ((new \Swift_Mailer($transport))->send($message) !== 1) { throw new NativeError('email_unavailable', 503); } }
        finally { try { $transport->stop(); } catch (\Throwable $ignored) {} }
        return ['accepted' => true];
    }
}
