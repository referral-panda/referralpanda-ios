#if canImport(SwiftUI)
  import ReferralPanda
  import SwiftUI

  #if canImport(UIKit)
    import UIKit
  #endif

  /// What the person did. The screen draws and reports; it makes no requests itself.
  public struct ScreenActions {
    public struct ShareRequest: Sendable {
      /// "system", "messages", "whatsapp", "copy_link" or "more".
      public let channel: String
      /// The screen's share message, with the plain link in it. May be empty.
      public let message: String
      public let link: String
    }

    public var copy: (@MainActor (String) async -> Void)?
    public var share: (@MainActor (ShareRequest) async -> Void)?
    /// Returns true if the code was accepted.
    public var redeem: (@MainActor (String) async -> Bool)?
    public var redeemOfferCode: (@MainActor (String) async -> Void)?

    public init() {}
  }

  /// Optional pieces an app can add to the renderer.
  public enum ReferralPandaUI {
    /// Draws a Lottie animation. The SDK has no dependencies, so it cannot draw one itself:
    /// set this once at app start if your screens use animations and your app has a Lottie
    /// library. Arguments: the file, whether to loop, whether to play (false when the person
    /// has asked for reduced motion).
    @MainActor public static var lottieView: ((URL, _ loop: Bool, _ play: Bool) -> AnyView)?
  }

  /// Renders a ReferralPanda screen with SwiftUI. It draws what it is given and reports what
  /// the person does through `actions`, so it can be used with data from anywhere. Most apps
  /// use `ReferralView(placement:)`, which loads the screen and wires the actions.
  public struct ScreenView: View {
    private let layout: ScreenLayout
    private let actions: ScreenActions
    private let forcedScheme: ColorScheme?
    private let link: String

    @Environment(\.colorScheme) private var deviceScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .body) private var textScale: CGFloat = 100
    @StateObject private var fonts = FontLoader()

    /// - Parameters:
    ///   - config: `placement.screen.config`.
    ///   - strings: `placement.strings`: resolved for the locale, tokens still in place.
    ///   - locale: `placement.locale`. Decides right-to-left layout.
    ///   - colorScheme: follows the device unless set.
    public init(
      config: [String: JSONValue], strings: [String: String], data: ScreenData,
      locale: String? = nil, colorScheme: ColorScheme? = nil,
      actions: ScreenActions = ScreenActions(), onUnknownNode: ((String) -> Void)? = nil
    ) {
      layout = ScreenLayout.build(
        config: config, strings: strings, data: data, locale: locale, platform: "ios",
        onUnknownNode: onUnknownNode)
      self.actions = actions
      forcedScheme = colorScheme
      link = data.values["referral.link"] ?? ""
    }

    public init(
      placement: Placement, colorScheme: ColorScheme? = nil,
      actions: ScreenActions = ScreenActions()
    ) {
      self.init(
        config: placement.screen.config, strings: placement.strings,
        data: ScreenData(placement), locale: placement.locale, colorScheme: colorScheme,
        actions: actions)
    }

    public var body: some View {
      let context = RenderContext(
        theme: layout.theme, dark: (forcedScheme ?? deviceScheme) == .dark,
        // Large text stays inside its box when the person has set a very large system font.
        scale: min(textScale / 100, 1.6), regularFont: fonts.regular, boldFont: fonts.bold,
        reduceMotion: reduceMotion, actions: actions, link: link)
      VStack(spacing: 0) {
        Group {
          if let root = layout.root { ElementView(element: root, context: context, fill: true) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        if let badge = layout.badge {
          // Free plan: the screen takes the room there is and the badge sits under it.
          Words(badge, style: "caption", color: "muted", context: context)
            .multilineTextAlignment(.center)
            .padding(.top, 8)
            .padding(.bottom, 12)
        }
      }
      .background(context.color("background").ignoresSafeArea())
      .environment(\.layoutDirection, layout.rightToLeft ? .rightToLeft : .leftToRight)
      .task(id: layout.theme.regularFont) {
        await fonts.load(regular: layout.theme.regularFont, bold: layout.theme.boldFont)
      }
    }
  }

  struct RenderContext {
    let theme: ScreenTheme
    let dark: Bool
    let scale: CGFloat
    let regularFont: String?
    let boldFont: String?
    let reduceMotion: Bool
    let actions: ScreenActions
    let link: String

    func color(_ name: String) -> Color {
      let pair = theme.colors[name]
      return Color(hex: (dark ? pair?.dark : pair?.light) ?? "#808080")
    }
    var radius: CGFloat { theme.radius }

    func font(_ size: CGFloat, _ weight: Font.Weight = .regular, mono: Bool = false) -> Font {
      let scaled = size * scale
      if mono { return .system(size: scaled, weight: weight, design: .monospaced) }
      let bold = weight != .regular
      if let name = bold ? (boldFont ?? regularFont) : regularFont {
        // An uploaded bold file already is bold: do not thicken it again.
        let font = Font.custom(name, fixedSize: scaled)
        return bold && boldFont == nil ? font.weight(weight) : font
      }
      return .system(size: scaled, weight: weight)
    }
  }

  private struct TextStyle {
    let size: CGFloat
    let line: CGFloat
    let weight: Font.Weight
    let kerning: CGFloat
  }
  private let textStyles = [
    "title": TextStyle(size: 28, line: 33, weight: .bold, kerning: -0.56),
    "heading": TextStyle(size: 20, line: 25, weight: .semibold, kerning: -0.2),
    "body": TextStyle(size: 16, line: 23, weight: .regular, kerning: 0),
    "caption": TextStyle(size: 13, line: 18, weight: .regular, kerning: 0),
  ]

  /// Text in the screen's font. Every piece of text goes through here.
  private struct Words: View {
    let text: String
    let style: TextStyle
    let weight: Font.Weight
    let color: String
    let context: RenderContext

    init(
      _ text: String, style: String, weight: Font.Weight? = nil, color: String,
      context: RenderContext
    ) {
      self.text = text
      let chosen = textStyles[style] ?? TextStyle(size: 16, line: 23, weight: .regular, kerning: 0)
      self.style = chosen
      self.weight = weight ?? chosen.weight
      self.color = color
      self.context = context
    }

    var body: some View {
      Text(text)
        .font(context.font(style.size, weight))
        .kerning(style.kerning)
        // The system font's own line is about 1.2 times its size.
        .lineSpacing(max(0, (style.line - style.size * 1.2) * context.scale))
        .foregroundColor(context.color(color))
        .fixedSize(horizontal: false, vertical: true)
    }
  }

  private struct PressStyle: ButtonStyle {
    var pressed = 0.7
    func makeBody(configuration: Configuration) -> some View {
      configuration.label.opacity(configuration.isPressed ? pressed : 1)
    }
  }

  private struct ActionButton: View {
    let label: String
    let primary: Bool
    let action: String
    var compact = false
    var disabled = false
    let fill: Bool
    let context: RenderContext
    let run: @MainActor () async -> Void

    var body: some View {
      Button {
        Task { await run() }
      } label: {
        Text(label)
          .font(context.font(17, .semibold))
          .multilineTextAlignment(.center)
          .foregroundColor(context.color(primary ? "on_primary" : "text"))
          .padding(.vertical, compact ? 0 : 14)
          .padding(.horizontal, 18)
          .frame(maxWidth: fill ? .infinity : nil, minHeight: compact ? 48 : 52)
          .background(
            RoundedRectangle(cornerRadius: context.radius, style: .continuous)
              .fill(primary ? context.color("primary") : Color.clear)
          )
          .overlay(
            RoundedRectangle(cornerRadius: context.radius, style: .continuous)
              .strokeBorder(context.color("border"), lineWidth: primary ? 0 : 1)
          )
          .contentShape(Rectangle())
      }
      .buttonStyle(PressStyle())
      .disabled(disabled)
      .opacity(disabled ? 0.7 : 1)
      .accessibilityIdentifier("rp-action:\(action)")
    }
  }

  private func announce(_ text: String) {
    #if canImport(UIKit) && !os(watchOS)
      if !text.isEmpty { UIAccessibility.post(notification: .announcement, argument: text) }
    #endif
  }

  private struct CodeBox: View {
    let label: String
    let code: String
    let copiedLabel: String
    let fill: Bool
    let context: RenderContext
    @State private var copied = false

    var body: some View {
      Button {
        guard let copy = context.actions.copy else { return }
        Task {
          await copy(code)
          copied = true
          announce(copiedLabel)
          try? await Task.sleep(nanoseconds: 2_000_000_000)
          copied = false
        }
      } label: {
        VStack(spacing: 6) {
          if !label.isEmpty { Words(label, style: "caption", color: "muted", context: context) }
          if !code.isEmpty {
            Text(code)
              // The code keeps its size: it must fit on one line.
              .font(.system(size: 32 * min(context.scale, 1.2), weight: .bold, design: .monospaced))
              .kerning(4.5)
              .lineLimit(1)
              .minimumScaleFactor(0.5)
              .foregroundColor(context.color("text"))
          }
          Words(copied ? copiedLabel : " ", style: "caption", color: "success", context: context)
            .frame(minHeight: 18)
        }
        .padding(.top, 18)
        .padding(.bottom, 14)
        .padding(.horizontal, 16)
        .frame(maxWidth: fill ? .infinity : nil)
        .background(
          RoundedRectangle(cornerRadius: context.radius, style: .continuous)
            .fill(context.color("surface"))
        )
        .overlay(
          RoundedRectangle(cornerRadius: context.radius, style: .continuous)
            .strokeBorder(context.color("border"), lineWidth: 1)
        )
      }
      .buttonStyle(PressStyle(pressed: 0.8))
      .accessibilityElement(children: .ignore)
      .accessibilityAddTraits(.isButton)
      .accessibilityLabel(
        [label, code.map(String.init).joined(separator: " ")].filter { !$0.isEmpty }
          .joined(separator: ", ")
      )
      .accessibilityIdentifier("rp-action:copy")
    }
  }

  private struct RedeemInput: View {
    enum Phase { case idle, busy, accepted, refused }
    let placeholder: String
    let button: String
    let success: String
    let failure: String
    let context: RenderContext
    @State private var code = ""
    @State private var phase = Phase.idle

    private func submit() async {
      let entered = code.trimmingCharacters(in: .whitespacesAndNewlines)
      guard let redeem = context.actions.redeem, !entered.isEmpty, phase != .busy else { return }
      phase = .busy
      let accepted = await redeem(entered)
      phase = accepted ? .accepted : .refused
      announce(accepted ? success : failure)
    }

    var body: some View {
      let message = phase == .accepted ? success : phase == .refused ? failure : ""
      VStack(alignment: .leading, spacing: 8) {
        HStack(spacing: 8) {
          field
            .font(context.font(17, mono: true))
            .foregroundColor(context.color("text"))
            .padding(.horizontal, 14)
            .frame(minHeight: 48)
            .background(
              RoundedRectangle(cornerRadius: context.radius, style: .continuous)
                .fill(context.color("background"))
            )
            .overlay(
              RoundedRectangle(cornerRadius: context.radius, style: .continuous)
                .strokeBorder(context.color("border"), lineWidth: 1)
            )
            .accessibilityLabel(placeholder.isEmpty ? button : placeholder)
          ActionButton(
            label: button, primary: true, action: "redeem", compact: true,
            disabled: phase == .busy, fill: false, context: context, run: submit)
        }
        if !message.isEmpty {
          Words(
            message, style: "caption", color: phase == .accepted ? "success" : "muted",
            context: context)
        }
      }
    }

    @ViewBuilder private var field: some View {
      let input = TextField(
        "", text: $code,
        prompt: Text(placeholder).foregroundColor(context.color("muted"))
      )
      .textFieldStyle(.plain)
      .disableAutocorrection(true)
      .onSubmit { Task { await submit() } }
      .onChange(of: code) { value in
        // Codes are upper case, whatever keyboard typed them.
        let cleaned = String(value.uppercased().prefix(20))
        if cleaned != value { code = cleaned }
      }
      #if os(iOS)
        input.textInputAutocapitalization(.characters).submitLabel(.done)
      #else
        input
      #endif
    }
  }

  private struct RemoteImage: View {
    let url: String?
    let alt: String
    let aspect: Double
    let cover: Bool
    let rounded: Bool
    let context: RenderContext

    var body: some View {
      context.color("surface")
        .aspectRatio(aspect, contentMode: .fit)
        .overlay(
          Group {
            if let url, let address = URL(string: url) {
              AsyncImage(url: address) { image in
                image.resizable().aspectRatio(contentMode: cover ? .fill : .fit)
              } placeholder: {
                Color.clear
              }
            }
          }
        )
        .clipShape(
          RoundedRectangle(cornerRadius: rounded ? context.radius : 0, style: .continuous)
        )
        .accessibilityHidden(alt.isEmpty)
        .accessibilityLabel(alt)
    }
  }

  struct ElementView: View {
    let element: ScreenElement
    let context: RenderContext
    /// True when the parent stretches its children to its own width.
    let fill: Bool

    private func list(_ children: [ScreenElement], fill: Bool) -> some View {
      ForEach(Array(children.enumerated()), id: \.offset) { item in
        ElementView(element: item.element, context: context, fill: fill)
      }
    }

    var body: some View {
      switch element {
      case .stack(let horizontal, let spacing, let padding, let align, let children):
        if horizontal {
          HStack(
            alignment: align == "start" ? .top : align == "end" ? .bottom : .center,
            spacing: spacing
          ) { list(children, fill: false) }
          .padding(padding)
          .frame(maxWidth: fill ? .infinity : nil, alignment: .leading)
        } else {
          VStack(
            alignment: align == "center" ? .center : align == "end" ? .trailing : .leading,
            spacing: spacing
          ) { list(children, fill: align == "stretch") }
          .padding(padding)
          .frame(
            maxWidth: fill ? .infinity : nil,
            alignment: align == "center" ? .center : align == "end" ? .trailing : .leading)
        }
      case .scroll(let spacing, let padding, let children):
        ScrollView(showsIndicators: false) {
          // Children stretch; one with a fixed size (an icon) sits at the leading edge.
          VStack(alignment: .leading, spacing: spacing) { list(children, fill: true) }
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
      case .card(let spacing, let padding, let background, let border, let children):
        VStack(alignment: .leading, spacing: spacing) { list(children, fill: true) }
          .padding(padding)
          .frame(maxWidth: fill ? .infinity : nil, alignment: .leading)
          .background(
            RoundedRectangle(cornerRadius: context.radius, style: .continuous)
              .fill(context.color(background))
          )
          .overlay(
            RoundedRectangle(cornerRadius: context.radius, style: .continuous)
              .strokeBorder(context.color("border"), lineWidth: border ? 1 : 0)
          )
      case .spacer(let size):
        Color.clear.frame(width: size, height: size)
      case .text(let text, let style, let align, let color):
        let heading = style == "title" || style == "heading"
        Words(text, style: style, color: color, context: context)
          .multilineTextAlignment(
            align == "center" ? .center : align == "end" ? .trailing : .leading
          )
          .frame(
            maxWidth: fill ? .infinity : nil,
            alignment: align == "center" ? .center : align == "end" ? .trailing : .leading
          )
          .accessibilityAddTraits(heading ? .isHeader : [])
      case .image(let url, let alt, let aspect, let cover, let rounded):
        RemoteImage(
          url: url, alt: alt, aspect: aspect, cover: cover, rounded: rounded, context: context)
      case .lottie(let url, let loop, let aspect):
        Color.clear
          .aspectRatio(aspect, contentMode: .fit)
          .overlay(
            Group {
              if let url, let address = URL(string: url), let draw = ReferralPandaUI.lottieView {
                draw(address, loop, !context.reduceMotion)
              }
            }
          )
          .accessibilityHidden(true)
      case .icon(let name, let size, let color):
        IconView(name: name, size: size, color: context.color(color))
      case .codeBox(let label, let code, let copiedLabel):
        CodeBox(label: label, code: code, copiedLabel: copiedLabel, fill: fill, context: context)
      case .button(let label, let primary, let action):
        ActionButton(
          label: label, primary: primary, action: action.name, fill: fill, context: context
        ) {
          switch action {
          case .share(let channel, let message):
            await context.actions.share?(
              .init(channel: channel, message: message, link: context.link))
          case .redeemOfferCode(let code):
            await context.actions.redeemOfferCode?(code)
          }
        }
      case .channelRow(let channels, let message):
        HStack(spacing: 8) {
          ForEach(Array(channels.enumerated()), id: \.offset) { item in
            Button {
              Task {
                await context.actions.share?(
                  .init(channel: item.element.channel, message: message, link: context.link))
              }
            } label: {
              VStack(spacing: 6) {
                IconView(
                  name: "channel:\(item.element.channel)", size: 24,
                  color: context.color("primary"))
                Text(item.element.label)
                  .font(context.font(12))
                  .lineLimit(1)
                  .foregroundColor(context.color("text"))
              }
              .padding(.vertical, 12)
              .padding(.horizontal, 4)
              .frame(maxWidth: .infinity)
              .overlay(
                RoundedRectangle(cornerRadius: context.radius, style: .continuous)
                  .strokeBorder(context.color("border"), lineWidth: 1)
              )
              .contentShape(Rectangle())
            }
            .buttonStyle(PressStyle())
            .accessibilityLabel(item.element.label)
            .accessibilityIdentifier("rp-action:share:\(item.element.channel)")
          }
        }
      case .progress(let caption, let current, let top, let milestones):
        VStack(alignment: .leading, spacing: 12) {
          if !caption.isEmpty {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
              Words(caption, style: "caption", color: "muted", context: context)
              Spacer(minLength: 0)
              Words(
                progressCounter(current, top), style: "caption", weight: .semibold, color: "text",
                context: context
              ).monospacedDigit()
            }
          }
          Capsule()
            .fill(context.color("border"))
            .frame(height: 8)
            .overlay(
              GeometryReader { box in
                Capsule()
                  .fill(context.color("primary"))
                  .frame(
                    width: box.size.width
                      * max(0, min(1, Double(current) / Double(max(top, 1)))))
              }
            )
            .accessibilityElement()
            .accessibilityValue("\(min(current, top)) / \(top)")
          VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(milestones.enumerated()), id: \.offset) { item in
              let milestone = item.element
              HStack(spacing: 10) {
                IconView(
                  name: milestone.reached ? "check" : "lock", size: 16,
                  color: context.color(milestone.reached ? "success" : "muted"))
                Words(
                  milestone.label, style: "body", color: milestone.reached ? "text" : "muted",
                  context: context
                ).frame(maxWidth: .infinity, alignment: .leading)
                Words(
                  String(milestone.count), style: "caption", color: "muted", context: context
                ).monospacedDigit()
              }
            }
          }
        }
        .frame(maxWidth: fill ? .infinity : nil, alignment: .leading)
      case .rewardList(let title, let emptyLabel, let rewards):
        VStack(alignment: .leading, spacing: 10) {
          if !title.isEmpty {
            Words(title, style: "heading", color: "text", context: context)
              .accessibilityAddTraits(.isHeader)
          }
          if rewards.isEmpty {
            if !emptyLabel.isEmpty {
              Words(emptyLabel, style: "body", color: "muted", context: context)
            }
          } else {
            VStack(spacing: 8) {
              ForEach(rewards, id: \.id) { reward in
                HStack(spacing: 10) {
                  IconView(
                    name: reward.issued ? "check" : "clock", size: 16,
                    color: context.color(reward.issued ? "success" : "muted"))
                  Words(reward.label, style: "body", color: "text", context: context)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.vertical, 12)
                .padding(.horizontal, 14)
                .background(
                  RoundedRectangle(cornerRadius: context.radius, style: .continuous)
                    .fill(context.color("surface"))
                )
              }
            }
          }
        }
        .frame(maxWidth: fill ? .infinity : nil, alignment: .leading)
      case .statsRow(let stats):
        HStack(alignment: .top, spacing: 8) {
          ForEach(Array(stats.enumerated()), id: \.offset) { item in
            // Read as "label: value", shown as the value above its label.
            VStack(alignment: .leading, spacing: 2) {
              Text(item.element.value)
                .font(context.font(24, .bold))
                .monospacedDigit()
                .foregroundColor(context.color("text"))
              // A long label in a narrow cell gets a little smaller before it breaks a word.
              Words(item.element.label, style: "caption", color: "muted", context: context)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(
              RoundedRectangle(cornerRadius: context.radius, style: .continuous)
                .fill(context.color("surface"))
            )
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(item.element.label): \(item.element.value)")
          }
        }
        .fixedSize(horizontal: false, vertical: true)
      case .redeemInput(let placeholder, let button, let success, let failure):
        RedeemInput(
          placeholder: placeholder, button: button, success: success, failure: failure,
          context: context)
      }
    }
  }

  extension Color {
    /// "#RGB", "#RRGGBB" or "#RRGGBBAA". Anything else is mid grey.
    init(hex: String) {
      var digits = hex.trimmingCharacters(in: .whitespaces)
      if digits.hasPrefix("#") { digits.removeFirst() }
      if digits.count == 3 { digits = digits.map { "\($0)\($0)" }.joined() }
      guard digits.count == 6 || digits.count == 8, let value = UInt64(digits, radix: 16) else {
        self.init(.sRGB, red: 0.5, green: 0.5, blue: 0.5, opacity: 1)
        return
      }
      let rgb = digits.count == 8 ? value >> 8 : value
      self.init(
        .sRGB, red: Double((rgb >> 16) & 0xFF) / 255, green: Double((rgb >> 8) & 0xFF) / 255,
        blue: Double(rgb & 0xFF) / 255,
        opacity: digits.count == 8 ? Double(value & 0xFF) / 255 : 1)
    }
  }
#endif
