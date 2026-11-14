import Foundation

// Share links look like https://go.referralpanda.com/{handle}/{code}, with /t/ before the
// code in sandbox. The server decides whether a link belongs to this project; the SDK only
// needs to tell "one of ours" from any other URL the app is opened with.

public let defaultLinkHosts = ["go.referralpanda.com"]

func matches(_ value: String, _ pattern: String) -> Bool {
  value.range(of: "^(?:\(pattern))$", options: .regularExpression) != nil
}

private let codePattern = "[A-Za-z0-9]{3,20}"
private let handlePattern = "[a-z0-9]([a-z0-9-]{0,46}[a-z0-9])?"
private let channelPattern = "[a-z0-9_]{1,50}"

private func parse(_ url: String) -> (host: String, segments: [String])? {
  let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
  let lower = trimmed.lowercased()
  let prefix = lower.hasPrefix("https://") ? 8 : lower.hasPrefix("http://") ? 7 : 0
  guard prefix > 0 else { return nil }
  let rest = trimmed.dropFirst(prefix)
  let authority = rest.prefix { !"/?#".contains($0) }
  guard !authority.isEmpty else { return nil }
  var host = authority.lowercased()
  if let colon = host.lastIndex(of: ":"), host[host.index(after: colon)...].allSatisfy(\.isNumber) {
    host = String(host[..<colon])
  }
  let path = rest.dropFirst(authority.count).prefix { !"?#".contains($0) }
  return (host, path.split(separator: "/").map(String.init))
}

/// The code in a share link, or nil when the URL is not a share link on one of the hosts.
public func shareLinkCode(_ url: String, hosts: [String] = defaultLinkHosts) -> String? {
  guard let parsed = parse(url), hosts.contains(parsed.host) else { return nil }
  let segments = parsed.segments
  guard let handle = segments.first, matches(handle.lowercased(), handlePattern) else { return nil }
  let code: String
  switch segments.count {
  case 2: code = segments[1]
  case 3 where segments[1] == "t": code = segments[2]
  default: return nil
  }
  return matches(code, codePattern) ? code.uppercased() : nil
}

func isChannel(_ value: String) -> Bool { matches(value, channelPattern) }

/// Adds the share channel to a link, so clicks can be counted per channel.
public func shareLink(_ link: String, channel: String?) -> String {
  let name = (channel ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
  guard isChannel(name) else { return link }
  let parts = link.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)
  let base = String(parts.first ?? "")
  let joined = base + (base.contains("?") ? "&" : "?") + "ch=" + name
  return parts.count > 1 ? joined + "#" + parts[1] : joined
}

/// The same characters JavaScript's encodeURIComponent leaves alone, so every SDK sends the
/// same bytes for the same user id.
func encodeComponent(_ value: String) -> String {
  var allowed = CharacterSet.alphanumerics
  allowed.insert(charactersIn: "-_.!~*'()")
  // CharacterSet.alphanumerics includes non-ASCII letters; those must be escaped too.
  let ascii = CharacterSet(charactersIn: Unicode.Scalar(0)..<Unicode.Scalar(128))
  return value.addingPercentEncoding(withAllowedCharacters: allowed.intersection(ascii)) ?? value
}
