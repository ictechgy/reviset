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
