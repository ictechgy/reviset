# 품질 반복 2 · pass11 · 2026-10-19

45e0476(엔진19/helper16)은109검사·실제900쪽56.269초를 통과했고 Claude 범위APPROVE가 단위 우회의 수정을 확인했다. 이후 두 독립 full-diff 리뷰는 `1/2.3`, `1/2,000`, `.5/2`의 일부 정수 분수 토큰이 미지원 비율을 통과시키고 전체/지역 추정 변경에 진입하는 사례를 재현해 BLOCK했다. 이전 승인·차단·QA를 구분하고 output/checkpoints/45e04768에 보존했다.

엔진20/helper17은 완전한 정수 분수 피연산자 경계를 요구하며 숫자/소수/그룹 연속부 앞에서 토큰을 잘라 소유권을 주지 않는다. `.5` 스칼라는 점을 포함한 전체 항목이고 독립 `5` 판독은 충돌이다. `.5/2` 같은 압축 비율은 보류한다. 기존 양쪽 공백 숫자 목록 규칙의 `.5 / 2`, `1 / 2.3`은 두 관측으로 유지하며 실제 수식 의미를 추정하지 않는다. 공통170사례, 전체/지역 비율 음성 대조군, 문장부호/분수 목록/날짜 양성 대조군을 검증했다. 초기 두 목록 기대 오류의 실패 로그는 보존했고 threshold는 낮추지 않았다. focused2통과, `npm run check` **109/109통과, 실패/skip0,72.672초** (`pass11-check-final.txt`). 새 full-diff 리뷰·앱·공개자료·대용량·ZIP을 동일 clean head로 고정한다. 보편적 완벽 OCR와 PowerPoint 엄격 충실도는 아직 OPEN이다.

# 품질 반복 2 · pass10 · 2026-10-19

f262a12(엔진18/helper15)은109개 검사와 전체 독립 코드APPROVE/설계WATCH, 실제900쪽54.750초·600쪽178.022초를 통과했지만 Claude의 범위 REQUEST_CHANGES가 한국어 단위 뒤 기호에서 Swift/TypeScript 검증 차이를 추가 지적했다. `Amount 2원)/ cup olives`를 재현했고 코드 준비와 배포 차단을 분리했다. 이전 리뷰/QA는 output/checkpoints/f262a121 및 해당 pass9 artifact에 보존했다.

엔진19/helper16은 숫자 이웃의 불완전 문자열 추정 대신 숫자 줄 슬래시의 명시적 허용 문법만 적용한다. 완전 분수·날짜·공백 목록·붙은 문자 단위에 속하지 않으면 보류하므로 단위 토큰 끝의 차이로 우회하지 않는다. 비교 숫자 값과 마스킹의 단위 리터럴, 원문·대안·신뢰도는 유지한다. 공통131사례와 한국어 단위 우회의 전체·지역 추정 변경 음성 대조군을 추가했다. focused2통과, `npm run check` **109/109통과, 실패/skip0,71.587초** (`pass10-check-final.txt`). 새 전체 리뷰·실제 앱·공개자료·패키지를 동일 clean head로 다시 검증한다. 지원하지 않는 비율·알파벳 숫자 경로·숫자와 함께 있는 URL·복잡한 수식의 보수적 보류와 보편적 OCR/PowerPoint 충실도 OPEN 상태는 공개한다.

# 품질 반복 2 · pass9 · 2026-10-19

f0af7aa(엔진17/helper14)은109개 검사와 전체 독립 코드APPROVE/설계WATCH를 받았고, 실제900쪽54.915초·600쪽172.802초도 통과했다. 이후 Claude의 범위 REQUEST_CHANGES가 전각/대시 부호와 보이지 않는 한글 채움 문자로 숫자 검증을 우회하는 사례를 지적해 재현했다. 내부 코드 준비와 별도로 배포 준비는 BLOCKED로 기록했으며 이전 QA는 output/checkpoints/f0af7aa0에 보존한다.

엔진18/helper15는 숫자와 슬래시 사이 비문자 접두/접미를 통합 판정하고 Unicode 기본 무시 문자·비공백 제어 문자·명시된 슬래시 유사 문자를 보류한다. Unicode White_Space와 전각 마이너스의 검증 정규화를 두 언어에서 맞추며 원문·신뢰도·대안은 유지한다. 공유90사례, 전각/채움 문자의 전체·지역 추정 변경 음성 대조군, 실제 OCR 세 형태 원문 확인을 추가했다. 지원하지 않는 소수/그룹 비율·문자숫자 슬래시 라벨·ISO 코드 접두 목록도 공개된 음성 대조군으로 남긴다. `npm run check` **109/109통과, 실패/skip0,70.400초** (`pass9-check-final.txt`). 현재 full-diff 두 lane과 Claude, 새 앱/공개자료/대용량/ZIP 검증을 동일 clean head로 다시 고정한다. 제품 전체 완벽 판독/PowerPoint 엄격 충실도는 아직 OPEN이다.

# 품질 반복 2 · pass8 · 2026-10-19

efd8871(엔진16/helper13)은108개 검사를 통과했으나 두 독립 리뷰가 `/+2`, `/½`, `/ .2`의 분자 누락 검증 우회를 재현했다. Claude COMMENT도 통화 기호 목록의 불필요한 보류, 보이지 않는 문자·결합 문자에서의 Swift/TypeScript 차이, 실제 helper 처리 경로의 검사 부족을 지적했다. 해당 head는 BLOCKED이며 원문 리뷰/실패 로그를 보존한다.

엔진17/helper14는 슬래시가 속한 완전한 숫자 토큰·3요소 날짜·명시적 공백 목록·붙어 있는 문자 단위를 구분한다. 그 외 숫자 인접 슬래시는 보류하고, 통화 기호 목록은 유지한다. 공유58사례로 두 언어의 판정을 검증하며 OCR 원문·대안·신뢰도는 바꾸지 않는다. 실제 OCR 첫 검사에서 `1/ cup`의 단위 오판과 테스트의 대소문자 필터 오류가 드러나 모두 수정했다. 실제 `/2`, `1/ cup`, `/+2` 행은 unsupported_notation/consensus=false다. focused4통과, `npm run check` **109/109통과, 실패/skip0,57.793초** (`pass8-check-final.txt`). 새 full-diff 리뷰와 앱/대용량/공개자료/ZIP 검증은 동일 clean head로 고정한다. 숫자 경로/URL·복잡한 요소 사이 순서는 보수적 보류 범위이며 보편적 완벽 판독을 주장하지 않는다.

# 품질 반복 2 · pass7 · 2026-10-19

8084105(엔진15)는107/107검사·900쪽54.743초/RSS815890432bytes·600쪽169.563초/RSS836206592bytes를 통과했지만 독립 설계가 불완전 분수1/,/2의 verified 상태를 BLOCK했다. Claude의 후속COMMENT도 분수→정수 슬래시 유실과 한 요소 안 작은 통화기호/RTL 순서의 보완을 제안했다. 이 head는 최종 승인으로 쓰지 않으며 원문 리뷰/실행 결과를 보존했다.

엔진16/helper13는 불완전 slash 표기를 unsupported로 보류하고, diff의 추정 대응도 분수/정수 종류가 같아야 허용한다. 숫자 토큰화 한 경로에서 종류·값·패턴을 만들며 단위와 source 관측은 유지한다. 원문 요소 내부의 상관된 glyph 논리 순서를 보존하고 요소 사이만 공간 순서로 배치한다. UserUnit0.5/1/2/10의 실제 PDFKit/PDF.js 크기 차이를 재현해 최소 native pixel 여유를 보수적으로 유지했다. 초기 focused4통과 후 숫자 목록 구분자의 전체 회귀 실패1을 재현해 helper13으로 고쳤고 focused3검사도 통과했다. `npm run check` **108/108통과,실패/skip0,70.004초** (`pass7-check-final.txt`). 초기107/108실패 로그는 남긴다. full-diff와 최종 새 앱 QA는 다시 고정한다.

# 품질 반복 2 · pass6 · 2026-10-19

Claude가 pass5의 문구 일치 범위가 주변 줄 전체 또는 OCR로 나뉜 원문 전체를 포함하는 재현을 추가 지적했다. 실제 포함 글꼴 PDF 두 줄과 한 원문 두 OCR 조각에서 확인하고, OCR 대상 안에 중심이 있는 상관된 glyph만 공간 순서로 대조하도록 고쳤다. 원문은 전체 선택을 유지하며 합집합/정확한 문자 일치/8192glyph·256run 예산을 모두 적용한다. OCR 내부 이미지 숫자와 불명확한 원문은 계속 보류한다.

엔진15/helper11은 완전한 vulgar/slash 분수를 위치별 한 숫자 항목으로 검증한다. 혼합 정수·분수는 따로 세고 분모·부호·항목 수 충돌을 보류한다. diff의 항목 수/지역 비교도 같은 경계를 사용하고 단위는 유지한다. 공개 W3C PDF의 분수4행이 실제 교차검증을 통과했다. AppleGothic½ 행 신뢰도0.3과 다른 글꼴의 상충 판독은 확실하다고 올리지 않고 실패/음성 대조군으로 보존한다. 판독 가능한 별도1/2→1/4 스캔의 추정 변경은 통과했다. 테스트의 최초 강제 승격 기대가 잘못됐으며 제품 threshold를 낮추지 않았다.

직전99444dd(엔진14)의 전체102검사/독립 코드APPROVE·설계WATCH, 실제900쪽55.699초/RSS817512448bytes,600쪽190.911초/RSS885702656bytes,공개12자료33쪽+20변형·backend8·SwiftBridge·공개PPTX UI가 통과했다. Claude의 범위 precision 문제를 받아들여 이 head의 release 준비는 BLOCKED로 기록했다. 새 소스는 `npm run check` **107/107 통과, 실패/skip0,57.179초** (`pass6-check-final.txt`). 최초106/107 실패와 잘못된 테스트 기대/원인도 보존했다. full-diff 양 lane과 새 패키지 QA를 다시 수행한다. Agy는 사용량 한도, Grok 코드 검토는 무응답 timeout으로 최종 승인에 포함하지 않는다. 이전 Grok 레이아웃 논의와 Agy의 유효한 범위 리뷰 원문은 별도로 유지한다.

# 품질 반복 2 · pass5 · 2026-10-19

엔진14: glyph outline의 clip 증명은 문서에 실제 포함된 font program만 허용하고, 직사각 clip 안쪽 한 네이티브 픽셀 여유를 요구한다. 미포함 Helvetica에서 PDF.js 대체 외곽선과 실제 PDFKit 화면의 차이가 재현되어 포함 여부를 이름이나 missingFile로 추측하지 않도록 고쳤다. 고정 PDF.js worker의 빌드 시 boolean 전달 패치·정확한 upstream/수정 SHA·report 환경 SHA를 추가했다. 서명된 앱 실행 중에는 worker를 수정하지 않는다.

텍스트 요소 하나의 공백 안 이미지 숫자도 OCR에서 누락하지 않도록 전체 문구 일치와 영역 합집합을 함께 검사한다. 확실한 인접 원문 비교와 미확인 OCR 공백은 동시에 보존한다. 빈 visibility_spans가 관측 취소선으로 통과하는 경로, 인접 줄의 빈 글꼴 여백이 다른 줄을 가린다고 오인하는 경로도 닫았다.

`npm run check`: **102/102 통과, 실패/skip0**, 56.253초 (`.omx/artifacts/quality-loop-02/pass5-check.txt`). 양성 clip/인접 줄의 실제 PDFKit 픽셀 동일성, 잉크 절단 및 대체 글꼴 음성 대조군, worker idempotence/변조·버전 거절을 포함한다. 현재 릴리스 앱/ZIP은 이 소스의 최종 검증본이 아니다. 독립 full-diff 재리뷰와 새 앱 대용량/공개 corpus/이동 실행 검증 뒤 다시 묶는다. 범용 OCR 정확도와 PowerPoint 엄격 픽셀 동일성은 계속 OPEN이다.

# 품질 반복 2 · 2026-10-19

사용자가 완벽해질 때까지 반복하도록 요청했다. review-loop로 알려진 실패를 합격 기준으로 낮추지 않고 재현·수정·재검증한다. 첫 수정 묶음은 읽기 순서만 다른 OCR의 거짓 텍스트 수정, 흐린/점선 내부 경계가 합쳐지는 표, 표 검출 상태 누락, 페이지 전체 OCR 대체로 확실한 원문이 사라지는 문제다.

