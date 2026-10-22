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
    @Published var rowStart = 1
    @Published var columnStart = 1
    let rowLimit = 100
    let columnLimit = 12
    @Published var beforeCells: [JSON] = []
    @Published var afterCells: [JSON] = []
    @Published var changes: [JSON] = []
    @Published var selectedChangeID = ""
    @Published var selectedRow = 0
    @Published var selectedColumn = 0
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
    @Published var changeTotal = 0
    @Published var changesFromID = ""
    @Published var changesToID = ""
    @Published var changesMode = "range_net"
    @Published var cellHistoryMessage = ""
    @Published var cellHistoryCursor = ""
    @Published var cellHistoryTotal = 0
    @Published var busy = false
    @Published var loadingDemo = false
    @Published var loadingReport = false
    @Published var loadingRange = false
    @Published var loadingChanges = false
    @Published var loadingCell = false
    @Published var loadingMCP = false
    @Published var status = ""
    @Published var failure = ""
    @Published var rangeFailure = ""
    @Published var changesFailure = ""
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
    init(bridge: Bridge) { self.bridge = bridge }
    var revisions: [JSON] { report["revisions"].array }
    var scope: String { projectID + "|" + reportID }
    var rangeScope: String { [scope,beforeID,afterID,beforeSheetID,afterSheetID,String(rowStart),String(columnStart)].joined(separator:"|") }
    var comparisonScope: String { [scope,changesFromID,changesToID,changesMode].joined(separator:"|") }
    var ready: Bool { active && !reportID.isEmpty && report["report_id"].string == reportID && !loadingReport && !busy && !loadingDemo }
    var project: JSON { projects.first { $0["project_id"].string == projectID } ?? JSON() }
    var selectedChange: JSON { changes.first { $0["change_id"].string == selectedChangeID } ?? JSON() }
    func revision(_ id: String) -> JSON { revisions.first { $0["revision_occurrence_id"].string == id } ?? JSON() }
    func sheets(_ occurrence: String) -> [JSON] { revision(occurrence)["sheets"].array }
    func sheet(_ occurrence: String, _ id: String) -> JSON { sheets(occurrence).first { $0["sheet_id"].string == id } ?? JSON() }
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
        loadingRange = false; loadingChanges = false; loadingCell = false; loadingMCP = false
        mcp = ""; mcpScope = ""; mcpFailure = ""
    }
    func closeReads() {
        active = false; invalidateReads(); loadingReport = false; loadingDemo = false; clearCells()
        if canCancelAnalysis { cancelAnalysis() }
    }
    func clearCells() {
        invalidate("range"); invalidate("cell"); invalidate("history")
        beforeCells = []; afterCells = []; beforeCell = JSON(); afterCell = JSON(); cellHistory = []; cellHistoryMessage = ""; cellHistoryCursor = ""; cellHistoryTotal = 0
        selectedRow = 0; selectedColumn = 0; selectedChangeID = ""; beforeAddress = ""; afterAddress = ""; cellTextOffset = 0; cellTextNext = nil
        rangeFailure = ""; cellFailure = ""; loadingRange = false; loadingCell = false
    }
    func clearSelection() {
        clearCells(); changes = []; coverage = []; releases = []; changeCursor = ""; changeTotal = 0
        changesFailure = ""; changesFromID = ""; changesToID = ""; loadingChanges = false; report = JSON(); reportID = ""
        beforeID = ""; afterID = ""; beforeSheetID = ""; afterSheetID = ""
        rowStart = 1; columnStart = 1; addressInput = "A1"
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
        clearCells(); invalidate("changes")
        if let before { beforeID = before }; if let after { afterID = after }
        changes = []; changeCursor = ""; changeTotal = 0
        rowStart = 1; columnStart = 1; addressInput = "A1"; selectInitialSheets()
        let identity = rangeScope
        await loadRange()
        guard rangeScope == identity, ready else { return }; await loadChanges()
    }
    func changeSheet(before: String? = nil, after: String? = nil) async {
        guard ready else { return }; clearCells()
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
        let row = rowStart, column = columnStart
        beforeCells = []; afterCells = []; rangeFailure = ""; loadingRange = true
        do {
            let a = try await rangeCells(occurrence:old,sheet:left,row:row,column:column,ticket:ticket,identity:identity)
            guard current(ticket), rangeScope == identity else { return }
            let b: [JSON]
            if old == new && left == right { b = a }
            else { b = try await rangeCells(occurrence:new,sheet:right,row:row,column:column,ticket:ticket,identity:identity) }
            guard current(ticket), rangeScope == identity else { return }
            beforeCells = a; afterCells = b; loadingRange = false
        } catch {
            guard current(ticket), rangeScope == identity else { return }
            beforeCells = []; afterCells = []; loadingRange = false; rangeFailure = error.localizedDescription
        }
    }
    func loadChanges(next: Bool = false) async {
        guard ready, !beforeID.isEmpty, !afterID.isEmpty else { return }
        if !next { changesFromID = beforeID; changesToID = afterID; changesMode = mode }
        let ticket = begin("changes"), identity = comparisonScope
        loadingChanges = true; changesFailure = ""
        if !next { changes = []; selectedChangeID = ""; changeCursor = "" }
        var args: [String:Any] = ["from_revision_occurrence_id":changesFromID,"to_revision_occurrence_id":changesToID,"mode":changesMode,"limit":100,"max_output_tokens":8000,"text_length":128]
        if next, !changeCursor.isEmpty { args["cursor"] = changeCursor }
        do {
            let value = try await query("list_workbook_changes",args,ticket:ticket)
            guard current(ticket), comparisonScope == identity else { return }
            changes = value["items"].array; changeCursor = value["next_cursor"].string
            changeTotal = value["total"].int; loadingChanges = false
        } catch {
            guard current(ticket), comparisonScope == identity else { return }
            changes = []; changeCursor = ""; selectedChangeID = ""; loadingChanges = false; changesFailure = error.localizedDescription
        }
    }
    func changeMode(_ value: String) async {
        guard ready else { return }; mode = value; await loadChanges()
    }
    func moveWindow(rows: Int = 0, columns: Int = 0) async {
        guard ready else { return }
        rowStart = min(1_048_576-rowLimit+1,max(1,rowStart+rows))
        columnStart = min(16_384-columnLimit+1,max(1,columnStart+columns))
        clearCells(); addressInput = WorkbookGrid.address(rowStart,columnStart); await loadRange()
    }
    func goToAddress() async {
        guard ready else { return }
        guard let (row,column) = WorkbookGrid.parseAddress(addressInput) else { rangeFailure = "A1–XFD1048576 형식의 물리 셀 주소를 입력하세요."; return }
        rowStart = max(1,min(row,1_048_576-rowLimit+1)); columnStart = max(1,min(column,16_384-columnLimit+1))
        clearCells(); addressInput = WorkbookGrid.address(row,column); let identity = rangeScope
        await loadRange(); guard ready, rangeScope == identity else { return }; await selectCell(row,column)
    }
    func selectCell(_ row: Int, _ column: Int) async {
        guard ready else { return }
        selectedChangeID = ""; selectedRow = row; selectedColumn = column
        beforeAddress = WorkbookGrid.address(row,column); afterAddress = beforeAddress
        await loadSelectedCells()
    }
    func loadSelectedCells(offset: Int = 0) async {
        guard ready else { return }
        invalidate("history")
        let oldAddress = beforeAddress, newAddress = afterAddress
        beforeCell = JSON(); afterCell = JSON(); cellHistory = []; cellHistoryMessage = ""; cellHistoryCursor = ""; cellHistoryTotal = 0; cellFailure = ""; loadingCell = true; cellTextOffset = offset; cellTextNext = nil
        let ticket = begin("cell"), identity = rangeScope
        do {
            var a = JSON(), b = JSON()
            if !beforeSheetID.isEmpty,let (row,column) = WorkbookGrid.parseAddress(oldAddress) {
                let value = try await query("get_workbook_cell",["revision_occurrence_id":beforeID,"sheet_id":beforeSheetID,"row":row,"column":column,"text_offset":offset,"text_length":1024,"max_output_tokens":8000],ticket:ticket)
                guard current(ticket), rangeScope == identity, beforeAddress == oldAddress, afterAddress == newAddress else { return }
                a = Self.cellResult(value)
            }
            if !afterSheetID.isEmpty,let (row,column) = WorkbookGrid.parseAddress(newAddress) {
                let value = try await query("get_workbook_cell",["revision_occurrence_id":afterID,"sheet_id":afterSheetID,"row":row,"column":column,"text_offset":offset,"text_length":1024,"max_output_tokens":8000],ticket:ticket)
                guard current(ticket), rangeScope == identity, beforeAddress == oldAddress, afterAddress == newAddress else { return }
                b = Self.cellResult(value)
            }
            guard current(ticket), rangeScope == identity, beforeAddress == oldAddress, afterAddress == newAddress else { return }
            beforeCell = a; afterCell = b; loadingCell = false
            cellTextNext = [a,b].flatMap { cell in ["value","formula","number_format"].compactMap { key -> Int? in let cursor = cell["text_continuations"][key]["next_offset"]; return cursor.isNull ? nil : cursor.int } }.filter { $0 > offset }.min()
        } catch {
            guard current(ticket), rangeScope == identity, beforeAddress == oldAddress, afterAddress == newAddress else { return }
            beforeCell = JSON(); afterCell = JSON(); loadingCell = false; cellFailure = error.localizedDescription
        }
    }
    static func cellResult(_ value: JSON) -> JSON {
        if !value["cell"].isNull { return value["cell"] }
        let item = value["items"].array.first ?? value
        return item["cell"].isNull ? (item["address"].string.isEmpty ? JSON() : item) : item["cell"]
    }
    func chooseChange(_ id: String) async {
        guard ready, let change = changes.first(where:{$0["change_id"].string == id}) else { return }
        invalidate("cell"); invalidate("history"); cellHistory = []; beforeCell = JSON(); afterCell = JSON(); cellFailure = ""; loadingCell = false
        let a = change["from_revision_occurrence_id"].string, b = change["to_revision_occurrence_id"].string
        guard revisions.contains(where:{$0["revision_occurrence_id"].string == a}), revisions.contains(where:{$0["revision_occurrence_id"].string == b}) else { cellFailure = "변경의 버전 근거를 찾지 못했습니다."; return }
        beforeID = a; afterID = b
        beforeSheetID = change["from_sheet_id"].string; afterSheetID = change["to_sheet_id"].string
        let address = change["after_address"].string.isEmpty ? change["before_address"].string : change["after_address"].string
        if let (row,column) = WorkbookGrid.parseAddress(address) {
            rowStart = min(row,1_048_576-rowLimit+1); columnStart = min(column,16_384-columnLimit+1)
            selectedRow = row; selectedColumn = column; addressInput = address
        } else { selectedRow = 0; selectedColumn = 0 }
        selectedChangeID = id; beforeAddress = change["before_address"].string; afterAddress = change["after_address"].string
        beforeCell = change["before"]; afterCell = change["after"]; cellTextOffset = 0; cellTextNext = nil
        await loadRange()
        if currentChangeIs(id) { await loadSelectedCells() }
    }
    private func currentChangeIs(_ id: String) -> Bool { ready && selectedChangeID == id }
    func stepChange(_ offset: Int) async {
        guard !changes.isEmpty else { return }
        let index = changes.firstIndex(where:{$0["change_id"].string == selectedChangeID}) ?? (offset > 0 ? -1 : changes.count)
        let target = index + offset
        if changes.indices.contains(target) { await chooseChange(changes[target]["change_id"].string) }
    }
    func loadCellHistory(next: Bool = false) async {
        guard ready, selectedRow > 0, selectedColumn > 0, !afterSheetID.isEmpty else { return }
        guard let (row,column) = WorkbookGrid.parseAddress(afterAddress) else { return }
        let ticket = begin("history"), identity = rangeScope, address = afterAddress
        let cursor = next ? cellHistoryCursor : ""
        cellHistory = []; cellHistoryMessage = "이력을 읽는 중…"; cellFailure = ""
        do {
            var args: [String:Any] = ["revision_occurrence_id":afterID,"sheet_id":afterSheetID,"row":row,"column":column,"limit":100,"max_output_tokens":8000,"text_length":128]
            if !cursor.isEmpty { args["cursor"] = cursor }
            let value = try await query("get_workbook_cell_history",args,ticket:ticket)
            guard current(ticket), rangeScope == identity, afterAddress == address else { return }
            cellHistory = value["items"].array
            cellHistoryCursor = value["next_cursor"].string; cellHistoryTotal = value["total"].int
            cellHistoryMessage = cellHistory.isEmpty ? "기록된 셀 이력이 없습니다." : "이번 페이지 \(cellHistory.count)개 / 총 \(cellHistoryTotal)개 · 첫 열 고유 키로 추정한 이력이며 대응 미확정 위치는 명시합니다."
        } catch {
            guard current(ticket), rangeScope == identity, afterAddress == address else { return }
            cellHistory = []; cellHistoryMessage = ""; cellHistoryCursor = ""; cellHistoryTotal = 0; cellFailure = error.localizedDescription
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
    func run() async {
        guard active, !busy, !loadingDemo, !projectID.isEmpty else { return }
        let project = projectID, oldReport = reportID, token = UUID()
        defer { bridge.releaseAnalysis(owner:token) }
        analysisToken = token; committing = false
        invalidateReads(); busy = true; cancelRequested = false; failure = ""; status = "원본 통합 문서를 읽고 버전 차이를 분석하는 중…"
        do {
            let staged = try await bridge.call("workbookAnalyze",["project_id":project],analysis:true,analysisOwner:token,holdAnalysis:true)
            guard active, !cancelRequested, projectID == project else { throw CancellationError() }
            committing = true; status = "고정 보고서를 저장하는 중…"
            let committed = try await bridge.call("workbookCommit",["project_id":project,"result":staged.raw])
            guard projectID == project else { throw CancellationError() }
            analysisToken = nil; committing = false; busy = false; status = "분석 완료 · 원본과 보고서를 고정했습니다."
            let completion = begin("analysis-completion")
            await refreshProjects()
            guard active, current(completion), projectID == project else { return }
            await selectProject(project,snapshot:committed["report_id"].string)
        } catch {
            analysisToken = nil; committing = false; busy = false
            let cancelled = cancelRequested || error is CancellationError || (error as? BridgeError)?.code == "CANCELLED"
            status = cancelled ? "분석을 취소했습니다. 이전 고정 보고서를 유지합니다." : "분석하지 못했습니다. 이전 고정 보고서를 유지합니다."
            let message = error.localizedDescription
            if active, projectID == project, !oldReport.isEmpty { await selectProject(project,snapshot:oldReport) }
            failure = cancelled ? "" : message
            if cancelled { status = "분석을 취소했습니다. 이전 고정 보고서를 유지합니다." }
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
                Text("\(WorkbookGrid.columnLabel(model.columnStart))–\(WorkbookGrid.columnLabel(model.columnStart+model.columnLimit-1))열").font(.caption.monospacedDigit())
                Button { Task { await model.moveWindow(columns:model.columnLimit) } } label: { Image(systemName:"chevron.right") }.disabled(model.columnStart+model.columnLimit>16384).accessibilityLabel("다음 12열")
                Button { Task { await model.moveWindow(rows:-model.rowLimit) } } label: { Image(systemName:"chevron.up") }.disabled(model.rowStart == 1).accessibilityLabel("이전 100행")
                Text("\(model.rowStart)–\(model.rowStart+model.rowLimit-1)행").font(.caption.monospacedDigit())
                Button { Task { await model.moveWindow(rows:model.rowLimit) } } label: { Image(systemName:"chevron.down") }.disabled(model.rowStart+model.rowLimit>1048576).accessibilityLabel("다음 100행")
            }.padding(.horizontal,12).padding(.vertical,7).disabled(!model.ready)
            if !model.rangeFailure.isEmpty { Text(verbatim:model.rangeFailure).font(.caption).foregroundStyle(.red).padding(8) }
            HSplitView {
                gridPane(before:true)
                gridPane(before:false)
            }.frame(minHeight:240,maxHeight:.infinity).overlay { if model.loadingRange { ZStack { Color(nsColor:.windowBackgroundColor).opacity(0.94); ProgressView("셀 범위를 읽는 중…") } } }
            Text("물리 주소 기준 나란히 보기 · 행/시트 대응은 변경 근거의 추정 방법을 확인하세요. 빈 칸은 저장된 관측이 없는 위치이며 삭제를 뜻하지 않습니다.").font(.caption).foregroundStyle(.secondary).padding(.horizontal,12).padding(.vertical,6)
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
        return VStack(alignment:.leading,spacing:0) {
            HStack { Text(verbatim:(before ? "이전 · " : "이후 · ") + model.versionLabel(occurrence)).font(.caption.weight(.semibold)); Spacer(); if sheet["hidden"].bool { Label("숨김 시트",systemImage:"eye.slash").font(.caption) } }.padding(8).background(Color(nsColor:.controlBackgroundColor))
            if id.isEmpty { WorkbookStatus(title:"대응 시트 없음",detail:"다른 시트를 선택하거나 변경 근거에서 추가·삭제 여부를 확인하세요.",loading:false) }
            else { WorkbookGrid(cells:cells,rowStart:model.rowStart,columnStart:model.columnStart,rowCount:model.rowLimit,columnCount:model.columnLimit,selectedRow:model.selectedRow,selectedColumn:model.selectedColumn,onSelect:{row,column in Task { await model.selectCell(row,column) }}).disabled(!model.ready || model.loadingRange) }
        }.frame(minWidth:280,maxWidth:.infinity,maxHeight:.infinity)
    }
    private var changesPane: some View {
        VStack(spacing:0) {
            HStack {
                Text(model.changesMode == "history" ? "구간의 중간 변경 이력" : "두 버전 사이의 순변경").font(.headline)
                Text("표시 \(model.changes.count)개 / 총 \(model.changeTotal)개").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button { Task { await model.stepChange(-1) } } label: { Image(systemName:"chevron.up") }.accessibilityLabel("이전 변경")
                Button { Task { await model.stepChange(1) } } label: { Image(systemName:"chevron.down") }.accessibilityLabel("다음 변경")
                if !model.changeCursor.isEmpty { Button("다음 변경") { Task { await model.loadChanges(next:true) } } }
            }.padding(.horizontal,12).padding(.vertical,7).disabled(!model.ready || model.loadingChanges)
            Text(verbatim:model.versionLabel(model.changesFromID) + " → " + model.versionLabel(model.changesToID)).font(.caption).foregroundStyle(.secondary).lineLimit(1).padding(.horizontal,12).frame(maxWidth:.infinity,alignment:.leading)
            if model.loadingChanges { ProgressView("변경을 읽는 중…").frame(maxWidth:.infinity,maxHeight:.infinity) }
            else if !model.changesFailure.isEmpty { Text(verbatim:model.changesFailure).font(.caption).foregroundStyle(.red).padding(12).frame(maxWidth:.infinity,maxHeight:.infinity) }
            else if model.changes.isEmpty { Text("선택한 구간에서 기록된 변경이 없습니다. 판독 범위의 한계는 셀 근거에서 확인하세요.").font(.callout).foregroundStyle(.secondary).frame(maxWidth:.infinity,maxHeight:.infinity) }
            else {
                List(selection:Binding<String?>(get:{model.selectedChangeID.isEmpty ? nil : model.selectedChangeID},set:{if let id = $0 { Task { await model.chooseChange(id) } }})) {
                    ForEach(model.changes,id:\.workbookChangeID) { change in
                        HStack(spacing:10) {
                            Text(verbatim:WorkbookLabels.kind(change["kind"].string)).font(.caption.weight(.semibold)).frame(width:110,alignment:.leading)
                            Text(verbatim:change["before_address"].string + " → " + change["after_address"].string).font(.system(.caption,design:.monospaced)).frame(width:125,alignment:.leading)
                            Text(verbatim:change["description"].string).font(.caption).lineLimit(2)
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
                WorkbookCoverageView(gaps:model.coverage + model.sheet(model.afterID,model.afterSheetID)["coverage_gaps"].array,total:model.report["coverage_gap_count"].int,truncated:model.report["coverage_truncated"].bool)
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
                Text("저장된 수식 결과 · 재계산하지 않음").font(.caption.weight(.medium)).foregroundStyle(.orange)
                Text(verbatim:"날짜 기준: 이전 " + model.revision(model.beforeID)["date_system"].string + " / 이후 " + model.revision(model.afterID)["date_system"].string).font(.caption).foregroundStyle(.secondary)
                if model.loadingCell { ProgressView("셀을 읽는 중…") }
                else if !model.cellFailure.isEmpty { Text(verbatim:model.cellFailure).font(.caption).foregroundStyle(.red) }
                else if model.selectedRow == 0, model.selectedChangeID.isEmpty { Text("셀 또는 변경 항목을 선택하면 수식 원문·저장된 값·유형을 확인할 수 있습니다.").foregroundStyle(.secondary) }
                else { WorkbookCellDetail(title:"이전 · " + model.versionLabel(model.beforeID),cell:model.beforeCell); Divider(); WorkbookCellDetail(title:"이후 · " + model.versionLabel(model.afterID),cell:model.afterCell) }
                if model.cellTextOffset > 0 || model.cellTextNext != nil {
                    Text("긴 셀 원문 일부 · UTF-16 위치 \(model.cellTextOffset)부터 표시").font(.caption).foregroundStyle(.secondary)
                    HStack { if model.cellTextOffset > 0 { Button("처음") { Task { await model.loadSelectedCells() } } }; if let next = model.cellTextNext { Button("원문 이어 읽기") { Task { await model.loadSelectedCells(offset:next) } } } }.disabled(model.loadingCell || !model.ready)
                }
                if !model.selectedChange.isNull {
                    Divider(); Text("변경과 대응 방법").font(.headline)
                    Text(verbatim:WorkbookLabels.kind(model.selectedChange["kind"].string)).font(.callout)
                    Text(verbatim:WorkbookLabels.association(model.selectedChange["association"].string)).font(.caption.weight(.medium))
                    Text(verbatim:model.selectedChange["alignment_method"].string).font(.system(.caption,design:.monospaced)).textSelection(.enabled)
                    Text(verbatim:model.selectedChange["description"].string).font(.caption)
                    Text("추정 대응은 같은 업무 레코드임을 확정하지 않습니다. 모호한 대응을 삭제로 해석하지 마세요.").font(.caption).foregroundStyle(.secondary)
                }
                if model.selectedRow > 0 {
                    Button("선택 셀 이력 읽기") { Task { await model.loadCellHistory() } }.disabled(!model.ready || model.loadingCell)
                    if !model.cellHistoryMessage.isEmpty { Text(verbatim:model.cellHistoryMessage).font(.caption).foregroundStyle(.secondary) }
                    if !model.cellHistoryCursor.isEmpty { Button("다음 셀 이력") { Task { await model.loadCellHistory(next:true) } }.disabled(!model.ready) }
                    ForEach(Array(model.cellHistory.enumerated()),id:\.offset) { _, event in
                        VStack(alignment:.leading,spacing:3) { Text(verbatim:model.versionLabel(event["revision_occurrence_id"].string)).lineLimit(2); Text(verbatim:event["cell"]["address"].string + " · " + event["cell"]["value"].string); Text(verbatim:event["availability"].string + " · " + WorkbookLabels.association(event["association"].string)); Text(verbatim:event["alignment_method"].string) }.font(.caption).textSelection(.enabled)
                    }
                }
                Divider()
                WorkbookSheetMetadata(title:"이전 시트 메타데이터",sheet:model.sheet(model.beforeID,model.beforeSheetID))
                WorkbookSheetMetadata(title:"이후 시트 메타데이터",sheet:model.sheet(model.afterID,model.afterSheetID))
                WorkbookCoverageView(gaps:model.coverage + model.sheet(model.beforeID,model.beforeSheetID)["coverage_gaps"].array + model.sheet(model.afterID,model.afterSheetID)["coverage_gaps"].array,total:model.report["coverage_gap_count"].int,truncated:model.report["coverage_truncated"].bool)
            }.padding(14).frame(maxWidth:.infinity,alignment:.leading)
        }.background(Color(nsColor:.controlBackgroundColor))
    }
}
private struct WorkbookCellDetail: View {
    let title: String
    let cell: JSON
    var body: some View {
        VStack(alignment:.leading,spacing:7) {
            Text(verbatim:title).font(.headline).lineLimit(2)
            if cell.isNull { Text("저장된 셀 관측 없음 · 삭제를 확정하지 않음").font(.caption).foregroundStyle(.secondary) }
            else {
                Text(verbatim:cell["address"].string + " · " + cell["value_type"].string).font(.system(.caption,design:.monospaced))
                if cell["formula_interpretation"].string == "unresolved" { Text("공유·배열 수식의 셀별 의미 확인 필요").font(.caption.weight(.medium)).foregroundStyle(.orange) }
                if !cell["formula"].isNull { detail("수식 원문",cell["formula"].string); Text("수식은 실행하지 않았습니다.").font(.caption2).foregroundStyle(.secondary) }
                detail(cell["formula_interpretation"].string == "unresolved" ? "저장된 관측값 · 입력/계산 결과 미확정" : cell["formula"].isNull ? "저장된 입력값" : "저장된 계산 결과",cell["value"].isNull ? "값 관측 없음 · 빈 문자열/0과 다름" : cell["value"].string.isEmpty ? "빈 문자열" : cell["value"].string)
                if !cell["number_format"].isNull { detail("원본 숫자 형식",cell["number_format"].string) }
                if cell["hidden_row"].bool || cell["hidden_column"].bool { Label((cell["hidden_row"].bool ? "숨김 행 " : "") + (cell["hidden_column"].bool ? "숨김 열" : ""),systemImage:"eye.slash").font(.caption).foregroundStyle(.orange) }
                if !cell["style"].dictionary.isEmpty { detail("원본 기본 스타일",cell["style"].dictionary.keys.sorted().map { $0 + ": " + cell["style"][$0].string }.joined(separator:"\n")) }
                if cell["style_truncated"].bool { Text("기본 스타일의 일부만 표시합니다.").font(.caption).foregroundStyle(.orange) }
                detail("원본 근거",cell["source_ref"].string)
            }
        }
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
    var body: some View {
        VStack(alignment:.leading,spacing:7) {
            Text("판독 범위와 한계").font(.headline)
            Text("Excel·Calc의 계산/화면을 완전히 재현하지 않습니다. 차트, 피벗, 매크로, 외부 데이터 등은 원본 기능별 제한을 확인하세요.").font(.caption).foregroundStyle(.secondary)
            if truncated { Text("고정 보고서의 한계 \(total)개 중 일부를 표시합니다. 전체 항목은 MCP의 판독 한계 조회로 이어 읽을 수 있습니다.").font(.caption).foregroundStyle(.orange) }
            if gaps.isEmpty { Text("보고된 추가 판독 한계 없음 · 완전 호환을 의미하지 않음").font(.caption).foregroundStyle(.secondary) }
            if gaps.count > 50 { Text("한계 \(gaps.count)개 중 50개를 표시합니다. 전체 항목은 고정 보고서/MCP에서 확인하세요.").font(.caption).foregroundStyle(.secondary) }
            ForEach(Array(gaps.prefix(50).enumerated()),id:\.offset) { _, gap in VStack(alignment:.leading,spacing:3) { Text(verbatim:gap["feature"].string + (gap["address"].string.isEmpty ? "" : " · " + gap["address"].string)).font(.caption.weight(.medium)); Text(verbatim:gap["reason"].string).font(.caption).foregroundStyle(.secondary) } }
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
    static func association(_ value: String) -> String { switch value { case "exact": return "원문 일치"; case "inferred": return "추정 대응"; case "needs_review": return "대응 확인 필요"; default: return value.isEmpty ? "대응 미확정" : value } }
    static func kind(_ value: String) -> String { switch value { case "formula": return "수식 변경"; case "cache_availability": return "저장 결과 유무 변경"; case "calculation_settings": return "저장된 계산 설정 변경"; case "stored_value": return "저장값 변경"; case "value_type": return "값 유형 변경"; case "number_format": return "숫자 형식 변경"; case "style": return "기본 서식 변경"; case "visibility": return "숨김 상태 변경"; case "cell_observation": return "셀 관측 차이"; case "row_position": return "행 위치 변경"; case "row_correspondence": return "행 대응 확인"; case "sheet_name": return "시트 이름 변경"; case "sheet_position": return "시트 순서 변경"; case "sheet_visibility": return "시트 숨김 변경"; case "sheet_dimensions": return "행·열 메타 변경"; case "sheet_observation": return "시트 관측 차이"; case "merges": return "병합 범위 변경"; case "date_system": return "날짜 기준 변경"; default: return value } }
}

// AppKit creates reusable cells only for visible rows. The data source is a
// bounded 100×12 physical window backed by sparse observations, never a dense
// workbook. Formula text remains plain text and is never evaluated by AppKit.
struct WorkbookGrid: NSViewRepresentable {
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
        let scroll = NSScrollView(); scroll.hasVerticalScroller = true; scroll.hasHorizontalScroller = true; scroll.autohidesScrollers = false
        let table = NSTableView(); table.identifier = NSUserInterfaceItemIdentifier("Docver.workbook.grid"); table.usesAlternatingRowBackgroundColors = true; table.gridStyleMask = [.solidHorizontalGridLineMask,.solidVerticalGridLineMask]; table.rowHeight = 27; table.headerView = NSTableHeaderView(); table.allowsMultipleSelection = false; table.allowsColumnSelection = true; table.columnAutoresizingStyle = .noColumnAutoresizing
        table.dataSource = context.coordinator; table.delegate = context.coordinator; table.target = context.coordinator; table.action = #selector(Coordinator.clicked(_:)); table.setAccessibilityLabel("통합 문서 셀 그리드 · 물리 주소")
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
            if value.selectedRow >= value.rowStart,value.selectedRow < value.rowStart+value.rowCount { table.selectRowIndexes(IndexSet(integer:value.selectedRow-value.rowStart),byExtendingSelection:false) } else { table.deselectAll(nil) }
        }
        func numberOfRows(in tableView: NSTableView) -> Int { parent.rowCount }
        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            guard let tableColumn else { return nil }
            let id = NSUserInterfaceItemIdentifier("WorkbookPlainCell")
            let cell = tableView.makeView(withIdentifier:id,owner:self) as? NSTableCellView ?? NSTableCellView()
            cell.identifier = id
            let text: NSTextField
            if let existing = cell.textField { text = existing } else { text = NSTextField(labelWithString:""); text.translatesAutoresizingMaskIntoConstraints = false; text.lineBreakMode = .byTruncatingTail; cell.addSubview(text); cell.textField = text; NSLayoutConstraint.activate([text.leadingAnchor.constraint(equalTo:cell.leadingAnchor,constant:6),text.trailingAnchor.constraint(equalTo:cell.trailingAnchor,constant:-5),text.centerYAnchor.constraint(equalTo:cell.centerYAnchor)]) }
            let physicalRow = parent.rowStart+row
            if tableColumn.identifier.rawValue == "row" { text.stringValue = String(physicalRow); text.font = .monospacedDigitSystemFont(ofSize:11,weight:.regular); text.textColor = .secondaryLabelColor; cell.toolTip = nil }
            else {
                let column = Int(tableColumn.identifier.rawValue) ?? 1
                let value = sparse[String(physicalRow)+":"+String(column)] ?? JSON()
                let raw = value["value"].isNull ? "" : value["value"].string
                text.stringValue = String(raw.prefix(400)); text.font = .systemFont(ofSize:12); text.textColor = value["hidden_row"].bool || value["hidden_column"].bool ? .secondaryLabelColor : .labelColor
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

            if let first = model.revisions.first,let last = model.revisions.last {
                await model.changeVersions(before:first["revision_occurrence_id"].string,after:last["revision_occurrence_id"].string)
            }
            await model.changeMode("history")
            let historyCount = model.changeTotal
            if let change = model.changes.first(where:{!$0["after_address"].string.isEmpty || !$0["before_address"].string.isEmpty}) {
                await model.chooseChange(change["change_id"].string)
                guard model.selectedChangeID == change["change_id"].string,model.beforeID == change["from_revision_occurrence_id"].string,model.afterID == change["to_revision_occurrence_id"].string,model.beforeCell.isNull || model.beforeCell["address"].string == change["before_address"].string,model.afterCell.isNull || model.afterCell["address"].string == change["after_address"].string,model.cellFailure.isEmpty else { throw BridgeError(code:"WORKBOOK_SMOKE_EVIDENCE",message:"변경 선택 후 버전·셀 근거가 다릅니다.") }
                checks["history_change_navigation"] = true
                await model.loadCellHistory()
                checks["cell_history_items"] = model.cellHistory.count
            }
            model.tab = "compare"
            try await Task.sleep(nanoseconds:400_000_000)
            guard let window = NSApp.windows.first(where:{$0.isVisible && containsGrid($0.contentView)}) else { throw BridgeError(code:"WORKBOOK_SMOKE_WINDOW",message:"실제 네이티브 통합 문서 그리드 창이 없습니다.") }
            try Smoke.captureView(window,folder.appendingPathComponent("native-workbook-compare.png"))
            checks["actual_native_grid_capture"] = true

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
        if view.identifier?.rawValue == "Docver.workbook.grid" { return true }
        return view.subviews.contains { containsGrid($0) }
    }
}
