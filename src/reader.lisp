;;;; SC2 reading MusicXML 4.0 partwise into a score.
;;;;
;;;; READ-MUSICXML source &key split-voices (unsupported :error) → a SCORE.
;;;; SOURCE is a pathname (a file), a string (the MusicXML text itself), an octet
;;;; vector (UTF-8) or a character stream. It is decoded with xml-protocol
;;;; (*XML-BACKEND*, xml-backend-native) and handed to MUSICXML-TO-SCORE.
;;;; The DOCTYPE's external subset is never fetched: xml-protocol refuses it with
;;;; an XML-ENTITY-ERROR whose message names the external DTD subset and offers
;;;; CONTINUE, and the reader invokes that CONTINUE. Any other XML-ERROR (input
;;;; that isn't well-formed, an external entity) is a SCORE-FORMAT-ERROR with
;;;; FORMAT :MUSICXML, CAUSE the XML-ERROR and POSITION (line . column) from it.
;;;;
;;;; MUSICXML-TO-SCORE document &key split-voices (unsupported :error) → a SCORE,
;;;; from an xml-protocol XML-DOCUMENT. SPLIT-VOICES is NIL or :AUTO (voices.lisp:
;;;; the score read here, then SPLIT-VOICES); UNSUPPORTED is :ERROR, :WARN or
;;;; :SKIP (below). Other values are TYPE-ERRORs.
;;;;
;;;; Text values are trimmed of XML whitespace. "Decimal" means an optional
;;;; "-", digits, and optionally "." and digits, read as an exact rational
;;;; ("0.5" is 1/2). Durations and offsets are whole notes; a MusicXML duration
;;;; d in a part whose current <divisions> is D is d / (4 D).
;;;;
;;;; Document. The root element must be <score-partwise> (else SCORE-FORMAT-ERROR,
;;;; POSITION its path); its version attribute is not checked, so 3.x files read
;;;; with the 4.0 vocabulary. Elements are classified by +ELEMENT-CONTEXTS+
;;;; (tables.lisp). <part-list> lists the <score-part>s; the <part>s follow, each
;;;; with the id of a score-part, in part-list order (a part whose id names no
;;;; score-part, a score-part with no part, and a part with a different number
;;;; of <measure>s than the first are SCORE-FORMAT-ERRORs). Measure i of every
;;;; part is measure i of the measure map.
;;;;
;;;; The cursor. Each part's measure is read in document order with a cursor, a
;;;; position from the measure's start, 0 at <measure>. A <note> without <chord>
;;;; and without <grace> starts at the cursor and advances it by its duration; a
;;;; <chord> note starts where the previous <note> of the measure started and
;;;; doesn't move it (its own <duration>, <voice> and <type> are ignored); a grace
;;;; note starts at the cursor and doesn't move it. <forward> advances and
;;;; <backup> moves back by their <duration> (a backup past the measure start is a
;;;; SCORE-FORMAT-ERROR). The POSITION of a <direction>, <harmony> or measure
;;;; <sound> is the cursor, plus its <offset> (decimal divisions) when it has one.
;;;; <divisions> (a decimal > 0) applies from its <attributes> on, across
;;;; measures; a <duration> (a decimal > 0) before any is a SCORE-FORMAT-ERROR, as
;;;; is a non-grace note without one.
;;;;
;;;; The measure map. Measure-level facts come from the first part only; in the
;;;; other parts <time>, <key>, <barline> and the measure-level directions below
;;;; are dropped silently. For measure i:
;;;;   L        the largest cursor position reached in the measure in any part.
;;;;   TIME     the <time> of the first part's measure: one <beats> and one
;;;;            <beat-type>, read as (parse-meter "beats/beat-type") ("3+2" beats
;;;;            are additive); the symbol attribute is display. Two pairs,
;;;;            <interchangeable> or <senza-misura>: unsupported, ELEMENT "time".
;;;;   KEY      the <key> without a number attribute, or with number "1": <fifths>
;;;;            an integer -7..7 and <mode> "major" (also when absent) or "minor";
;;;;            the tonic is (fifths-pitch-class (+ fifths (if minor 3 0))). Other
;;;;            modes, non-traditional keys (<key-step>...): unsupported, ELEMENT
;;;;            "key". A <time> or <key> after the cursor has left 0: unsupported
;;;;            (mid-measure change), ELEMENT "time" or "key".
;;;;   PICKUP-P i = 0, implicit="yes", and 0 < L < the meter's bar.
;;;;   LENGTH   L when L > 0 and L isn't the bar of the meter in force, else NIL.
;;;;   NUMBER   the text attribute when it is present and not empty; else the
;;;;            number attribute when it differs from the bar's default label, the
;;;;            decimal bar number (score-protocol bars: 0 for a pickup, then 1,
;;;;            2, ...); else NIL. So number="3" text="3" keeps "3", and
;;;;            number="3" on bar 3 reads NIL.
;;;;   BARLINE  the <bar-style> of the <barline location="right"> by
;;;;            +BAR-STYLES+; absent → :REGULAR. Other styles: unsupported, ELEMENT
;;;;            "bar-style". The left barline's style is ignored. <barline
;;;;            location="middle">: unsupported, ELEMENT "barline".
;;;;   REPEAT-START  a <repeat direction="forward"> on the left barline.
;;;;   REPEAT-END    a <repeat direction="backward"> on the right barline: its
;;;;            times attribute when it is an integer >= 2, else 2. A repeat on the
;;;;            other side: unsupported, ELEMENT "repeat".
;;;;   ENDING   an <ending type="start"> on the left barline. PASSES: its number
;;;;            attribute, positive integers separated by commas and/or spaces
;;;;            ("1, 2", "1,2", "1 2"; else unsupported, ELEMENT "ending").
;;;;            MEASURES: up to and including the first measure j >= i whose right
;;;;            barline has an <ending> of type "stop" or "discontinue"; without
;;;;            one, up to the measure before the next ending start, else the last
;;;;            measure. A second ending start in one measure: unsupported.
;;;;   JUMP, TEMPO, REHEARSAL  from the first part's directions (Directions).
;;;;
;;;; Parts, staves, voices. A part's NAME and ABBREVIATION are the texts of
;;;; <part-name> and <part-abbreviation>, NIL when empty or absent. STAVES: the
;;;; first <staves> of the part, at least the largest <staff> or clef number
;;;; used, default 1. Staff k's CLEF is set by the first <clef> with number k
;;;; (absent number = 1): sign, line and <clef-octave-change> (absent 0) by
;;;; +CLEF-SIGNS+, else unsupported, ELEMENT "clef"; default :TREBLE. A later
;;;; clef for the staff that gives the same keyword is ignored; a different one
;;;; is unsupported (the model has one clef per staff), ELEMENT "clef".
;;;; VOICES. Each note's voice value is its <voice> text, "1" when absent. When
;;;; the score-part has P >= 1 <player>s and every voice value in the part is a
;;;; decimal integer 1..P, the part has P voices, voice k taking the value "k",
;;;; its NAME the text of player k's <player-name> (NIL when empty). Otherwise
;;;; players are ignored and the voices are the distinct voice values: integer
;;;; values ascending, then the others in order of first appearance; a part with
;;;; no notes has one voice, value "1". A voice's STAFF is the <staff> (default
;;;; 1) of its first note, 1 for a voice with no notes. Its STEM is :UP (:DOWN)
;;;; when at least one of its <note>s has <stem> up (down) and none has the
;;;; other; else NIL. Notes on another staff than their voice's stay in the
;;;; voice (cross-staff notation is layout).
;;;;
;;;; Events. Each <note> without <chord> makes an event in its voice at its
;;;; onset; <chord> notes join the event of the previous <note> of the measure.
;;;;   REST-EVENT    <rest>. MEASURE-REST-P: measure="yes". HIDDEN-P: the note's
;;;;                 print-object="no" (display-step and display-octave are
;;;;                 ignored). A rest with <chord>: unsupported, ELEMENT "note".
;;;;   NOTE-EVENT    one <pitch> note; CHORD-EVENT when <chord> notes join it,
;;;;                 its NOTES the CHORD-NOTEs in document order.
;;;;   PITCH         <step> A-G and <octave> an integer (else SCORE-FORMAT-ERROR),
;;;;                 <alter> a decimal that must be an integer -2..2 (else
;;;;                 unsupported, ELEMENT "note"); absent = 0.
;;;;   ACCIDENTAL    :CAUTIONARY when the note has an <accidental> with
;;;;                 cautionary, parentheses, bracket or editorial "yes";
;;;;                 :FORCED for any other <accidental>; :AUTO without one. The
;;;;                 accidental's own value is display.
;;;;   DURATION      the first note's duration; for a grace note the notated
;;;;                 value of its <type> (+NOTE-TYPES+) and <dot>s, 1/8 when the
;;;;                 type is absent or outside the table. <type> and <dot> of
;;;;                 other notes are display.
;;;;   TUPLET        <time-modification> actual-notes / normal-notes (both
;;;;                 positive integers), NIL when absent or when the ratio is 1.
;;;;                 <tuplet> notations (brackets) are ignored.
;;;;   GRACE         <grace>: :ACCIACCATURA when slash="yes", else :APPOGGIATURA.
;;;;   <unpitched> and <cue> notes: unsupported, ELEMENT "note".
;;;; Within a voice's measure, events are in onset order (document order among
;;;; equal onsets). An event that starts before the previous non-grace event of
;;;; its voice ends: unsupported, ELEMENT "note" (two voices under one voice
;;;; value). Gaps: in a voice measure with at least one event, every stretch of
;;;; [0, L) not covered by its events (before, between or after them) is filled
;;;; with hidden rests (HIDDEN-P T), the pieces of (music-theory:split-duration
;;;; gap :meter (bar meter) :offset o), where o is the gap's start, plus the
;;;; meter's bar minus L in a pickup; one rest of the gap's length when
;;;; SPLIT-DURATION signals MUSIC-THEORY-ERROR. A voice with no event in a
;;;; measure has an empty voice measure there.
;;;;
;;;; Ties. A note with <tie type="start"> or <notations><tied type="start"> has a
;;;; TIE whose END is the id of the first note, in document order, of the same
;;;; voice whose event starts at the note's onset + its event's duration (in the
;;;; same or a later measure) and whose pitch is EQUALP; a note event or a chord
;;;; note. With no such note: unsupported, ELEMENT "tie" (or "tied" when the note
;;;; has no <tie> start); skipping drops the tie. Stop markers are not needed.
;;;;
;;;; Notations, on the note's event (any note of a chord gives the chord's):
;;;;   <slur>          per part, by number (default 1), in document order: a
;;;;                   start opens; a stop closes the latest open slur of that
;;;;                   number. A SPANNER :SLUR from the start note's event to the
;;;;                   stop note's. A stop with nothing open, and a slur still open
;;;;                   at the end of the part: unsupported, ELEMENT "slur".
;;;;                   type="continue" is ignored.
;;;;   <articulations> each child by +ARTICULATION-ELEMENTS+ an ARTICULATION;
;;;;                   <breath-mark> (any content) the BREATH-MARK.
;;;;   <fermata>       the FERMATA, SHAPE by content (+FERMATA-SHAPES+, empty =
;;;;                   :NORMAL; other shapes unsupported, ELEMENT "fermata"). A
;;;;                   second fermata on one event: unsupported, ELEMENT "fermata".
;;;;   <dynamics>      the event's DYNAMIC, as for directions below.
;;;; A second breath mark on an event is unsupported, ELEMENT "breath-mark".
;;;;
;;;; Lyrics (<lyric> on any note of the event, in document order):
;;;;   VERSE     the number attribute: a decimal integer >= 1, else the integer
;;;;             its trailing ASCII digits spell when >= 1 ("verse2" → 2,
;;;;             "part1verse3" → 3), else 1; absent → 1.
;;;;   TEXT      the <text>s joined by the content of the <elision> between them,
;;;;             "‿" (U+203F) when that is empty.
;;;;   SYLLABIC  the first <syllabic> by +SYLLABIC-NAMES+, :SINGLE when absent;
;;;;             other values unsupported, ELEMENT "lyric".
;;;;   EXTENDER  an <extend> with no type attribute or type "start".
;;;; A lyric without <text> (a melisma's continuation) makes no LYRIC. <laughing>
;;;; and <humming>: unsupported, ELEMENT "lyric".
;;;;
;;;; Directions (<direction>, and a <sound> child of <measure>, read as a
;;;; direction holding only that sound). A direction is, by the first that holds:
;;;;   a JUMP      when it has a <segno> or <coda> direction-type, a <sound> with
;;;;               tocoda, fine, dacapo, dalsegno, segno or coda, or <words> that
;;;;               match a jump: one JUMP-MARK per <segno> and per <coda>; one for
;;;;               the sound's tocoda (:TO-CODA), fine (:FINE), dacapo="yes" or
;;;;               dalsegno (the :DA-CAPO or :DAL-SEGNO row of +JUMP-DIRECTIONS+
;;;;               whose words match the direction's <words>, else :DA-CAPO or
;;;;               :DAL-SEGNO); a sound segno or coda attribute without the
;;;;               matching direction-type adds :SEGNO or :CODA; with no sound
;;;;               jump attribute, one per <words> matching a row's WORDS or
;;;;               OTHER-WORDS (STRING-EQUAL, trimmed).
;;;;   a TEMPO     when it has a <metronome>, a <sound> with a tempo attribute, or
;;;;               <words> and a <sound>: one TEMPO-MARK at OFFSET = the
;;;;               direction's position, TEXT the <words> texts joined by " " (NIL
;;;;               without words), TEMPO from the metronome (BPM: <per-minute>, a
;;;;               decimal > 0; BEAT-UNIT: <beat-unit> by +NOTE-TYPES+ with its
;;;;               <beat-unit-dot>s), else from sound tempo (BPM that decimal,
;;;;               BEAT-UNIT 1/4), else NIL. A metronome with a second <beat-unit>
;;;;               (a metric modulation) or without a decimal per-minute:
;;;;               unsupported, ELEMENT "metronome".
;;;; and, in any direction:
;;;;   <rehearsal> the measure's REHEARSAL-MARK (TEXT its text); a second one in a
;;;;               measure is unsupported, ELEMENT "rehearsal".
;;;;   <dynamics>  each child (+ELEMENT-CONTEXTS+ "dynamics" row) a DYNAMIC-MARK
;;;;               with that VALUE, on the event of the direction's target voice
;;;;               found by ATTACHMENT. A second dynamic for one event:
;;;;               unsupported, ELEMENT "dynamics".
;;;;   <wedge>     type "crescendo" or "diminuendo" opens a hairpin SPANNER
;;;;               (:CRESCENDO, :DIMINUENDO) whose START is found by ATTACHMENT;
;;;;               type "stop" closes the latest open wedge of the part with its
;;;;               number (default 1); END is START when the stop's absolute
;;;;               position is START's onset, else the last event, read from a
;;;;               <note>, of the stop's target voice whose absolute onset is
;;;;               before the stop's position. A stop with nothing open, no END,
;;;;               or a wedge still open at the end of the part: unsupported,
;;;;               ELEMENT "wedge".
;;;;               type "continue" is ignored.
;;;;   <words>     not part of a jump or a tempo: unsupported, ELEMENT "words"
;;;;               (free text has no place in the model).
;;;; Jumps, tempo marks and rehearsal marks belong to the measure map: they are
;;;; read in the first part only. JUMP holds the measure's jump marks, TEMPO its
;;;; tempo marks (sorted by offset by MAKE-MEASURE-INFO).
;;;; ATTACHMENT. The direction's target voice is its <voice> value's voice; else
;;;; the part's first voice whose STAFF is the direction's <staff> (default 1);
;;;; else the part's first voice. The mark goes on the first event of the target
;;;; voice, read from a <note> after the direction in document order and in the
;;;; same measure, that starts at or after the direction's position; failing
;;;; that, on the last event of the target voice in the measure that starts at or
;;;; before the position; failing that it is unsupported (ELEMENT "dynamics" or
;;;; "wedge").
;;;;
;;;; Chord symbols. The <harmony> elements of the first part that has any (those
;;;; of other parts are dropped silently) become CHORD-SYMBOL-ANCHORs at (bar .
;;;; position), SYMBOL by HARMONY-TO-CHORD-SYMBOL (harmony.lisp).
;;;;
;;;; Metadata (SCORE-METADATA): :TITLE the text of <work>/<work-title> when that
;;;; element exists, else of <movement-title>; :SUBTITLE the text of
;;;; <movement-title> when a <work-title> exists; :COMPOSER, :LYRICIST,
;;;; :ARRANGER the first <identification>/<creator> of each +METADATA-CREATORS+
;;;; type; :COPYRIGHT the first <rights>. Empty texts are left out.
;;;;
;;;; Ids. An element takes the id attribute of its carrier when the value is
;;;; VALID-ID-P and no element before it in document order (score-protocol
;;;; ids.lisp) already took it; every other element gets the id MAKE-SCORE mints
;;;; for it (the score is built by MAKE-SCORE from the elements and the file's
;;;; ids, with :ID-COUNTER 0, so a file read twice gives the same ids). Carriers:
;;;;   measure       the first part's <measure> id, when it is a slice id M.P
;;;;                 (score-protocol SLICE-ID) with P the first part's id: M
;;;;   part          <score-part> id
;;;;   staff         the clef that set its CLEF
;;;;   voice         its <player> (when players define the voices)
;;;;   note event, rest event  its <note>
;;;;   chord event   the first <notations> of its first <note>
;;;;   chord note    its <note>
;;;;   lyric         <lyric>; fermata: <fermata>; tie: the <tied type="start">
;;;;   articulation, breath mark  the <articulations> holding it, for its first
;;;;                 child only
;;;;   dynamic       its <direction>, or <dynamics> inside <notations>
;;;;   slur          the <slur type="start">; hairpin: the <direction> of its start
;;;;   tempo mark, rehearsal mark, jump mark  their <direction>
;;;;   ending        the left <barline> of the first part that starts it
;;;;   chord-symbol anchor  <harmony>
;;;; A <direction> that yields several elements gives its id to the first, in
;;;; the order jump marks, tempo mark, rehearsal mark, dynamics, hairpin start.
;;;; Gap-filling hidden rests have no carrier. PROVENANCE and CONFIDENCE are NIL
;;;; on everything the reader makes (SPLIT-VOICES sets them on its guesses).
;;;;
;;;; Unsupported. Content outside the model (an UNSUPPORTED element of
;;;; tables.lisp, or a case marked unsupported above) is handled by UNSUPPORTED:
;;;;   :ERROR  (default) MUSICXML-UNSUPPORTED is signalled with ERROR: FORMAT
;;;;           :MUSICXML, ELEMENT the local name stated (the element that skipping
;;;;           drops), POSITION its path, REASON a short phrase, CAUSE NIL unless
;;;;           stated. It is inside a SKIP-ELEMENT restart: the element is dropped
;;;;           and reading goes on as if it weren't in the file. Unhandled, the
;;;;           error ends the read.
;;;;   :WARN   the element is dropped and LOSSY-CONVERSION is signalled with WARN,
;;;;           FORMAT :MUSICXML and WHAT "<name>" (the element's name in angle
;;;;           brackets).
;;;;   :SKIP   the element is dropped silently.
;;;; A path is "/" followed by the steps from the root to the element, joined by
;;;; "/", each NAME[k] with k its 1-based index among the siblings of that name:
;;;; "/score-partwise[1]/part[1]/measure[2]/note[3]/notations[1]/ornaments[1]".
;;;; Structural damage (above: SCORE-FORMAT-ERROR) has FORMAT :MUSICXML, POSITION
;;;; the path of the offending element (for a missing or bad <duration>, and for
;;;; a backup past the measure start, its <note>, <forward> or <backup>; for a
;;;; bad <pitch>, its <note>), no restart.

(in-package #:score-backend-musicxml)

(defun read-musicxml (source &key split-voices (unsupported :error))
  "The SCORE in the MusicXML SOURCE (file header)."
  (declare (ignore source split-voices unsupported))
  (%sc2-pending 'read-musicxml))

(defun musicxml-to-score (document &key split-voices (unsupported :error))
  "The SCORE of the xml-protocol DOCUMENT, a MusicXML partwise score (file header)."
  (declare (ignore document split-voices unsupported))
  (%sc2-pending 'musicxml-to-score))
