<?php
namespace Kanboard\Plugin\FamilyHub\Controller;

use Kanboard\Controller\BaseController;
use Kanboard\Core\Controller\AccessForbiddenException;
use Kanboard\Plugin\FamilyHub\Model\NativeService;
use Kanboard\Plugin\FamilyHub\Model\NativeError;
use Kanboard\Plugin\FamilyHub\Model\NativeAccountDeletionService;

/** Same-origin self-service without the mobile app. Passwords are never in URLs. */
class AccountDeletionController extends BaseController
{
    private function guard($post=false)
    {
        $this->response->withHeader('Cache-Control','no-store')->withHeader('Referrer-Policy','no-referrer')->withHeader('X-Content-Type-Options','nosniff')->withHeader('Content-Security-Policy',"default-src 'none'; style-src 'unsafe-inline'; form-action 'self'; frame-ancestors 'none'; base-uri 'none'");
        if (!NativeApiController::secureTransport($_SERVER) && !(defined('FAMILYHUB_DEVELOPMENT_ENVIRONMENT') && FAMILYHUB_DEVELOPMENT_ENVIRONMENT===true)) { throw new AccessForbiddenException(); }
        if ($post) { if (!$this->request->isPost()) { throw new AccessForbiddenException(); } $this->checkCSRFForm(); }
    }
    public function index()
    {
        $this->guard();$this->render();
    }
    public function preview()
    {
        $this->guard(true);
        // Flush the CSRF session before native SQL begins; no PHP shutdown write
        // may race SQLite or re-create an authenticated session after deletion.
        $csrf=$this->helper->form->csrf();
        if (session_status()===PHP_SESSION_ACTIVE) { session_write_close(); }
        try {
            $service=new NativeService($this->container);
            $session=$service->dispatch('auth.login',['username'=>$this->request->getRawValue('username'),'password'=>$this->request->getRawValue('password'),'otp'=>$this->request->getRawValue('otp'),'deviceName'=>'Jivie account deletion website'],'',$_SERVER['REMOTE_ADDR']??'unknown');
            $plan=$service->dispatch('account.deletion.preview',['policyVersion'=>3],'Bearer '.$session['token'],$_SERVER['REMOTE_ADDR']??'unknown');
            $this->render(['plan'=>$plan,'token'=>$session['token'],'operationId'=>$this->uuid(),'receiptToken'=>bin2hex(random_bytes(32))],null,200,$csrf);
        } catch (NativeError $error) { $this->render(null,$error->errorCode,$error->status,$csrf); }
        catch (\Throwable $error) { $this->render(null,'server_error',500,$csrf); }
    }
    public function confirm()
    {
        $this->guard(true);$csrf=$this->helper->form->csrf();
        if (session_status()===PHP_SESSION_ACTIVE) { session_write_close(); }
        $input=$this->request->getValues();
        try {
            $transfers=[];$deletions=[];$resolutions=[];
            foreach ($input['owners']??[] as $sid=>$successor) { if ($successor==='deleteOwnedScope') { $deletions[]=$sid; } elseif ($successor!=='') { $transfers[]=['scopeId'=>$sid,'successorAccountId'=>$successor]; } }
            foreach ($input['structures']??[] as $value) { $p=explode(':',$value);if(!in_array(count($p),[2,3],true)){throw new NativeError('validation_error');}$action=$p[2]??'preserveStructure';if(!in_array($action,['preserveStructure','detachOrganization'],true)){throw new NativeError('validation_error');}$resolutions[]=['scopeId'=>$p[0],'recordId'=>$p[1],'action'=>$action]; }
            // Older already-issued forms used policy2. New forms carry the
            // exact preview version, including across an unknown-result retry.
            $policy = $input['policyVersion'] ?? '2';
            if (!is_string($policy) || !preg_match('/^[123]$/D', $policy)) {
                throw new NativeError('validation_error');
            }
            $params=['policyVersion'=>(int)$policy,'operationId'=>$input['operationId']??null,'receiptToken'=>$input['receiptToken']??null,'previewHash'=>$input['previewHash']??null,'password'=>$input['password']??null,'otp'=>$input['otp']??null,'confirmation'=>$input['confirmation']??null,'ownershipTransfers'=>$transfers,'ownedScopeDeletions'=>$deletions,'resolutions'=>$resolutions];
            $result=(new NativeService($this->container))->dispatch('account.deletion.confirm',$params,'Bearer '.($input['token']??''),$_SERVER['REMOTE_ADDR']??'unknown');
            $this->render(['result'=>$result,'operationId'=>$params['operationId'],'receiptToken'=>$params['receiptToken']],null,200,$this->anonymousCsrf($csrf));
        } catch (NativeError $error) {
            // Lost response followed by a form POST replay must still reveal the
            // receipt outcome, without restoring the deleted bearer or password.
            if (in_array($error->errorCode,['device_revoked','auth_required'],true)) {
                try {
                    $statusParams=['operationId'=>$input['operationId']??null,'receiptToken'=>$input['receiptToken']??null];
                    $result=(new NativeService($this->container))->dispatch('account.deletion.status',$statusParams,'',$_SERVER['REMOTE_ADDR']??'unknown');
                    if ($result['deleted'] || $result['cleanupPending']) { $this->render(['result'=>$result]+$statusParams,null,200,$this->anonymousCsrf($csrf));return; }
                } catch (NativeError $ignored) { }
            }
            $this->render(null,$error->errorCode,$error->status,$csrf);
        } catch (\Throwable $error) { $this->render(null,'server_error',500,$csrf); }
    }
    public function status()
    {
        $this->guard(true);$csrf=$this->helper->form->csrf();
        if (session_status()===PHP_SESSION_ACTIVE) { session_write_close(); }
        try {
            $params=['operationId'=>$this->request->getRawValue('operationId'),'receiptToken'=>$this->request->getRawValue('receiptToken')];
            $result=(new NativeService($this->container))->dispatch('account.deletion.status',$params,'',$_SERVER['REMOTE_ADDR']??'unknown');
            $this->render(['result'=>$result]+$params,null,200,$csrf);
        } catch (NativeError $error) { $this->render(null,$error->errorCode,$error->status,$csrf); }
        catch (\Throwable $error) { $this->render(null,'server_error',500,$csrf); }
    }
    public function cancelPending()
    {
        $this->guard(true);$csrf=$this->helper->form->csrf();
        if (session_status()===PHP_SESSION_ACTIVE) { session_write_close(); }
        try {
            $params=['operationId'=>$this->request->getRawValue('operationId'),'receiptToken'=>$this->request->getRawValue('receiptToken')];
            $token=$this->request->getRawValue('token');
            $result=(new NativeService($this->container))->dispatch('account.deletion.cancelPending',$params,is_string($token)&&$token!=='' ? 'Bearer '.$token:'',$_SERVER['REMOTE_ADDR']??'unknown');
            $this->render(['result'=>$result]+$params,null,200,$csrf);
        } catch (NativeError $error) { $this->render(null,$error->errorCode,$error->status,$csrf); }
        catch (\Throwable $error) { $this->render(null,'server_error',500,$csrf); }
    }
    private function uuid()
    {
        $hex=bin2hex(random_bytes(16));return substr($hex,0,8).'-'.substr($hex,8,4).'-4'.substr($hex,13,3).'-a'.substr($hex,17,3).'-'.substr($hex,20);
    }
    private function anonymousCsrf($previous)
    {
        // A pre-existing Kanboard login was deleted too. Start a fresh anonymous
        // CSRF session so the receipt-status form works after account deletion.
        if (headers_sent()) { return $previous; }
        $csrfKey=$_SESSION['csrf_key']??null;
        $_SESSION=[];
        if (session_status()!==PHP_SESSION_ACTIVE) { session_start(); }
        // Keep only CSRF material under the same random session ID. Thus a lost
        // HTTP response does not invalidate the original form POST's CSRF token;
        // no authenticated user/session data are ever restored.
        $_SESSION=[];if ($csrfKey!==null) { $_SESSION['csrf_key']=$csrfKey; }
        $csrf=$this->helper->form->csrf();session_write_close();return $csrf;
    }
    private function render($state=null,$error=null,$status=200,$csrf=null)
    {
        $this->response->html($this->template->render('FamilyHub:account_deletion/index',['available'=>NativeAccountDeletionService::available() && defined('FAMILYHUB_ENABLE_NATIVE_API') && FAMILYHUB_ENABLE_NATIVE_API===true,'state'=>$state,'error'=>$error,'csrf'=>$csrf??$this->helper->form->csrf()]),$status);
    }
}
