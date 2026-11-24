;;;; SC2 the MusicXML vocabulary: which elements the reader maps, which it
;;;; drops, and the value tables both directions share.
;;;;
;;;; Element classes. The reader walks a MusicXML document from <score-partwise>
;;;; down. Every element it walks is a CONTEXT, a row of +ELEMENT-CONTEXTS+:
;;;; (context mapped ignored). A child element of a context is
;;;;   MAPPED       when its name is in MAPPED: the rules of reader.lisp read it;
;;;;   IGNORED      when its name is in IGNORED: it is dropped, silently, with
;;;;                everything inside it (layout, appearance, playback and
;;;;                bookkeeping that the model leaves to the engraver or derives);
;;;;   UNSUPPORTED  otherwise: content the model can't hold. The reader signals
;;;;                MUSICXML-UNSUPPORTED for it (reader.lisp, "Unsupported"),
;;;;                naming the child, which skipping drops; except that a child
;;;;                listed in +UNSUPPORTED-PARENTS+ makes its parent unsupported:
;;;;                the parent is named and dropped (an <unpitched> note, a <key>
;;;;                with <key-step>, a <time> with <senza-misura>, ...).
;;;; Names compare with STRING= on the local name. Text, comments and processing
;;;; instructions inside a context are skipped. Attributes are not elements:
;;;; an attribute the rules don't name is ignored (default-x, color, font-*,
;;;; placement, print-object except on rests, ...). A value outside a value
;;;; table below (a dynamic "ppppp", a clef sign "percussion", a <kind> "other")
;;;; is unsupported too; reader.lisp names the element reported for each case.
;;;;
;;;; Value tables. Each is data read in both directions: the writer looks up the
;;;; model value, the reader the MusicXML text. Text compares with STRING= after
;;;; trimming XML whitespace (space, tab, CR, LF) from both ends.

(in-package #:score-backend-musicxml)

(defparameter +musicxml-doctype+
  '("score-partwise" "-//Recordare//DTD MusicXML 4.0 Partwise//EN"
    "http://www.musicxml.org/dtds/partwise.dtd")
  "(name public-id system-id) of the DOCTYPE the writer emits. The reader never
fetches the system id. Data.")

(defparameter +musicxml-version+ "4.0"
  "The version attribute of the <score-partwise> the writer emits. Data.")

(defparameter +element-contexts+
  '(("score-partwise" ("work" "movement-title" "identification" "part-list" "part")
     ("movement-number" "defaults" "credit"))
    ("work" ("work-title") ("work-number" "opus"))
    ("identification" ("creator" "rights") ("encoding" "source" "relation" "miscellaneous"))
    ("part-list" ("score-part") ("part-group"))
    ("score-part" ("part-name" "part-abbreviation" "player")
     ("identification" "part-link" "part-name-display" "part-abbreviation-display" "group"
      "score-instrument" "midi-device" "midi-instrument"))
    ("player" ("player-name") ())
    ("part" ("measure") ())
    ("measure" ("note" "backup" "forward" "direction" "attributes" "harmony" "sound" "barline")
     ("print" "listening" "grouping" "link" "bookmark"))
    ("attributes" ("divisions" "key" "time" "staves" "clef")
     ("footnote" "level" "part-symbol" "instruments" "staff-details" "directive"
      "measure-style"))
    ("key" ("fifths" "mode") ("cancel" "key-octave"))
    ("time" ("beats" "beat-type") ())
    ("clef" ("sign" "line" "clef-octave-change") ())
    ("note" ("grace" "chord" "pitch" "rest" "tie" "duration" "voice" "type" "dot"
             "accidental" "time-modification" "stem" "staff" "notations" "lyric")
     ("instrument" "footnote" "level" "notehead" "notehead-text" "beam" "play" "listen"))
    ("pitch" ("step" "alter" "octave") ())
    ("rest" () ("display-step" "display-octave"))
    ("time-modification" ("actual-notes" "normal-notes") ("normal-type" "normal-dot"))
    ("notations" ("tied" "slur" "articulations" "dynamics" "fermata")
     ("footnote" "level" "tuplet"))
    ("articulations" ("accent" "strong-accent" "staccato" "tenuto" "detached-legato"
                      "staccatissimo" "spiccato" "stress" "unstress" "soft-accent"
                      "breath-mark")
     ())
    ("lyric" ("syllabic" "text" "elision" "extend") ("end-line" "end-paragraph" "footnote" "level"))
    ("direction" ("direction-type" "offset" "voice" "staff" "sound") ("footnote" "level" "listening"))
    ("direction-type" ("rehearsal" "segno" "coda" "words" "wedge" "dynamics" "metronome")
     ("dashes" "image" "staff-divide"))
    ("metronome" ("beat-unit" "beat-unit-dot" "per-minute") ())
    ("dynamics" ("pppp" "ppp" "pp" "p" "mp" "mf" "f" "ff" "fff" "ffff" "fp" "sf" "sfp"
                 "sfz" "fz" "rf" "rfz")
     ())
    ("harmony" ("root" "kind" "bass" "degree" "offset") ("frame" "footnote" "level" "staff"))
    ("root" ("root-step" "root-alter") ())
    ("bass" ("bass-step" "bass-alter") ("bass-separator"))
    ("degree" ("degree-value" "degree-alter" "degree-type") ())
    ("barline" ("bar-style" "ending" "repeat") ("footnote" "level"))
    ("sound" () ("instrument-change" "midi-device" "midi-instrument" "play" "swing" "offset")))
  "(context mapped ignored) per element the reader walks (file header). Data.")

