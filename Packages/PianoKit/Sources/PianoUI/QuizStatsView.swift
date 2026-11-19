import DesignKit
import PianoKit
import SwiftUI

/// Statistiche (statistics) of Impara: per-exercise stats, the time taken to find
/// a note, so the slowest can be trained: today, the last 14 days, every level, and the current level's
/// slowest notes with "Allenati su queste" (the quiz then asks only those).
/// The Impara tab of Statistiche (`StatsHub`).
struct QuizStatsView: View {
    let quiz: NoteQuiz
    @Environment(\.pianoScale) private var s
    @Environment(\.dismiss) private var dismiss
    /// The level "Le più lente" shows (the Tastiera's slow notes would vanish once the path moved on to level 2): nil = the current level, or the level with most notes answered when the current one has few.
    @State private var slowLevel: NoteQuiz.Level?
    /// Schermo / V49 (the two are judged apart); the choice shows once the level has V49 answers.
    @State private var v49Chosen = false
    private var v49: Bool { v49Chosen && quiz.hasV49(shownSlowLevel) }

    var body: some View {
        let c = 1 + (s - 1) * 0.4
        // dashboard tiles
        ScrollViewReader { proxy in
        ScrollView {
            ViewThatFits(in: .horizontal) {
                // iPad, Mac: the four numbers in a row, then two columns
                VStack(spacing: 12) {
                    TileRow { answersTile; rightTile; timeTile; knownTile }
                    practiceTile
                    TileRow { days(c); levels(c) }
                    TileRow { slowest(c); confusions(c) }
                }
                .frame(minWidth: 600)
                // iPhone: numbers in pairs, then one column
                VStack(spacing: 12) {
                    TileRow { answersTile; rightTile }
                    TileRow { timeTile; knownTile }
                    practiceTile
                    days(c)
                    slowest(c)
                    confusions(c).id("confusions")
                    levels(c).id("levels")
                }
            }
        }
        #if DEBUG
        .onAppear { if let id = DemoStats.scrollTo { proxy.scrollTo(id, anchor: .top) } }   // screenshots
        #endif
        }
    }

    private func section<Content: View>(_ title: String, _ icon: String, _ c: CGFloat,
                                        @ViewBuilder _ content: () -> Content) -> some View {
        DashboardTile(title: title, icon: icon) {
            VStack(alignment: .leading, spacing: 8) { content() }
        }
    }

    private static func seconds(_ v: Double) -> String { v.formatted(.number.precision(.fractionLength(1))) + " s" }

    // MARK: today's numbers

    private var todayStats: (n: Int, right: Int, seconds: Double) {
        let d = quiz.store.today()
        return (d.right + d.wrong, d.right, d.seconds)
    }

    private var answersTile: some View {
        DashboardTile(title: "Oggi", icon: "checkmark.circle") {
            BigValue(text: "\(todayStats.n)", caption: todayStats.n == 1 ? "risposta" : "risposte")
        }
    }

    private var rightTile: some View {
        let t = todayStats, pct = t.n == 0 ? nil : Int((Double(t.right) / Double(t.n) * 100).rounded())
        return DashboardTile(title: "Giuste", icon: "target") {
            BigValue(text: pct.map { "\($0)%" } ?? "–", tint: pct.map { $0 >= 80 ? Theme.ok : nil } ?? nil)
            Text("al primo colpo").font(.footnote).foregroundStyle(Theme.mute)
        }
    }

    /// Seconds per note today, and its line over the last 14 days (lower = faster).
    private var timeTile: some View {
        let t = todayStats
        let points = quiz.store.history(days: 14).compactMap { d -> (Date, Double)? in
            let n = d.stats.right + d.stats.wrong
            return n == 0 ? nil : (d.day, d.stats.seconds / Double(n))
        }
        return DashboardTile(title: "Tempo", icon: "stopwatch") {
            BigValue(text: t.n == 0 ? "–" : Self.seconds(t.seconds / Double(t.n)), caption: "a nota")
            Sparkline(points: points)
        }
    }

