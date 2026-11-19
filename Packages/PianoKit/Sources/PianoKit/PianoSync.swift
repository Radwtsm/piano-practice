import Foundation
import Observation
#if canImport(UIKit)
import UIKit
#endif

/// Optional sync of the statistics between iPhone, iPad and Mac through a small self-hosted HTTP service.
/// Each device keeps its own answers (`QuizStore.mine`, `StatsStore.data`) and uploads them whole
/// (`PUT /piano/state/<device>`); it reads the other devices' documents (`GET /piano/state`) and the stores add them up.
/// The server is set with the `PianoSyncServer` key (host:port) in the app's Info.plist or in UserDefaults; when it is
/// empty (the default) the app stays local-only. Offline, a try fails quietly and the next one catches up.
@MainActor @Observable
public final class PianoSync {
    struct Doc: Codable {
        var device: String
        var at: Double
        var quiz: QuizStore.Data_
        var stats: [String: [String: StatsStore.Day]]
    }

    public private(set) var lastSync: Date?
    /// Why the last try failed, in words (nil when it worked).
    public private(set) var problem: String?
    /// Called after the other devices' data arrived (the quiz redraws its counts).
    @ObservationIgnored public var onChange: () -> Void = {}

    /// For Statistiche: "Uguali su iPhone, iPad e Mac · aggiornate alle 12:30".
    public var statusText: String {
        if address.isEmpty { return "Statistiche solo su questo dispositivo" }
        if let p = problem { return "Non sincronizzate ora: " + p }
        guard let t = lastSync else { return "Sincronizzo con gli altri dispositivi…" }
        return "Uguali su iPhone, iPad e Mac · aggiornate alle " + t.formatted(date: .omitted, time: .shortened)
    }

    @ObservationIgnored private let quiz: QuizStore
    @ObservationIgnored private let stats: () -> StatsStore
    @ObservationIgnored private let address: String
    @ObservationIgnored private var running = false

    public init(quiz: QuizStore, stats: @escaping () -> StatsStore, address: String = PianoSync.configuredServer) {
        self.quiz = quiz
        self.stats = stats
        self.address = address
    }

    /// The sync server (host:port) from UserDefaults or Info.plist `PianoSyncServer`; empty = sync off.
    public nonisolated static var configuredServer: String {
        let v = UserDefaults.standard.string(forKey: "PianoSyncServer")
            ?? Bundle.main.object(forInfoDictionaryKey: "PianoSyncServer") as? String
        return v?.trimmingCharacters(in: .whitespaces) ?? ""
    }

    /// Every 3 minutes while the app runs (the first right away).
    public func keepInSync() async {
        guard !address.isEmpty else { return }
        while !Task.isCancelled {
            await sync()
            try? await Task.sleep(for: .seconds(180))
        }
    }

    public func sync() async {
        #if targetEnvironment(simulator)
        // test answers from the simulator must never land in real statistics
        problem = "il simulatore non sincronizza (dati di prova)"
        return
        #endif
        guard !address.isEmpty, !running else { return }
        quiz.flushPractice()                                  // today's practice time goes up with the answers
        running = true
        defer { running = false }
        do {
            let (data, code) = try await send("GET", "/piano/state")
            guard code == 200 else { throw SyncError.http(code) }
            let me = Self.deviceID
            let all = (try JSONSerialization.jsonObject(with: data) as? [String: Any])?["devices"] as? [String: Any] ?? [:]
            let docs = all.compactMap { id, value -> Doc? in
                guard id != me, let d = try? JSONSerialization.data(withJSONObject: value) else { return nil }
                return try? JSONDecoder().decode(Doc.self, from: d)
            }
            let st = stats()
            quiz.setOthers(docs.map(\.quiz))
            st.setOthers(docs.map(\.stats))
            let mine = Doc(device: Self.deviceName, at: Date().timeIntervalSince1970, quiz: quiz.mine, stats: st.data)
            let (_, put) = try await send("PUT", "/piano/state/\(me)", body: JSONEncoder().encode(mine))
            guard put == 200 else { throw SyncError.http(put) }
            lastSync = Date()
            problem = nil
            onChange()
        } catch {
            problem = (error as? SyncError)?.text ?? "il server non risponde"
        }
    }

    enum SyncError: Error {
        case http(Int)
        var text: String { "il server ha risposto \(self.code)" }
        var code: Int { if case .http(let c) = self { return c }; return 0 }
    }

    private func send(_ method: String, _ path: String, body: Data? = nil) async throws -> (Data, Int) {
        guard let url = URL(string: "http://\(address)\(path)") else { throw SyncError.http(0) }
        var r = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 10)
        r.httpMethod = method
        if let body {
            r.httpBody = body
            r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let (data, response) = try await URLSession.shared.data(for: r)
        return (data, (response as? HTTPURLResponse)?.statusCode ?? 0)
    }

    // MARK: this device

    /// A random id per install (the server's file name); never the device's real name or serial.
    static var deviceID: String {
        if let id = UserDefaults.standard.string(forKey: "pt:deviceID") { return id }
        let id = UUID().uuidString
        UserDefaults.standard.set(id, forKey: "pt:deviceID")
        return id
    }

    static var deviceName: String {
        #if os(iOS)
        return UIDevice.current.userInterfaceIdiom == .pad ? "iPad" : "iPhone"
        #else
        return "Mac"
        #endif
    }
}
