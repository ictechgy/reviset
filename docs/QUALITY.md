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

사용자에게 Windows PowerPoint / macOS PowerPoint / 같은 버전 원본 PDF 중 목표 환경을 확인 중이다. 우선 위 macOS PowerPoint export를 독립 기준으로 사용한다. 정확한 원본 PDF가 제공되는 경우에는 확인된 bundle 대응을 통해 그 바이트를 그대로 표시한다. PPTX 단독 변환의 모든 환경·폰트·특수 개체를 보증한 것으로 넓히지 않는다.

## 완료 전 합격 게이트

| 항목 | 상태 |
| --- | --- |
| 로컬 한글/영어·숫자·부호 OCR와 추정 근거 | 구현 및 실제 helper 테스트 통과 |
| 취소선/가림·OCR 누락·동일 화면 오판 방지 | 구현 및 재현 테스트 통과 |
| 회전/CropBox 좌표·스캔 표 행/열 | 현재 Mac 실제 helper 테스트 통과 |
| PPTX 실제 렌더·한글·숨김 슬라이드 | 구현 및 실제 변환 테스트 통과 |
| 300쪽 스캔 PDF×2의 실제 앱 작업 | 검증 대기 |
| 새 번들/이동한 ZIP/읽기 전용 MCP | 최종 source 검증 대기 |
| 최종 full-diff 독립 코드/아키텍처 리뷰 | 최종 source 고정 후 실행 |
| 목표 PowerPoint 환경의 픽셀 동일성 | 미통과·목표 환경 확인 중 |
| 다양한 실제 문서·스캔 열화/언어·특수 PDF | corpus 확장 필요 |

복잡하거나 손상된 문서에서 인식 불가/보류를 숨기지 않으며, 파일을 읽었다는 사실과 텍스트/의미를 정확히 이해했다는 주장을 구별한다. 공증·다른 장비/최소 OS·프로젝트 공개 라이선스는 판독 품질과 별개의 배포 게이트다.
