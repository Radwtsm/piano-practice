import Foundation

/// Dita (fingers): the five-finger position, fingering suggested where the sheet has none, the
/// hands' starting position for a lesson and the fingers' names. Fingers are 1 (thumb) to 5 (little finger) on both
/// hands; in a position the right thumb is on the lowest of five neighbouring white keys, the left thumb on the highest.
public enum Fingering {
    public static let names = ["pollice", "indice", "medio", "anulare", "mignolo"]

    /// White-key index of a note (C4 = 28; a black key counts as the white key below it).
    static func step(_ m: Int) -> Int { Staff.spell(m, fifths: 0).d }

    static func isWhite(_ m: Int) -> Bool { ![1, 3, 6, 8, 10].contains(((m % 12) + 12) % 12) }

    /// The MIDI note of a white-key index.
    public static func midi(step d: Int) -> Int { (d / 7 + 1) * 12 + [0, 2, 4, 5, 7, 9, 11][d % 7] }

    /// The thumb's white key when `finger` plays `note` in a five-finger position.
    public static func thumb(note: Int, finger: Int, hand: Piece.Hand) -> Int? {
        guard (1...5).contains(finger), isWhite(note) else { return nil }
        return midi(step: hand == .right ? step(note) - (finger - 1) : step(note) + (finger - 1))
    }

    /// The finger that plays `note` with the thumb on `thumb` (nil = outside the position).
    public static func finger(note: Int, thumb: Int, hand: Piece.Hand) -> Int? {
        let f = hand == .right ? step(note) - step(thumb) + 1 : step(thumb) - step(note) + 1
        return (1...5).contains(f) ? f : nil
    }

    /// The five white keys of the position with the thumb on `thumb`, from the thumb to the little finger.
    public static func position(thumb: Int, hand: Piece.Hand) -> [Int] {
        (0..<5).map { midi(step: hand == .right ? step(thumb) + $0 : step(thumb) - $0) }
    }

    /// The first written finger of a text like "3" or "35" (a change of finger on the same note).
    public static func first(_ f: String) -> Int? { f.first.flatMap { Int(String($0)) }.flatMap { (1...5).contains($0) ? $0 : nil } }

    /// Fingering for a hand whose sheet has none at all (MIDI files, pieces without fingers): five fingers on five
    /// neighbouring white keys, the hand moving only when a note falls outside, to where the coming notes fit best.
    /// A chord wider than the hand gets thumb and little finger on its ends. Hands with any written finger are left
    /// alone (never mix the sheet's fingering with guesses).
    public static func suggest(_ events: inout [Piece.Event]) {
        for h in [Piece.Hand.right, .left] {
            let idx = events.indices.filter { events[$0].h == h }
            guard !idx.isEmpty, idx.allSatisfy({ events[$0].f.isEmpty }) else { continue }
            // onsets of this hand, in order, each with its notes
            var groups: [[Int]] = []
            for i in idx {
                if let last = groups.last?.last, abs(events[last].s - events[i].s) < 1e-6 { groups[groups.count - 1].append(i) }
                else { groups.append([i]) }
            }
            var low: Int?                                          // lowest white index of the position
            for (g, group) in groups.enumerated() {
                let steps = group.map { step(events[$0].n) }
                let lo = steps.min()!, hi = steps.max()!
                if hi - lo > 4 {                                   // wider than the hand: ends + inside
                    for i in group {
                        let st = step(events[i].n)
                        let f = st == lo ? 1 : st == hi ? 5 : min(4, max(2, 1 + (st - lo) * 4 / (hi - lo)))
                        events[i].f = String(h == .right ? f : 6 - f)
                        events[i].suggested = true
                    }
                    low = nil
                    continue
                }
                if low == nil || lo < low! || hi > low! + 4 {
                    // the widest run of coming onsets that fits in five white keys, starting here
                    var a = lo, b = hi
                    for next in groups[(g + 1)...] {
                        let s2 = next.map { step(events[$0].n) }
                        let na = min(a, s2.min()!), nb = max(b, s2.max()!)
                        if nb - na > 4 { break }
                        (a, b) = (na, nb)
                    }
                    low = a
                }
                for i in group {
                    let f = step(events[i].n) - low! + 1             // 1 = lowest key of the position
                    events[i].f = String(h == .right ? f : 6 - f)
                    events[i].suggested = true
                }
            }
        }
    }

    /// "Destra: pollice sul Do · Sinistra: pollice sul Sol": where the hands start, from the first fingered note of
    /// each hand in `events` (a lesson's notes); nil when there is no finger to go by.
    public static func start(_ events: [Piece.Event], fifths: Int = 0) -> String? {
        var parts: [String] = []
        for (h, word) in [(Piece.Hand.right, "Destra"), (.left, "Sinistra")] {
            guard let e = events.first(where: { $0.h == h && first($0.f) != nil }), let f = first(e.f) else { continue }
            if let t = thumb(note: e.n, finger: f, hand: h) {
                parts.append("\(word): pollice sul \(Staff.name(t, fifths: 0))")
            } else {
                parts.append("\(word): \(names[f - 1]) sul \(Staff.name(e.n, fifths: fifths))")
            }
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

extension Piece {
    /// The piece with fingering suggested for any hand the sheet left without (`Fingering.suggest`).
    public func withSuggestedFingers() -> Piece {
        var p = self
        Fingering.suggest(&p.events)
        return p
    }
}
