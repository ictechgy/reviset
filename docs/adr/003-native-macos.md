# ADR-003: 네이티브 macOS UI와 격리된 분석·저장 경계

2026-10-19 · 채택. 사용자의 네이티브 앱 요구가 PLAN의 Electron 기본안을 대체한다.

SwiftUI·AppKit이 창·목록·파일 선택·메뉴를 제공하고 PDFKit이 원본 PDF를 표시한다. WKWebView, Electron, React를 제품 런타임에 사용하지 않는다. TypeScript의 검증·분석·SQLite·query·export·MCP는 기존 엔진을 재사용한다. Node를 `Contents/Helpers/node`, 번들 엔진과 lockfile 고정 운영 의존성을 Resources에 포함한다. 로컬 arm64 ad-hoc 서명이며 공증은 하지 않는다.

앱은 동일 보관소의 두 UI 실행을 flock으로 막는다. 요청마다 프로세스를 실행하고 명시적인 보관소 경로와 버전 있는 JSON 프로토콜을 쓴다. stdout은 응답, stderr는 진행 이벤트다. 원문 파싱과 JSON 해석은 UI 스레드 밖에서 수행한다. 분석 결과 전체는 디스크에 stage하고 작은 ID/hash descriptor만 UI에 전달한다. draft hash·stage hash·run 상태를 확인한 별도 commit이 report/run/latest pointer를 한 SQLite 트랜잭션으로 저장한다. commit 시작 전에 취소를 받으면 저장하지 않으며 commit 중에는 취소 버튼을 비활성화한다. 재시작 때 미완료 run을 interrupted로 바꾼다. 하나의 UI가 보관소 쓰기를 조정하며 MCP는 읽기 전용이다.

UI report projection은 페이지 메타데이터만 반환하고 요소·원문 파일은 선택할 때 요청한다. PDFKit document는 현재 소스별로 재사용하고 실제 페이지 렌더는 PDFKit이 지연 처리한다. 변경과 계보는 SwiftUI LazyVStack을 쓴다. 엔진 matching은 전체 점수 행렬을 계산하되 결과 후보는 페이지당 상위 8개로 제한한다. 후보 누락과 PDF 관측 공백을 숨기지 않는다. 1,000쪽 이상의 성능 보장이나 모든 실제 문서의 정확도를 뜻하지 않는다.

PDF 원문 텍스트는 유지하고 glyph별 그림 순서·기하·표시 상태를 부가한다. 관측 취소선 주석과 추정 선·가림을 구분한다. 불확실한 가시성은 단순 텍스트 delta를 보류한다. 원본 구조인 OOXML table과 PDF 격자 추정은 출처가 다르며 동일 셀 의미로 결합하지 않는다. 부분 가림, 클리핑·투명도·마스크·이미지·불확실한 폰트는 coverage gap으로 남긴다. 이 해석기는 PDF 렌더러 전체를 구현한 것이 아니므로 복잡한 문서에서 원본 PDF 화면을 함께 검토한다.

PPTX는 현재 구조 보기 fallback을 명시한다. LibreOffice/독립 Office 참조가 없는 상태에서 고충실도 PPTX 렌더라고 보고하지 않는다. 스캔 OCR·chart 의미·복합 그룹/마스터·PDF 전체 가시성·공개 배포 라이선스는 별도 과제로 유지한다.