- 선택된 원문과 OCR을 영역별로 구분한다. 원문·표시 상태·OCR 주 판독과 대안은 그대로 남고, 비교 사용/보류/참고 역할을 별도 필드로 보존한다. 가림·부분 취소선·혼합 상태를 가로지르는 OCR 행은 통째로 보류하며 숨은 과거 OCR층은 비교에 쓰지 않는다.
- 읽기 순서만 바뀐 PDF OCR은 동일 문구/좌표의 완전한 일대일 대응을 확인한 경우에만 의미 수정에서 제외한다. 다른 픽셀은 화면 변경으로, 순서는 공백으로 남긴다. 중복 수량이나 OOXML 편집을 숨기지 않는다.
- 약한 명암/점선 경계는 정형 표를 더 확정하는 근거가 아니라 잘못 합쳐진 후보를 거절하는 근거다. 검출불가·크기/규칙 예산·미확정 경계를 구분해 schema/query/export와 앱에 남긴다.
- 직전 사용자 앱 엔진9의 구간 비교 kernel/matcher를 고정해 새로운 혼합 선택 규칙이 과거 구간 event ID를 바꾸지 않게 한다. 0.1 kernel도 유지한다.

숫자/글자 혼동의 영어 단독 ROI 판독, 다단/혼합 크기 행 순서, PowerPoint 글머리·수직 배치·글꼴 차이는 다음 반복에서 다룬다. 현재 소스/검증 상태는 `.omx/artifacts/quality-loop-02/state.json`과 해당 pass artifact로 추적하며 최종 앱/승인은 새 head에서 다시 고정한다.

# 혼합 크기 행 읽기 순서 보완 · 2026-10-19

Claude가 후속 승인과 함께 작은 지표명 옆 큰 금액의 행 순서 역전을 LOW로 재현했다. 양쪽 세로 중심이 서로의 범위 안에 있을 때 같은 행으로 묶도록 보완하고, 큰 제목 옆 여러 줄·같은 행 미세 흔들림·혼합 크기 KPI 대조군을 함께 유지한다. helper8/엔진9로 새 관측을 구분한다. 직전c2cf28f는91개 검사와 공개12자료33쪽+20변형을 통과했고 코드APPROVE/설계WATCH였으나, 최종 소스는 이 수정까지 포함해 다시 검증한다. AppKit 정규화로 성립하지 않는 endian fixture를 제거한 실패/수정 기록도 보존하며, 미지원 형식 분기 직접 검증을 했다고 주장하지 않는다.

# 최종 소비자·페이지 대응 보완 · 2026-10-19

독립 검토가 문구는 같고 서로 다른 원본 래스터가 재정렬된 경우의1점 동률과 Markdown 이력의 추정 표기 누락을 재현했다. 수동 결정→유일한 원본 페이지→유일한 원본 래스터→텍스트 최적 대응 순으로 고정하며 중복 래스터·파생 PPTX 화면은 자동 확정하지 않는다. 엔진8로 구분하고 과거0.1 kernel은 그대로 둔다. Markdown에도 문구/표시 판정·근거 출처·변경별 공백을 출력한다. PPTX의 원문 좌표와 파생/참조 PDF의 화면 좌표 대응은 아직 검증되지 않아 해당 화면에 원문 bbox를 전이해 그리지 않고 명시한다. 원본 PDF 자체의 근거 강조는 유지한다. 최종 독립 검토와 패키지는 이 변경까지 포함한 full diff로 고정한다. Claude 후속 검토의 큰 글자 옆 여러 행의 순서 역전도 max-height 겹침 기준과 재현 검사로 수정했다. 추가 숫자 충돌·미지원 little-endian 픽셀·untracked 특수 파일도 명시 처리한다. 부분 표 경계 검출 범위는 진한 연속 선으로 한정하며 흐린/점선 경계의 누락 가능성을 기록한다.

# 공개 샘플 corpus 확장 · 2026-10-19

28ae49a의 독립 코드 검토가 부분 가로 경계를 누락해 병합 표를 더 적은 행의 정형 격자로 잘못 해석하는 사례를 재현했다. 후보 행 사이의 실제 픽셀도 검사해 부분 가로 경계가 있으면 격자 복원을 보류하고, 기존 부분 세로 경계 대조군에 가로 경계 대조군을 추가했다. 엔진7로 분리하며28ae의 검토/검사 결과를 새 head 승인으로 재사용하지 않는다. 두 독립 lane은 이후 모델 capacity 오류로 최종 판정을 반환하지 못했으므로28ae 전체 승인으로 집계하지 않는다.

Claude의28ae 코드 검토는 REQUEST_CHANGES였다. 글자만 있는 주 판독과 숫자가 있는 타일 판독의 충돌, 표 값의 취소선/가림 보류, 같은 행의 미세 좌표 흔들림, 충돌과 근거 부재의 상태 구분, 실제 픽셀 범위와 취소선 상태 계산을 보완했다. Agy의 padded bitmap 방어 제안도 반영했다. 벡터 원문과 래스터 표 추정은 method/kind/provenance가 다른 관측으로 보존한다. 공개 샘플의 양성 대조군은 살아 있는 OOXML 요소 안의 텍스트 교체·삽입·제거이며 요소 전체 삭제 검사가 아니다. dirty corpus 식별에는 비무시 untracked 파일과 symlink 자체의 해시도 포함한다.

28ae에서89개 테스트가 통과한 실행 뒤, corpus·600쪽·테스트를 겹쳐 돌린 실행은11개 실패와600쪽 숫자 변경 누락을 기록했다. 실패 기록을 보존하며 원인을 단정하지 않는다. 단독 진단2개는 통과했다. 최종 수정본은 무거운 OCR 검증을 순차 실행해 새 소스/번들 기준으로 다시 확인한다.

사용자가 안전한 공개 샘플로 진행하도록 위임했다. 한국어 독립 PowerPoint 참조를 포함한7개 PDF·5개 PPTX를 HTTPS/고정 SHA로 받았고, 실행 코드·매크로·외부 리소스를 사용하지 않는 로컬 검증 경로를 추가했다. Microsoft의 작은 표 누락을 재현해 완전한 래스터 격자 추정을 보완하고, 반복 숫자의 set 비교를 위치별 양방향1:1 비교로 수정했다. 격자 빈 셀·부분 테두리·음성 대조군, 숫자 중복/상이 판독/좌표, grayscale 취소선·밑줄의 테스트를 추가했다. 외부 리뷰는 이번 계획에서 REQUEST_CHANGES였으며 수정된 최종 코드의 승인으로 간주하지 않는다. 이전3386b15의 전체 리뷰/패키지 기록도 새 source 승인으로 재사용하지 않는다.

# 구간 공백 provenance 최종 수정 · 2026-10-19

Claude가 interval-gap 이유 배열이 match와 공유되는 한 곳을 추가 지적했다. Change 생성 시 이유 배열을 복제해 기존 match와 다른 event의 근거를 변경하지 않도록 수정하고, 실제 3쪽 PPTX/PDF 비교에서 두 경로 모두 오염되지 않는지 검사한다. 최종 승인과 패키지는 이 수정 뒤의 SHA로 다시 고정한다.

# 계약 연결 재리뷰 수정 · 2026-10-19

- dc86fa2의 native response-schema 검사 누락과 historical range matcher/schema-ID 재생 문제를 수정했다. native protocol0.1과 새 envelope schema0.2를 분리하며 Swift Bridge가 실제 번들 backend의 recover/projects 응답을 수락하는 회귀 검사를 추가했다.
- 0.1 출시 kernel은 matching 후보와 schema 상수까지 고정한다. old range의 change kind와 net-ID 입력을 재현하며, 현재 매칭의 exact-source 개선을 과거 report에 섞지 않는다.
- 이전 각 SHA의 BLOCK/REQUEST CHANGES는 보존하고 최종 full-diff 독립 리뷰와 새 번들 QA를 다시 수행한다.

# 두 번째 재리뷰 수정 · 2026-10-19

- c72d372도 REQUEST CHANGES/BLOCK이었다. full-page OCR many-to-one 대응, 같은 숫자 위치 교환의 observed 승격, 동일 textless PPTX 재가져오기의 거짓 add/delete를 추가 수정했다. 이전 판정을 현재 승인으로 사용하지 않는다.
- 같은 source asset/page identity를 우선하며, 전체 OCR도 일대일 대응을 요구한다. 불확실한 image OCR은 삭제로 만들지 않고 읽을 수 있는 raw source 영역은 별도 비교한다. 영역 값의 출처와 영역 대응 추정을 분리한다.
- Cross-format 렌더러 차이는 페이지 지문/충실도 공백으로 남기며 모든 페이지를 화면 변경으로 만들지 않는다. 원문/추정 enum 확장에 맞춰 새 schema0.2.0을 생산하고 old0.1 snapshot 읽기·내보내기를 보존한다.
- c72d372 실제 앱600쪽 cold OCR은 약180초/최대RSS약865MB에서 숫자 변경1건을 찾았다. 최종 bundle은 재검증한다.

# OCR/렌더 리뷰 수정 · 2026-10-19

- 현재 엔진은 `0.2.0-native.ocr-render.10`이다. 검증 중 생성한 미출시 `.ocr-render.1/.2/.3/.4/.5/.6/.7/.8` 보고서는 저장된 history/export를 읽을 수 있지만 range 재계산은 unknown-engine 오류로 보류한다. 0.1 출시 엔진은 보존된 kernel로 계속 재계산한다.
- full-diff 독립 리뷰가 재현한 겹친 숫자 행 오연결, OCR 취소선 근거의 observed 승격, SVG의 외부 로컬 파일 읽기를 수정하고 재현 회귀 테스트를 추가했다. 이전50ef32f 판정은 REQUEST CHANGES/BLOCK이며 현재 수정본 승인으로 사용하지 않는다.
- Claude/Agy의 새 코드 리뷰도 REQUEST CHANGES였다. 파생 PPTX 화면이 OOXML 변경을 누르지 않도록 source/derived 근거를 분리하고, 파일 read/exec 제한, 정확한 공간·숫자 토큰 경고, xref 범위 메타데이터 정규화, 실패 batch 보존, 환경 확인 실패 시 OCR 보류, cold-cache 중복 렌더 생략, streaming timeline hash와 source-buffer 수명 축소, 선형 page-index projection을 보완했다. Grok 코드 리뷰는 timeout으로 무효이며 승인으로 집계하지 않는다.
-50ef32f 실제 앱 기준 스캔300쪽×2가 약197초/최대RSS약862MB로 통과했지만, 수정된 최종 번들은 다시 검증한다. 이는 해당 합성 자료/현재 장비 측정이며512MiB 입력 성능 보증이 아니다.
- PowerPoint 참조의 엄격한 화면 동일성은 계속 미통과다. 최종 검증·리뷰의 정확한 SHA와 raw evidence는 `.omx/artifacts/`와 `release/validation.json`에 남긴다.

# OCR·렌더 품질 보완 · 2026-10-19

사용자가 판독/OCR/PPTX 충실도를 보완할 때까지 계속 진행하도록 요구했다. 현재 변경은 `docs/QUALITY.md`와 ADR-004를 기준으로 한다. 아래 0.1 기록의 "OCR 미지원/PPTX 구조 보기"는 당시 체크포인트이며 현재 구현을 설명하지 않는다.

- Swift Vision/PDFKit helper: 한글/영어, 숫자·부호 재인식, 겹치는 타일, 원본 CropBox/회전, native raster 지문, 이미지 취소선 후보. macOS26+ 화면 표의 행/열/병합 셀 추정.
- 원문·표시 상태와 OCR annex 분리. raw 불확실성을 지우지 않고 별도 추정 비교를 지원한다. 낮은 점수·대안 충돌·OCR 영역 누락은 보류하고, 확실한 숫자 영역은 부분 비교한다. 동일 화면에 텍스트 수정 없음; 이미지/차트/배치 차이는 화면 변경으로 관측한다.
- 실제 PPTX PDF 렌더를 위해 공식 SHA와 TDF 서명을 검증한 LibreOffice를 앱에 포함한다. 시스템 설치는 하지 않는다. 숨김 슬라이드, 페이지 수/비율, 한글 폰트, missing-font/변환 원문 경고, 확인된 bundle의 원본 PDF 우선 표시.
- source bytes를 검증한 임시 사본으로 변환하고, isolated profile/HOME/font cache, IP network 차단, process-group 취소/timeout, Python bytecode 쓰기 방지를 적용한다. 원본·vendor signature를 유지한다.
- 512MiB 파일 상한, 최대16쪽 native batch, 동일 픽셀의 OCR 재사용. report/run/latest와 같은 트랜잭션에서 개별 native page 인덱스를 저장한다. 페이지 source hash는 stream한다.
- 중간 source의 70개 테스트 통과. 최종 새 패키지·300쪽 스캔×2·이동 ZIP·독립 full-diff 리뷰는 정확한 최종 source snapshot의 별도 artifact로 검증한다. source가 바뀌면 이전 승인을 재사용하지 않는다.
- PowerPoint 독립 참조 10덱/26쪽을 확보해 해시를 확인했다. 초기 픽셀 오차는 0이 아니므로 원본 충실도의 최종 합격으로 세지 않는다. 목표 PowerPoint 환경과 실제 문서 corpus의 확장이 남아 있다. `docs/QUALITY.md`에 수치의 의미와 남은 게이트를 기록한다.

