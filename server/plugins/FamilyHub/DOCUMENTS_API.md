# Organization tables and private attachments (local schema 19)

This source adds capabilities `features.spreadsheets` and `features.attachments` only when every schema 19 table is present. API enablement, authenticated devices, account binding, current inherited membership, moderation blocks, read-only roles, archived parent scopes and archived inline projects still apply. No deployment or public release is implied. Plugin version remains unchanged.

All methods use the existing native v1 JSON POST envelope. UUID fields use canonical lower-case UUIDs. Request IDs belong to one scope/account/device across all document methods: keep the same ID/body for retries and use a fresh ID for each different operation, including begin versus complete. Successful mutations have durable receipts; authorization is checked before replay. Responses and rate limits contain no private filesystem paths.

## Tables

Tables initially belong directly to organization scopes. `tables.list(scopeId)` returns `{sheets:[...]}` with summaries: cells is `{}`. `tables.get(scopeId,id)` returns `{sheet,lease}`. A sheet has `id,scopeId,title,cells,revision,updatedAt` (epoch seconds). Cells are raw strings keyed by A1 addresses; the server never evaluates formulas or fetches external formula data. Creation starts at revision 1. Maximum 100 live tables per scope ensures the complete list stays bounded.

- `tables.create(scopeId,id,title,requestId)` → `{sheet}`
- `tables.acquire(scopeId,id,requestId?,token?)` → `{lease}`
- `tables.renew(scopeId,id,token,requestId?)` → `{lease}`
- `tables.release(scopeId,id,token,requestId?)` → `{released:true}`
- `tables.save(scopeId,id,token,expectedRevision,title,cells,requestId)` → `{sheet}`
- `tables.delete(scopeId,id,token,expectedRevision,requestId)` → `{deleted:true}`

Clients should always provide requestId for lease actions. The exclusive lease lasts 90 seconds; renew every 25 seconds while editing. Even a second device belonging to the same account must wait. An active lease exposes holderName,holderAccountId,holderDeviceId,expiresAt; only its authenticated device receives token. The token is derived using that device's bearer and an unpredictable acquisition nonce. Only its SHA-256 hash is stored. A lost/expired lease cannot save, renew or release a later holder's lease. Table writes also compare the expected revision. An already-successful save retry acknowledges the original committed receipt; it does not perform a new write.

Title is at most 200 UTF8 bytes. Documents allow 10000 nonempty cells, 4096 UTF8 bytes per raw cell and 512KiB encoded cells; addresses A1..ZZZ100000. Main failures: table_unavailable (404), table_locked (409) (safe holder lease), lease_lost (409), table_conflict (409) (current sheet), table_limit (422), validation_error (422), idempotency_mismatch (409), permission_revoked (403) and scope_archived (403). Shared table create/save requires the existing content-policy acceptance.

## Attachments

Every call supplies the exact triple scopeId,targetType,targetId. Supported targets are scope (its own scope UUID), task (a live task in that scope), and table (a live organization table). Task targets recheck the live project context; project-only access never opens a parent or sibling scope. Pending uploads are absent from lists and cannot be downloaded. Only the original authenticated account/device uploads chunks or completes its upload. Any currently authorized editor can delete a published file.

- `attachments.list(scopeId,targetType,targetId)` → `{attachments}`
- `attachments.begin(...,id,name,mime,size,sha256,requestId)` → `{attachment}`
- `attachments.chunk(...,id,offset,dataBase64)` → `{attachment}`
- `attachments.complete(...,id,requestId)` → `{attachment}`
- `attachments.get(...,id,offset?,limit?)` → `{attachment,offset,dataBase64,total,done}`
- `attachments.delete(...,id,requestId)` → `{deleted:true}`

Metadata has id,scopeId,targetType,targetId,name,mime,size,sha256,createdAt,complete,offset. A chunk is at most 262144 decoded bytes, strictly canonical Base64. Ordered chunks have an exact offset; identical chunk retries are safe, differing retries fail 409. Completion validates exact size, SHA-256 and content signature before publication. Downloads require authentication for every bounded chunk and recheck stored bytes against the immutable size/hash.

