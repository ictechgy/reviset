import Foundation
import AppKit
import UniformTypeIdentifiers
import Darwin

@MainActor final class AppModel: ObservableObject {
    @Published var libraryAvailable = true
    @Published var initializing = true
    @Published var projects: [JSON] = []
    @Published var projectID = ""
    @Published var report = JSON()
    @Published var reports: [JSON] = []
    @Published var changes: [JSON] = []
    @Published var selectedChangeID: String? = nil
    @Published var from = 0
    @Published var to = 1
    @Published var leftPageID = ""
    @Published var rightPageID = ""
    @Published var busy = false
    @Published var loading = false
    @Published var loadingChanges = false
    @Published var committing = false
    @Published var status = ""
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
    @Published var importSheet = false
    @Published var mappingSheet = false
    let bridge: Bridge
    private var libraryLock: Int32 = -1
    private var cancelRequested = false
    private var analysisToken: UUID?
    private var started = false
    private var rangeGeneration = 0
    private var selectionGeneration = 0
    private var pendingRange: (key: String, generation: Int, task: Task<[JSON], Error>)?
    private var pageNavigation: (report:String, from:Int, to:Int, left:String, right:String)?
    init() {
        let resources = Bundle.main.resourceURL!
        let base = ProcessInfo.processInfo.environment["DOCVER_TEST_USER_DATA"].map { URL(fileURLWithPath: $0) } ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Docver")
        let library = base.appendingPathComponent("library")
        try? FileManager.default.createDirectory(at: library, withIntermediateDirectories: true)
        bridge = Bridge(resources: resources, library: library)
        libraryLock = Darwin.open(library.appendingPathComponent(".app-lock").path, O_CREAT | O_RDWR | O_CLOEXEC, S_IRUSR | S_IWUSR)
        if libraryLock < 0 || flock(libraryLock, LOCK_EX | LOCK_NB) != 0 { libraryAvailable = false; error = "이 보관소를 사용하는 Docver 앱이 이미 실행 중입니다." }
    }
    var project: JSON { projects.first { $0["project_id"].string == projectID } ?? JSON() }
    var revisions: [JSON] { report["revisions"].array }
    var selected: JSON { changes.first { $0["change_id"].string == selectedChangeID } ?? JSON() }
    var filteredChanges: [JSON] { changes.filter { (kind == "all" || $0["kind"].string == kind) && (search.isEmpty || ($0["before"].string + " " + $0["after"].string).localizedCaseInsensitiveContains(search)) } }
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
        do { _ = try await bridge.call("recover"); try await refresh(); if let p = projects.first { await selectProject(p["project_id"].string) } }
        catch { fail(error) }
    }
    func selectProject(_ id: String, snapshot: String? = nil) async {
        guard libraryAvailable && !busy else { return }
        selectionGeneration += 1;rangeGeneration += 1;pendingRange?.task.cancel();pendingRange=nil;loadingChanges=false;let generation=selectionGeneration;pageNavigation=nil
        loading = true; error = ""; projectID = id; report = JSON(); changes = []; selectedChangeID = nil
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
        if revisions.count < 2 { changes = []; selectedChangeID = ""; return }
        let history = tab == "history", start = history ? 0 : from, end = history ? revisions.count - 1 : to
        let project=projectID,reportID=report["report_id"].string,before=revision(start)["revision_occurrence_id"].string,after=revision(end)["revision_occurrence_id"].string
        let mode=history ? "history" : end == start+1 ? "adjacent" : "range_net"
        let key=[project,reportID,before,after,mode].joined(separator:"|")
        let generation:Int,task:Task<[JSON],Error>
        if let pending=pendingRange,pending.key==key {
            generation=pending.generation;task=pending.task
        } else {
            pendingRange?.task.cancel()
            rangeGeneration += 1;generation=rangeGeneration;loadingChanges=true
            task=Task { try await self.bridge.call("changes",["project_id":project,"report_id":reportID,"from":before,"to":after,"mode":mode]).array }
            pendingRange=(key,generation,task)
        }
        do {
            let response=try await task.value
            guard generation==rangeGeneration else{return}
            changes=response
            if !changes.contains(where:{$0["change_id"].string==selectedChangeID}) {
                selectedChangeID=changes.first(where:{$0["kind"].string=="text_modified"})?["change_id"].string ?? changes.first?["change_id"].string ?? ""
            }
            selectEvidence();loadingChanges=false
            if pendingRange?.generation==generation {pendingRange=nil}
        } catch {
            guard generation==rangeGeneration else{return}
            loadingChanges=false
            if pendingRange?.generation==generation {pendingRange=nil}
            throw error
        }
    }

    func selectEvidence() {
        if let n=pageNavigation,n.report==report["report_id"].string,n.from==from,n.to==to {leftPageID=n.left;rightPageID=n.right;return}
        guard !selected.isNull else { return }
        if tab == "history" { return }
        let evidence = selected["evidence"].array
        let left=evidence.filter { $0["revision_occurrence_id"].string == revision(from)["revision_occurrence_id"].string }.map { displayPageID($0["page_id"].string, in:revision(from)) }
        leftPageID = left.contains(leftPageID) ? leftPageID : left.first ?? ""
        let right=evidence.filter { $0["revision_occurrence_id"].string == revision(to)["revision_occurrence_id"].string }.map { displayPageID($0["page_id"].string, in:revision(to)) }
        rightPageID = right.contains(rightPageID) ? rightPageID : right.first ?? ""
    }
    func displayPageID(_ sourcePageID:String,in revision:JSON)->String {
        primaryPages(revision).first { $0["appearance"]["source_page_id"].string == sourcePageID }?["page_id"].string ?? sourcePageID
    }
    func chooseChange(_ id:String){guard !loadingChanges else{return};pageNavigation=nil;selectedChangeID=id;selectEvidence()}
    func openHistoryPage(_ index:Int,_ pageID:String){
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
        guard libraryAvailable && !initializing && !busy else { return };let token=UUID();analysisToken=token; busy = true; committing = false; cancelRequested = false; error = ""; progress = JSON(); status = "문서를 준비하고 있습니다"
        do {
            let result = try await bridge.call("analyze", ["project_id": id], analysis: true) { [weak self] p in
                Task { @MainActor in guard let self,self.busy,!self.committing,self.analysisToken==token else{return}; self.progress = p; self.status = p["phase"].string == "match" ? "페이지 대응과 변경을 계산합니다" : p["label"].string.isEmpty ? "원본을 추출합니다" : p["label"].string + " 추출 중" }
            }
            if cancelRequested { throw BridgeError(code: "CANCELLED", message: "분석을 취소했습니다.") }
            committing = true; status = "고정 보고서를 저장합니다"
            _ = try await bridge.call("commit", ["project_id": id, "result": result.raw])
            analysisToken=nil;busy = false; committing = false
            await selectProject(id, snapshot: result["report_id"].string)
            var summary=["새 고정 보고서 저장"]
            let quality=report["quality_counts"]
            if quality["ocr_inferred_pages"].int>0{summary.append("OCR 추정 \(quality["ocr_inferred_pages"].int)쪽")}
            if quality["ocr_failed_pages"].int>0{summary.append("OCR 실패 \(quality["ocr_failed_pages"].int)쪽")}
            if quality["unresolved_comparison_pages"].int>0{summary.append("판독 보류 \(quality["unresolved_comparison_pages"].int)쪽")}
            if quality["pptx_without_render"].int>0{summary.append("PPTX 렌더 없음 \(quality["pptx_without_render"].int)쪽")}
            if quality["reference_pdf_pages"].int>0{summary.append("제공 PDF 화면 \(quality["reference_pdf_pages"].int)쪽 · 대응 추정")}
            status=summary.joined(separator:" · ")
        } catch {
            analysisToken=nil;committing = false
            if cancelRequested || (error as? BridgeError)?.code == "CANCELLED" {
                _ = try? await bridge.call("recover", progress["analysis_run_id"].string.isEmpty ? [:] : ["run_id": progress["analysis_run_id"].string])
                status = "분석을 취소했습니다. 이전 보고서는 유지됩니다."
            } else { fail(error) }
            try? await refresh();busy=false
        }
    }
    func cancel() { guard busy && !committing else { return }; cancelRequested = true; bridge.cancel(); status = "분석을 취소하고 있습니다" }
    func create(title: String, rows: [ImportRow]) async throws -> JSON {
        try await bridge.call("create", ["title": title, "revisions": rows.map { ["label": $0.label, "files": $0.urls.map(\.path)] as [String: Any] }])
    }
    func demo() async {
        do {
            let folder = bridge.resources.appendingPathComponent("demo/lifecycle-five")
            let manifest = JSON(try JSONSerialization.jsonObject(with: Data(contentsOf: folder.appendingPathComponent("manifest.json"))))
            let rows = manifest["revisions"].array.map { ImportRow(label: $0["label"].string, urls: $0["files"].array.map { folder.appendingPathComponent($0.string) }) }
            let p = try await create(title: "사업계획 · 합성 데모", rows: rows); report = JSON(); try await refresh(); projectID = p["project_id"].string
            await run(projectID)
        } catch { fail(error) }
    }
    func reorder(_ index: Int, delta: Int) async {
        var order = Array(project["revisions"].array.indices); guard order.indices.contains(index + delta) else { return }; order.swapAt(index, index + delta)
        do { _ = try await bridge.call("reorder", ["project_id": projectID, "order": order]); try await refresh(); status = "순서 변경은 재분석 후 새 보고서로 반영됩니다" } catch { fail(error) }
    }
    func navigateEvidence(_ evidence: JSON) {
        guard !loadingChanges else{return}
        let occurrence=evidence["revision_occurrence_id"].string
        if occurrence == revision(from)["revision_occurrence_id"].string {
            let id=displayPageID(evidence["page_id"].string,in:revision(from))
            guard primaryPages(revision(from)).contains(where:{$0["page_id"].string==id}) else{status="이 근거에 대응하는 원문 페이지를 확인할 수 없습니다.";return}
            leftPageID=id
        }
        if occurrence == revision(to)["revision_occurrence_id"].string {
            let id=displayPageID(evidence["page_id"].string,in:revision(to))
            guard primaryPages(revision(to)).contains(where:{$0["page_id"].string==id}) else{status="이 근거에 대응하는 원문 페이지를 확인할 수 없습니다.";return}
            rightPageID=id
        }
        pageNavigation=(report["report_id"].string,from,to,leftPageID,rightPageID)
    }
    func applyRelation(project: String, report: String, draftHash: String, before: String, after: String, left: [String], right: [String], kind: String, reason: String) async throws {
        guard !busy && project == projectID && report == self.report["report_id"].string else { throw BridgeError(code: "STALE_REPORT", message: "최신 분석 결과에서 대응을 수정하세요.") }
        _ = try await bridge.call("mappingRelation", ["project_id": project, "report_id": report, "draft_hash": draftHash, "unlink": kind == "unlink", "selection": ["kind": kind == "unlink" ? "continuation" : kind, "from_occurrence": before, "to_occurrence": after, "from_page_ids": left, "to_page_ids": right, "reason": reason]])
        try await refresh()
    }
    func exportReport() async {
        let panel = NSOpenPanel(); panel.title = "보고서를 저장할 폴더"; panel.canChooseFiles = false; panel.canChooseDirectories = true; panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let target = url.appendingPathComponent("Docver-" + report["report_id"].string.dropFirst(4).prefix(12))
        do { _ = try await bridge.call("export", ["project_id": projectID, "report_id": report["report_id"].string, "folder": target.path]); NSWorkspace.shared.open(target); status = "JSON·JSONL·Markdown 보고서를 저장했습니다" } catch { fail(error) }
    }
    func loadMCP() async { do { mcp = try await bridge.call("mcpConfig", ["project_id": projectID]).string } catch { fail(error) } }
    func page(_ id: String) async throws -> JSON { try await bridge.call("page", ["project_id": projectID, "report_id": report["report_id"].string, "page_id": id]) }
}
struct ImportRow: Identifiable { let id = UUID(); var label: String; var urls: [URL] }
let changeNames = ["text_modified": "텍스트 수정", "page_moved": "페이지 이동", "page_added": "페이지 추가", "page_deleted": "페이지 삭제", "text_struck_through": "취소선 표시", "text_occluded": "텍스트 가림", "text_revealed": "텍스트 다시 표시", "visual_region_changed": "화면 변경", "coverage_gap": "관측 공백", "page_split": "페이지 분할", "page_merged": "페이지 병합", "page_lineage_changed": "페이지 계보 변경"]
func isReferenceAppearanceChange(_ change:JSON)->Bool {
    change["kind"].string == "visual_region_changed" && change["evidence"].array.contains { $0["method"].string == "provided_pdf_native_raster" }
}
func changeDisplayName(_ change:JSON)->String {
    if isReferenceAppearanceChange(change) { return "제공 PDF 화면 차이" }
    return changeNames[change["kind"].string] ?? "변경을 선택하세요"
}
