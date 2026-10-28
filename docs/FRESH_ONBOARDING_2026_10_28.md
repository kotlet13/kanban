# Fresh installation: one recovery file

User explicitly chose a new start for the three production users on 28 October
2026. Implement and test the simplified flow locally first, then reset only Jivie
production account/business data. This replaces the preservation requirement for
those live records, not the requirement to preserve hosting settings and private
safety backups. No phone, store release or native installation was authorized by
this implementation task.

## Implemented behavior

- A demonstrably empty native installation creates an encrypted SQLite vault
  automatically, with its random key in the platform secure store. Offline-only
  use needs no account or recovery-file wizard.
- On the first new connected account, the user saves one file combining the
  existing installation-key and account-key formats. A confirmed native file save
  advances account initialization and fresh protection completion automatically.
- Cancelled saves, share-sheet returns and download-start acknowledgements do not
  count as a durable save. Web retains its account-file export/reimport flow.
- Saved preparation is bound to the exact account root and local device keys.
  Interrupted work resumes the existing signed request and preserves receipts.
- Existing/populated/locked installations keep the existing migration/recovery
  safeguards. This change does not automatically discard their data or restart
  their cryptographic identity.
- Previously issued account and installation files remain readable. The combined
  file contains keys, **not a backup of business records**. Another account needs
  its own recovery material. Never commit recovery files or credentials.

The application still enforces email/account requirements, explicit invitation
acceptance and existing authorization/signature checks. No plaintext fallback,
server-held recovery root, weakened permission check or new cryptographic suite
was introduced.

## Review and local verification

GPT-6.1 Sol/high agents implemented vault and account slices, prepared reset
primitives, and reviewed the other slices; root reviewed integration and ran real
signed HTTP tests against a separate loopback-only synthetic server.

- Vault: 14 distinct new controls passed, including actual encrypted SQLite
  write/reopen, interruption before/after key retention, old-source protection,
  combined-file recovery, codec ambiguity guards and the bootstrap widget.
- Account: 14 distinct new controls passed: SQL/codec 10 and widget 4, including
  save/cancel/download behavior, immutable initialization resumption, device/root
  binding and browser fallback.
- Real signed HTTP: two fresh accounts initialized and completed protection;
  owner created encrypted content and invited the second account; recipient
  accepted and decrypted it; a blank third client recovered using the same owner
  file and decrypted the original content. Three phase tests passed.

These tests use actual local SQLite, PHP/Sodium transport and signed commands.
The HTTP client's secure store is a private synthetic file store, not an Android
Keystore/iOS Keychain or a native file-picker run. No native release/upgrade or
physical-device PASS is claimed.

### Failed attempts and corrections

- HTTP setup attempt 1: fixture image lacked Sodium. Replaced with the existing
  crypto-enabled image. Its initial disposable tmpfs seed was lost when stopped;
  no successful setup or real user data existed there.
- HTTP setup attempt 2 found a real non-reentrant directory-lock deadlock when
  finishing the saved marker. Fixed by checking local ready state inside the
  lock; full verification remains in the completion operation. Hung synthetic
  state was retained privately. Attempt 3 passed with a fresh pair because the
  reviewed saved-marker format changed during development.
- Sharing attempt 1 reached successful guest decryption but its oracle wrongly
  compared internal `_recordPolicy` metadata as user content. Corrected only that
  comparison; attempt 2 resumed the same scenario, without repeating creation,
  publication or invitation acceptance. Recovery passed on attempt 1.
- Agent fixture compilation/scroll/canonical-codec attempts are recorded in their
  private result ledgers. No fourth attempt or broad historical suite was run.

Evidence (ignored, private): `build/qa/fresh-onboarding-20261028/`, including
`vault/result.json`, `account/result.json`, HTTP phase logs and synthetic clients.
Preserve these files without publishing their credentials or recovery material.

## Production reset

Local reset primitives and maintenance plan are documented separately in
`server/scripts/fresh-reset/README.md`. Fresh full backup and independent isolated
restore verification are required before live deletion. Preserve the admin,
source/schema, configuration, SMTP/FCM secrets, TLS, cron definitions, unrelated
sites/databases and earlier safety backups. Rotate the Jivie server incarnation
so old tokens/commands/recovery identities cannot become fresh authorization.

### Production outcome

Reset completed on 28 October 2026. Maintenance began at22:02:06UTC; HTTPS and
all six original cron definitions were restored by22:06:25UTC (259seconds).

- Current schema23 and all200 hosted plugin files were independently matched to
  reviewed source. Production read-only capture/sealing passed.
- Fresh full backup:6,156,735bytes,225tables/1,056rows,3private files/4directories.
  SHA256 `5c02286407e458dcddeec79e81cccca69abf801aa9760b0993f479f26999d6b9`.
- Actual isolated MariaDB10.11.19 restore passed: every row/DDL/source/data/config/
  key/cron hash matched. Networknone, noports or hostbinds; no application worker
  ran in the restored copy. The owned restore container and anonymous volume were
  removed after verification; backup and proof remain private.
- All three pinned nonadmin users and old FamilyHub account/business/device/
  cryptographic/migration/delivery state were removed transactionally. All177
  FamilyHub tables were empty except the new instance and zero lock seeds before
  release. There were no attachment/idea files to quarantine in production.
- New server incarnation: `14fb6cbc-2670-49fe-a43f-26125fb5aba2`. Old incarnation
  `ad56910f-ca2e-41ee-af0d-3f18081497cf` no longer authorizes clients.
- Retained admin/core data, schema, source, private files, configuration, SMTP/FCM
  keys, original HTTPS rules/mode and original cron compare exact. Old delivery
  queues empty. Actual TLS capability response200 confirmed newSID and unchanged
  crypto1/2, cutover3, invitation4/decline/search and account changes.
- No new user enrollment, invitation, business record or phone action followed
  reset. First new account will need a newly issued administrator enrollment code
  through the existing flow; later users receive new invitations.

Private host operation:
`/home/tripar13/private/jivie-production/fresh-reset23-20261028-220129`.
Private local evidence/backup:
`/Users/anzenovsak/JivieProductionSafety/20261028-fresh-reset`.
Outcome archive SHA256:
`3252803b934a60361b2eb8e21cd60cd14d7da43a82cefc7ea36215f943bee7f6`.

Reset tooling's initial synthetic capture fixture remains STOP3 (fixture setup
defects); do not call it PASS. Actual production capture passed independently.
Distinct downstream tests exercised full backup/restore, competing kernel lock,
quarantine, reset, preserved core, repeat-apply refusal and release permissions.
See its README for precise attempt ledger. No successful backup/restore was rerun.

Application implementation committed/pushed as7e1133d. The simplified app has not
been published or installed. Users must wait for the new release before fresh
setup. Do not tell users that the currently published build has this new flow.

## Next required investigation before Google Play release

User reports that after entering a password in Jivie, the Android keyboard stays
in incognito mode even in other applications. Cause is unverified; do not treat
this as a proven global Android flag mutation. After this fresh-flow/reset work,
inspect password fields, focus/input-connection disposal, keyboard IME flags and
any secure-window handling, including navigation/background transitions. Fix any
confirmed application defect and test the relevant lifecycle locally before the
next store release. Native cross-application keyboard behavior still needs an
Android device confirmation. User explicitly requested this ordering on 28 October.
