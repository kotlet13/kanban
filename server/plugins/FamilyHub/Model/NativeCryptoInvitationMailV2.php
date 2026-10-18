<?php

namespace Kanboard\Plugin\FamilyHub\Model;

/** Generic, encrypted-token invitation outbox. Never sends content or key material. */
class NativeCryptoInvitationMailV2 extends NativeCryptoInvitationV2
{
    public function run($limit = 20, $transport = null, $deadline = null)
    {
        if (!NativeAccountMailCrypto::configured()) {
            throw new NativeError('email_unavailable', 503);
        }
        if (!is_int($limit) || $limit < 1 || $limit > 50) {
            throw new NativeError('validation_error');
        }
        $transport = $transport ?? new NativeAccountMailTransport();
        $deadline = $deadline ?? microtime(true) + 60;
        $counts = ['examined' => 0,'accepted' => 0,'retry' => 0,'cancelled' => 0];
        $this->change("UPDATE familyhub_crypto_invitation_mail_v2 SET state='cancelled',token_cipher=NULL,lease_token=NULL WHERE state IN ('pending','processing') AND invitation_id IN (SELECT id FROM familyhub_crypto_invitations_v2 WHERE state<>'pending' OR expires_at<=?)", [time()]);
        $rows = $this->many("SELECT invitation_id FROM familyhub_crypto_invitation_mail_v2 WHERE (state='pending' AND next_attempt<=?) OR (state='processing' AND lease_until<=?) ORDER BY next_attempt,invitation_id LIMIT ".$limit, [time(),time()]);
        foreach ($rows as $row) {
            if (microtime(true) + 50 > $deadline) {
                break;
            }
            $lease = $this->transaction(function () use ($row) {
                $job = $this->one('SELECT * FROM familyhub_crypto_invitation_mail_v2 WHERE invitation_id=?'.$this->lockSuffix(), [$row['invitation_id']]);
                if (!$job || !in_array($job['state'], ['pending','processing'], true) || ($job['state'] === 'processing' && (int)$job['lease_until'] > time()) || ($job['state'] === 'pending' && (int)$job['next_attempt'] > time())) {
                    return null;
                }
                $lease = bin2hex(random_bytes(16));
                $this->change("UPDATE familyhub_crypto_invitation_mail_v2 SET state='processing',attempts=attempts+1,lease_token=?,lease_until=? WHERE invitation_id=?", [$lease,time() + 120,$row['invitation_id']]);
                return $lease;
            });
            if (!$lease) {
                continue;
            }$counts['examined']++;
            $result = $this->transaction(function () use ($row, $lease, $transport, $deadline) {
                $id = $row['invitation_id'];
                $invitation = $this->one('SELECT * FROM familyhub_crypto_invitations_v2 WHERE id=?', [$id]);
                if ($invitation) {
                    $this->one('SELECT u.id FROM users u JOIN familyhub_accounts a ON a.user_id=u.id WHERE a.account_id=?'.$this->lockSuffix(), [$invitation['creator_account_id']]);
                }
                try {
                    $scope = $this->usable($invitation);
                } catch (NativeError $error) {
                    $scope = null;
                }
                $job = $this->one('SELECT * FROM familyhub_crypto_invitation_mail_v2 WHERE invitation_id=?'.$this->lockSuffix(), [$id]);
                if (!$job || $job['state'] !== 'processing' || $job['lease_token'] !== $lease) {
                    return 'cancelled';
                }
                $invitation = $this->one('SELECT * FROM familyhub_crypto_invitations_v2 WHERE id=?', [$id]);
                if (!$scope || $invitation['state'] !== 'pending' || $invitation['recipient_kind'] !== 'email' || (int)$job['attempts'] > 5) {
                    $this->finish($id, $lease, 'cancelled');
                    return 'cancelled';
                }
                if (microtime(true) + 50 > $deadline) {
                    $this->retry($id, $lease, 60);
                    return 'retry';
                }
                try {
                    // Only an installed, signed legacy bridge authorizes the
                    // original ciphertext's AAD; ordinary v4 never downgrades.
                    $legacyBridge=$this->bridgeEvidence($invitation);
                    $aad=$legacyBridge===null?$this->aad($id):$this->serverId().':email-invitation:'.$id;
                    $token = NativeAccountMailCrypto::decrypt($job['token_cipher'], $aad);
                    if (!hash_equals($invitation['token_hash'], hash('sha256', self::token($token)))) {
                        throw new NativeError('email_unavailable', 503);
                    }
                    $url = NativeEmailInvitationService::publicUrl($this->configModel->get('application_url')).'/index.php?controller=InvitationController&action=show&plugin=FamilyHub&language='.$job['language'].'#token='.rawurlencode($token);
                    $creator = $this->one('SELECT u.name,u.username FROM users u JOIN familyhub_accounts a ON a.user_id=u.id WHERE a.account_id=?', [$invitation['creator_account_id']]);
                    $details = ['inviterName' => $creator['name'] ?: $creator['username'],'scopeName' => 'Encrypted space','role' => $invitation['role'],'contractVersion' => 4,'scopeKind' => $scope['kind'],'expiresAt' => (int)$invitation['expires_at']];
                    if (($transport->send($invitation['recipient_value'], 'invitation', $url, $id, $job['language'], $details)['accepted'] ?? false) !== true) {
                        throw new NativeError('email_unavailable', 503);
                    }
                    $this->finish($id, $lease, 'accepted');
                    return 'accepted';
                } catch (\Throwable $ignored) {
                    if ((int)$job['attempts'] >= 5) {
                        $this->finish($id, $lease, 'cancelled');
                        return 'cancelled';
                    }
                    $this->retry($id, $lease, min(900, 60 * (2 ** (int)$job['attempts'])));
                    return 'retry';
                }
            }, true);
            $counts[$result]++;
        }
        return $counts;
    }
    private function finish($id, $lease, $state)
    {
        $this->change('UPDATE familyhub_crypto_invitation_mail_v2 SET state=?,token_cipher=NULL,lease_token=NULL,accepted_at=? WHERE invitation_id=? AND lease_token=?', [$state,$state === 'accepted' ? time() : null,$id,$lease]);
    }
    private function retry($id,$lease,$seconds)
    {
        $this->change("UPDATE familyhub_crypto_invitation_mail_v2 SET state='pending',lease_token=NULL,next_attempt=? WHERE invitation_id=? AND lease_token=?",[time() + $seconds,$id,$lease]);
    }
}
