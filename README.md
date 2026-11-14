# ReferralPanda for iOS

The Swift SDK. Swift 5.9+, iOS 15+, no dependencies.

Two products:

- `ReferralPanda`: the headless core. Every call, and no UI.
- `ReferralPandaUI`: the screens you design in the dashboard, drawn with SwiftUI, plus the share sheet and Apple's offer code sheet.

## Use

```swift
import ReferralPanda

// At app start. Use a public key (rp_pub_…), never a secret key.
try ReferralPanda.configure(apiKey: "rp_pub_live_…")

// When the user signs in, and at each app start while they are signed in.
try await ReferralPanda.logIn(user.id)

// Every URL the app is opened with.
.onOpenURL { ReferralPanda.handleURL($0) }
.onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { ReferralPanda.handleURL($0.webpageURL) }

// Draw your own referral screen.
let referral = try await ReferralPanda.getReferral()   // code, link, stats, rewards
let share = try await ReferralPanda.getShareContent(channel: "whatsapp")
ReferralPanda.trackShare(channel: "whatsapp")
let result = try await ReferralPanda.redeemCode("SAM123")
ReferralPanda.track("signed_up")
```

## Show the screen from the dashboard

```swift
import ReferralPandaUI

// Anywhere in your own layout. It fills the space it is given.
ReferralView(placement: "settings_referral")
  .onCodeRedeemed { result in … }

// Or over the app, as a sheet.
ReferralPanda.presentReferralScreen(placement: "settings_referral")

// The system share sheet with the user's link.
try await ReferralPanda.share()
```

Screens with a Lottie animation need a Lottie library in your app, because the SDK has no dependencies. Tell the renderer how to draw one, once, at app start:

```swift
ReferralPandaUI.lottieView = { url, loop, play in AnyView(MyLottieView(url: url, loop: loop, play: play)) }
```

Without it the animation's space is left empty. An uploaded font is used when it is a TrueType or OpenType file; otherwise the system font stays.

Money is always integer minor units (`amountMinor`, cents) with an ISO currency.

Referral codes never unlock paid features by themselves on iOS. A reward is delivered through RevenueCat or as an Apple offer code, which the user redeems in Apple's own sheet.

## Sample app

`Example` is a small app with the dashboard screen, a hand-built screen on the headless calls, and every conformance fixture. See `Example/README.md`.

## Develop

```bash
pnpm test:swift
```

The core mirrors `sdks/react-native/src/core`, and the renderer mirrors `sdks/react-native/src/ui`. Change behaviour in both, in the same pull request. See `docs/adr/0016-swift-sdk.md`.

The renderer is checked against the shared fixtures in `sdks/conformance`. To look at what it draws, this writes a PNG for every fixture, light and dark:

```bash
RP_SNAPSHOT_DIR=/tmp/rp-shots swift test --package-path sdks/ios --filter SnapshotTests
```

## About this repository

This is the source of the SDK as Swift Package Manager installs it. It is developed in
ReferralPanda's main repository, where its tests run against the same fixtures as our other
SDKs, and copied here on every release. Issues are welcome here. For a change, open an issue
first: a pull request made here cannot be merged directly, because the next release would
overwrite it.
