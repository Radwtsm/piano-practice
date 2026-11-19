import XCTest
@testable import PianoKit

/// Percorso: tappe, generated sight-reading melodies, the session's sight score.
@MainActor
final class PathTests: XCTestCase {
    private func rng(_ seed: UInt64 = 7) -> () -> Double {
        var x = seed
        return { x = x &* 6364136223846793005 &+ 1442695040888963407; return Double(x >> 11) / Double(1 << 53) }
    }

    private func store() -> QuizStore { QuizStore(url: FileManager.default.temporaryDirectory.appendingPathComponent("p-\(UUID()).json")) }

    func testMelodiesFitTheirTappa() {
        let r = rng()
        for t in PathPlan.tappe {
            for _ in 0..<50 {
                let m = t.sight.melody(r)
                XCTAssertEqual(m.beats.reduce(0, +), 16, "4 bars of 4/4")
                XCTAssertEqual(m.notes.count, m.beats.count)
                XCTAssertEqual(m.notes.first, m.notes.last, "starts and ends on the key's note")
                XCTAssertTrue(t.sight.halves || m.beats.allSatisfy { $0 == 1 })
                let range = (m.notes.min()!, m.notes.max()!)
                XCTAssertLessThanOrEqual(range.1 - range.0, 8, "one five-finger position")
            }
        }
        for _ in 0..<40 {                                                       // tappa 5: Sol maggiore or Fa maggiore
            let g = PathPlan.tappe[4].sight.melody(r)
            if g.fifths == 1 { XCTAssertEqual(g.notes.first, 67); XCTAssertFalse(g.notes.contains(65), "Fa♯ in Sol maggiore") }
            else { XCTAssertEqual(g.fifths, -1); XCTAssertEqual(g.notes.first, 65); XCTAssertFalse(g.notes.contains(71), "Si♭ in Fa maggiore") }
        }
    }

    func testReadingAMelodyScoresTheTappa() {
        let st = store()
        let s = SightSession(tappa: 1, spec: PathPlan.tappe[0].sight, store: st, random: rng())
        XCTAssertEqual(s.choices, ["Do", "Re", "Mi", "Fa", "Sol", "La", "Si"])
        XCTAssertFalse(s.choose(s.answer == "Do" ? "Re" : "Do"))              // one mistake on the first note
        while !s.finished { XCTAssertTrue(s.choose(s.answer)) }
        XCTAssertEqual(s.rightFirst, s.melody.notes.count - 1)
        XCTAssertEqual(st.sight(tappa: 1).melodies, 1)
        XCTAssertEqual(st.sight(tappa: 1).wrong, 1)
        s.next()
        XCTAssertFalse(s.finished)
        XCTAssertTrue(s.press(s.current! + 12))                               // V49: any octave
    }

    func testCurrentTappaAndSightGoal() {
        let st = store()
        UserDefaults.standard.set(false, forKey: "pt:quiz.guided")
        let q = NoteQuiz(store: st)
        q.use(pieces: [])
        let path = PathProgress(quiz: q)
        XCTAssertEqual(path.current.number, 1)
        XCTAssertFalse(path.sightPassed(PathPlan.tappe[0]))
        for _ in 0..<Tappa.melodiesToPass { st.recordSight(tappa: 1, right: 9, wrong: 1, seconds: 20) }
        XCTAssertTrue(path.sightPassed(PathPlan.tappe[0]))
        XCTAssertEqual(path.current.number, 1, "the quiz levels are still to learn")
        XCTAssertTrue(path.isAhead(PathPlan.tappe[1]))
    }
}
