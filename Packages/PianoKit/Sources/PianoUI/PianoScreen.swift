import DesignKit
import PianoKit
import SwiftUI
import UniformTypeIdentifiers

/// Everything the app shares between iPad and Mac: sound, keyboard input, library, practice logic.
@MainActor @Observable
public final class PianoModel {
    public let trainer: Trainer
    public let midi = MIDIInput()
    public let library = Library()
    /// Impara: the note quiz; while its screen is open the V49 answers it instead of the lesson.
    #if DEBUG
    public let quiz = DemoStats.enabled ? NoteQuiz(store: DemoStats.store()) : NoteQuiz()
    #else
    public let quiz = NoteQuiz()
    #endif
    /// Prima vista open: the V49 answers it (percorso).
    public var sight: SightSession?
    /// The Sessione di oggi step being done in the quiz (its answers count for it).
    public var sessionStep: PathProgress.Step?
    /// Statistics shared by iPhone, iPad and Mac through the sync server.
    public let sync: PianoSync
    public var learning = false
    @ObservationIgnored private var started = false
    public private(set) var soundState = "Carico il pianoforte…"
    /// Size of text and drawing (A− / A+), saved.
    public var scale: CGFloat = {
        let v = UserDefaults.standard.double(forKey: "pt:scale")
        #if os(iOS)
        return v > 0 ? v : 1.35
        #else
        return v > 0 ? v : 1
        #endif
    }() { didSet { UserDefaults.standard.set(Double(scale), forKey: "pt:scale") } }

    public func zoom(_ d: CGFloat) { scale = min(1.9, max(0.8, ((scale + d) * 20).rounded() / 20)) }
    /// Apri file… (button in the Brano menu, ⌘O on the Mac).
    public var importing = false
    /// Lessons, tip and buttons folded into one line: automatic as soon as a key is played, back with a tap.
    public var controlsHidden = false

    public init() {
        trainer = Trainer(sound: Sampler())
        let t = trainer
        sync = PianoSync(quiz: quiz.store, stats: { t.stats })
        sync.onChange = { [weak self] in self?.quiz.storeChanged() }
        midi.onMessage = { [weak self] st, d1, d2 in
            guard let self else { return }
            if let sight = self.sight {                           // prima vista: a key = an answer
                if st & 0xf0 == 0x90, d2 > 0, st & 0x0f != 9 {
                    self.quiz.store.practice(.learn)
                    self.trainer.sound.note(Int(d1), at: self.trainer.sound.now, dur: 0.7, vel: 0.35 + Double(d2) / 190)
                    sight.press(Int(d1))
                }
                return
            }
            guard self.learning else { self.trainer.midi(st, d1, d2); return }
            let cmd = st & 0xf0
            guard st & 0x0f != 9 else { return }                  // pads: nothing to do in the quiz
            if cmd == 0x90, d2 > 0 {
                self.trainer.sound.note(Int(d1), at: self.trainer.sound.now, dur: 0.7, vel: 0.35 + Double(d2) / 190)
                self.quiz.hold(Int(d1))
            } else if cmd == 0x80 || cmd == 0x90 {
                self.quiz.release(Int(d1))
            }
        }
        trainer.onPlay = { [weak self] in
            guard let self else { return }
            self.quiz.store.practice(.play)                       // Brani / Suona libero time
            guard !self.controlsHidden else { return }
            withAnimation(.easeInOut(duration: 0.25)) { self.controlsHidden = true }
        }
    }

    public func start() async {
        guard !started else { return }                        // Impara and the practice screen both ask
        started = true
        midi.start()
        Task { await sync.keepInSync() }
        library.reload()   // no piece opened: Piano starts in Suona libero, songs come from Brani
        guard let folder = Bundle.main.resourceURL?.appendingPathComponent("salamander") else { return }
        soundState = await trainer.sound.load(folder: folder) ? "" : "Il suono del pianoforte non si è caricato: riapri l'app."
    }

    /// The library's pieces, read (Impara takes its notes and chords from them).
    public func libraryPieces() -> [Piece] {
        if library.items.isEmpty { library.reload() }
        return library.items.compactMap { item in
            (try? Data(contentsOf: item.url)).flatMap { try? Piece.load(name: item.url.lastPathComponent, data: $0) }
        }
    }

