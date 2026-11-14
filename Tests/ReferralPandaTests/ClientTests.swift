import XCTest

@testable import ReferralPanda

final class ClientTests: XCTestCase {
  // MARK: Keys

  func testRefusesASecretKey() {
    XCTAssertThrowsError(try ReferralPandaClient(apiKey: "rp_sk_live_abc")) { error in
      XCTAssertEqual((error as? ReferralPandaError)?.code, .invalidArgument)
      XCTAssertTrue((error as? ReferralPandaError)?.message.contains("secret key") ?? false)
    }
    XCTAssertThrowsError(try ReferralPandaClient(apiKey: "hello"))
  }

  func testEnvironmentComesFromTheKey() throws {
    XCTAssertEqual(try makeClient(apiKey: "rp_pub_test_x").client.environment, .sandbox)
    XCTAssertEqual(try makeClient(apiKey: "rp_pub_live_x").client.environment, .production)
  }

  // MARK: Identity

  func testLogInIdentifiesTheUser() async throws {
    let h = try makeClient()
    let created = try await h.client.logIn("sam", attributes: ["first_name": "Sam"])
    XCTAssertTrue(created)
    let call = try XCTUnwrap(h.api.calls(to: "/identify").first)
    XCTAssertEqual(call.method, "POST")
    XCTAssertEqual(call.header("Authorization"), "Bearer rp_pub_test_abc")
    XCTAssertEqual(call.header("X-ReferralPanda-SDK"), "swift/\(sdkVersion) ios")
    XCTAssertNotNil(call.header("Idempotency-Key"))
    XCTAssertEqual(call.body?["app_user_id"], "sam")
    XCTAssertEqual(call.body?["platform"], "ios")
    XCTAssertEqual(call.body?["app_version"], "1.2.3")
    XCTAssertEqual(call.body?["attributes"], ["first_name": "Sam"])
    let user = await h.client.appUserID
    XCTAssertEqual(user, "sam")
  }

  func testInstallIdSurvivesSignOutAndRelaunch() async throws {
    let h = try makeClient()
    try await h.client.logIn("sam")
    await h.client.logOut()
    try await h.client.logIn("alex")
    let again = try makeClient(storage: h.storage)
    try await again.client.logIn("sam")
    let ids = (h.api.calls(to: "/identify") + again.api.calls(to: "/identify"))
      .compactMap { $0.body?["install_id"]?.stringValue }
    XCTAssertEqual(ids.count, 3)
    XCTAssertEqual(Set(ids).count, 1)
    XCTAssertGreaterThanOrEqual(ids[0].count, 16)
  }

  func testAUserGivenAtConfigurationIsSignedIn() async throws {
    let h = try makeClient { $0.appUserID = "sam"; $0.revenueCatAppUserID = "rc_sam" }
    try await h.client.ready()
    XCTAssertEqual(h.api.calls(to: "/identify").first?.body?["rc_app_user_id"], "rc_sam")
    let referral = try await h.client.getReferral()
    XCTAssertEqual(referral.code, "SAM123")
  }

  func testCallsThatNeedAUserSaySo() async throws {
    let h = try makeClient()
    await assertThrows(.notLoggedIn) { _ = try await h.client.getReferral() }
    await assertThrows(.notLoggedIn) { _ = try await h.client.redeemCode("ABC123") }
    await assertThrows(.invalidArgument) { try await h.client.logIn("  ") }
  }

  func testEventsAnnounceSignInAndOut() async throws {
    let h = try makeClient()
    let seen = Collected<String?>()
    await h.client.addListener { if case .userChanged(let id) = $0 { seen.add(id) } }
    try await h.client.logIn("sam")
    try await h.client.logIn("sam")
    await h.client.logOut()
    XCTAssertEqual(seen.all, ["sam", nil])
  }

  // MARK: Attribution

  func testALinkOpenedBeforeSignInIsSentAfterIt() async throws {
    let h = try makeClient()
    let link = URL(string: "https://go.referralpanda.com/toffee/ALEX99")!
    XCTAssertTrue(h.client.handleURL(link))
    XCTAssertFalse(h.client.handleURL(URL(string: "https://example.com/toffee/ALEX99")))
    XCTAssertFalse(h.client.handleURL(nil))
    await eventually("the link to be saved") { h.storage.string(forKey: "rp:\(shortHash("rp_pub_test_abc")):pending") != nil }
    XCTAssertTrue(h.api.calls(to: "/attribution").isEmpty)

    try await h.client.logIn("sam")
    await eventually("attribution") { h.api.calls(to: "/attribution").count == 1 }
    let body = h.api.calls(to: "/attribution")[0].body
    XCTAssertEqual(body?["link_url"]?.stringValue, link.absoluteString)
    XCTAssertEqual(body?["app_user_id"], "sam")
    XCTAssertNotNil(body?["install_id"]?.stringValue)
    await eventually("the link to be cleared") { h.storage.string(forKey: "rp:\(shortHash("rp_pub_test_abc")):pending") == nil }
  }

