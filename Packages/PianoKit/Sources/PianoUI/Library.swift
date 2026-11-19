import Foundation
import Observation
import PianoKit

/// Pieces the app can open: the ones shipped in the app (`pieces/`) plus the user's folder (iPad: the app's
/// Documents, visible in File › Sul mio iPad › Piano; Mac: ~/Music/Piano).
@MainActor @Observable
public final class Library {
    public struct Item: Identifiable, Hashable {
        public let url: URL
        public let title: String
        public var id: URL { url }
    }

    public private(set) var items: [Item] = []
    static let types = ["musicxml", "xml", "mxl", "mid", "midi"]

    public init() {}

    public static var userFolder: URL {
        #if os(macOS)
        let dir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Music/Piano")
        #else
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        #endif
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    public func reload() {
        var out: [Item] = []
        var seen = Set<String>()
        for dir in [Self.userFolder, Bundle.main.resourceURL?.appendingPathComponent("pieces")].compactMap({ $0 }) {
            let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
            for f in files.sorted(by: { $0.lastPathComponent < $1.lastPathComponent })
            where Self.types.contains(f.pathExtension.lowercased()) {
                guard seen.insert(f.lastPathComponent).inserted else { continue }   // own copy wins over the shipped one
                let title = (try? Data(contentsOf: f)).flatMap { try? Piece.load(name: f.lastPathComponent, data: $0).title }
                out.append(Item(url: f, title: title ?? f.deletingPathExtension().lastPathComponent))
            }
        }
        items = out
    }
}
