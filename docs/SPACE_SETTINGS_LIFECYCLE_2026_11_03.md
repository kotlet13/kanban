# Space lifecycle actions in settings — 3 November 2026

Archive/restore and permanent deletion now appear as explicit buttons at the bottom of a selected space’s settings. Both shared and device-local spaces use the same placement and localized labels. These controls no longer appear in shared-space member or module headings. Synchronization indicators remain visible. Project-row menus and project-detail contextual actions remain available.

This change only relocates the actions. Shared actions still resolve the current scope and its management/deletion capability, and invoke the existing archive or counted deletion flow. Deletion still requires the existing named preview, counts, blocker checks and explicit confirmation, with session/permission revalidation. Local actions resolve the current catalog entry; the default personal space and linked entries have no local lifecycle controls. No lifecycle repository, crypto guard, persistence or network behavior was changed in this UI work.

The reported household deletion failure is a separate core investigation. These UI tests do not establish that a real encrypted household can be deleted successfully.

## Targeted verification

New file: `test/organizer/ui/space_settings_lifecycle_20261103_test.dart`.

- 15 new widget controls passed: settings placement and SL/EN labels at 320/390 px; archive dispatch; counted delete/cancel/confirm; financial blocker; account change while preview is pending; member/viewer/capability restrictions; shared restore; local actions with preview/confirmation; default/linked local exclusions; task/finance/shopping headings with sync retained; organization heading without its lifecycle popup while project-row archive remains available.
- First run: 14 passed, one local fixture failed. Its isolated settings page had not initialized the organizer snapshot, so the existing `PersonalWorkspaceGuard` correctly closed the dialog. The real shell initializes that snapshot before settings. The fixture was corrected to do the same; only this failed case was rerun and passed on attempt 2. No product guard was changed to obtain the pass.
- Obsolete header-menu expectations in `scope_lifecycle_menu_test.dart`, `sharing_workspace_cleanup_test.dart` and `ux_navigation_20261027_test.dart` were aligned with the new placement. The former counted menu test now explicitly exercises project context. Those historical suites were not rerun.
- Changed-file static analysis: zero errors/warnings; one existing brace-style info in `sharing_members.dart`. Diff whitespace check passed.
- Independent source review found no new permission or confirmation weakening.

Evidence: `build/qa/space-settings-lifecycle-20261103/ui-r1.log` and `ui-local-r2.log`. Widgets use synthetic controllers and a real empty in-memory schema for infrastructure; this is not a native phone or HTTP deletion test. No production or phone actions were taken.
