#if canImport(AppKit) && canImport(SwiftUI)
  import AppKit
  import ReferralPanda
  import SwiftUI
  import XCTest

  @testable import ReferralPandaUI

  /// Draws fixtures to PNG files for a person to look at. Runs only when RP_SNAPSHOT_DIR is
  /// set: `RP_SNAPSHOT_DIR=/tmp/shots swift test --filter SnapshotTests`.
  final class SnapshotTests: XCTestCase {
    private struct Fixture: Decodable {
      struct Input: Decodable {
        let config: [String: JSONValue]
        let strings: [String: String]
        let locale: String
        let data: ScreenData
      }
      let name: String
      let input: Input
    }

    @MainActor
    func testDrawFixtures() throws {
      guard let folder = ProcessInfo.processInfo.environment["RP_SNAPSHOT_DIR"] else {
        throw XCTSkip("Set RP_SNAPSHOT_DIR to draw the fixtures.")
      }
      let fixtures = fixtureFolder
      try FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
      for file in try FileManager.default.contentsOfDirectory(atPath: fixtures.path).sorted()
      where file.hasSuffix(".json") {
        let fixture = try JSONDecoder().decode(
          Fixture.self, from: Data(contentsOf: fixtures.appendingPathComponent(file)))
        for scheme in [ColorScheme.light, .dark] {
          let view = ScreenView(
            config: fixture.input.config, strings: fixture.input.strings,
            data: fixture.input.data, locale: fixture.input.locale, colorScheme: scheme
          ).frame(width: 390, height: 844)
          let host = NSHostingView(rootView: view)
          host.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
          let window = NSWindow(
            contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
          window.contentView = host
          host.layoutSubtreeIfNeeded()
          RunLoop.main.run(until: Date().addingTimeInterval(0.2))
          guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { continue }
          host.cacheDisplay(in: host.bounds, to: bitmap)
          let name = "\(fixture.name)-\(scheme == .dark ? "dark" : "light").png"
          try bitmap.representation(using: .png, properties: [:])?
            .write(to: URL(fileURLWithPath: folder).appendingPathComponent(name))
        }
      }
    }
  }
#endif
