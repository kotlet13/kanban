# Local full-sync integration checks — 21 October 2026

Status: local scenarios concluded. H1/H2/H3/H5/H6 passed; H4 stopped after
three attempts and H7 stopped after two with unresolved client behavior.
This is a separate local HTTP integration run, not a phone or production
readiness result. Previously successful tests and phone scenarios were not
rerun. Do not start phone regression yet expecting these two gaps to be fixed.

## Isolation and evidence

The lab uses only `jivie-fullsync-lab-20261021` on `127.0.0.1:59777` with its
three explicitly owned volumes. Two new synthetic accounts have independent
client SQLite databases, secure stores, sessions and crypto identities. The
current application repository, crypto verifiers, durable queues and ordinary
`syncNow` implementation communicate with the real local server over HTTP.
No UI automation, native package build, phone operation or production change
is part of this run. Existing QA servers and client data are not reused.

Private fixtures, keys, signed bodies, databases and raw logs are under
`/tmp/jivie-fullsync-lab-20261021` with restricted permissions. Public metadata
is under `build/qa/local-diagnostics/full-sync-lab-20261021/`. Do not publish
the private ledger or copy it into this document.

The phase launcher records each attempt before compilation starts, rejects
concurrent launches, checks the reviewed source digest, skips completed phases
and limits every problematic phase to three launches. A failed dependent phase
does not block unrelated scenarios. Failed state is retained; no counter reset
or replacement account is used to conceal a failure.

## Execution boundaries

The test transport can interrupt a real request either before transmission or
after receiving the server's actual applied response. It does not manufacture
server receipts or alter signed records. Restart checks dispose the repository,
transport and database and recreate them from the same durable files.

Test-only request pacing respects the existing server quotas. Reported phase
duration includes pacing and is not an application speed benchmark. A pacing
delay that crosses a real authority freshness boundary must be identified as
such rather than automatically blamed on the application.

Initial ordinary sync may pull a newer manifest before the stale-claim helper
is reached. Successful full-sync convergence therefore does not by itself
prove execution of that exact helper branch. Earlier targeted synthetic tests
cover that branch separately; they are not executed again here.

## Results

The authoritative launch outcomes are in `phase-launch-summary.json`. Final
scenario outcomes and remaining limitations are recorded below. Each failed
launch remains in the ledger; a successful substep is not a full scenario PASS.

| Phase | First outcome | Meaning |
| --- | --- | --- |
| H1 full sync after sharing changes the scope head | PASS | Verified current choice manifest advances from revision 1 to 2; both clients sync and the baseline finance data and signed requests remain intact. |
| H2 response lost after actual applied ACK | PASS | Server has exactly one applied receipt and manifest revision 3; the client's exact signed request remains pending with its original revision claims. |
| H2 fresh-client restart and receipt recovery | FAIL on attempt 1; PASS on attempt 2 after the fix | The same pending request resolves through one real receipt lookup, with zero resend and unchanged signed bytes, hash and revision claims. |
| H3 next-cycle owner sync and member catch-up | PASS on final attempt 3 after diagnosis and fix | The member installs the actual received revision 3 after verifying the missing inner directory proof; no new choice batch is created. |
| H5 interruption before sending | PASS, attempt 1 | One exact signed request and its claims are persisted, then interrupted before the HTTP delegate sends the batch. |
| H5 restart and actual delivery | PASS, attempt 1 | One genuine unknown receipt, one exact original batch, one applied ACK; the member catches up and both retain the finance baseline. |
| H6 competing account-choice publications | PASS, final attempt 3 | Two signed requests from the same base reach the real server; one succeeds and one receives a revision conflict, then both ordinary syncs converge. |
| H4 competing edits of one task | FAIL / STOP after attempt 3 | Real server accepts one and rejects the other; the losing draft survives, but remains pending instead of becoming a surfaced conflict. No fourth attempt. |
| H7 revocation with already-signed pending work | Partial / FAIL; stopped after attempt 2 | Signed removal and fresh server 403 verified; ordinary recovery sends zero batches and retains the request, but cached access/finance selector is not withdrawn. No blind third attempt. |

