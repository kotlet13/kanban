<?php
namespace Kanboard\Plugin\FamilyHub\Controller;

use Kanboard\Controller\BaseController;
use Kanboard\Core\Controller\AccessForbiddenException;
use Kanboard\Plugin\FamilyHub\Model\NativeEnrollmentService;
use Kanboard\Plugin\FamilyHub\Model\NativeError;

/** Admin web session + CSRF plus durable issuance ID, never native public bearer admin. */
class EnrollmentController extends BaseController
{
    private function authorize()
    {
        if (!$this->userSession->isAdmin() || !NativeApiController::secureTransport($_SERVER) && !(defined('FAMILYHUB_DEVELOPMENT_ENVIRONMENT') && FAMILYHUB_DEVELOPMENT_ENVIRONMENT === true)) { throw new AccessForbiddenException(); }
        $this->response->withHeader('Cache-Control', 'no-store')->withHeader('Referrer-Policy', 'no-referrer')->withHeader('X-Content-Type-Options', 'nosniff');
    }
    public function index()
    {
        $this->authorize();
        $this->render();
    }
    public function issue()
    {
        $this->authorize();
        if (!$this->request->isPost()) { throw new AccessForbiddenException(); }
        $this->checkCSRFForm();
        try { $result = (new NativeEnrollmentService($this->container))->issue($this->userSession->getId(), $this->request->getRawValue('issuanceId')); $this->render($result); }
        catch (NativeError $error) { $this->render(null, $error->errorCode, $error->status); }
    }
    private function render($issued = null, $error = null, $status = 200)
    {
        $this->response->html($this->helper->layout->config('FamilyHub:enrollment/index', ['title' => 'FamilyHub enrollment', 'available' => (new NativeEnrollmentService($this->container))->available(), 'issued' => $issued, 'error' => $error, 'issuanceId' => (new NativeEnrollmentService($this->container))->formId()]), $status);
    }
}
