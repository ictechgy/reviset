import SwiftUI
import AppKit
import UniformTypeIdentifiers

private extension JSON {
    var workbookSheetID: String { self["sheet_id"].string }
    var workbookChangeID: String { self["change_id"].string }
}

// A workbook window shares the application's Bridge and exclusive library lock.
// It owns only its read requests; closing it never cancels a document analysis.
@MainActor final class WorkbookModel: ObservableObject {
    let bridge: Bridge
    @Published var projects: [JSON] = []
    @Published var reports: [JSON] = []
    @Published var report = JSON()
    @Published var projectID = ""
    @Published var reportID = ""
    @Published var beforeID = ""
    @Published var afterID = ""
    @Published var beforeSheetID = ""
    @Published var afterSheetID = ""
    @Published var mode = "range_net"
    @Published var rowStart = 1 { didSet { beforeRowStart = rowStart; afterRowStart = rowStart } }
    @Published var columnStart = 1 { didSet { beforeColumnStart = columnStart; afterColumnStart = columnStart } }
    @Published var beforeRowStart = 1
    @Published var beforeColumnStart = 1
    @Published var afterRowStart = 1
    @Published var afterColumnStart = 1
    let rowLimit = 100
    let columnLimit = 12
    @Published var beforeCells: [JSON] = []
    @Published var afterCells: [JSON] = []
    @Published var changes: [JSON] = []
    @Published var selectedChangeID = ""
    @Published var selectedRow = 0
    @Published var selectedColumn = 0
    @Published var revealGeneration = 0
    @Published var beforeAddress = ""
    @Published var afterAddress = ""
    @Published var cellTextOffset = 0
    @Published var cellTextNext: Int?
    @Published var beforeCell = JSON()
    @Published var afterCell = JSON()
    @Published var cellHistory: [JSON] = []
    @Published var coverage: [JSON] = []
    @Published var releases: [JSON] = []
    @Published var changeCursor = ""
    @Published var changePreviousCursors: [String] = []
    @Published var changePageNumber = 1
    private var changePageCursor = ""
    @Published var changeTotal = 0
    @Published var changesFromID = ""
    @Published var changesToID = ""
    @Published var changesMode = "range_net"
    @Published var cellHistoryMessage = ""
    @Published var cellHistoryCursor = ""
    @Published var cellHistoryPreviousCursors: [String] = []
    @Published var cellHistoryPageNumber = 1
    private var cellHistoryPageCursor = ""
    private var cellHistoryCursorAnchor: HistoryAnchor?
    @Published var loadingHistory = false
    @Published var cellHistoryFailure = ""
    @Published var cellHistoryTotal = 0
    var pagingOutputBudget = 8000
    private let cursorHistoryLimit = 128
    @Published var busy = false
    @Published var loadingDemo = false
    @Published var loadingReport = false
    @Published var loadingRange = false
    @Published var loadingChanges = false
    @Published var loadingCell = false
    @Published var loadingMCP = false
    @Published var status = ""
    @Published var failure = ""
    @Published private var recoveryWarnings: [String:String] = [:]
    private var recoveryWarningRuns: [String:String] = [:]
    var recoveryWarning: String { recoveryWarnings[projectID] ?? "" }
    @Published var rangeFailure = ""
    @Published var addressFailure = ""
    @Published var changesFailure = ""
    @Published var comparisonNotice = ""
    @Published var cellFailure = ""
    @Published var mcpFailure = ""
    @Published var mcp = ""
    @Published var importPresented = false
    @Published var publishPresented = false
    @Published var addressInput = "A1"
    @Published var inspectorVisible = true
    @Published var tab = "compare"
    private var generations: [String: Int] = [:]
    private var owners: [String: BridgeRequestCancellation] = [:]
    private var cancelRequested = false
    private var analysisToken: UUID?
    @Published private(set) var committing = false
    var canCancelAnalysis: Bool { analysisToken != nil && !committing }
    private var started = false
    private var active = false
    private var mcpScope = ""

