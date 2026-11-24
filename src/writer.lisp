;;;; SC2 writing a score as MusicXML 4.0 partwise.
;;;;
;;;; WRITE-MUSICXML score &optional destination → with DESTINATION NIL, the
;;;; MusicXML text (a string); with a pathname, the file is written (UTF-8,
;;;; superseding) and the pathname returned; with a character stream, the text is
;;;; written to it and the stream returned. The text is
;;;; (xml-protocol:encode (score-to-musicxml score) :pretty t :declaration t):
;;;; xml-backend-native's layout (an XML declaration line, two-space
;;;; indentation, one element per line, an element whose only child is text on
;;;; one line, an empty element as <name/>), so equal scores give equal bytes.
;;;; After writing it signals LOSSY-CONVERSION with WARN, FORMAT :MUSICXML, once
;;;; for each of these WHATs that applies, in this order:
;;;;   "provenance and confidence"  an element has PROVENANCE or CONFIDENCE;
;;;;   "chord-symbol text"          an anchor's symbol has TEXT or DIALECT;
;;;;   "chord-symbol kind"          CHORD-SYMBOL-TO-HARMONY lost a symbol's kind;
;;;;   "notated value"              a grace event or a tempo mark's beat unit has
;;;;                                no notated value (DURATION-DOTS gives NIL).
;;;;
;;;; SCORE-TO-MUSICXML score → a fresh xml-protocol XML-DOCUMENT: the DOCTYPE of
;;;; +MUSICXML-DOCTYPE+ and the root below. Attributes are written in the order
;;;; shown; [..] is written only when its condition holds; integers print with
;;;; ~D. A DECIMAL prints an integer with ~D, a ratio whose denominator has no
;;;; prime factor but 2 and 5 as its exact decimal (145/2 → "72.5"), anything
;;;; else (a float is RATIONALIZEd first) rounded to two decimals with trailing
;;;; zeros dropped.
;;;;
;;;; <score-partwise version="4.0">
;;;;   [<work><work-title>TITLE</work-title></work>]   TITLE or SUBTITLE; the
;;;;                          title is "" (<work-title/>) when only SUBTITLE is set
;;;;   [<movement-title>SUBTITLE</movement-title>]
;;;;   [<identification>]     a COMPOSER, LYRICIST, ARRANGER or COPYRIGHT:
;;;;     <creator type="composer|lyricist|arranger">..</creator> each present, in
;;;;     +METADATA-CREATORS+ order, then [<rights>COPYRIGHT</rights>]
;;;;   <part-list> one per part:
;;;;     <score-part id=PART-ID>
;;;;       <part-name>NAME</part-name>              (<part-name/> for NIL)
;;;;       [<part-abbreviation>ABBREVIATION</part-abbreviation>]
;;;;       <player id=VOICE-ID><player-name>NAME</player-name></player>  one per
;;;;                          voice, in voice order (<player-name/> for NIL)
;;;;   <part id=PART-ID> one per part, each holding one <measure> per measure.
;;;;
;;;; Per part. The voices are numbered k = 1, 2, ... in part order: notes and
;;;; directions of voice k carry <voice>k</voice>. When the part has two or more
;;;; staves they also carry <staff>s</staff> (s the voice's STAFF); with one
;;;; staff, no <staff>. Durations are in the part's DIVISIONS D: the least
;;;; positive integer with 4 D x an integer for every x among the part's
;;;; non-grace event durations, every BAR-LENGTH of the score and, in the first
;;;; part, every tempo-mark offset and chord-symbol anchor offset. A length x is
;;;; written as the integer 4 D x.
;;;;
;;;; <measure number=LABEL [text=NUMBER] [implicit="yes"] id=SLICE>, where LABEL
;;;; is the bar number (~D: 0 for a pickup), text is the measure's NUMBER when it
;;;; isn't NIL, implicit for a pickup, and SLICE is (slice-id measure-id
;;;; part-id). Inside, in this order:
;;;;   1. <attributes> in measure 0, and where TIME or KEY is set:
;;;;        [<divisions>D</divisions>]                  measure 0
;;;;        [<key><fifths>F</fifths><mode>major|minor</mode></key>]   KEY: F is
;;;;                          (key-signature key)
;;;;        [<time><beats>B</beats><beat-type>T</beat-type></time>]   TIME: B the
;;;;                          numerators joined by "+", T the denominator
;;;;        [<staves>S</staves>]                        measure 0, S >= 2 staves
;;;;        <clef [number=k] id=STAFF-ID><sign>..</sign><line>..</line>
;;;;          [<clef-octave-change>c</clef-octave-change>]</clef>   measure 0,
;;;;                          one per staff in order, by +CLEF-SIGNS+; number
;;;;                          only with S >= 2; the change only when not 0.
;;;;      Every part writes the measure's TIME and KEY; the reader uses the first.
;;;;   2. <barline location="left" [id=ENDING-ID]> when REPEAT-START or ENDING:
;;;;        [<bar-style>heavy-light</bar-style>]        REPEAT-START
;;;;        [<ending number=PASSES type="start"/>]      ENDING; PASSES ~D joined
;;;;                          by ", "; the id only in the first part
;;;;        [<repeat direction="forward"/>]             REPEAT-START
;;;;   3. The measure track, first part only. Its items, sorted by offset, then
;;;;      by rank, then in stored order: the rehearsal mark (offset 0, rank 0);
;;;;      :SEGNO and :CODA jump marks (0, rank 1); tempo marks (their OFFSET,
;;;;      rank 2); the measure's chord-symbol anchors (their offset, rank 3); the
;;;;      other jump marks (the bar's length, rank 4). From cursor 0, an item
;;;;      past the cursor is preceded by <forward><duration>..</duration>
;;;;      </forward> to its offset. After the last item, when the cursor isn't 0,
;;;;      <backup> to 0. Items:
;;;;        rehearsal  <direction id=ID><direction-type><rehearsal>TEXT
;;;;                   </rehearsal></direction-type></direction>
;;;;        jump       <direction id=ID>, then for :SEGNO <direction-type><segno/>
;;;;                   </direction-type>, for :CODA <direction-type><coda/>
;;;;                   </direction-type>, for the others <direction-type><words>
;;;;                   WORDS</words></direction-type>; then <sound ATTR=VALUE/>;
;;;;                   WORDS, ATTR, VALUE from +JUMP-DIRECTIONS+
;;;;        tempo      <direction id=ID>, then [<direction-type><words>TEXT</words>
;;;;                   </direction-type>] when TEXT, [<direction-type><metronome>
;;;;                   <beat-unit>TYPE</beat-unit> <beat-unit-dot/>... <per-minute>
;;;;                   BPM</per-minute></metronome></direction-type>] when TEMPO
;;;;                   and its beat unit has a notated value (TYPE and dots from
;;;;                   DURATION-DOTS by +NOTE-TYPES+, BPM a DECIMAL), then
;;;;                   <sound tempo=Q/> with Q = bpm x beat-unit x 4 (quarter
;;;;                   notes a minute, a DECIMAL) when TEMPO, else <sound/>
;;;;        anchor     CHORD-SYMBOL-TO-HARMONY with :id (harmony.lisp)
;;;;   4. The voices, in part order, each with a non-empty voice measure: when the
;;;;      cursor isn't 0, <backup> to 0 first. Then per event, in order:
;;;;        a. its DYNAMIC: <direction id=ID><direction-type><dynamics><VALUE/>
;;;;           </dynamics></direction-type><voice>k</voice>[<staff>s</staff>]
;;;;           </direction>
;;;;        b. per hairpin (score-spanners order) starting on the event:
;;;;           <direction id=SPANNER-ID><direction-type><wedge type="crescendo|
;;;;           diminuendo" number=n/></direction-type><voice>k</voice>[<staff>]
;;;;           </direction>
;;;;        c. its notes (below); the cursor advances by a non-grace DURATION
;;;;        d. per hairpin ending on the event: as b without id, type="stop".
;;;;      Hairpin numbers n: per part, in writing order, the least n >= 1 not
;;;;      held by a hairpin started and not yet stopped. Slurs number the same
;;;;      way, separately.
;;;;   5. <barline location="right"> when BARLINE isn't :REGULAR, REPEAT-END, or
;;;;      an ending's last measure (start + MEASURES - 1):
;;;;        [<bar-style>STYLE</bar-style>]              by +BAR-STYLES+
;;;;        [<ending number=PASSES type="stop|discontinue"/>]   "stop" when the
;;;;                          measure has REPEAT-END, else "discontinue"
;;;;        [<repeat direction="backward" [times=N]/>]  REPEAT-END, times unless 2
;;;;
;;;; Notes. A note or rest event is one <note>; a chord event one per chord note,
;;;; in order, the second and later with <chord/>. Each <note>:
;;;;   <note [print-object="no"] id=ID>     print-object for a hidden rest; ID the
;;;;                          event's, a chord note's own
;;;;     [<grace/> | <grace slash="yes"/>]  :APPOGGIATURA | :ACCIACCATURA
;;;;     [<chord/>]
;;;;     <pitch><step>L</step>[<alter>a</alter>]<octave>o</octave></pitch>
;;;;       | <rest/> | <rest measure="yes"/>          alter only when not 0
;;;;     [<duration>..</duration>]          non-grace
;;;;     [<tie type="stop"/>] [<tie type="start"/>]   the note is a tie's END /
;;;;                          has a TIE
;;;;     <voice>k</voice>
;;;;     [<type>..</type> <dot/>...]        the notated value by DURATION-DOTS
;;;;                          (with :TUPLET; a grace's DURATION is already
;;;;                          notated), not for a measure rest or without one
;;;;     [<accidental [cautionary="yes"]>NAME</accidental>]   ACCIDENTAL :FORCED
;;;;                          (:CAUTIONARY), NAME by +ACCIDENTAL-NAMES+
;;;;     [<time-modification><actual-notes>n</actual-notes><normal-notes>m
;;;;       </normal-notes></time-modification>]   TUPLET n/m in lowest terms
;;;;     [<stem>up|down</stem>]             the voice's STEM, pitched notes only
;;;;     [<staff>s</staff>]
;;;;     [<notations [id=EVENT-ID]>]        id on a chord's first note, which
;;;;                          always has <notations>; other notes when not empty:
;;;;       [<tied type="stop"/>] [<tied type="start" id=TIE-ID/>]
;;;;       first note only: per slur ending on the event <slur type="stop"
;;;;       number=n/>, then per slur starting <slur type="start" number=n
;;;;       id=SPANNER-ID/>; per articulation <articulations id=ID><ELEMENT/>
;;;;       </articulations> (+ARTICULATION-ELEMENTS+); the breath mark as
;;;;       <articulations id=ID><breath-mark/></articulations>; the fermata as
;;;;       <fermata id=ID>CONTENT</fermata> (+FERMATA-SHAPES+)
;;;;     first note only, per lyric: <lyric number=VERSE id=ID><syllabic>..
;;;;       </syllabic><text>TEXT</text>[<extend/>]</lyric>
;;;;
;;;; Ids. Every element's id is written once, on the carrier reader.lisp reads
;;;; it from (a measure's as the slice ids of its <measure>s; measure-level marks
;;;; and chord symbols in the first part only), so the id attributes of the
;;;; document are exactly the element ids plus one slice id per measure and part,
;;;; each once, besides <part id>, which refers to its <score-part>.
;;;;
;;;; Round trip. For a score s with no CHECK-SCORE issues,
;;;; (read-musicxml (write-musicxml s)) is SCORE-EQUAL to s after these changes,
;;;; which are all the format loses: PROVENANCE and CONFIDENCE NIL everywhere;
;;;; chord symbols' TEXT and DIALECT NIL; a symbol whose kind was lost read back
;;;; as HARMONY-TO-CHORD-SYMBOL reads its <harmony>; a grace with no notated
;;;; value read back as 1/8, a tempo whose beat unit has none as (Q, 1/4); a
;;;; voice with no events on STAFF 1, and a voice with no pitched note with STEM
;;;; NIL; an empty part name NIL; SCORE-SPANNERS in the document order of their
;;;; starts (part, measure, voice, event; on one event hairpins before slurs).

(in-package #:score-backend-musicxml)

(defun write-musicxml (score &optional destination)
  "SCORE as MusicXML text, to DESTINATION (file header)."
  (declare (ignore score destination))
  (%sc2-pending 'write-musicxml))

(defun score-to-musicxml (score)
  "SCORE as an xml-protocol XML-DOCUMENT (file header)."
  (declare (ignore score))
  (%sc2-pending 'score-to-musicxml))
