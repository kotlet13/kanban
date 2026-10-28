# Fresh FamilyHub data reset: local primitives and conditional production plan

This is a new procedure, separate from the preservation-only schema19→23 upgrade.
No production operation was performed by the helper author during preparation.
The private CLI controller and shell wrapper now cover capture/seal, six-worker
maintenance, full backup, verified restore gate, staged reset, scoped quarantine,
read verification and explicit releases. There is no public web entry point.

`ResetDatabase.php` accepts an existing PDO connection and an independently approved
complete schema-definition manifest. `plan()` is read-only and returns counts,
exact selected core-user identities, old server incarnation and a whole-database
stale-state hash. Keep this plan private: usernames and database definitions are
administrative material. `apply()` performs DML in one transaction, preserves all
DDL/core rows except the exact selected users, empties every reviewed FamilyHub
table, and reseeds only `familyhub_instance` with a fresh random server ID and
`familyhub_native_lock` with zero. It never resets auto-increment values. MySQL
canonical CREATE definitions omit only the volatile table `AUTO_INCREMENT=N`
option; column auto-increment declarations remain part of the definition.

The actual fresh schema23 fixture has177 FamilyHub tables. Unknown tables, DDL,
views, triggers, routines/events, unexpected account mappings, target admins,
missing active admin, foreign core references, stale/replayed plan and incomplete
maintenance flags stop the operation. Foreign keys remain enforced; deletion order
comes from the complete reviewed FK graph. The core-user reference check is
conservative: core metadata/session/preferences referencing a target also stop,
rather than silently cascading their deletion. No graph exception is authorized.

The low-level class's maintenance flags are caller assertions. For production use
only the sealed `operate.sh` and `reset.php` controller: they bind real paused
crontab/process snapshots, HTTPS maintenance bytes and65second clock, verified
restore proof and scoped file inventory. The controller acquires the same existing
exclusive migration.lock inode as NativeCryptoMaintenanceLease, holds it across
quarantine and SQL, and writes a durable state journal. The exporter establishes
that lock before its frozen full-data backup inventory. No application bootstrap,
delivery worker, business RPC, authentication or enrollment is invoked.

`InventoryFiles.php` reads only DATA_DIR/familyhub/attachments and ideas, including
empty directories, modes, binary sizes and SHA256. It rejects symlinks, unknown
FamilyHub namespaces, special files and configurable file/byte bounds. It bounds total entries and checks remaining bytes before hashing. It does
not traverse core files/cache, protected backups, external evidence or the crypto
lock. Encrypted crypto blobs/chunks, migration staging and moderation chunks are
SQL data and are covered by the DB reset. No file is deleted or moved by this inventory helper; reset.php separately quarantines the exact two reviewed namespaces.

## Production scope and gates

The user's conditional production instruction becomes actionable only after the
new fresh-install/account/recovery workflow passes its agreed local tests. This
primitive fixture is not that application workflow or a native recovery PASS.

1. Freeze reviewed source and independently create a complete schema23 DDL manifest
   from known core/plugin source and the verified current backup schema. Pin the
   exact dedicated installation root, private DATA_DIR, database, old SID, exact
   three FamilyHub account/user mappings and all retained administrator IDs. No
   hostname or path wildcard is permitted. Stop for extra accounts, unknown
   objects, stale schema or any target core references. Inspect legacy core project
   ownership/membership, task/comment/file/subtask references explicitly; do not
   classify unrelated projects or another installation as application reset data.
2. Preserve hosting source/configuration, DB connection credentials, admin password
   and TOTP/API identity, settings and plugin version rows, domain/TLS/rewrite,
   private SMTP/account-mail/push encryption keys and FCM credentials, PHP/Sodium,
   cron definitions and every unrelated site/database. SMTP/FCM **configuration**
   stays; old account/device registrations, push/mail delivery queues and old
   notification preferences are FamilyHub user data and must be empty.
3. Enter real HTTP503 maintenance for exactly this installation. Save and pause
   all six FamilyHub worker crons (old five plus security-mail), preserving all
   unrelated cron lines byte-for-byte. Wait at least65 actual seconds and verify
   no worker remains. Acquire the real exclusive existing migration.lock lease.
   Never rename familyhub/crypto or replace migration.lock while holding its fd.
4. Under maintenance take a fresh complete private DB/source/DATA/config/key/cron
   backup. Verify full isolated MariaDB10.11.19 restore and exact rows, definitions,
   files, empty directories and configuration before reset. Keep these safety
   backups/evidence outside Git/webroot; the reset instruction does not authorize
   deleting them. The existing upgrade export/restore code is reference material;
   its schema19 deployment pins must not be bypassed or misrepresented as schema23
   reset support.
