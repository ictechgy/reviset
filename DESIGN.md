# Design

## Source of truth
- Status: Active — 사용자가 A(고요한 스튜디오)를 선택. 중앙 문서 영역 확대와 수백 페이지 처리 요구 반영.
- Last refreshed: 2026-10-23
- Primary product surfaces: macOS 데스크톱 앱의 프로젝트·버전 입력, 타임라인, 원문 비교, 대응 검토, 내보내기.
- Evidence reviewed: PLAN.md §5~9, PROGRESS.md, packages/schema 및 query. 기존 UI/브랜드/컴포넌트/시각 기준은 없다.

## Brand
- Product name: **Reviset / 리비셋** — 사용자가 2026-10-22 확정. 이전 이름 Docver. 표시 브랜드와 호환성 식별자의 경계는 [리네이밍 기록](docs/RENAMING.md)을 따른다.
- Personality: 차분하고 정확한 문서 작업 도구. 영어·한국어 UI를 지원하고 시스템 언어를 기본으로 따른다.
- Trust signals: 고정 보고서, 원문 페이지·인용, 추정/사용자 확정·관측 한계 구분.
- Avoid: 마케팅형 hero, 과장된 정확도, 의미 없는 장식, 미지원 기능의 완료 표시.

## Product goals
- Goals: Finder에서 문서를 선택하고 순서/bundle을 정해 분석, 전체 중간 이력을 읽고 원문을 확인, 대응 수정과 export를 앱에서 완료.
- Non-goals: 원본 편집, 클라우드 업로드, 모델 계정 필수화, 첫/끝 비교만 제공.
- Success signals: 5버전 합성 작업, 재실행 복원, 부분 실패/취소, 같은 report의 MCP/export 일치, 패키지 .app 실제 실행.

## Personas and jobs
- Primary personas: 여러 차례 수정된 발표자료를 검토하는 작성자·리뷰어.
- User jobs: 숫자가 언제 바뀌었는지, 중간 삽입/삭제와 재배치, 원문 근거 확인.
- Key contexts of use: 오프라인 macOS 데스크톱, 파일 형식이 섞인 여러 버전.

## Information architecture
- Primary navigation: 프로젝트 목록, 전체 이력, 비교/대응 검토, AI·내보내기.
- Core routes/screens: 빈 상태/가져오기 sheet, 활성 report 타임라인·비교, 관측 한계, MCP 연결 안내.
- Content hierarchy: 프로젝트 → 고정 보고서 → 비교 구간 → 변경 → 원문/근거.

## Design principles
- 원문 사실·표시 상태의 관측/추정·페이지 대응 추정을 구분하고 unavailable을 삭제로 표현하지 않는다.
- 작업 가능한 다음 행동을 제공하며 과거 report를 고정해서 다시 읽게 한다.
- Tradeoffs: PPTX는 실제 변환 PDF를 우선하며 구조 보기는 변환 실패 fallback이다. 원본 PDF/변환 화면/추정 OCR의 출처를 표시하고 충실도를 과장하지 않는다.

## Visual language
- Color: A 시안의 밝은 macOS형 중립색과 파란 강조색을 기본으로 사용. 상태는 색과 문자 함께 표시.
- Typography: 시스템 -apple-system/sans-serif, 한글 본문 13~15px, 주요 제목 20~28px.
- Spacing/layout rhythm: 4/8px 기반, 문서 비교가 중심이고 긴 hash는 축약.
- Shape/radius/elevation: A 시안의 얇은 경계·낮은 그림자·작은 곡률의 panel·sheet.
- Motion: 짧은 상태 전환, reduced-motion 준수.
- Imagery/iconography: 실제 문서 preview 또는 명시적 구조 보기. 차트/숫자 생성으로 원문을 채우지 않는다.

