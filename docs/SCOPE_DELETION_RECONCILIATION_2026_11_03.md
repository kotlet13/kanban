# Encrypted scope deletion: receipt verification and metadata recovery

## Report and boundaries

After Android 1.11.16, the user confirmed that the previous synchronization problem was resolved. Deleting a test household then showed an unavailable-data message, left the household visible, and a following synchronization reported `metadata / crypto_reconciliation_required`.

The work uses the preserved synthetic account, server and client from the real HTTP password workflow. No production, phone, real user data or server source/schema is changed. Earlier successful setup, password and synchronization phases are not rerun. The UI placement and Android release are tracked separately by the parent agent.

## Reproduced sequence, before the correction

The independent HTTP workflow used the ordinary repository preview and confirmed deletion on its existing synthetic household:

1. `crypto2.scope.delete` ran once and the server committed deletion.
2. The immutable client outbox row contained an **applied** response.
3. `CryptoBusinessDeletion._verifyOwnResult` then threw `crypto_scope_deletion_event_inclusion`. The local household still had `deleted=false` and `revoked=false`, and the original approved preview/request remained stored.
4. A distinct ordinary manual synchronization reproduced the user's `metadata / crypto_reconciliation_required`, with three scopes still in the local view and no pending or blocked content changes. This performed 29 HTTP calls and never requested `crypto2.scope.deletionStatus`.

Evidence: the private preserved workflow's `delete_household-failed-1-summary.json` and `delete_household_failed_followup` artifacts, with exact stack/operation trace retained by the independent reviewer. These are local observations, not an assertion that the actual phone's private state has been inspected.

## Confirmed causes

The deletion queue delivers its exact signed command through its own transport. The enclosing business operation still had the account authority snapshot from before that delivery. The server atomically appended the account's signed deletion companion event, but the result verifier requested the account directory inside the old read boundary. Its real signed-inclusion check therefore examined the earlier prefix and rejected a successfully committed deletion.

The subsequent metadata path treated missing catalog scopes conservatively. It only requested legacy `scopes.list` access notices. Their server query joins `familyhub_scope_revocations`; encrypted deletion retains signed deletion evidence but creates no corresponding legacy revocation row. The encrypted cleanup **does** set `familyhub_scopes.deleted_at`. The existing fully verified `retainedStatus` path had no caller in metadata discovery, so omission remained unresolved instead of being recognized as a confirmed deletion.

## Correction

- After matching the exact saved result, header, companion event and command hash, invalidate the old authority lease and check companion-event inclusion in a fresh verified operation. The inclusion check is retained; an applied transport flag alone is insufficient.
- For cached scopes omitted from the encrypted catalog and unresolved by legacy notices, call the existing signed retained-deletion verifier. Only its verified result contributes `deletedScopeIds` and `revokedScopeIds`.
- The verifier still checks the scope's already anchored membership head, manager authority, signed header and leaf, leaf inclusion, exact historical author directory, signature, and account companion-event inclusion. Catalog omission, a bare server flag or a malformed witness cannot delete a local scope.
- Absent, malformed, unanchored or denied evidence leaves the cached scope pending. Authentication failures and identity replacement continue to abort rather than applying a stale result.
- Previously confirmed local `deleted=true` **and** `revoked=true` scopes skip repeated witness discovery. Revocation alone is not treated as a terminal deletion.
- Original signed requests, applied responses, draft data and deletion journals are preserved. The normal synchronization repair issues no new deletion request and requires no second user confirmation.

Product files:

- `lib/organizer/data/e2ee/crypto_business_deletion.dart`
- `lib/organizer/data/e2ee/crypto_business_router.dart`

## New focused verification

`test/organizer/data/e2ee/crypto_scope_deletion_reconciliation_20261103_test.dart` contains 13 new controls, all passing on their first functional run:

- A valid omitted encrypted household is recognized through signed deletion evidence, with protected SQL rows and journals unchanged.
- Bad header signature, wrong scope, missing anchored history, bad companion-event head, malformed response and forbidden response do not mark it deleted.
- Authentication loss propagates; session replacement prevents applying a verified result.
- A resolved legacy denial incurs no unrelated deletion lookup; an already confirmed terminal deletion incurs no repeated witness lookup.
- The exact applied deletion response succeeds only with fresh verified companion-event inclusion; a fresh prefix that still lacks that event is rejected.

