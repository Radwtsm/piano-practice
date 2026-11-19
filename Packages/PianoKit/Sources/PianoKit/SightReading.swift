import Foundation
import Observation
import QuartzCore

/// Prima vista (sight reading):
/// short melodies the app writes itself, never seen before and easy for the tappa — the most effective sight-reading
/// practice is a lot of new, easy music (docs/DESIGN.md: Mishra 2014). Four bars of 4/4 in one five-finger
/// position, mostly steps, starting and ending on the key's note.
public struct Melody: Equatable {
    public var notes: [Int]
    /// 1 = quarter, 2 = half (beats).
    public var beats: [Int]
    public var clef: Staff.Clef
    public var fifths: Int

    public var hand: Piece.Hand { clef == .treble ? .right : .left }
}

/// What a tappa's melodies use: where the hand is, the key, the note values.
public struct SightSpec: Equatable {
    /// (thumb, hand, key signature) of each allowed position; one is picked per melody.
    public var positions: [(thumb: Int, hand: Piece.Hand, fifths: Int)]
    public var halves: Bool

    public init(positions: [(thumb: Int, hand: Piece.Hand, fifths: Int)], halves: Bool) {
        self.positions = positions
        self.halves = halves
    }

    public static func == (a: SightSpec, b: SightSpec) -> Bool {
        a.halves == b.halves && a.positions.map(\.thumb) == b.positions.map(\.thumb) && a.positions.map(\.fifths) == b.positions.map(\.fifths)
    }

    /// A new melody (`random` in 0..<1, injectable for tests).
    public func melody(_ random: () -> Double) -> Melody {
        let p = positions[Int(random() * Double(positions.count)) % positions.count], fifths = p.fifths
        let keys = Fingering.position(thumb: p.thumb, hand: p.hand).sorted().map { m -> Int in
            m + Staff.keyAccidental(letter: Staff.spell(m, fifths: 0).letter, fifths: fifths)
        }
        // the key's note: the position's lowest note for Do/Sol/Fa positions (they start on the tonic)
        let home = 0
        var beats: [Int] = []
        for _ in 0..<4 {                                                   // 4 bars of 4 beats
            var left = 4
            while left > 0 {
                let b = halves && left >= 2 && random() < 0.3 ? 2 : 1
                beats.append(b)
                left -= b
            }
        }
        if halves, beats.count >= 2, beats[beats.count - 1] == 1, beats[beats.count - 2] == 1 {
            beats.removeLast(2)
            beats.append(2)                                                // end on a long note
        }
        var i = home, notes: [Int] = []
        for k in beats.indices {
            if k == beats.count - 1 { i = home } else if k > 0 {
                let r = random()
                let step = r < 0.5 ? 1 : r < 0.8 ? 2 : r < 0.9 ? 0 : 3
                let up = random() < 0.5
                var n = i + (up ? step : -step)
                if n < 0 || n > 4 { n = i + (up ? -step : step) }
                i = min(4, max(0, n))
            }
            notes.append(keys[i])
        }
        return Melody(notes: notes, beats: beats, clef: p.hand == .right ? .treble : .bass, fifths: fifths)
    }
}

/// One melody being read: name each note in order (buttons) or play it on the V49; a wrong answer is marked and you
/// try again. The result goes to the tappa's sight-reading score (`QuizStore.recordSight`).
@MainActor @Observable
public final class SightSession {
    public private(set) var melody: Melody
    public private(set) var index = 0
    /// Notes found at the first try / after a mistake (index → true = first try).
    public private(set) var firstTry: [Int: Bool] = [:]
    public private(set) var wrongName: String?
    public private(set) var finished = false
    /// Melodies read in this sitting.
    public private(set) var done = 0
    /// The seven names in scale order, spelled as this melody's key writes them (Fa♯ in Sol maggiore).
    public var choices: [String] {
        [0, 2, 4, 5, 7, 9, 11].map { pc in
            let m = 60 + pc
            return Staff.name(m + Staff.keyAccidental(letter: Staff.spell(m, fifths: 0).letter, fifths: melody.fifths), fifths: melody.fifths)
        }
    }
    @ObservationIgnored public let tappa: Int
    @ObservationIgnored private let spec: SightSpec
    @ObservationIgnored private let store: QuizStore
    @ObservationIgnored private var started = CACurrentMediaTime()
    @ObservationIgnored private var missedThis = false
    @ObservationIgnored private let random: () -> Double

    public init(tappa: Int, spec: SightSpec, store: QuizStore, random: @escaping () -> Double = { Double.random(in: 0..<1) }) {
        self.tappa = tappa
        self.spec = spec
        self.store = store
        self.random = random
        melody = spec.melody(random)
    }

    public var current: Int? { finished ? nil : melody.notes[index] }
    public var answer: String { current.map { Staff.name($0, fifths: melody.fifths) } ?? "" }
    public var rightFirst: Int { firstTry.values.filter { $0 }.count }

    /// A name button. True when it is the note.
    @discardableResult
    public func choose(_ name: String) -> Bool {
        guard !finished else { return false }
        guard name == answer else { missedThis = true; wrongName = name; return false }
        advance()
        return true
    }

    /// A V49 key (any octave counts: reading is the skill here, not the octave).
    @discardableResult
    public func press(_ m: Int) -> Bool {
        guard let c = current else { return false }
        guard (m - c) % 12 == 0 else { missedThis = true; wrongName = Staff.name(m, fifths: melody.fifths); return false }
        advance()
        return true
    }

    private func advance() {
        firstTry[index] = !missedThis
        missedThis = false
        wrongName = nil
        if index + 1 < melody.notes.count { index += 1; return }
        finished = true
        done += 1
        store.recordSight(tappa: tappa, right: rightFirst, wrong: melody.notes.count - rightFirst,
                          seconds: CACurrentMediaTime() - started)
    }

    public func next() {
        melody = spec.melody(random)
        index = 0
        firstTry = [:]
        wrongName = nil
        finished = false
        missedThis = false
        started = CACurrentMediaTime()
    }
}
