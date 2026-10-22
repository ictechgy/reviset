# 스프레드시트 후속 개선 · 2026-10-22

현재 앱은 [Docver-Sheets.app](../release/Docver-Sheets.app), ZIP은 [workbook6 arm64](../release/Docver-0.5.0-workbook6-arm64.zip)다. 실행 소스 `ba8eae815950f92511b7ebb81335bc1f02c6e79f`와 이후 문서 커밋을 구분한다. ZIP391921164B, SHA256 `285802b0f37bb7179b1bc655e9c4bb931b077a531080b710a906edb74d371b5f`. 현재 Mac에서 실제 이동 실행한 비공개 패키지이며 공증·다른 Mac 합격을 뜻하지 않는다.

## 달라진 동작

- 셀 첫 조회와 범위 조회가 실패하면 바로 다시 읽는다. 원문 이어 읽기 실패는 처음부터 다시 읽어 복구한다. 주소 입력 오류는 읽기 실패와 분리하며 유효한 셀·변경 선택 시 해제한다.
- 셀 응답의 프로젝트·고정 보고서·버전 occurrence·시트·물리 주소와 행·열을 검사한다. 한쪽이라도 맞지 않으면 양쪽 근거를 함께 비우고 오류를 표시한다. 저장 관측이 없는 셀은 조회 실패·삭제와 구분한다. 잘못된 버전 근거를 가진 변경은 이전 셀 재시도 대상을 남기지 않는다.
- 이동한 행의 표시 범위가 다를 때만 `이후 버전` 기준을 표시한다. 이전 버전에만 있는 셀·공통 범위는 중립 라벨을 사용한다. 넓은 이력 조회 구간과 선택한 변경의 두 버전을 구분하며 그리드를 다시 클릭해도 구간이 다르면 안내를 유지한다. 다음·마지막 페이지의 이동 행동을 명시한다.
- 원문은 선택 가능한 고정폭 글자로 그대로 표시하고 관측 없음·빈 문자열·이미 읽은 짧은 필드 안내는 별도 보조 글자로 표시한다. 빈 조각은 원문 끝 표시를 반복하지 않는다. UTF-16 범위와 원문 자체는 바꾸지 않는다.

## 고정 소스 검증

| 검사 | 결과와 범위 |
| --- | --- |
| 집중 통합 | 최종 ba8eae8의88/88 PASS, 실패·skip0,19.918초. 실제 WorkbookModel·Bridge 회귀를 포함한다. |
| 컴파일 | 최종 TypeScript0.330초,10개 Swift 파일 엄격 동시성·warnings-as-errors3.900초, 앱 빌드31.440초 PASS. 네 실행의219개 입력 해시 불변·최종 소스 일치. |
| 실패·경계 |14개 잘못된 범위/형태 응답, 첫/이어 읽기/범위 실패와 재시도, 실제 요청의 고정 ID·주소·offset0, 누락 관측, 늦은 요청 차단·창 닫기, 주소 오류 해제, 이전 전용/이동/공통 라벨을 검증했다. |
| 이전 코드 대조 |58cbefe의 실제 WorkbookModel은 다른 프로젝트 응답을 표시해 `UntrustedCellDisplayed-wrong-project`로 실패한다. 당시 probe·소스 SHA와 red-control01 기록을 보존했다. 수정 후 같은 오류 경로를 차단한다. |
| 실제 앱 |최종 데모3버전·A2→A3/A4→A2·넓은 이력·페이지 이동·내보내기·로컬 라벨·AppKit 열 머리글/가로 이동을 확인했다. 실제 backend 응답이 새 validator를 통과하며 fixture만의 검사가 아니다. |
| 긴 원문 |최종1200셀씩 양쪽 화면에서1803UTF16 원문을2응답으로 재구성한다. 양쪽 A1의1024–1803 실제 독립 조각 일치·첫 조각 복귀와 수정하지 않은 실제 화면을 확인했다. |
| 이동 ZIP |최종20검사 PASS: 서명·guard runtime·9개 구성요소 SHA·build-info, 공백 경로의 실제 앱·12MCP도구15호출/범위 밖 거절/DB불변·기존5버전 PPTX/PDF 및 LibreOffice 흐름. 실행 전 생성 MCP설정이 이동 앱 내부 Node/서버를 가리키는지 확인했다. |

