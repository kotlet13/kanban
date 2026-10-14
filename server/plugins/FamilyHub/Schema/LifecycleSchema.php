<?php
namespace Kanboard\Plugin\FamilyHub\Schema;

/** Durable scope identities and task-relative reminders. Existing data stays intact. */
class LifecycleSchema
{
    public static function create(\PDO $pdo, $mysql)
    {
        foreach (['familyhub_scopes'=>['deleted_at'=>'BIGINT DEFAULT NULL'],
                  'familyhub_push_registrations'=>['notification_format'=>'INTEGER NOT NULL DEFAULT 1'],
                  'familyhub_reminders'=>['schedule_mode'=>"VARCHAR(16) NOT NULL DEFAULT 'absolute'",'offset_minutes'=>'INTEGER DEFAULT NULL']] as $table=>$columns) {
            $present=$mysql?$pdo->query("SELECT column_name FROM information_schema.columns WHERE table_schema=DATABASE() AND table_name='$table'")->fetchAll(\PDO::FETCH_COLUMN):array_column($pdo->query('PRAGMA table_info('.$table.')')->fetchAll(\PDO::FETCH_ASSOC),'name');
            foreach ($columns as $name=>$definition) { if (!in_array($name,$present,true)) { $pdo->exec('ALTER TABLE '.$table.' ADD COLUMN '.$name.' '.$definition); } }
        }
        // Private file removal is retried after the atomic SQL deletion, never before it.
        $pdo->exec('CREATE TABLE IF NOT EXISTS familyhub_scope_deletion_files (scope_id VARCHAR(36) NOT NULL,path_hash VARCHAR(64) NOT NULL,path VARCHAR(1024) NOT NULL,PRIMARY KEY(scope_id,path_hash))'.($mysql?' ENGINE=InnoDB CHARSET=utf8mb4':''));
    }
}
