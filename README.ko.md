# Docver

[English (기준 문서)](README.md) · 한국어

이 문서는 한국어 번역입니다. 내용이 다를 경우 영어 README를 기준으로 합니다.

**문서의 변경 이력을 원문 근거와 함께 읽는 네이티브 macOS 앱.**

Docver는 여러 버전의 PPTX·PDF와 XLSX·ODS·CSV를 비교합니다. 사람은 원문을 나란히 보고, AI는 같은 고정 보고서를 읽기 전용 MCP로 조회합니다. 문서를 가져오고 분석하는 데 계정·API 키·클라우드 업로드가 필요하지 않습니다.

예를 들어 `초안.pptx → 검토.pdf → 최종.pptx`에서 매출이 `100억 → 120억 → 110억`으로 바뀐 과정과 각 버전의 원문을 확인할 수 있습니다. 처음과 마지막의 차이뿐 아니라 중간에 추가됐다가 사라진 내용도 이력으로 남깁니다.

> **개발·검증 중인 프로젝트입니다.** 현재 GitHub에서는 소스에서 빌드하는 경로를 제공합니다. 검증한 로컬 설치본은 Apple Silicon Mac용이며 공개 설치본 배포·공증·다른 Mac 설치 검증은 남아 있습니다. 프로젝트 라이선스도 아직 확정하지 않았습니다.

## 실제 화면

### PPTX·PDF 비교

![PPTX와 PDF를 나란히 보고 숫자 변경의 전후 원문과 근거를 확인하는 Docver 화면](docs/images/document-comparison.png)

5버전 합성 데모에서 `100억 → 120억`의 숫자 변경과 해당 원문 근거를 확인하는 화면입니다. 왼쪽은 PPTX의 LibreOffice 변환, 오른쪽은 원본 PDF입니다.

### 스프레드시트 비교

![이전 A2와 이후 A3의 셀을 나란히 표시하고 저장값과 행 이동 근거를 확인하는 Docver 화면](docs/images/workbook-comparison.png)

이전 `A2`와 이후 `A3`의 실제 주소, 저장된 입력값과 추정 행 이동을 표시합니다. 두 화면 모두 합성 데모를 실제 앱에서 캡처한 것입니다.

## 주요 기능

| 대상 | 지원하는 작업 | 해석할 때의 한계 |
| --- | --- | --- |
| PPTX·PDF | 버전별 원문, 숫자·텍스트 변경, 페이지 이동, 중간 이력, 화면 차이 | 형식 간 정보 부재와 추출 실패를 실제 삭제와 구분합니다. |
| 스캔·복합 PDF | macOS Vision 로컬 OCR, 가림·취소선의 표시 상태, 표 구조 추정 | OCR·가림·표 대응은 불확실성을 함께 보존하며 작성자의 삭제 의도를 확정하지 않습니다. |
| XLSX·ODS·UTF-8 CSV | 시트·셀·수식·저장값·기본 서식·숨김·행 이동 비교 | 수식을 재계산하지 않습니다. CSV는 문자열로 읽고 고급 Excel/Calc 개체는 별도 한계로 표시합니다. |
| 사람의 검토 | 페이지 연결·해제·분할·병합, 같은 버전 PPTX와 제공 PDF의 대응 수정 | 사용자 연결은 참고용이며 렌더 충실도를 보증하지 않습니다. |
| AI·내보내기 | 고정 보고서 JSON·JSONL·Markdown, 특정 버전 조회, 변경 근거·이력의 읽기 전용 MCP | AI는 원문을 지시가 아닌 데이터로 취급하고 고정 보고서 ID를 인용해야 합니다. |

UI는 **SwiftUI·AppKit·PDFKit**, 공통 엔진은 TypeScript와 SQLite를 사용합니다. PDF는 PDFKit으로 표시하고 PPTX 미리보기는 동봉 LibreOffice 변환 또는 사용자가 함께 제공한 PDF를 사용합니다.

## 소스에서 시작하기

### 준비

- Apple Silicon Mac. 앱의 빌드 대상은 macOS 14 이상이며 현재 실행 검증 환경은 macOS 27.0.1입니다.
- Node.js 24 이상과 npm.
- Xcode 또는 Command Line Tools의 Swift·C 컴파일러와 macOS SDK. 현재 검증에는 macOS 27.0 SDK를 사용했습니다.
- 빌드 시 npm 의존성 설치와 첫 빌드의 LibreOffice 다운로드를 위한 인터넷 연결.

