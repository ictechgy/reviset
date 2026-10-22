# 현재 검증 · 2026-10-22 스프레드시트

현재 앱은 `release/Docver-Sheets.app`, ZIP은 `release/Docver-0.5.0-workbook6-arm64.zip`, clean runtime source는 `ba8eae815950f92511b7ebb81335bc1f02c6e79f`다. [후속 변경·검토·한계](WORKBOOK-RECOVERY-2026-10-22.md), [이동 ZIP 검증](../release/validation-workbook6.json), [실행 결합 JSON](../.omx/artifacts/workbook-improve-20261022/composite-qualification.json)을 따른다. 이후 문서 커밋과 앱의 실행 소스를 구분한다.

최종88/88 집중 검사·TypeScript·경고0 엄격 Swift, 실제 앱 데모·긴 원문·이동ZIP20검사가 통과했다. 독립 코드 COMMENT/SOURCE_READY, 구조 CLEAR/SOURCE_READY, actionable0건이다. Claude는5d 전체 변경/ba8 후속 delta와 최종 실제 이미지2장을 각각 APPROVE했다. Grok 최종 범위와 패키지 판정은 위 후속 기록에 명시한다. 정적 캡처·소스·OS 입력·제품 전체 승인은 별개다.

전체341개 회귀는600fac9, 정상40만 셀 새 분석11.548초/peakRSS3,149,283,328B는578의 실측이다. 과대 반복 서식 한도·대용량 재열기는076에서 검증했다. 최종 앱의7개 공통 backend/helper 바이트가076과 같지만 과거 결과를 최종 새 측정으로 바꾸지 않는다. 수식 재계산·고급 Excel/Calc 개체·다른 Mac·공증·OS입력/VoiceOver 합격을 의미하지 않는다. 기존 보편 OCR·PowerPoint strict 참조 미해결은 OPEN이다. 이전42개 해시와 직전ZIP3/검증 JSON을 더한44개 보존 경로가 일치한다.

아래2026-10-21과 E3·AL·F 기록은 각 당시 고정 소스의 역사다.

# 현재 추가 검증 · 2026-10-21 재리뷰

현재 실행본은 `release/Docver-Review.app`, runtime source `1872f61fb78867f31ca70a14732b7c0c7bfadd39`이며 [재리뷰·한계·증거](REVIEW-2026-10-21.md)와 [이동 ZIP 검증](../release/validation-review1.json)을 기준으로 한다. 아래 E3·AL·F 등 과거 검증은 각 고정 소스에만 해당한다.

R5 전체267 PASS + 최종7파일 집중21 PASS + 최종 실제 앱/MCP16작업 + 이동ZIP16검사를 결합한 **same-Mac PRIVATE_PACKAGE_READY**다. 최종R8전체npmtest, 보편OCR, PowerPoint픽셀동일성, OS입력/VoiceOver·다른Mac·공증/공개배포 합격으로 해석하지 않는다. strictSwift exit0에도 기존 캡처 경고4개가 남는다.

세 native parser 정책에서 전역 디렉터리 data grant를 없앴다. 다만 정확히 허용한 ancestor **내 entry 이름**, helper 폴더·OS/font/vendor/job 루트와 전역 metadata/필요 broker는 남으므로 완전한 파일명·broker 격리가 아니다. per-job CoreML 초기 비용이 실제로 있으며300쪽PPTX32.624초를 스캔PDF OCR 속도로 대신하지 않는다. 새 v2 대응은1000×1000 지원 영역과 행렬/계산 비용 제한을 구분하며, 비대칭·상한 밖은 명시 실패한다. v1 과거 admission은 보존했다.

새 최종 실제 화면에서 이전 P2(문장 전체 색상·근거 버전 누락·3행 대응 목록)를 Claude가 닫고APPROVE했다. 원본 SHA/mtime와 DB 불변·손상 draft 읽기·관측한 종료/재시작은 별도 실행으로 통과했다. 기존 stress 판독 코퍼스와 독립 PowerPoint 참조 미통과를 이 리뷰로 합격 처리하지 않는다. 자세한 잔여 WATCH는 위 재리뷰 문서를 따른다.

# 품질 검증 · 진행 중

요구: 실제 네이티브 Mac 앱에서 PDF 원문·가시성·OCR·PPTX 원본 충실도를 보완한다. `HANDOFF.md`와 `PLAN.md`는 원본 그대로 보존한다. 이 문서는 현재 판독 품질의 합격 기준이며 전체 PDF의 100% 인식을 선언하는 문서가 아니다.

## 무료 OCR 연구 loop05 · 새 Paddle 후보 두 개 모두 보류

`.omx/artifacts/quality-loop-05/paddle/`에서 공식 저장소의 고정 revision·파일 SHA를 검증한 `PP-OCRv6_medium_rec`와 `korean_PP-OCRv5_mobile_rec`를 별도 연구용 환경에서 비교했다. 사전 등록한 같은 image-only crop/default CTC 조건으로 기존480개와 별도132개 PNG 전부를 두 모델에 넣었다. 정답·원본 글꼴·이전 답을 inference에 전달하지 않았고 해당 경로 읽기와 네트워크를 차단했다. 정답 대조는 inference 종료 후 별도 평가 단계에서 수행했다. 연구용 의존성73개의 당시 audit은 알려진 취약점0이며 안전성 인증을 의미하지 않는다. 모델/환경은 앱에 포함하지 않았다.

480개는 상관된 합성 사례이며 일반 문서 정확도의 표본이 아니다. raw 전체 문구 기준은 다음과 같다.

| 모델 | 정확 | 비어 있지 않은 오독 | 빈 결과 | 기존 정상218개 중 손실 |
| --- | ---: | ---: | ---: | ---: |
| 기존 helper26의 이전 결과 | 218 | 22 | 240 | 기준 |
| PP-OCRv6 medium | 335 | 125 | 20 | 43 |
| Korean PP-OCRv5 mobile | 293 | 187 | 0 | 28 |

V6의 공백 문자만 출력한66개도 raw에서는 비어 있지 않은 오독이다. 별도 NFC/공백 정규화 지표에서는 빈 결과86개다. 기존 오독22개 중 각각12개·2개를 고쳤지만 기존 정상 판독43개·28개를 훼손해 사전 보존 기준을 통과하지 못했다. 두 모델이 같은 오답에 합의한 사례도480개 중33개다. 합의나 모델 점수만으로 정확 판독으로 승격하지 않는다.

별도132개에서 정확 결과는 각각59개·67개, 비어 있지 않은 오독69개·65개다. 정답이 빈4개는 두 모델 모두 올바르게 빈 결과였고 정확 수에 포함한다. 빈 출력 총8개·4개 중 이 정답4개를 제외한 누락은4개·0개다. 같은 오답 합의는13개였다. 공백 출력과 빈 정답이 겹치는 집계를 중복 없이 해석한다.

초기 실행은 sandbox 호환성으로 native SIGSEGV와 AVX 탐지 shell 실행 거절이 났다. 실패 원문과 사전 amendment1–4를 남겼고, 같은 이미지/모델/알고리즘/판정 기준을 유지한 채 연구 작업 안에서 필요한 OS 실행 경로만 허용한 뒤 전체480개62.818823초·132개18.101446333초의 inference를 완료했다. 모델 graph/parameter hash는 전후 동일했고 원격 Python/pickle 실행은 허용하지 않았다. OS/계정/전역 설정은 바꾸지 않았다.

최종 판정은 `final-evaluation.json`의 **REJECT_NO_PRODUCTION_ADOPTION**이다. 프로덕션 OCR·의존성·엔진/schema·보고서는 바꾸지 않았고, 후보가 보존 기준에서 탈락했으므로 앱 통합·cold replay gate를 통과했다고 세지 않는다. 미해결 OCR과 PowerPoint strict0/26은 계속 OPEN이다. 무료 대체 도구의 일부 개선을 완벽 판독으로 부르거나 정답 기반 문구 치환·사후 임계값 조절로 실패를 숨기지 않는다.

## 최근 검증본 E3 · 2026-10-20

같은 Mac용 선택적 참고 창 검증본은 `release/Docver-Render.app`, ZIP은 `release/Docver-0.4.0-render2-arm64.zip`이다. clean runtime source는 `af0309a272f79ba82b2a14882748e6613e984e09`다. 앱의 빌드 원본과 이후 문서 커밋을 구분한다. `release/validation-render2.json`과 `.omx/artifacts/native-sidecar-03/composite-qualification.json`이 원본·앱·패키지·리뷰를 연결한다. 엔진53/schema0.4/Vision26/MCP API0.4.0-mcp.1의 판독·diff 알고리즘과 저장 보고서는 유지한다.

- 전체 `npm run check` **252/252 PASS**, 실패·skip·cancel0. 테스트165.502466625초, 명령166.277165875초이며 검증 전후 추적190개 파일이 일치했다. 빌드21.884189875초.
- 실제 앱/MCP **15개 작업 PASS**: 네이티브 새5버전·공개PPTX10개·새300쪽 덱의12작업과 동봉MCP의5버전·300쪽·과거900쪽 재열기3작업이다. 300쪽 작업33.012471958초, 같은300쪽을 두 occurrence로 사용했으므로 서로 다른 원본600쪽 분석으로 세지 않는다. 과거900쪽 재열기도 새900쪽 분석이 아니다.
- 공개10개/300쪽에서 production Sheet·PDFKit의 선택 페이지·전체 페이지 수·실제 PDF 경로·bridge PDF SHA·active lease를 확인했다. `model.sidecarRequest=nil` 후 job/lease 정리와 report/SQLite 불변을 검증해 C의 실제 실패를 닫았다.
- 실제 앱 SIGKILL의 helper 종료와 재열기 외에, bridge+앱 SIGKILL로 **실제 pending job/lease를 남긴 뒤** 같은 library의 앱 재실행으로 복구·DB 불변을 확인했다. production Swift Bridge와 동봉 backend의 Task 취소는 **명시적 sidecarClose 전에** 자체 helper·파일이 정리되고 독립 조회가 살아 있는 것을 확인했다. 종료 뒤 explicit close는 멱등성 검사다.
- ZIP **391389156bytes**, SHA256 `7cf45ec1649d7b1e47481d74f11daeea4a7f8fa598121a3302cbea0d1682f8bf`. 공백 경로로 이동·최소 PATH·cwd `/`의 실제 앱/MCP/서명 등 **16개 검사 PASS**. 원래 앱과 이동 복사본 모두 guard의 hardened runtime·빈 entitlement·같은 SHA를 확인했다. `release-validation/validation.json`이 상세 범위를 고정한다.
- 추가 실제 OS probe는 현재 guard로 `vfork`·`posix_spawn`·경로 밖 canary hardlink의 EPERM과 canary 불변을 확인했다. 이는 자기 소유 fixture 검사이며 임의의 OS 취약점 방어 증명이 아니다.

