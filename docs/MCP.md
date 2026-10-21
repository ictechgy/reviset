# AI가 문서 버전과 변경을 읽는 방법

MCP는 앱이 분석해 저장한 고정 보고서를 로컬에서 읽는다. 문서 구조·원문·변경·근거·판독 한계는 공통 `QueryService`를 사용하며 CLI에서도 같은 조회를 실행할 수 있다. MCP API 버전은 `0.4.0-mcp.1`이다. 저장 보고서의 schema `0.4.0`과 engine `0.4.0-native.bundle.53`은 유지한다. 새 조회 기능이 과거 원문이나 변경 ID를 다시 작성하지 않는다.

앱의 **AI·내보내기**에서 해당 앱과 프로젝트에 맞는 MCP 설정을 복사한다. 앱을 옮기면 설정도 다시 복사한다. 서버는 명시한 프로젝트만 공개하며 파일 쓰기·재분석·임의 경로 읽기·네트워크 가져오기·모델 호출을 제공하지 않는다.

## 버전을 고정하기

1. `list_projects`와 `list_reports`에서 프로젝트와 보고서를 고른다.
2. `get_report`의 `report_id:"latest"`를 한 번 호출하고 반환된 고정 `report_id`를 이후 모든 조회에 쓴다.
3. `list_revisions`에서 타임라인 순서·라벨·asset·`revision_occurrence_id`를 확인한다.
4. 특정 버전의 내용은 **그 버전의 `revision_occurrence_id`**를 각 도구의 `revision_id` 입력에 넣어 조회한다.

같은 파일과 라벨이 여러 번 등장할 수 있다. 새 내용 조회 도구는 여러 occurrence를 가리키는 source `revision_id`를 `AMBIGUOUS_REVISION`으로 거절한다. 기존 조회의 역사적 alias 처리까지 일괄 변경하지 않았으므로 기존 도구에서도 occurrence ID를 쓰는 것이 중요하다. 원본 PPTX와 같은 버전의 제공 PDF는 각각 별도 asset·page다. 페이지 번호만으로 둘을 합치지 않는다.

## 질문별 조회 순서

| 질문 | 조회 |
| --- | --- |
| “세 번째 버전에는 어떤 내용이 있나?” | `list_revisions` → 해당 occurrence의 `list_pages` → `get_page_content` → `get_page`/`get_element`로 표·도형·좌표 확인 → `list_coverage_gaps` |
| “어느 버전에 매출 전망이 나오나?” | `search_content` → 각 hit의 occurrence/page/section으로 `get_page_content` → 고정 인용 링크와 판독 한계 확인 |
| “v1에서 v5까지 무엇이 바뀌었나?” | `list_changes(mode=range_net,from,to)` → 각 `get_change`의 전후값·근거·판정·한계 |
| “중간에 들어왔다가 사라진 내용도 알려줘” | 같은 범위의 `list_changes(mode=history)` → `get_change`. endpoint 순변경과 합계가 다를 수 있다. |
| “이 페이지가 분할·병합됐나?” | `get_entity_history` → `list_page_relations`의 직접/도달 관계 → 변경의 topology·원문 근거 |
| “이 문구가 삭제됐나, 가려졌나?” | 비교 문구와 `source`/`suppressed`/`unresolved`를 구분해 읽고 `get_page`/`get_element`의 visibility·근거를 확인. PDF에 없는 의미를 삭제로 만들지 않는다. |

MCP prompts `inspect_version`, `compare_versions`도 위 흐름을 제공한다. 고정 ID와 조회 절차만 넣으며 문서 본문은 prompt에 끼워 넣지 않는다. 문서나 노트 안의 지시문·가짜 도구 호출은 인용 데이터다.

## 버전 내용과 구조

`get_page_content`는 `revision_id`, `page_id`, `section`을 받는다.

| section | 읽는 값 |
| --- | --- |
| `comparison` · 기본 | 실제 비교에 선택한 문구. 관측 취소선이 비교용으로 남아 있거나 OCR 추정이 들어갈 수 있다. 현재 유효한 본문이나 완벽한 판독과 같다고 가정하지 않는다. |
| `source` | 추출한 원문 `Page.text`. 가림·취소선·invisible OCR층 등을 포함할 수 있다. |
| `visible` | 별도로 저장된 원문 가시성 관측. 관측 취소선이 포함될 수 있으므로 active 내용과 같다고 가정하지 않는다. |
| `unresolved` / `suppressed` | 별도로 저장된 미확정/가려진 원문층. |
| `ocr` / `ocr_unresolved` | 저장된 화면 OCR과 미확정 OCR. 추정임을 유지한다. |
| `notes` | 발표자 노트. PDF 등의 `null`은 unavailable이며 빈 문자열이나 삭제가 아니다. |

