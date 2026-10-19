# Design

## Source of truth
- Status: Active — 사용자가 A(고요한 스튜디오)를 선택. 중앙 문서 영역 확대와 수백 페이지 처리 요구 반영.
- Last refreshed: 2026-10-19
- Primary product surfaces: macOS 데스크톱 앱의 프로젝트·버전 입력, 타임라인, 원문 비교, 대응 검토, 내보내기.
- Evidence reviewed: PLAN.md §5~9, PROGRESS.md, packages/schema 및 query. 기존 UI/브랜드/컴포넌트/시각 기준은 없다.

## Brand
- Personality: 차분하고 정확한 문서 작업 도구. 한국어 우선.
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
- Tone: 간결하고 구체적인 한국어.
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
