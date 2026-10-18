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
            model.inspector=true
            try await Task.sleep(nanoseconds:700_000_000);try capture(output.appendingPathComponent("native-compare.png"))
            model.inspector=false;model.focus=true;model.showChanges=false;model.pageMode="after"
            if model.primaryPages(model.revision(model.to)).count>=300{model.rightPageID=model.primaryPages(model.revision(model.to))[299]["page_id"].string}
            try await Task.sleep(nanoseconds:700_000_000);try capture(output.appendingPathComponent("native-focus.png"))
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
            let result:[String:Any]=["native_ui":"SwiftUI/AppKit/PDFKit","report_id":model.report["report_id"].string,"project_id":model.projectID,"pages":model.revisions.map{model.primaryPages($0).count},"numeric_changes":numeric.map(\.raw),"analysis_and_ui_seconds":Date().timeIntervalSince(startedAt),"error":model.error,"mcp_config":model.mcp]
            try JSON(result).data().write(to:output.appendingPathComponent("result.json"));NSApp.terminate(nil)
        }catch{if let output=ProcessInfo.processInfo.environment["DOCVER_SMOKE_OUTPUT"]{try? JSON(["error":error.localizedDescription]).data().write(to:URL(fileURLWithPath:output))};fputs("Docver native smoke failed: \(error)\n",stderr);NSApp.terminate(nil)}
    }
    static func capture(_ url:URL) throws {
        guard let window=NSApp.windows.first(where:{$0.isVisible && $0.contentView != nil}),let view=window.contentView,let bitmap=view.bitmapImageRepForCachingDisplay(in:view.bounds) else{throw BridgeError(code:"CAPTURE_FAILED",message:"앱 화면을 캡처할 수 없습니다.")}
        view.cacheDisplay(in:view.bounds,to:bitmap)
        guard let png=bitmap.representation(using:.png,properties:[:]) else{throw BridgeError(code:"CAPTURE_FAILED",message:"PNG 생성 실패")};try png.write(to:url)
    }
}
