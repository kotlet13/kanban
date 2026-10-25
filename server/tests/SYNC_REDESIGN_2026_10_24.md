# Server sync redesign verification

The new PHP tests use a disposable SQLite database and a standalone native model
fixture. They do not open retained QA databases, publish messages, call HTTP,
operate phones, or modify existing containers. Each Docker invocation used
`--rm --network none --read-only` and the existing
`familyhub-crypto-tests:local` image. The notification configuration fixture also
used an isolated `/tmp` tmpfs for the existing maintenance lease.

## Source contracts

- `account.changes` accepts `{cursor:null|string}`. It returns a version 1,
  server/account/device-bound response, authenticated opaque cursor,
  `changed`, `accountDomains`, changed `scopes` and their `domains`,
  `hasMore:false`, and `resetRequired` for the explicit null cursor.
- Capabilities advertise `accountChangeVersions:[1]` and `accountChanges:true`
  when the server-only 32-byte account-mail key and metadata schema are ready.
  The HMAC key is domain separated; SMTP is not a dependency. Key rotation,
  identity mismatch and cursor tampering produce `invalid_cursor`.
- Snapshot reads use existing durable content/finance counters and schema 22
  `documents_sequence` / `configuration_revision`. Document and notification
  mutations bump the relevant counter in their enclosing transaction.
  The probe reads no document, business record, reminder or preference payload.
- Invitation polling selects indexed, unexpired active lifecycle rows only.
  Expiry changes the active set without requiring a scheduled mutation.
  The explicit bounds are 2,048 accessible scopes, a 512 KiB cursor, and
  1,024 active invitations; overflow fails instead of truncating progress.
- Schema 23 adds signed owner policy baselines, paged immutable entries and an
  active policy pointer. It preserves existing ciphertext, signatures and keys.
  New commands are `crypto2.scope.recordPolicy.prepare`, `.stage`, `.activate`;
  reads are `.status` and `.baseline`. Stages contain at most 32 entries from
  one domain. Evidence reads filter finance using its separate ACL and apply
  both entry and byte budgets.
- Owner activation checks exact head/access, both domain sequences, complete
  current record coverage, every current proof hash and a canonical sorted
  leaf root. Existing historical content contracts 6/3 remain valid. Activated
  ordinary business writes require content 7 / finance 4 plus record policy.
  Activated current-record pulls require `supportedRecordPolicyVersion:1`;
  older callers receive `crypto_upgrade_required`. Historical reads and exact
  receipts keep their original meaning. Generic legacy sync versions stay put.
- Content admission implements owner/creator, predecessor task assignee, and
  shopping checkbox permissions. Assignment changes and foreign dependent
  cascade deletion are checked before mutation. A parent workspace owner is
  recognized only through current membership and signed parent/child binding;
  host administrator, organization leader and general manager are not owners.
  Technical record types keep an explicit list of their existing guards.
- Host admission compares signed HMAC commitments and public metadata. Honest
  receivers must additionally bind those commitments to decrypted fields and
  the stable encrypted secret. The host cannot prove ciphertext semantics.

## Recorded bounded runs

| New test | Runs and result | Distinct controls |
|---|---|---:|
| `account-changes-metadata.php` | Run 1 PASS; initial vector implementation, before document inventories were replaced with counters. Not rerun. | 19 |
| `account-changes-boundaries.php` | Run 1 fixture failure: nonexistent moderation `reason` column. Run 2: first 11 controls passed, then fixture failure: omitted native API flag. Run 3 `--dispatch-only`: final 2 passed. The first control repeated during the failed-scenario retry is counted once. | 13 |
| `account-changes-counters.php` | Run 1 PASS; real table/upload/cascade transaction seams, idempotency, no-inventory query, additive schema and invitation clock expiry. | 16 |
| `account-changes-notification-configuration.php` | Run 1 fixture failure: missing `DATA_DIR`; run 2 PASS with isolated tmpfs. | 9 |
| `crypto-record-policy-admission.php` | Run 1 found an actual canonical map ordering bug in tombstone commitment equality. Fixed to compare canonical bytes. Run 2 PASS; earlier partial controls are not counted twice. | 27 |
| `crypto-record-policy-evidence.php` | Run 1 PASS; finance evidence privacy, filtered pagination, identity/active baseline binding, byte bound and revoke. | 9 |
| `crypto-record-policy-targeted.php` | Run 1 PASS; exact record lookup and filtering hidden finance rows before pagination. This supersedes the earlier evidence assertion that allowed a hidden finance ID in the continuation cursor. | 6 |
| `crypto-record-policy-table-leases.php` | Run 1 PASS; prevalidated membership/head seam plus real lease SQL: author viewer, foreign writer denial, own release, existing preactivation gate. | 7 |
| `crypto-record-policy-companion.php` | Run 1 PASS; exact same-batch task intent association and independent task admission, without finance expansion. | 9 |
| `crypto-record-policy-task-delete.php` | Run 1 PASS; an authorized task tombstone can retain its live intent companion, while assignee deletion remains forbidden. | 3 |

