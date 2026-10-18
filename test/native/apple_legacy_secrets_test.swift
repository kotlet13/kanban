import Foundation
import Security

private enum ProofFailure: Error { case failed }
private func require(_ value: Bool) throws { if !value { throw ProofFailure.failed } }

private final class FakeStore: JivieLegacySecrets.Store {
  var rows: [[String: Any]] = []
  var copies = 0, updates = 0
  var failCopy = 0, failUpdate = 0
  var duplicate = false, wrongBytes = false
  init(count: Int = 5) {
    for (i, name) in JivieLegacySecrets.accounts.prefix(count).enumerated() {
      rows.append([kSecAttrAccount as String: name, kSecAttrService as String: "synthetic.service",
        kSecAttrAccessGroup as String: "synthetic.group", kSecAttrSynchronizable as String: false,
        kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked,
        kSecValueData as String: Data([UInt8(i), 0, 255]), kSecValuePersistentRef as String: Data([UInt8(i + 1)])])
    }
  }
  func copy(_ query: [String: Any]) -> (OSStatus, Any?) {
    copies += 1
    guard query[kSecAttrAccessible as String] == nil,
      query[kSecAttrSynchronizable as String] as? Bool == false,
      query[kSecClass as String] as? String == kSecClassGenericPassword as String,
      query[kSecUseDataProtectionKeychain as String] as? Bool == true else { return (errSecParam, nil) }
    if copies == failCopy { return (errSecInteractionNotAllowed, nil) }
    var found = rows.filter { row in
      row[kSecAttrAccount as String] as? String == query[kSecAttrAccount as String] as? String &&
      row[kSecAttrService as String] as? String == query[kSecAttrService as String] as? String &&
      (query[kSecAttrAccessGroup as String] == nil || row[kSecAttrAccessGroup as String] as? String == query[kSecAttrAccessGroup as String] as? String) &&
      (query[kSecValuePersistentRef as String] == nil || row[kSecValuePersistentRef as String] as? Data == query[kSecValuePersistentRef as String] as? Data)
    }
    if found.isEmpty { return (errSecItemNotFound, nil) }
    if duplicate { found.append(found[0]) }
    if wrongBytes && updates > 0 {
      found[0][kSecValueData as String] = Data([99])
    }
    return (errSecSuccess, found)
  }
  func update(_ query: [String: Any], _ attributes: [String: Any]) -> OSStatus {
    updates += 1
    guard attributes.count == 1, attributes[kSecAttrAccessible as String] as? String == JivieLegacySecrets.target,
      query[kSecAttrAccessGroup as String] as? String == "synthetic.group",
      let index = rows.firstIndex(where: { $0[kSecValuePersistentRef as String] as? Data == query[kSecValuePersistentRef as String] as? Data }) else { return errSecParam }
    if updates == failUpdate { return errSecInteractionNotAllowed }
    rows[index][kSecAttrAccessible as String] = JivieLegacySecrets.target
    return errSecSuccess
  }
}

private func mustFail(_ body: () throws -> Void) throws {
  do { try body() } catch is JivieLegacySecrets.Failure { return }
  throw ProofFailure.failed
}

private final class ActualStore: JivieLegacySecrets.Store {
  let system = JivieLegacySecrets.SystemStore()
  var updates = 0
  var copies = 0
  func copy(_ query: [String: Any]) -> (OSStatus, Any?) {
    copies += 1
    let result = system.copy(query)
    if result.0 != errSecSuccess && result.0 != errSecItemNotFound {
      print("JIVIE_NATIVE_SECRET_PROOF copy=\(copies) status=\(result.0)")
    } else if result.0 == errSecSuccess && !(result.1 is [[String: Any]]) {
      print("JIVIE_NATIVE_SECRET_PROOF copy=\(copies) result_type=\(type(of: result.1 as Any))")
    }
    return result
  }
  func update(_ query: [String: Any], _ attributes: [String: Any]) -> OSStatus {
    updates += 1
    return system.update(query, attributes)
  }
}

