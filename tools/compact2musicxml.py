#!/usr/bin/env python3
"""Turn a compact piano transcription (sources/*.txt) into MusicXML + lessons JSON for the trainer.

Format (one bar per line; a line starting with '#', or ' # ' after the content, is a comment):

    title: Ode to Joy
    subtitle: Symphony No. 9, 4th movement (easy)
    composer: Ludwig van Beethoven
    arranger: piano-practice
    key: 2                  # sharps (+) or flats (-)
    time: 3/4
    tempo: 94
    lesson: 1-4 | Il mattone | Testo del consiglio (HTML semplice ammesso)

    1 | D4+G4+B4/h:124 A4/q:3 | G3/h.:1
    16 time 2/4 | E4+A4+C#5/e:135 r/e r/q | A2/e:5 r/e r/q

A token is notes joined by '+' (pitch = letter, optional # or b, octave; C4 = middle C), then
'/' + duration (w h q e s, one '.' per dot), then optional ':' + one finger per note in the
written order, then flags: '!' staccato, '~' tied to the same pitch in the next token.
'r/q' is a rest. An empty hand gets a whole-bar rest.

Usage: compact2musicxml.py sources/x.txt  → pieces/x.musicxml and pieces/x.lessons.json
"""
import json
import re
import sys
from pathlib import Path
from xml.sax.saxutils import escape

DIV = 4                                   # divisions per quarter: a sixteenth = 1
BASE = {'w': 16, 'h': 8, 'q': 4, 'e': 2, 's': 1}
TYPE = {'w': 'whole', 'h': 'half', 'q': 'quarter', 'e': 'eighth', 's': '16th'}
STEP_SEMI = {'C': 0, 'D': 2, 'E': 4, 'F': 5, 'G': 7, 'A': 9, 'B': 11}
TOKEN = re.compile(r'^(?P<notes>[^/]+)/(?P<dur>[whqes])(?P<dots>\.*)(?::(?P<fing>\d+))?(?P<flags>[!~]*)$')
PITCH = re.compile(r'^([A-G])([#b]?)(-?\d)$')


def parse_token(tok, where):
    m = TOKEN.match(tok)
    if not m:
        sys.exit(f'{where}: token non valido "{tok}"')
    dur = BASE[m['dur']]
    add = dur
    for _ in m['dots']:
        add //= 2
        dur += add
    notes = []
    if m['notes'] != 'r':
        for p in m['notes'].split('+'):
            pm = PITCH.match(p)
            if not pm:
                sys.exit(f'{where}: nota non valida "{p}"')
            notes.append((pm[1], {'#': 1, 'b': -1}.get(pm[2], 0), int(pm[3])))
    fing = m['fing'] or ''
    if fing and len(fing) != len(notes):
        sys.exit(f'{where}: {len(notes)} note ma dita "{fing}"')
    return {'notes': notes, 'dur': dur, 'type': TYPE[m['dur']], 'dots': len(m['dots']),
            'fing': fing, 'stacc': '!' in m['flags'], 'tie': '~' in m['flags']}


def note_xml(tok, staff, tie_stop):
    out = []
    if not tok['notes']:
        dots = '<dot/>' * tok['dots']
        return [f'<note><rest/><duration>{tok["dur"]}</duration><voice>{staff}</voice>'
                f'<type>{tok["type"]}</type>{dots}<staff>{staff}</staff></note>']
    for i, (step, alter, octave) in enumerate(tok['notes']):
        pitch_id = (step, alter, octave)
        x = ['<note>']
        if i:
            x.append('<chord/>')
        x.append(f'<pitch><step>{step}</step>' + (f'<alter>{alter}</alter>' if alter else '') +
                 f'<octave>{octave}</octave></pitch>')
        x.append(f'<duration>{tok["dur"]}</duration>')
        stop, start = pitch_id in tie_stop, tok['tie']
        if stop:
            x.append('<tie type="stop"/>')
        if start:
            x.append('<tie type="start"/>')
        x.append(f'<voice>{staff}</voice><type>{tok["type"]}</type>' + '<dot/>' * tok['dots'])
        x.append(f'<staff>{staff}</staff>')
        nots = []
        if stop:
            nots.append('<tied type="stop"/>')
        if start:
            nots.append('<tied type="start"/>')
        if tok['stacc']:
            nots.append('<articulations><staccato/></articulations>')
        if tok['fing']:
            nots.append(f'<technical><fingering>{tok["fing"][i]}</fingering></technical>')
        if nots:
            x.append('<notations>' + ''.join(nots) + '</notations>')
        x.append('</note>')
        out.append(''.join(x))
    return out


