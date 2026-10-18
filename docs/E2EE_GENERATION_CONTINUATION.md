# Interrupted migration generations (source implementation)

This is pre-live source, not a deployed protocol or a claim of independent cryptographic review. Runtime representative evidence is still required. The production wizard exposes **Resume after changing devices** on an unfinished migration. Its local request IDs and original signed commands are durable; retries reconcile their original receipts.

`NativeCryptoMigrationGenerationV3` owns the boundary. The exact read is `crypto2.migration.generation.status`, selected by either `generationId` or `migrationId`. The exact writes are `prepare`, `financeDraft`, `draft`, `seal`, `approve`, and `finish` under the same namespace. No ordinary scope, record, grant, or reminder RPC gains a historical-signature exception.

## A: before final publication

A `prepare` with mode `supersede` requires no staged own-log-anchored final scope activation and no installed origin or record. Each account also checks its complete independently verified own log before approving. Unknown or unavailable original attestation proofs leave the operation incomplete; an opaque server list cannot prove publication absence.

Current owners build fresh epoch-one, zero-predecessor candidates using the existing builders. The draft-only branch stores new recovery-wrapped keys as preparatory keys and preserves the exact signed proposal before publishing any head, grant, activation, or floor. Finance contribution preparation is limited to a registered generation/core, with existing eligibility and review rules. The complete candidate hashes, current source heads/access/lifecycle, complete retained proof digest set, and required contributor tokens enter one frozen context.

Each required account signs the closed `JivieMigrationGenerationApproval/v3\n` body `{version:3,serverId,migrationId,generationId,mode,contextHash,accountId,deviceId,authorDirectoryHeadHash,deviceSnapshotHash}`. Its hash is included in that account's ordinary `migrationAttest` event. The opaque token is SHA256 of `JivieMigrationGenerationToken/v3\n` plus canonical `{version:3,serverId,migrationId,generationId}`. Own-log appends are allowed; changing the reviewed identity/device snapshot requires a new explicit review.

`finish` runs in the existing locked SQL transaction. It checks all fresh approvals, exact current source/component CAS and no publication/admission again, marks the old migration aborted and its preparatory heads superseded, detaches only the active head pointers, and creates the replacement migration. Old keys, source rows, captures, staged ciphertext, requests, receipts, signed heads and approvals remain retained. The replacement is still preparatory. It publishes only the exact locally saved approved proposals and later repeats the normal complete FILE comparison and final cutover process.

The coordinator retains the old local capture row/journal before moving its discovery pointer. A new explicit review abandons only the earlier generation's approval capability, retaining that generation and its material. It does not overwrite an old signed request or reuse a consumed nonce.

## B: after a final publication

Mode `continue` preserves the exact old heads, epochs, keys, source roots, targets and already published activation bytes. All required accounts and current lawful scope managers must freshly approve the frozen context under their current device snapshots. There is no genesis reset or reseal.

Only the final locked `commit3` call enters `withContinuedEvidence`. Its private capability permits verification of exact indexed retained proofs with the device key from an included historical directory prefix on the current directory chain. Fresh approvals and current management remain separate checks. The capability is removed in `finally`, including rollback/error paths. It cannot authorize an ordinary RPC or a new signature under an old prefix. The existing commit validator still reconstructs all source, coverage, certificate, recipient, graph and lifecycle checks before atomic installation.

The reachable coordinator path resumes a complete already signed final publication set. A missing original signed endpoint, missing required publication, changed source/head/roles, deleted contributor, absent key material, or orphaned manager leaves the attempt explicitly incomplete/read only with all old data preserved. It does **not** fabricate an old-prefix signature or claim full continuation for material that was never signed. Completion and device-key rotation remain distinct: installing the historical baseline does not enable ordinary writes under a stale signed device snapshot.

Four additive source tables retain generations, approvals, drafts and the exact evidence index: `familyhub_crypto_migration_generations_v3`, `familyhub_crypto_migration_generation_approvals_v3`, `familyhub_crypto_migration_generation_drafts_v3`, and `familyhub_crypto_migration_generation_evidence_v3`. No affected-fence account-deletion snapshot/invalidation subsystem is added; that deletion remains honestly blocked until migration/continuation completes.
