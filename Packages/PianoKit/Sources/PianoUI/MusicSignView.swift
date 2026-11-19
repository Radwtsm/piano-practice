import CoreText
import SwiftUI

/// One sign of the sheet. Where the system's music font has the real glyph
/// it is that glyph; where it hasn't (iOS 17 showed
/// "?" boxes for semibreve, minima, rests, repeat) the sign is drawn on a small staff. Checked in the font itself,
/// not by OS version, so an update switches by itself.
struct MusicSignView: View {
    enum Kind {
        case trebleClef, bassClef, sharp, flat, natural, keySignature, ledger, fingers
        case whole, half, quarter, eighth, dotted, tie, time, barline
        case wholeRest, halfRest, quarterRest, eighthRest
        case staccato, slur, dynamics, pedal, repeatSign, fermata
    }

    let kind: Kind
    private static let font = "Apple Symbols"

    /// The real glyph for the signs that have one in Unicode's music block.
    static func glyph(_ k: Kind) -> String? {
        switch k {
        case .trebleClef: return "𝄞"
        case .bassClef: return "𝄢"
        case .whole: return "𝅝"
        case .half: return "𝅗𝅥"
        case .quarter: return "♩"
        case .eighth: return "♪"
        case .wholeRest: return "𝄻"
        case .halfRest: return "𝄼"
        case .quarterRest: return "𝄽"
        case .eighthRest: return "𝄾"
        case .repeatSign: return "𝄆 𝄇"
        case .fermata: return "𝄐"
        case .barline: return "𝄀"
        default: return nil
        }
    }

    /// Every character of `s` has a glyph in the music font (a missing font falls back to one without them = false).
    static func fontHas(_ s: String) -> Bool {
        let f = CTFontCreateWithName(font as CFString, 20, nil)
        let chars = Array(s.replacingOccurrences(of: " ", with: "").utf16)
        var glyphs = [CGGlyph](repeating: 0, count: chars.count)
        return !chars.isEmpty && CTFontGetGlyphsForCharacters(f, chars, &glyphs, chars.count)
    }

    private static var cache: [String: Bool] = [:]
    private static func available(_ s: String) -> Bool {
        // launch argument -pt.drawSigns YES: always the drawn version (to check what an iOS 17 device shows)
        if UserDefaults.standard.bool(forKey: "pt.drawSigns") { return false }
        if let v = cache[s] { return v }
        let v = fontHas(s)
        cache[s] = v
        return v
    }

    private static let ink = Color(hex: 0x1d1d1f), paper = Color(hex: 0xf4f2ec)

    var body: some View {
        if let g = Self.glyph(kind), Self.available(g) {
            Text(g)
                .font(.custom(Self.font, size: g.count > 2 ? 26 : 40))
                .minimumScaleFactor(0.4)
                .foregroundStyle(Self.ink)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Self.paper, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .accessibilityHidden(true)
        } else {
            drawn
        }
    }

