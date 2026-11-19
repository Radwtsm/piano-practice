import XCTest
@testable import PianoKit

/// Practice logic on the bundled piece (Ode to Joy) (no sound loaded: notes are silent, the steps still work).
@MainActor
final class TrainerTests: XCTestCase {
    private func trainer() throws -> Trainer {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "Fixtures/ode-to-joy.musicxml", withExtension: nil))
        let t = Trainer(sound: Sampler())
        t.stats = StatsStore(url: FileManager.default.temporaryDirectory.appendingPathComponent("stats-\(UUID()).json"))
        UserDefaults.standard.removeObject(forKey: "pt:test.musicxml:a")
        UserDefaults.standard.removeObject(forKey: "pt:test.musicxml:b")
        UserDefaults.standard.removeObject(forKey: "pt:test.musicxml:bpm")
        t.open(name: "test.musicxml", data: try Data(contentsOf: url), )
        t.setHands(.both)
        return t
    }

    private func settle() {
        let e = expectation(description: "step")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { e.fulfill() }
        wait(for: [e], timeout: 1)
    }

    /// Piano opens in Suona libero with no piece; the wheel/arrows do nothing until one is opened.
    func testStartsFreeWithoutPiece() {
        let t = Trainer(sound: Sampler())
        XCTAssertEqual(t.mode, .free)
        XCTAssertNil(t.piece)
        t.go(1)
        t.endFree()
        XCTAssertEqual(t.mode, .free)
    }

    func testChordNeedsAllNotesHeldTogether() throws {
        let t = try trainer()
        let need = t.stepNotes.map(\.n)
        XCTAssertGreaterThan(need.count, 1)
        t.noteOn(need[0])
        t.noteOff(need[0])                      // let go before the chord was complete
        for n in need.dropFirst() { t.noteOn(n) }
        settle()
        XCTAssertEqual(t.stepIdx, 0)
        XCTAssertEqual(t.missing.map(\.n), [need[0]])
        t.noteOn(need[0])
        settle()
        XCTAssertEqual(t.stepIdx, 1)
    }

    /// Bars only. First time = the first 4; "avanti" = the next ones, as many.
    func testWrongKeyAndRangeEnd() throws {
        let t = try trainer()
        t.noteOn(20)
        XCTAssertTrue(t.wrongHeld.contains(20))
        t.noteOff(20)
        for _ in t.steps { t.go(1) }
        XCTAssertTrue(t.finished)
        XCTAssertEqual(t.rangeName, "Battute 1–4")
        XCTAssertEqual(t.nextLessonName, "Battute 5–8")
        t.noteOn(62)                            // the tail of the last chord: still finished
        XCTAssertTrue(t.finished)
        Trainer.finishGrace = 0
        defer { Trainer.finishGrace = 0.8 }
        t.noteOn(48)                            // below middle C = redo
        XCTAssertFalse(t.finished)
        XCTAssertEqual(t.range.a, 1)
        XCTAssertEqual(t.stepIdx, 0)
        for _ in t.steps { t.go(1) }
        t.noteOn(60)                            // middle C and up = the next bars
        XCTAssertEqual(t.range.a, 5)
        XCTAssertEqual(t.range.b, 8)
        XCTAssertFalse(t.finished)
    }

    func testEndOfPieceNeverRestartsByItself() throws {
        let t = try trainer()
        Trainer.finishGrace = 0
        defer { Trainer.finishGrace = 0.8 }
        t.selectRange(14, 17)                   // the last bars of the piece
        for _ in t.steps { t.go(1) }
        XCTAssertTrue(t.finished)
        XCTAssertNil(t.nextLessonName)
        t.noteOn(60)                            // nothing after: the right side does nothing
        XCTAssertTrue(t.finished)
        t.noteOn(48)                            // the left side redoes it
        XCTAssertFalse(t.finished)
        XCTAssertEqual(t.stepIdx, 0)
    }

    func testPadsAndWheel() throws {
        let t = try trainer()
        t.midi(0x99, 42, 100)                   // pad 7 = cycle hands
        XCTAssertEqual(t.hands, .right)
        t.midi(0xE0, 0, 0x7f)                   // wheel up = one step forward
        XCTAssertEqual(t.stepIdx, 1)
        t.midi(0xE0, 0, 0x7f)                   // not re-armed until it comes back to the centre
        XCTAssertEqual(t.stepIdx, 1)
    }

    func testRoundStatsAndDrill() throws {
        let t = try trainer()
        let wrongBar = t.stepNotes.first!.b
        t.noteOn(20)                            // a wrong key in the first bar
        t.noteOff(20)
        while !t.finished {
            let need = t.stepNotes.map(\.n)
            for n in need { t.noteOn(n) }
            settle()
            for n in need { t.noteOff(n) }
        }
        let r = try XCTUnwrap(t.lastRound)
        XCTAssertEqual(r.bars[wrongBar]?.wrong, 1)
        XCTAssertEqual(r.weakest(), [wrongBar])
        XCTAssertEqual(t.stats.history(piece: "test.musicxml").first?.bars[wrongBar]?.rounds, 1)
        t.practiceWeak()
        XCTAssertTrue(t.drilling)
        XCTAssertTrue(t.loop)
        XCTAssertEqual(t.range.a, wrongBar)
    }

    func testDrillRangeTakesWeakNeighbours() {
        func stat(_ w: Int) -> BarStat { var b = BarStat(); b.wrong = w; return b }
        XCTAssertEqual(Trainer.drillRange([5: stat(4), 6: stat(1), 9: stat(2)]).map { [$0.a, $0.b] }, [5, 6])
        XCTAssertEqual(Trainer.drillRange([3: stat(1), 4: stat(3), 5: stat(2), 6: stat(2)]).map { [$0.a, $0.b] }, [4, 6])
        XCTAssertNil(Trainer.drillRange([:]))
    }
}