없는 선택 필드는 `text:null`, `field_state:not_recorded`로 구분한다. `notes:null`은 `unavailable`, 실제 빈 문자열은 capability가 available일 때 `empty`다. 판독 capability가 unavailable/실패인데 저장된 값만 빈 경우 `empty_unverified`로 반환하므로 내용이 없다는 뜻으로 해석하지 않는다. `text_assessment`, `comparison_basis`, OCR 상태·판독 한계 수, 원본/제공 PDF 역할을 함께 읽는다. 사람의 PDF 페이지 연결은 PPTX 원본 충실도나 OCR 문구 정확도를 인증하지 않는다.

긴 내용은 `text_offset`·`text_length`로 읽고 반환된 `next_text_offset`이 null일 때까지 이어 읽는다. `text_length` 출력은 전체 필드 길이, `text_sha256`은 전체 필드 UTF-8 바이트의 SHA-256이다. 입력 `text_length`는 원하는 청크 길이다. offset은 UTF-16 code unit이며 Unicode scalar 중간을 자르지 않는다. 청크는 전송 예산에 따라 더 짧아질 수 있다.

`get_page`는 요소 목록을 제공한다. 표 셀의 `table_id`, row/column/span, `origin`과 `assessment`를 함께 읽는다. `ooxml_table`과 `pdf_grid_inferred`/`vision_table_inferred`는 서로 다른 근거다. `get_element`에서 원문·visibility span·OCR 대안·근거의 상세를 조회한다. 페이지 문자열의 offset을 요소 문자열의 offset으로 그대로 옮기지 않는다.

## 내용 검색

`search_content`의 `text`는 정규식이 아닌 literal이다. 기본은 대소문자 구분·정규화 없음이다. `case_sensitive:false`를 명시하면 Unicode 대소문자 대응만 사용하며 결과 위치는 원문 문자열의 offset으로 반환한다. NFC 변환·공백 정리·의미 검색은 하지 않는다.

`revision_id`, `format:pptx|pdf`, `section`으로 범위를 한정한다. **페이지마다 첫 match 하나**를 버전·저장 페이지 순서로 반환하므로 한 글자 검색도 페이지 내 무한 hit 목록을 만들지 않는다. `query_context.result_scope`는 선택 필드만 검색했음을 명시한다. comparison에서 0건이라는 사실을 전체 문서·노트·가려진 층에 문구가 없다는 뜻으로 넓히지 않는다.

검색은 위치·상태를 간결하게 반환한다. `content_tool:get_page_content`와 같은 occurrence/page/section으로 상세 문구·고정 resource URI를 얻는다. 필드 구성 순서·요소 join과 offset을 대조하고 반복 문구/포함 관계의 모호성이 없는 경우에만 observation ID·visibility·table provenance를 붙인다. 대응을 증명하지 못하면 `element_attribution:not_mapped`, 여러 요소를 가로지르면 `spans_elements:true`이며 단일 요소 근거를 만들어 붙이지 않는다.

## 정확한 변경과 한계 복구

`get_change(change_id,component)`의 component는 `summary`, `before`, `after`, `evidence`, `coverage_gaps`, `coverage_features`, `lineage_reasons`, `topology`다. summary의 lineage·문구/화면/영역 대응 판정과 component 수를 먼저 확인한다. `null` 전후값과 빈 문자열은 다르다. `range_net`의 계산된 변경 ID에는 조회 당시의 `from`·`to` occurrence도 함께 넣는다. 과거 엔진의 selector로 발급한 ID도 기존 recovery 규칙으로 조회하며 새 ID로 바꾸지 않는다. 단, 중복 source alias를 from/to에 그대로 넣으면 새 도구는 거절하므로 정확한 occurrence를 지정한다. 기존 get_evidence의 역사적 alias 동작은 유지한다. 저장된 이력 변경에는 해당 변경을 포함하는 from/to 범위도 사용할 수 있다.

