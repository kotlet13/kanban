# Email invitation contract 2

Source FamilyHub **0.10.0 / additive schema14**. Deployment and real delivery have separate evidence. Native envelope/HTTPS/bearer rules remain unchanged. `invitationContractVersions: [1,2]` and `features.emailInvitations` advertise the new email flow when the existing dedicated account-mail encryption key and SMTP configuration are available. No account-existence lookup is exposed.

Transport: HTTPS `POST <base>/index.php?controller=NativeApiController&action=handle&plugin=FamilyHub`, `Content-Type: application/json`, body `{"v":1,"op":"operation","params":{}}`. Device authentication uses `Authorization: Bearer <device token>`, never cookies or a global API key. Success is `{"v":1,"data":{}}`; failure is `{"v":1,"error":{"code":"...","message":"...","details":{}}}` with the appropriate HTTP status. Secrets belong in request bodies/headers, never query parameters; redirects must not forward credentials to another origin. The full Native API specification remains in the application source repository.

## Operations

| Operation | Authentication | Parameters | Result |
| --- | --- | --- | --- |
| `invitations2.create` | Owner bearer for concrete nonpersonal, unarchived scope | `scopeId`, `recipientEmail`, `role` (`member` or `viewer`), UUID `requestId`, `language` (`sl`/`en`), optional `expiresIn` integer 60–604800 (default86400) | `{invitation, deliveryQueued:true}` |
| `invitations2.preview` | Public; optional current bearer for accepted-invitation recovery | `token` | `{invitation, scope, inviterName, registrationAllowed, requiresExplicitAcceptance:true}` |
| `invitations2.pending` | Current device bearer | `{}` | `{invitations:[preview...]}` |
| `auth.registerInvitation2` | Public invitation possession | `token`, chosen `username`, `password` (12–72bytes), `displayName`, `deviceName` | Normal device session; **no membership** |
| `invitations2.accept` | Current device bearer | Exactly one of `token` or `invitationId` | `{scope}` |
| `invitations.list` / `invitations.revoke` | Existing owner bearer | Unchanged contract1 parameters | Both invitation kinds handled |

Invitation wire retains `id`, `scopeId`, `recipientUsername`, `role`, `projectFinanceIncluded`, `expiresAt`, `acceptedAt`, `revokedAt`; adds `contractVersion` (1or2), `recipientEmail` (null for v1). Email invitations have `recipientUsername: ""`. Scope previews contain `id`, `kind`, `name`, `projectFinanceIncluded`; acceptance returns the normal full scope wire. `inviterName` is the creator's display name, falling back to username. No token, matched account ID, SMTP payload or account existence is returned to the inviter in create, replay or list. `deliveryQueued` confirms durable enqueue, **not delivery**. Expiry/revocation and scope/issuer permissions are checked again at delivery and acceptance.

Public preview's `registrationAllowed:true` is constant for usable email tokens: it does not reveal whether the recipient already has an account. The registration attempt returns generic `invitation_authentication_required`409 when a verified address is already registered/bound; the recipient then signs in normally. The application may always offer both login and registration. Pending previews are authenticated, have `registrationAllowed:false`, and include no token. Accepted token previews are accessible only to the accepted account with fresh scope access; public/wrong-account requests fail. This supports recovering a lost acceptance reply after restart.

## Recipient identity and sequencing

Email normalization is ASCII-only validation plus trim/lowercase, exactly as account verification. `users.email` and `pending_email` are never accepted as verified identities. A single existing verified address binds the invitation to its durable `accountId`, independent of username/numeric user ID. Ambiguous historical duplicate verified addresses fail closed permanently for invitations created during that ambiguity; neither account gains access. Changing the verified address does not transfer an existing invitation to another account. Registration from a token creates a new chosen username/password account and confirms the invitation address through possession of the emailed capability; it never overwrites an existing account or bypasses login/TOTP.

Email confirmation, email invitation registration and account deletion serialize with the shared native transaction mutex. Confirmation refuses an address already verified by a different account. Registration/confirmation bind all existing unbound invitations for that email to the verified account. Deleting that account removes bound invitations and their cascading encrypted jobs; re-created accounts cannot revive them. No existing identity/session/SMTP key or data is reset by the migration.

