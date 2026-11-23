(defsystem "score-backend-musicxml"
  :version "0.0.1"
  :description "MusicXML 4.0 (.musicxml, .mxl) reader and writer for score-protocol"
  :author "egao1980"
  :license "MIT"
  :pathname "src"
  :serial t
  :components ((:file "package"))
  :in-order-to ((test-op (test-op "score-backend-musicxml/tests"))))

(defsystem "score-backend-musicxml/tests"
  :depends-on ("score-backend-musicxml" "rove")
  :pathname "tests"
  :serial t
  :components ((:file "score-backend-musicxml-test"))
  :perform (test-op (o c)
             (unless (symbol-call :rove :run c)
               (error "tests failed for ~A" (component-name c)))))
