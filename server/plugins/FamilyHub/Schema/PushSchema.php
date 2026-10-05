<?php
namespace Kanboard\Plugin\FamilyHub\Schema;

class PushSchema
{
    public static function create(\PDO $pdo, $mysql)
    {
        $suffix = $mysql ? ' ENGINE=InnoDB CHARSET=utf8mb4' : '';
        $pdo->exec('CREATE TABLE familyhub_push_registrations(device_id VARCHAR(36) PRIMARY KEY,account_id VARCHAR(36) NOT NULL,token_hash VARCHAR(64) DEFAULT NULL UNIQUE,token_cipher TEXT DEFAULT NULL,project_id VARCHAR(30) NOT NULL,platform VARCHAR(10) DEFAULT NULL,language VARCHAR(2) DEFAULT NULL,revision BIGINT NOT NULL,active INTEGER NOT NULL,updated_at BIGINT NOT NULL,FOREIGN KEY(device_id) REFERENCES familyhub_devices(id) ON DELETE CASCADE)'.$suffix);
        $pdo->exec('CREATE INDEX familyhub_push_account ON familyhub_push_registrations(account_id,active)');
        $pdo->exec('CREATE TABLE familyhub_push_jobs(inbox_id BIGINT NOT NULL,device_id VARCHAR(36) NOT NULL,registration_revision BIGINT NOT NULL,token_hash VARCHAR(64) NOT NULL,state VARCHAR(20) NOT NULL,attempts INTEGER NOT NULL,next_attempt BIGINT NOT NULL,expires_at BIGINT NOT NULL,lease_token VARCHAR(32) DEFAULT NULL,lease_until BIGINT DEFAULT NULL,sent_at BIGINT DEFAULT NULL,PRIMARY KEY(inbox_id,device_id,registration_revision))'.$suffix);
        $pdo->exec('CREATE INDEX familyhub_push_due ON familyhub_push_jobs(state,next_attempt)');
        $pdo->exec('CREATE INDEX familyhub_inbox_group ON familyhub_inbox(recipient_account_id,group_key,kind,category,audience,id)');
    }
}
