import DesignKit
import PianoKit
import SwiftUI

/// Percorso: the tappa
/// you are on and what passes it, today's session step by step (each opens its exercise), every tappa.
struct PathScreen: View {
    @Bindable var model: PianoModel
    /// A quiz step: close and let the quiz run (the guide picks the level).
    let onQuiz: (PathProgress.Step) -> Void
    /// The Brano step: to the practice (one of your pieces).
    let onPiece: () -> Void
    @State private var sight: SightSession?
    @Environment(\.pianoScale) private var s

    private var path: PathProgress { PathProgress(quiz: model.quiz) }

    var body: some View {
        let c = 1 + (s - 1) * 0.4, t = path.current
        PianoSheet(title: "Percorso", minWidth: 640, minHeight: 620) {
            ScrollView {
                // dashboard tiles
                VStack(alignment: .leading, spacing: 12) {
                    ViewThatFits(in: .horizontal) {
                        TileRow { current(t, c); all(c) }.frame(minWidth: 600)
                        current(t, c)
                    }
                    session(c)
                    ViewThatFits(in: .horizontal) {
                        Color.clear.frame(width: 600, height: 0)   // wide: Le tappe already sits beside the tappa
                        all(c)
                    }
                    Text("In arrivo: ritmo, orecchio, tecnica sulla V49 e un brano di metodo per ogni tappa.")
                        .font(.footnote).foregroundStyle(Theme.mute)
                }
            }
        }
        .sheet(item: $sight) { SightReadingView(model: model, session: $0).environment(\.pianoScale, s) }
    }

    /// How far the tappa is, 0…1: each goal (its levels + the prima vista) counts the same, a level by how much of
    /// the 80% it has, the prima vista by melodies played. Only for the ring: passing still needs every goal.
    private func progress(_ t: Tappa) -> Double {
        let levels = t.levels.map { min(1, model.quiz.mastery(of: $0) / NoteQuiz.pass) }
        let st = model.quiz.store.sight(tappa: t.number)
        let sight = path.sightPassed(t) ? 1 : min(0.99, Double(st.melodies) / Double(Tappa.melodiesToPass))
        return (levels.reduce(0, +) + sight) / Double(levels.count + 1)
    }

    private func current(_ t: Tappa, _ c: CGFloat) -> some View {
        let p = progress(t), done = path.passed(t)
        return DashboardTile(title: "Tappa \(t.number) di \(PathPlan.tappe.count)", icon: "map") {
            HStack(alignment: .center, spacing: 14) {
                ProgressRing(value: p, label: "\(Int((p * 100).rounded(.down)))%", tint: done ? Theme.ok : Theme.accent)
                    .frame(width: 64 * c, height: 64 * c)
                VStack(alignment: .leading, spacing: 4) {
                    Text(t.title).font(.display(24 * c)).lineLimit(2).minimumScaleFactor(0.7)
                    Text(t.learn).font(.system(size: 14 * c)).foregroundStyle(Theme.mute).fixedSize(horizontal: false, vertical: true)
                }
            }
            ForEach(t.levels) { l in
                let k = model.quiz.known(l)
                goal(model.quiz.mastery(of: l) >= NoteQuiz.pass, "\(l.title): sai \(k.known) su \(k.total) (serve l'80%)", c)
            }
            let st = model.quiz.store.sight(tappa: t.number)
            goal(path.sightPassed(t), "Prima vista: \(min(st.melodies, Tappa.melodiesToPass))/\(Tappa.melodiesToPass) melodie"
                 + (st.melodies > 0 ? ", \(Int((st.accuracy * 100).rounded()))% al primo colpo" : "") + " (serve l'80%)", c)
        }
    }

    private func goal(_ ok: Bool, _ text: String, _ c: CGFloat) -> some View {
        Label { Text(text) } icon: {
            Image(systemName: ok ? "checkmark.circle.fill" : "circle").foregroundStyle(ok ? Theme.ok : Theme.mute)
        }
        .font(.system(size: 15 * c, weight: .medium))
    }

    private func session(_ c: CGFloat) -> some View {
        let steps = PathProgress.Step.allCases
        return VStack(alignment: .leading, spacing: 10) {
            Text("Sessione di oggi · ~15 minuti").font(.system(size: 17 * c, weight: .semibold))
            ViewThatFits(in: .horizontal) {
                TileRow { ForEach(steps) { stepTile($0, c) } }.frame(minWidth: 640)       // iPad, Mac: one row
                VStack(spacing: 12) {                                                     // iPhone: two by two
                    ForEach(Array(stride(from: 0, to: steps.count, by: 2)), id: \.self) { i in
                        TileRow { ForEach(steps[i..<min(i + 2, steps.count)]) { stepTile($0, c) } }
                    }
                }
            }
        }
    }

    /// One step of today's session: the whole tile starts it (a phone has no room for a worded button).
    private func stepTile(_ step: PathProgress.Step, _ c: CGFloat) -> some View {
        let done = path.isDone(step, practisedToday: model.trainer.stats.practised())
        return Button { start(step) } label: {
            DashboardTile(title: path.title(step), icon: done ? "checkmark.circle.fill" : icon(step), tappable: !done) {
                if done {
                    BigValue(text: "Fatto", tint: Theme.ok)
                } else if step == .piece {
                    Image(systemName: "play.circle.fill").font(.system(size: 34 * c))
                        .foregroundStyle(step == firstOpen ? Theme.accent : Theme.mute)
                } else {
                    BigValue(text: "\(min(path.count(step), path.target(step)))/\(path.target(step))",
                             tint: step == firstOpen ? Theme.accent : nil)
                }
                Text(path.detail(step)).font(.system(size: 13 * c)).foregroundStyle(Theme.mute)
                    .lineLimit(3).minimumScaleFactor(0.8)
            }
        }
        .buttonStyle(.plain)
        .disabled(done && step != .sight)
        .accessibilityLabel("\(path.title(step)), \(done ? "fatto" : "inizia")")
    }

    /// The first step not done yet (its Inizia is the main action).
    private var firstOpen: PathProgress.Step? {
        PathProgress.Step.allCases.first { !path.isDone($0, practisedToday: model.trainer.stats.practised()) }
    }

    private func icon(_ s: PathProgress.Step) -> String {
        switch s {
        case .review: return "clock.arrow.circlepath"
        case .quiz: return "questionmark.bubble"
        case .sight: return "eye"
        case .piece: return "music.note"
        }
    }

    private func start(_ step: PathProgress.Step) {
        switch step {
        case .review, .quiz: onQuiz(step)
        case .sight:
            let t = path.current
            sight = SightSession(tappa: t.number, spec: t.sight, store: model.quiz.store)
        case .piece: onPiece()
        }
    }

    private func all(_ c: CGFloat) -> some View {
        DashboardTile(title: "Le tappe", icon: "list.bullet") {
            ForEach(PathPlan.tappe) { t in
                let ok = path.passed(t), here = t == path.current
                HStack(spacing: 10) {
                    Image(systemName: ok ? "checkmark.circle.fill" : here ? "location.fill" : "lock.fill")
                        .foregroundStyle(ok ? Theme.ok : here ? Theme.accent : Theme.mute).frame(width: 24 * c)
                    Text("\(t.number). \(t.title)").font(.system(size: 15 * c, weight: here ? .semibold : .regular))
                        .foregroundStyle(path.isAhead(t) ? Theme.mute : Theme.ink)
                    Spacer(minLength: 0)
                }
            }
        }
    }
}

extension SightSession: Identifiable {
    public nonisolated var id: ObjectIdentifier { ObjectIdentifier(self) }
}
