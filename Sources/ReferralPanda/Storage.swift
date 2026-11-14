import Foundation

/// Where the SDK keeps its small amount of state: an install id, events waiting to be sent,
/// and the last referral summary and screens for offline use.
public protocol ReferralPandaStorage: Sendable {
  func string(forKey key: String) -> String?
  func set(_ value: String, forKey key: String)
  func removeValue(forKey key: String)
}

/// Keeps everything in memory. For tests, and for apps that must not write to disk.
public final class MemoryStorage: ReferralPandaStorage, @unchecked Sendable {
  private let lock = NSLock()
  private var values: [String: String] = [:]
  public init() {}

  public func string(forKey key: String) -> String? {
    lock.lock()
    defer { lock.unlock() }
    return values[key]
  }
  public func set(_ value: String, forKey key: String) {
    lock.lock()
    defer { lock.unlock() }
    values[key] = value
  }
  public func removeValue(forKey key: String) {
    lock.lock()
    defer { lock.unlock() }
    values[key] = nil
  }
}

/// The default: the app's own UserDefaults, in a suite of its own.
public final class UserDefaultsStorage: ReferralPandaStorage, @unchecked Sendable {
  // UserDefaults is safe to use from any thread.
  private let defaults: UserDefaults
  public init(suiteName: String = "com.referralpanda.sdk") {
    defaults = UserDefaults(suiteName: suiteName) ?? .standard
  }
  public func string(forKey key: String) -> String? { defaults.string(forKey: key) }
  public func set(_ value: String, forKey key: String) { defaults.set(value, forKey: key) }
  public func removeValue(forKey key: String) { defaults.removeObject(forKey: key) }
}

/// JSON values under one prefix. Storage problems never break the app: a failed read is
/// "nothing stored", a failed write is dropped.
struct Store: Sendable {
  let storage: ReferralPandaStorage
  let prefix: String

  func get<T: Decodable>(_ type: T.Type, _ key: String) -> T? {
    guard let raw = storage.string(forKey: prefix + key), let data = raw.data(using: .utf8) else {
      return nil
    }
    return try? JSONDecoder().decode(Box<T>.self, from: data).value
  }

  func set<T: Encodable>(_ key: String, _ value: T) {
    // Wrapped, because a bare string or number is not a JSON document for every encoder.
    guard let data = try? JSONEncoder().encode(Box(value: value)),
      let raw = String(data: data, encoding: .utf8)
    else { return }
    storage.set(raw, forKey: prefix + key)
  }

  func remove(_ key: String) { storage.removeValue(forKey: prefix + key) }

}

private struct Box<Value> { let value: Value }
extension Box: Decodable where Value: Decodable {}
extension Box: Encodable where Value: Encodable {}

/// A short, stable, non-reversible name for a string. Keeps one key's stored data apart from
/// another's, and one user's from the next.
func shortHash(_ value: String) -> String {
  var hash: UInt32 = 5381
  for unit in value.utf16 { hash = (hash << 5) &+ hash &+ UInt32(unit) }
  return String(hash, radix: 36)
}

/// A random v4 UUID. Used for install ids, event ids and idempotency keys.
func newID() -> String { UUID().uuidString.lowercased() }