이 시점에서 모든 PDF의 완벽한 판독이나 모든 PowerPoint 환경의 픽셀 동일성이 완료됐다고 보고하지 않는다. 실제 개선과 미통과 기준을 분리해 계속 검증한다.

---

# 네이티브 Mac 앱 구현 상태 · 2026-10-19

사용자가 A안을 선택하고 중앙 문서 확대·수백 페이지·진짜 네이티브 앱을 요구하여 초기 Electron 가정을 SwiftUI·AppKit·PDFKit으로 대체했다. 원래 PLAN/HANDOFF는 수정하지 않았다. Claude의 세 시안은 `docs/design/concepts/`에 보존했다. Claude·Grok·Agy의 초기 설계 자문 원문/argv/해시/종료 상태는 `.omx/artifacts/ask-*`에 남겼으며, 설계 자문을 최종 코드 승인으로 취급하지 않는다.

현재 `release/Docver.app`은 실제 실행 가능한 arm64 로컬 ad-hoc 서명 앱이다. Node helper와 lockfile 고정 운영 의존성이 들어 있다. 프로젝트 가져오기·순서 변경·전체 이력·인접/구간 비교·원본 PDF·PPTX 구조 보기·근거 강조·대응 수정·과거 고정 보고서·export·읽기 전용 MCP 설정을 제공한다. 집중 모드에서는 보조 패널/변경 목록을 접고 한 페이지를 창 대부분에 표시한다.

검증:

- `npm run check`: 55개 통합 테스트 통과. 그림 순서/가림/부분 가림/배경·투명도/관측 취소선과 숨김 주석/추정 선과 격자/비가시 OCR/색상/클리핑/비사각형/블렌드/회전·CropBox/표 출처를 포함한다.
- `npm run mac:build`: Swift 네이티브 실행 파일과 Node helper를 빌드하고 ad-hoc 서명·strict verify.
- `node scripts/native-backend-smoke.mjs`: 개발 Node가 아닌 번들 helper와 최소 PATH로 8개 작업 검증. stage 변조/취소·복구/stale draft 거절, 새·과거 report, lazy 원문, export 동일성, 실제 MCP stdio와 DB hash 불변.
- `node scripts/native-smoke.mjs`: 실제 `.app`의 5버전 `[3,4,4,3,3]`쪽 데모, 숫자 변경 2개, 원문 비교·집중 모드·전체 이력 화면. stderr 비어 있음.
- `node scripts/native-smoke.mjs --scale`: 300쪽×3버전 합성 PPTX→PDF→PPTX, 숫자 변경 2개, 300쪽 원문 표시. 약 6초(분석과 UI 대기·화면 저장을 포함한 현재 장비의 관측치). stderr 비어 있음. 결과·화면은 `output/native-*`.

미완료/검증 범위: PPTX 고충실도 렌더와 Office 참조, OCR/이미지·차트 의미, 복합 PDF 가시성 전체 판정, 다양한 실문서 정확도 corpus, macOS 14 실기·다른 장비·접근성 전체 검증, Developer ID/공증·공개 배포·오픈소스 라이선스 확정. PDF 가림은 삭제 의도로 단정하지 않으며 불확실성은 원문과 gap으로 보존한다. 원본 OOXML 표와 PDF 격자 추정은 동일 셀 의미로 합치지 않는다. 1차 코드 리뷰에서 발견한 후보 cap의 비대칭 모호성, MCP의 긴 표시 배열 순회 실패, 이미지 마스크 가림 누락, helper crash/cancel 혼동을 수정하고 회귀 검증했다. Claude/Agy의 클리핑·Form BBox·annotation overlay·복합 선·병합 셀·전체 이력 이동·초기화 race 지적도 반영했다. 표시 상태 이벤트에는 관측/추정 필드를 추가했고 PPTX의 미계산 표시 상태를 PDF의 확인된 보임으로 취급하지 않는다. 사각형/페이지 경계 clip은 내부 글자를 불확실성 없이 통과시키고 복잡한 clip은 gap으로 남긴다. OCR 모드3 텍스트는 화면 검증이 없어 비교를 보류한다. 표 텍스트를 page.text에 포함해 초기 매칭/report ID와 달라진다. Grok 코드 리뷰는 최초 및 축소 packet 재시도 모두 timeout으로 최종 verdict가 없어 승인으로 세지 않는다. 설계 자문 결과만 유효하다. 재리뷰의 두꺼운 곡선 stroke 누락도 수정해 불명확한 paint를 uncertain/gap으로 보존한다. 숨김 OC 레이어의 그림과 text clipping 모드도 확정 가림으로 쓰지 않는다. 관측 취소선은 visible_text에 남기며 전용 표시 이벤트로 기록하고, 보이지 않는 원문층의 변경은 별도 gap으로 알린다. 확정 표시 판정은 일반 fill(Tr0) 및 invisible(Tr3)의 검증된 글꼴 메트릭에 한정하고 fill+stroke/outline/clip 모드는 unverified로 보존한다. PDF.js의 source-over blend는 Normal로 정규화해 일반 Office 계열 gs가 변경 비교를 막지 않는다. 완전히 가려졌거나 관측 불확실성이 있는 페이지의 대응 실패는 확정 추가/삭제 대신 공백으로 보존한다. 0 ascent 등 퇴화한 글꼴 메트릭과 잘못된 matrix를 확정 가시성에 쓰지 않는다. matrix가 없는 경우는 고정한 PDF.js 6.4의 실제 CanvasGraphics/text extraction과 동일한 identity 기본값이며, 알 수 없는 비표준 matrix를 추정하는 규칙이 아니다. 작은 반투명 박스와 짧은 선이 마이너스 기호만 덮는 경우도 보임으로 확정하지 않는다. 소수점·쉼표처럼 잉크 면적이 글꼴 상자의 5%보다 작은 문자도 놓치지 않도록, 후행 paint의 양수 겹침은 보수적으로 불확실 처리한다. 격자 연결이나 작은 겹침만으로 보임을 보장하지 않는다. 글꼴 상자에 걸친 테두리도 잉크와의 분리가 검증되지 않으면 gap이 생길 수 있다. 작은 Square/Redact/appearance가 있는 Link 주석도 같은 양수 겹침 규칙을 적용한다. Redact는 QuadPoints 없이 rect만 있어도 원문 위의 미적용 삭제 의도를 불확실로 남긴다. 분석 API에 노출된 취소선의 작은 겹침·좌표 부재는 충분한 quad 관측과 구분한다. PDF.js가 유효하지 않은 QuadPoints 주석을 표시 목록에서 제외하는 경우까지 지원한다고 주장하지 않는다. 폭 0인 PDF 선은 그려지지 않는 선이 아니라 device hairline이므로 직선·곡선 모두 보수적 면적과 gap을 갖는다. 1.5/1,5의 실제 동일 렌더 hairline 회귀에서도 확정 숫자 변경을 생성하지 않는다. 선의 miter 모서리·cap·shear 범위와 ExtGState의 LW/LC/LJ/ML을 반영하고, 미지원 GS 항목은 글자/영역 루프 공통 allowlist로 불확실 처리한다. 알려진 주석 subtype의 Invisible 플래그는 PDF.js 표시 규칙에 맞추고 Hidden/NoView만 제외한다. 직선 hairline·miter·GS 굵은 선의 동일 렌더 숫자 회귀를 검증했다. 서브픽셀 stroke의 축별 확대를 고정 PDF.js 구현과 맞추고 직선 join은 인접 방향의 각도·miter 한도로 범위를 줄였다. 6pt 여백의 표 셀은 테두리 그리기 순서가 달라도 동일 화면·visible을 유지한다. 초미세 V 선의 추가 HIGH 주장은 독립 24회 PNG 비교에서 잉크 변화 0으로 재현되지 않아 결함으로 집계하지 않는다. 실제 잉크를 덮는 .05pt 선은 직접/GS·비균등/전단 6개 경우에서 불확실로 남는 것을 확인했다. 최종 리뷰 결과는 정확한 snapshot artifact로 별도 기록한다.

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


밀도 검증 추가(481b580 패키지, 현재 장비): PDF 300쪽×2, 쪽당 본문 10줄. 분석 2.488초/최대 RSS 1.123GB, 저장 1.809초/1.486GB, 원문 페이지 요청 0.652초/0.798GB. `output/native-dense/result.json`의 `/usr/bin/time -l` 기록이며 보편적인 자원 상한은 아니다. helper가 요청마다 full report를 파싱하고 원본 hash를 확인하므로 빠른 페이지 이동의 중복 읽기와 메모리 비용은 WATCH로 유지한다. 공개·실문서 성능 보장을 넓히기 전 요청 병합/동시성 제한·page index가 필요하다.


2026-10-19 quality loop3 resumed after user rejected stopping with open quality gates.
Engine28 addresses an actual whitespace-only-font metrics omission and an
embedded later-parenthesis empty-margin overlap. Public Azure raw Foo is now
visible/selected while original F00 OCR remains uncertain; public training
source middle-dot text is visible after exact later-ink footprint accounting.
Seven focused native/clip/unknown-font controls pass, including actual digit
ink preservation and true-overlap/substitute negatives. Full suite is running;
the initial new-test type annotation failure is preserved and corrected. Low-confidence ROI and independent Tesseract experiments are
local under .omx/artifacts/quality-loop-03; not yet product dependencies.
Product perfection and PowerPoint fidelity remain active work, not accepted
residuals or a completion checkpoint.

Engine28 full regression131/131 and public12sources33pages+20variants passed;
selected comparison truth improved24/27→26/27 while primary OCR stayed24/27.
Independent code/architecture and Claude nevertheless blocked engine28 for
a reproduced target-overhang false visibility (native2/659 altered pixels).
Engine29 repairs this using complete pairwise embedded ink with both-side
native-pixel clearance, retaining all other target geometry and raw values.
Nine focused controls pass; full regression/re-review pending. Work continues
on the remaining OCR region and PPTX fidelity; no completion checkpoint.

Engine29 independent code APPROVE/architecture WATCH closed the actual
embedded f-overhang defect; product work stayed active. The training fixture's
later overlapping metric margin belonged to Korean 시, not a parenthesis.
Engine30 now implements the bounded additive ROI path described in ADR004.
Actual W3C primary Pineapple옓/.3 is unchanged; all8 native contexts read
Pineapple with full2058-core-pixel envelope coverage. Pure admission/selection,
canonical SQLite report/native-page reopen and paged evidence/export controls
pass. Current whole-suite regression is running. This is selected inferred
evidence recovery, not corrected primary OCR or whole-document perfection.
PPTX strict pixel fidelity remains an active failure to investigate next.

Engine30 public12source/33page+20variant canonical validation passed with
selected truth27/27 and unchanged primary24/27; independent code and Claude
still blocked it for concrete annex/paging/selection-policy defects. Engine31
repairs those contracts, tightens deletion to an actual opaque-white original
character footprint and keeps both readings. Five pure/canonical/actual-MCP
contract tests pass, including8readings x32tokens x3alternatives through the
real transport and malformed-annex/neighbor-page isolation. Genuine native
Pineapple한 / Pineapple 주스 / Pineapple한글 controls pass. Initial137-test
regression retained a30-second ruled-grid timeout (136pass/1fail); shared
ROI time budget/cancellation and bounded prefix/character work are being
qualified before a new snapshot/review. Product completion stays active OPEN.
A hash-verified official office2pdf0.9.1 CLI is in an ignored, sandboxed local
prototype only; it has not been added as a product dependency or renderer.

