import Foundation

/// Where the shared conformance fixtures are. In the repository this SDK is developed in
/// they are in sdks/conformance/expected. In the public repository they are copied into
/// Tests/Fixtures/expected.
let fixtureFolder: URL = {
  let tests = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
  let inPackage = tests.appendingPathComponent("Fixtures/expected")
  if FileManager.default.fileExists(atPath: inPackage.path) { return inPackage }
  return tests.deletingLastPathComponent().deletingLastPathComponent()
    .appendingPathComponent("conformance/expected")
}()
