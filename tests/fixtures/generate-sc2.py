"""Generate the SC2 MusicXML fixtures and their music21 oracle file.

    uv run --with music21==10.5.2 python -I tests/fixtures/generate-sc2.py

Three jobs, all independent of the Lisp code:

1. Golden files. tests/fixtures/sc0/*.sexp are the SC0 fixture scores (copied
   from score-protocol 0.1.0). This script is a second implementation of the
   writer rules in src/writer.lisp, with music-theory 0.5.1's MusicXML kind
   rules (CHORD-SYMBOL-MUSICXML-KIND) for <harmony>: it writes each score as
   tests/fixtures/golden/<name>.musicxml, byte for byte as WRITE-MUSICXML must.
2. The corpus. Short public-domain tunes, re-encoded by us from the data below,
   written as a notation program would write them (no ids, layout and playback
   elements the reader ignores, MuseScore-style voice numbers 1, 2, 5, 6) into
   tests/fixtures/corpus/. Also the hymnal pair hymn-shared / hymn-split (one
   hymn in shared-stem layout and hand-split into four voices) and a deflated
   .mxl archive written with Python's zipfile.
3. The oracle. music21 parses every golden and corpus file; the script writes
   what it finds (measures, events with pitches, durations, ties and lyrics,
   harmonies, keys, meters, tempi) to tests/fixtures/sc2-facts.sexp. It also
   computes the same facts from its own model of each file (the SC0 forms, the
   tune data) and stops when music21 disagrees, so the goldens and the corpus
   say what this script meant them to say.

Offsets and durations are in whole notes (music21 quarterLength / 4).
"""

import io
import os
import re
import sys
import zipfile
from fractions import Fraction
from math import gcd

HERE = os.path.dirname(os.path.abspath(__file__))
SC0 = os.path.join(HERE, "sc0")
GOLDEN = os.path.join(HERE, "golden")
CORPUS = os.path.join(HERE, "corpus")

# --- s-expressions -----------------------------------------------------------

TOKEN = re.compile(r'\s+|;[^\n]*|\(|\)|"(?:[^"\\]|\\.)*"|[^\s()";]+')
NUMBER = re.compile(r'^[+-]?\d+(/\d+)?$|^[+-]?\d*\.\d+$')


class Kw(str):
    """A keyword, without its colon."""


def read_sexp(text):
    stack = [[]]
    pos = 0
    while pos < len(text):
        m = TOKEN.match(text, pos)
        tok, pos = m.group(0), m.end()
        if tok[0].isspace() or tok[0] == ";":
            continue
        if tok == "(":
            stack.append([])
        elif tok == ")":
            items = stack.pop()
            if len(items) == 3 and items[1] == ".":
                items = (items[0], items[2])          # a dotted pair
            stack[-1].append(items)
        elif tok[0] == '"':
            stack[-1].append(re.sub(r'\\(.)', r'\1', tok[1:-1]))
        elif tok[0] == ":":
            stack[-1].append(Kw(tok[1:].lower()))
        elif NUMBER.match(tok):
            stack[-1].append(float(tok) if "." in tok else Fraction(tok))
        elif tok.lower() == "nil":
            stack[-1].append(None)
        elif tok.lower() == "t":
            stack[-1].append(True)
        else:
            stack[-1].append(tok)
    (top,) = stack[0]
    return top


def form(f):
    """(:kind k v ...) → (kind, {key: value})."""
    return f[0], {f[i]: f[i + 1] for i in range(1, len(f), 2)}


def lisp(x):
    """Python value → s-expression text."""
    if x is None or x is False:
        return "nil"
    if x is True:
        return "t"
    if isinstance(x, Kw):
        return ":" + x
    if isinstance(x, str):
        return '"' + x.replace("\\", "\\\\").replace('"', '\\"') + '"'
    if isinstance(x, Fraction):
        return str(x.numerator) if x.denominator == 1 else f"{x.numerator}/{x.denominator}"
    if isinstance(x, int):
        return str(x)
    if isinstance(x, float):
        return lisp(Fraction(x).limit_denominator(1000000))
    if isinstance(x, tuple) and len(x) == 2 and not isinstance(x[1], (list, tuple)):
        return f"({lisp(x[0])} . {lisp(x[1])})"
    return "(" + " ".join(lisp(i) for i in x) + ")"


# --- music theory, the parts the rules need -----------------------------------

LETTERS = "CDEFGAB"
LETTER_FIFTHS = [0, 2, 4, -1, 1, 3, 5]
ACC = {"bb": -2, "b": -1, "": 0, "#": 1, "##": 2}
ACC_TEXT = {-2: "bb", -1: "b", 0: "", 1: "#", 2: "##"}


def parse_pitch(name):
    """"F#4" → (letter, alter, octave)."""
    m = re.match(r'^([A-G])(bb|b|##|#|)(-?\d+)$', name)
    return LETTERS.index(m.group(1)), ACC[m.group(2)], int(m.group(3))


def pitch_name(letter, alter, octave):
    return LETTERS[letter] + ACC_TEXT[alter] + str(octave)


def parse_pc(name):
    m = re.match(r'^([A-G])(bb|b|##|#|)$', name)
    return LETTERS.index(m.group(1)), ACC[m.group(2)]


def pc_name(letter, alter):
    return LETTERS[letter] + ACC_TEXT[alter]


def pc_from_fifths(f):
    alter, offset = divmod(f + 1, 7)
    return LETTER_FIFTHS.index(offset - 1), alter


def pc_fifths(letter, alter):
    return LETTER_FIFTHS[letter] + 7 * alter


def key_signature(key_name):
    """"G major" → (fifths, mode)."""
    tonic, mode = key_name.split(" ")
    return pc_fifths(*parse_pc(tonic)) + (-3 if mode == "minor" else 0), mode


def key_from_signature(fifths, mode):
    return pc_name(*pc_from_fifths(fifths + (3 if mode == "minor" else 0))) + " " + mode


def parse_meter(text):
    nums, den = text.split("/")
    return [int(n) for n in nums.split("+")], int(den)


def meter_bar(text):
    nums, den = parse_meter(text)
    return Fraction(sum(nums), den)


BASES = [Fraction(2), Fraction(1), Fraction(1, 2), Fraction(1, 4), Fraction(1, 8), Fraction(1, 16),
         Fraction(1, 32), Fraction(1, 64), Fraction(1, 128)]
TYPE_NAMES = ["breve", "whole", "half", "quarter", "eighth", "16th", "32nd", "64th", "128th"]


def duration_dots(value, max_dots=3):
    """music-theory DURATION-DOTS: (base, dots) or None."""
    for dots in range(max_dots + 1):
        base = value / (2 - Fraction(1, 2 ** dots))
        if base in BASES:
            return base, dots
    return None


def type_value(type_name, dots=0):
    return BASES[TYPE_NAMES.index(type_name)] * (2 - Fraction(1, 2 ** dots))


def lcm(a, b):
    return a * b // gcd(a, b)


def decimal(x):
    """The writer's DECIMAL (src/writer.lisp)."""
    x = Fraction(x)
    if x.denominator == 1:
        return str(x.numerator)
    d = x.denominator
    while d % 2 == 0:
        d //= 2
    while d % 5 == 0:
        d //= 5
    if d == 1:
        s = format(float(x), "f")       # exact: a terminating decimal
        n = 0
        while Fraction(s) != x:
            n += 1
            s = f"{float(x):.{n}f}"
        return s.rstrip("0").rstrip(".")
    return f"{float(x):.2f}".rstrip("0").rstrip(".")


# --- XML, laid out as xml-backend-native writes it ----------------------------


class E:
    def __init__(self, name, attrs=(), children=()):
        self.name, self.attrs, self.children = name, list(attrs), list(children)

    def add(self, child):
        if child is not None:
            self.children.append(child)
        return child


def esc(s, attr=False):
    s = s.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")
    return s.replace('"', "&quot;") if attr else s


def render(node, out, indent=0):
    pad = "  " * indent
    if isinstance(node, str):
        out.append(pad + esc(node) + "\n")
        return
    attrs = "".join(f' {k}="{esc(str(v), True)}"' for k, v in node.attrs)
    if not node.children:
        out.append(f"{pad}<{node.name}{attrs}/>\n")
    elif len(node.children) == 1 and isinstance(node.children[0], str):
        out.append(f"{pad}<{node.name}{attrs}>{esc(node.children[0])}</{node.name}>\n")
    else:
        out.append(f"{pad}<{node.name}{attrs}>\n")
        for c in node.children:
            render(c, out, indent + 1)
        out.append(f"{pad}</{node.name}>\n")


DOCTYPE_40 = ('<!DOCTYPE score-partwise PUBLIC "-//Recordare//DTD MusicXML 4.0 Partwise//EN" '
              '"http://www.musicxml.org/dtds/partwise.dtd">')
DOCTYPE_31 = ('<!DOCTYPE score-partwise PUBLIC "-//Recordare//DTD MusicXML 3.1 Partwise//EN" '
              '"http://www.musicxml.org/dtds/partwise.dtd">')


def document(root, doctype=DOCTYPE_40):
    out = ['<?xml version="1.0" encoding="UTF-8"?>\n', doctype + "\n"]
    render(root, out)
    return "".join(out)


def text_el(name, text, attrs=()):
    return E(name, attrs, [text] if text != "" else [])


# --- the SC0 model, as plain data ----------------------------------------------


def load_score(path):
    with open(path, encoding="utf-8") as f:
        kind, s = form(read_sexp(f.read()))
    assert kind == "score"
    meta = s.get("metadata") or []
    score = {
        "metadata": {meta[i]: meta[i + 1] for i in range(0, len(meta), 2)},
        "measures": [load_measure(m) for m in s["measures"]],
        "parts": [load_part(p) for p in s["parts"]],
        "anchors": [load_anchor(a) for a in s.get("chord-symbols") or []],
        "spanners": [form(sp)[1] for sp in s.get("spanners") or []],
    }
    return score


def load_measure(f):
    _, m = form(f)
    out = dict(m)
    out["ending"] = form(m["ending"])[1] if m.get("ending") else None
    out["jump"] = [form(j)[1] for j in m.get("jump") or []]
    out["rehearsal"] = form(m["rehearsal"])[1] if m.get("rehearsal") else None
    out["tempo"] = [form(t)[1] for t in m.get("tempo") or []]
    out["barline"] = m.get("barline") or Kw("regular")
    return out


def load_part(f):
    _, p = form(f)
    return {"id": p["id"], "name": p.get("name"), "abbreviation": p.get("abbreviation"),
            "staves": [form(s)[1] for s in p["staves"]],
            "voices": [load_voice(v) for v in p["voices"]]}


def load_voice(f):
    _, v = form(f)
    return {"id": v["id"], "name": v.get("name"), "staff": int(v.get("staff") or 1),
            "stem": v.get("stem"),
            "measures": [[load_event(e) for e in ms] for ms in v["measures"]]}


def sub(m, key):
    return form(m[key])[1] if m.get(key) else None


def load_event(f):
    kind, e = form(f)
    ev = {"kind": kind, "id": e.get("id"), "duration": e["duration"], "tuplet": e.get("tuplet"),
          "grace": e.get("grace"), "measure-rest": e.get("measure-rest"), "hidden": e.get("hidden"),
          "fermata": sub(e, "fermata"), "dynamic": sub(e, "dynamic"),
          "breath": sub(e, "breath-mark"),
          "articulations": [form(a)[1] for a in e.get("articulations") or []],
          "lyrics": [form(l)[1] for l in e.get("lyrics") or []],
          "provenance": e.get("provenance"), "confidence": e.get("confidence")}
    if kind == "note":
        ev["notes"] = [{"id": e.get("id"), "pitch": e["pitch"], "accidental": e.get("accidental"),
                        "tie": sub(e, "tie")}]
    elif kind == "chord":
        ev["notes"] = []
        for n in e["notes"]:
            _, cn = form(n)
            ev["notes"].append({"id": cn.get("id"), "pitch": cn["pitch"],
                                "accidental": cn.get("accidental"), "tie": sub(cn, "tie")})
    else:
        ev["notes"] = []
    return ev


def load_anchor(f):
    _, a = form(f)
    sym = a["symbol"]
    return {"id": a.get("id"), "bar": int(a["bar"]), "offset": a["offset"],
            "symbol": {sym[i]: sym[i + 1] for i in range(0, len(sym), 2)},
            "confidence": a.get("confidence")}


def bars(score):
    """Per measure: (bar, start, length, meter text, key text)."""
    out, time, key, start = [], "4/4", "C major", Fraction(0)
    first = 0 if score["measures"] and score["measures"][0].get("pickup") else 1
    for i, m in enumerate(score["measures"]):
        time = m.get("time") or time
        key = m.get("key") or key
        length = m.get("length") or meter_bar(time)
        out.append((first + i, start, Fraction(length), time, key))
        start += Fraction(length)
    return out


