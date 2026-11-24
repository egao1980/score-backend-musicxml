;;;; SC2 round trips (src/writer.lisp, "Round trip"): score → MusicXML → score,
;;;; and file → score → MusicXML → score.

(in-package #:score-backend-musicxml/tests)

(deftest-parametrize sc0-scores-round-trip
    ((name) :rows (mapcar #'list +sc0-names+))
  (testing (format nil "~A: write then read gives the score back, ids preserved" name)
    (ok (score-equal (read-musicxml (quiet-write (sc0-score name))) (sexp-to-score (lossless-form name))))))

(deftest-parametrize files-round-trip
    ((file) :rows (mapcar #'list +fact-files+))
  (let* ((first (read-fixture file))
         (text (quiet-write first))
         (second (read-musicxml text)))
    (testing (format nil "~A: read, write, read gives the same score, ids included" file)
      (ok (score-equal first second)))
    (testing (format nil "~A: writing it again gives the same bytes" file)
      (ok (equal text (quiet-write second))))))

(deftest-parametrize goldens-rewrite-as-themselves
    ((name) :rows (mapcar #'list +sc0-names+))
  (testing (format nil "~A: the golden file, read and written, is unchanged" name)
    (ok (equal (quiet-write (read-fixture (golden-name name))) (file-string (golden-name name))))))

(deftest round-trip-losses
  (testing "provenance and confidence are not carried"
    (let ((back (read-musicxml (quiet-write (sc0-score "sc0-omr-result")))))
      (ok (null (uncertain-elements back :below 2)))
      (ok (notany #'element-provenance (score-elements back)))))
  (testing "chord symbols come back without TEXT and DIALECT"
    (let ((back (read-musicxml (quiet-write (sc0-score "sc0-chords-under-rests")))))
      (ok (notany (lambda (a) (or (chord-symbol-text (anchor-symbol a)) (chord-symbol-dialect (anchor-symbol a))))
                  (seq-list (score-chord-symbols back)))))))
