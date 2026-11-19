import PianoKit
import SwiftUI

/// A staff with clef, key signature and some notes, as they look on the sheet
///). Drawn on paper colours, scaled to the frame it gets (height ≈ 0.7 × width reads best).
struct StaffView: View {
    let notes: [Int]
    let clef: Staff.Clef
    let fifths: Int
    var noteColor: Color = Theme.ink
    /// Steps drawn blue: a line gets a thick blue stroke, a space a soft blue band (the quiz's hint/anchor).
    var marks: [Int] = []
    /// The way from `from` to the note, numbered 1, 2, 3… step by step (the same numbers as the white keys on
    /// the quiz keyboard), and the finger above the note.
    var steps: (from: Int, to: Int)?
    var finger: Int?

    static let ink = Color(hex: 0x1d1d1f), paper = Color(hex: 0xf4f2ec)

    var body: some View {
        Canvas { g, size in draw(&g, size) }
            .background(Self.paper, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .accessibilityElement()
            .accessibilityLabel("Pentagramma in chiave di \(clef == .treble ? "violino" : "basso")")
    }

    private func draw(_ g: inout GraphicsContext, _ size: CGSize) {
        // sp = half the distance between two lines; the staff sits in the middle with room for 3 ledger lines each side
        let sp = min(size.height / 22, size.width / 26)
        let (y, notesX) = Self.drawFrame(&g, size, sp: sp, clef: clef, fifths: fifths)
        let bottom = Staff.bottomLine(clef)
        for d in marks {
            let ly = y(d), x0 = sp * 1.5, x1 = size.width - sp * 1.5
            if (d - bottom) % 2 == 0 {
                g.stroke(Path { $0.move(to: CGPoint(x: x0, y: ly)); $0.addLine(to: CGPoint(x: x1, y: ly)) },
                         with: .color(Theme.hint), lineWidth: max(2, sp * 0.4))
            } else {
                g.fill(Path(CGRect(x: x0, y: ly - sp * 0.8, width: x1 - x0, height: sp * 1.6)), with: .color(Theme.hint.opacity(0.25)))
            }
        }
        // notes (a chord = stacked; a second apart = the upper one beside)
        let xs = notesX
        var prev: Int?, flip = false
        for p in Set(notes).sorted().map({ Staff.spell($0, fifths: fifths) }) {
            flip = prev.map { p.d - $0 == 1 } == true ? !flip : false
            prev = p.d
            let x = xs + (flip ? sp * 2.1 : 0), ny = y(p.d)
            var d = bottom - 2
            while d >= p.d { Self.ledger(&g, x, y(d), sp); d -= 2 }
            d = bottom + 10
            while d <= p.d { Self.ledger(&g, x, y(d), sp); d += 2 }
            var head = g
            head.translateBy(x: x, y: ny)
            head.rotate(by: .degrees(-20))
            let r = CGRect(x: -sp * 1.2, y: -sp * 0.85, width: sp * 2.4, height: sp * 1.7)
            head.fill(Path(ellipseIn: r), with: .color(noteColor))
            head.stroke(Path(ellipseIn: r), with: .color(Self.ink), lineWidth: max(1, sp * 0.1))
            if let st = steps, st.to == p.d { drawSteps(&g, st, x: xs - sp * 3.6, y: y, sp: sp, bottom: bottom) }
            if let f = finger {
                let above = p.d < bottom + 9
                g.draw(Text("\(f)").font(.system(size: sp * 2.6, weight: .heavy)).foregroundColor(Theme.hint),
                       at: CGPoint(x: x, y: ny + (above ? -sp * 3.4 : sp * 3.4)))
            }
            if p.acc != Staff.keyAccidental(letter: p.letter, fifths: fifths) {
                g.draw(Text(p.acc > 0 ? "♯" : p.acc < 0 ? "♭" : "♮").font(.custom("Apple Symbols", size: sp * 3.4)).foregroundColor(Self.ink),
                       at: CGPoint(x: xs - sp * 2.6, y: ny - (p.acc < 0 ? sp * 0.5 : 0)))
            }
        }
    }

    /// A numbered dot on every step from `from` to the note, zigzag: lines on the left, spaces on the right (the dots
    /// are a step = half a line gap apart, so in one column they would overlap; the zigzag also shows line vs space).
    private func drawSteps(_ g: inout GraphicsContext, _ st: (from: Int, to: Int), x: CGFloat, y: (Int) -> CGFloat, sp: CGFloat,
                           bottom: Int) {
        let dir = st.to >= st.from ? 1 : -1, n = abs(st.to - st.from)
        guard n > 0 else { return }
        for k in 1...n {
            let d = st.from + k * dir, line = (d - bottom) % 2 == 0
            let c = CGPoint(x: x - (line ? sp * 1.6 : 0), y: y(d)), r = sp * 0.9
            g.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)), with: .color(Theme.hint))
            g.draw(Text("\(k)").font(.system(size: sp * 1.4, weight: .bold)).foregroundColor(.white), at: c)
        }
    }

    /// Lines, clef and key signature; returns the step → y mapping and where the notes may start (shared with
    /// `MelodyStaff`).
    static func drawFrame(_ g: inout GraphicsContext, _ size: CGSize, sp: CGFloat, clef: Staff.Clef, fifths: Int)
        -> (y: (Int) -> CGFloat, notesX: CGFloat) {
        let top = size.height / 2 - 4 * sp
        let bottom = Staff.bottomLine(clef)
        let y = { (d: Int) in top + 8 * sp - CGFloat(d - bottom) * sp }
        let x0 = sp * 1.5, x1 = size.width - sp * 1.5
        for i in 0..<5 {
            let ly = top + CGFloat(i) * 2 * sp
            g.stroke(Path { $0.move(to: CGPoint(x: x0, y: ly)); $0.addLine(to: CGPoint(x: x1, y: ly)) },
                     with: .color(ink), lineWidth: max(1, sp * 0.12))
        }
        // clef: the treble one curls around the G line, the bass one's dots sit around the F line
        let clefText = Text(clef == .treble ? "𝄞" : "𝄢")
            .font(.custom("Apple Symbols", size: sp * (clef == .treble ? 10.6 : 8.6))).foregroundColor(ink)
        g.draw(clefText, at: CGPoint(x: x0 + sp * 0.4, y: clef == .treble ? y(32) - sp * 0.9 : y(24) + sp * 2.05),
               anchor: .leading)
        // key signature
        let n = min(7, abs(fifths)), shift = clef == .treble ? 0 : -14
        let ksX = x0 + sp * 7.2                              // clear of the bass clef's dots
        for i in 0..<n {
            let d = (fifths > 0 ? Staff.sharpPos : Staff.flatPos)[i] + shift
            g.draw(Text(fifths > 0 ? "♯" : "♭").font(.custom("Apple Symbols", size: sp * 3.4)).foregroundColor(ink),
                   at: CGPoint(x: ksX + CGFloat(i) * sp * 1.4, y: y(d) - (fifths > 0 ? 0 : sp * 0.5)))
        }
        return (y, ksX + CGFloat(n) * sp * 1.4 + sp * 5)
    }

    static func ledger(_ g: inout GraphicsContext, _ x: CGFloat, _ y: CGFloat, _ sp: CGFloat) {
        g.stroke(Path { $0.move(to: CGPoint(x: x - sp * 1.9, y: y)); $0.addLine(to: CGPoint(x: x + sp * 1.9, y: y)) },
                 with: .color(ink), lineWidth: max(1, sp * 0.12))
    }
}
