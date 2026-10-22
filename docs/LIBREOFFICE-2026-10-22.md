# LibreOffice compatibility — 2026-10-22

Reviset was checked against actual LibreOffice Calc and Impress saves, including ODS/XLSX round trips, PPTX exports and PDF exports. The tested workflows passed after fixing an opaque-rectangle recognition issue in exported PDFs. This is a bounded compatibility check, not a claim that all Office features or rendering are equivalent.

## Environment and supported routes

The check used the bundled, signature-verified LibreOffice **26.8.1.1**, revision `bf6ef2662401c7d6dce671ab4deb26ee0af3a7c1`, on the current Apple Silicon Mac. Synthetic documents were authored with fresh private profiles, disabled macros, isolated temporary directories and the renderer sandbox. Production font configuration was used for the qualifying Impress exports.

| Workflow | Observed result |
| --- | --- |
| Calc FODS → ODS → XLSX → ODS, two independent versions | Six real saves; extraction, comparison, history, reopening and original-byte export checks passed |
| Impress ODP → PPTX | Both `Impress Office Open XML` and `Impress MS PowerPoint 2007 XML` filters preserved the tested content and produced working previews; four checks passed |
| Impress PPTX → PDF | Korean text, table content, strike-through and opaque-cover evidence verified |
| PPTX → PDF → PPTX version history | Both numeric edits `100 → 120 → 140` detected; missing hidden-slide observations remain explicit |
| Same-version PPTX plus exported PDF | Two visible pages qualified as reference pairs |
| Direct ODP import | Unsupported; save as PPTX or export PDF in Impress before importing |

The filter names above follow LibreOffice's [official conversion-filter documentation](https://help.libreoffice.org/latest/en-GB/text/shared/guide/convertfilters.html). Both tested PPTX filters emitted transitional 2006 OOXML; strict OOXML compatibility is not implied.

## Calc results

**154 assertions passed:** 135 extraction/diff/query/reopen/immutability assertions and 19 mixed-format history/export assertions. Four actual CLI analyses covered three same-format histories and one history of the same content across save formats. Tests included Korean and multiline text, numbers, zero, booleans, dates, formulas and saved values, formula-to-constant changes at an unchanged value, merged cells, hidden rows/columns/sheets, basic styles, inserted rows and inferred row moves. Exported originals retained their hashes.

The first harness run passed 132 of 135 assertions. The other three expected cell changes for an unmatched inserted row, while the documented contract emits `row_correspondence` with `needs_review`. The corrected assertions require that category, uncertainty, address, value and missing-before evidence. Original failures were retained and the revised expectations received independent review; no product change was needed for Calc.

Calc itself changed boolean literals to `of:=FALSE()` / `of:=TRUE()` formulas during XLSX-to-ODS saving. Reviset reports that saved-source change. ODS ISO dates and XLSX numeric date serials, formula dialects and cross-format styles are not assumed semantically identical. Such comparisons can require review. Reviset reads saved formula results; it does not recalculate the workbook.

## PDF issue found and fixed

LibreOffice can start a rectangle halfway along an edge, emit redundant collinear segments and return explicitly to the start before closing the path. Reviset previously recognized only one compact rectangle encoding. A real opaque white cover therefore remained `uncertain`, with its text suppressed and comparison withheld, instead of producing an inferred occlusion event.

The repair accepts a bounded, finite, single M/L/Z contour when its monotonic edge runs prove a simple axis-aligned rectangle. It rejects multiple buffers or contours, curves, diagonals, reversals, concavity, repeated windings and oversized paths. Existing opacity, transform, mask and clipping checks still apply. Matching the pinned PDF.js renderer's single-buffer behavior prevents inventing coverage by concatenating buffers.

The real export now retains `COVERED SECRET 42` as source evidence, classifies it as `occluded`, excludes it from visible/comparison text and emits `text_occluded` with an **inferred** assessment. Strike-through remains `struck_inferred`. Neither proves an author's deletion intent. PDF table structure also remains inferred; original PPTX cell identity is not guaranteed after export.

New document reports include `pdf_rectangle_path_policy=single-axis-aligned-rectangle-v2` in their identity. Engine `0.4.0-native.bundle.53` and schema `0.4.0` remain unchanged because matching/diff dispatch did not change. Stored reports are not rewritten. Office preview caches contain converted bytes and native OCR caches contain raw observations; current visibility is evaluated separately.

An earlier authoring control omitted production font configuration and produced missing Korean plus a corrupt text layer. Screenshots, font/ToUnicode inspection and an independent PDF extractor confirmed the bad export. Repeating the export with the production font configuration produced readable Korean and correct text. The failed exports remain negative controls; they were not counted as successful compatibility results.

## Execution and review scope