The restart failure is an application recovery gap, not a duplicate financial
entry: initial pull materializes the already-current manifest, then the
account-choice `ensure` fast path returns without resolving its older pending
request. The first failed run made 152 HTTP calls, all returning 200, with no
new batch for the lost request. Business outboxes and conflicts were empty.
The failed state was retained for the narrow fix and attempt 2; the successful
response-loss phase was not repeated.

The fix reconciles only older pending ordinary account-choice materializations
after a successful verified manifest read. Exact request, business journal and
record claims must agree. Receipt-only delivery reuses the existing receipt
identity, authorization and batch-ACK validation. It cannot resend, run a
delivery preflight or retry blocked work. Unknown or access-denied receipts
leave pending work intact; captured manifests are excluded.

One new targeted queue test passed on its first launch. It covers unknown and
denied outcomes, substituted request hash, malformed ACK, a valid selected ACK,
immutable claims and signed bytes, and a caller attempting to widen the
selection after invocation. Existing successful queue tests were not rerun.

Independent inspection of H2 attempt 2 confirmed exactly one receipt lookup
for the lost request, no resend, zero pending/blocked crypto work, and the
unchanged 33.33 EUR balance / 12.34 EUR expense. The initial failed attempt and
its metrics remain separately recorded.

H3's next-cycle check also catches up the member after the owner's H2 scope
rotation. Its first attempt passed the owner's sync, then failed on the member.
The member's attempted choice publication received a real revision conflict.
Its received revision 3 remained unprojected while its authenticated local
physical base was still revision 2. The advancement guard correctly refused
to treat revision 2 as a newer base. This is distinct from the resolved H2
pending-receipt gap. Diagnosis must preserve the revision guard and capture
the original inner projection error; the generic stored authority-pending
message alone does not identify its cause.

H3 attempt 2 reproduced the original inner failure on the actual member's
retained signed revision 3 and then the same ordinary member sync:
`directoryAt` → `_verifyManager` → `_verify` → `projectRecord`, with
`directory_proof_pending`, `online=false` and the requested prefix absent.
The outer record was already authenticated. The inner offer/delegation used
the owner's directory generation 15, while the member retained generation 14.
The diagnostic used the member's own keys and unchanged signature/decryption
checks, with no SQL installation of a projection. The owner's already
successful H3 substep was skipped.

The fix enables online directory resolution during ordinary account-choice
sync dispatch. For a received record, it requires the exact current membership
head, epoch and access revision and excludes historical-only projection.
For a current-manifest read without a snapshot, it requires the offer target
head to equal the freshly verified current head; the live manager/device and
current directory checks remain enabled. Both paths exclude frozen/deleted
evidence contexts. Other dispatches retain their defaults. Anchored directory
chains and all existing signature/role/identity checks still run.

H3's final third attempt passed in 7.297 seconds on the original member state,
without prefetching its missing proof or resetting the database. The owner's
already completed substep was skipped. Both prior failures remain recorded.
Independent inspection confirmed member revision 3 verified and current, one
directory read, zero new choice batches, no pending work, and the original
rejected 409 request retained with its exact hash, signed authorization and
expected-revision-2 claim. Server manifest history remains exactly revisions
1, 2 and 3; account/entry ciphertext, history and authorization hashes still
match the initial baseline.

A separate, small SQLite-backup clone was used for the new verifier control,
with network writes denied. Its first two attempts failed because the test
counted unrelated, already-permitted directory reads. The third, final attempt
matched the exact issuer account and requested directory head: default-offline
and historical-only checks stayed pending without fetching that target; the
ordinary opt-in path fetched it over real HTTP and verified the unchanged
payload. No business projection was installed by this control, and the original
member database and secure-store hashes remained identical. Frozen/deleted
exclusions were reviewed in source; they were not separately executed here.

