# Learning design

Piano Practice teaches an adult beginner to read sheet music and play their own pieces. Every learning mechanic in
the app was checked against published research before it was built; this page lists what the app does, why, and how
strong the evidence is. Much music-learning research uses small groups, children or professionals, and almost none
studies adult beginners: where a conclusion comes from another field (memory research, motor learning) it says so.

Evidence strength: **strong** = many studies or meta-analyses · **medium** = a few consistent studies ·
**weak** = small studies, mixed results or teachers' opinion.

## The method

Four skills, in this order, a bit of each every day:

1. **Notes on the keyboard** – find every C (the white key left of the two black keys), then the others.
2. **Notes on the staff** – not one by one, but from **landmarks** (middle C, treble G on the second line, bass F on
   the fourth line) and counting steps (line → space → line). Treble first, then bass, then sharps, flats and key
   signatures.
3. **Rhythm** – note values and counting aloud.
4. **Reading a piece** – putting 1–3 together on real bars, slowly, with help that fades out.

## What the app does, and why

| Mechanic | Research | Strength |
|---|---|---|
| The quiz makes you **answer** (retrieval), never just re-read; after a mistake it shows the right answer | Testing effect: self-testing beats re-reading for retention over days and weeks, even when it feels less productive (Roediger & Karpicke 2006; "desirable difficulties", Bjork 1994) | strong (memory, not music) |
| Every note has a **review date**: 1 → 2 → 4 → 8 → 16 → 32 days after a first-try right answer (grows at most once a day), tomorrow after a mistake; "today's session" starts from the notes that are due | Spacing: the best gap is ~10–20 % of the time you want to remember for; too short hurts more than too long (Cepeda et al. 2008; Donovan & Radosevich 1999, 63 studies) | strong |
| A note counts as **known** only when it is right *and* fast: 3 first-try rights in a row, at least 2 of them under a per-level time (e.g. 2.5 s) | Sight-reading goes with recognition speed and pattern recognition (Waters et al.; eye–hand span studies) | medium |
| **Short daily sessions** (~15 min: review → quiz → sight reading → piece) | Distributed practice beats massed practice, though it depends on the task and the gap (Donovan & Radosevich 1999) | medium |
| **Loop the hard bars** until clean ("practise the weak spots") | Duke, Simmons & Cash 2009 (17 advanced pianists): neither total time nor repetitions predicted the next day's result; finding the hard spot and repeating it until correct did | medium (one small study) |
| **Sight reading** of short melodies the app generates: 4 bars in one five-finger position, mostly steps, start and end on the key note | Mishra 2014 meta-analysis (92 studies): a lot of new, easy music; improvisation and ear training are among the factors most linked to sight-reading | medium |
| **Statistics**: time per note, first-try %, slowest notes, practice minutes, days in a row | Self-regulation (plan → monitor → reflect) improves practice quality (McPherson & Zimmerman 2002/2011; Osborne et al. practice diaries) | medium |
| **One hint after a mistake**, never the answer: the black-key group on the keyboard, or "one step up ↑" with the landmark line highlighted on the staff | Guidance hypothesis: help that is always on boosts performance now but blocks learning to do without it (Salmoni et al. 1984; mixed but consistent evidence) | medium (motor learning) |
| **Staff from the middle out**: middle lines first, then all lines, then middle spaces, then all spaces; one step back when you forget a note of an earlier step | Landmark reading + small steps; confusions in real sessions were almost all line ↔ neighbouring space | weak (design choice, checked on usage data) |
| **Live review**: notes missed or slow *in this round* come back ~6× more often (never immediately: 2–3 questions in between) until right and on time twice in a row | Spacing within a session + testing effect | medium |
| **AFK detection**: more than 15 s without input, or the app in background, pauses the clock; that answer doesn't count as slow | Keeps the speed statistics honest | – |
| **Geometric feedback over text**: the same blue for the clef's line and its key, numbered steps on the staff and on the keys, the finger on the note | Fewer words, faster reading of the feedback | weak (design choice) |
| **Your own pieces** as material, plus a full path for everything else | Self-determination theory: autonomy and competence sustain practice (studies on music students) | weak–medium |

## Hidden hints removed

An audit of the quiz looked for ways to guess without reading. Each one inflated "known", and each was fixed (tests
in `NoteQuizTests`):

- consecutive notes were often neighbours, so you could count from the previous answer → a new note is at least 3
  steps away;
- the highlighted key was always in the same octave next to the "middle C" label → random octave;
- chord answers rarely contained the same root with the other mode → always included;
- the chord's keys were highlighted before answering → only after;
- a missed note came back after 1–2 questions (short-term memory) → not before 3;
- "train the 5 slowest" could be solved by elimination → one question in three from the rest of the level;
- a single black-key button gave the black key away → all five black-key names when any is in play;
- the key-signature reminder never went away → hidden for the notes you already know.

## What the research doesn't settle (and the app keeps simple)

- Rest between repetitions inside a session: opposite results depending on the task.
- Falling notes vs. sheet for the very first pieces: no independent research (only vendors' claims); the app starts
  with falling notes for motivation and the reading path moves you to the staff.
- Middle-C method vs. intervals: a hybrid (landmark notes + steps), as most teachers suggest.
- Deliberate practice explains only part of the result (21 % in music, Macnamara et al. 2014): success is measured in
  clean rounds, time per note and retention, not minutes.

## Sources

- Roediger & Karpicke 2006, *The Power of Testing Memory* – https://notes.andymatuschak.org/Testing_effect
- Cepeda, Vul, Rohrer, Wixted & Pashler 2008, *Spacing effects in learning* – https://www.evullab.org/pdf/CepedaVulRohrerWixtedPashler-PS-2008.pdf
- Donovan & Radosevich 1999, meta-analysis of distributed practice – https://www.gwern.net/docs/spaced-repetition/1999-donovan.pdf
- Carter & Grahn 2016, blocked vs. interleaved practice – https://www.ncbi.nlm.nih.gov/pmc/articles/PMC4989027/
- Duke, Simmons & Cash 2009, *It's not how much; it's how* – https://www.structural-learning.com/research-briefings/practise-the-hard-bit
- Simmons & Duke 2006, sleep and keyboard melody learning – https://cml.music.utexas.edu/research/skill-learning-and-procedural-memory
- Mental practice (reviews incl. Pascual-Leone 1995) – https://pmc.ncbi.nlm.nih.gov/articles/PMC3747442
- Guidance hypothesis – https://pmc.ncbi.nlm.nih.gov/articles/PMC4893479
- Mishra 2014, factors in sight-reading accuracy – https://profiles.umsl.edu/en/publications/factors-related-to-sight-reading-accuracy-a-meta-analysis/
- Eye–hand span in music reading – https://www.ncbi.nlm.nih.gov/pmc/articles/PMC8612695/
- Sound before symbol, review by Ausman 2022 – https://journalhosting.ucalgary.ca/index.php/cjnse/article/view/75284
- Self-regulation in music practice – https://www.frontiersin.org/articles/10.3389/fpsyg.2024.1324100
- Deliberate practice: Macnamara et al. 2014 – https://dx.doi.org/10.3389/fpsyg.2014.00751
