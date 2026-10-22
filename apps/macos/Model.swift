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
    let message:String
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
                catch{sidecarRecoveryWarning="참고 작업을 정리하지 못했습니다. 임시 작업 폴더를 확인하세요. "+error.localizedDescription}
            }
        }
    }
    @Published var sidecarRecoveryWarning = ""
    @Published var documentRecoveryWarning = ""
    @Published var workbookRecoveryWarning = ""
    var sidecarResult = JSON()
    var sidecarFailure = ""
    @Published var loading = false
    @Published var loadingChanges = false
    @Published var changesFailure = ""
    @Published var committing = false
    @Published var status = ""
    @Published var evidenceWarning = ""
    @Published var error = ""
    @Published var progress = JSON()
    @Published var tab = "compare"
    @Published var focus = false
    @Published var inspector = false
    @Published var showChanges = true
    @Published var pageMode = "both"
    @Published var zoom = 0.0
    @Published var search = ""
    @Published var kind = "all"
    @Published var mcp = ""
    @Published var mcpFailure = ""
    @Published var reorderConfirmation:ReorderConfirmation?
    @Published var importSheet = false
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
    private var pageNavigation: (report:String, from:Int, to:Int, left:String, right:String)?
    init() {
        let resources = Bundle.main.resourceURL!
        let base = ProcessInfo.processInfo.environment["DOCVER_TEST_USER_DATA"].map { URL(fileURLWithPath: $0) } ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Docver")
        let library = base.appendingPathComponent("library")
        try? FileManager.default.createDirectory(at: library, withIntermediateDirectories: true)
        bridge = Bridge(resources: resources, library: library)
        libraryLock = Darwin.open(library.appendingPathComponent(".app-lock").path, O_CREAT | O_RDWR | O_CLOEXEC, S_IRUSR | S_IWUSR)
        if libraryLock < 0 || flock(libraryLock, LOCK_EX | LOCK_NB) != 0 { libraryAvailable = false; error = "이 보관소를 사용하는 Reviset 또는 Docver 앱이 이미 실행 중입니다." }
    }
    var project: JSON { projects.first { $0["project_id"].string == projectID } ?? JSON() }
    var revisions: [JSON] { report["revisions"].array }
    var selected: JSON { changes.first { $0["change_id"].string == selectedChangeID } ?? JSON() }
    var filteredChanges: [JSON] { changes.filter { (kind == "all" || $0["kind"].string == kind) && (search.isEmpty || ($0["before"].string + " " + $0["after"].string).localizedCaseInsensitiveContains(search)) } }
    var currentMCPConfig:String? {libraryAvailable && !initializing && !loading && mcpProjectID==projectID && !mcp.isEmpty ? mcp:nil}
    var emptyChangesMessage:String {
        if busy && changes.isEmpty {return "분석 중입니다. 완료 후 변경 목록을 다시 불러옵니다."}
        if loadingChanges || loading {return "변경 목록을 불러오고 있습니다…"}
        if !changesFailure.isEmpty {return changesFailure=="새 입력 처리로 변경 목록 조회를 중단했습니다." ? changesFailure:"변경 목록을 불러오지 못했습니다. 구간을 다시 선택하거나 보고서를 다시 여세요."}
        if revisions.count<2 {return "두 버전 이상을 가져오면 변경을 비교할 수 있습니다."}
        if changes.isEmpty {return "선택한 구간에서 감지된 변경이 없습니다. 판독 보류와 관측 한계는 원문 근거에서 확인하세요."}
        return "필터·검색과 일치하는 변경이 없습니다. 유형이나 검색어를 바꿔 보세요."
    }
    func primaryPages(_ revision: JSON) -> [JSON] {
        let pptx = revision["assets"].array.filter { $0["format"].string == "pptx" }.map { $0["asset_id"].string }
        return revision["pages"].array.filter { pptx.isEmpty || pptx.contains($0["asset_id"].string) }
    }
    func revision(_ index: Int) -> JSON { revisions.indices.contains(index) ? revisions[index] : JSON() }
    var mappingSelection: JSON {
        report["mapping_relations"].array.first { $0["from_occurrence"].string == revision(from)["revision_occurrence_id"].string && $0["to_occurrence"].string == revision(to)["revision_occurrence_id"].string && $0["from_page_ids"].array.map(\.string).contains(leftPageID) && $0["to_page_ids"].array.map(\.string).contains(rightPageID) } ?? JSON(["kind":"continuation","from_page_ids":[leftPageID],"to_page_ids":[rightPageID],"reason":""])
    }
    func fail(_ e: Error) { error = e.localizedDescription }
    func refresh() async throws { projects = try await bridge.call("projects").array }
    func start() async {
        guard error.isEmpty && !started else {if !started{initializing=false};return};started = true;defer{initializing=false}
        do {
            do { _ = try await bridge.call("recover") }
            catch { documentRecoveryWarning = "이전 문서 임시 작업을 정리하지 못했습니다. 저장된 보고서는 계속 열 수 있습니다. " + error.localizedDescription }
            do { _ = try await bridge.call("workbookRecover") }
            catch { workbookRecoveryWarning = "이전 스프레드시트 임시 작업을 정리하지 못했습니다. 문서 비교는 계속 사용할 수 있습니다. " + error.localizedDescription }
            if let recovered=try? await bridge.call("sidecarRecover"),recovered["skipped"].int>0 {sidecarRecoveryWarning="이전 참고 작업 \(recovered["skipped"].int)개를 자동 정리하지 못했습니다. 원문과 변경 이력은 계속 사용할 수 있습니다."}
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
                let loadedReport = try await bridge.call("view", ["project_id": id, "report_id": reportID]);guard generation==selectionGeneration else{return};report=loadedReport; from = 0; to = min(1, revisions.count - 1)
                leftPageID = primaryPages(revision(from)).first?["page_id"].string ?? ""
                rightPageID = primaryPages(revision(to)).first?["page_id"].string ?? ""
                try await updateChanges()
            }
        } catch {if generation==selectionGeneration{fail(error)}}
        if generation==selectionGeneration{loading = false}
    }
    func updateChanges() async throws {
        guard !report.isNull else { return }
        if revisions.count < 2 { changes = []; selectedChangeID = ""; selectEvidence(); return }
        let history = tab == "history", start = history ? 0 : from, end = history ? revisions.count - 1 : to
        let project=projectID,reportID=report["report_id"].string,before=revision(start)["revision_occurrence_id"].string,after=revision(end)["revision_occurrence_id"].string
        let mode=history ? "history" : end == start+1 ? "adjacent" : "range_net"
        let key=[project,reportID,before,after,mode].joined(separator:"|")
        let preferredChange=selectedChangeID
        let generation:Int,task:Task<[JSON],Error>
        if let pending=pendingRange,pending.key==key {
            generation=pending.generation;task=pending.task
        } else {
            pendingRange?.task.cancel()
            rangeGeneration += 1;generation=rangeGeneration;loadingChanges=true;changesFailure="";changes=[];selectedChangeID=nil
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
            changes=[];selectedChangeID=nil;loadingChanges=false;changesFailure=error.localizedDescription;selectEvidence()
            if pendingRange?.generation==generation {pendingRange=nil}
            throw error
        }
    }

    func selectEvidence() {
        if let n=pageNavigation,n.report==report["report_id"].string,n.from==from,n.to==to {
            leftPageID=normalizedPage(n.left,in:revision(from),preserveAbsent:true)
            rightPageID=normalizedPage(n.right,in:revision(to),preserveAbsent:true)
            return
        }
        guard !selected.isNull else {
            evidenceWarning=""
            leftPageID=normalizedPage(leftPageID,in:revision(from))
            rightPageID=normalizedPage(rightPageID,in:revision(to))
            return
        }
        if tab == "history" { return }
        evidenceWarning=""
        let evidence = selected["evidence"].array
        leftPageID = evidenceSelection(evidence, in:revision(from), current:leftPageID)
        rightPageID = evidenceSelection(evidence, in:revision(to), current:rightPageID)
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
            evidenceWarning="이 근거에 대응하는 원문 페이지를 확인할 수 없습니다."
            return primary.contains(current) ? current : ""
        }
        return resolved.contains(current) ? current : resolved.first ?? ""
    }
    func displayPageID(_ sourcePageID:String,in revision:JSON)->String {
        primaryPages(revision).first { $0["appearance"]["source_page_id"].string == sourcePageID }?["page_id"].string ?? sourcePageID
    }
    func navigatePage(_ id:String,in occurrence:String) {
        let before=revision(from),after=revision(to)
        guard occurrence==before["revision_occurrence_id"].string || occurrence==after["revision_occurrence_id"].string else{return}
        let target=occurrence==before["revision_occurrence_id"].string ? before:after
        guard id.isEmpty || primaryPages(target).contains(where:{$0["page_id"].string==id}) else{evidenceWarning="선택한 원문 페이지를 확인할 수 없습니다.";return}
        if occurrence==before["revision_occurrence_id"].string{leftPageID=id}
        if occurrence==after["revision_occurrence_id"].string{rightPageID=id}
        evidenceWarning="";pageNavigation=(report["report_id"].string,from,to,leftPageID,rightPageID)
    }
    func chooseChange(_ id:String){
        guard !loadingChanges else{return}
        if tab=="history",let change=changes.first(where:{$0["change_id"].string==id}),let a=revisions.firstIndex(where:{$0["revision_occurrence_id"].string==change["from_occurrence"].string}),let b=revisions.firstIndex(where:{$0["revision_occurrence_id"].string==change["to_occurrence"].string}),a<b {
            from=a;to=b;tab="compare";inspector=true;evidenceWarning="";pageNavigation=nil
            Task {
                do{try await updateChanges();guard from==a,to==b,changes.contains(where:{$0["change_id"].string==id})else{return};selectedChangeID=id;selectEvidence()}
                catch{fail(error)}
            }
            return
        }
        evidenceWarning="";pageNavigation=nil;selectedChangeID=id;selectEvidence()
    }
    func openHistoryPage(_ index:Int,_ pageID:String){
        evidenceWarning=""
        from=max(0,index-1);to=min(revisions.count-1,max(1,index))
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
        guard libraryAvailable && !initializing && !busy && !projects.contains(where:{$0["project_id"].string==id && $0["unreadable"].bool}) else { return };selectionGeneration += 1;rangeGeneration += 1;pendingRange?.task.cancel();pendingRange=nil;loading=false;loadingChanges=false;changesFailure="";evidenceWarning="";let token=UUID();analysisToken=token; busy = true; committing = false; cancelRequested = false; error = ""; progress = JSON(); status = "문서를 준비하고 있습니다"
        let generation=selectionGeneration,retainedProject=projectID,retainedReport=report["report_id"].string
        var runID="",commitAttempted=false
        defer{bridge.releaseAnalysis(owner:token)}
        do {
            let result = try await bridge.call("analyze", ["project_id": id], analysis: true,progress:{ [weak self] p in
                Task { @MainActor in guard let self,self.busy,!self.committing,self.analysisToken==token else{return}; self.progress = p; self.status = p["phase"].string == "match" ? "페이지 대응과 변경을 계산합니다" : p["phase"].string == "render" ? p["label"].string+" 화면 준비 중" : p["label"].string.isEmpty ? "원본을 추출합니다" : p["label"].string + " 추출 중" }
            },analysisOwner:token,holdAnalysis:true)
            runID=result["analysis_run_id"].string
            if cancelRequested { throw BridgeError(code: "CANCELLED", message: "분석을 취소했습니다.") }
            committing = true; commitAttempted=true; status = "고정 보고서를 저장합니다"
            let committed = try await bridge.call("commit", ["project_id": id, "result": result.raw])
            guard committed["status"].string=="complete",!committed["report_id"].string.isEmpty else { throw BridgeError(code:"COMMIT_REPLY",message:"분석 저장 응답을 확인하지 못했습니다.") }
            bridge.releaseAnalysis(owner:token)
            analysisToken=nil;busy = false; committing = false
            if committed["cleanup_pending"].bool { documentRecoveryWarning="분석 결과는 저장됐으며 임시 파일 정리를 확인해야 합니다." }
            guard generation==selectionGeneration else { return }
            await openCompletedReport(id,snapshot:committed["report_id"].string,recovered:false)
        } catch {
            let runError=error
            if runID.isEmpty { runID=progress["analysis_run_id"].string }
            var recoveredReport="",cleanupPending=false,uncertain=commitAttempted,recoveryWarning=""
            var mayRecover = !commitAttempted
            if commitAttempted, !runID.isEmpty {
                committing=true;status="이번 분석의 저장 상태를 확인합니다"
                do {
                    let run=try await bridge.call("runStatus",["project_id":id,"analysis_run_id":runID])
                    guard run["project_id"].string==id,run["analysis_run_id"].string==runID else { throw BridgeError(code:"RUN_SCOPE",message:"이번 분석의 저장 상태 범위를 확인하지 못했습니다.") }
                    if ["success","partial"].contains(run["status"].string),!run["report_id"].string.isEmpty {
                        recoveredReport=run["report_id"].string;cleanupPending=run["cleanup_pending"].bool;uncertain=false
                    } else if ["running","failed","interrupted"].contains(run["status"].string),run["report_id"].isNull {
                        uncertain=false;mayRecover=true
                    } else { recoveryWarning="이번 분석의 저장 여부를 확인하지 못했습니다." }
                } catch { recoveryWarning="이번 분석의 저장 여부 확인 필요: " + error.localizedDescription }
            }
            if mayRecover,!runID.isEmpty {
                do { _ = try await bridge.call("recover",["run_id":runID]) }
                catch { recoveryWarning="이번 문서 분석의 임시 파일 정리를 확인하지 못했습니다. " + error.localizedDescription }
            }
            // Release the writer only after the exact owned run is reconciled;
            // report reads must not hold another window's analysis reservation.
            bridge.releaseAnalysis(owner:token)
            analysisToken=nil;committing=false;busy=false
            if cleanupPending { recoveryWarning="분석 결과는 저장됐으며 임시 파일 정리를 확인해야 합니다." }
            if uncertain && recoveryWarning.isEmpty { recoveryWarning="이번 분석의 저장 여부를 확인하지 못했습니다. 저장 상태를 다시 확인해야 합니다." }
            if !recoveryWarning.isEmpty { documentRecoveryWarning=recoveryWarning }
            guard generation==selectionGeneration else { return }
            if !recoveredReport.isEmpty {
                await openCompletedReport(id,snapshot:recoveredReport,recovered:true)
                return
            }
            let cancelled=cancelRequested || runError is CancellationError || (runError as? BridgeError)?.code=="CANCELLED"
            let outcome=uncertain ? "저장 여부 확인 필요 · 마지막으로 확인한 상태를 유지합니다." : cancelled ? "분석을 취소했습니다. 이전 보고서는 유지됩니다." : "분석하지 못했습니다. 이전 보고서는 유지됩니다."
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
            status=outcome
        }
    }
    private func openCompletedReport(_ project:String,snapshot:String,recovered:Bool) async {
        let generation=selectionGeneration+1
        await selectProject(project,snapshot:snapshot)
        guard generation==selectionGeneration,projectID==project else { return }
        guard report["report_id"].string==snapshot else { status="저장된 분석 결과를 확인했습니다. 보고서를 다시 불러와주세요.";return }
        var summary=[recovered ? "저장된 분석 결과를 확인해 다시 열었습니다." : "새 고정 보고서 저장"]
        let quality=report["quality_counts"]
        if quality["ocr_inferred_pages"].int>0{summary.append("OCR 추정 \(quality["ocr_inferred_pages"].int)쪽")}
        if quality["ocr_failed_pages"].int>0{summary.append("OCR 실패 \(quality["ocr_failed_pages"].int)쪽")}
        if quality["unresolved_comparison_pages"].int>0{summary.append("판독 보류 \(quality["unresolved_comparison_pages"].int)쪽")}
        if quality["pptx_without_render"].int>0{summary.append("PPTX 렌더 없음 \(quality["pptx_without_render"].int)쪽")}
        if quality["reference_pdf_pages"].int>0{summary.append("제공 PDF 화면 \(quality["reference_pdf_pages"].int)쪽 · 사용자 연결 \(quality["human_reference_pdf_pages"].int)쪽 · 자동 추정 \(quality["inferred_reference_pdf_pages"].int)쪽")}
        status=summary.joined(separator:" · ")
    }
    func cancel() { guard busy && !committing,let token=analysisToken else { return }; cancelRequested = true; bridge.cancel(owner:token); status = "분석을 취소하고 있습니다" }
    func create(title: String, rows: [ImportRow]) async throws -> JSON {
        let interrupted=pendingRange != nil || loadingChanges
        selectionGeneration += 1;rangeGeneration += 1;pendingRange?.task.cancel();pendingRange=nil;loading=false;loadingChanges=false;changesFailure=(!report.isNull && interrupted) ? "새 입력 처리로 변경 목록 조회를 중단했습니다.":""
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
            if project["dirty"].bool && relations+pairs+bundles>0 {error="대기 중인 페이지 대응·제공 PDF 연결 변경을 먼저 분석한 뒤 순서를 바꾸세요.";return}
            let request=ReorderConfirmation(project:projectID,draft:try project.data(),draftHash:project["draft_hash"].string,order:order,message:"순서를 바꾸면 현재 입력의 사용자 대응 \(relations)개·개별 결정 \(pairs)개와 제공 PDF 연결 이력 \(bundles)개가 초기화됩니다. 입력한 이유는 이전 고정 보고서에서 계속 확인할 수 있습니다.")
            if relations+pairs+bundles>0 {reorderConfirmation=request}else{await confirmReorder(request)}
        }catch{fail(error)}
    }
    func confirmReorder(_ request:ReorderConfirmation) async {
        reorderConfirmation=nil
        guard !busy && !loading,request.project==projectID,(try? project.data())==request.draft else{error="입력이 바뀌었습니다. 현재 버전 순서를 확인한 뒤 다시 시도하세요.";return}
        loading=true;defer{loading=false}
        do {
            _ = try await bridge.call("reorder",["project_id":request.project,"order":request.order,"discard_human_decisions":true,"draft_hash":request.draftHash])
            try await refresh();status="순서 변경은 재분석 후 새 보고서로 반영됩니다. 이전 고정 보고서는 유지됩니다."
        }catch{fail(error)}
    }
    func navigateEvidence(_ evidence: JSON) {
        guard !loadingChanges else{return}
        let occurrence=evidence["revision_occurrence_id"].string
        if occurrence == revision(from)["revision_occurrence_id"].string {
            let id=displayPageID(evidence["page_id"].string,in:revision(from))
            guard primaryPages(revision(from)).contains(where:{$0["page_id"].string==id}) else{evidenceWarning="이 근거에 대응하는 원문 페이지를 확인할 수 없습니다.";return}
            leftPageID=id
        }
        if occurrence == revision(to)["revision_occurrence_id"].string {
            let id=displayPageID(evidence["page_id"].string,in:revision(to))
            guard primaryPages(revision(to)).contains(where:{$0["page_id"].string==id}) else{evidenceWarning="이 근거에 대응하는 원문 페이지를 확인할 수 없습니다.";return}
            rightPageID=id
        }
        evidenceWarning="";pageNavigation=(report["report_id"].string,from,to,leftPageID,rightPageID)
    }
    func applyRelation(project: String, report: String, draftHash: String, before: String, after: String, left: [String], right: [String], kind: String, reason: String) async throws {
        guard !busy && project == projectID && report == self.report["report_id"].string else { throw BridgeError(code: "STALE_REPORT", message: "최신 분석 결과에서 대응을 수정하세요.") }
        _ = try await bridge.call("mappingRelation", ["project_id": project, "report_id": report, "draft_hash": draftHash, "unlink": kind == "unlink", "selection": ["kind": kind == "unlink" ? "continuation" : kind, "from_occurrence": before, "to_occurrence": after, "from_page_ids": left, "to_page_ids": right, "reason": reason]])
        try await refresh()
    }
    func isBundle(_ revision:JSON)->Bool {
        revision["assets"].array.count == 2 && Set(revision["assets"].array.map{$0["format"].string}) == Set(["pptx","pdf"])
    }
    var bundleEditingUnavailable: String? {
        if project["unreadable"].bool{return "입력 기록 손상 · 고정 보고서 읽기 전용입니다."}
        if busy || loading || initializing {return "분석과 페이지 로딩이 끝난 뒤 수정하세요."}
        if project["dirty"].bool {return "입력·대응 변경을 먼저 분석하세요."}
        if report["report_id"].string.isEmpty || project["last_report_id"].string != report["report_id"].string {return "최신 고정 보고서에서 수정하세요."}
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
        guard project == projectID,report == self.report["report_id"].string,bundleEditingUnavailable == nil else{throw BridgeError(code:"STALE_REPORT",message:"최신 분석 결과에서 제공 PDF 연결을 수정하세요. 입력 내용은 닫기 전까지 유지됩니다.")}
        let target:Any=pdf.map{$0 as Any} ?? NSNull()
        _ = try await bridge.call("bundleMapping",["project_id":project,"report_id":report,"draft_hash":draftHash,"selection":["revision_occurrence_id":occurrence,"source_asset_id":sourceAsset,"rendered_asset_id":pdfAsset,"source_page_id":source,"rendered_page_id":target,"action":action,"reason":reason]])
        try await refresh()
    }
    func exportReport() async {
        let panel = NSOpenPanel(); panel.title = "보고서를 저장할 폴더"; panel.canChooseFiles = false; panel.canChooseDirectories = true; panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let target = url.appendingPathComponent("Reviset-" + report["report_id"].string.dropFirst(4).prefix(12))
        do { _ = try await bridge.call("export", ["project_id": projectID, "report_id": report["report_id"].string, "folder": target.path]); NSWorkspace.shared.open(target); status = "JSON·JSONL·Markdown 보고서를 저장했습니다" } catch { fail(error) }
    }
    func loadMCP() async {
        let project=projectID;mcpGeneration += 1;let generation=mcpGeneration
        guard !project.isEmpty,libraryAvailable else{return}
        mcp="";mcpProjectID="";mcpFailure=""
        do {
            let config=try await bridge.call("mcpConfig",["project_id":project]).string
            guard !Task.isCancelled,project==projectID,generation==mcpGeneration else{return}
            mcpProjectID=project;mcp=config
        } catch {if !Task.isCancelled,project==projectID,generation==mcpGeneration {mcpFailure=error.localizedDescription}}
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
        guard descriptor>=0 else{throw BridgeError(code:"FILE_INPUT",message:"일반 원본 파일을 열지 못했습니다.")}
        let handle=FileHandle(fileDescriptor:descriptor,closeOnDealloc:true);defer{try? handle.close()}
        var metadata=stat()
        guard Darwin.fstat(descriptor,&metadata)==0,metadata.st_mode & S_IFMT == S_IFREG else{throw BridgeError(code:"FILE_INPUT",message:"일반 원본 파일만 가져올 수 있습니다.")}
        guard metadata.st_size<=512*1024*1024 else{throw BridgeError(code:"FILE_LIMIT",message:"파일당 512 MiB 이하를 지원합니다.")}
        var digest=SHA256(),count=0
        while let data=try handle.read(upToCount:1024*1024),!data.isEmpty {
            count += data.count
            guard count<=512*1024*1024 else{throw BridgeError(code:"FILE_LIMIT",message:"파일당 512 MiB 이하를 지원합니다.")}
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
    static func groupingUnavailable(_ rows:[ImportRow],at index:Int)->String? {
        guard rows.indices.contains(index),index>0 else{return "앞 버전이 있을 때 위와 묶을 수 있습니다."}
        let a=rows[index-1],b=rows[index]
        guard a.members.count==1,b.members.count==1 else{return "PPTX 1개와 PDF 1개만 묶을 수 있습니다."}
        guard Set((a.urls+b.urls).map{$0.pathExtension.lowercased()})==Set(["pptx","pdf"]) else{return "서로 다른 형식의 PPTX 1개와 PDF 1개를 선택하세요."}
        return nil
    }
    @discardableResult static func group(_ rows:inout [ImportRow],at index:Int)->Bool {
        guard groupingUnavailable(rows,at:index)==nil else{return false}
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
let changeNames = ["text_modified": "텍스트 수정", "page_moved": "페이지 이동", "page_added": "페이지 추가", "page_deleted": "페이지 삭제", "text_struck_through": "취소선 표시", "text_occluded": "텍스트 가림", "text_revealed": "텍스트 다시 표시", "visual_region_changed": "화면 변경", "coverage_gap": "관측 공백", "page_split": "페이지 분할", "page_merged": "페이지 병합", "page_lineage_changed": "페이지 계보 변경"]
func isReferenceAppearanceChange(_ change:JSON)->Bool {
    change["kind"].string == "visual_region_changed" && change["evidence"].array.contains { $0["method"].string == "provided_pdf_native_raster" }
}
func changeDisplayName(_ change:JSON)->String {
    if isReferenceAppearanceChange(change) { return "제공 PDF 화면 차이" }
    return changeNames[change["kind"].string] ?? "변경을 선택하세요"
}
func versionDisplayName(_ index:Int,_ revision:JSON)->String {
    let prefix="v\(index+1)",label=revision["label"].string
    return label.trimmingCharacters(in:.whitespacesAndNewlines).caseInsensitiveCompare(prefix) == .orderedSame ? prefix:prefix+" "+label
}
func changeVersionSummary(_ change:JSON,revisions:[JSON])->String {
    func name(_ key:String)->String {revisions.firstIndex{$0["revision_occurrence_id"].string==key}.map{versionDisplayName($0,revisions[$0])} ?? "버전 미확정"}
    return name(change["from_occurrence"].string)+" → "+name(change["to_occurrence"].string)
}
func notesDisplayText(_ page:JSON)->String {
    switch page["capabilities"]["notes"].string {
    case "extraction_failed":return "노트 추출 실패 · 원본을 확인하세요."
    case "unsupported":return "노트 추출 미지원 · 원본에서 확인하세요."
    case "unavailable":return "노트 관측 불가 · 이 형식에는 발표자 노트 정보가 없습니다."
    case "available":return page["notes"].isNull ? "노트 관측값을 확인할 수 없습니다.":page["notes"].string.isEmpty ? "노트 없음 · 원본 구조 관측":page["notes"].string
    default:return "노트 관측 상태 미확정 · 원본에서 확인하세요."
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
    let changed=Set(target.difference(from:reference).compactMap{change->Int? in if case let .insert(offset,_,_)=change{return offset};return nil})
    return target.enumerated().map{ChangeTextRun(text:$0.element,changed:changed.contains($0.offset))}
}
func evidenceVersionLabel(_ evidence:JSON,change:JSON,revisions:[JSON])->String {
    let occurrence=evidence["revision_occurrence_id"].string
    var indices=revisions.indices.filter{!occurrence.isEmpty && revisions[$0]["revision_occurrence_id"].string==occurrence}
    if indices.isEmpty && occurrence.isEmpty {let revision=evidence["revision_id"].string;indices=revisions.indices.filter{!revision.isEmpty && revisions[$0]["revision_id"].string==revision}}
    guard indices.count==1,let index=indices.first else{return "버전 확인 필요 · p.\(evidence["page"].int)"}
    let id=revisions[index]["revision_occurrence_id"].string
    let side=id==change["from_occurrence"].string ? "이전":id==change["to_occurrence"].string ? "이후":"다른 버전"
    return "\(side) · v\(index+1) · p.\(evidence["page"].int)"
}
