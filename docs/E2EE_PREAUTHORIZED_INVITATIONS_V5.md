# Existing-account preauthorized E2EE invitations (v5)

Status: local implementation contract; no native or production approval. Existing
v4 invitations, signatures, data and acceptance paths remain supported unchanged.
This is an additive capability, advertised only when both protocol support and
new reservation storage are ready. Old clients must fail closed on new head
fields rather than overlooking their preparation and lifecycle semantics. Once
a space receives such a head, its older member clients need an app upgrade to
sync it. Host capability discovery does not negotiate support with every member
device; that compatibility negotiation is outside this local implementation.

An owner authorizes disclosure by pressing Send. For an existing verified account
on the same server, the owner installs encrypted envelopes and a prepared signed roster during Send.
Send already authorizes that exact recipient's cryptographic rights. The
recipient's later explicit signed consent activates ordinary SQL access
without another owner request, scope head, epoch, key rotation or access revision.
The host receives public keys, signatures and sealed envelopes, never domain keys.
This protocol does not solve delivery of keys to an account that does not yet exist.

## Exact wire additions

All commands retain the version-2 signed command envelope and existing domains.
`crypto2.invitations.resolvePreauthorization` is an authenticated, manager-only
read with `{scopeId, recipient, role, afterGeneration?, limit?}`. It resolves only
a current verified email identity or active username and returns:

```
{
  recipient: {kind: "email" | "username", value: string, accountId: UUID},
  preauthorization: {
    version: 1,
    member: {
      accountId, rootSigningKeyBase64, rootEncryptionKeyBase64,
      recoveryRootEpochId, identityEpochId, directoryHeadHash,
      deviceSnapshotHash, role, financeRole, manageKeys
    },
    policyVersion: integer,
    accessBasis: [{scopeToken: SHA256, accessRevision: integer}]
  },
  recipientDirectory: <existing paginated signed directory representation>
}
```

Email resolution is protected by current scope management permission, not a public
account lookup. The client verifies the complete directory and existing identity
pins. No pending or unverified address may resolve. The member has exactly the
existing ten-field scope-member shape. Direct invitations support verified policy 1, 2 and 3 using the existing exact
projected rights. Missing recipient keys fail explicitly. An existing ready
account never silently falls back to a delayed manual invitation. An exact
`crypto_invitation_recipient_unregistered` result, meaning no current verified
email identity exists, retains the existing new-account v4 flow. That path still
uses its legacy acceptance and owner-admission lifecycle.
Old hosts without invitationPreauthorizationVersions:[1] retain explicit v4
compatibility; no v5 success is claimed for those hosts.

Signed create/resend adds optional `preauthorization` with exactly the object
above. Its ordinary payload also binds invitationId, recipient, role, expiry,
server, source membershipHeadHash and expectedAccessRevision. The declared
member/role/policy/basis must match the fresh protected resolver and current head.
The complete signed create proof hashes to `preauthorizationProofHash` using the
existing canonical proof hash. Existing requests without this object remain v4.

A head may add `invitationPreauthorizations`, a prepare-marker sorted list (accountId order, maximum
100) whose entries have exactly:

```
{accountId, invitationId, preauthorizationProofHash, invitationScopeId}
```

Each entry refers to a roster member. For a direct invitation invitationScopeId
is this head's scope. An inherited child preparation marker references the same parent
invitation and is allowed only with the existing verified signed parent/child
relationship and policy. A joining membership intent is either the existing
`{accountId, invitationId, acceptanceProofHash}` or the new, exclusive
`{accountId, invitationId, preauthorizationProofHash}`. Never substitute a fake
acceptance hash for a preauthorization. Preparation markers survive subsequent heads until an explicit signed removal,
or an exact owner-signed resend/replacement of a revoked or expired invitation.
A consumed invitation cannot be replaced through this pending-invitation path.

`crypto2.invitations.publishPreauthorization` is signed by the invitation
creator account, which must still hold current owner/manager authority:

```
{scopeId, invitationId, preauthorizationHeadHash,
 childHeads: [{scopeId, headHash}], authorDirectoryHeadHash}
```

The parent and every required child are already fully activated with ordinary
closure, key, grant-manifest, lifecycle, current-authority and CAS checks. Server
readiness checks the complete current graph and exact stored reservations.
Publication releases mail delivery. Send is successful only after this succeeds.
Interrupted preparation retains exact journals/proposals/keys and remains
unpublished; it never manufactures consent or silently restages an unknown request.

Signed `crypto2.invitations.accept` retains the existing payload and adds
`preauthorizationHeadHash` if and only if this is a preauthorized invitation.
It is the exact published readiness head, even if the current scope has
advanced. Before first publication, a verified current descendant preserving the
exact preparation and complete grants may become that readiness head; this never
restages keys or changes the original create proof. Acceptance verifies the same account roots/identity epoch/device
snapshot and complete prepared reservation. It atomically records exact signed
consent, sets ordinary SQL membership active and consumes the invitation. The
reserved access revision is not incremented. Normal v4 accept still returns
pending keys and uses its unchanged owner-admission path.