```sh
git clone https://github.com/ictechgy/docver.git
cd docver
npm ci
DOCVER_APP_NAME=Docver-Local.app npm run mac:build
open release/Docver-Local.app
```

빌드는 고정한 LibreOffice를 내려받아 SHA-256·TDF 서명을 확인한 뒤 앱에 포함합니다. 앱에는 Node 실행 파일과 운영 의존성도 포함하므로 **빌드한 앱 실행에는 별도의 Node 설치가 필요하지 않습니다**. 분석은 로컬에서 수행합니다.

패키징에 쓰는 Node는 시스템 dylib에만 연결된 실행 파일이어야 합니다. 빌드가 `Node links a non-system dylib`로 중단되면 `otool -L "$(command -v node)"`로 연결을 확인하고 이 조건을 만족하는 Node 실행 파일을 사용하세요. Vision API를 컴파일하지 못하면 Xcode/SDK 선택과 버전을 확인하세요. [의존성·패키징 기록](docs/dependencies.md)에 세부 조건이 있습니다.

### 앱 사용

1. 문서는 **문서 버전 가져오기**(`⌘O`), 스프레드시트는 **스프레드시트 버전 비교…**(`⌘⇧O`)로 엽니다. 파일 순서를 버전 순서로 지정합니다.
2. PPTX 또는 PDF 하나만으로 문서 버전이 성립합니다. 같은 버전의 PPTX와 PDF를 함께 묶는 것은 선택 사항입니다.
3. 이전·이후 버전과 페이지 또는 시트를 고릅니다. 문서는 **비교**와 **전체 이력** 탭을 전환하고, 스프레드시트는 **두 버전 순변경** 또는 **구간 전체 이력**을 선택합니다.
4. 변경을 선택해 전후 원문과 근거를 읽습니다. 스프레드시트의 긴 원문은 이어 읽기로 확인하고 조회 실패 시 다시 읽을 수 있습니다.
5. **AI·내보내기**에서 고정 보고서를 내보내거나 해당 프로젝트의 MCP 설정을 복사합니다.

앱의 **5버전 합성 데모**와 **3버전 엑셀 데모**로 직접 확인할 수 있습니다. 문서 집중 모드는 `⌘⌥F`, 근거 패널은 `⌘⌥I`입니다.

가져온 원본은 `~/Library/Application Support/Docver/library/`에 복사하며 사용자가 선택한 원본을 덮어쓰지 않습니다. 분석을 다시 해도 과거 고정 보고서는 별도로 보존합니다.

## CLI와 MCP

위 앱 빌드를 마친 소스 폴더에서 실행합니다.

```sh
# 합성 문서 생성 → 분석 → 변경 조회 → 내보내기
npm run fixtures
npm run cli -- analyze --manifest tests/fixtures/generated/forward/manifest.json
npm run cli -- query --project prj_forward --tool list_changes --args '{"kind":"text_modified","max_output_tokens":8000}'
npm run cli -- export --project prj_forward --out artifacts/forward
```

CLI 저장소 기본값은 `.docver/`이고 `--store PATH`로 바꿀 수 있습니다. 문서 manifest의 `revisions` 배열 순서가 버전 순서입니다. 스프레드시트 CLI는 `workbook-analyze`, `workbook-query`, `workbook-export`를 제공합니다. [스프레드시트 계약](docs/SPREADSHEETS.md)을 참고하세요.

MCP는 분석·수정·셸 실행을 제공하지 않는 프로젝트 범위의 읽기 전용 서버입니다. 문서와 스프레드시트의 특정 버전 내용, 중간 변경, 전후값과 근거를 조회합니다. 앱이 만든 설정은 동봉 Node·서버를 가리키므로 앱을 이동하면 설정을 다시 복사하세요.

MCP로 조회한 원문은 연결한 AI 클라이언트로 전달되며 해당 클라이언트의 데이터 정책이 적용됩니다. 클라우드 모델을 연결하면 조회한 내용이 외부 서비스로 전달될 수 있습니다.

AI에게는 다음처럼 요청할 수 있습니다.

> 이 프로젝트의 매출 전망 변경 이력을 찾아줘. 각 변경의 버전과 페이지 또는 셀 주소, 고정 보고서 ID를 근거로 제시하고 OCR·대응 추정의 한계도 알려줘.

`latest` 조회는 응답에서 고정 보고서 ID로 해석합니다. 후속 조회와 인용에는 그 ID를 사용하고, 원문은 `next_cursor`와 텍스트 continuation을 끝까지 읽어야 합니다. 연결 방법과 조회 예시는 [MCP 가이드](docs/MCP.md)에 있습니다.

