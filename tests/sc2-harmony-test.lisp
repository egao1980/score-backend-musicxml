;;;; SC2 <harmony> ↔ chord symbol (src/harmony.lisp), adapters over
;;;; music-theory's MusicXML kind mapping. Expected symbols are MT3 readings of
;;;; lead-sheet text (music-theory's PARSE-CHORD-SYMBOL, :POP).

(in-package #:score-backend-musicxml/tests)

(defun hx (root-step root-alter kind &key degrees bass id (kind-attrs ""))
  "A <harmony> element: ROOT-STEP and ROOT-ALTER, KIND, DEGREES as (value alter
type), BASS as (step alter)."
  (with-output-to-string (s)
    (format s "<harmony~@[ id=~S~]>" id)
    (when root-step
      (format s "<root><root-step>~A</root-step>~:[~;<root-alter>~A</root-alter>~]</root>"
              root-step (and root-alter (not (eql root-alter 0))) root-alter))
    (when kind (format s "<kind~A>~A</kind>" kind-attrs kind))
    (when bass
      (format s "<bass><bass-step>~A</bass-step>~:[~;<bass-alter>~A</bass-alter>~]</bass>"
              (first bass) (and (second bass) (/= (second bass) 0)) (second bass)))
    (loop for (value alter type) in degrees
          do (format s "<degree><degree-value>~A</degree-value><degree-alter>~A</degree-alter>~
<degree-type>~A</degree-type></degree>" value alter type))
    (format s "</harmony>")))

(defun harmony-element (xml)
  (xml-protocol:document-root-element (xml-protocol:decode xml)))

(defun read-harmony (xml)
  (harmony-to-chord-symbol (harmony-element xml)))

(defun compact-xml (element)
  (xml-protocol:encode element :pretty nil :declaration nil))

;;; Reading -------------------------------------------------------------------------

(deftest-parametrize harmony-kinds-read
    ((kind text)
     ("major" "Bb") ("minor" "Bbm") ("augmented" "Bb+") ("diminished" "Bbm(b5)")
     ("dominant" "Bb7") ("major-seventh" "Bbmaj7") ("minor-seventh" "Bbm7")
     ("diminished-seventh" "Bbdim7") ("augmented-seventh" "Bb+7")
     ("half-diminished" "Bbm7(b5)") ("major-minor" "Bbmmaj7") ("major-sixth" "Bb6")
     ("minor-sixth" "Bbm6") ("dominant-ninth" "Bb9") ("major-ninth" "Bbmaj9")
     ("minor-ninth" "Bbm9") ("dominant-11th" "Bb11") ("major-11th" "Bbmaj11")
     ("minor-11th" "Bbm11") ("dominant-13th" "Bb13") ("major-13th" "Bbmaj13")
     ("minor-13th" "Bbm13") ("suspended-second" "Bbsus2") ("suspended-fourth" "Bbsus4")
     ("Neapolitan" "Bb") ("Italian" "Bb5(add#4,addb6,omit5)")
     ("French" "Bb5(add2,add#4,addb6,omit5)") ("German" "Bbm(add#4,addb6,omit5)")
     ("pedal" "Bb5(omit5)") ("power" "Bb5") ("Tristan" "Bb5(#9,add#4,add#6,omit5)"))
  (testing (format nil "kind ~A on B flat reads as ~A" kind text)
    (ok (equalp (read-harmony (hx "B" -1 kind)) (cs text)))))

(deftest-parametrize harmony-degrees-read
    ((root alter kind degrees bass text)
     ("C" 0 "major" () nil "C")
     ("F" 1 "minor-seventh" () nil "F#m7")
     ("D" 0 "dominant" '((9 -1 "add")) nil "D7(b9)")
     ("C" 0 "dominant" '((5 -1 "alter")) nil "C7(b5)")
     ("C" 0 "dominant-13th" '((11 1 "alter")) nil "C13(#11)")
     ("C" 0 "dominant-ninth" '((9 -1 "alter")) nil "C9(b9)")
     ("C" 0 "major" '((9 0 "add")) nil "Cadd9")
     ("C" 0 "minor" '((9 0 "add")) nil "Cm(add9)")
     ("C" 0 "dominant" '((5 0 "subtract")) nil "C7(omit5)")
     ("C" 0 "major" '((3 0 "subtract")) nil "C(omit3)")
     ("C" 0 "major-sixth" '((9 0 "add")) nil "C6/9")
     ("C" 0 "dominant" '((3 0 "subtract") (4 0 "add")) nil "C7sus4")
     ("C" 0 "dominant" '((4 0 "add") (3 0 "subtract")) nil "C7(add4,omit3)")
     ("C" 0 "dominant-ninth" '((3 0 "subtract") (4 0 "add")) nil "C9sus4")
     ("A" 0 "major" '((3 0 "subtract") (4 0 "add")) '("E" 0) "Asus4/E")
     ("C" 0 "major" '((3 0 "subtract") (2 0 "add")) nil "Csus2")
     ("C" 0 "minor" '((3 0 "subtract") (4 0 "add")) nil "Cm(add4,omit3)")
     ("C" 0 "major-seventh" '((5 1 "alter")) nil "C+maj7")
     ("C" 0 "minor-ninth" '((7 1 "alter")) nil "Cm(maj9)")
     ("C" 0 "minor-ninth" '((5 -1 "alter")) nil "Cø9")
     ("C" 0 "minor-seventh" '((5 -1 "alter")) nil "Cm7(b5)")
     ("F" 0 "major" () '("A" 0) "F/A")
     ("E" -1 "major" () '("B" -1) "Eb/Bb")
     ("F" 1 "minor-seventh" () '("C" 1) "F#m7/C#")
     ("C" 0 "dominant" '((9 -1 "add") (9 1 "add") (11 1 "add") (13 -1 "add") (5 0 "subtract")) nil
      "C7alt")
     ("C" 0 "Neapolitan" () nil "C"))
  (testing (format nil "~A ~A with ~S reads as ~A" root kind degrees text)
    (ok (equalp (read-harmony (hx root alter kind :degrees degrees :bass bass)) (cs text)))))

(deftest harmony-special-cases-read
  (testing "kind none is N.C., whatever else the element holds"
    (ok (equalp (read-harmony (hx "C" 0 "none")) (make-chord-symbol :no-chord-p t)))
    (ok (equalp (read-harmony (hx "G" 0 "none" :bass '("B" 0))) (make-chord-symbol :no-chord-p t))))
  (testing "display text attributes are ignored: TEXT and DIALECT are NIL"
    (let ((c (read-harmony (hx "C" 0 "minor-seventh" :kind-attrs " text=\"-7\" use-symbols=\"no\""))))
      (ok (equalp c (cs "Cm7")))
      (ok (null (chord-symbol-text c)))
      (ok (null (chord-symbol-dialect c)))))
  (testing "whitespace around values is trimmed"
    (ok (equalp (read-harmony "<harmony><root><root-step> G </root-step></root><kind>
 dominant </kind></harmony>")
                (cs "G7"))))
  (testing "a decimal integer alter reads as that integer"
    (ok (equalp (read-harmony (hx "B" "-1.0" "major")) (cs "Bb")))))

(deftest-parametrize harmony-unsupported
    ((xml element skipped)
     ("<harmony><root><root-step>C</root-step></root><kind>other</kind><degree><degree-value>9</degree-value><degree-alter>0</degree-alter><degree-type>add</degree-type></degree></harmony>"
      "harmony" nil)
     ("<harmony><numeral><numeral-root>5</numeral-root></numeral><kind>dominant</kind></harmony>"
      "harmony" nil)
     ("<harmony><function>V</function><kind>dominant</kind></harmony>" "harmony" nil)
     ("<harmony><root><root-step>C</root-step></root><kind>major</kind><inversion>1</inversion></harmony>"
      "inversion" "C")
     ("<harmony><root><root-step>C</root-step><root-alter>0.5</root-alter></root><kind>major</kind></harmony>"
      "harmony" nil)
     ("<harmony><root><root-step>C</root-step><root-alter>3</root-alter></root><kind>major</kind></harmony>"
      "harmony" nil)
     ("<harmony><root><root-step>C</root-step></root><kind>majestic</kind></harmony>" "harmony" nil)
     ("<harmony><root><root-step>C</root-step></root><kind>dominant</kind><degree><degree-value>5</degree-value><degree-alter>0</degree-alter><degree-type>alter</degree-type></degree></harmony>"
      "harmony" nil)
     ("<harmony><root><root-step>C</root-step></root><kind>dominant</kind><degree><degree-value>9</degree-value><degree-alter>-2</degree-alter><degree-type>add</degree-type></degree></harmony>"
      "harmony" nil)
     ("<harmony><root><root-step>C</root-step></root><kind>dominant</kind><degree><degree-value>9</degree-value><degree-alter>0</degree-alter><degree-type>replace</degree-type></degree></harmony>"
      "harmony" nil)
     ("<harmony><root><root-step>G</root-step></root><kind>suspended-fourth</kind><degree><degree-value>7</degree-value><degree-alter>0</degree-alter><degree-type>add</degree-type></degree></harmony>"
      "harmony" nil))
  (testing (format nil "~A is unsupported (ELEMENT ~S)" xml element)
    (let ((c (signalled (lambda () (read-harmony xml)) 'musicxml-unsupported)))
      (ok (typep c 'musicxml-unsupported))
      (ok (equal element (and c (musicxml-unsupported-element c))))
      (ok (eq :musicxml (and c (score-format-error-format c))))
      (ok (and c (null (score-format-error-position c)))))
    (testing "SKIP-ELEMENT drops it"
      (let ((result (handler-bind ((musicxml-unsupported #'skip-element)) (read-harmony xml))))
        (ok (equalp result (and skipped (cs skipped))))))))

(deftest harmony-unsupported-cause
  (testing "a degree music-theory refuses is unsupported, with its error as CAUSE"
    (let ((c (signalled (lambda ()
                          (read-harmony (hx "C" 0 "dominant" :degrees '((7 0 "add")))))
                        'musicxml-unsupported)))
      (ok (equal "harmony" (and c (musicxml-unsupported-element c))))
      (ok (typep (and c (score-format-error-cause c)) 'music-theory-error)))))

(deftest harmony-format-errors
  (testing "a harmony without a kind is a score-format-error"
    (let ((c (signalled (lambda () (read-harmony (hx "C" 0 nil))) 'score-format-error)))
      (ok (typep c 'score-format-error))
      (ok (and c (not (typep c 'musicxml-unsupported))))))
  (testing "a root step outside A-G is a score-format-error"
    (ok (signalled (lambda () (read-harmony (hx "H" 0 "major"))) 'score-format-error)))
  (testing "a harmony without a root is a score-format-error unless its kind is none"
    (ok (signalled (lambda () (read-harmony (hx nil 0 "major"))) 'score-format-error))
    (ok (equalp (read-harmony (hx nil 0 "none")) (make-chord-symbol :no-chord-p t)))))

;;; Writing -------------------------------------------------------------------------

(deftest-parametrize chord-symbols-write
    ((text xml lost)
     ("C" "<harmony><root><root-step>C</root-step></root><kind>major</kind></harmony>" ())
     ("C7" "<harmony><root><root-step>C</root-step></root><kind>dominant</kind></harmony>" ())
     ("F#m7" "<harmony><root><root-step>F</root-step><root-alter>1</root-alter></root><kind>minor-seventh</kind></harmony>" ())
     ("Bb/D" "<harmony><root><root-step>B</root-step><root-alter>-1</root-alter></root><kind>major</kind><bass><bass-step>D</bass-step></bass></harmony>" ())
     ("Eb/Bb" "<harmony><root><root-step>E</root-step><root-alter>-1</root-alter></root><kind>major</kind><bass><bass-step>B</bass-step><bass-alter>-1</bass-alter></bass></harmony>" ())
     ("C7(b9)" "<harmony><root><root-step>C</root-step></root><kind>dominant</kind><degree><degree-value>9</degree-value><degree-alter>-1</degree-alter><degree-type>add</degree-type></degree></harmony>" ())
     ("C7(#9)" "<harmony><root><root-step>C</root-step></root><kind>dominant</kind><degree><degree-value>9</degree-value><degree-alter>1</degree-alter><degree-type>add</degree-type></degree></harmony>" ())
     ("C7(b5)" "<harmony><root><root-step>C</root-step></root><kind>dominant</kind><degree><degree-value>5</degree-value><degree-alter>-1</degree-alter><degree-type>alter</degree-type></degree></harmony>" ())
     ("C13(#11)" "<harmony><root><root-step>C</root-step></root><kind>dominant-13th</kind><degree><degree-value>11</degree-value><degree-alter>1</degree-alter><degree-type>alter</degree-type></degree></harmony>" ())
     ("C9(#11)" "<harmony><root><root-step>C</root-step></root><kind>dominant-ninth</kind><degree><degree-value>11</degree-value><degree-alter>1</degree-alter><degree-type>add</degree-type></degree></harmony>" ())
     ("C9" "<harmony><root><root-step>C</root-step></root><kind>dominant-ninth</kind></harmony>" ())
     ("Csus4" "<harmony><root><root-step>C</root-step></root><kind>suspended-fourth</kind></harmony>" ())
     ("C7sus4" "<harmony><root><root-step>C</root-step></root><kind>dominant</kind><degree><degree-value>3</degree-value><degree-alter>0</degree-alter><degree-type>subtract</degree-type></degree><degree><degree-value>4</degree-value><degree-alter>0</degree-alter><degree-type>add</degree-type></degree></harmony>" ())
     ("C9sus4" "<harmony><root><root-step>C</root-step></root><kind>dominant-ninth</kind><degree><degree-value>3</degree-value><degree-alter>0</degree-alter><degree-type>subtract</degree-type></degree><degree><degree-value>4</degree-value><degree-alter>0</degree-alter><degree-type>add</degree-type></degree></harmony>" ())
     ("C(add4,omit3)" "<harmony><root><root-step>C</root-step></root><kind>major</kind><degree><degree-value>4</degree-value><degree-alter>0</degree-alter><degree-type>add</degree-type></degree><degree><degree-value>3</degree-value><degree-alter>0</degree-alter><degree-type>subtract</degree-type></degree></harmony>" ())
     ("C+maj7" "<harmony><root><root-step>C</root-step></root><kind>major-seventh</kind><degree><degree-value>5</degree-value><degree-alter>1</degree-alter><degree-type>alter</degree-type></degree></harmony>" ())
     ("C6/9" "<harmony><root><root-step>C</root-step></root><kind>major-sixth</kind><degree><degree-value>9</degree-value><degree-alter>0</degree-alter><degree-type>add</degree-type></degree></harmony>" ())
     ("C7alt" "<harmony><root><root-step>C</root-step></root><kind>dominant</kind><degree><degree-value>9</degree-value><degree-alter>-1</degree-alter><degree-type>add</degree-type></degree><degree><degree-value>9</degree-value><degree-alter>1</degree-alter><degree-type>add</degree-type></degree><degree><degree-value>11</degree-value><degree-alter>1</degree-alter><degree-type>add</degree-type></degree><degree><degree-value>13</degree-value><degree-alter>-1</degree-alter><degree-type>add</degree-type></degree><degree><degree-value>5</degree-value><degree-alter>0</degree-alter><degree-type>subtract</degree-type></degree></harmony>" ())
     ("Cm7(b5)" "<harmony><root><root-step>C</root-step></root><kind>half-diminished</kind></harmony>" ())
     ("Cm(b5)" "<harmony><root><root-step>C</root-step></root><kind>diminished</kind></harmony>" ())
     ("C5(add#4,addb6,omit5)" "<harmony><root><root-step>C</root-step></root><kind>power</kind><degree><degree-value>4</degree-value><degree-alter>1</degree-alter><degree-type>add</degree-type></degree><degree><degree-value>6</degree-value><degree-alter>-1</degree-alter><degree-type>add</degree-type></degree><degree><degree-value>5</degree-value><degree-alter>0</degree-alter><degree-type>subtract</degree-type></degree></harmony>" ())
     ("C5(omit5)" "<harmony><root><root-step>C</root-step></root><kind>power</kind><degree><degree-value>5</degree-value><degree-alter>0</degree-alter><degree-type>subtract</degree-type></degree></harmony>" ())
     ("Cadd9" "<harmony><root><root-step>C</root-step></root><kind>major</kind><degree><degree-value>9</degree-value><degree-alter>0</degree-alter><degree-type>add</degree-type></degree></harmony>" ())
     ("C7(omit3)" "<harmony><root><root-step>C</root-step></root><kind>dominant</kind><degree><degree-value>3</degree-value><degree-alter>0</degree-alter><degree-type>subtract</degree-type></degree></harmony>" ())
     ("N.C." "<harmony><root><root-step>C</root-step></root><kind>none</kind></harmony>" ())
     ("Cm(maj9)" "<harmony><root><root-step>C</root-step></root><kind>minor-ninth</kind><degree><degree-value>7</degree-value><degree-alter>1</degree-alter><degree-type>alter</degree-type></degree></harmony>" ())
     ("Cø9" "<harmony><root><root-step>C</root-step></root><kind>minor-ninth</kind><degree><degree-value>5</degree-value><degree-alter>-1</degree-alter><degree-type>alter</degree-type></degree></harmony>" ()))
  (testing (format nil "~A writes as ~A" text xml)
    (multiple-value-bind (element lost-now) (chord-symbol-to-harmony (cs text))
      (ok (equal xml (compact-xml element)))
      (ok (equal lost lost-now)))))

(deftest chord-symbol-write-details
  (testing ":ID becomes the id attribute"
    (ok (equal "<harmony id=\"h-1\"><root><root-step>G</root-step></root><kind>major</kind></harmony>"
               (compact-xml (chord-symbol-to-harmony (cs "G") :id "h-1")))))
  (testing "TEXT or DIALECT is lost"
    (ok (equal '("chord-symbol text")
               (nth-value 1 (chord-symbol-to-harmony (parse-chord-symbol "C7" :dialect :jazz)))))
    (ok (equal '("chord-symbol text")
               (nth-value 1 (chord-symbol-to-harmony (parse-chord-symbol "Cm(maj9)"))))))
  (testing "a symbol that isn't well-formed is a music-theory-error"
    (ok (signalled (lambda () (chord-symbol-to-harmony (make-chord-symbol :root (parse-pitch-class "C"))))
                   'music-theory-error))))

(deftest-parametrize chord-symbols-round-trip
    ((text)
     ("C") ("Cm") ("C+") ("Cm(b5)") ("C7") ("Cmaj7") ("Cm7") ("Cdim7") ("C+7") ("Cm7(b5)")
     ("Cmmaj7") ("C6") ("Cm6") ("C9") ("Cmaj9") ("Cm9") ("C11") ("Cmaj11") ("Cm11") ("C13")
     ("Cmaj13") ("Cm13") ("Csus2") ("Csus4") ("C7sus4") ("C9sus4") ("C5") ("C5(omit5)")
     ("C+maj7") ("C7(b9)") ("C7(#9)") ("C7(#11)") ("C7(b13)") ("C7(b5)") ("C7(b9,#9)")
     ("C13(#11)") ("C9(#11)") ("C9(b9)") ("Cadd9") ("Cm(add9)") ("C6/9") ("Cm6/9") ("C7alt")
     ("C(add2)") ("C7(omit3)") ("C(omit3)") ("C(b5)") ("C(b9)") ("F#m7/C#") ("Bb7(b9)/D")
     ("Ebmaj7/G") ("Asus4/E") ("Gmaj7sus4") ("C5(add2,add#4,addb6,omit5)")
     ("Cm(add#4,addb6,omit5)") ("C5(#9,add#4,add#6,omit5)") ("N.C.") ("Cm(maj9)") ("Cø9") ("Cdim9")
     ("C+9") ("C(add4,omit3)") ("C7(add4,omit3)"))
  (testing (format nil "~A survives <harmony>" text)
    (ok (equalp (harmony-to-chord-symbol (chord-symbol-to-harmony (cs text))) (cs text)))))