    /// Active minutes today (Impara + Brani, AFK left out), the
    /// line of the last 14 days and the days in a row.
    private var practiceTile: some View {
        let h = quiz.store.history(days: 14), today = h.last?.stats ?? .init()
        let streak = quiz.store.streak()
        return DashboardTile(title: "Esercizio", icon: "timer") {
            HStack(alignment: .firstTextBaseline) {
                BigValue(text: Self.minutes(today.practice), caption: "oggi")
                Spacer(minLength: 8)
                if streak > 1 {
                    Label("\(streak) giorni di fila", systemImage: "flame.fill")
                        .font(.subheadline.weight(.semibold)).foregroundStyle(AppStyle.warnText).lineLimit(1)
                }
            }
            Sparkline(points: h.map { ($0.day, $0.stats.practice / 60) })
            Text("Impara \(Self.minutes(today.learn ?? 0)) · Brani \(Self.minutes(today.play ?? 0))")
                .font(.footnote).foregroundStyle(Theme.mute)
        }
    }

    private static func minutes(_ s: Double) -> String {
        s < 60 ? (s < 1 ? "0 min" : "<1 min") : s < 3600 ? "\(Int(s / 60)) min" : "\(Int(s / 3600)) h \(Int(s / 60) % 60) min"
    }

    private var knownTile: some View {
        let k = quiz.known(quiz.level)
        return DashboardTile(title: "Sai", icon: "graduationcap") {
            BigValue(text: "\(k.known)/\(k.total)")
            ProgressView(value: Double(k.known), total: Double(max(k.total, 1))).tint(Theme.ok)
            Text(quiz.level.title).font(.footnote).foregroundStyle(Theme.mute).lineLimit(2)
        }
    }

    /// One bar per day: height = answers, green part = right at the first try.
    private func days(_ c: CGFloat) -> some View {
        let h = quiz.store.history(days: 14)
        let top = max(1, h.map { $0.stats.right + $0.stats.wrong }.max() ?? 1)
        return section("Ultimi 14 giorni", "chart.bar.fill", c) {
            HStack(alignment: .bottom, spacing: 4) {
                ForEach(h, id: \.day) { d in
                    let n = d.stats.right + d.stats.wrong, bar = 90 * c
                    VStack(spacing: 4) {
                        VStack(spacing: 0) {
                            Rectangle().fill(Theme.bad.opacity(0.8)).frame(height: bar * CGFloat(d.stats.wrong) / CGFloat(top))
                            Rectangle().fill(Theme.ok).frame(height: bar * CGFloat(d.stats.right) / CGFloat(top))
                        }
                        .frame(height: bar, alignment: .bottom)
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                        Text(d.day.formatted(.dateTime.day())).font(.system(size: 10 * c)).foregroundStyle(Theme.mute)
                    }
                    .frame(maxWidth: .infinity)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(d.day.formatted(date: .abbreviated, time: .omitted)): \(n) risposte, \(d.stats.right) giuste")
                }
            }
            Text("Verde = giuste al primo colpo, rosso = con un errore.").font(.system(size: 12 * c)).foregroundStyle(Theme.mute)
        }
    }

    private var answered: [NoteQuiz.Level] { NoteQuiz.Level.allCases.filter { quiz.answeredNotes($0) > 0 || quiz.hasV49($0) } }

    private var shownSlowLevel: NoteQuiz.Level {
        if let l = slowLevel { return l }
        if quiz.answeredNotes(quiz.level) >= 5 { return quiz.level }
        return answered.max { quiz.answeredNotes($0) < quiz.answeredNotes($1) } ?? quiz.level
    }

