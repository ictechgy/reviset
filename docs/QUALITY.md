# 품질 검증 · 진행 중

요구: 실제 네이티브 Mac 앱에서 PDF 원문·가시성·OCR·PPTX 원본 충실도를 보완한다. `HANDOFF.md`와 `PLAN.md`는 원본 그대로 보존한다. 이 문서는 현재 판독 품질의 합격 기준이며 전체 PDF의 100% 인식을 선언하는 문서가 아니다.

## 구현한 경로

- PDFKit 원본 화면과 독립적인 원문/글자 표시 관측. 같은 native 화면의 원문층 차이는 숫자 수정으로 만들지 않는다.
- 한글/영어 Vision OCR, 겹치는 타일과 숫자 재인식, 원문층/이전 invisible OCR층/새 OCR 분리, 추정·낮은 점수·대안·좌표 보존.
- OCR 영역 누락을 삭제로 단정하지 않음. 읽을 수 있는 숫자 영역은 부분 비교. 스캔된 취소선은 픽셀 후보로 추정하고 밑줄과 구별.
- macOS26+의 표 구조 인식: 행·열·병합 범위와 화면 좌표. OOXML 셀, PDF 격자 추정, 화면 OCR 셀을 구별.
- 번들 LibreOffice 실제 PPTX PDF 렌더, 한글 fontconfig, 숨김 슬라이드 포함, 페이지 수·비율 검증, missing-font/원문 불일치 경고, 같은 버전 원본 PDF 우선 표시.
- 512MiB 입력 상한, 16쪽 native batch, 같은 픽셀 OCR 재사용, 트랜잭션 내 개별 페이지 인덱스와 stream source hash. 높은 밀도 자료의 다른 메모리 경로는 계속 측정한다.

## 재현 명령

```sh
npm run check
npm run mac:build
node scripts/native-backend-smoke.mjs
node scripts/native-smoke.mjs
node scripts/native-smoke.mjs --scale
npx tsx scripts/prepare-scan-scale.ts 300
node scripts/native-smoke.mjs --scan-scale
npx tsx scripts/verify-office-reference.ts
```

OCR·렌더·MCP 회귀 테스트가 통과한 체크포인트가 있다. 최종 합격과 패키지 판정은 `.omx/artifacts/`의 정확한 base/head/patch 해시와 원문 리뷰, `release/validation.json`으로 따로 고정한다. 이후 수정이 생기면 이전 승인으로 대체하지 않는다. native smoke는 실제 앱의 모델과 화면을 실행하며 OS 입력 자동화를 대신하지 않는다.

## PowerPoint 독립 참조