These controls use real SQLite, real signed membership, deletion header/leaf signatures and account-directory reduction. The acquisition of an already anchored scope and historical directories is a test seam. The independent preserved HTTP continuation is the separate end-to-end release gate.

Evidence: `build/qa/scope-deletion-20261103/data-tests-r1.log`. No prior successful tests were rerun. An initial analyzer-only missing test import was corrected before this functional run. Final targeted analysis has zero errors and zero warnings; 15 existing style infos remain in the two older product files. New test source has no analyzer issues. Evidence: `build/qa/scope-deletion-20261103/data-analyze-r2.log`.

## Real HTTP acceptance

The original isolated server `jivie-password-flow-20261102` was restarted on loopback port 57901. Before starting it, nine client/server SQL, session, key, recovery and evidence files were copied into `before-household-deletion-20261103` and their hashes verified. The same account and installation were retained throughout; no old successful setup, password, rebind or synchronization phase was repeated.

| New phase | Result | Observed behavior |
| --- | --- | --- |
| `delete_household_preview` | PASS R1, 4 HTTP calls | Actual repository preview of the existing synthetic household was eligible; no confirmation was sent. |
| `delete_household` | FAIL R1, 9 HTTP calls | Exactly one deletion committed on the server. Its immutable applied response was preserved, but stale companion-event verification threw before local finalization. |
| `delete_household_failed_followup` | Observed unresolved R1, 29 HTTP calls | Ordinary manual synchronization reproduced `metadata / crypto_reconciliation_required`; no deletion-witness lookup occurred. This observation is not a successful synchronization. |
| `sync_after_delete` | PASS R1, 28 HTTP calls | Ordinary manual synchronization of that same failure fetched one signed deletion witness and issued **zero** deletion commands or new confirmations. The deleted household disappeared from active scopes and the current error cleared. |
| `fresh_household_delete` | PASS R3, 285 HTTP calls, approximately 7 seconds | The same account created one additional disposable household and a small task, synchronized the task, selected that household, previewed deletion, and sent exactly one deletion command. Its automatic follow-up finished without error. |

The fresh flow made one user-level preview call plus the existing required preview revalidation inside the confirmed deletion. The two preview HTTP requests are not two user confirmations. Its creation, key setup, task synchronization and deletion are included in the 285-call count; that count is not the cost of the deletion alone.

Fresh-flow attempt history is preserved: R1 failed before loading the test because Flutter could not copy its native-assets manifest; no harness or HTTP action ran. R2 failed in the new test's inferred `Map<String, String>` before any scope/task creation or deletion; its failure snapshot made one capabilities read. The fixture map was explicitly typed, and R3 was the first attempt reaching the actual create/delete sequence. The startup failure counts toward the three-attempt ceiling. No fourth attempt or repetition of a passing phase occurred.

The acceptance checks prove:

- The existing committed deletion is repaired by synchronization alone; the original preview, signed deletion request and applied response are not regenerated.
- The old and fresh deleted households are absent from the active scope list. The original organization and its child project remain active, with their business payloads, server revisions and stored remote rows unchanged.
- Account identity key material, current authentication session and the saved recovery file remain unchanged. Verified directory trust anchors are allowed to advance when observing the signed deletion event; that is not a key replacement.
- The six original held checkpoint rows and the first applied deletion request retain their exact signed bodies, request hashes, states and responses.
- Current sync diagnostics contain no failures and the active command/content queues are empty. The repair attempt selected metadata work and transferred zero content/finance pages; it does not claim to have redownloaded all unchanged content.
- Fresh deletion used a currently selected household. The repository test does not render the settings or selection fallback; that is covered by the separate UI regression, not a native phone test.

Evidence remains private under `build/qa/password-flow-http-20261102`: phase logs and summaries, `delete-household-preview-result.json`, `delete-household-committed-evidence.json`, `delete-household-result.json`, `fresh-household-deletion-result.json`, and the original backup manifest. Harness source: `test/organizer/data/e2ee/password_full_flow_http_20261102_test.dart`.

These are real loopback HTTP/client/server results with production cryptographic guards and real SQLite. Platform secret storage is replaced by the existing disk adapter; native vault/UI, phones, public server and Play distribution were not exercised by this workflow.
