# Changelog

## 0.15.0 - 2026-10-16

- Add organization tables with bounded raw cells/formulas, expected revisions, exclusive renewable device leases and explicit client saves. Add schema19's five document/attachment/request/cleanup tables without changing existing records or preferences.
- Add authenticated private scope/task/table attachments, bounded chunk transfers, size/hash/type validation, private storage, report evidence and durable lifecycle/account cleanup. Backups must include every database table and the entire private DATA_DIR, configuration, encryption keys and cron. PHP ZipArchive is required for ZIP office formats; GD remains required for idea photos.
- Extend policy3 invitations with exact existing Native usernames alongside email, durable recipient identity and separate authenticated acceptance. Atomic resend replaces the old invitation and pending encrypted delivery together; older servers are capability-gated.
- Simplify SL/EN invitation mail/landing with exact expiry/timezone, accurate access descriptions, Android install and return-to-original-email guidance; public iOS availability remains pending.
- Fix boolean householdPerson.archived validation without weakening project record6 or other record fields. Prevent username reuse from revoking/deleting another account's durable modern invitation.

## 0.14.1 — 2026-10-15

- Default notification sound to on in every category when no preference is stored or a partial stored preference omits `sound`.
- Preserve every stored `sound: false` and `sound: true`, including values materialized by older versions. Do not migrate, backfill, clear or rewrite existing settings.
- Resolve the current category sound preference immediately before push delivery, including Android display2 and operating-system notification payloads.
- Retain schema18, worker setup, request identities, keys and registrations. Do not replay notification history or opt devices in automatically.

## 0.14.0 — 2026-10-14

- Add reviewed whole-space and project deletion with counted previews, durable tombstones, idempotent retries and post-commit private-image cleanup. Preserve accounts, devices, parents and unrelated financial facts; reject deletion graphs with external dependencies.
- Extend archival to household and organization spaces, including descendant write, invitation and delivery guards. Normal member removal revokes direct descendant access; child ownership requires resolution first.
- Add sync6/record6 for archived projects, idea-board format2 text sizing and garden-scene format3. Keep original queued operation identities and require compatible clients for richer records.
- Add task-relative reminders and negotiated push display format2. Modern Android renders grouped topic notifications; legacy Android and iOS retain operating-system alerts. Shopping notifications open the authorized parent list, including deleted-item context.
- Migrate schema17 to18 additively: scope deletion markers and private-file cleanup queue, relative-reminder fields and push notification-format registration. Existing registrations default to legacy format1.

Back up the database, private data tree and configuration before upgrading, and verify restoration. Source publication does not establish a hosted deployment or physical-device delivery.

## 0.13.0 — first standalone public source publication, 2026-10-13

- Editable idea-board records (`sync5`) with authenticated private photographs
  and image-attached annotations; complete board/image evidence for reports.
- Shared-content policy acceptance and content/member reporting, with private
  administrator review and bounded evidence retention.
- Whole-household/organization and project-only sharing, private synchronization,
  scoped finances and linked payments, invitations, account recovery/deletion.
- Existing bounded notification/reminder/email/push workers and read retention.

Schema17; PHP runtime source unchanged from the reviewed FamilyHub0.13.0 source
distribution. Source is published with a fresh history, installation ZIP,
MIT license and standalone documentation. This is not a new Jivie Android build
or an automatic upgrade of anyone's Kanboard installation.
