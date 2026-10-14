# Changelog

## 0.14.0 — 2026-10-14

- Add reviewed whole-space and project deletion with counted previews, durable tombstones, idempotent retries and post-commit private-image cleanup. Preserve accounts, devices, parents and unrelated financial facts; reject deletion graphs with external dependencies.
- Extend archival to household and organization spaces, including descendant write, invitation and delivery guards. Normal member removal revokes direct descendant access; child ownership requires resolution first.
- Add sync6/record6 for archived projects, idea-board format2 text sizing and garden-scene format3. Keep original queued operation identities and require compatible clients for richer records.
- Add task-relative reminders and negotiated push display format2. Modern Android renders grouped topic notifications; legacy Android and iOS retain operating-system alerts. Shopping notifications open the authorized parent list, including deleted-item context.
- Migrate schema17 to18 additively: scope deletion markers and private-file cleanup queue, relative-reminder fields and push notification-format registration. Existing registrations default to legacy format1.

Back up the database, private data tree and configuration before upgrading, and verify restoration. Source publication does not establish a hosted deployment or physical-device delivery.
