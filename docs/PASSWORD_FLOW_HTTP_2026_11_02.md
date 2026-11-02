# Password, reauthentication and synchronization: actual local HTTP workflow

The full local workflow **reproduces the user's failure pattern** using the unchanged 1.11.15 product source and a real isolated HTTP server. A normal password change succeeds. Subsequent sign-out/login, local device approval and space protection leave six naturally created checkpoint requests blocked with `crypto_command_receipt_pending` / `scope_reauthorization_required`, matching the user's nineteen-request diagnostic structure. No production or phone changes, product repair or release were performed in this investigation.

## Initial source analysis — recorded before runtime execution

The following analysis was initially a hypothesis. The later runtime and SQL sections distinguish what was subsequently observed from what remained inferred. The exact contents of the user's nineteen requests have not been inspected, so the local reproduction is evidence of the same failure route, not a claim that every original phone request has been individually diagnosed.

### Password changes and device identity are different transitions

* `NativePasswordChangeService::change` preserves the exact current native authentication device/token and updates its credential fingerprint. Other native sessions are revoked. It does not mutate E2EE directory entries, account roots or scope keys. The client `CollaborationAccountRecovery.changeAccountPassword` verifies this preserved session contract.
* `NativePasswordResetService::confirm` revokes all native authentication sessions. The next `NativeAuthService::login` calls `issue`, which creates a new native device ID. It does not itself rotate cryptographic scope state.
* `CollaborationAccountActions._authenticate` installs that new session and calls `syncNow()` before an account protection wizard has necessarily completed. Local account-partitioned encrypted records and retained command evidence survive.
* Same-installation `AccountCryptoV2Workflow.rebindLocalDevice` authorizes the new device with the retained old approved key, creates a new device keypair and retires the approving crypto device. The account root and identity epoch remain unchanged, but the device snapshot changes. `AccountProtectionReady._rotateRecoveredOwners` therefore needs to rotate owned scopes whose roster references the prior device snapshot.
* `AccountCryptoV2Workflow.recover` is a separate FILE recovery path. It submits `crypto2.account.recoverEpoch`, changes the identity epoch and revokes the old crypto devices. It must not be substituted silently for the local rebind path in a test.

The user's chronology confirms a login with the new password, but does not conclusively identify whether the preceding action was a current-session password change or email reset. A direct password change with no subsequent login cannot cover the complete reported transition. Relevant variants are direct change while staying signed in; same-installation login followed by local rebind; and email reset followed by that login/rebind. FILE recovery is a distinct variant only where deliberately exercised.

### Candidate sequence that can create the retained work naturally

1. Create an account and populated spaces, and complete ordinary synchronization.
2. Reset the password or sign in again on the same installation, retaining its local data and keys.
3. Rebind the local crypto device, then allow ordinary synchronization before completing protection for the owned spaces.
4. A checkpoint can be prepared against the old scope head, while fresh delivery detects the changed account device snapshot and blocks it with `scope_rotation_required`.
5. Complete the ordinary owned-space protection work. Rotation advances the scope epoch/head; the same immutable old checkpoint now fails fresh delivery with `scope_reauthorization_required`.
6. Run manual synchronization. It should publish/verify a current complete checkpoint and safely account for the obsolete derived checkpoint without deleting its signed evidence or inventing an applied receipt.

This sequence must be observed through the real transport and ordinary workflow; inserting a blocked row or constructing a replacement snapshot directly would not reproduce the user's process.

### Specific candidate obstruction in supersession

`CryptoCheckpointSupersession.reconcile` (`lib/organizer/data/e2ee/crypto_checkpoint_supersession.dart`, around lines 144–153) verifies the old retained checkpoint through `SessionCryptoAccess.verifyDomainCheckpoint`. Any `CryptoAuthorityPending` from that historical check is caught and leaves the old row active.

`verifyDomainCheckpoint` (`lib/organizer/data/e2ee/session_crypto_access.dart`, around lines 4403–4429) checks whether that exact checkpoint proof was included in an account scope observation. Without such observation, a member device snapshot differing from the current trusted anchor requires a qualifying forward directory reference; otherwise it raises `history_freshness_pending`.

The directional predicate in `crypto_scope_anchor.dart` requires the referenced directory generation to be **newer** than the known anchor. After a genuine device rebind, the old scope roster generally references an **older** device snapshot. A never-delivered checkpoint also cannot normally be present as that exact proof in a previous account scope observation. Thus the old-proof verification may raise `history_freshness_pending` even after a valid current checkpoint has been obtained, and supersession may silently retain every old request.

