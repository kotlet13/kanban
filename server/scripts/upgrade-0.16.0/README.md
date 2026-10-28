# Private FamilyHub 0.15.0/schema19 → 0.16.0/schema23 deployment

This is a new procedure; the old upgrade helpers are unchanged. The deployment
ZIP is a private complete plugin snapshot, not a published source release. It
contains 191 current plugin files, the unchanged public notice and the same eight
explicit public contract paths (200 files). It pins the exact previously deployed
107-file 0.15.0 baseline. It never runs the application bootstrap during backup or
migration and never invokes delivery workers.

The schema step runs only existing reviewed migrations20–23. It adds127 empty
crypto tables; two historical tables receive a zero-valued counter column and the
invitations table receives three indexes. Every historical column/value, identity,
account/device/password/session row and other plugin schema row must stay exact.
Historical SHOW CREATE text is exact after removing only the five independently
verified added definition lines. New table definitions match the independent
MariaDB10.11.19 oracle. This installs encrypted transport support; it does not
perform an authenticated business-data migration or recovery for any account.

The only configuration change is one exact, hash-pinned true
`FAMILYHUB_ENABLE_CRYPTO_PREVIEW` definition inserted immediately after the first
`<?php` in root config.php. All original configuration bytes, keys, HTTPS, cron,
complete SITE source/vendor tree and DATA files/directories are retained in the
full private backup. The original configuration is also retained separately during
apply. A fresh actual isolated MariaDB restore proof is mandatory before stage.

## Gates and sequence

Run capture.php and crypto-runtime.php from the **same fresh private subdirectory**,
not directly in the private configuration root. Capture pins all existing root
configuration files and rejects any existing crypto gate. The shared runtime
checks sodium signing/XChaCha20 roundtrips, mbstring, PDO MySQL, OpenSSL and curl;
ZipArchive/tokenizer/GD are checked separately. Verify the actual web SAPI runtime
and private-data writability before maintenance; CLI availability alone is not web
runtime evidence. The production web runtime was independently checked by root.

`seal.py CAPTURE OUTPUT` creates a new private0700 folder outside the repository,
with exact deployment pins and0600 regular files. It accepts only a fresh capture
of the fixed production/test1 identities and baseline schema19/107 source hashes.
Transfer every sealed file, verify all hashes and use the exact emitted hostWork.

```sh
sh WORK/operate.sh WORK prepare
sh WORK/operate.sh WORK pause
# Wait at least65 actual seconds; HTTPS503 and paused cron must remain verified.
sh WORK/operate.sh WORK export
```

Prepare/export fail if views, triggers, routines or events exist in this database:
those need a separately reviewed full dump. The export read-locks every InnoDB
base table, dumps every CREATE and binary-preserved row, copies full SITE and
DATA including empty directories and every pinned configuration/key, then requires
matching before/after inventories. No table mutation occurs during export.

Download the exact reported Crypto23-private-backup.zip into a fresh private
folder outside Git, verify SHA and restore only into a fresh `mariadb:10.11.19`
container with network none, no ports/binds and one anonymous MySQL volume:

```sh
python3 server/scripts/upgrade-0.16.0/restore-verify.py ARCHIVE --sha256 SHA --container FRESH_CONTAINER --private-root PRIVATE_ROOT
```

Every row, definition, source file, DATA file/empty directory, config/key, HTTPS
and original cron is compared. No PHP/application/worker runs during this restore.
Copy its0600 restore-proof.json into the same sealed WORK without modifying it.

```sh
sh WORK/operate.sh WORK stage ARCHIVE_ON_HOST SHA
sh WORK/operate.sh WORK apply ARCHIVE_ON_HOST SHA
sh WORK/operate.sh WORK verify ARCHIVE_ON_HOST SHA
sh WORK/operate.sh WORK release-http SHA
sh WORK/operate.sh WORK release-workers SHA
```

