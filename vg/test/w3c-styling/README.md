# W3C SVG 1.1 (2nd Ed) styling chapter — vendored conformance corpus

The 14 `styling-*` tests from the official W3C SVG 1.1 Second Edition test
suite (https://www.w3.org/Graphics/SVG/Test/20110816/), vendored verbatim —
each file carries its W3C copyright header, per the W3C Test Suite License.

Why: the 208-file main corpus is a real-world grab-bag in which only FOUR
files use `<style>` CSS at all, so the vg CSS engine (grammar_css selector
parsing + grammar_style cascade/inheritance) was nearly untested. This
chapter is CSS-in-SVG conformance material: type/class selectors, cascade
specificity, presentation-attribute-vs-CSS priority, inheritance.

Score with the existing parity harness:

    AEVG_SIZE=400 python3 vg/test/svg-compare-aevg.py --svg-dir vg/test/w3c-styling

Reds here are a NAMED GAP LIST for grammar_css/grammar_style (it documents
"no specificity computation, no nesting"), not a regression bar — see
vg/test/w3c-styling-scores.md for the current baseline.
