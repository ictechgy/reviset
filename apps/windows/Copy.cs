namespace Reviset.Windows;

internal sealed class Copy
{
    public string Language { get; set; } = "en";
    public string this[string key] => Words.TryGetValue(key, out var pair) ? Language == "ko" ? pair.Ko : pair.En : key;
    private static readonly Dictionary<string, (string En, string Ko)> Words = new()
    {
        ["documents"] = ("Documents", "문서"), ["workbooks"] = ("Spreadsheets", "스프레드시트"), ["import"] = ("Import versions…", "버전 가져오기…"),
        ["refresh"] = ("Refresh", "새로 고침"), ["analyze"] = ("Analyze draft", "초안 분석"), ["cancel"] = ("Cancel", "취소"), ["export"] = ("Export…", "내보내기…"),
        ["mcp"] = ("Copy MCP config", "MCP 설정 복사"), ["layout"] = ("Layout", "화면 배치"), ["balanced"] = ("Balanced", "균형"), ["focus"] = ("Document focus", "문서 집중"), ["review"] = ("Review", "검토"),
        ["sidebar"] = ("Project sidebar", "프로젝트 사이드바"), ["inspector"] = ("Evidence inspector", "근거 패널"), ["changesBottom"] = ("Changes at bottom", "변경 목록 아래"), ["changesLeft"] = ("Changes on left", "변경 목록 왼쪽"), ["changesRight"] = ("Changes on right", "변경 목록 오른쪽"),
        ["inspectorLeft"] = ("Inspector on left", "근거 패널 왼쪽"), ["inspectorRight"] = ("Inspector on right", "근거 패널 오른쪽"), ["vertical"] = ("Compare top / bottom", "위아래 비교"),
        ["saveLayout"] = ("Save layout…", "배치 저장…"), ["applyLayout"] = ("Saved layouts", "저장된 배치"), ["deleteLayout"] = ("Delete saved layout", "저장된 배치 삭제"), ["reset"] = ("Reset workspace layout", "화면 배치 초기화"),
        ["before"] = ("Before", "이전"), ["after"] = ("After", "이후"), ["report"] = ("Pinned report", "고정 보고서"), ["pages"] = ("Pages", "페이지"), ["sheet"] = ("Sheet", "시트"), ["changes"] = ("Changes", "변경 목록"), ["evidence"] = ("Evidence / source detail", "근거 / 원본 상세"),
        ["zoom"] = ("Zoom", "확대"),
        ["interval"] = ("Change list interval", "변경 목록 구간"), ["event"] = ("Selected event evidence", "선택한 변경 근거"),
        ["ready"] = ("Ready", "준비됨"), ["chooseProject"] = ("Import versions or select a project to begin.", "버전을 가져오거나 프로젝트를 선택하세요."), ["noReport"] = ("This draft has no saved report. Analyze it to create a pinned snapshot.", "저장된 보고서가 없는 초안입니다. 분석하여 고정 보고서를 만드세요."),
        ["selectPage"] = ("Select a page.", "페이지를 선택하세요."), ["structural"] = ("Structural text — source rendering unavailable", "구조화 텍스트 — 원본 렌더링 불가"), ["source"] = ("Preview source", "미리보기 원본"),
        ["row"] = ("Row", "행"), ["column"] = ("Column", "열"), ["go"] = ("Go", "이동"), ["previous"] = ("Previous", "이전"), ["next"] = ("Next", "다음"), ["more"] = ("Load more changes", "변경 더 보기"),
        ["sparse"] = ("Sparse preview: — means not materialized, not confirmed blank. Formulas are stored source; cached values are not recalculated.", "희소 미리보기: —는 관측되지 않은 셀이며 빈 셀로 확정하지 않습니다. 원본 수식과 저장된 값을 표시하며 재계산하지 않습니다."),
        ["formula"] = ("Formula", "수식"), ["cached"] = ("Stored value", "저장된 값"), ["showFormula"] = ("Show formulas in grid", "표에 수식 표시"), ["noChanges"] = ("No observed changes in this range. Coverage limits still apply.", "이 범위에서 관측된 변경이 없습니다. 관측 한계는 유지됩니다."),
        ["title"] = ("Project title", "프로젝트 이름"), ["label"] = ("Version label", "버전 이름"), ["files"] = ("Source files", "원본 파일"), ["add"] = ("Add version…", "버전 추가…"), ["up"] = ("Move up", "위로"), ["down"] = ("Move down", "아래로"), ["remove"] = ("Remove", "제거"), ["start"] = ("Import and analyze", "가져오기 및 분석"),
        ["documentHint"] = ("Add versions in chronological order. Each version accepts one PDF, one PPTX, or a PDF + PPTX pair. Source files are copied after SHA-256 verification.", "버전을 시간순으로 추가하세요. 각 버전은 PDF, PPTX 하나 또는 PDF + PPTX 묶음을 받습니다. SHA-256 검증 후 원본을 복사합니다."),
        ["workbookHint"] = ("Add one XLSX, ODS or UTF-8 comma-delimited CSV per version, in chronological order. Formulas and macros are never executed.", "각 버전에 XLSX, ODS 또는 UTF-8 쉼표 구분 CSV 하나를 시간순으로 추가하세요. 수식과 매크로를 실행하지 않습니다."),
        ["layoutName"] = ("Layout name (1–48 characters)", "배치 이름 (1–48자)"), ["save"] = ("Save", "저장"), ["error"] = ("Reviset", "리비셋"), ["cancelled"] = ("Cancelled. Imported sources and previously saved reports remain available.", "취소했습니다. 가져온 원본과 기존 보고서는 유지됩니다."),
        ["importing"] = ("Verifying and importing source files…", "원본 검증 및 가져오는 중…"), ["analyzing"] = ("Analyzing…", "분석 중…"), ["committing"] = ("Saving verified report…", "검증된 보고서 저장 중…"), ["exported"] = ("Export complete", "내보내기 완료"), ["copied"] = ("MCP config copied. Review it in your AI client before enabling it.", "MCP 설정을 복사했습니다. AI 클라이언트에서 확인 후 사용하세요."),
        ["lock"] = ("Another Reviset instance is using this library. Close that instance before opening it here.", "다른 리비셋 인스턴스가 이 라이브러리를 사용 중입니다. 해당 인스턴스를 종료한 뒤 여세요."),
        ["coverage"] = ("Coverage limits", "관측 한계"), ["newProject"] = ("New project", "새 프로젝트"), ["address"] = ("Cell address (e.g. A1)", "셀 주소 (예: A1)"), ["selectCell"] = ("Select a cell or change to inspect its stored source evidence.", "셀이나 변경을 선택하여 저장된 원본 근거를 확인하세요."),
        ["reorder"] = ("Reorder draft…", "초안 순서 변경…"), ["reorderHint"] = ("This changes the input draft only. Saved reports remain pinned. Reanalysis creates a new report; existing human mapping decisions require explicit handling in the macOS app.", "입력 초안만 변경합니다. 기존 보고서는 유지됩니다. 새 보고서는 재분석하여 만듭니다. 기존 수동 대응 결정이 있으면 macOS 앱에서 명시적으로 처리해야 합니다."),
    };
}