Runtime evidence must confirm the old command's epoch/head/access revision, its author's directory, the new checkpoint's corresponding fields, the changed device snapshot, whether an exact observation exists, and the exact supersession exit. The exported `scope_reauthorization_required` proves the fresh delivery head mismatch; it does **not** by itself prove this separate supersession hypothesis.

### Why earlier focused fixtures can miss this

`test/organizer/data/e2ee/crypto_checkpoint_supersession_20261102_test.dart` constructs its old and successor scope heads using the same verified account directory and the same member device snapshots (`makeHead`, around lines 288–350). Its transport is synthetic. The tests validate signatures, SQL bookkeeping and replacement proof rules, including 19 retained checkpoints, but they do not execute an actual password reset, authentication device replacement and crypto rebind before the scope transition. Consequently the old-roster/new-anchor freshness branch above is not established by their passing results.

The prior password-change checks also did not constitute a complete real HTTP password → login → protection → ordinary-sync test. Their existing PASS results remain valid for the controls they exercised; this new workflow is additional coverage, not a rerun or a retroactive claim that those tests failed.

### Security boundary for any eventual correction

An old signed outgoing checkpoint is retained evidence of a local derived assertion. It is not current write authority. Retirement bookkeeping must remain distinct from accepting that assertion as a trusted snapshot for restoring or projecting records. A correction must preserve exact immutable signed bytes, request binding, historical signer and scope-chain validation, fresh current authority, a complete verified replacement inventory, known-record/restore-anchor coverage, receipt reconciliation and transaction guards. It must not weaken ordinary checkpoint verification, replay obsolete writes under current authority, forge an ACK, remove user intent, or discard the original blocked row. No implementation change is made by this analysis.

### Read-only inspection after the first actual post-rebind sync

The isolated real HTTP workflow subsequently reproduced the reported diagnostic shape with **six naturally created retained checkpoints**, across three scopes and two domains. `sync_after_rebind-failed-1-summary.json` records `crypto_command_receipt_pending`, receipt `unknown`, resume `guardBlocked`, and current/retained `scope_reauthorization_required`. The rows were created by ordinary synchronization after local device rebind, not inserted by a fixture.

Read-only SQL inspection after that failed sync establishes the following facts:

* All three scopes advanced from epoch 1 to epoch 2. The old rosters reference account directory generations 2, 4 and 6; the current account pin is generation 24. The old and current device snapshot hashes differ.
* All six immutable held command hashes match their stored request hashes, and none claims rows in `crypto_outbox_records`.
* Five domains have exactly one current, complete checkpoint with a corresponding applied outgoing replacement. Their reusable-checkpoint SQL guards all pass: projection caught up, no omitted known record, no uncovered restore anchor, no pending received record, and exact projected record counts.
* Four of those five replacements have identical sequence, manifest, count and history basis to the old assertion. Project finance has a later sequence (1 → 2), which the existing later-inventory rule permits. All replacement history bases remain `verifiedCheckpoint`; the possible history-basis-only mismatch is **not observed here**.
* Project content has a current checkpoint and matching inventory, but its final `crypto_scope_state.complete` is 0. It therefore has an earlier reusable-checkpoint gate than the other five. This final-state observation alone does not identify when or why that flag was cleared.
* No exact proof hash from the six held checkpoints occurs in the 20 persisted `scopeObservationIncluded` payloads. Their old directory references are older than the current pin, so they cannot satisfy the directional newer-reference predicate.

For the five complete domains, these persisted values eliminate the simple inventory/history-basis comparison gates. The subsequent isolated verifier probe below confirms `history_freshness_pending` for their old signed assertions. Project content additionally has the earlier final-state `complete=0` gate; the verifier probe does not explain that flag. Original device/user data and all production services remain untouched by this audit.

### Confirmed historical-verifier obstruction on the cloned local installation

One explicitly authorized diagnostic phase was run on a separate clone of the same failing installation. Each of the six old checkpoint proofs was passed to the actual `SessionCryptoAccess` implementation with its own fresh access instance and fresh verified-operation boundary. The probe obtained current account/scope authority, then called `verifyDomainCheckpoint(oldProof, onlineAuthorDirectory: true)`. The transport enforced a finite read-only HTTP allowlist; no queue reconciliation, signing, command delivery, supersession marker or other repair was invoked.

