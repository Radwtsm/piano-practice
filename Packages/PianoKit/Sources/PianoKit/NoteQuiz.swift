import Foundation
import Observation
import QuartzCore

/// How a MIDI note is written on a staff : the diatonic step (C4 = 28) and the sign.
public enum Staff {
    public enum Clef: String, Codable { case treble = "G", bass = "F" }

    public struct Spelled: Equatable {
        /// Diatonic index: C4 = 28, D4 = 29 … (7 per octave).
        public let d: Int
        /// C = 0 … B = 6.
        public let letter: Int
        /// −1 flat, 0 natural, +1 sharp.
        public let acc: Int
    }

    static let sharpSpelling = [(0, 0), (0, 1), (1, 0), (1, 1), (2, 0), (3, 0), (3, 1), (4, 0), (4, 1), (5, 0), (5, 1), (6, 0)]
    static let flatSpelling = [(0, 0), (1, -1), (1, 0), (2, -1), (2, 0), (3, 0), (4, -1), (4, 0), (5, -1), (5, 0), (6, -1), (6, 0)]
    static let sharpOrder = [3, 0, 4, 1, 5, 2, 6]          // F C G D A E B
    static let flatOrder = [6, 2, 5, 1, 4, 0, 3]           // B E A D G C F
    /// Staff step of each key-signature sign, treble clef; bass = 14 steps lower.
    public static let sharpPos = [38, 35, 39, 36, 33, 37, 34], flatPos = [34, 37, 33, 36, 32, 35, 31]
    public static let letters = ["Do", "Re", "Mi", "Fa", "Sol", "La", "Si"]

    public static func spell(_ m: Int, fifths: Int) -> Spelled {
        let (letter, acc) = (fifths < 0 ? flatSpelling : sharpSpelling)[((m % 12) + 12) % 12]
        return Spelled(d: (m / 12 - 1) * 7 + letter, letter: letter, acc: acc)
    }

    /// The sign the key signature already gives this letter (so the note needs none in front).
    public static func keyAccidental(letter: Int, fifths: Int) -> Int {
        let n = min(7, abs(fifths))
        if fifths > 0 && sharpOrder.prefix(n).contains(letter) { return 1 }
        if fifths < 0 && flatOrder.prefix(n).contains(letter) { return -1 }
        return 0
    }

    /// The step on the bottom line: E4 (treble) / G2 (bass).
    public static func bottomLine(_ clef: Clef) -> Int { clef == .treble ? 30 : 18 }

    /// The line the clef marks, the place to count from: Sol (G4) for the treble, Fa (F3) for the bass.
    public static func anchor(_ clef: Clef) -> Int { clef == .treble ? 32 : 24 }

    /// The white key of a staff step (d 28 = C4 = 60).
    public static func natural(_ d: Int) -> Int {
        let o = Int((Double(d) / 7).rounded(.down)), l = d - o * 7
        return 12 * (o + 1) + [0, 2, 4, 5, 7, 9, 11][l]
    }

    /// The note's name as the sheet spells it ("Fa#", "Sib"), in Italian.
    public static func name(_ m: Int, fifths: Int) -> String {
        let p = spell(m, fifths: fifths)
        return letters[p.letter] + (p.acc > 0 ? "#" : p.acc < 0 ? "b" : "")
    }
}

/// Quiz delle note (note quiz): a note on the staff (or a lit key, or a chord) → tap its
/// name among buttons (no on-screen keys to press on iOS), or play it on the V49 (Mac/iPad). Notes come from the
/// user's pieces; the missed ones come back more often (Leitner boxes).
@MainActor @Observable
public final class NoteQuiz {
    public enum Level: Int, CaseIterable, Codable, Identifiable {
        case keyboard, landmarks, treble, bass, all, chords
        public var id: Int { rawValue }

        /// The path's order. rawValue stays as saved (UserDefaults, quiz.json keys; 6 was "Che dito?", removed as too easy:
        /// the fingers are taught by the pieces and sight reading); compare levels by `number`.
        public static let allCases: [Level] = [.keyboard, .landmarks, .treble, .bass, .all, .chords]
        /// 1-based place on the path ("Livello 2").
        public var number: Int { Self.allCases.firstIndex(of: self)! + 1 }
        /// The keyboard is the question (no staff): a key lit, its name to choose.
        public var asksOnKeyboard: Bool { self == .keyboard }

        public var title: String {
            switch self {
            case .keyboard: return "Le note sulla tastiera"
            case .landmarks: return "Note di riferimento"
            case .treble: return "Chiave di violino"
            case .bass: return "Chiave di basso"
            case .all: return "Tutte, con ♯ e ♭"
            case .chords: return "Accordi"
            }
        }

        public var tip: String {
            switch self {
            case .keyboard:
                return "Il Do è il tasto bianco subito a sinistra dei 2 tasti neri; il Fa subito a sinistra dei 3. Da lì: Do Re Mi Fa Sol La Si, un tasto bianco alla volta."
            case .landmarks:
                return "Tre note da sapere a colpo d'occhio: il Do centrale (taglio sotto il violino, sopra il basso), il Sol sulla seconda riga del violino (la chiave gira intorno a quella riga) e il Fa sulla quarta riga del basso (tra i due puntini)."
            case .treble:
                return "Tutte le note della chiave di violino (quelle dei tuoi brani escono più spesso). Parti dal riferimento più vicino e conta: riga → spazio → riga, ogni gradino è il tasto bianco dopo."
            case .bass:
                return "Tutte le note della chiave di basso (quelle dei tuoi brani escono più spesso). Riferimenti: Fa sulla quarta riga, Do centrale sopra il pentagramma."
            case .all:
                return "Note con armature fino a 2 ♯ o 2 ♭ (più quelle dei tuoi brani): i ♯ o ♭ all'inizio valgono per tutte quelle note, anche senza segno accanto."
            case .chords:
                return "Un accordo base sono 3 note a salti sul pentagramma (riga-riga-riga o spazio-spazio-spazio): la più bassa gli dà il nome. Maggiore suona allegro (radice + 4 tasti + 3), minore più triste (radice + 3 + 4), contando anche i neri."
            }
        }
    }

    /// One thing to recognise: a note, how it is written (clef + key signature).
    public struct Item: Hashable, Codable {
        public let midi: Int
        public let clef: Staff.Clef
        public let fifths: Int
        /// Accordi: the chord's notes (root position from `midi`) and its name; empty for single notes.
        public var chord: [Int] = []
        public var chordName = ""
        var key: String { chord.isEmpty ? "\(clef.rawValue):\(midi):\(fifths)" : "chord:" + chordName }
    }

    /// wrong(key) = a wrong V49 key; wrongName = a wrong button.
    public enum Feedback: Equatable { case none, right, wrong(Int), wrongName(String) }

    public private(set) var level: Level
    public private(set) var item: Item?
    public private(set) var feedback: Feedback = .none
    /// This session: questions answered right at the first try / with a mistake.
    public private(set) var rightFirst = 0
    public private(set) var missed = 0
    /// Keys to draw (whole octaves, around the level's notes).
    public private(set) var range: ClosedRange<Int> = 60...83
    public private(set) var pool: [Item] = []
    /// Accordi: the pitch classes chosen so far (tap toggles, V49 = what is held).
    public private(set) var chosen = Set<Int>()
    /// The name buttons: every note name of the level in scale order (Do first); Accordi: 4 chord names.
    public private(set) var choices: [String] = []

    /// "Allenati sulle più lente" (train the slowest): the quiz asks only these until `endFocus`.
    public private(set) var focus: [Item]?
    /// The one help after a mistake: its words (one line, in place of "riprova"), the keys lit blue on the keyboard, the staff steps drawn blue. Never names the
    /// answer. Tastiera: the black-key group; staff levels: a note one step away.
    public struct Hint: Equatable {
        public let text: String
        public var keys: [Int] = []
        public var staff: [Int] = []
    }
    public private(set) var hint: Hint?

