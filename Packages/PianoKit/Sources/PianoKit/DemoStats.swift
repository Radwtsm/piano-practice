import Foundation

#if DEBUG
/// Fictitious statistics for looking at the screens in the simulator (rule: never real data in a test):
/// `-pt.demoStats YES` at launch → a throw-away store in tmp, filled with the same answers every time (14 days,
/// levels 1-3, a few slow and confused notes). Simulator only: a device always uses the real store.
@MainActor public enum DemoStats {
    public static var enabled: Bool {
        #if targetEnvironment(simulator)
        return UserDefaults.standard.bool(forKey: "pt.demoStats")
        #else
        return false
        #endif
    }

    /// `-pt.open stats|path`: that sheet opens at launch (screenshots without taps). Simulator only.
    public static var open: String? {
        #if targetEnvironment(simulator)
        return UserDefaults.standard.string(forKey: "pt.open")
        #else
        return nil
        #endif
    }

    /// `-pt.scrollTo confusions|levels`: the statistics open scrolled to that tile.
    public static var scrollTo: String? {
        #if targetEnvironment(simulator)
        return UserDefaults.standard.string(forKey: "pt.scrollTo")
        #else
        return nil
        #endif
    }

    public static func store(now: Date = Date()) -> QuizStore {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("piano-demo-quiz.json")
        try? FileManager.default.removeItem(at: url)
        let store = QuizStore(url: url)
        let cal = Calendar.current
        for (li, level) in [NoteQuiz.Level.keyboard, .landmarks, .treble].enumerated() {
            let items = NoteQuiz.pool(for: level, pieces: [])
            for day in 0..<14 where (day + li) % 4 != 3 {                   // some days off
                let date = cal.date(byAdding: .day, value: -day, to: now) ?? now
                for (i, it) in items.enumerated() where (i + day) % (li + 2) == 0 {
                    let slow = i % 5 == 0, wrong = (i + day) % 7 == 0
                    store.answer(level, it, right: !wrong, seconds: (slow ? 4.2 : 1.6) + Double(day % 3) * 0.3 + Double(li) * 0.4,
                                 date: date)
                    if wrong { store.confuse(level, it, with: Staff.name(items[(i + 1) % items.count].midi, fifths: it.fifths)) }
                }
            }
        }
        return store
    }
}
#endif