**All six proofs entered the actual verifier and raised `history_freshness_pending`.** The probe made 13 real read requests: seven capability reads and six `crypto2.authority.snapshot` requests. Each command's device still matched the current device, while its recorded author directory and scope head differed from the current ones. The earlier source hypothesis is therefore now a confirmed local historical-verifier failure, not merely an inference from an exported error string.

The five domains with reusable current checkpoints cannot complete the old-proof verification required by supersession; its existing `CryptoAuthorityPending` catch retains them. Project content fails this same isolated verification, but its final `complete=0` state also prevents the earlier reusable-checkpoint requirement. The probe was deliberately not a full supersession execution, so it does not claim that this exception was the first runtime exit for that sixth domain or that repairing it alone would finish all six.

The clone's held rows, SQL identity-key material and secure-store contents were byte-identical before and after the probe. Hash checks also confirmed all four original fixture files unchanged. Evidence: `build/qa/password-flow-verifier-20261102/build/qa/password-flow-http-20261102/held-checkpoint-verifier-probe.json`. This confirms the mechanism on the naturally failing local workflow; it does not inspect or individually diagnose the user's nineteen original phone requests.

## Actual local HTTP phases and results

### Observed intermediate results

Evidence is in `build/qa/password-flow-http-20261102/*-summary.json` and the preserved private SQLite fixture. The fixture uses one newly enrolled synthetic account, the actual local PHP HTTP server, production `CollaborationRepository` routing, cryptographic guards and projections. Each phase opens the same persisted installation in a fresh process. Explicit sync phases call `syncNow(manual: true)`; the UI controller's automatic scheduler, native key storage/vault and uninterrupted warm-process timing are not exercised. No retained checkpoint was manually inserted or marked blocked.

| Phase | Observed result |
| --- | --- |
| Populated baseline | **PASS:** three spaces (household, organization and child project); the task, finance account and expense have their expected values, positive server revisions and verified cryptographic record proofs. Pending and blocked records/commands are zero. |
| Change password while remaining signed in | **PASS:** exact authentication session preserved; secure-store contents and SQL device-key material unchanged. Three HTTP calls. |
| Sync after that password change | **PASS:** the baseline records/proofs remain valid and active queues remain empty. |
| Sign out, then sign in with the new password | Authentication succeeds with a new device. Its automatic post-auth sync reports `crypto_reconciliation_required`; local crypto phase is `missing`. This is not a rejected password or a successful sync. |
| Approve the new session using the retained local device | **PASS:** the ordinary `rebindLocalDevice()` path reaches local phase `ready`; no FILE recovery is performed. |
| One manual sync after rebind, before owned-space protection | **Observed unresolved state, not sync PASS:** six `crypto2.domain.checkpoint` requests become blocked naturally, each retaining `scope_rotation_required`. Three content pages and three finance pages commit, with zero newly applied records. Diagnostics include `scoped_export_manager_changed` and `crypto_payment_records_pending` / `commandAuthorityPending`. |
| Complete owned-space protection | **FAIL, first attempt:** `protection_scope_action_required`. All three saved scope actions have `canManage: true` and `scope_review_confirmation_required`; all three retained rotation reviews use `reviewedRecoveryBaseline`. The six blocked requests remain preserved. |
| Open the saved scope review with a fresh page manager | **FAIL, first attempt:** the actual retained-review path (`pendingRotationReviews` → `proposedMembers` → `previewRotation`) throws `scope_prefix_pending` before confirmation. Stack: `SessionCryptoAccess.verifiedCandidateAncestor` → `ScopeCryptoManager.previewRotation`. No review is accepted and no additional hydration helper is injected into the test. |
| Use the existing review-local-data action and explicitly confirm | **PASS, second attempt at the review issue:** `reviewRotation` → paginated `previewRotation` → `confirmRotation(acceptedCandidateHistory: true)` completes all three scopes. The synthetic user reviews available data before confirming. 268 HTTP calls; the six existing blocked commands remain. |
| Complete protection after those explicit reviews | **PASS, second attempt:** account protection completes through the unchanged production service. 73 HTTP calls. This is protection completion only, not sync completion: the six blocked commands remain. |
| Sync after the completed rebind/protection workflow | **FAIL, first attempt:** `preflight / crypto_command_receipt_pending`, remaining **6**. Every sample is `crypto2.domain.checkpoint`, receipt `unknown`, resume `guardBlocked`, current and retained reason `scope_reauthorization_required`. 272 HTTP calls. This reproduces the user's diagnostic pattern through the complete local workflow, with six naturally generated requests instead of nineteen. |

