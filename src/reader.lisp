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
;;;;                   start opens; a stop closes the open slur CLOSING picks
;;;;                   (below), the stop's voice being its note's voice value. A
;;;;                   SPANNER :SLUR from the start note's event to the stop
;;;;                   note's. A stop with no slur of its number open, and a slur
;;;;                   still open at the end of the part: unsupported, ELEMENT
;;;;                   "slur". type="continue" is ignored.
;;;;   <articulations> each child by +ARTICULATION-ELEMENTS+ an ARTICULATION;
;;;;                   <breath-mark> (any content) the BREATH-MARK.
;;;;   <fermata>       the FERMATA, SHAPE by content (+FERMATA-SHAPES+, empty =
;;;;                   :NORMAL; other shapes unsupported, ELEMENT "fermata"). A
;;;;                   second fermata in one <note>: unsupported, ELEMENT "fermata".
;;;;   <dynamics>      the event's DYNAMIC, as for directions below.
;;;; A second breath mark in one <note> is unsupported, ELEMENT "breath-mark".
;;;; Marks on several notes of one chord count once: the event's FERMATA and
;;;; BREATH-MARK are the first among its notes, and an articulation of a kind the
;;;; event already has, from a later note, is dropped silently (some programs
;;;; write a chord's marks on every notehead).
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
;;;;               type "stop" closes the open wedge of the part with its number
;;;;               (default 1) that CLOSING picks, the stop's voice being its
;;;;               target voice (ATTACHMENT); END is START when the stop's
;;;;               absolute position is START's onset, else the last event, read
;;;;               from a <note>, of the stop's target voice whose absolute
;;;;               onset is before the stop's position. A stop with no wedge of its
;;;;               number open, no END, or a wedge still open at the end of the
;;;;               part: unsupported, ELEMENT "wedge".
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
;;;; CLOSING. Among the slurs (wedges) of the part that are open and have the
;;;; stop's number, the stop closes the one opened last, in document order,
;;;; whose start event is in the stop's voice; when none of them is, the one
;;;; opened last. Two open spanners share a number only in a file that numbers
;;;; them per voice or per staff, as some notation programs do (MusicXML asks
;;;; for distinct numbers while they overlap): there each stop closes its own
;;;; voice's spanner. With distinct numbers at most one is open, and the voice
;;;; plays no part.
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

;;; Entry points ---------------------------------------------------------------------

(defun %check-read-options (split-voices unsupported)
  (check-type split-voices (member nil :auto))
  (check-type unsupported (member :error :warn :skip)))

(defun read-musicxml (source &key split-voices (unsupported :error))
  "The SCORE in the MusicXML SOURCE (file header)."
  (check-type source (or pathname string (vector (unsigned-byte 8)) stream))
  (%check-read-options split-voices unsupported)
  (musicxml-to-score (%decode-xml source :musicxml)
                     :split-voices split-voices :unsupported unsupported))

(defvar *candidates* nil
  "During a read: handle → the id attribute of the carrier of that handle's
element.")

(defun musicxml-to-score (document &key split-voices (unsupported :error))
  "The SCORE of the xml-protocol DOCUMENT, a MusicXML partwise score (file header)."
  (check-type document xml-protocol:xml-document)
  (%check-read-options split-voices unsupported)
  (let ((score (let ((*unsupported* unsupported)
                     (*handle-count* 0)
                     (*reserved-ids* nil)
                     (*candidates* (make-hash-table :test 'equal)))
                 (%settle-ids (%read-document document) :candidates *candidates*))))
    (if split-voices (split-voices score) score)))

;;; The intermediate representation --------------------------------------------------
;;; One record per score element, built once into the draft score (support.lisp,
;;; "Settling ids"). References between records are pointers; they become
;;; handles when the draft is built.

(defstruct (%rec (:copier nil) (:predicate nil))
  "What becomes one score element: CANDIDATE, the id attribute of its carrier
(file header, \"Ids\") or NIL; HANDLE, its provisional id, once allocated."
  (candidate nil)
  (handle nil))

(defun %handle (rec)
  "REC's handle: what a reference to its element names in the draft."
  (or (%rec-handle rec) (setf (%rec-handle rec) (%new-handle))))

(defun %id (rec)
  "The :ID REC's element is built with in the draft: its handle, registered
with its candidate."
  (let ((handle (%handle rec)))
    (when (%rec-candidate rec)
      (setf (gethash handle *candidates*) (%rec-candidate rec)))
    handle))

(defstruct (%mark (:include %rec) (:copier nil) (:predicate nil))
  "A fermata, breath mark, articulation, dynamic, jump mark or rehearsal mark.
VALUE: its shape, kind, value or text. FROM: the located <note> it came from."
  (value nil) (from nil))

(defstruct (%lyr (:include %rec) (:copier nil) (:predicate nil))
  verse text syllabic extender)

(defstruct (%tie (:include %rec) (:copier nil) (:predicate nil))
  "A tie; TARGET is the %NOTE it ends on."
  target)

(defstruct (%tmark (:include %rec) (:copier nil) (:predicate nil))
  offset tempo text)

(defstruct (%ending (:include %rec) (:copier nil) (:predicate nil))
  passes (measures 1))

(defstruct (%anchor (:include %rec) (:copier nil) (:predicate nil))
  measure offset symbol)

(defstruct (%span (:include %rec) (:copier nil) (:predicate nil))
  "A slur or hairpin from the %EVENT START to END; DOC orders its start."
  kind start end doc)

(defstruct (%note (:include %rec) (:copier nil) (:predicate nil))
  "One pitch of an event: a note event's own, or a chord note. The tie start is
TIE-LOC (the <tie> or <tied> reported if it has no end, named TIE-NAME) and
TIE-CANDIDATE (the <tied type=\"start\"> id); TIE the %TIE once linked."
  pitch accidental event tie-loc tie-name tie-candidate tie)

(defstruct (%event (:include %rec) (:copier nil) (:predicate nil))
  "An event: read from a <note> (READ-P, DOC its document index) or a gap rest.
VOICE is its voice value, VC its %VOICE; MEASURE its measure index and ONSET its
position there; INDEX its place in its voice measure."
  voice vc measure onset duration tuplet grace rest-p measure-rest hidden
  (staff 1) doc read-p index
  (notes '()) (stems '()) notations-candidate notations-seen
  fermata breath (articulations '()) dynamic (lyrics '()))

(defstruct (%voice (:include %rec) (:copier nil) (:predicate nil))
  name (staff 1) stem (measures '()))

(defstruct (%msr (:include %rec) (:copier nil) (:predicate nil))
  "A measure of the measure map, from the first part's <measure> (file header,
\"The measure map\")."
  number-attr text-attr implicit time key (barline :regular) repeat-start repeat-end
  ending ending-stop (jumps '()) (tempos '()) rehearsal
  (reach 0) meter (start 0) length pickup number bar)

(defstruct (%dir (:copier nil) (:predicate nil))
  "A <direction> and the elements it yields, for its id (file header, \"Ids\")."
  candidate (jumps '()) tempo rehearsal (dynamics '()) (hairpins '()))

(defstruct (%dyn (:copier nil) (:predicate nil))
  "A <dynamics> element: its MARKS; EVENT when it sits in <notations>, else the
DIR and the place ATTACHMENT starts from."
  marks loc dir event measure position voice staff doc)

(defstruct (%wedge (:copier nil) (:predicate nil))
  "A <wedge> start (KIND :CRESCENDO or :DIMINUENDO) or stop (:STOP)."
  kind number loc dir measure position voice staff doc)

(defstruct (%pw (:include %rec) (:copier nil) (:predicate nil))
  "A part being read: its walk state, then its voices and links."
  index first-p track-p players name abbreviation
  divisions staves (max-staff 1) (clefs '())
  (events '()) (notes '()) (dirs '()) (dyns '()) (wedges '()) (spanners '())
  (anchors '()) (open-slurs '())
  (doc 0) (measure 0) (cursor 0) (reach 0) last-event (intervals '()) (reaches '())
  (voices '()) (voice-table (make-hash-table :test 'equal)))

;;; The document ------------------------------------------------------------------------

(defun %read-document (document)
  "The draft score of DOCUMENT: every element built with its handle (file
header, everything but \"Ids\")."
  (let ((root-element (xml-protocol:document-root-element document)))
    (unless root-element
      (error 'score-protocol:score-format-error :format :musicxml :reason "no root element"))
    (let ((root (%loc root-element nil 1)))
      (unless (string= (%name root) "score-partwise")
        (%format-error root "the root element isn't <score-partwise>"))
      (let* ((kids (%walk root))
             (part-list (%kid kids "part-list"))
             (score-parts (and part-list (%kids (%walk part-list) "score-part")))
             (parts (%kids kids "part"))
             (measures (mapcar (lambda (part) (%kids (%walk part) "measure")) parts)))
        (%check-parts score-parts parts measures)
        (let* ((first-id (and parts (%attr (first parts) "id")))
               (track (position-if (lambda (ms) (some (lambda (m) (%child m "harmony")) ms)) measures))
               (msrs (mapcar (lambda (measure)
                               (make-%msr :candidate (%measure-candidate measure first-id)
                                          :number-attr (%attr measure "number")
                                          :text-attr (%attr measure "text")
                                          :implicit (equal (%attr measure "implicit") "yes")))
                             (first measures)))
               (pws (loop for score-part in score-parts
                          for part-measures in measures
                          for i from 0
                          collect (%read-part score-part part-measures i (and track (= i track)) msrs)))
               (starts (%measure-map msrs pws)))
          (dolist (pw pws) (%link-part pw starts))
          (dolist (pw pws) (mapc #'%distribute-carrier (%pw-dirs pw)))
          (%build-draft (%metadata kids) msrs pws))))))

(defun %check-parts (score-parts parts measures)
  "SCORE-FORMAT-ERROR unless the <part>s match the <score-part>s, in order, and
each has the first part's number of measures (file header, \"Document\")."
  (loop for part in parts
        for i from 0
        for id = (%attr part "id")
        for named = (and id (find id score-parts :key (lambda (sp) (%attr sp "id")) :test #'equal))
        do (unless named
             (%format-error part "a <part> whose id names no <score-part>"))
           (unless (eq named (nth i score-parts))
             (%format-error part "a <part> out of part-list order"))
           (unless (= (length (nth i measures)) (length (first measures)))
             (%format-error part "a <part> whose number of measures differs from the first part's")))
  (when (> (length score-parts) (length parts))
    (%format-error (nth (length parts) score-parts) "a <score-part> with no <part>")))

(defun %measure-candidate (measure part-id)
  "M when MEASURE's id is the slice id M.P with P = PART-ID, else NIL."
  (let* ((id (%attr measure "id"))
         (dot (and id part-id (position #\. id))))
    (when dot
      (let ((m (subseq id 0 dot)) (p (subseq id (1+ dot))))
        (and (score-protocol:valid-id-p m) (score-protocol:valid-id-p p) (string= p part-id) m)))))

(defun %metadata (kids)
  "SCORE-METADATA from the root's mapped children KIDS (file header, \"Metadata\")."
  (let* ((work (%kid kids "work"))
         (work-title (and work (%kid (%walk work) "work-title")))
         (movement (%kid kids "movement-title"))
         (identification (%kid kids "identification"))
         (credits (and identification (%walk identification))))
    (loop for (key value)
            in (append (list (list :title (cond (work-title (%text work-title))
                                                 (movement (%text movement))))
                             (list :subtitle (and work-title movement (%text movement))))
                       (loop for (key type) in +metadata-creators+
                             collect (list key (let ((creator (find type (%kids credits "creator")
                                                                    :key (lambda (c) (%attr c "type"))
                                                                    :test #'equal)))
                                                 (and creator (%text creator)))))
                       (list (list :copyright (let ((rights (%kid credits "rights")))
                                                (and rights (%text rights))))))
          when (%present-p value)
            nconc (list key value))))

;;; Parts and measures -------------------------------------------------------------------

(defun %read-part (score-part measures index track-p msrs)
  "Walk the <part> whose <score-part> is SCORE-PART and whose <measure>s are
MEASURES. MSRS are the measure records, filled from the first part."
  (let* ((kids (%walk score-part))
         (pw (make-%pw :index index :first-p (= index 0) :track-p track-p
                       :candidate (%attr score-part "id")
                       :players (%kids kids "player")
                       :name (%nonempty-text (%kid kids "part-name"))
                       :abbreviation (%nonempty-text (%kid kids "part-abbreviation")))))
    (loop for measure in measures
          for msr in msrs
          for i from 0
          do (%read-measure pw measure i (and (%pw-first-p pw) msr)))
    (setf (%pw-reaches pw) (nreverse (%pw-reaches pw)))
    pw))

(defun %read-measure (pw loc i msr)
  "Read the <measure> LOC, measure I, with the cursor. MSR is its measure record
in the first part, NIL in the others."
  (setf (%pw-measure pw) i (%pw-cursor pw) 0 (%pw-reach pw) 0
        (%pw-last-event pw) nil (%pw-intervals pw) '())
  (dolist (child (%walk loc :skip (append (unless msr '("barline"))
                                          (unless (%pw-track-p pw) '("harmony")))))
    (let ((name (%name child)))
      (cond ((string= name "note") (%read-note pw child))
            ((string= name "backup") (%read-move pw child -1))
            ((string= name "forward") (%read-move pw child 1))
            ((string= name "direction") (%read-direction pw child msr))
            ((string= name "sound") (%read-direction pw child msr :sound-only t))
            ((string= name "attributes") (%read-attributes pw child msr))
            ((string= name "harmony") (%read-harmony pw child))
            ((string= name "barline") (%read-barline child msr)))))
  (push (%pw-reach pw) (%pw-reaches pw)))

(defun %advance (pw distance)
  "Move the cursor by DISTANCE; the measure's reach follows it."
  (let ((cursor (+ (%pw-cursor pw) distance)))
    (setf (%pw-cursor pw) cursor
          (%pw-reach pw) (max (%pw-reach pw) cursor))))

(defun %duration (pw loc)
  "The <duration> of LOC (a <note>, <forward> or <backup>) in whole notes."
  (let* ((duration (%child loc "duration"))
         (x (and duration (%parse-decimal (%text duration)))))
    (unless (and x (plusp x))
      (%format-error loc "a missing <duration>, or one that isn't a decimal > 0"))
    (unless (%pw-divisions pw)
      (%format-error loc "a <duration> before any <divisions>"))
    (/ x (* 4 (%pw-divisions pw)))))

(defun %read-move (pw loc sign)
  "A <backup> (SIGN -1) or <forward> (SIGN 1)."
  (let ((distance (%duration pw loc)))
    (when (and (minusp sign) (> distance (%pw-cursor pw)))
      (%format-error loc "a <backup> past the start of the measure"))
    (%advance pw (* sign distance))))

(defun %position (pw offset)
  "The position of a <direction> or <harmony> whose <offset> is OFFSET (or NIL):
the cursor plus the offset (file header, \"The cursor\")."
  (let ((cursor (%pw-cursor pw)))
    (if (null offset)
        cursor
        (let ((x (%parse-decimal (%text offset))))
          (unless x (%format-error offset "an <offset> that isn't a decimal"))
          (unless (%pw-divisions pw) (%format-error offset "an <offset> before any <divisions>"))
          (let ((position (+ cursor (/ x (* 4 (%pw-divisions pw))))))
            (if (minusp position)
                (progn (%unsupported "offset" offset "a position before the start of the measure")
                       cursor)
                position))))))

(defun %staff-number (loc)
  "The positive integer of the <staff> LOC."
  (let ((k (%digits-integer (%text loc))))
    (unless (and k (plusp k)) (%format-error loc "a <staff> that isn't a positive integer"))
    k))

;;; Notes ----------------------------------------------------------------------------------

(defun %read-pitch (note loc)
  "The SPELLED-PITCH of the <pitch> LOC of the <note> NOTE, or NIL when its alter
is unsupported."
  (let* ((kids (%walk loc))
         (step (%kid kids "step"))
         (octave (%kid kids "octave"))
         (alter (%kid kids "alter"))
         (letter (and step (%step-letter (%text step))))
         (o (and octave (%parse-integer-text (%text octave))))
         (a (if alter (%parse-decimal (%text alter)) 0)))
    (unless (and letter o)
      (%format-error note "a <pitch> without a step A-G and an integer octave"))
    (and (integerp a) (<= -2 a 2)
         (music-theory:make-spelled-pitch :letter letter :alter a :octave o))))

(defun %accidental (loc)
  "ACCIDENTAL of the <note> LOC (file header, \"Events\")."
  (let ((accidental (%child loc "accidental")))
    (cond ((null accidental) :auto)
          ((some (lambda (name) (equal (%attr accidental name) "yes"))
                 '("cautionary" "parentheses" "bracket" "editorial"))
           :cautionary)
          (t :forced))))

(defun %stem (loc)
  (let ((stem (%child loc "stem")))
    (and stem (find (%text stem) '(:up :down) :test #'string-equal))))

(defun %tuplet (loc)
  "TUPLET of the <note> LOC: actual / normal notes, NIL for none or 1."
  (let ((modification (%child loc "time-modification")))
    (when modification
      (let* ((kids (%walk modification))
             (actual (let ((kid (%kid kids "actual-notes"))) (and kid (%digits-integer (%text kid)))))
             (normal (let ((kid (%kid kids "normal-notes"))) (and kid (%digits-integer (%text kid))))))
        (if (and actual normal (plusp actual) (plusp normal))
            (let ((ratio (/ actual normal))) (and (/= ratio 1) ratio))
            (%unsupported "time-modification" modification "not two positive integers"))))))

(defun %grace-duration (loc)
  "The notated value of the grace <note> LOC: its <type> and <dot>s, else 1/8."
  (let* ((type (%child loc "type"))
         (base (and type (first (find (%text type) +note-types+ :key #'second :test #'string=)))))
    (if base
        (music-theory:tuplet-duration base 1 :dots (length (%kids (%children loc) "dot")))
        1/8)))

(defun %overlaps-p (pw voice onset duration grace)
  "True when an event of VOICE at ONSET would start before an earlier non-grace
event of the voice in this measure ends."
  (some (lambda (interval)
          (destructuring-bind (start . end) interval
            (if grace
                (and (<= start onset) (< onset end))
                (and (< start (+ onset duration)) (< onset end)))))
        (cdr (assoc voice (%pw-intervals pw) :test #'string=))))

(defun %read-note (pw loc)
  "Read the <note> LOC (file header, \"The cursor\", \"Events\")."
  (let ((chord (%child loc "chord"))
        (grace (%child loc "grace"))
        (rest (%child loc "rest"))
        (pitch-loc (%child loc "pitch"))
        (event (%pw-last-event pw)))
    (cond ((and chord (or rest (null event) (%event-rest-p event)))
           (%unsupported "note" loc "a <chord> note that joins no pitched note"))
          ((and grace rest)
           (%unsupported "note" loc "a grace rest"))
          ((not (or rest pitch-loc))
           (%format-error loc "a <note> with neither <pitch> nor <rest>"))
          (t
           (let ((pitch (and pitch-loc (%read-pitch loc pitch-loc))))
             (cond ((and pitch-loc (null pitch))
                    (%unsupported "note" loc "an <alter> that isn't an integer -2..2"))
                   (chord
                    (%read-note-content pw loc event (%add-note pw loc event pitch)))
                   (t
                    (%read-event pw loc grace rest pitch))))))))

(defun %note-staff (pw loc)
  (let* ((staff (%child loc "staff"))
         (k (if staff (%staff-number staff) 1)))
    (setf (%pw-max-staff pw) (max (%pw-max-staff pw) k))
    k))

(defun %add-note (pw loc event pitch)
  "A %NOTE of PITCH from the <note> LOC, joined to EVENT."
  (let ((note (make-%note :pitch pitch :accidental (%accidental loc) :event event
                          :candidate (%attr loc "id"))))
    (%note-staff pw loc)
    (setf (%event-notes event) (append (%event-notes event) (list note)))
    (push (%stem loc) (%event-stems event))
    (push note (%pw-notes pw))
    note))

(defun %read-event (pw loc grace rest pitch)
  "The new event of the <note> LOC at the cursor; dropped (as unsupported) when
it overlaps an earlier event of its voice."
  (let* ((onset (%pw-cursor pw))
         (duration (if grace (%grace-duration loc) (%duration pw loc)))
         (voice (let ((kid (%child loc "voice"))) (if kid (%text kid) "1"))))
    (if (%overlaps-p pw voice onset duration grace)
        (%unsupported "note" loc "two voices under one voice value")
        (let ((event (make-%event :voice voice :measure (%pw-measure pw) :onset onset
                                  :duration duration :tuplet (%tuplet loc)
                                  :grace (and grace (if (equal (%attr grace "slash") "yes")
                                                        :acciaccatura
                                                        :appoggiatura))
                                  :rest-p (and rest t)
                                  :measure-rest (and rest (equal (%attr rest "measure") "yes"))
                                  :hidden (and rest (equal (%attr loc "print-object") "no"))
                                  :staff (%note-staff pw loc)
                                  :doc (incf (%pw-doc pw)) :read-p t
                                  :candidate (%attr loc "id"))))
          (push event (%pw-events pw))
          (unless grace
            (push (cons onset (+ onset duration))
                  (cdr (or (assoc voice (%pw-intervals pw) :test #'string=)
                           (car (push (list voice) (%pw-intervals pw))))))
            (%advance pw duration))
          (setf (%pw-last-event pw) event)
          (if pitch
              (%read-note-content pw loc event (%add-note pw loc event pitch))
              (progn (push (%stem loc) (%event-stems event))
                     (%walk rest)
                     (%read-note-content pw loc event nil)))))))

(defun %read-note-content (pw loc event note)
  "The ties, notations and lyrics of the committed <note> LOC, on EVENT. NOTE is
its %NOTE, NIL for a rest."
  (dolist (kid (%walk loc))
    (let ((name (%name kid)))
      (cond ((string= name "tie")
             (when (and note (equal (%attr kid "type") "start")
                        (not (equal (%note-tie-name note) "tie")))
               (setf (%note-tie-loc note) kid (%note-tie-name note) "tie")))
            ((string= name "notations") (%read-notations pw kid event note loc))
            ((string= name "lyric") (%read-lyric kid event))))))

(defun %read-notations (pw loc event note note-loc)
  "The <notations> LOC of the <note> NOTE-LOC (file header, \"Notations\")."
  (when (and note (eq note (first (%event-notes event))) (not (%event-notations-seen event)))
    (setf (%event-notations-seen event) t
          (%event-notations-candidate event) (%attr loc "id")))
  (dolist (kid (%walk loc))
    (let ((name (%name kid)))
      (cond ((string= name "tied")
             (when (and note (equal (%attr kid "type") "start"))
               (unless (%note-tie-candidate note)
                 (setf (%note-tie-candidate note) (%attr kid "id")))
               (unless (%note-tie-loc note)
                 (setf (%note-tie-loc note) kid (%note-tie-name note) "tied"))))
            ((string= name "slur") (%read-slur pw kid event))
            ((string= name "articulations") (%read-articulations kid event note-loc))
            ((string= name "dynamics") (%read-dynamics pw kid :event event))
            ((string= name "fermata") (%read-fermata kid event note-loc))))))

(defun %closing-entry (entries number in-voice-p)
  "The entry a stop of NUMBER closes (file header, CLOSING), or NIL. ENTRIES are
the open slurs or wedges of the part, the one opened last first, each a list
whose first element is its number (a string); IN-VOICE-P is true of an entry
whose start event is in the stop's voice."
  (declare (ignore entries number in-voice-p))
  (%sc21-pending '%closing-entry))

(defun %read-slur (pw loc event)
  "A <slur>: a start opens one of its number, a stop closes the open one CLOSING
picks."
  (let ((type (%attr loc "type"))
        (number (or (%attr loc "number") "1")))
    (cond ((equal type "start")
           (push (list number event loc (incf (%pw-doc pw))) (%pw-open-slurs pw)))
          ((equal type "stop")
           (let ((open (%closing-entry (%pw-open-slurs pw) number
                                       (lambda (entry)
                                         (string= (%event-voice (second entry)) (%event-voice event))))))
             (if open
                 (progn
                   (setf (%pw-open-slurs pw) (remove open (%pw-open-slurs pw)))
                   (push (make-%span :kind :slur :start (second open) :end event
                                     :candidate (%attr (third open) "id") :doc (fourth open))
                         (%pw-spanners pw)))
                 (%unsupported "slur" loc "a slur stop with no slur open")))))))

(defun %read-articulations (loc event note-loc)
  "The children of the <articulations> LOC: articulations and the breath mark.
Its id goes to the first element made from them."
  (let ((carrier (%attr loc "id")))
    (flet ((take-carrier () (prog1 carrier (setf carrier nil))))
      (dolist (kid (%walk loc))
        (if (string= (%name kid) "breath-mark")
            (let ((breath (%event-breath event)))
              (cond ((null breath)
                     (setf (%event-breath event)
                           (make-%mark :from note-loc :candidate (take-carrier))))
                    ((eq (%mark-from breath) note-loc)
                     (%unsupported "breath-mark" kid "a second breath mark in one <note>"))))
            (let ((kind (first (find (%name kid) +articulation-elements+ :key #'second :test #'string=))))
              (unless (find-if (lambda (mark) (and (eq (%mark-value mark) kind)
                                                   (not (eq (%mark-from mark) note-loc))))
                               (%event-articulations event))
                (setf (%event-articulations event)
                      (append (%event-articulations event)
                              (list (make-%mark :value kind :from note-loc
                                                :candidate (take-carrier))))))))))))

(defun %read-fermata (loc event note-loc)
  "The <fermata> LOC: the event's first fermata."
  (let* ((text (%text loc))
         (shape (if (string= text "")
                    :normal
                    (first (find text +fermata-shapes+ :key #'second :test #'string=))))
         (fermata (%event-fermata event)))
    (cond ((null shape) (%unsupported "fermata" loc "a fermata shape outside the model"))
          ((null fermata)
           (setf (%event-fermata event)
                 (make-%mark :value shape :from note-loc :candidate (%attr loc "id"))))
          ((eq (%mark-from fermata) note-loc)
           (%unsupported "fermata" loc "a second fermata in one <note>")))))

(defun %verse (number)
  "VERSE of a lyric whose number attribute is NUMBER (file header, \"Lyrics\")."
  (or (and number
           (let ((k (%digits-integer
                     (subseq number (1+ (or (position-if-not #'%ascii-digit number :from-end t) -1))))))
             (and k (>= k 1) k)))
      1))

(defun %read-lyric (loc event)
  "The <lyric> LOC, a LYRIC of EVENT unless it has no <text>."
  (let* ((kids (%walk loc))
         (syllabic-loc (%kid kids "syllabic"))
         (syllabic (if syllabic-loc
                       (first (find (%text syllabic-loc) +syllabic-names+ :key #'second :test #'string=))
                       :single)))
    (if (null syllabic)
        (%unsupported "lyric" loc "a syllabic value outside the model")
        (let ((text nil) (joiner nil) (extender nil))
          (dolist (kid kids)
            (let ((name (%name kid)))
              (cond ((string= name "text")
                     (setf text (if text (concatenate 'string text (or joiner "") (%text kid)) (%text kid))
                           joiner nil))
                    ((string= name "elision")
                     (setf joiner (let ((content (%text kid)))
                                    (if (string= content "") (string (code-char #x203F)) content))))
                    ((string= name "extend")
                     (when (member (%attr kid "type") '(nil "start") :test #'equal)
                       (setf extender t))))))
          (when text
            (setf (%event-lyrics event)
                  (append (%event-lyrics event)
                          (list (make-%lyr :verse (%verse (%attr loc "number")) :text text
                                           :syllabic syllabic :extender extender
                                           :candidate (%attr loc "id"))))))))))

;;; Directions ------------------------------------------------------------------------------

(defun %read-metronome (loc)
  "The TEMPO of the <metronome> LOC, or NIL when it is unsupported."
  (let* ((kids (%walk loc))
         (units (%kids kids "beat-unit"))
         (per-minute (%kid kids "per-minute"))
         (bpm (and per-minute (%parse-decimal (%text per-minute))))
         (base (and (= 1 (length units))
                    (first (find (%text (first units)) +note-types+ :key #'second :test #'string=)))))
    (if (and base bpm (plusp bpm))
        (music-theory:make-tempo
         :bpm bpm
         :beat-unit (music-theory:tuplet-duration base 1 :dots (length (%kids kids "beat-unit-dot"))))
        (%unsupported "metronome" loc "a metric modulation, or no decimal <per-minute>"))))

(defun %jump-row (text rows)
  "The first of the +JUMP-DIRECTIONS+ ROWS whose WORDS or OTHER-WORDS are TEXT."
  (let ((text (%trim text)))
    (find-if (lambda (row)
               (or (and (second row) (string-equal text (second row)))
                   (member text (fifth row) :test #'string-equal)))
             rows)))

(defun %sound-jump (attribute default words)
  "The kind of a sound ATTRIBUTE (\"dacapo\" or \"dalsegno\") jump: the row of
that attribute whose words match one of WORDS, else DEFAULT."
  (let ((rows (remove attribute +jump-directions+ :key #'third :test-not #'equal)))
    (or (loop for word in words
              for row = (%jump-row (%text word) rows)
              when row return (first row))
        default)))

(defun %read-direction (pw loc msr &key sound-only)
  "The <direction> LOC, or with SOUND-ONLY a measure-level <sound> (file header,
\"Directions\"). MSR is the measure record in the first part, else NIL."
  (let* ((kids (if sound-only (list loc) (%walk loc)))
         (sound (%kid kids "sound"))
         (position (%position pw (%kid kids "offset")))
         (voice (let ((kid (%kid kids "voice"))) (and kid (%text kid))))
         (staff (let ((kid (%kid kids "staff"))) (and kid (%staff-number kid))))
         (types (loop for kid in (%kids kids "direction-type") append (%walk kid)))
         (dir (make-%dir :candidate (and (not sound-only) (%attr loc "id"))))
         (doc (incf (%pw-doc pw))))
    (when sound (%walk sound))
    (flet ((sound (name) (and sound (%attr sound name))))
      (let* ((segnos (%kids types "segno"))
             (codas (%kids types "coda"))
             (words (%kids types "words"))
             (metronome (let ((kid (%kid types "metronome"))) (and kid (%read-metronome kid))))
             (dacapo (equal (sound "dacapo") "yes"))
             (sound-jump (or (sound "tocoda") (sound "fine") dacapo (sound "dalsegno")))
             (word-jumps (unless sound-jump
                           (loop for word in words
                                 for row = (%jump-row (%text word) +jump-directions+)
                                 when row collect (cons word (first row)))))
             (kinds (append (mapcar (constantly :segno) segnos)
                            (mapcar (constantly :coda) codas)
                            (and (sound "tocoda") '(:to-coda))
                            (and (sound "fine") '(:fine))
                            (and dacapo (list (%sound-jump "dacapo" :da-capo words)))
                            (and (sound "dalsegno") (list (%sound-jump "dalsegno" :dal-segno words)))
                            (and (sound "segno") (null segnos) '(:segno))
                            (and (sound "coda") (null codas) '(:coda))
                            (mapcar #'cdr word-jumps)))
             (sound-tempo (let ((x (and (sound "tempo") (%parse-decimal (sound "tempo")))))
                            (and x (plusp x) x)))
             (tempo-p (and (null kinds) (or metronome sound-tempo (and words sound))))
             (used (cond (sound-jump words)
                         (kinds (mapcar #'car word-jumps))
                         (tempo-p words))))
        (when msr
          (dolist (kind kinds)
            (let ((mark (make-%mark :value kind)))
              (setf (%msr-jumps msr) (append (%msr-jumps msr) (list mark))
                    (%dir-jumps dir) (append (%dir-jumps dir) (list mark)))))
          (when tempo-p
            (let ((mark (make-%tmark :offset position
                                     :tempo (or metronome
                                                (and sound-tempo
                                                     (music-theory:make-tempo :bpm sound-tempo
                                                                              :beat-unit 1/4)))
                                     :text (and words (format nil "~{~A~^ ~}" (mapcar #'%text words))))))
              (setf (%msr-tempos msr) (append (%msr-tempos msr) (list mark))
                    (%dir-tempo dir) mark))))
        (dolist (word words)
          (unless (member word used)
            (%unsupported "words" word "free text outside a jump or a tempo")))
        (dolist (rehearsal (%kids types "rehearsal"))
          (when msr
            (if (%msr-rehearsal msr)
                (%unsupported "rehearsal" rehearsal "a second rehearsal mark in one measure")
                (let ((mark (make-%mark :value (%text rehearsal))))
                  (setf (%msr-rehearsal msr) mark
                        (%dir-rehearsal dir) mark)))))
        (dolist (dynamics (%kids types "dynamics"))
          (%read-dynamics pw dynamics :dir dir :position position :voice voice :staff staff :doc doc))
        (dolist (wedge (%kids types "wedge"))
          (let* ((type (%attr wedge "type"))
                 (kind (cond ((equal type "crescendo") :crescendo)
                             ((equal type "diminuendo") :diminuendo)
                             ((equal type "stop") :stop))))
            (when kind
              (push (make-%wedge :kind kind :number (or (%attr wedge "number") "1") :loc wedge :dir dir
                                 :measure (%pw-measure pw) :position position :voice voice
                                 :staff staff :doc doc)
                    (%pw-wedges pw)))))
        (push dir (%pw-dirs pw))))))

(defun %read-dynamics (pw loc &key dir event position voice staff doc)
  "The <dynamics> LOC: one dynamic mark per child. In <notations> (EVENT given)
its own id goes to the first; in a direction ATTACHMENT finds the event later."
  (let* ((carrier (and event (%attr loc "id")))
         (marks (loop for kid in (%walk loc)
                      for first = t then nil
                      collect (make-%mark :value (intern (string-upcase (%name kid)) :keyword)
                                          :candidate (and first carrier)))))
    (when marks
      (push (make-%dyn :marks marks :loc loc :dir dir :event event :measure (%pw-measure pw)
                       :position position :voice voice :staff staff
                       :doc (or doc (incf (%pw-doc pw))))
            (%pw-dyns pw)))))

;;; Attributes, barlines, harmonies -------------------------------------------------------------

(defun %read-attributes (pw loc msr)
  "The <attributes> LOC. <time> and <key> count in the first part only (MSR)."
  (dolist (kid (%walk loc :skip (unless msr '("time" "key"))))
    (let ((name (%name kid)))
      (cond ((string= name "divisions")
             (let ((x (%parse-decimal (%text kid))))
               (unless (and x (plusp x)) (%format-error kid "<divisions> that isn't a decimal > 0"))
               (setf (%pw-divisions pw) x)))
            ((string= name "staves")
             (unless (%pw-staves pw) (setf (%pw-staves pw) (%staff-number kid))))
            ((string= name "clef") (%read-clef pw kid))
            ((string= name "key") (%read-key pw kid msr))
            ((string= name "time") (%read-time pw kid msr))))))

(defun %read-key (pw loc msr)
  "The measure's KEY from the <key> LOC, when it has no number or number 1."
  (let ((number (%attr loc "number")))
    (when (or (null number) (string= number "1"))
      (if (plusp (%pw-cursor pw))
          (%unsupported "key" loc "a key change inside the measure")
          (let* ((kids (%walk loc))
                 (fifths (let ((kid (%kid kids "fifths"))) (and kid (%parse-integer-text (%text kid)))))
                 (mode-loc (%kid kids "mode"))
                 (mode (if mode-loc (find (%text mode-loc) '(:major :minor) :test #'string-equal) :major)))
            (if (and fifths (<= -7 fifths 7) mode)
                (unless (%msr-key msr)
                  (setf (%msr-key msr)
                        (music-theory:make-key
                         :tonic (music-theory:fifths-pitch-class (+ fifths (if (eq mode :minor) 3 0)))
                         :mode mode)))
                (%unsupported "key" loc "a key outside the model")))))))

(defun %read-time (pw loc msr)
  "The measure's TIME from the <time> LOC."
  (if (plusp (%pw-cursor pw))
      (%unsupported "time" loc "a time change inside the measure")
      (let* ((kids (%walk loc))
             (beats (%kids kids "beats"))
             (types (%kids kids "beat-type")))
        (if (and (= 1 (length beats)) (= 1 (length types)))
            (let ((meter (handler-case (music-theory:parse-meter
                                        (format nil "~A/~A" (%text (first beats)) (%text (first types))))
                           (music-theory:music-theory-error (condition)
                             (%unsupported "time" loc "a meter music-theory can't read" condition)))))
              (when (and meter (null (%msr-time msr)))
                (setf (%msr-time msr) meter)))
            (%unsupported "time" loc "not one <beats> and one <beat-type>")))))

(defun %read-clef (pw loc)
  "The <clef> LOC: the CLEF of its staff, the first time."
  (let* ((number (or (%digits-integer (%attr loc "number")) 1))
         (kids (%walk loc))
         (sign (let ((kid (%kid kids "sign"))) (and kid (%text kid))))
         (line (let ((kid (%kid kids "line")))
                 (if kid
                     (%parse-integer-text (%text kid))
                     (third (find sign +clef-signs+ :key #'second :test #'equal)))))
         (change (let ((kid (%kid kids "clef-octave-change")))
                   (if kid (%parse-integer-text (%text kid)) 0)))
         (clef (first (find-if (lambda (row) (and (equal (second row) sign)
                                                  (eql (third row) line)
                                                  (eql (fourth row) change)))
                               +clef-signs+)))
         (entry (assoc number (%pw-clefs pw))))
    (cond ((or (null clef) (< number 1)) (%unsupported "clef" loc "a clef outside the model"))
          ((null entry)
           (setf (%pw-max-staff pw) (max (%pw-max-staff pw) number))
           (push (list number clef (%attr loc "id")) (%pw-clefs pw)))
          ((not (eq (second entry) clef))
           (%unsupported "clef" loc "a second clef for one staff")))))

(defun %parse-passes (text)
  "The passes of an <ending> number TEXT: positive integers separated by commas
and/or spaces, or NIL."
  (let ((tokens '()) (start nil))
    (loop for i from 0 to (length text)
          for char = (and (< i (length text)) (char text i))
          do (if (and char (not (member char '(#\, #\Space))))
                 (unless start (setf start i))
                 (when start
                   (push (subseq text start i) tokens)
                   (setf start nil))))
    (let ((passes (mapcar #'%digits-integer (nreverse tokens))))
      (and passes (every (lambda (k) (and k (plusp k))) passes) passes))))

(defun %read-barline (loc msr)
  "The <barline> LOC of the first part (file header: BARLINE, REPEAT-START,
REPEAT-END, ENDING)."
  (let* ((location (or (%attr loc "location") "right"))
         (left (string= location "left")))
    (if (string= location "middle")
        (%unsupported "barline" loc "a barline inside the measure")
        (dolist (kid (%walk loc))
          (let ((name (%name kid))
                (type (%attr kid "type")))
            (cond ((string= name "bar-style")
                   (unless left
                     (let ((style (first (find (%text kid) +bar-styles+ :key #'second :test #'string=))))
                       (if style
                           (setf (%msr-barline msr) style)
                           (%unsupported "bar-style" kid "a bar style outside the model")))))
                  ((string= name "repeat")
                   (let ((direction (%attr kid "direction")))
                     (cond ((and left (equal direction "forward"))
                            (setf (%msr-repeat-start msr) t))
                           ((and (not left) (equal direction "backward"))
                            (setf (%msr-repeat-end msr)
                                  (let ((times (%digits-integer (%attr kid "times"))))
                                    (if (and times (>= times 2)) times 2))))
                           (t (%unsupported "repeat" kid "a repeat on the wrong side of the measure")))))
                  ((string= name "ending")
                   (cond ((and left (equal type "start"))
                          (let ((passes (%parse-passes (or (%attr kid "number") ""))))
                            (cond ((null passes)
                                   (%unsupported "ending" kid "ending numbers that aren't positive integers"))
                                  ((%msr-ending msr)
                                   (%unsupported "ending" kid "a second ending in one measure"))
                                  (t (setf (%msr-ending msr)
                                           (make-%ending :passes passes :candidate (%attr loc "id")))))))
                         ((and (not left) (member type '("stop" "discontinue") :test #'equal))
                          (setf (%msr-ending-stop msr) t))
                         (t (%unsupported "ending" kid "an ending on the wrong side of the measure"))))))))))

(defun %read-harmony (pw loc)
  "The <harmony> LOC of the chord-symbol track's part."
  (let* ((position (%position pw (%child loc "offset")))
         (symbol (%harmony-symbol loc)))
    (when symbol
      (push (make-%anchor :measure (%pw-measure pw) :offset position :symbol symbol
                          :candidate (%attr loc "id"))
            (%pw-anchors pw)))))

;;; The measure map -----------------------------------------------------------------------------

(defun %measure-map (msrs pws)
  "Fill the measure records from the parts' reaches (file header, \"The measure
map\"); the vector of measure records, which know their absolute starts."
  (let ((meter (music-theory:make-meter)) (start 0))
    (loop for msr in msrs
          for i from 0
          for reach = (reduce #'max pws :key (lambda (pw) (nth i (%pw-reaches pw))) :initial-value 0)
          do (setf meter (or (%msr-time msr) meter))
             (let ((bar (music-theory:meter-measure-duration meter)))
               (setf (%msr-reach msr) reach
                     (%msr-meter msr) meter
                     (%msr-pickup msr) (and (= i 0) (%msr-implicit msr) (< 0 reach bar))
                     (%msr-length msr) (and (plusp reach) (/= reach bar) reach)
                     (%msr-start msr) start)
               (incf start (or (%msr-length msr) bar)))))
  (let ((first-bar (if (and msrs (%msr-pickup (first msrs))) 0 1)))
    (loop for msr in msrs
          for bar from first-bar
          for label = (format nil "~D" bar)
          do (setf (%msr-bar msr) bar
                   (%msr-number msr)
                   (let ((text (%msr-text-attr msr)) (number (%msr-number-attr msr)))
                     (cond ((%present-p text) text)
                           ((and (%present-p number) (string/= number label)) number))))))
  (loop for tail on msrs
        for ending = (%msr-ending (first tail))
        when ending
          do (setf (%ending-measures ending)
                   (let ((stop (position-if #'%msr-ending-stop tail))
                         (next (position-if #'%msr-ending (rest tail))))
                     (cond (stop (1+ stop))
                           (next (1+ next))
                           (t (length tail))))))
  (coerce msrs 'simple-vector))

(defun %abs-onset (event starts)
  "The absolute onset of EVENT; STARTS is the vector of measure records."
  (+ (%msr-start (svref starts (%event-measure event))) (%event-onset event)))

;;; Voices and links -------------------------------------------------------------------------------

(defun %link-part (pw starts)
  "The voices of PW, its voice measures, ties, dynamics, hairpins and open slurs
(file header, \"Parts, staves, voices\" to \"Directions\")."
  (%part-voices pw)
  (%fill-voices pw starts)
  (dolist (event (%pw-events pw))
    (when (rest (%event-notes event))
      (setf (%rec-candidate event) (%event-notations-candidate event))))
  (%link-ties pw starts)
  (%link-dynamics pw)
  (%link-wedges pw starts)
  (dolist (open (reverse (%pw-open-slurs pw)))
    (%unsupported "slur" (third open) "a slur still open at the end of the part")))

(defun %part-voices (pw)
  "The voices of PW in order, and its table voice value → voice (file header,
VOICES)."
  (let* ((events (reverse (%pw-events pw)))
         (values (remove-duplicates (mapcar #'%event-voice events) :test #'string= :from-end t))
         (players (%pw-players pw))
         (count (length players))
         (table (%pw-voice-table pw)))
    (if (and (plusp count)
             (every (lambda (value) (let ((k (%digits-integer value))) (and k (<= 1 k count)))) values))
        (let ((voices (loop for player in players
                            collect (make-%voice :candidate (%attr player "id")
                                                 :name (%nonempty-text (%kid (%walk player) "player-name"))))))
          (loop for voice in voices for k from 1 do (setf (gethash (format nil "~D" k) table) voice))
          (dolist (value values) (setf (gethash value table) (nth (1- (%digits-integer value)) voices)))
          (setf (%pw-voices pw) voices))
        (let ((ordered (append (stable-sort (remove-if-not #'%digits-integer (copy-list values))
                                            #'< :key #'%digits-integer)
                               (remove-if #'%digits-integer values))))
          (setf (%pw-voices pw)
                (mapcar (lambda (value)
                          (setf (gethash value table) (make-%voice)))
                        (or ordered (list "1"))))))
    (dolist (event events)
      (setf (%event-vc event) (gethash (%event-voice event) table)))
    (dolist (voice (%pw-voices pw))
      (let* ((own (remove voice events :key #'%event-vc :test-not #'eq))
             (stems (mapcan (lambda (event) (copy-list (%event-stems event))) own))
             (up (member :up stems))
             (down (member :down stems)))
        (setf (%voice-staff voice) (if own (%event-staff (first own)) 1)
              (%voice-stem voice) (cond ((and up (not down)) :up)
                                        ((and down (not up)) :down)))))))

(defun %gap-rests (start length msr i)
  "Hidden rests filling LENGTH from START in the measure record MSR (measure I)."
  (let* ((meter (%msr-meter msr))
         (shift (if (%msr-pickup msr) (- (music-theory:meter-measure-duration meter) (%msr-reach msr)) 0))
         (pieces (handler-case (music-theory:split-duration length :meter meter :offset (+ start shift))
                   (music-theory:music-theory-error () (list length))))
         (at start))
    (loop for piece in pieces
          collect (make-%event :rest-p t :hidden t :duration piece :onset at :measure i)
          do (incf at piece))))

(defun %fill-gaps (events msr i)
  "EVENTS, sorted, with every stretch of [0, L) they don't cover filled."
  (let ((at 0) (out '()))
    (flet ((gap (end)
             (when (< at end)
               (dolist (rest (%gap-rests at (- end at) msr i)) (push rest out))
               (setf at end))))
      (dolist (event events)
        (gap (%event-onset event))
        (push event out)
        (unless (%event-grace event)
          (setf at (+ (%event-onset event) (%event-duration event)))))
      (gap (%msr-reach msr)))
    (nreverse out)))

(defun %fill-voices (pw starts)
  "Every voice's events per measure: onset order, gaps filled."
  (let ((count (length starts)))
    (dolist (voice (%pw-voices pw))
      (let ((buckets (make-array count :initial-element '())))
        (dolist (event (%pw-events pw))            ; reverse document order
          (when (eq (%event-vc event) voice)
            (push event (svref buckets (%event-measure event)))))
        (setf (%voice-measures voice)
              (loop for i below count
                    for events = (stable-sort (svref buckets i) #'< :key #'%event-onset)
                    collect (and events (%fill-gaps events (svref starts i) i))))
        (dolist (events (%voice-measures voice))
          (loop for event in events
                for k from 0
                do (setf (%event-index event) k
                         (%event-vc event) voice)))))))

(defun %link-ties (pw starts)
  "The TIE of every note with a tie start (file header, \"Ties\")."
  (let ((notes (reverse (%pw-notes pw))))
    (dolist (note notes)
      (when (%note-tie-loc note)
        (let* ((event (%note-event note))
               (onset (+ (%abs-onset event starts) (%event-duration event)))
               (target (find-if (lambda (other)
                                  (let ((other-event (%note-event other)))
                                    (and (eq (%event-vc other-event) (%event-vc event))
                                         (= (%abs-onset other-event starts) onset)
                                         (equalp (%note-pitch other) (%note-pitch note)))))
                                notes)))
          (if target
              (setf (%note-tie note) (make-%tie :candidate (%note-tie-candidate note) :target target))
              (%unsupported (%note-tie-name note) (%note-tie-loc note) "a tie with no note to end on")))))))

(defun %target-voice (pw voice staff)
  "ATTACHMENT's target voice for a direction with <voice> VOICE and <staff> STAFF."
  (or (and voice (gethash voice (%pw-voice-table pw)))
      (find (or staff 1) (%pw-voices pw) :key #'%voice-staff)
      (first (%pw-voices pw))))

(defun %attach (pw voice staff measure position doc)
  "The event ATTACHMENT finds for a direction read at document index DOC
(file header), or NIL."
  (let ((events (nth measure (%voice-measures (%target-voice pw voice staff))))
        (best nil))
    (dolist (event events)
      (when (and (%event-read-p event) (> (%event-doc event) doc) (>= (%event-onset event) position)
                 (or (null best) (< (%event-doc event) (%event-doc best))))
        (setf best event)))
    (or best (find-if (lambda (event) (<= (%event-onset event) position)) events :from-end t))))

(defun %link-dynamics (pw)
  "Every dynamic on its event, in document order; a second one for an event is
unsupported."
  (dolist (dyn (reverse (%pw-dyns pw)))
    (let ((event (or (%dyn-event dyn)
                     (%attach pw (%dyn-voice dyn) (%dyn-staff dyn) (%dyn-measure dyn)
                              (%dyn-position dyn) (%dyn-doc dyn)))))
      (if (null event)
          (%unsupported "dynamics" (%dyn-loc dyn) "no event to put the dynamic on")
          (dolist (mark (%dyn-marks dyn))
            (when (%event-dynamic event)
              (%unsupported "dynamics" (%dyn-loc dyn) "a second dynamic for one event")
              (return))
            (setf (%event-dynamic event) mark)
            (when (%dyn-dir dyn)
              (setf (%dir-dynamics (%dyn-dir dyn)) (append (%dir-dynamics (%dyn-dir dyn)) (list mark)))))))))

(defun %wedge-end (pw wedge position starts)
  "The last event read from a <note> of WEDGE's target voice whose absolute onset
is before POSITION, or NIL."
  (let ((best nil))
    (dolist (events (%voice-measures (%target-voice pw (%wedge-voice wedge) (%wedge-staff wedge))) best)
      (dolist (event events)
        (when (and (%event-read-p event) (< (%abs-onset event starts) position))
          (setf best event))))))

(defun %link-wedges (pw starts)
  "The hairpins of PW: starts by ATTACHMENT, stops closing the open wedge of
their number CLOSING picks (file header, <wedge>)."
  (let ((open '()))
    (dolist (wedge (reverse (%pw-wedges pw)))
      (if (eq (%wedge-kind wedge) :stop)
          (let* ((voice (%target-voice pw (%wedge-voice wedge) (%wedge-staff wedge)))
                 (entry (%closing-entry open (%wedge-number wedge)
                                        (lambda (entry)
                                          (eq (%event-vc (%span-start (second entry))) voice)))))
            (if (null entry)
                (%unsupported "wedge" (%wedge-loc wedge) "a wedge stop with no wedge open")
                (let* ((span (second entry))
                       (start (%span-start span))
                       (position (+ (%msr-start (svref starts (%wedge-measure wedge))) (%wedge-position wedge)))
                       (end (if (= position (%abs-onset start starts))
                                start
                                (%wedge-end pw wedge position starts))))
                  (if (null end)
                      (%unsupported "wedge" (%wedge-loc wedge) "no event to end the hairpin on")
                      (let ((dir (%wedge-dir (third entry))))
                        (setf open (remove entry open)
                              (%span-end span) end)
                        (push span (%pw-spanners pw))
                        (setf (%dir-hairpins dir) (append (%dir-hairpins dir) (list span))))))))
          (let ((start (%attach pw (%wedge-voice wedge) (%wedge-staff wedge) (%wedge-measure wedge)
                                (%wedge-position wedge) (%wedge-doc wedge))))
            (if start
                (push (list (%wedge-number wedge)
                            (make-%span :kind (%wedge-kind wedge) :start start :doc (%wedge-doc wedge))
                            wedge)
                      open)
                (%unsupported "wedge" (%wedge-loc wedge) "no event to start the hairpin on")))))
    (dolist (entry (reverse open))
      (%unsupported "wedge" (%wedge-loc (third entry)) "a hairpin still open at the end of the part"))))

(defun %distribute-carrier (dir)
  "Give DIR's id to the first element it yields (file header, \"Ids\")."
  (let ((first (find-if #'identity (append (%dir-jumps dir) (list (%dir-tempo dir) (%dir-rehearsal dir))
                                           (%dir-dynamics dir) (%dir-hairpins dir)))))
    (when (and first (%dir-candidate dir))
      (setf (%rec-candidate first) (%dir-candidate dir)))))

;;; The draft ---------------------------------------------------------------------------------------

(defun %build-tie (note)
  (let ((tie (%note-tie note)))
    (and tie
         (let* ((target (%tie-target tie))
                (event (%note-event target)))
           (score-protocol:make-tie :id (%id tie)
                                    :end (%handle (if (rest (%event-notes event)) target event)))))))

(defun %build-event (event)
  (let* ((fermata (%event-fermata event))
         (dynamic (%event-dynamic event))
         (marks (list :fermata (and fermata (score-protocol:make-fermata :id (%id fermata)
                                                                          :shape (%mark-value fermata)))
                      :dynamic (and dynamic (score-protocol:make-dynamic-mark :id (%id dynamic)
                                                                               :value (%mark-value dynamic)))
                      :lyrics (mapcar (lambda (lyric)
                                        (score-protocol:make-lyric
                                         :id (%id lyric) :verse (%lyr-verse lyric) :text (%lyr-text lyric)
                                         :syllabic (%lyr-syllabic lyric) :extender (%lyr-extender lyric)))
                                      (%event-lyrics event))))
         (notes (%event-notes event)))
    (if (%event-rest-p event)
        (apply #'score-protocol:make-rest-event
               :id (%id event) :duration (%event-duration event) :tuplet (%event-tuplet event)
               :measure-rest-p (%event-measure-rest event) :hidden-p (%event-hidden event) marks)
        (let ((sounding (list* :duration (%event-duration event) :tuplet (%event-tuplet event)
                               :grace (%event-grace event)
                               :articulations (mapcar (lambda (mark)
                                                        (score-protocol:make-articulation
                                                         :id (%id mark) :kind (%mark-value mark)))
                                                      (%event-articulations event))
                               :breath-mark (let ((breath (%event-breath event)))
                                              (and breath (score-protocol:make-breath-mark :id (%id breath))))
                               marks)))
          (if (rest notes)
              (apply #'score-protocol:make-chord-event
                     :id (%id event)
                     :notes (mapcar (lambda (note)
                                      (score-protocol:make-chord-note
                                       :id (%id note) :pitch (%note-pitch note)
                                       :accidental (%note-accidental note) :tie (%build-tie note)))
                                    notes)
                     sounding)
              (let ((note (first notes)))
                (apply #'score-protocol:make-note-event
                       :id (%id event) :pitch (%note-pitch note) :accidental (%note-accidental note)
                       :tie (%build-tie note) sounding)))))))

(defun %build-part (pw)
  (score-protocol:make-part
   :id (%id pw) :name (%pw-name pw) :abbreviation (%pw-abbreviation pw)
   :staves (loop for k from 1 to (max (or (%pw-staves pw) 1) (%pw-max-staff pw))
                 collect (let ((entry (assoc k (%pw-clefs pw))))
                           (score-protocol:make-staff :id (%id (make-%rec :candidate (third entry)))
                                                      :clef (or (second entry) :treble))))
   :voices (loop for voice in (%pw-voices pw)
                 collect (score-protocol:make-voice
                          :id (%id voice) :name (%voice-name voice) :staff (%voice-staff voice)
                          :stem (%voice-stem voice)
                          :measures (mapcar (lambda (events) (mapcar #'%build-event events))
                                            (%voice-measures voice))))))

(defun %build-measure (msr)
  (let ((ending (%msr-ending msr))
        (rehearsal (%msr-rehearsal msr)))
    (score-protocol:make-measure-info
     :id (%id msr) :number (%msr-number msr) :time (%msr-time msr) :key (%msr-key msr)
     :pickup-p (%msr-pickup msr) :length (%msr-length msr) :barline (%msr-barline msr)
     :repeat-start (%msr-repeat-start msr) :repeat-end (%msr-repeat-end msr)
     :ending (and ending (score-protocol:make-ending :id (%id ending) :passes (%ending-passes ending)
                                                     :measures (%ending-measures ending)))
     :jump (mapcar (lambda (mark) (score-protocol:make-jump-mark :id (%id mark) :kind (%mark-value mark)))
                   (%msr-jumps msr))
     :rehearsal (and rehearsal (score-protocol:make-rehearsal-mark :id (%id rehearsal)
                                                                   :text (%mark-value rehearsal)))
     :tempo (mapcar (lambda (mark)
                      (score-protocol:make-tempo-mark :id (%id mark) :offset (%tmark-offset mark)
                                                      :tempo (%tmark-tempo mark) :text (%tmark-text mark)))
                    (%msr-tempos msr)))))

(defun %spanner-key (pw span)
  "(part measure voice event kind document) of SPAN's start (file header, Round
trip: SCORE-SPANNERS in the document order of their starts)."
  (let ((start (%span-start span)))
    (list (%pw-index pw) (%event-measure start) (position (%event-vc start) (%pw-voices pw))
          (%event-index start) (if (eq (%span-kind span) :slur) 1 0) (%span-doc span))))

(defun %key< (a b)
  (loop for x in a for y in b
        do (cond ((< x y) (return t)) ((> x y) (return nil)))
        finally (return nil)))

(defun %build-draft (metadata msrs pws)
  "The draft score: every element with its handle as id (support.lisp)."
  (let* ((measures (mapcar #'%build-measure msrs))
         (parts (mapcar #'%build-part pws))
         (anchors (loop for pw in pws
                        append (loop for anchor in (reverse (%pw-anchors pw))
                                     collect (score-protocol:make-chord-symbol-anchor
                                              :id (%id anchor)
                                              :position (cons (%msr-bar (nth (%anchor-measure anchor) msrs))
                                                              (%anchor-offset anchor))
                                              :symbol (%anchor-symbol anchor)))))
         (spans (mapcar #'cdr (stable-sort (loop for pw in pws
                                                 append (loop for span in (reverse (%pw-spanners pw))
                                                              collect (cons (%spanner-key pw span) span)))
                                           #'%key< :key #'car)))
         (spanners (loop for span in spans
                         collect (score-protocol:make-spanner :id (%id span) :kind (%span-kind span)
                                                              :start (%handle (%span-start span))
                                                              :end (%handle (%span-end span))))))
    (score-protocol:make-score :metadata metadata :measures measures :parts parts
                               :chord-symbols anchors :spanners spanners)))
