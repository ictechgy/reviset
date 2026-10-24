# Workspace customization

Use **Layout / 화면 배치** in either native workspace to arrange its source comparison and supporting panels. Document and spreadsheet layouts are saved separately.

- Start with **Source first**: Changes on the left, large source comparison, projects and evidence closed. This is the new default and reset target. Balanced, Document Focus, Review and saved layouts remain available. Existing saved preferences are retained; apply Source first explicitly to try the new arrangement. Reset never deletes a project or report.
- Drag the native splitters to change panel sizes and the before/after ratio.
- Place Changes below, left, or right of the comparison. Hide supporting panels when you need more document space; place the evidence inspector on either side.
- Switch between horizontal and vertical source comparison.
- On macOS, toggle Document Focus to temporarily enlarge the source. Toggling Focus off restores the preceding panels with geometry edits made while focused. Opening a panel during Focus restores the retained arrangement and merges only the changed visibility flags. Saving during Focus records that retained arrangement with edited geometry and keeps Focus active. Applying a preset, saved layout or reset starts a new baseline. Independently hiding panels, even all of them, keeps report and history-range controls available.
- Save a named layout, apply it later, or delete the saved layout. Up to twelve names are stored per workspace. Cancelling the save dialog writes nothing.

Layout changes retain the existing report, source hosts, selected pages/cells and viewing state. Display preferences never enter canonical reports, exported machine data or MCP responses. Source text and user-authored names are not interpreted as format strings or instructions.

On macOS, the View menu shortcuts act on the active document or spreadsheet window: `⌘⌥F` for focus, `⌘⌥I` for evidence, `⌘⌥S` for projects, `⌘⌥C` for changes, and `⌘⌥0` for reset. The toolbar layout menu exposes docking, presets and named layouts. Windows provides native menus and keyboard-focusable splitters.

Settings are versioned and size-limited. Unsupported positions and invalid dimensions recover to safe defaults. Future-schema settings are preserved without overwrite. Window size constraints can temporarily limit visible space without replacing the user's preferred panel dimensions.

The fixed report and query controls stay available in Focus. The comparison interval belongs to the change list; source headers identify the selected event's actual versions/pages/cells. Selecting an intermediate event keeps the wider query interval. Previous/next change actions stay in the same list. A text-diff view provides bounded before/after snippets with `−/+` markers while retaining the native source hosts; appearance observations and unavailable content use neutral labels rather than semantic deletion markers. Detailed source evidence remains available separately.

On Windows, a visible project panel remains accessible in narrow windows. Hide it explicitly from Layout or choose Document Focus to give the source more room. The change-mode selector switches between net changes and intermediate history while preserving the selected version interval.

## Reading wide or long sources

Resize or hide supporting panels when the source needs more room. A layout change preserves the current zoom and manual viewport where feasible; at 150% zoom, a narrow pane can show only part of a PDF page. Use native scrollbars or change zoom to inspect the remaining source. Workbook grids also scroll horizontally; selecting a cell change reveals that selected cell rather than unrelated off-screen changes.

Large projects still need memory for analysis and fixed reports. Paged lists, sparse grids and bounded previews control view payloads, not the entire process footprint. See the [Windows scaling limits](WINDOWS.md#large-documents-and-workbooks) and source-bound [public-corpus measurements](PUBLIC-CORPUS-FIXES-2026-10-23.md).

Actual runtime checks and external visual/code opinions are recorded in the [native workspace qualification](NATIVE-WORKSPACES-2026-10-23.md). All 25 current Mac originals and 18 Windows originals were inspected directly without a new visible blocker. Earlier Claude static reviews remain **COMMENT** at Mac `1615b0ab` (eight images) and Windows `e443a440` (18 images); their verdicts are not carried to the current source. Dynamic Focus restoration, panel opening and named-save behavior are checked separately. Static screenshots do not qualify interaction or accessibility.

## Native implementation decisions

Claude, Devin and Grok independently reviewed the design at commit `990927052bf8be463a81a307f01f8d6bf3d950ab`. Each requested refinements before implementation. Their common recommendations were native controls, bounded docking, preserved source state, UI-only preferences, explicit platform capability gaps and actual Windows qualification. Design discussion is not an implementation approval.

Reviset retains its SwiftUI/AppKit shell and adds a WPF shell for Windows. Both use the existing local bridge. Windows PDF display uses the existing fingerprinted PDF.js/canvas renderer in an owned backend process, with a fixed-report/page-only API, source SHA verification, pixel and encoded-image limits. Advisors also proposed Windows.Data.Pdf and PDFium; choosing the existing renderer avoids another rendering dependency and reuses tested source-selection rules. This choice is not a claim that the advisors agreed on a renderer, or that a Windows Job Object provides file/network confinement.

Windows native Job Objects own backend lifetime. Apple native helpers, Office conversion and sidecar rendering fail closed before execution on Windows; generic POSIX external-processor supervision is unavailable there. Portable extraction, workbook analysis and MCP do not depend on that supervisor. The Windows regular-file boundary compares the selected file's identity with the opened descriptor; unlike macOS `O_NOFOLLOW`, this is not an atomic no-follow guarantee.

Native qualification and independent implementation reviews are recorded separately from this design decision. Existing [localization qualification](LOCALIZATION-2026-10-23.md) remains bound to its original source and app; it is not relabelled as validation of these new layouts or the Windows app.
