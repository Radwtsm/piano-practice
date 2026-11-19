import DesignKit
import SwiftUI

/// Brani: the songs Piano knows
/// (shipped + the user's folder) and Apri file…; tapping one opens it for practice.
struct SongsSheet: View {
    @Bindable var model: PianoModel
    @Environment(\.pianoScale) private var s
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let c = 1 + (s - 1) * 0.4
        PianoSheet(title: "Brani", minWidth: 420, minHeight: 360) {
            ScrollView {
                VStack(spacing: 8) {
                    ForEach(model.library.items) { item in
                        let current = item.url.lastPathComponent == model.trainer.pieceName
                        Button {
                            model.open(item.url)
                            dismiss()
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "music.note")
                                    .font(.system(size: 17 * c, weight: .semibold))
                                    .foregroundStyle(.white)
                                    .frame(width: 36 * c, height: 36 * c)
                                    .background(Theme.accent, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                                Text(item.title).font(.system(size: 17 * c, weight: .semibold)).lineLimit(1)
                                Spacer(minLength: 0)
                                if current { Image(systemName: "checkmark").foregroundStyle(Theme.accent).bold() }
                            }
                            .padding(10)
                            .contentShape(Rectangle())
                            .glass(RoundedRectangle(cornerRadius: 16, style: .continuous), interactive: true)
                        }
                        .buttonStyle(.plain)
                    }
                    if model.library.items.isEmpty {
                        Text("Nessun brano ancora: aprine uno (MusicXML o MIDI).").foregroundStyle(Theme.mute)
                    }
                }
            }
            HStack(spacing: 12) {
                CapsuleAction(title: "Apri file…", symbol: "folder") {
                    dismiss()
                    // the file picker can't open while this sheet is still on screen
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { model.importing = true }
                }
                #if os(macOS)
                CapsuleAction(title: "Mostra cartella brani", symbol: "folder.badge.gearshape") {
                    NSWorkspace.shared.open(Library.userFolder)
                }
                #endif
            }
            Text("MusicXML (.musicxml, .mxl) o MIDI. Da MuseScore scarica in MusicXML: porta mani e diteggiature.")
                .font(.system(size: 13 * c)).foregroundStyle(Theme.mute)
        }
    }
}
