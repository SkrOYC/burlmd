# G001 reference approval

The epic lead independently inspected the private G001-only capture before
proposal generation and approved its state: the pre-G004 `Welcome.md` tab and
plus control remain, no emulated platform chrome appears, and the GTK HeaderBar
is host-owned. The approved PNG has SHA-256
`af4ce587e7ad9470bdc2cc9e28c711c03c2b09521e9a48a920664e8dc4d66981`.

Reviewed Stage 3 commit `a88e1f6a8b1d3998127a6a3213104d4f76c539e6`
authorizes this reference-establishment procedure. Implementation commit
`4ea6139a0c996fc8e80a2b1ead58511deaf671d6` contains the approved reference
and the G001 code. No production typography, pixel tolerance, or comparison
mask was changed to imitate a historical reference.

Both retained non-writing runs used that immutable implementation commit and
exited 0. Each passed 356 Flutter tests, clean Dart analysis, and a zero-pixel
comparison over 1,769,076 product pixels. The lead independently repeated the
committed-source command and observed exit 0 and zero changed product pixels.

The provenance, snapshots, and images are byte-preserved copies of their QA
outputs. Transcripts use lossless `gzip -n` compression to preserve tool-emitted
trailing whitespace without treating it as authored-source formatting. Each
decompressed transcript was compared byte for byte with its original QA file.
Paths beginning with `.qa/` inside the records are historical. Retained copies
have the same basenames here, with `.gz` appended for compressed transcripts.

Run 1's original transcript has 79,272 bytes and SHA-256
`eda14322d3b16bf84fbc09aea883e8cb2239dd18af1c7abcafab836cf58cbeea`.
Run 2's original transcript has 79,792 bytes and SHA-256
`07a907b9387a0a480dbeeae048c23986b581d9dabb6f9b678fbc437992f45e0a`.
Each of the three original Fontconfig diagnostic files has 17,904 bytes and
SHA-256 `f839b4ca169fb4588c0a1afe8f87e2d930cd5a037e531f71c36ab245a106fec6`.

Fontconfig warnings are recorded, not a proven explanation of the historical
mismatch. This is private Linux milestone evidence, not platform, performance,
packaging, or supported-release qualification.
