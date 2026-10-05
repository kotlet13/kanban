<?php
namespace Kanboard\Plugin\FamilyHub\Schema;

/** No relationship with legacy projects/metadata or automatic Kanboard roles. */
class NativeSchema
{
    public static function ensureIdentities(\PDO $pdo, $mysql)
    {
        $exists = $mysql ? "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema=DATABASE() AND table_name='familyhub_instance'" : "SELECT COUNT(*) FROM sqlite_master WHERE type='table' AND name='familyhub_instance'";
        if ((int)$pdo->query($exists)->fetchColumn() === 0) {
            $suffix = $mysql ? ' ENGINE=InnoDB CHARSET=utf8mb4' : '';
            $pdo->exec('CREATE TABLE familyhub_instance(id INTEGER PRIMARY KEY,server_id VARCHAR(36) NOT NULL)'.$suffix);
            $hex = bin2hex(random_bytes(16));
            $id = substr($hex,0,8).'-'.substr($hex,8,4).'-4'.substr($hex,13,3).'-a'.substr($hex,17,3).'-'.substr($hex,20);
            $pdo->prepare('INSERT INTO familyhub_instance VALUES(1,?)')->execute([$id]);
            $pdo->exec('CREATE TABLE familyhub_accounts(user_id INTEGER PRIMARY KEY,account_id VARCHAR(36) NOT NULL UNIQUE,FOREIGN KEY(user_id) REFERENCES users(id) ON DELETE CASCADE)'.$suffix);
        }
        foreach (['familyhub_members' => ['account_id'], 'familyhub_devices' => ['account_id'],
                  'familyhub_invitations' => ['creator_account_id', 'accepted_account_id']] as $table => $columns) {
            $present = $mysql ? $pdo->query("SELECT column_name FROM information_schema.columns WHERE table_schema=DATABASE() AND table_name='$table'")->fetchAll(\PDO::FETCH_COLUMN) : array_column($pdo->query('PRAGMA table_info('.$table.')')->fetchAll(\PDO::FETCH_ASSOC), 'name');
            foreach ($columns as $column) {
                if (!in_array($column, $present, true)) {
                    $pdo->exec('ALTER TABLE '.$table.' ADD COLUMN '.$column.' VARCHAR(36) '.($column === 'accepted_account_id' ? 'DEFAULT NULL' : "NOT NULL DEFAULT ''"));
                }
            }
        }
    }

    public static function create(\PDO $pdo, $mysql)
    {
        $text = $mysql ? 'MEDIUMTEXT' : 'TEXT';
        $suffix = $mysql ? ' ENGINE=InnoDB CHARSET=utf8mb4' : '';
        $tables = [
            'familyhub_instance' => 'id INTEGER PRIMARY KEY, server_id VARCHAR(36) NOT NULL',
            'familyhub_accounts' => 'user_id INTEGER PRIMARY KEY, account_id VARCHAR(36) NOT NULL UNIQUE, FOREIGN KEY(user_id) REFERENCES users(id) ON DELETE CASCADE',
            'familyhub_native_lock' => 'id INTEGER PRIMARY KEY, counter BIGINT NOT NULL',
            'familyhub_scopes' => 'id VARCHAR(36) PRIMARY KEY, kind VARCHAR(20) NOT NULL, name VARCHAR(200) NOT NULL, owner_id INTEGER NOT NULL, sequence BIGINT NOT NULL DEFAULT 0, created_at BIGINT NOT NULL',
            'familyhub_members' => 'scope_id VARCHAR(36) NOT NULL, user_id INTEGER NOT NULL, account_id VARCHAR(36) NOT NULL, role VARCHAR(20) NOT NULL, active INTEGER NOT NULL DEFAULT 1, PRIMARY KEY(scope_id,user_id), FOREIGN KEY(scope_id) REFERENCES familyhub_scopes(id)',
            'familyhub_records' => 'scope_id VARCHAR(36) NOT NULL, id VARCHAR(36) NOT NULL, type VARCHAR(30) NOT NULL, revision BIGINT NOT NULL, deleted INTEGER NOT NULL DEFAULT 0, payload '.$text.' DEFAULT NULL, sequence BIGINT NOT NULL, updated_at VARCHAR(40) NOT NULL, PRIMARY KEY(scope_id,id), FOREIGN KEY(scope_id) REFERENCES familyhub_scopes(id)',
            'familyhub_operations' => 'scope_id VARCHAR(36) NOT NULL, user_id INTEGER NOT NULL, id VARCHAR(36) NOT NULL, request_hash VARCHAR(64) NOT NULL, response '.$text.' NOT NULL, status INTEGER NOT NULL, PRIMARY KEY(scope_id,user_id,id), FOREIGN KEY(scope_id) REFERENCES familyhub_scopes(id)',
            'familyhub_devices' => 'id VARCHAR(36) PRIMARY KEY, user_id INTEGER NOT NULL, account_id VARCHAR(36) NOT NULL, name VARCHAR(80) NOT NULL, token_hash VARCHAR(64) NOT NULL UNIQUE, credentials_hash VARCHAR(64) NOT NULL, created_at BIGINT NOT NULL, expires_at BIGINT NOT NULL, revoked_at BIGINT DEFAULT NULL',
            'familyhub_invitations' => 'id VARCHAR(36) PRIMARY KEY, scope_id VARCHAR(36) NOT NULL, creator_id INTEGER NOT NULL, creator_account_id VARCHAR(36) NOT NULL, recipient_username VARCHAR(64) NOT NULL, role VARCHAR(20) NOT NULL, token_hash VARCHAR(64) NOT NULL UNIQUE, created_at BIGINT NOT NULL, expires_at BIGINT NOT NULL, accepted_at BIGINT DEFAULT NULL, accepted_by INTEGER DEFAULT NULL, accepted_account_id VARCHAR(36) DEFAULT NULL, revoked_at BIGINT DEFAULT NULL, FOREIGN KEY(scope_id) REFERENCES familyhub_scopes(id)',
            'familyhub_rate_limits' => 'id VARCHAR(64) PRIMARY KEY, window_start BIGINT NOT NULL, attempts INTEGER NOT NULL',
            'familyhub_totp_state' => 'user_id INTEGER PRIMARY KEY, secret_hash VARCHAR(64) NOT NULL, last_step BIGINT NOT NULL',
        ];
        foreach ($tables as $table => $columns) {
            $pdo->exec('CREATE TABLE '.$table.' ('.$columns.')'.$suffix);
        }
        $pdo->exec('INSERT INTO familyhub_native_lock (id,counter) VALUES (1,0)');
        $hex = bin2hex(random_bytes(16));
        $serverId = substr($hex, 0, 8).'-'.substr($hex, 8, 4).'-4'.substr($hex, 13, 3).'-a'.substr($hex, 17, 3).'-'.substr($hex, 20);
        $statement = $pdo->prepare('INSERT INTO familyhub_instance(id,server_id) VALUES(1,?)');
        $statement->execute([$serverId]);
        $pdo->exec('CREATE INDEX familyhub_record_pull ON familyhub_records(scope_id,sequence)');
        $pdo->exec('CREATE INDEX familyhub_member_user ON familyhub_members(user_id,active)');
        $pdo->exec('CREATE INDEX familyhub_device_user ON familyhub_devices(user_id)');
        $pdo->exec('CREATE INDEX familyhub_native_invite_scope ON familyhub_invitations(scope_id)');
    }
}
