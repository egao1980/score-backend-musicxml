;;;; score-backend-musicxml: MusicXML 4.0 partwise, plain (.musicxml) and
;;;; compressed (.mxl), for score-protocol. Brief: cl-stack/docs/capabilities/
;;;; score.md, slice SC2. XML goes through xml-protocol and xml-backend-native
;;;; (the DOCTYPE is written, never fetched); .mxl archives through
;;;; compression-protocol; chord symbols are music-theory values.

(defpackage #:score-backend-musicxml
  (:use #:cl)
  (:nicknames #:stack-score-musicxml)
  (:documentation "Reads MusicXML 4.0 partwise scores into score-protocol scores and writes
them back, as text (.musicxml) or as a compressed archive (.mxl). Element ids
travel as MusicXML id attributes. Also registers the serdes-protocol formats
:MUSICXML and :MXL (SC2).")
  (:export
   ;; Reading (reader.lisp)
   #:read-musicxml #:musicxml-to-score
   ;; Writing (writer.lisp)
   #:write-musicxml #:score-to-musicxml
   ;; Compressed MusicXML (mxl.lisp)
   #:read-mxl #:write-mxl
   ;; Chord symbols as <harmony> (harmony.lisp)
   #:harmony-to-chord-symbol #:chord-symbol-to-harmony
   ;; Hymnal voice splitting (voices.lisp)
   #:split-voices
   ;; serdes-protocol formats (serdes.lisp)
   #:musicxml-serdes-backend #:mxl-serdes-backend))

(in-package #:score-backend-musicxml)

(defun %sc21-pending (name)
  "Contract stub for the 0.1.1 bug fixes (SC2.1). Every call is replaced by the
implementation, then this function is deleted."
  (error "score-backend-musicxml SC2.1 pending: ~A" name))
