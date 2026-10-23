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

### Recorded qualification, 2026-10-23

The implementation was qualified at commit `b3f556a615f88dd892f8fc61f77e8e429e262c6c`. The complete integration suite ran at the earlier implementation commit shown below; it is not presented as a full-suite run of the final commit. The subsequent fixes received focused regression tests, public-fixture replay and code/architecture review.

| Check | Source snapshot | Result and scope |
| --- | --- | --- |
| Complete integration suite | `4989296f6babc9e9108fc40a7136b723d710291c` | 456 passed, zero failures or skips; TypeScript check passed. Tracked sources stayed unchanged during the run. |
| Final exporter regressions | `b3f556a` | 10 passed, zero failures or skips; TypeScript check passed. Covers significant character/space changes, table-cell coverage, independent hidden-layer changes, conservative rejection, admission limits and archived engine-54 query parity. |
| Existing PowerPoint/LibreOffice PDF pairs | `b3f556a`, compared with `78df903` | Ten decks, 26 pages: false text-edit events fell from two to zero; all 26 automatic page matches remained. All 27 pre-existing uncertainty-event payloads remained byte-identical. Two new run-layout explanations were added. |
| Actual authored PDF controls | `b3f556a` | Four passed: a split run with unchanged `100` produced no text edit; `100 → 101` with and without a split, and `1 00 → 100`, retained a text edit. |
| Final native macOS app | `b3f556a` | Build and strict local signature verification passed. Two three-version PDF projects passed fresh analysis and reopening, four launches total. The Korean explanation and numeric-change views were visually inspected. |
| MCP inside that app | `b3f556a` | 74 positive-case calls passed, checking original strings, change/history evidence and project scope. Another 54 calls checked uncertainty in a preserved report extracted at `4989296`; those calls are not a new extraction or an accuracy pass. |

The subsequent UI closure at `28283c5adda503ce47687bb77a4a28297e720ada` removes wording-change highlights and their caption from visual events carrying `pdf_visual_difference_without_text_change`. Its rebuilt native app passed four fresh-analysis/reopen launches and 74 bundled MCP calls; 54 additional calls again queried the preserved `4989296` negative report without claiming new extraction or accuracy. A separate inspector harness compiled from the same final Swift sources rendered that app's actual report: the selected visual event retained both raw strings without red/green wording emphasis or its caption, while an actual `100 → 101` text edit retained both. Both opaque captures were visually inspected. This harness is not OS mouse/keyboard or VoiceOver coverage. All 72 engine/harness files used for the B3 public replay remained byte-identical; no new full-suite or public-replay run is attributed to the UI commit.

The public replay used manifest SHA-256 `4209c193deb0e6f24a2806aa152395364e558e131b0bd3419e0151cae636bd19` from upstream commit `faeca2bc29598744a62f787076d9e340e5095b8b`. All 32 input-file hashes matched the baseline and remained unchanged. OCR was disabled, and the LibreOffice PDFs were preserved earlier conversion outputs: this run did not launch a new renderer or measure new pixel fidelity. Forced ordinal associations were used only as a separate diagnostic for these known-source fixtures; production automatic matching was checked separately.

A retained negative native fixture has ambiguous glyph overlap and withholds a real `100 → 101` text-edit claim while exposing the raw strings and uncertainty. It remains an unresolved accuracy case; passing the read-only MCP checks does not resolve it. The local app has an ad-hoc signature, not notarization. These checks do not cover all fonts, exporters, OCR inputs, accessibility interactions or PowerPoint rendering fidelity.
