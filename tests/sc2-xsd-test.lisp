;;;; SC2 validation against the MusicXML 4.0 XSD. schema-protocol-xsd can't load
;;;; that schema yet (egao1980/schema-protocol-xsd#6), so this runs xmllint out
;;;; of process, and only when MUSICXML_XSD names a local musicxml.xsd (from
;;;; github.com/w3c/musicxml, schema/ at tag v4.0, with xml.xsd, xlink.xsd and
;;;; catalog.xml beside it: xmllint gets XML_CATALOG_FILES and --nonet). Without
;;;; them every test is skipped.

(in-package #:score-backend-musicxml/tests)

(defun musicxml-xsd ()
  "The local schema and its catalog, or NIL."
  (let ((xsd (uiop:getenv "MUSICXML_XSD")))
    (and xsd (plusp (length xsd)) (probe-file xsd)
         (handler-case (zerop (stack-process:run '("xmllint" "--version") :output nil :error-output nil))
           (error () nil))
         (list (namestring (probe-file xsd))
               (namestring (merge-pathnames "catalog.xml" (probe-file xsd)))))))

(defun xmllint-valid-p (text schema)
  (destructuring-bind (xsd catalog) schema
    (zerop (stack-process:run (list "xmllint" "--nonet" "--noout" "--schema" xsd "-")
                              :input text :output nil :error-output nil
                              :env (list (cons "XML_CATALOG_FILES" catalog))))))

(deftest-parametrize written-scores-validate
    ((name) :rows (mapcar #'list (append +sc0-names+ +corpus-names+)))
  (let ((schema (musicxml-xsd)))
    (if (null schema)
        (skip "xmllint or MUSICXML_XSD missing (egao1980/schema-protocol-xsd#6)")
        (testing (format nil "~A as written validates against the MusicXML 4.0 XSD" name)
          (ok (xmllint-valid-p (quiet-write (if (member name +sc0-names+ :test #'string=)
                                                (sc0-score name)
                                                (read-fixture (corpus-name name))))
                               schema))))))
