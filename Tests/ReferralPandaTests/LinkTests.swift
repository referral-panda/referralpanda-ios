import XCTest

@testable import ReferralPanda

final class LinkTests: XCTestCase {
  func testReadsTheCodeFromAShareLink() {
    XCTAssertEqual(shareLinkCode("https://go.referralpanda.com/toffee/sam123"), "SAM123")
    XCTAssertEqual(shareLinkCode("https://go.referralpanda.com/toffee/t/SAM123"), "SAM123")
    XCTAssertEqual(shareLinkCode("  HTTPS://GO.ReferralPanda.com:443/toffee/SAM123?ch=x#y "), "SAM123")
    XCTAssertEqual(
      shareLinkCode("https://invite.toffee.app/toffee/SAM123", hosts: ["invite.toffee.app"]),
      "SAM123")
  }

  func testIgnoresEverythingElse() {
    for url in [
      "https://example.com/toffee/SAM123", "https://go.referralpanda.com/toffee",
      "https://go.referralpanda.com/toffee/x/SAM123", "https://go.referralpanda.com/toffee/t/SAM123/more",
      "https://go.referralpanda.com/-bad/SAM123", "https://go.referralpanda.com/toffee/no",
      "toffee://go.referralpanda.com/toffee/SAM123", "not a url", "",
    ] {
      XCTAssertNil(shareLinkCode(url), url)
    }
  }

  func testAddsTheChannel() {
    let link = "https://go.referralpanda.com/toffee/SAM123"
    XCTAssertEqual(shareLink(link, channel: "WhatsApp"), "\(link)?ch=whatsapp")
    XCTAssertEqual(shareLink("\(link)?a=1#top", channel: "sms"), "\(link)?a=1&ch=sms#top")
    XCTAssertEqual(shareLink(link, channel: "not ok!"), link)
    XCTAssertEqual(shareLink(link, channel: nil), link)
  }

  func testEncodesLikeEncodeURIComponent() {
    XCTAssertEqual(encodeComponent("sam+1@example.com/ä b"), "sam%2B1%40example.com%2F%C3%A4%20b")
    XCTAssertEqual(encodeComponent("a-b_c.d!e~f*g'h(i)"), "a-b_c.d!e~f*g'h(i)")
  }

  func testPreviewTokens() {
    let token = "rpv_" + String(repeating: "a", count: 43)
    XCTAssertEqual(
      ReferralPandaClient.previewToken(from: URL(string: "rpplayground://preview?token=\(token)")!),
      token)
    XCTAssertEqual(
      ReferralPandaClient.previewToken(from: URL(string: "x://preview/?a=1&token=\(token)")!), token)
    XCTAssertNil(ReferralPandaClient.previewToken(from: URL(string: "x://other?token=\(token)")!))
    XCTAssertNil(ReferralPandaClient.previewToken(from: URL(string: "x://preview?token=rpv_short")!))
  }

  func testShortHashMatchesTheOtherSDKs() {
    // djb2 over UTF-16 units, base 36: the same as the React Native SDK.
    XCTAssertEqual(shortHash(""), "45h")
    XCTAssertEqual(shortHash("a"), "3t3a")
  }
}