    struct Ticket {
        let channel: String
        let generation: Int
        let owner: BridgeRequestCancellation
    }
    struct HistoryAnchor: Equatable {
        let occurrence: String
        let sheet: String
        let address: String
        let row: Int
        let column: Int
    }
    init(bridge: Bridge) { self.bridge = bridge }
    var revisions: [JSON] { report["revisions"].array }
    var scope: String { projectID + "|" + reportID }
    var rangeScope: String { [scope,beforeID,afterID,beforeSheetID,afterSheetID,String(beforeRowStart),String(beforeColumnStart),String(afterRowStart),String(afterColumnStart)].joined(separator:"|") }
    var comparisonScope: String { [scope,changesFromID,changesToID,changesMode].joined(separator:"|") }
    var independentPaneCoordinates: Bool { beforeRowStart != afterRowStart || beforeColumnStart != afterColumnStart || beforeAddress != afterAddress }
    var navigationRangePrefix: String {
        let differentRanges = beforeRowStart != afterRowStart || beforeColumnStart != afterColumnStart
        return differentRanges && paneCoordinate(before:false) != nil && rowStart == afterRowStart && columnStart == afterColumnStart ? "이후 " : ""
    }
    var ready: Bool { active && !reportID.isEmpty && report["report_id"].string == reportID && !loadingReport && !busy && !loadingDemo }
    var project: JSON { projects.first { $0["project_id"].string == projectID } ?? JSON() }
    var selectedChange: JSON { changes.first { $0["change_id"].string == selectedChangeID } ?? JSON() }
    func revision(_ id: String) -> JSON { revisions.first { $0["revision_occurrence_id"].string == id } ?? JSON() }
    func sheets(_ occurrence: String) -> [JSON] { revision(occurrence)["sheets"].array }
    func sheet(_ occurrence: String, _ id: String) -> JSON { sheets(occurrence).first { $0["sheet_id"].string == id } ?? JSON() }
    func paneCoordinate(before: Bool) -> (row: Int,column: Int)? {
        guard !(before ? beforeSheetID : afterSheetID).isEmpty,let (row,column) = WorkbookGrid.parseAddress(before ? beforeAddress : afterAddress) else { return nil }
        return (row,column)
    }
    var cellHistoryAnchor: HistoryAnchor? {
        for before in [false,true] {
            let occurrence = before ? beforeID : afterID,sheet = before ? beforeSheetID : afterSheetID,address = before ? beforeAddress : afterAddress
            if !occurrence.isEmpty,!sheet.isEmpty,let (row,column) = WorkbookGrid.parseAddress(address) { return HistoryAnchor(occurrence:occurrence,sheet:sheet,address:address,row:row,column:column) }
        }
        return nil
    }
    func versionLabel(_ id: String) -> String {
        let r = revision(id)
        return r.isNull ? "선택 없음" : "v\(r["index"].int + 1) · \(r["label"].string)"
    }
    func begin(_ channel: String) -> Ticket {
        owners[channel]?.cancel()
        let generation = (generations[channel] ?? 0) + 1
        let owner = BridgeRequestCancellation()
        generations[channel] = generation; owners[channel] = owner
        return Ticket(channel:channel,generation:generation,owner:owner)
    }
    func current(_ ticket: Ticket) -> Bool { generations[ticket.channel] == ticket.generation }
    func invalidate(_ channel: String) {
        owners.removeValue(forKey:channel)?.cancel()
        generations[channel] = (generations[channel] ?? 0) + 1
    }
    func invalidateReads() {
        for channel in Array(owners.keys) { invalidate(channel) }
        loadingRange = false; loadingChanges = false; loadingCell = false; loadingHistory = false; loadingMCP = false
        mcp = ""; mcpScope = ""; mcpFailure = ""
    }
    func closeReads() {
        active = false; invalidateReads(); loadingReport = false; loadingDemo = false; clearCells()
        if canCancelAnalysis { cancelAnalysis() }
    }
    func clearCells() {
        invalidate("range"); invalidate("cell"); invalidate("history")
        beforeCells = []; afterCells = []; beforeCell = JSON(); afterCell = JSON(); resetCellHistory()
        selectedRow = 0; selectedColumn = 0; selectedChangeID = ""; beforeAddress = ""; afterAddress = ""; cellTextOffset = 0; cellTextNext = nil
        rangeFailure = ""; addressFailure = ""; cellFailure = ""; loadingRange = false; loadingCell = false
    }
    func clearSelection() {
        clearCells(); changes = []; coverage = []; releases = []; resetChangePaging(); changeTotal = 0
        changesFailure = ""; comparisonNotice = ""; changesFromID = ""; changesToID = ""; loadingChanges = false; report = JSON(); reportID = ""
        beforeID = ""; afterID = ""; beforeSheetID = ""; afterSheetID = ""
        rowStart = 1; columnStart = 1; addressInput = "A1"
    }
    private func resetChangePaging() { changeCursor = ""; changePreviousCursors = []; changePageCursor = ""; changePageNumber = 1 }
    private func resetCellHistory() {
        invalidate("history"); cellHistory = []; cellHistoryMessage = ""; cellHistoryCursor = ""; cellHistoryTotal = 0
        cellHistoryPreviousCursors = []; cellHistoryPageCursor = ""; cellHistoryCursorAnchor = nil; cellHistoryPageNumber = 1; loadingHistory = false; cellHistoryFailure = ""
    }
    func start() async {
        active = true
        if started {
            let project = projectID, snapshot = reportID
            await refreshProjects()
            if active, projectID == project, !project.isEmpty { await selectProject(project,snapshot:snapshot) }
        } else { started = true; await refreshProjects(selectFirst:true) }
    }
    func refreshProjects(selectFirst: Bool = false) async {
        let ticket = begin("projects"), selection = projectID
        do {
            let value = try await bridge.call("workbookProjects",owner:ticket.owner)
            guard current(ticket), projectID == selection else { return }
            projects = value.raw is [Any] ? value.array : value["items"].array
            if selectFirst, projectID.isEmpty, let first = projects.first { await selectProject(first["project_id"].string) }
        } catch {
            guard current(ticket), projectID == selection else { return }
            failure = error.localizedDescription
        }
    }
    func selectProject(_ id: String, snapshot: String = "") async {
        guard active, !busy, !loadingDemo else { return }
        invalidateReads(); projectID = id; reports = []; clearSelection(); failure = ""; status = ""
        guard !id.isEmpty else { return }
        let ticket = begin("reports"); loadingReport = true
        do {
            let value = try await bridge.call("workbookReports",["project_id":id],owner:ticket.owner)
            guard current(ticket), projectID == id else { return }
            reports = value.raw is [Any] ? value.array : value["items"].array
            loadingReport = false
            let target = snapshot.isEmpty ? reports.first?["report_id"].string ?? "" : snapshot
            if !target.isEmpty { await selectReport(target) }
            else { status = "아직 고정 보고서가 없습니다. 분석을 시작하세요." }
        } catch {
            guard current(ticket), projectID == id else { return }
            loadingReport = false; failure = error.localizedDescription
        }
    }
    func selectReport(_ id: String) async {
        guard active, !busy, !loadingDemo else { return }
        invalidateReads(); clearSelection(); reportID = id
        let project = projectID, ticket = begin("view"); loadingReport = true; failure = ""
        do {
            let value = try await bridge.call("workbookView",["project_id":project,"report_id":id],owner:ticket.owner)
            guard current(ticket), projectID == project, reportID == id else { return }
            guard value["project_id"].string == project, value["report_id"].string == id else { throw BridgeError(code:"WORKBOOK_SCOPE",message:"통합 문서 보고서의 범위가 다릅니다.") }
            report = value; loadingReport = false
            beforeID = revisions.first?["revision_occurrence_id"].string ?? ""
            afterID = revisions.last?["revision_occurrence_id"].string ?? ""
            selectInitialSheets()
            coverage = value["coverage_gaps"].array
            await loadRange()
            guard current(ticket), projectID == project, reportID == id, active else { return }
            await loadChanges()
            guard current(ticket), projectID == project, reportID == id, active else { return }
            await loadReleases()
        } catch {
            guard current(ticket), projectID == project, reportID == id else { return }
            report = JSON(); loadingReport = false; failure = error.localizedDescription
        }
    }
    func selectInitialSheets() {
        let left = sheets(beforeID), right = sheets(afterID)
        beforeSheetID = left.first?["sheet_id"].string ?? ""
        let name = left.first?["name"].string ?? ""
        let sameName = right.filter { $0["name"].string == name }
        afterSheetID = (sameName.count == 1 ? sameName.first : right.first)?["sheet_id"].string ?? ""
    }
    func changeVersions(before: String? = nil, after: String? = nil) async {
        guard ready else { return }
        revealGeneration += 1
        var left = before ?? beforeID,right = after ?? afterID
        guard let leftIndex = revisions.firstIndex(where:{$0["revision_occurrence_id"].string == left}),let rightIndex = revisions.firstIndex(where:{$0["revision_occurrence_id"].string == right}) else { return }
        if leftIndex > rightIndex { swap(&left,&right); status = "저장된 버전 순서에 맞게 이전·이후를 자동으로 정렬했습니다." }
        clearCells(); invalidate("changes")
        beforeID = left; afterID = right; comparisonNotice = ""
        changes = []; resetChangePaging(); changeTotal = 0
        rowStart = 1; columnStart = 1; addressInput = "A1"; selectInitialSheets()
        let identity = rangeScope
        await loadRange()
        guard rangeScope == identity, ready else { return }; await loadChanges()
    }
    func changeSheet(before: String? = nil, after: String? = nil) async {
        guard ready else { return }; clearCells()
        revealGeneration += 1
        if let before { beforeSheetID = before }; if let after { afterSheetID = after }
        rowStart = 1; columnStart = 1; addressInput = "A1"
        await loadRange()
    }
    func query(_ name: String, _ args: [String: Any], ticket: Ticket) async throws -> JSON {
        var scoped = args; scoped["project_id"] = projectID; scoped["report_id"] = reportID
        return try await bridge.call("workbookQuery",["name":name,"args":scoped],owner:ticket.owner)
    }
    private func rangeCells(occurrence: String, sheet: String, row: Int, column: Int, ticket: Ticket, identity: String) async throws -> [JSON] {
        guard !sheet.isEmpty else { return [] }
        let project = projectID, snapshot = reportID
        let args: [String:Any] = ["project_id":project,"report_id":snapshot,"revision_occurrence_id":occurrence,"sheet_id":sheet,"row_start":row,"row_limit":rowLimit,"column_start":column,"column_limit":columnLimit]
        let value = try await bridge.call("workbookGrid",args,owner:ticket.owner)
        guard current(ticket), rangeScope == identity else { throw CancellationError() }
        let cells = value["items"].array
        guard value["project_id"].string == project,value["report_id"].string == snapshot,value["revision_occurrence_id"].string == occurrence,value["sheet_id"].string == sheet,cells.count <= rowLimit*columnLimit,cells.allSatisfy({$0["row"].int >= row && $0["row"].int < row+rowLimit && $0["column"].int >= column && $0["column"].int < column+columnLimit}) else { throw BridgeError(code:"WORKBOOK_RANGE_SCOPE",message:"셀 범위 응답의 버전·시트·주소를 확인하지 못했습니다.") }
        return cells
    }
    func loadRange() async {
        guard ready else { return }
        let ticket = begin("range"), identity = rangeScope
        let old = beforeID, new = afterID, left = beforeSheetID, right = afterSheetID
        let leftRow = beforeRowStart, leftColumn = beforeColumnStart, rightRow = afterRowStart, rightColumn = afterColumnStart
        beforeCells = []; afterCells = []; rangeFailure = ""; loadingRange = true
        do {
            let a = try await rangeCells(occurrence:old,sheet:left,row:leftRow,column:leftColumn,ticket:ticket,identity:identity)
            guard current(ticket), rangeScope == identity else { return }
            let b: [JSON]
            if old == new && left == right && leftRow == rightRow && leftColumn == rightColumn { b = a }
            else { b = try await rangeCells(occurrence:new,sheet:right,row:rightRow,column:rightColumn,ticket:ticket,identity:identity) }
            guard current(ticket), rangeScope == identity else { return }
            beforeCells = a; afterCells = b; loadingRange = false
        } catch {
            guard current(ticket), rangeScope == identity else { return }
            beforeCells = []; afterCells = []; loadingRange = false; rangeFailure = error.localizedDescription
        }
    }
    func loadChanges(next: Bool = false,previous: Bool = false,preserveEndpoints: Bool = false) async {
        guard ready, !beforeID.isEmpty, !afterID.isEmpty else { return }
        guard !(next && previous),!next || !changeCursor.isEmpty,!previous || !changePreviousCursors.isEmpty else { return }
        let reset = !next && !previous
        if reset {
            if !preserveEndpoints { changesFromID = beforeID; changesToID = afterID }
            changesMode = mode; changes = []; resetChangePaging()
        }
        let targetCursor = next ? changeCursor : previous ? changePreviousCursors.last ?? "" : ""
        var back = changePreviousCursors
        let targetPage = next ? changePageNumber+1 : previous ? max(1,changePageNumber-1) : 1
        if next { back.append(changePageCursor); if back.count > cursorHistoryLimit { back.removeFirst(back.count-cursorHistoryLimit) } }
        if previous { back.removeLast() }
        let ticket = begin("changes"), identity = comparisonScope
        loadingChanges = true; changesFailure = ""; selectedChangeID = ""
        var args: [String:Any] = ["from_revision_occurrence_id":changesFromID,"to_revision_occurrence_id":changesToID,"mode":changesMode,"limit":100,"max_output_tokens":pagingOutputBudget,"text_length":128]
        if !targetCursor.isEmpty { args["cursor"] = targetCursor }
        do {
            let value = try await query("list_workbook_changes",args,ticket:ticket)
            guard current(ticket), comparisonScope == identity else { return }
            changes = value["items"].array; changeCursor = value["next_cursor"].string
            changePageCursor = targetCursor; changePreviousCursors = back; changePageNumber = targetPage
            changeTotal = value["total"].int; loadingChanges = false
        } catch {
            guard current(ticket), comparisonScope == identity else { return }
            if changesMode == "range_net",(error as? BridgeError)?.code == "WORKBOOK_DIFF_LIMIT" {
                loadingChanges = false; mode = "history"
                comparisonNotice = "양끝 차이 계산 한도에 도달하여 구간 전체 이력으로 표시합니다. 두 버전 사이의 순변경과는 다릅니다."
                await loadChanges(preserveEndpoints:true); return
            }
            selectedChangeID = ""; loadingChanges = false; changesFailure = error.localizedDescription
        }
    }
    func changeMode(_ value: String) async {
        guard ready else { return }
        // Evidence navigation may show an adjacent pair inside a wider interval.
        // Changing the comparison method does not constitute a new version pick.
        let preserve = revisions.contains(where:{$0["revision_occurrence_id"].string == changesFromID}) && revisions.contains(where:{$0["revision_occurrence_id"].string == changesToID})
        mode = value; comparisonNotice = ""; await loadChanges(preserveEndpoints:preserve)
    }
    func moveWindow(rows: Int = 0, columns: Int = 0) async {
        guard ready else { return }
        revealGeneration += 1
        rowStart = min(1_048_576-rowLimit+1,max(1,rowStart+rows))
        columnStart = min(16_384-columnLimit+1,max(1,columnStart+columns))
        clearCells(); addressInput = WorkbookGrid.address(rowStart,columnStart); await loadRange()
    }
    func goToAddress() async {
        guard ready else { return }
        guard let (row,column) = WorkbookGrid.parseAddress(addressInput) else { addressFailure = "A1–XFD1048576 형식의 물리 셀 주소를 입력하세요."; return }
        rowStart = max(1,min(row,1_048_576-rowLimit+1)); columnStart = max(1,min(column,16_384-columnLimit+1))
        clearCells(); addressInput = WorkbookGrid.address(row,column); let identity = rangeScope
        await loadRange(); guard ready, rangeScope == identity else { return }; await selectCell(row,column)
    }
    func selectCell(_ row: Int, _ column: Int) async {
        guard ready else { return }
        addressFailure = ""
        revealGeneration += 1
        let previousRange = rangeScope
        if beforeRowStart != afterRowStart || row < beforeRowStart || row >= beforeRowStart+rowLimit {
            rowStart = min(row,1_048_576-rowLimit+1)
        }
        if beforeColumnStart != afterColumnStart || column < beforeColumnStart || column >= beforeColumnStart+columnLimit {
            columnStart = min(column,16_384-columnLimit+1)
        }
        selectedChangeID = ""; selectedRow = row; selectedColumn = column
        beforeAddress = WorkbookGrid.address(row,column); afterAddress = beforeAddress
        if rangeScope != previousRange {
            let identity = rangeScope
            await loadRange()
            guard ready,rangeScope == identity,beforeAddress == WorkbookGrid.address(row,column),afterAddress == beforeAddress else { return }
        }
        await loadSelectedCells()
    }
    func loadSelectedCells(offset: Int = 0) async {
        guard ready else { return }
        invalidate("history")
        let oldAddress = beforeAddress, newAddress = afterAddress
        beforeCell = JSON(); afterCell = JSON(); resetCellHistory(); cellFailure = ""; loadingCell = true; cellTextOffset = offset; cellTextNext = nil
        let ticket = begin("cell"), identity = rangeScope
        do {
            var a = JSON(), b = JSON()
            if !beforeSheetID.isEmpty,let (row,column) = WorkbookGrid.parseAddress(oldAddress) {
                let value = try await query("get_workbook_cell",["revision_occurrence_id":beforeID,"sheet_id":beforeSheetID,"row":row,"column":column,"text_offset":offset,"text_length":1024,"max_output_tokens":8000],ticket:ticket)
                guard current(ticket), rangeScope == identity, beforeAddress == oldAddress, afterAddress == newAddress else { return }
                a = try scopedCellResult(value,occurrence:beforeID,sheet:beforeSheetID,address:oldAddress)
            }
            if !afterSheetID.isEmpty,let (row,column) = WorkbookGrid.parseAddress(newAddress) {
                let value = try await query("get_workbook_cell",["revision_occurrence_id":afterID,"sheet_id":afterSheetID,"row":row,"column":column,"text_offset":offset,"text_length":1024,"max_output_tokens":8000],ticket:ticket)
                guard current(ticket), rangeScope == identity, beforeAddress == oldAddress, afterAddress == newAddress else { return }
                b = try scopedCellResult(value,occurrence:afterID,sheet:afterSheetID,address:newAddress)
            }
            guard current(ticket), rangeScope == identity, beforeAddress == oldAddress, afterAddress == newAddress else { return }
            beforeCell = a; afterCell = b; loadingCell = false
            cellTextNext = [a,b].flatMap { cell in ["value","formula","number_format"].compactMap { key -> Int? in let cursor = cell["text_continuations"][key]["next_offset"]; return cursor.isNull ? nil : cursor.int } }.filter { $0 > offset }.min()
        } catch {
            guard current(ticket), rangeScope == identity, beforeAddress == oldAddress, afterAddress == newAddress else { return }
            beforeCell = JSON(); afterCell = JSON(); loadingCell = false; cellFailure = error.localizedDescription
        }
    }
    private func scopedCellResult(_ value: JSON,occurrence: String,sheet: String,address: String) throws -> JSON {
        let items = value["items"].array
        guard value["project_id"].string == projectID,value["report_id"].string == reportID,value["revision_occurrence_id"].string == occurrence,value["sheet_id"].string == sheet,value["items"].raw is [Any] else {
            throw BridgeError(code:"WORKBOOK_CELL_SCOPE",message:"셀 원문 응답의 버전·시트·주소를 확인하지 못했습니다.")
        }
        if value["availability"].string == "not_materialized",items.isEmpty { return JSON() }
        guard value["availability"].string == "available",items.count == 1,let (row,column) = WorkbookGrid.parseAddress(address),items[0]["address"].string == address,items[0]["row"].number == Double(row),items[0]["column"].number == Double(column) else {
            throw BridgeError(code:"WORKBOOK_CELL_SCOPE",message:"셀 원문 응답의 버전·시트·주소를 확인하지 못했습니다.")
        }
        return items[0]
    }
    func chooseChange(_ id: String) async {
        guard ready, let change = changes.first(where:{$0["change_id"].string == id}) else { return }
        addressFailure = ""
        revealGeneration += 1
        invalidate("cell"); resetCellHistory(); beforeCell = JSON(); afterCell = JSON(); cellFailure = ""; loadingCell = true
        let a = change["from_revision_occurrence_id"].string, b = change["to_revision_occurrence_id"].string
        guard revisions.contains(where:{$0["revision_occurrence_id"].string == a}), revisions.contains(where:{$0["revision_occurrence_id"].string == b}) else {
            beforeAddress = ""; afterAddress = ""; selectedChangeID = ""; selectedRow = 0; selectedColumn = 0; cellTextOffset = 0; cellTextNext = nil
            loadingCell = false; cellFailure = "변경의 버전 근거를 찾지 못했습니다."; return
        }
        beforeID = a; afterID = b
        beforeSheetID = change["from_sheet_id"].string; afterSheetID = change["to_sheet_id"].string
        let address = change["after_address"].string.isEmpty ? change["before_address"].string : change["after_address"].string
        if let (row,column) = WorkbookGrid.parseAddress(address) {
            rowStart = min(row,1_048_576-rowLimit+1); columnStart = min(column,16_384-columnLimit+1)
            selectedRow = row; selectedColumn = column; addressInput = address
        } else { selectedRow = 0; selectedColumn = 0 }
        selectedChangeID = id; beforeAddress = change["before_address"].string; afterAddress = change["after_address"].string
        if let coordinate = paneCoordinate(before:true) { beforeRowStart = min(coordinate.row,1_048_576-rowLimit+1); beforeColumnStart = min(coordinate.column,16_384-columnLimit+1) }
        if let coordinate = paneCoordinate(before:false) { afterRowStart = min(coordinate.row,1_048_576-rowLimit+1); afterColumnStart = min(coordinate.column,16_384-columnLimit+1) }
        beforeCell = JSON(); afterCell = JSON(); cellTextOffset = 0; cellTextNext = nil
        await loadRange()
        if currentChangeIs(id) { await loadSelectedCells() }
    }
    private func currentChangeIs(_ id: String) -> Bool { ready && selectedChangeID == id }
    func stepChange(_ offset: Int) async {
        guard ready,!loadingChanges,!changes.isEmpty else { return }
        let index = changes.firstIndex(where:{$0["change_id"].string == selectedChangeID}) ?? (offset > 0 ? -1 : changes.count)
        let target = index + offset
        if changes.indices.contains(target) { await chooseChange(changes[target]["change_id"].string) }
        else {
            let identity = comparisonScope,oldCursor = changePageCursor
            if offset > 0,!changeCursor.isEmpty { await loadChanges(next:true) }
            else if offset < 0,!changePreviousCursors.isEmpty { await loadChanges(previous:true) }
            else { return }
            guard ready,comparisonScope == identity,changePageCursor != oldCursor,changesFailure.isEmpty,let change = (offset > 0 ? changes.first : changes.last) else { return }
            await chooseChange(change["change_id"].string)
        }
    }
    func loadCellHistory(next: Bool = false,previous: Bool = false) async {
        guard ready,let anchor = cellHistoryAnchor else { return }
        if (next || previous),cellHistoryCursorAnchor != anchor { resetCellHistory(); return }
        guard !(next && previous),!next || !cellHistoryCursor.isEmpty,!previous || !cellHistoryPreviousCursors.isEmpty else { return }
        let ticket = begin("history"), identity = rangeScope
        let cursor = next ? cellHistoryCursor : previous ? cellHistoryPreviousCursors.last ?? "" : ""
        var back = !next && !previous ? [] : cellHistoryPreviousCursors
        let targetPage = next ? cellHistoryPageNumber+1 : previous ? max(1,cellHistoryPageNumber-1) : 1
        if next { back.append(cellHistoryPageCursor); if back.count > cursorHistoryLimit { back.removeFirst(back.count-cursorHistoryLimit) } }
        if previous { back.removeLast() }
        loadingHistory = true; cellHistoryFailure = ""
        do {
            var args: [String:Any] = ["revision_occurrence_id":anchor.occurrence,"sheet_id":anchor.sheet,"row":anchor.row,"column":anchor.column,"limit":100,"max_output_tokens":pagingOutputBudget,"text_length":128]
            if !cursor.isEmpty { args["cursor"] = cursor }
            let value = try await query("get_workbook_cell_history",args,ticket:ticket)
            guard current(ticket), rangeScope == identity, cellHistoryAnchor == anchor else { return }
            cellHistory = value["items"].array
            cellHistoryCursor = value["next_cursor"].string; cellHistoryTotal = value["total"].int
            cellHistoryPageCursor = cursor; cellHistoryCursorAnchor = anchor; cellHistoryPreviousCursors = back; cellHistoryPageNumber = targetPage; loadingHistory = false
            cellHistoryMessage = cellHistory.isEmpty ? "기록된 셀 이력이 없습니다." : "이번 페이지 \(cellHistory.count)개 / 총 \(cellHistoryTotal)개 · 첫 열 고유 키로 추정한 이력이며 대응 미확정 위치는 명시합니다."
        } catch {
            guard current(ticket), rangeScope == identity, cellHistoryAnchor == anchor else { return }
            loadingHistory = false; cellHistoryFailure = error.localizedDescription
        }
    }
    func loadReleases() async {
        guard ready else { return }; let ticket = begin("releases"), identity = scope
        do {
            let value = try await bridge.call("workbookReleases",["project_id":projectID],owner:ticket.owner)
            guard current(ticket), scope == identity else { return }
            releases = value.raw is [Any] ? value.array : value["items"].array
        } catch { guard current(ticket), scope == identity else { return }; failure = error.localizedDescription }
    }
    private func noteRecovery(_ message: String,project: String,run: String) { recoveryWarningRuns[project] = run; recoveryWarnings[project] = message }
    private func clearRecovery(project: String,run: String) {
        if recoveryWarningRuns[project] == run { recoveryWarningRuns.removeValue(forKey:project); recoveryWarnings.removeValue(forKey:project) }
    }
    func run() async {
        guard active, !busy, !loadingDemo, !projectID.isEmpty else { return }
        let project = projectID, oldReport = reportID, token = UUID()
        defer { bridge.releaseAnalysis(owner:token) }
        var stagedRunID = ""
        var commitAttempted = false
        analysisToken = token; committing = false
        invalidateReads(); busy = true; cancelRequested = false; failure = ""; status = "원본 통합 문서를 읽고 버전 차이를 분석하는 중…"
        do {
            let staged = try await bridge.call("workbookAnalyze",["project_id":project],analysis:true,analysisOwner:token,holdAnalysis:true)
            stagedRunID = staged["analysis_run_id"].string
            guard active, !cancelRequested, projectID == project else { throw CancellationError() }
            committing = true; commitAttempted = true; status = "고정 보고서를 저장하는 중…"
            let committed = try await bridge.call("workbookCommit",["project_id":project,"result":staged.raw])
            if committed["cleanup_pending"].bool { noteRecovery("분석 결과는 저장됐으며 임시 파일 정리를 확인해야 합니다.",project:project,run:stagedRunID) }
            else { clearRecovery(project:project,run:stagedRunID) }
            stagedRunID = ""
            bridge.releaseAnalysis(owner:token)
            guard projectID == project else { throw CancellationError() }
            analysisToken = nil; committing = false; busy = false; status = "분석 완료 · 원본과 보고서를 고정했습니다."
            let completion = begin("analysis-completion")
            await refreshProjects()
            guard active, current(completion), projectID == project else { return }
            await selectProject(project,snapshot:committed["report_id"].string)
            if active,projectID == project,reportID == committed["report_id"].string { status = "분석 완료 · 원본과 보고서를 고정했습니다." }
        } catch {
            var recoveryReport = "",cleanupFailure = "",saveUncertain = false
            if !stagedRunID.isEmpty {
                // A lost commit reply does not establish a failed commit. Check
                // this exact owned run before considering its staged-file cleanup.
                committing = true; status = "이번 분석의 저장 상태를 확인하는 중…"
                do {
                    let run = try await bridge.call("workbookRunStatus",["project_id":project,"analysis_run_id":stagedRunID])
                    guard run["project_id"].string == project,run["analysis_run_id"].string == stagedRunID else { throw BridgeError(code:"WORKBOOK_RUN_SCOPE",message:"이번 분석의 저장 상태 범위를 확인하지 못했습니다.") }
                    if run["status"].string == "success",!run["report_id"].string.isEmpty {
                        recoveryReport = run["report_id"].string; clearRecovery(project:project,run:stagedRunID)
                    } else if run["status"].string == "staged" {
                        status = "이번 분석의 임시 결과를 정리하는 중…"
                        do { _ = try await bridge.call("workbookDiscard",["project_id":project,"analysis_run_id":stagedRunID]); clearRecovery(project:project,run:stagedRunID) }
                        catch { cleanupFailure = "임시 분석 정리를 확인하지 못했습니다: " + error.localizedDescription }
                    } else if run["status"].string != "failed" {
                        saveUncertain = commitAttempted; cleanupFailure = "이번 분석의 저장·정리 상태를 다시 확인해야 합니다."
                    }
                } catch {
                    saveUncertain = commitAttempted
                    cleanupFailure = (saveUncertain ? "저장 여부 확인 필요: " : "임시 분석 상태 확인 필요: ") + error.localizedDescription
                }
                if !cleanupFailure.isEmpty { noteRecovery(cleanupFailure,project:project,run:stagedRunID) }
            }
            // The database outcome/owned cleanup attempt is settled before UI
            // reads. A slow or cancelled report refresh cannot hold the writer.
            bridge.releaseAnalysis(owner:token)
            analysisToken = nil; committing = false; busy = false
            if !recoveryReport.isEmpty {
                let completion = begin("analysis-completion")
                await refreshProjects()
                guard active,current(completion),projectID == project else { return }
                await selectProject(project,snapshot:recoveryReport)
                if active,projectID == project,reportID == recoveryReport { status = ready ? "저장된 분석 결과를 확인해 다시 열었습니다." : "저장된 분석 결과를 확인했습니다. 화면을 다시 불러와주세요." }
                return
            }
            let cancelled = cancelRequested || error is CancellationError || (error as? BridgeError)?.code == "CANCELLED"
            let outcome = saveUncertain ? "저장 여부 확인 필요 · 마지막으로 확인한 보고서를 표시합니다." : cancelled ? "분석을 취소했습니다. 이전 고정 보고서를 유지합니다." : "분석하지 못했습니다. 이전 고정 보고서를 유지합니다."
            let message = error.localizedDescription
            if active, projectID == project, !oldReport.isEmpty { await selectProject(project,snapshot:oldReport) }
            guard projectID == project else { return }
            failure = cancelled || saveUncertain ? "" : message
            status = outcome
        }
    }
    func cancelAnalysis() { guard canCancelAnalysis,let token = analysisToken else { return }; cancelRequested = true; status = "취소 중… 이전 고정 보고서를 유지합니다."; bridge.cancel(owner:token) }
    func create(title: String, rows: [WorkbookImportRow]) async throws {
        guard active, !busy, !loadingDemo else { throw BridgeError(code:"WORKBOOK_BUSY",message:"현재 작업이 끝난 뒤 가져오세요.") }
        busy = true; failure = ""; invalidateReads()
        do {
            let value = try await bridge.call("workbookCreate",["title":title,"revisions":rows.map { ["label":$0.label,"path":$0.url.path,"expected_sha256":$0.identity.sha256] }])
            busy = false; importPresented = false
            guard active else { return }
            let project = value["project_id"].string, completion = begin("create-completion")
            await refreshProjects()
            guard active, current(completion) else { return }
            await selectProject(project)
            guard active, projectID == project else { return }; await run()
        } catch { busy = false; throw error }
    }
    func useDemo() async {
        guard active, !busy, !loadingDemo, !loadingReport else { return }
        let ticket = begin("demo"), identity = scope, resources = bridge.resources
        loadingDemo = true; failure = ""; status = "합성 엑셀 3버전의 원본을 확인하는 중…"
        defer { if current(ticket) { loadingDemo = false } }
        do {
            let demo = try await Task.detached(priority:.userInitiated) { try WorkbookImportRow.bundledDemo(resources:resources) }.value
            guard active, current(ticket), scope == identity else { return }
            loadingDemo = false
            do { try await create(title:demo.title,rows:demo.rows) }
            catch { if active,scope == identity { failure = error.localizedDescription; status = "데모를 가져오지 못했습니다." } }
        } catch {
            guard active, current(ticket), scope == identity else { return }
            failure = error.localizedDescription; status = "데모를 가져오지 못했습니다."
        }
    }
    func publish(label: String, reason: String) async throws {
        guard ready else { throw BridgeError(code:"WORKBOOK_NOT_READY",message:"고정 보고서를 먼저 선택하세요.") }
        let project = projectID, snapshot = reportID; busy = true
        do {
            _ = try await bridge.call("workbookPublish",["project_id":project,"report_id":snapshot,"label":label,"reason":reason])
            guard projectID == project, reportID == snapshot else { busy = false; return }
            busy = false; publishPresented = false; status = "현재 보고서를 로컬 배포본으로 고정했습니다."; await loadReleases()
        } catch { busy = false; throw error }
    }
    func export() async {
        guard ready else { return }
        let panel = NSOpenPanel(); panel.canChooseFiles = false; panel.canChooseDirectories = true; panel.canCreateDirectories = true
        panel.prompt = "내보내기"; panel.message = "고정 보고서의 JSON·Markdown을 저장할 폴더를 선택하세요."
        guard panel.runModal() == .OK, let folder = panel.url else { return }
        let project = projectID, snapshot = reportID; busy = true; failure = ""
        do {
            _ = try await bridge.call("workbookExport",["project_id":project,"report_id":snapshot,"folder":folder.path])
            guard projectID == project, reportID == snapshot else { busy = false; return }
            busy = false; status = "고정 보고서를 내보냈습니다: " + folder.path
        } catch { busy = false; if projectID == project, reportID == snapshot { failure = error.localizedDescription } }
    }
    func loadMCP() async {
        guard ready else { return }
        let ticket = begin("mcp"), identity = scope; loadingMCP = true; mcp = ""; mcpScope = ""; mcpFailure = ""
        do {
            let value = try await bridge.call("workbookMcpConfig",["project_id":projectID,"report_id":reportID],owner:ticket.owner)
            guard current(ticket), ready, scope == identity else { return }
            mcp = value["config"].string.isEmpty ? value.string : value["config"].string
            if mcp.isEmpty, !value.dictionary.isEmpty { mcp = String(decoding:try value.data(),as:UTF8.self) }
            guard !mcp.isEmpty else { throw BridgeError(code:"WORKBOOK_MCP_EMPTY",message:"MCP 설정을 받지 못했습니다.") }
            mcpScope = identity; loadingMCP = false
        } catch { guard current(ticket), scope == identity else { return }; mcp = ""; mcpScope = ""; loadingMCP = false; mcpFailure = error.localizedDescription }
    }
    var canCopyMCP: Bool { ready && !mcp.isEmpty && mcpScope == scope && !loadingMCP }
    func copyMCP() { guard canCopyMCP else { return }; NSPasteboard.general.clearContents(); NSPasteboard.general.setString(mcp,forType:.string) }
}