## Components
- Existing components to reuse: 없음. 공통 query/report 계약을 재사용.
- New/changed components: AppShell, ProjectList, ImportSheet, VersionBar, HistoryList, ComparePane, PageView, MappingControls, ExportPanel. PageView는 원본 PDF/변환 PPTX 출처, OCR 추정 점수·원문 확인, 글꼴 대체/누락 경고를 한국어로 제공한다. 화면 변경은 의미상 삭제와 구분한다.
- Variants and states: 선택/비활성/처리 중/오류/부분 성공/관측 공백.
- Token/component ownership: apps/macos의 SwiftUI·AppKit view와 시스템 색상/폰트.

## Accessibility
- Target standard: WCAG 2.2 AA를 지향, 이번 단계는 핵심 키보드/대비/label 확인.
- Keyboard/focus behavior: native menu Cmd+O, Cmd+Option+F 집중 모드, Cmd+Option+I 근거 패널, sheet 닫기 Escape, native control.
- Contrast/readability: 저대비 작은 텍스트 지양, 변경은 text label과 전후값.
- Screen-reader semantics: SwiftUI Text·Label·Button·Picker·sheet의 native 접근성 의미. VoiceOver 실기 전체 검증은 미완료.
- Reduced motion and sensory considerations: 번쩍임 없음, prefers-reduced-motion.

## Responsive behavior
- Supported breakpoints/devices: macOS 1100×740 이상, 기준 1440×960.
- Layout adaptations: 좁은 창에서는 보조 패널 축소, 내용 스크롤. 문서 2쪽은 실제 비율 유지. 집중 모드에서 사이드바 숨김, 한 페이지 크게 보기, 100~200% 확대, 근거 패널/변경 목록 접기.
- Touch/hover differences: hover 전용 행동 금지, 키보드 대응.

## Interaction states
- Loading: 작업 중 표시와 취소. 렌더/분석을 UI thread에 두지 않는다.
- Empty: 파일 가져오기와 합성 데모 시작.
- Error: 파일별 오류·관측 한계, 재시도 행동. 기존 report 유지.
- Success: report 갱신과 고정 ID, export 결과 알림.
- Disabled: 분석 중 중복 쓰기 금지, 조건 충족 전 분석/연결 비활성.
- Offline/slow network: 앱 자체는 로컬에서 동작. 외부 네트워크 불필요.

## Content voice
- Tone: 간결하고 구체적인 영어·한국어. 영어 문구를 기준으로 번역의 의미와 불확실성 표현을 대조한다.
- Terminology: 버전, 페이지, 변경, 대응, 관측 한계, 고정 보고서.
- Microcopy rules: 구조 보기는 원본 렌더와 구분, 추정 점수를 확률이라고 하지 않는다.
- OCR 근거: 최초 판독과 문맥 재판독을 따로 표시한다. 재판독이 비교에 쓰여도 최초 문자열·점수와 각 조건의 결과를 열어 볼 수 있다. 보류한 재판독을 숨은 원문으로 표시하지 않는다. 수많은 추출 행은 지연 생성한다. 조건별 언어·확대 배율·문맥 범위·판독 점수와 상태를 함께 표시하며, 최초 판독 연결이 검증되지 않은 기록은 명시한다.

## Implementation constraints
- Framework/styling system: SwiftUI + AppKit + PDFKit. 별도 Node helper가 TypeScript 공통 엔진을 실행. 외부 CDN·폰트 없음.
- Design-token constraints: 사용자 선택 후 palette 고정, 근거 없는 theme 혼합 금지.
- Performance constraints: 분석 별도 프로세스, 전체 결과는 디스크 stage, UI에는 작은 projection. 페이지별 원문 요청·PDFKit 지연 렌더·변경/계보 LazyVStack. 300페이지씩 3버전의 패키지 앱 검증.
- Compatibility constraints: 우선 현재 arm64 Mac용 로컬 .app/zip. 서명·공증·다른 아키텍처는 검증 범위 별도.
- Test/screenshot expectations: 시안 3개 실제 screenshot을 사용자에게 제시. 완성 앱도 실제 패키지 실행 screenshot과 모델 기반 작업 검증 기록. OS 입력 자동화·전체 접근성 검증은 별도.

