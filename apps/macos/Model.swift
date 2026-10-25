import Foundation
import AppKit
import UniformTypeIdentifiers
import Darwin
import CryptoKit

// The captured request belongs to the model contract; model-only consumers do
// not need to compile the PDFKit sheet or its other view dependencies.
struct SidecarRequest: Identifiable {
    let id = UUID().uuidString.lowercased()
    let owner = BridgeRequestCancellation()
    let project: String
    let report: String
    let occurrence: String
    let page: String
    let label: String
    var scope: [String: Any] {
        ["project_id":project,"report_id":report,"revision_occurrence_id":occurrence,"page_id":page,"session_id":id]
    }
}
struct ReorderConfirmation:Identifiable {
    let id=UUID()
    let project:String
    let draft:Data
    let draftHash:String
    let order:[Int]
    let uiMessage:UIMessage
    @MainActor var message:String {uiMessage.text}
}

// A dialog captures its route when it opens. Bundled source files still form
// one version entry; only a new-comparison route requires a pair of entries.
enum ImportIntent {
    case ordinary, newComparison
    var minimumVersionEntries:Int {self == .newComparison ? 2:1}
    @MainActor func validateVersionEntries(_ count:Int)throws {
        guard count>=minimumVersionEntries else {
            throw BridgeError(code:"IMPORT_VERSION_MINIMUM",message:UIMessage(self == .newComparison ? "git.importComparisonMinimum":"git.importVersionMinimum"))
        }
    }
}

@MainActor final class AppModel: ObservableObject {
    @Published var libraryAvailable = true
    @Published var initializing = true
    @Published var projects: [JSON] = []
    @Published var projectID = "" {
        didSet {if oldValue != projectID {mcp="";mcpFailure="";mcpProjectID="";mcpGeneration += 1}}
    }
    @Published var report = JSON()
    @Published var reports: [JSON] = []
    @Published var changes: [JSON] = []
    @Published var selectedChangeID: String? = nil
    @Published var from = 0
    @Published var to = 1
    @Published var leftPageID = ""
    @Published var rightPageID = ""
    @Published var busy = false
    @Published var sidecarConfigured = false
    @Published var sidecarRequest: SidecarRequest? {
        didSet {
            guard let previous=oldValue,previous.id != sidecarRequest?.id else{return}
            previous.owner.cancel()
            let bridge=bridge,scope=previous.scope
            Task {
                do{_ = try await bridge.call("sidecarClose",scope)}
                catch{sidecarRecoveryWarningMessage = UIMessage("doc.recovery.sidecarFailure", .message(bridgeErrorMessage(error)))}
            }
        }
    }
    @Published var sidecarRecoveryWarningMessage = UIMessage.raw("")
    var sidecarRecoveryWarning:String {get{sidecarRecoveryWarningMessage.text} set{sidecarRecoveryWarningMessage = .raw(newValue)}}
    @Published var documentRecoveryWarningMessage = UIMessage.raw("")
    var documentRecoveryWarning:String {get{documentRecoveryWarningMessage.text} set{documentRecoveryWarningMessage = .raw(newValue)}}
    @Published var workbookRecoveryWarningMessage = UIMessage.raw("")
    var workbookRecoveryWarning:String {get{workbookRecoveryWarningMessage.text} set{workbookRecoveryWarningMessage = .raw(newValue)}}
    var sidecarResult = JSON()
    var sidecarFailureMessage=UIMessage.raw("")
    var sidecarFailure:String {get{sidecarFailureMessage.text} set{sidecarFailureMessage = .raw(newValue)}}
    @Published var loading = false
    @Published var loadingChanges = false
    @Published var changesFailureMessage = UIMessage.raw("") {didSet {storedHistoryRecovery=nil}}
    @Published private var storedHistoryRecovery:(project:String,report:String,from:Int,to:Int)?
    var changesFailure:String {get{changesFailureMessage.text} set{changesFailureMessage = .raw(newValue)}}
    @Published var committing = false
    @Published var statusMessage = UIMessage.raw("")
    var status:String {get{statusMessage.text} set{statusMessage = .raw(newValue)}}
    @Published var evidenceWarningMessage = UIMessage.raw("")
    var evidenceWarning:String {get{evidenceWarningMessage.text} set{evidenceWarningMessage = .raw(newValue)}}
    @Published var errorMessage = UIMessage.raw("")
    var error:String {get{errorMessage.text} set{errorMessage = .raw(newValue)}}
    @Published var progress = JSON()
    @Published var tab = "compare"
    @Published var focus = false
    @Published var inspector = false
    @Published var showChanges = true
    @Published var pageMode = "both"
    @Published var diffMode = "source"
    @Published var lineageSheet = false
    @Published var toolsSheet = false
    @Published var zoom = 0.0
    @Published var search = ""
    @Published var kind = "all"
    @Published var mcp = ""
    @Published var mcpFailureMessage = UIMessage.raw("")
    var mcpFailure:String {get{mcpFailureMessage.text} set{mcpFailureMessage = .raw(newValue)}}
    @Published var reorderConfirmation:ReorderConfirmation?
    @Published var importSheet = false {didSet {if !importSheet {importIntent = .ordinary}}}
    private(set) var importIntent:ImportIntent = .ordinary
    @Published var mappingSheet = false
    @Published var bundleSheet = false
    @Published var bundleOccurrence = ""
    @Published var bundleSourceID = ""
    @Published var bundleProjectID = ""
    @Published var bundleReportID = ""
    let bridge: Bridge
    private var libraryLock: Int32 = -1
    private var cancelRequested = false
    private var analysisToken: UUID?
    private var started = false
    private var rangeGeneration = 0
    private var selectionGeneration = 0
    private var mcpGeneration = 0
    private var mcpProjectID = ""
    private var pendingRange: (key: String, generation: Int, task: Task<[JSON], Error>)?
    private var rejectedEventScope:(project:String,report:String,from:Int,to:Int)?
    private var pageNavigation: (report:String, from:Int, to:Int, left:String, right:String)?
    init() {
        let resources = Bundle.main.resourceURL!
        let base = ProcessInfo.processInfo.environment["DOCVER_TEST_USER_DATA"].map { URL(fileURLWithPath: $0) } ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Docver")
        let library = base.appendingPathComponent("library")
        try? FileManager.default.createDirectory(at: library, withIntermediateDirectories: true)
        bridge = Bridge(resources: resources, library: library)
        libraryLock = Darwin.open(library.appendingPathComponent(".app-lock").path, O_CREAT | O_RDWR | O_CLOEXEC, S_IRUSR | S_IWUSR)
        if libraryLock < 0 || flock(libraryLock, LOCK_EX | LOCK_NB) != 0 { libraryAvailable = false; errorMessage = UIMessage("doc.library.alreadyOpen") }
    }
    var project: JSON { projects.first { $0["project_id"].string == projectID } ?? JSON() }
    var revisions: [JSON] { report["revisions"].array }
    // Query endpoints stay fixed while a history event supplies its own source pair.
    var sourceFrom:Int { sourceIndices.0 }
    var sourceTo:Int { sourceIndices.1 }
    private var sourceIndices:(Int,Int) {
        if tab == "history", !selected.isNull,
           let a=revisions.firstIndex(where:{$0["revision_occurrence_id"].string==selected["from_occurrence"].string}),
           let b=revisions.firstIndex(where:{$0["revision_occurrence_id"].string==selected["to_occurrence"].string}), a<b, a>=from, b<=to {return (a,b)}
        return (from,to)
    }
    var readingSingleVersion:Bool {sourceFrom==sourceTo || revisions.count<2}
    var effectiveDiffMode:String {readingSingleVersion ? "source":diffMode}
    func setDiffMode(_ value:String) {diffMode = readingSingleVersion || value != "text" ? "source":"text"}
    private func enforceSingleSourcePresentation() {if readingSingleVersion {diffMode="source"}}