struct WorkbookWorkspace: View {
    @StateObject var model: WorkbookModel
    init(bridge: Bridge) { _model = StateObject(wrappedValue:WorkbookModel(bridge:bridge)) }
    var body: some View {
        VStack(spacing:0) {
            HSplitView {
                sidebar.frame(minWidth:205,idealWidth:225,maxWidth:290)
                VStack(spacing:0) {
                    reportBar
                    if model.loadingReport { WorkbookStatus(title:"고정 보고서를 불러오는 중…",detail:"다른 버전의 셀을 섞어 표시하지 않습니다.",loading:true) }
                    else if model.report.isNull { emptyWorkspace }
                    else if model.tab == "compare" { comparison }
                    else { aiAndReleases }
                }.frame(minWidth:640,maxWidth:.infinity,maxHeight:.infinity)
                if model.inspectorVisible, model.tab == "compare", !model.report.isNull { WorkbookInspector(model:model).frame(minWidth:260,idealWidth:290,maxWidth:380) }
            }
            Divider()
            HStack(spacing:8) {
                if model.busy || model.loadingDemo { ProgressView().controlSize(.small) }
                Text(verbatim:model.status.isEmpty ? "수식·매크로·외부 연결을 실행하지 않습니다. 저장된 결과는 재계산값이 아닙니다." : model.status).lineLimit(2)
                Spacer(); Text("읽기 전용 · workbook.1")
            }.font(.caption).foregroundStyle(.secondary).padding(.horizontal,12).padding(.vertical,6)
        }.frame(minWidth:1180,minHeight:760).background(Color(nsColor:.windowBackgroundColor)).preferredColorScheme(.light)
        .toolbar {
            ToolbarItem { Text("스프레드시트 버전 비교").font(.headline) }
            ToolbarItemGroup(placement:.primaryAction) {
                Picker("작업",selection:$model.tab) { Text("셀 비교").tag("compare"); Text("AI·배포본").tag("ai") }.pickerStyle(.segmented).frame(width:200)
                Button { model.inspectorVisible.toggle() } label: { Label("셀 근거",systemImage:"sidebar.right") }
                Button { model.importPresented = true } label: { Label("버전 가져오기",systemImage:"plus") }.disabled(model.busy || model.loadingDemo)
            }
        }
        .sheet(isPresented:$model.importPresented) { WorkbookImportSheet(model:model) }
        .sheet(isPresented:$model.publishPresented) { WorkbookPublishSheet(model:model) }
        .task { await model.start(); await WorkbookNativeSmoke.runIfRequested(model) }
        .onDisappear { model.closeReads() }
    }
    private var sidebar: some View {
        VStack(alignment:.leading,spacing:10) {
            HStack { Text("통합 문서").font(.headline); Spacer(); Button { Task { await model.refreshProjects() } } label: { Image(systemName:"arrow.clockwise") }.disabled(model.busy) }
            List(selection:Binding<String?>(get:{model.projectID.isEmpty ? nil : model.projectID},set:{if let id = $0 { Task { await model.selectProject(id) } }})) {
                ForEach(model.projects,id:\.id) { project in
                    VStack(alignment:.leading,spacing:3) { Text(verbatim:project["title"].string).lineLimit(2); Text("버전 \(project["revision_count"].int)개").font(.caption).foregroundStyle(.secondary) }.tag(project["project_id"].string)
                }
            }.disabled(model.busy || model.loadingDemo).frame(minHeight:130,maxHeight:260)
            Button { model.importPresented = true } label: { Label("XLSX·ODS·CSV 가져오기",systemImage:"plus.circle") }.disabled(model.busy || model.loadingDemo)
            Button("3버전 엑셀 데모") { Task { await model.useDemo() } }.disabled(model.busy || model.loadingDemo || model.loadingReport)
            Divider()
            Text("버전 · 저장된 순서").font(.headline)
            ScrollView {
                VStack(alignment:.leading,spacing:9) {
                    ForEach(model.revisions,id:\.id) { r in
                        VStack(alignment:.leading,spacing:3) {
                            Text(verbatim:"v\(r["index"].int+1) · \(r["label"].string)").font(.callout.weight(.medium)).lineLimit(2)
                            HStack { Text(r["format"].string.uppercased()); Text("\(r["sheets"].array.count)개 시트"); if r["revision_occurrence_id"].string == model.beforeID { Text("이전").foregroundStyle(.orange) }; if r["revision_occurrence_id"].string == model.afterID { Text("이후").foregroundStyle(.blue) } }.font(.caption).foregroundStyle(.secondary)
                        }.frame(maxWidth:.infinity,alignment:.leading)
                    }
                }.padding(.horizontal,3)
            }
            if !model.projectID.isEmpty {
                if model.busy { Button("분석 취소") { model.cancelAnalysis() }.disabled(!model.canCancelAnalysis) }
                else { Button("이 프로젝트 다시 분석") { Task { await model.run() } }.disabled(model.loadingReport || model.loadingDemo) }
            }
            Text("파일 하나가 버전 하나입니다. 같은 파일이 다시 등장해도 버전의 위치는 구별합니다.").font(.caption).foregroundStyle(.secondary)
        }.padding(12)
    }
    private var reportBar: some View {
        VStack(alignment:.leading,spacing:7) {
            HStack {
                Text(verbatim:model.project["title"].string.isEmpty ? "스프레드시트" : model.project["title"].string).font(.title3.weight(.semibold)).lineLimit(1)
                Spacer()
                if !model.reports.isEmpty {
                    Picker("고정 보고서",selection:Binding(get:{model.reportID},set:{id in Task { await model.selectReport(id) }})) {
                        ForEach(model.reports,id:\.id) { r in Text(verbatim:r["created_at"].string + " · " + String(r["report_id"].string.suffix(8))).tag(r["report_id"].string) }
                    }.frame(maxWidth:340).disabled(model.busy || model.loadingReport || model.loadingDemo)
                }
            }
            if !model.failure.isEmpty { Text(verbatim:model.failure).font(.caption).foregroundStyle(.red).textSelection(.enabled) }
            if !model.recoveryWarning.isEmpty { Text(verbatim:model.recoveryWarning).font(.caption).foregroundStyle(.orange).textSelection(.enabled) }
        }.padding(12)
    }
    private var emptyWorkspace: some View {
        VStack(spacing:0) {
            WorkbookStatus(title:model.projects.isEmpty ? "업무 파일의 버전별 변경을 확인하세요" : "분석한 통합 문서가 없습니다",detail:"XLSX·ODS·UTF-8 CSV 원본을 순서대로 가져오세요. 수식 원문, 입력값, 저장된 계산 결과를 분리해서 비교합니다.",loading:model.loadingDemo)
            Button("3버전 엑셀 데모") { Task { await model.useDemo() } }.buttonStyle(.borderedProminent).disabled(model.busy || model.loadingDemo || model.loadingReport).padding(.bottom,24)
        }
    }
    private var comparison: some View {
        VStack(spacing:0) {
            versionBar
            Divider()
            HStack {
                TextField("셀 주소 · A1",text:$model.addressInput).textFieldStyle(.roundedBorder).frame(width:130).onSubmit { Task { await model.goToAddress() } }
                Button("이동") { Task { await model.goToAddress() } }
                Spacer()
                Button { Task { await model.moveWindow(columns:-model.columnLimit) } } label: { Image(systemName:"chevron.left") }.disabled(model.columnStart == 1).accessibilityLabel("이전 12열")
                Text("\(model.navigationRangePrefix)\(WorkbookGrid.columnLabel(model.columnStart))–\(WorkbookGrid.columnLabel(model.columnStart+model.columnLimit-1))열").font(.caption.monospacedDigit())
                Button { Task { await model.moveWindow(columns:model.columnLimit) } } label: { Image(systemName:"chevron.right") }.disabled(model.columnStart+model.columnLimit>16384).accessibilityLabel("다음 12열")
                Button { Task { await model.moveWindow(rows:-model.rowLimit) } } label: { Image(systemName:"chevron.up") }.disabled(model.rowStart == 1).accessibilityLabel("이전 100행")
                Text("\(model.navigationRangePrefix)\(model.rowStart)–\(model.rowStart+model.rowLimit-1)행").font(.caption.monospacedDigit())
                Button { Task { await model.moveWindow(rows:model.rowLimit) } } label: { Image(systemName:"chevron.down") }.disabled(model.rowStart+model.rowLimit>1048576).accessibilityLabel("다음 100행")
            }.padding(.horizontal,12).padding(.vertical,7).disabled(!model.ready)
            if !model.addressFailure.isEmpty { Text(verbatim:model.addressFailure).font(.caption).foregroundStyle(.red).padding(8) }
            if !model.rangeFailure.isEmpty {
                HStack {
                    Text(verbatim:model.rangeFailure).font(.caption).foregroundStyle(.red).textSelection(.enabled)
                    Button("셀 범위 다시 읽기") { Task { await model.loadRange() } }.disabled(!model.ready || model.loadingRange)
                }.padding(8)
            }
            HSplitView {
                gridPane(before:true)
                gridPane(before:false)
            }.frame(minHeight:240,maxHeight:.infinity).overlay { if model.loadingRange { ZStack { Color(nsColor:.windowBackgroundColor).opacity(0.94); ProgressView("셀 범위를 읽는 중…") } } }
            Text(model.independentPaneCoordinates ? "이전·이후 근거의 주소를 각각 표시합니다. 범위 이동·셀 선택을 하면 같은 물리 주소 탐색으로 돌아갑니다." : "같은 물리 주소로 나란히 탐색합니다. 빈 칸은 저장된 관측이 없는 위치이며 삭제를 뜻하지 않습니다.").font(.caption).foregroundStyle(.secondary).padding(.horizontal,12).padding(.vertical,6)
            Text("ƒ 수식 · ∅ 저장 결과 없음 · ?ƒ 수식 의미 미확정 · … 원문 일부").font(.caption2).foregroundStyle(.secondary).padding(.horizontal,12).padding(.bottom,5)
            Divider()
            changesPane.frame(minHeight:150,idealHeight:200,maxHeight:240)
        }
    }
    private var versionBar: some View {
        VStack(spacing:8) {
            HStack {
                versionPicker(title:"이전",selection:model.beforeID,before:true)
                Image(systemName:"arrow.right").foregroundStyle(.secondary)
                versionPicker(title:"이후",selection:model.afterID,before:false)
                Picker("차이 범위",selection:Binding(get:{model.mode},set:{value in Task { await model.changeMode(value) }})) { Text("두 버전 순변경").tag("range_net"); Text("구간 전체 이력").tag("history") }.frame(width:210)
            }
            HStack { sheetPicker(before:true); sheetPicker(before:false) }
        }.padding(.horizontal,12).padding(.bottom,10).disabled(!model.ready)
    }
    private func versionPicker(title: String, selection: String, before: Bool) -> some View {
        Picker(title,selection:Binding(get:{selection},set:{id in Task { if before { await model.changeVersions(before:id) } else { await model.changeVersions(after:id) } }})) {
            ForEach(model.revisions,id:\.id) { r in Text(verbatim:model.versionLabel(r["revision_occurrence_id"].string)).tag(r["revision_occurrence_id"].string) }
        }.frame(maxWidth:.infinity)
    }
    private func sheetPicker(before: Bool) -> some View {
        let occurrence = before ? model.beforeID : model.afterID
        let current = before ? model.beforeSheetID : model.afterSheetID
        return Picker(before ? "이전 시트" : "이후 시트",selection:Binding(get:{current},set:{id in Task { if before { await model.changeSheet(before:id) } else { await model.changeSheet(after:id) } }})) {
            if current.isEmpty { Text("시트 없음").tag("") }
            ForEach(model.sheets(occurrence),id:\.workbookSheetID) { s in Text(verbatim:s["name"].string + (s["hidden"].bool ? " · 숨김" : "") + " (\(s["row_count"].int)×\(s["column_count"].int))").tag(s["sheet_id"].string) }
        }.frame(maxWidth:.infinity)
    }
    private func gridPane(before: Bool) -> some View {
        let occurrence = before ? model.beforeID : model.afterID
        let id = before ? model.beforeSheetID : model.afterSheetID
        let sheet = model.sheet(occurrence,id)
        let cells = before ? model.beforeCells : model.afterCells
        let row = before ? model.beforeRowStart : model.afterRowStart
        let column = before ? model.beforeColumnStart : model.afterColumnStart
        let coordinate = model.paneCoordinate(before:before)
        return VStack(alignment:.leading,spacing:0) {
            HStack { Text(verbatim:(before ? "이전 · " : "이후 · ") + model.versionLabel(occurrence)).font(.caption.weight(.semibold)); Spacer(); if sheet["hidden"].bool { Label("숨김 시트",systemImage:"eye.slash").font(.caption) } }.padding(8).background(Color(nsColor:.controlBackgroundColor))
            HStack {
                Text("\(row)–\(row+model.rowLimit-1)행 · \(WorkbookGrid.columnLabel(column))–\(WorkbookGrid.columnLabel(column+model.columnLimit-1))열").font(.caption2).foregroundStyle(.secondary)
                Spacer()
                if let coordinate { Text("근거 \(WorkbookGrid.address(coordinate.row,coordinate.column))").font(.system(.caption,design:.monospaced)).foregroundStyle(.blue) }
            }.padding(.horizontal,8).padding(.bottom,5)
            if id.isEmpty { WorkbookStatus(title:"대응 시트 없음",detail:"다른 시트를 선택하거나 변경 근거에서 추가·삭제 여부를 확인하세요.",loading:false) }
            else { WorkbookGrid(pane:before ? "before" : "after",revealIntent:[model.scope,occurrence,id,String(model.revealGeneration)].joined(separator:"|"),cells:cells,rowStart:row,columnStart:column,rowCount:model.rowLimit,columnCount:model.columnLimit,selectedRow:coordinate?.row ?? 0,selectedColumn:coordinate?.column ?? 0,onSelect:{row,column in Task { await model.selectCell(row,column) }}).disabled(!model.ready || model.loadingRange) }
        }.frame(minWidth:280,maxWidth:.infinity,maxHeight:.infinity)
    }
    private var changesPane: some View {
        VStack(spacing:0) {
            HStack {
                Text(model.changesMode == "history" ? "구간의 중간 변경 이력" : "두 버전 사이의 순변경").font(.headline)
                Text("\(model.changePageNumber)페이지 · 표시 \(model.changes.count)개 / 총 \(model.changeTotal)개").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button { Task { await model.stepChange(-1) } } label: { Image(systemName:"chevron.up") }.accessibilityLabel("이전 변경")
                Button { Task { await model.stepChange(1) } } label: { Image(systemName:"chevron.down") }.accessibilityLabel("다음 변경")
                if model.changePageNumber > 1 { Button("처음") { Task { await model.loadChanges(preserveEndpoints:true) } } }
                if !model.changePreviousCursors.isEmpty { Button("이전 페이지") { Task { await model.loadChanges(previous:true) } } }
                if !model.changeCursor.isEmpty { Button("다음 페이지") { Task { await model.loadChanges(next:true) } } }
            }.padding(.horizontal,12).padding(.vertical,7).disabled(!model.ready || model.loadingChanges)
            Text(verbatim:"조회 구간 · " + model.versionLabel(model.changesFromID) + " → " + model.versionLabel(model.changesToID)).font(.caption).foregroundStyle(.secondary).lineLimit(1).padding(.horizontal,12).frame(maxWidth:.infinity,alignment:.leading)
            if !model.selectedChangeID.isEmpty,(model.changesFromID != model.beforeID || model.changesToID != model.afterID) { Text("목록은 조회 구간을 유지합니다. 위 비교는 선택한 변경이 발생한 두 버전입니다.").font(.caption2).foregroundStyle(.secondary).padding(.horizontal,12).frame(maxWidth:.infinity,alignment:.leading) }
            if !model.changeCursor.isEmpty { Text("응답 크기로 나누어 표시합니다. ‘다음 페이지’에서 변경을 계속 확인하세요.").font(.caption2).foregroundStyle(.secondary).padding(.horizontal,12).frame(maxWidth:.infinity,alignment:.leading) }
            else if !model.changePreviousCursors.isEmpty { Text("마지막 페이지입니다. 앞선 변경은 ‘이전 페이지’에서 확인하세요.").font(.caption2).foregroundStyle(.secondary).padding(.horizontal,12).frame(maxWidth:.infinity,alignment:.leading) }
            if !model.comparisonNotice.isEmpty { Text(verbatim:model.comparisonNotice).font(.caption).foregroundStyle(.orange).padding(.horizontal,12).padding(.vertical,3) }
            if model.changePageNumber > model.changePreviousCursors.count+1 { Text("최근 128개 페이지까지 되돌아갈 수 있습니다. 구간을 다시 선택하면 처음부터 조회합니다.").font(.caption2).foregroundStyle(.secondary).padding(.horizontal,12) }
            if model.loadingChanges { ProgressView("변경을 읽는 중…").frame(maxWidth:.infinity,maxHeight:.infinity) }
            else if !model.changesFailure.isEmpty { Text(verbatim:model.changesFailure).font(.caption).foregroundStyle(.red).padding(12).frame(maxWidth:.infinity,maxHeight:.infinity) }
            else if model.changes.isEmpty { Text("선택한 구간에서 기록된 변경이 없습니다. 판독 범위의 한계는 셀 근거에서 확인하세요.").font(.callout).foregroundStyle(.secondary).frame(maxWidth:.infinity,maxHeight:.infinity) }
            else {
                List(selection:Binding<String?>(get:{model.selectedChangeID.isEmpty ? nil : model.selectedChangeID},set:{if let id = $0 { Task { await model.chooseChange(id) } }})) {
                    ForEach(model.changes,id:\.workbookChangeID) { change in
                        HStack(spacing:10) {
                            Text(verbatim:WorkbookLabels.kind(change["kind"].string)).font(.caption.weight(.semibold)).frame(width:110,alignment:.leading)
                            Text(verbatim:change["before_address"].string + " → " + change["after_address"].string).font(.system(.caption,design:.monospaced)).frame(width:125,alignment:.leading)
                            Text(verbatim:WorkbookLabels.description(change)).font(.caption).lineLimit(2)
                            Spacer()
                            Text(verbatim:WorkbookLabels.association(change["association"].string)).font(.caption).foregroundStyle(change["association"].string == "needs_review" ? .orange : .secondary)
                        }.tag(change["change_id"].string)
                    }
                }.listStyle(.inset).disabled(!model.ready)
            }
        }
    }
    private var aiAndReleases: some View {
        ScrollView {
            VStack(alignment:.leading,spacing:18) {
                Text("AI가 고정된 버전·시트·셀 근거를 읽습니다").font(.title2.weight(.semibold))
                Text("MCP는 현재 프로젝트를 범위로 읽기 전용 도구를 제공합니다. 셀 주소와 버전 occurrence ID, 수식 원문과 저장된 값을 함께 인용하도록 요청하세요. 수식 계산과 외부 링크 갱신은 수행하지 않습니다.").foregroundStyle(.secondary)
                HStack { Button("MCP 설정 불러오기") { Task { await model.loadMCP() } }.disabled(!model.ready || model.loadingMCP); Button("설정 복사") { model.copyMCP() }.disabled(!model.canCopyMCP); if model.loadingMCP { ProgressView().controlSize(.small) } }
                if !model.mcpFailure.isEmpty { Text(verbatim:model.mcpFailure).foregroundStyle(.red).font(.caption) }
                if model.canCopyMCP { Text(verbatim:model.mcp).font(.system(.caption,design:.monospaced)).textSelection(.enabled).padding(12).frame(maxWidth:.infinity,alignment:.leading).background(Color(nsColor:.textBackgroundColor)).clipShape(RoundedRectangle(cornerRadius:6)) }
                Divider()
                HStack { Text("로컬 배포본").font(.headline); Spacer(); Button("현재 보고서 배포본 고정…") { model.publishPresented = true }.disabled(!model.ready); Button("보고서 내보내기…") { Task { await model.export() } }.disabled(!model.ready) }
                Text("이름·이유와 원본/보고서 식별자를 보존합니다. 로컬 기록이며 외부 전송이나 편집자 인증을 의미하지 않습니다.").font(.caption).foregroundStyle(.secondary)
                if model.releases.isEmpty { Text("고정한 배포본이 없습니다.").foregroundStyle(.secondary) }
                if model.releases.count > 100 { Text("배포본 중 최근 100개를 표시합니다.").font(.caption).foregroundStyle(.secondary) }
                ForEach(Array(model.releases.prefix(100).enumerated()),id:\.offset) { _, release in
                    VStack(alignment:.leading,spacing:5) {
                        Text(verbatim:release["label"].string).font(.headline)
                        Text(verbatim:release["reason"].string).textSelection(.enabled)
                        Text(verbatim:release["recorded_at"].string + " · " + release["report_id"].string).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                    }.padding(12).frame(maxWidth:.infinity,alignment:.leading).background(Color(nsColor:.controlBackgroundColor)).clipShape(RoundedRectangle(cornerRadius:6))
                }
                Divider()
                WorkbookCoverageView(gaps:model.coverage,total:model.report["coverage_gap_count"].int,truncated:model.report["coverage_truncated"].bool,revisions:model.revisions)
            }.padding(24).frame(maxWidth:1000,alignment:.leading)
        }
    }
}

