<?php
namespace Kanboard\Plugin\FamilyHub\Schema;

/** Authorized key-recipient reservations; acceptance alone activates SQL membership. */
class PreauthorizedInvitationSchema
{
    public static function create(\PDO $pdo,$mysql)
    {
        $suffix=$mysql?' ENGINE=InnoDB CHARSET=utf8mb4':'';$text=$mysql?'MEDIUMTEXT':'TEXT';
        $pdo->exec('CREATE TABLE IF NOT EXISTS familyhub_crypto_invitation_reservations_v5(scope_id VARCHAR(36) NOT NULL,account_id VARCHAR(36) NOT NULL,invitation_id VARCHAR(36) NOT NULL,invitation_scope_id VARCHAR(36) NOT NULL,proof_hash VARCHAR(64) NOT NULL,member '.$text.' NOT NULL,state VARCHAR(16) NOT NULL,PRIMARY KEY(scope_id,account_id))'.$suffix);
        $pdo->exec('CREATE TABLE IF NOT EXISTS familyhub_crypto_invitation_publications_v5(invitation_id VARCHAR(36) PRIMARY KEY,head_hash VARCHAR(64) NOT NULL,child_heads '.$text.' NOT NULL,authorization '.$text.' NOT NULL,created_at BIGINT NOT NULL)'.$suffix);
    }
}
