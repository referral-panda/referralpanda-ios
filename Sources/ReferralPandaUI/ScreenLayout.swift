import Foundation
import ReferralPanda

/// One thing on the screen, with every string already resolved and every rule already
/// applied (platform, visibility, which rewards to list). The SwiftUI views draw exactly
/// this and nothing else, so what the conformance fixtures check here is what is shown.
indirect enum ScreenElement: Equatable {
  struct Milestone: Equatable {
    let label: String
    let count: Int
    let reached: Bool
  }
  struct Channel: Equatable {
    let channel: String
    let label: String
  }
  struct StatCell: Equatable {
    let label: String
    let value: String
  }
  struct RewardRow: Equatable {
    let id: String
    let label: String
    let issued: Bool
  }
  enum Action: Equatable {
    case share(channel: String, message: String)
    case redeemOfferCode(String)

    var name: String {
      switch self {
      case .share(let channel, _): return "share:\(channel)"
      case .redeemOfferCode: return "redeem_offer_code"
      }
    }
  }

  case stack(horizontal: Bool, spacing: Double, padding: Double, align: String, [ScreenElement])
  case scroll(spacing: Double, padding: Double, [ScreenElement])
  case card(spacing: Double, padding: Double, background: String, border: Bool, [ScreenElement])
  case spacer(Double)
  case text(String, style: String, align: String, color: String)
  case image(url: String?, alt: String, aspect: Double, cover: Bool, rounded: Bool)
  case lottie(url: String?, loop: Bool, aspect: Double)
  case icon(name: String, size: Double, color: String)
  case codeBox(label: String, code: String, copiedLabel: String)
  case button(label: String, primary: Bool, Action)
  case channelRow([Channel], message: String)
  case progress(caption: String, current: Int, top: Int, [Milestone])
  case rewardList(title: String, emptyLabel: String, [RewardRow])
  case statsRow([StatCell])
  case redeemInput(placeholder: String, button: String, success: String, failure: String)
}

struct ScreenTheme: Equatable {
  struct Pair: Equatable {
    let light: String
    let dark: String
  }
  var colors: [String: Pair] = [:]
  var radius: Double = 16
  /// URLs of an uploaded font, when the screen uses one.
  var regularFont: String?
  var boldFont: String?
}

struct ScreenLayout: Equatable {
  var root: ScreenElement?
  /// The Free plan badge, drawn under the screen.
  var badge: String?
  var theme = ScreenTheme()
  var rightToLeft = false

  /// Builds what to show from what the placement route sends.
  /// - Parameters:
  ///   - config: `placement.screen.config`.
  ///   - strings: `placement.strings`: resolved for the locale, tokens still in place.
  ///   - onUnknownNode: called for a node type this SDK does not know (a screen newer than the SDK).
  static func build(
    config: [String: JSONValue], strings: [String: String], data: ScreenData, locale: String?,
    platform: String = "ios", onUnknownNode: ((String) -> Void)? = nil
  ) -> ScreenLayout {
    let builder = Builder(
      strings: strings, data: data, platform: platform, onUnknownNode: onUnknownNode)
    var theme = ScreenTheme()
    let themeConfig = config["theme"]
    for (name, pair) in themeConfig?["colors"]?.objectValue ?? [:] {
      if let light = pair["light"]?.stringValue, let dark = pair["dark"]?.stringValue {
        theme.colors[name] = .init(light: light, dark: dark)
      }
    }
    theme.radius = themeConfig?["radius"]?.doubleValue ?? 16
    if themeConfig?["font"]?["family"]?.stringValue == "custom" {
      theme.regularFont = data.assetURL(themeConfig?["font"]?["regular"]?.stringValue)
      theme.boldFont = data.assetURL(themeConfig?["font"]?["bold"]?.stringValue)
    }
    return ScreenLayout(
      root: config["root"].flatMap(builder.element),
      badge: data.badge ? badgeText : nil, theme: theme,
      rightToLeft: isRightToLeft(locale ?? config["defaultLocale"]?.stringValue ?? "en"))
  }
}

private let aspects = ["1:1": 1.0, "16:9": 16.0 / 9.0, "4:3": 4.0 / 3.0, "3:4": 3.0 / 4.0]

private struct Builder {
  let strings: [String: String]
  let data: ScreenData
  let platform: String
  let onUnknownNode: ((String) -> Void)?

  func t(_ key: JSONValue?) -> String {
    guard let key = key?.stringValue, let text = strings[key] else { return "" }
    return interpolate(text, data.values)
  }

  /// Whether a node is shown on this platform. Offer code redemption exists on iOS only.
  func visible(_ node: JSONValue) -> Bool {
    if node["type"]?.stringValue == "offer_code_redeem_button", platform != "ios" { return false }
    guard let platforms = node["platforms"]?.arrayValue else { return true }
    return platforms.contains(.string(platform))
  }

  func children(_ node: JSONValue) -> [ScreenElement] {
    (node["children"]?.arrayValue ?? []).compactMap(element)
  }

