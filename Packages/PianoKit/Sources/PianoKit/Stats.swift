import Foundation

/// What went wrong in one bar (wrong keys, hesitations, chords not held together).
public struct BarStat: Codable, Equatable {
    public var wrong = 0
    /// Steps that took much longer than usual to find (see `Round.hesitations`).
    public var hesitations = 0
    /// Chords whose notes were let go before all of them were down.
    public var chordBreaks = 0
    /// Rounds in which this bar was played (the denominator for the history).
    public var rounds = 0

    public init() {}
    public var score: Int { wrong + hesitations + chordBreaks }

    mutating func add(_ o: BarStat) {
        wrong += o.wrong
        hesitations += o.hesitations
        chordBreaks += o.chordBreaks
        rounds += o.rounds
    }
}

/// One pass through the lesson in practice mode, from the first step to the end.
public struct Round: Equatable {
    public var bars: [Int: BarStat] = [:]
    /// Seconds from a step being shown to its keys being down, per bar.
    var stepTimes: [(bar: Int, seconds: Double)] = []

    public init() {}

    public static func == (a: Round, b: Round) -> Bool { a.bars == b.bars }

    /// A step counts as a hesitation when it took more than 2.5× the round's median and at least 2 s.
    mutating func countHesitations() {
        let sorted = stepTimes.map(\.seconds).sorted()
        guard !sorted.isEmpty else { return }
        let limit = max(2, sorted[sorted.count / 2] * 2.5)
        for t in stepTimes where t.seconds > limit { bars[t.bar, default: BarStat()].hesitations += 1 }
    }

    public var total: BarStat { bars.values.reduce(into: BarStat()) { $0.add($1) } }
    public var clean: Bool { total.score == 0 }

    /// The worst bars first (only bars with something wrong), at most `n`.
    public func weakest(_ n: Int = 3) -> [Int] {
        bars.filter { $0.value.score > 0 }.sorted { ($0.value.score, -$0.key) > ($1.value.score, -$1.key) }.prefix(n).map(\.key)
    }
}

/// History per piece and day (`yyyy-MM-dd` → bar → totals), saved as JSON next to the app's data. This device writes
/// its own rounds (`data`); the other devices' come from the sync server (`PianoSync`) and every read adds them up.
public final class StatsStore {
    public typealias Day = [Int: BarStat]
    private(set) var data: [String: [String: Day]] = [:]
    private var others: [[String: [String: Day]]] = []
    private let url: URL

    public init(url: URL? = nil) {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Piano", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.url = url ?? dir.appendingPathComponent("stats.json")
        if let d = try? Data(contentsOf: self.url), let decoded = try? JSONDecoder().decode([String: [String: Day]].self, from: d) {
            data = decoded
        }
        let o = self.url.deletingPathExtension().appendingPathExtension("others.json")
        others = (try? Data(contentsOf: o)).flatMap { try? JSONDecoder().decode([[String: [String: Day]]].self, from: $0) } ?? []
    }

    /// The other devices' rounds from the server (kept on disk for offline).
    func setOthers(_ list: [[String: [String: Day]]]) {
        others = list
        let o = url.deletingPathExtension().appendingPathExtension("others.json")
        if let d = try? JSONEncoder().encode(list) { try? d.write(to: o, options: .atomic) }
    }

    static func dayKey(_ date: Date) -> String {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }

    public func record(piece: String, round: Round, date: Date = Date()) {
        let k = Self.dayKey(date)
        var day = data[piece]?[k] ?? [:]
        for (b, s) in round.bars { day[b, default: BarStat()].add(s) }
        data[piece, default: [:]][k] = day
        if let d = try? JSONEncoder().encode(data) { try? d.write(to: url, options: .atomic) }
    }

    /// A round of any piece was played that day (on any device): the session's "Brano" step is done.
    public func practised(on date: Date = Date()) -> Bool {
        let k = Self.dayKey(date)
        return ([data] + others).contains { $0.values.contains { $0[k] != nil } }
    }

    /// Days with data for this piece, newest first.
    public func history(piece: String) -> [(day: String, bars: Day)] {
        var days = data[piece] ?? [:]
        for o in others {
            for (k, bars) in o[piece] ?? [:] {
                for (b, st) in bars { days[k, default: [:]][b, default: BarStat()].add(st) }
            }
        }
        return days.sorted { $0.key > $1.key }.map { ($0.key, $0.value) }
    }

    /// Bars summed over the last `days` days with data.
    public func recent(piece: String, days: Int = 7) -> Day {
        history(piece: piece).prefix(days).reduce(into: Day()) { acc, d in
            for (b, s) in d.bars { acc[b, default: BarStat()].add(s) }
        }
    }
}
