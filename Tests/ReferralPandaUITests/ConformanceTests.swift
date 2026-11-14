import Foundation
import ReferralPanda
import XCTest

@testable import ReferralPandaUI

/// The shared conformance fixtures (sdks/conformance/expected): what the placement route
/// sends, and what any correct renderer shows for it. The same files every SDK reads.
private struct Fixture: Decodable {
  struct Input: Decodable {
    let config: [String: JSONValue]
    let strings: [String: String]
    let locale: String
    let rtl: Bool
    let platform: String
    let data: ScreenData
  }
  let name: String
  let input: Input
  let expect: ScreenOutline
}

private func fixtures() throws -> [Fixture] {
  try FileManager.default.contentsOfDirectory(atPath: fixtureFolder.path)
    .filter { $0.hasSuffix(".json") }.sorted()
    .map {
      try JSONDecoder().decode(
        Fixture.self, from: Data(contentsOf: fixtureFolder.appendingPathComponent($0)))
    }
}

final class ConformanceTests: XCTestCase {
  func testEveryFixtureShowsWhatItShould() throws {
    let all = try fixtures()
    XCTAssertGreaterThanOrEqual(all.count, 17, "The fixtures were not found at \(fixtureFolder.path)")
    for fixture in all {
      var unknown: [String] = []
      let layout = ScreenLayout.build(
        config: fixture.input.config, strings: fixture.input.strings, data: fixture.input.data,
        locale: fixture.input.locale, platform: fixture.input.platform,
        onUnknownNode: { unknown.append($0) })
      XCTAssertEqual(layout.outline.texts, fixture.expect.texts, "\(fixture.name): texts")
      XCTAssertEqual(layout.outline.actions, fixture.expect.actions, "\(fixture.name): actions")
      XCTAssertEqual(layout.outline.assets, fixture.expect.assets, "\(fixture.name): assets")
      XCTAssertEqual(layout.rightToLeft, fixture.input.rtl, "\(fixture.name): direction")
      XCTAssertEqual(unknown, [], "\(fixture.name): every node type is known")
      XCTAssertEqual(layout.theme.colors.count, 8, "\(fixture.name): theme colors")
    }
  }

  func testANodeFromANewerSchemaIsSkipped() {
    var unknown: [String] = []
    let config: [String: JSONValue] = [
      "root": [
        "type": "stack",
        "children": [
          ["type": "hologram", "text": "title"], ["type": "text", "text": "title"],
        ],
      ]
    ]
    let data = try! JSONDecoder().decode(
      ScreenData.self,
      from: Data(
        #"{"values":{},"stats":{"total":0,"pending":0,"qualified":0,"rewarded":0},"rewards":[]}"#
          .utf8))
    let layout = ScreenLayout.build(
      config: config, strings: ["title": "Hello"], data: data, locale: nil,
      onUnknownNode: { unknown.append($0) })
    XCTAssertEqual(layout.outline.texts, ["Hello"])
    XCTAssertEqual(unknown, ["hologram"])
  }

  func testInterpolate() {
    XCTAssertEqual(interpolate("Hi {{ name }}, welcome", ["name": "Sam"]), "Hi Sam, welcome")
    XCTAssertEqual(interpolate("Hi {{name}}, welcome", [:]), "Hi , welcome")
    XCTAssertEqual(interpolate("  You get   {{x}} ", [:]), "You get")
  }
}
