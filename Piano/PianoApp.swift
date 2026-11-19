import PianoUI
import SwiftUI

/// Piano: the native piano trainer. Same code on iPad and Mac, all of it in PianoKit + PianoUI.
@main
struct PianoApp: App {
    @State private var model = PianoModel()
    @Environment(\.scenePhase) private var phase

    var body: some Scene {
        WindowGroup {
            root
                // statistics out when you leave, the other devices' in when you come back
                .onChange(of: phase) { _, p in if p != .inactive { Task { await model.sync.sync() } } }
                #if os(macOS)
                .frame(minWidth: 900, minHeight: 620)
                #endif
        }
        #if os(macOS)
        // A real first size (before: the window opened at the content's minimum, larger than the space the
        // layout asked for, and showed shifted until resized).
        .defaultSize(width: 1320, height: 880)
        // No title bar strip: the backdrop runs to the top
        // edge under the traffic lights; the top 28 pt still drags the window.
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Apri…") { model.importing = true }.keyboardShortcut("o")
                Button("Mostra cartella brani") { NSWorkspace.shared.open(Library.userFolder) }
            }
        }
        #endif
    }

    /// iPhone (touch only, no V49): Impara first, practice from its Brani button; iPad/Mac: practice first.
    @ViewBuilder private var root: some View {
        #if os(iOS)
        if UIDevice.current.userInterfaceIdiom == .phone { LearnScreen(model: model) } else { PianoScreen(model: model) }
        #else
        PianoScreen(model: model)
        #endif
    }
}
