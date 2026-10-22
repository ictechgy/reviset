# 오피스 문서 버전·배포 시장 조사 · 2026-10-22

공식 제품 문서와 공개 사용자 사례를 확인했다. 가격·점유율·실사용 고객 수는 추정하지 않았다. 아래 기능은 업체 문서 기준이며 직접 구매·제품 전수시험 결과가 아니다. 사용자 글은 불편을 보여 주는 개별 사례로, 모집단 비율이나 모든 최신 버전의 결함을 증명하지 않는다.

## 이미 존재하는 방식

| 도구·방식 | 확인한 버전 관리·배포 동작 | Docver와 비교할 지점 |
| --- | --- | --- |
| SharePoint 문서 라이브러리 | major/minor 버전, 초안 가시성, 승인과 공개 버전을 구분한다. 모든 저장이 독립 버전이 되는 것은 아니다. | 편집 파일·배포본·이전 공개본을 구분할 실제 수요가 있다. Docver의 로컬 릴리스 표시는 서버 승인·권한 제어와 다르다. |
| Excel Show Changes / Spreadsheet Compare | Show Changes는 값·수식 이력을 보여 주지만 서식·숨김·차트·피벗 동작 등은 제외한다. Spreadsheet Compare는 별도 두 파일의 값·수식·서식을 비교하며 특정 Office 에디션 조건이 있다. | 파일 보관만으로 원하는 변경을 바로 찾을 수 있지는 않다. 기능별 비교 범위와 사용 환경을 명시해야 한다. |
| Google Sheets | 버전 이름과 개별 셀 편집 이력을 제공한다. 셀 이력에서 행·열 삽입삭제, 서식, 수식이 만든 변경 등이 빠질 수 있고 과거 revision이 병합될 수 있다. | 이름 붙인 배포 버전과 특정 셀의 원문·변경 경로를 함께 읽는 기능이 유용하다. |
| LibreOffice Calc | Record/Manage/Compare Document와 파일 내부 버전 저장이 있다. 별도 이름으로 Save As하면 파일 내부의 이전 버전이 새 파일에 보존되지 않는다는 주의가 있다. | ODS 원본을 읽고 여러 독립 파일을 순서대로 비교하는 경로가 필요하다. |
| xltrail | Git 기반 Excel 버전 관리와 시트·구성 요소 이력을 제공한다. 입력 값·수식·VBA 등을 추적하지만 계산 결과 값은 추적하지 않는다고 명시한다. | 전용 비교·버전 관리 시장은 이미 있다. Docver의 저장된 수식 결과 비교는 재계산이나 결과의 신선도 보증과 구분해야 한다. |

근거: [SharePoint 공식 버전 정책](https://support.microsoft.com/en-au/sharepoint/lists/documents-and-library/how-versioning-works-in-lists-and-libraries), [Excel Show Changes 공식 한계](https://support.microsoft.com/en-us/excel/get-help-with-show-changes-in-excel), [Spreadsheet Compare 공식 기능·에디션](https://support.microsoft.com/en-us/excel/basic-tasks-in-spreadsheet-compare), [Google 공식 버전·셀 이력](https://support.google.com/docs/answer/190843), [Calc 공식 24.2 가이드](https://books.libreoffice.org/en/CG24/CG2412-SharingAndReviewing.html), [xltrail 공식 제품 설명](https://www.xltrail.com/). Calc 가이드는 해당 문서 버전의 기능 설명이며 현재 모든 메뉴 위치가 동일하다는 보증으로 쓰지 않는다.

xltrail 홈페이지에는 Tom Capital의 IT 담당자와 EDR 개발자의 고객 후기가 실려 있다. 이는 금융·개발 조직이 Excel을 버전 관리하는 공개 도입 사례로 참고할 수 있지만, 업체가 게시한 후기이므로 독립적인 계약·배포 범위 검증으로 해석하지 않는다. [업체 게시 고객 사례](https://www.xltrail.com/)

## 실제 공개 불편 사례와 구현에 반영한 점

- 행이 추가·삭제되는 엔지니어링 보고서를 단순 위치 기준으로 비교하자 절반 이상이 변경으로 표시됐다는 사용 사례가 있다. Docver는 고유 행 내용·첫 열 키로 이동을 추론하고, 중복 키·물리 위치 대체는 확정 대응으로 표시하지 않는다. [사용자 원문](https://www.reddit.com/r/excel/comments/1sfu357/comparing_sheets_for_changes/)
- 파일 이름에 날짜를 붙여 매주 복사하고 별도 Change History 시트에 변경 이유를 적는 수작업 사례가 있다. Docver는 원본 SHA, 고정 보고서, 사용자 버전 라벨·릴리스 이유와 전체 내보내기를 연결한다. 라벨 입력자가 실제 원본 편집자였다고 인증하지 않는다. [사용자 원문](https://www.reddit.com/r/excel/comments/1o3woav/version_control_for_excel_has_anyone_actually/)
- 공식 제품 한계에서도 셀 변경 이력과 서식·행열·계산 결과 이력이 서로 다름을 확인할 수 있다. Docver는 값·수식·캐시 가용성·타입·지원 서식·숨김·이동을 나눠 보여 주며, 없는 캐시를 값 삭제라고 주장하지 않는다. [Excel의 제외 범위](https://support.microsoft.com/en-us/excel/get-help-with-show-changes-in-excel), [Sheets의 제외 범위](https://support.google.com/docs/answer/190843)
- Calc의 파일 내부 버전과 별도 배포 파일은 보존 방식이 다르다. Docver는 가져온 파일을 바꾸지 않고 독립된 원본 자산과 고정 보고서를 보관한다. 기존 오피스의 내부 변경 기록이나 저장 시각으로 실제 작성자·모든 편집 사건을 복원한다고 약속하지 않는다. [Calc 버전 저장 설명](https://books.libreoffice.org/en/CG24/CG2412-SharingAndReviewing.html)

## 제품 판단

이 자료에서 도출한 가설은 **계정·Office 사용권 없이 Mac에서 XLSX·ODS·CSV 배포 파일을 모아 비교하고, AI가 고정 버전의 셀·수식·변경 근거를 읽는 작업**에 우선 집중하는 것이다. 이는 수요 검증 인터뷰나 기존 도구 대비 우월성 측정이 아니라 위 사례와 현재 구현을 연결한 판단이다.

현재 구현은 로컬 릴리스 기록·원본 보존·읽기 전용 MCP를 제공한다. 실시간 공동 편집, 외부 서버 배포·승인·권한, VBA 실행·비교, 피벗·차트 동작, 모든 Excel 렌더링·수식 재계산을 구현했다고 표시하지 않는다. 실제 지원·검증 범위는 [스프레드시트 계약](SPREADSHEETS.md)과 최종 검증 기록을 따른다.