| Check | Exact execution source | Result |
| --- | --- | --- |
| Calc authoring and 154 assertions | `635a7953ba68e9ebb54081a496c5381f92b62701` | Passed |
| Eight affected integration files, including native OCR and historical replay | `f911f1102a7cd76c1649fedd080795a130e17fca` | 104 passed in 306.66 seconds |
| Final single-buffer repair, type checking and five rectangle regressions | `569b21164d3d9ab23ef0f843d8d61927e464d6a6` | Passed |
| New native app | Clean runtime `8364e3d9d67f2ed4ed5ffa3d58ce50e1313ab93e` | Six native launches and five MCP sessions passed; 20 captures inspected |
| Parser-reaching curve controls and TypeScript checking | `f3a66bc418abb4f3c69866bca4819e849ec27eae`; all three TypeScript files are byte-identical at final runtime | Five passed; type checking passed |
| Strict Swift compilation | All ten Swift source hashes match final runtime | Passed with warnings treated as errors; fixed-byte execution before the final commit |

The final local app is **`release/Reviset-LibreOffice-3.app`**, built from clean source `8364e3d9d67f2ed4ed5ffa3d58ce50e1313ab93e` without the optional host-bound sidecar. Native fresh analysis and exact-report reopening passed for Calc, mixed PPTX/PDF history and the dedicated PDF visibility pair: **six launches**. **Five MCP sessions** covered the three new reports and old/new packaged reads of an unstamped legacy report. All **20 captures** were inspected, including the four document history selections. The formerly failing captures now display the expected Revenue140/Revenue120 source pages and matching evidence without a loading placeholder.

Original inputs, stored report bodies, copied legacy libraries and protected earlier apps retained their hashes. New document reports carry the new rectangle policy; legacy report/history/range responses remained byte-identical. Strict app signature verification passed. These checks establish **SOURCE_READY / same-Mac PRIVATE_PACKAGE_READY** within this scope.

An initial native validator assumed the MCP report summary always contained the full environment. The default response budget explicitly omitted that field; increasing the requested budget exposed the expected policy. The validator now checks immutable stored metadata and respects explicit response omissions. Failed-run evidence was preserved.

A second run exposed a timing error in the native smoke harness: its wait could finish before the scheduled history query started, then inspect state during the reload. A diagnostic replay of the exact stored report showed the correct page selection and completed 27 ms after the old assertion point. The harness now observes an actual loading cycle and waits for the same complete change/occurrence/page predicates with a bounded timeout. The app's selection model and user-facing navigation were unchanged. This repair strengthens the runtime check rather than qualifying the failed run.

The subsequent app passed all six functional launches and five MCP sessions, but two history captures still showed a PDF loading indicator. A second smoke-only correction therefore waits for the actual visible PDF/structure view to match the selected source and page before capturing, with a bounded timeout and a final selection check. Model readiness alone does not establish rendered-page readiness. Mounted source identity also does not universally prove rasterization or the absence of overlays; every final capture is inspected separately. The final visual result is recorded separately from the mounted-view check.

A separate controlled historical fixture was produced by the old packaged c09 engine with two nonempty human bundle decisions. Access to the old producer used an explicitly recorded export-only in-memory harness; it was not an unmodified app launch. Actual unmodified old/new bundled MCP processes then returned identical tool-result bytes across 17 paged responses each, covering report, decisions, history, range-net and source pages. Complete stored report bodies, input assets and libraries were preserved. This validates historical association representation/readability, not a native human-confirmation gesture or the correctness of the association. The final App3 qualification explicitly matches the five relevant backend files (Node, bridge, MCP, PDF.js main and worker) to the previously exercised candidate569 package; the controlled human-report result is carried forward through those exact bytes.

Independent code and architecture lanes reviewed the complete four-file source diff from `635a7953ba68e9ebb54081a496c5381f92b62701` to `8364e3d9d67f2ed4ed5ffa3d58ce50e1313ab93e`: **APPROVE / CLEAR**. Claude identified the split-buffer risk, weak curve controls and capture timing gaps; the concrete findings were repaired and re-reviewed. Grok independently reviewed rectangle recognition, provenance and historical compatibility. External source verdicts do not qualify app pixels or universal rendering fidelity. Raw invocations, immutable scopes and finding dispositions are retained separately in the local evidence directory.

The earlier 370-test full-suite run remains tied to `568fc97`; it was not rerun or relabelled as a full-suite result for this repair. Detailed argv, source hashes, raw outputs, original failed controls and fixed-report evidence are preserved under local `.omx/artifacts/libreoffice-compat-20261022/`. That directory and generated app bundles are excluded from the public source repository.

## Remaining boundaries

This run used small synthetic inputs. It does not add a maximum-size workbook/deck qualification, formula recalculation, macros, external-data refresh, advanced chart/pivot fidelity or direct ODP support. Complex or unprovable PDF visibility remains uncertain. Universal OCR accuracy, strict PowerPoint rendering fidelity, OS gestures/VoiceOver, another Mac, notarization and a public installer remain outside this qualification.