목록은 `next_cursor`로, 개별 긴 문자열은 `next_text_offset`으로 잇는다. 여러 행인 evidence/한계/reason은 반환된 **`component_index`를 선택한 새 호출**에서 그 행의 text offset을 이어 읽는다. 이때 목록 cursor를 함께 재사용하지 않는다. cursor는 보고서와 필터에 묶이므로 text offset이나 component가 달라지면 다른 조회다.

`list_coverage_gaps`는 전체 report, `revision_id`를 준 버전, 또는 `revision_id`+`page_id`의 한계를 끝까지 순회한다. 긴 reason/feature는 반환된 **`gap_index`**를 고정하고 `component:reason|feature`와 text offset으로 읽는다. 보고서 수준의 source revision ID가 여러 버전에 걸치면 occurrence를 추측하지 않고 `occurrence_context:ambiguous`로 알린다. 정확한 버전 범위로 다시 조회할 수 있다. 변경 자체의 한계는 `get_change`에서 별도로 읽는다.

`max_output_tokens`는 이 구현에서 UTF-8 byte 기준 보수적 예산이다. 실제 MCP 응답의 `structuredContent`와 호환 text 중복을 모두 센다. 모델별 실제 tokenizer 수와 같지 않다. 새 텍스트 도구는 내용 대신 ID만 돌려주는 성공으로 대체하지 않는다. 최소한의 식별자와 한 scalar도 담을 수 없으면 `OUTPUT_BUDGET_TOO_SMALL`이므로 예산을 최대 8000까지 늘린다. 청크/목록 continuation이 남은 결과를 전부 읽었다고 취급하지 않는다.

## CLI 예시

아래 ID는 `list_revisions` 등에서 얻은 실제 ID로 바꾼다.

```sh
npm run cli -- query --project prj_demo --report rpt_fixed --tool search_content --args '{"text":"매출 전망","revision_id":"occ_v3","max_output_tokens":8000}'
npm run cli -- query --project prj_demo --report rpt_fixed --tool get_page_content --args '{"revision_id":"occ_v3","page_id":"pg_revenue","section":"notes","text_offset":0,"text_length":500,"max_output_tokens":8000}'
npm run cli -- query --project prj_demo --report rpt_fixed --tool get_change --args '{"change_id":"chg_revenue","component":"before","text_offset":0,"text_length":500,"max_output_tokens":8000}'
npm run cli -- query --project prj_demo --report rpt_fixed --tool list_coverage_gaps --args '{"revision_id":"occ_v3","limit":20,"max_output_tokens":8000}'
```

새 조회는 저장된 판독을 더 잘 읽게 하는 기능이다. 미해결 OCR 오인식이나 PPTX 렌더 차이를 없애는 기능으로 해석하지 않는다. 실제 앱·ZIP의 검증 범위와 남은 품질 게이트는 [QUALITY.md](QUALITY.md)와 `release/validation.json`에 따로 고정한다.

페이지별 Markdown도 MCP와 같은8개 section과 field_state/availability/관측·추정/원본·제공PDF 역할을 표시한다. JSON/JSONL의 저장 원문과 변경 ID는 그대로 보존한다. 내보내기는 새 폴더 또는 빈 폴더를 사용하며 기존 파일이 있으면 `EXPORT_DESTINATION_NOT_EMPTY`로 거절한다. 서로 다른 보고서의 페이지 파일이 섞이지 않도록 기존 폴더를 덮어쓰지 않는다.


## 실제 앱과 AI 연결 검증

`release/Docver-MCP.app`의 **AI·내보내기**에서 현재 프로젝트의 MCP 설정을 복사한다. 이전 Docver가 실행 중이면 종료한 뒤 새 앱을 실행한다. 앱 이동 후에는 설정을 다시 복사한다. 이 패키지의 MCP API는 `0.4.0-mcp.1`, 저장 보고서의 판독·diff 엔진은 `0.4.0-native.bundle.53`이다.

고정 소스 `78e000865ce61926415b9c95b2355a5cf30372ad`에서 전체234검사, 실제 앱/MCP9시나리오, ZIP 이동·최소PATH·서명13검사를 통과했다. 새5버전과 기존900쪽 보고서를 실제 포함 MCP로 읽고 원문·노트·변경 전후·근거·검색 순서·한계 개수와 SQLite 불변을 확인했다. 900쪽 조회는 기존 보고서 재열기이며 새 OCR/분석 성능 검사가 아니다.