The30s ruled-grid failure repeated under parallel test files, while isolated
actual test passed in1.58s; a separate native probe measured24.85s total and
216.6MB RSS. Native test files are now sequential, outer process budget60s/page
and existing cancellation retained; ROI remains12s/page best effort. This is
failure containment/robustness, not a claim of improved throughput. Final
137-case serial run is active; no source approval or completion yet.

Engine31 final serial regression137/137 PASS,0fail/skip/cancel,105.253s.
Runtime source stayed fixed for that run; only these evidence notes followed.
Fresh frozen native positive/public corpus and independent full-base reviews
remain required. Product work continues into actual PPTX renderer comparison.

Engine31 frozen public corpus12sources/33pages+20variants passed, including
final opaque-white character evidence and eight available W3C contexts.
Claude scoped delta approval is retained separately; Grok timed out and Agy
was quota-blocked, neither counts as a review. Independent code review found
a new Unicode component-offset defect and correctly kept31 BLOCKED.

Engine32 dispatches context/empty-character text before validating primary
text offsets. Its actual MCP regression follows returned32-unit cursors when
the same offset splits an unrelated primary emoji, reconstructs both selected
components, and still rejects an invalid primary cursor. Optional document
tables and raster-grid metadata now decode independently: malformed optional
geometry/status cannot erase valid primary OCR or the other structure annex.
Cache replay preserves explicit diagnostics. Five focused contract tests pass;
whole-suite qualification and full-base re-review follow.

Sandboxed office2pdf0.9.1 prototype completed10decks/26pages. It reduces some
large pixel differences but regresses other pages and changes broad background
RGB values on some English pages. No automatic renderer replacement or strict
fidelity claim is justified. The binary remains outside the product.

Independent architecture review also found an equal-token-count bypass: a
single-scalar token could disappear while another word split. Engine32 now
tracks the deleted scalar's actual original token and rejects deleting its
sole scalar, even with a matching white-footprint certificate. Space, tab,
nonbreaking-space and newline controls cover that bypass. An earlier32 suite
passed137/137 before this final policy repair; the final suite is rerun.

Engine32 final serial full regression137/137 PASS,0fail/skip/cancel,106.586s.
Runtime sources were fixed for this final run. Optional table/grid isolation,
actual-MCP Unicode component pagination and original-token deletion veto all
pass. Subsequent native packaging and broader fidelity work remain active.
The separate explicit-inset prototype lowers mean RGB error on all26 pages,
but3 gt24 and6 any-difference metrics regress; font-alias prototype regresses
7/10 Korean pages and is not adopted. Standards/default and text-coordinate
checks are required before adopting a renderer-only inset materialization.

Engine32 package clean9418 built with strict local signature verification;
actual5-version native workflow13.604s,900pages55.205s/RSS816037888bytes,
600scans196.653s/RSS864059392bytes PASS. These are source32 package results.
Internal code APPROVE and architecture WATCH remain exact32 evidence; Claude
scoped REQUEST_CHANGES finds zero-cost token-boundary relocation, so combined
readiness stays BLOCKED despite the internal gate. No failed review is hidden.

Engine33 requires context and high-score alternative agreement on aligned
tokens, with exactly one original token carrying an edit; certified partial
deletions and substitutions cannot move boundaries. Aligned certified deletion
remains accepted. Persisted invalid-annex flags now force that annex empty,
preventing contradictory valid tables plus an ignored-metadata diagnostic.
Mandatory page-schema/mode/helper/protocol failures get specific per-page
diagnostics in canonical pages while successful neighbors remain usable.

Renderer-only input preparation materializes omitted ECMA text margins
(l/r91440EMU,t/b45720EMU) for ordinary nonplaceholder slide shapes. Original
assets and raw source semantics are preserved; explicit values, placeholder
inheritance, tables, signed/ambiguous packages and unrelated namespaces are
not rewritten. Namespace-aware byte edits are deterministic, depth/count
bounded and cache policy versioned. The actual Impress control now starts
text at72+7.2pt and implicit/explicit defaults render identically;8focused
contracts passed. The mean-color error improvement on26reference pages is
not strict pixel equality, and3gt24/6any metrics regressed in the experiment.
The alternative renderer/font-alias experiments remain unadopted.

The native source drawer now distinguishes original OCR and inferred context
readings, shows the preserved primary value/score and per-context results,
and does not label withheld OCR as hidden original text. Rows are lazy.
Swift typecheck and current TypeScript build pass; final33 regression, exact
references, native UI/runtime/package and independent reviews remain required.

Engine33 final serial full regression140/140 PASS,0fail/skip/cancel,113.234s;
SwiftUI typecheck PASS. Runtime sources fixed for this run through snapshot;
only evidence notes follow. Fresh frozen independent fullbase reviews, actual
Office/public/native package qualification and weak genuine-Hangul expansion
remain active. Code checks are not treated as task completion.


Engine34 repairs token-local ownership of repeated-character deletion
certificates. Optional OCR/raster/preview cache write failures retain successful
observations and expose precise canonical diagnostics; invalid neighboring
native pages retain their own failure reasons. Focused11 contracts pass,
including actual Impress rendering with a deterministic native-protocol control
(the latter is not a native OCR/raster fidelity claim).

PPTX renderer input policyv7 excludes OPC signature indicators at arbitrary
part paths, keeps extension/MC ancestry opaque, preserves XML BOMs, enforces
post-derivation UTF8/package budgets, and avoids inflating media for unchanged
input. Changed input is prepared in a separately cancellable, minimal-environment
process, with deterministic repacking and source/derived hash, property count
and skip metadata retained in page preview provenance. Originals remain unchanged.
Scope remains canonical slide parts and ordinary slide shapes; layout/master
decorations and nonstandard slide paths are not normalized. Source validation
still includes synchronous work; no general hard latency bound is claimed.

The native evidence drawer now shows language, crop padding, scale, context
status and reading scores; an unverified primary relationship is labelled.
Actual UI/package/runtime qualification remains separate. Genuine low-resolution
Korean controls also exposed three incorrect primary readings at score0.5;
independent local-model experiments contradict all three and correctly read two,
but are not product dependencies or evidence for automatic correction. These
remaining OCR failures keep product completion open after the34 source fixes.

Engine34 final serial full regression143/143 PASS,0fail/skip/cancel,120.509s;
SwiftUI typecheck PASS. Runtime source fixed during this run through snapshot;
only evidence notes followed. Frozen full-base re-review, actual packaged helper
resolution/UI/runtime, fresh Office/public qualification and measured Korean OCR
errors remain separate active gates. The product is not marked complete.


Engine34 clean09b05e72 package built with bundled office-input.mjs and strict
local signature validation. Actual5-version native smoke13.867s and900-page
workflow56.223s PASS, including real packaged conversion from cwd /. These
remain exact34 runtime evidence; working35 OCR changes receive no runtime
credit. Actual600-scan package qualification is running separately.

Engine35 actual borderline diagnostic reuses PNGs verified by SHA against the
stored native render and extends only diagnostic ROI eligibility to natural
score<=0.5. Three correct score0.5 primaries keep mixed-language agreement,
while three incorrect selected Korean readings have spatially matched,
supported-language counter-readings. The working policy adds bounded borderline
context observation after existing weak/ambiguous priority and withholds an
inferred comparison on supported-language disagreement. Original OCR strings,
scores, visibility, alternatives and raw projections remain untouched; no
replacement text is inferred from the veto. Missing/failed/edge-cut contexts do
not supply disagreement. Positive correction admission remains stricter.
Actual production/helper and broader heldout qualification remain required.

Engine34 actual600-scan native workflow190.215s PASS (300+300pages, inferred
100억→120억). Source34 runtime/screenshot/keybinary/backend evidence archived
under output/checkpoints/09b05e72; no35 runtime credit. Independent completebase
code APPROVE and architecture WATCH plus Claude namedclosure APPROVE are retained
separately. Screen Recording permission and native UI automation are unavailable;
expanded drawer OS interaction remains unverified, without blocking other work.

Engine35 actual production helper on the16original low-resolution Korean controls
plus production supplement/Page schema/selection retains7previous correct selected
readings and reduces incorrect nonempty selections3→0 by retaining them unresolved.
All primary line JSON fields and native raster hashes are unchanged; a Swift
NSArray comparison across in-memory CGFloat/decoded NSNumber falsely differed,
so persisted JSON values were independently compared recursively. Initial failed
harness/log is retained. These are bounded controls, not whole-document OCR
accuracy, an automatic correction result or latency qualification. Overall product
work remains open; final35 serial suite and frozen independent reviews follow.


Initial35 full serial regression143/144 PASS,1failure: the new OCR conflict veto
withheld a title; regional diff then missed readable100/120swaps because those
amounts also occurred in distant rows. Failure log retained. Fix permits only
unique bidirectional selected-raster numeric pairs with matching number pattern
and exactly one supported numeric slot to survive a distant same-text veto.
Overlapping/unknown/partial geometry still withholds inference. Events remain
regional/inferred, not semantic entity movement. Native swap and synthetic
unresolved-header/overlapping-peer controls pass4/4; final full run is rerun.

The16 native OCR controls call the actual production DocverVision.process path
including primary/tile/numeric/strike/grid/ROI; the DOCVER_TEST driver bypasses
the stdio wrapper and optional asynchronous document-structure observer. Canonical
supplement/schema/selection are production functions. Full helper protocol and
packaged runtime are tested separately; the bounded result is not a whole-app
or latency certification.


Engine35 final serial full regression145/145 PASS,0fail/skip/cancel,123.992s;
SwiftUI/TypeScript checks PASS. Runtime source fixed for this final run through
snapshot; evidence notes appended afterward. The initial144-case failure remains
separately retained. Native16control selection replay and preserved primary/raster
checks are bounded evidence; fresh prespecified32-case heldout/public/Office/
packaged qualification remain active. Correct Contract review can be withheld
when one contextual crop hallucinates a registered-sign suffix: conservative
recall remains an explicit quality concern, not a claim of OCR correctness.

Actual34bundled bridge page read from cwd/ with minimalPATH retained the full
historical31W3C canonical page (76elements,2ROIannexes). An isolated native
NSHostingView harness uses that exact returned element and the unchanged product
OCR-evidence view; posting a mouse event inside its own window opens the group
and internal bitmap shows all8conditions/languages/scales/statuses/scores. This
is component rendering/interaction plus separate packaged-payload validation;
full packaged OS-input interaction and Screen Recording remain unverified.


Engine35 full-base original approval was superseded by independently reproduced
post-blind addenda: N1 stale admitted-ROI withholding diagnostics (code MEDIUM,
BLOCKED) and N4 page-scoped nonnumeric recall loss from a distant header veto
(architecture MEDIUM,BLOCK). Original reports remain unchanged. Claude35 requests
changes; Grok35timed out with empty output and Agy35quota429 is not review evidence.
Fresh frozen35 public12sources/33pages+20variants canonical/control checks pass,
with recognition misses retained. Frozen35 Office10decks/26pages cold-cache run
in a separate clean worktree matches26page geometries but0strictRGBpages;
max>24changedfraction.0388700,maxanyRGB.651709,meanRGBaverage2.261812.
This remains an active fidelity failure, not pixel-equivalence qualification.

Engine36 derives contextual withholding gaps only after accepted ROI readings
settle final roles. Mixed accepted/unresolved regions retain genuine gaps;
reselection removes only selector-owned stale contextual reasons. Eligible
borderline OCR with no usable supported-language context is withheld while
primary text/score/visibility/raw projections remain unchanged. The native drawer
shows annex-level unavailable/budget/background/empty/failure status even when
no context rows exist. Reference verification uses a run-local cache.

A bounded nonnumeric regional fallback compares short(<=128UTF16)selected raster
lines only in matched PDF pages with the same native environment and verified
geometry/distinctraster. It requires unique bidirectional footprint pairing,
no other overlapping observation, equal token count, exactly one changed token
and at least one unchanged letter-bearing anchor. Existing moved/elsewhere-text,
source/annotation/estimated-source disagreement and numeric guards remain.
Events are location-level region/inferred evidence, not semantic entity identity.
Wraps/joins/insertion,unanchored/multi-token edits and unresolved page matches
remain conservative gaps. Legacy pre-hybrid numeric contracts remain intact.
Ten focused controls pass; initial annotation negative fixture lacked its actual
region evidence and initial test type errors were corrected with logs retained.
Final full-suite/frozen independent review and runtime qualification follow.

