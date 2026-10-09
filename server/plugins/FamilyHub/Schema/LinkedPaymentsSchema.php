<?php
namespace Kanboard\Plugin\FamilyHub\Schema;

class LinkedPaymentsSchema
{
    public static function create(\PDO $pdo, $mysql)
    {
        $text = $mysql ? 'LONGTEXT' : 'TEXT';
        $pdo->exec('CREATE TABLE IF NOT EXISTS familyhub_payment_events (scope_id VARCHAR(36) NOT NULL, event_id VARCHAR(36) NOT NULL, entry_id VARCHAR(36) NOT NULL, payer_account_id VARCHAR(36) NOT NULL, revision BIGINT NOT NULL, data '.$text.' NOT NULL, PRIMARY KEY(scope_id,event_id), UNIQUE(scope_id,entry_id))');
        $pdo->exec('CREATE TABLE IF NOT EXISTS familyhub_payment_projections (scope_id VARCHAR(36) NOT NULL, event_id VARCHAR(36) NOT NULL, source_scope_id VARCHAR(36) NOT NULL, owner_account_id VARCHAR(36) NOT NULL, data '.$text.' NOT NULL, PRIMARY KEY(scope_id,event_id))');
        $pdo->exec('CREATE TABLE IF NOT EXISTS familyhub_payment_cash (scope_id VARCHAR(36) NOT NULL, movement_id VARCHAR(36) NOT NULL, data '.$text.' NOT NULL, PRIMARY KEY(scope_id,movement_id))');
    }
}