The order is **preview → login or registration → explicit accept**. Registration keeps the invitation unaccepted. A lost registration reply is recovered through normal login with the chosen username/password; it cannot register a second account using the same email/token. A second accept by the same accepted account returns current scope access without creating another membership, changing its role, or advancing sequence again. If membership was later revoked, replay cannot restore it. Wrong recipient is `invitation_invalid`403; malformed/expired/revoked/unavailable tokens are generic `invitation_invalid`404 (issuer/scope loss can return existing ACL errors). A caller must preserve the pending token and server/account partition across failure/restart rather than discard it on login success. Recipient inbox acceptance by ID requires the same verified email and durable binding as token acceptance.

## Email and landing

Tokens are `fhi2_` plus64hex characters from32random bytes. Invitations retain only SHA256 hashes. Dedicated queue ciphertext uses existing AES256GCM account-mail encryption, with associated data `<serverId>:email-invitation:<invitationId>`. SMTP uses the existing strict transport, no global BCC, no inbox preferences and no external resources/tracking. The existing account-mail worker drains both queues within its limit/deadline, so existing cron remains valid. Leases last120seconds, failures retry up to5attempts with bounded exponential delay; active leases exclude concurrent workers. Accepted/cancelled jobs clear ciphertext immediately; cron removes expired/revoked/accepted pending secrets. SMTP acceptance means the SMTP server accepted mail, not that a person received/opened it. SMTP retries after a process crash cannot guarantee exactly-once email delivery.

The base URL is administrator `application_url`, optionally overridden by `FAMILYHUB_PUBLIC_URL`. It must be HTTPS, with no credentials/query/fragment; HTTP loopback is permitted only by explicit development configuration. HTTP Host headers never construct invitation links. The link is:

`https://host/base/index.php?controller=InvitationController&action=show&plugin=FamilyHub&language=sl#token=fhi2_...`

The token fragment does not reach PHP or access logs. The public landing is static (no preview request, automatic login or acceptance), no-store, no-referrer, deny framing, and uses a nonce CSP with no third-party content. The user may open `jivie://invite?server=<encoded-base-url>&token=<token>&v=2`, copy that app link, or copy the code and enter it alongside the displayed server. No store ID/public release is invented. Browsers may retain the capability in local URL/history/clipboard, so possession must remain private. Server/error logs never include tokens or request bodies.

Durable quotas: IP120/minute across contract2 operations; sender30create attempts/day; normalized recipient5attempts/day; registration10/IP per10minutes (existing login quotas unchanged). Sender/recipient buckets survive denied transaction rollback. A repeated create request uses its original UUID/body and returns the stored response; it cannot send a second email, and changed bodies produce `idempotency_mismatch`409. Repeated requests still consume request quotas.

Delivery holds the issuer user/scope locks during bounded SMTP, as the existing mail worker holds locks for security mail. Contract2 delivery does not hold the global native mutex during SMTP. Writes on that scope can wait up to the transport deadline; account status/email request do not require the global mutex. HTTPS or SMTP configuration failure preserves a bounded retry job; administrators must configure the canonical URL before enabling invitation creation.

## Backward compatibility and migration

Schema14 adds only `recipient_email`, `recipient_account_id` and a `familyhub_invitation_mail` table with cascading invitation foreign key. Old token hashes, usernames, operation IDs/request bodies, memberships, sessions and instance ID are untouched. Existing `fhi1_` invitation/auth.register semantics remain readable, including legacy automatic membership on username-bound registration. Contract1 refuses `fhi2_`; contract2 refuses `fhi1_`. New clients must capability-gate the email form. Existing Android1.2.0 can continue its username flow against this server. Old clients listing new email invitations receive an empty recipientUsername and can still revoke by ID; they cannot create/accept the new format through contract1.

The migration is supported on SQLite, MySQL8.4 and MariaDB10.11. Back up database/privatefiles/config before a hosted upgrade, restore in isolation, and verify identity/counts before applying the additive migration. Rolling plugin source back while keeping schema14 is not the documented downgrade path: restore the verified preupgrade snapshot. Real hosting, SMTP delivery and physical app-link behavior require separate evidence.

## Local verification

`server/tests/email-invitation-integration.php` performs77checks on each isolated SQLite/MySQL/MariaDB environment, including real loopback SMTP only, concurrent accepts/registrations, confirm-versus-register uniqueness, SMTP-versus-revoke, duplicate historic identities, account deletion/recreation, replay recovery and both quota dimensions. Existing account48checks and deletion36checks also pass on all three. These are synthetic tests, not evidence of hosted delivery or phone behavior.
