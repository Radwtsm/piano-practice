import DesignKit
import SwiftUI

/// Segni: every sign a beginner meets on the
/// sheet, drawn big, with what it means in plain words. Opened from Impara's header.
struct SymbolsSheet: View {
    @Environment(\.pianoScale) private var s

    struct Sign: Identifiable {
        let kind: MusicSignView.Kind
        let name: String
        let meaning: String
        var id: String { name }
    }

    struct Group: Identifiable {
        let title: String
        let signs: [Sign]
        var id: String { title }
    }

    static let groups: [Group] = [
        Group(title: "Dove suonare", signs: [
            Sign(kind: .trebleClef, name: "Chiave di violino",
                 meaning: "Il pentagramma di sopra, di solito la mano destra. Il ricciolo gira intorno alla seconda riga dal basso: lì c'è il Sol."),
            Sign(kind: .bassClef, name: "Chiave di basso",
                 meaning: "Il pentagramma di sotto, di solito la mano sinistra. I due puntini stanno intorno alla quarta riga dal basso: lì c'è il Fa."),
            Sign(kind: .sharp, name: "Diesis",
                 meaning: "Alza la nota di mezzo tono: suoni il tasto subito a destra (di solito un tasto nero). Fa♯ = il nero a destra del Fa."),
            Sign(kind: .flat, name: "Bemolle",
                 meaning: "Abbassa la nota di mezzo tono: suoni il tasto subito a sinistra. Si♭ = il nero a sinistra del Si."),
            Sign(kind: .natural, name: "Bequadro",
                 meaning: "Annulla ♯ o ♭: torni al tasto bianco normale, fino alla fine della battuta."),
            Sign(kind: .keySignature, name: "Armatura",
                 meaning: "I ♯ o ♭ subito dopo la chiave valgono per tutto il brano: se c'è un ♯ sulla riga del Fa, ogni Fa diventa Fa♯ anche senza segno accanto."),
            Sign(kind: .ledger, name: "Taglio addizionale",
                 meaning: "Una righetta corta per le note sopra o sotto il pentagramma. Il Do centrale ha un taglio: sotto il violino, sopra il basso."),
            Sign(kind: .fingers, name: "Numeri sopra le note",
                 meaning: "Le dita: 1 pollice, 2 indice, 3 medio, 4 anulare, 5 mignolo. Uguale per le due mani."),
        ]),
        Group(title: "Quanto dura", signs: [
            Sign(kind: .whole, name: "Semibreve", meaning: "Testa vuota senza gambo: tienila 4 tempi."),
            Sign(kind: .half, name: "Minima", meaning: "Testa vuota con gambo: 2 tempi."),
            Sign(kind: .quarter, name: "Semiminima", meaning: "Testa piena con gambo: 1 tempo, il battito che conti."),
            Sign(kind: .eighth, name: "Croma", meaning: "Con una codina (o unite a due da una barra): mezzo tempo. Conta \"1 e 2 e\"."),
            Sign(kind: .dotted, name: "Punto dopo la nota", meaning: "Allunga la nota della sua metà: minima col punto = 3 tempi."),
            Sign(kind: .tie, name: "Legatura (stessa nota)", meaning: "Un arco tra due note uguali: suoni la prima e la tieni anche per la seconda, senza ripremere."),
            Sign(kind: .time, name: "Tempo (i due numeri)", meaning: "Quello di sopra = quanti tempi ha ogni battuta (4/4: conti 1-2-3-4; 3/4: conti 1-2-3)."),
            Sign(kind: .barline, name: "Stanghetta", meaning: "Divide le battute. Ogni battuta ha lo stesso numero di tempi."),
        ]),
        Group(title: "Silenzi", signs: [
            Sign(kind: .wholeRest, name: "Pausa di semibreve", meaning: "Rettangolo appeso alla riga: 4 tempi (o una battuta intera) di silenzio."),
            Sign(kind: .halfRest, name: "Pausa di minima", meaning: "Rettangolo appoggiato sulla riga: 2 tempi di silenzio."),
            Sign(kind: .quarterRest, name: "Pausa di semiminima", meaning: "Lo zig-zag: 1 tempo di silenzio."),
            Sign(kind: .eighthRest, name: "Pausa di croma", meaning: "Mezzo tempo di silenzio."),
        ]),
        Group(title: "Come suonare", signs: [
            Sign(kind: .staccato, name: "Staccato", meaning: "Un puntino sopra o sotto la testa: suona corta, stacca subito il dito."),
            Sign(kind: .slur, name: "Legato (note diverse)", meaning: "Un arco su note diverse: passa da una all'altra senza buchi."),
            Sign(kind: .dynamics, name: "Piano, forte", meaning: "p = piano (piano di volume), f = forte, mp/mf = a metà. < = sempre più forte, > = sempre più piano."),
            Sign(kind: .pedal, name: "Pedale", meaning: "Schiaccia il pedale (sustain) da qui fino all'asterisco ✱ o alla fine della riga sotto."),
            Sign(kind: .repeatSign, name: "Ritornello", meaning: "Suoni il pezzo tra i due segni due volte."),
            Sign(kind: .fermata, name: "Corona", meaning: "Tieni la nota più a lungo del normale, quanto ti piace."),
        ]),
    ]

    var body: some View {
        let c = 1 + (s - 1) * 0.4
        PianoSheet(title: "I segni dello spartito", minWidth: 420) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    ForEach(Self.groups) { g in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(g.title).font(.system(size: 15 * c, weight: .bold)).foregroundStyle(Theme.mute)
                            ForEach(g.signs) { sign in row(sign, c) }
                        }
                    }
                }
            }
        }
    }

    private func row(_ sign: Sign, _ c: CGFloat) -> some View {
        HStack(alignment: .top, spacing: 14) {
            MusicSignView(kind: sign.kind)
                .frame(width: 64 * c, height: 64 * c)
            VStack(alignment: .leading, spacing: 3) {
                Text(sign.name).font(.system(size: 17 * c, weight: .semibold))
                Text(sign.meaning).font(.system(size: 15 * c)).foregroundStyle(Theme.ink.opacity(0.85))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .glass(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}
