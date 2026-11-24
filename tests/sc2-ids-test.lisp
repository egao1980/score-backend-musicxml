;;;; SC2 ids in MusicXML (src/reader.lisp, "Ids"): carried by id attributes,
;;;; minted as MAKE-SCORE mints them otherwise.

(in-package #:score-backend-musicxml/tests)

(defun ids-of (score) (mapcar #'element-id (score-elements score)))

(deftest ids-from-carriers
  (let ((s (read-musicxml
            (mxml (list (list " number=\"1\" id=\"m-1.P1\""
                              (cat "<attributes><clef id=\"st-1\"><sign>G</sign><line>2</line></clef></attributes>"
                                   "<barline location=\"left\" id=\"en-1\"><ending number=\"1\" type=\"start\"/></barline>"
                                   "<direction id=\"jm-1\"><direction-type><segno/></direction-type><sound segno=\"s\"/></direction>"
                                   "<direction id=\"rh-1\"><direction-type><rehearsal>A</rehearsal></direction-type></direction>"
                                   "<direction id=\"tm-1\"><direction-type><metronome><beat-unit>quarter</beat-unit><per-minute>60</per-minute></metronome></direction-type></direction>"
                                   "<harmony id=\"h-1\"><root><root-step>C</root-step></root><kind>major</kind></harmony>"
                                   "<direction id=\"dy-1\"><direction-type><dynamics><mf/></dynamics></direction-type></direction>"
                                   "<direction id=\"sp-2\"><direction-type><wedge type=\"crescendo\"/></direction-type></direction>"
                                   "<note id=\"e-1\"><pitch><step>C</step><octave>4</octave></pitch><duration>2</duration><tie type=\"start\"/>"
                                   "<notations><tied type=\"start\" id=\"ti-1\"/><slur type=\"start\" id=\"sp-1\"/><articulations id=\"ar-1\"><staccato/></articulations>"
                                   "<articulations id=\"br-1\"><breath-mark/></articulations><fermata id=\"fe-1\"/></notations><lyric id=\"ly-1\"><text>la</text></lyric></note>"
                                   "<note id=\"e-3\"><pitch><step>C</step><octave>4</octave></pitch><duration>2</duration><notations><slur type=\"stop\"/></notations></note>"
                                   "<direction><direction-type><wedge type=\"stop\"/></direction-type></direction>"))
                        (list " number=\"2\" id=\"m-2.P1\""
                              (cat "<note id=\"n-1\"><pitch><step>C</step><octave>4</octave></pitch><duration>4</duration><notations id=\"e-2\"/></note>"
                                   "<note id=\"n-2\"><chord/><pitch><step>E</step><octave>4</octave></pitch><duration>4</duration></note>"
                                   "<barline location=\"right\"><ending number=\"1\" type=\"stop\"/></barline>")))
                  :score-part "<player id=\"v-1\"><player-name>Voice</player-name></player>"))))
    (testing "every element takes its carrier's id, in document order"
      (ok (equal (ids-of s)
                 '("m-1" "en-1" "jm-1" "rh-1" "tm-1" "m-2" "P1" "st-1" "v-1" "e-1" "ti-1" "ar-1"
                   "fe-1" "br-1" "dy-1" "ly-1" "e-3" "e-2" "n-1" "n-2" "h-1" "sp-2" "sp-1"))))
    (testing "references use the carried ids"
      (ok (equal (tie-end (note-tie (find-element s "e-1"))) "e-3"))
      (ok (equal (mapcar (lambda (sp) (list (spanner-start sp) (spanner-end sp))) (seq-list (score-spanners s)))
                 '(("e-1" "e-3") ("e-1" "e-3")))))
    (testing "the counter is the highest serial seen"
      (ok (= 3 (score-id-counter s))))))

(deftest ids-minted-in-document-order
  (let ((s (read-snippet (list (cat "<harmony><root><root-step>C</root-step></root><kind>major</kind></harmony>"
                                    (n "C4" 2 (nots "<slur type=\"start\"/>") "<lyric><text>a</text></lyric>")
                                    (n "D4" 2 (nots "<slur type=\"stop\"/>")))
                               (n "E4" 4)))))
    (ok (equal (ids-of s) '("m-1" "m-2" "P1" "st-3" "v-4" "e-5" "ly-6" "e-7" "e-8" "h-9" "sp-a")))
    (ok (= 10 (score-id-counter s)))))

(deftest ids-that-are-not-taken
  (let ((s (read-musicxml
            (mxml (list (list " number=\"1\" id=\"m-1.P2\""
                              (cat "<note id=\"1x\"><pitch><step>C</step><octave>4</octave></pitch><duration>2</duration></note>"
                                   "<note id=\"e-5\"><pitch><step>D</step><octave>4</octave></pitch><duration>2</duration></note>"))
                        (list " number=\"2\" id=\"m-7.P1\""
                              (cat "<note id=\"e-5\"><pitch><step>E</step><octave>4</octave></pitch><duration>2</duration></note>"
                                   "<note id=\"e-6\"><pitch><step>F</step><octave>4</octave></pitch><duration>2</duration></note>")))))))
    (testing "invalid ids, ids taken earlier and slices of another part are minted"
      (ok (equal (ids-of s) '("m-8" "m-7" "P1" "st-9" "v-a" "e-b" "e-5" "e-c" "e-6"))))))

(deftest measure-ids-come-from-the-first-part
  (let ((s (read-musicxml
            (mxml (list (list " number=\"1\" id=\"m-3.P1\"" (n "C4" 4)))
                  :extra-parts '(("P2" ("<attributes><divisions>1</divisions></attributes><note><rest/><duration>4</duration></note>")))))))
    (ok (equal (element-id (first (seq-list (score-measure-map s)))) "m-3"))))

(deftest voice-ids-only-from-players
  (testing "players that define the voices give their ids"
    (ok (equal (mapcar #'element-id
                       (part-voices (part-at (read-snippet (list (cat (n "C5" 4) (bk 4) (n "A4" 4 (v 2))))
                                                           :score-part "<player id=\"S\"><player-name>S</player-name></player><player id=\"A\"><player-name>A</player-name></player>")
                                             0)))
               '("S" "A"))))
  (testing "otherwise voices get minted ids"
    (ok (every (lambda (id) (and (valid-id-p id) (string= "v-" (subseq id 0 2))))
               (mapcar #'element-id
                       (part-voices (part-at (read-snippet (list (cat (n "C5" 4) (bk 4) (n "A4" 4 (v 2))))
                                                           :score-part "<player id=\"S\"><player-name>S</player-name></player>")
                                             0)))))))

(defun strip-minted-ids (form)
  "FORM without the ids of elements other than parts (whose ids MusicXML files
always give), and without the counter."
  (cond ((atom form) form)
        ((member (car form) (cons :score +element-kinds+))
         (cons (car form)
               (loop for (key value) on (cdr form) by #'cddr
                     unless (or (eq key :id-counter) (and (eq key :id) (not (eq (car form) :part))))
                       nconc (list key (strip-minted-ids value)))))
        (t (cons (strip-minted-ids (car form)) (strip-minted-ids (cdr form))))))

(deftest-parametrize corpus-ids-are-make-score-ids
    ((name) :rows (mapcar #'list +corpus-names+))
  (let ((s (read-fixture (corpus-name name))))
    (testing (format nil "~A: reading twice gives the same ids" name)
      (ok (score-equal s (read-fixture (corpus-name name)))))
    (testing (format nil "~A: the ids are the ones MAKE-SCORE mints for an id-less copy" name)
      (ok (score-equal s (sexp-to-score (strip-minted-ids (score-to-sexp s))))))))
