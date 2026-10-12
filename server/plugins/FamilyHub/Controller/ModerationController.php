<?php
namespace Kanboard\Plugin\FamilyHub\Controller;
use Kanboard\Controller\BaseController;
use Kanboard\Core\Controller\AccessForbiddenException;
use Kanboard\Plugin\FamilyHub\Model\NativeModerationAdminService;
use Kanboard\Plugin\FamilyHub\Model\NativeModerationService;
use Kanboard\Plugin\FamilyHub\Model\NativeError;

class ModerationController extends BaseController
{
    private function authorize()
    {
        if (!$this->userSession->isAdmin() || !NativeApiController::secureTransport($_SERVER) && !(defined('FAMILYHUB_DEVELOPMENT_ENVIRONMENT') && FAMILYHUB_DEVELOPMENT_ENVIRONMENT===true)) { throw new AccessForbiddenException(); }
        $this->response->withHeader('Cache-Control','no-store')->withHeader('Referrer-Policy','no-referrer')->withHeader('X-Content-Type-Options','nosniff');
    }
    public function index() { $this->authorize();$this->render(); }
    public function review()
    {
        $this->authorize();if (!$this->request->isPost()) { throw new AccessForbiddenException(); }$this->checkCSRFForm();
        try {
            (new NativeModerationAdminService($this->container))->review($this->userSession->getId(),['reportId'=>$this->request->getRawValue('reportId'),'reviewRevision'=>(int)$this->request->getRawValue('reviewRevision'),'targetRevision'=>(int)$this->request->getRawValue('targetRevision'),'action'=>$this->request->getRawValue('decision'),'note'=>$this->request->getRawValue('note'),'confirmation'=>$this->request->getRawValue('confirmation')]);
            $this->render();
        } catch (NativeError $error) { $this->render($error->errorCode,$error->status); }
    }
    private function render($error=null,$status=200)
    {
        (new NativeModerationService($this->container))->purgeExpired();
        $data=(new NativeModerationAdminService($this->container))->reports($this->userSession->getId(),$this->request->getIntegerParam('page',0));
        $data['title']='FamilyHub reports';$data['error']=$error;
        $this->response->html($this->helper->layout->config('FamilyHub:moderation/index',$data),$status);
    }
}