## Open questions
- [x] A 선택 / 사용자 / 중앙 문서 크게 보기와 수백 페이지 지원을 추가 조건으로 확정.
- [ ] Developer ID 및 공증 / 사용자 / 다른 Mac 공개 배포 시 필요. 로컬 앱 사용은 먼저 진행.


## Manual page relations — engine44 implementation contract
- Claude's local UI discussion recommends a single paired native searchable List sheet for continuation1:1/split1:N/mergeN:1/unlink. Keep lightA and document preview dominant. Scope is design discussion, not implementation approval.
- Reuse current before/after pages as initial selections. Each side supports native multiple selection and 번호·요약 검색 (current compact180-character summaries, not full-text search). Hundreds-page lists stay lazy; any pages can be chosen, at most32 members per relation.
- Show selected counts, cardinality, exact displaced pairs and residual-branch behavior before one Apply action. Reason is required, max2000UTF16 units, preserved verbatim. Cancel before apply writes nothing; apply atomically modifies the draft and starts analysis. Cancelling analysis leaves a pending dirty draft and prior report available.
- Every branch remains a separately labelled page button in history and structural-event evidence. Preserve a selected branch across delayed range updates. Counterparts follow directed accepted edges; undirected family membership must not invent ancestry.
- Split/merge events describe topology, not confirmed text deletion/replacement. Mark text comparison withheld and preserve each member's actual source/OCR provenance. Range family summaries explicitly use directed reachability, not complete bipartite correspondence. Full edge graph is available in JSON/export/read-onlyMCP.

## Native canvas review45 follow-up
Claude reviewed three actual app45 captures (focus p300, split/mergehistory,600scancompare), scope staticvisibleUIonly, sheets excluded for transparent cacheDisplaycapture. Valid REQUEST_CHANGES: comparetimeline duplicates rangecontrols and fixed240pt changelist reducescanvas; pageedge contrast absent; historylegend separated by oversizedemptygraphpane. Pixel estimates in advisor text are screenshotpixels,not verifiedpointmeasurements. Adopt removal of duplicate timeline incompare, nativeNSSplitViewControllerdraggable document/listpanes(defaultlist140pt), independentpersistedcompare/historypaneheights, compactgraphforsmallhistory, legendinsidegraph, nativeunderpagebackground/pagebreaks/shadows. Preservefocus and independentviewport zoom/sourcecoordinates; no canonicalengine/renderchange. Explicit sheetnativebackground fixes actualviewopacity before newcapture; no screenshotediting. Native UIQA must verifyactualnewrender and dividerbehavior.

### Native49 visible history legend
Actual48fivecaptureClaude review confirms largerdocumentcanvas/pageedges/compactchangelist/sheets, but historylegend wasclipped atsplitboundary. Keep “— 관측 없음…” underhistorysubtitleoutside scrollcontent, alwaysvisible at anydividerposition. Native split remainsuserresizable; source/diff unchanged. The applybuttonalreadyusesborderedProminent+defaultAction; advisorrecommendationtoaddthoseisnot a newcodefix. Capturemayreflectinactivewindow/systemaccent; no unverifiedactivecolorclaim.

### 2026-10-20 provided PDF appearance
- A qualified supplied PDF may provide the native PPTX display while raw OOXML text/notes/hidden slides remain primary source observations. Show `제공 PDF · 페이지 대응 추정`, not a PowerPoint fidelity certificate.
- Distinguish supplied-PDF pixel differences from source edits. If unchanged PPTX bytes have different PDFs, explain the export/source inconsistency as a review gap. Missing one page's appearance is a page gap; it does not cancel other page comparisons.
- Selecting PDF appearance evidence must navigate to the associated primary PPTX slide. Keep source coordinate overlays withheld across an inferred relation. Count provided PDF display separately from missing/conversion previews.

