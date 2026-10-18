# 문서 버전 추적기 계획서

작성일: 2026-10-18 · 상태: 구현 전 계획 · 가칭: Document Version Tracker

## 1. 만들 제품과 성공 기준

여러 버전의 프레젠테이션 원본과 PDF를 한 프로젝트에 넣고, 처음부터 마지막까지 무엇이 추가·삭제·수정·이동됐는지 원문과 함께 따라가는 로컬 오픈소스 앱을 만든다.
사람은 타임라인과 비교 화면으로 읽고, AI는 각 버전의 정규화된 원문과 같은 변경 결과를 JSON·Markdown·읽기 전용 MCP로 읽는다. AI 연결은 후순위 부가기능이 아니라 v0.1의 결과물이다.

대표 성공 시나리오:

1. 사용자가 `초안.pptx → 검토본.pdf → 수정본.pptx → 최종.pdf`를 한 번에 넣고 순서를 확정한다.
2. 3쪽이 6쪽으로 옮겨져도 같은 슬라이드의 계보를 유지한다.
3. 예상 매출이 `100억 → 120억 → 110억`으로 바뀐 시점과 각 원문 위치를 확인한다.
4. 중간 버전에만 들어갔다가 사라진 슬라이드도 전체 이력에서 찾는다.
5. AI에게 “매출 전망이 바뀐 이력을 근거와 함께 정리해줘”라고 요청하면 MCP로 해당 변경과 페이지 증거를 조회할 수 있다.

## 2. 요구사항·가정·미정 선택

### 사용자가 확정한 요구

- 입력은 PPT 원본 또는 PDF 어느 하나만 있어도 성립한다. 원본과 PDF를 동시에 요구하지 않는다.
- 버전 사이에 `PPTX → PDF → PPTX`, `PDF → PPTX → PDF`처럼 형식이 양방향으로 바뀌어도 추적한다.
- 최초↔최종 비교뿐 아니라 모든 중간 단계의 추가·삭제·수정·이동을 읽을 수 있어야 한다.
- AI가 문서와 변경 이력을 읽기 쉬워야 하며 MCP 접근을 제공한다.
- 공개 가능한 오픈소스 프로젝트로 개발한다. 이번 산출물은 계획서이며 구현을 시작하지 않는다.

### 이 계획의 설계 가정

- “PPT 원본”의 기본 지원 형식은 `.pptx`로 해석한다. 바이너리 `.ppt`는 아래 결정 게이트에서 지원 여부를 확정한다.
- macOS를 첫 배포 대상으로 삼고, 핵심 엔진과 데이터 포맷은 Windows/Linux에서도 쓸 수 있게 분리한다.
- 원본 편집기보다 비교·계보 탐색을 우선한다. 파일은 사용자가 명시적으로 가져오며 원본을 덮어쓰지 않는다.
- 같은 버전의 PPTX와 내보낸 PDF는 선택적으로 묶는다. PDF-only 버전도 완전한 독립 입력이다.
- PDF는 한 페이지에 슬라이드 한 장인 일반 내보내기를 기본으로 한다. 유인물 PDF는 자동 판별 후 범위 밖임을 안내하거나 수동 분리로 처리한다.
- AI 서비스 계정과 모델 설치 없이도 모든 비교·내보내기·MCP 조회가 가능하게 만든다.

### 구현 중 증거로 결정할 선택

| 결정 게이트 | 기본안 | 확정 조건·대안 |
| --- | --- | --- |
| G1: 렌더러 | LibreOffice 로컬 변환 + PDF.js 표시 | 합성 덱의 한글·도표·폰트 대체 오차를 측정한 뒤 확정; 웹 PPTX 렌더러와 비교 |
| G2: 데스크톱 셸 | Electron + React + TypeScript | 설치 크기·메모리가 목표를 초과하면 Tauri 대안 비교 |
| G3: 구형 `.ppt` | v0.1 핵심 보장 밖으로 명시 | 변환 spike가 성공하면 로컬 변환 어댑터로 수용하고 원본 식별자 손실 기록 |
| G4: OCR | 이미지 전용 PDF는 시각 비교와 한계 표시 | 로컬 OCR의 한글·숫자 정확도를 별도 검증하면 선택 기능으로 추가 |
| G5: 라이선스 | Apache-2.0 잠정 제안 | 배포 의존성·변환기 재배포 조건과 프로젝트 목적 검토 후 확정 |

## 3. 제품 위치와 기존 도구

