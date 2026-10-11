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
                    'invitationContractVersions'=>[1,2,3], 'spaceAccessPolicyVersions'=>[3], 'organizationAccessPolicyVersions'=>[1,2,3], 'linkedPaymentContractVersions'=>[3], 'features' => ['spaceProjectMembership'=>$enabled,'scopedInvitations'=>$enabled,'projectSharingMigration'=>$enabled,'emailInvitations'=>$enabled && NativeEmailInvitationService::available(),'linkedPayments'=>$enabled,'scopeMetadata'=>$enabled,'householdGardenSync'=>$enabled,'scopeAccessChanges'=>$enabled,'organizationLeadership'=>$enabled,'projectFinanceMembership'=>$enabled,'accessMigrationPreview'=>$enabled,'stableScopePublication'=>$enabled,'projectArchiving'=>$enabled, 'financePlanning' => $enabled, 'taskCosts' => $enabled, 'organizations' => $enabled, 'householdPeople' => $enabled, 'richPlanning' => $enabled, 'accountDeletion' => $enabled && NativeAccountDeletionService::available(), 'privateSync' => $enabled, 'personalFinanceEntry' => $enabled, 'accountEnrollment' => $enabled && (new NativeEnrollmentService($this->container))->available(), 'emailVerification' => $enabled && NativeAccountMailCrypto::configured(), 'passwordReset' => $enabled && NativeAccountMailCrypto::configured(), 'sessionRenewal' => $enabled, 'deviceLogin' => $enabled, 'totp' => $enabled, 'invitationRegistration' => $enabled,
                                   'recordSync' => $enabled, 'collaboration' => $enabled, 'inbox' => $enabled, 'scheduledReminders' => $enabled, 'externalPush' => $pushConfigured, 'smtp' => $enabled && NativeSmtpTransport::configured(), 'finance' => $enabled, 'legacyProjectSharing' => false],
                    'pushProjectId'=>$pushConfigured ? FAMILYHUB_FCM_PROJECT_ID : null,
                    'accountDeletionPolicyVersions'=>[1,2,3], 'financeContractVersions' => [1, 2], 'recordContractVersions' => [1, 2, 3, 4], 'recordTypesV4'=>['project','task','event','shoppingList','shoppingItem','householdPerson','garden'], 'recordTypesV3' => ['project', 'task', 'event', 'shoppingList', 'shoppingItem', 'householdPerson'], 'recordTypesV2' => ['project', 'task', 'event', 'shoppingList', 'shoppingItem'],
                    'recordTypes' => ['project', 'task', 'shoppingList', 'shoppingItem'], 'scopeKinds' => ['household', 'project', 'personal', 'organization']];
        }
        if (!$enabled) { throw new NativeError('feature_disabled', 503); }
        $class = match (explode('.', $operation)[0]) {
            'auth' => NativeAuthService::class,
            'personal' => NativePersonalService::class,
            'account' => str_starts_with($operation, 'account.deletion.') ? NativeAccountDeletionService::class : NativeAccountService::class,
            'scopes' => NativeScopeService::class,
            'invitations' => NativeInvitationService::class,
            'invitations3' => NativeEmailInvitationService::class,
            'invitations2' => NativeEmailInvitationService::class,
            'sync', 'sync2', 'sync3', 'sync4' => NativeSyncService::class,
            'inbox' => NativeInboxService::class,
            'reminders' => NativeReminderService::class,
            'finance', 'finance2' => NativeFinanceService::class,
            'finance3' => NativeLinkedPaymentService::class,
            'push' => NativePushService::class,
            default => throw new NativeError('unsupported_operation', 404),
        };
        $service = new $class($this->container, $bearer, $ip);
        return $service->execute($operation, $params);
    }
}
