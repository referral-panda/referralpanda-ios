#if canImport(SwiftUI)
  import SwiftUI

  /// 24 by 24. The same drawings as the web and React Native renderers, one per icon in the
  /// schema, so a screen looks the same as it did in the dashboard.
  private enum Shape {
    case path(String)
    case rect(Double, Double, Double, Double, Double)
    case circle(Double, Double, Double)
  }

  private let linkPath =
    "M10 14a4 4 0 0 0 5.7 0l3-3a4 4 0 0 0-5.7-5.7l-1 1M14 10a4 4 0 0 0-5.7 0l-3 3a4 4 0 0 0 5.7 5.7l1-1"

  private let drawings: [String: [Shape]] = [
    "gift": [
      .rect(3, 9, 18, 12, 2),
      .path(
        "M3 13h18M12 9v12M12 9c-2 0-4.5-.6-4.5-3A2.2 2.2 0 0 1 12 6c0-1.6 1-3 2.6-3A2.3 2.3 0 0 1 16.5 6c0 2.4-2.5 3-4.5 3Z"
      ),
    ],
    "heart": [
      .path("M12 20s-7.5-4.4-7.5-10A4.3 4.3 0 0 1 12 7.5 4.3 4.3 0 0 1 19.5 10c0 5.6-7.5 10-7.5 10Z")
    ],
    "star": [.path("m12 3 2.7 5.8 6.3.8-4.7 4.3 1.3 6.1L12 17l-5.6 3 1.3-6.1L3 9.6l6.3-.8L12 3Z")],
    "sparkles": [
      .path(
        "M10 3l1.6 4.4L16 9l-4.4 1.6L10 15l-1.6-4.4L4 9l4.4-1.6L10 3ZM18 14l.9 2.1L21 17l-2.1.9L18 20l-.9-2.1L15 17l2.1-.9L18 14Z"
      )
    ],
    "trophy": [
      .path(
        "M8 4h8v5a4 4 0 0 1-8 0V4ZM8 6H5c0 3 1.2 4.5 3 4.5M16 6h3c0 3-1.2 4.5-3 4.5M12 13v4M8.5 20h7M10 17h4"
      )
    ],
    "users": [
      .path(
        "M9 11a3.2 3.2 0 1 0 0-6.4A3.2 3.2 0 0 0 9 11ZM3 20c0-3.3 2.7-5.5 6-5.5s6 2.2 6 5.5M16 5a3 3 0 0 1 0 6M17.5 14.7c2.1.6 3.5 2.5 3.5 5.3"
      )
    ],
    "user_plus": [
      .path(
        "M10 11a3.2 3.2 0 1 0 0-6.4 3.2 3.2 0 0 0 0 6.4ZM4 20c0-3.3 2.7-5.5 6-5.5s6 2.2 6 5.5M19 8v6M16 11h6"
      )
    ],
    "share": [.path("M12 15V4M8 8l4-4 4 4M5 12v6a2 2 0 0 0 2 2h10a2 2 0 0 0 2-2v-6")],
    "link": [.path(linkPath)],
    "copy": [.rect(9, 9, 11, 11, 2), .path("M5 15V6a2 2 0 0 1 2-2h9")],
    "check": [.path("m5 12.5 4.5 4.5L19 7.5")],
    "clock": [.circle(12, 12, 8.5), .path("M12 7.5V12l3 2")],
    "lock": [.rect(5, 11, 14, 9, 2), .path("M8 11V8a4 4 0 0 1 8 0v3")],
    "cash": [.rect(3, 6, 18, 12, 2), .circle(12, 12, 2.5), .path("M6.5 9.5v.01M17.5 14.5v.01")],
    "ticket": [
      .path(
        "M4 8a2 2 0 0 1 2-2h12a2 2 0 0 1 2 2v2a2 2 0 0 0 0 4v2a2 2 0 0 1-2 2H6a2 2 0 0 1-2-2v-2a2 2 0 0 0 0-4V8ZM14 6v12"
      )
    ],
    "rocket": [
      .path(
        "M12 15c-1.5-1-3-2.5-3-3 0-4 2.5-8 7-9 1 4.5-1 8-5 9.5-.3.8-.8 1.8-1.5 2.5M9 12l-3 .5L4.5 15l3 .5M12 15l-.5 3 2.5 1.5.5-3M15.5 8.5v.01"
      )
    ],
    // Share channels.
    "channel:messages": [
      .path("M4 6a2 2 0 0 1 2-2h12a2 2 0 0 1 2 2v9a2 2 0 0 1-2 2h-7l-4 3.5V17H6a2 2 0 0 1-2-2V6Z")
    ],
    "channel:whatsapp": [
      .path(
        "M12 3.5A8.5 8.5 0 0 0 4.6 16.2L3.5 20.5l4.4-1.1A8.5 8.5 0 1 0 12 3.5ZM9 8.5c.2 2.5 2 4.8 4.5 5.5l1.5-1.5"
      )
    ],
    "channel:copy_link": [.path(linkPath)],
    "channel:more": [.path("M6 12v.01M12 12v.01M18 12v.01")],
  ]

  /// Reads the part of SVG path syntax the drawings above use: M L H V C S A Z, in both
  /// cases, with circular arcs only.
  func svgPath(_ data: String) -> Path {
    var path = Path()
    var numbers: [Double] = []
    var command: Character = "M"
    var current = CGPoint.zero
    var start = CGPoint.zero
    var lastControl: CGPoint?

    func run() {
      let relative = command.isLowercase
      func point(_ x: Double, _ y: Double) -> CGPoint {
        relative ? CGPoint(x: current.x + x, y: current.y + y) : CGPoint(x: x, y: y)
      }
      var index = 0
      func take(_ count: Int) -> [Double]? {
        guard index + count <= numbers.count else { return nil }
        defer { index += count }
        return Array(numbers[index..<index + count])
      }
      var first = true
      switch command.lowercased() {
      case "m":
        while let n = take(2) {
          let to = point(n[0], n[1])
          if first {
            path.move(to: to)
            start = to
          } else {
            path.addLine(to: to)
          }
          current = to
          first = false
        }
        lastControl = nil
      case "l":
        while let n = take(2) {
          current = point(n[0], n[1])
          path.addLine(to: current)
        }
        lastControl = nil
      case "h":
        while let n = take(1) {
          current = CGPoint(x: relative ? current.x + n[0] : n[0], y: current.y)
          path.addLine(to: current)
        }
        lastControl = nil
      case "v":
        while let n = take(1) {
          current = CGPoint(x: current.x, y: relative ? current.y + n[0] : n[0])
          path.addLine(to: current)
        }
        lastControl = nil
      case "c":
        while let n = take(6) {
          let c1 = point(n[0], n[1])
          let c2 = point(n[2], n[3])
          let to = point(n[4], n[5])
          path.addCurve(to: to, control1: c1, control2: c2)
          lastControl = c2
          current = to
        }
      case "s":
        while let n = take(4) {
          let c1 =
            lastControl.map { CGPoint(x: 2 * current.x - $0.x, y: 2 * current.y - $0.y) } ?? current
          let c2 = point(n[0], n[1])
          let to = point(n[2], n[3])
          path.addCurve(to: to, control1: c1, control2: c2)
          lastControl = c2
          current = to
        }
      case "a":
        while let n = take(7) {
          let to = point(n[5], n[6])
          addArc(&path, from: current, to: to, radius: n[0], large: n[3] != 0, sweep: n[4] != 0)
          current = to
        }
        lastControl = nil
      case "z":
        path.closeSubpath()
        current = start
        lastControl = nil
      default:
        break
      }
      numbers = []
    }

    var token = ""
    func flush() {
      if let value = Double(token) { numbers.append(value) }
      token = ""
    }
    for character in data {
      if character.isLetter, character != "e" {
        flush()
        run()
        command = character
      } else if character == "-" {
        flush()
        token = "-"
      } else if character == "." {
        // "4.5.6" is two numbers: 4.5 and .6
        if token.contains(".") { flush() }
        token.append(character)
      } else if character.isNumber {
        token.append(character)
      } else {
        flush()
      }
    }
    flush()
    run()
    return path
  }

  private func addArc(
    _ path: inout Path, from: CGPoint, to: CGPoint, radius: Double, large: Bool, sweep: Bool
  ) {
    let dx = (from.x - to.x) / 2
    let dy = (from.y - to.y) / 2
    let half = dx * dx + dy * dy
    guard half > 0 else { return }
    // A radius too small to reach is grown until it does, as SVG says.
    let r = max(radius, half.squareRoot())
    let factor = (large != sweep ? 1.0 : -1.0) * (max(0, r * r - half) / half).squareRoot()
    let center = CGPoint(
      x: factor * dy + (from.x + to.x) / 2, y: -factor * dx + (from.y + to.y) / 2)
    path.addArc(
      center: center, radius: r,
      startAngle: .radians(atan2(from.y - center.y, from.x - center.x)),
      endAngle: .radians(atan2(to.y - center.y, to.x - center.x)),
      // SwiftUI names the direction for a y-up plane; these drawings are y-down.
      clockwise: !sweep)
  }

  /// A line icon. An icon added to the schema after this SDK was built leaves its space empty.
  struct IconView: View {
    let name: String
    let size: Double
    let color: Color

    var body: some View {
      Canvas { context, _ in
        let scale = size / 24
        for shape in drawings[name] ?? [] {
          let path: Path
          switch shape {
          case .path(let data): path = svgPath(data)
          case .rect(let x, let y, let width, let height, let radius):
            path = Path(
              roundedRect: CGRect(x: x, y: y, width: width, height: height), cornerRadius: radius)
          case .circle(let x, let y, let r):
            path = Path(ellipseIn: CGRect(x: x - r, y: y - r, width: 2 * r, height: 2 * r))
          }
          context.stroke(
            path.applying(CGAffineTransform(scaleX: scale, y: scale)), with: .color(color),
            style: StrokeStyle(lineWidth: 1.75 * scale, lineCap: .round, lineJoin: .round))
        }
      }
      .frame(width: size, height: size)
      // The drawings are made left to right. They are not mirrored.
      .environment(\.layoutDirection, .leftToRight)
      // Decoration: screen readers skip it.
      .accessibilityHidden(true)
    }
  }
#endif
