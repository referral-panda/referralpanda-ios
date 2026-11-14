import Foundation
import XCTest

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

@testable import ReferralPanda

final class HTTPTests: XCTestCase {
  private func client(_ api: FakeAPI, slept: Collected<UInt64> = Collected(), logs: Collected<String>? = nil) -> HTTPClient {
    HTTPClient(
      apiURL: "https://api.test", apiKey: "rp_pub_test_abc", transport: api,
      sleep: { slept.add($0) }, timeout: 10, userAgent: "swift/test ios",
      debug: logs.map { logs in { logs.add($0) } })
  }

  func testRetriesServerErrorsWithTheSameIdempotencyKey() async throws {
    let count = Collected<Int>()
    let api = FakeAPI { _ in
      count.add(1)
      return count.all.count < 3 ? .error(503, "internal_error") : Answer(body: ["created": false])
    }
    let slept = Collected<UInt64>()
    let result = try await client(api, slept: slept)
      .request("POST", "/v1/sdk/customers/identify", body: ["a": 1], as: WireIdentify.self)
    XCTAssertFalse(result.data.created)
    XCTAssertEqual(api.calls.count, 3)
    XCTAssertEqual(Set(api.calls.compactMap { $0.header("Idempotency-Key") }).count, 1)
    XCTAssertEqual(slept.all, [400, 1200])
    XCTAssertEqual(api.calls[0].body, ["a": 1])
  }

  func testGivesUpAfterThreeAttempts() async {
    let api = FakeAPI { _ in throw Offline() }
    await assertThrows(.networkError) {
      _ = try await self.client(api).request("GET", "/v1/x", as: Ignored.self)
    }
    XCTAssertEqual(api.calls.count, 3)
    XCTAssertNil(api.calls[0].header("Idempotency-Key"))

    let timeouts = FakeAPI { _ in throw URLError(.timedOut) }
    await assertThrows(.timeout) {
      _ = try await self.client(timeouts).request("GET", "/v1/x", as: Ignored.self)
    }
  }

  func testDoesNotRetryARefusal() async {
    let api = FakeAPI { _ in
      Answer(
        status: 401,
        body: ["error": ["code": "api_key_revoked", "message": "Revoked.", "request_id": "req_9"]])
    }
    do {
      _ = try await client(api).request("GET", "/v1/x", as: Ignored.self)
      XCTFail("Expected an error")
    } catch let error as ReferralPandaError {
      XCTAssertEqual(error.code, .apiKeyRevoked)
      XCTAssertEqual(error.message, "Revoked.")
      XCTAssertEqual(error.status, 401)
      XCTAssertEqual(error.requestID, "req_9")
    } catch {
      XCTFail("\(error)")
    }
    XCTAssertEqual(api.calls.count, 1)
  }

  func testWaitsWhenAskedToButNotForLong() async throws {
    let count = Collected<Int>()
    let api = FakeAPI { _ in
      count.add(1)
      return count.all.count == 1
        ? Answer(status: 429, body: ["error": ["code": "rate_limited"]], headers: ["Retry-After": "2"])
        : Answer()
    }
    let slept = Collected<UInt64>()
    _ = try await client(api, slept: slept).request("GET", "/v1/x", as: Ignored.self)
    XCTAssertEqual(slept.all, [2000, 400])

    let long = FakeAPI { _ in
      Answer(status: 429, body: ["error": ["code": "rate_limited"]], headers: ["Retry-After": "60"])
    }
    await assertThrows(.rateLimited) {
      _ = try await self.client(long).request("GET", "/v1/x", as: Ignored.self)
    }
    XCTAssertEqual(long.calls.count, 1)
  }

  func testDebugLinesHoldNoKeysBodiesOrQueries() async throws {
    let logs = Collected<String>()
    let api = FakeAPI { _ in Answer(headers: ["x-request-id": "req_1"]) }
    _ = try await client(api, logs: logs)
      .request("POST", "/v1/sdk/events?app_user_id=sam%40example.com", body: ["secret": "s3cret"], as: Ignored.self)
    XCTAssertEqual(logs.all, ["POST /v1/sdk/events 200 req_1"])
  }

  func testAnAnswerThatCannotBeReadIsAnError() async {
    let api = FakeAPI { _ in Answer(body: ["unexpected": true]) }
    await assertThrows(.internalError) {
      _ = try await self.client(api).request("GET", "/v1/x", as: WireReferral.self)
    }
  }

  func testPreviewUsesTheTokenAsTheCredential() async throws {
    let token = "rpv_" + String(repeating: "b", count: 43)
    var body = placementBody().objectValue ?? [:]
    body["draft"] = true
    body["expires_at"] = "2027-01-15T09:00:00.000Z"
    let answer = JSONValue.object(body)
    let api = FakeAPI { _ in Answer(body: answer) }
    let preview = try await ReferralPandaClient.screenPreview(
      token: token, locale: "pt-BR", apiURL: "https://api.test/", transport: api)
    XCTAssertTrue(preview.draft)
    XCTAssertEqual(preview.placement.key, "settings")
    XCTAssertEqual(api.calls[0].path, "/v1/sdk/preview?locale=pt-BR")
    XCTAssertEqual(api.calls[0].header("Authorization"), "Bearer \(token)")
    await assertThrows(.invalidArgument) {
      _ = try await ReferralPandaClient.screenPreview(token: "nope", transport: api)
    }
  }
}