    public func open(_ url: URL) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url) else { trainer.show("Il file non si legge"); return }
        trainer.open(name: url.lastPathComponent, data: data)
    }

    /// A file picked with Apri file…: copied into the user's folder, so it stays in the menu.
    public func importFile(_ url: URL) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let dest = Library.userFolder.appendingPathComponent(url.lastPathComponent)
        if dest.standardizedFileURL != url.standardizedFileURL {
            try? FileManager.default.removeItem(at: dest)
            try? FileManager.default.copyItem(at: url, to: dest)
        }
        library.reload()
        open(FileManager.default.fileExists(atPath: dest.path) ? dest : url)
    }
}

public struct PianoScreen: View {
    @Bindable var model: PianoModel
    @State private var showPads = false
    @State private var showStats = false
    @State private var showSongs = false
    @State private var showLearn = false
    @Environment(\.verticalSizeClass) private var vClass
    @FocusState private var focused: Bool
    /// iPhone: Piano opens on Impara and this screen comes from there; the button goes back to it.
    var onLearn: (() -> Void)?

    public init(model: PianoModel, onLearn: (() -> Void)? = nil) {
        self.model = model
        self.onLearn = onLearn
    }

    private var t: Trainer { model.trainer }
    /// iPhone: the iPad's music-stand size does not fit a phone; practice draws at 60% there.
    private var s: CGFloat {
        #if os(iOS)
        if UIDevice.current.userInterfaceIdiom == .phone { return model.scale * 0.6 }
        #endif
        return model.scale
    }
    /// Header, lessons and buttons grow less than the keyboard, notes and chord names (what matters while playing).
    private var c: CGFloat { 1 + (s - 1) * 0.4 }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            toolbar
            // it used to float over the cards and hide them): the
            // lessons panel pushes the status line and the cards down and the falling-notes area gives up the space,
            // so nothing is covered and the keyboard never moves.
            // Suona libero: no lessons, no
            // bar line — only what you hold (cards) and the keyboard.
            if t.error != nil || (t.mode != .free && !model.controlsHidden) {
                lessonPanel
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
            if t.mode != .free { status }
            // iPhone: no room for the hand cards; the status line already names the notes and fingers
            if !Self.isPhone { HandCards(trainer: t) }
            if Self.isPhone && vClass == .regular {
                Label("Gira il telefono: tasti più grandi", systemImage: "rotate.right")
                    .font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.mute)
            }
            StageView(trainer: t)
        }
        .padding(Self.isPhone ? 8 : 16)
        .background(pianoBackdrop())
        .foregroundStyle(Theme.ink)
        .tint(Theme.accent)
        .preferredColorScheme(.dark)
        .overlay(alignment: .bottom) { toast }
        .focusable()
        .focused($focused)
        .focusEffectDisabled()
        .onKeyPress(phases: .down) { key in handleKey(key) }
        .onAppear {
            focused = true
            if Self.isPhone { model.controlsHidden = true }  // the lessons panel opens from the title on a phone
        }
        .task { await model.start() }
        .fileImporter(isPresented: $model.importing, allowedContentTypes: Self.pieceTypes) { result in
            if case .success(let url) = result { model.importFile(url) }
        }
        .sheet(isPresented: $showPads) { PadsSheet(trainer: t).environment(\.pianoScale, s) }
        .sheet(isPresented: $showStats) { StatsHub(model: model, tab: .piece).environment(\.pianoScale, s) }
        .sheet(isPresented: $showSongs) { SongsSheet(model: model).environment(\.pianoScale, s) }
        #if os(iOS)
        .fullScreenCover(isPresented: $showLearn, onDismiss: { model.learning = false }) {
            LearnScreen(model: model, onClose: { showLearn = false })
        }
        #else
        .sheet(isPresented: $showLearn, onDismiss: { model.learning = false }) {
            LearnScreen(model: model, onClose: { showLearn = false }).frame(minWidth: 900, minHeight: 640)
        }
        #endif
        .environment(\.pianoScale, s)
    }

    static var isPhone: Bool {
        #if os(iOS)
        return UIDevice.current.userInterfaceIdiom == .phone
        #else
        return false
        #endif
    }

    static let pieceTypes: [UTType] = [UTType(filenameExtension: "musicxml"), UTType(filenameExtension: "mxl"),
                                       .xml, .midi].compactMap { $0 }


    private func toggleLessons() {
        withAnimation(.snappy(duration: 0.25)) { model.controlsHidden.toggle() }
    }

    // MARK: toolbar (always on screen, one row)

    private var toolbar: some View {
        HStack(spacing: 14 * c) {
            Button { showSongs = true } label: {
                Label("Brani…", systemImage: "music.note.list")
                    .labelStyle(Self.isPhone ? AnyLabelStyle(.iconOnly) : AnyLabelStyle(.titleAndIcon))  // phone: no room for words
                    .padding(.horizontal, 14 * c)
                    .frame(height: 40 * c)
                    .glass(Capsule(), interactive: true)
                    .fixedSize()
            }
            .buttonStyle(.plain)
            .help("I tuoi brani: scegline uno da esercitare")
            Button { if let onLearn { onLearn() } else { showLearn = true } } label: {
                Label("Impara", systemImage: "graduationcap.fill")
                    .labelStyle(Self.isPhone ? AnyLabelStyle(.iconOnly) : AnyLabelStyle(.titleAndIcon))  // phone: no room for words
                    .padding(.horizontal, 14 * c)
                    .frame(height: 40 * c)
                    .glass(Capsule(), interactive: true)
                    .fixedSize()
            }
            .buttonStyle(.plain)
            .help("Impara le note, la tastiera e gli accordi")
            if t.mode == .free {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Suona libero").font(.display(22 * c)).lineLimit(1)
                    Text(Self.isPhone ? "Tocca i tasti: vedi il nome" : "Le carte dicono cosa tieni giù").font(.system(size: 14 * c, weight: .medium))
                        .foregroundStyle(Theme.mute).lineLimit(1)
                }
            } else {
                lessonTitle
            }
            Spacer(minLength: 8)
            // Responsive: the widest row that fits (iPad landscape, a narrow Mac window, bigger text).
            ViewThatFits(in: .horizontal) {
                controlsRow(compact: 0)
                controlsRow(compact: 1)
                controlsRow(compact: 2)
                controlsRow(compact: 3)                         // iPhone: transport only, the rest in …
            }
            .layoutPriority(1)
        }
        .font(.system(size: 15 * c, weight: .semibold))
    }

    private var lessonTitle: some View {
        Button(action: toggleLessons) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(t.piece?.title ?? "Piano").font(.display(22 * c)).lineLimit(1)
                    Text(t.rangeName).font(.system(size: 14 * c, weight: .medium)).foregroundStyle(Theme.mute).lineLimit(1)
                }
                Image(systemName: "chevron.down")
                    .font(.system(size: 13 * c, weight: .bold))
                    .foregroundStyle(Theme.mute)
                    .rotationEffect(.degrees(model.controlsHidden ? 0 : 180))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(minWidth: 140 * c, alignment: .leading)
        .accessibilityLabel(model.controlsHidden ? "Mostra lezioni e consigli" : "Nascondi lezioni e consigli")
    }

    /// 0 = everything spelled out; 1 = speed as a menu, keyboard as an icon; 2 = hands as a menu too;
    /// 3 = only the transport, hands/speed/loop inside the … menu (iPhone).
    private func controlsRow(compact: Int) -> some View {
        HStack(spacing: 12 * c) {
            if t.mode == .free {
                // the piece's controls (play, hands, speed, loop) mean nothing here: only the way back to it
                if let piece = t.piece {
                    Button { t.endFree() } label: {
                        Label("Torna a " + piece.title, systemImage: "arrow.uturn.backward")
                            .lineLimit(1)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 16 * c)
                            .frame(height: 40 * c)
                            .glass(Capsule(), tint: Theme.accent, interactive: true)
                    }
                    .buttonStyle(.plain)
                }
            } else {
                transport
                if compact < 3 {
                    if compact < 2 { handsPicker } else { handsMenu }
                    if compact == 0 { speed } else { speedMenu }
                    loopButton
                }
            }
            if compact < 3 { keyboardStatus(withText: compact == 0 && !Self.isPhone) }  // iPhone: no V49
            moreMenu(practice: compact == 3 && t.mode != .free)
        }
        .fixedSize()
    }

    private static let handNames: [Trainer.Hands: String] = [.left: "Sinistra", .right: "Destra", .both: "Due mani"]

    private var handsMenu: some View {
        Menu {
            Picker("Mani", selection: Binding(get: { t.hands }, set: { t.setHands($0) })) {
                ForEach([Trainer.Hands.left, .right, .both], id: \.self) { Text(Self.handNames[$0]!).tag($0) }
            }
        } label: {
            pillLabel(Self.handNames[t.hands]!, "hand.raised.fill")
        }
        .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden)
        .accessibilityLabel("Mani: " + Self.handNames[t.hands]!)
    }

    private var speedMenu: some View {
        Menu {
            Picker("Velocità", selection: Binding(get: { t.bpm }, set: { t.bpm = $0 })) {
                ForEach(Array(Set([40, 50, 60, 70, 80, 90, 100, 120, 140, t.bpm])).sorted(), id: \.self) { Text("\($0)").tag($0) }
            }
        } label: {
            pillLabel("\(t.bpm)", "metronome.fill")
        }
        .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden)
        .accessibilityLabel("Velocità \(t.bpm)")
    }

    private func pillLabel(_ text: String, _ symbol: String) -> some View {
        Label(text, systemImage: symbol)
            .font(.system(size: 15 * c, weight: .semibold))
            .padding(.horizontal, 14 * c)
            .frame(height: 40 * c)
            .glass(Capsule(), interactive: true)
    }

    /// Back · Listen/Stop · Hear the step · Forward, as one capsule (media-control language).
    private var transport: some View {
        HStack(spacing: 4 * c) {
            iconButton("backward.fill", "Indietro di un passo (freccia sinistra)") { t.go(-1) }
            Button { t.mode == .listen ? t.stopListen() : t.startListen() } label: {
                Image(systemName: t.mode == .listen ? "stop.fill" : "play.fill")
                    .font(.system(size: 17 * c, weight: .bold))
                    .frame(width: 44 * c, height: 44 * c)
                    .foregroundStyle(.white)
                    .glass(Circle(), tint: t.sound.ready ? Theme.accent : nil, interactive: true)
            }
            .buttonStyle(.plain)
            .disabled(!t.sound.ready)
            .help(t.sound.ready ? (t.mode == .listen ? "Ferma" : "Ascolta la lezione") : model.soundState)
            .accessibilityLabel(t.mode == .listen ? "Ferma" : "Ascolta")
            iconButton("speaker.wave.2.fill", "Fammi sentire questo passo (Invio)") { t.hearStep() }
            iconButton("forward.fill", "Avanti di un passo (spazio o freccia destra)") { t.go(1) }
        }
        .padding(4 * c)
        .glass(Capsule())
    }

    private func iconButton(_ symbol: String, _ help: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 16 * c, weight: .semibold))
                .frame(width: 40 * c, height: 40 * c)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
    }

    private var handsPicker: some View {
        Picker("Mani", selection: Binding(get: { t.hands }, set: { t.setHands($0) })) {
            Text("Sinistra").tag(Trainer.Hands.left)
            Text("Destra").tag(Trainer.Hands.right)
            Text("Due mani").tag(Trainer.Hands.both)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .fixedSize()
    }

    private var speed: some View {
        HStack(spacing: 6 * c) {
            Image(systemName: "metronome.fill").foregroundStyle(Theme.mute)
            Slider(value: Binding(get: { Double(t.bpm) }, set: { t.bpm = Int($0) }), in: 30...160, step: 1)
                .frame(width: 90 * c)
            Text("\(t.bpm)").monospacedDigit().frame(minWidth: 30 * c, alignment: .leading)
        }
        .help("Velocità dell'ascolto (battiti al minuto)")
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Velocità \(t.bpm)")
    }

    private var loopButton: some View {
        Button { t.loop.toggle() } label: {
            Image(systemName: "repeat")
                .font(.system(size: 16 * c, weight: .bold))
                .frame(width: 40 * c, height: 40 * c)
                .foregroundStyle(t.loop ? .white : Theme.ink)
                .glass(Circle(), tint: t.loop ? Theme.accent : nil, interactive: true)
        }
        .buttonStyle(.plain)
        .help(t.loop ? "Loop attivo: tocca per toglierlo" : "Loop: rifà la lezione a ruota")
        .accessibilityLabel(t.loop ? "Togli il loop" : "Metti in loop")
    }

    /// The V49: green keys = connected (name in the tooltip / VoiceOver), grey = plug it in.
    private func keyboardStatus(withText: Bool) -> some View {
        let on = !model.midi.sources.isEmpty
        let text = model.midi.failure ?? (on ? "Collegata: " + model.midi.sources.joined(separator: ", ")
                                             : "Nessuna tastiera: collega la V49 (adattatore USB)")
        return HStack(spacing: 6) {
            Image(systemName: "pianokeys").font(.system(size: 17 * c, weight: .semibold))
                .foregroundStyle(on ? Theme.ok : Theme.mute)
            if !on && withText { Text("Collega la V49").font(.system(size: 13 * c, weight: .medium)).foregroundStyle(Theme.mute) }
        }
        .padding(.horizontal, !on && withText ? 14 * c : 0)
        .frame(minWidth: 40 * c, minHeight: 40 * c)
        .glass(Capsule())                                   // like every other control of the bar
        .help(text)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(text)
    }

    private func moreMenu(practice: Bool) -> some View {
        Menu {
            if practice {
                Section("Pratica") {
                    Picker("Mani", selection: Binding(get: { t.hands }, set: { t.setHands($0) })) {
                        ForEach([Trainer.Hands.left, .right, .both], id: \.self) { Text(Self.handNames[$0]!).tag($0) }
                    }
                    Picker("Velocità \(t.bpm)", selection: Binding(get: { t.bpm }, set: { t.bpm = $0 })) {
                        ForEach(Array(Set([40, 50, 60, 70, 80, 90, 100, 120, 140, t.bpm])).sorted(), id: \.self) { Text("\($0)").tag($0) }
                    }
                    .pickerStyle(.menu)
                    Toggle(isOn: Binding(get: { t.loop }, set: { t.loop = $0 })) { Label("Loop", systemImage: "repeat") }
                }
            }
            Section {
                // Suona libero ↔ back: the way back is the bar's "Torna a <brano>" only
                if t.mode != .free {
                    Button { t.startFree() } label: { Label("Suona libero", systemImage: "pianokeys") }
                }
                Button { showStats = true } label: { Label("Statistiche…", systemImage: "chart.bar.xaxis") }
                if !Self.isPhone {                            // the V49 is never plugged into the phone
                    Button { showPads = true } label: { Label("Pad e rotella della V49…", systemImage: "square.grid.2x2") }
                }
            }
            Section("Testo") {
                Button { model.zoom(0.1) } label: { Label("Più grande", systemImage: "textformat.size.larger") }
                Button { model.zoom(-0.1) } label: { Label("Più piccolo", systemImage: "textformat.size.smaller") }
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 17 * c, weight: .bold))
                .frame(width: 40 * c, height: 40 * c)
                .glass(Circle(), interactive: true)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .accessibilityLabel("Altro: brano, pad, testo")
    }

    // MARK: lessons + tip (folds away while playing)

    private var lessonPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            // no named lessons, only the bars to practise, chosen with a slider.
            HStack(spacing: 14 * c) {
                Text(t.rangeName)
                    .font(.system(size: 17 * c, weight: .semibold)).monospacedDigit()
                    .frame(minWidth: 150 * c, alignment: .leading)
                if let n = t.piece?.bars.count, n > 1 {
                    BarRangeSlider(count: n, a: t.range.a, b: t.range.b, scale: c) { a, b in
                        t.selectRange(a, b)
                        focused = true
                    }
                    Button { t.selectRange(1, n); focused = true } label: {
                        Text("Tutto il brano").font(.system(size: 15 * c, weight: .semibold))
                            .padding(.horizontal, 14 * c).frame(height: 36 * c)
                            .glass(Capsule(), interactive: true)
                    }
                    .buttonStyle(.plain)
                    .fixedSize()
                }
            }
            if let e = t.error {
                Text(e).foregroundStyle(Theme.bad).bold()
            } else if !t.tip.characters.isEmpty {
                Label { Text(t.tip).fixedSize(horizontal: false, vertical: true) } icon: {
                    Image(systemName: "lightbulb.fill").foregroundStyle(Theme.accentSoft)
                }
                .font(.system(size: 15 * c))
                .lineLimit(3)
            }
            if let p = t.piece, t.outOfRange || !p.composer.isEmpty {
                Text(([p.subtitle, p.composer].filter { !$0.isEmpty }.joined(separator: " · "))
                     + (t.outOfRange ? " · alcune note escono dai 49 tasti: usa OCTAVE" : ""))
                    .font(.system(size: 13 * c)).foregroundStyle(Theme.mute).lineLimit(1)
            }
        }
        .padding(14 * c)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glass(RoundedRectangle(cornerRadius: AppStyle.panelRadius, style: .continuous))
    }

    // MARK: status line

    private var status: some View {
        HStack(spacing: 18) {
            if let piece = t.piece, !piece.bars.isEmpty {
                let p = t.mode == .listen ? t.listenPhase : t.currentTime
                let B = t.barAt(max(p, 0)), beatLen = 4 / Double(B.beatType)
                let beat = min(B.beats, Int(floor((p - B.start) / beatLen + Trainer.eps)) + 1)
                Text("Battuta " + B.label).font(.display(20 * s)).monospacedDigit()
                HStack(spacing: 4) {
                    ForEach(1...max(1, B.beats), id: \.self) { i in
                        let now = i == beat && p >= B.start - Trainer.eps
                        Text("\(i)").font(.system(size: 13 * s, weight: now ? .bold : .regular))
                            .frame(width: 26 * s, height: 26 * s)
                            .foregroundStyle(now ? .white : Theme.mute)
                            .background(now ? Theme.accent : Theme.panel2, in: Circle())
                    }
                }
                say(B: B, p: p)
                    .lineLimit(1)
                    .minimumScaleFactor(0.55)
            }
            Spacer(minLength: 0)
        }
        .frame(height: 40 * s)                             // one line, always: playing never moves the keyboard
        .modifier(Panel())
    }

    @ViewBuilder private func say(B: Piece.Bar, p: Double) -> some View {
        if t.mode == .listen {
            Text(t.listenPhase < t.bar(t.range.a).start ? "Pronti… conta con il click" : "Ascolta e guarda dove cadono le note.")
        } else if t.finished {
            Text("Lezione finita, ottimo lavoro!").font(.system(size: 18 * s, weight: .semibold)).foregroundStyle(Theme.ok)
        } else if t.stepIdx == 0, t.got.isEmpty, let pos = Fingering.start(t.evs, fifths: t.piece?.fifths ?? 0) {
            // before the first key, where the hands go (from the sheet's fingers, or the suggested ones)
            (Text(Image(systemName: "hand.raised")) + Text(" Mani in posizione · ").bold() + Text(pos))
                .font(.system(size: 18 * s)).lineLimit(1).minimumScaleFactor(0.6)
        } else {
            stepLine(B: B, p: p).font(.system(size: 18 * s))
        }
    }

    private func stepLine(B: Piece.Bar, p: Double) -> Text {
        let sn = t.stepNotes, r = sn.filter { $0.h == .right }, l = sn.filter { $0.h == .left }
        let off = abs(((p - B.start) / (4 / Double(B.beatType))).truncatingRemainder(dividingBy: 1)) > Trainer.eps
        var line = Text("")
        if !l.isEmpty { line = line + Text("Sinistra: ").bold().foregroundColor(Theme.lh) + fingers(l) + Text("  ") }
        if !r.isEmpty { line = line + Text("Destra: ").bold().foregroundColor(Theme.rh) + fingers(r) }
        if off { line = line + Text(" (tra un tempo e l'altro: “e”)").font(.system(size: 13 * s)).foregroundColor(Theme.mute) }
        let miss = t.missing
        if !miss.isEmpty {
            line = line + Text(" · ") + Text("manca: ").bold()
            for (i, e) in miss.enumerated() {
                line = line + Text((i > 0 ? ", " : "") + "\(noteName(e.n)) (\(e.h == .right ? "destra" : "sinistra"))")
                    .foregroundColor(Theme.hand(e.h))
            }
        }
        line = line + Text("   passo \(t.stepIdx + 1) di \(t.steps.count)").font(.system(size: 13 * s)).foregroundColor(Theme.mute)
        return line
    }

    private func fingers(_ list: [Piece.Event]) -> Text {
        var out = Text("")
        for (i, e) in list.enumerated() {
            if i > 0 { out = out + Text(" + ") }
            out = out + Text(noteName(e.n))
            if !e.f.isEmpty { out = out + Text(" (\(e.f))").font(.system(size: 13 * s)).foregroundColor(Theme.mute) }
        }
        return out
    }

    @ViewBuilder private var toast: some View {
        if let toast = t.toast {
            Text(toast.text).font(.system(size: 17 * s, weight: .bold))
                .foregroundStyle(Theme.ink)
                .padding(.horizontal, 20).padding(.vertical, 12)
                .glass(Capsule())
                .padding(.bottom, 24)
                .allowsHitTesting(false)
                .transition(.opacity)
        }
    }

    // MARK: computer / iPad keyboard

    private func handleKey(_ key: KeyPress) -> KeyPress.Result {
        switch key.key {
        case .rightArrow, .space: t.go(1)
        case .leftArrow: t.go(-1)
        case .return: t.hearStep()
        default:
            switch key.characters.lowercased() {
            case "r": t.padAction("restart")
            case "b": t.padAction("bar")
            default: return .ignored
            }
        }
        return .handled
    }
}

