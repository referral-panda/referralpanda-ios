import Foundation

/// Where a referral has got to. New values may be added by the API, so this is not an enum.
public struct ReferralStatus: RawRepresentable, Hashable, Codable, Sendable {
  public let rawValue: String
  public init(rawValue: String) { self.rawValue = rawValue }
  public static let attributed = ReferralStatus(rawValue: "attributed")
  public static let signedUp = ReferralStatus(rawValue: "signed_up")
  public static let converted = ReferralStatus(rawValue: "converted")
  public static let held = ReferralStatus(rawValue: "held")
  public static let qualified = ReferralStatus(rawValue: "qualified")
  public static let rewarded = ReferralStatus(rawValue: "rewarded")
  public static let void = ReferralStatus(rawValue: "void")
}

public struct RewardState: RawRepresentable, Hashable, Codable, Sendable {
  public let rawValue: String
  public init(rawValue: String) { self.rawValue = rawValue }
  public static let pending = RewardState(rawValue: "pending")
  public static let held = RewardState(rawValue: "held")
  public static let approved = RewardState(rawValue: "approved")
  public static let issuing = RewardState(rawValue: "issuing")
  public static let issued = RewardState(rawValue: "issued")
  public static let void = RewardState(rawValue: "void")
  public static let clawedBack = RewardState(rawValue: "clawed_back")
}

public struct RewardKind: RawRepresentable, Hashable, Codable, Sendable {
  public let rawValue: String
  public init(rawValue: String) { self.rawValue = rawValue }
  public static let revenueCatPromotional = RewardKind(rawValue: "revenuecat_promotional")
  public static let offerCode = RewardKind(rawValue: "offer_code")
  public static let tremendous = RewardKind(rawValue: "tremendous")
  public static let webhookOnly = RewardKind(rawValue: "webhook_only")
}

public struct Reward: Hashable, Codable, Sendable, Identifiable {
  public let id: String
  public let state: RewardState
  public let kind: RewardKind?
  /// What to call it in the app, for example "One free month".
  public let label: String?
  /// Money rewards only. Integer minor units (cents), never a decimal.
  public let amountMinor: Int?
  /// ISO 4217, for example "USD".
  public let currency: String?
  /// When a held reward is released. ISO 8601.
  public let availableAt: String?
  /// For an issued offer code reward: the code to redeem in the store.
  public let offerCode: String?
  /// For an issued gift card or cash reward: where the user collects it.
  public let redeemURL: String?
}

public struct RewardOffer: Hashable, Codable, Sendable {
  public let kind: RewardKind
  public let label: String?
}

public struct Referral: Hashable, Codable, Sendable {
  public struct Stats: Hashable, Codable, Sendable {
    public let total: Int
    public let byStatus: [String: Int]
    /// How many of this user's referrals are at a status.
    public func count(_ status: ReferralStatus) -> Int { byStatus[status.rawValue] ?? 0 }
  }
  public struct Program: Hashable, Codable, Sendable {
    public let id: String
    public let name: String
    public let holdDays: Int
    public let referrerReward: RewardOffer?
    public let refereeReward: RewardOffer?
  }
  public struct ReferredBy: Hashable, Codable, Sendable {
    public let code: String
    public let status: ReferralStatus
  }

  /// This user's own code.
  public let code: String
  /// This user's share link.
  public let link: String
  public let stats: Stats
  public let rewards: [Reward]
  public let program: Program?
  /// Set when this user was invited by someone.
  public let referredBy: ReferredBy?
  public let fetchedAt: Date
  /// True when the device was offline and this is the last copy that was saved.
  public internal(set) var stale: Bool

  func sameContent(as other: Referral) -> Bool {
    code == other.code && link == other.link && stats == other.stats
      && rewards == other.rewards && program == other.program && referredBy == other.referredBy
  }
}

public struct Placement: Hashable, Codable, Sendable {
  public struct Screen: Hashable, Codable, Sendable {
    public let id: String
    public let version: Int
    public let schemaVersion: Int
    /// The screen document, as described at referralpanda.com/docs/screens.
    public let config: [String: JSONValue]
    public let publishedAt: String?
  }
  public struct Stats: Hashable, Codable, Sendable {
    public let total: Int
    public let pending: Int
    public let qualified: Int
    public let rewarded: Int
  }
  public struct RewardLine: Hashable, Codable, Sendable, Identifiable {
    public let id: String
    public let label: String
    /// "pending" or "issued".
    public let state: String
  }

  public let key: String
  public let screen: Screen
  public let locale: String
  /// Strings for the locale, with {{tokens}} still in place.
  public let strings: [String: String]
  /// Values for the tokens.
  public let values: [String: String]
  public let stats: Stats
  public let rewards: [RewardLine]
  /// Asset id to URL.
  public let assets: [String: String]
  public let offerCode: String?
  /// Show "Powered by ReferralPanda" under the screen (Free plan). The SDK's renderer draws it.
  public let badge: Bool
  public let fetchedAt: Date
  public internal(set) var stale: Bool
}

