# Document Version Tracker

PPTX와 PDF가 섞인 버전들을 로컬에서 추출하고, 페이지 대응·숫자 변경·이동·중간 삽입/삭제를 원문 근거와 함께 보존하는 프로젝트입니다. 현재는 **첫 구현 체크포인트**이며 데스크톱 앱과 배포본은 아직 없습니다.

Node.js 24 이상이 필요합니다. 이 소스 체크아웃에서는 TypeScript 실행에 개발 의존성 `tsx`를 사용합니다. 모델 계정, API 키, LibreOffice 없이 합성 데모와 MCP 검증을 실행할 수 있습니다.

```sh
npm ci
npm run fixtures
npm run check
npm run cli -- analyze --manifest tests/fixtures/generated/forward/manifest.json
npm run cli -- query --project prj_forward --tool list_changes --args '{"kind":"text_modified","max_output_tokens":8000}'
npm run cli -- export --project prj_forward --out artifacts/forward
```

`artifacts/forward/history.md`에서 `100 → 120 → 110`과 중간에만 존재했던 페이지를 확인할 수 있습니다. `report.json`, `manifest.json`, `changes.jsonl`, `pages.jsonl`, `elements.jsonl`, `revisions.json`, `lineages.json`, 페이지별 Markdown도 생성합니다. 생성된 fixture·원본 캐시·결과는 Git에서 제외합니다.

기본 저장소는 `.docver/`입니다. 모든 CLI 명령에 `--store PATH`로 별도 저장소를 지정할 수 있습니다. 원본 파일을 덮어쓰지 않습니다. 테스트는 새 임시 폴더를 만들고 종료 시 지웁니다.

## 자신의 합성 문서 입력

다음 manifest를 작성하고 `analyze --manifest manifest.json`을 실행합니다. 파일 경로는 manifest 위치 기준입니다. 배열 순서가 버전 순서이며 각 버전은 파일 하나만으로 유효합니다.

```json
{
  "project_id": "prj_example",
  "title": "합성 발표자료",
  "revisions": [
    {"label": "초안", "files": ["v1.pptx"]},
    {"label": "검토", "files": ["v2.pdf"]},
    {"label": "수정", "files": ["v3.pptx", "v3.pdf"]}
  ],
  "mapping_decisions": []
}
```

한 버전에 PPTX와 PDF를 하나씩 넣으면 선택적 bundle입니다. 숨김 슬라이드가 있을 수 있으므로 페이지 번호로 연결하지 않고 텍스트 대응을 계산합니다. 두 원문의 내용이 다르면 `bundle_inconsistent`를 기록하며 양쪽 관측을 보존합니다. 두 PDF 또는 두 PPTX를 한 버전으로 묶는 것은 거절합니다.

`list_revisions`의 `revision_occurrence_id`로 버전의 특정 등장을 선택하고, `list_pages` → `get_page` → `get_element`/`get_evidence` 순서로 원문을 읽습니다. 같은 파일을 여러 번 넣으면 revision ID는 같아도 occurrence와 관측 ID는 다릅니다.

`list_changes`는 `history`, `adjacent`, `range_net`을 지원합니다. `history`는 모든 인접 이벤트를 유지하고, `range_net`은 `from`/`to` occurrence의 순변경을 계산합니다. 점수는 검증된 확률이 아닙니다. 복제·분할·병합 후보는 `needs_review`로 남습니다.

현재 사용자 수정은 manifest의 `mapping_decisions`에 `from_page_id`, `to_page_id`, `action: "link" | "unlink"`, `reason`을 넣고 재분석합니다. 인접 버전 사이의 1:1 수정만 지원하며, 분할/병합 확정과 UI 편집은 다음 단계입니다. 과거 report는 유지됩니다.

## 읽기 전용 MCP

실행 전에 CLI로 보고서를 만듭니다. 클라이언트 프로세스의 stdout에는 JSON-RPC만 있어야 하므로 직접 실행하거나 `npm run --silent mcp`를 사용합니다.

```sh
node node_modules/tsx/dist/cli.mjs apps/mcp/main.ts --store .docver --project prj_forward
```

