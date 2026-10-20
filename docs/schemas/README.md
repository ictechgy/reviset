# 스키마와 AI 조회 계약 · 0.4.0

모델 원본은 `packages/schema/index.ts`, 도구 입력·출력은 `packages/query/index.ts`다. `npm run schemas`로 이 폴더의 draft-2020-12 JSON Schema를 재생성한다. `report.schema.json`은 전체 report, `manifest.schema.json`은 사용자 입력, `fixture_manifest.schema.json`은 합성 fixture의 seed/hash/정답 metadata다.

## 식별과 가용성

- `asset_id=sha256:<bytes>`; `revision_id`는 asset 집합, `revision_occurrence_id`는 특정 타임라인 등장이다.
- `page_id`/`observation_id`는 occurrence 안의 관측이다. 문서 간 ID 일치로 대응을 단정하지 않는다.
- `report_id`는 canonical 결과 snapshot, `analysis_run_id`는 실행이다. report 스키마·환경·순서·mapping이 바뀌면 새 snapshot이다.
- `available / unavailable / unsupported / extraction_failed`를 구분한다. 원문 사실은 `observed`, 대응은 `inferred` 또는 `human_confirmed`, 경쟁 후보는 `needs_review`다.
- bbox는 회전 보정 후 좌상단 `[0,1]` 좌표이며 `[x,y,width,height]`다. 원래 좌표계와 변환 행렬도 보존한다. 변경의 숫자 근거는 가능한 경우 해당 텍스트 요소의 인용과 bbox를 가리킨다.

## MCP와 공통 query

| 도구 | 추가 입력 | 결과 항목 |
| --- | --- | --- |
| `list_projects` | 없음 | 시작 시 허용한 프로젝트만 |
| `list_reports` | project_id | 고정 report 목록 |
| `get_report` | project_id, report_id | 스키마·엔진·환경·개수 |
| `list_revisions` | 공통 scope | 입력·상태·occurrence·페이지 수 |
| `list_pages` | revision_id | 원문 발췌·가용성·요소 수 |
| `get_page` | revision_id, page_id | 순서대로 분할된 원문 요소 |
| `get_page_content` | revision_id, page_id, section, text_offset/text_length | comparison/source/visible/unresolved/suppressed/ocr/ocr_unresolved/notes의 정확한 청크·필드 상태·SHA |
| `search_content` | text, revision_id/format/section, case_sensitive | 페이지별 첫 literal hit·원문 offset·판독 상태·가능한 경우 요소 출처 |
| `get_element` | observation_id | 원문·bbox·추출법; text_offset/text_length, span_offset/span_limit, appearance_evidence_offset/appearance_evidence_limit |
| `list_changes` | mode, from/to, kind, entity_id, change_id, text | 관측 delta와 근거 |
| `get_change` | change_id, from/to, component/component_index, text_offset/text_length | 변경 요약·전체 전후값·개별 근거·한계·계보 이유·topology |
| `list_coverage_gaps` | revision_id/page_id/feature/gap_index, component, text_offset/text_length | report/버전/페이지의 전체 판독 한계와 개별 긴 reason/feature |
| `list_bundle_decisions` | revision_id/source_page_id/decision_id, reason_offset/reason_length | 같은 버전의 제공 PDF 연결 이유·대체된 쌍·이력 |
| `list_page_relations` | relation_id/page_id, from/to_occurrence, reachable_from/to_page_id, reason_offset/reason_length | 실제 방향 연결과 이유의 분할 원문 |
| `get_entity_history` | entity_id | 각 버전의 페이지 원문·변경 ID |
| `get_evidence` | change_id 또는 observation_id 하나 | 페이지·인용·좌표; text_offset/text_length |

`get_report` 이하의 공통 scope는 project_id와 report_id다. report_id=`latest`는 첫 조회에서 고정 ID로 해석한다. 이후 해당 ID를 사용한다. revision_id 입력에는 occurrence ID를 쓴다. 새 내용 조회 도구와 list_bundle_decisions는 중복 원본 revision alias를 AMBIGUOUS_REVISION으로 거절한다. 기존 도구 일부의 역사적 first-occurrence alias 동작은 호환성을 위해 유지하므로 라벨이나 중복 원본 ID로 버전을 추측하지 않는다. MCP API0.4.0-mcp.1의 실용 흐름·2개 prompt는 [MCP 조회 가이드](../MCP.md)를 참고한다.

