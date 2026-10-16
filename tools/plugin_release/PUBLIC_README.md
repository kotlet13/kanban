# FamilyHub 0.15.0 for Jivie

FamilyHub **0.15.0 / schema 19** is a Kanboard plugin for optional self-hosted accounts, private synchronization and shared household/project spaces in Jivie. Jivie's personal local use does not require this server. Managed hosting is not included. This repository contains plugin source only, with a fresh publication history; it does not contain the mobile application's history or production configuration/data.

## Organization tables and private documents

Version0.15.0 adds organization tables with raw text, numbers/formulas, whole-document revision checks and an exclusive90-second renewable device lease. The server stores raw formulas without evaluating code or fetching URLs. Other authorized members can view while one device edits. Private attachments belong to the exact shared scope, task or organization table; each authenticated upload/download rechecks current access. Limits are20MiB/file and256MiB/scope. Supported formats are PDF, DOC/DOCX, ODT, XLS/XLSX, ODS, TXT, CSV, RTF and JPEG/PNG; ZIP office formats require PHP ZipArchive. Files are never publicly linked, executed or rendered by FamilyHub. See [DOCUMENTS_API.md](DOCUMENTS_API.md) for exact limits, operations, moderation, cleanup and retention.

Schema19 adds five tables without rewriting existing users, content, preferences, sessions or keys. Capabilities `spreadsheets` and `attachments` remain false until the complete schema exists. Retain the existing reminders cron: it also retries document cleanup and removes expired unfinished uploads/orphan files in bounded batches. Back up **all database tables, every file below private DATA_DIR, configuration, encryption keys, matching source and cron**, and verify a complete isolated restore before upgrade. Protect the private data tree outside public document roots; attachment directories/files use0700/0600. Source packaging is separate from a hosted migration.

## Explicit username or email invitations

Version0.15.0 extends invitation3 with a recipient email or exact existing active username. Username invitations bind the durable Native account, disclose no email, require a separate explicit acceptance and appear in that account's pending invitations, even without SMTP. They never register or automatically join an account. New recipients still use the email flow. Clients must check `usernameInvitations` and `invitationResend` capabilities; older servers do not gain these features by changing labels. Atomic resend creates a new ID/token/expiry, invalidates the previous link and cancels its unfinished mail job in the same transaction. Retries reuse the same request identity/body. See [the sharing contract](docs/space-sharing-api-contract.md).

Invitation mail gives the exact expiry date/time with UTC timezone and accurate policy-specific rights. Its SL/EN landing offers the existing Android install link, clear return-to-original-email guidance after installation and an app-open action. It does not promise automatic invitation transfer through the store; iPhone/iPad public availability remains pending. Registration and login alone never accept modern invitations. The release also fixes record3 household-person archive validation while preserving record6 project archive checks and protects account-bound invitations when an old username is reused.

## Space lifecycle and notifications

Version0.14.0 adds counted, owner-reviewed whole-space deletion and editor-authorized inline project deletion. Closed content graphs are removed with durable tombstones and retry-safe request identities; unrelated scopes, accounts and devices remain. External financial dependencies and separately owned descendants block deletion. Private image unlink runs after commit through a durable cleanup queue. Archive pauses descendant writes, invitations and delivery while retaining history. Normal member removal also revokes descendant direct access, with child-ownership safeguards. See [the lifecycle contract](docs/scope-lifecycle-api-contract.md).

Schema18 also adds task-relative reminder scheduling and negotiated push display format2. New Android clients render grouped topic notifications from data-only delivery; legacy Android and iOS retain operating-system alerts. Shopping notifications resolve their authorized parent list. Existing registrations remain format1 until explicitly upgraded. Sync6/record6 supports archived projects, idea-board format2 and garden-scene format3 without rewriting old queued bodies. Back up all database tables, the entire private data tree and configuration, then rehearse restoration before upgrading. See [the changelog](CHANGELOG.md).

## Editable idea boards