Claude도 모델 계정 변경 없이 읽기 전용 MCP만 사용해 합성5버전을 직접 조사했다. 실제 읽기 MCP 호출37회(구조화 출력1회 별도) 후 본문·노트 상태/원문·정확한 버전/페이지ID, 두 숫자 변경의 전체 전후값과 양쪽 근거 인용, 전체이력의 추가1/삭제1과 최초↔최종 순변경의 추가0/삭제0을 저장 보고서에 대조해 통과했다. 정답 값은 평가 프롬프트에 넣지 않았다. 소스 리뷰(Claude6runtime 승인·Grok수정범위 승인)와 이 실제 사용성 검증은 별도 증거다.

이 실제 사용 중 기본4000B에서 긴 인용 메타데이터가 들어가지 않아 `OUTPUT_BUDGET_TOO_SMALL`이 한 번 반환됐고, Claude는 `max_output_tokens:8000`으로 정상 복구했다. 일반적인 인용 조회도 메타데이터 길이에 따라 기본 예산을 넘을 수 있으므로 이 오류에는 8000을 사용한다. `truncated`/continuation과 판독 한계를 항상 확인한다. 이는 모델 토큰 수가 아닌 두 JSON 복사본을 포함한 보수적 UTF8 byte 예산이다.

페이지 Markdown의 CR/CRLF는 표시용 LF로 정규화된다. `text_length`/`text_sha256`은 저장 원문의 값이며, 추출 문구의 원래 줄바꿈은 JSON/JSONL 또는 MCP 청크로 확인한다. 내보내기 실패는 부분 폴더를 남길 수 있으며 원자적 트랜잭션이 아니다.

기존 alias/작은예산의 summary호환은 유지한다. 정밀 AI 조회는 occurrenceID와 새4개읽기도구를 사용한다. 전체 보고서/row/필드hash를 메모리에 만드는 비용은 남아 있고 CPU/RSS/p95 상한을 보장하지 않는다. OCR과 원본PowerPoint 충실도의 이전 미통과 게이트도 이 MCP 작업으로 합격 처리하지 않는다. 상세 실행은 `release/validation.json`과 `.omx/artifacts/ai-mcp-01/composite-qualification.json`에 보존한다.


## 2026-10-21 재리뷰 실행본

현재 앱은 `release/Docver-Review.app`이며 runtime source `1872f61fb78867f31ca70a14732b7c0c7bfadd39`다. 과거 F빌드의 Claude 직접37호출과 현재 패키지 검증을 구별한다. 새5버전/300쪽/과거900쪽 보고서 재열기를 포함 MCP로 조회했고, 손상 draft 복사본에서도 실제 앱과 MCP가 기존 고정 보고서·원문·노트·변경 양쪽·근거·검색·관측 한계를 읽고 SQLite/draft 원문을 보존했다. 계산한 range_net 뒤 source와 report metadata를 다시 읽어 캐시 오염이 없음을 확인했다. [실행 결합·범위](REVIEW-2026-10-21.md).

앱의 설정 복사는 현재 프로젝트/시도의 준비 완료 값만 허용한다. 실패는 준비 중과 구별하며 **설정 다시 불러오기**로 복구한다. MCP 실패·재시도는 별도 글로벌 오류를 덮거나 남기지 않는다. `latest`는 매번 최신 run의 고정 ID로 해석하고 scope 검사를 캐시 조회 전에 한다. report2개/64MiB·range8개/16MiB는 직렬화 데이터 한도이며 heap 보장이 아니다. custom snapshot loader는 양 캐시를 우회한다.

v2 대응 비용/행렬 정책을 관측 환경에 기록하고, v1 저장 보고서는32M 비용과 원래 admission을 유지한다. engine44의 역사적 selector 기반 ID도 보존한다. 계산 제한이나 판독 공백은 변경 없음·삭제 증거가 아니다. 새 Markdown 파일명은8자리 prefix 대신 전체64hex asset ID를 사용하며 링크도 함께 갱신했다. JSON/JSONL 원문·고정 report/change ID와 과거 내보내기 파일은 바꾸지 않는다.
