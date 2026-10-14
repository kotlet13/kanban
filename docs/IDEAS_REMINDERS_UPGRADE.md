# Deadline reminders and Idea controls — 14 October 2026

Implemented upgrade notes 2, 11 and 12, including the archived Idea projection from note 13. This document describes local source and isolated development evidence. It does not assert a hosted migration, store release, installation or physical notification delivery.

## Reminder semantics

The existing absolute remote reminder JSON, request identities, hashes and receipts are unchanged. A new explicitly chosen task reminder can add `scheduleMode: deadline` and `offsetMinutes: 0 | 60 | 1440`. The server stores both fields in schema18 and derives its UTC instant from the current canonical task deadline. It does not trust the client's cached instant. These are exact duration offsets, including across daylight-saving changes; the date/time shown is local to the device.

Only a pending reminder follows source deadline changes. Changing the title leaves it alone. Completion, source deletion or removal of the deadline cancels it; reopening a task does not recreate it. Delivered reminders remain delivered when the deadline moves. An explicit later Save is a new user choice, rather than automatic resurrection. The existing due worker, account-specific access checks and deduplicated notification writer remain responsible for delivery. Source sync reschedules server reminders without issuing a second `reminders.put`. A pending local command retains its exact original body and request ID while its local preview follows the current source.

Device-only tasks expose the same deadline choices and cancellation without an account. Their explicit preferences are durable device metadata, fenced by task creation identity, and included in encrypted content6 backups. Effective alarms resolve these offsets before device snoozes; early task reminders also materialize the normal durable center/read record. Preferences follow a pending deadline. Moving a deadline after the previous alert time suppresses another automatic alert. Completion/removal leaves a cancelled preference so reinstating the task/deadline cannot silently re-enable it. Existing tasks without an explicit choice retain the previous automatic deadline reminder. Mapped private tasks route the control to their existing account-specific remote source.

## Ideas

Two touch pointers pan and zoom the viewport while selecting, drawing or erasing. A second pointer discards unfinished editing previews and does not commit strokes or element moves. Erasing is buffered until the one-pointer edit completes. After both fingers lift, the selected one-finger tool remains usable. Hand mode and read-only viewing retain their existing InteractiveViewer gestures. These gestures alter the view only, not board JSON.

Selected text/sticky elements have separate increase/decrease text-size controls. Font size is persisted independently of box dimensions and viewport scale, participates in undo/redo and the existing three-way element merge, and applies to image annotations too. Root units are board pixels; annotation units are normalized to their parent photo, preserving the existing geometry model. Valid ranges are 6–300 for root text and .005–2 for image-local text. Existing defaults remain 22 and .065.

Every editable Idea card has a three-dot menu for archiving/restoring and deletion. Deletion identifies the board and requires confirmation. Active and archived boards are separated; the Archived expansion is collapsed by default. All-spaces actions retain an explicit local/shared source, with revision, source, account and permission guards. Local archived spaces remain readable and reject writes; archived spaces are excluded from the All projection. Viewer cards have no lifecycle actions.

## Version compatibility

Unextended boards retain exact version1 JSON. Extended boards use version2, add a boolean `archived`, and include numeric `fontSize` in every element. Once an extended board has been saved it retains version2 even if restored/defaulted. Clients read both versions and reject unexpected keys. The server rejects a version2 board written through record5 and rejects downgrading a stored version2 board.

`sync6.push/pull` negotiates record6 for extended Ideas, garden document3 and optional inline-project archive state. Existing record1–5 operations retain their body, operation ID and original contract; transporting a queued old operation through sync6 does not rewrite its business payload or replay hash. Upgraded scopes advertise the required contract and older pulls/writes are refused. Recovery and private sync negotiate the same transport. The rich page budget and bounded page size remain.

SQLite schema10 is a compatibility fence for the new JSON contracts; there are no new SQLite columns or rewrites of old records/outbox bodies. Portable encrypted content6 preserves older supported documents and adds `localTaskReminderPreferences`. It carries extended Idea boards/drafts/private image bytes and immutable operation history. Content5 remains readable; extended boards require content6.