  func element(_ node: JSONValue) -> ScreenElement? {
    guard let type = node["type"]?.stringValue, visible(node) else { return nil }
    let spacing = node["spacing"]?.doubleValue ?? 0
    let padding = node["padding"]?.doubleValue ?? 0
    switch type {
    case "stack":
      return .stack(
        horizontal: node["direction"]?.stringValue == "horizontal", spacing: spacing,
        padding: padding, align: node["align"]?.stringValue ?? "stretch", children(node))
    case "scroll":
      return .scroll(spacing: spacing, padding: padding, children(node))
    case "card":
      return .card(
        spacing: spacing, padding: padding,
        background: node["background"]?.stringValue ?? "surface",
        border: node["border"]?.boolValue ?? false, children(node))
    case "spacer":
      return .spacer(node["size"]?.doubleValue ?? 0)
    case "text":
      let text = t(node["text"])
      guard !text.isEmpty else { return nil }
      return .text(
        text, style: node["style"]?.stringValue ?? "body",
        align: node["align"]?.stringValue ?? "start", color: node["color"]?.stringValue ?? "text")
    case "image":
      return .image(
        url: data.assetURL(node["asset"]?.stringValue), alt: t(node["alt"]),
        aspect: aspects[node["aspect"]?.stringValue ?? ""] ?? 1,
        cover: node["fit"]?.stringValue != "contain", rounded: node["rounded"]?.boolValue ?? false)
    case "lottie":
      return .lottie(
        url: data.assetURL(node["asset"]?.stringValue), loop: node["loop"]?.boolValue ?? true,
        aspect: aspects[node["aspect"]?.stringValue ?? ""] ?? 1)
    case "icon":
      return .icon(
        name: node["name"]?.stringValue ?? "", size: node["size"]?.doubleValue ?? 24,
        color: node["color"]?.stringValue ?? "primary")
    case "code_box":
      return .codeBox(
        label: t(node["label"]), code: data.values["referral.code"] ?? "",
        copiedLabel: t(node["copied_label"]))
    case "share_button":
      return .button(
        label: t(node["label"]), primary: node["style"]?.stringValue != "secondary",
        .share(channel: node["channel"]?.stringValue ?? "system", message: t(node["message"])))
    case "channel_row":
      let channels = (node["channels"]?.arrayValue ?? []).compactMap(\.stringValue)
      return .channelRow(
        channels.map { .init(channel: $0, label: channelLabels[$0] ?? $0) },
        message: t(node["message"]))
    case "progress":
      let current = data.stat(node["metric"]?.stringValue ?? "qualified")
      let milestones = (node["milestones"]?.arrayValue ?? []).map { item -> ScreenElement.Milestone in
        let count = item["count"]?.intValue ?? 0
        return .init(label: t(item["label"]), count: count, reached: current >= count)
      }
      return .progress(
        caption: t(node["caption"]), current: current, top: milestones.last?.count ?? 1,
        milestones)
    case "reward_list":
      let show = node["show"]?.stringValue ?? "all"
      let rewards = data.rewards.filter { show == "all" || $0.state == show }
      return .rewardList(
        title: t(node["title"]), emptyLabel: rewards.isEmpty ? t(node["empty_label"]) : "",
        rewards.map { .init(id: $0.id, label: $0.label, issued: $0.state == "issued") })
    case "stats_row":
      return .statsRow(
        (node["stats"]?.arrayValue ?? []).map {
          .init(label: t($0["label"]), value: String(data.stat($0["stat"]?.stringValue ?? "")))
        })
    case "redeem_code_input":
      return .redeemInput(
        placeholder: t(node["placeholder"]), button: t(node["button_label"]),
        success: t(node["success_label"]), failure: t(node["error_label"]))
    case "offer_code_redeem_button":
      // Only when the person has a code to redeem.
      guard let code = data.offerCode, !code.isEmpty else { return nil }
      return .button(label: t(node["label"]), primary: false, .redeemOfferCode(code))
    default:
      // A screen made for a newer SDK. Skip what we do not know and keep going.
      onUnknownNode?(type)
      return nil
    }
  }
}

/// What a person can read and do, in reading order: the form the conformance fixtures use.
struct ScreenOutline: Equatable, Decodable {
  var texts: [String] = []
  var actions: [String] = []
  var assets: [String] = []
}

extension ScreenLayout {
  var outline: ScreenOutline {
    var result = ScreenOutline()
    func say(_ text: String) {
      let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
      if !trimmed.isEmpty { result.texts.append(trimmed) }
    }
    func visit(_ element: ScreenElement) {
      switch element {
      case .stack(_, _, _, _, let children), .scroll(_, _, let children),
        .card(_, _, _, _, let children):
        children.forEach(visit)
      case .text(let text, _, _, _):
        say(text)
      case .image(let url, _, _, _, _), .lottie(let url, _, _):
        if let url { result.assets.append(url) }
      case .codeBox(let label, let code, _):
        say(label)
        say(code)
        result.actions.append("copy")
      case .button(let label, _, let action):
        say(label)
        result.actions.append(action.name)
      case .channelRow(let channels, _):
        for channel in channels {
          say(channel.label)
          result.actions.append("share:\(channel.channel)")
        }
      case .progress(let caption, let current, let top, let milestones):
        if !caption.isEmpty {
          say(caption)
          say(progressCounter(current, top))
        }
        for milestone in milestones {
          say(milestone.label)
          say(String(milestone.count))
        }
      case .rewardList(let title, let emptyLabel, let rewards):
        say(title)
        say(emptyLabel)
        rewards.forEach { say($0.label) }
      case .statsRow(let stats):
        for stat in stats {
          say(stat.label)
          say(stat.value)
        }
      case .redeemInput(_, let button, _, _):
        say(button)
        result.actions.append("redeem")
      case .spacer, .icon:
        break
      }
    }
    if let root { visit(root) }
    // The Free plan badge comes last, under whatever the screen shows.
    if let badge { say(badge) }
    return result
  }
}

func progressCounter(_ current: Int, _ top: Int) -> String { "\(current) / \(top)" }
