# 네이티브 Mac 앱 구현 상태 · 2026-10-19

사용자가 A안을 선택하고 중앙 문서 확대·수백 페이지·진짜 네이티브 앱을 요구하여 초기 Electron 가정을 SwiftUI·AppKit·PDFKit으로 대체했다. 원래 PLAN/HANDOFF는 수정하지 않았다. Claude의 세 시안은 `docs/design/concepts/`에 보존했다. Claude·Grok·Agy의 초기 설계 자문 원문/argv/해시/종료 상태는 `.omx/artifacts/ask-*`에 남겼으며, 설계 자문을 최종 코드 승인으로 취급하지 않는다.

현재 `release/Docver.app`은 실제 실행 가능한 arm64 로컬 ad-hoc 서명 앱이다. Node helper와 lockfile 고정 운영 의존성이 들어 있다. 프로젝트 가져오기·순서 변경·전체 이력·인접/구간 비교·원본 PDF·PPTX 구조 보기·근거 강조·대응 수정·과거 고정 보고서·export·읽기 전용 MCP 설정을 제공한다. 집중 모드에서는 보조 패널/변경 목록을 접고 한 페이지를 창 대부분에 표시한다.

검증:

- `npm run check`: 36개 통합 테스트 통과. 그림 순서/가림/부분 가림/배경·투명도/관측 취소선과 숨김 주석/추정 선과 격자/비가시 OCR/색상/클리핑/비사각형/블렌드/회전·CropBox/표 출처를 포함한다.
- `npm run mac:build`: Swift 네이티브 실행 파일과 Node helper를 빌드하고 ad-hoc 서명·strict verify.
- `node scripts/native-backend-smoke.mjs`: 개발 Node가 아닌 번들 helper와 최소 PATH로 8개 작업 검증. stage 변조/취소·복구/stale draft 거절, 새·과거 report, lazy 원문, export 동일성, 실제 MCP stdio와 DB hash 불변.
- `node scripts/native-smoke.mjs`: 실제 `.app`의 5버전 `[3,4,4,3,3]`쪽 데모, 숫자 변경 2개, 원문 비교·집중 모드·전체 이력 화면. stderr 비어 있음.
- `node scripts/native-smoke.mjs --scale`: 300쪽×3버전 합성 PPTX→PDF→PPTX, 숫자 변경 2개, 300쪽 원문 표시. 약 6초(분석과 UI 대기·화면 저장을 포함한 현재 장비의 관측치). stderr 비어 있음. 결과·화면은 `output/native-*`.

미완료/검증 범위: PPTX 고충실도 렌더와 Office 참조, OCR/이미지·차트 의미, 복합 PDF 가시성 전체 판정, 다양한 실문서 정확도 corpus, macOS 14 실기·다른 장비·접근성 전체 검증, Developer ID/공증·공개 배포·오픈소스 라이선스 확정. PDF 가림은 삭제 의도로 단정하지 않으며 불확실성은 원문과 gap으로 보존한다. 원본 OOXML 표와 PDF 격자 추정은 동일 셀 의미로 합치지 않는다. 1차 코드 리뷰에서 발견한 후보 cap의 비대칭 모호성, MCP의 긴 표시 배열 순회 실패, 이미지 마스크 가림 누락, helper crash/cancel 혼동을 수정하고 회귀 검증했다. Claude/Agy의 클리핑·Form BBox·annotation overlay·복합 선·병합 셀·전체 이력 이동·초기화 race 지적도 반영했다. 표시 상태 이벤트에는 관측/추정 필드를 추가했고 PPTX의 미계산 표시 상태를 PDF의 확인된 보임으로 취급하지 않는다. 사각형/페이지 경계 clip은 내부 글자를 불확실성 없이 통과시키고 복잡한 clip은 gap으로 남긴다. OCR 모드3 텍스트는 화면 검증이 없어 비교를 보류한다. 표 텍스트를 page.text에 포함해 초기 매칭/report ID와 달라진다. Grok 1차 코드 packet은 timeout으로 무효이며 작은 범위로 운영 재시도한다. 최종 리뷰 결과는 정확한 snapshot artifact로 별도 기록한다.

아래는 초기 CLI/MCP 체크포인트의 당시 기록이다. 위의 현재 상태를 우선한다.

---

# 구현 진행 기록

업데이트: 2026-10-19 KST · 상태: 첫 구현 체크포인트 완료, v0.1 전체 미완료

HANDOFF.md와 PLAN.md 전체를 기준으로 구현했다. 두 원본 문서와 형제 프로젝트는 수정하지 않았다. PLAN SHA-256도 인수인계의 `57e9c9ea3d14267da3eff96cf912d13aa8ed46e47d86c7a7cb1d6eeb2b7d0b1d`와 일치한다. 이 하위 폴더에 독립 Git 저장소를 초기화했으며 commit/push/공개 배포는 하지 않았다. 기존 개인 문서·Local Media 자료 대신 새 합성 자료만 사용했다.

