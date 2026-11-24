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
;;;; chord symbols' TEXT and DIALECT NIL; a grace with no notated
;;;; value read back as 1/8, a tempo whose beat unit has none as (Q, 1/4); a
;;;; voice with no events on STAFF 1, and a voice with no pitched note with STEM
;;;; NIL; an empty part name NIL; SCORE-SPANNERS in the document order of their
;;;; starts (part, measure, voice, event; on one event hairpins before slurs).

(in-package #:score-backend-musicxml)

(defparameter +lost-whats+
  '("provenance and confidence" "chord-symbol text" "notated value")
  "The LOSSY-CONVERSION WHATs WRITE-MUSICXML signals, in order (file header). Data.")

(defun write-musicxml (score &optional destination)
  "SCORE as MusicXML text, to DESTINATION (file header)."
  (check-type score score-protocol:score)
  (check-type destination (or null pathname stream))
  (multiple-value-bind (document lost) (%score-document score)
    (let ((text (xml-protocol:encode document :pretty t :declaration t)))
      (prog1 (etypecase destination
               (null text)
               (pathname
                (with-open-file (out destination :direction :output :if-exists :supersede
                                                 :if-does-not-exist :create :external-format :utf-8)
                  (write-string text out))
                destination)
               (stream (write-string text destination) destination))
        (dolist (what lost)
          (warn 'score-protocol:lossy-conversion :format :musicxml :what what))))))

(defun score-to-musicxml (score)
  "SCORE as an xml-protocol XML-DOCUMENT (file header)."
  (check-type score score-protocol:score)
  (values (%score-document score)))

;;; The writing context ---------------------------------------------------------

(defstruct (%writing (:constructor %make-writing (score)) (:copier nil) (:predicate nil))
  "What writing SCORE needs besides the element at hand: the ids tie ENDs name,
the spanners, the hairpin and slur numbers of the part being written, and the
LOST WHATs found so far."
  (score nil :read-only t)
  (tie-ends (make-hash-table :test 'equal))
  (spanners '())
  (slurs '())
  (wedges '())
  (lost '()))

(defun %lose (writing what)
  (pushnew what (%writing-lost writing) :test #'string=))

(defun %start-number (held key)
  "(values n held): the least n >= 1 not in HELD, an alist key → n, and HELD
with KEY holding it."
  (let ((n (loop for n from 1 unless (rassoc n held) return n)))
    (values n (acons key n held))))

(defun %stop-number (held key)
  "(values n held): the number KEY holds, and HELD without it."
  (let ((entry (assoc key held :test #'equal)))
    (values (if entry (cdr entry) 1) (remove entry held))))

(defun %seq (seq)
  (fset:convert 'list seq))

(defun %decimal (x)
  "X as a DECIMAL (file header)."
  (let ((x (if (floatp x) (rationalize x) x)))
    (if (integerp x)
        (format nil "~D" x)
        (let ((d (denominator x)) (twos 0) (fives 0))
          (loop while (evenp d) do (setf d (/ d 2)) (incf twos))
          (loop while (zerop (mod d 5)) do (setf d (/ d 5)) (incf fives))
          (multiple-value-bind (scaled digits)
              (if (= d 1)
                  (let ((k (max twos fives))) (values (* x (expt 10 k)) k))
                  (values (round (* x 100)) 2))
            (let* ((text (format nil "~D" (abs scaled)))
                   (text (if (<= (length text) digits)
                             (concatenate 'string (make-string (- (1+ digits) (length text))
                                                               :initial-element #\0)
                                          text)
                             text))
                   (point (- (length text) digits))
                   (fixed (string-right-trim "0" (concatenate 'string (subseq text 0 point) "."
                                                              (subseq text point)))))
              (format nil "~:[~;-~]~A" (minusp scaled) (string-right-trim "." fixed))))))))

;;; The document ----------------------------------------------------------------

(defun %score-document (score)
  "(values document lost): SCORE-TO-MUSICXML's document, and the WHATs WRITE-MUSICXML
warns, in +LOST-WHATS+ order."
  (let ((writing (%make-writing score))
        (metadata (score-protocol:score-metadata score))
        (parts (%seq (score-protocol:score-parts score))))
    (setf (%writing-spanners writing) (%seq (score-protocol:score-spanners score)))
    (dolist (element (score-protocol:score-elements score))
      (typecase element
        (score-protocol:tie
         (setf (gethash (score-protocol:tie-end element) (%writing-tie-ends writing)) t)))
      (when (or (score-protocol:element-provenance element)
                (score-protocol:element-confidence element))
        (%lose writing "provenance and confidence")))
    (flet ((meta (key) (getf metadata key)))
      (let ((root (%el "score-partwise" (list (cons "version" +musicxml-version+))
                       (and (or (%present-p (meta :title)) (%present-p (meta :subtitle)))
                            (%el "work" nil (%el "work-title" nil (or (meta :title) ""))))
                       (and (%present-p (meta :subtitle)) (%el "movement-title" nil (meta :subtitle)))
                       (and (some (lambda (key) (%present-p (meta key)))
                                  '(:composer :lyricist :arranger :copyright))
                            (%el "identification" nil
                                 (loop for (key type) in +metadata-creators+
                                       when (%present-p (meta key))
                                         collect (%el "creator" (list (cons "type" type)) (meta key)))
                                 (and (%present-p (meta :copyright))
                                      (%el "rights" nil (meta :copyright)))))
                       (%el "part-list" nil (mapcar #'%score-part-element parts))
                       (loop for part in parts
                             for first-p = t then nil
                             collect (%part-element writing part first-p)))))
        (values (xml-protocol:make-xml-document
                 :children (list (make-instance 'xml-protocol:xml-doctype
                                                :name (first +musicxml-doctype+)
                                                :public-id (second +musicxml-doctype+)
                                                :system-id (third +musicxml-doctype+))
                                 root))
                (remove-if-not (lambda (what) (member what (%writing-lost writing) :test #'string=))
                               +lost-whats+))))))

(defun %score-part-element (part)
  (%el "score-part" (list (cons "id" (score-protocol:element-id part)))
       (%el "part-name" nil (or (score-protocol:part-name part) ""))
       (and (%present-p (score-protocol:part-abbreviation part))
            (%el "part-abbreviation" nil (score-protocol:part-abbreviation part)))
       (loop for voice in (score-protocol:part-voices part)
             collect (%el "player" (list (cons "id" (score-protocol:element-id voice)))
                          (%el "player-name" nil (or (score-protocol:voice-name voice) ""))))))

(defun %divisions (score part first-p)
  "The DIVISIONS of PART (file header)."
  (let ((divisions 1))
    (flet ((add (x) (setf divisions (lcm divisions (denominator (* 4 x))))))
      (dolist (voice (score-protocol:part-voices part))
        (dolist (events (%seq (score-protocol:voice-measures voice)))
          (dolist (event (%seq events))
            (unless (and (typep event 'score-protocol:sounding-event) (score-protocol:event-grace event))
              (add (score-protocol:event-duration event))))))
      (loop for bar from (score-protocol:score-first-bar score) to (score-protocol:score-last-bar score)
            do (add (score-protocol:bar-length score bar)))
      (when first-p
        (dolist (measure (%seq (score-protocol:score-measure-map score)))
          (dolist (mark (score-protocol:measure-info-tempo measure))
            (add (score-protocol:tempo-mark-offset mark))))
        (dolist (anchor (%seq (score-protocol:score-chord-symbols score)))
          (add (cdr (score-protocol:anchor-position anchor))))))
    divisions))

(defun %passes-text (ending)
  (format nil "~{~D~^, ~}" (score-protocol:ending-passes ending)))

(defun %part-element (writing part first-p)
  "The <part> of PART (file header, \"Per part\")."
  (let* ((score (%writing-score writing))
         (divisions (%divisions score part first-p))
         (two (>= (length (score-protocol:part-staves part)) 2))
         (measures (%seq (score-protocol:score-measure-map score)))
         (count (length measures))
         (first-bar (score-protocol:score-first-bar score))
         (ending-ends (make-array count :initial-element nil)))
    (setf (%writing-slurs writing) '()
          (%writing-wedges writing) '())
    (loop for measure in measures
          for i from 0
          for ending = (score-protocol:measure-info-ending measure)
          when ending
            do (setf (aref ending-ends (min (1- count) (+ i (score-protocol:ending-measures ending) -1)))
                     ending))
    (flet ((duration (x) (%el "duration" nil (format nil "~D" (* 4 divisions x)))))
      (%el "part" (list (cons "id" (score-protocol:element-id part)))
           (loop for measure in measures
                 for i from 0
                 for bar = (+ first-bar i)
                 collect (%measure-element writing part measure i bar first-p two divisions
                                           (aref ending-ends i) #'duration))))))

(defun %measure-element (writing part measure i bar first-p two divisions ending-end duration)
  "The <measure> I of PART (file header, items 1-5). DURATION makes a
<duration> of a length."
  (let* ((score (%writing-score writing))
         (time (score-protocol:measure-info-time measure))
         (key (score-protocol:measure-info-key measure))
         (ending (score-protocol:measure-info-ending measure))
         (repeat-start (score-protocol:measure-info-repeat-start measure))
         (repeat-end (score-protocol:measure-info-repeat-end measure))
         (barline (score-protocol:measure-info-barline measure))
         (cursor 0)
         (content '()))
    (flet ((add (element) (push element content))
           (move-to (offset)
             (cond ((> offset cursor)
                    (push (%el "forward" nil (funcall duration (- offset cursor))) content))
                   ((< offset cursor)
                    (push (%el "backup" nil (funcall duration (- cursor offset))) content)))
             (setf cursor offset)))
      ;; 1. attributes
      (when (or (= i 0) time key)
        (add (%el "attributes" nil
                  (and (= i 0) (%el "divisions" nil (format nil "~D" divisions)))
                  (and key (%el "key" nil
                                (%el "fifths" nil (format nil "~D" (music-theory:key-signature key)))
                                (%el "mode" nil (string-downcase (symbol-name (music-theory:key-mode key))))))
                  (and time (%el "time" nil
                                 (%el "beats" nil (format nil "~{~D~^+~}" (music-theory:meter-numerators time)))
                                 (%el "beat-type" nil (format nil "~D" (music-theory:meter-denominator time)))))
                  (and (= i 0) two
                       (%el "staves" nil (format nil "~D" (length (score-protocol:part-staves part)))))
                  (and (= i 0)
                       (loop for staff in (score-protocol:part-staves part)
                             for k from 1
                             collect (destructuring-bind (sign line octave)
                                         (rest (assoc (score-protocol:staff-clef staff) +clef-signs+))
                                       (%el "clef" (list (cons "number" (and two (format nil "~D" k)))
                                                         (cons "id" (score-protocol:element-id staff)))
                                            (%el "sign" nil sign)
                                            (%el "line" nil (format nil "~D" line))
                                            (and (/= octave 0)
                                                 (%el "clef-octave-change" nil (format nil "~D" octave))))))))))
      ;; 2. the left barline
      (when (or repeat-start ending)
        (add (%el "barline" (list (cons "location" "left")
                                  (cons "id" (and first-p ending (score-protocol:element-id ending))))
                  (and repeat-start (%el "bar-style" nil "heavy-light"))
                  (and ending (%el "ending" (list (cons "number" (%passes-text ending))
                                                  (cons "type" "start"))))
                  (and repeat-start (%el "repeat" '(("direction" . "forward")))))))
      ;; 3. the measure track
      (when first-p
        (dolist (item (%track-items score measure bar))
          (move-to (first item))
          (add (%track-element writing (second item) (third item))))
        (move-to 0))
      ;; 4. the voices
      (loop for voice in (score-protocol:part-voices part)
            for k from 1
            for measures = (score-protocol:voice-measures voice)
            for events = (and (< i (fset:size measures)) (%seq (fset:@ measures i)))
            when events
              do (move-to 0)
                 (let ((staff (and two (score-protocol:voice-staff voice))))
                   (dolist (event events)
                     (dolist (element (%event-elements writing event voice k staff duration))
                       (add element))
                     (unless (and (typep event 'score-protocol:sounding-event)
                                  (score-protocol:event-grace event))
                       (incf cursor (score-protocol:event-duration event)))
                     (dolist (element (%hairpin-stops writing event k staff))
                       (add element)))))
      ;; 5. the right barline
      (when (or (not (eq barline :regular)) repeat-end ending-end)
        (add (%el "barline" '(("location" . "right"))
                  (and (not (eq barline :regular))
                       (%el "bar-style" nil (second (assoc barline +bar-styles+))))
                  (and ending-end
                       (%el "ending" (list (cons "number" (%passes-text ending-end))
                                           (cons "type" (if repeat-end "stop" "discontinue")))))
                  (and repeat-end
                       (%el "repeat" (list (cons "direction" "backward")
                                           (cons "times" (and (/= repeat-end 2)
                                                              (format nil "~D" repeat-end)))))))))
      (%el "measure" (list (cons "number" (format nil "~D" bar))
                           (cons "text" (and (%present-p (score-protocol:measure-info-number measure))
                                             (score-protocol:measure-info-number measure)))
                           (cons "implicit" (and (score-protocol:measure-info-pickup-p measure) "yes"))
                           (cons "id" (score-protocol:slice-id (score-protocol:element-id measure)
                                                               (score-protocol:element-id part))))
           (nreverse content)))))

;;; The measure track -------------------------------------------------------------

(defun %track-items (score measure bar)
  "(offset kind element) per item of MEASURE's track, sorted (file header, item 3)."
  (let ((items '())
        (jumps (score-protocol:measure-info-jump measure))
        (rehearsal (score-protocol:measure-info-rehearsal measure)))
    (flet ((item (offset rank kind element) (push (list offset rank kind element) items)))
      (when rehearsal (item 0 0 :rehearsal rehearsal))
      (dolist (jump jumps)
        (when (member (score-protocol:jump-mark-kind jump) '(:segno :coda)) (item 0 1 :jump jump)))
      (dolist (mark (score-protocol:measure-info-tempo measure))
        (item (score-protocol:tempo-mark-offset mark) 2 :tempo mark))
      (dolist (anchor (%seq (score-protocol:score-chord-symbols score)))
        (when (= (car (score-protocol:anchor-position anchor)) bar)
          (item (cdr (score-protocol:anchor-position anchor)) 3 :anchor anchor)))
      (dolist (jump jumps)
        (unless (member (score-protocol:jump-mark-kind jump) '(:segno :coda))
          (item (score-protocol:bar-length score bar) 4 :jump jump))))
    (mapcar (lambda (item) (list (first item) (third item) (fourth item)))
            (stable-sort (nreverse items)
                         (lambda (a b) (or (< (first a) (first b))
                                           (and (= (first a) (first b)) (< (second a) (second b)))))))))

(defun %track-element (writing kind element)
  "The direction or harmony of the track item ELEMENT of KIND."
  (let ((id (list (cons "id" (score-protocol:element-id element)))))
    (ecase kind
      (:rehearsal
       (%el "direction" id (%el "direction-type" nil
                                (%el "rehearsal" nil (score-protocol:rehearsal-mark-text element)))))
      (:jump
       (destructuring-bind (kind words attribute value &rest other)
           (assoc (score-protocol:jump-mark-kind element) +jump-directions+)
         (declare (ignore other))
         (%el "direction" id
              (%el "direction-type" nil (if words
                                            (%el "words" nil words)
                                            (%el (string-downcase (symbol-name kind)))))
              (%el "sound" (list (cons attribute value))))))
      (:tempo
       (let ((tempo (score-protocol:tempo-mark-tempo element))
             (text (score-protocol:tempo-mark-text element)))
         (%el "direction" id
              (and text (%el "direction-type" nil (%el "words" nil text)))
              (and tempo
                   (let ((bpm (music-theory:tempo-bpm tempo))
                         (unit (music-theory:tempo-beat-unit tempo)))
                     (multiple-value-bind (base dots) (music-theory:duration-dots unit)
                       (if base
                           (%el "direction-type" nil
                                (%el "metronome" nil
                                     (%el "beat-unit" nil (second (assoc base +note-types+)))
                                     (loop repeat dots collect (%el "beat-unit-dot"))
                                     (%el "per-minute" nil (%decimal bpm))))
                           (progn (%lose writing "notated value") nil)))))
              (if tempo
                  (%el "sound" (list (cons "tempo" (%decimal (* (rationalize (music-theory:tempo-bpm tempo))
                                                                (music-theory:tempo-beat-unit tempo)
                                                                4)))))
                  (%el "sound")))))
      (:anchor
       (multiple-value-bind (harmony lost)
           (chord-symbol-to-harmony (score-protocol:anchor-symbol element)
                                    :id (score-protocol:element-id element))
         (dolist (what lost) (%lose writing what))
         harmony)))))

;;; Events and notes -----------------------------------------------------------------

(defun %location (k staff)
  "Fresh <voice>K</voice> and, unless STAFF is NIL, <staff>STAFF</staff>."
  (list (%el "voice" nil (format nil "~D" k))
        (and staff (%el "staff" nil (format nil "~D" staff)))))

(defun %hairpin-p (spanner)
  (and (member (score-protocol:spanner-kind spanner) '(:crescendo :diminuendo)) t))

(defun %event-elements (writing event voice k staff duration)
  "The elements EVENT writes before the cursor moves past it (file header, item
4 a-c), in order."
  (let* ((id (score-protocol:element-id event))
         (dynamic (score-protocol:event-dynamic event))
         (dynamic-element
           (and dynamic
                (%el "direction" (list (cons "id" (score-protocol:element-id dynamic)))
                     (%el "direction-type" nil
                          (%el "dynamics" nil
                               (%el (string-downcase
                                     (symbol-name (score-protocol:dynamic-mark-value dynamic))))))
                     (%location k staff))))
         (starts
           (loop for spanner in (%writing-spanners writing)
                 when (and (%hairpin-p spanner) (equal (score-protocol:spanner-start spanner) id))
                   collect (multiple-value-bind (n held)
                               (%start-number (%writing-wedges writing) (score-protocol:element-id spanner))
                             (setf (%writing-wedges writing) held)
                             (%el "direction" (list (cons "id" (score-protocol:element-id spanner)))
                                  (%el "direction-type" nil
                                       (%el "wedge" (list (cons "type" (string-downcase
                                                                        (symbol-name
                                                                         (score-protocol:spanner-kind spanner))))
                                                          (cons "number" (format nil "~D" n)))))
                                  (%location k staff))))))
    (append (and dynamic-element (list dynamic-element))
            starts
            (%note-elements writing event voice k staff duration))))

(defun %hairpin-stops (writing event k staff)
  "The wedge stops of the hairpins ending on EVENT (file header, item 4 d)."
  (let ((id (score-protocol:element-id event)))
    (loop for spanner in (%writing-spanners writing)
          when (and (%hairpin-p spanner) (equal (score-protocol:spanner-end spanner) id))
            collect (multiple-value-bind (n held)
                        (%stop-number (%writing-wedges writing) (score-protocol:element-id spanner))
                      (setf (%writing-wedges writing) held)
                      (%el "direction" nil
                           (%el "direction-type" nil
                                (%el "wedge" (list (cons "type" "stop")
                                                   (cons "number" (format nil "~D" n)))))
                           (%location k staff))))))

(defun %slur-elements (writing event)
  "The <slur>s on EVENT's first note: a stop per slur ending on it, then a start
per slur starting on it, in SCORE-SPANNERS order."
  (let ((id (score-protocol:element-id event)))
    (flet ((slurs-at (reader)
             (loop for spanner in (%writing-spanners writing)
                   when (and (eq (score-protocol:spanner-kind spanner) :slur)
                             (equal (funcall reader spanner) id))
                     collect spanner)))
      (append
       (loop for spanner in (slurs-at #'score-protocol:spanner-end)
             collect (multiple-value-bind (n held)
                         (%stop-number (%writing-slurs writing) (score-protocol:element-id spanner))
                       (setf (%writing-slurs writing) held)
                       (%el "slur" (list (cons "type" "stop") (cons "number" (format nil "~D" n))))))
       (loop for spanner in (slurs-at #'score-protocol:spanner-start)
             collect (multiple-value-bind (n held)
                         (%start-number (%writing-slurs writing) (score-protocol:element-id spanner))
                       (setf (%writing-slurs writing) held)
                       (%el "slur" (list (cons "type" "start") (cons "number" (format nil "~D" n))
                                         (cons "id" (score-protocol:element-id spanner))))))))))

(defun %event-marks (writing event)
  "The <notations> children EVENT's first note carries after its ties: slurs,
articulations, the breath mark, the fermata."
  (let ((sounding (typep event 'score-protocol:sounding-event))
        (fermata (score-protocol:event-fermata event)))
    (append (%slur-elements writing event)
            (and sounding
                 (loop for articulation in (score-protocol:event-articulations event)
                       collect (%el "articulations"
                                    (list (cons "id" (score-protocol:element-id articulation)))
                                    (%el (second (assoc (score-protocol:articulation-kind articulation)
                                                        +articulation-elements+))))))
            (let ((breath (and sounding (score-protocol:event-breath-mark event))))
              (and breath
                   (list (%el "articulations" (list (cons "id" (score-protocol:element-id breath)))
                              (%el "breath-mark")))))
            (and fermata
                 (list (%el "fermata" (list (cons "id" (score-protocol:element-id fermata)))
                            (second (assoc (score-protocol:fermata-shape fermata) +fermata-shapes+))))))))

(defun %notated-value (writing event grace)
  "<type> and <dot>s of EVENT's notated value, or NIL (a grace event without one
loses it)."
  (let ((duration (score-protocol:event-duration event)))
    (multiple-value-bind (base dots)
        (if grace
            (music-theory:duration-dots duration)
            (music-theory:duration-dots duration :tuplet (score-protocol:event-tuplet event)))
      (cond (base (cons (%el "type" nil (second (assoc base +note-types+)))
                        (loop repeat dots collect (%el "dot"))))
            (grace (%lose writing "notated value") nil)
            (t nil)))))

(defun %lyric-element (lyric)
  (%el "lyric" (list (cons "number" (format nil "~D" (score-protocol:lyric-verse lyric)))
                     (cons "id" (score-protocol:element-id lyric)))
       (%el "syllabic" nil (second (assoc (score-protocol:lyric-syllabic lyric) +syllabic-names+)))
       (%el "text" nil (score-protocol:lyric-text lyric))
       (and (score-protocol:lyric-extender lyric) (%el "extend"))))

(defun %pitch-element (pitch)
  (let ((alter (music-theory:spelled-pitch-alter pitch)))
    (%el "pitch" nil
         (%el "step" nil (string (char +steps+ (music-theory:spelled-pitch-letter pitch))))
         (and (/= alter 0) (%el "alter" nil (format nil "~D" alter)))
         (%el "octave" nil (format nil "~D" (music-theory:spelled-pitch-octave pitch))))))

(defun %note-elements (writing event voice k staff duration)
  "The <note>s of EVENT (file header, \"Notes\"): one for a note or rest event,
one per chord note for a chord event."
  (let* ((chord-p (typep event 'score-protocol:chord-event))
         (rest-p (typep event 'score-protocol:rest-event))
         (grace (and (not rest-p) (score-protocol:event-grace event)))
         (tuplet (score-protocol:event-tuplet event))
         (measure-rest (and rest-p (score-protocol:rest-event-measure-rest-p event)))
         (stem (score-protocol:voice-stem voice))
         (notes (cond (chord-p (score-protocol:chord-event-notes event))
                      (rest-p (list nil))
                      (t (list event)))))
    (loop for note in notes
          for first = t then nil
          for id = (score-protocol:element-id (if chord-p note event))
          for end-p = (and note (gethash id (%writing-tie-ends writing)))
          for tie = (and note (score-protocol:note-tie note))
          for accidental = (and note (score-protocol:note-accidental note))
          collect
          (let ((notations
                  (%el "notations" (list (cons "id" (and chord-p first (score-protocol:element-id event))))
                       (and end-p (%el "tied" '(("type" . "stop"))))
                       (and tie (%el "tied" (list (cons "type" "start")
                                                  (cons "id" (score-protocol:element-id tie)))))
                       (and first (%event-marks writing event)))))
            (%el "note" (list (cons "print-object" (and rest-p (score-protocol:rest-event-hidden-p event) "no"))
                              (cons "id" id))
                 (and grace (%el "grace" (list (cons "slash" (and (eq grace :acciaccatura) "yes")))))
                 (and (not first) (%el "chord"))
                 (if note
                     (%pitch-element (score-protocol:note-pitch note))
                     (%el "rest" (list (cons "measure" (and measure-rest "yes")))))
                 (and (not grace) (funcall duration (score-protocol:event-duration event)))
                 (and end-p (%el "tie" '(("type" . "stop"))))
                 (and tie (%el "tie" '(("type" . "start"))))
                 (%el "voice" nil (format nil "~D" k))
                 (and (not measure-rest) (%notated-value writing event grace))
                 (and (member accidental '(:forced :cautionary))
                      (%el "accidental" (list (cons "cautionary" (and (eq accidental :cautionary) "yes")))
                           (second (assoc (music-theory:spelled-pitch-alter (score-protocol:note-pitch note))
                                          +accidental-names+))))
                 (and tuplet
                      (%el "time-modification" nil
                           (%el "actual-notes" nil (format nil "~D" (numerator tuplet)))
                           (%el "normal-notes" nil (format nil "~D" (denominator tuplet)))))
                 (and note stem (%el "stem" nil (string-downcase (symbol-name stem))))
                 (and staff (%el "staff" nil (format nil "~D" staff)))
                 (and (or (xml-protocol:xml-element-children notations)
                          (xml-protocol:xml-element-attributes notations))
                      notations)
                 (and first (mapcar #'%lyric-element (score-protocol:event-lyrics event))))))))
