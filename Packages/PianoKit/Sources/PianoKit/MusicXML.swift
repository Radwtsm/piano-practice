import Foundation

/// A tiny element tree built with `XMLParser`, so the reader below can walk the DOM the way the earlier implementation did
/// (iOS has no `XMLDocument`).
final class XMLNode {
    let tag: String
    let attributes: [String: String]
    var children: [XMLNode] = []
    var text = ""

    init(tag: String, attributes: [String: String]) {
        self.tag = tag
        self.attributes = attributes
    }

    func kid(_ tag: String) -> XMLNode? { children.first { $0.tag == tag } }
    func kids(_ tag: String) -> [XMLNode] { children.filter { $0.tag == tag } }
    var trimmed: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }
    func num(_ tag: String, _ fallback: Double = 0) -> Double { kid(tag).flatMap { Double($0.trimmed) } ?? fallback }

    /// Every descendant with this tag (document order), like `querySelectorAll`.
    func descendants(_ tag: String) -> [XMLNode] {
        children.flatMap { ($0.tag == tag ? [$0] : []) + $0.descendants(tag) }
    }

    func first(_ path: [String]) -> XMLNode? {
        guard let head = path.first else { return self }
        for node in descendants(head) { if let found = node.first(Array(path.dropFirst())) { return found } }
        return nil
    }

    static func parse(_ text: String) -> XMLNode? {
        let builder = Builder()
        let parser = XMLParser(data: Data(text.utf8))
        parser.delegate = builder
        guard parser.parse() else { return nil }
        return builder.root
    }

    private final class Builder: NSObject, XMLParserDelegate {
        var root: XMLNode?
        var stack: [XMLNode] = []

        func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?,
                    attributes: [String: String] = [:]) {
            let node = XMLNode(tag: name, attributes: attributes)
            if let parent = stack.last { parent.children.append(node) } else { root = node }
            stack.append(node)
        }

        func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
            stack.removeLast()
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) { stack.last?.text += string }
    }
}

/// MusicXML (partwise) → `Piece`, same walk as the earlier implementation.
enum MusicXML {
    private static let steps: [String: Int] = ["C": 0, "D": 2, "E": 4, "F": 5, "G": 7, "A": 9, "B": 11]

    static func piece(text: String, name: String) throws -> Piece {
        guard let doc = XMLNode.parse(text) else { throw PieceError.unreadable("Il file MusicXML non si legge (XML rotto).") }
        guard doc.tag == "score-partwise" else {
            throw PieceError.unreadable("Serve un MusicXML \"partwise\" (quello che esporta MuseScore).")
        }
        let work = doc.first(["work", "work-title"])?.trimmed.nonEmpty
        let movement = doc.first(["movement-title"])?.trimmed.nonEmpty
        var piece = Piece(title: work ?? movement ?? Piece.baseName(name))
        piece.subtitle = movement != nil && work != nil ? movement! : ""
        piece.composer = doc.descendants("creator").first { $0.attributes["type"] == "composer" }?.trimmed ?? ""
        piece.xml = text

        let parts = doc.kids("part")
        let twoParts = parts.count >= 2
        var ties: [String: Int] = [:]  // "hand:midi" → index of the event waiting for its tie stop
        for (pi, part) in parts.prefix(2).enumerated() {
            var div = 1.0, start = 0.0, beats = 4.0, beatType = 4.0, staves = 1.0
            for (mi, meas) in part.kids("measure").enumerated() {
                var pos = 0.0, maxPos = 0.0, lastStart = 0.0
                for el in meas.children {
                    switch el.tag {
                    case "attributes":
                        div = el.num("divisions", div)
                        staves = el.num("staves", staves)
                        if let key = el.kid("key"), piece.fifths == nil { piece.fifths = Int(key.num("fifths")) }
                        if let t = el.kid("time") {
                            beats = t.num("beats", beats)
                            beatType = t.num("beat-type", beatType)
                        }
                    case "direction":
                        if piece.tempo == 0, let s = el.descendants("sound").first(where: { $0.attributes["tempo"] != nil }) {
                            piece.tempo = Double(s.attributes["tempo"]!) ?? 0
                        }
                        if piece.tempo == 0, let pm = el.first(["metronome", "per-minute"]) {
                            piece.tempo = Double(pm.trimmed) ?? 0
                        }
                    case "sound":
                        if piece.tempo == 0, let t = el.attributes["tempo"] { piece.tempo = Double(t) ?? 0 }
                    case "backup":
                        pos -= el.num("duration") / div
                    case "forward":
                        pos += el.num("duration") / div
                        maxPos = max(maxPos, pos)
                    case "note":
                        if el.kid("grace") != nil || el.kid("cue") != nil { continue }
                        let dur = el.num("duration") / div
                        let isChord = el.kid("chord") != nil
                        let s = isChord ? lastStart : pos
                        if !isChord {
                            lastStart = pos
                            pos += dur
                            maxPos = max(maxPos, pos)
                        }
                        guard let p = el.kid("pitch"), el.kid("rest") == nil,
                              let step = p.kid("step").flatMap({ steps[$0.trimmed] }) else { continue }
                        let midi = Int(12 * (p.num("octave") + 1)) + step + Int(p.num("alter"))
                        let staff = el.num("staff", 1)
                        let hand: Piece.Hand = twoParts ? (pi == 0 ? .right : .left)
                            : staves >= 2 ? (staff == 1 ? .right : .left) : (midi >= 60 ? .right : .left)
                        let tieTypes = el.kids("tie").compactMap { $0.attributes["type"] }
                        let key = "\(hand.rawValue):\(midi)"
                        let abs = Piece.snap(start + s)
                        if tieTypes.contains("stop"), let prev = ties[key] {
                            piece.events[prev].d = Piece.snap(abs + dur - piece.events[prev].s)
                            if !tieTypes.contains("start") { ties[key] = nil }
                            continue
                        }
                        let fingering = el.descendants("technical").flatMap { $0.kids("fingering") }
                            .map(\.trimmed).joined()
                        let staccato = el.descendants("articulations")
                            .contains { $0.kid("staccato") != nil || $0.kid("staccatissimo") != nil }
                        piece.events.append(.init(s: abs, d: Piece.snap(dur), n: midi, h: hand, f: fingering,
                                                  staccato: staccato, b: 0))
                        if tieTypes.contains("start") { ties[key] = piece.events.count - 1 }
                    default:
                        break
                    }
                }
                let barLen = maxPos > 0 ? maxPos : beats * 4 / beatType
                if pi == 0 {
                    piece.bars.append(.init(num: mi + 1, label: meas.attributes["number"] ?? String(mi + 1),
                                            start: start, len: barLen, beats: Int(beats), beatType: Int(beatType)))
                }
                start += pi == 0 ? barLen : (piece.bars.indices.contains(mi) ? piece.bars[mi].len : maxPos)
            }
        }
        piece.finish()
        return piece
    }
}

extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}
