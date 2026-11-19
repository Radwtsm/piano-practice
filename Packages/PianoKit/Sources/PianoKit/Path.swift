import Foundation

/// Il percorso (the path): tappe (stages)
/// by skill, each with its quiz levels and its own sight-reading melodies, passed by what you know, not by minutes.
/// The user's pieces are optional: the "brano" (piece) part of the session.
public struct Tappa: Identifiable, Equatable {
    public let number: Int
    public let title: String
    /// What you learn, one line.
    public let learn: String
    public let levels: [NoteQuiz.Level]
    public let sight: SightSpec
    public var id: Int { number }

    /// Melodies to read and the share of notes right at the first try, to pass the tappa.
    public static let melodiesToPass = 8, sightToPass = 0.8
}

public enum PathPlan {
    public static let tappe: [Tappa] = [
        Tappa(number: 1, title: "Tastiera e dita",
              learn: "Trovare ogni tasto, contare le dita 1–5, la mano destra nella posizione di Do (Do–Sol).",
              levels: [.keyboard],
              sight: SightSpec(positions: [(60, .right, 0)], halves: false)),
        Tappa(number: 2, title: "Leggere in chiave di violino",
              learn: "Le note di riferimento e la chiave di violino; destra in posizione di Do e di Sol, minime e semiminime.",
              levels: [.landmarks, .treble],
              sight: SightSpec(positions: [(60, .right, 0), (67, .right, 0)], halves: true)),
        Tappa(number: 3, title: "Leggere in chiave di basso",
              learn: "La chiave di basso e la mano sinistra in posizione di Do (mignolo sul Do).",
              levels: [.bass],
              sight: SightSpec(positions: [(55, .left, 0)], halves: true)),
        Tappa(number: 4, title: "Accordi",
              learn: "Accordi maggiori e minori: riconoscerli scritti e sentirli; melodie per tutte e due le mani.",
              levels: [.chords],
              sight: SightSpec(positions: [(60, .right, 0), (67, .right, 0), (55, .left, 0)], halves: true)),
        Tappa(number: 5, title: "♯, ♭ e tonalità",
              learn: "L'armatura: Sol maggiore (Fa♯) e Fa maggiore (Si♭), fino a 2 ♯ e 2 ♭.",
              levels: [.all],
              sight: SightSpec(positions: [(67, .right, 1), (65, .right, -1)], halves: true)),
    ]
}

/// Where you are on the path and what today's session holds.
@MainActor
public struct PathProgress {
    public let quiz: NoteQuiz

    public init(quiz: NoteQuiz) { self.quiz = quiz }

    public func passed(_ t: Tappa) -> Bool {
        t.levels.allSatisfy { quiz.mastery(of: $0) >= NoteQuiz.pass } && sightPassed(t)
    }

    public func sightPassed(_ t: Tappa) -> Bool {
        let s = quiz.store.sight(tappa: t.number)
        return s.melodies >= Tappa.melodiesToPass && s.accuracy >= Tappa.sightToPass
    }

    /// The first tappa not passed (all passed = the last, to keep practising).
    public var current: Tappa { PathPlan.tappe.first { !passed($0) } ?? PathPlan.tappe.last! }

    public func isAhead(_ t: Tappa) -> Bool { t.number > current.number }

    // MARK: Sessione di oggi (~15 min: half general skills, half a piece)

    public enum Step: String, CaseIterable, Identifiable {
        case review, quiz, sight, piece
        public var id: String { rawValue }
    }

    /// Answers / melodies that complete a step.
    public static let reviewAnswers = 10, quizAnswers = 15, sightMelodies = 3

    public func title(_ s: Step) -> String {
        switch s {
        case .review: return "Ripasso"
        case .quiz: return "Quiz"
        case .sight: return "Prima vista"
        case .piece: return "Brano"
        }
    }

    public func detail(_ s: Step) -> String {
        switch s {
        case .review:
            let due = NoteQuiz.Level.allCases.filter { $0.number < quiz.frontier.number }.reduce(0) { $0 + quiz.dueCount($1) }
            return due == 0 ? "Niente da ripassare oggi" : "\(due) note tornano oggi"
        case .quiz: return (current.levels.first { quiz.mastery(of: $0) < NoteQuiz.pass } ?? current.levels[0]).title
        case .sight: return "Melodie nuove da leggere"
        case .piece: return "Una lezione lenta e pulita"
        }
    }

    // progress of today's steps, kept per day on this device
    private static func key(_ s: Step, _ date: Date) -> String { "pt:session:\(StatsStore.dayKey(date)):\(s.rawValue)" }

    public func count(_ s: Step, date: Date = Date()) -> Int { UserDefaults.standard.integer(forKey: Self.key(s, date)) }

    public func add(_ s: Step, _ n: Int = 1, date: Date = Date()) {
        UserDefaults.standard.set(count(s, date: date) + n, forKey: Self.key(s, date))
    }

    public func target(_ s: Step) -> Int {
        switch s {
        case .review: return Self.reviewAnswers
        case .quiz: return Self.quizAnswers
        case .sight: return Self.sightMelodies
        case .piece: return 1
        }
    }

    public func isDone(_ s: Step, practisedToday: Bool = false) -> Bool {
        if s == .review, detail(.review).hasPrefix("Niente") { return true }
        if s == .piece, practisedToday { return true }
        return count(s) >= target(s)
    }
}
