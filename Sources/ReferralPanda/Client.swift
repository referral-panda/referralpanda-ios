import Foundation

public let sdkVersion = "0.1.0-beta.0"

public enum ReferralPandaEnvironment: String, Sendable {
  case sandbox, production
}

public struct ReferralPandaOptions: Sendable {
  /// Your id for the signed-in user. Leave out until the user signs in, then call logIn.
  public var appUserID: String?
  /// The RevenueCat app user id, when it differs from appUserID.
  public var revenueCatAppUserID: String?
  public var apiURL = "https://api.referralpanda.com"
  /// Hosts whose links are share links. Add your custom link domain here.
  public var linkHosts: [String] = []
  /// Defaults to UserDefaults, in a suite of its own.
  public var storage: ReferralPandaStorage?
  public var transport: HTTPTransport?
  /// Logs one line per request: method, path, status and request id. Nothing else.
  public var debug = false
  public var debugHandler: (@Sendable (String) -> Void)?
  /// How long events wait to be sent together. 0 sends only when flush() is called.
  public var flushInterval: TimeInterval = 2
  public var timeout: TimeInterval = 10
  /// "ios" unless the app says otherwise.
  public var platform = "ios"
  /// Defaults to the app's CFBundleShortVersionString.
  public var appVersion: String?
  /// The locale screens are asked for, for example "pt-BR". Defaults to the device's first language.
  public var locale: String?
  /// For tests.
  public var now: @Sendable () -> Date = { Date() }
  public var sleep: @Sendable (_ milliseconds: UInt64) async -> Void = {
    try? await Task.sleep(nanoseconds: $0 * 1_000_000)
  }

  public init(appUserID: String? = nil, revenueCatAppUserID: String? = nil) {
    self.appUserID = appUserID
    self.revenueCatAppUserID = revenueCatAppUserID
  }
}

private struct PendingAttribution: Codable, Equatable, Sendable {
  var linkURL: String?
}

private struct QueuedEvent: Codable, Sendable {
  let type: String
  let eventID: String
  let occurredAt: String
  let properties: [String: JSONValue]?
  /// The user at the time, so an event recorded before logOut is not credited to the next user.
  let user: String?
}

private struct CachedPlacement: Codable, Sendable {
  var placement: Placement
  var maxAge: TimeInterval
}

private let eventTypePattern = "[a-z][a-z0-9_]{0,62}"
private let placementKeyPattern = "[a-z][a-z0-9_]{0,62}"
private let referralTTL: TimeInterval = 30
private let defaultPlacementMaxAge = 60
private let maxQueue = 500
private let batchSize = 100
private let flushAt = 20

