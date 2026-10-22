# Public-document repairs — 2026-10-23

This follow-up addresses reproducible failures in the [official public-document test](PUBLIC-CORPUS-2026-10-22.md). The nine originals are pinned in the [corpus manifest](fixtures/official-corpus-2026-10-22.json). They remain byte-identical and are not redistributed here. Failed attempts and earlier measurements remain in the local evidence archive.

The final implementation and local native app in this report use **`8d5e18964edaa7a8bfd27b248bad96090ff9ccf4`**. Later documentation-only commits do not change that app. Measurements below identify their actual source snapshot; an earlier cold OCR run is not presented as a new run on the final commit.

## Repairs

- **Direct ODS import:** large repeated blank-cell styles use bounded rectangles, retaining source ranges, number formats and visibility without expanding their area. The 500,000 materialized-cell limit remains. Known validation/protection annotations retain explicit unsupported-feature gaps. Unknown attributes deliberately remain subject to materialization limits. Hidden-column boundaries are indexed once per sheet.
- **Workbook differences:** explicit blanks and content retain both physical endpoints with `needs_review`, including blank versus zero. Compression does not change cross-format correspondence confidence. Inferred row moves also retain independent physical formatting differences. Original source rectangles and compared subranges remain distinct. MCP and the native grid expose these observations; the changes pane visibly warns when cross-format blank formatting cannot be compared.
- **Raster strike inference:** a horizontal band needs ink evidence independent of the glyph itself. Digit crossbars and rotated labels can remain ambiguous instead of being called deletions. Genuine strike controls remain covered. Tight strokes indistinguishable from glyph ink can still be uncertain.
- **PDF regional correspondence:** an unresolved page association or missing literal text anchor produces explicit uncertainty instead of a forced value change. Multiple reasons share one regional gap. Fully readable whole-page comparisons retain their existing path.
- **Large-document memory and persistence:** PDF.js is released before native observations are combined. Repeated-input ownership avoids unnecessary copies. Canonical hashing/staging uses bounded batches, while full Store validation remains mandatory. SQLite failures survive automatic rollback, and caught staging failures remove their partial files.
- **MCP:** an eight-entry, 16 MiB derivative cache complements the unchanged 64 MiB full-report cache. `latest` is resolved once per request and binds both loading and cache identity. Scope checks, cursor validation and output limits remain. Cache sizing counts escaped UTF-8 incrementally; unsupported cache entries do not fail the query or invoke getters/custom serializers.
- **Cancellation:** late PDF extraction/integration aborts remain `CANCELLED`. Synchronous staging still has the cancellation limitation described below.

Document engine `0.4.0-native.bundle.54` preserves engine 53 through its exact archived diff. Workbook engine `workbook.1.1` retains 1.0 reads and rejects 1.1-only fields mislabeled as 1.0, including hash-valid derived indexes. See the [spreadsheet contract](SPREADSHEETS.md).

## Public-document measurements

Native PDF runs below use helper `docver-vision-27-strike-ink-separation`, binary SHA-256 `c71bb4e9a6adc194ac31be618998e9fd23486d68becb30d7198d732eda7f6900`. They are single local measurements, not cross-machine throughput guarantees.

| Check | Source and result |
| --- | --- |
| Original DESNZ ODS pair | Final `8d5e189`: **48,660 saved values**, 963 blank-style rectangles and 8,231 inherited style properties matched independent bounded XML readers. Direct import retained the six text spans lost in the earlier LibreOffice conversion. **64 checks / 27 MCP calls passed**, 6.253 s; database bytes unchanged |
| DESNZ PDF pair | Extraction snapshot `daf15c6`: all **28 + 40 pages**, 32 checks, 330.764 s, including both reported false-strike regions. Later captured extraction/helper files were bound by hash to final source; changed query/failure-handling paths were recorded separately. Final `8d5e189` MCP: **17 checks / 81 calls passed**, 0.721 s, including fixed-report and `latest` reads; database unchanged |
| NIST cold OCR | `de5f1b1` plus patch SHA-256 `7e602a7cea747a3d301c2367fa20ca51eb64f342861db6639da589d422fc09cb`: **492 pages**, initially empty OCR cache, analyze/commit/reopen passed in **1,795.357 s**; sampled peak process-tree RSS **3,923,616 KiB** |
| NIST cached engine replay | `7dd5a809`: fresh library with only a verified copy of the revised-helper OCR cache; no report/database copied. All **492 pages** analyzed, committed and reopened in **46.915 s**; sampled peak RSS **4,078,720 KiB** |
| NIST final MCP | Final `8d5e189`, reading that unchanged stored report: **23 checks / 544 calls / all 492 pages passed** in **87.786 s**; sampled peak RSS **3,121,536 KiB**. Includes actual `latest` reads, source-content checks and project isolation. Maximum response **7,993/8,000 bytes**; all 7,628 coverage gaps remain retrievable; database unchanged |

The final NIST run tests the current query code against preserved observations; it is not another cold OCR or full-engine run. Its cached page-list median was **0.186 ms**. First uncached queries can still load the full report. Earlier 44.905 s engine and 529-call MCP results used older cached observations; they remain historical evidence and are not substituted for the measurements above.