클라이언트 설정 예시입니다. 아래 경로는 체크아웃과 Node 실행 파일의 절대경로로 바꿉니다.

```json
{
  "mcpServers": {
    "docver": {
      "command": "/absolute/path/to/node",
      "args": [
        "/absolute/project/node_modules/tsx/dist/cli.mjs",
        "/absolute/project/apps/mcp/main.ts",
        "--store", "/absolute/project/.docver",
        "--project", "prj_forward"
      ]
    }
  }
}
```

공개 프로젝트는 시작 시 `--project`로 고정합니다. 여러 번 지정할 수 있습니다. 서버는 SQLite를 실제 읽기 전용으로 열며 import·재분석·쓰기·셸·모델 도구가 없습니다. SDK 1.32.1의 기본 협상 버전은 `2025-11-25`이며 호환 클라이언트의 이전 버전도 SDK가 협상합니다.

도구와 resource 계약, 출력 한도와 원문 분할 방법은 [MCP 계약](docs/schemas/README.md)에 있습니다. 최초 `latest` 조회에서 받은 고정 `report_id`를 후속 호출에 사용하세요. 재계산 후에도 옛 report와 근거 URI가 유효합니다.

## 렌더링 실험과 현재 한계

```sh
npm run spike
npm run cli -- preview --file tests/fixtures/generated/forward/v2.pdf --page 2 --out artifacts/preview.png
```

`spike`는 한글·혼합 폰트·도형·투명도·표·차트·회전 텍스트가 있는 6쪽 PPTX, 숨김 3쪽, 독립 PDFKit 기준 PDF와 PNG, 환경·한계 보고서를 만듭니다. 현재 장비에는 LibreOffice가 없어 PPTX 변환을 검증하지 못했습니다. 설치된 변환기를 실험하려면 `DOCVER_SOFFICE=/path/to/soffice npm run spike`를 사용합니다. 자동으로 외부 프로그램을 설치하지 않습니다.

합성 PDF 생성은 macOS AppleGothic을 기본으로 사용합니다. 다른 환경에서는 `DOCVER_FIXTURE_FONT=/path/to/korean-capable.ttf`를 설정하세요. 폰트는 저장소에 포함하거나 재배포하지 않습니다.

- PPTX: 직접 작성된 텍스트·좌표·노트·숨김 상태·이미지 hash를 추출합니다. 마스터/레이아웃 상속과 그룹 변환은 미지원이며 좌표 한계를 기록합니다. 회전 도형의 bbox는 근사값입니다.
- PDF: 텍스트 레이어·회전/크롭 viewport 변환·요소 bbox와 PNG 미리보기를 추출합니다. 읽기 순서는 추정이며 유인물 판별은 미구현입니다.
- 스캔 PDF는 원문 텍스트를 만들지 않습니다. OCR과 시각 영역 diff는 미구현입니다. 텍스트가 관측되지 않는 구간은 삭제·숫자 수정으로 채우지 않습니다.
- 현재 diff는 페이지 계보와 텍스트 중심입니다. 개체별 정밀 계보, 이미지·레이아웃 delta, 자동 재등장 연결, 분할/병합 확정, 작업 worker/복구 UI는 미구현입니다.
- PPTX 렌더 충실도, 독립 Office 참조와의 픽셀 오차, 대규모 정확도·성능 목표는 미검증입니다. `.ppt`는 지원하지 않습니다.
- 입력당 50 MiB, PDF 1000쪽, PPTX ZIP 전체 비압축 100 MiB/part 20 MiB 제한이 있습니다. 분석 취소는 버전 경계에서 협력적으로 처리합니다.

단계별 현황과 검증 명령은 [PROGRESS.md](PROGRESS.md), 설계 기준은 [PLAN.md](PLAN.md), 구현 결정은 [ADR-001](docs/adr/001-engine.md)과 [ADR-002](docs/adr/002-rendering.md)를 참고하세요.

공개 라이선스는 G5 결정 전입니다. 현재 패키지의 `private`/`UNLICENSED`는 배포 보류 상태를 나타냅니다. 의존성 라이선스는 [목록](docs/dependencies.md)에 기록했습니다.