def convert(src: Path):
    meta, lessons, bars = {}, [], []
    time = (4, 4)
    for ln, raw in enumerate(src.read_text(encoding='utf-8').splitlines(), 1):
        # comments: a line starting with '#', or ' # ' after the content ('F#4' is a note, not a comment)
        line = '' if raw.lstrip().startswith('#') else re.sub(r'\s#\s.*$', '', raw).rstrip()
        if not line.strip():
            continue
        if re.match(r'^[a-z]+:', line):
            k, v = line.split(':', 1)
            v = v.strip()
            if k == 'lesson':
                rng, name, tip = (p.strip() for p in v.split('|', 2))
                a, b = (int(n) for n in rng.split('-'))
                lessons.append({'name': name, 'a': a, 'b': b, 'tip': tip})
            elif k == 'time':
                time = tuple(int(n) for n in v.split('/'))
                meta['time'] = time
            else:
                meta[k] = v
            continue
        head, rh, lh = (p.strip() for p in line.split('|'))
        hm = re.match(r'^(\d+)(?:\s+time\s+(\d+)/(\d+))?$', head)
        if not hm:
            sys.exit(f'{src}:{ln}: inizio battuta non valido "{head}"')
        new_time = (int(hm[2]), int(hm[3])) if hm[2] else None
        if new_time:
            time = new_time
        bars.append({'num': int(hm[1]), 'time': time, 'new_time': new_time or (time if not bars else None),
                     'R': [parse_token(t, f'{src}:{ln}') for t in rh.split()],
                     'L': [parse_token(t, f'{src}:{ln}') for t in lh.split()]})

    fifths = int(meta.get('key', 0))
    parts = []
    tie_open = {1: set(), 2: set()}
    for bar in bars:
        blen = bar['time'][0] * 16 // bar['time'][1]
        x = [f'<measure number="{bar["num"]}">']
        if bar is bars[0] or bar['new_time']:
            attrs = []
            if bar is bars[0]:
                attrs.append(f'<divisions>{DIV}</divisions><key><fifths>{fifths}</fifths></key>')
            attrs.append(f'<time><beats>{bar["time"][0]}</beats><beat-type>{bar["time"][1]}</beat-type></time>')
            if bar is bars[0]:
                attrs.append('<staves>2</staves><clef number="1"><sign>G</sign><line>2</line></clef>'
                             '<clef number="2"><sign>F</sign><line>4</line></clef>')
            x.append('<attributes>' + ''.join(attrs) + '</attributes>')
            if bar is bars[0] and 'tempo' in meta:
                x.append(f'<direction placement="above"><direction-type><metronome><beat-unit>quarter</beat-unit>'
                         f'<per-minute>{meta["tempo"]}</per-minute></metronome></direction-type>'
                         f'<staff>1</staff><sound tempo="{meta["tempo"]}"/></direction>')
        for staff, hand in ((1, 'R'), (2, 'L')):
            toks = bar[hand] or [{'notes': [], 'dur': blen, 'type': 'whole', 'dots': 0}]
            total = sum(t['dur'] for t in toks)
            if total != blen:
                sys.exit(f'{src}: battuta {bar["num"]} mano {hand}: durata {total}/16 invece di {blen}/16')
            for t in toks:
                stops = tie_open[staff]
                x.extend(note_xml(t, staff, stops))
                tie_open[staff] = set(t['notes']) if t.get('tie') else set()
            if staff == 1:
                x.append(f'<backup><duration>{blen}</duration></backup>')
        x.append('</measure>')
        parts.append(''.join(x))

    credits = []
    title = meta.get('title', src.stem)
    if meta.get('composer'):
        credits.append(f'<creator type="composer">{escape(meta["composer"])}</creator>')
    if meta.get('arranger'):
        credits.append(f'<creator type="arranger">{escape(meta["arranger"])}</creator>')
    # OSMD draws work-title as the title and movement-title as the subtitle
    work = f'<work><work-title>{escape(title)}</work-title></work>' + \
        (f'<movement-title>{escape(meta["subtitle"])}</movement-title>' if meta.get('subtitle') else '')
    xml = ('<?xml version="1.0" encoding="UTF-8"?>\n'
           '<!DOCTYPE score-partwise PUBLIC "-//Recordare//DTD MusicXML 4.0 Partwise//EN" '
           '"http://www.musicxml.org/dtds/partwise.dtd">\n'
           f'<score-partwise version="4.0">{work}<identification>{"".join(credits)}</identification>'
           '<part-list><score-part id="P1"><part-name>Piano</part-name></score-part></part-list>'
           '<part id="P1">\n' + '\n'.join(parts) + '\n</part></score-partwise>\n')
    out = src.parent.parent / 'pieces' / (src.stem + '.musicxml')
    out.write_text(xml, encoding='utf-8')
    if lessons:
        (out.parent / (src.stem + '.lessons.json')).write_text(
            json.dumps(lessons, ensure_ascii=False, indent=1) + '\n', encoding='utf-8')
    print(f'{out}: {len(bars)} battute, {len(lessons)} lezioni')


if __name__ == '__main__':
    for a in sys.argv[1:] or sorted(str(p) for p in (Path(__file__).parent.parent / 'sources').glob('*.txt')):
        convert(Path(a))
