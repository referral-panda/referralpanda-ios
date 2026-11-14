#if canImport(SwiftUI)
  import ReferralPanda
  import SwiftUI

  #if canImport(UIKit)
    import UIKit
  #endif

  @MainActor
  private final class PlacementModel: ObservableObject {
    @Published var placement: Placement?
    @Published var loading = true
    private var token: ListenerToken?
    private var seen = ""

    func start(key: String, locale: String?, onError: ((Error) -> Void)?) async {
      if token == nil {
        token = try? await ReferralPanda.addListener { [weak self] event in
          Task { @MainActor in
            switch event {
            case .placementUpdated(let fresh) where fresh.key == key: self?.show(fresh)
            case .userChanged: await self?.load(key: key, locale: locale, refresh: false, onError: nil)
            default: break
            }
          }
        }
      }
      await load(key: key, locale: locale, refresh: false, onError: onError)
    }

    func load(key: String, locale: String?, refresh: Bool, onError: ((Error) -> Void)?) async {
      do {
        show(try await ReferralPanda.getPlacement(key, locale: locale, refresh: refresh))
      } catch {
        onError?(error)
      }
      loading = false
    }

    private func show(_ fresh: Placement) {
      placement = fresh
      // Counted once per screen version shown.
      let shown = "\(fresh.key):\(fresh.screen.id):\(fresh.screen.version)"
      guard seen != shown else { return }
      seen = shown
      ReferralPanda.track(
        "screen_viewed",
        properties: [
          "placement": .string(fresh.key), "screen_id": .string(fresh.screen.id),
          "version": .int(fresh.screen.version),
        ])
    }

    func stop() {
      guard let token else { return }
      self.token = nil
      Task { await ReferralPanda.removeListener(token) }
    }
  }

  /// The referral screen you designed in the dashboard, anywhere in your app. It fills the
  /// space it is given. Publishing a new version in the dashboard changes it within a minute.
  ///
  /// It uses only the public SDK calls: what this view does, an app can do with the same calls.
  public struct ReferralView<Loading: View, Fallback: View>: View {
    private let key: String
    private let locale: String?
    private let colorScheme: ColorScheme?
    private let loading: Loading
    private let fallback: Fallback
    private var onShare: ((String) -> Void)?
    private var onCodeRedeemed: ((RedeemResult) -> Void)?
    private var onError: ((Error) -> Void)?
    @StateObject private var model = PlacementModel()

    /// - Parameters:
    ///   - placement: the placement key from the dashboard, for example "settings_referral".
    ///   - locale: follows the device unless set.
    ///   - colorScheme: follows the device unless set.
    ///   - loading: shown until the screen has loaded for the first time.
    ///   - fallback: shown when the placement has no published screen, or it could not be loaded.
    public init(
      placement: String, locale: String? = nil, colorScheme: ColorScheme? = nil,
      @ViewBuilder loading: () -> Loading, @ViewBuilder fallback: () -> Fallback
    ) {
      key = placement
      self.locale = locale
      self.colorScheme = colorScheme
      self.loading = loading()
      self.fallback = fallback()
    }

    public func onShare(_ action: @escaping (_ channel: String) -> Void) -> Self {
      var copy = self
      copy.onShare = action
      return copy
    }
    public func onCodeRedeemed(_ action: @escaping (RedeemResult) -> Void) -> Self {
      var copy = self
      copy.onCodeRedeemed = action
      return copy
    }
    public func onError(_ action: @escaping (Error) -> Void) -> Self {
      var copy = self
      copy.onError = action
      return copy
    }

    public var body: some View {
      Group {
        if let placement = model.placement {
          ScreenView(placement: placement, colorScheme: colorScheme, actions: actions(placement))
        } else if model.loading {
          loading
        } else {
          fallback
        }
      }
      .task(id: "\(key)|\(locale ?? "")") {
        await model.start(key: key, locale: locale, onError: onError)
      }
      .onDisappear { model.stop() }
    }

    private func actions(_ placement: Placement) -> ScreenActions {
      var actions = ScreenActions()
      actions.copy = { code in
        ReferralPanda.copyToClipboard(code)
        ReferralPanda.track("code_copied", properties: ["placement": .string(placement.key)])
      }
      actions.share = { request in
        do {
          // The screen's message already has the plain link in it. Hand it back as a token so
          // the link that goes out carries the channel.
          let template =
            request.link.isEmpty
            ? request.message
            : request.message.replacingOccurrences(of: request.link, with: "{{referral.link}}")
          let message = template.isEmpty ? nil : template
          switch request.channel {
          case "system", "more":
            try await ReferralPanda.share(channel: request.channel, message: message)
          case "copy_link":
            let content = try await ReferralPanda.getShareContent(
              channel: request.channel, message: message)
            ReferralPanda.copyToClipboard(content.link)
            ReferralPanda.trackShare(channel: request.channel)
          default:
            let content = try await ReferralPanda.getShareContent(
              channel: request.channel, message: message)
            if await ReferralPanda.open(channel: request.channel, text: content.message) {
              ReferralPanda.trackShare(channel: request.channel)
            } else {
              // The app is not installed: the system sheet instead. share() records it.
              try await ReferralPanda.share(channel: request.channel, message: message)
            }
          }
          onShare?(request.channel)
        } catch {
          onError?(error)
        }
      }
      actions.redeem = { code in
        do {
          let result = try await ReferralPanda.redeemCode(code)
          onCodeRedeemed?(result)
          guard case .redeemed = result else { return false }
          await model.load(key: key, locale: locale, refresh: true, onError: nil)
          return true
        } catch {
          onError?(error)
          return false
        }
      }
      actions.redeemOfferCode = { code in
        // Apple's own sheet. The code never unlocks anything by itself.
        if await !ReferralPanda.presentOfferCodeRedemption() {
          ReferralPanda.copyToClipboard(code)
        }
      }
      return actions
    }
  }

  extension ReferralView where Loading == EmptyView, Fallback == EmptyView {
    public init(placement: String, locale: String? = nil, colorScheme: ColorScheme? = nil) {
      self.init(
        placement: placement, locale: locale, colorScheme: colorScheme,
        loading: { EmptyView() }, fallback: { EmptyView() })
    }
  }
#endif