/// The whole SDK without any UI. Everything the screen renderer does goes through the public
/// methods here, so an app can build its own referral screen on the same calls.
public actor ReferralPandaClient {
  public nonisolated let environment: ReferralPandaEnvironment
  private let http: HTTPClient
  private let store: Store
  private let linkHosts: [String]
  private let options: ReferralPandaOptions
  private let debug: (@Sendable (String) -> Void)?

  private var user: String?
  private var revenueCatUser: String?
  private var pending: PendingAttribution?
  private var install: String?
  private var queue: [QueuedEvent] = []
  private var referral: Referral?
  /// The request in flight, and whose it is. Never handed to another user.
  private var referralRequest: (user: String, task: Task<Referral, Error>)?
  /// Sign-ins and sign-outs run one at a time, in the order they were asked for.
  private var identity: Task<Void, Never> = Task {}
  private var placements: [String: CachedPlacement] = [:]
  private var flushing: Task<Void, Never>?
  private var flushTimer: Task<Void, Never>?
  private var attributing: Task<Void, Never>?
  private var startTask: Task<Void, Error>?
  private var listeners: [ListenerToken: @Sendable (ReferralPandaEvent) -> Void] = [:]

  /// - Parameter apiKey: a public key (rp_pub_…). Never a secret key: those must not ship in an app.
  public init(apiKey: String, options: ReferralPandaOptions = ReferralPandaOptions()) throws {
    let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
    if key.hasPrefix("rp_sk_") {
      throw ReferralPandaError(
        .invalidArgument,
        "This is a secret key. Apps must use a public key (rp_pub_…). Roll this key in the dashboard, because a key in an app can be read by anyone."
      )
    }
    guard key.hasPrefix("rp_pub_") else {
      throw ReferralPandaError(.invalidArgument, "apiKey must be a public key (rp_pub_…).")
    }
    environment = key.hasPrefix("rp_pub_test_") ? .sandbox : .production
    linkHosts = (defaultLinkHosts + options.linkHosts).map { $0.lowercased() }
    revenueCatUser = options.revenueCatAppUserID
    store = Store(
      storage: options.storage ?? UserDefaultsStorage(), prefix: "rp:\(shortHash(key)):")
    let log: (@Sendable (String) -> Void)? =
      options.debugHandler ?? (options.debug ? { @Sendable line in print("[ReferralPanda] \(line)") } : nil)
    debug = log
    http = HTTPClient(
      apiURL: options.apiURL.trimmingTrailingSlashes(), apiKey: key,
      transport: options.transport ?? URLSessionTransport(), sleep: options.sleep,
      timeout: options.timeout, userAgent: "swift/\(sdkVersion) \(options.platform)", debug: log)
    self.options = options
    let appUserID = options.appUserID
    Task { await self.begin(appUserID) }
  }

  // MARK: - Identity

  private func begin(_ appUserID: String?) {
    guard startTask == nil else { return }
    startTask = Task { try await self.start(appUserID) }
  }

  private func start(_ appUserID: String?) async throws {
    // Anything recorded while this was loading (a link, an event at app start) is kept.
    if let stored = store.get(PendingAttribution.self, "pending"), pending == nil {
      pending = stored
    }
    queue = (store.get([QueuedEvent].self, "events") ?? []) + queue
    if let appUserID {
      _ = try await signIn(appUserID, attributes: nil)
    } else if !queue.isEmpty {
      scheduleFlush()
    }
  }

  /// Returns when stored state is loaded and any user given at configuration is signed in.
  /// Throws when that sign-in failed.
  public func ready() async throws {
    begin(options.appUserID)
    try await startTask?.value
  }

  private func settled() async { try? await ready() }

  /// The signed-in user's id, or nil.
  public var appUserID: String? { user }

  /// Tells ReferralPanda who the user is. Call it when the user signs in, and again at each
  /// app start. Creates their referral code on first sight, and sends any link the app was
  /// opened with before they signed in.
  /// - Returns: true when this user was new to ReferralPanda.
  @discardableResult
  public func logIn(
    _ appUserID: String, attributes: Attributes? = nil, revenueCatAppUserID: String? = nil
  ) async throws -> Bool {
    await settled()
    return try await inTurn {
      if let revenueCatAppUserID { await self.setRevenueCatUser(revenueCatAppUserID) }
      return try await self.signIn(appUserID, attributes: attributes)
    }
  }

  private func setRevenueCatUser(_ id: String) { revenueCatUser = id }

  /// Runs one identity change after the previous one has finished. Two sign-ins at once
  /// (a double tap, or a sign-in racing a sign-out) would otherwise interleave, and the
  /// device could end up showing one user while holding another's data.
  private func inTurn<T: Sendable>(_ change: @escaping @Sendable () async throws -> T)
    async throws -> T
  {
    let previous = identity
    let task = Task { () async throws -> T in
      await previous.value
      return try await change()
    }
    identity = Task { _ = try? await task.value }
    return try await task.value
  }

  private func signIn(_ appUserID: String, attributes: Attributes?) async throws -> Bool {
    let id = appUserID.trimmingCharacters(in: .whitespacesAndNewlines)
    guard (1...255).contains(id.count) else {
      throw ReferralPandaError(.invalidArgument, "appUserID must be 1 to 255 characters.")
    }
    if user != id { forgetUser() }
    var body: [String: JSONValue] = [
      "app_user_id": .string(id),
      "install_id": .string(installID()),
      "platform": .string(options.platform),
    ]
    if let revenueCatUser { body["rc_app_user_id"] = .string(revenueCatUser) }
    if let attributes { body["attributes"] = .object(attributes) }
    if let version = options.appVersion ?? Self.bundleVersion {
      body["app_version"] = .string(version)
    }
    let answer = try await http.request(
      "POST", "/v1/sdk/customers/identify", body: .object(body), as: WireIdentify.self)
    let changed = user != id
    user = id
    if changed { emit(.userChanged(appUserID: id)) }
    // Not awaited: signing in should not wait on attribution or queued events.
    Task { await self.sendAttribution() }
    scheduleFlush()
    return answer.data.created
  }

  private static var bundleVersion: String? {
    Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
  }

  /// Forgets the user on this device. Their data on the server is untouched.
  public func logOut() async {
    await settled()
    _ = try? await inTurn {
      await self.flush()
      await self.signOut()
    }
  }

  private func signOut() {
    forgetUser()
    let changed = user != nil
    user = nil
    if changed { emit(.userChanged(appUserID: nil)) }
  }

  /// A random id for this install, made once and kept on the device. It survives signing out,
  /// so two accounts used on one install can be recognised as one person. It is not an
  /// advertising id, it is unknown outside this app, and the server keeps only a hash of it.
  private func installID() -> String {
    if let install { return install }
    if let stored = store.get(String.self, "install_id"), stored.count >= 16 {
      install = stored
      return stored
    }
    let created = newID()
    store.set("install_id", created)
    install = created
    return created
  }

  private func forgetUser() {
    referral = nil
    referralRequest = nil
    placements.removeAll()
  }

  /// Updates attributes on the signed-in user, for example `["first_name": "Sam"]`.
  public func setAttributes(_ attributes: Attributes) async throws {
    let user = try await requireUser()
    _ = try await http.request(
      "POST", "/v1/sdk/customers/identify",
      body: ["app_user_id": .string(user), "attributes": .object(attributes)], as: Ignored.self)
  }

  private func requireUser() async throws -> String {
    await settled()
    guard let user else { throw ReferralPandaError.notLoggedIn }
    return user
  }

  // MARK: - Attribution

  /// Give every URL the app is opened with to this. Returns true when it was a share link,
  /// so the app can skip its own handling. The link is kept until a user is signed in.
  @discardableResult
  public nonisolated func handleURL(_ url: URL?) -> Bool {
    guard let text = url?.absoluteString, shareLinkCode(text, hosts: linkHosts) != nil else {
      return false
    }
    Task { await self.noteLink(String(text.prefix(2000))) }
    return true
  }

  private func noteLink(_ url: String) async {
    pending = PendingAttribution(linkURL: url)
    store.set("pending", pending)
    await settled()
    await sendAttribution()
  }

  private func sendAttribution() async {
    if let attributing {
      await attributing.value
      return
    }
    let task = Task { await self.attributeOnce() }
    attributing = task
    await task.value
    if attributing == task { attributing = nil }
  }

  private func attributeOnce() async {
    guard let sent = pending, let user, let link = sent.linkURL else { return }
    do {
      let answer = try await http.request(
        "POST", "/v1/sdk/attribution",
        body: [
          "app_user_id": .string(user), "install_id": .string(installID()),
          "link_url": .string(link),
        ], as: WireAttribution.self)
      clearPending(sent)
      if answer.data.matched { _ = try? await refreshReferral() }
    } catch {
      // Offline or the API is down: keep it for the next attempt. Anything else will never
      // succeed, so it is dropped rather than retried forever.
      if let error = error as? ReferralPandaError, !error.retryLater { clearPending(sent) }
    }
  }

  private func clearPending(_ sent: PendingAttribution) {
    // A link that arrived while the request was in flight stays.
    guard pending == sent else { return }
    pending = nil
    store.remove("pending")
  }

  /// For a code the user types in. A user can only ever be referred once.
  public func redeemCode(_ code: String) async throws -> RedeemResult {
    let user = try await requireUser()
    let cleaned = code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    guard matches(cleaned, "[A-Z0-9]{3,20}") else { return .invalidCode }
    do {
      let answer = try await http.request(
        "POST", "/v1/sdk/codes/redeem",
        body: [
          "app_user_id": .string(user), "code": .string(cleaned),
          "install_id": .string(installID()),
        ], as: WireAttribution.self)
      Task { _ = try? await self.refreshReferral() }
      return .redeemed(
        firstTime: answer.data.referral?.created ?? false,
        referralStatus: answer.data.referral.map { ReferralStatus(rawValue: $0.status) }
          ?? .attributed)
    } catch let error as ReferralPandaError where error.code == .codeNotFound {
      return .invalidCode
    } catch let error as ReferralPandaError where error.code == .selfReferral {
      return .ownCode
    }
  }

  // MARK: - The referral summary

  /// The user's code, link, counts, rewards and who invited them. Answers from memory for a
  /// short while. When the device is offline it answers with the last saved copy, marked stale.
  public func getReferral(refresh: Bool = false) async throws -> Referral {
    _ = try await requireUser()
    if !refresh, let referral,
      options.now().timeIntervalSince(referral.fetchedAt) < referralTTL
    {
      return referral
    }
    return try await refreshReferral()
  }

  private func refreshReferral() async throws -> Referral {
    let user = try await requireUser()
    // Share a request in flight only with the same user.
    if let current = referralRequest, current.user == user { return try await current.task.value }
    let task = Task { try await self.fetchReferral(user) }
    referralRequest = (user, task)
    let result = await task.result
    if referralRequest?.task == task { referralRequest = nil }
    return try result.get()
  }

  private func fetchReferral(_ user: String) async throws -> Referral {
    let slot = "referral:\(shortHash(user))"
    let previous = referral ?? store.get(Referral.self, slot)
    do {
      let answer = try await http.request(
        "GET", "/v1/sdk/customers/\(encodeComponent(user))/referral", as: WireReferral.self)
      let fresh = Referral(answer.data, fetchedAt: options.now())
      guard self.user == user else {
        // Someone else signed in, or the user signed out, while this was on its way. The
        // answer belongs to the earlier user and is never shown to the current one.
        if self.user != nil { return try await refreshReferral() }
        throw ReferralPandaError.notLoggedIn
      }
      referral = fresh
      store.set(slot, fresh)
      announce(previous: previous, next: fresh)
      return fresh
    } catch let error as ReferralPandaError {
      if error.isOffline, var saved = previous, self.user == user {
        saved.stale = true
        return saved
      }
      throw error
    }
  }

  private func announce(previous: Referral?, next: Referral) {
    // Nothing is announced the first time a device sees a user: after a reinstall every old
    // reward would otherwise look newly earned.
    guard let previous else { return }
    let known = Dictionary(
      previous.rewards.map { ($0.id, $0.state) }, uniquingKeysWith: { first, _ in first })
    for reward in next.rewards {
      if let state = known[reward.id] {
        if state != reward.state { emit(.rewardUpdated(reward)) }
      } else {
        emit(.rewardEarned(reward))
      }
    }
    let before = previous.referredBy?.status
    if let now = next.referredBy?.status, now != before {
      emit(.referralStatusChanged(status: now, previous: before))
    }
    if !previous.sameContent(as: next) { emit(.referralChanged(next)) }
  }

  /// The user's rewards. The same list as `getReferral().rewards`.
  public func getRewards(refresh: Bool = false) async throws -> [Reward] {
    try await getReferral(refresh: refresh).rewards
  }

  /// The newest offer code the user can redeem in the store, or nil.
  public func getOfferCode() async throws -> String? {
    try await getRewards().first { $0.state == .issued && $0.offerCode != nil }?.offerCode
  }

  // MARK: - Placements

  /// The published screen for a placement, with its strings and values. Use it to render the
  /// screen yourself. Works before a user signs in, with program-wide values only.
  ///
  /// A cached copy is returned at once. When it is older than the server allows, a fresh one
  /// is fetched in the background and announced with a placementUpdated event.
  public func getPlacement(_ key: String, locale: String? = nil, refresh: Bool = false)
    async throws -> Placement
  {
    await settled()
    guard matches(key, placementKeyPattern) else {
      throw ReferralPandaError(.invalidArgument, "A placement key looks like settings_referral.")
    }
    let locale = locale ?? options.locale ?? Locale.preferredLanguages.first ?? ""
    let slot = "placement:\(key):\(locale):\(user.map(shortHash) ?? "")"
    var cached = placements[slot]
    if cached == nil, !refresh, let stored = store.get(CachedPlacement.self, slot) {
      cached = stored
      placements[slot] = stored
    }
    if let cached, !refresh {
      if options.now().timeIntervalSince(cached.placement.fetchedAt) >= cached.maxAge {
        let before = cached.placement.screen
        Task {
          guard let fresh = try? await self.fetchPlacement(key, locale: locale, slot: slot) else {
            return
          }
          if fresh.screen.version != before.version || fresh.screen.id != before.id {
            self.emit(.placementUpdated(fresh))
          }
        }
      }
      return cached.placement
    }
    do {
      return try await fetchPlacement(key, locale: locale, slot: slot)
    } catch let error as ReferralPandaError {
      if error.isOffline, var saved = cached?.placement {
        saved.stale = true
        return saved
      }
      throw error
    }
  }

  private func fetchPlacement(_ key: String, locale: String, slot: String) async throws
    -> Placement
  {
    let query = [
      user.map { "app_user_id=\(encodeComponent($0))" },
      locale.isEmpty ? nil : "locale=\(encodeComponent(locale))",
    ].compactMap { $0 }.joined(separator: "&")
    do {
      let answer = try await http.request(
        "GET", "/v1/sdk/placements/\(key)\(query.isEmpty ? "" : "?\(query)")",
        as: WirePlacement.self)
      let entry = CachedPlacement(
        placement: Placement(answer.data, fetchedAt: options.now()),
        maxAge: TimeInterval(answer.maxAge ?? defaultPlacementMaxAge))
      placements[slot] = entry
      store.set(slot, entry)
      return entry.placement
    } catch let error as ReferralPandaError {
      // Unpublished or unassigned since: stop showing the old one.
      if error.status == 404 {
        placements[slot] = nil
        store.remove(slot)
      }
      throw error
    }
  }

  // MARK: - Sharing

  /// The link and a message to share, without opening anything. For apps with their own
  /// share flow. `message` may use {{referral.link}} and {{referral.code}}; when it leaves the
  /// link out, the link is added at the end.
  public func getShareContent(channel: String? = nil, message: String? = nil) async throws
    -> ShareContent
  {
    let referral = try await getReferral()
    let link = shareLink(referral.link, channel: channel)
    let trimmed = message?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    var text = (trimmed.isEmpty ? "{{referral.link}}" : trimmed)
      .replacingOccurrences(
        of: "\\{\\{\\s*referral\\.link\\s*\\}\\}",
        with: NSRegularExpression.escapedTemplate(for: link), options: .regularExpression
      )
      .replacingOccurrences(
        of: "\\{\\{\\s*referral\\.code\\s*\\}\\}",
        with: NSRegularExpression.escapedTemplate(for: referral.code), options: .regularExpression)
    if !text.contains(link) { text += " \(link)" }
    return ShareContent(code: referral.code, link: link, message: text)
  }

  /// Records a share the app handled itself, for example its own WhatsApp button.
  public nonisolated func trackShare(channel: String) {
    track("share_tapped", properties: isChannel(channel) ? ["channel": .string(channel)] : [:])
  }

  // MARK: - Events

  /// Records an event, for example `track("screen_viewed", properties: ["placement": "settings"])`.
  /// "signed_up" also moves the user's referral forward. Events are sent together a moment
  /// later and survive being offline or the app closing.
  /// - Returns: false when the name is not lowercase letters, digits and underscores starting
  ///   with a letter. Such an event is not recorded.
  @discardableResult
  public nonisolated func track(_ type: String, properties: Attributes = [:]) -> Bool {
    guard matches(type, eventTypePattern) else {
      debug?("track: \"\(type.prefix(64))\" is not a valid event name, so it was not recorded")
      return false
    }
    // Stamped here, so events keep their order however the tasks below are scheduled.
    let id = newID()
    let occurredAt = Self.timestamp(options.now())
    Task { await self.enqueue(type, id: id, occurredAt: occurredAt, properties: properties) }
    return true
  }

  private static func timestamp(_ date: Date) -> String {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter.string(from: date)
  }

  private func enqueue(_ type: String, id: String, occurredAt: String, properties: Attributes) {
    queue.append(
      QueuedEvent(
        type: type, eventID: id, occurredAt: occurredAt,
        properties: properties.isEmpty ? nil : properties, user: user))
    if queue.count > maxQueue { queue.removeFirst(queue.count - maxQueue) }
    store.set("events", queue)
    if queue.count >= flushAt || type == "signed_up" {
      Task { await self.flush() }
    } else {
      scheduleFlush()
    }
  }

  private func scheduleFlush() {
    guard options.flushInterval > 0, flushTimer == nil, !queue.isEmpty else { return }
    let delay = UInt64(options.flushInterval * 1000)
    flushTimer = Task {
      await self.options.sleep(delay)
      await self.timerFired()
    }
  }

  private func timerFired() async {
    flushTimer = nil
    await flush()
  }

  /// Sends queued events now. Call it when the app goes to the background.
  public func flush() async {
    if let flushing {
      await flushing.value
      return
    }
    let task = Task { await self.flushAll() }
    flushing = task
    await task.value
    if flushing == task { flushing = nil }
  }

  private func flushAll() async {
    await settled()
    while let first = queue.first {
      // One request per user, so no event is credited to someone else.
      let batch = Array(queue.filter { $0.user == first.user }.prefix(batchSize))
      let sent = Set(batch.map(\.eventID))
      var body: [String: JSONValue] = [
        "events": .array(
          batch.map { event in
            var item: [String: JSONValue] = [
              "type": .string(event.type), "event_id": .string(event.eventID),
              "occurred_at": .string(event.occurredAt),
            ]
            if let properties = event.properties { item["properties"] = .object(properties) }
            return .object(item)
          })
      ]
      if let user = first.user { body["app_user_id"] = .string(user) }
      do {
        _ = try await http.request("POST", "/v1/sdk/events", body: .object(body), as: Ignored.self)
      } catch {
        if let error = error as? ReferralPandaError, error.retryLater { return }
        // Refused for good (for example a property the API does not accept): drop the batch.
      }
      queue.removeAll { sent.contains($0.eventID) }
      store.set("events", queue)
    }
  }

  /// Call when the app returns to the foreground: retries anything that could not be sent.
  public func resume() async {
    await settled()
    await sendAttribution()
    await flush()
  }

  // MARK: - Listeners

  /// The listener is called off the main thread. Keep the token to remove it.
  @discardableResult
  public func addListener(_ listener: @escaping @Sendable (ReferralPandaEvent) -> Void)
    -> ListenerToken
  {
    let token = ListenerToken()
    listeners[token] = listener
    return token
  }

  public func removeListener(_ token: ListenerToken) { listeners[token] = nil }

  /// The same events as a stream: `for await event in client.events { … }`.
  public nonisolated var events: AsyncStream<ReferralPandaEvent> {
    AsyncStream { continuation in
      let registration = Task { await self.addListener { continuation.yield($0) } }
      continuation.onTermination = { _ in
        Task { await self.removeListener(await registration.value) }
      }
    }
  }

  private func emit(_ event: ReferralPandaEvent) {
    for listener in listeners.values { listener(event) }
  }
}