    /// Staff steps drawn blue on the question: where the counting starts — the clef's line (Sol / Fa, always,
    /// the same blue as its key on the keyboard), or after a one-step mistake the step of the name chosen.
    public var staffMarks: [Int] {
        if let g = geometry { return [g.from] }
        guard let it = item, it.chord.isEmpty, level != .keyboard, level != .chords else { return [] }
        return [Staff.anchor(it.clef)]
    }

    /// Geometric feedback, not text: after an answer on a staff level, the way from where you count to the note,
    /// drawn the same on both: steps 1, 2, 3… up the staff (line → space → line) = white keys 1, 2, 3… to the right;
    /// and the finger that plays it in the hand position (treble right hand, bass left hand).
    public struct Geometry: Equatable {
        /// Staff steps: from (the clef's line, or the name chosen by mistake) to the note.
        public let from: Int
        public let to: Int
        /// The white keys of each step, `from` first (the note's own key may be black: `Item.midi`).
        public let keys: [Int]
        public let finger: Int
    }

    /// Shown after a right answer (until the next question) or a one-step mistake (until it is right).
    public var geometry: Geometry? {
        guard let it = item, it.chord.isEmpty, level != .keyboard, level != .chords else { return nil }
        let from: Int
        switch feedback {
        case .right: from = Staff.anchor(it.clef)
        case .wrong, .wrongName: guard let c = hint?.staff.first else { return nil }; from = c
        case .none: return nil
        }
        let to = Staff.spell(it.midi, fifths: it.fifths).d
        let keys = stride(from: from, through: to, by: to >= from ? 1 : -1).map(Staff.natural)
        return Geometry(from: from, to: to, keys: keys, finger: Self.finger(to, clef: it.clef))
    }

    /// The finger in the five-finger position that starts on the nearest Do or Sol at or below the note (thumb there
    /// for the right hand, little finger for the left): Sol on the treble line = 1, La 2, Si 3; Fa on the bass line = 2.
    public static func finger(_ d: Int, clef: Staff.Clef) -> Int {
        let at = (0...3).first { ((d - $0) % 7 + 7) % 7 == 0 || ((d - $0) % 7 + 7) % 7 == 4 } ?? 0
        return clef == .treble ? at + 1 : 5 - at
    }

    /// pitch class → (black keys in its group, place in the group): Do Re Mi = 2-group, Fa Sol La Si = 3-group.
    private static let place: [Int: (group: Int, at: Int)] = [
        0: (2, 0), 2: (2, 1), 4: (2, 2), 1: (2, 0), 3: (2, 1),
        5: (3, 0), 7: (3, 1), 9: (3, 1), 11: (3, 2), 6: (3, 0), 8: (3, 1), 10: (3, 2)]

    /// After a wrong answer: the black-key group (Tastiera) or the one-step staff hint, whichever fits.
    private func explain(_ it: Item, chose m: Int?, name: String?) {
        hint = nil                                                  // a hint is about THIS mistake only
        if level == .keyboard {
            hintGroup(it, chose: m.map { (($0 % 12) + 12) % 12 } ?? name.flatMap { n in (0..<12).first { Staff.name(60 + $0, fifths: it.fifths) == n } })
        } else {
            hintStep(it, chose: name ?? m.map { Staff.name($0, fifths: it.fifths) })
        }
    }

    /// Staff levels: the name chosen is the note one step above or below (a line taken for the next space or the
    /// other way round) → its step drawn blue with the way to the note (`geometry`), and a short "1 passo più su ↑".
    private func hintStep(_ it: Item, chose name: String?) {
        guard it.chord.isEmpty, let name,
              let letter = Staff.letters.indices.filter({ name.hasPrefix(Staff.letters[$0]) })
                .max(by: { Staff.letters[$0].count < Staff.letters[$1].count }) else { return }
        let d = Staff.spell(it.midi, fifths: it.fifths).d
        guard let c = [d - 1, d + 1].first(where: { (($0 % 7) + 7) % 7 == letter }) else { return }
        hint = Hint(text: "Non è \(Staff.letters[letter]): 1 passo \(c < d ? "più su ↑" : "più giù ↓")", staff: [c])
    }

    /// Sets the group hint when `chose` (a pitch class) sits where the asked key would sit in the other group.
    private func hintGroup(_ it: Item, chose pc: Int?) {
        let asked = ((it.midi % 12) + 12) % 12, blacks: Set = [1, 3, 6, 8, 10]
        guard level == .keyboard, let pc, blacks.contains(asked) == blacks.contains(pc),   // white with white, black with black
              let a = Self.place[asked], let b = Self.place[pc], a.group != b.group, a.at == b.at else { return }
        let lit = shown ?? it.midi                          // the octave on screen (the keyboard can show it higher)
        let base = lit - ((lit % 12) + 12) % 12
        hint = Hint(text: a.group == 2 ? "2 neri = Do Re Mi" : "3 neri = Fa Sol La Si",
                    keys: (a.group == 2 ? [1, 3] : [6, 8, 10]).map { base + $0 })
    }

    /// What the focus banner says: the slowest notes or the confusions, or this round's notes to
    /// review (Riepilogo › Allena queste).
    public private(set) var focusConfused = false
    public private(set) var focusLive = false
    @ObservationIgnored public let store: QuizStore
    /// Bumped when the other devices' answers arrive: every count below reads it, so the screen redraws.
    public private(set) var revision = 0
    public func storeChanged() { revision += 1 }
    @ObservationIgnored private var pieces: [Piece] = []
    @ObservationIgnored private var askedAt = 0.0
    /// The key lit/written this time: the item's note, but in the keyboard level a random octave of `range`
    /// (always C4–B4 next to "Do centrale" = the place on the screen gave the name away).
    public private(set) var shown: Int?
    @ObservationIgnored private var recent: [Item] = []
    /// The level's notes that are in the pieces: asked twice as often.
    @ObservationIgnored private var fromPieces = Set<Item>()
    @ObservationIgnored private var wrongThisItem = false
    /// The last answer came from the V49: the next note is picked from the V49 cards, so a note missed on the
    /// keyboard comes back more often too (it used to read only the buttons' cards), Tastiera included.
    @ObservationIgnored private var lastV49 = false

    /// AFK: more than this with no touch or key, or the app left (`appAway`, screen locked), makes the answer a pause: it counts right/wrong, never speed.
    nonisolated public static let pause = 15.0
    @ObservationIgnored private var lastEvent = 0.0
    @ObservationIgnored private var pausedThisItem = false

    /// A touch or key: a gap longer than `pause` since the last one (or the question) = you were away.
    private func event() {
        store.practice(.learn)
        let now = CACurrentMediaTime()
        if now - lastEvent > Self.pause { pausedThisItem = true }
        lastEvent = now
    }

    /// The app went to the background / the screen locked: this question's time no longer measures you.
    public func appAway() { pausedThisItem = true }

    /// Seconds to the answer, nil when it was a pause.
    private var elapsed: Double? { pausedThisItem ? nil : CACurrentMediaTime() - askedAt }

    /// A note missed, or found slowly, in this round. It comes back often until it is right at the first try and in
    /// time twice in a row, then it leaves the list (and counts as improved).
    public struct Live: Identifiable, Equatable {
        public let item: Item
        public var misses = 0
        /// The slow time that put it here (nil = it came for a mistake).
        public var seconds: Double?
        public var streak = 0
        public var id: String { item.key }
        public var name: String { item.chord.isEmpty ? Staff.name(item.midi, fifths: item.fifths) : item.chordName }
    }
    /// This round's notes to review, newest first.
    public private(set) var live: [Live] = []
    /// This round's notes that left `live` (two good answers after a miss / slow one).
    public private(set) var improved: [Item] = []
    /// Questions answered this round (the round = since the level or the training started).
    public private(set) var answered = 0
    /// Needs 2 answers in a row this good to leave `live`; slower than twice the level's "fast" time = slow.
    public static let liveStreak = 2