원래 base `5982c71e4c0d859bf2facca954a5caa494363ade`부터 E3까지26개 변경 경로의 독립 코드 lane은 **APPROVE / SOURCE_READY**, 아키텍처 lane은 **WATCH / SOURCE_READY**다. 이후 실제 앱·fault·패키지 증거에 대한 별도 closure도 각각 APPROVE와 WATCH로 **INTEGRATION_READY / PRIVATE_PACKAGE_READY**를 확인했다. 결합 판정은 **COMMENT / WATCH, 같은 Mac의 비공개 패키지 READY**이며 제품 전체는 **OPEN**이다. 디렉터리 이름·metadata 예외, 문서별 보수적 거절·변환 비용, 외부 설치본/글꼴 의존은 남은 WATCH다. OS 입력·IME·VoiceOver·다른 Mac·공증·공개 배포·글꼴/vendor 재배포 자격은 이 결과에 포함하지 않는다.

Claude와 Grok의 전체 E1 검토 뒤 지적된 오류 안내와 monitor 경계를 수정했다. E1→E3의 전체 intervening9경로 delta 및 새 회귀 검토에 두 advisor가 각각 terminal APPROVE를 반환했다. 이는 해당 delta의 closure이며 외부 advisor의 E3 전체26경로·제품 정확도 승인으로 확대하지 않는다. Grok에는1200초 제한을 주었고 stdout/stderr·argv·prompt hash·scope를 개별 보존했다. 내부 두 lane은 전체 E3 diff를 검토했다. Agy는 이전 `RESOURCE_EXHAUSTED` quota/exit3/stdout0으로 사용 불가였으며 유효한 E3 리뷰가 없다. 상세 validity는 `advisor-validity.json`이다.

E3는 monitor를 READY 이전 trusted guard로 exec하고 PT_DENY_ATTACH와 hardened runtime을 적용한다. 실제 fixture에서 parent-side `setpgid`는 EACCES, Mach task port는 거절, ptrace 시도는 부모 SIGSEGV와 전체 소유 PID 종료로 닫혔다. 추가 SBPL `system-debug` deny의 독립 효과를 이 결과로 증명하지 않는다. E2에서 parent-side group 변경은 재현됐지만 attach·monitor 정지·timeout 우회·실제 x2t exploit은 재현되지 않았다. E2의 통합 보류와 C/D 실패 기록은 각각 당시 snapshot의 증거로 남긴다.

포함 Node·MCP·Vision은 이전 F의 바이트와 같다. F의 실제 Claude37도구호출+구조화응답1 증거는 이전 F 범위로 유지하며 E3에서 새 AI 소비자 검증을 실행했다고 표시하지 않는다. 기존 `Docver.app`·`Docver-MCP.app`과 두 ZIP의 SHA는 그대로다. HANDOFF/PLAN도 원문 그대로다. OCR 480개/PowerPoint26쪽의 미해결 게이트는 아래와 같고 앱 안정성 통과로 판독 성공 수를 올리지 않는다.

## 이전 MCP 검증본 F · 2026-10-20

현재 MCP 개선 검증본은 `release/Docver-MCP.app`, ZIP은 `release/Docver-0.4.0-mcp1-arm64.zip`이다. clean runtime source `78e000865ce61926415b9c95b2355a5cf30372ad`에서 빌드했다. 엔진은 `0.4.0-native.bundle.53`, schema0.4.0, Vision helper26, MCP API0.4.0-mcp.1이다. 이후 문서 변경 커밋과 앱 빌드 원본 SHA를 구분한다. `release/validation.json`, `release/validation-mcp1.json`, `.omx/artifacts/ai-mcp-01/composite-qualification.json`이 해당 바이트와 증거를 고정한다.

- 전체 234/234 테스트 통과, 실패·skip·cancel 0. 테스트 156.831809459초, 명령 전체 157.588447208초. 검증 전후 추적 소스 176개 바이트가 일치했다.
- 실제 앱/동봉 MCP 9개 작업 통과: 새 5버전·backend·수동 관계·번들 대응·참조 PDF 화면·공유 XML 원문·기존 900페이지 보고서 재열기·5버전 MCP·900페이지 MCP. 900페이지 재열기를 이 빌드의 새 900페이지 분석으로 계산하지 않는다.
- ZIP 390897279bytes, SHA256 `20f12659025bebc11db7e8818ccb37861c4e2066570a4c1c778e70db439e6a3a`. 공백 경로에 풀어 최소 PATH/cwd `/`의 13개 검사를 통과했다. 앱/동봉 Office 서명, 새 5버전·MCP·재열기 등 상세 범위는 위 합성 증거에 기록했다.
- 원래 base부터 전체 17개 변경 경로의 독립 코드 판정은 APPROVE/READY, 아키텍처는 WATCH/SOURCE_READY다. 소스 준비와 제품 전체 완료는 별개다. 후속 문서만 변경한 범위도 별도 closure로 구분한다.
- Claude가 실제 동봉 읽기 전용 MCP에서 37개 도구 호출과 1개 구조화 응답을 수행했다. 5버전·노트·두 변경·과거 이력·net 조회 결과를 확인했고 DB 바이트는 유지됐다. 기본 4000byte 응답 예산 오류 1회는 8000byte로 재요청해 복구했다. 이 사용 검증을 전체 판독 정확도 승인으로 확대하지 않는다.

이전 `release/Docver.app`과 `release/Docver-0.4.0-native53-svg-guard-v1-arm64.zip`은 runtime source `3ff0af791b661c8243ae8276a76e0c3a47644be9`의 별도 검증본으로 보존했다. 그때의 223개 테스트·앱 11개 시나리오·새 900페이지 분석(60.337862583초, RSS 표본 최대1013.484375MiB), ZIP390495400bytes/SHA256 `44eabdfc94b7a9c1fa3da55b8ef00adc3cd2cf2b56b31a8130d4e2e3c884f6bf`와 전체152경로 리뷰는 `.omx/artifacts/quality-loop-03/native53al-composite-qualification.json`의 해당 원본에만 적용한다. 이전 600/900/1,200페이지 재열기와 현재 검증본의 검사를 혼합하지 않는다.

미해결 판독 문제도 유지한다. 같은 helper26의 이전 480개 상관된 합성 사례에서는 전체 문구 일치 218개, 비어 있지 않은 오인식 22개, 판독 보류/빈 결과 240개였다. 이번 앱에서 480개를 새로 전수 실행한 수치로 바꾸지 않는다. 오인식에는 `Client`→`Cllent`, `biIling`→`billing` 등이 있다. 이를 정답 문구로 강제 치환하지 않으며 원문 이미지·관측·추정 경고를 보존한다. 별도 OCR 엔진/언어·확대·축소 후보는 기존 정상 판독을 훼손하는 반례 때문에 채택하지 않았다. 렌더 해시 대조에서 같은 픽셀/다른 정답 충돌은 없었으므로 이 자료가 판독 불가능성을 증명한 것도 아니다.

이전 독립 PowerPoint 기준 26쪽의 엄격 픽셀 동일성도 0쪽이었다. MCP 개선이나 XML·문장 순서·리소스 경계 수정이 그 충실도 게이트를 통과시킨 것은 아니다. 사용자는 PowerPoint 사용권이 없어 무료 도구로 계속하도록 선택했다. 현재 LibreOffice 렌더와 공개된 독립 기준 PDF로 검증하며, 유료 앱의 설치·활성화를 전제하지 않는다. 다른 Mac/최소 OS, OS 입력·IME·VoiceOver, Developer ID 공증·공개 배포 검증도 남아 있다. 따라서 제품 전체 완료 상태는 **OPEN**이다.

이전 판독 루프의 Claude 소스 리뷰 timeout·Grok timeout·Agy quota 제한은 그 범위의 실패 증거로 보존한다. 후속 MCP 제안/실제 클라이언트 사용 검증과 이번 OCR 논의의 유효한 응답을 과거 실패나 새 소스 승인으로 바꾸지 않는다. 실제 화면에 대한 이전 승인을 새 빌드 전체 승인으로 확대하지 않는다.

## 선택적 네이티브 참고 창 · E3 검증 범위

`Docver-Render.app`의 별도 PDFKit 참고 창은 원본 SHA·고정 보고서·버전 occurrence·페이지를 확인한 뒤 OnlyOffice로 문서 전체를 변환한다. 기본 렌더러나 저장 report·diff·MCP 결과는 바꾸지 않는다. 현재 E3 검증 범위는 위에 고정하며 제품 전체 완료와 구분한다.

빌드에 호스트 설정을 넣으려면 `DOCVER_APP_NAME=Docver-Render.app DOCVER_OPTIONAL_SIDECAR=host-bound npm run mac:build`를 명시해야 한다. `dist/onlyoffice-sidecar`에 이전 준비물이 남아 있어도 플래그 없는 일반 빌드에는 provider·호스트 글꼴 경로·metadata가 들어가지 않는다. 다른 앱 이름에서 이 플래그를 쓰면 빌드 전에 거절한다. 외부 vendor 앱·indexer·글꼴 프로그램은 복사하지 않는다. 설정과 metadata는 이 Mac에 종속되며 공개·다른 Mac 배포 자격이 아니다.

참고 창은 숨김 페이지, 이미지뿐인 페이지, 짧거나 반복되는 문구처럼 모든 페이지의 대응 근거를 확보할 수 없는 문서를 거절한다. source-only 대응 검사로 불가능한 문서는 변환 전에 페이지 번호와 함께 알린다. 원본 구조의 제외·가림 상태를 반영해 페이지당 최대8개 고유 문구 후보를 쓰고, 변환 후에도 페이지 수·비율·다른 페이지 문구의 혼입을 검사한다. 이 조건이 문서 내용 전체의 정확도나 PowerPoint 동일성을 증명하지 않는다. 전체 페이지의 사용자가 이동하는 참고 화면을 보이므로, 선택 페이지만 검사하도록 대응 기준을 낮추지 않는다.

입력·임시 파일·metadata·PDF를 포함한 job의 sampled256MiB 초과 거절, 파일 성장128MiB, process별 CPU90초, 감독 변환120초, stdout/stderr 각각1MiB 제한을 유지한다. 2k페이지·20M원문/PDF문자 및 source 준비와 PDF 검사 각각의8M비교/2B문자 검사 예산은 각각 독립적인 거절 조건이다. 페이지/문자 상한에 맞는 모든 문서를 받아들인다는 약속은 아니다. 매번 전체 문서를 검증·변환하며 미디어가 많은 문서는 더 일찍 제한될 수 있다. 자원 상한을 올리거나 보류를 정확 판독으로 세지 않는다. source unzip/XML 검증 같은 동기 준비 단계는 즉시 취소를 보장하지 않으며, 문구 대응과 PDF 페이지 검사는 중간 취소를 확인한다.

후속 구현은 broker Mach 조회·등록, preference/LaunchServices, 다른 프로세스 신호, POSIX/SystemV IPC와 IOKit도 차단한다. 감독기는 부모 종료를 감시하고 로그 파이프가 닫혀도 자식 그룹 정리 전에 SIGPIPE로 죽지 않는다. helper의 실패 exit에서는 close를 기다리기 전에 그룹을 정리한다. 앱 정상 종료는 자체 참고 요청만 취소하고, 브리지는 앱 부모를 잃으면 자체 작업을 중단한다. macOS 회귀 테스트는 실제 규칙으로 내부 일반 파일 읽기 허용/경로 밖 읽기·쓰기/소켓/추가 fork·exec/환경·Mach 조회·신호 차단, 용량·symlink·로그·취소·timeout, 감독기 SIGKILL 및 부모 SIGKILL을 확인한다. 이 결과를 임의의 OS 취약점에 대한 완전 격리 증명으로 부르지 않는다.

