import DesignKit
import PianoKit
import SwiftUI

/// Statistiche: per day, one cell per bar coloured by mistakes per round (green = clean, red = many), the hardest
/// bars of the last 7 days, and "Esercita queste" (see what I get wrong most, then practise it).
/// The Brano tab of Statistiche (`StatsHub`).
struct PieceStatsView: View {
    let model: PianoModel
    private var trainer: Trainer { model.trainer }
    @Environment(\.dismiss) private var dismiss
    @Environment(\.pianoScale) private var s

    var body: some View {
        let history = trainer.stats.history(piece: trainer.pieceName)
        let recent = trainer.stats.recent(piece: trainer.pieceName)
        let barCount = trainer.piece?.bars.count ?? 0
        VStack(alignment: .leading, spacing: 16) {
            if let title = trainer.piece?.title {
                Text(title).font(.system(size: 17 * s, weight: .semibold))
            }
            if trainer.piece == nil {
                // no piece open (the usual case from Impara on the phone): pick one here (empty tab)
                Text("Di quale brano? Per ogni battuta vedi dove sbagli di più.")
                    .font(.system(size: 17 * s)).foregroundStyle(Theme.mute)
                ForEach(model.library.items) { item in
                    Button { model.open(item.url) } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "music.note").foregroundStyle(.white)
                                .frame(width: 32 * s, height: 32 * s)
                                .background(Theme.accent, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                            Text(item.title).font(.system(size: 17 * s, weight: .semibold)).lineLimit(1)
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.forward").foregroundStyle(Theme.mute)
                        }
                        .padding(10)
                        .contentShape(Rectangle())
                        .glass(RoundedRectangle(cornerRadius: 16, style: .continuous), interactive: true)
                    }
                    .buttonStyle(.plain)
                }
            } else if history.isEmpty {
                Text("Ancora niente: suona una lezione fino in fondo e qui vedi dove sbagli di più.")
                    .font(.system(size: 17 * s)).foregroundStyle(Theme.mute)
            } else {
                hardest(recent)
                DashboardTile(title: "Battuta per battuta", icon: "square.grid.3x3.fill") {
                ScrollView([.horizontal, .vertical]) {
                    Grid(alignment: .leading, horizontalSpacing: 4, verticalSpacing: 6) {
                        GridRow {
                            Text("Battuta").font(.system(size: 12 * s, weight: .semibold)).foregroundStyle(Theme.mute)
                            ForEach(1...max(1, barCount), id: \.self) { b in
                                Text("\(b)").font(.system(size: 11 * s, weight: .semibold)).foregroundStyle(Theme.mute)
                                    .frame(width: 26 * s)
                            }
                        }
                        ForEach(history.prefix(30), id: \.day) { d in
                            GridRow {
                                Text(Self.dayLabel(d.day)).font(.system(size: 14 * s, weight: .medium)).lineLimit(1)
                                ForEach(1...max(1, barCount), id: \.self) { b in cell(d.bars[b]) }
                            }
                        }
                    }
                }
                legend
                }
            }
            Spacer(minLength: 0)
        }
    }

    private func hardest(_ recent: [Int: BarStat]) -> some View {
        let worst = recent.filter { $0.value.score > 0 }.sorted { $0.value.score > $1.value.score }.prefix(5)
        return DashboardTile(title: "Più difficili negli ultimi 7 giorni", icon: "flame") {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: 14) { hardestText(worst); Spacer(); hardestAction(worst, recent) }
            VStack(alignment: .leading, spacing: 10) { hardestText(worst); hardestAction(worst, recent) }
        }
        }
    }

    private func hardestText(_ worst: ArraySlice<(key: Int, value: BarStat)>) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            BigValue(text: "\(worst.count)", caption: worst.count == 1 ? "battuta" : "battute",
                     tint: worst.isEmpty ? Theme.ok : nil)
            Text(worst.isEmpty ? "Nessun errore: ottimo!"
                     : worst.map { "battuta \($0.key) (\(Self.describe($0.value)))" }.joined(separator: " · "))
                    .font(.system(size: 15 * s, weight: .medium)).foregroundStyle(Theme.mute).lineLimit(2).minimumScaleFactor(0.7)
        }
    }

    @ViewBuilder private func hardestAction(_ worst: ArraySlice<(key: Int, value: BarStat)>, _ recent: [Int: BarStat]) -> some View {
            if !worst.isEmpty {
                CapsuleAction(title: "Allena le battute più difficili", symbol: "scope", primary: true) {
                    trainer.practiceWeak(recent)
                    dismiss()
                }
            }
    }

    static func describe(_ b: BarStat) -> String {
        [b.wrong > 0 ? "\(b.wrong) sbagliati" : nil, b.hesitations > 0 ? "\(b.hesitations) esitazioni" : nil,
         b.chordBreaks > 0 ? "\(b.chordBreaks) accordi staccati" : nil].compactMap { $0 }.joined(separator: ", ")
    }

    /// Mistakes per round: 0 green, under 1 yellow, under 3 orange, else red; not played = empty.
    private func cell(_ b: BarStat?) -> some View {
        let color: Color
        if let b, b.rounds > 0 {
            let per = Double(b.score) / Double(b.rounds)
            color = per == 0 ? Theme.ok : per < 1 ? Color(hex: 0xffd60a) : per < 3 ? Theme.rh : Theme.bad
        } else {
            color = Theme.panel2.opacity(0.5)
        }
        return RoundedRectangle(cornerRadius: 5, style: .continuous).fill(color)
            .frame(width: 26 * s, height: 22 * s)
            .help(b.map { "giri \($0.rounds) · " + (Self.describe($0).isEmpty ? "nessun errore" : Self.describe($0)) } ?? "non suonata")
    }

    private var legend: some View {
        HStack(spacing: 14) {
            ForEach([(Theme.ok, "pulita"), (Color(hex: 0xffd60a), "qualche errore"), (Theme.rh, "spesso"),
                     (Theme.bad, "molto spesso"), (Theme.panel2.opacity(0.5), "non suonata")], id: \.1) { c, t in
                HStack(spacing: 6) {
                    RoundedRectangle(cornerRadius: 4).fill(c).frame(width: 14, height: 14)
                    Text(t)
                }
            }
        }
        .font(.system(size: 13 * s)).foregroundStyle(Theme.mute)
    }

    static func dayLabel(_ key: String) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        guard let d = f.date(from: key) else { return key }
        if Calendar.current.isDateInToday(d) { return "Oggi" }
        if Calendar.current.isDateInYesterday(d) { return "Ieri" }
        let out = DateFormatter()
        out.locale = Locale(identifier: "it_IT")
        out.dateFormat = "EEE d MMM"
        return out.string(from: d)
    }
}