모든 도구에 명시적 inputSchema/outputSchema, readOnlyHint가 있다. SDK의 기본 protocol은 2025-11-25이고 SDK가 이전 버전과 협상한다. 기준은 [MCP 도구 명세](https://modelcontextprotocol.io/specification/2025-11-25/server/tools)와 [resources 명세](https://modelcontextprotocol.io/specification/2025-11-25/server/resources)다.

리소스는 다음 template만 지원한다. 목록에는 허용 프로젝트의 manifest를 제공한다.

```text
docver://projects/{project_id}/reports/{report_id}/manifest
docver://projects/{project_id}/reports/{report_id}/revisions/{revision_id}/pages/{page_id}
docver://projects/{project_id}/reports/{report_id}/revisions/{revision_id}/pages/{page_id}/content
docver://projects/{project_id}/reports/{report_id}/revisions/{revision_id}/pages/{page_id}/notes
docver://projects/{project_id}/reports/{report_id}/changes/{change_id}
docver://projects/{project_id}/reports/{report_id}/changes/{change_id}/detail
docver://projects/{project_id}/reports/{report_id}/coverage-gaps
docver://projects/{project_id}/reports/{report_id}/pages/{page_id}/relations
docver://projects/{project_id}/reports/{report_id}/entities/{entity_id}
docver://projects/{project_id}/reports/{report_id}/evidence/{observation_id}
```

파일 경로·URL fetch·셸·본문 지시 실행은 받지 않는다. resource 응답도 bounded query 결과이며, 후속 cursor는 해당 도구로 전달한다. 원본 이미지 바이너리 제공은 아직 구현하지 않았다.

## 페이지네이션과 예산

공통 입력: 기본 limit=50, 최대 200. max_output_tokens 기본 4000, 입력 범위 256~8000이다. 현재 tokenizer 대신 UTF-8 byte 수를 보수적 token 추정 상한으로 사용한다. 이는 모델별 tokenizer와 다르다.

query 응답의 JSON byte 수는 해당 예산을 넘지 않는다. MCP는 structuredContent와 호환용 JSON text의 중복 비용까지 합쳐 예산에 맞춘다. 너무 작은 예산에는 `OUTPUT_BUDGET_TOO_SMALL`을 반환하므로 실용적으로 2000~8000을 권장한다. JSON-RPC transport envelope의 ID·헤더는 이 업무 payload 예산 밖이다.

응답은 `schema_version`, 고정 `report_id`, `items`, `next_cursor`, `coverage_gaps`, `truncated`, `omitted_fields`, `token_estimation`을 포함한다. 새 내용 도구에는 선택적 `query_context`도 있다. 공통 envelope의 coverage gap은 예산에 따라 일부만 반환하며 omitted_fields에 표시한다. 전체 한계는 list_coverage_gaps 또는 export의 manifest/report로 확인한다.

cursor는 report ID·쿼리 hash·안정 정렬 위치에 묶는다. cursor를 사용해도 필터를 똑같이 전달해야 한다. limit과 출력 예산은 바꿔도 된다. 다른 report에는 `CURSOR_REPORT_MISMATCH`, 다른 필터에는 `CURSOR_QUERY_MISMATCH`를 반환한다.

기존 목록 도구에서 하나의 항목이 너무 크면 ID·resource URI·누락 필드 목록을 담은 summary를 반환하고 cursor를 진행한다. 새 내용 도구는 실제 MCP dualJSON 크기에 맞춰 텍스트 청크를 줄이며 ID-only 성공으로 대체하지 않는다. 최소 scalar도 담을 수 없으면 OUTPUT_BUDGET_TOO_SMALL이다. 원문은 다음처럼 읽는다.

1. `list_pages`로 page_id를 찾는다.
2. `get_page`의 cursor로 모든 요소 ID를 읽는다.
3. 요소 text가 생략됐으면 `get_element`를 text_length=100~500으로 호출한다.
4. `next_text_offset`을 다음 text_offset으로 사용한다(오프셋 단위는 JavaScript UTF-16 code unit). null이면 끝이다. 이모지의 surrogate pair를 중간에서 자르지 않는다. 길이 1 요청도 한 scalar를 위해 2 code unit을 반환할 수 있으며, 임의 offset이 pair 중간이면 `TEXT_OFFSET`으로 거절한다.

변경의 긴 전후값은 get_change component=before/after로, 긴 인용은 get_evidence 또는 get_change component=evidence로 읽는다. get_change의 여러 행은 component_index, list_coverage_gaps의 개별 한계는 gap_index를 고정해 text_offset으로 잇는다. 목록 cursor와 다른 text offset을 섞지 않는다. 발표자 노트는 get_page_content section=notes와 next_text_offset으로 읽는다. 생성된 summary를 완전한 원문으로 취급하지 않는다. null/unavailable·not_recorded·empty·empty_unverified를 구분한다.

## PDF 표시 상태와 표 출처

`text`는 추출 원문이다. `visible_text`·`suppressed_text`·`unresolved_text`는 별도이며 가림을 삭제 의도로 단정하지 않는다. 완전한 불투명 사각형 추정 가림은 visible-only delta에 추정 근거를 붙이고, 부분 가림·마스크·알 수 없는 클리핑·비가시 OCR 등은 단순 text delta를 보류한다. OCR 모드3 텍스트는 이전 체크포인트와 달리 검증된 화면 원문으로 사용하지 않는다. 표시 변경은 `appearance_assessment=observed|inferred`로 페이지 대응의 신뢰 상태와 구분한다. PPTX에 계산된 표시 상태가 없으면 PDF와의 appearance 이벤트를 생성하지 않는다.

`get_element`는 원문과 글자별 상태를 각각 분할 조회한다. 기본 `span_limit=0`, `appearance_evidence_limit=0`은 큰 배열을 생략하고 count와 다음 offset만 반환한다. `span_limit=1~20`과 `span_offset`으로 `visibility_spans`를, `appearance_evidence_limit=1~10`과 `appearance_evidence_offset`으로 `visibility_evidence`를 순회한다. 각각 `next_span_offset`·`next_appearance_evidence_offset`이 null이면 끝이다. offset 단위는 각 배열의 항목 인덱스다. 긴 text를 읽을 때는 span/evidence 기본값 0을 유지한다. `get_page`도 큰 표시 배열을 생략하고 count 및 요소 ID를 제공한다. 작은 출력 예산에서는 chunk 길이를 줄인다.

OOXML 표의 `ooxml_table/observed`와 PDF 격자에서 추정한 `pdf_grid_inferred/inferred`는 원래 같은 구조를 뜻하지 않는다. 현재 diff는 페이지 텍스트 단위이며 형식 사이의 셀 대응은 제공하지 않는다. 표 텍스트가 추가되면서 초기 체크포인트와 매칭 점수/report ID가 달라질 수 있다.

## Native OCR·화면 증거 확장

`Element.provenance`는 observed 또는 inferred이며 `vision_ocr`와 `vision_document_cell`은 추정이다. `ocr.confidence`는 line 단위의 모델 점수이고 확률이 아니다. 숫자의 `numeric_consensus`, 대안 충돌 `ambiguous`, 전체 대안 문자열을 보존한다. 스캔 원문의 `Page.text`를 OCR로 덮어쓰지 않으며 `ocr_text`·`ocr_unresolved_text`와 `comparison_basis=raster_ocr`를 분리한다. raw visibility의 공백은 OCR 비교가 가능해도 유지한다.

`get_page`는 OCR 대안 문자열을 생략하고 길이·점수·요소 ID를 제공한다. `get_element`에서 `ocr_alternative_index=0..2`, `ocr_alternative_offset`, `ocr_alternative_length=1..1000`으로 각각의 전체 대안을 순회한다. 응답의 `ocr_alternative.next_text_offset`이 null이면 끝이다. 일반 text/span/appearance evidence와 독립적으로 읽으며, 너무 작은 예산에는 각 chunk 길이를 줄인다. export에는 대안 전체가 있고 영구적으로 잘라 저장하지 않는다.

`Change.text_assessment=inferred`인 OCR 변경에는 원문 확인 gap을 붙인다. OCR 영역 누락이나 숫자 개수/대안의 불일치는 정확한 값 삭제로 확정하지 않는다. 확실하게 읽히고 유일하게 대응한 숫자 영역은 `text_scope=region`으로 비교할 수 있으며, 페이지 다른 부분의 공백은 남는다. 이는 원본 table cell ID의 복구나 형식 간 셀 계보 확정이 아니다.

`Page.raster`는 native PDFKit 렌더 SHA-256·크기·환경을 고정한다. 같은 native 화면이면 raw/OCR만의 차이로 텍스트 수정을 만들지 않는다. `visual_region_changed`의 근거는 `method=native_raster`, `render_sha256`이며 의미상 삭제를 뜻하지 않는다. 형식 간 렌더 차이는 렌더러/폰트 대체의 영향을 추정으로 남긴다. 관측 주석 상태와 native 픽셀이 다른 경우도 gap으로 남긴다.

화면에서 인식한 `vision_table_inferred/inferred`의 행·열·병합 범위는 macOS26+의 표 구조 관측이다. OOXML 원본 셀과 PDF 선 격자 추정과 구별한다. 일반 OCR은 macOS14+ native helper이며 앞선 "OCR 미실행" 기록을 대체한다. `Page.preview`는 파생 PPTX PDF의 hash·페이지·renderer/font 환경·경고를 고정한다.

관측 취소선은 여전히 화면에서 읽을 수 있으므로 `visible_text`에 포함하고 `text_struck_through`로 표시 변경을 표현한다. 숨김 OC paint나 글자 clipping 모드는 확정 가림으로 쓰지 않는다. 보이는 내용이 같더라도 억제된 원문층이 바뀌면 `raw_text_changed_in_suppressed_layer` 관측 공백을 기록한다.

신규 report/change와 조회 envelope는 0.4.0을 생산한다. 기존 0.1/0.2 snapshot은 읽기/내보내기에서 원래 버전을 보존하며, range 재계산은 지원되는 archived engine에만 허용한다. 새 Change enum/provenance를 해석하는 소비자는 schema_version과 schema_hash를 함께 확인한다. text_scope=region의 값은 원문 관측일 수 있지만 region_pairing_assessment=inferred는 영역 대응 자체가 추정임을 명시한다.


## 수동 페이지 분할·병합과 호환성

manifest의 `mapping_relations`는 선택적이다. 각 관계는 kind(continuation/split/merge), 인접한 from_occurrence/to_occurrence, from_page_ids/to_page_ids, reason을 받는다. 주 문서 페이지로 1:1/1:N/N:1만 허용하며 한쪽 최대32페이지, 새 관계의 이유는 공백만으로 구성할 수 없고 최대2000UTF16단위다. 엔진이 페이지 순서와 결정적 relation_id를 정규화한다. 기존 mapping_decisions는 계속 받으며 과거의 긴 이유도 보존한다.

page_split/page_merged 이벤트는 구성 변경이며 문구의 삭제·수정을 확정하지 않는다. range_net의 page_lineage_changed는 방향 경로를 가진 계보 묶음이다. topology.semantics=directed_reachability는 모든 양쪽 조합의 직접 대응을 뜻하지 않는다. 실제 경로는 list_page_relations의 reachable_from_page_id/reachable_to_page_id로 조회한다. 이유는 next_reason_offset을 따라 이어 읽는다.

구간에서 계산한 이벤트의 근거는 get_evidence에 change_id와 동일한 from/to occurrence ID를 함께 전달해 복구한다. 큰 이벤트/계보도 cursor와 개별 페이지·요소 도구로 순회한다. 전체 export에는 page-relations.jsonl과 mapping-relations.json이 포함된다.

저장된0.1/0.2 보고서는 변환하지 않고 읽는다. range_net은 native1/ocr9/ocr42/ocr43의 보관된 kernel, 동일한 방향 그래프 kernel을 유지한44, 또는 현재 엔진을 지원한다. 다른 과거 엔진의 재계산은 ENGINE_VERSION_UNAVAILABLE로 명시하며 저장된 history/export는 계속 조회한다. 앱-백엔드 통신 envelope는0.4.0이고 과거 보고서 본문의 schema_version은 유지한다.


현재 엔진의 range_net ID는 별칭 revision_id 입력도 해석된 occurrence ID로 정규화하므로 같은 구간의 ID가 같다. get_evidence에는 이벤트가 반환한 from_occurrence/to_occurrence를 그대로 전달할 수 있다. 보관된44 이하 kernel의 기존 raw-selector ID는 바꾸지 않으며, 근거 조회는 해당 구간의 유효한 revision/occurrence 별칭 조합을 대조해 복구한다.

## Schema0.4 same-version reference decisions

New53 reports use schema0.4.0 and canonical engine0.4.0-native.bundle.53. `bundle_decision.schema.json`, `bundle_selection.schema.json` and `list_bundle_decisions.schema.json` describe typed association history/input/retrieval; the manifest/report include optional `bundle_decisions`. `revision.bundle_mapping_basis` retains immutable raw automatic pairs for strict runtime replay. JSON Schema describes shape; same-source/PDF ownership, exact baseline/displacement/score/hash-chain replay, human appearance authority and final effective-map equality are enforced by runtime validators.

`list_bundle_decisions` accepts project/report scope, optional revision/source/decision filters, cursor/limit/output budget and Unicode-safe `reason_offset`/`reason_length` (1–500). Entries retain decision identity and direct longer-reason retrieval hints if budget summarization is necessary. Read-only MCP exposes this query, with no association write tool. Native `bundleMapping` is a private scoped desktop write action, separate from adjacent-version relation editing.

Historical0.1/0.2/0.3 reports remain readable. Their bounded query envelopes stay0.3.0 for complete historical replay; current0.4 reports use0.4.0. Exact archived44/45/50/51 kernels and immutable golden responses protect old event IDs and evidence rather than recomputing them with new semantics. Full exports add bundle-decisions.jsonl while preserving raw report JSON.

For `list_bundle_decisions` and the new content-reading tools, an alias shared by multiple occurrences returns `AMBIGUOUS_REVISION`; provide an exact `revision_occurrence_id`. A unique raw revision alias remains valid. Other archived query alias semantics remain unchanged. This prevents new filters silently hiding another occurrence of the same original asset set. Stored history get_change accepts a containing from/to interval; computed net IDs retain their original endpoints. Historical get_evidence recovery remains available.
