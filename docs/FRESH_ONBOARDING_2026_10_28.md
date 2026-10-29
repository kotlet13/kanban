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

## Android password keyboard follow-up

After the completed production reset, investigated the user's report that entering
a Jivie password leaves the Android keyboard in incognito mode in other apps.
No Jivie native code changes global keyboard settings. Android's
`IME_FLAG_NO_PERSONALIZED_LEARNING` is per editor; Flutter creates a fresh editor
configuration. The reported cross-application symptom is not proven to be caused
by Jivie without a native reproduction.

A local lifecycle test did reproduce a password retaining focus after Android
backgrounding; its baseline stopped at that failed focus assertion before the
connection assertion. The corrected test explicitly confirms connection closure.
`PasswordVisibility` now releases only
its focused secret descendant on Android `hidden`, `paused`, or `detached`, and
when the wrapper becomes disabled during submission. It does **not** unfocus on
transient `inactive`: Android keyboards/autofill may emit it while typing. It does
not clear the password, automatically focus it on return, alter other fields or
apply this lifecycle behavior to iOS. Observer and owned focus node are disposed.

All seven obscured input sites are covered. The previously direct password field
in preserved-installation-file recovery now uses the same lifecycle owner and
explicitly disables suggestions, autocorrection and personalized learning. It
remains hidden; no new visibility toggle was added there.

Six distinct new widget controls passed, including the RED→PASS background case,
disabled/revealed-secret handling, an unrelated normal field, nonsecret wrapper,
iOS preservation, and the preserved-file password. Four controls initially hit
an invalid fixture lifecycle transition on cleanup; corrected fixture sequence
passed on attempt2. No old successful suite was repeated. Independent native and
Dart source review found no remaining actionable issue in this change.

Actual Samsung cross-app keyboard behavior still needs device confirmation after
installing a new build. Password privacy flags remain enabled; do not claim that
the system-wide symptom has been reproduced or definitively fixed on a device.
No phone installation or Google Play submission occurred in this task.
Evidence: `build/qa/password-ime-lifecycle-20261028/result.json`; final targeted
analysis reports0errors/0warnings and3pre-existing style infos.


## 29 October — first public33 Android setup blocked before save picker

User enrolled the first fresh account, confirmed email, then reported a generic
error on the one-file screen when pressing Save. User explicitly confirms that
the Android destination picker never appears. Do not ask to reenroll, delete the
app or reverify email. Read-only production counts: accounts1/devices1,
crypto_accounts0/directory_state0/crypto_receipts0. No server mutation during
this diagnosis. These counts prove registration, but not where the client failed.

The wizard catches errors from prepareRecoveryFile, local vault key export,
bundle creation, native save and status refresh into the same generic message;
it does not retain the actual exception there. Native save uses ACTION_CREATE_DOCUMENT;
no proven filename/size violation was found by this inspection. Root cause is
NOT yet established. ADB currently lists no connected devices. Need targeted
Android diagnostics/reproduction before a speculative product change. No tests
rerun, no phone install, no further reset or enrollment code issued.


### Same29October follow-up — open-vault export defect reproduced and fixed

Connected S25 is public1.11.1(33), app PID32513. Read-only app log capture did
not expose the swallowed wizard exception; no device action or install performed.
The new local native test holds the actual encrypted database open while calling
prepareRecoveryFile: baseline fails with LocalVaultException(vault_busy) from
LocalVaultFiles.lock. The active DB holds a shared installation lease, while
prepareRecoveryFile incorrectly demanded exclusive ownership even to read an
existing key. Earlier export tests had not kept a DB handle open.

Existing key export now uses a shared lease and verifies the journal/key/probe.
Initial key creation remains exclusive, with state reread after lease transition.
No replacement key, migration, reset, database close or protocol change. Three
new controls pass: export with live read/write DB and unchanged journal/key;
exclusive operation still blocks export; missing secure key fails without creating
replacement. Analyze:0errors/0warnings,3pre-existinginfos. No old successful suite
rerun. Evidence build/qa/public33-recovery-save-20261029/ includes baseline/fixed
logs and result. This proves the local cause/path; exact native exception has
not been captured and handset still runs33. Google Play replacement required
before the same account can continue on the device; do not reenroll or reset.