    private var drawn: some View {
        Canvas { g, size in
            // a 64-unit box; staff lines at y 18…46 (7 apart), middle line = 32
            g.scaleBy(x: size.width / 64, y: size.height / 64)
            draw(&g)
        }
        .background(Self.paper, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityHidden(true)
    }

    private func line(_ y: CGFloat) -> CGFloat { 18 + 7 * y }           // staff line 0 (top) … 4 (bottom)

    private func draw(_ g: inout GraphicsContext) {
        let ink = GraphicsContext.Shading.color(Self.ink)
        func stroke(_ p: Path, _ w: CGFloat = 1) { g.stroke(p, with: ink, lineWidth: w) }
        func staff(from x0: CGFloat = 4, to x1: CGFloat = 60) {
            for i in 0..<5 { stroke(Path { $0.move(to: CGPoint(x: x0, y: line(CGFloat(i)))); $0.addLine(to: CGPoint(x: x1, y: line(CGFloat(i)))) }, 0.8) }
        }
        func head(_ x: CGFloat, _ y: CGFloat, filled: Bool) {
            var h = g
            h.translateBy(x: x, y: y)
            h.rotate(by: .degrees(-20))
            let r = Path(ellipseIn: CGRect(x: -4.6, y: -3.3, width: 9.2, height: 6.6))
            if filled { h.fill(r, with: ink) } else { h.stroke(r, with: ink, lineWidth: 1.6) }
        }
        func stem(_ x: CGFloat, _ y: CGFloat) { stroke(Path { $0.move(to: CGPoint(x: x + 4.1, y: y - 1)); $0.addLine(to: CGPoint(x: x + 4.1, y: y - 21)) }, 1.2) }
        func note(_ x: CGFloat, _ y: CGFloat, filled: Bool = true, withStem: Bool = true) {
            head(x, y, filled: filled)
            if withStem { stem(x, y) }
        }
        func text(_ s: String, _ x: CGFloat, _ y: CGFloat, size: CGFloat, font: Font? = nil) {
            g.draw(Text(s).font(font ?? .custom("Apple Symbols", size: size)).foregroundColor(Self.ink), at: CGPoint(x: x, y: y))
        }
        switch kind {
        case .trebleClef: staff(); text("𝄞", 22, 31, size: 46)
        case .bassClef: staff(); text("𝄢", 24, 29, size: 34)
        case .sharp: staff(); text("♯", 24, line(2), size: 22); note(38, line(2), withStem: false)
        case .flat: staff(); text("♭", 24, line(2) - 3, size: 22); note(38, line(2), withStem: false)
        case .natural: staff(); text("♮", 24, line(2), size: 22); note(38, line(2), withStem: false)
        case .keySignature:
            staff(); text("𝄞", 13, 31, size: 46); text("♯", 30, line(0), size: 17); text("♯", 38, line(1.5), size: 17)
        case .ledger:
            staff(from: 4, to: 60)
            stroke(Path { $0.move(to: CGPoint(x: 25, y: line(5))); $0.addLine(to: CGPoint(x: 41, y: line(5))) }, 1.2)
            note(33, line(5), withStem: false)
        case .fingers:
            staff()                                    // heads only: the digits sit right above them, no stem in the way
            for (x, n, y) in [(16.0, "1", line(3)), (32.0, "2", line(2)), (48.0, "3", line(1))] {
                note(x, y, withStem: false)
                text(n, x, y - 10, size: 10, font: .system(size: 10, weight: .bold))
            }
        case .whole: staff(); note(32, line(2), filled: false, withStem: false)
        case .half: staff(); note(30, line(2.5), filled: false)
        case .quarter: staff(); note(30, line(2.5))
        case .eighth:
            staff(); note(30, line(2.5))
            stroke(Path { p in
                p.move(to: CGPoint(x: 34.1, y: line(2.5) - 21))
                p.addCurve(to: CGPoint(x: 40, y: line(2.5) - 8), control1: CGPoint(x: 36, y: line(2.5) - 16),
                           control2: CGPoint(x: 42, y: line(2.5) - 14))
            }, 1.6)
        case .dotted:
            staff(); note(28, line(2.5), filled: false)
            g.fill(Path(ellipseIn: CGRect(x: 37, y: line(2) + 1.5, width: 3, height: 3)), with: ink)
        case .tie:
            staff(); note(18, line(2.5)); note(44, line(2.5))
            stroke(Path { $0.move(to: CGPoint(x: 20, y: line(2.5) + 5)); $0.addQuadCurve(to: CGPoint(x: 44, y: line(2.5) + 5), control: CGPoint(x: 32, y: line(2.5) + 12)) }, 1.4)
        case .time:
            staff(); text("4", 32, line(1), size: 15, font: .system(size: 15, weight: .black)); text("4", 32, line(3), size: 15, font: .system(size: 15, weight: .black))
        case .barline:
            staff(); note(18, line(2.5)); note(46, line(2))
            stroke(Path { $0.move(to: CGPoint(x: 32, y: line(0))); $0.addLine(to: CGPoint(x: 32, y: line(4))) }, 1.4)
        case .wholeRest: staff(); g.fill(Path(CGRect(x: 26, y: line(1), width: 12, height: 3.6)), with: ink)
        case .halfRest: staff(); g.fill(Path(CGRect(x: 26, y: line(2) - 3.6, width: 12, height: 3.6)), with: ink)
        case .quarterRest:
            staff()
            stroke(Path { p in
                p.move(to: CGPoint(x: 29, y: line(0.6))); p.addLine(to: CGPoint(x: 35, y: line(1.5)))
                p.addLine(to: CGPoint(x: 29, y: line(2.3))); p.addLine(to: CGPoint(x: 35, y: line(3.1)))
                p.addQuadCurve(to: CGPoint(x: 30, y: line(3.9)), control: CGPoint(x: 26, y: line(3.1)))
            }, 2.2)
        case .eighthRest:
            staff()
            g.fill(Path(ellipseIn: CGRect(x: 27, y: line(1.6), width: 4.2, height: 4.2)), with: ink)
            stroke(Path { $0.move(to: CGPoint(x: 30, y: line(2.1))); $0.addQuadCurve(to: CGPoint(x: 37, y: line(1.6)), control: CGPoint(x: 34, y: line(2.4))); $0.addLine(to: CGPoint(x: 31, y: line(3.6))) }, 1.6)
        case .staccato:
            staff(); note(30, line(2.5))
            g.fill(Path(ellipseIn: CGRect(x: 28.5, y: line(2.5) + 6, width: 3, height: 3)), with: ink)
        case .slur:
            staff(); note(16, line(3)); note(32, line(2)); note(48, line(1))
            stroke(Path { $0.move(to: CGPoint(x: 18, y: line(3) - 25)); $0.addQuadCurve(to: CGPoint(x: 52, y: line(1) - 25), control: CGPoint(x: 34, y: 0)) }, 1.4)
        case .dynamics:
            text("p", 20, 32, size: 26, font: .system(size: 26, weight: .bold, design: .serif).italic())
            text("f", 44, 32, size: 26, font: .system(size: 26, weight: .bold, design: .serif).italic())
        case .pedal:
            text("Ped.", 26, 30, size: 18, font: .system(size: 18, weight: .bold, design: .serif).italic())
            text("✱", 52, 30, size: 14, font: .system(size: 14, weight: .bold))
        case .repeatSign:
            staff()
            for (x, w) in [(12.0, 3.0), (17.0, 1.0)] { stroke(Path { $0.move(to: CGPoint(x: x, y: line(0))); $0.addLine(to: CGPoint(x: x, y: line(4))) }, w) }
            for (x, w) in [(52.0, 3.0), (47.0, 1.0)] { stroke(Path { $0.move(to: CGPoint(x: x, y: line(0))); $0.addLine(to: CGPoint(x: x, y: line(4))) }, w) }
            for x in [21.0, 41.0] { for y in [line(1.5), line(2.5)] { g.fill(Path(ellipseIn: CGRect(x: x, y: y - 1.6, width: 3.2, height: 3.2)), with: ink) } }
        case .fermata:
            staff(); note(30, line(2.5), withStem: false)
            stroke(Path { $0.move(to: CGPoint(x: 22, y: 12)); $0.addQuadCurve(to: CGPoint(x: 38, y: 12), control: CGPoint(x: 30, y: 2)) }, 1.6)
            g.fill(Path(ellipseIn: CGRect(x: 28.5, y: 9, width: 3, height: 3)), with: ink)
        }
    }
}
