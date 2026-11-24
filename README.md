# score-backend-musicxml

Reads and writes MusicXML 4.0 partwise, plain (`.musicxml`) and compressed (`.mxl`), for [score-protocol](https://github.com/egao1980/score-protocol). XML goes through [xml-protocol](https://github.com/egao1980/xml-protocol) (the DOCTYPE is written, never fetched), archives through [compression-protocol](https://github.com/egao1980/compression-protocol), and chord symbols are [music-theory](https://github.com/egao1980/music-theory) values.

**Status:** SC2 (0.1.0) and the 0.1.1 bug fixes implemented: a slur or wedge stop closes the open spanner of its number in its own voice first (#3), and once a staff splits, `split-voices` splits its unison and rest measures too (#4). The exact rules are in the file headers under `src/`, and the Rove suite under `tests/` is the spec. The design is in the capability brief [cl-stack/docs/capabilities/score.md](https://github.com/egao1980/cl-stack/blob/main/docs/capabilities/score.md).

| Function | Does |
|----------|------|
| `read-musicxml` source `&key split-voices unsupported` | MusicXML (a pathname, the text, UTF-8 octets or a stream) → a score |
| `write-musicxml` score `&optional destination` | score → MusicXML 4.0 text, byte-stable, ids as `id` attributes |
| `read-mxl`, `write-mxl` | the same through a `.mxl` archive (`META-INF/container.xml`) |
| `musicxml-to-score`, `score-to-musicxml` | the same on xml-protocol documents |
| `harmony-to-chord-symbol`, `chord-symbol-to-harmony` | `<harmony>` ↔ music-theory chord symbol |
| `split-voices` | hymnal layout: shared-stem chords on a staff → two voices |

Loading the system registers the serdes-protocol formats `:musicxml` and `:mxl`. Content outside the model signals `musicxml-unsupported` with a `skip-element` restart, or is dropped with `:unsupported :warn` / `:skip`.

```sh
cl-repo test --system score-backend-musicxml
```

The XSD tests run `xmllint` when `MUSICXML_XSD` names a local copy of the MusicXML 4.0 `musicxml.xsd` with `xml.xsd`, `xlink.xsd` and `catalog.xml` beside it (github.com/w3c/musicxml, `schema/` at tag v4.0); otherwise they are skipped. CI's `xsd` job fetches those four files, checks their SHA-256 values and runs them on Ubuntu; the schema is not in this repository (W3C Community Final Specification Agreement). Fixtures and their provenance: [tests/fixtures/PROVENANCE.md](tests/fixtures/PROVENANCE.md).

## License

MIT, see [LICENSE](LICENSE).
