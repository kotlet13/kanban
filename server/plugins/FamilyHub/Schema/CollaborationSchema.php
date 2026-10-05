<?php
namespace Kanboard\Plugin\FamilyHub\Schema;

class CollaborationSchema
{
    public static function ensureChannels(\PDO $pdo, $mysql)
    {
        $columns = $mysql ? $pdo->query("SELECT column_name FROM information_schema.columns WHERE table_schema=DATABASE() AND table_name='familyhub_inbox'")->fetchAll(\PDO::FETCH_COLUMN) : array_column($pdo->query('PRAGMA table_info(familyhub_inbox)')->fetchAll(\PDO::FETCH_ASSOC), 'name');
        if (!in_array('in_app', $columns, true)) { $pdo->exec('ALTER TABLE familyhub_inbox ADD COLUMN in_app INTEGER NOT NULL DEFAULT 1'); }
    }

    public static function createDelivery(\PDO $pdo, $mysql)
    {
        $pdo->exec("CREATE TABLE familyhub_deliveries(inbox_id BIGINT PRIMARY KEY, state VARCHAR(20) NOT NULL, attempts INTEGER NOT NULL, next_attempt BIGINT NOT NULL, expires_at BIGINT NOT NULL, lease_token VARCHAR(32) DEFAULT NULL, lease_until BIGINT DEFAULT NULL, sent_at BIGINT DEFAULT NULL)".($mysql ? ' ENGINE=InnoDB CHARSET=utf8mb4' : ''));
        $pdo->exec('CREATE INDEX familyhub_delivery_due ON familyhub_deliveries(state,next_attempt)');
    }

    public static function ensureInboxState(\PDO $pdo, $mysql)
    {
        $pdo->exec('CREATE TABLE IF NOT EXISTS familyhub_inbox_state(account_id VARCHAR(36) PRIMARY KEY, sequence BIGINT NOT NULL DEFAULT 0, visibility_revision BIGINT NOT NULL DEFAULT 0)'.($mysql ? ' ENGINE=InnoDB CHARSET=utf8mb4' : ''));
        $columns = $mysql ? $pdo->query("SELECT column_name FROM information_schema.columns WHERE table_schema=DATABASE() AND table_name='familyhub_inbox'")->fetchAll(\PDO::FETCH_COLUMN) : array_column($pdo->query('PRAGMA table_info(familyhub_inbox)')->fetchAll(\PDO::FETCH_ASSOC), 'name');
        foreach (['revision' => 'BIGINT NOT NULL DEFAULT 1', 'sequence' => 'BIGINT NOT NULL DEFAULT 0'] as $name => $definition) {
            if (!in_array($name, $columns, true)) { $pdo->exec('ALTER TABLE familyhub_inbox ADD COLUMN '.$name.' '.$definition); }
        }
        // Preserve any early development inbox rows with a full cursor backfill.
        foreach ($pdo->query('SELECT DISTINCT recipient_account_id FROM familyhub_inbox')->fetchAll(\PDO::FETCH_COLUMN) as $account) {
            $insert = $mysql ? 'INSERT IGNORE' : 'INSERT OR IGNORE';
            $pdo->prepare($insert.' INTO familyhub_inbox_state VALUES(?,0,0)')->execute([$account]);
            $rows = $pdo->prepare('SELECT id FROM familyhub_inbox WHERE recipient_account_id=? AND sequence=0 ORDER BY id'); $rows->execute([$account]);
            $ids = $rows->fetchAll(\PDO::FETCH_COLUMN); $rows->closeCursor();
            foreach ($ids as $id) {
                $pdo->prepare('UPDATE familyhub_inbox_state SET sequence=sequence+1 WHERE account_id=?')->execute([$account]);
                $statement = $pdo->prepare('SELECT sequence FROM familyhub_inbox_state WHERE account_id=?'); $statement->execute([$account]); $sequence = $statement->fetchColumn(); $statement->closeCursor();
                $pdo->prepare('UPDATE familyhub_inbox SET sequence=? WHERE id=?')->execute([$sequence, $id]);
            }
        }
    }