private struct WorkbookStatus: View {
    let title: String
    let detail: String
    let loading: Bool
    var body: some View { VStack(spacing:12) { if loading { ProgressView() } else { Image(systemName:"tablecells").font(.system(size:36)).foregroundStyle(.secondary) }; Text(verbatim:title).font(.title3.weight(.semibold)); Text(verbatim:detail).font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth:520) }.padding(28).frame(maxWidth:.infinity,maxHeight:.infinity) }
}

private struct WorkbookInspector: View {
    @ObservedObject var model: WorkbookModel
    var body: some View {
        ScrollView {
            VStack(alignment:.leading,spacing:15) {
                HStack { Text("셀 근거").font(.headline); Spacer(); if model.selectedRow > 0 { Text(WorkbookGrid.address(model.selectedRow,model.selectedColumn)).font(.system(.headline,design:.monospaced)) } }
                Text("수식은 재계산하지 않음 · 저장값 기준").font(.caption.weight(.medium)).foregroundStyle(.orange)
                Text(verbatim:"날짜 기준: 이전 " + model.revision(model.beforeID)["date_system"].string + " / 이후 " + model.revision(model.afterID)["date_system"].string).font(.caption).foregroundStyle(.secondary)
                if model.loadingCell { ProgressView("셀을 읽는 중…") }
                else if !model.cellFailure.isEmpty {
                    Text(verbatim:model.cellFailure).font(.caption).foregroundStyle(.red)
                    if model.cellHistoryAnchor != nil { Button(model.cellTextOffset > 0 ? "원문 처음부터 다시 읽기" : "셀 원문 다시 읽기") { Task { await model.loadSelectedCells() } }.disabled(!model.ready) }
                }
                else if model.selectedRow == 0, model.selectedChangeID.isEmpty { Text("셀 또는 변경 항목을 선택하면 수식 원문·저장된 값·유형을 확인할 수 있습니다.").foregroundStyle(.secondary) }
                else { cellSection("이전 · " + model.versionLabel(model.beforeID),cell:model.beforeCell); Divider(); cellSection("이후 · " + model.versionLabel(model.afterID),cell:model.afterCell) }
                if !model.selectedChange.isNull {
                    Divider(); Text("변경과 대응 방법").font(.headline)
                    Text(verbatim:WorkbookLabels.kind(model.selectedChange["kind"].string)).font(.callout)
                    Text(verbatim:WorkbookLabels.association(model.selectedChange["association"].string)).font(.caption.weight(.medium))
                    Text(verbatim:WorkbookLabels.method(model.selectedChange["alignment_method"].string)).font(.caption).textSelection(.enabled)
                    Text(verbatim:WorkbookLabels.description(model.selectedChange)).font(.caption)
                    Text("추정 대응은 같은 업무 레코드임을 확정하지 않습니다. 모호한 대응을 삭제로 해석하지 마세요.").font(.caption).foregroundStyle(.secondary)
                }
                if model.selectedRow > 0 {
                    Button("선택 셀 이력 읽기") { Task { await model.loadCellHistory() } }.disabled(!model.ready || model.loadingCell || model.loadingHistory)
                    if model.loadingHistory { ProgressView("셀 이력 페이지를 읽는 중…").controlSize(.small) }
                    if !model.cellHistoryFailure.isEmpty { Text(verbatim:model.cellHistoryFailure).font(.caption).foregroundStyle(.red) }
                    if !model.cellHistoryMessage.isEmpty { Text(verbatim:model.cellHistoryMessage).font(.caption).foregroundStyle(.secondary) }
                    HStack {
                        if !model.cellHistoryPreviousCursors.isEmpty { Button("이전 이력 페이지") { Task { await model.loadCellHistory(previous:true) } } }
                        if !model.cellHistoryCursor.isEmpty { Button("다음 이력 페이지") { Task { await model.loadCellHistory(next:true) } } }
                    }.disabled(!model.ready || model.loadingCell || model.loadingHistory)
                    if !model.cellHistory.isEmpty { Text("\(model.cellHistoryPageNumber)페이지 · 최대 최근 128페이지 되돌리기").font(.caption2).foregroundStyle(.secondary) }
                    ForEach(Array(model.cellHistory.enumerated()),id:\.offset) { _, event in
                        VStack(alignment:.leading,spacing:3) {
                            Text(verbatim:model.versionLabel(event["revision_occurrence_id"].string)).lineLimit(2)
                            Text(verbatim:(event["cell"]["address"].string.isEmpty ? event["address"].string : event["cell"]["address"].string) + (event["cell"].isNull ? "" : " · " + event["cell"]["value"].string))
                            Text(verbatim:WorkbookLabels.availability(event["availability"].string) + " · " + WorkbookLabels.association(event["association"].string))
                            Text(verbatim:WorkbookLabels.method(event["alignment_method"].string))
                        }.font(.caption).textSelection(.enabled)
                    }
                }
                Divider()
                WorkbookSheetMetadata(title:"이전 시트 메타데이터",sheet:model.sheet(model.beforeID,model.beforeSheetID))
                WorkbookSheetMetadata(title:"이후 시트 메타데이터",sheet:model.sheet(model.afterID,model.afterSheetID))
                WorkbookCoverageView(gaps:model.coverage,total:model.report["coverage_gap_count"].int,truncated:model.report["coverage_truncated"].bool,revisions:model.revisions)
            }.padding(14).frame(maxWidth:.infinity,alignment:.leading)
        }.background(Color(nsColor:.controlBackgroundColor))
    }
    private func cellSection(_ title: String,cell: JSON) -> some View {
        WorkbookCellDetail(title:title,cell:cell,textOffset:model.cellTextOffset,nextTextOffset:model.cellTextNext,canPage:model.ready && !model.loadingCell,onTextPage:{ offset in Task { await model.loadSelectedCells(offset:offset) } })
    }
}
private struct WorkbookCellDetail: View {
    let title: String
    let cell: JSON
    let textOffset: Int
    let nextTextOffset: Int?
    let canPage: Bool
    let onTextPage: (Int) -> Void
    var body: some View {
        VStack(alignment:.leading,spacing:7) {
            Text(verbatim:title).font(.headline).lineLimit(2)
            if cell.isNull { Text("저장된 셀 관측 없음 · 삭제를 확정하지 않음").font(.caption).foregroundStyle(.secondary) }
            else {
                Text(verbatim:cell["address"].string + " · " + cell["value_type"].string).font(.system(.caption,design:.monospaced))
                if cell["formula_interpretation"].string == "unresolved" { Text("공유·배열 수식의 셀별 의미 확인 필요").font(.caption.weight(.medium)).foregroundStyle(.orange) }
                if !cell["formula"].isNull { rawDetail("수식 원문",field:"formula"); Text("수식은 실행하지 않았습니다.").font(.caption2).foregroundStyle(.secondary) }
                rawDetail(cell["formula_interpretation"].string == "unresolved" ? "저장된 관측값 · 입력/계산 결과 미확정" : cell["formula"].isNull ? "저장된 입력값" : "저장된 계산 결과",field:"value")
                if textOffset > 0 || ["value","formula","number_format"].contains(where:{cell["text_continuations"][$0]["state"].string == "truncated"}) {
                    HStack {
                        if textOffset > 0 { Button("양쪽 처음부터") { onTextPage(0) } }
                        if let nextTextOffset { Button("양쪽 원문 이어 읽기") { onTextPage(nextTextOffset) } }
                    }.disabled(!canPage)
                    Text("이전·이후 원문을 같은 UTF-16 위치로 함께 이동합니다.").font(.caption2).foregroundStyle(.secondary)
                }
                if !cell["number_format"].isNull { rawDetail("원본 숫자 형식",field:"number_format") }
                if cell["hidden_row"].bool || cell["hidden_column"].bool { Label((cell["hidden_row"].bool ? "숨김 행 " : "") + (cell["hidden_column"].bool ? "숨김 열" : ""),systemImage:"eye.slash").font(.caption).foregroundStyle(.orange) }
                if !cell["style"].dictionary.isEmpty { detail("원본 기본 스타일",cell["style"].dictionary.keys.sorted().map { $0 + ": " + cell["style"][$0].string }.joined(separator:"\n")) }
                if cell["style_truncated"].bool { Text("기본 스타일의 일부만 표시합니다.").font(.caption).foregroundStyle(.orange) }
                detail("원본 근거",cell["source_ref"].string)
            }
        }
    }
    private func sourceLabel(_ label: String,field: String) -> String {
        let continuation = cell["text_continuations"][field]
        if continuation["state"].string == "truncated" {
            let start = continuation["offset"].int,end = start+cell[field].string.utf16.count
            return label + " · 원문 일부\nUTF-16 \(start)–\(end) / \(continuation["total_length"].int) · 0부터, 끝 제외"
        }
        return label
    }
    private func rawDetail(_ label: String,field: String) -> some View {
        VStack(alignment:.leading,spacing:4) {
            Text(verbatim:sourceLabel(label,field:field)).font(.caption.weight(.medium)).foregroundStyle(.secondary)
            if let status = sourceStatus(field) {
                Text(verbatim:status).font(.caption).foregroundStyle(.secondary)
            } else {
                Text(verbatim:cell[field].string).font(.system(.caption,design:.monospaced)).textSelection(.enabled).fixedSize(horizontal:false,vertical:true)
            }
            if cell["text_continuations"][field]["state"].string == "truncated",!cell[field].string.isEmpty {
                Text(cell["text_continuations"][field]["next_offset"].isNull ? "— 원문 마지막 조각 끝 · 앞부분은 처음부터 확인할 수 있습니다." : "… 현재 조각 끝 · 뒤에 원문이 더 있습니다.").font(.caption2.weight(.medium)).foregroundStyle(.orange)
            }
        }
    }
    private func sourceStatus(_ field: String) -> String? {
        let raw = cell[field],continuation = cell["text_continuations"][field]
        if raw.isNull { return "값 관측 없음 · 빈 문자열/0과 다름" }
        if raw.string.isEmpty {
            if continuation["total_length"].int > 0 { return "앞부분에서 읽은 값 · 현재 조각 없음" }
            return "빈 문자열"
        }
        return nil
    }
    private func detail(_ label: String, _ value: String) -> some View { VStack(alignment:.leading,spacing:3) { Text(verbatim:label).font(.caption.weight(.medium)).foregroundStyle(.secondary); Text(verbatim:value).font(.system(.caption,design:.monospaced)).textSelection(.enabled).fixedSize(horizontal:false,vertical:true) } }
}
private struct WorkbookSheetMetadata: View {
    let title: String
    let sheet: JSON
    var body: some View {
        if !sheet.isNull {
            VStack(alignment:.leading,spacing:5) {
                Text(verbatim:title).font(.caption.weight(.semibold))
                Text(verbatim:sheet["name"].string + (sheet["hidden"].bool ? " · 숨김 시트" : "")).font(.caption)
                Text("병합 \(sheet["merge_count"].int)개 · 행 메타 \(sheet["row_metadata_count"].int)개 · 열 메타 \(sheet["column_metadata_count"].int)개").font(.caption).foregroundStyle(.secondary)
                ForEach(Array(sheet["row_metadata"].array.filter { $0["hidden"].bool }.prefix(10).enumerated()),id:\.offset) { _, range in Text("숨김 행 \(range["start"].int)–\(range["end"].int)").font(.caption) }
                ForEach(Array(sheet["column_metadata"].array.filter { $0["hidden"].bool }.prefix(10).enumerated()),id:\.offset) { _, range in Text("숨김 열 \(WorkbookGrid.columnLabel(range["start"].int))–\(WorkbookGrid.columnLabel(range["end"].int))").font(.caption) }
                if !sheet["merges"].array.isEmpty { Text(verbatim:"병합 범위: " + sheet["merges"].array.map(\.string).joined(separator:", ")).font(.caption).textSelection(.enabled) }
                if sheet["metadata_truncated"].bool { Text("행·열·병합 메타데이터 일부만 표시합니다. 전체 요약은 고정 보고서/MCP에서 확인하세요.").font(.caption).foregroundStyle(.secondary) }
            }
        }
    }
}
private struct WorkbookCoverageView: View {
    let gaps: [JSON]
    let total: Int
    let truncated: Bool
    let revisions: [JSON]
    private struct Key: Hashable { let feature: String; let reason: String }
    private struct Entry: Identifiable { let id: Int; let feature: String; let reason: String; var observations: [JSON] }
    private var entries: [Entry] {
        var result: [Entry] = [],positions: [Key:Int] = [:]
        for gap in gaps.prefix(50) {
            let key = Key(feature:gap["feature"].string,reason:gap["reason"].string)
            if let index = positions[key] { result[index].observations.append(gap) }
            else { positions[key] = result.count; result.append(Entry(id:result.count,feature:key.feature,reason:key.reason,observations:[gap])) }
        }
        return result
    }
    private func provenance(_ entry: Entry) -> String {
        let occurrences = Set(entry.observations.map { $0["revision_occurrence_id"].string }.filter { !$0.isEmpty })
        if revisions.count > 1,occurrences == Set(revisions.map { $0["revision_occurrence_id"].string }),entry.observations.allSatisfy({$0["sheet_id"].string.isEmpty && $0["address"].string.isEmpty}) { return "전체 \(revisions.count)개 버전에 공통 적용" }
        var labels: [String] = [],seen = Set<String>()
        for observation in entry.observations {
            let occurrence = observation["revision_occurrence_id"].string,sheetID = observation["sheet_id"].string,address = observation["address"].string
            let revision = revisions.first { $0["revision_occurrence_id"].string == occurrence }
            var parts: [String] = []
            if let revision { parts.append("v\(revision["index"].int+1)") }
            else if !occurrence.isEmpty { parts.append("버전 " + String(occurrence.suffix(8))) }
            if !sheetID.isEmpty { parts.append(revision?["sheets"].array.first(where:{$0["sheet_id"].string == sheetID})?["name"].string ?? "시트 " + String(sheetID.suffix(8))) }
            if !address.isEmpty { parts.append(address) }
            let label = parts.isEmpty ? "보고서 공통" : parts.joined(separator:" · ")
            if seen.insert(label).inserted { labels.append(label) }
        }
        return "적용: " + labels.prefix(8).joined(separator:", ") + (labels.count > 8 ? " 외 \(labels.count-8)개 위치" : "")
    }
    var body: some View {
        VStack(alignment:.leading,spacing:7) {
            Text("판독 범위와 한계").font(.headline)
            Text("Excel·Calc의 계산/화면을 완전히 재현하지 않습니다. 차트, 피벗, 매크로, 외부 데이터 등은 원본 기능별 제한을 확인하세요.").font(.caption).foregroundStyle(.secondary)
            if truncated || gaps.count > 50 { Text("판독 한계 기록 \(total)개 중 \(min(50,gaps.count))개를 표시합니다. 전체 항목은 MCP로 이어 읽을 수 있습니다.").font(.caption).foregroundStyle(.orange) }
            if gaps.isEmpty { Text("보고된 추가 판독 한계 없음 · 완전 호환을 의미하지 않음").font(.caption).foregroundStyle(.secondary) }
            if !gaps.isEmpty { Text("같은 내용은 한 번 표시합니다 · \(min(50,gaps.count))개 기록을 \(entries.count)개 항목으로 묶음").font(.caption).foregroundStyle(.secondary) }
            ForEach(entries) { entry in VStack(alignment:.leading,spacing:3) { Text(verbatim:entry.feature).font(.caption.weight(.medium)); Text(verbatim:entry.reason).font(.caption).foregroundStyle(.secondary); Text(verbatim:provenance(entry)).font(.caption2).foregroundStyle(.secondary) } }
        }
    }
}

