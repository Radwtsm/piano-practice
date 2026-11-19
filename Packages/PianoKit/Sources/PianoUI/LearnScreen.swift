import DesignKit
import PianoKit
import SwiftUI

/// Impara (learn): levels from the keyboard to the staff to chords, one question at a time,
/// answered with name buttons (or on the V49 when it is plugged in). iPhone: the app's first screen; iPad/Mac: from the Impara button.
public struct LearnScreen: View {
    @Bindable var model: PianoModel
    /// iPad/Mac: back to practice; nil on iPhone (practice opens from here instead).
    var onClose: (() -> Void)?
    @State private var practice = false
    @State private var advance: Task<Void, Never>?
    /// Narrow screens (iPhone upright): the tip opens from its button, so the staff keeps the room.
    @State private var showTip = false
    @State private var showSigns = false
    @State private var showStats = false
    @State private var showPath = false
    /// Riepilogo del giro: from the score, or from Fine in a training (then closing it ends the training).
    @State private var showSummary = false
    @State private var summaryEndsFocus = false
    @Environment(\.scenePhase) private var phase

    public init(model: PianoModel, onClose: (() -> Void)? = nil) {
        self.model = model
        self.onClose = onClose
    }

    private var q: NoteQuiz { model.quiz }
    private var s: CGFloat { model.scale }
    private var c: CGFloat { 1 + (s - 1) * 0.4 }

    public var body: some View {
        GeometryReader { geo in
            // Turned sideways: staff on the left, name buttons
            // on the right under the thumb, a low keyboard across the bottom. Upright: everything in one column.
            let wide = geo.size.width > geo.size.height * 1.2, short = geo.size.height < 600
            // phone sideways (small phone, 414 pt high): the guide moves into the header, the tip
            // opens as a popover and the buttons get lower, so the question and both button rows stay on screen
            let tight = wide && short
            VStack(alignment: .leading, spacing: short ? 8 : 12) {
                header(tight: tight)
                levels
                if let f = q.focus { focusBanner(f.count) } else if !tight { guideBanner }
                if wide {
                    HStack(alignment: .top, spacing: 12) {
                        question.frame(maxWidth: .infinity, maxHeight: .infinity)
                        VStack(spacing: 10) {
                            side(tipOpen: !short, popover: short)
                            Spacer(minLength: 0)
                            answers(columns: 4, low: short)
                        }
                        .frame(width: min(400 * c, geo.size.width * 0.42))
                    }
                    .frame(maxHeight: .infinity)
                    if !q.level.asksOnKeyboard {                           // tasti, dita: the keyboard is the question
                        QuizKeyboard(quiz: q, scale: s)
                            .frame(height: short ? 58 : max(70, min(130 * s, geo.size.height * 0.16)))
                    }
                } else {
                    question.frame(maxHeight: .infinity)               // gives way: keyboard + buttons always fit
                    side(tipOpen: showTip)
                    if !q.level.asksOnKeyboard {
                        QuizKeyboard(quiz: q, scale: s)
                            .frame(height: max(70, min(130 * s, geo.size.height * 0.16)))
                    }
                    answers(columns: 7)
                }
            }
            .padding(.horizontal, 16).padding(.vertical, tight ? 10 : 16)
        }
        .background(pianoBackdrop())
        #if DEBUG
        .onAppear {
            if DemoStats.open == "stats" { showStats = true }
            if DemoStats.open == "path" { showPath = true }
        }
        #endif
        .foregroundStyle(Theme.ink)
        .tint(Theme.accent)
        .preferredColorScheme(.dark)
        .onAppear {
            model.learning = true
            q.use(pieces: model.libraryPieces())
        }
        .onDisappear { model.learning = onClose == nil && !practice }
        .task { await model.start() }
        // AFK: the app left or the screen locked = this question's time is a pause, not slowness
        .onChange(of: phase) { _, p in if p != .active { q.appAway(); q.store.flushPractice() } }
        .onChange(of: q.feedback) { _, f in
            guard f == .right else { return }
            scheduleNext()
            // Sessione di oggi: this answer counts for the step; step done = back to the Percorso for the next one
            if let step = model.sessionStep {
                let path = PathProgress(quiz: q)
                path.add(step)
                if path.count(step) >= path.target(step) {
                    model.sessionStep = nil
                    Task { try? await Task.sleep(for: .milliseconds(1000)); showPath = true }
                }
            }
        }
        .sheet(isPresented: $showPath) {
            PathScreen(model: model, onQuiz: { step in
                showPath = false
                model.sessionStep = step
                advance?.cancel()
                q.followGuide()
            }, onPiece: {
                showPath = false
                if let onClose { onClose() } else { model.learning = false; practice = true }
            })
            .environment(\.pianoScale, s)
        }
        .sheet(isPresented: $showSummary, onDismiss: {
            if summaryEndsFocus { q.endFocus() }
            summaryEndsFocus = false
        }) {
            RoundSummary(quiz: q, onDone: { summaryEndsFocus = false; showSummary = false }).environment(\.pianoScale, s)
        }
        .sheet(isPresented: $showSigns) { SymbolsSheet().environment(\.pianoScale, s) }
        .sheet(isPresented: $showStats) { StatsHub(model: model, tab: .quiz).environment(\.pianoScale, s) }
        #if os(iOS)
        .fullScreenCover(isPresented: $practice, onDismiss: { model.learning = true }) {
            PianoScreen(model: model, onLearn: { practice = false })
        }
        #endif
        .environment(\.pianoScale, s)
    }