    var eventInsideQuery:Bool {sourceFrom != from || sourceTo != to}
    var manuallyBrowsing:Bool {guard let n=pageNavigation else{return false};return n.report==report["report_id"].string && n.from==sourceFrom && n.to==sourceTo}
    var selected: JSON { changes.first { $0["change_id"].string == selectedChangeID } ?? JSON() }
    var filteredChanges: [JSON] { changes.filter { (kind == "all" || $0["kind"].string == kind) && (search.isEmpty || ($0["before"].string + " " + $0["after"].string).localizedCaseInsensitiveContains(search)) } }
    var currentMCPConfig:String? {libraryAvailable && !initializing && !loading && mcpProjectID==projectID && !mcp.isEmpty ? mcp:nil}
    var canOpenStoredHistory:Bool {
        guard let recovery=storedHistoryRecovery else{return false}
        return !loading && !loadingChanges && !busy && tab != "history" && recovery.project==projectID && recovery.report==report["report_id"].string && recovery.from==from && recovery.to==to
    }
    func openStoredHistory()async {
        guard canOpenStoredHistory else{return}
        tab="history";try? await updateChanges()
    }
    var emptyChangesMessage:String {
        if busy && changes.isEmpty {return L("doc.changes.analysisPending")}
        if loadingChanges || loading {return L("doc.changes.loadingEllipsis")}
        if !changesFailure.isEmpty {if canOpenStoredHistory {return L("git.archivedDiffUnavailable")};return changesFailureMessage==UIMessage("doc.changes.interrupted") ? changesFailure:L("doc.changes.failed")}
        if revisions.count<2 {return L("doc.changes.needRevisions")}
        if readingSingleVersion {return L("git.singleVersionChanges")}
        if changes.isEmpty {return L("doc.changes.none")}
        return L("doc.changes.filteredNone")
    }
    var unselectedChangeMessage:String {
        if !evidenceWarning.isEmpty {return evidenceWarning}
        if !changes.isEmpty {return L("doc.tail.change.selectPrompt")}
        return emptyChangesMessage
    }
    var changeListProvenance:String {
        if from==to {return L("git.reading")}
        if tab=="history" {return L("git.documentStoredHistory")}
        return to==from+1 ? L("git.documentStoredAdjacent"):L("git.documentComputedNet")
    }
    var canStartNewComparison:Bool {libraryAvailable && !initializing && !busy && !loading}
    func openNewComparisonImport() {guard canStartNewComparison,!importSheet else{return};importIntent = .newComparison;importSheet=true}
    func primaryPages(_ revision: JSON) -> [JSON] {
        let pptx = revision["assets"].array.filter { $0["format"].string == "pptx" }.map { $0["asset_id"].string }
        return revision["pages"].array.filter { pptx.isEmpty || pptx.contains($0["asset_id"].string) }
    }
    func revision(_ index: Int) -> JSON { revisions.indices.contains(index) ? revisions[index] : JSON() }
    var mappingSelection: JSON {
        report["mapping_relations"].array.first { $0["from_occurrence"].string == revision(sourceFrom)["revision_occurrence_id"].string && $0["to_occurrence"].string == revision(sourceTo)["revision_occurrence_id"].string && $0["from_page_ids"].array.map(\.string).contains(leftPageID) && $0["to_page_ids"].array.map(\.string).contains(rightPageID) } ?? JSON(["kind":"continuation","from_page_ids":[leftPageID],"to_page_ids":[rightPageID],"reason":""])
    }
    func fail(_ e: Error) { errorMessage = bridgeErrorMessage(e) }
    func refresh() async throws { projects = try await bridge.call("projects").array }
    func start() async {
        guard error.isEmpty && !started else {if !started{initializing=false};return};started = true;defer{initializing=false}
        do {
            do { _ = try await bridge.call("recover") }
            catch { documentRecoveryWarningMessage = UIMessage("doc.recovery.documentFailure", .message(bridgeErrorMessage(error))) }
            do { _ = try await bridge.call("workbookRecover") }
            catch { workbookRecoveryWarningMessage = UIMessage("doc.recovery.workbookFailure", .message(bridgeErrorMessage(error))) }
            if let recovered=try? await bridge.call("sidecarRecover"),recovered["skipped"].int>0 {sidecarRecoveryWarningMessage=UIMessage.plural("doc.recovery.skippedSidecars",recovered["skipped"].int)}
            if FileManager.default.fileExists(atPath:bridge.resources.appendingPathComponent("onlyoffice-sidecar/provider.json").path) {sidecarConfigured = (try? await bridge.call("sidecarInfo")["configured"].bool) ?? false}
            try await refresh(); if let p = projects.first(where:{!$0["unreadable"].bool}) ?? projects.first { await selectProject(p["project_id"].string) }
        }
        catch { fail(error) }
    }
    func selectProject(_ id: String, snapshot: String? = nil) async {
        guard libraryAvailable && !busy else { return }
        selectionGeneration += 1;rangeGeneration += 1;pendingRange?.task.cancel();pendingRange=nil;loadingChanges=false;let generation=selectionGeneration;pageNavigation=nil
        loading = true; error = ""; evidenceWarning = ""; changesFailure=""; projectID = id; report = JSON(); changes = []; selectedChangeID = nil
        do {
            try await refresh();let loadedReports = try await bridge.call("reports", ["project_id": id]).array
            guard generation==selectionGeneration else{return};reports=loadedReports
            let reportID = snapshot ?? project["last_report_id"].string
            if reportID.isEmpty { report = JSON(); changes = [] }
            else {
                let loadedReport = try await bridge.call("view", ["project_id": id, "report_id": reportID]);guard generation==selectionGeneration else{return};report=loadedReport; from = max(0,revisions.count-2); to = max(0,revisions.count-1)
                leftPageID = primaryPages(revision(from)).first?["page_id"].string ?? ""
                rightPageID = primaryPages(revision(to)).first?["page_id"].string ?? ""
                try await updateChanges()
            }
        } catch {if generation==selectionGeneration{fail(error)}}
        if generation==selectionGeneration{loading = false}
    }
    func updateChanges() async throws {
        guard !report.isNull else { return }
        if revisions.count < 2 || from == to {
            enforceSingleSourcePresentation()
            rangeGeneration += 1;pendingRange?.task.cancel();pendingRange=nil;loadingChanges=false;changesFailure=""
            changes = []; selectedChangeID = "";selectEvidence(); return
        }
        let history = tab == "history", start = from, end = to
        let project=projectID,reportID=report["report_id"].string,before=revision(start)["revision_occurrence_id"].string,after=revision(end)["revision_occurrence_id"].string
        let mode=history ? "history" : end == start+1 ? "adjacent" : "range_net"
        let key=[project,reportID,before,after,mode].joined(separator:"|")
        let preferredChange=selectedChangeID
        let generation:Int,task:Task<[JSON],Error>
        if let pending=pendingRange,pending.key==key {
            generation=pending.generation;task=pending.task
        } else {
            pendingRange?.task.cancel()
            rangeGeneration += 1;generation=rangeGeneration;rejectedEventScope=nil;evidenceWarning="";loadingChanges=true;changesFailure="";changes=[];selectedChangeID=nil
            task=Task { try await self.bridge.call("changes",["project_id":project,"report_id":reportID,"from":before,"to":after,"mode":mode]).array }
            pendingRange=(key,generation,task)
        }
        do {
            let response=try await task.value
            guard generation==rangeGeneration else{return}
            changes=response
            if !changes.contains(where:{$0["change_id"].string==selectedChangeID}) {
                selectedChangeID=changes.first(where:{$0["change_id"].string==preferredChange})?["change_id"].string ?? changes.first(where:{$0["kind"].string=="text_modified"})?["change_id"].string ?? changes.first?["change_id"].string ?? ""
            }
            selectEvidence();loadingChanges=false
            if pendingRange?.generation==generation {pendingRange=nil}
        } catch {
            guard generation==rangeGeneration else{return}
            changes=[];selectedChangeID=nil;loadingChanges=false;changesFailureMessage=bridgeErrorMessage(error)
            if (error as? BridgeError)?.code=="ENGINE_VERSION_UNAVAILABLE",!history {storedHistoryRecovery=(project,reportID,start,end)}
            selectEvidence()
            if pendingRange?.generation==generation {pendingRange=nil}
            throw error
        }
    }

