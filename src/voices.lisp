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
;;;; The staff SPLITS when, in at least one measure, L's voice measure is empty
;;;; and U's holds a CHORD-EVENT. Then U's STEM becomes :UP and L's :DOWN, and
;;;; each measure in which L's voice measure is empty and U's is not is SPLIT:
;;;; every event E of U's voice measure gives one event to U and one to L, in
;;;; order. So a measure of single notes and rests on a split staff is split
;;;; too: in hymnal layout that is a measure the two voices sing in unison,
;;;; printed with one notehead. Other measures are unchanged. When the staff
;;;; doesn't split, a new L is not added and the stems are unchanged.
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

;;; The split works on canonical forms (score-protocol sexp.lisp): copies are
;;; plist edits, and the new score goes through %SETTLE-IDS (support.lisp) with
;;; the input's ids final, so new elements are minted above its counter in
;;; document order, as COPY-SCORE mints them. A unison copy that a copied tie
;;; ends on gets a handle, so the tie can name it before it has an id.

(defparameter +guess-provenance+ '(:source :musicxml :backend "score-backend-musicxml")
  "The canonical form of a guess's PROVENANCE (file header). Data.")

(defstruct (%split (:copier nil) (:predicate nil))
  "A split in progress: SPLIT-P once a staff splits; UPPER maps a dropped upper
note's id to its chord's; GUESSES maps a draft id to the guess's WHAT."
  (split-p nil)
  (upper (make-hash-table :test 'equal))
  (guesses (make-hash-table :test 'equal)))

(defun %get (form key &optional default)
  "KEY's value in the element FORM, DEFAULT when the form leaves it out."
  (getf (cdr form) key default))

(defun %put (form key value)
  "The element FORM with KEY's value VALUE, or without KEY when VALUE is NIL."
  (let ((plist (loop for (k v) on (cdr form) by #'cddr unless (eq k key) nconc (list k v))))
    (cons (car form) (if value (append plist (list key value)) plist))))

(defun %without-ids (form)
  (%map-form form (constantly nil) #'identity))

(defun %guess (form)
  (%put (%put form :provenance +guess-provenance+) :confidence 1/2))

(defun %pitch< (a b)
  "True when the pitch text A sorts below B (PITCH-MIDI, then
PITCH-DIATONIC-INDEX)."
  (let ((p (music-theory:parse-pitch a))
        (q (music-theory:parse-pitch b)))
    (or (< (music-theory:pitch-midi p) (music-theory:pitch-midi q))
        (and (= (music-theory:pitch-midi p) (music-theory:pitch-midi q))
             (< (music-theory:pitch-diatonic-index p) (music-theory:pitch-diatonic-index q))))))

(defun %mark-copies (event)
  "The FERMATA, DYNAMIC, ARTICULATIONS and BREATH-MARK of the event form EVENT,
without ids, as a plist."
  (loop for key in '(:fermata :dynamic :articulations :breath-mark)
        for value = (%get event key)
        when value nconc (list key (%without-ids value))))

(defun %split-event (event split counterparts)
  "(values upper lower): the events the event form EVENT gives U and L (file
header). COUNTERPARTS maps a unison-copied note event's id to its copy's handle."
  (let ((id (%get event :id))
        (shared (loop for key in '(:duration :tuplet :grace)
                      for value = (%get event key)
                      when value nconc (list key value))))
    (ecase (car event)
      (:chord
       (let* ((notes (%get event :notes))
                     (sorted (stable-sort (copy-list notes) #'%pitch< :key (lambda (n) (%get n :pitch))))
                     (high (car (last sorted)))
                     (low (first sorted))
                     (three (> (length notes) 2))
                     (upper (append (list :note :id id :pitch (%get high :pitch)
                                          :accidental (%get high :accidental) :tie (%get high :tie))
                                    shared
                                    (loop for key in '(:articulations :fermata :breath-mark :dynamic :lyrics
                                                       :provenance :confidence)
                                          for value = (%get event key)
                                          when value nconc (list key value))))
                     (lower (if three
                                (let ((handle (%new-handle)))
                                  (setf (gethash handle (%split-guesses split)) "chord split")
                                  (%guess (append (list :chord :id handle :notes (remove high notes :count 1))
                                                  shared (%mark-copies event))))
                                (append (list :note :id (%get low :id) :pitch (%get low :pitch)
                                              :accidental (%get low :accidental) :tie (%get low :tie))
                                        shared (%mark-copies event)
                                        (loop for key in '(:provenance :confidence)
                                              for value = (%get low key)
                                              when value nconc (list key value))))))
         (setf (gethash (%get high :id) (%split-upper split)) id)
         (when three
           (setf (gethash id (%split-guesses split)) "chord split"))
         (values (if three (%guess upper) upper) lower)))
      (:note
       (let* ((handle (gethash id counterparts))
              (tie (%get event :tie))
              (end (and tie (gethash (%get tie :end) counterparts))))
         (setf (gethash handle (%split-guesses split)) "unison")
         (values event
                 (%guess (%put (%put (%put (%without-ids event) :lyrics nil) :id handle)
                               :tie (and end (list :tie :end end)))))))
      (:rest
       (values event (%put (%without-ids event) :lyrics nil))))))

(defun %split-measures (upper-measures lower-measures)
  "The indices (from 0, ascending) of the measures that are SPLIT on a staff
whose U has the voice measures UPPER-MEASURES and L LOWER-MEASURES, lists of
event forms of one length (NIL for an empty voice measure); NIL when the staff
doesn't split (file header)."
  (declare (ignore upper-measures lower-measures))
  (%sc21-pending '%split-measures))

(defun %split-staff (voices split measure-count)
  "((original . replacement) ...) for VOICES, the forms of one staff's voices in
part order, when the staff splits (file header); a new L has original NIL."
  (when (<= 1 (length voices) 2)
    (destructuring-bind (upper &optional lower)
        (if (and (= 2 (length voices))
                 (eq (%get (second voices) :stem) :up)
                 (eq (%get (first voices) :stem) :down))
            (reverse voices)
            voices)
      (let* ((upper-measures (%get upper :measures))
             (lower-measures (if lower (%get lower :measures) (make-list measure-count)))
             (splits (%split-measures upper-measures lower-measures)))
        (when splits
          (let ((counterparts (make-hash-table :test 'equal)))
            (dolist (j splits)
              (dolist (event (nth j upper-measures))
                (when (eq (car event) :note)
                  (setf (gethash (%get event :id) counterparts) (%new-handle)))))
            (let ((new-upper (copy-list upper-measures))
                  (new-lower (copy-list lower-measures)))
              (dolist (j splits)
                (let ((pairs (mapcar (lambda (event)
                                       (multiple-value-list (%split-event event split counterparts)))
                                     (nth j upper-measures))))
                  (setf (nth j new-upper) (mapcar #'first pairs)
                        (nth j new-lower) (mapcar #'second pairs))))
              (setf (%split-split-p split) t)
              (list (cons upper (%put (%put upper :stem :up) :measures new-upper))
                    (cons lower (%put (%put (or lower (list :voice :staff (%get upper :staff 1)))
                                            :stem :down)
                                      :measures new-lower))))))))))

(defun %split-part (part split measure-count)
  "The part form PART with its shared-stem staves split: each split voice
replaced, a new L right after its U."
  (let ((voices (%get part :voices)))
    (loop for k from 1 to (length (%get part :staves))
          for pairs = (%split-staff (remove k voices :key (lambda (voice) (%get voice :staff 1))
                                                     :test-not #'eql)
                                    split measure-count)
          when pairs
            do (destructuring-bind ((upper . new-upper) (lower . new-lower)) pairs
                 (setf voices
                       (loop for voice in voices
                             if (eq voice upper)
                               collect new-upper
                               and when (null lower) collect new-lower end
                             else if (eq voice lower)
                                    collect new-lower
                             else collect voice))))
    (%put part :voices voices)))

(defun %form-strings (form)
  "Every id and reference string in the score FORM, as a table."
  (let ((strings (make-hash-table :test 'equal)))
    (flet ((note (string) (setf (gethash string strings) t) string))
      (%map-form form #'note #'note))
    strings))

(defun split-voices (score)
  "SCORE with shared-stem staves split into two voices each (file header)."
  (check-type score score-protocol:score)
  (let* ((form (score-protocol:score-to-sexp score))
         (input (make-hash-table :test 'equal))
         (*reserved-ids* (%form-strings form))
         (*handle-count* 0)
         (split (make-%split))
         (measure-count (length (getf (cdr form) :measures)))
         (parts (mapcar (lambda (part) (%split-part part split measure-count))
                        (getf (cdr form) :parts))))
    (if (not (%split-split-p split))
        score
        (let ((draft (score-protocol:sexp-to-score
                      (%map-form (cons :score (loop for (key value) on (cdr form) by #'cddr
                                                    nconc (list key (if (eq key :parts) parts value))))
                                 #'identity
                                 (lambda (reference)
                                   (values (gethash reference (%split-upper split) reference)))))))
          (dolist (element (score-protocol:score-elements score))
            (setf (gethash (score-protocol:element-id element) input) t))
          (multiple-value-bind (new finals order)
              (%settle-ids draft :final-p (lambda (id) (gethash id input))
                                 :id-counter (score-protocol:score-id-counter score))
            (dolist (id order new)
              (let ((what (gethash id (%split-guesses split))))
                (when what
                  (signal 'score-protocol:low-confidence-guess
                          :element-id (values (gethash id finals id)) :what what :confidence 1/2)))))))))