## 단계와 구현 범위

| 단계 | 이번 결과 | 남은 합격 기준 |
| --- | --- | --- |
| M0 계약·fixture | TypeScript/Zod 모델, 버전 JSON Schema, 입력/fixture manifest, 명시 정답표와 6개 mixed-format 시나리오 구현·자동 검증 | 정답표의 사용자/외부 독립 검토는 미실행 |
| M1 추출·렌더 | PPTX/PDF 단독 추출, bundle 대응/불일치, PDF PNG, 격리 변환 어댑터와 렌더 spike | 실제 LibreOffice 실행, 독립 Office 참조, 픽셀 충실도 검증; G1 열림 |
| M2 매칭·변경 | 전역 텍스트 매칭, 경쟁 후보, 이동+숫자 수정, 중간 삽입/삭제, hidden coverage gap | 시각·이미지/배치 특징, 개체 계보, 분할/병합 확정, 광범위 정확도 측정 |
| M3 저장·조회 | SQLite snapshot/run 분리, byte-addressed assets, 순서/수정별 새 report, 과거 snapshot·공통 query | 엔진 변경 alias/supersedes, migration, 영속 추출 캐시·worker/세밀한 취소·재시도 |
| M4 AI | JSON/JSONL/Markdown, 10개 읽기 전용 MCP 도구, 5개 resource template, cursor/scope/budget | 이미지 evidence 제공, 노트 원문의 MCP 분할 조회, 클라이언트별 실사용 검증 |
| M5 UI | 미구현 | Electron/React 선택 검증, 타임라인·비교·근거 이동·수동 대응 편집 |
| M6 배포 | 미시작 | 새 macOS 설치·성능 검증, G5 공개 라이선스·의존성 notice, 설치본 |

## 변경 파일

- `package.json`, lockfile, `tsconfig.json`, `.gitignore`: Node.js 24/TypeScript 실행 기반과 고정 의존성.
- `packages/schema`, `docs/schemas`: canonical hash, 관측/가용성/근거/계보/report와 입력·출력 스키마.
- `packages/ingest`, `packages/render`: relationship 순서의 OOXML, PDF.js 텍스트/viewport/bbox, PNG, 로컬 변환 어댑터.
- `packages/matching`, `packages/diff`, `packages/engine`: 전역 1:1 대응과 후보·정보 공백·인접 변경·분석 실행.
- `packages/storage`, `packages/query`, `packages/export`: 불변 저장·읽기·내보내기 공유 경로.
- `apps/cli`, `apps/mcp`: analyze/query/export/preview와 실제 읽기 전용 stdio 서버.
- `scripts`, `tests/ground-truth`, `tests/integration`: 재현 가능한 합성 생성기, 렌더 spike, 통합 검증.
- `README.md`, `docs/adr`, `docs/dependencies.md`: 실행법·초기 결정·지원 범위와 미검증 사항.

## 실행 환경과 결정

macOS arm64, Node.js v24.19.0, npm 11.6.2. LibreOffice는 PATH와 기본 앱 위치에 없었다. TypeScript 엔진과 내장 SQLite를 먼저 사용했다. PDF.js 6.4.299, MCP SDK 1.32.1을 lockfile로 고정했다. SDK 기본 협상 protocol은 2025-11-25이며 실제 클라이언트 연결을 검증했다. Electron은 아직 설치하지 않았다.

라이선스 G5는 미결정이라 패키지를 private/UNLICENSED로 두었다. 개발용 PptxGenJS의 image-size 전이 경고는 2.0.4 override로 해결하고 이미지 포함 fixture/spike를 실행했다. 공개 배포의 승인이나 라이선스 확정을 받은 것으로 취급하지 않는다.

## 검증 명령과 결과

- `npm ci`: lockfile만으로 151개 패키지 재설치 성공, audit 0건.
- `npm run check`: 엄격 타입 검사(noUnused 포함) + 통합 테스트 **19/19 통과**, clean install 후 마지막 실행 약 1.80초. 성능 목표 검증 수치는 아니다.
- `npm run fixtures`: 6개 타임라인 생성 성공. 두 방향 단독 입력, 5버전 이력, 복제·분할/병합 후보, 숨김 공백, 정상/잘못된 bundle과 스캔 PDF를 포함한다. seed=20261018, 생성기/폰트 hash/asset hash/의도된 delta/정답 page key를 기록한다.
- `npm run schemas`: 모델·fixture·도구 계약의 JSON Schema 재생성 성공.
- `npm run spike`: 6쪽 PPTX/숨김 3쪽/텍스트 요소 18개 추출. 한글·혼합 폰트·도형·투명도·표·차트·회전 텍스트 각 6개. 원본 PNG 6개와 독립 PDFKit 기준 PDF/PNG 생성. reference-1.png를 직접 열어 한글·표·회전 텍스트 표시를 확인했다.
- spike 변환 결과: **CONVERTER_UNAVAILABLE**, 픽셀 정확도 **unverified**. 동일 변환기의 출력으로 고충실도를 주장하지 않는다.
- `npm audit`, `npm audit --omit=dev`: 알려진 취약점 0건(이 실행 시점 registry 결과).
- CLI analyze/export/query를 실제 실행해 `.docver/`와 `artifacts/forward/`를 생성했다.