    private func track(_ it: Item, seconds: Double?, v49: Bool) {
        answered += 1
        let fast = v49 ? QuizStore.fastV49 : QuizStore.fast(level), slow = seconds.map { $0 > 2 * fast } ?? false   // a pause is not slow
        if let i = live.firstIndex(where: { $0.item == it }) {
            if wrongThisItem { live[i].misses += 1; live[i].streak = 0 }
            else if slow { live[i].seconds = seconds; live[i].streak = 0 }
            else if seconds == nil {}                                   // a pause: neither better nor worse
            else {
                live[i].streak += 1
                if live[i].streak >= Self.liveStreak { live.remove(at: i); if !improved.contains(it) { improved.append(it) } }
            }
        } else if wrongThisItem || slow {
            live.insert(Live(item: it, misses: wrongThisItem ? 1 : 0, seconds: wrongThisItem ? nil : seconds), at: 0)
        }
    }

    // MARK: staff stages (lines first, then spaces: easier to memorise)

    /// Steps from the middle of the staff outwards: the middle line with its neighbour lines, then the outer lines, the middle spaces, the outer
    /// spaces, then the whole level (ledger lines, the pieces' sharps/flats). Each step adds its notes to the ones
    /// before once those are known; forgetting one brings the quiz back to that step. Same cards, same "Sai".
    static let staffGroups: [Staff.Clef: [(title: String, midi: [Int])]] = [
        .treble: [("Righe in mezzo", [67, 71, 74]), ("Tutte le righe", [64, 77]),
                  ("Spazi in mezzo", [69, 72]), ("Tutti gli spazi", [65, 76])],
        .bass: [("Righe in mezzo", [47, 50, 53]), ("Tutte le righe", [43, 57]),
                ("Spazi in mezzo", [48, 52]), ("Tutti gli spazi", [45, 55])],
    ]

    /// The stage being learned on a staff level: its notes in words and how many are ready (3 right in a row).
    public struct Stage: Equatable {
        public let index: Int
        public let title: String
        public let notes: String
        public let known: Int
        public let total: Int
    }

    public var stage: Stage? {
        _ = revision
        return stageItems().map { st in
            let g = Self.staffGroups[st.clef]![st.index]
            let mine = st.items.filter { g.midi.contains($0.midi) }
            let names = g.midi.map { Staff.name($0, fifths: 0) }.joined(separator: " ")
            return Stage(index: st.index, title: g.title, notes: names,
                         known: Set(mine.filter { store.isSteady(level, $0) }.map(\.midi)).count, total: Set(mine.map(\.midi)).count)
        }
    }

    /// The notes asked now on a staff level (the groups up to the first one not known yet); nil = the whole pool.
    private func stageItems() -> (index: Int, clef: Staff.Clef, items: [Item])? {
        guard level == .treble || level == .bass else { return nil }
        let clef: Staff.Clef = level == .treble ? .treble : .bass
        var asked: [Item] = []
        for (i, g) in Self.staffGroups[clef]!.enumerated() {
            let group = pool.filter { $0.clef == clef && $0.chord.isEmpty && g.midi.contains($0.midi) }
            asked += group
            // 3 right at the first try in a row (either card) moves on; only a mistake moves back, a slow answer doesn't
            if group.count >= 2 && !group.allSatisfy({ store.isSteady(level, $0) }) { return (i, clef, asked) }
        }
        return nil
    }
    @ObservationIgnored private var lastStage: Int?

    private func newRound() {
        rightFirst = 0
        missed = 0
        answered = 0
        live = []
        improved = []
    }
    @ObservationIgnored private var generator: () -> Double

    public init(store: QuizStore = QuizStore(), random: @escaping () -> Double = { Double.random(in: 0..<1) }) {
        self.store = store
        generator = random
        level = Level(rawValue: UserDefaults.standard.integer(forKey: "pt:quiz.level")) ?? .keyboard
        guided = UserDefaults.standard.object(forKey: "pt:quiz.guided") as? Bool ?? true
    }

    /// Pieces whose notes the quiz uses (the app's library); none = a beginner's default set.
    public func use(pieces: [Piece]) {
        self.pieces = pieces
        setLevel(guided ? recommended : level)
    }

    // MARK: guide (the app steers you to the right exercises)

    /// A level is passed when you know this share of its notes.
    public static let pass = 0.8
    /// The app picks the level (default); off while you chose one yourself, back with `followGuide`.
    public private(set) var guided: Bool {
        didSet { UserDefaults.standard.set(guided, forKey: "pt:quiz.guided") }
    }
    /// What the guide just did and why ("Livello 1 superato…"), shown for a few questions.
    public private(set) var guideNote: String?
    @ObservationIgnored private var noteLeft = 0
    /// Too many mistakes on the level being learned: one round on the level before it first.
    @ObservationIgnored private var stepBack: Level?
    /// The level was entered already passed (a review), not to learn it.
    @ObservationIgnored private var reviewing = false

    /// The first level not passed yet; every level passed = the last.
    public var frontier: Level { Level.allCases.first { mastery(of: $0) < Self.pass } ?? .chords }

    /// Not reached yet: shown with a lock, still open to try.
    public func isAhead(_ l: Level) -> Bool { l.number > frontier.number }

    /// Where the guide sends you: a step back after many mistakes, a passed level with 3+ notes due today (reviews),
    /// else the first level not passed.
    public var recommended: Level {
        if let b = stepBack { return b }
        let f = frontier
        return Level.allCases.first { $0.number < f.number && dueCount($0) >= 3 } ?? f
    }

    /// A level chip tapped: your choice wins until "Torna al percorso".
    public func pick(_ l: Level) {
        guided = false
        stepBack = nil
        say(isAhead(l) ? "Viene dopo il livello \(frontier.number)" : nil)
        setLevel(l)
    }

    public func followGuide() {
        guided = true
        say(nil)
        setLevel(recommended)
    }

    private func say(_ s: String?) {
        guideNote = s
        noteLeft = s == nil ? 0 : 3
    }

    /// After each question: move to the level the guide wants, saying why. True when it changed level.
    private func steer() -> Bool {
        guard guided, focus == nil else { return false }
        let asked = rightFirst + missed
        if stepBack == level, rightFirst >= 8 { stepBack = nil }        // the round back went well
        if stepBack == nil, level == frontier, level.number > 1, asked >= 10, missed * 2 > asked {
            stepBack = Level.allCases[level.number - 2]
        }
        let to = recommended
        guard to != level else { return false }
        if let b = stepBack, b == to {
            say("Qui sbagli tante: un giro su «\(to.title)» e poi ci riprovi")
        } else if reviewing && dueCount(level) < 3 {
            say("Ripasso fatto. Ora: «\(to.title)»")
        } else if mastery(of: level) >= Self.pass {
            say("Livello \(level.number) superato! Ora: «\(to.title)»")
        } else {
            say(to.number < level.number ? "Prima il ripasso di oggi: «\(to.title)»" : "Ora: «\(to.title)»")
        }
        setLevel(to)
        return true
    }

    public func setLevel(_ l: Level) {
        level = l
        UserDefaults.standard.set(l.rawValue, forKey: "pt:quiz.level")
        focus = nil
        lastStage = nil
        pool = Self.pool(for: l, pieces: pieces)
        fromPieces = Set(Self.fromPieces(l, pieces))
        let notes = pool.flatMap { $0.chord.isEmpty ? [$0.midi] : $0.chord }
        var lo = (notes.min() ?? 60) / 12 * 12, hi = (notes.max() ?? 71) / 12 * 12 + 11
        if hi - lo < 23 { if lo >= 60 { hi = lo + 23 } else { lo = hi - 23 } }   // at least 2 octaves
        range = lo...hi
        newRound()
        reviewing = l.number < frontier.number
        item = nil
        next()
    }

    /// Share of this level's notes you know (box ≥ 3 = right 3 times in a row).
    public var mastery: Double {
        guard !pool.isEmpty else { return 0 }
        return Double(pool.filter { store.isKnown(level, $0) }.count) / Double(pool.count)
    }

