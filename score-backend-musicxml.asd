(defsystem "score-backend-musicxml"
  :version "0.1.0"
  :description "MusicXML 4.0 (.musicxml, .mxl) reader and writer for score-protocol"
  :author "egao1980"
  :license "MIT"
  :depends-on ((:version "score-protocol" "0.1.0") (:version "music-theory" "0.4.0")
               "fset" "xml-protocol" "xml-backend-native" "serdes-protocol"
               "compression-protocol" "compression-backend-chipz")
  :pathname "src"
  :serial t
  :components ((:file "package")
               (:file "tables")
               (:file "harmony")
               (:file "reader")
               (:file "voices")
               (:file "writer")
               (:file "mxl")
               (:file "serdes"))
  :in-order-to ((test-op (test-op "score-backend-musicxml/tests"))))

(defsystem "score-backend-musicxml/tests"
  :depends-on ("score-backend-musicxml" "rove" "process-backend-uiop")
  :pathname "tests"
  :serial t
  :components ((:file "package")
               (:file "sc2-harmony-test")
               (:file "sc2-reader-test")
               (:file "sc2-ids-test")
               (:file "sc2-unsupported-test")
               (:file "sc2-writer-test")
               (:file "sc2-roundtrip-test")
               (:file "sc2-voices-test")
               (:file "sc2-mxl-test")
               (:file "sc2-serdes-test")
               (:file "sc2-xsd-test"))
  :perform (test-op (o c)
             (unless (symbol-call :rove :run c)
               (error "tests failed for ~A" (component-name c)))))
