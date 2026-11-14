#if canImport(SwiftUI)
  import SwiftUI

  #if canImport(CoreText)
    import CoreText
  #endif

  /// Loads a screen's uploaded font once and gives back the name to use, when it is ready.
  /// Until then, and if it cannot be read, the system font stays.
  @MainActor
  final class FontLoader: ObservableObject {
    @Published var regular: String?
    @Published var bold: String?
    /// File address to registered font name, for the life of the app.
    private static var registered: [String: String] = [:]

    func load(regular: String?, bold: String?) async {
      self.regular = await Self.register(regular)
      self.bold = await Self.register(bold)
    }

    private static func register(_ address: String?) async -> String? {
      guard let address, let url = URL(string: address) else { return nil }
      if let name = registered[address] { return name }
      #if canImport(CoreText)
        // Core Text reads TrueType and OpenType files. A web-only format (WOFF2) is left out.
        guard let (data, _) = try? await URLSession.shared.data(from: url),
          let provider = CGDataProvider(data: data as CFData), let font = CGFont(provider),
          let name = font.postScriptName as String?
        else { return nil }
        // Already registered by the app or an earlier screen is fine.
        CTFontManagerRegisterGraphicsFont(font, nil)
        registered[address] = name
        return name
      #else
        return nil
      #endif
    }
  }
#endif
