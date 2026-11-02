# Retiring obsolete checkpoint assertions after local device rebind

## Proven problem and narrow correction

The real local password/login workflow is documented in `PASSWORD_FLOW_HTTP_2026_11_02.md`. Ordinary synchronization after local device rebind naturally produced six held checkpoints. After explicit scope review and completed protection, manual sync still reported unknown receipts and `scope_reauthorization_required`. A read-only probe on an isolated clone confirmed that the ordinary historical checkpoint verifier rejects all six old proofs with `history_freshness_pending`.

`CryptoCheckpointSupersession` now authenticates an old retained local assertion through a private `_retainedAssertionHead` method. This validates exact command/payload shape, same server/account, historical signed scope head and role, the exact author directory as a prefix of the freshly verified own directory, and the device signature at that historical directory. The existing descendant check then connects that head to the current one. The method returns only historical head evidence to local bookkeeping; it does not return `CryptoCheckpointAuthority` or admit records.

The current replacement checkpoint still passes the unchanged `SessionCryptoAccess.verifyDomainCheckpoint`, including historical freshness. Existing complete-inventory and known-record/restore-anchor checks, exact signed request hash, zero record claims, unknown-receipt check, fresh authority revalidation and atomic compare-and-swap guards remain in place. The original blocked row, signed bytes and response remain unchanged. No applied receipt is invented. A marker and audit record retire only the derived assertion.

No optional freshness bypass was added to the generic checkpoint verifier. No schema, server, account-key, password or business-record behavior was changed by this correction.

## New focused coverage

`test/organizer/data/e2ee/checkpoint_rebind_retirement_20261102_test.dart` runs a distinct fixture with an actual signed `crypto2.device.rebind`, retired original device and different old/new scope snapshots. Account-directory reducers, scope proposal/activation verification, signatures and SQL guards are real; transport acquisition is synthetic. This coverage supplements the real HTTP workflow and does not replace it.

Thirteen new tests passed on their first functional run:

* An unobserved old assertion can be retired after the rebind while the ordinary historical verifier still rejects it both before and after retirement.
* An assertion signed by the now-retired original device is checked against its exact historical author directory.
* Extra payload fields, negative record counts, malformed author hashes, foreign account binding and bad signatures retain the original evidence.
* Missing scope history and claimed business records prevent retirement.
* A terminal receipt or inventory coverage lost during the receipt lookup prevents retirement.
* Current replacement freshness remains mandatory.
* A validly signed same-account directory outside the current verified lineage cannot authenticate the retained assertion.

Only this new test file was executed. Existing successful tests were not rerun. The shared older fixture has an opt-in rebind variant; its existing default behavior remains unchanged.

Evidence is in `build/qa/checkpoint-rebind-retirement-20261102/`. `new-tests-r1.log` records 13 PASS. The first targeted analysis identified an incorrect new-test import (six derivative errors and one unused-import warning); after correcting the import, `analyze-r2.log` reports no issues for all three changed Dart files. No failed functional test is hidden by this analysis correction.

## Release gate

**Completed locally:** the root agent continued the **same** preserved naturally failing HTTP installation with the corrected source. `sync_after_rebind` attempt 2 passed on 2 November 2026 at 21:17:31 UTC, taking approximately 11 seconds and 266 real HTTP requests. No account, key, scope or business-record reset was used.

The actual run verified six retirement markers with corresponding audit records, the exact original blocked command bytes/responses retained, all six content/finance domains complete with reusable checkpoints, zero active pending/blocked work, no sync error, and removal of the full-refresh marker. Existing task and finance values and their verified record proofs remained intact. Project content's earlier `complete=0` state recovered through the ordinary full sync, without a manual SQL repair.

This satisfies the required successful local workflow gate before release preparation. The user's actual nineteen phone requests have not yet been retried with the correction, so this is **local HTTP success, not confirmed phone or production success**. The complete workflow evidence and release follow-up are maintained by the root agent in `PASSWORD_FLOW_HTTP_2026_11_02.md` and the release documentation.