# --- chord symbols as <harmony> (src/harmony.lisp) -------------------------------

# (kind, canonical value on C) where the value is what MT3's PARSE-CHORD-SYMBOL
# makes of the +HARMONY-KINDS+ text: (quality extensions suspension alterations
# added omitted).
KINDS = [
    ("major", ("major", (), None, (), (), ())),
    ("minor", ("minor", (), None, (), (), ())),
    ("augmented", ("augmented", (), None, (), (), ())),
    ("diminished", ("diminished", (), None, (), (), ())),
    ("dominant", ("dominant-7", (), None, (), (), ())),
    ("major-seventh", ("major-7", (), None, (), (), ())),
    ("minor-seventh", ("minor-7", (), None, (), (), ())),
    ("diminished-seventh", ("diminished-7", (), None, (), (), ())),
    ("augmented-seventh", ("augmented-7", (), None, (), (), ())),
    ("half-diminished", ("half-diminished-7", (), None, (), (), ())),
    ("major-minor", ("minor-major-7", (), None, (), (), ())),
    ("major-sixth", ("major-6", (), None, (), (), ())),
    ("minor-sixth", ("minor-6", (), None, (), (), ())),
    ("dominant-ninth", ("dominant-7", (9,), None, (), (), ())),
    ("major-ninth", ("major-7", (9,), None, (), (), ())),
    ("minor-ninth", ("minor-7", (9,), None, (), (), ())),
    ("dominant-11th", ("dominant-7", (9, 11), None, (), (), ())),
    ("major-11th", ("major-7", (9, 11), None, (), (), ())),
    ("minor-11th", ("minor-7", (9, 11), None, (), (), ())),
    ("dominant-13th", ("dominant-7", (9, 11, 13), None, (), (), ())),
    ("major-13th", ("major-7", (9, 11, 13), None, (), (), ())),
    ("minor-13th", ("minor-7", (9, 11, 13), None, (), (), ())),
    ("suspended-second", ("major", (), 2, (), (), ())),
    ("suspended-fourth", ("major", (), 4, (), (), ())),
    ("Neapolitan", ("major", (), None, (), (), ())),
    ("Italian", ("power", (), None, (), ((4, 1), (6, -1)), (5,))),
    ("French", ("power", (), None, (), ((2, 0), (4, 1), (6, -1)), (5,))),
    ("German", ("minor", (), None, (), ((4, 1), (6, -1)), (5,))),
    ("pedal", ("power", (), None, (), (), (5,))),
    ("power", ("power", (), None, (), (), ())),
    ("Tristan", ("power", (), None, ((9, 1),), ((4, 1), (6, 1)), (5,))),
]

QUALITY_DEGREES = {"major": (1, 3, 5), "minor": (1, 3, 5), "diminished": (1, 3, 5),
                   "augmented": (1, 3, 5), "dominant-7": (1, 3, 5, 7), "major-7": (1, 3, 5, 7),
                   "minor-7": (1, 3, 5, 7), "minor-major-7": (1, 3, 5, 7),
                   "half-diminished-7": (1, 3, 5, 7), "diminished-7": (1, 3, 5, 7),
                   "augmented-7": (1, 3, 5, 7), "augmented-major-7": (1, 3, 5, 7),
                   "major-6": (1, 3, 5, 6), "minor-6": (1, 3, 5, 6), "power": (1, 5)}


def pairs(x):
    return tuple(sorted((int(d), int(a)) for d, a in (x or ())))


def degree_el(value, alter, kind):
    return E("degree", [], [text_el("degree-value", str(value)), text_el("degree-alter", str(alter)),
                            text_el("degree-type", kind)])


def step_alter(parent, prefix, pc):
    letter, alter = parse_pc(pc)
    el = E(prefix, [], [text_el(prefix + "-step", LETTERS[letter])])
    if alter:
        el.add(text_el(prefix + "-alter", str(alter)))
    return el


STRUCTURAL = {  # music-theory +MUSICXML-STRUCTURAL-DEGREES+: quality → (base, degrees)
    "diminished-7": ("minor-7", [(5, -1, "alter"), (7, -1, "alter")]),
    "minor-major-7": ("minor-7", [(7, 1, "alter")]),
    "half-diminished-7": ("minor-7", [(5, -1, "alter")]),
    "augmented-7": ("dominant-7", [(5, 1, "alter")]),
    "augmented-major-7": ("major-7", [(5, 1, "alter")]),
}


def chord_symbol_to_harmony(sym, hid=None):
    """(element, lost) as CHORD-SYMBOL-TO-HARMONY, with the kind and degrees of
    music-theory's CHORD-SYMBOL-MUSICXML-KIND (rules X1-X3)."""
    lost = []
    if sym.get("text") or sym.get("dialect"):
        lost.append("chord-symbol text")
    h = E("harmony", [("id", hid)] if hid else [])
    if sym.get("no-chord-p"):
        h.add(E("root", [], [text_el("root-step", "C")]))
        h.add(text_el("kind", "none"))
        return h, lost
    q = str(sym["quality"])
    x = tuple(int(e) for e in sym.get("extensions") or ())
    s = sym.get("suspension")
    s = int(s) if s else None
    alts, added = pairs(sym.get("alterations")), pairs(sym.get("added"))
    omitted = tuple(int(d) for d in sym.get("omitted") or ())

    def plain(quality, ext):
        return next((k for k, b in KINDS if b[0] == quality and b[1] == ext and b[2] is None
                     and not (b[3] or b[4] or b[5])), None)

    degrees = []
    if q == "major" and s and not x:                       # X2: the suspended kinds
        kind, written_sus = ("suspended-second" if s == 2 else "suspended-fourth"), True
    else:
        written_sus = False
        kind = plain(q, x)
        if kind is None:                                   # X2: structural degrees
            base, structural = STRUCTURAL[q]
            kind = plain(base, x)
            degrees += structural
    if s and not written_sus:                              # X3
        degrees += [(3, 0, "subtract"), (s, 0, "add")]
    degrees += [(d, a, "alter" if d == 5 or d in x else "add") for d, a in alts]
    degrees += [(d, a, "add") for d, a in added]
    degrees += [(d, 0, "subtract") for d in omitted]
    h.add(step_alter(h, "root", sym["root"]))
    h.add(text_el("kind", kind))
    if sym.get("bass"):
        h.add(step_alter(h, "bass", sym["bass"]))
    for d, a, t in degrees:
        h.add(degree_el(d, a, t))
    return h, lost


# --- the reference writer (src/writer.lisp) ------------------------------------

CLEFS = {"treble": ("G", 2, 0), "treble-8vb": ("G", 2, -1), "treble-8va": ("G", 2, 1),
         "bass": ("F", 4, 0), "bass-8vb": ("F", 4, -1), "alto": ("C", 3, 0), "tenor": ("C", 4, 0)}
BAR_STYLES = {"regular": "regular", "double": "light-light", "final": "light-heavy",
              "dashed": "dashed", "dotted": "dotted", "heavy": "heavy", "none": "none"}
ARTICULATIONS = {"accent": "accent", "marcato": "strong-accent", "staccato": "staccato",
                 "staccatissimo": "staccatissimo", "tenuto": "tenuto",
                 "detached-legato": "detached-legato", "spiccato": "spiccato", "stress": "stress",
                 "unstress": "unstress", "soft-accent": "soft-accent"}
FERMATAS = {"normal": "normal", "short": "angled", "long": "square"}
ACCIDENTALS = {-2: "flat-flat", -1: "flat", 0: "natural", 1: "sharp", 2: "double-sharp"}
JUMPS = [("segno", None, "segno", "segno"), ("coda", None, "coda", "coda"),
         ("to-coda", "To Coda", "tocoda", "coda"), ("fine", "Fine", "fine", "yes"),
         ("da-capo", "D.C.", "dacapo", "yes"), ("da-capo-al-fine", "D.C. al Fine", "dacapo", "yes"),
         ("da-capo-al-coda", "D.C. al Coda", "dacapo", "yes"), ("dal-segno", "D.S.", "dalsegno", "segno"),
         ("dal-segno-al-fine", "D.S. al Fine", "dalsegno", "segno"),
         ("dal-segno-al-coda", "D.S. al Coda", "dalsegno", "segno")]
JUMP_ORDER = [j[0] for j in JUMPS]


class Numbers:
    """Least free number >= 1, per part (slurs and hairpins separately)."""

    def __init__(self):
        self.held = {}

    def start(self, key):
        n = 1
        while n in self.held.values():
            n += 1
        self.held[key] = n
        return n

    def stop(self, key):
        return self.held.pop(key)


def all_elements_have(score, key):
    """True when some element of the score has KEY (provenance / confidence)."""
    def walk(x):
        if isinstance(x, dict):
            if x.get(key) is not None:
                return True
            return any(walk(v) for v in x.values())
        if isinstance(x, list):
            return any(walk(v) for v in x)
        return False
    return walk(score)


def write_score(score):
    """(text, lost) for an SC0 score, as WRITE-MUSICXML."""
    lost = set()
    md = score["metadata"]
    root = E("score-partwise", [("version", "4.0")])
    if md.get("title") or md.get("subtitle"):
        root.add(E("work", [], [text_el("work-title", md.get("title") or "")]))
    if md.get("subtitle"):
        root.add(text_el("movement-title", md["subtitle"]))
    if any(md.get(k) for k in ("composer", "lyricist", "arranger", "copyright")):
        ident = root.add(E("identification"))
        for k in ("composer", "lyricist", "arranger"):
            if md.get(k):
                ident.add(text_el("creator", md[k], [("type", k)]))
        if md.get("copyright"):
            ident.add(text_el("rights", md["copyright"]))
    plist = root.add(E("part-list"))
    for p in score["parts"]:
        sp = plist.add(E("score-part", [("id", p["id"])]))
        sp.add(text_el("part-name", p["name"] or ""))
        if p["abbreviation"]:
            sp.add(text_el("part-abbreviation", p["abbreviation"]))
        for v in p["voices"]:
            sp.add(E("player", [("id", v["id"])], [text_el("player-name", v["name"] or "")]))
    bt = bars(score)
    spanners = score["spanners"]
    tie_ends = set()
    for p in score["parts"]:
        for v in p["voices"]:
            for ms in v["measures"]:
                for e in ms:
                    for n in e["notes"]:
                        if n["tie"]:
                            tie_ends.add(n["tie"]["end"])
    for pi, p in enumerate(score["parts"]):
        root.add(write_part(score, p, pi == 0, bt, spanners, tie_ends, lost))
    if all_elements_have(score, "provenance") or all_elements_have(score, "confidence"):
        lost.add("provenance and confidence")
    order = ["provenance and confidence", "chord-symbol text", "notated value"]
    return document(root), [w for w in order if w in lost]


def divisions(score, part, first, bt):
    xs = [e["duration"] for v in part["voices"] for ms in v["measures"] for e in ms if not e["grace"]]
    xs += [b[2] for b in bt]
    if first:
        xs += [t.get("offset") or 0 for m in score["measures"] for t in m["tempo"]]
        xs += [a["offset"] for a in score["anchors"]]
    d = 1
    for x in xs:
        d = lcm(d, (Fraction(x) * 4).denominator)
    return d


