;;;; 0.1.1 regressions. Spanners whose number is reused in another voice pair
;;;; within their voice (src/reader.lisp, CLOSING); the corpus holds the
;;;; spanners of its tune data, so old-hundredth has one hairpin, not four
;;;; (generate-sc2.py gave every voice of a tune the same event ids, #3); on a
;;;; split staff a measure of unisons is split too (src/voices.lisp, #4).

(in-package #:score-backend-musicxml/tests)

(defun event-place (score id)
  "(PART VOICE POSITION) of the event ID: the indices, from 0, of its part in
the score and of its voice in the part, and its ELEMENT-POSITION."
  (let* ((voice (element-parent score id))
         (part (element-parent score (element-id voice))))
    (list (position part (seq-list (score-parts score)))
          (position voice (part-voices part))
          (element-position score id))))

(defun spanner-rows (score)
  "Each spanner of SCORE, in order, as (KIND START END), START and END the
EVENT-PLACE of its events."
  (mapcar (lambda (sp)
            (list (spanner-kind sp) (event-place score (spanner-start sp))
                  (event-place score (spanner-end sp))))
          (seq-list (score-spanners score))))

(defun cn (pitch duration &rest extra)
  "A <chord/> <note> of PITCH with DURATION divisions; EXTRA as for N."
  (format nil "<note><chord/>~A<duration>~A</duration>~{~A~}</note>" (pitch-xml pitch) duration extra))

(defun wedge (type) (format nil "<wedge type=~S/>" type))
(defun slur (type) (nots (format nil "<slur type=~S/>" type)))

;;; Spanners numbered per voice (#3) ---------------------------------------------------

(deftest hairpins-numbered-per-voice
  (testing "two voices' hairpins, both number 1, each end in their own voice"
    (let ((s (read-snippet (list (cat (dir (wedge "crescendo") (v 1)) (n "C5" 4 (v 1)) (bk 4)
                                      (dir (wedge "crescendo") (v 2)) (n "A4" 4 (v 2)))
                                 (cat (n "D5" 2 (v 1)) (dir (wedge "stop") (v 1)) (n "E5" 2 (v 1)) (bk 4)
                                      (n "B4" 2 (v 2)) (dir (wedge "stop") (v 2)) (n "C5" 2 (v 2)))))))
      (ok (equal (spanner-rows s)
                 '((:crescendo (0 0 (1 . 0)) (0 0 (2 . 0)))
                   (:crescendo (0 1 (1 . 0)) (0 1 (2 . 0))))))
      (testing "and keep them when written and read back"
        (ok (score-equal (read-musicxml (quiet-write s)) s)))))
  (testing "a direction without <voice> stops the hairpin of its staff's voice"
    (let ((s (read-snippet (list (cat "<attributes><staves>2</staves></attributes>"
                                      (dir (wedge "diminuendo") (st 1)) (n "C5" 4 (v 1) (st 1)) (bk 4)
                                      (dir (wedge "diminuendo") (st 2)) (n "C3" 4 (v 5) (st 2)))
                                 (cat (n "D5" 2 (v 1) (st 1)) (dir (wedge "stop") (st 1)) (n "E5" 2 (v 1) (st 1))
                                      (bk 4)
                                      (n "D3" 2 (v 5) (st 2)) (dir (wedge "stop") (st 2)) (n "E3" 2 (v 5) (st 2)))))))
      (ok (equal (spanner-rows s)
                 '((:diminuendo (0 0 (1 . 0)) (0 0 (2 . 0)))
                   (:diminuendo (0 1 (1 . 0)) (0 1 (2 . 0))))))))
  (testing "with no hairpin of its number open in its voice, a stop closes the latest one"
    (let ((s (read-snippet (list (cat (dir (wedge "crescendo") (v 1)) (n "C5" 4 (v 1)) (bk 4) (n "A4" 4 (v 2)))
                                 (cat (n "D5" 4 (v 1)) (bk 4)
                                      (n "B4" 2 (v 2)) (dir (wedge "stop") (v 2)) (n "C5" 2 (v 2)))))))
      (ok (equal (spanner-rows s) '((:crescendo (0 0 (1 . 0)) (0 1 (2 . 0)))))))))

(deftest slurs-numbered-per-voice
  (testing "two voices' slurs, both number 1, each end in their own voice"
    (let ((s (read-snippet (list (cat (n "C5" 4 (v 1) (slur "start")) (bk 4) (n "A4" 4 (v 2) (slur "start")))
                                 (cat (n "D5" 4 (v 1) (slur "stop")) (bk 4) (n "B4" 4 (v 2) (slur "stop")))))))
      (ok (equal (spanner-rows s)
                 '((:slur (0 0 (1 . 0)) (0 0 (2 . 0)))
                   (:slur (0 1 (1 . 0)) (0 1 (2 . 0))))))
      (testing "and keep them when written and read back"
        (ok (score-equal (read-musicxml (quiet-write s)) s)))))
  (testing "with no slur of its number open in its voice, a stop closes the latest one"
    (let ((s (read-snippet (list (cat (n "C5" 4 (v 1) (slur "start")) (bk 4) (n "A4" 4 (v 2)))
                                 (cat (n "D5" 4 (v 1)) (bk 4) (n "B4" 4 (v 2) (slur "stop")))))))
      (ok (equal (spanner-rows s) '((:slur (0 0 (1 . 0)) (0 1 (2 . 0)))))))))

(defparameter +corpus-spanners+
  '(("amazing-grace"
     (:slur (0 0 (1 . 1/2)) (0 0 (1 . 5/8)))
     (:slur (0 0 (5 . 1/2)) (0 0 (5 . 5/8)))
     (:slur (0 0 (6 . 1/2)) (0 0 (6 . 5/8))))
    ("londonderry-air"
     (:crescendo (0 0 (2 . 0)) (0 0 (3 . 3/8))))
    ("old-hundredth"
     (:crescendo (0 0 (2 . 0)) (0 0 (3 . 0)))))
  "Per corpus file with spanners, the SPANNER-ROWS of its tune data
(generate-sc2.py); the other files have none.")

(deftest-parametrize corpus-spanners
    ((name) :rows (mapcar #'list +corpus-names+))
  (testing (format nil "~A holds its tune's spanners, each in its own voice" name)
    (ok (equal (spanner-rows (read-fixture (corpus-name name)))
               (rest (assoc name +corpus-spanners+ :test #'string=))))))

;;; Unison measures on a split staff (#4) ---------------------------------------------

(defun satb-measures (shared)
  "Four bars of a hymn on two staves: hymnal layout when SHARED (shared-stem
chords, a single note for a unison, soprano and alto parting in bar 2 as
voices 1 and 2), else hand-split into voices 1, 2, 5 and 6. Bars 3 and 4 end
on D4 in soprano and alto, tied across the barline; bar 4 is one unison."
  (flet ((up (k) (cat (v k) "<stem>up</stem>"))
         (down (k) (cat (v k) "<stem>down</stem>"))
         (tie-start () "<tie type=\"start\"/>")
         (tied-start () (nots "<tied type=\"start\"/>"))
         (tie-stop () "<tie type=\"stop\"/>")
         (tied-stop () (nots "<tied type=\"stop\"/>")))
    (if shared
        (list (cat "<attributes><staves>2</staves></attributes>"
                   (n "G4" 1 (v 1) (st 1)) (cn "B4" 1 (v 1) (st 1))
                   (n "F#4" 1 (v 1) (st 1)) (cn "A4" 1 (v 1) (st 1))
                   (n "D4" 1 (v 1) (st 1)) (cn "G4" 1 (v 1) (st 1))
                   (n "E4" 1 (v 1) (st 1)) (cn "G4" 1 (v 1) (st 1))
                   (bk 4)
                   (n "G3" 1 (v 5) (st 2)) (cn "D4" 1 (v 5) (st 2))
                   (n "D3" 1 (v 5) (st 2)) (cn "D4" 1 (v 5) (st 2))
                   (n "G3" 1 (v 5) (st 2)) (cn "B3" 1 (v 5) (st 2))
                   (n "C3" 1 (v 5) (st 2)) (cn "C4" 1 (v 5) (st 2)))
              (cat (n "A4" 2 (up 1) (st 1)) (n "B4" 2 (up 1) (st 1))
                   (bk 4)
                   (n "F#4" 1 (down 2) (st 1)) (n "G4" 1 (down 2) (st 1)) (n "G4" 2 (down 2) (st 1))
                   (bk 4)
                   (n "D3" 2 (v 5) (st 2)) (cn "D4" 2 (v 5) (st 2))
                   (n "G3" 2 (v 5) (st 2)) (cn "D4" 2 (v 5) (st 2)))
              (cat (n "F#4" 1 (v 1) (st 1)) (cn "A4" 1 (v 1) (st 1))
                   (n "E4" 1 (v 1) (st 1)) (cn "G4" 1 (v 1) (st 1))
                   (n "D4" 1 (v 1) (st 1)) (cn "F#4" 1 (v 1) (st 1))
                   (n "D4" 1 (tie-start) (v 1) (st 1) (tied-start))
                   (bk 4)
                   (n "A2" 1 (v 5) (st 2)) (cn "C4" 1 (v 5) (st 2))
                   (n "E3" 1 (v 5) (st 2)) (cn "B3" 1 (v 5) (st 2))
                   (n "D3" 1 (v 5) (st 2)) (cn "A3" 1 (v 5) (st 2))
                   (n "D3" 1 (v 5) (st 2)) (cn "A3" 1 (v 5) (st 2)))
              (cat (n "D4" 4 (tie-stop) (v 1) (st 1) (tied-stop))
                   (bk 4)
                   (n "G2" 4 (v 5) (st 2)) (cn "B3" 4 (v 5) (st 2))))
        (flet ((line (k stem staff notes)
                 (apply #'cat (loop for (pitch duration tie) in notes
                                    collect (apply #'n pitch duration
                                                   (append (and (eq tie :start) (list (tie-start)))
                                                           (and (eq tie :stop) (list (tie-stop)))
                                                           (list (funcall stem k) (st staff))
                                                           (and (eq tie :start) (list (tied-start)))
                                                           (and (eq tie :stop) (list (tied-stop)))))))))
          (loop for (s a te b) in '(((("B4" 1) ("A4" 1) ("G4" 1) ("G4" 1))
                                     (("G4" 1) ("F#4" 1) ("D4" 1) ("E4" 1))
                                     (("D4" 1) ("D4" 1) ("B3" 1) ("C4" 1))
                                     (("G3" 1) ("D3" 1) ("G3" 1) ("C3" 1)))
                                    ((("A4" 2) ("B4" 2))
                                     (("F#4" 1) ("G4" 1) ("G4" 2))
                                     (("D4" 2) ("D4" 2))
                                     (("D3" 2) ("G3" 2)))
                                    ((("A4" 1) ("G4" 1) ("F#4" 1) ("D4" 1 :start))
                                     (("F#4" 1) ("E4" 1) ("D4" 1) ("D4" 1 :start))
                                     (("C4" 1) ("B3" 1) ("A3" 1) ("A3" 1))
                                     (("A2" 1) ("E3" 1) ("D3" 1) ("D3" 1)))
                                    ((("D4" 4 :stop))
                                     (("D4" 4 :stop))
                                     (("B3" 4))
                                     (("G2" 4))))
                for i from 0
                collect (cat (if (= i 0) "<attributes><staves>2</staves></attributes>" "")
                             (line 1 #'up 1 s) (bk 4) (line 2 #'down 1 a) (bk 4)
                             (line 5 #'up 2 te) (bk 4) (line 6 #'down 2 b)))))))

(defun satb (shared &rest keys)
  (apply #'read-snippet (satb-measures shared) :fifths 1 keys))

(deftest split-unison-measures
  (testing "the hand-split edition reads as soprano, alto, tenor and bass"
    (let ((s (satb nil)))
      (ok (equal (mapcar #'voice-staff (part-voices (part-at s 0))) '(1 1 2 2)))
      (ok (equal (mapcar #'voice-stem (part-voices (part-at s 0))) '(:up :down :up :down)))))
  (multiple-value-bind (split guesses)
      (collect-warnings (lambda () (satb t :split-voices :auto)) 'low-confidence-guess)
    (testing "split, the hymnal layout is the hand-split edition, the unison bar 4 too"
      (ok (same-content-p split (satb nil)))
      (ok (null (check-score split))))
    (testing "the alto sings the unison D4s of bars 3 and 4, tied"
      (let ((alto-3 (car (last (measure-events split 0 1 2))))
            (alto-4 (measure-events split 0 1 3)))
        (ok (equal (mapcar #'note-names alto-4) '(("D4"))))
        (ok (and (note-tie alto-3) alto-4
                 (equal (tie-end (note-tie alto-3)) (element-id (first alto-4)))))))
    (testing "both copies are guesses, signalled in document order"
      (ok (equal (mapcar (lambda (g) (list (low-confidence-guess-what g)
                                           (event-place split (low-confidence-guess-element-id g))))
                         guesses)
                 '(("unison" (0 1 (3 . 3/4))) ("unison" (0 1 (4 . 0))))))
      (ok (equal (mapcar #'element-id (uncertain-elements split))
                 (mapcar #'low-confidence-guess-element-id guesses))))
    (testing "a split score has nothing left to split"
      (ok (score-equal (split-voices split) split)))))

(deftest split-rests-and-unisons
  (let ((s (read-snippet (list (cat (n "C4" 4) (cn "E4" 4)) (n :rest 4) (cat (n "E4" 2) (n "D4" 2))))))
    (multiple-value-bind (split guesses) (collect-warnings (lambda () (split-voices s)) 'low-confidence-guess)
      (testing "once a staff splits, a bar of rests or single notes gives the lower voice copies"
        (ok (equal (voice-forms split 0 1)
                   '(((:note :pitch "C4" :duration 1))
                     ((:rest :duration 1))
                     ((:note :pitch "E4" :duration 1/2) (:note :pitch "D4" :duration 1/2))))))
      (testing "the upper voice keeps its events"
        (ok (equal (voice-forms split 0 0)
                   '(((:note :pitch "E4" :duration 1))
                     ((:rest :duration 1))
                     ((:note :pitch "E4" :duration 1/2) (:note :pitch "D4" :duration 1/2))))))
      (testing "the copied notes are guesses, the copied rest isn't"
        (ok (equal (mapcar #'low-confidence-guess-what guesses) '("unison" "unison")))
        (ok (equal (mapcar (lambda (e) (element-position split (element-id e))) (uncertain-elements split))
                   '((3 . 0) (3 . 1/2)))))))
  (testing "a staff with no chord isn't split, whatever its measures hold"
    (let ((s (read-snippet (list (cat (n "C4" 2) (n "D4" 2)) (n :rest 4) (n "E4" 4)))))
      (ok (score-equal (split-voices s) s)))))