[pptxdiff](https://github.com/sugatoray/pptxdiff)는 PPTX 구조 비교와 슬라이드 재배치 대응을 문서화하고 있다.
[PPTX Version Control](https://github.com/ttomohisa/htmlapps-pptx-version-control)은 PPTX 이력과 시각 비교 기능을 제공한다고 설명한다.
[Draftable 공식 API](https://api.draftable.com/)는 PDF·Word·PowerPoint·Excel 비교를 제공한다. 이 계획은 기존 제품에 기능이 없다고 단정하지 않는다.

검증할 차별화 가설은 **이미 흩어진 혼합 형식의 여러 버전을 통합하고, 불확실성과 원문 근거를 보존한 계보를 사람과 AI에게 동일하게 제공하는 경험**이다.
기존 오픈소스의 파싱·정렬 코드를 재사용할지는 라이선스와 정확도를 측정한 후 결정한다. 경쟁 도구의 정확도는 아직 직접 검증하지 않았다.
구현 근거는 공개 포맷 문서와 독립 합성 fixture로 남긴다. 상용 제품의 코드·비공개 API·자산을 복제하지 않고 자체 UI와 데이터 모델을 만든다.

## 4. v0.1과 후속 범위

### v0.1 필수

- 여러 `.pptx`·`.pdf`의 일괄 입력, 버전 순서 편집, 동일 버전 bundle, 중복 파일 감지.
- PPTX 구조 추출과 로컬 미리보기 생성, PDF 텍스트·좌표·미리보기 추출.
- 슬라이드/페이지 대응, 추가·삭제·순서 이동, 텍스트·숫자 수정, 이미지·레이아웃 변화 표시.
- 전체 버전 타임라인, 인접 비교, 임의 두 버전 비교, 개체별 전체 계보, 중간에 생겼다가 사라진 항목 조회.
- 대응 후보와 신뢰도 이유 표시, 사람이 연결·연결 해제·분할/병합 관계를 수정하는 기능.
- 각 버전의 페이지·요소별 정규화된 원문과 변경 이력을 JSON·JSONL·Markdown으로 내보내기, 스키마 문서, 같은 결과를 읽는 CLI와 읽기 전용 MCP 서버.
- 원문 페이지·좌표·텍스트 인용을 포함하는 증거 링크, 불변 report snapshot, 다시 계산해도 과거 결과 재현.
- 정보 부재·인식 실패·형식 차이·실제 삭제의 구분, 취소·재시도·부분 실패 복구.

### 후속

- 이미지 전용 PDF의 로컬 OCR과 OCR 근거 표시, 표·차트 내부 값 추출 고도화.
- 자동 분할/병합 판정, 지식 기반 개체 추적, 변경 이유에 대한 선택적 AI 설명.
- PDF 비교 보고서, 주석·검토 상태, 폴더 감시, 협업 공유, 다른 오피스 형식.
- PowerPoint Add-in, 원본 편집·병합, 클라우드 동기화는 초기 범위에 포함하지 않는다.
- 노트·애니메이션 등 PPTX 전용 기능의 정밀 diff는 후속이지만, v0.1도 가용성은 기록하여 오판을 막는다.

## 5. 화면과 사용 흐름

1. **프로젝트 만들기:** 파일을 끌어놓고 버전 카드의 순서를 확정한다. 파일명·수정일은 정렬 제안에만 쓴다.
2. **입력 확인:** 각 카드에 PPTX/PDF, 페이지 수, bundle 여부, 변환 상태, 읽을 수 없는 정보가 표시된다.
3. **분석:** 추출·렌더링·대응·변경 계산의 진행률과 실패한 파일을 보여준다. 성공한 파일은 보존한다.
4. **전체 이력:** 가로축 버전, 세로축 슬라이드 계보. 추가·삭제·수정·이동·미확정 연결을 구별한다.
5. **비교:** 좌우 원문과 변경 목록, 오버레이/깜빡임, 텍스트 전후값을 제공한다. 변경 클릭으로 근거 위치로 이동한다.
6. **계보:** 한 슬라이드나 개체가 어느 버전에서 바뀌었는지 표시한다. 분할/병합은 여러 연결로 표현한다.
7. **대응 수정:** 후보 두 항목을 연결하거나 해제하고 이유를 남긴다. 수정은 새 결정 revision과 새 report를 만든다.
8. **AI/내보내기:** 현재 report ID, 가용 정보, JSON/Markdown 저장, MCP 실행·연결 예시를 제공한다.

선택한 report snapshot을 화면에 항상 표시한다. “최신”은 이동하는 별칭이며 공유·인용 링크는 고정 ID를 사용한다.
색만으로 상태를 전달하지 않고 아이콘·문자 라벨을 함께 쓴다. 삭제 전후의 빈 페이지는 “원문 없음”과 “관측 불가”를 구별한다.

## 6. 혼합 형식의 공통 표현과 비교 계약

PPTX는 슬라이드·도형·표·노트 등 별도 part를 가진 구조형 문서이며, package 내부 식별자는 문서 간 동일성을 보장하지 않는다.
구조 해석은 [Microsoft PresentationML 문서](https://learn.microsoft.com/en-us/office/open-xml/presentation/structure-of-a-presentationml-document)와 [ECMA-376](https://ecma-international.org/publications-and-standards/standards/ecma-376/)을 기준으로 한다.

두 입력을 `PageObservation + ElementObservation`으로 정규화하되, 원본별 capability와 provenance를 지우지 않는다.

| 관측 항목 | PPTX만 있음 | 텍스트 PDF만 있음 | 이미지 PDF만 있음 |
| --- | --- | --- | --- |
| 페이지/보이는 배치 | 로컬 렌더 결과 + 원본 구조 | PDF 렌더 결과 | PDF 렌더 결과 |
| 텍스트·숫자 | 원본 run·문단·도형에서 추출 | 텍스트 레이어에서 추출; 읽기 순서 추정 | v0.1은 unavailable; OCR 도입 시 inferred |
| 이미지·도형 | 객체·미디어 hash·좌표 | 렌더 영역·추출 객체; 원래 도형 구분은 제한 | 시각 영역 비교 |
| 표·차트 | 구조 추출 지원 범위를 명시 | 셀/데이터 의미는 대체로 unknown | unknown |
| 발표자 노트·애니메이션 | available 또는 unsupported | unavailable; 삭제 판정 불가 | unavailable; 삭제 판정 불가 |
| 숨김 슬라이드 | 원본의 존재·숨김 상태 기록 | 내보내기에서 빠졌을 수 있음 | 내보내기에서 빠졌을 수 있음 |

- capability 상태는 `available / unavailable / unsupported / extraction_failed`로, 관측 결과의 불확실성과 별도 저장한다.
- 양쪽에서 비교 가능한 속성만 사실 delta 후보로 계산한다. 한쪽 속성이 없으면 `coverage_gap`이며 삭제가 아니다.
- PDF로만 관측되는 시각적 변경은 `visual_region_changed`로 표현한다. “차트 매출값 수정” 같은 의미는 추정으로 분리한다.
- 숨김 슬라이드가 PDF에서 안 보이면 `not_observed_in_export`로 표시한다. 삭제는 비교 범위가 동등할 때만 확정 후보로 낸다.
- bundle의 PPTX 구조와 PDF의 보이는 결과가 다르면 `bundle_inconsistent`로 남긴다. PDF가 같은 버전이라고 자동 확정하지 않는다.
- 같은 버전 bundle은 별도의 page mapping을 가진다. 숨김 슬라이드·페이지 누락 때문에 페이지 번호를 그대로 맞추지 않는다.
- PDF-only 입력은 원래 PPTX를 역생성할 필요가 없다. 공통 관측 표현으로 바로 비교한다.

## 7. 대응·계보 알고리즘

1. 입력 byte hash, 형식, 페이지 크기, 원문 식별자, 렌더·추출기 버전을 기록한다.
2. 텍스트 정규화 값과 원문을 함께 보관한다. 숫자·소수점·부호·통화·단위는 정규화로 지우지 않는다.
3. 제목·본문 유사도, 이미지 hash, 저해상도 시각 특징, 상대 배치로 후보를 만든다.
4. 전체 페이지 후보를 전역 매칭한다. 순서는 약한 단서로만 써서 재배치를 허용한다.
5. 1:1 연결에 점수와 기여 특징을 붙인다. 점수는 검증 전에는 확률이라고 부르지 않는다.
6. 복제·동일 템플릿·분할/병합처럼 애매한 경우 후보 집합과 `needs_review`를 남긴다.
7. 인접 버전 연결을 계보 그래프로 만들고, 앞뒤 버전의 강한 근거로 단절을 보조하되 관측 공백은 유지한다.
8. 대응한 페이지 내부의 텍스트·이미지·배치를 비교한다. PPTX↔PDF에서는 공통 관측 속성만 사용한다.
9. 사용자 수정은 추출 원본을 변경하지 않고 별도 mapping decision으로 저장한다. 재계산에도 우선 적용한다.

`moved`와 `modified`는 동시에 성립할 수 있다. 페이지 자체의 순서 이동과 페이지 내부 개체 위치 이동은 다른 이벤트다.
새 복제본을 기존 항목의 이동으로 오인하지 않도록 `copied_from`과 `same_lineage`를 분리한다.
v0.1의 자동 분할/병합은 제안 수준이며, 사람이 관계를 확정하면 그래프·UI·MCP 모두 동일하게 반영한다.
사라진 뒤 다시 나타난 항목은 증거가 충분하면 `reappeared`로 연결하고, 중간 형식의 정보 부재를 가상의 삭제/추가로 채우지 않는다.
최초↔최종의 순변경과 인접 이벤트를 누적한 전체 이력을 함께 제공한다. 두 결과는 의미가 달라 합계가 같다고 가정하지 않는다.

## 8. 데이터 모델과 불변성

| 엔터티 | 핵심 필드·역할 |
| --- | --- |
| `Project` | `project_id`, 제목, 명시적으로 가져온 asset 목록 |
| `Asset` | `asset_id=sha256(bytes)`, 형식, 원본 byte 수; 경로 대신 불투명 ID로 외부 노출 |
| `Revision` | `revision_id`, asset 집합과 bundle 설정; 생성 후 불변 |
| `TimelineRevision` | `timeline_revision_id`, 순서가 확정된 revision occurrence 목록; 재정렬 시 새 ID |
| `ObservationSet` | asset hash, 추출기·렌더러·폰트 환경·설정 hash, capability, 관측 결과 |
| `Page/ElementObservation` | `observation_id`, 원문 page/shape 참조, text, bbox, visual hash, provenance |
| `EntityLineage` | 프로젝트에서 발급한 안정 `entity_id`, 관측 연결, 복제·분할·병합 관계 |
| `MappingDecision` | `mapping_revision_id`, 사용자 확정/해제 연결, 이유, supersedes 관계 |
| `Change` | 이벤트 ID, from/to revision, entity ID, 유형, 전후값, 증거, 신뢰도·가용성 |
| `ReportSnapshot` | `report_id`, 입력·순서·관측·결정·엔진·스키마 hash, 생성시각, coverage |
| `AnalysisRun` | `analysis_run_id`, 시작·종료·실패·캐시 사용 여부, 연결한 report ID; 실행 메타데이터 |

`entity_id`는 확정한 계보에 대해 유지한다. 엔진 변경으로 계보를 재구성하면 기존 ID를 몰래 재사용하지 않고 alias/supersedes를 제공한다.
같은 파일이 타임라인에 두 번 등장할 수 있으므로 `revision_occurrence_id`는 파일 hash와 별도로 둔다.
`change_id`는 report·구간·대상·속성에서 결정적으로 생성한다. 같은 report를 다시 읽으면 ID·정렬이 바뀌지 않는다.
`report_id`는 입력·타임라인·관측·mapping·엔진·스키마의 canonical hash로 결정한다. 같은 조건의 재실행은 같은 report를 재사용하고, 실행마다 새 `analysis_run_id`를 남긴다. 입력·순서·mapping·엔진 등이 바뀌면 새 report가 된다. 실행 시각·소요 시간은 canonical 결과 hash에서 제외한다.
증거 좌표는 회전 보정 후 좌상단 기준 `[0,1]`의 `bbox=[x, y, width, height]`로 표준화한다. `width/height`는 음수가 아니고 `x+width`, `y+height`는 1 이하여야 한다. 원래 좌표계·페이지 크기·변환 행렬도 보존한다.
`observed`는 추출된 값, `inferred`는 대응/해석의 추정, `human_confirmed`는 사람이 확정한 판단이다. 셋을 하나의 신뢰 라벨로 합치지 않는다.

작은 변경 예시(실제 데이터가 아닌 스키마 설명용 합성 값):

```json
{
  "schema_version": "0.1.0",
  "report_id": "rpt_demo_004",
  "change_id": "chg_demo_017",
  "entity_id": "ent_revenue_title",
  "from_revision": "rev_02_pdf",
  "to_revision": "rev_03_pptx",
  "kind": "text_modified",
  "before": {"text": "예상 매출 120억", "availability": "available"},
  "after": {"text": "예상 매출 110억", "availability": "available"},
  "evidence": [
    {"revision_id": "rev_02_pdf", "asset_id": "sha256:demo02", "page": 5,
     "bbox": [0.1, 0.2, 0.5, 0.1], "quote": "예상 매출 120억", "method": "pdf_text"},
    {"revision_id": "rev_03_pptx", "asset_id": "sha256:demo03", "page": 7,
     "bbox": [0.1, 0.2, 0.5, 0.1], "quote": "예상 매출 110억", "method": "ooxml_text"}
  ],
  "lineage": {"status": "inferred", "score": 0.94, "reasons": ["text", "layout"]},
  "coverage_gaps": [],
  "evidence_uri": "docver://projects/prj_demo/reports/rpt_demo_004/changes/chg_demo_017"
}
```

## 9. AI가 읽는 결과물과 MCP 계약

### 내보내기

- `manifest.json`: schema/report/입력 hash/버전 순서/coverage/엔진 정보를 담는 시작점.
- `changes.jsonl`: 한 줄에 한 이벤트. `schema_version`, `report_id`, `change_id`, `entity_id`, 근거를 포함한다.
- `lineages.json`·`revisions.json`: 계보와 버전 메타데이터. 임시 중간 이벤트도 누락하지 않는다.
- `pages.jsonl`·`elements.jsonl`: 버전별 정규화된 원문·읽기 순서·좌표·추출 방법·가용성. 원문 인용과 정규화 값은 구분한다.
- `content/{revision_id}/page-0001.md`: 페이지별 읽기용 내용과 원문 근거. 그림/차트/스캔의 추출 제한을 표시하고 AI 해석으로 본문을 채우지 않는다.
- `history.md`: 변경 요약과 전후값, 버전·페이지 링크, 미확정 연결과 정보 공백을 읽기 좋게 표시한다.
- AI가 만든 해설은 선택적 `annotations` 파일에 모델·입력 report ID와 함께 저장한다. 관측된 delta 테이블을 덮어쓰지 않는다.
- JSON Schema와 예시를 버전 관리한다. 같은 report의 UI·CLI·MCP·내보내기는 공통 query service를 사용한다.

### v0.1 MCP 도구(읽기 전용)

| 도구 | 입력·출력 요지 |
| --- | --- |
| `list_projects` / `list_reports` | 공개 대상으로 등록한 프로젝트/고정 report 목록, `cursor`, `limit` |
| `get_report` / `list_revisions` | `project_id`, `report_id`; coverage·입력 순서·스키마·가용 기능 |
| `list_pages` / `get_page` | report, revision, page ID; 페이지 목록/정규화된 원문·요소 요약·근거, cursor |
| `get_element` | report, observation ID; 원문·정규화 값·bbox·추출 방법·그림/차트의 가용성 |
| `list_changes` | report, `from/to`, `mode=adjacent|range_net|history`, kind/entity/text 필터, cursor |
| `get_entity_history` | report, entity; 전체 생애와 분할/병합·관측 공백, 페이지별 증거 |
| `get_evidence` | report, change/observation ID; 인용·페이지·좌표와 선택적 제한 크기 이미지 |

모든 도구는 명시적 `inputSchema`·`outputSchema`, `readOnlyHint: true`를 제공한다. 이 힌트에 의존하지 않고 서버 저장소 자체를 읽기 전용으로 연다.
결과는 `structuredContent`와 호환용 JSON text를 제공한다. 계약 근거는 [MCP Tools 명세](https://modelcontextprotocol.io/specification/2025-11-25/server/tools)다.
`list_changes` 같은 업무 데이터 페이지네이션은 앱의 도구 입력/출력 계약이다. MCP의 `tools/list` 페이지네이션과 혼동하지 않는다.
기본 `limit=50`, 최대 200, `max_output_tokens=4000`을 제안한다. 서버는 추정 token 수와 byte 상한을 적용하고 `truncated`, `next_cursor`, `omitted_fields`를 반환한다.
모델별 tokenizer 차이를 명시하고 큰 인용/이미지는 기본 제외한다. 항목이 한도를 넘으면 이유와 더 작은 증거 조회 링크를 준다.
cursor에는 report ID·query hash·정렬 위치를 묶는다. 다른 report에 재사용하면 `CURSOR_REPORT_MISMATCH`로 실패한다.
첫 조회에서 최신 별칭을 고정 report ID로 해석하고 이후 호출은 그 ID를 사용한다. 재계산 중에도 이전 report 조회를 보장한다.

### MCP resources와 경계

- `docver://projects/{project_id}/reports/{report_id}/manifest`
- `docver://projects/{project_id}/reports/{report_id}/revisions/{revision_id}/pages/{page_id}`
- `docver://projects/{project_id}/reports/{report_id}/changes/{change_id}`
- `docver://projects/{project_id}/reports/{report_id}/entities/{entity_id}`
- `docver://projects/{project_id}/reports/{report_id}/evidence/{observation_id}`
- resource URI는 등록된 내부 ID만 해석한다. `file://`, 임의 절대경로, `../`, URL fetch를 받지 않는다.
- resources 목록·읽기·template은 [MCP Resources 명세](https://modelcontextprotocol.io/specification/2025-11-25/server/resources)를 따른다. 큰 전체 이력은 필터 도구로 읽는다.
- 기본 전송은 로컬 stdio다. 시작 인수에서 공개 프로젝트를 고정하고, 해당 scope 안의 읽기에는 매번 승인 절차를 추가하지 않는다.
- 파일 import·mapping 수정·재분석·원본 쓰기·셸 실행·모델 호출 도구는 노출하지 않는다. 앱/CLI의 쓰기 경로와 분리한다.
- 문서 본문의 지시문은 인용 데이터다. 서버 동작 명령으로 실행하지 않으며, 모델 추론을 사실 이벤트로 저장하는 API도 제공하지 않는다.
- 예시: `get_entity_history({"project_id":"prj_demo","report_id":"rpt_demo_004","entity_id":"ent_revenue_title","max_output_tokens":2000})`.
- 응답에는 `report_id`, `schema_version`, `items`, `next_cursor`, `coverage_gaps`, 근거 resource URI를 공통 포함한다.
- 원문 전체를 기본 반환하지 않는다. 페이지 목록→선택 페이지→필요 요소/증거 순서로 읽으며 `get_page`도 요소 cursor와 출력 상한을 지원한다.

## 10. 잠정 기술 스택과 ADR

**ADR-001: 관측·계보·조회 엔진을 UI와 독립된 TypeScript package로 만든다.**
선택 요인은 UI/CLI/MCP 결과 일치, 초기 개발 속도, JSON Schema 공유다. SQLite와 content-addressed 파일 저장을 사용한다.
대안은 Python 엔진+별도 UI, Rust 중심 엔진이다. 각각 문서 처리 생태계와 성능 이점이 있지만 초기 다언어 계약 부담이 생긴다.
후속 성능 측정에서 병목이 확인된 모듈만 worker/native 모듈로 교체한다. UI 프로세스에서 큰 문서 분석을 돌리지 않는다.

**ADR-002: 구조 비교와 렌더 비교를 함께 유지한다.**
PPTX ZIP/XML 어댑터는 외부 entity·외부 관계 fetch를 하지 않고 크기·중첩 한도를 둔다. PDF.js는 텍스트·viewport·미리보기에 사용한다.
[PDF.js PDFPageProxy](https://mozilla.github.io/pdf.js/api/draft/module-pdfjsLib-PDFPageProxy.html)는 텍스트 추출과 viewport·렌더 API를 제공한다.
LibreOffice 변환기는 독립 작업 폴더·새 임시 사용자 프로필·시간 제한으로 실행한다. [공식 CLI 문서](https://help.libreoffice.org/latest/en-US/text/shared/guide/start_parameters.html)의 headless/convert-to 인터페이스를 사용한다.
대안은 웹 PPTX 렌더러 또는 플랫폼별 PowerPoint 자동화다. 후자는 설치·플랫폼 의존성이 있어 기본 경로로 삼지 않는다.

**렌더링 spike의 필수 산출물:** 한글, 혼합 폰트, 도형, 투명도, 표, 차트, 회전 텍스트, 숨김 슬라이드 각 3개 이상인 합성 덱·원본 이미지·오차 보고서.
원본 렌더 기준은 새 합성 덱에서 직접 생성한 참조 PDF로 고정한다. 구조 추출 결과와 픽셀 오차를 분리 평가한다.
참조 PDF의 작성 도구·버전·폰트 환경을 기록하고, 평가 중인 동일 변환기의 출력만을 정답으로 삼아 렌더 정확도를 자가 증명하지 않는다. 독립 참조를 확보하지 못한 경우 구조 검증과 변환 재현성만 보고하고 시각적 충실도는 미검증으로 남긴다.
변환기가 없거나 실패해도 PDF 입력은 작동해야 한다. PPTX 구조는 보존하며 미리보기 실패를 명시하고 재시도할 수 있게 한다.
G1 종료 시 변환기 설치/배포 방식, 폰트 안내, 지원 기능 표, 선택한 버전과 이유를 `docs/adr/002-rendering.md`에 기록한다.

## 11. 제안 디렉터리 구조

아래는 앞으로 만들 구조이며, 현재 존재하는 소스 파일을 가리키는 것이 아니다.

```text
apps/desktop/                 # Electron·React UI와 파일 입력
apps/cli/                     # import/analyze/export/query 명령
apps/mcp/                     # stdio 읽기 전용 서버
packages/schema/              # JSON Schema·타입·마이그레이션
packages/ingest/              # PPTX·PDF 어댑터와 capability
packages/render/              # 변환 worker·좌표계·미리보기
packages/matching/            # 페이지/개체 후보와 계보
packages/diff/                # 관측 delta와 coverage gap
packages/query/               # UI·CLI·MCP 공통 조회
packages/storage/             # SQLite·불변 snapshot·asset store
tests/fixtures/generated/     # 새 합성 입력과 manifest
tests/ground-truth/           # 사람이 작성한 정답 계보·변경
tests/integration/            # mixed-format·snapshot·MCP
docs/adr/                     # 근거 있는 결정 기록
docs/schemas/                 # 스키마·예시·MCP 계약
```

## 12. 단계별 실행 계획과 합격 기준

| 단계 | 산출물·제안 담당 경계 | 완료 조건 |
| --- | --- | --- |
| M0: 계약·fixture | schema, ground-truth, 6개 혼합 타임라인 | 양방향 형식 전이와 정보 공백을 schema로 표현; 정답표 검토 |
| M1: 파싱·렌더 spike | ingest/render, G1·G3 ADR | PPTX-only/PDF-only 독립 추출, bundle 정렬, 실패·한계 기록; 렌더 오차 측정 |
| M2: 매칭·변경 | matching/diff, CLI 분석 | 삽입·삭제·이동·숫자 수정, 복제·분할 후보, 정보 부재 오판 방지 fixture 통과 |
| M3: 저장·공통 조회 | storage/query, 불변 report | 같은 조건은 같은 report ID·결과 hash, 과거 report 재조회, 재정렬·mapping 수정 시 새 snapshot; 실행 이력은 별도 run ID |
| M4: AI 인터페이스 | export/CLI/MCP, schema docs | JSON/Markdown과 MCP의 ID·이벤트 일치, pagination·scope·budget 테스트 통과 |
| M5: UI | desktop 타임라인·비교·대응 수정 | 5버전 작업을 UI에서 완료하고 동일 report를 AI가 조회; 원문 위치 연결 검증 |
| M6: v0.1 배포 | 설치본·합성 데모·지원 표 | 새 macOS 환경 설치·분석·MCP 연결 재현, 원본 byte hash 불변, 알려진 한계 공개 |

병렬 구현 시 schema/query 계약을 먼저 고정한다. 이후 ingest/render, matching/diff, desktop, MCP/export를 분리할 수 있다.
독립 lane은 자기 모듈과 테스트를 소유하고 공통 schema 변경은 함께 조정한다. 다른 프로젝트의 소스나 설정에는 의존하지 않는다.

## 13. 합성 fixture와 검증

fixture는 이 신규 프로젝트의 임시 작업 디렉터리에서 새로 생성한다. 기존 개인 문서·Local Media 자료·실제 고객 파일은 사용하지 않는다.
각 타임라인에 source seed, 생성기 버전, 파일 hash, 의도한 delta, 허용한 정보 손실, 정답 mapping을 담은 manifest를 둔다.

| 검증 사례 | 필수 합격 기준 |
| --- | --- |
| `PPTX → PDF → PPTX`, 역방향 | 두 방향 모두 같은 슬라이드 계보 연결; 노트 부재를 삭제로 생성하지 않음 |
| 5개 버전, 중간 삽입·삭제·이동 | 잠시 존재한 슬라이드와 순변경을 모두 조회; 이동+수정 동시 표시 |
| 숫자 `100 → 120 → 110`, 부호·소수점·단위 | 원문 전후값 보존, 변경 구간·page·bbox 일치 |
| 동일 슬라이드 복제·템플릿 반복 | 복제와 이동을 구별하거나 needs_review; 확신한 잘못된 연결 방지 |
| 1장→2장 분할, 2장→1장 병합 | 자동 후보 표시 후 사용자 연결 수정, 수정 결과가 UI·export·MCP에 일치 |
| 숨김 슬라이드·노트·애니메이션의 PDF 부재 | coverage gap을 생성하고 가상의 삭제/복원 이벤트를 만들지 않음 |
| bundle의 페이지 누락·잘못된 PDF | 불일치와 수동 mapping 표시; 조용히 번호로 연결하지 않음 |
| 글자→윤곽선/이미지 PDF, 회전·크롭 | 한계를 노출하고 시각 비교 제공; OCR 없는 숫자를 아는 척하지 않음 |
| 재계산·사용자 수정·스키마 변경 | 같은 조건 재계산은 같은 report ID; 조건·mapping·스키마 변경은 새 ID; 옛 증거 링크 유효; migration 또는 명시적 버전 오류 |
| MCP cursor/filter/budget | 중복·누락 없이 끝까지 조회; report가 바뀌면 cursor 거절; truncation 명시 |
| MCP 범위·읽기 전용 | 임의 경로/다른 프로젝트/셸 요청 거절; 조회 전후 저장소 hash 불변 |
| AI 질의 재현 | “수익 수치 전체 이력”을 모델 없이 MCP 호출로 정답 목록·근거까지 반환 |
| AI 원문 읽기 | PDF-only·PPTX-only 버전 각각에서 페이지 목록→원문→요소 근거를 조회; 큰 페이지는 나눠 읽고 이미지/차트 한계를 반환 |
| 손상 ZIP/PDF·암호 파일·변환 timeout | 파일별 명시 오류·재시도; 정상 파일 결과와 원본 보존 |

아래 수치는 **검증 전 제안 목표**다. M1의 기준 장비·덱 크기를 기록하고 무리한 목표는 이유와 함께 ADR로 조정한다.

- 정답이 유일한 30개 합성 타임라인/600페이지에서 페이지 대응 precision ≥98%, recall ≥95%; 형식 전이별 따로 보고한다.
- 텍스트 레이어가 있는 합성 숫자 변경 precision ≥99%, recall ≥98%; OCR/차트 해석과 섞어 평균내지 않는다.
- 애매한 fixture의 불확실성 표시율 100%, unavailable 속성의 잘못된 삭제 이벤트 0건을 회귀 조건으로 둔다.
- M2급 16GB 기준 5버전×50페이지에서 cold 분석 180초 이내를 탐색 목표로 삼고 변환·추출·매칭 시간을 분리 측정한다.
- 이미 분석된 report의 변경 첫 목록 p95 300ms, 근거 페이지 이동 p95 500ms를 목표로 한다. 렌더 캐시 조건을 기록한다.
- 같은 입력·엔진·설정·mapping으로 재계산한 canonical 결과 hash가 일치하고 MCP의 순회 조회가 export와 100% 일치해야 한다.

## 14. 위험과 대응

| 위험 | 대응·결정 지점 |
| --- | --- |
| 렌더러 차이를 사용자 편집으로 오인 | 구조·시각 delta 분리, 렌더 provenance, 공통 렌더 비교와 원본 PDF 차이를 별도 표시 |
| PDF에서 원본 의미를 복원하기 어려움 | capability 기반 축소, unknown 유지, 시각 근거, 수동 연결; 의미 생성으로 메우지 않음 |
| 계보 오연결이 전체 이력을 오염 | 후보·이유·confidence, 복제/분할 명시, 사용자 수정과 snapshot 고정 |
| 큰 문서·여러 버전에서 비용 폭증 | hash cache, 저해상도 후보 축소, worker queue·취소, 상세 렌더 지연 생성 |
| AI가 한 요약을 변경 사실로 오해 | 관측/추정/사람 확정 분리, coverage 동반, 모든 요약에 report·change 근거 연결 |
| 스키마·엔진 변경으로 외부 도구 파손 | versioned schema, 고정 report ID, 명시적 migration, 호환성 fixture |
| 기존 도구와 차별화 약함 | 혼합 형식 5버전 작업을 실제 사용자 본인의 업무 흐름에서 검증하고 기능 추가 전 개선 효과 측정 |

## 15. 다음 세션 시작 프롬프트

> 이 폴더의 PLAN.md를 기준으로 문서 버전 추적기를 구현하라. 먼저 M0의 schema·합성 fixture·정답표를 만들고, M1의 PPTX/PDF 추출과 렌더링 spike 결과로 G1/G3를 결정하라. PPTX-only/PDF-only와 양방향 형식 전이를 반드시 유지하고, 정보 부재를 삭제로 해석하지 말라. v0.1에는 JSON/JSONL/Markdown export와 읽기 전용 MCP를 UI와 동일한 공통 query service 위에 구현하라. 제안 경로는 아직 없는 파일이며 실제 신규 프로젝트 구조로 생성하라. 개인정보나 기존 다른 프로젝트 자료를 조사하지 말고 새 합성 fixture만 사용하라. 단계별 완료 조건과 검증 결과를 기록하고, 계획의 변경은 이유와 ADR로 남겨라.

## 16. 공개 근거와 확인 상태

자료 조회일: 2026-10-18. 위의 기능 설명은 각 upstream의 공개 문서에 근거하며, 실행 정확도나 시장 수요를 검증했다는 뜻은 아니다.
MCP 구현 시 negotiated protocol version과 사용 SDK 버전을 고정한다. 여기서 인용한 2025-11-25 명세를 무조건 최신이라고 가정하지 않는다.
이 문서는 계획 작성자의 설계안이며 외부 독립 검토나 구현 검증을 받았다고 주장하지 않는다.