Engine36 full serial suite149/149 PASS,0fail/skip/cancel,124.155s. Runtime
source was fixed throughout this final run; only this evidence note follows.
Pure replay of32actual frozen35/helper20 heldout observations through current36
selection retains16correct selected readings and reduces wrong selected3→2.
The two remaining errors have Vision score1.0; no universal OCR accuracy,
fresh native latency, packaged36 or current Office fidelity claim is made.

Engine36 actual clean f876 native build passed strict ad-hoc/vendor signature
verification, bundled dependency-lock parity and8 packaged backend checks
including cancel/recovery, immutable snapshots, export parity and scoped read-only
MCP/unchanged SQLite hash. Actual five-version13.725s,900mixedpages55.294s and
600repeatedscanpages294.195s pass. Last is slower than34's190.215s; it is an
active performance concern, not unique-page p95 qualification. Bundle stayed
frozen36;37working source edits began during600scan without a rebuild.
An isolated actual native OCR-evidence component shows unavailable context
status even with zero rows. Full packaged OS-input interaction remains unverified.

Independent complete original-base36code REQUEST_CHANGES and architecture BLOCK
found own-footprint overlap slivers and split-word reflow false regional edits.
37rejects peers overlapping either own or paired footprint, and uses a bounded
negative-only continuation search for a changed token's prefix/suffix, including
a terminal line-break hyphen. Monotonic nearby boundary tokens may complete up
to3fragments; branch/character/depth budget uncertainty withholds that pair.
It emits an explicit possible-reflow gap with original quotes/boxes, preserving
other independent edits. Native change details now display localized coverage
reasons, previously missing from the drawer.152/152full serial tests pass,
0fail/skip/cancel,122.450s;SwiftUI typecheck passes. Only evidence docs follow.

Unchanged20observer research on32prior native-raster-hash-verified controls at
all natural scores found positive high-score English counterreadings for29/30,
but allscript/bilingual broad disagreement would also lose correct11/25.
All26nonempty fresh primary strings matched;4 exact box comparisons missed
after persisted floating-point roundtrip, and the initial failed harness is
retained. This is diagnostic crop research, not new production eligibility.
Claude/Grok exit0 DISCUSSION_COMPLETE evidence is separate from code approvals.
Grok highlighted dictionary-veto risk; local Tesseract remains ignored research,
with actual Vision-context pixel and dictionary-off tests being prepared.
A prospective480page/20newphrase/3hostfont/8samplingcondition set is preregistered;
no results or accuracy bound claimed. Product completion, high-score OCR,
PPTX strict fidelity, unique-page performance and manual split/merge remain OPEN.

Engine37 complete original-base reviews remain BLOCKED: adjacent fragment
terminal hyphens bypassed conservation (code), and repeated-boundary tokens
like murmur→mur searched only forward despite a valid preceding fragment
(architecture).38normalizes only terminal line-break hyphen marks for every
boundary fragment and searches both applicable orientations with a shared64node
budget; raw strings remain unchanged. Seven regional controls pass, including
both directions, ASCII/soft/Unicode hyphens and distant independent edits.

Prospective480image-only PDF cases (20new literal phrases,3hostfonts,4source
pixel sizes,2gray levels) completed through current20process and actual native
pixel capture. Baseline full-page literal matches218,nonempty not-full-truth79,
empty183. A prespecified negative-only arm using any positive conflicting broad
en-US contextual reading retains218matches, reduces not-full-truth79→22,
raises empty183→240 and withholds0previously full-correct pages. Two-conflict
arm retains218/reduces79→27. Conditions repeat phrases and are correlated;
these are fixture counts, not iid accuracy bounds or per-selected-region errors.
The experiments used8context research calls but evaluated2; no2crop latency
claim.6missing-primary conditions in the old32set and22remaining480failures
are not solved. No pixel-identical native hashes were found in48deliberate
I/l string-pair controls; pixel ambiguity was not established by that probe.

38implements high-score natural pure-Latin nonnumeric counterobservation in the
existing4line/12s budget, after weak/ambiguous and borderline priorities. It uses
only broadpadding.75 en-US contexts at1x/2x. Positive spatial disagreement can
withhold selection; absent/unusable high-score context is not agreement and
does not introduce a blanket new veto. Numeric, Hangul/mixed scripts, observed
source priority, annotation/strike/geometry guards and strict positive-correction
admission remain separate. Primary text/score/visibility are unchanged.
Helper21/engine38 invalidate observation caches. Current full serial155/155PASS,
0fail/skip/cancel,129.751s, plus9focused controls and helper build PASS. Runtime
source fixed throughout final suite; only evidence docs follow. Actual current
480native qualification, frozen reviews, packaged runtime and latency follow.

Pinned localTesseract6 research on22actual Vision-input crop PNGs verifies input
SHA; defaults and all6DAWG-off/user-word-pattern-empty initialization each yield
15correct and identical outputs, including correct29/30but wrong Korean5/7/13/14.
Ten old32cases lack the designated native crop and remain explicit skips. This
does not prove absence of learned language priors or qualify a product engine.
No Tesseract dependency/models are bundled. Claude/Grok discussions are valid
discussions, not source/product approval; Agy's quota failure is not review.


Engine38 actual frozen qualification completed:480prospective correlated fixture
conditions retain218full-page literal matches,22nonempty not-full-truth and240
empty selected pages;all480primary non-ROI fields/native PNG hashes unchanged
from20,and no previously full-correct page lost. This is a bounded count,not
universal accuracy. Actual signed38app5versions13.685s/900mixed55.704s/
600scanpages324.002s/backend8checksPASS. The scan set has300distinct page labels
across two versions and301unique native image hashes,not300 identical pages.
Earlier continuation shorthand calling it repeated scans referred to version
repetition and must not imply an identical-page throughput result. Its slow
borderline mixed-script ROI path remains performance work.

Complete original-base38reviews codeREQUEST_CHANGES (UnicodeLatin presence
gate) and architectureWATCH are preserved separately. ScopedClaude38APPROVE
is not full-base/product approval;Grok timeout and Agyquota are invalid reviews.
39aligns the consumer's Latin presence predicate with UnicodeLatin producer
eligibility;nonASCII-only lower/upper/ligature cases preserve primary/source
priority. Negative-only reflow guards cover terminal Unicode Dash_Punctuation,
soft hyphen and minus marks;raw evidence remains exact.

39also reuses one normalized native image observation for equal-hash/equal-pixel-
dimension pages already rendered by warm-cache lookup. This adds no render
pass to cold/no-reuse paths. Actual representative mismatches and individual
failures trigger independent peer OCR. Nested observations are deep-cloned;
viewport/rotation and operational cache warnings remain page-local. Raster disk
keys/validation include dimensions. Optional-annex availability may be shared
like existing image-cache reuse;no equivalence to every independent stochastic
retry or600scan speedup is claimed. Five deterministic subprocess cases and
actual native three-page numeric/strike/token/raster preservation pass. Initial
fake-test dimension-key collision expectation failure is retained;corrected
5/5pass. Fullserial162/162PASS,0fail/skip/cancel,133.829s;runtime source fixed
through suite and commit,only evidence docs follow. The ignored uniform-tile
prototype preserves88primary/raster pairs but its8.18%median component gain
fails the preregistered10%gate;not adopted. Product remains OPEN for remaining
OCR errors,strict PPTX fidelity,performance and missing manual split/merge.


Complete original-base39 independent code APPROVE/READY and architectureWATCH
returned for exactf25c3bb,96paths/9changed,with separately hashed raw reports.
They do not approve40 or product completion. Both independently closed the
Unicode mismatch and verified grouped failure/clone/progress boundaries.

The38scan cache contains600page records,301unique native PNGs,598mixed-script
borderline title records and4784ROIcontexts. Exactly0.5/nonambiguous mixed
Hangul+Latin cannot receive a positive correction;the consumer rejects mono-
language contextual dissent when either required script is unsupported. An
ignored candidate therefore omits only these unused monolingual contexts.
Preregistered32distinct-page AB/BA paired nativeprocess experiment retained
all32primary numeric/strike/token fields,PNGhashes,currently usable bilingual
contexts,and canonical selected/unresolved/roles/gaps. Median component gain
23.6094%passes10%gate. No app/p95 claim;two warmups and cached-PDF reset each
arm,stdio/optional async structure excluded. Sources,hashes,raw pairs and gate
are preserved under mixed-context-prototype.

40implements that profile as4bilingual contexts,keeping8for weak/ambiguous
positive admission and monoscript borderline evidence,and2for high-scoreLatin.
No primary/confidence rewrite or relaxed correction threshold. Helper22 and
ROIpolicyv4 invalidate native environment caches. Native eligibility boundaries,
actual natural0.5mixed scan and pure counterevidence/admission controls pass.
An independently observed representative also retains its own render-stage
cache warning;peer warnings remain separate and cached warnings stripped.
Fullserial164/164PASS,0fail/skip/cancel,156.114s;runtime source fixed through
suite/commit and only evidence docs follow. Actual current480/app/scale/ZIP
and40complete original-base reviews follow;remaining OCR/PPTX/manual relation
work remainsOPEN. Repeated test/review checkpoints are not product completion.


40actual uninstrumented helper22process+selector480qualification retains
218full-page literal matches/22nonempty not-full-truth/240empty,all480primary
non-ROI and native PNG hashes unchanged,0previously correct lost. However the
complete original-base40architecture review BLOCKS source readiness despite
code-laneAPPROVE: native Unicode White_Space compaction ignoresNEL while TS\s
retains it. Actual frozen supplementation makes a mixed.5 primary TS-ambiguous,
so8contexts admit an existing correction and4lose it. This is a schema-valid
synthetic protocol boundary,not observed Vision NEL output. No40app was built.
Claude40REQUEST_CHANGES also notes parity;its stale-warning hypothesis is not
reproduced because existing writeCache strips flags.41explicitly replays the
independent representative's source/raster caches to verify warning cleanup.

41repairs the comparison-key root contract: native ambiguity compaction and
high-scoreLatin eligibility use the explicit ECMAScript whitespace set. NEL,
180E and200B remain meaningful;FEFF remains whitespace. Shared45fixtures cover
every included codepoint,excluded controls,NFC/NFD,Latin eligibility and default
case conversion. The first native run exposed Swift String.lowercased final
Greek sigma differing from JS;NSString.default lowercasing aligns that context.
Raw primary strings/scores are unchanged. The failed nativeSIGTRAP diagnostic
and initial test-property type error are retained,not counted as passing.
Corrected native controls pass,including actual producer4/8context planning on
real raster with synthetic eligibility metadata and competitive score cutoffs;
these are policy units,not accuracy counts. Actual TSsupplementation reproduces
the8vs4NELcorrection seam. Helper23/ROIpolicyv5 invalidate caches. Fullserial
165/165PASS,0fail/skip/cancel,158.010s;runtime source fixed through suite/commit,
only evidence docs appended afterwards. Current41production480/app/scale and
complete original-base reviews follow. No old approval or performance result
is reused as current41package completion. Remaining product gates stayOPEN.

Claude's native manual-relations design discussion completed separately,
recommending one searchable paired-list sheet with explicit1:1/split/merge/
unlink cardinality,conflict review and every branch page in history. This is
proposed UX advice,not implemented/approved source or a new global design.


41actual480helper23requalification again retained218full-page literal matches,
22nonempty not-full-truth,240empty,all480primary/PNGunchanged and0previouslost.
Nevertheless both full-base41reviews BLOCK: Foundation's dollar anchor accepted
one terminalNEL outside the declared Latin class,and Swift canonical String
equality equated distinct post-lowercase UTF16 keys for5standardLatin composition
pairs. Actual frozen supplementation shows8contexts preserve a one-Hangul-scalar
correction while4lose it. These are interface boundary controls,not observed
Vision emissions. The pipeline intentionally withheld41app before build;its
exit1is that guard,not a native480orbuild failure. Existingrelease remains38.

42uses strict whole-string anchors and exactUTF16 comparison of compact keys.
The four-context mixed profile additionally requires every competitive
alternative's NFC raw input to be literally identical to the primary;otherwise
all eight contexts remain. This makes consumer nonambiguity a direct guarantee
independent of cross-runtime casing/Unicode-version differences. Harmless case
or spacing alternatives conservatively retain8.61shared cases now include
terminalNEL/CRLF/FEFF and two-input literal-key equality,with exactUTF16 expected
outputs. Five composition-pair native producer8context controls and actualTS
supplement8positive/4negative controls pass. Initialpurefixtureused the wrong
monolingual language for a Hangul-dominant line;corrected fixture passes and
failed log is retained. Focused native guard pass10.618s. Helper24/policyv6
invalidate caches. Fullserial165/165PASS0fail/skip/cancel,158.408s;runtime fixed
through suite/commit,only evidence docs follow. Current42native480/app/latency
and complete original-base reviews follow;no currentpackage/perfection claim.


