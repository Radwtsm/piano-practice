import DesignKit
import PianoKit
import SwiftUI

/// A melody on the staff, note by note (prima vista): quarters filled, halves hollow, stems, bar lines; the note to
/// read in yellow ("this one", as in Impara), the ones done green (first try) or red (after a mistake).
struct MelodyStaff: View {
    let melody: Melody
    let current: Int?
    let firstTry: [Int: Bool]

    var body: some View {
        Canvas { g, size in draw(&g, size) }
            .background(StaffView.paper, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .accessibilityElement()
            .accessibilityLabel("Melodia di \(melody.notes.count) note in chiave di \(melody.clef == .treble ? "violino" : "basso")")
    }

    private func draw(_ g: inout GraphicsContext, _ size: CGSize) {
        let sp = min(size.height / 20, size.width / 30)
        let (y, x0) = StaffView.drawFrame(&g, size, sp: sp, clef: melody.clef, fifths: melody.fifths)
        let x1 = size.width - sp * 3, totalBeats = melody.beats.reduce(0, +)
        // as many bars as fit with room for each note (a phone shows 2 at a time, turning with the reading)
        let bars = max(1, min(totalBeats / 4, Int((x1 - x0) / (4 * 3.6 * sp))))
        let starts = melody.beats.indices.map { melody.beats[..<$0].reduce(0, +) }
        let page = ((current.map { starts[$0] } ?? totalBeats - 1) / 4) / bars
        let first = page * bars * 4, last = first + bars * 4
        let unit = (x1 - x0) / CGFloat(bars * 4)
        let bottom = Staff.bottomLine(melody.clef), middle = bottom + 4
        for (i, (m, b)) in zip(melody.notes, melody.beats).enumerated() where starts[i] >= first && starts[i] < last {
            let beat = starts[i] - first
            let p = Staff.spell(m, fifths: melody.fifths)
            let x = x0 + (CGFloat(beat) + 0.35) * unit, ny = y(p.d)
            var d = bottom - 2
            while d >= p.d { StaffView.ledger(&g, x, y(d), sp); d -= 2 }
            d = bottom + 10
            while d <= p.d { StaffView.ledger(&g, x, y(d), sp); d += 2 }
            let color: Color = i == current ? Theme.warn : firstTry[i].map { $0 ? Theme.ok : Theme.bad } ?? StaffView.ink
            var head = g
            head.translateBy(x: x, y: ny)
            head.rotate(by: .degrees(-20))
            let r = CGRect(x: -sp * 1.2, y: -sp * 0.85, width: sp * 2.4, height: sp * 1.7)
            if b >= 2 { head.stroke(Path(ellipseIn: r.insetBy(dx: sp * 0.15, dy: sp * 0.15)), with: .color(color), lineWidth: sp * 0.35) }
            else { head.fill(Path(ellipseIn: r), with: .color(color)) }
            if i == current { head.stroke(Path(ellipseIn: r), with: .color(StaffView.ink), lineWidth: max(1, sp * 0.18)) }
            let up = p.d < middle                                   // stem up below the middle line
            let sx = up ? x + sp * 1.1 : x - sp * 1.1
            g.stroke(Path { $0.move(to: CGPoint(x: sx, y: ny)); $0.addLine(to: CGPoint(x: sx, y: ny + (up ? -7 : 7) * sp)) },
                     with: .color(color), lineWidth: max(1, sp * 0.15))
            if p.acc != Staff.keyAccidental(letter: p.letter, fifths: melody.fifths) {
                g.draw(Text(p.acc > 0 ? "♯" : p.acc < 0 ? "♭" : "♮").font(.custom("Apple Symbols", size: sp * 3.4)).foregroundColor(color),
                       at: CGPoint(x: x - sp * 2.6, y: ny - (p.acc < 0 ? sp * 0.5 : 0)))
            }
            if i == current {                                       // a mark under the note to read
                g.fill(Path(roundedRect: CGRect(x: x - sp * 1.2, y: y(bottom - 6), width: sp * 2.4, height: sp * 0.5), cornerRadius: sp * 0.25),
                       with: .color(StaffView.ink))
            }
            let end = beat + b
            if end % 4 == 0 {                                       // bar line (thick at the melody's end)
                let bx = x0 + CGFloat(end) * unit - unit * 0.1
                let lw = first + end == totalBeats ? sp * 0.45 : max(1, sp * 0.12)
                g.stroke(Path { $0.move(to: CGPoint(x: bx, y: y(bottom + 8))); $0.addLine(to: CGPoint(x: bx, y: y(bottom))) },
                         with: .color(StaffView.ink), lineWidth: lw)
            }
        }
    }
}

/// Prima vista (percorso): read a new melody note by note with the name buttons (or the V49), then hear it.
struct SightReadingView: View {
    @Bindable var model: PianoModel
    let session: SightSession
    @Environment(\.pianoScale) private var s
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let c = 1 + (s - 1) * 0.4
        PianoSheet(title: "Prima vista · tappa \(session.tappa)", minWidth: 760, minHeight: 560) {
            GeometryReader { geo in
                let wide = geo.size.width > geo.size.height * 1.2
                VStack(alignment: .leading, spacing: 12) {
                    MelodyStaff(melody: session.melody, current: session.current.map { _ in session.index }, firstTry: session.firstTry)
                        .frame(height: wide ? geo.size.height * 0.48 : min(220 * c, geo.size.height * 0.4))
                    status(c)
                    Spacer(minLength: 0)
                    if session.finished {
                        HStack(spacing: 10) {
                            CapsuleAction(title: "Ascolta", symbol: "speaker.wave.2") { play() }
                            CapsuleAction(title: "Un'altra melodia", symbol: "arrow.forward", primary: true) { session.next() }
                        }
                    } else {
                        names(c, columns: 7)
                    }
                }
            }
        }
        .onAppear { model.sight = session }
        .onDisappear { model.sight = nil }
        .onChange(of: session.finished) { _, done in if done { PathProgress(quiz: model.quiz).add(.sight) } }
    }

