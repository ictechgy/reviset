# Windows native application

Reviset's Windows application uses WPF native controls and the same local Node engine as the macOS app. It requires Windows 10/11 x64. The portable package includes .NET and Node; no Office subscription, browser shell, or model account is required. Source files remain local.

## Build

On Windows x64, install the official .NET 10 SDK and Node 24, then run:

```powershell
npm ci --ignore-scripts
npm run build
npm run windows:build
```

The output is `release/Reviset-Windows-x64/Reviset.exe`. Keep the entire folder together: the native executable uses its adjacent `runtime/node.exe`, `backend`, and `node_modules`. Build metadata records the exact source commit, dirty state, official Node runtime URL/hash and patched PDF.js fingerprint. Node 24.22.1 is pinned by the packager and verified against its official SHA-256 before bundling. The package is not Authenticode signed.

The [Windows workflow](../.github/workflows/windows.yml) builds on an actual Windows runner, tests portable document/workbook processing, runs the packaged WPF smoke and uploads the portable ZIP with native evidence. A macOS cross-build is a compiler check, not evidence that the Windows application ran.

## Platform capabilities

| Capability | Windows implementation |
| --- | --- |
| PDF text and appearance observations | Shared PDF.js extraction, including explicit visibility uncertainty |
| PDF page display | Bounded PNG preview from a verified asset selected by fixed report/page identity |
| PPTX text, tables, shapes and notes | Shared original-structure extraction |
| XLSX, ODS and CSV | Shared sparse observations, formulas and stored values; no recalculation |
| JSON/JSONL/Markdown and read-only MCP | Shared fixed-report services |
| Apple Vision OCR | Unavailable on Windows; retained observations from existing reports remain data |
| Confined LibreOffice/ONLYOFFICE rendering | Unavailable on Windows until a qualified Windows confinement adapter exists |

PPTX structural content is labelled separately from an original page rendering. Image-only PDFs need an OCR adapter to obtain text; a page preview is not OCR. Windows does not automatically run a system Office installation without confinement. Conversion/OCR gaps remain explicit and are not reported as deletion or successful extraction.

## Layouts and data

Both native workspaces provide panel resizing, docking, visibility, built-in layouts and named saved layouts. Document and spreadsheet layouts are separate local display preferences. Changing layout does not modify source files, reports, report IDs, or MCP responses. Use Reset Layout to recover the default arrangement without deleting a project.

The app library and display preferences live under the user's local application data. A native exclusive library lock prevents two application writers from using the same library. Backend requests use UTF-8 pipes and argument arrays without shell interpolation. Page-preview requests cannot choose arbitrary file paths; original assets are hash-verified before rendering.

## Implementation and qualification

Native implementation and qualification are in progress on branch `feat/native-layout-windows`. Source/build availability and successful Windows runtime qualification are recorded separately. This document will name the tested commit and Windows workflow run when they have completed.

Implementation references: [Microsoft WPF/.NET 10](https://learn.microsoft.com/en-us/dotnet/desktop/wpf/whats-new/net100), [Desktop SDK project properties](https://learn.microsoft.com/en-us/dotnet/core/project-sdk/msbuild-props-desktop), [cross-platform Windows targeting](https://learn.microsoft.com/en-us/dotnet/core/tools/sdk-errors/netsdk1100), and [official Node release files](https://nodejs.org/dist/v24.22.1/).
