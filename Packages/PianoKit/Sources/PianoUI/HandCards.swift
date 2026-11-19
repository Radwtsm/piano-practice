import DesignKit
import PianoKit
import SwiftUI

/// One card per hand with a mini staff of the notes of this moment, their names and the chord name, plus
/// "Insieme si sente" when both hands together make a different chord.
struct HandCards: View {
    let trainer: Trainer
    @Environment(\.pianoScale) private var s

    var body: some View {
        // Suona libero needs no piece (the app opens in it); practice and listening do
        if trainer.mode == .free || trainer.piece != nil {
            let events = trainer.piece?.events ?? []
            let t = trainer.currentTime
            // Suona libero: what you hold now, split at middle C
            let held = trainer.held.sorted().map {
                Piece.Event(s: 0, d: 1, n: $0, h: $0 < 60 ? .left : .right, f: "", staccato: false, b: 0)
            }
            let at = trainer.mode == .free ? held : trainer.mode == .listen
                ? trainer.evs.filter { abs($0.s - t) < Trainer.eps }
                : events.filter { abs($0.s - t) < Trainer.eps && trainer.hands.rawValue.contains($0.h.rawValue) }
            let r = at.filter { $0.h == .right }, l = at.filter { $0.h == .left }
            // everything sounding at this moment (both hands, held notes too) = the harmony you hear
            let sounding = trainer.mode == .free ? held
                : events.filter { $0.s <= t + Trainer.eps && t < $0.s + $0.d - Trainer.eps }
            let all = sounding.count > 1 ? Chords.describe(sounding.map(\.n)) : nil
            // Fixed slots and heights (playing must not move the page): the staff is always there,
            // "Insieme si sente" always has its place, text shrinks instead of wrapping.
            HStack(alignment: .top, spacing: 12) {
                // left hand on the left, as on the keyboard
                // Suona libero is not tied to the piece: no key signature of it on the staves
                let fifths = trainer.mode == .free ? 0 : trainer.piece?.fifths ?? 0
                card(.left, "Mano sinistra", l, fifths: fifths)
                card(.right, "Mano destra", r, fifths: fifths)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Insieme si sente").font(.system(size: 13 * s, weight: .semibold)).foregroundStyle(Theme.mute)
                    Text(all?.title ?? "—").font(.display(30 * s)).foregroundStyle(Theme.ink)
                        .lineLimit(1).minimumScaleFactor(0.5)
                    Text(all?.detail ?? " ").font(.system(size: 15 * s)).foregroundStyle(Theme.mute)
                        .lineLimit(3).minimumScaleFactor(0.6)
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .modifier(Panel())
                .frame(width: 260 * s)
            }
            .frame(height: Self.height(s))
        }
    }

    /// The cards' fixed height: the mini staff plus the panel's padding.
    static func height(_ s: CGFloat) -> CGFloat { 104 * s + 20 }

    private func card(_ h: Piece.Hand, _ title: String, _ evs: [Piece.Event], fifths: Int) -> some View {
        let d = Chords.describe(evs.map(\.n))
        return HStack(alignment: .center, spacing: 14) {
            MiniStaff(notes: evs.map(\.n), treble: h == .right, fifths: fifths, color: Theme.hand(h))
                .frame(width: 150 * s, height: 104 * s)
                .background(Theme.paper, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .opacity(d == nil ? 0.5 : 1)
            FingerHand(hand: h, lit: Set(evs.compactMap { Fingering.first($0.f) }))
                .frame(width: 66 * s, height: 70 * s)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13 * s, weight: .semibold)).foregroundStyle(Theme.hand(h))
                Text(d?.title ?? "pausa").font(.display(30 * s)).foregroundStyle(d == nil ? Theme.mute : Theme.ink)
                    .lineLimit(1).minimumScaleFactor(0.5)
                Group {
                    if let d { (evs.count > 1 ? noteList(evs) + Text(" — ") : Text("")) + Text(d.detail) } else { Text(" ") }
                }
                // same sizes as "Insieme si sente" (consistent); 3 lines so a chord's notes with
                // fingers and its inversion fit without "…"
                .font(.system(size: 15 * s))
                .foregroundStyle(Theme.mute)
                .lineLimit(3)
                .minimumScaleFactor(0.6)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding(.vertical, -0)
        .modifier(Panel())
    }

    private func noteList(_ evs: [Piece.Event]) -> Text {
        var out = Text("")
        for (i, e) in evs.sorted(by: { $0.n < $1.n }).enumerated() {
            if i > 0 { out = out + Text(" · ") }
            out = out + Text(noteName(e.n)).bold().foregroundColor(Theme.ink)
            if !e.f.isEmpty { out = out + Text(" (dito \(e.f))").font(.system(size: 13 * s)) }
        }
        return out
    }
}

struct Panel: ViewModifier {
    func body(content: Content) -> some View {
        content.appPanel()
    }
}

/// A small staff with only the notes of this moment, as the sheet prints them.
struct MiniStaff: View {
    let notes: [Int]
    let treble: Bool
    let fifths: Int
    let color: Color

