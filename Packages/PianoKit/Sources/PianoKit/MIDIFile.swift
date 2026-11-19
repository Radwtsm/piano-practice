import Foundation
#if canImport(Compression)
import Compression
#endif

/// Standard MIDI file → `Piece` (falling notes only, no sheet): Track 1 = right hand,
/// track 2 = left; a single track is split at middle C. Channel 10 (drums) is ignored.
enum MIDIFile {
    static func piece(data: Data, name: String) throws -> Piece {
        let u = [UInt8](data)
        func u16(_ i: Int) -> Int { Int(u[i]) << 8 | Int(u[i + 1]) }
        func u32(_ i: Int) -> Int { u16(i) << 16 | u16(i + 2) }
        func tag(_ i: Int) -> String { i + 4 <= u.count ? String(decoding: u[i..<i + 4], as: UTF8.self) : "" }
        guard tag(0) == "MThd", u.count >= 14 else { throw PieceError.unreadable("Non è un file MIDI.") }
        let ntr = u16(10), tpq = u16(12)
        guard tpq & 0x8000 == 0 else { throw PieceError.unreadable("MIDI con tempo SMPTE: non supportato.") }
        var p = 8 + u32(4)
        var tracks: [[(s: Double, d: Double, n: Int)]] = []
        var tempo = 0, beats = 4, beatType = 4
        for _ in 0..<ntr where p < u.count {
            guard tag(p) == "MTrk" else { break }
            let end = min(p + 8 + u32(p + 4), u.count)
            var q = p + 8, tick = 0, run: UInt8 = 0
            var on: [Int: Int] = [:]
            var notes: [(s: Double, d: Double, n: Int)] = []
            func vlq() -> Int {
                var v = 0, b: UInt8
                repeat { b = q < u.count ? u[q] : 0; q += 1; v = v << 7 | Int(b & 0x7f) } while b & 0x80 != 0
                return v
            }
            while q < end {
                tick += vlq()
                var st = u[q]
                if st & 0x80 != 0 { q += 1 } else { st = run }
                if st == 0xff {
                    let type = u[q]; q += 1
                    let l = vlq()
                    if type == 0x51, tempo == 0, q + 2 < u.count {
                        tempo = Int((60_000_000.0 / Double(Int(u[q]) << 16 | Int(u[q + 1]) << 8 | Int(u[q + 2]))).rounded())
                    }
                    if type == 0x58, tick == 0, q + 1 < u.count { beats = Int(u[q]); beatType = 1 << Int(u[q + 1]) }
                    q += l
                    continue
                }
                if st == 0xf0 || st == 0xf7 { q += vlq(); continue }
                run = st
                let cmd = st & 0xf0, ch = st & 0x0f
                let a = Int(u[q]); q += 1
                var b = 0
                if cmd != 0xc0 && cmd != 0xd0 { b = Int(u[q]); q += 1 }
                if ch == 9 { continue }
                if cmd == 0x90 && b > 0 {
                    on[a] = tick
                } else if cmd == 0x80 || (cmd == 0x90 && b == 0), let started = on[a] {
                    notes.append((Double(started) / Double(tpq), Double(tick - started) / Double(tpq), a))
                    on[a] = nil
                }
            }
            if !notes.isEmpty { tracks.append(notes) }
            p = end
        }
        guard !tracks.isEmpty else { throw PieceError.unreadable("Il file MIDI non contiene note.") }
        var piece = Piece(title: Piece.baseName(name))
        piece.tempo = Double(tempo == 0 ? 100 : tempo)
        for (i, notes) in tracks.enumerated() {
            for e in notes {
                let hand: Piece.Hand = tracks.count >= 2 ? (i == 0 ? .right : .left) : (e.n >= 60 ? .right : .left)
                piece.events.append(.init(s: Piece.snap(e.s), d: Piece.snap(max(e.d, 0.05)), n: e.n, h: hand,
                                          f: "", staccato: false, b: 0))
            }
        }
        let barLen = Double(beats) * 4 / Double(beatType)
        let last = piece.events.map { $0.s + $0.d }.max() ?? 0
        var s = 0.0, i = 0
        while s < last {
            piece.bars.append(.init(num: i + 1, label: String(i + 1), start: s, len: barLen, beats: beats, beatType: beatType))
            i += 1
            s += barLen
        }
        piece.finish()
        return piece
    }
}

/// `.mxl` = a zip with the score inside : central directory → `META-INF/container.xml`
/// rootfile (else the first .xml/.musicxml), stored or deflated.
enum MXL {
    static func rootScore(_ data: Data) throws -> String {
        let u = [UInt8](data)
        func u16(_ i: Int) -> Int { Int(u[i]) | Int(u[i + 1]) << 8 }
        func u32(_ i: Int) -> Int { u16(i) | u16(i + 2) << 16 }
        let broken = PieceError.unreadable("File .mxl rovinato.")
        guard u.count >= 22, let eocd = stride(from: u.count - 22, through: 0, by: -1).first(where: { u32($0) == 0x06054b50 })
        else { throw broken }
        var files: [String: (method: Int, csize: Int, off: Int)] = [:]
        var p = u32(eocd + 16)
        for _ in 0..<u16(eocd + 10) {
            guard p + 46 <= u.count else { throw broken }
            let nl = u16(p + 28), el = u16(p + 30), cl = u16(p + 32)
            let name = String(decoding: u[p + 46..<min(p + 46 + nl, u.count)], as: UTF8.self)
            files[name] = (u16(p + 10), u32(p + 20), u32(p + 42))
            p += 46 + nl + el + cl
        }
        func read(_ name: String) throws -> String {
            guard let f = files[name], f.off + 30 <= u.count else { throw broken }
            let start = f.off + 30 + u16(f.off + 26) + u16(f.off + 28)
            guard start + f.csize <= u.count else { throw broken }
            let raw = Data(u[start..<start + f.csize])
            if f.method == 0 { return String(decoding: raw, as: UTF8.self) }
            return String(decoding: try inflate(raw), as: UTF8.self)
        }
        var root = files.keys.sorted().first {
            !$0.hasPrefix("META-INF") && ($0.lowercased().hasSuffix(".xml") || $0.lowercased().hasSuffix(".musicxml"))
        }
        if files["META-INF/container.xml"] != nil,
           let container = try? read("META-INF/container.xml"),
           let range = container.range(of: #"full-path="([^"]+)""#, options: .regularExpression) {
            let path = String(container[range].dropFirst("full-path=\"".count).dropLast())
            if files[path] != nil { root = path }
        }
        guard let root else { throw PieceError.unreadable("Nel file .mxl non c'è lo spartito.") }
        return try read(root)
    }

    /// Raw deflate (zip method 8) with Apple's Compression (`COMPRESSION_ZLIB` = raw deflate, no header).
    private static func inflate(_ data: Data) throws -> Data {
        var out = Data()
        let filter = try OutputFilter(.decompress, using: .zlib) { out.append($0 ?? Data()) }
        try filter.write(data)
        try filter.finalize()
        return out
    }
}