startup은 exclusive app-lock 아래 valid pending/closing/active-only lease, 빈 pre-lease 폴더와 검증된 seed만 복구한다. 알 수 없는 비어 있지 않은 폴더나 손상된 lease는 보존하고 UI에서 정리 실패 수와 폴더를 볼 수 있게 한다. 문서·보고서 열기는 유지한다. 새 smoke는 PDFKit의 실제 경로와 bridge PDF SHA, 선택 페이지, DB/report 바이트와 닫은 후 정리를 확인한다. 이 문단을 작성했던 C의 실제 실패와 이후 D/E/E2/E3의 결과는 아래 이력에 분리한다. 현재 E3의 앱·리뷰·이동 ZIP 결과는 위 최근 검증본에 고정한다.

### 실제 C 앱 반례와 후속 D 소스

C clean `6c032236b7c43800ea02a485007014871514df46`는 전체249테스트와 앱 빌드·fresh5버전을 통과했으나 첫 공개 PPTX의 실제 닫기 검사에서 `SIDECAR_CLEANUP`으로 실패했다. PDFKit 표시·선택3쪽·PDF 경로/SHA 검사 다음, report/DB 바이트 검사 전에 실패했으므로 그 뒤의 불변성 검사를 통과로 세지 않는다. 원문 실패·앱 바이트·capture를 `.omx/artifacts/native-sidecar-01/`에 보존한다. C 독립 양 lane은 실제 반례를 반영해 BLOCK/REQUEST_CHANGES로 판정했고 C ZIP은 만들지 않았다.

D는 화면의 `.onDisappear` 대신 모델의 요청 교체·nil 전환에서 이전 요청의 취소 토큰과 고정 scope로 정리한다. 같은 토큰을 실제 bridge 실행에도 넘기므로 요청이 닫힌 뒤 늦게 시작되는 작업도 실행하지 못한다. Sheet가 전혀 없는 native model 회귀 검사가 프로젝트/보고서를 바꾸고 교체·닫기·지연 실행·다른 조회 보존·중복 정리 없음까지 확인한다. 참고 창의 밝은 배경도 명시한다.

Claude C의 예산 중복 계산 지적은 source 준비에서 계산한 고유 문구를 요청 안에서 한 번만 보관하고 PDF 검사가 재사용하도록 수정한다. 두 단계의8M/2B 제한은 독립적이며, dense300쪽·8문구 pure control을 추가했다. 브리지의 부모 감시는 첫 탐지에서 timer를 지우고 controller를 중단해 반복 자기 SIGTERM이 finally를 끊지 않도록 한다. 감독기는 직접 자식 PID와 process group 변경도 검사하며, escaped-child OS control을 추가했다. reaped PID를 다시 kill하지 않는다. 파일 경로 비교는 symlink를 해소한다.

Directory-data 전역 예외를 없애는 추가 후보는 실제 native probe가 exit134로 실패하여 채택하지 않았다. 통과한 기존 디렉터리 메타데이터/열람 예외를 유지하며, 임의 경로의 파일 내용이 허용되는 것으로 확대하지 않는다. 이름·메타데이터/일부 process-info 허용과 손상된 seed 보존은 알려진 WATCH다. D 집중18검사는 통과했으며 새 전체·독립 리뷰·실제 앱·300쪽·강제종료/재시작·이동 ZIP은 각각 추가 검증이 필요하다.

## 무료 도구 판독·렌더 연구 · 2026-10-20

아래는 `.omx/artifacts/quality-loop-04/`의 별도 실험이다. OCR 후보를 제품 판독 경로에 채택하지 않았고 현재 검증 앱·ZIP을 보존했다. 후속 참고 미리보기 소스 구현은 아래에 별도로 구분한다. 이전 native45/helper26의 480개 원본 PNG 해시를 확인하고 같은 480개를 모두 남겨 비교했다. 후보 생성에는 정답·폰트 조건을 주지 않고, 정답을 읽는 평가는 별도 프로세스로 실행했다. 이 상관된 합성 자료를 일반 문서 정확도로 확대하지 않는다.

| 독립 후보 | 480개 문구 완전 일치 | 비어 있지 않은 오인식 | 기존 정답 218개 중 손실 | 기존 오독 22개 중 교정 |
| --- | ---: | ---: | ---: | ---: |
| GLM-OCR bf16 · 잉크 영역 crop | 297 | 183 | 59 | 14 |
| EasyOCR english_g2 · crop | 135 | 345 | 112 | 0 |
| EasyOCR latin_g2 · crop | 160 | 320 | 97 | 1 |
| EasyOCR korean_g2 · crop | 56 | 424 | 164 | 0 |

표는 공백까지 포함한 원문 문자열 일치다. 기존 NFC·공백 축약 평가에서 korean_g2는 60개 일치·420개 오인식이며, 이 차이를 숨기지 않는다. 위 네 후보는 480개에서 빈 결과가 0개였고, 모두 기존 정답 보존 기준을 실패했다. Latin/English 모델이 지원하지 않는 한글 96개도 분모에서 빼지 않는다. 엔진·문자 집합을 정답 조건에 따라 선택하는 정책은 만들지 않았다.

별도 Arial·Georgia·Courier New·Avenir Next, 두 크기, 깨끗한 영상/JPEG 열화 및 빈 화면·완전 가림 4개를 포함한 132개 대조군도 유지했다. GLM은 51개 일치·81개 오인식이고 빈 대조군 4개 모두 문구를 생성했다. EasyOCR의 원문 일치는 English42/Latin56/Korean53개, 오인식은 각각90/76/79개다. English·Latin은 빈 대조군 4개를 비웠고, Korean은 4개 모두 문자를 생성했다. 빈 대조군의 정답인 빈 출력은 일치 수에 이미 포함된다. 원문/공백 축약 수치, 지원하지 않는 문자 집합과 행별 평가 파일의 해시는 `easyocr/final-evaluation.json`에 남겼다. 개별 행은 같은 폴더의 `corpus480-evaluation.json`과 `controls132-evaluation.json`에 보존했다.

같은 모델의 I/l/i 후보 점수 재계산은 잔여 8개 중 교정 0개였다. 영상 연결 성분으로 글자를 나눈 실험은 480개 중 적격 0개여서 인식 자체를 실행하지 않았다. 별도 Vision 문자 상자 기반의 가설적 픽셀 조각/고정 순열 3개 실험은 이전 오독20개·정답16개를 실행했으나 교정0개였다. 세 순열이 같은 답에 동의한 8개 중 4개도 오답이었다. 같은 줄의 점 있는 i와 정확한 RGBA 글자 모양을 대조하는 실험도 후보0개였다. 보류·부적격을 해결로 계산하지 않는다. 같은 픽셀의 I/l 충돌이 발견되지 않았으므로 판독 불가능성이 증명된 것도 아니다.

OnlyOffice10.0.0.169는 공식 arm DMG의 해시·개발자 서명·공증 티켓을 확인하고 이 프로젝트의 연구 폴더에서만 사용했다. 공개 원본10개/독립 PowerPoint 기준26쪽에서 평균 RGB 채널 오차는 LibreOffice2.2618121944에서 OnlyOffice1.8239458250으로 감소했고, 24쪽은 개선·2쪽은 악화했다. 두 렌더러 모두 엄격 픽셀 동일성은0/26이다. startup2·3쪽의 그림자 회귀와 텍스트 영역3개의 불일치 표시가 남는다. 전체 요소 문자열 대조에서 나온8개 표시는 글머리표·줄바꿈의 영향도 있어8쪽의 내용 삭제로 분류하지 않는다.

OnlyOffice 실행 prototype은 공유 입력 검증·원본 복사·새0700폴더·네트워크/불필요한 읽기·쓰기/추가 fork·exec 제한·환경 분리·프로세스 그룹 취소를 적용했다. 파일별128MiB와 감독 프로세스·변환 자식 각각의 CPU90초는 OS 한도이며 총 작업 CPU/RSS 한도는 아니다. 전체256MiB는 표본 감시와 종료 후 검사에 의한 초과 거절 기준이다. 총 용량의 엄격한 상한으로 부르지 않는다(보존한 sparse 대조군은 거절 시300MiB). 감독 변환 호출의 wall120초와 stdout·stderr 각각1MiB 한도도 적용했다. 앞선 동기 입력 검증, 최대30초의 codesign 검사와 준비·복사는 이120초 밖이다. DirFD/nofollow 순회, 경로 밖 canary·외부 쓰기·네트워크·fork·exec·환경·파일/총 용량·symlink·로그·취소·timeout 대조군7개를 통과했다. 공개10개 변환과 기존 OnlyOffice 대비26쪽의 RGBA·텍스트 배치 동일성도 확인했다. 이는 PowerPoint 동등성이나 앱 배포 승인과 별개다.

이전 prototype의 오래된 출력 재사용 문제는 새 폴더를 강제해 독립 코드 리뷰의6개 mock으로 닫았다. 후속 v3 격리는 정확한 고정 snapshot에서 코드 APPROVE·아키텍처 WATCH로 연구 범위의 F2/B1을 닫았다. PDF/캐시 식별자, 폰트 생성·배포 조건, 숨김 슬라이드·소비자 연결은 canonical 렌더러 채택 게이트로 남는다. 현재 검증 앱이나 canonical report의 렌더러를 변경하지 않았다. Claude·Grok의 유효한 응답은 실험 설계 논의이며 새 OCR 결과/소스 승인이 아니다. Grok 제한은1200초로 주었고 Agy는 quota 오류(exit3/출력0)라 리뷰로 계산하지 않는다.

### source A 중간 기록 · 후속 네이티브 참고 미리보기

현재 소스에는 PDFKit의 선택적 OnlyOffice 참고 창을 추가했다. 고정 report/버전 occurrence/페이지/asset SHA를 검사하며 별도 UUID 작업·lease로 표시한다. 저장된 PageData·asset·raster·diff·MCP 결과에는 반영하지 않는다. 원문 전체에서 고유한 문구, 페이지 수·비율을 대조하고 숨김 슬라이드·모호한 연결은 거절한다. 화면은 추정임을 표시하며 근거 좌표를 덧씌우지 않는다. 창 닫기와 결과 생성이 겹쳐도 닫힌 작업이 다시 publish되지 않도록 marker 연결·정리를 분리했다.

Python 의존 없이 별도의 C 감독 도구를 사용하며 Vision helper의 빌드 fingerprint는 바꾸지 않았다. 네이티브 감독부에서 OS 대조군7개와 공개10개 변환을 통과했다. 실제 새 source 함수에서도10개/26쪽의 페이지 대응·원문 보존·임시 작업 정리를 확인했다. 포함 관계가 있는 정상 제목을 잘못 보류한 반례는 전체 원문 기준 고유 문구로 수정하고 합성 중첩 제목·페이지 교환 대조군을 추가했다. 집중7개 테스트·TypeScript 검사는 통과했다. 이는 전체 소스 독립 리뷰·새 앱·이동한 ZIP 검증을 대신하지 않는다.

