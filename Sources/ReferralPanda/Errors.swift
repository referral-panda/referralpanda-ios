import Foundation

/// Why a call failed. Codes from the API are passed through as they are; the rest are raised
/// by the SDK itself.
public struct ReferralPandaError: Error, Equatable, Sendable, LocalizedError {
  public struct Code: RawRepresentable, Hashable, Sendable, ExpressibleByStringLiteral {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(stringLiteral value: String) { self.rawValue = value }

    public static let notConfigured: Code = "not_configured"
    public static let notLoggedIn: Code = "not_logged_in"
    public static let networkError: Code = "network_error"
    public static let timeout: Code = "timeout"
    public static let invalidArgument: Code = "invalid_argument"
    public static let unavailable: Code = "unavailable"
    // From the API.
    public static let invalidAPIKey: Code = "invalid_api_key"
    public static let apiKeyRevoked: Code = "api_key_revoked"
    public static let invalidRequest: Code = "invalid_request"
    public static let notFound: Code = "not_found"
    public static let customerNotFound: Code = "customer_not_found"
    public static let codeNotFound: Code = "code_not_found"
    public static let selfReferral: Code = "self_referral"
    public static let rateLimited: Code = "rate_limited"
    public static let internalError: Code = "internal_error"
  }

  public let code: Code
  public let message: String
  /// HTTP status, when the API answered.
  public let status: Int?
  /// Quote this to support. It identifies the request in our logs.
  public let requestID: String?

  public init(_ code: Code, _ message: String, status: Int? = nil, requestID: String? = nil) {
    self.code = code
    self.message = message
    self.status = status
    self.requestID = requestID
  }

  public var errorDescription: String? { message }

  /// The device is offline or the API is down: worth trying again later.
  var isOffline: Bool {
    code == .networkError || code == .timeout || (status ?? 0) >= 500
  }
  var retryLater: Bool { isOffline || status == 429 }

  static let notLoggedIn = ReferralPandaError(.notLoggedIn, "Call logIn(_:) before this.")
}
