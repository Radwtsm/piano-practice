import Foundation
import Observation
import QuartzCore

/// Practice and listen logic (without drawing): bar ranges, steps, the wait-for-the-right-keys
/// practice, listen mode at any speed, sustain pedal, V49 pads and pitch wheel. UI words are Italian on purpose.
@MainActor @Observable
public final class Trainer {
    /// `free` = Suona libero: the keys only make sound, no steps, back with `endFree`.
    public enum Mode { case practice, listen, free }
    public enum Hands: String, CaseIterable { case right = "R", left = "L", both = "RL" }
    public static let eps = 1e-6

    // piece + the bars practised (no named lessons, only bars chosen with a slider)
    public private(set) var piece: Piece?
    public private(set) var pieceName = ""
    public private(set) var range = (a: 1, b: 1)
    /// Only "Punti deboli" says something here now (the named lessons' tips are gone with them).
    public private(set) var tip = AttributedString()
    public private(set) var error: String?
    public private(set) var lo = 36                         // V49 with OCTAVE off: C2..C6
    public private(set) var hi = 84
    // steps
    public private(set) var hands: Hands = .both
    public var bpm = 60 { didSet { save("bpm", bpm); if mode == .listen { stopListen() } } }
    public var loop = false
    public private(set) var evs: [Piece.Event] = []
    public private(set) var steps: [Double] = []
    public private(set) var stepIdx = 0
    public private(set) var got = Set<Int>()
    public private(set) var held = Set<Int>()
    public private(set) var wrongHeld = Set<Int>()
    public private(set) var wrong: [Int: Double] = [:]       // key → time of the wrong press (red flash)
    public private(set) var finished = false
    /// Piano opens in Suona libero with no piece.
    public private(set) var mode = Mode.free
    /// Listen mode: the step on screen now (cards, status); practice uses `steps[stepIdx]`.
    public private(set) var listenStep: Double = 0
    public private(set) var listenPhase: Double = 0
    public private(set) var toast: (text: String, id: Int)?
    // pads
    public static let padActions = [("restart", "↺ Ricomincia la lezione"), ("bar", "↺ Ricomincia la battuta"),
                                    ("hear", "Fammi sentire"), ("listen", "▶ Ascolta / ■ Ferma"),
                                    ("prevLes", "← Lezione prima"), ("nextLes", "Lezione dopo →"),
                                    ("hands", "Cambia mani"), ("loop", "Ripeti sì / no")]
    public private(set) var padMap: [String]
    public private(set) var learning = -1
    public private(set) var padHit = -1
    public private(set) var padMessage = ""

    @ObservationIgnored public let sound: Sampler
    /// Called on every key press (the screen hides its controls while you play).
    @ObservationIgnored public var onPlay: () -> Void = {}
    @ObservationIgnored private var live: [Int: Sampler.Voice] = [:]
    @ObservationIgnored private var sustained = Set<Int>()
    @ObservationIgnored private var pedal = false
    @ObservationIgnored private var t0 = 0.0
    @ObservationIgnored private var from = 0.0
    @ObservationIgnored private var to = 0.0
    @ObservationIgnored private var listenTimer: Timer?
    @ObservationIgnored private var glide = (from: 0.0, to: 0.0, t: 0.0)
    @ObservationIgnored private var wheelArmed = true
    @ObservationIgnored private var finishedAt = 0.0
    // play statistics: wrong keys, hesitations, chords let go, per bar, per day
    /// The round just ended (summary on the "Lezione finita" screen).
    public private(set) var lastRound: Round?
    /// "Esercita i punti deboli": the weakest bars in loop until 3 clean rounds in a row.
    public private(set) var drilling = false
    public private(set) var drillClean = 0
    public private(set) var drillDone = false
    @ObservationIgnored public var stats = StatsStore()
    @ObservationIgnored private var round = Round()
    @ObservationIgnored private var stepShownAt = 0.0
    @ObservationIgnored private var timedStep = -1
    /// After "Lezione finita", keys pressed within this time are the end of the last chord, not "go on".
    static var finishGrace = 0.8
    @ObservationIgnored private var toastCount = 0
    @ObservationIgnored private let defaults = UserDefaults.standard

    public init(sound: Sampler) {
        self.sound = sound
        let saved = UserDefaults.standard.stringArray(forKey: "pt:pads")
        padMap = saved?.count == 8 ? saved! : (36...43).map { "9:\($0)" }
        if let h = UserDefaults.standard.string(forKey: "pt:hands").flatMap(Hands.init) { hands = h }
    }

