;;;; SC2 hymnal voice splitting: two voices notated on one staff as shared-stem
;;;; chords become two voice lines.
;;;;
;;;; A hymnal prints soprano and alto on the treble staff, tenor and bass on the
;;;; bass staff. Where two voices move together they share stems: one chord
;;;; carries both. Where they part, the staff switches to two voices (MusicXML
;;;; <voice> 1 and 2, stems up and down). Reading such a file gives one voice per
;;;; staff holding chords, sometimes a second voice too. SPLIT-VOICES turns the
;;;; shared-stem measures into two voices, like a hand-split edition.
;;;;
;;;; SPLIT-VOICES score → a new SCORE (READ-MUSICXML's :SPLIT-VOICES :AUTO calls
;;;; it on the score it read). Per part and per staff k, with V the part's voices
;;;; whose STAFF is k, in part order:
;;;;   |V| = 0 or |V| > 2  the staff is left as it is.
;;;;   |V| = 1  U is that voice; L is a new voice (no id: MAKE-SCORE mints one;
;;;;            NAME NIL, STAFF k, STEM :DOWN, every voice measure empty),
;;;;            inserted right after U in the part's voices.
;;;;   |V| = 2  U and L are the two: the one with STEM :UP is U when their stems
;;;;            are :UP and :DOWN, else the first in part order is U.
;;;; U's STEM becomes :UP and L's :DOWN. Then each measure in which L's voice
;;;; measure is empty and U's holds at least one CHORD-EVENT is SPLIT: every
;;;; event E of U's voice measure gives one event to U and one to L, in order.
;;;; Other measures are unchanged. When no measure of a staff splits, a new L is
;;;; not added and the stems are unchanged.
;;;;   CHORD-EVENT with notes sorted by pitch (PITCH-MIDI, then
;;;;      PITCH-DIATONIC-INDEX, then chord order), h the highest and l the lowest:
;;;;      U gets a NOTE-EVENT with E's id and h's pitch, accidental and tie; L
;;;;      gets, with two notes, a NOTE-EVENT with l's id, pitch, accidental and
;;;;      tie; with three or more, a CHORD-EVENT (no id) of every note but h,
;;;;      in chord order, keeping their ids. Both have E's DURATION, TUPLET and
;;;;      GRACE. h's own id is dropped: a TIE whose END was h's id now ends on E's
;;;;      id. With three or more notes, both events are a guess.
;;;;   NOTE-EVENT  U keeps E; L gets a copy without lyrics and without ids (a
;;;;      unison: both voices sing it). The copy is a guess.
;;;;   REST-EVENT  U keeps E; L gets a copy without lyrics and without ids.
;;;; Marks: U's event keeps E's FERMATA, DYNAMIC, ARTICULATIONS, BREATH-MARK and
;;;; LYRICS (with their ids); L's gets copies of the FERMATA, DYNAMIC,
;;;; ARTICULATIONS and BREATH-MARK without ids, and no lyrics. A TIE on a copied
;;;; unison note is copied (no id) when its END's event was split in the same
;;;; way, ending on that event's L counterpart; otherwise the copy has no tie.
;;;; Spanners are unchanged (they stay on U's events).
;;;; A guess has CONFIDENCE 1/2 and PROVENANCE (make-provenance :source :musicxml
;;;; :backend "score-backend-musicxml"). After the new score is built (so with
;;;; its minted ids) SPLIT-VOICES signals LOW-CONFIDENCE-GUESS with SIGNAL for
;;;; each guess, in document order: ELEMENT-ID its id, WHAT "unison" for a copied
;;;; note and "chord split" for an event of a three-note chord, CONFIDENCE 1/2.
;;;; Every element the split doesn't touch keeps its id; new ones are minted by
;;;; COPY-SCORE, so a split score never reuses a serial.

(in-package #:score-backend-musicxml)

(defun split-voices (score)
  "SCORE with shared-stem staves split into two voices each (file header)."
  (declare (ignore score))
  (%sc2-pending 'split-voices))
