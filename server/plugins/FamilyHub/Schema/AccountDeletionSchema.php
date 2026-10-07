<?php
namespace Kanboard\Plugin\FamilyHub\Schema;

class AccountDeletionSchema
{
    public static function create(\PDO $pdo, $mysql)
    {
        // No user/account IDs, credentials or payloads survive in receipts.
        $pdo->exec('CREATE TABLE familyhub_deletion_receipts(operation_id VARCHAR(36) PRIMARY KEY, token_hash VARCHAR(64) NOT NULL, deleted_at BIGINT NOT NULL, complete INTEGER NOT NULL DEFAULT 0, cancelled INTEGER NOT NULL DEFAULT 0)'.($mysql ? ' ENGINE=InnoDB CHARSET=utf8mb4' : ''));
        $pdo->exec('CREATE TABLE familyhub_deletion_files(operation_id VARCHAR(36) NOT NULL, path_hash VARCHAR(64) NOT NULL, path VARCHAR(1024) NOT NULL, PRIMARY KEY(operation_id,path_hash), FOREIGN KEY(operation_id) REFERENCES familyhub_deletion_receipts(operation_id) ON DELETE CASCADE)'.($mysql ? ' ENGINE=InnoDB CHARSET=utf8mb4' : ''));
    }
}