Limits: 20MiB/file, 256MiB/scope including staging, 100 files/target including staging, 1000 files/scope. Filenames are at most 240 UTF8 bytes, with no path separators, leading dot, control characters or bidi controls. Exact extension/MIME pairs permit PDF, DOC, DOCX, ODT, XLS, XLSX, ODS, TXT, CSV, RTF, PNG, JPG/JPEG. SVG, HTML and executable extensions are refused. Office ZIP containers require their expected entries, bounded entry count/uncompressed size/ratio, and no traversal/encrypted/macro/binary executable entries. ZipArchive is needed for ZIP office formats. Content validation identifies format; it is not an antivirus service. Documents are never executed, extracted or rendered by this server.

The existing shared-content acceptance applies to begin/chunk/complete. New downloads have no static/public URLs. Files are stored without an extension or user filename in private DATA_DIR/familyhub/attachments, using SHA-256(scopeId:id) and mode 0600. Every storage operation rejects symlink directory components. Final reads reject symlink files. Durable cleanup unlinks the exact hashed leaf, never traversing symlinks to a target.

## Moderation and lifecycle

The existing moderation.reportPreview/report methods accept targetType `table` or `attachment` and the table/file UUID. Reporting needs current read access and does not require content-policy acceptance. Table evidence contains a bounded 100-cell × 200-byte preview, full document hash, revision and affected attachment metadata. Attachment evidence contains immutable metadata plus current target context and its hash, with no document bytes. Administrators use the existing private review page; removal verifies the current revision/full hash/context. A changed table or attachment context requires a fresh report. Removing a table clears its lease and queues all its files. No additional native administrator privilege is exposed.

Task, table, inline project, scope and account removal queue physical file cleanup atomically with the corresponding SQL mutations. Closed project extraction copies complete task files to the new scope and removes private unfinished uploads. Account deletion removes personal/deleted-scope files, unfinished uploads, files of deleted tasks, associated private reports and bearer lease state; retained shared documents remain available with their author binding removed. Deletion previews bind the new metadata and expose counts. Shared table/file data retained by this policy is explicitly counted in the account preview.

The existing cli/reminders.php worker retries bounded deletion, removes staging older than 7 days and scans a bounded rotating page for untracked crash files older than 7 days. Completed live files never expire by age. SQL tombstones make files inaccessible even if physical unlink fails; cleanup queue entries remain for retry. File cleanup must run with the same private DATA_DIR. SQLite uses BEGIN IMMEDIATE; MySQL/MariaDB serialize document changes with the existing scope row lock.

## Backup and local verification

Back up **all database tables, every file below private DATA_DIR (including familyhub/attachments and familyhub/ideas), configuration, encryption keys, matching plugin source and worker setup**. Include document requests, chunk staging and deletion queues so retries and cleanup survive restoration. A metadata-only export cannot restore attachment bytes. Verify the complete database/files restore on an isolated instance. Existing schema 18 deployment/backup helpers are intentionally not relaxed to approve schema 19. MySQL DDL is not a transactional downgrade; preserve the verified pre-upgrade restore point. No hosting migration, upload, release artifact, public repository or store submission is performed by this source work.

Dedicated synthetic SQLite/MariaDB fixtures:

```sh
docker compose -f server/compose.documents-tests.yaml up -d
docker exec -u nginx familyhub-documents-tests-sqlite-1 php /familyhub-tests/documents-integration.php
docker exec -u nginx familyhub-documents-tests-mariadb-1 php /familyhub-tests/documents-integration.php
```

MySQL 8.4 uses a separate project and fresh volumes:

```sh
docker compose -p familyhub-documents-mysql -f server/compose.documents-tests.yaml -f server/compose.documents-mysql-tests.yaml up -d mariadb
docker exec -u nginx familyhub-documents-mysql-mariadb-1 php /familyhub-tests/documents-integration.php
```

The development fixture seeds synthetic memberships directly and does not send invitations or external email/push. It exercises HTTP transport, additive schema preservation, authorization, two-device leases, actual concurrent acquisition/save, idempotence, chunking, signatures/hash validation, storage failure rollback, symlink protection, quotas, moderation and durable lifecycle cleanup against real PDO databases.
