import Foundation

#if canImport(UIKit) && !os(watchOS)
  import UIKit
#endif

/// The SDK, configured once for the app. Every method here is also what the screen renderer
/// uses, so an app can build its own referral UI on exactly the same calls.
///
/// ```swift
/// try ReferralPanda.configure(apiKey: "rp_pub_…")
/// try await ReferralPanda.logIn(user.id)
/// let referral = try await ReferralPanda.getReferral()
/// ```
public enum ReferralPanda {
  // The module and this type share a name, so `ReferralPanda.Reward` means a member of this
  // type. These make the common model names resolve either way.
  public typealias Client = ReferralPandaClient
  public typealias Options = ReferralPandaOptions
  public typealias Event = ReferralPandaEvent
  public typealias Failure = ReferralPandaError

  private static let lock = NSLock()
  private static var configured: ReferralPandaClient?
  private static var observers: [NSObjectProtocol] = []

  /// Call once at app start, before anything else. Calling it again replaces the configuration.
  /// - Parameter apiKey: a public key (rp_pub_…).
  /// - Throws: when the key is not a public key.
  @discardableResult
  public static func configure(
    apiKey: String, appUserID: String? = nil,
    options: ReferralPandaOptions = ReferralPandaOptions()
  ) throws -> ReferralPandaClient {
    var options = options
    if let appUserID { options.appUserID = appUserID }
    let client = try ReferralPandaClient(apiKey: apiKey, options: options)

    lock.lock()
    defer { lock.unlock() }
    for observer in observers { NotificationCenter.default.removeObserver(observer) }
    observers = []
    configured = client
    #if canImport(UIKit) && !os(watchOS)
      observers = [
        NotificationCenter.default.addObserver(
          forName: UIApplication.didBecomeActiveNotification, object: nil, queue: nil
        ) { _ in Task { await client.resume() } },
        NotificationCenter.default.addObserver(
          forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: nil
        ) { _ in Task { await client.flush() } },
      ]
    #endif
    return client
  }

  public static var isConfigured: Bool { client != nil }

  /// The configured client, or nil before `configure`.
  public static var client: ReferralPandaClient? {
    lock.lock()
    defer { lock.unlock() }
    return configured
  }

  private static func current() throws -> ReferralPandaClient {
    guard let client else {
      throw ReferralPandaError(.notConfigured, "Call ReferralPanda.configure(apiKey:) first.")
    }
    return client
  }

  public static var appUserID: String? {
    get async { await client?.appUserID }
  }

  @discardableResult
  public static func logIn(
    _ appUserID: String, attributes: Attributes? = nil, revenueCatAppUserID: String? = nil
  ) async throws -> Bool {
    try await current().logIn(
      appUserID, attributes: attributes, revenueCatAppUserID: revenueCatAppUserID)
  }

  public static func logOut() async { await client?.logOut() }

  public static func setAttributes(_ attributes: Attributes) async throws {
    try await current().setAttributes(attributes)
  }

  /// Give every URL the app is opened with to this: from `onOpenURL`, and from
  /// `onContinueUserActivity` for universal links. Returns false, without throwing, when the
  /// SDK is not configured yet.
  @discardableResult
  public static func handleURL(_ url: URL?) -> Bool { client?.handleURL(url) ?? false }

  public static func getReferral(refresh: Bool = false) async throws -> Referral {
    try await current().getReferral(refresh: refresh)
  }

  public static func getRewards(refresh: Bool = false) async throws -> [Reward] {
    try await current().getRewards(refresh: refresh)
  }

  public static func getOfferCode() async throws -> String? {
    try await current().getOfferCode()
  }

  public static func getPlacement(_ key: String, locale: String? = nil, refresh: Bool = false)
    async throws -> Placement
  {
    try await current().getPlacement(key, locale: locale, refresh: refresh)
  }

  public static func getShareContent(channel: String? = nil, message: String? = nil)
    async throws -> ShareContent
  {
    try await current().getShareContent(channel: channel, message: message)
  }

  public static func trackShare(channel: String) { client?.trackShare(channel: channel) }

  public static func redeemCode(_ code: String) async throws -> RedeemResult {
    try await current().redeemCode(code)
  }

  /// Returns false when the SDK is not configured or the event name is not valid.
  @discardableResult
  public static func track(_ type: String, properties: Attributes = [:]) -> Bool {
    client?.track(type, properties: properties) ?? false
  }

  public static func flush() async { await client?.flush() }

  @discardableResult
  public static func addListener(_ listener: @escaping @Sendable (ReferralPandaEvent) -> Void)
    async throws -> ListenerToken
  {
    try await current().addListener(listener)
  }

  public static func removeListener(_ token: ListenerToken) async {
    await client?.removeListener(token)
  }
}
