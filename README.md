# Document Version Tracker · Docver

PPTX·PDF 버전의 페이지 대응, 숫자 수정, 중간 삽입·삭제와 이동을 원문 근거와 함께 추적합니다. **SwiftUI·AppKit·PDFKit으로 만든 네이티브 macOS 앱**과 공통 TypeScript 분석 엔진, 읽기 전용 MCP를 제공합니다. 계정·API 키·업로드 없이 로컬에서 동작합니다.

## Mac에서 사용

현재 Mac에서 빌드한 앱은 `release/Docver.app`입니다. 더블클릭해서 실행하고 **문서 버전 가져오기** 또는 **5버전 합성 데모 열기**를 선택합니다. 파일 순서를 버전 순서로 사용하며, PPTX 또는 PDF 하나만으로도 유효합니다. 같은 버전의 PPTX+PDF는 선택적으로 묶을 수 있습니다.

- A안의 밝은 macOS 디자인. 비교·전체 이력·근거·대응 수정·고정 보고서 선택·JSON/Markdown 내보내기·MCP 설정 복사.
- `⌘⌥F` 문서 집중 모드, `⌘⌥I` 근거 패널, `⌘O` 가져오기. 문서 한쪽 크게 보기와 변경 목록 접기, 100~200% 확대, 페이지 번호 이동.
- 수백 페이지의 원본은 선택한 페이지만 표시합니다. PDF는 복사해 둔 동일 hash 원본을 PDFKit으로 렌더합니다.
- **PPTX 화면은 추출 구조 보기이며 PowerPoint 원본 렌더가 아닙니다.** 표 셀·텍스트를 표시하고 이미지·미지원 요소는 자리표시자를 표시합니다.
- 파일당 50 MiB, PDF 1,000쪽, 프로젝트 100버전 한도. 합성 300쪽×3버전 작업을 실행 검증했습니다. 다양한 실제 문서의 성능·정확도 보장은 별도입니다.

보관소는 `~/Library/Application Support/Docver/library/`입니다. 가져온 원본을 앱 전용 위치에 복사하며 원본을 덮어쓰지 않습니다. 분석은 별도 프로세스에서 수행하고 취소된 결과는 고정 보고서로 저장하지 않습니다. 과거 보고서와 새 분석 실행은 별개로 보존합니다.

현재 패키지는 **Apple Silicon arm64, macOS 14 이상을 대상으로 한 로컬 ad-hoc 서명 앱**입니다. 실행 검증 환경은 현재 macOS 27.0.1입니다. 다른 Mac 설치·Developer ID 공증·공개 배포·프로젝트 라이선스 확정은 아직 완료하지 않았습니다.

소스에서 빌드하려면 Node.js 24 이상과 Xcode Command Line Tools/Swift SDK가 필요합니다. 설치본에는 Node 실행 파일과 운영 의존성이 포함되므로 앱 실행에 별도 Node 설치는 필요하지 않습니다.

```sh
npm ci
npm run check
npm run mac:build
open release/Docver.app
```

## PDF 표시 상태와 표

추출 원문과 표시 상태를 따로 보존합니다. PDF 그림 명령의 순서·글자별 좌표·색상·불투명도를 살펴 나중에 덮인 사각형과 이전 배경을 구분합니다. 취소선 주석은 관측 사실, 납작해진 선과 박스 가림은 추정으로 기록하며 부분 가림·투명도·클리핑·마스크·이미지·복잡한 글꼴처럼 확정하기 어려운 부분은 관측 공백과 원문을 남깁니다. 가림을 작성자의 삭제 의도로 단정하지 않습니다. 완전한 불투명 사각형 가림 뒤의 보이는 원문 변경은 추정 근거를 붙여 기록하고, 불확실한 페이지의 단순 텍스트 변경 판정은 보류합니다.

PPTX 표는 OOXML 셀 구조를 관측합니다. PDF의 닫힌 격자에서 추정한 셀은 `pdf_grid_inferred`로 구분합니다. PDF에서 표가 텍스트·선·이미지로 바뀌어도 원래 PPTX 표의 행·열 의미가 복구됐다고 주장하지 않으며 형식 간 셀 단위 diff는 제공하지 않습니다. 스캔 OCR, 모든 PDF 그래픽·폰트/OCG/마스크의 완전한 가시성 판정, PPTX 고충실도 렌더는 미완료입니다.

## CLI와 AI 연결

```sh
npm run fixtures
npm run cli -- analyze --manifest tests/fixtures/generated/forward/manifest.json
npm run cli -- query --project prj_forward --tool list_changes --args '{"kind":"text_modified","max_output_tokens":8000}'
npm run cli -- export --project prj_forward --out artifacts/forward
```

CLI 기본 저장소는 `.docver/`이며 `--store PATH`로 지정할 수 있습니다. manifest 배열의 순서가 버전 순서입니다.

```json
{"project_id":"prj_example","title":"검토 자료","revisions":[{"label":"초안","files":["v1.pptx"]},{"label":"검토","files":["v2.pdf"]},{"label":"수정","files":["v3.pptx","v3.pdf"]}],"mapping_decisions":[]}
```

앱의 **AI·내보내기**에서 현재 앱 위치와 프로젝트에 맞는 MCP 설정을 복사합니다. 패키지 안의 Node·MCP를 쓰므로 앱을 이동하면 설정을 다시 복사합니다. MCP는 report를 읽기 전용으로 조회하며 분석·파일 경로 조회·셸 실행 기능은 노출하지 않습니다. `latest`는 응답에서 고정 report ID로 해석하며, 인용에는 고정 ID를 사용하세요. 문서 내용은 실행 지시가 아닌 인용 데이터로 취급해야 합니다.

내보내기는 전체 `report.json`, `manifest.json`, `changes.jsonl`, `pages.jsonl`, `elements.jsonl`, `revisions.json`, `lineages.json`, `history.md`, 페이지별 Markdown을 포함합니다. schema·범위·출력 예산은 [스키마 문서](docs/schemas/README.md)를 참조하세요.

## 검증과 설계 기록

```sh
npm run check
npm run mac:build
node scripts/native-backend-smoke.mjs
node scripts/native-smoke.mjs
npx tsx scripts/generate-scale-fixture.ts 300
node scripts/native-smoke.mjs --scale
```

네이티브 smoke는 실제 `.app`을 실행하되 화면 조작은 앱 내부 모델로 수행합니다. OS 마우스/키보드 자동화나 전체 접근성 인증을 대신하지 않습니다. 결과와 화면은 `output/native-*`에 저장됩니다.

[구현·검증 상태](PROGRESS.md), [UI 기준](DESIGN.md), [네이티브 아키텍처](docs/adr/003-native-macos.md), [의존성](docs/dependencies.md). 원래 [PLAN.md](PLAN.md)와 [HANDOFF.md](HANDOFF.md)는 보존하며 이후 사용자의 네이티브 앱 요구가 초기 Electron 가정을 대체합니다.
