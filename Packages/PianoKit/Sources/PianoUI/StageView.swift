import DesignKit
import PianoKit
import QuartzCore
import SwiftUI

/// Falling notes onto the drawn V49. Touch/click a key = play it.
struct StageView: View {
    let trainer: Trainer
    @Environment(\.pianoScale) private var s
    @State private var touchKey: Int?

    struct Key { var x: CGFloat, w: CGFloat, black: Bool }

    struct Layout {
        var roll: CGFloat, kb: CGFloat, width: CGFloat
        var keys: [Int: Key] = [:]

        init(size: CGSize, lo: Int, hi: Int, scale s: CGFloat) {
            width = size.width
            kb = max(95, min(170 * s, size.width * 0.15, size.height * 0.45))
            roll = max(60, size.height - kb - 22 * s)
            let whites = (lo...hi).filter { !isBlack($0) }.count
            let ww = size.width / CGFloat(max(1, whites)), bw = ww * 0.62
            var wi: CGFloat = 0
            for m in lo...hi {
                if isBlack(m) { keys[m] = Key(x: wi * ww - bw / 2, w: bw, black: true) }
                else { keys[m] = Key(x: wi * ww, w: ww, black: false); wi += 1 }
            }
        }

        func key(at p: CGPoint, lo: Int, hi: Int) -> Int? {
            guard p.y >= roll + 4 else { return nil }
            for m in lo...hi { if let k = keys[m], k.black, p.y < roll + kb * 0.62, p.x >= k.x, p.x < k.x + k.w { return m } }
            for m in lo...hi { if let k = keys[m], !k.black, p.x >= k.x, p.x < k.x + k.w { return m } }
            return nil
        }
    }

    var body: some View {
        GeometryReader { geo in
            let lay = Layout(size: geo.size, lo: trainer.lo, hi: trainer.hi, scale: s)
            TimelineView(.animation) { tl in
                Canvas { g, size in
                    _ = tl.date                                   // redraw every frame
                    draw(&g, size, lay, now: CACurrentMediaTime())
                }
                .accessibilityLabel("Note che scendono sulla tastiera")
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { v in
                    let m = lay.key(at: v.location, lo: trainer.lo, hi: trainer.hi)
                    guard m != touchKey else { return }
                    if let old = touchKey { trainer.noteOff(old) }
                    touchKey = m
                    if let m { trainer.noteOn(m) }
                }
                .onEnded { _ in
                    if let old = touchKey { trainer.noteOff(old) }
                    touchKey = nil
                })
        }
        .overlay(alignment: .top) { GeometryReader { geo in finishedPanel(rollHeight: Layout(size: geo.size, lo: trainer.lo, hi: trainer.hi, scale: s).roll) } }
        .background(Theme.stage)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    /// "Lezione finita!" with two big buttons (touch), over the falling notes; the keys work too (see Trainer.noteOn).
    @ViewBuilder private func finishedPanel(rollHeight: CGFloat) -> some View {
        if trainer.finished && trainer.mode == .practice {
            let r = trainer.lastRound
            VStack(spacing: 10 * s) {
                Text(trainer.drillDone ? "Punti deboli superati!" : r?.clean == true ? "Giro perfetto!" : "Lezione finita!")
                    .font(.display(28 * s)).foregroundStyle(Theme.ok)
                if let r, !r.clean {
                    summary(r)
                }
                // one row when it fits, else the main choices first and the others below (smaller)
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 12 * s) { secondaryPills(r); mainPills(r) }
                    VStack(spacing: 10 * s) {
                        HStack(spacing: 12 * s) { mainPills(r) }
                        HStack(spacing: 12 * s) { secondaryPills(r) }
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: max(0, rollHeight - 44 * s))
        }
    }

    /// "Tasti sbagliati 3 · esitazioni 1 · accordi staccati 1 — più difficili: battute 5, 7"
    private func summary(_ r: Round) -> some View {
        let t = r.total
        let parts = [t.wrong > 0 ? "tasti sbagliati \(t.wrong)" : nil, t.hesitations > 0 ? "esitazioni \(t.hesitations)" : nil,
                     t.chordBreaks > 0 ? "accordi staccati \(t.chordBreaks)" : nil].compactMap { $0 }
        let weak = r.weakest().map(String.init).joined(separator: ", ")
        return Text(parts.joined(separator: " · ").capitalizedFirst + (weak.isEmpty ? "" : " — più difficili: battute \(weak)"))
            .font(.system(size: 17 * s, weight: .medium)).foregroundStyle(Theme.ink)
            .lineLimit(1).minimumScaleFactor(0.6)
            .padding(.horizontal, 24)
    }

    @ViewBuilder private func mainPills(_ r: Round?) -> some View {
        pill("Rifai", "arrow.counterclockwise", fill: Theme.panel2) { trainer.redo() }
        if let r, !r.clean {
            pill("Esercita i punti deboli", "scope", fill: Theme.panel2) { trainer.practiceWeak() }
                .accessibilityHint("Ripete le battute più difficili finché fai 3 giri puliti di fila")
        }
        if let next = trainer.nextLessonName {
            pill(next, "arrow.right", fill: Theme.accent, trailingIcon: true) { trainer.nextLesson() }
        }
    }

    @ViewBuilder private func secondaryPills(_ r: Round?) -> some View {
        pill("In loop", "repeat", fill: Theme.panel2) { trainer.loop = true; trainer.redo() }
            .accessibilityHint("Rifà questa lezione a ruota finché non togli il loop")
        pill("Suona libero", "pianokeys", fill: Theme.panel2) { trainer.startFree() }
    }

    private func pill(_ title: String, _ symbol: String, fill: Color, trailingIcon: Bool = false,
                      action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8 * s) {
                if !trailingIcon { Image(systemName: symbol) }
                Text(title)
                if trailingIcon { Image(systemName: symbol) }
            }
            .font(.system(size: 17 * s, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 18 * s).padding(.vertical, 11 * s)
            .glass(Capsule(), tint: fill == Theme.accent ? Theme.accent : nil, interactive: true)
        }
        .buttonStyle(.plain)
    }