def write_part(score, part, first, bt, spanners, tie_ends, lost):
    D = divisions(score, part, first, bt)
    dur = lambda x: str(int(Fraction(x) * 4 * D))
    two = len(part["staves"]) >= 2
    pel = E("part", [("id", part["id"])])
    slurs, wedges = Numbers(), Numbers()
    nmeasures = len(score["measures"])
    endings_last = {}
    for i, m in enumerate(score["measures"]):
        if m["ending"]:
            endings_last[min(nmeasures - 1, i + int(m["ending"].get("measures") or 1) - 1)] = m["ending"]
    for i, m in enumerate(score["measures"]):
        bar, start, length, time, key = bt[i]
        attrs = [("number", str(bar))]
        if m.get("number"):
            attrs.append(("text", m["number"]))
        if m.get("pickup"):
            attrs.append(("implicit", "yes"))
        attrs.append(("id", m["id"] + "." + part["id"]))
        mel = pel.add(E("measure", attrs))
        # 1. attributes
        if i == 0 or m.get("time") or m.get("key"):
            a = mel.add(E("attributes"))
            if i == 0:
                a.add(text_el("divisions", str(D)))
            if m.get("key"):
                f, mode = key_signature(m["key"])
                a.add(E("key", [], [text_el("fifths", str(f)), text_el("mode", mode)]))
            if m.get("time"):
                nums, den = parse_meter(m["time"])
                a.add(E("time", [], [text_el("beats", "+".join(map(str, nums))),
                                     text_el("beat-type", str(den))]))
            if i == 0:
                if two:
                    a.add(text_el("staves", str(len(part["staves"]))))
                for k, st in enumerate(part["staves"], 1):
                    sign, line, octave = CLEFS[str(st.get("clef") or "treble")]
                    c = a.add(E("clef", ([("number", str(k))] if two else []) + [("id", st["id"])]))
                    c.add(text_el("sign", sign))
                    c.add(text_el("line", str(line)))
                    if octave:
                        c.add(text_el("clef-octave-change", str(octave)))
        # 2. left barline
        if m.get("repeat-start") or m["ending"]:
            battrs = [("location", "left")]
            if first and m["ending"]:
                battrs.append(("id", m["ending"]["id"]))
            b = mel.add(E("barline", battrs))
            if m.get("repeat-start"):
                b.add(text_el("bar-style", "heavy-light"))
            if m["ending"]:
                b.add(E("ending", [("number", ", ".join(str(int(x)) for x in m["ending"]["passes"])),
                                   ("type", "start")]))
            if m.get("repeat-start"):
                b.add(E("repeat", [("direction", "forward")]))
        # 3. the measure track
        cursor = Fraction(0)
        if first:
            items = []
            if m["rehearsal"]:
                items.append((Fraction(0), 0, len(items), ("rehearsal", m["rehearsal"])))
            for j in m["jump"]:
                if j["kind"] in ("segno", "coda"):
                    items.append((Fraction(0), 1, len(items), ("jump", j)))
            for t in m["tempo"]:
                items.append((Fraction(t.get("offset") or 0), 2, len(items), ("tempo", t)))
            for a in score["anchors"]:
                if a["bar"] == bar:
                    items.append((Fraction(a["offset"]), 3, len(items), ("anchor", a)))
            for j in m["jump"]:
                if j["kind"] not in ("segno", "coda"):
                    items.append((length, 4, len(items), ("jump", j)))
            for off, _, _, (kind, x) in sorted(items, key=lambda it: it[:3]):
                if off > cursor:
                    mel.add(E("forward", [], [text_el("duration", dur(off - cursor))]))
                    cursor = off
                mel.add(track_item(kind, x, lost))
            if cursor > 0:
                mel.add(E("backup", [], [text_el("duration", dur(cursor))]))
                cursor = Fraction(0)
        # 4. voices
        for k, v in enumerate(part["voices"], 1):
            events = v["measures"][i] if i < len(v["measures"]) else []
            if not events:
                continue
            if cursor > 0:
                mel.add(E("backup", [], [text_el("duration", dur(cursor))]))
                cursor = Fraction(0)
            loc = [text_el("voice", str(k))] + ([text_el("staff", str(v["staff"]))] if two else [])
            for e in events:
                if e["dynamic"]:
                    mel.add(E("direction", [("id", e["dynamic"]["id"])],
                              [E("direction-type", [], [E("dynamics", [], [E(str(e["dynamic"]["value"]))])])]
                              + loc))
                for sp in spanners:
                    if sp["kind"] in ("crescendo", "diminuendo") and sp["start"] == e["id"]:
                        n = wedges.start(sp["id"])
                        mel.add(E("direction", [("id", sp["id"])],
                                  [E("direction-type", [], [E("wedge", [("type", str(sp["kind"])),
                                                                         ("number", str(n))])])] + loc))
                for el in note_elements(e, k, v, two, dur, spanners, tie_ends, slurs, lost):
                    mel.add(el)
                if not e["grace"]:
                    cursor += Fraction(e["duration"])
                for sp in spanners:
                    if sp["kind"] in ("crescendo", "diminuendo") and sp["end"] == e["id"]:
                        n = wedges.stop(sp["id"])
                        mel.add(E("direction", [],
                                  [E("direction-type", [], [E("wedge", [("type", "stop"),
                                                                         ("number", str(n))])])] + loc))
        # 5. right barline
        ending_end = endings_last.get(i)
        if m["barline"] != "regular" or m.get("repeat-end") or ending_end:
            b = mel.add(E("barline", [("location", "right")]))
            if m["barline"] != "regular":
                b.add(text_el("bar-style", BAR_STYLES[str(m["barline"])]))
            if ending_end:
                b.add(E("ending", [("number", ", ".join(str(int(x)) for x in ending_end["passes"])),
                                   ("type", "stop" if m.get("repeat-end") else "discontinue")]))
            if m.get("repeat-end"):
                ra = [("direction", "backward")]
                if int(m["repeat-end"]) != 2:
                    ra.append(("times", str(int(m["repeat-end"]))))
                b.add(E("repeat", ra))
    return pel


def track_item(kind, x, lost):
    if kind == "rehearsal":
        return E("direction", [("id", x["id"])],
                 [E("direction-type", [], [text_el("rehearsal", x["text"])])])
    if kind == "jump":
        _, words, attr, value = JUMPS[JUMP_ORDER.index(str(x["kind"]))]
        d = E("direction", [("id", x["id"])])
        if words is None:
            d.add(E("direction-type", [], [E(str(x["kind"]))]))
        else:
            d.add(E("direction-type", [], [text_el("words", words)]))
        d.add(E("sound", [(attr, value)]))
        return d
    if kind == "tempo":
        d = E("direction", [("id", x["id"])])
        if x.get("text"):
            d.add(E("direction-type", [], [text_el("words", x["text"])]))
        if x.get("bpm"):
            bpm, unit = Fraction(x["bpm"]), Fraction(x["beat-unit"])
            dd = duration_dots(unit)
            if dd:
                base, dots = dd
                met = E("metronome", [], [text_el("beat-unit", TYPE_NAMES[BASES.index(base)])]
                        + [E("beat-unit-dot") for _ in range(dots)]
                        + [text_el("per-minute", decimal(bpm))])
                d.add(E("direction-type", [], [met]))
            else:
                lost.add("notated value")
            d.add(E("sound", [("tempo", decimal(bpm * unit * 4))]))
        else:
            d.add(E("sound"))
        return d
    if kind == "anchor":
        h, l = chord_symbol_to_harmony(x["symbol"], x["id"])
        lost.update(l)
        return h
    raise ValueError(kind)


def note_elements(e, k, v, two, dur, spanners, tie_ends, slurs, lost):
    out = []
    notes = e["notes"] or [None]
    for ni, n in enumerate(notes):
        nid = e["id"] if e["kind"] != "chord" else n["id"]
        attrs = ([("print-object", "no")] if e["kind"] == "rest" and e["hidden"] else []) + [("id", nid)]
        el = E("note", attrs)
        if e["grace"]:
            el.add(E("grace", [("slash", "yes")] if e["grace"] == "acciaccatura" else []))
        if ni > 0:
            el.add(E("chord"))
        if n is None:
            el.add(E("rest", [("measure", "yes")] if e["measure-rest"] else []))
        else:
            letter, alter, octave = parse_pitch(n["pitch"])
            pe = el.add(E("pitch", [], [text_el("step", LETTERS[letter])]))
            if alter:
                pe.add(text_el("alter", str(alter)))
            pe.add(text_el("octave", str(octave)))
        if not e["grace"]:
            el.add(text_el("duration", dur(e["duration"])))
        is_end = n is not None and nid in tie_ends
        if is_end:
            el.add(E("tie", [("type", "stop")]))
        if n is not None and n["tie"]:
            el.add(E("tie", [("type", "start")]))
        el.add(text_el("voice", str(k)))
        if not e["measure-rest"]:
            value = Fraction(e["duration"]) if e["grace"] else \
                Fraction(e["duration"]) * Fraction(e["tuplet"] or 1)
            dd = duration_dots(value)
            if dd:
                base, dots = dd
                el.add(text_el("type", TYPE_NAMES[BASES.index(base)]))
                for _ in range(dots):
                    el.add(E("dot"))
            elif e["grace"]:
                lost.add("notated value")
        if n is not None and n.get("accidental") in ("forced", "cautionary"):
            el.add(text_el("accidental", ACCIDENTALS[parse_pitch(n["pitch"])[1]],
                           [("cautionary", "yes")] if n["accidental"] == "cautionary" else []))
        if e["tuplet"]:
            t = Fraction(e["tuplet"])
            el.add(E("time-modification", [], [text_el("actual-notes", str(t.numerator)),
                                               text_el("normal-notes", str(t.denominator))]))
        if n is not None and v["stem"]:
            el.add(text_el("stem", str(v["stem"])))
        if two:
            el.add(text_el("staff", str(v["staff"])))
        nots = E("notations", [("id", e["id"])] if e["kind"] == "chord" and ni == 0 else [])
        if is_end:
            nots.add(E("tied", [("type", "stop")]))
        if n is not None and n["tie"]:
            nots.add(E("tied", [("type", "start"), ("id", n["tie"]["id"])]))
        if ni == 0:
            for sp in spanners:
                if sp["kind"] == "slur" and sp["end"] == e["id"]:
                    nots.add(E("slur", [("type", "stop"), ("number", str(slurs.stop(sp["id"])))]))
            for sp in spanners:
                if sp["kind"] == "slur" and sp["start"] == e["id"]:
                    nots.add(E("slur", [("type", "start"), ("number", str(slurs.start(sp["id"]))),
                                        ("id", sp["id"])]))
            for a in e["articulations"]:
                nots.add(E("articulations", [("id", a["id"])], [E(ARTICULATIONS[str(a["kind"])])]))
            if e["breath"]:
                nots.add(E("articulations", [("id", e["breath"]["id"])], [E("breath-mark")]))
            if e["fermata"]:
                nots.add(text_el("fermata", FERMATAS[str(e["fermata"].get("shape") or "normal")],
                                 [("id", e["fermata"]["id"])]))
        if nots.children or nots.attrs:
            el.add(nots)
        if ni == 0:
            for ly in e["lyrics"]:
                le = el.add(E("lyric", [("number", str(int(ly.get("verse") or 1))), ("id", ly["id"])]))
                le.add(text_el("syllabic", str(ly.get("syllabic") or "single")))
                le.add(text_el("text", ly["text"]))
                if ly.get("extender"):
                    le.add(E("extend"))
        out.append(el)
    return out


# --- facts --------------------------------------------------------------------
# One entry per file: (file :measures ROWS :events ROWS :harmonies ROWS :keys
# ROWS :times ROWS :tempos ROWS), where
#   measure  (index bar offset length)
#   event    (part staff voice measure offset kind pitches duration tuplet grace
#             hidden tie lyrics): PART and STAFF 1-based; VOICE the voice's
#             1-based rank in its part (by <voice> value, as the reader orders
#             voices) when its staff holds two or more voices with events in that
#             measure, else NIL (music21 only makes Voice objects then); MEASURE
#             0-based; KIND :note :chord or :rest; PITCHES sorted names; a grace
#             note's DURATION is its notated value; TIE true when a note of the
#             event starts a tie; LYRICS ((verse syllabic text) ...) by verse.
#   harmony  (measure offset root bass tones): BASS NIL without a slash bass;
#             TONES the sorted pitch-class names, the bass included.
#   key      (measure fifths mode)     time (measure "3/4")
#   tempo    (measure offset bpm beat-unit), metronome marks only.


def model_facts(score):
    bt = bars(score)
    first = bt[0][0] if bt else 1
    measures = [(i, b, s, l) for i, (b, s, l, _, _) in enumerate(bt)]
    events = []
    for pi, p in enumerate(score["parts"], 1):
        for k, v in enumerate(p["voices"], 1):
            for mi, ms in enumerate(v["measures"]):
                shared = sum(1 for w in p["voices"] if w["staff"] == v["staff"] and w["measures"][mi]) > 1
                at = Fraction(0)
                for e in ms:
                    pitches = sorted(n["pitch"] for n in e["notes"])
                    events.append((pi, v["staff"], k if shared else None, mi, at, Kw(e["kind"]), pitches,
                                   Fraction(e["duration"]), e["tuplet"] if not e["grace"] else None,
                                   bool(e["grace"]), bool(e["hidden"]),
                                   any(n["tie"] for n in e["notes"]),
                                   sorted([(int(l.get("verse") or 1), Kw(l.get("syllabic") or "single"),
                                            l["text"]) for l in e["lyrics"]])))
                    if not e["grace"]:
                        at += Fraction(e["duration"])
    harmonies = []
    for a in score["anchors"]:
        sym = a["symbol"]
        if sym.get("no-chord-p"):
            harmonies.append((a["bar"] - first, a["offset"], None, None, []))
        else:
            tones = set(realise(sym)) | ({sym["bass"]} if sym.get("bass") else set())
            harmonies.append((a["bar"] - first, a["offset"], sym["root"], sym.get("bass"), sorted(tones)))
    keys, times, tempos = [], [], []
    for i, m in enumerate(score["measures"]):
        if m.get("key"):
            f, mode = key_signature(m["key"])
            keys.append((i, f, Kw(mode)))
        if m.get("time"):
            times.append([i, m["time"]])
        for t in m["tempo"]:
            if t.get("bpm"):
                tempos.append((i, Fraction(t.get("offset") or 0), Fraction(t["bpm"]), Fraction(t["beat-unit"])))
    return {"measures": measures, "events": sorted(events, key=event_key), "harmonies": sorted(harmonies, key=str),
            "keys": keys, "times": times, "tempos": tempos}


