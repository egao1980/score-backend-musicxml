;;;; SC2 chord symbols as MusicXML <harmony>, both directions.
;;;;
;;;; The chord-level mapping belongs to music-theory (0.5.1, music-theory#16):
;;;; MUSIC-THEORY:CHORD-SYMBOL-MUSICXML-KIND chord → (values kind degrees) and
;;;; MUSIC-THEORY:MUSICXML-KIND-CHORD-SYMBOL kind root &key bass degrees → a
;;;; CHORD-SYMBOL, or NIL for "other". A degree there is (type value alter): TYPE
;;;; :ADD, :ALTER or :SUBTRACT, VALUE and ALTER integers, in MusicXML order;
;;;; their rules (which kind names a chord, structural degrees, suspensions,
;;;; which degrees a kind admits) are in music-theory's src/chord-symbol.lisp
;;;; header. The two functions here are adapters between those values and the
;;;; <harmony> element; the rules below are the XML side only.
;;;;
;;;; HARMONY-TO-CHORD-SYMBOL element → a CHORD-SYMBOL. ELEMENT is an xml-protocol
;;;; XML-ELEMENT named "harmony"; its children follow the "harmony", "root",
;;;; "bass" and "degree" rows of +ELEMENT-CONTEXTS+ (tables.lisp). Text values are
;;;; trimmed. In order:
;;;;   1. <numeral> or <function> (a Roman-numeral or functional harmony):
;;;;      unsupported, ELEMENT "harmony". <inversion>: unsupported, ELEMENT
;;;;      "inversion" (skipping it reads the chord in root position).
;;;;   2. KIND, the text of <kind>: a harmony without one is a SCORE-FORMAT-ERROR.
;;;;      The attributes of <kind> (text, use-symbols, stack-degrees,
;;;;      parentheses-degrees, bracket-degrees, halign) and the text attributes of
;;;;      <root-step> and <bass-step> are display and are ignored: MusicXML
;;;;      carries the chord, not how it was spelled. For "none" the root, bass
;;;;      and degrees are ignored too.
;;;;   3. ROOT from <root>: <root-step> a letter A-G (else SCORE-FORMAT-ERROR) and
;;;;      <root-alter>, absent = 0, a decimal number that must be an integer in
;;;;      -2..2 (else unsupported, ELEMENT "harmony"), as a music-theory
;;;;      PITCH-CLASS-NAME. BASS likewise from <bass> (<bass-step>, <bass-alter>),
;;;;      when present. A harmony with no <root> and a kind other than "none" and
;;;;      "other" is a SCORE-FORMAT-ERROR.
;;;;   4. DEGREES, the <degree> elements in document order, each (type value
;;;;      alter): <degree-type> "add", "alter" or "subtract" as :ADD, :ALTER,
;;;;      :SUBTRACT; <degree-value> a positive integer; <degree-alter> an integer
;;;;      (a decimal number that is one). Anything else is unsupported, ELEMENT
;;;;      "harmony". The print-object and text attributes are display.
;;;;   5. The symbol: (musicxml-kind-chord-symbol kind root :bass bass :degrees
;;;;      degrees). NIL ("other", a chord spelled by its degrees alone) is
;;;;      unsupported, ELEMENT "harmony". A MUSIC-THEORY-ERROR (a kind outside
;;;;      MusicXML 4.0, a degree the kind doesn't admit, such as (:add 7 0)) makes
;;;;      the harmony unsupported, ELEMENT "harmony", with that error as CAUSE.
;;;;      The value has TEXT and DIALECT NIL.
;;;; Kind "dominant" with (add 9 -1) on D is D7(b9); "major" with (subtract 3 0)
;;;; (add 4 0) and bass E on A is Asus4/E; in the other order, (add 4 0)
;;;; (subtract 3 0) is A(add4,omit3)/E.
;;;; Unsupported here means MUSICXML-UNSUPPORTED signalled as the reader does
;;;; (reader.lisp, "Unsupported"): with ELEMENT as stated, POSITION the path of
;;;; that element when the call comes from the reader, else NIL, inside a
;;;; SKIP-ELEMENT restart. When ELEMENT is "harmony", HARMONY-TO-CHORD-SYMBOL
;;;; returns NIL after SKIP-ELEMENT.
;;;;
;;;; CHORD-SYMBOL-TO-HARMONY symbol &key id → (values element lost). With (kind
;;;; degrees) = (chord-symbol-musicxml-kind symbol), ELEMENT is a fresh
;;;; XML-ELEMENT
;;;;   <harmony id=ID>
;;;;     <root><root-step>L</root-step>[<root-alter>a</root-alter>]</root>
;;;;     <kind>KIND</kind>
;;;;     [<bass><bass-step>L</bass-step>[<bass-alter>a</bass-alter>]</bass>]
;;;;     <degree><degree-value>v</degree-value><degree-alter>a</degree-alter>
;;;;       <degree-type>add|alter|subtract</degree-type></degree>   per degree
;;;;   </harmony>
;;;; with the id attribute only when ID is given, root-alter and bass-alter only
;;;; when not 0, <degree-alter> always ("0" too), integers printed with ~D. N.C.
;;;; ("none") writes the root C, which MusicXML 4.0 requires. No display
;;;; attributes are written. LOST is ("chord-symbol text") when the symbol's
;;;; TEXT or DIALECT isn't NIL (MusicXML can't carry them), else (). SYMBOL must
;;;; be well-formed (MT3 W1-W5), else MUSIC-THEORY-ERROR as
;;;; CHORD-SYMBOL-MUSICXML-KIND signals. For every well-formed symbol c,
;;;; (harmony-to-chord-symbol (chord-symbol-to-harmony c)) is EQUALP to c with
;;;; TEXT and DIALECT NIL.

(in-package #:score-backend-musicxml)

;;; Reading ----------------------------------------------------------------------

(defun harmony-to-chord-symbol (element)
  "The CHORD-SYMBOL of the <harmony> ELEMENT (file header)."
  (check-type element xml-protocol:xml-element)
  (%harmony-symbol (%loc element)))

(defun %harmony-pitch-class (harmony loc prefix)
  "The PITCH-CLASS-NAME of the located <root> or <bass> LOC (PREFIX \"root\" or
\"bass\") of the <harmony> HARMONY (rule 3), or NIL when its alter is
unsupported."
  (let* ((kids (%walk loc))
         (step (%kid kids (concatenate 'string prefix "-step")))
         (alter (%kid kids (concatenate 'string prefix "-alter")))
         (letter (and step (%step-letter (%text step))))
         (value (if alter (%parse-decimal (%text alter)) 0)))
    (unless letter
      (%format-error harmony (format nil "<~A-step> is not a letter A-G" prefix)))
    (and (integerp value) (<= -2 value 2)
         (music-theory:make-pitch-class-name :letter letter :alter value))))

(defun %harmony-degree (loc)
  "The music-theory degree (type value alter) of the located <degree> LOC (rule
4), or NIL when it is unsupported."
  (let* ((kids (%walk loc))
         (value (let ((kid (%kid kids "degree-value"))) (and kid (%parse-decimal (%text kid)))))
         (alter (let ((kid (%kid kids "degree-alter"))) (and kid (%parse-decimal (%text kid)))))
         (type (let ((kid (%kid kids "degree-type")))
                 (and kid (find (%text kid) '(:add :alter :subtract) :test #'string-equal)))))
    (and type (typep value '(integer 1)) (integerp alter)
         (list type value alter))))

(defun %harmony-symbol (loc)
  "The CHORD-SYMBOL of the located <harmony> LOC (file header, rules 1-5), or
NIL when the harmony is dropped as unsupported."
  (let ((poison (%poison loc)))
    (when poison
      (return-from %harmony-symbol
        (%unsupported "harmony" loc (format nil "<~A> harmony is outside the model" (%name poison))))))
  (flet ((drop (reason &optional cause)
           (return-from %harmony-symbol (%unsupported "harmony" loc reason cause))))
    (let* ((kids (%walk loc))
           (kind-loc (or (%kid kids "kind") (%format-error loc "a <harmony> without <kind>")))
           (kind (%text kind-loc)))
      (if (string= kind "none")
          (music-theory:musicxml-kind-chord-symbol kind nil)
          (let* ((root-loc (%kid kids "root"))
                 (root (cond (root-loc (or (%harmony-pitch-class loc root-loc "root")
                                           (drop "a root alter that isn't an integer -2..2")))
                             ((string/= kind "other")
                              (%format-error loc "a <harmony> without <root>"))))
                 (bass-loc (%kid kids "bass"))
                 (bass (and bass-loc (or (%harmony-pitch-class loc bass-loc "bass")
                                         (drop "a bass alter that isn't an integer -2..2"))))
                 (degrees (loop for degree in (%kids kids "degree")
                                collect (or (%harmony-degree degree)
                                            (drop "a <degree> outside the model"))))
                 (symbol (handler-case (music-theory:musicxml-kind-chord-symbol
                                        kind root :bass bass :degrees degrees)
                           (music-theory:music-theory-error (condition)
                             (drop "a chord music-theory can't hold" condition)))))
            (or symbol (drop "a chord spelled by its degrees alone (kind other)")))))))

;;; Writing ------------------------------------------------------------------------

(defun %harmony-step-element (prefix pitch-class)
  "<root> or <bass> (PREFIX) for PITCH-CLASS: the step, and the alter unless 0."
  (let ((alter (music-theory:pitch-class-name-alter pitch-class)))
    (%el prefix nil
         (%el (concatenate 'string prefix "-step") nil
              (string (char +steps+ (music-theory:pitch-class-name-letter pitch-class))))
         (and (/= alter 0)
              (%el (concatenate 'string prefix "-alter") nil (format nil "~D" alter))))))

(defun chord-symbol-to-harmony (symbol &key id)
  "(values <harmony> element, lost descriptions) for SYMBOL (file header)."
  (check-type symbol music-theory:chord-symbol)
  (check-type id (or null string))
  (multiple-value-bind (kind degrees) (music-theory:chord-symbol-musicxml-kind symbol)
    (let ((root (or (music-theory:chord-symbol-root symbol)     ; N.C.: MusicXML needs a root
                    (music-theory:make-pitch-class-name :letter 0)))
          (bass (music-theory:chord-symbol-bass symbol)))
      (values (%el "harmony" (list (cons "id" id))
                   (%harmony-step-element "root" root)
                   (%el "kind" nil kind)
                   (and bass (%harmony-step-element "bass" bass))
                   (loop for (type value alter) in degrees
                         collect (%el "degree" nil
                                      (%el "degree-value" nil (format nil "~D" value))
                                      (%el "degree-alter" nil (format nil "~D" alter))
                                      (%el "degree-type" nil (string-downcase (symbol-name type))))))
              (and (or (music-theory:chord-symbol-text symbol)
                       (music-theory:chord-symbol-dialect symbol))
                   (list "chord-symbol text"))))))