### Native51 supplied-PDF evidence actions
- The explicit evidence button and automatic change selection both resolve supplied-PDF page IDs to the primary PPTX slide. Preserve explicit navigation through subsequent selection updates; an unmapped PDF page keeps the current source selection and shows a Korean explanation.
- Label inferred supplied-PDF visual events `제공 PDF 화면 차이`. Identical source text in these events and coverage gaps uses neutral text color, while actual text edit before/after retains its edit colors. The supplied-PDF association label and source warning remain visible.
- Actual production AppModel regression covers left/right evidence actions, persisted navigation pins, unmapped secondary guards, direct source and PDF-only navigation. Packaged-app smoke must execute the explicit action as well as automatic selection; source tests alone do not qualify visible app behavior.

### Native52 reversible import bundles and safe evidence selection
- Automatic evidence selection applies the same primary-page membership invariant as explicit evidence buttons. If same-version secondary evidence cannot be resolved, retain a valid source selection and explain the missing correspondence. A genuinely absent before/after side stays empty.
- Import rows retain one stable identity and current label per file. Grouping creates a separate group identity; moving a group keeps it together. 묶음 해제 places both original members next to each other at the group's position. If the group label was edited, retain it on the first selected member and restore the other's label. Do not reorder PDF-first input silently.
- Show an explicit same-version PPTX+PDF label, grouping help for disabled states, and a visible 묶음 해제 action. Hash selected file bytes off the UI thread; while hashing/copying disable draft mutations and show progress. A changed input explains which file must be selected again. Original source files are never overwritten.
- The SHA guard is an optional private create input, verified against bytes actually copied. It is not an OCR/fidelity certificate or a canonical observation field. Real pre-create UI supplies it; old internal demo/programmatic inputs remain compatible.
- Same-version page correction will use a separate fixed-scope sheet, preserving the current adjacent-version sheet's guards and the central canvas. That feature remains open;52 only handles pre-create grouping/ungrouping.

- Evidence-navigation warnings have separate state from analysis/export status, clear on a valid new selection, new analysis or deliberate page navigation, and never overwrite progress. A mixed internal legacy/selected import row preserves positional verification for every selected member; missing per-file identities are explicit null slots rather than dropping checks for the whole bundle.

## Native53 same-version page correction
- Dedicated native sheet: one frozen project/report/revision, separate from adjacent-version split/merge. Open from the document column link button. Latest clean reports can Apply; older/dirty snapshots support inspection only.
- Searchable native lists keep one source slide and one supplied PDF page selected, with a selected-page jump outside filtered results. Only selected previews load. PPTX preview requests its independent source basis and labels structure or LibreOffice conversion; the supplied PDF remains a separate original.
- Show current inferred/human association, source-wide unlink/block, exact replacement pairs and prior human reasons, persisted and proposed mismatch/geometry/reuse/hidden/missing-raster warnings. Reason is required, preserved verbatim, limited to2000UTF16 units, and applied by an explicit button without Return as a default action to protect Hangul composition.
- Failed CAS retains sheet edits; cancellation before Apply writes nothing. Applied dirty history remains pending if analysis is cancelled. History entries page through the read-only query and expand complete Unicode reasons. Human links say 사용자 연결 · 참고용 and never certify PowerPoint fidelity.
- Page Picker/go supersedes an older evidence pin. Split/merge captions show page sets on each side of one arrow; generated vN prefixes are not duplicated. Import introduction states that PPTX+PDF bundling is optional.
- Actual53 app captures and Claude visual review are pending; earlier52 visual REQUEST_CHANGES stays open until new evidence closes its scope.