5. Produce and review plan+file manifest. Journal the source/target paths and hashes
   in a fresh private0700 operation directory. Quarantine only the exact validated
   attachments/ideas directories into a fresh private destination on the same
   filesystem, preserving all files and the crypto lock inode. Recreate only those
   two empty private0700 live directories if they previously existed. Re-inventory
   quarantine against the frozen file manifest. All other DATA bytes stay exact.
   Do not run a generic recursive deletion, truncate tables, drop schema or remove
   the whole DATA_DIR/familyhub root.
6. With maintenance, cron pause, lease and verified quarantine still holding,
   execute the exact approved DB plan once. It clears accounts/email/TOTP/device
   sessions/enrollment/tokens/invitations, all business and finance data,
   notifications/mail/push queues, changes/cursors/receipts/rate counters,
   account/scope/device crypto identity and proofs, encrypted blobs and all staged
   migration/deletion/moderation data. It replaces the server incarnation and
   keeps current schema23 installed. It removes only the three pinned nonadmin
   core users; retained admin/config/settings/source/keys/core rows must compare
   exact, apart from the intentionally new SID/FH lock seed.
7. Verify all177 reviewed FamilyHub tables empty except the two seed rows; no old
   user/device/crypto/blob/migration row remains; new SID differs from old; all
   retained rows/DDL and unrelated filesystem inventories are unchanged. Release
   HTTP while worker crons stay paused, verify actual TLS capabilities/new SID
   and unchanged features, then restore exactly the original cron after an empty
   queue check. Do not manually run delivery workers as a smoke test.
8. Only the newly tested app performs new enrollment/account/file/key setup.
   Confirm a new recovery KEY file can restore the new account/local key through
   existing formats. A key file has no business-data snapshot. Old account FILEs,
   invitation tokens, signed commands, account-bound backups and device tokens
   belong to the old SID/account incarnation and must never be accepted as fresh
   authorization. Old local data remains isolated on existing devices; reconnect
   must fail closed without uploading it to a new account or silently erasing it.

If interrupted before DB commit, keep maintenance/cron pause, inspect the durable
journal, and restore the exact quarantined directories before aborting. Filesystem
rename plus SQL commit is not a single atomic transaction. After DB commit and
before any new client use, the verified full old snapshot can be restored under
maintenance as an intentional abort. Once a new account/client writes, a blind
rollback is unsafe; retain both incarnations and reconcile explicitly. Do not
release workers against mixed old/new files and database state.

## Local verification, 28 October2026

- SQLite: complete real Kanboard128 migrations + FamilyHub23,16 assertions PASS
  on attempt2. Attempt1 invoked omitted core migration49; no reset ran.
- MariaDB10.11.19: complete real Kanboard139 migrations + FamilyHub23,16 assertions
  PASS on attempt3. Attempt1 used Unix-socket startup readiness before TCP became
  ready; attempt2 omitted the synthetic DB_DRIVER constant required by core
  migration46. Neither reached reset assertions. No fourth attempt.
- File inventory:8 assertions PASS attempt1 in a fresh private synthetic tmp tree.
  Read-only/binary/modes/empty dirs/bounds/symlink/unknown namespace behavior tested.
- DB checks cover exact identity/count, core-reference stop, unknown schema,
  maintenance/drain, stale plan/replay, new SID, absent old sessions, empty account
  map, removed staged migration/blob chunks, exact retained admin/settings and DDL.
  They do not exercise HTTP signatures, real cron/HTTP503, real process drain,
  quarantine/restore crash recovery, platform key stores, native UI or devices.

Evidence: `build/qa/fresh-reset-20261028`. Only owned disposable Docker containers
and anonymous volumes were removed. No existing container, installation, protected
backup or user data was modified. No production or device/network operation ran.
The MariaDB runner's network joins only a fresh database container with network
none, no host ports, and read-only source; it cannot address hosting.


## Concrete sealed operation

`capture.php` is read-only and may run only from a fresh private subdirectory,
with its sibling ResetDatabase.php and crypto-runtime.php. It accepts exactly the
reviewed production or test1 profile and a current0600 crontab capture file. It
requires schema23,225tables,200source files,127crypto tables, three native accounts,
no incoming cross-database FK, no opaque core session row, no target avatar and no
target core-user reference. The production operator independently confirmed the
retained administrator's remember_me row and null target avatars. It prints hashes,
paths, exact selected user IDs/names/roles and table definitions; no passwords or
key bytes. Save its JSON privately.

`seal.py CAPTURE NEW_PRIVATE_OUTPUT` rechecks the fixed target/SID, fresh capture,
local200source,177FamilyHub/225total tables and independent127crypto+three changed
historical DDL definitions. It creates no credentials. It emits a fresh exact
hostWork directory and helper hashes. Copy every sealed file there, verify hashes
and use that returned WORK. If helpers were edited after sealing, seal to a new
private output and transfer the newly frozen files rather than using stale copies.

