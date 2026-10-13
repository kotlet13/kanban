# One-time review test1 upgrade: 0.11.2/schema15 → 0.13.0/schema17

Specific guarded CLI helpers for `/home/tripar13/jivie-test.triparna.si`,
database `tripar13_jivietest`, serverId
`95c11fe0-916c-48be-a3f6-999732846266`. These are separate from completed test2
helpers. Existing test1 root configuration, SMTP/FCM, accounts and cron remain.
No credentials are embedded. Android artifacts are outside this operation.

Inputs belong in the fresh private mode0700 directory
`/home/tripar13/private/jivie-test/review-upgrade-0.13.0-20261013` (mode0600 files).
Old83/new96 source manifests and the immutable 0.13 ZIP are pinned. No application
or delivery worker is bootstrapped by the backup or upgrade helpers.

`operate.sh prepare` captures the exact original crontab, checks config/identity,
GD PNG/JPEG, schema15 and old/new source hashes, and prepares a pause candidate
for exactly five test1 workers. Other cron lines remain byte-identical.
`operate.sh pause` applies that candidate and verifies public TLS HTTP503.
Wait at least65 actual seconds. Close editing clients before capturing.

`operate.sh export` requires a fresh process drain proof, paused cron, unchanged
configuration/maintenance and read locks on all InnoDB tables. It exports every
CREATE definition and row, complete DATA tree and empty directories, root
configuration, original HTTPS rules and original cron. Two database and file
inventories must match. The archive remains outside public directories; older
backups are preserved rather than recursively duplicated.

Download the reported archive into a new private mode0700 directory outside Git,
set mode0600, and compare its reported SHA. Restore with `restore-verify.py` into
a **fresh MariaDB10.11.19 container**, network=none, no ports or host bind mounts,
only the image's anonymous MySQL volume. Every row/CREATE/file/config/HTTPS/cron
hash and account/session count must match. No application or worker is started.
Return that exact fresh `restore-proof.json` to the private hosted work directory.

Then use `operate.sh stage ARCHIVE SHA`, `operate.sh apply ARCHIVE SHA`,
`operate.sh verify ARCHIVE SHA` and `operate.sh release SHA`. The helper refuses
a stale/wrong backup, mismatched proof, changed live rows/data/code or rerun.
Only migrations16 and17 run: six new empty tables, one FamilyHub metadata row
15→17, exact96-file code swap. All historical rows/definitions/identities,
configuration, DATA and core stay identical; original plugin copies remain private.
Release verifies preservation, restores the exact original cron, then atomically
restores original HTTPS rules. Preserve paused state and all originals if any
guard fails; never blindly retry DDL or import old SQL onto a live database.

`fixture-test.py` uses nonempty synthetic Kanboard/MariaDB data and a separate
PHP fixture. Only fixture config/HTTPS pins and its synthetic pause clock differ;
the actual hosted65-second rule remains. It exercises export, genuine isolated
restore, both migrations, historical preservation, code swap/release and five
negative guards. Its PHP runner may bind synthetic files; the restore target
always forbids host binds/network/ports. Fixture artifacts are private outside Git.

The archived field `config.php` is a copy of the existing test1 root config,
not a newly introduced private config. `crontab.original` contains the complete
pre-upgrade cron. The restored proof calls these `configHttpsAndCronHashesMatch`.
Fresh current-schema backups are required for later work; these one-time schema15
helpers must not be reused as schema17 backup tools.