The last intermediate failure has a concrete source explanation matching these persisted results. `ScopeCryptoManager.reviewRotation()` sets its `emergency` flag whenever a current member's device snapshot differs from the source scope roster, then selects `reviewedRecoveryBaseline`. Ordinary local device rebind changes that snapshot as well. `AccountProtectionReady._rotateRecoveredOwners()` reaches this path precisely for the stale snapshot, but calls `confirmRotation(... acceptedCandidateHistory: false)`. The existing guard therefore requires explicit history review for each of the three owned scopes. This observation explains the additional user-facing review in this local process; it does not yet establish the separate checkpoint-supersession hypothesis or the complete cause of the user's 19 requests.

The retained-preview failure also matches the production page's construction: `ScopeRecoveryPage` creates a fresh `ScopeCryptoManager(SessionCryptoAccess(...))`, then `_restore()` loads a saved review and calls `previewRotation()` without populating that access object's candidate-head map. `previewRotation()` requires each saved record's membership head to be present in that map via `verifiedCandidateAncestor()`. The new local test executes those production methods and confirms this fresh-manager failure. It does **not** constitute a native-phone or rendered-widget reproduction. The persisted keys and records remain present; the exception concerns the missing verified head in the new manager's in-memory context.

The existing **review local data** button path completes without an extra hidden hydration call. Nevertheless, the final sync is unresolved after protection succeeds. Independent read-only inspection of the preserved SQLite database confirms six blocked checkpoint rows, zero blocked-record claims, zero checkpoint-supersession markers, and the same six retained request hashes as before review/rotation. Each blocked response now records `scope_reauthorization_required`; the database also contains 38 applied checkpoints. The ordinary task, finance account and finance entry remain present. Final transfer diagnostics show three committed content pages and three committed finance pages, zero newly applied records, and no pending/blocked business-record changes. Thus receiving/reading data and completing protection do not establish that all outstanding synchronization commands have finished.

**The end-to-end local workflow now reproduces the reported failure pattern, and the isolated real verifier confirms `history_freshness_pending` for all six old checkpoint proofs.** Five domains already have complete replacement snapshots but cannot pass that old-proof verification; project content also retains an earlier `complete=0` gate. The email-reset/FILE-recovery variant has deliberately not been executed, so this exact failing account, data and request queue stay available for diagnosis. Production, phones and user data have not been changed by this test.

## Execution ledger and preserved continuation

The first enrollment created the real synthetic account/session but its test phase failed during automatic sync: the initial test adapter omitted the production crypto readiness gate. That adapter was removed before account-key setup; subsequent phases use the production router and its independent workflow caches. Enrollment was not retried and no replacement account was created. Email verification used the real account-mail worker and a loopback SMTP capture. The first scope-creation attempt stopped at the ordinary content-policy consent requirement, before any scope or crypto command was created. The actual policy was fetched and accepted, then the same preallocated scope requests succeeded on attempt 2.

No historical successful tests or completed phases were rerun. The retained-review and review-local actions are two attempts at the same review issue; protection completion took two attempts, separated by the actual explicit reviews. The failing final sync ran once. The separate verifier probe ran once on copied client storage, against the same synthetic account/server. Older observation logs say test PASS when capturing an unresolved sync; the table above explicitly marks these as unresolved. Future harness runs emit `OBSERVED-UNRESOLVED`. No failure was relabeled as a successful synchronization.

The original SQLite, session, secure-store file and ledger are byte-identical before and after the verifier probe. A final read verifies the task title, account opening balance 45.67 EUR and expense 12.34 EUR are unchanged and retain positive acknowledged server revisions. Private evidence includes `final-data-preservation.json`, `reproduced-failure-preserved/`, and the isolated verifier directory. None of the synthetic credentials, keys, recovery file or raw databases is committed to Git.

The dedicated `jivie-password-flow-20261102` container was stopped normally after observation, with its database and all client evidence retained. Its loopback endpoint is `http://127.0.0.1:57901`; only this container was created or stopped. Server source hashes remain identical to the starting manifest (`70b49310f7100c3d28e720d8b7da67a6ad6253a9`), and application/backend product source remains unchanged. Targeted harness analysis reports zero issues. No build, Play submission, phone action or production action was performed.

Continue a later repair from this **same failing fixture**. The final sync phase has used one of three attempts. Do not repeat enrollment, password change, rebind, scope reviews or the successful baseline. Verification of a correction must demonstrate that the retained derived requests are safely resolved, all six domains become complete, and the existing acknowledged user records remain intact; it must also cover the fresh-page preview and same-installation rebind workflow without weakening historical-data guards.
