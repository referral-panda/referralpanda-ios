import ReferralPanda
import ReferralPandaUI
import SwiftUI

/// The same program with hand-built UI, using only headless SDK calls.
struct CustomTab: View {
  @EnvironmentObject private var session: Session
  @State private var referral: Referral?
  @State private var friendCode = ""
  @State private var message = ""

  var body: some View {
    NavigationView {
      Group {
        if session.userID == nil {
          SignIn()
        } else {
          content
        }
      }
      .navigationTitle("Custom")
    }
    .navigationViewStyle(.stack)
    .task(id: session.userID) { await load(refresh: false) }
  }

  private var content: some View {
    List {
      if let referral {
        Section("Your code") {
          HStack {
            Text(referral.code).font(.system(.title2, design: .monospaced).bold())
              .accessibilityIdentifier("custom-code")
            Spacer()
            Button("Copy") {
              UIPasteboard.general.string = referral.code
              ReferralPanda.track("code_copied", properties: ["placement": "custom"])
              message = "Copied"
            }
          }
          Text(referral.link).font(.footnote).foregroundColor(.secondary)
          Button("Share") {
            Task {
              do {
                let shared = try await ReferralPanda.share(message: "Join me: {{referral.link}}")
                session.log("share sheet: \(shared ? "shared" : "closed")")
              } catch { session.log("share failed: \(error.localizedDescription)") }
            }
          }
          .accessibilityIdentifier("custom-share")
        }
        Section("Friends") {
          row("Invited", referral.stats.total)
          row("Qualified", referral.stats.count(.qualified))
          row("Rewarded", referral.stats.count(.rewarded))
          if let invitedBy = referral.referredBy {
            Text("Invited with \(invitedBy.code) (\(invitedBy.status.rawValue))")
          }
        }
        Section("Rewards") {
          if referral.rewards.isEmpty { Text("None yet").foregroundColor(.secondary) }
          ForEach(referral.rewards) { reward in
            HStack {
              Text(reward.label ?? reward.kind?.rawValue ?? "Reward")
              Spacer()
              Text(reward.state.rawValue).foregroundColor(.secondary)
            }
          }
        }
        if referral.stale { Text("Offline: showing the last saved copy.").font(.footnote) }
      }
      Section("Have a code?") {
        TextField("Friend's code", text: $friendCode)
          .textInputAutocapitalization(.characters)
          .disableAutocorrection(true)
          .accessibilityIdentifier("custom-redeem-field")
        Button("Redeem") { Task { await redeem() } }
          .accessibilityIdentifier("custom-redeem")
        Button("Record signed_up") {
          ReferralPanda.track("signed_up")
          message = "Recorded"
        }
      }
      if !message.isEmpty {
        Text(message).foregroundColor(.secondary).accessibilityIdentifier("custom-message")
      }
    }
    .refreshable { await load(refresh: true) }
  }

  private func row(_ label: String, _ value: Int) -> some View {
    HStack {
      Text(label)
      Spacer()
      Text(String(value)).monospacedDigit()
    }
  }

  private func load(refresh: Bool) async {
    guard session.userID != nil else {
      referral = nil
      return
    }
    do {
      referral = try await ReferralPanda.getReferral(refresh: refresh)
    } catch {
      session.log("getReferral failed: \(error.localizedDescription)")
    }
  }

  private func redeem() async {
    do {
      switch try await ReferralPanda.redeemCode(friendCode) {
      case .redeemed(let firstTime, let status):
        message = firstTime ? "Code accepted (\(status.rawValue))" : "Already redeemed"
        await load(refresh: true)
      case .invalidCode: message = "That code is not valid"
      case .ownCode: message = "That is your own code"
      }
    } catch {
      message = error.localizedDescription
    }
  }
}