    public func mastery(of l: Level) -> Double {
        _ = revision
        let p = Self.pool(for: l, pieces: pieces)
        guard !p.isEmpty else { return 0 }
        return Double(p.filter { store.isKnown(l, $0) }.count) / Double(p.count)
    }

    /// A V49 key pressed. Returns true when it answers the question. Its answers go to the note's V49 card : phone and keyboard answers are judged differently.
    @discardableResult
    public func press(_ m: Int) -> Bool {
        guard let it = item, feedback != .right else { return false }
        lastV49 = true
        event()
        if !it.chord.isEmpty { return pressChord(m, it, toggle: true) }
        let ok = level == .keyboard ? m % 12 == it.midi % 12 : m == it.midi
        if ok {
            if !wrongThisItem { rightFirst += 1 }
            store.answer(level, it, right: !wrongThisItem, seconds: elapsed, v49: true)
            track(it, seconds: elapsed, v49: true)
            feedback = .right
        } else {
            if !wrongThisItem { missed += 1 }
            wrongThisItem = true
            store.confuse(level, it, with: Staff.name(m, fifths: it.fifths), v49: true)
            explain(it, chose: m, name: nil)
            feedback = .wrong(m)
        }
        return ok
    }

    /// A V49 key let go: in Accordi the note leaves the chord being built.
    public func release(_ m: Int) {
        guard item?.chord.isEmpty == false, feedback != .right else { return }
        chosen.remove(m % 12)
    }

    /// V49 note-on in Accordi: add (never toggle off, the key is held).
    public func hold(_ m: Int) {
        guard let it = item else { return }
        if it.chord.isEmpty { press(m) } else if feedback != .right { lastV49 = true; event(); _ = pressChord(m, it, toggle: false) }
    }

    private func pressChord(_ m: Int, _ it: Item, toggle: Bool) -> Bool {
        let pc = m % 12, want = Set(it.chord.map { $0 % 12 })
        if toggle && chosen.contains(pc) { chosen.remove(pc); feedback = .none; return false }
        guard want.contains(pc) else {
            if !wrongThisItem { missed += 1 }
            wrongThisItem = true
            store.confuse(level, it, with: Staff.name(m, fifths: it.fifths), v49: true)
            feedback = .wrong(m)
            return false
        }
        chosen.insert(pc)
        if case .wrong = feedback { feedback = .none }
        guard chosen == want else { return false }
        if !wrongThisItem { rightFirst += 1 }
        store.answer(level, it, right: !wrongThisItem, seconds: elapsed, v49: true)
        track(it, seconds: elapsed, v49: true)
        feedback = .right
        return true
    }

    /// The right name for the question: the note as the sheet spells it, or the chord's name.
    public var answer: String {
        guard let it = item else { return "" }
        return it.chord.isEmpty ? Staff.name(it.midi, fifths: it.fifths) : it.chordName
    }

    /// A name button tapped. Returns true when it is the answer.
    @discardableResult
    public func choose(_ name: String) -> Bool {
        guard let it = item, feedback != .right else { return false }
        lastV49 = false
        event()
        guard name == answer else {
            if !wrongThisItem { missed += 1 }
            wrongThisItem = true
            store.confuse(level, it, with: name)
            explain(it, chose: nil, name: name)
            feedback = .wrongName(name)
            return false
        }
        if !wrongThisItem { rightFirst += 1 }
        store.answer(level, it, right: !wrongThisItem, seconds: elapsed)
        track(it, seconds: elapsed, v49: false)
        feedback = .right
        return true
    }

    private func makeChoices() {
        if level == .chords {
            // the same root's other kind and a chord with 2 notes in common are always there, so the lowest
            // note alone does not give the answer
            var pick: [String] = [answer]
            for c in Self.confusable(answer) where !pick.contains(c) { pick.append(c) }
            var others = Array(Set(pool.map(\.chordName)).subtracting(pick)).sorted()
            while pick.count < 4, !others.isEmpty { pick.append(others.remove(at: Int(generator() * Double(others.count)) % others.count)) }
            choices = pick.sorted()
        } else {
            var seen = Set<String>(), out: [(Int, String)] = []
            for it in pool {
                let n = Staff.name(it.midi, fifths: it.fifths)
                if seen.insert(n).inserted { out.append((((it.midi % 12) + 12) % 12, n)) }
            }
            // the seven letters always (a beginner must not guess from a short list), plus the pool's ♯/♭ names
            for (pc, n) in zip([0, 2, 4, 5, 7, 9, 11], Staff.letters) where !out.contains(where: { $0.0 == pc }) && seen.insert(n).inserted {
                out.append((pc, n))
            }
            // one black key in the pool = one ♯/♭ button = a lit black key answers itself; offer all five
            if level == .keyboard, out.contains(where: { [1, 3, 6, 8, 10].contains($0.0) }) {
                for pc in [1, 3, 6, 8, 10] where !out.contains(where: { $0.0 == pc }) {
                    out.append((pc, Staff.name(60 + pc, fifths: item?.fifths ?? 0)))
                }
            }
            choices = out.sorted { $0.0 < $1.0 }.map(\.1)
        }
    }

    /// Chord names easy to mix up with `name`: Do maggiore → Do minore + La minore; Do minore → Do maggiore + Mib
    /// maggiore; other kinds → the root's major and minor.
    static func confusable(_ name: String) -> [String] {
        guard let r = Chords.names.indices.last(where: { name.hasPrefix(Chords.names[$0] + " ") }) else { return [] }
        let root = Chords.names[r], kind = name.dropFirst(root.count + 1)
        switch kind {
        case "maggiore": return [root + " minore", Chords.names[(r + 9) % 12] + " minore"]
        case "minore": return [root + " maggiore", Chords.names[(r + 3) % 12] + " maggiore"]
        default: return [root + " maggiore", root + " minore"]
        }
    }

    /// The knowledge level of this note (the key-signature line goes away for notes you know).
    public func knows(_ it: Item) -> Bool { store.isKnown(level, it) }

    /// Two notes of the same clef less than 3 steps apart (Re → Mi): the second is counted from the first.
    private func near(_ a: Item, _ b: Item?) -> Bool {
        guard let b, a.chord.isEmpty, level != .keyboard, a.clef == b.clef else { return false }
        return abs(Staff.spell(a.midi, fifths: a.fifths).d - Staff.spell(b.midi, fifths: b.fifths).d) < 3
    }