def event_key(row):
    return (row[0], row[1], row[3], row[4], str(row[2]), row[9] is False, str(row[6]))


INTERVALS = {  # semitones and letter steps above the root, per degree, natural form
    1: (0, 0), 2: (2, 1), 3: (4, 2), 4: (5, 3), 5: (7, 4), 6: (9, 5), 7: (11, 6),
    9: (14, 1), 11: (17, 3), 13: (21, 5)}
QUALITY_TONES = {  # degree → semitone offset from the natural interval
    "major": {3: 0, 5: 0}, "minor": {3: -1, 5: 0}, "diminished": {3: -1, 5: -1},
    "augmented": {3: 0, 5: 1}, "dominant-7": {3: 0, 5: 0, 7: -1}, "major-7": {3: 0, 5: 0, 7: 0},
    "minor-7": {3: -1, 5: 0, 7: -1}, "minor-major-7": {3: -1, 5: 0, 7: 0},
    "half-diminished-7": {3: -1, 5: -1, 7: -1}, "diminished-7": {3: -1, 5: -1, 7: -2},
    "augmented-7": {3: 0, 5: 1, 7: -1}, "augmented-major-7": {3: 0, 5: 1, 7: 0},
    "major-6": {3: 0, 5: 0, 6: 0}, "minor-6": {3: -1, 5: 0, 6: 0}, "power": {5: 0}}


def realise(sym):
    """Pitch-class names of a chord symbol's tones (MT3 CHORD-TONES)."""
    tones = {1: 0}
    tones.update(QUALITY_TONES[str(sym["quality"])])
    for e in sym.get("extensions") or ():
        tones[int(e)] = 0
    if sym.get("suspension"):
        tones.pop(3, None)
        tones[int(sym["suspension"])] = 0
    for d, a in sym.get("alterations") or ():
        tones[int(d)] = int(a)
    for d, a in sym.get("added") or ():
        tones[int(d)] = int(a)
    for d in sym.get("omitted") or ():
        tones.pop(int(d), None)
    rl, ra = parse_pc(sym["root"])
    out = []
    for d, a in tones.items():
        semis, steps = INTERVALS[d]
        letter = (rl + steps) % 7
        natural = (LETTER_SEMIS[letter] - LETTER_SEMIS[rl]) % 12
        want = (semis + a) % 12
        alter = ra + ((want - natural + 6) % 12 - 6)
        out.append(pc_name(letter, alter))
    return out


LETTER_SEMIS = [0, 2, 4, 5, 7, 9, 11]


def m21_name(p):
    return p.name.replace("-", "b")


def m21_facts(path):
    """What music21 reads in the MusicXML file PATH, as facts."""
    import xml.etree.ElementTree as ET
    from music21 import converter, stream, note, chord, harmony, key, meter, tempo
    tree = ET.parse(path)
    layout = []          # per music21 part: (part index, staff, voice ranks of the part)
    for pi, part in enumerate(tree.getroot().findall("part"), 1):
        staves = max([int(s.text) for s in part.iter("staves")] or [1])
        values = sorted({(v.text or "1").strip() for v in part.iter("voice")} or {"1"},
                        key=lambda x: (0, int(x)) if x.isdigit() else (1, x))
        ranks = {v: i for i, v in enumerate(values, 1)}
        for st in range(1, staves + 1):
            layout.append((pi, st, ranks))
    s = converter.parse(path, format="musicxml", forceSource=True)
    assert len(s.parts) == len(layout), (path, len(s.parts), len(layout))
    q = lambda x: Fraction(x) / 4
    measures, events, harmonies, keys, times, tempos = [], [], set(), [], [], []
    for (pi, st, ranks), p in zip(layout, s.parts):
        for mi, m in enumerate(p.getElementsByClass(stream.Measure)):
            if pi == 1 and st == 1:
                measures.append((mi, m.number, q(m.offset), q(m.duration.quarterLength)))
                for ks in m.getElementsByClass(key.KeySignature):
                    keys.append((mi, ks.sharps, Kw(getattr(ks, "mode", None) or "major")))
                for ts in m.getElementsByClass(meter.TimeSignature):
                    times.append([mi, ts.ratioString])
                for mm in m.recurse().getElementsByClass(tempo.MetronomeMark):
                    if mm.number is not None:
                        tempos.append((mi, q(mm.getOffsetInHierarchy(m)), Fraction(mm.number),
                                       q(mm.referent.quarterLength)))
            for cs in m.recurse().getElementsByClass(harmony.Harmony):
                off = q(cs.getOffsetInHierarchy(m))
                if isinstance(cs, harmony.NoChord):
                    harmonies.add((mi, off, None, None, ()))
                else:
                    root, bass = m21_name(cs.root()), m21_name(cs.bass())
                    harmonies.add((mi, off, root, bass if bass != root else None,
                                   tuple(sorted({m21_name(x) for x in cs.pitches}))))
            groups = [(ranks.get(v.id), v.notesAndRests) for v in m.voices] if m.voices else []
            groups.append((None, m.notesAndRests if not m.voices else
                           [n for n in m if isinstance(n, note.GeneralNote)]))
            for voice, notes in groups:
                for n in notes:
                    if isinstance(n, harmony.Harmony):
                        continue
                    grace = n.duration.isGrace
                    if grace:
                        dur = type_value(n.duration.type, n.duration.dots)
                    else:
                        dur = q(n.duration.quarterLength)
                    tup = None
                    if n.duration.tuplets and not grace:
                        t = n.duration.tuplets[0]
                        tup = Fraction(t.numberNotesActual, t.numberNotesNormal)
                    if isinstance(n, note.Rest):
                        kind, pitches, tie = "rest", [], False
                    elif isinstance(n, chord.Chord):
                        kind = "chord"
                        pitches = sorted(x.nameWithOctave.replace("-", "b") for x in n.pitches)
                        tie = any(x.tie is not None and x.tie.type in ("start", "continue") for x in n.notes)
                    else:
                        kind = "note"
                        pitches = [n.pitch.nameWithOctave.replace("-", "b")]
                        tie = n.tie is not None and n.tie.type in ("start", "continue")
                    lyrics = sorted((int(l.number), Kw(l.syllabic or "single"), l.text) for l in n.lyrics)
                    events.append((pi, st, voice, mi, q(n.getOffsetInHierarchy(m)), Kw(kind), pitches, dur,
                                   tup, grace, bool(kind == "rest" and n.style.hideObjectOnPrint), tie, lyrics))
    return {"measures": measures, "events": sorted(events, key=event_key),
            "harmonies": sorted([(a, b, c, d, list(e)) for a, b, c, d, e in harmonies], key=str),
            "keys": keys, "times": times, "tempos": tempos}


def diff_facts(name, ours, theirs, allowed=()):
    """Stop unless the two fact sets agree (except the ALLOWED keys)."""
    bad = []
    for key in ("measures", "events", "harmonies", "keys", "times", "tempos"):
        if key in allowed:
            continue
        a, b = [lisp(r) for r in ours[key]], [lisp(r) for r in theirs[key]]
        if a != b:
            extra, missing = [r for r in b if r not in a], [r for r in a if r not in b]
            bad.append(f"  {key}: music21 also has {extra[:4]}, lacks {missing[:4]}")
    if bad:
        sys.exit(f"{name}: music21 disagrees with the script's model\n" + "\n".join(bad))


# --- the corpus: tune data → the same plain model --------------------------------
# A voice's music is measures separated by "|", each a list of tokens:
#   C4:4  F#4:8.  Bb3:2        a note: pitch, ":", 1 2 4 8 16 32 (whole..32nd), dots
#   r:4   R                    a rest; R is a whole-measure rest (measure="yes")
#   [D4,G4]:2                  a chord
#   g/D5:8  G/D5:8             a grace note (appoggiatura / acciaccatura): notated value
#   3/F4:8                     a triplet note (3 in the time of 2): the notated value
# Suffixes after the duration: ~ tie to the next note, ( slur start, ) slur end,
# F fermata, B breath mark, s staccato, a accent, t tenuto, m marcato.
# Prefix marks before a note: {mf} a dynamic, {<} / {>} a hairpin starting on it;
# {/} after a note: the open hairpin ends on it.
# Lyrics: a verse is a string of syllables given to the voice's notes in order
# (not rests, grace notes or tie continuations). "word-" continues the word
# (begin/middle), a syllable after one ends it; "word_" has an extender; "_"
# gives a note no syllable.

DURS = {"1": Fraction(1), "2": Fraction(1, 2), "4": Fraction(1, 4), "8": Fraction(1, 8),
        "16": Fraction(1, 16), "32": Fraction(1, 32)}
NOTE_RE = re.compile(r'^(?P<grace>[gG]/)?(?P<trip>3/)?(?P<body>\[[^\]]+\]|[A-G](?:bb|b|##|#)?-?\d|r|R)'
                     r'(?::(?P<dur>\d+)(?P<dots>\.*))?(?P<flags>[~()FBsatm]*)$')


def parse_music(text, bars_info, prefix="t"):
    """Measures of events (dicts as load_event makes them) and the hairpins. Ids
    are PREFIX and a serial, so the voices of one tune never share one."""
    measures, spanners = [], []
    open_slur, open_wedge, pending = None, None, {}
    serial = [0]

    def tid():
        serial[0] += 1
        return f"{prefix}{serial[0]}"

    chunks = [c.strip() for c in text.split("|")]
    for mi, chunk in enumerate(chunks):
        events = []
        for tok in chunk.split():
            if tok.startswith("{") and tok.endswith("}"):
                mark = tok[1:-1]
                if mark == "/":
                    spanners.append(dict(open_wedge, end=events[-1]["id"]))
                    open_wedge = None
                elif mark in ("<", ">"):
                    pending["wedge"] = "crescendo" if mark == "<" else "diminuendo"
                else:
                    pending["dynamic"] = {"value": Kw(mark)}
                continue
            m = NOTE_RE.match(tok)
            if not m:
                raise ValueError(f"bad token {tok!r}")
            body, flags = m.group("body"), m.group("flags") or ""
            e = {"kind": "note", "id": tid(), "tuplet": None, "grace": None, "measure-rest": None,
                 "hidden": None, "fermata": None, "dynamic": pending.pop("dynamic", None),
                 "breath": None, "articulations": [], "lyrics": [], "notes": [],
                 "provenance": None, "confidence": None}
            if body == "R":
                e.update(kind="rest", duration=bars_info[mi][2], **{"measure-rest": True})
            else:
                value = DURS[m.group("dur")] * (2 - Fraction(1, 2 ** len(m.group("dots"))))
                if m.group("grace"):
                    e["grace"] = Kw("acciaccatura" if m.group("grace") == "G/" else "appoggiatura")
                if m.group("trip"):
                    e["tuplet"] = Fraction(3, 2)
                    value = value * Fraction(2, 3)
                e["duration"] = value
                if body == "r":
                    e["kind"] = "rest"
                elif body.startswith("["):
                    e["kind"] = "chord"
                    e["notes"] = [{"id": tid(), "pitch": p, "accidental": None, "tie": None}
                                  for p in body[1:-1].split(",")]
                else:
                    e["notes"] = [{"id": e["id"], "pitch": body, "accidental": None, "tie": None}]
            if "~" in flags:
                for n in e["notes"]:
                    n["tie"] = {"id": tid(), "end": None}
            if "F" in flags:
                e["fermata"] = {"shape": Kw("normal")}
            if "B" in flags:
                e["breath"] = {"id": None}
            for flag, kind in (("a", "accent"), ("m", "marcato"), ("s", "staccato"), ("t", "tenuto")):
                if flag in flags:
                    e["articulations"].append({"kind": Kw(kind)})
            if "wedge" in pending:
                open_wedge = {"id": tid(), "kind": Kw(pending.pop("wedge")), "start": e["id"]}
            if ")" in flags and open_slur:
                spanners.append(dict(open_slur, end=e["id"]))
                open_slur = None
            if "(" in flags:
                open_slur = {"id": tid(), "kind": Kw("slur"), "start": e["id"]}
            events.append(e)
        measures.append(events)
    return measures, spanners


def link_ties(measures):
    """Point each tie at the next note of equal pitch."""
    flat = [e for ms in measures for e in ms if not e["grace"]]
    for i, e in enumerate(flat):
        for n in e["notes"]:
            if n["tie"]:
                nxt = flat[i + 1]
                target = next(x for x in nxt["notes"] if x["pitch"] == n["pitch"])
                n["tie"]["end"] = target["id"]