    func selectEvidence() {
        let a=sourceFrom,b=sourceTo
        if let n=pageNavigation,n.report != report["report_id"].string || n.from != a || n.to != b {pageNavigation=nil}
        if let n=pageNavigation,n.report==report["report_id"].string,n.from==a,n.to==b {
            leftPageID=normalizedPage(n.left,in:revision(a),preserveAbsent:true)
            rightPageID=normalizedPage(n.right,in:revision(b),preserveAbsent:true)
            return
        }
        guard !selected.isNull else {
            if let rejected=rejectedEventScope,selectedChangeID==nil,rejected.project==projectID,rejected.report==report["report_id"].string,rejected.from==from,rejected.to==to {return}
            rejectedEventScope=nil
            evidenceWarning=""
            leftPageID=normalizedPage(leftPageID,in:revision(a))
            rightPageID=normalizedPage(rightPageID,in:revision(b))
            return
        }
        evidenceWarning=""
        let evidence = selected["evidence"].array
        leftPageID = evidenceSelection(evidence, in:revision(a), current:leftPageID)
        rightPageID = evidenceSelection(evidence, in:revision(b), current:rightPageID)
    }
    private func normalizedPage(_ id:String,in revision:JSON,preserveAbsent:Bool = false)->String {
        let pages=primaryPages(revision)
        if (preserveAbsent && id.isEmpty) || pages.contains(where:{$0["page_id"].string==id}) { return id }
        return pages.first?["page_id"].string ?? ""
    }
    func evidenceSelection(_ evidence:[JSON],in revision:JSON,current:String)->String {
        let relevant=evidence.filter { $0["revision_occurrence_id"].string == revision["revision_occurrence_id"].string }
        let primary=Set(primaryPages(revision).map { $0["page_id"].string })
        let resolved=relevant.map { displayPageID($0["page_id"].string,in:revision) }.filter { primary.contains($0) }
        if !relevant.isEmpty && resolved.isEmpty {
            evidenceWarningMessage = UIMessage("doc.evidence.pageUnavailable")
            return primary.contains(current) ? current : ""
        }
        return resolved.contains(current) ? current : resolved.first ?? ""
    }
    func displayPageID(_ sourcePageID:String,in revision:JSON)->String {
        primaryPages(revision).first { $0["appearance"]["source_page_id"].string == sourcePageID }?["page_id"].string ?? sourcePageID
    }
    func navigatePage(_ id:String,in occurrence:String) {
        let before=revision(sourceFrom),after=revision(sourceTo)
        guard occurrence==before["revision_occurrence_id"].string || occurrence==after["revision_occurrence_id"].string else{return}
        let target=occurrence==before["revision_occurrence_id"].string ? before:after
        guard id.isEmpty || primaryPages(target).contains(where:{$0["page_id"].string==id}) else{evidenceWarningMessage = UIMessage("doc.evidence.selectionUnavailable");return}
        if occurrence==before["revision_occurrence_id"].string{leftPageID=id}
        if occurrence==after["revision_occurrence_id"].string{rightPageID=id}
        evidenceWarning="";pageNavigation=(report["report_id"].string,sourceFrom,sourceTo,leftPageID,rightPageID)
    }
    func chooseChange(_ id:String){
        guard !loadingChanges, changes.contains(where:{$0["change_id"].string==id}) else{return}
        if tab=="history",let change=changes.first(where:{$0["change_id"].string==id}) {
            guard let a=revisions.firstIndex(where:{$0["revision_occurrence_id"].string==change["from_occurrence"].string}),let b=revisions.firstIndex(where:{$0["revision_occurrence_id"].string==change["to_occurrence"].string}),a<b,a>=from,b<=to else {
                selectedChangeID=nil;pageNavigation=nil;leftPageID="";rightPageID="";rejectedEventScope=(projectID,report["report_id"].string,from,to);evidenceWarningMessage=UIMessage("doc.evidence.selectionUnavailable");return
            }
        }
        rejectedEventScope=nil;evidenceWarning="";pageNavigation=nil;selectedChangeID=id;selectEvidence()
    }
    func stepChange(_ offset:Int) {
        let rows=filteredChanges
        guard !loadingChanges,!rows.isEmpty else{return}
        let index=rows.firstIndex(where:{$0["change_id"].string==selectedChangeID}) ?? (offset>0 ? -1:rows.count)
        let next=index+offset
        guard rows.indices.contains(next) else{return}
        chooseChange(rows[next]["change_id"].string)
    }
    func returnToChange() {pageNavigation=nil;selectEvidence()}
    func selectVersion(_ index:Int) {
        guard revisions.indices.contains(index),!busy,!loading else{return}
        from=max(0,index-1);to=index;selectedChangeID=nil;pageNavigation=nil;evidenceWarning="";enforceSingleSourcePresentation();changeRange()
    }
    func openHistoryPage(_ index:Int,_ pageID:String){
        guard revisions.indices.contains(index),primaryPages(revision(index)).contains(where:{$0["page_id"].string==pageID}) else{return}
        evidenceWarning="";selectedChangeID=nil
        from=max(0,index-1);to=min(revisions.count-1,index)
        let edges=report["matches"].array
        let parents=edges.filter { $0["to_page_id"].string == pageID }.map { $0["from_page_id"].string }
        let children=edges.filter { $0["from_page_id"].string == pageID }.map { $0["to_page_id"].string }
        let left=primaryPages(revision(from)).first { parents.contains($0["page_id"].string) }?["page_id"].string ?? ""
        let right=primaryPages(revision(to)).first { children.contains($0["page_id"].string) }?["page_id"].string ?? ""
        pageNavigation=(report["report_id"].string,from,to,index==0 ? pageID:left,index==0 ? right:pageID)
        tab="compare";selectEvidence();changeRange()
    }
    func changeRange() { Task { do { try await updateChanges() } catch { fail(error) } } }
    func run(_ id: String) async {
        guard libraryAvailable && !initializing && !busy && !projects.contains(where:{$0["project_id"].string==id && $0["unreadable"].bool}) else { return };selectionGeneration += 1;rangeGeneration += 1;pendingRange?.task.cancel();pendingRange=nil;loading=false;loadingChanges=false;changesFailure="";evidenceWarning="";let token=UUID();analysisToken=token; busy = true; committing = false; cancelRequested = false; error = ""; progress = JSON(); statusMessage = UIMessage("doc.analysis.preparing")
        let generation=selectionGeneration,retainedProject=projectID,retainedReport=report["report_id"].string
        var runID="",commitAttempted=false
        defer{bridge.releaseAnalysis(owner:token)}
        do {
            let result = try await bridge.call("analyze", ["project_id": id], analysis: true,progress:{ [weak self] p in
                Task { @MainActor in guard let self,self.busy,!self.committing,self.analysisToken==token else{return}; self.progress = p; self.statusMessage = p["phase"].string == "match" ? UIMessage("doc.analysis.matching") : p["phase"].string == "render" ? UIMessage("doc.analysis.rendering", .verbatim(p["label"].string)) : p["label"].string.isEmpty ? UIMessage("doc.analysis.extracting") : UIMessage("doc.analysis.extractingLabel", .verbatim(p["label"].string)) }
            },analysisOwner:token,holdAnalysis:true)
            runID=result["analysis_run_id"].string
            if cancelRequested { throw BridgeError(code: "CANCELLED", message: UIMessage("doc.analysis.cancelled")) }
            committing = true; commitAttempted=true; statusMessage = UIMessage("doc.analysis.committing")
            let committed = try await bridge.call("commit", ["project_id": id, "result": result.raw])
            guard committed["status"].string=="complete",!committed["report_id"].string.isEmpty else { throw BridgeError(code:"COMMIT_REPLY",message:UIMessage("doc.error.commitReply")) }
            bridge.releaseAnalysis(owner:token)
            analysisToken=nil;busy = false; committing = false
            if committed["cleanup_pending"].bool { documentRecoveryWarningMessage = UIMessage("doc.recovery.cleanupPending") }
            guard generation==selectionGeneration else { return }
            await openCompletedReport(id,snapshot:committed["report_id"].string,recovered:false)
        } catch {
            let runError=error
            if runID.isEmpty { runID=progress["analysis_run_id"].string }
            var recoveredReport="",cleanupPending=false,uncertain=commitAttempted,recoveryWarning=UIMessage.raw("")
            var mayRecover = !commitAttempted
            if commitAttempted, !runID.isEmpty {
                committing=true;statusMessage = UIMessage("doc.analysis.checkingSave")
                do {
                    let run=try await bridge.call("runStatus",["project_id":id,"analysis_run_id":runID])
                    guard run["project_id"].string==id,run["analysis_run_id"].string==runID else { throw BridgeError(code:"RUN_SCOPE",message:UIMessage("doc.error.runScope")) }
                    if ["success","partial"].contains(run["status"].string),!run["report_id"].string.isEmpty {
                        recoveredReport=run["report_id"].string;cleanupPending=run["cleanup_pending"].bool;uncertain=false
                    } else if ["running","failed","interrupted"].contains(run["status"].string),run["report_id"].isNull {
                        uncertain=false;mayRecover=true
                    } else { recoveryWarning=UIMessage("doc.recovery.saveUnknown") }
                } catch { recoveryWarning=UIMessage("doc.recovery.saveFailure", .message(bridgeErrorMessage(error))) }
            }
            if mayRecover,!runID.isEmpty {
                do { _ = try await bridge.call("recover",["run_id":runID]) }
                catch { recoveryWarning=UIMessage("doc.recovery.runCleanupFailure", .message(bridgeErrorMessage(error))) }
            }
            // Release the writer only after the exact owned run is reconciled;
            // report reads must not hold another window's analysis reservation.
            bridge.releaseAnalysis(owner:token)
            analysisToken=nil;committing=false;busy=false
            if cleanupPending { recoveryWarning=UIMessage("doc.recovery.cleanupPending") }
            if uncertain && recoveryWarning.isEmpty { recoveryWarning=UIMessage("doc.recovery.recheckSave") }
            if !recoveryWarning.isEmpty { documentRecoveryWarningMessage=recoveryWarning }
            guard generation==selectionGeneration else { return }
            if !recoveredReport.isEmpty {
                await openCompletedReport(id,snapshot:recoveredReport,recovered:true)
                return
            }
            let cancelled=cancelRequested || runError is CancellationError || (runError as? BridgeError)?.code=="CANCELLED"
            let outcome=uncertain ? UIMessage("doc.analysis.saveUncertain") : cancelled ? UIMessage("doc.analysis.cancelledRetained") : UIMessage("doc.analysis.failedRetained")
            try? await refresh()
            guard generation==selectionGeneration,projectID==retainedProject else { return }
            var completionGeneration=generation
            if !retainedProject.isEmpty {
                if let loaded=try? await bridge.call("reports",["project_id":retainedProject]).array {
                    guard generation==selectionGeneration,projectID==retainedProject else { return };reports=loaded
                }
                if report.isNull,!retainedReport.isEmpty { completionGeneration += 1;await selectProject(retainedProject,snapshot:retainedReport) }
                else if !report.isNull { try? await updateChanges() }
            }
            guard selectionGeneration==completionGeneration,projectID==retainedProject else { return }
            if !cancelled && !uncertain { fail(runError) }
            statusMessage=outcome
        }
    }
    private func openCompletedReport(_ project:String,snapshot:String,recovered:Bool) async {
        let generation=selectionGeneration+1
        await selectProject(project,snapshot:snapshot)
        guard generation==selectionGeneration,projectID==project else { return }
        guard report["report_id"].string==snapshot else { statusMessage = UIMessage("doc.analysis.savedReload");return }
        var summary=[recovered ? UIMessage("doc.analysis.recovered") : UIMessage("doc.analysis.saved")]
        let quality=report["quality_counts"]
        if quality["ocr_inferred_pages"].int>0{summary.append(UIMessage.plural("doc.analysis.ocrInferredPages",quality["ocr_inferred_pages"].int))}
        if quality["ocr_failed_pages"].int>0{summary.append(UIMessage.plural("doc.analysis.ocrFailedPages",quality["ocr_failed_pages"].int))}
        if quality["unresolved_comparison_pages"].int>0{summary.append(UIMessage.plural("doc.analysis.unresolvedPages",quality["unresolved_comparison_pages"].int))}
        if quality["pptx_without_render"].int>0{summary.append(UIMessage.plural("doc.analysis.noRenderPages",quality["pptx_without_render"].int))}
        if quality["reference_pdf_pages"].int>0{summary.append(UIMessage("doc.analysis.referenceSummary", .message(UIMessage.plural("doc.analysis.referenceTotal",quality["reference_pdf_pages"].int)), .message(UIMessage.plural("doc.analysis.referenceHuman",quality["human_reference_pdf_pages"].int)), .message(UIMessage.plural("doc.analysis.referenceInferred",quality["inferred_reference_pdf_pages"].int))))}
        statusMessage = .joined(summary, separator:" · ")
    }
    func cancel() { guard busy && !committing,let token=analysisToken else { return }; cancelRequested = true; bridge.cancel(owner:token); statusMessage = UIMessage("doc.analysis.cancelling") }
    func create(title: String, rows: [ImportRow], intent:ImportIntent = .ordinary) async throws -> JSON {
        try intent.validateVersionEntries(rows.count)
        let interrupted=pendingRange != nil || loadingChanges
        selectionGeneration += 1;rangeGeneration += 1;pendingRange?.task.cancel();pendingRange=nil;loading=false;loadingChanges=false;changesFailureMessage=(!report.isNull && interrupted) ? UIMessage("doc.changes.interrupted"):.raw("")
        do{return try await bridge.call("create", ["title": title, "revisions": rows.map(\.createPayload)])}
        catch{if !report.isNull {try? await updateChanges()};throw error}
    }
    func demo() async {
        guard !busy && !loading && !initializing else{return}
        do {
            let folder = bridge.resources.appendingPathComponent("demo/lifecycle-five")
            let manifest = JSON(try JSONSerialization.jsonObject(with: Data(contentsOf: folder.appendingPathComponent("manifest.json"))))
            let rows = manifest["revisions"].array.map { ImportRow(label: $0["label"].string, urls: $0["files"].array.map { folder.appendingPathComponent($0.string) }) }
            let p = try await create(title: "사업계획 · 합성 데모", rows: rows); report = JSON(); try await refresh(); projectID = p["project_id"].string
            await run(projectID)
        } catch { fail(error) }
    }
    func reorder(_ index: Int, delta: Int) async {
        guard !busy && !loading && !initializing && reorderConfirmation == nil else{return}
        var order = Array(project["revisions"].array.indices); guard order.indices.contains(index + delta) else { return }; order.swapAt(index, index + delta)
        do {
            let relations=project["mapping_relations"].array.count,pairs=project["mapping_decisions"].array.count,bundles=project["bundle_decision_count"].int
            if project["dirty"].bool && relations+pairs+bundles>0 {errorMessage = UIMessage("doc.reorder.analyzePending");return}
            let request=ReorderConfirmation(project:projectID,draft:try project.data(),draftHash:project["draft_hash"].string,order:order,uiMessage:UIMessage("doc.reorder.warning", .count(relations), .count(pairs), .count(bundles)))
            if relations+pairs+bundles>0 {reorderConfirmation=request}else{await confirmReorder(request)}
        }catch{fail(error)}
    }
    func confirmReorder(_ request:ReorderConfirmation) async {
        reorderConfirmation=nil
        guard !busy && !loading,request.project==projectID,(try? project.data())==request.draft else{errorMessage = UIMessage("doc.reorder.inputChanged");return}
        loading=true;defer{loading=false}
        do {
            _ = try await bridge.call("reorder",["project_id":request.project,"order":request.order,"discard_human_decisions":true,"draft_hash":request.draftHash])
            try await refresh();statusMessage = UIMessage("doc.reorder.pending")
        }catch{fail(error)}
    }
    func navigateEvidence(_ evidence: JSON) {
        guard !loadingChanges else{return}
        let occurrence=evidence["revision_occurrence_id"].string
        if occurrence == revision(sourceFrom)["revision_occurrence_id"].string {
            let id=displayPageID(evidence["page_id"].string,in:revision(sourceFrom))
            guard primaryPages(revision(sourceFrom)).contains(where:{$0["page_id"].string==id}) else{evidenceWarningMessage = UIMessage("doc.evidence.pageUnavailable");return}
            leftPageID=id
        }
        if occurrence == revision(sourceTo)["revision_occurrence_id"].string {
            let id=displayPageID(evidence["page_id"].string,in:revision(sourceTo))
            guard primaryPages(revision(sourceTo)).contains(where:{$0["page_id"].string==id}) else{evidenceWarningMessage = UIMessage("doc.evidence.pageUnavailable");return}
            rightPageID=id
        }
        evidenceWarning="";pageNavigation=(report["report_id"].string,sourceFrom,sourceTo,leftPageID,rightPageID)
    }
    func applyRelation(project: String, report: String, draftHash: String, before: String, after: String, left: [String], right: [String], kind: String, reason: String) async throws {
        guard !busy && project == projectID && report == self.report["report_id"].string else { throw BridgeError(code: "STALE_REPORT", message: UIMessage("doc.error.staleMapping")) }
        _ = try await bridge.call("mappingRelation", ["project_id": project, "report_id": report, "draft_hash": draftHash, "unlink": kind == "unlink", "selection": ["kind": kind == "unlink" ? "continuation" : kind, "from_occurrence": before, "to_occurrence": after, "from_page_ids": left, "to_page_ids": right, "reason": reason]])
        try await refresh()
    }
    func isBundle(_ revision:JSON)->Bool {
        revision["assets"].array.count == 2 && Set(revision["assets"].array.map{$0["format"].string}) == Set(["pptx","pdf"])
    }
    var bundleEditingUnavailable: String? {
        if project["unreadable"].bool{return L("doc.project.readOnlyReason")}
        if busy || loading || initializing {return L("doc.bundle.waitLoading")}
        if project["dirty"].bool {return L("doc.bundle.analyzePending")}
        if report["report_id"].string.isEmpty || project["last_report_id"].string != report["report_id"].string {return L("doc.bundle.chooseLatest")}
        return nil
    }
    func openBundle(_ revision:JSON,source:String="") {
        guard !busy && !loading && !initializing,isBundle(revision),revisions.contains(where:{$0["revision_occurrence_id"].string==revision["revision_occurrence_id"].string}) else{return}
        bundleProjectID=projectID;bundleReportID=report["report_id"].string;bundleOccurrence=revision["revision_occurrence_id"].string;bundleSourceID=source;bundleSheet=true
    }
    func bundleContext(project:String,report:String,occurrence:String) async throws -> JSON {
        try await bridge.call("bundle",["project_id":project,"report_id":report,"revision_occurrence_id":occurrence])
    }
    func applyBundle(project:String,report:String,draftHash:String,occurrence:String,sourceAsset:String,pdfAsset:String,source:String,pdf:String?,action:String,reason:String) async throws {
        guard project == projectID,report == self.report["report_id"].string,bundleEditingUnavailable == nil else{throw BridgeError(code:"STALE_REPORT",message:UIMessage("doc.error.staleBundle"))}
        let target:Any=pdf.map{$0 as Any} ?? NSNull()
        _ = try await bridge.call("bundleMapping",["project_id":project,"report_id":report,"draft_hash":draftHash,"selection":["revision_occurrence_id":occurrence,"source_asset_id":sourceAsset,"rendered_asset_id":pdfAsset,"source_page_id":source,"rendered_page_id":target,"action":action,"reason":reason]])
        try await refresh()
    }
    func exportReport() async {
        let exportLanguage=LanguagePreferences.shared.effectiveLanguage
        let panel = NSOpenPanel(); panel.title = L("doc.tail.report.saveFolderPrompt"); panel.canChooseFiles = false; panel.canChooseDirectories = true; panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let target = url.appendingPathComponent("Reviset-" + report["report_id"].string.dropFirst(4).prefix(12) + "." + exportLanguage)
        do { _ = try await bridge.call("export", ["project_id": projectID, "report_id": report["report_id"].string, "folder": target.path, "language":exportLanguage]); NSWorkspace.shared.open(target); statusMessage = UIMessage("doc.tail.report.savedJsonJsonlMarkdown") } catch { fail(error) }
    }
    func loadMCP() async {
        let project=projectID;mcpGeneration += 1;let generation=mcpGeneration
        guard !project.isEmpty,libraryAvailable else{return}
        mcp="";mcpProjectID="";mcpFailure=""
        do {
            let config=try await bridge.call("mcpConfig",["project_id":project]).string
            guard !Task.isCancelled,project==projectID,generation==mcpGeneration else{return}
            mcpProjectID=project;mcp=config
        } catch {if !Task.isCancelled,project==projectID,generation==mcpGeneration {mcpFailureMessage=bridgeErrorMessage(error)}}
    }
    func openSidecar(_ revision:JSON,page:String) {
        guard libraryAvailable && !busy && !loading && sidecarConfigured && !page.isEmpty else{return}
        sidecarResult=JSON();sidecarFailure=""
        let index=revisions.firstIndex{$0["revision_occurrence_id"].string==revision["revision_occurrence_id"].string}
        let label=index.map{versionDisplayName($0,revision)} ?? revision["label"].string
        sidecarRequest=SidecarRequest(project:projectID,report:report["report_id"].string,occurrence:revision["revision_occurrence_id"].string,page:page,label:label)
    }
    func page(_ id: String) async throws -> JSON { try await bridge.call("page", ["project_id": projectID, "report_id": report["report_id"].string, "page_id": id]) }
}
struct ImportFileIdentity: Equatable {
    let sha256:String
    let bytes:Int
    static func capture(_ url:URL)throws->ImportFileIdentity {
        // Reject special files atomically; opening a FIFO for reading otherwise
        // waits for a writer before the import sheet can report any error.
        let descriptor=Darwin.open(url.path,O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        guard descriptor>=0 else{throw BridgeError(code:"FILE_INPUT",message:UIMessage("doc.tail.import.regularSourceOpenFailed"))}
        let handle=FileHandle(fileDescriptor:descriptor,closeOnDealloc:true);defer{try? handle.close()}
        var metadata=stat()
        guard Darwin.fstat(descriptor,&metadata)==0,metadata.st_mode & S_IFMT == S_IFREG else{throw BridgeError(code:"FILE_INPUT",message:UIMessage("doc.tail.import.regularSourceOnly"))}
        guard metadata.st_size<=512*1024*1024 else{throw BridgeError(code:"FILE_LIMIT",message:UIMessage("doc.tail.import.maxFileSize512MiB"))}
        var digest=SHA256(),count=0
        while let data=try handle.read(upToCount:1024*1024),!data.isEmpty {
            count += data.count
            guard count<=512*1024*1024 else{throw BridgeError(code:"FILE_LIMIT",message:UIMessage("doc.tail.import.maxFileSize512MiB"))}
            digest.update(data:data)
        }
        return ImportFileIdentity(sha256:digest.finalize().map{String(format:"%02x",$0)}.joined(),bytes:count)
    }
}
struct ImportMember: Identifiable,Equatable {
    let id:UUID
    var label:String
    let url:URL
    let identity:ImportFileIdentity?
}
struct ImportRow: Identifiable,Equatable {
    let id:UUID
    var label:String {didSet{if members.count==1{members[0].label=label}}}
    private(set) var members:[ImportMember]
    var urls:[URL]{members.map(\.url)}
    init(label:String,urls:[URL]) {
        let files=urls.enumerated().map{index,url in ImportMember(id:UUID(),label:index==0 ? label:url.deletingPathExtension().lastPathComponent,url:url,identity:nil)}
        self.init(id:files.count==1 ? files[0].id:UUID(),label:label,members:files)
    }
    init(id:UUID,label:String,members:[ImportMember]){self.id=id;self.label=label;self.members=members;if self.members.count==1{self.members[0].label=label}}
    static func selected(_ url:URL)throws->ImportRow {
        let member=ImportMember(id:UUID(),label:url.deletingPathExtension().lastPathComponent,url:url,identity:try ImportFileIdentity.capture(url))
        return ImportRow(id:member.id,label:member.label,members:[member])
    }
    var createPayload:[String:Any] {
        var payload:[String:Any]=["label":label,"files":urls.map(\.path)]
        if members.contains(where:{$0.identity != nil}) {payload["expected_sha256"]=members.map{member -> Any in if let identity=member.identity{return identity.sha256};return NSNull()}}
        return payload
    }
    @MainActor static func groupingUnavailable(_ rows:[ImportRow],at index:Int)->String? {
        guard rows.indices.contains(index),index>0 else{return L("doc.tail.bundle.groupWithAboveNeedsPreviousVersion")}
        let a=rows[index-1],b=rows[index]
        guard a.members.count==1,b.members.count==1 else{return L("doc.tail.bundle.onlyOnePptxOnePdf")}
        guard Set((a.urls+b.urls).map{$0.pathExtension.lowercased()})==Set(["pptx","pdf"]) else{return L("doc.tail.bundle.selectPptxAndPdfDifferentFormats")}
        return nil
    }
    @discardableResult static func group(_ rows:inout [ImportRow],at index:Int)->Bool {
        guard rows.indices.contains(index),index>0,rows[index-1].members.count==1,rows[index].members.count==1,Set((rows[index-1].urls+rows[index].urls).map{$0.pathExtension.lowercased()})==Set(["pptx","pdf"]) else{return false}
        let a=rows[index-1],b=rows[index]
        var first=a.members[0],second=b.members[0];first.label=a.label;second.label=b.label
        rows.replaceSubrange((index-1)...index,with:[ImportRow(id:UUID(),label:a.label,members:[first,second])]);return true
    }
    @discardableResult static func ungroup(_ rows:inout [ImportRow],at index:Int)->Bool {
        guard rows.indices.contains(index),rows[index].members.count==2 else{return false}
        let group=rows[index]
        let restored=group.members.enumerated().map{offset,member in ImportRow(id:member.id,label:offset==0 ? group.label:member.label,members:[member])}
        rows.replaceSubrange(index...index,with:restored);return true
    }
    @discardableResult static func move(_ rows:inout [ImportRow],at index:Int,by delta:Int)->Bool {
        guard (delta == -1 || delta == 1),rows.indices.contains(index),rows.indices.contains(index+delta) else{return false}
        rows.swapAt(index,index+delta);return true
    }
}
func fittedPageSize(width:Double,height:Double,available:CGSize,inset:CGFloat=0)->CGSize? {
    guard inset.isFinite,inset>=0 else{return nil}
    let boundsWidth=Double(available.width-2*inset),boundsHeight=Double(available.height-2*inset)
    guard [width,height,boundsWidth,boundsHeight].allSatisfy({$0.isFinite && $0>0}) else{return nil}
    let scale=min(boundsWidth/width,boundsHeight/height),w=width*scale,h=height*scale
    guard scale.isFinite,scale>0,w.isFinite,h.isFinite,w>0,h>0 else{return nil}
    return CGSize(width:w,height:h)
}
@MainActor func appearanceStateName(_ value:String)->String {
    let names=["visible":L("doc.appearance.visible"),"occluded":L("doc.appearance.occluded"),"partially_occluded":L("doc.appearance.partiallyOccluded"),"struck_through":L("doc.appearance.struck"),"struck_inferred":L("doc.appearance.struckInferred"),"partially_struck_through":L("doc.appearance.partiallyStruck"),"hidden_render_mode":L("doc.appearance.hiddenMode"),"uncertain":L("doc.appearance.uncertain"),"unverified":L("doc.appearance.unverified")]
    return names[value] ?? L("doc.appearance.unknownCode", .verbatim(value))
}
let changeKinds = ["coverage_gap", "page_added", "page_deleted", "page_lineage_changed", "page_merged", "page_moved", "page_split", "text_modified", "text_occluded", "text_revealed", "text_struck_through", "visual_region_changed"]
@MainActor func changeKindName(_ kind:String)->String {
    switch kind {
    case "text_modified": return L("doc.tail.changeKind.textEdit")
    case "page_moved": return L("doc.tail.changeKind.pageMove")
    case "page_added": return L("doc.tail.changeKind.pageAddition")
    case "page_deleted": return L("doc.tail.changeKind.pageDeletion")
    case "text_struck_through": return L("doc.tail.changeKind.strikethroughMarked")
    case "text_occluded": return L("doc.tail.changeKind.textObscured")
    case "text_revealed": return L("doc.tail.changeKind.textRevealedAgain")
    case "visual_region_changed": return L("doc.tail.changeKind.visualChange")
    case "coverage_gap": return L("doc.tail.changeKind.observationGap")
    case "page_split": return L("doc.tail.changeKind.pageSplit")
    case "page_merged": return L("doc.tail.changeKind.pageMerge")
    case "page_lineage_changed": return L("doc.tail.changeKind.pageLineageChange")
    default: return kind.isEmpty ? L("doc.tail.change.selectPrompt") : kind
    }
}
func isReferenceAppearanceChange(_ change:JSON)->Bool {
    change["kind"].string == "visual_region_changed" && change["evidence"].array.contains { $0["method"].string == "provided_pdf_native_raster" }
}
@MainActor func changeDisplayName(_ change:JSON)->String {
    if isReferenceAppearanceChange(change) { return L("doc.tail.changeKind.suppliedPdfVisualDifference") }
    return changeKindName(change["kind"].string)
}
func versionDisplayName(_ index:Int,_ revision:JSON)->String {
    let prefix="v\(index+1)",label=revision["label"].string
    return label.trimmingCharacters(in:.whitespacesAndNewlines).caseInsensitiveCompare(prefix) == .orderedSame ? prefix:prefix+" · "+label
}
@MainActor func changeVersionSummary(_ change:JSON,revisions:[JSON])->String {
    func name(_ key:String)->String {revisions.firstIndex{$0["revision_occurrence_id"].string==key}.map{versionDisplayName($0,revisions[$0])} ?? L("doc.tail.version.unconfirmed")}
    return name(change["from_occurrence"].string)+" → "+name(change["to_occurrence"].string)
}
@MainActor func notesDisplayText(_ page:JSON)->String {
    switch page["capabilities"]["notes"].string {
    case "extraction_failed":return L("doc.tail.notes.extractionFailedCheckSource")
    case "unsupported":return L("doc.tail.notes.extractionUnsupportedCheckSource")
    case "unavailable":return L("doc.tail.notes.unobservableFormatHasNoSpeakerNotes")
    case "available":return page["notes"].isNull ? L("doc.tail.notes.observedValueUnavailable"):page["notes"].string.isEmpty ? L("doc.tail.notes.noneObservedFromSourceStructure"):page["notes"].string
    default:return L("doc.tail.notes.observationStatusUnconfirmedCheckSource")
    }
}
func evidencePageSummary(_ change:JSON)->String {
    func pages(_ occurrence:String)->String {
        let numbers=Set(change["evidence"].array.filter{$0["revision_occurrence_id"].string==occurrence}.map{$0["page"].int}.filter{$0>0}).sorted()
        return numbers.isEmpty ? "—":numbers.map{"p.\($0)"}.joined(separator:", ")
    }
    return pages(change["from_occurrence"].string)+" → "+pages(change["to_occurrence"].string)
}

struct ChangeTextRun {let text:String;let changed:Bool}
// Presentation only: preserve exact characters; bound the token diff so a long
// source cannot turn an inspector redraw into unbounded CPU work.
func changeTextRuns(_ text:String,comparedWith other:String)->[ChangeTextRun] {
    guard text.utf16.count<=4096,other.utf16.count<=4096 else{return [ChangeTextRun(text:text,changed:false)]}
    func tokens(_ value:String)->[String] {
        var result:[String]=[],current="",previous = -1
        for c in value {let kind=c.isWhitespace ? 0:c.isNumber ? 1:c.isLetter ? 2:3
            if kind != previous || kind==3 {if !current.isEmpty{result.append(current)};current=""}
            current.append(c);previous=kind
        };if !current.isEmpty{result.append(current)};return result
    }
    let target=tokens(text),reference=tokens(other)
    guard target.count<=512,reference.count<=512 else{return [ChangeTextRun(text:text,changed:false)]}
    let changed=Set(target.difference(from:reference,by:{$0.utf16.elementsEqual($1.utf16)}).compactMap{change->Int? in if case let .insert(offset,_,_)=change{return offset};return nil})
    return target.enumerated().map{ChangeTextRun(text:$0.element,changed:changed.contains($0.offset))}
}
@MainActor func evidenceVersionLabel(_ evidence:JSON,change:JSON,revisions:[JSON])->String {
    let occurrence=evidence["revision_occurrence_id"].string
    var indices=revisions.indices.filter{!occurrence.isEmpty && revisions[$0]["revision_occurrence_id"].string==occurrence}
    if indices.isEmpty && occurrence.isEmpty {let revision=evidence["revision_id"].string;indices=revisions.indices.filter{!revision.isEmpty && revisions[$0]["revision_id"].string==revision}}
    guard indices.count==1,let index=indices.first else{return L("doc.tail.version.checkNeededOnPage", .integer(evidence["page"].int))}
    let id=revisions[index]["revision_occurrence_id"].string
    let side=id==change["from_occurrence"].string ? L("doc.common.before"):id==change["to_occurrence"].string ? L("doc.common.after"):L("doc.tail.version.differentVersion")
    return "\(side) · v\(index+1) · p.\(evidence["page"].int)"
}

struct UnifiedTextDiffLine:Equatable {
    let prefix:String
    let text:String
    var terminator:String=""
    var rawText:String {text+terminator}
}
struct UnifiedTextDiff {
    let lines:[UnifiedTextDiffLine]
    let bounded:Bool
    let semantic:Bool
    var terminatorsDiffer=false
}
private struct StoredDiffLine {let text:String;let terminator:String;var rawText:String{text+terminator}}
private func storedDiffLines(_ text:String)->[StoredDiffLine] {
    let units=Array(text.utf16);var result:[StoredDiffLine]=[],start=0,index=0
    while index<units.count {
        if units[index]==13 || units[index]==10 {
            let end=index;index += units[index]==13 && index+1<units.count && units[index+1]==10 ? 2:1
            result.append(StoredDiffLine(text:String(decoding:units[start..<end],as:UTF16.self),terminator:String(decoding:units[end..<index],as:UTF16.self)));start=index
        } else {index+=1}
    }
    if start<units.count || result.isEmpty {result.append(StoredDiffLine(text:String(decoding:units[start..<units.count],as:UTF16.self),terminator:""))};return result
}
// Annotation is a projection of a complete observed string, never of an unread
// continuation. Keep its display work inside the same source/line budget as diff.
func neutralSourceLines(_ text:String,complete:Bool)->[UnifiedTextDiffLine]? {
    guard complete,text.utf16.count<=4096 else{return nil}
    let lines=storedDiffLines(text)
    guard lines.count<=128 else{return nil}
    return lines.map{UnifiedTextDiffLine(prefix:"",text:$0.text,terminator:$0.terminator)}
}
func unifiedTextDiff(before:String,after:String,semantic:Bool)->UnifiedTextDiff {
    // Never truncate a source and then present that fragment as a complete diff.
    guard before.utf16.count<=4096,after.utf16.count<=4096 else{return UnifiedTextDiff(lines:[],bounded:false,semantic:false)}
    let old=storedDiffLines(before),new=storedDiffLines(after)
    guard old.count<=128,new.count<=128 else{return UnifiedTextDiff(lines:[],bounded:false,semantic:false)}
    let endingChange=old.map(\.terminator) != new.map(\.terminator)
    guard semantic else{return UnifiedTextDiff(lines:old.map{UnifiedTextDiffLine(prefix:"",text:$0.text,terminator:$0.terminator)}+new.map{UnifiedTextDiffLine(prefix:"",text:$0.text,terminator:$0.terminator)},bounded:true,semantic:false,terminatorsDiffer:endingChange)}
    let difference=new.difference(from:old,by:{$0.rawText.utf16.elementsEqual($1.rawText.utf16)})
    let removed=Set(difference.compactMap{entry->Int? in if case let .remove(offset,_,_)=entry{return offset};return nil})
    let added=Set(difference.compactMap{entry->Int? in if case let .insert(offset,_,_)=entry{return offset};return nil})
    var result:[UnifiedTextDiffLine]=[],a=0,b=0
    while a<old.count || b<new.count {
        if a<old.count,removed.contains(a) {result.append(UnifiedTextDiffLine(prefix:"−",text:old[a].text,terminator:old[a].terminator));a+=1}
        else if b<new.count,added.contains(b) {result.append(UnifiedTextDiffLine(prefix:"+",text:new[b].text,terminator:new[b].terminator));b+=1}
        else if a<old.count,b<new.count {result.append(UnifiedTextDiffLine(prefix:" ",text:old[a].text,terminator:old[a].terminator));a+=1;b+=1}
        else if a<old.count {result.append(UnifiedTextDiffLine(prefix:"−",text:old[a].text,terminator:old[a].terminator));a+=1}
        else {result.append(UnifiedTextDiffLine(prefix:"+",text:new[b].text,terminator:new[b].terminator));b+=1}
    }
    return UnifiedTextDiff(lines:result,bounded:true,semantic:true,terminatorsDiffer:endingChange)
}
func documentTextDiff(_ change:JSON)->UnifiedTextDiff {
    let semantic=change["kind"].string=="text_modified" && change["topology"].isNull && !change["before"].isNull && !change["after"].isNull
    return unifiedTextDiff(before:change["before"].string,after:change["after"].string,semantic:semantic)
}

// This projection does not depend on panel visibility or Focus. Keep page
// correspondence separate from text reading, region matching and appearance.
enum DocumentSelectedContextCategory:String {case pageCorrespondence,textAssessment,regionCorrespondence,appearanceAssessment}
struct DocumentSelectedContextItem:Equatable {
    let category:DocumentSelectedContextCategory
    let status:String
    let reasons:[String]
}
func documentSelectedContext(_ change:JSON)->[DocumentSelectedContextItem] {
    guard !change.isNull else{return []}
    var result:[DocumentSelectedContextItem]=[]
    let lineage=change["lineage"],reasons=lineage["reasons"].array.map(\.string)
    if !lineage["status"].string.isEmpty || !reasons.isEmpty {result.append(DocumentSelectedContextItem(category:.pageCorrespondence,status:lineage["status"].string,reasons:reasons))}
    for (field,category) in [("text_assessment",DocumentSelectedContextCategory.textAssessment),("region_pairing_assessment",.regionCorrespondence),("appearance_assessment",.appearanceAssessment)] {
        if !change[field].string.isEmpty {result.append(DocumentSelectedContextItem(category:category,status:change[field].string,reasons:[]))}
    }
    return result
}

struct DocumentReportQualityCount:Equatable {let key:String;let count:Int}
struct DocumentReportDetailsProjection {
    let totalCoverageGaps:Int
    let gaps:[JSON]
    let quality:[DocumentReportQualityCount]
    var coverageTruncated:Bool {totalCoverageGaps>gaps.count}
}
func documentReportDetails(_ report:JSON)->DocumentReportDetailsProjection {
    let all=report["coverage_gaps"].array
    let count=report["coverage_gap_count"].isNull ? all.count:max(all.count,report["coverage_gap_count"].int)
    let qualityKeys=["ocr_inferred_pages","ocr_failed_pages","unresolved_comparison_pages","reference_pdf_pages","human_reference_pdf_pages","inferred_reference_pdf_pages","pptx_without_render"]
    let quality=qualityKeys.filter{!report["quality_counts"][$0].isNull}.map{DocumentReportQualityCount(key:$0,count:max(0,report["quality_counts"][$0].int))}
    return DocumentReportDetailsProjection(totalCoverageGaps:count,gaps:Array(all.prefix(50)),quality:quality)
}
