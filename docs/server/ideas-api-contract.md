# FamilyHub editable idea boards — record5/assets1

Source target: FamilyHub0.13.0/schema17; this is a protocol specification, not proof
of hosted deployment or a mobile-store release. `features.ideas`/`ideaAssets`
identify runtime availability; GD PNG/JPEG support is required for the visual
administrator review. Unavailable runtimes reject new board/image writes while
original synchronization remains available.

## Records and access

`sync5.pull/push/pushTaskWithCost` add type `idea`. Versions1–4 retain their original
canonical operation bodies, IDs and receipts. A scope containing boards requires5
before an older client reads it; other scopes retain their previous minimum.
Pull pages have bounded row/byte counts and truthful cursor/hasMore continuation.

The closed JSON board has `version:1`, `id`, `title`, null-or-valid `projectId`,
`width`, `height`, `elements`, `revision`, `createdAt`, `updatedAt`. The outer
record's server revision is authoritative; createdAt is immutable. Limits include
2000 elements,20 photos,50000 total points, at most768KiB raw UTF-8 board JSON
and1MiB PHP-default escaped board JSON. Pull pages cap their actual escaped
wire content around1.5MiB (at most20 rows), below the client2MiB transport limit.

Elements have `id`, `kind`, `x`, `y`, `width`, `height`, `rotation`, `color`,
`strokeWidth`, `text`, `points`, `parentImageId`, `asset`. Kinds: text/sticky/image/
stroke/rectangle/ellipse/line/arrow. Points are `{x,y}`, rotation radians (±2π),
color ARGB. Only images have immutable `{sha256,mime,size,width,height}` assets.
An attached element must name an image in this board; images cannot be nested.
Root coordinates and stroke widths are board pixels, attached coordinates and
stroke widths are normalized image-local units;
stroke points are relative to their element origin. Both transforms apply.
No SVG, executable markup, arbitrary image URLs or filesystem paths are accepted.

Boards may be direct household/organization/personal content or project children.
References must exist in the authorized scope; shared projects use their root.
Whole-space/project-only membership policies remain unchanged. Project extraction
copies the closed board/image graph; deletion rejects live board children.

## Private image API

Native bearer-authenticated HTTPS JSON always names `scopeId`, `boardId`, `sha256`.
A hash alone never grants access. Private files are in `DATA_DIR/familyhub/ideas`,
outside HTTP roots. Schema17 adds asset metadata/report-image reference tables.
A server backup must include all tables and the complete private data directory.

- `ideas.asset.begin`: add mime/size/width/height; normalized JPEG/PNG only,
  at most2MiB and4096×4096. Returns immutable metadata/completion/offset.
- `ideas.asset.chunk`: add offset and base64 `data` (alias `dataBase64`), at most
  256KiB decoded. Exact replay is safe; conflicting bytes/offsets are rejected.
- `ideas.asset.complete`: verifies total size, SHA256, MIME/dimensions and image
  structure before marking complete; replay is safe.
- `ideas.asset.get` (alias download): offset and optional limit up to256KiB;
  returns metadata, offset, data/dataBase64, total, done and complete.

Unpublished uploads are limited to their uploader. Referenced complete images are
available to authorized board readers. Other members may reuse that exact image
in this board, not alter its upload. Cross-board/scope guessing is denied. Staging
is bounded to20 photos per board/64MiB per uploader. Shared writes require existing
explicit policy1 acceptance; personal private synchronization remains exempt.
The board operation follows completed image uploads; chunks never notify.

## Notifications, conflicts and reports

Category `ideas`, events idea.created/updated/deleted: existing recipient access,
actor exclusion, grouping/deduplication and channel preferences apply. Missing
preferences use push/inApp-on, email/sound-off defaults. `inbox.open` accepts
`recordContractVersion:5`. Configured push/SMTP and OS permission remain separate.

Explicit Save commits a revision; local drafts do not publish. Client three-way
merge compares stable element IDs: independent edits merge; same-element or
delete/edit conflicts preserve both candidates. Rebase archives the old immutable
request and queues a new operation ID. Originals remain in encrypted recovery.

Moderation1 evidence includes the exact board and immutable image descriptors.
Fresh revision/previewHash checks apply at submission and admin review. Report
references retain private images. The admin sees a safe raster, readable escaped UTF-8 text notes, collapsed escaped full JSON
and authenticated original photos; annotations cannot hide originals. Anonymous
and expired-report image access is denied. Removal tombstones the exact board.
Existing resolved-report180-day cleanup releases evidence references; bounded
7-day orphan cleanup retains live board/report images. Confirmed account deletion
uses the existing durable private-file cleanup queue.

## Copies and offline use

Client schema9/content5 stores real verified photo bytes, local boards/space links,
drafts/bases and immutable operation history; older copy versions remain readable.
Shared archives stay quarantined until explicit resume or standalone conversion.
Standalone conversion creates new board/element IDs and copies images into the
new local workspace while retaining the encrypted original archive. Missing
images mark completeness; they are never silently omitted as a complete copy.
Files, photo decoding and copy sizes are bounded. Network loss does not delete
local content or masquerade as confirmed permission revocation.