(defparameter +unsupported-parents+
  '(("unpitched" . "note") ("cue" . "note") ("key-step" . "key") ("key-alter" . "key")
    ("key-accidental" . "key") ("interchangeable" . "time") ("senza-misura" . "time")
    ("numeral" . "harmony") ("function" . "harmony") ("laughing" . "lyric")
    ("humming" . "lyric"))
  "(child . parent): an unsupported CHILD that makes its PARENT the unsupported
element (file header). Data.")

(defparameter +note-types+
  '((2 "breve") (1 "whole") (1/2 "half") (1/4 "quarter") (1/8 "eighth") (1/16 "16th")
    (1/32 "32nd") (1/64 "64th") (1/128 "128th"))
  "(base <type>): the notated base values (music-theory DURATION-DOTS bases) and
their MusicXML note-type names. Data.")

(defparameter +clef-signs+
  '((:treble "G" 2 0) (:treble-8vb "G" 2 -1) (:treble-8va "G" 2 1) (:bass "F" 4 0)
    (:bass-8vb "F" 4 -1) (:alto "C" 3 0) (:tenor "C" 4 0))
  "(clef sign line octave-change): STAFF-CLEF values and their <clef>. Data.")

(defparameter +bar-styles+
  '((:regular "regular") (:double "light-light") (:final "light-heavy") (:dashed "dashed")
    (:dotted "dotted") (:heavy "heavy") (:none "none"))
  "(barline <bar-style>): MEASURE-INFO-BARLINE values. Data.")

(defparameter +articulation-elements+
  '((:accent "accent") (:marcato "strong-accent") (:staccato "staccato")
    (:staccatissimo "staccatissimo") (:tenuto "tenuto") (:detached-legato "detached-legato")
    (:spiccato "spiccato") (:stress "stress") (:unstress "unstress")
    (:soft-accent "soft-accent"))
  "(kind element): ARTICULATION-KIND values and their <articulations> children.
Data.")

(defparameter +fermata-shapes+
  '((:normal "normal") (:short "angled") (:long "square"))
  "(shape content): FERMATA-SHAPE values and the content of <fermata>. Empty
content reads as :NORMAL. Data.")

(defparameter +syllabic-names+
  '((:single "single") (:begin "begin") (:middle "middle") (:end "end"))
  "(syllabic <syllabic>): LYRIC-SYLLABIC values. Data.")

(defparameter +accidental-names+
  '((-2 "flat-flat") (-1 "flat") (0 "natural") (1 "sharp") (2 "double-sharp"))
  "(alter <accidental>): the accidental the writer shows for a pitch's ALTER.
Data.")

(defparameter +metadata-creators+
  '((:composer "composer") (:lyricist "lyricist") (:arranger "arranger"))
  "(metadata-key <creator> type): the creators the model keeps. Data.")

(defparameter +jump-directions+
  '((:segno nil "segno" "segno" ())
    (:coda nil "coda" "coda" ())
    (:to-coda "To Coda" "tocoda" "coda" ())
    (:fine "Fine" "fine" "yes" ())
    (:da-capo "D.C." "dacapo" "yes" ("Da Capo"))
    (:da-capo-al-fine "D.C. al Fine" "dacapo" "yes" ("Da Capo al Fine"))
    (:da-capo-al-coda "D.C. al Coda" "dacapo" "yes" ("Da Capo al Coda"))
    (:dal-segno "D.S." "dalsegno" "segno" ("Dal Segno"))
    (:dal-segno-al-fine "D.S. al Fine" "dalsegno" "segno" ("Dal Segno al Fine"))
    (:dal-segno-al-coda "D.S. al Coda" "dalsegno" "segno" ("Dal Segno al Coda")))
  "(kind words sound-attribute sound-value other-words) per JUMP-MARK-KIND, in
+JUMPS+ order. WORDS is the <words> text the writer emits (NIL: the kind is the
<segno> or <coda> direction-type itself); SOUND-ATTRIBUTE and SOUND-VALUE the
<sound> attribute it carries. The reader accepts WORDS and OTHER-WORDS,
compared with STRING-EQUAL after trimming (reader.lisp). Data.")