  func testALinkIsKeptWhileOfflineAndDroppedWhenRefused() async throws {
    let offline = FakeAPI { call in
      if call.path.hasSuffix("/attribution") { throw Offline() }
      return standardAnswer(call)
    }
    let h = try makeClient(api: offline)
    try await h.client.logIn("sam")
    h.client.handleURL(URL(string: "https://go.referralpanda.com/toffee/ALEX99"))
    await eventually("three attempts") { offline.calls(to: "/attribution").count == 3 }
    let key = "rp:\(shortHash("rp_pub_test_abc")):pending"
    XCTAssertNotNil(h.storage.string(forKey: key))

    offline.setHandler { call in
      call.path.hasSuffix("/attribution") ? .error(404, "code_not_found") : standardAnswer(call)
    }
    await h.client.resume()
    XCTAssertEqual(offline.calls(to: "/attribution").count, 4)
    XCTAssertNil(h.storage.string(forKey: key))
  }

  func testRedeemCode() async throws {
    let h = try makeClient()
    try await h.client.logIn("sam")
    let ok = try await h.client.redeemCode(" alex99 ")
    XCTAssertEqual(ok, .redeemed(firstTime: true, referralStatus: .attributed))
    XCTAssertEqual(h.api.calls(to: "/codes/redeem").first?.body?["code"], "ALEX99")

    let malformed = try await h.client.redeemCode("no")
    XCTAssertEqual(malformed, .invalidCode)
    XCTAssertEqual(h.api.calls(to: "/codes/redeem").count, 1)

    h.api.setHandler { call in
      call.path.hasSuffix("/codes/redeem") ? .error(404, "code_not_found") : standardAnswer(call)
    }
    let unknown = try await h.client.redeemCode("NOPE12")
    XCTAssertEqual(unknown, .invalidCode)
    h.api.setHandler { call in
      call.path.hasSuffix("/codes/redeem") ? .error(422, "self_referral") : standardAnswer(call)
    }
    let own = try await h.client.redeemCode("SAM123")
    XCTAssertEqual(own, .ownCode)
    h.api.setHandler { call in
      call.path.hasSuffix("/codes/redeem") ? .error(401, "invalid_api_key") : standardAnswer(call)
    }
    await assertThrows(.invalidAPIKey) { _ = try await h.client.redeemCode("ALEX99") }
  }

  // MARK: The referral summary

  func testGetReferralAnswersFromMemoryForAWhile() async throws {
    let h = try makeClient()
    try await h.client.logIn("sam+1@example.com")
    let first = try await h.client.getReferral()
    XCTAssertEqual(first.code, "SAM123")
    XCTAssertEqual(first.stats.total, 2)
    XCTAssertEqual(first.stats.count(.qualified), 1)
    XCTAssertEqual(first.stats.count(.rewarded), 0)
    XCTAssertEqual(first.program?.holdDays, 7)
    XCTAssertEqual(first.program?.referrerReward?.kind, .offerCode)
    XCTAssertFalse(first.stale)
    _ = try await h.client.getReferral()
    XCTAssertEqual(h.api.calls(to: "/referral").count, 1)
    XCTAssertEqual(
      h.api.calls(to: "/referral")[0].path, "/v1/sdk/customers/sam%2B1%40example.com/referral")

    h.clock.advance(31)
    _ = try await h.client.getReferral()
    XCTAssertEqual(h.api.calls(to: "/referral").count, 2)
    _ = try await h.client.getReferral(refresh: true)
    XCTAssertEqual(h.api.calls(to: "/referral").count, 3)
  }

  func testOfflineAnswersWithTheSavedCopyMarkedStale() async throws {
    let h = try makeClient()
    try await h.client.logIn("sam")
    _ = try await h.client.getReferral()

    // A new launch, with no network for the referral call.
    let offline = FakeAPI { call in
      if call.path.hasSuffix("/referral") { throw Offline() }
      return standardAnswer(call)
    }
    let next = try makeClient(api: offline, storage: h.storage)
    try await next.client.logIn("sam")
    let saved = try await next.client.getReferral()
    XCTAssertTrue(saved.stale)
    XCTAssertEqual(saved.code, "SAM123")

    // Another user has no saved copy, and is never given Sam's.
    try await next.client.logIn("alex")
    await assertThrows(.networkError) { _ = try await next.client.getReferral() }
  }

