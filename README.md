# Document Version Tracker · Docver

PPTX·PDF 버전의 페이지 대응, 숫자 수정, 중간 삽입·삭제와 이동을 원문 근거와 함께 추적합니다. **SwiftUI·AppKit·PDFKit으로 만든 네이티브 macOS 앱**과 공통 TypeScript 분석 엔진, 읽기 전용 MCP를 제공합니다. 계정·API 키·업로드 없이 로컬에서 동작합니다.

## Mac에서 사용

현재 Mac에서 빌드한 앱은 `release/Docver.app`입니다. 더블클릭해서 실행하고 **문서 버전 가져오기** 또는 **5버전 합성 데모 열기**를 선택합니다. 파일 순서를 버전 순서로 사용하며, PPTX 또는 PDF 하나만으로도 유효합니다. 같은 버전의 PPTX+PDF는 선택적으로 묶을 수 있습니다.

최근 검증본은 [Docver.app](release/Docver.app)과 [arm64 ZIP](release/Docver-0.4.0-native53-svg-guard-v1-arm64.zip)입니다. 빌드 원본은 `3ff0af791b661c8243ae8276a76e0c3a47644be9`이며, 223개 테스트·실제 앱 11개 시나리오·ZIP 이동 실행 검사를 통과했습니다. 상세 증거는 [검증 기록](release/validation.json), 남은 OCR·PowerPoint 충실도 문제는 [품질 현황](docs/QUALITY.md)에 기록합니다. 이 결과는 모든 문서를 완벽히 판독한다는 의미가 아닙니다.

- 인접 버전의 1:1 연결·해제·1:N 분할·N:1 병합을 수정합니다. 한 관계에서 최대32페이지를 고르고 이유를 남기며, 모든 분기를 전체 이력과 원문에서 따로 열 수 있습니다.
- 같은 버전의 PPTX 슬라이드와 제공 PDF 페이지를 별도 창에서 연결·해제·재연결하고 이유·대체된 연결을 보존합니다. 과거 보고서에서는 연결 이력을 조회합니다. 사용자 연결은 참고용이며 PowerPoint 화면 충실도를 보증하지 않습니다.
- A안의 밝은 macOS 디자인. 비교·전체 이력·근거·대응 수정·고정 보고서 선택·JSON/Markdown 내보내기·MCP 설정 복사.
- `⌘⌥F` 문서 집중 모드, `⌘⌥I` 근거 패널, `⌘O` 가져오기. 문서 한쪽 크게 보기와 변경 목록 접기, 100~200% 확대, 페이지 번호 이동.
- 수백 페이지의 원본은 선택한 페이지만 표시합니다. PDF는 복사해 둔 동일 hash 원본을 PDFKit으로 렌더합니다.
- PPTX 원문은 텍스트 조각·저장된 필드 값·줄바꿈과 도형·표의 순서를 보존합니다. 발표자 노트의 문단과 빈 줄도 유지합니다. XML 원문은 UTF-8과 BOM이 있는 UTF-16을 읽고, 손상된 인코딩과 허용하지 않는 문자는 명시 오류로 표시합니다.
- PPTX는 앱에 포함된 LibreOffice로 실제 PDF를 렌더해 표시합니다. 내용 대응이 확인된 같은 버전의 원본 PDF를 함께 가져오면 그 PDF를 우선 표시합니다. 별도 변환 화면이 없으면 구조 보기를 명시합니다. 숨김 슬라이드도 포함해 원본 슬라이드 번호와 렌더 페이지를 검증합니다.
- 스캔·복합 PDF에는 macOS Vision의 로컬 한글/영어 OCR을 사용합니다. 300 DPI 목표, 최대 4096px, 겹치는 타일과 숫자 영역 재인식으로 부호·소수점·금액을 검증합니다. 인식 점수는 확률이 아니며 OCR 변경은 추정과 원문 확인 표식을 붙입니다.
- 파일당 512 MiB, PDF 1,000쪽, 프로젝트 100버전 상한입니다. 분석은 페이지를 최대 16쪽씩 native helper로 처리하고, 같은 화면의 OCR은 버전 간 재사용합니다. 페이지 이동은 SQLite의 개별 페이지 인덱스를 사용합니다. 상한이 모든 문서의 속도·정확도 보장은 아닙니다.

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

추출 원문과 표시 상태를 따로 보존합니다. PDF 그림 명령의 순서·글자별 좌표·색상·불투명도를 살펴 나중에 덮인 사각형과 이전 배경을 구분합니다. 취소선 주석은 관측 사실, 납작해진 선·박스 가림·이미지에 합쳐진 수평 취소선은 추정으로 기록합니다. 가림을 작성자의 삭제 의도로 단정하지 않습니다.

