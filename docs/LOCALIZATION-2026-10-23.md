# English/Korean interface qualification — 2026-10-23

This record covers native interface localization, human Markdown export copy and preservation of original evidence. It does not extend OCR language coverage or certify PowerPoint rendering fidelity.

## Source and app binding

- Public baseline: `a70974d78d4802a3c93f00b7b4055ed852323e1f`.
- Final executable source: `9ba86af1a24f0caa3603ee577e81b5bec3d00701` (clean build).
- Complete implementation patch SHA-256: `50e73fcbb145add416f13e468f20981a8ec1f4459ec17a8bae26768ca60e8573` (55 changed files).
- Local qualified app: `release/Reviset-Languages-7.app`.
- Tracked source-manifest SHA-256 during build, app execution, MCP and post-run audit: `1a36c191c32802e6be5e720d44c0aa28ad1ef411b0afc486a354f769c4270830`.
- App executable SHA-256: `e47c0d28dfd432e580066b89af982824924311cb27e7724b7f3d36e3713cf1f0`.
- Bundled Node v24.19.0 SHA-256: `1781eb7d1b56241a6ac5176120a8fc75df51fadc0d0714f02cfeef56ce96f508`.

Documentation and screenshot publication after this code snapshot do not rebuild or relabel the app. Its build-info retains the source commit above. Signatures verified before and after execution are local ad-hoc signatures; public notarized installer distribution remains outstanding.

## Executed checks

| Check | Actual source | Result |
| --- | --- | --- |
| Complete integration suite | `f9e5612e933c577b7064fd6116f53b858ea7dfbf` | 464 passed, 0 failed/skipped, 1,219.9 seconds |
| Final related native/localization/export regression set | `9ba86af1a24f0caa3603ee577e81b5bec3d00701` | 17 passed, 0 failed/skipped, 67.9 seconds |
| TypeScript and complete Swift 5/macOS 14 typecheck | Final executable source | Passed; Swift warnings treated as errors |
| Catalog, literal references and placeholder validation | Final executable source | 944 English/Korean keys; none unreferenced |
| Packaged native app | Final executable source | Four successful document/workbook fresh/reopen runs |
| Bundled MCP, using all four app-generated configurations | Final executable source | Identical tool schemas and locale-paired query results |
| Post-run integrity and strict app/node signature verification | Final executable source | Passed |

The complete suite ran before the final UI/review fixes and is not presented as a full-suite run at the final commit. Those changes received the final related regression set, compiler checks and actual final-app execution above. Core extraction/diff/query code and MCP schemas were unchanged by those later fixes. The first isolated-suite attempt lacked generated fixtures and failed; the preserved second attempt generated them and passed.

Fresh-checkout preparation:

```sh
npm ci
npm run fixtures
npm run build
npm test
```

## Observed native behavior

The four runs were document-English fresh, document-Korean reopen, workbook-English fresh and workbook-Korean reopen. Each exercised in-process language changes and retained fixed report content. Document and workbook originals are repository-generated synthetic fixtures.

- Actual File/View submenu tracking presented all four app-owned labels in English and Korean. Closed native submenu caches can retain prior titles until the menu opens; testing only those caches produced an earlier false failure. The final check records titles while the real `NSMenu` is open, with timed cancellation.
- Document checks retained the same model, selected pages/change, report bytes, PDF view identity, supported 150% zoom, scroll origin and displayed page. The same fallback canvas retained its source while localized image/unsupported labels redrew.
- Import checks retained opaque titles and version labels containing braces, percent markers, Korean and Arabic. Untouched default titles followed the language. Native unchanged-value echoes no longer mark defaults edited; edited and explicitly cleared titles remain user data.
- Workbook checks retained model/grid/coordinator identity, cell selection, viewport and reveal authority. Cached headers, accessibility labels and tooltips refreshed. Row `1000` used identical ungrouped visible/accessibility digits.
- Both languages' document, import, defaults, structure, settings and workbook views were inspected in original-resolution captures. Long selected workbook mode text can use ordinary popup ellipsis; its complete text remains in the menu and section heading.

These are actual packaged-app model/actions, native field focus/commit and `NSMenu` tracking checks. They do not claim OS mouse/keyboard automation, a complete interaction matrix or a VoiceOver audit.

## Original evidence and AI reads

Each document MCP run checked 34 raw fields; each workbook run checked 50 cells against the stored fixed report. Locale-paired requests produced exact matching results and identical schemas. SQLite bytes did not change during these read-only sessions. The post-run audit also verified retained original asset hashes (eight document assets and three workbook assets per corresponding run), reopened report equality, app/backend/runtime hashes and the exact prior host language preference.

English/Korean export checks freeze JSON/JSONL and copied-source buffers before the second-language write. They preserve report/export IDs, user reasons, formulas and multilingual quotations, including key-like and format-like strings. Only human Markdown copy and its documented language-specific destination change.

OCR remains configured for Korean/English independently of UI language. The UI smoke result does not assert an unmeasured recognizer configuration. Additional script OCR, universal PDF interpretation and pixel-identical PowerPoint output remain outside this qualification.

## Review and retained evidence

The independent code/spec and architecture lanes reviewed the complete 55-file final implementation. The code lane returned **COMMENT / READY**, with no actionable findings; named LSP tooling was unavailable and full compiler diagnostics were used instead. The architecture lane returned **CLEAR**.

Claude and Grok completed independent full implementation reviews at `3f3d1c447e95909aa6182f00a4cdc27e06868ef6`, both returning COMMENT. Their findings and later native failures were fixed or adjudicated against source/runtime evidence. Both targeted advisor closure reviews returned **APPROVE** for the complete intervening H04→H09 delta (SHA-256 `62b8915f06f23648826a86e2e42b67b91cde7af7176e57a039e9816c5cb544a7`). That scope is finding closure rather than a second claim of full final-feature approval.

Local raw evidence is retained under `.omx/artifacts/localization-20261023/`: full-suite attempts, scoped source manifests, `review-08`, raw advisor invocations/prompts/stdout/stderr, native attempts 01–07 and their failures, plus successful menu/title experiments. These ignored working artifacts are not part of the public repository. The final native QA summary SHA-256 is `f7e0c7b19677bc7c4b6316d350e33b43ccd3066671de43200d375bd99d20e585`; its evidence index SHA-256 is `65e1e989783cadfa4b659666dfdf51f083077ce40fae7120e22ac8c2a97a37d1`.

## Published captures

The README images are byte-for-byte copies of the final app's synthetic-fixture captures:

| Repository image | SHA-256 |
| --- | --- |
| `images/document-comparison-en.png` | `94475b04148dd0f75bef31927409127b06522d4d800286724d27f7dc43dc5d47` |
| `images/workbook-comparison-en.png` | `7640fdf7b6d0f85ec8b1f179ecb275c69380e82e82f773abae55006568a7f2f4` |
| `images/document-comparison.png` | `0903286dd15d782cbe7ebf1beb0925daed03ea40abcb4b160a5a606f15e4423b` |
| `images/workbook-comparison.png` | `4b8cac16c9d85b81492a666bf212ea0360ba108cdf1743888a09f2243e1e89bd` |