Version0.13.0 introduced local-first editable boards with text, photos, drawing and image-attached annotations, plus authorized household/organization/project sharing. `sync5` adds the idea record without rewriting old operations. Image transfers are authenticated, bounded and private, with verified hashes and no public attachment URLs. Explicit board saves produce the `ideas` notification category; image chunks do not notify. Reports retain the complete board and private photos for administrator review. GD PNG/JPEG support is required; missing support is advertised and rejects new writes while older content remains usable. Back up all database tables and the entire private `DATA_DIR`, including `familyhub/ideas` and `familyhub/attachments`. See [the idea-board contract](docs/ideas-api-contract.md). Source preparation does not establish a hosted upgrade.

## Notification defaults

Version 0.12.0 adds shared-content policy acceptance and reports to the administrator of this server. Reports and their evidence stay on this installation; they are not sent to TriparNA. Only authorized shared content or visible members can be reported. Reporting does not automatically remove content or membership, and is available without accepting the shared-content policy. Local use and personal private synchronization remain separate. See [the moderation contract](docs/moderation-api-contract.md) for operations, access checks, administrator handling and retention.

Read inbox notifications retain the existing seven-day period from the first read; marking unread cancels retention. Cleanup uses the existing reminders cron and visibility revision. Missing category preferences enable in-app, push and sound for every category, including reminders and Ideas; email remains disabled. A missing sound field in an older partial preference inherits sound-on. Every explicitly saved false or true remains unchanged. This default change performs no migration, backfill or rewrite of existing settings; reading preferences or delivering an event never materializes default preference rows. Workers reread the current saved choice before delivery. Device registration and operating-system permission are still separate; the update does not register devices or deliver historic notifications.

## Whole-space and project-only sharing

Policy 3 separates the shared boundary from account ownership. A member of a shared household or organization can work with all its shared content, finances and existing/future projects, including editing, deleting and managing invitations/members within that boundary. A project-only member receives those rights inside that project, with no access to its parent or siblings. Private payment accounts and other personal data remain separate. Ownership identity and last-owner safeguards remain in place; membership never grants server administration or access to another person's account.

New scopes explicitly request policy 3. Existing policies 1/2 require an owner-reviewed migration preview; old invitations do not silently acquire broader meaning. The versioned invitation contract 3 communicates the exact boundary and rights. Legacy household projects stored inside the household need a reviewed extraction of their closed dependency graph before they can be shared individually. Cross-project financial dependencies must be resolved rather than exposed through a broader invitation. See [docs/space-sharing-api-contract.md](docs/space-sharing-api-contract.md) for compatibility, migration preconditions and access checks. Source preparation is separate from deployment and physical device verification.

## Email invitations

Version 0.10.0 adds invitations addressed to a verified email identity. The owner enters an email and role; the encrypted account-mail worker sends an expiring invitation link. New recipients choose their own username and password, existing users sign in, and both explicitly accept the invitation before obtaining membership. Registration itself grants no access to the invited space. The sender never receives the registration token or an account-existence result. Legacy username invitations remain available through the original contract. See [docs/email-invitation-api-contract.md](docs/email-invitation-api-contract.md) for compatibility, limits and identity checks.

Email invitations require the existing account-mail encryption key and SMTP configuration, plus an administrator-configured HTTPS Kanboard application URL (or `FAMILYHUB_PUBLIC_URL`). Do not derive this address from an untrusted request header. The existing `cli/account-mail.php` worker also processes invitation messages; no additional cron is necessary. Enqueueing and SMTP acceptance do not prove delivery to the recipient's inbox. Links open a read-only SL/EN landing page with an app-open action, Android install guidance and link/code-copy fallback; opening a link never accepts membership.

## Spaces policy and gardens

