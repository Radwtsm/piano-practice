/// Names what a hand plays, in Italian, for a beginner (port of the earlier implementation): one note → its name; two → the
/// interval; three or more → the chord (root + kind) and, when the lowest note is not the root, its inversion.
public enum Chords {
    public static let names = ["Do", "Do#", "Re", "Re#", "Mi", "Fa", "Fa#", "Sol", "Sol#", "La", "La#", "Si"]

    private static let kinds: [([Int], String)] = [
        ([0, 4, 7], "maggiore"), ([0, 3, 7], "minore"), ([0, 3, 6], "diminuito"), ([0, 4, 8], "aumentato"),
        ([0, 2, 7], "sus2"), ([0, 5, 7], "sus4"),
        ([0, 4, 7, 10], "settima"), ([0, 4, 7, 11], "maggiore settima"), ([0, 3, 7, 10], "minore settima"),
        ([0, 3, 6, 10], "semidiminuito"), ([0, 3, 6, 9], "diminuito settima"), ([0, 4, 7, 9], "sesta"),
        ([0, 3, 7, 9], "minore sesta"),
        ([0, 4, 10], "settima (senza quinta)"), ([0, 4, 11], "maggiore settima (senza quinta)"),
        ([0, 3, 10], "minore settima (senza quinta)"),
    ]
    private static let intervals = ["unisono", "seconda minore", "seconda maggiore", "terza minore", "terza maggiore",
                                    "quarta", "tritono", "quinta", "sesta minore", "sesta maggiore", "settima minore",
                                    "settima maggiore"]

    public struct Description: Equatable {
        public let title: String
        public let detail: String
    }

    /// MIDI notes → name + explanation; nil for no notes.
    public static func describe(_ notes: [Int]) -> Description? {
        let ns = Array(Set(notes)).sorted()
        guard let low = ns.first else { return nil }
        if ns.count == 1 { return .init(title: names[low % 12], detail: "nota singola") }
        var pcs: [Int] = []
        for n in ns where !pcs.contains(n % 12) { pcs.append(n % 12) }
        if pcs.count == 1 { return .init(title: names[low % 12], detail: "la stessa nota in due ottave (ottava)") }
        if pcs.count == 2 && ns.count > 2 {
            let lo = low % 12, hi = pcs.first { $0 != lo }!
            return .init(title: "\(names[lo]) + \(names[hi])",
                         detail: intervals[(hi - lo + 12) % 12] + ", con una nota raddoppiata all'ottava")
        }
        if ns.count == 2 {
            let span = ns[1] - ns[0]
            return .init(title: "\(names[ns[0] % 12]) + \(names[ns[1] % 12])",
                         detail: intervals[span % 12] + (span >= 12 ? " (più un'ottava)" : ""))
        }
        let bass = low % 12
        guard let best = findChord(pcs) else {
            if let upper = findChord(pcs.filter { $0 != bass }) {
                return .init(title: "\(names[upper.root]) \(upper.kind) / \(names[bass])",
                             detail: "accordo di \(names[upper.root]) \(upper.kind) con il \(names[bass]) al basso")
            }
            return .init(title: ns.map { names[$0 % 12] }.joined(separator: " + "), detail: "insieme di note")
        }
        guard bass != best.root else {
            return .init(title: "\(names[best.root]) \(best.kind)",
                         detail: "posizione base: in basso c'è la radice \(names[best.root])")
        }
        let iv = (bass - best.root + 12) % 12
        let inversion = iv == 3 || iv == 4 ? "primo rivolto" : iv == 6 || iv == 7 || iv == 8 ? "secondo rivolto" : "terzo rivolto"
        return .init(title: "\(names[best.root]) \(best.kind)",
                     detail: "\(inversion): in basso c'è il \(names[bass]), la radice \(names[best.root]) è più su")
    }

    private static func findChord(_ pcs: [Int]) -> (root: Int, kind: String)? {
        for (ivs, kind) in kinds where ivs.count == pcs.count {
            for root in pcs where pcs.map({ ($0 - root + 12) % 12 }).sorted() == ivs { return (root, kind) }
        }
        return nil
    }
}