### 2026-10-19 engine43 working — conservative literal raw profile guard
- Claude42 focused key-contract review: valid exit0 REQUEST_CHANGES. Adopted raw UTF16 equality instead of native NFC equality for four-context eligibility; unknown alternatives containers also retain eight contexts. Unicode-version example was hypothetical, not an observed installed-runtime disagreement or OCR accuracy result.
- Helper25/policyv7 invalidates profile caches. Native boundary tests cover precomposed/decomposed and malformed containers. Engine43 typecheck PASS; serial full/native validation pending frozen42 app qualification completion.
- Independent complete original-base42 code and architecture lanes found no blocker at their depth (code APPROVE, architecture WATCH). This does not override Claude's narrower guard finding or mark product complete.
- Actual frozen42 native480:218 full-page correct,22 nonempty-not-fulltruth,240empty;0 previously correct lost;all480 primary/PNG unchanged. Actual frozen42 600-scan app PASS269.908820s,sampled driver-treepeak1121.125MiB;single-run workload evidence only,not p95/universal performance. Other42 app jobs ongoing. Manual split/merge and PPTX fidelity still open; continue implementing.
- Engine43 full serial `npm run check`:165/165 PASS,0fail/skip/cancel,161429.145417ms. Native producer checks exercised raw-distinct NFC and malformed-container8-context guards. Runtime source held fixed during suite. No43app/native480claim; latest actualapp42 jobs allpass (600scan269.908820s,5versions14.831088s,900mixed57.370262s,backend13.939517s), continuous artifact hashes preserved.


### 2026-10-19 engine44 working — native manual split/merge and directed lineage
- Added canonical typed1:1/split1:N/mergeN:1 groups, reasons preserved verbatim, at most32 members, deterministic topology IDs/order. Engine/CLI validate primary-source membership, adjacent occurrence scopes, duplicate/conflicting/negative decisions. Legacy pair decisions remain accepted.
- Desktop rewrites complete affected groups atomically in BEGIN IMMEDIATE. Residualstars3→2→1→0 normalize; displaced accepted pairs get unlink tombstones. Mapping uses latest-report/draft CAS. Analysis stages against an input hash and validates it again inside report/pointer commit; cancellation leaves pending dirty draft and immutable old report.
- One structural event per split/merge; branch members do not enter ordinary pairwise text/move/appearance/visual or unmatched add/delete paths. Every member is addressable with its own qualified evidence; topology does not confirm text deletion/replacement. New schema0.3 reads stored0.1/0.2; exact42/43 range kernels archived alongside1/9 kernels.
- New range calculation propagates endpoint bitsets through directed accepted edges, never an undirected-family Cartesian product. Structural family summaries explicitly use directed_reachability; list_page_relations supports bounded graph/path/substring queries, and synthetic range evidence can be recovered with change_id + from/to. Full edges/groups exported inJSON/JSONL/Markdown.
- Claude UI design discussion implemented as one paired native searchable multi-selection List sheet, counts/reason/displaced edges before singleApply, current group selection/reason prefilled, every branch history button and qualified evidence navigation. Search honestly labels compact summaries. NativeSwiftUI/AppKit/PDFKit only.
- Targeted10tests PASS: actual3versionPPTX split→merge+independent100→120, primary/adjacent/duplicate/max32/negative boundaries, residual stars+tombstones, phantomB→F DAG,64endpoint high-bit controls, multibyte pagination/full export/storage, stale2connection/CAS/cancel/reopen/history immutability, archived42/43 IDs. TypeScript and native Swift typechecks PASS; full suite/build/app screenshots still pending.
- Adopted nonblocking Claude43 comments as additional helper26/vision-roi-v8 hardening: unknown alternatives defaultnil; high-score Latin pruned profile also requires literal raw competitive agreement. When equality cannot be proven, retain all8 contexts rather than omit ROI. New actualproducer controls cover high-score exact2 vs differentraw8. Source43 reviews APPROVE/WATCH and focusedClaudeAPPROVE are historical43 scope;44 reviews pending.
- Actualapp42 remains frozen and fully qualified for its4jobs, not current44. ZIP27 remains stale. Product OCR false/withheld cases and strict PPTX fidelity remain OPEN; keep working, do not end at this checkpoint.
- First44 full suite:174/175PASS,1failure (159484.254ms): existing MCP history test assumed all3rows fit one response. Added topology metadata correctly produced a next cursor. Test now follows every actual MCP cursor, asserts byte budgets and exact3occurrenceIDs. A separate backward-compatibility check found strict new-reason validation could reject old long/whitespace reasons: stored reports/drafts and legacy manifest decisions retain the old contract; only new UI/API decisions and new relation groups use the bounded reason rule. Native/helper and other174tests passed; rerun pending these fixes.
- Final44 serial `npm run check`:176/176PASS,0fail/skip/cancel,136678.111584ms. Runtime held fixed during the complete rerun. Native producer high-score raw guard, actual Swift Bridge schema0.3 and actual MCP history cursors passed. Targeted11manual/legacy tests also PASS; both native app Swift typechecks PASS. This is a source qualification gate; packaged44 app/native480/current independent corpus/Office/ZIP/reviews remain pending.


### 2026-10-19 engine45 working — synthetic evidence aliases and native query settling
- Complete44 architecture lane independently reproduced a new range evidence boundary: revision_id aliases entered net-ID hash preimages while events returned canonical occurrence fields; get_evidence with those event fields failed. Current45 IDs now canonicalize resolved occurrence endpoints. Archived44 and older raw-selector IDs stay unchanged; bounded valid alias combinations recover their evidence. Actual12targeted tests PASS including alias→returned endpoint→evidence, historical44 preimages, repeated-asset occurrences and prior42/43 IDs.
- Clean packaged44 built and signed successfully, but actual native manual workflow failed twice at MANUAL_EVENTS. SQLite contains all3immutable reports; latest has exactly1split,1merge,1numeric edit. MainView tab.onChange issued an identical range request while the awaited call was pending, invalidating its generation before the later response settled. Other44app jobs and native480 were withheld after that failed gate; no app44 completion claim.
- Native model now shares a pending task for the same immutable query key, waits for its response, preserves a valid current selection, and exposes loading state while rejecting stale responses. Inspector/selection actions explain or respect pending loading. Actual smoke now deliberately overlaps same-range awaits and captures the paired native sheet, branch navigation and no-write dismissal. Large-page app smoke will also capture the preselected p.240 sheet.
- Valid scoped Claude44 UI review REQUEST_CHANGES: adopted always-visible selected-page chips, first-selection scrolling, filtered-out selection count, explicit cardinality/reason/limit validation, multiline reason editor/count, disabled-action explanations and removal icon. Rejected its claim that unlinking an absent edge is a no-op: this is an intentional negative tombstone preventing automatic relinking; UI now explains this and one-pair-at-a-time behavior. No all-provider/source approval inferred. Minor contradictory0.2 schema prose corrected to0.3.
- New TypeScript and nativeSwift typechecks PASS. Full45 regression/app/review/native480/public/Office/ZIP qualification pending. Common matching/diff/DAG helper sources are exact44bytes;45 changes query ID/evidence semantics plus native UX. Product remains actively OPEN.
- Engine45 full serial `npm run check`:177/177PASS,0fail/skip/cancel,133310.493291ms; runtime held fixed. NativeSwift app typecheck PASS. Complete44 reviews finalized code COMMENT/READY and architecture BLOCK(R1alias-evidence), plus actual44appMANUAL_EVENTS gate failed twice; all belong to44. New45 fixes require fresh review and actual packaged rerun; no45app/native480 claim yet.

### 2026-10-19 native46 working — actual Claude visual findings and superseded range work
- Frozen45 actual app all5 jobs PASS with continuous bundle hashes: manualrelations23.431294459s, backend13.322671375s, five14.544053833s,600distinctlabeledscanpages249.072209334s,900mixed59.313157291s. Sampled driver-tree peaks701.765625/361.78125/433.015625/1133.90625/1240.71875MiB respectively; not p95 or memory ceiling. Native manualchecks exercise realmodel/sheet, not fullOSinput.
- Actual45 helper26 canonical480:218fullcorrect/22nonempty-not-fulltruth/240empty, all480primary andPNG unchanged,0development/actual42correctlost. Correlatedsyntheticconditions, no universalaccuracy claim. Public45 qualification12sources33pages20variants completed, selectedOCRmissesretained. IndependentPowerPoint45 ten decks26pages allgeometrymatches,0strictpixelidentity,max>24deltafraction0.03887002743484225/maxanyRGBfraction0.6517086762688614/meanRGBerror2.261812194435651. Standalone fidelity remainsOPEN.
- Completebase45 independent lanes:codeCOMMENT/READY,architectureWATCH, no sourceblocker; low32-pagecaptionis per-side. Own frozenalias/evidence controls preserve60historicalIDs/recover90events. Actual qualification is separately parent-owned; source review is not productcompletion. Evidence45synthesis preserves exactreports/runtimebinding.
- Claude reviewed three actual45nativecaptures via audited multimodalstdin (focusp300/manualsplitmergehistory/600scancompare): valid REQUEST_CHANGES scopedvisibleUIonly. Adopted fewer duplicatecompareheaders, native draggable document/change split with independent persistedpaneheights, smaller initialchangelist, compactsmallhistory/legend, PDFunderpagebackground/breaks/shadows. Screenshotpixelestimates arenotpointmeasurements. Sheetwasexcluded: cacheDisplaycapturedtransparentrootratherthanwindowbackground; explicit native sheetbackground precedes newcapture. No PNG editing.
- New per-request cancellation handle is restricted to read-onlychanges. Superseded modelrange/project selection cancelsitsownquerytask/process; siblingqueries and analysis/commitareuntouched. Foundation-only processprobe prepared; nativecompile/runtimeverification pending serializeddocumentOCRresearch. No46approval/buildclaim.
- Grok45 both focusedattempts timeout124 with emptystdout (7939Bthen3264Bpackets); transportping alone isnotreview. Agyquota429 unresolved, no retrybeforequotareset/credentialoraccountchanges. Externalreviewnotmisreportedcomplete.
- Native46 keeps exact45 TypeScript/helper/engine semantics, so no canonical engine/schema bump for visual/process-lifecycle changes. Historical44/45 matching/diff/DAG source remains unchanged; archivebeforefuturekernelchanges. Productwork staysactive for OCR andPPTXfidelity, currentZIP27stale.

- Native46 first full serial178/178PASS,0fail/skip/cancel138300.702334ms, heldfixedBridge/engine/newprocessintegrationthroughsuite. FocusedactualSwiftBridge5processrace/isolationchecks+SwiftUItypecheckPASS. Subsequent geometry preference isolation and internalSmoke existing-synthetic-snapshot/divider-hide-reopen checks added only to nativeUI/QA; sameengine/helper/Bridge/testfixtures untouched. TargetedTypeScript/Swiftcompile and actualnewappqualification required for that final native delta; no redundant unchangedengineaccuracy rerun implied.

### 2026-10-19 native47 working — actual pane reopen regression
- Actualfrozen46manualapp run failedLAYOUT_MEMORY after21.782744209s,peak708.65625MiB. Real split/merge/sheetcapture completed; defaultpaneandnativeprogrammaticdividerresize passed, subsequenthide/reopenheightfailed. Remainingfourjobs withheld; no46readyclaim. Actualnewopaque sheetcapture readable; no PNGpostprocessing.
- Narrowfix: remove geometryobserver in NSViewControllerRepresentable dismantle before obsoletehostingview teardown; only attachedvalidsplitgeometry mayupdate savedheight. ExplicitMainActor.assumeIsolated reflects NotificationCenterqueue:.maindelivery and eliminates threeSwift5concurrencywarnings; no runtimeoffmainraceclaim. Smoke failure includes actual resized/reopened/savednumbers. Freshcompileandactualrerunrequired.

- Both independent46lanes separately reproduced a MEDIUMQAfalse-success: native-view-reopen retained oldresult.json and ignored freshfailure.json while nativeSmoke catches/exits0. Freshunique46outputs were not claimed false; scriptretrywasunsound. Fix clears every per-runresult/failure/process/immutableartifact, rejects currentfailure, and binds a fresh result to a random invocationnonce echoed by nativeSmoke. Actualscriptregression must exercise positive→failingrerun samefolder and rejectzero-exitfailure.

