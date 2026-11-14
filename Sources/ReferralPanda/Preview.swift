import Foundation

/// A screen as the dashboard has it right now, published or not, filled with sample data.
public struct ScreenPreview: Hashable, Sendable {
  public let placement: Placement
  /// True when this version has not been published yet.
  public let draft: Bool
  /// When the preview token stops working. ISO 8601.
  public let expiresAt: String
}

private let tokenPattern = "rpv_[A-Za-z0-9_-]{43}"

extension ReferralPandaClient {
  /// The preview token inside a link from the dashboard's "Preview on device" QR code, or nil
  /// when the link is not a preview link.
  public static func previewToken(from url: URL) -> String? {
    guard let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
      parts.host == "preview", parts.path.isEmpty || parts.path == "/",
      let token = parts.queryItems?.first(where: { $0.name == "token" })?.value,
      matches(token, tokenPattern)
    else { return nil }
    return token
  }

  /// Fetches the newest version of a screen with a preview token from the dashboard. Needs no
  /// API key and no configured client: the token alone says which screen. Nothing is cached,
  /// so calling it again shows the latest edit.
  public static func screenPreview(
    token: String, locale: String? = nil,
    apiURL: String = "https://api.referralpanda.com",
    transport: HTTPTransport = URLSessionTransport(), timeout: TimeInterval = 10
  ) async throws -> ScreenPreview {
    guard matches(token, tokenPattern) else {
      throw ReferralPandaError(.invalidArgument, "That is not a preview token.")
    }
    let http = HTTPClient(
      apiURL: apiURL.trimmingTrailingSlashes(),
      // Sent as the bearer token. A preview token is the whole credential for this call.
      apiKey: token, transport: transport,
      sleep: { try? await Task.sleep(nanoseconds: $0 * 1_000_000) },
      timeout: timeout, userAgent: "swift/\(sdkVersion) preview", debug: nil)
    let query = locale.map { "?locale=\(encodeComponent($0))" } ?? ""
    let wire = try await http.request("GET", "/v1/sdk/preview\(query)", as: WirePlacement.self).data
    return ScreenPreview(
      placement: Placement(wire, fetchedAt: Date()), draft: wire.draft ?? false,
      expiresAt: wire.expires_at ?? "")
  }
}

extension String {
  func trimmingTrailingSlashes() -> String {
    var value = self
    while value.hasSuffix("/") { value.removeLast() }
    return value
  }
}