  func testNewAndChangedRewardsAreAnnounced() async throws {
    let rewards = Collected<JSONValue>()
    let api = FakeAPI { call in
      call.path.hasSuffix("/referral")
        ? Answer(body: referralBody(rewards: rewards.all)) : standardAnswer(call)
    }
    let h = try makeClient(api: api)
    let seen = Collected<String>()
    await h.client.addListener { event in
      switch event {
      case .rewardEarned(let reward): seen.add("earned \(reward.id)")
      case .rewardUpdated(let reward): seen.add("updated \(reward.id) \(reward.state.rawValue)")
      case .referralChanged: seen.add("changed")
      default: break
      }
    }
    try await h.client.logIn("sam")
    rewards.add(rewardBody("rw_old", state: "held"))
    _ = try await h.client.getReferral()
    // The first look at a user announces nothing: after a reinstall nothing is "new".
    XCTAssertEqual(seen.all, [])

    rewards.add(rewardBody("rw_new", state: "issued", offerCode: "FREEMONTH"))
    _ = try await h.client.getReferral(refresh: true)
    XCTAssertEqual(seen.all, ["earned rw_new", "changed"])
    let code = try await h.client.getOfferCode()
    XCTAssertEqual(code, "FREEMONTH")

    _ = try await h.client.getReferral(refresh: true)
    XCTAssertEqual(seen.all.count, 2)
  }

  func testSigningInAsSomeoneElseForgetsTheFirstUser() async throws {
    let h = try makeClient()
    try await h.client.logIn("sam")
    _ = try await h.client.getReferral()
    try await h.client.logIn("alex")
    _ = try await h.client.getReferral()
    XCTAssertEqual(
      h.api.calls(to: "/referral").map(\.path),
      ["/v1/sdk/customers/sam/referral", "/v1/sdk/customers/alex/referral"])
  }

  // MARK: Placements

  func testPlacementIsCachedAndRefreshedInTheBackground() async throws {
    let version = Collected<Int>()
    let api = FakeAPI { call in
      call.path.contains("/placements/")
        ? Answer(
          body: placementBody(version: 1 + version.all.count),
          headers: ["Cache-Control": "private, max-age=120"])
        : standardAnswer(call)
    }
    let h = try makeClient(api: api)
    let updates = Collected<Int>()
    await h.client.addListener {
      if case .placementUpdated(let placement) = $0 { updates.add(placement.screen.version) }
    }
    let first = try await h.client.getPlacement("settings")
    XCTAssertEqual(first.screen.version, 1)
    XCTAssertEqual(first.strings["title"], "Invite {{referral.code}}")
    XCTAssertEqual(first.values["referral.code"], "SAM123")
    XCTAssertFalse(first.badge)
    XCTAssertEqual(api.calls(to: "/placements/settings")[0].path, "/v1/sdk/placements/settings?locale=en")

    h.clock.advance(119)
    _ = try await h.client.getPlacement("settings")
    XCTAssertEqual(api.calls(to: "/placements/settings").count, 1)

    version.add(1)
    h.clock.advance(2)
    let cached = try await h.client.getPlacement("settings")
    XCTAssertEqual(cached.screen.version, 1)
    await eventually("the newer screen") { updates.all == [2] }
    let fresh = try await h.client.getPlacement("settings")
    XCTAssertEqual(fresh.screen.version, 2)
  }

  func testPlacementBadgeAndUserAndValidation() async throws {
    let api = FakeAPI { call in
      call.path.contains("/placements/")
        ? Answer(body: placementBody(badge: true)) : standardAnswer(call)
    }
    let h = try makeClient(api: api)
    try await h.client.logIn("sam")
    let placement = try await h.client.getPlacement("settings", locale: "pt-BR")
    XCTAssertTrue(placement.badge)
    XCTAssertEqual(
      api.calls(to: "/placements/settings")[0].path,
      "/v1/sdk/placements/settings?app_user_id=sam&locale=pt-BR")
    await assertThrows(.invalidArgument) { _ = try await h.client.getPlacement("Not A Key") }
  }

  func testAPlacementThatIsGoneStopsBeingShown() async throws {
    let h = try makeClient()
    _ = try await h.client.getPlacement("settings")
    h.api.setHandler { call in
      call.path.contains("/placements/") ? .error(404, "not_found") : standardAnswer(call)
    }
    await assertThrows(.notFound) { _ = try await h.client.getPlacement("settings", refresh: true) }
    let relaunched = try makeClient(api: h.api, storage: h.storage)
    await assertThrows(.notFound) { _ = try await relaunched.client.getPlacement("settings") }
  }