Apply checks the actual restored baseline again, applies only the four schema
versions, verifies preservation, updates only FamilyHub schema metadata19→23,
then swaps the exact plugin and exact crypto config candidate while HTTP503 holds.
Any partial-DDL failure leaves maintenance active and requires inspection; this is
not a transactional DDL rollback promise. Retain all state and backups.

HTTP release restores the exact original HTTPS rules while delivery cron remains
paused. Worker release first requires live anonymous HTTPS200 capabilities with
same server identity, crypto transports1/2, cutover3, invitation4/preauthorization,
record policies, decline/search and account changes. It restores the exact original
cron bytes as a prefix and adds exactly one new bounded security-mail cron:

```text
* * * * * /usr/bin/timeout 50s /opt/alt/php84/usr/bin/php SITE/plugins/FamilyHub/cli/security-mail.php 1 >/dev/null 2>&1
```

`/usr/bin/timeout` must exist before prepare. The positional1 is intentional:
security-mail.php does not parse account-mail.php's `--limit` argument. The original
cron remains privately retained byte-for-byte. No new workers are manually run.
The old five worker paths and every unrelated cron line stay unchanged.

`abort.sh WORK` is conservative pre-stage/pre-DDL abort only. It refuses any
staging/migration/release state, restores original HTTPS and then the original cron
only after live TLS verification. Never use an old plugin/APK as a rollback after
accounts have started encrypted work.

## Local evidence, 28 October2026

Independent source review and independent MariaDB10.11.19 schema oracle passed.
The schema oracle added127 new empty tables to98 baseline tables and identified
exactly three historical DDL changes. Its private derivation is retained at
`~/.local/share/jivie/backups/crypto23-schema-oracle-20261028`.

The **synthetic capture fixture remains STOP3** and was not run a fourth time:

1. It mistakenly selected retained preupgrade schema18 plugin source; identity
   preflight rejected it before export.
2. Its original disposable PHP image lacked tokenizer; preflight rejected it.
3. Its capture helper was wrongly placed among root configuration files and was
   correctly rejected for containing the crypto-gate literal.

These were fixture setup errors. Actual production capture succeeded independently
from the correct private subdirectory on PHP8.4.27/MariaDB10.11.19. Do not describe
fixture-test.py as passing or rerun that stopped capture case without new direction.
One disposable-image build also caught a tokenizer/core PHP ABI mismatch; the
second build updated only that isolated fixture image's PHP stack to8.4.27 and
passed all runtime/extension preflight checks. No existing container/image changed.

A **distinct downstream fixture with explicitly known synthetic deployment pins**
then verified full consistent backup, actual isolated restore and stage once.
Its first apply stopped on SQL-collation versus PHP table-name ordering. Sorting
both complete name sets fixed that comparison without weakening any table/row
checks. Only the failing apply continuation was retried from the retained exact
synthetic backup SQL in a new isolated database; the passing export and actual
restore tests were not repeated. Apply attempt2, verify, intentional historical-row
change rejection, HTTP-release and cron-confirmation state transitions passed.

Evidence: `~/.local/share/jivie/backups/crypto23-fixtures/downstream-2e3d713a/`
`results.json` and `apply-retry-results.json`. The downstream synthetic baseline
has99 tables (one deliberate binary/NULL preservation probe), then226 tables.
It proves old-row/binary/NULL preservation and zero new counters/tables. Real
HTTPS/crontab installation, server filesystem UID parity and user/device runtime
were not exercised by this fixture. Its drain timestamp and public-capability
proof are explicitly synthetic state inputs; production must use real65 seconds,
actual HTTPS503/200, actual web runtime and live capability verification.

New database-object count guards received narrow source review after this passing
fixture; export-body tests were not repeated. Production prepare must run these
new information_schema queries against the actual host. Syntax checks on changed
PHP, Python compilation, shell syntax and diff whitespace checks passed.

All owned synthetic containers and anonymous volumes were removed after their
runs; private source/SQL/backups/proofs/logs remain. Other Docker containers,
production, devices and native tests were untouched by this helper task.
