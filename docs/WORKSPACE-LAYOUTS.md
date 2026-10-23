# Workspace customization

Use **Layout / 화면 배치** in either native workspace to arrange its source comparison and supporting panels. Document and spreadsheet layouts are saved separately.

- Start with Balanced, Document Focus, or Review. Reset restores Balanced without deleting a project or report.
- Drag the native splitters to change panel sizes and the before/after ratio.
- Place Changes below, left, or right of the comparison. Hide supporting panels when you need more document space; place the evidence inspector on either side.
- Switch between horizontal and vertical source comparison.
- Save a named layout, apply it later, or delete the saved layout. Up to twelve names are stored per workspace. Cancelling the save dialog writes nothing.

Layout changes retain the existing report, source hosts, selected pages/cells and viewing state. Display preferences never enter canonical reports, exported machine data or MCP responses. Source text and user-authored names are not interpreted as format strings or instructions.

On macOS, the View menu shortcuts act on the active document or spreadsheet window: `⌘⌥F` for focus, `⌘⌥I` for evidence, `⌘⌥S` for projects, `⌘⌥C` for changes, and `⌘⌥0` for reset. The toolbar layout menu exposes docking, presets and named layouts. Windows provides native menus and keyboard-focusable splitters.

Settings are versioned and size-limited. Unsupported positions and invalid dimensions recover to safe defaults. Future-schema settings are preserved without overwrite. Window size constraints can temporarily limit visible space without replacing the user's preferred panel dimensions.

## Native implementation decisions

Claude, Devin and Grok independently reviewed the design at commit `990927052bf8be463a81a307f01f8d6bf3d950ab`. Each requested refinements before implementation. Their common recommendations were native controls, bounded docking, preserved source state, UI-only preferences, explicit platform capability gaps and actual Windows qualification. Design discussion is not an implementation approval.

Reviset retains its SwiftUI/AppKit shell and adds a WPF shell for Windows. Both use the existing local bridge. Windows PDF display uses the existing fingerprinted PDF.js/canvas renderer in an owned backend process, with a fixed-report/page-only API, source SHA verification, pixel and encoded-image limits. Advisors also proposed Windows.Data.Pdf and PDFium; choosing the existing renderer avoids another rendering dependency and reuses tested source-selection rules. This choice is not a claim that the advisors agreed on a renderer, or that a Windows Job Object provides file/network confinement.

Windows native Job Objects own backend lifetime. Apple native helpers, Office conversion and sidecar rendering fail closed before execution on Windows; generic POSIX external-processor supervision is unavailable there. Portable extraction, workbook analysis and MCP do not depend on that supervisor. The Windows regular-file boundary compares the selected file's identity with the opened descriptor; unlike macOS `O_NOFOLLOW`, this is not an atomic no-follow guarantee.

Native qualification and independent implementation reviews are recorded separately from this design decision. Existing [localization qualification](LOCALIZATION-2026-10-23.md) remains bound to its original source and app; it is not relabelled as validation of these new layouts or the Windows app.