  func testAPlacementSurvivesBeingOffline() async throws {
    let h = try makeClient()
    _ = try await h.client.getPlacement("settings")
    let offline = FakeAPI { _ in throw Offline() }
    let next = try makeClient(api: offline, storage: h.storage)
    let saved = try await next.client.getPlacement("settings")
    XCTAssertEqual(saved.screen.id, "scr_1")
    let forced = try await next.client.getPlacement("settings", refresh: true)
    XCTAssertTrue(forced.stale)
  }

  // MARK: Sharing

  func testShareContent() async throws {
    let h = try makeClient()
    try await h.client.logIn("sam")
    let link = "https://go.referralpanda.com/toffee/SAM123"
    let plain = try await h.client.getShareContent()
    XCTAssertEqual(plain, ShareContent(code: "SAM123", link: link, message: link))
    let custom = try await h.client.getShareContent(
      channel: "whatsapp", message: "Use {{ referral.code }} at {{referral.link}}!")
    XCTAssertEqual(custom.message, "Use SAM123 at \(link)?ch=whatsapp!")
    let noLink = try await h.client.getShareContent(message: "Join me")
    XCTAssertEqual(noLink.message, "Join me \(link)")
  }

  // MARK: Events

  func testEventsAreSentTogetherAndOncePerUser() async throws {
    let h = try makeClient()
    XCTAssertTrue(h.client.track("app_opened"))
    XCTAssertFalse(h.client.track("Not Valid"))
    try await h.client.logIn("sam")
    h.client.track("screen_viewed", properties: ["placement": "settings"])
    h.client.trackShare(channel: "whatsapp")
    h.client.trackShare(channel: "NOT OK")
    await eventually("events to be queued") {
      (h.storage.string(forKey: "rp:\(shortHash("rp_pub_test_abc")):events") ?? "")
        .components(separatedBy: "eventID").count == 5
    }
    await h.client.flush()

    let calls = h.api.calls(to: "/events")
    XCTAssertEqual(calls.count, 2)
    XCTAssertNil(calls[0].body?["app_user_id"])
    XCTAssertEqual(calls[0].body?["events"]?.arrayValue?.count, 1)
    XCTAssertEqual(calls[1].body?["app_user_id"], "sam")
    let events = calls[1].body?["events"]?.arrayValue ?? []
    XCTAssertEqual(events.map { $0["type"]?.stringValue }, ["screen_viewed", "share_tapped", "share_tapped"])
    XCTAssertEqual(events[0]["properties"], ["placement": "settings"])
    XCTAssertEqual(events[1]["properties"], ["channel": "whatsapp"])
    XCTAssertNil(events[2]["properties"])
    XCTAssertEqual(events[0]["occurred_at"]?.stringValue, "2027-01-15T08:00:00.000Z")
    XCTAssertEqual(Set(events.compactMap { $0["event_id"]?.stringValue }).count, 3)

    await h.client.flush()
    XCTAssertEqual(h.api.calls(to: "/events").count, 2)
  }

  func testEventsSurviveBeingOfflineAndARelaunch() async throws {
    let offline = FakeAPI { call in
      if call.path.hasSuffix("/events") { throw Offline() }
      return standardAnswer(call)
    }
    let h = try makeClient(api: offline)
    try await h.client.logIn("sam")
    h.client.track("signed_up")
    await eventually("three attempts") { offline.calls(to: "/events").count == 3 }

    let next = try makeClient(storage: h.storage)
    try await next.client.logIn("sam")
    await next.client.flush()
    let sent = next.api.calls(to: "/events")
    XCTAssertEqual(sent.count, 1)
    XCTAssertEqual(sent[0].body?["events"]?.arrayValue?.first?["type"], "signed_up")
    XCTAssertEqual(sent[0].body?["app_user_id"], "sam")
  }

  func testARefusedBatchIsDropped() async throws {
    let h = try makeClient()
    h.api.setHandler { call in
      call.path.hasSuffix("/events") ? .error(400, "invalid_request") : standardAnswer(call)
    }
    try await h.client.logIn("sam")
    h.client.track("odd_event")
    await eventually("the event to be queued") {
      h.storage.string(forKey: "rp:\(shortHash("rp_pub_test_abc")):events")?.contains("odd_event") == true
    }
    await h.client.flush()
    await h.client.flush()
    XCTAssertEqual(h.api.calls(to: "/events").count, 1)
  }

  func testEventStream() async throws {
    let h = try makeClient()
    let stream = h.client.events
    let first = Task { () -> String? in
      for await event in stream {
        if case .userChanged(let id) = event { return id }
      }
      return nil
    }
    await eventually("the stream to be listening") {
      try? await h.client.logIn("sam")
      await h.client.logOut()
      return true
    }
    try await h.client.logIn("alex")
    let id = await first.value
    XCTAssertNotNil(id)
  }
}
