;;;; SC2 compressed MusicXML (.mxl): a zip archive with a container file.
;;;;
;;;; Archives go through compression-protocol (OPEN-ARCHIVE, READ-ENTRY,
;;;; WRITE-ARCHIVE-BYTES); compression-backend-chipz inflates deflated entries.
;;;;
;;;; WRITE-MXL score &optional destination → with DESTINATION NIL, the archive as
;;;; an octet vector; with a pathname, the file is written (superseding) and the
;;;; pathname returned; with a binary output stream, the octets are written to it
;;;; and the stream returned. The archive is exactly
;;;;   (compression-protocol:write-archive-bytes
;;;;    (list (list "mimetype" +mxl-mimetype+)
;;;;          (list "META-INF/container.xml" container)
;;;;          (list +mxl-rootfile+ (write-musicxml score)))
;;;;    :format :zip)
;;;; with CONTAINER the text of
;;;;   <?xml version="1.0" encoding="UTF-8"?>
;;;;   <container>
;;;;     <rootfiles>
;;;;       <rootfile full-path="score.musicxml" media-type=+MUSICXML-MEDIA-TYPE+/>
;;;;     </rootfiles>
;;;;   </container>
;;;; as xml-protocol encodes it (:pretty t :declaration t). Every entry is stored
;;;; (zip method 0) with no timestamp, so the bytes depend on the score only, and
;;;; "mimetype" comes first, uncompressed, as MusicXML 4.0 asks. WRITE-MXL warns
;;;; LOSSY-CONVERSION exactly as WRITE-MUSICXML does (FORMAT :MUSICXML).
;;;;
;;;; READ-MXL source &key split-voices (unsupported :error) → a SCORE. SOURCE is a
;;;; pathname or an octet vector. The rootfile is the full-path of the first
;;;; <rootfile> in META-INF/container.xml whose media-type is absent or
;;;; +MUSICXML-MEDIA-TYPE+ (other rootfiles are alternative renditions, such as
;;;; PDF); its entry is read as MusicXML with READ-MUSICXML and the keywords. The
;;;; mimetype entry is not required (MusicXML 2.0 archives have none). SCORE-
;;;; FORMAT-ERROR with FORMAT :MXL: data that isn't a zip archive or is damaged
;;;; (CAUSE the ARCHIVE-ERROR or COMPRESSION-ERROR, POSITION NIL); no
;;;; META-INF/container.xml, or one with no such rootfile (POSITION
;;;; "META-INF/container.xml"); a rootfile path with no entry (POSITION that
;;;; path). Errors in the MusicXML itself are READ-MUSICXML's (FORMAT :MUSICXML).

(in-package #:score-backend-musicxml)

(defparameter +mxl-mimetype+ "application/vnd.recordare.musicxml"
  "The content of an .mxl archive's mimetype entry, and the :MXL media type.
Data.")

(defparameter +musicxml-media-type+ "application/vnd.recordare.musicxml+xml"
  "The media type of uncompressed MusicXML: the :MUSICXML media type, and the
rootfile media-type in container.xml. Data.")

(defparameter +mxl-rootfile+ "score.musicxml"
  "The entry name WRITE-MXL gives the score. Data.")

(defun write-mxl (score &optional destination)
  "SCORE as a compressed MusicXML archive, to DESTINATION (file header)."
  (declare (ignore score destination))
  (%sc2-pending 'write-mxl))

(defun read-mxl (source &key split-voices (unsupported :error))
  "The SCORE in the compressed MusicXML archive SOURCE (file header)."
  (declare (ignore source split-voices unsupported))
  (%sc2-pending 'read-mxl))
