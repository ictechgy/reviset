# Reviset

English (canonical) · [한국어](README.ko.md)

**Read document version history beside the original source.**

Reviset is a local desktop app for comparing PPTX/PDF documents and XLSX/ODS/CSV workbooks. Follow versions, choose a change, and inspect its original pages or physical cells side by side. AI clients can query the same fixed reports through a read-only MCP server. Import and analysis need no account, API key or cloud upload.

For example, follow `draft.pptx → review.pdf → final.pptx` as a forecast changes `100억 → 120억 → 110억` (억 denotes 100 million). Intermediate history keeps the `120억` step that the first-to-last comparison (`100억 → 110억`) does not show.

The native interface supports English and Korean on Apple Silicon macOS and Windows x64. Reviset was formerly **Docver**; see [rename compatibility](docs/RENAMING.md).

## Read versions and changes

1. Import documents or spreadsheet versions in order. A PPTX and its supplied PDF from the same version form one version entry.
2. Compare two endpoints or read intermediate history. Selecting a change opens that event's sources while retaining the list's wider query interval.
3. Read the original page or physical cell. **Extracted text diff** offers bounded `−/+` excerpts; **Original source** returns to the page or grid. Long stored cell fields have explicit continuations.
4. On macOS, use **AI tools and export** to export a fixed report or copy the project's MCP configuration. On Windows, use **Project → Export…** to export and **Project → AI tools · copy MCP config** to copy the configuration.

One imported version can be read on its own. **New comparison / Import versions** starts a separate timeline with at least two entries. Imported versions are snapshots; Reviset does not create Git commits or establish an editor's identity or editing time.

For workbooks, the change query, selected event and physical source have separate identities. On Windows, retrying a failed workbook query preserves independently verified physical observations and raw-reader position; changing a comparison method retains displayed physical sources. Query Retry repeats the captured request. Raw-reader Retry repeats its captured physical source, side, component, UTF-16 offset, cursor and limit. See [cell reading and recovery](docs/SPREADSHEETS.md#cell-reading-and-recovery).

## Native workspaces

**Source first** keeps a compact Changes list beside large original sources. Resize or dock panels, use each pane's zoom and **Fit**, switch comparison direction, or save a named layout. Document and workbook preferences are separate. Temporary Focus restores the preceding arrangement when closed; fixed-report and query controls stay available. [Workspace guide](docs/WORKSPACE-LAYOUTS.md).

![English macOS document source workspace](docs/images/macos-git-source-en.png)

macOS original sources v2 → v3; compact Changes beside large PDFKit pages.

![English macOS extracted text view](docs/images/macos-git-text-en.png)

macOS extracted text: query v1 → v3, selected intermediate event v1 → v2, with source terminators.

![English macOS workbook source grids](docs/images/macos-git-workbook-en.png)

macOS workbook physical source grids and stored values; correspondence is inferred and formulas are not recalculated.

![English Windows native document workspace](docs/images/windows-git-source-en.png)

Windows source pages at 100%: query v1 → v3 and selected event v1 → v2 remain distinct.

Native client-content captures omit OS title chrome. The four captures above are selected from the repository's five byte-exact Mac36 and Windows41 originals, with literal producers `158dd21` and `13bee23`. [Screenshot provenance](docs/images/README.md) records the complete commits, file hashes and review scopes.

## Build from source

On Apple Silicon macOS 14 or later, install Node 24+ and Xcode/Command Line Tools with a macOS SDK:

```sh
git clone https://github.com/ictechgy/reviset.git
cd reviset
npm ci
REVISET_APP_NAME=Reviset-Local.app npm run mac:build
open release/Reviset-Local.app
```

The macOS build verifies and bundles its pinned LibreOffice, Node and production dependencies. Running the built app needs no separate Node installation. Packaging requires a Node executable linked only to system dylibs. [Packaging notes](docs/dependencies.md).

On Windows x64 with .NET 10 SDK and Node 24:

```powershell
npm ci --ignore-scripts
npm run build
npm run windows:build
.\release\Reviset-Windows-x64\Reviset.exe
```

Keep the whole output folder together. .NET, Node and production dependencies are bundled. [Windows capabilities and build](docs/WINDOWS.md).

## AI and export

MCP exposes project-scoped, read-only content, changes and evidence. Resolve `latest` once and reuse the returned fixed report ID; follow `next_cursor` and text continuations. Copy the app's configuration again after moving it. Selecting a report in the app does not pin an external client. Source content retrieved by a cloud AI client follows that client's data policies. [MCP guide](docs/MCP.md).

The CLI provides `analyze`, `query`, `export` and separate `workbook-analyze`, `workbook-query`, `workbook-export` commands. The default CLI store is `.docver/`; `--store PATH` selects another location. [Spreadsheet contract](docs/SPREADSHEETS.md).

## Scope and validation

Supported inputs are `.pptx`, `.pdf`, `.xlsx`, `.ods` and UTF-8 comma-separated CSV. Legacy `.ppt`/`.xls`, encrypted files and direct ODP import are unsupported. Imported originals are copied; selected source files are not overwritten. Workbook size limits are in the [spreadsheet contract](docs/SPREADSHEETS.md).

PPTX/PDF text, pages, notes and appearance observations retain extraction and correspondence limits. Workbooks preserve supported cell values, formulas, saved results and basic formatting; formulas, macros and external links are not executed or recalculated. Missing, empty, materialized blank, partial, invalid and already-read fields remain distinct. OCR uncertainty, unsupported objects and conversion gaps are visible. Universal OCR accuracy, exact PowerPoint rendering and complete Excel/Calc behavior are unqualified. Windows has PDF previews and PPTX structure, with Apple OCR and confined Office rendering unavailable.

Development and validation are ongoing. The [native validation record](docs/NATIVE-GIT-DIFF-2026-10-24.md) gives tested behavior and capability limits. Mac notarization, Windows signing and installation on other machines remain open. Earlier [public-corpus measurements](docs/PUBLIC-CORPUS-FIXES-2026-10-23.md) retain their original execution source.

Run `npm run build`, `npm run fixtures` and `npm test` for development checks. Native tests require their platform toolchains. [Quality status](docs/QUALITY.md) · [Schemas](docs/schemas/README.md) · [Architecture](docs/adr/003-native-macos.md).

## License

A project license has not been selected; `package.json` declares `UNLICENSED`. Public source availability is not a license grant. Third-party components retain their own [licenses and notices](docs/dependencies.md).
