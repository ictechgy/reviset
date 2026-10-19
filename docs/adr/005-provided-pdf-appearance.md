# ADR-005: supplied-PDF appearance with separate source observations

Status: implemented in the working engine50 candidate; qualification and source review are recorded in PROGRESS.md. Product completeness remains open.

A supplied PDF can preserve a user's export more faithfully than rerendering a PPTX with a different application. It does not establish that the PDF was exported from that exact source. The source PPTX, supplied PDF, slide/page association and visible pixels therefore remain separate observations.

## Contract

- Cache raw parse observations by input content SHA256 and format within an analysis. Clone on cache write/read before enriching an occurrence. Retain original bytes in the content store and verify them before deferred conversion. A file changing between identity capture and ingest aborts analysis with `SOURCE_CHANGED`; it does not commit a partially mismatched timeline.
- Evaluate the complete timeline before qualifying bundles. A supplied PDF SHA256 paired with more than one distinct PPTX SHA256 fails automatic reference qualification in every such occurrence. A different PDF byte hash is not proof of a fresh export.
- The first automatic path requires complete one-to-one coverage of visible slides and supplied PDF pages, unique accepted matches with score at least0.95, nonempty case-sensitive NFC/whitespace-compacted source/PDF text equality, no unresolved/raw-vs-selected PDF text conflict, relative aspect-ratio error at most0.001, and a verified native PDFKit raster. An existing `bundle_inconsistent` result also rejects qualification. Rotated PDFs currently fall back for review. Empty/photo/duplicate/partial exports can conservatively fail this path.
- A qualified primary page gets an optional `appearance` annex pointing to the exact supplied PDF asset, page ID/number, transform and raster. Its association is `inferred`. Keep PPTX elements, text, notes and hidden state. Never copy reference pixels into `Page.raster` or promote the relation to an exact matching anchor.
- Skip LibreOffice conversion only for a fully qualified bundle. Otherwise retain its established conversion/structure fallback. Hidden slides remain source observations; a hidden slide without an exported counterpart can have no rendered preview.
- `reference_appearance_policy` on each new revision means the new eligibility policy was **evaluated**, including a rejected or PDF-only revision. It is not a qualification verdict. This marker must also exist on rejected bundles: its absence selects historical display resolution, which would otherwise bypass the new rejection guard. Only an actual page annex authorizes new reference display. Reports without the marker retain their old display policy.

## Comparison and evidence

The standalone headless `DocverVision` CLI already captures canonical PDFKit pixels for the Node engine. The SwiftUI viewer does not create canonical observations. Its environment fingerprint hashes helper metadata including helper binary/version, OS/build, fonts and rendering settings. Native rasters now also record CropBox, actual rotation and the300DPI/max4096/source-color-profile policy. Source/default color profiles are not claimed to be normalized to a single RGB profile; exact PDF asset hashes retain the original profiles.

Compare renderer name, box, rendering policy, rotation and complete environment fingerprint. Missing/unverified metadata is a page-specific gap. Two present incompatible environments produce an interval gap. Read-only MCP/query/export reads stored observations and never invokes a renderer.

- Different reference pixels with unchanged PPTX bytes are a review gap (`reference_pdf_changed_without_pptx_source_change`), not an asserted PPTX visual edit. Preserve both PDF hashes and page evidence.
- Changed PPTX bytes with identical reference pixels also require source review. A visually identical PDF does not prove that an OOXML edit was absent.
- Comparable differing pixels associated with changed sources can produce an inferred visual event. Cite actual PDF asset/page/render hashes. Source text edits continue to use OOXML evidence independently of reference pixels.
- The report schema checks same-revision PDF identity, transform, raster and accepted mapping, and rejects qualified references reused against different PPTX assets across revisions. New annotations are additive optional schema0.3.0 fields with a new schema hash; canonical engine identity is `0.3.0-native.bundle.50`.
- The native page picker keeps primary source slide IDs. Selecting PDF visual evidence resolves to the primary slide whose appearance points to that PDF page. Display origin and association remain visible. Count provided-PDF pages separately from converted pages or missing previews.

## Historical behavior

Archive the exact44/45 matching, diff and directed-range kernels before changing current appearance behavior. Old45 retains occurrence-canonical net IDs; old44 retains raw-selector IDs. Golden fixtures generated by immutable native49 code cover complete events, IDs and evidence for both versions, continuation/branch cases and four selector combinations. Shared helper modules are unchanged in this candidate; future helper changes must preserve their historical behavior or archive their imports as well.

## Deliberate limits

Automatic association is not authenticated export provenance or universal PowerPoint pixel equivalence. Manual same-version pairing, partial-bundle correction, explicit draft ungrouping, independent standalone PPTX rendering parity and broader automatic qualification remain separate product work. Adjacent timeline mapping guards remain unchanged. No proprietary embedded reference fonts are extracted or redistributed.

## OCR experiment disposition

An isolated research folder tested official PaddlePaddle Korean/English PP-OCRv5 ONNX weights with pinned upstream commits/digests and Microsoft ONNX Runtime1.30.0 CPU binaries. Installation hooks were skipped; model inference denied network access. This is not a product dependency.

All480 current production PDFKit raster hashes matched. Fixed crops used429 native observed line boxes and480 visible-ink bounds of previously inspected, single-line synthetic fixtures, without truth in inference. English visible-ink recognition read310correct/163incorrect/7empty; Korean296correct/184incorrect. They contradicted49/45 respectively of218 previously correct selections. Two-model agreement still accepted42false results among321; a posthoc0.99 threshold accepted10false among84. The resize experiment approximated OpenCV interpolation with the existing canvas library and is not an official upstream benchmark or blind holdout.

Reject unconditional replacement and consensus promotion. Keep raw research outputs, known failures and model provenance; the production OCR selection policy remains unchanged. The current canonical480-case result is still218correct/22nonempty-not-full-truth/240empty. This is a measured correlated corpus, not a universal accuracy bound.
