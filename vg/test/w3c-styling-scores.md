# W3C styling chapter — baseline scores (2026-07-19)

`AEVG_SIZE=400 python3 vg/test/svg-compare-aevg.py --svg-dir vg/test/w3c-styling`
MAE vs librsvg; good <20, ok <40.

| test | MAE | verdict |
|---|---|---|
| styling-css-09-f (case-sensitivity) | 2.6 | good |
| styling-pres-01-t (presentation-attr vs CSS priority) | 3.6 | good |
| styling-css-06-b | 4.2 | good |
| styling-css-05-b | 4.6 | good |
| styling-css-03-b (descendant-ish rules) | 6.2 | good |
| styling-class-01-f (class attribute) | 6.4 | good |
| styling-css-01-b (type selectors) | 8.0 | good |
| styling-css-02-b (class selectors) | 8.0 | good |
| styling-css-10-f | 8.4 | good |
| styling-pres-02-f | 9.5 | good |
| styling-inherit-01-b (inheritance) | 12.5 | good |
| styling-css-07-f | 13.0 | good |
| styling-css-08-f | 28.5 | ok |
| **styling-css-04-f (cascade/specificity)** | **133.8** | **diff — the named gap** |

The one red is the SPECIFICITY test — grammar_css documents "no specificity
computation" (rules merge in declaration order), so this is the known gap
made measurable, not a surprise. styling-css-08-f's "ok" is worth a look
when someone is next in grammar_css. Per the conformance-house-rule: don't
grind individual files; this table is the gap list.
