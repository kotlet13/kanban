# Schema 23 migration discovery hotfix — 28 October 2026

## Confirmed cause and scope

Public Android 1.11.0 (32) completed account preparation after email verification,
but scope protection discovery showed a generic failure. Read-only production
inspection returned `crypto_migration_schema_unsupported` with schema 23 and zero
migration rows. The owner of `Dom` had verified email and a crypto directory.
This was independent of the earlier renamed recovery-file extension problem.

`NativeCryptoMigrationV2::schema()` did not classify five schema 21/23 crypto
tables (`invitation_publications_v5`, `invitation_reservations_v5`, and the three
`record_policy_*_v1` tables), nor `familyhub_scopes.documents_sequence` and
`familyhub_inbox_state.configuration_revision`. The closed allowlist correctly
rejected unknown schema, but its known-schema list had not evolved with the
schema migrations.

## Changes

- Classify the five existing crypto tables explicitly; do not wildcard-accept
  unknown crypto tables or unknown legacy columns.
- Include both added counters in exact typed legacy capture, preserving values.
- Extend the closed inbox observation decoder with the optional configuration
  counter. New four-column baselines retain the counter and reject rollback or
  disappearance. Existing signed three-column baselines retain their exact
  original shape. Account binding and the existing sequence checks remain.
- App UI now distinguishes failure to inspect a scope from an actual contributor
  wait. The other-owner explanation appears only in `waitingContributors`.
  This UI fix is source-only, pending a future app release; Google Play 32 was
  not replaced or reinstalled.

No DDL, credentials, grants, keys, recovery epochs, pending requests, local
vaults or business data were changed by the hotfix. No plaintext fallback.

## Targeted validation

Evidence: `build/qa/migration-schema-20261028/` (ignored local evidence).

- Original code reproduced `crypto_migration_schema_unsupported` against a fresh
  schema built by the real migrations 1–23.
- **14 synthetic SQLite assertions PASS**: schema acceptance, actual capture
  discovery of an owned household, no migration created, exact typed counters,
  new baseline roundtrip, old signed baseline compatibility, monotone advance,
  rollback/disappearance rejection, unknown-field rejection, unchanged source
  values, and unknown table/column fail-closed checks.
- **14 MariaDB 10.11.19 assertions PASS** for the same regression on the production
  database engine. This was an intentional engine-specific check, not a broad
  repetition of historical business tests. Private network-none container, no
  published ports, fresh tmpfs data, no production rows; removed after the test.
- **2 new widget tests PASS**: failed inspection does not claim another owner is
  pending and can retry without preparing; genuine contributor waiting retains
  its explanation. Targeted Dart analysis: no issues.
- PHP lint and Git diff whitespace check PASS.
- Deployment helper tested with `exec` disabled, fresh synthetic source files,
  read-only mounts and network-none Docker: exact old/new hashes PASS.

Attempt ledger: initial PHP fixture lacked the vendor-required `libs` mount;
corrected baseline then reproduced the intended old-code failure. First fixed
run accepted schema but the minimal users fixture lacked `is_active`; second
fixed run passed remaining 13 checks without repeating the accepted-schema
check. MariaDB passed first run. Initial widget filter used literal `--plain-name`
with an alternation and ran no tests; corrected `--name` ran only the two new
cases. None of these setup failures is counted as product PASS.

## Production application and verification

Two PHP files installed **2026-10-28 19:54:17 UTC (20:54:17 Europe/Ljubljana)**.
FamilyHub remains version 0.16.0 / schema 23, with this documented source hotfix.
Archive SHA256:
`8a91cfff8dd5168c83eb3860d089fde72f0936ea794304cdf22326c1ca4664e9`.

| File | Previous SHA256 | Installed SHA256 |
|---|---|---|
| NativeCryptoCaptureInboxStateV3.php | fc874e08398496d5d46044570a2b24046d277a3bc468ddde852694ab6c1b143c | 873490467fe42cd2f45762d3187f0217163465d2e2e18a5ad002f2c2b25a2463 |
| NativeCryptoMigrationV2.php | 10690fd69202296f96abc07e581735ad1b3982d6a4e5448997b3c5c07055772c | 6c40cbd5422ecc1071b847e3c53a5f95a4fc43bc83674f94c8479beb7e2fcd18 |

The updater verified old hashes, staged and parsed both new files, backed up the
old files privately, then atomically replaced the backwards-compatible baseline
reader before the migration model. Config/SMTP/FCM/cron/PHP version unchanged.
Private host evidence is under the existing upgrade work directory in
`migration-schema23-hotfix-r2/` (`result.json`, `.before` files, read-only results).
The earlier deployment attempt stopped during staging because hosting disables
PHP `exec`; **no live source changed in that attempt**. R2 used PHP's own
`token_get_all(..., TOKEN_PARSE)` and succeeded. No blanket rollback occurred.

After installation, a SQL READ ONLY transaction with the model's existing
snapshot-read mode verified:

- schema accepted; no column differences;
- actual `crypto2.migration.capture.discover` model read for `Dom` succeeded;
- capture version 3, two owned connected scopes, one pending contributor;
- zero migration rows, no existing migration started.

The initial extended read-only probe used ordinary model lock suffixes and hit
PDOException (`SELECT FOR UPDATE` under READ ONLY). The corrected private probe
used the existing snapshot registry, which suppresses locks and also rejects
`change()`. This was diagnostic setup, not a new product failure; no production
write transaction was used. SQL identity/SID was checked before inspection.
No record contents, credentials or recovery keys were emitted.

Public HTTPS capabilities returned 200, the same server identity, encrypted
transports [1,2], and cutover version 3. This is availability evidence, not a
signed HTTP end-to-end migration test. The read-only model check uses an injected
owner actor and does not claim to test authentication/signatures.

## Remaining user step

Open the same public Jivie app, return to space protection and press **Ponovi
preverjanje** once. Do not create another recovery file or reinstall. Inspect the
result before continuing the existing protection workflow. The full native
migration/cutover and recovery are **not yet confirmed**. The real contributor
count may require another account's contribution later; this hotfix does not
bypass that rule. Existing plaintext-copy retention remains 30 days only after
successful restore of a new encrypted backup, not from this installation date.
