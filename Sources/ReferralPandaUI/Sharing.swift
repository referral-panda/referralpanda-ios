#if canImport(SwiftUI)
  import ReferralPanda
  import SwiftUI

  #if os(iOS)
    import StoreKit
    import UIKit
  #endif

  // The parts of the SDK that need the screen: the share sheet, the clipboard, Apple's offer
  // code sheet and showing the referral screen over the app.
  extension ReferralPanda {
    /// Opens the system share sheet with the user's link, and records the share.
    /// - Returns: true when the person shared, false when they closed the sheet.
    @MainActor @discardableResult
    public static func share(channel: String? = nil, message: String? = nil) async throws -> Bool {
      let channel = channel ?? "system"
      let content = try await getShareContent(channel: channel, message: message)
      #if os(iOS)
        guard let presenter = topViewController() else {
          throw ReferralPandaError(.unavailable, "There is no window to show the share sheet in.")
        }
        trackShare(channel: channel)
        return await withCheckedContinuation { continuation in
          let sheet = UIActivityViewController(
            activityItems: [content.message], applicationActivities: nil)
          sheet.completionWithItemsHandler = { _, completed, _, _ in
            continuation.resume(returning: completed)
          }
          // iPad shows it as a popover, which needs somewhere to point.
          sheet.popoverPresentationController?.sourceView = presenter.view
          sheet.popoverPresentationController?.sourceRect = CGRect(
            x: presenter.view.bounds.midX, y: presenter.view.bounds.midY, width: 0, height: 0)
          sheet.popoverPresentationController?.permittedArrowDirections = []
          presenter.present(sheet, animated: true)
        }
      #else
        throw ReferralPandaError(.unavailable, "Sharing is not available on this platform.")
      #endif
    }

    /// iOS: opens Apple's own sheet for redeeming an offer code.
    /// - Returns: false when the sheet is not available here.
    @MainActor @discardableResult
    public static func presentOfferCodeRedemption() async -> Bool {
      #if os(iOS) && !targetEnvironment(macCatalyst)
        if #available(iOS 16.0, *), let scene = activeScene() {
          do {
            try await AppStore.presentOfferCodeRedeemSheet(in: scene)
            return true
          } catch {
            return false
          }
        }
        SKPaymentQueue.default().presentCodeRedemptionSheet()
        return true
      #else
        return false
      #endif
    }

    /// Shows the referral screen over the app, as a sheet with a close button.
    /// - Parameter closeLabel: read by screen readers and shown on the button. Pass your own translation.
    /// - Returns: false when there is no window to show it in.
    @MainActor @discardableResult
    public static func presentReferralScreen(
      placement: String, locale: String? = nil, closeLabel: String = "Close"
    ) -> Bool {
      #if os(iOS)
        guard let presenter = topViewController() else { return false }
        let host = UIHostingController(
          rootView: PresentedScreen(placement: placement, locale: locale, closeLabel: closeLabel))
        host.modalPresentationStyle = .pageSheet
        presenter.present(host, animated: true)
        return true
      #else
        return false
      #endif
    }

    @MainActor static func copyToClipboard(_ text: String) {
      #if os(iOS)
        UIPasteboard.general.string = text
      #endif
    }

    /// Opens Messages or WhatsApp with the text ready to send. False when it could not.
    @MainActor static func open(channel: String, text: String) async -> Bool {
      #if os(iOS)
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-_.~")
        let encoded = text.addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
        let addresses =
          channel == "whatsapp"
          ? ["whatsapp://send?text=\(encoded)", "https://wa.me/?text=\(encoded)"]
          : ["sms:&body=\(encoded)"]
        for address in addresses {
          if let url = URL(string: address), await UIApplication.shared.open(url) { return true }
        }
      #endif
      return false
    }

    #if os(iOS)
      @MainActor private static func activeScene() -> UIWindowScene? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        return scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
      }

      @MainActor private static func topViewController() -> UIViewController? {
        let windows = activeScene()?.windows ?? []
        var top = (windows.first { $0.isKeyWindow } ?? windows.first)?.rootViewController
        while let presented = top?.presentedViewController { top = presented }
        return top
      }
    #endif
  }

  private struct PresentedScreen: View {
    let placement: String
    let locale: String?
    let closeLabel: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
      VStack(spacing: 0) {
        HStack {
          Spacer()
          Button(closeLabel) { dismiss() }
            .font(.system(size: 16, weight: .semibold))
            .foregroundColor(.primary)
            .frame(minWidth: 44, minHeight: 44)
            .accessibilityIdentifier("rp-close")
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
        ReferralView(placement: placement, locale: locale)
          .frame(maxWidth: .infinity, maxHeight: .infinity)
      }
    }
  }
#endif