H5 recorded response-boundary counters durably before returning the actual
HTTP response to the application. The original request was delivered once,
with unchanged signed bytes/hash/claims, and the manifest advanced by exactly
one revision to the rotated head. The owner-completion marker precedes the
member catch-up so a later peer failure cannot repeat a completed upload.
The restart phase took 66.634 seconds including test quota pacing; this is not
a latency measurement. Both H5 phases passed on their first launch.

H6 preflight initially failed before any competing mutation. Attempt 1 used
a standalone offline helper; attempt 2 reproduced the failure through the
actual repository `refreshFinanceAccountChoices` API. The latter exposed a
real cold-session current-manifest read gap, distinct from received-record
projection. The narrow current-read opt-in described above addresses that
gap without passing a historical snapshot or relaxing live manager checks.
Both failed attempts remain recorded; no CAS intent was created in either.
The final third attempt passed in 141.635 seconds including quota pacing: the
real competing publications produced exactly one applied response and one
409 conflict, preserved their original signed requests and revision claims,
and both clients converged through ordinary sync to the same verified revision
5 and record proof hash, with no pending or blocked work. The opening balance,
expense, account/entry identities and original signed authorizations remained
unchanged. No fourth attempt was run.

H4's first launch failed before the task baseline upload and before any CAS
race. The task and its original local outbox entry were retained. The exact
failure path was `_writeRaw` → `_personal` → `_verifiedScopeDescriptor` →
`verifiedScopeDescriptor` → `currentHead` / ancestor `_verifyHead` →
`ScopeCryptoCodec.verifyProposal` member directory lookup. Payload
classification used the default offline descriptor path before reaching the
existing online write-authority check. This was a separate cold-write gap.
The fix passes the existing online option only from outgoing non-metadata
payload classification, guarded against frozen/deleted evidence contexts.
Other descriptor callers, including isolated FILE verification, keep their
offline default. Current-head, directory, signature and identity verification
remain unchanged.

H4 attempt 2 passed both initial client syncs, then failed a test-only oracle:
the creator had local optimistic revision 2 and the peer revision 1, while
both stored server revision 1 and the identical authenticated crypto record.
The final oracle compares server revision, payload and crypto proof, retaining
each actor’s own local revision for its later edit. No CAS or competing edit
had been attempted in either failed launch.

The third and final H4 launch reached the real race once: owner received 200
and member 409 on the same authenticated base. Exact original signed requests
and revision claims were preserved. The owner recorded revision 2; the member
retained its original local draft and wire-6 outbox entry as `pending`, with
no conflict row. Its ordinary push reported `crypto_business_delivery_pending`.
The expected user-visible conflict transition therefore failed. This is an
open application behavior, not demonstrated data loss. H4 stopped after
8.861 seconds on attempt 3; no further retry, new task, conflict resolution or
replacement fixture was performed. The losing work remains available for
future diagnosis. Later H4 canonical-projection and finance assertions were
not reached, so this scenario is not a partial full-sync PASS. Independent
server evidence confirms exactly one task at revision 2 with history [1, 2],
no duplicate revision group, and unchanged baseline finance records.
Source review pinpoints the gap: `_writeRaw` maps a non-applied durable crypto
outcome, including the real rejected 409, to
`crypto_business_delivery_pending`. The application outbox therefore never
reaches its existing `CollaborationApiException(conflict)` handling.

H7 retains the unresolved H4 draft. Because that pending task prevents the
ordinary full sync from reaching finance, setup uses the application's actual
scoped `refreshFinanceAccountChoices` API to stage its separate signed
financial choice. Post-revocation behavior is still checked through ordinary
sync. Its first launch reached the intended pre-send interruption and durably
saved the exact request and claims, but failed the test's expected exception
type: the transport exposed `CollaborationException/network`, rather than the
anticipated delivery-pending wrapper. No removal or direct denial probe had
started. Attempt 2 skipped the completed rotation and staging.