/// Pads + pitch wheel help, and "Insegna i pad" (records the pad notes the V49 really sends).
struct PadsSheet: View {
    let trainer: Trainer
    @Environment(\.pianoScale) private var s

    var body: some View {
        PianoSheet(title: "Comandi dalla V49, senza staccare le mani", minWidth: 560, minHeight: 380) {
            Text("**Rotella PITCH** (quella a sinistra che torna al centro): su = avanti di un passo, giù = indietro. **Pad** (gli 8 quadrati in alto a sinistra), disposti come sulla V49:")
            Grid(horizontalSpacing: 8, verticalSpacing: 8) {
                ForEach([[4, 5, 6, 7], [0, 1, 2, 3]], id: \.self) { row in   // V49 layout: pads 5-8 on top
                    GridRow {
                        ForEach(row, id: \.self) { i in
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Pad \(i + 1)").font(.system(size: 12 * s, weight: .semibold)).foregroundStyle(Theme.mute)
                                Text(Trainer.padActions[i].1).font(.system(size: 14 * s))
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(10)
                            .glass(RoundedRectangle(cornerRadius: 16, style: .continuous), tint: i == trainer.padHit ? Theme.accent : nil)
                            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Theme.accent, lineWidth: i == trainer.learning ? 2 : 0))
                        }
                    }
                }
            }
            HStack(spacing: 10) {
                Text("Se un pad fa la cosa sbagliata o niente:").foregroundStyle(Theme.mute)
                CapsuleAction(title: "Insegna i pad", symbol: "hand.tap") { trainer.startLearningPads() }
                Text(trainer.padMessage).foregroundStyle(Theme.ink)
            }
            .font(.system(size: 14 * s))
            Text("Dalla tastiera del computer: **R** = ricomincia lezione, **B** = ricomincia battuta, frecce/spazio = passo, Invio = fammi sentire.")
                .font(.system(size: 14 * s)).foregroundStyle(Theme.mute)
            Spacer()
        }
    }
}
