import SwiftUI
import AppKit
import UniformTypeIdentifiers
import CoreFoundation

private extension JSON {
    var workbookSheetID: String { self["sheet_id"].string }
    var workbookChangeID: String { self["change_id"].string }
}

enum WorkbookEmptyChangesKind:String {case additionalVersion,singleRead,noChanges}

// A workbook window shares the application's Bridge and exclusive library lock.
// It owns only its read requests; closing it never cancels a document analysis.
@MainActor final class WorkbookModel: ObservableObject {
    let bridge: Bridge
    @Published var projects: [JSON] = []
    @Published var reports: [JSON] = []
    @Published var report = JSON()
    @Published var projectID = "" {didSet {if oldValue != projectID {eventAnchor=nil;pagedEvent=nil;selectionNotice="";cancelInitialSelection()}}}
    @Published var reportID = "" {didSet {if oldValue != reportID {eventAnchor=nil;pagedEvent=nil;selectionNotice="";cancelInitialSelection()}}}
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
    @Published var changesFromID = "" {didSet {if oldValue != changesFromID {eventAnchor=nil;pagedEvent=nil;selectionNotice=""}}}
    @Published var changesToID = "" {didSet {if oldValue != changesToID {eventAnchor=nil;pagedEvent=nil;selectionNotice=""}}}
    @Published var changesMode = "range_net" {didSet {if oldValue != changesMode {eventAnchor=nil;pagedEvent=nil;selectionNotice=""}}}
    @Published private var cellHistoryMessageContent = UIMessage.raw("")
    var cellHistoryMessage: String { get { cellHistoryMessageContent.text } set { cellHistoryMessageContent = .raw(newValue) } }
    @Published var cellHistoryCursor = ""
    @Published var cellHistoryPreviousCursors: [String] = []
    @Published var cellHistoryPageNumber = 1
    private var cellHistoryPageCursor = ""
    private var cellHistoryCursorAnchor: HistoryAnchor?
    @Published var loadingHistory = false
    @Published private var cellHistoryFailureContent = UIMessage.raw("")
    var cellHistoryFailure: String { get { cellHistoryFailureContent.text } set { cellHistoryFailureContent = .raw(newValue) } }
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
    @Published private var statusContent = UIMessage.raw("")
    var status: String { get { statusContent.text } set { statusContent = .raw(newValue) } }
    @Published private var failureContent = UIMessage.raw("")
    var failure: String { get { failureContent.text } set { failureContent = .raw(newValue) } }
    @Published private var recoveryWarnings: [String:UIMessage] = [:]
    private var recoveryWarningRuns: [String:String] = [:]
    var recoveryWarning: String { recoveryWarnings[projectID]?.text ?? "" }
    @Published private var rangeFailureContent = UIMessage.raw("")
    var rangeFailure: String { get { rangeFailureContent.text } set { rangeFailureContent = .raw(newValue) } }
    @Published private var addressFailureContent = UIMessage.raw("")
    var addressFailure: String { get { addressFailureContent.text } set { addressFailureContent = .raw(newValue) } }
    @Published private var changesFailureContent = UIMessage.raw("")
    var changesFailure: String { get { changesFailureContent.text } set { changesFailureContent = .raw(newValue) } }
    @Published private var comparisonNoticeContent = UIMessage.raw("")
    var comparisonNotice: String { get { comparisonNoticeContent.text } set { comparisonNoticeContent = .raw(newValue) } }
    @Published private var selectionNoticeContent = UIMessage.raw("")
    var selectionNotice: String { get { selectionNoticeContent.text } set { selectionNoticeContent = .raw(newValue) } }
    @Published private var blankFormattingWarningScope = ""
    @Published private var cellFailureContent = UIMessage.raw("")
    var cellFailure: String { get { cellFailureContent.text } set { cellFailureContent = .raw(newValue) } }
    @Published private var mcpFailureContent = UIMessage.raw("")
    var mcpFailure: String { get { mcpFailureContent.text } set { mcpFailureContent = .raw(newValue) } }
    @Published var mcp = ""
    @Published var importPresented = false {didSet {if !importPresented {importIntent = .ordinary}}}
    private(set) var importIntent:ImportIntent = .ordinary
    @Published var publishPresented = false
    @Published var addressInput = "A1"
    @Published var inspectorVisible = false
    @Published var diffMode = "source"
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
    private struct EventAnchor {let scope:String;let id:String;let event:Data;let decoded:JSON}
    @Published private var eventAnchor:EventAnchor?
    // Only the exact event retained across an actual same-query page request may
    // outlive the visible list. Manual list edits never mint this authority.
    @Published private var pagedEvent:EventAnchor?
    private struct InitialSelectionIntent:Equatable {let scope:String;let epoch:Int}
    private var initialSelectionIntent:InitialSelectionIntent?
    private var initialNavigationEpoch=0
    private func cancelInitialSelection() {initialNavigationEpoch += 1;initialSelectionIntent=nil}
    private func beginInitialSelection(from:String,to:String) {
        cancelInitialSelection()
        guard !from.isEmpty,!to.isEmpty,from != to else{return}
        initialSelectionIntent=InitialSelectionIntent(scope:[scope,from,to,mode].joined(separator:"|"),epoch:initialNavigationEpoch)
    }

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
    var readingSingleVersion:Bool {beforeID==afterID || revisions.count<2}
    var effectiveDiffMode:String {readingSingleVersion ? "source":diffMode}
    func setDiffMode(_ value:String) {diffMode = readingSingleVersion || value != "text" ? "source":"text"}
    private func enforceSingleSourcePresentation() {if readingSingleVersion {diffMode="source"}}

    var emptyChangesKind:WorkbookEmptyChangesKind {
        if revisions.count<2 {return .additionalVersion}
        if !changesFromID.isEmpty,changesFromID==changesToID {return .singleRead}
        return .noChanges
    }
    var emptyChangesMessage:String {
        switch emptyChangesKind {case .additionalVersion:return L("git.workbookNeedVersions");case .singleRead:return L("git.singleVersionChanges");case .noChanges:return L("workbook.changes.empty")}
    }
    func openNewComparisonImport() {guard ready,!importPresented else{return};importIntent = .newComparison;importPresented=true}
    var showingSheetMetadata:Bool {
        let event=selectedChange,kind=event["kind"].string
        return !event.isNull && selectedRow==0 && beforeAddress.isEmpty && afterAddress.isEmpty && (kind.hasPrefix("sheet_") || ["merges","date_system","calculation_settings"].contains(kind)) && event["before_address"].string.isEmpty && event["after_address"].string.isEmpty && event["from_revision_occurrence_id"].string==beforeID && event["to_revision_occurrence_id"].string==afterID && event["from_sheet_id"].string==beforeSheetID && event["to_sheet_id"].string==afterSheetID
    }
    var selectedSourceWarnings:[String] {
        guard !showingSheetMetadata else{return []}
        return (readingSingleVersion ? [true]:[true,false]).compactMap {before in
            let cell=before ? beforeCell:afterCell,messages=workbookSelectedWarningMessages(cell)
            guard !messages.isEmpty else{return nil}
            let prefix=(readingSingleVersion ? L("doc.common.source")+" · ":before ? L("workbook.pane.beforePrefix"):L("workbook.pane.afterPrefix"))+(before ? beforeAddress:afterAddress)
            return prefix+" · "+messages.joined(separator:" · ")
        }
    }
    func sourceIdentity(before:Bool)->String {
        let occurrence=before ? beforeID:afterID,id=before ? beforeSheetID:afterSheetID,address=before ? beforeAddress:afterAddress,name=sheet(occurrence,id)["name"].string
        let workbookMetadata=["date_system","calculation_settings"].contains(selectedChange["kind"].string)
        let sheetLabel = !name.isEmpty ? name : !id.isEmpty ? L("workbook.sheet.missingIdentity",.verbatim(id)) : workbookMetadata ? L("workbook.sheet.workbookMetadata"):L("workbook.sheet.unmatchedSource")
        return versionLabel(occurrence)+" · "+sheetLabel+(address.isEmpty ? "":" · "+address)
    }
    var missingSourceSheetCaptions:[String] {
        guard !["date_system","calculation_settings"].contains(selectedChange["kind"].string) else{return []}
        return [true,false].compactMap {before in
            let occurrence=before ? beforeID:afterID,id=before ? beforeSheetID:afterSheetID
            guard sheet(occurrence,id).isNull else{return nil}
            return (before ? L("workbook.pane.beforePrefix"):L("workbook.pane.afterPrefix"))+L("workbook.sheet.unmatchedSource")+(id.isEmpty ? "":" · "+id)
        }
    }
    var canOpenCellDetails:Bool {ready && cellHistoryAnchor != nil && (selectedRow>0 || !selectedChange.isNull)}
    func openCellDetails() {guard canOpenCellDetails else{return};inspectorVisible=true}
    var navigationDetail:String {readingSingleVersion ? L("workbook.nav.singleSourceDetail") : independentPaneCoordinates ? L("workbook.nav.independentDetail") : L("workbook.nav.sameAddressDetail")}
    var sourceScopeDescription:String {
        guard !changesFromID.isEmpty,!changesToID.isEmpty,changesFromID != beforeID || changesToID != afterID else{return ""}
        return L(selectedChange.isNull ? "workbook.changes.currentSourceDifference":"workbook.changes.intervalDifference",.verbatim(versionLabel(changesFromID)),.verbatim(versionLabel(changesToID)),.verbatim(versionLabel(beforeID)),.verbatim(versionLabel(afterID)))
    }
    var scope: String { projectID + "|" + reportID }
    var rangeScope: String { [scope,beforeID,afterID,beforeSheetID,afterSheetID,String(beforeRowStart),String(beforeColumnStart),String(afterRowStart),String(afterColumnStart)].joined(separator:"|") }
    var comparisonScope: String { [scope,changesFromID,changesToID,changesMode].joined(separator:"|") }
    var changeListProvenance:String {
        if changesFromID==changesToID {return L("git.reading")}
        if changesMode=="history" {return L("git.documentStoredHistory")}
        if let a=revisions.firstIndex(where:{$0["revision_occurrence_id"].string==changesFromID}),let b=revisions.firstIndex(where:{$0["revision_occurrence_id"].string==changesToID}),b==a+1 {return L("git.documentStoredAdjacent")}
        return L("git.workbookComputedNet")
    }
    var blankFormattingWarning: String {
        guard ready,!loadingChanges,changesFailure.isEmpty,blankFormattingWarningScope == comparisonScope else { return "" }
        return L("workbook.warning.blankFormatting")
    }
    var independentPaneCoordinates: Bool { beforeRowStart != afterRowStart || beforeColumnStart != afterColumnStart || beforeAddress != afterAddress }
    var navigationRangePrefix: String {
        let differentRanges = beforeRowStart != afterRowStart || beforeColumnStart != afterColumnStart
        return differentRanges && paneCoordinate(before:false) != nil && rowStart == afterRowStart && columnStart == afterColumnStart ? L("workbook.nav.afterPrefix") : ""
    }
    var ready: Bool { active && !reportID.isEmpty && report["report_id"].string == reportID && !loadingReport && !busy && !loadingDemo }
    var project: JSON { projects.first { $0["project_id"].string == projectID } ?? JSON() }
    private func retainedEvent(_ id:String)->JSON {
        guard let retained=pagedEvent,retained.scope==comparisonScope,retained.id==id,eventBelongsToQuery(retained.decoded) else{return JSON()}
        return retained.decoded
    }
    var selectedChange: JSON {
        guard !selectedChangeID.isEmpty else{return JSON()}
        if let event=changes.first(where:{$0["change_id"].string==selectedChangeID}) {return eventBelongsToQuery(event) ? event:JSON()}
        let event=retainedEvent(selectedChangeID)
        guard event["from_revision_occurrence_id"].string==beforeID,event["to_revision_occurrence_id"].string==afterID,event["from_sheet_id"].string==beforeSheetID,event["to_sheet_id"].string==afterSheetID,event["before_address"].string==beforeAddress,event["after_address"].string==afterAddress else{return JSON()}
        return event
    }
    private var anchoredChange:JSON {
        guard let anchor=eventAnchor,anchor.scope==comparisonScope else{return JSON()}
        let event=changes.first(where:{$0["change_id"].string==anchor.id}) ?? retainedEvent(anchor.id)
        guard !event.isNull,eventBelongsToQuery(event),(try? event.data())==anchor.event else{return JSON()}
        return event
    }
    private func eventBelongsToQuery(_ event:JSON)->Bool {
        guard !event["change_id"].string.isEmpty,["history","range_net"].contains(changesMode),
              let lower=revisions.firstIndex(where:{$0["revision_occurrence_id"].string==changesFromID}),
              let upper=revisions.firstIndex(where:{$0["revision_occurrence_id"].string==changesToID}),
              let a=revisions.firstIndex(where:{$0["revision_occurrence_id"].string==event["from_revision_occurrence_id"].string}),
              let b=revisions.firstIndex(where:{$0["revision_occurrence_id"].string==event["to_revision_occurrence_id"].string}),
              lower<=a,a<b,b<=upper else{return false}
        if changesMode=="range_net",a != lower || b != upper {return false}
        let kind=event["kind"].string,metadata=kind.hasPrefix("sheet_") || ["merges","date_system","calculation_settings"].contains(kind)
        guard metadata || !event["before_address"].string.isEmpty || !event["after_address"].string.isEmpty else{return false}
        return [true,false].allSatisfy {before in
            let occurrence=event[before ? "from_revision_occurrence_id":"to_revision_occurrence_id"].string,sheetID=event[before ? "from_sheet_id":"to_sheet_id"].string,address=event[before ? "before_address":"after_address"].string
            // Metadata and an unmaterialized cell side can have no coordinate
            // or sheet. A physical coordinate must belong to its occurrence.
            return address.isEmpty || (WorkbookGrid.parseAddress(address) != nil && !sheetID.isEmpty && !sheet(occurrence,sheetID).isNull)
        }
    }
    private func eligibleInitialChange(_ event:JSON)->Bool {
        let kind=event["kind"].string
        return !kind.hasPrefix("sheet_") && !["merges","date_system","calculation_settings"].contains(kind) && eventBelongsToQuery(event) && (!event["before_address"].string.isEmpty || !event["after_address"].string.isEmpty)
    }
    var canReturnToChange:Bool {ready && selectedChangeID.isEmpty && !loadingChanges && !anchoredChange.isNull}
    func returnToChange() async {
        guard canReturnToChange else {
            if anchoredChange.isNull {selectedChangeID="";eventAnchor=nil;pagedEvent=nil}
            return
        }
        let id=anchoredChange["change_id"].string
        await chooseChange(id)
    }
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
        return r.isNull ? L("workbook.selection.none") : versionDisplayName(r["index"].int,r)
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
        eventAnchor=nil;pagedEvent=nil;selectionNotice="";cancelInitialSelection()
        for channel in Array(owners.keys) { invalidate(channel) }
        loadingReport = false; loadingRange = false; loadingChanges = false; loadingCell = false; loadingHistory = false; loadingMCP = false
        mcp = ""; mcpScope = ""; mcpFailure = ""; blankFormattingWarningScope = ""
    }
    func closeReads() {
        active = false; invalidateReads(); loadingReport = false; loadingDemo = false; clearCells()
        if canCancelAnalysis { cancelAnalysis() }
    }
    func clearCells() {
        invalidate("range"); invalidate("cell"); invalidate("history")
        beforeCells = []; afterCells = []; beforeCell = JSON(); afterCell = JSON(); resetCellHistory()
        selectedRow = 0; selectedColumn = 0; selectedChangeID = ""; beforeAddress = ""; afterAddress = ""; cellTextOffset = 0; cellTextNext = nil
        rangeFailure = ""; addressFailure = ""; cellFailure = ""; selectionNotice = ""; loadingRange = false; loadingCell = false
    }
    func clearSelection() {
        eventAnchor=nil;pagedEvent=nil;cancelInitialSelection()
        clearCells(); changes = []; coverage = []; releases = []; resetChangePaging(); changeTotal = 0
        changesFailure = ""; comparisonNotice = ""; blankFormattingWarningScope = ""; changesFromID = ""; changesToID = ""; loadingChanges = false; report = JSON(); reportID = ""
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
            failureContent = bridgeErrorMessage(error)
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
            else { statusContent = UIMessage("workbook.status.noReport") }
        } catch {
            guard current(ticket), projectID == id else { return }
            loadingReport = false; failureContent = bridgeErrorMessage(error)
        }
    }
    func selectReport(_ id: String) async {
        guard active, !busy, !loadingDemo else { return }
        invalidateReads(); clearSelection(); reportID = id
        let project = projectID, ticket = begin("view"); loadingReport = true; failure = ""
        do {
            let value = try await bridge.call("workbookView",["project_id":project,"report_id":id],owner:ticket.owner)
            guard current(ticket), projectID == project, reportID == id else { return }
            guard value["project_id"].string == project, value["report_id"].string == id else { throw BridgeError(code:"WORKBOOK_SCOPE",message:UIMessage("workbook.error.reportScope")) }
            report = value; loadingReport = false
            beforeID = revisions.indices.contains(max(0,revisions.count-2)) ? revisions[max(0,revisions.count-2)]["revision_occurrence_id"].string : ""
            afterID = revisions.last?["revision_occurrence_id"].string ?? ""
            selectInitialSheets();beginInitialSelection(from:beforeID,to:afterID)
            coverage = value["coverage_gaps"].array
            await loadRange()
            guard current(ticket), projectID == project, reportID == id, active else { return }
            await loadChanges()
            guard current(ticket), projectID == project, reportID == id, active else { return }
            await loadReleases()
        } catch {
            guard current(ticket), projectID == project, reportID == id else { return }
            report = JSON(); loadingReport = false; failureContent = bridgeErrorMessage(error)
        }
    }
    func selectInitialSheets() {
        let left = sheets(beforeID), right = sheets(afterID)
        beforeSheetID = left.first?["sheet_id"].string ?? ""
        let name = left.first?["name"].string ?? ""
        let sameName = right.filter { $0["name"].string == name }
        afterSheetID = (sameName.count == 1 ? sameName.first : right.first)?["sheet_id"].string ?? ""
    }
    func selectVersion(_ occurrence:String) async {
        guard let index=revisions.firstIndex(where:{$0["revision_occurrence_id"].string==occurrence}) else{return}
        await changeVersions(before:revisions[max(0,index-1)]["revision_occurrence_id"].string,after:occurrence)
    }
    func changeVersions(before: String? = nil, after: String? = nil) async {
        guard ready else { return }
        revealGeneration += 1
        var left = before ?? (changesFromID.isEmpty ? beforeID:changesFromID),right = after ?? (changesToID.isEmpty ? afterID:changesToID)
        guard let leftIndex = revisions.firstIndex(where:{$0["revision_occurrence_id"].string == left}),let rightIndex = revisions.firstIndex(where:{$0["revision_occurrence_id"].string == right}) else { return }
        if leftIndex > rightIndex { swap(&left,&right); statusContent = UIMessage("workbook.status.sortedVersions") }
        eventAnchor=nil;cancelInitialSelection();clearCells(); invalidate("changes")
        beforeID = left; afterID = right;enforceSingleSourcePresentation(); comparisonNotice = ""; blankFormattingWarningScope = ""
        changes = []; resetChangePaging(); changeTotal = 0
        rowStart = 1; columnStart = 1; addressInput = "A1"; selectInitialSheets();beginInitialSelection(from:beforeID,to:afterID)
        let identity = rangeScope
        await loadRange()
        guard rangeScope == identity, ready else { return }; await loadChanges()
    }
    func changeSheet(before: String? = nil, after: String? = nil) async {
        guard ready else { return }; cancelInitialSelection();clearCells()
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
        guard value["project_id"].string == project,value["report_id"].string == snapshot,value["revision_occurrence_id"].string == occurrence,value["sheet_id"].string == sheet,cells.count <= rowLimit*columnLimit,cells.allSatisfy({$0["row"].int >= row && $0["row"].int < row+rowLimit && $0["column"].int >= column && $0["column"].int < column+columnLimit}) else { throw BridgeError(code:"WORKBOOK_RANGE_SCOPE",message:UIMessage("workbook.error.rangeScope")) }
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
            beforeCells = []; afterCells = []; loadingRange = false; rangeFailureContent = bridgeErrorMessage(error)
        }
    }
    func loadChanges(next: Bool = false,previous: Bool = false,preserveEndpoints: Bool = false,autoSelectInitial:Bool=true) async {
        let previousScope=comparisonScope,previousAnchor=eventAnchor,retained=anchoredChange
        guard ready, !beforeID.isEmpty, !afterID.isEmpty else { return }
        guard !(next && previous),!next || !changeCursor.isEmpty,!previous || !changePreviousCursors.isEmpty else { return }
        selectionNotice = ""
        if !autoSelectInitial || next || previous {cancelInitialSelection()}
        if beforeID==afterID, !preserveEndpoints {
            enforceSingleSourcePresentation()
            invalidate("changes");changes=[];selectedChangeID="";eventAnchor=nil;pagedEvent=nil;resetChangePaging();changeTotal=0;changesFailure="";loadingChanges=false
            changesFromID=beforeID;changesToID=afterID;changesMode=mode;return
        }
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
        // Only the explicit report/version action owns this one-shot intent.
        // Manual navigation may revoke it while this scoped list request waits.
        let initialIntent=initialSelectionIntent.flatMap{$0.scope==identity ? $0:nil}
        if identity==previousScope,!retained.isNull,let anchor=previousAnchor {
            pagedEvent=anchor
        } else {
            eventAnchor=nil;pagedEvent=nil;selectedChangeID=""
        }
        loadingChanges = true; changesFailure = ""; blankFormattingWarningScope = ""
        var args: [String:Any] = ["from_revision_occurrence_id":changesFromID,"to_revision_occurrence_id":changesToID,"mode":changesMode,"limit":100,"max_output_tokens":pagingOutputBudget,"text_length":128]
        if !targetCursor.isEmpty { args["cursor"] = targetCursor }
        do {
            let value = try await query("list_workbook_changes",args,ticket:ticket)
            guard current(ticket), comparisonScope == identity else { return }
            guard value["project_id"].string == projectID,value["report_id"].string == reportID,value["from_revision_occurrence_id"].string == changesFromID,value["to_revision_occurrence_id"].string == changesToID,value["mode"].string == changesMode else { throw BridgeError(code:"WORKBOOK_CHANGES_SCOPE",message:UIMessage("workbook.error.changesScope")) }
            if value["blank_formatting_comparison"].string == "unsupported_across_formats" { blankFormattingWarningScope = identity }
            changes = value["items"].array; changeCursor = value["next_cursor"].string
            changePageCursor = targetCursor; changePreviousCursors = back; changePageNumber = targetPage
            changeTotal = value["total"].int; loadingChanges = false
            if let anchor=eventAnchor,let returned=changes.first(where:{$0["change_id"].string==anchor.id}),(try? returned.data()) != anchor.event {
                // A changed event payload cannot relabel already-mounted raw cells.
                eventAnchor=nil;pagedEvent=nil;selectedChangeID=""
            }
            if let intent=initialIntent,initialSelectionIntent==intent {
                cancelInitialSelection()
                if selectedChangeID.isEmpty,let first=changes.first(where:eligibleInitialChange) {
                    await chooseChange(first["change_id"].string,preservingVisibleWindow:true)
                }
            }
        } catch {
            guard current(ticket), comparisonScope == identity else { return }
            if changesMode == "range_net",(error as? BridgeError)?.code == "WORKBOOK_DIFF_LIMIT" {
                loadingChanges = false; mode = "history"
                comparisonNoticeContent = UIMessage("workbook.warning.historyFallback")
                await loadChanges(preserveEndpoints:true,autoSelectInitial:false); return
            }
            loadingChanges = false; changesFailureContent = bridgeErrorMessage(error)
        }
    }
    func changeMode(_ value: String) async {
        guard ready,["range_net","history"].contains(value) else { return }
        // Evidence navigation may show an adjacent pair inside a wider interval.
        // Changing the comparison method does not constitute a new version pick.
        let preserve = revisions.contains(where:{$0["revision_occurrence_id"].string == changesFromID}) && revisions.contains(where:{$0["revision_occurrence_id"].string == changesToID})
        mode = value; comparisonNotice = ""; await loadChanges(preserveEndpoints:preserve,autoSelectInitial:false)
    }
    func moveWindow(rows: Int = 0, columns: Int = 0) async {
        guard ready else { return }
        cancelInitialSelection()
        revealGeneration += 1
        rowStart = min(1_048_576-rowLimit+1,max(1,rowStart+rows))
        columnStart = min(16_384-columnLimit+1,max(1,columnStart+columns))
        clearCells(); addressInput = WorkbookGrid.address(rowStart,columnStart); await loadRange()
    }
    func goToAddress() async {
        guard ready else { return }
        guard let (row,column) = WorkbookGrid.parseAddress(addressInput) else { addressFailureContent = UIMessage("workbook.error.address"); return }
        cancelInitialSelection()
        rowStart = max(1,min(row,1_048_576-rowLimit+1)); columnStart = max(1,min(column,16_384-columnLimit+1))
        clearCells(); addressInput = WorkbookGrid.address(row,column); let identity = rangeScope
        await loadRange(); guard ready, rangeScope == identity else { return }; await selectCell(row,column)
    }
    func selectCell(_ row: Int, _ column: Int) async {
        guard ready else { return }
        cancelInitialSelection()
        addressFailure = ""; selectionNotice = ""
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
            if beforeID==afterID,beforeSheetID==afterSheetID,oldAddress==newAddress {b=a}
            else if !afterSheetID.isEmpty,let (row,column) = WorkbookGrid.parseAddress(newAddress) {
                let value = try await query("get_workbook_cell",["revision_occurrence_id":afterID,"sheet_id":afterSheetID,"row":row,"column":column,"text_offset":offset,"text_length":1024,"max_output_tokens":8000],ticket:ticket)
                guard current(ticket), rangeScope == identity, beforeAddress == oldAddress, afterAddress == newAddress else { return }
                b = try scopedCellResult(value,occurrence:afterID,sheet:afterSheetID,address:newAddress)
            }
            guard current(ticket), rangeScope == identity, beforeAddress == oldAddress, afterAddress == newAddress else { return }
            beforeCell = a; afterCell = b; loadingCell = false
            cellTextNext = [a,b].flatMap { cell in ["value","formula","number_format"].compactMap { key -> Int? in let cursor = cell["text_continuations"][key]["next_offset"]; return cursor.isNull ? nil : cursor.int } }.filter { $0 > offset }.min()
        } catch {
            guard current(ticket), rangeScope == identity, beforeAddress == oldAddress, afterAddress == newAddress else { return }
            beforeCell = JSON(); afterCell = JSON(); loadingCell = false; cellFailureContent = bridgeErrorMessage(error)
        }
    }
    private func scopedCellResult(_ value: JSON,occurrence: String,sheet: String,address: String) throws -> JSON {
        let items = value["items"].array
        guard value["project_id"].string == projectID,value["report_id"].string == reportID,value["revision_occurrence_id"].string == occurrence,value["sheet_id"].string == sheet,value["items"].raw is [Any] else {
            throw BridgeError(code:"WORKBOOK_CELL_SCOPE",message:UIMessage("workbook.error.cellScope"))
        }
        if value["availability"].string == "not_materialized",items.isEmpty { return JSON() }
        guard value["availability"].string == "available",items.count == 1,let (row,column) = WorkbookGrid.parseAddress(address),items[0]["address"].string == address,items[0]["row"].number == Double(row),items[0]["column"].number == Double(column) else {
            throw BridgeError(code:"WORKBOOK_CELL_SCOPE",message:UIMessage("workbook.error.cellScope"))
        }
        return items[0]
    }
    func chooseChange(_ id: String,preservingVisibleWindow:Bool=false) async {
        guard ready else{return}
        let visible=changes.first(where:{$0["change_id"].string==id}),change=visible ?? retainedEvent(id)
        guard !change.isNull,eventBelongsToQuery(change) else {
            selectedChangeID="";eventAnchor=nil;pagedEvent=nil;cancelInitialSelection()
            selectionNoticeContent = UIMessage("workbook.warning.unverifiedSelection");return
        }
        selectionNotice = ""
        cancelInitialSelection()
        if visible != nil {pagedEvent=nil}
        let oldBefore=(beforeID,beforeSheetID,beforeRowStart,beforeColumnStart),oldAfter=(afterID,afterSheetID,afterRowStart,afterColumnStart)
        addressFailure = ""
        revealGeneration += 1
        invalidate("cell"); resetCellHistory(); beforeCell = JSON(); afterCell = JSON(); cellFailure = ""; loadingCell = true
        let a = change["from_revision_occurrence_id"].string, b = change["to_revision_occurrence_id"].string
        beforeID = a; afterID = b
        beforeSheetID = change["from_sheet_id"].string; afterSheetID = change["to_sheet_id"].string
        let address = change["after_address"].string.isEmpty ? change["before_address"].string : change["after_address"].string
        if let (row,column) = WorkbookGrid.parseAddress(address) {
            rowStart = min(row,1_048_576-rowLimit+1); columnStart = min(column,16_384-columnLimit+1)
            selectedRow = row; selectedColumn = column; addressInput = address
        } else { selectedRow = 0; selectedColumn = 0 }
        if let bytes=try? change.data(),let decoded=try? JSONSerialization.jsonObject(with:bytes) {
            eventAnchor=EventAnchor(scope:comparisonScope,id:id,event:bytes,decoded:JSON(decoded))
        } else {eventAnchor=nil}
        selectedChangeID = id; beforeAddress = change["before_address"].string; afterAddress = change["after_address"].string
        func window(_ coordinate:(row:Int,column:Int),_ old:(String,String,Int,Int),_ occurrence:String,_ sheet:String)->(Int,Int) {
            let retain=preservingVisibleWindow && old.0==occurrence && old.1==sheet && coordinate.row>=old.2 && coordinate.row<old.2+rowLimit && coordinate.column>=old.3 && coordinate.column<old.3+columnLimit
            return retain ? (old.2,old.3):(min(coordinate.row,1_048_576-rowLimit+1),min(coordinate.column,16_384-columnLimit+1))
        }
        let aCoordinate=paneCoordinate(before:true),bCoordinate=paneCoordinate(before:false)
        let aWindow=aCoordinate.map{window($0,oldBefore,beforeID,beforeSheetID)} ?? (preservingVisibleWindow ? (oldBefore.2,oldBefore.3):(beforeRowStart,beforeColumnStart))
        let bWindow=bCoordinate.map{window($0,oldAfter,afterID,afterSheetID)} ?? (preservingVisibleWindow ? (oldAfter.2,oldAfter.3):(afterRowStart,afterColumnStart))
        if preservingVisibleWindow {
            let shared=bCoordinate != nil ? bWindow:aCoordinate != nil ? aWindow:bWindow
            rowStart=shared.0;columnStart=shared.1
        }
        (beforeRowStart,beforeColumnStart)=aWindow;(afterRowStart,afterColumnStart)=bWindow
        beforeCell = JSON(); afterCell = JSON(); cellTextOffset = 0; cellTextNext = nil
        await loadRange()
        if currentChangeIs(id) { await loadSelectedCells() }
    }
    private func currentChangeIs(_ id: String) -> Bool { ready && selectedChangeID == id && !selectedChange.isNull }
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
            cellHistoryMessageContent = cellHistory.isEmpty ? UIMessage("workbook.history.empty") : UIMessage("workbook.history.pageSummary",.count(cellHistory.count),.count(cellHistoryTotal))
        } catch {
            guard current(ticket), rangeScope == identity, cellHistoryAnchor == anchor else { return }
            loadingHistory = false; cellHistoryFailureContent = bridgeErrorMessage(error)
        }
    }
    func loadReleases() async {
        guard ready else { return }; let ticket = begin("releases"), identity = scope
        do {
            let value = try await bridge.call("workbookReleases",["project_id":projectID],owner:ticket.owner)
            guard current(ticket), scope == identity else { return }
            releases = value.raw is [Any] ? value.array : value["items"].array
        } catch { guard current(ticket), scope == identity else { return }; failureContent = bridgeErrorMessage(error) }
    }
    private func noteRecovery(_ message: UIMessage,project: String,run: String) { recoveryWarningRuns[project] = run; recoveryWarnings[project] = message }
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
        invalidateReads(); busy = true; cancelRequested = false; failure = ""; statusContent = UIMessage("workbook.status.analyzing")
        do {
            let staged = try await bridge.call("workbookAnalyze",["project_id":project],analysis:true,analysisOwner:token,holdAnalysis:true)
            stagedRunID = staged["analysis_run_id"].string
            guard active, !cancelRequested, projectID == project else { throw CancellationError() }
            committing = true; commitAttempted = true; statusContent = UIMessage("workbook.status.saving")
            let committed = try await bridge.call("workbookCommit",["project_id":project,"result":staged.raw])
            if committed["cleanup_pending"].bool { noteRecovery(UIMessage("workbook.warning.cleanupPending"),project:project,run:stagedRunID) }
            else { clearRecovery(project:project,run:stagedRunID) }
            stagedRunID = ""
            bridge.releaseAnalysis(owner:token)
            guard projectID == project else { throw CancellationError() }
            analysisToken = nil; committing = false; busy = false; statusContent = UIMessage("workbook.status.complete")
            let completion = begin("analysis-completion")
            await refreshProjects()
            guard active, current(completion), projectID == project else { return }
            await selectProject(project,snapshot:committed["report_id"].string)
            if active,projectID == project,reportID == committed["report_id"].string { statusContent = UIMessage("workbook.status.complete") }
        } catch {
            var recoveryReport = "",cleanupFailure = UIMessage.raw(""),saveUncertain = false
            if !stagedRunID.isEmpty {
                // A lost commit reply does not establish a failed commit. Check
                // this exact owned run before considering its staged-file cleanup.
                committing = true; statusContent = UIMessage("workbook.status.checkingSave")
                do {
                    let run = try await bridge.call("workbookRunStatus",["project_id":project,"analysis_run_id":stagedRunID])
                    guard run["project_id"].string == project,run["analysis_run_id"].string == stagedRunID else { throw BridgeError(code:"WORKBOOK_RUN_SCOPE",message:UIMessage("workbook.error.runScope")) }
                    if run["status"].string == "success",!run["report_id"].string.isEmpty {
                        recoveryReport = run["report_id"].string; clearRecovery(project:project,run:stagedRunID)
                    } else if run["status"].string == "staged" {
                        statusContent = UIMessage("workbook.status.cleaning")
                        do { _ = try await bridge.call("workbookDiscard",["project_id":project,"analysis_run_id":stagedRunID]); clearRecovery(project:project,run:stagedRunID) }
                        catch { cleanupFailure = UIMessage("workbook.error.cleanupDetail",.message(bridgeErrorMessage(error))) }
                    } else if run["status"].string != "failed" {
                        saveUncertain = commitAttempted; cleanupFailure = UIMessage("workbook.warning.saveCleanup")
                    }
                } catch {
                    saveUncertain = commitAttempted
                    cleanupFailure = saveUncertain ? UIMessage("workbook.error.saveDetail",.message(bridgeErrorMessage(error))) : UIMessage("workbook.error.stagedDetail",.message(bridgeErrorMessage(error)))
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
                if active,projectID == project,reportID == recoveryReport { statusContent = ready ? UIMessage("workbook.status.reopened") : UIMessage("workbook.status.savedReload") }
                return
            }
            let cancelled = cancelRequested || error is CancellationError || (error as? BridgeError)?.code == "CANCELLED"
            let outcome = saveUncertain ? UIMessage("workbook.status.saveUncertain") : cancelled ? UIMessage("workbook.status.cancelled") : UIMessage("workbook.status.failed")
            let message = bridgeErrorMessage(error)
            if active, projectID == project, !oldReport.isEmpty { await selectProject(project,snapshot:oldReport) }
            guard projectID == project else { return }
            failureContent = cancelled || saveUncertain ? .raw("") : message
            statusContent = outcome
        }
    }
    func cancelAnalysis() { guard canCancelAnalysis,let token = analysisToken else { return }; cancelRequested = true; statusContent = UIMessage("workbook.status.cancelling"); bridge.cancel(owner:token) }
    func create(title: String, rows: [WorkbookImportRow], intent:ImportIntent = .ordinary) async throws {
        try intent.validateVersionEntries(rows.count)
        guard active, !busy, !loadingDemo else { throw BridgeError(code:"WORKBOOK_BUSY",message:UIMessage("workbook.error.busy")) }
        let retainedProject = projectID, retainedReport = reportID, retainedRange = rangeScope
        let interruptedReport = loadingReport || report.isNull
        let interruptedRange = loadingRange, interruptedChanges = loadingChanges, interruptedCell = loadingCell, interruptedHistory = loadingHistory
        let restoreMCP = loadingMCP || !mcp.isEmpty, retainedOffset = cellTextOffset
        busy = true; failure = ""; invalidateReads()
        let completion = begin("create-completion")
        func retained() -> Bool { active && current(completion) && projectID == retainedProject && reportID == retainedReport && rangeScope == retainedRange }
        do {
            let value = try await bridge.call("workbookCreate",["title":title,"revisions":rows.map { ["label":$0.label,"path":$0.url.path,"expected_sha256":$0.identity.sha256] }])
            busy = false
            guard retained() else { return }; importPresented = false
            let project = value["project_id"].string
            await refreshProjects()
            guard retained() else { return }
            await selectProject(project)
            guard active, projectID == project else { return }; await run()
        } catch {
            busy = false
            if retained(), !retainedProject.isEmpty {
                if interruptedReport {
                    await selectProject(retainedProject,snapshot:retainedReport)
                } else {
                    // Cancellation is not an empty observation. Retry the reads
                    // owned by the retained view, stopping at any newer scope.
                    if interruptedRange || beforeCells.isEmpty || afterCells.isEmpty { await loadRange() }
                    if retained(), interruptedChanges || changesFromID.isEmpty { await loadChanges(preserveEndpoints:!changesFromID.isEmpty && !changesToID.isEmpty) }
                    if retained(), interruptedCell { await loadSelectedCells(offset:retainedOffset) }
                    if retained(), interruptedHistory { await loadCellHistory() }
                    if retained(), restoreMCP { await loadMCP() }
                    if retained() { await loadReleases() }
                }
            }
            throw error
        }
    }
    func useDemo() async {
        guard active, !busy, !loadingDemo, !loadingReport else { return }
        let ticket = begin("demo"), identity = scope, resources = bridge.resources
        loadingDemo = true; failure = ""; statusContent = UIMessage("workbook.status.checkingDemo")
        defer { if current(ticket) { loadingDemo = false } }
        do {
            let demo = try await Task.detached(priority:.userInitiated) { try WorkbookImportRow.bundledDemo(resources:resources) }.value
            guard active, current(ticket), scope == identity else { return }
            loadingDemo = false
            do { try await create(title:demo.title,rows:demo.rows) }
            catch { if active,scope == identity { failureContent = bridgeErrorMessage(error); statusContent = UIMessage("workbook.status.demoFailed") } }
        } catch {
            guard active, current(ticket), scope == identity else { return }
            failureContent = bridgeErrorMessage(error); statusContent = UIMessage("workbook.status.demoFailed")
        }
    }
    func publish(label: String, reason: String) async throws {
        guard ready else { throw BridgeError(code:"WORKBOOK_NOT_READY",message:UIMessage("workbook.error.notReady")) }
        let project = projectID, snapshot = reportID; busy = true
        do {
            _ = try await bridge.call("workbookPublish",["project_id":project,"report_id":snapshot,"label":label,"reason":reason])
            guard projectID == project, reportID == snapshot else { busy = false; return }
            busy = false; publishPresented = false; statusContent = UIMessage("workbook.status.published"); await loadReleases()
        } catch { busy = false; throw error }
    }
    func export() async {
        guard ready else { return }
        let language = LanguagePreferences.shared.effectiveLanguage
        let panel = NSOpenPanel(); panel.canChooseFiles = false; panel.canChooseDirectories = true; panel.canCreateDirectories = true
        panel.prompt = L("workbook.action.export"); panel.message = L("workbook.export.folderPrompt")
        guard panel.runModal() == .OK, let folder = panel.url else { return }
        let project = projectID, snapshot = reportID; busy = true; failure = ""
        do {
            _ = try await bridge.call("workbookExport",["project_id":project,"report_id":snapshot,"folder":folder.path,"language":language])
            guard projectID == project, reportID == snapshot else { busy = false; return }
            busy = false; statusContent = UIMessage("workbook.status.exported",.verbatim(folder.path))
        } catch { busy = false; if projectID == project, reportID == snapshot { failureContent = bridgeErrorMessage(error) } }
    }
    func loadMCP() async {
        guard ready else { return }
        let ticket = begin("mcp"), identity = scope; loadingMCP = true; mcp = ""; mcpScope = ""; mcpFailure = ""
        do {
            let value = try await bridge.call("workbookMcpConfig",["project_id":projectID,"report_id":reportID],owner:ticket.owner)
            guard current(ticket), ready, scope == identity else { return }
            mcp = value["config"].string.isEmpty ? value.string : value["config"].string
            if mcp.isEmpty, !value.dictionary.isEmpty { mcp = String(decoding:try value.data(),as:UTF8.self) }
            guard !mcp.isEmpty else { throw BridgeError(code:"WORKBOOK_MCP_EMPTY",message:UIMessage("workbook.error.mcpEmpty")) }
            mcpScope = identity; loadingMCP = false
        } catch { guard current(ticket), scope == identity else { return }; mcp = ""; mcpScope = ""; loadingMCP = false; mcpFailureContent = bridgeErrorMessage(error) }
    }
    var canCopyMCP: Bool { ready && !mcp.isEmpty && mcpScope == scope && !loadingMCP }
    func copyMCP() { guard canCopyMCP else { return }; NSPasteboard.general.clearContents(); NSPasteboard.general.setString(mcp,forType:.string) }
}

