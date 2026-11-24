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

(defparameter +mxl-container+ "META-INF/container.xml"
  "The entry name of an .mxl archive's container file. Data.")

(defun %container-text ()
  "META-INF/container.xml as WRITE-MXL writes it (file header)."
  (xml-protocol:encode
   (xml-protocol:make-xml-document
    :children (list (%el "container" nil
                         (%el "rootfiles" nil
                              (%el "rootfile" (list (cons "full-path" +mxl-rootfile+)
                                                    (cons "media-type" +musicxml-media-type+)))))))
   :pretty t :declaration t))

(defun write-mxl (score &optional destination)
  "SCORE as a compressed MusicXML archive, to DESTINATION (file header)."
  (check-type score score-protocol:score)
  (check-type destination (or null pathname stream))
  (let ((octets (compression-protocol:write-archive-bytes
                 (list (list "mimetype" +mxl-mimetype+)
                       (list +mxl-container+ (%container-text))
                       (list +mxl-rootfile+ (write-musicxml score)))
                 :format :zip)))
    (etypecase destination
      (null octets)
      (pathname
       (with-open-file (out destination :direction :output :if-exists :supersede
                                        :if-does-not-exist :create :element-type '(unsigned-byte 8))
         (write-sequence octets out))
       destination)
      (stream (write-sequence octets destination) destination))))

(defun read-mxl (source &key split-voices (unsupported :error))
  "The SCORE in the compressed MusicXML archive SOURCE (file header)."
  (check-type source (or pathname (vector (unsigned-byte 8))))
  (%check-read-options split-voices unsupported)
  (read-musicxml (%mxl-rootfile-octets source) :split-voices split-voices :unsupported unsupported))

(defun %mxl-error (position reason &optional cause)
  (error 'score-protocol:score-format-error :format :mxl :position position :reason reason :cause cause))

(defun %container-rootfile (document)
  "The full-path of the first MusicXML <rootfile> of the container DOCUMENT, or NIL."
  (let* ((root (xml-protocol:document-root-element document))
         (rootfiles (and root (xml-protocol:xml-child root "rootfiles")))
         (rootfile (and rootfiles
                        (find-if (lambda (rootfile)
                                   (let ((type (xml-protocol:xml-attr rootfile "media-type")))
                                     (or (null type) (string= (%trim type) +musicxml-media-type+))))
                                 (xml-protocol:xml-children-named rootfiles "rootfile")))))
    (and rootfile (xml-protocol:xml-attr rootfile "full-path"))))

(defun %mxl-rootfile-octets (source)
  "The octets of the MusicXML rootfile of the .mxl archive SOURCE (file header).
Archive damage is a SCORE-FORMAT-ERROR :MXL with the compression-protocol
condition as CAUSE."
  (let ((archive (handler-case (compression-protocol:open-archive source :format :zip)
                   (compression-protocol:compression-error (condition)
                     (%mxl-error nil "not a zip archive" condition)))))
    (unwind-protect
         (handler-case
             (let ((names (mapcar #'compression-protocol:archive-entry-name
                                  (compression-protocol:archive-entries archive))))
               (unless (member +mxl-container+ names :test #'string=)
                 (%mxl-error +mxl-container+ "no container"))
               (let ((path (%container-rootfile
                            (%decode-xml (compression-protocol:read-entry archive +mxl-container+)
                                         :mxl +mxl-container+))))
                 (unless path
                   (%mxl-error +mxl-container+ "no MusicXML rootfile in the container"))
                 (unless (member path names :test #'string=)
                   (%mxl-error path "the rootfile has no entry"))
                 (compression-protocol:read-entry archive path)))
           (compression-protocol:compression-error (condition)
             (%mxl-error nil "a damaged archive" condition)))
      (compression-protocol:close-archive archive))))