- Structure fallback previews use a light contrasting well and a neutral one-device-pixel page outline. The blue overlay remains reserved for selected change evidence; neutral-edge inspection deselects evidence without removing that feature. Bundle page lists and preview wells share the same fixed center gutter. Schematic text uses actual font line-height within its inset element height to reduce small-preview clipping; it does not claim original fonts or complete PowerPoint layout fidelity.

- Structure fit leaves8pt inside the canvas on every edge, including extreme page ratios. Bundle preview captions reserve equal two-line height so the two wells start and end together. Full-fit extreme-page text may be tiny; page identity, zoom and extracted-text controls remain the reading paths, without stretching or fabricating the source.

## 2026-10-21 review follow-up
- A project switch invalidates pending selection and MCP requests. Copy is available only for a ready configuration owned by the current project. An unreadable draft disables mutation while its fixed reports, original pages, export and read-only MCP remain accessible. Healthy projects remain usable; the bad draft body is never rewritten by recovery reads.
- A timeline reorder with recorded human relations or supplied-PDF decisions requires a native confirmation stating that the current draft's decisions will reset and old fixed reports remain readable. Pending, unanalyzed decisions cannot be discarded by reordering. Confirmation is bound to the captured project and draft hash.
- History change rows identify their version interval. Selecting one opens that interval in comparison and selects its actual evidence. Empty, filtered-empty, loading and failed comparisons have distinct messages; a single-version report uses one wide document column.
- Page changes cancel superseded helper requests. Keep the already opened document view during verification of the next page, with a visible previous-page loading label and disabled evidence interaction until the verified payload arrives. Preserve full source-hash validation. Invalid typed page input restores the actual current page number.
- Notes distinguish empty supported notes from unavailable, unsupported and failed observations. Occluded/struck/revealed appearance text uses neutral color because appearance alone does not establish semantic deletion. Optional reference-viewer titles include vN as well as the source label.
- A new interval clears the previous interval's rows/inspector while loading or failed. Cancelling or failing an analysis/import must settle loading ownership and refresh the retained report's comparison. Retained page payloads cannot supply evidence or extracted content until both report and page identity match the request; current-page failure clears the stale payload.
- The adjacent-version mapping sheet shows the selected pages' stored assigned relations and their review status, separately from displaced conflicts. An empty assigned edge is not candidate absence; the caption explicitly says that other similar candidates may exist. These are current-state labels, not a claim that the proposed edit was already applied.

- Starting analysis shows an explicit analysis-in-progress message while retained change rows are unavailable. Starting import marks an interrupted retained-range query unavailable until it is refreshed; neither state claims that there are no changes. User cancellation escalates after3s only for the captured still-current cancelled analysis process.

- The inspector preserves exact source strings and highlights only differing lexical runs with color plus underline; neutral appearance/coverage/structure changes remain neutral. Work is bounded to4096UTF16 and512tokens per side, otherwise text is shown neutrally. Every evidence button names its side, explicit vN and page; ambiguous historical revision aliases are not guessed. The mapping sheet uses taller scrollable lists with a visible total/search/scroll hint, retaining search and selected-page chips.

- Initial page verification says a page is being checked unless a retained payload actually exists. Pending human decisions prompt analysis before reorder, without offering a destructive reset; active confirmation freezes reorder arrows. MCP errors have project-owned failure text and an explicit retry; retry generations prevent an older same-project response from overwriting a newer attempt. Native/Office helper directory enumeration is limited to the read allowlist while directory metadata traversal remains available.

- Mapping sheet keeps its title/cancel, validation and Apply footer outside a scrolling middle form. The two page lists have a stable280pt height; long conflicts, selection captions, reasons and failures scroll without pushing the primary controls out of the fixed720pt sheet.


## Spreadsheet workspace · 2026-10-22

