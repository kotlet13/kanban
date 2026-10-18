import Foundation
import Security
import LocalAuthentication

/// Only these pre-vault records may change accessibility. Values, account names,
/// service and access group are never rewritten, deleted or recreated.
struct JivieLegacySecrets {
  static let accounts = [
    "organizer_device_session_v1",
    "jivie_pending_invitation_v1",
    "organizer_remote_push_intent_v1",
    "organizer_remote_push_cleanup_v1",
    "jivie_account_deletion_receipts_v1",
  ]
  static let target = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly as String

  enum Failure: Error {
    case arguments, discovery, ambiguous, attributes, update, verification
  }

  protocol Store {
    func copy(_ query: [String: Any]) -> (OSStatus, Any?)
    func update(_ query: [String: Any], _ attributes: [String: Any]) -> OSStatus
  }

  struct SystemStore: Store {
    func copy(_ query: [String: Any]) -> (OSStatus, Any?) {
      var value: CFTypeRef?
      let status = SecItemCopyMatching(query as CFDictionary, &value)
      return (status, value)
    }
    func update(_ query: [String: Any], _ attributes: [String: Any]) -> OSStatus {
      SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
    }
  }

  private struct Item {
    let account: String, service: String, group: String, accessibility: String
    let bytes: Data, reference: Data
  }

  static func protect(_ arguments: Any?, store: Store = SystemStore()) throws {
    guard let args = arguments as? [String: Any],
      Set(args.keys).isSubset(of: ["service", "accessGroup"]),
      let service = args["service"] as? String, !service.isEmpty, service.utf8.count <= 1024 else {
      throw Failure.arguments
    }
    let group: String?
    if let raw = args["accessGroup"], !(raw is NSNull) {
      guard let value = raw as? String, !value.isEmpty, value.utf8.count <= 1024 else {
        throw Failure.arguments
      }
      group = value
    } else {
      group = nil
    }
    for account in accounts {
      let query = discovery(account: account, service: service, group: group)
      let found = try find(query, account: account, service: service, group: group, store: store)
      guard let before = found else { continue }
      // A persistent reference and the actual returned group bind the update
      // even when Flutter's configured group is nil. No accessibility filter
      // may hide an old item during discovery or readback.
      var exact = identity(account: account, service: service, group: before.group)
      exact[kSecValuePersistentRef as String] = before.reference
      if before.accessibility != target {
        guard store.update(exact, [kSecAttrAccessible as String: target]) == errSecSuccess else {
          throw Failure.update
        }
      }
      // macOS rejects a return-persistent-ref query that itself contains a
      // persistent reference. Rediscover the unique full identity instead,
      // then require exactly the original reference and unchanged bytes.
      let readback = discovery(account: account, service: service, group: before.group)
      guard let after = try find(readback, account: account, service: service,
                                 group: before.group, store: store),
        after.accessibility == target, after.reference == before.reference,
        after.bytes == before.bytes else {
        throw Failure.verification
      }
    }
  }

  private static func identity(account: String, service: String, group: String?) -> [String: Any] {
    var query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrAccount as String: account,
      kSecAttrService as String: service,
      kSecAttrSynchronizable as String: false,
    ]
    let authentication = LAContext()
    authentication.interactionNotAllowed = true
    query[kSecUseAuthenticationContext as String] = authentication
    if let group = group { query[kSecAttrAccessGroup as String] = group }
    #if os(macOS)
    query[kSecUseDataProtectionKeychain as String] = true
    #endif
    return query
  }

  private static func discovery(account: String, service: String, group: String?) -> [String: Any] {
    var query = identity(account: account, service: service, group: group)
    query[kSecMatchLimit as String] = kSecMatchLimitAll
    query[kSecReturnAttributes as String] = true
    query[kSecReturnData as String] = true
    query[kSecReturnPersistentRef as String] = true
    return query
  }

  private static func find(_ query: [String: Any], account: String, service: String,
                           group: String?, store: Store) throws -> Item? {
    let (status, raw) = store.copy(query)
    if status == errSecItemNotFound { return nil }
    guard status == errSecSuccess, let rows = raw as? [[String: Any]] else {
      throw Failure.discovery
    }
    guard rows.count == 1, let row = rows.first else { throw Failure.ambiguous }
    guard row[kSecAttrAccount as String] as? String == account,
      row[kSecAttrService as String] as? String == service,
      let actualGroup = row[kSecAttrAccessGroup as String] as? String, !actualGroup.isEmpty,
      group == nil || actualGroup == group,
      let sync = row[kSecAttrSynchronizable as String] as? Bool, sync == false,
      let accessible = row[kSecAttrAccessible as String] as? String,
      [kSecAttrAccessibleWhenUnlocked as String, target].contains(accessible),
      let bytes = row[kSecValueData as String] as? Data,
      let reference = row[kSecValuePersistentRef as String] as? Data, !reference.isEmpty else {
      throw Failure.attributes
    }
    return Item(account: account, service: service, group: actualGroup,
                accessibility: accessible, bytes: bytes, reference: reference)
  }
}
