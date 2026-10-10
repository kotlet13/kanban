<?php
namespace Kanboard\Plugin\FamilyHub\Schema;

/** Additive extension: existing token hashes, request bodies and usernames stay intact. */
class EmailInvitationSchema
{
    public static function create(\PDO $pdo, $mysql)
    {
        $pdo->exec('ALTER TABLE familyhub_invitations ADD COLUMN recipient_email VARCHAR(254) DEFAULT NULL');
        $pdo->exec('ALTER TABLE familyhub_invitations ADD COLUMN recipient_account_id VARCHAR(36) DEFAULT NULL');
        $pdo->exec('CREATE INDEX familyhub_invitation_email ON familyhub_invitations(recipient_email,expires_at)');
        $text=$mysql?'MEDIUMTEXT':'TEXT'; $suffix=$mysql?' ENGINE=InnoDB CHARSET=utf8mb4':'';
        $pdo->exec('CREATE TABLE familyhub_invitation_mail(invitation_id VARCHAR(36) PRIMARY KEY, token_cipher '.$text.' DEFAULT NULL, language VARCHAR(2) NOT NULL, state VARCHAR(20) NOT NULL, attempts INTEGER NOT NULL DEFAULT 0, next_attempt BIGINT NOT NULL, lease_token VARCHAR(32) DEFAULT NULL, lease_until BIGINT DEFAULT NULL, accepted_at BIGINT DEFAULT NULL, FOREIGN KEY(invitation_id) REFERENCES familyhub_invitations(id) ON DELETE CASCADE)'.$suffix);
        $pdo->exec('CREATE INDEX familyhub_invitation_mail_due ON familyhub_invitation_mail(state,next_attempt)');
    }
}