```sh
sh WORK/operate.sh WORK prepare
sh WORK/operate.sh WORK pause
# Verify actual HTTPS503 and wait at least65 real seconds.
sh WORK/operate.sh WORK export
```

Export creates a fresh BACKUPS/fresh-reset23-before-* private directory with the
full database.sql, SITE, DATA including empty directories, private configuration
and key copies, exact original HTTPS and cron, manifest, and
FreshReset23-private-backup.zip plus SHA256. The original schema19 exporter and its
pins are unchanged; this is a separate schema23 implementation derived from it.
No captured SQL/configuration/key is written to Git or a public directory.

Download the exact archive into a fresh private0700 directory outside Git, verify
SHA, start a fresh MariaDB10.11.19 container with network none/no ports/one anonymous
MySQL volume, then use the separate schema23 verifier:

```sh
python3 server/scripts/fresh-reset/restore-verify.py ARCHIVE --sha256 SHA --container FRESH_CONTAINER --private-root PRIVATE_ROOT
```

This actually imports all SQL and compares every row/definition, all source/data
files and empty directories, all configuration/key hashes, original HTTPS/cron and
old account/device counts, without starting PHP or workers. Upload the exact
resulting0600 restore-proof.json into WORK. Retain the archive, extracted proof and
all safety evidence. Then execute these separate state transitions:

```sh
sh WORK/operate.sh WORK stage HOST_ARCHIVE SHA
sh WORK/operate.sh WORK apply HOST_ARCHIVE SHA
sh WORK/operate.sh WORK verify HOST_ARCHIVE SHA
sh WORK/operate.sh WORK release-http HOST_ARCHIVE SHA
sh WORK/operate.sh WORK release-workers
```

Stage requires the full live snapshot to still equal the restored backup. Apply
requires that exact staged snapshot, journals quarantine_started/files_quarantined/
database_committed/verified, and refuses replay. Files are renamed only into
WORK/quarantine-data on the same filesystem, never deleted. All unrelated DATA and
SITE/configuration bytes, core rows and retained user rows are checked again.
Release HTTP restores original .htaccess bytes **and0644 mode**. Worker release
requires the new public SID and unchanged crypto/invitation capabilities over real
verified TLS, still-empty old account/business/delivery state, then restores the
exact original six-worker cron bytes without adding jobs. New anonymous rate-limit
rows after HTTP release are permitted; new account/business rows are not.

## Additional local integration evidence

The first capture fixture is **STOP3**, never rerun a fourth time:

1. The image's copied core had no Apache .htaccess; the fixture then explicitly
   supplied synthetic original HTTPS rules.
2. A synthetic opaque-session expiration exceeded the core INT32 range; corrected
   fixture to1.
3. Capture correctly rejected224rather than225tables. Direct invocation of core
   migration functions had omitted PicoDb's independent schema_version table.

The new incoming cross-schema FK, opaque core-session and target avatar preflight
guards were individually exercised successfully during that third fixture before
capture stopped. This is not a passing complete capture fixture. Production's
separate actual read-only capture subsequently passed225tables/three accounts/
200source; the production operator holds its private evidence.

At root's explicit direction, a **distinct downstream fixture** then created the
exact source-defined schema_version metadata and supplied known synthetic pins;
it never invoked capture.php. Complete consistent private backup and actual full
isolated MariaDB10.11.19 restore passed once. Its first stage then caught a path
prefix mismatch: exporter still used the historical crypto23-preupgrade prefix,
while reset required fresh-reset23-before. Source was corrected. Only the failing
stage/apply continuation resumed from the retained exact verified SQL/files/archive
in a fresh isolated database; passing backup and independent restore were not run
again. Thirteen continuation stages passed, including real kernel lock contention,
real binary attachments/ideas quarantine, SQL reset/new SID, retained core/config/
file verification, second-apply refusal, explicit HTTP-release0644 mode and original
cron state confirmation. Root/source review also caught and corrected inherited
writePrivate's missing mode argument before that release check.

Evidence is retained outside Git at
`~/.local/share/jivie/backups/fresh-reset23-fixtures/downstream-f703fadf/`
(results.json, continuation-results.json, full archive, extracted verified restore,
quarantine and synthetic host tree). Summary logs are in
build/qa/fresh-reset-20261028. The original16+16unit assertions were not repeated.
All owned new containers and anonymous volumes were removed; no existing container,
production account, device or protected backup was touched by this helper work.
Real HTTP503/200, actual crontab installation and actual65second elapsed drain are
production requirements; fixture timestamps, cron state and final capabilities
were explicitly synthetic inputs. Full backup/restore, filesystem rename, kernel
lock conflict and release-file permissions were real local operations.
