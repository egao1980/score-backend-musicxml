;;;; SC2 hymnal voice splitting (src/voices.lisp). hymn-shared and hymn-split are
;;;; the same hymn in shared-stem layout and hand-split into four voices
;;;; (tests/fixtures/generate-sc2.py).

(in-package #:score-backend-musicxml/tests)

(defun shared () (read-fixture (corpus-name "hymn-shared")))
(defun shared-split () (read-fixture (corpus-name "hymn-shared") :split-voices :auto))
(defun hand-split () (read-fixture (corpus-name "hymn-split")))

(defun measure-events (score part voice measure)
  (seq-list (fset:@ (voice-measures (voice-at score part voice)) measure)))

(deftest split-matches-the-hand-split-edition
  (testing "split, the shared-stem hymn is the hand-split one (up to id names)"
    (ok (same-content-p (shared-split) (hand-split))))
  (testing "SPLIT-VOICES on the read score is what :SPLIT-VOICES :AUTO reads"
    (ok (score-equal (split-voices (shared)) (shared-split))))
  (testing "a score with no shared stems is unchanged"
    (ok (score-equal (split-voices (hand-split)) (hand-split)))))

(deftest unsplit-reading
  (let ((s (shared)))
    (testing "without :SPLIT-VOICES the file's voices stay: 1 and 2 on the treble staff, 5 on the bass"
      (ok (equal (mapcar #'voice-staff (part-voices (part-at s 0))) '(1 1 2)))
      (ok (every (lambda (e) (typep e '(or chord-event note-event))) (measure-events s 0 0 0)))
      (ok (typep (first (measure-events s 0 0 0)) 'chord-event)))))

(deftest split-ids
  (let* ((s (shared)) (split (shared-split)))
    (testing "the upper voice keeps every event id"
      (ok (equal (mapcar #'element-id (events split 0 0)) (mapcar #'element-id (events s 0 0)))))
    (testing "the lower voice takes the lower chord notes' ids"
      (ok (equal (mapcar #'element-id (measure-events split 0 1 0))
                 (mapcar (lambda (c) (element-id (first (chord-event-notes c)))) (measure-events s 0 0 0)))))
    (testing "a tie that ended on a dropped upper note ends on its chord's id"
      (let ((tenor-m3 (car (last (measure-events split 0 2 2))))
            (tenor-m4 (first (measure-events split 0 2 3))))
        (ok (equal (tie-end (note-tie tenor-m3)) (element-id tenor-m4)))
        (ok (null (check-score split)))))
    (testing "new voices sit after their upper voice, stems up and down"
      (ok (equal (mapcar #'voice-staff (part-voices (part-at split 0))) '(1 1 2 2)))
      (ok (equal (mapcar #'voice-stem (part-voices (part-at split 0))) '(:up :down :up :down))))))

(deftest split-guesses
  (multiple-value-bind (s guesses) (collect-warnings #'shared-split 'low-confidence-guess)
    (testing "the unison is the one guess, signalled once"
      (ok (equal (mapcar (lambda (g) (list (low-confidence-guess-what g) (low-confidence-guess-confidence g)))
                         guesses)
                 '(("unison" 1/2)))))
    (let ((u (uncertain-elements s)))
      (testing "it is the alto's copy of the soprano's G4 in bar 2"
        (ok (= 1 (length u)))
        (ok (equal (and u (element-id (first u))) (and guesses (low-confidence-guess-element-id (first guesses)))))
        (ok (equal (and u (list (element-position s (element-id (first u))) (note-names (first u))))
                   '((2 . 0) ("G4"))))
        (ok (eq (and u (element-parent s (element-id (first u)))) (voice-at s 0 1)))
        (ok (eql 1/2 (and u (element-confidence (first u)))))
        (ok (equalp (and u (element-provenance (first u)))
                    (make-provenance :source :musicxml :backend "score-backend-musicxml")))))))

(deftest split-three-note-chords
  (let ((s (sexp-to-score
            '(:score :measures ((:measure :time "4/4" :key "C major"))
              :parts ((:part :staves ((:staff))
                       :voices ((:voice :measures (((:chord :id "c" :notes ((:chord-note :id "lo" :pitch "C4")
                                                                           (:chord-note :id "mid" :pitch "E4")
                                                                           (:chord-note :id "hi" :pitch "G4"))
                                                     :duration 1 :fermata (:fermata :id "f"))))))))))))
    (multiple-value-bind (split guesses) (collect-warnings (lambda () (split-voices s)) 'low-confidence-guess)
      (testing "the top note goes up, the others stay a chord below"
        (ok (equal (mapcar (lambda (v) (strip-ids (element-to-sexp v))) (part-voices (part-at split 0)))
                   '((:voice :stem :up :measures (((:note :pitch "G4" :duration 1 :fermata (:fermata)))))
                     (:voice :stem :down
                      :measures (((:chord :notes ((:chord-note :pitch "C4") (:chord-note :pitch "E4"))
                                   :duration 1 :fermata (:fermata)))))))))
      (testing "ids: the upper event keeps the chord's, the lower chord keeps its notes'"
        (ok (equal (element-id (first (measure-events split 0 0 0))) "c"))
        (ok (equal (mapcar #'element-id (chord-event-notes (first (measure-events split 0 1 0)))) '("lo" "mid")))
        (ok (equal (element-id (event-fermata (first (measure-events split 0 0 0)))) "f")))
      (testing "both events are guesses"
        (ok (equal (mapcar #'low-confidence-guess-what guesses) '("chord split" "chord split")))
        (ok (equal (mapcar #'element-confidence (uncertain-elements split)) '(1/2 1/2)))))))