def tie_stops(measures):
    ends = {n["tie"]["end"] for ms in measures for e in ms for n in e["notes"] if n["tie"]}
    return {e["id"] for ms in measures for e in ms if any(n["id"] in ends for n in e["notes"])}


def add_lyrics(measures, verses):
    stops = tie_stops(measures)
    slots = [e for ms in measures for e in ms
             if e["kind"] != "rest" and not e["grace"] and e["id"] not in stops]
    for vn, verse in enumerate(verses, 1):
        sylls = verse.split()
        if len(sylls) > len(slots):
            raise ValueError(f"verse {vn} has {len(sylls)} syllables for {len(slots)} notes")
        cont = False
        for e, s in zip(slots, sylls):
            if s == "_":
                continue
            ext = s.endswith("_")
            s = s.rstrip("_")
            more = s.endswith("-")
            s = s.rstrip("-")
            syl = ("middle" if more else "end") if cont else ("begin" if more else "single")
            e["lyrics"].append({"verse": vn, "text": s, "syllabic": Kw(syl), "extender": ext})
            cont = more


def tune_score(t):
    """The plain model of a tune (load_score's shape, ids only for references)."""
    nmeasures = len(t["parts"][0]["voices"][0]["music"].split("|"))
    measures = []
    for i in range(nmeasures):
        x = t.get("measures", {}).get(i, {})
        m = {"id": None, "number": x.get("number"), "time": x.get("time"), "key": x.get("key"),
             "pickup": None, "length": x.get("length"), "barline": Kw(x.get("barline", "regular")),
             "repeat-start": x.get("repeat-start"), "repeat-end": x.get("repeat-end"),
             "ending": ({"passes": x["ending"][0], "measures": x["ending"][1]} if x.get("ending") else None),
             "jump": [{"kind": Kw(j)} for j in x.get("jump", [])],
             "rehearsal": {"text": x["rehearsal"]} if x.get("rehearsal") else None,
             "tempo": [{"offset": o, "bpm": b, "beat-unit": u, "text": tx} for o, b, u, tx in x.get("tempo", [])]}
        measures.append(m)
    measures[0]["time"] = t["time"]
    measures[0]["key"] = t["key"]
    if t.get("pickup"):
        measures[0]["pickup"] = True
        measures[0]["length"] = t["pickup"]
    score = {"metadata": t.get("metadata", {}), "measures": measures, "parts": [], "anchors": [],
             "spanners": []}
    bt = bars(score)
    parsed = []
    for p in t["parts"]:
        parsed.append([parse_music(v["music"], bt, f"p{len(parsed) + 1}v{k}t")
                       for k, v in enumerate(p["voices"], 1)])
    # A measure whose content isn't its meter's bar (a pickup, the bar that
    # completes it) states its length, as the reader derives it.
    for i, m in enumerate(measures):
        total = max(sum(e["duration"] for e in ms[i] if not e["grace"]) for pv in parsed for ms, _ in pv)
        if total != meter_bar(bt[i][3]):
            m["length"] = total
    bt = bars(score)
    for p, pv in zip(t["parts"], parsed):
        part = {"id": None, "name": p["name"], "abbreviation": p.get("abbreviation"),
                "staves": [{"clef": Kw(c)} for c in p.get("clefs", ["treble"])], "voices": []}
        for v, (ms, sp) in zip(p["voices"], pv):
            assert len(ms) == nmeasures, (t["slug"], v["value"], len(ms), nmeasures)
            for i, events in enumerate(ms):
                total = sum(e["duration"] for e in events if not e["grace"])
                assert not events or total == bt[i][2], (t["slug"], v["value"], i, total, bt[i][2])
            link_ties(ms)
            try:
                add_lyrics(ms, v.get("lyrics", []))
            except ValueError as err:
                raise ValueError(f"{t['slug']}: {err}")
            part["voices"].append({"id": None, "name": None, "staff": v.get("staff", 1), "stem": v.get("stem"),
                                   "value": v["value"], "measures": ms})
            score["spanners"] += sp
        score["parts"].append(part)
    first = bt[0][0]
    for mi, offset, sym in t.get("chords", []):
        score["anchors"].append({"id": None, "bar": first + mi, "offset": Fraction(offset), "symbol": sym})
    return score


def cs(text):
    """A chord symbol in MT3 slots from compact text: "G", "Em", "D7", "Cmaj7",
    "Am7", "Bdim" (the diminished triad), "C7(b9)", "D7sus4", "F/A", "N.C."."""
    if text == "N.C.":
        return {"no-chord-p": True}
    m = re.match(r'^([A-G](?:b|#)?)(m7|maj7|m|7sus4|7|dim|6|9)?(\(b9\))?(?:/([A-G](?:b|#)?))?$', text)
    root, q, b9, bass = m.groups()
    quality, ext, sus = {None: ("major", (), None), "m": ("minor", (), None), "7": ("dominant-7", (), None),
                         "maj7": ("major-7", (), None), "m7": ("minor-7", (), None),
                         "dim": ("diminished", (), None), "6": ("major-6", (), None),
                         "9": ("dominant-7", (9,), None), "7sus4": ("dominant-7", (), 4)}[q]
    sym = {"root": root, "quality": Kw(quality)}
    if ext:
        sym["extensions"] = list(ext)
    if sus:
        sym["suspension"] = sus
    if b9:
        sym["alterations"] = [(9, -1)]
    if bass:
        sym["bass"] = bass
    return sym


# --- the corpus writer: MusicXML as a notation program writes it ------------------

def midi(name):
    letter, alter, octave = parse_pitch(name)
    return 12 * (octave + 1) + LETTER_SEMIS[letter] + alter


def key_alters(key_name):
    """Letter → alter in the key signature."""
    f, _ = key_signature(key_name)
    order = [3, 0, 4, 1, 5, 2, 6]               # F C G D A E B
    alters = [0] * 7
    for i in range(abs(f)):
        letter = order[i] if f > 0 else order[6 - i]
        alters[letter] = 1 if f > 0 else -1
    return alters


def emit_foreign(score, style):
    md = score["metadata"]
    root = E("score-partwise", [("version", style.get("version", "4.0"))])
    if md.get("title"):
        if style.get("title") == "movement":
            root.add(text_el("movement-title", md["title"]))
        else:
            root.add(E("work", [], [text_el("work-number", "1"), text_el("work-title", md["title"])]))
    ident = root.add(E("identification"))
    for k in ("composer", "lyricist", "arranger"):
        if md.get(k):
            ident.add(text_el("creator", md[k], [("type", k)]))
    if md.get("copyright"):
        ident.add(text_el("rights", md["copyright"]))
    ident.add(E("encoding", [], [text_el("software", "generate-sc2.py"),
                                 text_el("encoding-date", "2026-11-24"),
                                 E("supports", [("element", "accidental"), ("type", "yes")])]))
    root.add(E("defaults", [], [E("scaling", [], [text_el("millimeters", "7"), text_el("tenths", "40")]),
                                E("page-layout", [], [text_el("page-height", "1697"),
                                                      text_el("page-width", "1200")])]))
    if md.get("title"):
        root.add(E("credit", [("page", "1")],
                   [text_el("credit-type", "title"),
                    text_el("credit-words", md["title"], [("default-x", "600"), ("justify", "center")])]))
    plist = root.add(E("part-list"))
    hymn = any(len(p["staves"]) > 1 for p in score["parts"])
    if hymn:
        plist.add(E("part-group", [("type", "start"), ("number", "1")],
                    [text_el("group-symbol", "brace")]))
    for pi, p in enumerate(score["parts"], 1):
        pid = f"P{pi}"
        sp = plist.add(E("score-part", [("id", pid)]))
        sp.add(text_el("part-name", p["name"] or ""))
        if p["abbreviation"]:
            sp.add(text_el("part-abbreviation", p["abbreviation"]))
        sp.add(E("score-instrument", [("id", pid + "-I1")], [text_el("instrument-name", p["name"] or "")]))
        sp.add(E("midi-instrument", [("id", pid + "-I1")], [text_el("midi-channel", str(pi)),
                                                           text_el("midi-program", "53")]))
    if hymn:
        plist.add(E("part-group", [("type", "stop"), ("number", "1")]))
    bt = bars(score)
    for pi, p in enumerate(score["parts"], 1):
        root.add(emit_part(score, p, pi, bt, style))
    return document(root, DOCTYPE_31 if style.get("version") == "3.1" else DOCTYPE_40)


def emit_part(score, part, pi, bt, style):
    D = divisions(score, part, pi == 1, bt) * style.get("divisions-factor", 1)
    dur = lambda x: str(int(Fraction(x) * 4 * D))
    two = len(part["staves"]) >= 2
    pel = E("part", [("id", f"P{pi}")])
    spanners = score["spanners"]
    tie_ends = {n["tie"]["end"] for v in part["voices"] for ms in v["measures"] for e in ms
                for n in e["notes"] if n["tie"]}
    nmeasures = len(score["measures"])
    endings_last = {}
    for i, m in enumerate(score["measures"]):
        if m["ending"]:
            endings_last[i + int(m["ending"]["measures"]) - 1] = m["ending"]
    key = score["measures"][0]["key"]
    for i, m in enumerate(score["measures"]):
        bar, start, length, time, _ = bt[i]
        key = m.get("key") or key
        alters = key_alters(key)
        attrs = [("number", str(bar))] + ([("implicit", "yes")] if m.get("pickup") else []) + \
            [("width", str(200 + 10 * i))]
        mel = pel.add(E("measure", attrs))
        if i == 0:
            mel.add(E("print", [], [E("system-layout", [], [E("system-margins", [], [
                text_el("left-margin", "50"), text_el("right-margin", "0")])])]))
        if i == 0 or m.get("time") or m.get("key"):
            a = mel.add(E("attributes"))
            if i == 0:
                a.add(text_el("divisions", str(D)))
            if m.get("key"):
                f, mode = key_signature(m["key"])
                k = a.add(E("key", [], [text_el("fifths", str(f))]))
                if mode == "minor" or not style.get("omit-major-mode"):
                    k.add(text_el("mode", mode))
            if m.get("time"):
                nums, den = parse_meter(m["time"])
                a.add(E("time", [("symbol", "common")] if m["time"] == "4/4" else [],
                        [text_el("beats", "+".join(map(str, nums))), text_el("beat-type", str(den))]))
            if i == 0:
                if two:
                    a.add(text_el("staves", str(len(part["staves"]))))
                for k, st in enumerate(part["staves"], 1):
                    sign, line, octave = CLEFS[str(st["clef"])]
                    c = a.add(E("clef", [("number", str(k))] if two else []))
                    c.add(text_el("sign", sign))
                    c.add(text_el("line", str(line)))
                    if octave:
                        c.add(text_el("clef-octave-change", str(octave)))
        if m.get("repeat-start") or m["ending"]:
            b = mel.add(E("barline", [("location", "left")]))
            if m.get("repeat-start"):
                b.add(text_el("bar-style", "heavy-light"))
            if m["ending"]:
                b.add(E("ending", [("number", ",".join(str(x) for x in m["ending"]["passes"])),
                                   ("type", "start"), ("default-y", "40")],
                        [f"{m['ending']['passes'][0]}."]))
            if m.get("repeat-start"):
                b.add(E("repeat", [("direction", "forward")]))
        cursor = Fraction(0)
        if pi == 1:
            if m["rehearsal"]:
                mel.add(E("direction", [("placement", "above")], [E("direction-type", [], [
                    text_el("rehearsal", m["rehearsal"]["text"], [("font-weight", "bold"),
                                                                    ("enclosure", "square")])])]))
            for j in m["jump"]:
                if j["kind"] in ("segno", "coda"):
                    mel.add(E("direction", [("placement", "above")],
                              [E("direction-type", [], [E(str(j["kind"]), [("default-y", "20")])]),
                               E("sound", [(str(j["kind"]), str(j["kind"]))])]))
            for t in m["tempo"]:
                assert not t["offset"]
                d = mel.add(E("direction", [("placement", "above")]))
                if t["text"]:
                    d.add(E("direction-type", [], [text_el("words", t["text"], [("font-weight", "bold")])]))
                if t["bpm"]:
                    base, dots = duration_dots(Fraction(t["beat-unit"]))
                    d.add(E("direction-type", [], [E("metronome", [("parentheses", "no")],
                        [text_el("beat-unit", TYPE_NAMES[BASES.index(base)])]
                        + [E("beat-unit-dot") for _ in range(dots)]
                        + [text_el("per-minute", decimal(t["bpm"]))])]))
                    d.add(E("sound", [("tempo", decimal(Fraction(t["bpm"]) * Fraction(t["beat-unit"]) * 4))]))
        anchors = [a for a in score["anchors"] if a["bar"] == bar] if pi == 1 else []
        for k, v in enumerate(part["voices"]):
            events = v["measures"][i]
            if not events:
                continue
            if cursor > 0:
                mel.add(E("backup", [], [text_el("duration", dur(cursor))]))
                cursor = Fraction(0)
            shared = sum(1 for w in part["voices"] if w["staff"] == v["staff"] and w["measures"][i]) > 1
            loc = ([text_el("voice", v["value"])] if shared or style.get("dynamics-voice") else []) + \
                [text_el("staff", str(v["staff"]))]
            onsets, at = [], Fraction(0)
            for e in events:
                onsets.append(at)
                if not e["grace"]:
                    at += e["duration"]
            beam_open = False
            for ei, e in enumerate(events):
                if k == 0:
                    for a in list(anchors):
                        later = [o for o in onsets[ei + 1:] if o <= a["offset"]]
                        if onsets[ei] <= a["offset"] and not later and not e["grace"]:
                            h, _ = chord_symbol_to_harmony(a["symbol"])
                            if a["offset"] > onsets[ei]:
                                h.add(E("offset", [], [dur(a["offset"] - onsets[ei])]))
                            mel.add(h)
                            anchors.remove(a)
                if e["dynamic"]:
                    mel.add(E("direction", [("placement", "below")],
                              [E("direction-type", [], [E("dynamics", [("default-y", "-80")],
                                                          [E(str(e["dynamic"]["value"]))])])]
                              + loc + [E("sound", [("dynamics", "80")])]))
                for sp in spanners:
                    if sp["kind"] in ("crescendo", "diminuendo") and sp["start"] == e["id"]:
                        mel.add(E("direction", [("placement", "below")],
                                  [E("direction-type", [], [E("wedge", [("type", str(sp["kind"])),
                                                                         ("number", "1")])])] + loc))
                beam = None
                if e["kind"] != "rest" and not e["grace"] and duration_dots(e["duration"] * (e["tuplet"] or 1)) \
                        and duration_dots(e["duration"] * (e["tuplet"] or 1))[0] == Fraction(1, 8):
                    nxt = events[ei + 1] if ei + 1 < len(events) else None
                    if beam_open:
                        beam, beam_open = "end", False
                    elif nxt and nxt["kind"] != "rest" and not nxt["grace"] and \
                            nxt["duration"] * (nxt["tuplet"] or 1) == Fraction(1, 8):
                        beam, beam_open = "begin", True
                for el in foreign_notes(e, v, two, dur, spanners, tie_ends, alters, beam, events, ei):
                    mel.add(el)
                if not e["grace"]:
                    cursor += e["duration"]
                for sp in spanners:
                    if sp["kind"] in ("crescendo", "diminuendo") and sp["end"] == e["id"]:
                        mel.add(E("direction", [("placement", "below")],
                                  [E("direction-type", [], [E("wedge", [("type", "stop"),
                                                                         ("number", "1")])])] + loc))
        if pi == 1:
            for j in m["jump"]:
                if j["kind"] not in ("segno", "coda"):
                    _, words, attr, value = JUMPS[JUMP_ORDER.index(str(j["kind"]))]
                    mel.add(E("direction", [("placement", "above")],
                              [E("direction-type", [], [text_el("words", words, [("font-style", "italic")])]),
                               E("sound", [(attr, value)])]))
        ending_end = endings_last.get(i)
        if m["barline"] != "regular" or m.get("repeat-end") or ending_end:
            b = mel.add(E("barline", [("location", "right")]))
            if m["barline"] != "regular" or m.get("repeat-end"):
                b.add(text_el("bar-style", BAR_STYLES[str(m["barline"])] if m["barline"] != "regular"
                              else "light-heavy"))
            if ending_end:
                b.add(E("ending", [("number", ",".join(str(x) for x in ending_end["passes"])),
                                   ("type", "stop" if m.get("repeat-end") else "discontinue")]))
            if m.get("repeat-end"):
                b.add(E("repeat", [("direction", "backward")] +
                        ([("times", str(m["repeat-end"]))] if m["repeat-end"] != 2 else [])))
    return pel