    private func label(_ s: String, _ size: CGFloat, _ weight: Font.Weight, _ color: Color) -> Text {
        Text(s).font(.system(size: size, weight: weight)).foregroundColor(color)
    }

    private func draw(_ g: inout GraphicsContext, _ size: CGSize, _ lay: Layout, now: Double) {
        let listening = trainer.mode == .listen, free = trainer.mode == .free
        let piece = trainer.piece
        guard free || piece != nil else { return }               // Suona libero needs no piece (the app opens in it)
        let W = size.width, ROLL = lay.roll, KB = lay.kb, keys = lay.keys
        let ph = trainer.phase(at: now)
        let win = piece != nil ? 2 * trainer.bar(trainer.range.a).len : 8, pps = ROLL / win
        g.fill(Path(CGRect(x: 0, y: 0, width: W, height: ROLL)), with: .color(Theme.stage))
        for m in stride(from: trainer.lo, through: trainer.hi, by: 12) {
            guard let k = keys[m] else { continue }
            let x = k.x.rounded() + 0.5
            g.stroke(Path { $0.move(to: CGPoint(x: x, y: 0)); $0.addLine(to: CGPoint(x: x, y: ROLL)) },
                     with: .color(Color(hex: 0x1d212a)), lineWidth: 1)
        }
        for B in free ? [] : piece?.bars ?? [] {             // Suona libero: no bars of the piece
            let y = ROLL - (B.start - ph) * pps
            guard y >= 0, y <= ROLL else { continue }
            let yy = y.rounded() + 0.5
            g.stroke(Path { $0.move(to: CGPoint(x: 0, y: yy)); $0.addLine(to: CGPoint(x: W, y: yy)) },
                     with: .color(Theme.line), lineWidth: 1)
            g.draw(label("batt. " + B.label, 13 * s, .semibold, Color(hex: 0x6c7382)), at: CGPoint(x: 6, y: y - 9 * s), anchor: .leading)
        }
        let cur: Double? = !listening && trainer.steps.indices.contains(trainer.stepIdx) ? trainer.steps[trainer.stepIdx] : nil
        let got = trainer.got, held = trainer.held
        for e in (free ? [] : trainer.evs) {
            let yb = ROLL - (e.s - ph) * pps, yt = ROLL - (e.s + e.d - ph) * pps
            guard yb >= 0, yt <= ROLL, let k = keys[e.n] else { continue }
            let pad: CGFloat = k.black ? 1 : 2
            let top = max(0, yt + 1), bot = min(ROLL, yb - 1)
            guard bot - top >= 2 else { continue }
            let isCur = cur.map { abs(e.s - $0) < Trainer.eps } ?? false
            var layer = g
            layer.opacity = cur.map { e.s < $0 - Trainer.eps } == true ? 0.25 : (isCur || listening ? 1 : 0.7)
            let fill = isCur && got.contains(e.n) && held.contains(e.n) ? Theme.ok : Theme.hand(e.h)
            layer.fill(Path(roundedRect: CGRect(x: k.x + pad, y: top, width: k.w - pad * 2, height: bot - top), cornerRadius: 4),
                       with: .color(fill))
            if bot - top > 16 * s, !e.f.isEmpty {
                layer.draw(label(e.f, min(15 * s, k.w * 0.7), .bold, e.suggested ? Theme.dark.opacity(0.5) : Theme.dark), at: CGPoint(x: k.x + k.w / 2, y: bot - 10 * s))
            }
        }
        if free {
            g.draw(Text("Suona libero").font(.display(26 * s)).foregroundColor(Theme.mute.opacity(0.6)),
                   at: CGPoint(x: W / 2, y: ROLL / 2))
        } else if trainer.finished {
            g.fill(Path(CGRect(x: 0, y: 0, width: W, height: ROLL)), with: .color(Color(hex: 0x0d0f13, alpha: 0.82)))
            // where to press: left of middle C = redo, middle C and up = next lesson
            let mid = keys[60]?.x ?? W / 2
            g.draw(label("← tasto qui = rifai la lezione", 17 * s, .bold, Theme.ink), at: CGPoint(x: mid / 2, y: ROLL - 22 * s))
            g.draw(label(trainer.nextLessonName.map { "tasto qui = \($0) →" } ?? "fine del brano", 17 * s, .bold,
                         trainer.nextLessonName != nil ? Theme.ok : Theme.mute),
                   at: CGPoint(x: (mid + W) / 2, y: ROLL - 22 * s))
            g.stroke(Path { $0.move(to: CGPoint(x: mid, y: ROLL - 44)); $0.addLine(to: CGPoint(x: mid, y: ROLL)) },
                     with: .color(Theme.mute), lineWidth: 1)
        }
        var lit: [Int: Piece.Event] = [:]
        if listening { for e in trainer.evs where e.s <= ph && ph < e.s + e.d { lit[e.n] = e } }
        else if !trainer.finished && !free { for e in trainer.stepNotes { lit[e.n] = e } }
        let ky = ROLL
        g.fill(Path(CGRect(x: 0, y: ky, width: W, height: 4)), with: .color(Color(hex: 0x05060a)))
        // Key states: hand colour = to play (sunk + 'ripremi' = still held from the step before); green = pressed now
        // and right; red = pressed in this step and wrong; grey = held but not asked now; ✓ = played in this step, released.
        func drawKey(_ m: Int, _ k: Key) {
            let h = k.black ? KB * 0.62 : KB, e = lit[m], down = held.contains(m)
            let done = !listening && got.contains(m)
            let wt = trainer.wrong[m]
            var fill = k.black ? Color(hex: 0x181a20) : Color(hex: 0xf4f2ec)
            let isWrong = !(down && done) && (trainer.wrongHeld.contains(m) || (wt.map { now - $0 < 0.45 } ?? false))
            if down && done { fill = Theme.ok }
            else if isWrong { fill = Theme.bad }
            else if let e { fill = Theme.hand(e.h) }
            else if down && free { fill = Theme.hand(m < 60 ? .left : .right) }
            else if down { fill = k.black ? Color(hex: 0x7d8597) : Color(hex: 0x9aa3b5) }
            let sink: CGFloat = down ? 4 : 0, x = k.x + (k.black ? 0 : 0.5), w = k.w - (k.black ? 0 : 1), y = ky + 4 + sink
            let shape = Path(roundedRect: CGRect(x: x, y: y, width: w, height: h - 4 - sink), cornerRadius: k.black ? 3 : 5)
            g.fill(shape, with: .color(fill))
            if !k.black { g.stroke(shape, with: .color(Theme.stage), lineWidth: 1) }
            if down {                                         // dot at the bottom = "your finger is on it"
                let r = min(4, k.w * 0.18)
                g.fill(Path(ellipseIn: CGRect(x: k.x + k.w / 2 - r, y: ky + h - 6 - r, width: 2 * r, height: 2 * r)),
                       with: .color(k.black ? Color(hex: 0xf4f2ec) : Theme.dark))
                g.fill(Path(CGRect(x: x, y: y, width: w, height: 14)),
                       with: .linearGradient(Gradient(colors: [.black.opacity(0.55), .clear]),
                                             startPoint: CGPoint(x: 0, y: y), endPoint: CGPoint(x: 0, y: y + 14)))
            }
            if down && free {
                g.draw(label(noteName(m), min(13 * s, k.w * (k.black ? 0.62 : 0.45)), .bold, Theme.dark),
                       at: CGPoint(x: k.x + k.w / 2, y: ky + h - 16 * s + sink))
            }
            if let e {
                if !e.f.isEmpty {
                    g.draw(label(e.f, min(18 * s, k.w * 0.8), .bold, e.suggested ? Theme.dark.opacity(0.5) : Theme.dark),   // lighter = suggested
                           at: CGPoint(x: k.x + k.w / 2, y: ky + h - (k.black ? 14 : 36) * s + sink))
                }
                let t = label(noteName(m), min(11 * s, k.w * (k.black ? 0.62 : 0.45)), .bold, Theme.dark)
                if !k.black { g.draw(t, at: CGPoint(x: k.x + k.w / 2, y: ky + h - 16 * s + sink)) }
                else {
                    var r = g
                    r.translateBy(x: k.x + k.w / 2, y: ky + h - 32 * s + sink)
                    r.rotate(by: .degrees(-90))
                    r.draw(t, at: .zero, anchor: .leading)
                }
                if down && !done && !listening {               // still held from the step before: strike it again
                    let tw: CGFloat = 58 * s
                    g.fill(Path(roundedRect: CGRect(x: k.x + k.w / 2 - tw / 2, y: ky - 20 * s, width: tw, height: 17 * s), cornerRadius: 8 * s),
                           with: .color(Theme.hand(e.h)))
                    g.draw(label("ripremi", 12 * s, .bold, Theme.dark), at: CGPoint(x: k.x + k.w / 2, y: ky - 11.5 * s))
                }
            }
            if isWrong {                                      // ✕ = wrong, so a wrong key never reads as the right hand's red
                g.draw(label("✕", min(16 * s, k.w * 0.6), .heavy, .white), at: CGPoint(x: k.x + k.w / 2, y: ky + h * 0.45 + sink))
            }
            if done && !down {
                let cy = ky - 11 * s, r = min(9 * s, k.w * 0.42)       // badge just above the key, never under a black key
                g.fill(Path(ellipseIn: CGRect(x: k.x + k.w / 2 - r, y: cy - r, width: 2 * r, height: 2 * r)), with: .color(Theme.ok))
                g.draw(label("✓", min(12 * s, k.w * 0.5), .bold, Theme.dark), at: CGPoint(x: k.x + k.w / 2, y: cy + 0.5))
            }
        }
        for m in trainer.lo...trainer.hi { if let k = keys[m], !k.black { drawKey(m, k) } }
        for m in trainer.lo...trainer.hi { if let k = keys[m], k.black { drawKey(m, k) } }
        for m in stride(from: trainer.lo, through: trainer.hi, by: 12) {
            guard let k = keys[m] else { continue }
            g.draw(label(m == 60 ? "Do centrale" : "Do", 12 * s, .semibold, Theme.mute), at: CGPoint(x: k.x + k.w / 2, y: ky + KB + 11 * s))
            if m == 60 && lit[60] == nil {
                g.fill(Path(ellipseIn: CGRect(x: k.x + k.w / 2 - 3.5, y: ky + KB - 11.5, width: 7, height: 7)), with: .color(Theme.mute))
            }
        }
    }
}

extension String {
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}