Version 0.8.0 adds explicit organization leadership, reviewed opt-in migration to project financial read membership, stable local-space publication and household garden synchronization. Existing organizations keep policy 1 until an owner reviews and applies the current access preview. Policy-2 members see all finances of their accepted projects; leaders see all existing/future organization projects. Editing requires separate direct roles/grants. Leadership is not a delivery subscription. `sync4` preserves format-2 household garden documents with bounded validation, revision conflicts and tombstones. Source updates and test results are separate from any hosted deployment. The exact versioned contract is in [docs/spaces-api-contract.md](docs/spaces-api-contract.md).

## Linked personal payments

Version 0.9.0 adds one canonical organization expense plus explicitly selected private/household cash and receivable projections. Reimbursement legs require source financial write authority, preserve request identities across retries, and never become duplicate expense/income rows. Private card identifiers remain private. Older clients must upgrade before reading financial scopes with linked payments. Complete snapshots are bounded to 512 KiB; larger histories return an explicit incomplete error. Account deletion policy 3 requires a fresh review of retained shared financial facts and private projection removal. See [docs/linked-payments-api-contract.md](docs/linked-payments-api-contract.md) for methods, limits and local-first recovery boundaries.

## License and requirements

The plugin's new code is licensed under [MIT](LICENSE), copyright TriparNA – kooperativa za sonaravno življenje in razvoj tehnologij samooskrbe, z.o.o. Existing third-party notices remain applicable. No third-party library or Kanboard core source is bundled. Kanboard is MIT licensed. Optional SMTP uses Kanboard's existing Swift Mailer library (MIT, copyright 2013–2016 Fabien Potencier); it is not copied into this repository and is no longer maintained upstream.

Compatibility is restricted to **Kanboard 1.2.54**, PHP **8.1+**, PDO SQLite or MySQL/MariaDB, and HTTPS. PHP 8.4 and SQLite/MySQL/MariaDB were used in isolated development checks. This is not a guarantee for every host or a production installation certificate. No Kanboard core patch, production Composer installation, Docker, SSH or permanent worker is required.

## Installation on your own server

1. Back up the complete Kanboard database, configuration and attachments. Verify that the backup can be restored in a separate environment before installing or upgrading the plugin.
2. Copy this directory as `plugins/FamilyHub` under the Kanboard installation. `Plugin.php` must be directly inside `FamilyHub`; avoid an extra nesting level. Do not copy repository metadata or private files into the public web root.
3. Load Kanboard to apply the plugin's additive database migrations. Check database permissions, supported driver and plugin loading before enabling the API. New FamilyHub tables do not automatically import old Kanboard project data or financial metadata.
4. Enable the desired features in Kanboard's protected configuration only after testing with non-production accounts. Keep backups and credentials outside all HTTP document roots.

The normal installation defaults are deliberately disabled. The minimum explicit configuration for the native API is:

```php
define('FAMILYHUB_ENABLE_NATIVE_API', true);
```

If your deployment is **self-hosted**, the account deletion feature additionally requires:

```php
define('FAMILYHUB_ACCOUNT_MODE', 'self_hosted');
```

Never set development-environment or plaintext-transport flags on a production server. At a TLS reverse proxy, set `FAMILYHUB_TRUSTED_PROXY_IPS` to the exact trusted proxy IPs; untrusted forwarded headers do not satisfy HTTPS checks. `FAMILYHUB_CORS_ORIGINS` defaults empty. If browser API use is required, configure exact approved origins, with no wildcard or cookie-credential fallback.

## API and accounts

Native HTTP endpoint, relative to your Kanboard base directory:

```text
POST index.php?controller=NativeApiController&action=handle&plugin=FamilyHub
Content-Type: application/json

{"v":1,"op":"capabilities","params":{}}
```

Capabilities describe the durable server identity, record contract versions and currently available features. Do not infer a configured SMTP, push or enrollment service from plugin installation alone. Authenticated calls use the user's revocable bearer device token. Never use a global `jsonrpc` key or an administrator credential in a mobile client.

