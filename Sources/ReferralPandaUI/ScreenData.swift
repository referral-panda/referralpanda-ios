import Foundation
import ReferralPanda

/// What a screen is filled in with: the person's values, numbers, rewards and files.
public struct ScreenData: Hashable, Sendable, Decodable {
  public var values: [String: String]
  public var stats: Placement.Stats
  public var rewards: [Placement.RewardLine]
  /// Asset id to URL.
  public var assets: [String: String]
  public var offerCode: String?
  /// Show "Powered by ReferralPanda" under the screen (Free plan). Set by the API.
  public var badge: Bool

  public init(_ placement: Placement) {
    values = placement.values
    stats = placement.stats
    rewards = placement.rewards
    assets = placement.assets
    offerCode = placement.offerCode
    badge = placement.badge
  }

  private enum CodingKeys: String, CodingKey {
    case values, stats, rewards, assets, offerCode, badge
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    values = try container.decode([String: String].self, forKey: .values)
    stats = try container.decode(Placement.Stats.self, forKey: .stats)
    rewards = try container.decode([Placement.RewardLine].self, forKey: .rewards)
    assets = try container.decodeIfPresent([String: String].self, forKey: .assets) ?? [:]
    offerCode = try container.decodeIfPresent(String.self, forKey: .offerCode)
    badge = try container.decodeIfPresent(Bool.self, forKey: .badge) ?? false
  }

  func stat(_ name: String) -> Int {
    switch name {
    case "total": return stats.total
    case "pending": return stats.pending
    case "qualified": return stats.qualified
    case "rewarded": return stats.rewarded
    default: return 0
    }
  }

  /// The URL for an "asset:<id>" reference, if the server resolved one.
  func assetURL(_ reference: String?) -> String? {
    guard let reference, reference.hasPrefix("asset:") else { return nil }
    return assets[String(reference.dropFirst("asset:".count))]
  }
}

/// The badge's text. The same words as every other renderer (see the conformance fixtures).
let badgeText = "Powered by ReferralPanda"

/// Share channel names are not translated yet: they are the same on every platform.
let channelLabels = [
  "messages": "Messages", "whatsapp": "WhatsApp", "copy_link": "Copy link", "more": "More",
]

private let tokenPattern = try? NSRegularExpression(pattern: "\\{\\{\\s*([^{}]*?)\\s*\\}\\}")

/// Replaces {{tokens}} with their values. A token with no value becomes an empty string, so
/// a missing name gives "Hi !" at worst and never shows braces. The result is plain text.
func interpolate(_ text: String, _ values: [String: String]) -> String {
  var result = ""
  let source = text as NSString
  var cursor = 0
  let found =
    tokenPattern?.matches(in: text, range: NSRange(location: 0, length: source.length)) ?? []
  for match in found {
    result += source.substring(
      with: NSRange(location: cursor, length: match.range.location - cursor))
    result += values[source.substring(with: match.range(at: 1))] ?? ""
    cursor = match.range.location + match.range.length
  }
  result += source.substring(from: cursor)
  return
    result
    .replacingOccurrences(of: "[ \\t]{2,}", with: " ", options: .regularExpression)
    .trimmingCharacters(in: .whitespacesAndNewlines)
}

func isRightToLeft(_ locale: String) -> Bool {
  locale.range(of: "^(ar|he|fa|ur)(-|$)", options: .regularExpression) != nil
}