통합 테스트는 다음을 검증한다.

- 양방향 `100 → 120 → 110`의 같은 계보와 실제 page/bbox/요소 근거, 부호·소수점 보존.
- 중간 페이지 추가/삭제, 이동+수정, 단순 삽입 뒤 페이지를 이동으로 오인하지 않음.
- PDF 노트/숨김 정보 부재를 삭제로 기록하지 않음, hidden slide의 중간 PDF 공백 연결.
- 정상 bundle 내용 대응과 잘못된 bundle의 명시 경고, OCR 없는 스캔 숫자 변경을 생성하지 않음.
- 같은 조건·파일명/경로 변경의 같은 report와 서로 다른 run ID. 재정렬·사용자 1:1 수정의 새 report 및 과거 조회.
- 같은 파일의 반복 등장에 별도 occurrence/관측 ID, history와 range_net의 구분.
- query/export 이벤트 ID·전체 데이터 일치, 페이지→요소→근거 읽기, cursor의 report/filter 결합과 최신 별칭 고정.
- 긴 페이지 원문을 bounded chunk로 끝 공백까지 복원. 이 테스트에서 XMLParser의 기본 trim에 따른 원문 손실을 발견해 수정했다.
- 손상 ZIP/PDF·암호 PDF·구형 PPT의 명시 오류와 정상 버전 보존. DTD·외부 관계 거절, bbox 검증, 변환기 부재/timeout, 사전 취소.
- 실제 MCP stdio 연결과 input/output schema·resource, 숫자 전체 이력·entity history, 업무 payload byte 예산, 다른 프로젝트·file URI·셸 도구 거절.
- MCP 조회 전후 SQLite hash 동일, SQLite read-only 연결에서 DELETE 실패.

## 재현 가능한 첫 데모

```sh
npm ci
npm run fixtures
npm run check
npm run cli -- analyze --manifest tests/fixtures/generated/forward/manifest.json
npm run cli -- export --project prj_forward --out artifacts/forward
```

확인 report: `rpt_d1c7ba9ec62e3c6113d5d312728f7146241889c4e6437af8cd05c3bcbbc5e1e9`.
입력 페이지 수: 3 → 4 → 3. 숫자 근거: page 2의 100 → page 2의 120 → page 1의 110.
결과 16개: 텍스트 수정 2, 상대순서 이동 표시 6, 페이지 추가 1, 삭제 1, capability 공백 6. 이동 표시는 상대순서 역전이 참여한 페이지들이며 사용자가 수행한 이동 작업의 최소 개수라는 뜻이 아니다. 별도 report coverage 항목은 28개다.

## 남은 실패·미검증과 다음 작업

현재 자동 테스트 실패는 없다. 다만 합성 6개 시나리오는 PLAN의 30 타임라인/600페이지 목표를 대신하지 않는다. PPTX 마스터/그룹 좌표, 회전 도형 bbox, 표·차트 의미, 유인물 판별, OCR, 이미지/시각 diff는 미지원 또는 근사치이며 관측 한계로 표시한다. 손상/암호 파일은 실패 상태를 보존하지만 자동 복구는 제공하지 않는다. 오래된 비호환 스키마 snapshot은 SCHEMA_INCOMPATIBLE로 거절하며 migration은 없다.

다음 순서:

1. M1의 실제 LibreOffice/폰트 환경과 독립 Office 참조를 확보해 G1을 닫는다. 구조 정확도와 렌더 오차는 분리 측정한다.
2. M2의 개체/시각 대응과 정확도 corpus, 분할/병합의 사용자 확정 그래프를 확장한다.
3. M3의 worker·캐시·세밀한 취소/재시도·migration, 계보 alias/supersedes를 추가한다.
4. 공통 query 위에 M5 UI를 구현하고, 5버전 작업·근거 클릭·수정→새 report를 실제 화면에서 검증한다.
5. M4 클라이언트 실사용과 M6 라이선스/새 장비 설치를 검증한다. CLI/MCP 구현만으로 v0.1 완료라고 보고하지 않는다.
