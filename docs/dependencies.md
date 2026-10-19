# 의존성 및 네이티브 패키지

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

시스템 폰트는 사용 환경에서 읽을 뿐 저장소에 복사하지 않는다. 현재 로컬 패키지는 공식 TDF 서명 LibreOffice 26.8.1.1을 `Contents/Helpers/LibreOffice.app`에 포함한다. DMG SHA-256은 ca074e0b13571efb30a31fc531c5f95e997030637325e5d5de92d67aefdf0dfc, vendor Team ID는 7P5S3ZLCN7이다. 원본 vendor LICENSE.html/NOTICE와 source 링크를 보존하며 이 로컬 번들을 공개 배포 승인으로 취급하지 않는다. 시스템에 별도 LibreOffice를 설치하지 않는다. canvas의 전이 네이티브 구성요소, PDF.js 포함 폰트/wasm, Node 런타임 등 번들 구성요소의 배포 notice는 M6에서 별도 검토한다.

초기 npm audit에서 개발용 PptxGenJS의 image-size 전이 의존성 경고가 있었다. image-size를 호환 API의 2.0.4로 override한 뒤 fixture/이미지 포함 렌더 spike를 실행 검증했다. 최종 `npm audit` 전체 범위와 `npm audit --omit=dev` 결과는 PROGRESS.md에 기록한다. 이 목록은 제품 설치본 라이선스 검토를 대신하지 않는다.

네이티브 앱 UI는 시스템 SwiftUI·AppKit·PDFKit을 사용한다. Electron/React는 포함하지 않는다. esbuild 0.28.2(MIT)는 backend/MCP 번들 생성에만 사용한다. build는 root package-lock.json을 복사하고 npm ci --omit=dev로 운영 의존성을 재현한다. 현재 로컬 앱에는 Node 24.19.0 arm64 실행 파일을 복사하며 실행 환경의 libc++/시스템 dylib을 사용한다. 다른 장비의 최소 OS 검증과 공개 재배포 notice/라이선스 검토는 아직 완료되지 않았다.

OCR/표 구조는 macOS 시스템 Vision·PDFKit·CoreText를 사용한다. 모델·시스템 글꼴을 저장소나 설치본에 복사하지 않는다. Swift helper는 앱에 포함하며 macOS26+ 구조 API는 availability guard로 분리한다. 개발 검증 자료의 PowerPoint PDF는 upstream의 독립 참조이며 제품 번들에 포함하지 않는다.

PDF.js의 legacy worker는 `scripts/prepare-pdfjs.ts`로 빌드 시에만 수정한다. 문서에 실제 포함된 글꼴 프로그램인지 나타내는 boolean과 유한한 실제 ascent/descent 두 값만 추가 전달하며 전체 fontExtraProperties는 켜지 않는다. 공백에만 쓰여 textContent.styles에서 빠진 글꼴도 실제 메트릭으로 처리한다. upstream/수정본 SHA를 고정하고 다른 버전·바이트는 거절한다. 이전 V1 수정본은 정확한 SHA를 확인하고 upstream을 재구성·재검증한 뒤 V2로 이행한다. worker 변경 고지·재현 소스·라이선스를 앱에 보존하며 서명 후에는 쓰지 않는다. 개발 테스트 준비와 공개 corpus 명령도 같은 준비 함수를 사용한다. 미수정 worker에서는 포함 여부를 확정하지 않으며 실제 worker SHA를 report 관측 환경에 남긴다.