    /// Right answer: hear it (the note or the chord), then the next question.
    private func scheduleNext() {
        if let it = q.item {
            let sound = model.trainer.sound
            for m in it.chord.isEmpty ? [it.midi] : it.chord { sound.note(m, at: sound.now, dur: 0.9, vel: 0.6) }
        }
        advance?.cancel()
        advance = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(900))
            guard !Task.isCancelled else { return }
            withAnimation(.snappy(duration: 0.2)) { q.next() }
        }
    }

    // MARK: header + levels

    /// One row that always fits (Brani fell off the right edge on small phones): words where there is room,
    /// icons only on a phone; the same capsule for every button.
    private func header(tight: Bool) -> some View {
        ViewThatFits(in: .horizontal) {
            headerRow(compact: false, guide: tight)
            headerRow(compact: true, guide: tight)
        }
        .font(.system(size: 15 * c, weight: .semibold))
    }

    private func headerRow(compact: Bool, guide: Bool) -> some View {
        HStack(spacing: 10 * c) {
            Text("Impara").font(.display(22 * c)).lineLimit(1).fixedSize()
            if guide && q.focus == nil { guideLine(compact: true) }
            Spacer(minLength: 4)
            barButton("Percorso…", "map", compact) { showPath = true }
                .help("Le tappe, cosa ti manca e la sessione di oggi")
            barButton("Statistiche…", "chart.bar.xaxis", compact) { showStats = true }
                .help("Quanto ci metti, cosa sbagli, giorno per giorno")
            barButton("Segni…", "questionmark.circle", compact) { showSigns = true }
                .help("Cosa vogliono dire ♯, ♭, pause e gli altri segni dello spartito")
            if onClose == nil {
                // the practice screen (mirror of its "Impara"); "Brani…" is the songs sheet inside it
                barButton("Pratica", "music.quarternote.3", compact) { model.learning = false; practice = true }
                    .help("Esercita i tuoi brani (meglio in orizzontale)")
            } else if let onClose {
                // opened over the practice (iPad/Mac): closes like every Piano sheet
                Button("Fine", action: onClose).bold().padding(.leading, 4)
            }
        }
        .fixedSize(horizontal: compact ? false : true, vertical: false)
    }

    private func barButton(_ title: String, _ symbol: String, _ compact: Bool, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .labelStyle(compact ? AnyLabelStyle(.iconOnly) : AnyLabelStyle(.titleAndIcon))
                .modifier(BarCapsule(c: c))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }

    private func focusBanner(_ n: Int) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "scope").foregroundStyle(AppStyle.warnText)
            Text(q.focusLive ? "Allenamento sulle \(n) note da rivedere"
                 : q.focusConfused ? "Allenamento sulle confusioni: \(n) note" : "Allenamento sulle \(n) note più lente")
                .font(.system(size: 15 * c, weight: .semibold))
            Spacer(minLength: 4)
            Button("Fine") {                                   // what the training did, then back to the quiz
                if q.answered > 0 { summaryEndsFocus = true; showSummary = true } else { q.endFocus() }
            }.bold()
        }
        .padding(.horizontal, 14 * c).padding(.vertical, 8 * c)
        .glass(Capsule())
    }

    /// The guide: where you are on the way and what passes the level, or "Torna al percorso" after you chose
    /// a level yourself.
    private var guideBanner: some View {
        guideLine(compact: false)
            .padding(.horizontal, 14 * c).padding(.vertical, 8 * c)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glass(Capsule())
    }

    private var guideText: String {
        let k = q.known(), need = Int((Double(k.total) * NoteQuiz.pass).rounded(.up))
        // on a staff level, the group being learned (lines, then spaces) says what to look at
        if q.guideNote == nil, q.focus == nil, let st = q.stage {
            return "\(st.title): \(st.notes) · \(st.known)/\(st.total)"   // short: it fits next to Torna al percorso
        }
        return q.guideNote ?? (!q.guided ? "Livello scelto da te"
            : q.level.number < q.frontier.number ? "Ripasso di oggi: \(q.dueCount()) note da rivedere"
            : q.frontier == .chords && q.mastery >= NoteQuiz.pass ? "Percorso finito: qui ripassi gli accordi"
            : "Percorso: sai \(k.known) note su \(k.total) · a \(need) si passa al livello \(q.level.number + 1)")
    }

    /// The guide's line: its own row, or (compact, phone sideways) inside the header with an icon-only button.
    private func guideLine(compact: Bool) -> some View {
        HStack(spacing: compact ? 8 : 10) {
            Image(systemName: "signpost.right.fill").foregroundStyle(Theme.accentSoft)
            Text(guideText).font(.system(size: (compact ? 13 : 14) * c, weight: .semibold))
                .lineLimit(2).minimumScaleFactor(compact ? 0.7 : 0.8)
            if !compact { Spacer(minLength: 4) }
            if !q.guided {
                Button { advance?.cancel(); withAnimation(.snappy(duration: 0.2)) { q.followGuide() } } label: {
                    let l = Label("Torna al percorso", systemImage: "arrow.uturn.backward").lineLimit(1).fixedSize()
                    if compact { l.labelStyle(AnyLabelStyle(.iconOnly)).modifier(BarCapsule(c: c)) } else { l }
                }
                .buttonStyle(.plain)
                .font(.system(size: 14 * c, weight: .bold))
                .accessibilityLabel("Torna al percorso")
            }
        }
    }

    private var levels: some View {
        ScrollViewReader { proxy in
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {   // runs under the screen's side margins instead of being cut inside them
                ForEach(NoteQuiz.Level.allCases) { l in
                    let on = l == q.level
                    let ahead = q.isAhead(l)
                    Button { advance?.cancel(); withAnimation(.snappy(duration: 0.2)) { q.pick(l) } } label: {
                        HStack(spacing: 6) {
                            if ahead { Image(systemName: "lock.fill").font(.system(size: 11 * c, weight: .bold)) }
                            Text("\(l.number). " + l.title).lineLimit(1)
                            let k = q.known(l)
                            Text("\(k.known)/\(k.total)")
                                .font(.system(size: 12 * c, weight: .bold)).monospacedDigit()
                                .foregroundStyle(on ? .white.opacity(0.85) : Theme.mute)
                        }
                        .font(.system(size: 15 * c, weight: .semibold))
                        .foregroundStyle(on ? .white : ahead ? Theme.mute : Theme.ink)
                        .padding(.horizontal, 14 * c).frame(height: 36 * c)
                        .glass(Capsule(), tint: on ? Theme.accent : nil, interactive: true)
                    }
                    .buttonStyle(.plain)
                    .id(l)
                    .accessibilityLabel("\(l.title), sai \(q.known(l).known) su \(q.known(l).total)" + (ahead ? ", viene dopo" : ""))
                }
            }
        }
        .contentMargins(.horizontal, 16, for: .scrollContent)
        .padding(.horizontal, -16)
        .onAppear { proxy.scrollTo(q.level, anchor: .center) }               // the saved level is in view
        .onChange(of: q.level) { _, l in withAnimation { proxy.scrollTo(l, anchor: .center) } }   // the guide moved on
        }
    }

    // MARK: question

    @ViewBuilder private var question: some View {
        if let it = q.item {
            VStack(spacing: 12) {
                switch q.level {
                case .keyboard:
                    QuizKeyboard(quiz: q, scale: s)
                        // real proportions (white key ~1:6), not stretched to fill the card (screenshot)
                        .aspectRatio(QuizKeyboard.aspect(q), contentMode: .fit)
                        .frame(maxWidth: 560 * s)                          // width decides, height follows: no gap
                case .chords:
                    StaffView(notes: it.chord, clef: .treble, fifths: 0, noteColor: noteColor)
                        .aspectRatio(1.5, contentMode: .fit)
                        .frame(maxWidth: 420 * s, minHeight: 110)
                default:
                    StaffView(notes: [it.midi], clef: it.clef, fifths: it.fifths, noteColor: noteColor, marks: q.staffMarks,
                              steps: q.geometry.map { ($0.from, $0.to) }, finger: q.feedback == .right ? q.geometry?.finger : nil)
                        .aspectRatio(1.5, contentMode: .fit)
                        .frame(maxWidth: 460 * s, minHeight: 110)
                    // the key-signature line only while you don't know the note, back after a mistake
                    if it.fifths != 0 && (!q.knows(it) || q.feedback != .none && q.feedback != .right) {
                        Text(Self.keyLine(it.fifths))
                            .font(.system(size: 14 * s, weight: .medium)).foregroundStyle(Theme.mute)
                            .lineLimit(2).minimumScaleFactor(0.7).multilineTextAlignment(.center)
                    }
                }
                feedback(it)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(14 * c)
            .glass(RoundedRectangle(cornerRadius: AppStyle.panelRadius, style: .continuous))
        }
    }

    /// "Armatura: Fa♯ Do♯ = ogni Fa e Do è un tasto nero" (the signs after the clef, in words).
    static func keyLine(_ fifths: Int) -> String {
        let n = min(7, abs(fifths)), sharp = fifths > 0
        let letters = (sharp ? [3, 0, 4, 1, 5, 2, 6] : [6, 2, 5, 1, 4, 0, 3]).prefix(n).map { Staff.letters[$0] }
        return "Armatura: " + letters.map { $0 + (sharp ? "♯" : "♭") }.joined(separator: " ")
            + " = ogni " + letters.joined(separator: ", ") + " si suona " + (sharp ? "un tasto più a destra" : "un tasto più a sinistra")
    }

    private var noteColor: Color {
        switch q.feedback {
        case .right: return Theme.ok
        case .wrong, .wrongName: return Theme.bad
        case .none: return Color(hex: 0x1d1d1f)
        }
    }

    @ViewBuilder private func feedback(_ it: NoteQuiz.Item) -> some View {
        Group {
            switch q.feedback {
            case .right:
                Label(it.chord.isEmpty ? "Giusto: \(q.answer)" : "Giusto: \(q.answer) = " + it.chord.map { Chords.names[$0 % 12] }.joined(separator: " · "),
                      systemImage: "checkmark.circle.fill")
                    .foregroundStyle(Theme.ok)
            case .wrong(let m):
                // the hint alone (one line): the red key already says which was pressed
                Label(q.hint?.text ?? "Quello è un \(Staff.name(m, fifths: it.fifths)): riprova", systemImage: "xmark.circle.fill")
                    .foregroundStyle(Theme.bad)
            case .wrongName(let n):
                // the hint alone, one line (small phones in landscape have no room for a line more): the red button says "not this"
                Label(q.hint?.text ?? "Non è \(n): riprova", systemImage: "xmark.circle.fill")
                    .foregroundStyle(Theme.bad)
            case .none:
                Text((q.level == .chords ? "Che accordo è?" : q.level == .keyboard ? "Che tasto è quello giallo?"
                      : "Che nota è?")
                     + (model.midi.sources.isEmpty ? "" : " Tocca il nome o suonala sulla V49"))
                    .foregroundStyle(Theme.ink)                      // the question itself: primary text, not a hint
            }
        }
        .font(.system(size: 17 * s, weight: .semibold))
        .lineLimit(2).minimumScaleFactor(0.7)
        .frame(minHeight: 28 * s)
    }

    /// The answer: one big button per note name (Do first, same place every time) or 4 chord names.

    private func answers(columns most: Int, low: Bool = false) -> some View {
        let n = q.choices.count
        let cols = q.level == .chords ? 2 : n <= most ? n : (n + 1) / 2   // 9 names = 5 + 4, never 7 + 2
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: max(1, cols)), spacing: 8) {
            ForEach(q.choices, id: \.self) { name in
                let state: Color? = q.feedback == .right && name == q.answer ? Theme.ok
                    : q.feedback == .wrongName(name) ? Theme.bad : nil
                Button { q.choose(name) } label: {
                    Text(name)
                        .font(.system(size: (q.level == .chords ? 17 : 20) * c, weight: .bold))
                        .lineLimit(1).minimumScaleFactor(0.6)
                        .foregroundStyle(state == nil ? Theme.ink : .white)
                        .frame(maxWidth: .infinity, minHeight: low ? 44 : 52 * c)
                        .contentShape(Rectangle())
                        .glass(RoundedRectangle(cornerRadius: 14, style: .continuous), tint: state, interactive: true)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(name)
            }
        }
    }

    // MARK: tip + score

    private func side(tipOpen: Bool, popover: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if tipOpen {
                Label { Text(q.level.tip).fixedSize(horizontal: false, vertical: true) } icon: {
                    Image(systemName: "lightbulb.fill").foregroundStyle(Theme.accentSoft)
                }
                .font(.system(size: 15 * c))
                .onTapGesture { showTip = false }
            }
            HStack(spacing: 12) {
                if !tipOpen {
                    Button { withAnimation(.snappy(duration: 0.2)) { showTip = true } } label: {
                        ViewThatFits(in: .horizontal) {
                            Label("Consiglio", systemImage: "lightbulb.fill").lineLimit(1).fixedSize()
                            Image(systemName: "lightbulb.fill")
                        }
                    }
                    .accessibilityLabel("Consiglio")
                    .buttonStyle(.plain).foregroundStyle(Theme.accentSoft)
                    // sideways on a phone the tip would push the buttons off the screen: it floats instead
                    .popover(isPresented: Binding(get: { popover && showTip }, set: { showTip = $0 })) {
                        Text(q.level.tip).font(.system(size: 15 * c)).fixedSize(horizontal: false, vertical: true)
                            .padding(16).frame(width: 340)
                            .presentationCompactAdaptation(.popover)
                    }
                }
                Button { showSummary = true } label: {             // the round's summary
                    HStack(spacing: 12) {
                        Label("\(q.rightFirst)", systemImage: "checkmark").foregroundStyle(Theme.ok).fixedSize()
                        Label("\(q.missed)", systemImage: "xmark").foregroundStyle(Theme.bad).fixedSize()
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Riepilogo del giro: \(q.rightFirst) giuste, \(q.missed) con errore")
                Spacer(minLength: 0)
                if q.dueCount() > 0 {                                  // review day reached
                    Label("\(q.dueCount())", systemImage: "clock.arrow.circlepath").foregroundStyle(AppStyle.warnText).fixedSize()
                        .accessibilityLabel("\(q.dueCount()) note da ripassare oggi")
                }
                let k = q.known()
                Text("Sai \(k.known)/\(k.total)").foregroundStyle(Theme.mute).fixedSize()   // Statistiche… is in the bar
                    .accessibilityLabel("Sai \(k.known) note su \(k.total)")
            }
            .font(.system(size: 14 * c, weight: .semibold)).monospacedDigit()
            LiveRow(quiz: q, c: c)                                   // updated at every answer
        }
        .padding(14 * c)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glass(RoundedRectangle(cornerRadius: AppStyle.panelRadius, style: .continuous))
    }
}