- Native47 cancellationcatch now respects its per-request cancelledflag even if stdinwrite races childtermination; cancelledrange returns CancellationError instead of unrelatedI/Oerror. Existingmodelgenerationguardalreadyhid supersedederrors;thiscloses narrowBridgecontract. Added24actualSwiftProcessmidlaunch cancellationraces, preserve sibling/nonrange/no-crash-logchecks.

- Final47 serial`npm run check`179/179PASS,0fail/skip/cancel139936.820791ms, runtimefixedthroughsuite; warnings-as-errorsSwiftUItypecheckPASS with0warnings. Newtests exercise24SwiftProcesscancellationraces and actualnative-view-reopen validator success→zeroexitfailure→stalenonce→success reuse. No laternative/runtimechangescrediteduntilfreshqualification.
- Historical46componenttypechecklog was overwritten by root's reused targetedrunner, so it cannotserveasimmutable46evidence; preserved native46-macos-build.txt contains all3warnings(4762B SHA2af9e9a6447c3fbe5e50486508a539ce7a7347c358b0a649517191e008fab10d). New47finalcomponentlogs use distinctnative47names.

### 2026-10-19 native48 working — actual split initialization lifecycle
- Actualfrozen47manual rerun failedLAYOUT_MEMORY22.102222708s,peak783.8125MiB:resized145,reopened105,saved-1. This falsifies the47teardownsaving-only hypothesis; firstpositioned initialization did not produce a savedheight. Source47strictcompile/full179PASS doesnotcloseactualUIgate. Laterfourjobswithheldagain.
- MoveproductionWorkspaceSplit into its own nativecomponentfile and initialize/persist from the actualNSSplitViewlayout/resize lifecycle, including real sizedembeddedview; remove NotificationCenter observer dependency. Detach disablescallbacks. StrengthenappQA intendeddefault140±2pt instead of acceptingminimum105. Add actualSwiftUIembedded componentprobe before fullappanalysis.

- Isolatednative48probe reproduced105default. Temporarydiagnostic observedactualsplitbounds900x668/windowattached/callbackactive, but `subviews.count==3`: AppKit adds a non-pane view, so the hard`subviews.count==2` guard preventedinitialization/persistence. This supersedes the earlier lifecycle-hook hypothesis. Use documented`arrangedSubviews` for actualsplitpanes in production/QA; restore47controller/observerlifecycle instead of retaining speculative customcallbackcode. Temporarydebug/customsubclassremoved. NewrealembeddedUIprobe verifiesactualdefault140 and4resize/hide/reopencycles.

- Native48 isolatedproductioncomponent test PASS3307.845042ms:actualSwiftUIembeddedNSsplit initializes140pt and remembers180/160/220/140pt through4divider+hide/reopencycles. NativeAPIprogrammaticinteraction,notOSinputautomation. Original2failedprototypes/diagnostic retained; no debug/customcallbackcode in finalcomponent. Full180/regression/newappqualification pending.

- Final48 serial`npm run check`180/180PASS,0fail/skip/cancel143008.6385ms, runtimeheldfixedthroughsuite. Warnings-as-errorsfullnativeSwiftUItypecheck0warnings. IncludesactualproductionWorkspaceSplit default140+4divider/hide/reopencycles,Bridge24midlaunchraces,actualnativevalidatorstaleresult/failure/noncecontrols. Onlyevidencedocsfollow; actualnewpackaged48runtime/visualreviewpending.

### 2026-10-19 native49 working — visible history semantics
- Actualclean48app all5hashboundjobsPASS:manual25.046421875s683.6875MiB/backend13.839616042s456.421875/five16.023811s480.328125/600UIreopen12.092893542s721.109375/900UIreopen13.07979025s538.171875. Manualactualpane140/doc639/resized180/reopened180;split/merge/allbranches/no-writecancel/oldreportimmutabilityPASS. 600/900reopenown45reports,notnewanalysislatency.
- Claude48auditedactual5capture review validREQUEST_CHANGES:prior45canvas/pageedge/list/sheetissuesclosed,but historylegendclipped atdivider. Native49moveslegendunderhistorysubtitleoutsideScrollView, so alwaysvisible. No speculativeheightcalculation/customlifecycle. ApplybuttonalreadyhasborderedProminent/defaultAction, so advisor's nonblockingrecommendationisredundant; no fabricatedfix.
- Grok48focusedpaneguard reviewVALIDexit0/788B/terminalAPPROVE,promptSHA21abdf96601664713e61303dc58fa1733106885ae7725e5748f2b83431746af5; scopeguardonly,notfullbase/product/nativeUIapproval. Earlieremptytimeoutsstayinvalid. Agyquotaunchanged.

- Native49warnings-as-errorsSwiftUItypecheckPASS0warnings. OnlyhistorylegendTextmovedoutsideScrollView since exact48full180; engine/helper/Bridge/geometry/testbytes unchanged. Actualnative rerender required, no redundantfullsuiteforoneTextrelocation.
- IgnoredofflineTesseract6.0.1research completed1134observations:378historicalnative20actualROIcrops×3fixedarms,102missingretained. Bilingualdefault andall6DAWGoffboth269fullcorrect,95currentemptyreadcorrect,but21currentcorrectcontradicted;English243fullcorrect/82emptycorrect/34contradicted. Missingcropsinclude11ofcurrent22nonempty-nottruth,23correct,68empty;availablewrong11notcontradicted. All5strictLatinrecoverycandidatesstillincludeonefalsebiIling→billing evenwithTesseractagreement. NOadoption,notcurrent26ROIbyteproof/universalaccuracy. OldinputcropSHAs/modelsverified, no network/modeldownloads/primaryreplacement.

### 2026-10-20 engine50 working — provided PDF fidelity and OCR qualification
- Native49 exact source5c843896 actual5jobs and Claude actual5PNGvisual review PASS/APPROVE; completebase codeAPPROVE/READY, architectureWATCH. Current49ZIP newly qualified: release/Docver-0.3.0-native49-arm64.zip390237253B SHA78ab42e3006055cf6b07c9fcdb5b076bef0ef1a6142a1319a6b5e5878da27f90. Actual ZIP relocation with spaces, root/vendor strict signatures, minimalPATH/cwd/ native freshfive20.004733417s and backend8checks14.267195791s including read-only scopedMCP/DBhash PASS. Source49 review and package are historical once50 changes; product remainsOPEN.
- Official pinned PaddlePaddle ONNX Korean/English+Microsoft ONNX Runtime1.30.0 CPU research ran in ignored folder with model digests/SRI verified, install hooks skipped and no inference network. All480currentPDFKitrasters matched;909fixedcrops×2models1818observations22.448051709s. English visibleink310correct/163wrong/7empty,49currentcorrectcontradictions;Korean296correct/184wrong,45contradictions. Two-modelconsensus321has42false; posthoc.99threshold84has10false. Approximate canvas/OpenCV resize difference and prior-inspected correlatedsingleline scope recorded. No production dependency, OCR replacement or agreement-based promotion adopted. Production still218correct/22wrong/240empty on that480case corpus.
- Working engine50 caches rawparse metadata bySHA+format and clones it before occurrence enrichment. It qualifies conservative full suppliedPDF bundles before LO, records separate inferred `Page.appearance`, skips redundant LO only forqualifiedbundles, and keeps rawPPTX/PDF observations. Never treats supplied pixels as an exact source matching anchor. Entiretimeline samePDF/differentPPTX guard, correct referenceasset/page/hash evidence, separate nativequalitycounts and evidence-to-primary-slide navigation added. Originalbytes reverified; SourceChanged abort preserves committed snapshots. See ADR005 for contract and current limitations.
- Exact44/45matching/diff/DAG kernels archived BEFORE current sourcechanges. Golden4reports×4selectors generated using immutable49source reproduce complete oldnetevents/IDs/get_evidence responses. Old45 occurrencecanonicalIDs and44rawselectors retained; no silent historical recomputation under50 semantics. Shared helpers unchanged in this iteration; future changes require historical preservation.
- Initial50 strictSwiftwarnings-as-errors0warnings and serial184/184PASS0fail/skip/cancel144712.17225ms, runtime/testfixtures fixed. Only2schema documentation mirrors then regenerated. Runtimebinding checker initially also counted those expected docs changes; completion record distinguishes them from runtime source changes. This184result is now historical INITIAL50 evidence because subsequent advisor findings caused real fixes.
- Claude proposal review VALIDREQUEST_CHANGES adopted stale-PDF reuse guard; clarified existing headless helper and hashed OS/helper/font/config fingerprint. Updated source review VALIDREQUEST_CHANGES identified samePPTX/differentPDF falsevisualedit, one missingpage wrongly promoted tointervalgap and incomplete renderer key. Fixed all3 with regression controls; also disallow existingbundleinconsistentqualification, rotate0onlyfallback, crossrevisionReportreusevalidation and SOURCE_CHANGEDabort. Policy marker on everynewrevision is intentional eligibility/legacy routing, not a successfulqualificationclaim. Current5targetedtestsPASS3975.694375ms including realreorderedPDF/hidden/bundle-standalone-cache/ROexport/oldreport and source-race abort. Revised strictSwift/full185 runtime verification INPROGRESS; do not credit initial184 to those fixes yet.
- Grok50proposal timedout180s emptyexit124; focused followup exited0 but only proposed ls/find with headless permission error/noverdict. Both INVALID, no newapproval. Prior48guard approval retains its narrow scope. Agyquota429 remains unresolved; no account/credential/purchase/retry workaround.
- Actual clean50app/newreferencePDFnativecaptures/fullbase independent source reviews remain pending. Native49app/ZIP are still current packaged bytes. No PowerPoint26-page strict equivalence, perfectOCR, sameversionmanualmapping or wholeOSinput/accessibility/minOS/notarization claim.

- Revised50b strictSwiftwarnings-as-errors PASS0warnings and full185/185PASS0fail/skip/cancel147124.547291ms. Before/after runtime/testfixture binding rechecked with0changes; regenerated schema mirrors separately after suite. Includes samePPTX/differentPDFreviewgap, page-vs-intervalmissingmetadata controls, renderer-key negative control, rotationfallback, crossrevisionreportreuse validation, source mutation abort and immutable44/45goldens. Actualnewclean50app remains the next gate.

### 2026-10-20 engine51 working — explicit evidence navigation and historical50 preservation
- Exact50 source a52b651b77be72037323c3e8ace8b0c28a02a80e clean-built app passed6 artifact-bound jobs: fresh reference7.491327s, manual relations21.795711s, backend13.615460s, five versions15.767740s,600UIreopen12.073664s and900UIreopen13.275777s. Large reopens use own45 reports, not new50 analysis latency. No full OS-input claim.
- Complete original-base50 independent code lane COMMENT/READY (127paths) found LOW visual warning tagged text; architecture lane BLOCK (127paths) found actual explicit evidence button still used secondary PDF IDs in the primary PPTX picker. Therefore aggregate50 BLOCKED despite185tests/all6app jobs. The previous smoke covered automatic selection, not this explicit action. Preserve both verdicts; no50 ZIP released.
- Working51 fixes both left/right explicit evidence actions, validates primary membership, preserves navigation pins and refuses unmapped secondary selections. Actual production AppModel test safely reproduces old50 failure and passes current51 navigation, pin, unmapped, direct-source and PDF-only controls. Packaged reference smoke now invokes both actual buttons and verifies both fetched pages have reference_pdf origin.
- Supplied-PDF visual event rows/inspector now say 제공 PDF 화면 차이, with neutral source text for visual/reference gaps. This clarifies inferred PDF appearance versus source text changes without changing the source observations.
- Correcting warning feature text→visual_comparison changes canonical event bytes. Engine51 archives exact50 matching/diff/range kernels and immutable50-generated golden events/IDs/evidence for all4selector combinations. Old50 text-scoped bytes remain exact; new51 uses visual scope. Schema stays additive0.3.0/helper26 unchanged. Targeted7/7PASS5257.528666ms; standalone actualModel current action PASS1362.808333ms.
- First51 strict Swift PASS0warnings; full check stopped at a missing test callback type before executing tests. Fixed explicit event array typing. Fresh51b strict/full/source binding rerun in progress; retain initial failure separately. Current packaged app is50, latest qualified ZIP49; no51 app/review/package completion claim.
- Claude50 focused source closure valid APPROVE only for its8specific findings. Grok50 valid focused REQUEST_CHANGES retains the causal-limit WATCH: supplied PDF pixel differences cannot prove a PPTX graphical edit. The event remains inferred with exact PDF evidence and explicit warning. Other Grok timeout/plan-only outputs invalid; Agy quota429 remains unavailable with no account/purchase workaround. Product remains active OPEN.