## Isolated verification

- Existing Idea/reminder UI and repository targets: **46 PASS**.
- Existing portable-backup validation targets: **11 PASS**.
- New reminder repository/UI, Idea archive/font UI and actual canvas gesture targets with existing reminder coverage: **50 PASS**. Gesture coverage includes hand/read-only modes at 360, 800 and 1280 widths; selection, pen and eraser pinch; interrupted stroke cancellation and resumed drawing.
- New domain/SQLite/encrypted backup targets: **6 PASS**, including the explicit All-spaces source/revision/archive lifecycle guard.
- Fresh isolated FamilyHub HTTP fixture: **27 PASS** in `server/tests/relative-reminder-ideas6-integration.php`. This checks canonical relative derivation, replay/account isolation, pending moves, completion/deadline removal, non-resurrection/no duplicate delivery, exact Idea font/archive HTTP roundtrip, old operation replay after scope6 upgrade, old pull refusal and rejected invalid font size. Additional cases verify inline-project archive cancels pending reminders, denies stale child writes/deletes/replays and new reminders, and restoring the project does not resurrect cancelled reminders.
- Actual per-Idea menu/font, local relative dialog and archived-parent read-only interaction: **4 PASS** in `upgrade_ideas_ui_test.dart`.
- Screenshots are saved by `test/organizer/ui/upgrade_ideas_ui_test.dart` under ignored `build/qa/upgrade-ideas/`: menu, collapsed archive, selected text-size controls and local deadline dialog.

Actual Android/iOS/macOS installations and system notifications require the root release/physical validation work. Linux and Windows native builds are deferred by the user. No server deployment, live account/data action or Git commit/push was performed by this implementation subagent.

## Space navigation and active archives (note 14)

The default picker lists Personal, device spaces, shared households and organizations. Project scopes are in the separate **Shared with me** list, with search for long lists. A project-only grant names a readable parent only when that parent is actually authorized; otherwise it identifies a directly shared project. Archived device/shared spaces and projects are in collapsed sections. The closed picker retains the current exact project or revoked selection. Selecting after a dialog verifies current account/device identity and access. iOS opens the panel in a SafeArea fullscreen-dialog page with the existing platform transition; Android and macOS retain the dialog.

Active All/Utrip/task/calendar/reminder projections exclude archived device spaces and inline-project tasks/events. Normal task and calendar pages apply the same inline-project filter. Projects retain a separate collapsed archive section, including the Home category filter. Posted financial facts and stored source records remain intact. Ordinary local task rows expose the deadline-reminder button.

The separate, explicitly requested **Export unsent work** JSON contains this device/account's immutable generic and financial candidates even after a confirmed read-access revocation. It adds only locally changed Idea draft payloads and their referenced verified image bytes (recovery schema2 when needed). It never contains canonical records, remote/base snapshots or permission grants. A Settings **Open unsent work** action reopens that file for read-only inspection, image display and copying; its decoder/view has no repository, importer or delivery capability. Normal encrypted portable backups continue to exclude revoked/deleted/unreadable remote scopes and associated drafts/assets. Prepared backup release invalidates when read/deletion rights change.

Navigation evidence: existing picker/navigation suites **75 PASS / 1 opt-in screenshot skip**; initial active/archive/hierarchy targets **11 PASS**; affected widget/release/planning/All/Utrip/repository regression targets **55 PASS**. Final picker baseline **84 PASS / 1 opt-in skip**, including iOS fullscreen and narrow 2× stacked tabs; final recovery/iOS/collaboration/portable targets **43 PASS**; separate revoke/restart plus authorized portable-export separation regression **1 PASS**. UI and data recovery verifies no remote send and corrupt-media rejection. Navigation screenshots are in ignored `build/qa/upgrade-navigation/`; phone sizes 320/390 and macOS width1280 are exercised at 1×/2× text. Recovery/active-projection/Idea UI targets **7 PASS**, final Idea parent-guard suite **26 PASS** plus explicit archived-parent UI coverage in the four-case suite. Full analysis has no new findings (10 existing release-tool infos).
