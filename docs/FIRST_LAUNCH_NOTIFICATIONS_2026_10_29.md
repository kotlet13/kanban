# First-launch notification permission

The user confirmed that public1.11.2 now saves the recovery file successfully and creates a household. This is a user-reported device PASS, not an independent end-to-end synchronization or recovery test.

The next requested change adds the system notification permission request to the first unlocked mobile app launch. It runs after the first frame, works without an account, and waits for foreground activity. Existing granted permission is not requested again. A persistent, non-sensitive installation guide flag prevents automatic repeat prompts after denial, dismissal, restart or request failure; manual notification settings remain available. Existing installations without the flag also get one opportunity on the first launch after this update, subject to the OS permission policy. Desktop and web do not request automatically.

The wrapper lives inside JivieApp, hence after LocalVaultBootstrap's safety gate. It reuses the initialized local notification adapter. It does not change account subscriptions, reminder preferences or remote push opt-in, does not contact the server, and does not override operating-system permission decisions. OS permission alone is not proof of remote push registration/delivery. No manifest permission, encryption, data format or dependency changes.

Six new local widget controls PASS: denied permission and remount, already granted, background initialization and resume, plugin failure without UI blockage/repeated prompting, iOS routing and desktop exclusion. Attempt1 failed to compile because the fixture awaited a void lifecycle callback. Attempt2 assertions reached completion but all six failed Flutter's platform-override cleanup invariant. Fixture cleanup was moved inside the test body; attempt3 passed all six. No fourth run and no prior successful business suite rerun. Targeted analysis reports no issues. Evidence: build/qa/first-launch-notifications-20261029.

The tests use the real adapter with a simulated platform scheduler. Native dialog appearance and delivery have not been tested on a phone in this task. No release build, Google Play submission, phone or production-server operations. This change is prepared for the next release; it is not included in already published1.11.2.

Android platform behavior was checked against the official permission documentation: https://developer.android.com/develop/ui/compose/notifications/notification-permission . Android13+ fresh installs require notification permission; older Android versions may not show a runtime question.
