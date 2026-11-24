;;;; SC2 chord symbols as MusicXML <harmony>, both directions.
;;;;
;;;; The bridge is MT3's normal form: every MusicXML 4.0 <kind> has a canonical
;;;; :POP text on the root C (+HARMONY-KINDS+, a copy of music-theory's MusicXML
;;;; kind table; tests/sc2-harmony-test.lisp checks the copy against it). The
;;;; reader turns a <harmony> into lead-sheet text and lets
;;;; MUSIC-THEORY:PARSE-CHORD-SYMBOL normalise it (rules R1-R6, the fifth fold,
;;;; sorting), so a symbol read from MusicXML is a value the MT3 grammar also
;;;; produces. The writer picks the kind whose canonical value covers most of the
;;;; symbol and writes the rest as <degree> elements.
;;;;
;;;; HARMONY-TO-CHORD-SYMBOL element → a CHORD-SYMBOL. ELEMENT is an xml-protocol
;;;; XML-ELEMENT named "harmony"; its children follow the "harmony", "root",
;;;; "bass" and "degree" rows of +ELEMENT-CONTEXTS+ (tables.lisp). Text values are
;;;; trimmed. In order:
;;;;   1. <numeral> or <function> (a Roman-numeral or functional harmony):
;;;;      unsupported, ELEMENT "harmony". <inversion>: unsupported, ELEMENT
;;;;      "inversion" (skipping it reads the chord in root position).
;;;;   2. KIND, the text of <kind>: a harmony without one is a SCORE-FORMAT-ERROR.
;;;;      Its +HARMONY-KINDS+ row gives the canonical text T. A kind outside the
;;;;      table, and "other" (T NIL), are unsupported, ELEMENT "harmony". "none" is
;;;;      N.C., (make-chord-symbol :no-chord-p t); nothing else is read.
;;;;   3. ROOT from <root>: <root-step> a letter A-G (else SCORE-FORMAT-ERROR) and
;;;;      <root-alter>, absent = 0, a decimal number that must be an integer in
;;;;      -2..2 (else unsupported, ELEMENT "harmony"). BASS likewise from <bass>
;;;;      (<bass-step>, <bass-alter>), when present. A harmony with no <root> but
;;;;      a kind other than "none" is a SCORE-FORMAT-ERROR.
;;;;   4. DEGREES, the <degree> elements in document order, each (type value
;;;;      alter): <degree-type> "add", "alter" or "subtract", <degree-value> a
;;;;      positive integer, <degree-alter> an integer (a decimal number that is
;;;;      one). Anything else is unsupported, ELEMENT "harmony".
;;;;   5. The text. T is "C" followed by a WORD and, when T has "(", a GROUP:
;;;;      WORD is the part before "(" and the group items are the comma-separated
;;;;      items between "(" and the final ")". Then, consuming degrees:
;;;;        R-SUS7  on the kinds "suspended-second" and "suspended-fourth", the
;;;;                first degree (add 7 a) with a = 0 makes WORD "7" + WORD, with
;;;;                a = 1 "maj7" + WORD (C7sus4, Cmaj7sus4: MusicXML's add 7 is a
;;;;                minor seventh, relative to the dominant chord).
;;;;        R-SUS   when the kind's canonical value has no SUSPENSION and its
;;;;                QUALITY is :MAJOR, :AUGMENTED, :DOMINANT-7, :MAJOR-7,
;;;;                :AUGMENTED-7 or :MAJOR-6, the first (subtract 3 0) together
;;;;                with the first (add 4 0), else the first (add 2 0), append
;;;;                "sus4" (or "sus2") to WORD.
;;;;      Every other degree, in order, appends an item to the group:
;;;;        (add d a)       "add" + ACC(a) + d
;;;;        (alter d a)     ACC(a) + d; a = 0 is unsupported (ELEMENT "harmony")
;;;;        (subtract d a)  "omit" + d
;;;;      ACC is "b" for -1, "" for 0, "#" for 1; any other alter is unsupported
;;;;      (ELEMENT "harmony"). The text is ROOT (PITCH-CLASS-STRING) + WORD, then
;;;;      "(" + the items joined by "," + ")" when there are items, then "/" +
;;;;      BASS when there is a bass. Kind "dominant" with (add 9 -1) on D is
;;;;      "D7(addb9)"; "suspended-fourth" with (add 7 0) on G is "G7sus4"; "major"
;;;;      with (subtract 3 0) (add 4 0) and bass E on A is "Asus4/E".
;;;;   6. The symbol: (parse-chord-symbol text :dialect :pop), rebuilt with TEXT
;;;;      and DIALECT NIL (MusicXML carries the chord, not how it was spelled; the
;;;;      text attributes of <kind>, <root-step> and <bass-step> are display
;;;;      text and are ignored). A CHORD-SYMBOL-PARSE-ERROR (a combination MT3
;;;;      rejects, such as an alteration of an omitted degree) makes the harmony
;;;;      unsupported, ELEMENT "harmony", with the parse error as CAUSE.
;;;; Unsupported here means MUSICXML-UNSUPPORTED signalled as the reader does
;;;; (reader.lisp, "Unsupported"): with ELEMENT as stated, POSITION the path of
;;;; that element when the call comes from the reader, else NIL, inside a
;;;; SKIP-ELEMENT restart. When ELEMENT is "harmony", HARMONY-TO-CHORD-SYMBOL
;;;; returns NIL after SKIP-ELEMENT.
;;;;
;;;; CHORD-SYMBOL-TO-HARMONY symbol &key id → (values element lost). ELEMENT is a
;;;; fresh XML-ELEMENT "harmony" with an id attribute when ID is given; LOST is a
;;;; list of the descriptions of what MusicXML can't carry, in this order, each
;;;; at most once: "chord-symbol text" when the symbol's TEXT or DIALECT isn't
;;;; NIL; "chord-symbol kind" when step 3 below was needed. SYMBOL must be
;;;; well-formed (MT3 W1-W5), else MUSIC-THEORY-ERROR as PRINT-CHORD-SYMBOL. N.C.
;;;; is <root><root-step>C</root-step></root><kind>none</kind> (MusicXML 4.0
;;;; requires a root). Otherwise, with B_K the canonical value of kind K (T
;;;; parsed in :POP) and Q, X, S, A, D, O the symbol's QUALITY, EXTENSIONS,
;;;; SUSPENSION, ALTERATIONS, ADDED and OMITTED:
;;;;   0. :AUGMENTED-MAJOR-7 has no kind: Q := :MAJOR-7 and (5 . 1) joins A.
;;;;   1. The candidates are the kinds with QUALITY Q, EXTENSIONS X and
;;;;      SUSPENSION S whose ALTERATIONS, ADDED and OMITTED are subsets of A, D
;;;;      and O. The kind is the candidate with the most of those three
;;;;      together, the first in +HARMONY-KINDS+ order on ties (so C is "major",
;;;;      not "Neapolitan").
;;;;   2. No candidate and S not NIL: candidates as in 1 with SUSPENSION NIL; the
;;;;      suspension is written as the degrees (add S 0) (subtract 3 0).
;;;;   3. Still none: candidates as in 1 (then 2) with EXTENSIONS (); each
;;;;      extension e is written as (add e 0), first. MusicXML has no ninth to
;;;;      thirteenth kinds for these qualities, and reads the added degrees back
;;;;      as ADDED: the symbol is lost ("chord-symbol kind").
;;;; The <degree>s, in this order: the extensions of step 3, the suspension of
;;;; step 2, then the symbol's tones the kind lacks: each alteration (d . a) not
;;;; in B_K as (alter d a) when d is a degree of B_K's CHORD-TONES, else (add d
;;;; a); each added tone (d . a) not in B_K as (add d a); each omitted degree d
;;;; not in B_K as (subtract d 0); each group sorted as in the symbol. Every
;;;; <degree> holds <degree-value>, <degree-alter> (always, "0" too) and
;;;; <degree-type>. The element:
;;;;   <harmony id=ID>
;;;;     <root><root-step>L</root-step>[<root-alter>a</root-alter>]</root>
;;;;     <kind>KIND</kind>
;;;;     [<bass><bass-step>L</bass-step>[<bass-alter>a</bass-alter>]</bass>]
;;;;     [<degree>...</degree>]...
;;;;   </harmony>
;;;; with root-alter and bass-alter only when not 0, integers printed with ~D.
;;;; For every well-formed symbol c that is not lost,
;;;; (harmony-to-chord-symbol (chord-symbol-to-harmony c)) is EQUALP to c with
;;;; TEXT and DIALECT NIL: C7 is "dominant"; C7(b9) "dominant" + (add 9 -1);
;;;; C13(#11) "dominant-13th" + (alter 11 1); C7sus4 "dominant" + (add 4 0)
;;;; (subtract 3 0); C+M7 "major-seventh" + (alter 5 1); C6/9 "major-sixth" +
;;;; (add 9 0); F/A "major" with bass A.

(in-package #:score-backend-musicxml)

(defparameter +harmony-kinds+
  '(("major" "C") ("minor" "Cm") ("augmented" "C+") ("diminished" "Cm(b5)")
    ("dominant" "C7") ("major-seventh" "Cmaj7") ("minor-seventh" "Cm7")
    ("diminished-seventh" "Cdim7") ("augmented-seventh" "C+7")
    ("half-diminished" "Cm7(b5)") ("major-minor" "Cmmaj7")
    ("major-sixth" "C6") ("minor-sixth" "Cm6")
    ("dominant-ninth" "C9") ("major-ninth" "Cmaj9") ("minor-ninth" "Cm9")
    ("dominant-11th" "C11") ("major-11th" "Cmaj11") ("minor-11th" "Cm11")
    ("dominant-13th" "C13") ("major-13th" "Cmaj13") ("minor-13th" "Cm13")
    ("suspended-second" "Csus2") ("suspended-fourth" "Csus4")
    ("Neapolitan" "C")
    ("Italian" "C5(add#4,addb6,omit5)")
    ("French" "C5(add2,add#4,addb6,omit5)")
    ("German" "Cm(add#4,addb6,omit5)")
    ("pedal" "C5(omit5)") ("power" "C5")
    ("Tristan" "C5(#9,add#4,add#6,omit5)")
    ("other" nil) ("none" "N.C."))
  "(kind canonical-text): every MusicXML 4.0 <kind> and MT3's canonical :POP
symbol on C for it (music-theory's MusicXML kind table, copied as data). Data.")

(defun harmony-to-chord-symbol (element)
  "The CHORD-SYMBOL of the <harmony> ELEMENT (file header)."
  (declare (ignore element))
  (%sc2-pending 'harmony-to-chord-symbol))

(defun chord-symbol-to-harmony (symbol &key id)
  "(values <harmony> element, lost descriptions) for SYMBOL (file header)."
  (declare (ignore symbol id))
  (%sc2-pending 'chord-symbol-to-harmony))