선택적 provider는 외부의 서명된 OnlyOffice 앱을 지정하고 team·binary·CodeResources·버전·호스트 font inventory와 생성 metadata의 SHA를 확인한다. metadata는 실행하지 않고 JSON 값 대입만 허용한다. 생성된 metadata에는 사용자 설치 글꼴 경로도 포함되며 시스템 전용 목록으로 부르지 않는다. 앱·font indexer·폰트 프로그램은 번들하지 않고 provider JSON과 두 metadata 파일만 allowlist로 복사한다. 이 Mac의 private build 구성으로, 다른 Mac의 준비·배포·라이선스 검증을 완료한 것이 아니다.

## 구현한 경로

- PDFKit 원본 화면과 독립적인 원문/글자 표시 관측. 같은 native 화면의 원문층 차이는 숫자 수정으로 만들지 않는다.
- 한글/영어 Vision OCR, 겹치는 타일과 숫자 재인식, 원문층/이전 invisible OCR층/새 OCR 분리, 추정·낮은 점수·대안·좌표 보존.
- OCR 영역 누락을 삭제로 단정하지 않음. 읽을 수 있는 숫자 영역은 부분 비교. 스캔된 취소선은 픽셀 후보로 추정하고 밑줄과 구별.
- macOS26+의 표 구조 인식: 행·열·병합 범위와 화면 좌표. OOXML 셀, PDF 격자 추정, 화면 OCR 셀을 구별.
- 번들 LibreOffice 실제 PPTX PDF 렌더, 한글 fontconfig, 숨김 슬라이드 포함, 페이지 수·비율 검증, missing-font/원문 불일치 경고, 같은 버전 원본 PDF 우선 표시.
- 512MiB 입력 상한, 16쪽 native batch, 같은 픽셀 OCR 재사용, 트랜잭션 내 개별 페이지 인덱스와 stream source hash. 높은 밀도 자료의 다른 메모리 경로는 계속 측정한다.

## 재현 명령

```sh
npm run check
npm run mac:build
node scripts/native-backend-smoke.mjs
node scripts/native-smoke.mjs
node scripts/native-smoke.mjs --scale
npx tsx scripts/prepare-scan-scale.ts 300
node scripts/native-smoke.mjs --scan-scale
npx tsx scripts/verify-office-reference.ts
```

OCR·렌더·MCP 회귀 테스트가 통과한 체크포인트가 있다. 최종 합격과 패키지 판정은 `.omx/artifacts/`의 정확한 base/head/patch 해시와 원문 리뷰, `release/validation.json`으로 따로 고정한다. 이후 수정이 생기면 이전 승인으로 대체하지 않는다. native smoke는 실제 앱의 모델과 화면을 실행하며 OS 입력 자동화를 대신하지 않는다.

## PowerPoint 독립 참조