struct WorkbookWorkspace: View {
    @State private var language = LanguagePreferences.shared
    @StateObject var model: WorkbookModel
    @StateObject private var layout=WorkspaceLayoutStore(scope:.workbook)
    init(bridge: Bridge) { _model = StateObject(wrappedValue:WorkbookModel(bridge:bridge)) }
    init(model:WorkbookModel) { _model = StateObject(wrappedValue:model) }
    var body: some View {
        VStack(spacing:0) {
            WorkspacePaneSplit(name:"workbook.projects",auxiliaryFirst:true,auxiliaryVisible:layout.configuration.sidebarVisible,extent:.points(layout.configuration.sidebarWidth),primaryMinimum:760,auxiliaryMinimum:180,onResize:{value in if case .points(let width)=value {layout.update{$0.sidebarWidth=min(380,max(180,width))}}}) {
                WorkspacePaneSplit(name:"workbook.inspector",auxiliaryFirst:layout.configuration.inspectorDock == .left,auxiliaryVisible:layout.configuration.inspectorVisible && !model.report.isNull,extent:.points(layout.configuration.inspectorWidth),primaryMinimum:layout.configuration.changesVisible && layout.configuration.changesDock != .bottom ? 500:300,auxiliaryMinimum:260,onResize:{value in if case .points(let width)=value {layout.update{$0.inspectorWidth=min(480,max(260,width))}}}) {
                    VStack(spacing:0) {
                        reportBar
                        if model.loadingReport { WorkbookStatus(title:L("workbook.status.loadingReport"),detail:L("workbook.status.loadingReportDetail"),loading:true) }
                        else if model.report.isNull { emptyWorkspace }
                        else { comparison }
                    }.frame(maxWidth:.infinity,maxHeight:.infinity)
                } auxiliary:{WorkbookInspector(model:model)}
            } auxiliary:{sidebar}
            Divider()
            HStack(spacing:8) {
                if model.busy || model.loadingDemo { ProgressView().controlSize(.small) }
                Text(verbatim:model.status.isEmpty ? L("workbook.status.readOnlyDetail") : model.status).lineLimit(2)
                Spacer(); Text(L("workbook.status.readOnly"))
            }.readableFont(.caption).foregroundStyle(.secondary).padding(.horizontal,12).padding(.vertical,6)
        }.frame(minWidth:1180,minHeight:760).background(Color(nsColor:.windowBackgroundColor)).preferredColorScheme(.light)
        .toolbar {
            ToolbarItem { Menu {ForEach(model.projects,id:\.id){project in Button(project["title"].string){Task{await model.selectProject(project["project_id"].string)}}};Divider();Button(L("git.manageVersions")){layout.update{$0.sidebarVisible=true}}} label:{Label(model.project["title"].string.isEmpty ? L("workbook.window.title"):model.project["title"].string,systemImage:"folder")}.disabled(model.busy || model.loadingReport) }
            ToolbarItem { WorkspaceLayoutMenu(layout:layout) }
            ToolbarItemGroup(placement:.primaryAction) {
                Button { model.importPresented = true } label: { Label(L("workbook.action.importVersions"),systemImage:"plus") }.disabled(model.busy || model.loadingDemo)
                Menu {
                    Button(L("workbook.action.demo")){Task{await model.useDemo()}}
                    Button(L("workbook.action.reanalyze")){Task{await model.run()}}.disabled(!model.ready)
                    Button(L("workbook.action.exportReport")){Task{await model.export()}}.disabled(!model.ready)
                    Button(L("git.aiTools")){model.tab="ai"}
                    Button(L("workbook.action.pinRelease")){model.publishPresented=true}.disabled(!model.ready)
                } label:{Label(L("git.actions"),systemImage:"ellipsis.circle")}
            }
        }
        .focusedSceneObject(layout)
        .onChange(of:model.inspectorVisible){layout.update{$0.inspectorVisible=model.inspectorVisible}}
        .onChange(of:layout.configuration.inspectorVisible){model.inspectorVisible=layout.configuration.inspectorVisible}
        .sheet(isPresented:Binding(get:{model.tab=="ai"},set:{if !$0{model.tab="compare"}})){NativeDetailSheet(title:L("git.aiTools")){aiAndReleases}}
        .sheet(isPresented:$model.importPresented) { WorkbookImportSheet(model:model,intent:model.importIntent) }
        .sheet(isPresented:$model.publishPresented) { WorkbookPublishSheet(model:model) }
        .task { model.inspectorVisible=layout.configuration.inspectorVisible;await model.start(); await WorkbookNativeSmoke.runIfRequested(model,layout:layout) }
        .onDisappear { model.closeReads() }
    }
    private var sidebar: some View {
        VStack(alignment:.leading,spacing:10) {
            HStack { Text(L("workbook.sidebar.title")).readableFont(.headline); Spacer(); Button { Task { await model.refreshProjects() } } label: { Image(systemName:"arrow.clockwise") }.disabled(model.busy) }
            List(selection:Binding<String?>(get:{model.projectID.isEmpty ? nil : model.projectID},set:{if let id = $0 { Task { await model.selectProject(id) } }})) {
                ForEach(model.projects,id:\.id) { project in
                    VStack(alignment:.leading,spacing:3) { Text(verbatim:project["title"].string).lineLimit(2); Text(LC("workbook.count.versions",project["revision_count"].int)).readableFont(.caption).foregroundStyle(.secondary) }.tag(project["project_id"].string)
                }
            }.disabled(model.busy || model.loadingDemo).frame(minHeight:130,maxHeight:260)
            Button { model.importPresented = true } label: { Label(L("workbook.action.importFormats"),systemImage:"plus.circle") }.disabled(model.busy || model.loadingDemo)
            Button(L("workbook.action.demo")) { Task { await model.useDemo() } }.disabled(model.busy || model.loadingDemo || model.loadingReport)
            Divider()
            Text(L("workbook.sidebar.versions")).readableFont(.headline)
            ScrollView {
                VStack(alignment:.leading,spacing:9) {
                    ForEach(model.revisions,id:\.id) { r in
                        VStack(alignment:.leading,spacing:3) {
                            Text(verbatim:model.versionLabel(r["revision_occurrence_id"].string)).readableFont(.callout, weight: .medium).lineLimit(2)
                            HStack { Text(r["format"].string.uppercased()); Text(LC("workbook.count.sheets",r["sheets"].array.count)); if r["revision_occurrence_id"].string == model.beforeID { Text(L("workbook.before")).foregroundStyle(.orange) }; if r["revision_occurrence_id"].string == model.afterID { Text(L("workbook.after")).foregroundStyle(.blue) } }.readableFont(.caption).foregroundStyle(.secondary)
                        }.frame(maxWidth:.infinity,alignment:.leading)
                    }
                }.padding(.horizontal,3)
            }
            if !model.projectID.isEmpty {
                if model.busy { Button(L("workbook.action.cancelAnalysis")) { model.cancelAnalysis() }.disabled(!model.canCancelAnalysis) }
                else { Button(L("workbook.action.reanalyze")) { Task { await model.run() } }.disabled(model.loadingReport || model.loadingDemo) }
            }
            Text(L("workbook.sidebar.versionExplanation")).readableFont(.caption).foregroundStyle(.secondary)
        }.padding(12)
    }
    private var reportBar: some View {
        VStack(alignment:.leading,spacing:4){
            HStack {
                NativeWorkspaceIdentity(name:"Reviset.workbook.projectTitle",title:workspaceIdentityTitle(projectTitle:model.project["title"].string,reportTitle:model.report["title"].string,fallback:L("workbook.window.title")),reportID:model.reportID).frame(minWidth:140,maxWidth:.infinity,alignment:.leading)
                if !model.reports.isEmpty {
                    Menu {ForEach(model.reports,id:\.id){r in Button(localizedISODate(r["created_at"].string)+" · "+String(r["report_id"].string.suffix(12))){Task{await model.selectReport(r["report_id"].string)}}};Divider();Button(L("git.reportDetails")){model.tab="ai"}} label:{Image(systemName:"lock.doc")}.accessibilityLabel(L("git.reportChip",.verbatim(String(model.reportID.suffix(12))))).help(model.reportID).disabled(model.busy || model.loadingReport || model.loadingDemo)
                }
                Spacer()
                if model.busy {ProgressView().controlSize(.small);Button(L("workbook.action.cancelAnalysis")){model.cancelAnalysis()}.disabled(!model.canCancelAnalysis)}
            }.background(WorkspaceLayoutMarker(name:"Reviset.workbook.reportBar"))
            if !model.failure.isEmpty {Text(verbatim:model.failure).readableFont(.caption).foregroundStyle(.red).textSelection(.enabled)}
            if !model.recoveryWarning.isEmpty {Text(verbatim:model.recoveryWarning).readableFont(.caption).foregroundStyle(.orange).textSelection(.enabled)}
        }.controlSize(.small).padding(.horizontal,12).padding(.vertical,5)
    }
    private var emptyWorkspace: some View {
        VStack(spacing:0) {
            WorkbookStatus(title:model.projects.isEmpty ? L("workbook.empty.title") : L("workbook.empty.noAnalysis"),detail:L("workbook.empty.detail"),loading:model.loadingDemo)
            Button(L("workbook.action.demo")) { Task { await model.useDemo() } }.buttonStyle(.borderedProminent).disabled(model.busy || model.loadingDemo || model.loadingReport).padding(.bottom,24)
        }
    }
    private var comparison: some View {
        VStack(spacing:0) {
            versionBar
            Divider()
            HStack {
                if model.effectiveDiffMode=="source" {
                TextField(L("workbook.nav.address"),text:$model.addressInput).accessibilityIdentifier("Docver.workbook.addressInput").textFieldStyle(.roundedBorder).frame(width:130).onSubmit { Task { await model.goToAddress() } }
                Button(L("workbook.action.go")) { Task { await model.goToAddress() } }
                Spacer()
                Button { Task { await model.moveWindow(columns:-model.columnLimit) } } label: { Image(systemName:"chevron.left") }.disabled(model.columnStart == 1).accessibilityLabel(L("workbook.nav.previousColumns"))
                Text(L("workbook.nav.columns",.verbatim(model.navigationRangePrefix),.verbatim(WorkbookGrid.columnLabel(model.columnStart)),.verbatim(WorkbookGrid.columnLabel(model.columnStart+model.columnLimit-1)))).readableFont(.caption).monospacedDigit()
                Button { Task { await model.moveWindow(columns:model.columnLimit) } } label: { Image(systemName:"chevron.right") }.disabled(model.columnStart+model.columnLimit>16384).accessibilityLabel(L("workbook.nav.nextColumns"))
                Button { Task { await model.moveWindow(rows:-model.rowLimit) } } label: { Image(systemName:"chevron.up") }.disabled(model.rowStart == 1).accessibilityLabel(L("workbook.nav.previousRows"))
                Text(L("workbook.nav.rows",.verbatim(model.navigationRangePrefix),.integer(model.rowStart),.integer(model.rowStart+model.rowLimit-1))).readableFont(.caption).monospacedDigit()
                Button { Task { await model.moveWindow(rows:model.rowLimit) } } label: { Image(systemName:"chevron.down") }.disabled(model.rowStart+model.rowLimit>1048576).accessibilityLabel(L("workbook.nav.nextRows"))
                } else {
                    Text(L("workbook.nav.textModeDetail")).readableFont(.caption).foregroundStyle(.secondary)
                    Button(L("git.original")){model.setDiffMode("source")}.background(WorkspaceLayoutMarker(name:"Reviset.workbook.showOriginal"))
                    Spacer()
                }
                WorkbookCellDetailsButton(model:model).frame(width:110,height:24)
            }.padding(.horizontal,12).padding(.vertical,7).disabled(!model.ready)
            if !model.addressFailure.isEmpty { Text(verbatim:model.addressFailure).readableFont(.caption).foregroundStyle(.red).padding(8) }
            if !model.rangeFailure.isEmpty {
                HStack {
                    Text(verbatim:model.rangeFailure).readableFont(.caption).foregroundStyle(.red).textSelection(.enabled)
                    Button(L("workbook.action.reloadRange")) { Task { await model.loadRange() } }.disabled(!model.ready || model.loadingRange)
                }.padding(8)
            }
            WorkspacePaneSplit(name:"workbook.changes",isVertical:layout.configuration.changesDock != .bottom,auxiliaryFirst:layout.configuration.changesDock == .left,auxiliaryVisible:layout.configuration.changesVisible,extent:.points(layout.configuration.changesDock == .bottom ? layout.configuration.changesHeight:layout.configuration.changesWidth),primaryMinimum:240,auxiliaryMinimum:layout.configuration.changesDock == .bottom ? 110:260,onResize:{value in if case .points(let size)=value {layout.update{if $0.changesDock == .bottom {$0.changesHeight=min(600,max(110,size))}else{$0.changesWidth=min(600,max(260,size))}}}}) {
                VStack(spacing:0) {
                    WorkspacePaneSplit(name:"workbook.pages",isVertical:layout.configuration.pageArrangement == .horizontal,auxiliaryVisible:model.beforeID != model.afterID,extent:.fraction(layout.configuration.pageFraction),primaryMinimum:150,auxiliaryMinimum:150,onResize:{value in if case .fraction(let fraction)=value {layout.update{$0.pageFraction=min(0.8,max(0.2,fraction))}}}) {gridPane(before:true)} auxiliary:{gridPane(before:false)}
                    .disabled(model.effectiveDiffMode != "source")
                    .frame(minHeight:160,maxHeight:.infinity).opacity(model.effectiveDiffMode=="source" ? 1:0).allowsHitTesting(model.effectiveDiffMode=="source").accessibilityHidden(model.effectiveDiffMode != "source")
                    .overlay {if model.effectiveDiffMode=="text" {WorkbookUnifiedDiff(model:model)}}
                    .overlay { if model.loadingRange { ZStack { Color(nsColor:.windowBackgroundColor).opacity(0.94); ProgressView(L("workbook.status.loadingRange")) } } }
                    if model.effectiveDiffMode=="source" {Text(model.navigationDetail).readableFont(.caption).foregroundStyle(.secondary).padding(.horizontal,12).padding(.vertical,6)}
                    WorkbookSelectedWarnings(model:model).padding(.horizontal,12).padding(.bottom,4)
                    HStack{Text(L("workbook.cell.storedOnly")).readableFont(.caption2).foregroundStyle(.secondary);if !model.selectedChange.isNull{Text(WorkbookLabels.association(model.selectedChange["association"].string)).readableFont(.caption2).foregroundStyle(.orange)};Spacer();if model.canReturnToChange {Button(L("git.returnToChange")){Task{await model.returnToChange()}}.readableFont(.caption).background(WorkspaceLayoutMarker(name:"Reviset.workbook.returnToChange"))}}.padding(.horizontal,12).padding(.bottom,5)
                }
            } auxiliary:{changesPane}
        }
    }
    private var versionBar: some View {
        HStack(spacing:8) {
            Text(L("git.query")).readableFont(.caption).foregroundStyle(.secondary)
            if model.revisions.count==1 {Text(verbatim:model.versionLabel(model.revisions[0]["revision_occurrence_id"].string)).readableFont(.caption, weight: .semibold)} else {
            Menu {ForEach(model.revisions,id:\.id){revision in Button(model.versionLabel(revision["revision_occurrence_id"].string)){Task{await model.selectVersion(revision["revision_occurrence_id"].string)}}}} label:{Image(systemName:"clock.arrow.circlepath")}.help(L("git.versions")).accessibilityLabel(L("git.versions"))
            versionPicker(title:L("workbook.before"),selection:model.changesFromID.isEmpty ? model.beforeID:model.changesFromID,before:true)
            Image(systemName:"arrow.right").foregroundStyle(.secondary)
            versionPicker(title:L("workbook.after"),selection:model.changesToID.isEmpty ? model.afterID:model.changesToID,before:false)
            Picker(L("workbook.comparison.mode"),selection:Binding(get:{model.mode},set:{value in Task { await model.changeMode(value) }})) { Text(L("git.net")).tag("range_net"); Text(L("git.history")).tag("history") }.labelsHidden().pickerStyle(.segmented).frame(width:275).disabled(model.changesFromID==model.changesToID)
            }
            Spacer(minLength:4)
            Menu {Picker(L("git.view"),selection:Binding(get:{model.effectiveDiffMode},set:{model.setDiffMode($0)})){Text(L("git.original")).tag("source");Text(L("git.textDiff")).tag("text")}.disabled(model.readingSingleVersion)} label:{Label(model.effectiveDiffMode=="source" ? L("git.original"):L("git.textDiff"),systemImage:"rectangle.split.2x1")}
            Button{layout.update{$0.changesVisible.toggle()}}label:{Image(systemName:"list.bullet")}.help(L("layout.panel.changes")).accessibilityLabel(L("layout.panel.changes"))
            Button{model.inspectorVisible.toggle()}label:{Image(systemName:"sidebar.right")}.help(L("workbook.inspector.title")).accessibilityLabel(L("workbook.inspector.title"))
        }.controlSize(.small).padding(.horizontal,12).padding(.vertical,7).disabled(!model.ready)
    }
    private func versionPicker(title: String, selection: String, before: Bool) -> some View {
        Picker(title,selection:Binding(get:{selection},set:{id in Task { if before { await model.changeVersions(before:id) } else { await model.changeVersions(after:id) } }})) {
            ForEach(model.revisions,id:\.id) { r in Text(verbatim:model.versionLabel(r["revision_occurrence_id"].string)).tag(r["revision_occurrence_id"].string) }
        }.labelsHidden().frame(maxWidth:170)
    }
    private func sheetPicker(before: Bool) -> some View {
        let occurrence = before ? model.beforeID : model.afterID
        let current = before ? model.beforeSheetID : model.afterSheetID
        return Picker(before ? L("workbook.sheet.before") : L("workbook.sheet.after"),selection:Binding(get:{current},set:{id in Task { if before { await model.changeSheet(before:id) } else { await model.changeSheet(after:id) } }})) {
            if current.isEmpty { Text(L("workbook.sheet.none")).tag("") }
            ForEach(model.sheets(occurrence),id:\.workbookSheetID) { s in Text(verbatim:s["name"].string + (s["hidden"].bool ? L("workbook.sheet.hiddenSuffix") : "") + " (\(s["row_count"].int)×\(s["column_count"].int))").tag(s["sheet_id"].string) }
        }.frame(maxWidth:.infinity).background(WorkspaceLayoutMarker(name:"Reviset.workbook.sheetPicker."+(before ? "before":"after"))).disabled(!model.ready || model.loadingRange)
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
            HStack { Text(verbatim:(model.readingSingleVersion ? L("doc.common.source")+" · ":(before ? L("workbook.pane.beforePrefix") : L("workbook.pane.afterPrefix"))) + model.versionLabel(occurrence)).readableFont(.caption, weight: .semibold); Spacer();sheetPicker(before:before).labelsHidden().controlSize(.small); if sheet["hidden"].bool { Label(L("workbook.sheet.hidden"),systemImage:"eye.slash").readableFont(.caption) } }.padding(8).background(Color(nsColor:.controlBackgroundColor))
            HStack {
                Text(L("workbook.pane.range",.integer(row),.integer(row+model.rowLimit-1),.verbatim(WorkbookGrid.columnLabel(column)),.verbatim(WorkbookGrid.columnLabel(column+model.columnLimit-1)))).readableFont(.caption2).foregroundStyle(.secondary)
                Spacer()
                if let coordinate { Text(L("workbook.pane.evidence",.verbatim(WorkbookGrid.address(coordinate.row,coordinate.column)))).readableFont(.caption, design: .monospaced).foregroundStyle(.blue) }
            }.padding(.horizontal,8).padding(.bottom,5)
            if id.isEmpty { WorkbookStatus(title:L("workbook.sheet.unmatched"),detail:L("workbook.sheet.unmatchedDetail"),loading:false) }
            else { WorkbookGrid(keyboardEnabled:model.effectiveDiffMode=="source",sourceIdentity:[model.scope,occurrence,id].joined(separator:"|"),language:language.effectiveLanguage,pane:before ? "before" : "after",revealIntent:[model.scope,occurrence,id,String(model.revealGeneration)].joined(separator:"|"),cells:cells,rowStart:row,columnStart:column,rowCount:model.rowLimit,columnCount:model.columnLimit,selectedRow:coordinate?.row ?? 0,selectedColumn:coordinate?.column ?? 0,onSelect:{row,column in Task { await model.selectCell(row,column) }}).disabled(!model.ready || model.loadingRange) }
        }.frame(minWidth:280,maxWidth:.infinity,maxHeight:.infinity)
    }
    private var changesPane: some View {
        VStack(spacing:0) {
            let compact=layout.configuration.changesDock != .bottom
            if model.revisions.count != 1 {
            let arrangement=compact ? AnyLayout(VStackLayout(alignment:.leading,spacing:6)):AnyLayout(HStackLayout())
            arrangement {
                Text(model.changesFromID==model.changesToID ? L("git.reading"):(model.changesMode == "history" ? L("workbook.changes.historyTitle") : L("workbook.changes.netTitle"))).readableFont(.headline)
                Text(L("workbook.changes.page",.integer(model.changePageNumber),.count(model.changes.count),.count(model.changeTotal))).readableFont(.caption).foregroundStyle(.secondary)
                if !compact {Spacer()}
                HStack(spacing:6) {
                    Button { Task { await model.stepChange(-1) } } label: { Image(systemName:"chevron.up") }.accessibilityLabel(L("workbook.changes.previous"))
                    Button { Task { await model.stepChange(1) } } label: { Image(systemName:"chevron.down") }.accessibilityLabel(L("workbook.changes.next"))
                    if model.changePageNumber > 1 { Button { Task { await model.loadChanges(preserveEndpoints:true) } } label: {if compact {Image(systemName:"backward.end")} else {Text(L("workbook.paging.first"))}}.accessibilityLabel(L("workbook.paging.first")).help(L("workbook.paging.first")) }
                    if !model.changePreviousCursors.isEmpty { Button { Task { await model.loadChanges(previous:true) } } label: {if compact {Image(systemName:"chevron.left")} else {Text(L("workbook.paging.previous"))}}.accessibilityLabel(L("workbook.paging.previous")).help(L("workbook.paging.previous")) }
                    if !model.changeCursor.isEmpty { Button { Task { await model.loadChanges(next:true) } } label: {if compact {Image(systemName:"chevron.right")} else {Text(L("workbook.paging.next"))}}.accessibilityLabel(L("workbook.paging.next")).help(L("workbook.paging.next")) }
                }.controlSize(compact ? .small:.regular)
            }.padding(.horizontal,12).padding(.vertical,7).disabled(!model.ready || model.loadingChanges)
            Text(model.changeListProvenance).readableFont(.caption2).foregroundStyle(.secondary).padding(.horizontal,12).frame(maxWidth:.infinity,alignment:.leading)
            Text(verbatim:model.versionLabel(model.changesFromID)+" → "+model.versionLabel(model.changesToID)).readableFont(.caption2).foregroundStyle(.secondary).padding(.horizontal,12).frame(maxWidth:.infinity,alignment:.leading)
            }
            if !model.sourceScopeDescription.isEmpty { WorkbookSourceScopeCaption(text:model.sourceScopeDescription).padding(.horizontal,12).frame(maxWidth:.infinity,alignment:.leading) }
            if !model.changeCursor.isEmpty { Text(L("workbook.paging.more")).readableFont(.caption2).foregroundStyle(.secondary).padding(.horizontal,12).frame(maxWidth:.infinity,alignment:.leading) }
            else if !model.changePreviousCursors.isEmpty { Text(L("workbook.paging.last")).readableFont(.caption2).foregroundStyle(.secondary).padding(.horizontal,12).frame(maxWidth:.infinity,alignment:.leading) }
            if !model.comparisonNotice.isEmpty { Text(verbatim:model.comparisonNotice).readableFont(.caption).foregroundStyle(.orange).padding(.horizontal,12).padding(.vertical,3) }
            if !model.selectionNotice.isEmpty { Text(verbatim:model.selectionNotice).readableFont(.caption).foregroundStyle(.orange).padding(.horizontal,12).padding(.vertical,3) }
            if !model.blankFormattingWarning.isEmpty {
                Label(model.blankFormattingWarning,systemImage:"exclamationmark.triangle").readableFont(.caption).foregroundStyle(.orange).fixedSize(horizontal:false,vertical:true).frame(maxWidth:.infinity,alignment:.leading).padding(.horizontal,12).padding(.vertical,3).accessibilityIdentifier("Docver.workbook.blankFormattingWarning")
            }
            if model.changePageNumber > model.changePreviousCursors.count+1 { Text(L("workbook.paging.historyLimit")).readableFont(.caption2).foregroundStyle(.secondary).padding(.horizontal,12) }
            if model.loadingChanges { ProgressView(L("workbook.status.loadingChanges")).frame(maxWidth:.infinity,maxHeight:.infinity) }
            else if !model.changesFailure.isEmpty { Text(verbatim:model.changesFailure).readableFont(.caption).foregroundStyle(.red).padding(12).frame(maxWidth:.infinity,maxHeight:.infinity) }
            else if model.changes.isEmpty {WorkbookEmptyChangesState(model:model).frame(maxWidth:.infinity,maxHeight:.infinity)}
            else {
                List(selection:Binding<String?>(get:{model.selectedChangeID.isEmpty ? nil : model.selectedChangeID},set:{if let id = $0 { Task { await model.chooseChange(id) } }})) {
                    ForEach(model.changes,id:\.workbookChangeID) { change in
                        let rowLayout=compact ? AnyLayout(VStackLayout(alignment:.leading,spacing:5)):AnyLayout(HStackLayout(spacing:10))
                        rowLayout {
                            Text(verbatim:WorkbookLabels.kind(change["kind"].string)).readableFont(.caption, weight: .semibold).frame(width:compact ? nil:110,alignment:.leading)
                            Text(verbatim:change["before_address"].string + " → " + change["after_address"].string).readableFont(.caption, design: .monospaced).frame(width:compact ? nil:125,alignment:.leading)
                            Text(verbatim:WorkbookLabels.description(change)).readableFont(.caption).lineLimit(compact ? 4:2)
                            if !compact {Spacer()}
                            Text(verbatim:WorkbookLabels.association(change["association"].string)).readableFont(.caption).foregroundStyle(change["association"].string == "needs_review" ? .orange : .secondary)
                        }.tag(change["change_id"].string)
                    }
                }.listStyle(.inset).disabled(!model.ready).background(WorkspaceLayoutMarker(name:"Reviset.workbook.changes.list"))
            }
        }
    }
    private var aiAndReleases: some View {
        ScrollView {
            VStack(alignment:.leading,spacing:18) {
                Text(L("git.reportDetails")).readableFont(.headline)
                Text(model.reportID).readableFont(.caption, design: .monospaced).textSelection(.enabled)
                Text(localizedISODate(model.report["created_at"].string)).readableFont(.caption)
                Text(L("git.reportScope")).readableFont(.caption).foregroundStyle(.secondary)
                Text(L("workbook.ai.title")).readableFont(.title2, weight: .semibold)
                Text(L("workbook.ai.detail")).foregroundStyle(.secondary)
                HStack { Button(L("workbook.action.loadMCP")) { Task { await model.loadMCP() } }.disabled(!model.ready || model.loadingMCP); Button(L("workbook.action.copyConfig")) { model.copyMCP() }.disabled(!model.canCopyMCP); if model.loadingMCP { ProgressView().controlSize(.small) } }
                if !model.mcpFailure.isEmpty { Text(verbatim:model.mcpFailure).foregroundStyle(.red).readableFont(.caption) }
                if model.canCopyMCP { Text(verbatim:model.mcp).readableFont(.caption, design: .monospaced).textSelection(.enabled).padding(12).frame(maxWidth:.infinity,alignment:.leading).background(Color(nsColor:.textBackgroundColor)).clipShape(RoundedRectangle(cornerRadius:6)) }
                Divider()
                HStack { Text(L("workbook.release.title")).readableFont(.headline); Spacer(); Button(L("workbook.action.pinRelease")) { model.publishPresented = true }.disabled(!model.ready); Button(L("workbook.action.exportReport")) { Task { await model.export() } }.disabled(!model.ready) }
                Text(L("workbook.release.detail")).readableFont(.caption).foregroundStyle(.secondary)
                if model.releases.isEmpty { Text(L("workbook.release.empty")).foregroundStyle(.secondary) }
                if model.releases.count > 100 { Text(L("workbook.release.limit")).readableFont(.caption).foregroundStyle(.secondary) }
                ForEach(Array(model.releases.prefix(100).enumerated()),id:\.offset) { _, release in
                    VStack(alignment:.leading,spacing:5) {
                        Text(verbatim:release["label"].string).readableFont(.headline)
                        Text(verbatim:release["reason"].string).textSelection(.enabled)
                        Text(verbatim:localizedISODate(release["recorded_at"].string) + " · " + release["report_id"].string).readableFont(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                    }.padding(12).frame(maxWidth:.infinity,alignment:.leading).background(Color(nsColor:.controlBackgroundColor)).clipShape(RoundedRectangle(cornerRadius:6))
                }
                Divider()
                WorkbookCoverageView(gaps:model.coverage,total:model.report["coverage_gap_count"].int,truncated:model.report["coverage_truncated"].bool,revisions:model.revisions)
            }.padding(24).frame(maxWidth:1000,alignment:.leading)
        }
    }
}