    private func slowest(_ c: CGFloat) -> some View {
        let l = shownSlowLevel, list = quiz.slowest(8, level: l, v49: v49)
        return section("Le più lente", "tortoise", c) {
            HStack(spacing: 6) {
                Text("Livello").font(.system(size: 15 * c, weight: .bold)).foregroundStyle(Theme.mute)
                if answered.count > 1 {
                    Menu {
                        Picker("Livello", selection: Binding(get: { l }, set: { slowLevel = $0 })) {
                            ForEach(answered) { Text("\($0.number). \($0.title)").tag($0) }
                        }
                    } label: {
                        Label(l.title, systemImage: "chevron.up.chevron.down").labelStyle(.titleAndIcon)
                            .font(.system(size: 15 * c, weight: .bold))
                    }
                    .menuIndicator(.hidden)
                    .accessibilityLabel("Livello: \(l.title)")
                } else {
                    Text(l.title).font(.system(size: 15 * c, weight: .bold)).foregroundStyle(Theme.mute)
                }
            }
            if quiz.hasV49(l) {
                Picker("Risposte", selection: $v49Chosen) {
                    Text("Schermo").tag(false)
                    Text("V49").tag(true)
                }
                .pickerStyle(.segmented)
                if v49 && l == .keyboard {
                    Text("In Tastiera la V49 è allenamento: fa tornare le note sbagliate, ma non conta per \u{201C}Sai\u{201D}.")
                        .font(.system(size: 12 * c)).foregroundStyle(Theme.mute)
                }
            }
            if quiz.answeredNotes(l, v49: v49) == 0 {
                Text("Rispondi a qualche domanda di questo livello: qui vedrai le note che ti prendono più tempo.")
                    .foregroundStyle(Theme.mute)
            } else if list.isEmpty {
                // nothing slow now and no recent mistake = say so, in green (a beginner's good news)
                Label("Le trovi tutte in fretta e senza errori recenti.", systemImage: "checkmark.circle.fill")
                    .font(.system(size: 15 * c, weight: .semibold)).foregroundStyle(Theme.ok)
            } else {
                ForEach(list) { r in
                    HStack(spacing: 12) {
                        if l.asksOnKeyboard {
                            MiniKeyView(midi: r.item.midi).frame(width: 66 * c, height: 44 * c)   // a key, not a staff
                        } else if r.item.chord.isEmpty {
                            StaffView(notes: [r.item.midi], clef: r.item.clef, fifths: r.item.fifths)
                                .frame(width: 66 * c, height: 44 * c)
                        }
                        Text(r.name).font(.system(size: 17 * c, weight: .semibold))
                        Spacer(minLength: 4)
                        VStack(alignment: .trailing, spacing: 1) {
                            Text(r.time.map(Self.seconds) ?? "–").font(.system(size: 17 * c, weight: .semibold)).monospacedDigit()
                            // red only for a mistake in the last answers; older ones are history
                            Text(r.missedLately ? "sbagliata di recente" : "lenta di recente")
                                .font(.system(size: 12 * c)).foregroundStyle(r.missedLately ? Theme.bad : Theme.mute)
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
                // the real count (the button said "5" with only 2 notes listed)
                CapsuleAction(title: list.count >= 5 ? "Allena le 5 note più lente" : "Allena le \(list.count) note più lente",
                              symbol: "scope", primary: true) {
                    if l != quiz.level { quiz.setLevel(l) }
                    quiz.trainSlowest(min(5, list.count), v49: v49)
                    dismiss()
                }
                Text("Il tempo è la media delle ultime 3 risposte giuste (massimo 30 s: una pausa non conta come lentezza). "
                     + "Qui restano solo le note lente adesso o sbagliate di recente; anche nel quiz normale tornano più spesso.")
                    .font(.system(size: 12 * c)).foregroundStyle(Theme.mute)
            }
        }
    }

    /// The wrong names chosen most, on the level "Le più lente" shows.
    @ViewBuilder private func confusions(_ c: CGFloat) -> some View {
        let l = shownSlowLevel, list = quiz.confusions(level: l, v49: v49)
        if !list.isEmpty {
            section("Confusioni · \(l.title)", "arrow.left.arrow.right", c) {
                ForEach(list) { x in
                    HStack(spacing: 12) {
                        Text(x.name).font(.system(size: 17 * c, weight: .semibold))
                        Image(systemName: "arrow.left.arrow.right").foregroundStyle(Theme.mute)
                        Text(x.chose).font(.system(size: 17 * c))
                        Spacer(minLength: 4)
                        Text("\(x.count)×").font(.system(size: 15 * c, weight: .semibold)).monospacedDigit()
                            .foregroundStyle(Theme.bad)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("\(x.name) scambiata per \(x.chose), \(x.count) volte")
                }
                CapsuleAction(title: "Allena queste coppie", symbol: "scope", primary: true) {
                    quiz.trainConfused(level: l, v49: v49)
                    dismiss()
                }
                Text("Le note che hai scambiato al primo colpo e con cosa. L'allenamento chiede solo loro e le note "
                     + "con cui le confondi, finché non tocchi Fine.")
                    .font(.system(size: 12 * c)).foregroundStyle(Theme.mute)
            }
        }
    }

    private func levels(_ c: CGFloat) -> some View {
        section("Livelli", "list.number", c) {
            ForEach(NoteQuiz.Level.allCases) { l in
                let k = quiz.known(l), due = quiz.dueCount(l)
                // name + count on top, the bar, then what's due and the speed: fits a phone without wrapping
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("\(l.number). \(l.title)").font(.system(size: 15 * c, weight: .medium)).lineLimit(1)
                        Spacer(minLength: 4)
                        Text("\(k.known)/\(k.total)").font(.system(size: 15 * c, weight: .semibold)).monospacedDigit()
                    }
                    ProgressView(value: Double(k.known), total: Double(max(k.total, 1)))
                        .tint(quiz.mastery(of: l) >= NoteQuiz.pass ? Theme.ok : Theme.accent)
                    HStack {
                        if due > 0 {
                            Text("\(due) da ripassare").foregroundStyle(AppStyle.warnText)
                        }
                        Spacer(minLength: 4)
                        Text(quiz.averageSeconds(l).map { Self.seconds($0) + " a nota" } ?? "–")
                            .monospacedDigit().foregroundStyle(Theme.mute)
                    }
                    .font(.system(size: 12 * c, weight: .medium))
                }
                .padding(.vertical, 2)
            }
            Text("Sai una nota quando la indovini al primo colpo 3 volte di fila, in media in meno di 3 secondi sulla "
                 + "Tastiera e di 2,5 negli altri livelli. Ogni nota torna a ripasso dopo 1, 2, 4, 8, 16 giorni se la indovini; un errore la riporta a domani.")
                .font(.system(size: 12 * c)).foregroundStyle(Theme.mute)
        }
    }
}

/// One octave with the key lit (Statistiche › Le più lente, level 1: the level is about keys, not the staff).
struct MiniKeyView: View {
    let midi: Int

    var body: some View {
        Canvas { g, size in
            let ww = size.width / 7, pc = midi % 12
            let whites = [0, 2, 4, 5, 7, 9, 11], blacks = [(1, 1), (3, 2), (6, 4), (8, 5), (10, 6)]
            for (i, w) in whites.enumerated() {
                let r = Path(roundedRect: CGRect(x: CGFloat(i) * ww + 0.5, y: 0, width: ww - 1, height: size.height), cornerRadius: 2)
                g.fill(r, with: .color(w == pc ? Theme.warn : Color(hex: 0xf4f2ec)))
            }
            for (b, after) in blacks {
                let r = Path(roundedRect: CGRect(x: CGFloat(after) * ww - ww * 0.3, y: 0, width: ww * 0.6, height: size.height * 0.6), cornerRadius: 2)
                g.fill(r, with: .color(b == pc ? Theme.warn : Color(hex: 0x181a20)))
            }
        }
        .background(Theme.stage)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .accessibilityHidden(true)
    }
}
