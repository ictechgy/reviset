# Interface languages and original document text

Reviset provides English and Korean interface resources. Choose **System Default**, **English**, or **한국어** in **Reviset → Settings…** (`⌘,`). System Default chooses the first supported language in the system preference order and falls back to English. It resolves that order at launch. After changing the macOS language order, reopen Reviset to apply it. The choice is stored under the app-owned `RevisetUILanguage` preference; the app does not write `AppleLanguages`.

The app's own labels, messages, evidence explanations, import/review sheets and workbook accessibility metadata update in place. The existing model, analysis request, source selection and draft values are retained. Some macOS-owned menu items follow the process or system app language and can require reopening. This does not require restarting analysis.

## Display and source boundaries

| Translated presentation | Preserved source data |
| --- | --- |
| Menus, buttons, help, accessibility labels, known status/reason labels | Document text, notes, cell values, formulas and number-format source |
| App-generated errors and progress; known backend error codes | Unknown backend error detail, IDs, paths, project/version/sheet names |
| Count phrases and displayed dates | User-authored association/release reasons, source timestamps, machine reason codes |

UI-generated messages retain a semantic key and explicit arguments until presentation. An immutable language snapshot formats each message. Arguments are inserted once: text containing `{0}`, `%@`, percent signs, apparent localization keys or instructions remains quoted data. Native resources use the named `Reviset.strings` table so they cannot implicitly reinterpret document strings as keys.

Display dates use the selected English (`en_US`) or Korean (`ko_KR`) locale and the local timezone. Stored ISO timestamps, raw workbook values and technical coordinates are unchanged. English count phrases distinguish one/other; Korean uses the other form. A language preference is not part of a canonical report or comparison setting.

## OCR and document languages

Interface translation does not extend document recognition coverage. General Vision OCR and document-table recognition remain configured for **Korean and English**, with automatic language detection and language correction disabled. Language names beside contextual observations describe their recorded codes. They are not a supported-recognition-language selector.

Original PPTX/PDF text layers and workbook strings can preserve Unicode from other scripts where extraction succeeds. Reading order, glyph mapping, RTL/bidi, vertical writing, regional numeric notation and OCR accuracy retain their existing limitations. Japanese, Chinese and other script OCR are not newly qualified by translating the UI. CSV remains UTF-8 and comma-delimited.

## Exports and AI clients

The native app pins its selected display language before opening the export folder picker. JSON/JSONL, fixed report IDs and all quoted source fields are independent of that language. Native document exports use language-suffixed folders, `Reviset-<id12>.en` and `Reviset-<id12>.ko`, inside the chosen destination so both languages can coexist. A document export requires a new or empty report folder: repeating an export into the same nonempty folder fails with `EXPORT_DESTINATION_NOT_EMPTY`; choose a different destination folder to preserve the earlier export.

English and Korean workbook Markdown exports can coexist in one folder: the legacy English file is `<export_id>.md`, and Korean uses `<export_id>.ko.md`; their paired JSON/JSONL, copied originals and export ID stay the same.

CLI export language is explicit:

```sh
npm run cli -- export --project PROJECT --out NEW_FOLDER --language en
npm run cli -- workbook-export --project WORKBOOK_PROJECT --out FOLDER --language ko
```

Omitting `--language` preserves prior defaults: Korean for document Markdown and English for workbook Markdown. Only `en` and `ko` are accepted. Document CLI exports use the exact `--out` path and require it to be new or empty; choose separate folders for each language. MCP tool descriptions remain English, its schemas stay unchanged, and original text remains exact evidence. A connected AI client can write its explanation in the user's language; Reviset itself performs no model calls or automatic source translation.

## Resources and checks

Semantic keys and paired translations live in `apps/macos/Localization/*.json`. The build validates duplicate keys, required locales, matching numbered placeholders, source key references and argument counts, then writes `en.lproj/Reviset.strings` and `ko.lproj/Reviset.strings` into the app before signing. English is the fallback. Resource packaging and the shared Swift source list are used by the native build and regression probes.

Localization checks cover language resolution/persistence, missing-key fallback, zero/one/many, nested messages, opaque source arguments, date/code labels and invalid catalogs. Export checks compare machine outputs byte for byte across languages and retain raw multilingual/formula-like text. Packaged-app language/draft/grid captures have their own source-bound qualification; source tests alone do not establish complete layout or VoiceOver coverage.

Engine-generated descriptions, coverage reason strings and machine codes remain verbatim evidence in Markdown as well as JSON/JSONL. Korean Markdown can therefore contain English engine prose and original multilingual quotations. Known backend validation codes receive translated guidance in the app; their exact code and diagnostic detail remain visible. Unknown diagnostics retain their original language.