@main
struct AppleLegacySecretProof {
  static func main() {
    do {
      let args: [String: Any] = ["service": "synthetic.service", "accessGroup": "synthetic.group"]
      var cases = 0
      let complete = FakeStore()
      let original = complete.rows.map { $0[kSecValueData as String] as! Data }
      try JivieLegacySecrets.protect(args, store: complete)
      try require(complete.updates == 5 && complete.rows.allSatisfy { $0[kSecAttrAccessible as String] as? String == JivieLegacySecrets.target })
      try require(complete.rows.map { $0[kSecValueData as String] as! Data } == original)
      try JivieLegacySecrets.protect(args, store: complete)
      try require(complete.updates == 5); cases += 1

      let mixed = FakeStore(count: 3)
      mixed.rows[0][kSecAttrAccessible as String] = JivieLegacySecrets.target
      try JivieLegacySecrets.protect(["service": "synthetic.service", "accessGroup": NSNull()], store: mixed)
      try require(mixed.updates == 2 && mixed.rows.count == 3); cases += 1

      let partial = FakeStore(); partial.failUpdate = 3
      try mustFail { try JivieLegacySecrets.protect(args, store: partial) }
      try require(partial.rows.prefix(2).allSatisfy { $0[kSecAttrAccessible as String] as? String == JivieLegacySecrets.target })
      partial.failUpdate = 0
      try JivieLegacySecrets.protect(args, store: partial)
      try require(partial.updates == 6 && partial.rows.map { $0[kSecValueData as String] as! Data } == original); cases += 1

      let unknown = FakeStore(); unknown.rows[0][kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
      try mustFail { try JivieLegacySecrets.protect(args, store: unknown) }
      try require(unknown.updates == 0); cases += 1
      let duplicate = FakeStore(); duplicate.duplicate = true
      try mustFail { try JivieLegacySecrets.protect(args, store: duplicate) }
      try require(duplicate.updates == 0); cases += 1
      let denied = FakeStore(); denied.failCopy = 1
      try mustFail { try JivieLegacySecrets.protect(args, store: denied) }
      try require(denied.updates == 0); cases += 1
      let readback = FakeStore(); readback.failCopy = 2
      try mustFail { try JivieLegacySecrets.protect(args, store: readback) }
      try require(readback.updates == 1 && readback.rows.count == 5); cases += 1
      let mismatch = FakeStore(); mismatch.wrongBytes = true
      try mustFail { try JivieLegacySecrets.protect(args, store: mismatch) }
      try require(mismatch.updates == 1 && mismatch.rows.map { $0[kSecValueData as String] as! Data } == original); cases += 1
      let sync = FakeStore(); sync.rows[0][kSecAttrSynchronizable as String] = true
      try mustFail { try JivieLegacySecrets.protect(args, store: sync) }
      try require(sync.updates == 0); cases += 1
      try mustFail { try JivieLegacySecrets.protect(["service": "synthetic.service", "accounts": ["unrelated"]], store: FakeStore()) }; cases += 1

      var actual = false
      if CommandLine.arguments.count == 3 && CommandLine.arguments[1] == "--real-keychain" {
        let group = CommandLine.arguments[2]
        try require(group == "CXNM99632B.si.tripar.jivie.migrationproof20261018")
        let service = "si.tripar.jivie.synthetic.migration." + UUID().uuidString
        let actualStore = ActualStore()
        var seeded: [[String: Any]] = []
        defer { for query in seeded { SecItemDelete(query as CFDictionary) } }
        for (i, account) in JivieLegacySecrets.accounts.enumerated() {
          let identity: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: account, kSecAttrService as String: service,
            kSecAttrAccessGroup as String: group, kSecAttrSynchronizable as String: false,
            kSecUseDataProtectionKeychain as String: true]
          var add = identity
          add[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlocked
          add[kSecValueData as String] = Data([UInt8(i), 0, 255, 17])
          let seededStatus = SecItemAdd(add as CFDictionary, nil)
          if seededStatus != errSecSuccess {
            print("JIVIE_NATIVE_SECRET_PROOF seed_status=\(seededStatus)")
          }
          try require(seededStatus == errSecSuccess)
          seeded.append(identity)
        }
        // Nil configured group must discover and bind the actual returned group.
        try JivieLegacySecrets.protect(["service": service, "accessGroup": NSNull()], store: actualStore)
        try require(actualStore.updates == 5)
        try JivieLegacySecrets.protect(["service": service, "accessGroup": group], store: actualStore)
        try require(actualStore.updates == 5)
        actual = true
      }
      print("JIVIE_NATIVE_SECRET_PROOF pass=true cases=\(cases) actual_mac_keychain=\(actual) production_add_delete_calls=0")
    } catch let failure as JivieLegacySecrets.Failure {
      print("JIVIE_NATIVE_SECRET_PROOF pass=false failure=\(failure)")
      exit(1)
    } catch {
      print("JIVIE_NATIVE_SECRET_PROOF pass=false")
      exit(1)
    }
  }
}
