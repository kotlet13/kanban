<?php
namespace Kanboard\Plugin\FamilyHub\Schema;

/** Additive metadata counters; existing documents and signed bytes are untouched. */
class AccountChangesSchema
{
    public static function create(\PDO $pdo, $mysql)
    {
        $columns = $mysql ? $pdo->query("SELECT column_name FROM information_schema.columns WHERE table_schema=DATABASE() AND table_name='familyhub_scopes'")->fetchAll(\PDO::FETCH_COLUMN)
            : array_column($pdo->query('PRAGMA table_info(familyhub_scopes)')->fetchAll(\PDO::FETCH_ASSOC), 'name');
        if (!in_array('documents_sequence', $columns, true)) { $pdo->exec('ALTER TABLE familyhub_scopes ADD COLUMN documents_sequence BIGINT NOT NULL DEFAULT 0'); }
        $columns = $mysql ? $pdo->query("SELECT column_name FROM information_schema.columns WHERE table_schema=DATABASE() AND table_name='familyhub_inbox_state'")->fetchAll(\PDO::FETCH_COLUMN)
            : array_column($pdo->query('PRAGMA table_info(familyhub_inbox_state)')->fetchAll(\PDO::FETCH_ASSOC), 'name');
        if (!in_array('configuration_revision', $columns, true)) { $pdo->exec('ALTER TABLE familyhub_inbox_state ADD COLUMN configuration_revision BIGINT NOT NULL DEFAULT 0'); }
        $indexes = [
            'familyhub_crypto_invitation_sender_changes' => ['familyhub_crypto_invitations_v2', 'creator_account_id,state,expires_at'],
            'familyhub_crypto_invitation_recipient_changes' => ['familyhub_crypto_invitations_v2', 'recipient_account_id,state,expires_at'],
            'familyhub_invitation_sender_changes' => ['familyhub_invitations', 'creator_account_id,accepted_at,revoked_at,expires_at'],
            'familyhub_invitation_recipient_changes' => ['familyhub_invitations', 'recipient_account_id,accepted_at,revoked_at,expires_at'],
            'familyhub_invitation_username_changes' => ['familyhub_invitations', 'recipient_username,accepted_at,revoked_at,expires_at'],
        ];
        foreach ($indexes as $name => [$table,$definition]) {
            $statement=$pdo->prepare($mysql ? 'SELECT COUNT(*) FROM information_schema.STATISTICS WHERE TABLE_SCHEMA=DATABASE() AND TABLE_NAME=? AND INDEX_NAME=?' : "SELECT COUNT(*) FROM sqlite_master WHERE type='index' AND tbl_name=? AND name=?");
            $statement->execute([$table,$name]);$exists=(int)$statement->fetchColumn();$statement->closeCursor();
            if (!$exists) { $pdo->exec('CREATE INDEX '.$name.' ON '.$table.'('.$definition.')'); }
        }
    }
}