These are 93 distinct newly observed controls across the evolving source, not
93 repeats of final-source integration tests. Final source-only lint checked
all 39 changed/new PHP files successfully; `git diff --check` passed.
The policy admission/coverage fixture explicitly substitutes already verified
owner authority, so its result is not a signature or HTTP proof. MariaDB,
fresh server HTTP, native Mac and full client/server behavior remain separate
validation performed by the coordinating task.

The later three suites add 22 newly observed controls. The original nine-entry
evidence suite was not rerun after the hidden-ID cursor correction; its first
assertion is superseded by the targeted privacy suite. Its source is updated
for the corrected contract. Counts describe evolving-source evidence, not a
claim that every earlier suite ran against the final source.

Client follow-ups owned with the server work:

- Personal sync activation/resume invalidates only the current device's account
  change cursor, with the coordinating repository owning the invalidation/ACK
  race guard. No data or domain cursor is deleted.
- A scoped document stream publishes actual changed table/attachment proof
  projections after the outer SQL commit. An initial test found that Drift's
  update notification also runs after rollback, so explicit transaction-scoped
  signal accumulation replaces that approach. Three new controls passed on
  run 2, after the actual rollback failure on run 1.
- The policy-successor primitive in `crypto_sync_repository.dart` remains
  **unwired**. Its three-run budget stopped after an initial fixture compile
  failure, two passing single-record controls followed by a missing finance
  notification fixture, and a targeted retry with that same fixture error.
  The fixture is corrected in source; no fourth run occurred. Whole-group
  claim/pointer rollback and idempotence are **unverified**. Existing nonempty
  scope policy activation stays deferred; original requests and receipts stay
  intact. A future matrix requires a new human-authorized continuation.

## Explicit remaining protocol limitation

Converting an inline project to a separate encrypted child after record policy
activation needs a new atomic target policy publication. Until that signed
protocol exists, the server returns
`crypto_record_policy_relocation_pending` before source mutation. Source data,
original creators, exact staged requests and receipts remain intact. Earlier
unactivated relocation keeps its existing contract. This limitation does not
grant a relocation manager authorship of other people's records.

## Target-bound blob staging follow-up

The optional signed `recordPolicyTarget` is exactly
`{type, wireId, currentRecordProofHash}` on `crypto2.blob.begin`, `.chunk`
and `.complete`. `recordPolicyBlobTargets: true` advertises support. It is
available only for a live existing ordinary content record in an activated
scope, after the unchanged current membership/head/access/archive/domain
checks. The accepted current proof must match. The real owner, immutable
creator, or accepted predecessor task assignee may stage; the shopping
checkbox exception grants no upload right. Finance and new-record viewer
creation retain their original guards. Ordinary unbound writer uploads are
unchanged.

The original signed begin authorization durably stores the target without a
schema change and is returned by `blob.get`. Each subsequent upload command
must repeat that binding and recheck the current record proof and authority.
`records.batch` binds the blob permanently to its content type and wire ID;
a later legitimate edit of that same record may retain the blob without
matching its old upload-time predecessor hash. Abort may omit the target
while preserving its existing own-upload cleanup rules. Exact already
applied command receipts retain the existing receipt-first behavior.

`crypto-record-policy-blob-target.php` ran twice in an ephemeral read-only,
network-disabled test container. Run 1 passed three partial checks and then
stopped at a fixture assertion comparing canonical-map insertion order with
PHP strict array equality. The assertion now compares canonical bytes. Run 2
passed all 25 distinct controls, including live creator viewer staging,
per-step proof/creator/assignee changes, preserved denied-upload bytes,
immutable targets, baseline creator, missing/deleted target denial, no finance
or checkbox expansion, final record binding, and the old unbound writer path.
No third run, live server staging, HTTP, native app, signature verification or
recipient-decryption result is claimed by this fixture. Membership/head and
command signature verification are explicitly prevalidated seams. Client
protocol and receiver controls are owned by the collaborating client task.

## Protection catalog compatibility correction

