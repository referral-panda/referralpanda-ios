import Foundation
import XCTest

@testable import ReferralPanda

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

struct Call: Sendable {
  let method: String
  /// Path and query.
  let path: String
  let headers: [String: String]
  let body: JSONValue?

  /// Header names differ in capitalisation between platforms.
  func header(_ name: String) -> String? {
    headers.first { $0.key.lowercased() == name.lowercased() }?.value
  }
}

struct Answer: Sendable {
  var status = 200
  var body: JSONValue = .object([:])
  var headers: [String: String] = [:]
  static func error(_ status: Int, _ code: String) -> Answer {
    Answer(status: status, body: ["error": ["code": .string(code), "message": "No."]])
  }
}

struct Offline: Error {}

/// Stands in for the API. Answers from `handler`, and remembers every request.
final class FakeAPI: HTTPTransport, @unchecked Sendable {
  private let lock = NSLock()
  private var recorded: [Call] = []
  private var respond: @Sendable (Call) throws -> Answer

  init(_ respond: @escaping @Sendable (Call) throws -> Answer = { _ in Answer() }) {
    self.respond = respond
  }

  var calls: [Call] {
    lock.lock()
    defer { lock.unlock() }
    return recorded
  }
  func calls(to suffix: String) -> [Call] {
    calls.filter { $0.path.split(separator: "?")[0].hasSuffix(suffix) }
  }
  func setHandler(_ respond: @escaping @Sendable (Call) throws -> Answer) {
    lock.lock()
    defer { lock.unlock() }
    self.respond = respond
  }

  private func record(_ call: Call) -> @Sendable (Call) throws -> Answer {
    lock.lock()
    defer { lock.unlock() }
    recorded.append(call)
    return respond
  }

  func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
    let url = request.url!
    let parts = URLComponents(url: url, resolvingAgainstBaseURL: false)
    let call = Call(
      method: request.httpMethod ?? "GET",
      // As sent, escapes and all.
      path: (parts?.percentEncodedPath ?? "") + (parts?.percentEncodedQuery.map { "?\($0)" } ?? ""),
      headers: request.allHTTPHeaderFields ?? [:],
      body: request.httpBody.flatMap { try? JSONDecoder().decode(JSONValue.self, from: $0) })
    let answer = try record(call)(call)
    let response = HTTPURLResponse(
      url: url, statusCode: answer.status, httpVersion: nil, headerFields: answer.headers)!
    return (try JSONEncoder().encode(answer.body), response)
  }
}

func referralBody(
  code: String = "SAM123", rewards: [JSONValue] = [], referredBy: JSONValue = .null
) -> JSONValue {
  [
    "code": .string(code),
    "link": .string("https://go.referralpanda.com/toffee/\(code)"),
    "stats": ["total": 2, "by_status": ["qualified": 1, "attributed": 1]],
    "rewards": .array(rewards),
    "program": [
      "id": "prog_1", "name": "Give a month", "hold_days": 7,
      "referrer_reward": ["kind": "offer_code", "label": "One free month"],
      "referee_reward": .null,
    ],
    "referred_by": referredBy,
  ]
}

func rewardBody(_ id: String, state: String, offerCode: JSONValue = .null) -> JSONValue {
  [
    "reward_id": .string(id), "state": .string(state), "kind": "offer_code",
    "label": "One free month", "amount_minor": .null, "currency": .null,
    "available_at": .null, "offer_code": offerCode, "redeem_url": .null,
  ]
}

func placementBody(version: Int = 1, badge: JSONValue? = nil) -> JSONValue {
  var body: [String: JSONValue] = [
    "key": "settings",
    "screen": [
      "id": "scr_1", "version": .int(version), "schema_version": 1,
      "config": ["schemaVersion": 1, "components": []], "published_at": .null,
    ],
    "locale": "en", "strings": ["title": "Invite {{referral.code}}"],
    "values": ["referral.code": "SAM123"],
    "stats": ["total": 0, "pending": 0, "qualified": 0, "rewarded": 0],
    "rewards": [], "assets": [:], "offer_code": .null,
  ]
  if let badge { body["badge"] = badge }
  return .object(body)
}

/// The usual API: identify, referral, placement, attribution, redeem and events all succeed.
func standardAnswer(_ call: Call) -> Answer {
  let path = call.path.split(separator: "?")[0]
  if path.hasSuffix("/identify") { return Answer(body: ["created": true]) }
  if path.hasSuffix("/referral") { return Answer(body: referralBody()) }
  if path.contains("/placements/") { return Answer(body: placementBody()) }
  if path.hasSuffix("/attribution") || path.hasSuffix("/codes/redeem") {
    return Answer(body: [
      "matched": true, "referral": ["id": "ref_1", "status": "attributed", "created": true],
    ])
  }
  return Answer()
}

final class Clock: @unchecked Sendable {
  private let lock = NSLock()
  private var current = Date(timeIntervalSince1970: 1_800_000_000)
  var now: Date {
    lock.lock()
    defer { lock.unlock() }
    return current
  }
  func advance(_ seconds: TimeInterval) {
    lock.lock()
    defer { lock.unlock() }
    current += seconds
  }
}

final class Collected<T>: @unchecked Sendable {
  private let lock = NSLock()
  private var items: [T] = []
  func add(_ item: T) {
    lock.lock()
    defer { lock.unlock() }
    items.append(item)
  }
  var all: [T] {
    lock.lock()
    defer { lock.unlock() }
    return items
  }
}

struct Harness {
  let api: FakeAPI
  let storage: MemoryStorage
  let clock: Clock
  let client: ReferralPandaClient
}

func makeClient(
  apiKey: String = "rp_pub_test_abc", api: FakeAPI = FakeAPI(standardAnswer),
  storage: MemoryStorage = MemoryStorage(), clock: Clock = Clock(),
  configure: (inout ReferralPandaOptions) -> Void = { _ in }
) throws -> Harness {
  var options = ReferralPandaOptions()
  options.transport = api
  options.storage = storage
  options.locale = "en"
  options.appVersion = "1.2.3"
  options.flushInterval = 0
  options.now = { clock.now }
  options.sleep = { _ in }
  configure(&options)
  return Harness(
    api: api, storage: storage, clock: clock,
    client: try ReferralPandaClient(apiKey: apiKey, options: options))
}

/// Waits for work the SDK does in the background.
func eventually(
  _ what: String = "condition", timeout: TimeInterval = 3,
  file: StaticString = #filePath, line: UInt = #line, _ condition: () async -> Bool
) async {
  let deadline = Date().addingTimeInterval(timeout)
  while Date() < deadline {
    if await condition() { return }
    try? await Task.sleep(nanoseconds: 5_000_000)
  }
  XCTFail("Timed out waiting for \(what)", file: file, line: line)
}

func assertThrows(
  _ code: ReferralPandaError.Code, file: StaticString = #filePath, line: UInt = #line,
  _ work: () async throws -> Void
) async {
  do {
    try await work()
    XCTFail("Expected \(code.rawValue)", file: file, line: line)
  } catch let error as ReferralPandaError {
    XCTAssertEqual(error.code, code, file: file, line: line)
  } catch {
    XCTFail("Unexpected error \(error)", file: file, line: line)
  }
}
