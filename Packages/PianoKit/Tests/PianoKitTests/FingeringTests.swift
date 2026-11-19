import XCTest
@testable import PianoKit

/// Five-finger positions, suggested fingering, the lesson's starting position, the "Che dito?" level.
@MainActor
final class FingeringTests: XCTestCase {
    private func ev(_ s: Double, _ n: Int, _ h: Piece.Hand, _ f: String = "") -> Piece.Event {
        Piece.Event(s: s, d: 1, n: n, h: h, f: f, staccato: false, b: 1)
    }

    func testPositionsBothHands() {
        XCTAssertEqual(Fingering.position(thumb: 60, hand: .right), [60, 62, 64, 65, 67])            // Do–Sol
        XCTAssertEqual(Fingering.position(thumb: 55, hand: .left), [55, 53, 52, 50, 48])             // Sol3 … Do3
        XCTAssertEqual(Fingering.finger(note: 64, thumb: 60, hand: .right), 3)
        XCTAssertEqual(Fingering.finger(note: 48, thumb: 55, hand: .left), 5)
        XCTAssertNil(Fingering.finger(note: 69, thumb: 60, hand: .right))
        XCTAssertEqual(Fingering.thumb(note: 64, finger: 3, hand: .right), 60)
        XCTAssertEqual(Fingering.thumb(note: 48, finger: 5, hand: .left), 55)
    }

    func testSuggestsFiveFingerPositionsAndMoves() {
        // right: Do Re Mi Fa Sol, then La Si Do (out of the position: the hand moves)
        var e = [60, 62, 64, 65, 67, 69, 71, 72].enumerated().map { ev(Double($0.offset), $0.element, .right) }
        e += [ev(0, 48, .left), ev(1, 52, .left), ev(2, 55, .left)]                               // left: Do Mi Sol
        Fingering.suggest(&e)
        XCTAssertEqual(e.filter { $0.h == .right }.prefix(5).map(\.f), ["1", "2", "3", "4", "5"])
        XCTAssertTrue(e.allSatisfy { $0.suggested && !$0.f.isEmpty })
        XCTAssertEqual(e.filter { $0.h == .right }.suffix(3).map(\.f), ["1", "2", "3"])              // new position on La
        XCTAssertEqual(e.filter { $0.h == .left }.map(\.f), ["5", "3", "1"])
    }

    func testSheetFingersAreNeverReplaced() {
        var e = [ev(0, 60, .right, "2"), ev(1, 62, .right), ev(0, 48, .left)]
        Fingering.suggest(&e)
        XCTAssertEqual(e[0].f, "2")
        XCTAssertEqual(e[1].f, "")                                                                    // that hand has fingers: left alone
        XCTAssertEqual(e[2].f, "5")
        XCTAssertFalse(e[0].suggested)
    }

    func testStartingPosition() {
        let e = [ev(0, 64, .right, "3"), ev(0, 48, .left, "5")]
        XCTAssertEqual(Fingering.start(e), "Destra: pollice sul Do · Sinistra: pollice sul Sol")
        XCTAssertNil(Fingering.start([ev(0, 60, .right)]))
    }
}