struct WorkbookImportRow: Identifiable {
    let id = UUID()
    var label: String
    let url: URL
    let identity: ImportFileIdentity
    static func bundledDemo(resources: URL) throws -> (title: String, rows: [WorkbookImportRow]) {
        let resourceRoot = resources.resolvingSymlinksInPath().standardizedFileURL
        let folder = resources.appendingPathComponent("demo/workbooks",isDirectory:true).resolvingSymlinksInPath().standardizedFileURL
        let manifest = folder.appendingPathComponent("manifest.json")
        guard folder.path.hasPrefix(resourceRoot.path + "/"),manifest.resolvingSymlinksInPath().deletingLastPathComponent() == folder else { throw BridgeError(code:"WORKBOOK_DEMO_PATH",message:"앱에 포함된 데모 경로를 확인하지 못했습니다.") }
        let attributes = try FileManager.default.attributesOfItem(atPath:manifest.path)
        guard attributes[.type] as? FileAttributeType == .typeRegular,((attributes[.size] as? NSNumber)?.intValue ?? 65_537) <= 65_536 else { throw BridgeError(code:"WORKBOOK_DEMO_MANIFEST",message:"앱의 데모 목록을 읽을 수 없습니다.") }
        let value = JSON(try JSONSerialization.jsonObject(with:Data(contentsOf:manifest)))
        let title = value["title"].string, revisions = value["revisions"].array
        guard !title.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty,title.count <= 200,revisions.count == 3,Set(revisions.map { $0["path"].string }).count == 3 else { throw BridgeError(code:"WORKBOOK_DEMO_MANIFEST",message:"앱의 합성 3버전 데모 목록이 올바르지 않습니다.") }
        let rows = try revisions.map { revision -> WorkbookImportRow in
            let name = revision["path"].string,label = revision["label"].string
            guard name.range(of:"^v[1-3]\\.xlsx$",options:.regularExpression) != nil,!label.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty,label.count <= 200 else { throw BridgeError(code:"WORKBOOK_DEMO_MANIFEST",message:"앱의 데모 파일 이름·버전 이름을 확인하지 못했습니다.") }
            let url = folder.appendingPathComponent(name)
            guard url.resolvingSymlinksInPath().deletingLastPathComponent() == folder else { throw BridgeError(code:"WORKBOOK_DEMO_PATH",message:"앱에 포함된 데모 경로를 확인하지 못했습니다.") }
            var row = try selected(url); row.label = label; return row
        }
        return (title,rows)
    }
    static func selected(_ url: URL) throws -> WorkbookImportRow {
        guard ["xlsx","ods","csv"].contains(url.pathExtension.lowercased()) else { throw BridgeError(code:"WORKBOOK_FORMAT",message:"XLSX·ODS·UTF-8 CSV만 지원합니다.") }
        let size = (try FileManager.default.attributesOfItem(atPath:url.path)[.size] as? NSNumber)?.intValue ?? 0
        guard size <= 64*1024*1024 else { throw BridgeError(code:"WORKBOOK_LIMIT",message:"통합 문서는 파일당 64 MiB 이하를 지원합니다.") }
        let identity = try ImportFileIdentity.capture(url)
        guard identity.bytes <= 64*1024*1024 else { throw BridgeError(code:"WORKBOOK_LIMIT",message:"통합 문서는 파일당 64 MiB 이하를 지원합니다.") }
        return WorkbookImportRow(label:url.deletingPathExtension().lastPathComponent,url:url,identity:identity)
    }
}
private struct WorkbookImportSheet: View {
    @ObservedObject var model: WorkbookModel
    @Environment(\.dismiss) private var dismiss
    @State private var title = "새 통합 문서 프로젝트"
    @State private var rows: [WorkbookImportRow] = []
    @State private var choosing = false
    @State private var saving = false
    @State private var failure = ""
    private var locked: Bool { choosing || saving }
    var body: some View {
        VStack(alignment:.leading,spacing:16) {
            HStack { Text("스프레드시트 버전 가져오기").font(.title2.weight(.semibold)); Spacer(); Button("닫기") { dismiss() }.keyboardShortcut(.cancelAction).disabled(locked) }
            Text("오래된 버전부터 순서대로 정렬하세요. 파일 하나가 버전 하나입니다. 저장된 수식·값만 읽으며 수식·매크로·외부 연결을 실행하지 않습니다.").font(.callout).foregroundStyle(.secondary)
            TextField("프로젝트 이름",text:$title).textFieldStyle(.roundedBorder).disabled(locked)
            Button("XLSX·ODS·CSV 파일 선택…") { choose() }.disabled(locked)
            List {
                ForEach(Array(rows.enumerated()),id:\.element.id) { index, row in
                    HStack {
                        Text("v\(index+1)").font(.caption).foregroundStyle(.secondary)
                        VStack(alignment:.leading,spacing:3) { TextField("버전 이름",text:Binding(get:{rows.indices.contains(index) ? rows[index].label : ""},set:{if rows.indices.contains(index) { rows[index].label = $0 }})); Text(verbatim:row.url.lastPathComponent + " · \(row.identity.bytes) bytes").font(.caption).foregroundStyle(.secondary) }
                        Button { move(index,-1) } label: { Image(systemName:"chevron.up") }.disabled(index == 0 || locked).accessibilityLabel("버전 위로 이동")
                        Button { move(index,1) } label: { Image(systemName:"chevron.down") }.disabled(index == rows.count-1 || locked).accessibilityLabel("버전 아래로 이동")
                        Button { if rows.indices.contains(index) { rows.remove(at:index) } } label: { Image(systemName:"xmark") }.disabled(locked).accessibilityLabel("버전 제거")
                    }.disabled(locked)
                }
            }.frame(minHeight:220,maxHeight:360)
            Text("파일당 64 MiB · 최대 100개 버전. ODP·XLS·XLSM·암호화 파일은 지원하지 않습니다. CSV는 UTF-8, 쉼표 구분 형식입니다.").font(.caption).foregroundStyle(.secondary)
            if !failure.isEmpty { Text(verbatim:failure).font(.caption).foregroundStyle(.red) }
            HStack { if locked { ProgressView().controlSize(.small); Text(choosing ? "원본 SHA-256 확인 중…" : "가져오는 중…").font(.caption) }; Spacer(); Button("이 순서로 분석 시작") { Task { await create() } }.buttonStyle(.borderedProminent).disabled(locked || rows.isEmpty || rows.count > 100 || title.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty || rows.contains { $0.label.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty }) }
        }.padding(24).frame(width:840)
    }
    private func move(_ index: Int, _ by: Int) { let target = index+by; guard rows.indices.contains(index),rows.indices.contains(target) else { return }; rows.swapAt(index,target) }
    private func choose() {
        let panel = NSOpenPanel(); panel.allowsMultipleSelection = true; panel.canChooseDirectories = false
        panel.allowedContentTypes = ["xlsx","ods","csv"].compactMap { UTType(filenameExtension:$0) }
        guard panel.runModal() == .OK else { return }
        let urls = panel.urls
        guard rows.count+urls.count <= 100 else { failure = "버전은 최대 100개까지 가져올 수 있습니다."; return }
        choosing = true; failure = ""
        Task {
            do { let selected = try await Task.detached(priority:.userInitiated) { try urls.map { try WorkbookImportRow.selected($0) } }.value; rows += selected }
            catch { failure = error.localizedDescription }
            choosing = false
        }
    }
    private func create() async {
        saving = true; failure = ""
        do { try await model.create(title:title,rows:rows); dismiss() } catch { failure = error.localizedDescription }
        saving = false
    }
}
private struct WorkbookPublishSheet: View {
    @ObservedObject var model: WorkbookModel
    @Environment(\.dismiss) private var dismiss
    @State private var label = ""
    @State private var reason = ""
    @State private var failure = ""
    @State private var saving = false
    var body: some View {
        VStack(alignment:.leading,spacing:16) {
            Text("현재 보고서를 로컬 배포본으로 고정").font(.title2.weight(.semibold))
            Text("고정된 보고서·원본 버전 식별자와 아래 설명을 함께 보존합니다. 외부로 전송하지 않습니다.").foregroundStyle(.secondary)
            Text(verbatim:model.reportID).font(.system(.caption,design:.monospaced)).textSelection(.enabled)
            TextField("배포본 이름 · 예: 2026년 10월 승인본",text:$label).textFieldStyle(.roundedBorder)
            Text("고정 이유").font(.headline)
            TextEditor(text:$reason).frame(height:100).border(Color.secondary.opacity(0.3))
            if !failure.isEmpty { Text(verbatim:failure).font(.caption).foregroundStyle(.red) }
            HStack { Button("취소") { dismiss() }.keyboardShortcut(.cancelAction); Spacer(); if saving { ProgressView().controlSize(.small) }; Button("로컬 배포본 고정") { Task { saving = true; do { try await model.publish(label:label,reason:reason); dismiss() } catch { failure = error.localizedDescription }; saving = false } }.buttonStyle(.borderedProminent).disabled(saving || label.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty || reason.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty) }
        }.padding(24).frame(width:620).disabled(saving)
    }
}

private enum WorkbookLabels {
    static func description(_ change: JSON) -> String {
        let raw = change["description"].string
        switch change["kind"].string {
        case "row_position":
            let before = change["before_address"].string.drop(while:{$0.isLetter}),after = change["after_address"].string.drop(while:{$0.isLetter})
            if let from = Int(before),let to = Int(after) { return "대응을 추정한 행이 \(from)행에서 \(to)행으로 이동했습니다." }
            return "대응을 추정한 행의 물리 위치가 바뀌었습니다."
        case "formula": return "수식 원문이 바뀌었습니다. 수식은 재계산하지 않았습니다."
        case "stored_value": return "저장된 값이 바뀌었습니다. 수식 결과는 이전 계산값일 수 있습니다."
        case "value_type": return "저장된 값의 유형이 바뀌었습니다."
        case "cache_availability": return "수식의 저장 결과 유무가 바뀌었습니다. 결과가 없다고 셀이 삭제된 것은 아닙니다."
        case "calculation_settings": return "지원하는 저장된 계산 설정이 바뀌었습니다. 재계산을 수행하거나 결과의 최신성을 확인한 것은 아닙니다."
        case "number_format": return "원본 숫자 형식이 바뀌었습니다."
        case "style": return "지원하는 기본 서식이 바뀌었습니다."
        case "visibility": return "관측된 행·열의 숨김 상태가 바뀌었습니다."
        case "row_correspondence": return "대응되지 않은 행에서 셀이 관측되었습니다. 실제 추가·삭제로 단정하지 않습니다."
        case "cell_observation":
            if change["alignment_method"].string == "cross_format_date_representation" { return "서로 다른 형식의 날짜·시간 표현을 같은 값으로 확인할 수 없습니다. 실제 값·유형 변경으로 단정하지 않습니다." }
            if change["alignment_method"].string == "unresolved_formula_interpretation" { return "셀·수식·저장 결과의 관측이 바뀌었습니다. 공유·배열 수식의 의미가 미확정이므로 수식 삭제·직접 입력·재계산 결과로 단정하지 않습니다." }
            return "한쪽에서만 셀이 관측되었습니다. 관측 없음은 명시된 빈 셀·0과 다릅니다."
        case "sheet_observation": return "한쪽 버전에서만 시트가 관측되었습니다. 대응 확인이 필요하며 실제 추가·삭제로 단정하지 않습니다."
        case "sheet_dimensions": return "지원하는 행·열 크기 또는 숨김 구간이 바뀌었습니다. 셀 관측이 없는 빈 위치의 메타데이터도 포함합니다."
        case "merges": return "관측된 셀 병합 범위가 바뀌었습니다."
        case "sheet_name": return raw.hasPrefix("Sheet name: ") ? "시트 이름: " + raw.dropFirst("Sheet name: ".count) : raw
        case "sheet_position": return raw.hasPrefix("Sheet index: ") ? "시트 순서(0부터): " + raw.dropFirst("Sheet index: ".count) : raw
        case "sheet_visibility": return raw.hasPrefix("Sheet hidden: ") ? "시트 숨김 상태: " + raw.dropFirst("Sheet hidden: ".count).replacingOccurrences(of:"true",with:"숨김").replacingOccurrences(of:"false",with:"표시") : raw
        case "date_system":
            if raw.hasPrefix("Date system changed from "),let end = raw.firstIndex(of:";") {
                let transition = raw[raw.index(raw.startIndex,offsetBy:"Date system changed from ".count)..<end].replacingOccurrences(of:" to ",with:" → ")
                return "날짜 기준이 바뀌었습니다 (\(transition)). 숫자 날짜값을 변환하거나 같은 값으로 단정하지 않습니다."
            }
            return "날짜 기준이 바뀌었습니다. 숫자 날짜값을 변환하거나 같은 값으로 단정하지 않습니다."
        default: return raw
        }
    }
    static func availability(_ value: String) -> String { switch value { case "not_materialized": return "저장된 셀 관측 없음 · 빈 셀·삭제로 단정하지 않음"; case "correspondence_unresolved": return "대응 미확정 · 다른 셀로 건너뛰지 않음"; case "available": return "저장된 관측 있음"; default: return value } }
    static func association(_ value: String) -> String { switch value { case "exact": return "원문 일치"; case "inferred": return "추정 대응"; case "needs_review": return "대응 확인 필요"; default: return value.isEmpty ? "대응 미확정" : value } }
    static func method(_ value: String) -> String { switch value { case "unique_nonempty_first_column_key": return "첫 열의 중복 없는 값으로 추정"; case "unique_exact_row_content": return "중복 없는 행 내용의 일치로 추정"; case "unique_exact_sheet_name": return "중복 없는 시트 이름으로 추정"; case "unique_exact_sheet_content": return "중복 없는 시트 내용으로 추정"; case "physical_row_fallback": return "같은 물리 행 번호 · 대응 확인 필요"; case "unmatched_row_observation": return "행 대응을 찾지 못함"; case "unmatched_sheet_observation": return "시트 대응을 찾지 못함"; case "selected_physical_cell": return "직접 선택한 물리 셀"; case "no_unambiguous_cell_lineage": return "모호하지 않은 셀 이력을 찾지 못함"; default: return value } }
    static func kind(_ value: String) -> String { switch value { case "formula": return "수식 변경"; case "cache_availability": return "저장 결과 유무 변경"; case "calculation_settings": return "저장된 계산 설정 변경"; case "stored_value": return "저장값 변경"; case "value_type": return "값 유형 변경"; case "number_format": return "숫자 형식 변경"; case "style": return "기본 서식 변경"; case "visibility": return "숨김 상태 변경"; case "cell_observation": return "셀 관측 차이"; case "row_position": return "행 위치 변경"; case "row_correspondence": return "행 대응 확인"; case "sheet_name": return "시트 이름 변경"; case "sheet_position": return "시트 순서 변경"; case "sheet_visibility": return "시트 숨김 변경"; case "sheet_dimensions": return "행·열 메타 변경"; case "sheet_observation": return "시트 관측 차이"; case "merges": return "병합 범위 변경"; case "date_system": return "날짜 기준 변경"; default: return value } }
}

// AppKit creates reusable cells only for visible rows. The data source is a
// bounded 100×12 physical window backed by sparse observations, never a dense
// workbook. Formula text remains plain text and is never evaluated by AppKit.
@MainActor final class WorkbookTableScrollView: NSScrollView {
    private var synchronizingHeader = false
    override func reflectScrolledClipView(_ clipView: NSClipView) {
        super.reflectScrolledClipView(clipView)
        if clipView === contentView { synchronizeHeader() }
    }
    override func tile() { super.tile(); synchronizeHeader() }
    override func layout() { super.layout(); synchronizeHeader() }
    func synchronizeHeader() {
        guard !synchronizingHeader,let table = documentView as? NSTableView,table.numberOfColumns > 0,let header = table.headerView else { return }
        var ancestor = header.superview,headerClip: NSClipView?
        while let view = ancestor,view !== self {
            if let clip = view as? NSClipView { headerClip = clip; break }
            ancestor = view.superview
        }
        guard let headerClip,headerClip !== contentView else { return }
        // The header has its own clip view. Restoring the document clip alone
        // can leave it at the preceding horizontal position. Align the actual
        // first-column edges, accounting for public view-coordinate transforms.
        let body = table.convert(table.rect(ofColumn:0),to:self),title = header.convert(header.headerRect(ofColumn:0),to:self)
        let offset = title.minX-body.minX
        guard offset.isFinite,abs(offset) > 0.25 else { return }
        synchronizingHeader = true; defer { synchronizingHeader = false }
        headerClip.scroll(to:NSPoint(x:headerClip.bounds.origin.x+offset,y:headerClip.bounds.origin.y))
    }
}