def foreign_notes(e, v, two, dur, spanners, tie_ends, alters, beam, events, ei):
    out = []
    notes = e["notes"] or [None]
    for ni, n in enumerate(notes):
        el = E("note", [("default-x", str(80 + 30 * ei))] +
               ([("print-object", "no")] if e["kind"] == "rest" and e["hidden"] else []))
        if e["grace"]:
            el.add(E("grace", [("slash", "yes")] if e["grace"] == "acciaccatura" else []))
        if ni > 0:
            el.add(E("chord"))
        if n is None:
            el.add(E("rest", [("measure", "yes")] if e["measure-rest"] else []))
        else:
            letter, alter, octave = parse_pitch(n["pitch"])
            pe = el.add(E("pitch", [], [text_el("step", LETTERS[letter])]))
            if alter:
                pe.add(text_el("alter", str(alter)))
            pe.add(text_el("octave", str(octave)))
        if not e["grace"]:
            el.add(text_el("duration", dur(e["duration"])))
        if n is not None and n["id"] in tie_ends:
            el.add(E("tie", [("type", "stop")]))
        if n is not None and n["tie"]:
            el.add(E("tie", [("type", "start")]))
        el.add(text_el("voice", v["value"]))
        value = e["duration"] if e["grace"] else e["duration"] * (e["tuplet"] or 1)
        if not e["measure-rest"]:
            base, dots = duration_dots(value)
            el.add(text_el("type", TYPE_NAMES[BASES.index(base)]))
            for _ in range(dots):
                el.add(E("dot"))
        if n is not None and parse_pitch(n["pitch"])[1] != alters[parse_pitch(n["pitch"])[0]]:
            el.add(text_el("accidental", ACCIDENTALS[parse_pitch(n["pitch"])[1]]))
        if e["tuplet"]:
            el.add(E("time-modification", [], [text_el("actual-notes", "3"), text_el("normal-notes", "2")]))
        if n is not None:
            stem = v["stem"] or ("up" if midi(e["notes"][0]["pitch"]) < (71 if v["staff"] == 1 else 50) else "down")
            el.add(text_el("stem", str(stem), [("default-y", "10")]))
        if two:
            el.add(text_el("staff", str(v["staff"])))
        if ni == 0 and beam:
            el.add(text_el("beam", beam, [("number", "1")]))
        nots = E("notations")
        if n is not None and n["id"] in tie_ends:
            nots.add(E("tied", [("type", "stop")]))
        if n is not None and n["tie"]:
            nots.add(E("tied", [("type", "start")]))
        if ni == 0:
            for sp in spanners:
                if sp["kind"] == "slur" and sp["end"] == e["id"]:
                    nots.add(E("slur", [("type", "stop"), ("number", "1")]))
                if sp["kind"] == "slur" and sp["start"] == e["id"]:
                    nots.add(E("slur", [("type", "start"), ("number", "1"), ("placement", "above")]))
            if e["tuplet"]:
                pos = sum(1 for x in events[:ei] if x["tuplet"]) % 3
                if pos == 0:
                    nots.add(E("tuplet", [("type", "start"), ("bracket", "no")]))
                elif pos == 2:
                    nots.add(E("tuplet", [("type", "stop")]))
            arts = [E(ARTICULATIONS[str(a["kind"])]) for a in e["articulations"]]
            if e["breath"]:
                arts.append(E("breath-mark"))
            if arts:
                nots.add(E("articulations", [], arts))
            if e["fermata"]:
                nots.add(E("fermata", [("type", "upright")]))
        if nots.children:
            el.add(nots)
        if ni == 0:
            for ly in e["lyrics"]:
                le = el.add(E("lyric", [("number", str(ly["verse"])), ("default-y", str(-80 - 15 * ly["verse"]))]))
                le.add(text_el("syllabic", str(ly["syllabic"])))
                le.add(text_el("text", ly["text"]))
                if ly["extender"]:
                    le.add(E("extend", [("type", "start")]))
        out.append(el)
    return out


# --- the tunes ---------------------------------------------------------------------
# Public-domain melodies and texts, re-encoded by us (MIT). Where a harmony or a
# second part is given, it is ours. Each entry names the source of the tune and
# the text.


def lead(slug, title, music, key, time, *, pickup=None, lyrics=(), chords=(), measures=None,
         metadata=None, style=None, source=""):
    md = {"title": title}
    md.update(metadata or {})
    return {"slug": slug, "source": source, "key": key, "time": time, "pickup": pickup,
            "metadata": md, "measures": measures or {}, "chords": list(chords), "style": style or {},
            "parts": [{"name": "Voice", "voices": [{"value": "1", "music": music, "lyrics": list(lyrics)}]}]}


def satb(slug, title, s, a, t, b, key, time, *, lyrics=(), pickup=None, measures=None, metadata=None,
         style=None, source=""):
    md = {"title": title}
    md.update(metadata or {})
    return {"slug": slug, "source": source, "key": key, "time": time, "pickup": pickup, "metadata": md,
            "measures": measures or {}, "chords": [], "style": style or {},
            "parts": [{"name": "Choir", "abbreviation": "Ch.", "clefs": ["treble", "bass"],
                       "voices": [{"value": "1", "staff": 1, "stem": "up", "music": s, "lyrics": list(lyrics)},
                                  {"value": "2", "staff": 1, "stem": "down", "music": a},
                                  {"value": "5", "staff": 2, "stem": "up", "music": t},
                                  {"value": "6", "staff": 2, "stem": "down", "music": b}]}]}


