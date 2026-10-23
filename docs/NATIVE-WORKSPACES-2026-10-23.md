# Native workspace qualification — 2026-10-23

This record covers customizable native layouts and the Windows app. English is canonical. Both current apps were built and run at the same clean source, `29f3a8ad58698bdd5f410efa786ed39022512756`; runtime checks and reviewer recommendations are recorded separately.

| Scope | Source / artifact | State |
| --- | --- | --- |
| Actual Mac app | `29f3a8ad`, `Reviset-Workspace8.app` | PASS within the scope below |
| Actual Windows x64 package | `29f3a8ad`, [workflow 39975028777](https://github.com/ictechgy/reviset/actions/runs/39975028777) | PASS within the production-action scope below |
| Native implementation review | Base `990927052bf8be463a81a307f01f8d6bf3d950ab` → `29f3a8ad` | Code COMMENT, zero actionable findings; architecture WATCH, no BLOCK; scaling watch retained |
| Final Claude / Devin / Grok code reviews | `29f3a8ad` | Claude / Devin / Grok APPROVE |
| Current original-image inspection | 25 Mac / 18 Windows originals at `29f3a8ad` | Directly inspected; no new visible blocker within the static scope |

Earlier source reviews at `1615b0ab` returned Claude APPROVE and Devin/Grok REQUEST CHANGES. Accepted Focus visibility/named-save and Windows saved-report selection findings are repaired and have current runtime coverage; all three providers completed their code-review closure at `29f3a8ad`. Earlier Claude static reviews remain COMMENT at Mac `1615b0ab` (eight images) and Windows `e443a440` (18 images). None is relabelled as a current-source approval.

## Actual Mac checks

- Five actual app runs cover English/Korean document and workbook workspaces plus a real second-process library-lock denial. Each language exercises six document layouts and 56 chrome checks: independently hiding all panels stays outside Focus and retains report/history controls.
- Geometry edits during Focus merge into the retained baseline. Opening Projects, Changes or Evidence exits Focus, restoring other prior panel flags and merging only the changed flags. Checks cover all-visible and all-hidden starting layouts in Compare/History and both workbook runs. Named Save during Focus captures the retained arrangement with edited geometry, keeps Focus active and survives reload/reapply. Explicit preset/saved-layout/reset application can replace the baseline.
- Actual PDF host/document/page/150% zoom and report/evidence selection remain intact. Native grids retain their coordinator, selected raw cells, reveal authority and feasible viewport state; PDF viewports can clamp as pane dimensions change. Workbook left/right change lists occupy 81.44% of the English pane and 84.95% of the Korean pane, above the 60% gate.
- All 25 original Mac captures were inspected directly: 12 standard document layouts, four manually hidden-panel views, four workbook docks, four workbook comparison/AI views and one lock view. They show actual AppKit/PDFKit content without image edits; the dynamic Focus changes are qualified by production hooks, not claimed as before/after trigger screenshots.
- The locked second app has two disabled production import-label environments and a disabled physical top-plus import button with the correct Korean locale. Four bundled-runtime MCP reads expose 29 tools and return eight document content items or 12 bounded workbook cell items per language. Same-snapshot English/Korean transcripts/configurations match; original assets, SQLite/report bodies, host preferences, source and runtime bytes remain unchanged by reopen/layout/locale/MCP checks.

The actual delivery app and bundled Node pass strict deep signature verification before/after checks. The Mac app is ad hoc signed, not notarized. Uneven source heights reflect the retained custom divider ratio; copy/grid-width followups remain. A conditional source-box concern from an earlier static review remains unconfirmed.

## Actual Windows and regression scope

The current Windows workflow passed 95 portable/boundary tests, zero failed and four POSIX-only skipped (99 total), 24 preference checks and 63 production WPF window/model/action checks. Workbook checks cover six layouts and both grids, physical row geometry at feasible retained viewports, horizontal scrolling where available and separate physical stored-cell queries. Mode synchronization and invalid reversed ranges are checked in English/Korean. Native Reorder with three distinct reports retains the older middle report, source pages/event scope, selected net interval, 200% zoom and both manual X/Y viewports; all three fixed report bodies and the report list remain unchanged. Bundled-runtime MCP exposes 29 read-only tools, reads five document page items and 72 workbook cell items, and denies foreign-project scope. All 18 original Windows PNGs were inspected directly.

The portable ZIP is 132,322,986 bytes, SHA-256 `38d087bb2a63273053672488d6612947b3190e1d9aaf2ed86e01d55dc0b648a9`. Its metadata records the exact clean source and verified official Node input. Claude, Devin and Grok approved the tested `29f3a8ad` source. A nonblocking Windows followup remains: if Reorder writes the draft but later refresh/restoration fails or is cancelled, generic failure wording and stale draft metadata can remain until the project is reopened. Fixed reports stay unchanged. Production-model actions and native captures do not qualify OS gestures, the full Mac toolbar, semantic OS accessibility identifiers, VoiceOver/Narrator or installation on another computer. Static images do not certify state/byte integrity, OCR or Office fidelity.

The full suite at `5180cb160ac3d819a205c974a643590648f75ceb` passed 468 tests with zero failures and one Windows-only skip (469 total). It was not rerun at the current source. Earlier Mac 492-page analysis/MCP results retain their [original sources](PUBLIC-CORPUS-FIXES-2026-10-23.md); cached analysis used 97.2% of a 4 GiB test budget. No equivalent Windows scale result is claimed. View paging does not bound all analysis/report memory.

| Byte identity | SHA-256 |
| --- | --- |
| Mac executable | `5d820f8b24e11cf92febde54f9347079287e21b29a87d768594ac6f353db3db2` |
| Mac QA summary / 25-original manifest | `64814d448783bfe923252668b44d515e7bab2fdf35c53d7d67f631641d6d5de9` / `ccfa4ac395708b8b7f901fd06ea6e5dc3048ebb2e3546076b4b54d6320bd2ec5` |

Full local argv/status/stdout/stderr, manifests, raw captures and before/after hashes are retained separately; generated app/library/test artifacts are excluded from the public repository. The Windows WPF/.NET x64 portable package is unsigned. Apple OCR and confined Office conversion remain unavailable on Windows; helpers fail closed there. PPTX structural fallback is labelled, formulas are not recalculated and manual page/bundle mapping is macOS UI functionality. Universal OCR and pixel-identical Office rendering remain unqualified. See [Windows capabilities](WINDOWS.md) and [workspace controls](WORKSPACE-LAYOUTS.md).
