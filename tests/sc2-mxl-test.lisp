;;;; SC2 compressed MusicXML (src/mxl.lisp).

(in-package #:score-backend-musicxml/tests)

(defparameter +container-text+
  "<?xml version=\"1.0\" encoding=\"UTF-8\"?>
<container>
  <rootfiles>
    <rootfile full-path=\"score.musicxml\" media-type=\"application/vnd.recordare.musicxml+xml\"/>
  </rootfiles>
</container>
"
  "META-INF/container.xml as WRITE-MXL writes it.")

(defun quiet-mxl (score &optional destination)
  (handler-bind ((lossy-conversion #'muffle-warning))
    (write-mxl score destination)))

(defun expected-mxl (score)
  (compression-protocol:write-archive-bytes
   (list (list "mimetype" "application/vnd.recordare.musicxml")
         (list "META-INF/container.xml" +container-text+)
         (list "score.musicxml" (quiet-write score)))
   :format :zip))

(deftest-parametrize mxl-bytes
    ((name) :rows (mapcar #'list +sc0-names+))
  (let ((score (sc0-score name)))
    (testing (format nil "~A: the archive is mimetype, container and score, stored" name)
      (ok (equalp (quiet-mxl score) (expected-mxl score))))
    (testing (format nil "~A: the archive reads back as the MusicXML does" name)
      (ok (score-equal (read-mxl (quiet-mxl score)) (read-musicxml (quiet-write score)))))))

(deftest mxl-layout
  (let* ((bytes (quiet-mxl (sc0-score "sc0-pickup")))
         (archive (compression-protocol:open-archive bytes :format :zip)))
    (unwind-protect
         (progn
           (testing "entries in order, every one stored"
             (ok (equal (mapcar #'compression-protocol:archive-entry-name (compression-protocol:archive-entries archive))
                        '("mimetype" "META-INF/container.xml" "score.musicxml")))
             (ok (every (lambda (e) (eql 0 (compression-protocol:archive-entry-method e)))
                        (compression-protocol:archive-entries archive))))
           (testing "the mimetype entry"
             (ok (equalp (compression-protocol:read-entry archive "mimetype")
                         (map (quote (vector (unsigned-byte 8))) (function char-code) "application/vnd.recordare.musicxml")))))
      (compression-protocol:close-archive archive)))
  (testing "WRITE-MXL warns as WRITE-MUSICXML does"
    (ok (equal '("provenance and confidence")
               (mapcar #'lossy-conversion-what
                       (nth-value 1 (collect-warnings (lambda () (write-mxl (sc0-score "sc0-omr-result")))
                                                      'lossy-conversion)))))))

(deftest mxl-from-other-programs
  (let ((expected (read-fixture (corpus-name "amazing-grace"))))
    (testing "deflated entries, a PDF rendition listed first, the score in a subdirectory"
      (ok (score-equal expected (read-mxl (fixture-path "lead-sheet.mxl"))))
      (ok (score-equal expected (read-mxl (file-octets "lead-sheet.mxl")))))))

(deftest mxl-destinations
  (let* ((score (sc0-score "sc0-three-verses"))
         (expected (expected-mxl score)))
    (uiop:with-temporary-file (:pathname path :type "mxl")
      (testing "a pathname"
        (ok (equal path (write-mxl score path)))
        (ok (equalp expected (with-open-file (in path :element-type '(unsigned-byte 8))
                               (let ((v (make-array (file-length in) :element-type '(unsigned-byte 8))))
                                 (read-sequence v in) v))))
        (ok (score-equal score (read-mxl path))))
      (testing "a binary stream"
        (with-open-file (out path :direction :output :element-type '(unsigned-byte 8) :if-exists :supersede)
          (ok (eq out (write-mxl score out))))
        (ok (score-equal score (read-mxl path)))))))

(defun mxl-error (bytes)
  (signalled (lambda () (read-mxl bytes)) 'score-format-error))

(deftest mxl-errors
  (testing "data that isn't a zip archive"
    (let ((c (mxl-error (file-octets (corpus-name "amazing-grace")))))
      (ok (typep c 'score-format-error))
      (ok (eq :mxl (and c (score-format-error-format c))))
      (ok (typep (and c (score-format-error-cause c)) 'compression-protocol:compression-error))))
  (testing "no container"
    (let ((c (mxl-error (compression-protocol:write-archive-bytes
                         '(("mimetype" "application/vnd.recordare.musicxml") ("score.musicxml" "<x/>"))
                         :format :zip))))
      (ok (equal "META-INF/container.xml" (and c (score-format-error-position c))))
      (ok (eq :mxl (and c (score-format-error-format c))))))
  (testing "a container whose only rootfile isn't MusicXML"
    (let ((c (mxl-error (compression-protocol:write-archive-bytes
                         '(("META-INF/container.xml" "<container><rootfiles><rootfile full-path=\"a.pdf\" media-type=\"application/pdf\"/></rootfiles></container>")
                           ("a.pdf" "%PDF"))
                         :format :zip))))
      (ok (equal "META-INF/container.xml" (and c (score-format-error-position c))))))
  (testing "a rootfile with no entry"
    (let ((c (mxl-error (compression-protocol:write-archive-bytes
                         '(("META-INF/container.xml" "<container><rootfiles><rootfile full-path=\"music/missing.xml\"/></rootfiles></container>"))
                         :format :zip))))
      (ok (equal "music/missing.xml" (and c (score-format-error-position c))))))
  (testing "damage inside the score is READ-MUSICXML's, FORMAT :MUSICXML"
    (let ((c (mxl-error (compression-protocol:write-archive-bytes
                         (list (list "META-INF/container.xml" +container-text+)
                               (list "score.musicxml" "<score-partwise><part-list>"))
                         :format :zip))))
      (ok (eq :musicxml (and c (score-format-error-format c)))))))