struct WorkbookGrid: NSViewRepresentable {
    let pane: String
    let revealIntent: String
    let cells: [JSON]
    let rowStart: Int
    let columnStart: Int
    let rowCount: Int
    let columnCount: Int
    let selectedRow: Int
    let selectedColumn: Int
    let onSelect: (Int,Int) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> NSScrollView {
        let scroll = WorkbookTableScrollView(); scroll.hasVerticalScroller = true; scroll.hasHorizontalScroller = true; scroll.autohidesScrollers = false
        let table = NSTableView(); table.identifier = NSUserInterfaceItemIdentifier("Docver.workbook.grid." + pane); table.usesAlternatingRowBackgroundColors = true; table.gridStyleMask = [.solidHorizontalGridLineMask,.solidVerticalGridLineMask]; table.rowHeight = 27; table.headerView = NSTableHeaderView(); table.allowsMultipleSelection = false; table.allowsColumnReordering = false; table.columnAutoresizingStyle = .noColumnAutoresizing
        table.dataSource = context.coordinator; table.delegate = context.coordinator; table.target = context.coordinator; table.action = #selector(Coordinator.clicked(_:)); table.setAccessibilityLabel((pane == "before" ? "이전" : "이후") + " 통합 문서 셀 그리드 · 물리 주소")
        scroll.documentView = table; context.coordinator.table = table; context.coordinator.update(self)
        return scroll
    }
    func updateNSView(_ scroll: NSScrollView, context: Context) { context.coordinator.update(self) }
    static func columnLabel(_ column: Int) -> String { var value = column, result = ""; while value > 0 { value -= 1; result = String(UnicodeScalar(65+value%26)!) + result; value /= 26 }; return result }
    static func address(_ row: Int, _ column: Int) -> String { columnLabel(column) + String(row) }
    static func parseAddress(_ text: String) -> (Int,Int)? {
        let upper = text.trimmingCharacters(in:.whitespacesAndNewlines).uppercased()
        guard let match = upper.range(of:"^[A-Z]{1,3}[1-9][0-9]{0,6}$",options:.regularExpression),match == (upper.startIndex..<upper.endIndex) else { return nil }
        let letters = upper.prefix { $0.isLetter }; var column = 0
        for scalar in letters.unicodeScalars { column = column*26+Int(scalar.value)-64 }
        guard let row = Int(upper.dropFirst(letters.count)),row <= 1_048_576,column > 0,column <= 16_384 else { return nil }
        return (row,column)
    }
    @MainActor final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate {
        var parent: WorkbookGrid
        weak var table: NSTableView?
        var sparse: [String:JSON] = [:]
        var columnsKey = ""
        var updating = false
        var lastRequested = ""
        var lastRevealed = ""
        init(_ parent: WorkbookGrid) { self.parent = parent }
        func update(_ value: WorkbookGrid) {
            updating = true; defer { updating = false }
            parent = value
            lastRequested = "\(value.selectedRow):\(value.selectedColumn)"
            sparse = Dictionary(value.cells.map { (String($0["row"].int)+":"+String($0["column"].int),$0) },uniquingKeysWith:{a,_ in a})
            guard let table else { return }
            let key = "\(value.columnStart):\(value.columnCount)"
            if columnsKey != key {
                for column in table.tableColumns { table.removeTableColumn(column) }
                let row = NSTableColumn(identifier:NSUserInterfaceItemIdentifier("row")); row.title = "행"; row.width = 58; row.minWidth = 58; table.addTableColumn(row)
                for offset in 0..<value.columnCount { let n = value.columnStart+offset; let column = NSTableColumn(identifier:NSUserInterfaceItemIdentifier(String(n))); column.title = WorkbookGrid.columnLabel(n); column.width = 130; column.minWidth = 75; table.addTableColumn(column) }
                columnsKey = key
            }
            table.reloadData()
            if value.selectedRow >= value.rowStart,value.selectedRow < value.rowStart+value.rowCount,value.selectedColumn >= value.columnStart,value.selectedColumn < value.columnStart+value.columnCount {
                let row = value.selectedRow-value.rowStart,column = value.selectedColumn-value.columnStart+1
                table.selectRowIndexes(IndexSet(integer:row),byExtendingSelection:false)
                let reveal = "\(value.revealIntent):\(value.rowStart):\(value.columnStart):\(value.selectedRow):\(value.selectedColumn)"
                if lastRevealed != reveal {
                    table.scrollRowToVisible(row); table.scrollColumnToVisible(column)
                    // AppKit aligns the selected data column to x=0 and can
                    // scroll the row-number column away even for A. Reveal both
                    // when they fit; later user scrolling remains untouched.
                    if value.columnStart == 1,table.rect(ofColumn:column).maxX <= table.visibleRect.width,let scroll = table.enclosingScrollView {
                        let clip = scroll.contentView
                        clip.scroll(to:NSPoint(x:0,y:clip.bounds.origin.y)); scroll.reflectScrolledClipView(clip)
                    }
                    lastRevealed = reveal
                }
            } else { table.deselectAll(nil); lastRevealed = "" }
            (table.enclosingScrollView as? WorkbookTableScrollView)?.synchronizeHeader()
        }
        func numberOfRows(in tableView: NSTableView) -> Int { parent.rowCount }
        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            guard let tableColumn else { return nil }
            let id = NSUserInterfaceItemIdentifier("WorkbookPlainCell")
            let cell = tableView.makeView(withIdentifier:id,owner:self) as? NSTableCellView ?? NSTableCellView()
            cell.identifier = id
            cell.wantsLayer = true; cell.layer?.borderWidth = 0; cell.layer?.backgroundColor = NSColor.clear.cgColor
            let text: NSTextField
            if let existing = cell.textField { text = existing } else { text = NSTextField(labelWithString:""); text.translatesAutoresizingMaskIntoConstraints = false; text.lineBreakMode = .byTruncatingTail; cell.addSubview(text); cell.textField = text; NSLayoutConstraint.activate([text.leadingAnchor.constraint(equalTo:cell.leadingAnchor,constant:6),text.trailingAnchor.constraint(equalTo:cell.trailingAnchor,constant:-5),text.centerYAnchor.constraint(equalTo:cell.centerYAnchor)]) }
            let physicalRow = parent.rowStart+row
            if tableColumn.identifier.rawValue == "row" { text.identifier = NSUserInterfaceItemIdentifier("Docver.workbook.row.\(physicalRow)"); text.stringValue = String(physicalRow); text.font = .monospacedDigitSystemFont(ofSize:11,weight:.regular); text.textColor = .secondaryLabelColor; cell.toolTip = nil }
            else {
                let column = Int(tableColumn.identifier.rawValue) ?? 1
                text.identifier = NSUserInterfaceItemIdentifier("Docver.workbook.cell." + WorkbookGrid.address(physicalRow,column))
                let value = sparse[String(physicalRow)+":"+String(column)] ?? JSON()
                if physicalRow == parent.selectedRow,column == parent.selectedColumn { cell.layer?.borderWidth = 1; cell.layer?.borderColor = NSColor.controlAccentColor.cgColor; cell.layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.12).cgColor }
                let raw = value["value"].isNull ? "" : value["value"].string
                let unresolved = value["formula_interpretation"].string == "unresolved"
                var flags = unresolved ? "?ƒ" : value["formula"].isNull ? "" : "ƒ"
                if value["cached_result"].string == "missing" { flags += "∅" }
                let valueTruncated = value["source_lengths"]["value"].int > raw.utf16.count
                if value["text_truncated"].bool,!valueTruncated { flags += "…" }
                text.stringValue = (flags.isEmpty ? "" : flags + " ") + String(raw.prefix(400)) + (valueTruncated ? "…" : ""); text.font = .systemFont(ofSize:12); text.textColor = value["hidden_row"].bool || value["hidden_column"].bool ? .secondaryLabelColor : .labelColor
                let formula = value["formula"].isNull ? "" : " · 수식 원문: " + String(value["formula"].string.prefix(600))
                let interpretation = value["formula_interpretation"].string == "unresolved" ? " · 공유·배열 수식의 셀별 의미 확인 필요 · 저장된 관측값, 입력/계산 결과 미확정" : value["formula"].isNull ? "" : " · 저장된 수식 결과, 재계산하지 않음"
                cell.toolTip = WorkbookGrid.address(physicalRow,column) + (value.isNull ? " · 저장된 관측 없음" : " · " + value["value_type"].string + formula + interpretation)
                text.setAccessibilityLabel(WorkbookGrid.address(physicalRow,column) + " " + text.stringValue + interpretation)
            }
            return cell
        }
        private func select(_ row: Int, _ column: Int) {
            guard !updating,row >= 0,row < parent.rowCount,column >= parent.columnStart,column < parent.columnStart+parent.columnCount else { return }
            let physicalRow = parent.rowStart+row,key = "\(physicalRow):\(column)"
            guard key != lastRequested else { return }; lastRequested = key
            parent.onSelect(physicalRow,column)
        }
        func tableViewSelectionDidChange(_ notification: Notification) {
            guard let table = notification.object as? NSTableView else { return }
            if let type = NSApp.currentEvent?.type,[NSEvent.EventType.leftMouseDown,.leftMouseUp,.leftMouseDragged].contains(type) { return }
            let index = table.selectedColumn
            let column = index > 0 && index < table.tableColumns.count ? Int(table.tableColumns[index].identifier.rawValue) ?? parent.columnStart : max(parent.columnStart,min(parent.selectedColumn,parent.columnStart+parent.columnCount-1))
            select(table.selectedRow,column)
        }
        @objc func clicked(_ table: NSTableView) { let row = table.clickedRow,column = table.clickedColumn; guard row >= 0,column > 0,column < table.tableColumns.count,let physicalColumn = Int(table.tableColumns[column].identifier.rawValue) else { return }; select(row,physicalColumn) }
    }
}