Existing local Kanboard users authenticate with `auth.login`, their password and configured TOTP. Capability-gated `auth.renew` extends an active device session to 30 days during its last seven days using the same bearer and device; expired, revoked or credential-invalidated sessions cannot renew. External-authentication providers are unsupported. Enrollment for the first native account requires a short-lived administrator-issued code; Settings → FamilyHub Bootstrap exposes a protected issuance page. After the first native account, additional new users require invitations. Creating an account is distinct from signing in or joining a space.

`personal.ensure` creates an owner-only private space on explicit request; signing in does not upload personal data. Shared native household/project spaces have their own memberships and individual records. Generic `sync3` carries projects, tasks, events, shopping and people without accounts; `finance2` carries financial accounts, monthly rules and entries. Financial access is still checked at the financial API boundary: policy 3 derives it from membership, while legacy policies retain their documented grant rules. A linked task and cost use an atomic paired operation. A person profile does not create a sign-in or membership. Household/organization child projects inherit full-space access under policy 3; independently invited project members have no parent access. Project scopes have one permanent root project. Recoverable archival preserves records, memberships and financial history while preventing normal writes and active reminders. Older operation bodies retain their original IDs and hashes through a versioned bridge; older clients cannot silently erase rich metadata. Legacy Kanboard web projects do not edit the new native tables. A revoked member loses future server access; previously obtained offline copies cannot be recalled.

Legacy project invitation proof APIs remain separately disabled. Do not enable `FAMILYHUB_ENABLE_PROJECT_INVITATIONS` on real financial projects: old Kanboard project metadata has no independent private-finance boundary.

## Self-service account deletion

The complete versioned deletion contract and verified limits are included in [docs/account-deletion-contract.md](docs/account-deletion-contract.md).

Open this relative URL on the same HTTPS Kanboard server:

```text
index.php?controller=AccountDeletionController&action=index&plugin=FamilyHub
```

The page operates on the user's Kanboard/FamilyHub account on this server, and requires sign-in, a current preview, explicit consequences/ownership decisions and fresh password/TOTP confirmation. Native clients use `account.deletion.preview`, `account.deletion.confirm` and a private receipt for `account.deletion.status`. Deletion removes the Kanboard sign-in as well as the native identity; signing out or disabling an account is not the same operation.

Deletion policy 2 requires explicit child-project detachment when an organization is removed and explicit structural preservation where foreign content depends on it. It does not expose inaccessible child project names. Shared owners must transfer ownership to an eligible member or explicitly delete an eligible sole-owner scope. The preview specifies which original-author contributions are removed and which structures need explicit preservation for other members. Edits inside other authors' records can remain as part of their shared record; the system does not promise field-by-field historical authorship. Certain legacy objects with other contributors require resolution instead of deleting those other users' content. An SQL commit alone is not completion when physical file cleanup remains pending: keep the receipt and check status. `account.deletion.cancelPending` can resolve an unknown request using its original strong receipt token; cancellation and deletion are serialized. Creating a new cancellation marker requires authentication as the original account. An existing receipt can still report its outcome using the strong token after the account is gone; do not send another account’s bearer or reuse its identity for this step. A confirmed cancellation prevents the old request from deleting later; if deletion already committed, cancellation reports that outcome rather than restoring the account. A status result of `deleted:false` alone does not prove that an original request cannot still finish.

Deleting a server account does not erase independent local data, exported files, other members' downloaded copies, hosting logs or protected server backups. Their handling is the server operator's responsibility. Report evidence has the specific retention below; hosting logs/backups have the operator's separate policy. Native operations are coordinated; concurrent writes through legacy Kanboard core routes do not share all of that coordination. Do not present this plugin alone as a complete store-ready or compliance-certified product.

## Shared rules and reports

Jivie explicitly shows and accepts versioned rules before uploading shared content. Reading, reporting, joining an invitation and safety actions such as member removal or reminder cancellation do not require this acceptance. Personal synchronization is exempt. A new server enforces the policy for older clients too; coordinate the plugin and client upgrade so users can accept the new rules. Pending edits are not rewritten as consent flags.