    public static function create(\PDO $pdo, $mysql)
    {
        $suffix = $mysql ? ' ENGINE=InnoDB CHARSET=utf8mb4' : '';
        $text = $mysql ? 'MEDIUMTEXT' : 'TEXT';
        foreach (['contract_version INTEGER NOT NULL DEFAULT 1', 'created_by VARCHAR(36) DEFAULT NULL', 'updated_by VARCHAR(36) DEFAULT NULL'] as $column) {
            $pdo->exec('ALTER TABLE familyhub_records ADD COLUMN '.$column);
        }
        $auto = $mysql ? 'BIGINT AUTO_INCREMENT PRIMARY KEY' : 'INTEGER PRIMARY KEY AUTOINCREMENT';
        $tables = [
            'familyhub_inbox_state' => 'account_id VARCHAR(36) PRIMARY KEY, sequence BIGINT NOT NULL DEFAULT 0, visibility_revision BIGINT NOT NULL DEFAULT 0',
            'familyhub_inbox' => 'id '.$auto.', event_key VARCHAR(64) NOT NULL, recipient_account_id VARCHAR(36) NOT NULL, scope_id VARCHAR(36) NOT NULL, category VARCHAR(20) NOT NULL, kind VARCHAR(40) NOT NULL, audience VARCHAR(20) NOT NULL, actor_account_id VARCHAR(36) DEFAULT NULL, target_type VARCHAR(30) NOT NULL, target_id VARCHAR(36) NOT NULL, target_revision BIGINT NOT NULL, group_key VARCHAR(120) NOT NULL, created_at VARCHAR(40) NOT NULL, read_at VARCHAR(40) DEFAULT NULL, revision BIGINT NOT NULL DEFAULT 1, sequence BIGINT NOT NULL, UNIQUE(event_key,recipient_account_id)',
            'familyhub_inbox_preferences' => 'scope_id VARCHAR(36) NOT NULL, account_id VARCHAR(36) NOT NULL, category VARCHAR(20) NOT NULL, settings '.$text.' NOT NULL, PRIMARY KEY(scope_id,account_id,category)',
            'familyhub_reminders' => 'id VARCHAR(36) PRIMARY KEY, scope_id VARCHAR(36) NOT NULL, account_id VARCHAR(36) NOT NULL, target_type VARCHAR(30) NOT NULL, target_id VARCHAR(36) NOT NULL, target_fingerprint VARCHAR(64) NOT NULL, remind_at VARCHAR(40) NOT NULL, remind_epoch BIGINT NOT NULL, revision BIGINT NOT NULL, state VARCHAR(20) NOT NULL',
            'familyhub_finance_policy' => 'scope_id VARCHAR(36) PRIMARY KEY, enabled INTEGER NOT NULL DEFAULT 0, revision BIGINT NOT NULL DEFAULT 0, sequence BIGINT NOT NULL DEFAULT 0',
            'familyhub_finance_grants' => 'scope_id VARCHAR(36) NOT NULL, account_id VARCHAR(36) NOT NULL, access_level VARCHAR(10) NOT NULL, PRIMARY KEY(scope_id,account_id)',
            'familyhub_finance_records' => 'scope_id VARCHAR(36) NOT NULL, id VARCHAR(36) NOT NULL, type VARCHAR(30) NOT NULL, revision BIGINT NOT NULL, deleted INTEGER NOT NULL DEFAULT 0, payload '.$text.' DEFAULT NULL, sequence BIGINT NOT NULL, updated_at VARCHAR(40) NOT NULL, created_by VARCHAR(36) NOT NULL, updated_by VARCHAR(36) NOT NULL, PRIMARY KEY(scope_id,id)',
            'familyhub_finance_operations' => 'scope_id VARCHAR(36) NOT NULL, account_id VARCHAR(36) NOT NULL, id VARCHAR(36) NOT NULL, request_hash VARCHAR(64) NOT NULL, response '.$text.' NOT NULL, status INTEGER NOT NULL, PRIMARY KEY(scope_id,account_id,id)',
            'familyhub_finance_audit' => 'scope_id VARCHAR(36) NOT NULL, record_id VARCHAR(36) NOT NULL, revision BIGINT NOT NULL, actor_account_id VARCHAR(36) NOT NULL, changed_at VARCHAR(40) NOT NULL, before_json '.$text.' DEFAULT NULL, after_json '.$text.' NOT NULL, op_id VARCHAR(36) NOT NULL, PRIMARY KEY(scope_id,record_id,revision)',
        ];
        foreach ($tables as $table => $columns) { $pdo->exec('CREATE TABLE '.$table.' ('.$columns.')'.$suffix); }
        $pdo->exec('CREATE INDEX familyhub_inbox_recipient ON familyhub_inbox(recipient_account_id,id)');
        $pdo->exec('CREATE INDEX familyhub_reminder_due ON familyhub_reminders(state,remind_epoch)');
        $pdo->exec('CREATE INDEX familyhub_finance_pull ON familyhub_finance_records(scope_id,sequence)');
    }
}
