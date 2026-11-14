// swift-tools-version: 5.9
import PackageDescription

// The headless SDK. It has no dependencies and no UI, so an app that draws its own referral
// screen carries nothing else. The SwiftUI renderer is a second product on top of this one.
let package = Package(
  name: "ReferralPanda",
  platforms: [.iOS(.v15), .macOS(.v12), .tvOS(.v15)],
  products: [
    .library(name: "ReferralPanda", targets: ["ReferralPanda"]),
    .library(name: "ReferralPandaUI", targets: ["ReferralPandaUI"]),
  ],
  targets: [
    .target(
      name: "ReferralPanda",
      resources: [.copy("PrivacyInfo.xcprivacy")]
    ),
    .target(name: "ReferralPandaUI", dependencies: ["ReferralPanda"]),
    .testTarget(name: "ReferralPandaTests", dependencies: ["ReferralPanda"]),
    .testTarget(name: "ReferralPandaUITests", dependencies: ["ReferralPandaUI"]),
  ]
)
