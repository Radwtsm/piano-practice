import Foundation

/// A piece as the trainer plays it (port of the earlier implementation). Times are in quarter notes, snapped to a 1/96 grid.
public struct Piece: Equatable {
    public struct Bar: Equatable {
        public var num: Int
        public var label: String
        public var start: Double
        public var len: Double
        public var beats: Int
        public var beatType: Int
    }

    public enum Hand: String { case right = "R", left = "L" }

    public struct Event: Equatable {
        /// Start, duration (quarter notes), MIDI note.
        public var s: Double
        public var d: Double
        public var n: Int
        public var h: Hand
        /// Fingering text ("1", "35"…), empty when the sheet has none.
        public var f: String
        /// `f` was suggested by the app (`Fingering.suggest`), the sheet had none (drawn lighter).
        public var suggested = false
        public var staccato: Bool
        /// Bar number (1-based).
        public var b: Int

        public init(s: Double, d: Double, n: Int, h: Hand, f: String, staccato: Bool, b: Int) {
            self.s = s; self.d = d; self.n = n; self.h = h; self.f = f; self.staccato = staccato; self.b = b
        }
    }

    public var title: String
    public var subtitle = ""
    public var composer = ""
    public var tempo: Double = 0
    public var fifths: Int?
    public var bars: [Bar] = []
    public var events: [Event] = []
    /// The MusicXML text, for the score pane (nil for MIDI pieces).
    public var xml: String?
    public var hasScore: Bool { xml != nil }

    static let grid = 1.0 / 96
    static func snap(_ t: Double) -> Double { (t / grid).rounded() * grid }

    /// Finishes a piece: sort, bar numbers, default tempo and key.
    mutating func finish() {
        events.sort { $0.s != $1.s ? $0.s < $1.s : $0.n < $1.n }
        for i in events.indices {
            var b = 0
            while b + 1 < bars.count, bars[b + 1].start <= events[i].s + 1e-6 { b += 1 }
            events[i].b = bars.indices.contains(b) ? bars[b].num : 1
        }
        if tempo == 0 { tempo = 90 }
        if fifths == nil { fifths = 0 }
    }
}

public enum PieceError: LocalizedError {
    case unreadable(String)
    public var errorDescription: String? {
        switch self { case .unreadable(let why): return why }
    }
}

extension Piece {
    /// `loadPiece`: picks the reader from the file name.
    public static func load(name: String, data: Data) throws -> Piece {
        let lower = name.lowercased()
        if lower.hasSuffix(".mid") || lower.hasSuffix(".midi") { return try MIDIFile.piece(data: data, name: name) }
        let text: String
        if lower.hasSuffix(".mxl") {
            text = try MXL.rootScore(data)
        } else {
            guard let decoded = String(data: data, encoding: .utf8) else {
                throw PieceError.unreadable("Il file MusicXML non si legge (XML rotto).")
            }
            text = decoded
        }
        return try MusicXML.piece(text: text, name: name)
    }

    static func baseName(_ name: String) -> String {
        (name as NSString).deletingPathExtension
    }
}
