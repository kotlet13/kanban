import Flutter
import UIKit
import UserNotifications
import firebase_messaging

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var remoteApnsTokenReceived = false
  private let privateFilePicker = JiviePrivateFilePicker()
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    UNUserNotificationCenter.current().delegate = self as? UNUserNotificationCenterDelegate
    FLTFirebaseMessagingPlugin.configureNotificationCenterDelegate()
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  override func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
    remoteApnsTokenReceived = true
    super.application(application, didRegisterForRemoteNotificationsWithDeviceToken: deviceToken)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "JiviePrivateFileIO") {
      let channel = FlutterMethodChannel(name: "jivie/private_file_io", binaryMessenger: registrar.messenger())
      channel.setMethodCallHandler { [weak self] call, result in
        guard let self = self else {
          result(FlutterError(code: "file_io", message: "File picker is unavailable", details: nil))
          return
        }
        self.privateFilePicker.handle(call, result: result)
      }
    }
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "JivieLocalVault") {
      let channel = FlutterMethodChannel(name: "jivie/local_vault", binaryMessenger: registrar.messenger())
      channel.setMethodCallHandler { call, result in
        if call.method == "protectLegacySecrets" {
          do {
            try JivieLegacySecrets.protect(call.arguments)
            result(true)
          } catch {
            result(FlutterError(code: "vault_secure_storage", message: "Legacy credential protection could not be verified", details: nil))
          }
          return
        }
        guard call.method == "protectLocalStorage" else {
          result(FlutterMethodNotImplemented)
          return
        }
        do {
          try protectJivieLocalStorage()
          result(true)
        } catch {
          result(FlutterError(code: "vault_backup_policy", message: "Local backup policy could not be applied", details: nil))
        }
      }
    }
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "VsakdanRemotePushReadiness") {
      let channel = FlutterMethodChannel(name: "vsakdan/remote_push_readiness", binaryMessenger: registrar.messenger())
      channel.setMethodCallHandler { [weak self] call, result in
        switch call.method {
        case "applicationId": result(Bundle.main.bundleIdentifier)
        case "registerApns": UIApplication.shared.registerForRemoteNotifications(); result(nil)
        case "hasApnsToken": result(self?.remoteApnsTokenReceived ?? false)
        default: result(FlutterMethodNotImplemented)
        }
      }
    }
  }
}

private func protectJivieLocalStorage() throws {
  let documents = try FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
  let vault = documents.appendingPathComponent("jivie_vault_v1", isDirectory: true)
  try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
  var paths = [vault]
  for name in ["organizer_shared_v1.sqlite", "organizer_shared_v1.sqlite-wal", "organizer_shared_v1.sqlite-shm", "organizer_shared_v1.sqlite-journal", "organizer_personal_v1.hive", "organizer_personal_v1.hivec"] {
    let url = documents.appendingPathComponent(name)
    if FileManager.default.fileExists(atPath: url.path) { paths.append(url) }
  }
  for var url in paths {
    var values = URLResourceValues()
    values.isExcludedFromBackup = true
    try url.setResourceValues(values)
    guard try url.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup == true else {
      throw NSError(domain: "JivieLocalVault", code: 1)
    }
  }
}

/// .open reads the provider's URL; unlike file_picker's import mode it creates
/// no app tmp/Inbox copy. Exports have one explicit, private, bounded staging
/// directory, cleaned on completion/cancel and at the next safe startup.
private final class JiviePrivateFilePicker: NSObject, UIDocumentPickerDelegate, UIAdaptivePresentationControllerDelegate {
  private var pending: FlutterResult?
  private var exporting = false
  private var limit = 0
  private var extensions: [String] = []
  private var staging: URL?
  private var generation = UUID()
  private var reading = false
  private weak var activePicker: UIDocumentPickerViewController?
  private var shareActivity: UIActivityViewController?