The accept result is `state: "keysReady"`. Status for the consumed new path contains `admissionMode: "preauthorized"` and the existing
`activatedHeadHash` (the published readiness head),
`acceptanceProofHash`, and scope. Existing consumed/manual status is unchanged.
The preview includes the published `preauthorizationHeadHash` for signing consent.

The consumed status retains recipientAcceptanceAuthorization using the existing
recipient proof format. Scope-local directory reads permit the exact referenced
creator/publication/recipient signer prefixes. No global consent-proof endpoint
or per-head consent overlay is required by this narrowed trust model.

## Trust, authority and disclosure invariants

**Owner Send authorizes disclosure and the exact signed roster rights.** The
recipient already has cryptographic authorization after Send; its private keys
alone open the sealed envelopes. The hosting administrator cannot decrypt those
envelopes or domain content with public directory data, delivery tokens or SQL.
Existing hosting administration and first-use directory trust remain explicit;
verified/pinned identity replacement, key, policy, head, closure and CAS guards
are not relaxed.

The recipient's Agree action is a distinct UI/server lifecycle condition.
Ordinary SQL membership stays inactive and undiscoverable until the recipient's
exact signed acceptance. The new invitationPreauthorizations field is a prepare
marker, **not a cryptographic consent restriction on the signed roster**. Existing
member()/manager/signature verification continues to use the owner-authorized
roster. No global consent overlay or unsigned consent boolean changes the
cryptographic authority model. A malicious hosting administrator could bypass
its own consent UI/access lifecycle for an already owner-authorized recipient,
but cannot open that recipient's envelopes. This scoped trust choice is explicit
and is not a claim of cryptographically enforced recipient consent against a
malicious host and recipient working together.

Automatic opening still requires the exact owner-signed invitation, published
origin/pregrant head and the recipient's own signed acceptance proof; a status
string or SQL flag alone cannot manufacture this client checkpoint. Both signed
payloads bind server, invitation, scope, creator proof hash, role, expiry and the
original recipient identity. The normal head chain verifies any later authorized
device, root or rights update; original signed evidence is retained as history.

Before disclosure, all current identity, policy, head and inventory checks run.
reviewedRecoveryBaseline is never automatically approved. Device/root changes
that cannot be justified with existing verified recovery/key distribution fail
closed. A directory-head-only advance with unchanged identity/device snapshot is
not a replacement account and may use its verified historical prefix.

Recipient acceptance does not expose local personal data. Existing ready accounts
use their current login and key material; no second account setup or owner grant
is part of this path. Scope titles remain encrypted and are opened only through
the verified accepted scope/key path.

## Lifetime, graph and concurrency

Prepared reservations persist independently of invitation usability. For an
unaccepted reservation, expiry or revoke blocks new consent and ordinary SQL
access remains inactive. Removing the reservation from crypto parity requires a
normal signed roster-removal rotation. Revoking an invitation does not remove
already accepted membership; that uses normal membership removal and rotation.
Otherwise an unsigned expiry would invalidate the active head for everyone.
Already delivered ciphertext/key envelopes cannot be erased retroactively.

Future rotations preserve pending preparation markers and seal keys only to
their bound recipient identity. A head dropping a slot invalidates admission. New
inherited children created while a parent preparation is pending must include
the matching preauthorization grant; acceptance validates current graph readiness again. Existing
parent/child signed relationship and financial policy checks are retained.

Different invitations serialize through ordinary current-head CAS. No prepared
head is frozen until later acceptance: the owner activates it during Send, so
later content writes do not invalidate closure cursors. Lost replies and repeated Send/accept calls reuse original signed requests,
receipts and keys. After restart, an explicit Send with the same scope,
recipient, role and language resumes the unique unfinished signed preparation
with its original action, request, token and keys. Completed, terminal, expired,
revoked or superseded attempts do not become a new automatic grant. Ambiguous
matching preparations require review. This is explicit retry, with no startup
worker or timer. Terminal rejection cannot be treated as applied. No key/claim/journal reset is
permitted. Tests are new local targeted controls, at most three attempts each;
previous PASS controls are not repeated. Native, phones, production, full UX and
performance claims require their own later evidence.

Member-list display may use optional headGet `acceptedAccountIds`: a trusted
SQL lifecycle projection intersected with the independently verified signed
roster. It hides unaccepted preparations from the accepted-member list and never
changes cryptographic membership, key access, or signature/manager authority.
If a host omits the projection, marked recipients remain hidden in that display.