H7 attempt 2 verified signed parent and child heads excluding the member,
then sent the exact captured request once through a separate test transport.
The real server returned 403 `permission_revoked`; the physical choice manifest
was unchanged. A fresh ordinary member sync emitted zero record batches. Its
exact signed pending request and revision claim, and the separate H4 losing
draft, were retained. However, both cached scopes still had `revoked=false`,
the child finance selector remained, and two `scope_reconciliation=missing`
markers were recorded. The local revocation/selector-hiding assertions failed.
The test did not persist the full completion error/work snapshot, so this is
not evidence of a clean successful cycle; only invocation, completion identity
and zero mutation are asserted for that recovery call.

The source explains this outcome: crypto scope discovery returns the current
catalog and an empty `revokedScopeIds` list. A missing cached scope deliberately
becomes reconciliation work; catalog absence alone is not authenticated
revocation. Inbox `visibility_changed` triggered its existing retry and is not
evidence that scope discovery did not run: scope discovery precedes inbox and
is served through the crypto authority path. Fixing the remaining gap requires
explicit revocation/denial evidence to reach local access state while retaining
missing-server and recovery safeguards. No speculative absence-to-revocation
conversion was made. H7 stopped after 2 attempts (the third remains unused),
with no second removal, repeated denial probe or replacement fixture.

## Data integrity and final verification

Initial preparation passed on its first launch for both crypto identities,
the parent/child scopes with one finance account and one expense, and sharing
admission. The initial server snapshot contains exactly one account, one entry
and one child account-choice manifest, with no duplicate revision groups.

The client baseline is 45.67 EUR opening balance and 12.34 EUR expense, leaving
33.33 EUR. Financial identities, contents and original signed requests are
compared with this baseline throughout the relevant checks. Server opaque
row counts supplement client decryption assertions; they do not replace them.

Final bounded server inspection confirms the unchanged account/entry baseline,
one choice manifest with history 1–5, and one task with history 1–2, without
duplicate revision groups. The one H7 receipt lookup found no stored receipt;
the fresh 403 is proved by the actual HTTP call, not by a durable receipt row.
These observations are kept separate from the failed client-state assertions.

Final source digest: `a4c3ae3ee39d1509fec5f28d189727626f8fc9a8d196524c539a504f9262e5bf`.
Scoped analysis of the four changed runtime files and two test files reports
0 errors, 0 warnings and 69 existing informational findings; the new harness
has no analyzer findings. Root and independent review passed for the changes
actually implemented. No old successful suite was rerun.

The new owned Docker container is stopped. All other pre-existing container
states match the initial inventory. Owned volumes, both private clients and
the small verifier-control clone are retained. Public evidence is 777,107
bytes, private files 16,314,524 bytes, and server data 5,894,144 bytes plus a
12 KiB TLS volume. There are no new native packages or full source copies.
Across all 23 retained HTTP attempt sets, actual 429 responses total zero;
this reflects test quota pacing and is not a performance result.

## Remaining work before phone regression

1. Propagate a verified terminal task revision conflict from the crypto journal
   into the application's existing conflict handling, preserving the original
   draft and capturing the authenticated remote winner. Continue the preserved
   H4 state only under a new explicit test/fix scope; its three attempts are spent.
2. Discover explicit revoked access for omitted cached scopes and update the
   selector/read-only state without equating catalog absence with revocation.
   Retain the H7 pending work and completed server denial evidence.
3. After those local gaps are fixed and verified, check native platform behavior
   with the user. No phone build or installation was performed in this run.

## Limits

This headless run uses private test SQLite files and real application crypto
protocols. It does not retest native SQLCipher packaging, Keychain/Keystore,
file pickers, TLS on the phones, UI behavior or OS suspension/background
delivery. Those native boundaries still require the user's later phone check.
The H6 race uses the same current membership head; it is not an additional
stale-head continuation proof. The H4 task race edits unlinked titles, so it
does not cover task-derived financial transactions or manual conflict
resolution. Frozen/deleted and negative current-read exclusions were reviewed
in source, not all independently executed as new runtime controls.
An intentional transport interruption is not equivalent to a simulated power
loss in the middle of an OS disk write. Coverage is the finite scenarios in
the result table, not a claim that every possible synchronization failure has
been exhausted.
