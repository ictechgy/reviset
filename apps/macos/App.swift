import SwiftUI
import AppKit
import PDFKit
import CryptoKit

@main struct RevisetApp: App {
    @StateObject private var model=AppModel()
    @Environment(\.openWindow) private var openWindow
    var body: some Scene {
        Window("Reviset", id:"main") {MainView().environmentObject(model).task {
            await Smoke.runIfRequested(model)
            if ProcessInfo.processInfo.environment["DOCVER_WORKBOOK_SMOKE_REQUEST"] != nil {
                for _ in 0..<400 { if !model.initializing { break }; try? await Task.sleep(nanoseconds:50_000_000) }
                if let path=ProcessInfo.processInfo.environment["DOCVER_WORKBOOK_SMOKE_REQUEST"],let data=try? Data(contentsOf:URL(fileURLWithPath:path)),let raw=try? JSONSerialization.jsonObject(with:data),JSON(raw)["expect_library_locked"].bool {
                    openWindow(id:"workbooks")
                    await Smoke.workbookLockProbe(model,request:JSON(raw))
                } else if model.libraryAvailable && !model.initializing { openWindow(id:"workbooks") }
            }
        }.onReceive(NotificationCenter.default.publisher(for:NSApplication.willTerminateNotification)){_ in model.bridge.terminateAnalysis();model.sidecarRequest=nil;model.bridge.cancelSidecars()}}
        .defaultSize(width:1440,height:960)
        .windowToolbarStyle(.unifiedCompact)
        .commands {
            CommandGroup(after:.newItem){Button("문서 버전 가져오기…"){model.importSheet=true}.keyboardShortcut("o").disabled(model.busy || model.loading || !model.libraryAvailable || model.initializing);Button("스프레드시트 버전 비교…"){openWindow(id:"workbooks")}.keyboardShortcut("o",modifiers:[.command,.shift]).disabled(!model.libraryAvailable || model.initializing)}
            CommandGroup(after:.sidebar){Button("문서 크게 보기"){model.focus.toggle()}.keyboardShortcut("f",modifiers:[.command,.option]);Button("근거 패널"){model.inspector.toggle()}.keyboardShortcut("i",modifiers:[.command,.option])}
        }
        Window("Reviset · 스프레드시트",id:"workbooks") {
            Group {
            if !model.libraryAvailable {
                VStack(spacing:12) { Image(systemName:"lock.fill").font(.largeTitle); Text("다른 Reviset 또는 Docver가 이 보관소를 사용하고 있습니다."); Text("해당 앱을 종료한 뒤 다시 여세요.").foregroundStyle(.secondary) }.frame(minWidth:640,minHeight:420)
            } else if model.initializing {
                ProgressView("보관소를 준비하는 중…").frame(minWidth:640,minHeight:420)
            } else {
                VStack(spacing:0) {
                    if !model.workbookRecoveryWarning.isEmpty { Label(model.workbookRecoveryWarning,systemImage:"info.circle").font(.caption).padding(10).frame(maxWidth:.infinity,alignment:.leading).background(.orange.opacity(0.1)) }
                    WorkbookWorkspace(bridge:model.bridge)
                }
            }
            }.task { await model.start() }
        }.defaultSize(width:1440,height:960).windowToolbarStyle(.unifiedCompact)
    }
}
@MainActor enum Smoke {
    private static var started=false
    static func workbookLockProbe(_ model:AppModel,request:JSON) async {
        let folder=URL(fileURLWithPath:request["output"].string)
        do {
            try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
            let db=model.bridge.library.appendingPathComponent("docver.sqlite"),before=try fileDigest(db)
            try await Task.sleep(nanoseconds:500_000_000)
            func hasGrid(_ view:NSView)->Bool { if view.identifier?.rawValue.hasPrefix("Docver.workbook.grid.") == true {return true};return view.subviews.contains(where:hasGrid) }
            let grids=NSApp.windows.compactMap(\.contentView).contains(where:hasGrid),after=try fileDigest(db)
            let passed = !model.libraryAvailable && !model.initializing && !grids && before == after
            try JSON(["completed":passed,"checks":["library_lock_denied":!model.libraryAvailable,"workbook_grid_not_instantiated":!grids,"database_bytes_unchanged":before == after],"interaction_scope":"actual second app process and restored workbook scene; no OS gestures"]).data().write(to:folder.appendingPathComponent("validation.json"))
        } catch {try? JSON(["completed":false,"error":error.localizedDescription]).data().write(to:folder.appendingPathComponent("validation.json"))}
        NSApp.terminate(nil)
    }
    static func runIfRequested(_ model:AppModel) async {
        guard !started,let path=ProcessInfo.processInfo.environment["DOCVER_SMOKE_REQUEST"] else{return};started=true
        do{
            let request=JSON(try JSONSerialization.jsonObject(with:Data(contentsOf:URL(fileURLWithPath:path))))
            let output=URL(fileURLWithPath:request["output"].string);try FileManager.default.createDirectory(at:output,withIntermediateDirectories:true)
            // MainView's startup task may still be loading; wait cooperatively without blocking the app.
            for _ in 0..<200 {if !model.initializing{break};try await Task.sleep(nanoseconds:50_000_000)}
            guard !model.initializing else{throw BridgeError(code:"STARTUP_TIMEOUT",message:"초기화가 완료되지 않았습니다.")}
            let startedAt=Date()
            if !request["existing_project_id"].string.isEmpty {
                await model.selectProject(request["existing_project_id"].string,snapshot:request["existing_report_id"].string)
            } else if !request["bundle_revisions"].array.isEmpty {
                let rows=request["bundle_revisions"].array.map{r in ImportRow(label:r["label"].string,urls:r["files"].array.map{URL(fileURLWithPath:$0.string)})}
                let p=try await model.create(title:"제공 PDF 화면 근거 검증",rows:rows);model.projectID=p["project_id"].string;await model.run(model.projectID)
            } else if request["files"].array.isEmpty{await model.demo()}
            else{let rows=request["files"].array.map{ImportRow(label:URL(fileURLWithPath:$0.string).deletingPathExtension().lastPathComponent,urls:[URL(fileURLWithPath:$0.string)])};let p=try await model.create(title:"수백 페이지 합성 검증",rows:rows);model.projectID=p["project_id"].string;await model.run(model.projectID)}
            guard !model.report.isNull else{throw BridgeError(code:"SMOKE_NO_REPORT",message:model.error)}
            let assets=model.bridge.library.appendingPathComponent("assets")
            let assetFacts=try FileManager.default.contentsOfDirectory(at:assets,includingPropertiesForKeys:nil).filter{$0.lastPathComponent.range(of:"^[a-f0-9]{64}$",options:.regularExpression) != nil}.map{url in
                (url:url,sha:try fileDigest(url),modified:try FileManager.default.attributesOfItem(atPath:url.path)[.modificationDate] as? Date)
            }
            let aspectChecks=request["aspect_ratio_checks"].bool ? try await exerciseAspectRatios(model,output):[]
            if request["bundle_sheet_page"].int>0 {
                let revision=model.revision(0),number=request["bundle_sheet_page"].int
                guard let selected=model.primaryPages(revision).first(where:{$0["page"].int==number}) else{throw BridgeError(code:"BUNDLE_LARGE_PAGE",message:"수백 페이지 묶음의 선택 페이지를 찾지 못했습니다.")}
                let context=try await model.bundleContext(project:model.projectID,report:model.report["report_id"].string,occurrence:revision["revision_occurrence_id"].string)
                guard context["revision"]["pages"].array.count>=600,context["mapping"].array.contains(where:{$0["source_page_id"].string==selected["page_id"].string}) else{throw BridgeError(code:"BUNDLE_LARGE_CONTEXT",message:"수백 페이지 묶음의 연결 정보가 다릅니다.")}
                model.openBundle(revision,source:selected["page_id"].string);try await Task.sleep(nanoseconds:850_000_000)
                guard model.bundleSourceID==selected["page_id"].string,let sheet=NSApp.windows.compactMap({$0.sheets.first}).first else{throw BridgeError(code:"BUNDLE_LARGE_SHEET",message:"선택한 페이지의 묶음 수정 창을 열지 못했습니다.")}
                try captureView(sheet,output.appendingPathComponent("native-bundle-page240.png"));model.bundleSheet=false;try await Task.sleep(nanoseconds:200_000_000)
            }
            let manualChecks=request["manual_relations"].bool ? try await exerciseManualRelations(model,output):[]
            let layoutChecks=request["layout_checks"].bool ? try await exerciseLayout(model):[:]
            let referenceChecks=request["reference_appearance_checks"].bool ? try await exerciseReferenceAppearance(model):[:]
            let importChecks=request["import_draft_files"].array.isEmpty ? [:]:try await exerciseImportDraft(model,output,request["import_draft_files"].array.map{URL(fileURLWithPath:$0.string)})
            let bundleChecks=request["bundle_mapping_checks"].bool ? try await exerciseBundleMapping(model,output):[:]
            let sidecarChecks=request["sidecar_checks"].bool ? try await exerciseSidecar(model,output,request["sidecar_page"].int):[:]
            model.inspector=true
            try await Task.sleep(nanoseconds:700_000_000);try capture(output.appendingPathComponent("native-compare.png"))
            model.inspector=false;model.focus=true;model.showChanges=false;model.pageMode="after"
            if model.primaryPages(model.revision(model.to)).count>=300{model.rightPageID=model.primaryPages(model.revision(model.to))[299]["page_id"].string}
            try await Task.sleep(nanoseconds:700_000_000);try capture(output.appendingPathComponent("native-focus.png"))
            if model.from != model.to && model.primaryPages(model.revision(model.from)).count>=300 && model.primaryPages(model.revision(model.to)).count>=300 {
                model.focus=false;model.pageMode="both";model.inspector=true
                model.leftPageID=model.primaryPages(model.revision(model.from))[239]["page_id"].string;model.rightPageID=model.primaryPages(model.revision(model.to))[239]["page_id"].string
                try await Task.sleep(nanoseconds:250_000_000);model.mappingSheet=true;try await Task.sleep(nanoseconds:500_000_000)
                guard let sheet=NSApp.windows.compactMap({$0.sheets.first}).first else { throw BridgeError(code:"LARGE_MAPPING_SHEET",message:"수백 페이지 대응 창 표시 실패") }
                try captureView(sheet,output.appendingPathComponent("native-mapping-page240.png"));model.mappingSheet=false;model.inspector=false
            }
            model.tab="history";model.focus=false;try await model.updateChanges()
            try await Task.sleep(nanoseconds:300_000_000);try capture(output.appendingPathComponent("native-history.png"))
            var historyChangeCheck:[String:Any]=[:]
            if let change=model.changes.last(where:{$0["kind"].string=="text_modified"}) {
                let id=change["change_id"].string,before=change["from_occurrence"].string,after=change["to_occurrence"].string
                model.chooseChange(id)
                for _ in 0..<200 {
                    if !model.loadingChanges && model.selectedChangeID==id && model.tab=="compare" {break}
                    try await Task.sleep(nanoseconds:20_000_000)
                }
                try await Task.sleep(nanoseconds:300_000_000)
                let evidence=change["evidence"].array
                guard model.tab=="compare",model.selectedChangeID==id,model.revision(model.from)["revision_occurrence_id"].string==before,model.revision(model.to)["revision_occurrence_id"].string==after,
                      evidence.contains(where:{$0["revision_occurrence_id"].string==before && model.displayPageID($0["page_id"].string,in:model.revision(model.from))==model.leftPageID}),
                      evidence.contains(where:{$0["revision_occurrence_id"].string==after && model.displayPageID($0["page_id"].string,in:model.revision(model.to))==model.rightPageID}) else {throw BridgeError(code:"HISTORY_CHANGE_SELECTION",message:"실제 이력 선택과 비교 구간·원문 근거가 다릅니다.")}
                historyChangeCheck=["selected_change_id":id,"from_occurrence":before,"to_occurrence":after,"source_pages_verified":true]
                try capture(output.appendingPathComponent("native-history-change.png"));model.tab="history";try await model.updateChanges()
            }
            // Navigate both the first and final history columns and let pending range calls settle.
            for index in [0,model.revisions.count-1]{
                let id=model.primaryPages(model.revision(index)).last!["page_id"].string
                model.openHistoryPage(index,id);try await Task.sleep(nanoseconds:250_000_000)
                guard (index==0 ? model.leftPageID:model.rightPageID)==id else{throw BridgeError(code:"HISTORY_NAVIGATION",message:"전체 이력의 원문 페이지 이동 실패")}
            }
            model.tab="history";try await model.updateChanges()
            await model.loadMCP()
            let numeric=model.changes.filter{$0["kind"].string=="text_modified"}
            let result:[String:Any]=["native_ui":"SwiftUI/AppKit/PDFKit","report_id":model.report["report_id"].string,"project_id":model.projectID,"pages":model.revisions.map{model.primaryPages($0).count},"numeric_changes":numeric.map(\.raw),"analysis_and_ui_seconds":Date().timeIntervalSince(startedAt),"error":model.error,"mcp_config":model.mcp,"manual_relation_checks":manualChecks,"layout_checks":layoutChecks,"reference_appearance_checks":referenceChecks,"import_draft_checks":importChecks,"bundle_mapping_checks":bundleChecks,"smoke_invocation_id":request["smoke_invocation_id"].string]
            var complete=result;complete["aspect_ratio_checks"]=aspectChecks
            for fact in assetFacts {
                let modified=try FileManager.default.attributesOfItem(atPath:fact.url.path)[.modificationDate] as? Date
                guard try fileDigest(fact.url)==fact.sha,modified==fact.modified else{throw BridgeError(code:"SOURCE_ASSET_CHANGED",message:"화면 표시 후 저장 원본의 hash 또는 수정 시간이 바뀌었습니다.")}
            }
            complete["source_assets_unchanged"]=assetFacts.map{["name":$0.url.lastPathComponent,"sha256":$0.sha]}
            complete["history_change_check"]=historyChangeCheck
            complete["sidecar_checks"]=sidecarChecks
            try JSON(complete).data().write(to:output.appendingPathComponent("result.json"));NSApp.terminate(nil)
        }catch{if let output=ProcessInfo.processInfo.environment["DOCVER_SMOKE_OUTPUT"]{try? JSON(["error":error.localizedDescription]).data().write(to:URL(fileURLWithPath:output))};fputs("Reviset native smoke failed: \(error)\n",stderr);NSApp.terminate(nil)}
    }
    static func exerciseSidecar(_ model:AppModel,_ output:URL,_ requestedPage:Int) async throws->[String:Any] {
        guard model.sidecarConfigured else{throw BridgeError(code:"SIDECAR_NOT_CONFIGURED",message:"참고 렌더러가 준비되지 않았습니다.")}
        let revision=model.revision(0),pages=model.primaryPages(revision)
        guard let page=(requestedPage>0 ? pages.first(where:{$0["page"].int==requestedPage}):pages.last) else{throw BridgeError(code:"SIDECAR_PAGE",message:"참고 화면의 원문 페이지가 없습니다.")}
        let before=try model.report.data(),database=model.bridge.library.appendingPathComponent("docver.sqlite"),beforeDB=try fileDigest(database)
        model.openSidecar(revision,page:page["page_id"].string)
        guard let request=model.sidecarRequest else{throw BridgeError(code:"SIDECAR_OPEN",message:"참고 화면 요청을 만들지 못했습니다.")}
        func pdfView(_ view:NSView)->PDFView? {
            if let pdf=view as? PDFView{return pdf}
            for child in view.subviews{if let pdf=pdfView(child){return pdf}}
            return nil
        }
        do {
            var sheet:NSWindow?,pdf:PDFView?
            for _ in 0..<3600 {
                if !model.sidecarFailure.isEmpty{throw BridgeError(code:"SIDECAR_RENDER_FAILED",message:model.sidecarFailure)}
                sheet=NSApp.windows.compactMap{$0.sheets.first}.first
                if let content=sheet?.contentView,let candidate=pdfView(content),let doc=candidate.document,let current=candidate.currentPage,doc.pageCount==pages.count,doc.index(for:current)==page["page"].int-1 {pdf=candidate;break}
                try await Task.sleep(nanoseconds:50_000_000)
            }
            guard let sheet,let pdf,let doc=pdf.document else{throw BridgeError(code:"SIDECAR_PDFKIT",message:"실제 PDFKit 참고 페이지가 열리지 않았습니다.")}
            try await Task.sleep(nanoseconds:350_000_000);try captureView(sheet,output.appendingPathComponent("native-sidecar.png"))
            let jobs=model.bridge.library.appendingPathComponent("sidecars-v1/jobs"),leases=model.bridge.library.appendingPathComponent("sidecars-v1/leases")
            let pdfPath=jobs.appendingPathComponent(request.id).appendingPathComponent("converted.pdf"),pdfSHA=try fileDigest(pdfPath)
            guard model.sidecarResult["pdf_sha256"].string==pdfSHA,doc.documentURL?.resolvingSymlinksInPath().standardizedFileURL==pdfPath.resolvingSymlinksInPath().standardizedFileURL else{throw BridgeError(code:"SIDECAR_PDF_HASH",message:"참고 화면과 변환 결과의 PDF hash 또는 경로가 다릅니다.")}
            guard FileManager.default.fileExists(atPath:leases.appendingPathComponent(request.id+".active.json").path) else{throw BridgeError(code:"SIDECAR_LEASE",message:"참고 화면 작업의 소유권이 없습니다.")}
            model.sidecarRequest=nil
            for _ in 0..<200 {
                let a=(try? FileManager.default.contentsOfDirectory(atPath:jobs.path)) ?? [],b=(try? FileManager.default.contentsOfDirectory(atPath:leases.path)) ?? []
                if a.isEmpty&&b.isEmpty{break};try await Task.sleep(nanoseconds:25_000_000)
            }
            let remainingJobs=try FileManager.default.contentsOfDirectory(atPath:jobs.path),remainingLeases=try FileManager.default.contentsOfDirectory(atPath:leases.path)
            guard remainingJobs.isEmpty&&remainingLeases.isEmpty else{throw BridgeError(code:"SIDECAR_CLEANUP",message:"참고 화면의 임시 작업이 남았습니다.")}
            let after=try await model.bridge.call("view",["project_id":request.project,"report_id":request.report])
            guard try before==model.report.data(),try before==after.data(),try beforeDB==fileDigest(database) else{throw BridgeError(code:"SIDECAR_REPORT_MUTATION",message:"참고 화면이 저장된 결과를 변경했습니다.")}
            return ["renderer":"ONLYOFFICE Desktop Editors","native_pdfkit":true,"page":page["page"].int,"page_count":doc.pageCount,"pdf_sha256":pdfSHA,"report_and_database_unchanged":true,"owned_jobs_and_leases_removed":true]
        }catch{model.sidecarRequest=nil;_ = try? await model.bridge.call("sidecarClose",request.scope);throw error}
    }
    static func fileDigest(_ url:URL)throws->String {
        let file=try FileHandle(forReadingFrom:url);defer{try? file.close()};var digest=SHA256()
        while let bytes=try file.read(upToCount:1024*1024),!bytes.isEmpty{digest.update(data:bytes)}
        return digest.finalize().map{String(format:"%02x",$0)}.joined()
    }
    static func exerciseAspectRatios(_ model:AppModel,_ output:URL) async throws->[[String:Any]] {
        model.focus=true;model.pageMode="both";model.showChanges=false;model.inspector=false;model.tab="compare";try await model.updateChanges();try await Task.sleep(nanoseconds:650_000_000)
        // The first change can be one-sided (these pages intentionally differ).
        // Select both fixture pages through the same production navigation as
        // the page picker before measuring the two visible source canvases.
        for index in [model.from,model.to] {
            let revision=model.revision(index)
            guard let page=model.primaryPages(revision).first else{throw BridgeError(code:"ASPECT_PAGE",message:"비율 검증 원문이 없습니다.")}
            model.navigatePage(page["page_id"].string,in:revision["revision_occurrence_id"].string)
        }
        // Inspect the neutral page edge independently from the legitimate blue
        // selected-evidence overlay, which is covered by the evidence checks.
        model.selectedChangeID=nil
        try await Task.sleep(nanoseconds:650_000_000)
        func canvases(_ view:NSView)->[StructureCanvas.Canvas] {
            var found:[StructureCanvas.Canvas]=[];if let canvas=view as? StructureCanvas.Canvas{found.append(canvas)}
            for child in view.subviews{found += canvases(child)};return found
        }
        func checks(_ view:NSView)throws->[[String:Any]] {
            try canvases(view).map{canvas in
                let width=canvas.page["width"].number,height=canvas.page["height"].number,displayWidth=Double(canvas.bounds.width),displayHeight=Double(canvas.bounds.height)
                // AppKit aligns representable bounds to device pixels. Measure
                // absolute error in the shorter dimension, not a percentage of
                // a thin page's width (35.2pt can legitimately snap to35pt).
                let backingScale=Double(canvas.window?.backingScaleFactor ?? 1),tolerance=1/max(1,backingScale)
                let error=abs(displayWidth*height-displayHeight*width)/max(width,height)
                guard width>0,height>0,displayWidth>0,displayHeight>0,error.isFinite,error<=tolerance+0.000001 else{throw BridgeError(code:"ASPECT_STRETCHED",message:"실제 구조 보기의 페이지 비율이 원본과 다릅니다. 원본 \(width)×\(height), 화면 \(displayWidth)×\(displayHeight), 오차 \(error)pt")}
                return ["source_width":width,"source_height":height,"display_width":displayWidth,"display_height":displayHeight,"backing_scale":backingScale,"aspect_error_points":error,"pixel_rounding_tolerance_points":tolerance,"page_ratio_preserved":true]
            }
        }
        guard let window=NSApp.windows.first(where:{$0.isVisible && $0.contentView != nil}),let content=window.contentView else{throw BridgeError(code:"ASPECT_WINDOW",message:"페이지 비율 검증 창을 찾지 못했습니다.")}
        try capture(output.appendingPathComponent("native-aspect-main.png"))
        let main=try checks(content);try JSON(["canvases":main]).data().write(to:output.appendingPathComponent("aspect-main-bounds.json"));guard main.count==2,main.contains(where:{$0["source_width"] as? Double ?? 0 < ($0["source_height"] as? Double ?? 0)/10}),main.contains(where:{$0["source_width"] as? Double ?? 0 > ($0["source_height"] as? Double ?? 0)*10}) else{throw BridgeError(code:"ASPECT_FIXTURE",message:"세로·가로로 긴 두 원본 구조를 표시하지 못했습니다. \(main)")}
        let source=model.primaryPages(model.revision(0))[0],payload=try await model.page(source["page_id"].string);guard payload["source"]["kind"].string=="pptx",payload["page"]["preview"].isNull else{throw BridgeError(code:"ASPECT_STRUCTURE",message:"구조 보기 검증에 별도 PDF 렌더를 사용했습니다.")}
        model.openBundle(model.revision(0),source:source["page_id"].string);try await Task.sleep(nanoseconds:700_000_000)
        guard let sheet=window.sheets.first,let sheetContent=sheet.contentView else{throw BridgeError(code:"ASPECT_BUNDLE_SHEET",message:"긴 페이지의 제공 PDF 연결 창을 열지 못했습니다.")}
        let selected=try checks(sheetContent);guard selected.count==1 else{throw BridgeError(code:"ASPECT_BUNDLE_SOURCE",message:"연결 창의 독립 구조 원문을 확인하지 못했습니다.")};try captureView(sheet,output.appendingPathComponent("native-aspect-bundle.png"));model.bundleSheet=false;model.focus=false;model.showChanges=true;try await Task.sleep(nanoseconds:200_000_000)
        return main+selected
    }
    static func exerciseBundleMapping(_ model:AppModel,_ output:URL) async throws->[String:Any] {
        let project=model.projectID,original=model.report["report_id"].string,revision=model.revision(0),occurrence=revision["revision_occurrence_id"].string,sources=model.primaryPages(revision)
        guard sources.count>=2,model.isBundle(revision),let pdfAsset=revision["assets"].array.first(where:{$0["format"].string=="pdf"}) else{throw BridgeError(code:"BUNDLE_FIXTURE",message:"슬라이드 두 장 이상의 PPTX·PDF 묶음이 필요합니다.")}
        let source=sources[0]["page_id"].string,wrong=sources[1]["appearance"]["source_page_id"].string,correct=sources[0]["appearance"]["source_page_id"].string,reason="  사용자 확인 🧭\n문구가 다른 PDF 페이지도 사유와 경고를 보존  "
        guard !wrong.isEmpty,!correct.isEmpty else{throw BridgeError(code:"BUNDLE_AUTO_FIXTURE",message:"최초 자동 연결 두 쌍을 확인하지 못했습니다.")}
        let first=try await model.bundleContext(project:project,report:original,occurrence:occurrence)
        guard first["current_snapshot"].bool,first["mapping"].array.count>=2,first["revision"]["pages"].array.count>=4 else{throw BridgeError(code:"BUNDLE_CONTEXT",message:"실제 수정 화면의 연결 정보를 불러오지 못했습니다.")}
        model.openBundle(revision,source:source);try await Task.sleep(nanoseconds:700_000_000)
        guard model.bundleSheet,let sheet=NSApp.windows.compactMap({$0.sheets.first}).first else{throw BridgeError(code:"BUNDLE_NATIVE_SHEET",message:"제공 PDF 연결 창을 표시하지 못했습니다.")}
        try captureView(sheet,output.appendingPathComponent("native-bundle-before.png"));model.bundleSheet=false;try await Task.sleep(nanoseconds:200_000_000)
        let untouched=try await model.bundleContext(project:project,report:original,occurrence:occurrence)
        guard untouched["decision_count"].int==0,!model.project["dirty"].bool else{throw BridgeError(code:"BUNDLE_CANCEL_WRITE",message:"적용 전 닫은 창에서 이력이 바뀌었습니다.")}
        try await model.applyBundle(project:project,report:original,draftHash:first["draft_hash"].string,occurrence:occurrence,sourceAsset:sources[0]["asset_id"].string,pdfAsset:pdfAsset["asset_id"].string,source:source,pdf:wrong,action:"link",reason:reason)
        do{try await model.applyBundle(project:project,report:original,draftHash:first["draft_hash"].string,occurrence:occurrence,sourceAsset:sources[0]["asset_id"].string,pdfAsset:pdfAsset["asset_id"].string,source:source,pdf:correct,action:"link",reason:"오래된 요청 거부");throw BridgeError(code:"BUNDLE_STALE_ACCEPTED",message:"오래된 연결 변경을 허용했습니다.")}catch let e as BridgeError where e.code=="STALE_REPORT"{}
        await model.run(project);guard model.error.isEmpty else{throw BridgeError(code:"BUNDLE_LINK_ANALYSIS",message:model.error)}
        var currentReport=model.report["report_id"].string
        let linked=try await model.page(source),independent=try await model.bridge.call("page",["project_id":project,"report_id":currentReport,"page_id":source,"basis":"source"])
        guard linked["source"]["origin"].string=="reference_pdf",linked["page"]["appearance"]["association"].string=="human_confirmed",linked["page"]["appearance"]["reason"].string==reason,linked["display_page_number"].int==first["revision"]["pages"].array.first(where:{$0["page_id"].string==wrong})?["page"].int,independent["source"]["kind"].string=="pptx" else{throw BridgeError(code:"BUNDLE_SOURCE_AUTHORITY",message:"사용자 연결의 PDF 출처·원본 구분이 일치하지 않습니다.")}
        let context=try await model.bundleContext(project:project,report:currentReport,occurrence:occurrence)
        guard context["decision_count"].int==1,context["manual_states"].array.contains(where:{$0["source_page_id"].string==sources[1]["page_id"].string && $0["displaced"].bool}) else{throw BridgeError(code:"BUNDLE_DISPLACEMENT",message:"기존 연결의 해제 이력을 확인하지 못했습니다.")}
        model.openBundle(model.revision(0),source:source);try await Task.sleep(nanoseconds:650_000_000)
        guard let changedSheet=NSApp.windows.compactMap({$0.sheets.first}).first else{throw BridgeError(code:"BUNDLE_CHANGED_SHEET",message:"수정 후 연결 창을 표시하지 못했습니다.")};try captureView(changedSheet,output.appendingPathComponent("native-bundle-human.png"));model.bundleSheet=false;try await Task.sleep(nanoseconds:150_000_000)
        for (action,target,why) in [("unlink",Optional<String>.none,"사용자가 제공 PDF 연결 해제"),("link",Optional(correct),"올바른 PDF 페이지로 재연결")]{
            let state=try await model.bundleContext(project:project,report:currentReport,occurrence:occurrence)
            try await model.applyBundle(project:project,report:currentReport,draftHash:state["draft_hash"].string,occurrence:occurrence,sourceAsset:sources[0]["asset_id"].string,pdfAsset:pdfAsset["asset_id"].string,source:source,pdf:target,action:action,reason:why)
            await model.run(project);guard model.error.isEmpty else{throw BridgeError(code:"BUNDLE_REANALYSIS",message:model.error)};currentReport=model.report["report_id"].string
            let payload=try await model.page(source);guard action=="unlink" ? payload["source"]["origin"].string != "reference_pdf":payload["page"]["appearance"]["source_page_id"].string==correct else{throw BridgeError(code:"BUNDLE_UNLINK_RELINK",message:"연결 해제·재연결 결과가 다릅니다.")}
        }
        let history=try await model.bridge.call("bundleDecisions",["project_id":project,"report_id":currentReport,"revision_id":occurrence,"max_output_tokens":8000])
        guard history["items"].array.count==3,history["items"].array[0]["reason"].string==reason else{throw BridgeError(code:"BUNDLE_HISTORY",message:"연결 이유와 세 개의 이력을 확인하지 못했습니다.")}
        let old=try await model.bridge.call("view",["project_id":project,"report_id":original]);guard old["bundle_decision_count"].int==0 else{throw BridgeError(code:"BUNDLE_OLD_CHANGED",message:"이전 보고서의 이력이 변경되었습니다.")}
        let displaced=try await model.page(sources[1]["page_id"].string);guard displaced["source"]["origin"].string != "reference_pdf" else{throw BridgeError(code:"BUNDLE_DISPLACED_REFILLED",message:"해제된 슬라이드에 PDF가 자동으로 다시 연결되었습니다.")}
        await model.selectProject(project,snapshot:currentReport);guard model.report["bundle_decision_count"].int==3 else{throw BridgeError(code:"BUNDLE_REOPEN",message:"재조회 후 연결 이력이 다릅니다.")}
        guard let parent=NSApp.windows.first(where:{$0.isVisible && $0.contentView != nil}) else{throw BridgeError(code:"BUNDLE_HISTORY_WINDOW",message:"연결 이력 창을 표시하지 못했습니다.")}
        let finalContext=try await model.bundleContext(project:project,report:currentReport,occurrence:occurrence),activeIDs=Set(finalContext["manual_states"].array.filter{!$0["displaced"].bool}.map{$0["decision_id"].string})
        let historyWindow=NSWindow(contentRect:NSRect(x:0,y:0,width:800,height:580),styleMask:[.titled,.closable],backing:.buffered,defer:false);historyWindow.contentView=NSHostingView(rootView:BundleHistorySheet(projectID:project,reportID:currentReport,occurrence:occurrence,activeDecisionIDs:activeIDs).environmentObject(model));parent.beginSheet(historyWindow,completionHandler:{_ in});try await Task.sleep(nanoseconds:500_000_000);try captureView(historyWindow,output.appendingPathComponent("native-bundle-history.png"));parent.endSheet(historyWindow);historyWindow.orderOut(nil)
        return ["original_report_id":original,"revision_occurrence_id":occurrence,"verbatim_first_reason":reason,"native_context_contract":true,"native_sheet_cancel_no_write":true,"stale_write_rejected":true,"source_and_pdf_preview_authority":true,"displaced_source_stays_unlinked":true,"append_only_link_unlink_relink":true,"old_snapshot_unchanged":true,"reopen_history_count":3,"interaction_scope":"production model/actions and rendered native sheets; no OS mouse/keyboard input automation"]
    }
    static func exerciseImportDraft(_ model:AppModel,_ output:URL,_ files:[URL]) async throws->[String:Any] {
        guard files.count==2 else{throw BridgeError(code:"IMPORT_FIXTURE",message:"가져오기 묶음 검증 파일이 필요합니다.")}
        let analysedProject=model.projectID,analysedReport=model.report["report_id"].string
        var rows=try files.map{try ImportRow.selected($0)}
        rows[0].label="초안 원본";rows[1].label="검토 화면";let original=rows
        guard ImportRow.group(&rows,at:1),ImportRow.ungroup(&rows,at:0),rows==original,ImportRow.group(&rows,at:1) else{throw BridgeError(code:"IMPORT_ROUNDTRIP",message:"묶기·해제 후 파일 정보가 달라졌습니다.")}
        rows[0].label="통합 검토본"
        guard let parent=NSApp.windows.first(where:{$0.isVisible && $0.contentView != nil}) else{throw BridgeError(code:"IMPORT_WINDOW",message:"가져오기 창을 표시할 수 없습니다.")}
        let sheet=NSWindow(contentRect:NSRect(x:0,y:0,width:900,height:500),styleMask:[.titled,.closable],backing:.buffered,defer:false)
        sheet.contentView=NSHostingView(rootView:ImportView(initialRows:rows).environmentObject(model).background(Color(nsColor:.windowBackgroundColor)))
        parent.beginSheet(sheet,completionHandler:{_ in});try await Task.sleep(nanoseconds:500_000_000)
        do{try captureView(sheet,output.appendingPathComponent("native-import-bundle.png"))}catch{parent.endSheet(sheet);sheet.orderOut(nil);throw error}
        parent.endSheet(sheet);sheet.orderOut(nil)
        guard ImportRow.ungroup(&rows,at:0),rows.map(\.id)==original.map(\.id),rows.map(\.label)==["통합 검토본",original[1].label],ImportRow.group(&rows,at:1) else{throw BridgeError(code:"IMPORT_EDITED_LABEL",message:"묶음 이름과 파일 순서 보존 실패")}
        let count=try await model.bridge.call("projects").array.count
        let created=try await model.create(title:"묶음 가져오기 동작 검증",rows:rows)
        guard created["revisions"].array.count==1,created["revisions"].array[0]["files"].array.count==2 else{throw BridgeError(code:"IMPORT_CREATE",message:"묶은 원본 두 개를 가져오지 못했습니다.")}
        var mixed=[try ImportRow.selected(files[0]),ImportRow(label:"내부 호환 입력",urls:[files[1]])]
        guard ImportRow.group(&mixed,at:1) else{throw BridgeError(code:"IMPORT_MIXED_GROUP",message:"검증 정보가 다른 파일 묶기 실패")}
        let mixedCreated=try await model.create(title:"파일별 검증 전달 확인",rows:mixed)
        guard mixedCreated["revisions"].array[0]["files"].array.count==2 else{throw BridgeError(code:"IMPORT_MIXED_SERIALIZATION",message:"파일별 검증 정보를 전달하지 못했습니다.")}
        let changed=output.appendingPathComponent("selected-then-changed.pdf");try Data("abc".utf8).write(to:changed)
        let picked=try ImportRow.selected(changed);try Data("abd".utf8).write(to:changed)
        do{_ = try await model.create(title:"변경 파일 거부 검증",rows:[picked]);throw BridgeError(code:"IMPORT_MUTATION_ACCEPTED",message:"선택 후 변경된 파일을 허용했습니다.")}
        catch let e as BridgeError where e.code=="SOURCE_CHANGED" {}
        guard try await model.bridge.call("projects").array.count==count+2 else{throw BridgeError(code:"IMPORT_REJECT_WRITE",message:"거절한 가져오기가 프로젝트를 바꿨습니다.")}
        try await model.refresh()
        guard model.projectID==analysedProject,model.report["report_id"].string==analysedReport else{throw BridgeError(code:"IMPORT_CHANGED_SELECTION",message:"가져오기 검증이 기존 보고서 선택을 바꿨습니다.")}
        return ["mixed_nullable_identity_serialized_through_native_bridge":true,"analysed_project_and_report_unchanged":true,"group_ungroup_id_label_order_roundtrip":true,"edited_group_label_retained":true,"selected_sha_bundle_create":true,"changed_source_rejected_without_project":true,"actual_native_sheet_capture":true,"interaction_scope":"production model/actions and rendered native sheet; no OS input automation"]
    }
    static func exerciseReferenceAppearance(_ model:AppModel) async throws->[String:Any] {
        var references=0
        for revision in model.revisions {for page in model.primaryPages(revision) where !page["appearance"].isNull {
            let payload=try await model.bridge.call("page",["project_id":model.projectID,"report_id":model.report["report_id"].string,"page_id":page["page_id"].string])
            guard payload["source"]["origin"].string=="reference_pdf",payload["page"]["preview"].isNull,payload["page"]["raster"].isNull,payload["display_page"]["asset_id"].string==page["appearance"]["asset_id"].string,payload["display_page_number"].int==payload["page"]["appearance"]["page"].int else{throw BridgeError(code:"REFERENCE_SOURCE",message:"제공 PDF의 원본·페이지 근거가 일치하지 않습니다.")}
            references+=1
        }}
        guard references>0,model.revisions.count>=2 else{throw BridgeError(code:"REFERENCE_MISSING",message:"제공 PDF 대응이 없습니다.")}
        model.tab="compare";model.from=0;model.to=1;try await model.updateChanges()
        guard let visual=model.changes.first(where:{$0["kind"].string=="visual_region_changed" || $0["coverage_gaps"].array.contains(where:{$0["reason"].string=="reference_pdf_changed_without_pptx_source_change"})}) else{throw BridgeError(code:"REFERENCE_VISUAL",message:"제공 PDF의 화면 차이 근거가 없습니다.")}
        model.selectedChangeID=visual["change_id"].string;model.selectEvidence()
        guard model.primaryPages(model.revision(0)).contains(where:{$0["page_id"].string==model.leftPageID}),model.primaryPages(model.revision(1)).contains(where:{$0["page_id"].string==model.rightPageID}),visual["appearance_assessment"].string=="inferred",visual["evidence"].array.allSatisfy({$0["method"].string=="provided_pdf_native_raster"}) else{throw BridgeError(code:"REFERENCE_NAVIGATION",message:"PDF 화면 근거에서 원본 슬라이드로 이동하지 못했습니다.")}
        model.leftPageID="";model.rightPageID=""
        for evidence in visual["evidence"].array {model.navigateEvidence(evidence)}
        model.selectEvidence()
        guard model.primaryPages(model.revision(0)).contains(where:{$0["page_id"].string==model.leftPageID}),model.primaryPages(model.revision(1)).contains(where:{$0["page_id"].string==model.rightPageID}) else{throw BridgeError(code:"REFERENCE_BUTTON_NAVIGATION",message:"근거 버튼에서 원본 슬라이드로 이동하지 못했습니다.")}
        for id in [model.leftPageID,model.rightPageID]{let payload=try await model.page(id);guard payload["source"]["origin"].string=="reference_pdf" else{throw BridgeError(code:"REFERENCE_BUTTON_SOURCE",message:"근거 버튼 이동 후 PDF 화면을 열지 못했습니다.")}}
        return ["reference_pages":references,"hash_verified_pdf_source":true,"source_slide_navigation":true,"evidence_button_navigation":true,"visual_association_inferred":true,"source_unchanged_reference_difference_withheld":visual["kind"].string=="coverage_gap"]
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
    static func exerciseLayout(_ model:AppModel) async throws->[String:Any] {
        model.tab="compare";model.focus=false;model.showChanges=true;try await model.updateChanges()
        try await Task.sleep(nanoseconds:300_000_000)
        func pane(_ view:NSView)->NSSplitView? {
            if let split=view as? NSSplitView,split.identifier?.rawValue=="Docver.workspace.compare" {return split}
            for child in view.subviews {if let split=pane(child){return split}};return nil
        }
        func current()throws->NSSplitView {
            for window in NSApp.windows where window.isVisible {if let content=window.contentView,let split=pane(content){return split}}
            throw BridgeError(code:"LAYOUT_SPLIT",message:"네이티브 문서·변경 분할 창을 찾지 못했습니다.")
        }
        let split=try current(),initial=split.arrangedSubviews[1].frame.height,canvas=split.arrangedSubviews[0].frame.height
        guard abs(initial-140)<2 && canvas>initial else {throw BridgeError(code:"LAYOUT_DEFAULT",message:"문서 영역의 기본 높이가 충분하지 않습니다: \(canvas), \(initial)")}
        split.setPosition(canvas-40,ofDividerAt:0);split.layoutSubtreeIfNeeded();try await Task.sleep(nanoseconds:100_000_000)
        let resized=split.arrangedSubviews[1].frame.height
        guard resized>=initial+35 else{throw BridgeError(code:"LAYOUT_DRAG",message:"네이티브 분할선으로 변경 목록 크기를 바꾸지 못했습니다.")}
        model.showChanges=false;try await Task.sleep(nanoseconds:150_000_000);model.showChanges=true;try await Task.sleep(nanoseconds:250_000_000)
        let reopened=try current(),remembered=reopened.arrangedSubviews[1].frame.height
        guard abs(remembered-resized)<2 else{throw BridgeError(code:"LAYOUT_MEMORY",message:"변경 목록 높이 유지 실패: 조절 \(resized), 다시 열기 \(remembered), 저장 \(WorkspaceGeometryPreferences.height("Docver.workspace.compare.changesHeight") ?? -1)")}
        reopened.setPosition(reopened.bounds.height-reopened.dividerThickness-initial,ofDividerAt:0)
        return ["default_change_pane_points":initial,"default_document_pane_points":canvas,"resized_change_pane_points":resized,"reopened_change_pane_points":remembered,"native_divider_and_height_reopen":true,"existing_snapshot_reopen":!model.report.isNull]
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