PDFKit의 실제 렌더 지문도 비교합니다. 화면이 같으면 원문층이나 OCR만 달라졌다는 이유로 숫자 수정을 만들지 않습니다. 이미지·차트·배치처럼 글자가 같아도 화면이 바뀌면 `visual_region_changed`로 기록합니다. 형식 간 렌더 차이는 렌더러·폰트 대체가 원인일 수 있어 추정으로 구분합니다.

원문 가시성의 불확실성은 보존하며 별도의 화면 OCR을 추정 비교에 사용할 수 있습니다. 낮은 점수·숫자 대안 충돌·짝이 없는 OCR 영역에서는 정확한 텍스트 변경을 보류합니다. OCR 누락을 삭제로 만들지 않습니다. 페이지 일부가 불확실해도 유일하게 대응하고 읽을 수 있는 숫자 영역은 `text_scope=region`으로 비교하며 다른 영역의 공백을 유지합니다.

PPTX 표는 OOXML 셀 구조를 관측합니다. PDF의 닫힌 격자는 `pdf_grid_inferred`, macOS 26 이상에서 인식한 화면 표는 `vision_table_inferred`입니다. 화면 OCR 표는 행·열·병합 범위와 좌표를 보존하지만 원래 PPTX 셀 식별자를 복구한 것은 아닙니다. macOS 14/15에서는 표 구조 API의 미지원 상태와 일반 OCR 결과를 제공합니다.

PowerPoint 독립 참조의 픽셀 비교와 남은 정확도 기준은 [품질 검증](docs/QUALITY.md)에 기록합니다. LibreOffice 변환을 모든 PowerPoint 환경의 픽셀 동일성으로 부르지 않습니다. 누락 글꼴과 변환 텍스트 불일치는 페이지별 경고로 남깁니다.

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

버전별 내용 검색, 원문·노트·가림/OCR 층의 분할 읽기, 변경 전후값·근거·판독 한계 조회는 [AI용 MCP 조회 가이드](docs/MCP.md)를 참고하세요. `inspect_version`·`compare_versions` prompt도 같은 조회 순서를 안내합니다.

내보내기는 전체 `report.json`, `manifest.json`, `changes.jsonl`, `bundle-decisions.jsonl`, `pages.jsonl`, `elements.jsonl`, `revisions.json`, `lineages.json`, `page-relations.jsonl`, `mapping-relations.json`, `history.md`, 페이지별 Markdown을 포함합니다. schema·범위·출력 예산은 [스키마 문서](docs/schemas/README.md)를 참조하세요.

## 검증과 설계 기록

```sh
npm run check
npm run mac:build
node scripts/native-backend-smoke.mjs
node scripts/native-smoke.mjs
npx tsx scripts/native-relations-smoke.ts
npx tsx scripts/generate-scale-fixture.ts 300
node scripts/native-smoke.mjs --scale
npx tsx scripts/prepare-scan-scale.ts 300
node scripts/native-smoke.mjs --scan-scale
npx tsx scripts/verify-office-reference.ts
```

네이티브 smoke는 실제 `.app`을 실행하되 화면 조작은 앱 내부 모델로 수행합니다. OS 마우스/키보드 자동화나 전체 접근성 인증을 대신하지 않습니다. 결과와 화면은 `output/native-*`에 저장됩니다.

[구현·검증 상태](PROGRESS.md), [UI 기준](DESIGN.md), [네이티브 아키텍처](docs/adr/003-native-macos.md), [의존성](docs/dependencies.md). 원래 [PLAN.md](PLAN.md)와 [HANDOFF.md](HANDOFF.md)는 보존하며 이후 사용자의 네이티브 앱 요구가 초기 Electron 가정을 대체합니다.

변환기는 매크로/OLE, 지원하지 않는 임베디드 개체, 외부 리소스 및 SVG 외부 참조가 있는 PPTX를 구조 보기로 보류합니다. 512MiB는 입력 상한이며 그 크기의 모든 문서에 대한 메모리·시간 보증이 아닙니다.

### Same-version reference history (schema0.4 / engine53 source)

`list_bundle_decisions` is read-only and snapshot-scoped. Filter by `revision_id` (occurrence or unambiguous revision alias), `source_page_id` or `decision_id`; traverse `cursor` and `reason_offset`/`reason_length` to recover verbatim Unicode reasons within the output budget. Full exports include `bundle-decisions.jsonl`. Stored0.1/0.2/0.3 reports remain readable and retain historical0.3 query envelopes; current0.4 reports use0.4 envelopes.

Desktop drafts/staging use versioned tables/folders. Reports, runs and assets are still shared, so serialize older/newer standalone backend writers against one library; native app instances use the existing exclusive library lock. Old binaries can read supported explicit old snapshots, and reject future-schema snapshots. Immutable report bodies are never downgraded.
