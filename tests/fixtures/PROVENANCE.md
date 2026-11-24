# Test fixture provenance

Everything here is MIT. The music is public domain, re-encoded by us; nothing is copied from another corpus. Regenerate with the script rather than hand-edit:

```sh
uv run --with music21==10.5.2 python -I tests/fixtures/generate-sc2.py
```

| File | Source | Version | SPDX | How |
|------|--------|---------|------|-----|
| `sc0/*.sexp` | the SC0 fixture scores of score-protocol (hand-built; the tunes and texts they name are public domain) | score-protocol 0.1.0 | MIT | copied from score-protocol `tests/fixtures/` |
| `golden/*.musicxml` | the SC0 scores, as `write-musicxml` must write them | — | MIT | `generate-sc2.py`: a second implementation of the rules in `src/writer.lisp`, with music-theory 0.5.1's MusicXML kind rules for `<harmony>`, independent of the Lisp code |
| `corpus/*.musicxml` | 20 public-domain pieces (table below), re-encoded by us; harmonies of the hymns are ours | — | MIT | `generate-sc2.py`, from the tune data in the script, written the way a notation program writes MusicXML: no ids, layout and playback elements the reader ignores, voices 1, 2, 5, 6 |
| `corpus/hymn-shared.musicxml` | *Tallis's Canon* (below) in hymnal layout: soprano and alto, tenor and bass, as shared-stem chords where their rhythms agree, a single note where they sing one pitch, two voices in bar 3 | — | MIT | `generate-sc2.py` (`shared_stems`), from the four voices of `hymn-split` |
| `lead-sheet.mxl` | `corpus/amazing-grace.musicxml` in a compressed archive as other programs write one: deflated entries, a PDF rendition listed first in `container.xml`, the score under `music/` | — | MIT | `generate-sc2.py`, with Python's `zipfile` |
| `sc2-facts.sexp` | what music21 reads in every golden and corpus file: measures, events (pitches, durations, tuplets, grace notes, ties, hidden rests, lyrics), harmonies (root, bass, realised tones), keys, meters, metronome marks | music21 10.5.2 | MIT (generated facts; music21 itself is BSD-3-Clause) | same script. It also computes these facts from its own model of each file and stops when music21 disagrees |
| `sc2-lost.sexp` | per SC0 score, the `lossy-conversion` warnings of `write-musicxml` | — | MIT | same script, from the rules of `src/writer.lisp` |

Every golden and corpus file validates against the MusicXML 4.0 XSD (github.com/w3c/musicxml, tag v4.0) with `xmllint --nonet` and the schema's `catalog.xml`, checked when the fixtures were generated.

| Corpus file | Piece and source |
|-------------|------------------|
| `corpus/amazing-grace.musicxml` | *Amazing Grace*: tune New Britain (1829); text John Newton (1779) |
| `corpus/greensleeves.musicxml` | *Greensleeves*: English, 16th century; text from the 1580 broadside |
| `corpus/scarborough-fair.musicxml` | *Scarborough Fair*: English traditional ballad, as printed in the 19th century |
| `corpus/oh-susanna.musicxml` | *Oh! Susanna*: Stephen Foster (1848) |
| `corpus/red-river-valley.musicxml` | *Red River Valley*: North American traditional song, published 1896 |
| `corpus/home-on-the-range.musicxml` | *Home on the Range*: Daniel E. Kelley, text Brewster M. Higley (1872) |
| `corpus/shenandoah.musicxml` | *Shenandoah*: American traditional, 19th century |
| `corpus/londonderry-air.musicxml` | *Londonderry Air*: Irish traditional air, printed by George Petrie (1855); no text |
| `corpus/auld-lang-syne.musicxml` | *Auld Lang Syne*: Scots traditional tune; text Robert Burns (1788) |
| `corpus/silent-night.musicxml` | *Silent Night*: Franz Xaver Gruber (1818); English text John Freeman Young (1859) |
| `corpus/simple-gifts.musicxml` | *Simple Gifts*: Joseph Brackett (1848) |
| `corpus/yankee-doodle.musicxml` | *Yankee Doodle*: American traditional, 18th century |
| `corpus/when-the-saints.musicxml` | *When the Saints Go Marching In*: African-American spiritual, traditional |
| `corpus/swing-low.musicxml` | *Swing Low, Sweet Chariot*: African-American spiritual, attributed to Wallace Willis (before 1862) |
| `corpus/twinkle-twinkle.musicxml` | *Twinkle, Twinkle, Little Star*: French melody *Ah! vous dirai-je, maman* (1761); text Jane Taylor (1806) |
| `corpus/frere-jacques.musicxml` | *Frère Jacques*: French traditional round, 18th century (two parts, the second entering in bar 3) |
| `corpus/joy-to-the-world.musicxml` | *Joy to the World*: arranged by Lowell Mason (1839); text Isaac Watts (1719) |
| `corpus/camptown-races.musicxml` | *Camptown Races*: Stephen Foster (1850) |
| `corpus/old-hundredth.musicxml` | *Old Hundredth*: Genevan Psalter (1551); text William Kethe (1561); harmony ours |
| `corpus/hymn-to-joy.musicxml` | *Hymn to Joy*: Ludwig van Beethoven (1824); text Friedrich Schiller (1785); harmony ours |
| `corpus/hymn-split.musicxml`, `corpus/hymn-shared.musicxml` | *Tallis's Canon*: Thomas Tallis (1567); text Thomas Ken (1674); harmony ours |

The events of each voice have ids of their own (`p1v2t5`: part, voice, serial), so a slur or hairpin of the tune data belongs to one voice. Until 0.1.1 every voice of a tune numbered its events from `t1`, and `corpus/old-hundredth.musicxml` repeated the soprano's crescendo in the alto, tenor and bass (#3); regenerating changed only that file. `tests/sc21-regression-test.lisp` pins the spanners of every corpus file.

Melodies are first phrases, re-encoded from memory of the public-domain tunes; structure marks some pieces carry (the D.S. al Coda of *Camptown Races*, the endings of *Yankee Doodle*, the key change of *Hymn to Joy*, the meter changes of *Shenandoah*) are ours, there to exercise the reader.

The brief also lists MusicXML files exported by MuseScore 4. No MuseScore was available when these fixtures were made; the MuseScore round trip belongs to score-parity's MuseScore oracle (slice SC5).

## Where our conventions differ from music21

- **Units.** Offsets and durations are whole notes; music21's are quarter notes. The script divides by 4.
- **Voices.** music21 makes `Voice` objects only in a measure whose staff holds two or more voices. A fact's voice is the voice's rank in its part (by `<voice>` value, as the reader orders voices) in such measures, and NIL elsewhere.
- **`suspended-fourth` with an added 7.** music21 adds a major seventh (G C D F♯), although MusicXML defines an added degree's alter relative to the dominant chord (a minor seventh). music-theory 0.5.1 admits no added 7 at all, so the reader reports such a harmony unsupported. The corpus avoids the form; `tests/sc2-harmony-test.lisp` pins the behaviour.
- **What music21 doesn't read.** It ignores `id` attributes, `<player>` and the measure `text` attribute, and keeps a text-only tempo direction as a text expression. Ids, voice names, number labels and text-only tempo marks are checked by hand-written tests instead; tempo facts list metronome marks only.
- **Chord tones.** music21's chord pitches include a slash bass. Both sides of a harmony fact are the tones plus the bass, as a set of pitch-class names.
- **Text.** music21 writes flats as `-`; facts use `b` (`Bb4`), as music-theory prints them.