- Source contract: docs/SPREADSHEETS.md. Add a workbook window in this native app, sharing its exclusive library and Bridge. Existing document views/reports retain their contracts. Entry points: toolbar and File menu, with Command-Shift-O.
- Preserve the selected light macOS direction. Central space belongs to a large native, virtualized cell grid; projects/sheets/versions and changes/details surround it. A file's print pagination is not worksheet structure.
- Read XLSX/ODS/CSV, show exact physical addresses and raw formulas separately from saved results. Never label cached results as freshly calculated. Preserve strings, number types, blank/zero, hidden content and unsupported coverage. Show inferred row association.
- Scoped loading/failure supersedes old actions. Independent query generations own their processes; stale data cannot become authority for copy/export/publish. Both workspace kinds share one admitted analysis; only the owner may cancel.
- Local releases require an explicit fixed report, bounded label and reason. UI describes them as local records, not a network delivery, user authentication, or server approval. Exports use fixed report/occurrence/sheet identities. MCP configuration grants a project scope; each response resolves `latest` to a fixed report ID, and subsequent reads and citations must use that fixed ID.
- Native verification covers actual AppKit grid data, formula/value inspector, version and change navigation, CSV/XLSX/ODS sources, Unicode, error/retry/cancel state, and packaged MCP. Actual screenshots are reviewed by Claude; Grok source/UI review is separately attributed. No pre-credit for future tests.


### Qualified workbook evidence reading · 2026-10-22
- Each cell field displays the actual returned UTF-16 half-open range, its total and an explicit end/continuation annotation outside the verbatim source. Before/after sections each expose the shared next/first pager before format/style details and state that both sides move together. Short fields already read on the first part explain an empty later fragment. Failed continuation retains a restart-at-zero action using the same scoped query generation.
- Known change explanations are localized for display while immutable report/MCP descriptions remain verbatim. Physical source addresses, inferred association, unavailable cache and unresolved formula/cross-format caveats remain visible.
- Actual dense qualification reconstructs1803UTF16 units across two responses, advances both returned A1 fragments to1024–1803, verifies exact independent slices and restores the first page before continuing. This is a production model action plus separate static render capture, not OS click automation. Current captures and provider scopes are recorded in docs/WORKBOOK-2026-10-22.md.


### Workbook read recovery · 2026-10-22
- Address validation is separate from grid read failure. A rejected change with missing version evidence clears the previous cell anchor. Failed grid reads have a direct retry; failed cell reads offer retry on the first part and restart at zero after a continuation failure. Every retry retains report, version, sheet and physical address scope, and supersedes its previous request.
- Cell detail responses must match the requested project/report/occurrence/sheet and physical address before display. Missing observations remain distinct from query failures.
- While comparing moved rows with different visible windows and a valid after-side address, the shared navigation range explicitly identifies the after side; each pane retains its own actual coordinates. Shared windows and before-only evidence retain a neutral range label. Range movement still returns to shared physical coordinates.
- Empty, unavailable and already-read fragment notices use secondary system text, separate from selectable monospaced source. Empty later fragments do not repeat a source-end marker. Verbatim strings and UTF-16 offsets remain unchanged.
- Label the change list's fixed query interval explicitly. Selecting one event may show its adjacent evidence pair above while retaining the wider list interval; explain both scopes together. Paged lists name the next/previous action rather than implying that the visible rows are all changes.


