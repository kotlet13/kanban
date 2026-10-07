<?php
namespace Kanboard\Plugin\FamilyHub\Model;

class NativeService extends NativeDatabase
{
    public function dispatch($operation, array $params, $bearer, $ip)
    {
        $supported = in_array($this->pdo->getAttribute(\PDO::ATTR_DRIVER_NAME), ['sqlite', 'mysql'], true);
        $enabled = defined('FAMILYHUB_ENABLE_NATIVE_API') && FAMILYHUB_ENABLE_NATIVE_API === true && $supported;
        if ($operation === 'capabilities') {
            $pushConfigured=$enabled && NativeFcmConfig::configured();
            return ['api' => 'familyhub_native', 'version' => 1, 'serverId' => $supported ? $this->serverId() : null, 'enabled' => $enabled,
                    'features' => ['accountDeletion' => $enabled && NativeAccountDeletionService::available(), 'privateSync' => $enabled, 'personalFinanceEntry' => $enabled, 'accountEnrollment' => $enabled && (new NativeEnrollmentService($this->container))->available(), 'emailVerification' => $enabled && NativeAccountMailCrypto::configured(), 'passwordReset' => $enabled && NativeAccountMailCrypto::configured(), 'deviceLogin' => $enabled, 'totp' => $enabled, 'invitationRegistration' => $enabled,
                                   'recordSync' => $enabled, 'collaboration' => $enabled, 'inbox' => $enabled, 'scheduledReminders' => $enabled, 'externalPush' => $pushConfigured, 'smtp' => $enabled && NativeSmtpTransport::configured(), 'finance' => $enabled, 'legacyProjectSharing' => false],
                    'pushProjectId'=>$pushConfigured ? FAMILYHUB_FCM_PROJECT_ID : null,
                    'recordContractVersions' => [1, 2], 'recordTypesV2' => ['project', 'task', 'event', 'shoppingList', 'shoppingItem'],
                    'recordTypes' => ['project', 'task', 'shoppingList', 'shoppingItem'], 'scopeKinds' => ['household', 'project', 'personal']];
        }
        if (!$enabled) { throw new NativeError('feature_disabled', 503); }
        $class = match (explode('.', $operation)[0]) {
            'auth' => NativeAuthService::class,
            'personal' => NativePersonalService::class,
            'account' => str_starts_with($operation, 'account.deletion.') ? NativeAccountDeletionService::class : NativeAccountService::class,
            'scopes' => NativeScopeService::class,
            'invitations' => NativeInvitationService::class,
            'sync', 'sync2' => NativeSyncService::class,
            'inbox' => NativeInboxService::class,
            'reminders' => NativeReminderService::class,
            'finance' => NativeFinanceService::class,
            'push' => NativePushService::class,
            default => throw new NativeError('unsupported_operation', 404),
        };
        $service = new $class($this->container, $bearer, $ip);
        return $service->execute($operation, $params);
    }
}