- Revised51b strict Swift warnings-as-errors PASS0warnings and complete187/187PASS0fail/skip/cancel145595.718875ms. Full runtime/test/fixture bytes bound before/after with0changes. Initial51 test typing failure retained separately. New frozen51 clean app, complete-base independent reviews and package qualification follow; product remainsOPEN.

### 2026-10-20 native52 working — automatic evidence membership and reversible import bundles
- Frozen51 clean app6jobs passed with artifact bindings: fresh reference11.112194s, manual22.022211s, backend13.876618s, five16.009163s,600UIreopen11.819505s,900UIreopen13.224414s. Fresh canonical51 actual600scan analysis+UI264.345417292s, sampled driver-tree peak1106MiB;900mixed63.910150s/1095MiB. These are one-run synthetic workloads on this Mac, not p95, ceilings or full OS-input tests.
- Both complete original-base51 independent lanes BLOCKED: automatic selectEvidence/chooseChange still accepted unresolved secondary PDF IDs despite the explicit button's new guard. Code REQUESTCHANGES/BLOCKED, architecture BLOCK/BLOCKED; all133paths covered. Both native-role launches failed400 because configuredgpt5.5 was unsupported by this account before inspection; independent installed-TOML-backed review sessions supplied the actual reviews with honest generic-agent-definition-backed metadata. No model/account/credential change or native-role claim.
- Root safely reproduced51 failure with actual immutable51Model/Bridge plus new automatic navigation test: exit1,0.4844835s, binarySHA6b7da4eaacc9566c937280cfcff1a6e066e960e409755627e0ef008c20d95530. Working52 validates automatic resolved IDs against primary source pages; unknown relevant evidence retains a valid selection plus explanation, valid mixed evidence resolves, and a genuinely absent side remains empty. Tests exercise automatic and explicit routes separately.
- Pre-create native import now supports explicit 묶음 해제. Stable per-file IDs/labels/order/fingerprints survive grouping, whole-group reorder and ungroup. Each group has its own transient ID. An edited group name stays on the first selected file; the other keeps its name. Preserve explicit member order even PDF-first rather than silently moving it. Invalid same-format/triple/out-of-range operations leave the draft intact.
- UI-selected files are streamed through SHA256 off the UI thread. Create carries optional per-file expected digests; private bridge validates format/count and DesktopService checks actual copied bytes before writing. Same-length/same-mtime replacement is rejected SOURCE_CHANGED. Demo/programmatic legacy create payload and canonical manifest/report/engine/schema stay unchanged; repeated asset occurrences remain legal. This does not implement same-version page correction or existing-bundle editing.
- Claude52 proposal review valid REQUEST_CHANGES: adopted identity/label/order/move/stale-file issues; exact-byte SHA is stronger than mtime/bookmark identity, and automatic PPTX-first sorting/global duplicate blocking were not adopted because explicit order and legal repeated versions must survive. Dedicated same-version correction sheet was recommended for subsequent work; it is not implemented/approved in52.
- First52 native strict compile found AppKit chose async beginSheet overload in smoke; fixed explicit completion handler so capture can precede dismissal. Failure log preserved. Revised52 strict Swift warnings-as-errors0warnings plus4/4targeted PASS4171.8875ms: actual production Model selection controls, actual native import identity/roundtrip/actions, DesktopService byte-race rejection and actual native bridge validation. Full190 source-bound regression currently running. New packaged52 import-sheet rendering/action/create guard remains pending; no52 approval/package claim.

- Initial52 full190/190PASS0fail/skip/cancel149121.993833ms with fixed runtime/test bytes and strict0warnings. Claude focused source review valid APPROVE scoped to that patch, with5nonblockingcomments. Adopted status-test reset, dedicated evidenceWarning (clears on valid selection without overwriting generic progress), preservation of every selected member's digest in mixed legacy/selected bundles using nullable per-file slots, and actual smoke's analysed-project/report preservation assertion. Content-addressed blobs from earlier files on a later failed create remain the existing behavior; only project creation is atomic, no claim of no filesystem writes. Original files are never overwritten.
- Revised52 strict0warnings and4targetedPASS4388.886666ms include mixed nullable expected digests in actual Swift payload and actual bridge rejection, warning emission/reset and unrelated-status preservation. Initial190 is historical before these fixes; revised190 source-bound full run is pending. Claude revised focused closure running. Grok initial selector source request timed out124 with empty stdout/stderr (invalid); one operational retry uses exact same original packet and will not be credited to later warning polish. No all-provider approval.

- Revised52b full190/190PASS0fail/skip/cancel155531.905125ms, strict0warnings, source/test/fixture0changes during run. Claude revised focused source closure valid APPROVE (scope all revised selection/import patch, not fullbase/product) closed initial1/2/4/5 and accepted the precise no-failed-project claim. Its residual UI-only stale-warning-on-new-analysis concern led to clearing warning at actual run entry and explicit page picker/go actions. Actual Model regression now verifies run-entry warning clear even when the isolated probe has no backend;4targetedPASS (exact log retained).
- Native smoke adds a real mixed selected/legacy bundle create to exercise Swift NSNull→Bridge.call→private validation and explicitly asserts original analysed project/report remain selected. Current strict0warnings/4targeted source binding passed after those changes; final one-line go warning reset follows. Final52c full190 is pending on these final frozen runtime bytes. Both Grok selector requests timed out124 with empty stdout/stderr; retry exhausted, no new approval. Agy quota remains unavailable; no account/purchase changes.

- Final52c strict Swift warnings-as-errors PASS0warnings and complete190/190PASS0fail/skip/cancel147672.904084ms; all runtime/test/fixture bytes remained fixed. This run includes final run-entry/page-picker/go warning reset and mixed-native-bridge smoke code. Actual production model/import/bridge targeted4PASS4474.987166ms before final go-line includes actual async run-entry warning cleanup without a bundled backend. Final complete-base reviews and clean packaged52 rendering/actions remain pending. Canonical engine remains0.3.0-native.bundle.51; native build cycle52 adds no observation/query/schema identity change.

### 2026-10-20 native53 working — explicit same-version PDF decisions
- Qualified52 interim source9a766aa64b6ada9d1e04aacc9eba07779a0ecdd1:190checks/strict Swift, six bound native app jobs and relocated ZIP pass. Independent full-base codeCOMMENT/READY and architectureWATCH/READY. Claude52 actual visual REQUEST_CHANGES stayed separate from source readiness; product remains OPEN. ZIP SHAa7098469d0c6d0c1adbe12450ff4dc8960bb9a53515105e52e4e8494827c2942,390305262B.
- Working53 schema0.4.0 / canonical0.4.0-native.bundle.53, helper26 unchanged: append-only same-revision PPTX/PDF link, source-wide unlink/block, exact prior-pair displacement, verbatim reason, asset/occurrence/report/draft binding. The raw automatic mapping basis is persisted and replayed; incomplete/forged displacement, resurrected automatic pairs, missing human authority and baseline drift fail closed. The engine reconstructs raw associations before applying decisions, then converts unreferenced source slides on clones. A supplied PDF never replaces raw OOXML observations or authenticates PowerPoint fidelity.
- Early independent code review found two actual integrity gaps (omitted first inferred conflicts; revived inferred pairs after unlink). Root repaired both, added counterexamples, and the independent narrow repair probe passed old52 first-decision compatibility plus four-step replay. Architecture early review found the sheet occurrence-key mismatch and missing concrete warnings. Both repaired with actual Node bridge coverage and explicit warning consumers. These are WIP feedback, not final53 readiness verdicts.
- New dedicated SwiftUI sheet, independent source/PDF previews, current/previous human reasons, explicit Apply with Hangul-safe Return behavior, read-only paginated history, source-wide unlink, source/draft CAS and retained edits. Current page navigation supersedes old pins, page-set captions use one arrow, import intro clarifies optional grouping, duplicate vN labels are removed.
- Draft/staging version isolation is limited to desktop_projects_v4/staging-v4; reports/runs/assets stay shared. Serialized native use retains the exclusive library lock. Older standalone recovery concurrency is not guaranteed; explicit old snapshots stay immutable and future-schema reads fail clearly. See ADR006.
- Focused repaired core/native-action/reference18PASS13093.184209ms; additional real partial/reused-PDF conversion and immutable51 four-selector golden give16focusedPASS9553.989375ms. Current strict Swift0warnings; full regression runs on fixed runtime/test/fixture bytes. New packaged53 app, full-base two-lane readiness and Claude actual visual review remain pending. No renewed universal OCR, PowerPoint equivalence, full OS-input, VoiceOver, minimum-OS or notarization claim.

- Initial53a strict Swift0warnings; full200 ran to completion:198PASS/2FAIL0skip/cancel154767.990458ms. Failures were the intentionally expanded read-only MCP tool list and the intentional historical0.3 envelope contract expected as current0.4 by an old assertion. Updated those explicit contract assertions; independently caught and fixed native history requests above the shared8000budget limit before running the packaged app. Fresh53b strict/full binding now running. Initial failure logs retained.

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


### 2026-10-20 native53 Z qualification and ordered PPTX text repair

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


### 2026-10-20 native53 AL 실제 앱·ZIP 검증 완료 / 제품 판독 게이트 OPEN

- Clean source `3ff0af791b661c8243ae8276a76e0c3a47644be9`의 실제 앱 11개 serial 작업이 모두 통과했다. UTF8/LE/BE 원문·표·노트·미리보기/재열기 21.808188084s; 새900쪽 혼합 분석60.337862583s; 비율8.874821917s; 제공PDF/가져오기10.250058875s; 번들27.057395s; 수동관계21.273454666s; backend13.239466583s; five15.443865458s; 기존600/900/1200보고서 재열기11.663506041/12.872995208/14.446382709s. 모든 작업 후 앱 핵심8파일 hash 일치. 새900쪽의 1초 프로세스트리 RSS 표본 최대1013.484375MiB, p95/메모리 상한 보장은 아니다. 재열기는 새 분석이 아니다. 실제 AL UTF16 focus PNG도 직접 확인했다.
- 새 ZIP `release/Docver-0.4.0-native53-svg-guard-v1-arm64.zip`:390495400B, SHA256 `44eabdfc94b7a9c1fa3da55b8ef00adc3cd2cf2b56b31a8130d4e2e3c884f6bf`. 엄격 앱/Office 서명, ZIP/해제/공백 경로 이동, cwd `/`·최소PATH에서 새five17.377122084s/backend8검사13.608585333s/참조PDF·가져오기10.266557125s/번들·과거이력·MCP·두번째프로세스27.936095375s/최종서명 통과. 이전 Z/AK ZIP과 검증 기록을 보존한다.
- 독립 complete152 AL code APPROVE/READY:35470B SHA256 `eb50ddfd907f67a14edc4f504307a6261d94e8ecfba52232046444776f89ea6a`; architecture WATCH/SOURCE_READY:44707B SHA256 `3e6bae6b0f403126837094bfa38c5205386991d59ca5a7c5b75f39577cc04ddf`. 두 lane 모두 원래 base/정확한 AL/변경152개를 고정했다. 합성은 COMMENT/소스READY이며 플랫폼·품질WATCH는 남는다.
- 정확한 AL223/strict0warnings, source review, 실제11작업, ZIP을 `native53al-composite-qualification.json`으로 연결했고 `release/validation.json`은 이제 AL을 가리킨다. 빌드 후 추적runtime/test122파일 해시 일치. 현재 문서 closure는 이 앱 빌드의 clean source SHA를 바꾸지 않는다. HANDOFF.md/PLAN.md는 수정하지 않는다.
- helper26의 이전480사례218정확/22비어있지않은오인식/240빈결과, 독립PowerPoint26쪽 strict동일0, 다른Mac/최소OS·OS입력/IME/VoiceOver·공증/공개배포는 여전히 OPEN. OCR raw/추정 경고를 보존하고 정답 맞춤 치환이나 rejected 후보 승격을 하지 않았다. 이전실제480/PowerPoint결과를 이번 fullcorpus재실행으로 재분류하지 않는다. 최종Claude timeout+1동일retry invalid, Grok timeout invalid, Agy quota 미가용; 전체3provider최종승인 주장을 하지 않는다.