공개 합성 업무 자료 10개 덱, 26쪽의 원본 PPTX와 PowerPoint PDF를 사용한다. [upstream manifest](https://github.com/developer0hye/office2pdf/blob/faeca2bc29598744a62f787076d9e340e5095b8b/tests/golden_mocks/business/manifest.json)의 source/PDF SHA-256을 검증한다. upstream은 Microsoft PowerPoint16.111.1, macOS26.5.2의 독립 export라고 기록했다. 이 환경에서 PowerPoint를 직접 실행한 것으로 주장하지 않는다. 자료는 `output/office-reference/` 검증 캐시에만 두며 제품/소스 배포에 추가하지 않는다.

초기 측정은 1440×810에서 RGB 채널 차이 24를 넘는 픽셀 비율이 페이지에 따라 최대 약 1.0~3.9%였다. 이는 **96~99% 정확도라는 뜻이 아니며, 엄격한 픽셀 동일성은 통과하지 못했다.** 일부 참조의 Malgun Gothic은 현재 Mac에 없어 폰트 대체 경고가 나온다. 효과·텍스트 배치 등 렌더러 차이도 남아 있다. 전체 수치·페이지 이미지·출처는 `output/office-reference/result.json`과 provenance에 남긴다. 합성 PDFKit 기준 화면을 PowerPoint의 정답으로 취급하지 않는다.

사용자가 공개 샘플로 진행하도록 위임했다. 위 macOS PowerPoint16.111.1 export를 현재 독립 기준으로 선택하고, 다른 운영체제/버전과의 동일성으로 넓히지 않는다. 정확한 원본 PDF가 제공되는 경우에는 확인된 bundle 대응을 통해 그 바이트를 그대로 표시한다. PPTX 단독 변환의 모든 환경·폰트·특수 개체를 보증한 것으로 넓히지 않는다.

## 완료 전 합격 게이트

| 항목 | 상태 |
| --- | --- |
| 로컬 한글/영어·숫자·부호 OCR와 추정 근거 | 구현 및 실제 helper 테스트 통과 |
| 취소선/가림·OCR 누락·동일 화면 오판 방지 | 구현 및 재현 테스트 통과 |
| 회전/CropBox 좌표·스캔 표 행/열 | 현재 Mac 실제 helper 테스트 통과 |
| PPTX 실제 렌더·한글·숨김 슬라이드 | 구현 및 실제 변환 테스트 통과 |
| 300쪽 스캔 PDF×2의 실제 앱 작업 | 3386b15에서187초/약838MB 통과; 새 수정 번들은 재검증 |
| 새 번들/이동한 ZIP/읽기 전용 MCP | 3386b15에서 통과; 새 수정 source는 재검증 |
| 최종 full-diff 독립 코드/아키텍처 리뷰 | 최종 source 고정 후 실행 |
| 목표 PowerPoint 환경의 픽셀 동일성 | 선택한 macOS PowerPoint 기준 미통과 |
| 다양한 실제 문서·스캔 열화/언어·특수 PDF | corpus 확장 필요 |

복잡하거나 손상된 문서에서 인식 불가/보류를 숨기지 않으며, 파일을 읽었다는 사실과 텍스트/의미를 정확히 이해했다는 주장을 구별한다. 공증·다른 장비/최소 OS·프로젝트 공개 라이선스는 판독 품질과 별개의 배포 게이트다.

## 추가 공개 corpus

사용자 위임으로 W3C OCR 예제, Microsoft Azure 문서 분석 샘플, Mozilla의 일반 학술 예제, python-pptx의 표/그룹/차트/도형/텍스트 샘플을 받았다. 여기에 독립 PowerPoint 참조의 한국어 분기 보고/보안 교육 PDF도 포함했다. 총7개 PDF와5개 PPTX이며 출처/고정commit/바이트 SHA/수동 active-content 검사 결과는 `docs/fixtures/public-corpus.json`에 기록했다. 업무 자료는 공개된 허구의 합성 예제다. 표준 printerSettings.bin은 인쇄 설정 데이터이며 실행 파일이나 매크로로 분류하지 않는다. 이는 모든 파서 취약점이 없다는 인증은 아니다. 자료는 `output/public-corpus/` 로컬 검증 캐시에만 저장하며 원격 코드나 클라우드 판독은 실행하지 않는다.

```sh
npm run corpus:public -- --download
```

수동으로 본 선택 영역은 `docs/fixtures/public-corpus-truth.json`에 별도로 기록했다. W3C의 기존 OCR층은 정답에서 제외한다. 화면의⅛과 기존 OCR층의¼가 다른 사례를 보존한다. 선택 문구의 인식 결과와 전체 문서 정확도는 구별한다. 숫자/글자 혼동(Foo/F00 등)과 낮은 점수는 실패 또는 보류로 남긴다. 이미지 PDF의 저해상도 변형은 실제 앱처럼 PDFKit에서 다시 렌더링되며, 입력 픽셀·유효DPI·재렌더 픽셀과 정방향 좌표 변환을 기록한다.

공개 PPTX 양성 대조군은 살아 있는 OOXML 텍스트 요소 안의 교체·삽입·문자 제거를 검사한다. 요소 전체 삭제나 모든 문서의 변경 재현율을 측정한 것이 아니다. 벡터 원문의 격자 연관은 원문 text 관측으로, 래스터 격자 셀은 별도 inferred table_cell 관측으로 남기며 method와 provenance를 유지한다. 빈 셀은 값이 관측되지 않은 상태이고 병합/부분 구분선은 정형 격자로 확정하지 않는다.

Microsoft의 작은3×3 표를 Vision 문서 구조 인식이 놓치는 사례에 대응해 완전히 닫힌 격자의 보조 추정을 추가했다. 빈 셀은 좌표를 유지하되 값이 관측됐다고 단정하지 않는다. 부분 테두리/병합은 추측하지 않는다. 표 셀은 `pdf_grid_inferred`, OCR 값은 계속 추정/보류로 표시하며 기존 원문을 바꾸지 않는다. 같은 숫자 두 개는 위치별 양방향1:1 검증을 요구하고, 겹친 타일의 같은 판독은 중복 제거하되 다른 판독은 불일치로 남긴다. grayscale8bit 취소선과 밑줄도 구별하며 지원되지 않는 형식/너무 작은 영역을 단순히 취소선 없음으로 숨기지 않는다.