All nine original file hashes and all 261 source/test/document hashes were unchanged across final public replay. There were no source-document writes or external uploads.

## Regression and native-app qualification

| Scope | Evidence |
| --- | --- |
| Complete integration suite | Clean `2e733bb`: **439/439 passed**, zero failures/skips, 1,187.668 s; source hashes unchanged throughout |
| Subsequent backend repairs | `3fcf8b5`: **144/144 affected workbook/query/MCP tests** and TypeScript passed. Those backend files are unchanged in final `8d5e189` |
| Final UI delta | `8d5e189`: both native read/reliability tests passed with Swift warnings treated as errors. Cases cover empty/nonempty warning state, errors, five incorrect scope fields, delayed responses and lifecycle resets |
| Repeated-asset ownership | Pristine `376dfef` versus `3fcf8b5` with final-identical document backend: five synthetic scenarios, 25 occurrences, 84 pages, 168 element observations and **281 assertions per engine**. Complete revision/page objects and IDs match without dropping or normalizing fields. A real historical manual link enriches only its selected occurrence |
| Historical reports | All 126 stored engine-53 events and complete range payloads/IDs matched the pristine earlier runtime, including detailed change/evidence retrieval |
| Strike controls | 13 direct raster controls including bitmap edges, plus native OCR strike/underline controls and the reported public false-strike regions |
| Final native app | `Reviset-Public-Fixes-3.app`, clean `8d5e189`, SwiftUI/AppKit/PDFKit. Five actual app scenarios passed: three-version XLSX demo, one million styled blanks, blank→zero, moved content with physical formatting, and cross-format warning. **28 independently specified cells**, original/report immutability, local release and export checks passed |
| Packaged MCP | The final app's own Node and bundled `mcp.mjs`: **76 real calls** across those five libraries, all 28 expected cells, 13 read-only workbook tools, cross-format coverage, project denial and unchanged database bytes passed |

The complete suite predates the last scoped backend/UI repairs; the table distinguishes those subsequent checks rather than claiming a full-suite rerun at the final commit. The bundled Node runtime is 24.19.0; these final runs used pinned runtime bytes. App signature verification passed `codesign --verify --deep --strict`, and Node links only system libraries. This is a local ad-hoc signed app, not a notarized public binary release.

All five actual native comparison screenshots were inspected. The orange cross-format warning is visible above a populated list; blank→zero retains both endpoints; moved-row and physical-formatting events remain visible. Empty-list warning behavior is verified by the native model/bridge fixture, not claimed as a real cross-format document with no events. The smoke driver exercises production model actions and rendered AppKit grids; it does not establish OS mouse/keyboard or VoiceOver coverage.

## Limits and security scope

The **4 GiB process-tree RSS limit** was retained. The cached engine peak of 4,078,720 KiB uses about **97.2%** of it, leaving only **2.8% headroom**. This is a measured pass with little margin, not a general memory guarantee. Node heap, elapsed time, output and artifact-growth limits also applied.

A separate 512 MiB **test output-file** cap could not accommodate the 299,830,451-byte canonical NIST report plus a similarly sized page index. Later runs explicitly used a **1 GiB output-file cap**. The failed 512 MiB runs remain failed evidence. This did not raise the product's source-document limit.

Staging writes bounded batches synchronously. Event-loop cancellation is observed after that window; an abort delivered during it can still yield a staged descriptor. Commit-time checks remain in place. Already-aborted signals are checked between batches. Caught serialization/write failures remove partial files; process termination or cleanup failure can still require startup recovery.

Public-corpus runs inherited a whole-process macOS sandbox that denied IP networking, source writes and out-of-scope access. Those runs used clean environments and private runtime/helper paths. The test-only handling of nested sandbox launchers is recorded in the [original report](PUBLIC-CORPUS-2026-10-22.md); the outer sandbox remains inherited. Document bodies are untrusted data. External advisor packets contained allowlisted code/contracts and locally authored verification notes, without public document bodies, credentials or authentication files. MCP remains read-only and project-scoped.

LibreOffice's own ODS→XLSX conversion still loses six text spans; direct ODS import avoids that conversion. Automatic correspondence across renamed/restructured DESNZ sheets remains unresolved. Renaming while changing equivalent blank encodings can also prevent sheet association. When a moved row gains/loses a cell, the physical blank observation and inferred row move remain separate; keyed cell history exposes the corresponding prior/next address, but the cell event has no direct sibling move-event link. These are explicit observation/association limits, not proof of semantic deletion.

The PDF total `384.2`→`385` is available as source evidence, but reflowed multi-number prose is not forced into a precise regional change. OCR ambiguity, inferred PDF tables and coverage gaps remain visible. These tests do not establish universal OCR accuracy or pixel-identical PowerPoint rendering.

Raw source snapshots, invocation records, failed attempts, source hashes, advisor output and verification results remain locally under `.omx/artifacts/public-corpus-fixes-20261023/`; the original corpus evidence remains under `.omx/artifacts/public-realdata-20261022/`. The final public replay is `final-replay-3/`; app evidence is `build/attempt-05/`, `build/app-qualification.json` and `build/packaged-mcp-02/`. The packaged-MCP harness's earlier attempt used an incorrect coverage-count field name; its failure remains preserved, and the corrected attempt uses the documented field.
