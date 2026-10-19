import SwiftUI
import AppKit

@main struct DocverApp: App {
    @StateObject private var model=AppModel()
    var body: some Scene {
        Window("Docver", id:"main") {MainView().environmentObject(model).task {await Smoke.runIfRequested(model)}}
        .defaultSize(width:1440,height:960)
        .windowToolbarStyle(.unifiedCompact)
        .commands {
            CommandGroup(after:.newItem){Button("문서 버전 가져오기…"){model.importSheet=true}.keyboardShortcut("o").disabled(model.busy || !model.libraryAvailable || model.initializing)}
            CommandGroup(after:.sidebar){Button("문서 크게 보기"){model.focus.toggle()}.keyboardShortcut("f",modifiers:[.command,.option]);Button("근거 패널"){model.inspector.toggle()}.keyboardShortcut("i",modifiers:[.command,.option])}
        }
    }
}
@MainActor enum Smoke {
    private static var started=false
    static func runIfRequested(_ model:AppModel) async {
        guard !started,let path=ProcessInfo.processInfo.environment["DOCVER_SMOKE_REQUEST"] else{return};started=true
        do{
            let request=JSON(try JSONSerialization.jsonObject(with:Data(contentsOf:URL(fileURLWithPath:path))))
            let output=URL(fileURLWithPath:request["output"].string);try FileManager.default.createDirectory(at:output,withIntermediateDirectories:true)
            // MainView's startup task may still be loading; wait cooperatively without blocking the app.
            for _ in 0..<200 {if !model.initializing{break};try await Task.sleep(nanoseconds:50_000_000)}
            guard !model.initializing else{throw BridgeError(code:"STARTUP_TIMEOUT",message:"초기화가 완료되지 않았습니다.")}
            let startedAt=Date()
            if request["files"].array.isEmpty{await model.demo()}
            else{let rows=request["files"].array.map{ImportRow(label:URL(fileURLWithPath:$0.string).deletingPathExtension().lastPathComponent,urls:[URL(fileURLWithPath:$0.string)])};let p=try await model.create(title:"수백 페이지 합성 검증",rows:rows);model.projectID=p["project_id"].string;await model.run(model.projectID)}
            guard !model.report.isNull else{throw BridgeError(code:"SMOKE_NO_REPORT",message:model.error)}
            let manualChecks=request["manual_relations"].bool ? try await exerciseManualRelations(model,output):[]
            model.inspector=true
            try await Task.sleep(nanoseconds:700_000_000);try capture(output.appendingPathComponent("native-compare.png"))
            model.inspector=false;model.focus=true;model.showChanges=false;model.pageMode="after"
            if model.primaryPages(model.revision(model.to)).count>=300{model.rightPageID=model.primaryPages(model.revision(model.to))[299]["page_id"].string}
            try await Task.sleep(nanoseconds:700_000_000);try capture(output.appendingPathComponent("native-focus.png"))
            if model.primaryPages(model.revision(model.from)).count>=300 && model.primaryPages(model.revision(model.to)).count>=300 {
                model.focus=false;model.pageMode="both";model.inspector=true
                model.leftPageID=model.primaryPages(model.revision(model.from))[239]["page_id"].string;model.rightPageID=model.primaryPages(model.revision(model.to))[239]["page_id"].string
                try await Task.sleep(nanoseconds:250_000_000);model.mappingSheet=true;try await Task.sleep(nanoseconds:500_000_000)
                guard let sheet=NSApp.windows.compactMap({$0.sheets.first}).first else { throw BridgeError(code:"LARGE_MAPPING_SHEET",message:"수백 페이지 대응 창 표시 실패") }
                try captureView(sheet,output.appendingPathComponent("native-mapping-page240.png"));model.mappingSheet=false;model.inspector=false
            }
            model.tab="history";model.focus=false;try await model.updateChanges()
            try await Task.sleep(nanoseconds:300_000_000);try capture(output.appendingPathComponent("native-history.png"))
            // Navigate both the first and final history columns and let pending range calls settle.
            for index in [0,model.revisions.count-1]{
                let id=model.primaryPages(model.revision(index)).last!["page_id"].string
                model.openHistoryPage(index,id);try await Task.sleep(nanoseconds:250_000_000)
                guard (index==0 ? model.leftPageID:model.rightPageID)==id else{throw BridgeError(code:"HISTORY_NAVIGATION",message:"전체 이력의 원문 페이지 이동 실패")}
            }
            model.tab="history";try await model.updateChanges()
            await model.loadMCP()
            let numeric=model.changes.filter{$0["kind"].string=="text_modified"}
            let result:[String:Any]=["native_ui":"SwiftUI/AppKit/PDFKit","report_id":model.report["report_id"].string,"project_id":model.projectID,"pages":model.revisions.map{model.primaryPages($0).count},"numeric_changes":numeric.map(\.raw),"analysis_and_ui_seconds":Date().timeIntervalSince(startedAt),"error":model.error,"mcp_config":model.mcp,"manual_relation_checks":manualChecks]
            try JSON(result).data().write(to:output.appendingPathComponent("result.json"));NSApp.terminate(nil)
        }catch{if let output=ProcessInfo.processInfo.environment["DOCVER_SMOKE_OUTPUT"]{try? JSON(["error":error.localizedDescription]).data().write(to:URL(fileURLWithPath:output))};fputs("Docver native smoke failed: \(error)\n",stderr);NSApp.terminate(nil)}
    }
    static func exerciseManualRelations(_ model:AppModel,_ output:URL) async throws -> [String] {
        let project=model.projectID,original=model.report["report_id"].string
        let a=model.primaryPages(model.revision(0)),b=model.primaryPages(model.revision(1)),c=model.primaryPages(model.revision(2))
        guard a.count==2 && b.count==3 && c.count==2 else { throw BridgeError(code:"MANUAL_FIXTURE",message:"분할·병합 검증 문서가 다릅니다.") }
        try await model.applyRelation(project:project,report:original,draftHash:model.report["draft_hash"].string,before:model.revision(0)["revision_occurrence_id"].string,after:model.revision(1)["revision_occurrence_id"].string,left:[a[0]["page_id"].string],right:[b[0]["page_id"].string,b[1]["page_id"].string],kind:"split",reason:"원문 확인: 전략 페이지를 설계·구현으로 분할")
        await model.run(project)
        guard model.error.isEmpty else { throw BridgeError(code:"MANUAL_SPLIT",message:model.error) }
        try await model.applyRelation(project:project,report:model.report["report_id"].string,draftHash:model.report["draft_hash"].string,before:model.revision(1)["revision_occurrence_id"].string,after:model.revision(2)["revision_occurrence_id"].string,left:[b[0]["page_id"].string,b[1]["page_id"].string],right:[c[0]["page_id"].string],kind:"merge",reason:"원문 확인: 설계·구현 페이지를 다시 병합")
        await model.run(project)
        guard model.error.isEmpty && model.report["mapping_relations"].array.count==2 else { throw BridgeError(code:"MANUAL_MERGE",message:model.error.isEmpty ? "확정 관계 저장 실패":model.error) }
        model.tab="history"
        async let first:Void=model.updateChanges();async let second:Void=model.updateChanges();_=try await(first,second)
        guard model.changes.filter({$0["kind"].string=="page_split"}).count==1 && model.changes.filter({$0["kind"].string=="page_merged"}).count==1 else { throw BridgeError(code:"MANUAL_EVENTS",message:"분할·병합 이벤트 조회 실패") }
        try await Task.sleep(nanoseconds:300_000_000);try capture(output.appendingPathComponent("native-manual-history.png"))
        for page in b.prefix(2) { model.openHistoryPage(1,page["page_id"].string);try await Task.sleep(nanoseconds:250_000_000);guard model.rightPageID==page["page_id"].string else { throw BridgeError(code:"MANUAL_BRANCH_NAVIGATION",message:"분기 원문 선택이 초기화됐습니다.") } }
        model.from=0;model.to=1;model.tab="compare";try await model.updateChanges();model.inspector=true
        let split=model.changes.first { $0["kind"].string=="page_split" }!;model.chooseChange(split["change_id"].string)
        try await Task.sleep(nanoseconds:250_000_000);model.mappingSheet=true;try await Task.sleep(nanoseconds:500_000_000)
        guard let sheet=NSApp.windows.compactMap({$0.sheets.first}).first else { throw BridgeError(code:"MANUAL_SHEET",message:"네이티브 대응 수정 창을 표시하지 못했습니다.") }
        try captureView(sheet,output.appendingPathComponent("native-relations-sheet.png"));model.mappingSheet=false
        let reports=try await model.bridge.call("reports",["project_id":project]).array
        guard reports.count==3 else { throw BridgeError(code:"MANUAL_CANCEL",message:"적용하지 않은 창에서 보고서가 바뀌었습니다.") }
        let old=try await model.bridge.call("view",["project_id":project,"report_id":original])
        guard old["mapping_relations"].array.isEmpty else { throw BridgeError(code:"MANUAL_IMMUTABILITY",message:"과거 보고서의 대응이 바뀌었습니다.") }
        return ["concurrent same-range awaits settle the immutable history response","native model split + merge persisted in3 immutable reports","every branch opens without async selection reset","actual paired native sheet rendered and dismissed without writes","original snapshot retains original topology"]
    }
    static func captureView(_ window:NSWindow,_ url:URL) throws {
        guard let view=window.contentView,let bitmap=view.bitmapImageRepForCachingDisplay(in:view.bounds) else { throw BridgeError(code:"CAPTURE_FAILED",message:"앱 화면을 캡처할 수 없습니다.") }
        view.cacheDisplay(in:view.bounds,to:bitmap)
        guard let png=bitmap.representation(using:.png,properties:[:]) else { throw BridgeError(code:"CAPTURE_FAILED",message:"PNG 생성 실패") };try png.write(to:url)
    }
    static func capture(_ url:URL) throws {
        guard let window=NSApp.windows.first(where:{$0.isVisible && $0.contentView != nil}),let view=window.contentView,let bitmap=view.bitmapImageRepForCachingDisplay(in:view.bounds) else{throw BridgeError(code:"CAPTURE_FAILED",message:"앱 화면을 캡처할 수 없습니다.")}
        view.cacheDisplay(in:view.bounds,to:bitmap)
        guard let png=bitmap.representation(using:.png,properties:[:]) else{throw BridgeError(code:"CAPTURE_FAILED",message:"PNG 생성 실패")};try png.write(to:url)
    }
}