F = Fraction
TUNES = [
    lead("amazing-grace", "Amazing Grace",
         "D4:4 | G4:2 B4:8( G4:8) | B4:2 A4:4 | G4:2 E4:4 | D4:2 D4:4 | G4:2 B4:8( G4:8) | B4:2 A4:8( B4:8) | D5:2F",
         "G major", "3/4", pickup=F(1, 4),
         lyrics=["A- maz- ing_ _ grace how sweet the sound that saved a_ _ wretch like_ _ me.",
                 "'Twas grace that_ _ taught my heart to fear, and grace my_ _ fears re- _ lieved."],
         chords=[(1, 0, cs("G")), (2, 0, cs("G7")), (3, 0, cs("C")), (4, 0, cs("G")), (5, 0, cs("G")),
                 (6, 0, cs("Em")), (6, F(1, 2), cs("D7")), (7, 0, cs("G"))],
         measures={0: {"tempo": [(0, 72, F(1, 4), None)]}, 7: {"barline": "final"}},
         metadata={"lyricist": "John Newton", "composer": "Traditional"},
         source="tune New Britain (1829); text John Newton (1779)"),
    lead("greensleeves", "Greensleeves",
         "A4:4 | C5:2 D5:4 | E5:4. F5:8 E5:4 | D5:2 B4:4 | G4:4. A4:8 B4:4 | C5:2 A4:4 | A4:4. G#4:8 A4:4 "
         "| B4:2 G#4:4 | E4:2",
         "A minor", "3/4", pickup=F(1, 4),
         lyrics=["A- las, my love,_ _ you do me wrong, to cast_ _ me off dis- cour- _ teous- ly."],
         chords=[(1, 0, cs("Am")), (2, 0, cs("C")), (3, 0, cs("G")), (4, 0, cs("Em")), (5, 0, cs("Am")),
                 (6, 0, cs("Am")), (7, 0, cs("E")), (8, 0, cs("Am"))],
         measures={8: {"barline": "final"}},
         metadata={"composer": "Traditional"}, style={"version": "3.1", "title": "movement"},
         source="English, 16th century; text from the 1580 broadside"),
    lead("scarborough-fair", "Scarborough Fair",
         "D4:2 D4:4 | A4:2 A4:4 | E4:4. F4:8 E4:4 | D4:2. | r:4 A4:4 C5:4 | D5:2 C5:4 | A4:4 B4:4 G4:4 | A4:2.F",
         "D minor", "3/4",
         lyrics=["Are you go- ing to Scar- bo- rough Fair? Pars- ley, sage, rose- ma- ry, thyme."],
         chords=[(0, 0, cs("Dm")), (1, 0, cs("Dm")), (2, 0, cs("C")), (3, 0, cs("Dm")), (4, 0, cs("F")),
                 (5, 0, cs("C")), (6, 0, cs("Dm")), (6, F(1, 2), cs("C")), (7, 0, cs("Dm"))],
         measures={0: {"tempo": [(0, 92, F(1, 4), "Andante")]}, 7: {"barline": "final"}},
         metadata={"composer": "Traditional"},
         source="English traditional ballad, as printed in the 19th century"),
    lead("oh-susanna", "Oh! Susanna",
         "C4:8 D4:8 | E4:4 G4:4 G4:4. A4:8 | G4:4 E4:4 C4:4. D4:8 | E4:4s E4:4s D4:4 C4:4 | D4:2. C4:8 D4:8 "
         "| E4:4 G4:4 G4:4. A4:8 | G4:4 E4:4 C4:4. D4:8 | E4:4 E4:4 D4:4 D4:4 | C4:2.",
         "C major", "4/4", pickup=F(1, 4),
         lyrics=["I come from Al- a- ba- ma with my ban- jo on my knee, I'm go- ing to Lou- 'si- an- a, "
                 "my true love for to see."],
         chords=[(1, 0, cs("C")), (2, 0, cs("C")), (3, 0, cs("C")), (4, 0, cs("G7")), (5, 0, cs("C")),
                 (6, 0, cs("C")), (7, 0, cs("C")), (7, F(1, 2), cs("G7")), (8, 0, cs("C"))],
         measures={8: {"barline": "final"}},
         metadata={"composer": "Stephen Foster", "lyricist": "Stephen Foster"},
         source="Stephen Foster (1848)"),
    lead("red-river-valley", "Red River Valley",
         "C4:8 F4:8 | A4:4 A4:4 A4:4. G4:8 | A4:4 G4:4 F4:2~ | F4:2 r:4 C4:8 F4:8 | A4:4 F4:4 A4:4 C5:4 "
         "| Bb4:2. A4:8 G4:8 | F4:4 G4:4 A4:4 G4:4 | F4:2.",
         "F major", "4/4", pickup=F(1, 4),
         lyrics=["From this val- ley they say you are go- ing, we will miss your bright eyes and sweet smile, "
                 "for they say"],
         chords=[(1, 0, cs("F")), (2, 0, cs("F")), (3, 0, cs("F")), (3, F(1, 2), cs("C7")), (4, 0, cs("F")),
                 (5, 0, cs("Bb")), (6, 0, cs("C7")), (7, 0, cs("F"))],
         measures={7: {"barline": "final"}},
         metadata={"composer": "Traditional"}, style={"divisions-factor": 4},
         source="North American traditional song, published 1896"),
    lead("home-on-the-range", "Home on the Range",
         "D4:8 D4:8 | G4:4 A4:4 B4:4 | G4:4. F#4:8 E4:4 | C5:2 C5:4 | C5:4. B4:8 C5:4 | D5:2.~ | D5:4 r:4 B4:8 B4:8 "
         "| B4:2",
         "G major", "3/4", pickup=F(1, 4),
         lyrics=["Oh give me a home where the buf- fa- lo roam, where the deer"],
         chords=[(1, 0, cs("G")), (2, 0, cs("G")), (3, 0, cs("C")), (4, 0, cs("C")), (5, 0, cs("G")),
                 (6, 0, cs("G/B")), (6, F(1, 2), cs("D7")), (7, 0, cs("G"))],
         measures={7: {"barline": "final"}},
         metadata={"composer": "Daniel E. Kelley", "lyricist": "Brewster M. Higley"},
         source="Daniel E. Kelley, text Brewster M. Higley (1872)"),
    lead("shenandoah", "Shenandoah",
         "A3:4 | D4:4 D4:4 D4:4. E4:8 | F#4:8 G4:8 B4:4 A4:4 | F#4:2~ F#4:4 r:4 | D5:4 C#5:4 B4:2 "
         "| E4:4 F#4:4 A4:4 | F#4:4 E4:4 D4:2 | D4:2.F",
         "D major", "4/4", pickup=F(1, 4),
         lyrics=["Oh Shen- an- do- ah, I long to hear you, a- way, you roll- ing riv- er."],
         chords=[(1, 0, cs("D")), (2, 0, cs("G")), (3, 0, cs("D")), (4, 0, cs("Bm")), (5, 0, cs("A7")),
                 (6, 0, cs("D")), (6, F(1, 2), cs("A7")), (7, 0, cs("D"))],
         measures={2: {"time": "3/4"}, 3: {"time": "4/4"}, 5: {"time": "3/4"}, 6: {"time": "4/4"},
                   7: {"barline": "final"}},
         metadata={"composer": "Traditional"},
         source="American traditional (sea shanty), 19th century"),
    lead("londonderry-air", "Londonderry Air",
         "Bb3:8 C4:8 D4:8 | {p} Eb4:4. D4:8 Eb4:8 Ab4:8 G4:8 Eb4:8 | G/F4:8 {<} Eb4:4. C4:8 Bb3:4 Bb3:8 C4:8 "
         "| Eb4:4. F4:8 {/} G4:8 Ab4:8 G4:8 F4:8 | {mf} Eb4:2. r:8 Bb3:8 | Eb4:2F r:8",
         "Eb major", "4/4", pickup=F(3, 8),
         chords=[(1, 0, cs("Eb")), (1, F(1, 2), cs("Ab")), (2, 0, cs("Eb/Bb")), (2, F(1, 2), cs("Bb7")),
                 (3, 0, cs("Eb")), (3, F(1, 2), cs("Ab")), (4, 0, cs("Bb7")), (5, 0, cs("Eb"))],
         measures={0: {"tempo": [(0, 60, F(1, 4), "Slowly")]}, 5: {"barline": "final"}},
         metadata={"composer": "Traditional"},
         source="Irish traditional air, printed by George Petrie (1855)"),
    lead("auld-lang-syne", "Auld Lang Syne",
         "C4:4 | F4:4. F4:8 F4:4 A4:4 | G4:4. F4:8 G4:4 A4:8 G4:8 | F4:4. F4:8 A4:4 C5:4 | D5:2. C4:4 | D5:2. r:4",
         "F major", "4/4", pickup=F(1, 4),
         lyrics=["Should auld ac- quain- tance be for- got, and nev- er brought to mind? Should mind"],
         chords=[(1, 0, cs("F")), (2, 0, cs("C7")), (3, 0, cs("F")), (3, F(1, 2), cs("F7")), (4, 0, cs("Bb")),
                 (5, 0, cs("Bb"))],
         measures={1: {"repeat-start": True}, 4: {"ending": ([1], 1), "repeat-end": 2},
                   5: {"ending": ([2], 1), "barline": "final"}},
         metadata={"lyricist": "Robert Burns", "composer": "Traditional"},
         source="Scots traditional tune; text Robert Burns (1788)"),
    lead("silent-night", "Silent Night",
         "F4:4. G4:8 F4:4 | D4:2. | F4:4. G4:8 F4:4 | D4:2. | C5:4 C5:8 A4:4. | Bb4:4. Bb4:4. | G4:4 G4:8 Bb4:4. "
         "| F4:4. D4:4.F",
         "Bb major", "6/8",
         lyrics=["Si- lent night, ho- ly night, all is calm, all is bright,",
                 "Si- lent night, ho- ly night, shep- herds quake at the sight,"],
         chords=[(0, 0, cs("Bb")), (2, 0, cs("Bb")), (4, 0, cs("F7")), (5, 0, cs("Bb")), (6, 0, cs("Eb")),
                 (7, 0, cs("Bb"))],
         measures={0: {"tempo": [(0, 50, F(3, 8), "Andante")]}, 7: {"barline": "final"}},
         metadata={"composer": "Franz Xaver Gruber", "lyricist": "Joseph Mohr"},
         source="Franz Xaver Gruber (1818); English text John Freeman Young (1859)"),
    lead("simple-gifts", "Simple Gifts",
         "C4:8 C4:8 | F4:8 F4:8 G4:8 A4:8 | F4:8 A4:8 Bb4:8 C5:8 | C5:4 Bb4:8 A4:8 | G4:8 F4:8 G4:8 A4:8 "
         "| G4:4 C4:8 C4:8 | F4:4. F4:8",
         "F major", "2/4", pickup=F(1, 4),
         lyrics=["'Tis the gift to be sim- ple, 'tis the gift to be free, 'tis the gift to come down where we ought"],
         chords=[(1, 0, cs("F")), (2, 0, cs("F")), (3, 0, cs("F")), (4, 0, cs("C")), (5, 0, cs("C")),
                 (6, 0, cs("F"))],
         measures={6: {"barline": "final", "length": F(1, 2)}},
         metadata={"composer": "Joseph Brackett"},
         source="Joseph Brackett (1848)"),
    lead("yankee-doodle", "Yankee Doodle",
         "G4:8 G4:8 A4:8 B4:8 | G4:8 B4:8 A4:8 D4:8 | G4:8 G4:8 A4:8 B4:8 | G4:4 F#4:4 | G4:4 G4:4",
         "G major", "2/4",
         lyrics=["Yan- kee Doo- dle went to town a- rid- ing on a po- ny, stuck a"],
         chords=[(0, 0, cs("G")), (1, 0, cs("G")), (1, F(1, 4), cs("D7")), (2, 0, cs("G")), (3, 0, cs("D7")),
                 (4, 0, cs("G"))],
         measures={0: {"repeat-start": True}, 3: {"ending": ([1], 1), "repeat-end": 2},
                   4: {"ending": ([2], 1), "barline": "final"}},
         metadata={"composer": "Traditional"},
         source="American traditional, 18th century"),
    lead("when-the-saints", "When the Saints Go Marching In",
         "r:4 F4:4 A4:4 Bb4:4 | C5:2.~ C5:4 | r:4 F4:4 A4:4 Bb4:4 | C5:1 | r:4 F4:4 A4:4 Bb4:4 | C5:2 A4:2 "
         "| F4:2 A4:2 | G4:1F",
         "F major", "4/4",
         lyrics=["Oh, when the saints, oh, when the saints, oh, when the saints go march- ing in"],
         chords=[(0, 0, cs("N.C.")), (0, F(1, 4), cs("F")), (1, 0, cs("F")), (2, 0, cs("F")), (3, 0, cs("C7")),
                 (4, 0, cs("F")), (4, F(1, 2), cs("F7")), (5, 0, cs("Bb")), (5, F(1, 2), cs("F/A")),
                 (6, 0, cs("F")), (6, F(1, 2), cs("D7")), (7, 0, cs("G7"))],
         measures={0: {"tempo": [(0, 120, F(1, 4), None)]}, 7: {"barline": "final"}},
         metadata={"composer": "Traditional"}, style={"dynamics-voice": True},
         source="African-American spiritual, early 20th-century form"),
    lead("swing-low", "Swing Low, Sweet Chariot",
         "A4:2 F4:4. D4:8 | C4:2. r:4 | F4:4 F4:4 3/F4:8 3/F4:8 3/F4:8 A4:4 | C5:2. r:4 | A4:2 F4:4. D4:8 "
         "| C4:2. r:4 | F4:4 F4:4 3/G4:8 3/F4:8 3/G4:8 A4:4 | F4:2.F r:4",
         "F major", "4/4",
         lyrics=["Swing low, sweet char- i- ot, com- ing for to car- ry me home, swing low, sweet char- i- ot,"],
         chords=[(0, 0, cs("F")), (1, 0, cs("F")), (2, 0, cs("F")), (3, 0, cs("C7")), (4, 0, cs("F")),
                 (5, 0, cs("Bb")), (6, 0, cs("F")), (6, F(3, 4), cs("C7")), (7, 0, cs("F"))],
         measures={7: {"barline": "final"}},
         metadata={"composer": "Wallace Willis"},
         source="African-American spiritual, attributed to Wallace Willis (before 1862)"),
    lead("twinkle-twinkle", "Twinkle, Twinkle, Little Star",
         "C4:4 C4:4 | G4:4 G4:4 | A4:4 A4:4 | G4:2 | F4:4 F4:4 | E4:4 E4:4 | D4:4 D4:4 | C4:2 "
         "| G4:4 G4:4 | F4:4 F4:4 | E4:4 E4:4 | D4:2",
         "C major", "2/4",
         lyrics=["Twin- kle, twin- kle, lit- tle star, how I won- der what you are! "
                 "Up a- bove the world so high,"],
         chords=[(0, 0, cs("C")), (2, 0, cs("F")), (3, 0, cs("C")), (4, 0, cs("F")), (5, 0, cs("C")),
                 (6, 0, cs("G7")), (7, 0, cs("C")), (8, 0, cs("C")), (9, 0, cs("F")), (10, 0, cs("C")),
                 (11, 0, cs("G7"))],
         measures={0: {"rehearsal": "A"}, 7: {"jump": ["fine"], "barline": "final"},
                   8: {"rehearsal": "B"}, 11: {"jump": ["da-capo-al-fine"], "barline": "double"}},
         metadata={"lyricist": "Jane Taylor", "composer": "Traditional"},
         source="French melody Ah! vous dirai-je, maman (1761); text Jane Taylor (1806)"),
    {"slug": "frere-jacques", "source": "French traditional round, 18th century", "key": "F major",
     "time": "4/4", "pickup": None, "metadata": {"title": "Frère Jacques", "composer": "Traditional"},
     "measures": {3: {"barline": "final"}}, "chords": [(0, 0, cs("F")), (1, 0, cs("F")), (2, 0, cs("F")),
                                                       (3, 0, cs("F"))],
     "style": {"omit-major-mode": True},
     "parts": [{"name": "Voice 1", "abbreviation": "V. 1",
                "voices": [{"value": "1", "music": "F4:4 G4:4 A4:4 F4:4 | F4:4 G4:4 A4:4 F4:4 | A4:4 Bb4:4 C5:2 "
                                                   "| A4:4 Bb4:4 C5:2",
                            "lyrics": ["Frè- re Jac- ques, frè- re Jac- ques, dor- mez- vous? dor- mez- vous?"]}]},
               {"name": "Voice 2", "abbreviation": "V. 2",
                "voices": [{"value": "1", "music": "R | R | F4:4 G4:4 A4:4 F4:4 | F4:4 G4:4 A4:4 F4:4",
                            "lyrics": ["Frè- re Jac- ques, frè- re Jac- ques,"]}]}]},
    lead("joy-to-the-world", "Joy to the World",
         "{f} D5:4 C#5:8. B4:16 | A4:4. G4:8 | F#4:4 E4:4 | D4:4. A4:8 | B4:4. B4:8 | C#5:4. C#5:8 | D5:2~ "
         "| D5:4 r:4",
         "D major", "2/4",
         lyrics=["Joy to the world! the Lord is come; let earth re- ceive her King;"],
         chords=[(0, 0, cs("D")), (1, 0, cs("D")), (2, 0, cs("G")), (2, F(1, 4), cs("A7")), (3, 0, cs("D")),
                 (4, 0, cs("G")), (5, 0, cs("A")), (6, 0, cs("D")), (7, 0, cs("D"))],
         measures={0: {"tempo": [(0, 100, F(1, 4), "Allegro")]}, 7: {"barline": "final"}},
         metadata={"composer": "Lowell Mason", "lyricist": "Isaac Watts"},
         source="arranged by Lowell Mason (1839); text Isaac Watts (1719)"),
    lead("camptown-races", "Camptown Races",
         "A4:8 A4:8 F#4:8 A4:8 | B4:8 A4:8 F#4:4 | E4:4s F#4:8 E4:8 | D4:4. r:8 | D4:4a E4:4a | D4:2",
         "D major", "2/4",
         lyrics=["Camp- town la- dies sing this song, doo- dah! doo- dah! doo- dah day!"],
         chords=[(0, 0, cs("D")), (1, 0, cs("D")), (2, 0, cs("A7")), (3, 0, cs("D")), (4, 0, cs("A7")),
                 (5, 0, cs("D"))],
         measures={1: {"jump": ["segno"]}, 2: {"jump": ["to-coda"]},
                   3: {"jump": ["dal-segno-al-coda"], "barline": "double"},
                   4: {"jump": ["coda"], "rehearsal": "Coda"}, 5: {"barline": "final"}},
         metadata={"composer": "Stephen Foster", "lyricist": "Stephen Foster"},
         source="Stephen Foster (1850)"),
    satb("old-hundredth", "Old Hundredth",
         "{mf} G4:2 G4:4 F#4:4 | {<} E4:2 D4:2 | G4:2 {/} A4:2 | B4:1F",
         "{mf} D4:2 D4:4 D4:4 | C4:2 B3:2 | D4:2 F#4:2 | G4:1F",
         "{mf} B3:2 B3:4 A3:4 | G3:2 G3:2 | B3:2 D4:2 | D4:1F",
         "{mf} G3:2 G3:4 D3:4 | C3:2 G2:2 | G3:2 D3:2 | G2:1F",
         "G major", "4/4",
         lyrics=["All peo- ple that on earth do dwell,", "Him serve with mirth, his praise forth tell,"],
         measures={0: {"tempo": [(0, 80, F(1, 2), None)]}, 3: {"barline": "final"}},
         metadata={"composer": "Louis Bourgeois", "lyricist": "William Kethe"},
         source="Genevan Psalter (1551); text William Kethe (1561); harmony ours"),
    satb("hymn-to-joy", "Hymn to Joy",
         "F#4:4 F#4:4 G4:4 A4:4 | A4:4 G4:4 F#4:4 E4:4 | D4:4 D4:4 E4:4 F#4:4 | F#4:4. E4:8 E4:2 "
         "| B4:4 B4:4 C5:4 D5:4 | D5:2 B4:2F",
         "D4:4 D4:4 E4:4 F#4:4 | F#4:4 E4:4 D4:4 C#4:4 | A3:4 B3:4 C#4:4 D4:4 | D4:4. C#4:8 C#4:2 "
         "| G4:4 G4:4 A4:4 A4:4 | A4:2 G4:2F",
         "A3:2 B3:4 D4:4 | D4:4 B3:4 A3:4 A3:4 | F#3:4 G3:4 A3:4 A3:4 | A3:4. A3:8 A3:2 "
         "| D4:4 D4:4 E4:4 F#4:4 | F#4:2 D4:2F",
         "D3:2 G3:4 F#3:4 | D3:4 E3:4 F#3:4 A2:4 | B2:4 G2:4 A2:4 D3:4 | A2:4. A2:8 A2:2 "
         "| G2:4 G3:4 F#3:4 D3:4 | D3:2 G2:2F",
         "D major", "4/4",
         lyrics=["Freu- de, schö- ner Göt- ter- fun- ken, Toch- ter aus E- ly- si- um, wir be- tre- ten"],
         measures={0: {"tempo": [(0, 96, F(1, 4), "Allegro moderato")]}, 4: {"key": "G major"},
                   5: {"barline": "final"}},
         metadata={"composer": "Ludwig van Beethoven", "lyricist": "Friedrich Schiller"},
         style={"version": "3.1"},
         source="Ludwig van Beethoven (1824); text Friedrich Schiller (1785); harmony ours"),
]

