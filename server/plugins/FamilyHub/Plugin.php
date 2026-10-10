<?php

namespace Kanboard\Plugin\FamilyHub;

use Kanboard\Core\Plugin\Base;
use Kanboard\Plugin\FamilyHub\Model\InvitationService;
use Kanboard\Plugin\FamilyHub\Api\IdentityMiddleware;

class Plugin extends Base
{
    public function initialize()
    {
        $this->applicationAccessMap->add('InvitationController', 'show', \Kanboard\Core\Security\Role::APP_PUBLIC);
        $this->applicationAccessMap->add('NativeApiController', 'handle', \Kanboard\Core\Security\Role::APP_PUBLIC);
        $this->applicationAccessMap->add('AccountDeletionController', '*', \Kanboard\Core\Security\Role::APP_PUBLIC);
        $this->applicationAccessMap->add('EnrollmentController', '*', \Kanboard\Core\Security\Role::APP_ADMIN);
        $this->template->hook->attach('template:config:sidebar', 'FamilyHub:enrollment/sidebar');
        $this->api->getMiddlewareHandler()->withMiddleware(new IdentityMiddleware($this->container));
        $service = new InvitationService($this->container);
        $api = $this->api->getProcedureHandler();
        $api->withCallback('familyHubGetCapabilities', function () use ($service) {
            return $service->capabilities();
        });
        $api->withCallback('familyHubCreateProjectInvitation', function ($project_id, $recipient_username, $request_id, $expires_in = 86400) use ($service) {
            return $service->create($project_id, $recipient_username, $request_id, $expires_in);
        });
        $api->withCallback('familyHubPreviewProjectInvitation', function ($token) use ($service) {
            return $service->preview($token);
        });
        $api->withCallback('familyHubAcceptProjectInvitation', function ($token) use ($service) {
            return $service->accept($token);
        });
        $api->withCallback('familyHubRevokeProjectInvitation', function ($invitation_id) use ($service) {
            return $service->revoke($invitation_id);
        });
    }

    public function getPluginName() { return 'FamilyHub'; }
    public function getPluginVersion() { return '0.11.0'; }
    public function getPluginAuthor() { return 'TriparNA'; }
    public function getPluginDescription() { return 'Opt-in native account, scope and record synchronization API.'; }
    public function getCompatibleVersion() { return '1.2.54'; }
}