    // MARK: piece + bars

    public func open(name: String, data: Data) {
        if mode == .listen { stopListen() }
        let p: Piece
        do { p = try Piece.load(name: name, data: data).withSuggestedFingers() } catch {   // fingers for every hand
            self.error = error.localizedDescription
            return
        }
        error = nil
        piece = p
        pieceName = name
        let ns = p.events.map(\.n)
        if let l = ns.min(), let h = ns.max() {
            lo = min(36, l / 12 * 12)
            hi = max(84, (h + 12) / 12 * 12)
        }
        let sb = defaults.integer(forKey: key("bpm"))
        bpm = sb >= 30 && sb <= 160 ? sb : min(60, Int(p.tempo.rounded()))
        let sa = defaults.integer(forKey: key("a")), se = defaults.integer(forKey: key("b"))
        if sa >= 1 && se >= sa { selectRange(sa, se) } else { selectRange(1, 4) }   // first time: the first 4 bars
    }

    /// Notes outside the 49 keys (the by-line says "usa OCTAVE").
    public var outOfRange: Bool {
        guard let ns = piece?.events.map(\.n), let l = ns.min(), let h = ns.max() else { return false }
        return l < 36 || h > 84
    }

    private func key(_ k: String) -> String { "pt:\(pieceName):\(k)" }
    private func save(_ k: String, _ v: Int) { if !pieceName.isEmpty { defaults.set(v, forKey: key(k)) } }

    public func selectRange(_ a: Int, _ b: Int, tip: AttributedString = AttributedString()) {
        drilling = false
        drillDone = false
        if mode == .free { mode = .practice }
        if mode == .listen { stopListen() }
        guard let n = piece?.bars.count else { return }
        let a = max(1, min(n, a))
        range = (a, max(a, min(n, b)))
        save("a", range.a)
        save("b", range.b)
        self.tip = tip
        rebuild()
    }

    /// "Battute 5–8", or "Tutto il brano".
    public var rangeName: String {
        range.a == 1 && range.b == (piece?.bars.count ?? 0) ? "Tutto il brano" : "Battute \(range.a)–\(range.b)"
    }

    /// The bars after these, as many as now (nil at the end of the piece): what "avanti" goes to.
    public var nextRange: (a: Int, b: Int)? {
        guard let n = piece?.bars.count, range.b < n else { return nil }
        return (range.b + 1, min(n, range.b + 1 + range.b - range.a))
    }

    /// The bars before these, as many as now (nil at the start).
    public var previousRange: (a: Int, b: Int)? {
        guard range.a > 1 else { return nil }
        return (max(1, range.a - 1 - (range.b - range.a)), range.a - 1)
    }

    public func setHands(_ h: Hands) {
        if mode == .listen { stopListen() }
        hands = h
        defaults.set(h.rawValue, forKey: "pt:hands")
        rebuild()
    }

    private func rebuild() {
        guard let piece else { return }
        finished = false
        evs = piece.events.filter { $0.b >= range.a && $0.b <= range.b && hands.rawValue.contains($0.h.rawValue) }
        steps = Array(Set(evs.map(\.s))).sorted()
        stepIdx = 0
        got.removeAll()
        let start = steps.first ?? bar(range.a).start
        glide = (start, start, 0)
        round = Round()
        timedStep = -1
        stepShownAt = CACurrentMediaTime()
    }

    public func bar(_ num: Int) -> Piece.Bar { piece!.bars[max(0, min(piece!.bars.count - 1, num - 1))] }

    public func barAt(_ t: Double) -> Piece.Bar {
        let bars = piece!.bars
        var i = 0
        while i + 1 < bars.count, bars[i + 1].start <= t + Self.eps { i += 1 }
        return bars[i]
    }

    public var stepNotes: [Piece.Event] {
        guard steps.indices.contains(stepIdx) else { return [] }
        let t = steps[stepIdx]
        return evs.filter { abs($0.s - t) < Self.eps }
    }

    /// The moment the status line and the hand cards describe.
    public var currentTime: Double { mode == .listen ? listenStep : (steps.indices.contains(stepIdx) ? steps[stepIdx] : 0) }

    private var spq: Double { 60 / Double(bpm) }