# Tallis's Canon (Thomas Tallis, 1567; text Thomas Ken, 1674; harmony ours), the
# hymnal pair: hand-split (four voices) and shared-stem (as a hymnal prints it).
TALLIS = satb("hymn-split", "Tallis's Canon",
              "{mf} G4:2 G4:4 F#4:4 | G4:2 A4:2B | A4:4 B4:4 B4:4 A4:4 | B4:1F",
              "{mf} D4:2 D4:4 D4:4 | G4:2 F#4:2B | F#4:2 G4:4 F#4:4 | G4:1F",
              "{mf} B3:2 B3:4 A3:4 | B3:2 D4:2 | D4:4 D4:4 D4:4 D4:4~ | D4:1F",
              "{mf} G3:2 G3:4 D3:4 | G3:2 D3:2 | D3:4 G3:4 B2:4 D3:4 | G2:1F",
              "G major", "4/4",
              lyrics=["Glo- ry to thee, my God, this night, for light"],
              measures={3: {"barline": "final"}},
              metadata={"composer": "Thomas Tallis", "lyricist": "Thomas Ken"},
              source="Thomas Tallis (1567); text Thomas Ken (1674); harmony ours")


def shared_stems(score):
    """The hymnal layout of a four-voice score: per staff and measure, the two
    voices as shared-stem chords where their rhythms agree (a single note where
    they sing the same pitch), else as two voices."""
    import copy
    out = copy.deepcopy(score)
    part = out["parts"][0]
    voices = part["voices"]
    upper = {1: voices[0], 2: voices[2]}
    lower = {1: voices[1], 2: voices[3]}
    new_lower = {1: [], 2: []}
    for st in (1, 2):
        u, l = upper[st], lower[st]
        u["stem"] = None
        for mi in range(len(out["measures"])):
            ue, le = u["measures"][mi], l["measures"][mi]
            if [e["duration"] for e in ue] != [e["duration"] for e in le]:
                new_lower[st].append(le)
                continue
            merged = []
            for a, b in zip(ue, le):
                if a["kind"] == "rest":
                    merged.append(a)
                    continue
                if a["notes"][0]["pitch"] == b["notes"][0]["pitch"]:
                    merged.append(a)
                    continue
                c = dict(a, kind="chord", notes=b["notes"] + a["notes"])
                merged.append(c)
            u["measures"][mi] = merged
            new_lower[st].append([])
    # Ties: a chord note tied in the hand-split score still ties to its pitch.
    for st in (1, 2):
        lower[st]["measures"] = new_lower[st]
    keep = [voices[0]] + ([voices[1]] if any(new_lower[1]) else []) + [voices[2]] + \
        ([voices[3]] if any(new_lower[2]) else [])
    part["voices"] = keep
    # Ids of merged-away events: spanners and tie ends pointing at a lower voice's
    # event in a merged measure now point at the chord holding that pitch.
    return out


# --- main ----------------------------------------------------------------------------

SC0_NAMES = ["sc0-carol-6-8", "sc0-chords-under-rests", "sc0-jumps", "sc0-key-change", "sc0-keyboard",
             "sc0-omr-result", "sc0-pickup", "sc0-repeats-voltas", "sc0-satb", "sc0-three-verses"]


def write(path, text):
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        f.write(text)


def mxl_fixture(musicxml_text):
    """A compressed archive as other programs write one: deflated entries, a PDF
    rendition listed first, the score in a subdirectory."""
    container = ('<?xml version="1.0" encoding="UTF-8"?>\n<container>\n  <rootfiles>\n'
                 '    <rootfile full-path="pdf/lead-sheet.pdf" media-type="application/pdf"/>\n'
                 '    <rootfile full-path="music/lead-sheet.xml"/>\n  </rootfiles>\n</container>\n')
    buf = io.BytesIO()
    with zipfile.ZipFile(buf, "w") as z:
        info = zipfile.ZipInfo("mimetype", date_time=(2026, 11, 24, 0, 0, 0))
        z.writestr(info, "application/vnd.recordare.musicxml", compress_type=zipfile.ZIP_STORED)
        for name, data in (("META-INF/container.xml", container), ("music/lead-sheet.xml", musicxml_text),
                           ("pdf/lead-sheet.pdf", "%PDF-1.4 placeholder, not read\n")):
            info = zipfile.ZipInfo(name, date_time=(2026, 11, 24, 0, 0, 0))
            z.writestr(info, data, compress_type=zipfile.ZIP_DEFLATED)
    return buf.getvalue()


def main():
    os.makedirs(GOLDEN, exist_ok=True)
    os.makedirs(CORPUS, exist_ok=True)
    entries = []
    lost_rows = []
    for name in SC0_NAMES:
        score = load_score(os.path.join(SC0, name + ".sexp"))
        text, lost = write_score(score)
        path = os.path.join(GOLDEN, name + ".musicxml")
        write(path, text)
        lost_rows.append((name, lost))
        ours, theirs = model_facts(score), m21_facts(path)
        diff_facts(name, ours, theirs)
        entries.append((f"golden/{name}.musicxml", theirs))
    tunes = TUNES + [TALLIS]
    for t in tunes:
        score = tune_score(t)
        path = os.path.join(CORPUS, t["slug"] + ".musicxml")
        write(path, emit_foreign(score, t["style"]))
        ours, theirs = model_facts(score), m21_facts(path)
        diff_facts(t["slug"], ours, theirs)
        entries.append((f"corpus/{t['slug']}.musicxml", theirs))
    shared = shared_stems(tune_score(TALLIS))
    path = os.path.join(CORPUS, "hymn-shared.musicxml")
    write(path, emit_foreign(shared, TALLIS["style"]))
    ours, theirs = model_facts(shared), m21_facts(path)
    diff_facts("hymn-shared", ours, theirs)
    entries.append(("corpus/hymn-shared.musicxml", theirs))
    with open(os.path.join(CORPUS, "amazing-grace.musicxml"), encoding="utf-8") as f:
        archive = mxl_fixture(f.read())
    with open(os.path.join(HERE, "lead-sheet.mxl"), "wb") as f:
        f.write(archive)
    rows = []
    for name, facts in entries:
        body = " ".join(f":{k} ({' '.join(lisp(r) for r in facts[k])})"
                        for k in ("measures", "events", "harmonies", "keys", "times", "tempos"))
        rows.append(f'({lisp(name)}\n  {body})')
    write(os.path.join(HERE, "sc2-facts.sexp"),
          ";; What music21 10.5.2 reads in each golden and corpus file, generated by\n"
          ";; generate-sc2.py. Row shapes are in the script (\"facts\").\n(" + "\n ".join(rows) + ")\n")
    write(os.path.join(HERE, "sc2-lost.sexp"),
          ";; Per SC0 fixture, the LOSSY-CONVERSION WHATs WRITE-MUSICXML signals, in order\n"
          ";; (generate-sc2.py, from the rules of src/writer.lisp).\n("
          + "\n ".join(lisp([n, l]) for n, l in lost_rows) + ")\n")
    print(f"{len(SC0_NAMES)} goldens, {len(tunes) + 1} corpus files, {len(entries)} fact entries")


if __name__ == "__main__":
    main()