// A missing source field and an observed empty string are separate states.
// Continuation metadata describes the exact fragment; it must not become a
// complete diff just because its current fragment happens to be empty.
enum WorkbookRawFieldState:String {case unavailable,missing,empty,complete,partial,earlier,invalid}
struct WorkbookRawFieldObservation {
    let state:WorkbookRawFieldState
    let text:String?
    let offset:Int
    let total:Int
    var complete:Bool {state == .complete || state == .empty}
}
func workbookRawField(_ cell:JSON,field:String)->WorkbookRawFieldObservation {
    func result(_ state:WorkbookRawFieldState,_ text:String?=nil,_ offset:Int=0,_ total:Int=0)->WorkbookRawFieldObservation {WorkbookRawFieldObservation(state:state,text:text,offset:offset,total:total)}
    guard !cell.isNull else{return result(.unavailable)}
    let raw=cell[field],metadata=cell["text_continuations"][field].dictionary
    func integer(_ value:Any?)->Int? {
        guard let number=value as? NSNumber,CFGetTypeID(number) != CFBooleanGetTypeID(),["c","s","i","l","q","C","S","I","L","Q"].contains(String(cString:number.objCType)),number.int64Value>=0,number.int64Value<=Int64(Int32.max) else{return nil}
        return Int(number.int64Value)
    }
    guard let state=metadata["state"] as? String,let offset=integer(metadata["offset"]),let total=integer(metadata["total_length"]),let nextRaw=metadata["next_offset"] else{return result(.invalid)}
    let next:Int?
    if nextRaw is NSNull {next=nil}else{guard let value=integer(nextRaw) else{return result(.invalid)};next=value}
    if state=="missing" {return raw.isNull && total==0 && next==nil ? result(.missing,nil,offset,total):result(.invalid)}
    guard let text=raw.raw as? String else{return result(.invalid)}
    switch state {
    case "empty":return text.isEmpty && total==0 && offset==0 && next==nil ? result(.empty,text):result(.invalid)
    case "complete":
        guard offset==0,next==nil,total>0,total==text.utf16.count else{return result(.invalid)}
        return result(text.isEmpty ? .empty:.complete,text,offset,total)
    case "truncated":
        let end=offset+text.utf16.count
        guard total>0,offset<=total,end<=total else{return result(.invalid)}
        if text.isEmpty {return offset==total && next==nil ? result(.earlier,text,offset,total):result(.invalid)}
        guard offset>0 || end<total else{return result(.invalid)}
        if let next {guard next==end,end<total else{return result(.invalid)}}else{guard end==total else{return result(.invalid)}}
        return result(.partial,text,offset,total)
    default:return result(.invalid)
    }
}
// The selected engine event authorizes one compared field. Reading two raw
// cells alone does not establish a value/formula edit (for example across date
// systems or formula dialects). Unknown and withheld event contexts stay neutral.
enum WorkbookFieldDiffEligibility:Equatable {case neutral,formulaSource,storedValue}
struct WorkbookSelectedEventScope {
    let beforeOccurrence:String
    let afterOccurrence:String
    let beforeSheet:String
    let afterSheet:String
}
func workbookFieldContextAuthorized(change:JSON,before:JSON,after:JSON,scope:WorkbookSelectedEventScope)->Bool {
    guard !change.isNull,!before.isNull,!after.isNull,
          ["exact","inferred"].contains(change["association"].string),
          ["unique_nonempty_first_column_key","unique_exact_row_content"].contains(change["alignment_method"].string),
          !change["from_revision_occurrence_id"].string.isEmpty,!change["to_revision_occurrence_id"].string.isEmpty,
          change["from_revision_occurrence_id"].string != change["to_revision_occurrence_id"].string,
          !change["from_sheet_id"].string.isEmpty,!change["to_sheet_id"].string.isEmpty,
          change["from_revision_occurrence_id"].string==scope.beforeOccurrence,change["to_revision_occurrence_id"].string==scope.afterOccurrence,
          change["from_sheet_id"].string==scope.beforeSheet,change["to_sheet_id"].string==scope.afterSheet,
          !before["address"].string.isEmpty,!after["address"].string.isEmpty,
          change["before_address"].string==before["address"].string,change["after_address"].string==after["address"].string else{return false}
    return true
}
func workbookFieldDiffEligibility(change:JSON,before:JSON,after:JSON,scope:WorkbookSelectedEventScope)->WorkbookFieldDiffEligibility {
    guard workbookFieldContextAuthorized(change:change,before:before,after:after,scope:scope),before["formula_interpretation"].string != "unresolved",after["formula_interpretation"].string != "unresolved" else{return .neutral}
    switch change["kind"].string {
    case "formula":
        let old=before["formula_dialect"].string,new=after["formula_dialect"].string
        return !before["formula"].isNull && !after["formula"].isNull && ["xlsx_a1","ods_openformula"].contains(old) && old==new ? .formulaSource:.neutral
    case "stored_value":
        return ["present","not_applicable"].contains(before["cached_result"].string) && ["present","not_applicable"].contains(after["cached_result"].string) && ["blank","string","number","boolean","date","time","error"].contains(before["value_type"].string) && before["value_type"].string==after["value_type"].string ? .storedValue:.neutral
    default:return .neutral
    }
}
func workbookFieldTextDiff(before:JSON,after:JSON,field:String,textOffset:Int,eligibility:WorkbookFieldDiffEligibility)->UnifiedTextDiff? {
    let old=workbookRawField(before,field:field),new=workbookRawField(after,field:field)
    guard textOffset==0,old.complete,new.complete,let oldText=old.text,let newText=new.text else{return nil}
    let unresolved=before["formula_interpretation"].string=="unresolved" || after["formula_interpretation"].string=="unresolved"
    let missingCache=field=="value" && (before["cached_result"].string=="missing" || after["cached_result"].string=="missing")
    let eligibleField=(eligibility == .formulaSource && field=="formula") || (eligibility == .storedValue && field=="value")
    let semantic = eligibleField && !unresolved && !missingCache && (field=="formula" || before["value_type"].string==after["value_type"].string)
    return unifiedTextDiff(before:oldText,after:newText,semantic:semantic)
}
func workbookSelectedWarningKeys(_ cell:JSON)->[String] {
    guard !cell.isNull else{return ["cellNotMaterialized"]}
    var keys:[String]=[]
    if cell["formula_interpretation"].string=="unresolved" {keys.append("formulaUnresolvedShort")}
    let missingCache=cell["cached_result"].string=="missing"
    if missingCache {keys.append("resultMissingShort")}
    if cell["cache_freshness"].string=="unknown" {keys.append("freshnessUnknownShort")}
    if !missingCache {
        if cell["value"].isNull {keys.append(cell["value_type"].string=="blank" ? "valueBlankShort":"valueUnrecordedShort")}
        else if cell["value"].raw is String,cell["value"].string.isEmpty {
            let field=workbookRawField(cell,field:"value")
            if field.state == .empty || ((cell["source_lengths"]["value"].raw as? NSNumber).map{CFGetTypeID($0) != CFBooleanGetTypeID() && $0.doubleValue==0} ?? false) {keys.append("valueEmptyShort")}
        }
    }
    return keys
}
enum WorkbookFieldCaption:String {case compared,notAsserted,withheld,formulaRole,cache,valueType,dialect,missing,fragment,invalid,unavailable,identical,observedBlank,observed}
func workbookObservationCaptionKey(cell:JSON,field:String)->String {
    guard !cell.isNull else{return "cellNotMaterialized"}
    switch workbookRawField(cell,field:field).state {
    case .unavailable:return "cellNotMaterialized"
    case .invalid:return "invalidSourceSegment"
    case .partial,.earlier:return "partialSourceSegment"
    case .empty:return "observationEmpty"
    case .missing:
        if field=="formula" {return "formulaAbsent"}
        if field=="value",cell["cached_result"].string=="missing" {return "resultMissingShort"}
        return field=="value" && cell["value_type"].string=="blank" ? "valueBlankShort":"observationNull"
    case .complete:return "observationPresent"
    }
}
@MainActor func workbookObservationCaption(cell:JSON,field:String)->String {
    switch workbookObservationCaptionKey(cell:cell,field:field) {
    case "formulaAbsent":return L("git.formulaAbsent")
    case "resultMissingShort":return L("git.cacheMissing")
    case "valueBlankShort":return L("git.observedBlank")
    case "observationEmpty":return L("workbook.cell.emptyString")
    case "cellNotMaterialized":return L("workbook.cell.noObservation")
    default:return L("workbook.cell.valueAbsent")
    }
}
func workbookFieldShowsRaw(caption:WorkbookFieldCaption,diff:UnifiedTextDiff?)->Bool {caption != .compared || diff?.bounded != true}
func workbookFieldCaption(change:JSON,before:JSON,after:JSON,field:String,textOffset:Int,scope:WorkbookSelectedEventScope)->WorkbookFieldCaption {
    let old=workbookRawField(before,field:field),new=workbookRawField(after,field:field)
    if old.state == .unavailable || new.state == .unavailable {return .unavailable}
    if old.state == .invalid || new.state == .invalid {return .invalid}
    if old.state == .missing || new.state == .missing {
        if field=="value",[before,after].contains(where:{$0["value"].isNull && $0["value_type"].string=="blank" && $0["cached_result"].string != "missing"}) {return .observedBlank}
        return .missing
    }
    if textOffset>0 || !old.complete || !new.complete {return .fragment}
    if change.isNull {return .notAsserted}
    if !workbookFieldContextAuthorized(change:change,before:before,after:after,scope:scope) {return .withheld}
    if (field=="formula" && change["kind"].string != "formula") || (field=="value" && change["kind"].string != "stored_value") || (field=="number_format" && change["kind"].string != "number_format") {return .notAsserted}
    if field=="number_format" {return .observed}
    if before["formula_interpretation"].string=="unresolved" || after["formula_interpretation"].string=="unresolved" {return .formulaRole}
    if field=="value",!["present","not_applicable"].contains(before["cached_result"].string) || !["present","not_applicable"].contains(after["cached_result"].string) {return .cache}
    if field=="value",!["blank","string","number","boolean","date","time","error"].contains(before["value_type"].string) || before["value_type"].string != after["value_type"].string {return .valueType}
    if field=="formula",before["formula_dialect"].string != after["formula_dialect"].string {return .dialect}
    let eligibility=workbookFieldDiffEligibility(change:change,before:before,after:after,scope:scope)
    if eligibility == .neutral {return .withheld}
    if let a=old.text,let b=new.text,a.utf16.elementsEqual(b.utf16) {return .identical}
    return .compared
}
@MainActor func workbookFieldCaptionText(_ reason:WorkbookFieldCaption)->String {
    switch reason {
    case .compared:return ""
    case .notAsserted:return L("git.fieldNotAsserted")
    case .withheld:return L("git.fieldPairWithheld")
    case .formulaRole:return L("workbook.cell.unresolvedFormula")
    case .cache:return L("git.fieldCacheUnavailable")
    case .valueType:return L("git.fieldValueType")
    case .dialect:return L("git.fieldDialect")
    case .missing:return L("git.fieldMissing")
    case .fragment:return L("git.partialDiff")
    case .invalid:return L("git.invalidObservation")
    case .unavailable:return L("workbook.cell.noObservation")
    case .identical:return L("git.fieldIdentical")
    case .observedBlank:return L("git.observedBlank")
    case .observed:return L("git.fieldObserved")
    }
}
@MainActor func workbookSelectedWarningMessages(_ cell:JSON)->[String] {
    workbookSelectedWarningKeys(cell).map {key in
        switch key {case "cellNotMaterialized":return L("workbook.cell.noObservation");case "formulaUnresolvedShort":return L("workbook.cell.unresolvedFormula");case "resultMissingShort":return L("git.cacheMissing");case "freshnessUnknownShort":return L("git.cacheUnknown");case "valueBlankShort":return L("git.observedBlank");case "valueEmptyShort":return L("workbook.cell.emptyString");default:return L("workbook.cell.valueAbsent")}
    }
}
private struct WorkbookSelectedWarnings:View {
    @ObservedObject var model:WorkbookModel
    var body:some View {
        VStack(alignment:.leading,spacing:3){
            if model.loadingCell {Text(L("workbook.status.loadingCell")).readableFont(.caption2).foregroundStyle(.secondary)}
            else if !model.cellFailure.isEmpty {HStack{Text(verbatim:model.cellFailure).textSelection(.enabled);Button(L("workbook.action.reloadSourceStart")){Task{await model.loadSelectedCells()}}.disabled(!model.ready)}.readableFont(.caption).foregroundStyle(.orange)}
            else if model.selectedRow>0 || !model.selectedChange.isNull {
                if model.showingSheetMetadata {Text(L("workbook.cell.metadataEvent")).readableFont(.caption2).foregroundStyle(.secondary)}
                else {ForEach(Array(model.selectedSourceWarnings.enumerated()),id:\.offset){index,message in Label(message,systemImage:"exclamationmark.circle").readableFont(.caption2).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true).background(WorkspaceLayoutMarker(name:"Reviset.workbook.selectedCellWarning.\(index)"))}}
            }
        }.frame(maxWidth:.infinity,alignment:.leading)
    }

}
struct WorkbookEmptyChangesState:View {
    @ObservedObject var model:WorkbookModel
    var body:some View {
        NativeEmptyComparisonGuidance(message:model.emptyChangesMessage,showsImport:model.emptyChangesKind == .additionalVersion,canImport:model.ready,onImport:{model.openNewComparisonImport()})
    }
}
private struct WorkbookUnifiedDiff:View {
    @ObservedObject var model:WorkbookModel
    var body:some View {
        VStack(alignment:.leading,spacing:12){
            Text(L("git.storedDiff")).readableFont(.headline)
            Text(verbatim:model.sourceIdentity(before:true)+" → "+model.sourceIdentity(before:false)).readableFont(.caption).textSelection(.enabled).background(WorkspaceLayoutMarker(name:"Reviset.workbook.textSourceIdentity"))
            ForEach(Array(model.missingSourceSheetCaptions.enumerated()),id:\.offset){_,caption in Text(verbatim:caption).readableFont(.caption2).foregroundStyle(.secondary)}
            if model.loadingCell {ProgressView(L("workbook.status.loadingCell"))}
            else if !model.cellFailure.isEmpty {Text(model.cellFailure).foregroundStyle(.red)}
            else if model.showingSheetMetadata {
                VStack(alignment:.leading,spacing:8){
                    Text(L("workbook.cell.metadataEvent")).readableFont(.caption).foregroundStyle(.secondary)
                    Text(WorkbookLabels.kind(model.selectedChange["kind"].string)).readableFont(.headline)
                    Text(verbatim:WorkbookLabels.description(model.selectedChange)).readableFont(.callout).textSelection(.enabled)
                    WorkbookSheetMetadata(title:L("workbook.sheet.beforeMetadata"),sheet:model.sheet(model.beforeID,model.beforeSheetID))
                    WorkbookSheetMetadata(title:L("workbook.sheet.afterMetadata"),sheet:model.sheet(model.afterID,model.afterSheetID))
                }.background(WorkspaceLayoutMarker(name:"Reviset.workbook.sheetMetadataDiff"))
            }
            else {
                HStack {
                    if model.cellTextOffset>0 {Button(L("workbook.action.sourceStartBoth")){Task{await model.loadSelectedCells(offset:0)}}}
                    if let next=model.cellTextNext {Button(L("workbook.action.sourceNextBoth")){Task{await model.loadSelectedCells(offset:next)}}}
                }.controlSize(.small).disabled(!model.ready || model.loadingCell)
                ScrollView([.horizontal,.vertical]){VStack(alignment:.leading,spacing:16){field("formula",title:L("workbook.cell.formula"));field("value",title:L("git.savedObservation"));field("number_format",title:L("workbook.cell.numberFormat"))}}
            }
            Spacer(minLength:0)
        }.padding(20).frame(maxWidth:.infinity,maxHeight:.infinity,alignment:.topLeading).background(Color(nsColor:.textBackgroundColor)).background(WorkspaceLayoutMarker(name:"Reviset.workbook.unifiedDiff"))
    }
    @ViewBuilder private func field(_ key:String,title:String)->some View {
        let old=workbookRawField(model.beforeCell,field:key),new=workbookRawField(model.afterCell,field:key)
        let eligibility=workbookFieldDiffEligibility(change:model.selectedChange,before:model.beforeCell,after:model.afterCell,scope:WorkbookSelectedEventScope(beforeOccurrence:model.beforeID,afterOccurrence:model.afterID,beforeSheet:model.beforeSheetID,afterSheet:model.afterSheetID))
        let diff=workbookFieldTextDiff(before:model.beforeCell,after:model.afterCell,field:key,textOffset:model.cellTextOffset,eligibility:eligibility)
        let caption=workbookFieldCaption(change:model.selectedChange,before:model.beforeCell,after:model.afterCell,field:key,textOffset:model.cellTextOffset,scope:WorkbookSelectedEventScope(beforeOccurrence:model.beforeID,afterOccurrence:model.afterID,beforeSheet:model.beforeSheetID,afterSheet:model.afterSheetID))
        VStack(alignment:.leading,spacing:7){
            Text(title).readableFont(.caption, weight: .semibold)
            // Status/offset/type labels live outside the verbatim source text.
            observation(old,before:true,showSource:workbookFieldShowsRaw(caption:caption,diff:diff),field:key)
            observation(new,before:false,showSource:workbookFieldShowsRaw(caption:caption,diff:diff),field:key)
            if let diff {
                if !diff.bounded {Text(L("git.diffBound")).readableFont(.caption).foregroundStyle(.secondary)}
                else {
                    if caption != .compared {Text(workbookFieldCaptionText(caption)).readableFont(.caption).foregroundStyle(.secondary)}
                    if diff.terminatorsDiffer {Text(L("git.terminatorsDiffer")).readableFont(.caption).foregroundStyle(.secondary)}
                    if diff.semantic && caption == .compared {
                    ForEach(Array(diff.lines.enumerated()),id:\.offset){_,line in NativeDiffSourceLine(prefix:line.prefix,text:line.text,semantic:diff.semantic,terminator:line.terminator)}
                    }
                }
            } else {Text(workbookFieldCaptionText(caption)).readableFont(.caption2).foregroundStyle(.secondary)}
        }
    }
    @ViewBuilder private func observation(_ value:WorkbookRawFieldObservation,before:Bool,showSource:Bool,field:String)->some View {
        let cell=before ? model.beforeCell:model.afterCell,side=before ? L("doc.common.before"):L("doc.common.after")
        let status:String = {switch value.state {
            case .unavailable:return L("workbook.cell.noObservation")
            case .invalid:return L("git.invalidObservation")
            case .missing:return workbookObservationCaption(cell:cell,field:field)+(value.offset==0 ? "":" · "+L("git.requestedOffset",.integer(value.offset)))
            case .empty:return L("workbook.cell.emptyString")
            case .earlier:return L("workbook.cell.valueEarlier")
            case .partial:return L("git.fragmentRange",.integer(value.offset),.integer(value.offset+(value.text?.utf16.count ?? 0)),.integer(value.total))
            case .complete:return field=="value" ? WorkbookLabels.valueType(cell["value_type"].string):field=="formula" ? L("workbook.cell.formula"):L("workbook.cell.numberFormat")
        }}()
        VStack(alignment:.leading,spacing:3){
            Text(side+" · "+status).readableFont(.caption).foregroundStyle(.secondary)
            if showSource,let text=value.text,!text.isEmpty {NativeNeutralSourceText(text:text,lines:neutralSourceLines(text,complete:value.complete)?.map{(text:$0.text,terminator:$0.terminator)}).background(WorkspaceLayoutMarker(name:"Reviset.workbook.rawField."+field+"."+(before ? "before":"after")))}
        }
    }
}

