<?php

namespace Kanboard\Plugin\FamilyHub\Model;

use InvalidArgumentException;
use JsonRPC\Exception\AccessDeniedException;
use Kanboard\Core\Base;
use Kanboard\Core\Security\Role;
use PDO;
use Throwable;

/** Every entry point checks the authenticated identity; global API credentials have none. */
class InvitationService extends Base
{
    public function capabilities()
    {
        $actor = $this->actor();
        return array(
            'plugin' => 'FamilyHub',
            'plugin_version' => (new \Kanboard\Plugin\FamilyHub\Plugin($this->container))->getPluginVersion(),
            'contract_version' => 1,
            'kanboard_version' => APP_VERSION,
            'actor' => array('user_id' => (int) $actor['id'], 'username' => $actor['username']),
            'features' => array(
                'project_invitations' => $this->enabled(),
                'account_registration' => false,
                'device_login' => false,
                'local_first_sync' => false,
                'finance_acl' => false,
            ),
            'invitation_policy' => array(
                'enabled' => $this->enabled(),
                'configuration' => 'FAMILYHUB_ENABLE_PROJECT_INVITATIONS',
                'reason' => $this->enabled() ? 'explicit_opt_in' : 'requires_separate_finance_storage_and_acl',
                'recipient' => 'existing_named_user',
                'role' => Role::PROJECT_MEMBER,
                'max_lifetime_seconds' => 604800,
            ),
        );
    }

    public function create($project_id, $recipient_username, $request_id, $expires_in = 86400)
    {
        $actor = $this->requireEnabledActor();
        $this->validateId($project_id);
        if (! is_string($recipient_username) || strlen($recipient_username) > 50 || $recipient_username === '') {
            throw new InvalidArgumentException('Invalid recipient username');
        }
        if (! is_string($request_id) || ! preg_match('/\A[A-Za-z0-9_-]{16,64}\z/', $request_id)) {
            throw new InvalidArgumentException('Invalid request id');
        }
        if (! is_int($expires_in) || $expires_in < 60 || $expires_in > 604800) {
            throw new InvalidArgumentException('Invalid expiration');
        }
        return $this->transaction(function () use ($actor, $project_id, $recipient_username, $request_id, $expires_in) {
            $this->requireManager($project_id, $actor['id']);
            $recipient = $this->userModel->getByUsername($recipient_username);
            if (empty($recipient) || ! $recipient['is_active'] || $recipient['id'] == $actor['id']) {
                $this->deny();
            }
            $existing = $this->one('SELECT * FROM familyhub_project_invitations WHERE creator_id = ? AND request_id = ?', array($actor['id'], $request_id));
            if ($existing) {
                if ((int) $existing['project_id'] !== $project_id || $existing['recipient_id'] != $recipient['id'] || $existing['expires_at'] - $existing['created_at'] !== $expires_in) {
                    throw new InvalidArgumentException('Request id already used with different parameters');
                }
                // A hash cannot reproduce the original bearer token. Never issue another token on replay.
                return $this->createdResponse($existing, null);
            }
            $token = bin2hex(random_bytes(32));
            $now = time();
            $row = array(
                'id' => bin2hex(random_bytes(16)),
                'project_id' => $project_id,
                'creator_id' => (int) $actor['id'],
                'recipient_id' => (int) $recipient['id'],
                'request_id' => $request_id,
                'token_hash' => hash('sha256', $token),
                'created_at' => $now,
                'expires_at' => $now + $expires_in,
            );
            $this->execute('INSERT INTO familyhub_project_invitations (id, project_id, creator_id, recipient_id, request_id, token_hash, created_at, expires_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?)', array_values($row));
            return $this->createdResponse($row, $token);
        });
    }

    public function preview($token)
    {
        $actor = $this->requireEnabledActor();
        $row = $this->findForRecipient($token, $actor['id']);
        $this->requirePending($row);
        $project = $this->requireManager($row['project_id'], $row['creator_id']);
        return array('invitation_id' => $row['id'], 'project_id' => (int) $row['project_id'], 'project_name' => $project['name'], 'role' => Role::PROJECT_MEMBER, 'expires_at' => (int) $row['expires_at']);
    }

    public function accept($token)
    {
        $actor = $this->requireEnabledActor();
        return $this->transaction(function () use ($token, $actor) {
            $row = $this->findForRecipient($token, $actor['id']);
            if ($row['accepted_at'] !== null) {
                // An accepted token must never recreate membership that was subsequently removed.
                $project = $this->projectModel->getById($row['project_id']);
                if (empty($project) || ! $project['is_active'] || $project['is_private'] || $this->projectUserRoleModel->getUserRole($row['project_id'], $actor['id']) === '') {
                    $this->deny();
                }
                return array('invitation_id' => $row['id'], 'project_id' => (int) $row['project_id'], 'accepted' => true, 'replayed' => true);
            }
            $this->requirePending($row);
            $this->requireManager($row['project_id'], $row['creator_id']);
            // Atomic conditional consume: two requests cannot both grant membership.
            $changed = $this->execute('UPDATE familyhub_project_invitations SET accepted_at = ? WHERE id = ? AND accepted_at IS NULL AND revoked_at IS NULL AND expires_at > ?', array(time(), $row['id'], time()));
            if ($changed !== 1) {
                $this->deny();
            }
            // Preserve an existing direct/group role, including viewer; never upgrade it silently.
            if ($this->projectUserRoleModel->getUserRole($row['project_id'], $actor['id']) === '') {
                if (! $this->projectUserRoleModel->addUser($row['project_id'], $actor['id'], Role::PROJECT_MEMBER)) {
                    $this->deny();
                }
            }
            return array('invitation_id' => $row['id'], 'project_id' => (int) $row['project_id'], 'accepted' => true, 'replayed' => false);
        });
    }

