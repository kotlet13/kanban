# Optional Firebase mobile client configuration

Firebase is optional: absent configuration builds and runs without Dart Firebase initialization, token requests or permission prompts. When Android native XML is present, FirebaseInitProvider initializes its local default app before Dart; messaging auto-init and analytics remain disabled until the appropriate opt-in. Only Android/iOS support remote push; web/macOS remain usable without it. No Analytics, Firebase Auth, Firestore or Cloud Functions are included.

After the owner creates a Firebase Spark project, registers the actual mobile application identifiers and downloads their **mobile client** configuration files:

```sh
python3 tools/firebase/configure_client.py --android /path/google-services.json --ios /path/GoogleService-Info.plist
flutter build apk --dart-define-from-file=.firebase/client.json
flutter build ios --dart-define-from-file=.firebase/client.json
```

Either input may be omitted. The utility checks both files use the same project/sender, validates app ID/key formats and extracts authoritative identifiers from Android Gradle and iOS Runner build configurations; inconsistent/flavoured/unresolved identifiers are rejected. The current IDs are Android `com.takndev.kanbanconnect` and iOS `com.example.kanban`. Identifier/signing changes require a separate owner decision. `--output-dir /tmp/fixture-root` writes into an isolated root for tests. Existing output files are staged and replaced after input validation, with rollback on write failure. An iOS-only run refuses to overwrite client JSON if generated Android XML already exists: supply both inputs, or deliberately remove that XML before switching to an iOS-only configuration. No network request or secret logging occurs.

Outputs:

- `.firebase/client.json`: public client identifiers used by explicit Dart `FirebaseOptions`.
- `android/app/src/main/res/values/firebase_config.xml`: public native identifiers needed by FirebaseInitProvider/MessagingService before Dart starts in a terminated Android process. This avoids a mandatory Google Services Gradle plugin/file. The manifest disables messaging auto-init and analytics collection by default.

Both outputs are ignored by Git. Do not pass a service-account JSON, APNs `.p8` key or server encryption key into the client. The JSON uses `FIREBASE_PROJECT_ID`, `FIREBASE_SENDER_ID`, `FIREBASE_ANDROID_API_KEY`, `FIREBASE_ANDROID_APP_ID`, `FIREBASE_ANDROID_PACKAGE`, `FIREBASE_IOS_API_KEY`, `FIREBASE_IOS_APP_ID`, `FIREBASE_IOS_BUNDLE_ID`. iOS uses explicit Dart options after cached identity/opt-in initialization, rather than a bundled GoogleService plist. APNs can display the generic OS notification before Dart; the pinned Flutter messaging plugin retains launch metadata for `getInitialMessage`.

A configured build is insufficient to enable delivery. The user must sign in, use a server configured for the **same** Firebase project, explicitly opt this device in, and allow OS notifications. iOS additionally needs the owner's signing team, push-capable bundle/profile, APNs key in Firebase and the optional `ios/Runner/RemotePush.entitlements` assigned to the selected configuration with `APNS_ENVIRONMENT=development` or `production`. That template is not automatically enabled or signed. The UI waits for an APNs token before requesting/registering an FCM token. Token renewal is enabled only after opt-in; opt-out/account switch/signout stop renewal and delete the SDK token.

The safe background handler performs no database/login/navigation work. Foreground delivery refreshes the persisted inbox without showing another notification. Initial/opened pushes carry only recipient identities plus a notification ID; the app resolves the persisted group and current rights before navigating. A force-quit application may need reopening before delivery resumes, as documented by Firebase.

No real Firebase project or external delivery is verified by these preparation tests. Follow `docs/NOTIFICATION_SETUP.md` for server/APNs setup and eventual physical-device proof.

References: [Flutter FCM setup](https://firebase.google.com/docs/cloud-messaging/flutter/get-started), [receive messages](https://firebase.google.com/docs/cloud-messaging/flutter/receive-messages), [pinned messaging package](https://pub.dev/packages/firebase_messaging/versions/16.7.0).