private struct WorkbookStatus: View {
    let title: String
    let detail: String
    let loading: Bool
    var body: some View { VStack(spacing:12) { if loading { ProgressView() } else { Image(systemName:"tablecells").font(.system(size:36)).foregroundStyle(.secondary) }; Text(verbatim:title).readableFont(.title3, weight: .semibold); Text(verbatim:detail).readableFont(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth:520) }.padding(28).frame(maxWidth:.infinity,maxHeight:.infinity) }
}

private struct WorkbookCellDetailsButton:NSViewRepresentable {
    @ObservedObject private var readability=ReadabilityPreferences.shared
    @ObservedObject var model:WorkbookModel
    @MainActor final class Coordinator:NSObject {
        var model:WorkbookModel?
        private func identity(_ model:WorkbookModel)->[String] {[model.scope,model.comparisonScope,model.rangeScope,model.beforeAddress,model.afterAddress,model.selectedChangeID,String(model.selectedRow),String(model.selectedColumn),String(model.revealGeneration)]}
        @objc func open(_ sender:NSButton){
            guard let model,model.canOpenCellDetails else{return}
            guard let window=sender.window,let content=window.contentView else{return}
            let scope=identity(model)
            func install(_ view:NSView){
                if let scroll=view as? WorkbookTableScrollView {
                    scroll.pendingCellDetailsReveal = { [weak self,weak model,weak window] scroll in
                        guard let self,let model,let window,model.inspectorVisible,model.effectiveDiffMode=="source",self.identity(model)==scope else{return true}
                        guard let content=window.contentView,workspaceLayoutMarkers(in:content).contains(where:{$0.identifier?.rawValue=="Reviset.workbook.cellDetails" && !$0.isHiddenOrHasHiddenAncestor && !$0.visibleRect.isEmpty}) else{return false}
                        guard let table=scroll.documentView as? NSTableView,let owner=table.dataSource as? WorkbookGrid.Coordinator else{return true}
                        let before=owner.parent.pane=="before",occurrence=before ? model.beforeID:model.afterID,sheet=before ? model.beforeSheetID:model.afterSheetID
                        guard owner.parent.keyboardEnabled,!scroll.isHiddenOrHasHiddenAncestor,!scroll.visibleRect.isEmpty,["before","after"].contains(owner.parent.pane),owner.parent.revealIntent==[model.scope,occurrence,sheet,String(model.revealGeneration)].joined(separator:"|"),let coordinate=model.paneCoordinate(before:before),owner.parent.selectedRow==coordinate.row,owner.parent.selectedColumn==coordinate.column,let column=table.tableColumns.firstIndex(where:{$0.identifier.rawValue==String(coordinate.column)}) else{return true}
                        scroll.revealColumnToRightOfGutter(column)
                        // A user-sized column may be wider than its viewport.
                        // The explicit attempt still finishes here.
                        return true
                    }
                } else {for child in view.subviews {install(child)}}
            }
            install(content)
            model.openCellDetails()
            WorkspacePreferredGeometry.requestCompletion(in:window)
        }
    }
    func makeCoordinator()->Coordinator {Coordinator()}
    func makeNSView(context:Context)->NSButton {let button=NSButton(title:"",target:context.coordinator,action:#selector(Coordinator.open(_:)));button.bezelStyle = .rounded;button.identifier=NSUserInterfaceItemIdentifier("Reviset.workbook.cellDetailsAction");return button}
    func updateNSView(_ button:NSButton,context:Context) {context.coordinator.model=model;button.title=L("workbook.action.cellDetails");button.font = .systemFont(ofSize:readability.pointSize(.body));button.setAccessibilityLabel(button.title);button.isEnabled=model.canOpenCellDetails}
}
struct WorkbookSourceScopeCaption:NSViewRepresentable {
    @ObservedObject private var readability=ReadabilityPreferences.shared
    let text:String
    func makeNSView(context:Context)->NSTextField {
        let field=NSTextField(wrappingLabelWithString:"");field.identifier=NSUserInterfaceItemIdentifier("Reviset.workbook.queryEventScopeCopy");field.textColor = .secondaryLabelColor;field.setContentHuggingPriority(.defaultLow,for:.horizontal);return field
    }
    func updateNSView(_ field:NSTextField,context:Context) {field.stringValue=text;field.font = .systemFont(ofSize:readability.pointSize(.caption));field.setAccessibilityLabel(text);field.invalidateIntrinsicContentSize()}
    static func finiteWidth(_ proposed:CGFloat?)->CGFloat {max(1,proposed.flatMap{$0.isFinite ? $0:nil} ?? 280)}
    func sizeThatFits(_ proposal:ProposedViewSize,nsView:NSTextField,context:Context)->CGSize? {
        let width=Self.finiteWidth(proposal.width)
        nsView.preferredMaxLayoutWidth=width
        let height=nsView.cell?.cellSize(forBounds:NSRect(x:0,y:0,width:width,height:CGFloat.greatestFiniteMagnitude)).height ?? nsView.fittingSize.height
        return CGSize(width:width,height:ceil(max(1,height))+2)
    }
}
private struct WorkbookInspector: View {
    @State private var language = LanguagePreferences.shared
    @ObservedObject var model: WorkbookModel
    var body: some View {
        ScrollView {
            VStack(alignment:.leading,spacing:15) {
                HStack { Text(L("workbook.inspector.title")).readableFont(.headline); Spacer(); if model.selectedRow > 0 { Text(WorkbookGrid.address(model.selectedRow,model.selectedColumn)).readableFont(.headline, design: .monospaced) } }
                Text(L("workbook.cell.storedOnly")).readableFont(.caption, weight: .medium).foregroundStyle(.orange)
                Text(verbatim:L("workbook.cell.dateBeforePrefix") + WorkbookLabels.dateSystem(model.revision(model.beforeID)["date_system"].string) + L("workbook.cell.dateAfterPrefix") + WorkbookLabels.dateSystem(model.revision(model.afterID)["date_system"].string)).readableFont(.caption).foregroundStyle(.secondary)
                if model.loadingCell { ProgressView(L("workbook.status.loadingCell")) }
                else if !model.cellFailure.isEmpty {
                    Text(verbatim:model.cellFailure).readableFont(.caption).foregroundStyle(.red)
                    if model.cellHistoryAnchor != nil { Button(model.cellTextOffset > 0 ? L("workbook.action.reloadSourceStart") : L("workbook.action.reloadCellSource")) { Task { await model.loadSelectedCells() } }.disabled(!model.ready) }
                }
                else if model.showingSheetMetadata {Text(L("workbook.cell.metadataEvent")).readableFont(.caption).foregroundStyle(.secondary)}
                else if model.selectedRow == 0, model.selectedChangeID.isEmpty { Text(L("workbook.cell.selectPrompt")).foregroundStyle(.secondary) }
                else { cellSection((model.readingSingleVersion ? L("doc.common.source")+" · ":L("workbook.pane.beforePrefix")) + model.versionLabel(model.beforeID),cell:model.beforeCell); if !model.readingSingleVersion {Divider(); cellSection(L("workbook.pane.afterPrefix") + model.versionLabel(model.afterID),cell:model.afterCell)} }
                if !model.selectedChange.isNull {
                    Divider(); Text(L("workbook.cell.changeMethod")).readableFont(.headline)
                    Text(verbatim:WorkbookLabels.kind(model.selectedChange["kind"].string)).readableFont(.callout)
                    Text(verbatim:WorkbookLabels.association(model.selectedChange["association"].string)).readableFont(.caption, weight: .medium)
                    Text(verbatim:WorkbookLabels.method(model.selectedChange["alignment_method"].string)).readableFont(.caption).textSelection(.enabled)
                    Text(verbatim:WorkbookLabels.description(model.selectedChange)).readableFont(.caption)
                    Text(L("workbook.cell.inferenceWarning")).readableFont(.caption).foregroundStyle(.secondary)
                }
                if model.selectedRow > 0 {
                    Button(L("workbook.action.cellHistory")) { Task { await model.loadCellHistory() } }.disabled(!model.ready || model.loadingCell || model.loadingHistory)
                    if model.loadingHistory { ProgressView(L("workbook.status.loadingHistory")).controlSize(.small) }
                    if !model.cellHistoryFailure.isEmpty { Text(verbatim:model.cellHistoryFailure).readableFont(.caption).foregroundStyle(.red) }
                    if !model.cellHistoryMessage.isEmpty { Text(verbatim:model.cellHistoryMessage).readableFont(.caption).foregroundStyle(.secondary) }
                    HStack {
                        if !model.cellHistoryPreviousCursors.isEmpty { Button(L("workbook.paging.historyPrevious")) { Task { await model.loadCellHistory(previous:true) } } }
                        if !model.cellHistoryCursor.isEmpty { Button(L("workbook.paging.historyNext")) { Task { await model.loadCellHistory(next:true) } } }
                    }.disabled(!model.ready || model.loadingCell || model.loadingHistory)
                    if !model.cellHistory.isEmpty { Text(L("workbook.history.page",.integer(model.cellHistoryPageNumber))).readableFont(.caption2).foregroundStyle(.secondary) }
                    ForEach(Array(model.cellHistory.enumerated()),id:\.offset) { _, event in
                        VStack(alignment:.leading,spacing:3) {
                            Text(verbatim:model.versionLabel(event["revision_occurrence_id"].string)).lineLimit(2)
                            Text(verbatim:(event["cell"]["address"].string.isEmpty ? event["address"].string : event["cell"]["address"].string) + (event["cell"].isNull ? "" : " · " + event["cell"]["value"].string))
                            Text(verbatim:WorkbookLabels.availability(event["availability"].string) + " · " + WorkbookLabels.association(event["association"].string))
                            Text(verbatim:WorkbookLabels.method(event["alignment_method"].string))
                        }.readableFont(.caption).textSelection(.enabled)
                    }
                }
                Divider()
                WorkbookSheetMetadata(title:L("workbook.sheet.beforeMetadata"),sheet:model.sheet(model.beforeID,model.beforeSheetID))
                WorkbookSheetMetadata(title:L("workbook.sheet.afterMetadata"),sheet:model.sheet(model.afterID,model.afterSheetID))
                WorkbookCoverageView(gaps:model.coverage,total:model.report["coverage_gap_count"].int,truncated:model.report["coverage_truncated"].bool,revisions:model.revisions)
            }.padding(14).frame(maxWidth:.infinity,alignment:.leading)
        }.background(Color(nsColor:.controlBackgroundColor)).background(WorkspaceLayoutMarker(name:"Reviset.workbook.cellDetails"))
    }
    private func cellSection(_ title: String,cell: JSON) -> some View {
        WorkbookCellDetail(title:title,cell:cell,textOffset:model.cellTextOffset,nextTextOffset:model.cellTextNext,canPage:model.ready && !model.loadingCell,onTextPage:{ offset in Task { await model.loadSelectedCells(offset:offset) } })
    }
}
private struct WorkbookCellDetail: View {
    @State private var language = LanguagePreferences.shared
    let title: String
    let cell: JSON
    let textOffset: Int
    let nextTextOffset: Int?
    let canPage: Bool
    let onTextPage: (Int) -> Void
    var body: some View {
        VStack(alignment:.leading,spacing:7) {
            Text(verbatim:title).readableFont(.headline).lineLimit(2)
            if cell.isNull { Text(L("workbook.cell.noObservation")).readableFont(.caption).foregroundStyle(.secondary) }
            else {
                Text(verbatim:cell["address"].string + " · " + WorkbookLabels.valueType(cell["value_type"].string)).readableFont(.caption, design: .monospaced)
                if !cell["source_range"].string.isEmpty { Text(verbatim:L("workbook.cell.blankRangePrefix") + cell["source_range"].string).readableFont(.caption).textSelection(.enabled) }
                if !cell["difference_range"].string.isEmpty { Text(verbatim:L("workbook.cell.differenceRangePrefix") + cell["difference_range"].string).readableFont(.caption).textSelection(.enabled) }
                if cell["formula_interpretation"].string == "unresolved" { Text(L("workbook.cell.unresolvedFormula")).readableFont(.caption, weight: .medium).foregroundStyle(.orange) }
                rawDetail(cell["formula_interpretation"].string == "unresolved" ? L("workbook.cell.unresolvedValue") : cell["formula"].isNull ? L("workbook.cell.input") : L("workbook.cell.result"),field:"value")
                if !cell["formula"].isNull { rawDetail(L("workbook.cell.formula"),field:"formula"); Text(L("workbook.cell.formulaNotExecuted")).readableFont(.caption2).foregroundStyle(.secondary) }
                if textOffset > 0 || ["value","formula","number_format"].contains(where:{cell["text_continuations"][$0]["state"].string == "truncated"}) {
                    HStack {
                        if textOffset > 0 { Button(L("workbook.action.sourceStartBoth")) { onTextPage(0) } }
                        if let nextTextOffset { Button(L("workbook.action.sourceNextBoth")) { onTextPage(nextTextOffset) } }
                    }.disabled(!canPage)
                    Text(L("workbook.cell.sourcePaging")).readableFont(.caption2).foregroundStyle(.secondary)
                }
                if !cell["number_format"].isNull { rawDetail(L("workbook.cell.numberFormat"),field:"number_format") }
                if cell["hidden_row"].bool || cell["hidden_column"].bool { Label((cell["hidden_row"].bool ? L("workbook.cell.hiddenRowPrefix") : "") + (cell["hidden_column"].bool ? L("workbook.cell.hiddenColumn") : ""),systemImage:"eye.slash").readableFont(.caption).foregroundStyle(.orange) }
                if !cell["style"].dictionary.isEmpty { detail(L("workbook.cell.style"),cell["style"].dictionary.keys.sorted().map { $0 + ": " + cell["style"][$0].string }.joined(separator:"\n")) }
                if cell["style_truncated"].bool { Text(L("workbook.cell.styleTruncated")).readableFont(.caption).foregroundStyle(.orange) }
                detail(L("workbook.cell.sourceRef"),cell["source_ref"].string)
            }
        }
    }
    private func sourceLabel(_ label: String,field: String) -> String {
        let continuation = cell["text_continuations"][field]
        if continuation["state"].string == "truncated" {
            let start = continuation["offset"].int,end = start+cell[field].string.utf16.count
            return L("workbook.cell.partialSource",.verbatim(label),.integer(start),.integer(end),.integer(continuation["total_length"].int))
        }
        return label
    }
    private func rawDetail(_ label: String,field: String) -> some View {
        VStack(alignment:.leading,spacing:4) {
            Text(verbatim:sourceLabel(label,field:field)).readableFont(.caption, weight: .medium).foregroundStyle(.secondary)
            if let status = sourceStatus(field) {
                Text(verbatim:status).readableFont(.caption).foregroundStyle(.secondary)
            } else {
                Text(verbatim:cell[field].string).readableFont(.caption, design: .monospaced).textSelection(.enabled).fixedSize(horizontal:false,vertical:true)
            }
            if cell["text_continuations"][field]["state"].string == "truncated",!cell[field].string.isEmpty {
                Text(cell["text_continuations"][field]["next_offset"].isNull ? L("workbook.cell.sourceLastChunk") : L("workbook.cell.sourceMoreChunks")).readableFont(.caption2, weight: .medium).foregroundStyle(.orange)
            }
        }.background(WorkspaceLayoutMarker(name:"Reviset.workbook.inspector.raw."+field))
    }
    private func sourceStatus(_ field: String) -> String? {
        let raw = cell[field],continuation = cell["text_continuations"][field]
        if raw.isNull { return L("workbook.cell.valueAbsent") }
        if raw.string.isEmpty {
            if continuation["total_length"].int > 0 { return L("workbook.cell.valueEarlier") }
            return L("workbook.cell.emptyString")
        }
        return nil
    }
    private func detail(_ label: String, _ value: String) -> some View { VStack(alignment:.leading,spacing:3) { Text(verbatim:label).readableFont(.caption, weight: .medium).foregroundStyle(.secondary); Text(verbatim:value).readableFont(.caption, design: .monospaced).textSelection(.enabled).fixedSize(horizontal:false,vertical:true) } }
}
private struct WorkbookSheetMetadata: View {
    @State private var language = LanguagePreferences.shared
    let title: String
    let sheet: JSON
    var body: some View {
        if !sheet.isNull {
            VStack(alignment:.leading,spacing:5) {
                Text(verbatim:title).readableFont(.caption, weight: .semibold)
                Text(verbatim:sheet["name"].string + (sheet["hidden"].bool ? L("workbook.sheet.hiddenNameSuffix") : "")).readableFont(.caption)
                Text(L("workbook.sheet.metadataCounts",.count(sheet["merge_count"].int),.count(sheet["row_metadata_count"].int),.count(sheet["column_metadata_count"].int))).readableFont(.caption).foregroundStyle(.secondary)
                if sheet["blank_style_range_count"].int > 0 { Text(L("workbook.sheet.blankRanges",.count(sheet["blank_style_range_count"].int))).readableFont(.caption).foregroundStyle(.secondary) }
                ForEach(Array(sheet["row_metadata"].array.filter { $0["hidden"].bool }.prefix(10).enumerated()),id:\.offset) { _, range in Text(L("workbook.sheet.hiddenRows",.integer(range["start"].int),.integer(range["end"].int))).readableFont(.caption) }
                ForEach(Array(sheet["column_metadata"].array.filter { $0["hidden"].bool }.prefix(10).enumerated()),id:\.offset) { _, range in Text(L("workbook.sheet.hiddenColumns",.verbatim(WorkbookGrid.columnLabel(range["start"].int)),.verbatim(WorkbookGrid.columnLabel(range["end"].int)))).readableFont(.caption) }
                if !sheet["merges"].array.isEmpty { Text(verbatim:L("workbook.sheet.mergesPrefix") + sheet["merges"].array.map(\.string).joined(separator:", ")).readableFont(.caption).textSelection(.enabled) }
                if sheet["metadata_truncated"].bool { Text(L("workbook.sheet.metadataTruncated")).readableFont(.caption).foregroundStyle(.secondary) }
            }
        }
    }
}
private struct WorkbookCoverageView: View {
    @State private var language = LanguagePreferences.shared
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
        if revisions.count > 1,occurrences == Set(revisions.map { $0["revision_occurrence_id"].string }),entry.observations.allSatisfy({$0["sheet_id"].string.isEmpty && $0["address"].string.isEmpty}) { return L("workbook.coverage.allVersions",.count(revisions.count)) }
        var labels: [String] = [],seen = Set<String>()
        for observation in entry.observations {
            let occurrence = observation["revision_occurrence_id"].string,sheetID = observation["sheet_id"].string,address = observation["address"].string
            let revision = revisions.first { $0["revision_occurrence_id"].string == occurrence }
            var parts: [String] = []
            if let revision { parts.append("v\(revision["index"].int+1)") }
            else if !occurrence.isEmpty { parts.append(L("workbook.coverage.versionPrefix") + String(occurrence.suffix(8))) }
            if !sheetID.isEmpty { parts.append(revision?["sheets"].array.first(where:{$0["sheet_id"].string == sheetID})?["name"].string ?? L("workbook.coverage.sheetPrefix") + String(sheetID.suffix(8))) }
            if !address.isEmpty { parts.append(address) }
            let label = parts.isEmpty ? L("workbook.coverage.common") : parts.joined(separator:" · ")
            if seen.insert(label).inserted { labels.append(label) }
        }
        return L("workbook.coverage.appliesPrefix") + labels.prefix(8).joined(separator:", ") + (labels.count > 8 ? LC("workbook.coverage.moreLocations",labels.count-8) : "")
    }
    var body: some View {
        VStack(alignment:.leading,spacing:7) {
            Text(L("workbook.coverage.title")).readableFont(.headline)
            Text(L("workbook.coverage.detail")).readableFont(.caption).foregroundStyle(.secondary)
            if truncated || gaps.count > 50 { Text(L("workbook.coverage.shown",.count(min(50,gaps.count)),.count(total))).readableFont(.caption).foregroundStyle(.orange) }
            if gaps.isEmpty { Text(L("workbook.coverage.none")).readableFont(.caption).foregroundStyle(.secondary) }
            if !gaps.isEmpty { Text(L("workbook.coverage.grouped",.count(min(50,gaps.count)),.count(entries.count))).readableFont(.caption).foregroundStyle(.secondary) }
            ForEach(entries) { entry in
                let label = WorkbookLabels.coverage(entry.feature)
                VStack(alignment:.leading,spacing:3) {
                    Text(verbatim:label.title).readableFont(.caption, weight: .medium)
                    // Stored reason text and feature identifiers are source evidence,
                    // not localization keys. Retain the exact bytes in either UI language.
                    Text(L("workbook.coverage.sourceReason")).readableFont(.caption2).foregroundStyle(.secondary)
                    Text(verbatim:entry.reason).readableFont(.caption).textSelection(.enabled)
                    Text(verbatim:entry.feature).readableFont(.caption2, design: .monospaced).foregroundStyle(.secondary)
                    if let detail = label.detail {
                        DisclosureGroup(L("workbook.coverage.sourceEvidence")) {
                            Text(verbatim:detail).readableFont(.caption).foregroundStyle(.secondary)
                        }.readableFont(.caption)
                    }
                    Text(verbatim:provenance(entry)).readableFont(.caption2).foregroundStyle(.secondary)
                }
            }
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
        guard folder.path.hasPrefix(resourceRoot.path + "/"),manifest.resolvingSymlinksInPath().deletingLastPathComponent() == folder else { throw BridgeError(code:"WORKBOOK_DEMO_PATH",message:UIMessage("workbook.error.demoPath")) }
        let attributes = try FileManager.default.attributesOfItem(atPath:manifest.path)
        guard attributes[.type] as? FileAttributeType == .typeRegular,((attributes[.size] as? NSNumber)?.intValue ?? 65_537) <= 65_536 else { throw BridgeError(code:"WORKBOOK_DEMO_MANIFEST",message:UIMessage("workbook.error.demoRead")) }
        let value = JSON(try JSONSerialization.jsonObject(with:Data(contentsOf:manifest)))
        let title = value["title"].string, revisions = value["revisions"].array
        guard !title.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty,title.count <= 200,revisions.count == 3,Set(revisions.map { $0["path"].string }).count == 3 else { throw BridgeError(code:"WORKBOOK_DEMO_MANIFEST",message:UIMessage("workbook.error.demoManifest")) }
        let rows = try revisions.map { revision -> WorkbookImportRow in
            let name = revision["path"].string,label = revision["label"].string
            guard name.range(of:"^v[1-3]\\.xlsx$",options:.regularExpression) != nil,!label.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty,label.count <= 200 else { throw BridgeError(code:"WORKBOOK_DEMO_MANIFEST",message:UIMessage("workbook.error.demoNames")) }
            let url = folder.appendingPathComponent(name)
            guard url.resolvingSymlinksInPath().deletingLastPathComponent() == folder else { throw BridgeError(code:"WORKBOOK_DEMO_PATH",message:UIMessage("workbook.error.demoPath")) }
            var row = try selected(url); row.label = label; return row
        }
        return (title,rows)
    }
    static func selected(_ url: URL) throws -> WorkbookImportRow {
        guard ["xlsx","ods","csv"].contains(url.pathExtension.lowercased()) else { throw BridgeError(code:"WORKBOOK_FORMAT",message:UIMessage("workbook.error.format")) }
        let size = (try FileManager.default.attributesOfItem(atPath:url.path)[.size] as? NSNumber)?.intValue ?? 0
        guard size <= 64*1024*1024 else { throw BridgeError(code:"WORKBOOK_LIMIT",message:UIMessage("workbook.error.fileLimit")) }
        let identity = try ImportFileIdentity.capture(url)
        guard identity.bytes <= 64*1024*1024 else { throw BridgeError(code:"WORKBOOK_LIMIT",message:UIMessage("workbook.error.fileLimit")) }
        return WorkbookImportRow(label:url.deletingPathExtension().lastPathComponent,url:url,identity:identity)
    }
}
struct WorkbookImportSheet: View {
    // Keep the opening route for this sheet's lifetime, including parent redraws.
    @State private var intent:ImportIntent
    @State private var language = LanguagePreferences.shared
    @ObservedObject var model: WorkbookModel
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var titleEdited = false
    @State private var rows: [WorkbookImportRow] = []
    @State private var choosing = false
    @State private var saving = false
    @State private var failureContent = UIMessage.raw("")
    private var failure: String { failureContent.text }
    init(model: WorkbookModel, intent:ImportIntent = .ordinary, initialTitle: String? = nil, initialRows: [WorkbookImportRow] = []) {
        self.model = model
        _intent = State(initialValue:intent)
        _title = State(initialValue:initialTitle ?? "")
        _titleEdited = State(initialValue:initialTitle != nil)
        _rows = State(initialValue:initialRows)
    }
    private var locked: Bool { choosing || saving }
    // An untouched default follows the display language. Once edited, including
    // explicitly cleared, the draft is user data and remains verbatim.
    private var effectiveTitle: String { titleEdited ? title : L("workbook.import.defaultTitle") }
    private var titleBinding: Binding<String> { Binding(get:{effectiveTitle},set:{value in guard titleEdited || value != effectiveTitle else{return};title=value;titleEdited=true}) }
    var body: some View {
        VStack(alignment:.leading,spacing:16) {
            HStack { Text(L("workbook.import.title")).readableFont(.title2, weight: .semibold); Spacer(); Button(L("workbook.action.close")) { dismiss() }.keyboardShortcut(.cancelAction).disabled(locked) }
            Text(L("workbook.import.detail")).readableFont(.callout).foregroundStyle(.secondary)
            if intent == .newComparison {Text(L("git.importComparisonMinimum")).readableFont(.callout).foregroundStyle(.secondary)}
            TextField(L("workbook.import.projectName"),text:titleBinding).accessibilityIdentifier("Docver.workbook.import.title").textFieldStyle(.roundedBorder).disabled(locked)
            Button(L("workbook.import.choose")) { choose() }.disabled(locked)
            List {
                ForEach(Array(rows.enumerated()),id:\.element.id) { index, row in
                    HStack {
                        Text("v\(index+1)").readableFont(.caption).foregroundStyle(.secondary)
                        VStack(alignment:.leading,spacing:3) { TextField(L("workbook.import.versionName"),text:Binding(get:{rows.indices.contains(index) ? rows[index].label : ""},set:{if rows.indices.contains(index) { rows[index].label = $0 }})).accessibilityIdentifier("Docver.workbook.import.version." + row.id.uuidString); Text(verbatim:row.url.lastPathComponent + " · " + LC("workbook.import.bytes",row.identity.bytes)).readableFont(.caption).foregroundStyle(.secondary) }
                        Button { move(index,-1) } label: { Image(systemName:"chevron.up") }.disabled(index == 0 || locked).accessibilityLabel(L("workbook.import.moveUp"))
                        Button { move(index,1) } label: { Image(systemName:"chevron.down") }.disabled(index == rows.count-1 || locked).accessibilityLabel(L("workbook.import.moveDown"))
                        Button { if rows.indices.contains(index) { rows.remove(at:index) } } label: { Image(systemName:"xmark") }.disabled(locked).accessibilityLabel(L("workbook.import.remove"))
                    }.disabled(locked)
                }
            }.frame(minHeight:220,maxHeight:360)
            Text(L("workbook.import.limits")).readableFont(.caption).foregroundStyle(.secondary)
            if !failure.isEmpty { Text(verbatim:failure).readableFont(.caption).foregroundStyle(.red) }
            HStack { if locked { ProgressView().controlSize(.small); Text(choosing ? L("workbook.import.checkingHash") : L("workbook.import.importing")).readableFont(.caption) }; Spacer(); Button(L("workbook.import.start")) { Task { await create() } }.buttonStyle(.borderedProminent).disabled(locked || rows.count<intent.minimumVersionEntries || rows.count > 100 || effectiveTitle.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty || rows.contains { $0.label.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty }) }
        }.padding(24).frame(width:840)
    }
    private func move(_ index: Int, _ by: Int) { let target = index+by; guard rows.indices.contains(index),rows.indices.contains(target) else { return }; rows.swapAt(index,target) }
    private func choose() {
        let panel = NSOpenPanel(); panel.allowsMultipleSelection = true; panel.canChooseDirectories = false
        panel.allowedContentTypes = ["xlsx","ods","csv"].compactMap { UTType(filenameExtension:$0) }
        guard panel.runModal() == .OK else { return }
        let urls = panel.urls
        guard rows.count+urls.count <= 100 else { failureContent = UIMessage("workbook.error.versionLimit"); return }
        choosing = true; failureContent = .raw("")
        Task {
            do { let selected = try await Task.detached(priority:.userInitiated) { try urls.map { try WorkbookImportRow.selected($0) } }.value; rows += selected }
            catch { failureContent = bridgeErrorMessage(error) }
            choosing = false
        }
    }
    private func create() async {
        saving = true; failureContent = .raw("")
        do { try await model.create(title:effectiveTitle,rows:rows,intent:intent); dismiss() } catch { failureContent = bridgeErrorMessage(error) }
        saving = false
    }
}
private struct WorkbookPublishSheet: View {
    @State private var language = LanguagePreferences.shared
    @ObservedObject var model: WorkbookModel
    @Environment(\.dismiss) private var dismiss
    @State private var label = ""
    @State private var reason = ""
    @State private var failureContent = UIMessage.raw("")
    private var failure: String { failureContent.text }
    @State private var saving = false
    var body: some View {
        VStack(alignment:.leading,spacing:16) {
            Text(L("workbook.release.pinTitle")).readableFont(.title2, weight: .semibold)
            Text(L("workbook.release.pinDetail")).foregroundStyle(.secondary)
            Text(verbatim:model.reportID).readableFont(.caption, design: .monospaced).textSelection(.enabled)
            TextField(L("workbook.release.namePlaceholder"),text:$label).textFieldStyle(.roundedBorder)
            Text(L("workbook.release.reason")).readableFont(.headline)
            TextEditor(text:$reason).frame(height:100).border(Color.secondary.opacity(0.3))
            if !failure.isEmpty { Text(verbatim:failure).readableFont(.caption).foregroundStyle(.red) }
            HStack { Button(L("workbook.action.cancel")) { dismiss() }.keyboardShortcut(.cancelAction); Spacer(); if saving { ProgressView().controlSize(.small) }; Button(L("workbook.release.pinAction")) { Task { saving = true; do { try await model.publish(label:label,reason:reason); dismiss() } catch { failureContent = bridgeErrorMessage(error) }; saving = false } }.buttonStyle(.borderedProminent).disabled(saving || label.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty || reason.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty) }
        }.padding(24).frame(width:620).disabled(saving)
    }
}

@MainActor private enum WorkbookLabels {
    static func valueType(_ value: String) -> String {
        let label: String
        switch value {
        case "blank": label = L("workbook.valueType.blank")
        case "string": label = L("workbook.valueType.string")
        case "number": label = L("workbook.valueType.number")
        case "boolean": label = L("workbook.valueType.boolean")
        case "date": label = L("workbook.valueType.date")
        case "time": label = L("workbook.valueType.time")
        case "error": label = L("workbook.valueType.error")
        default: return value.isEmpty ? "" : L("workbook.code.unknown",.verbatim(value))
        }
        return L("workbook.code.label",.verbatim(label),.verbatim(value))
    }
    static func dateSystem(_ value: String) -> String {
        let label: String
        switch value {
        case "1900": label = L("workbook.dateSystem.1900")
        case "1904": label = L("workbook.dateSystem.1904")
        case "iso8601": label = L("workbook.dateSystem.iso8601")
        case "unknown": label = L("workbook.dateSystem.unknown")
        default: return value.isEmpty ? "" : L("workbook.code.unknown",.verbatim(value))
        }
        return L("workbook.code.label",.verbatim(label),.verbatim(value))
    }

    static func coverage(_ feature: String) -> (title: String,detail: String?) {
        switch feature {
        case "advanced_styles": return (L("workbook.coverage.feature.advanced_styles"),L("workbook.coverage.feature.advanced_styles.detail"))
        case "array_formulas": return (L("workbook.coverage.feature.array_formulas"),L("workbook.coverage.feature.array_formulas.detail"))
        case "blank_range_formula_interpretation": return (L("workbook.coverage.feature.blank_range_formula_interpretation"),L("workbook.coverage.feature.blank_range_formula_interpretation.detail"))
        case "calculation_metadata": return (L("workbook.coverage.feature.calculation_metadata"),L("workbook.coverage.feature.calculation_metadata.detail"))
        case "cell_metadata": return (L("workbook.coverage.feature.cell_metadata"),L("workbook.coverage.feature.cell_metadata.detail"))
        case "cell_protection": return (L("workbook.coverage.feature.cell_protection"),L("workbook.coverage.feature.cell_protection.detail"))
        case "charts": return (L("workbook.coverage.feature.charts"),L("workbook.coverage.feature.charts.detail"))
        case "comments": return (L("workbook.coverage.feature.comments"),L("workbook.coverage.feature.comments.detail"))
        case "conditional_formatting": return (L("workbook.coverage.feature.conditional_formatting"),L("workbook.coverage.feature.conditional_formatting.detail"))
        case "covered_cell_content": return (L("workbook.coverage.feature.covered_cell_content"),L("workbook.coverage.feature.covered_cell_content.detail"))
        case "cross_format_blank_formatting": return (L("workbook.coverage.feature.cross_format_blank_formatting"),L("workbook.coverage.feature.cross_format_blank_formatting.detail"))
        case "cross_format_capabilities": return (L("workbook.coverage.feature.cross_format_capabilities"),L("workbook.coverage.feature.cross_format_capabilities.detail"))
        case "cross_format_date_representation": return (L("workbook.coverage.feature.cross_format_date_representation"),L("workbook.coverage.feature.cross_format_date_representation.detail"))
        case "data_validation": return (L("workbook.coverage.feature.data_validation"),L("workbook.coverage.feature.data_validation.detail"))
        case "date_epoch": return (L("workbook.coverage.feature.date_epoch"),L("workbook.coverage.feature.date_epoch.detail"))
        case "defined_names": return (L("workbook.coverage.feature.defined_names"),L("workbook.coverage.feature.defined_names.detail"))
        case "display_layout": return (L("workbook.coverage.feature.display_layout"),L("workbook.coverage.feature.display_layout.detail"))
        case "embedded_objects": return (L("workbook.coverage.feature.embedded_objects"),L("workbook.coverage.feature.embedded_objects.detail"))
        case "external_links": return (L("workbook.coverage.feature.external_links"),L("workbook.coverage.feature.external_links.detail"))
        case "external_relationships": return (L("workbook.coverage.feature.external_relationships"),L("workbook.coverage.feature.external_relationships.detail"))
        case "formula_interpretation": return (L("workbook.coverage.feature.formula_interpretation"),L("workbook.coverage.feature.formula_interpretation.detail"))
        case "inferred_correspondence": return (L("workbook.coverage.feature.inferred_correspondence"),L("workbook.coverage.feature.inferred_correspondence.detail"))
        case "missing_error_cache": return (L("workbook.coverage.feature.missing_error_cache"),L("workbook.coverage.feature.missing_error_cache.detail"))
        case "missing_formula_cache": return (L("workbook.coverage.feature.missing_formula_cache"),L("workbook.coverage.feature.missing_formula_cache.detail"))
        case "number_format": return (L("workbook.coverage.feature.number_format"),L("workbook.coverage.feature.number_format.detail"))
        case "ods_style_family": return (L("workbook.coverage.feature.ods_style_family"),L("workbook.coverage.feature.ods_style_family.detail"))
        case "phonetic_guides": return (L("workbook.coverage.feature.phonetic_guides"),L("workbook.coverage.feature.phonetic_guides.detail"))
        case "rich_text": return (L("workbook.coverage.feature.rich_text"),L("workbook.coverage.feature.rich_text.detail"))
        case "rich_text_extensions": return (L("workbook.coverage.feature.rich_text_extensions"),L("workbook.coverage.feature.rich_text_extensions.detail"))
        case "row_column_default_styles": return (L("workbook.coverage.feature.row_column_default_styles"),L("workbook.coverage.feature.row_column_default_styles.detail"))
        case "scripts_events": return (L("workbook.coverage.feature.scripts_events"),L("workbook.coverage.feature.scripts_events.detail"))
        case "shared_array_formulas": return (L("workbook.coverage.feature.shared_array_formulas"),L("workbook.coverage.feature.shared_array_formulas.detail"))
        case "stored_formula_results": return (L("workbook.coverage.feature.stored_formula_results"),L("workbook.coverage.feature.stored_formula_results.detail"))
        case "style_application": return (L("workbook.coverage.feature.style_application"),L("workbook.coverage.feature.style_application.detail"))
        case "unknown_calc_value_type": return (L("workbook.coverage.feature.unknown_calc_value_type"),L("workbook.coverage.feature.unknown_calc_value_type.detail"))
        case "untyped_csv": return (L("workbook.coverage.feature.untyped_csv"),L("workbook.coverage.feature.untyped_csv.detail"))
        case "very_hidden_sheet": return (L("workbook.coverage.feature.very_hidden_sheet"),L("workbook.coverage.feature.very_hidden_sheet.detail"))
        case "drawings": return (L("workbook.coverage.feature.drawings"),L("workbook.coverage.feature.drawings.detail"))
        case "pivots": return (L("workbook.coverage.feature.pivots"),L("workbook.coverage.feature.pivots.detail"))
        case "structured_tables": return (L("workbook.coverage.feature.structured_tables"),L("workbook.coverage.feature.structured_tables.detail"))
        case "connections": return (L("workbook.coverage.feature.connections"),L("workbook.coverage.feature.connections.detail"))
        case "query_tables": return (L("workbook.coverage.feature.query_tables"),L("workbook.coverage.feature.query_tables.detail"))
        case "extension_features": return (L("workbook.coverage.feature.extension_features"),L("workbook.coverage.feature.extension_features.detail"))
        case "filters": return (L("workbook.coverage.feature.filters"),L("workbook.coverage.feature.filters.detail"))
        case "protection": return (L("workbook.coverage.feature.protection"),L("workbook.coverage.feature.protection.detail"))
        default: return (L("workbook.coverage.unknownFeature",.verbatim(feature)),nil)
        }
    }

    static func description(_ change: JSON) -> String {
        let raw = change["description"].string
        switch change["kind"].string {
        case "row_position":
            let before = change["before_address"].string.drop(while:{$0.isLetter}),after = change["after_address"].string.drop(while:{$0.isLetter})
            if let from = Int(before),let to = Int(after) { return L("workbook.description.rowMove",.integer(from),.integer(to)) }
            return L("workbook.description.rowPosition")
        case "formula": return L("workbook.description.formula")
        case "stored_value": return L("workbook.description.storedValue")
        case "value_type": return L("workbook.description.valueType")
        case "cache_availability": return L("workbook.description.cache")
        case "calculation_settings": return L("workbook.description.calculationSettings")
        case "number_format": return L("workbook.description.numberFormat")
        case "style": return L("workbook.description.style")
        case "formatting_range":
            let before = change["before_blank_style_range"]["address"].string,after = change["after_blank_style_range"]["address"].string
            return L("workbook.description.blankRangePrefix") + (before.isEmpty ? L("workbook.observation.none") : before) + " → " + (after.isEmpty ? L("workbook.observation.none") : after) + L("workbook.description.blankRangeSuffix")
        case "visibility": return L("workbook.description.visibility")
        case "row_correspondence": return L("workbook.description.rowCorrespondence")
        case "cell_observation":
            if change["alignment_method"].string == "physical_blank_content_coordinate" { return L("workbook.description.blankContent") }
            if change["alignment_method"].string == "cross_format_date_representation" { return L("workbook.description.crossFormatDate") }
            if change["alignment_method"].string == "unresolved_formula_interpretation" { return L("workbook.description.unresolvedFormula") }
            return L("workbook.description.cellObservation")
        case "sheet_observation": return L("workbook.description.sheetObservation")
        case "sheet_dimensions": return L("workbook.description.dimensions")
        case "merges": return L("workbook.description.merges")
        case "sheet_name": return raw.hasPrefix("Sheet name: ") ? L("workbook.description.sheetNamePrefix") + raw.dropFirst("Sheet name: ".count) : raw
        case "sheet_position": return raw.hasPrefix("Sheet index: ") ? L("workbook.description.sheetPositionPrefix") + raw.dropFirst("Sheet index: ".count) : raw
        case "sheet_visibility": return raw.hasPrefix("Sheet hidden: ") ? L("workbook.description.sheetVisibilityPrefix") + raw.dropFirst("Sheet hidden: ".count).replacingOccurrences(of:"true",with:L("workbook.visibility.hidden")).replacingOccurrences(of:"false",with:L("workbook.visibility.visible")) : raw
        case "date_system":
            if raw.hasPrefix("Date system changed from "),let end = raw.firstIndex(of:";") {
                let transition = raw[raw.index(raw.startIndex,offsetBy:"Date system changed from ".count)..<end].replacingOccurrences(of:" to ",with:" → ")
                return L("workbook.description.dateTransition",.verbatim(transition))
            }
            return L("workbook.description.dateSystem")
        default: return raw
        }
    }
    static func availability(_ value: String) -> String { switch value { case "not_materialized": return L("workbook.availability.absent"); case "correspondence_unresolved": return L("workbook.availability.unresolved"); case "available": return L("workbook.availability.available"); default: return value.isEmpty ? "" : L("workbook.code.unknown",.verbatim(value)) } }
    static func association(_ value: String) -> String { switch value { case "exact": return L("workbook.association.exact"); case "inferred": return L("workbook.association.inferred"); case "needs_review": return L("workbook.association.review"); default: return value.isEmpty ? L("workbook.association.unresolved") : L("workbook.code.unknown",.verbatim(value)) } }
    static func method(_ value: String) -> String { switch value { case "unique_nonempty_first_column_key": return L("workbook.method.firstColumn"); case "unique_exact_row_content": return L("workbook.method.rowContent"); case "unique_exact_sheet_name": return L("workbook.method.sheetName"); case "unique_exact_sheet_content": return L("workbook.method.sheetContent"); case "physical_blank_content_coordinate": return L("workbook.method.blankContent"); case "physical_blank_formatting_range": return L("workbook.method.blankFormatting"); case "physical_row_fallback": return L("workbook.method.physicalRow"); case "unmatched_row_observation": return L("workbook.method.unmatchedRow"); case "unmatched_sheet_observation": return L("workbook.method.unmatchedSheet"); case "selected_physical_cell": return L("workbook.method.selectedCell"); case "no_unambiguous_cell_lineage": return L("workbook.method.noLineage"); default: return value.isEmpty ? "" : L("workbook.code.unknown",.verbatim(value)) } }
    static func kind(_ value: String) -> String { switch value { case "formula": return L("workbook.kind.formula"); case "cache_availability": return L("workbook.kind.cache"); case "calculation_settings": return L("workbook.kind.calculationSettings"); case "stored_value": return L("workbook.kind.storedValue"); case "value_type": return L("workbook.kind.valueType"); case "number_format": return L("workbook.kind.numberFormat"); case "style": return L("workbook.kind.style"); case "formatting_range": return L("workbook.kind.formattingRange"); case "visibility": return L("workbook.kind.visibility"); case "cell_observation": return L("workbook.kind.cellObservation"); case "row_position": return L("workbook.kind.rowPosition"); case "row_correspondence": return L("workbook.kind.rowCorrespondence"); case "sheet_name": return L("workbook.kind.sheetName"); case "sheet_position": return L("workbook.kind.sheetPosition"); case "sheet_visibility": return L("workbook.kind.sheetVisibility"); case "sheet_dimensions": return L("workbook.kind.dimensions"); case "sheet_observation": return L("workbook.kind.sheetObservation"); case "merges": return L("workbook.kind.merges"); case "date_system": return L("workbook.kind.dateSystem"); default: return value.isEmpty ? "" : L("workbook.code.unknown",.verbatim(value)) } }
}

// AppKit creates reusable cells only for visible rows. The data source is a
// bounded 100×12 physical window backed by sparse observations, never a dense
// workbook. Formula text remains plain text and is never evaluated by AppKit.
private final class WorkbookPinnedRowsView:NSView {
    let heading:Bool
    var fields:[NSTextField]=[]
    override var isFlipped:Bool {true}
    override var acceptsFirstResponder:Bool {false}
    override var canBecomeKeyView:Bool {false}
    init(heading:Bool){self.heading=heading;super.init(frame:.zero)}
    required init?(coder:NSCoder){fatalError("init(coder:) is unavailable")}
    override func hitTest(_ point:NSPoint)->NSView? {super.hitTest(point)==nil ? nil:self}
    override func mouseDown(with event:NSEvent) {
        guard !heading,let scroll=superview as? WorkbookTableScrollView,scroll.sourceKeyboardEnabled,let table=scroll.documentView as? NSTableView,let owner=table.dataSource as? WorkbookGrid.Coordinator else{return}
        let row=table.row(at:table.convert(event.locationInWindow,from:nil))
        owner.selectPhysicalRow(row)
    } // Covered data cells never receive gutter clicks.
    override func scrollWheel(with event:NSEvent) {superview?.scrollWheel(with:event)}
    override func draw(_ dirtyRect:NSRect){NSColor.controlBackgroundColor.setFill();bounds.fill();NSColor.gridColor.setFill();NSRect(x:max(0,bounds.width-1),y:0,width:1,height:bounds.height).fill()}
    func synchronize(_ table:NSTableView,rowStart:Int,pane:String){
        let range=table.rows(in:table.visibleRect),start=range.location==NSNotFound ? 0:range.location,count=heading ? 1:min(max(0,table.numberOfRows-start),range.length)
        let pointSize=table.tableColumns.first?.headerCell.font?.pointSize ?? 14
        let font=NSFont.monospacedDigitSystemFont(ofSize:pointSize,weight:.regular)
        let textHeight=ceil(font.ascender-font.descender+font.leading)+2
        while fields.count<count {let field=NSTextField(labelWithString:"");field.alignment = .right;field.isEditable=false;field.isSelectable=false;addSubview(field);fields.append(field)}
        for (index,field) in fields.enumerated(){
            field.isHidden=index>=count
            guard index<count else{continue}
            let local=start+index,physical=rowStart+local,text=heading ? L("workbook.grid.rowHeader"):String(physical)
            field.stringValue=text;field.identifier=NSUserInterfaceItemIdentifier(heading ? "Reviset.workbook.rowGutterHeader."+pane:"Reviset.workbook.rowGutter."+pane+".row.\(physical)");field.setAccessibilityLabel(heading ? text:L("workbook.grid.rowAX",.integer(physical)))
            let row=heading ? bounds:table.convert(table.rect(ofRow:local),to:self)
            field.font=font;field.frame=NSRect(x:6,y:row.midY-textHeight/2,width:max(0,bounds.width-12),height:textHeight)
            field.textColor = !heading && table.selectedRow==local ? .labelColor:.secondaryLabelColor
        }
    }
}
@MainActor final class WorkbookTableScrollView: NSScrollView,WorkspacePreferredGeometryObserver {
    private var remainingReadinessSettles=0
    var pendingCellDetailsReveal:((WorkbookTableScrollView)->Bool)? {
        didSet {if pendingCellDetailsReveal != nil {remainingReadinessSettles=2;WorkspacePreferredGeometry.watch(self)}}
    }
    var hasPendingPreferredGeometryAction:Bool {pendingCellDetailsReveal != nil}
    func workspacePreferredGeometryDidSettle() {
        guard let pending=pendingCellDetailsReveal else{return}
        remainingReadinessSettles -= 1
        if pending(self) || remainingReadinessSettles<=0 {pendingCellDetailsReveal=nil}
        else {
            // One extra geometry tail allows the action's SwiftUI inspector
            // marker to mount. Missing readiness cannot retain pan authority.
            WorkspacePreferredGeometry.requestCompletion(in:window)
        }
    }
    override func scrollWheel(with event:NSEvent) {pendingCellDetailsReveal=nil;super.scrollWheel(with:event)}
    var sourceKeyboardEnabled=true {didSet{if !sourceKeyboardEnabled {pendingCellDetailsReveal=nil}}}
    private let rowGutter=WorkbookPinnedRowsView(heading:false),rowHeading=WorkbookPinnedRowsView(heading:true)
    private var gutterRowStart=1,gutterPane=""
    private var synchronizingGutter=false
    var pinnedRowGutter:NSView {rowGutter}
    func pinnedRowLabel(_ physical:Int)->NSTextField? {rowGutter.fields.first{!$0.isHidden && $0.stringValue==String(physical)}}
    func configurePinnedRows(rowStart:Int,pane:String){gutterRowStart=rowStart;gutterPane=pane;synchronizePinnedRows()}
    func synchronizePinnedRows(){
        guard !synchronizingGutter,let table=documentView as? NSTableView,table.numberOfColumns>0 else{return}
        synchronizingGutter=true;defer{synchronizingGutter=false}
        if rowGutter.superview==nil {addSubview(rowGutter);addSubview(rowHeading)}
        let body=contentView.convert(contentView.bounds,to:self),width=min(table.rect(ofColumn:0).width,body.width),frame=NSRect(x:body.minX,y:body.minY,width:width,height:body.height)
        if rowGutter.frame != frame {rowGutter.frame=frame}
        rowGutter.identifier=NSUserInterfaceItemIdentifier("Reviset.workbook.rowGutter."+gutterPane);rowGutter.setAccessibilityHidden(!sourceKeyboardEnabled);rowHeading.setAccessibilityHidden(!sourceKeyboardEnabled)
        rowGutter.synchronize(table,rowStart:gutterRowStart,pane:gutterPane)
        if let header=table.headerView {let headerRect=header.convert(header.bounds,to:self);rowHeading.frame=NSRect(x:body.minX,y:headerRect.minY,width:width,height:headerRect.height);rowHeading.synchronize(table,rowStart:gutterRowStart,pane:gutterPane)}
    }
    func revealColumnToRightOfGutter(_ column:Int){
        guard let table=documentView as? NSTableView,column>0,column<table.numberOfColumns else{return}
        let original=contentView.bounds.origin,visible=contentView.bounds,rect=table.rect(ofColumn:column),gutter=min(table.rect(ofColumn:0).width,visible.width)
        var x=original.x
        if rect.width>visible.width-gutter {x=rect.minX-gutter}
        else {
            if rect.minX<x+gutter {x=rect.minX-gutter}
            if rect.maxX>x+visible.width {x=rect.maxX-visible.width}
        }
        x=max(0,min(x,max(0,table.bounds.width-visible.width)))
        contentView.scroll(to:NSPoint(x:x,y:original.y));reflectScrolledClipView(contentView)
    }
    func columnVisibleToRightOfGutter(_ column:Int)->Bool {
        guard let table=documentView as? NSTableView,column>0,column<table.numberOfColumns else{return false}
        let visible=contentView.bounds,rect=table.rect(ofColumn:column),gutter=min(table.rect(ofColumn:0).width,visible.width)
        return rect.minX>=visible.minX+gutter-0.5 && rect.maxX<=visible.maxX+0.5
    }
    override var acceptsFirstResponder:Bool {sourceKeyboardEnabled && super.acceptsFirstResponder}
    override var canBecomeKeyView:Bool {sourceKeyboardEnabled && super.canBecomeKeyView}
    override func becomeFirstResponder()->Bool {sourceKeyboardEnabled && super.becomeFirstResponder()}
    private var synchronizingHeader = false
    override func reflectScrolledClipView(_ clipView: NSClipView) {
        super.reflectScrolledClipView(clipView)
        if clipView === contentView {
            if let event=NSApp.currentEvent,event.window === window,[NSEvent.EventType.leftMouseDown,.leftMouseDragged].contains(event.type),bounds.contains(convert(event.locationInWindow,from:nil)) {pendingCellDetailsReveal=nil}
            synchronizeHeader();synchronizePinnedRows()
        }
    }
    override func tile() { super.tile(); synchronizeHeader();synchronizePinnedRows() }
    override func layout() { super.layout(); synchronizeHeader();synchronizePinnedRows() }
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

final class WorkbookSourceTableView:NSTableView {
    var sourceKeyboardEnabled=true
    override var acceptsFirstResponder:Bool {sourceKeyboardEnabled && super.acceptsFirstResponder}
    override var canBecomeKeyView:Bool {sourceKeyboardEnabled && super.canBecomeKeyView}
    override func becomeFirstResponder()->Bool {sourceKeyboardEnabled && super.becomeFirstResponder()}
}
private final class WorkbookReadableHeaderCell:NSTableHeaderCell {
    var readablePointSize:CGFloat=14 {
        didSet {super.font = .systemFont(ofSize:readablePointSize,weight:.medium)}
    }
    // AppKit reapplies its small default header font during native layout.
    // Retain the interface preference whenever the table reapplies that style.
    override var font:NSFont? {
        get {super.font}
        set {super.font = .systemFont(ofSize:readablePointSize,weight:.medium)}
    }
}
@MainActor private enum WorkbookGridAnnotation {
    private static let measurementCell:NSCell = {
        let label=NSTextField(labelWithString:"");label.font = .systemFont(ofSize:13)
        return label.cell!
    }()
    static func flags(_ cell:JSON)->String {
        let raw=cell["value"].isNull ? "":cell["value"].string
        var result=cell["formula_interpretation"].string=="unresolved" ? "?ƒ":cell["formula"].isNull ? "":"ƒ"
        if cell["cached_result"].string=="missing" {result += (result.isEmpty ? "":" · ")+"∅"}
        if cell["text_truncated"].bool || cell["source_lengths"]["value"].int>raw.utf16.count {result += (result.isEmpty ? "":" · ")+"…"}
        return result
    }
    static func reservedWidth(for flags:String,pointSize:CGFloat=13)->CGFloat {
        guard !flags.isEmpty else{return 0}
        measurementCell.font = .systemFont(ofSize:pointSize)
        measurementCell.stringValue=flags
        return min(max(80,pointSize*6),measurementCell.cellSize.width+5)
    }
}
private final class WorkbookValueCellView:NSTableCellView {
    let annotation=NSTextField(labelWithString:"")
    override init(frame:NSRect) {
        super.init(frame:frame)
        let source=NSTextField(labelWithString:"");source.lineBreakMode = .byTruncatingTail
        annotation.font = .systemFont(ofSize:13);annotation.textColor = .secondaryLabelColor
        addSubview(annotation);addSubview(source);textField=source
    }
    required init?(coder:NSCoder) {fatalError("init(coder:) is unavailable")}
    func setAnnotation(_ value:String,pointSize:CGFloat) {annotation.stringValue=value;annotation.font = .systemFont(ofSize:pointSize);annotation.isHidden=value.isEmpty;needsLayout=true}
    override func layout() {
        super.layout()
        let width=WorkbookGridAnnotation.reservedWidth(for:annotation.stringValue,pointSize:annotation.font?.pointSize ?? 13)
        let annotationHeight=ceil(annotation.font.map{$0.ascender-$0.descender+$0.leading} ?? 16)+2
        let sourceHeight=ceil(textField?.font.map{$0.ascender-$0.descender+$0.leading} ?? 19)+2
        annotation.frame=NSRect(x:6,y:max(0,(bounds.height-annotationHeight)/2),width:max(0,width-5),height:annotationHeight)
        textField?.frame=NSRect(x:6+width,y:max(0,(bounds.height-sourceHeight)/2),width:max(0,bounds.width-11-width),height:sourceHeight)
    }
}
struct WorkbookGrid: NSViewRepresentable {
    @ObservedObject private var readability=ReadabilityPreferences.shared
    var keyboardEnabled=true
    var sourceIdentity=""
    let language: String
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
        let table = WorkbookSourceTableView()
        // Spreadsheet geometry uses explicit cell padding. Inset table styles
        // resize columns asynchronously at mount, which can be mistaken for a
        // user resize and overwrite the retained compact width.
        table.style = .plain;table.intercellSpacing=NSSize(width:1,height:1)
        table.identifier = NSUserInterfaceItemIdentifier("Docver.workbook.grid." + pane); table.usesAlternatingRowBackgroundColors = true; table.gridStyleMask = [.solidHorizontalGridLineMask,.solidVerticalGridLineMask]; table.headerView = NSTableHeaderView(); table.allowsMultipleSelection = false; table.allowsColumnReordering = false; table.columnAutoresizingStyle = .noColumnAutoresizing
        table.dataSource = context.coordinator; table.delegate = context.coordinator; table.target = context.coordinator; table.action = #selector(Coordinator.clicked(_:)); table.setAccessibilityLabel((pane == "before" ? L("workbook.grid.beforeAX") : L("workbook.grid.afterAX")))
        scroll.documentView = table; context.coordinator.table = table; context.coordinator.update(self)
        return scroll
    }
    func updateNSView(_ scroll: NSScrollView, context: Context) {
        (scroll as? WorkbookTableScrollView)?.sourceKeyboardEnabled=keyboardEnabled
        (scroll.documentView as? WorkbookSourceTableView)?.sourceKeyboardEnabled=keyboardEnabled
        scroll.setAccessibilityHidden(!keyboardEnabled);scroll.documentView?.setAccessibilityHidden(!keyboardEnabled)
        if !keyboardEnabled {resignHiddenSourceFirstResponder(in:scroll)}
        context.coordinator.update(self)
    }
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
        private var resizedWidths:[String:[Int:CGFloat]]=[:]
        private var widthSources:[String]=[]
        private var defaultWidths:[String:[Int:CGFloat]]=[:]
        private var defaultWidthColumns:[String:[Int]]=[:]
        private var defaultWidthSources:[String]=[]
        private var widthSource:String {parent.sourceIdentity.isEmpty ? parent.pane:parent.sourceIdentity}
        private var valuePointSize:CGFloat {parent.readability.pointSize(.body)}
        private var annotationPointSize:CGFloat {parent.readability.pointSize(.caption2)}
        private var chromePointSize:CGFloat {parent.readability.pointSize(.caption)}
        init(_ parent: WorkbookGrid) { self.parent = parent }
        func update(_ value: WorkbookGrid) {
            updating = true; defer { updating = false }
            parent = value
            lastRequested = "\(value.selectedRow):\(value.selectedColumn)"
            sparse = Dictionary(value.cells.map { (String($0["row"].int)+":"+String($0["column"].int),$0) },uniquingKeysWith:{a,_ in a})
            guard let table else { return }
            // Change native typography in place: the same table, physical
            // source range and selected-cell reveal intent remain mounted.
            let rowHeight=valuePointSize+14,headerHeight=chromePointSize+14
            let previousRowHeight=table.rowHeight
            let previousOrigin=table.enclosingScrollView?.contentView.bounds.origin
            table.rowHeight=rowHeight
            if let header=table.headerView,abs(header.frame.height-headerHeight)>0.5 {var frame=header.frame;frame.size.height=headerHeight;header.frame=frame;table.enclosingScrollView?.tile()}
            let key = "\(widthSource):\(value.columnStart):\(value.columnCount)"
            if columnsKey != key {
                for column in table.tableColumns { table.removeTableColumn(column) }
                let row = NSTableColumn(identifier:NSUserInterfaceItemIdentifier("row")); row.headerCell = WorkbookReadableHeaderCell(textCell:L("workbook.grid.rowHeader")); row.width = 58; row.minWidth = 58; table.addTableColumn(row)
                for offset in 0..<value.columnCount { let n = value.columnStart+offset; let column = NSTableColumn(identifier:NSUserInterfaceItemIdentifier(String(n))); column.headerCell = WorkbookReadableHeaderCell(textCell:WorkbookGrid.columnLabel(n)); column.minWidth = 64; column.width = 64; table.addTableColumn(column) }
                columnsKey = key
            }
            let rowFont=NSFont.monospacedDigitSystemFont(ofSize:chromePointSize,weight:.regular)
            let lastRow=String(max(value.rowStart,value.rowStart+value.rowCount-1))
            let gutterWidth=max(58,ceil((lastRow as NSString).size(withAttributes:[.font:rowFont]).width)+18)
            if let gutter=table.tableColumns.first {gutter.minWidth=gutterWidth;gutter.width=gutterWidth}
            for column in table.tableColumns {(column.headerCell as? WorkbookReadableHeaderCell)?.readablePointSize=chromePointSize}
            for column in table.tableColumns.dropFirst() {
                guard let physical=Int(column.identifier.rawValue) else{continue}
                let width=resizedWidths[widthSource]?[physical] ?? retainedDefaultWidth(physical)
                if abs(column.width-width)>0.5 {column.width=width}
            }
            table.tableColumns.first?.title = L("workbook.grid.rowHeader")
            table.setAccessibilityLabel(value.pane == "before" ? L("workbook.grid.beforeAX") : L("workbook.grid.afterAX"))
            table.headerView?.needsDisplay = true
            table.reloadData()
            if abs(previousRowHeight-rowHeight)>0.5,previousRowHeight>0,let previousOrigin,let scroll=table.enclosingScrollView {
                let stride=previousRowHeight+table.intercellSpacing.height,newStride=rowHeight+table.intercellSpacing.height
                scroll.contentView.scroll(to:NSPoint(x:previousOrigin.x,y:max(0,previousOrigin.y/stride*newStride)));scroll.reflectScrolledClipView(scroll.contentView)
            }
            if value.selectedRow >= value.rowStart,value.selectedRow < value.rowStart+value.rowCount,value.selectedColumn >= value.columnStart,value.selectedColumn < value.columnStart+value.columnCount {
                let row = value.selectedRow-value.rowStart,column = value.selectedColumn-value.columnStart+1
                table.selectRowIndexes(IndexSet(integer:row),byExtendingSelection:false)
                let reveal = "\(value.revealIntent):\(value.rowStart):\(value.columnStart):\(value.selectedRow):\(value.selectedColumn)"
                if lastRevealed != reveal {
                    table.scrollRowToVisible(row)
                    if let scroll=table.enclosingScrollView as? WorkbookTableScrollView {scroll.revealColumnToRightOfGutter(column)}else{table.scrollColumnToVisible(column)}
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
            if let scroll=table.enclosingScrollView as? WorkbookTableScrollView {scroll.synchronizeHeader();scroll.configurePinnedRows(rowStart:value.rowStart,pane:value.pane)}
        }
        private func retainedDefaultWidth(_ column:Int)->CGFloat {
            let source=widthSource,cached=defaultWidths[source]?[column] ?? 64
            // A pending/failed range is not evidence that the physical column
            // became narrower. The measurement ceiling also needs no remeasure.
            guard !parent.cells.isEmpty,cached<180 else{return cached}
            let width=max(cached,compactWidth(column))
            if defaultWidths[source]==nil {
                if defaultWidthSources.count>=16 {
                    let expired=defaultWidthSources.removeFirst()
                    defaultWidths.removeValue(forKey:expired);defaultWidthColumns.removeValue(forKey:expired)
                }
                defaultWidthSources.append(source);defaultWidths[source]=[:];defaultWidthColumns[source]=[]
            }
            if defaultWidths[source]?[column]==nil {
                if (defaultWidthColumns[source]?.count ?? 0)>=256,let expired=defaultWidthColumns[source]?.removeFirst() {defaultWidths[source]?.removeValue(forKey:expired)}
                defaultWidthColumns[source]?.append(column)
            }
            // Grow only as wider bounded observations arrive. Manual widths use
            // their separate retention policy and always take precedence.
            defaultWidths[source]?[column]=width
            return width
        }
        private func compactWidth(_ column:Int)->CGFloat {
            // Measurement is bounded to the same 64 UTF-16 source preview. It
            // never rewrites the native text field, formats values or executes formulas.
            let observations=parent.cells.filter{$0["column"].int==column}
            let numericColumn=observations.contains{["number","boolean"].contains($0["value_type"].string)}
            var result:CGFloat=64
            for cell in observations {
                let raw=cell["value"].isNull ? "":cell["value"].string
                guard !raw.isEmpty else{continue}
                let sample=String(decoding:raw.utf16.prefix(64),as:UTF16.self)
                let numeric=["number","boolean"].contains(cell["value_type"].string)
                let annotationWidth=WorkbookGridAnnotation.reservedWidth(for:WorkbookGridAnnotation.flags(cell),pointSize:annotationPointSize)
                let measured=(sample as NSString).size(withAttributes:[.font:NSFont.systemFont(ofSize:valuePointSize)]).width+16+annotationWidth
                result=max(result,min(numeric ? 112:180,max(numeric || numericColumn ? 64:96,ceil(measured))))
            }
            return result
        }
        func tableViewColumnDidResize(_ notification:Notification) {
            guard !updating,let table=notification.object as? NSTableView,table === self.table,
                  let column=notification.userInfo?["NSTableColumn"] as? NSTableColumn,
                  let physical=Int(column.identifier.rawValue) else{return}
            let source=widthSource
            if resizedWidths[source]==nil {
                if widthSources.count>=16 {resizedWidths.removeValue(forKey:widthSources.removeFirst())}
                widthSources.append(source);resizedWidths[source]=[:]
            }
            resizedWidths[source]?[physical]=column.width
        }
        func numberOfRows(in tableView: NSTableView) -> Int { parent.rowCount }
        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            guard let tableColumn else { return nil }
            let id = NSUserInterfaceItemIdentifier(tableColumn.identifier.rawValue == "row" ? "WorkbookRowNumberCell":"WorkbookPlainCell")
            let cell = tableView.makeView(withIdentifier:id,owner:self) as? NSTableCellView ?? (tableColumn.identifier.rawValue == "row" ? NSTableCellView():WorkbookValueCellView())
            cell.identifier = id
            cell.wantsLayer = true; cell.layer?.masksToBounds = true; cell.layer?.borderWidth = 0; cell.layer?.backgroundColor = NSColor.clear.cgColor
            let text: NSTextField
            if let existing = cell.textField { text = existing } else { text = NSTextField(labelWithString:""); text.translatesAutoresizingMaskIntoConstraints = false; text.lineBreakMode = .byTruncatingTail; cell.addSubview(text); cell.textField = text; NSLayoutConstraint.activate([text.leadingAnchor.constraint(equalTo:cell.leadingAnchor,constant:6),text.trailingAnchor.constraint(equalTo:cell.trailingAnchor,constant:-5),text.centerYAnchor.constraint(equalTo:cell.centerYAnchor)]) }
            text.maximumNumberOfLines=1;text.cell?.usesSingleLineMode=true;text.cell?.wraps=false;text.lineBreakMode = .byTruncatingTail
            let physicalRow = parent.rowStart+row
            if tableColumn.identifier.rawValue == "row" { text.identifier = NSUserInterfaceItemIdentifier("Docver.workbook.row.\(physicalRow)"); text.stringValue = String(physicalRow); text.font = .monospacedDigitSystemFont(ofSize:chromePointSize,weight:.regular); text.textColor = .secondaryLabelColor; text.setAccessibilityLabel(L("workbook.grid.rowAX",.integer(physicalRow))); cell.toolTip = nil }
            else {
                let column = Int(tableColumn.identifier.rawValue) ?? 1
                text.identifier = NSUserInterfaceItemIdentifier("Docver.workbook.cell." + WorkbookGrid.address(physicalRow,column))
                let value = sparse[String(physicalRow)+":"+String(column)] ?? JSON()
                if physicalRow == parent.selectedRow,column == parent.selectedColumn { cell.layer?.borderWidth = 1; cell.layer?.borderColor = NSColor.controlAccentColor.cgColor; cell.layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.12).cgColor }
                let raw = value["value"].isNull ? "" : value["value"].string
                let flags=WorkbookGridAnnotation.flags(value)
                let valueTruncated = value["source_lengths"]["value"].int > raw.utf16.count
                (cell as? WorkbookValueCellView)?.setAnnotation(flags,pointSize:annotationPointSize)
                text.stringValue = raw; text.font = .systemFont(ofSize:valuePointSize); text.textColor = value["hidden_row"].bool || value["hidden_column"].bool ? .secondaryLabelColor : .labelColor
                let formula = value["formula"].isNull ? "" : L("workbook.grid.formulaPrefix") + String(value["formula"].string.prefix(600))
                let interpretation = value["formula_interpretation"].string == "unresolved" ? L("workbook.grid.unresolvedSuffix") : value["formula"].isNull ? "" : L("workbook.grid.resultSuffix")
                cell.toolTip = WorkbookGrid.address(physicalRow,column) + (value.isNull ? L("workbook.grid.absentSuffix") : " · " + WorkbookLabels.valueType(value["value_type"].string) + formula + interpretation + "\n" + (valueTruncated ? L("git.savedValuePreview"):L("git.savedValue")) + ": " + raw + (value["text_truncated"].bool || valueTruncated ? "\n"+L("git.gridPreviewRoute"):""))
                text.setAccessibilityLabel(WorkbookGrid.address(physicalRow,column) + " " + flags + " " + text.stringValue + interpretation)
            }
            return cell
        }
        private func select(_ row: Int, _ column: Int) {
            guard parent.keyboardEnabled,!updating,row >= 0,row < parent.rowCount,column >= parent.columnStart,column < parent.columnStart+parent.columnCount else { return }
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
        func selectPhysicalRow(_ row:Int) {
            (table?.enclosingScrollView as? WorkbookTableScrollView)?.pendingCellDetailsReveal=nil
            select(row,max(parent.columnStart,min(parent.selectedColumn,parent.columnStart+parent.columnCount-1)))
        }
        @objc func clicked(_ table: NSTableView) {
            let row = table.clickedRow,column = table.clickedColumn
            guard row >= 0,column >= 0,column < table.tableColumns.count else { return }
            let physicalColumn: Int
            if column == 0 {selectPhysicalRow(row);return}
            else { guard let value = Int(table.tableColumns[column].identifier.rawValue) else { return }; physicalColumn = value }
            select(row,physicalColumn)
        }
    }
}

// A gated fixture driver, matching the existing document Smoke contract. It
// exercises the shipped production model and real native table, never a mock
// service. Only an explicit environment request enables it.
@MainActor enum WorkbookNativeSmoke {
    private static var started = false
    static func runIfRequested(_ model: WorkbookModel,layout:WorkspaceLayoutStore) async {
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
            if request["single_revision_checks"].bool {
                checks["single_revision_checks"] = try await exerciseSingleRevision(model,layout:layout,folder:folder,originals:originals,metadata:metadata)
                model.closeReads()
                guard !model.ready,!model.canCopyMCP else{throw BridgeError(code:"WORKBOOK_SINGLE_CLOSE",message:"Closed single-version workspace retained authority.")}
                checks["closed_workspace_invalidates_authority"] = true
                let result:[String:Any] = ["completed":true,"project_id":project,"report_id":snapshot,"revision_count":model.revisions.count,"seconds":Date().timeIntervalSince(began),"checks":checks,"mcp_config":"","interaction_scope":"production workbook actions, visible AppKit guidance/button/grid and existing import sheet; programmatic actions without submitted import or OS input","smoke_invocation_id":request["smoke_invocation_id"].string]
                try JSON(result).data().write(to:folder.appendingPathComponent("validation.json"))
                NSApp.terminate(nil);return
            }
            if request["git_diff_checks"].bool {checks["git_diff_checks"] = try await exerciseGitDiffWorkspace(model,layout:layout,folder:folder)}
            if request.dictionary.keys.contains("expected_blank_formatting_warning") { checks["initial_blank_formatting_warning"] = try checkBlankFormattingWarning(model,request:request) }
            let requiredKinds = request["required_change_kinds"].array.map(\.string)
            if !requiredKinds.isEmpty {
                if let first=model.revisions.first,let last=model.revisions.last {await model.changeVersions(before:first["revision_occurrence_id"].string,after:last["revision_occurrence_id"].string)}
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
            if request["layout_checks"].bool {checks["layout_checks"] = try await exerciseLayouts(model,layout:layout,window:window,folder:folder)}
            if request.dictionary.keys.contains("expected_blank_formatting_warning") { checks["rendered_blank_formatting_warning"] = try checkBlankFormattingWarning(model,request:request) }
            if !request["require_dense_raw_proof"].bool,model.selectedChangeID.isEmpty,let representative=model.changes.first(where:{!$0["before_address"].string.isEmpty && !$0["after_address"].string.isEmpty}) {
                await model.chooseChange(representative["change_id"].string);try await Task.sleep(nanoseconds:200_000_000)
                checks["representative_selected_event_capture"]=["change_id":model.selectedChangeID,"pane_evidence":try assertPanes(model,window:window)]
            }
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
            guard let tools=window.sheets.first else{throw BridgeError(code:"WORKBOOK_TOOLS_SHEET",message:"Native AI/export details sheet did not appear.")}
            try Smoke.captureView(tools,folder.appendingPathComponent("native-workbook-ai-release.png"))
            model.tab = "compare"
            for _ in 0..<100 {if window.sheets.isEmpty{break};try await Task.sleep(nanoseconds:20_000_000)}
            guard window.sheets.isEmpty else{throw BridgeError(code:"WORKBOOK_TOOLS_DISMISS",message:"Native AI/export details sheet did not dismiss before continuing.")}
            let reread = try await model.bridge.call("workbookView",["project_id":project,"report_id":snapshot])
            guard try reread.data() == metadata else { throw BridgeError(code:"WORKBOOK_SMOKE_IMMUTABLE",message:"셀 조회·배포·내보내기가 고정 보고서 메타데이터를 바꿨습니다.") }
            for original in originals { guard try ImportFileIdentity.capture(original.url) == original.identity else { throw BridgeError(code:"WORKBOOK_SMOKE_ORIGINAL",message:"원본 파일의 SHA-256 또는 크기가 달라졌습니다.") } }
            checks["original_bytes_unchanged"] = true; checks["report_metadata_unchanged"] = true
            let config = model.mcp
            // Locale qualification deliberately changes version/selection state.
            // Run it only after production checks, captures, and the MCP snapshot
            // so those results cannot inherit its temporary navigation choices.
            if request["language_switch_check"].bool {
                model.tab = "compare"
                try await Task.sleep(nanoseconds:300_000_000)
                checks["language_switch"] = try await exerciseLanguageSwitch(model,window:window,folder:folder,originals:originals)
            }
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
    private static func guidanceView(_ view:NSView?)->WorkbookEmptyGuidanceView? {
        guard let view else{return nil};if let found=view as? WorkbookEmptyGuidanceView{return found}
        for child in view.subviews {if let found=guidanceView(child){return found}};return nil
    }
    private static func readingGuidanceFacts(_ model:WorkbookModel,window:NSWindow,route:String)async throws->[String:Any] {
        try await Task.sleep(nanoseconds:200_000_000);window.contentView?.layoutSubtreeIfNeeded()
        guard model.changesFromID==model.changesToID,!model.changesFromID.isEmpty,model.changes.isEmpty,model.effectiveDiffMode=="source",let content=window.contentView,let view=guidanceView(content),!view.message.isHiddenOrHasHiddenAncestor,!view.message.visibleRect.isEmpty,view.message.stringValue==model.emptyChangesMessage,view.message.stringValue != L("workbook.changes.empty") else{throw BridgeError(code:"WORKBOOK_READING_GUIDANCE",message:"Single-source workbook did not display its count-aware native reading guidance.")}
        let tables=["before","after"].compactMap{grid(content,pane:$0)},visible=tables.filter{!$0.isHiddenOrHasHiddenAncestor && !$0.visibleRect.isEmpty}
        let one=model.revisions.count==1
        guard visible.count==1,visible[0].numberOfRows>0,visible[0].numberOfColumns>1,!workspaceLayoutMarkers(in:content).contains(where:{$0.identifier?.rawValue=="Reviset.workbook.unifiedDiff"}),model.emptyChangesKind == (one ? .additionalVersion:.singleRead),view.importButton.isHidden != one,!one || view.importButton.isEnabled else{throw BridgeError(code:"WORKBOOK_READING_SOURCE",message:"Count-aware workbook guidance obscured the useful original grid or its new-comparison action.")}
        return ["route":route,"language":LanguagePreferences.shared.effectiveLanguage,"revision_count":model.revisions.count,"kind":model.emptyChangesKind.rawValue,"native_visible_message":view.message.stringValue,"native_message_field_verified":true,"effective_view":"source","query_before":model.changesFromID,"query_after":model.changesToID,"native_visible_grid_count":visible.count,"native_grid_rows":visible[0].numberOfRows,"native_grid_columns":visible[0].numberOfColumns,"new_comparison_button_visible":!view.importButton.isHidden,"new_comparison_button_enabled":view.importButton.isEnabled]
    }
    private static func exerciseSingleRevision(_ model:WorkbookModel,layout:WorkspaceLayoutStore,folder:URL,originals:[WorkbookImportRow],metadata:Data)async throws->[String:Any] {
        guard model.revisions.count==1,let first=model.revisions.first else{throw BridgeError(code:"WORKBOOK_SINGLE_COUNT",message:"Single-version qualification requires one actually imported workbook.")}
        let project=model.projectID,report=model.reportID,occurrence=first["revision_occurrence_id"].string
        layout.reset();model.diffMode="text";await model.selectVersion(occurrence);model.setDiffMode("text")
        try await Task.sleep(nanoseconds:300_000_000)
        guard let window=NSApp.windows.first(where:{$0.isVisible && containsGrid($0.contentView)}),let content=window.contentView else{throw BridgeError(code:"WORKBOOK_SINGLE_WINDOW",message:"Single imported workbook has no rendered native grid.")}
        let facts=try await readingGuidanceFacts(model,window:window,route:"one_imported_version")
        let rawBefore=try model.beforeCell.data(),rawAfter=try model.afterCell.data(),cellsBefore=try JSON(model.beforeCells.map(\.raw)).data(),cellsAfter=try JSON(model.afterCells.map(\.raw)).data()
        let identity=[model.projectID,model.reportID,model.beforeID,model.afterID,model.beforeSheetID,model.afterSheetID,String(model.selectedRow),String(model.selectedColumn)]
        let tables=["before","after"].compactMap{grid(content,pane:$0)},state=tables.map{($0,$0.dataSource as AnyObject?,$0.selectedRow,$0.enclosingScrollView!.contentView.bounds.origin)}
        func storedAssets()throws->[String:ImportFileIdentity] {
            let directory=model.bridge.library.appendingPathComponent("assets")
            return try Dictionary(uniqueKeysWithValues:FileManager.default.contentsOfDirectory(at:directory,includingPropertiesForKeys:nil).filter{$0.lastPathComponent.range(of:"^[a-f0-9]{64}$",options:.regularExpression) != nil}.map{($0.lastPathComponent,try ImportFileIdentity.capture($0))})
        }
        let assets=try storedAssets();guard !assets.isEmpty else{throw BridgeError(code:"WORKBOOK_SINGLE_ASSETS",message:"Imported workbook has no content-addressed source bytes to verify.")}
        try Smoke.captureView(window,folder.appendingPathComponent("native-one-workbook-reading.png"))
        guard let view=guidanceView(content) else{throw BridgeError(code:"WORKBOOK_SINGLE_ACTION",message:"New comparison action is unavailable.")}
        defer{model.importPresented=false;for sheet in window.sheets{window.endSheet(sheet);sheet.orderOut(nil)}}
        view.importButton.performClick(nil)
        func fields(_ view:NSView?)->[NSTextField] {guard let view else{return []};return (view as? NSTextField).map{[$0]} ?? view.subviews.flatMap{fields($0)}}
        for _ in 0..<100 {if let sheet=window.sheets.first,fields(sheet.contentView).contains(where:{$0.isEditable && $0.placeholderString==L("workbook.import.projectName")}){break};try await Task.sleep(nanoseconds:20_000_000)}
        guard model.importPresented,let sheet=window.sheets.first,fields(sheet.contentView).contains(where:{$0.isEditable && $0.placeholderString==L("workbook.import.projectName") && $0.stringValue==L("workbook.import.defaultTitle")}) else{throw BridgeError(code:"WORKBOOK_SINGLE_IMPORT",message:"Native New comparison action did not open the existing new-timeline import sheet.")}
        try Smoke.captureView(sheet,folder.appendingPathComponent("native-one-workbook-import.png"))
        model.importPresented=false
        for _ in 0..<100 {if window.sheets.isEmpty{break};try await Task.sleep(nanoseconds:20_000_000)}
        guard window.sheets.isEmpty else{throw BridgeError(code:"WORKBOOK_SINGLE_DISMISS",message:"Existing import sheet did not dismiss before continuing.")}
        try await Task.sleep(nanoseconds:150_000_000)
        guard identity==[model.projectID,model.reportID,model.beforeID,model.afterID,model.beforeSheetID,model.afterSheetID,String(model.selectedRow),String(model.selectedColumn)],try model.beforeCell.data()==rawBefore,try model.afterCell.data()==rawAfter,try JSON(model.beforeCells.map(\.raw)).data()==cellsBefore,try JSON(model.afterCells.map(\.raw)).data()==cellsAfter else{throw BridgeError(code:"WORKBOOK_SINGLE_STATE",message:"Opening new comparison changed the current report or observed raw cells.")}
        for (table,coordinator,selected,origin) in state {guard ["before","after"].contains(where:{grid(content,pane:$0) === table}),(table.dataSource as AnyObject?) === coordinator,table.selectedRow==selected,let scroll=table.enclosingScrollView,abs(scroll.contentView.bounds.minX-origin.x)<1,abs(scroll.contentView.bounds.minY-origin.y)<1 else{throw BridgeError(code:"WORKBOOK_SINGLE_HOST",message:"Opening new comparison replaced the source host or changed its selection/viewport.")}}
        let reread=try await model.bridge.call("workbookView",["project_id":project,"report_id":report])
        guard try reread.data()==metadata,try storedAssets()==assets else{throw BridgeError(code:"WORKBOOK_SINGLE_IMMUTABLE",message:"Reading or opening import changed the fixed report or stored raw asset bytes.")}
        for original in originals {guard try ImportFileIdentity.capture(original.url)==original.identity else{throw BridgeError(code:"WORKBOOK_SINGLE_ORIGINAL",message:"Original workbook bytes changed.")}}
        _ = try await readingGuidanceFacts(model,window:window,route:"after_import_dismissal")
        return ["passed":true,"reading_guidance":facts,"actual_revision_count":1,"native_new_comparison_action_reached":true,"existing_new_timeline_import_sheet_mounted":true,"import_not_submitted":true,"import_sheet_dismissed":true,"report_metadata_disk_reread_unchanged":true,"raw_selected_cells_and_grid_observations_unchanged":true,"stored_asset_bytes_unchanged":true,"stored_asset_count":assets.count,"original_bytes_unchanged":true,"original_input_count":originals.count,"native_grid_hosts_and_viewport_preserved":true,"captures":["native-one-workbook-reading.png","native-one-workbook-import.png"]]
    }
    // Optional shipped-app qualification. The locale mutation, seeded draft,
    // AppKit scroll, and captures are explicit programmatic operations. This is
    // not an OS input/VoiceOver automation claim and does not submit the draft.
    private static func exerciseGitDiffWorkspace(_ model:WorkbookModel,layout:WorkspaceLayoutStore,folder:URL)async throws->[String:Any] {
        guard !model.revisions.isEmpty else{throw BridgeError(code:"WORKBOOK_GIT_REVISIONS",message:"Qualification requires workbook versions.")}
        let revisions=model.revisions,first=revisions[0]["revision_occurrence_id"].string,last=revisions.last!["revision_occurrence_id"].string,previous=revisions[max(0,revisions.count-2)]["revision_occurrence_id"].string
        guard model.beforeID==previous,model.afterID==last else{throw BridgeError(code:"WORKBOOK_GIT_DEFAULT",message:"New workbook report did not open predecessor → latest.")}
        layout.reset();try await Task.sleep(nanoseconds:350_000_000)
        guard !layout.configuration.sidebarVisible,!layout.configuration.inspectorVisible,layout.configuration.changesVisible,layout.configuration.changesDock == .left,let window=NSApp.windows.first(where:{$0.isVisible && containsGrid($0.contentView)}),let content=window.contentView else{throw BridgeError(code:"WORKBOOK_GIT_LAYOUT",message:"Source First workbook layout is unavailable.")}
        try Smoke.captureView(window,folder.appendingPathComponent("native-workbook-git-source-first.png"))
        await model.changeVersions(before:first,after:last);await model.changeMode("history")
        let query=[model.changesFromID,model.changesToID,model.changesMode],rows=try JSON(model.changes.map(\.raw)).data()
        guard let change=model.changes.first(where:{!$0["before_address"].string.isEmpty && !$0["after_address"].string.isEmpty}) else{throw BridgeError(code:"WORKBOOK_GIT_EVENT",message:"Qualification needs a paired workbook change.")}
        var queried=false;let observation=model.$loadingChanges.dropFirst().sink{if $0{queried=true}};defer{observation.cancel()}
        await model.chooseChange(change["change_id"].string)
        guard query==[model.changesFromID,model.changesToID,model.changesMode],try JSON(model.changes.map(\.raw)).data()==rows,!queried,model.beforeID==change["from_revision_occurrence_id"].string,model.afterID==change["to_revision_occurrence_id"].string,model.beforeAddress==change["before_address"].string,model.afterAddress==change["after_address"].string else{throw BridgeError(code:"WORKBOOK_GIT_SCOPE",message:"Workbook event selection replaced query/list or physical addresses.")}
        observation.cancel();let selectionDidNotQuery = !queried
        try await Task.sleep(nanoseconds:200_000_000);try Smoke.captureView(window,folder.appendingPathComponent("native-workbook-git-history.png"))
        func scopeFields(_ view:NSView)->[NSTextField] {(view as? NSTextField).map{[$0]} ?? view.subviews.flatMap{scopeFields($0)}}
        let scopeField=scopeFields(content).first(where:{$0.identifier?.rawValue=="Reviset.workbook.queryEventScopeCopy"})
        if !model.sourceScopeDescription.isEmpty {
            guard let scopeField,!scopeField.isHiddenOrHasHiddenAncestor,!scopeField.visibleRect.isEmpty,scopeField.stringValue.utf16.elementsEqual(model.sourceScopeDescription.utf16) else{throw BridgeError(code:"WORKBOOK_GIT_SCOPE_COPY",message:"Mounted native query/event caption is unavailable or differs from the displayed source scope.")}
        }
        try Smoke.captureView(window,folder.appendingPathComponent("native-workbook-query-event-scope.png"))
        let scopeCopy:[String:Any] = ["query_from":model.changesFromID,"query_to":model.changesToID,"source_from":model.beforeID,"source_to":model.afterID,"selected_event_id":model.selectedChangeID,"visible_copy":scopeField?.stringValue ?? "","qualified":!model.sourceScopeDescription.isEmpty,"mounted_native_label_verified":!model.sourceScopeDescription.isEmpty,"native_identifier":scopeField?.identifier?.rawValue ?? "","capture":"native-workbook-query-event-scope.png"]
        let cellDetails=try await exerciseCellDetails(model,layout:layout,window:window,folder:folder)
        let rawCellFacts=try rawSavedValueCellFacts(model,content:content)
        var manualQueried=false;let manualObservation=model.$loadingChanges.dropFirst().sink{if $0{manualQueried=true}};defer{manualObservation.cancel()}
        await model.changeSheet(before:model.beforeSheetID,after:model.afterSheetID)
        guard model.selectedChange.isNull,model.canReturnToChange else{throw BridgeError(code:"WORKBOOK_GIT_RETURN_SHEET",message:"Manual sheet browsing kept event authority or lost Return.")}
        await model.selectCell(1,1)
        guard model.selectedChange.isNull,model.canReturnToChange else{throw BridgeError(code:"WORKBOOK_GIT_RETURN_CELL",message:"Manual cell browsing lost Return.")}
        await model.moveWindow(rows:model.rowLimit)
        guard model.selectedChange.isNull,model.canReturnToChange else{throw BridgeError(code:"WORKBOOK_GIT_RETURN_WINDOW",message:"Manual window browsing lost Return.")}
        layout.setFocus(true);try await Task.sleep(nanoseconds:200_000_000)
        guard workspaceLayoutMarkers(in:content).contains(where:{$0.identifier?.rawValue=="Reviset.workbook.returnToChange" && !$0.isHiddenOrHasHiddenAncestor && !$0.visibleRect.isEmpty}) else{throw BridgeError(code:"WORKBOOK_GIT_RETURN_FOCUS",message:"Focus hid Return to selected workbook event.")}
        try Smoke.captureView(window,folder.appendingPathComponent("native-workbook-git-manual-return.png"))
        await model.returnToChange();layout.setFocus(false);try await Task.sleep(nanoseconds:200_000_000)
        guard !manualQueried,query==[model.changesFromID,model.changesToID,model.changesMode],try JSON(model.changes.map(\.raw)).data()==rows,model.selectedChangeID==change["change_id"].string,model.beforeSheetID==change["from_sheet_id"].string,model.afterSheetID==change["to_sheet_id"].string,model.beforeAddress==change["before_address"].string,model.afterAddress==change["after_address"].string else{throw BridgeError(code:"WORKBOOK_GIT_RETURN_SCOPE",message:"Return changed the query/list or failed to restore exact sheet and cell sources.")}
        manualObservation.cancel()
        let tables=["before","after"].compactMap{grid(content,pane:$0)},selection=[model.beforeID,model.afterID,model.beforeAddress,model.afterAddress,model.selectedChangeID]
        let sheetControls=workspaceLayoutMarkers(in:content).filter{$0.identifier?.rawValue.hasPrefix("Reviset.workbook.sheetPicker.")==true}
        guard sheetControls.count==2,sheetControls.allSatisfy({$0.contentEnabled}) else{throw BridgeError(code:"WORKBOOK_GIT_HEADER_SOURCE",message:"Original workbook sheet Picker environments are unavailable or disabled.")}
        let state=tables.map{($0,$0.dataSource as AnyObject?,$0.enclosingScrollView!.contentView.bounds.origin)}
        guard let focusedTable=tables.first,window.makeFirstResponder(focusedTable) else{throw BridgeError(code:"WORKBOOK_GIT_SOURCE_FOCUS",message:"Actual grid could not take keyboard focus for qualification.")}
        model.diffMode="text";try await Task.sleep(nanoseconds:200_000_000)
        guard sheetControls.allSatisfy({!$0.contentEnabled}) else{throw BridgeError(code:"WORKBOOK_GIT_HIDDEN_HEADER",message:"Invisible original sheet Picker environments remained enabled.")}
        if let responder=window.firstResponder as? NSView {guard !tables.contains(where:{responder === $0 || responder.isDescendant(of:$0)}) else{throw BridgeError(code:"WORKBOOK_GIT_HIDDEN_FOCUS",message:"Text mode left keyboard focus in an invisible grid.")}}
        guard workspaceLayoutMarkers(in:content).contains(where:{$0.identifier?.rawValue=="Reviset.workbook.unifiedDiff"}) else{throw BridgeError(code:"WORKBOOK_GIT_DIFF_VIEW",message:"Native workbook text diff is unavailable.")}
        let hiddenInputFacts=try hiddenNativeSourceInputFacts(window:window,sources:tables)
        try Smoke.captureView(window,folder.appendingPathComponent("native-workbook-git-unified.png"));model.diffMode="source";try await Task.sleep(nanoseconds:200_000_000)
        guard tables.count==2,selection==[model.beforeID,model.afterID,model.beforeAddress,model.afterAddress,model.selectedChangeID] else{throw BridgeError(code:"WORKBOOK_GIT_SELECTION",message:"Text mode changed workbook selection.")}
        for (table,coordinator,origin) in state {let actual=table.enclosingScrollView!.contentView.bounds.origin;guard ["before","after"].contains(where:{grid(content,pane:$0) === table}),(table.dataSource as AnyObject?) === coordinator,abs(actual.x-origin.x)<1,abs(actual.y-origin.y)<1 else{throw BridgeError(code:"WORKBOOK_GIT_HOST",message:"Text mode changed grid/coordinator or viewport.")}}
        layout.setFocus(true);try await Task.sleep(nanoseconds:200_000_000)
        guard workspaceLayoutMarkers(in:content).contains(where:{$0.identifier?.rawValue=="Reviset.workbook.reportBar"}) else{throw BridgeError(code:"WORKBOOK_GIT_REPORT",message:"Focus hid workbook fixed report.")}
        try Smoke.captureView(window,folder.appendingPathComponent("native-workbook-git-focus.png"));layout.setFocus(false)
        model.diffMode="text";await model.selectVersion(first)
        guard model.beforeID==first,model.afterID==first,model.changes.isEmpty,model.diffMode=="source",model.effectiveDiffMode=="source" else{throw BridgeError(code:"WORKBOOK_GIT_V1",message:"First workbook version from text mode did not show the original source.")}
        model.setDiffMode("text");guard model.diffMode=="source" else{throw BridgeError(code:"WORKBOOK_GIT_V1_TEXT",message:"Single workbook source accepted change-only text mode.")}
        let firstReading=try await readingGuidanceFacts(model,window:window,route:"version_menu_v1")
        model.diffMode="text";await model.changeVersions(before:first,after:first)
        guard model.diffMode=="source",model.effectiveDiffMode=="source" else{throw BridgeError(code:"WORKBOOK_GIT_EQUAL_TEXT",message:"Equal workbook endpoints kept a text overlay.")}
        let equalReading=try await readingGuidanceFacts(model,window:window,route:"equal_query_endpoints")
        try await Task.sleep(nanoseconds:200_000_000)
        let visibleTables=tables.filter{!$0.isHiddenOrHasHiddenAncestor && !$0.visibleRect.isEmpty}
        guard visibleTables.count==1,!workspaceLayoutMarkers(in:content).contains(where:{$0.identifier?.rawValue=="Reviset.workbook.unifiedDiff"}),Set(["before","after"].compactMap{grid(content,pane:$0)}.map(ObjectIdentifier.init))==Set(tables.map(ObjectIdentifier.init)) else{throw BridgeError(code:"WORKBOOK_GIT_SINGLE_SOURCE_VISIBLE",message:"Single workbook source was covered or its grid hosts were replaced.")}
        try Smoke.captureView(window,folder.appendingPathComponent("native-workbook-git-single-source.png"))
        await model.selectVersion(last);await model.changeMode("range_net")
        return ["passed":true,"default_predecessor_latest":true,"source_first_default":true,"query_interval_and_rows_preserved":true,"selection_started_no_range_query":selectionDidNotQuery,"physical_addresses_preserved":true,"raw_saved_value_cell_checks":rawCellFacts,"cell_details_checks":cellDetails,"query_event_scope_copy":scopeCopy,"native_grid_hosts_preserved":tables.count,"coordinator_and_viewport_preserved":true,"hidden_source_keyboard_focus_resigned":true,"hidden_source_input_gate":hiddenInputFacts,"hidden_source_sheet_picker_environments_disabled":true,"hidden_source_sheet_picker_environment_count":sheetControls.count,"focus_fixed_report_visible":true,"first_version_single_read":true,"single_source_from_text_routes_verified":2,"single_source_native_source_visible":true,"single_source_reading_guidance_verified":true,"single_source_reading_guidance":[firstReading,equalReading],"manual_sheet_cell_window_return_without_requery":true,"focus_return_action_visible":true,"captures":["native-workbook-git-source-first.png","native-workbook-git-history.png","native-workbook-git-unified.png","native-workbook-git-focus.png","native-workbook-git-single-source.png","native-workbook-git-manual-return.png","native-workbook-cell-details.png","native-workbook-query-event-scope.png"]]
    }
    private static func exerciseCellDetails(_ model:WorkbookModel,layout:WorkspaceLayoutStore,window:NSWindow,folder:URL)async throws->[String:Any] {
        let literal="stored only; not recalculated"
        guard let candidate=(model.beforeCells+model.afterCells).first(where:{$0["value"].string==literal}),let content=window.contentView else{return ["qualified":false,"reason":"No authored literal cell in this fixture window."]}
        func views(_ view:NSView)->[NSView] {[view]+view.subviews.flatMap{views($0)}}
        let originalLayout=layout.configuration,selected=model.selectedChangeID,originalInspector=model.inspectorVisible
        let rows=try JSON(model.changes.map(\.raw)).data(),query=model.comparisonScope,fixed=try model.report.data()
        var queried=false;let observer=model.$loadingChanges.dropFirst().sink{if $0{queried=true}};defer{observer.cancel()}
        await model.selectCell(candidate["row"].int,candidate["column"].int);model.inspectorVisible=false;layout.update{$0.inspectorVisible=false}
        try await Task.sleep(nanoseconds:200_000_000)
        let tables=["before","after"].compactMap{grid(content,pane:$0)},states=tables.map{($0,$0.dataSource as AnyObject?,$0.enclosingScrollView!.contentView.bounds.origin,$0.selectedRow,$0.enclosingScrollView!.contentView.bounds.width)}
        if let table=tables.first {_ = window.makeFirstResponder(table)}
        guard let button=views(content).compactMap({$0 as? NSButton}).first(where:{$0.identifier?.rawValue=="Reviset.workbook.cellDetailsAction"}),button.isEnabled,!button.visibleRect.isEmpty else{throw BridgeError(code:"WORKBOOK_CELL_DETAILS_ACTION",message:"Focused physical cell has no visible native Cell details action.")}
        let identity=[model.beforeID,model.afterID,model.beforeSheetID,model.afterSheetID,model.beforeAddress,model.afterAddress,model.selectedChangeID],before=try model.beforeCell.data(),after=try model.afterCell.data()
        button.performClick(nil);try await Task.sleep(nanoseconds:250_000_000)
        guard model.inspectorVisible,let details=workspaceLayoutMarkers(in:content).first(where:{$0.identifier?.rawValue=="Reviset.workbook.cellDetails"}),!details.visibleRect.isEmpty,[model.beforeCell,model.afterCell].contains(where:{$0["value"].string.utf16.elementsEqual(literal.utf16)}),workspaceLayoutMarkers(in:content).contains(where:{$0.identifier?.rawValue=="Reviset.workbook.inspector.raw.value" && !$0.visibleRect.isEmpty}),try model.beforeCell.data()==before,try model.afterCell.data()==after,identity==[model.beforeID,model.afterID,model.beforeSheetID,model.afterSheetID,model.beforeAddress,model.afterAddress,model.selectedChangeID] else{throw BridgeError(code:"WORKBOOK_CELL_DETAILS_SOURCE",message:"Cell details did not reveal the existing bounded raw reader or changed physical source authority.")}
        var horizontalReveal:[[String:Any]]=[],geometryValid=true
        for (table,coordinator,origin,row,width) in states {
            guard let scroll=table.enclosingScrollView as? WorkbookTableScrollView,let owner=table.dataSource as? WorkbookGrid.Coordinator else{geometryValid=false;horizontalReveal.append(["table":table.identifier?.rawValue ?? "nil","missing_native_owner":true]);continue}
            let column=table.tableColumns.firstIndex(where:{$0.identifier.rawValue==String(owner.parent.selectedColumn)}),rowLabel=scroll.pinnedRowLabel(owner.parent.selectedRow),actual=scroll.contentView.bounds
            let hostRetained=views(content).contains(where:{$0===table}),coordinatorRetained=(table.dataSource as AnyObject?) === coordinator,verticalRetained=abs(actual.origin.y-origin.y)<0.5,selectionRetained=table.selectedRow==row,columnVisible=column.map{scroll.columnVisibleToRightOfGutter($0)} ?? false,rowVisible=rowLabel.map{!$0.visibleRect.isEmpty} ?? false
            geometryValid = geometryValid && hostRetained && coordinatorRetained && verticalRetained && selectionRetained && columnVisible && rowVisible
            horizontalReveal.append(["pane":owner.parent.pane,"before_x":Double(origin.x),"after_x":Double(actual.origin.x),"vertical_origin":Double(origin.y),"after_y":Double(actual.origin.y),"before_width":Double(width),"after_width":Double(actual.width),"column_rect":column.map{NSStringFromRect(table.rect(ofColumn:$0))} ?? "missing","gutter_rect":NSStringFromRect(scroll.pinnedRowGutter.frame),"table_visible_rect":NSStringFromRect(table.visibleRect),"inspected_column":owner.parent.selectedColumn,"inspected_column_visible_right_of_gutter":columnVisible,"physical_row_label_visible":rowVisible,"physical_row_label":rowLabel?.stringValue ?? "missing","host_retained":hostRetained,"coordinator_retained":coordinatorRetained,"selection_retained":selectionRetained,"vertical_origin_retained":verticalRetained,"pending_reveal":scroll.pendingCellDetailsReveal != nil])
        }
        guard geometryValid else {
            let facts=JSON(["panes":horizontalReveal]);try? facts.data().write(to:folder.appendingPathComponent("cell-details-geometry-failure.json"))
            throw BridgeError(code:"WORKBOOK_CELL_DETAILS_HOST",message:"Cell details must retain hosts, selection and vertical origin while revealing the inspected column beside the pinned row gutter. Geometry: "+(String(data:(try? facts.data()) ?? Data(),encoding:.utf8) ?? "unavailable"))
        }
        let segments=[("before",model.beforeCell),("after",model.afterCell)].map {side,cell->[String:Any] in
            ["side":side,"address":cell["address"].string,"fields":["value","formula","number_format"].map {field->[String:Any] in let raw=cell[field].string,continuation=cell["text_continuations"][field];return ["field":field,"raw_utf16":Array(raw.utf16).map(Int.init),"state":continuation["state"].string,"offset":continuation["offset"].int,"observed_end":continuation["offset"].int+raw.utf16.count,"total_length":continuation["total_length"].int,"next_offset":continuation["next_offset"].raw] }]
        }
        try Smoke.captureView(window,folder.appendingPathComponent("native-workbook-cell-details.png"))
        let oversizedChecks=try await exerciseOversizedCellDetails(model,layout:layout,window:window,button:button,tables:tables)
        model.inspectorVisible=originalInspector;layout.update{$0=originalLayout};await model.returnToChange();try await Task.sleep(nanoseconds:200_000_000)
        guard !queried,model.comparisonScope==query,try JSON(model.changes.map(\.raw)).data()==rows,try model.report.data()==fixed,model.selectedChangeID==selected else{throw BridgeError(code:"WORKBOOK_CELL_DETAILS_RESTORE",message:"Cell details qualification replaced the query/list/report or failed to restore the selected event.")}
        return ["qualified":true,"native_action_performed":true,"existing_bounded_raw_reader_visible":true,"literal_unchanged":literal,"address":candidate["address"].string,"physical_scope_retained_by_action":true,"query_list_report_and_selected_event_restored_without_query":true,"grid_hosts_coordinators_selection_and_vertical_viewports_retained_by_action":true,"explicit_horizontal_reveal_only":true,"horizontal_reveal":horizontalReveal,"inspected_columns_visible_right_of_pinned_gutter":true,"physical_row_gutter_labels_visible":true,"oversized_column_one_shot_checks":oversizedChecks,"source_segments":segments,"capture":"native-workbook-cell-details.png","interaction_scope":"actual packaged production native button performClick; horizontal reveal is explicit while source scope, selected cells, retained hosts and vertical origins stay fixed; no OS input or value beyond recorded continuation bounds"]
    }
    private static func exerciseOversizedCellDetails(_ model:WorkbookModel,layout:WorkspaceLayoutStore,window:NSWindow,button:NSButton,tables:[NSTableView])async throws->[String:Any] {
        guard let content=window.contentView else{throw BridgeError(code:"WORKBOOK_CELL_DETAILS_OVERSIZED",message:"Oversized column qualification has no window content.")}
        func views(_ view:NSView)->[NSView] {[view]+view.subviews.flatMap{views($0)}}
        let originalSize=content.bounds.size,configuration=layout.configuration,originalOrigins=tables.map{$0.enclosingScrollView!.contentView.bounds.origin},before=try model.beforeCell.data(),after=try model.afterCell.data(),identity=[model.rangeScope,model.comparisonScope,model.beforeAddress,model.afterAddress,model.selectedChangeID,String(model.selectedRow),String(model.selectedColumn),String(model.revealGeneration)]
        var columns:[(NSTableColumn,CGFloat,CGFloat)]=[],facts:[[String:Any]]=[]
        defer {
            for (column,width,maximum) in columns {column.width=width;column.maxWidth=maximum}
            for table in tables {table.tile()}
            layout.update{$0=configuration};window.setContentSize(originalSize)
            for (table,origin) in zip(tables,originalOrigins) {if let scroll=table.enclosingScrollView {scroll.contentView.scroll(to:origin);scroll.reflectScrolledClipView(scroll.contentView)}}
        }
        for table in tables {
            guard let owner=table.dataSource as? WorkbookGrid.Coordinator,let column=table.tableColumns.first(where:{$0.identifier.rawValue==String(owner.parent.selectedColumn)}),let scroll=table.enclosingScrollView else{throw BridgeError(code:"WORKBOOK_CELL_DETAILS_OVERSIZED",message:"Oversized column qualification lost its physical source owner.")}
            columns.append((column,column.width,column.maxWidth));column.maxWidth=2000;column.width=1600;table.tile()
            scroll.contentView.scroll(to:NSPoint(x:0,y:scroll.contentView.bounds.origin.y));scroll.reflectScrolledClipView(scroll.contentView)
        }
        let states=tables.map{($0,$0.dataSource as AnyObject?,$0.selectedRow,$0.enclosingScrollView!.contentView.bounds.origin.y)}
        button.performClick(nil);try await Task.sleep(nanoseconds:150_000_000)
        for (table,owner,row,y) in states {
            guard let scroll=table.enclosingScrollView as? WorkbookTableScrollView,let coordinator=table.dataSource as? WorkbookGrid.Coordinator,let index=table.tableColumns.firstIndex(where:{$0.identifier.rawValue==String(coordinator.parent.selectedColumn)}),table.rect(ofColumn:index).width>scroll.contentView.bounds.width,!scroll.columnVisibleToRightOfGutter(index),scroll.pendingCellDetailsReveal==nil,scroll.contentView.bounds.origin.y==y,table.selectedRow==row,(table.dataSource as AnyObject?) === owner else{throw BridgeError(code:"WORKBOOK_CELL_DETAILS_OVERSIZED",message:"A column that cannot fit retained reveal authority or moved its physical source.")}
            facts.append(try oversizedLeadingSourceFacts(table,column:index,row:row))
            scroll.contentView.scroll(to:NSPoint(x:127,y:y));scroll.reflectScrolledClipView(scroll.contentView)
        }
        let fragmentCount=facts.filter{$0["native_text_leading_fragment_visible"] as? Bool == true}.count
        guard fragmentCount>0 else{throw BridgeError(code:"WORKBOOK_CELL_DETAILS_OVERSIZED_TEXT",message:"Oversized column qualification has no observed nonempty leading source text fragment.")}
        let origins=tables.map{$0.enclosingScrollView!.contentView.bounds.origin}
        window.setContentSize(NSSize(width:originalSize.width+64,height:originalSize.height));try await Task.sleep(nanoseconds:100_000_000)
        guard let pages=views(content).compactMap({$0 as? NSSplitView}).first(where:{$0.identifier?.rawValue=="Reviset.workspace.workbook.pages"}),let sizing=pages.delegate as? WorkspacePaneSizing,let auxiliary=pages.arrangedSubviews.last else{throw BridgeError(code:"WORKBOOK_CELL_DETAILS_OVERSIZED",message:"Oversized column qualification has no native page divider.")}
        sizing.resizeAuxiliary(to:(pages.isVertical ? auxiliary.frame.width:auxiliary.frame.height)+25,commit:true);try await Task.sleep(nanoseconds:100_000_000)
        for ((table,owner,row,_),origin) in zip(states,origins) {
            guard let scroll=table.enclosingScrollView as? WorkbookTableScrollView,scroll.pendingCellDetailsReveal==nil,scroll.contentView.bounds.origin==origin,table.selectedRow==row,(table.dataSource as AnyObject?) === owner else{throw BridgeError(code:"WORKBOOK_CELL_DETAILS_OVERSIZED",message:"Passive window/divider geometry replayed a completed oversized-column reveal or changed selection/owner.")}
        }
        guard try model.beforeCell.data()==before,try model.afterCell.data()==after,identity==[model.rangeScope,model.comparisonScope,model.beforeAddress,model.afterAddress,model.selectedChangeID,String(model.selectedRow),String(model.selectedColumn),String(model.revealGeneration)] else{throw BridgeError(code:"WORKBOOK_CELL_DETAILS_OVERSIZED",message:"Oversized column qualification changed physical raw source or query scope.")}
        return ["qualified":true,"panes":facts,"observed_nonempty_leading_fragment_count":fragmentCount,"manual_horizontal_origin":127,"pending_consumed_after_first_ready_attempt":true,"later_passive_window_and_divider_geometry_did_not_pan":true,"vertical_selection_hosts_and_source_scope_retained":true,"widths_layout_window_and_viewports_restored_before_return":true]
    }
    // Shared shipped-qualification assertion: local native regressions exercise
    // the same distinction between missing observations and missing native views.
    static func oversizedLeadingSourceFacts(_ table:NSTableView,column:Int,row:Int)throws->[String:Any] {
        guard let scroll=table.enclosingScrollView as? WorkbookTableScrollView,let owner=table.dataSource as? WorkbookGrid.Coordinator,column>0,column<table.numberOfColumns,row>=0,row<table.numberOfRows,let physicalColumn=Int(table.tableColumns[column].identifier.rawValue) else{throw BridgeError(code:"WORKBOOK_CELL_DETAILS_OVERSIZED_OWNER",message:"Oversized source qualification has no valid native physical owner or coordinate.")}
        let physicalRow=owner.parent.rowStart+row,address=WorkbookGrid.address(physicalRow,physicalColumn),observation=owner.sparse["\(physicalRow):\(physicalColumn)"],value=observation?["value"] ?? JSON(),raw=value.isNull ? "":value.string
        let state=observation==nil ? "missing_observation":value.isNull ? "null_value":raw.isEmpty ? "empty_string":"nonempty_string",diagnostic="pane=\(owner.parent.pane), address=\(address), source=\(state), expectedUTF16=\(raw.utf16.count)"
        guard let cell=table.view(atColumn:column,row:row,makeIfNecessary:true) as? NSTableCellView else{throw BridgeError(code:"WORKBOOK_CELL_DETAILS_OVERSIZED_CELL",message:"Oversized source has no native cell; "+diagnostic)}
        guard let text=cell.textField else{throw BridgeError(code:"WORKBOOK_CELL_DETAILS_OVERSIZED_FIELD",message:"Oversized source cell has no native text field; "+diagnostic)}
        guard text.stringValue.utf16.elementsEqual(raw.utf16) else{throw BridgeError(code:"WORKBOOK_CELL_DETAILS_OVERSIZED_RAW",message:"Oversized native source differs from the exact grid observation; "+diagnostic+", nativeUTF16=\(text.stringValue.utf16.count)")}
        cell.layoutSubtreeIfNeeded()
        let leadingError=abs(table.rect(ofColumn:column).minX-scroll.contentView.bounds.minX-scroll.pinnedRowGutter.frame.width),applicable = !raw.isEmpty
        var usable=scroll.contentView.convert(scroll.contentView.bounds,to:scroll);usable.origin.x += scroll.pinnedRowGutter.frame.width;usable.size.width -= scroll.pinnedRowGutter.frame.width
        guard leadingError<0.5 else{throw BridgeError(code:"WORKBOOK_CELL_DETAILS_OVERSIZED_LEADING",message:"Oversized source column is not aligned beside the gutter; "+diagnostic)}
        var fragmentValue:Any=NSNull(),fragmentRect:Any=NSNull()
        if applicable {
            let fragment=text.convert(NSRect(x:text.bounds.minX,y:text.bounds.midY-2,width:min(12,text.bounds.width),height:4),to:scroll)
            guard usable.contains(fragment),!text.visibleRect.isEmpty else{throw BridgeError(code:"WORKBOOK_CELL_DETAILS_OVERSIZED_TEXT",message:"Oversized observed source text has no visible leading fragment; "+diagnostic)}
            fragmentValue=true;fragmentRect=NSStringFromRect(fragment)
        }
        return ["pane":owner.parent.pane,"physical_address":address,"source_observation_state":state,"source_observation_present":observation != nil,"native_cell_present":true,"native_text_field_present":true,"expected_raw_utf16":Array(raw.utf16).map(Int.init),"native_raw_utf16":Array(text.stringValue.utf16).map(Int.init),"raw_utf16_exact":true,"column_width":Double(table.rect(ofColumn:column).width),"viewport_width":Double(scroll.contentView.bounds.width),"whole_column_cannot_fit":table.rect(ofColumn:column).width>usable.width,"pending_nil_after_attempt":scroll.pendingCellDetailsReveal==nil,"leading_edge_alignment_error":Double(leadingError),"source_text_visibility_applicable":applicable,"text_visibility_check":applicable ? "visible":"not_applicable_no_raw_text","native_text_leading_fragment_visible":fragmentValue,"leading_fragment_rect":fragmentRect,"usable_viewport_rect":NSStringFromRect(usable)]
    }
    private static func rawSavedValueCellFacts(_ model:WorkbookModel,content:NSView)throws->[[String:Any]] {
        var facts:[[String:Any]]=[]
        for before in [true,false] {
            let source=before ? model.beforeCells:model.afterCells,rowStart=before ? model.beforeRowStart:model.afterRowStart,columnStart=before ? model.beforeColumnStart:model.afterColumnStart
            guard let table=grid(content,pane:before ? "before":"after") else{continue}
            for value in source where value["value"].string=="stored only; not recalculated" {
                let row=value["row"].int-rowStart,column=value["column"].int-columnStart+1,raw=value["value"].string
                guard row>=0,column>0,column<table.numberOfColumns,let cell=table.view(atColumn:column,row:row,makeIfNecessary:true) as? NSTableCellView,let text=cell.textField else{throw BridgeError(code:"WORKBOOK_RAW_CELL",message:"Stored fixture value has no actual native cell.")}
                cell.layoutSubtreeIfNeeded()
                guard text.stringValue.contains(raw),cell.toolTip?.contains(raw)==true,text.maximumNumberOfLines==1,text.lineBreakMode == .byTruncatingTail,cell.layer?.masksToBounds==true,text.frame.minX>=2,text.frame.maxX<=cell.bounds.maxX-2 else{throw BridgeError(code:"WORKBOOK_RAW_CELL_CLIP",message:"Raw saved value was changed, crossed its cell boundary, or lacked its full observed value in the tooltip.")}
                facts.append(["pane":before ? "before":"after","occurrence":before ? model.beforeID:model.afterID,"sheet_id":before ? model.beforeSheetID:model.afterSheetID,"address":value["address"].string,"source_value":raw,"source_utf16":Array(raw.utf16).map(Int.init),"native_field_value":text.stringValue,"single_line":true,"tail_truncation":true,"native_cell_clip":true,"full_observed_value_in_tooltip":true,"cell_width":Double(cell.bounds.width),"text_min_x":Double(text.frame.minX),"text_max_x":Double(text.frame.maxX)])
            }
        }
        return facts
    }
    private static func exerciseLayouts(_ model:WorkbookModel,layout:WorkspaceLayoutStore,window:NSWindow,folder:URL)async throws->[String:Any] {
        let original=layout.configuration
        defer{layout.update{$0=original}}
        guard let content=window.contentView,!model.changes.isEmpty else{throw BridgeError(code:"WORKBOOK_LAYOUT_FIXTURE",message:"A rendered workbook with changes is required for layout qualification.")}
        let identity=[model.projectID,model.reportID,model.beforeID,model.afterID,model.beforeSheetID,model.afterSheetID,model.selectedChangeID,String(model.selectedRow),String(model.selectedColumn)]
        let rawBefore=try model.beforeCell.data(),rawAfter=try model.afterCell.data()
        struct Pane {let table:NSTableView;let coordinator:WorkbookGrid.Coordinator;let reveal:String;let selected:Int;let origin:NSPoint}
        var panes:[String:Pane]=[:]
        for name in ["before","after"] {
            guard let table=grid(content,pane:name),let coordinator=table.dataSource as? WorkbookGrid.Coordinator,let scroll=table.enclosingScrollView else{continue}
            panes[name]=Pane(table:table,coordinator:coordinator,reveal:coordinator.parent.revealIntent,selected:table.selectedRow,origin:scroll.contentView.bounds.origin)
        }
        guard !panes.isEmpty else{throw BridgeError(code:"WORKBOOK_LAYOUT_GRID",message:"No live workbook grid is available.")}
        func retainedState()throws {
        let current=[model.projectID,model.reportID,model.beforeID,model.afterID,model.beforeSheetID,model.afterSheetID,model.selectedChangeID,String(model.selectedRow),String(model.selectedColumn)]
        guard current==identity,try model.beforeCell.data()==rawBefore,try model.afterCell.data()==rawAfter else{throw BridgeError(code:"WORKBOOK_LAYOUT_STATE",message:"Docking changed the selected report, cell or raw evidence.")}
        for (name,pane) in panes {
            guard let table=grid(content,pane:name),let coordinator=table.dataSource as? WorkbookGrid.Coordinator,let scroll=table.enclosingScrollView,table === pane.table,coordinator === pane.coordinator,coordinator.parent.revealIntent==pane.reveal,table.selectedRow==pane.selected else{throw BridgeError(code:"WORKBOOK_LAYOUT_IDENTITY",message:"Docking replaced a grid/coordinator or reset its selection/reveal authority.")}
            let maximum=NSPoint(x:max(0,scroll.documentView!.frame.width-scroll.contentView.bounds.width),y:max(0,scroll.documentView!.frame.height-scroll.contentView.bounds.height))
            guard abs(scroll.contentView.bounds.minX-min(pane.origin.x,maximum.x))<1,abs(scroll.contentView.bounds.minY-min(pane.origin.y,maximum.y))<1 else{throw BridgeError(code:"WORKBOOK_LAYOUT_VIEWPORT",message:"Docking moved the manual grid viewport beyond native size clamping.")}
        }
        }
        var geometry:[[String:Any]]=[]
        for dock in [WorkspaceChangesDock.left,.right] {
            layout.apply(.review);layout.update{$0.changesDock=dock;$0.inspectorDock=dock == .left ? .right:.left}
            try await Task.sleep(nanoseconds:350_000_000);content.layoutSubtreeIfNeeded()
            try retainedState()
            func split(_ view:NSView)->NSSplitView? {
                if let candidate=view as? NSSplitView,candidate.identifier?.rawValue=="Reviset.workspace.workbook.changes" {return candidate}
                return view.subviews.lazy.compactMap(split).first
            }
            guard let changes=split(content),let list=workspaceLayoutMarkers(in:content).first(where:{$0.identifier?.rawValue=="Reviset.workbook.changes.list"}),changes.arrangedSubviews.count==2 else{throw BridgeError(code:"WORKBOOK_LAYOUT_LIST",message:"The docked change list is unavailable.")}
            let pane=changes.arrangedSubviews[dock == .left ? 0:1],fraction=list.bounds.height/pane.bounds.height
            guard list.visibleRect.height>=pane.bounds.height*0.6,fraction>=0.6 else{throw BridgeError(code:"WORKBOOK_LAYOUT_LIST_HEIGHT",message:"The \(dock.rawValue) change list occupies only \(fraction) of its pane height.")}
            let file="native-workbook-layout-"+LanguagePreferences.shared.effectiveLanguage+"-changes-"+dock.rawValue+".png"
            try Smoke.captureView(window,folder.appendingPathComponent(file))
            geometry.append(["dock":dock.rawValue,"pane_height":pane.bounds.height,"list_height":list.bounds.height,"visible_list_height":list.visibleRect.height,"list_fraction":fraction,"capture":file])
        }
        layout.update{$0.sidebarVisible=true;$0.inspectorVisible=true;$0.changesVisible=true;$0.sidebarWidth=279;$0.changesDock = .right;$0.changesWidth=389;$0.inspectorDock = .left;$0.inspectorWidth=341;$0.pageArrangement = .horizontal;$0.pageFraction=0.37}
        try await Task.sleep(nanoseconds:250_000_000);try retainedState()
        let custom=layout.configuration
        layout.toggleFocus();try await Task.sleep(nanoseconds:250_000_000);try retainedState()
        layout.update{$0.pageFraction=0.63;$0.pageArrangement = .vertical;$0.sidebarWidth=301;$0.changesDock = .left;$0.changesWidth=417;$0.inspectorWidth=355}
        var merged=custom;merged.pageFraction=0.63;merged.pageArrangement = .vertical;merged.sidebarWidth=301;merged.changesDock = .left;merged.changesWidth=417;merged.inspectorWidth=355
        try await Task.sleep(nanoseconds:250_000_000);try retainedState()
        guard layout.saveCurrent(named:"Workbook Focus QA"),let named=layout.saved.last,named.configuration==merged,layout.isFocused else{throw BridgeError(code:"WORKBOOK_FOCUS_NAMED_SAVE",message:"Saving during workbook Focus captured transient hidden panels or left Focus.")}
        let stored=WorkspaceLayoutStore(scope:.workbook),mergedBytes=WorkspaceLayoutPreferences.data(.workbook)
        guard layout.isFocused,!stored.isFocused,stored.configuration==merged,stored.saved.contains(named) else{throw BridgeError(code:"WORKBOOK_FOCUS_PERSIST",message:"A focused workbook geometry edit or named save discarded its retained arrangement or persisted hidden panels.")}
        layout.toggleFocus();try await Task.sleep(nanoseconds:250_000_000);try retainedState()
        guard !layout.isFocused,layout.configuration==merged,WorkspaceLayoutPreferences.data(.workbook)==mergedBytes else{throw BridgeError(code:"WORKBOOK_FOCUS_RESTORE",message:"Leaving workbook Focus lost its edited arrangement or rewrote persisted bytes.")}
        layout.apply(.balanced);layout.apply(named);try await Task.sleep(nanoseconds:250_000_000);try retainedState()
        guard !layout.isFocused,layout.configuration==merged else{throw BridgeError(code:"WORKBOOK_FOCUS_NAMED_APPLY",message:"Reapplying the workbook layout saved during Focus lost retained visibility or geometry.")}
        layout.remove(named.id)
        let panels:[(String,WritableKeyPath<WorkspaceLayoutConfiguration,Bool>)]=[("projects",\.sidebarVisible),("changes",\.changesVisible),("evidence",\.inspectorVisible)]
        var visibilityExits:[[String:Any]]=[]
        for allHidden in [false,true] {
            for (name,panel) in panels {
                var baseline=merged;baseline.sidebarVisible = !allHidden;baseline.changesVisible = !allHidden;baseline.inspectorVisible = !allHidden
                layout.update{$0=baseline};layout.toggleFocus();try await Task.sleep(nanoseconds:250_000_000);try retainedState()
                layout.update{$0.pageFraction=0.57;$0.changesDock = .right;$0.changesHeight=247}
                layout.update{$0[keyPath:panel].toggle();$0.inspectorWidth=367}
                var expected=baseline;expected[keyPath:panel]=true;expected.pageFraction=0.57;expected.changesDock = .right;expected.changesHeight=247;expected.inspectorWidth=367
                try await Task.sleep(nanoseconds:250_000_000);try retainedState()
                let reopened=WorkspaceLayoutStore(scope:.workbook)
                guard !layout.isFocused,!reopened.isFocused,layout.configuration==expected,reopened.configuration==expected else{throw BridgeError(code:"WORKBOOK_FOCUS_VISIBILITY",message:"Opening a workbook panel from Focus discarded unrelated retained panels or edited geometry.")}
                visibilityExits.append(["panel":name,"previously_all_hidden":allHidden,"sidebar_visible":expected.sidebarVisible,"changes_visible":expected.changesVisible,"inspector_visible":expected.inspectorVisible])
            }
        }
        layout.update{$0=original};try await Task.sleep(nanoseconds:250_000_000)
        return ["transitions":geometry,"minimum_visible_list_fraction":0.6,"report_selection_raw_cells_grid_coordinator_and_viewport_preserved":true,"focused_geometry_merges_into_persisted_baseline":true,"focus_exit_restores_custom_visibility_and_edited_geometry":true,"focused_named_save_reload_and_apply_retain_baseline":true,"focused_visibility_exit_merges_only_changed_flags":visibilityExits,"interaction_scope":"actual packaged production layout actions and native geometry; no OS gestures"]
    }
    private static func exerciseLanguageSwitch(_ model: WorkbookModel,window: NSWindow,folder: URL,originals: [WorkbookImportRow]) async throws -> [String:Any] {
        let preferences = LanguagePreferences.shared,defaults = UserDefaults.standard
        let originalSelection = preferences.selection
        let preferenceDomain = Bundle.main.bundleIdentifier ?? "org.docver.native"
        let originalStoredPreference = defaults.persistentDomain(forName:preferenceDomain)?[LanguagePreferences.preferenceKey]
        var preferenceRestored = false
        func restorePreference() {
            preferences.selection = originalSelection
            if let originalStoredPreference { defaults.set(originalStoredPreference,forKey:LanguagePreferences.preferenceKey) }
            else { defaults.removeObject(forKey:LanguagePreferences.preferenceKey) }
            preferenceRestored = true
        }
        defer { if !preferenceRestored { restorePreference() } }
        func require(_ condition: Bool,_ message: String) throws {
            guard condition else { throw BridgeError(code:"WORKBOOK_SMOKE_LOCALIZATION",message:message) }
        }
        guard let first = model.revisions.first,let last = model.revisions.last else {
            throw BridgeError(code:"WORKBOOK_SMOKE_LOCALIZATION_FIXTURE",message:"A pinned workbook with source revisions is required.")
        }
        // Exercise real production status and validation-message creation before
        // changing the language. No localized string is injected into the model.
        await model.changeVersions(before:last["revision_occurrence_id"].string,after:first["revision_occurrence_id"].string)
        let observed = model.afterCells.first(where:{!$0["value"].isNull}) ?? model.beforeCells.first(where:{!$0["value"].isNull})
        if let observed { await model.selectCell(observed["row"].int,observed["column"].int) }
        else { await model.selectCell(1,1) }
        let previousInput = model.addressInput
        defer { model.addressInput = previousInput; model.addressFailure = "" }
        let opaqueInput = "Draft {0} 원문 🙂"
        model.addressInput = opaqueInput
        await model.goToAddress()
        try require(!model.addressFailure.isEmpty,"The production address-validation warning was not created.")
        let selected = [model.projectID,model.reportID,model.beforeID,model.afterID,model.beforeSheetID,model.afterSheetID,model.beforeAddress,model.afterAddress,model.selectedChangeID,String(model.selectedRow),String(model.selectedColumn),String(model.revealGeneration),model.rangeScope,model.comparisonScope]
        let reportBytes = try model.report.data(),projectBytes = try model.project.data()
        let sourceCells = try JSON(["before":model.beforeCells.map(\.raw),"after":model.afterCells.map(\.raw),"before_cell":model.beforeCell.raw,"after_cell":model.afterCell.raw,"changes":model.changes.map(\.raw)]).data()
        let modelIdentity = ObjectIdentifier(model)
        var draftRow = try originals.first ?? WorkbookImportRow.bundledDemo(resources:model.bridge.resources).rows[0]
        draftRow.label = "Version {1} 원문 🙂"
        let draftTitle = "Opaque {0} 프로젝트 🙂",draftIdentity = draftRow.identity
        let draftView = WorkbookImportSheet(model:model,initialTitle:draftTitle,initialRows:[draftRow])
        let draftHost = NSHostingView(rootView:draftView.background(Color.white).preferredColorScheme(.light))
        let draftWindow = NSWindow(contentRect:NSRect(x:140,y:100,width:840,height:610),styleMask:[.titled,.closable],backing:.buffered,defer:false)
        draftWindow.title = "Workbook import localization qualification"
        draftWindow.isReleasedWhenClosed = false; draftWindow.isOpaque = true; draftWindow.backgroundColor = .white
        draftWindow.contentView = draftHost; draftWindow.makeKeyAndOrderFront(nil)
        defer { draftWindow.close() }
        let defaultDraftHost = NSHostingView(rootView:WorkbookImportSheet(model:model,initialRows:[draftRow]).background(Color.white).preferredColorScheme(.light))
        let defaultDraftWindow = NSWindow(contentRect:NSRect(x:180,y:140,width:840,height:610),styleMask:[.titled,.closable],backing:.buffered,defer:false)
        defaultDraftWindow.title = "Workbook default-title localization qualification"
        defaultDraftWindow.isReleasedWhenClosed = false; defaultDraftWindow.isOpaque = true; defaultDraftWindow.backgroundColor = .white
        defaultDraftWindow.contentView = defaultDraftHost; defaultDraftWindow.orderFront(nil)
        defer { defaultDraftWindow.close() }
        func fields(_ view: NSView?) -> [NSTextField] {
            guard let view else { return [] }
            return (view as? NSTextField).map { [$0] } ?? view.subviews.flatMap { fields($0) }
        }
        func checkDraft() throws -> [String:Any] {
            let actual = fields(draftWindow.contentView).filter(\.isEditable)
            // SwiftUI's semantic accessibility identifiers are not guaranteed to
            // propagate to the backing NSTextFields. Their localized placeholders
            // identify these two production controls without relying on that bridge.
            let titles = actual.filter { $0.placeholderString == L("workbook.import.projectName") }
            let labels = actual.filter { $0.placeholderString == L("workbook.import.versionName") }
            guard actual.count == 2,titles.count == 1,labels.count == 1,let title = titles.first,let label = labels.first,title !== label else {
                let found = actual.map { ["placeholder":$0.placeholderString ?? "","value":$0.stringValue,"native_ax_id":$0.accessibilityIdentifier()] }
                throw BridgeError(code:"WORKBOOK_SMOKE_LOCALIZATION_DRAFT",message:"The production import draft did not expose exactly one localized title and version field: \(found)")
            }
            try require(title.stringValue == draftTitle && label.stringValue == draftRow.label,"The production import draft lost its opaque title or version label.")
            try require(draftWindow.contentView === draftHost,"A language change replaced the import draft host.")
            return ["title":title.stringValue,"version_label":label.stringValue,"title_placeholder":title.placeholderString ?? "","version_placeholder":label.placeholderString ?? "","found_native_ax_ids":actual.map { $0.accessibilityIdentifier() }.filter { !$0.isEmpty },"field_identification":"unique localized placeholders on the two editable production NSTextFields; semantic SwiftUI AX identifier propagation is not asserted","host_identity_retained":true,"programmatic_seed_only":true]
        }
        func defaultTitleField() throws -> NSTextField {
            defaultDraftWindow.contentView?.layoutSubtreeIfNeeded()
            let actual = fields(defaultDraftWindow.contentView).filter { $0.isEditable && $0.placeholderString == L("workbook.import.projectName") }
            guard actual.count == 1,let field = actual.first else {
                throw BridgeError(code:"WORKBOOK_SMOKE_LOCALIZATION_DRAFT",message:"The unseeded production import draft did not expose a unique localized title field.")
            }
            return field
        }
        func checkDefaultTitle(_ expected: String) throws -> String {
            let field = try defaultTitleField()
            try require(defaultDraftWindow.contentView === defaultDraftHost && field.stringValue == expected,"The unseeded production import title did not follow its untouched/edited state.")
            return field.stringValue
        }
        func checkTechnicalRow() async throws -> [String:Any] {
            // Exercise the production grid at a coordinate where quantity
            // formatting would insert a separator, independent of fixture size.
            let state = WorkbookGrid(language:preferences.effectiveLanguage,pane:"technical-localization",revealIntent:"technical-row",cells:[],rowStart:1000,columnStart:1,rowCount:2,columnCount:1,selectedRow:1000,selectedColumn:1,onSelect:{_,_ in})
            let host = NSHostingView(rootView:state)
            let probe = NSWindow(contentRect:NSRect(x:160,y:120,width:300,height:110),styleMask:[.titled],backing:.buffered,defer:false)
            probe.isReleasedWhenClosed = false; probe.contentView = host; probe.orderFront(nil)
            defer { probe.close() }
            try await Task.sleep(nanoseconds:100_000_000)
            host.layoutSubtreeIfNeeded()
            guard let table = grid(host,pane:"technical-localization"),let row = table.view(atColumn:0,row:0,makeIfNecessary:true) as? NSTableCellView,let text = row.textField else {
                throw BridgeError(code:"WORKBOOK_SMOKE_LOCALIZATION",message:"The production row-1000 grid did not render.")
            }
            let expectedAX = L("workbook.grid.rowAX",.integer(1000))
            try require(text.stringValue == "1000" && text.accessibilityLabel() == expectedAX && expectedAX.contains("1000") && !expectedAX.contains("1,000"),"Technical row digits differ between the visible row header and its accessibility label.")
            return ["physical_row":1000,"visible_digits":text.stringValue,"row_ax":text.accessibilityLabel() ?? "","ungrouped_digits_match":true,"scope":"separately hosted production WorkbookGrid with an empty sparse coordinate window"]
        }
        struct Pane {
            let table: NSTableView
            let coordinator: WorkbookGrid.Coordinator
            let origin: NSPoint
            let reveal: String
            let lastRequested: String
            let lastRevealed: String
            let localRow: Int
            let physicalRow: Int
        }
        var panes: [String:Pane] = [:],originalOrigins: [String:NSPoint] = [:]
        defer {
            for (name,origin) in originalOrigins {
                guard let table = grid(window.contentView,pane:name),let scroll = table.enclosingScrollView else { continue }
                scroll.contentView.scroll(to:origin); scroll.reflectScrolledClipView(scroll.contentView)
            }
        }
        preferences.selection = .en
        try await Task.sleep(nanoseconds:300_000_000)
        window.contentView?.layoutSubtreeIfNeeded(); draftWindow.contentView?.layoutSubtreeIfNeeded(); defaultDraftWindow.contentView?.layoutSubtreeIfNeeded()
        let englishDraft = try checkDraft(),englishTechnicalRow = try await checkTechnicalRow()
        let englishDefaultTitle = try checkDefaultTitle(L("workbook.import.defaultTitle"))
        // Native focus/commit can echo an unchanged binding value. That is not
        // a user edit and must not freeze the generated default title.
        let untouchedField=try defaultTitleField()
        defaultDraftWindow.makeKeyAndOrderFront(nil)
        try require(defaultDraftWindow.makeFirstResponder(untouchedField),"The untouched title field could not receive native focus.")
        try require(defaultDraftWindow.makeFirstResponder(nil),"The untouched title field could not commit native focus.")
        try await Task.sleep(nanoseconds:100_000_000)
        _ = try checkDefaultTitle(englishDefaultTitle)
        for name in ["before","after"] {
            guard let table = grid(window.contentView,pane:name),let coordinator = table.dataSource as? WorkbookGrid.Coordinator,let scroll = table.enclosingScrollView else { continue }
            let clip = scroll.contentView; originalOrigins[name] = clip.bounds.origin
            // Leave the selected physical cell unchanged while placing the
            // viewport at a non-default position. Locale updates must not reveal it.
            let y = min(max(0,clip.documentRect.height-clip.bounds.height),clip.bounds.origin.y+54)
            clip.scroll(to:NSPoint(x:clip.bounds.origin.x,y:y)); scroll.reflectScrolledClipView(clip)
            let visibleRows = table.rows(in:table.visibleRect),localRow = max(0,min(coordinator.parent.rowCount-1,visibleRows.location))
            panes[name] = Pane(table:table,coordinator:coordinator,origin:clip.bounds.origin,reveal:coordinator.parent.revealIntent,lastRequested:coordinator.lastRequested,lastRevealed:coordinator.lastRevealed,localRow:localRow,physicalRow:coordinator.parent.rowStart+localRow)
        }
        try require(!panes.isEmpty,"No actual production workbook grid is visible.")
        func capturePanes() throws -> [String:[String:Any]] {
            var result: [String:[String:Any]] = [:]
            for (name,pane) in panes {
                guard let actual = grid(window.contentView,pane:name),let coordinator = actual.dataSource as? WorkbookGrid.Coordinator else { throw BridgeError(code:"WORKBOOK_SMOKE_LOCALIZATION",message:"The production grid disappeared.") }
                try require(actual === pane.table && coordinator === pane.coordinator,"A language change replaced the grid or its coordinator.")
                try require(coordinator.parent.language == preferences.effectiveLanguage,"The actual NSViewRepresentable did not receive the current display language.")
                try require(abs(actual.visibleRect.minX-pane.origin.x) <= 0.75 && abs(actual.visibleRect.minY-pane.origin.y) <= 0.75,"A language change moved the viewport.")
                try require(coordinator.parent.revealIntent == pane.reveal && coordinator.lastRequested == pane.lastRequested && coordinator.lastRevealed == pane.lastRevealed,"A language change altered selection/reveal authority.")
                try require(actual.tableColumns[0].title == L("workbook.grid.rowHeader"),"The cached row header did not refresh.")
                let rowCell = actual.view(atColumn:0,row:pane.localRow,makeIfNecessary:true) as? NSTableCellView
                let dataCell = actual.view(atColumn:1,row:pane.localRow,makeIfNecessary:true) as? NSTableCellView
                let expectedGridAX = name == "before" ? L("workbook.grid.beforeAX") : L("workbook.grid.afterAX")
                try require(actual.accessibilityLabel() == expectedGridAX,"The table accessibility label did not refresh.")
                try require(rowCell?.textField?.accessibilityLabel() == L("workbook.grid.rowAX",.integer(pane.physicalRow)),"The reusable row-cell accessibility label did not refresh.")
                try require(dataCell?.toolTip?.isEmpty == false,"The actual cell has no source tooltip.")
                result[name] = ["row_header":actual.tableColumns[0].title,"table_ax":actual.accessibilityLabel() ?? "","row_ax":rowCell?.textField?.accessibilityLabel() ?? "","cell_tooltip":dataCell?.toolTip ?? "","raw_display_value":dataCell?.textField?.stringValue ?? "","selected_local_row":actual.selectedRow,"viewport_x":Double(actual.visibleRect.minX),"viewport_y":Double(actual.visibleRect.minY),"reveal_intent":coordinator.parent.revealIntent,"grid_and_coordinator_identity_retained":true]
            }
            return result
        }
        let englishPanes = try capturePanes(),englishWarning = model.addressFailure,englishStatus = model.status
        try require(englishWarning == L("workbook.error.address"),"The typed English validation warning did not render.")
        try Smoke.captureView(window,folder.appendingPathComponent("native-workbook-localization-en.png"))
        try Smoke.captureView(draftWindow,folder.appendingPathComponent("native-workbook-import-draft-en.png"))
        preferences.selection = .ko
        try await Task.sleep(nanoseconds:300_000_000)
        window.contentView?.layoutSubtreeIfNeeded(); draftWindow.contentView?.layoutSubtreeIfNeeded(); defaultDraftWindow.contentView?.layoutSubtreeIfNeeded()
        let koreanDraft = try checkDraft(),koreanTechnicalRow = try await checkTechnicalRow(),koreanPanes = try capturePanes(),koreanWarning = model.addressFailure,koreanStatus = model.status
        let koreanDefaultTitle = try checkDefaultTitle(L("workbook.import.defaultTitle"))
        try require(englishDefaultTitle != koreanDefaultTitle,"An untouched default import title stayed in its opening language.")
        try require(koreanWarning == L("workbook.error.address") && koreanWarning != englishWarning,"A previously stored typed warning did not switch languages.")
        if model.revisions.count > 1 {
            try require(englishStatus != koreanStatus && koreanStatus == L("workbook.status.sortedVersions"),"A previously stored production status did not switch languages.")
        }
        for name in panes.keys {
            try require(englishPanes[name]?["cell_tooltip"] as? String != koreanPanes[name]?["cell_tooltip"] as? String,"A cached cell tooltip did not switch languages.")
            try require(englishPanes[name]?["raw_display_value"] as? String == koreanPanes[name]?["raw_display_value"] as? String,"Changing display language changed raw cell display text.")
            try require(englishPanes[name]?["selected_local_row"] as? Int == koreanPanes[name]?["selected_local_row"] as? Int,"Changing display language changed the native selection.")
        }
        try require(model.addressInput == opaqueInput && ObjectIdentifier(model) == modelIdentity,"A language change replaced the model or changed a user draft.")
        let currentSelection = [model.projectID,model.reportID,model.beforeID,model.afterID,model.beforeSheetID,model.afterSheetID,model.beforeAddress,model.afterAddress,model.selectedChangeID,String(model.selectedRow),String(model.selectedColumn),String(model.revealGeneration),model.rangeScope,model.comparisonScope]
        try require(currentSelection == selected,"A language change altered physical coordinates, scope, or reveal intent.")
        try require(try model.report.data() == reportBytes && model.project.data() == projectBytes,"A language change altered report/project metadata.")
        let currentCells = try JSON(["before":model.beforeCells.map(\.raw),"after":model.afterCells.map(\.raw),"before_cell":model.beforeCell.raw,"after_cell":model.afterCell.raw,"changes":model.changes.map(\.raw)]).data()
        try require(currentCells == sourceCells,"A language change altered source observations or change evidence.")
        let reread = try await model.bridge.call("workbookView",["project_id":model.projectID,"report_id":model.reportID])
        try require(try reread.data() == reportBytes,"A language change altered the stored pinned report.")
        for original in originals { try require(try ImportFileIdentity.capture(original.url) == original.identity,"A language change altered original workbook bytes.") }
        try require(try ImportFileIdentity.capture(draftRow.url) == draftIdentity,"The unsubmitted draft changed source bytes.")
        try Smoke.captureView(window,folder.appendingPathComponent("native-workbook-localization-ko.png"))
        try Smoke.captureView(draftWindow,folder.appendingPathComponent("native-workbook-import-draft-ko.png"))
        // Deliver the public text-edit delegate notification to the actual
        // production NSTextField. This is an explicit programmatic edit, not OS
        // keyboard input; its SwiftUI Binding must retain the deliberate clear.
        let clearField = try defaultTitleField()
        guard let delegate = clearField.delegate,delegate.responds(to:NSSelectorFromString("controlTextDidChange:")) else {
            throw BridgeError(code:"WORKBOOK_SMOKE_LOCALIZATION_DRAFT",message:"The production title field has no text-edit delegate.")
        }
        clearField.stringValue = ""
        delegate.controlTextDidChange?(Notification(name:NSControl.textDidChangeNotification,object:clearField))
        try await Task.sleep(nanoseconds:100_000_000)
        _ = try checkDefaultTitle("")
        preferences.selection = .en
        try await Task.sleep(nanoseconds:300_000_000)
        let returnedEnglishDraft = try checkDraft(),clearedEnglishTitle = try checkDefaultTitle("")
        restorePreference()
        let restored = defaults.persistentDomain(forName:preferenceDomain)?[LanguagePreferences.preferenceKey]
        let storedPreferenceRestored = originalStoredPreference == nil ? restored == nil : (originalStoredPreference as? NSObject)?.isEqual(restored) == true
        try require(storedPreferenceRestored && preferences.selection == originalSelection,"The exact prior language preference was not restored.")
        return ["en":["panes":englishPanes,"warning":englishWarning,"status":englishStatus,"draft":englishDraft,"technical_row":englishTechnicalRow],"ko":["panes":koreanPanes,"warning":koreanWarning,"status":koreanStatus,"draft":koreanDraft,"technical_row":koreanTechnicalRow],"return_to_en_draft":returnedEnglishDraft,"default_title":["en":englishDefaultTitle,"ko":koreanDefaultTitle,"cleared_then_switched_to_en":clearedEnglishTitle,"same_host_retained":true,"clear_scope":"programmatic NSTextField controlTextDidChange delegate notification; no OS keyboard input or submitted import"],"same_model_grid_selection_viewport_and_reveal_intent":true,"source_cells_changes_project_and_stored_report_unchanged":true,"original_sha_and_size_unchanged":true,"preference_restored_exactly":true,"original_preference_entry_present":originalStoredPreference != nil,"draft_host":"opaque white NSWindows with NSHostingView of production WorkbookImportSheet; seeded and unseeded @State, one programmatic clear, no submitted import or OS input","capture_scope":"actual packaged production main window and import component; programmatic locale/scroll changes, no VoiceOver automation"]
    }
    private static func checkBlankFormattingWarning(_ model: WorkbookModel,request: JSON) throws -> [String:Any] {
        guard model.ready,!model.loadingChanges,model.changesFailure.isEmpty,(!model.blankFormattingWarning.isEmpty) == request["expected_blank_formatting_warning"].bool else { throw BridgeError(code:"WORKBOOK_SMOKE_FORMATTING_WARNING",message:"현재 비교 구간의 빈 셀 서식 판독 한계 안내가 예상과 다릅니다.") }
        if request.dictionary.keys.contains("expected_blank_formatting_empty"),model.changes.isEmpty != request["expected_blank_formatting_empty"].bool { throw BridgeError(code:"WORKBOOK_SMOKE_FORMATTING_EMPTY",message:"빈 셀 서식 안내를 검증할 변경 목록의 빈 상태가 예상과 다릅니다.") }
        return ["warning":model.blankFormattingWarning,"empty_changes":model.changes.isEmpty,"comparison_scope":model.comparisonScope]
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
            let selectedSource=[model.beforeID,model.afterID,model.beforeSheetID,model.afterSheetID,model.beforeAddress,model.afterAddress],selectedRaw=[try model.beforeCell.data(),try model.afterCell.data()]
            await model.loadChanges(next:true)
            guard model.changePageNumber == 2,model.selectedChangeID==last,model.selectedChange["change_id"].string==last,selectedSource==[model.beforeID,model.afterID,model.beforeSheetID,model.afterSheetID,model.beforeAddress,model.afterAddress],selectedRaw==[try model.beforeCell.data(),try model.afterCell.data()],model.changesFailure.isEmpty else { throw BridgeError(code:"WORKBOOK_SMOKE_PAGE_AUTHORITY",message:"페이지 교체가 선택한 변경의 고정된 원본 근거를 바꿨습니다.") }
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
            let physicalColumn = state.columnStart+index-1,expectedID = index == 0 ? "row" : String(physicalColumn),expectedTitle = index == 0 ? L("workbook.grid.rowHeader") : WorkbookGrid.columnLabel(physicalColumn)
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
            let gutterVisible=(table.enclosingScrollView as? WorkbookTableScrollView)?.pinnedRowLabel(coordinate.row).map{!$0.isHiddenOrHasHiddenAncestor && !$0.visibleRect.isEmpty} ?? false
            guard gutterVisible else { throw BridgeError(code:"WORKBOOK_SMOKE_ROW_GUTTER",message:"고정된 행 번호가 실제 셀 근거 옆에 표시되지 않았습니다: " + name) }
            let cell = before ? model.beforeCell : model.afterCell,cells = before ? model.beforeCells : model.afterCells
            guard cell.isNull || cells.contains(where:{$0["row"].int == coordinate.row && $0["column"].int == coordinate.column}) else { throw BridgeError(code:"WORKBOOK_SMOKE_PANE_SOURCE",message:"셀 원문은 있지만 표시 범위에 해당 원본 관측이 없습니다.") }
            result.append(["pane":name,"highlight":WorkbookGrid.address(coordinate.row,coordinate.column),"row_start":row,"column_start":column,"selected_local_row":table.selectedRow,"visible":true,"cell_border_visible":true,"row_gutter_visible":gutterVisible,"header_geometry":headerGeometry])
        }
        return result
    }
}
