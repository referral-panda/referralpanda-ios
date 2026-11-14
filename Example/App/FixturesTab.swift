import ReferralPanda
import ReferralPandaUI
import SwiftUI

/// The shared conformance fixtures (sdks/conformance/expected), drawn by the real renderer.
/// Needs no backend: the actions are answered here.
private struct Fixture: Decodable, Identifiable {
  struct Input: Decodable {
    let config: [String: JSONValue]
    let strings: [String: String]
    let locale: String
    let data: ScreenData
  }
  let name: String
  let input: Input
  var id: String { name }
}

private func loadFixtures() -> [Fixture] {
  guard let folder = Bundle.main.url(forResource: "expected", withExtension: nil),
    let files = try? FileManager.default.contentsOfDirectory(
      at: folder, includingPropertiesForKeys: nil)
  else { return [] }
  return files.filter { $0.pathExtension == "json" }
    .compactMap { try? JSONDecoder().decode(Fixture.self, from: Data(contentsOf: $0)) }
    .sorted { $0.name < $1.name }
}

struct FixturesTab: View {
  private let fixtures = loadFixtures()

  var body: some View {
    NavigationView {
      List(fixtures) { fixture in
        NavigationLink(fixture.name) { FixtureScreen(fixture: fixture) }
      }
      .navigationTitle("Fixtures")
    }
    .navigationViewStyle(.stack)
  }
}

private struct FixtureScreen: View {
  let fixture: Fixture
  @EnvironmentObject private var session: Session
  @State private var dark = false
  @State private var sharing: String?

  var body: some View {
    ScreenView(
      config: fixture.input.config, strings: fixture.input.strings, data: fixture.input.data,
      locale: fixture.input.locale, colorScheme: dark ? .dark : .light, actions: actions
    )
    .navigationTitle(fixture.name)
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      Button(dark ? "Light" : "Dark") { dark.toggle() }.accessibilityIdentifier("toggle-scheme")
    }
    .sheet(item: $sharing) { ShareSheet(text: $0) }
  }

  private var actions: ScreenActions {
    var actions = ScreenActions()
    actions.copy = { text in
      UIPasteboard.general.string = text
      session.log("fixture copy: \(text)")
    }
    actions.share = { request in
      session.log("fixture share: \(request.channel)")
      sharing = request.message.isEmpty ? request.link : request.message
    }
    // Any code starting with "OK" is accepted.
    actions.redeem = { code in
      session.log("fixture redeem: \(code)")
      try? await Task.sleep(nanoseconds: 400_000_000)
      return code.uppercased().hasPrefix("OK")
    }
    actions.redeemOfferCode = { _ in
      let shown = await ReferralPanda.presentOfferCodeRedemption()
      session.log("offer code sheet: \(shown ? "shown" : "not available")")
    }
    return actions
  }
}

extension String: @retroactive Identifiable {
  public var id: String { self }
}

private struct ShareSheet: UIViewControllerRepresentable {
  let text: String
  func makeUIViewController(context: Context) -> UIActivityViewController {
    UIActivityViewController(activityItems: [text], applicationActivities: nil)
  }
  func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
