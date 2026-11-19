import DesignKit
import PianoKit
import SwiftUI

/// The palette: dark stage, orange right hand, cyan left hand.
/// Piano's palette = the design tokens (DesignKit) + the hand colours, which are content, not chrome.
enum Theme {
    static let bg = AppStyle.bg, panel = AppStyle.panel, panel2 = AppStyle.panel2, line = AppStyle.line
    static let ink = AppStyle.ink, mute = AppStyle.mute, paper = AppStyle.paper
    static let accent = AppStyle.accent, accentSoft = AppStyle.accentSoft
    static let ok = AppStyle.ok, bad = AppStyle.bad, warn = AppStyle.warn
    // hands: right = the accent red, left = system purple; wrong keys also get a ✕
    static let rh = AppStyle.accent, lh = Color.purple
    /// Tastiera's group hint (blue: yellow = "this key", red = wrong, green = right).
    static let hint = AppStyle.info
    static let stage = Color(hex: 0x0b0b0c), dark = Color(hex: 0x111113)

    static func hand(_ h: PianoKitHand) -> Color { h == .right ? rh : lh }
}

/// The backdrop with Piano's own glows (left hand, right hand, action blue).
func pianoBackdrop() -> Backdrop { Backdrop(glows: [Theme.lh, Theme.rh, Theme.accent]) }

typealias PianoKitHand = Piece.Hand



let noteNames = Chords.names
func noteName(_ m: Int) -> String { noteNames[m % 12] }
func isBlack(_ m: Int) -> Bool { [1, 3, 6, 8, 10].contains(m % 12) }

/// Text/drawing size factor (A− / A+ in the header, saved; iPad starts bigger: it sits on the music stand).
private struct PianoScaleKey: EnvironmentKey { static let defaultValue: CGFloat = 1 }
extension EnvironmentValues {
    var pianoScale: CGFloat {
        get { self[PianoScaleKey.self] }
        set { self[PianoScaleKey.self] = newValue }
    }
}

extension View {
    /// A sheet's minimum size, on the Mac only: on iPhone it overflowed the screen (Segni at 420 pt on
    /// a 414 pt phone). Every Piano sheet uses this instead of `.frame(minWidth:minHeight:)`.
    func macSheetFrame(minWidth: CGFloat, minHeight: CGFloat) -> some View {
        #if os(macOS)
        frame(minWidth: minWidth, minHeight: minHeight)
        #else
        self
        #endif
    }
}
