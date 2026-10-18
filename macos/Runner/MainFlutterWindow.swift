import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    self.contentViewController = flutterViewController
    self.contentMinSize = NSSize(width: 640, height: 480)
    self.setContentSize(NSSize(width: 1280, height: 800))
    self.center()

    RegisterGeneratedPlugins(registry: flutterViewController)
    let vaultChannel = FlutterMethodChannel(name: "jivie/local_vault", binaryMessenger: flutterViewController.engine.binaryMessenger)
    vaultChannel.setMethodCallHandler { call, result in
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

    super.awakeFromNib()
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
