# Document processing limits

Document engine `0.4.0-native.bundle.57` records its extraction policies in each report's `observation_environment`. Existing reports retain their original engine and evidence. Engine55/56 range comparisons use the frozen55 diff implementation.

These limits bound Reviset's own extraction and visibility work. They do not establish a complete CPU/RSS guarantee for PDF.js, platform frameworks or every external processor.

| Surface | Page or part limit | Document limit |
| --- | --- | --- |
| PDF source text | 100,000 items; 2 million UTF-16 units | 500,000 items; 20 million UTF-16 units |
| PDF appearance work | 8 million work units; 25,000 unique evidence entries | 128 million work units; 500,000 unique evidence entries |
| PPTX slide references | 1,000 unique slide targets; unique slide and relationship IDs | Preflight runs before reading slide bodies |
| PPTX XML parsing | 8 MiB per parsed part | 128 MiB cumulative parsed XML; 2 million XML nodes |
| PPTX observations | 25,000 elements; 2 million text units; 500,000 notes units | 500,000 elements; 20 million text units; 5 million notes units |

Additional glyph, region and parsed-text counters are defined in [pdf-glyphs.ts](../packages/ingest/pdf-glyphs.ts), [pdf.ts](../packages/ingest/pdf.ts) and [pptx.ts](../packages/ingest/pptx.ts). Repeated part reads are charged again; repeated slide targets are rejected. Valid decks with 1,000 distinct slides have a regression check.

Appearance policy v2 retains the 128 million document work budget. Its spatial candidates preserve painter order and exact overlap predicates, including embedded glyph ink extending beyond advance metrics; broad regions are stored once. Document glyph/evidence limits are 4 million each. Calibration covers an actual embedded-font 300-page PDF with 900,000 glyph spans, plus the same real PDF.js operators repeated for 1,000 pages (114,266,000 work units, 3 million spans). This is extraction/visibility validation, not qualification of every possible 1,000-page report, native layout or OCR workload.

If PDF appearance work exceeds its budget, source text remains available as **unverified**, with `appearance_budget_exceeded_visibility_unverified` in coverage. A prior partial visibility conclusion is cleared. Source-text or PPTX admission failures produce typed errors and failed/partial extraction; they cannot establish that content was deleted.

Native document change lists carry at most 100 preview rows and 1 MiB per page. Their continuation belongs to the fixed project, report, endpoints, mode and filters. Selected complete changes arrive in 128 Ki UTF-16 chunks and are verified before evidence is installed. A single selected event above 128 Mi UTF-16 units has an explicit limit error; use the bounded MCP component readers or export. One-shot helpers still reload the immutable report for later pages/chunks, so exceptionally large events incur extra I/O.

The macOS PDF source preview disables document actions, external link dispatch and direct dropped-file replacement. It remains a platform PDFKit viewer, not a separately sandboxed PDF parser. Model-owned navigation and per-pane zoom remain available.