// A gated fixture driver, matching the existing document Smoke contract. It
// exercises the shipped production model and real native table, never a mock
// service. Only an explicit environment request enables it.
@MainActor enum WorkbookNativeSmoke {
    private static var started = false
    static func runIfRequested(_ model: WorkbookModel) async {
        guard !started,let path = ProcessInfo.processInfo.environment["DOCVER_WORKBOOK_SMOKE_REQUEST"] else { return }
        started = true
        var output: URL?
        do {
            let request = JSON(try JSONSerialization.jsonObject(with:Data(contentsOf:URL(fileURLWithPath:path))))
            if !request["paging_output_budget"].isNull { model.pagingOutputBudget = max(2000,min(8000,request["paging_output_budget"].int)) }
            let folder = URL(fileURLWithPath:request["output"].string); output = folder
            try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
            let began = Date()
            let useDemo = request["use_demo"].bool
            let originals: [WorkbookImportRow]
            if useDemo { originals = try WorkbookImportRow.bundledDemo(resources:model.bridge.resources).rows }
            else { originals = try request["files"].array.map { try WorkbookImportRow.selected(URL(fileURLWithPath:$0.string)) } }
            if useDemo {
                await model.useDemo()
                guard model.ready,model.failure.isEmpty else { throw BridgeError(code:"WORKBOOK_SMOKE_DEMO",message:model.failure.isEmpty ? "앱의 3버전 엑셀 데모를 가져오지 못했습니다." : model.failure) }
            } else if !request["existing_project_id"].string.isEmpty {
                await model.selectProject(request["existing_project_id"].string,snapshot:request["existing_report_id"].string)
            } else {
                guard !originals.isEmpty else { throw BridgeError(code:"WORKBOOK_SMOKE_INPUT",message:"실제 통합 문서 검증 파일이 필요합니다.") }
                var rows = originals
                let labels = request["labels"].array
                for i in rows.indices where labels.indices.contains(i) { rows[i].label = labels[i].string }
                try await model.create(title:request["title"].string.isEmpty ? "통합 문서 네이티브 검증" : request["title"].string,rows:rows)
            }
            guard model.ready,model.failure.isEmpty,model.rangeFailure.isEmpty,model.changesFailure.isEmpty else { throw BridgeError(code:"WORKBOOK_SMOKE_READY",message:[model.failure,model.rangeFailure,model.changesFailure].filter { !$0.isEmpty }.joined(separator:"\n")) }
            let project = model.projectID,snapshot = model.reportID,metadata = try model.report.data()
            var checks: [String:Any] = ["native_ui":"SwiftUI/AppKit NSTableView","sparse_viewport":true,"viewport_rows":model.rowLimit,"viewport_columns":model.columnLimit,"source_sha_forwarded":!originals.isEmpty,"public_bundled_demo_action":useDemo]
            checks["initial_net_change_count"] = model.changeTotal
            let requiredKinds = request["required_change_kinds"].array.map(\.string)
            if !requiredKinds.isEmpty {
                await model.changeMode("history")
                var observed = Set(model.changes.map { $0["kind"].string }), pages = 1
                while !requiredKinds.allSatisfy({observed.contains($0)}),!model.changeCursor.isEmpty,pages < 100 {
                    await model.loadChanges(next:true); pages += 1
                    for change in model.changes { observed.insert(change["kind"].string) }
                }
                for kind in requiredKinds where !observed.contains(kind) { throw BridgeError(code:"WORKBOOK_SMOKE_CHANGE",message:"예상 변경 종류를 찾지 못했습니다: " + kind) }
                checks["required_history_kinds"] = requiredKinds; checks["change_pages_read"] = pages
            }

            // Expectations originate in independent fixture definitions, rather
            // than being derived from the parser's own output.
            var checkedCells = 0
            for expectation in request["expected_cells"].array {
                let index = expectation["revision_index"].int
                guard model.revisions.indices.contains(index) else { throw BridgeError(code:"WORKBOOK_SMOKE_REVISION",message:"셀 예상의 버전 위치가 다릅니다.") }
                let occurrence = model.revisions[index]["revision_occurrence_id"].string
                await model.changeVersions(after:occurrence)
                if !expectation["sheet_name"].string.isEmpty {
                    guard let selected = model.sheets(occurrence).first(where:{$0["name"].string == expectation["sheet_name"].string}) else { throw BridgeError(code:"WORKBOOK_SMOKE_SHEET",message:"셀 예상의 시트가 없습니다.") }
                    await model.changeSheet(after:selected["sheet_id"].string)
                }
                guard let (row,column) = WorkbookGrid.parseAddress(expectation["address"].string) else { throw BridgeError(code:"WORKBOOK_SMOKE_ADDRESS",message:"셀 예상 주소가 잘못되었습니다.") }
                await model.selectCell(row,column)
                guard model.cellFailure.isEmpty else { throw BridgeError(code:"WORKBOOK_SMOKE_CELL",message:model.cellFailure) }
                for key in ["value","formula","value_type","number_format","formula_interpretation"] where expectation.dictionary.keys.contains(key) {
                    let expected = expectation[key],actual = model.afterCell[key]
                    guard (expected.isNull ? actual.isNull : expected.string == actual.string) else { throw BridgeError(code:"WORKBOOK_SMOKE_CELL_TRUTH",message:"독립 원본 예상과 셀 값이 다릅니다: " + expectation["address"].string + " · " + key) }
                }
                checkedCells += 1
            }
            checks["independent_expected_cells"] = checkedCells
            checks["mode_interval"] = try await exerciseModeInterval(model,request:request)

            if let first = model.revisions.first,let last = model.revisions.last {
                await model.changeVersions(before:first["revision_occurrence_id"].string,after:last["revision_occurrence_id"].string)
            }
            await model.changeMode("history")
            let historyCount = model.changeTotal
            let movedChange = model.changes.first { !$0["before_address"].string.isEmpty && !$0["after_address"].string.isEmpty && $0["before_address"].string != $0["after_address"].string }
            if let change = movedChange ?? model.changes.first(where:{!$0["after_address"].string.isEmpty || !$0["before_address"].string.isEmpty}) {
                await model.chooseChange(change["change_id"].string)
                guard model.selectedChangeID == change["change_id"].string,model.beforeID == change["from_revision_occurrence_id"].string,model.afterID == change["to_revision_occurrence_id"].string,model.beforeCell.isNull || model.beforeCell["address"].string == change["before_address"].string,model.afterCell.isNull || model.afterCell["address"].string == change["after_address"].string,model.cellFailure.isEmpty else { throw BridgeError(code:"WORKBOOK_SMOKE_EVIDENCE",message:"변경 선택 후 버전·셀 근거가 다릅니다.") }
                checks["history_change_navigation"] = true
                await model.loadCellHistory()
                checks["cell_history_items"] = model.cellHistory.count
            }
            model.tab = "compare"
            if request["require_dense_raw_proof"].bool { checks["dense_raw_value"] = try await exerciseDenseRawValue(model) }
            try await Task.sleep(nanoseconds:400_000_000)
            guard let window = NSApp.windows.first(where:{$0.isVisible && containsGrid($0.contentView)}) else { throw BridgeError(code:"WORKBOOK_SMOKE_WINDOW",message:"실제 네이티브 통합 문서 그리드 창이 없습니다.") }
            checks["pane_evidence"] = try assertPanes(model,window:window)
            checks["header_scroll_geometry"] = try await exerciseHeaderScrollGeometry(model,window:window)
            try Smoke.captureView(window,folder.appendingPathComponent("native-workbook-compare.png"))
            if request["require_dense_raw_proof"].bool {
                try Smoke.captureView(window,folder.appendingPathComponent("native-workbook-dense-raw.png"))
                checks["dense_raw_continuation"] = try await exerciseDenseContinuation(model)
                try await Task.sleep(nanoseconds:250_000_000)
                _ = try assertPanes(model,window:window)
                try Smoke.captureView(window,folder.appendingPathComponent("native-workbook-dense-raw-continuation.png"))
                await model.loadSelectedCells()
                guard model.cellFailure.isEmpty,model.cellTextOffset == 0,model.beforeCell["address"].string == "A1",model.afterCell["address"].string == "A1",model.beforeCell["text_continuations"]["value"]["offset"].int == 0,model.afterCell["text_continuations"]["value"]["offset"].int == 0 else { throw BridgeError(code:"WORKBOOK_SMOKE_DENSE_RESTORE",message:"원문 첫 조각으로 되돌아온 상태를 확인하지 못했습니다.") }
            }
            checks["actual_native_grid_capture"] = true

            // Independent fixtures can require distant forward/backward moves.
            // Verify the actual NSTableView selection and visible cell rectangle,
            // rather than accepting a model coordinate that is off screen.
            var checkedMoves: [[String:Any]] = []
            for (index,expected) in request["expected_moves"].array.enumerated() {
                if let first = model.revisions.first,let last = model.revisions.last { await model.changeVersions(before:first["revision_occurrence_id"].string,after:last["revision_occurrence_id"].string) }
                await model.changeMode("history")
                func matches(_ change: JSON) -> Bool {
                    guard change["before_address"].string == expected["before_address"].string,change["after_address"].string == expected["after_address"].string else { return false }
                    for (key,field) in [("from_revision_index","from_revision_occurrence_id"),("to_revision_index","to_revision_occurrence_id")] where expected.dictionary.keys.contains(key) {
                        let position = expected[key].int
                        guard model.revisions.indices.contains(position),change[field].string == model.revisions[position]["revision_occurrence_id"].string else { return false }
                    }
                    return true
                }
                var change = model.changes.first(where:matches),pages = 1
                while change == nil,!model.changeCursor.isEmpty,pages < 100 {
                    await model.loadChanges(next:true); pages += 1; change = model.changes.first(where:matches)
                }
                guard let change else { throw BridgeError(code:"WORKBOOK_SMOKE_MOVE_MISSING",message:"독립 원본의 이동 근거를 찾지 못했습니다: " + expected["before_address"].string + " → " + expected["after_address"].string) }
                await model.chooseChange(change["change_id"].string)
                guard model.rangeFailure.isEmpty,model.cellFailure.isEmpty else { throw BridgeError(code:"WORKBOOK_SMOKE_MOVE_LOAD",message:model.rangeFailure + model.cellFailure) }
                try await Task.sleep(nanoseconds:300_000_000)
                let panes = try assertPanes(model,window:window)
                try Smoke.captureView(window,folder.appendingPathComponent("native-workbook-move-\(index+1).png"))
                checkedMoves.append(["before_address":expected["before_address"].string,"after_address":expected["after_address"].string,"panes":panes])
            }
            if !checkedMoves.isEmpty { checks["independent_expected_moves"] = checkedMoves }
            if request["require_before_only_history"].bool { checks["before_only_history"] = try await exerciseBeforeOnlyHistory(model,request:request,window:window,folder:folder) }
            if request["exercise_same_address_reveal"].bool || request["require_same_address_reveal"].bool { checks["same_address_reveal"] = try await exerciseSameAddressReveal(model,request:request,window:window,folder:folder) }
            checks["paging"] = try await exercisePaging(model,request:request)
            try await Task.sleep(nanoseconds:150_000_000)
            checks["paging_header_geometry"] = try assertPanes(model,window:window)

            // The old request is cancelled while its owned Bridge process is
            // pending. It cannot restore the previous selected-cell authority.
            let superseded = Task { await model.selectCell(1,1) }
            await Task.yield()
            await model.selectCell(2,2)
            await superseded.value
            guard model.selectedRow == 2,model.selectedColumn == 2,model.afterAddress == "B2",model.afterCell.isNull || model.afterCell["address"].string == "B2" else { throw BridgeError(code:"WORKBOOK_SMOKE_STALE_CELL",message:"교체된 요청이 현재 셀 선택을 덮어썼습니다.") }
            checks["superseded_cell_request_rejected"] = true
            if let first = model.revisions.first,let last = model.revisions.last { await model.changeVersions(before:first["revision_occurrence_id"].string,after:last["revision_occurrence_id"].string) }
            await model.changeMode("range_net")
            checks["history_event_count"] = historyCount; checks["range_net_count"] = model.changeTotal
            await model.loadMCP()
            guard model.canCopyMCP else { throw BridgeError(code:"WORKBOOK_SMOKE_MCP",message:model.mcpFailure.isEmpty ? "현재 범위의 MCP 설정을 만들지 못했습니다." : model.mcpFailure) }
            checks["mcp_scope_owned_configuration"] = true
            if request["exercise_release"].bool {
                let before = model.releases.count
                try await model.publish(label:"검증 배포본",reason:"합성 원본의 버전별 변경 검증")
                guard model.releases.count == before+1,model.releases.contains(where:{$0["report_id"].string == snapshot && $0["label"].string == "검증 배포본"}) else { throw BridgeError(code:"WORKBOOK_SMOKE_RELEASE",message:"현재 고정 보고서의 로컬 배포본을 확인하지 못했습니다.") }
                checks["local_release_persisted"] = true
            }
            let exported = folder.appendingPathComponent("export")
            try FileManager.default.createDirectory(at:exported,withIntermediateDirectories:true)
            _ = try await model.bridge.call("workbookExport",["project_id":project,"report_id":snapshot,"folder":exported.path])
            checks["actual_export"] = true
            model.tab = "ai"; try await Task.sleep(nanoseconds:300_000_000)
            try Smoke.captureView(window,folder.appendingPathComponent("native-workbook-ai-release.png"))
            let reread = try await model.bridge.call("workbookView",["project_id":project,"report_id":snapshot])
            guard try reread.data() == metadata else { throw BridgeError(code:"WORKBOOK_SMOKE_IMMUTABLE",message:"셀 조회·배포·내보내기가 고정 보고서 메타데이터를 바꿨습니다.") }
            for original in originals { guard try ImportFileIdentity.capture(original.url) == original.identity else { throw BridgeError(code:"WORKBOOK_SMOKE_ORIGINAL",message:"원본 파일의 SHA-256 또는 크기가 달라졌습니다.") } }
            checks["original_bytes_unchanged"] = true; checks["report_metadata_unchanged"] = true
            let config = model.mcp
            model.closeReads()
            guard !model.canCopyMCP,!model.ready else { throw BridgeError(code:"WORKBOOK_SMOKE_CLOSE_AUTHORITY",message:"창을 닫은 뒤 이전 범위의 복사 권한이 남았습니다.") }
            checks["closed_workspace_invalidates_authority"] = true
            let result: [String:Any] = ["completed":true,"project_id":project,"report_id":snapshot,"revision_count":model.revisions.count,"seconds":Date().timeIntervalSince(began),"checks":checks,"mcp_config":config,"interaction_scope":"production model/actions and rendered AppKit grid; no OS mouse/keyboard or VoiceOver automation","smoke_invocation_id":request["smoke_invocation_id"].string]
            try JSON(result).data().write(to:folder.appendingPathComponent("validation.json"))
        } catch {
            if let output { try? JSON(["completed":false,"error":error.localizedDescription]).data().write(to:output.appendingPathComponent("validation.json")) }
        }
        NSApp.terminate(nil)
    }
    private static func containsGrid(_ view: NSView?) -> Bool {
        guard let view else { return false }
        if view.identifier?.rawValue.hasPrefix("Docver.workbook.grid.") == true { return true }
        return view.subviews.contains { containsGrid($0) }
    }
    private static func exercisePaging(_ model: WorkbookModel,request: JSON) async throws -> [String:Any] {
        if let first = model.revisions.first,let last = model.revisions.last { await model.changeVersions(before:first["revision_occurrence_id"].string,after:last["revision_occurrence_id"].string) }
        await model.changeMode("history")
        guard model.changesFailure.isEmpty else { throw BridgeError(code:"WORKBOOK_SMOKE_PAGING",message:model.changesFailure) }
        var checks: [String:Any] = ["output_budget":model.pagingOutputBudget,"cursor_history_limit":128]
        let identity = model.comparisonScope,firstIDs = model.changes.map { $0["change_id"].string }
        if !model.changeCursor.isEmpty,let last = firstIDs.last {
            await model.chooseChange(last)
            await model.stepChange(1)
            guard model.comparisonScope == identity,model.changePageNumber == 2,!model.changePreviousCursors.isEmpty,model.selectedChangeID == model.changes.first?["change_id"].string,model.changesFailure.isEmpty else { throw BridgeError(code:"WORKBOOK_SMOKE_STEP_NEXT_PAGE",message:"다음 변경으로 페이지 경계를 건너지 못했습니다.") }
            await model.stepChange(-1)
            guard model.comparisonScope == identity,model.changePageNumber == 1,model.changes.map({$0["change_id"].string}) == firstIDs,model.selectedChangeID == last else { throw BridgeError(code:"WORKBOOK_SMOKE_STEP_PREVIOUS_PAGE",message:"이전 변경으로 원래 페이지의 마지막 근거에 돌아오지 못했습니다.") }
            await model.loadChanges(next:true)
            guard model.changePageNumber == 2,model.selectedChangeID.isEmpty,model.changesFailure.isEmpty else { throw BridgeError(code:"WORKBOOK_SMOKE_PAGE_AUTHORITY",message:"페이지 교체 후 이전 변경 선택이 남았습니다.") }
            await model.loadChanges(previous:true)
            guard model.changePageNumber == 1,model.changes.map({$0["change_id"].string}) == firstIDs else { throw BridgeError(code:"WORKBOOK_SMOKE_PAGE_BACK",message:"이전 변경 페이지의 항목이 다릅니다.") }
            checks["change_forward_backward_and_cross_page_steps"] = true
        } else {
            if request["require_change_paging"].bool { throw BridgeError(code:"WORKBOOK_SMOKE_PAGE_FIXTURE",message:"변경 페이지 경계를 검증할 만큼의 원본 변경이 없습니다.") }
            checks["change_single_page"] = true
        }
        if let first = model.revisions.first,let last = model.revisions.last { await model.changeVersions(before:first["revision_occurrence_id"].string,after:last["revision_occurrence_id"].string) }
        let historyAddress = request["history_address"].string.isEmpty ? "A2" : request["history_address"].string
        guard let (historyRow,historyColumn) = WorkbookGrid.parseAddress(historyAddress) else { throw BridgeError(code:"WORKBOOK_SMOKE_HISTORY_ADDRESS",message:"셀 이력 검증 주소가 올바르지 않습니다.") }
        await model.selectCell(historyRow,historyColumn); await model.loadCellHistory()
        guard model.cellHistoryFailure.isEmpty else { throw BridgeError(code:"WORKBOOK_SMOKE_HISTORY_PAGING",message:model.cellHistoryFailure) }
        let firstHistory = try JSON(model.cellHistory.map(\.raw)).data()
        if !model.cellHistoryCursor.isEmpty {
            let next = Task { await model.loadCellHistory(next:true) }
            await Task.yield()
            if model.loadingHistory {
                guard try JSON(model.cellHistory.map(\.raw)).data() == firstHistory else { throw BridgeError(code:"WORKBOOK_SMOKE_HISTORY_LOADING",message:"다음 이력 응답을 받기 전에 현재 이력 페이지가 지워졌습니다.") }
                checks["history_retained_while_next_request_pending"] = true
            }
            await next.value
            guard model.cellHistoryPageNumber == 2,!model.cellHistoryPreviousCursors.isEmpty,model.cellHistoryFailure.isEmpty else { throw BridgeError(code:"WORKBOOK_SMOKE_HISTORY_NEXT",message:"다음 셀 이력 페이지를 읽지 못했습니다.") }
            await model.loadCellHistory(previous:true)
            guard model.cellHistoryPageNumber == 1,try JSON(model.cellHistory.map(\.raw)).data() == firstHistory,model.cellHistoryFailure.isEmpty else { throw BridgeError(code:"WORKBOOK_SMOKE_HISTORY_BACK",message:"이전 셀 이력 페이지의 항목이 다릅니다.") }
            checks["history_forward_backward_pages"] = true
        } else {
            if request["require_cell_history_paging"].bool { throw BridgeError(code:"WORKBOOK_SMOKE_HISTORY_PAGE_FIXTURE",message:"셀 이력 페이지 경계를 검증할 만큼의 원본 이력이 없습니다.") }
            checks["history_single_page"] = true
        }
        return checks
    }
    private static func exerciseHeaderScrollGeometry(_ model: WorkbookModel,window: NSWindow) async throws -> [String:Any] {
        var original: [String:NSPoint] = [:],manual: [String:NSPoint] = [:],scrolled: [String:Any] = [:]
        for pane in ["before","after"] {
            guard let table = grid(window.contentView,pane:pane),let scroll = table.enclosingScrollView else { continue }
            let clip = scroll.contentView; original[pane] = clip.bounds.origin
            let x = min(max(0,clip.documentRect.width-clip.bounds.width),clip.bounds.origin.x+200)
            clip.scroll(to:NSPoint(x:x,y:clip.bounds.origin.y)); scroll.reflectScrolledClipView(clip); manual[pane] = clip.bounds.origin
        }
        try await Task.sleep(nanoseconds:100_000_000)
        for pane in ["before","after"] {
            guard let table = grid(window.contentView,pane:pane),let coordinator = table.dataSource as? WorkbookGrid.Coordinator else { continue }
            scrolled[pane] = try assertHeaderGeometry(table,state:coordinator.parent,pane:pane)
        }
        await model.loadRange(); try await Task.sleep(nanoseconds:100_000_000)
        for pane in ["before","after"] {
            guard let table = grid(window.contentView,pane:pane),let coordinator = table.dataSource as? WorkbookGrid.Coordinator,let position = manual[pane] else { continue }
            guard abs(table.visibleRect.minX-position.x) <= 0.75 else { throw BridgeError(code:"WORKBOOK_SMOKE_HEADER_PASSIVE_SCROLL",message:"범위 다시 읽기가 사용자의 가로 스크롤을 바꿨습니다: " + pane) }
            _ = try assertHeaderGeometry(table,state:coordinator.parent,pane:pane)
        }
        for (pane,position) in original {
            guard let table = grid(window.contentView,pane:pane),let scroll = table.enclosingScrollView else { continue }
            scroll.contentView.scroll(to:position); scroll.reflectScrolledClipView(scroll.contentView)
        }
        try await Task.sleep(nanoseconds:100_000_000)
        return ["manual_scroll_header_geometry":scrolled,"passive_refresh_preserves_horizontal_scroll":true,"restored_header_geometry":try assertPanes(model,window:window)]
    }
    private static func exerciseDenseRawValue(_ model: WorkbookModel) async throws -> [String:Any] {
        model.addressInput = "A1"; await model.goToAddress()
        guard model.beforeCells.count == 1200,model.afterCells.count == 1200,model.afterCells.first(where:{$0["address"].string == "A1"})?["text_truncated"].bool == true else { throw BridgeError(code:"WORKBOOK_SMOKE_DENSE_VIEWPORT",message:"독립 원본의 1,200셀 미리보기·생략 상태를 확인하지 못했습니다.") }
        let expected = String(repeating:"한글😀 데이터 원문 \"따옴표\" ",count:100) + "1:1"
        let identity = model.rangeScope; var units: [UInt16] = [],pages = 0
        repeat {
            guard model.cellFailure.isEmpty,model.rangeScope == identity,model.afterAddress == "A1",model.afterCell["address"].string == "A1" else { throw BridgeError(code:"WORKBOOK_SMOKE_DENSE_CELL",message:model.cellFailure.isEmpty ? "선택한 A1 원문 범위가 다릅니다." : model.cellFailure) }
            let cell = model.afterCell,continuation = cell["text_continuations"]["value"],offset = continuation["offset"].int,chunk = Array(cell["value"].string.utf16)
            guard continuation["total_length"].int == expected.utf16.count,offset <= units.count,offset+chunk.count >= units.count else { throw BridgeError(code:"WORKBOOK_SMOKE_DENSE_CONTINUATION",message:"A1 원문 조각의 길이·이어 읽기 위치가 다릅니다.") }
            units += chunk.dropFirst(units.count-offset); pages += 1
            if continuation["next_offset"].isNull { break }
            guard pages < 64 else { throw BridgeError(code:"WORKBOOK_SMOKE_DENSE_PAGES",message:"독립 A1 원문 검증의 페이지 한도를 넘었습니다.") }
            await model.loadSelectedCells(offset:continuation["next_offset"].int)
        } while true
        guard String(decoding:units,as:UTF16.self) == expected else { throw BridgeError(code:"WORKBOOK_SMOKE_DENSE_TRUTH",message:"선택한 A1의 전체 원문이 독립 합성 원본과 다릅니다.") }
        await model.loadSelectedCells()
        return ["selected_address":"A1","viewport_cells_per_side":1200,"preview_truncated":true,"raw_utf16_length":units.count,"raw_pages":pages,"full_raw_matches_independent_fixture":true,"first_raw_model_page_prepared_for_static_capture_review":true]
    }
    private static func exerciseDenseContinuation(_ model: WorkbookModel) async throws -> [String:Any] {
        let expected = Array((String(repeating:"한글😀 데이터 원문 \"따옴표\" ",count:100) + "1:1").utf16)
        let firstBefore = model.beforeCell["text_continuations"]["value"]["offset"].int,firstAfter = model.afterCell["text_continuations"]["value"]["offset"].int
        guard let next = model.cellTextNext,next > model.cellTextOffset else { throw BridgeError(code:"WORKBOOK_SMOKE_DENSE_NEXT",message:"선택한 원문의 다음 조각으로 이동할 수 없습니다.") }
        // This is the same shared production pager used by each cell section's
        // visible continuation button, without claiming an OS button click.
        await model.loadSelectedCells(offset:next)
        guard model.cellFailure.isEmpty,model.cellTextOffset == next,model.beforeAddress == "A1",model.afterAddress == "A1" else { throw BridgeError(code:"WORKBOOK_SMOKE_DENSE_NEXT_SCOPE",message:"이어 읽은 A1의 원본 범위가 달라졌습니다.") }
        var excerpts: [[String:Any]] = []
        for (side,cell,previous) in [("before",model.beforeCell,firstBefore),("after",model.afterCell,firstAfter)] {
            let continuation = cell["text_continuations"]["value"],start = continuation["offset"].int,units = Array(cell["value"].string.utf16),end = start+units.count
            // This fixture's shared next offset is a complete UTF-16 boundary.
            guard cell["address"].string == "A1",start == next,start > previous,start <= end,end <= expected.count,continuation["total_length"].int == expected.count,units == Array(expected[start..<end]) else { throw BridgeError(code:"WORKBOOK_SMOKE_DENSE_NEXT_TRUTH",message:"이어 읽은 조각의 범위·내용이 독립 원본과 다릅니다: " + side) }
            excerpts.append(["side":side,"address":cell["address"].string,"start_utf16":start,"end_utf16_exclusive":end,"total_utf16":expected.count,"excerpt_matches_independent_fixture":true])
        }
        return ["requested_shared_offset":next,"both_sides_advanced":true,"excerpts":excerpts,"interaction_scope":"production pager action plus separate actual static capture; no OS click automation"]
    }
    private static func exerciseSameAddressReveal(_ model: WorkbookModel,request: JSON,window: NSWindow,folder: URL) async throws -> [String:Any] {
        let address = request["same_address_reveal_address"].string.isEmpty ? "B2" : request["same_address_reveal_address"].string
        guard WorkbookGrid.parseAddress(address) != nil else { throw BridgeError(code:"WORKBOOK_SMOKE_REVEAL_ADDRESS",message:"다시 표시할 셀 검증 주소가 올바르지 않습니다.") }
        if let first = model.revisions.first,let last = model.revisions.last { await model.changeVersions(before:first["revision_occurrence_id"].string,after:last["revision_occurrence_id"].string) }
        await model.changeMode("history")
        var first: JSON?,second: JSON?,firstPage = 1,secondPage = 1,pages = 0
        while second == nil,pages < 100 {
            pages += 1
            for change in model.changes where change["before_address"].string == address && change["after_address"].string == address {
                if let selected = first {
                    if change["change_id"].string != selected["change_id"].string,change["from_revision_occurrence_id"].string == selected["from_revision_occurrence_id"].string,change["to_revision_occurrence_id"].string == selected["to_revision_occurrence_id"].string { second = change; secondPage = model.changePageNumber; break }
                } else { first = change; firstPage = model.changePageNumber }
            }
            if second != nil || model.changeCursor.isEmpty { break }
            await model.loadChanges(next:true)
            guard model.changesFailure.isEmpty else { throw BridgeError(code:"WORKBOOK_SMOKE_REVEAL_CHANGES",message:model.changesFailure) }
        }
        guard let first,let second else {
            if request["require_same_address_reveal"].bool { throw BridgeError(code:"WORKBOOK_SMOKE_REVEAL_FIXTURE",message:"동일 버전 쌍의 같은 셀 주소에서 두 변경을 확인할 원본이 없습니다: " + address) }
            return ["not_applicable":"no_two_changes_at_same_address_in_same_occurrence_pair"]
        }
        while model.changePageNumber > firstPage { await model.loadChanges(previous:true); guard model.changesFailure.isEmpty else { throw BridgeError(code:"WORKBOOK_SMOKE_REVEAL_PAGE",message:model.changesFailure) } }
        await model.chooseChange(first["change_id"].string)
        try await Task.sleep(nanoseconds:250_000_000)
        _ = try assertPanes(model,window:window)
        var scrollPositions: [String:CGFloat] = [:]
        for pane in ["before","after"] {
            guard let table = grid(window.contentView,pane:pane),let state = table.dataSource as? WorkbookGrid.Coordinator else { throw BridgeError(code:"WORKBOOK_SMOKE_REVEAL_GRID",message:"다시 표시 검증의 실제 셀 그리드가 없습니다.") }
            table.scrollRowToVisible(state.parent.rowCount-1)
        }
        try await Task.sleep(nanoseconds:100_000_000)
        for pane in ["before","after"] {
            guard let table = grid(window.contentView,pane:pane),let state = table.dataSource as? WorkbookGrid.Coordinator else { throw BridgeError(code:"WORKBOOK_SMOKE_REVEAL_GRID",message:"실제 셀 그리드가 없습니다.") }
            let row = state.parent.selectedRow-state.parent.rowStart,column = state.parent.selectedColumn-state.parent.columnStart+1
            guard !table.visibleRect.intersects(table.frameOfCell(atColumn:column,row:row)) else { throw BridgeError(code:"WORKBOOK_SMOKE_REVEAL_SCROLL",message:"검증할 셀을 화면 밖으로 스크롤하지 못했습니다.") }
            scrollPositions[pane] = table.visibleRect.minY
        }
        // A real passive viewport read must not override the user's scroll.
        await model.loadRange(); try await Task.sleep(nanoseconds:200_000_000)
        for pane in ["before","after"] {
            guard let table = grid(window.contentView,pane:pane),let previous = scrollPositions[pane],abs(table.visibleRect.minY-previous) < 1 else { throw BridgeError(code:"WORKBOOK_SMOKE_REVEAL_PASSIVE",message:"수동 새로고침이 사용자의 스크롤 위치를 바꿨습니다.") }
        }
        while model.changePageNumber < secondPage { await model.loadChanges(next:true); guard model.changesFailure.isEmpty else { throw BridgeError(code:"WORKBOOK_SMOKE_REVEAL_PAGE",message:model.changesFailure) } }
        let generation = model.revealGeneration
        await model.chooseChange(second["change_id"].string)
        try await Task.sleep(nanoseconds:250_000_000)
        guard model.revealGeneration > generation,model.beforeAddress == address,model.afterAddress == address,model.selectedChangeID == second["change_id"].string else { throw BridgeError(code:"WORKBOOK_SMOKE_REVEAL_INTENT",message:"같은 주소의 다른 변경이 새 표시 요청으로 처리되지 않았습니다.") }
        let panes = try assertPanes(model,window:window)
        try Smoke.captureView(window,folder.appendingPathComponent("native-workbook-same-address-reveal.png"))
        return ["address":address,"first_change_id":first["change_id"].string,"second_change_id":second["change_id"].string,"same_occurrence_pair":true,"passive_refresh_preserves_manual_scroll":true,"explicit_same_address_navigation_reveals_cell":true,"panes":panes]
    }
    private static func exerciseBeforeOnlyHistory(_ model: WorkbookModel,request: JSON,window: NSWindow,folder: URL) async throws -> [String:Any] {
        let address = request["before_only_history_address"].string.isEmpty ? "B2" : request["before_only_history_address"].string
        if let first = model.revisions.first,let last = model.revisions.last { await model.changeVersions(before:first["revision_occurrence_id"].string,after:last["revision_occurrence_id"].string) }
        await model.changeMode("history")
        func matches(_ change: JSON) -> Bool { change["before_address"].string == address && change["after_address"].string.isEmpty }
        var change = model.changes.first(where:matches),pages = 1
        while change == nil,!model.changeCursor.isEmpty,pages < 100 {
            await model.loadChanges(next:true); pages += 1; change = model.changes.first(where:matches)
            guard model.changesFailure.isEmpty else { throw BridgeError(code:"WORKBOOK_SMOKE_BEFORE_HISTORY_CHANGES",message:model.changesFailure) }
        }
        guard let change else { throw BridgeError(code:"WORKBOOK_SMOKE_BEFORE_HISTORY_FIXTURE",message:"이전 쪽에만 관측된 셀 변경 원본이 없습니다: " + address) }
        await model.chooseChange(change["change_id"].string)
        guard let anchor = model.cellHistoryAnchor,anchor.occurrence == change["from_revision_occurrence_id"].string,anchor.sheet == change["from_sheet_id"].string,anchor.address == address,model.afterAddress.isEmpty,!model.beforeCell.isNull else { throw BridgeError(code:"WORKBOOK_SMOKE_BEFORE_HISTORY_ANCHOR",message:"이전 쪽 셀을 이력의 원본 근거로 선택하지 못했습니다.") }
        await model.loadCellHistory()
        var sourceObserved = false,laterMissing = false,historyPages = 0
        repeat {
            historyPages += 1
            guard model.cellHistoryAnchor == anchor,model.cellHistoryFailure.isEmpty,!model.cellHistory.isEmpty else { throw BridgeError(code:"WORKBOOK_SMOKE_BEFORE_HISTORY_READ",message:model.cellHistoryFailure.isEmpty ? "이전 셀 근거의 이력이 비어 있습니다." : model.cellHistoryFailure) }
            for event in model.cellHistory {
                guard model.revisions.contains(where:{$0["revision_occurrence_id"].string == event["revision_occurrence_id"].string}) else { throw BridgeError(code:"WORKBOOK_SMOKE_BEFORE_HISTORY_SCOPE",message:"고정 보고서 밖의 셀 이력이 표시됐습니다.") }
                if event["revision_occurrence_id"].string == anchor.occurrence,event["cell"]["address"].string == address,!event["cell"].isNull { sourceObserved = true }
                if event["revision_occurrence_id"].string == change["to_revision_occurrence_id"].string,event["availability"].string == "not_materialized",event["cell"].isNull,!event["address"].string.isEmpty { laterMissing = true }
            }
            if sourceObserved && laterMissing || model.cellHistoryCursor.isEmpty || historyPages >= 100 { break }
            await model.loadCellHistory(next:true)
        } while true
        guard sourceObserved,laterMissing else { throw BridgeError(code:"WORKBOOK_SMOKE_BEFORE_HISTORY_TRUTH",message:"이전 셀 관측과 이후의 명시된 관측 공백을 이력에서 확인하지 못했습니다.") }
        try await Task.sleep(nanoseconds:250_000_000)
        let panes = try assertPanes(model,window:window)
        try Smoke.captureView(window,folder.appendingPathComponent("native-workbook-before-only-history.png"))
        return ["address":address,"anchor_occurrence":anchor.occurrence,"anchor_sheet":anchor.sheet,"source_observation_present":true,"later_hole_explicitly_not_materialized":true,"history_pages":historyPages,"project_report_scope_preserved":true,"panes":panes]
    }
    private static func exerciseModeInterval(_ model: WorkbookModel,request: JSON) async throws -> [String:Any] {
        guard model.revisions.count >= 3,let first = model.revisions.first,let last = model.revisions.last else { return ["not_applicable":"fewer_than_three_versions"] }
        let from = first["revision_occurrence_id"].string,to = last["revision_occurrence_id"].string
        await model.changeVersions(before:from,after:to); await model.changeMode("history")
        guard model.changesFailure.isEmpty else { throw BridgeError(code:"WORKBOOK_SMOKE_MODE_HISTORY",message:model.changesFailure) }
        let historyCount = model.changeTotal,firstPageIDs = model.changes.map { $0["change_id"].string }
        func intermediate(_ change: JSON) -> Bool {
            change["to_revision_occurrence_id"].string != to && (!change["before_address"].string.isEmpty || !change["after_address"].string.isEmpty)
        }
        var selected = model.changes.first(where:intermediate),pages = 1
        while selected == nil,!model.changeCursor.isEmpty,pages < 100 { await model.loadChanges(next:true); pages += 1; selected = model.changes.first(where:intermediate) }
        guard let selected else {
            if request["require_mode_interval_check"].bool { throw BridgeError(code:"WORKBOOK_SMOKE_MODE_FIXTURE",message:"넓은 구간 안의 중간 변경을 검증할 원본 이력이 없습니다.") }
            return ["not_applicable":"no_intermediate_cell_change"]
        }
        await model.chooseChange(selected["change_id"].string)
        guard model.cellFailure.isEmpty,model.rangeFailure.isEmpty else { throw BridgeError(code:"WORKBOOK_SMOKE_MODE_EVIDENCE",message:model.cellFailure + model.rangeFailure) }
        let paneState = [model.beforeID,model.afterID,model.beforeAddress,model.afterAddress,String(model.beforeRowStart),String(model.beforeColumnStart),String(model.afterRowStart),String(model.afterColumnStart),String(model.selectedRow),String(model.selectedColumn)]
        let beforeCell = try model.beforeCell.data(),afterCell = try model.afterCell.data()
        for method in ["range_net","history"] {
            await model.changeMode(method)
            let currentPanes = [model.beforeID,model.afterID,model.beforeAddress,model.afterAddress,String(model.beforeRowStart),String(model.beforeColumnStart),String(model.afterRowStart),String(model.afterColumnStart),String(model.selectedRow),String(model.selectedColumn)]
            guard model.changesFromID == from,model.changesToID == to,paneState == currentPanes,try model.beforeCell.data() == beforeCell,try model.afterCell.data() == afterCell,model.changesFailure.isEmpty else { throw BridgeError(code:"WORKBOOK_SMOKE_MODE_INTERVAL",message:"비교 방법 변경이 넓은 구간이나 선택한 셀 근거를 바꿨습니다.") }
            if method == "history" {
                guard model.changeTotal == historyCount,model.changes.map({$0["change_id"].string}) == firstPageIDs else { throw BridgeError(code:"WORKBOOK_SMOKE_MODE_HISTORY_TRUTH",message:"전체 이력으로 돌아온 뒤 넓은 구간의 변경이 달라졌습니다.") }
            } else {
                let ticket = model.begin("mode-smoke-check")
                let expected = try await model.query("list_workbook_changes",["from_revision_occurrence_id":from,"to_revision_occurrence_id":to,"mode":model.changesMode,"limit":100,"max_output_tokens":model.pagingOutputBudget,"text_length":128],ticket:ticket)
                guard model.changeTotal == expected["total"].int,model.changes.map({$0["change_id"].string}) == expected["items"].array.map({$0["change_id"].string}) else { throw BridgeError(code:"WORKBOOK_SMOKE_MODE_NET_TRUTH",message:"순변경 응답이 명시한 넓은 구간과 다릅니다.") }
            }
        }
        return ["wide_from":from,"wide_to":to,"selected_from":paneState[0],"selected_to":paneState[1],"wide_interval_retained_across_mode_switch":true,"pane_versions_coordinates_and_raw_cells_retained":true,"actual_scoped_query_matches":true]
    }
    private static func grid(_ view: NSView?,pane: String) -> NSTableView? {
        guard let view else { return nil }
        if let table = view as? NSTableView,table.identifier?.rawValue == "Docver.workbook.grid." + pane { return table }
        for child in view.subviews { if let table = grid(child,pane:pane) { return table } }
        return nil
    }
    private static func assertHeaderGeometry(_ table: NSTableView,state: WorkbookGrid,pane: String) throws -> [[String:Any]] {
        guard let header = table.headerView,header.tableView === table,!table.allowsColumnReordering,table.tableColumns.count == state.columnCount+1 else { throw BridgeError(code:"WORKBOOK_SMOKE_HEADER_STRUCTURE",message:"셀 원본 열 순서와 실제 헤더 구조가 다릅니다: " + pane) }
        let visible = table.convert(table.visibleRect,to:nil),rows = table.rows(in:table.visibleRect)
        var result: [[String:Any]] = []
        for index in table.tableColumns.indices {
            let body = table.convert(table.rect(ofColumn:index),to:nil)
            if index != 0,body.maxX <= visible.minX || body.minX >= visible.maxX { continue }
            let title = header.convert(header.headerRect(ofColumn:index),to:nil)
            let physicalColumn = state.columnStart+index-1,expectedID = index == 0 ? "row" : String(physicalColumn),expectedTitle = index == 0 ? "행" : WorkbookGrid.columnLabel(physicalColumn)
            guard table.tableColumns[index].identifier.rawValue == expectedID,table.tableColumns[index].headerCell.stringValue == expectedTitle else { throw BridgeError(code:"WORKBOOK_SMOKE_HEADER_IDENTITY",message:"물리 열의 헤더·식별자가 다릅니다: " + pane + " · " + expectedTitle) }
            guard abs(title.minX-body.minX) <= 0.75,abs(title.maxX-body.maxX) <= 0.75 else { throw BridgeError(code:"WORKBOOK_SMOKE_HEADER_ALIGNMENT",message:"실제 헤더와 셀 열의 화면 좌표가 다릅니다: \(pane) \(expectedTitle), header=\(title.minX)…\(title.maxX), body=\(body.minX)…\(body.maxX)") }
            var item: [String:Any] = ["column_id":expectedID,"title":expectedTitle,"header_min_x":title.minX,"header_max_x":title.maxX,"body_min_x":body.minX,"body_max_x":body.maxX,"aligned":true]
            if rows.length > 0,rows.location < state.rowCount,body.maxX > visible.minX,body.minX < visible.maxX {
                let row = rows.location,physicalRow = state.rowStart+row
                let expectedCell = index == 0 ? "Docver.workbook.row.\(physicalRow)" : "Docver.workbook.cell." + WorkbookGrid.address(physicalRow,physicalColumn)
                guard let cell = table.view(atColumn:index,row:row,makeIfNecessary:false) as? NSTableCellView,cell.textField?.identifier?.rawValue == expectedCell else { throw BridgeError(code:"WORKBOOK_SMOKE_HEADER_CELL_IDENTITY",message:"표시된 헤더 아래 셀의 물리 주소가 다릅니다: " + pane + " · " + expectedCell) }
                item["rendered_cell_id"] = expectedCell
            }
            result.append(item)
        }
        return result
    }
    private static func assertPanes(_ model: WorkbookModel,window: NSWindow) throws -> [[String:Any]] {
        var result: [[String:Any]] = []
        window.contentView?.layoutSubtreeIfNeeded()
        for before in [true,false] {
            let name = before ? "before" : "after",sheet = before ? model.beforeSheetID : model.afterSheetID
            if sheet.isEmpty {
                guard grid(window.contentView,pane:name) == nil,model.paneCoordinate(before:before) == nil else { throw BridgeError(code:"WORKBOOK_SMOKE_MISSING_PANE",message:"없는 시트에 임의 셀 강조가 남았습니다.") }
                result.append(["pane":name,"availability":"no_sheet","highlight":NSNull()]); continue
            }
            guard let table = grid(window.contentView,pane:name),let coordinator = table.dataSource as? WorkbookGrid.Coordinator else { throw BridgeError(code:"WORKBOOK_SMOKE_PANE",message:"실제 통합 문서 그리드 데이터 원본이 없습니다.") }
            let state = coordinator.parent,row = before ? model.beforeRowStart : model.afterRowStart,column = before ? model.beforeColumnStart : model.afterColumnStart
            guard state.rowStart == row,state.columnStart == column else { throw BridgeError(code:"WORKBOOK_SMOKE_PANE_ORIGIN",message:"이전·이후 범위 시작 주소가 실제 그리드와 다릅니다.") }
            let headerGeometry = try assertHeaderGeometry(table,state:state,pane:name)
            guard let coordinate = model.paneCoordinate(before:before) else {
                guard state.selectedRow == 0,state.selectedColumn == 0,table.selectedRow < 0 else { throw BridgeError(code:"WORKBOOK_SMOKE_EMPTY_ENDPOINT",message:"셀 근거가 없는 끝점에 임의 셀 강조가 남았습니다.") }
                result.append(["pane":name,"availability":"no_cell_evidence","highlight":NSNull(),"row_start":row,"column_start":column,"header_geometry":headerGeometry]); continue
            }
            let localRow = coordinate.row-row,localColumn = coordinate.column-column+1
            guard state.selectedRow == coordinate.row,state.selectedColumn == coordinate.column,localRow >= 0,localRow < state.rowCount,localColumn > 0,localColumn <= state.columnCount,table.selectedRow == localRow,table.visibleRect.intersects(table.frameOfCell(atColumn:localColumn,row:localRow)) else { throw BridgeError(code:"WORKBOOK_SMOKE_PANE_EVIDENCE",message:"이전·이후의 실제 셀 근거가 올바르게 강조되어 화면에 표시되지 않았습니다: " + name) }
            guard let highlighted = table.view(atColumn:localColumn,row:localRow,makeIfNecessary:false),highlighted.layer?.borderWidth == 1 else { throw BridgeError(code:"WORKBOOK_SMOKE_PANE_HIGHLIGHT",message:"실제 셀 주소의 강조 테두리를 확인하지 못했습니다: " + name) }
            let gutter = table.rect(ofColumn:0),gutterVisible = table.visibleRect.intersection(gutter).width >= gutter.width-0.5
            if state.columnStart == 1,table.rect(ofColumn:localColumn).maxX <= table.visibleRect.width {
                guard gutterVisible else { throw BridgeError(code:"WORKBOOK_SMOKE_ROW_GUTTER",message:"셀 근거와 함께 표시할 수 있는 행 번호가 가로 스크롤로 가려졌습니다: " + name) }
            }
            let cell = before ? model.beforeCell : model.afterCell,cells = before ? model.beforeCells : model.afterCells
            guard cell.isNull || cells.contains(where:{$0["row"].int == coordinate.row && $0["column"].int == coordinate.column}) else { throw BridgeError(code:"WORKBOOK_SMOKE_PANE_SOURCE",message:"셀 원문은 있지만 표시 범위에 해당 원본 관측이 없습니다.") }
            result.append(["pane":name,"highlight":WorkbookGrid.address(coordinate.row,coordinate.column),"row_start":row,"column_start":column,"selected_local_row":table.selectedRow,"visible":true,"cell_border_visible":true,"row_gutter_visible":gutterVisible,"header_geometry":headerGeometry])
        }
        return result
    }
}
