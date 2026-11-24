;;;; SC2 the serdes-protocol formats (src/serdes.lisp).

(in-package #:score-backend-musicxml/tests)

(deftest formats-are-registered
  (ok (typep (serdes-protocol:find-backend :musicxml) 'musicxml-serdes-backend))
  (ok (typep (serdes-protocol:find-backend :mxl) 'mxl-serdes-backend))
  (ok (equal (serdes-protocol:format-media-type :musicxml) "application/vnd.recordare.musicxml+xml"))
  (ok (equal (serdes-protocol:format-media-type :mxl) "application/vnd.recordare.musicxml"))
  (ok (eq :mxl (serdes-protocol:find-format-for-media-type "application/vnd.recordare.musicxml")))
  (ok (serdes-protocol:format-binary-p :mxl))
  (ng (serdes-protocol:format-binary-p :musicxml)))

(deftest encode-and-decode
  (let ((score (sc0-score "sc0-satb")))
    (testing ":musicxml is WRITE-MUSICXML and READ-MUSICXML"
      (ok (equal (serdes-protocol:encode score :format :musicxml) (write-musicxml score)))
      (ok (score-equal (serdes-protocol:decode (write-musicxml score) :format :musicxml) score)))
    (testing ":mxl is WRITE-MXL and READ-MXL"
      (ok (equalp (serdes-protocol:encode score :format :mxl) (write-mxl score)))
      (ok (score-equal (serdes-protocol:decode (write-mxl score) :format :mxl) score)))
    (testing "with :STREAM the text goes to the stream"
      (ok (equal (with-output-to-string (out) (serdes-protocol:encode score :format :musicxml :stream out))
                 (write-musicxml score))))))

(deftest errors-through-serdes
  (testing "serdes-protocol reports reader errors as its own decode error, naming ours"
    (let ((c (signalled (lambda ()
                          (serdes-protocol:decode (mxml (list (n "C4" 4 (nots "<ornaments><trill-mark/></ornaments>"))))
                                                  :format :musicxml))
                        'serdes-protocol:serdes-decode-error)))
      (ok (typep c 'serdes-protocol:serdes-decode-error))
      (ok (and c (search "ornaments[1]" (serdes-protocol:serdes-error-message c)))))))
