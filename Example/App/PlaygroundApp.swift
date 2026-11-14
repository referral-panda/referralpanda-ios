import ReferralPanda
import ReferralPandaUI
import SwiftUI

let placementKey = "settings_referral"

/// The SDK's state as the app sees it, and a log of what the SDK told the app.
@MainActor
final class Session: ObservableObject {
  @Published var configured = false
  @Published var userID: String?
  @Published var lines: [String] = []
  @Published var problem: String?

  init() {
    let info = Bundle.main.infoDictionary ?? [:]
    let key = (info["RPAPIKey"] as? String) ?? ""
    guard !key.isEmpty else {
      log("No API key. Run scripts/configure.sh. The Fixtures tab works without one.")
      return
    }
    var options = ReferralPandaOptions()
    options.apiURL = (info["RPAPIURL"] as? String) ?? options.apiURL
    if let host = info["RPLinkHost"] as? String, !host.isEmpty { options.linkHosts = [host] }
    options.debugHandler = { line in Task { @MainActor [weak self] in self?.log(line) } }
    do {
      let client = try ReferralPanda.configure(apiKey: key, options: options)
      configured = true
      log("configured (\(client.environment.rawValue)) → \(options.apiURL)")
      Task { await listen() }
      if let user = info["RPAutoUser"] as? String, !user.isEmpty { Task { await logIn(user) } }
    } catch {
      problem = error.localizedDescription
      log("configure failed: \(error.localizedDescription)")
    }
  }

  private func listen() async {
    _ = try? await ReferralPanda.addListener { event in
      Task { @MainActor [weak self] in
        switch event {
        case .userChanged(let id):
          self?.userID = id
          self?.log("userChanged → \(id ?? "nobody")")
        case .rewardEarned(let reward): self?.log("rewardEarned → \(reward.label ?? reward.id)")
        case .rewardUpdated(let reward):
          self?.log("rewardUpdated → \(reward.label ?? reward.id) \(reward.state.rawValue)")
        case .referralStatusChanged(let status, _):
          self?.log("referralStatusChanged → \(status.rawValue)")
        case .referralChanged: self?.log("referralChanged")
        case .placementUpdated(let placement):
          self?.log("placementUpdated → v\(placement.screen.version)")
        }
      }
    }
  }

  func logIn(_ id: String) async {
    do {
      let created = try await ReferralPanda.logIn(id)
      log("logIn \(id): \(created ? "new user" : "known user")")
    } catch {
      log("logIn failed: \(error.localizedDescription)")
    }
  }

  func logOut() async {
    await ReferralPanda.logOut()
    log("logOut")
  }

  func log(_ line: String) {
    lines.insert(line, at: 0)
    if lines.count > 200 { lines.removeLast() }
  }
}

@main
struct PlaygroundApp: App {
  @StateObject private var session = Session()

  var body: some Scene {
    WindowGroup {
      TabView {
        ScreenTab().tabItem { Label("Screen", systemImage: "rectangle.portrait") }
        CustomTab().tabItem { Label("Custom", systemImage: "hammer") }
        FixturesTab().tabItem { Label("Fixtures", systemImage: "square.grid.2x2") }
        LogTab().tabItem { Label("Log", systemImage: "list.bullet") }
      }
      .environmentObject(session)
      // Every link the app is opened with goes to the SDK first.
      .onOpenURL { url in
        // A real app gets share links as universal links. Those need an https domain, so on
        // a simulator the link arrives wrapped: rpswift://link?url=<the share link>.
        let wrapped = URLComponents(url: url, resolvingAgainstBaseURL: false)?
          .queryItems?.first { $0.name == "url" }?.value.flatMap(URL.init(string:))
        let link = url.scheme == "rpswift" ? wrapped : url
        session.log(ReferralPanda.handleURL(link) ? "share link opened" : "other link: \(url.scheme ?? "")")
      }
      .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
        if ReferralPanda.handleURL(activity.webpageURL) { session.log("share link opened") }
      }
    }
  }
}

/// Sign in as a made-up user. Shown where a tab needs one.
struct SignIn: View {
  @EnvironmentObject private var session: Session
  @State private var name = "sam"

  var body: some View {
    VStack(spacing: 16) {
      if session.configured {
        Text("Sign in as a test user").font(.headline)
        TextField("User id", text: $name)
          .textFieldStyle(.roundedBorder)
          .textInputAutocapitalization(.never)
          .disableAutocorrection(true)
          .accessibilityIdentifier("user-id")
        Button("Sign in") { Task { await session.logIn(name) } }
          .buttonStyle(.borderedProminent)
          .accessibilityIdentifier("sign-in")
      } else {
        Text("Not configured").font(.headline)
        Text(session.problem ?? "Run scripts/configure.sh to point this app at the local backend. The Fixtures tab works without it.")
          .font(.subheadline).foregroundColor(.secondary).multilineTextAlignment(.center)
      }
    }
    .padding(24)
  }
}

/// The screen designed in the dashboard.
struct ScreenTab: View {
  @EnvironmentObject private var session: Session

  var body: some View {
    if session.userID == nil {
      SignIn()
    } else {
      ReferralView(placement: placementKey) {
        ProgressView()
      } fallback: {
        Text("No published screen for \"\(placementKey)\".")
          .foregroundColor(.secondary).padding()
      }
      .onShare { session.log("shared via \($0)") }
      .onCodeRedeemed { session.log("redeemed: \($0)") }
      .onError { session.log("screen error: \($0.localizedDescription)") }
    }
  }
}

struct LogTab: View {
  @EnvironmentObject private var session: Session

  var body: some View {
    NavigationView {
      List(Array(session.lines.enumerated()), id: \.offset) { item in
        Text(item.element).font(.system(.footnote, design: .monospaced))
      }
      .navigationTitle("Log")
      .toolbar {
        if session.userID != nil {
          Button("Sign out") { Task { await session.logOut() } }
        }
      }
    }
    .navigationViewStyle(.stack)
  }
}
