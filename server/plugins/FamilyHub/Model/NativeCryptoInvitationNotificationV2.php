<?php
namespace Kanboard\Plugin\FamilyHub\Model;

/** An exact acceptance is a routing hint for its original inviter, never grant authority. */
class NativeCryptoInvitationNotificationV2 extends NativeDatabase
{
    const KIND = 'crypto2.invitation.accepted';

    private static function eventKey($id, $hash)
    {
        return hash('sha256', 'crypto2-invitation-accepted:'.$id.':'.$hash);
    }

    private function creation($row)
    {
        $proof = json_decode($row['authorization'], true, 34, JSON_THROW_ON_ERROR);
        [$command] = NativeCryptoCodec::decode($proof);
        $p = $command['payload'];
        if (!in_array($command['operation'], ['crypto2.invitations.create','crypto2.invitations.resend'], true)
            || isset($p['preauthorization']) || $command['accountId'] !== $row['creator_account_id']
            || $command['deviceId'] !== $row['creator_device_id']
            || ($p['recipient']['kind'] ?? null) !== 'email'
            || !array_key_exists('accountId', $p['recipient']) || $p['recipient']['accountId'] !== null
            || $p['recipient']['value'] !== $row['recipient_value']
            || $row['recipient_kind'] !== 'email' || $p['scopeId'] !== $row['scope_id']
            || $p['invitationId'] !== $row['id'] || $p['tokenHash'] !== $row['token_hash']
            || $p['role'] !== $row['role'] || $p['expiresAt'] !== (int)$row['expires_at']) return null;
        return ['command'=>$command,'hash'=>NativeCryptoV2Codec::hash((object)$proof)];
    }

    /** Called in the signed acceptance transaction, after the account binding was stored. */
    public function accepted($id, $hash)
    {
        $row = $this->one('SELECT * FROM familyhub_crypto_invitations_v2 WHERE id=?', [$id]);
        if (!$row || $row['state'] !== 'accepted' || !$this->creation($row)) return;
        $writer = new NativeNotificationWriter($this->container);
        // The opaque group retains the exact proof hash without a new schema or
        // any content. This also prevents distinct acceptances being coalesced.
        $writer->insert($row['scope_id'], $row['creator_account_id'], $row['recipient_account_id'],
            'membership', $id, 1, self::KIND, 'membership', 'personal', self::eventKey($id, $hash), $id.':'.$hash);
    }

    /** Fresh lifecycle + exact proof association for inbox reads and both delivery workers. */
    public function reference($inbox)
    {
        if (!$inbox || $inbox['kind'] !== self::KIND || $inbox['target_type'] !== 'membership'
            || $inbox['category'] !== 'membership' || $inbox['audience'] !== 'personal') return null;
        $parts = explode(':', $inbox['group_key']);
        if (count($parts) !== 6 || $parts[0] !== $inbox['scope_id'] || $parts[1] !== $inbox['target_id']
            || !preg_match('/^[a-f0-9]{64}$/D', $parts[2]) || $parts[3] !== 'membership'
            || $parts[4] !== 'personal' || !ctype_digit($parts[5])
            || !hash_equals(self::eventKey($inbox['target_id'], $parts[2]), $inbox['event_key'])) return null;
        $row = $this->one('SELECT * FROM familyhub_crypto_invitations_v2 WHERE id=?', [$inbox['target_id']]);
        if (!$row || $row['state'] !== 'accepted' || $row['scope_id'] !== $inbox['scope_id']
            || $row['creator_account_id'] !== $inbox['recipient_account_id']
            || $row['recipient_account_id'] !== $inbox['actor_account_id']) return null;
        $creation = $this->creation($row);
        if (!$creation) return null;
        $accepted = $this->one("SELECT * FROM familyhub_crypto_invitation_acceptances_v2 WHERE invitation_id=? AND proof_hash=? AND account_id=? AND state='accepted'", [$row['id'],$parts[2],$row['recipient_account_id']]);
        if (!$accepted) return null;
        $proof = json_decode($accepted['authorization'], true, 34, JSON_THROW_ON_ERROR);
        [$command] = NativeCryptoCodec::decode($proof);
        $p = $command['payload'];
        if ($command['operation'] !== 'crypto2.invitations.accept'
            || $command['serverId'] !== $creation['command']['serverId']
            || $command['accountId'] !== $accepted['account_id'] || $command['deviceId'] !== $accepted['device_id']
            || $p['scopeId'] !== $row['scope_id'] || $p['invitationId'] !== $row['id']
            || $p['tokenHash'] !== $row['token_hash'] || $p['creatorProofHash'] !== $creation['hash']
            || $p['role'] !== $row['role'] || $p['expiresAt'] !== (int)$row['expires_at']
            || $p['membershipHeadHash'] !== $creation['command']['payload']['membershipHeadHash']
            || NativeCryptoV2Codec::hash((object)$proof) !== $parts[2]) return null;
        try {
            (new NativeCryptoInvitationV2($this->container))->usable($row);
        } catch (NativeError $error) {
            if (in_array($error->status, [403,404,409], true)) return null;
            throw $error;
        }
        return ['scopeId'=>$row['scope_id'],'invitationId'=>$row['id'],'acceptanceProofHash'=>$parts[2],
            'creatorProofHash'=>$creation['hash'],'tokenHash'=>$row['token_hash']];
    }

    /** Consuming or revoking an invitation suppresses only its still-unsent delivery references. */
    public function resolved($id)
    {
        $invitation = $this->one('SELECT * FROM familyhub_crypto_invitations_v2 WHERE id=?', [$id]);
        if (!$invitation || !$this->creation($invitation)) return;
        $rows = $this->many('SELECT id,recipient_account_id FROM familyhub_inbox WHERE target_id=? AND target_type=? AND kind=?', [$id,'membership',self::KIND]);
        if (!$rows) return;
        foreach ($rows as $row) {
            $this->change("UPDATE familyhub_push_jobs SET state='cancelled',lease_token=NULL,lease_until=NULL WHERE inbox_id=? AND state IN ('pending','processing')", [$row['id']]);
            $this->change("UPDATE familyhub_deliveries SET state='cancelled',lease_token=NULL,lease_until=NULL WHERE inbox_id=? AND state IN ('pending','processing')", [$row['id']]);
        }
        (new NativeNotificationWriter($this->container))->visibilityChanged(array_column($rows, 'recipient_account_id'));
    }
}
