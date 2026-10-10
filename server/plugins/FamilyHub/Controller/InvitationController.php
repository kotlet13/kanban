<?php
namespace Kanboard\Plugin\FamilyHub\Controller;

use Kanboard\Controller\BaseController;
use Kanboard\Plugin\FamilyHub\Model\NativeEmailInvitationService;

/** The token is a fragment: PHP, reverse-proxy access logs and GET never consume it. */
class InvitationController extends BaseController
{
    public function show()
    {
        if (session_status()===PHP_SESSION_ACTIVE) { session_abort(); }
        $nonce=base64_encode(random_bytes(18));
        $this->response->withHeader('Cache-Control','no-store')->withHeader('Referrer-Policy','no-referrer')
            ->withHeader('X-Content-Type-Options','nosniff')->withHeader('X-Frame-Options','DENY')
            ->withHeader('Content-Security-Policy',"default-src 'none'; script-src 'nonce-$nonce'; style-src 'nonce-$nonce'; base-uri 'none'; form-action 'none'; frame-ancestors 'none'");
        try {
            if (($_SERVER['REQUEST_METHOD']??'')!=='GET' || !defined('FAMILYHUB_ENABLE_NATIVE_API') || FAMILYHUB_ENABLE_NATIVE_API!==true) { throw new \RuntimeException(); }
            if (!NativeApiController::secureTransport($_SERVER) && !(defined('FAMILYHUB_DEVELOPMENT_ENVIRONMENT') && FAMILYHUB_DEVELOPMENT_ENVIRONMENT===true)) { throw new \RuntimeException(); }
            $server=NativeEmailInvitationService::publicUrl($this->configModel->get('application_url'));
            $serverJson=json_encode($server,JSON_HEX_TAG|JSON_HEX_AMP|JSON_HEX_APOS|JSON_HEX_QUOT|JSON_THROW_ON_ERROR);
            $html=<<<HTML
<!doctype html><html lang="sl"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><meta name="referrer" content="no-referrer"><title>Povabilo v Jivie</title>
<style nonce="$nonce">[hidden]{display:none!important}:root{color-scheme:light dark;font:16px system-ui,sans-serif}body{margin:0;background:#f5f6f8;color:#26313d}main{max-width:480px;margin:8vh auto;padding:30px;border-radius:20px;background:white;box-shadow:0 8px 40px #25334914}h1{font-size:28px}p{line-height:1.55}a,button{display:block;width:100%;box-sizing:border-box;margin:14px 0;padding:14px;border-radius:10px;font:inherit;text-align:center;text-decoration:none;background:#2563eb;color:white;border:0;cursor:pointer}button{background:#e9eef5;color:#26313d}.server{font-size:14px;overflow-wrap:anywhere}#status{font-size:14px;min-height:1.5em}@media(max-width:560px){main{margin:24px;padding:24px}}@media(prefers-color-scheme:dark){body{background:#151b23;color:#e8edf5}main{background:#222b37}button{background:#344256;color:#e8edf5}}</style>
<main><h1>Jivie</h1><h2>Povabilo v prostor</h2><p>V aplikaciji preverite pošiljatelja, prostor in vlogo. Prijavite se ali ustvarite račun, nato povabilo izrecno sprejmite.</p><p class="server">Strežnik: <span id="server"></span></p><a id="open" hidden>Odpri v aplikaciji</a><button id="copy" hidden>Kopiraj povezavo</button><button id="code" hidden>Kopiraj kodo povabila</button><p id="status" role="status">Povabilo nima veljavne kode.</p><p>Če se aplikacija ne odpre, kopirajte povezavo in jo vnesite v Jivie pri sprejemu povabila. Samo odprtje povezave ne dodeli dostopa.</p></main>
<script nonce="$nonce">(()=>{const server=$serverJson;document.getElementById('server').textContent=server;const token=new URLSearchParams(location.hash.slice(1)).get('token');if(!/^fhi[23]_[a-f0-9]{64}$/.test(token||''))return;const link='jivie://invite?server='+encodeURIComponent(server)+'&token='+encodeURIComponent(token)+'&v='+token.charAt(3);const open=document.getElementById('open');open.href=link;open.hidden=false;document.getElementById('status').textContent='Povabilo je pripravljeno za odprtje v aplikaciji.';for(const [id,value] of [['copy',link],['code',token]]){const button=document.getElementById(id);button.hidden=false;button.onclick=async()=>{try{await navigator.clipboard.writeText(value);document.getElementById('status').textContent='Kopirano.';}catch(_){const area=document.createElement('textarea');area.value=value;area.readOnly=true;document.querySelector('main').append(area);area.focus();area.select();document.getElementById('status').textContent='Kopirajte označeno besedilo.';}};}})();</script></html>
HTML;
            if (($_GET['language']??'sl')==='en') {
                $html=strtr($html,[
                    '<html lang="sl">'=>'<html lang="en">','Povabilo v Jivie'=>'Invitation to Jivie','Povabilo v prostor'=>'Space invitation',
                    'V aplikaciji preverite pošiljatelja, prostor in vlogo. Prijavite se ali ustvarite račun, nato povabilo izrecno sprejmite.'=>'Review the inviter, space and role in the app. Sign in or create an account, then explicitly accept the invitation.',
                    'Strežnik:'=>'Server:','Odpri v aplikaciji'=>'Open in the app','Kopiraj povezavo'=>'Copy link','Kopiraj kodo povabila'=>'Copy invitation code',
                    'Povabilo nima veljavne kode.'=>'The invitation has no valid code.',
                    'Če se aplikacija ne odpre, kopirajte povezavo in jo vnesite v Jivie pri sprejemu povabila. Samo odprtje povezave ne dodeli dostopa.'=>'If the app does not open, copy the link and paste it into the invitation screen in Jivie. Opening a link does not grant access.',
                    'Povabilo je pripravljeno za odprtje v aplikaciji.'=>'The invitation is ready to open in the app.','Kopirano.'=>'Copied.','Kopirajte označeno besedilo.'=>'Copy the selected text.'
                ]);
            }
            $this->response->withHeader('Content-Type','text/html; charset=utf-8')->withBody($html)->send();
        } catch (\Throwable $ignored) {
            $this->response->withStatusCode(503)->withHeader('Content-Type','text/plain; charset=utf-8')->withBody('Povabila trenutno niso na voljo.')->send();
        }
    }
}
