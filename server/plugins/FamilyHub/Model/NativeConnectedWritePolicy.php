<?php

namespace Kanboard\Plugin\FamilyHub\Model;

/** Email write policy is independent of sodium/runtime readiness and persists for initialized accounts. */
class NativeConnectedWritePolicy extends NativeDatabase
{
    public static function required($pdo, $account = null)
    {
        if (defined('FAMILYHUB_REQUIRE_VERIFIED_CONNECTED_WRITES') && FAMILYHUB_REQUIRE_VERIFIED_CONNECTED_WRITES === true || defined('FAMILYHUB_ENABLE_CRYPTO_PREVIEW') && FAMILYHUB_ENABLE_CRYPTO_PREVIEW === true) {
            return true;
        }
        if ($account === null) {
            return false;
        }
        try {
            $s = $pdo->prepare('SELECT account_id FROM familyhub_crypto_accounts WHERE account_id=?');
            $s->execute([$account]);
            $found = $s->fetchColumn() !== false;
            $s->closeCursor();
            return $found || NativeCryptoV2Boundary::account($pdo, $account);
        } catch (\PDOException $e) {
            $state = $e->errorInfo[0] ?? $e->getCode();
            $number = (int)($e->errorInfo[1] ?? 0);
            if ($state === '42S02' || $number === 1146 || $state === 'HY000' && $number === 1 && str_contains($e->getMessage(), 'no such table: familyhub_crypto_accounts')) {
                return NativeCryptoV2Boundary::account($pdo, $account);
            }throw new NativeError('email_policy_unavailable', 503);
        }
    }
    public function requireAccount($account)
    {
        if (self::required($this->pdo, $account) && !$this->one('SELECT account_id FROM familyhub_email_identities WHERE account_id=? AND verified_at IS NOT NULL', [$account])) {
            throw new NativeError('email_verification_required', 403);
        }
    }
    public function guardOperation($operation)
    {
        $parts = explode('.', $operation);
        $group = $parts[0];
        $action = $parts[1] ?? '';
        $write = match($group) {
            'scopes' => !in_array($action, ['list','members','accessMigrationPreview','projectSharingPreview','deletionPreview'], true),
            'personal' => $action === 'ensure',
            'sync','sync2','sync3','sync4','sync5','sync6' => in_array($action, ['push','pushTaskWithCost'], true),
            'finance','finance2','finance4' => in_array($action, ['push','enable','grant'], true),
            'finance3' => in_array($action, ['paymentCommit','paymentReimburse','paymentProject'], true),
            'invitations','invitations2','invitations3' => in_array($action, ['create','resend','accept','revoke'], true),
            'tables' => !in_array($action, ['list','get'], true),
            'attachments' => in_array($action, ['begin','chunk','complete','delete'], true),
            'ideas' => $action === 'asset' && in_array($parts[2] ?? '', ['begin','chunk','complete'], true),
            'reminders' => in_array($action, ['put','cancel'], true),
            'moderation' => $action === 'report',
            default => false,
        };
        if ($write) {
            $this->requireAccount($this->actor(false)['user']['account_id']);
        }
    }
}
