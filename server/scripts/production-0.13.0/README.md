# Production installation evidence helpers — 13 October 2026

Fixed target: `jivie.triparna.si`, database `tripar13_jivieprod`. These are
installation-time helpers, not a recurring backup or ongoing health-check service.
See [the actual result](../../../docs/server/PRODUCTION_SETUP.md).

- `manifest.json`: 96 public FamilyHub 0.13.0 source files, pinned by
  `../deploy-cpanel-production.php`; no credentials or private data.
- `backup.php`: consistent export of the **fresh, pre-FamilyHub** database and
  original configuration/data/cron under maintenance after a real 65-second drain.
  Requires private operator artifacts and fixed original configuration hash.
  Uses table read locks, fresh exclusive output, and duplicate snapshots.
  It will not back up the currently migrated deployment. Do not weaken its guards.
- `restore-verify.py`: verifies the extracted private backup and actual restored
  database in an isolated MariaDB container; checks rows, definitions and files.
  It does not turn a ZIP checksum into a claim of successful restoration.
- `verify.php`: read-only comparison immediately after schema17 migration and
  **before accounts or workers change the initial state**. Only two system seed
  rows are allowed; all user tables must be empty. This is not an ongoing
  production checker and must never motivate deleting real data to make it pass.

Actual configuration, SQL, ZIP backup and operator proof remain private outside
Git and the public document roots. The hosted backup helper had unused legacy
constants removed from this source after the successful run; its executed export
and independently restored results are preserved in the private evidence.
The final deployment helper on the host is `deploy-production-0.13.0-r2.php`.
