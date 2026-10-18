# 첫 체크포인트 의존성

2026-10-19 설치 metadata 기준. 정확한 전이 버전은 package-lock.json에 고정한다. 프로젝트 자체 공개 라이선스(G5)와 설치본 재배포 검토는 아직 끝나지 않았다.

| 직접 의존성 | 버전 | upstream 라이선스 | 용도 |
| --- | --- | --- | --- |
| pdfjs-dist | 6.4.299 | Apache-2.0 | PDF 텍스트·좌표·렌더 |
| @napi-rs/canvas | 1.0.11 | MIT | 로컬 PNG 렌더 |
| fast-xml-parser | 5.11.2 | MIT | OOXML 구조 |
| fflate | 0.8.3 | MIT | ZIP |
| zod | 4.6.7 | MIT | 타입·실행 검증·JSON Schema |
| @modelcontextprotocol/sdk | 1.32.1 | MIT | 로컬 stdio MCP |
| pptxgenjs | 4.0.1 | MIT | 개발용 합성 PPTX |
| pdfkit | 0.20.2 | MIT | 개발용 독립 합성 PDF |
| typescript | 7.0.2 | Apache-2.0 | 개발용 타입 검사 |
| tsx | 4.23.15 | MIT | 소스 체크아웃 실행 |

시스템 폰트는 사용 환경에서 읽을 뿐 저장소에 복사하지 않는다. LibreOffice는 설치·재배포하지 않았다. canvas의 전이 네이티브 구성요소, PDF.js 포함 폰트/wasm, Electron 등 향후 번들 구성요소의 배포 notice는 M6에서 별도 검토한다.

초기 npm audit에서 개발용 PptxGenJS의 image-size 전이 의존성 경고가 있었다. image-size를 호환 API의 2.0.4로 override한 뒤 fixture/이미지 포함 렌더 spike를 실행 검증했다. 최종 `npm audit` 전체 범위와 `npm audit --omit=dev` 결과는 PROGRESS.md에 기록한다. 이 목록은 제품 설치본 라이선스 검토를 대신하지 않는다.
