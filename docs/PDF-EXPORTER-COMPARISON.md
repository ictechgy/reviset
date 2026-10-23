# Comparing PDFs from different exporters

A PDF exported by PowerPoint and a PDF exported by LibreOffice can express the same visible text with different text runs, paint order, glyph advances and drawing paths. They can also differ visibly because of fonts, wrapping, shadows or unsupported objects. Reviset keeps those observations separate from an author's semantic edits.

## Text-run comparison

Document engine `0.4.0-native.bundle.55` adds policy `observed-glyph-run-boundaries-v1`. It runs only on a resolved pair of PDF pages with available, fully readable observed source text. It correlates every non-whitespace source character with an available visible glyph span, orders those spans spatially and compares characters and boundaries. Raw source strings, run IDs, source references, search contents and glyph observations are never rewritten.

Explicit spaces inside a source run remain significant. At a run boundary, near-touching glyph advances can establish a join and a clear gap can establish a separator. The uncertain interval is rejected. Corresponding rows and glyph positions must remain within the declared local tolerances. Numbers, punctuation, signs, units, duplicates and their order remain significant. This is a bounded comparison of observations, not proof that a particular exporter caused a difference.

When the checks succeed but the original comparison strings differ, the change list retains `pdf_source_run_layout_equivalent` with both original page strings and source evidence. It withholds the page-wide and regional semantic `text_modified` claim for that pair. Actual native pixel differences remain separate `visual_region_changed` observations, carrying `pdf_visual_difference_without_text_change`: font/export/layout differences, actual graphic or style edits and unresolved text edits are all possible causes. Sibling withheld-text gaps remain significant; absence of a text-modified event does not establish unchanged wording. The app explains both reasons, and MCP clients receive the same report and evidence.

The checks reject unresolved/estimated geometry, OCR participation, annotations overlapping the text, non-visible or struck text, incompatible row boundaries, unsupported direction/rotation, ambiguous joins and overlapping glyphs. Every element contributing to the compared string must be covered, including inferred table cells that retain observed PDF text. The bounded proof admits at most 4,096 total observations, 256 annotation carriers/region-evidence entries, 2,048 source runs and 32,768 UTF-16 source units/glyph spans per page. Annotation intersection checks use only the bounded carrier set. A rejected comparison retains the existing comparison/uncertainty path; it is not declared equivalent. Rewrapping across different rows, ligatures with incompatible mappings, missing ToUnicode information, arbitrary bidi text and every exporter/font combination are not universally resolved.

## Original and reference authorities

A supplied same-version PDF is retained byte for byte. A qualified or explicitly reviewed PPTX/PDF association can use that PDF as appearance evidence while retaining the PPTX's structure, notes and source identity. The association does not certify PowerPoint fidelity. PDF-only input remains supported; it does not reconstruct absent PPTX structure or prove why two rendered screens differ.

Producer/Creator metadata is not an equality or causality signal. Source text is untrusted quoted data. No formula, macro, external link or document instruction is executed by this comparison.

## Historical reports

Engine 54's complete diff is archived unchanged in `packages/diff/legacy-bundle-54.ts`. Historical engine-54 history, directed range results, endpoint IDs and evidence use that kernel; reanalysis creates a new report under engine 55. Engine 53 and older archived kernels retain their own dispatch. Stored manual same-version PDF associations remain accepted for engines 53, 54 and 55. Visible-layout equivalence does not suppress an independently changed hidden text layer: a normalized change in suppressed text retains its own raw_text_changed_in_suppressed_layer warning. Unchanged hidden text does not acquire that warning merely because visible runs were split.

## Validation scope

The reproducible local harness is `scripts/verify-exporter-comparison.ts`. It checks pinned upstream PowerPoint references against preserved LibreOffice exports of the exact same ten source decks, with 26 pages, and separately checks actual locally authored PDF numeric/spacing controls. Upstream fixture bytes remain in the private validation cache and are not redistributed. Its compact-character diagnostic is not the product equivalence predicate and is not an accuracy score. Public replay runs deny networking and source writes; raw observations, input hashes and failed attempts stay in the local evidence archive.

The earlier [PowerPoint reference measurements](QUALITY.md#powerpoint-독립-참조) retain their original snapshot and pixel-fidelity limitations. Eliminating a false text edit does not make LibreOffice render pixel-identical to PowerPoint, resolve all existing coverage gaps or establish universal OCR accuracy.
