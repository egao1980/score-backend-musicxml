;;;; SC2 writing MusicXML (src/writer.lisp). The goldens were written by
;;;; generate-sc2.py, a separate implementation of the writer rules, and read
;;;; back by music21 (sc2-facts.sexp) and xmllint.

(in-package #:score-backend-musicxml/tests)

(defun quiet-write (score &optional destination)
  "WRITE-MUSICXML with its LOSSY-CONVERSION warnings muffled."
  (handler-bind ((lossy-conversion #'muffle-warning))
    (write-musicxml score destination)))

(deftest-parametrize goldens-are-byte-exact
    ((name) :rows (mapcar #'list +sc0-names+))
  (testing (format nil "~A writes as golden/~A.musicxml, byte for byte" name name)
    (ok (equal (quiet-write (sc0-score name)) (file-string (golden-name name))))))

(deftest-parametrize lossy-conversions
    ((name lost) :rows (quoted-rows (read-forms-file "sc2-lost.sexp")))
  (testing (format nil "~A warns ~S" name lost)
    (multiple-value-bind (text warnings)
        (collect-warnings (lambda () (write-musicxml (sc0-score name))) 'lossy-conversion)
      (ok (stringp text))
      (ok (equal lost (mapcar #'lossy-conversion-what warnings)))
      (ok (every (lambda (w) (eq :musicxml (lossy-conversion-format w))) warnings)))))

(deftest more-lossy-conversions
  (testing "a symbol whose kind MusicXML lacks; a grace note with no notated value"
    (let ((s (sexp-to-score
              '(:score :measures ((:measure :time "4/4" :key "C major"))
                :parts ((:part :staves ((:staff))
                         :voices ((:voice :measures (((:note :pitch "D5" :duration 5/32 :grace :appoggiatura)
                                                      (:note :pitch "C5" :duration 1)))))))
                :chord-symbols ((:chord-symbol :bar 1 :offset 0
                                 :symbol (:root "C" :quality :minor-major-7 :extensions (9))))))))
      (ok (equal '("chord-symbol kind" "notated value")
                 (mapcar #'lossy-conversion-what
                         (nth-value 1 (collect-warnings (lambda () (write-musicxml s)) 'lossy-conversion))))))))

(defun id-attributes (node)
  "Every id attribute value in the xml-protocol NODE's tree."
  (let ((ids '()))
    (labels ((walk (x)
               (cond ((xml-protocol:xml-document-p x)
                      (mapc #'walk (xml-protocol:xml-document-children x)))
                     ((xml-protocol:xml-element-p x)
                      (dolist (a (xml-protocol:xml-element-attributes x))
                        (when (string= (xml-protocol:xml-attribute-local-name a) "id")
                          (push (xml-protocol:xml-attribute-value a) ids)))
                      (mapc #'walk (xml-protocol:xml-element-children x))))))
      (walk node))
    ids))

(defun expected-id-attributes (score)
  "The element ids of SCORE but its measures', one slice id per measure and part,
and each part id again (the <part id> reference)."
  (append (loop for e in (score-elements score)
                unless (typep e 'measure-info) collect (element-id e))
          (mapcar #'element-id (seq-list (score-parts score)))
          (loop for m in (seq-list (score-measure-map score))
                nconc (loop for p in (seq-list (score-parts score))
                            collect (slice-id (element-id m) (element-id p))))))

(deftest-parametrize ids-are-written-once
    ((name) :rows (mapcar #'list +sc0-names+))
  (testing (format nil "~A: the document's ids are the element ids and the slice ids, each once" name)
    (let ((s (sc0-score name)))
      (ok (equal (sort (id-attributes (handler-bind ((lossy-conversion #'muffle-warning))
                                        (score-to-musicxml s)))
                       #'string<)
                 (sort (expected-id-attributes s) #'string<))))))

(deftest-parametrize divisions-per-part
    ((name divisions)
     ("sc0-carol-6-8" '(4)) ("sc0-chords-under-rests" '(1)) ("sc0-jumps" '(1)) ("sc0-key-change" '(2))
     ("sc0-keyboard" '(3 1)) ("sc0-omr-result" '(1)) ("sc0-pickup" '(2)) ("sc0-repeats-voltas" '(1))
     ("sc0-satb" '(1)) ("sc0-three-verses" '(1)))
  (testing (format nil "~A: <divisions> per part ~S" name divisions)
    (let* ((doc (handler-bind ((lossy-conversion #'muffle-warning)) (score-to-musicxml (sc0-score name))))
           (root (xml-protocol:document-root-element doc)))
      (ok (equal divisions
                 (loop for part in (xml-protocol:xml-children-named root "part")
                       collect (parse-integer
                                (xml-protocol:xml-element-text
                                 (xml-protocol:xml-child
                                  (xml-protocol:xml-child (xml-protocol:xml-child part "measure") "attributes")
                                  "divisions")))))))))

(deftest the-document
  (let* ((doc (score-to-musicxml (sc0-score "sc0-pickup")))
         (doctype (find-if #'xml-protocol:xml-doctype-p (xml-protocol:xml-document-children doc)))
         (root (xml-protocol:document-root-element doc)))
    (testing "the DOCTYPE names MusicXML 4.0 partwise"
      (ok (equal (and doctype (list (xml-protocol:xml-doctype-name doctype)
                                    (xml-protocol:xml-doctype-public-id doctype)
                                    (xml-protocol:xml-doctype-system-id doctype)))
                 '("score-partwise" "-//Recordare//DTD MusicXML 4.0 Partwise//EN"
                   "http://www.musicxml.org/dtds/partwise.dtd"))))
    (testing "the root is <score-partwise version=\"4.0\">"
      (ok (equal (xml-protocol:xml-element-local-name root) "score-partwise"))
      (ok (equal (xml-protocol:xml-attr root "version") "4.0")))
    (testing "the text is xml-protocol's encoding of the document"
      (ok (equal (write-musicxml (sc0-score "sc0-pickup"))
                 (xml-protocol:encode (score-to-musicxml (sc0-score "sc0-pickup")) :pretty t :declaration t))))))

(deftest destinations
  (let* ((score (sc0-score "sc0-three-verses"))
         (text (file-string (golden-name "sc0-three-verses"))))
    (testing "a character stream: the text is written and the stream returned"
      (ok (equal text (with-output-to-string (out)
                        (ok (eq out (write-musicxml score out)))))))
    (testing "a pathname: the file is written, UTF-8, and the pathname returned"
      (uiop:with-temporary-file (:pathname path :type "musicxml")
        (ok (equal path (write-musicxml score path)))
        (ok (equal text (uiop:read-file-string path :external-format :utf-8)))
        (testing "an existing file is superseded"
          (write-musicxml (sc0-score "sc0-pickup") path)
          (ok (equal (file-string (golden-name "sc0-pickup"))
                     (uiop:read-file-string path :external-format :utf-8))))))))

(deftest-parametrize corpus-writes-deterministically
    ((name) :rows (mapcar #'list +corpus-names+))
  (testing (format nil "~A: equal scores write equal bytes" name)
    (ok (equal (quiet-write (read-fixture (corpus-name name)))
               (quiet-write (read-fixture (corpus-name name)))))))
