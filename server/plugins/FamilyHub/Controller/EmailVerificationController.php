<?php
namespace Kanboard\Plugin\FamilyHub\Controller;

use Kanboard\Controller\BaseController;
use Kanboard\Plugin\FamilyHub\Model\NativeAccountService;
use Kanboard\Plugin\FamilyHub\Model\NativeEmailInvitationService;
use Kanboard\Plugin\FamilyHub\Model\NativeError;

/** Fragment capability: GET renders only; explicit same-origin JSON POST consumes. */
class EmailVerificationController extends BaseController
{
    private function guard($method)
    {
        if (session_status()===PHP_SESSION_ACTIVE) { session_abort(); }
        $this->response->withHeader('Cache-Control','no-store')->withHeader('Referrer-Policy','no-referrer')->withHeader('X-Content-Type-Options','nosniff')->withHeader('X-Frame-Options','DENY');
        if (($_SERVER['REQUEST_METHOD']??'')!==$method) { throw new NativeError('method_not_allowed',405); }
        if (!defined('FAMILYHUB_ENABLE_NATIVE_API') || FAMILYHUB_ENABLE_NATIVE_API!==true) { throw new NativeError('email_unavailable',503); }
        if (!NativeApiController::secureTransport($_SERVER) && !(defined('FAMILYHUB_DEVELOPMENT_ENVIRONMENT') && FAMILYHUB_DEVELOPMENT_ENVIRONMENT===true)) { throw new NativeError('https_required',403); }
        return NativeEmailInvitationService::publicUrl($this->configModel->get('application_url'));
    }
    public function show()
    {
        try {
            $server=$this->guard('GET');
            $nonce=base64_encode(random_bytes(18));
            $this->response->withHeader('Content-Security-Policy',"default-src 'none'; script-src 'nonce-$nonce'; style-src 'nonce-$nonce'; connect-src 'self'; base-uri 'none'; form-action 'none'; frame-ancestors 'none'");
            $serverJson=json_encode($server,JSON_HEX_TAG|JSON_HEX_AMP|JSON_HEX_APOS|JSON_HEX_QUOT|JSON_THROW_ON_ERROR);
            $english=($_GET['language']??'sl')==='en';
            $strings=$english?['Confirm email','Open in Jivie','Confirm on this computer','Open the app to review your account, or explicitly confirm here. Opening this page does not confirm anything.','The link is invalid.','Email confirmed. Return to the open app; your progress is kept.','This link has expired, was already used or no longer matches the requested email. Use the latest message.','Account','Server','Verification is temporarily unavailable. Please try again.']:['Potrdi e-pošto','Odpri v Jivie','Potrdi na tem računalniku','V aplikaciji preveri račun ali izrecno potrdi tukaj. Samo odprtje te strani ne potrdi ničesar.','Povezava ni veljavna.','E-pošta je potrjena. Vrni se v odprto aplikacijo; napredek ostane ohranjen.','Povezava je potekla, je že uporabljena ali ne ustreza več zahtevanemu naslovu. Uporabi zadnje sporočilo.','Račun','Strežnik','Potrditev trenutno ni na voljo. Poskusi znova.'];
            $labels=json_encode($strings,JSON_HEX_TAG|JSON_HEX_AMP|JSON_HEX_APOS|JSON_HEX_QUOT|JSON_THROW_ON_ERROR);
            $lang=$english?'en':'sl';
            $html=<<<HTML
<!doctype html><html lang="$lang"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><meta name="referrer" content="no-referrer"><title>Jivie</title>
<style nonce="$nonce">[hidden]{display:none!important}body{font:16px system-ui,sans-serif;background:#f5f6f8;color:#26313d;margin:0}main{max-width:480px;margin:8vh auto;padding:28px;background:white;border-radius:20px}p{line-height:1.5;overflow-wrap:anywhere}a,button{display:block;box-sizing:border-box;width:100%;margin:14px 0;padding:14px;border:0;border-radius:10px;background:#2563eb;color:white;text-align:center;font:inherit;text-decoration:none;cursor:pointer}button{background:#e9eef5;color:#26313d}:focus-visible{outline:3px solid #e89d00;outline-offset:3px}@media(max-width:560px){main{margin:20px}}</style>
<main><h1 id="title"></h1><p id="description"></p><p id="server"></p><p id="account"></p><a id="open" hidden></a><button id="confirm" hidden></button><p id="status" role="status"></p></main>
<script nonce="$nonce">(()=>{const server=$serverJson,s=$labels;const el=id=>document.getElementById(id);el('title').textContent=s[0];el('description').textContent=s[3];el('server').textContent=s[8]+': '+server;el('status').textContent=s[4];const p=new URLSearchParams(location.hash.slice(1));if([...p.keys()].length!==4||!(p.get('email')||'').includes('@')||!/^fhv1_[a-f0-9]{64}$/.test(p.get('token')||'')||!['accountId','serverId'].every(k=>/^[a-f0-9-]{36}$/.test(p.get(k)||'')))return;const data=Object.fromEntries(p);el('account').textContent=s[7]+': '+data.email;el('open').textContent=s[1];el('open').href='jivie://verify-email?'+new URLSearchParams({server,...data});el('open').hidden=false;el('confirm').textContent=s[2];el('confirm').hidden=false;el('status').textContent='';el('confirm').onclick=async()=>{el('confirm').disabled=true;try{const url=new URL(location.href);url.hash='';url.searchParams.set('action','confirm');const response=await fetch(url,{method:'POST',credentials:'omit',headers:{'Content-Type':'application/json'},body:JSON.stringify(data)});const result=await response.json();if(!response.ok||result.verified!==true){el('status').textContent=result.error==='account_token_invalid'?s[6]:s[9];el('confirm').disabled=false;return;}el('status').textContent=s[5];el('open').hidden=true;el('confirm').hidden=true;history.replaceState(null,'',location.pathname+location.search);}catch(_){el('status').textContent=s[9];el('confirm').disabled=false;}};})();</script></html>
HTML;
            $this->response->withHeader('Content-Type','text/html; charset=utf-8')->withBody($html)->send();
        } catch (\Throwable $error) { $this->response->withStatusCode(503)->withBody('Email verification unavailable.')->send(); }
    }
    public function confirm()
    {
        try {
            $server=$this->guard('POST');
            $parts=parse_url($server);
            $origin=$parts['scheme'].'://'.$parts['host'].(isset($parts['port'])?':'.$parts['port']:'');
            if (($_SERVER['HTTP_ORIGIN']??'')!==$origin) { throw new NativeError('origin_not_allowed',403); }
            if (strtolower(trim(explode(';',$_SERVER['CONTENT_TYPE']??'')[0]))!=='application/json') { throw new NativeError('json_required',415); }
            $body=file_get_contents('php://input',false,null,0,2049);
            if (strlen($body)>2048) { throw new NativeError('request_too_large',413); }
            $params=json_decode($body,true,8,JSON_THROW_ON_ERROR);
            if (!is_array($params)) { throw new NativeError('invalid_request'); }
            $result=(new NativeAccountService($this->container,'',$_SERVER['REMOTE_ADDR']??'unknown'))->confirmLink($params);
            $this->response->json($result);
        } catch (NativeError $error) { $this->response->json(['error'=>$error->errorCode],$error->status); }
        catch (\JsonException $error) { $this->response->json(['error'=>'invalid_request'],422); }
        catch (\Throwable $error) { $this->response->json(['error'=>'email_unavailable'],503); }
    }
}
