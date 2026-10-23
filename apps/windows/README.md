# Reviset for Windows

This is a native WPF desktop client targeting .NET 10 on Windows 10/11 x64. It shares the versioned TypeScript extraction, diff, storage and MCP engine with the macOS application. It does not embed a web UI or execute imported formulas, macros, source documents or copied MCP configuration.

Build and package from the repository root using `scripts/build-windows.ts`. The distributable directory contains `Reviset.exe`, its self-contained .NET runtime, `runtime/node.exe`, `backend/bridge.mjs`, `backend/mcp.mjs`, the backend dependencies and build information. Keep that directory together. A cross-build on macOS verifies compilation; it cannot qualify Windows rendering or process behavior.

The application opens `%LOCALAPPDATA%\Reviset\library` under an exclusive app-lifetime lock. Only one Windows GUI instance can use that library at a time. Layout and language preferences live separately in `%LOCALAPPDATA%\Reviset\preferences.json`. Document and spreadsheet workspaces have independent layouts. Splitters resize retained native panes; the Layout menu selects pane positions, comparison orientation, presets and up to twelve named layouts per workspace. Unknown future preference versions remain read-only and are preserved.

Document import accepts one PDF or PPTX, or one PDF + PPTX pair per labelled revision. Spreadsheet import accepts one XLSX, ODS or UTF-8 comma-delimited CSV per revision. Add and reorder revisions before import; document drafts can also be reordered afterwards without replacing existing pinned reports. Reanalysis creates a new report. The native spreadsheet grid pages fifty rows by up to eight columns, supports physical address navigation and distinguishes sparse absence from confirmed blank. Cell details expose stored formulas and cached values without recalculating them. The change-list mode selects adjacent history events or endpoint net changes for the same explicit interval; inspecting an intermediate event keeps that list interval fixed. Sparse and truncated grid previews have grey italic annotations and explanatory tooltips, while literal source dashes and ellipses retain normal source styling. An explicit version change keeps a missing previously selected sheet absent until the user chooses an available sheet.

Page previews use the shared bounded PDF renderer when available. A PPTX without a supported rendered preview shows explicit structural text and the reason rendering is unavailable. Structural text is never presented as a pixel-faithful slide. Source content and diagnostic codes remain verbatim when the UI language changes.

Every engine request starts the fixed bundled Node executable with an absolute script path and `ArgumentList`, concurrent bounded UTF-8 pipes, an allowlisted environment and a Windows job with `KILL_ON_JOB_CLOSE`. Job assignment must succeed before the bridge receives request input. Cancellation kills the request's process tree. Pinned report IDs and generation checks reject superseded document, page, grid and detail responses. Startup recovery runs while the GUI owns the library lock. Before another library mutation, the admitted writer also recovers interrupted runs and unclaimed stages without replacing pinned reports. Invalid helper responses produce a typed protocol error with a bounded plain-text diagnostic log at `%LOCALAPPDATA%\Reviset\logs\helper-error.log`; the latest helper error replaces the previous log.

## Native smoke qualification

On Windows, launch the actual packaged app:

```powershell
Reviset.exe --smoke C:\temp\reviset-smoke --fixtures C:\temp\reviset-fixtures
```

The fixture directory must contain `windows-smoke.json`, with paths relative to that directory:

```json
{
  "documents": {
    "title": "Document control",
    "revisions": [
      { "label": "v1", "files": ["v1.pdf"] },
      { "label": "v2", "files": ["v2.pdf"] },
      { "label": "v3", "files": ["v3.pptx"] }
    ]
  },
  "workbook": {
    "title": "Workbook control",
    "revisions": [
      { "label": "v1", "path": "workbooks/v1.xlsx" },
      { "label": "v2", "path": "workbooks/v2.csv" },
      { "label": "v3", "path": "workbooks/v3.ods" }
    ]
  }
}
```

Generate the repository's synthetic control files with `scripts/generate-windows-fixtures.ts`. Smoke mode uses an isolated `profile` below its output folder, exercises real import/analyze/staged commit, pinned reports, previews, native grids, address queries, exports, English/Korean controls, retained panes, production Layout-menu visibility toggles, native named-layout Save/Cancel and saved-layout Apply, preference reload, scope rejection and cancellation recovery. It records `result.json` with `passed`, `library`, both project/report IDs, named checks, source preview provenance, source asset preservation and package build information. It also saves the production-generated `document-mcp.json` and `workbook-mcp.json` for an independent bundled MCP reader check, plus native rendered PNGs.

These layout dialog checks do not automate the overwrite-confirmation MessageBox. This is programmatic WPF window/control qualification. It does not claim OS mouse, keyboard or screen-reader automation. An optional `--backend-root` is accepted only together with smoke mode, for an explicitly isolated development bundle. Normal launches cannot override the bundled executable paths.

The portable preference checks can also run on macOS/Linux with `.NET 10`:

```text
dotnet run --project tests/windows/PreferencesChecks.csproj -c Release
```
