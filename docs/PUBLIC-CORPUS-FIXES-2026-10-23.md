# Public-document repairs — 2026-10-23

This follow-up addresses reproducible failures in the [official public-document test](PUBLIC-CORPUS-2026-10-22.md). The original results and failed attempts remain intact. Tests reuse the nine hash-pinned originals in the [corpus manifest](fixtures/official-corpus-2026-10-22.json); no original documents are redistributed here.

## What changed

- **Direct ODS ingestion:** large repeated blank-cell formatting is stored as bounded rectangles. The 500,000 materialized-cell limit remains in place. MCP, range comparisons and the native grid can inspect this formatting without expanding entire sheets. Source rectangles and changed subranges have separate provenance fields. See the [spreadsheet contract](SPREADSHEETS.md).
- **Raster strike inference:** a horizontal band must have ink evidence independent of the glyph itself. Ordinary digit crossbars and rotated labels can remain ambiguous instead of being called deletions. Genuine single-digit, multi-digit and colored strikes retain positive controls.
- **PDF regional correspondence:** an uncertain page association or a region lacking a literal text anchor produces quoted uncertainty evidence. This deliberately withholds some unlabeled values and page-number changes. It does not change the fully readable whole-page comparison path. Multiple uncertainty reasons for the same regional pair share one event.
- **Large-PDF memory:** PDF.js is released before native observations are combined; repeated-input cache ownership and validation avoid unnecessary full-tree copies. Report hashing and staging write canonical JSON in batches. Store validation remains mandatory, and SQLite errors survive an automatic rollback in document commits, workbook commits and draft mutations. Partial staging files are removed after caught serialization/write failures.
- **MCP pagination:** an additional eight-entry, 16 MiB cache retains query rows and pagination metadata. The full-report cache remains capped at 64 MiB. Every request checks project scope, resolves `latest` afresh and preserves cursor, output-budget and coverage semantics. The first request and uncached searches can still load the full report.
- **Cancellation:** an abort during PDF extraction, native observation integration or final page validation remains `CANCELLED`.

Document engine `0.4.0-native.bundle.54` preserves engine 53 through an exact archived diff implementation. Workbook engine `workbook.1.1` reads previous 1.0 reports; 1.1-only fields cannot be labeled as 1.0.

## Completed measurements

| Check | Result and scope |
| --- | --- |
| Original DESNZ ODS pair | 48,660 saved values, 963 blank-style rectangles and 8,231 inherited style properties matched independent bounded XML readers. Direct ingestion preserves all six text spans omitted by the earlier LibreOffice conversion |
| Strike controls | 13 direct raster controls, including bitmap edges; existing OCR controls and real strike/underline integration passed. The two reported public false-strike regions were retested with helper 27 |
| Historical document reports | All 126 stored engine-53 events and full range payloads/IDs matched a pristine earlier runtime, including detailed change and evidence retrieval |
| NIST cached engine path | 492 pages analyzed, committed, reopened and read through the page index in 44.905 s; sampled peak tree RSS 4,020,192 KiB |
| NIST actual app bridge | Separate processes completed create, analyze, stage, commit, run-status, view and three page actions in 49.992 s; sampled peak tree RSS 3,548,368 KiB |
| NIST actual MCP | 529 calls and 21 checks traversed all 492 pages, verified selected source-text hashes, searched source content and checked project isolation. Total 67.704 s; sampled peak tree RSS 3,206,976 KiB; database SHA-256 unchanged |

The cached NIST and MCP measurements above use preserved observations from the earlier helper. They prove the memory, persistence and query repairs on those observations; they are not a cold OCR qualification of the revised helper. Final cold-document, complete-suite, packaged-app and review results are recorded separately when available.

The previous MCP baseline took about 1,795 ms for each page-list request and was intentionally stopped after 84 pages. With the same stored report, the 491 cached requests had a median of 0.244 ms. Complete page traversal took 33.672 s, including 17 requests recovering ordinals explicitly omitted from oversized metadata responses. Unique uncached text/search requests still cost about 1.8 s in that run. No response-size limit was increased.

## Limits and security scope

Report staging writes synchronous bounded batches. Event-loop cancellation is observed after this staging window; an already-aborted signal is checked between batches. Process termination or a cleanup failure can still require startup recovery.

The four-GiB process-tree memory limit was retained. A separate 512 MiB **test output-file** cap prevented saving the NIST database: its canonical report occupies 299,830,451 bytes, and the bounded page-read index stores approximately that much again. Later runs explicitly used a one-GiB output-file cap. This is distinct from the unchanged product source-document size limit. Failed runs were preserved; the original 512 MiB test did not pass. Artifact-growth limits apply per run so retaining previous evidence does not consume the next run's allowance.

The inherited whole-process macOS sandbox still denies IP networking, source writes and out-of-scope access. Every run uses a clean environment and bounded time, memory, file and output budgets. The logged test-only handling of nested sandbox launchers remains as described in the original report. A private runtime uses the exact pinned Node bytes and the revised sibling helper; setting an environment variable alone does not override a packaged sibling helper.

MCP is read-only and project-scoped. Downloaded document text remains data. External Claude/Grok packets contain allowlisted source code and locally authored verification notes, not public document bodies or credentials.

The upstream LibreOffice ODS-to-XLSX text loss is unchanged; direct ODS import avoids that conversion. Automatic cell lineage across the renamed/restructured DESNZ sheets remains unresolved. The PDF total `384.2` to `385` is readable as source evidence, but reflowed multi-number prose is not forced into a precise regional change. OCR ambiguity, inferred PDF tables and coverage gaps remain explicit. These tests do not establish universal OCR accuracy, PowerPoint pixel equivalence, notarization or behavior on another Mac.

Local raw evidence is retained under `.omx/artifacts/public-corpus-fixes-20261023/` and the original `.omx/artifacts/public-realdata-20261022/`.