    @ViewBuilder private func status(_ c: CGFloat) -> some View {
        Group {
            if session.finished {
                Label("\(session.rightFirst) note su \(session.melody.notes.count) al primo colpo · melodie oggi: \(session.done)",
                      systemImage: "checkmark.circle.fill").foregroundStyle(Theme.ok)
            } else if let w = session.wrongName {
                Label("Non è \(w): riprova", systemImage: "xmark.circle.fill").foregroundStyle(Theme.bad)
            } else {
                Text("Nota \(session.index + 1) di \(session.melody.notes.count): come si chiama?"
                     + (model.midi.sources.isEmpty ? "" : " Tocca il nome o suonala sulla V49"))
            }
        }
        .font(.system(size: 17 * c, weight: .semibold)).lineLimit(2).minimumScaleFactor(0.7)
    }

    private func names(_ c: CGFloat, columns: Int) -> some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: columns), spacing: 8) {
            ForEach(session.choices, id: \.self) { name in
                Button {
                    let note = session.current
                    if session.choose(name), let note {                 // right: hear it
                        let sound = model.trainer.sound
                        sound.note(note, at: sound.now, dur: 0.6, vel: 0.6)
                    }
                } label: {
                    Text(name).font(.system(size: 20 * c, weight: .bold)).lineLimit(1).minimumScaleFactor(0.6)
                        .foregroundStyle(session.wrongName == name ? .white : Theme.ink)
                        .frame(maxWidth: .infinity, minHeight: 52 * c)
                        .contentShape(Rectangle())
                        .glass(RoundedRectangle(cornerRadius: 14, style: .continuous), tint: session.wrongName == name ? Theme.bad : nil, interactive: true)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(name)
            }
        }
    }

    /// The melody at 80 bpm.
    private func play() {
        let sound = model.trainer.sound, beat = 0.75
        var t = sound.now + 0.1
        for (m, b) in zip(session.melody.notes, session.melody.beats) {
            sound.note(m, at: t, dur: Double(b) * beat * 0.95, vel: 0.6)
            t += Double(b) * beat
        }
    }
}