공개 합성 업무 자료 10개 덱, 26쪽의 원본 PPTX와 PowerPoint PDF를 사용한다. [upstream manifest](https://github.com/developer0hye/office2pdf/blob/faeca2bc29598744a62f787076d9e340e5095b8b/tests/golden_mocks/business/manifest.json)의 source/PDF SHA-256을 검증한다. upstream은 Microsoft PowerPoint16.111.1, macOS26.5.2의 독립 export라고 기록했다. 이 환경에서 PowerPoint를 직접 실행한 것으로 주장하지 않는다. 자료는 `output/office-reference/` 검증 캐시에만 두며 제품/소스 배포에 추가하지 않는다.

초기 측정은 1440×810에서 RGB 채널 차이 24를 넘는 픽셀 비율이 페이지에 따라 최대 약 1.0~3.9%였다. 이는 **96~99% 정확도라는 뜻이 아니며, 엄격한 픽셀 동일성은 통과하지 못했다.** 일부 참조의 Malgun Gothic은 현재 Mac에 없어 폰트 대체 경고가 나온다. 효과·텍스트 배치 등 렌더러 차이도 남아 있다. 전체 수치·페이지 이미지·출처는 `output/office-reference/result.json`과 provenance에 남긴다. 합성 PDFKit 기준 화면을 PowerPoint의 정답으로 취급하지 않는다.

사용자가 공개 샘플로 진행하도록 위임했다. 위 macOS PowerPoint16.111.1 export를 현재 독립 기준으로 선택하고, 다른 운영체제/버전과의 동일성으로 넓히지 않는다. 정확한 원본 PDF가 제공되는 경우에는 확인된 bundle 대응을 통해 그 바이트를 그대로 표시한다. PPTX 단독 변환의 모든 환경·폰트·특수 개체를 보증한 것으로 넓히지 않는다.

## 완료 전 합격 게이트

| 항목 | 상태 |
| --- | --- |
| 로컬 한글/영어·숫자·부호 OCR와 추정 근거 | 구현 및 실제 helper 테스트 통과 |
| 취소선/가림·OCR 누락·동일 화면 오판 방지 | 구현 및 재현 테스트 통과 |
| 회전/CropBox 좌표·스캔 표 행/열 | 현재 Mac 실제 helper 테스트 통과 |
| PPTX 실제 렌더·한글·숨김 슬라이드 | 구현 및 실제 변환 테스트 통과 |
| 300쪽 스캔 PDF×2의 실제 앱 작업 | 이전 V fresh600 스캔 분석 통과; AL은 그 보고서 재열기 통과. 새 AL 스캔 분석 시간으로 재분류하지 않음 |
| 새 번들/이동한 ZIP/읽기 전용 MCP | F clean source Docver-MCP 앱과 정확한 mcp1 ZIP에서 통과; 위 고정 증거 참조 |
| 최종 full-diff 독립 코드/아키텍처 리뷰 | F의 원래 base부터 전체17경로 코드 APPROVE/READY·아키텍처 WATCH/SOURCE_READY; 후속 문서 변경은 별도 범위 |
| 목표 PowerPoint 환경의 픽셀 동일성 | 선택한 macOS PowerPoint 기준 미통과 |
| 다양한 실제 문서·스캔 열화/언어·특수 PDF | corpus 확장 필요 |

복잡하거나 손상된 문서에서 인식 불가/보류를 숨기지 않으며, 파일을 읽었다는 사실과 텍스트/의미를 정확히 이해했다는 주장을 구별한다. 공증·다른 장비/최소 OS·프로젝트 공개 라이선스는 판독 품질과 별개의 배포 게이트다.

## 추가 공개 corpus

사용자 위임으로 W3C OCR 예제, Microsoft Azure 문서 분석 샘플, Mozilla의 일반 학술 예제, python-pptx의 표/그룹/차트/도형/텍스트 샘플을 받았다. 여기에 독립 PowerPoint 참조의 한국어 분기 보고/보안 교육 PDF도 포함했다. 총7개 PDF와5개 PPTX이며 출처/고정commit/바이트 SHA/수동 active-content 검사 결과는 `docs/fixtures/public-corpus.json`에 기록했다. 업무 자료는 공개된 허구의 합성 예제다. 표준 printerSettings.bin은 인쇄 설정 데이터이며 실행 파일이나 매크로로 분류하지 않는다. 이는 모든 파서 취약점이 없다는 인증은 아니다. 자료는 `output/public-corpus/` 로컬 검증 캐시에만 저장하며 원격 코드나 클라우드 판독은 실행하지 않는다.

```sh
npm run corpus:public -- --download
```

수동으로 본 선택 영역은 `docs/fixtures/public-corpus-truth.json`에 별도로 기록했다. W3C의 기존 OCR층은 정답에서 제외한다. 화면의⅛과 기존 OCR층의¼가 다른 사례를 보존한다. 선택 문구의 인식 결과와 전체 문서 정확도는 구별한다. 숫자/글자 혼동(Foo/F00 등)과 낮은 점수는 실패 또는 보류로 남긴다. 이미지 PDF의 저해상도 변형은 실제 앱처럼 PDFKit에서 다시 렌더링되며, 입력 픽셀·유효DPI·재렌더 픽셀과 정방향 좌표 변환을 기록한다.

공개 PPTX 양성 대조군은 살아 있는 OOXML 텍스트 요소 안의 교체·삽입·문자 제거를 검사한다. 요소 전체 삭제나 모든 문서의 변경 재현율을 측정한 것이 아니다. 벡터 원문의 격자 연관은 원문 text 관측으로, 래스터 격자 셀은 별도 inferred table_cell 관측으로 남기며 method와 provenance를 유지한다. 빈 셀은 값이 관측되지 않은 상태다. 검출 가능한 진하고 연속된 부분 구분선이 있으면 정형 격자 복원을 보류한다. 흐리거나 점선인 내부 경계는 놓쳐 행/열을 더 적게 추정할 수 있으므로 화면 확인이 필요하다.

Microsoft의 작은3×3 표를 Vision 문서 구조 인식이 놓치는 사례에 대응해 완전히 닫힌 격자의 보조 추정을 추가했다. 빈 셀은 좌표를 유지하되 값이 관측됐다고 단정하지 않는다. 검출된 진하고 연속된 부분 테두리/병합 경계가 있으면 복원을 보류한다. 흐린 선·점선의 모든 병합 경계를 검출한다는 보증은 아니다. 표 셀은 `pdf_grid_inferred`, OCR 값은 계속 추정/보류로 표시하며 기존 원문을 바꾸지 않는다. 같은 숫자 두 개는 위치별 양방향1:1 검증을 요구하고, 겹친 타일의 같은 판독은 중복 제거하되 다른 판독은 불일치로 남긴다. grayscale8bit 취소선과 밑줄도 구별하며 지원되지 않는 형식/너무 작은 영역을 단순히 취소선 없음으로 숨기지 않는다.

## 반복 보완2

엔진10의 혼합 영역 비교는 확실한 원문을 페이지 전체 OCR로 덮어쓰지 않는다. 원문/추정 선택·보류·참고 역할은 별도 관측 필드이고 원문 텍스트·가시성·OCR 주 판독/대안을 보존한다. 혼합 상태를 가로지르는 OCR 행이나 가림/부분 취소선은 통째로 보류한다. 표의 미검출과 검출불가/예산/미확정 경계도 구분한다. 약한 경계 대조군 통과는 모든 희미한 표를 복원했다는 뜻이 아니다.

읽기 순서만 달라진 OCR의 의미 수정은 완전한 문구/좌표 일대일 검사를 통과한 경우에만 제외하고, 화면 차이와 순서 공백을 남긴다. 직전 앱 엔진9 구간 재현도 고정 kernel로 유지한다. 진행/재현/최종 검증은 `.omx/artifacts/quality-loop-02/`에 기록하며 이 절을 전체 제품 완료 판정으로 쓰지 않는다.

반복2의 첫 독립 재리뷰는 승인되지 않았다. 부분 원문 범위를 통째로 shadow 처리하는 문제, uncertain 상태 아래 가려진 글자, 원문만 선택된 혼합 페이지의 거짓 순서 수정, 혼합 KPI 순서와 회색 표 배경 오인이 재현됐다. 엔진11에서 수정하고 실제 글자 가림 PDF·부분 판독 음성 대조군·독립 숫자 영역 양성 대조군·회색/교차 셀 배경/실제 글자 표·각 격자 예산 대조군으로 검사한다. 이 수정의 최종 리뷰와 제품 전체 완료는 별도로 판정한다.

엔진13은 분리된 원문 사이의 이미지 숫자를 큰 외곽 사각형으로 덮어 보지 않는다. 실제 영역 합집합과 내부 빈틈·L형 빈틈·연산 한도를 검사하며, 바깥 OCR 경계 오차 허용치를 내부 소수점 빈틈에 적용하지 않는다. 원문이 확실한 영역의 숫자/관측 취소선은 다른 미확인 OCR 때문에 사라지지 않게 별도 영역 비교한다.

공개 Azure 표의 작은 Foo는 글꼴 여백만 셀 clip 밖에 나가 원문 판독이 보류된 사례였다. 고정 PDF.js의 실제 loaded glyph outline이 알려진 직사각형 clip 안에 완전히 들어오는 경우에만 빈 여백과 잉크를 구별한다. 실제 잉크를 자른 대조군은 보류하고, 빈 여백만 자른 PDF는 원래 PDF와 실제 PDFKit 화면 해시가 같은지 검사한다. 지원되지 않는 폰트/그래픽 상태는 그대로 보류한다. OCR의 F00 주 판독을 Foo로 치환하거나 점수를 올린 것이 아니다. 공개 corpus는 주 OCR 점수와 선택된 비교 근거의 관측/추정을 따로 기록한다.

PowerPoint 글머리표 폰트 실험은 원본/참조를 보존한 파생 사본으로 수행한다. conference2쪽의 전체 화면 차이 비율은0.03121999→0.03112740으로 소폭 줄었지만 기준은 여전히 실패다. 직접 run font만으로 실제 상속된 bullet font를 일반적으로 확정할 수 없으므로 이 실험을 제품의 자동 보정으로 적용하지 않는다. 원본과의 충실도는 계속 별도 게이트다.

엔진14는 클립 외곽선 증명을 문서에 실제 포함된 글꼴 프로그램으로 제한한다. 미포함 Helvetica의 대체 외곽선과 실제 PDFKit 픽셀 차이를 음성 대조군으로 유지한다. 포함된 LiberationSans의 빈 여백/인접 줄은 실제 픽셀 동일성을 확인하며, 잉크 절단은 보류한다. OCR의 문구가 다른 경우 완전한 원문 사각형도 중복 판독의 증명이 아니므로 한 요소 내부 이미지 숫자가 사라지지 않게 한다. 전체102개 검사의 범위와 제품 전체 완료는 구분한다.

엔진15/helper11은 인접 줄의 글꼴 여백과 분리된 OCR 조각을 실제 대상 glyph 중심으로 대조한다. 전체 source 문자열은 유지하고, target 문자 일치와 union coverage를 모두 요구한다. 지원되는 완전한 분수는 위치별 한 숫자 항목으로 검증하며 단위·부호·분모·항목 수 차이는 보류한다. 원문 OCR/대안/신뢰도는 바꾸지 않는다. 공개 W3C의 분수4행이 실제 교차검증을 통과했고, 합성1/2→1/4 스캔은 추정 변경으로 기록된다. AppleGothic½의 낮은 행 신뢰도 사례는 여전히 보류하며, 다른 글꼴의 conflicted 결과도 실패 artifact에 보존한다. 숫자 검증만으로 전체 행 신뢰도를 올리지 않는다.

엔진16/helper13에서는 불완전 분수1/,/2를 숫자 검증에 통과시키지 않는다. 추정 비교도 분수/정수 종류를 구분해1/2→12 같은 슬래시 유실을 값 수정으로 확정하지 않는다. 원문 요소 안의 혼합 글자 크기·RTL 순서는 보존하고, 서로 다른 요소의 배치 추정과 구분한다. UserUnit 배율이 있는 실제 PDF에서 PDF.js/PDFKit 크기 차이를 재현해 최소 네이티브 픽셀 여유를 보수적으로 유지한다. 정상 글꼴 여백의 실제 화면 동일성, 한 픽셀보다 작은 여유의 보류, 분모·부호·단위·분리/합쳐진 숫자·불완전 표기 대조군을 함께 유지한다.

엔진17/helper14는 숫자 토큰 범위로 슬래시를 분류하고 부호·분수·소수점으로 시작하는 분자 누락도 보류한다. 통화 기호를 가진 정상 숫자 목록은 유지하며, 보이지 않는 서식 문자·미지원 분수 기호·숫자 결합 문자의 Swift/TypeScript 판정은 공유 사례집으로 대조한다. 실제 Vision OCR이 읽은 `/2`, `1/ cup`, `/+2` 줄에서 unsupported_notation 및 numeric_consensus=false를 확인한다. 숫자 꼬리 경로/URL과 복잡한 요소 간 읽기 순서는 여전히 보수적 보류 대상이다.

엔진18/helper15는 전각/대시 부호와 보이지 않는 한글 채움 문자의 우회를 재현해 양쪽 숫자 인접성을 보완했다. Unicode 기본 무시 문자·비공백 제어 문자는 보류하고 공백 속성/전각 마이너스 정규화는 두 언어가 공유한다. 90사례에는 보수적으로 지원하지 않는 소수 비율·문자숫자 슬래시 라벨·ISO 코드 접두 목록도 음성 대조군으로 기록한다. 실제 OCR 세 행은 형태별 원문을 대조한다.

엔진19/helper16은 한국어/복합 단위 뒤 기호의 언어별 차이를 숫자 줄의 명시적 슬래시 허용 문법으로 닫는다. 단위를 값이나 마스킹 패턴에 흡수하지 않으며, 분수·날짜·명시적 목록·붙은 문자 단위 이외 표기는 검증을 보류한다. 공통131사례에는 원/만/억/만원/USD/%와 여러 기호 조합, 정상 단위 목록, 전체·지역 추정 변경 음성 대조군이 포함된다. 숫자와 함께 있는 URL·미지원 슬래시 표현은 보수적인 판독 한계다.

엔진20/helper17은 분자의 소수 일부·분모의 연속 숫자/소수/그룹 일부를 정수 분수로 인정하지 않는다. 공통170사례와 전체·지역 변경 음성 대조군, 정상 분수의 문장부호/목록/날짜 양성 대조군을 유지한다. 부분 숫자만 잘라 검증을 통과시키지 않으며 OCR 원문은 보존한다.

`.5`를 원문 그대로 한 숫자 항목으로 검증하고 독립 `5` 판독은 충돌로 처리한다. `.5/2`는 미지원 비율, `.5 / 2`는 명시적 두 항목 목록이며 실제 수식 의미는 추정하지 않는다. 초기 경계 검사의 목록/비율 기대 오류는 실패 로그로 보존했다.

## native53 working qualification

Canonical0.4.0-native.bundle.53/schema0.4.0 adds same-version manual provided-PDF association without changing helper26 OCR decisions. Raw automatic baseline and exact append-only displaced pair replay reject missing/invented history and resurrected inferred pairs. The actual asset extraction must reproduce the baseline; merely rehashing a forged record does not pass engine validation. Current source/target authority remains independent and inferred with respect to PPTX fidelity.

Focused core/native action/reference18PASS13093.184209ms; additional partial/reused-PDF conversion plus immutable51golden16PASS9553.989375ms. The latter includes real partial-bundle LO conversion on unreferenced source slides and raw target/source preservation. Historical44/45/50/51 complete event/ID/get_evidence bytes stay exact for all recorded selector combinations. Current strict Swift0warnings. Full200check running; actual clean53 app, new visual review and relocation remain pending. Old52 qualification does not qualify new53 runtime.

Early independent WIP reviews caught the context-key failure, missing warning consumer and two decision-history validation counterexamples; fixes have focused tests and separate narrow repair evidence. They are not frozen53 full-base readiness verdicts. Full OS-input/VoiceOver/minimum OS/notarization, universal OCR and PowerPoint equivalence remain open.

- Revised53b strict Swift PASS0warnings2.489189708s and full200/200PASS0fail/skip/cancel151422.553625ms. All runtime/test/fixture sources unchanged during verification. After the suite only App smoke and its driver added p240/large-bundle capture and robust MCP cursor traversal; canonical production/engine/query/schema/desktop/models/tests/fixtures remain byte-identical. Exact delta and strict/type checks are recorded in native53-post-suite-delta.json; the new packaged scenarios still require actual execution.

- Clean53r34211 app passed reference/import, native same-version link/unlink/relink + history/MCP/second-process reopen, manual timeline relations and backend jobs; remaining serial jobs still running. The initial802 bundle native actions succeeded but its driver failed after MCP metadata summary omitted a field; fixed explicit8000budget and truncation check. Independent code review then found LOW newtool ambiguous revision aliases; repaired only list_bundle_decisions with AMBIGUOUS_REVISION plus a two-occurrence/two-decision regression. Canonical event generation/archived query behavior unchanged. Full53q requalification follows; no universal/product completion claim.

- Revised53q complete201/201PASS0fail/skip/cancel (native53q-full-check.txt); strict Swift warnings-as-errors PASS0warnings2.467238125s. Full runtime/test/fixture bytes unchanged during the run. Includes exact occurrence vs ambiguous new-tool alias controls; BundleSheet source preview now preserves page aspect ratio when fitting a short pane. Frozen53r actual7jobs allPASS:reference13.313411959s/bundle26.674570917s/manual21.736546042s/backend13.700576s/five15.954355917s/600UIreopen11.956779917s/900UIreopen13.114444125s. These do not qualify53q; new clean53q app/scale/ZIP follow.

- Post-review53q readiness superseded: both lanes reproduced a public Manifest derived-score inconsistency after score+ID rehash; parent repairs this with exact shared pure similarity validation at schema replay and apply plus real engine rejection controls. Thin/wide/subpoint structure previews use a shared finite-positive fit with actual Swift controls. New source helper imports schema only as a type; historical matching primitives remain byte-equivalent. Targeted19PASS11126.805875ms; full202 now running on fixed source/test/fixture bytes.
- Claude actual53q five-image review VALID REQUEST_CHANGES (prompt eaa6ea7489f16c1e6492cd2abd215741b7c1ee561ac7f8a9bdcce2b60000ad7b): prior52 page sets/optional input/vN fixes visually confirmed. Adopt explicit prior→proposed pair and oldest-first/current-state clarity. Preserve user-provided reason whitespace/emoji; it is data, not a built-in status marker. The apparently differing PDF state came from first-link versus after-relink captures; label stages explicitly rather than rewriting correct chronological history.

- Revised53s full202/202PASS0fail/skip/cancel155631.530167ms (wrapper156.3577765s), strict Swift0warnings2.494824792s, source/test/fixture bytes unchanged. Includes actual engine forged-score rejection and exact partial-score controls, historical44/45/50/51 replay, all positive aspect-fit controls. After suite only BundleSheet history/copy/current-state UI and App capture harness changed: explicit prior→proposed pair, same-pair reason-only confirmation, oldest-first label, current active decision tag, and neutral reason labels preserving verbatim user whitespace/emoji. Late UI strict/native controls and actual clean53s app requalification follow; no whole-product completion claim.

- Frozen53s firstreference13.509514083s and nativebundle27.924665041s PASS; new actual aspect job FAILED relative0.1% guard. Dirty diagnostic actualapp reproduced source1270000×25400000 / canvas35×704: mathematical fit35.2pt snapped35pt by AppKit. Retain failure; noS ZIP. Final53t actual guard measures shorter-axis absolute error within one backing pixel, records source/display/backing scale/error/tolerance, still rejects zero/nonfinite/out-of-tolerance dimensions. Only smoke/driver and documentation changed; production fit/core stays exact53s. New clean53t build/all8actualjobs required.

- Frozen53t actualreference13.252711084s/nativebundle27.632549042s PASS; aspect absolute-error guard passed but cardinality failed ASPECT_FIXTURE because auto-selected firstchange was one-sided. Preserve T failure, noT ZIP. The harness now explicitly selects both primary pages through production navigatePage, waits for payloads and records actual bounds/capture before cardinality checks. No absent-side product behavior, core, fit or test sources changed. Clean53u aspect-first/all8 native qualification required.

- Frozen53u actual aspectPASS12.468234584s: mainthin35×704/wide696×35 each0.2pt residual, bundle14×2730.35pt residual; scale2 tolerance0.5pt. Actual reference/bundle/manual/backend also PASS; remaining3jobs running. Parent inspected original PNGs and found history hosting-view capture background transparent (native cacheDisplay excludes window background), hiding black header/caption in black-alpha viewers. Explicit native history windowBackgroundColor will produce opaque actual view/capture; no post-capture image editing or invented pixels. This UI-only background delta requires new clean53v capture/visual closure.

- Frozen53u completed all8actualjobs with exact app hashes preserved: aspect12.468234584s431.046875MiB/reference10.016308208s462.359375/bundle27.091739083s777.21875/manual22.177762917s836.3125/backend13.964682208s473.0625/five15.996589542s536.828125/600UIreopen11.759258375s580.28125/900UIreopen13.31903225s574.578125. Reopen uses own51fresh reports, not new53analysis latency. Native programmatic model/actions/views, no OSinput claim. One history background UI-only delta now proceeds as53v; full202 core/tests remain exact apart from ignored generated fixture metadata regenerated during macbuild.

- Frozen53v all8actualnativejobs PASS with unchanged app hashes. Independent complete150path reviews codeAPPROVE/READY and architectureWATCH/SOURCE_READY; no unresolved source blocker, product/visual/release separate. Claude7actualcapture review VALID REQUEST_CHANGES prompt0582f2a0df7260de733dbbc98bf4f69b48e219025256eb7b6e1609a53277ff9d: priorpair/reason/history clarity closed; thin/wide structure page edges invisible against white, and trailing unverified caption runs toward PDF column. Working53w adds neutral one-device-pixel page outline, light contrasting native preview wells and left-aligned caption below its own header. Only2native styling files advance; full202 core/test/helper/backend bytes exact. Fresh V600/900+1200rawbundle stay artifact-bound V results, never relabeled W fresh latency; W will reopen copied freshV reports and requalify exact new styling. Grok score review emptytimeout180s/124INVALID207a2c60df2c6e747d0239602918b4acf8fd55c538f5225bfd8770739ad585c3; no new approval/retry. Agy priorquota429 unchanged.

- FrozenV fresh600scan PASS272.388379708s1200.640625MiB and900mixed PASS61.628088709s1271.859375MiB, one-run driver-tree1s samples. V1200rawbundle workflow FAILED66.402601167s1455.515625MiB at p240auto-pair test setup: all600raw pages loaded, automaticmapping246/300,54 correctly needs_review because 48hex digests share many masked-digit bigrams. Failed artifacts/first immutable report retained; no large-workflow successclaim. Pure unchangedmatcher probe reproduces246+54, while new deterministic48letter labels yield300inferred correctreversepairs, eachscore1,0needs_review; do not relax matcher. Only large syntheticdriver text changes; large-only watchdog600s (small180s unchanged) bounds complete4analysis/manual-history workload without asserting latency. X actual large and new UI compile/build/review/capture/ZIP remain required; W strict0warnings2.460769125s/tsc.250409917s alreadyPASS.

- ExactX large1200rawpages fullworkflow PASS97.61797425s1275.421875MiB; all9nativejobs PASS, including copiedV600/900 and ownX1200immutable-report p240reopen. ClaudeX7actualPNG VALID REQUEST_CHANGES (7da12dc3b3adfbc01ef7bce645bb62d5ebda101da05de8c192fa15bec1136204): neutraledges/wells/own-column caption improved; adopt shared20ptlist/previewgutter and actualfontlineheight-fit to preventtitleclip. Blue2pt border is existing selected-evidence overlay drawn last, intentionally preserved; aspectfixture now deselects only for neutraledge inspection. No removed production highlight.
- Y readonlyhistory performance probe at exactX source:10k same-pair entries×32768text, baseline28460.175667ms versus per-replay pairscorecache candidate59.24775ms;256text292.556458→56.452791ms,8192text7047.498458→57.226166ms. One-run component-only, not fullnative/create/p95 guarantee. Candidate keeps schemahash/valid-chain/rehashed-forgery rejection. Cache localtoone replay and keyed by both Page objects, releases aftercall; new regression checks distinct targets and0→1 observation mutation acrosscalls/restoration. Firsttestbad0→0data failed, parent stopped onlyowned failing suite descendants71.590915083s(-15), allsourcebytesfixed; failure/invalidfull preserved. Corrected3focusedtestsPASS, fresh203strict/full fixed-source run nowinprogress. WholeJSON/history/availability/platform/OCR/fidelity watches remainOPEN.

- RevisedY2 complete203/203PASS0fail/skip/cancel151324.260958ms (wrapper152.028054666s), strictSwift0warnings2.498380583s. Runtime/test/fixture bytes fixed before/after; firstbadtest/incomplete203run retained separately. Includes per-call paircache isolation/target-key mutation regression, derived-score forgery controls, actual partialbundle engine rejection and historical44/45/50/51 events/IDs/evidence. Cache changes validation work only, no canonical score/schema shape/engine semantics; fullbase immutableYreview and actualnewapp/visual/ZIP required next. Font fitting removes prior floor and fits explicit line-height; general wrapped text/source typography remain schematic limits.

- FrozenY all9actualjobsPASS exact app hashes: aspect12.802736959s/reference10.204428291s/bundle26.612363792s/manual22.165165917s/backend13.746777s/five15.640592667s/600UIreopen12.177037458s/900UIreopen13.597348958s/1200UIreopen15.184787292s. Source lanes codeAPPROVE/READY, architectureWATCH/SOURCE_READY full150. ClaudeY7staticcapture VALID REQUEST_CHANGES648a73ec12084e26b6926a67b8aa54501c52fca00719a874350b81bedeb1e667 confirms neutraledges/glyphclip/horizontalgutter closure, requests equalcaptionheight and page inset. Z reserves2captionlines and8ptstructurecanvas inset; actualSwiftfit/inset controls rejectnegative/nonfinite/exhaustedbounds. Mainhighlight remains unchanged. Extreme1:20 full-fit text physicallytiny is optionallegibilitywatch with existingzoom/title/rawtext paths, not inventedcontent or distortion. Only4SwiftUI/test paths advance afterY203; exactTSengine/schema/cache/helpers unchanged. Strict/targetednative controls and cleanZactual9jobs/visual/ZIP required.


### native53 Z exact qualification; next source-order repair

- Clean `3c4057fe9a23ecfdc7191bd33345e81081fd4485` passed all9 serial actual-app scenarios, including exact copied600/900/1200page reports reopened without modifying their bodies. Native53z strict0warnings and actual Swift fit controls cover the late4Swift delta after Y203; Y203 is not relabeled as a full Z rerun. Full150path independent reviews: code APPROVE/sourceREADY; architecture WATCH/SOURCE_READY.
- Claude7actual-capture visual review returned valid APPROVE (prompt `d966ba34d6027e53a81ef11f49f585cddcb27637bbd241f32535bcf29c25ef6f`). Equal caption footprints and inset outlined structure pages are visibly corrected. PDFKit/structure fit-margin consistency, tiny extreme-aspect text and the empty-state hierarchy remain nonblocking limits, not whole-product approval.
- Z ZIP `release/Docver-0.4.0-native53-arm64.zip`:390490790bytes, SHA256 `a38c5538ad99bae5d6eb3ee803d5cffed61881665d6985139ea600578d8197f8`. Source/vendor strict signatures and relocation into a path with spaces passed; fresh five-version analysis, bundled backend8checks, reference/import guards and native bundle/history/MCP/second-process reopen passed. Exact composite: `.omx/artifacts/quality-loop-03/native53z-composite-qualification.json`. Generic release validation now points to Z. This does not qualify later source changes.
- One additional prespecified OCR arm downsampled all480actual PDFKit renders to1/3 and verified each render SHA against frozen native45. Raw candidate198correct/184wrong/98empty;68prior-correct losses despite47empty recoveries and1wrong repair;10false agreements. Rejected for production, originals/observations preserved in `ocr-downsample-53z/`. The initial generator-PNG hash mismatch was caught before recognition; the revised probe used actual PDF render only. Current218correct/22wrong/240empty canonical baseline unchanged.
- CUA native pipe startup failed; read-only OS permission preflight returned accessibility/post-event/screen-capture false. No permission request or setting change. Programmatic production actions/rendered native views are validated; actual OS input remains unqualified.
- Further source inspection reproduced a real PPTX raw-text defect: `Before [date] after` became `Before after[date]` and soft line breaks disappeared. Working repair correlates ordered XML to actual paragraph objects by per-parent/tag occurrence, preserves run/field/break and sp/table/sp source order, notes paragraphs/empty lines, single entity decoding and literal CDATA. Missing object paragraph correlation fails explicitly. Fourfocused regressions and tsc passed; strict/full207, focused Claude/Grok and independent source review follow. No visual rendering or complete PowerPoint equivalence claim.
- `drawingml-ordered-paragraphs-v2` is included in `observation_environment` before report hashing. Matching/diff/query/replay/schema/helper remain unchanged, so engine53/schema0.4 remain appropriate; the independent architecture note records this boundary. Old reports retain stored observations. A changed extraction that invalidates an append-only bundle basis still fails `BUNDLE_HISTORY`, without silently rebasing scores/history; review the prior report or import the same originals into a new project. Product completion remains OPEN.


- Ordered-PPTX review loop: initial207PASS/strict0warnings; follow-up210PASS and212PASS on separately bound intermediate bytes are preserved, not promoted to the latest source. Independent reviews reproduced empty-drawing omission, false XML_DEPTH for shallow CDATA containing literal tags, and false XML_DTD for literal declarations in CDATA/comments/PIs. Corrected all three while retaining actual declaration rejection. The existing parser already defaulted to maxNestedTags100; there was no demonstrated unlimited-depth bypass.
- Claude then requested changes for quadratic pre-validation regex scanning. Frozen actual extractor1MB malformedtag/comment probes each hit a2s child deadline; validation-first repaired those forms, but the pinned validator also accepts raw< in quotedattributes. Replaced all lexical strip/depth regexes with a single forward cursor scanner. Each comment/CDATA/PI region is consumed once; raw< inside tags/attributes is rejected, actualDTD/entities are blocked, and depth101 is rejected before the validator allocates a deep stack. Original XML bytes still go to validation/parsers. Explicit100-level parser and recursive-walk guards remain. Parser exceptions have typed diagnostics.
- Ninefocused regressions passed, including mixed/all-empty drawing parents, exact100accept/101reject, literalmarkup/quoted>/encoded&lt; positives, and six approximately1MB invalid-or-excess-depth inputs in one isolated5s child (165.455417ms including startup). Two source scopes may reuse an observationID; actual Store save/reopen/query retrieves the correct old/new text by explicit reportID and preserves old report bodies. Stale bundle scores remain rejected; recovery wording states verification failure without guessing its cause or transferring history.
- New fixed-source AF full212/strict, clean source review, ownfield/table/notes actual native fresh/reopen, fresh900mixed analysis, nine other native scenarios and separate text-v2 ZIP qualification are pending. Prior Z ZIP remains separately qualified. No new dependency, XML data rewrite, schema shape, helper, matching/diff/query kernel or engine-version change. Universal OCR/PowerPoint fidelity and platform gates remain OPEN; UTF-16 XML parts and strict XML Char-reference validation remain known pre-existing parser limits for a later bounded pass.

- Final AF fixed-source strict Swift PASS0warnings2.517261875s and full212/212PASS0fail/skip/cancel151760.376667ms (wrapper152.489329084s). Runtime/test/fixture hashes are identical before/after. Claude full4file linear-scanner review APPROVE (89f4f76b920868262d71161b2341e778dd3e9ac87dadd7454415c85cdfe97f92), followed by exact guard-first/deep-case delta APPROVE (cca2b81d41ecb6a0f041f410e2f878dab75d9d174aff1e17b20691aeda904326); the latter conditional full-suite gate is now satisfied. Earlier REQUEST_CHANGES evidence remains retained. Independent code scanner closure found no further defect with6parser/12attribute/4declaration controls; it is not yet complete151path readiness.
- New Grok ordered-source request timed out120s/124 with empty stdout/stderr (b0694ec3a5d6c55716d5751ce8d47a514891a5dd026e2a2cc2a95fbbb8464e7f): invalid review, no approval credited or same-scope retry. Agy remains quota-unavailable. Clean151path final source review and actual native text-v2/900page/remaining9jobs/relocatedZIP still require execution; source gates alone do not qualify the app.


### 2026-10-20 native53 AF actual qualification and Unicode source repair

- AF clean `da3249d6d5e253796d6d3b750f30ffff02d42a52` completed all11serial actual-app jobs with8app-file hashes fixed and synthetic inputs unchanged: ordered-source15.768468792s/398.703125MiB; fresh900mixed62.597974666s/1302.53125MiB; aspect8.862467542s/611.96875MiB; reference/import9.858219584s/437.59375MiB; bundle26.763814959s/882.328125MiB; manual21.469989959s/707.703125MiB; backend13.756230375s/450.6875MiB; five16.062975792s/542.75MiB; copied600/900/1200reopen12.302590709/13.3715155/15.150465875s and564.03125/728.28125/619.453125MiB. Driver-owned1s samples, one run only. The one-slide actual app retains exact raw fields/table/notes/export and second-process report bodies; dynamic date-field rendering is not the stored raw value or an independent PowerPoint reference.
- Independent full151path AF code APPROVE/sourceREADY (report SHA b5b3052e47dce09552e4b29eb408b98ee1a69c57e853d68f323f4dca36af0f1b), architecture WATCH/SOURCE_READY with original-base coverage and old/new immutable-report/query controls. AF app evidence is separate from source readiness. AF was not archived as a new ZIP because the next bounded Unicode repair followed immediately; qualified Z ZIP remains preserved.
- Next own source controls reproduce BOM-marked UTF16LE/BE wrongly rejected XML_DEPTH, invalid UTF8 silently changed to U+FFFD, and XML1.0-forbidden raw/reference U+0001 accepted. Working Unicode repair uses fatal BOM-selected UTF8/UTF16 decoding, declared-encoding agreement, raw XML Char checks, and actual numeric-reference checks in markup/text while preserving literal CDATA/comment/PI strings. Ingest policy advances to `drawingml-ordered-paragraphs-v3-unicode`, hash-bound through the existing environment. No XML byte rewrite, dependency, engine/schema/matching/diff/query/helper/Swift change.
- All13focused parser/history/query tests pass, including6BOM/declaration combinations across XML+rels, malformed encoding, legal/forbidden character boundaries and original bounded XML scanner cases. Source5control evidence initially reused input paths during candidate execution and changed ZIP timestamps; original byte streams were restored only after equality with every originally recorded SHA256. Baseline results stay unchanged, candidate copies are now separate, and exact-original5control recheck passes; the bookkeeping note is retained in pptx-encoding/. Strict/full216, Claude Unicode review and actual new native/ZIP qualification remain pending.

- Unicode AG fixed-source strict Swift PASS0warnings2.5527785s and complete216/216PASS0fail/skip/cancel158199.618084ms (wrapper158.928244042s), runtime/test/fixture bytes unchanged. The copied run wrapper's pre-run scope text says full212, which is a stale label; actual command log and terminal216counts bind the216run. Claude Unicode request a525047febe6620fcfb548643bf7aa33bb9eedfbc528338c19ae3916a630c4da timed out120s/124 with empty stdout/stderr, invalid/no approval; one operational retry uses the exact same packet. Independent early Unicode reviews and clean app/ZIP remain pending.

- AG complete151path source review returned REQUEST_CHANGES/BLOCKED in both lanes: valid UTF16 ingestion reached UTF8-only renderer relationships/preparation (MEDIUM), malformed numeric references such as `&#x;` passed pinned validator (LOW); architecture also independently reproduced unknown/miscased named-entity admission. Reports are exactAG, not approvals of later code. Claude one operational retry returned valid APPROVE for AG ingestion-only delta (same a525047febe6620fcfb548643bf7aa33bb9eedfbc528338c19ae3916a630c4da); it did not inspect the downstream renderer and does not override reproduced blockers.
- Actual cleanAG first native Unicode job FAILED11.75609275s/405.40625MiB: all3UTF8/LE/BE revisions parsed successfully, but UTF16 previews lacked render with INVALID_XML. Logs/report/input bytes retained. No AG ZIP and no remaining jobs promoted. Root fixed the real producer/consumer seam in nextAH, rather than removing the preview assertion.
- AH working shared `packages/xml/index.ts` supplies fatal BOM decoding, declaration/Char checks, linear depth/lexical/reference validation and original-encoding private-copy encoding. Active text/tag regions allow only five exact predefined named entities or syntactically complete valid numeric references; escaped/CDATA/comment/PI literal spellings remain literal. Ingest policy advances to v4-shared-xml so OCR-off/preview-disabled reports also distinguish admission behavior. Renderer relationship validation and inset metadata/slides share the guard; only genuinely edited private slide parts are reencoded with original byte order/BOM/declaration. No-edit/signed/untouched source bytes remain exact; original sources are never rewritten.
- Office input policy advances to v8-unicode-bounded-insets; source helper fingerprint includes the shared XML file. UTF16 SVG is detected by BOM even under .bin and goes through the retained active-content/external-resource guards before Office. Existing network/read isolation, macro/OLE controls, ZIP budgets and signed-package behavior remain covered. No OCR/matching/diff/query/schema/Swift change or general PowerPoint equivalence claim.
- AH24focused checks PASS0fail/skip/cancel9949.949875ms, including actual Impress standard-inset render, UTF16 allparts and slide-only/mixed metadata, deterministic private copies/byte order/signatures/budgets/external resources/SVG guards, malformed numeric and named references, raw/reference Unicode boundaries, report-scoped history/query and original XML deadline tests. Full221/strict, independent final152path reviews, Claude shared-scope review and new actual app/ZIP remain pending. AG216 is not relabeled AH verification.

- AH complete221/221PASS0fail/skip/cancel153727.795333ms (wrapper154.445698834s), strict0warnings2.515843458s, all bound bytes fixed. Subsequent changes are a distinct AI source;221 is not relabeled final. Independent early reviews actually closed AG UTF16admission and malformed-reference findings, then caught redundant raw declaration regex fallbacks and the remaining UTF8-only source-font warning scan. Both adopted.
- Claude shared-scope review valid REQUEST_CHANGES (4fa92284cd64300cb0f4101ec66bdd5d3e7c919b532a6401db2cde1885ae217a): adopted BOMless UTF16 media sniff/fail-closed routing, consistent decoder-capability diagnostics, stale-helper proof, SVG CSS obfuscation handling and redundant declaration-regex removal. Existing parent-helper policy handshake already rejects old helper metadata; new actual job additionally requires changed_properties>0 and correct source digest/policy on all3encodings. Qualified Z public-corpus evidence is not relabeled a new all-deck gate; SVGZ/other unexamined media stay outside current claims.
- AI source-font scan now shares XML decoding and binds source_font_policy in renderer environment; pure UTF8/BOM/LE/BE named-font parity covers prior silent UTF16warning loss. SVG style inspection preserves actual text/CDATA order, decodes valid references exactly once, keeps CDATA/escaped literal entities literal and rejects CSS escapes/imports/external URLs. Firstfocused CSS negative failed because pinned processEntities:true left numeric references raw; root replaced that assumption with explicit ordered decoding, then targeted4pure checks passed. This actual failure is retained in tool transcript and its disposition, not promoted as a passing run.
- FinalAI222strict/full now running on fixed9runtime/testpaths, independent focused reviews and Claude finalsource closure pending. New actual native/ZIP remains required. No source rewrite, font extraction/installation, model download or network/upload behavior added.

- AI exact fixed-source222/222PASS0fail/skip/cancel156629.851875ms (wrapper157.355180333s), strict0warnings2.503118208s. Full-run bytes fixed. Claude final9file request ae358772e4b751c177b8ae55afb0789617def7b7d0507461ae1314b3e53d6c8a timed out180/124 empty stdout/stderr, invalid/no approval; later changed source is a new scope, not a relabeled retry.
- Further independent review reproduced encoded external url() in SVG presentation fill/filter attrs, valid encoded quoted-local false rejection, and serialized/single-quoted font-name diagnostic mismatch. Root fixed by inspecting decoded values of every preserved qualified SVG attribute, enforcing href for both href/xlink:href without key collision, and parsing DrawingML font nodes with namespace/quote/entity awareness. The renderer font policy is explicitly environment-bound; comments/wrong namespaces/+theme families do not invent font warnings.
- Small independent URL-cost probe found prior missing-parenthesis regex backtracking. Replaced all resource URL suffix regexes with a forward URL lexeme cursor: reject nested/unclosed parentheses/quotes, inspect localfragments, advance past consumed expression. Own focused3PASS812.9345ms includes two approximately1MB invalid SVG CSS inputs rejected in an isolated5s child394.979833ms. No large native timeout or actual external fetch was claimed. Current finalAJ223/strict, exact-source independent review, Claude narrowed final closure and packaged native/ZIP gates remain pending.

- AJ full223attempt failed before tests: strictSwift0warnings2.437287208s, npmcheck0.331085167s at tscTS6133unusedRegExp match variable. Removed only the unused variable/assignment; the URL scanner still consumes RegExp.exec in the same while condition. Exact9file final2→final3 identity delta retained;8files identical. New AK223strict/full runs on corrected fixedsource; AJ is not a passing suite.
- Current corrected9file source also passed pure intake/renderguard/privatecopy/fontscan on all5 SHA-pinned public PPTX (9pages), originals unchanged, no new render/native/OCR accuracy claim. Independent final3 recheck passed actual former SVG/font counterexamples and checked the monotone URLcursor; no new actionable finding reported in that focused closure. Complete152path readiness still requires immutablehead.
- Claude narrowed final2 request164a9f91ae8dafaf7f819460883cbe433737fd8f4fb55c482edf1381d667e072 again timed out180/124 with empty stdout/stderr, invalid/no approval. One exactpacket operational retry runs; its packet precedes only the unused-local removal, which is explicitly disclosed and separately checked by tsc/source review. No other provider approval is inferred.

- Corrected AK fixed-source strictSwift PASS0warnings2.434544583s and full223/223PASS0fail/skip/cancel152242.281667ms (wrapper152.961101667s), allruntime/test/fixture bytes unchanged. Includes complete current sharedXML/source-font/SVGlinear/resourceguards and historical44/45/50/51 event/evidence replay. Independent final3 focused code closure no new actionable findings (aad97607948672ef346e85623c7cf12cb03aa53e8555dd2a64419cf1e0dd1be4); architecture own24purecontrols and exactpriorcounterexamples also passed, finalwhole152pending. New sourcebuild/native11jobs/ZIP and complete original-base readiness follow on clean commit; product still OPEN, not universal OCR/PowerPoint/platform completion.

- CleanAK `1cc9af04a1fb71b49f9c433727d8b4e7d86c4b8e` actual11jobs allPASS with app8criticalhashes fixed: sharedXML22.451646666s/546.578125MiB; fresh90061.64537875s/1256.25MiB; aspect8.860616958s/606.625MiB; reference9.919313416s/382.796875MiB; bundle26.225652208s/1070.71875MiB; manual21.744371083s/678.421875MiB; backend13.706251084s/449.359375MiB; five15.796328375s/563.75MiB; copied600/900/1200reopen11.774772708/12.872333291/15.230489625s and726.515625/557.90625/720.484375MiB. Single-run driver-tree1s sampling, not p95. Allthree UTF8/LE/BE actualpreviews have derivedinsets>0, correctv8policy/sourceSHA and identical missing-font warnings; exactrawtext/table/notes/export and secondprocess bodies retained.
- AK ZIP `release/Docver-0.4.0-native53-xml-v4-arm64.zip`390495314B SHA2565cd78b5ab11a0432938eddf5ab3e4a407a95ea8a34dfeae1e93b5aac68cc6a1e passed strictapp/vendor signatures, ZIP/unzip into pathwithspaces, relocatedfreshfive/backend8/referenceimport/bundlehistory+MCP+secondprocess andfinalsignature. Exact releasevalidation retained. Sourcecode lane complete152 COMMENT/READY (8a639e2093109630f4209d1d5b3f191da3d8f63281c6b14cf83ee13c554c8d78), architecture full152 reportpending. AK artifacts do not qualify futureAL.
- QualifiedcodeWATCH: a nonempty SVG xml:base can change standards-based fragment URI resolution; only guardadmission/URI resolution was demonstrated, no LibreOffice honor/fetch or sandboxbypass. Root adopts small ALfail-closed policy rejectingnonemptyxml:base (emptybase/localfragment positive remains), and binds svg_resource_policy into renderer environment. New pureSVGcontrolPASS437.690209ms across bothUTF16orders/names, direct/inheritedbase andrelative/external/whitespace cases. New fixed-source AL223strict/full runs; finalapp/ZIP qualification will be separate. This is conservative boundary hardening, not a claimed reproduced nativeexploit.
- Latest Claude exactfinal2 operationalretry also timedout180/124empty, retryexhausted; no finalapproval credited. Both prior substantive ClaudeREQUEST_CHANGES and allsourcecounterexamples/dispositions remain preserved. ProductcompletionOPEN for universalOCR/PowerPoint fidelity/platformgates.

- AK architecture full152 WATCH/SOURCE_READY report52206B SHA25661e74f6e708f6dbb2e1e56806f5b613696809e6c51d9c940c798961b8bc1b55a; combined with independent codeCOMMENT/READY and exactapp/ZIP gates, AK is a separately qualified checkpoint. ProductOPEN and its base-URIWATCH retained; not futureAL approval.
- AL exactfixed-source strictSwift PASS0warnings2.693743209s and full223/223PASS0fail/skip/cancel152374.466958ms (wrapper153.126279584s), runtime/test/fixture bytes unchanged. Independent source lane replays original3baseURIexamples and currentUTF16SVGcontrolPASS; no new narrowdeltaissue. Standardsbasis https://www.w3.org/TR/xmlbase/ verified; no nativefetch claim. New cleanALsourcecomplete152 closure, freshapp11jobs and separateSVG-policyZIP remain pending.


### 2026-10-20 source D 재리뷰와 E 감독 구조 수정

- D2ca797b 전체251/251PASS157731.698375ms(wrapper158.476216초), 추적190파일 불변. 독립 코드APPROVE/sourceREADY와 달리 아키텍처는 직접 child가 setpgid로 이탈한 직후 guard/group을 죽이면 다음50ms검사 전 child가 남을 수 있는 D-B1을 근거로 BLOCK/SOURCE_BLOCKED했다. 이는 source interleaving이며 실제 x2t exploit 재현으로 주장하지 않는다. D앱/ZIP은 실행하지 않았고 D는 최종 승인이 아니다.
- E는 Node가 분리한 session leader G를 fork child로 대체하지 않고 같은 PID에서 sandbox/x2t로 exec한다. G의 PID=PGID=SID를 확인하므로 setpgid/setsid 이탈을 OS가 거절하며 sandbox는 추가 fork를 막는다. fork한 trusted monitor M만 전용fd3에 PID/최종OK를 쓰고, launcher/converter의 kqueue 종료 감시 두 개를 각각 등록한 뒤에만 변환을 시작한다. Node는 monitor 종료/오류/잘못된 응답에서 원래 G그룹을 취소하며 Gexit0과 최종검사OK를 모두 요구한다. 부모 종료/자원초과는 M이 그룹을 정리한다. 별도정상종료·기존실패경로·실제앱 검증은 독립 gate다.
- native control은 escape 시도 이후 PID 게시를 기다려 즉시 취소/monitor SIGKILL을 각각12회 검사한다. 원래 D의 escape-only 검사와 별개다. 새 clean E 전체·양 lane·실제앱·이동ZIP은 검증 전이며 기존 F/AL 앱·ZIP/HANDOFF/PLAN은 보존한다. 보편 OCR/PowerPoint 충실도 OPEN을 이 감독 수정으로 해결했다고 세지 않는다.

- E4817a0b 전체251/251PASS161484.686166ms(wrapper162.221819초), 추적190파일 불변. 독립 코드의20개 runtime fault control에서 resource reject가 TOOL_SUPERVISOR로 바뀐 경우 한국어 SIDECAR_LIMIT로 번역되지 않는 작은 회귀를 찾아 E2에서 두 코드 모두 동일한 제한 안내로 정리한다. 실제 native aggregate/symlink reject와 pure error-identity/cancellation 보존 검사를 추가하며 E의 전체결과를 E2 결과로 다시 표시하지 않는다.


### 2026-10-20 source E2 실제 검증과 E3 감독 경계 보강

- E2 clean2374b60 전체252/252PASS160209.810583ms(wrapper160.953237초). 독립 코드COMMENT/sourceREADY(2f3ae948…), 아키텍처WATCH/sourceREADY(f706e572…) 후 실제 앱 build20.983초, five+공개PPTX10개+fresh300쪽 덱12native작업과MCP five/300/old900 3작업 총15PASS. C의 실제닫기실패반례를 같은assertion으로 재실행해PDFKit선택쪽·해시·닫기정리·DB/report불변까지 통과했다. ZIP render1 391388340B SHA294499aec2f35f71699a0f3fc1201fe054e5f1749fcd8b095e83414d5abf39fd, 공백이동경로 실제app/MCP/서명 총12checksPASS. F/AL앱/ZIP는 보존한다.
- E2 앱SIGKILL후 helper전부0.104437초내종료/잔여0, 추가 bridge+app동시SIGKILL은 실제pendingjob/lease1개를 남겨 actual같은library재시작으로 복구/DB불변(helpers0.040078초). E2 Swift Bridge cancel 검사는 명시적sidecarClose를 포함하므로 cancellation-alone 증거로 세지 않는다. E3검사에서는 명시close전에정리불변을 확인한다.
- Grok completeE REQUEST_CHANGES는 감독M이 untrustedG의 미exec child여서 debugging후group이탈 가능성을 지적했다. E2 actualproductionpolicy/guard 자체fixture에서 parent-side setpgid(M,M)=0을 확인했지만 task_for_pid=5,ptrace=-1/EPERM,monitor정상종료였다. 여기서 attach/정지/timeout우회나 실제x2t exploit은 재현되지 않았다. 첫repro는vendorroot가job까지포함해쓰기거절(exit4)이었으며 별도보존하고, 분리한vendor/actualprobe결과와 혼동하지 않는다. E2 source/app/ZIP PASS들은 그대로 두고최종통합승인은 추가경계검증대기로BLOCKED했다.
- E3는 M을 같은G그룹에서 trusted guard의--monitor이미지로 먼저exec해 parent-side setpgid를 OS EACCES로 막고, PT_DENY_ATTACH·hardened runtime(디버깅entitlement없음)·sandbox system-debug deny를 추가한다. dirFD와privatefd3/ready만명시적으로exec에보존하고 monitor신원/FD/보호/kqueue등록이끝난후READY를준다. Node는실패진단에실제exit/signal을포함한다. nativecontrol에서M그룹이탈거절과Mach/ptrace거절(부모SIGSEGV도failclosed)을직접검사한다. 전체/양lane/새앱/ZIP은새native-sidecar-03에서재검증전까지PASS로세지않는다.
- Claude E completeCOMMENT와E2 limit-only closureAPPROVE, Grok E completeREQUEST_CHANGES와E2 limit-only closureAPPROVE는각scope별원문을보존한다. E2 narrowapproval은monitor지적을닫지않는다. 480 OCR218정확/22오독/240빈,PowerPointstrict0/26은OPEN이다.

- E3 집중17/17PASS3444.312667ms(wrapper3.470154초), 실제native감독검사2408.273ms. parent-side그룹변경은EACCES/원래G그룹유지, Mach taskport거절, ptrace는부모SIGSEGV와전체ownedPID종료로failclosed를확인했다. 초기E3검사에서실제SIGSEGV를에러에표시하지못한진단회귀가드러나signal을TOOL_FAILED에도보존하고재검사했다. 서명된runtimeguard SHA b995ae2ed0fc0e482ccd6c1a27872a84bdf384e41cedd995f1c7d19e3b7d9ffa; 최종앱/이동ZIP복사본의같은서명flags와entitlement는별도확인한다.
