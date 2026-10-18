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
    let bridge: Bridge
    private var libraryLock: Int32 = -1
    private var cancelRequested = false
    private var analysisToken: UUID?
    private var started = false
    private var rangeGeneration = 0
    private var selectionGeneration = 0
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
    func fail(_ e: Error) { error = e.localizedDescription }
    func refresh() async throws { projects = try await bridge.call("projects").array }
    func start() async {
        guard error.isEmpty && !started else {if !started{initializing=false};return};started = true;defer{initializing=false}
        do { _ = try await bridge.call("recover"); try await refresh(); if let p = projects.first { await selectProject(p["project_id"].string) } }
        catch { fail(error) }
    }
    func selectProject(_ id: String, snapshot: String? = nil) async {
        guard libraryAvailable && !busy else { return }
        selectionGeneration += 1;rangeGeneration += 1;let generation=selectionGeneration;pageNavigation=nil
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
        rangeGeneration += 1; let generation = rangeGeneration
        let response = try await bridge.call("changes", ["project_id": projectID, "report_id": report["report_id"].string, "from": revision(start)["revision_occurrence_id"].string, "to": revision(end)["revision_occurrence_id"].string, "mode": history ? "history" : end == start + 1 ? "adjacent" : "range_net"]).array
        guard generation == rangeGeneration else { return }; changes = response
        selectedChangeID = changes.first(where: { $0["kind"].string == "text_modified" })?["change_id"].string ?? changes.first?["change_id"].string ?? ""
        selectEvidence()
    }
    func selectEvidence() {
        if let n=pageNavigation,n.report==report["report_id"].string,n.from==from,n.to==to {leftPageID=n.left;rightPageID=n.right;return}
        guard !selected.isNull else { return }
        if tab == "history" { return }
        let evidence = selected["evidence"].array
        leftPageID = evidence.first { $0["revision_occurrence_id"].string == revision(from)["revision_occurrence_id"].string }?["page_id"].string ?? ""
        rightPageID = evidence.first { $0["revision_occurrence_id"].string == revision(to)["revision_occurrence_id"].string }?["page_id"].string ?? ""
    }
    func chooseChange(_ id:String){pageNavigation=nil;selectedChangeID=id;selectEvidence()}
    func openHistoryPage(_ index:Int,_ pageID:String){
        from=max(0,index-1);to=min(revisions.count-1,max(1,index))
        let ids=report["lineages"].array.first{$0["page_ids"].array.map(\.string).contains(pageID)}?["page_ids"].array.map(\.string) ?? [pageID]
        let left=primaryPages(revision(from)).first{ids.contains($0["page_id"].string)}?["page_id"].string ?? ""
        let right=primaryPages(revision(to)).first{ids.contains($0["page_id"].string)}?["page_id"].string ?? ""
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
    func correctMapping(_ action: String, reason: String) async {
        do {
            _ = try await bridge.call("mapping", ["project_id": projectID, "report_id": report["report_id"].string, "decision": ["from_page_id": leftPageID, "to_page_id": rightPageID, "action": action, "reason": reason]])
            try await refresh(); await run(projectID)
        } catch { fail(error) }
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
let changeNames = ["text_modified": "텍스트 수정", "page_moved": "페이지 이동", "page_added": "페이지 추가", "page_deleted": "페이지 삭제", "text_struck_through": "취소선 표시", "text_occluded": "텍스트 가림", "text_revealed": "텍스트 다시 표시", "visual_region_changed": "화면 변경", "coverage_gap": "관측 공백"]
