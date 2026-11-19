import SwiftUI

/// Design tokens (Apple dark): black canvas, graphite steps, ONE accent for actions —
/// the red of Apple Music, #FA2D48 —
/// and the system green/red/yellow for right/wrong/warning (a wrong state also gets its ✕/⚠ symbol, since the
/// accent is red too). Fixed values, so every screen gets exactly the same shade on every device. Apps
/// add only their own content colours (Piano: the hands).
public enum AppStyle {
    public static let bg = Color.black
    public static let panel = Color(hex: 0x1c1c1e)
    public static let panel2 = Color(hex: 0x2c2c2e)
    public static let line = Color.white.opacity(0.10)
    public static let ink = Color(hex: 0xf5f5f7)
    public static let mute = Color(hex: 0x98989d)
    public static let paper = Color(hex: 0xf5f5f7)
    public static let accent = Color(hex: 0xfa2d48)        // Apple Music red, fixed in light and dark
    public static let accentSoft = Color(hex: 0xff8a98)
    public static let ok = Color.green
    /// Attention on shapes: status dots, icons alone, banner tints.
    public static let warn = Color.yellow
    /// Attention in words (labels, captions): system orange, readable on light backgrounds too, where yellow text
    /// isn't.
    public static let warnText = Color.orange
    public static let bad = Color.red
    /// A guide on shapes, neither good nor bad (Piano's black-key group hint).
    public static let info = Color.blue
    /// Radii: controls are capsules/circles; panels 22, small shells 12 (radius tiers).
    public static let panelRadius: CGFloat = 22
    public static let shellRadius: CGFloat = 12
}

extension Color {
    public init(hex: UInt32, alpha: Double = 1) {
        self.init(.sRGB, red: Double(hex >> 16 & 0xff) / 255, green: Double(hex >> 8 & 0xff) / 255,
                  blue: Double(hex & 0xff) / 255, opacity: alpha)
    }
}

extension Font {
    /// Headings: SF Pro Display, semibold (typography).
    public static func display(_ size: CGFloat) -> Font { .system(size: size, weight: .semibold) }
}

extension View {
    /// Liquid Glass like the system apps (iOS/macOS 26); the blurred material before that.
    /// `tint` = a coloured glass (the main action), `interactive` = reacts to touch.
    @ViewBuilder public func glass<S: Shape>(_ shape: S, tint: Color? = nil, interactive: Bool = false) -> some View {
        if #available(iOS 26, macOS 26, *) {
            let g: Glass = tint.map { Glass.regular.tint($0) } ?? .regular
            glassEffect(interactive ? g.interactive() : g, in: shape)
        } else {
            background(tint.map { AnyShapeStyle($0) } ?? AnyShapeStyle(.regularMaterial), in: shape)
        }
    }

    /// A panel: padded content on glass with the panel radius.
    public func appPanel() -> some View {
        padding(.horizontal, 14).padding(.vertical, 10)
            .glass(RoundedRectangle(cornerRadius: AppStyle.panelRadius, style: .continuous))
    }
}

/// The canvas behind the glass: near-black with soft glows (glass needs something to bend). `glows` = the app's
/// own colours, e.g. Piano's hand colours; default the accent blue.
public struct Backdrop: View {
    let glows: [Color]
    public init(glows: [Color] = [AppStyle.accent, AppStyle.accentSoft]) { self.glows = glows }

    public var body: some View {
        ZStack {
            Color.black
            ForEach(Array(glows.prefix(3).enumerated()), id: \.offset) { i, c in
                RadialGradient(colors: [c.opacity(i == 2 ? 0.16 : 0.26), .clear],
                               center: [UnitPoint.topLeading, .topTrailing, .center][i], startRadius: 0, endRadius: 680)
            }
        }
        .ignoresSafeArea()
    }
}

/// A label style chosen at run time (`.iconOnly` / `.titleAndIcon` are different types); bars use it to
/// drop the words on a phone.
public struct AnyLabelStyle: LabelStyle {
    private let make: (Configuration) -> AnyView
    public init<S: LabelStyle>(_ style: S) { make = { AnyView(Label($0).labelStyle(style)) } }
    public func makeBody(configuration: Configuration) -> some View { make(configuration) }
}