/// The quiz's keyboard, only to look at (no keys to press on screen): whole octaves around the
/// level's notes, "Do" under every C. Accent = the key asked (keyboard level); green = where the answer is, shown once you got
/// it (staff → key position); red = a wrong V49 key.
struct QuizKeyboard: View {
    let quiz: NoteQuiz
    let scale: CGFloat

    /// Width : height of a keyboard of the quiz's range with piano-like white keys (1 : 6) plus the label strip.
    static func aspect(_ quiz: NoteQuiz) -> CGFloat {
        let whites = quiz.range.filter { !isBlack($0) }.count
        return CGFloat(max(1, whites)) / 6.8
    }

    var body: some View {
        GeometryReader { geo in
            let keys = layout(geo.size)
            Canvas { g, size in draw(&g, size, keys) }
                .accessibilityElement()
                .accessibilityLabel("Tastiera")
        }
        .background(Theme.stage)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private func layout(_ size: CGSize) -> [Int: StageView.Key] {
        let r = quiz.range, whites = r.filter { !isBlack($0) }.count
        let ww = size.width / CGFloat(max(1, whites)), bw = ww * 0.62
        var out: [Int: StageView.Key] = [:], wi: CGFloat = 0
        for m in r {
            if isBlack(m) { out[m] = .init(x: wi * ww - bw / 2, w: bw, black: true) }
            else { out[m] = .init(x: wi * ww, w: ww, black: false); wi += 1 }
        }
        return out
    }

    private func draw(_ g: inout GraphicsContext, _ size: CGSize, _ keys: [Int: StageView.Key]) {
        let kb = size.height - 18 * scale
        let target = quiz.item.map { $0.chord.isEmpty ? [quiz.shown ?? $0.midi] : $0.chord } ?? []
        let asked = quiz.level.asksOnKeyboard    // the keyboard IS the question; chords = read the staff
        // the staff's blue = the keyboard's blue (where you count from), then the way to the note
        let geo = quiz.geometry, from = geo?.keys.first ?? quiz.staffMarks.first.map(Staff.natural)
        func fill(_ m: Int, _ black: Bool) -> Color {
            if case .wrong(let w) = quiz.feedback, w == m { return Theme.bad }
            if target.contains(m) {
                if quiz.feedback == .right { return Theme.ok }
                if asked { return Theme.warn }               // yellow = "this one" (red means wrong)
            }
            if quiz.hint?.keys.contains(m) == true { return Theme.hint }   // the group to count; the asked key stays yellow
            if m == from { return Theme.hint }
            if geo?.keys.contains(m) == true { return Color(hex: 0xbfd9f6) }    // the steps on the way, light blue
            return black ? Color(hex: 0x181a20) : Color(hex: 0xf4f2ec)
        }
        for pass in [false, true] {
            for m in quiz.range {
                guard let k = keys[m], k.black == pass else { continue }
                let h = k.black ? kb * 0.62 : kb
                let shape = Path(roundedRect: CGRect(x: k.x + (k.black ? 0 : 0.5), y: 0, width: k.w - (k.black ? 0 : 1), height: h),
                                 cornerRadius: k.black ? 3 : 5)
                g.fill(shape, with: .color(fill(m, k.black)))
                if !k.black { g.stroke(shape, with: .color(Theme.stage), lineWidth: 1) }
            }
        }
        if let way = geo {                                    // step numbers on the keys, the finger on the note's key
            for (k, m) in way.keys.enumerated().dropFirst() {
                guard let key = keys[m] else { continue }
                g.draw(Text("\(k)").font(.system(size: 13 * scale, weight: .bold)).foregroundColor(Theme.hint),
                       at: CGPoint(x: key.x + key.w / 2, y: kb - 12 * scale))
            }
            if quiz.feedback == .right, let it = quiz.item, let key = keys[it.midi] {
                let c = CGPoint(x: key.x + key.w / 2, y: (key.black ? kb * 0.62 * 0.55 : kb * 0.3)), r = 10 * scale   // above the step number
                g.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)), with: .color(Theme.hint))
                g.draw(Text("\(way.finger)").font(.system(size: 13 * scale, weight: .heavy)).foregroundColor(.white), at: c)
            }
        }
        for m in quiz.range where m % 12 == 0 {
            guard let k = keys[m] else { continue }
            let first = k.x < 1                               // first key: label starts at the edge, never clipped
            g.draw(Text(m == 60 ? "Do centrale" : "Do").font(.system(size: 11 * scale, weight: .semibold)).foregroundColor(Theme.mute),
                   at: CGPoint(x: first ? k.x + 4 : k.x + k.w / 2, y: kb + 9 * scale), anchor: first ? .leading : .center)
        }
    }
}

/// The bar capsule (same height and padding for every button of Impara's bar).
struct BarCapsule: ViewModifier {
    let c: CGFloat
    func body(content: Content) -> some View {
        content.padding(.horizontal, 12 * c).frame(minWidth: 40 * c).frame(height: 40 * c).glass(Capsule(), interactive: true)
    }
}
