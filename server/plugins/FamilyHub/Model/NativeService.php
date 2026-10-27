<?php
namespace Kanboard\Plugin\FamilyHub\Model;

class NativeService extends NativeDatabase
{
    /** Only explicitly public operator metadata: never infer from admin users,
     * SMTP credentials, workspace owners, request headers, or secret config. */
    public static function hostingInformation()
    {
        $result = [];
        foreach (['operatorName' => 'FAMILYHUB_HOSTING_OPERATOR_NAME',
                  'operatorContact' => 'FAMILYHUB_HOSTING_OPERATOR_CONTACT'] as $key => $constant) {
            $value = defined($constant) ? constant($constant) : null;
            if (!is_string($value)) { continue; }
            $value = trim($value);
            // Single-line, bounded UTF-8 text; no bidi/control spoofing.
            if ($value === '' || strlen($value) > 1200 ||
                preg_match('//u', $value) !== 1 ||
                preg_match('/[\\x{0000}-\\x{001f}\\x{007f}-\\x{009f}\\x{202a}-\\x{202e}\\x{2066}-\\x{2069}]/u', $value) !== 0 ||
                preg_match('/^.{1,300}$/us', $value) !== 1) { continue; }
            $result[$key] = $value;
        }
        return (object) $result;
    }

    public function dispatch($operation, array $params, $bearer, $ip)
    {
        $supported = in_array($this->pdo->getAttribute(\PDO::ATTR_DRIVER_NAME), ['sqlite', 'mysql'], true);
        $enabled = defined('FAMILYHUB_ENABLE_NATIVE_API') && FAMILYHUB_ENABLE_NATIVE_API === true && $supported;
        if ($operation === 'capabilities') {
            $documentsReady=$enabled && \Kanboard\Plugin\FamilyHub\Schema\DocumentsSchema::ready($this->pdo);
            $ideasAvailable=$enabled && NativeIdeaAssetService::available();
            $pushConfigured=$enabled && NativeFcmConfig::configured();
            $cryptoReady=$enabled && NativeCryptoService::enabled($this->pdo);
            $changesReady=$enabled && NativeAccountChanges::available($this->pdo);
            return ['api' => 'familyhub_native', 'version' => 1, 'serverId' => $supported ? $this->serverId() : null, 'enabled' => $enabled, 'hostingInformation' => self::hostingInformation(),
                    'invitationPreauthorizationVersions'=>$cryptoReady&&NativeCryptoInvitationPreauthorizationV5::ready($this->pdo)?[1]:[], 'cryptoTransportVersions'=>$cryptoReady?[1,2]:[], 'cryptoAuthoritySnapshotVersions'=>$cryptoReady?[1]:[], 'cryptoMemberLabelsVersions'=>$cryptoReady?[1]:[], 'cryptoCutoverSupported'=>$cryptoReady, 'cryptoCutoverVersion'=>$cryptoReady?3:null,
                    'organizationFinanceContractVersions'=>[1], 'scopeLifecycleContractVersions'=>[1], 'gardenDocumentVersions'=>[2,3], 'moderationContractVersions'=>[1], 'sharedContentPolicyVersions'=>[1], 'invitationContractVersions'=>$cryptoReady?[1,2,3,4]:[1,2,3], 'spaceAccessPolicyVersions'=>[3], 'organizationAccessPolicyVersions'=>[1,2,3], 'linkedPaymentContractVersions'=>[3], 'features' => ['organizationFinance'=>$enabled,'spreadsheets'=>$documentsReady,'attachments'=>$documentsReady,'scopeDeletion'=>$enabled,'scopeArchiving'=>$enabled,'gardenSceneV3'=>$enabled,'ideas'=>$ideasAvailable,'ideaAssets'=>$ideasAvailable,'contentReporting'=>$enabled,'sharedContentPolicy'=>$enabled,'spaceProjectMembership'=>$enabled,'scopedInvitations'=>$enabled,'projectSharingMigration'=>$enabled,'usernameInvitations'=>$enabled,'recipientSearch'=>$enabled,'invitationResend'=>$enabled,'emailInvitations'=>$enabled && NativeEmailInvitationService::available(),'linkedPayments'=>$enabled,'scopeMetadata'=>$enabled,'householdGardenSync'=>$enabled,'scopeAccessChanges'=>$enabled,'organizationLeadership'=>$enabled,'projectFinanceMembership'=>$enabled,'accessMigrationPreview'=>$enabled,'stableScopePublication'=>$enabled,'projectArchiving'=>$enabled, 'financePlanning' => $enabled, 'taskCosts' => $enabled, 'organizations' => $enabled, 'householdPeople' => $enabled, 'richPlanning' => $enabled, 'accountDeletion' => $enabled && NativeAccountDeletionService::available(), 'privateSync' => $enabled, 'personalFinanceEntry' => $enabled, 'accountEnrollment' => $enabled && (new NativeEnrollmentService($this->container))->available(), 'emailVerification' => $enabled && NativeAccountMailCrypto::configured(), 'passwordReset' => $enabled && NativeAccountMailCrypto::configured(), 'sessionRenewal' => $enabled, 'deviceLogin' => $enabled, 'totp' => $enabled, 'invitationRegistration' => $enabled,
                                   'recordSync' => $enabled, 'collaboration' => $enabled, 'inbox' => $enabled, 'scheduledReminders' => $enabled, 'externalPush' => $pushConfigured, 'smtp' => $enabled && NativeSmtpTransport::configured(), 'finance' => $enabled, 'legacyProjectSharing' => false],
                    'accountChangeVersions'=>$changesReady?[1]:[], 'accountChanges'=>$changesReady,
                    'recordPolicyVersions'=>$cryptoReady&&NativeCryptoRecordPolicyV1::available($this->pdo)?[1]:[],
                    'recordPolicyBlobTargets'=>$cryptoReady&&NativeCryptoRecordPolicyV1::available($this->pdo),
                    'recordPolicyRestores'=>$cryptoReady&&NativeCryptoRecordPolicyV1::available($this->pdo),
                    'pushDisplayVersion'=>2, 'pushProjectId'=>$pushConfigured ? FAMILYHUB_FCM_PROJECT_ID : null,
                    'accountDeletionPolicyVersions'=>[1,2,3,4], 'financeContractVersions' => [1, 2, 3], 'recordContractVersions' => [1, 2, 3, 4, 5, 6], 'recordTypesV6'=>['project','task','event','shoppingList','shoppingItem','householdPerson','garden','idea'], 'ideaBoardVersions'=>[1,2], 'reminderScheduleVersions'=>[1,2], 'recordTypesV5'=>['project','task','event','shoppingList','shoppingItem','householdPerson','garden','idea'], 'recordTypesV4'=>['project','task','event','shoppingList','shoppingItem','householdPerson','garden'], 'recordTypesV3' => ['project', 'task', 'event', 'shoppingList', 'shoppingItem', 'householdPerson'], 'recordTypesV2' => ['project', 'task', 'event', 'shoppingList', 'shoppingItem'],
                    'recordTypes' => ['project', 'task', 'shoppingList', 'shoppingItem'], 'scopeKinds' => ['household', 'project', 'personal', 'organization']];
        }
        if (!$enabled) { throw new NativeError('feature_disabled', 503); }
        (new NativeConnectedWritePolicy($this->container,$bearer,$ip))->guardOperation($operation);
        (new NativeModerationService($this->container, $bearer, $ip))->guardWrite($operation, $params);
        $class = match (explode('.', $operation)[0]) {
            'crypto' => NativeCryptoService::class,
            'crypto2' => NativeCryptoV2Service::class,
            'tables' => NativeTableService::class,
            'attachments' => NativeAttachmentService::class,
            'ideas' => NativeIdeaAssetService::class,
            'moderation' => NativeModerationService::class,
            'auth' => NativeAuthService::class,
            'personal' => NativePersonalService::class,
            'account' => $operation === 'account.changes' ? NativeAccountChanges::class : (str_starts_with($operation, 'account.deletion.') ? NativeAccountDeletionService::class : NativeAccountService::class),
            'scopes' => NativeScopeService::class,
            'recipients' => NativeRecipientSearchService::class,
            'invitations' => NativeInvitationService::class,
            'invitations3' => NativeEmailInvitationService::class,
            'invitations2' => NativeEmailInvitationService::class,
            'sync', 'sync2', 'sync3', 'sync4', 'sync5', 'sync6' => NativeSyncService::class,
            'inbox' => NativeInboxService::class,
            'reminders' => NativeReminderService::class,
            'finance', 'finance2', 'finance4' => NativeFinanceService::class,
            'finance3' => NativeLinkedPaymentService::class,
            'push' => NativePushService::class,
            default => throw new NativeError('unsupported_operation', 404),
        };
        $service = new $class($this->container, $bearer, $ip);
        return $service->execute($operation, $params);
    }
}