[집중 검사](../.omx/artifacts/workbook-improve-20261022/focused-04.json), [입력 결합](../.omx/artifacts/workbook-improve-20261022/source-seal.json), [ZIP 검증](../release/validation-workbook6.json), [실제 이동 화면](../.omx/artifacts/workbook-improve-20261022/native-demo-04/native-workbook-move-1.png), [실제 긴 원문](../.omx/artifacts/workbook-improve-20261022/native-dense-04/native-workbook-dense-raw-continuation.png). 모델 행동·정적 캡처이며 OS 클릭·키보드·VoiceOver 자동 검증으로 확대하지 않는다.

## 리뷰와 판정

독립 `code-reviewer`와 `architect`를 `agent_type`으로 각각 실행해58cbefe→ba8eae8의5개 경로 전체 diff를 검토했다. 코드 COMMENT/SOURCE_READY(LSP 도구 미노출), 구조 CLEAR/SOURCE_READY, 미해결 actionable0건이다. 소스·실행·패키지·제품 전체 상태를 구분한다.

Claude와 Grok은 각각58cbefe→5d9e621 전체 변경과5d9e621→ba8eae8 두 파일 후속 delta를 실제 CLI에서 APPROVE했다. Grok 전체 검토는1135.619초, 후속 형식 재시도는116.964초였다. 두 범위를 결합하며 하나의 최종 전체 HEAD 승인으로 다시 표시하지 않는다. 최종 ba8 실제 캡처2장은 Claude APPROVE다. Grok 초기 지적3건은 주소 오류 분리·잘못된 변경의 이전 anchor 제거·이전 전용 범위 중립 표시로 수정했다. c200 소스 APPROVE 등 중간 판정은 당시 범위로 보존한다.

Grok 첫 delta 응답은 판정을 굵은 Markdown으로 감싸 plain-line 판독에서 invalid였다. 원문을 보존하고 단 한 번 형식 재시도를 요청했다. 이 첫 응답 자체는 승인 근거로 세지 않는다. 초기 native-read01/02는 시험 scaffold 의존성·컴파일 옵션 실패이며 수정 후 실제 probe가 통과했다. precommit 엄격 검사 입력 해시를 확인하고 최종 clean HEAD에서 다시 검사했다.

각 호출의 stdout/stderr·절대경로·버전/도움말 probe·argv·prompt SHA·시작/종료·scope·terminal 판정은 `.omx/artifacts/workbook-improve-20261022/`에 개별 보존한다. Grok3600초, Claude 소스900초·이미지600초를 부여했다. 현재 결합은 [검증 JSON](../.omx/artifacts/workbook-improve-20261022/composite-qualification.json)을 따른다.

## 유지한 범위

이번 변경은 네이티브 읽기·표시에 한정한다. 동봉 Node·Vision·RendererGuard·bridge·MCP·Office 입력 검사·lockfile7개 구성요소는076 검증본과 바이트가 같다. [동일성 근거](../.omx/artifacts/workbook-improve-20261022/backend-identity.json). 전체341개 회귀는600fac9,40만 셀 새 분석11.548초/peakRSS3,149,283,328B는578의 역사적 실측이며 최종 새 실행이라고 하지 않는다. 기존 한도·OCR·Office 검증은 [기능 도입 기록](WORKBOOK-2026-10-22.md)에 별도로 남긴다.

원래4앱·4ZIP·HANDOFF/PLAN42개 해시와 직전 ZIP3/검증 JSON2개, 총44개 경로가 일치한다. 중간 ZIP4·5도 덮어쓰지 않았다. 모든 문서의 완벽한 OCR·PowerPoint 원본 화면 동일성, 수식 재계산·고급 Excel 개체·다른 Mac/공증·OS입력/VoiceOver 합격은 여전히 이 결과의 범위 밖이다.
