# Official public-document compatibility — 2026-10-22–23

Real public documents exposed compatibility and accuracy limitations that the earlier synthetic LibreOffice check did not cover. Results are **partial**, not a blanket compatibility or OCR-accuracy pass.

Subsequent fixes and their separate validation are recorded in the [2026-10-23 repair report](PUBLIC-CORPUS-FIXES-2026-10-23.md). The historical results below retain their original execution scope.

## Corpus and provenance

Nine original files were tested: four UK DESNZ spreadsheets (2023 provisional/final, XLSX and ODS), two corresponding statistical-release PDFs (28 and 40 pages), NASA's eight-slide OMI Phase-F presentation, NIST SP 800-53 Revision 5 (492 pages), and the previously pinned one-page W3C OCR example. Eight files were acquired from official HTTPS download endpoints; the W3C cache was independently rehashed. Exact URLs, sizes and SHA-256 values are in [the corpus manifest](fixtures/official-corpus-2026-10-22.json). Original and converted bytes remain local and are not redistributed in this repository.

Sources: [DESNZ provisional release](https://www.gov.uk/government/statistics/provisional-uk-greenhouse-gas-emissions-national-statistics-2023), [DESNZ final release](https://www.gov.uk/government/statistics/final-uk-greenhouse-gas-emissions-statistics-1990-to-2023), [NASA publication record](https://ntrs.nasa.gov/citations/20240007006), [NIST publication record](https://csrc.nist.gov/pubs/sp/800/53/r5/upd1/final), [W3C OCR example](https://www.w3.org/WAI/WCAG22/working-examples/pdf-ocr/ocr-example.pdf). GOV.UK identifies Open Government Licence terms; NASA identifies public use as permitted; NIST's publication states its US-government copyright status. Public provenance does not establish that a file is exploit-free.

## Results

| Route | Result |
| --- | --- |
| Original DESNZ XLSX provisional → final | 49,953 saved values exactly matched an independent bounded XML reader; 44 checks and 17 actual read-only MCP calls passed |
| DESNZ ODS → actual LibreOffice XLSX, then compare | 48,660 saved values matched the independently read converted files; 44 checks and 17 MCP calls passed. This does not certify conversion fidelity |
| Direct original DESNZ ODS imports | Both blocked by the existing 500,000 materialized-cell limit; not counted as successful imports |
| NASA PPTX → LibreOffice PDF | Eight source slides and eight exported pages imported, rendered and queried; 26 MCP calls. Selected cover preview inspected; no PowerPoint pixel-equivalence claim |
| DESNZ PDF provisional → final | All 28 + 40 pages imported with native raster/OCR observations and read-only MCP traversal (78 calls). Spot-checks found appearance and correspondence accuracy limitations below |
| W3C OCR PDF | One page imported with native OCR and four MCP calls; selected checks are not whole-page OCR ground truth |
| NIST 492-page PDF | Incomplete: cold analysis cancelled at 25 minutes after 416 native pages; hash-verified cache retry finished the remaining 76 native pages but exceeded the 4 GiB process-tree limit before producing a stored report. Not a successful import or MCP qualification |

The two spreadsheet suites checked **98,613 actual saved values**, 88 contract assertions and two real MCP sessions with 34 calls. Independent XML readers and source cells were used as the oracle; the product output was not its own ground truth. The files contained no formulas, so these runs do not add formula-recalculation or formula-accuracy coverage.

The precise stored 2023 total changes from `384.16330024426702` to `384.97255609012558` in the original workbooks. Their sheet structures change from 11 to 24 sheets, and the total table is renamed and rearranged. Both endpoints are readable through MCP, but automatic same-cell lineage remains unresolved. The published PDF rounds the final total to 385; that rounded number is not an exact workbook-cell oracle.

## Confirmed limitations

1. **ODS styled blank regions exceed the current dense model.** These legitimate files explicitly repeat formatted blank cells through column XFD. The provisional file reaches the limit in `Table2b_CO2` row 6 (495,248 already materialized plus 16,384); the final file reaches it in `1_2` row 9 (491,949 plus 16,384). Nonempty data is much smaller, but dropping blank styles would lose real formatting observations. The limit was not increased or bypassed. Supporting these files requires a bounded sparse representation for styled rectangles across extraction, queries, diff and stored-report compatibility.
2. **LibreOffice conversion loses six text spans.** Actual ODS-to-XLSX saves omit nested spans inside hyperlinks, including the `2` in some `CO2` labels and text in linked references. Independent raw ODF/OOXML confirms this is a conversion change. Reviset correctly reads the resulting XLSX, but those files are not content-equivalent to the original ODS. Numeric serialization also changes decimal spelling; the saved source values are retained separately.
3. **PDF appearance inference has false positives.** An ordinary table-of-contents digit `6` is classified as `struck_inferred`, producing a strike event. An ordinary chart-axis `2020` is also misclassified, producing a reveal event when paired with another chart. Independent page renders show no strike or cover in those regions. These are recorded failures even though the events are labeled inferred.
4. **Restructured PDF correspondence needs review.** Some modified-text candidates pair page numbers or values from different charts. Their `needs_review`/inferred qualification is essential; a candidate such as 160 → 100 is not established as a real numerical revision when the charts and units differ. The national 384.2 → 385 change is available in source/unresolved text but was not recovered as a precise matched text-change event in this sample.

5. **Large real-PDF completion is not yet reliable within the tested budget.** The initial NIST attempt ran for 1,505.57 seconds before its explicit 25-minute cancellation. A separate retry reused 832 byte-verified cache files, completed the remaining 76 native pages and was terminated after 273.72 seconds when sampled process-tree RSS reached 4,205,376 KiB, exceeding the 4 GiB ceiling. Neither attempt produced a qualifying stored report. Native page completion is not full extraction, persistence or MCP completion. The memory cap was retained; the cache and both failed libraries were preserved. The exact allocation hotspot has not been established by a heap profile.

## Security and injection handling

Acquisition used an explicit official-host HTTPS allowlist, refused redirects and proxy-environment configuration, and enforced 20 MiB/120-second download limits. Screening traversed bounded ZIP/XML and PDF objects. Two original XLSX files contain external-reference parts (the final one also contains an external image relationship); they were restricted to static ingestion and were never opened in LibreOffice. Passive hyperlinks were counted but never followed.

All real-document parser and engine runs used a separate whole-process macOS sandbox with clean HOME/TMP/environment, a read allowlist, read-only downloads, writes confined to the artifact directory and denied IP networking. LibreOffice used fresh profiles, macro security level 3 and exact per-job IPC paths. Boundary probes verified denial of out-of-scope reads/writes, source writes and network connections. The supervisor enforced wall time, process-tree memory, file size, output and artifact-size bounds.

macOS refuses nested sandbox application. A test-only preload therefore replaced the two known native/LibreOffice sandbox-launch forms with execution under the already inherited outer sandbox. Exact requested policies and substitutions were logged. This is whole-engine isolated corpus evidence, not a claim that the unchanged per-helper launcher ran with a second sandbox. Product policies were not weakened.

MCP remains read-only and project-scoped. A separate synthetic instruction-string control was retained as data; unsupported execution-tool calls and out-of-scope reads were refused. Public document bodies were not sent to external AI reviewers. Claude/Grok received only the code patch and locally authored verification notes.

## Repair and evidence scope

The older public-corpus runner had one native preview call outside the native launcher and reused the same evidence directory for repeated source snapshots. The repair routes verified source bytes through a private native job and gives each run a unique evidence directory. Actual sandboxed rendering then exposed a Foundation atomic-file-write failure. The helper writes a private intermediate PNG without atomic staging; the parent verifies and publishes completed output. The source is now in a separate read-only directory, with a post-render source hash check. The output is created exclusively, read through a bounded no-follow descriptor and checked against native metadata, PNG framing, dimensions and the render digest before parent publication. Existing destinations are preserved. Failed publication can leave an unreferenced file in that unique failed run; this is not a power-loss durability guarantee.

The complete two-file patch against `32dc92d6482e3702cd475ceed8bbbbd38048c8f5` has SHA-256 `db2076fd7a922da85d39f0be51ee37333c334dbccfc3218751fca98dc28e356a`. Focused real native and negative controls passed in 30.264 seconds, including actual read-only source policy enforcement, unchanged W3C pixels and normal 32-line OCR. TypeScript checking passed. The final `npm run native:helpers` build completed in 6.55 seconds and produced the exact previously tested helper bytes (`de10da29f21ad77dc4e6325f8cc98e5d55e0cbb5d7aa0305486a200923c98e15`); the old dist helper and App3 package were preserved. This does not claim a newly qualified app package.

Final review state: independent code APPROVE and architecture CLEAR for the complete two-file source patch; Claude and Grok both returned terminal APPROVE on that complete patch (71.17 and 900.08 seconds respectively, exit 0). The reviewed bytes are committed as `d52766a18bd0c979ad0e2427418c4c0145a0f449`; its cumulative two-file diff matches the reviewed patch hash above. Earlier Claude COMMENT and Grok REQUEST CHANGES are preserved with their original prompts and were followed by the source/output boundary changes above. These source verdicts do not close the corpus failures.

Public-document engine runs used the source/runtime from `32dc92d6482e3702cd475ceed8bbbbd38048c8f5` and the previously packaged App3 helper. The repaired helper has separate strict Swift/TypeScript and actual W3C render/OCR controls; those earlier full-document runs are not relabeled as final-helper executions.

Original failed controls and runs are preserved. The initial PDF scanner incorrectly used call-stack recursion for indirect object graphs; an iterative bounded traversal fixed the NIST scan. An initial reopen assertion compared JSON property order instead of structured values; a targeted read-only replay verified deep equality, immutable stored report bodies and database bytes without rerunning OCR. Neither harness correction erases the ODS, conversion or PDF accuracy failures above.

Raw invocation records, source and binary hashes, original files, full reports, MCP responses, independent oracles, screenshots and failures are retained locally under `.omx/artifacts/public-realdata-20261022/`. No universal OCR, Office fidelity, native UI accessibility, notarization or other-Mac qualification is claimed.
