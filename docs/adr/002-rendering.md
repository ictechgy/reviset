# ADR-002: 구조 추출을 유지하고 렌더링 검증은 별도로 기록

2026-10-19 · 상태: G1 열림, G3은 초기 지원 범위 밖

## 환경과 근거

macOS arm64, Node.js 24.19.0에서 PDF.js 6.4.299와 @napi-rs/canvas 1.0.11의 텍스트·좌표 추출과 PNG 미리보기를 실행했다. PATH의 `soffice`/`libreoffice`와 기본 `/Applications/LibreOffice.app/Contents/MacOS/soffice`는 없었다. 변환기를 설치하거나 재배포하지 않았다.

OOXML은 [Microsoft PresentationML 구조 문서](https://learn.microsoft.com/en-us/office/open-xml/presentation/structure-of-a-presentationml-document)의 presentation relationship과 slide 순서를 따른다. package 내부 shape/slide 번호는 문서 간 identity로 사용하지 않는다. ZIP 크기·XML 깊이를 제한하고 DTD/entity 선언을 거절한다. 외부 관계를 fetch하지 않는다.

PDF 추출·viewport·렌더는 [PDFPageProxy API](https://mozilla.github.io/pdf.js/api/draft/module-pdfjsLib-PDFPageProxy.html)를 사용한다. 사용자 좌표계·회전/크롭을 반영하는 viewport transform을 보존하고 bbox를 정규화한다. 실제 미리보기 결과에서 한글·표·회전 텍스트가 보이는 것을 확인했다. 다양한 PDF의 정확도 검증과 글자별 정밀 사각형은 별도 과제다.

변환 어댑터는 [LibreOffice 공식 CLI](https://help.libreoffice.org/latest/en-US/text/shared/guide/start_parameters.html)에 따라 임시 출력 폴더·독립 사용자 프로필·headless PDF 변환·실행시간 제한을 사용한다. 실행 파일 부재와 가짜 지연 변환기의 timeout은 검증했지만, 실제 LibreOffice 변환의 성공/폰트/프로세스 종료는 미검증이다.

## 재현 명령과 산출물

`npm run spike`는 `artifacts/render-spike/`에 다음을 만든다.

- `deck.pptx`: 6쪽, 숨김 3쪽. 한글·혼합 폰트·도형·투명도·표·차트·회전 텍스트 각 6회.
- `source-*.png`: 신규 합성 이미지 6개.
- `reference.pdf`, `reference-*.png`: PDFKit 0.20.2로 같은 합성 설계를 독립 작성한 기준 자료.
- `report.json`: 폰트 hash, 작성 도구, 구조 추출 수치, 변환 상태, 픽셀 비교의 검증 여부.

현재 결과: 구조 6쪽/숨김 3쪽/텍스트 요소 18개. 표·차트 의미 추출은 unsupported, 회전 도형 bbox는 approximate. 변환은 `CONVERTER_UNAVAILABLE`, 픽셀 충실도는 `unverified`다.

이 PDFKit 기준은 Office 내보내기 결과가 아니다. 폰트 선택·줄바꿈·표·차트 기본값이 다르므로 고충실도 정답으로 사용하지 않는다. 변환기와 독립적으로 만들었더라도 Office 참조 렌더를 확보해야 한다. 변환기가 설치된 경우 스크립트의 픽셀 오차는 참고 수치만 제공한다.

## 지원표와 남은 결정

| 항목 | 첫 체크포인트 |
| --- | --- |
| PPTX 직접 텍스트·노트·숨김 | 지원 |
| PPTX 그룹/레이아웃 상속 | 미지원, coverage gap |
| PPTX 표·차트 의미·애니메이션 | 미지원 |
| PPTX 미리보기 | 어댑터 구현, 실제 변환 미검증 |
| PDF 텍스트·좌표·PNG | 합성 자료에서 실행 검증 |
| 이미지 PDF | 미리보기 가능, 텍스트 unavailable, OCR 없음 |
| `.ppt` | 명시적 UNSUPPORTED_FORMAT |

G1 종료에는 실제 변환기 버전·설치 방식·폰트 대체 안내, 독립 Office 참조와 오차 보고서가 필요하다. 폰트·LibreOffice를 앱에 재배포할지는 라이선스 검토와 함께 결정한다. G3의 `.ppt` 변환은 spike도 미실행이므로 지원을 약속하지 않는다.
