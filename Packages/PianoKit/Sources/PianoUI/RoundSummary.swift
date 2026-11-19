import DesignKit
import PianoKit
import SwiftUI

/// Riepilogo del giro: this round's answers, the notes that
/// got better and the ones still to review, with "Allena queste". Opened from the score in Impara and from Fine in a
/// training; the round goes on unless you start a new one.
struct RoundSummary: View {
    let quiz: NoteQuiz
    /// Allena queste / Nuovo giro: the sheet closes after either.
    let onDone: () -> Void
    @Environment(\.pianoScale) private var s

    var body: some View {
        let c = 1 + (s - 1) * 0.4
        PianoSheet(title: "Questo giro", minWidth: 420, minHeight: 420) {
            ScrollView {
                VStack(spacing: 12) {
                    TileRow {
                        DashboardTile(title: "Risposte", icon: "number") { BigValue(text: "\(quiz.answered)") }
                        DashboardTile(title: "Al primo colpo", icon: "checkmark") {
                            BigValue(text: quiz.answered == 0 ? "–" : "\(quiz.rightFirst * 100 / max(1, quiz.answered))%",
                                     caption: "\(quiz.missed) con errore")
                        }
                    }
                    DashboardTile(title: "Migliorate", icon: "arrow.up.right") {
                        if quiz.improved.isEmpty {
                            Text("Una nota sbagliata o lenta migliora quando la fai giusta e in fretta \(NoteQuiz.liveStreak) volte di fila.")
                                .font(.system(size: 14 * c)).foregroundStyle(Theme.mute)
                        } else {
                            Text(quiz.improved.map(Self.name).joined(separator: " · "))
                                .font(.system(size: 17 * c, weight: .semibold)).foregroundStyle(Theme.ok)
                        }
                    }
                    DashboardTile(title: "Da rivedere", icon: "arrow.triangle.2.circlepath") {
                        if quiz.live.isEmpty {
                            Label("Niente: le hai fatte tutte giuste e in fretta.", systemImage: "checkmark.circle.fill")
                                .font(.system(size: 15 * c, weight: .semibold)).foregroundStyle(Theme.ok)
                        } else {
                            ForEach(quiz.live) { l in
                                HStack {
                                    Text(l.name).font(.system(size: 17 * c, weight: .semibold))
                                    Spacer(minLength: 4)
                                    Text(LiveRow.detail(l)).font(.system(size: 14 * c)).monospacedDigit()
                                        .foregroundStyle(l.misses > 0 ? Theme.bad : AppStyle.warnText)
                                }
                                .accessibilityElement(children: .combine)
                            }
                            CapsuleAction(title: "Allena queste", symbol: "scope", primary: true) {
                                quiz.trainLive()
                                onDone()
                            }
                        }
                    }
                    if quiz.answered > 0 {
                        CapsuleAction(title: "Nuovo giro", symbol: "arrow.counterclockwise") {
                            quiz.restartRound()
                            onDone()
                        }
                    }
                }
            }
        }
    }

    static func name(_ it: NoteQuiz.Item) -> String {
        it.chord.isEmpty ? Staff.name(it.midi, fifths: it.fifths) : it.chordName
    }
}

/// The live line under the score: this round's notes to review, updated at every answer.
struct LiveRow: View {
    let quiz: NoteQuiz
    let c: CGFloat

    var body: some View {
        if !quiz.live.isEmpty {
            HStack(spacing: 8) {
                Text("Da rivedere").foregroundStyle(Theme.mute).fixedSize()
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(quiz.live) { l in
                            Text("\(l.name) \(Self.short(l))")
                                .foregroundStyle(l.misses > 0 ? Theme.bad : AppStyle.warnText)
                                .padding(.horizontal, 8).padding(.vertical, 2)
                                .background(Capsule().fill(Color.white.opacity(0.08)))
                        }
                    }
                }
            }
            .font(.system(size: 14 * c, weight: .semibold)).monospacedDigit()
            .lineLimit(1)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Da rivedere: " + quiz.live.map { "\($0.name), \(Self.detail($0))" }.joined(separator: "; "))
        } else if let last = quiz.improved.last {
            Label("Migliorata: \(RoundSummary.name(last))", systemImage: "arrow.up.right")
                .font(.system(size: 14 * c, weight: .semibold)).foregroundStyle(Theme.ok).lineLimit(1)
        }
    }

    /// "✕2" for mistakes, "6 s" for a slow one, plus the good answers so far ("· 1/2").
    static func short(_ l: NoteQuiz.Live) -> String {
        (l.misses > 0 ? "✕\(l.misses)" : l.seconds.map { "\(Int($0.rounded())) s" } ?? "")
            + (l.streak > 0 ? " \(l.streak)/\(NoteQuiz.liveStreak)" : "")
    }

    static func detail(_ l: NoteQuiz.Live) -> String {
        (l.misses > 0 ? (l.misses == 1 ? "1 errore" : "\(l.misses) errori")
            : l.seconds.map { "lenta: \(Int($0.rounded())) s" } ?? "")
            + (l.streak > 0 ? " · \(l.streak) su \(NoteQuiz.liveStreak) giuste" : "")
    }
}
