# ADR-001: 첫 체크포인트의 엔진과 저장 계약

2026-10-19 · 상태: 초기 경로에 적용, 제품 전체 스택 확정 아님

## 결정

공통 TypeScript 모델·쿼리를 CLI, export, MCP가 사용한다. Node.js 24.19.0에서 내장 `node:sqlite`로 보고서를 저장하고, 원본 byte를 SHA-256 asset store에 보관한다. 별도 네이티브 SQLite 빌드 단계를 피할 수 있었고, read-only 연결과 snapshot 재조회가 통합 검증을 통과했다. Electron/React와 데스크톱 worker는 아직 도입하지 않았다.

`packages/schema`의 Zod 모델에서 JSON Schema를 생성한다. bbox는 좌상단 `[x,y,width,height]`이며 범위와 합 제약은 런타임에서도 검사한다. 표준 JSON Schema에는 좌표 합 제약이 표현되지 않아 런타임 검사가 추가로 필요하다.

report ID는 프로젝트·입력 byte hash·버전 순서/라벨·관측·추출기 환경·mapping decision·엔진 버전·스키마 hash를 포함한 canonical 결과에서 결정한다. report 생성시각과 실행시간은 canonical 입력에 넣지 않는다. 생성시각은 SQLite 메타데이터에, 실행은 UUID `analysis_run_id`와 시작/종료·성공/부분실패/실패 상태에 기록한다. 재실행은 같은 report를 재사용한다. 최신 별칭은 마지막으로 보고서를 만든 분석 실행을 따라간다.

동일 byte의 파일은 이름과 경로가 달라도 같은 조건에서 같은 report를 생성한다. 경로는 report·MCP에 노출하지 않는다. revision ID와 타임라인 occurrence를 구분한다. mapping을 바꾸면 새 snapshot을 만들며 옛 report를 수정하지 않는다.

export의 페이지 Markdown 경로는 `content/{revision_occurrence_id}/page-{번호}-{asset hash 접두어}.md`로 정했다. 같은 revision 반복과 bundle 두 원문의 페이지 번호 충돌을 피하고 양쪽 증거를 보존하기 위한 선택이다.

## 검증된 범위

합성 입력의 양방향 형식 전환, `100 → 120 → 110`, 이동+수정, 중간 삽입/삭제, 숨김 정보 공백, 재계산·재정렬·사용자 1:1 수정, CLI/export/MCP ID 일치를 테스트한다. MCP는 실제 SQLite read-only 연결과 stdio 클라이언트로 검증한다.

## 보류

현재 매칭 특징은 숫자를 가리지 않은 원문을 보존하면서 대응용 문자열의 숫자를 자리표시자로 치환한 문자 bigram이다. 전역 최대 가중치 1:1 대응에 임계값 0.58을 적용한다. 후보 임계값은 0.40, 경쟁 후보 점수 차이 0.06 이내는 `needs_review`다. 이미지·시각·배치 특징 결합과 30 타임라인/600페이지 목표 검증 전에는 제품 정확도 수치로 해석할 수 없다.

계보는 현재 페이지 단위다. 엔진 변경·타임라인 재구성 후의 entity alias/supersedes, 사람이 확정하는 다대다 관계, 영속 추출 캐시·작업 큐·스키마 migration은 남아 있다. 이 때문에 M2~M4 전체 완료로 표시하지 않는다. 사용자 문서의 본문 지시문은 데이터이며 코드나 모델 명령으로 실행하지 않는다.

대안인 Python/Rust 엔진과 외부 SQLite 드라이버는 아직 별도 벤치마크하지 않았다. 기본 스택을 바꿀 근거는 이번 체크포인트에서 발견하지 못했다.
