<?php

namespace Kanboard\Plugin\FamilyHub\Api;

use JsonRPC\Exception\AccessDeniedException;
use JsonRPC\MiddlewareInterface;
use Kanboard\Core\Base;

/** Run after Kanboard authentication; never interpret the application API token as a user. */
class IdentityMiddleware extends Base implements MiddlewareInterface
{
    public function execute($username, $password, $procedureName)
    {
        if (strpos($procedureName, 'familyHub') !== 0) {
            return;
        }
        if ($username === 'jsonrpc' || ! $this->userSession->isLogged() || $this->userSession->getUsername() !== $username) {
            throw new AccessDeniedException('Authenticated user identity required');
        }
    }
}