    private static let sharpSp = [(0, 0), (0, 1), (1, 0), (1, 1), (2, 0), (3, 0), (3, 1), (4, 0), (4, 1), (5, 0), (5, 1), (6, 0)]
    private static let flatSp = [(0, 0), (1, -1), (1, 0), (2, -1), (2, 0), (3, 0), (4, -1), (4, 0), (5, -1), (5, 0), (6, -1), (6, 0)]
    private static let sharpOrder = [3, 0, 4, 1, 5, 2, 6], flatOrder = [6, 2, 5, 1, 4, 0, 3]
    private static let sharpPos = [38, 35, 39, 36, 33, 37, 34], flatPos = [34, 37, 33, 36, 32, 35, 31]

    var body: some View {
        Canvas { g, size in
            g.scaleBy(x: size.width / 150, y: size.height / 104)
            let sp: CGFloat = 7, W: CGFloat = 150, top: CGFloat = 30
            let bottomD = treble ? 30 : 18                  // E4 / G2 sit on the bottom line
            func yOf(_ d: Int) -> CGFloat { top + 8 * sp - CGFloat(d - bottomD) * sp }
            func line(_ x1: CGFloat, _ x2: CGFloat, _ y: CGFloat) {
                g.stroke(Path { $0.move(to: CGPoint(x: x1, y: y)); $0.addLine(to: CGPoint(x: x2, y: y)) },
                         with: .color(Color(hex: 0x333333)), lineWidth: 1)
            }
            let ink = Color(hex: 0x222222)
            for i in 0..<5 { line(4, W - 4, top + CGFloat(i) * 2 * sp) }
            if treble {
                g.draw(Text("𝄞").font(.custom("Apple Symbols", size: 78)).foregroundColor(ink),
                       at: CGPoint(x: 4, y: top + 8 * sp + 12), anchor: .bottomLeading)
            } else {
                g.draw(Text("𝄢").font(.custom("Apple Symbols", size: 60)).foregroundColor(ink),
                       at: CGPoint(x: 5, y: top + 8 * sp + 2), anchor: .bottomLeading)
            }
            let n = min(7, abs(fifths)), shift = treble ? 0 : -14
            for i in 0..<n {
                let d = (fifths > 0 ? Self.sharpPos : Self.flatPos)[i] + shift
                g.draw(Text(fifths > 0 ? "♯" : "♭").font(.system(size: 17)).foregroundColor(ink),
                       at: CGPoint(x: 38 + CGFloat(i) * 8, y: yOf(d)))
            }
            func keyAcc(_ l: Int) -> Int {
                fifths > 0 && Self.sharpOrder.prefix(n).contains(l) ? 1 : fifths < 0 && Self.flatOrder.prefix(n).contains(l) ? -1 : 0
            }
            let xs = 46 + CGFloat(n) * 8 + 22
            var prevD: Int?, flip = false
            for m in Set(notes).sorted() {
                let (letter, acc) = (fifths < 0 ? Self.flatSp : Self.sharpSp)[m % 12]
                let d = (m / 12 - 1) * 7 + letter
                flip = prevD.map { d - $0 == 1 } == true ? !flip : false   // a second: put the upper note beside
                prevD = d
                let x = xs + (flip ? 13 : 0), y = yOf(d)
                var dd = bottomD - 2
                while dd >= d { line(x - 10, x + 10, yOf(dd)); dd -= 2 }
                dd = bottomD + 10
                while dd <= d { line(x - 10, x + 10, yOf(dd)); dd += 2 }
                var head = Path(ellipseIn: CGRect(x: -7.2, y: -5.4, width: 14.4, height: 10.8))
                head = head.applying(CGAffineTransform(rotationAngle: -20 * .pi / 180).concatenating(.init(translationX: x, y: y)))
                g.fill(head, with: .color(color))
                g.stroke(head, with: .color(ink), lineWidth: 1)
                if acc != keyAcc(letter) {
                    g.draw(Text(acc > 0 ? "♯" : acc < 0 ? "♭" : "♮").font(.system(size: 16)).foregroundColor(ink),
                           at: CGPoint(x: xs - 15, y: y))
                }
            }
        }
        .accessibilityLabel("note sul pentagramma")
    }
}

/// A hand drawn as five fingers, numbered 1 (thumb) to 5, the ones to use now lit in the hand's colour.
/// Seen from above, palm down: the right thumb on the left, the left thumb on the right — as they lie on the keys.
struct FingerHand: View {
    let hand: Piece.Hand
    let lit: Set<Int>
    @Environment(\.pianoScale) private var s

    private static let lengths: [CGFloat] = [0.55, 0.85, 1, 0.9, 0.7]   // thumb … little finger

    var body: some View {
        let order = hand == .right ? [1, 2, 3, 4, 5] : [5, 4, 3, 2, 1]
        HStack(alignment: .bottom, spacing: 3 * s) {
            ForEach(order, id: \.self) { f in
                let on = lit.contains(f)
                GeometryReader { g in
                    VStack {
                        Spacer(minLength: 0)
                        Text("\(f)").font(.system(size: 12 * s, weight: .bold)).monospacedDigit()
                            .foregroundStyle(on ? Theme.dark : Theme.mute)
                            .frame(width: g.size.width, height: g.size.height * Self.lengths[f - 1], alignment: .top)
                            .padding(.top, 2)
                            .background(on ? Theme.hand(hand) : Theme.mute.opacity(0.18),
                                        in: Capsule(style: .continuous))
                    }
                }
            }
        }
        .accessibilityElement()
        .accessibilityLabel(lit.isEmpty ? "Mano" : "Dita: " + lit.sorted().map { "\($0) \(Fingering.names[$0 - 1])" }.joined(separator: ", "))
    }
}
