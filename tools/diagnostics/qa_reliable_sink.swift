import Foundation
import CoreFoundation

// Shared verbatim by the isolated fixture and the QA application's native bridge.
final class QAReliableSink {
  private var handle: FileHandle?
  private(set) var run = ""
  private(set) var unavailable = "notInitialized"
  private var bytes = 0, serial = 0
  private var counts: [String: Int] = [:], sizes: [String: Int] = [:]
  private var drops: [String: Int] = [:]
  private var accepted = Set<Int>()
  private var ackProved = false
  private let limits = ["error": (128, 524288), "work": (1024, 327680),
    "sync": (128, 65536), "request": (1024, 655360), "ui": (128, 65536),
    "completion": (64, 16384)]
  private let maxBytes = 2 * 1024 * 1024

  init(root: URL, app: String) {
    do {
      let fm = FileManager.default
      for candidate in [root.deletingLastPathComponent(), root] {
        if fm.fileExists(atPath: candidate.path),
           try candidate.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink == true {
          throw NSError(domain: "QASink", code: 1)
        }
      }
      try fm.createDirectory(at: root, withIntermediateDirectories: true,
                             attributes: [.posixPermissions: 0o700])
      let old = try fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
        .filter { $0.lastPathComponent.hasPrefix("run-") && $0.pathExtension == "ndjson" }
      guard old.count < 2 else { unavailable = "runLimit"; return }
      run = "\(Int(Date().timeIntervalSince1970 * 1000))-\(ProcessInfo.processInfo.processIdentifier)"
      let file = root.appendingPathComponent("run-\(run).ndjson")
      guard !fm.fileExists(atPath: file.path),
            fm.createFile(atPath: file.path, contents: nil,
                          attributes: [.posixPermissions: 0o600]) else {
        unavailable = "fileExists"; return
      }
      handle = try FileHandle(forWritingTo: file)
      unavailable = "none"
      guard append("health", ["event": "nativeReady", "app": app]) else { return }
    } catch { unavailable = "fileUnavailable"; handle = nil }
  }

  private func append(_ category: String, _ data: [String: Any], dartSeq: Int? = nil) -> Bool {
    guard let output = handle else { return false }
    serial += 1
    let envelope: [String: Any] = ["v": 1, "run": run, "n": serial,
      "atMs": Int(Date().timeIntervalSince1970 * 1000), "kind": category,
      "dartSeq": dartSeq as Any? ?? NSNull(), "data": data]
    do {
      var encoded = try JSONSerialization.data(withJSONObject: envelope, options: [.sortedKeys])
      encoded.append(10)
      guard bytes + encoded.count <= maxBytes else { unavailable = "byteLimit"; return false }
      try output.write(contentsOf: encoded)
      // Health markers flush the small diagnostic file. Ordinary events only
      // append, so per-request diagnostics do not force a main-thread fsync.
      if category == "health" { try output.synchronize() }
      bytes += encoded.count
      return true
    } catch { unavailable = "writeFailed"; handle = nil; return false }
  }

  private func int(_ value: Any?, _ max: Int = 1000000000) -> Bool {
    guard let number = value as? NSNumber,
      CFGetTypeID(number) != CFBooleanGetTypeID() else { return false }
    let d = number.doubleValue
    return d >= 0 && d <= Double(max) && d.rounded() == d
  }
  private func token(_ value: Any?, _ max: Int = 100) -> Bool {
    guard let text = value as? String, !text.isEmpty, text.utf8.count <= max else { return false }
    return text.range(of: "^[A-Za-z0-9_.-]+$", options: .regularExpression) != nil
  }
  private func valid(_ category: String, _ data: [String: Any]) -> Bool {
    let keys = Set(data.keys)
    switch category {
    case "work":
      return keys == Set(["event", "kind", "job", "priority", "op", "active", "pending", "waitMs"])
        && token(data["event"]) && token(data["kind"]) && int(data["job"])
        && token(data["priority"]) && token(data["op"])
        && int(data["active"], 64) && int(data["pending"], 64) && int(data["waitMs"])
    case "sync":
      return keys == Set(["event", "scopes", "content", "finance", "fallback"])
        && token(data["event"]) && int(data["scopes"], 10000)
        && int(data["content"], 10000) && int(data["finance"], 10000)
        && (data["fallback"] is NSNull || token(data["fallback"]))
    case "request":
      guard keys == Set(["op", "site", "kind", "job", "frames"]),
        token(data["op"]), token(data["site"]), token(data["kind"]), int(data["job"]),
        let frames = data["frames"] as? [String], frames.count <= 4 else { return false }
      return frames.allSatisfy { $0.utf8.count <= 180 &&
        $0.range(of: "^organizer/[A-Za-z0-9_./]+\\.dart:[0-9]+:[0-9]+$", options: .regularExpression) != nil }
    case "ui":
      return keys == Set(["event"]) && token(data["event"])
    case "completion":
      return keys == Set(["sequence", "unresolved", "error", "retry"])
        && int(data["sequence"]) && data["unresolved"] as? Bool != nil
        && data["retry"] as? Bool != nil
        && (data["error"] is NSNull || token(data["error"]))
    case "error":
      guard keys == Set(["phase", "code", "frames"]), token(data["phase"]),
        token(data["code"]), let frames = data["frames"] as? [String], frames.count <= 10 else { return false }
      return frames.allSatisfy { $0.utf8.count <= 400 && $0.contains("package:kanban/") }
    default: return false
    }
  }

  func event(_ args: Any?) -> [String: Any] {
    guard let args = args as? [String: Any], Set(args.keys) == Set(["v", "seq", "kind", "data"]),
      args["v"] as? Int == 1, int(args["seq"]), let seq = args["seq"] as? Int,
      let category = args["kind"] as? String, let data = args["data"] as? [String: Any],
      let limit = limits[category], valid(category, data) else {
      return ["v": 1, "accepted": false, "reason": "invalidSchema"]
    }
    let size = (try? JSONSerialization.data(withJSONObject: data).count) ?? maxBytes
    if counts[category, default: 0] >= limit.0 || sizes[category, default: 0] + size > limit.1 {
      drops[category, default: 0] += 1
      if drops[category] == 1 {
        _ = append("health", ["event": "categoryLimit", "category": category, "dropped": 1])
      }
      return ["v": 1, "seq": seq, "accepted": false, "reason": "categoryLimit", "run": run]
    }
    guard append(category, data, dartSeq: seq) else {
      return ["v": 1, "seq": seq, "accepted": false, "reason": unavailable, "run": run]
    }
    counts[category, default: 0] += 1
    sizes[category, default: 0] += size
    if accepted.count < 4096 { accepted.insert(seq) }
    return ["v": 1, "seq": seq, "accepted": true, "run": run]
  }

  // Sent once by Dart only after it has checked the event acknowledgement.
  // This is not acknowledged recursively and cannot carry a path or payload.
  func acknowledge(_ args: Any?) {
    guard !ackProved, let value = args as? [String: Any],
      Set(value.keys) == Set(["v", "seq", "run"]), value["v"] as? Int == 1,
      let seq = value["seq"] as? Int, accepted.contains(seq), value["run"] as? String == run else { return }
    ackProved = append("health", ["event": "dartValidatedAck", "seq": seq])
  }
}
