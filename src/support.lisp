;;;; SC2 machinery the reader, the writer and voice splitting share.
;;;;
;;;; Located elements. The reader walks xml-protocol elements as %LOCs: the
;;;; element, the %LOC of its parent element and its 1-based index among the
;;;; element siblings of its name. %PATH is the path of reader.lisp
;;;; ("Unsupported"); an element located without an index (a <harmony> handed to
;;;; HARMONY-TO-CHORD-SYMBOL) is detached, and it and everything below it have
;;;; path NIL.
;;;;
;;;; Classification. %WALK of a context (a row of +ELEMENT-CONTEXTS+) returns its
;;;; mapped children, in document order. It drops IGNORED children silently,
;;;; reports every other child as unsupported, and reports a mapped child that
;;;; holds a child of +UNSUPPORTED-PARENTS+ under the mapped child's own name, so
;;;; the readers of the rules never see it. Callers name the mapped children that
;;;; are dropped silently in their situation (:SKIP: the measure-level facts of
;;;; parts other than the first).
;;;;
;;;; The policy. %UNSUPPORTED applies *UNSUPPORTED* (:ERROR outside a read, so a
;;;; direct HARMONY-TO-CHORD-SYMBOL call signals) and returns NIL: the caller
;;;; drops the element by not reading it. Under :ERROR it signals
;;;; MUSICXML-UNSUPPORTED inside a SKIP-ELEMENT restart established around the
;;;; ERROR form itself.
;;;;
;;;; Settling ids (reader.lisp "Ids", voices.lisp). %SETTLE-IDS turns a DRAFT
;;;; score into the final one in two more builds, through the canonical form:
;;;;   build 1, the draft: every element has a provisional id (a handle, or one
;;;;     the draft's MAKE-SCORE minted) or a final one (an id SPLIT-VOICES keeps).
;;;;     References name provisional or final ids. SCORE-ELEMENTS of the draft is
;;;;     score-protocol's document order after its normalising sorts.
;;;;   The first taker: in that order, a provisional element takes its CANDIDATE
;;;;     when it is VALID-ID-P and no final id and no earlier element took it.
;;;;   build 2: SEXP-TO-SCORE of the draft's form with provisional ids replaced by
;;;;     the chosen candidate or removed, and :ID-COUNTER the given counter, so
;;;;     MAKE-SCORE mints exactly as for that id-less score. References still name
;;;;     provisional ids, which have no serial and don't count.
;;;;   build 3: every reference rewritten to the final id of the element it
;;;;     named. Element n of build 2's SCORE-ELEMENTS is element n of the draft's:
;;;;     the builds differ in ids and references only, and score-protocol 0.1.0
;;;;     never orders by id (articulations by kind, lyrics by verse, jump marks by
;;;;     kind, tempo marks by offset, anchors by position, all stable).
;;;; Handles are "zH1", "zH2", ...: valid ids without a serial, fresh for each
;;;; read or split, and never one of *RESERVED-IDS*.

(in-package #:score-backend-musicxml)

;;; Located elements and paths -----------------------------------------------

(defstruct (%loc (:constructor %loc (element &optional parent index))
                 (:copier nil) (:predicate nil))
  "An XML-ELEMENT in its place (file header)."
  (element nil :read-only t)
  (parent nil :read-only t)
  (index nil :read-only t))

(defun %name (loc)
  "The local name of the located element LOC."
  (xml-protocol:xml-element-local-name (%loc-element loc)))

(defun %children (loc)
  "The element children of LOC, located, in document order. Text, CDATA,
comments and processing instructions are skipped and not counted."
  (let ((counts '()))
    (loop for child in (xml-protocol:xml-element-children (%loc-element loc))
          when (xml-protocol:xml-element-p child)
            collect (let* ((name (xml-protocol:xml-element-local-name child))
                           (cell (or (assoc name counts :test #'string=)
                                     (car (push (cons name 0) counts)))))
                      (%loc child loc (incf (cdr cell)))))))

(defun %kid (locs name)
  "The first of LOCS named NAME, or NIL."
  (find name locs :key #'%name :test #'string=))

(defun %kids (locs name)
  "Every one of LOCS named NAME, in order."
  (remove name locs :key #'%name :test-not #'string=))

(defun %child (loc name)
  "The first element child of LOC named NAME, located, or NIL."
  (%kid (%children loc) name))

(defun %path (loc)
  "\"/score-partwise[1]/part[1]/measure[2]/note[3]\" for LOC, or NIL when LOC
is detached (file header)."
  (let ((steps '()))
    (loop for at = loc then (%loc-parent at)
          while at
          do (if (%loc-index at)
                 (push (format nil "~A[~D]" (%name at) (%loc-index at)) steps)
                 (return-from %path nil)))
    (format nil "~{/~A~}" steps)))

;;; Text and numbers -----------------------------------------------------------

(defparameter +xml-whitespace+
  (coerce (list #\Space #\Tab (code-char 13) (code-char 10)) 'string)
  "The characters trimmed from text values: space, tab, CR, LF. Data.")

(defparameter +steps+ "CDEFGAB"
  "MusicXML step letters, in music-theory letter-index order. Data.")

(defun %trim (string)
  (string-trim +xml-whitespace+ string))

(defun %text (loc)
  "The text of the located element LOC, trimmed."
  (%trim (xml-protocol:xml-element-text (%loc-element loc))))

(defun %attr (loc name)
  "The value of LOC's attribute NAME, trimmed, or NIL."
  (let ((value (xml-protocol:xml-attr (%loc-element loc) name)))
    (and value (%trim value))))

(defun %ascii-digit (char)
  "The value of CHAR when it is an ASCII digit, else NIL."
  (let ((code (char-code char)))
    (and (<= 48 code 57) (- code 48))))

(defun %parse-decimal (string)
  "The exact rational STRING spells as a decimal (reader.lisp: an optional
\"-\", digits, and optionally \".\" and digits), trimmed, or NIL."
  (let* ((text (%trim string))
         (end (length text))
         (i 0) (negative nil) (value 0) (scale 1))
    (when (and (< i end) (char= (char text i) #\-))
      (setf negative t)
      (incf i))
    (flet ((scan (fraction)
             (let ((start i))
               (loop for digit = (and (< i end) (%ascii-digit (char text i)))
                     while digit
                     do (setf value (+ (* 10 value) digit))
                        (when fraction (setf scale (* 10 scale)))
                        (incf i))
               (> i start))))
      (and (scan nil)
           (or (= i end)
               (and (char= (char text i) #\.)
                    (progn (incf i) (scan t))
                    (= i end)))
           (let ((x (/ value scale)))
             (if negative (- x) x))))))

(defun %parse-integer-text (string)
  "The integer STRING spells as a decimal (\"-1.0\" is -1), or NIL."
  (let ((x (and string (%parse-decimal string))))
    (and (integerp x) x)))

(defun %digits-integer (string)
  "The integer STRING spells when it is ASCII digits only (a decimal integer),
or NIL."
  (and string
       (plusp (length string))
       (every #'%ascii-digit string)
       (parse-integer string)))

(defun %step-letter (text)
  "The letter index 0..6 of the MusicXML step TEXT (C .. B), or NIL."
  (and (= (length text) 1) (position (char text 0) +steps+)))

;;; Classification and the unsupported policy --------------------------------

(defvar *unsupported* :error
  "The UNSUPPORTED policy of the read in progress (reader.lisp). :ERROR outside
a read.")

(defun %unsupported (name loc reason &optional cause)
  "Apply *UNSUPPORTED* to the unsupported element NAME located at LOC (reader.lisp,
\"Unsupported\"). Returns NIL whenever it returns: the caller drops the element."
  (ecase *unsupported*
    (:error
     (restart-case (error 'score-protocol:musicxml-unsupported
                          :format :musicxml :element name :position (%path loc)
                          :reason reason :cause cause)
       (score-protocol:skip-element ()
         :report (lambda (stream)
                   (format stream "Drop <~A> and read on as if it weren't in the file." name))
         nil)))
    (:warn
     (warn 'score-protocol:lossy-conversion :format :musicxml :what (format nil "<~A>" name))
     nil)
    (:skip nil)))

(defun %format-error (loc reason &optional cause)
  "Signal SCORE-FORMAT-ERROR (:MUSICXML) for the structural damage at LOC."
  (error 'score-protocol:score-format-error
         :format :musicxml :position (and loc (%path loc)) :reason reason :cause cause))

(defun %poison (loc)
  "The child of LOC that makes LOC itself unsupported (+UNSUPPORTED-PARENTS+),
or NIL."
  (let ((name (%name loc)))
    (find-if (lambda (child)
               (let ((row (assoc (%name child) +unsupported-parents+ :test #'string=)))
                 (and row (string= (cdr row) name))))
             (%children loc))))

(defun %walk (loc &key skip)
  "The mapped children of the context LOC, located, in document order (file
header). Children named in SKIP are dropped silently."
  (destructuring-bind (&optional mapped ignored)
      (rest (assoc (%name loc) +element-contexts+ :test #'string=))
    (loop for child in (%children loc)
          for name = (%name child)
          when (cond ((member name skip :test #'string=) nil)
                     ((member name ignored :test #'string=) nil)
                     ((not (member name mapped :test #'string=))
                      (%unsupported name child "outside the MusicXML mapping"))
                     ((%poison child)
                      (%unsupported name child
                                    (format nil "<~A> is outside the model"
                                            (%name (%poison child)))))
                     (t t))
            collect child)))

;;; XML ------------------------------------------------------------------------

(defparameter +dtd-subset-refusal+ "external DTD subset is not fetched"
  "The message of the XML-ENTITY-ERROR xml-backend-native signals instead of
fetching a DOCTYPE's external subset; the only XML error the readers continue.
Data.")

(defun %decode-xml (source format &optional position)
  "The XML-DOCUMENT of SOURCE. The external DTD subset is never fetched (its
refusal is continued); any other XML-ERROR is a SCORE-FORMAT-ERROR of FORMAT
with that CAUSE, at POSITION, or at (line . column) when POSITION is NIL."
  (handler-case
      (handler-bind ((xml-protocol:xml-entity-error
                       (lambda (condition)
                         (when (search +dtd-subset-refusal+
                                       (or (xml-protocol:xml-error-message condition) ""))
                           (continue condition)))))
        (xml-protocol:decode source))
    (xml-protocol:xml-error (condition)
      (error 'score-protocol:score-format-error
             :format format :cause condition
             :reason (or (xml-protocol:xml-error-message condition) "not well-formed XML")
             :position (or position
                           (cons (xml-protocol:xml-error-line condition)
                                 (xml-protocol:xml-error-column condition)))))))

(defun %el (name &optional attributes &rest children)
  "A fresh XML-ELEMENT NAME. ATTRIBUTES are (name . value) conses in order; one
with a NIL value is left out. CHILDREN are elements, strings and lists of them;
NIL and \"\" are left out, so an empty text prints as <name/>."
  (apply #'xml-protocol:make-xml-element name
         (remove nil attributes :key #'cdr)
         (loop for child in children
               if (listp child) append (remove-if (lambda (c) (or (null c) (equal c ""))) child)
               else unless (equal child "") collect child)))

;;; Handles and settling ids ---------------------------------------------------

(defvar *handle-count* 0
  "The number of handles the read or split in progress allocated.")

(defvar *reserved-ids* nil
  "NIL, or a hash table of strings no handle may equal (a split's input ids and
references).")

(defun %new-handle ()
  "A fresh handle (file header)."
  (loop for handle = (format nil "zH~D" (incf *handle-count*))
        unless (and *reserved-ids* (gethash handle *reserved-ids*))
          return handle))

(defparameter +form-kinds+
  '(:measure :ending :jump :rehearsal :tempo-mark :part :staff :voice :rest :note :chord
    :chord-note :tie :articulation :fermata :breath-mark :dynamic :lyric :chord-symbol :spanner)
  "The kind keywords of score-protocol's element forms (sexp.lisp grammar). Data.")

(defun %map-form (form id-function reference-function)
  "FORM with every element :ID value v replaced by (ID-FUNCTION v), the key left
out when that is NIL, and every reference r (a :TIE's :END, a :SPANNER's :START
and :END) replaced by (REFERENCE-FUNCTION r). Values that aren't element forms
(metadata, provenance, chord-symbol plists) are copied unchanged."
  (labels ((walk (x)
             (cond ((atom x) x)
                   ((member (car x) +form-kinds+)
                    (cons (car x)
                          (loop for (key value) on (cdr x) by #'cddr
                                for new = (cond ((eq key :id) (funcall id-function value))
                                                ((and (member (car x) '(:tie :spanner))
                                                      (member key '(:start :end)))
                                                 (funcall reference-function value))
                                                (t (walk value)))
                                unless (and (eq key :id) (null new))
                                  nconc (list key new))))
                   (t (cons (walk (car x)) (walk (cdr x)))))))
    (walk form)))

(defun %with-id-counter (form counter)
  "The :SCORE FORM with :ID-COUNTER COUNTER."
  (cons :score
        (loop for (key value) on (cdr form) by #'cddr
              nconc (list key (if (eq key :id-counter) counter value)))))

(defun %settle-ids (draft &key (candidates (make-hash-table :test 'equal))
                               (final-p (constantly nil)) (id-counter 0))
  "(values score finals order): the final score of the DRAFT (file header).
CANDIDATES maps a provisional id to its carrier's id attribute; FINAL-P is true
of the ids that stay. FINALS maps each provisional id to its element's final id;
ORDER lists the draft's ids in document order."
  (let ((elements (score-protocol:score-elements draft))
        (taken (make-hash-table :test 'equal))
        (chosen (make-hash-table :test 'equal))
        (finals (make-hash-table :test 'equal)))
    (dolist (element elements)
      (let ((id (score-protocol:element-id element)))
        (when (funcall final-p id) (setf (gethash id taken) t))))
    (dolist (element elements)
      (let* ((id (score-protocol:element-id element))
             (candidate (and (not (funcall final-p id)) (gethash id candidates))))
        (when (and candidate (score-protocol:valid-id-p candidate) (not (gethash candidate taken)))
          (setf (gethash candidate taken) t
                (gethash id chosen) candidate))))
    (let* ((minted (score-protocol:sexp-to-score
                    (%with-id-counter
                     (%map-form (score-protocol:score-to-sexp draft)
                                (lambda (id) (if (funcall final-p id) id (values (gethash id chosen))))
                                #'identity)
                     id-counter)))
           (minted-elements (score-protocol:score-elements minted)))
      (assert (= (length elements) (length minted-elements)) ()
              "Settling ids changed the element count of the draft.")
      (loop for old in elements
            for new in minted-elements
            for id = (score-protocol:element-id old)
            do (assert (eq (class-of old) (class-of new)) ()
                       "Settling ids changed the document order of the draft.")
               (unless (funcall final-p id)
                 (setf (gethash id finals) (score-protocol:element-id new))))
      (values (score-protocol:sexp-to-score
               (%map-form (score-protocol:score-to-sexp minted)
                          #'identity
                          (lambda (reference) (values (gethash reference finals reference)))))
              finals
              (mapcar #'score-protocol:element-id elements)))))

(defun %present-p (string)
  "True for a non-empty string."
  (and string (plusp (length string))))

(defun %nonempty-text (loc)
  "The text of LOC, or NIL when LOC is NIL or its text is empty."
  (and loc (let ((text (%text loc))) (and (%present-p text) text))))
