import CryptoKit
import XCTest
@testable import PianoKit

/// Snapshot of what the MusicXML reader makes of the bundled piece: one line per header field, bar and event,
/// fingerprinted with SHA-256 (124 lines). The reader was first validated line by line against an earlier JavaScript
/// implementation; this snapshot keeps it from drifting. Ties merge (the last chord lasts 2 + 4 beats).
final class PieceTests: XCTestCase {
    private func fixture(_ name: String) throws -> Data {
        try Data(contentsOf: XCTUnwrap(Bundle.module.url(forResource: "Fixtures/\(name)", withExtension: nil)))
    }

    private func number(_ x: Double) -> String { x == x.rounded() ? String(Int(x)) : String(x) }

    func testOdeToJoySnapshot() throws {
        let piece = try Piece.load(name: "ode-to-joy.musicxml", data: fixture("ode-to-joy.musicxml"))
        var lines = [piece.title, piece.subtitle, piece.composer, number(piece.tempo), String(piece.fifths ?? 0)]
        lines += piece.bars.map { [String($0.num), $0.label, number($0.start), number($0.len), String($0.beats),
                                   String($0.beatType)].joined(separator: "|") }
        lines += piece.events.map { [number($0.s), number($0.d), String($0.n), $0.h.rawValue, $0.f,
                                     $0.staccato ? "1" : "0", String($0.b)].joined(separator: "|") }
        XCTAssertEqual(lines.count, 124)
        XCTAssertEqual(lines.prefix(6), ["Ode to Joy", "Symphony No. 9, 4th movement (easy)", "Ludwig van Beethoven",
                                         "96", "2", "1|1|0|4|4|4"])
        XCTAssertEqual(lines.last, "62|6|69|R|5|0|16")
        let hash = SHA256.hash(data: Data(lines.joined(separator: "\n").utf8)).map { String(format: "%02x", $0) }.joined()
        XCTAssertEqual(hash, "eaedf0b865c60638c6ec1b7b6f6c193db8a37154003ddc7e9ebf9a66e2d82855",
                       "snapshot changed:\n" + lines.joined(separator: "\n"))
    }

    /// Same answers as the earlier implementation.
    func testChordNamesMatchWebApp() {
        let cases: [([Int], String, String)] = [
            ([60, 64, 67], "Do maggiore", "posizione base: in basso c'è la radice Do"),
            ([64, 67, 72], "Do maggiore", "primo rivolto: in basso c'è il Mi, la radice Do è più su"),
            ([57, 61, 64], "La maggiore", "posizione base: in basso c'è la radice La"),
            ([62, 67, 71], "Sol maggiore", "secondo rivolto: in basso c'è il Re, la radice Sol è più su"),
            ([60, 62], "Do + Re", "seconda maggiore"),
            ([55], "Sol", "nota singola"),
        ]
        for (notes, title, detail) in cases {
            XCTAssertEqual(Chords.describe(notes), .init(title: title, detail: detail), "\(notes)")
        }
    }
}
