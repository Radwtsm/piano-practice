import XCTest
@testable import PianoKit

/// Quiz delle note: spelling on the staff, pools from the bundled piece (Ode to Joy), answers and the Leitner boxes.
@MainActor
final class NoteQuizTests: XCTestCase {
    private func piece() throws -> Piece {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "Fixtures/ode-to-joy.musicxml", withExtension: nil))
        return try Piece.load(name: "ode-to-joy.musicxml", data: try Data(contentsOf: url))
    }

    private func quiz(_ pieces: [Piece] = [], guided: Bool = false) -> NoteQuiz {
        UserDefaults.standard.removeObject(forKey: "pt:quiz.level")
        UserDefaults.standard.set(guided, forKey: "pt:quiz.guided")                    // most tests pick the level
        let store = QuizStore(url: FileManager.default.temporaryDirectory.appendingPathComponent("quiz-\(UUID()).json"))
        var seed: UInt64 = 42                                                             // deterministic "random"
        let q = NoteQuiz(store: store, random: {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return Double(seed >> 11) / Double(1 << 53)
        })
        q.use(pieces: pieces)
        return q
    }

    func testSpelling() {
        XCTAssertEqual(Staff.spell(60, fifths: 0), .init(d: 28, letter: 0, acc: 0))      // Do centrale
        XCTAssertEqual(Staff.spell(67, fifths: 0).d, 32)                                   // Sol: second line from E4 (30)
        XCTAssertEqual(Staff.name(66, fifths: 2), "Fa#")
        XCTAssertEqual(Staff.name(70, fifths: -1), "Sib")
        XCTAssertEqual(Staff.keyAccidental(letter: 3, fifths: 2), 1)                       // Fa in Re maggiore
        XCTAssertEqual(Staff.keyAccidental(letter: 4, fifths: 2), 0)
    }

    func testKeyboardLevelAcceptsAnyOctave() {
        let q = quiz()
        q.setLevel(.keyboard)
        let it = try! XCTUnwrap(q.item)
        XCTAssertFalse(q.press(it.midi + 1))
        XCTAssertEqual(q.feedback, .wrong(it.midi + 1))
        XCTAssertTrue(q.press(it.midi - 24))
        XCTAssertEqual(q.feedback, .right)
        XCTAssertEqual(q.rightFirst, 0)                                                   // a mistake came first
        XCTAssertEqual(q.missed, 1)
    }

    func testStaffLevelNeedsTheExactKey() throws {
        let q = quiz()
        q.setLevel(.treble)
        let it = try XCTUnwrap(q.item)
        XCTAssertFalse(q.press(it.midi + 12))                                             // right name, wrong octave
        XCTAssertTrue(q.press(it.midi))
    }

    func testPoolsComeFromThePieces() throws {
        let p = try piece()
        let q = quiz([p])
        q.setLevel(.treble)
        let right = Set(p.events.filter { $0.h == .right }.map(\.n)).filter { ![1, 3, 6, 8, 10].contains($0 % 12) }
        let treble = Set(q.pool.map(\.midi))
        XCTAssertTrue(right.isSubset(of: treble))                                         // the pieces' notes …
        XCTAssertTrue(Set(NoteQuiz.defaultTreble).isSubset(of: treble))                   // … and the whole clef
        XCTAssertTrue(q.pool.allSatisfy { $0.clef == .treble })
        q.setLevel(.bass)
        XCTAssertTrue(q.pool.allSatisfy { $0.clef == .bass })
        XCTAssertGreaterThanOrEqual(q.range.count, 24)
        q.setLevel(.chords)
        XCTAssertFalse(q.pool.isEmpty)
        XCTAssertTrue(q.pool.allSatisfy { $0.chord.count >= 3 && !$0.chordName.isEmpty })
    }

    func testChordIsBuiltKeyByKey() throws {
        let q = quiz()
        q.setLevel(.chords)
        let it = try XCTUnwrap(q.item)
        let notes = it.chord
        XCTAssertFalse(q.press(notes[0] + 12))                                            // any octave counts
        XCTAssertFalse(q.press(notes[0] + 12))                                            // tapped again = removed
        XCTAssertTrue(q.chosen.isEmpty)
        XCTAssertFalse(q.press(notes[0] + 1))                                             // not in the chord
        XCTAssertEqual(q.feedback, .wrong(notes[0] + 1))
        for n in notes.dropLast() { q.hold(n) }
        q.release(notes[0])
        XCTAssertEqual(q.chosen.count, notes.count - 2)
        q.hold(notes[0])
        q.hold(notes.last!)
        XCTAssertEqual(q.feedback, .right)
    }

    /// Answers are name buttons on iOS — all seven letters, Do first; chords = 4 names.
    func testNameButtons() throws {
        let q = quiz()
        q.setLevel(.treble)
        XCTAssertEqual(q.choices, Staff.letters)
        let wrongName = try XCTUnwrap(q.choices.first { $0 != q.answer })
        XCTAssertFalse(q.choose(wrongName))
        XCTAssertEqual(q.feedback, .wrongName(wrongName))
        XCTAssertTrue(q.choose(q.answer))
        XCTAssertEqual(q.missed, 1)
        q.setLevel(.all)
        XCTAssertTrue(Set(Staff.letters).isSubset(of: Set(q.choices)))
        q.setLevel(.chords)
        XCTAssertEqual(q.choices.count, 4)
        XCTAssertTrue(q.choices.contains(q.answer))
        XCTAssertTrue(q.choose(q.answer))
    }

    /// Time to find each note; the slowest come first in the stats and can be trained alone.
    func testTimesAndSlowestNotes() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("quiz-\(UUID()).json")
        let store = QuizStore(url: url)
        UserDefaults.standard.removeObject(forKey: "pt:quiz.level")
        let q = NoteQuiz(store: store, random: { 0.5 })
        q.use(pieces: [])
        q.setLevel(.treble)
        let a = q.pool[0], b = q.pool[1]
        store.answer(.treble, a, right: true, seconds: 1)
        store.answer(.treble, b, right: false, seconds: 6)
        store.answer(.treble, b, right: true, seconds: 50)                        // capped at 30
        let sb = try XCTUnwrap(store.stat(.treble, b))
        XCTAssertEqual([sb.answers, sb.firstTry, sb.wrong], [2, 1, 1])
        XCTAssertEqual(sb.seconds, 36)
        XCTAssertEqual(sb.last, 30)
        XCTAssertEqual(q.slowest().map(\.item), [b])                              // a is fast, b missed lately
        XCTAssertEqual(q.averageSeconds(.treble)!, 37.0 / 3, accuracy: 0.001)
        q.trainSlowest(1)
        XCTAssertEqual(q.focus, [b])
        XCTAssertEqual(q.item, b)
        q.setLevel(.bass)                                                          // another level ends the focus
        XCTAssertNil(q.focus)
        XCTAssertEqual(QuizStore(url: url).stat(.treble, b)?.answers, 2)          // saved
        XCTAssertEqual(store.history(days: 3).count, 3)
        XCTAssertEqual(store.history(days: 3).last?.stats.right, 2)
    }

    /// Review days double after each first-try right and reset after a miss; "known" needs
    /// 3 first-try rights in a row AND those 3 fast (`QuizStore.fast`).
    func testReviewDaysAndFastMastery() throws {
        let store = QuizStore(url: FileManager.default.temporaryDirectory.appendingPathComponent("quiz-\(UUID()).json"))
        let it = NoteQuiz.Item(midi: 67, clef: .treble, fifths: 0)
        let day = { (d: Int) in Calendar.current.date(byAdding: .day, value: d, to: Date())! }
        store.answer(.treble, it, right: true, seconds: 1, date: day(0))
        XCTAssertEqual(store.stat(.treble, it)?.interval, 1)
        XCTAssertFalse(store.isDue(.treble, it, today: day(0)))
        XCTAssertTrue(store.isDue(.treble, it, today: day(1)))
        store.answer(.treble, it, right: true, seconds: 1, date: day(1))
        store.answer(.treble, it, right: true, seconds: 1, date: day(3))
        XCTAssertEqual(store.stat(.treble, it)?.interval, 4)
        XCTAssertTrue(store.isKnown(.treble, it))
        store.answer(.treble, it, right: false, seconds: 1, date: day(7))
        XCTAssertEqual(store.stat(.treble, it)?.interval, 1)
        XCTAssertFalse(store.isKnown(.treble, it))
        let slow = NoteQuiz.Item(midi: 69, clef: .treble, fifths: 0)
        for _ in 0..<3 { store.answer(.treble, slow, right: true, seconds: 5) }
        XCTAssertFalse(store.isKnown(.treble, slow))                                // right but slow = not known yet
        for _ in 0..<3 { store.answer(.treble, slow, right: true, seconds: 2) }
        XCTAssertTrue(store.isKnown(.treble, slow))                                 // only the latest 3 count
        let key = NoteQuiz.Item(midi: 64, clef: .treble, fifths: 0)
        for _ in 0..<3 { store.answer(.keyboard, key, right: true, seconds: 2.8) }
        XCTAssertTrue(store.isKnown(.keyboard, key))                                // Tastiera: 12 buttons, 3 s
        XCTAssertFalse(store.isKnown(.treble, key))
        let old = NoteQuiz.Item(midi: 72, clef: .treble, fifths: 0)               // known by the old rule: stays known
        for s in [1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 3.5, 3.5, 3.5] { store.answer(.treble, old, right: true, seconds: s) }
        XCTAssertTrue(store.isKnown(.treble, old))
    }

    /// quiz.json written before per-note stats existed still loads its boxes.
    func testOldQuizFileStillLoads() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("quiz-\(UUID()).json")
        try #"{"boxes":{"2|G:67:0":3},"days":{},"items":{"2|G:69:0":{"answers":2,"firstTry":2,"wrong":0,"seconds":3,"last":1}}}"#
            .write(to: url, atomically: true, encoding: .utf8)
        let store = QuizStore(url: url)
        XCTAssertEqual(store.box(.treble, .init(midi: 67, clef: .treble, fifths: 0)), 3)
        XCTAssertNil(store.stat(.treble, .init(midi: 67, clef: .treble, fifths: 0)))
        XCTAssertEqual(store.stat(.treble, .init(midi: 69, clef: .treble, fifths: 0))?.answers, 2)  // file from before the review fields
    }

    /// The Tastiera's white keys were respelled (fifths 2 → 0) and
    /// left their answers on a second card; both cards of a key are one again (summed, latest state), on load and
    /// across devices, and a pre-v2 file's review days come back to at most 2.
    func testOldSplitCardsMergeAndReviewDaysAreFixed() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("quiz-\(UUID()).json")
        try #"{"boxes":{"0|G:65:2":4,"0|G:65:0":2},"days":{},"items":{"0|G:65:2":{"answers":13,"firstTry":12,"wrong":1,"seconds":91,"last":2,"interval":32,"due":"2026-11-25","at":1000},"0|G:65:0":{"answers":12,"firstTry":11,"wrong":1,"seconds":47,"last":3,"interval":32,"due":"2026-11-25","at":2000}}}"#
            .write(to: url, atomically: true, encoding: .utf8)
        let store = QuizStore(url: url)
        for f in [0, 2, 5] {                                                   // any spelling = the same card
            let st = store.stat(.keyboard, .init(midi: 65, clef: .treble, fifths: f))
            XCTAssertEqual(st?.answers, 25)
            XCTAssertEqual(st?.wrong, 2)
            XCTAssertEqual(st?.interval, 2)                                    // was 32 after one evening
            XCTAssertEqual(store.box(.keyboard, .init(midi: 65, clef: .treble, fifths: f)), 2)   // latest card's box
        }
        XCTAssertEqual(QuizStore.canonical("3|F:50:0"), "3|F:50:0")           // other levels keep their names
        XCTAssertEqual(QuizStore.canonical("5|chord:Do maggiore"), "5|chord:Do maggiore")
    }

    /// Review days grow once a day, never inside one session.
    func testReviewDaysGrowOncePerDay() throws {
        let store = QuizStore(url: FileManager.default.temporaryDirectory.appendingPathComponent("quiz-\(UUID()).json"))
        let it = NoteQuiz.Item(midi: 67, clef: .treble, fifths: 0)
        let day = { (d: Int) in Calendar.current.date(byAdding: .day, value: d, to: Date())! }
        for _ in 0..<6 { store.answer(.treble, it, right: true, seconds: 1, date: day(0)) }
        XCTAssertEqual(store.stat(.treble, it)?.interval, 1)
        store.answer(.treble, it, right: true, seconds: 1, date: day(1))
        store.answer(.treble, it, right: true, seconds: 1, date: day(1))
        XCTAssertEqual(store.stat(.treble, it)?.interval, 2)
    }

    /// A wrong name is remembered per note; training asks the pair.
    func testConfusionsAreSavedAndTrained() throws {
        let q = quiz()
        q.setLevel(.keyboard)
        var asked = q.item!
        let right = q.answer
        let wrong = q.choices.first { $0 != right }!
        q.choose(wrong)
        q.choose(wrong)
        q.choose(right)
        let c = q.confusions().first!
        XCTAssertEqual(c.item.midi, asked.midi)
        XCTAssertEqual(c.chose, wrong)
        XCTAssertEqual(c.count, 2)
        q.trainConfused()
        XCTAssertTrue(q.focusConfused)
        XCTAssertTrue(q.focus!.contains(asked))
        XCTAssertTrue(q.focus!.contains { Staff.name($0.midi, fifths: $0.fifths) == wrong })   // the note chosen too
        asked = q.item!
        XCTAssertTrue(q.focus!.contains(asked))
    }

    /// A wrong name in the same place of the other black-key group
    /// lights the asked key's group and says to count the black keys; any other mistake doesn't.
    func testGroupHintForSamePlaceInTheOtherGroup() throws {
        let q = quiz()
        q.setLevel(.keyboard)
        var hinted = 0
        for _ in 0..<40 {
            let it = q.item!, pc = it.midi % 12, lit = q.shown ?? it.midi
            let other: [Int: String] = [2: "Sol", 7: "Re", 4: "Si", 11: "Mi", 0: "Fa", 5: "Do"]
            if let wrong = other[pc] {
                q.choose(wrong)
                XCTAssertEqual(q.hint?.keys, [2, 4].contains(pc) || pc == 0 ? [lit + 1 - pc, lit + 3 - pc]   // its octave
                               : [lit + 6 - pc, lit + 8 - pc, lit + 10 - pc])
                hinted += 1
            } else if [1, 3, 6, 8, 10].contains(pc) {
                q.choose(pc == 1 ? "Mi" : "Do")                                   // black asked, white chosen: no hint
                XCTAssertNil(q.hint?.keys)
            }
            q.choose(q.answer)
            q.next()
            XCTAssertNil(q.hint?.keys)                                             // gone with the next question
        }
        XCTAssertGreaterThan(hinted, 3)
    }

    /// The V49 is judged apart from the buttons. Its answers go to their own card; on Tastiera they
    /// never make a note known (you copy the yellow key), on the staff levels they do with their own speed.
    func testV49AnswersHaveTheirOwnCard() throws {
        let store = QuizStore(url: FileManager.default.temporaryDirectory.appendingPathComponent("quiz-\(UUID()).json"))
        let key = NoteQuiz.Item(midi: 62, clef: .treble, fifths: 0)
        for _ in 0..<3 { store.answer(.keyboard, key, right: true, seconds: 1, v49: true) }
        XCTAssertNil(store.stat(.keyboard, key))                                   // buttons' card untouched
        XCTAssertEqual(store.stat(.keyboard, key, v49: true)?.answers, 3)
        XCTAssertFalse(store.isKnown(.keyboard, key))                               // Tastiera: V49 never counts
        let g = NoteQuiz.Item(midi: 67, clef: .treble, fifths: 0)
        for _ in 0..<3 { store.answer(.treble, g, right: true, seconds: 2.8, v49: true) }
        XCTAssertTrue(store.isKnown(.treble, g))                                    // staff: V49 under 4 s counts
        let a = NoteQuiz.Item(midi: 69, clef: .treble, fifths: 0)
        for _ in 0..<3 { store.answer(.treble, a, right: true, seconds: 4.5, v49: true) }
        XCTAssertFalse(store.isKnown(.treble, a))
        for _ in 0..<3 { store.answer(.treble, a, right: true, seconds: 1.5) }      // the buttons' card still counts
        XCTAssertTrue(store.isKnown(.treble, a))

        let q = quiz()
        q.setLevel(.treble)
        let it = q.item!
        q.press(it.midi)                                                            // the V49 path
        XCTAssertEqual(q.answeredNotes(.treble, v49: true), 1)
        XCTAssertEqual(q.answeredNotes(.treble), 0)
        XCTAssertTrue(q.hasV49(.treble))
    }

    /// Practising on the V49, a note missed on the V49 comes back more often (the pick read only the
    /// buttons' cards, so V49 mistakes changed nothing during the practice).
    func testV49MistakesComeBackMoreOftenOnTheV49() throws {
        let q = quiz()
        q.setLevel(.treble)
        let target = try XCTUnwrap(q.pool.first)
        for it in q.pool where it != target {                                       // the rest: known on the V49
            for _ in 0..<3 { q.store.answer(.treble, it, right: true, seconds: 1, v49: true) }
        }
        q.store.answer(.treble, target, right: false, seconds: 1, v49: true)
        var asked = 0
        for _ in 0..<300 {
            let it = try XCTUnwrap(q.item)
            if it == target { asked += 1; q.store.answer(.treble, it, right: false, seconds: 1, v49: true) }
            q.press(it.midi)                                                        // answered on the V49
            q.next()
        }
        XCTAssertGreaterThan(Double(asked), 2.5 * 300 / Double(q.pool.count))      // fair share ×2.5 or more
    }

    /// A note missed this round is in `live` and comes back often; two quick first-try rights in a row move it to `improved`.
    func testLiveReviewDuringTheRound() throws {
        let q = quiz()
        q.setLevel(.treble)
        let target = try XCTUnwrap(q.item)
        XCTAssertFalse(q.choose(q.choices.first { $0 != q.answer }!))              // a mistake…
        XCTAssertTrue(q.choose(q.answer))
        XCTAssertEqual(q.live.map(\.item), [target])                               // …puts it in the live list
        XCTAssertEqual(q.live.first?.misses, 1)
        var asked = 0, total = 0
        while q.live.contains(where: { $0.item == target }) && total < 200 {
            q.next(); total += 1
            if q.item == target { asked += 1 }
            XCTAssertTrue(q.choose(q.answer))                                       // quick and right
        }
        XCTAssertEqual(asked, NoteQuiz.liveStreak)                                  // out after 2 good answers
        XCTAssertLessThan(total, 25)                                                // and it came back soon
        XCTAssertEqual(q.improved, [target])
        XCTAssertEqual(q.answered, total + 1)
        q.restartRound()
        XCTAssertTrue(q.live.isEmpty && q.improved.isEmpty && q.answered == 0)
    }

    /// Le più lente = slow NOW (last answers over the fast time and 30% over your usual) or missed lately;
    /// an old slow average or an old mistake doesn't keep a note there.
    func testSlowestUsesRecentAnswers() throws {
        let q = quiz()
        q.setLevel(.treble)
        let p = q.pool
        for it in p.prefix(4) { for _ in 0..<3 { q.store.answer(.treble, it, right: true, seconds: 1.5) } }
        q.store.answer(.treble, p[4], right: true, seconds: 30)                     // slow long ago…
        for _ in 0..<3 { q.store.answer(.treble, p[4], right: true, seconds: 1.6) } // …fast now
        q.store.answer(.treble, p[5], right: false, seconds: 2)                     // an old mistake…
        for _ in 0..<3 { q.store.answer(.treble, p[5], right: true, seconds: 1.5) } // …3 rights since
        for _ in 0..<3 { q.store.answer(.treble, p[6], right: true, seconds: 6) }   // slow now
        q.store.answer(.treble, p[7], right: false, seconds: 2)                     // missed lately
        q.store.answer(.treble, p[7], right: true, seconds: 1.2)
        q.store.answer(.treble, p[8], right: false, seconds: 30)                    // missed, nothing right since
        XCTAssertEqual(q.slowest().map(\.item), [p[7], p[8], p[6]])
        XCTAssertNil(q.slowest().first { $0.item == p[8] }?.time)                  // no time shown for the miss
        q.store.answer(.treble, p[8], right: true, seconds: 1.3)
        for _ in 0..<2 { q.store.answer(.treble, p[8], right: true, seconds: 1.3) }
        for _ in 0..<3 { q.store.answer(.treble, p[6], right: true, seconds: 1.4) }
        for _ in 0..<2 { q.store.answer(.treble, p[7], right: true, seconds: 1.2) }
        XCTAssertTrue(q.slowest().isEmpty)                                          // "Le trovi tutte in fretta"
        XCTAssertEqual(q.answeredNotes(.treble), 9)
    }

    /// the treble level asks the lines first, then lines + spaces, then every note; same cards,
    /// so knowing the lines already skips straight on.
    func testStaffLevelsTeachLinesThenSpaces() throws {
        let q = quiz()
        q.setLevel(.treble)
        func asked(_ n: Int = 60) -> Set<Int> {
            var seen = Set<Int>()
            for _ in 0..<n { seen.insert(q.item!.midi); q.next() }
            return seen
        }
        func learn(_ m: Set<Int>) {
            for it in q.pool where m.contains(it.midi) { for _ in 0..<3 { q.store.answer(.treble, it, right: true, seconds: 1) } }
        }
        // the middle line and its neighbours, then outwards, then the spaces the same way
        let steps: [(String, String, Set<Int>)] = [("Righe in mezzo", "Sol Si Re", [67, 71, 74]), ("Tutte le righe", "Mi Fa", [64, 77]),
                                                   ("Spazi in mezzo", "La Do", [69, 72]), ("Tutti gli spazi", "Fa Mi", [65, 76])]
        var sofar = Set<Int>()
        for (title, notes, midi) in steps {
            sofar.formUnion(midi)
            XCTAssertEqual(q.stage?.title, title)
            XCTAssertEqual(q.stage?.notes, notes)
            XCTAssertEqual(asked(), sofar)
            learn(midi)
        }
        XCTAssertNil(q.stage)
        XCTAssertTrue(asked(200).contains(60))                                      // Do centrale (ledger line) now too
        XCTAssertEqual(q.known().total, q.pool.count)                               // "Sai" still counts the whole level
        q.store.answer(.treble, q.pool.first { $0.midi == 71 }!, right: false, seconds: 2)
        XCTAssertEqual(q.stage?.title, "Righe in mezzo")                            // forgot Si: back to that step
    }

    /// An answer after the app left (or a gap with no touch) counts right/wrong but not its time; the round doesn't call it slow.
    func testPausesAreNotSlowness() throws {
        let q = quiz()
        q.setLevel(.treble)
        let it = try XCTUnwrap(q.item)
        for _ in 0..<2 { q.store.answer(.treble, it, right: true, seconds: 2) }
        q.appAway()                                                                 // screen locked mid-question
        XCTAssertTrue(q.choose(q.answer))
        let st = try XCTUnwrap(q.store.stat(.treble, it))
        XCTAssertEqual(st.answers, 3)
        XCTAssertEqual(st.recent, [2, 2])                                           // the pause left no time
        XCTAssertEqual(st.average!, 2, accuracy: 0.001)                             // counted as its usual
        XCTAssertTrue(q.live.isEmpty)                                               // not "slow" in Da rivedere
        q.next()
        XCTAssertTrue(q.choose(q.answer))                                           // the next question is timed again
        XCTAssertEqual(q.store.stat(.treble, q.item!)?.recent?.count ?? 0 > 0, true)
    }

    /// One slow answer of the last 3 doesn't take a note away (2 of 3 under the time); V49 staff = 4 s.
    func testKnownIsGentlerForABeginner() throws {
        let store = QuizStore(url: FileManager.default.temporaryDirectory.appendingPathComponent("quiz-\(UUID()).json"))
        let re = NoteQuiz.Item(midi: 74, clef: .treble, fifths: 0)
        for t in [2.1, 8.5, 1.9] { store.answer(.treble, re, right: true, seconds: t, v49: true) }   // mean 4.2
        XCTAssertTrue(store.isKnown(.treble, re))
        let fa = NoteQuiz.Item(midi: 77, clef: .treble, fifths: 0)
        for t in [6.0, 8.5, 1.9] { store.answer(.treble, fa, right: true, seconds: t, v49: true) }
        XCTAssertFalse(store.isKnown(.treble, fa))                                  // 2 of 3 slow: not yet
    }

    /// A staff step moves on with 3 right in a row and falls back only on a mistake, not on a slow answer.
    func testStepsFallBackOnlyOnMistakes() throws {
        let q = quiz()
        q.setLevel(.treble)
        for m in [67, 71, 74] { for _ in 0..<3 { q.store.answer(.treble, .init(midi: m, clef: .treble, fifths: 0), right: true, seconds: 9) } }
        XCTAssertEqual(q.stage?.title, "Tutte le righe")                            // slow but right: on
        q.store.answer(.treble, .init(midi: 71, clef: .treble, fifths: 0), right: true, seconds: 25)
        XCTAssertEqual(q.stage?.title, "Tutte le righe")                            // a slow answer: stays
        q.store.answer(.treble, .init(midi: 71, clef: .treble, fifths: 0), right: false, seconds: 2)
        XCTAssertEqual(q.stage?.title, "Righe in mezzo")                            // a mistake: back
        XCTAssertEqual(q.staffMarks, [32])                                          // the Sol line in blue (= its key)
    }

    /// A name one step away on the staff gets a hint that says where it is, never the answer.
    func testOneStepHintOnTheStaff() throws {
        let q = quiz()
        for m in [67, 71, 74, 64, 77] { for _ in 0..<3 { q.store.answer(.treble, .init(midi: m, clef: .treble, fifths: 0), right: true, seconds: 1) } }
        q.setLevel(.treble)
        var n = 0
        while q.item?.midi != 69 && n < 300 { q.next(); n += 1 }                    // La (2nd space)
        XCTAssertEqual(q.item?.midi, 69)
        XCTAssertFalse(q.choose("Sol"))
        XCTAssertEqual(q.hint?.text, "Non è Sol: 1 passo più su ↑")                 // short: the drawing explains
        XCTAssertEqual(q.hint?.staff, [32])
        XCTAssertEqual(q.geometry, .init(from: 32, to: 33, keys: [67, 69], finger: 2))   // Sol line → La space
        XCTAssertFalse(q.choose("Re"))                                              // not a neighbour: no hint
        XCTAssertNil(q.hint)
        q.choose(q.answer)
        q.next()
        XCTAssertNil(q.hint)
    }

    /// Geometric link staff ↔ keyboard ↔ fingers: after a right answer the
    /// way from the clef's line to the note, step by step = white key by white key, and the finger.
    func testGeometryLinksStaffKeysAndFingers() throws {
        XCTAssertEqual([28, 32, 24, 20, 35].map(Staff.natural), [60, 67, 53, 47, 72])
        XCTAssertEqual([32, 33, 34, 35, 36, 31, 28].map { NoteQuiz.finger($0, clef: .treble) }, [1, 2, 3, 1, 2, 4, 1])
        XCTAssertEqual(NoteQuiz.finger(24, clef: .bass), 2)                         // Fa on the bass line, left hand
        let q = quiz()
        q.setLevel(.treble)
        let it = try XCTUnwrap(q.item)
        XCTAssertNil(q.geometry)                                                    // nothing before the answer
        XCTAssertEqual(q.staffMarks, [32])
        q.choose(q.answer)
        let g = try XCTUnwrap(q.geometry)
        let d = Staff.spell(it.midi, fifths: 0).d
        XCTAssertEqual(g.from, 32)
        XCTAssertEqual(g.to, d)
        XCTAssertEqual(g.keys.count, abs(d - 32) + 1)
        XCTAssertEqual(g.keys.first, 67)
        XCTAssertEqual(g.keys.last, it.midi)
        q.setLevel(.keyboard)
        q.choose(q.answer)
        XCTAssertNil(q.geometry)                                                    // Tastiera: no staff
    }

    /// Active time between touches/keys, AFK gaps left out,
    /// Impara and Brani apart; days in a row; old day records still load.
    func testPracticeTime() throws {
        let store = QuizStore(url: FileManager.default.temporaryDirectory.appendingPathComponent("quiz-\(UUID()).json"))
        let t0 = Date().timeIntervalSince1970
        for s in [0.0, 5, 10, 14] { store.practice(.learn, now: t0 + s) }           // 14 s of answers
        store.practice(.learn, now: t0 + 300)                                       // back after 5 min: not counted
        store.practice(.learn, now: t0 + 303)
        for s in [400.0, 402, 404] { store.practice(.play, now: t0 + s) }
        store.flushPractice(now: t0 + 404)
        let today = try XCTUnwrap(store.history(days: 1).last?.stats)
        XCTAssertEqual(today.learn!, 17, accuracy: 0.001)
        XCTAssertEqual(today.play!, 4, accuracy: 0.001)
        XCTAssertEqual(today.practice, 21, accuracy: 0.001)
        XCTAssertEqual(store.streak(), 1)
        let old = try JSONDecoder().decode(QuizStore.Day.self, from: Data(#"{"right":3,"wrong":1,"seconds":9}"#.utf8))
        XCTAssertNil(old.learn)
        XCTAssertEqual(old.practice, 0)
    }

    func testMissedNotesComeBackMoreOften() throws {
        let q = quiz()
        q.setLevel(.landmarks)
        // answer every landmark right three times → all in box 3, mastery 100%
        for _ in 0..<120 {
            let it = try XCTUnwrap(q.item)
            q.press(it.midi)
            q.next()
        }
        XCTAssertGreaterThan(q.mastery, 0.9)
        let it = try XCTUnwrap(q.item)
        q.press(it.midi + 2)                                                              // wrong → back to box 0
        q.press(it.midi)
        XCTAssertEqual(q.store.box(.landmarks, it), 0)
        XCTAssertLessThan(q.mastery, 1)
    }

    // MARK: hidden hints

    func testNextNoteIsNeverNextToThePrevious() throws {
        let q = quiz()
        for g in NoteQuiz.staffGroups[.treble]! {                                   // the whole level (steps known)
            for m in g.midi { for _ in 0..<3 { q.store.answer(.treble, .init(midi: m, clef: .treble, fifths: 0), right: true, seconds: 1) } }
        }
        q.setLevel(.treble)
        for _ in 0..<200 {
            let a = try XCTUnwrap(q.item)
            q.next()
            let b = try XCTUnwrap(q.item)
            XCTAssertGreaterThanOrEqual(abs(Staff.spell(a.midi, fifths: 0).d - Staff.spell(b.midi, fifths: 0).d), 3)
        }
    }

    func testMissedNoteWaitsThreeQuestions() throws {
        let q = quiz()
        q.setLevel(.all)                                                                  // a big pool (treble = 5 lines first)
        let it = try XCTUnwrap(q.item)
        q.choose("nessuna")                                                               // wrong → box 0, weight 8
        q.choose(q.answer)
        for _ in 0..<3 { q.next(); XCTAssertNotEqual(q.item, it) }
        let t = quiz()
        t.setLevel(.treble)                                                               // 3-note first step: 1 between
        let line = try XCTUnwrap(t.item)
        t.choose("nessuna")
        t.choose(t.answer)
        t.next()
        XCTAssertNotEqual(t.item, line)
    }

    func testKeyboardLightsTheNoteInDifferentOctaves() throws {
        let q = quiz()
        q.setLevel(.keyboard)
        var octaves = Set<Int>()
        for _ in 0..<40 {
            let it = try XCTUnwrap(q.item), m = try XCTUnwrap(q.shown)
            XCTAssertEqual(m % 12, it.midi % 12)
            XCTAssertTrue(q.range.contains(m))
            octaves.insert(m / 12)
            XCTAssertTrue(q.press(m))
            q.next()
        }
        XCTAssertGreaterThan(octaves.count, 1)
    }

    func testChordChoicesHoldTheSameRootsOtherKind() {
        let q = quiz()
        q.setLevel(.chords)
        for _ in 0..<30 {
            let a = q.answer
            XCTAssertTrue(q.choices.contains(a))
            for c in NoteQuiz.confusable(a) { XCTAssertTrue(q.choices.contains(c), "\(a): \(q.choices)") }
            q.next()
        }
        XCTAssertEqual(NoteQuiz.confusable("Do maggiore"), ["Do minore", "La minore"])
        XCTAssertEqual(NoteQuiz.confusable("Do# minore"), ["Do# maggiore", "Mi maggiore"])
    }

    // MARK: guide

    /// Answers right at the first try until the guide leaves `l` (or `limit` questions).
    private func pass(_ q: NoteQuiz, _ l: NoteQuiz.Level, limit: Int = 400) {
        var n = 0
        while q.level == l && n < limit { q.choose(q.answer); q.next(); n += 1 }
    }

    func testGuideStartsAtTheFirstLevelAndMovesOnWhenPassed() throws {
        let q = quiz(guided: true)
        XCTAssertTrue(q.guided)
        XCTAssertEqual(q.level, .keyboard)
        XCTAssertTrue(q.isAhead(.treble))
        pass(q, .keyboard)
        XCTAssertEqual(q.level, .landmarks)                                               // path order
        XCTAssertEqual(q.frontier, .landmarks)
        XCTAssertTrue(q.guideNote?.contains("superato") == true, q.guideNote ?? "nil")
        XCTAssertFalse(q.isAhead(.landmarks))
        XCTAssertTrue(q.isAhead(.bass))
    }

    func testManyMistakesGoOneLevelBackThenReturn() throws {
        let q = quiz(guided: true)
        pass(q, .keyboard)
        for _ in 0..<10 { q.choose("nessuna"); q.choose(q.answer); q.next() }
        XCTAssertEqual(q.level, .keyboard)
        XCTAssertTrue(q.guideNote?.contains("sbagli tante") == true, q.guideNote ?? "nil")
        pass(q, .keyboard, limit: 20)
        XCTAssertEqual(q.level, .landmarks)                                               // back after 8 right
    }

    func testChoosingALevelTurnsTheGuideOffUntilAskedBack() {
        let q = quiz(guided: true)
        q.pick(.chords)
        XCTAssertFalse(q.guided)
        XCTAssertEqual(q.level, .chords)
        XCTAssertTrue(q.guideNote?.contains("dopo") == true)
        for _ in 0..<5 { q.choose(q.answer); q.next() }
        XCTAssertEqual(q.level, .chords)                                                  // your choice stays
        q.followGuide()
        XCTAssertTrue(q.guided)
        XCTAssertEqual(q.level, .keyboard)
    }

    func testAllLevelTeachesKeySignaturesWithoutGivingThemAway() {
        let q = quiz()
        q.setLevel(.all)
        let g = q.pool.filter { $0.fifths == 1 }
        XCTAssertTrue(g.contains { $0.midi == 66 && $0.clef == .treble })                // Fa♯ in Sol maggiore
        XCTAssertTrue(g.contains { Staff.name($0.midi, fifths: 1).count <= 3 && !Staff.name($0.midi, fifths: 1).hasSuffix("#") })
        XCTAssertTrue(q.pool.contains { $0.fifths == -2 && Staff.name($0.midi, fifths: -2) == "Mib" })
    }
}