    public function revoke($invitation_id)
    {
        $actor = $this->requireEnabledActor();
        if (! is_string($invitation_id) || ! preg_match('/\A[0-9a-f]{32}\z/', $invitation_id)) {
            throw new InvalidArgumentException('Invalid invitation id');
        }
        return $this->transaction(function () use ($actor, $invitation_id) {
            $row = $this->one('SELECT * FROM familyhub_project_invitations WHERE id = ?', array($invitation_id));
            if (! $row) {
                $this->deny();
            }
            $this->requireManager($row['project_id'], $actor['id']);
            if ($row['accepted_at'] !== null) {
                $this->deny(); // Revoke an unused invitation; membership removal is a separate action.
            }
            $changed = $this->execute('UPDATE familyhub_project_invitations SET revoked_at = ? WHERE id = ? AND revoked_at IS NULL AND accepted_at IS NULL', array(time(), $row['id']));
            if ($changed !== 1) {
                // Resolve a concurrent consume; already-revoked remains an idempotent success.
                $current = $this->one('SELECT * FROM familyhub_project_invitations WHERE id = ?', array($row['id']));
                if (! $current || $current['accepted_at'] !== null || $current['revoked_at'] === null) {
                    $this->deny();
                }
            }
            return array('invitation_id' => $row['id'], 'revoked' => true);
        });
    }

    private function actor()
    {
        if (! $this->userSession->isLogged() || $this->userSession->getId() <= 0) {
            $this->deny();
        }
        $actor = $this->userModel->getById($this->userSession->getId());
        if (empty($actor) || ! $actor['is_active']) {
            $this->deny();
        }
        return $actor;
    }

    private function enabled()
    {
        return defined('FAMILYHUB_ENABLE_PROJECT_INVITATIONS') && FAMILYHUB_ENABLE_PROJECT_INVITATIONS === true && in_array(DB_DRIVER, array('sqlite', 'mysql'), true);
    }

    private function requireEnabledActor()
    {
        $actor = $this->actor();
        if (! $this->enabled()) {
            throw new AccessDeniedException('Project invitations are disabled');
        }
        return $actor;
    }

    private function requireManager($project_id, $user_id)
    {
        $user = $this->userModel->getById($user_id);
        $project = $this->projectModel->getById($project_id);
        if (empty($user) || ! $user['is_active'] || empty($project) || ! $project['is_active'] || $project['is_private'] || $this->projectUserRoleModel->getUserRole($project_id, $user_id) !== Role::PROJECT_MANAGER) {
            $this->deny();
        }
        // Application administrator status alone is insufficient.
        return $project;
    }

    private function findForRecipient($token, $user_id)
    {
        if (! is_string($token) || ! preg_match('/\A[0-9a-f]{64}\z/', $token)) {
            $this->deny();
        }
        $row = $this->one('SELECT * FROM familyhub_project_invitations WHERE token_hash = ? AND recipient_id = ?', array(hash('sha256', $token), $user_id));
        if (! $row) {
            $this->deny();
        }
        return $row;
    }

    private function requirePending($row)
    {
        if ($row['accepted_at'] !== null || $row['revoked_at'] !== null || $row['expires_at'] <= time()) {
            $this->deny();
        }
    }

    private function createdResponse($row, $token)
    {
        return array('invitation_id' => $row['id'], 'project_id' => (int) $row['project_id'], 'expires_at' => (int) $row['expires_at'], 'token' => $token, 'token_available' => $token !== null);
    }

    private function validateId($id)
    {
        if (! is_int($id) || $id <= 0) {
            throw new InvalidArgumentException('Invalid project id');
        }
    }

    private function one($sql, array $parameters)
    {
        $statement = $this->db->getConnection()->prepare($sql);
        $statement->execute($parameters);
        return $statement->fetch(PDO::FETCH_ASSOC);
    }

    private function execute($sql, array $parameters)
    {
        $statement = $this->db->getConnection()->prepare($sql);
        $statement->execute($parameters);
        return $statement->rowCount();
    }

    private function transaction($operation)
    {
        $pdo = $this->db->getConnection();
        $pdo->beginTransaction();
        try {
            $result = $operation();
            $pdo->commit();
            return $result;
        } catch (Throwable $error) {
            if ($pdo->inTransaction()) {
                $pdo->rollBack();
            }
            throw $error;
        }
    }

    private function deny()
    {
        throw new AccessDeniedException('Access denied');
    }
}