    /// The next question (the screen calls it a moment after a right answer).
    public func next() {
        if item != nil {                                                   // nil = first question of a level
            if noteLeft > 0 { noteLeft -= 1; if noteLeft == 0 { guideNote = nil } }
            if steer() { return }                                          // setLevel asked the first question
        }
        feedback = .none
        hint = nil
        chosen = []
        wrongThisItem = false
        askedAt = CACurrentMediaTime()
        lastEvent = askedAt
        pausedThisItem = false
        guard !pool.isEmpty else { item = nil; shown = nil; return }
        // Leitner: box 0 = 8 shares, 1 = 4, 2 = 2, 3+ = 1, times up to 3 for a note found slower than the level's
        // usual
        // on a staff level the lines first, then the spaces, then everything (a training list overrides it)
        let st = focus == nil ? stageItems() : nil
        if st?.index != lastStage, let old = lastStage, (st?.index ?? 99) > old, noteLeft == 0 {
            guideNote = st == nil ? "Righe e spazi imparati: ora tutte le note del livello"
                : "Imparate! Ora anche " + Self.staffGroups[st!.clef]![st!.index].midi.map { Staff.name($0, fifths: 0) }.joined(separator: " ")
            noteLeft = 4
        }
        lastStage = st?.index
        var asked = focus.map { f in f + live.map(\.item).filter { !f.contains($0) } } ?? st?.items ?? pool
        if let f = focus, generator() < 1.0 / 3 {           // 5 notes in turn are known by elimination
            let rest = pool.filter { !f.contains($0) }
            if !rest.isEmpty { asked = rest }
        }
        // nothing from the last questions (a missed note must not come back from short-term memory);
        // not next to the previous note on the staff. Each rule gives way when the pool is too small for it.
        let gap = min(3, max(1, (asked.count - 1) / 2)), prev = item   // 3 notes = 1 between, 5 = 2
        var candidates = asked
        // gives way in a 3-note step (Sol Si Re: Si is next to both, it would never be asked)
        let rules: [(Item) -> Bool] = [{ !self.recent.suffix(gap).contains($0) }] + (asked.count > 3 ? [{ !self.near($0, prev) }] : [])
        for keep in rules {
            let f = candidates.filter(keep)
            if !f.isEmpty { candidates = f }
        }
        let v49 = lastV49
        let review = Set(live.map(\.item))
        let typical = median(asked.compactMap { store.stat(level, $0, v49: v49)?.average })
        let weights = candidates.map { it -> Double in
            let slow = store.stat(level, it, v49: v49)?.average.map { typical > 0 ? min(3, max(1, $0 / typical)) : 1 } ?? 1
            let due = store.isDue(level, it, v49: v49) ? 4.0 : 1                 // its review day has come
            return [8.0, 4, 2, 1][min(3, store.box(level, it, v49: v49))] * slow * due * (fromPieces.contains(it) ? 2 : 1)
                * (review.contains(it) ? 6 : 1)                     // missed/slow this round = back soon
        }
        var r = generator() * weights.reduce(0, +)
        var pick = candidates[candidates.count - 1]
        for (c, w) in zip(candidates, weights) {
            r -= w
            if r < 0 { pick = c; break }
        }
        let lastShown = shown
        item = pick
        recent = Array((recent + [pick]).suffix(3))
        shown = pick.midi
        if level == .keyboard {
            // a random octave, far from the key lit before (on the keyboard: no counting from the last one)
            let all = range.filter { $0 % 12 == pick.midi % 12 }
            let far = all.filter { m in lastShown.map { abs(Staff.spell(m, fifths: 0).d - Staff.spell($0, fifths: 0).d) >= 3 } ?? true }
            let from = far.isEmpty ? all : far
            if !from.isEmpty { shown = from[Int(generator() * Double(from.count)) % from.count] }
        }
        makeChoices()
    }

    /// The level's notes that are slow NOW or were missed lately (the list used the average of
    /// every answer ever and was full of red while the last answers took 1.5-3 s): the recent time is over the
    /// level's "fast" time and 30% over your usual, or a mistake sits in the last answers. Missed first, then slowest.
    /// Empty = you find them all quickly.
    public func slowest(_ n: Int = 8, level l: Level? = nil, v49: Bool = false) -> [Report] {
        let l = l ?? level
        let all = Self.pool(for: l, pieces: pieces).compactMap { it in store.stat(l, it, v49: v49).map { Report(item: it, stat: $0) } }
        let usual = median(all.compactMap(\.time)), fast = v49 ? QuizStore.fastV49 : QuizStore.fast(l)
        return all.filter { $0.missedLately || ($0.time ?? 0) > max(fast, usual * 1.3) }
            .sorted { ($0.missedLately ? 1 : 0, $0.time ?? 0) > ($1.missedLately ? 1 : 0, $1.time ?? 0) }
            .prefix(n).map { $0 }
    }

    /// Notes of a level answered at least once (on the buttons, or on the V49).
    public func answeredNotes(_ l: Level, v49: Bool = false) -> Int {
        _ = revision
        return Self.pool(for: l, pieces: pieces).filter { store.stat(l, $0, v49: v49) != nil }.count
    }

    /// A fresh round: this round's counts, live list and improved notes start again (the quiz goes on).
    public func restartRound() { newRound() }

    /// Riepilogo › "Allena queste": the round's notes to review become the training list.
    public func trainLive() {
        let s = live.map(\.item)
        guard !s.isEmpty else { return }
        focus = s
        focusConfused = false
        focusLive = true
        newRound()
        next()
    }

    /// Statistiche › Confusioni: for each note of the level, the wrong name chosen most and how often, most first.
    public struct Confusion: Identifiable {
        public let item: Item
        public let name: String
        public let chose: String
        public let count: Int
        public var id: String { item.key + "|" + chose }
    }

    public func confusions(_ n: Int = 6, level l: Level? = nil, v49: Bool = false) -> [Confusion] {
        _ = revision
        let l = l ?? level
        return Self.pool(for: l, pieces: pieces).flatMap { it -> [Confusion] in
            let name = it.chord.isEmpty ? Staff.name(it.midi, fifths: it.fifths) : it.chordName
            return (store.stat(l, it, v49: v49)?.confused ?? [:]).map { Confusion(item: it, name: name, chose: $0.key, count: $0.value) }
        }
        .sorted { ($0.count, $0.name) > ($1.count, $1.name) }
        .prefix(n).map { $0 }
    }

    /// Trains the notes of the confusions: the note asked and, when it is in the level, the one chosen instead.
    public func trainConfused(level l: Level? = nil, v49: Bool = false) {
        let l = l ?? level
        if l != level { setLevel(l) }
        var s: [Item] = []
        for c in confusions(level: l, v49: v49) {
            for it in [c.item] + pool.filter({ (Staff.name($0.midi, fifths: $0.fifths) == c.chose || $0.chordName == c.chose) })
            where !s.contains(it) { s.append(it) }
        }
        guard !s.isEmpty else { return }
        focus = s
        focusConfused = true
        focusLive = false
        newRound()
        next()
    }

    public func trainSlowest(_ n: Int = 5, v49: Bool = false) {
        let s = slowest(n, v49: v49).map(\.item)
        guard !s.isEmpty else { return }
        focus = s
        focusConfused = false
        focusLive = false
        newRound()
        next()
    }

    public func endFocus() {
        focus = nil
        newRound()
        next()
    }

    /// Notes of the level whose review day has come.
    public func dueCount(_ l: Level? = nil) -> Int {
        _ = revision
        let l = l ?? level
        return Self.pool(for: l, pieces: pieces).filter { store.isDue(l, $0) }.count
    }

    /// Notes of a level you know (right at the first try 3 times in a row, fast: `QuizStore.fast`) and how many there are.
    public func known(_ l: Level? = nil) -> (known: Int, total: Int) {
        _ = revision
        let l = l ?? level, p = Self.pool(for: l, pieces: pieces)
        return (p.filter { store.isKnown(l, $0) }.count, p.count)
    }

    /// Average seconds to the right answer over a level (nil before any answer).
    /// Any V49 answer on this level (Statistiche shows its Schermo / V49 choice only then).
    public func hasV49(_ l: Level) -> Bool {
        _ = revision
        return Self.pool(for: l, pieces: pieces).contains { store.stat(l, $0, v49: true) != nil }
    }

    public func averageSeconds(_ l: Level, v49: Bool = false) -> Double? {
        let st = Self.pool(for: l, pieces: pieces).compactMap { store.stat(l, $0, v49: v49) }
        let n = st.reduce(0) { $0 + $1.answers }
        return n == 0 ? nil : st.reduce(0) { $0 + $1.seconds } / Double(n)
    }

    public struct Report: Identifiable {
        public let item: Item
        public let stat: QuizStore.ItemStat
        public var id: String { item.key }
        public var name: String {
            item.chord.isEmpty ? Staff.name(item.midi, fifths: item.fifths) : item.chordName
        }
        /// The recent time (last 3 right answers); nil right after a miss (no right answer since: the miss's own time
        /// says nothing). Files from before `recent` existed: the last answer's.
        public var time: Double? { stat.answers == 0 ? nil : stat.recent == nil ? stat.last : stat.recentAverage }
        /// A mistake in the last answers: fewer than 3 right since the last wrong one (`recent` restarts at a miss).
        public var missedLately: Bool { stat.wrong > 0 && (stat.recent.map { $0.count < 3 } ?? false) }
    }

