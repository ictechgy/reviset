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