public struct ShareContent: Hashable, Sendable {
  public let code: String
  /// The share link, tagged with the channel when one was given.
  public let link: String
  /// Ready to send. Contains the link.
  public let message: String
}

public enum RedeemResult: Hashable, Sendable {
  /// The code was accepted, now or earlier. A user can only be referred once.
  case redeemed(firstTime: Bool, referralStatus: ReferralStatus)
  case invalidCode
  case ownCode
}

/// Things the SDK tells the app about. Delivered off the main thread.
public enum ReferralPandaEvent: Sendable {
  /// The referral summary changed in any way.
  case referralChanged(Referral)
  /// A reward this device had not seen before.
  case rewardEarned(Reward)
  /// A known reward moved to another state, for example from held to issued.
  case rewardUpdated(Reward)
  /// The referral that brought this user moved on, for example to qualified.
  case referralStatusChanged(status: ReferralStatus, previous: ReferralStatus?)
  /// A user signed in or out on this device.
  case userChanged(appUserID: String?)
  /// A newer published screen arrived for a placement that was served from cache.
  case placementUpdated(Placement)
}

public struct ListenerToken: Hashable, Sendable {
  let id = UUID()
}

// MARK: - What the API sends

struct WireIdentify: Decodable, Sendable {
  let created: Bool
}

struct WireAttribution: Decodable, Sendable {
  struct Referral: Decodable, Sendable {
    let status: String
    let created: Bool
  }
  let matched: Bool
  let referral: Referral?
}

struct WireReferral: Decodable, Sendable {
  struct Stats: Decodable, Sendable {
    let total: Int
    let by_status: [String: Int]
  }
  struct Reward: Decodable, Sendable {
    let reward_id: String
    let state: String
    let kind: String?
    let label: String?
    let amount_minor: Int?
    let currency: String?
    let available_at: String?
    let offer_code: String?
    let redeem_url: String?
  }
  struct Offer: Decodable, Sendable {
    let kind: String
    let label: String?
  }
  struct Program: Decodable, Sendable {
    let id: String
    let name: String
    let hold_days: Int
    let referrer_reward: Offer?
    let referee_reward: Offer?
  }
  struct ReferredBy: Decodable, Sendable {
    let code: String
    let status: String
  }
  let code: String
  let link: String
  let stats: Stats
  let rewards: [Reward]
  let program: Program?
  let referred_by: ReferredBy?
}

struct WirePlacement: Decodable, Sendable {
  struct Screen: Decodable, Sendable {
    let id: String
    let version: Int
    let schema_version: Int
    let config: [String: JSONValue]
    let published_at: String?
  }
  let key: String
  let screen: Screen
  let locale: String
  let strings: [String: String]
  let values: [String: String]
  let stats: Placement.Stats
  let rewards: [Placement.RewardLine]
  let assets: [String: String]
  let offer_code: String?
  /// Absent from an API older than the badge.
  let badge: Bool?
  // Preview only.
  let draft: Bool?
  let expires_at: String?
}

extension Reward {
  init(_ wire: WireReferral.Reward) {
    self.init(
      id: wire.reward_id, state: RewardState(rawValue: wire.state),
      kind: wire.kind.map(RewardKind.init(rawValue:)), label: wire.label,
      amountMinor: wire.amount_minor, currency: wire.currency, availableAt: wire.available_at,
      offerCode: wire.offer_code, redeemURL: wire.redeem_url)
  }
}

extension RewardOffer {
  init(_ wire: WireReferral.Offer) {
    self.init(kind: RewardKind(rawValue: wire.kind), label: wire.label)
  }
}

extension Referral {
  init(_ wire: WireReferral, fetchedAt: Date) {
    self.init(
      code: wire.code, link: wire.link,
      stats: Stats(total: wire.stats.total, byStatus: wire.stats.by_status),
      rewards: wire.rewards.map(Reward.init),
      program: wire.program.map {
        Program(
          id: $0.id, name: $0.name, holdDays: $0.hold_days,
          referrerReward: $0.referrer_reward.map(RewardOffer.init),
          refereeReward: $0.referee_reward.map(RewardOffer.init))
      },
      referredBy: wire.referred_by.map {
        ReferredBy(code: $0.code, status: ReferralStatus(rawValue: $0.status))
      },
      fetchedAt: fetchedAt, stale: false)
  }
}

extension Placement {
  init(_ wire: WirePlacement, fetchedAt: Date) {
    self.init(
      key: wire.key,
      screen: Screen(
        id: wire.screen.id, version: wire.screen.version,
        schemaVersion: wire.screen.schema_version, config: wire.screen.config,
        publishedAt: wire.screen.published_at),
      locale: wire.locale, strings: wire.strings, values: wire.values, stats: wire.stats,
      rewards: wire.rewards, assets: wire.assets, offerCode: wire.offer_code,
      badge: wire.badge == true, fetchedAt: fetchedAt, stale: false)
  }
}
