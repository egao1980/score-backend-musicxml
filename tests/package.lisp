(defpackage #:score-backend-musicxml/tests
  (:use #:cl #:rove #:score-protocol #:music-theory #:score-backend-musicxml))

(in-package #:score-backend-musicxml/tests)

;;; Fixtures --------------------------------------------------------------------

(defparameter +sc0-names+
  '("sc0-carol-6-8" "sc0-chords-under-rests" "sc0-jumps" "sc0-key-change" "sc0-keyboard"
    "sc0-omr-result" "sc0-pickup" "sc0-repeats-voltas" "sc0-satb" "sc0-three-verses")
  "The SC0 fixture scores, tests/fixtures/sc0/<name>.sexp, and their goldens.")

(defparameter +corpus-names+
  '("amazing-grace" "auld-lang-syne" "camptown-races" "frere-jacques" "greensleeves"
    "home-on-the-range" "hymn-shared" "hymn-split" "hymn-to-joy" "joy-to-the-world"
    "londonderry-air" "oh-susanna" "old-hundredth" "red-river-valley" "scarborough-fair"
    "shenandoah" "silent-night" "simple-gifts" "swing-low" "twinkle-twinkle"
    "when-the-saints" "yankee-doodle")
  "The corpus, tests/fixtures/corpus/<name>.musicxml.")

(defun fixture-path (name)
  (asdf:system-relative-pathname "score-backend-musicxml/tests"
                                 (concatenate 'string "tests/fixtures/" name)))

(defun read-forms-file (name)
  "The single top-level form in tests/fixtures/NAME."
  (with-open-file (in (fixture-path name) :external-format :utf-8)
    (with-standard-io-syntax
      (let ((*read-eval* nil)
            (*package* (find-package '#:score-backend-musicxml/tests)))
        (read in)))))

(defun file-string (name)
  "The text of tests/fixtures/NAME (UTF-8)."
  (with-open-file (in (fixture-path name) :external-format :utf-8)
    (let ((s (make-string (file-length in))))
      (subseq s 0 (read-sequence s in)))))

(defun file-octets (name)
  (with-open-file (in (fixture-path name) :element-type '(unsigned-byte 8))
    (let ((v (make-array (file-length in) :element-type '(unsigned-byte 8))))
      (read-sequence v in)
      v)))

(defun sc0-form (name)
  (read-forms-file (format nil "sc0/~A.sexp" name)))

(defvar *sc0-scores* (make-hash-table :test 'equal))

(defun sc0-score (name)
  (or (gethash name *sc0-scores*)
      (setf (gethash name *sc0-scores*) (sexp-to-score (sc0-form name)))))

(defun golden-name (name) (format nil "golden/~A.musicxml" name))
(defun corpus-name (name) (format nil "corpus/~A.musicxml" name))

(defun read-fixture (name &rest keys)
  "READ-MUSICXML of tests/fixtures/NAME, as a pathname."
  (apply #'read-musicxml (fixture-path name) keys))

(defun quoted-rows (rows)
  "ROWS with every value quoted: DEFTEST-PARAMETRIZE evaluates the values of
:ROWS rows as forms, like literal rows."
  (mapcar (lambda (row) (mapcar (lambda (x) (list 'quote x)) row)) rows))

;;; Forms ---------------------------------------------------------------------------

(defparameter +element-kinds+
  '(:measure :part :staff :voice :rest :note :chord :chord-note :lyric :chord-symbol :spanner
    :dynamic :fermata :breath-mark :articulation :tie :tempo-mark :rehearsal :jump :ending)
  "The kind keywords of score-protocol element forms.")

(defun strip-keys (form keys)
  "FORM with the KEYS entries removed from every element form (and from the
score form), recursively."
  (cond ((atom form) form)
        ((member (car form) (cons :score +element-kinds+))
         (cons (car form)
               (loop for (key value) on (cdr form) by #'cddr
                     unless (member key keys)
                       nconc (list key (strip-keys value keys)))))
        (t (cons (strip-keys (car form) keys) (strip-keys (cdr form) keys)))))

(defun strip-ids (form)
  "FORM without ids, the id counter, provenance and confidence: content only."
  (strip-keys form '(:id :id-counter :provenance :confidence)))

(defun strip-chord-text (form)
  "FORM with :TEXT and :DIALECT removed from every chord-symbol's symbol plist."
  (cond ((atom form) form)
        ((eq (car form) :chord-symbol)
         (cons :chord-symbol
               (loop for (key value) on (cdr form) by #'cddr
                     nconc (list key (if (eq key :symbol)
                                         (loop for (k v) on value by #'cddr
                                               unless (member k '(:text :dialect))
                                                 nconc (list k v))
                                         value)))))
        (t (cons (strip-chord-text (car form)) (strip-chord-text (cdr form))))))

(defun lossless-form (name)
  "The SC0 fixture NAME as a MusicXML round trip returns it (src/writer.lisp,
Round trip): no provenance or confidence, chord symbols without TEXT or DIALECT."
  (strip-chord-text (strip-keys (sc0-form name) '(:provenance :confidence))))

(defun renumbered-form (score)
  "The canonical form of SCORE with every id, and every reference to one (a
tie's :END, a spanner's :START and :END), replaced by its element's place in
document order (\"i1\", \"i2\", ...), and without provenance, confidence and
the counter."
  (let ((names (make-hash-table :test 'equal)) (k 0))
    (dolist (e (score-elements score))
      (unless (gethash (element-id e) names)
        (setf (gethash (element-id e) names) (format nil "i~D" (incf k)))))
    (labels ((walk (form)
               (cond ((atom form) form)
                     ((member (car form) (cons :score +element-kinds+))
                      (cons (car form)
                            (loop for (key value) on (cdr form) by #'cddr
                                  unless (member key '(:id-counter :provenance :confidence))
                                    nconc (list key (if (and (member key '(:id :start :end)) (stringp value))
                                                        (or (gethash value names) value)
                                                        (walk value))))))
                     (t (cons (walk (car form)) (walk (cdr form)))))))
      (walk (score-to-sexp score)))))

(defun same-content-p (a b)
  "True when scores A and B are equal up to the names of their ids (and their
provenance and confidence)."
  (equal (renumbered-form a) (renumbered-form b)))

(defun seq-list (seq) (fset:convert 'list seq))

(defun part-at (score i) (nth i (seq-list (score-parts score))))

(defun voice-at (score part voice) (nth voice (part-voices (part-at score part))))

(defun voice-forms (score part voice)
  "The id-less forms of the events of VOICE of PART, per voice measure."
  (mapcar (lambda (events) (mapcar (lambda (e) (strip-ids (element-to-sexp e))) (seq-list events)))
          (seq-list (voice-measures (voice-at score part voice)))))

(defun measure-forms (score)
  (mapcar (lambda (m) (strip-ids (element-to-sexp m))) (seq-list (score-measure-map score))))

(defun cs (text &optional (dialect :pop))
  "The chord symbol TEXT reads as in DIALECT, with TEXT and DIALECT NIL: what
the MusicXML reader returns for it."
  (let ((c (parse-chord-symbol text :dialect dialect)))
    (make-chord-symbol :root (chord-symbol-root c) :quality (chord-symbol-quality c)
                       :extensions (chord-symbol-extensions c)
                       :alterations (chord-symbol-alterations c)
                       :suspension (chord-symbol-suspension c) :added (chord-symbol-added c)
                       :omitted (chord-symbol-omitted c) :bass (chord-symbol-bass c)
                       :no-chord-p (chord-symbol-no-chord-p c))))

;;; MusicXML snippets ------------------------------------------------------------------

(defun mxml (measures &key (divisions 1) (time '("4" "4")) (fifths 0) (head "") (score-part "")
                           (attributes t) (extra-parts '()) (part-id "P1"))
  "A partwise document: one part PART-ID holding MEASURES (strings, each a
measure's content, numbered 1, 2, ...; or (attributes content), the measure's
attribute text given as is); the first measure starts with
<attributes> (DIVISIONS, a key of FIFTHS, TIME) unless ATTRIBUTES is NIL. HEAD
goes before <part-list>, SCORE-PART inside the <score-part>. EXTRA-PARTS is a
list of (id measures) for more parts (no attributes added)."
  (with-output-to-string (s)
    (format s "<?xml version=\"1.0\" encoding=\"UTF-8\"?>~%<score-partwise version=\"4.0\">~A~%"
            head)
    (format s "<part-list><score-part id=~S><part-name>Test</part-name>~A</score-part>"
            part-id score-part)
    (loop for (id) in extra-parts
          do (format s "<score-part id=~S><part-name>~A</part-name></score-part>" id id))
    (format s "</part-list>~%<part id=~S>~%" part-id)
    (loop for m in measures
          for i from 1
          do (if (consp m)
                 (format s "<measure~A>" (first m))
                 (format s "<measure number=\"~D\">" i))
             (when (and attributes (= i 1))
               (format s "<attributes><divisions>~D</divisions><key><fifths>~D</fifths></key>~
<time><beats>~A</beats><beat-type>~A</beat-type></time></attributes>"
                       divisions fifths (first time) (second time)))
             (format s "~A</measure>~%" (if (consp m) (second m) m)))
    (format s "</part>~%")
    (loop for (id ms) in extra-parts
          do (format s "<part id=~S>~%" id)
             (loop for m in ms for i from 1
                   do (format s "<measure number=\"~D\">~A</measure>~%" i m))
             (format s "</part>~%"))
    (format s "</score-partwise>~%")))

(defun n (pitch duration &rest extra)
  "A <note> of PITCH (\"F#4\", or :rest) with DURATION divisions; EXTRA strings
go after <duration> (voice, staff, notations...)."
  (format nil "<note>~A<duration>~A</duration>~{~A~}</note>"
          (pitch-xml pitch) duration extra))

(defun pitch-xml (pitch)
  (if (eq pitch :rest)
      "<rest/>"
      (let ((p (parse-pitch pitch)))
        (format nil "<pitch><step>~C</step>~@[<alter>~D</alter>~]<octave>~D</octave></pitch>"
                (char "CDEFGAB" (spelled-pitch-letter p))
                (let ((a (spelled-pitch-alter p))) (and (/= a 0) a))
                (spelled-pitch-octave p)))))

(defun read-snippet (measures &rest keys &key split-voices (unsupported :error) &allow-other-keys)
  "READ-MUSICXML of (apply #'mxml MEASURES KEYS)."
  (let ((doc-keys (loop for (k v) on keys by #'cddr
                        unless (member k '(:split-voices :unsupported)) nconc (list k v))))
    (read-musicxml (apply #'mxml measures doc-keys)
                   :split-voices split-voices :unsupported unsupported)))

;;; Conditions -------------------------------------------------------------------------

(defun signalled (thunk &optional (type 'condition))
  "The first condition of TYPE THUNK signals, or NIL."
  (handler-case (progn (funcall thunk) nil)
    (condition (c) (and (typep c type) c))))

(defun collect-warnings (thunk type)
  "(values result conditions): THUNK's value and every condition of TYPE it
signalled (warnings muffled)."
  (let ((seen '()))
    (values (handler-bind ((condition (lambda (c)
                                        (when (typep c type)
                                          (push c seen)
                                          (when (find-restart 'muffle-warning c)
                                            (muffle-warning c))))))
              (funcall thunk))
            (nreverse seen))))

;;; Facts (the shape generate-sc2.py writes) ----------------------------------------

(defun fact-entry (file)
  "The plist of facts music21 read in FILE (tests/fixtures/sc2-facts.sexp)."
  (rest (assoc file (read-forms-file "sc2-facts.sexp") :test #'string=)))

(defun row-string (row) (prin1-to-string row))

(defun sorted-rows (rows)
  (sort (copy-list rows) #'string< :key #'row-string))

(defun note-names (event)
  (sort (mapcar #'pitch-name
                (typecase event
                  (note-event (list (note-pitch event)))
                  (chord-event (mapcar #'note-pitch (chord-event-notes event)))
                  (t '())))
        #'string<))

(defun event-tied-p (event)
  (typecase event
    (note-event (and (note-tie event) t))
    (chord-event (and (some #'note-tie (chord-event-notes event)) t))
    (t nil)))

(defun score-facts (score)
  "The facts of SCORE, in the shapes of generate-sc2.py (\"facts\")."
  (let* ((first (score-first-bar score))
         (measures (seq-list (score-measure-map score)))
         (rows-measures
           (loop for m in measures for i from 0
                 for bar = (+ first i)
                 collect (list i bar (bar-start score bar) (bar-length score bar))))
         (rows-events '()))
    (loop for part in (seq-list (score-parts score)) for pno from 1
          do (loop for voice in (part-voices part) for k from 1
                   do (loop for events in (seq-list (voice-measures voice)) for j from 0
                            for shared = (> (count-if (lambda (w)
                                                        (and (= (voice-staff w) (voice-staff voice))
                                                             (plusp (fset:size
                                                                     (fset:@ (voice-measures w) j)))))
                                                      (part-voices part))
                                            1)
                            do (dolist (e (seq-list events))
                                 (let ((grace (and (typep e 'sounding-event) (event-grace e) t)))
                                   (push (list pno (voice-staff voice) (and shared k) j
                                               (cdr (element-position score (element-id e)))
                                               (etypecase e
                                                 (rest-event :rest) (note-event :note)
                                                 (chord-event :chord))
                                               (note-names e) (event-duration e)
                                               (and (not grace) (event-tuplet e)) grace
                                               (and (typep e 'rest-event) (rest-event-hidden-p e))
                                               (event-tied-p e)
                                               (sort (mapcar (lambda (l)
                                                               (list (lyric-verse l) (lyric-syllabic l)
                                                                     (lyric-text l)))
                                                             (event-lyrics e))
                                                     #'< :key #'first))
                                         rows-events))))))
    (list :measures rows-measures
          :events (nreverse rows-events)
          :harmonies
          (loop for a in (seq-list (score-chord-symbols score))
                for sym = (anchor-symbol a)
                for (bar . offset) = (anchor-position a)
                collect (if (chord-symbol-no-chord-p sym)
                            (list (- bar first) offset nil nil '())
                            (let ((bass (and (chord-symbol-bass sym)
                                             (pitch-class-string (chord-symbol-bass sym)))))
                              (list (- bar first) offset (pitch-class-string (chord-symbol-root sym))
                                    bass
                                    (sort (remove-duplicates
                                           (append (and bass (list bass))
                                                   (mapcar (lambda (tone) (pitch-class-string (cdr tone)))
                                                           (chord-tones sym)))
                                           :test #'string=)
                                          #'string<)))))
          :keys (loop for m in measures for i from 0
                      when (measure-info-key m)
                        collect (list i (key-signature (measure-info-key m))
                                      (key-mode (measure-info-key m))))
          :times (loop for m in measures for i from 0
                       when (measure-info-time m)
                         collect (list i (meter-string (measure-info-time m))))
          :tempos (loop for m in measures for i from 0
                        nconc (loop for tm in (measure-info-tempo m)
                                    when (tempo-mark-tempo tm)
                                      collect (list i (tempo-mark-offset tm)
                                                    (tempo-bpm (tempo-mark-tempo tm))
                                                    (tempo-beat-unit (tempo-mark-tempo tm))))))))

;;; Snippet pieces ------------------------------------------------------------------

(defun v (k) (format nil "<voice>~A</voice>" k))
(defun st (k) (format nil "<staff>~A</staff>" k))
(defun fwd (d) (format nil "<forward><duration>~A</duration></forward>" d))
(defun bk (d) (format nil "<backup><duration>~A</duration></backup>" d))
(defun dir (inner &rest extra)
  "A <direction> holding INNER (direction-type content), then EXTRA."
  (format nil "<direction><direction-type>~A</direction-type>~{~A~}</direction>" inner extra))
(defun dyn (value) (format nil "<dynamics><~A/></dynamics>" value))
(defun nots (&rest inner) (format nil "<notations>~{~A~}</notations>" inner))
(defun bl (location &rest inner)
  (format nil "<barline location=~S>~{~A~}</barline>" location inner))
(defun cat (&rest strings) (apply #'concatenate 'string strings))
