# Docver → Reviset

The product is now **Reviset** (리비셋). The canonical repository is
[ictechgy/reviset](https://github.com/ictechgy/reviset).

## App and build names

`npm run mac:build` produces `release/Reviset.app`, with the executable
`Contents/MacOS/Reviset`. The app's windows, menu/Finder name, icon filename,
export-folder prefix, CLI help, package name, and MCP server identity use Reviset.

To select a separate local build:

```sh
REVISET_APP_NAME=Reviset-Local.app npm run mac:build
open release/Reviset-Local.app
```

`DOCVER_APP_NAME` remains a build-input alias. `REVISET_APP_NAME` takes precedence
when both are set. Legacy `Docver[-suffix].app` filenames are accepted, but the
executable and displayed product name inside a newly built bundle are Reviset.
Only validated app basenames inside `release/` are accepted.

The host-bound optional viewer still requires an explicit flag and a separate
`Reviset-Render.app` or `Reviset-Review.app` build. The new flag is
`REVISET_OPTIONAL_SIDECAR=host-bound`; the legacy `DOCVER_OPTIONAL_SIDECAR` alias
and legacy Render/Review filenames remain accepted. The new flag takes
precedence. Default builds do not include host font metadata or viewer settings.

## Existing libraries and citations

The rename does not move or rewrite a library. These compatibility identifiers
remain unchanged:

| Identifier | Retained value | Purpose |
| --- | --- | --- |
| App library | `~/Library/Application Support/Docver/library/` | Reopen the existing documents and workbooks |
| CLI/MCP default store | `.docver/` | Continue reading the same checkout-local store |
| SQLite filename | `docver.sqlite` | Reuse the existing database |
| macOS bundle identifier | `org.docver.native` | Retain application identity and preferences |
| Report resource scheme | `docver://` | Keep existing fixed-report citations readable |

Schema and engine versions, report IDs, original-document bytes, and report
contents are unchanged. Internal helper names, `DOCVER_*` runtime/test controls,
and preference/accessibility keys also retain their compatibility names.
Reviset and Docver share the existing library lock; quit one before opening the
other against the same library.

New app-generated MCP configuration uses the `reviset` key in `mcpServers`, and
the server announces its name as `reviset`. The key is a client label. Existing
configuration labeled `docver` can still connect if its executable paths remain
valid. Copy configuration again from **AI·내보내기** when switching to Reviset or
moving the app. Keep using the returned fixed report IDs and `docver://` URIs.

## Historical validation

Earlier validation records and preserved Docver app bundles keep their original
names, source SHAs, and screenshots. They describe those exact builds. Renaming
does not extend their results to a new build, change the project license, or
qualify a public installer. `HANDOFF.md` and `PLAN.md` remain original records.
