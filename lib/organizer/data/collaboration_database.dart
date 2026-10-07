import 'dart:async';
import 'package:drift/drift.dart';
import '../domain/collaboration_models.dart' show AccountSession;

/// Shared rows and their immutable outgoing operations use one SQLite commit.
/// Anonymous and explicitly enabled private workspaces share this atomic store.
class CollaborationDatabase extends GeneratedDatabase {
  CollaborationDatabase(super.executor);
  @override
  int get schemaVersion => 5;
  AccountSession? personalProfile;
  final personalChanges = StreamController<void>.broadcast();
  void activatePersonal(AccountSession? profile) {
    personalIdentityGeneration++;
    personalProfile = profile;
    personalChanges.add(null);
  }

  Future<void> touchPersonal() => execute(
    "INSERT INTO local_meta(name,value) VALUES('organizer_generation','1') ON CONFLICT(name) DO UPDATE SET value=CAST(value AS INTEGER)+1",
  );
  int personalIdentityGeneration = 0;
  void personalChanged() {
    if (!personalChanges.isClosed) personalChanges.add(null);
  }

  @override
  Iterable<TableInfo<Table, dynamic>> get allTables => const [];
  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (_) async {
      for (final statement in _schema) {
        await customStatement(statement);
      }
      for (final statement in [
        ..._upgrade2,
        ..._upgrade3,
        ..._upgrade4,
        ..._upgrade5,
      ]) {
        await customStatement(statement);
      }
    },
    onUpgrade: (_, from, to) async {
      if (from < 1 || from > 4 || to != 5) {
        throw const FormatException('Unsupported shared database schema');
      }
      if (from < 2) {
        for (final statement in _upgrade2) {
          await customStatement(statement);
        }
      }
      if (from < 3) {
        for (final statement in _upgrade3) {
          await customStatement(statement);
        }
      }
      if (from < 4) {
        for (final statement in _upgrade4) {
          await customStatement(statement);
        }
      }
      for (final statement in _upgrade5) {
        await customStatement(statement);
      }
    },
    beforeOpen: (_) async {
      await customStatement('PRAGMA foreign_keys = ON');
      await customStatement('PRAGMA busy_timeout = 5000');
    },
  );

  static const _schema = [
    'CREATE TABLE accounts (partition TEXT PRIMARY KEY, profile TEXT NOT NULL)',
    'CREATE TABLE local_meta (name TEXT PRIMARY KEY, value TEXT NOT NULL)',
    '''CREATE TABLE scopes (partition TEXT NOT NULL, id TEXT NOT NULL, data TEXT NOT NULL,
       cursor INTEGER NOT NULL DEFAULT 0, blocked INTEGER NOT NULL DEFAULT 0,
       PRIMARY KEY(partition,id), FOREIGN KEY(partition) REFERENCES accounts(partition))''',
    '''CREATE TABLE records (partition TEXT NOT NULL, scope_id TEXT NOT NULL, id TEXT NOT NULL,
       type TEXT NOT NULL, local_revision INTEGER NOT NULL, server_revision INTEGER NOT NULL,
       payload TEXT, deleted INTEGER NOT NULL, remote TEXT,
       PRIMARY KEY(partition,scope_id,id),
       FOREIGN KEY(partition,scope_id) REFERENCES scopes(partition,id))''',
    '''CREATE TABLE outbox (sequence INTEGER PRIMARY KEY AUTOINCREMENT, op_id TEXT NOT NULL UNIQUE,
       partition TEXT NOT NULL, scope_id TEXT NOT NULL, record_id TEXT NOT NULL,
       request TEXT NOT NULL, state TEXT NOT NULL DEFAULT 'pending',
       FOREIGN KEY(partition,scope_id,record_id) REFERENCES records(partition,scope_id,id))''',
    'CREATE INDEX outbox_partition ON outbox(partition,sequence)',
    '''CREATE TABLE conflicts (id TEXT PRIMARY KEY, partition TEXT NOT NULL, scope_id TEXT NOT NULL,
       record_id TEXT NOT NULL, type TEXT NOT NULL, reason TEXT NOT NULL, remote TEXT,
       FOREIGN KEY(partition,scope_id,record_id) REFERENCES records(partition,scope_id,id))''',
    '''CREATE TABLE sync_leases (partition TEXT PRIMARY KEY, owner TEXT NOT NULL,
       expires_at INTEGER NOT NULL, FOREIGN KEY(partition) REFERENCES accounts(partition))''',
  ];

  static const _upgrade2 = [
    'ALTER TABLE outbox ADD COLUMN wire_version INTEGER NOT NULL DEFAULT 1',
    'ALTER TABLE scopes ADD COLUMN finance_cursor INTEGER NOT NULL DEFAULT 0',
    'ALTER TABLE scopes ADD COLUMN finance_access_revision INTEGER NOT NULL DEFAULT 0',
    'ALTER TABLE scopes ADD COLUMN finance_policy TEXT',
    'ALTER TABLE scopes ADD COLUMN finance_blocked INTEGER NOT NULL DEFAULT 0',
    'CREATE TABLE members (partition TEXT NOT NULL,scope_id TEXT NOT NULL,account_id TEXT NOT NULL,data TEXT NOT NULL,PRIMARY KEY(partition,scope_id,account_id))',
    'CREATE TABLE inbox (partition TEXT NOT NULL,id INTEGER NOT NULL,data TEXT NOT NULL,PRIMARY KEY(partition,id))',
    'CREATE TABLE inbox_state (partition TEXT PRIMARY KEY,cursor INTEGER NOT NULL DEFAULT 0,visibility_revision INTEGER NOT NULL DEFAULT 0)',
    "CREATE TABLE commands (sequence INTEGER PRIMARY KEY AUTOINCREMENT,id TEXT NOT NULL UNIQUE,partition TEXT NOT NULL,operation TEXT NOT NULL,params TEXT NOT NULL,entity_key TEXT NOT NULL,state TEXT NOT NULL DEFAULT 'pending')",
    'CREATE INDEX commands_partition ON commands(partition,sequence)',
    'CREATE TABLE notification_preferences (partition TEXT NOT NULL,scope_id TEXT NOT NULL,data TEXT NOT NULL,PRIMARY KEY(partition,scope_id))',
    'CREATE TABLE scheduled_reminders (partition TEXT NOT NULL,id TEXT NOT NULL,scope_id TEXT NOT NULL,data TEXT NOT NULL,PRIMARY KEY(partition,id))',
    'CREATE TABLE finance_records (partition TEXT NOT NULL,scope_id TEXT NOT NULL,id TEXT NOT NULL,type TEXT NOT NULL,local_revision INTEGER NOT NULL,server_revision INTEGER NOT NULL,payload TEXT,deleted INTEGER NOT NULL,remote TEXT,PRIMARY KEY(partition,scope_id,id))',
    "CREATE TABLE finance_outbox (sequence INTEGER PRIMARY KEY AUTOINCREMENT,op_id TEXT NOT NULL UNIQUE,partition TEXT NOT NULL,scope_id TEXT NOT NULL,record_id TEXT NOT NULL,request TEXT NOT NULL,state TEXT NOT NULL DEFAULT 'pending')",
    'CREATE INDEX finance_outbox_partition ON finance_outbox(partition,sequence)',
    'CREATE TABLE finance_conflicts (id TEXT PRIMARY KEY,partition TEXT NOT NULL,scope_id TEXT NOT NULL,record_id TEXT NOT NULL,type TEXT NOT NULL,reason TEXT NOT NULL,remote TEXT)',
  ];

  static const _upgrade3 = [
    'ALTER TABLE inbox ADD COLUMN remote TEXT',
    'ALTER TABLE scheduled_reminders ADD COLUMN remote TEXT',
    'ALTER TABLE scopes ADD COLUMN finance_complete INTEGER NOT NULL DEFAULT 0',
    'UPDATE inbox SET remote=data',
    'UPDATE scheduled_reminders SET remote=data',
  ];

  static const _upgrade4 = [
    "CREATE TABLE personal_workspaces(id TEXT PRIMARY KEY,revision INTEGER NOT NULL DEFAULT 0,partition TEXT,scope_id TEXT,paused INTEGER NOT NULL DEFAULT 0,enabled INTEGER NOT NULL DEFAULT 1,migration_snapshot TEXT)",
    "CREATE TABLE personal_records(workspace TEXT NOT NULL,id TEXT NOT NULL,type TEXT NOT NULL,payload TEXT NOT NULL,PRIMARY KEY(workspace,id))",
    "CREATE TABLE personal_record_map(workspace TEXT NOT NULL,id TEXT NOT NULL,remote_id TEXT NOT NULL,type TEXT NOT NULL,PRIMARY KEY(workspace,id),UNIQUE(workspace,remote_id))",
    "CREATE TABLE restored_backups(id TEXT PRIMARY KEY,created_at TEXT NOT NULL,source_partition TEXT,data TEXT NOT NULL)",
  ];

  static const _upgrade5 = [
    "CREATE TABLE device_gardens(id TEXT PRIMARY KEY,payload TEXT NOT NULL)",
  ];

  Future<List<Map<String, dynamic>>> rows(
    String sql, [
    List<Object?> args = const [],
  ]) async => (await customSelect(
    sql,
    variables: args.map(_variable).toList(),
  ).get()).map((row) => row.data).toList();
  Future<void> execute(String sql, [List<Object?> args = const []]) =>
      customStatement(sql, args);
  Variable<Object> _variable(Object? value) => switch (value) {
    int value => Variable<int>(value),
    String value => Variable<String>(value),
    null => const Variable<String>(null),
    _ => throw ArgumentError('Unsupported SQL argument'),
  };
}