## English and Korean interface — 2026-10-23
- Scope: native document and workbook windows, menus/settings, errors/progress, evidence/coverage labels, accessibility, counts and displayed dates. Preference is System Default / English / 한국어, stored in an app-owned preference. Unsupported system languages fall back to English through the supported preference order.
- Use stable semantic keys in the named native `Reviset.strings` table with explicit arguments. Both locale resources ship in the bundle; build validates key and placeholder parity. Interpolated user arguments are formatted once and never interpreted as localization keys or format instructions.
- An immutable localizer snapshot formats messages. UI-generated transient messages retain key/arguments and resolve at display time; background errors retain code and raw detail. Unknown error details and user-authored reasons remain verbatim.
- Live language changes retain the existing model, import/review drafts, selections, analysis requests and document viewports. Do not rebuild the workspace using `.id(language)`. SwiftUI observes the preference; AppKit grid caches/accessibility explicitly refresh for a language change. System-owned menu items may follow the process/macOS app language until reopening.
- Document text, project/version/sheet names, formulas, file paths, human reasons, IDs and machine reason codes remain exact source data. UI preferences do not enter canonical report identities. OCR recognition and document-table recognition remain configured for Korean/English; UI selection does not change them or claim new language accuracy.
- Human Markdown exports accept an explicit en/ko display language, pinned at export start; legacy callers retain Korean for document Markdown and English for workbook Markdown. Native document folders use `.en`/`.ko` suffixes; each document export requires a new or empty report folder. Workbook languages share JSON/JSONL and copied originals while using `.md`/`.ko.md` human reports. JSON/JSONL, evidence source text and report IDs stay unchanged. MCP instructions/tool descriptions remain English and its read-only schemas stay unchanged.
- Qualification includes fallback/persistence, zero/one/many, placeholders containing braces/percent/key-like data, raw text and report identity invariants, language switch with draft/selection retained, refreshed grid accessibility, and actual packaged-app English/Korean captures. RTL/vertical writing, additional OCR models and general script accuracy are outside this interface-localization scope.
- Claude and Grok design discussions at base `a70974d` both requested stable semantic keys, typed stored messages and explicit bundle packaging. Adopt named resources and single-pass argument formatting; use app-owned preference instead of writing AppleLanguages. Code and visual reviews are separately snapshot-bound and are not implied by design consultation.

## Customizable native workspaces and Windows — 2026-10-23
- Native surfaces: retain SwiftUI/AppKit/PDFKit on macOS; use WPF native controls on Windows with the same local Node engine and fixed-report bridge. No browser shell or remote document upload is required.
- Keep the central source comparison dominant. Offer Balanced, Document Focus and Review presets; independently resize and hide the project, changes and evidence panels. Changes can dock below or beside the comparison; evidence can sit on either side. Offer a visible Layout menu, named saved layouts and a reset action. A bounded docking model is preferable to floating panels that can become inaccessible off screen.
- Layout is an app-owned, versioned display preference, separate for document and workbook workspaces. Save only geometry/visibility/docking and bounded user preset names. Never add layout, locale or window geometry to reports, source observations, query schemas or MCP responses. Invalid or obsolete values recover to safe defaults; a temporarily smaller window must not erase preferred dimensions.
- Retain existing native comparison hosts, PDF/grid instances, selections, report IDs, import drafts, zoom and manually scrolled viewports when applying a layout. Move/collapse native panes instead of reconstructing the workspace with a layout identity. Layout controls act on the active window.
- All layout actions are available through native buttons/menus and keyboard focus. Drag splitters have accessible names. Names are verbatim user data, with a bounded count and length; cancelling Save writes nothing. Resetting layout never deletes projects or reports.
- Windows uses native file dialogs, virtualized data grids and bounded page previews. Import, staged analysis/commit, fixed report navigation, source/evidence, export and project-scoped MCP reuse the existing contracts. UI language is English/Korean and does not translate source data.
- Platform capabilities remain explicit. Apple Vision/PDFKit OCR and the macOS-confined LibreOffice renderer are unavailable on Windows until a qualified Windows adapter exists. Never run an Office converter without its required confinement, or substitute structural reconstruction for an original render without a visible label. Portable PDF text/appearance extraction, PPTX structure and XLSX/ODS/CSV analysis remain available.
- Qualify macOS native host/viewport preservation, preference corruption/reopen and actual layouts. Cross-compiling Windows is a build check; actual Windows process, engine, preview, grid, export, cancellation and layout checks require a Windows runner. Preserve separate raw Claude/Devin/Grok design and implementation-review records without attributing a design suggestion as approval.
