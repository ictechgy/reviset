# 스키마와 AI 조회 계약 · 0.1.0

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
| `get_element` | observation_id | 원문·bbox·추출법; text_offset/text_length |
| `list_changes` | mode, from/to, kind, entity_id, change_id, text | 관측 delta와 근거 |
| `get_entity_history` | entity_id | 각 버전의 페이지 원문·변경 ID |
| `get_evidence` | change_id 또는 observation_id 하나 | 페이지·인용·좌표; text_offset/text_length |

`get_report` 이하의 공통 scope는 project_id와 report_id다. report_id=`latest`는 첫 조회에서 고정 ID로 해석한다. 이후 해당 ID를 사용한다. revision_id 입력은 occurrence ID를 권장하며, 원본 revision ID를 사용하면 처음 등장한 occurrence를 선택한다.

모든 도구에 명시적 inputSchema/outputSchema, readOnlyHint가 있다. SDK의 기본 protocol은 2025-11-25이고 SDK가 이전 버전과 협상한다. 기준은 [MCP 도구 명세](https://modelcontextprotocol.io/specification/2025-11-25/server/tools)와 [resources 명세](https://modelcontextprotocol.io/specification/2025-11-25/server/resources)다.

리소스는 다음 template만 지원한다. 목록에는 허용 프로젝트의 manifest를 제공한다.

```text
docver://projects/{project_id}/reports/{report_id}/manifest
docver://projects/{project_id}/reports/{report_id}/revisions/{revision_id}/pages/{page_id}
docver://projects/{project_id}/reports/{report_id}/changes/{change_id}
docver://projects/{project_id}/reports/{report_id}/entities/{entity_id}
docver://projects/{project_id}/reports/{report_id}/evidence/{observation_id}
```

파일 경로·URL fetch·셸·본문 지시 실행은 받지 않는다. resource 응답도 bounded query 결과이며, 후속 cursor는 해당 도구로 전달한다. 원본 이미지 바이너리 제공은 아직 구현하지 않았다.

## 페이지네이션과 예산

공통 입력: 기본 limit=50, 최대 200. max_output_tokens 기본 4000, 입력 범위 256~8000이다. 현재 tokenizer 대신 UTF-8 byte 수를 보수적 token 추정 상한으로 사용한다. 이는 모델별 tokenizer와 다르다.

query 응답의 JSON byte 수는 해당 예산을 넘지 않는다. MCP는 structuredContent와 호환용 JSON text의 중복 비용까지 합쳐 예산에 맞춘다. 너무 작은 예산에는 `OUTPUT_BUDGET_TOO_SMALL`을 반환하므로 실용적으로 2000~8000을 권장한다. JSON-RPC transport envelope의 ID·헤더는 이 업무 payload 예산 밖이다.

응답은 `schema_version`, 고정 `report_id`, `items`, `next_cursor`, `coverage_gaps`, `truncated`, `omitted_fields`, `token_estimation`을 포함한다. coverage gap도 예산에 따라 일부만 반환할 수 있으며 이를 omitted_fields에 표시한다. 전체 coverage는 export의 manifest/report로 확인한다.

cursor는 report ID·쿼리 hash·안정 정렬 위치에 묶는다. cursor를 사용해도 필터를 똑같이 전달해야 한다. limit과 출력 예산은 바꿔도 된다. 다른 report에는 `CURSOR_REPORT_MISMATCH`, 다른 필터에는 `CURSOR_QUERY_MISMATCH`를 반환한다.

하나의 항목이 너무 크면 ID·resource URI·누락 필드 목록을 담은 summary를 반환하고 cursor를 진행한다. 원문은 다음처럼 읽는다.

1. `list_pages`로 page_id를 찾는다.
2. `get_page`의 cursor로 모든 요소 ID를 읽는다.
3. 요소 text가 생략됐으면 `get_element`를 text_length=100~500으로 호출한다.
4. `next_text_offset`을 다음 text_offset으로 사용한다(오프셋 단위는 JavaScript UTF-16 code unit). null이면 끝이다.

변경의 긴 인용은 `get_evidence`에 change_id와 offset/length를 전달한다. 생성된 summary를 완전한 원문으로 취급하지 않는다. 발표자 노트의 전체 원문은 현재 JSON/페이지 Markdown export에서 읽을 수 있으며, MCP에서 노트를 나눠 읽는 전용 조회는 아직 없다.