    private func median(_ v: [Double]) -> Double {
        let s = v.sorted()
        return s.isEmpty ? 0 : s[s.count / 2]
    }

    /// The name shown in the keyboard level ("Trova un Sol").
    public var askedName: String { item.map { Staff.name($0.midi, fifths: $0.fifths) } ?? "" }

    // MARK: pools

    /// Every white note of each clef:
    /// treble Do4–La5 (one ledger line each side), bass Mi2–Do4; the pieces' own notes are added and asked twice as often.
    static let defaultTreble = (60...81).filter { ![1, 3, 6, 8, 10].contains($0 % 12) }
    static let defaultBass = (40...60).filter { ![1, 3, 6, 8, 10].contains($0 % 12) }
    /// Key signatures the "all" level teaches besides the pieces' own: up to 2 ♯ / 2 ♭.
    static let generalKeys = [1, -1, 2, -2]

    static func pool(for l: Level, pieces: [Piece]) -> [Item] {
        var out = Set(fromPieces(l, pieces))
        switch l {
        case .keyboard:
            // all twelve keys (black ones spelled like the first piece, sharps without one)
            let fifths = pieces.first?.fifths ?? 0
            out = Set((0..<12).map { Item(midi: 60 + $0, clef: .treble, fifths: [1, 3, 6, 8, 10].contains($0) ? fifths : 0) })
        case .landmarks:
            return [Item(midi: 60, clef: .treble, fifths: 0), Item(midi: 67, clef: .treble, fifths: 0),
                    Item(midi: 72, clef: .treble, fifths: 0), Item(midi: 60, clef: .bass, fifths: 0),
                    Item(midi: 53, clef: .bass, fifths: 0), Item(midi: 48, clef: .bass, fifths: 0)]
        case .treble:
            out.formUnion(defaultTreble.map { Item(midi: $0, clef: .treble, fifths: 0) })
        case .bass:
            out.formUnion(defaultBass.map { Item(midi: $0, clef: .bass, fifths: 0) })
        case .all:
            // the notes a key signature changes (Fa→Fa♯ in Sol maggiore) and their neighbours that it doesn't (Mi, Sol),
            // in both clefs: with only changed notes every answer would carry a ♯/♭ (a hidden hint,)
            for f in generalKeys {
                for (clef, notes) in [(Staff.Clef.treble, defaultTreble), (.bass, defaultBass)] {
                    for m in notes {
                        let letter = Staff.spell(m, fifths: 0).letter
                        let acc = Staff.keyAccidental(letter: letter, fifths: f)
                        let nextToOne = [6, 1].contains { Staff.keyAccidental(letter: (letter + $0) % 7, fifths: f) != 0 }
                        if acc != 0 || nextToOne { out.insert(Item(midi: m + acc, clef: clef, fifths: f)) }
                    }
                }
            }
        case .chords:
            return chordPool(pieces)
        }
        return out.sorted { ($0.clef.rawValue, $0.fifths, $0.midi) < ($1.clef.rawValue, $1.fifths, $1.midi) }
    }

    /// The level's notes that come from the pieces (asked twice as often).
    static func fromPieces(_ l: Level, _ pieces: [Piece]) -> [Item] {
        let white = { (m: Int) in ![1, 3, 6, 8, 10].contains(m % 12) }
        switch l {
        case .treble, .bass:
            let h: Piece.Hand = l == .treble ? .right : .left
            return Set(pieces.flatMap { $0.events.filter { $0.h == h }.map(\.n) }.filter(white)).sorted()
                .map { Item(midi: $0, clef: l == .treble ? .treble : .bass, fifths: 0) }
        case .all:
            return Array(Set(pieces.flatMap { p in
                p.events.map { Item(midi: $0.n, clef: $0.h == .right ? .treble : .bass, fifths: p.fifths ?? 0) }
            }))
        default:
            return []
        }
    }

    /// The named chords (3+ different notes sounding together in one hand) of the pieces, in root position around
    /// middle C, plus always the beginner's six (Do, Fa, Sol maggiore; La, Re, Mi minore).
    static func chordPool(_ pieces: [Piece]) -> [Item] {
        var byName: [String: Item] = [:]
        func add(root: Int, intervals: [Int], name: String) {
            guard byName[name] == nil else { return }
            let r = 60 + root
            byName[name] = Item(midi: r, clef: .treble, fifths: 0, chord: intervals.map { r + $0 }, chordName: name)
        }
        for p in pieces {
            for h in [Piece.Hand.right, .left] {
                let groups = Dictionary(grouping: p.events.filter { $0.h == h }) { ($0.s * 96).rounded() }
                for g in groups.values {
                    let pcs = Array(Set(g.map { $0.n % 12 }))
                    guard pcs.count >= 3, let d = Chords.describe(g.map(\.n)), d.detail != "insieme di note",
                          !d.title.contains("/") else { continue }
                    let root = Chords.names.firstIndex { d.title.hasPrefix($0 + " ") } ?? 0
                    add(root: root, intervals: pcs.map { ($0 - root + 12) % 12 }.sorted(), name: d.title)
                }
            }
        }
        do {                                            // the beginner's six always (not only the pieces)
            for (root, minor) in [(0, false), (5, false), (7, false), (9, true), (2, true), (4, true)] {
                add(root: root, intervals: minor ? [0, 3, 7] : [0, 4, 7],
                    name: Chords.names[root] + (minor ? " minore" : " maggiore"))
            }
        }
        return byName.values.sorted { $0.chordName < $1.chordName }
    }
}

/// Leitner box per note and level + answers per day, saved as JSON next to the stats. This device writes only its own
/// answers (`mine`); the other devices' files come from the sync server (`PianoSync`) and every read adds them up:
/// counts are summed, the review state of a note (box, interval, due day) is the one of its latest answer anywhere.
public final class QuizStore {
    public struct Day: Codable, Equatable {
        public var right = 0
        public var wrong = 0
        public var seconds = 0.0
        /// Active practice seconds: Impara (quiz, prima vista) and Brani/Suona libero; AFK gaps left out.
        public var learn: Double?
        public var play: Double?
        public var practice: Double { (learn ?? 0) + (play ?? 0) }
        public init() {}
    }

    /// One note/chord of one level: how often, how fast, how many times wrong first.
    public struct ItemStat: Codable, Equatable {
        public var answers = 0
        public var firstTry = 0
        public var wrong = 0
        /// Seconds from the question to the right answer, summed (each capped at 30 s: a pause is not slowness).
        public var seconds = 0.0
        public var last = 0.0
        /// Spaced review across days (Cepeda et al. 2008, docs/DESIGN.md): days until the next review (1 → 2 → 4 → 8 → 16 →
        /// 32 after each first-try right, back to 1 after a miss) and that day (`yyyy-MM-dd`).
        public var interval = 0
        public var due: String?
        /// When it was last answered (seconds since 1970): across devices the latest answer sets the review state.
        public var at = 0.0
        /// Seconds of the latest first-try rights in a row (up to 3, emptied by a miss, like the box): "known" is
        /// timed on these, not on every answer ever (old slow answers kept a note "unknown").
        public var recent: [Double]?
        /// The wrong names chosen for this note and how often, e.g. Si ×2
        /// for La♯: Statistiche › Confusioni and their training.
        public var confused: [String: Int]?
        public var average: Double? { answers == 0 ? nil : seconds / Double(answers) }
        /// Average of `recent`; files from before it fall back to the last answer.
        public var recentAverage: Double? {
            guard let r = recent else { return answers == 0 ? nil : last }
            return r.isEmpty ? nil : r.reduce(0, +) / Double(r.count)
        }

        public init(answers: Int = 0, firstTry: Int = 0, wrong: Int = 0, seconds: Double = 0, last: Double = 0,
                    interval: Int = 0, due: String? = nil, at: Double = 0, recent: [Double]? = nil) {
            (self.answers, self.firstTry, self.wrong, self.seconds, self.last) = (answers, firstTry, wrong, seconds, last)
            (self.interval, self.due, self.at, self.recent) = (interval, due, at, recent)
        }