Kanboard administrators review reports under Settings → FamilyHub reports, at `index.php?controller=ModerationController&action=index&plugin=FamilyHub`. Active administrator sign-in, TLS, CSRF, a review note and revision checks are required. Removal/restriction/reversal requires an explicit confirmation checkbox. Reporting alone does not sanction anyone. Leaf content can be tombstoned; structural parent/root text can be redacted without destroying its child graph. Scoped restrictions are reversible and preserve original grants/membership; reversing a restriction does not restore an independently removed membership. Financial ledger records are not deleted through moderation.

The limited preview and report details stay on this server. Open reports remain for review. Evidence, details and review notes are redacted 180 days after resolution/dismissal by bounded cleanup (existing reminders worker or administrator page); minimal process metadata remains. Account deletion removes associated acceptance/reports/audits as disclosed in its preview. Operators must review reports and run cleanup; a reporting button alone does not certify compliance.

## Optional delivery

The account/inbox remains in FamilyHub. Email and FCM are optional delivery channels; a successful registration or provider acknowledgment does not prove a displayed notification.

SMTP requires `FAMILYHUB_SMTP_HOST`, `FAMILYHUB_SMTP_PORT`, `FAMILYHUB_SMTP_ENCRYPTION` (`ssl` or `tls`), `FAMILYHUB_SMTP_FROM`, and any provider-required username/password. Verified TLS is mandatory; no `mail()` or global BCC fallback is used. Account verification/recovery additionally requires a separate random 32-byte base64 `FAMILYHUB_ACCOUNT_MAIL_KEY_BASE64`, read from a private protected file.

FCM requires `FAMILYHUB_ENABLE_FCM=true`, `FAMILYHUB_FCM_PROJECT_ID`, a private `FAMILYHUB_FCM_SERVICE_ACCOUNT_FILE`, a separate random 32-byte base64 `FAMILYHUB_PUSH_KEY_BASE64`, and verified `FAMILYHUB_PUBLIC_ROOT`. The sender and compiled mobile client must use compatible Firebase project configuration. Arbitrary servers do not gain universal push delivery automatically. Service-account JSON/APNs keys must never enter this directory, client configuration or a public repository.

Optional CLI cron commands, run from the Kanboard root with the host's PHP CLI:

```sh
php plugins/FamilyHub/cli/reminders.php --limit=100
php plugins/FamilyHub/cli/delivery.php --limit=20
php plugins/FamilyHub/cli/account-mail.php --limit=20
php plugins/FamilyHub/cli/account-deletion-cleanup.php
php plugins/FamilyHub/cli/push-preflight.php
php plugins/FamilyHub/cli/push.php --limit=20
```

Configure only the workers your deployment uses, after reviewing their source and configuration. A minute cron can dispatch bounded work without a permanent process. Preflight does not perform a delivery test. Store each encryption key with protected server backups; changing a key does not magically decrypt old queued ciphertext. Avoid secrets, private data and enrollment-code output in cron email or logs.

## Upgrade, rollback and validation

Back up before every migration and rehearse restoration. Removing the plugin directory disables endpoints and workers but does not drop its tables, undo memberships, restore deleted accounts or remove downloaded copies. Roll back database changes by restoring a verified full backup; never improvise rollback by deleting invitation or finance rows. Replacing 0.12.0 with older code alone bypasses its restrictions and policy checks; do not treat that as a safe rollback.

Before use, test allowed and denied access with synthetic accounts, two-device editing/retries, revocation, private-space isolation, financial permissions, account deletion and actual delivery for any enabled channel. This source package excludes development environments, test credentials and private fixtures. The distribution is preparation for an independently operated deployment; it does not authorize installation on a production server.

Publisher/contact: [TriparNA](https://triparna.si/) — [support@jivie.app](mailto:support@jivie.app). Do not send passwords, tokens, server keys or personal backups to support.
