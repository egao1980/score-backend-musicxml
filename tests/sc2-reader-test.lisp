;;;; SC2 reading MusicXML (src/reader.lisp): the corpus and the goldens against
;;;; music21's reading, the goldens against the SC0 models, and the mapping rules
;;;; one by one on small documents.

(in-package #:score-backend-musicxml/tests)

;;; Against music21 -----------------------------------------------------------------

(defparameter +fact-files+
  (append (mapcar #'golden-name +sc0-names+) (mapcar #'corpus-name +corpus-names+))
  "Every file of tests/fixtures/sc2-facts.sexp.")

(deftest-parametrize files-read-as-music21-reads-them
    ((file) :rows (mapcar #'list +fact-files+))
  (let ((facts (fact-entry file))
        (ours (score-facts (read-fixture file))))
    (dolist (key '(:measures :events :harmonies :keys :times :tempos))
      (testing (format nil "~A ~(~A~)" file key)
        (ok (equal (sorted-rows (getf facts key)) (sorted-rows (getf ours key))))))))

(deftest-parametrize goldens-read-as-their-models
    ((name) :rows (mapcar #'list +sc0-names+))
  (testing (format nil "~A: the golden file reads as the SC0 score, ids and all" name)
    (ok (score-equal (read-fixture (golden-name name)) (sexp-to-score (lossless-form name))))))

(deftest sources
  (let* ((file (corpus-name "amazing-grace"))
         (expected (read-fixture file)))
    (testing "a pathname, a string, octets and a character stream read alike"
      (ok (score-equal expected (read-musicxml (file-string file))))
      (ok (score-equal expected (read-musicxml (file-octets file))))
      (ok (score-equal expected (with-input-from-string (in (file-string file)) (read-musicxml in))))
      (ok (score-equal expected (musicxml-to-score
                                 (handler-bind ((xml-protocol:xml-entity-error #'continue))
                                   (xml-protocol:decode (file-string file)))))))
    (testing "keyword values are checked"
      (ok (signalled (lambda () (read-musicxml (file-string file) :split-voices :always)) 'type-error))
      (ok (signalled (lambda () (read-musicxml (file-string file) :unsupported :ignore)) 'type-error)))))

;;; Durations and pitches -----------------------------------------------------------

(defun first-voice (measures &rest keys)
  (voice-forms (apply #'read-snippet measures keys) 0 0))

(deftest durations
  (testing "durations are <duration> / (4 x divisions); time-modification gives TUPLET"
    (ok (equal (first-voice
                (list (cat (n "C4" 6) (n "D4" 3) (n "E4" 9)
                           (n "F4" 2 "<time-modification><actual-notes>3</actual-notes><normal-notes>2</normal-notes></time-modification>")
                           (n "G4" 2 "<time-modification><actual-notes>3</actual-notes><normal-notes>2</normal-notes></time-modification>")
                           (n "A4" 2 "<time-modification><actual-notes>3</actual-notes><normal-notes>2</normal-notes></time-modification>")))
                :divisions 6)
               '(((:note :pitch "C4" :duration 1/4) (:note :pitch "D4" :duration 1/8)
                  (:note :pitch "E4" :duration 3/8) (:note :pitch "F4" :duration 1/12 :tuplet 3/2)
                  (:note :pitch "G4" :duration 1/12 :tuplet 3/2)
                  (:note :pitch "A4" :duration 1/12 :tuplet 3/2))))))
  (testing "decimal durations are exact"
    (ok (equal (first-voice (list (cat (n "C4" "1.5") (n "D4" "0.5") (n "E4" "6"))) :divisions 2)
               '(((:note :pitch "C4" :duration 3/16) (:note :pitch "D4" :duration 1/16)
                  (:note :pitch "E4" :duration 3/4))))))
  (testing "<divisions> applies from its <attributes> on"
    (ok (equal (first-voice (list (n "C4" 4) (cat "<attributes><divisions>4</divisions></attributes>" (n "D4" 16))))
               '(((:note :pitch "C4" :duration 1)) ((:note :pitch "D4" :duration 1))))))
  (testing "a ratio of 1 is no tuplet; <type> and <dot> of a timed note are display"
    (ok (equal (first-voice (list (n "C4" 4 "<type>half</type><dot/><time-modification><actual-notes>2</actual-notes><normal-notes>2</normal-notes></time-modification>")))
               '(((:note :pitch "C4" :duration 1)))))))

(deftest pitches-and-accidentals
  (ok (equal (first-voice (list (cat (n "F#4" 1 "<accidental>sharp</accidental>")
                                     (n "Bb3" 1 "<accidental cautionary=\"yes\">flat</accidental>")
                                     (n "Ebb4" 1)
                                     (n "C##5" 1 "<accidental parentheses=\"yes\">double-sharp</accidental>"))))
             '(((:note :pitch "F#4" :duration 1/4 :accidental :forced)
                (:note :pitch "Bb3" :duration 1/4 :accidental :cautionary)
                (:note :pitch "Ebb4" :duration 1/4)
                (:note :pitch "C##5" :duration 1/4 :accidental :cautionary)))))
  (testing "an accidental's value is display: a natural sign on F# still forces it"
    (ok (equal (first-voice (list (n "F#4" 4 "<accidental editorial=\"yes\">natural</accidental>")))
               '(((:note :pitch "F#4" :duration 1 :accidental :cautionary)))))))

(deftest grace-notes
  (ok (equal (first-voice
              (list (cat "<note><grace slash=\"yes\"/><pitch><step>D</step><octave>5</octave></pitch><voice>1</voice><type>16th</type><dot/></note>"
                         "<note><grace/><pitch><step>E</step><octave>5</octave></pitch><voice>1</voice></note>"
                         "<note><grace/><pitch><step>F</step><octave>5</octave></pitch><voice>1</voice><type>long</type></note>"
                         (n "C5" 4))))
             '(((:note :pitch "D5" :duration 3/32 :grace :acciaccatura)
                (:note :pitch "E5" :duration 1/8 :grace :appoggiatura)
                (:note :pitch "F5" :duration 1/8 :grace :appoggiatura)
                (:note :pitch "C5" :duration 1))))))

(deftest rests-and-chords
  (testing "measure rests and hidden rests"
    (ok (equal (first-voice (list "<note><rest measure=\"yes\"/><duration>4</duration></note>"
                                  (cat "<note print-object=\"no\"><rest><display-step>E</display-step><display-octave>4</display-octave></rest><duration>2</duration></note>"
                                       (n :rest 2))))
               '(((:rest :duration 1 :measure-rest t))
                 ((:rest :duration 1/2 :hidden t) (:rest :duration 1/2))))))
  (testing "<chord> notes join the previous note's event; their own durations are ignored"
    (ok (equal (first-voice (list (cat (n "C4" 2) "<note><chord/><pitch><step>E</step><octave>4</octave></pitch><duration>3</duration></note>"
                                       "<note><chord/><pitch><step>G</step><octave>4</octave></pitch><duration>1</duration><accidental>natural</accidental></note>"
                                       (n :rest 2))))
               '(((:chord :notes ((:chord-note :pitch "C4") (:chord-note :pitch "E4")
                                  (:chord-note :pitch "G4" :accidental :forced))
                   :duration 1/2)
                  (:rest :duration 1/2)))))))

(deftest gaps
  (testing "gaps in a voice are hidden rests, the pieces of SPLIT-DURATION"
    (ok (equal (voice-forms (read-snippet (list (cat (n "C4" 2) (fwd 4) (n "D4" 2))
                                                (cat (n "C4" 2) (bk 2) (n "E4" 8 (v 2)))
                                                (cat (fwd 2) (n "C4" 6)))
                                          :divisions 2)
                            0 0)
               '(((:note :pitch "C4" :duration 1/4) (:rest :duration 1/4 :hidden t)
                  (:rest :duration 1/4 :hidden t) (:note :pitch "D4" :duration 1/4))
                 ((:note :pitch "C4" :duration 1/4) (:rest :duration 1/4 :hidden t)
                  (:rest :duration 1/2 :hidden t))
                 ((:rest :duration 1/4 :hidden t) (:note :pitch "C4" :duration 3/4))))))
  (testing "a voice silent in a measure has an empty voice measure"
    (ok (equal (voice-forms (read-snippet (list (cat (n "C4" 2) (bk 2) (n "E4" 8 (v 2))) (n "D4" 8))
                                          :divisions 2)
                            0 1)
               '(((:note :pitch "E4" :duration 1)) ()))))
  (testing "in a pickup the gap is split where it lies in the bar"
    (let ((s (read-snippet (list (list " number=\"0\" implicit=\"yes\"" (cat (fwd 2) (n "C4" 1)))
                                 (list " number=\"1\"" (n "D4" 4))))))
      (ok (equal (voice-forms s 0 0)
                 '(((:rest :duration 1/4 :hidden t) (:rest :duration 1/4 :hidden t)
                    (:note :pitch "C4" :duration 1/4))
                   ((:note :pitch "D4" :duration 1)))))
      (ok (equal (first (measure-forms s)) '(:measure :time "4/4" :key "C major" :pickup t :length 3/4))))))

;;; Ties, slurs, marks ---------------------------------------------------------------

(defun events (score part voice)
  "Every event of VOICE of PART, in order, across measures."
  (loop for ms in (seq-list (voice-measures (voice-at score part voice)))
        append (seq-list ms)))

(deftest ties
  (let* ((s (read-snippet (list (cat (n "C4" 2 "<tie type=\"start\"/>") (n "C4" 1) (n "E4" 1 (nots "<tied type=\"start\"/>")))
                                (cat (n "E4" 2) (n "G4" 2 "<tie type=\"start\"/>"))
                                (cat (n "G4" 4))
                                (cat (n "C4" 2) "<note><chord/><pitch><step>E</step><octave>4</octave></pitch><duration>2</duration><tie type=\"start\"/></note>"
                                     (n "D4" 2) "<note><chord/><pitch><step>E</step><octave>4</octave></pitch><duration>2</duration></note>"))))
         (es (events s 0 0)))
    (testing "a tie ends on the next note of its voice with an equal pitch"
      (ok (equal (tie-end (note-tie (nth 0 es))) (element-id (nth 1 es)))))
    (testing "<tied> alone ties too, across the barline"
      (ok (equal (tie-end (note-tie (nth 2 es))) (element-id (nth 3 es)))))
    (testing "a tie into the next measure"
      (ok (equal (tie-end (note-tie (nth 4 es))) (element-id (nth 5 es)))))
    (testing "a chord note ties to the equal-pitch note of the next chord"
      (let ((from (second (chord-event-notes (nth 6 es))))
            (to (second (chord-event-notes (nth 7 es)))))
        (ok (equal (tie-end (note-tie from)) (element-id to)))
        (ok (null (note-tie (first (chord-event-notes (nth 6 es))))))))
    (testing "a tie is an element with an id"
      (ok (valid-id-p (element-id (note-tie (nth 0 es))))))))

(deftest slurs
  (let* ((s (read-snippet (list (cat (n "C4" 1 (nots "<slur type=\"start\" number=\"1\"/>"))
                                     (n "D4" 1 (nots "<slur type=\"start\" number=\"2\"/>"))
                                     (n "E4" 1 (nots "<slur type=\"stop\" number=\"2\"/>"))
                                     (n "F4" 1 (nots "<slur type=\"stop\" number=\"1\"/><slur type=\"start\"/>")))
                                (cat (n "G4" 4 (nots "<slur type=\"continue\"/><slur type=\"stop\"/>"))))))
         (es (mapcar #'element-id (events s 0 0)))
         (spans (mapcar (lambda (sp) (list (spanner-kind sp) (spanner-start sp) (spanner-end sp)))
                        (seq-list (score-spanners s)))))
    (testing "slurs pair by number, nested ones too, in the order they start"
      (ok (equal spans (list (list :slur (nth 0 es) (nth 3 es)) (list :slur (nth 1 es) (nth 2 es))
                             (list :slur (nth 3 es) (nth 4 es))))))))

(deftest articulations-fermatas-breath-marks
  (ok (equal (first-voice
              (list (cat (n "C4" 1 (nots "<articulations><staccato/><accent/></articulations>"))
                         (n "D4" 1 (nots "<articulations><breath-mark>comma</breath-mark></articulations>"))
                         (n "E4" 1 (nots "<articulations><strong-accent type=\"up\"/></articulations><fermata/>"))
                         (n "F4" 1 (nots "<fermata type=\"inverted\">angled</fermata>")))
                    (cat (n :rest 2 (nots "<fermata>square</fermata>")) (n "G4" 2 (nots "<fermata>normal</fermata>")))))
             '(((:note :pitch "C4" :duration 1/4
                 :articulations ((:articulation :kind :accent) (:articulation :kind :staccato)))
                (:note :pitch "D4" :duration 1/4 :breath-mark (:breath-mark))
                (:note :pitch "E4" :duration 1/4 :articulations ((:articulation :kind :marcato))
                 :fermata (:fermata))
                (:note :pitch "F4" :duration 1/4 :fermata (:fermata :shape :short)))
               ((:rest :duration 1/2 :fermata (:fermata :shape :long))
                (:note :pitch "G4" :duration 1/2 :fermata (:fermata)))))))

(deftest lyrics
  (ok (equal (first-voice
              (list (cat (n "C4" 2 "<lyric number=\"1\"><syllabic>begin</syllabic><text>Hal</text></lyric>"
                            "<lyric number=\"2\"><text>a</text><elision/><text>e</text></lyric>"
                            "<lyric number=\"part1verse3\"><text>Three</text><extend/></lyric>"
                            "<lyric number=\"4\"><text>de</text><elision>~</elision><text>o</text></lyric>")
                         (n "D4" 2 "<lyric number=\"1\"><syllabic>end</syllabic><text>lo</text></lyric>"
                            "<lyric number=\"3\"><extend type=\"stop\"/></lyric>"
                            "<lyric name=\"chorus\"><text>x</text><extend type=\"start\"/></lyric>"))))
             '(((:note :pitch "C4" :duration 1/2
                 :lyrics ((:lyric :text "Hal" :syllabic :begin) (:lyric :verse 2 :text "a‿e")
                          (:lyric :verse 3 :text "Three" :extender t) (:lyric :verse 4 :text "de~o")))
                (:note :pitch "D4" :duration 1/2
                 :lyrics ((:lyric :text "lo" :syllabic :end) (:lyric :text "x" :extender t)))))))
  (testing "lyrics on any note of a chord go to the chord"
    (ok (equal (first-voice (list (cat (n "C4" 4 "<lyric><text>a</text></lyric>")
                                       "<note><chord/><pitch><step>E</step><octave>4</octave></pitch><duration>4</duration><lyric number=\"2\"><text>b</text></lyric></note>")))
               '(((:chord :notes ((:chord-note :pitch "C4") (:chord-note :pitch "E4")) :duration 1
                   :lyrics ((:lyric :text "a") (:lyric :verse 2 :text "b")))))))))

;;; Directions -------------------------------------------------------------------------

(defun dynamics-of (score part voice)
  (mapcar (lambda (e) (and (event-dynamic e) (dynamic-mark-value (event-dynamic e))))
          (events score part voice)))

(deftest dynamics
  (testing "a dynamic goes on the next event of its voice at or after its position"
    (ok (equal (dynamics-of (read-snippet (list (cat (dir (dyn "mf")) (n "C4" 1) (dir (dyn "p")) (n "D4" 1)
                                                     (dir (dyn "f") "<offset>1</offset>") (n "E4" 1) (n "F4" 1))
                                                (cat (n "G4" 4) (dir (dyn "sfz")))
                                                (n "A4" 4 (nots (dyn "pp")))))
                            0 0)
               '(:mf :p nil :f :sfz :pp))))
  (testing "after a grace note, a dynamic goes on the main note"
    (ok (equal (dynamics-of (read-snippet (list (cat "<note><grace/><pitch><step>D</step><octave>5</octave></pitch><voice>1</voice><type>eighth</type></note>"
                                                     (dir (dyn "p")) (n "C5" 4))))
                            0 0)
               '(nil :p))))
  (testing "the target voice: <voice>, else the first voice on <staff>, else the first voice"
    (let ((s (read-snippet (list (cat "<attributes><staves>2</staves></attributes>"
                                      (dir (dyn "mf") (st 2)) (n "C5" 4 (v 1) (st 1)) (bk 4)
                                      (dir (dyn "p") (v 2)) (n "A4" 4 (v 2) (st 1)) (bk 4)
                                      (n "C3" 4 (v 5) (st 2)))))))
      (ok (equal (list (dynamics-of s 0 0) (dynamics-of s 0 1) (dynamics-of s 0 2))
                 '((nil) (:p) (:mf)))))))

(deftest hairpins
  (let* ((s (read-snippet (list (cat (dir "<wedge type=\"crescendo\"/>") (n "C4" 1) (n "D4" 1) (n "E4" 1)
                                     (dir "<wedge type=\"stop\"/>") (dir "<wedge type=\"diminuendo\" number=\"2\"/>")
                                     (n "F4" 1))
                                (cat (n "G4" 4) (dir "<wedge type=\"stop\" number=\"2\"/>"))
                                (cat (dir "<wedge type=\"crescendo\"/>") (dir "<wedge type=\"stop\"/>") (n "A4" 4)))))
         (es (mapcar #'element-id (events s 0 0))))
    (ok (equal (mapcar (lambda (sp) (list (spanner-kind sp) (spanner-start sp) (spanner-end sp)))
                       (seq-list (score-spanners s)))
               (list (list :crescendo (nth 0 es) (nth 2 es)) (list :diminuendo (nth 3 es) (nth 4 es))
                     (list :crescendo (nth 5 es) (nth 5 es)))))))

;;; The measure map ------------------------------------------------------------------------

(deftest measure-numbers-pickups-lengths
  (let ((s (read-snippet (list (list " number=\"0\" implicit=\"yes\"" (n "C4" 1))
                               (list " number=\"1\" text=\"1\"" (n "D4" 4))
                               (list " number=\"7\"" (n "E4" 4))
                               (list " number=\"3\"" (cat (n "F4" 3) (bl "right" "<bar-style>light-heavy</bar-style>")))))))
    (ok (equal (measure-forms s)
               '((:measure :time "4/4" :key "C major" :pickup t :length 1/4)
                 (:measure :number "1") (:measure :number "7")
                 (:measure :length 3/4 :barline :final)))))
  (testing "implicit with a full bar is no pickup; a short first bar without it is no pickup"
    (ok (equal (measure-forms (read-snippet (list (list " number=\"1\" implicit=\"yes\"" (n "C4" 4)))))
               '((:measure :time "4/4" :key "C major"))))
    (ok (equal (measure-forms (read-snippet (list (n "C4" 2) (n "D4" 4))))
               '((:measure :time "4/4" :key "C major" :length 1/2) (:measure))))))

(deftest signatures
  (ok (equal (measure-forms
              (read-snippet (list (cat "<attributes><divisions>2</divisions><key><fifths>-3</fifths><mode>minor</mode></key><time><beats>2+3</beats><beat-type>8</beat-type></time></attributes>"
                                       (n "C4" 5))
                                  (cat "<attributes><key><fifths>2</fifths></key><time symbol=\"common\"><beats>3</beats><beat-type>4</beat-type></time></attributes>"
                                       (n "D4" 6))
                                  (cat "<attributes><key number=\"1\"><fifths>0</fifths><mode>major</mode></key><key number=\"2\"><fifths>5</fifths></key></attributes>"
                                       (n "E4" 6)))
                            :attributes nil))
             '((:measure :time "2+3/8" :key "C minor") (:measure :time "3/4" :key "D major")
               (:measure :key "C major"))))
  (testing "the first part's signatures win"
    (ok (equal (measure-forms (read-snippet (list (n "C4" 4))
                                            :extra-parts '(("P2" ("<attributes><divisions>1</divisions><key><fifths>3</fifths></key><time><beats>3</beats><beat-type>4</beat-type></time></attributes><note><pitch><step>A</step><octave>3</octave></pitch><duration>4</duration></note>")))))
               '((:measure :time "4/4" :key "C major"))))))

(deftest barlines-repeats-endings
  (ok (equal (measure-forms
              (read-snippet (list (cat (bl "left" "<bar-style>heavy-light</bar-style><repeat direction=\"forward\"/>") (n "C4" 4))
                                  (cat (bl "left" "<ending number=\"1 2\" type=\"start\"/>") (n "D4" 4)
                                       (bl "right" "<bar-style>light-heavy</bar-style><ending number=\"1 2\" type=\"stop\"/><repeat direction=\"backward\" times=\"3\"/>"))
                                  (cat (bl "left" "<ending number=\"3\" type=\"start\">3.</ending>") (n "E4" 4))
                                  (cat (n "F4" 4) (bl "right" "<bar-style>light-light</bar-style><ending number=\"3\" type=\"discontinue\"/>"))
                                  (cat (n "G4" 4) (bl "right" "<bar-style>dashed</bar-style><repeat direction=\"backward\" times=\"1\"/>")))))
             '((:measure :time "4/4" :key "C major" :repeat-start t)
               (:measure :barline :final :repeat-end 3 :ending (:ending :passes (1 2)))
               (:measure :ending (:ending :passes (3) :measures 2))
               (:measure :barline :double)
               (:measure :barline :dashed :repeat-end 2))))
  (testing "an ending without a stop runs to the next ending, else to the end"
    (ok (equal (measure-forms (read-snippet (list (cat (bl "left" "<ending number=\"1\" type=\"start\"/>") (n "C4" 4))
                                                  (cat (bl "left" "<ending number=\"2\" type=\"start\"/>") (n "D4" 4))
                                                  (n "E4" 4))))
               '((:measure :time "4/4" :key "C major" :ending (:ending :passes (1)))
                 (:measure :ending (:ending :passes (2) :measures 2))
                 (:measure)))))
  (testing "barlines of other parts are dropped"
    (ok (equal (measure-forms (read-snippet (list (n "C4" 4))
                                            :extra-parts '(("P2" ("<attributes><divisions>1</divisions></attributes><note><rest/><duration>4</duration></note><barline location=\"right\"><bar-style>light-heavy</bar-style><repeat direction=\"backward\"/></barline>")))))
               '((:measure :time "4/4" :key "C major"))))))

(defun jumps-of (score)
  (mapcar (lambda (m) (mapcar #'jump-mark-kind (measure-info-jump m))) (seq-list (score-measure-map score))))

(deftest jumps-and-rehearsal-marks
  (let ((s (read-snippet (list (cat (dir "<segno/>" "<sound segno=\"segno\"/>") (dir "<rehearsal>A</rehearsal>") (n "C4" 4))
                               (cat (n "C4" 4) (dir "<words>To Coda</words>" "<sound tocoda=\"coda\"/>"))
                               (cat (n "C4" 4) (dir "<words>D.S. al Coda</words>" "<sound dalsegno=\"segno\"/>"))
                               (cat (dir "<coda/>" "<sound coda=\"coda\"/>") (n "C4" 4) (dir "<words>Fine</words>" "<sound fine=\"yes\"/>"))
                               (cat (n "C4" 4) (dir "<words> d.c. al fine </words>"))
                               (cat (n "C4" 4) (dir "<words>Da Capo</words>" "<sound dacapo=\"yes\"/>"))
                               (cat (n "C4" 4) (dir "<words>D.C. al Coda</words>" "<sound dacapo=\"yes\"/>"))
                               (cat "<sound segno=\"s2\"/>" (n "C4" 4))))))
    (ok (equal (jumps-of s)
               '((:segno) (:to-coda) (:dal-segno-al-coda) (:coda :fine) (:da-capo-al-fine) (:da-capo)
                 (:da-capo-al-coda) (:segno))))
    (ok (equal (rehearsal-mark-text (measure-info-rehearsal (first (seq-list (score-measure-map s))))) "A"))))

(defun tempo-forms (score)
  (mapcar (lambda (m) (mapcar (lambda (tm) (strip-ids (element-to-sexp tm))) (measure-info-tempo m)))
          (seq-list (score-measure-map score))))

(deftest tempo-marks
  (ok (equal (tempo-forms
              (read-snippet (list (cat (dir "<metronome><beat-unit>quarter</beat-unit><beat-unit-dot/><per-minute>60</per-minute></metronome>" "<sound tempo=\"90\"/>") (n "C4" 4))
                                  (cat "<direction><sound tempo=\"120\"/></direction>" (n "C4" 4))
                                  (cat "<direction><direction-type><words>Andante</words></direction-type><direction-type><metronome><beat-unit>half</beat-unit><per-minute>50</per-minute></metronome></direction-type></direction>" (n "C4" 4))
                                  (cat (dir "<words>rit.</words>" "<sound/>") (n "C4" 4))
                                  (cat (n "C4" 2) (dir "<metronome><beat-unit>quarter</beat-unit><per-minute>80</per-minute></metronome>") (n "D4" 2))
                                  (cat (dir "<metronome><beat-unit>quarter</beat-unit><per-minute> 72.5 </per-minute></metronome>") (n "C4" 4)))))
             '(((:tempo-mark :bpm 60 :beat-unit 3/8)) ((:tempo-mark :bpm 120 :beat-unit 1/4))
               ((:tempo-mark :bpm 50 :beat-unit 1/2 :text "Andante")) ((:tempo-mark :text "rit."))
               ((:tempo-mark :offset 1/2 :bpm 80 :beat-unit 1/4)) ((:tempo-mark :bpm 145/2 :beat-unit 1/4))))))

(deftest measure-marks-come-from-the-first-part
  (let ((s (read-snippet (list (n "C4" 4))
                         :extra-parts '(("P2" ("<attributes><divisions>1</divisions></attributes><direction><direction-type><rehearsal>X</rehearsal></direction-type></direction><direction><direction-type><words>Presto</words></direction-type><sound tempo=\"160\"/></direction><direction><direction-type><segno/></direction-type></direction><note><rest/><duration>4</duration></note>"))))))
    (ok (equal (measure-forms s) '((:measure :time "4/4" :key "C major"))))))

;;; Parts, staves, voices ----------------------------------------------------------------

(deftest parts-staves-voices
  (testing "names, staves, clefs"
    (let* ((s (read-snippet (list (cat "<attributes><staves>2</staves><clef number=\"1\"><sign>G</sign><line>2</line><clef-octave-change>-1</clef-octave-change></clef><clef number=\"2\"><sign>C</sign><line>3</line></clef></attributes>"
                                       (n "C4" 4 (st 1)) (bk 4) (n "C3" 4 (v 2) (st 2)))
                                  (cat "<attributes><clef number=\"2\"><sign>C</sign><line>3</line></clef></attributes>"
                                       (n "D4" 4 (st 1)) (bk 4) (n "D3" 4 (v 2) (st 2))))
                            :score-part "<part-abbreviation>T.</part-abbreviation>"))
           (part (part-at s 0)))
      (ok (equal (part-name part) "Test"))
      (ok (equal (part-abbreviation part) "T."))
      (ok (equal (mapcar #'staff-clef (part-staves part)) '(:treble-8vb :alto)))
      (ok (equal (mapcar #'voice-staff (part-voices part)) '(1 2)))))
  (testing "players define the voices and name them"
    (let ((part (part-at (read-snippet (list (cat (n "C5" 4) (bk 4) (n "A4" 4 (v 2))))
                                       :score-part "<player id=\"pl1\"><player-name>Soprano</player-name></player><player id=\"pl2\"><player-name/></player><player id=\"pl3\"><player-name>Tacet</player-name></player>")
                         0)))
      (ok (equal (mapcar #'voice-name (part-voices part)) '("Soprano" nil "Tacet")))))
  (testing "players that don't fit the voice values are ignored"
    (let ((part (part-at (read-snippet (list (cat (n "C5" 4) (bk 4) (n "A4" 4 (v 2))))
                                       :score-part "<player id=\"pl1\"><player-name>Soprano</player-name></player>")
                         0)))
      (ok (equal (mapcar #'voice-name (part-voices part)) '(nil nil)))))
  (testing "voices: integer values ascending, then the others in order of appearance"
    (let ((s (read-snippet (list (cat (n "C4" 4 (v "B")) (bk 4) (n "D4" 4 (v 10)) (bk 4) (n "E4" 4 (v 2))
                                      (bk 4) (n "F4" 4 (v "A")) (bk 4) (n "G4" 4))))))
      (ok (equal (mapcar (lambda (voice) (note-names (fset:first (fset:@ (voice-measures voice) 0))))
                         (part-voices (part-at s 0)))
                 '(("G4") ("E4") ("D4") ("C4") ("F4"))))))
  (testing "a voice's stem is the one all its stems agree on"
    (let ((s (read-snippet (list (cat (n "C5" 2 "<stem>up</stem>") (n "D5" 2 "<stem>up</stem>") (bk 4)
                                      (n "A4" 2 (v 2) "<stem>down</stem>") (n "B4" 2 (v 2) "<stem>up</stem>") (bk 4)
                                      (n "C4" 2 (v 3)) (n :rest 2 (v 3)) (bk 4)
                                      (n "E4" 2 (v 4) "<stem>none</stem>") (n "F4" 2 (v 4) "<stem>down</stem>"))))))
      (ok (equal (mapcar #'voice-stem (part-voices (part-at s 0))) '(:up nil nil :down)))))
  (testing "a part without notes has one voice"
    (ok (= 1 (length (part-voices (part-at (read-snippet (list "")) 0)))))))

(deftest metadata
  (ok (equal (score-metadata
              (read-musicxml (mxml (list (n "C4" 4))
                                   :head "<work><work-title>Work</work-title></work><movement-title>Movement</movement-title><identification><creator type=\"composer\">Comp</creator><creator type=\"poet\">Poet</creator><creator type=\"lyricist\">Lyr</creator><creator type=\"arranger\">Arr</creator><creator type=\"composer\">Other</creator><rights>First</rights><rights>Second</rights></identification>")))
             '(:title "Work" :subtitle "Movement" :composer "Comp" :lyricist "Lyr" :arranger "Arr"
               :copyright "First")))
  (testing "without a work title the movement title is the title"
    (ok (equal (score-metadata (read-musicxml (mxml (list (n "C4" 4)) :head "<movement-title>M</movement-title>")))
               '(:title "M"))))
  (testing "an empty work title still makes the movement title the subtitle"
    (ok (equal (score-metadata (read-musicxml (mxml (list (n "C4" 4))
                                                    :head "<work><work-title/></work><movement-title>M</movement-title>")))
               '(:subtitle "M")))))

(deftest chord-symbols
  (let ((s (read-snippet (list (cat (n "C4" 4)))
                         :extra-parts '(("P2" ("<attributes><divisions>1</divisions></attributes><harmony><root><root-step>F</root-step></root><kind>major</kind></harmony><note><pitch><step>F</step><octave>3</octave></pitch><duration>1</duration></note><harmony><root><root-step>C</root-step></root><kind>dominant</kind><offset>1</offset></harmony><note><rest/><duration>3</duration></note>"))
                                        ("P3" ("<attributes><divisions>1</divisions></attributes><harmony><root><root-step>G</root-step></root><kind>minor</kind></harmony><note><rest/><duration>4</duration></note>"))))))
    (testing "the first part with harmonies gives the track; positions include <offset>"
      (ok (equal (mapcar #'anchor-position (seq-list (score-chord-symbols s))) '((1 . 0) (1 . 1/2))))
      (ok (equalp (mapcar #'anchor-symbol (seq-list (score-chord-symbols s))) (list (cs "F") (cs "C7")))))))
