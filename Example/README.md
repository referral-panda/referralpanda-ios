# ReferralPanda Playground (Swift)

The Swift SDK's test app. Four tabs:

- **Screen**: the referral screen designed in the dashboard (`ReferralView`).
- **Custom**: the same program with hand-built UI, using only headless SDK calls.
- **Fixtures**: every shared conformance fixture, drawn by the real renderer. Needs no backend.
- **Log**: what the SDK told the app through its listener, and one line per request.

It uses the SDK from the package one folder up, the same sources customers get.

## Run it

You need Xcode and [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).

For the Fixtures tab alone:

```bash
sdks/ios/Example/scripts/configure.sh
```

Then open `sdks/ios/Example/ReferralPandaPlayground.xcodeproj` and run the Playground scheme on a simulator.

## Run it against a local backend

From the repository root:

```bash
pnpm --filter @referralpanda/e2e serve
```

In another terminal:

```bash
pnpm --filter @referralpanda/e2e seed:playground
```

```bash
sdks/ios/Example/scripts/configure.sh
```

`seed:playground` writes a sandbox public key to `apps/playground/.env.local`, and `configure.sh` copies it into `Local.xcconfig`. Neither file is committed. Run `configure.sh` again after seeding again.

To sign a user in at launch without typing:

```bash
RP_AUTO_USER=sam sdks/ios/Example/scripts/configure.sh
```

In the Fixtures tab, a code starting with `OK` is accepted by the code field, and anything else is refused.

Apple's offer code sheet opens in the simulator but stays empty, because the simulator has no App Store account.
