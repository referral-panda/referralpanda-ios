import Foundation

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

/// How requests leave the device. Replace it in tests.
public protocol HTTPTransport: Sendable {
  func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

/// The default transport: a URLSession that keeps no cookies and no cache.
public struct URLSessionTransport: HTTPTransport, @unchecked Sendable {
  private let session: URLSession

  public init(session: URLSession? = nil) {
    self.session = session ?? URLSession(configuration: .ephemeral)
  }

  public func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
    try await withCheckedThrowingContinuation { continuation in
      let task = session.dataTask(with: request) { data, response, error in
        if let error {
          continuation.resume(throwing: error)
        } else if let response = response as? HTTPURLResponse {
          continuation.resume(returning: (data ?? Data(), response))
        } else {
          continuation.resume(throwing: URLError(.badServerResponse))
        }
      }
      task.resume()
    }
  }
}

struct HTTPResult<T: Sendable>: Sendable {
  let data: T
  /// Seconds the server allows the answer to be reused for, from Cache-Control.
  let maxAge: Int?
}

/// For calls whose answer the SDK does not read.
struct Ignored: Decodable, Sendable {
  init() {}
  init(from decoder: Decoder) throws {}
}

private let attempts = 3
private let backoffMs: [UInt64] = [400, 1200]
/// The longest the SDK will wait because the server asked it to. Past this the call fails.
private let maxRetryAfterMs: UInt64 = 5000

struct HTTPClient: Sendable {
  let apiURL: String
  /// A public key, or a preview token. Never logged.
  let apiKey: String
  let transport: HTTPTransport
  let sleep: @Sendable (_ milliseconds: UInt64) async -> Void
  let timeout: TimeInterval
  let userAgent: String
  /// Called with the method, path, status and request id. Never with keys or bodies.
  let debug: (@Sendable (String) -> Void)?

  /// One request to the API, with a timeout and a few retries on network failures, 5xx and
  /// 429. Every POST carries an Idempotency-Key that is the same on each retry, so a request
  /// that reached the server but whose answer was lost is not applied twice.
  func request<T: Decodable & Sendable>(
    _ method: String, _ path: String, body: JSONValue? = nil, as type: T.Type = T.self
  ) async throws -> HTTPResult<T> {
    guard let url = URL(string: apiURL + path) else {
      throw ReferralPandaError(.invalidArgument, "The API address is not a valid URL.")
    }
    var request = URLRequest(url: url)
    request.httpMethod = method
    request.timeoutInterval = timeout
    request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    request.setValue(userAgent, forHTTPHeaderField: "X-ReferralPanda-SDK")
    if method == "POST" {
      request.setValue("application/json", forHTTPHeaderField: "Content-Type")
      request.setValue(newID(), forHTTPHeaderField: "Idempotency-Key")
    }
    if let body { request.httpBody = try? JSONEncoder().encode(body) }
    // Without the query: a query can hold a user id.
    let logPath = String(path.prefix { $0 != "?" })

    var failure = ReferralPandaError(.networkError, "The request could not be sent.")
    for attempt in 0..<attempts {
      if attempt > 0 { await sleep(backoffMs[min(attempt - 1, backoffMs.count - 1)]) }

      let data: Data
      let response: HTTPURLResponse
      do {
        (data, response) = try await transport.send(request)
      } catch {
        let timedOut = (error as? URLError)?.code == .timedOut
        failure = ReferralPandaError(
          timedOut ? .timeout : .networkError,
          timedOut ? "The request timed out." : "The request could not be sent.")
        debug?("\(method) \(logPath) \(failure.code.rawValue)")
        continue
      }

      let json = try? JSONDecoder().decode(JSONValue.self, from: data)
      let requestID =
        response.value(forHTTPHeaderField: "x-request-id")
        ?? json?["error"]?["request_id"]?.stringValue
      debug?("\(method) \(logPath) \(response.statusCode)\(requestID.map { " \($0)" } ?? "")")

      if (200..<300).contains(response.statusCode) {
        let cache = response.value(forHTTPHeaderField: "cache-control") ?? ""
        let maxAge = cache.range(of: "max-age=[0-9]+", options: .regularExpression)
          .flatMap { Int(cache[$0].dropFirst(8)) }
        if T.self == Ignored.self, let ignored = Ignored() as? T {
          return HTTPResult(data: ignored, maxAge: maxAge)
        }
        do {
          return HTTPResult(data: try JSONDecoder().decode(T.self, from: data), maxAge: maxAge)
        } catch {
          throw ReferralPandaError(
            .internalError, "The API sent an answer this SDK version does not understand.",
            status: response.statusCode, requestID: requestID)
        }
      }

      let error = json?["error"]
      failure = ReferralPandaError(
        ReferralPandaError.Code(
          rawValue: error?["code"]?.stringValue
            ?? (response.statusCode >= 500 ? "internal_error" : "invalid_request")),
        error?["message"]?.stringValue ?? "The API answered \(response.statusCode).",
        status: response.statusCode, requestID: requestID)
      guard response.statusCode == 429 || response.statusCode >= 500 else { throw failure }
      if response.statusCode == 429 {
        let seconds = Double(response.value(forHTTPHeaderField: "retry-after") ?? "0") ?? 0
        let wait = UInt64(max(0, seconds) * 1000)
        if wait > maxRetryAfterMs { throw failure }
        if wait > 0, attempt < attempts - 1 { await sleep(wait) }
      }
    }
    throw failure
  }
}