  private func safeName(_ name: String) -> Bool {
    return !name.isEmpty && name.count <= 255 && name != "." && name != ".." &&
      !name.unicodeScalars.contains { $0.value < 32 || $0.value == 127 || $0.value == 47 || $0.value == 92 }
  }

  private func exportRoot() throws -> URL {
    let caches = try FileManager.default.url(for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
    return caches.appendingPathComponent("jivie-private-exports-v1", isDirectory: true)
  }

  private func cleanExports() throws {
    let root = try exportRoot()
    guard FileManager.default.fileExists(atPath: root.path) else { return }
    guard try root.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink != true else {
      throw NSError(domain: "JiviePrivateFileIO", code: 1)
    }
    for url in try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isSymbolicLinkKey, .isDirectoryKey]) {
      let values = try url.resourceValues(forKeys: [.isSymbolicLinkKey, .isDirectoryKey])
      guard UUID(uuidString: url.lastPathComponent) != nil, values.isDirectory == true,
        values.isSymbolicLink != true else { continue }
      try FileManager.default.removeItem(at: url)
    }
  }

  private func recoveryShareRoot() throws -> URL {
    let caches = try FileManager.default.url(for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
    let root = caches.appendingPathComponent("jivie-recovery-shares-v1", isDirectory: true)
    if FileManager.default.fileExists(atPath: root.path) {
      guard try root.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink != true else {
        throw NSError(domain: "JiviePrivateFileIO", code: 1)
      }
    }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true,
      attributes: [.posixPermissions: 0o700, .protectionKey: FileProtectionType.complete])
    var values = URLResourceValues(); values.isExcludedFromBackup = true
    var protected = root; try protected.setResourceValues(values)
    try FileManager.default.setAttributes([.posixPermissions: 0o700,
      .protectionKey: FileProtectionType.complete], ofItemAtPath: root.path)
    guard try protected.resourceValues(forKeys: [.isExcludedFromBackupKey, .isSymbolicLinkKey]).isExcludedFromBackup == true,
      try protected.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink != true else {
      throw NSError(domain: "JiviePrivateFileIO", code: 1)
    }
    let expiry = Date().addingTimeInterval(-86400)
    for directory in try FileManager.default.contentsOfDirectory(at: root,
      includingPropertiesForKeys: [.isSymbolicLinkKey, .isDirectoryKey, .contentModificationDateKey]) {
      let attributes = try directory.resourceValues(forKeys: [.isSymbolicLinkKey, .isDirectoryKey, .contentModificationDateKey])
      guard UUID(uuidString: directory.lastPathComponent) != nil,
        attributes.isDirectory == true, attributes.isSymbolicLink != true else {
        throw NSError(domain: "JiviePrivateFileIO", code: 1)
      }
      let children = try FileManager.default.contentsOfDirectory(at: directory,
        includingPropertiesForKeys: [.isSymbolicLinkKey, .isRegularFileKey])
      guard children.count <= 1 else { throw NSError(domain: "JiviePrivateFileIO", code: 1) }
      for file in children {
        let flags = try file.resourceValues(forKeys: [.isSymbolicLinkKey, .isRegularFileKey])
        guard flags.isSymbolicLink != true, flags.isRegularFile == true,
          file.lastPathComponent.range(of: "^jivie-(installation|account)-[a-f0-9]{32}\\.jivie-recovery$", options: .regularExpression) != nil else {
          throw NSError(domain: "JiviePrivateFileIO", code: 1)
        }
      }
      if let modified = attributes.contentModificationDate, modified < expiry {
        try FileManager.default.removeItem(at: directory)
      }
    }
    return root
  }

  private func shareRecovery(_ args: [String: Any], result: @escaping FlutterResult) throws {
    guard let name = args["name"] as? String,
      name.range(of: "^jivie-(installation|account)-[a-f0-9]{32}\\.jivie-recovery$", options: .regularExpression) != nil,
      let bytes = args["bytes"] as? FlutterStandardTypedData,
      !bytes.data.isEmpty, bytes.data.count <= 65536 else {
      throw NSError(domain: "JiviePrivateFileIO", code: 2)
    }
    let root = try recoveryShareRoot()
    guard try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil).count < 16 else {
      throw NSError(domain: "JiviePrivateFileIO", code: 2)
    }
    let directory = root.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false,
      attributes: [.posixPermissions: 0o700, .protectionKey: FileProtectionType.complete])
    let file = directory.appendingPathComponent(name)
    try bytes.data.write(to: file, options: [.atomic, .completeFileProtection])
    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
    let handle = try FileHandle(forWritingTo: file); try handle.synchronize(); try handle.close()
    guard var presenter = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene })
      .flatMap({ $0.windows }).first(where: { $0.isKeyWindow })?.rootViewController else {
      throw NSError(domain: "JiviePrivateFileIO", code: 3)
    }
    while let presented = presenter.presentedViewController { presenter = presented }
    let activity = UIActivityViewController(activityItems: [file], applicationActivities: nil)
    activity.popoverPresentationController?.sourceView = presenter.view
    activity.popoverPresentationController?.sourceRect = CGRect(x: presenter.view.bounds.midX,
      y: presenter.view.bounds.midY, width: 1, height: 1)
    activity.completionWithItemsHandler = { [weak self, weak activity] _, completed, _, _ in
      guard let self = self, let activity = activity, self.shareActivity === activity else { return }
      self.shareActivity = nil
      let callback = self.pending; self.pending = nil
      if !completed { try? FileManager.default.removeItem(at: directory) }
      // Platform completion is not a verified external recovery copy. Retain
      // completed handoff staging for late receiver reads until safe expiry.
      callback?(completed ? "shareStarted" : "cancelled")
    }
    pending = result; shareActivity = activity
    presenter.present(activity, animated: true)
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard pending == nil else {
      result(FlutterError(code: "file_busy", message: "Another file operation is active", details: nil))
      return
    }
    do {
      if call.method == "legacyPickerRoots" {
        let documents = try FileManager.default.url(for: .documentDirectory,
          in: .userDomainMask, appropriateFor: nil, create: true)
        result(["iosTemporary": NSTemporaryDirectory(), "iosDocuments": documents.path]); return
      }
      _ = try recoveryShareRoot()
      if call.method == "shareRecovery" {
        guard let args = call.arguments as? [String: Any] else { throw NSError(domain: "JiviePrivateFileIO", code: 2) }
        try shareRecovery(args, result: result); return
      }
      if let directory = staging {
        try FileManager.default.removeItem(at: directory)
        staging = nil
      }
      try cleanExports()
      if call.method == "cleanup" { result(true); return }
      generation = UUID()
      reading = false
      guard let args = call.arguments as? [String: Any] else { throw NSError(domain: "JiviePrivateFileIO", code: 2) }
      let picker: UIDocumentPickerViewController
      if call.method == "pick" {
        guard let allowed = args["extensions"] as? [String], let maxBytes = args["maxBytes"] as? Int,
          !allowed.isEmpty, allowed.count <= 32, (1...201326592).contains(maxBytes),
          allowed.allSatisfy({ $0.range(of: "^[a-z0-9-]{1,20}$", options: .regularExpression) != nil }) else {
          throw NSError(domain: "JiviePrivateFileIO", code: 2)
        }
        exporting = false; extensions = allowed; limit = maxBytes
        picker = UIDocumentPickerViewController(documentTypes: ["public.item"], in: .open)
      } else if call.method == "save" {
        guard let name = args["name"] as? String, safeName(name),
          let bytes = args["bytes"] as? FlutterStandardTypedData, bytes.data.count <= 201326592 else {
          throw NSError(domain: "JiviePrivateFileIO", code: 2)
        }
        let root = try exportRoot()
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        var values = URLResourceValues(); values.isExcludedFromBackup = true
        var protectedRoot = root; try protectedRoot.setResourceValues(values)
        try FileManager.default.setAttributes([.posixPermissions: 0o700, .protectionKey: FileProtectionType.complete], ofItemAtPath: root.path)
        guard try protectedRoot.resourceValues(forKeys: [.isExcludedFromBackupKey, .isSymbolicLinkKey]).isExcludedFromBackup == true,
          try protectedRoot.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink != true else {
          throw NSError(domain: "JiviePrivateFileIO", code: 1)
        }
        let directory = root.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700, .protectionKey: FileProtectionType.complete])
        staging = directory
        let file = directory.appendingPathComponent(name)
        try bytes.data.write(to: file, options: [.atomic, .completeFileProtection])
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
        let handle = try FileHandle(forWritingTo: file); try handle.synchronize(); try handle.close()
        exporting = true
        picker = UIDocumentPickerViewController(url: file, in: .exportToService)
      } else { result(FlutterMethodNotImplemented); return }
      guard var presenter = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene })
        .flatMap({ $0.windows }).first(where: { $0.isKeyWindow })?.rootViewController else {
        throw NSError(domain: "JiviePrivateFileIO", code: 3)
      }
      while let presented = presenter.presentedViewController { presenter = presented }
      pending = result
      activePicker = picker
      picker.allowsMultipleSelection = false
      picker.delegate = self
      picker.presentationController?.delegate = self
      presenter.present(picker, animated: true) { picker.presentationController?.delegate = self }
    } catch {
      finish(nil, error: "The file operation could not start", fallback: result)
    }
  }

  func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
    guard controller === activePicker, pending != nil, !reading else { return }
    let request = generation
    if exporting { finish("saved", expected: request); return }
    reading = true
    guard urls.count == 1, let url = urls.first, safeName(url.lastPathComponent),
      extensions.contains(url.pathExtension.lowercased()) else { finish(nil, error: "Invalid selected file"); return }
    let maxBytes = limit
    DispatchQueue.global(qos: .userInitiated).async {
      let scoped = url.startAccessingSecurityScopedResource()
      defer { if scoped { url.stopAccessingSecurityScopedResource() } }
      do {
        guard let input = InputStream(url: url) else { throw NSError(domain: "JiviePrivateFileIO", code: 4) }
        input.open(); defer { input.close() }
        var output = Data(), buffer = [UInt8](repeating: 0, count: 65536)
        while true {
          let capacity = buffer.count
          let read = input.read(&buffer, maxLength: capacity)
          if read < 0 { throw NSError(domain: "JiviePrivateFileIO", code: 4) }
          if read == 0 { break }
          guard output.count + read <= maxBytes else { throw NSError(domain: "JiviePrivateFileIO", code: 5) }
          output.append(contentsOf: buffer.prefix(read))
        }
        DispatchQueue.main.async { self.finish(["name": url.lastPathComponent, "bytes": FlutterStandardTypedData(bytes: output)], expected: request) }
      } catch {
        DispatchQueue.main.async { self.finish(nil, error: "The selected file could not be read", expected: request) }
      }
    }
  }

  func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
    guard controller === activePicker, !reading else { return }
    finish(exporting ? "cancelled" : nil, expected: generation)
  }
  func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
    guard presentationController.presentedViewController === activePicker, !reading else { return }
    finish(exporting ? "cancelled" : nil, expected: generation)
  }

  private func finish(_ value: Any?, error: String? = nil, fallback: FlutterResult? = nil, expected: UUID? = nil) {
    if let request = expected, request != generation { return }
    let callback = pending ?? fallback
    pending = nil
    activePicker = nil
    reading = false
    if let directory = staging {
      do { try FileManager.default.removeItem(at: directory); staging = nil }
      catch { callback?(FlutterError(code: "file_cleanup", message: "Private export cleanup is incomplete", details: nil)); return }
    }
    if let message = error { callback?(FlutterError(code: "file_io", message: message, details: nil)) }
    else { callback?(value) }
  }
}