        /// Files from before the review fields  still decode.
        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            answers = try c.decodeIfPresent(Int.self, forKey: .answers) ?? 0
            firstTry = try c.decodeIfPresent(Int.self, forKey: .firstTry) ?? 0
            wrong = try c.decodeIfPresent(Int.self, forKey: .wrong) ?? 0
            seconds = try c.decodeIfPresent(Double.self, forKey: .seconds) ?? 0
            last = try c.decodeIfPresent(Double.self, forKey: .last) ?? 0
            interval = try c.decodeIfPresent(Int.self, forKey: .interval) ?? 0
            due = try c.decodeIfPresent(String.self, forKey: .due)
            at = try c.decodeIfPresent(Double.self, forKey: .at) ?? 0
            recent = try c.decodeIfPresent([Double].self, forKey: .recent)
            confused = try c.decodeIfPresent([String: Int].self, forKey: .confused)
        }
    }

    /// "Known" needs speed too (sight reading goes with fast recognition): right at the first try 3 times
    /// in a row AND those 3 found in under this many seconds on average. Tastiera has 12 name buttons to look through
    /// (2 s was out of reach once eye + finger are counted), the others up to 7 + ♯/♭.
    public static func fast(_ l: NoteQuiz.Level) -> Double { l == .keyboard ? 3.0 : 2.5 }
    /// The V49's: reading the note AND moving the hand to the key (staff levels; Tastiera never counts from it).
    public static let fastV49 = 4.0                     // 3 → 4 s (reading + moving the hand, a beginner)

    struct Data_: Codable {
        /// 2 = review days grow once a day; nil = older, see `merge`.
        var v: Int?
        var boxes: [String: Int] = [:]
        var days: [String: Day] = [:]
        /// Optional so older quiz.json files still decode.
        var items: [String: ItemStat]?
        /// Prima vista (sight reading) per tappa ("1" …): melodies read, notes right at the first try / wrong.
        var sight: [String: SightStat]?
    }

    public struct SightStat: Codable, Equatable {
        public var melodies = 0
        public var right = 0
        public var wrong = 0
        public var seconds = 0.0
        public var accuracy: Double { right + wrong == 0 ? 0 : Double(right) / Double(right + wrong) }
    }

    /// This device's own answers (saved, sent to the server).
    private(set) var mine = Data_(v: 2)
    /// The other devices' answers, as the server last gave them.
    private var others: [Data_] = []
    /// mine + others, what every read uses.
    private var view = Data_()
    private let url: URL

    public init(url: URL? = nil) {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Piano", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.url = url ?? dir.appendingPathComponent("quiz.json")
        // through `merge` even alone: old cards get their one name (`storeKey`) and old review days are fixed
        if let d = try? Data(contentsOf: self.url), let decoded = try? JSONDecoder().decode(Data_.self, from: d) {
            mine = Self.merge([decoded])
        }
        others = (try? Data(contentsOf: Self.othersURL(self.url))).flatMap { try? JSONDecoder().decode([Data_].self, from: $0) } ?? []
        view = Self.merge([mine] + others)
    }

    /// The other devices' data from the server (kept on disk, so the sums are there offline too).
    func setOthers(_ list: [Data_]) {
        others = list
        if let out = try? JSONEncoder().encode(list) { try? out.write(to: Self.othersURL(url), options: .atomic) }
        view = Self.merge([mine] + others)
    }

    static func othersURL(_ url: URL) -> URL { url.deletingPathExtension().appendingPathExtension("others.json") }

    /// The one name of a note's card: every read and write goes
    /// through it, so a change in how a level spells its notes never splits their statistics again. Tastiera = the
    /// key alone (its white keys' ♯/♭ spelling once changed and left their old answers on a second card).
    /// `v49`: the note's V49 card, apart from the buttons' one (older cards stay the buttons' ones: nothing moves).
    static func storeKey(_ l: NoteQuiz.Level, _ it: NoteQuiz.Item, v49: Bool = false) -> String {
        (l == .keyboard && it.chord.isEmpty ? "\(l.rawValue)|key:\(it.midi)" : "\(l.rawValue)|\(it.key)") + (v49 ? "|v49" : "")
    }

    /// A saved card name → its name today (`storeKey`): "0|G:65:2" and "0|G:65:0" are both "0|key:65".
    static func canonical(_ k: String) -> String {
        let p = k.split(separator: "|", maxSplits: 1)
        guard p.count == 2, p[0] == "\(NoteQuiz.Level.keyboard.rawValue)" else { return k }
        let f = p[1].split(separator: ":")
        guard f.count == 3, f[0] != "chord", let m = Int(f[1]) else { return k }
        return "\(p[0])|key:\(m)"
    }

    /// Every device's answers as one: counts summed, the review state of a card = its latest answer anywhere. Also
    /// for one list alone: cards are renamed with `canonical` (two old cards of one note = one, summed) and files from
    /// before v2 get their review days back to at most 2 (they doubled at every answer, even in the same session: 32
    /// days after one evening).
    static func merge(_ list: [Data_]) -> Data_ {
        var out = Data_(), latest: [String: Double] = [:]
        out.v = 2
        var items: [String: ItemStat] = [:]
        for d in list {
            for (k, v) in d.days {
                var t = out.days[k, default: Day()]
                t.right += v.right; t.wrong += v.wrong; t.seconds += v.seconds
                if v.learn != nil { t.learn = (t.learn ?? 0) + v.learn! }
                if v.play != nil { t.play = (t.play ?? 0) + v.play! }
                out.days[k] = t
            }
            for (old, v0) in d.items ?? [:] {
                let k = canonical(old)
                var v = v0
                if d.v == nil, v.interval > 2 {
                    v.interval = 2
                    v.due = StatsStore.dayKey(Calendar.current.date(
                        byAdding: .day, value: 2, to: Date(timeIntervalSince1970: v.at))!)
                }
                var t = items[k] ?? ItemStat()
                t.answers += v.answers; t.firstTry += v.firstTry; t.wrong += v.wrong; t.seconds += v.seconds
                for (name, n) in v.confused ?? [:] { t.confused = (t.confused ?? [:]).merging([name: n], uniquingKeysWith: +) }
                if v.at >= (latest[k] ?? -1) {
                    latest[k] = v.at
                    (t.last, t.interval, t.due, t.at, t.recent) = (v.last, v.interval, v.due, v.at, v.recent)
                    out.boxes[k] = d.boxes[old] ?? 0
                }
                items[k] = t
            }
            for (old, b) in d.boxes {   // boxes without stats (old files)
                let k = canonical(old)
                if latest[k] == nil && out.boxes[k] == nil { out.boxes[k] = b }
            }
            for (k, v) in d.sight ?? [:] {
                var t = out.sight?[k] ?? SightStat()
                t.melodies += v.melodies; t.right += v.right; t.wrong += v.wrong; t.seconds += v.seconds
                out.sight = (out.sight ?? [:]).merging([k: t]) { $1 }
            }
        }
        out.items = items
        return out
    }

    func box(_ l: NoteQuiz.Level, _ it: NoteQuiz.Item, v49: Bool = false) -> Int {
        view.boxes[Self.storeKey(l, it, v49: v49)] ?? 0
    }

    /// `seconds` nil = a pause: the answer counts, its time is the note's usual one (averages stay true) and
    /// it never enters `recent`/`last`.
    func answer(_ l: NoteQuiz.Level, _ it: NoteQuiz.Item, right: Bool, seconds: Double?, date: Date = Date(),
                v49: Bool = false) {
        let k = Self.storeKey(l, it, v49: v49)
        // the review state goes on from the latest answer on any device; the counts are this device's own
        let seen = view.items?[k]
        mine.boxes[k] = right ? min(4, (view.boxes[k] ?? 0) + 1) : 0
        var st = mine.items?[k] ?? ItemStat()
        st.answers += 1
        if right { st.firstTry += 1 } else { st.wrong += 1 }
        // review days grow once a day, never inside one session (6 rights in one evening = 32 days)
        let sameDay = seen.map { StatsStore.dayKey(Date(timeIntervalSince1970: $0.at)) == StatsStore.dayKey(date) } ?? false
        st.interval = !right ? 1 : sameDay && (seen?.interval ?? 0) > 0 ? seen!.interval
            : min(32, max(1, (seen?.interval ?? 0) * 2))
        st.due = StatsStore.dayKey(Calendar.current.date(byAdding: .day, value: st.interval, to: date)!)
        let usual = seen?.average ?? (v49 ? Self.fastV49 : Self.fast(l)) * 1.5
        let t = seconds.map { min($0, 30) }
        st.seconds += t ?? usual
        st.last = t ?? seen?.last ?? usual
        st.at = max(date.timeIntervalSince1970, (seen?.at ?? 0) + 0.001)
        st.recent = !right ? [] : t.map { Array(((seen?.recent ?? []) + [$0]).suffix(3)) } ?? seen?.recent
        mine.items = (mine.items ?? [:]).merging([k: st]) { $1 }
        var d = mine.days[StatsStore.dayKey(date), default: Day()]
        if right { d.right += 1 } else { d.wrong += 1 }
        d.seconds += t ?? usual
        mine.days[StatsStore.dayKey(date)] = d
        if let out = try? JSONEncoder().encode(mine) { try? out.write(to: url, options: .atomic) }
        view = Self.merge([mine] + others)
    }

    func stat(_ l: NoteQuiz.Level, _ it: NoteQuiz.Item, v49: Bool = false) -> ItemStat? {
        view.items?[Self.storeKey(l, it, v49: v49)]
    }

    /// A wrong name chosen for `it` (a button, or the name of the V49 key pressed): Statistiche › Confusioni.
    func confuse(_ l: NoteQuiz.Level, _ it: NoteQuiz.Item, with name: String, v49: Bool = false) {
        let k = Self.storeKey(l, it, v49: v49)
        var st = mine.items?[k] ?? ItemStat()
        st.confused = (st.confused ?? [:]).merging([name: 1], uniquingKeysWith: +)
        mine.items = (mine.items ?? [:]).merging([k: st]) { $1 }
        if let out = try? JSONEncoder().encode(mine) { try? out.write(to: url, options: .atomic) }
        view = Self.merge([mine] + others)
    }

    /// Prima vista: one melody read in a tappa.
    func recordSight(tappa: Int, right: Int, wrong: Int, seconds: Double, date: Date = Date()) {
        var st = mine.sight?["\(tappa)"] ?? SightStat()
        st.melodies += 1; st.right += right; st.wrong += wrong; st.seconds += min(seconds, 300)
        mine.sight = (mine.sight ?? [:]).merging(["\(tappa)": st]) { $1 }
        var d = mine.days[StatsStore.dayKey(date), default: Day()]   // counts in "oggi" too
        d.right += right; d.wrong += wrong; d.seconds += min(seconds, 300)
        mine.days[StatsStore.dayKey(date)] = d
        if let out = try? JSONEncoder().encode(mine) { try? out.write(to: url, options: .atomic) }
        view = Self.merge([mine] + others)
    }

    public func sight(tappa: Int) -> SightStat { view.sight?["\(tappa)"] ?? SightStat() }

    /// Right at the first try 3 times in a row and fast (see `fast`). A rule change never takes a note away: the old all-answers average under 2 s
    /// still counts.
    /// Buttons or V49, each on its own card with its own speed: Tastiera only from the buttons
    /// (on the V49 you copy the yellow key: training, not knowing), the staff levels from either.
    func isKnown(_ l: NoteQuiz.Level, _ it: NoteQuiz.Item) -> Bool {
        if box(l, it) >= 3, let st = stat(l, it),
           (st.recentAverage ?? .infinity) < Self.fast(l) || (st.average ?? .infinity) < 2.0 || Self.mostlyFast(st, Self.fast(l)) { return true }
        guard l != .keyboard, box(l, it, v49: true) >= 3, let v = stat(l, it, v49: true) else { return false }
        return (v.recentAverage ?? .infinity) < Self.fastV49 || Self.mostlyFast(v, Self.fastV49)
    }

    /// (gentler for a beginner, only widens the old rule): 2 of the last 3 right answers under the time, so one
    /// slow answer doesn't take a note away.
    static func mostlyFast(_ st: ItemStat, _ fast: Double) -> Bool {
        guard let r = st.recent, r.count >= 2 else { return false }
        return r.suffix(3).filter { $0 < fast }.count >= 2
    }

    /// 3 right at the first try in a row on either card (speed aside): the staff steps move on with it.
    func isSteady(_ l: NoteQuiz.Level, _ it: NoteQuiz.Item) -> Bool {
        box(l, it) >= 3 || box(l, it, v49: true) >= 3
    }

    /// Seen before and its review day has come (today or earlier).
    func isDue(_ l: NoteQuiz.Level, _ it: NoteQuiz.Item, v49: Bool = false, today: Date = Date()) -> Bool {
        guard let d = stat(l, it, v49: v49)?.due else { return false }
        return d <= StatsStore.dayKey(today)
    }

    // MARK: practice time

    public enum Practice { case learn, play }
    @ObservationIgnored private var lastTick: [Practice: Double] = [:]
    @ObservationIgnored private var pending: [Practice: Double] = [:]

    /// A touch, an answer or a key: the time since the previous one counts as practice when it is short (≤
    /// `NoteQuiz.pause`); a longer gap was a pause/AFK. Saved every 20 s and on `flushPractice`.
    public func practice(_ kind: Practice, now: Double = Date().timeIntervalSince1970) {
        if let last = lastTick[kind], now - last <= NoteQuiz.pause, now > last { pending[kind, default: 0] += now - last }
        lastTick[kind] = now
        if pending.values.reduce(0, +) >= 20 { flushPractice(now: now) }
    }

    /// Writes the practice time gathered so far into today (app to the background, before a sync).
    public func flushPractice(now: Double = Date().timeIntervalSince1970) {
        guard pending.values.contains(where: { $0 > 0 }) else { return }
        let k = StatsStore.dayKey(Date(timeIntervalSince1970: now))
        var d = mine.days[k, default: Day()]
        if let s = pending[.learn], s > 0 { d.learn = (d.learn ?? 0) + s }
        if let s = pending[.play], s > 0 { d.play = (d.play ?? 0) + s }
        mine.days[k] = d
        pending = [:]
        if let out = try? JSONEncoder().encode(mine) { try? out.write(to: url, options: .atomic) }
        view = Self.merge([mine] + others)
    }

    /// Days in a row with some practice or answers, up to today (or yesterday, when today has none yet).
    public func streak(until date: Date = Date()) -> Int {
        let cal = Calendar.current
        func active(_ d: Date) -> Bool {
            let x = view.days[StatsStore.dayKey(d)] ?? Day()
            return x.practice > 0 || x.right + x.wrong > 0
        }
        var day = active(date) ? date : cal.date(byAdding: .day, value: -1, to: date)!, n = 0
        while active(day) { n += 1; day = cal.date(byAdding: .day, value: -1, to: day)! }
        return n
    }

    /// The last `n` days (oldest first), days without answers included as zero.
    public func history(days n: Int = 14, until date: Date = Date()) -> [(day: Date, stats: Day)] {
        (0..<n).reversed().map { i in
            let d = Calendar.current.date(byAdding: .day, value: -i, to: date)!
            return (d, view.days[StatsStore.dayKey(d)] ?? Day())
        }
    }

    /// Answers given today (for "oggi: 24 note, 2,1 s di media").
    public func today(_ date: Date = Date()) -> Day { view.days[StatsStore.dayKey(date)] ?? Day() }
}