## 지원 범위와 한계

- `.pptx`, `.pdf`, `.xlsx`, `.ods`, UTF-8 쉼표 CSV를 지원합니다. 구형 `.ppt`·`.xls`, 암호화 파일은 지원 범위 밖입니다.
- PDF의 취소선 주석은 관측 사실로, 납작해진 선·박스 가림·화면 OCR의 대응은 추정으로 구분합니다. 가림·OCR 누락을 의미상 삭제로 단정하지 않습니다.
- PDF 표는 원래 PPTX 셀 식별자를 복구한 것이 아닙니다. Vision 문서 표 구조는 macOS 26 이상에서 사용하며 이전 지원 OS에서는 일반 OCR과 미지원 상태를 제공합니다.
- 수식·매크로·외부 링크를 실행하거나 재계산하지 않습니다. 저장된 계산 결과는 누락되거나 오래된 값일 수 있습니다.
- 모든 문서의 완벽한 OCR, PowerPoint와 픽셀 단위로 같은 렌더링, 차트·피벗·고급 서식의 완전한 재현은 달성하지 못했습니다. 글꼴 대체·관측 공백·불확실성을 함께 표시합니다.
- 매크로/OLE·지원하지 않는 임베디드 개체·외부 리소스가 있는 PPTX는 LibreOffice 변환을 보류합니다. 구조 보기나 별도로 제공한 같은 버전의 PDF에서 확인할 수 있습니다.
- 문서는 파일당 512 MiB·PDF 1,000쪽·프로젝트 100버전, 스프레드시트는 파일당 64 MiB·보고서 합계 50만 관측 셀/10만 변경/256 MiB 등의 한도가 함께 적용됩니다. 상한은 처리 시간·메모리·정확도 보장이 아닙니다. 세부 조건은 [스프레드시트 계약](docs/SPREADSHEETS.md)을 참고하세요.

## 개발과 검증

```sh
npm run build   # TypeScript 검사
npm test        # 전체 통합 검사; 네이티브 검사는 macOS 도구 체인 필요
```

테스트 준비 단계는 PDF.js worker의 고정 패치를 적용하고 지원 Mac에서는 Vision helper를 빌드합니다. 전체 검사는 OCR·Office·네이티브 검사를 포함해 시간이 걸릴 수 있습니다.

현재 검증 기록은 실행 소스별로 구분합니다. `ba8eae8`에서는 집중 검사 88개와 실제 앱·MCP·이동 ZIP 20개 항목을 확인했고, 전체 회귀 341개는 이전 `600fac9`의 기록입니다. 이는 보편 OCR 정확도나 다른 Mac 설치 인증을 뜻하지 않습니다.

| 문서 | 내용 |
| --- | --- |
| [품질 현황](docs/QUALITY.md) | 검증 결과, 남은 정확도·배포 기준 |
| [최근 개선·검증](docs/WORKBOOK-RECOVERY-2026-10-22.md) | 조회 복구·셀 근거·UI 개선의 고정 소스와 리뷰 범위 |
| [MCP 가이드](docs/MCP.md) | AI 연결, 조회 순서와 출력 예산 |
| [스프레드시트 계약](docs/SPREADSHEETS.md) | 지원 형식, 수식·셀 의미, 처리 한도 |
| [스키마](docs/schemas/README.md) | 고정 보고서와 조회 응답 |
| [네이티브 아키텍처](docs/adr/003-native-macos.md) | 앱·공통 엔진 구조 |
| [의존성](docs/dependencies.md) | 패키징·제3자 구성요소 |

자세한 원시 실행 기록에는 로컬 검증 경로가 포함될 수 있습니다. `.omx/`, `release/`, `output/`, 생성 fixture와 원본 보관소는 GitHub 소스에 포함하지 않습니다. 설계·구현 이력은 [DESIGN.md](DESIGN.md), [PROGRESS.md](PROGRESS.md)에 남깁니다.

## 라이선스

프로젝트 자체 라이선스는 아직 확정하지 않았으며 `package.json`은 `UNLICENSED`입니다. 라이선스가 확정되기 전에는 오픈소스 라이선스가 부여된 것으로 간주하지 마세요. 제3자 구성요소의 라이선스·고지는 각각 별도로 적용되며 [의존성 기록](docs/dependencies.md)에 정리되어 있습니다.
