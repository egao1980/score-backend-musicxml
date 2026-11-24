;;;; SC2 the serdes-protocol formats :MUSICXML and :MXL.
;;;;
;;;; Loading this system registers both (REGISTER-FORMAT):
;;;;   :MUSICXML  media type +MUSICXML-MEDIA-TYPE+, text. ENCODE score → the
;;;;              string WRITE-MUSICXML returns (with :STREAM, written there).
;;;;              DECODE source → READ-MUSICXML source.
;;;;   :MXL       media type +MXL-MIMETYPE+, binary. ENCODE score → the octets
;;;;              WRITE-MXL returns (with :STREAM, written there). DECODE source
;;;;              (octets or a pathname) → READ-MXL source.
;;;; Through serdes-protocol, errors reach the caller as SERDES-ENCODE-ERROR /
;;;; SERDES-DECODE-ERROR (serdes-protocol translates them with HANDLER-CASE, so
;;;; SKIP-ELEMENT isn't reachable from a handler outside SERDES:DECODE); call
;;;; READ-MUSICXML or READ-MXL to handle MUSICXML-UNSUPPORTED. This file is
;;;; given, not stubbed: it only delegates.

(in-package #:score-backend-musicxml)

(defclass musicxml-serdes-backend (serdes-protocol:serdes-backend) ()
  (:documentation "serdes-protocol backend for :MUSICXML (file header)."))

(defclass mxl-serdes-backend (serdes-protocol:serdes-backend) ()
  (:documentation "serdes-protocol backend for :MXL (file header)."))

(defmethod serdes-protocol:backend-encode ((backend musicxml-serdes-backend) value &key stream)
  (if stream
      (write-musicxml value stream)
      (write-musicxml value)))

(defmethod serdes-protocol:backend-decode ((backend musicxml-serdes-backend) source &key)
  (read-musicxml source))

(defmethod serdes-protocol:backend-media-type ((backend musicxml-serdes-backend))
  +musicxml-media-type+)

(defmethod serdes-protocol:backend-encode ((backend mxl-serdes-backend) value &key stream)
  (if stream
      (write-mxl value stream)
      (write-mxl value)))

(defmethod serdes-protocol:backend-decode ((backend mxl-serdes-backend) source &key)
  (read-mxl source))

(defmethod serdes-protocol:backend-media-type ((backend mxl-serdes-backend))
  +mxl-mimetype+)

(defmethod serdes-protocol:backend-binary-p ((backend mxl-serdes-backend))
  t)

(serdes-protocol:register-format :musicxml (make-instance 'musicxml-serdes-backend)
                                 :media-type +musicxml-media-type+)

(serdes-protocol:register-format :mxl (make-instance 'mxl-serdes-backend)
                                 :media-type +mxl-mimetype+ :binary t)