    /// Where the falling notes are (quarter notes) at `now` (CACurrentMediaTime): the audio clock while listening,
    /// otherwise a 0.3 s ease-in-out glide to the current step.
    public func phase(at now: Double) -> Double {
        if mode == .listen { return (sound.now - t0) / spq }
        let target = steps.indices.contains(stepIdx) ? steps[stepIdx] : glide.to
        if target != glide.to { return target }
        let k = min(1, max(0, (now - glide.t) / 0.3))
        let e = k < 0.5 ? 4 * k * k * k : 1 - pow(-2 * k + 2, 3) / 2
        return glide.from + (glide.to - glide.from) * e
    }

    private func moveTo(_ i: Int) {
        let now = CACurrentMediaTime()
        let cur = phase(at: now)
        stepIdx = i
        glide = (cur, steps.indices.contains(i) ? steps[i] : cur, now)
        stepShownAt = now
        if i == 0 { round = Round(); timedStep = -1 }
    }

    // MARK: input

    public func noteOn(_ m: Int, vel: Double = 0.8) {
        onPlay()
        if let v = live[m] { sound.stop(v) }
        live[m] = sound.note(m, at: sound.now, vel: vel)
        sustained.remove(m)
        held.insert(m)
        if finished && mode == .practice {
            // The choice is made on the keyboard, never by itself: a key below middle C = redo these
            // bars, middle C and up = the next ones (nothing at the end of the piece). The tail of the last chord (a
            // note landing just after the end) does not count. Pitch wheel up/down does the same through go.
            guard CACurrentMediaTime() - finishedAt > Self.finishGrace else { return }
            if m < 60 { redo(); show("↺ Da capo") } else if nextRange != nil { nextLesson(); show(rangeName) }
            return
        }
        guard mode == .practice, !steps.isEmpty else { return }
        let need = stepNotes.map(\.n)
        if need.contains(m) {
            got.insert(m)
            // a chord counts only when all its notes are down at the same time (released ones are dropped in noteOff)
            if need.allSatisfy({ got.contains($0) && held.contains($0) }) {
                if timedStep != stepIdx {
                    round.stepTimes.append((stepBar, CACurrentMediaTime() - stepShownAt))
                    timedStep = stepIdx
                }
                let at = stepIdx
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
                    guard let self, self.stepIdx == at, !self.finished else { return }
                    self.go(1)
                }
            }
        } else {
            wrong[m] = CACurrentMediaTime()
            wrongHeld.insert(m)
            round.bars[stepBar, default: BarStat()].wrong += 1
        }
    }

    public func noteOff(_ m: Int) {
        held.remove(m)
        wrongHeld.remove(m)
        let s = stepNotes
        if mode == .practice, !finished, got.contains(m), s.count > 1, s.contains(where: { !got.contains($0.n) }) {
            got.remove(m)
            round.bars[stepBar, default: BarStat()].chordBreaks += 1
            show("Tienile giù insieme")                       // let go before the chord was complete
        }
        if pedal { sustained.insert(m); return }
        if let v = live.removeValue(forKey: m) { sound.stop(v) }
    }

    public func setPedal(_ down: Bool) {
        pedal = down
        guard !down else { return }
        for m in sustained where !held.contains(m) { if let v = live.removeValue(forKey: m) { sound.stop(v) } }
        sustained.removeAll()
    }

    /// Notes of this step not pressed yet, once at least one is ("manca: …").
    public var missing: [Piece.Event] {
        guard !got.isEmpty else { return [] }
        return stepNotes.filter { !got.contains($0.n) }
    }

    /// One MIDI message from the keyboard.
    public func midi(_ st: UInt8, _ d1: UInt8, _ d2: UInt8) {
        let cmd = st & 0xf0, ch = Int(st & 0x0f)
        if cmd == 0x90, d2 > 0, padInput(ch, Int(d1)) { return }   // a pad (or teaching the pads)
        if ch == 9 { return }                                       // other drum-channel traffic (pad releases)
        switch cmd {
        case 0xe0: pitchWheel(Int(d1) | Int(d2) << 7)
        case 0x90 where d2 > 0: noteOn(Int(d1), vel: 0.35 + Double(d2) / 190)
        case 0x80, 0x90: noteOff(Int(d1))
        case 0xb0 where d1 == 64: setPedal(d2 >= 64)
        default: break
        }
    }

    // MARK: steps

    public func go(_ d: Int) {
        if mode == .free { guard piece != nil else { return }; mode = .practice }
        if mode == .listen { stopListen() }
        guard !steps.isEmpty else { return }
        if finished { if d < 0 { redo() } else if nextLessonName != nil { nextLesson() }; return }
        let nxt = stepIdx + d
        if nxt >= steps.count && !loop { finish(); return }
        if nxt >= steps.count { endRound(); drillStep() }
        got.removeAll()
        wrongHeld.removeAll()
        moveTo((nxt + steps.count) % steps.count)
    }

    private func finish() {
        endRound()
        finished = true
        finishedAt = CACurrentMediaTime()
        got.removeAll()
        wrongHeld.removeAll()
    }

    /// Bar of the current step.
    private var stepBar: Int { stepNotes.first?.b ?? range.a }

    /// Saves the round (if something was played) and keeps it for the summary.
    private func endRound() {
        guard !round.stepTimes.isEmpty, mode == .practice else { return }
        round.countHesitations()
        for b in Set(evs.map(\.b)) { round.bars[b, default: BarStat()].rounds += 1 }
        stats.record(piece: pieceName, round: round)
        lastRound = round
        round = Round()
    }

    /// Loop wrap: count clean rounds while drilling; 3 in a row = done.
    private func drillStep() {
        guard drilling, let r = lastRound else { show("🔁 Da capo"); return }
        if r.clean {
            drillClean += 1
            if drillClean >= 3 {
                drilling = false
                drillDone = true
                loop = false
                finish()
                lastRound = r
                return
            }
            show("Giro pulito \(drillClean) di 3")
        } else {
            drillClean = 0
            show("Ancora: \(r.total.score) da sistemare")
        }
    }

    /// The bars to drill: the worst one plus weak neighbours, at most 3 in a row.
    public static func drillRange(_ bars: [Int: BarStat]) -> (a: Int, b: Int)? {
        let weak = bars.filter { $0.value.score > 0 }
        guard let worst = weak.max(by: { ($0.value.score, -$0.key) < ($1.value.score, -$1.key) })?.key else { return nil }
        var a = worst, b = worst
        while b - a < 2 {
            let left = weak[a - 1]?.score ?? 0, right = weak[b + 1]?.score ?? 0
            if left == 0 && right == 0 { break }
            if right >= left { b += 1 } else { a -= 1 }
        }
        return (a, b)
    }

    /// "Esercita i punti deboli": loop on the weakest bars (of `bars`, default the last round) until 3 clean rounds.
    public func practiceWeak(_ bars: [Int: BarStat]? = nil) {
        guard let r = Self.drillRange(bars ?? lastRound?.bars ?? [:]) else { show("Nessun punto debole"); return }
        selectRange(r.a, r.b, tip: AttributedString("Punti deboli: battute \(r.a)–\(r.b). Si ripete da sola finché fai 3 giri puliti di fila."))
        loop = true
        drilling = true
        drillClean = 0
        show("🎯 Battute \(r.a)–\(r.b)")
    }

    /// "Battute 9–12" after Lezione finita (nil = end of the piece).
    public var nextLessonName: String? { nextRange.map { "Battute \($0.a)–\($0.b)" } }

    public func redo() {
        if mode == .free { mode = .practice }
        finished = false
        drillDone = false
        got.removeAll()
        wrongHeld.removeAll()
        moveTo(0)
    }

    public func nextLesson() {
        if mode == .free { mode = .practice }
        finished = false
        if let r = nextRange { selectRange(r.a, r.b) } else { redo() }
    }

    public func hearStep() {
        let t = sound.now + 0.02
        for e in stepNotes { sound.note(e.n, at: t, dur: min(1.6, e.d * spq)) }
    }

    /// Jump to the step at or after `t` (quarter notes); outside the bars practised = as many bars from there.
    public func jump(to t: Double) {
        guard piece != nil else { return }
        if mode == .listen { stopListen() }
        let b = barAt(t).num
        if b < range.a || b > range.b {
            selectRange(b, b + range.b - range.a)
        }
        finished = false
        got.removeAll()
        wrongHeld.removeAll()
        moveTo(max(0, steps.firstIndex { $0 >= t - Self.eps } ?? steps.count - 1))
        show("Battuta " + barAt(currentTime).label)
    }

    // MARK: listen

    /// Suona libero: the lesson stays where it was (also "Lezione finita"), `endFree` goes back to it.
    public func startFree() {
        if mode == .listen { stopListen() }
        got.removeAll()
        wrongHeld.removeAll()
        mode = .free
    }

    public func endFree() {
        guard mode == .free, piece != nil else { return }
        mode = .practice
        show(rangeName)
    }

    public func startListen() {
        guard sound.ready, piece != nil else { return }
        if mode == .free { mode = .practice }
        finished = false
        sound.stopAll()
        let A = bar(range.a), B = bar(range.b)
        from = A.start
        to = B.start + B.len
        let beat = 4 / Double(A.beatType), pre = Double(A.beats) * beat
        let at = sound.now + 0.2
        t0 = at + pre * spq - from * spq
        for i in 0..<A.beats { sound.click(at: at + Double(i) * beat * spq, accent: i == 0) }
        for e in evs {
            let len = e.staccato ? e.d * spq * 0.45 : e.d * spq * 0.97
            sound.note(e.n, at: t0 + e.s * spq, dur: len, vel: e.h == .left ? 0.62 : 0.78)
        }
        mode = .listen
        listenStep = from
        listenTimer?.invalidate()
        listenTimer = Timer.scheduledTimer(withTimeInterval: 1 / 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.listenTick() }
        }
    }

    public func stopListen() {
        listenTimer?.invalidate()
        listenTimer = nil
        sound.stopAll()
        mode = .practice
        got.removeAll()
        moveTo(0)
    }

    private func listenTick() {
        let ph = (sound.now - t0) / spq
        listenPhase = ph
        if ph > to + 0.5 { if loop { startListen() } else { stopListen() }; return }
        let cur = max(from, steps.last { $0 <= ph + Self.eps } ?? from)
        if cur != listenStep { listenStep = cur }
    }

    // MARK: V49 pads + pitch wheel

    public func startLearningPads() {
        learning = 0
        padMessage = "premi il pad 1 (in basso a sinistra)"
    }

    private func padInput(_ ch: Int, _ note: Int) -> Bool {
        let k = "\(ch):\(note)"
        if learning >= 0 {
            if padMap.prefix(learning).contains(k) { return true }
            padMap[learning] = k
            learning += 1
            if learning >= 8 {
                learning = -1
                defaults.set(padMap, forKey: "pt:pads")
                padMessage = "fatto, pad salvati."
            } else {
                padMessage = "ora premi il pad \(learning + 1) (\(Self.padActions[learning].1))"
            }
            return true
        }
        guard let i = padMap.firstIndex(of: k) else { return false }
        padHit = i
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in if self?.padHit == i { self?.padHit = -1 } }
        padAction(Self.padActions[i].0)
        return true
    }

    public func padAction(_ a: String) {
        guard piece != nil else { return }
        switch a {
        case "restart":
            if mode == .listen { stopListen() }
            redo()
            show("↺ Da capo: " + rangeName.lowercased())
        case "bar":
            if mode == .listen { stopListen() }
            finished = false
            let B = barAt(currentTime)
            got.removeAll()
            wrongHeld.removeAll()
            moveTo(max(0, steps.firstIndex { $0 >= B.start - Self.eps } ?? 0))
            show("↺ Battuta \(B.label) da capo")
        case "hear": hearStep()
        case "listen":
            if mode == .listen { stopListen(); show("■ Fermo") } else { startListen(); show("▶ Ascolta") }
        case "prevLes":
            if let r = previousRange { selectRange(r.a, r.b) }
            show(rangeName)
        case "nextLes":
            if let r = nextRange { selectRange(r.a, r.b) }
            show(rangeName)
        case "hands":
            setHands([.both: .right, .right: .left, .left: .both][hands]!)
            show([Hands.right: "Solo destra", .left: "Solo sinistra", .both: "Due mani"][hands]!)
        case "loop":
            loop.toggle()
            show(loop ? "Ripeti: sì" : "Ripeti: no")
        default: break
        }
    }

    /// A push past ~40% = one step; it must come back near the centre before the next one.
    private func pitchWheel(_ v: Int) {
        let d = v - 8192
        if wheelArmed && abs(d) > 3300 {
            wheelArmed = false
            go(d > 0 ? 1 : -1)
            show(d > 0 ? "Avanti →" : "← Indietro")
        } else if abs(d) < 1200 {
            wheelArmed = true
        }
    }

    public func show(_ text: String) {
        toastCount += 1
        toast = (text, toastCount)
        let id = toastCount
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.3) { [weak self] in if self?.toast?.id == id { self?.toast = nil } }
    }
}