Native QA exposed `protection_catalog_shape`: the policy fields originally
added inside `catalogScope` violated the protection client's exact fourteen
field contract. Those three additions are removed. `catalog` now returns
`recordPolicyVersions` as an outer JSON object mapping only that page's
returned scope IDs to integers 0 or 1, including `{}` for an empty page. This
is discovery metadata; the original descriptor bytes, field count and
protection manifest hash remain unchanged by policy activation. New clients
validate and attach the outer hints only to their local discovery model.

New `crypto-record-policy-catalog-compat.php` run 1 passed nine controls using
the actual catalog/descriptor/protection hash methods with disposable SQLite:
exact old shape, independent original hash calculation, unchanged descriptors
and hash after policy activation, page and ACL boundaries, and empty-object
encoding. No earlier PASS suite was repeated. This is not a signed protection
completion, native wizard or HTTP result; those remain root-owned QA work.

## Invitation policy display hint

Invitation preview/open `scope.recordPolicyVersion` is an optional host display
hint, integer 0 or 1. It selects explanatory recipient copy only. The existing
scope display values, signed invitation roles/consent/proofs, catalog descriptor
shape and protection manifest remain unchanged. New isolated helper controls in
`crypto-record-policy-invitation-display.php` passed all three checks on run 1:
inactive/active hint, unchanged old values and absence of authority assignment
or policy mutation. This fixture does not verify invitation consent, signatures
or HTTP behavior.

## Explicit restore admission (unreleased policy contract)

The current unreleased policy 1/content 7/finance 4 contract adds operation
`restore` and exact signed metadata
`recordRestore: {version: 1, tombstoneProofHash, previousLiveProofHash}`.
`recordPolicyRestores: true` gates client issuance. Published content 6 and
finance 3 history remains unchanged. A current tombstone cannot receive a live
ordinary edit or shopping checkbox successor. A restore requires the current
exact tombstone CAS and an original creator or real owner; task assignment
never grants restore authority. Creator substitution is forbidden.

Server admission walks at most 64 accepted historical proofs backwards,
checking each hash, scope/domain/ID/type and revision, and requires the supplied
live hash to be the nearest nondeleted ancestor. Missing/corrupt/long history
returns an explicit pending error without record effects. Receivers must also
verify decrypted history and preserve its per-record secret (or the exact
current tombstone baseline sidecar for a legacy record activated after
removal); the server makes no plaintext/key verification claim.

`crypto-record-policy-restore.php` run 1 passed 18 new isolated controls over
the actual codec/admission/history SQL. These cover explicit creator/owner
restore, denied implicit/checkbox resurrection, creator preservation, exact
and nearest predecessor bindings, invalid intent contexts, old published
history shape, bounded pending and unchanged historical rows. The fixture
seeds accepted history as a prevalidated seam; it is not an HTTP, command
signature, receipt, encrypted receiver or native integration result. Ordinary
membership/finance/reference/lifecycle/table lease/blob guards remain in their
normal paths. Client issuance/receiver work and preserved-draft unsupported
large-upload/finance-pair cases are coordinated separately. The central
policy-upgrade successor primitive remains unwired and its STOP3 untouched.

A separate new `crypto-record-policy-restore-boundaries.php` run 1 passed six
additional controls without reexecuting the first suite: exact activated
legacy tombstone baseline creator, stale baseline denial, technical-type
intent denial, the unchanged real finance SQL write guard, the unchanged
real table lease guard and preserved history/leases. Shared setup moved to
`crypto-record-policy-restore-fixture.php`. Table restoration currently remains
pending because a deleted table cannot acquire its normal live-table lease;
there is no lease bypass. These are two bounded restore runs and 24 newly
observed controls, not a native or final full-system proof.

## Finance viewer parity audit — source only, exception cancelled

The two UI controls using a scope viewer together with `financeRole: write`
exercise a synthetic model combination. They do **not** demonstrate a real
supported finance-viewer write feature. The current canonical server policy
maps policy-3 viewers to finance read and downgrades explicit viewer write to
read (`NativeFinanceAccess::policyForScope`). New viewer write grants are also
rejected (`NativeCryptoFinancePolicyV2::validateAction`), and signed membership
finance roles must match that canonical policy (`membershipParity`).

After this audit, root explicitly cancelled the proposed finance exception in
`NativeCryptoStorageV2`/`NativeCryptoScopeV2`. No finance grant, canonical SQL
policy or Storage/Scope authority gate was changed. No tests, runtime, Docker
or UI actions were performed for this audit. Existing content-policy viewer
exceptions and the independent finance write boundary retain their meaning.
