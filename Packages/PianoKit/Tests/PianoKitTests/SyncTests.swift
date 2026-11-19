import XCTest
@testable import PianoKit

/// Statistics of several devices add up; the review state of a note follows its latest answer anywhere.
final class SyncTests: XCTestCase {
    private func url(_ n: String) -> URL { FileManager.default.temporaryDirectory.appendingPathComponent("\(n)-\(UUID()).json") }

    func testQuizAnswersOfOtherDevicesAddUp() {
        let it = NoteQuiz.Item(midi: 64, clef: .treble, fifths: 0)
        let ipad = QuizStore(url: url("ipad"))
        for _ in 0..<3 { ipad.answer(.treble, it, right: true, seconds: 1) }
        let phoneURL = url("phone")
        let phone = QuizStore(url: phoneURL)
        phone.setOthers([ipad.mine])
        XCTAssertEqual(phone.stat(.treble, it)?.answers, 3)
        XCTAssertEqual(phone.box(.treble, it), 3)
        XCTAssertTrue(phone.isKnown(.treble, it))                                          // learnt on the iPad
        XCTAssertEqual(phone.today().right, 3)

        phone.answer(.treble, it, right: true, seconds: 1)                                 // goes on from box 3
        XCTAssertEqual(phone.box(.treble, it), 4)
        XCTAssertEqual(phone.stat(.treble, it)?.interval, 1)                               // same day: grows once a day
        XCTAssertEqual(phone.mine.items?.values.first?.answers, 1)                         // only its own answers sent
        XCTAssertEqual(phone.stat(.treble, it)?.answers, 4)

        phone.answer(.treble, it, right: false, seconds: 3)
        XCTAssertEqual(phone.box(.treble, it), 0)                                          // the latest answer wins
        XCTAssertEqual(phone.today().wrong, 1)
        XCTAssertEqual(QuizStore(url: phoneURL).stat(.treble, it)?.answers, 5)            // others kept on disk
    }

    func testOlderAnswerElsewhereDoesNotUndoANewerOne() {
        let it = NoteQuiz.Item(midi: 60, clef: .bass, fifths: 0)
        let mac = QuizStore(url: url("mac"))
        mac.answer(.bass, it, right: false, seconds: 2, date: Date(timeIntervalSinceNow: -3600))
        let phone = QuizStore(url: url("phone"))
        phone.answer(.bass, it, right: true, seconds: 1)
        phone.setOthers([mac.mine])
        XCTAssertEqual(phone.box(.bass, it), 1)
        XCTAssertEqual(phone.stat(.bass, it)?.wrong, 1)
    }

    func testPieceRoundsOfOtherDevicesAddUp() {
        var r = Round()
        r.bars[2] = { var b = BarStat(); b.wrong = 2; b.rounds = 1; return b }()
        let ipad = StatsStore(url: url("s-ipad"))
        ipad.record(piece: "inno.musicxml", round: r)
        let mac = StatsStore(url: url("s-mac"))
        mac.record(piece: "inno.musicxml", round: r)
        mac.setOthers([ipad.data])
        XCTAssertEqual(mac.recent(piece: "inno.musicxml")[2]?.wrong, 4)
        XCTAssertEqual(mac.data["inno.musicxml"]?.values.first?[2]?.wrong, 2)              // its own stay its own
    }
}
