<?php
namespace Kanboard\Plugin\FamilyHub\Schema;

class AccountSchema
{
    public static function create(\PDO $pdo, $mysql)
    {
        $suffix = $mysql ? ' ENGINE=InnoDB CHARSET=utf8mb4' : '';
        $text = $mysql ? 'MEDIUMTEXT' : 'TEXT';
        $tables = [
            'familyhub_personal_scopes' => 'account_id VARCHAR(36) PRIMARY KEY, scope_id VARCHAR(36) NOT NULL UNIQUE, FOREIGN KEY(account_id) REFERENCES familyhub_accounts(account_id) ON DELETE CASCADE, FOREIGN KEY(scope_id) REFERENCES familyhub_scopes(id)',
            'familyhub_enrollment' => 'id VARCHAR(36) PRIMARY KEY, token_hash VARCHAR(64) NOT NULL UNIQUE, created_at BIGINT NOT NULL, expires_at BIGINT NOT NULL, consumed_at BIGINT DEFAULT NULL, revoked_at BIGINT DEFAULT NULL',
            'familyhub_email_identities' => 'account_id VARCHAR(36) PRIMARY KEY, email VARCHAR(254) DEFAULT NULL, verified_at BIGINT DEFAULT NULL, pending_email VARCHAR(254) DEFAULT NULL, revision BIGINT NOT NULL DEFAULT 0, FOREIGN KEY(account_id) REFERENCES familyhub_accounts(account_id) ON DELETE CASCADE',
            'familyhub_account_tokens' => 'id VARCHAR(36) PRIMARY KEY, account_id VARCHAR(36) NOT NULL, purpose VARCHAR(20) NOT NULL, token_hash VARCHAR(64) NOT NULL UNIQUE, email VARCHAR(254) NOT NULL, identity_revision BIGINT NOT NULL, fingerprint VARCHAR(64) NOT NULL, created_at BIGINT NOT NULL, expires_at BIGINT NOT NULL, consumed_at BIGINT DEFAULT NULL, revoked_at BIGINT DEFAULT NULL, FOREIGN KEY(account_id) REFERENCES familyhub_accounts(account_id) ON DELETE CASCADE',
            'familyhub_account_mail' => 'token_id VARCHAR(36) PRIMARY KEY, token_cipher '.$text.' DEFAULT NULL, language VARCHAR(2) NOT NULL, state VARCHAR(20) NOT NULL, attempts INTEGER NOT NULL DEFAULT 0, next_attempt BIGINT NOT NULL, lease_token VARCHAR(32) DEFAULT NULL, lease_until BIGINT DEFAULT NULL, accepted_at BIGINT DEFAULT NULL, FOREIGN KEY(token_id) REFERENCES familyhub_account_tokens(id) ON DELETE CASCADE',
        ];
        foreach ($tables as $table => $columns) { $pdo->exec('CREATE TABLE '.$table.' ('.$columns.')'.$suffix); }
        $pdo->exec('CREATE INDEX familyhub_account_token_owner ON familyhub_account_tokens(account_id,purpose)');
        $pdo->exec('CREATE INDEX familyhub_account_mail_due ON familyhub_account_mail(state,next_attempt)');
    }
}
