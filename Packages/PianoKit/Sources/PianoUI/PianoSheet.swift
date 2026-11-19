import DesignKit
import PianoKit
import SwiftUI

/// Every Piano sheet: title on the left,
/// **Fine** on the right, the app backdrop, one type scale, the minimum size on the Mac only.
struct PianoSheet<Content: View>: View {
    let title: String
    var minWidth: CGFloat = 520
    var minHeight: CGFloat = 480
    @ViewBuilder let content: () -> Content
    @Environment(\.pianoScale) private var s
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let c = 1 + (s - 1) * 0.4
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(.display(24 * c)).lineLimit(2).minimumScaleFactor(0.7)
                Spacer(minLength: 8)
                Button("Fine") { dismiss() }.bold()
            }
            content()
        }
        .padding(20)
        .padding(.top, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .macSheetFrame(minWidth: minWidth, minHeight: minHeight)
        .background(pianoBackdrop())
        .foregroundStyle(Theme.ink)
        .tint(Theme.accent)
        .preferredColorScheme(.dark)
    }
}

/// The capsule action inside a sheet: glass, accent-tinted when it is the sheet's main action.
struct CapsuleAction: View {
    let title: String
    let symbol: String
    var primary = false
    let action: () -> Void
    @Environment(\.pianoScale) private var s

    var body: some View {
        let c = 1 + (s - 1) * 0.4
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.system(size: 16 * c, weight: .semibold))
                .foregroundStyle(primary ? .white : Theme.ink)
                .padding(.horizontal, 16 * c).frame(minHeight: 44 * c)
                .glass(Capsule(), tint: primary ? Theme.accent : nil, interactive: true)
        }
        .buttonStyle(.plain)
    }
}

/// One Statistiche (there were two sheets with the same name): **Impara** (notes, times, days) and **Brano**
/// (bars of the open piece), opened on the tab of the screen it was asked from.
struct StatsHub: View {
    enum Tab: String, CaseIterable { case quiz = "Impara", piece = "Brano" }
    let model: PianoModel
    @State var tab: Tab

    var body: some View {
        PianoSheet(title: "Statistiche", minWidth: 640, minHeight: 560) {
            Picker("Statistiche di", selection: $tab) {
                ForEach(Tab.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            // the numbers are the same on every device; say whether they are up to date
            (Text(Image(systemName: "arrow.triangle.2.circlepath")) + Text(" " + model.sync.statusText))
                .font(.footnote).foregroundStyle(model.sync.problem == nil ? Theme.mute : AppStyle.warnText)
                .frame(maxWidth: .infinity, alignment: .leading)
            switch tab {
            case .quiz: QuizStatsView(quiz: model.quiz)
            case .piece: PieceStatsView(model: model)
            }
        }
    }
}
